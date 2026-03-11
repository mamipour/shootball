extends Node2D

# Online multiplayer Curling mode.
# Alternating single-shot turns, 6 shots per end, proximity scoring.

enum Phase { WAITING, MY_AIM, OPP_AIM, EXECUTING, SETTLING, END_SCORED, GAME_OVER }

# ── Nodes ──
var my_pills: Array = []
var opp_pills: Array = []

# ── HUD ──
var hud_layer: CanvasLayer
var score_label: Label
var timer_bar: ProgressBar
var timer_bar_style: StyleBoxFlat
var phase_label: Label
var turn_indicator: Label
var center_msg: Label
var quit_btn: Button
var quit_confirm: Panel
var my_avatar_rect: TextureRect
var opp_avatar_rect: TextureRect
var my_name_label: Label
var opp_name_label: Label

# ── State ──
var phase: Phase = Phase.WAITING
var my_score: int = 0
var opp_score: int = 0
var end_num: int = 0
var i_am_player1: bool = true
var shot_number: int = 0

# ── Turn tracking ──
var my_used: Array[int] = []
var opp_used: Array[int] = []

# ── Single-shot aiming ──
var selected_pill: Pill = null
var dragging: bool = false
var drag_cur := Vector2.ZERO
var aim_dir := Vector2.ZERO
var aim_pow: float = 0.0

# ── Timer ──
var aim_timer: float = 0.0

# ── Settling ──
var settle_timer: float = 0.0

# ── End score display ──
var end_timer: float = 0.0

# ── Assets ──
var ice_texture: Texture2D = null

# ── Audio ──
var music: AudioStreamPlayer
var score_sfx: AudioStreamPlayer
var win_sfx: AudioStreamPlayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

	if Online.my_side != "":
		i_am_player1 = (Online.my_side == "player1")
	else:
		i_am_player1 = true

	ice_texture = load("res://assets/groundIce_wide_vector.svg")

	_setup_audio()
	_build_walls()
	_build_pills()
	_build_hud()
	_assign_avatars()

	Online.match_started.connect(_on_match_started)
	Online.curling_turn_started.connect(_on_curling_turn)
	Online.shots_received.connect(_on_shots_received)
	Online.curling_end_scored.connect(_on_curling_end_scored)
	Online.goal_scored.connect(_on_goal_scored)
	Online.game_over.connect(_on_game_over)
	Online.opponent_left.connect(_on_opponent_left)
	Online.timer_sync.connect(_on_timer_sync)
	Online.opponent_info_received.connect(_on_opponent_info)

	phase_label.text = "Waiting for opponent..."
	Online.send_ready()

func _setup_audio():
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/sounds/stadium.mp3")
	music.volume_db = -10.0
	music.finished.connect(func(): if phase != Phase.GAME_OVER: music.play())
	add_child(music)
	music.play()

	score_sfx = AudioStreamPlayer.new()
	score_sfx.stream = load("res://assets/sounds/goal.mp3")
	score_sfx.volume_db = 0.0
	add_child(score_sfx)

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

func _on_match_started(p_round: int, _p_aim_time: float):
	end_num = p_round
	my_used.clear()
	opp_used.clear()
	shot_number = 0
	settle_timer = 0.0
	center_msg.visible = false
	_clear_aim()
	print("[OnlineCurling] End %d started" % end_num)

func _on_curling_turn(whose_turn: String, p_shot_number: int, p_aim_time: float):
	shot_number = p_shot_number
	aim_timer = p_aim_time
	settle_timer = 0.0
	_clear_aim()

	var my_side := "player1" if i_am_player1 else "player2"
	if whose_turn == my_side:
		phase = Phase.MY_AIM
		var available := _my_available()
		if available.size() > 0:
			selected_pill = available[0]
			selected_pill.is_selected = true
	else:
		phase = Phase.OPP_AIM
	print("[OnlineCurling] Turn: %s, shot #%d" % [whose_turn, shot_number])

func _on_shots_received(p1_shot: Dictionary, p2_shot: Dictionary):
	phase = Phase.EXECUTING
	settle_timer = 0.0

	var my_shot: Dictionary = p1_shot if i_am_player1 else p2_shot
	var opp_shot: Dictionary = p2_shot if i_am_player1 else p1_shot

	if my_shot.has("shot") and my_shot.shot != null:
		var s: Dictionary = my_shot.shot
		var idx: int = int(s.get("pill_idx", 0))
		var dir := Vector2(float(s.get("dir_x", 0)), float(s.get("dir_y", 0)))
		var power: float = float(s.get("power", 0))
		if idx >= 0 and idx < 3 and power > 0:
			my_pills[idx].kick(dir.normalized() * power)
			if idx not in my_used:
				my_used.append(idx)

	if opp_shot.has("shot") and opp_shot.shot != null:
		var s: Dictionary = opp_shot.shot
		var idx: int = int(s.get("pill_idx", 0))
		var dir := Vector2(float(s.get("dir_x", 0)), float(s.get("dir_y", 0)))
		var power: float = float(s.get("power", 0))
		if idx >= 0 and idx < 3 and power > 0:
			opp_pills[idx].kick(dir.normalized() * power)
			if idx not in opp_used:
				opp_used.append(idx)

	if selected_pill != null:
		selected_pill.is_selected = false
		selected_pill = null

func _on_curling_end_scored(winner: String, points: int, scores: Dictionary):
	score_sfx.play()
	_update_scores_from_server(scores)
	phase = Phase.END_SCORED
	end_timer = 2.5
	var my_side := "player1" if i_am_player1 else "player2"
	if winner == "":
		center_msg.text = "Blank end!"
	elif winner == my_side:
		center_msg.text = "You +%d!" % points
	else:
		center_msg.text = "Opp +%d!" % points
	center_msg.visible = true

func _on_goal_scored(_scorer_id: String, scores: Dictionary):
	_update_scores_from_server(scores)

func _on_game_over(winner_id: String, reason: String, scores: Dictionary):
	_update_scores_from_server(scores)
	phase = Phase.GAME_OVER
	var i_won := (winner_id == Online.user_id)
	if reason == "opponent_left":
		center_msg.text = "YOU WIN!\nOpponent left"
	else:
		center_msg.text = "YOU WIN!" if i_won else "YOU LOSE!"
	center_msg.visible = true
	music.stop()
	win_sfx.play()

func _on_opponent_left():
	if phase != Phase.GAME_OVER:
		phase = Phase.GAME_OVER
		center_msg.text = "Opponent left"
		center_msg.visible = true

func _on_timer_sync(remaining: float):
	if phase == Phase.MY_AIM:
		aim_timer = remaining

func _update_scores_from_server(scores: Dictionary):
	var my_id := Online.user_id
	var opp_id := Online.opponent_user_id
	my_score = int(scores.get(my_id, my_score))
	opp_score = int(scores.get(opp_id, opp_score))

func _clear_aim():
	if selected_pill != null:
		selected_pill.is_selected = false
	selected_pill = null
	dragging = false
	aim_dir = Vector2.ZERO
	aim_pow = 0.0

# ── Process ──

func _process(delta: float):
	if get_tree().paused:
		return
	match phase:
		Phase.MY_AIM:
			aim_timer -= delta
			if aim_timer <= 0.0:
				_player_timeout()
		Phase.OPP_AIM:
			pass
		Phase.EXECUTING:
			settle_timer += delta
			if settle_timer > 0.5:
				phase = Phase.SETTLING
				settle_timer = 0.0
		Phase.SETTLING:
			if _all_stopped():
				settle_timer += delta
				if settle_timer >= Constants.SETTLE_GRACE_TIME:
					_on_shot_settled()
			else:
				settle_timer = 0.0
		Phase.END_SCORED:
			end_timer -= delta
			if end_timer <= 0.0:
				_reset_all()
				Online.send_ready()
				phase = Phase.WAITING
		Phase.GAME_OVER:
			pass

	_update_hud()
	queue_redraw()

func _my_available() -> Array:
	var result: Array = []
	for i in range(my_pills.size()):
		if i not in my_used:
			result.append(my_pills[i])
	return result

func _player_fire():
	if selected_pill == null or aim_pow < Constants.MIN_POWER:
		_player_timeout()
		return
	var pill_idx: int = my_pills.find(selected_pill)
	Online.submit_shot(pill_idx, aim_dir, aim_pow)
	selected_pill.is_selected = false
	selected_pill = null
	phase = Phase.WAITING

func _player_timeout():
	var available := _my_available()
	if available.is_empty():
		Online.submit_shot(0, Vector2.ZERO, 0.0)
	else:
		var pill: Pill = available[0]
		var idx: int = my_pills.find(pill)
		Online.submit_shot(idx, Vector2.ZERO, 0.0)
	if selected_pill != null:
		selected_pill.is_selected = false
	selected_pill = null
	phase = Phase.WAITING

func _on_shot_settled():
	if shot_number >= 6:
		_report_end_scores()
	else:
		Online.report_curling_shot_settled()
		phase = Phase.WAITING

func _report_end_scores():
	var center: Vector2 = _house_center()
	var outer_r: float = Constants.HOUSE_RADIUS_OUTER

	var my_dists: Array[float] = []
	var opp_dists: Array[float] = []
	for p in my_pills:
		var d: float = p.position.distance_to(center)
		if d <= outer_r:
			my_dists.append(d)
	for a in opp_pills:
		var d: float = a.position.distance_to(center)
		if d <= outer_r:
			opp_dists.append(d)

	my_dists.sort()
	opp_dists.sort()

	var points: int = 0
	var winner_id: String = ""

	if my_dists.is_empty() and opp_dists.is_empty():
		Online.report_curling_end_result("", 0)
		return

	if opp_dists.is_empty():
		points = my_dists.size()
		winner_id = Online.user_id
	elif my_dists.is_empty():
		points = opp_dists.size()
		winner_id = Online.opponent_user_id
	elif my_dists[0] < opp_dists[0]:
		winner_id = Online.user_id
		for d in my_dists:
			if d < opp_dists[0]:
				points += 1
			else:
				break
	else:
		winner_id = Online.opponent_user_id
		for d in opp_dists:
			if d < my_dists[0]:
				points += 1
			else:
				break

	Online.report_curling_end_result(winner_id, points)

func _house_center() -> Vector2:
	var f: Rect2 = Constants.FIELD_RECT
	return Vector2(f.position.x + f.size.x / 2.0, f.position.y + f.size.y / 2.0)

func _all_stopped() -> bool:
	for pill in my_pills + opp_pills:
		if not pill.is_stopped():
			return false
	return true

func _reset_all():
	var my_starts: Array = Constants.PLAYER_START if i_am_player1 else Constants.AI_START
	var opp_starts: Array = Constants.AI_START if i_am_player1 else Constants.PLAYER_START
	for i in range(3):
		my_pills[i].reset_to(my_starts[i])
	for i in range(3):
		opp_pills[i].reset_to(opp_starts[i])

# ── Input ──

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if quit_confirm.visible:
			_on_quit_cancel()
		else:
			_on_quit_pressed()
		return

	if phase != Phase.MY_AIM:
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
	var available := _my_available()
	var closest_pill: Pill = null
	var closest_dist: float = Constants.PILL_RADIUS * 3.0
	for pill in available:
		var dist: float = pill.position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_pill = pill
	if closest_pill != null:
		if selected_pill != null:
			selected_pill.is_selected = false
		selected_pill = closest_pill
		closest_pill.is_selected = true
		dragging = true
		drag_cur = pos
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
		_player_fire()

# ── Drawing ──

func _draw():
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.08, 0.10, 0.14))
	_draw_field()
	_draw_house()
	_draw_shot_indicators()
	if phase == Phase.MY_AIM and selected_pill != null and aim_pow > Constants.MIN_POWER:
		_draw_aim_arrow()

func _draw_field():
	var f: Rect2 = Constants.FIELD_RECT
	if ice_texture:
		draw_texture_rect(ice_texture, f, false)
	else:
		draw_rect(f, Color(0.82, 0.90, 0.95))
	draw_rect(f, Color(0.6, 0.75, 0.85, 0.4), false, 2.0)

func _draw_house():
	var center: Vector2 = _house_center()
	var field: Rect2 = Constants.FIELD_RECT

	draw_circle(center, Constants.HOUSE_RADIUS_OUTER, Color(0.15, 0.35, 0.75, 0.3))
	draw_arc(center, Constants.HOUSE_RADIUS_OUTER, 0, TAU, 64, Color(0.2, 0.4, 0.85, 0.6), 2.5, true)

	draw_circle(center, Constants.HOUSE_RADIUS_MID, Color(0.95, 0.95, 0.97, 0.35))
	draw_arc(center, Constants.HOUSE_RADIUS_MID, 0, TAU, 64, Color(0.7, 0.7, 0.75, 0.5), 2.0, true)

	draw_circle(center, Constants.HOUSE_RADIUS_INNER, Color(0.85, 0.15, 0.15, 0.3))
	draw_arc(center, Constants.HOUSE_RADIUS_INNER, 0, TAU, 64, Color(0.9, 0.2, 0.2, 0.6), 2.0, true)

	draw_circle(center, Constants.HOUSE_RADIUS_BUTTON, Color(0.9, 0.2, 0.2, 0.7))
	draw_arc(center, Constants.HOUSE_RADIUS_BUTTON, 0, TAU, 32, Color(0.5, 0.1, 0.1, 0.8), 1.5, true)

	var cl := Color(0.5, 0.6, 0.7, 0.3)
	draw_line(Vector2(center.x, field.position.y), Vector2(center.x, field.position.y + field.size.y), cl, 1.0)
	draw_line(Vector2(field.position.x, center.y), Vector2(field.position.x + field.size.x, center.y), cl, 1.0)

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
	draw_polygon([arrow_end, base_pt + perp * hs * 0.5, base_pt - perp * hs * 0.5], [color, color, color])
	var bar_w := 50.0
	var bar_h := 5.0
	var bar_pos: Vector2 = pill_pos + Vector2(-bar_w / 2, -Constants.PILL_RADIUS - 16)
	var pct: float = aim_pow / Constants.MAX_POWER
	draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.2, 0.2, 0.2, 0.5))
	var bar_col: Color = Color(0.2, 1.0, 0.2).lerp(Color(1.0, 0.2, 0.2), pct)
	draw_rect(Rect2(bar_pos, Vector2(bar_w * pct, bar_h)), bar_col)

func _draw_shot_indicators():
	var f: Rect2 = Constants.FIELD_RECT
	var y_top: float = f.position.y - 5
	var dot_r := 6.0
	var gap := 18.0

	var my_color: Color = Constants.PLAYER_COLOR if i_am_player1 else Constants.AI_COLOR
	var opp_color: Color = Constants.AI_COLOR if i_am_player1 else Constants.PLAYER_COLOR

	var px: float = f.position.x + 20
	for i in range(3):
		var col: Color
		if i in my_used:
			col = Color(my_color, 0.3)
		else:
			col = my_color
		draw_circle(Vector2(px + i * gap, y_top), dot_r, col)

	var ax: float = f.position.x + f.size.x - 20 - 2 * gap
	for i in range(3):
		var col: Color
		if i in opp_used:
			col = Color(opp_color, 0.3)
		else:
			col = opp_color
		draw_circle(Vector2(ax + i * gap, y_top), dot_r, col)

# ── HUD ──

func _update_hud():
	score_label.text = "%d – %d   End %d" % [my_score, opp_score, end_num]

	match phase:
		Phase.WAITING:
			timer_bar.visible = false
			phase_label.text = "Waiting..."
			turn_indicator.text = ""
		Phase.MY_AIM:
			timer_bar.visible = true
			timer_bar.value = aim_timer
			var pct: float = aim_timer / Constants.CURLING_AIM_TIME
			if pct > 0.5:
				timer_bar_style.bg_color = Color(0.2, 0.9, 0.2)
			elif pct > 0.25:
				timer_bar_style.bg_color = Color(0.95, 0.85, 0.1)
			else:
				timer_bar_style.bg_color = Color(0.95, 0.2, 0.15)
			var remaining: int = 3 - my_used.size()
			phase_label.text = "Your turn! Drag a disc to shoot  ·  %d disc%s left" % [remaining, "" if remaining == 1 else "s"]
			turn_indicator.text = "▶ YOUR SHOT"
			turn_indicator.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
		Phase.OPP_AIM:
			timer_bar.visible = false
			phase_label.text = "Opponent is aiming..."
			turn_indicator.text = "▶ OPP SHOT"
			turn_indicator.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
		Phase.EXECUTING, Phase.SETTLING:
			timer_bar.visible = false
			phase_label.text = ""
			turn_indicator.text = "Shot %d / 6" % shot_number if shot_number <= 6 else ""
		Phase.END_SCORED:
			timer_bar.visible = false
			phase_label.text = ""
			turn_indicator.text = ""
		Phase.GAME_OVER:
			timer_bar.visible = false
			phase_label.text = ""
			turn_indicator.text = ""

# ── Build helpers ──

func _build_walls():
	var f: Rect2 = Constants.FIELD_RECT
	var wt: float = Constants.WALL_THICKNESS
	_wall(Vector2(f.position.x + f.size.x / 2.0, f.position.y - wt / 2.0), Vector2(f.size.x + wt * 2, wt))
	_wall(Vector2(f.position.x + f.size.x / 2.0, f.position.y + f.size.y + wt / 2.0), Vector2(f.size.x + wt * 2, wt))
	_wall(Vector2(f.position.x - wt / 2.0, f.position.y + f.size.y / 2.0), Vector2(wt, f.size.y + wt * 2))
	_wall(Vector2(f.position.x + f.size.x + wt / 2.0, f.position.y + f.size.y / 2.0), Vector2(wt, f.size.y + wt * 2))

func _wall(pos: Vector2, size: Vector2):
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = size
	var col := CollisionShape2D.new()
	col.shape = shape
	body.add_child(col)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.5
	body.physics_material_override = mat
	add_child(body)

func _build_pills():
	var my_starts: Array = Constants.PLAYER_START if i_am_player1 else Constants.AI_START
	var opp_starts: Array = Constants.AI_START if i_am_player1 else Constants.PLAYER_START
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
		p.linear_damp = Constants.CURLING_PILL_DAMP
		add_child(p)
		my_pills.append(p)

	for i in range(3):
		var p := Pill.new()
		p.team = "opponent"
		p.pill_index = i
		p.pill_color = opp_color
		p.pill_color_light = opp_color_light
		p.position = opp_starts[i]
		p.linear_damp = Constants.CURLING_PILL_DAMP
		add_child(p)
		opp_pills.append(p)

func _build_hud():
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)

	var avatar_size := 34.0
	my_avatar_rect = TextureRect.new()
	my_avatar_rect.position = Vector2(vp.x / 2.0 - 210, 4)
	my_avatar_rect.size = Vector2(avatar_size, avatar_size)
	my_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	my_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_layer.add_child(my_avatar_rect)

	my_name_label = Label.new()
	my_name_label.text = "You"
	my_name_label.position = Vector2(vp.x / 2.0 - 170, 10)
	my_name_label.size = Vector2(60, 30)
	my_name_label.add_theme_font_size_override("font_size", 18)
	my_name_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	hud_layer.add_child(my_name_label)

	score_label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.position = Vector2(vp.x / 2.0 - 100, 8)
	score_label.size = Vector2(200, 50)
	score_label.add_theme_font_size_override("font_size", 28)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	hud_layer.add_child(score_label)

	opp_name_label = Label.new()
	opp_name_label.text = "Opponent"
	opp_name_label.position = Vector2(vp.x / 2.0 + 110, 10)
	opp_name_label.size = Vector2(90, 30)
	opp_name_label.add_theme_font_size_override("font_size", 18)
	opp_name_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.5))
	hud_layer.add_child(opp_name_label)

	opp_avatar_rect = TextureRect.new()
	opp_avatar_rect.position = Vector2(vp.x / 2.0 + 205, 4)
	opp_avatar_rect.size = Vector2(avatar_size, avatar_size)
	opp_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	opp_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_layer.add_child(opp_avatar_rect)

	phase_label = Label.new()
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.position = Vector2(vp.x / 2.0 - 350, 38)
	phase_label.size = Vector2(700, 25)
	phase_label.add_theme_font_size_override("font_size", 16)
	phase_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	hud_layer.add_child(phase_label)

	turn_indicator = Label.new()
	turn_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_indicator.position = Vector2(vp.x / 2.0 - 150, 58)
	turn_indicator.size = Vector2(300, 30)
	turn_indicator.add_theme_font_size_override("font_size", 18)
	turn_indicator.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	hud_layer.add_child(turn_indicator)

	timer_bar = ProgressBar.new()
	timer_bar.position = Vector2(vp.x / 2.0 - 300, vp.y - 35)
	timer_bar.size = Vector2(600, 16)
	timer_bar.min_value = 0.0
	timer_bar.max_value = Constants.CURLING_AIM_TIME
	timer_bar.value = Constants.CURLING_AIM_TIME
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
	center_msg.add_theme_font_size_override("font_size", 72)
	center_msg.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
	center_msg.visible = false
	hud_layer.add_child(center_msg)

	quit_btn = Button.new()
	quit_btn.text = "✕"
	quit_btn.position = Vector2(vp.x - 50, 8)
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
