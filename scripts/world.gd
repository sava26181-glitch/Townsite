extends Node3D
## Игровой мир: окружение и смена дня/ночи, трафик, пешеходы, полиция, бой, онлайн-игроки.

const Models = preload("res://scripts/models.gd")
const CityScript = preload("res://scripts/city.gd")
const PlayerScript = preload("res://scripts/player.gd")
const CarScript = preload("res://scripts/car.gd")
const NpcScript = preload("res://scripts/npc.gd")
const CamScript = preload("res://scripts/cam.gd")
const HudScript = preload("res://scripts/hud.gd")
const MissionScript = preload("res://scripts/missions.gd")
const RemoteScript = preload("res://scripts/remote_player.gd")
const PickupScript = preload("res://scripts/pickup.gd")

const PAINTS := [Color(0.1, 0.2, 0.4), Color(0.6, 0.05, 0.05), Color(0.85, 0.85, 0.87), Color(0.04, 0.04, 0.045),
	Color(0.35, 0.36, 0.38), Color(0.12, 0.3, 0.18), Color(0.45, 0.32, 0.2), Color(0.7, 0.68, 0.6), Color(0.15, 0.15, 0.3)]

var city
var player
var cam
var hud
var missions
var sun: DirectionalLight3D
var env: Environment
var sky_mat: PhysicalSkyMaterial
var time_of_day = 10.0
var cars: Array = []
var peds: Array = []
var police_cars: Array = []
var officers: Array = []
var remotes = {}
var rng = RandomNumberGenerator.new()
var lamp_lights: Array = []
var not_seen_time = 0.0
var traffic_t = 0.0
var police_t = 0.0
var send_t = 0.0
var lamp_t = 0.0
var night = 0.0
var personal_car = null
var dead_t = -1.0
var dead_pos = Vector3.ZERO


func _ready() -> void:
	Game.world = self
	rng.randomize()
	_setup_env()
	city = CityScript.new()
	add_child(city)
	city.build()
	player = PlayerScript.new()
	add_child(player)
	player.global_position = city.spawn_point()
	Game.player = player
	cam = CamScript.new()
	add_child(cam)
	cam.global_position = player.global_position
	missions = MissionScript.new()
	add_child(missions)
	hud = HudScript.new()
	add_child(hud)
	for i in 6:
		var l = OmniLight3D.new()
		l.omni_range = 16.0
		l.light_color = Color(1.0, 0.82, 0.55)
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		lamp_lights.append(l)
	Net.message.connect(_on_net)
	Game.wanted_changed.connect(_on_wanted)
	Game.set_wanted(0)
	# стартовые машины рядом с игроком
	for i in 10:
		_spawn_traffic(30.0, 140.0)
	for i in 18:
		_spawn_ped(10.0, 90.0)
	if Game.shot_dir != "":
		_take_shots()
	hud.show_banner("EMPIRE CITY", "Добро пожаловать! Жёлтые маркеры — задания, зелёный — оружие, синий — автосалон.")


# ---------------- Окружение ----------------
func _setup_env() -> void:
	var we = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	sky_mat = PhysicalSkyMaterial.new()
	sky_mat.turbidity = 8.0
	sky_mat.ground_color = Color(0.25, 0.24, 0.22)
	sky_mat.energy_multiplier = 1.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.68, 0.78)
	env.fog_density = 0.0018
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = Game.shadows
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.5
	add_child(sun)


func _update_daytime(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / 50.0, 24.0)
	var t = time_of_day
	var elev = sin((t - 6.0) / 12.0 * PI) * 70.0
	var day: float = clamp((elev + 4.0) / 18.0, 0.0, 1.0)
	night = 1.0 - day
	sun.rotation_degrees = Vector3(-elev, 210.0 + t * 3.0, 0)
	var w: float = clamp(elev / 30.0, 0.0, 1.0)
	sun.light_color = Color(1.0, lerp(0.62, 0.97, w), lerp(0.42, 0.92, w))
	sun.light_energy = day * 1.25
	sun.visible = elev > -3.0
	env.ambient_light_sky_contribution = lerp(0.0, 1.0, day)
	env.ambient_light_color = Color(0.17, 0.2, 0.32)
	env.ambient_light_energy = lerp(1.0, 1.0, day)
	env.fog_light_color = Color(0.05, 0.06, 0.1).lerp(Color(0.62, 0.68, 0.78), day)
	env.background_energy_multiplier = lerp(0.15, 1.0, day)
	city.set_night(night)


func _update_lamps() -> void:
	var cpos: Vector3 = cam.global_position
	if night < 0.2:
		for l in lamp_lights:
			l.light_energy = 0.0
		return
	var cand: Array = []
	for p in city.lamp_positions:
		var d: float = (p as Vector3).distance_squared_to(cpos)
		if d < 90.0 * 90.0:
			cand.append([d, p])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for i in lamp_lights.size():
		var l: OmniLight3D = lamp_lights[i]
		if i < cand.size():
			l.global_position = cand[i][1]
			l.light_energy = 2.2 * night
		else:
			l.light_energy = 0.0


func _process(delta: float) -> void:
	_update_daytime(delta)
	lamp_t -= delta
	if lamp_t <= 0.0:
		lamp_t = 0.4
		_update_lamps()
	traffic_t -= delta
	if traffic_t <= 0.0:
		traffic_t = 0.5
		_manage_traffic()
		_manage_peds()
	police_t -= delta
	if police_t <= 0.0:
		police_t = 0.5
		_manage_police(0.5)
	if dead_t >= 0.0:
		dead_t -= delta
		if dead_t < 0.0:
			_respawn_after_death()
	if Game.online:
		send_t -= delta
		if send_t <= 0.0:
			send_t = 0.1
			_send_state()
		for id in remotes.keys():
			var r = remotes[id]
			if is_instance_valid(r) and r.last_seen > 10.0:
				r.queue_free()
				remotes.erase(id)


# ---------------- Трафик ----------------
func spawn_car(kind: String, paint: Color, drv: String, from_n: Vector2i, to_n: Vector2i):
	var c = CarScript.new()
	c.kind = kind
	c.paint = paint
	c.driver = drv
	add_child(c)
	c.setup_ai(from_n, to_n)
	c.set_driver(drv)
	cars.append(c)
	return c


func _spawn_traffic(rmin: float, rmax: float) -> void:
	var ppos: Vector3 = player.global_position
	var n = city.random_node_near(ppos, rmin, rmax, rng)
	if n == null:
		return
	var nb: Array = city.neighbors(n)
	var to: Vector2i = nb[rng.randi() % nb.size()]
	var a: Vector3 = city.node_pos(n.x, n.y)
	for c in cars:
		if is_instance_valid(c) and c.global_position.distance_to(a) < 16.0:
			return
	var kinds = ["sedan", "sedan", "sedan", "suv", "suv", "taxi", "van", "sport"]
	var k: String = kinds[rng.randi() % kinds.size()]
	var col: Color = PAINTS[rng.randi() % PAINTS.size()]
	if k == "taxi":
		col = Color(0.95, 0.7, 0.05)
	spawn_car(k, col, "ai", n, to)


func _manage_traffic() -> void:
	var ppos: Vector3 = player.global_position
	var ai = 0
	for c in cars.duplicate():
		if not is_instance_valid(c):
			cars.erase(c)
			continue
		if c == player.car or c == personal_car or c.mission_tag != "":
			continue
		var d: float = c.global_position.distance_to(ppos)
		if d > 230.0 or c.global_position.y < -20.0:
			cars.erase(c)
			police_cars.erase(c)
			c.queue_free()
			continue
		if c.driver == "ai":
			ai += 1
	if ai < 16:
		_spawn_traffic(90.0, 170.0)


func nearest_car(p: Vector3, maxd: float):
	var best = null
	var bd = maxd
	for c in cars:
		if is_instance_valid(c) and not c.dead and c != player.car:
			var d: float = c.global_position.distance_to(p)
			if d < bd:
				bd = d
				best = c
	return best


func spawn_owned_car(k: String) -> void:
	if personal_car != null and is_instance_valid(personal_car) and personal_car != player.car:
		personal_car.queue_free()
	var ppos: Vector3 = player.global_position
	var n: Vector2i = city.nearest_node(ppos)
	var nb: Array = city.neighbors(n)
	var c = spawn_car(k, Color(0.08, 0.08, 0.09) if k != "sport" else Color(0.7, 0.04, 0.04), "none", n, nb[0])
	c.owned = true
	personal_car = c
	Game.say("Твоя машина ждёт на дороге рядом (метка на карте)")


func check_car_hits(c, spd: float) -> void:
	var cp: Vector3 = c.global_position
	var arr: Array = peds + officers
	if player.car == null:
		arr.append(player)
	for p in arr:
		if is_instance_valid(p) and not p.dead:
			var d: float = (p.global_position - cp).length()
			if d < 2.6 and p.global_position.y < cp.y + 1.5:
				p.hit_by_car(c, spd)


# ---------------- Пешеходы ----------------
func _spawn_ped(rmin: float, rmax: float) -> void:
	var sw = city.random_sidewalk_near(player.global_position, rmin, rmax, rng)
	if sw == null:
		return
	var n = NpcScript.new()
	add_child(n)
	n.global_position = sw[0] + Vector3(0, 0.1, 0)
	n.setup_ring(city.block_ring(sw[1]), (int(sw[2]) + 1) % 4)
	peds.append(n)


func spawn_ped_at(pos: Vector3, scared: bool) -> void:
	var n = NpcScript.new()
	add_child(n)
	n.global_position = pos + Vector3(0, 0.3, 0)
	peds.append(n)
	if scared:
		n.alarm(player.global_position)


func spawn_target(pos: Vector3, block: Vector2i, k: int):
	var n = NpcScript.new()
	n.role = "target"
	n.look_override = {"skin": Models.SKINS[0], "hair": Models.HAIRS[1], "shirt": Color(0.1, 0.1, 0.1),
		"pants": Color(0.08, 0.08, 0.09), "jacket": Color(0.7, 0.05, 0.05), "sleeves": true, "cop": false}
	add_child(n)
	n.health = 150.0
	n.global_position = pos + Vector3(0, 0.1, 0)
	n.setup_ring(city.block_ring(block), (k + 1) % 4)
	return n


func _manage_peds() -> void:
	var ppos: Vector3 = player.global_position
	for p in peds.duplicate():
		if not is_instance_valid(p):
			peds.erase(p)
			continue
		if p.global_position.distance_to(ppos) > 140.0:
			peds.erase(p)
			p.queue_free()
	if peds.size() < 26:
		_spawn_ped(45.0, 110.0)


# ---------------- Полиция ----------------
func _on_wanted(w: int) -> void:
	not_seen_time = 0.0
	if w == 0:
		for c in police_cars:
			if is_instance_valid(c):
				c.driver = "ai"
		for o in officers:
			if is_instance_valid(o):
				o.state = "idle"


func police_near(p: Vector3, r: float) -> bool:
	for c in cars:
		if is_instance_valid(c) and c.kind == "police" and c.global_position.distance_to(p) < r:
			return true
	for o in officers:
		if is_instance_valid(o) and not o.dead and o.global_position.distance_to(p) < r:
			return true
	return false


func _manage_police(dt: float) -> void:
	police_cars = police_cars.filter(func(c): return is_instance_valid(c) and not c.dead)
	officers = officers.filter(func(o): return is_instance_valid(o) and not o.dead)
	var ppos: Vector3 = player.global_position
	for o in officers.duplicate():
		if o.global_position.distance_to(ppos) > 160.0:
			officers.erase(o)
			o.queue_free()
	var w = Game.wanted
	if w == 0 or player.dead:
		return
	var want: int = min(1 + w, 6)
	if police_cars.size() < want:
		var n = city.random_node_near(ppos, 70.0, 140.0, rng)
		if n != null:
			var nb: Array = city.neighbors(n)
			var c = spawn_car("police", Color(0.03, 0.03, 0.035), "police", n, nb[rng.randi() % nb.size()])
			police_cars.append(c)
	var seen = police_near(ppos, 55.0 + w * 8.0)
	if seen:
		not_seen_time = 0.0
	else:
		not_seen_time += dt
		if not_seen_time > 10.0 + w * 4.0:
			Game.set_wanted(0)
			hud.show_big("РОЗЫСК СНЯТ", "Ты оторвался от полиции", Color(0.4, 0.8, 1.0))


func deploy_officers(c) -> void:
	for i in 2:
		var o = NpcScript.new()
		o.role = "cop"
		add_child(o)
		o.global_position = c.global_position + c.global_transform.basis.x * (1.8 if i == 0 else -1.8) + Vector3(0, 0.3, 0)
		officers.append(o)


func player_busted() -> void:
	if player.dead or dead_t >= 0.0:
		return
	var loss: int = min(int(Game.money * 0.1), 2000)
	Game.add_money(-loss)
	Game.set_wanted(0)
	missions.cancel_on_death()
	hud.show_big("АРЕСТОВАН", "Штраф $%d" % loss, Color(0.4, 0.6, 1.0))
	player.respawn(city.special_pos("police") + Vector3(0, 0.5, 2))


func on_player_dead() -> void:
	missions.cancel_on_death()
	hud.show_big("ПОТРАЧЕНО", "", Color(0.9, 0.15, 0.15))
	dead_t = 4.0
	Net.send({"t": "dead"})


func _respawn_after_death() -> void:
	var loss: int = min(int(Game.money * 0.1), 1500)
	Game.add_money(-loss)
	Game.set_wanted(0)
	player.respawn(city.spawn_point())
	Game.say("Больница: счёт за лечение $%d" % loss)


# ---------------- Бой ----------------
func find_target(origin: Vector3, fwd: Vector3, maxd: float, exclude):
	var best = null
	var best_score = -1.0
	var cands: Array = peds + officers
	for r in remotes.values():
		cands.append(r)
	for c in cars:
		if is_instance_valid(c) and c != player.car:
			cands.append(c)
	for t in cands:
		if not is_instance_valid(t) or t == exclude:
			continue
		if t.get("dead") == true:
			continue
		var to: Vector3 = t.global_position + Vector3(0, 1.0, 0) - origin
		var d = to.length()
		if d > maxd or d < 0.5:
			continue
		var flat = Vector3(to.x, 0, to.z).normalized()
		var dot = flat.dot(fwd)
		if dot < 0.86:
			continue
		var score = dot * 2.0 - d / maxd
		if t is VehicleBody3D:
			score -= 0.6
		if t.get("role") == "cop" or t.get("role") == "target":
			score += 0.2
		if score > best_score:
			best_score = score
			best = t
	return best


func shots_fired(p: Vector3) -> void:
	for n in peds:
		if is_instance_valid(n) and not n.dead and n.global_position.distance_to(p) < 45.0:
			n.alarm(p)
	if Game.wanted == 0 and police_near(p, 50.0):
		Game.set_wanted(1)


func on_npc_killed(n, by_player: bool) -> void:
	if not by_player:
		return
	if n.role == "cop":
		Game.set_wanted(max(Game.wanted + 1, 2))
	elif n.role == "ped":
		if Game.wanted < 1 or police_near(n.global_position, 60.0):
			Game.add_wanted(1)
	if rng.randf() < 0.6:
		var pk = PickupScript.new()
		pk.amount = rng.randi_range(20, 120)
		add_child(pk)
		pk.global_position = n.global_position + Vector3(0, 0.1, 0)


func explosion(p: Vector3, src) -> void:
	cam.shake = clamp(1.5 - cam.global_position.distance_to(p) / 40.0, 0.0, 1.5)
	var arr: Array = peds + officers + [player]
	for t in arr:
		if is_instance_valid(t) and not t.dead and t.global_position.distance_to(p) < 7.0:
			t.take_damage(90.0, true)
	for c in cars:
		if is_instance_valid(c) and c != src and not c.dead and c.global_position.distance_to(p) < 6.0:
			c.take_damage(40.0, false)
	if Game.wanted < 2 and police_near(p, 80.0):
		Game.add_wanted(1)


func tracer(a: Vector3, b: Vector3) -> void:
	var mi = MeshInstance3D.new()
	var im = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	mi.mesh = im
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.9, 0.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var fl = OmniLight3D.new()
	fl.omni_range = 5.0
	fl.light_energy = 3.0
	fl.light_color = Color(1.0, 0.8, 0.4)
	add_child(fl)
	fl.global_position = a
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)
	get_tree().create_timer(0.05).timeout.connect(fl.queue_free)


# ---------------- Онлайн ----------------
func _send_state() -> void:
	var d = {"t": "state", "dead": player.dead}
	if player.car != null and is_instance_valid(player.car):
		var c = player.car
		d["p"] = [c.global_position.x, c.global_position.y, c.global_position.z]
		d["r"] = c.global_rotation.y
		d["car"] = c.kind
		d["col"] = (c.paint as Color).to_html(false)
	else:
		d["p"] = [player.global_position.x, player.global_position.y, player.global_position.z]
		d["r"] = player.facing
		d["car"] = ""
	Net.send(d)


func _on_net(d: Dictionary) -> void:
	var t = str(d.get("t", ""))
	match t:
		"state":
			var id = str(d.get("id", ""))
			if id == "" or id == Net.my_id:
				return
			if not remotes.has(id):
				var r = RemoteScript.new()
				r.id = id
				r.pname = str(d.get("name", "Игрок"))
				add_child(r)
				var p = d.get("p", [0, 0, 0])
				r.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
				remotes[id] = r
			remotes[id].apply_state(d)
		"leave":
			var id2 = str(d.get("id", ""))
			if remotes.has(id2):
				remotes[id2].queue_free()
				remotes.erase(id2)
		"chat":
			hud.add_chat(str(d.get("name", "?")), str(d.get("text", "")))
		"hit":
			if not player.dead:
				player.take_damage(float(d.get("dmg", 10.0)))
				if player.dead:
					Net.send({"t": "killed", "by": str(d.get("from", ""))})
		"count":
			hud.net_lbl.text = "Онлайн: %d игроков" % int(d.get("n", 1))


# ---------------- Скриншоты для согласования (CI) ----------------
func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await _wait(3)
	var img = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(Game.shot_dir)
	img.save_png(Game.shot_dir.path_join(shot_name + ".png"))
	print("SHOT ", shot_name)


func _take_shots() -> void:
	time_of_day = 10.5
	await _wait(90)
	cam.yaw = 2.4
	cam.pitch = -0.12
	await _wait(40)
	await _shot("1_street_day")
	var n: Vector2i = city.nearest_node(player.global_position)
	var c = spawn_car("sport", Color(0.7, 0.04, 0.04), "none", n, city.neighbors(n)[0])
	await _wait(20)
	player.enter_car(c)
	cam.yaw = atan2(-c.global_transform.basis.z.x, -c.global_transform.basis.z.z) + 0.6
	cam.pitch = -0.18
	await _wait(60)
	await _shot("2_car_day")
	cam.free_mode = true
	cam.global_position = Vector3(-60, 95, 330)
	cam.rotation = Vector3(-0.32, 0.25, 0)
	cam.arm.spring_length = 0.0
	await _wait(40)
	await _shot("3_city_aerial")
	cam.global_position = Vector3(city.node_pos(4, 5).x + 4, 2.2, city.node_pos(4, 5).z + 30)
	cam.rotation = Vector3(0.05, 0.0, 0)
	await _wait(30)
	await _shot("4_street_level")
	time_of_day = 21.5
	await _wait(60)
	await _shot("5_night")
	cam.free_mode = false
	cam.arm.spring_length = 7.5
	time_of_day = 17.5
	Game.set_wanted(3)
	await _wait(400)
	cam.yaw += PI
	await _wait(30)
	await _shot("6_police_sunset")
	get_tree().quit()
