"""
Elevation Angle Sweep for ChArUco Board Detection & solvePnP Pose Accuracy
Measures at what minimum elevation the board can be detected,
and computes rotation error (degrees) and translation error (mm) per ring.
"""

import cv2
import cv2.aruco as aruco
import numpy as np

dict_5x5 = aruco.getPredefinedDictionary(aruco.DICT_5X5_100)
board = aruco.CharucoBoard((7, 5), 30.0, 22.0, dict_5x5)
tex = board.generateImage((2100, 1500), marginSize=0, borderBits=1)

K = np.array([[1600.0, 0, 960.0], [0, 1600.0, 540.0], [0, 0, 1]], dtype=np.float32)
dist_coeffs = np.zeros((5, 1), dtype=np.float32)
board_center = np.array([105.0, 75.0, 0.0], dtype=np.float32)
radius_mm = 380.0
detector = aruco.CharucoDetector(board)

elevations = [5.0, 8.0, 10.0, 12.0, 15.0, 20.0, 25.0, 35.0, 50.0, 70.0, 85.0]

print("==========================================================================================")
print(" CHARUCO BOARD DETECTABILITY & ESTIMATED POSE ERROR VS ELEVATION ANGLE")
print("==========================================================================================")
print(f"| {'Elevation (deg)':<15} | {'Markers':<8} | {'Corners':<8} | {'Status':<8} | {'Rot Error (deg)':<15} | {'Trans Error (mm)':<16} |")
print("|" + "-"*17 + "|" + "-"*10 + "|" + "-"*10 + "|" + "-"*10 + "|" + "-"*17 + "|" + "-"*18 + "|")

all_corners_3d = board.getChessboardCorners().copy()
all_corners_3d[:, 1] = 150.0 - all_corners_3d[:, 1]

for elev in elevations:
    elev_rad = np.radians(elev)
    cam_pos = board_center + np.array([radius_mm * np.cos(elev_rad), 0.0, radius_mm * np.sin(elev_rad)], dtype=np.float32)
    forward = (board_center - cam_pos) / np.linalg.norm(board_center - cam_pos)
    up = np.array([0.0, 0.0, 1.0], dtype=np.float32)
    right = np.cross(forward, up) / np.linalg.norm(np.cross(forward, up))
    cam_up = np.cross(right, forward)
    R_wc = np.vstack([right, -cam_up, forward])
    t_wc = -R_wc @ cam_pos
    
    board_pts = np.array([[0, 150, 0], [210, 150, 0], [210, 0, 0], [0, 0, 0]], dtype=np.float32)
    proj, _ = cv2.projectPoints(board_pts, cv2.Rodrigues(R_wc)[0], t_wc, K, dist_coeffs)
    H = cv2.getPerspectiveTransform(np.array([[0, 0], [2099, 0], [2099, 1499], [0, 1499]], dtype=np.float32), proj.reshape(-1, 2))
    frame = cv2.warpPerspective(tex, H, (1920, 1080), borderValue=240)
    
    ch, id, m, mid = detector.detectBoard(frame)
    num_c = len(id) if id is not None else 0
    num_m = len(mid) if mid is not None else 0
    
    if num_c >= 4:
        obj_pts = all_corners_3d[id.flatten()]
        img_pts = ch.reshape(-1, 2)
        success, est_rvec, est_tvec = cv2.solvePnP(obj_pts, img_pts, K, dist_coeffs, flags=cv2.SOLVEPNP_ITERATIVE)
        if success:
            R_est, _ = cv2.Rodrigues(est_rvec)
            R_err = R_est @ R_wc.T
            ang = np.degrees(np.arccos(np.clip((np.trace(R_err) - 1.0) / 2.0, -1.0, 1.0)))
            terr = np.linalg.norm(est_tvec.flatten() - t_wc.flatten())
            print(f"| {elev:<15.1f} | {num_m:<8d} | {num_c:<8d} | {'SUCCESS':<8} | {ang:<15.4f} | {terr:<16.4f} |")
            continue
    print(f"| {elev:<15.1f} | {num_m:<8d} | {num_c:<8d} | {'FAILED':<8} | {'N/A':<15} | {'N/A':<16} |")
print("==========================================================================================\n")
