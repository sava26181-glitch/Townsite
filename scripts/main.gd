extends Node3D
## Главное меню и запуск мира.

const WorldScript = preload("res://scripts/world.gd")

var menu: CanvasLayer
var name_edit: LineEdit
var url_edit: LineEdit


func _ready() -> void:
	if Game.autostart:
		start_game(false)
	else:
		_show_menu()


func _show_menu() -> void:
	menu = CanvasLayer.new()
	add_child(menu)
	var th = Theme.new()
	th.default_font_size = 28
	var bn = StyleBoxFlat.new()
	bn.bg_color = Color(0.85, 0.6, 0.15)
	bn.set_corner_radius_all(12)
	bn.content_margin_top = 14
	bn.content_margin_bottom = 14
	var bn2 = bn.duplicate()
	bn2.bg_color = Color(0.2, 0.21, 0.25)
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.055, 0.07)
	menu.add_child(bg)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.theme = th
	menu.add_child(center)
	var v = VBoxContainer.new()
	v.custom_minimum_size = Vector2(560, 0)
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	var title = Label.new()
	title.text = "EMPIRE CITY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.95, 0.7, 0.2))
	v.add_child(title)
	var sub = Label.new()
	sub.text = "ONLINE"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	v.add_child(sub)
	name_edit = LineEdit.new()
	name_edit.text = Game.player_name
	name_edit.placeholder_text = "Твой ник"
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(0, 60)
	v.add_child(name_edit)
	url_edit = LineEdit.new()
	url_edit.text = Game.server_url
	url_edit.placeholder_text = "Адрес сервера wss://..."
	url_edit.custom_minimum_size = Vector2(0, 54)
	url_edit.add_theme_font_size_override("font_size", 20)
	v.add_child(url_edit)
	var b1 = Button.new()
	b1.text = "Играть онлайн"
	b1.add_theme_stylebox_override("normal", bn)
	b1.add_theme_stylebox_override("hover", bn)
	b1.pressed.connect(start_game.bind(true))
	v.add_child(b1)
	var b2 = Button.new()
	b2.text = "Одиночная игра"
	b2.add_theme_stylebox_override("normal", bn2)
	b2.add_theme_stylebox_override("hover", bn2)
	b2.pressed.connect(start_game.bind(false))
	v.add_child(b2)
	var tip = Label.new()
	tip.text = "Слева — джойстик, справа — свайп камеры"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 18)
	tip.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	v.add_child(tip)


func start_game(online: bool) -> void:
	if menu:
		var n = name_edit.text.strip_edges()
		if n != "":
			Game.player_name = n
		Game.server_url = url_edit.text.strip_edges()
		Game.save_game()
		menu.queue_free()
		menu = null
	Game.online = online
	var w = WorldScript.new()
	add_child(w)
	if online:
		Net.connect_to(Game.server_url)
