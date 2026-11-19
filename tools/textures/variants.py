"""Make texture variations that all tile with each other.

Every variation keeps the original's outer border pixel-for-pixel, and takes its interior from a
different source texture. The join between them is a minimum-difference seam (image quilting):
it runs where the two images already look alike, usually along mortar lines. Because every
variation shares the same border, any two of them placed side by side meet exactly like the
original meets itself.

usage: python variants.py <original dir> <out dir> <source dir> [<source dir> ...]
Each dir holds color.png, normal.png, rough.png (512x512). The original's metal.png is copied.
"""
import os, shutil, sys
import numpy as np
from PIL import Image, ImageFilter

KEEP = 16     # px from each edge that are always the original (the shared border)
BAND = 96     # px from each edge within which the seam may run
FEATHER = 2   # px of blur across the seam so it isn't a hard cut
DARK = 3.0    # how strongly the seam prefers dark mortar gaps over matching colours


def load(d, name):
    return np.asarray(Image.open(os.path.join(d, name + '.png')).convert('RGB'), np.float32)


def match_stats(src, ref):
    """Shift/scale each channel of src to ref's mean and spread (so tones match)."""
    out = (src - src.mean((0, 1))) / (src.std((0, 1)) + 1e-6) * ref.std((0, 1)) + ref.mean((0, 1))
    return np.clip(out, 0, 255)


def seam_rows(cost):
    """Cheapest left-to-right path through cost[rows, cols], moving at most 1 row per column.
    Returns the path's row for each column."""
    h, w = cost.shape
    acc = cost.copy()
    back = np.zeros((h, w), np.int8)
    for x in range(1, w):
        prev = acc[:, x - 1]
        up = np.r_[np.inf, prev[:-1]]
        down = np.r_[prev[1:], np.inf]
        stack = np.stack([up, prev, down])
        choice = stack.argmin(0)
        acc[:, x] += stack[choice, np.arange(h)]
        back[:, x] = choice - 1
    rows = np.zeros(w, int)
    rows[-1] = acc[:, -1].argmin()
    for x in range(w - 1, 0, -1):
        rows[x - 1] = rows[x] + back[rows[x], x]
    return rows


def interior_mask(err):
    """1 where the new texture shows, 0 where the original does."""
    n = err.shape[0]
    ys, xs = np.mgrid[0:n, 0:n]
    # top edge: seam in rows KEEP..BAND, pixels below it are interior
    top = seam_rows(err[KEEP:BAND, :]) + KEEP
    bottom = n - 1 - (seam_rows(err[::-1][KEEP:BAND, :]) + KEEP)
    left = seam_rows(err[:, KEEP:BAND].T) + KEEP
    right = n - 1 - (seam_rows(err[:, ::-1][:, KEEP:BAND].T) + KEEP)
    inside = (ys > top[xs]) & (ys < bottom[xs]) & (xs > left[ys]) & (xs < right[ys])
    m = Image.fromarray((inside * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(FEATHER))
    m = np.asarray(m, np.float32) / 255
    m[:KEEP, :] = m[-KEEP:, :] = 0
    m[:, :KEEP] = m[:, -KEEP:] = 0
    return m[..., None]


def main():
    orig_dir, out_dir, sources = sys.argv[1], sys.argv[2], sys.argv[3:]
    oc, on, orr = load(orig_dir, 'color'), load(orig_dir, 'normal'), load(orig_dir, 'rough')
    os.makedirs(out_dir, exist_ok=True)
    for i, src in enumerate(sources, 1):
        nc = match_stats(load(src, 'color'), oc)
        nn = load(src, 'normal')
        nr = match_stats(load(src, 'rough'), orr)
        # where do the two differ least? colour mostly, plus surface shape
        # ...and prefer cutting through dark pixels in both (the mortar gaps), so stones stay whole
        lum_o, lum_n = oc.mean(2), nc.mean(2)
        err = ((oc - nc) ** 2).sum(2) + 0.5 * ((on - nn) ** 2).sum(2) + DARK * (lum_o ** 2 + lum_n ** 2)
        m = interior_mask(err)
        color = oc * (1 - m) + nc * m
        rough = orr * (1 - m) + nr * m
        # normals: blend as vectors, then make them unit length again
        vec = (on / 127.5 - 1) * (1 - m) + (nn / 127.5 - 1) * m
        vec /= np.linalg.norm(vec, axis=2, keepdims=True) + 1e-6
        normal = (vec + 1) * 127.5
        d = os.path.join(out_dir, f'var{i}')
        os.makedirs(d, exist_ok=True)
        for name, arr in (('color', color), ('normal', normal), ('rough', rough)):
            Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8)).save(os.path.join(d, name + '.png'))
        Image.fromarray((m[..., 0] * 255).astype(np.uint8)).save(os.path.join(d, 'mask.png'))
        shutil.copy(os.path.join(orig_dir, 'metal.png'), os.path.join(d, 'metal.png'))
        # check: the border really is identical to the original
        assert np.abs(color[:KEEP] - oc[:KEEP]).max() < 1 and np.abs(color[:, -KEEP:] - oc[:, -KEEP:]).max() < 1
        print(f'var{i}: {m.mean() * 100:.0f}% new')


if __name__ == '__main__':
    main()
