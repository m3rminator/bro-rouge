class_name RopeBridge
extends Node2D
## A rope bridge over a chasm: single boards (BridgePlank) between two posts, with ropes. It hangs a little and sags
## under whoever stands on it (more when he lands on it from high up). A board he stands on breaks after CRUMBLE_TIME; a
## board that breaks (by that, a bullet or a blast) starts the rest falling, one after another, away from the break. A
## drop of HARD_DROP or more onto it breaks the boards under him at once. `cells` are the level's `bridges` (a row of
## cells, left to right), `player` the Bro. Add it to the level node (at 0, 0).

const SAG := 3.0  # how much it hangs by itself, in the middle
const LOAD_SAG := 9.0  # how much further it goes down under his weight
const CRUMBLE_TIME := 0.55
const CHAIN_STEP := 0.25  # seconds between one board falling and the next one next to it
const HARD_DROP := 10.0 * Block.SIZE
const ROPE := Color("8a6a3a")
const ROPE_DARK := Color("4a301c")
const POST := Color("5a4630")

var cells: Array = []
var player: CharacterBody2D
var _planks: Array[BridgePlank] = []
var _sag := PackedFloat32Array()
var _stand := {}  # board index -> seconds his feet have been on it
var _fall_at := {}  # board index -> clock time it falls
var _clock := 0.0
var _load := 0.0  # 0..1: he is on the bridge
var _impact := 0.0  # a landing: the bridge dips deeper for a moment
var _at_x := 0.0  # where the dip is
var _peak := 0.0
var _was_floor := true
var _row := 0
var _left := 0


func _ready() -> void:
	if cells.is_empty():
		return
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	_row = cells[0].y
	_left = cells[0].x
	for i in cells.size():
		var plank := BridgePlank.new()
		plank.index = i
		plank.position = Vector2((_left + i) * Block.SIZE + Block.SIZE / 2.0, _row * Block.SIZE)
		plank.broken.connect(_on_broken)
		add_child(plank)
		_planks.append(plank)
		_sag.append(0.0)
	_at_x = _planks[_planks.size() / 2].position.x


func _alive(i: int) -> bool:
	return i >= 0 and i < _planks.size() and is_instance_valid(_planks[i]) and not _planks[i].falling


func _on_broken(plank: BridgePlank) -> void:
	for j in _planks.size():
		if _alive(j):
			var at := _clock + absi(j - plank.index) * CHAIN_STEP
			_fall_at[j] = minf(_fall_at.get(j, at), at)


func _physics_process(delta: float) -> void:
	_clock += delta
	if player == null or not is_instance_valid(player):
		return
	var on_floor := player.is_on_floor()
	if not on_floor:
		if _was_floor:
			_peak = player.position.y
		_peak = minf(_peak, player.position.y)
	var feet := player.position.y + Block.SIZE / 2.0
	var standing := -1
	if on_floor and absf(feet - _row * Block.SIZE) < Block.SIZE:
		for dx in [0.0, -5.0, 5.0]:
			var i := floori((player.position.x + dx) / Block.SIZE) - _left
			if _alive(i):
				standing = i
				break
	if standing >= 0:
		if not _was_floor:  # he just landed on it
			var drop := player.position.y - _peak
			_impact = clampf(drop / (8.0 * Block.SIZE), 0.2, 1.0)
			if drop >= HARD_DROP:
				for i in range(standing - 1, standing + 2):
					if _alive(i):
						_planks[i].snap()
		_at_x = player.position.x
		_load = move_toward(_load, 1.0, delta * 6.0)
		for i in range(standing - 1, standing + 2):  # the boards under his feet start to give way
			if _alive(i) and not _stand.has(i):
				_stand[i] = 0.0
	else:
		_load = move_toward(_load, 0.0, delta * 3.0)
	_was_floor = on_floor
	_impact = move_toward(_impact, 0.0, delta * 2.5)
	for i in _stand.keys():
		if not _alive(i):
			_stand.erase(i)
			continue
		_stand[i] += delta
		if _stand[i] >= CRUMBLE_TIME:
			_planks[i].snap()
			_stand.erase(i)
	for i in _fall_at.keys():
		if _clock >= _fall_at[i]:
			_fall_at.erase(i)
			if _alive(i):
				_planks[i].snap()
	var n := _planks.size()
	for i in n:
		if not _alive(i):
			continue
		var plank := _planks[i]
		var t := (i + 0.5) / n
		var shape := sin(PI * t)
		var near := (plank.position.x - _at_x) / (2.6 * Block.SIZE)
		var dip := (LOAD_SAG * _load + LOAD_SAG * _impact) * exp(-near * near) * pow(shape, 0.6)
		_sag[i] = lerpf(_sag[i], SAG * shape + dip, 1.0 - exp(-delta * 14.0))
		var shake := 0.0
		if (_stand.has(i) and _stand[i] > 0.1) or (_fall_at.has(i) and _fall_at[i] - _clock < 0.3):
			shake = randf_range(-1.0, 1.0)
		plank.position = Vector2((_left + i) * Block.SIZE + Block.SIZE / 2.0 + roundf(shake), _row * Block.SIZE + roundf(_sag[i]))
	queue_redraw()


func _draw() -> void:
	if _planks.is_empty():
		return
	var rail := 15.0
	var under := Vector2(0, 7.0)
	var up := Vector2(0, -rail)
	var left_end := Vector2(_left * Block.SIZE, _row * Block.SIZE)
	var right_end := Vector2((_left + _planks.size()) * Block.SIZE, _row * Block.SIZE)
	for post_x in [left_end.x, right_end.x]:  # a post at each end
		draw_rect(Rect2(post_x - 2, _row * Block.SIZE - rail - 4, 4, rail + 4 + Block.SIZE / 2.0), POST)
	for i in _planks.size():
		if not _alive(i):
			continue
		var p := _planks[i].position
		var before := left_end if i == 0 else (_planks[i - 1].position if _alive(i - 1) else Vector2.INF)
		if before != Vector2.INF:  # the handrail and the rope under the boards, to the one before
			draw_line(before + up, p + up, ROPE, 1.0)
			draw_line(before + under, p + under, ROPE_DARK, 1.0)
		if i == _planks.size() - 1:
			draw_line(p + up, right_end + up, ROPE, 1.0)
			draw_line(p + under, right_end + under, ROPE_DARK, 1.0)
		if i % 2 == 0:  # the ropes that hold the handrail up
			draw_line(p + up, p, ROPE, 1.0)
