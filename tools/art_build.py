"""Deterministic pixel-art pipeline.

Specs (art/sprites/*.yaml) + palettes (art/palettes) -> sprite sheets, Godot
SpriteFrames, previews and the catalog page. Same specs always produce the same
bytes. Already-approved assets are locked in art.lock.json: if a rebuild would
change one, the build stops and writes a before/after image to docs/diff/
instead, until you approve it with --accept NAME.

    py tools/art_build.py                 build (refuses to change locked assets)
    py tools/art_build.py --accept bro    approve the change to "bro" (or: all)
    py tools/art_build.py --check         verify files on disk match the specs
"""
import argparse
import hashlib
import html
import json
import sys
from pathlib import Path

import numpy as np
import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "art"
GAME = ROOT / "game"
DOCS = ROOT / "docs"
SPRITE_OUT = GAME / "assets" / "sprites"
LOCK_PATH = ROOT / "art.lock.json"
PREVIEW_SCALE = 8


class SpecError(Exception):
    pass


def load_yaml(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def hex_to_rgba(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def load_palettes():
    master = load_yaml(ART / "palettes" / "master.yaml")["colors"]
    sets = {}
    for path in sorted((ART / "palettes" / "sets").glob("*.yaml")):
        symbols = load_yaml(path)["symbols"]
        for sym, color in symbols.items():
            if len(str(sym)) != 1 or sym == ".":
                raise SpecError(f"{path.name}: bad symbol {sym!r}")
            if color not in master:
                raise SpecError(f"{path.name}: '{color}' is not in master.yaml")
        sets[path.stem] = symbols
    return master, sets


def parse_part(name, text, symbols, sprite):
    rows = [r for r in text.strip("\n").split("\n")]
    width = len(rows[0])
    for i, row in enumerate(rows):
        if len(row) != width:
            raise SpecError(f"{sprite}.{name}: row {i} is {len(row)} wide, expected {width}")
        for ch in row:
            if ch != "." and ch not in symbols:
                raise SpecError(f"{sprite}.{name}: symbol {ch!r} not in palette set")
    return rows


def render_frame(layers, parts, size, colors, sprite, where):
    w, h = size
    img = np.zeros((h, w, 4), dtype=np.uint8)
    for layer in layers:
        pname, x, y = layer[0], int(layer[1]), int(layer[2])
        flip = len(layer) > 3 and layer[3] == "flip"
        if pname not in parts:
            raise SpecError(f"{sprite} {where}: unknown part {pname!r}")
        rows = parts[pname]
        for ry, row in enumerate(rows):
            if flip:
                row = row[::-1]
            for rx, ch in enumerate(row):
                if ch == ".":
                    continue
                px, py = x + rx, y + ry
                if not (0 <= px < w and 0 <= py < h):
                    raise SpecError(f"{sprite} {where}: part {pname!r} pixel ({px},{py}) outside frame")
                img[py, px] = colors[ch]
    return img


def build_sprite(path, master, sets):
    spec = load_yaml(path)
    name = spec["name"]
    if spec["palette"] not in sets:
        raise SpecError(f"{name}: unknown palette set {spec['palette']!r}")
    symbols = sets[spec["palette"]]
    colors = {sym: hex_to_rgba(master[c]) for sym, c in symbols.items()}
    fw, fh = spec["frame"]
    parts = {p: parse_part(p, t, symbols, name) for p, t in spec["parts"].items()}

    anims = spec["animations"]
    max_frames = max(len(a["frames"]) for a in anims.values())
    sheet = np.zeros((fh * len(anims), fw * max_frames, 4), dtype=np.uint8)
    layout = []
    for row, (aname, anim) in enumerate(anims.items()):
        for col, layers in enumerate(anim["frames"]):
            frame = render_frame(layers, parts, (fw, fh), colors, name, f"{aname}[{col}]")
            sheet[row * fh:(row + 1) * fh, col * fw:(col + 1) * fw] = frame
        layout.append((aname, row, len(anim["frames"]), anim.get("fps", 8), anim.get("loop", True)))
    return spec, Image.fromarray(sheet, "RGBA"), layout


def png_bytes(img):
    import io
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=False, compress_level=9)
    return buf.getvalue()


def spriteframes_tres(name, fw, fh, layout):
    lines = [f'[gd_resource type="SpriteFrames" load_steps={sum(l[2] for l in layout) + 2} format=3]', "",
             f'[ext_resource type="Texture2D" path="res://assets/sprites/{name}.png" id="1"]', ""]
    anim_blocks = []
    idx = 0
    for aname, row, count, fps, loop in layout:
        frame_refs = []
        for col in range(count):
            sid = f"AtlasTexture_{idx}"
            idx += 1
            lines += [f'[sub_resource type="AtlasTexture" id="{sid}"]', 'atlas = ExtResource("1")',
                      f"region = Rect2({col * fw}, {row * fh}, {fw}, {fh})", ""]
            frame_refs.append('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % sid)
        anim_blocks.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}'
                           % (", ".join(frame_refs), "true" if loop else "false", aname, float(fps)))
    lines += ["[resource]", "animations = [%s]" % ", ".join(anim_blocks), ""]
    return "\n".join(lines).encode("utf-8")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_diff(name, old_path, new_img):
    DOCS.joinpath("diff").mkdir(parents=True, exist_ok=True)
    old = Image.open(old_path).convert("RGBA") if old_path.exists() else Image.new("RGBA", (1, 1))
    w, h = max(old.width, new_img.width), max(old.height, new_img.height)
    out = Image.new("RGBA", (w * 2 + 2, h), (255, 0, 255, 255))
    out.paste(old, (0, 0))
    out.paste(new_img, (w + 2, 0))
    out = out.resize((out.width * 6, out.height * 6), Image.NEAREST)
    out.save(DOCS / "diff" / f"{name}.png")
    return DOCS / "diff" / f"{name}.png"


# ---------------------------------------------------------------- catalog

def catalog_html(master, sets, sprites, storyboards, audio):
    e = html.escape
    import base64
    uri = {sp["name"]: "data:image/png;base64," + base64.b64encode(png_bytes(img)).decode() for sp, img, _ in sprites}
    css = """
    :root{--bg:#16131f;--card:#221d30;--ink:#ece8f4;--mute:#9a94ad;--line:#3a3350;--acc:#ffd23e}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,sans-serif}
    main{max-width:1100px;margin:auto;padding:24px 16px 80px}h1{margin:0 0 4px}h2{margin:48px 0 12px;border-bottom:1px solid var(--line);padding-bottom:6px}
    h3{margin:24px 0 8px;color:var(--acc)}.mute{color:var(--mute)}.grid{display:flex;flex-wrap:wrap;gap:10px}
    .sw{width:120px;background:var(--card);border-radius:8px;overflow:hidden;font-size:12px}.sw div{height:44px}.sw p{margin:4px 8px}
    .card{background:var(--card);border-radius:10px;padding:14px;margin:10px 0}
    img.px,.px{image-rendering:pixelated}.anim{display:inline-block;margin:8px 16px 8px 0;text-align:center;font-size:12px}
    .frame{background-repeat:no-repeat;background-color:#5ab4e8;border-radius:6px}
    .sym{display:inline-flex;align-items:center;gap:6px;margin:3px 10px 3px 0;font:12px monospace}.sym i{width:16px;height:16px;border-radius:3px;display:inline-block;border:1px solid #0006}
    .panels{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px}
    .panel{background:var(--card);border-radius:10px;overflow:hidden}.panel .stage{height:160px;background:linear-gradient(#5ab4e8 70%,#3e8034 70%,#3e8034 74%,#6e4628 74%);display:flex;align-items:flex-end;justify-content:center;padding-bottom:28px}
    .panel .stage.text{background:#2b2540;align-items:center;font-size:42px;padding:0}.panel p{margin:8px 12px 12px}.panel b{color:var(--acc)}
    table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:middle}audio{height:32px}
    """
    out = [f"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
           f"<title>Art & Audio Catalog</title><style>{css}"]
    keyframes = []
    body = ["<main><h1>Art &amp; Audio Catalog</h1><p class='mute'>Generated by tools/art_build.py — do not edit by hand. "
            "Every asset here is built from a spec, so it never drifts.</p>"]

    body.append("<h2>Master palette</h2><div class='grid'>")
    for cname, hexv in master.items():
        body.append(f"<div class='sw'><div style='background:{hexv}'></div><p><b>{e(cname)}</b><br>{hexv}</p></div>")
    body.append("</div><h2>Palette sets</h2>")
    for sname, symbols in sets.items():
        body.append(f"<div class='card'><h3 style='margin-top:0'>{e(sname)}</h3>")
        for sym, cname in symbols.items():
            body.append(f"<span class='sym'><i style='background:{master[cname]}'></i>{e(sym)} = {e(cname)}</span>")
        body.append("</div>")

    body.append("<h2>Sprites</h2>")
    for spec, img, layout in sprites:
        name, (fw, fh) = spec["name"], spec["frame"]
        s = spec.get("preview_scale", 6)
        body.append(f"<div class='card'><h3 style='margin-top:0'>{e(name)}</h3><p class='mute'>{e(spec.get('description', ''))}</p>"
                    f"<p class='mute'>frame {fw}×{fh} · palette <b>{e(spec['palette'])}</b> · sheet {img.width}×{img.height}</p>")
        for aname, row, count, fps, loop in layout:
            kf = f"k_{name}_{aname}"
            keyframes.append(f"@keyframes {kf}{{from{{background-position-x:0}}to{{background-position-x:-{count * fw * s}px}}}}")
            dur = count / fps
            body.append(f"<div class='anim'><div class='frame px' style='width:{fw * s}px;height:{fh * s}px;"
                        f"background-image:url({uri[name]});background-size:{img.width * s}px {img.height * s}px;"
                        f"background-position-y:-{row * fh * s}px;animation:{kf} {dur:.3f}s steps({count}) infinite'></div>"
                        f"{e(aname)} · {count}f @ {fps}fps{'' if loop else ' · once'}</div>")
        body.append(f"<p><img class='px' src='{uri[name]}' style='width:{img.width * 4}px;background:#0003'></p>")
        if spec.get("anchors"):
            body.append("<p class='mute'>anchors: " + ", ".join(f"{e(k)} = {v}" for k, v in spec["anchors"].items()) + "</p>")
        body.append("</div>")

    body.append("<h2>Storyboards</h2>")
    sprite_index = {sp["name"]: (sp, img, {l[0]: l for l in lay}) for sp, img, lay in sprites}
    for sb in storyboards:
        body.append(f"<h3>{e(sb['title'])}</h3><p class='mute'>{e(sb.get('description', ''))}</p><div class='panels'>")
        for i, panel in enumerate(sb["panels"], 1):
            shot = panel.get("shot")
            if shot:
                sname, aname, fidx = shot.split("/")
                sp, img, lay = sprite_index[sname]
                fw, fh = sp["frame"]
                s = 5
                row = lay[aname][1]
                flip = "transform:scaleX(-1);" if panel.get("flip") else ""
                stage = (f"<div class='stage'><div class='px' style='{flip}width:{fw * s}px;height:{fh * s}px;"
                         f"background:url({uri[sname]}) -{int(fidx) * fw * s}px -{row * fh * s}px/"
                         f"{img.width * s}px {img.height * s}px no-repeat'></div></div>")
            else:
                stage = f"<div class='stage text'>{e(panel.get('icon', '▶'))}</div>"
            extra = f"<br><span class='mute'>sfx: {e(panel['sfx'])}</span>" if panel.get("sfx") else ""
            body.append(f"<div class='panel'>{stage}<p><b>{i}. {e(panel['title'])}</b><br>{e(panel['caption'])}{extra}</p></div>")
        body.append("</div>")

    body.append("<h2>Audio</h2>")
    for kind, entries in audio.items():
        body.append(f"<h3>{e(kind)}</h3><table><tr><th>name</th><th>prompt</th><th>listen</th></tr>")
        for aname, entry in entries.items():
            rel = f"../game/assets/{kind}/{aname}.mp3"
            exists = (DOCS / rel).resolve().exists()
            player = f"<audio controls preload='none' src='{rel}'></audio>" if exists else "<span class='mute'>not generated yet</span>"
            body.append(f"<tr><td><b>{e(aname)}</b></td><td class='mute'>{e(entry['prompt'])}</td><td>{player}</td></tr>")
        body.append("</table>")

    out.append("".join(keyframes) + "</style></head><body>")
    out += body
    out.append("</main></body></html>")
    return "\n".join(out)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--accept", action="append", default=[], help="approve changes to a locked asset (or 'all')")
    ap.add_argument("--check", action="store_true", help="verify disk matches specs; write nothing")
    args = ap.parse_args()

    try:
        master, sets = load_palettes()
        sprites = [build_sprite(p, master, sets) for p in sorted((ART / "sprites").glob("*.yaml"))]
    except SpecError as err:
        sys.exit(f"SPEC ERROR: {err}")

    lock = json.loads(LOCK_PATH.read_text()) if LOCK_PATH.exists() else {}
    outputs = {}  # asset name -> {relpath: bytes}
    for spec, img, layout in sprites:
        name = spec["name"]
        fw, fh = spec["frame"]
        preview = img.resize((img.width * PREVIEW_SCALE, img.height * PREVIEW_SCALE), Image.NEAREST)
        outputs[name] = {
            f"game/assets/sprites/{name}.png": png_bytes(img),
            f"game/assets/sprites/{name}_frames.tres": spriteframes_tres(name, fw, fh, layout),
            f"docs/previews/{name}.png": png_bytes(preview),
        }

    changed = {}
    for name, files in outputs.items():
        new_hashes = {rel: sha(data) for rel, data in files.items()}
        if name in lock and lock[name] != new_hashes:
            changed[name] = new_hashes

    if args.check:
        bad = list(changed)
        for name, files in outputs.items():
            for rel, data in files.items():
                p = ROOT / rel
                if not p.exists() or sha(p.read_bytes()) != sha(data):
                    bad.append(f"{name}: {rel}")
        if bad:
            sys.exit("CHECK FAILED:\n  " + "\n  ".join(sorted(set(bad))))
        print(f"OK - {len(outputs)} assets match specs and lock.")
        return

    blocked = [n for n in changed if n not in args.accept and "all" not in args.accept]
    if blocked:
        print("These approved assets would change:")
        for name in blocked:
            diff = write_diff(name, ROOT / f"game/assets/sprites/{name}.png",
                              Image.open(__import__("io").BytesIO(outputs[name][f"game/assets/sprites/{name}.png"])))
            print(f"  - {name}   (before | after: {diff.relative_to(ROOT)})")
        sys.exit("Nothing written. Review the diff, then rerun with --accept NAME (or revert the spec).")

    for name, files in outputs.items():
        for rel, data in files.items():
            p = ROOT / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
        lock[name] = {rel: sha(data) for rel, data in files.items()}
    for stale in set(lock) - set(outputs):
        del lock[stale]
    LOCK_PATH.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n")

    storyboards = [load_yaml(p) for p in sorted((ART / "storyboards").glob("*.yaml"))]
    audio_spec = load_yaml(ROOT / "audio" / "catalog.yaml") if (ROOT / "audio" / "catalog.yaml").exists() else {}
    DOCS.mkdir(exist_ok=True)
    (DOCS / "catalog.html").write_text(catalog_html(master, sets, sprites, storyboards, audio_spec), encoding="utf-8")

    print(f"Built {len(outputs)} assets ({', '.join(outputs)}). Accepted changes: {', '.join(changed) or 'none'}.")
    print("Catalog: docs/catalog.html")


if __name__ == "__main__":
    main()
