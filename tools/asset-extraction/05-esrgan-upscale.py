import sys
import numpy as np
from PIL import Image
import torch

import os
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

from realesrgan import RealESRGANer
from basicsr.archs.rrdbnet_arch import RRDBNet

def enhance_rgba(path_in, path_out, outscale=4):
    im = Image.open(path_in).convert("RGBA")
    rgb = np.asarray(im)[:, :, :3].copy()
    alpha = np.asarray(im)[:, :, 3].copy()
    # 透明区域填充为最近边缘颜色，避免模型对黑色区域产生伪影
    h, w = alpha.shape
    fill = np.zeros((h, w, 3), dtype=np.uint8)
    # 用 alpha 加权平均？简单方案：用中值颜色填充
    opaque = alpha > 128
    if opaque.any():
        med = np.median(rgb[opaque].reshape(-1, 3), axis=0).astype(np.uint8)
    else:
        med = np.array([128, 128, 128], dtype=np.uint8)
    filled = rgb.copy()
    filled[~opaque] = med

    model = RRDBNet(num_in_ch=3, num_out_ch=3, num_feat=64, num_block=23, num_grow_ch=32, scale=4)
    upsampler = RealESRGANer(
        scale=4,
        model_path="/root/.toolchain/RealESRGAN_x4plus.pth",
        model=model,
        tile=0,
        tile_pad=10,
        pre_pad=0,
        half=False,
    )
    output, _ = upsampler.enhance(filled, outscale=outscale)
    out_rgb = output.astype(np.uint8)

    # alpha 用 LANCZOS 放大
    a_img = Image.fromarray(alpha).resize((out_rgb.shape[1], out_rgb.shape[0]), Image.LANCZOS)
    out = Image.fromarray(np.dstack([out_rgb, np.asarray(a_img)]), "RGBA")
    out.save(path_out)
    print(f"{path_in} -> {path_out} {out.size}")

enhance_rgba("/tmp/asset-pipeline/extract/main-shield.png", "/tmp/asset-pipeline/extract/main-shield@4x.png", outscale=4)
