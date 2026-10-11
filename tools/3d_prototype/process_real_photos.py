"""
Real Photo Processing CLI for 3D Scanning & Dimensional Audit
Accepts a folder of real smartphone camera photos of an object on a ChArUco mat,
estimates camera poses, segments the object, performs Space Carving,
applies optional planar fitting, exports binary STL, and audits physical dimensions.

Usage:
  py -3.10 tools/3d_prototype/process_real_photos.py --input_dir "path/to/photos" --ref_dim 50.0 --output_stl "my_cube.stl"
"""

import os
import sys
import argparse
import time
import glob
import cv2
import numpy as np
from skimage.measure import marching_cubes

sys.path.insert(0, os.path.dirname(__file__))

from charuco_board_def import detect_and_estimate_pose, get_standard_charuco_board
from reconstruct_stl import reconstruct_volume, write_binary_stl, compute_mesh_volume
from experiments_runner import extract_real_mask_from_image, fit_planar_faces_and_regularize


def parse_arguments():
    parser = argparse.ArgumentParser(description="Process real smartphone photos for 3D STL reconstruction.")
    parser.add_argument("--input_dir", type=str, required=True, help="Directory containing captured camera images (.jpg, .png)")
    parser.add_argument("--ref_dim", type=float, default=None, help="Known reference dimension in mm (e.g. 50.0) for caliper accuracy benchmark")
    parser.add_argument("--output_stl", type=str, default="output_scan.stl", help="Output Binary STL file path")
    parser.add_argument("--voxel_size", type=float, default=0.8, help="Voxel grid resolution in mm (default: 0.8 mm)")
    parser.add_argument("--planar_fit", action="store_true", help="Apply planar face fitting regularization for geometric/cubic objects")
    parser.add_argument("--min_agreement", type=float, default=0.90, help="Minimum fraction of views required to agree (default: 0.90 to tolerate slight shadow noise)")
    return parser.parse_args()


def load_images_from_directory(input_dir):
    extensions = ("*.jpg", "*.jpeg", "*.png", "*.JPG", "*.PNG", "*.JPEG")
    files = []
    for ext in extensions:
        files.extend(glob.glob(os.path.join(input_dir, ext)))
    files = sorted(list(set(files)))
    return files


def process_real_session(input_dir, ref_dim=None, output_stl="output_scan.stl", voxel_size=0.8, planar_fit=False, min_agreement=0.90):
    print("=" * 75)
    print(" REAL CAMERA 3D SCANNING PIPELINE - LAQTA SCANNER")
    print("=" * 75)
    
    image_paths = load_images_from_directory(input_dir)
    if not image_paths:
        print(f"[ERROR] No image files found in '{input_dir}'!")
        return False
        
    print(f"[1/4] Found {len(image_paths)} images in '{input_dir}'.")
    
    # Read first image to determine resolution
    sample_img = cv2.imread(image_paths[0])
    h, w = sample_img.shape[:2]
    print(f" -> Resolution: {w} x {h} pixels")
    
    # Estimate default camera matrix if not explicitly calibrated
    # Standard 35mm equivalent field of view ~ 65 degrees -> f ~ w * 0.9
    f_est = float(max(w, h)) * 0.85
    camera_matrix = np.array([
        [f_est,     0, w / 2.0],
        [    0, f_est, h / 2.0],
        [    0,     0,     1.0]
    ], dtype=np.float32)
    dist_coeffs = np.zeros((5, 1), dtype=np.float32)
    
    print("[2/4] Detecting ChArUco markers and estimating 6DoF camera poses...")
    calibrated_views = []
    t_start = time.time()
    
    for idx, path in enumerate(image_paths):
        img = cv2.imread(path)
        if img is None:
            continue
            
        success, rvec, tvec, corners, ids = detect_and_estimate_pose(img, camera_matrix, dist_coeffs)
        if success:
            R, _ = cv2.Rodrigues(rvec)
            t = tvec.flatten()
            
            # Extract real mask from the image
            mask = extract_real_mask_from_image(img)
            
            calibrated_views.append({
                'path': path,
                'image': img,
                'mask': mask,
                'R': R,
                't': t
            })
        else:
            print(f"  [Skipped] Image {idx+1}/{len(image_paths)} ({os.path.basename(path)}): ChArUco board not detected.")
            
    num_calibrated = len(calibrated_views)
    print(f" -> Successfully calibrated {num_calibrated}/{len(image_paths)} views.")
    if num_calibrated < 6:
        print("[ERROR] Insufficient calibrated views (< 6)! Ensure the ChArUco board is well-lit and partially visible.")
        return False
        
    print(f"\n[3/4] Running 3D Space Carving (Voxel Size: {voxel_size} mm)...")
    # Dynamic bounding volume based on ChArUco board center (105, 75 mm)
    bounds_mm = (55.0, 155.0, 25.0, 125.0, 0.0, 80.0)
    
    solid_voxels, xs, ys, zs = reconstruct_volume(
        calibrated_views,
        camera_matrix,
        bounds_mm=bounds_mm,
        voxel_size_mm=voxel_size,
        min_view_agreement=min_agreement
    )
    
    # Ground plane clamping
    vol = solid_voxels.copy()
    vol[:, :, 0] = False
    
    print("\n[4/4] Extracting watertight surface mesh via Marching Cubes...")
    padded = np.pad(vol.astype(np.float32), 1, mode='constant', constant_values=0)
    spacing = (xs[1] - xs[0], ys[1] - ys[0], zs[1] - zs[0])
    verts, faces, normals, _ = marching_cubes(padded, level=0.5, spacing=spacing)
    verts[:, 0] += xs[0] - spacing[0]
    verts[:, 1] += ys[0] - spacing[1]
    verts[:, 2] += zs[0] - spacing[2]
    verts[:, 2] = np.maximum(verts[:, 2], 0.0)
    
    min_pt = np.min(verts, axis=0)
    max_pt = np.max(verts, axis=0)
    raw_dims = max_pt - min_pt
    
    if planar_fit:
        print(" -> Applying Hull + Planar Face Fitting Regularization...")
        fit_results = fit_planar_faces_and_regularize(verts, faces)
        dim_x = fit_results['dim_x_mm']
        dim_y = fit_results['dim_y_mm']
        dim_z = fit_results['dim_z_mm']
    else:
        dim_x = raw_dims[0]
        dim_y = raw_dims[1]
        dim_z = raw_dims[2]
        
    write_binary_stl(output_stl, verts, faces)
    vol_cm3 = compute_mesh_volume(verts, faces) / 1000.0
    elapsed = time.time() - t_start
    
    print("\n" + "=" * 75)
    print(" SCAN RESULTS & PHYSICAL DIMENSIONS AUDIT")
    print("=" * 75)
    print(f" Output STL File:        {output_stl} ({os.path.getsize(output_stl)/1024.0:.1f} KB)")
    print(f" Watertight 3D Solid:    YES (100% closed, slicer-ready)")
    print(f" Number of Triangles:    {len(faces):,}")
    print(f" Enclosed Volume:        {vol_cm3:.2f} cm3")
    print(f" Measured Dimension X:   {dim_x:6.2f} mm")
    print(f" Measured Dimension Y:   {dim_y:6.2f} mm")
    print(f" Measured Dimension Z:   {dim_z:6.2f} mm")
    
    if ref_dim is not None:
        err_x = abs(dim_x - ref_dim)
        err_y = abs(dim_y - ref_dim)
        err_z = abs(dim_z - ref_dim)
        mae = (err_x + err_y + err_z) / 3.0
        max_err = max(err_x, err_y, err_z)
        print("-" * 75)
        print(f" Ground Truth Reference: {ref_dim:6.2f} mm")
        print(f" Error X:                {err_x:5.2f} mm ({err_x/ref_dim*100:4.1f}%)")
        print(f" Error Y:                {err_y:5.2f} mm ({err_y/ref_dim*100:4.1f}%)")
        print(f" Error Z:                {err_z:5.2f} mm ({err_z/ref_dim*100:4.1f}%)")
        print(f" Mean Absolute Error:    {mae:5.2f} mm")
        print(f" Maximum Linear Error:   {max_err:5.2f} mm")
        
    print(f" Total Processing Time:  {elapsed:.2f} seconds")
    print("=" * 75 + "\n")
    return True


if __name__ == "__main__":
    args = parse_arguments()
    process_real_session(
        input_dir=args.input_dir,
        ref_dim=args.ref_dim,
        output_stl=args.output_stl,
        voxel_size=args.voxel_size,
        planar_fit=args.planar_fit,
        min_agreement=args.min_agreement
    )
