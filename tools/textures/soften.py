"""Tone a texture down so its tiling is less obvious: remove most of the moss, even out the
big light/dark blotches that make each tile recognisable, and flatten the surface relief.

Every step either works pixel by pixel or blurs with wrap-around, so a texture that tiled
before still tiles afterwards.

usage: python soften.py <in dir> <out dir>
The dirs hold color.png, normal.png, rough.png. Settings are below.
"""
import os, sys
import numpy as np
from PIL import Image

MOSS_KEEP = 0.1     # how much of the moss's green survives (0 = none)
MOSS_DARKEN = 0.85  # moss becomes stone this much darker (moss mostly sits in the cracks)
MOSS_SHADING = 0.3  # how much of the moss clumps' own light/dark shading survives
MOSS_RELIEF = 0.15  # how much of the moss clumps' bumpiness survives in the normal map
BLOTCH = 0.35       # how much of the large-scale light/dark variation survives
DETAIL = 0.8        # how much of the fine detail (grain, edges) survives
BLOTCH_SIZE = 48    # px: anything broader than this counts as a "blotch"
NORMAL_STRENGTH = 0.55  # surface relief (1 = unchanged)
ROUGH_SPREAD = 0.5      # how much the roughness varies around its average (1 = unchanged)


def load(d, name):
    return np.asarray(Image.open(os.path.join(d, name + '.png')).convert('RGB'), np.float32)


def save(arr, d, name):
    Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8)).save(os.path.join(d, name + '.png'))


def wrap_blur(img, size):
    """Box blur, three passes (close to Gaussian), wrapping around the edges so tiling is kept."""
    out = img.copy()
    r = max(1, size // 2)
    for _ in range(3):
        for axis in (0, 1):
            acc = np.zeros_like(out)
            for k in range(-r, r + 1):
                acc += np.roll(out, k, axis=axis)
            out = acc / (2 * r + 1)
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    color, normal, rough = load(src, 'color'), load(src, 'normal'), load(src, 'rough')

    # 1. moss: how green is each pixel compared with grey stone?
    r, g, b = color[..., 0], color[..., 1], color[..., 2]
    # (moss here is yellow-green: well above blue, and not much below red)
    green = np.clip((g - b - 20) / 35.0, 0, 1) * np.clip((g - 0.8 * r) / 20.0, 0, 1)
    moss = wrap_blur(green[..., None], 3)[..., 0]
    moss = np.clip(moss * 2.0, 0, 1)[..., None]
    # replace it with the stone's own colour around it (the average of nearby non-moss pixels)
    weight = (1 - moss)
    stone = wrap_blur(color * weight, 24) / (wrap_blur(weight, 24) + 1e-3)
    grey = stone.mean(2, keepdims=True)
    lum = color.mean(2, keepdims=True)
    shading = 1 + (lum / (grey + 1e-3) - 1) * MOSS_SHADING
    replacement = stone * shading * MOSS_DARKEN
    color = color * (1 - moss * (1 - MOSS_KEEP)) + replacement * moss * (1 - MOSS_KEEP)

    # 2. even out the big blotches, keep a little less of the fine detail
    big = wrap_blur(color, BLOTCH_SIZE)
    mean = color.mean((0, 1))
    color = mean + (big - mean) * BLOTCH + (color - big) * DETAIL

    # 3. flatter surface relief
    vec = normal / 127.5 - 1
    vec[..., :2] *= NORMAL_STRENGTH * (1 - moss * (1 - MOSS_RELIEF))
    vec /= np.linalg.norm(vec, axis=2, keepdims=True) + 1e-6
    normal = (vec + 1) * 127.5

    # 4. more even roughness
    rough = rough.mean() + (rough - rough.mean()) * ROUGH_SPREAD

    save(color, dst, 'color')
    save(normal, dst, 'normal')
    save(rough, dst, 'rough')
    print('moss pixels before: %.1f%%' % (green.mean() * 100))


if __name__ == '__main__':
    main()
