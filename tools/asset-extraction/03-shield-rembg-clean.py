import io
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage
from rembg import remove as rembg_remove

SRC = "/root/.clawdex-mobile-attachments/019fcd8d-9c86-7ef3-9861-fdd979247c43/20260806-055108-876-317937-25686F80-522E-4A25-812C-4A5BC01FBB69.png"
OUT = "/tmp/asset-pipeline/extract"
img = Image.open(SRC).convert("RGB")
crop = img.crop((80, 290, 240, 455))
arr = np.asarray(crop).astype(np.int32)

buf = io.BytesIO(); crop.save(buf, format="PNG")
rbga = np.asarray(Image.open(io.BytesIO(rembg_remove(buf.getvalue()))).convert("RGBA"))
alpha = rbga[:, :, 3].astype(np.float32)
alpha = np.where(alpha < 80, 0, alpha)          # 清半透明杂点
alpha = ndimage.grey_erosion(alpha, size=(5, 5)) # 收缩 2px 去白边
alpha = np.asarray(Image.fromarray(alpha.astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.5)))
alpha = np.where(alpha < 4, 0, alpha).astype(np.float32)

shield = Image.fromarray(np.dstack([arr.astype(np.uint8), alpha.astype(np.uint8)]), "RGBA")
bbox = shield.getbbox()
if bbox: shield = shield.crop(bbox)
scale = 384 / max(shield.size)
shield = shield.resize((round(shield.width*scale), round(shield.height*scale)), Image.LANCZOS)
shield.save(f"{OUT}/main-shield.png")
print("main-shield clean ->", shield.size)
a = np.asarray(shield)[:, :, 3]
print("transparent:", round((a==0).sum()/a.size*100,1), "%")
