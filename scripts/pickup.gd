extends Node3D
## Подбираемые деньги (выпадают с прохожих).

const Models = preload("res://scripts/models.gd")

var amount = 50
var life = 40.0
var mesh: MeshInstance3D


func _ready() -> void:
	mesh = MeshInstance3D.new()
	mesh.mesh = Models.box(0.35, 0.12, 0.2)
	mesh.material_override = Models.mat(Color(0.25, 0.65, 0.3), 0.6, 0.0, 0.6)
	mesh.position.y = 0.4
	add_child(mesh)


func _process(delta: float) -> void:
	life -= delta
	mesh.rotation.y += delta * 2.5
	mesh.position.y = 0.4 + sin(life * 3.0) * 0.08
	var pl = Game.player
	if pl and not pl.dead and pl.car == null and pl.global_position.distance_to(global_position) < 1.6:
		Game.add_money(amount)
		Game.say("+$%d" % amount)
		queue_free()
	elif life <= 0.0:
		queue_free()
