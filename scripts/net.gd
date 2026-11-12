extends Node
## Онлайн через WebSocket (сервер на Render). Автопереподключение.

signal message(data)
signal status_changed(text)

var ws = WebSocketPeer.new()
var connected = false
var my_id = ""
var url = ""
var retry = 0.0


func connect_to(u: String) -> void:
	url = u.strip_edges()
	if url == "":
		return
	ws = WebSocketPeer.new()
	var err = ws.connect_to_url(url)
	if err != OK:
		status_changed.emit("Онлайн: ошибка адреса сервера")
	else:
		status_changed.emit("Онлайн: подключение (сервер может просыпаться ~40 с)...")


func disconnect_net() -> void:
	if connected:
		ws.close()
	connected = false
	url = ""
	my_id = ""


func _process(delta: float) -> void:
	if url == "":
		return
	ws.poll()
	var st = ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			retry = 0.0
			status_changed.emit("Онлайн: подключено")
			send({"t": "hello", "name": Game.player_name})
		while ws.get_available_packet_count() > 0:
			var txt = ws.get_packet().get_string_from_utf8()
			var d = JSON.parse_string(txt)
			if typeof(d) == TYPE_DICTIONARY:
				if str(d.get("t", "")) == "welcome":
					my_id = str(d.get("id", ""))
				message.emit(d)
	elif st == WebSocketPeer.STATE_CLOSED:
		if connected:
			status_changed.emit("Онлайн: связь потеряна, переподключение...")
		connected = false
		retry -= delta
		if retry <= 0.0:
			retry = 6.0
			connect_to(url)


func send(d: Dictionary) -> void:
	if connected:
		ws.send_text(JSON.stringify(d))
