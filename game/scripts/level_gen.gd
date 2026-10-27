class_name LevelGen
extends RefCounted
## Endless level generator. Every level of a run is built here from the run's depth (how many
## fights were cleared), so each run plays differently and every level is a bit bigger, fuller
## and tougher than the last. All numbers: design/run.yaml (GameData.RUN).
##
## Layout of a run: fight, fight, fight, BOSS (a Brute), HUB, fight, fight, fight, BOSS, HUB, ...
## Returns {rows: Array[String], title, kill_quota, kind: "level" | "boss" | "hub"}, with the same
## symbols as design/levels/*.txt (# . P E K B O X) plus the hub stations A (ammo) H (health and
## lives) G (grenades).
##
## Terrain has real height: stairs up to hills, stairs down into valleys, narrow gaps, steps, and
## hollow earth towers with a doorway at the bottom and tiers inside to climb (nothing floats in the air).
## Enemies and barrels are placed on ANY standable spot - ground, hill tops, valley floors,
## platforms - spread over the different heights, not along one line.

const ROWS := 17  # same height as the hand-made maps
const GROUND_MIN := 5  # highest ground top row (hill tops)
const GROUND_MAX := 13  # lowest ground top row (valley floors)
const PIT_FLOOR := 14  # lowest a gap floor may go (gaps are 2 deep, so ground rows 13+ dig less)
const ARENA := 40  # a boss level ends with this many flat columns: the walled arena (walls included)
const ARENA_GROUND := 12  # its ground top row (leaves room for the gallery above the Brute)
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
	var towers := 0 if boss else mini(R.platform_towers_base + int(R.platform_towers_per_depth * tier), R.platform_towers_max)
	var walls := []  # shaft cells of the towers: back wall shows there
	_towers(grid, heights, rng, towers, START_COLS + 2, width - (ARENA + 4 if boss else 16), walls)

	var start_row: int = heights[3] - 1
	grid[start_row][3] = "P"
	var exit_x := width - 9 if boss else width - 5  # a boss level's truck waits inside the arena
	grid[heights[exit_x] - 1][exit_x] = "X"  # the truck is 5 blocks long, centred on this tile

	var taken := {}  # Vector2i(x, row) of things already standing somewhere
	var enemies := mini(R.min_enemies + R.enemies_per_depth * tier + rng.randi_range(0, 3), R.max_enemies)
	var kamikaze_share := minf(R.kamikaze_base + R.kamikaze_per_depth * tier, R.kamikaze_max)
	var vest_share := minf(R.vest_base + R.vest_per_depth * tier, R.vest_max)
	var helmet_share := minf(R.helmet_base + R.helmet_per_depth * tier, R.helmet_max)
	var placed := enemies
	var unbreakable := []  # cells that nothing can break (boss arena)
	var stone := []  # cells drawn as rock whatever the biome (boss arena walls and platforms)
	var arena_info := {}
	if boss:
		enemies = 0  # the Brute alone: the Bro arrives straight in his arena
		placed = 0
		var arena := _arena(grid, width, rng, unbreakable, stone)
		var bx: int = arena.boss_col
		grid[ARENA_GROUND - 1][bx] = "B"
		for dx in range(-3, 4):
			taken[Vector2i(bx + dx, ARENA_GROUND - 1)] = true
		for x in range(width - ARENA, width - ARENA + 4):  # the doorway and the first steps inside stay clear
			taken[Vector2i(x, ARENA_GROUND - 1)] = true
		_barrels(grid, taken, rng, 3, width - ARENA + 4, width - 6)
		arena_info = arena
		var supplies := ["A", "G"]  # an ammo box and a grenade box on the flat ground in front of the doorway
		var sx := width - ARENA - 2
		while supplies.size() > 0 and sx > START_COLS:
			if grid[heights[sx] - 1][sx] == ".":
				grid[heights[sx] - 1][sx] = supplies.pop_back()
				taken[Vector2i(sx, heights[sx] - 1)] = true
				sx -= 2
			sx -= 1
		placed += 1
	else:
		_barrels(grid, taken, rng, R.barrel_clusters_base + int(R.barrel_clusters_per_depth * tier), 16, width - 10)
	var crate := _pick(_spots_by_row(grid, taken, START_COLS + 4, width - ARENA - 6 if boss else width - 12, 1), rng)  # the random crate (upgrade or another Bro)
	if crate.x >= 0:
		grid[crate.y][crate.x] = "U"
		_take(taken, crate, 1)
	var spots := _spots_by_row(grid, taken, 14, width - 10, 1)
	for i in enemies:
		var spot := _pick(spots, rng)
		if spot.x < 0:
			placed -= enemies - i
			break
		var roll := rng.randf()
		var kind := "E"
		if roll < kamikaze_share:
			kind = "K"
		elif roll < kamikaze_share + helmet_share:
			kind = "M"
		elif roll < kamikaze_share + helmet_share + vest_share:
			kind = "V"
		grid[spot.y][spot.x] = kind
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
		"walls": walls,
		"unbreakable": unbreakable,
		"stone": stone,
		"arena": arena_info,
	}


## Where a run begins: a rocky stretch of ground. The Bro cards open over it at once (main.gd), all of them.
static func start_zone() -> Dictionary:
	var width := 44
	var floor_row := 11
	var rows: Array = []
	for y in ROWS:
		var row := ""
		for x in width:
			var wall := false  # no side walls: nothing for a truck to drive through
			var step: bool = (x >= 14 and x < 19 and y == floor_row - 1) or (x >= 15 and x < 18 and y == floor_row - 2) or (x >= 24 and x < 27 and y == floor_row - 1)
			row += "#" if wall or y >= floor_row or step else "."
		rows.append(row)
	var put := func(x: int, ch: String):
		var r: String = rows[floor_row - 1]
		rows[floor_row - 1] = r.substr(0, x) + ch + r.substr(x + 1)
	put.call(6, "P")
	return {"rows": rows, "title": "Start", "kill_quota": 0, "kind": "start", "depth": -1, "biome": "stone"}


## The safe house between boss levels: a flat room with walls, the three stations and the door.
static func hub() -> Dictionary:
	var width := 38
	var floor_row := 11
	var rows: Array = []
	for y in ROWS:
		var row := ""
		for x in width:
			row += "#" if y >= floor_row else "."  # no side walls: the trucks drive in and out through open air
		rows.append(row)
	var put := func(x: int, ch: String):
		var r: String = rows[floor_row - 1]
		rows[floor_row - 1] = r.substr(0, x) + ch + r.substr(x + 1)
	put.call(4, "P")
	put.call(9, "A")  # three tiles apart: close together, but never in reach of two at once
	put.call(12, "H")
	put.call(15, "G")
	put.call(20, "X")
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
	var arena_set := false
	while x < width:
		var left := width - x
		var seg := rng.randi_range(4, 10)
		if boss and not arena_set and left <= ARENA + 20:  # walk the ground to the arena's height, then it is flat all the way
			arena_set = true
			var up := _stairs(heights, x, h, ARENA_GROUND, rng, width)
			x = up[0]
			h = up[1]
			last_was_gap = false
			continue
		if x < START_COLS or left <= END_COLS + 6 or (boss and (arena_set or left <= ARENA)):
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


## Earth towers standing on the ground - nothing floats. A tower is a tall wall of earth (two blocks thick) with
## shelves of earth growing out of it like stairs: the lowest is long, each one above is shorter, three rows
## higher. The side facing away from the wall is open, so he just walks in at the bottom and climbs shelf by
## shelf (a step stone at the end of each shelf makes every climb one normal jump), and the top shelf ends at
## the top of the wall so he can climb out over it. The dark back wall shows behind the whole thing (`walls`
## lists those cells). Enemies and barrels are placed on the shelves like anywhere else.
static func _towers(grid: Array, heights: PackedInt32Array, rng: RandomNumberGenerator, count: int, from: int, to: int, walls: Array) -> void:
	for t in count:
		for attempt in 40:
			var inner := rng.randi_range(8, 10)  # shelf depth, from the open end to the wall
			var w := inner + 2
			var x0 := rng.randi_range(from, maxi(from, to - w))
			if x0 < 4 or x0 + w + 4 >= heights.size():
				continue
			var g: int = heights[x0]
			var flat := true
			for x in range(x0 - 3, x0 + w + 3):
				if heights[x] != g or _gaps.has(x):
					flat = false
					break
			var tiers := 2 if g >= 11 and rng.randf() < 0.6 else 1
			var top := g - 3 * tiers - 3
			if not flat or top < 2 or not _free_box(grid, x0, top - 1, w, g - top + 1):
				continue
			var far_right := rng.randf() < 0.5
			var col := func(c: int) -> int:  # c = blocks in from the open end (the wall is at c = inner, inner + 1)
				return x0 + c if far_right else x0 + w - 1 - c
			for y in range(top, g):
				for c in range(inner, w):
					grid[y][col.call(c)] = "#"
				for c in inner:
					walls.append(Vector2i(col.call(c), y))
			var shelf := inner - 2  # length of the lowest shelf
			for k in tiers:
				var row := g - 3 - 3 * k
				for c in range(inner - shelf, inner):
					grid[row][col.call(c)] = "#"
				grid[row + 2][col.call(inner - shelf - 1)] = "#"  # step stone at its open end, on the level below
				if k == tiers - 1:
					grid[row - 1][col.call(inner - 1)] = "#"  # stone against the wall: the way out over its top
				shelf -= 2
			break


## The boss arena's gallery, built from column `a` on ground row `g`. From the left: a hill (stairs up, a
## plateau where the Bro stands), a few steps down, and then the Brute's floor with a bridge of earth over
## it, one block thick, reaching out from a tower wall toward the plateau. Barrels stand on the bridge.
## The Bro, standing on the plateau, shoots the bridge across the gap, block by block (one shot each);
## every barrel loses its support in turn, falls onto the Brute's head and blows up. Everything is earth
## down to the ground, nothing floats. Returns the column the Brute stands in.
static func _gallery(grid: Array, a: int, g: int) -> int:
	var fill := func(x: int, top: int) -> void:  # column x filled from row `top` down to the ground
		for y in range(top, g):
			grid[y][x] = "#"
	for k in range(1, 7):  # stairs up: tread 2, riser 1
		fill.call(a + 2 * k - 2, g - k)
		fill.call(a + 2 * k - 1, g - k)
	var p := a + 14  # last column of the plateau (top row g - 7: the Bro's feet are in row g - 8)
	for x in range(a + 12, p + 1):
		fill.call(x, g - 7)
	for k in range(6, 0, -1):  # steps down, tread 1
		fill.call(p + 7 - k, g - k)
	for x in range(p + 7, p + 15):  # the bridge, row g - 8, 8 blocks
		grid[g - 8][x] = "#"
	for x in [p + 15, p + 16]:  # the tower wall it grows out of
		fill.call(x, g - 9)
	for x in [p + 9, p + 11, p + 13]:  # barrels, a block apart so they fall one by one
		grid[g - 9][x] = "O"
	return p + 11


## The boss arena (the last ARENA columns, flat ground): rock walls all round and open sky above. The left wall has a
## two-block doorway at ground level - the way the Bro walks in; main.gd shuts it with two unbreakable blocks
## once he is inside. The right wall (two thick) is where the Brute's kamikazes come in; nothing breaks it. Three
## floating rock platforms a hop apart climb into each top corner. The two bottom rows of the whole level, the
## walls, the platforms and a few blocks of the floor cannot be broken. The Brute stands in the middle.
## Returns {door: [cells], trigger: column, entry_col, boss_col}.
static func _arena(grid: Array, width: int, rng: RandomNumberGenerator, unbreakable: Array, stone: Array) -> Dictionary:
	var a := width - ARENA
	var g := ARENA_GROUND
	for x in width:
		for y in [ROWS - 2, ROWS - 1]:
			unbreakable.append(Vector2i(x, y))
	var solid := func(x: int, y: int) -> void:  # a rock block that nothing breaks
		grid[y][x] = "#"
		unbreakable.append(Vector2i(x, y))
		stone.append(Vector2i(x, y))
	for y in range(0, g - 2):  # left wall, with the doorway (g-2, g-1) left open
		solid.call(a, y)
	for y in range(g, ROWS):  # ...and the earth under it
		unbreakable.append(Vector2i(a, y))
	for x in [width - 2, width - 1]:  # right wall
		for y in ROWS:
			solid.call(x, y)
	var lo := a + 1
	var hi := width - 3  # the floor between the walls
	for step in [[g - 2, a + 9], [g - 4, a + 5], [g - 6, a + 2]]:
		for k in 3:
			solid.call(step[1] + k, step[0])  # left corner
			solid.call(lo + hi - (step[1] + k), step[0])  # and its mirror image in the right one
	var boss_col := (lo + hi) / 2
	for x in range(lo + 1, hi):
		if absi(x - boss_col) > 2 and rng.randf() < 0.12:
			unbreakable.append(Vector2i(x, g))
			unbreakable.append(Vector2i(x, g + 1))
	return {"door": [Vector2i(a, g - 2), Vector2i(a, g - 1)], "trigger": a + 3, "entry_col": hi, "boss_col": boss_col}


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
