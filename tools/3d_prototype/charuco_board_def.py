"""
ChArUco Board Definition & Detection Utilities
Defines the standard metric calibration mat and robust pose estimation
under partial marker occlusion.
"""

import cv2
import cv2.aruco as aruco
import numpy as np


def get_standard_charuco_board():
    """
    Standard Metric ChArUco Board:
    - 7 columns x 5 rows of chessboard squares
    - Square size: 30.0 mm (ground truth)
    - Marker size: 22.0 mm (ground truth)
    - Dictionary: cv2.aruco.DICT_5X5_100
    Total physical board dimensions: 210 x 150 mm (fits cleanly inside standard A4 297 x 210 mm).
    """
    dictionary = aruco.getPredefinedDictionary(aruco.DICT_5X5_100)
    
    # Check OpenCV API version for CharucoBoard creation
    if hasattr(aruco, 'CharucoBoard'):
        try:
            # OpenCV 4.7+ (in millimeters)
            board = aruco.CharucoBoard((7, 5), 30.0, 22.0, dictionary)
        except TypeError:
            board = aruco.CharucoBoard_create(7, 5, 30.0, 22.0, dictionary)
    else:
        board = aruco.CharucoBoard_create(7, 5, 30.0, 22.0, dictionary)
        
    return board, dictionary


def generate_board_image(output_path="charuco_a4_mat.png", dpi=300):
    """
    Generates high-resolution printable image of the calibration board.
    At 300 DPI: 1 mm = 11.811 pixels.
    """
    board, _ = get_standard_charuco_board()
    # 210 x 150 mm board image
    width_px = int(7 * 30.0 * (dpi / 25.4))
    height_px = int(5 * 30.0 * (dpi / 25.4))
    
    if hasattr(board, 'generateImage'):
        img = board.generateImage((width_px, height_px), marginSize=20, borderBits=1)
    else:
        img = board.draw((width_px, height_px), marginSize=20, borderBits=1)
        
    cv2.imwrite(output_path, img)
    return output_path


def detect_and_estimate_pose(image, camera_matrix, dist_coeffs):
    """
    Robust pose estimation using ChArUco board.
    Resistant to partial occlusion: Even if 40-60% of markers are covered
    by the 3D printed object, visible chessboard corners are reconstructed.
    
    Returns:
        success (bool), rvec, tvec, charuco_corners, charuco_ids
    """
    board, dictionary = get_standard_charuco_board()
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
    
    # 1. Detect ArUco markers
    if hasattr(aruco, 'ArucoDetector'):
        detector_params = aruco.DetectorParameters()
        detector = aruco.ArucoDetector(dictionary, detector_params)
        corners, ids, rejected = detector.detectMarkers(gray)
    else:
        detector_params = aruco.DetectorParameters_create()
        corners, ids, rejected = aruco.detectMarkers(gray, dictionary, parameters=detector_params)
        
    if ids is None or len(ids) < 3:
        return False, None, None, None, None
        
    # 2. Refine & interpolate ChArUco chessboard corners from detected markers
    # This solves the occlusion problem: corners adjacent to visible markers are recovered
    if hasattr(aruco, 'interpolateCornersCharuco'):
        interpolated = aruco.interpolateCornersCharuco(corners, ids, gray, board)
        if len(interpolated) >= 2:
            num_corners, charuco_corners, charuco_ids = interpolated[0], interpolated[1], interpolated[2] if len(interpolated) >= 3 else (interpolated[0], interpolated[1], None)
        else:
            return False, None, None, None, None
    else:
        return False, None, None, None, None

    if charuco_corners is None or len(charuco_corners) < 4:
        return False, None, None, None, None

    # 3. Solve PnP for camera pose relative to metric board plane
    if hasattr(aruco, 'estimatePoseCharucoBoard'):
        success, rvec, tvec = aruco.estimatePoseCharucoBoard(
            charuco_corners, charuco_ids, board, camera_matrix, dist_coeffs, None, None
        )
        if success:
            return True, rvec, tvec, charuco_corners, charuco_ids
            
    # Fallback to cv2.solvePnP with ChArUco 3D board points
    # Get 3D object points for the detected corner IDs
    board_corners = board.getChessboardCorners() if hasattr(board, 'getChessboardCorners') else board.chessboardCorners
    obj_pts = board_corners[charuco_ids.flatten()]
    img_pts = charuco_corners.reshape(-1, 2)
    
    success, rvec, tvec = cv2.solvePnP(
        obj_pts, img_pts, camera_matrix, dist_coeffs, flags=cv2.SOLVEPNP_ITERATIVE
    )
    
    return success, rvec, tvec, charuco_corners, charuco_ids
