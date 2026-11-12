extends CanvasLayer
## Интерфейс: сенсорный джойстик и кнопки, мини-карта, деньги, звёзды, здоровье,
## миссии, магазины, чат и пауза.

var theme_main: Theme
var money_lbl: Label
var info_lbl: Label
var mission_lbl: Label
var timer_lbl: Label
var notify_lbl: Label
var notify_t = 0.0
var big_title: Label
var big_sub: Label
var big_t = 0.0
var banner: PanelContainer
var banner_t = 0.0
var damage_rect: ColorRect
var damage_t = 0.0
var stars: Control
var minimap: Control
var bars: Control
var joy_draw: Control
var chat_lbl: Label
var chat_lines: Array = []
var chat_edit: LineEdit
var chat_box: HBoxContainer
var shop: PanelContainer
var shop_list: VBoxContainer
var shop_title: Label
var pause_panel: PanelContainer
var net_lbl: Label
var buttons = {}
var joy_index = -1
var joy_center = Vector2.ZERO
var joy_pos = Vector2.ZERO
var cam_index = -1
var root: Control
var top_hb: HBoxContainer


func _ready() -> void:
	layer = 10
	theme_main = Theme.new()
	theme_main.default_font_size = 24
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	theme_main.set_stylebox("panel", "PanelContainer", sb)
	var bn = StyleBoxFlat.new()
	bn.bg_color = Color(0.16, 0.17, 0.2)
	bn.set_corner_radius_all(10)
	bn.content_margin_left = 16
	bn.content_margin_right = 16
	bn.content_margin_top = 10
	bn.content_margin_bottom = 10
	var bh = bn.duplicate()
	bh.bg_color = Color(0.85, 0.6, 0.15)
	theme_main.set_stylebox("normal", "Button", bn)
	theme_main.set_stylebox("hover", "Button", bn)
	theme_main.set_stylebox("pressed", "Button", bh)
	theme_main.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	root = Control.new()
	root.theme = theme_main
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	damage_rect = ColorRect.new()
	damage_rect.color = Color(0.8, 0.0, 0.0, 0.0)
	damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_rect)

	minimap = MiniMap.new()
	minimap.position = Vector2(20, 20)
	minimap.size = Vector2(210, 210)
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)
	bars = Bars.new()
	bars.position = Vector2(20, 236)
	bars.size = Vector2(210, 22)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bars)

	money_lbl = _label(38, Color(0.55, 0.95, 0.55))
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_lbl.position = Vector2(-330, 14)
	money_lbl.size = Vector2(310, 50)
	stars = Stars.new()
	stars.position = Vector2(-290, 64)
	stars.size = Vector2(270, 50)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stars)
	info_lbl = _label(22, Color(0.9, 0.9, 0.9))
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_lbl.position = Vector2(-330, 112)
	info_lbl.size = Vector2(310, 30)
	net_lbl = _label(18, Color(0.5, 0.85, 1.0))
	net_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	net_lbl.position = Vector2(-330, 140)
	net_lbl.size = Vector2(310, 26)

	mission_lbl = _label(26, Color(1.0, 0.85, 0.3))
	mission_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_lbl.position = Vector2(-350, 16)
	mission_lbl.size = Vector2(700, 36)
	timer_lbl = _label(30, Color(1, 1, 1))
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_lbl.position = Vector2(-100, 52)
	timer_lbl.size = Vector2(200, 40)

	notify_lbl = _label(26, Color(1, 1, 1))
	notify_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notify_lbl.position = Vector2(-400, -250)
	notify_lbl.size = Vector2(800, 40)

	big_title = _label(72, Color(1, 0.3, 0.3))
	big_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_title.position = Vector2(-600, -90)
	big_title.size = Vector2(1200, 100)
	big_sub = _label(30, Color(1, 1, 1))
	big_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_sub.position = Vector2(-600, 10)
	big_sub.size = Vector2(1200, 50)

	banner = PanelContainer.new()
	banner.position = Vector2(-330, 100)
	banner.custom_minimum_size = Vector2(660, 0)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bv = VBoxContainer.new()
	bv.name = "VBox"
	banner.add_child(bv)
	var bt = Label.new()
	bt.name = "T"
	bt.add_theme_font_size_override("font_size", 34)
	bt.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	bv.add_child(bt)
	var bs2 = Label.new()
	bs2.name = "S"
	bs2.autowrap_mode = TextServer.AUTOWRAP_WORD
	bv.add_child(bs2)
	banner.visible = false
	root.add_child(banner)

	chat_lbl = _label(20, Color(1, 1, 1))
	chat_lbl.position = Vector2(244, 84)
	chat_lbl.size = Vector2(500, 200)
	chat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD

	joy_draw = JoyDraw.new()
	joy_draw.hud = self
	joy_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(joy_draw)

	_top_buttons()
	_make_touch_buttons()
	_make_shop()
	_make_pause()
	get_viewport().size_changed.connect(_layout)
	_layout()
	Game.notify.connect(func(t): show_notify(t))
	Net.status_changed.connect(func(t): net_lbl.text = t)
	net_lbl.text = "Онлайн: подключение..." if Game.online else "Одиночная игра"


func _label(size: int, col: Color) -> Label:
	var l = Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", max(4, size / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _top_buttons() -> void:
	var hb = HBoxContainer.new()
	top_hb = hb
	hb.position = Vector2(220, 96)
	hb.add_theme_constant_override("separation", 10)
	root.add_child(hb)
	var pause = Button.new()
	pause.text = "  II  "
	pause.pressed.connect(func(): pause_panel.visible = true)
	hb.add_child(pause)
	if Game.online:
		var chat = Button.new()
		chat.text = "Чат"
		chat.pressed.connect(func(): chat_box.visible = not chat_box.visible)
		hb.add_child(chat)
	chat_box = HBoxContainer.new()
	chat_box.position = Vector2(-300, 150)
	chat_box.visible = false
	root.add_child(chat_box)
	chat_edit = LineEdit.new()
	chat_edit.custom_minimum_size = Vector2(460, 50)
	chat_edit.placeholder_text = "Сообщение..."
	chat_edit.max_length = 120
	chat_box.add_child(chat_edit)
	var send = Button.new()
	send.text = "Отправить"
	send.pressed.connect(_send_chat)
	chat_edit.text_submitted.connect(func(_t): _send_chat())
	chat_box.add_child(send)


func _send_chat() -> void:
	var t = chat_edit.text.strip_edges()
	if t != "":
		Net.send({"t": "chat", "text": t})
	chat_edit.text = ""
	chat_box.visible = false


func add_chat(who: String, text: String) -> void:
	chat_lines.append("%s: %s" % [who, text])
	while chat_lines.size() > 6:
		chat_lines.pop_front()
	chat_lbl.text = "\n".join(chat_lines)


# ---------------- Сенсорные кнопки ----------------
func _circle_tex(r: int, col: Color) -> ImageTexture:
	var d = r * 2
	var img = Image.create(d, d, false, Image.FORMAT_RGBA8)
	for y in d:
		for x in d:
			var dist = Vector2(x - r + 0.5, y - r + 0.5).length()
			var c = Color(0, 0, 0, 0)
			if dist <= r - 4:
				c = Color(col.r, col.g, col.b, col.a)
			elif dist <= r:
				c = Color(1, 1, 1, 0.55)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _btn(id: String, text: String, action: String, r: float, col: Color) -> void:
	var b = TouchScreenButton.new()
	b.texture_normal = _circle_tex(int(r), Color(col.r, col.g, col.b, 0.35))
	b.texture_pressed = _circle_tex(int(r), Color(col.r, col.g, col.b, 0.7))
	var sh = CircleShape2D.new()
	sh.radius = r
	b.shape = sh
	b.action = action
	var l = Label.new()
	l.text = text
	l.size = Vector2(r * 2, r * 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(r * 0.36))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	add_child(b)
	buttons[id] = {"node": b, "r": r}


func _make_touch_buttons() -> void:
	_btn("shoot", "ОГОНЬ", "shoot", 72, Color(0.9, 0.2, 0.2))
	_btn("jump", "ПРЫЖОК", "jump", 48, Color(0.3, 0.6, 1.0))
	_btn("sprint", "БЕГ", "sprint", 46, Color(0.3, 0.8, 0.4))
	_btn("enter", "СЕСТЬ", "enter", 50, Color(0.9, 0.7, 0.2))
	_btn("interact", "ДЕЙСТВИЕ", "interact", 52, Color(0.8, 0.5, 1.0))
	_btn("gas", "ГАЗ", "gas", 78, Color(0.3, 0.85, 0.4))
	_btn("brake", "ТОРМОЗ", "brake", 58, Color(0.9, 0.3, 0.3))
	_btn("handbrake", "РУЧНИК", "handbrake", 46, Color(0.9, 0.6, 0.2))


func _place(id: String, center: Vector2) -> void:
	var b: Dictionary = buttons[id]
	var n: TouchScreenButton = b["node"]
	n.position = center - Vector2(b["r"], b["r"])
	b["center"] = center


func _layout() -> void:
	var vp = get_viewport().get_visible_rect().size
	money_lbl.position = Vector2(vp.x - 330, 14)
	stars.position = Vector2(vp.x - 290, 64)
	info_lbl.position = Vector2(vp.x - 330, 112)
	net_lbl.position = Vector2(vp.x - 330, 140)
	mission_lbl.position = Vector2(vp.x / 2 - 350, 16)
	timer_lbl.position = Vector2(vp.x / 2 - 100, 52)
	notify_lbl.position = Vector2(vp.x / 2 - 400, vp.y - 260)
	big_title.position = Vector2(vp.x / 2 - 600, vp.y / 2 - 90)
	big_sub.position = Vector2(vp.x / 2 - 600, vp.y / 2 + 10)
	banner.position = Vector2(vp.x / 2 - 330, 100)
	top_hb.position = Vector2(244, 20)
	chat_box.position = Vector2(vp.x / 2 - 300, 100)
	_place("shoot", Vector2(vp.x - 130, vp.y - 140))
	_place("jump", Vector2(vp.x - 280, vp.y - 90))
	_place("sprint", Vector2(vp.x - 260, vp.y - 220))
	_place("enter", Vector2(vp.x - 110, vp.y - 320))
	_place("interact", Vector2(vp.x - 250, vp.y - 360))
	_place("gas", Vector2(vp.x - 130, vp.y - 150))
	_place("brake", Vector2(vp.x - 300, vp.y - 100))
	_place("handbrake", Vector2(vp.x - 290, vp.y - 250))


func _over_button(p: Vector2) -> bool:
	for id in buttons.keys():
		var b: Dictionary = buttons[id]
		var n: TouchScreenButton = b["node"]
		if n.visible and b.has("center") and p.distance_to(b["center"]) < float(b["r"]) + 6.0:
			return true
	return false


func _modal() -> bool:
	return shop.visible or pause_panel.visible or chat_box.visible


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			if _modal() or _over_button(st.position):
				return
			var vp = get_viewport().get_visible_rect().size
			if st.position.x < vp.x * 0.42 and st.position.y > vp.y * 0.3 and joy_index == -1:
				joy_index = st.index
				joy_center = st.position
				joy_pos = st.position
			elif cam_index == -1:
				cam_index = st.index
		else:
			if st.index == joy_index:
				joy_index = -1
				Game.joy = Vector2.ZERO
			if st.index == cam_index:
				cam_index = -1
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		if sd.index == joy_index:
			joy_pos = sd.position
			var v = (joy_pos - joy_center) / 85.0
			if v.length() > 1.0:
				v = v.normalized()
			Game.joy = v
		elif sd.index == cam_index:
			Game.cam_delta += sd.relative


func _process(delta: float) -> void:
	var pl = Game.player
	var in_car: bool = pl != null and pl.car != null
	var on_foot: bool = pl != null and pl.car == null and not pl.dead
	var vis = {
		"shoot": on_foot, "jump": on_foot, "sprint": on_foot,
		"enter": pl != null and not pl.dead and (in_car or Game.world.nearest_car(pl.global_position, 4.0) != null),
		"interact": on_foot and Game.world.missions.near != "",
		"gas": in_car, "brake": in_car, "handbrake": in_car,
	}
	for id in vis.keys():
		var n: TouchScreenButton = buttons[id]["node"]
		n.visible = vis[id] and not _modal()
	var el: Label = buttons["enter"]["node"].get_child(0)
	el.text = "ВЫЙТИ" if in_car else "СЕСТЬ"
	money_lbl.text = "$%s" % _fmt(Game.money)
	var extra = ""
	if in_car and is_instance_valid(pl.car):
		extra = "%d км/ч   " % int(absf(pl.car.forward_speed()) * 3.6)
	info_lbl.text = "%sПатроны: %d" % [extra, Game.ammo]
	if notify_t > 0.0:
		notify_t -= delta
		notify_lbl.modulate.a = clamp(notify_t, 0.0, 1.0)
	if big_t > 0.0:
		big_t -= delta
		var a: float = clamp(big_t, 0.0, 1.0)
		big_title.modulate.a = a
		big_sub.modulate.a = a
	if banner_t > 0.0:
		banner_t -= delta
		if banner_t <= 0.0:
			banner.visible = false
	if damage_t > 0.0:
		damage_t -= delta
		damage_rect.color.a = clamp(damage_t, 0.0, 0.35)
	minimap.queue_redraw()
	stars.queue_redraw()
	bars.queue_redraw()
	joy_draw.queue_redraw()


func _fmt(n: int) -> String:
	var s = str(n)
	var out = ""
	var c = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = " " + out
	return out


func show_notify(t: String) -> void:
	notify_lbl.text = t
	notify_t = 3.0


func show_big(title: String, sub: String, col: Color) -> void:
	big_title.text = title
	big_title.add_theme_color_override("font_color", col)
	big_sub.text = sub
	big_t = 4.0


func show_banner(title: String, text: String) -> void:
	(banner.get_node("VBox/T") as Label).text = title
	(banner.get_node("VBox/S") as Label).text = text
	banner.visible = true
	banner_t = 6.0


func set_mission(text: String, time_left) -> void:
	mission_lbl.text = text
	if time_left != null and float(time_left) >= 0.0:
		var t = int(float(time_left))
		timer_lbl.text = "%d:%02d" % [t / 60, t % 60]
	else:
		timer_lbl.text = ""


func flash_damage() -> void:
	damage_t = 0.5


# ---------------- Магазины ----------------
func _make_shop() -> void:
	var cc = CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	shop = PanelContainer.new()
	shop.custom_minimum_size = Vector2(620, 0)
	shop.visible = false
	cc.add_child(shop)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	shop.add_child(v)
	shop_title = Label.new()
	shop_title.add_theme_font_size_override("font_size", 34)
	shop_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	v.add_child(shop_title)
	shop_list = VBoxContainer.new()
	shop_list.add_theme_constant_override("separation", 8)
	v.add_child(shop_list)
	var close = Button.new()
	close.text = "Закрыть"
	close.pressed.connect(func(): shop.visible = false)
	v.add_child(close)


func open_shop(k: String) -> void:
	for c in shop_list.get_children():
		c.queue_free()
	match k:
		"ammu":
			shop_title.text = "Оружейный магазин"
			_shop_item("Патроны ×60", 150, func(): Game.ammo += 60)
			_shop_item("Патроны ×200", 400, func(): Game.ammo += 200)
			_shop_item("Бронежилет", 300, func(): Game.armor = 100.0)
		"hospital":
			shop_title.text = "Больница"
			_shop_item("Лечение", 100, func(): Game.player.health = 100.0)
		"cars":
			shop_title.text = "Автосалон"
			_shop_item("Седан «Illinois»", 3000, func(): _buy_car("sedan"))
			_shop_item("Фургон", 4000, func(): _buy_car("van"))
			_shop_item("Внедорожник", 8000, func(): _buy_car("suv"))
			_shop_item("Спорткар", 20000, func(): _buy_car("sport"))
		"garage":
			shop_title.text = "Гараж"
			if Game.owned_cars.is_empty():
				var l = Label.new()
				l.text = "У тебя пока нет машин. Купи их в автосалоне."
				shop_list.add_child(l)
			for i in Game.owned_cars.size():
				var ck: String = str(Game.owned_cars[i])
				_shop_item("Забрать: " + _car_name(ck), 0, func(): Game.world.spawn_owned_car(ck))
	shop.visible = true


func _car_name(k: String) -> String:
	return {"sedan": "Седан", "van": "Фургон", "suv": "Внедорожник", "sport": "Спорткар"}.get(k, k)


func _buy_car(k: String) -> void:
	Game.owned_cars.append(k)
	Game.save_game()
	Game.world.spawn_owned_car(k)


func _shop_item(title: String, price: int, cb: Callable) -> void:
	var b = Button.new()
	b.text = title + ("   —   $%d" % price if price > 0 else "")
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(_on_buy.bind(price, cb))
	shop_list.add_child(b)


func _on_buy(price: int, cb: Callable) -> void:
	if Game.money < price:
		show_notify("Не хватает денег")
		return
	Game.add_money(-price)
	cb.call()
	show_notify("Готово!")
	shop.visible = false


# ---------------- Пауза ----------------
func _make_pause() -> void:
	var cc = CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	pause_panel = PanelContainer.new()
	pause_panel.custom_minimum_size = Vector2(480, 0)
	pause_panel.visible = false
	cc.add_child(pause_panel)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pause_panel.add_child(v)
	var t = Label.new()
	t.text = "Пауза"
	t.add_theme_font_size_override("font_size", 38)
	v.add_child(t)
	var cont = Button.new()
	cont.text = "Продолжить"
	cont.pressed.connect(func(): pause_panel.visible = false)
	v.add_child(cont)
	var sh = Button.new()
	sh.text = "Тени: " + ("вкл" if Game.shadows else "выкл")
	sh.pressed.connect(_toggle_shadows.bind(sh))
	v.add_child(sh)
	var quit = Button.new()
	quit.text = "Выйти в меню"
	quit.pressed.connect(_quit_menu)
	v.add_child(quit)


func _toggle_shadows(sh: Button) -> void:
	Game.shadows = not Game.shadows
	Game.world.sun.shadow_enabled = Game.shadows
	sh.text = "Тени: " + ("вкл" if Game.shadows else "выкл")
	Game.save_game()


func _quit_menu() -> void:
	Game.save_game()
	Net.disconnect_net()
	Game.world = null
	Game.player = null
	get_tree().reload_current_scene()


# ---------------- Рисование ----------------
class JoyDraw extends Control:
	var hud

	func _draw() -> void:
		if hud == null or hud.joy_index == -1:
			var vp = get_viewport_rect().size
			if Game.player and not Game.player.dead:
				draw_circle(Vector2(170, vp.y - 170), 85, Color(1, 1, 1, 0.08))
				draw_arc(Vector2(170, vp.y - 170), 85, 0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
			return
		draw_circle(hud.joy_center, 85, Color(1, 1, 1, 0.1))
		draw_arc(hud.joy_center, 85, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		var k: Vector2 = hud.joy_center + Game.joy * 85.0
		draw_circle(k, 36, Color(1, 1, 1, 0.45))


class Stars extends Control:
	func _draw() -> void:
		var w = Game.wanted
		var blink = w > 0 and Game.world != null and Game.world.not_seen_time > 2.0 and int(Time.get_ticks_msec() / 300) % 2 == 0
		for i in 5:
			var c = Vector2(size.x - 25 - (4 - i) * 52, 25)
			var pts = PackedVector2Array()
			for k in 10:
				var a = -PI / 2 + k * PI / 5
				var r = 22.0 if k % 2 == 0 else 9.5
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			var active = i < w
			if active and not blink:
				draw_colored_polygon(pts, Color(1.0, 0.82, 0.25))
			pts.append(pts[0])
			draw_polyline(pts, Color(0, 0, 0, 0.8) if active else Color(1, 1, 1, 0.35), 2.0)


class Bars extends Control:
	func _draw() -> void:
		var pl = Game.player
		if pl == null:
			return
		draw_rect(Rect2(0, 0, size.x, 9), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(0, 0, size.x * clamp(pl.health / 100.0, 0.0, 1.0), 9), Color(0.3, 0.85, 0.35))
		draw_rect(Rect2(0, 12, size.x, 9), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(0, 12, size.x * clamp(Game.armor / 100.0, 0.0, 1.0), 9), Color(0.35, 0.6, 1.0))


class MiniMap extends Control:
	const S := 0.42

	func _to_map(w: Vector3, ppos: Vector3, fwd: Vector3, rgt: Vector3) -> Vector2:
		var rel = w - ppos
		return size / 2.0 + Vector2(rel.dot(rgt), -rel.dot(fwd)) * S

	func _draw() -> void:
		var world = Game.world
		var pl = Game.player
		if world == null or pl == null:
			return
		var city = world.city
		var cam = world.cam
		var fwd: Vector3 = cam.forward_flat()
		var rgt: Vector3 = cam.right_flat()
		var ppos: Vector3 = pl.global_position
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.15, 0.13, 0.92))
		var n: int = city.N
		for k in n + 1:
			var a: Vector3 = city.node_pos(k, 0)
			var b: Vector3 = city.node_pos(k, n)
			draw_line(_to_map(a, ppos, fwd, rgt), _to_map(b, ppos, fwd, rgt), Color(0.45, 0.47, 0.5), city.R * S)
			var c: Vector3 = city.node_pos(0, k)
			var d: Vector3 = city.node_pos(n, k)
			draw_line(_to_map(c, ppos, fwd, rgt), _to_map(d, ppos, fwd, rgt), Color(0.45, 0.47, 0.5), city.R * S)
		for key in world.missions.markers.keys():
			var info: Array = world.missions.INFO[key]
			var mp: Vector2 = _to_map(world.missions.markers[key], ppos, fwd, rgt)
			mp = mp.clamp(Vector2(6, 6), size - Vector2(6, 6))
			draw_circle(mp, 6, info[1])
			draw_arc(mp, 6, 0, TAU, 12, Color(0, 0, 0), 1.5)
		var blink = int(Time.get_ticks_msec() / 250) % 2 == 0
		for c2 in world.police_cars:
			if is_instance_valid(c2):
				var pp = _to_map(c2.global_position, ppos, fwd, rgt)
				draw_circle(pp, 4, Color(1, 0.2, 0.2) if blink else Color(0.2, 0.4, 1))
		for o in world.officers:
			if is_instance_valid(o):
				draw_circle(_to_map(o.global_position, ppos, fwd, rgt), 3, Color(0.3, 0.5, 1))
		for r in world.remotes.values():
			if is_instance_valid(r):
				var rp = _to_map(r.global_position, ppos, fwd, rgt).clamp(Vector2(5, 5), size - Vector2(5, 5))
				draw_circle(rp, 5, Color(0.3, 0.9, 1.0))
		var tp = world.missions.target_pos()
		if tp != null:
			var mpt = _to_map(tp, ppos, fwd, rgt).clamp(Vector2(8, 8), size - Vector2(8, 8))
			draw_circle(mpt, 8, Color(1.0, 0.85, 0.1))
			draw_arc(mpt, 8, 0, TAU, 16, Color(0, 0, 0), 2.0)
		# стрелка игрока
		var yaw: float = pl.facing
		if pl.car != null and is_instance_valid(pl.car):
			var f: Vector3 = pl.car.global_transform.basis.z
			yaw = atan2(-f.x, -f.z)
		var dir3 = Vector3(-sin(yaw), 0, -cos(yaw))
		var dir = Vector2(dir3.dot(rgt), -dir3.dot(fwd)).normalized()
		var perp = Vector2(-dir.y, dir.x)
		var c0 = size / 2.0
		draw_colored_polygon(PackedVector2Array([c0 + dir * 11, c0 - dir * 7 + perp * 7, c0 - dir * 3, c0 - dir * 7 - perp * 7]), Color(1, 1, 1))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.8), false, 3.0)
