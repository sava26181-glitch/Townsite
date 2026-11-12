extends VehicleBody3D
## Машина: физика VehicleBody3D, управление игроком, ИИ трафика и полиции, урон и взрыв.

const Models = preload("res://scripts/models.gd")

var kind = "sedan"
var paint = Color(0.1, 0.2, 0.4)
var driver = "none"   # none | player | ai | police
var spec: Dictionary
var health = 100.0
var dead = false
var wheels: Array = []
var body_node: Node3D
var ray: RayCast3D
var ai_from = Vector2i.ZERO
var ai_to = Vector2i.ZERO
var stuck_t = 0.0
var reverse_t = 0.0
var deployed = false
var mission_tag = ""
var owned = false
var prev_vel = Vector3.ZERO
var siren: AudioStreamPlayer3D
var light_t = 0.0
var headlights: Array = []
var engine_player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var eng_phase = 0.0
var burn_t = 0.0
var fire_light: OmniLight3D
var flip_t = 0.0
var max_force = 5000.0
var vmax = 40.0


func _ready() -> void:
	spec = Models.car_spec(kind)
	mass = spec["mass"]
	max_force = spec["force"]
	vmax = spec["vmax"]
	collision_layer = 2
	collision_mask = 1 | 2
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.45, 0.1)
	can_sleep = false
	var L: float = spec["L"]
	var W: float = spec["W"]
	var wr: float = spec["wr"]
	var wbz: float = spec["wb"]
	# коллизия: корпус + кабина
	var base = Models.car_base(kind)
	var belt = 0.95
	var roof_h = Models.car_top_y(kind)
	if base == "van":
		belt = 2.1
	elif base == "suv":
		belt = 1.15
	elif base == "sport":
		belt = 0.8
	var cs = CollisionShape3D.new()
	var bs = BoxShape3D.new()
	bs.size = Vector3(W * 0.95, belt - 0.32, L * 0.98)
	cs.shape = bs
	cs.position = Vector3(0, (belt + 0.32) / 2.0, 0)
	add_child(cs)
	if base != "van":
		var cs2 = CollisionShape3D.new()
		var bs2 = BoxShape3D.new()
		bs2.size = Vector3(W * 0.75, roof_h - belt, L * 0.45)
		cs2.shape = bs2
		cs2.position = Vector3(0, (roof_h + belt) / 2.0, -0.1)
		add_child(cs2)
	body_node = Models.make_car_body(kind, paint)
	add_child(body_node)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w = VehicleWheel3D.new()
			w.position = Vector3(sx * (W / 2.0 - 0.08), wr + 0.18, sz * wbz)
			w.wheel_radius = wr
			w.suspension_rest_length = 0.18
			w.suspension_travel = 0.2
			w.suspension_stiffness = 45.0 if base != "sport" else 60.0
			w.suspension_max_force = mass * 12.0
			w.damping_compression = 0.9
			w.damping_relaxation = 1.2
			w.wheel_friction_slip = 2.6
			w.wheel_roll_influence = 0.25
			w.use_as_steering = sz > 0.0
			w.use_as_traction = sz < 0.0 or base == "suv"
			w.add_child(Models.make_wheel(wr))
			add_child(w)
			wheels.append(w)
	ray = RayCast3D.new()
	ray.position = Vector3(0, 0.7, L / 2.0 + 0.3)
	ray.target_position = Vector3(0, 0, 9.0)
	ray.collision_mask = 2 | 4
	ray.add_exception(self)
	add_child(ray)
	if kind == "police":
		siren = AudioStreamPlayer3D.new()
		siren.stream = Game.siren_stream
		siren.unit_size = 18.0
		siren.max_distance = 220.0
		siren.volume_db = -6.0
		add_child(siren)


func set_driver(d: String) -> void:
	driver = d
	if d == "player":
		_start_engine_sound()
		_set_headlights(true)
		brake = 0.0
	else:
		if engine_player:
			engine_player.queue_free()
			engine_player = null
			playback = null
		if d == "none":
			engine_force = 0.0
			brake = 3.0
			_set_headlights(false)


func _set_headlights(on: bool) -> void:
	if on and headlights.is_empty():
		var hl: float = spec["L"] / 2.0
		for sx in [-0.6, 0.6]:
			var sp = SpotLight3D.new()
			sp.position = Vector3(sx, 0.65, hl + 0.1)
			sp.rotation = Vector3(-0.08, PI, 0)
			sp.spot_range = 40.0
			sp.spot_angle = 28.0
			sp.light_energy = 3.0
			sp.light_color = Color(1.0, 0.95, 0.85)
			sp.shadow_enabled = false
			add_child(sp)
			headlights.append(sp)
	elif not on:
		for h in headlights:
			h.queue_free()
		headlights.clear()


func setup_ai(from_n: Vector2i, to_n: Vector2i) -> void:
	ai_from = from_n
	ai_to = to_n
	var city = Game.world.city
	var a: Vector3 = city.node_pos(from_n.x, from_n.y)
	var b: Vector3 = city.node_pos(to_n.x, to_n.y)
	var dir = (b - a).normalized()
	var right = Vector3(-dir.z, 0, dir.x)
	var pos = a + dir * (city.R * 0.5 + 6.0) + right * city.LANE + Vector3(0, 0.15, 0)
	global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), pos)
	linear_velocity = dir * 8.0


func _lane_target(fa: Vector2i, ta: Vector2i) -> Vector3:
	var city = Game.world.city
	var a: Vector3 = city.node_pos(fa.x, fa.y)
	var b: Vector3 = city.node_pos(ta.x, ta.y)
	var dir = (b - a).normalized()
	var right = Vector3(-dir.z, 0, dir.x)
	return b - dir * (city.R * 0.5 + 1.0) + right * city.LANE


func forward_speed() -> float:
	return linear_velocity.dot(global_transform.basis.z)


func _physics_process(delta: float) -> void:
	if dead:
		burn_t += delta
		engine_force = 0.0
		brake = 5.0
		if fire_light:
			fire_light.light_energy = 3.0 + sin(burn_t * 20.0) * 1.0
		if burn_t > 35.0:
			queue_free()
		return
	# урон от ударов
	var dv = (prev_vel - linear_velocity).length()
	if dv > 9.0:
		take_damage((dv - 9.0) * 4.0, false)
		if driver == "player":
			Game.world.cam.shake = 0.8
	prev_vel = linear_velocity
	match driver:
		"player":
			_player_drive(delta)
		"ai":
			_ai_drive(delta, false)
		"police":
			_ai_drive(delta, true)
		_:
			engine_force = 0.0
			steering = move_toward(steering, 0.0, delta)
	if kind == "police":
		light_t += delta
		var chasing = driver == "police" and Game.wanted > 0
		if siren:
			if chasing and not siren.playing:
				siren.play()
			elif not chasing and siren.playing:
				siren.stop()
	# сбивание пешеходов
	var spd = linear_velocity.length()
	if spd > 5.0:
		Game.world.check_car_hits(self, spd)


func _player_drive(delta: float) -> void:
	var mv = Game.get_move()
	var spd = forward_speed()
	var gas = Input.is_action_pressed("gas") or mv.y < -0.35
	var brk = Input.is_action_pressed("brake") or mv.y > 0.35
	var steer_max = 0.55 * (1.0 - clamp(absf(spd) / 70.0, 0.0, 0.6))
	steering = move_toward(steering, -mv.x * steer_max, delta * 2.8)
	if gas:
		engine_force = max_force if spd < vmax else 0.0
		brake = 0.0
	elif brk:
		if spd > 1.5:
			engine_force = 0.0
			brake = 25.0
		else:
			engine_force = -max_force * 0.6
			brake = 0.0
	else:
		engine_force = 0.0
		brake = 1.5
	var hb = Input.is_action_pressed("handbrake")
	for w in wheels:
		var ww: VehicleWheel3D = w
		if not ww.use_as_steering:
			ww.wheel_friction_slip = 1.2 if hb else 2.6
	if hb:
		brake = max(brake, 8.0)
	# переворот: ставим на колёса
	if global_transform.basis.y.y < 0.3 and linear_velocity.length() < 2.0:
		flip_t += delta
		if flip_t > 1.5:
			var f = global_transform.basis.z
			f.y = 0
			global_transform = Transform3D(Basis.looking_at(-f.normalized(), Vector3.UP), global_position + Vector3(0, 1.2, 0))
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			flip_t = 0.0
	else:
		flip_t = 0.0
	_fill_engine(absf(spd) / vmax, gas)


func _ai_drive(delta: float, police: bool) -> void:
	var city = Game.world.city
	var target: Vector3
	var cruise = 11.0
	var pl = Game.player
	var chase = police and Game.wanted > 0 and pl != null
	var tpos: Vector3
	if chase:
		tpos = pl.global_position
		if pl.car != null and is_instance_valid(pl.car):
			tpos = pl.car.global_position
	if chase and global_position.distance_to(tpos) < 40.0:
		target = tpos
		cruise = 26.0
		var dist = global_position.distance_to(tpos)
		if pl.car == null and dist < 13.0:
			cruise = 0.0
			if not deployed:
				deployed = true
				Game.world.deploy_officers(self)
	else:
		target = _lane_target(ai_from, ai_to)
		var to_t = target - global_position
		to_t.y = 0.0
		if to_t.length() < 8.0:
			var nb: Array = city.neighbors(ai_to)
			if nb.size() > 1:
				nb.erase(ai_from)
			var nxt: Vector2i = nb[randi() % nb.size()]
			if chase:
				var pn: Vector2i = city.nearest_node(tpos)
				var best = 1e9
				for c in nb:
					var cc: Vector2i = c
					var dd = Vector2(cc - pn).length()
					if dd < best:
						best = dd
						nxt = cc
			ai_from = ai_to
			ai_to = nxt
			target = _lane_target(ai_from, ai_to)
		if chase:
			cruise = 24.0
	var local = to_local(target)
	var ang = atan2(local.x, local.z)
	var spd = forward_speed()
	if reverse_t > 0.0:
		reverse_t -= delta
		steering = -clamp(ang, -0.6, 0.6)
		engine_force = -max_force * 0.5
		brake = 0.0
		return
	steering = move_toward(steering, clamp(ang * 1.3, -0.6, 0.6), delta * 3.0)
	var desired = cruise
	if absf(ang) > 0.45:
		desired = min(desired, 8.0)
	if not chase and ray.is_colliding():
		desired = 0.0
	if spd < desired - 0.5:
		engine_force = max_force * (0.9 if chase else 0.55)
		brake = 0.0
	elif spd > desired + 1.5:
		engine_force = 0.0
		brake = 10.0
	else:
		engine_force = 0.0
		brake = 0.6 if desired > 0.0 else 6.0
	# застряли — сдаём назад
	if desired > 2.0 and absf(spd) < 0.6:
		stuck_t += delta
		if stuck_t > 2.5:
			stuck_t = 0.0
			reverse_t = 1.4
	else:
		stuck_t = 0.0


func eject_driver() -> void:
	Game.world.spawn_ped_at(global_position + global_transform.basis.x * 1.8, true)
	driver = "none"


func take_damage(d: float, by_player := true) -> void:
	if dead:
		return
	health -= d
	if by_player and driver == "police" and Game.wanted < 1:
		Game.set_wanted(1)
	if health <= 0.0:
		explode()


func explode() -> void:
	dead = true
	var burnt = Models.mat(Color(0.06, 0.05, 0.05), 0.9)
	_burn(body_node, burnt)
	for w in wheels:
		_burn(w, burnt)
	apply_central_impulse(Vector3(0, mass * 5.0, 0))
	apply_torque_impulse(Vector3(randf() - 0.5, 0, randf() - 0.5) * mass * 2.0)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.5, 0.15)
	fire_light.omni_range = 12.0
	fire_light.light_energy = 4.0
	fire_light.position.y = 1.2
	add_child(fire_light)
	if siren:
		siren.stop()
	set_driver("none")
	Game.play_3d(Game.boom_stream, global_position, 8.0, 0.8)
	Game.world.explosion(global_position, self)


func _burn(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for i in mi.get_surface_override_material_count():
			mi.set_surface_override_material(i, m)
	for c in n.get_children():
		_burn(c, m)


# ---------------- Звук двигателя ----------------
func _start_engine_sound() -> void:
	if engine_player:
		return
	engine_player = AudioStreamPlayer.new()
	var g = AudioStreamGenerator.new()
	g.mix_rate = 22050.0
	g.buffer_length = 0.12
	engine_player.stream = g
	engine_player.volume_db = -9.0
	add_child(engine_player)
	engine_player.play()
	playback = engine_player.get_stream_playback()


func _fill_engine(rpm: float, gas: bool) -> void:
	if playback == null:
		return
	var frames = playback.get_frames_available()
	var gear_rpm = fmod(rpm * 4.0, 1.0) * 0.6 + rpm * 0.4
	var f = 38.0 + gear_rpm * 150.0 + (10.0 if gas else 0.0)
	var amp = 0.18 + (0.1 if gas else 0.0)
	for i in frames:
		eng_phase = fmod(eng_phase + f / 22050.0, 1.0)
		var s = (eng_phase * 2.0 - 1.0) * amp * 0.6 + sin(eng_phase * TAU * 2.0) * amp * 0.5 + randf_range(-0.02, 0.02)
		playback.push_frame(Vector2(s, s))
