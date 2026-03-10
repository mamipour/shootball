extends Node2D

# Online multiplayer version of the game.
# Player controls their side's pills; opponent shots come from the server.

enum Phase { WAITING, AIMING, EXECUTING, SETTLING, GOAL_SCORED, GAME_OVER }

# ── Nodes ──
var my_pills: Array = []
var opp_pills: Array = []

# ── HUD ──
var hud_layer: CanvasLayer
var score_label: Label
var timer_bar: ProgressBar
var timer_bar_style: StyleBoxFlat
var phase_label: Label
var center_msg: Label
var quit_btn: Button
var quit_confirm: Panel

# ── State ──
var phase: Phase = Phase.WAITING
var my_score: int = 0
var opp_score: int = 0
var round_num: int = 0
var i_am_player1: bool = true

# ── Aiming ──
var sel_idx: int = -1
var dragging: bool = false
var drag_start := Vector2.ZERO
var drag_cur := Vector2.ZERO
var aim_dir := Vector2.ZERO
var aim_pow: float = 0.0
var aim_valid: bool = false
var shot_submitted: bool = false

# ── Timer ──
var aim_timer: float = 0.0

# ── Pending opponent shot (from server) ──
var pending_opp_shot: Dictionary = {}
var pending_my_shot: Dictionary = {}

# ── Assets ──
var grass_texture: Texture2D = null
var goal_left_tex: Texture2D = null
var goal_right_tex: Texture2D = null

# ── Audio ──
var stadium_music: AudioStreamPlayer
var goal_sfx: AudioStreamPlayer
var win_sfx: AudioStreamPlayer

# ── Settling ──
var settle_timer: float = 0.0

# ── Goal ──
var goal_timer: float = 0.0
var scorer_side: String = ""
var goal_this_round: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	i_am_player1 = (Online.my_side == "player1")

	grass_texture = load("res://assets/groundGrass_mownWide_vector.svg")
	goal_left_tex = load("res://assets/goal_left.svg")
	goal_right_tex = load("res://assets/goal_right.svg")

	_setup_audio()
	_build_walls()
	_build_pills()
	_assign_avatars()
	_build_hud()

	# Connect server signals
	Online.match_started.connect(_on_match_started)
	Online.shots_received.connect(_on_shots_received)
	Online.goal_scored.connect(_on_goal_scored)
	Online.game_over.connect(_on_game_over)
	Online.opponent_left.connect(_on_opponent_left)
	Online.timer_sync.connect(_on_timer_sync)

	phase_label.text = "Waiting for match to start..."

func _setup_audio():
	stadium_music = AudioStreamPlayer.new()
	stadium_music.stream = load("res://assets/sounds/stadium.mp3")
	stadium_music.volume_db = -8.0
	stadium_music.finished.connect(func(): if phase != Phase.GAME_OVER: stadium_music.play())
	add_child(stadium_music)
	stadium_music.play()

	goal_sfx = AudioStreamPlayer.new()
	goal_sfx.stream = load("res://assets/sounds/goal.mp3")
	goal_sfx.volume_db = 0.0
	add_child(goal_sfx)

	win_sfx = AudioStreamPlayer.new()
	win_sfx.stream = load("res://assets/sounds/win.mp3")
	win_sfx.volume_db = 0.0
	add_child(win_sfx)

func _assign_avatars():
	var my_tex := _load_avatar(Constants.player_avatar_idx)
	var opp_tex := _load_avatar(Constants.ai_avatar_idx)
	for pill in my_pills:
		pill.avatar_texture = my_tex
	for pill in opp_pills:
		pill.avatar_texture = opp_tex

func _load_avatar(idx: int) -> Texture2D:
	if idx < 0 or idx >= Constants.AVATAR_COUNT:
		return null
	return load(Constants.AVATAR_DIR + "avatar_%02d.png" % idx)

# ── Server signal handlers ──

func _on_match_started(p_round: int, p_aim_time: float):
	round_num = p_round
	aim_timer = p_aim_time
	phase = Phase.AIMING
	sel_idx = -1
	dragging = false
	shot_submitted = false
	aim_valid = false
	aim_pow = 0.0
	goal_this_round = false
	settle_timer = 0.0
	center_msg.visible = false
	pending_opp_shot = {}
	pending_my_shot = {}
	for p in my_pills:
		p.is_selected = false
	print("[Online] Round %d started" % round_num)

func _on_shots_received(p1_data: Dictionary, p2_data: Dictionary):
	phase = Phase.EXECUTING
	settle_timer = 0.0

	var my_data: Dictionary
	var opp_data: Dictionary
	if i_am_player1:
		my_data = p1_data.get("shot", {})
		opp_data = p2_data.get("shot", {})
	else:
		my_data = p2_data.get("shot", {})
		opp_data = p1_data.get("shot", {})

	# Fire my shot
	if my_data.size() > 0:
		var idx: int = int(my_data.get("pill_idx", 0))
		var dir := Vector2(float(my_data.get("dir_x", 0)), float(my_data.get("dir_y", 0)))
		var power: float = float(my_data.get("power", 0))
		if idx >= 0 and idx < 3:
			my_pills[idx].kick(dir.normalized() * power)

	# Fire opponent shot
	if opp_data.size() > 0:
		var idx: int = int(opp_data.get("pill_idx", 0))
		var dir := Vector2(float(opp_data.get("dir_x", 0)), float(opp_data.get("dir_y", 0)))
		var power: float = float(opp_data.get("power", 0))
		if idx >= 0 and idx < 3:
			opp_pills[idx].kick(dir.normalized() * power)

	for p in my_pills:
		p.is_selected = false
	sel_idx = -1
	print("[Online] Shots fired")

func _on_goal_scored(scorer_id: String, scores: Dictionary):
	goal_this_round = true
	goal_sfx.play()
	_update_scores_from_server(scores)
	phase = Phase.GOAL_SCORED
	goal_timer = Constants.GOAL_DISPLAY_TIME
	center_msg.text = "GOAL!"
	center_msg.visible = true

func _on_game_over(winner_id: String, reason: String, scores: Dictionary):
	_update_scores_from_server(scores)
	phase = Phase.GAME_OVER
	var i_won := (winner_id == Online.user_id)
	if reason == "opponent_left":
		center_msg.text = "YOU WIN!\nOpponent left"
	else:
		center_msg.text = "YOU WIN!" if i_won else "YOU LOSE!"
	center_msg.visible = true
	stadium_music.stop()
	win_sfx.play()

func _on_opponent_left():
	if phase != Phase.GAME_OVER:
		phase = Phase.GAME_OVER
		center_msg.text = "Opponent left"
		center_msg.visible = true

func _on_timer_sync(remaining: float):
	if phase == Phase.AIMING:
		aim_timer = remaining

func _update_scores_from_server(scores: Dictionary):
	var my_id := Online.user_id
	var opp_id := Online.opponent_user_id
	my_score = int(scores.get(my_id, my_score))
	opp_score = int(scores.get(opp_id, opp_score))

# ── Process ──

func _process(delta: float):
	if get_tree().paused:
		return
	match phase:
		Phase.AIMING:
			aim_timer -= delta
			if aim_timer <= 0.0:
				aim_timer = 0.0
		Phase.EXECUTING:
			settle_timer += delta
			_check_goals_local()
			if settle_timer > 0.5:
				phase = Phase.SETTLING
				settle_timer = 0.0
		Phase.SETTLING:
			_check_goals_local()
			if _all_stopped():
				settle_timer += delta
				if settle_timer >= Constants.SETTLE_GRACE_TIME:
					_report_round_result()
			else:
				settle_timer = 0.0
		Phase.GOAL_SCORED:
			goal_timer -= delta
			if goal_timer <= 0.0:
				_reset_pills()
				Online.send_ready()
		Phase.GAME_OVER:
			pass

	_update_hud()
	queue_redraw()

func _check_goals_local():
	if goal_this_round:
		return
	var f: Rect2 = Constants.FIELD_RECT
	var cy: float = f.position.y + f.size.y / 2.0
	var gh: float = Constants.GOAL_WIDTH / 2.0

	for pill in my_pills + opp_pills:
		var px: float = pill.position.x
		var py: float = pill.position.y
		if px > f.position.x + f.size.x + 5.0 and py > cy - gh and py < cy + gh:
			goal_this_round = true
			return
		if px < f.position.x - 5.0 and py > cy - gh and py < cy + gh:
			goal_this_round = true
			return

func _report_round_result():
	# Determine scorer locally and report to server
	var f: Rect2 = Constants.FIELD_RECT
	var cy: float = f.position.y + f.size.y / 2.0
	var gh: float = Constants.GOAL_WIDTH / 2.0
	var scorer_id := ""

	for pill in my_pills + opp_pills:
		var px: float = pill.position.x
		var py: float = pill.position.y
		# Right goal (player1 scores)
		if px > f.position.x + f.size.x + 5.0 and py > cy - gh and py < cy + gh:
			scorer_id = Online.user_id if i_am_player1 else Online.opponent_user_id
			break
		# Left goal (player2 scores)
		if px < f.position.x - 5.0 and py > cy - gh and py < cy + gh:
			scorer_id = Online.opponent_user_id if i_am_player1 else Online.user_id
			break

	Online.report_round_result(scorer_id)
	# Wait for server to respond with GOAL_SCORED or ROUND_START
	phase = Phase.WAITING

func _all_stopped() -> bool:
	for pill in my_pills + opp_pills:
		if not pill.is_stopped():
			return false
	return true

func _reset_pills():
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

	if phase != Phase.AIMING or shot_submitted:
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
	for i in range(my_pills.size()):
		if my_pills[i].position.distance_to(pos) < Constants.PILL_RADIUS * 2.5:
			for p in my_pills:
				p.is_selected = false
			sel_idx = i
			my_pills[i].is_selected = true
			dragging = true
			drag_start = pos
			drag_cur = pos
			return

func _on_drag(pos: Vector2):
	if not dragging or sel_idx < 0:
		return
	drag_cur = pos
	var pill_pos: Vector2 = my_pills[sel_idx].position
	var pull: Vector2 = drag_cur - pill_pos
	if pull.length() < 5.0:
		aim_pow = 0.0
		return
	aim_dir = -pull.normalized()
	aim_pow = clampf(pull.length() * Constants.POWER_SCALE, 0, Constants.MAX_POWER)
	var ga: Vector2 = my_pills[(sel_idx + 1) % 3].position
	var gb: Vector2 = my_pills[(sel_idx + 2) % 3].position
	aim_valid = _ray_hits_segment(pill_pos, aim_dir, ga, gb)

func _on_release():
	if dragging and sel_idx >= 0 and aim_pow > Constants.MIN_POWER and aim_valid:
		shot_submitted = true
		Online.submit_shot(sel_idx, aim_dir, aim_pow)
		phase_label.text = "Shot locked — waiting for opponent..."
	dragging = false

func _ray_hits_segment(origin: Vector2, dir: Vector2, a: Vector2, b: Vector2) -> bool:
	var d: Vector2 = dir.normalized()
	var ab: Vector2 = b - a
	var denom: float = d.x * ab.y - d.y * ab.x
	if absf(denom) < 0.001:
		return false
	var oa: Vector2 = a - origin
	var t: float = (oa.x * ab.y - oa.y * ab.x) / denom
	var s: float = (oa.x * d.y - oa.y * d.x) / denom
	return t > 0.0 and s > 0.05 and s < 0.95

# ── Drawing ──

func _draw():
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.06, 0.06, 0.10))
	_draw_field()
	_draw_field_lines()
	_draw_goal_pockets()
	if phase == Phase.AIMING and sel_idx >= 0 and not shot_submitted:
		_draw_gate()
		if aim_pow > Constants.MIN_POWER:
			_draw_aim_arrow()

func _draw_field():
	var f: Rect2 = Constants.FIELD_RECT
	if grass_texture:
		draw_texture_rect(grass_texture, f, false)
	else:
		draw_rect(f, Constants.FIELD_COLOR)

func _draw_field_lines():
	var f: Rect2 = Constants.FIELD_RECT
	var cx: float = f.position.x + f.size.x / 2.0
	var cy: float = f.position.y + f.size.y / 2.0
	var lc: Color = Constants.FIELD_LINE_COLOR
	var lw: float = 2.0
	draw_rect(f, lc, false, lw)
	draw_line(Vector2(cx, f.position.y), Vector2(cx, f.position.y + f.size.y), lc, lw)
	draw_arc(Vector2(cx, cy), 65, 0, TAU, 64, lc, lw)
	draw_circle(Vector2(cx, cy), 4, lc)
	var paw := 130.0
	var pah := 260.0
	draw_rect(Rect2(f.position.x, cy - pah / 2, paw, pah), lc, false, lw)
	draw_rect(Rect2(f.position.x + f.size.x - paw, cy - pah / 2, paw, pah), lc, false, lw)
	var gaw := 55.0
	var gah := 140.0
	draw_rect(Rect2(f.position.x, cy - gah / 2, gaw, gah), lc, false, lw)
	draw_rect(Rect2(f.position.x + f.size.x - gaw, cy - gah / 2, gaw, gah), lc, false, lw)
	draw_arc(Vector2(f.position.x + paw, cy), 55, -PI / 3, PI / 3, 32, lc, lw)
	draw_arc(Vector2(f.position.x + f.size.x - paw, cy), 55, PI - PI / 3, PI + PI / 3, 32, lc, lw)

func _draw_goal_pockets():
	var f: Rect2 = Constants.FIELD_RECT
	var cy: float = f.position.y + f.size.y / 2.0
	var gh: float = Constants.GOAL_WIDTH / 2.0
	var gd: float = Constants.GOAL_DEPTH
	var left_rect := Rect2(f.position.x - gd, cy - gh, gd, Constants.GOAL_WIDTH)
	var right_rect := Rect2(f.position.x + f.size.x, cy - gh, gd, Constants.GOAL_WIDTH)
	if goal_left_tex:
		draw_texture_rect(goal_left_tex, left_rect, false)
	else:
		draw_rect(left_rect, Color(0.10, 0.10, 0.15, 0.85))
	if goal_right_tex:
		draw_texture_rect(goal_right_tex, right_rect, false)
	else:
		draw_rect(right_rect, Color(0.10, 0.10, 0.15, 0.85))

func _draw_gate():
	var ga: Vector2 = my_pills[(sel_idx + 1) % 3].position
	var gb: Vector2 = my_pills[(sel_idx + 2) % 3].position
	draw_line(ga, gb, Constants.GATE_COLOR, 3.0)
	draw_circle(ga, 7, Constants.GATE_COLOR)
	draw_circle(gb, 7, Constants.GATE_COLOR)

func _draw_aim_arrow():
	var pill_pos: Vector2 = my_pills[sel_idx].position
	var color: Color = Constants.AIM_VALID_COLOR if aim_valid else Constants.AIM_INVALID_COLOR
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

# ── HUD ──

func _update_hud():
	score_label.text = "YOU  %d  –  %d  OPP" % [my_score, opp_score]

	match phase:
		Phase.WAITING:
			timer_bar.visible = false
			phase_label.text = "Waiting..."
		Phase.AIMING:
			timer_bar.visible = true
			timer_bar.value = aim_timer
			var pct: float = aim_timer / Constants.AIM_TIME
			if pct > 0.5:
				timer_bar_style.bg_color = Color(0.2, 0.9, 0.2)
			elif pct > 0.25:
				timer_bar_style.bg_color = Color(0.95, 0.85, 0.1)
			else:
				timer_bar_style.bg_color = Color(0.95, 0.2, 0.15)
			if shot_submitted:
				phase_label.text = "Shot locked — waiting for opponent..."
			elif sel_idx >= 0:
				phase_label.text = "Drag away from pill to aim  ·  release to lock"
			else:
				phase_label.text = "Tap one of your pills to select"
		Phase.EXECUTING, Phase.SETTLING:
			timer_bar.visible = false
			phase_label.text = ""
		Phase.GOAL_SCORED:
			timer_bar.visible = false
			phase_label.text = "Goal!"
		Phase.GAME_OVER:
			timer_bar.visible = false
			phase_label.text = ""

# ── Build helpers ──

func _build_walls():
	var f: Rect2 = Constants.FIELD_RECT
	var wt: float = Constants.WALL_THICKNESS
	var cy: float = f.position.y + f.size.y / 2.0
	var gh: float = Constants.GOAL_WIDTH / 2.0
	var gt: float = cy - gh
	var gb: float = cy + gh
	var gd: float = Constants.GOAL_DEPTH
	var rx: float = f.position.x + f.size.x
	var seg_top: float = gt - f.position.y
	var seg_bot: float = f.position.y + f.size.y - gb

	_wall(Vector2(f.position.x + f.size.x / 2.0, f.position.y - wt / 2.0), Vector2(f.size.x + wt * 2, wt))
	_wall(Vector2(f.position.x + f.size.x / 2.0, f.position.y + f.size.y + wt / 2.0), Vector2(f.size.x + wt * 2, wt))
	_wall(Vector2(f.position.x - wt / 2.0, f.position.y + seg_top / 2.0), Vector2(wt, seg_top))
	_wall(Vector2(f.position.x - wt / 2.0, gb + seg_bot / 2.0), Vector2(wt, seg_bot))
	_wall(Vector2(rx + wt / 2.0, f.position.y + seg_top / 2.0), Vector2(wt, seg_top))
	_wall(Vector2(rx + wt / 2.0, gb + seg_bot / 2.0), Vector2(wt, seg_bot))
	_wall(Vector2(f.position.x - gd - wt / 2.0, cy), Vector2(wt, Constants.GOAL_WIDTH + wt * 2))
	_wall(Vector2(f.position.x - gd / 2.0, gt - wt / 2.0), Vector2(gd, wt))
	_wall(Vector2(f.position.x - gd / 2.0, gb + wt / 2.0), Vector2(gd, wt))
	_wall(Vector2(rx + gd + wt / 2.0, cy), Vector2(wt, Constants.GOAL_WIDTH + wt * 2))
	_wall(Vector2(rx + gd / 2.0, gt - wt / 2.0), Vector2(gd, wt))
	_wall(Vector2(rx + gd / 2.0, gb + wt / 2.0), Vector2(gd, wt))

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

	score_label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.position = Vector2(440, 8)
	score_label.size = Vector2(400, 50)
	score_label.add_theme_font_size_override("font_size", 30)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	hud_layer.add_child(score_label)

	phase_label = Label.new()
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.position = Vector2(290, 38)
	phase_label.size = Vector2(700, 25)
	phase_label.add_theme_font_size_override("font_size", 16)
	phase_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	hud_layer.add_child(phase_label)

	timer_bar = ProgressBar.new()
	timer_bar.position = Vector2(340, 685)
	timer_bar.size = Vector2(600, 16)
	timer_bar.min_value = 0.0
	timer_bar.max_value = Constants.AIM_TIME
	timer_bar.value = Constants.AIM_TIME
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
	center_msg.position = Vector2(240, 250)
	center_msg.size = Vector2(800, 220)
	center_msg.add_theme_font_size_override("font_size", 80)
	center_msg.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
	center_msg.visible = false
	hud_layer.add_child(center_msg)

	quit_btn = Button.new()
	quit_btn.text = "✕"
	quit_btn.position = Vector2(1230, 8)
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
