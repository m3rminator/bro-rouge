"""Trace a character reference sheet into pixel-exact sprite parts.

The reference sheets in refrences/ are upscaled pixel art (each art pixel is a ~9 px block)
with six poses laid out the same way:

    run    | idle
    shoot  | jump
    crouch | hurt

For every pose this tool finds the pose's own pixel grid, takes the median color of each
cell, removes the sand background (flood fill from the edges), keeps the largest connected
figure (drops dust, shells, muzzle flashes, sparks) and snaps every pixel to a palette.

Two modes:
    py tools/trace_reference.py IMAGE --suggest 16
        print the main colors of the figure (to add them to master.yaml as a palette)
    py tools/trace_reference.py IMAGE --palette SET --out FILE.json
        snap to an art/palettes/sets/SET.yaml palette and write {pose: [rows]} as JSON;
        each row uses the set's symbols, "." = transparent

The output is only a starting point that gets pasted into art/sprites/NAME.yaml — that file
stays the source of truth (tools/build.py never reads the reference image).
"""
import argparse
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent

# Pose boxes as fractions of the sheet size (measured on the 1008 x 1046 sheets).
POSES = {
    "run": (30, 60, 400, 365), "idle": (500, 60, 820, 365),
    "shoot": (30, 410, 480, 720), "jump": (520, 385, 830, 690),
    "crouch": (60, 760, 400, 1015), "hurt": (500, 700, 920, 1046),
}
SHEET = (1008, 1046)


def fit_grid(g):
    best = None
    for pitch in np.arange(8.4, 9.1, 0.02):
        for phase in np.arange(0, pitch, 0.2):
            idx = np.round(np.arange(phase, len(g), pitch)).astype(int)
            idx = idx[idx < len(g)]
            v = g[idx].mean()
            if best is None or v > best[0]:
                best = (v, pitch, phase)
    return best[1], best[2]


def sample(a):
    """Median color of every art pixel of the crop `a` (H x W x 3 floats)."""
    gx = np.abs(np.diff(a, axis=1)).sum(2).sum(0)
    gy = np.abs(np.diff(a, axis=0)).sum(2).sum(1)
    px, phx = fit_grid(gx)
    py, phy = fit_grid(gy)
    xs = np.arange(phx + 0.5, a.shape[1], px)
    ys = np.arange(phy + 0.5, a.shape[0], py)
    cells = np.zeros((len(ys) - 1, len(xs) - 1, 3))
    for j in range(len(ys) - 1):
        for i in range(len(xs) - 1):
            xa, xb = int(xs[i] + px * 0.3), int(xs[i + 1] - px * 0.3)
            ya, yb = int(ys[j] + py * 0.3), int(ys[j + 1] - py * 0.3)
            cells[j, i] = np.median(a[ya:yb + 1, xa:xb + 1].reshape(-1, 3), axis=0)
    return cells


def is_sand(v):
    r, g, b = v
    return r > 150 and g > 115 and b < 150 and (g - b) > 35 and (r - g) < 58 and not (r > 225 and g > 225)


def figure_mask(cells):
    h, w, _ = cells.shape
    bg = np.zeros((h, w), bool)
    q = deque((y, x) for y in range(h) for x in range(w) if y in (0, h - 1) or x in (0, w - 1))
    while q:
        y, x = q.popleft()
        if bg[y, x] or not is_sand(cells[y, x]):
            continue
        bg[y, x] = True
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not bg[ny, nx]:
                q.append((ny, nx))
    fg = ~bg & ~((cells[..., 0] > 225) & (cells[..., 1] > 190))  # no flashes / sparks
    label = -np.ones((h, w), int)
    sizes = []
    for y in range(h):
        for x in range(w):
            if fg[y, x] and label[y, x] < 0:
                n = len(sizes)
                label[y, x] = n
                q = deque([(y, x)])
                count = 0
                while q:
                    cy, cx = q.popleft()
                    count += 1
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = cy + dy, cx + dx
                            if 0 <= ny < h and 0 <= nx < w and fg[ny, nx] and label[ny, nx] < 0:
                                label[ny, nx] = n
                                q.append((ny, nx))
                sizes.append(count)
    return label == int(np.argmax(sizes))


def trace(image_path):
    img = Image.open(image_path).convert("RGB")
    sx, sy = img.width / SHEET[0], img.height / SHEET[1]
    a = np.asarray(img).astype(float)
    poses = {}
    for name, (x0, y0, x1, y1) in POSES.items():
        crop = a[int(y0 * sy):int(y1 * sy), int(x0 * sx):int(x1 * sx)]
        cells = sample(crop)
        poses[name] = (cells, figure_mask(cells))
    return poses


def kmeans(points, k, seed=1):
    rng = np.random.default_rng(seed)
    cent = points[rng.choice(len(points), k, replace=False)]
    for _ in range(60):
        lab = ((points[:, None] - cent[None]) ** 2).sum(2).argmin(1)
        cent = np.array([points[lab == i].mean(0) if (lab == i).any() else cent[i] for i in range(k)])
    return cent, np.bincount(lab, minlength=k)


def snap(poses, set_name):
    master = yaml.safe_load((ROOT / "art/palettes/master.yaml").read_text(encoding="utf-8"))["colors"]
    symbols = yaml.safe_load((ROOT / f"art/palettes/sets/{set_name}.yaml").read_text(encoding="utf-8"))["symbols"]
    keys = list(symbols)
    pal = np.array([[int(master[symbols[k]][i:i + 2], 16) for i in (1, 3, 5)] for k in keys], float)
    out = {}
    for name, (cells, mask) in poses.items():
        lab = ((cells[:, :, None] - pal[None, None]) ** 2).sum(3).argmin(2)
        rows = ["".join(keys[lab[y, x]] if mask[y, x] else "." for x in range(cells.shape[1]))
                for y in range(cells.shape[0])]
        rows = [r for r in rows if r.strip(".")]
        left = min(len(r) - len(r.lstrip(".")) for r in rows)
        right = max(len(r.rstrip(".")) for r in rows)
        out[name] = [r[left:right] for r in rows]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image")
    ap.add_argument("--suggest", type=int, help="print N main colors of the figure")
    ap.add_argument("--palette", help="palette set to snap to (art/palettes/sets/NAME.yaml)")
    ap.add_argument("--out", help="JSON file for the traced poses")
    args = ap.parse_args()
    poses = trace(args.image)
    if args.suggest:
        pts = np.concatenate([cells[mask] for cells, mask in poses.values()])
        cent, count = kmeans(pts, args.suggest)
        for i in np.argsort(cent.sum(1)):
            r, g, b = cent[i].astype(int)
            print(f"#{r:02x}{g:02x}{b:02x}  {count[i]} px")
        return
    if not (args.palette and args.out):
        sys.exit("give --suggest N, or --palette SET --out FILE.json")
    Path(args.out).write_text(json.dumps(snap(poses, args.palette), indent=1), encoding="utf-8")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
