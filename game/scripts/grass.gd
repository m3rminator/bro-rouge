class_name Grass
extends Node2D
## Grass blades on top of a surface block (design/entities/grass.yaml, GameData.GRASS). No
## sprite: every blade is drawn pixel by pixel and bends on its own spring — wind sway, bodies
## standing in it or running through, explosions (Grass.blast). Blood that lands on a blade
## stays on it (stain_at). When the block breaks, the blades burst into green particles (burst).
## Child of its Block, so it disappears with it.

const STATS := GameData.GRASS
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
var _time := 0.0


func _ready() -> void:
	add_to_group("grass")
	z_index = 3  # in front of feet and bodies: they stand in the grass
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(global_position))  # same grass every time the level loads
	var n: int = STATS.blades_per_block
	for i in n:
		var slot := (i + rng.randf_range(0.1, 0.9)) / n  # spread evenly, a little jitter
		_x.append(floorf(lerpf(-Block.SIZE / 2.0 + 1.0, Block.SIZE / 2.0 - 2.0, slot)))
		_h.append(rng.randi_range(STATS.height_min, STATS.height_max))
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
	for i in _x.size():
		var bx := global_position.x + _x[i]
		var target: float = STATS.sway * sin(_time * STATS.sway_speed + bx * 0.12 + _phase[i] * 0.3)
		var flat := 0.0
		for b in pushers:
			var d: float = bx - b.global_position.x
			if b.get("_lying") and absf(d) < STATS.crush_width / 2.0:
				flat = 1.0  # a body lying on it presses the blade down, so the body stays in view
			elif absf(d) < STATS.push_radius:
				var near: float = 1.0 - absf(d) / STATS.push_radius
				target += signf(d if d != 0.0 else 1.0) * STATS.push * near
				_vel[i] += b.velocity.x * STATS.flick * near * delta * 10.0
		_vel[i] += (-STATS.stiffness * (_lean[i] - target) - STATS.damping * _vel[i]) * delta
		_lean[i] = clampf(_lean[i] + _vel[i] * delta, -_h[i] - 2.0, _h[i] + 2.0)
		_crush[i] = move_toward(_crush[i], flat, STATS.crush_speed * delta)
	queue_redraw()


## Bodies standing on this block: the Bro, enemies and their bodies.
func _pushers() -> Array:
	var out := []
	var standing_y := global_position.y - Block.SIZE  # a body on this block has its origin one tile up
	for b in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("enemies"):
		if absf(b.global_position.y - standing_y) < Block.SIZE * 0.6 \
				and absf(b.global_position.x - global_position.x) < Block.SIZE / 2.0 + maxf(STATS.push_radius, STATS.crush_width / 2.0):
			out.append(b)
	return out


func _draw() -> void:
	var root: int = STATS.root_depth
	draw_rect(Rect2(-Block.SIZE / 2.0, TOP, Block.SIZE, root), COLORS[3])  # closes the notches in the tile's top row
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


## The block breaks: every blade flies off as a green particle (red if it was bloody).
func burst() -> void:
	var parent := get_parent().get_parent()
	if parent == null:
		return
	var bits := CPUParticles2D.new()
	bits.one_shot = true
	bits.amount = maxi(1, _x.size() * STATS.burst_particles)
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
