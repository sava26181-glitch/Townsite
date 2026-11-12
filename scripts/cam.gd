extends Node3D
## Камера от третьего лица: свайп по правой половине экрана, автодоводка за машиной.

var yaw = 0.0
var pitch = -0.22
var arm: SpringArm3D
var camera: Camera3D
var idle_t = 0.0
var shake = 0.0
var free_mode = false


func _ready() -> void:
	arm = SpringArm3D.new()
	arm.spring_length = 4.6
	arm.collision_mask = 1
	arm.margin = 0.3
	var sh = SphereShape3D.new()
	sh.radius = 0.25
	arm.shape = sh
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.1
	camera.far = 1600.0
	arm.add_child(camera)
	camera.current = true


func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right_flat() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


func _process(delta: float) -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl) or free_mode:
		return
	var d = Game.take_cam_delta()
	var kb = Input.get_action_strength("cam_r") - Input.get_action_strength("cam_l")
	yaw -= d.x * 0.0065 + kb * delta * 2.2
	pitch = clamp(pitch - d.y * 0.0045, -1.25, 0.4)
	if d.length() > 0.5 or absf(kb) > 0.0:
		idle_t = 0.0
	else:
		idle_t += delta
	var car = pl.car
	var focus: Vector3
	var target_len = 4.4
	var target_fov = 68.0
	if car != null and is_instance_valid(car):
		focus = car.global_position + Vector3(0, 1.5, 0)
		target_len = 7.5 if car.kind != "van" else 9.0
		var spd: float = car.linear_velocity.length()
		target_fov = 68.0 + clamp(spd * 0.35, 0.0, 22.0)
		if idle_t > 1.0 and spd > 2.0:
			var f: Vector3 = car.global_transform.basis.z
			var mv: Vector3 = car.linear_velocity
			if mv.dot(f) < -1.0:
				f = -f
			var ty = atan2(-f.x, -f.z)
			yaw = lerp_angle(yaw, ty, clamp(delta * 2.5, 0.0, 1.0))
			pitch = lerp(pitch, -0.2, delta * 1.5)
		global_position = focus
	else:
		focus = pl.global_position + Vector3(0, 1.55, 0)
		if pl.aiming:
			target_len = 3.0
			focus += right_flat() * 0.55
		global_position = global_position.lerp(focus, clamp(delta * 14.0, 0.0, 1.0))
	arm.spring_length = lerp(arm.spring_length, target_len, clamp(delta * 4.0, 0.0, 1.0))
	camera.fov = lerp(camera.fov, target_fov, clamp(delta * 3.0, 0.0, 1.0))
	rotation = Vector3(pitch, yaw, 0)
	if shake > 0.0:
		shake = max(0.0, shake - delta * 2.0)
		camera.h_offset = randf_range(-1, 1) * shake * 0.15
		camera.v_offset = randf_range(-1, 1) * shake * 0.15
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
