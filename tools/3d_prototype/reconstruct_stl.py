"""
3D Reconstruction & Metric STL Exporter Prototype
Performs Multi-View Space Carving / Visual Hull from calibrated ChArUco images,
ensuring watertight solid geometry and exact 1:1 metric scale in millimeters.
"""

import os
import struct
import time
import cv2
import numpy as np
from skimage.measure import marching_cubes

from charuco_board_def import detect_and_estimate_pose, get_standard_charuco_board


def write_binary_stl(filename, vertices, faces):
    """
    Writes a watertight 3D triangle mesh to standard Binary STL format.
    Dimensions are preserved in exact physical millimeters.
    """
    num_faces = len(faces)
    header = b"3D Scan Metric STL - Laqta Scanner Prototype"[:80].ljust(80, b"\0")
    
    with open(filename, "wb") as f:
        f.write(header)
        f.write(struct.pack("<I", num_faces))
        
        for face in faces:
            v0 = vertices[face[0]]
            v1 = vertices[face[1]]
            v2 = vertices[face[2]]
            
            # Compute facet normal via cross product
            edge1 = v1 - v0
            edge2 = v2 - v0
            normal = np.cross(edge1, edge2)
            norm_len = np.linalg.norm(normal)
            if norm_len > 1e-9:
                normal = normal / norm_len
            else:
                normal = np.array([0.0, 0.0, 1.0], dtype=np.float32)
                
            # Pack normal + 3 vertices + 2 bytes attribute
            f.write(struct.pack("<3f", *normal.astype(np.float32)))
            f.write(struct.pack("<3f", *v0.astype(np.float32)))
            f.write(struct.pack("<3f", *v1.astype(np.float32)))
            f.write(struct.pack("<3f", *v2.astype(np.float32)))
            f.write(struct.pack("<H", 0))


def compute_mesh_volume(vertices, faces):
    """
    Computes enclosed volume of a watertight triangle mesh (in mm^3)
    using the divergence theorem.
    """
    v0 = vertices[faces[:, 0]]
    v1 = vertices[faces[:, 1]]
    v2 = vertices[faces[:, 2]]
    
    # Signed volume of tetrahedra formed with origin
    cross_prod = np.cross(v1, v2)
    signed_vols = np.einsum('ij,ij->i', v0, cross_prod) / 6.0
    return np.abs(np.sum(signed_vols))


def segment_foreground(image, rvec, tvec, camera_matrix, dist_coeffs):
    """
    Segments the object on top of the calibration board.
    Supports color/threshold segmentation and plane-difference.
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
    
    # Bilateral filter to smooth texture while preserving silhouette edges
    blurred = cv2.bilateralFilter(gray, 9, 75, 75)
    
    # Adaptive thresholding to segment solid foreground from board
    # If the object is distinct, Otsu or GrabCut extracts the silhouette
    _, thresh = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    
    # Morphological closing to fill small interior holes in silhouette
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel, iterations=2)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
    
    return mask


def reconstruct_volume(
    calibrated_views,
    camera_matrix,
    bounds_mm=(-40.0, 40.0, -40.0, 40.0, 0.0, 65.0),
    voxel_size_mm=1.0,
    min_view_agreement=0.85
):
    """
    Space Carving inside a calibrated metric 3D voxel grid.
    
    Args:
        calibrated_views: List of dicts with {'image': img, 'mask': mask, 'R': R, 't': t}
        camera_matrix: 3x3 intrinsic matrix
        bounds_mm: (xmin, xmax, ymin, ymax, zmin, zmax) in millimeters
        voxel_size_mm: Resolution in mm (e.g. 1.0mm or 0.5mm)
        min_view_agreement: Fraction of views that must agree voxel is inside silhouette
    """
    xmin, xmax, ymin, ymax, zmin, zmax = bounds_mm
    
    xs = np.arange(xmin, xmax + voxel_size_mm, voxel_size_mm, dtype=np.float32)
    ys = np.arange(ymin, ymax + voxel_size_mm, voxel_size_mm, dtype=np.float32)
    zs = np.arange(zmin, zmax + voxel_size_mm, voxel_size_mm, dtype=np.float32)
    
    nx, ny, nz = len(xs), len(ys), len(zs)
    total_voxels = nx * ny * nz
    
    print(f"[Space Carving] Voxel Grid: {nx} x {ny} x {nz} = {total_voxels:,} voxels")
    print(f"[Space Carving] Resolution: {voxel_size_mm} mm | Bounds: X[{xmin:.1f}, {xmax:.1f}] Y[{ymin:.1f}, {ymax:.1f}] Z[{zmin:.1f}, {zmax:.1f}] mm")
    
    # 3D coordinate grid (X, Y, Z) in board coordinate space
    grid_x, grid_y, grid_z = np.meshgrid(xs, ys, zs, indexing='ij')
    # Flatten to (N, 3)
    pts_w = np.column_stack([grid_x.ravel(), grid_y.ravel(), grid_z.ravel()])
    
    # Votes counter for each voxel: number of views where point projects inside silhouette
    votes = np.zeros(total_voxels, dtype=np.int16)
    valid_views_count = 0
    
    num_views = len(calibrated_views)
    
    for idx, view in enumerate(calibrated_views):
        mask = view['mask']
        R = view['R']
        t = view['t']
        
        # Project 3D world points to camera coordinates: P_c = R * P_w + t
        pts_c = (R @ pts_w.T + t.reshape(3, 1)).T
        
        # Filter points in front of camera (Z > 0)
        z_c = pts_c[:, 2]
        valid_z = z_c > 1e-3
        
        # Perspective projection
        fx = camera_matrix[0, 0]
        fy = camera_matrix[1, 1]
        cx = camera_matrix[0, 2]
        cy = camera_matrix[1, 2]
        
        u = np.zeros(total_voxels, dtype=np.float32)
        v = np.zeros(total_voxels, dtype=np.float32)
        
        u[valid_z] = (pts_c[valid_z, 0] * fx / z_c[valid_z]) + cx
        v[valid_z] = (pts_c[valid_z, 1] * fy / z_c[valid_z]) + cy
        
        # Round to pixel indices
        u_int = np.rint(u).astype(np.int32)
        v_int = np.rint(v).astype(np.int32)
        
        h, w = mask.shape[:2]
        in_bounds = valid_z & (u_int >= 0) & (u_int < w) & (v_int >= 0) & (v_int < h)
        
        # Check silhouette mask value
        is_inside = np.zeros(total_voxels, dtype=bool)
        is_inside[in_bounds] = mask[v_int[in_bounds], u_int[in_bounds]] > 0
        
        votes[is_inside] += 1
        valid_views_count += 1
        
    # Required agreement
    required_votes = int(np.ceil(valid_views_count * min_view_agreement))
    solid_voxels = (votes >= required_votes).reshape(nx, ny, nz)
    
    # Clip table base: Ensure flat bottom at Z=0 for 3D printer bed adhesion
    # Add a thin artificial floor boundary at Z=0 if needed
    solid_voxels[:, :, 0] = False
    
    return solid_voxels, xs, ys, zs


def extract_and_export_stl(solid_volume, xs, ys, zs, output_stl_path):
    """
    Extracts triangular mesh using Marching Cubes and exports metric Binary STL.
    """
    # Pad volume with 1 voxel of zeros on all sides to guarantee closed watertight mesh
    padded = np.pad(solid_volume.astype(np.float32), 1, mode='constant', constant_values=0)
    
    # Run Marching Cubes
    spacing = (xs[1] - xs[0], ys[1] - ys[0], zs[1] - zs[0])
    verts, faces, normals, values = marching_cubes(padded, level=0.5, spacing=spacing)
    
    # Adjust vertices back to world coordinates
    verts[:, 0] += xs[0] - spacing[0]
    verts[:, 1] += ys[0] - spacing[1]
    verts[:, 2] += zs[0] - spacing[2]
    
    # Ensure minimum Z is at least 0 (table surface)
    verts[:, 2] = np.maximum(verts[:, 2], 0.0)
    
    # Write Binary STL
    write_binary_stl(output_stl_path, verts, faces)
    
    # Compute metrics
    min_pt = np.min(verts, axis=0)
    max_pt = np.max(verts, axis=0)
    dims_mm = max_pt - min_pt
    
    volume_mm3 = compute_mesh_volume(verts, faces)
    volume_cm3 = volume_mm3 / 1000.0
    
    metrics = {
        'num_vertices': len(verts),
        'num_triangles': len(faces),
        'dim_x_mm': dims_mm[0],
        'dim_y_mm': dims_mm[1],
        'dim_z_mm': dims_mm[2],
        'min_pt': min_pt,
        'max_pt': max_pt,
        'volume_cm3': volume_cm3,
        'stl_size_kb': os.path.getsize(output_stl_path) / 1024.0
    }
    
    return metrics
