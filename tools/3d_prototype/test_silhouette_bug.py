import numpy as np
import cv2

# Simulate an image: 800x600
# Table (brown wood): RGB (120, 80, 50) in [0, 800] x [0, 600]
# White paper (A4) in center: [100, 700] x [80, 520], RGB (240, 240, 240)
# Phone in center of paper: [250, 550] x [220, 380], RGB (30, 30, 35) (dark phone)

img = np.zeros((600, 800, 3), dtype=np.uint8)
img[:, :] = (50, 80, 120) # BGR brown wood table

# Draw white paper
cv2.rectangle(img, (100, 80), (700, 520), (240, 240, 240), -1)

# Draw phone
cv2.rectangle(img, (250, 220), (550, 380), (35, 30, 30), -1)

# Current extractSmartSilhouette logic:
lab = cv2.cvtColor(img, cv2.COLOR_BGR2Lab)
procW, procH = 800, 600
cornerW = max(5, procW // 12)
cornerH = max(5, procH // 12)

corners = [
    lab[0:cornerH, 0:cornerW],
    lab[0:cornerH, procW-cornerW:procW],
    lab[procH-cornerH:procH, 0:cornerW],
    lab[procH-cornerH:procH, procW-cornerW:procW]
]

means = [np.mean(c, axis=(0, 1)) for c in corners]
bg = np.mean(means, axis=0)

print("Sampled bg Lab:", bg)
# Lab for white paper:
paper_lab = cv2.cvtColor(np.uint8([[[240, 240, 240]]]), cv2.COLOR_BGR2Lab)[0, 0]
phone_lab = cv2.cvtColor(np.uint8([[[35, 30, 30]]]), cv2.COLOR_BGR2Lab)[0, 0]

dist_paper = np.sum((paper_lab.astype(float) - bg)**2)
dist_phone = np.sum((phone_lab.astype(float) - bg)**2)

print(f"Dist paper: {dist_paper:.1f} (thresh={22**2}) -> Paper is FG? {dist_paper > 22**2}")
print(f"Dist phone: {dist_phone:.1f} (thresh={22**2}) -> Phone is FG? {dist_phone > 22**2}")
