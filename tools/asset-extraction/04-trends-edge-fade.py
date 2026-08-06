import numpy as np
from PIL import Image
from collections import deque

OUT = "/tmp/asset-pipeline/extract"
SRC = "/root/.clawdex-mobile-attachments/019fcd8d-9c86-7ef3-9861-fdd979247c43/20260806-055108-876-317937-25686F80-522E-4A25-812C-4A5BC01FBB69.png"
img = Image.open(SRC).convert("RGB")

def flood_remove(crop, tol=12):
    arr = np.asarray(crop.convert("RGB")).astype(np.int32)
    h, w, _ = arr.shape
    alpha = np.full((h, w), 255, dtype=np.uint8)
    dist = np.sqrt(((arr - np.array((255,255,255), dtype=np.int32)) ** 2).sum(axis=2))
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
    # 边缘渐隐：靠近裁剪边界的像素 alpha 线性衰减
    yy, xx = np.mgrid[0:h, 0:w]
    fade = np.minimum.reduce([
        yy.astype(np.float32),
        (h - 1 - yy).astype(np.float32),
        xx.astype(np.float32),
        (w - 1 - xx).astype(np.float32)
    ])
    fade = np.clip(fade / 10.0, 0, 1)
    alpha = (alpha.astype(np.float32) * fade).astype(np.uint8)
    return Image.fromarray(np.dstack([arr.astype(np.uint8), alpha]), "RGBA")

def trim_scale(im, min_size):
    bbox = im.getbbox()
    if bbox: im = im.crop(bbox)
    scale = max(1.0, min_size / max(im.size))
    if scale > 1.0:
        im = im.resize((round(im.width*scale), round(im.height*scale)), Image.LANCZOS)
    return im

trends = {
    "trend-red": (70, 770, 430, 838),
    "trend-blue": (490, 764, 850, 824),
    "trend-green": (70, 1046, 430, 1108),
    "trend-orange": (490, 1040, 850, 1100),
}
for name, box in trends.items():
    t = trim_scale(flood_remove(img.crop(box)), 512)
    t.save(f"{OUT}/{name}.png")
    print(name, t.size)
