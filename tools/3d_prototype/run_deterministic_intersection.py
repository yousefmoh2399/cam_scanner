import os
import sys
import numpy as np
import cv2
from skimage.measure import marching_cubes

sys.path.insert(0, os.path.dirname(__file__))
from reconstruct_stl import reconstruct_volume
from investigation_suite_v2 import create_l_bracket_mesh

def run_deterministic_intersection():
    np.random.seed(42)
    
    verts_true, faces_true = create_l_bracket_mesh()
    true_dims = np.array([60.0, 40.0, 50.0], dtype=np.float32)
    center = np.mean(verts_true, axis=0)
    
    K = np.array([[1600.0, 0, 960.0], [0, 1600.0, 540.0], [0, 0, 1]], dtype=np.float32)
    dist = np.zeros((5, 1), dtype=np.float32)
    elevations = [15.0, 35.0, 60.0, 85.0]
    views_per_ring = 12
    radius = 380.0
    
    # Session 1: Upright
    views1 = []
    for elev_deg in elevations:
        elev_rad = np.radians(elev_deg)
        for i in range(views_per_ring):
            azim_rad = np.radians((360.0 / views_per_ring) * i)
            cam_pos = center + np.array([
                radius * np.cos(elev_rad) * np.cos(azim_rad),
                radius * np.cos(elev_rad) * np.sin(azim_rad),
                radius * np.sin(elev_rad)
            ], dtype=np.float32)
            forward = (center - cam_pos) / np.linalg.norm(center - cam_pos)
            up = np.array([0.0, 0.0, 1.0], dtype=np.float32)
            right = np.cross(forward, up)
            if np.linalg.norm(right) < 1e-4: right = np.array([1.0, 0.0, 0.0], dtype=np.float32)
            right = right / np.linalg.norm(right)
            cam_up = np.cross(right, forward)
            R_wc = np.vstack([right, -cam_up, forward])
            t_wc = -R_wc @ cam_pos
            rvec, _ = cv2.Rodrigues(R_wc)
            tvec = t_wc.reshape(3, 1)
            
            proj, _ = cv2.projectPoints(verts_true, rvec, tvec, K, dist)
            mask = np.zeros((1080, 1920), dtype=np.uint8)
            for f in faces_true:
                cv2.fillPoly(mask, [proj.reshape(-1, 2)[f].astype(np.int32)], 255)
            views1.append({'mask': mask, 'R': R_wc, 't': t_wc.flatten()})
            
    bounds1 = (60.0, 150.0, 40.0, 110.0, 0.0, 65.0)
    solid1, xs1, ys1, zs1 = reconstruct_volume(views1, K, bounds_mm=bounds1, voxel_size_mm=0.8, min_view_agreement=1.0)
    
    vol1 = solid1.copy()
    vol1[:, :, 0] = False
    pad1 = np.pad(vol1.astype(np.float32), 1, mode='constant', constant_values=0)
    spacing = (xs1[1] - xs1[0], ys1[1] - ys1[0], zs1[1] - zs1[0])
    verts1_m, _, _, _ = marching_cubes(pad1, level=0.5, spacing=spacing)
    verts1_m[:, 0] += xs1[0] - spacing[0]
    verts1_m[:, 1] += ys1[0] - spacing[1]
    verts1_m[:, 2] += zs1[0] - spacing[2]
    verts1_m[:, 2] = np.maximum(verts1_m[:, 2], 0.0)
    d_single = np.max(verts1_m, axis=0) - np.min(verts1_m, axis=0)
    mae_single = float(np.mean(np.abs(d_single - true_dims)))
    
    # Session 2: Flipped on side
    R_flip = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], dtype=np.float32)
    verts2_raw = (R_flip @ (verts_true - center).T).T + center
    verts2_raw[:, 2] -= np.min(verts2_raw[:, 2])
    center2 = np.mean(verts2_raw, axis=0)
    
    views2 = []
    for elev_deg in elevations:
        elev_rad = np.radians(elev_deg)
        for i in range(views_per_ring):
            azim_rad = np.radians((360.0 / views_per_ring) * i)
            cam_pos = center2 + np.array([
                radius * np.cos(elev_rad) * np.cos(azim_rad),
                radius * np.cos(elev_rad) * np.sin(azim_rad),
                radius * np.sin(elev_rad)
            ], dtype=np.float32)
            forward = (center2 - cam_pos) / np.linalg.norm(center2 - cam_pos)
            up = np.array([0.0, 0.0, 1.0], dtype=np.float32)
            right = np.cross(forward, up)
            if np.linalg.norm(right) < 1e-4: right = np.array([1.0, 0.0, 0.0], dtype=np.float32)
            right = right / np.linalg.norm(right)
            cam_up = np.cross(right, forward)
            R_wc = np.vstack([right, -cam_up, forward])
            t_wc = -R_wc @ cam_pos
            rvec, _ = cv2.Rodrigues(R_wc)
            tvec = t_wc.reshape(3, 1)
            
            proj, _ = cv2.projectPoints(verts2_raw, rvec, tvec, K, dist)
            mask = np.zeros((1080, 1920), dtype=np.uint8)
            for f in faces_true:
                cv2.fillPoly(mask, [proj.reshape(-1, 2)[f].astype(np.int32)], 255)
            views2.append({'mask': mask, 'R': R_wc, 't': t_wc.flatten()})
            
    bounds2 = (60.0, 150.0, 40.0, 110.0, 0.0, 75.0)
    solid2, xs2, ys2, zs2 = reconstruct_volume(views2, K, bounds_mm=bounds2, voxel_size_mm=0.8, min_view_agreement=1.0)
    
    X1, Y1, Z1 = np.meshgrid(xs1, ys1, zs1, indexing='ij')
    pts_s1 = np.stack([X1.ravel(), Y1.ravel(), Z1.ravel()], axis=-1)
    pts_centered = pts_s1 - center
    
    rot_errors = [0.5, 1.0, 3.0]
    trans_errors = [1.0, 3.0, 5.0]
    
    fixed_rot_axis = np.array([0.0, 0.0, 1.0], dtype=np.float32)
    fixed_trans_dir = np.array([1.0 / np.sqrt(2), 1.0 / np.sqrt(2), 0.0], dtype=np.float32)
    
    rows = []
    err_single = np.abs(d_single - true_dims)
    rows.append({
        'rot': '—',
        'trans': '—',
        'desc': 'Single Session (No Flip)',
        'dx': d_single[0],
        'dy': d_single[1],
        'dz': d_single[2],
        'z_infl': d_single[2] - 50.0,
        'mae': float(np.mean(err_single)),
        'max_err': float(np.max(err_single))
    })
    
    for r_deg in rot_errors:
        ang_rad = np.radians(r_deg)
        rvec_err = fixed_rot_axis * ang_rad
        R_err, _ = cv2.Rodrigues(rvec_err)
        
        for t_val in trans_errors:
            t_vec_err = fixed_trans_dir * t_val
            
            pts_misreg = (R_err @ pts_centered.T).T + t_vec_err
            pts_in_s2 = (R_flip @ pts_misreg.T).T + center2
            
            i2 = np.round((pts_in_s2[:, 0] - xs2[0]) / (xs2[1] - xs2[0])).astype(np.int32)
            j2 = np.round((pts_in_s2[:, 1] - ys2[0]) / (ys2[1] - ys2[0])).astype(np.int32)
            k2 = np.round((pts_in_s2[:, 2] - zs2[0]) / (zs2[1] - zs2[0])).astype(np.int32)
            
            valid = (
                (i2 >= 0) & (i2 < len(xs2)) &
                (j2 >= 0) & (j2 < len(ys2)) &
                (k2 >= 0) & (k2 < len(zs2))
            )
            
            occupied_s2 = np.zeros(len(pts_s1), dtype=bool)
            valid_idx = np.where(valid)[0]
            occupied_s2[valid_idx] = solid2[i2[valid_idx], j2[valid_idx], k2[valid_idx]]
            
            solid_inter = (solid1.ravel() & occupied_s2).reshape(solid1.shape)
            vol_i = solid_inter.copy()
            vol_i[:, :, 0] = False
            
            if np.sum(vol_i) < 100:
                continue
                
            pad_i = np.pad(vol_i.astype(np.float32), 1, mode='constant', constant_values=0)
            verts_i, _, _, _ = marching_cubes(pad_i, level=0.5, spacing=spacing)
            verts_i[:, 0] += xs1[0] - spacing[0]
            verts_i[:, 1] += ys1[0] - spacing[1]
            verts_i[:, 2] += zs1[0] - spacing[2]
            verts_i[:, 2] = np.maximum(verts_i[:, 2], 0.0)
            
            dims_i = np.max(verts_i, axis=0) - np.min(verts_i, axis=0)
            errs = np.abs(dims_i - true_dims)
            mae_val = float(np.mean(errs))
            max_err_val = float(np.max(errs))
            z_infl_val = float(dims_i[2] - 50.0)
            
            rows.append({
                'rot': f"{r_deg:.1f}",
                'trans': f"{t_val:.1f}",
                'desc': '',
                'dx': dims_i[0],
                'dy': dims_i[1],
                'dz': dims_i[2],
                'z_infl': z_infl_val,
                'mae': mae_val,
                'max_err': max_err_val
            })
            
    out_file = os.path.join(os.path.dirname(__file__), "deterministic_results.txt")
    with open(out_file, "w", encoding="utf-8") as f:
        f.write("Rot_deg,Trans_mm,DimX,DimY,DimZ,Z_infl,MAE,MaxErr\n")
        for r in rows:
            f.write(f"{r['rot']},{r['trans']},{r['dx']:.2f},{r['dy']:.2f},{r['dz']:.2f},{r['z_infl']:.2f},{r['mae']:.2f},{r['max_err']:.2f}\n")
    print(f"Results written successfully to {out_file}")

if __name__ == '__main__':
    run_deterministic_intersection()
