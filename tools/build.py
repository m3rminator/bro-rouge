"""Deterministic build for art, game data and the catalog.

- art/sprites/*.yaml + art/palettes -> sprite sheets, Godot SpriteFrames, previews
- design/controls.yaml + design/entities/*.yaml + design/levels + design/run.yaml
  -> game/scripts/generated/game_data.gd
- everything above + storyboards + audio -> docs/catalog.html

Same specs always produce the same bytes. Already-approved sprites are locked in
art.lock.json: if a rebuild would change one, the build stops and writes a
before/after image to docs/diff/ instead, until you approve it with --accept NAME.

    py tools/build.py                 build (refuses to change locked sprites)
    py tools/build.py --accept bro    approve the change to "bro" (or: all)
    py tools/build.py --check         verify files on disk match the specs
"""
import argparse
import base64
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
DESIGN = ROOT / "design"
GAME_DATA = "game/scripts/generated/game_data.gd"
LOCK_PATH = ROOT / "art.lock.json"
PREVIEW_SCALE = 8


class SpecError(Exception):
    pass


def load_yaml(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def hex_to_rgba(value):
    """#rrggbb (opaque) or #rrggbbaa (semi-transparent, e.g. glows)."""
    value = value.lstrip("#")
    alpha = int(value[6:8], 16) if len(value) == 8 else 255
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


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


def gun_tip(layers, parts, size, gun, second=False):
    """Muzzle of one frame: just right of the rightmost pixel drawn in a gun color (`gun` =
    palette symbols), on the middle row of the barrel there. None if the frame has no gun."""
    w, h = size
    grid = [["."] * w for _ in range(h)]
    for layer in layers:
        x, y = int(layer[1]), int(layer[2])
        for ry, row in enumerate(parts[layer[0]]):
            for rx, ch in enumerate(row):
                if ch != ".":
                    grid[y + ry][x + rx] = ch
    if second:
        return second_gun_tip(grid, gun)
    cols = [x for x in range(w) if any(grid[y][x] in gun for y in range(h))]
    if not cols:
        return None
    tip = max(cols)
    rows = [y for y in range(h) if grid[y][tip] in gun]
    return (tip + 1, rows[(len(rows) - 1) // 2])


def second_gun_tip(grid, gun, min_size=8):
    """Tip of the other gun in a two-gun frame: the gun-colored blobs (8-connected, at least
    `min_size` pixels) are the guns; the second-rightmost blob's tip. None with one gun."""
    h, w = len(grid), len(grid[0])
    seen, blobs = set(), []
    for y in range(h):
        for x in range(w):
            if grid[y][x] in gun and (x, y) not in seen:
                stack, blob = [(x, y)], []
                seen.add((x, y))
                while stack:
                    cx, cy = stack.pop()
                    blob.append((cx, cy))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and grid[ny][nx] in gun:
                                seen.add((nx, ny))
                                stack.append((nx, ny))
                if len(blob) >= min_size:
                    blobs.append(blob)
    if len(blobs) < 2:
        return None
    blobs.sort(key=lambda b: max(p[0] for p in b), reverse=True)
    blob = blobs[1]
    tip = max(p[0] for p in blob)
    rows = sorted(p[1] for p in blob if p[0] == tip)
    return (tip + 1, rows[(len(rows) - 1) // 2])


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
    if spec.get("muzzle_symbols"):
        spec["_muzzles"] = {aname: [gun_tip(layers, parts, (fw, fh), spec["muzzle_symbols"]) for layers in anim["frames"]]
                            for aname, anim in anims.items()}
        if spec.get("two_guns"):
            spec["_muzzles2"] = {aname: [gun_tip(layers, parts, (fw, fh), spec["muzzle_symbols"], True) for layers in anim["frames"]]
                                 for aname, anim in anims.items()}
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


# ---------------------------------------------------------------- design data

KEY_NAMES = {**{c: f"KEY_{c}" for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"}, **{d: f"KEY_{d}" for d in "0123456789"},
             "Left": "KEY_LEFT", "Right": "KEY_RIGHT", "Up": "KEY_UP", "Down": "KEY_DOWN", "Space": "KEY_SPACE",
             "Enter": "KEY_ENTER", "Escape": "KEY_ESCAPE", "Tab": "KEY_TAB", "Shift": "KEY_SHIFT",
             "Ctrl": "KEY_CTRL", "Alt": "KEY_ALT"}


def split_anim(default_sprite, key):
    return tuple(key.split("/", 1)) if "/" in key else (default_sprite, key)


def load_design(sprites, audio):
    """Load controls + entities and cross-check every reference, so the catalog can't lie."""
    controls = load_yaml(DESIGN / "controls.yaml")["actions"]
    for action, spec in controls.items():
        for key in spec["keys"]:
            if key not in KEY_NAMES:
                raise SpecError(f"controls.{action}: unknown key {key!r} (allowed: {', '.join(KEY_NAMES)})")
    sprite_anims = {sp["name"]: {l[0] for l in lay} for sp, _, lay in sprites}
    sfx = set(audio.get("sfx", {}))
    entities = {}
    for path in sorted((DESIGN / "entities").glob("*.yaml")):
        ent = load_yaml(path)
        eid = ent["id"]
        if ent["sprite"] not in sprite_anims:
            raise SpecError(f"entity {eid}: unknown sprite {ent['sprite']!r}")
        for anim in ent.get("animations", {}):  # "anim" (entity's own sprite) or "sprite/anim"
            sname, aname = split_anim(ent["sprite"], anim)
            if sname not in sprite_anims or aname not in sprite_anims[sname]:
                raise SpecError(f"entity {eid}: sprite {sname!r} has no animation {aname!r}")
        for sym, prev in ent.get("level_preview", {}).items():
            if sym not in ent.get("level_symbols", {}):
                raise SpecError(f"entity {eid}: level_preview {sym!r} is not one of its level_symbols")
            if prev["anim"] not in sprite_anims[ent["sprite"]]:
                raise SpecError(f"entity {eid}: level_preview anim {prev['anim']!r} not in sprite {ent['sprite']!r}")
        for sound in ent.get("sounds", {}):
            if sound not in sfx:
                raise SpecError(f"entity {eid}: sound {sound!r} is not in audio/catalog.yaml")
        for action in ent.get("controls", []):
            if action not in controls:
                raise SpecError(f"entity {eid}: control {action!r} is not in design/controls.yaml")
        for f in ent.get("files", []):
            if not (ROOT / f).exists():
                raise SpecError(f"entity {eid}: file {f} does not exist")
        entities[eid] = ent
    entities = dict(sorted(entities.items(), key=lambda kv: (kv[1].get("order", 99), kv[0])))
    for ent in entities.values():
        for other in ent.get("spawns", []) + ent.get("spawned_by", []):
            if other not in entities:
                raise SpecError(f"entity {ent['id']}: unknown entity {other!r}")
    return controls, entities


def load_levels(entities):
    """design/levels/*.txt: one character per block-sized tile. Symbols come from entities' level_symbols."""
    symbols = {s for ent in entities.values() for s in ent.get("level_symbols", {})}
    levels = {}
    for path in sorted((DESIGN / "levels").glob("*.txt")):
        rows = path.read_text(encoding="utf-8").strip("\n").split("\n")
        for y, row in enumerate(rows):
            if len(row) != len(rows[0]):
                raise SpecError(f"{path.name}: row {y} is {len(row)} wide, expected {len(rows[0])}")
            for x, ch in enumerate(row):
                if ch not in symbols:
                    raise SpecError(f"{path.name}: unknown symbol {ch!r} at ({x},{y}); known: {''.join(sorted(symbols))}")
        if sum(r.count("P") for r in rows) != 1:
            raise SpecError(f"{path.name}: needs exactly one 'P' (player start)")
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in TALL_SYMBOLS:  # tall things: the tiles above them (and the Brute's sides) must be free
                    tall = TALL_SYMBOLS[ch]
                    around = [(x, y - k) for k in range(1, tall)]
                    if ch == "B":
                        around += [(x + dx, y - k) for dx in (-1, 1) for k in range(tall)]
                    for ax, ay in around:
                        if ay < 0 or not (0 <= ax < len(row)) or rows[ay][ax] == "#":
                            raise SpecError(f"{path.name}: {ch!r} at ({x},{y}) needs air at ({ax},{ay})")
        levels[path.stem] = rows
    return levels


TALL_SYMBOLS = {"P": 2, "E": 2, "K": 2, "X": 2, "B": 3, "O": 2}  # height in tiles of what stands on that tile


def enemy_symbols(entities):
    return {s for ent in entities.values() if ent["kind"] == "enemy" for s in ent.get("level_symbols", {})}


def load_run(levels, entities):
    """design/run.yaml: level order and kill quotas. Every map must exist, have one exit and enough enemies."""
    run = load_yaml(DESIGN / "run.yaml")
    foes = enemy_symbols(entities)
    for i, lv in enumerate(run["levels"], 1):
        if lv["map"] not in levels:
            raise SpecError(f"run.yaml level {i}: map {lv['map']!r} not found in design/levels")
        rows = levels[lv["map"]]
        if sum(r.count("X") for r in rows) != 1:
            raise SpecError(f"run.yaml level {i}: {lv['map']} needs exactly one 'X' (exit)")
        count = sum(r.count(c) for r in rows for c in foes)
        if not 0 < lv["kill_quota"] <= count:
            raise SpecError(f"run.yaml level {i}: kill_quota {lv['kill_quota']} but {lv['map']} has {count} enemies")
    return run


def load_storyboards(sprites, audio):
    anims = {sp["name"]: {l[0]: l[2] for l in lay} for sp, _, lay in sprites}
    boards = []
    for path in sorted((ART / "storyboards").glob("*.yaml")):
        board = load_yaml(path)
        for i, panel in enumerate(board["panels"], 1):
            if panel.get("shot"):
                sname, aname, fidx = panel["shot"].split("/")
                if sname not in anims or aname not in anims[sname] or int(fidx) >= anims[sname][aname]:
                    raise SpecError(f"{path.name} panel {i}: shot {panel['shot']!r} does not exist")
            if panel.get("sfx") and panel["sfx"] not in audio.get("sfx", {}):
                raise SpecError(f"{path.name} panel {i}: sound {panel['sfx']!r} is not in audio/catalog.yaml")
        boards.append(board)
    return boards


def tile_hash(x, y, salt=0):
    """Same integer hash as scripts/main.gd (tile_hash) - random-looking, but the same level always looks the same."""
    n = (x * 374761393 + y * 668265263 + salt * 1274126177) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return n ^ (n >> 16)


def tile_variants(sprites):
    anims = next(lay for sp, _, lay in sprites if sp["name"] == "terrain")
    names = [l[0] for l in anims]
    kinds = ("earth", "subsoil", "pebble", "flint", "rock", "grass", "stonetop", "stone", "deep")
    return {kind: sum(1 for n in names if n.startswith(kind + "_")) for kind in kinds}


def has_sky(rows, x, y, clearance):
    """Same rule as main.gd: grass only where `clearance` tiles above are all air."""
    return all(rows[yy][x] != "#" for yy in range(max(0, y - clearance), y))


def air_distance(rows, x, y, reach=3, not_above=False):
    """Same rule as main.gd: 1 = touches open air, up to reach+1 = buried deep. not_above ignores air higher up (the sky over the ground)."""
    def air(ax, ay):
        if ay < 0:
            return True
        if ax < 0 or ax >= len(rows[0]) or ay >= len(rows):
            return False  # the map edge counts as solid ground
        return rows[ay][ax] != "#"
    for r in range(1, reach + 1):
        for dy in range(0 if not_above else -r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) == r and air(x + dx, y + dy):
                    return r
    return reach + 1


def pick_tile(rows, x, y, variants, clearance, biome="earth"):
    """Same rules as main.gd (_add_block): returns (anim, drip anim or None, flip_h, flip_v)."""
    h = tile_hash(x, y)
    flip_h = bool((h >> 3) & 1)
    flip_v = bool((h >> 4) & 1)
    pick = lambda kind: f"{kind}_{tile_hash(x, y, 1) % variants[kind]}"
    sky = has_sky(rows, x, y, clearance)
    d = air_distance(rows, x, y)
    if biome == "stone":
        if sky:
            return pick("stonetop"), None, flip_h, False
        return (pick("stone") if d <= 2 else pick("deep")), None, flip_h, flip_v
    if sky:
        k = tile_hash(x, y, 1) % variants["grass"]
        return f"grass_{k}", (f"drip_{k}" if y + 1 < len(rows) else None), flip_h, False
    roll = tile_hash(x, y, 2) % 100
    if d <= 3:  # the second layer (two rows deep): some clods, now and then a stone
        return (pick("pebble") if roll < 14 else pick("earth")), None, flip_h, flip_v
    return (pick("flint") if roll < 7 else pick("subsoil")), None, flip_h, flip_v  # the third layer and deeper: low detail


def level_tiles(rows, variants, clearance, biome="earth"):
    """Yield (x, y, anim, flip_h, flip_v) for every terrain sprite to draw, including grass strands."""
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != "#":
                continue
            anim, drip, fh, fv = pick_tile(rows, x, y, variants, clearance, biome)
            yield x, y, anim, fh, fv
            if drip:
                yield x, y + 1, drip, fh, False


def render_level(rows, sprites, clearance, entities):
    index = {sp["name"]: (sp, img, {l[0]: l[1] for l in lay}) for sp, img, lay in sprites}
    previews = {sym: (ent["sprite"], prev["anim"], prev.get("flip", False))
                for ent in entities.values() for sym, prev in ent.get("level_preview", {}).items()}
    variants = tile_variants(sprites)

    def frame(sname, anim):
        sp, img, lay = index[sname]
        fw, fh = sp["frame"]
        return img.crop((0, lay[anim] * fh, fw, lay[anim] * fh + fh))

    T = entities["block"]["stats"]["size"]["value"]
    out = Image.new("RGBA", (len(rows[0]) * T, len(rows) * T), hex_to_rgba("#5ab4e8"))
    tiles = sorted(level_tiles(rows, variants, clearance), key=lambda t: t[2].startswith("drip"))
    for x, y, anim, fh, fv in tiles:
        tile = frame("terrain", anim)
        if fh:
            tile = tile.transpose(Image.FLIP_LEFT_RIGHT)
        if fv:
            tile = tile.transpose(Image.FLIP_TOP_BOTTOM)
        out.alpha_composite(tile, (x * T, y * T))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in previews:  # bottom-centered on its tile, like in the game; enemies start facing left
                sname, anim, flip = previews[ch]
                sprite = frame(sname, anim)
                if flip:
                    sprite = sprite.transpose(Image.FLIP_LEFT_RIGHT)
                px, py = x * T + T // 2 - sprite.width // 2, y * T + T - sprite.height
                out.alpha_composite(sprite, (max(px, 0), max(py, 0)))
    return out


def gd_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return json.dumps(v)


def game_data_gd(controls, entities, sprites, levels, run):
    lines = ["# GENERATED by tools/build.py from design/*.yaml and art/sprites/*.yaml — do not edit by hand.",
             "# Change the YAML, then run: py tools/build.py", "class_name GameData", "",
             "## Input action -> keys (design/controls.yaml)", "const CONTROLS := {"]
    for action, spec in controls.items():
        lines.append(f'\t"{action}": [{", ".join(KEY_NAMES[k] for k in spec["keys"])}],')
    lines += ["}", ""]
    for eid, ent in entities.items():
        lines.append(f"## {ent['name']} (design/entities/{eid}.yaml)")
        lines.append(f"const {eid.upper()} := {{")
        for stat, spec in ent.get("stats", {}).items():
            lines.append(f'\t"{stat}": {gd_value(spec["value"])},')
        lines += ["}", ""]
    lines += ["## Sprite anchors relative to the frame center, in pixels (art/sprites/*.yaml)", "const ANCHORS := {"]
    for spec, _, _ in sprites:
        if spec.get("anchors"):
            fw, fh = spec["frame"]
            pts = ", ".join(f'"{k}": Vector2({x + 0.5 - fw / 2}, {y + 0.5 - fh / 2})' for k, (x, y) in spec["anchors"].items())
            lines.append(f'\t"{spec["name"]}": {{{pts}}},')
    lines += ["}", "",
              "## Gun tip of every frame, relative to the frame center (null = no gun in that frame).",
              "## Found by tools/build.py from each sprite's muzzle_symbols, so bullets always leave the barrel.",
              "const MUZZLES := {"]
    for spec, _, _ in sprites:
        if spec.get("_muzzles"):
            fw, fh = spec["frame"]
            anims = ", ".join(f'"{a}": [' + ", ".join("null" if t is None else f"Vector2({t[0] + 0.5 - fw / 2}, {t[1] + 0.5 - fh / 2})"
                                                       for t in tips) + "]" for a, tips in spec["_muzzles"].items())
            lines.append(f'	"{spec["name"]}": {{{anims}}},')
    lines += ["}", "",
              "## The second gun's tip per frame, for sprites with two_guns (null = only one gun shows).",
              "const MUZZLES_2 := {"]
    for spec, _, _ in sprites:
        if spec.get("_muzzles2"):
            fw, fh = spec["frame"]
            anims = ", ".join(f'"{a}": [' + ", ".join("null" if t is None else f"Vector2({t[0] + 0.5 - fw / 2}, {t[1] + 0.5 - fh / 2})"
                                                       for t in tips) + "]" for a, tips in spec["_muzzles2"].items())
            lines.append(f'	"{spec["name"]}": {{{anims}}},')
    lines += ["}", "", "## Frame size (width, height) of every sprite (art/sprites/*.yaml).", "const SPRITE_SIZES := {"]
    for spec, _, _ in sprites:
        lines.append(f'	"{spec["name"]}": Vector2({spec["frame"][0]}, {spec["frame"][1]}),')
    lines += ["}", ""]
    variants = tile_variants(sprites)
    lines += ["## Number of terrain variants per kind (art/sprites/terrain.yaml).",
              "## Which one a block gets: scripts/main.gd (same rules as tools/build.py pick_tile) - by distance to open air and a position hash.",
              "const TILE_VARIANTS := {" + ", ".join(f'"{k}": {v}' for k, v in variants.items()) + "}", "",
              "## Level maps (design/levels/*.txt)", "const LEVELS := {"]
    for name, rows in levels.items():
        lines.append(f'\t"{name}": [')
        lines += [f'\t\t"{r}",' for r in rows]
        lines.append("\t],")
    lines += ["}", "", "## Run loop: level order and kill quotas (design/run.yaml)", "const RUN := {"]
    for stat, spec in run["stats"].items():
        lines.append(f'\t"{stat}": {gd_value(spec["value"])},')
    lines.append('\t"levels": [')
    for lv in run["levels"]:
        lines.append(f'\t\t{{"map": {gd_value(lv["map"])}, "title": {gd_value(lv["title"])}, "kill_quota": {lv["kill_quota"]}}},')
    lines += ["\t],", "}", ""]
    return "\n".join(lines).encode("utf-8")


# ---------------------------------------------------------------- catalog

def keycaps(keys):
    return " ".join(f"<kbd>{html.escape(k)}</kbd>" for k in keys)


def catalog_html(master, sets, sprites, storyboards, audio, controls, entities, levels, run):
    e = html.escape
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
    th{color:var(--mute);font-weight:600;font-size:13px}.tbl{overflow-x:auto}
    kbd{display:inline-block;min-width:26px;text-align:center;padding:2px 7px;margin:1px 2px;border-radius:5px;background:#3a3350;border-bottom:3px solid #14101e;font:600 13px monospace}
    nav{position:sticky;top:0;background:var(--bg);padding:10px 0;border-bottom:1px solid var(--line);z-index:5;display:flex;flex-wrap:wrap;gap:6px 16px}
    nav a{color:var(--ink);text-decoration:none;font-size:14px}nav a:hover{color:var(--acc)}
    .pill{display:inline-block;padding:1px 8px;border-radius:99px;background:#3a3350;font-size:12px;margin-right:4px}code{font-size:13px;color:#c8c0e0}
    .num{font:600 14px monospace;color:var(--acc);white-space:nowrap}
    """
    out = [f"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
           f"<title>Bro Rogue Catalog</title><style>{css}"]
    keyframes = []
    sprite_index = {sp["name"]: (sp, img, {l[0]: l for l in lay}) for sp, img, lay in sprites}

    def anim_box(sname, aname, s, label):
        sp, img, lay = sprite_index[sname]
        fw, fh = sp["frame"]
        _, row, count, fps, loop = lay[aname]
        kf = f"k_{sname}_{aname}_{s}"
        keyframes.append(f"@keyframes {kf}{{from{{background-position-x:0}}to{{background-position-x:-{count * fw * s}px}}}}")
        return (f"<div class='anim'><div class='frame px' style='width:{fw * s}px;height:{fh * s}px;"
                f"background-image:url({uri[sname]});background-size:{img.width * s}px {img.height * s}px;"
                f"background-position-y:-{row * fh * s}px;animation:{kf} {count / fps:.3f}s steps({count}) infinite'></div>"
                f"{label}</div>")

    def sound_player(name):
        rel = f"../game/assets/sfx/{name}.mp3"
        if (DOCS / rel).resolve().exists():
            return f"<audio controls preload='none' src='{rel}'></audio>"
        return "<span class='mute'>not generated yet</span>"

    body = ["<main><h1>Bro Rogue — Catalog</h1><p class='mute'>Generated by <code>py tools/build.py</code> — do not edit by hand. "
            "Everything here is read from the same spec files the game is built from, so it is always exactly what is in the game.</p>",
            "<nav><a href='#controls'>Controls</a><a href='#entities'>Entities</a>"
            + "".join(f"<a href='#ent-{e(i)}'>· {e(x['name'])}</a>" for i, x in entities.items())
            + "<a href='#run'>Run loop</a><a href='#levels'>Levels</a><a href='#palette'>Palettes</a><a href='#sprites'>Sprites</a><a href='#storyboards'>Storyboards</a><a href='#audio'>Audio</a></nav>"]

    # Controls
    used_by = {a: [x["name"] for x in entities.values() if a in x.get("controls", [])] for a in controls}
    body.append("<h2 id='controls'>Controls</h2><p class='mute'>Source: <code>design/controls.yaml</code></p>"
                "<div class='tbl'><table><tr><th>Action</th><th>Keys</th><th>What it does</th><th>Used by</th><th>Action id</th></tr>")
    for action, spec in controls.items():
        body.append(f"<tr><td><b>{e(spec['label'])}</b></td><td>{keycaps(spec['keys'])}</td><td>{e(spec['description'])}</td>"
                    f"<td>{e(', '.join(used_by[action]))}</td><td><code>{e(action)}</code></td></tr>")
    body.append("</table></div>")

    # Entities
    body.append("<h2 id='entities'>Entities</h2><p class='mute'>One card per thing in the game. Stats are the exact values the game uses "
                "(<code>GameData</code>). Source: <code>design/entities/*.yaml</code></p>")
    for eid, ent in entities.items():
        body.append(f"<div class='card' id='ent-{e(eid)}'><h3 style='margin-top:0'>{e(ent['name'])} "
                    f"<span class='pill'>{e(ent['kind'])}</span></h3><p>{e(ent['description'])}</p>")
        if ent.get("stats"):
            body.append(f"<h4>Stats <span class='mute'>— in code: <code>GameData.{eid.upper()}.&lt;name&gt;</code></span></h4>"
                        "<div class='tbl'><table><tr><th>Name</th><th>Value</th><th>Meaning</th></tr>")
            for stat, spec in ent["stats"].items():
                body.append(f"<tr><td><code>{e(stat)}</code></td><td class='num'>{spec['value']} {e(spec.get('unit', ''))}</td>"
                            f"<td>{e(spec['description'])}</td></tr>")
            body.append("</table></div>")
        if ent.get("controls"):
            body.append("<h4>Controls</h4><div class='tbl'><table>")
            for action in ent["controls"]:
                body.append(f"<tr><td><b>{e(controls[action]['label'])}</b></td><td>{keycaps(controls[action]['keys'])}</td></tr>")
            body.append("</table></div>")
        if ent.get("animations"):
            body.append(f"<h4>Animations <span class='mute'>— sprite <code>{e(ent['sprite'])}</code></span></h4>"
                        "<div class='tbl'><table><tr><th>Preview</th><th>Plays when</th><th>Frames</th></tr>")
            for key, when in ent["animations"].items():
                sname, aname = split_anim(ent["sprite"], key)
                _, _, count, fps, loop = sprite_index[sname][2][aname]
                fw, fh = sprite_index[sname][0]["frame"]
                scale = 3 if max(fw, fh) <= 32 else 2
                body.append(f"<tr><td>{anim_box(sname, aname, scale, e(key))}</td><td>{e(when)}</td>"
                            f"<td class='mute'>{count} @ {fps} fps{'' if loop else ', once'}</td></tr>")
            body.append("</table></div>")
        if ent.get("sounds"):
            body.append("<h4>Sounds</h4><div class='tbl'><table><tr><th>Sound</th><th>Plays when</th><th>Listen</th></tr>")
            for sname, when in ent["sounds"].items():
                body.append(f"<tr><td><code>{e(sname)}</code></td><td>{e(when)}</td><td>{sound_player(sname)}</td></tr>")
            body.append("</table></div>")
        if ent.get("level_symbols"):
            body.append("<h4>Level map symbols</h4><p>" + " · ".join(
                f"<kbd>{e(k)}</kbd> {e(v)}" for k, v in ent["level_symbols"].items()) + "</p>")
        links = []
        for key, label in (("spawns", "Spawns"), ("spawned_by", "Spawned by")):
            if ent.get(key):
                links.append(f"{label}: " + ", ".join(f"<a href='#ent-{e(o)}'>{e(entities[o]['name'])}</a>" for o in ent[key]))
        files = ", ".join(f"<code>{e(f)}</code>" for f in [f"design/entities/{eid}.yaml"] + ent.get("files", []))
        body.append(f"<p class='mute'>{' · '.join(links + ['Files: ' + files])}</p></div>")

    # Run loop
    foes = enemy_symbols(entities)
    body.append(f"<h2 id='run'>Run loop</h2><p class='mute'>Source: <code>design/run.yaml</code> — in code: "
                f"<code>GameData.RUN</code></p><p>{e(run['description'])}</p><div class='tbl'><table>"
                "<tr><th>Name</th><th>Value</th><th>Meaning</th></tr>")
    for stat, spec in run["stats"].items():
        body.append(f"<tr><td><code>{e(stat)}</code></td><td class='num'>{spec['value']} {e(spec.get('unit', ''))}</td>"
                    f"<td>{e(spec['description'])}</td></tr>")
    body.append("</table></div><h4>Level order</h4><div class='tbl'><table><tr><th>#</th><th>Level</th><th>Map</th>"
                "<th>Kill quota</th><th>Enemies in map</th><th>Notes</th></tr>")
    for i, lv in enumerate(run["levels"], 1):
        count = sum(r.count(c) for r in levels[lv["map"]] for c in foes)
        body.append(f"<tr><td class='num'>{i}</td><td><b>{e(lv['title'])}</b></td><td><a href='#map-{e(lv['map'])}'>"
                    f"<code>{e(lv['map'])}</code></a></td><td class='num'>{lv['kill_quota']}</td><td class='num'>{count}</td>"
                    f"<td>{e(lv.get('note', ''))}</td></tr>")
    body.append("</table></div>")

    body.append("<h2 id='levels'>Levels</h2><p class='mute'>Source: <code>design/levels/*.txt</code> — one character per "
                "block (24×24 px). Rendered with the exact tiles and variant formula the game uses.</p>")
    legend = {sym: (ent["name"], what) for ent in entities.values() for sym, what in ent.get("level_symbols", {}).items()}
    in_run = {lv["map"]: (i, lv) for i, lv in enumerate(run["levels"], 1)}
    for name, rows in levels.items():
        T = entities["block"]["stats"]["size"]["value"]
        preview = render_level(rows, sprites, entities["block"]["stats"]["grass_clearance"]["value"], entities)
        data = "data:image/png;base64," + base64.b64encode(png_bytes(preview)).decode()
        counts = {sym: sum(r.count(sym) for r in rows) for sym in legend}
        title = f"Level {in_run[name][0]}: {in_run[name][1]['title']} — {name}" if name in in_run else f"{name} (not in the run)"
        quota = f" · kill quota {in_run[name][1]['kill_quota']}" if name in in_run else ""
        body.append(f"<div class='card' id='map-{e(name)}'><h3 style='margin-top:0'>{e(title)}</h3>"
                    f"<p class='mute'>{len(rows[0])} × {len(rows)} blocks ({len(rows[0]) * T} × {len(rows) * T} px) · "
                    f"{sum(counts.get(c, 0) for c in foes)} enemies{quota}</p><div class='tbl'><img class='px' src='{data}' "
                    f"style='width:{preview.width * 2}px;max-width:none;border-radius:6px'></div><p>"
                    + " · ".join(f"<kbd>{e(sym)}</kbd> {e(what)} <span class='mute'>×{counts[sym]}</span>"
                                 for sym, (_, what) in legend.items()) + "</p></div>")

    body.append("<h2 id='palette'>Master palette</h2><div class='grid'>")
    for cname, hexv in master.items():
        body.append(f"<div class='sw'><div style='background:{hexv}'></div><p><b>{e(cname)}</b><br>{hexv}</p></div>")
    body.append("</div><h2>Palette sets</h2>")
    for sname, symbols in sets.items():
        body.append(f"<div class='card'><h3 style='margin-top:0'>{e(sname)}</h3>")
        for sym, cname in symbols.items():
            body.append(f"<span class='sym'><i style='background:{master[cname]}'></i>{e(sym)} = {e(cname)}</span>")
        body.append("</div>")

    body.append("<h2 id='sprites'>Sprites</h2>")
    for spec, img, layout in sprites:
        name, (fw, fh) = spec["name"], spec["frame"]
        s = spec.get("preview_scale", 6)
        body.append(f"<div class='card'><h3 style='margin-top:0'>{e(name)}</h3><p class='mute'>{e(spec.get('description', ''))}</p>"
                    f"<p class='mute'>frame {fw}×{fh} · palette <b>{e(spec['palette'])}</b> · sheet {img.width}×{img.height}</p>")
        if spec.get("reference"):
            ref_name = f"{name}{Path(spec['reference']).suffix}"
            body.append(f"<p class='mute'>Look reference (art style source):<br><img src='references/{e(ref_name)}' "
                        "style='max-height:220px;border-radius:6px;border:1px solid #0003'></p>")
        for aname, row, count, fps, loop in layout:
            kf = f"k_{name}_{aname}"
            keyframes.append(f"@keyframes {kf}{{from{{background-position-x:0}}to{{background-position-x:-{count * fw * s}px}}}}")
            dur = count / fps
            body.append(f"<div class='anim'><div class='frame px' style='width:{fw * s}px;height:{fh * s}px;"
                        f"background-image:url({uri[name]});background-size:{img.width * s}px {img.height * s}px;"
                        f"background-position-y:-{row * fh * s}px;animation:{kf} {dur:.3f}s steps({count}) infinite'></div>"
                        f"{e(aname)} · {count}f @ {fps}fps{'' if loop else ' · once'}</div>")
        body.append(f"<p><img class='px' src='{uri[name]}' style='width:{img.width * 4}px;background:#0003'></p>")
        if spec.get("_muzzles"):
            body.append("<p class='mute'>gun tip per frame (from colors " + e(spec["muzzle_symbols"]) + "): " + "; ".join(
                f"{e(a)} " + " ".join("—" if t is None else f"({t[0]},{t[1]})" for t in tips) for a, tips in spec["_muzzles"].items()) + "</p>")
        if spec.get("anchors"):
            body.append("<p class='mute'>anchors: " + ", ".join(f"{e(k)} = {v}" for k, v in spec["anchors"].items()) + "</p>")
        body.append("</div>")

    body.append("<h2 id='storyboards'>Storyboards</h2>")
    for sb in storyboards:
        body.append(f"<h3>{e(sb['title'])}</h3><p class='mute'>{e(sb.get('description', ''))}</p><div class='panels'>")
        for i, panel in enumerate(sb["panels"], 1):
            shot = panel.get("shot")
            if shot:
                sname, aname, fidx = shot.split("/")
                sp, img, lay = sprite_index[sname]
                fw, fh = sp["frame"]
                s = 5 if max(fw, fh) <= 24 else (4 if max(fw, fh) <= 32 else 2)
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

    body.append("<h2 id='audio'>Audio</h2>")
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
        for spec, _img, _layout in sprites:
            if spec.get("reference") and not (ROOT / spec["reference"]).is_file():
                raise SpecError(f"{spec['name']}: reference image {spec['reference']!r} not found")
        audio_spec = load_yaml(ROOT / "audio" / "catalog.yaml")
        controls, entities = load_design(sprites, audio_spec)
        levels = load_levels(entities)
        run = load_run(levels, entities)
        storyboards = load_storyboards(sprites, audio_spec)
        game_data = game_data_gd(controls, entities, sprites, levels, run)
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
        gd = ROOT / GAME_DATA
        if not gd.exists() or gd.read_bytes() != game_data:
            bad.append(f"{GAME_DATA} is out of date with design/")
        if bad:
            sys.exit("CHECK FAILED:\n  " + "\n  ".join(sorted(set(bad))))
        print(f"OK - {len(outputs)} sprites and game data match specs and lock.")
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

    (ROOT / GAME_DATA).parent.mkdir(parents=True, exist_ok=True)
    (ROOT / GAME_DATA).write_bytes(game_data)

    DOCS.mkdir(exist_ok=True)
    for spec, _img, _layout in sprites:
        if spec.get("reference"):
            ref = ROOT / spec["reference"]
            (DOCS / "references").mkdir(exist_ok=True)
            (DOCS / "references" / f"{spec['name']}{ref.suffix}").write_bytes(ref.read_bytes())
    (DOCS / "catalog.html").write_bytes(
        catalog_html(master, sets, sprites, storyboards, audio_spec, controls, entities, levels, run).encode("utf-8"))

    print(f"Built {len(outputs)} sprites ({', '.join(outputs)}), {len(entities)} entities, {len(controls)} controls, "
          f"{len(levels)} levels. "
          f"Accepted changes: {', '.join(changed) or 'none'}.")
    print("Catalog: docs/catalog.html")


if __name__ == "__main__":
    main()
