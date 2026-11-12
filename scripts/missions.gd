extends Node3D
## Маркеры (магазины, больница, задания) и миссии: доставка, угон на заказ, заказное убийство, гонка.

const Models = preload("res://scripts/models.gd")

const INFO := {
	"mission_a": ["Задания: Лестер", Color(1.0, 0.8, 0.1)],
	"mission_b": ["Задания: Франклин", Color(1.0, 0.8, 0.1)],
	"mission_c": ["Задания: Тревор", Color(1.0, 0.8, 0.1)],
	"ammu": ["Оружейный магазин", Color(0.3, 0.9, 0.3)],
	"cars": ["Автосалон", Color(0.3, 0.6, 1.0)],
	"garage": ["Гараж", Color(0.7, 0.4, 1.0)],
	"hospital": ["Больница", Color(1.0, 0.3, 0.3)],
	"police": ["Полиция", Color(0.3, 0.4, 1.0)],
}

var markers = {}
var near = ""
var active: Dictionary = {}
var beam: MeshInstance3D
var rng = RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	var city = Game.world.city
	for k in city.special.keys():
		var pos: Vector3 = city.special_pos(k)
		markers[k] = pos
		var info: Array = INFO[k]
		_make_marker(pos, info[1], info[0])
	beam = MeshInstance3D.new()
	var bm = Models.cyl(1.2, 120.0, -1.0, 12)
	bm.cap_top = false
	bm.cap_bottom = false
	beam.mesh = bm
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.85, 0.1, 0.28)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	add_child(beam)


func _make_marker(pos: Vector3, col: Color, text: String) -> void:
	var n = Node3D.new()
	n.position = pos
	add_child(n)
	var mi = MeshInstance3D.new()
	var cm = Models.cyl(1.0, 1.4, 1.0, 20)
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.r, col.g, col.b, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position.y = 0.7
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var l = Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 3.0
	l.font_size = 56
	l.outline_size = 12
	l.modulate = col.lightened(0.3)
	n.add_child(l)


func _process(delta: float) -> void:
	var pl = Game.player
	if pl == null or pl.dead:
		return
	var ppos: Vector3 = pl.global_position
	near = ""
	for k in markers.keys():
		var mp: Vector3 = markers[k]
		if ppos.distance_to(mp) < 2.8:
			near = k
	if near != "" and Input.is_action_just_pressed("interact"):
		_interact(near)
	if not active.is_empty():
		_update_mission(delta, ppos)


func _interact(k: String) -> void:
	var hud = Game.world.hud
	match k:
		"mission_a", "mission_b", "mission_c":
			if not active.is_empty():
				Game.say("Сначала закончи текущее задание")
			else:
				var types = ["delivery", "steal", "hit", "race"]
				start_mission(types[rng.randi() % types.size()])
		"ammu", "cars", "garage", "hospital":
			hud.open_shop(k)
		"police":
			if Game.wanted > 0 and Game.money >= 1000 * Game.wanted:
				Game.add_money(-1000 * Game.wanted)
				Game.set_wanted(0)
				Game.say("Взятка принята. Розыск снят.")
			else:
				Game.say("Здесь можно откупиться от розыска: $1000 за звезду")


# ---------------- Миссии ----------------
func start_mission(t: String) -> void:
	var city = Game.world.city
	var ppos: Vector3 = Game.player.global_position
	active = {"type": t, "time": 0.0, "step": 0}
	match t:
		"delivery":
			var sw = city.random_sidewalk_near(ppos, 250.0, 450.0, rng)
			if sw == null:
				active = {}
				return
			active["target"] = sw[0]
			var dist = ppos.distance_to(sw[0])
			active["time"] = 35.0 + dist / 9.0
			active["reward"] = int(250 + dist * 1.2)
			_announce("ДОСТАВКА", "Отвези посылку в отмеченную точку. Успей до конца таймера!")
		"steal":
			var n = city.random_node_near(ppos, 200.0, 380.0, rng)
			if n == null:
				active = {}
				return
			var nb: Array = city.neighbors(n)
			var c = Game.world.spawn_car("sport", Color(0.85, 0.65, 0.12), "none", n, nb[0])
			c.mission_tag = "steal"
			active["car"] = c
			active["target"] = c.global_position
			active["reward"] = 2500
			_announce("УГОН НА ЗАКАЗ", "Угони золотой спорткар и пригони его в гараж.")
		"hit":
			var sw2 = city.random_sidewalk_near(ppos, 180.0, 360.0, rng)
			if sw2 == null:
				active = {}
				return
			var npc = Game.world.spawn_target(sw2[0], sw2[1], sw2[2])
			active["npc"] = npc
			active["target"] = sw2[0]
			active["reward"] = 1800
			_announce("ЗАКАЗ", "Устрани цель в красной куртке. Это привлечёт полицию.")
		"race":
			var pts: Array = []
			var cur: Vector2i = city.nearest_node(ppos)
			var prev = Vector2i(-1, -1)
			for i in 8:
				var nb2: Array = city.neighbors(cur)
				nb2.erase(prev)
				var nx: Vector2i = nb2[rng.randi() % nb2.size()]
				prev = cur
				cur = nx
				pts.append(city.node_pos(cur.x, cur.y) + Vector3(0, 0.2, 0))
			active["points"] = pts
			active["target"] = pts[0]
			active["time"] = 70.0
			active["reward"] = 1500
			_announce("УЛИЧНАЯ ГОНКА", "Садись в машину и проедь все 8 чекпоинтов за 70 секунд.")
	beam.visible = true


func _announce(title: String, text: String) -> void:
	Game.world.hud.show_banner(title, text)


func _update_mission(delta: float, ppos: Vector3) -> void:
	var t: String = active["type"]
	var hud = Game.world.hud
	if active.has("time") and float(active["time"]) > 0.0:
		active["time"] = float(active["time"]) - delta
		if float(active["time"]) <= 0.0:
			fail("Время вышло")
			return
	var tgt: Vector3 = active["target"]
	match t:
		"delivery":
			hud.set_mission("Доставь посылку  •  %d м" % int(ppos.distance_to(tgt)), active["time"])
			if ppos.distance_to(tgt) < 5.0:
				complete()
		"steal":
			var c = active["car"]
			if c == null or not is_instance_valid(c) or c.dead:
				fail("Машина уничтожена")
				return
			if Game.player.car != c:
				active["target"] = c.global_position
				hud.set_mission("Угони золотой спорткар", -1.0)
			else:
				var g: Vector3 = markers["garage"]
				active["target"] = g
				hud.set_mission("Пригони машину в гараж  •  %d м" % int(ppos.distance_to(g)), -1.0)
				if ppos.distance_to(g) < 7.0:
					Game.player.exit_car()
					c.queue_free()
					complete()
		"hit":
			var npc = active["npc"]
			if npc == null or not is_instance_valid(npc) or npc.dead:
				Game.add_wanted(2)
				complete()
				return
			active["target"] = npc.global_position
			hud.set_mission("Устрани цель  •  %d м" % int(ppos.distance_to(npc.global_position)), -1.0)
		"race":
			if Game.player.car == null:
				hud.set_mission("Сядь в машину!", active["time"])
				return
			var pts: Array = active["points"]
			hud.set_mission("Гонка: чекпоинт %d/%d" % [active["step"] + 1, pts.size()], active["time"])
			if ppos.distance_to(tgt) < 10.0:
				active["step"] = int(active["step"]) + 1
				Game.play_3d(Game.shot_stream, ppos, -12.0, 2.5)
				if int(active["step"]) >= pts.size():
					complete()
					return
				active["target"] = pts[active["step"]]
	if not active.is_empty():
		beam.global_position = (active["target"] as Vector3) + Vector3(0, 60, 0)


func complete() -> void:
	var reward: int = active.get("reward", 500)
	Game.add_money(reward)
	Game.world.hud.show_big("ЗАДАНИЕ ВЫПОЛНЕНО", "+$%d" % reward, Color(1.0, 0.8, 0.2))
	_clear()


func fail(why: String) -> void:
	Game.world.hud.show_big("ЗАДАНИЕ ПРОВАЛЕНО", why, Color(1.0, 0.3, 0.3))
	if active.has("car") and is_instance_valid(active["car"]) and Game.player.car != active["car"]:
		active["car"].queue_free()
	_clear()


func _clear() -> void:
	active = {}
	beam.visible = false
	Game.world.hud.set_mission("", -1.0)


func on_enter_car(c) -> void:
	if not active.is_empty() and active["type"] == "steal" and active.get("car") == c:
		Game.set_wanted(max(Game.wanted, 1))


func target_pos():
	if active.is_empty():
		return null
	return active["target"]


func cancel_on_death() -> void:
	if not active.is_empty():
		fail("Ты выбыл из игры")
