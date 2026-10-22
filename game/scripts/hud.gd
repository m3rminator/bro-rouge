class_name Hud
extends CanvasLayer
## On-screen HUD (design/entities/hud.yaml). Top-left: hearts + lives. Top-center: level.
## Under them: spare magazines, then grenades left. Top-right: kills / quota. Center: big messages. Under the top line: the Brute's health bar.

const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")
const VIEW_W := 480
# master palette
const WHITE := Color("f4f2e8")
const YELLOW := Color("ffd23e")
const RED := Color("e85a50")
const GREEN := Color("7cc04e")
const OUTLINE := Color("14101e")
const BAR_BACK := Color("4a4858")
const ITEM_FRAMES := preload("res://assets/sprites/items_frames.tres")

var _hearts: Array[AnimatedSprite2D] = []
var _mags: Array[AnimatedSprite2D] = []  # one magazine icon per spare magazine (items/mag_hud)
var _grenades: Array[AnimatedSprite2D] = []  # one grenade icon per grenade left (items/grenade_hud)
var _lives := PixelText.make(Vector2(6, 17), PixelText.Align.LEFT)
var _ammo := PixelText.make(Vector2(6, 27), PixelText.Align.LEFT)
var _level := PixelText.make(Vector2(VIEW_W / 2.0, 4), PixelText.Align.CENTER)
var _kills := PixelText.make(Vector2(VIEW_W - 6, 4), PixelText.Align.RIGHT)
var _message := PixelText.make(Vector2(VIEW_W / 2.0, 92), PixelText.Align.CENTER, 2)
var _sub := PixelText.make(Vector2(VIEW_W / 2.0, 110), PixelText.Align.CENTER)
var _boss_name := PixelText.make(Vector2(VIEW_W / 2.0, 14), PixelText.Align.CENTER)
var _boss_back := ColorRect.new()
var _boss_fill := ColorRect.new()
var _message_time := 0.0


func _ready() -> void:
	layer = 10
	for t in [_lives, _ammo, _level, _kills, _message, _sub, _boss_name]:
		add_child(t)
	_boss_back.position = Vector2(VIEW_W / 2.0 - 60, 22)
	_boss_back.size = Vector2(120, 5)
	_boss_back.color = OUTLINE
	_boss_fill.position = _boss_back.position + Vector2(1, 1)
	_boss_fill.size = Vector2(118, 3)
	_boss_fill.color = RED
	add_child(_boss_back)
	add_child(_boss_fill)
	_show_boss(false)


func track(player: Node) -> void:
	for i in Run.bro_stats().max_hp:
		var heart := AnimatedSprite2D.new()
		heart.sprite_frames = FX_FRAMES
		heart.animation = "heart_full"
		heart.position = Vector2(10 + i * 9, 10)
		add_child(heart)
		_hearts.append(heart)
	for i in Run.bro_stats().max_spare_mags:
		var mag := AnimatedSprite2D.new()
		mag.sprite_frames = ITEM_FRAMES
		mag.animation = "mag_hud"
		mag.position = Vector2(12 + i * 12, 44)
		mag.visible = false
		add_child(mag)
		_mags.append(mag)
	for i in GameData.GRENADE.grenades_per_level:
		var g := AnimatedSprite2D.new()
		g.sprite_frames = ITEM_FRAMES
		g.animation = "grenade_hud"
		g.position = Vector2(12 + i * 14, 61)
		add_child(g)
		_grenades.append(g)
	player.grenades_changed.connect(_on_grenades_changed)
	player.hp_changed.connect(_on_hp_changed)
	player.ammo_changed.connect(_on_ammo_changed)


func show_level(number: int, loop: int, title: String) -> void:
	_level.text = ("LOOP %d  " % loop if loop > 1 else "") + "LEVEL %d  %s" % [number, title]


## Safe house: no kill counter.
func show_hub() -> void:
	_level.text = "SAFE HOUSE"
	_kills.text = ""


func set_lives(lives: int) -> void:
	_lives.text = "LIVES %d" % lives
	_lives.color = RED if lives <= 1 else WHITE


func set_kills(kills: int, quota: int) -> void:
	_kills.text = "KILLS %d/%d" % [kills, quota]
	_kills.color = GREEN if kills >= quota else WHITE


## Big center message. seconds = 0 keeps it until the next message.
func message(text: String, color: Color, seconds := 2.0, sub := "") -> void:
	_message.text = text
	_message.color = color
	_sub.text = sub
	_message_time = seconds if seconds > 0.0 else INF


func track_boss(boss: Node) -> void:
	_boss_name.text = "BRUTE"
	_boss_name.color = RED
	_show_boss(true)
	boss.health_changed.connect(_on_boss_health)


func _process(delta: float) -> void:
	_message_time -= delta
	if _message_time <= 0.0 and _message.text != "":
		_message.text = ""
		_sub.text = ""


func _on_hp_changed(hp: int, _max_hp: int) -> void:
	for i in _hearts.size():
		_hearts[i].animation = "heart_full" if i < hp else "heart_empty"


func _on_boss_health(hp: int, max_hp: int) -> void:
	_boss_fill.size.x = 118.0 * hp / max_hp
	if hp <= 0:
		get_tree().create_timer(1.5).timeout.connect(_show_boss.bind(false))


func _show_boss(on: bool) -> void:
	_boss_name.visible = on
	_boss_back.visible = on
	_boss_fill.visible = on


func _on_grenades_changed(left: int) -> void:
	for i in _grenades.size():
		_grenades[i].visible = i < left


func _on_ammo_changed(in_mag: int, spare_mags: int, reloading: bool) -> void:
	for i in _mags.size():
		_mags[i].visible = i < spare_mags
	if reloading:
		_ammo.text = "RELOADING"
		_ammo.color = YELLOW
	elif in_mag == 0 and spare_mags == 0:
		_ammo.text = "NO AMMO"
		_ammo.color = RED
	else:
		_ammo.text = "AMMO %d" % in_mag
		_ammo.color = RED if in_mag <= 8 else WHITE
