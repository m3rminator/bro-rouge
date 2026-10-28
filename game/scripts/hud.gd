class_name Hud
extends CanvasLayer
## On-screen HUD (design/entities/hud.yaml). Top-left: hearts + extra lives (X1). Top-center: level.
## Under them: spare magazines, then grenades left. Top-right: kills / quota. Center: big messages. Under the top line: the Brute's health bar.

const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")
var VIEW_W := int(Screen.view().x)
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
var _lives := PixelText.make(Vector2(6, 6), PixelText.Align.LEFT)  # "X1": extra lives, right of the hearts
var _player: Node  # Bruce's fury shows in the boost line
var _fists := false  # Bruce has no gun: no ammo text
var _ammo := PixelText.make(Vector2(6, 17), PixelText.Align.LEFT)
var _boosts := PixelText.make(Vector2(6, 62), PixelText.Align.LEFT)  # running crate boosts and their seconds
var _level := PixelText.make(Vector2(VIEW_W / 2.0, 4), PixelText.Align.CENTER)
var _kills := PixelText.make(Vector2(VIEW_W - 36, 4), PixelText.Align.RIGHT)
var _message := PixelText.make(Vector2(VIEW_W / 2.0, 92), PixelText.Align.CENTER, 2)
var _sub := PixelText.make(Vector2(VIEW_W / 2.0, 110), PixelText.Align.CENTER)
var _note := PixelText.make(Vector2(VIEW_W / 2.0, 16), PixelText.Align.CENTER)  # the small line for short notices
var _note_time := 0.0
var _boss_name := PixelText.make(Vector2(VIEW_W / 2.0, 14), PixelText.Align.CENTER)
var _boss_back := ColorRect.new()
var _boss_fill := ColorRect.new()
var _boss_ticks: Array[ColorRect] = []  # dividers between the phase blocks of the bar
var _message_time := 0.0
var _shell_icon: AnimatedSprite2D  # shell-count Bro (Sharif): one shell icon and the number
var _shell_count := PixelText.make(Vector2(22, 31), PixelText.Align.LEFT)


func _ready() -> void:
	layer = 10
	for t in [_lives, _ammo, _boosts, _level, _kills, _message, _sub, _note, _boss_name]:
		add_child(t)
	_boss_back.position = Vector2(VIEW_W / 2.0 - 60, 22)
	_boss_back.size = Vector2(120, 5)
	_boss_back.color = OUTLINE
	_boss_fill.position = _boss_back.position + Vector2(1, 1)
	_boss_fill.size = Vector2(118, 3)
	_boss_fill.color = RED
	add_child(_boss_back)
	add_child(_boss_fill)
	for i in GameData.BRUTE.phases - 1:
		var tick := ColorRect.new()
		tick.color = OUTLINE
		tick.size = Vector2(1, 5)
		tick.position = _boss_back.position + Vector2(1.0 + 118.0 * (i + 1) / GameData.BRUTE.phases, 0)
		add_child(tick)
		_boss_ticks.append(tick)
	_show_boss(false)


func track(player: Node) -> void:
	for i in Run.bro_stats().max_hp:
		var heart := AnimatedSprite2D.new()
		heart.sprite_frames = FX_FRAMES
		heart.animation = "heart_full"
		heart.position = Vector2(10 + i * 9, 10)
		add_child(heart)
		_hearts.append(heart)
	var stats := Run.bro_stats()
	_lives.position.x = 10 + stats.max_hp * 9
	if stats.shells_start > 0:
		_shell_icon = AnimatedSprite2D.new()
		_shell_icon.sprite_frames = ITEM_FRAMES
		_shell_icon.animation = "shell_hud"
		_shell_icon.position = Vector2(12, 34)
		add_child(_shell_icon)
		add_child(_shell_count)
	for i in stats.max_spare_mags:
		var mag := AnimatedSprite2D.new()
		mag.sprite_frames = ITEM_FRAMES
		mag.animation = stats.hud_mag_icon
		mag.position = Vector2(12 + i * 12, 34)
		mag.visible = false
		add_child(mag)
		_mags.append(mag)
	var icon_frames: SpriteFrames = ITEM_FRAMES
	var icon: String = "shield_hud" if stats.explosive == "defend" else stats.explosive + "_hud"  # c4_hud, airstrike_hud, revolver_hud (the plain grenade has grenade_hud)
	if stats.explosive == "disco":
		icon_frames = load("res://assets/sprites/disco_grenade_frames.tres")
	elif not ITEM_FRAMES.has_animation(icon):
		icon = "grenade_hud"
	_fists = stats.weapon == "fists"
	for i in Run.grenade_max():
		var g := AnimatedSprite2D.new()
		g.sprite_frames = icon_frames
		g.animation = icon
		g.position = Vector2(12 + i * 14, 51)
		add_child(g)
		_grenades.append(g)
	player.grenades_changed.connect(_on_grenades_changed)
	player.hp_changed.connect(_on_hp_changed)
	player.ammo_changed.connect(_on_ammo_changed)
	_player = player
	if _fists:
		player.fury_started.connect(func(): message("FURY", RED, 1.8, "TWO BLOWS KILL - BLOCKS ONE HIT"))
		player.fury_ended.connect(func(): message("FURY BROKEN", YELLOW, 1.2))


func show_level(number: int, loop: int, title: String) -> void:
	_level.text = ("LOOP %d  " % loop if loop > 1 else "") + "LEVEL %d  %s" % [number, title]


## A screen with no kill counter (the starting zone).
func show_title(text: String) -> void:
	_level.text = text
	_kills.text = ""


## Safe house: no kill counter.
func show_hub() -> void:
	_level.text = "SAFE HOUSE"
	_kills.text = ""


## `lives` counts the Bro himself, so the extra ones are one fewer: "X1" next to the hearts.
func set_lives(lives: int) -> void:
	var extra := maxi(lives - 1, 0)
	_lives.text = "X%d" % extra
	_lives.color = RED if extra == 0 else WHITE


func set_kills(kills: int, quota: int) -> void:
	_kills.text = "KILLS %d/%d" % [kills, quota]
	_kills.color = GREEN if kills >= quota else WHITE


## A short notice is a small line under the level name; only a message that stays (seconds = 0: dying, a cleared level)
## is the big one in the middle, until the next message.
func message(text: String, color: Color, seconds := 2.0, sub := "") -> void:
	if seconds > 0.0:
		_note.text = text if sub == "" else "%s - %s" % [text, sub]
		_note.color = color
		_note_time = seconds
		return
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
	var names := {"mag": "MAG", "rate": "FIRE", "speed": "SPEED", "damage": "DMG"}
	var boosts := ""
	for kind in Run.upgrades:
		boosts += "%s %d  " % [names[kind], ceili(Run.upgrades[kind])]
	_boosts.color = GREEN
	if _fists and _player != null and is_instance_valid(_player) and _player.fury_left() > 0.0:
		boosts += "FURY %d" % ceili(_player.fury_left())
		_boosts.color = RED
	_boosts.text = boosts
	_note_time -= delta
	if _note_time <= 0.0 and _note.text != "":
		_note.text = ""
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
	for tick in _boss_ticks:
		tick.visible = on


func _on_grenades_changed(left: int) -> void:
	for i in _grenades.size():
		_grenades[i].visible = i < left


func _on_ammo_changed(in_mag: int, spare_mags: int, reloading: bool) -> void:
	if _fists:
		_ammo.text = ""
		return
	if _shell_icon != null:  # shells: icon and number, no magazines, no reload
		_ammo.text = ""
		_shell_count.text = str(in_mag)
		_shell_count.color = RED if in_mag <= 5 else WHITE
		return
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
