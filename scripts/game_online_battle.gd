extends Node2D

# Online multiplayer Battle Arena mode.
# Multi-shot aiming, central pit with gravity, elimination-based win condition.

enum Phase { WAITING, AIMING, EXECUTING, SETTLING, ELIMINATION, GAME_OVER }

# ── Nodes ──
var my_pills: Array = []
var opp_pills: Array = []

# ── HUD ──
var hud_layer: CanvasLayer
var status_label: Label
var timer_bar: ProgressBar
var timer_bar_style: StyleBoxFlat
var center_msg: Label
var quit_btn: Button
var quit_confirm: Panel
var my_avatar_rect: TextureRect
var opp_avatar_rect: TextureRect
var my_name_label: Label
var opp_name_label: Label

# ── State ──
var phase: Phase = Phase.WAITING
var round_num: int = 0
var i_am_player1: bool = true

# ── Multi-shot aiming ──
var selected_pill: Pill = null
var shot_map: Dictionary = {}
var dragging: bool = false
var drag_start := Vector2.ZERO
var drag_cur := Vector2.ZERO
var aim_dir := Vector2.ZERO
var aim_pow: float = 0.0
var shots_submitted: bool = false

# ── Timer ──
var aim_timer: float = 0.0

# ── Settling ──
var settle_timer: float = 0.0

# ── Elimination display ──
var elim_timer: float = 0.0

# ── Pit ──
var pit_center := Vector2.ZERO
var pit_area: Area2D

# ── Assets ──
var arena_texture: Texture2D = null

# ── Audio ──
var battle_music: AudioStreamPlayer
var elim_sfx: AudioStreamPlayer
var win_sfx: AudioStreamPlayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

	if Online.my_side != "":
		i_am_player1 = (Online.my_side == "player1")
	else:
		i_am_player1 = true

	arena_texture = load("res://assets/arena_dust_floor.svg")
	var ar: Rect2 = Constants.BATTLE_ARENA_RECT
	pit_center = ar.position + ar.size / 2.0

	_setup_audio()
	_build_arena_walls()
	_build_pit()
	_build_pills()
	_build_hud()
	_assign_avatars()

	Online.match_started.connect(_on_match_started)
	Online.multi_shots_received.connect(_on_multi_shots_received)
	Online.elimination_received.connect(_on_elimination_received)
	Online.game_over.connect(_on_game_over)
	Online.opponent_left.connect(_on_opponent_left)
	Online.timer_sync.connect(_on_timer_sync)
	Online.opponent_info_received.connect(_on_opponent_info)

	Online.send_ready()

func _setup_audio():
	battle_music = AudioStreamPlayer.new()
	battle_music.stream = load("res://assets/sounds/stadium.mp3")
	battle_music.volume_db = -8.0
	battle_music.finished.connect(func(): if battle_music.playing == false and phase != Phase.GAME_OVER: battle_music.play())
	add_child(battle_music)
	battle_music.play()

	elim_sfx = AudioStreamPlayer.new()
	elim_sfx.stream = load("res://assets/sounds/goal.mp3")
	elim_sfx.volume_db = 0.0
	add_child(elim_sfx)

	win_sfx = AudioStreamPlayer.new()
	win_sfx.stream = load("res://assets/sounds/win.mp3")
	win_sfx.volume_db = 0.0
	add_child(win_sfx)

func _load_avatar(idx: int) -> Texture2D:
	if idx < 0 or idx >= Constants.AVATAR_COUNT:
		return null
	return load(Constants.AVATAR_DIR + "avatar_%02d.png" % idx)

func _assign_avatars():
	var my_tex := _load_avatar(Constants.player_avatar_idx)
	var opp_tex := _load_avatar(Constants.ai_avatar_idx)
	for pill in my_pills:
		pill.avatar_texture = my_tex
	for pill in opp_pills:
		pill.avatar_texture = opp_tex
	if my_avatar_rect:
		my_avatar_rect.texture = my_tex

# ── Server signal handlers ──

func _on_opponent_info(_opp_name: String, opp_avatar: int):
	if Online.my_side != "":
		var new_p1: bool = (Online.my_side == "player1")
		if new_p1 != i_am_player1:
			i_am_player1 = new_p1
			_rebuild_pills()

	var opp_idx: int = opp_avatar
	if opp_idx == Constants.player_avatar_idx:
		opp_idx = randi() % Constants.AVATAR_COUNT
		while opp_idx == Constants.player_avatar_idx:
			opp_idx = randi() % Constants.AVATAR_COUNT
	var opp_tex := _load_avatar(opp_idx)
	for pill in opp_pills:
		pill.avatar_texture = opp_tex
	if opp_avatar_rect:
		opp_avatar_rect.texture = opp_tex

func _rebuild_pills():
	for p in my_pills:
		p.queue_free()
	for p in opp_pills:
		p.queue_free()
	my_pills.clear()
	opp_pills.clear()
	_build_pills()
	_assign_avatars()

func _on_match_started(p_round: int, p_aim_time: float, positions: Dictionary = {}):
	if positions is Dictionary and positions.size() > 0:
		_apply_synced_positions(positions)
	round_num = p_round
	aim_timer = p_aim_time
	phase = Phase.AIMING
	dragging = false
	shots_submitted = false
	aim_pow = 0.0
	aim_dir = Vector2.ZERO
	settle_timer = 0.0
	center_msg.visible = false
	selected_pill = null
	shot_map.clear()
	for p in my_pills:
		if p.visible:
			p.is_selected = false
	if round_num == 1:
		selected_pill = my_pills[2]
		my_pills[2].is_selected = true

func _on_multi_shots_received(p1_shots: Array, p2_shots: Array):
	phase = Phase.EXECUTING
	settle_timer = 0.0

	var my_shots: Array
	var opp_shots: Array
	if i_am_player1:
		my_shots = p1_shots
		opp_shots = p2_shots
	else:
		my_shots = p2_shots
		opp_shots = p1_shots

	for s in my_shots:
		var idx: int = int(s.get("pill_idx", 0))
		var dir := Vector2(float(s.get("dir_x", 0)), float(s.get("dir_y", 0)))
		var power: float = float(s.get("power", 0))
		if idx >= 0 and idx < 3 and power > 0 and idx < my_pills.size() and my_pills[idx].visible:
			my_pills[idx].kick(dir.normalized() * power)

	for s in opp_shots:
		var idx: int = int(s.get("pill_idx", 0))
		var dir := Vector2(float(s.get("dir_x", 0)), float(s.get("dir_y", 0)))
		var power: float = float(s.get("power", 0))
		if idx >= 0 and idx < 3 and power > 0 and idx < opp_pills.size() and opp_pills[idx].visible:
			opp_pills[idx].kick(dir.normalized() * power)

	for p in my_pills:
		p.is_selected = false
	selected_pill = null

func _on_elimination_received(eliminations: Array):
	elim_sfx.play()
	phase = Phase.ELIMINATION
	elim_timer = 1.5
	var alive_my := _alive_pills(my_pills).size()
	var alive_opp := _alive_pills(opp_pills).size()
	center_msg.text = "Units — You: %d   Opp: %d" % [alive_my, alive_opp]
	center_msg.visible = true

func _on_game_over(winner_id: String, reason: String, _scores: Dictionary):
	phase = Phase.GAME_OVER
	var i_won := (winner_id == Online.user_id)
	if reason == "opponent_left":
		center_msg.text = "YOU WIN!\nOpponent left"
	else:
		center_msg.text = "YOU WIN!" if i_won else "YOU LOSE!"
	center_msg.visible = true
	battle_music.stop()
	win_sfx.play()

func _on_opponent_left():
	if phase != Phase.GAME_OVER:
		phase = Phase.GAME_OVER
		center_msg.text = "Opponent left"
		center_msg.visible = true

func _on_timer_sync(remaining: float):
	if phase == Phase.AIMING:
		aim_timer = remaining

# ── Process ──

func _process(delta: float):
	if get_tree().paused:
		return
	match phase:
		Phase.AIMING:
			aim_timer -= delta
			if aim_timer <= 0.0 and not shots_submitted:
				aim_timer = 0.0
				_submit_all_shots()
		Phase.EXECUTING:
			_apply_pit_gravity(delta)
			settle_timer += delta
			if settle_timer > 0.5:
				phase = Phase.SETTLING
				settle_timer = 0.0
		Phase.SETTLING:
			_apply_pit_gravity(delta)
			if _all_stopped():
				settle_timer += delta
				if settle_timer >= Constants.SETTLE_GRACE_TIME:
					_report_round_result()
			else:
				settle_timer = 0.0
		Phase.ELIMINATION:
			elim_timer -= delta
			if elim_timer <= 0.0:
				Online.send_ready()
				phase = Phase.WAITING
		Phase.GAME_OVER:
			pass

	_update_hud()
	queue_redraw()

func _submit_all_shots():
	if shots_submitted:
		return
	shots_submitted = true
	var shots_arr: Array = []
	for pill in shot_map:
		var shot: Dictionary = shot_map[pill]
		var idx: int = pill.pill_index
		shots_arr.append({"pill_idx": idx, "dir": shot.dir, "power": shot.power})
	Online.submit_multi_shot(shots_arr)

func _report_round_result():
	if not i_am_player1:
		phase = Phase.WAITING
		return
	var eliminations: Array = []
	var my_id := Online.user_id
	var opp_id := Online.opponent_user_id

	for i in range(my_pills.size()):
		var pill: Pill = my_pills[i]
		if not pill.visible:
			continue
		if pill.position.distance_to(pit_center) < Constants.PIT_RADIUS * 0.6:
			_eliminate_pill(pill)
			var uid: String = my_id if i_am_player1 else opp_id
			eliminations.append({"user_id": uid, "pill_idx": i})

	for i in range(opp_pills.size()):
		var pill: Pill = opp_pills[i]
		if not pill.visible:
			continue
		if pill.position.distance_to(pit_center) < Constants.PIT_RADIUS * 0.6:
			_eliminate_pill(pill)
			var uid: String = opp_id if i_am_player1 else my_id
			eliminations.append({"user_id": uid, "pill_idx": i})

	Online.report_elimination_result(eliminations, _collect_positions())

	if eliminations.size() > 0:
		elim_sfx.play()
		phase = Phase.ELIMINATION
		elim_timer = 1.5
		var alive_my := _alive_pills(my_pills).size()
		var alive_opp := _alive_pills(opp_pills).size()
		center_msg.text = "Units — You: %d   Opp: %d" % [alive_my, alive_opp]
		center_msg.visible = true
	else:
		phase = Phase.WAITING

func _collect_positions() -> Dictionary:
	var origin := Constants.FIELD_RECT.position
	var p1 := []
	var p2 := []
	for p in my_pills:
		var rel := p.position - origin
		p1.append([rel.x, rel.y, p.visible])
	for p in opp_pills:
		var rel := p.position - origin
		p2.append([rel.x, rel.y, p.visible])
	return {"p1": p1, "p2": p2}

func _apply_synced_positions(positions: Dictionary) -> void:
	var origin := Constants.FIELD_RECT.position
	var p1_data: Array = positions.get("p1", [])
	var p2_data: Array = positions.get("p2", [])
	var my_data: Array = p1_data if i_am_player1 else p2_data
	var opp_data: Array = p2_data if i_am_player1 else p1_data
	for i in range(mini(my_data.size(), my_pills.size())):
		var d: Array = my_data[i]
		var target := origin + Vector2(float(d[0]), float(d[1]))
		my_pills[i].position = target
		my_pills[i].linear_velocity = Vector2.ZERO
		if d.size() > 2:
			my_pills[i].visible = bool(d[2])
			my_pills[i].freeze = not bool(d[2])
	for i in range(mini(opp_data.size(), opp_pills.size())):
		var d: Array = opp_data[i]
		var target := origin + Vector2(float(d[0]), float(d[1]))
		opp_pills[i].position = target
		opp_pills[i].linear_velocity = Vector2.ZERO
		if d.size() > 2:
			opp_pills[i].visible = bool(d[2])
			opp_pills[i].freeze = not bool(d[2])

# ── Pit mechanics ──

func _apply_pit_gravity(delta: float):
	for pill in my_pills + opp_pills:
		if not pill.visible:
			continue
		var dist: float = pill.position.distance_to(pit_center)
		if dist < Constants.PIT_RADIUS * 0.6:
			_eliminate_pill(pill)
		elif dist < Constants.PIT_PULL_RADIUS:
			var pull_dir: Vector2 = (pit_center - pill.position).normalized()
			var strength: float = Constants.PIT_PULL_STRENGTH * (1.0 - dist / Constants.PIT_PULL_RADIUS)
			pill.apply_central_force(pull_dir * strength)

func _eliminate_pill(pill: Pill):
	if not pill.visible:
		return
	pill.visible = false
	pill.freeze = true
	pill.position = Vector2(-1000, -1000)

func _alive_pills(pills: Array) -> Array:
	var result: Array = []
	for p in pills:
		if p.visible:
			result.append(p)
	return result

func _all_stopped() -> bool:
	for pill in my_pills + opp_pills:
		if pill.visible and not pill.is_stopped():
			return false
	return true

# ── Input ──

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if quit_confirm.visible:
			_on_quit_cancel()
		else:
			_on_quit_pressed()
		return

	if phase != Phase.AIMING or shots_submitted:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release()
	elif event is InputEventMouseMotion and dragging:
		_on_drag(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release()
	elif event is InputEventScreenDrag:
		_on_drag(event.position)

func _on_press(pos: Vector2):
	var alive := _alive_pills(my_pills)
	var closest_pill: Pill = null
	var closest_dist: float = Constants.PILL_RADIUS * 3.0
	for pill in alive:
		var dist: float = pill.position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_pill = pill
	if closest_pill != null:
		for p in my_pills:
			p.is_selected = false
		selected_pill = closest_pill
		closest_pill.is_selected = true
		dragging = true
		drag_start = pos
		drag_cur = pos
		if closest_pill in shot_map:
			aim_dir = shot_map[closest_pill].dir
			aim_pow = shot_map[closest_pill].power
		else:
			aim_pow = 0.0

func _on_drag(pos: Vector2):
	if not dragging or selected_pill == null:
		return
	drag_cur = pos
	var pull: Vector2 = drag_cur - selected_pill.position
	if pull.length() < 5.0:
		aim_pow = 0.0
		return
	aim_dir = -pull.normalized()
	aim_pow = clampf(pull.length() * Constants.POWER_SCALE, 0, Constants.MAX_POWER)

func _on_release():
	if not dragging or selected_pill == null:
		return
	dragging = false
	if aim_pow > Constants.MIN_POWER:
		shot_map[selected_pill] = {"dir": aim_dir, "power": aim_pow}

# ── Drawing ──

func _draw():
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.18, 0.15, 0.12))
	_draw_arena()
	_draw_pit()
	_draw_arena_lines()
	if phase == Phase.AIMING and not shots_submitted:
		_draw_locked_arrows()
		if selected_pill != null and aim_pow > Constants.MIN_POWER:
			_draw_aim_arrow()

func _draw_arena():
	var ar: Rect2 = Constants.BATTLE_ARENA_RECT
	var cr: float = Constants.ARENA_CORNER_RADIUS
	var points := PackedVector2Array()
	var segments := 16

	points.append(Vector2(ar.position.x + cr, ar.position.y))
	points.append(Vector2(ar.position.x + ar.size.x - cr, ar.position.y))
	for i in range(segments + 1):
		var angle: float = -PI / 2.0 + (PI / 2.0) * i / segments
		points.append(Vector2(ar.position.x + ar.size.x - cr, ar.position.y + cr) + Vector2(cos(angle), sin(angle)) * cr)
	points.append(Vector2(ar.position.x + ar.size.x, ar.position.y + ar.size.y - cr))
	for i in range(segments + 1):
		var angle: float = 0.0 + (PI / 2.0) * i / segments
		points.append(Vector2(ar.position.x + ar.size.x - cr, ar.position.y + ar.size.y - cr) + Vector2(cos(angle), sin(angle)) * cr)
	points.append(Vector2(ar.position.x + cr, ar.position.y + ar.size.y))
	for i in range(segments + 1):
		var angle: float = PI / 2.0 + (PI / 2.0) * i / segments
		points.append(Vector2(ar.position.x + cr, ar.position.y + ar.size.y - cr) + Vector2(cos(angle), sin(angle)) * cr)
	points.append(Vector2(ar.position.x, ar.position.y + cr))
	for i in range(segments + 1):
		var angle: float = PI + (PI / 2.0) * i / segments
		points.append(Vector2(ar.position.x + cr, ar.position.y + cr) + Vector2(cos(angle), sin(angle)) * cr)

	if arena_texture:
		var uvs := PackedVector2Array()
		for pt in points:
			var u: float = (pt.x - ar.position.x) / ar.size.x
			var v: float = (pt.y - ar.position.y) / ar.size.y
			uvs.append(Vector2(u, v))
		var colors := PackedColorArray()
		for i in range(points.size()):
			colors.append(Color.WHITE)
		draw_polygon(points, colors, uvs, arena_texture)
	else:
		var colors := PackedColorArray()
		for i in range(points.size()):
			colors.append(Constants.ARENA_COLOR)
		draw_polygon(points, colors)

	for i in range(points.size()):
		draw_line(points[i], points[(i + 1) % points.size()], Constants.ARENA_WALL_COLOR, Constants.WALL_THICKNESS)

func _draw_pit():
	var pr: float = Constants.PIT_PULL_RADIUS
	draw_arc(pit_center, pr, 0, TAU, 64, Color(0.5, 0.3, 0.15, 0.15), 2.0, true)
	for ring in range(3):
		var r: float = Constants.PIT_RADIUS - ring * 8.0
		if r <= 0:
			break
		var alpha: float = 0.6 + ring * 0.15
		draw_arc(pit_center, r, 0, TAU, 64, Constants.PIT_EDGE_COLOR * Color(1, 1, 1, alpha), 3.0, true)
	draw_circle(pit_center, Constants.PIT_RADIUS * 0.85, Constants.PIT_COLOR)
	draw_circle(pit_center, Constants.PIT_RADIUS * 0.4, Color(0.03, 0.02, 0.01))

func _draw_arena_lines():
	var ar: Rect2 = Constants.BATTLE_ARENA_RECT
	var cx: float = ar.position.x + ar.size.x / 2.0
	var cy: float = ar.position.y + ar.size.y / 2.0
	var lc: Color = Constants.ARENA_LINE_COLOR
	draw_line(Vector2(cx, ar.position.y), Vector2(cx, ar.position.y + ar.size.y), lc, 1.5)
	draw_arc(Vector2(cx, cy), Constants.PIT_PULL_RADIUS + 20, 0, TAU, 64, lc, 1.0, true)

func _draw_aim_arrow():
	if selected_pill == null:
		return
	var pill_pos: Vector2 = selected_pill.position
	var color := Constants.AIM_VALID_COLOR
	var arrow_len: float = aim_pow / Constants.POWER_SCALE
	var arrow_end: Vector2 = pill_pos + aim_dir * arrow_len
	draw_line(pill_pos, arrow_end, color, 2.5)
	var hs := 10.0
	var perp: Vector2 = aim_dir.rotated(PI / 2.0)
	var base_pt: Vector2 = arrow_end - aim_dir * hs
	draw_polygon(
		[arrow_end, base_pt + perp * hs * 0.5, base_pt - perp * hs * 0.5],
		[color, color, color])
	var bar_w := 50.0
	var bar_h := 5.0
	var bar_pos: Vector2 = pill_pos + Vector2(-bar_w / 2, -Constants.PILL_RADIUS - 16)
	var pct: float = aim_pow / Constants.MAX_POWER
	draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.2, 0.2, 0.2, 0.5))
	var bar_col: Color = Color(0.2, 1.0, 0.2).lerp(Color(1.0, 0.2, 0.2), pct)
	draw_rect(Rect2(bar_pos, Vector2(bar_w * pct, bar_h)), bar_col)

func _draw_locked_arrows():
	for pill in shot_map:
		if not pill.visible:
			continue
		if pill == selected_pill:
			continue
		var shot: Dictionary = shot_map[pill]
		var arrow_len: float = shot.power / Constants.POWER_SCALE
		var arrow_end: Vector2 = pill.position + shot.dir * arrow_len
		var col := Color(0.4, 0.9, 0.4, 0.5)
		draw_line(pill.position, arrow_end, col, 2.0)
		var hs := 8.0
		var perp: Vector2 = shot.dir.rotated(PI / 2.0)
		var base_pt: Vector2 = arrow_end - shot.dir * hs
		draw_polygon(
			[arrow_end, base_pt + perp * hs * 0.5, base_pt - perp * hs * 0.5],
			[col, col, col])
		var bar_w := 50.0
		var bar_h := 5.0
		var bar_pos: Vector2 = pill.position + Vector2(-bar_w / 2, -Constants.PILL_RADIUS - 16)
		var pct: float = shot.power / Constants.MAX_POWER
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.2, 0.2, 0.2, 0.4))
		var bar_col: Color = Color(0.2, 1.0, 0.2).lerp(Color(1.0, 0.2, 0.2), pct)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * pct, bar_h)), Color(bar_col.r, bar_col.g, bar_col.b, 0.5))

# ── HUD ──

func _update_hud():
	var alive_my := _alive_pills(my_pills).size()
	var alive_opp := _alive_pills(opp_pills).size()
	status_label.text = "%d  —  %d" % [alive_my, alive_opp]

	match phase:
		Phase.WAITING:
			timer_bar.visible = false
		Phase.AIMING:
			timer_bar.visible = true
			timer_bar.value = aim_timer
			var pct: float = aim_timer / Constants.BATTLE_AIM_TIME
			if pct > 0.5:
				timer_bar_style.bg_color = Color(0.2, 0.9, 0.2)
			elif pct > 0.25:
				timer_bar_style.bg_color = Color(0.95, 0.85, 0.1)
			else:
				timer_bar_style.bg_color = Color(0.95, 0.2, 0.15)
		Phase.EXECUTING, Phase.SETTLING:
			timer_bar.visible = false
		Phase.ELIMINATION:
			timer_bar.visible = false
		Phase.GAME_OVER:
			timer_bar.visible = false

# ── Build helpers ──

func _build_arena_walls():
	var ar: Rect2 = Constants.BATTLE_ARENA_RECT
	var wt: float = Constants.WALL_THICKNESS
	var cr: float = Constants.ARENA_CORNER_RADIUS

	_wall(Vector2(ar.position.x + ar.size.x / 2.0, ar.position.y - wt / 2.0), Vector2(ar.size.x - cr * 2, wt))
	_wall(Vector2(ar.position.x + ar.size.x / 2.0, ar.position.y + ar.size.y + wt / 2.0), Vector2(ar.size.x - cr * 2, wt))
	_wall(Vector2(ar.position.x - wt / 2.0, ar.position.y + ar.size.y / 2.0), Vector2(wt, ar.size.y - cr * 2))
	_wall(Vector2(ar.position.x + ar.size.x + wt / 2.0, ar.position.y + ar.size.y / 2.0), Vector2(wt, ar.size.y - cr * 2))

	var corner_segments := 8
	for corner in range(4):
		var cx: float
		var cy: float
		var start_angle: float
		match corner:
			0:
				cx = ar.position.x + cr
				cy = ar.position.y + cr
				start_angle = PI
			1:
				cx = ar.position.x + ar.size.x - cr
				cy = ar.position.y + cr
				start_angle = -PI / 2.0
			2:
				cx = ar.position.x + ar.size.x - cr
				cy = ar.position.y + ar.size.y - cr
				start_angle = 0.0
			3:
				cx = ar.position.x + cr
				cy = ar.position.y + ar.size.y - cr
				start_angle = PI / 2.0

		for seg in range(corner_segments):
			var a1: float = start_angle + (PI / 2.0) * seg / corner_segments
			var a2: float = start_angle + (PI / 2.0) * (seg + 1) / corner_segments
			var p1 := Vector2(cx + cos(a1) * cr, cy + sin(a1) * cr)
			var p2 := Vector2(cx + cos(a2) * cr, cy + sin(a2) * cr)
			var mid := (p1 + p2) / 2.0
			var seg_len: float = p1.distance_to(p2)
			var angle: float = (p2 - p1).angle()
			_wall_angled(mid, Vector2(seg_len + 2.0, wt), angle)

func _wall(pos: Vector2, size: Vector2):
	var body := StaticBody2D.new()
	body.position = pos
	var shape := RectangleShape2D.new()
	shape.size = size
	var col := CollisionShape2D.new()
	col.shape = shape
	body.add_child(col)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.7
	body.physics_material_override = mat
	add_child(body)

func _wall_angled(pos: Vector2, size: Vector2, angle: float):
	var body := StaticBody2D.new()
	body.position = pos
	body.rotation = angle
	var shape := RectangleShape2D.new()
	shape.size = size
	var col := CollisionShape2D.new()
	col.shape = shape
	body.add_child(col)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.7
	body.physics_material_override = mat
	add_child(body)

func _build_pit():
	pit_area = Area2D.new()
	pit_area.position = pit_center
	var shape := CircleShape2D.new()
	shape.radius = Constants.PIT_RADIUS * 0.6
	var col := CollisionShape2D.new()
	col.shape = shape
	pit_area.add_child(col)
	pit_area.collision_layer = 0
	pit_area.collision_mask = 1
	pit_area.body_entered.connect(_on_pit_body_entered)
	add_child(pit_area)

func _on_pit_body_entered(body: Node2D):
	if body is Pill and body.visible:
		_eliminate_pill(body)

func _build_pills():
	var my_starts: Array = Constants.BATTLE_PLAYER_START if i_am_player1 else Constants.BATTLE_AI_START
	var opp_starts: Array = Constants.BATTLE_AI_START if i_am_player1 else Constants.BATTLE_PLAYER_START
	var my_color: Color = Constants.PLAYER_COLOR if i_am_player1 else Constants.AI_COLOR
	var my_color_light: Color = Constants.PLAYER_COLOR_LIGHT if i_am_player1 else Constants.AI_COLOR_LIGHT
	var opp_color: Color = Constants.AI_COLOR if i_am_player1 else Constants.PLAYER_COLOR
	var opp_color_light: Color = Constants.AI_COLOR_LIGHT if i_am_player1 else Constants.PLAYER_COLOR_LIGHT

	for i in range(3):
		var p := Pill.new()
		p.team = "mine"
		p.pill_index = i
		p.pill_color = my_color
		p.pill_color_light = my_color_light
		p.position = my_starts[i]
		add_child(p)
		my_pills.append(p)

	for i in range(3):
		var p := Pill.new()
		p.team = "opponent"
		p.pill_index = i
		p.pill_color = opp_color
		p.pill_color_light = opp_color_light
		p.position = opp_starts[i]
		add_child(p)
		opp_pills.append(p)

func _build_hud():
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)

	var fl := Constants.FIELD_RECT.position.x
	var fr := fl + Constants.FIELD_RECT.size.x
	var avatar_size := 34.0
	my_avatar_rect = TextureRect.new()
	var st := Constants.safe_top
	my_avatar_rect.position = Vector2(fl, 4 + st)
	my_avatar_rect.size = Vector2(avatar_size, avatar_size)
	my_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	my_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_layer.add_child(my_avatar_rect)

	my_name_label = Label.new()
	my_name_label.text = "You"
	my_name_label.position = Vector2(fl + 40, 10 + st)
	my_name_label.size = Vector2(60, 30)
	my_name_label.add_theme_font_size_override("font_size", 18)
	my_name_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	hud_layer.add_child(my_name_label)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.position = Vector2(vp.x / 2.0 - 100, 8 + st)
	status_label.size = Vector2(200, 50)
	status_label.add_theme_font_size_override("font_size", 26)
	status_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	hud_layer.add_child(status_label)

	opp_name_label = Label.new()
	opp_name_label.text = "Opponent"
	opp_name_label.position = Vector2(fr - 130, 10 + st)
	opp_name_label.size = Vector2(90, 30)
	opp_name_label.add_theme_font_size_override("font_size", 18)
	opp_name_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.5))
	hud_layer.add_child(opp_name_label)

	opp_avatar_rect = TextureRect.new()
	opp_avatar_rect.position = Vector2(fr - avatar_size, 4 + st)
	opp_avatar_rect.size = Vector2(avatar_size, avatar_size)
	opp_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	opp_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_layer.add_child(opp_avatar_rect)

	timer_bar = ProgressBar.new()
	timer_bar.position = Vector2(vp.x / 2.0 - 300, vp.y - 35)
	timer_bar.size = Vector2(600, 16)
	timer_bar.min_value = 0.0
	timer_bar.max_value = Constants.BATTLE_AIM_TIME
	timer_bar.value = Constants.BATTLE_AIM_TIME
	timer_bar.show_percentage = false

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.2, 0.6)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	timer_bar.add_theme_stylebox_override("background", bg_style)

	timer_bar_style = StyleBoxFlat.new()
	timer_bar_style.bg_color = Color(0.2, 0.9, 0.2)
	timer_bar_style.corner_radius_top_left = 4
	timer_bar_style.corner_radius_top_right = 4
	timer_bar_style.corner_radius_bottom_left = 4
	timer_bar_style.corner_radius_bottom_right = 4
	timer_bar.add_theme_stylebox_override("fill", timer_bar_style)
	hud_layer.add_child(timer_bar)

	center_msg = Label.new()
	center_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_msg.position = Vector2(vp.x / 2.0 - 400, vp.y / 2.0 - 60)
	center_msg.size = Vector2(800, 120)
	center_msg.add_theme_font_size_override("font_size", 64)
	center_msg.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	center_msg.visible = false
	hud_layer.add_child(center_msg)

	quit_btn = Button.new()
	quit_btn.text = "✕"
	quit_btn.position = Vector2(vp.x - 50 - Constants.safe_right, 8 + Constants.safe_top)
	quit_btn.size = Vector2(40, 40)
	quit_btn.add_theme_font_size_override("font_size", 22)
	quit_btn.pressed.connect(_on_quit_pressed)
	hud_layer.add_child(quit_btn)

	_build_quit_confirm()

func _build_quit_confirm():
	quit_confirm = Panel.new()
	quit_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	quit_confirm.visible = false
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0, 0, 0, 0.6)
	quit_confirm.add_theme_stylebox_override("panel", overlay_style)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-150, -70)
	box.size = Vector2(300, 140)
	box.add_theme_constant_override("separation", 20)
	quit_confirm.add_child(box)
	var msg := Label.new()
	msg.text = "Leave match?"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 26)
	msg.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(msg)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 30)
	box.add_child(btn_row)
	var yes_btn := Button.new()
	yes_btn.text = "  Yes  "
	yes_btn.add_theme_font_size_override("font_size", 22)
	yes_btn.custom_minimum_size = Vector2(120, 44)
	yes_btn.pressed.connect(_on_quit_yes)
	btn_row.add_child(yes_btn)
	var no_btn := Button.new()
	no_btn.text = "  No  "
	no_btn.add_theme_font_size_override("font_size", 22)
	no_btn.custom_minimum_size = Vector2(120, 44)
	no_btn.pressed.connect(_on_quit_cancel)
	btn_row.add_child(no_btn)
	hud_layer.add_child(quit_confirm)

func _on_quit_pressed():
	quit_confirm.visible = true
	get_tree().paused = true

func _on_quit_yes():
	get_tree().paused = false
	Online.leave_match()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_quit_cancel():
	quit_confirm.visible = false
	get_tree().paused = false
