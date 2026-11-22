extends Node
## WebSocket transport using TCPServer + WebSocketPeer (Godot 4.7 API).
## The host is authoritative; clients only send intent and receive snapshots.

signal message_received(from_id: int, msg: Dictionary)
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_state(ok: bool, detail: String)

var is_host := false
var peer_id := 1

var _tcp: TCPServer = null
var _clients: Dictionary = {} # id -> WebSocketPeer
var _socket: WebSocketPeer = null
var _next_id := 2
var _json := JSON.new()
var _client_open := false
var _client_ever_open := false

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	if is_host:
		_poll_server()
	elif _socket != null:
		_poll_client()

func start_server(port: int) -> bool:
	stop()
	_tcp = TCPServer.new()
	var err: int = _tcp.listen(port, "0.0.0.0")
	if err != OK:
		connection_state.emit(false, "Listen failed: %d" % err)
		_tcp = null
		return false
	is_host = true
	_clients.clear()
	_next_id = 2
	connection_state.emit(true, "Hosting on port %d" % port)
	return true

func start_client(url: String) -> void:
	stop()
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		connection_state.emit(false, "URL must start with ws:// or wss://")
		return
	_socket = WebSocketPeer.new()
	var err: int = _socket.connect_to_url(url)
	if err != OK:
		connection_state.emit(false, "Connect failed: %d" % err)
		_socket = null
		return
	is_host = false
	peer_id = 1
	_client_open = false
	_client_ever_open = false
	connection_state.emit(true, "Connecting to %s" % url)

func broadcast(msg: Dictionary) -> void:
	for id in _clients.keys():
		send_to(int(id), msg)

func send_to(id: int, msg: Dictionary) -> void:
	if not _clients.has(id):
		return
	var ws: WebSocketPeer = _clients[id]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))

func send_to_host(msg: Dictionary) -> void:
	if _client_open and _socket != null:
		_socket.send_text(JSON.stringify(msg))

func client_open() -> bool:
	return _client_open

func stop() -> void:
	if _socket != null:
		_socket.close(1000, "bye")
		_socket = null
	for id in _clients.keys():
		var ws: WebSocketPeer = _clients[id]
		ws.close(1000, "bye")
	_clients.clear()
	if _tcp != null:
		_tcp.stop()
		_tcp = null
	is_host = false
	_client_open = false
	_client_ever_open = false

func _poll_server() -> void:
	if _tcp == null:
		return
	while _tcp.is_connection_available():
		var stream = _tcp.take_connection()
		if stream == null:
			continue
		var ws := WebSocketPeer.new()
		if ws.accept_stream(stream) != OK:
			continue
		var id: int = _next_id
		_next_id += 1
		_clients[id] = ws
		peer_connected.emit(id)
	var to_remove: Array = []
	for id in _clients.keys():
		var peer: WebSocketPeer = _clients[id]
		peer.poll()
		var state: int = peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_read_socket(peer, int(id))
		elif state == WebSocketPeer.STATE_CLOSED:
			to_remove.append(id)
	for id in to_remove:
		_clients.erase(id)
		peer_disconnected.emit(int(id))

func _poll_client() -> void:
	_socket.poll()
	var state: int = _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _client_ever_open:
			_client_ever_open = true
			_client_open = true
			connection_state.emit(true, "Connected")
		_read_socket(_socket, 1)
	elif state == WebSocketPeer.STATE_CLOSED:
		if not _client_ever_open:
			connection_state.emit(false, _socket.get_close_reason())
		else:
			connection_state.emit(false, "Disconnected")
		_socket = null
		_client_open = false
		is_host = false

func _read_socket(ws: WebSocketPeer, sender: int) -> void:
	while ws.get_available_packet_count() > 0:
		var raw: String = ws.get_packet().get_string_from_utf8()
		if _json.parse(raw) != OK or not (_json.data is Dictionary):
			continue
		message_received.emit(sender, _json.data)
