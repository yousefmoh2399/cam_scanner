"""
Synthetic Benchmark Generator for 50.0 mm Calibration Cube
Simulates an exact physical 50.0 mm calibration cube sitting at the center of a ChArUco board,
with camera poses across 3 multi-view orbit rings (24 views).
"""

import os
import cv2
import cv2.aruco as aruco
import numpy as np

from charuco_board_def import get_standard_charuco_board


def create_cube_mesh():
    """
    Returns 8 vertices and 12 triangular facets of a 50.0 x 50.0 x 50.0 mm cube.
    Bottom sits at Z=0, centered at board center (X=105.0, Y=75.0).
    """
    cx, cy = 105.0, 75.0
    half = 25.0  # 50 mm total width
    h = 50.0     # 50 mm total height
    
    vertices = np.array([
        [cx - half, cy - half, 0.0],
        [cx + half, cy - half, 0.0],
        [cx + half, cy + half, 0.0],
        [cx - half, cy + half, 0.0],
        [cx - half, cy - half,   h],
        [cx + half, cy - half,   h],
        [cx + half, cy + half,   h],
        [cx - half, cy + half,   h],
    ], dtype=np.float32)
    
    # 6 faces * 2 triangles = 12 triangles
    faces = [
        # Bottom (Z=0)
        [0, 1, 2], [0, 2, 3],
        # Top (Z=50)
        [4, 6, 5], [4, 7, 6],
        # Front (Y=cy-25)
        [0, 5, 1], [0, 4, 5],
        # Right (X=cx+25)
        [1, 6, 2], [1, 5, 6],
        # Back (Y=cy+25)
        [2, 7, 3], [2, 6, 7],
        # Left (X=cx-25)
        [3, 4, 0], [3, 7, 4],
    ]
    return vertices, np.array(faces, dtype=np.int32)


def generate_benchmark_dataset(
    output_dir="tools/3d_prototype/dataset_50mm_cube",
    num_rings=3,
    views_per_ring=8,
    radius_mm=380.0
):
    """
    Generates 24 multi-view 1920x1080 images of a 50mm calibration cube.
    """
    os.makedirs(output_dir, exist_ok=True)
    
    # Camera parameters (simulating typical mobile sensor)
    img_w, img_h = 1920, 1080
    fx, fy = 1600.0, 1600.0
    cx, cy = 960.0, 540.0
    camera_matrix = np.array([
        [fx,  0, cx],
        [ 0, fy, cy],
        [ 0,  0,  1]
    ], dtype=np.float32)
    dist_coeffs = np.zeros((5, 1), dtype=np.float32)
    
    # Render ChArUco board texture at high resolution
    board, _ = get_standard_charuco_board()
    board_w_px = 2100
    board_h_px = 1500
    if hasattr(board, 'generateImage'):
        board_tex = board.generateImage((board_w_px, board_h_px), marginSize=0, borderBits=1)
    else:
        board_tex = board.draw((board_w_px, board_h_px), marginSize=0, borderBits=1)
        
    cube_verts, cube_faces = create_cube_mesh()
    board_center = np.array([105.0, 75.0, 25.0], dtype=np.float32)
    
    elevations = [25.0, 48.0, 72.0]  # Degrees
    views_info = []
    
    view_count = 0
    for elev_deg in elevations:
        elev_rad = np.radians(elev_deg)
        for i in range(views_per_ring):
            azim_deg = (360.0 / views_per_ring) * i
            azim_rad = np.radians(azim_deg)
            
            # Camera position relative to board center
            rel_x = radius_mm * np.cos(elev_rad) * np.cos(azim_rad)
            rel_y = radius_mm * np.cos(elev_rad) * np.sin(azim_rad)
            rel_z = radius_mm * np.sin(elev_rad)
            cam_pos = board_center + np.array([rel_x, rel_y, rel_z], dtype=np.float32)
            
            # Camera looks at target point (cube center: [105, 75, 25])
            forward = board_center - cam_pos
            forward = forward / np.linalg.norm(forward)
            
            # World up vector
            up = np.array([0.0, 0.0, 1.0], dtype=np.float32)
            right = np.cross(forward, up)
            if np.linalg.norm(right) < 1e-4:
                right = np.array([1.0, 0.0, 0.0], dtype=np.float32)
            right = right / np.linalg.norm(right)
            cam_up = np.cross(right, forward)
            
            # Camera rotation matrix: world to camera
            R_wc = np.vstack([right, -cam_up, forward])
            t_wc = -R_wc @ cam_pos
            
            rvec, _ = cv2.Rodrigues(R_wc)
            tvec = t_wc.reshape(3, 1)
            
            # Render empty scene with neutral table background
            frame = np.full((img_h, img_w, 3), 240, dtype=np.uint8)
            
            # 1. Project ChArUco board on plane Z=0 (origin [0, 0, 0] to [210, 150, 0] mm)
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
            warped_board = cv2.warpPerspective(board_tex, H_board, (img_w, img_h), flags=cv2.INTER_LINEAR, borderValue=240)
            
            # Composite board onto frame
            board_mask = cv2.warpPerspective(np.full((board_h_px, board_w_px), 255, dtype=np.uint8), H_board, (img_w, img_h), flags=cv2.INTER_NEAREST)
            frame[board_mask > 0] = cv2.cvtColor(warped_board, cv2.COLOR_GRAY2BGR)[board_mask > 0]
            
            # 2. Render 50.0 mm cube with shading and occlusion
            cube_proj, _ = cv2.projectPoints(cube_verts, rvec, tvec, camera_matrix, dist_coeffs)
            cube_proj = cube_proj.reshape(-1, 2)
            
            face_depths = []
            for face in cube_faces:
                f_pts_3d = cube_verts[face]
                f_center_c = (R_wc @ np.mean(f_pts_3d, axis=0) + t_wc)[2]
                face_depths.append((f_center_c, face))
            face_depths.sort(key=lambda x: x[0], reverse=True)
            
            cube_mask = np.zeros((img_h, img_w), dtype=np.uint8)
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
                    continue  # Back-face culled
                    
                diffuse = max(0.3, float(np.dot(fnorm, light_dir)))
                shade = int(40 + diffuse * 170)
                color = (shade, int(shade * 0.92), int(shade * 0.88))
                
                cv2.fillPoly(frame, [pts_2d], color)
                cv2.fillPoly(cube_mask, [pts_2d], 255)
                cv2.polylines(frame, [pts_2d], True, (15, 15, 15), 1)
                
            img_filename = f"view_{view_count:02d}_elev{int(elev_deg)}_azim{int(azim_deg)}.png"
            mask_filename = f"mask_{view_count:02d}.png"
            
            img_path = os.path.join(output_dir, img_filename)
            mask_path = os.path.join(output_dir, mask_filename)
            
            cv2.imwrite(img_path, frame)
            cv2.imwrite(mask_path, cube_mask)
            
            views_info.append({
                'img_path': img_path,
                'mask_path': mask_path,
                'R': R_wc,
                't': t_wc,
                'rvec': rvec,
                'tvec': tvec,
                'elev_deg': elev_deg,
                'azim_deg': azim_deg
            })
            view_count += 1
            
    print(f"[Benchmark Dataset] Successfully generated {len(views_info)} calibrated views in '{output_dir}'.")
    return views_info, camera_matrix, dist_coeffs
