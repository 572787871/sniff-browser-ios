import cv2
import numpy as np
from PIL import Image

SRC = "/root/.clawdex-mobile-attachments/019fcd8d-9c86-7ef3-9861-fdd979247c43/20260806-055108-876-317937-25686F80-522E-4A25-812C-4A5BC01FBB69.png"
OUT = "/tmp/asset-pipeline/extract"
import os
os.makedirs(OUT, exist_ok=True)

img = Image.open(SRC).convert("RGB")
W, H = img.size

# (名称, 裁剪框(x0,y0,x1,y1), 目标最小尺寸)
assets = [
    ("main-shield", (72, 292, 250, 462), 384),
    ("red-shield",   (92, 644, 176, 730), 128),
    ("blue-globe",   (508, 642, 592, 732), 128),
    ("green-list",   (90, 928, 172, 1010), 128),
    ("orange-funnel",(508, 924, 588, 1008), 128),
    ("import-icon",  (80, 1250, 166, 1334), 128),
    ("whitelist-icon",(78, 1390, 162, 1474), 128),
    ("trend-red",    (70, 770, 430, 838), 512),
    ("trend-blue",   (490, 764, 850, 824), 512),
    ("trend-green",  (70, 1046, 430, 1108), 512),
    ("trend-orange", (490, 1040, 850, 1100), 512),
]

def flood_remove_background(crop: Image.Image, tol: int = 12) -> Image.Image:
    """从边界向内洪水填充：与白色背景相近的连通区域设为透明。
    保留浅色图标块（填充在白色背景包围中，不会触及边界）。"""
    arr = np.asarray(crop.convert("RGB")).astype(np.int16)
    h, w, _ = arr.shape
    alpha = np.full((h, w), 255, dtype=np.uint8)
    dist = np.sqrt(((arr - 255.0) ** 2).sum(axis=2))  # 到纯白的距离
    # 背景判定：接近白（容差内）
    bg = dist <= tol
    # BFS 从边界
    from collections import deque
    q = deque()
    visited = np.zeros((h, w), dtype=bool)
    for x in range(w):
        for y in (0, h - 1):
            if bg[y, x] and not visited[y, x]:
                visited[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if bg[y, x] and not visited[y, x]:
                visited[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((-1,0),(1,0),(0,-1),(0,1)):
            ny, nx = y+dy, x+dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and bg[ny, nx]:
                visited[ny, nx] = True
                q.append((ny, nx))
    alpha[visited] = 0
    # 抗锯齿边缘：把与白色距离在 tol..tol+8 之间的像素做半透明过渡
    soft = (dist > tol) & (dist <= tol + 8)
    a = np.clip((dist[soft] - tol) / 8.0 * 255, 0, 255).astype(np.uint8)
    ys, xs = np.nonzero(soft)
    alpha[ys, xs] = a
    rgba = np.dstack([arr.astype(np.uint8), alpha])
    return Image.fromarray(rgba, "RGBA")

def trim_and_scale(img: Image.Image, min_size: int) -> Image.Image:
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    scale = max(1.0, min_size / max(img.size))
    if scale > 1.0:
        img = img.resize(
            (round(img.width * scale), round(img.height * scale)),
            Image.LANCZOS
        )
    return img

manifest = []
for name, box, min_size in assets:
    crop = img.crop(box)
    out = flood_remove_background(crop)
    out = trim_and_scale(out, min_size)
    out.save(f"{OUT}/{name}.png")
    manifest.append((name, box, out.size))
    print(f"{name}: box={box} -> {out.size}")

with open(f"{OUT}/manifest.txt", "w") as f:
    for name, box, size in manifest:
        f.write(f"{name}\t{box}\t{size}\n")
print("done")
