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
const UNDER := 16  # rows of earth under the old ground level in tall fight levels: room for tunnels under the surface
static var _rows := ROWS  # the level being built (tall fight levels: run.yaml level_rows)
static var _shift := 0  # rows added above the old 17: the ground sits this much lower
const GROUP_REACH := 3  # soldiers on one row this many columns apart or closer count as standing together
const ROOM_MAX := 4  # most soldiers in one room of a tunnel (between two doors)
const GROUND_MIN := 5  # highest ground top row (hill tops)
const GROUND_MAX := 13  # lowest ground top row (valley floors)
const PIT_FLOOR := 14  # lowest a gap floor may go (gaps are 2 deep, so ground rows 13+ dig less)
const ARENA := 40  # a boss level ends with this many flat columns: the walled arena (walls included)
const ARENA_GROUND := 12  # its ground top row (leaves room for the gallery above the Brute)
const START_COLS := 12  # flat safe run-up at the left edge
const END_COLS := 10  # flat run before the exit
const SKYLINE_MIN_WIDTH := 90  # levels at least this wide get a skyline (two towers over a chasm) and underground rooms
const TEMPLE_ROOM := 4  # free height of a building room (at least three)
const TEMPLE_PERIOD := 6  # one room plus the two block slab above it
const GATE_CHASM := 16  # the chasm behind a gate temple
const CHASM_WIDTH := 14  # too wide to jump: the zipline between the tower tops is the way over
const STEP_WIDTH := 3  # width of one stair tread
const TITLES := ["Jungle Outpost", "Ruined Camp", "River Crossing", "Overgrown Road", "Bandit Ridge",
		"Supply Depot", "Burnt Village", "Hidden Trail", "Rotting Bridge", "Smuggler's Run"]
const R := GameData.RUN

static var _gaps := {}  # columns that are gap floors in the level being built
static var tunnels_made := 0
static var tunnel_info: Array = []  # {from, to, ground, shaft} of each tunnel, for the level report
static var _signs: Array = []  # cells of the signposts that point up beside a chasm
static var _signs_down: Array = []  # of those, the ones that also point down (a way in under the ground)
static var _doors: Array = []  # {col, top row} of the doors that cut a tunnel into rooms (tunnel_door.gd)
static var _bridges: Array = []  # cells of the boards of an underground rope bridge over a chasm (rope_bridge.gd)
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
	_signs = []
	_doors = []
	_signs_down = []
	_bridges = []
	tunnels_made = 0
	tunnel_info = []
	_rows = ROWS if boss else R.level_rows + UNDER  # fight levels are tall: room for temples and high hills above, tunnels below
	_shift = 0 if boss else R.level_rows - ROWS
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
		extra.append_array(_tunnels(grid, heights, rng, 1 + (1 if width >= 120 else 0), START_COLS + 4, width - END_COLS - 6, walls, ladders))
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
	for sign_cell: Vector2i in _signs:
		_take(taken, sign_cell, 1)
	for door: Vector2i in _doors:  # nothing stands in a doorway
		_take(taken, Vector2i(door.x, door.y + 2), 1)
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
		var sx := width - ARENA - 3  # an ammo box and a grenade box side by side on the flat ground in front of the doorway
		while sx > START_COLS:
			if grid[heights[sx] - 1][sx] == "." and grid[heights[sx + 1] - 1][sx + 1] == "." and heights[sx] == heights[sx + 1]:
				grid[heights[sx] - 1][sx] = "A"
				grid[heights[sx] - 1][sx + 1] = "G"
				taken[Vector2i(sx, heights[sx] - 1)] = true
				taken[Vector2i(sx + 1, heights[sx] - 1)] = true
				break
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
	for info: Dictionary in tunnel_info:  # however they got there, no room of a tunnel holds more than ROOM_MAX soldiers
		placed -= _cap_grid(grid, info, rng)  # (the kill quota counts the ones left)
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
		"signs": _signs.duplicate(),
		"doors": _doors.duplicate(),
		"signs_down": _signs_down.duplicate(),
		"bridges": _bridges.duplicate(),
		"tunnels": tunnels_made,
		"tunnel_info": tunnel_info.duplicate(),
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
	put.call(9, "A")  # side by side: using one gives all three (hub_station.gd)
	put.call(10, "H")
	put.call(11, "G")
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
		_signs.append(Vector2i(xa - 2, g - 1))
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


## Stone buildings in the way of the Broforce ones: boxes of stacked rooms, each at least four blocks high and walled in
## by stone on both sides (the doors are at ground level only). Between two rooms lies a two block slab: its walking
## surface is carved stone and the layer under it is earth, so nothing he breaks can lock him out. A ladder shaft cuts
## through every slab, with stone around it, alternately at the left and at the right end of the room. The top floor is
## an open roof with no walls. One or two soldiers in every room (more in the gate), a crate with a guard in one of them.
## The gate (`gate_only`) is built first and has a chasm right behind its right wall: he has to climb it and ride the
## zipline from its roof over to the ground beyond. Returns {spots, crate, tops, zips}.
static func _temples(grid: Array, heights: PackedInt32Array, rng: RandomNumberGenerator, count: int, from: int, to: int, walls: Array, stone: Array, ladders: Array, gate_only := false) -> Dictionary:
	var out := {"spots": [], "crate": Vector2i(-1, -1), "tops": [], "zips": []}
	for t in count:
		for attempt in (500 if gate_only else 150):
			var gate := gate_only
			var ext := GATE_CHASM + 7 if gate else 0
			var floors := rng.randi_range(3 if gate else 2, mini(maxi(R.temple_floors_max, 3), 4 if gate else 3))
			var w := rng.randi_range(10, 14) + 2  # the interior plus the two walls
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
			var ytop := g - TEMPLE_PERIOD * floors - 2
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
			if gate:  # the chasm right behind the right wall, too wide to jump
				for x in range(x0 + w, x0 + w + GATE_CHASM):
					for y in _rows:
						grid[y][x] = "."
					heights[x] = _rows
			var lo := x0  # the left wall; the right wall is `hi`
			var hi := x0 + w - 1
			var roof := g - TEMPLE_PERIOD * floors  # the top row of the roof slab
			var surface := func(r: int) -> int: return g - TEMPLE_PERIOD * r  # the row he stands on in room r (r = floors is the roof)
			var start_left := rng.randf() < 0.5
			var left_of := func(k: int) -> bool: return start_left == (k % 2 == 1)  # which end ladder k stands at
			if gate:
				left_of = func(k: int) -> bool: return (floors - k) % 2 == 0  # the top ladder is at the left, away from the zipline post
			var shaft := {}  # ladder number -> its column
			for k in range(1, floors + 1):
				shaft[k] = lo + 1 if left_of.call(k) else hi - 1
			for y in range(roof, g):  # the walls: stone columns on both sides, from the roof down to the ground
				for x in [lo, hi]:
					grid[y][x] = "#"
					stone.append(Vector2i(x, y))
			for k in range(1, floors + 1):  # the slabs and the rooms above them
				var s: int = surface.call(k)  # top row of slab k
				for x in range(lo + 1, hi):
					for y in [s, s + 1]:
						grid[y][x] = "#"
						if y == s or absi(x - shaft[k]) <= 1:  # the walking surface and the rim of the shaft are stone, the layer between is earth
							stone.append(Vector2i(x, y))
				for y in [s, s + 1]:  # the shaft through the slab
					grid[y][shaft[k]] = "."
					walls.append(Vector2i(shaft[k], y))
				if k < floors:
					for y in range(s - TEMPLE_ROOM, s):  # the room above this slab
						for x in range(lo + 1, hi):
							walls.append(Vector2i(x, y))
			for y in range(g - TEMPLE_ROOM, g):  # the ground room
				for x in range(lo + 1, hi):
					walls.append(Vector2i(x, y))
			for y in range(g - 3, g):  # the doors (the gate is shut on the chasm side)
				grid[y][lo] = "."
				walls.append(Vector2i(lo, y))
				if not gate:
					grid[y][hi] = "."
					walls.append(Vector2i(hi, y))
			for k in range(1, floors + 1):
				ladders.append({"x": shaft[k], "top": surface.call(k), "bot": surface.call(k - 1), "step": 1 if left_of.call(k) else -1})
			for r in range(0, floors + 1):  # people: one or two in every room, a crate with a guard in one of them
				var row: int = surface.call(r)
				var cols := []
				for x in range(lo + 2 if r < floors else lo + 3, hi - 1 if r < floors else hi - 2):
					var clear := true
					for k in [r, r + 1]:
						if shaft.has(k) and absi(x - shaft[k]) < 2:
							clear = false
					if clear:
						cols.append(x)
				if cols.is_empty():
					continue
				var first: int = cols[rng.randi() % cols.size()]
				out.spots.append(Vector2i(first, row - 1))
				if gate and rng.randf() < 0.55:  # the other buildings hold fewer soldiers
					var second: int = cols[rng.randi() % cols.size()]
					if absi(second - first) >= 4:
						out.spots.append(Vector2i(second, row - 1))
				if r == rng.randi_range(0, floors) and out.crate.x < 0 and rng.randf() < 0.7:
					var at: int = cols[rng.randi() % cols.size()]
					out.crate = Vector2i(at, row - 1)
					out.spots.append(Vector2i(clampi(at + 3, cols[0], cols[-1]), row - 1))  # his guard
					out.spots.append(Vector2i(clampi(at - 3, cols[0], cols[-1]), row - 1))
			if gate:
				_cellar(grid, heights, rng, lo, hi, g, shaft[1] == lo + 1, walls, ladders, out.spots)
			out.tops.append({"lo": lo, "hi": hi, "row": roof, "ladder_left": left_of.call(floors)})
			if gate:  # the zipline from the roof to the ground on the far side of the chasm
				_signs.append(Vector2i(x0 - 2, g - 1))
				if not _bridges.is_empty():  # the cellar and its bridge: the way over is down as well
					_signs_down.append(Vector2i(x0 - 2, g - 1))
				out.zips.append({"a": Vector2i(hi, roof - 1), "b": Vector2i(x0 + w + GATE_CHASM + 3, g - 1)})
			for x in range(x0 - 3, x0 + w + 3 + ext):
				_reserved[x] = true
			break
	return out


## The gate building's cellar: up to three floors under the whole ground floor, joined by ladders (a zigzag from end to
## end), a corridor out under the ground in front of it on the first floor to a ladder up to the surface, and on the
## lowest floor the bridge over the chasm. Skipped when the earth under it is not all solid.
static func _cellar(grid: Array, heights: PackedInt32Array, rng: RandomNumberGenerator, lo: int, hi: int, g: int, up_left: bool, walls: Array, ladders: Array, spots: Array) -> void:
	if _floor_count(g) < 1 or lo < 20:
		return
	var n := _floor_count(g)
	var bottom := _floor_row(g, n)
	var hx := _flat_near(heights, lo - 12, lo - 4)  # the way up to the surface
	if hx < 0 or not _bridge_fits(grid, heights, hi, g, n):  # no bridge to reach: no cellar to dig either
		return
	for c in range(hx - 2, hi + 1):
		for y in range(g, bottom + 2):
			if grid[y][c] != "#" or _gaps.has(c):
				return
	var fl := _floor_row(g, 1)
	for c in range(hx, hi):
		_hollow(grid, walls, c, fl - 3, fl - 1)
	var down := hi - 2 if up_left else lo + 2
	var other := lo + 2 if up_left else hi - 2
	_dig_shaft(grid, walls, ladders, down, g, fl)
	_dig_shaft(grid, walls, ladders, hx, heights[hx], fl)
	for c in range(hx - 3, lo):
		_reserved[c] = true
	for c in [hx + 4, lo + 4 if absi(lo + 4 - down) > 2 else lo + 6, hi - 4 if absi(hi - 4 - down) > 2 else hi - 6]:
		spots.append(Vector2i(c, fl - 1))
	if n >= 2:
		_stack(grid, walls, ladders, spots, lo + 1, hi - 1, g, n, down, g, other, 2)
	_bridge(grid, heights, hi, g, n, walls, ladders, spots, other)


## Floors `from_k`..`n` under columns xl..xr (floor k has its surface at _floor_row), each with a ladder up to the floor
## above it (floor 1's goes to row `top1`): odd floors at column `odd_x`, even ones at `even_x`. Two soldiers on a floor.
## With `door_k` only that floor is open at column `xl`; the others start one column in, so their end is a wall.
static func _stack(grid: Array, walls: Array, ladders: Array, spots: Array, xl: int, xr: int, g: int, n: int, odd_x: int, top1: int, even_x: int, from_k: int, door_k := -1) -> void:
	for k in range(from_k, n + 1):
		var fl := _floor_row(g, k)
		for c in range(xl if door_k < 0 or k == door_k else xl + 1, xr + 1):  # the left end is a wall, except where the door is
			_hollow(grid, walls, c, fl - 3, fl - 1)
		_dig_shaft(grid, walls, ladders, odd_x if k % 2 == 1 else even_x, top1 if k == 1 else _floor_row(g, k - 1), fl)
		for c in [xl + (xr - xl) / 4, xl + 3 * (xr - xl) / 4]:
			if absi(c - odd_x) > 2 and absi(c - even_x) > 2:
				spots.append(Vector2i(c, fl - 1))


## How many cellar floors fit under ground row `g` (at most three).
static func _floor_count(g: int) -> int:
	var n := 0
	while n < 3 and _floor_row(g, n + 1) + 2 < _rows:
		n += 1
	return n


## The row of the surface of cellar floor `k` (1 is the first under the ground floor): six rows apart (air, floor, rock).
static func _floor_row(g: int, k: int) -> int:
	return g + 5 + 6 * (k - 1)


## The first column from `from` to `to` with level ground two columns to either side, else -1.
static func _flat_near(heights: PackedInt32Array, from: int, to: int) -> int:
	for c in range(from, to + 1):
		if c < 2 or c + 2 >= heights.size():
			continue
		var level := true
		for d in range(-2, 3):
			if heights[c + d] != heights[c]:
				level = false
		if level:
			return c
	return -1


## True when the chasm beside the cellar can take a bridge with the floors on its far side (what _bridge needs).
static func _bridge_fits(grid: Array, heights: PackedInt32Array, hi: int, g: int, n: int) -> bool:
	var a := hi + 1
	while a < heights.size() and heights[a] < _rows:
		a += 1
	var b := a
	while b < heights.size() and heights[b] >= _rows:
		b += 1
	if a - hi > 6 or b - a < 4 or b + 16 >= heights.size():
		return false
	if _flat_near(heights, b + 5, b + 10) < 0:
		return false
	var bottom := _floor_row(g, n)
	for c in range(b, b + 14):
		for y in range(g, bottom + 2):
			if grid[y][c] != "#" or _gaps.has(c):
				return false
	return true


## The cellar's other way out: a door in the wall of its lowest floor onto the chasm, a bridge of single planks across
## (a rope bridge: see rope_bridge.gd), and the same floors on the far side with a ladder up to the surface.
## Skipped when the far side is not solid.
static func _bridge(grid: Array, heights: PackedInt32Array, hi: int, g: int, n: int, walls: Array, ladders: Array, spots: Array, even_x: int) -> void:
	var a := hi + 1
	while a < heights.size() and heights[a] < _rows:
		a += 1
	var b := a
	while b < heights.size() and heights[b] >= _rows:
		b += 1
	if a - hi > 6 or b - a < 4 or b + 16 >= heights.size():
		return
	var far := _flat_near(heights, b + 5, b + 10)  # the way up on the far side
	if far < 0:
		return
	var bottom := _floor_row(g, n)
	for c in range(b, b + 14):
		for y in range(g, bottom + 2):
			if grid[y][c] != "#" or _gaps.has(c):
				return
	for y in range(bottom - 3, bottom):  # the door
		_hollow(grid, walls, hi, y, y)
	for c in range(a, b):
		_bridges.append(Vector2i(c, bottom))
	var far_even := b + 11 if far - b < 7 else b + 2
	_stack(grid, walls, ladders, spots, b, b + 12, g, n, far, heights[far], far_even, 1, n)
	for c in range(b - 1, b + 16):
		_reserved[c] = true


## Tunnels in the earth: two levels of corridors dug under the surface (the upper one at the first rows under the lowest
## ground, the lower one under it), with rooms along them, ladders between the levels, a hole in a room floor that drops
## to the lower level, and ladders up to the surface at both ends. Often a mountain stands over the middle of it: a
## tunnel through its foot, a ladder from that tunnel down to the upper level, and one up to the top. Returns the soldiers' cells.
static func _tunnels(grid: Array, heights: PackedInt32Array, rng: RandomNumberGenerator, count: int, from: int, to: int, walls: Array, ladders: Array) -> Array:
	var spots := []
	var made := 0
	for attempt in 600:
		if made >= count:
			break
		var mountain := rng.randf() < 0.55
		var peak := rng.randi_range(12, 17)
		var plateau := rng.randi_range(10, 16)
		var mw := 2 * (peak - 4) + plateau
		var xa := 0  # the underground: columns xa..xb
		var xb := 0
		var x0 := 0  # the mountain: columns x0..x0+mw-1
		if mountain:
			if to - from < mw + 26:
				mountain = false
		if mountain:
			x0 = rng.randi_range(from + 10, to - mw - 10)
			xa = x0 - 8
			xb = x0 + mw + 7
		else:
			var uw := rng.randi_range(40, 60)
			if to - from < uw + 6:
				continue
			xa = rng.randi_range(from + 3, to - uw - 3)
			xb = xa + uw - 1
		var free := true
		var surface := 0  # the lowest the surface is (the biggest row) over the whole span
		for c in range(xa - 3, xb + 4):
			if _gaps.has(c) or _reserved.has(c) or heights[c] >= _rows:
				free = false
				break
			if c >= xa and c <= xb:
				surface = maxi(surface, heights[c])
		if not free:
			continue
		var g := 0
		if mountain:
			g = heights[x0 - 1]
			if g - peak < 4 or absi(heights[x0 + mw] - g) > 1:
				continue
			surface = maxi(surface, g)
		var ya := surface + 3  # the upper corridor: air ya..ya+2, floor row fa
		var fa := ya + 3
		var yb := fa + 3  # the lower one
		var fb := yb + 3
		if fa > _rows - 2:
			continue
		var two := fb <= _rows - 2
		var hatches := []  # a flat place for a ladder up to the surface near each end
		for end in 2:
			var found := -1
			for k in 10:
				var hx := xa + 2 + k if end == 0 else xb - 2 - k
				if mountain and hx >= x0 - 2 and hx <= x0 + mw + 1:
					continue
				var level := true
				for d in range(-2, 3):
					if heights[hx + d] != heights[hx]:
						level = false
				if level:
					found = hx
					break
			hatches.append(found)
		if hatches[0] < 0 or hatches[1] < 0:
			continue
		var first_spot := spots.size()  # this tunnel's soldiers start here
		var down := -1000  # the ladder from the mountain passage down to the upper corridor
		if mountain:
			for i in mw:  # the mountain: a cliff four blocks high at each end (the door and a block of rock over it), then slopes
				var c := x0 + i
				heights[c] = g - mini(mini(4 + i, 4 + (mw - 1 - i)), peak)
				for y in _rows:
					grid[y][c] = "#" if y >= heights[c] else "."
			for c in range(x0, x0 + mw):  # the passage through its foot
				for y in range(g - 3, g):
					if grid[y][c] == "#":
						walls.append(Vector2i(c, y))
					grid[y][c] = "."
			var top_shaft := x0 + mw / 2 + rng.randi_range(-2, 2)
			for y in range(heights[top_shaft], g - 3):
				grid[y][top_shaft] = "."
				walls.append(Vector2i(top_shaft, y))
			ladders.append({"x": top_shaft, "top": heights[top_shaft], "bot": g, "step": 1})
			down = x0 + mw / 2 + (7 if top_shaft <= x0 + mw / 2 else -7)  # from the passage down to the upper corridor
			_dig_shaft(grid, walls, ladders, down, g, fa)
			for c in range(x0 + 3, x0 + mw - 3):  # soldiers in the passage
				if absi(c - top_shaft) >= 2 and absi(c - down) >= 2 and (c - x0) % 7 == 3:
					spots.append(Vector2i(c, g - 1))
		for c in range(xa, xb + 1):  # the upper corridor
			_hollow(grid, walls, c, ya, ya + 2)
		var rooms_a := _rooms(grid, walls, rng, xa + 5, xb - 5, ya, 2, rng.randi_range(3, 4))
		for hx: int in hatches:
			_dig_shaft(grid, walls, ladders, hx, heights[hx], fa)
		var occupied := [hatches[0], hatches[1], down]
		for dc in _door_columns(rng, xa + 4, xb - 4, rooms_a, occupied, 20):  # the upper corridor in two or three rooms
			_doors.append(Vector2i(dc, ya))
			occupied.append(dc)
		if two:
			for c in range(xa + 6, xb - 5):  # the lower corridor is a bit shorter
				_hollow(grid, walls, c, yb, yb + 2)
			var rooms_b := _rooms(grid, walls, rng, xa + 9, xb - 8, yb, 1, rng.randi_range(2, 3))
			for dc in _door_columns(rng, xa + 9, xb - 8, rooms_b, occupied, 18):  # and a long lower one too
				_doors.append(Vector2i(dc, yb))
				occupied.append(dc)
			var link := (xa + xb) / 2 + rng.randi_range(-6, 6)  # a ladder between the two corridors
			for shift in [0, 4, -4, 8, -8]:
				if _clear_of(occupied, link + shift, 3):
					link += shift
					break
			_dig_shaft(grid, walls, ladders, link, fa, fb)
			occupied.append(link)
			var hole := -1  # and a hole in the floor of an upper room, dropping into the lower corridor
			for room: Vector2i in rooms_a:
				var hx := room.x + room.y / 2
				if hx > xa + 8 and hx < xb - 8 and _clear_of(occupied, hx, 4):
					hole = hx
					break
			if hole >= 0:
				for dx in 2:
					for y in range(fa, yb):
						grid[y][hole + dx] = "."
						walls.append(Vector2i(hole + dx, y))
				occupied.append(hole)
			for room: Vector2i in rooms_b:
				for c in [room.x + 2, room.x + room.y - 3]:
					if _clear_of(occupied, c, 2):
						spots.append(Vector2i(c, fb - 1))
		for room: Vector2i in rooms_a:
			for c in [room.x + 2, room.x + room.y - 3]:
				if _clear_of(occupied, c, 2):
					spots.append(Vector2i(c, fa - 1))
		for c in range(xa + 4, xb - 3, 6):  # and a few in the corridor itself
			if _clear_of(occupied, c, 2) and rng.randf() < 0.6:
				spots.append(Vector2i(c, fa - 1))
		_cap_rooms(spots, first_spot, rng)
		for c in range(xa - 3, xb + 4):
			_reserved[c] = true
		made += 1
		tunnels_made += 1
		tunnel_info.append({"from": xa, "to": xb, "ground": surface, "mountain": mountain, "peak": peak if mountain else 0, "two": two, "rows": [fa - 1, fb - 1] if two else [fa - 1]})
	return spots


## At most ROOM_MAX soldiers in one room: the spots from index `first` on are sorted into the stretch of their row between
## two doors (or a corridor end), and a stretch with too many loses random ones.
static func _cap_rooms(spots: Array, first: int, rng: RandomNumberGenerator) -> void:
	var stretches := {}  # "row:number of doors to the left" -> spots
	for i in range(first, spots.size()):
		var s: Vector2i = spots[i]
		var left := 0
		for door: Vector2i in _doors:
			if door.y + 2 == s.y and door.x < s.x:   # a door stands at the top air row of its corridor; the soldiers stand two rows below it
				left += 1
		var key := "%d:%d" % [s.y, left]
		if not stretches.has(key):
			stretches[key] = []
		stretches[key].append(s)
	for key: String in stretches:
		var list: Array = stretches[key]
		while list.size() > ROOM_MAX:
			var gone: Vector2i = list.pop_at(rng.randi() % list.size())
			spots.erase(gone)


## Takes soldiers out of the rooms of one tunnel (a row of `info.rows` between two doors, or a door and a corridor end)
## that hold more than ROOM_MAX of them. Returns how many it took out.
static func _cap_grid(grid: Array, info: Dictionary, rng: RandomNumberGenerator) -> int:
	var removed := 0
	for y: int in info.rows:
		var stretches := {}  # number of doors to the left -> cells
		for x in range(info.from, info.to + 1):
			if not "EKMV".contains(grid[y][x]):
				continue
			var left := 0
			for door: Vector2i in _doors:
				if door.y + 2 == y and door.x >= info.from and door.x < x:
					left += 1
			if not stretches.has(left):
				stretches[left] = []
			stretches[left].append(x)
		for left: int in stretches:
			var list: Array = stretches[left]
			while list.size() > ROOM_MAX:
				var gone: int = list.pop_at(rng.randi() % list.size())
				grid[y][gone] = "."
				removed += 1
	return removed


## Air in column `c` from row `y1` to `y2`; a block there that was solid shows the back wall.
static func _hollow(grid: Array, walls: Array, c: int, y1: int, y2: int) -> void:
	for y in range(y1, y2 + 1):
		if grid[y][c] == "#":
			walls.append(Vector2i(c, y))
		grid[y][c] = "."


## A ladder shaft in column `x`, from the floor surface at row `top` down to the one at row `bot`: the column in between
## is hollowed out (the floor at the top too, so he climbs out beside it).
static func _dig_shaft(grid: Array, walls: Array, ladders: Array, x: int, top: int, bot: int) -> void:
	for y in range(top, bot):
		_hollow(grid, walls, x, y, y)
	ladders.append({"x": x, "top": top, "bot": bot, "step": 1})


## Rooms along a corridor whose air starts at row `y` (three rows high): each is taller by `extra` rows on top, 7 to 11
## wide. Returns {x: left column, y: width} of each one made (as Vector2i).
static func _rooms(grid: Array, walls: Array, rng: RandomNumberGenerator, from: int, to: int, y: int, extra: int, count: int) -> Array:
	var rooms := []
	var slot := (to - from) / maxi(count, 1)
	for i in count:
		var w := rng.randi_range(7, 11)
		var x := from + i * slot + rng.randi_range(0, maxi(slot - w, 0))
		if x + w > to:
			break
		for c in range(x, x + w):
			_hollow(grid, walls, c, y - extra, y - 1)
		rooms.append(Vector2i(x, w))
	return rooms


## Columns for doors that cut a corridor from `from` to `to` into two rooms (one door) or three (two doors, when it is
## long): near the third points of it, but never inside a bay (`rooms`) or next to a ladder, hole or other door.
## Nothing when it is shorter than `min_len`.
static func _door_columns(rng: RandomNumberGenerator, from: int, to: int, rooms: Array, occupied: Array, min_len: int) -> Array:
	var out := []
	if to - from < min_len:
		return out
	var count := 1 if to - from < 42 else 2
	for k in range(1, count + 1):
		var target := from + (to - from) * k / (count + 1) + rng.randi_range(-2, 2)
		for shift in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8, -8]:
			var c: int = target + shift
			var in_bay := false
			for room: Vector2i in rooms:
				if c >= room.x - 1 and c <= room.x + room.y:
					in_bay = true
			if not in_bay and c > from and c < to and _clear_of(occupied, c, 2) and _clear_of(out, c, 5):
				out.append(c)
				break
	return out


static func _clear_of(taken: Array, c: int, gap: int) -> bool:
	for t: int in taken:
		if absi(t - c) < gap + 1:
			return false
	return true


## A zipline between the top floors of two temples that stand next to each other, when nothing is in the way of the cable.
static func _temple_zips(grid: Array, tops: Array, zips: Array) -> void:
	tops.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p.lo < q.lo)
	for i in tops.size() - 1:
		var p: Dictionary = tops[i]
		var q: Dictionary = tops[i + 1]
		if not p.ladder_left or q.ladder_left:
			continue  # a zipline post never stands beside a ladder
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
