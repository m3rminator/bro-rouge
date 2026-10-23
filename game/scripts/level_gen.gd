class_name LevelGen
extends RefCounted
## Endless level generator. Every level of a run is built here from the run's depth (how many
## fights were cleared), so each run plays differently and every level is a bit bigger, fuller
## and tougher than the last. All numbers: design/run.yaml (GameData.RUN).
##
## Layout of a run: fight, fight, BOSS (a Brute), HUB, fight, fight, BOSS, HUB, ...
## Returns {rows: Array[String], title, kill_quota, kind: "level" | "boss" | "hub"}, with the same
## symbols as design/levels/*.txt (# . P E K B O X) plus the hub stations A (ammo) H (health and
## lives) G (grenades).
##
## Terrain has real height: stairs up to hills, stairs down into valleys, narrow gaps, steps, and
## towers of floating platforms (each tier two blocks above the last, reachable with a jump).
## Enemies and barrels are placed on ANY standable spot - ground, hill tops, valley floors,
## platforms - spread over the different heights, not along one line.

const ROWS := 17  # same height as the hand-made maps
const GROUND_MIN := 5  # highest ground top row (hill tops)
const GROUND_MAX := 13  # lowest ground top row (valley floors)
const PIT_FLOOR := 14  # lowest a gap floor may go (gaps are 2 deep, so ground rows 13+ dig less)
const START_COLS := 12  # flat safe run-up at the left edge
const END_COLS := 10  # flat run before the exit
const STEP_WIDTH := 3  # width of one stair tread
const TITLES := ["Jungle Outpost", "Ruined Camp", "River Crossing", "Overgrown Road", "Bandit Ridge",
		"Supply Depot", "Burnt Village", "Hidden Trail", "Rotting Bridge", "Smuggler's Run"]
const R := GameData.RUN

static var _gaps := {}  # columns that are gap floors in the level being built


static func is_boss(depth: int) -> bool:
	return depth % R.boss_every == R.boss_every - 1


## The level for fight number `depth` (0 = the first one).
static func combat(depth: int, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var boss := is_boss(depth)
	var tier := depth / R.boss_every * R.boss_every  # difficulty only steps up when a whole loop is done
	var width := mini(R.width_base + R.width_per_depth * tier, R.width_max)
	if boss:
		width = mini(R.boss_width + R.width_per_depth * (depth / R.boss_every), R.width_max)
	_gaps = {}
	var heights := _terrain(width, boss, rng)
	var grid: Array = []
	for y in ROWS:
		var row := []
		for x in width:
			row.append("#" if y >= heights[x] else ".")
		grid.append(row)
	var towers := mini(R.platform_towers_base + int(R.platform_towers_per_depth * tier), R.platform_towers_max)
	_platform_towers(grid, heights, rng, towers, START_COLS + 2, width - (40 if boss else 16))

	var start_row: int = heights[3] - 1
	grid[start_row][3] = "P"
	grid[heights[width - 4] - 1][width - 4] = "X"

	var taken := {}  # Vector2i(x, row) of things already standing somewhere
	var enemies := mini(R.min_enemies + R.enemies_per_depth * tier + rng.randi_range(0, 3), R.max_enemies)
	var kamikaze_share := minf(R.kamikaze_base + R.kamikaze_per_depth * tier, R.kamikaze_max)
	var placed := enemies
	if boss:
		var bx := width - 24
		grid[heights[bx] - 1][bx] = "B"
		for dx in range(-2, 3):
			taken[Vector2i(bx + dx, heights[bx] - 1)] = true
		_barrels(grid, taken, rng, 5, width - 48, width - 12)
		placed += 1
	else:
		_barrels(grid, taken, rng, R.barrel_clusters_base + int(R.barrel_clusters_per_depth * tier), 16, width - 10)
	var spots := _spots_by_row(grid, taken, 14, width - 10, 1)
	for i in enemies:
		var spot := _pick(spots, rng)
		if spot.x < 0:
			placed -= enemies - i
			break
		grid[spot.y][spot.x] = "K" if rng.randf() < kamikaze_share else "E"
		_take(taken, spot, 1)
		_drop(spots, spot)

	var rows: Array = []
	for row in grid:
		rows.append("".join(row))
	var quota := placed if boss else mini(placed, ceili(placed * minf(R.quota_base + R.quota_per_depth * tier, R.quota_max)))
	return {
		"rows": rows,
		"title": "Brute Arena" if boss else TITLES[rng.randi() % TITLES.size()],
		"kill_quota": quota,
		"kind": "boss" if boss else "level",
		"depth": depth,
		"biome": "stone" if rng.randf() < R.stone_biome_chance else "earth",
	}


## The safe house between boss levels: a flat room with walls, the three stations and the door.
static func hub() -> Dictionary:
	var width := 56
	var floor_row := 11
	var rows: Array = []
	for y in ROWS:
		var row := ""
		for x in width:
			var wall: bool = x < 2 or x >= width - 2
			row += "#" if wall or y >= floor_row else "."
		rows.append(row)
	var put := func(x: int, ch: String):
		var r: String = rows[floor_row - 1]
		rows[floor_row - 1] = r.substr(0, x) + ch + r.substr(x + 1)
	put.call(6, "P")
	put.call(16, "A")
	put.call(26, "H")
	put.call(36, "G")
	put.call(48, "X")
	return {"rows": rows, "title": "Safe House", "kill_quota": 0, "kind": "hub", "depth": -1}


# ---------------------------------------------------------------- terrain

## Ground top row for every column: flat stretches, steps, narrow gaps (only where they are
## shallow enough to climb out of), hills and valleys with stairs both ways. Boss arenas keep
## their last 34 columns flat and have no gaps or valleys.
static func _terrain(width: int, boss: bool, rng: RandomNumberGenerator) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(width)
	var h := 11
	var x := 0
	var last_was_gap := true  # no gap right at the start
	while x < width:
		var left := width - x
		var seg := rng.randi_range(4, 10)
		if x < START_COLS or left <= END_COLS + 6 or (boss and left <= 34):
			seg = mini(seg + 2, left)
			for i in seg:
				heights[x + i] = h
			x += seg
			last_was_gap = false
			continue
		var roll := rng.randf()
		if last_was_gap:
			roll = 0.0  # level ground after a gap, so its far edge is the same height as the near one
		var room := left - END_COLS - 8  # columns a big structure may use
		if roll < 0.14:  # flat stretch
			for i in mini(seg, left):
				heights[x + i] = h
			x += mini(seg, left)
			last_was_gap = false
		elif roll < 0.30:  # step up or down by one or two blocks
			h = clampi(h + rng.randi_range(-2, 2), GROUND_MIN, GROUND_MAX)
			for i in mini(seg, left):
				heights[x + i] = h
			x += mini(seg, left)
			last_was_gap = false
		elif roll < 0.42 and not boss and not last_was_gap:  # gap: 3 wide, 2 deep (climbable)
			for i in 3:
				heights[x + i] = mini(h + 2, PIT_FLOOR + 1)
				_gaps[x + i] = true
			x += 3
			last_was_gap = true
		elif roll < 0.72 and room > 40:  # hill: stairs up, a plateau, stairs down
			var h0 := h
			var top := maxi(GROUND_MIN, h0 - rng.randi_range(3, 7))
			var at := _stairs(heights, x, h, top, rng, width)
			x = at[0]
			h = at[1]
			var plateau := mini(rng.randi_range(4, 9), width - x)
			for i in plateau:
				heights[x + i] = h
			x += plateau
			at = _stairs(heights, x, h, h0, rng, width)
			x = at[0]
			h = at[1]
			last_was_gap = false
		elif roll < 0.96 and room > 40 and not boss:  # valley: stairs down, a floor, stairs back up
			var h0 := h
			var bottom := mini(GROUND_MAX, h0 + rng.randi_range(3, 6))
			if bottom - h0 < 2:
				bottom = mini(GROUND_MAX, h0 + 2)
			var at := _stairs(heights, x, h, bottom, rng, width)
			x = at[0]
			h = at[1]
			var floor_w := mini(rng.randi_range(6, 11), width - x)
			for i in floor_w:
				heights[x + i] = h
			x += floor_w
			at = _stairs(heights, x, h, h0, rng, width)
			x = at[0]
			h = at[1]
			last_was_gap = false
		else:
			for i in mini(seg, left):
				heights[x + i] = h
			x += mini(seg, left)
			last_was_gap = false
	return heights


## Stairs from height `h` to `target` (treads STEP_WIDTH wide, risers of 1-2 blocks). Returns [x, h].
static func _stairs(heights: PackedInt32Array, x: int, h: int, target: int, rng: RandomNumberGenerator, width: int) -> Array:
	while h != target and x < width:
		var rise := mini(absi(target - h), rng.randi_range(1, 2))
		h += rise * signi(target - h)
		for i in STEP_WIDTH:
			if x < width:
				heights[x] = h
				x += 1
	return [x, h]


## Towers of floating platforms: one block thick, 4-7 wide, with two blocks of walking room under
## the first tier. A single stone block at its foot is the first step up (one block), the tier is
## two blocks above that, and every further tier is two blocks higher again and one column of gap
## sideways - each climb is one normal jump. Only placed where there is free air all around.
static func _platform_towers(grid: Array, heights: PackedInt32Array, rng: RandomNumberGenerator, count: int, from: int, to: int) -> void:
	for t in count:
		for attempt in 30:
			var x := rng.randi_range(from, maxi(from, to))
			if x + 10 >= heights.size() or x < 4 or _gaps.has(x - 1) or _gaps.has(x) or _gaps.has(x + 1) or heights[x - 1] != heights[x] or heights[x + 1] != heights[x]:
				continue
			var dir := 1 if rng.randf() < 0.5 else -1
			var ground: int = heights[x]
			var row := ground - 3
			var tiers := rng.randi_range(2, 4)
			var w := rng.randi_range(4, 7)
			var x0 := x + 1 if dir == 1 else x - w
			var stone := x0 - 1 if dir == 1 else x0 + w
			if stone < 2 or stone >= heights.size() - 2 or heights[stone] != ground or _gaps.has(stone):
				continue
			var placed_any := false
			var prev_w := w
			for tier in tiers:
				if tier > 0:
					w = rng.randi_range(4, 7)
					x0 = x0 + prev_w + 1 if dir == 1 else x0 - w - 1
				if row < 3 or not _free_box(grid, x0, row - 2, w, 5):
					break
				for i in w:
					grid[row][x0 + i] = "#"
				if tier == 0:
					grid[ground - 1][stone] = "#"
				placed_any = true
				prev_w = w
				row -= 2
			if placed_any:
				break


## All of columns x..x+w-1, rows y..y+h-1 are air (and inside the map).
static func _free_box(grid: Array, x: int, y: int, w: int, h: int) -> bool:
	if x < 2 or x + w >= grid[0].size() - 2 or y < 1 or y + h > ROWS:
		return false
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if grid[yy][xx] != ".":
				return false
	return true


# ---------------------------------------------------------------- placement

## Every spot a `size`-wide thing can stand on (two blocks of air above it, solid under it and
## under both neighbours so nothing stands on a ledge edge), grouped by row.
static func _spots_by_row(grid: Array, taken: Dictionary, from: int, to: int, size: int) -> Dictionary:
	var by_row := {}
	for y in range(2, ROWS - 1):
		for x in range(from, mini(to, grid[0].size() - size - 1)):
			var ok := true
			for dx in range(-1, size + 1):
				if grid[y + 1][x + dx] != "#" or grid[y][x + dx] != ".":
					ok = false
					break
				if dx >= 0 and dx < size and (grid[y - 1][x + dx] != "." or grid[y - 2][x + dx] != "." or taken.has(Vector2i(x + dx, y))):
					ok = false
					break
			if ok:
				if not by_row.has(y):
					by_row[y] = []
				by_row[y].append(Vector2i(x, y))
	return by_row


## A random spot, with every height (row) equally likely to be chosen first - so the ground does
## not swallow everything - then a random column on that row. (-1, -1) if nothing is left.
static func _pick(by_row: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var rows := by_row.keys().filter(func(r): return not by_row[r].is_empty())
	if rows.is_empty():
		return Vector2i(-1, -1)
	var weights := rows.map(func(r): return sqrt(float(by_row[r].size())))
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	var chosen: int = rows[0]
	for i in rows.size():
		roll -= weights[i]
		if roll <= 0.0:
			chosen = rows[i]
			break
	var list: Array = by_row[chosen]
	return list[rng.randi() % list.size()]


## Keep things a column apart: remove the neighbours of a used spot from the candidates.
static func _drop(by_row: Dictionary, spot: Vector2i) -> void:
	var list: Array = by_row[spot.y]
	for dx in [-1, 0, 1]:
		list.erase(Vector2i(spot.x + dx, spot.y))


static func _take(taken: Dictionary, spot: Vector2i, size: int) -> void:
	for dx in range(-1, size + 1):
		taken[Vector2i(spot.x + dx, spot.y)] = true


## Clusters of 1-3 barrels side by side, on any standable spot.
static func _barrels(grid: Array, taken: Dictionary, rng: RandomNumberGenerator, clusters: int, from: int, to: int) -> void:
	for i in clusters:
		var size := rng.randi_range(1, 3)
		var spots := _spots_by_row(grid, taken, from, to, size)
		var spot := _pick(spots, rng)
		if spot.x < 0:
			continue
		for dx in size:
			grid[spot.y][spot.x + dx] = "O"
		_take(taken, spot, size)
