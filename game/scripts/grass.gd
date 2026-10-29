class_name Grass
extends Node2D
## Grass blades on top of a surface block (design/entities/grass.yaml, GameData.GRASS). No
## sprite: every blade is drawn pixel by pixel and bends on its own spring — wind sway, bodies
## standing in it or running through, explosions (Grass.blast). Blood that lands on a blade
## stays on it (stain_at). When the block breaks, the blades burst into green particles (burst).
## Child of its Block, so it disappears with it.

const STATS := GameData.GRASS
const SWAY: float = GameData.GRASS.sway
const SWAY_SPEED: float = GameData.GRASS.sway_speed
const STIFFNESS: float = GameData.GRASS.stiffness
const DAMPING: float = GameData.GRASS.damping
const PUSH_RADIUS: float = GameData.GRASS.push_radius
const PUSH: float = GameData.GRASS.push
const FLICK: float = GameData.GRASS.flick
const CRUSH_HALF: float = GameData.GRASS.crush_width / 2.0
const CRUSH_SPEED: float = GameData.GRASS.crush_speed
const REACH := maxf(GameData.GRASS.push_radius, GameData.GRASS.crush_width / 2.0)
const ACTIVE_TIME := 1.5
const IDLE_STEP := 0.05
const COLORS := [Color("24502a"), Color("3e8034"), Color("7cc04e"), Color("a2e24c")]  # master: grass_dark, grass, grass_light, grass_bright
const TOP := -Block.SIZE / 2.0  # the block's top edge (blades stand on it)

var _x := PackedFloat32Array()  # blade base, block space
var _h := PackedInt32Array()  # blade height in pixels
var _shade := PackedInt32Array()  # 0 dark, 1 mid, 2 light green (tips are a shade lighter)
var _lean := PackedFloat32Array()  # tip offset in pixels (+ = right)
var _vel := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _blood := PackedInt32Array()  # red pixels at the tip
var _blood_color: Array[Color] = []
var _crush := PackedFloat32Array()  # 0 standing .. 1 pressed down under a lying body
var _rim := PackedInt32Array()  # per column of the block: how many pixels the green rim stands above the top edge
var _vines := []  # [x, length, loop width (0 = a single strand)] hanging down the block face
var _time := 0.0
var _active := 0.0  # seconds the spring still has to run (something pushed it, or a blast)
var _idle_t := 0.0
var _sig := -1  # what the blades looked like when last drawn

static var _bodies_frame := -1
static var _bodies_cache := []
static var _bodies_at := PackedVector2Array()


func _ready() -> void:
	add_to_group("grass")
	z_index = 3  # in front of feet and bodies: they stand in the grass
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(global_position))  # same grass every time the level loads
	for x in int(Block.SIZE):  # ragged rim: runs of 1-3 columns at the same height
		var left := x % 3
		_rim.append(_rim[x - 1] if left != 0 and x > 0 else rng.randi_range(0, STATS.get("rim_height", 2)))
	if rng.randf() < STATS.get("vine_chance", 0.55):
		for v in rng.randi_range(1, 2):
			var length := rng.randi_range(3, STATS.get("vine_max", 8))
			var loop: int = rng.randi_range(3, 6) if rng.randf() < STATS.get("loop_chance", 0.5) else 0
			_vines.append([rng.randi_range(2, int(Block.SIZE) - 3 - loop), length, loop])
	var n: int = STATS.blades_per_block
	var bare_from: float = rng.randf_range(-10.0, 6.0) if rng.randf() < STATS.bare_chance else 99.0  # a bare patch in the tuft
	var tall_from: float = rng.randf_range(-10.0, 4.0) if rng.randf() < STATS.tall_chance else 99.0  # a clump of taller blades
	for i in n:
		var slot := (i + rng.randf_range(0.1, 0.9)) / n  # spread evenly, a little jitter
		var bx := floorf(lerpf(-Block.SIZE / 2.0 + 1.0, Block.SIZE / 2.0 - 2.0, slot))
		if bx >= bare_from and bx < bare_from + STATS.bare_width:
			continue
		_x.append(bx)
		var tall: bool = bx >= tall_from and bx < tall_from + STATS.tall_width
		_h.append(rng.randi_range(STATS.height_max, STATS.tall_height_max) if tall else rng.randi_range(STATS.height_min, STATS.height_max))
		_shade.append(rng.randi_range(0, 2))  # dark, mid or light green blade
		_lean.append(0.0)
		_vel.append(0.0)
		_phase.append(rng.randf() * TAU)
		_blood.append(0)
		_blood_color.append(Color.BLACK)
		_crush.append(0.0)
	var seen := VisibleOnScreenNotifier2D.new()  # only animate what is on screen
	seen.rect = Rect2(-Block.SIZE / 2.0 - 8.0, TOP - STATS.height_max - 8.0, Block.SIZE + 16.0, STATS.height_max + 16.0)
	seen.screen_entered.connect(set_process.bind(true))
	seen.screen_exited.connect(set_process.bind(false))
	add_child(seen)
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	var pushers := _pushers()
	if pushers.is_empty():
		_active -= delta
	else:
		_active = ACTIVE_TIME
	if _active <= 0.0:  # nothing touches it: the blades just follow the wind, a few times a second is plenty
		_idle_t += delta
		if _idle_t >= Quality.p("grass_step"):
			_idle_t = 0.0
			_sway_only()
		return
	var lying: Array[bool] = []
	for b in pushers:
		lying.append(b.get("_lying") == true)
	var sig := 0
	var gx := global_position.x
	var t_sway := _time * SWAY_SPEED
	var gain := -STIFFNESS * delta
	var drag := DAMPING * delta
	for i in _x.size():
		var bx := gx + _x[i]
		var target := SWAY * sin(t_sway + bx * 0.12 + _phase[i] * 0.3)
		var flat := 0.0
		var vel := _vel[i]
		for k in pushers.size():
			var b: Node2D = pushers[k]
			var d: float = bx - b.global_position.x
			if lying[k] and absf(d) < CRUSH_HALF:
				flat = 1.0  # a body lying on it presses the blade down, so the body stays in view
			elif absf(d) < PUSH_RADIUS:
				var near: float = 1.0 - absf(d) / PUSH_RADIUS
				target += signf(d if d != 0.0 else 1.0) * PUSH * near
				vel += b.velocity.x * FLICK * near * delta * 10.0
		var lean := _lean[i]
		vel += gain * (lean - target) - drag * vel
		lean = clampf(lean + vel * delta, -_h[i] - 2.0, _h[i] + 2.0)
		_vel[i] = vel
		_lean[i] = lean
		var crush := _crush[i]
		if crush != flat:
			crush = move_toward(crush, flat, CRUSH_SPEED * delta)
			_crush[i] = crush
		sig = (sig * 31 + roundi(lean) + roundi(crush * 8.0)) & 0x7fffffff
	for v in _vines:
		sig = (sig * 31 + roundi(sin(_time * 1.3 + v[0]) * 0.6)) & 0x7fffffff
	if sig != _sig:  # redraw only when a pixel would move: most frames the grass looks the same as the last
		_sig = sig
		queue_redraw()


## At rest the blades sit on the wind's curve with no spring: the cheap path for nearly all the grass on screen.
func _sway_only() -> void:
	var sig := 0
	var gx := global_position.x
	var t_sway := _time * SWAY_SPEED
	for i in _x.size():
		var lean := SWAY * sin(t_sway + (gx + _x[i]) * 0.12 + _phase[i] * 0.3)
		_lean[i] = lean
		_vel[i] = 0.0
		_crush[i] = 0.0
		sig = (sig * 31 + roundi(lean)) & 0x7fffffff
	for v in _vines:
		sig = (sig * 31 + roundi(sin(_time * 1.3 + v[0]) * 0.6)) & 0x7fffffff
	if sig != _sig:
		_sig = sig
		queue_redraw()


## Every body that can press grass and where it is, listed once per frame for all the tufts.
static func _bodies(tree: SceneTree) -> Array:
	var frame := Engine.get_process_frames()
	if frame != _bodies_frame:
		_bodies_frame = frame
		_bodies_cache = tree.get_nodes_in_group("player") + tree.get_nodes_in_group("enemies")
		_bodies_at = PackedVector2Array()
		for b in _bodies_cache:
			_bodies_at.append(b.global_position)
	return _bodies_cache


## Bodies standing on this block: the Bro, enemies and their bodies.
func _pushers() -> Array:
	var out := []
	var bodies := _bodies(get_tree())
	var reach := Block.SIZE / 2.0 + REACH
	var gp := global_position
	var standing_y := gp.y - Block.SIZE  # a body on this block has its origin one tile up
	for j in _bodies_at.size():
		var at := _bodies_at[j]
		if absf(at.y - standing_y) < Block.SIZE * 0.6 and absf(at.x - gp.x) < reach:
			out.append(bodies[j])
	return out


func _draw() -> void:
	var root: int = STATS.root_depth
	draw_rect(Rect2(-Block.SIZE / 2.0, TOP, Block.SIZE, root), COLORS[3])  # closes the notches in the tile's top row
	for x in _rim.size():  # the thin lit rim: bright on top, a mid green below it
		var rim := _rim[x]
		var px := -Block.SIZE / 2.0 + x
		if rim > 0:
			draw_rect(Rect2(px, TOP - rim, 1, rim), COLORS[3] if rim == _rim[maxi(x - 1, 0)] or rim == 1 else COLORS[2])
		draw_rect(Rect2(px, TOP + root, 1, 1), COLORS[2] if x % 2 == 0 else COLORS[1])
	for v in _vines:  # short vines and loops on the face, inside this block only
		var vx: float = -Block.SIZE / 2.0 + v[0]
		var sway := roundf(sin(_time * 1.3 + v[0]) * 0.6)
		for k in v[1]:
			var c: Color = COLORS[1] if k % 3 != 2 else COLORS[0]
			draw_rect(Rect2(vx + (sway if k > 2 else 0.0), TOP + root + 1 + k, 1, 1), c)
			if v[2] > 0:
				draw_rect(Rect2(vx + v[2] + (sway if k > 2 else 0.0), TOP + root + 1 + k, 1, 1), c)
		if v[2] > 0:
			for w in range(1, v[2]):
				draw_rect(Rect2(vx + w + sway, TOP + root + v[1], 1, 1), COLORS[1])
	for i in _x.size():
		var h := _h[i] - roundi(_h[i] * (1.0 - STATS.crushed_share) * _crush[i])
		for k in h + root:
			var t := float(k + 1) / (h + root)
			var x := roundf(_x[i] + _lean[i] * t * t)  # bends more toward the tip
			# root in the tile's bright top color (grows out of the ground), blade body, lighter tip
			var c: Color = COLORS[3] if k < root else COLORS[_shade[i] + (1 if k >= h + root - 2 else 0)]
			if k >= h + root - _blood[i]:
				c = _blood_color[i]
			draw_rect(Rect2(x, TOP + root - k - 1, 1, 1), c)


## A blood drop landed on top of the block at block-space `x`: blades there keep red tips.
func stain_at(x: float, color: Color, pixels := -1) -> void:
	if pixels < 0:
		pixels = STATS.blood_pixels
	for i in _x.size():
		if absf(_x[i] - x) <= 2.0:
			_blood[i] = clampi(maxi(_blood[i], randi_range(1, pixels)), 0, _h[i])
			_blood_color[i] = color
	queue_redraw()


## Explosion at `center` (radius `radius`): every tuft in range whips away from it.
static func blast(tree: SceneTree, center: Vector2, radius: float) -> void:
	var reach: float = radius * STATS.blast_range
	for g in tree.get_nodes_in_group("grass"):
		var d: float = g.global_position.x - center.x
		var dist: float = g.global_position.distance_to(center)
		if dist > reach:
			continue
		var force: float = STATS.blast_push * (1.0 - dist / reach)
		for i in g._x.size():
			var side := signf(d + g._x[i]) if d + g._x[i] != 0.0 else 1.0
			g._vel[i] += side * force * randf_range(0.7, 1.1)
		g._active = ACTIVE_TIME


## The block breaks: every blade flies off as a green particle (red if it was bloody).
func burst() -> void:
	var parent := get_parent().get_parent()
	if parent == null:
		return
	var bits := CPUParticles2D.new()
	bits.one_shot = true
	var got := Quality.take("cpu", Quality.n(maxi(1, _x.size() * STATS.burst_particles)))
	bits.amount = maxi(1, got)
	bits.finished.connect(Quality.give.bind("cpu", got))
	bits.lifetime = 0.9
	bits.explosiveness = 0.95
	bits.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	bits.emission_rect_extents = Vector2(Block.SIZE / 2.0, 2.0)
	bits.direction = Vector2.UP
	bits.spread = 55.0
	bits.initial_velocity_min = 50.0
	bits.initial_velocity_max = 150.0
	bits.gravity = Vector2(0, 380)
	bits.damping_min = 20.0
	bits.damping_max = 60.0
	bits.angular_velocity_min = -360.0
	bits.angular_velocity_max = 360.0
	bits.scale_amount_min = 1.0
	bits.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	ramp.colors = PackedColorArray([COLORS[3], COLORS[2], Color(COLORS[1], 0.0)])
	bits.color_ramp = ramp
	var variety := Gradient.new()  # each particle is one of the grass greens
	variety.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	variety.offsets = PackedFloat32Array([0.0, 0.33, 0.66])
	variety.colors = PackedColorArray([Color(0.7, 0.75, 0.7), Color.WHITE, Color(0.85, 0.95, 0.85)])
	bits.color_initial_ramp = variety
	bits.position = get_parent().position + Vector2(0, TOP - 3.0)
	bits.z_index = 3
	bits.finished.connect(bits.queue_free)
	parent.add_child(bits)
	bits.emitting = true
	var red := 0
	for b in _blood:
		red += 1 if b > 0 else 0
	if red > 0:  # bloody blades fly off red
		BloodDrops.emit(parent, bits.position, Vector2.UP, red * 2, 60.0, 120.0)
