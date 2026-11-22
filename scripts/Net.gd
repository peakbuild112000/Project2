extends Node
## WebSocket transport. The host runs a real TCP/WebSocket server on its PC;
## desktop and Web clients connect as regular WebSocket clients.
## Messages are compact JSON dictionaries. Autoloaded as `Net`.

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal message_received(id: int, msg: Dictionary)
signal status_changed(text: String)
signal connection_failed(reason: String)
signal ready_connected(id: int)

var mode: String = "none" # none | server | client | offline
var local_id: int = 1
var password: String = ""
var server_url: String = ""
var port: int = 9080
var connected_ok: bool = false

var _tcp: TCPServer
var _clients: Dictionary = {}
var _socket: WebSocketPeer
var _next_id: int = 2
var _hello_sent: bool = false
var _ever_open: bool = false
var _json := JSON.new()


func _process(_delta: float) -> void:
	if mode == "server":
		_poll_server()
	elif mode == "client":
		_poll_client()


func start_server(p_port: int, p_password: String) -> bool:
	stop()
	_tcp = TCPServer.new()
	var err := _tcp.listen(p_port, "0.0.0.0")
	if err != OK:
		status_changed.emit("SERVER ERROR: cannot listen on port %d (code %d)" % [p_port, err])
		_tcp = null
		return false
	mode = "server"
	port = p_port
	password = p_password
	local_id = 1
	connected_ok = true
	next_id_reset()
	status_changed.emit("SERVER ONLINE - port %d" % p_port)
	return true


func next_id_reset() -> void:
	_next_id = 2


func start_client(url: String, p_password: String) -> bool:
	stop()
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		status_changed.emit("CLIENT ERROR: URL must start with ws:// or wss://")
		return false
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(url)
	if err != OK:
		status_changed.emit("CLIENT ERROR: connect failed (code %d)" % err)
		_socket = null
		return false
	mode = "client"
	server_url = url
	password = p_password
	local_id = 0
	connected_ok = false
	_hello_sent = false
	_ever_open = false
	status_changed.emit("CONNECTING TO " + url)
	return true


func start_offline() -> void:
	stop()
	mode = "offline"
	local_id = 1
	connected_ok = true
	status_changed.emit("OFFLINE PRACTICE MODE")


func stop() -> void:
	if _socket != null:
		_socket.close(1000, "bye")
		_socket = null
	for id in _clients.keys():
		var ws: WebSocketPeer = _clients[id]
		ws.close(1000, "server stopped")
	_clients.clear()
	if _tcp != null:
		_tcp.stop()
		_tcp = null
	mode = "none"
	connected_ok = false
	_hello_sent = false
	_ever_open = false


func _poll_server() -> void:
	if _tcp == null:
		return
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		if stream == null:
			continue
		var ws := WebSocketPeer.new()
		ws.heartbeat_interval = 20.0
		if ws.accept_stream(stream) != OK:
			continue
		var id: int = _next_id
		_next_id += 1
		_clients[id] = ws
		status_changed.emit("Peer %d handshaking..." % id)

	var to_remove: Array[int] = []
	for id in _clients.keys():
		var ws: WebSocketPeer = _clients[id]
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_read_socket(ws, id)
		elif state == WebSocketPeer.STATE_CLOSED:
			to_remove.append(id)
	for id in to_remove:
		_clients.erase(id)
		peer_disconnected.emit(id)


func _poll_client() -> void:
	if _socket == null:
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _ever_open:
			_ever_open = true
			connected_ok = true
			peer_connected.emit(1)
			status_changed.emit("CONNECTED - authenticating")
		_read_socket(_socket, 1)
		if not _hello_sent and connected_ok:
			_hello_sent = true
			send({"t": "hello", "name": GameState.player_name, "password": password})
	elif state == WebSocketPeer.STATE_CLOSED:
		if not _ever_open:
			connection_failed.emit(_socket.get_close_reason())
		elif connected_ok:
			connected_ok = false
			peer_disconnected.emit(1)
			status_changed.emit("DISCONNECTED FROM SERVER")
		_socket = null
		mode = "none"


func _read_socket(ws: WebSocketPeer, sender: int) -> void:
	while ws.get_available_packet_count() > 0:
		var raw: String = ws.get_packet().get_string_from_utf8()
		if _json.parse(raw) != OK or not (_json.data is Dictionary):
			continue
		message_received.emit(sender, _json.data)


func send_to(id: int, msg: Dictionary) -> void:
	if mode != "server" or not _clients.has(id):
		return
	var ws: WebSocketPeer = _clients[id]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


func broadcast(msg: Dictionary) -> void:
	for id in _clients.keys():
		send_to(id, msg)


func send(msg: Dictionary) -> void:
	if mode == "client" and _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(msg))


func kick(id: int, reason: String) -> void:
	send_to(id, {"t": "kicked", "reason": reason})
	if _clients.has(id):
		var ws: WebSocketPeer = _clients[id]
		ws.close(1008, reason)


func default_client_url() -> String:
	if OS.has_feature("web"):
		var query: String = str(JavaScriptBridge.eval(
			"new URLSearchParams(location.search).get('server') || ''"))
		if not query.is_empty():
			return query
		var host: String = str(JavaScriptBridge.eval("location.hostname || 'localhost'"))
		var scheme: String = str(JavaScriptBridge.eval("location.protocol === 'https:' ? 'wss' : 'ws'"))
		return "%s://%s:9080" % [scheme, host]
	return "ws://127.0.0.1:9080"


func query_param(name: String) -> String:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return ""
	return str(JavaScriptBridge.eval(
		"new URLSearchParams(location.search).get('%s') || ''" % name))
