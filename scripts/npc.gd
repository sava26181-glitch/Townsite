extends CharacterBody3D
## Пешеход / полицейский / цель миссии.

const Models = preload("res://scripts/models.gd")

var role = "ped"        # ped | cop | target
var health = 100.0
var dead = false
var human: Node3D
var phase = 0.0
var state = "walk"      # walk | flee | chase | idle
var ring: Array = []
var ring_i = 0
var ring_dir = 1
var flee_from = Vector3.ZERO
var flee_t = 0.0
var shoot_cd = 1.0
var busted_t = 0.0
var dead_t = 0.0
var fling = Vector3.ZERO
var facing = 0.0
var walk_speed = 1.4
var look_override = null


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var cs = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	var look: Dictionary
	if role == "cop":
		look = Models.cop_look()
		health = 120.0
		state = "chase"
	else:
		var r = RandomNumberGenerator.new()
		r.randomize()
		look = Models.random_look(r)
		if look_override != null:
			look = look_override
		walk_speed = randf_range(1.1, 1.7)
	human = Models.make_human(look)
	add_child(human)


func setup_ring(points: Array, start: int) -> void:
	ring = points
	ring_i = start
	ring_dir = 1 if randf() < 0.5 else -1


func _physics_process(delta: float) -> void:
	if dead:
		dead_t += delta
		if fling.length() > 0.1:
			velocity = fling
			fling = fling.move_toward(Vector3.ZERO, delta * 12.0)
			velocity.y -= 19.6 * delta
			move_and_slide()
		if dead_t > 25.0:
			queue_free()
		return
	var target_v = Vector3.ZERO
	var pl = Game.player
	match state:
		"walk":
			if ring.size() == 4:
				var tp: Vector3 = ring[ring_i]
				var to = tp - global_position
				to.y = 0.0
				if to.length() < 0.8:
					ring_i = (ring_i + ring_dir + 4) % 4
				else:
					target_v = to.normalized() * walk_speed
		"flee":
			flee_t -= delta
			var away = global_position - flee_from
			away.y = 0.0
			if away.length() < 0.1:
				away = Vector3(randf() - 0.5, 0, randf() - 0.5)
			target_v = away.normalized() * 5.2
			if flee_t <= 0.0:
				state = "walk"
		"chase":
			if pl == null or pl.dead or Game.wanted == 0:
				state = "idle"
			else:
				var to2: Vector3 = pl.global_position - global_position
				to2.y = 0.0
				var dist = to2.length()
				if dist > 7.0:
					target_v = to2.normalized() * 5.0
				facing = atan2(-to2.x, -to2.z)
				shoot_cd -= delta
				if dist < 30.0 and shoot_cd <= 0.0:
					shoot_cd = randf_range(0.9, 1.6)
					_shoot_at(pl)
				if pl.car == null and dist < 2.4 and Game.wanted <= 2:
					busted_t += delta
					if busted_t > 1.2:
						busted_t = 0.0
						Game.world.player_busted()
				else:
					busted_t = 0.0
		"idle":
			if role == "cop" and Game.wanted > 0:
				state = "chase"
	velocity.x = move_toward(velocity.x, target_v.x, delta * 20.0)
	velocity.z = move_toward(velocity.z, target_v.z, delta * 20.0)
	if not is_on_floor():
		velocity.y -= 19.6 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	var hv = Vector2(velocity.x, velocity.z)
	if hv.length() > 0.3 and state != "chase":
		facing = lerp_angle(facing, atan2(-velocity.x, -velocity.z), clamp(delta * 8.0, 0.0, 1.0))
	human.rotation.y = facing
	phase += delta * (4.0 + hv.length() * 1.6)
	var aiming = state == "chase" and shoot_cd < 0.5
	Models.animate_human(human, phase, clamp(hv.length() / 4.0, 0.0, 1.2), aiming)


func _shoot_at(pl) -> void:
	var from = global_position + Vector3(0, 1.45, 0)
	var to: Vector3 = pl.global_position + Vector3(0, 1.2, 0)
	if pl.car != null and is_instance_valid(pl.car):
		to = pl.car.global_position + Vector3(0, 1.0, 0)
	var space = get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit = space.intersect_ray(q)
	Game.play_3d(Game.shot_stream, from, -2.0, 1.1)
	if hit:
		Game.world.tracer(from, hit["position"])
		return
	Game.world.tracer(from, to)
	var chance = 0.35 if pl.car == null else 0.25
	if randf() < chance:
		if pl.car != null and is_instance_valid(pl.car):
			pl.car.take_damage(6.0, false)
			pl.take_damage(3.0)
		else:
			pl.take_damage(9.0)


func alarm(from: Vector3) -> void:
	if dead:
		return
	if role == "cop":
		state = "chase"
		return
	state = "flee"
	flee_from = from
	flee_t = randf_range(6.0, 10.0)


func take_damage(d: float, by_player := true) -> void:
	if dead:
		return
	health -= d
	if role == "cop" and by_player and Game.wanted < 2:
		Game.set_wanted(2)
	if health <= 0.0:
		die(by_player)
	elif role != "cop":
		alarm(Game.player.global_position if Game.player else global_position)


func hit_by_car(c, spd: float) -> void:
	if dead:
		return
	fling = c.linear_velocity * 0.7 + Vector3(0, 4.0, 0)
	take_damage(spd * 6.0, c.driver == "player")


func die(by_player: bool) -> void:
	dead = true
	collision_layer = 0
	collision_mask = 1
	human.rotation.x = -PI / 2
	human.position.y = 0.15
	Game.world.on_npc_killed(self, by_player)
