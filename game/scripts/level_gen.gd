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

const ROWS := 17  # the height of the hand-made maps, boss arenas, the start zone and the hub
static var _rows := ROWS  # the level being built (tall fight levels: run.yaml level_rows)
static var _shift := 0  # rows added above the old 17: the ground sits this much lower
const GROUP_REACH := 3  # soldiers on one row this many columns apart or closer count as standing together
const GROUND_MIN := 5  # highest ground top row (hill tops)
const GROUND_MAX := 13  # lowest ground top row (valley floors)
const PIT_FLOOR := 14  # lowest a gap floor may go (gaps are 2 deep, so ground rows 13+ dig less)
const ARENA := 40  # a boss level ends with this many flat columns: the walled arena (walls included)
const ARENA_GROUND := 12  # its ground top row (leaves room for the gallery above the Brute)
const START_COLS := 12  # flat safe run-up at the left edge
const END_COLS := 10  # flat run before the exit
const SKYLINE_MIN_WIDTH := 90  # levels at least this wide get a skyline (two towers over a chasm) and underground rooms
const GATE_CHASM := 16  # the chasm behind a gate temple
const CHASM_WIDTH := 14  # too wide to jump: the zipline between the tower tops is the way over
const STEP_WIDTH := 3  # width of one stair tread
const TITLES := ["Jungle Outpost", "Ruined Camp", "River Crossing", "Overgrown Road", "Bandit Ridge",
		"Supply Depot", "Burnt Village", "Hidden Trail", "Rotting Bridge", "Smuggler's Run"]
const R := GameData.RUN

static var _gaps := {}  # columns that are gap floors in the level being built
static var _reserved := {}  # columns taken by a skyline, so nothing else is built over it

## Every level draws one of these "personalities": how many skylines (towers over a chasm or a street) and underground
## rooms it gets per 100 columns, how many plain towers (multiplier), how much cover. It is what makes two levels feel
## different even when the terrain dice fall alike.
const PERSONAS := [
	{"name": "Skyline District", "sky": 1.7, "caves": 0.4, "towers": 0.4, "temples": 0.8, "barrels": 1.0, "titles": ["Rooftop Run", "High Wire", "Skyline Sprint", "Tower Row"]},
	{"name": "Underground Network", "sky": 0.5, "caves": 1.8, "towers": 0.6, "temples": 0.8, "barrels": 1.3, "titles": ["Mole Tunnels", "Under the Camp", "Burrow Road", "Deep Cellar"]},
	{"name": "Jungle Sprawl", "sky": 0.9, "caves": 0.7, "towers": 1.0, "temples": 1.3, "barrels": 0.8, "titles": ["Overgrown Road", "Hidden Trail", "Vine Ridge", "Canopy Walk"]},
	{"name": "Fortified Ridge", "sky": 1.1, "caves": 1.0, "towers": 1.0, "temples": 1.3, "barrels": 1.6, "titles": ["Bandit Ridge", "Supply Depot", "Burnt Village", "Smuggler's Run"]},
]


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
	_reserved = {}
	_rows = ROWS if boss else R.level_rows  # fight levels are tall: room for temples and high hills
	_shift = _rows - ROWS
	var persona: Dictionary = PERSONAS[rng.randi() % PERSONAS.size()]
	var heights := _terrain(width, boss, rng)
	if _shift > 0:
		for x in width:
			heights[x] += _shift  # the ground sits near the bottom of the tall level
	var grid: Array = []
	for y in _rows:
		var row := []
		for x in width:
			row.append("#" if y >= heights[x] else ".")
		grid.append(row)
	var towers := 0 if boss else mini(int((R.platform_towers_base + R.platform_towers_per_depth * tier) * persona.towers), R.platform_towers_max)
	var walls := []  # shaft cells of the towers: back wall shows there
	var zips := []  # ziplines across the chasms: {a: Vector2i, b: Vector2i} (the cells the Bro stands on at each end)
	var extra := []  # enemy cells inside skyline streets, underground rooms and temples
	var stone := []  # cells drawn as rock whatever the biome (boss arena walls and platforms, temple floors)
	var ladders := []  # {x, top, bot}: a ladder in column x from the floor surface at row `bot` up to the one at row `top`
	var temple := {"crate": Vector2i(-1, -1), "tops": [], "zips": []}
	var gate := {"spots": [], "crate": Vector2i(-1, -1), "tops": [], "zips": []}
	if not boss:  # first, so nothing else is built where it stands
		gate = _temples(grid, heights, rng, 1, START_COLS + 6, width - END_COLS - 14, walls, stone, ladders, true)
		extra.append_array(gate.spots)
		zips.append_array(gate.zips)
	if not boss and width >= SKYLINE_MIN_WIDTH:
		var skylines := maxi(1, roundi(width / 100.0 * persona.sky * rng.randf_range(0.7, 1.3)))
		for i in skylines:
			extra.append_array(_skyline(grid, heights, rng, START_COLS + 6, width - END_COLS - 8, walls, zips, rng.randf() < 0.4))
		var rooms := maxi(1, roundi(width / 100.0 * persona.caves * rng.randf_range(0.7, 1.3)))
		for i in rooms:
			extra.append_array(_cave(grid, heights, rng, START_COLS + 6, width - END_COLS - 20, walls))
	if not boss:
		var temples := maxi(1, mini(int((R.temple_base + R.temple_per_depth * tier) * persona.temples), R.temple_max))
		temple = _temples(grid, heights, rng, temples - 1, START_COLS + 6, width - END_COLS - 14, walls, stone, ladders)
		extra.append_array(temple.spots)
		zips.append_array(temple.zips)
		temple.tops.append_array(gate.tops)
		if temple.crate.x < 0:
			temple.crate = gate.crate
	_towers(grid, heights, rng, towers, START_COLS + 2, width - (ARENA + 4 if boss else 16), walls)
	if not boss:
		_temple_zips(grid, temple.tops, zips)

	var start_row: int = heights[3] - 1
	grid[start_row][3] = "P"
	var exit_x := width - 9 if boss else width - 5  # a boss level's truck waits inside the arena
	grid[heights[exit_x] - 1][exit_x] = "X"  # the truck is 5 blocks long, centred on this tile

	var taken := {}  # Vector2i(x, row) of things already standing somewhere
	for l: Dictionary in ladders:  # nothing stands at a ladder's foot or where it lets out
		_take(taken, Vector2i(l.x, l.bot - 1), 1)
		_take(taken, Vector2i(l.x + l.step, l.top - 1), 1)
		_take(taken, Vector2i(l.x + 2 * l.step, l.top - 1), 1)
	var enemies := mini(R.min_enemies + R.enemies_per_depth * tier + rng.randi_range(0, 3), R.max_enemies)
	var kamikaze_share := minf(R.kamikaze_base + R.kamikaze_per_depth * tier, R.kamikaze_max)
	var vest_share := minf(R.vest_base + R.vest_per_depth * tier, R.vest_max)
	var helmet_share := minf(R.helmet_base + R.helmet_per_depth * tier, R.helmet_max)
	var placed := enemies
	var unbreakable := []  # cells that nothing can break (boss arena)
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
		_barrels(grid, taken, rng, int((R.barrel_clusters_base + R.barrel_clusters_per_depth * tier) * persona.barrels), 16, width - 10)
	var crate: Vector2i = temple.crate  # the random crate (upgrade or another Bro): up in a temple when there is one, with a soldier next to it
	if crate.x < 0:
		crate = _pick(_spots_by_row(grid, taken, START_COLS + 4, width - ARENA - 6 if boss else width - 12, 1), rng)
	if crate.x >= 0:
		grid[crate.y][crate.x] = "U"
		_take(taken, crate, 1)
	var spots := _spots_by_row(grid, taken, 14, width - 10, 1)
	var standing := {}  # Vector2i(x, row) of the soldiers placed so far, to keep the groups small
	for i in enemies:
		var spot := Vector2i(-1, -1)
		var limit := _group_limit(rng)  # this soldier may join a group of at most this many (1 = stands alone)
		for attempt in 12:
			spot = _pick(spots, rng)
			if spot.x < 0 or _group_size(standing, spot) <= limit:
				break
			spot = Vector2i(-1, -1)
		if spot.x < 0:
			if _pick(spots, rng).x < 0:  # nothing left at all
				placed -= enemies - i
				break
			placed -= 1  # no loose spot found for this one: he is left out
			continue
		standing[spot] = true
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

	for spot: Vector2i in extra:
		if grid[spot.y][spot.x] != "." or _group_size(standing, spot) > _group_limit(rng):
			continue  # streets and rooms obey the same group limit
		standing[spot] = true
		var roll := rng.randf()
		grid[spot.y][spot.x] = "V" if roll < vest_share + 0.15 else ("K" if roll < vest_share + 0.15 + kamikaze_share else "E")
		placed += 1
	for zip: Dictionary in zips:  # the blocks a zipline is fixed to can never be broken
		for end: Vector2i in [zip.a, zip.b]:
			unbreakable.append(end + Vector2i(0, 1))
			unbreakable.append(end + Vector2i(0, 2))
	var rows: Array = []
	for row in grid:
		rows.append("".join(row))
	var quota := placed if boss else mini(placed, ceili(placed * minf(R.quota_base + R.quota_per_depth * tier, R.quota_max)))
	return {
		"rows": rows,
		"title": "Brute Arena" if boss else (persona.titles + TITLES)[rng.randi() % (persona.titles.size() + TITLES.size())],
		"persona": persona.name,
		"kill_quota": quota,
		"kind": "boss" if boss else "level",
		"depth": depth,
		"biome": "stone" if rng.randf() < R.stone_biome_chance else "earth",
		"walls": walls,
		"zips": zips,
		"ladders": ladders,
		"gate": gate.zips.size() > 0,
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
	var width := 42
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
	put.call(18, "W")
	put.call(23, "X")
	return {"rows": rows, "title": "Safe House", "kill_quota": 0, "kind": "hub", "depth": -1}


# ---------------------------------------------------------------- terrain

## Ground top row for every column: flat stretches, steps, narrow gaps (only where they are
## shallow enough to climb out of), hills and valleys with stairs both ways. Boss arenas keep
## their last 34 columns flat and have no gaps or valleys.
static func _terrain(width: int, boss: bool, rng: RandomNumberGenerator) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(width)
	var gmin := GROUND_MIN if boss else GROUND_MIN - R.hill_extra  # tall levels let the hills rise higher
	var h := 11 if boss else rng.randi_range(10, 12)
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
			h = clampi(h + rng.randi_range(-2, 2), gmin, GROUND_MAX)
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
			var top := maxi(gmin, h0 - rng.randi_range(3, 7))
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


## Two towers with a chasm between them (it kills: there is no floor). The Bro cannot jump it, so he climbs the
## first tower's shelves, takes the zipline across from the top of its wall to the top of the second tower's wall
## and climbs down that one. Both towers have their wall on the chasm side and the open end facing away.
## The ground is levelled where it stands. Adds the zipline to `zips`.
static func _skyline(grid: Array, heights: PackedInt32Array, rng: RandomNumberGenerator, from: int, to: int, walls: Array, zips: Array, street: bool) -> Array:
	var inner := rng.randi_range(8, 9)
	var w := inner + 2
	var total := 2 * w + CHASM_WIDTH + 6  # the towers, the chasm and a little ground each side
	if to - from < total + 4:
		return []
	var x_start := -1
	var g := 0
	for attempt in 30:  # a spot where the ground on both sides is about as high as the towers will stand
		var x := rng.randi_range(from, to - total)
		if _span_reserved(x - 2, x + total + 2):
			continue
		var h: int = heights[x + total / 2]
		if h - _shift >= 8 and h - _shift <= 12 and absi(heights[x - 1] - h) <= 1 and absi(heights[x + total] - h) <= 1 and not _gaps.has(x - 1) and not _gaps.has(x + total):
			x_start = x
			g = h
			break
	if x_start < 0:
		return []
	var tiers := 2 if g - _shift >= 11 else 1
	var top := g - 3 * tiers - 3
	if top < 2:
		return []
	for x in range(x_start, x_start + total):  # level the ground
		for y in _rows:
			grid[y][x] = "#" if y >= g else "."
		heights[x] = g
		_gaps.erase(x)
	var xa := x_start + 3  # tower A: open end on its left, wall on the right
	_build_tower(grid, xa, g, inner, tiers, true, walls)
	var xb := xa + w + CHASM_WIDTH  # tower B: wall on its left
	_build_tower(grid, xb, g, inner, tiers, false, walls)
	for x in range(x_start - 2, x_start + total + 2):
		_reserved[x] = true
	var spots := []
	if street:  # no chasm: ground between the towers, with soldiers on it
		for x in range(xa + w + 2, xb - 1, 3):
			spots.append(Vector2i(x, g - 1))
	else:
		for x in range(xa + w, xb):  # the chasm: no floor at all
			for y in _rows:
				grid[y][x] = "."
			heights[x] = _rows
	zips.append({"a": Vector2i(xa + w - 1, top - 1), "b": Vector2i(xb, top - 1)})
	return spots


## Any column of x0..x1 already used by a skyline.
static func _span_reserved(x0: int, x1: int) -> bool:
	for x in range(x0, x1 + 1):
		if _reserved.has(x):
			return true
	return false


## Underground rooms: a trench ramp walks down from the ground (treads two wide, one block per step) into a
## two-block-high room under a roof of earth, with enemies inside (their cells are returned). The dark back
## wall shows in the room. Placed on flat ground that is clear above.
static func _cave(grid: Array, heights: PackedInt32Array, rng: RandomNumberGenerator, from: int, to: int, walls: Array) -> Array:
	var room_w := rng.randi_range(8, 18)
	var tunnel := rng.randf() < 0.5  # a tunnel has a ramp up on the far side too: a way along under the ground
	var length := 8 + room_w + (6 if tunnel else 0)  # ramp (three treads of two), the room, and the ramp out
	if to - from < length + 6:
		return []
	for attempt in 40:
		var x0 := rng.randi_range(from, to - length - 2)
		var g: int = heights[x0 + length / 2]
		if g - _shift > 12 or g - _shift < 6 or absi(heights[x0 - 3] - g) > 1 or absi(heights[x0 + length + 2] - g) > 1:
			continue
		var ok := true
		if _span_reserved(x0 - 2, x0 + length + 2):
			continue
		for x in range(x0 - 2, x0 + length + 2):  # bare terrain only: no tower, chasm or earlier room in the way
			if _gaps.has(x) or heights[x] >= _rows:
				ok = false
				break
			for y in _rows:
				if (grid[y][x] == "#") != (y >= heights[x]):
					ok = false
					break
			if not ok:
				break
		if not ok:
			continue
		for x in range(x0 - 2, x0 + length + 2):  # level the ground
			for y in _rows:
				grid[y][x] = "#" if y >= g else "."
			heights[x] = g
		for k in range(1, 4):  # the ramp: tread k is two columns, floor row g + k
			for dx in 2:
				for y in range(g, g + k):
					grid[y][x0 + 2 * (k - 1) + dx] = "."
				for y in range(g, g + k):
					walls.append(Vector2i(x0 + 2 * (k - 1) + dx, y))
		var rx := x0 + 6  # the room: air g+1..g+2 under the roof (row g), floor row g + 3
		var spots := []
		for x in range(rx, rx + room_w + 2):
			for y in [g + 1, g + 2]:
				grid[y][x] = "."
				walls.append(Vector2i(x, y))
			if x >= rx + 3 and (x - rx) % 3 == 0:
				spots.append(Vector2i(x, g + 2))
		if tunnel:  # the way out on the far side: the same ramp mirrored
			var xr := rx + room_w + 2
			for k in range(3, 0, -1):
				for dx in 2:
					var cx := xr + 2 * (3 - k) + dx
					for y in range(g, g + k):
						grid[y][cx] = "."
						walls.append(Vector2i(cx, y))
		for x in range(x0 - 2, x0 + length + 2):
			_reserved[x] = true
		return spots
	return []


## Stone temples: stacked floors of carved stone (one block thick, four blocks of room between them), each floor two blocks
## shorter than the one below on both ends, like a stepped pyramid. The ground is the first floor. A plain ladder stands
## at the end of every floor and runs up to the next - alternately on the right and on the left, so he crosses every floor
## to reach the next, past its soldiers (one or two on each). The dark back wall shows in the rooms. A crate waits on one
## floor with a soldier beside it. Returns {spots: the soldiers' cells, crate: its cell or (-1, -1)}.
static func _temples(grid: Array, heights: PackedInt32Array, rng: RandomNumberGenerator, count: int, from: int, to: int, walls: Array, stone: Array, ladders: Array, gate_only := false) -> Dictionary:
	var out := {"spots": [], "crate": Vector2i(-1, -1), "tops": [], "zips": []}
	for t in count:
		for attempt in (500 if gate_only else 150):
			var gate := gate_only  # the gate: built first, wherever it fits, with a chasm beyond it so he has to climb it and ride the zipline over
			var ext := GATE_CHASM + 7 if gate else 0
			var floors := rng.randi_range(3 if gate else 2, maxi(R.temple_floors_max, 3))
			var len1 := 6 + 4 * (floors - 1) + rng.randi_range(0, 4)  # the lowest floor; the top one is still six blocks long
			var w := len1 + 1  # plus the ladder column beside the lowest floor
			var x0 := rng.randi_range(from, maxi(from, to - w - ext))
			if gate:
				x0 = rng.randi_range(from + (to - from) / 5, maxi(from + (to - from) / 5, (to - from) * 3 / 5 + from - w - ext))
			if x0 < 4 or x0 + w + ext + 4 >= heights.size() or _span_reserved(x0 - 3, x0 + w + 3 + ext):
				continue
			var g: int = heights[x0 + w / 2]
			if gate:  # it takes the ground level of the way in, and flattens whatever lies there
				g = heights[x0 - 4]
				if g - _shift < 8 or g - _shift > 13 or absi(heights[x0 + w + ext + 4] - g) > 4:
					continue
			var low := g
			var high := g
			var bare := absi(heights[x0 - 3] - g) <= 2 and absi(heights[x0 + w + 3 + ext] - g) <= 2
			for x in range(x0 - 3, x0 + w + 3 + ext):  # bare, nearly level ground: no gap, chasm, tower or room in the way
				if not bare or _gaps.has(x) or heights[x] >= _rows:
					bare = false
					break
				low = mini(low, heights[x])
				high = maxi(high, heights[x])
				for y in _rows:
					if (grid[y][x] == "#") != (y >= heights[x]):
						bare = false
						break
			var ytop := g - 5 * floors - 2
			if gate:
				bare = true
				high = low
				for x in range(x0 - 3, x0 + w + 3 + ext):
					_gaps.erase(x)
			if not bare or high - low > 5 or ytop < 3 or g - _shift < 8 or g - _shift > 13:
				continue
			for x in range(x0 - 3, x0 + w + 3 + ext):  # level the ground under it
				for y in _rows:
					grid[y][x] = "#" if y >= g else "."
				heights[x] = g
			if gate:  # the chasm right after the lowest floor, too wide to jump
				for x in range(x0 + w, x0 + w + GATE_CHASM):
					for y in _rows:
						grid[y][x] = "."
					heights[x] = _rows
			var right_first := rng.randf() < 0.5  # the first ladder, from the ground, is on this side
			var lo := func(k: int) -> int: return x0 + 2 * (k - 1)  # first column of floor k (k = 1 is the lowest)
			var hi := func(k: int) -> int: return x0 + len1 - 1 - 2 * (k - 1)
			for k in range(1, floors + 1):
				var s := g - 5 * k  # the row of floor k's slab: its top edge is where he stands
				for x in range(lo.call(k), hi.call(k) + 1):
					grid[s][x] = "#"
					stone.append(Vector2i(x, s))
					for y in range(s + 1, s + 5):
						walls.append(Vector2i(x, y))  # the room under this floor
				var side_right: bool = (k % 2 == 1) == right_first  # the ladder up to this floor
				ladders.append({"x": hi.call(k) + 1 if side_right else lo.call(k) - 1, "top": s, "bot": s + 5, "step": -1 if side_right else 1})
				var cols := range(lo.call(k) + 2, hi.call(k) - 1)  # soldiers keep off the ends where the ladders are
				var first: int = cols[rng.randi() % cols.size()]
				out.spots.append(Vector2i(first, s - 1))
				if gate and rng.randf() < 0.55:  # the other temples hold fewer soldiers
					var second: int = cols[rng.randi() % cols.size()]
					if absi(second - first) >= 4:
						out.spots.append(Vector2i(second, s - 1))
				if k == floors - rng.randi_range(0, floors - 1) and out.crate.x < 0 and rng.randf() < 0.6:
					var at: int = cols[rng.randi() % cols.size()]
					out.crate = Vector2i(at, s - 1)
					out.spots.append(Vector2i(clampi(at + 3, lo.call(k) + 1, hi.call(k) - 1), s - 1))  # his guard
					out.spots.append(Vector2i(clampi(at - 3, lo.call(k) + 1, hi.call(k) - 1), s - 1))
			out.tops.append({"lo": lo.call(floors), "hi": hi.call(floors), "row": g - 5 * floors})
			if gate:  # the zipline from the roof to the ground on the far side of the chasm
								out.zips.append({"a": Vector2i(hi.call(floors), g - 5 * floors - 1), "b": Vector2i(x0 + w + GATE_CHASM + 3, g - 1)})
			for x in range(x0 - 3, x0 + w + 3 + ext):
				_reserved[x] = true
			break
	return out


## A zipline between the top floors of two temples that stand next to each other, when nothing is in the way of the cable.
static func _temple_zips(grid: Array, tops: Array, zips: Array) -> void:
	tops.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p.lo < q.lo)
	for i in tops.size() - 1:
		var p: Dictionary = tops[i]
		var q: Dictionary = tops[i + 1]
		var gap: int = q.lo - p.hi
		if gap < 8 or gap > 40 or absi(p.row - q.row) > 5:
			continue
		var clear := true
		for x in range(p.hi + 1, q.lo):
			for y in range(mini(p.row, q.row) - 4, maxi(p.row, q.row)):
				if grid[y][x] != ".":
					clear = false
		if clear:
			zips.append({"a": Vector2i(p.hi, p.row - 1), "b": Vector2i(q.lo, q.row - 1)})


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
			if x0 < 4 or x0 + w + 4 >= heights.size() or _span_reserved(x0 - 3, x0 + w + 3):
				continue
			var g: int = heights[x0]
			var flat := true
			for x in range(x0 - 3, x0 + w + 3):
				if heights[x] != g or _gaps.has(x):
					flat = false
					break
			var tiers := 2 if g - _shift >= 11 and rng.randf() < 0.6 else 1
			var top := g - 3 * tiers - 3
			if not flat or top < 2 or not _free_box(grid, x0, top - 1, w, g - top + 1):
				continue
			_build_tower(grid, x0, g, inner, tiers, rng.randf() < 0.5, walls)
			break


## Builds one tower (see _towers) with its open end at column x0 (far_right: the wall is on the right) on ground row g.
## Returns the row of the top of its wall, where the Bro stands when he climbs out.
static func _build_tower(grid: Array, x0: int, g: int, inner: int, tiers: int, far_right: bool, walls: Array) -> int:
	var w := inner + 2
	var top := g - 3 * tiers - 3
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
	return top


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
		for y in [_rows - 2, _rows - 1]:
			unbreakable.append(Vector2i(x, y))
	var solid := func(x: int, y: int) -> void:  # a rock block that nothing breaks
		grid[y][x] = "#"
		unbreakable.append(Vector2i(x, y))
		stone.append(Vector2i(x, y))
	for y in range(0, g - 2):  # left wall, with the doorway (g-2, g-1) left open
		solid.call(a, y)
	for y in range(g, _rows):  # ...and the earth under it
		unbreakable.append(Vector2i(a, y))
	for x in [width - 2, width - 1]:  # right wall
		for y in _rows:
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
	if x < 2 or x + w >= grid[0].size() - 2 or y < 1 or y + h > _rows:
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
	for y in range(2, _rows - 1):
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


## How many soldiers one may stand with: mostly alone or in pairs, sometimes three - never more.
static func _group_limit(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	return 1 if roll < 0.4 else (2 if roll < 0.75 else 3)


## The size of the group a soldier at `spot` would join: soldiers on the same row, each within GROUP_REACH columns of the next.
static func _group_size(standing: Dictionary, spot: Vector2i) -> int:
	var count := 1
	for way in [-1, 1]:
		var cur: int = spot.x
		while true:
			var found := false
			for d in range(1, GROUP_REACH + 1):
				if standing.has(Vector2i(cur + way * d, spot.y)):
					cur += way * d
					count += 1
					found = true
					break
			if not found:
				break
	return count


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
