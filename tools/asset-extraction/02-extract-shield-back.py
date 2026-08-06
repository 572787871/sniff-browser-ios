import cv2
import numpy as np
from PIL import Image
from collections import deque

SRC = "/root/.clawdex-mobile-attachments/019fcd8d-9c86-7ef3-9861-fdd979247c43/20260806-055108-876-317937-25686F80-522E-4A25-812C-4A5BC01FBB69.png"
OUT = "/tmp/asset-pipeline/extract"
img = Image.open(SRC).convert("RGB")

def flood_remove(crop: Image.Image, tol: int = 12, ref: tuple = (255,255,255)) -> Image.Image:
    arr = np.asarray(crop.convert("RGB")).astype(np.int32)
    h, w, _ = arr.shape
    alpha = np.full((h, w), 255, dtype=np.uint8)
    dist = np.sqrt(((arr - np.array(ref, dtype=np.int16)) ** 2).sum(axis=2))
    bg = dist <= tol
    visited = np.zeros((h, w), dtype=bool)
    q = deque()
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
                visited[ny, nx] = True; q.append((ny, nx))
    alpha[visited] = 0
    soft = (dist > tol) & (dist <= tol + 8)
    ys, xs = np.nonzero(soft)
    alpha[ys, xs] = np.clip((dist[soft] - tol) / 8.0 * 255, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([arr.astype(np.uint8), alpha]), "RGBA")

def trim_scale(im: Image.Image, min_size: int) -> Image.Image:
    bbox = im.getbbox()
    if bbox: im = im.crop(bbox)
    scale = max(1.0, min_size / max(im.size))
    if scale > 1.0:
        im = im.resize((round(im.width*scale), round(im.height*scale)), Image.LANCZOS)
    return im

# 1) 主盾牌：重新裁剪，避开右侧标题文字，仅含盾牌+光晕
main = img.crop((82, 294, 222, 448))
main = flood_remove(main, tol=14)
main = trim_scale(main, 384)
main.save(f"{OUT}/main-shield.png")
print("main-shield ->", main.size)

# 2) 返回按钮：导航区白色圆按钮（背景为导航栏浅灰）
nav = np.asarray(img.convert("RGB"))
gray = cv2.cvtColor(nav, cv2.COLOR_RGB2GRAY)
region = gray[100:250, 30:190]
white = (region > 250).astype(np.uint8)
n, labels, stats, cents = cv2.connectedComponentsWithStats(white, 8)
best = max((s for s in stats[1:]), key=lambda s: s[4])
x, y, bw, bh, area = best
x0, y0 = 30 + x - 16, 100 + y - 16
x1, y1 = 30 + x + bw + 16, 100 + y + bh + 16
print("back button blob:", (x, y, bw, bh), "crop:", (x0, y0, x1, y1))
back = img.crop((x0, y0, x1, y1))
# 用导航栏背景色(244,245,250)作为参考色去底
back = flood_remove(back, tol=6, ref=(244, 245, 250))
back = trim_scale(back, 96)
back.save(f"{OUT}/back-button.png")
print("back-button ->", back.size)
