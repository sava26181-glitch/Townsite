extends Node3D
## Другой игрок онлайн: плавная интерполяция позиции, модель человека или машины.

const Models = preload("res://scripts/models.gd")

var id = ""
var pname = "Игрок"
var human: Node3D
var car_node: Node3D
var car_kind = ""
var target_pos = Vector3.ZERO
var target_yaw = 0.0
var label: Label3D
var phase = 0.0
var dead = false
var last_seen = 0.0


func _ready() -> void:
	var r = RandomNumberGenerator.new()
	r.seed = hash(pname)
	var look = Models.random_look(r)
	look["jacket"] = Color(0.1, 0.1, 0.11)
	human = Models.make_human(look)
	add_child(human)
	label = Label3D.new()
	label.text = pname
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.3
	label.font_size = 48
	label.outline_size = 10
	label.modulate = Color(0.5, 0.9, 1.0)
	label.no_depth_test = true
	add_child(label)


func apply_state(d: Dictionary) -> void:
	last_seen = 0.0
	var p = d.get("p", [0, 0, 0])
	if typeof(p) == TYPE_ARRAY and p.size() == 3:
		target_pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	target_yaw = float(d.get("r", 0.0))
	dead = bool(d.get("dead", false))
	var nm = str(d.get("name", pname))
	if nm != pname:
		pname = nm
		label.text = nm
	var ck = str(d.get("car", ""))
	if ck != car_kind:
		car_kind = ck
		if car_node:
			car_node.queue_free()
			car_node = null
		if ck != "" and Models.CARS.has(Models.car_base(ck)):
			var col = Color.html(str(d.get("col", "#336699")))
			car_node = Models.make_car_body(ck, col)
			var sp = Models.car_spec(ck)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var w = Models.make_wheel(sp["wr"])
					w.position = Vector3(sx * (sp["W"] / 2.0 - 0.08), sp["wr"], sz * sp["wb"])
					car_node.add_child(w)
			add_child(car_node)
		human.visible = ck == ""


func _process(delta: float) -> void:
	last_seen += delta
	var before = global_position
	global_position = global_position.lerp(target_pos, clamp(delta * 10.0, 0.0, 1.0))
	if car_node:
		car_node.rotation.y = lerp_angle(car_node.rotation.y, target_yaw, clamp(delta * 10.0, 0.0, 1.0))
	else:
		human.rotation.y = lerp_angle(human.rotation.y, target_yaw, clamp(delta * 10.0, 0.0, 1.0))
		var v = (global_position - before).length() / max(delta, 0.001)
		phase += delta * (4.0 + v * 1.6)
		Models.animate_human(human, phase, clamp(v / 4.0, 0.0, 1.2))
		human.rotation.x = -PI / 2 if dead else 0.0


func take_damage(d: float, _by_player := true) -> void:
	Net.send({"t": "hit", "target": id, "dmg": d})
