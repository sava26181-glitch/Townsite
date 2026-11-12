extends Node
## Глобальное состояние игры: деньги, розыск, ввод, сохранения, звуки.

signal money_changed(v)
signal wanted_changed(v)
signal notify(text)

const SAVE_PATH := "user://save.json"
const DEFAULT_SERVER := "wss://empire-city-server.onrender.com"

var player_name = "Игрок"
var server_url = DEFAULT_SERVER
var online = false
var shadows = true

var money = 1000
var ammo = 90
var armor = 0.0
var wanted = 0
var owned_cars: Array = []

var world = null
var player = null
var autostart = false
var shot_dir = ""

# Сенсорный ввод (заполняет HUD)
var joy = Vector2.ZERO
var cam_delta = Vector2.ZERO

var shot_stream: AudioStreamWAV
var boom_stream: AudioStreamWAV
var siren_stream: AudioStreamWAV
var _save_timer = -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_game()
	for a in OS.get_cmdline_user_args():
		if a == "--autostart":
			autostart = true
		if a.begins_with("--shots="):
			shot_dir = a.substr(8)
			autostart = true
	shot_stream = _make_noise_burst(0.35, 9.0, 0.9, 90.0)
	boom_stream = _make_noise_burst(1.6, 2.2, 1.0, 45.0)
	siren_stream = _make_siren()


func _process(delta: float) -> void:
	if _save_timer > 0.0:
		_save_timer -= delta
		if _save_timer <= 0.0:
			save_game()


# ---------------- Ввод ----------------
func _add_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev = InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_add_action("move_f", [KEY_W, KEY_UP])
	_add_action("move_b", [KEY_S, KEY_DOWN])
	_add_action("move_l", [KEY_A, KEY_LEFT])
	_add_action("move_r", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])
	_add_action("sprint", [KEY_SHIFT])
	_add_action("enter", [KEY_F])
	_add_action("shoot", [KEY_CTRL, KEY_J])
	_add_action("interact", [KEY_E])
	_add_action("cam_l", [KEY_Q])
	_add_action("cam_r", [KEY_R])
	_add_action("gas", [])
	_add_action("brake", [])
	_add_action("handbrake", [KEY_SPACE])


func get_move() -> Vector2:
	if joy.length() > 0.08:
		return joy
	var v = Vector2(
		Input.get_action_strength("move_r") - Input.get_action_strength("move_l"),
		Input.get_action_strength("move_b") - Input.get_action_strength("move_f"))
	if v.length() > 1.0:
		v = v.normalized()
	return v


func take_cam_delta() -> Vector2:
	var d = cam_delta
	cam_delta = Vector2.ZERO
	return d


# ---------------- Экономика и розыск ----------------
func add_money(n: int) -> void:
	money = max(0, money + n)
	money_changed.emit(money)
	_save_timer = 2.0


func set_wanted(n: int) -> void:
	var nw: int = clamp(n, 0, 5)
	if nw == wanted:
		return
	wanted = nw
	wanted_changed.emit(wanted)


func add_wanted(n: int) -> void:
	set_wanted(wanted + n)


func say(text: String) -> void:
	notify.emit(text)


# ---------------- Сохранения ----------------
func save_game() -> void:
	var d = {
		"name": player_name, "server": server_url, "money": money, "ammo": ammo,
		"armor": armor, "cars": owned_cars, "shadows": shadows,
	}
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var txt = FileAccess.get_file_as_string(SAVE_PATH)
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return
	player_name = str(d.get("name", player_name))
	server_url = str(d.get("server", server_url))
	money = int(d.get("money", money))
	ammo = int(d.get("ammo", ammo))
	armor = float(d.get("armor", 0.0))
	shadows = bool(d.get("shadows", true))
	var cars = d.get("cars", [])
	if typeof(cars) == TYPE_ARRAY:
		owned_cars = cars


# ---------------- Процедурные звуки ----------------
func _make_noise_burst(length: float, decay: float, vol: float, thump_hz: float) -> AudioStreamWAV:
	var rate = 22050
	var n = int(rate * length)
	var data = PackedByteArray()
	data.resize(n * 2)
	var lp = 0.0
	for i in n:
		var t = float(i) / rate
		var env = exp(-t * decay)
		lp = lerp(lp, randf_range(-1.0, 1.0), 0.35)
		var s = (lp * 0.8 + sin(TAU * thump_hz * t) * 0.6 * exp(-t * decay * 1.5)) * env * vol
		data.encode_s16(i * 2, int(clamp(s, -1.0, 1.0) * 32000.0))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _make_siren() -> AudioStreamWAV:
	var rate = 22050
	var n = rate * 2
	var data = PackedByteArray()
	data.resize(n * 2)
	var ph = 0.0
	for i in n:
		var t = float(i) / rate
		var f = 700.0 + 450.0 * (0.5 + 0.5 * sin(TAU * t * 0.5))
		ph = fmod(ph + f / rate, 1.0)
		var s = (1.0 if ph < 0.5 else -1.0) * 0.18 + sin(TAU * ph) * 0.2
		data.encode_s16(i * 2, int(s * 32000.0))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


func play_3d(stream: AudioStream, pos: Vector3, db := 0.0, pitch := 1.0) -> void:
	if world == null:
		return
	var p = AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	p.max_distance = 180.0
	p.unit_size = 12.0
	world.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
