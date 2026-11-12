extends CharacterBody3D
## Игрок: ходьба/бег/прыжок, стрельба с автоприцелом, посадка в машины.

const Models = preload("res://scripts/models.gd")

var human: Node3D
var car = null
var health = 100.0
var dead = false
var aiming = false
var phase = 0.0
var shoot_cd = 0.0
var aim_t = 0.0
var facing = 0.0
var invuln = 0.0
var look: Dictionary


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var cs = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	var r = RandomNumberGenerator.new()
	r.seed = hash(Game.player_name)
	look = Models.random_look(r)
	look["jacket"] = Color(0.1, 0.1, 0.11)
	human = Models.make_human(look)
	add_child(human)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)


func _physics_process(delta: float) -> void:
	if dead:
		return
	invuln = max(0.0, invuln - delta)
	if car != null:
		if not is_instance_valid(car):
			car = null
			_show(true)
		else:
			global_position = car.global_position + Vector3(0, 0.3, 0)
			if Input.is_action_just_pressed("enter"):
				exit_car()
			return
	var cam = Game.world.cam
	var mv = Game.get_move()
	var dir: Vector3 = cam.forward_flat() * (-mv.y) + cam.right_flat() * mv.x
	var sprint = Input.is_action_pressed("sprint") or mv.length() > 0.95
	var spd = 7.5 if sprint else 3.2
	if mv.length() < 0.6 and not Input.is_action_pressed("sprint"):
		spd = 3.2 * mv.length() / 0.6
	var target_v = dir * spd
	var accel = 12.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, target_v.x, accel * delta * 6.0)
	velocity.z = move_toward(velocity.z, target_v.z, accel * delta * 6.0)
	if not is_on_floor():
		velocity.y -= 19.6 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = 7.0
	move_and_slide()
	# поворот модели
	var hv = Vector2(velocity.x, velocity.z)
	aim_t = max(0.0, aim_t - delta)
	aiming = aim_t > 0.0
	if aiming:
		pass
	elif hv.length() > 0.3:
		facing = lerp_angle(facing, atan2(-velocity.x, -velocity.z), clamp(delta * 12.0, 0.0, 1.0))
	human.rotation.y = facing
	# анимация
	var amt: float = clamp(hv.length() / 4.0, 0.0, 1.25)
	phase += delta * (4.0 + hv.length() * 1.6)
	Models.animate_human(human, phase, amt if is_on_floor() else 0.3, aiming)
	# стрельба
	shoot_cd = max(0.0, shoot_cd - delta)
	if Input.is_action_pressed("shoot") and shoot_cd <= 0.0:
		shoot()
	if Input.is_action_just_pressed("enter"):
		var c = Game.world.nearest_car(global_position, 4.0)
		if c != null:
			enter_car(c)
	if global_position.y < -30.0:
		global_position = Game.world.city.spawn_point()
		velocity = Vector3.ZERO


func shoot() -> void:
	if Game.ammo <= 0:
		Game.say("Нет патронов — купи в оружейном магазине")
		shoot_cd = 0.6
		return
	Game.ammo -= 1
	shoot_cd = 0.22
	aim_t = 1.2
	var cam = Game.world.cam
	var origin = global_position + Vector3(0, 1.45, 0)
	var fwd: Vector3 = cam.forward_flat()
	var target = Game.world.find_target(origin, fwd, 40.0, self)
	var aim_point: Vector3
	if target != null:
		aim_point = target.global_position + Vector3(0, 1.2, 0)
		if target is VehicleBody3D:
			aim_point = target.global_position + Vector3(0, 0.7, 0)
	else:
		aim_point = origin + (fwd + Vector3(0, -sin(-cam.pitch) * 0.6, 0)).normalized() * 60.0
	var d = (aim_point - origin)
	facing = atan2(-d.x, -d.z)
	human.rotation.y = facing
	var hand = origin + (aim_point - origin).normalized() * 0.6
	var space = get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(hand, aim_point + d.normalized() * 2.0, 1 | 2 | 4, [get_rid()])
	var hit = space.intersect_ray(q)
	var end = aim_point
	if hit:
		end = hit["position"]
		var col = hit["collider"]
		if col != null and col.has_method("take_damage"):
			col.take_damage(34.0, true)
	elif target != null and target.has_method("take_damage"):
		target.take_damage(34.0, true)
	Game.world.tracer(hand, end)
	Game.play_3d(Game.shot_stream, hand, 2.0)
	Game.world.shots_fired(global_position)


func take_damage(amount: float, _by_player := false) -> void:
	if dead or invuln > 0.0:
		return
	if Game.armor > 0.0:
		var a: float = min(Game.armor, amount * 0.7)
		Game.armor -= a
		amount -= a
	health -= amount
	Game.world.hud.flash_damage()
	if health <= 0.0:
		health = 0.0
		die()


func hit_by_car(c, spd: float) -> void:
	if car != null or dead:
		return
	take_damage(spd * 2.5)
	velocity = c.linear_velocity * 0.6 + Vector3(0, 5, 0)


func die() -> void:
	if dead:
		return
	if car != null:
		exit_car()
	dead = true
	human.rotation.x = -PI / 2
	human.position.y = 0.2
	Game.world.on_player_dead()


func respawn(pos: Vector3) -> void:
	dead = false
	health = 100.0
	human.rotation.x = 0.0
	human.position.y = 0.0
	global_position = pos
	velocity = Vector3.ZERO
	invuln = 3.0


func enter_car(c) -> void:
	if c.dead:
		return
	if c.driver == "ai" or c.driver == "police":
		c.eject_driver()
		if c.kind == "police":
			Game.add_wanted(2)
			Game.say("Угон полицейской машины!")
		elif Game.world.police_near(global_position, 45.0):
			Game.add_wanted(1)
	car = c
	c.set_driver("player")
	_show(false)
	collision_layer = 0
	collision_mask = 0
	Game.world.missions.on_enter_car(c)


func exit_car() -> void:
	var c = car
	car = null
	_show(true)
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	if c != null and is_instance_valid(c):
		c.set_driver("none")
		var side: Vector3 = c.global_transform.basis.x
		global_position = c.global_position + side * 1.6 + Vector3(0, 0.2, 0)
		velocity = c.linear_velocity * 0.5


func _show(v: bool) -> void:
	human.visible = v
