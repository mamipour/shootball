extends Node

# Nakama connection singleton — manages auth, matchmaking, and match communication.

signal authenticated
signal matchmaker_found(match_id: String, opponent_name: String, my_side: String)
signal match_started(round_num: int, aim_time: float)
signal shots_received(player1_shot: Dictionary, player2_shot: Dictionary)
signal goal_scored(scorer_id: String, scores: Dictionary)
signal game_over(winner_id: String, reason: String, scores: Dictionary)
signal opponent_left
signal timer_sync(remaining: float)
signal opponent_info_received(opp_name: String, opp_avatar: int)
signal connection_error(msg: String)

const SERVER_HOST := "shootball.avardgah.com"
const SERVER_PORT := 7350
const SERVER_KEY := "defaultkey"
const USE_SSL := false

var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket

var user_id: String = ""
var display_name: String = ""
var match_id: String = ""
var my_side: String = ""   # "player1" or "player2"
var opponent_user_id: String = ""

var _matchmaker_ticket: String = ""

# Op codes (must match server)
const OP_SHOT_SUBMIT := 1
const OP_ROUND_START := 2
const OP_SHOTS_EXECUTE := 3
const OP_GOAL_SCORED := 4
const OP_GAME_OVER := 5
const OP_PLAYER_READY := 6
const OP_OPPONENT_INFO := 7
const OP_PLAYER_LEFT := 8
const OP_TIMER_SYNC := 9
const OP_ROUND_RESULT := 10

func _ready():
	client = Nakama.create_client(SERVER_KEY, SERVER_HOST, SERVER_PORT, "http")

# ── Auth ──

func login_device() -> bool:
	var device_id := _get_device_id()
	session = await client.authenticate_device_async(device_id, null, true)
	if session.is_exception():
		push_error("Auth failed: %s" % session)
		connection_error.emit("Authentication failed")
		return false
	user_id = session.user_id
	display_name = session.username

	# First login: ask server for a guaranteed unique name
	var account = await client.get_account_async(session)
	if not account.is_exception():
		var dn: String = account.user.display_name
		if dn == "" or dn == null:
			var rpc_result = await client.rpc_async(session, "generate_unique_name", "")
			if not rpc_result.is_exception():
				var json := JSON.new()
				if json.parse(rpc_result.payload) == OK:
					display_name = json.data.get("name", display_name)
		else:
			display_name = dn

	print("[Online] Logged in as %s (%s)" % [display_name, user_id])
	authenticated.emit()
	return true

func update_display_name(new_name: String) -> void:
	await client.update_account_async(session, null, new_name)
	display_name = new_name

# ── Socket ──

func connect_socket() -> bool:
	if socket and socket.is_connected_to_host():
		return true
	socket = Nakama.create_socket_from(client)
	var result = await socket.connect_async(session)
	if result.is_exception():
		push_error("Socket connect failed: %s" % result)
		connection_error.emit("Connection failed")
		return false
	socket.received_match_state.connect(_on_match_state)
	socket.received_matchmaker_matched.connect(_on_matchmaker_matched)
	socket.closed.connect(_on_socket_closed)
	print("[Online] Socket connected")
	return true

func disconnect_socket():
	if socket:
		socket.close()
		socket = null

# ── Matchmaking ──

func find_match() -> void:
	if not socket or not socket.is_connected_to_host():
		var ok := await connect_socket()
		if not ok:
			return
	var result = await socket.add_matchmaker_async("*", 2, 2)
	if result.is_exception():
		push_error("Matchmaker failed: %s" % result)
		connection_error.emit("Matchmaking failed")
		return
	_matchmaker_ticket = result.ticket
	print("[Online] Matchmaker ticket: %s" % _matchmaker_ticket)

func cancel_matchmaking() -> void:
	if _matchmaker_ticket != "" and socket:
		await socket.remove_matchmaker_async(_matchmaker_ticket)
		_matchmaker_ticket = ""

func _on_matchmaker_matched(p_matched: NakamaRTAPI.MatchmakerMatched):
	_matchmaker_ticket = ""
	var joined = await socket.join_matched_async(p_matched)
	if joined.is_exception():
		push_error("Match join failed: %s" % joined)
		connection_error.emit("Failed to join match")
		return
	match_id = joined.match_id

	# Determine opponent from presences (side will be assigned by server via OP_OPPONENT_INFO)
	my_side = ""
	var presences = joined.presences
	for pres in presences:
		if pres.user_id != user_id:
			opponent_user_id = pres.user_id
			break

	print("[Online] Joined match %s" % match_id)
	matchmaker_found.emit(match_id, "", "")

# ── Match Communication ──

func submit_shot(pill_idx: int, dir: Vector2, power: float) -> void:
	if not socket or match_id == "":
		return
	var data := JSON.stringify({
		"pill_idx": pill_idx,
		"dir_x": dir.x,
		"dir_y": dir.y,
		"power": power,
	})
	socket.send_match_state_async(match_id, OP_SHOT_SUBMIT, data)

func send_ready() -> void:
	if not socket or match_id == "":
		return
	socket.send_match_state_async(match_id, OP_PLAYER_READY, "{}")

func report_round_result(scorer_id: String) -> void:
	if not socket or match_id == "":
		return
	var data := JSON.stringify({
		"type": "round_result",
		"scorer": scorer_id,
	})
	socket.send_match_state_async(match_id, OP_ROUND_RESULT, data)

func leave_match() -> void:
	if socket and match_id != "":
		await socket.leave_match_async(match_id)
	match_id = ""
	my_side = ""
	opponent_user_id = ""

# ── Friends ──

func add_friend(username: String) -> bool:
	var result = await client.add_friends_async(session, [], [username])
	if result.is_exception():
		return false
	return true

func list_friends() -> Array:
	var result = await client.list_friends_async(session, 0, 100, "")
	if result.is_exception():
		return []
	var friends := []
	for f in result.friends:
		friends.append({
			"user_id": f.user.id,
			"username": f.user.username,
			"display_name": f.user.display_name,
			"online": f.user.online,
			"state": f.state,  # 0=friend, 1=invite_sent, 2=invite_received, 3=blocked
		})
	return friends

# ── Signal Handlers ──

func _on_match_state(p_state: NakamaRTAPI.MatchData):
	var data_str := p_state.data
	var json := JSON.new()
	if json.parse(data_str) != OK:
		return
	var data: Dictionary = json.data

	match p_state.op_code:
		OP_ROUND_START:
			match_started.emit(
				data.get("round", 0),
				data.get("aim_time", 8.0),
			)
		OP_SHOTS_EXECUTE:
			var p1 := data.get("player1", {}) as Dictionary
			var p2 := data.get("player2", {}) as Dictionary
			shots_received.emit(p1, p2)
		OP_GOAL_SCORED:
			goal_scored.emit(
				data.get("scorer", ""),
				data.get("scores", {}),
			)
		OP_GAME_OVER:
			game_over.emit(
				data.get("winner", ""),
				data.get("reason", ""),
				data.get("scores", {}),
			)
		OP_OPPONENT_INFO:
			var assigned_side: String = data.get("your_side", "")
			if assigned_side != "":
				my_side = assigned_side
				print("[Online] Assigned side: %s" % my_side)
			opponent_info_received.emit(
				data.get("name", "Opponent"),
				data.get("avatar_idx", 0),
			)
		OP_PLAYER_LEFT:
			opponent_left.emit()
		OP_TIMER_SYNC:
			timer_sync.emit(data.get("remaining", 0.0))

func _on_socket_closed():
	print("[Online] Socket closed")

# ── Helpers ──

func _get_device_id() -> String:
	var cfg := ConfigFile.new()
	var path := "user://device_id.cfg"
	if cfg.load(path) == OK:
		return cfg.get_value("auth", "device_id", "")
	var id := _generate_uuid()
	cfg.set_value("auth", "device_id", id)
	cfg.save(path)
	return id

func _generate_uuid() -> String:
	var chars := "abcdef0123456789"
	var uuid := ""
	for i in range(32):
		uuid += chars[randi() % chars.length()]
		if i == 7 or i == 11 or i == 15 or i == 19:
			uuid += "-"
	return uuid
