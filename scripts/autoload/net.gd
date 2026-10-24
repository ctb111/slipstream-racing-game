extends Node
## Autoload "Net": old-school LAN play. The host opens an ENet server and
## shouts a UDP beacon on the local network every second; clients listen for
## beacons to list games, then connect. The host owns the lobby and starts races.

const PORT := 27015
const DISCOVERY_PORT := 27016
const PROTOCOL := "slipstream-1"
const MAX_PLAYERS := 8

signal servers_changed
signal lobby_changed
signal disconnected(reason: String)

## peer id -> {name}
var players := {}
## Race settings chosen by the host.
var lobby := {track = "kiefernring", laps = 3, bots = 3, difficulty = 1}
## "ip" -> {name, track, players, max, state, seen}
var servers := {}
var in_race := false

var _beacon: PacketPeerUDP
var _beacon_t := 0.0
var _listener: PacketPeerUDP
var _join_order: Array[int] = []


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Could not connect to the host."))
	multiplayer.server_disconnected.connect(func(): _fail("The host closed the game."))


func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server() and Game.mode == Game.Mode.HOST


# ---------------------------------------------------------------- hosting

func host() -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	Game.mode = Game.Mode.HOST
	lobby = {track = Game.track_id, laps = Game.laps, bots = Game.bots, difficulty = Game.difficulty}
	players = {1: {name = Game.player_name, paint = Game.paint_index, car = Game.car_id}}
	_join_order = [1]
	in_race = false
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	lobby_changed.emit()
	return OK


func set_lobby(settings: Dictionary) -> void:
	if not is_host():
		return
	lobby.merge(settings, true)
	_sync_lobby.rpc(players, lobby)


## Host only: grid = connected players in join order, then bots.
func start_race() -> void:
	if not is_host():
		return
	var grid := []
	var names := Game.BOT_NAMES.duplicate()
	names.shuffle()
	var slots := mini(int(lobby.bots) + players.size(), MAX_PLAYERS)
	for i in slots - players.size():
		grid.append({peer = 1, name = names[i], bot = true})
	for id in _join_order:
		if players.has(id):
			grid.append({peer = id, name = players[id].name, bot = false, paint = players[id].get("paint", -1),
				car = players[id].get("car", CarCatalog.DEFAULT)})
	in_race = true
	# Changeable weather: the host rolls the scenario and sends the whole
	# timeline, so every player's sky, rain and grip follow the same script.
	lobby.erase("weather_timeline")
	if Weather.cond_changeable(int(lobby.get("weather", -1))):
		lobby.weather_timeline = WeatherCycle.roll()
	_begin_race.rpc(grid, lobby)


# ---------------------------------------------------------------- joining

func join(ip: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	Game.mode = Game.Mode.CLIENT
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_beacon = null
	players = {}
	in_race = false
	Game.mode = Game.Mode.SINGLE


func start_scan() -> void:
	stop_scan()
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("LAN scan: could not listen on port %d (%s)" % [DISCOVERY_PORT, error_string(err)])
	servers.clear()
	servers_changed.emit()


func stop_scan() -> void:
	if _listener:
		_listener.close()
	_listener = null


func _process(dt: float) -> void:
	if _beacon and is_host():
		_beacon_t -= dt
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var info := {proto = PROTOCOL, name = Game.player_name, track = lobby.track,
				players = players.size(), max = MAX_PLAYERS, state = "racing" if in_race else "lobby"}
			_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var data := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var info = JSON.parse_string(data)
			if info is Dictionary and info.get("proto") == PROTOCOL:
				info.seen = Time.get_ticks_msec()
				servers[ip] = info
				changed = true
		var now := Time.get_ticks_msec()
		for ip in servers.keys():
			if now - servers[ip].seen > 3500:
				servers.erase(ip)
				changed = true
		if changed:
			servers_changed.emit()


# ---------------------------------------------------------------- lobby RPCs

func _on_connected() -> void:
	_register.rpc_id(1, Game.player_name, PROTOCOL, Game.paint_index, Game.car_id)


func _on_peer_connected(_id: int) -> void:
	pass # wait for _register


func _on_peer_disconnected(id: int) -> void:
	if is_host():
		players.erase(id)
		_join_order.erase(id)
		_sync_lobby.rpc(players, lobby)
	lobby_changed.emit()


@rpc("any_peer", "reliable")
func _register(player_name: String, proto: String, paint := 0, car := "") -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if proto != PROTOCOL or players.size() >= MAX_PLAYERS or in_race:
		_rejected.rpc_id(id, "Version mismatch." if proto != PROTOCOL else "Game full or already racing.")
		return
	var clean := player_name.strip_edges().substr(0, 16)
	players[id] = {name = clean if clean != "" else "Driver %d" % players.size(), paint = paint,
		car = car if CarCatalog.has(car) else CarCatalog.DEFAULT}
	_join_order.append(id)
	_sync_lobby.rpc(players, lobby)


## Tell the host our paint / car changed while waiting in the lobby.
func update_paint(index: int) -> void:
	_update_choice(index, Game.car_id)


func update_car(car: String) -> void:
	_update_choice(Game.paint_index, car)


func _update_choice(paint: int, car: String) -> void:
	if not multiplayer.has_multiplayer_peer() or Game.mode == Game.Mode.SINGLE:
		return
	if is_host():
		if players.has(1):
			players[1].paint = paint
			players[1].car = car
			_sync_lobby.rpc(players, lobby)
	else:
		_set_choice.rpc_id(1, paint, car)


@rpc("any_peer", "reliable")
func _set_choice(paint: int, car: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host() and players.has(id):
		players[id].paint = paint
		players[id].car = car if CarCatalog.has(car) else CarCatalog.DEFAULT
		_sync_lobby.rpc(players, lobby)


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	_fail(reason)


@rpc("authority", "reliable", "call_local")
func _sync_lobby(p: Dictionary, l: Dictionary) -> void:
	players = p
	lobby = l
	lobby_changed.emit()


@rpc("authority", "reliable", "call_local")
func _begin_race(grid: Array, l: Dictionary) -> void:
	lobby = l
	Game.grid = grid
	Game.track_id = l.track
	Game.laps = l.laps
	Game.difficulty = l.difficulty
	Game.weather_override = l.get("weather", -1)
	Game.weather_timeline = l.get("weather_timeline", {})
	in_race = true
	get_tree().change_scene_to_file("res://scenes/race.tscn")


## Host: race over, everyone back to the lobby.
func back_to_lobby() -> void:
	if is_host():
		in_race = false
		_to_lobby.rpc()


@rpc("authority", "reliable", "call_local")
func _to_lobby() -> void:
	in_race = false
	Game.grid = []
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _fail(reason: String) -> void:
	var was_online := Game.mode != Game.Mode.SINGLE
	leave()
	disconnected.emit(reason)
	if was_online and get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://scenes/menu.tscn":
		Game.pending_message = reason
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
