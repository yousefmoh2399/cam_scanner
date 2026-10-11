"""
Comprehensive 3D Reconstruction Experiment Runner & Diagnostic Benchmark
Executes the 4 controlled experiments:
  Exp 1: Baseline (Original 3 rings, generator mask)
  Exp 2: Real Image-Derived Segmentation Mask (Extracted from image with ChArUco background)
  Exp 3: Geometric Coverage Optimization (Added 5 deg Eye-Level and 85 deg Top-Down rings)
  Exp 4: Hull + Planar Face Fitting Regularization
"""

import os
import sys
import time
import cv2
import numpy as np
from skimage.measure import marching_cubes

sys.path.insert(0, os.path.dirname(__file__))

from charuco_board_def import get_standard_charuco_board
from synthetic_test_generator import create_cube_mesh
from reconstruct_stl import reconstruct_volume, extract_and_export_stl, write_binary_stl, compute_mesh_volume


def extract_real_mask_from_image(img):
    """
    Extracts the foreground object silhouette directly from the captured image
    where the object sits on the ChArUco calibration board.
    Does NOT use the generator's polygon mask!
    Uses color-saturation difference and edge morphological refinement.
    """
    # The ChArUco board is pure neutral grayscale (B=G=R).
    # The physical object has color/saturation or texture difference.
    diff_b_r = np.abs(img[:, :, 0].astype(np.int16) - img[:, :, 2].astype(np.int16))
    diff_b_g = np.abs(img[:, :, 0].astype(np.int16) - img[:, :, 1].astype(np.int16))
    diff_total = diff_b_r + diff_b_g
    
    # Threshold color difference
    _, thresh = cv2.threshold(diff_total.astype(np.uint8), 6, 255, cv2.THRESH_BINARY)
    
    # Clean noise with morphological operations
    kernel_close = cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7))
    kernel_open = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
    
    mask = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel_close, iterations=2)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel_open, iterations=1)
    
    return mask


def fit_planar_faces_and_regularize(vertices, faces):
    """
    Planar Face Fitting (Hull + Planar Regularization):
    Groups surface vertices by normal orientation, fits dominant planes via median inliers,
    and calculates calibrated planar dimensions.
    """
    # Compute per-face normals
    v0 = vertices[faces[:, 0]]
    v1 = vertices[faces[:, 1]]
    v2 = vertices[faces[:, 2]]
    face_normals = np.cross(v1 - v0, v2 - v0)
    norm_lens = np.linalg.norm(face_normals, axis=1, keepdims=True)
    norm_lens[norm_lens == 0] = 1.0
    face_normals = face_normals / norm_lens
    
    # Vertex normals by averaging adjacent face normals
    vert_normals = np.zeros_like(vertices)
    for i in range(3):
        np.add.at(vert_normals, faces[:, i], face_normals)
    vert_norm_lens = np.linalg.norm(vert_normals, axis=1, keepdims=True)
    vert_norm_lens[vert_norm_lens == 0] = 1.0
    vert_normals = vert_normals / vert_norm_lens
    
    # Marching cubes normals point inward (towards higher values 1.0)
    # So invert normals to point outward into the world:
    vert_normals = -vert_normals
    nx, ny, nz = vert_normals[:, 0], vert_normals[:, 1], vert_normals[:, 2]
    
    # Identify inlier points for each orthogonal face
    # Right (+X) and Left (-X)
    right_mask = nx > 0.60
    left_mask = nx < -0.60
    
    # Back (+Y) and Front (-Y)
    back_mask = ny > 0.60
    front_mask = ny < -0.60
    
    # Top (+Z)
    top_mask = nz > 0.60
    
    x_right = np.median(vertices[right_mask, 0]) if right_mask.sum() > 20 else np.max(vertices[:, 0])
    x_left = np.median(vertices[left_mask, 0]) if left_mask.sum() > 20 else np.min(vertices[:, 0])
    
    y_back = np.median(vertices[back_mask, 1]) if back_mask.sum() > 20 else np.max(vertices[:, 1])
    y_front = np.median(vertices[front_mask, 1]) if front_mask.sum() > 20 else np.min(vertices[:, 1])
    
    z_top = np.median(vertices[top_mask, 2]) if top_mask.sum() > 20 else np.max(vertices[:, 2])
    z_bottom = 0.0  # Board plane is physically fixed at Z=0
    
    dim_x = abs(x_right - x_left)
    dim_y = abs(y_back - y_front)
    dim_z = abs(z_top - z_bottom)
    
    return {
        'dim_x_mm': dim_x,
        'dim_y_mm': dim_y,
        'dim_z_mm': dim_z,
        'x_bounds': (x_left, x_right),
        'y_bounds': (y_front, y_back),
        'z_bounds': (z_bottom, z_top)
    }


def generate_custom_dataset(elevations, views_per_ring, output_dir, radius_mm=380.0):
    """
    Renders calibrated views for specified elevation rings.
    """
    os.makedirs(output_dir, exist_ok=True)
    
    img_w, img_h = 1920, 1080
    camera_matrix = np.array([[1600.0, 0, 960.0], [0, 1600.0, 540.0], [0, 0, 1]], dtype=np.float32)
    dist_coeffs = np.zeros((5, 1), dtype=np.float32)
    
    board, _ = get_standard_charuco_board()
    board_w_px = 2100
    board_h_px = 1500
    if hasattr(board, 'generateImage'):
        board_tex = board.generateImage((board_w_px, board_h_px), marginSize=0, borderBits=1)
    else:
        board_tex = board.draw((board_w_px, board_h_px), marginSize=0, borderBits=1)
        
    cube_verts, cube_faces = create_cube_mesh()
    board_center = np.array([105.0, 75.0, 25.0], dtype=np.float32)
    
    views_info = []
    view_count = 0
    
    for elev_deg in elevations:
        elev_rad = np.radians(elev_deg)
        for i in range(views_per_ring):
            azim_deg = (360.0 / views_per_ring) * i
            azim_rad = np.radians(azim_deg)
            
            rel_x = radius_mm * np.cos(elev_rad) * np.cos(azim_rad)
            rel_y = radius_mm * np.cos(elev_rad) * np.sin(azim_rad)
            rel_z = radius_mm * np.sin(elev_rad)
            cam_pos = board_center + np.array([rel_x, rel_y, rel_z], dtype=np.float32)
            
            forward = board_center - cam_pos
            forward = forward / np.linalg.norm(forward)
            
            up = np.array([0.0, 0.0, 1.0], dtype=np.float32)
            right = np.cross(forward, up)
            if np.linalg.norm(right) < 1e-4:
                right = np.array([1.0, 0.0, 0.0], dtype=np.float32)
            right = right / np.linalg.norm(right)
            cam_up = np.cross(right, forward)
            
            R_wc = np.vstack([right, -cam_up, forward])
            t_wc = -R_wc @ cam_pos
            
            rvec, _ = cv2.Rodrigues(R_wc)
            tvec = t_wc.reshape(3, 1)
            
            frame = np.full((img_h, img_w, 3), 240, dtype=np.uint8)
            
            # Project board
            board_world_pts = np.array([
                [  0.0,   0.0, 0.0],
                [210.0,   0.0, 0.0],
                [210.0, 150.0, 0.0],
                [  0.0, 150.0, 0.0],
            ], dtype=np.float32)
            proj_board_pts, _ = cv2.projectPoints(board_world_pts, rvec, tvec, camera_matrix, dist_coeffs)
            proj_board_pts = proj_board_pts.reshape(-1, 2).astype(np.float32)
            
            src_board_pts = np.array([
                [0, 0],
                [board_w_px - 1, 0],
                [board_w_px - 1, board_h_px - 1],
                [0, board_h_px - 1]
            ], dtype=np.float32)
            
            H_board = cv2.getPerspectiveTransform(src_board_pts, proj_board_pts)
            warped_board = cv2.warpPerspective(board_tex, H_board, (img_w, img_h), borderValue=240)
            board_mask = cv2.warpPerspective(np.full((board_h_px, board_w_px), 255, dtype=np.uint8), H_board, (img_w, img_h), flags=cv2.INTER_NEAREST)
            frame[board_mask > 0] = cv2.cvtColor(warped_board, cv2.COLOR_GRAY2BGR)[board_mask > 0]
            
            # Project cube
            cube_proj, _ = cv2.projectPoints(cube_verts, rvec, tvec, camera_matrix, dist_coeffs)
            cube_proj = cube_proj.reshape(-1, 2)
            
            face_depths = []
            for face in cube_faces:
                f_center_c = (R_wc @ np.mean(cube_verts[face], axis=0) + t_wc)[2]
                face_depths.append((f_center_c, face))
            face_depths.sort(key=lambda x: x[0], reverse=True)
            
            poly_mask = np.zeros((img_h, img_w), dtype=np.uint8)
            light_dir = np.array([0.4, 0.4, 0.8], dtype=np.float32)
            light_dir = light_dir / np.linalg.norm(light_dir)
            
            for depth, face in face_depths:
                pts_2d = cube_proj[face].astype(np.int32)
                v0, v1, v2 = cube_verts[face[0]], cube_verts[face[1]], cube_verts[face[2]]
                fnorm = np.cross(v1 - v0, v2 - v0)
                fnorm = fnorm / (np.linalg.norm(fnorm) + 1e-6)
                
                v_center = np.mean(cube_verts[face], axis=0)
                view_vec = cam_pos - v_center
                view_vec = view_vec / np.linalg.norm(view_vec)
                if np.dot(fnorm, view_vec) <= 0:
                    continue
                    
                diffuse = max(0.3, float(np.dot(fnorm, light_dir)))
                shade = int(40 + diffuse * 170)
                color = (shade, int(shade * 0.92), int(shade * 0.88))
                
                cv2.fillPoly(frame, [pts_2d], color)
                cv2.fillPoly(poly_mask, [pts_2d], 255)
                cv2.polylines(frame, [pts_2d], True, (15, 15, 15), 1)
                
            img_path = os.path.join(output_dir, f"view_{view_count:02d}.png")
            mask_path = os.path.join(output_dir, f"poly_mask_{view_count:02d}.png")
            cv2.imwrite(img_path, frame)
            cv2.imwrite(mask_path, poly_mask)
            
            views_info.append({
                'image': frame,
                'poly_mask': poly_mask,
                'R': R_wc,
                't': t_wc
            })
            view_count += 1
            
    return views_info, camera_matrix


def run_experiment(exp_name, views, camera_matrix, use_real_segmentation=False, apply_planar_fitting=False, min_agreement=1.0):
    t_start = time.time()
    calibrated_views = []
    
    for v in views:
        if use_real_segmentation:
            mask = extract_real_mask_from_image(v['image'])
        else:
            mask = v['poly_mask']
            
        calibrated_views.append({
            'mask': mask,
            'R': v['R'],
            't': v['t']
        })
        
    bounds_mm = (70.0, 140.0, 40.0, 110.0, 0.0, 60.0)
    voxel_size_mm = 0.8
    
    solid_voxels, xs, ys, zs = reconstruct_volume(
        calibrated_views,
        camera_matrix,
        bounds_mm=bounds_mm,
        voxel_size_mm=voxel_size_mm,
        min_view_agreement=min_agreement
    )
    
    # Marching cubes
    padded = np.pad(solid_volume_fix(solid_voxels).astype(np.float32), 1, mode='constant', constant_values=0)
    spacing = (xs[1] - xs[0], ys[1] - ys[0], zs[1] - zs[0])
    verts, faces, normals, _ = marching_cubes(padded, level=0.5, spacing=spacing)
    verts[:, 0] += xs[0] - spacing[0]
    verts[:, 1] += ys[0] - spacing[1]
    verts[:, 2] += zs[0] - spacing[2]
    verts[:, 2] = np.maximum(verts[:, 2], 0.0)
    
    min_pt = np.min(verts, axis=0)
    max_pt = np.max(verts, axis=0)
    raw_dims = max_pt - min_pt
    
    if apply_planar_fitting:
        fit_results = fit_planar_faces_and_regularize(verts, faces)
        dim_x = fit_results['dim_x_mm']
        dim_y = fit_results['dim_y_mm']
        dim_z = fit_results['dim_z_mm']
    else:
        dim_x = raw_dims[0]
        dim_y = raw_dims[1]
        dim_z = raw_dims[2]
        
    elapsed = time.time() - t_start
    
    err_x = abs(dim_x - 50.00)
    err_y = abs(dim_y - 50.00)
    err_z = abs(dim_z - 50.00)
    mae = (err_x + err_y + err_z) / 3.0
    max_err = max(err_x, err_y, err_z)
    
    return {
        'exp_name': exp_name,
        'dim_x': dim_x,
        'dim_y': dim_y,
        'dim_z': dim_z,
        'err_x': err_x,
        'err_y': err_y,
        'err_z': err_z,
        'mae': mae,
        'max_err': max_err,
        'triangles': len(faces),
        'time_s': elapsed
    }


def solid_volume_fix(solid):
    vol = solid.copy()
    vol[:, :, 0] = False
    return vol


def main():
    print("=========================================================================================")
    print(" RUNNING CONTROLLED EXPERIMENTS TO ISOLATE AND PROVE RECONSTRUCTION ERROR CAUSES")
    print("=========================================================================================")
    
    # Dataset A: Original 3 rings (25°, 48°, 72°) - 48 views
    views_orig, K = generate_custom_dataset([25.0, 48.0, 72.0], 16, "tools/3d_prototype/exp_dataset_orig")
    
    # Dataset B: 4 rings including 5° Eye-Level and 85° Top-Down - 64 views
    views_opt, _ = generate_custom_dataset([5.0, 35.0, 60.0, 85.0], 16, "tools/3d_prototype/exp_dataset_opt")
    
    results = []
    
    # Exp 1: Baseline (3 rings, generator polygon mask, agreement=0.92)
    print("\n[Running Exp 1] Baseline (3 rings: 25°, 48°, 72°, Generator Polygon Mask, 92% agreement)...")
    res1 = run_experiment("1. Baseline (3 rings, Polygon Mask, 92% agree)", views_orig, K, use_real_segmentation=False, apply_planar_fitting=False, min_agreement=0.92)
    results.append(res1)
    
    # Exp 2: Real Image Segmentation (3 rings, extracted directly from image, agreement=0.92)
    print("[Running Exp 2] Real Image-Derived Mask (Extracted from image colors & ChArUco bg)...")
    res2 = run_experiment("2. Real Image-Derived Mask (3 rings, 92% agree)", views_orig, K, use_real_segmentation=True, apply_planar_fitting=False, min_agreement=0.92)
    results.append(res2)
    
    # Exp 3: Geometric Coverage Optimization (4 rings: 5° Eye-level, 35°, 60°, 85° Top-down, 100% agreement)
    print("[Running Exp 3] Geometric Coverage (4 rings: 5° Eye-Level + 85° Top-Down, 100% agreement)...")
    res3 = run_experiment("3. Geometric Rings (5° Eye-level + 85° Top-down)", views_opt, K, use_real_segmentation=False, apply_planar_fitting=False, min_agreement=1.0)
    results.append(res3)
    
    # Exp 4: Hull + Planar Face Fitting Regularization
    print("[Running Exp 4] Hull + Planar Face Fitting Regularization on Opt dataset...")
    res4 = run_experiment("4. Hull + Planar Fitting Regularization", views_opt, K, use_real_segmentation=False, apply_planar_fitting=True, min_agreement=1.0)
    results.append(res4)
    
    # Print formatted comparative table
    print("\n" + "=" * 105)
    print(" EXPERIMENT COMPARISON TABLE (Ground Truth: 50.00 x 50.00 x 50.00 mm Cube)")
    print("=" * 105)
    print(f"{'Experiment':<46} | {'Dim X (mm)':<10} | {'Dim Y (mm)':<10} | {'Dim Z (mm)':<10} | {'MAE (mm)':<9} | {'Max Err':<8} | {'Time (s)':<8}")
    print("-" * 105)
    for r in results:
        print(f"{r['exp_name']:<46} | {r['dim_x']:>7.2f}    | {r['dim_y']:>7.2f}    | {r['dim_z']:>7.2f}    | {r['mae']:>6.2f}    | {r['max_err']:>5.2f}    | {r['time_s']:>5.2f}")
    print("=" * 105 + "\n")


if __name__ == "__main__":
    main()
