class_name DiscoGrenade
extends CharacterBody2D
## The Men in Black Bro's disco grenade (design/entities/disco.yaml, GameData.DISCO). Thrown like a grenade;
## when it comes to rest on the ground a party zone lights up around it (floor glow, spinning light spots and
## beams, colours that never stop changing) and enemies in range walk toward it. After party_time it goes off in
## a burst of light and the enemies near it panic (enemy.gd: they jump about and shoot each other).

const STATS := GameData.DISCO
const FRAMES := preload("res://assets/sprites/disco_grenade_frames.tres")
const WORLD_MASK := 1

var _sprite: AnimatedSprite2D
var _landed := false
var _party := 0.0
var _time := 0.0
var _lure := 0.0
var _music: AudioStreamPlayer  # the disco groove loop while the zone is lit


static func throw(parent: Node, pos: Vector2, vel: Vector2) -> DiscoGrenade:
	var g := DiscoGrenade.new()
	g.position = pos
	g.velocity = vel
	parent.add_child(g)
	return g


func _ready() -> void:
	add_to_group("disco_grenades")
	z_index = 3
	collision_layer = 0
	collision_mask = WORLD_MASK
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = STATS.radius
	shape.shape = circle
	add_child(shape)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.play("disco")
	_sprite.position = Vector2(0, -1)
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	_time += delta
	velocity.y += STATS.gravity * delta
	var hit := move_and_collide(velocity * delta)
	if hit:
		var n := hit.get_normal()
		if n.y < -0.5 and absf(velocity.y) < 70.0:  # on the ground: roll to a stop
			velocity.y = 0.0
			velocity.x = move_toward(velocity.x, 0.0, STATS.roll_friction * delta)
			if absf(velocity.x) < 8.0 and not _landed:
				_landed = true
				velocity = Vector2.ZERO
				Sfx.play(self, "grenade_bounce", -8.0, 0.1)
				_start_music()
		else:
			if velocity.length() > 70.0:
				Sfx.play(self, "grenade_bounce", -8.0, 0.1)
			velocity = velocity.bounce(n) * STATS.bounce
	if _landed:
		_party += delta
		_lure -= delta
		if _lure <= 0.0:  # now and then, call in everyone in range
			_lure = 0.25
			for e in get_tree().get_nodes_in_group("enemies"):
				if not e.dead and e.global_position.distance_to(global_position) <= STATS.lure_range:
					e.disco_lure(self)
		if _party >= STATS.party_time:
			_burst()
	queue_redraw()


## The party is over: a flash of light, and every enemy near it goes into panic.
func _burst() -> void:
	Shockwave.emit(get_parent(), global_position, STATS.zone_radius * 1.4, 0.6, true)
	Sfx.play(self, "disco_burst", -2.0)
	var caught := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead or e.is_in_group("bosses"):
			continue
		if e.global_position.distance_to(global_position) <= STATS.zone_radius * 1.6 or e.is_lured_by(self):
			caught.append(e)
	var soldiers := caught.filter(func(e): return not e.party_doom).size()
	for e in caught:
		e.disco_panic(STATS.panic_time, soldiers == 1)  # a soldier on his own has nobody to kill him
	queue_free()


func _start_music() -> void:
	var path := "res://assets/sfx/disco_party.mp3"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStreamMP3 = load(path).duplicate()
	stream.loop = true
	Volume.ensure()
	_music = AudioStreamPlayer.new()
	_music.bus = Volume.MUSIC_BUS
	_music.stream = stream
	_music.volume_db = -8.0
	add_child(_music)  # leaves with the grenade, so the loop stops at the burst
	_music.play()


func _draw() -> void:
	if not _landed:
		return
	var hue := fmod(_time * 0.7, 1.0)
	var r: float = STATS.zone_radius
	var pulse := 0.5 + 0.5 * sin(_time * 9.0)
	draw_circle(Vector2.ZERO, r, Color.from_hsv(hue, 0.8, 1.0, 0.10 + 0.05 * pulse))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color.from_hsv(fmod(hue + 0.5, 1.0), 0.9, 1.0, 0.5), 1.0, false)
	for i in 5:  # light beams swinging up and out of the ball
		var a := -PI / 2.0 + sin(_time * 2.2 + i * 1.7) * 1.2
		var c := Color.from_hsv(fmod(hue + i * 0.2, 1.0), 0.85, 1.0, 0.22)
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - 0.1) * r * 1.1, Vector2.from_angle(a + 0.1) * r * 1.1]), c)
	var n: int = STATS.light_spots
	for i in n:  # spots circling on the floor glow
		var a2 := _time * 1.6 + i * TAU / n
		var p := Vector2(cos(a2) * r * 0.75, sin(a2) * r * 0.25)
		draw_circle(p, 3.0, Color.from_hsv(fmod(hue + float(i) / n, 1.0), 0.8, 1.0, 0.85))
