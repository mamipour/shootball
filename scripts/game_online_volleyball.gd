extends Node2D

# Online multiplayer Volleyball mode.
# Multi-shot aiming, ball + net, ball-side scoring.

enum Phase { WAITING, AIMING, EXECUTING, SETTLING, POINT_SCORED, GAME_OVER }

class _VBall extends RigidBody2D:
	var ball_texture: Texture2D = null
	var _reset_pos: Vector2 = Vector2.ZERO
	var _has_reset: bool = false

	func reset_to(pos: Vector2):
		_reset_pos = pos
		_has_reset = true

	func _integrate_forces(state: PhysicsDirectBodyState2D):
		if _has_reset:
			state.transform = Transform2D(0, _reset_pos)
			state.linear_velocity = Vector2.ZERO
			state.angular_velocity = 0.0
			_has_reset = false

	func _draw():
		var r: float = Constants.VB_BALL_RADIUS
		draw_circle(Vector2(2, 2), r, Color(0.0, 0.0, 0.0, 0.2))
		if ball_texture != null:
			var size: float = r * 2.0
			draw_texture_rect(ball_texture, Rect2(Vector2(-r, -r), Vector2(size, size)), false)
		else:
			draw_circle(Vector2.ZERO, r, Color(0.9, 0.9, 0.92))
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(0.3, 0.3, 0.3, 0.6), 2.0, true)

	func _process(_delta: float):
		queue_redraw()

# ── Nodes ──
var my_pills: Array = []
var opp_pills: Array = []
var ball: RigidBody2D
var net_wall: StaticBody2D

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
var ball_side: String = "player1"
var ball_start_side: String = "player1"

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

# ── Point ──
var point_timer: float = 0.0

# ── Assets ──
var sand_texture: Texture2D = null
var ball_texture: Texture2D = null

# ── Audio ──
var stadium_music: AudioStreamPlayer
var point_sfx: AudioStreamPlayer
var win_sfx: AudioStreamPlayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

	if Online.my_side != "":
		i_am_player1 = (Online.my_side == "player1")
	else:
		i_am_player1 = true

	sand_texture = load("res://assets/groundSand_wide_vector.svg")
	ball_texture = load("res://assets/volleyball.svg")

	_setup_audio()
	_build_walls()
	_build_net()
	_build_ball()
	_build_pills()
	_assign_avatars()
	_build_hud()

	ball_side = "player1" if randi() % 2 == 0 else "player2"
	_place_ball_on_side(ball_side)

	Online.match_started.connect(_on_match_started)
	Online.multi_shots_received.connect(_on_multi_shots_received)
	Online.goal_scored.connect(_on_point_scored)
	Online.game_over.connect(_on_game_over)
	Online.opponent_left.connect(_on_opponent_left)
	Online.timer_sync.connect(_on_timer_sync)
	Online.opponent_info_received.connect(_on_opponent_info)

	phase_label.text = "Waiting for opponent..."
	Online.send_ready()

func _setup_audio():
	stadium_music = AudioStreamPlayer.new()
	stadium_music.stream = load("res://assets/sounds/stadium.mp3")
	stadium_music.volume_db = -8.0
	stadium_music.finished.connect(func(): if phase != Phase.GAME_OVER: stadium_music.play())
	add_child(stadium_music)
	stadium_music.play()

	point_sfx = AudioStreamPlayer.new()
	point_sfx.stream = load("res://assets/sounds/goal.mp3")
	point_sfx.volume_db = 0.0
	add_child(point_sfx)

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

func _rebuild_pills():
	for p in my_pills:
		p.queue_free()
	for p in opp_pills:
		p.queue_free()
	my_pills.clear()
	opp_pills.clear()
	_build_pills()
	_assign_avatars()

func _on_match_started(p_round: int, p_aim_time: float):
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
	ball_start_side = ball_side
	for p in my_pills:
		p.is_selected = false
	if round_num == 1:
		selected_pill = my_pills[2]
		my_pills[2].is_selected = true
	print("[OnlineVolleyball] Round %d started" % round_num)

func _on_multi_shots_received(p1_shots: Array, p2_shots: Array):
	phase = Phase.EXECUTING
	settle_timer = 0.0

	var my_shots: Array = p1_shots if i_am_player1 else p2_shots
	var opp_shots: Array = p2_shots if i_am_player1 else p1_shots

	for s in my_shots:
		var idx: int = int(s.get("pill_idx", 0))
		var dir := Vector2(float(s.get("dir_x", 0)), float(s.get("dir_y", 0)))
		var power: float = float(s.get("power", 0))
		if idx >= 0 and idx < 3 and power > 0:
			my_pills[idx].kick(dir.normalized() * power)

	for s in opp_shots:
		var idx: int = int(s.get("pill_idx", 0))
		var dir := Vector2(float(s.get("dir_x", 0)), float(s.get("dir_y", 0)))
		var power: float = float(s.get("power", 0))
		if idx >= 0 and idx < 3 and power > 0:
			opp_pills[idx].kick(dir.normalized() * power)

	for p in my_pills:
		p.is_selected = false
	selected_pill = null

func _on_point_scored(scorer_id: String, scores: Dictionary):
	point_sfx.play()
	_update_scores_from_server(scores)
	phase = Phase.POINT_SCORED
	point_timer = Constants.GOAL_DISPLAY_TIME
	var i_scored := (scorer_id == Online.user_id)
	center_msg.text = "You score!" if i_scored else "Opponent scores!"
	center_msg.visible = true
	# After point, ball goes to winner's side
	if scorer_id == Online.user_id:
		ball_side = "player1" if i_am_player1 else "player2"
	else:
		ball_side = "player2" if i_am_player1 else "player1"

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
			if aim_timer <= 0.0 and not shots_submitted:
				aim_timer = 0.0
				_submit_all_shots()
		Phase.EXECUTING:
			settle_timer += delta
			if settle_timer > 0.5:
				phase = Phase.SETTLING
				settle_timer = 0.0
		Phase.SETTLING:
			if _all_stopped():
				settle_timer += delta
				if settle_timer >= Constants.SETTLE_GRACE_TIME:
					_report_round_result()
			else:
				settle_timer = 0.0
		Phase.POINT_SCORED:
			point_timer -= delta
			if point_timer <= 0.0:
				_reset_all()
				Online.send_ready()
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
		shots_arr.append({"pill_idx": pill.pill_index, "dir": shot.dir, "power": shot.power})
	Online.submit_multi_shot(shots_arr)
	phase_label.text = "Shots submitted — waiting for opponent..."

func _check_ball_side() -> String:
	var f: Rect2 = Constants.FIELD_RECT
	var cx: float = f.position.x + f.size.x / 2.0
	if ball.position.x < cx:
		return "player1"
	else:
		return "player2"

func _report_round_result():
	var current_side: String = _check_ball_side()
	var scorer_id := ""

	if current_side == ball_start_side:
		# Ball stayed → that side failed → opponent scores
		if ball_start_side == "player1":
			scorer_id = Online.opponent_user_id if i_am_player1 else Online.user_id
		else:
			scorer_id = Online.user_id if i_am_player1 else Online.opponent_user_id
	else:
		# Ball crossed net — rally continues, no point
		ball_side = current_side

	Online.report_round_result(scorer_id)
	if scorer_id == "":
		phase = Phase.WAITING
	else:
		phase = Phase.WAITING

func _all_stopped() -> bool:
	if ball.linear_velocity.length() >= Constants.SETTLE_VELOCITY_THRESHOLD:
		return false
	for pill in my_pills + opp_pills:
		if not pill.is_stopped():
			return false
	return true

func _place_ball_on_side(side: String):
	var f: Rect2 = Constants.FIELD_RECT
	var cy: float = f.position.y + f.size.y / 2.0
	var ball_x: float
	if (side == "player1") == i_am_player1:
		ball_x = f.position.x + f.size.x * 0.25
	else:
		ball_x = f.position.x + f.size.x * 0.75
	ball.reset_to(Vector2(ball_x, cy))

func _reset_all():
	_place_ball_on_side(ball_side)
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
	var closest_pill: Pill = null
	var closest_dist: float = Constants.PILL_RADIUS * 3.0
	for pill in my_pills:
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
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.06, 0.06, 0.10))
	_draw_field()
	_draw_net_visual()
	if phase == Phase.AIMING and not shots_submitted:
		_draw_locked_arrows()
		if selected_pill != null and aim_pow > Constants.MIN_POWER:
			_draw_aim_arrow()

func _draw_field():
	var f: Rect2 = Constants.FIELD_RECT
	if sand_texture:
		draw_texture_rect(sand_texture, f, false)
	else:
		draw_rect(f, Color(0.76, 0.70, 0.50))
	var lc := Color(0.9, 0.85, 0.7, 0.35)
	draw_rect(f, lc, false, 2.0)

func _draw_net_visual():
	var f: Rect2 = Constants.FIELD_RECT
	var cx: float = f.position.x + f.size.x / 2.0
	var top_y: float = f.position.y
	var bot_y: float = f.position.y + f.size.y
	draw_line(Vector2(cx, top_y), Vector2(cx, bot_y), Color(1, 1, 1, 0.7), 3.0)
	var dash_len: float = 12.0
	var gap_len: float = 6.0
	var y: float = top_y
	while y < bot_y:
		var end_y: float = minf(y + dash_len, bot_y)
		draw_line(Vector2(cx - 5, y), Vector2(cx + 5, end_y), Color(1, 1, 1, 0.2), 1.0)
		draw_line(Vector2(cx + 5, y), Vector2(cx - 5, end_y), Color(1, 1, 1, 0.2), 1.0)
		y += dash_len + gap_len
	draw_circle(Vector2(cx, top_y), 5.0, Color(0.8, 0.8, 0.8, 0.6))
	draw_circle(Vector2(cx, bot_y), 5.0, Color(0.8, 0.8, 0.8, 0.6))

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
		draw_polygon([arrow_end, base_pt + perp * hs * 0.5, base_pt - perp * hs * 0.5], [col, col, col])

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
			var pct: float = aim_timer / Constants.VOLLEYBALL_AIM_TIME
			if pct > 0.5:
				timer_bar_style.bg_color = Color(0.2, 0.9, 0.2)
			elif pct > 0.25:
				timer_bar_style.bg_color = Color(0.95, 0.85, 0.1)
			else:
				timer_bar_style.bg_color = Color(0.95, 0.2, 0.15)
			if shots_submitted:
				phase_label.text = "Shots submitted — waiting for opponent..."
			else:
				var locked_count: int = shot_map.size()
				var my_side_str := "player1" if i_am_player1 else "player2"
				var side_hint: String = "push the ball past the net!" if ball_start_side == my_side_str else "return the ball!"
				phase_label.text = "Tap a disc to aim  ·  %d/3 aimed  ·  %s" % [locked_count, side_hint]
		Phase.EXECUTING, Phase.SETTLING:
			timer_bar.visible = false
			phase_label.text = ""
		Phase.POINT_SCORED:
			timer_bar.visible = false
			phase_label.text = ""
		Phase.GAME_OVER:
			timer_bar.visible = false
			phase_label.text = ""

# ── Build helpers ──

func _build_ball():
	ball = _VBall.new()
	ball.ball_texture = ball_texture
	ball.gravity_scale = 0.0
	ball.can_sleep = false
	ball.linear_damp = Constants.VB_BALL_LINEAR_DAMP
	ball.collision_layer = 1
	ball.collision_mask = 1
	var mat := PhysicsMaterial.new()
	mat.bounce = Constants.VB_BALL_BOUNCE
	mat.friction = Constants.VB_BALL_FRICTION
	ball.physics_material_override = mat
	var shape := CircleShape2D.new()
	shape.radius = Constants.VB_BALL_RADIUS
	var col := CollisionShape2D.new()
	col.shape = shape
	ball.add_child(col)
	add_child(ball)

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
	mat.bounce = 0.7
	body.physics_material_override = mat
	add_child(body)

func _build_net():
	var f: Rect2 = Constants.FIELD_RECT
	var cx: float = f.position.x + f.size.x / 2.0
	net_wall = StaticBody2D.new()
	net_wall.position = Vector2(cx, f.position.y + f.size.y / 2.0)
	net_wall.collision_layer = 2
	net_wall.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4, f.size.y)
	var col := CollisionShape2D.new()
	col.shape = shape
	net_wall.add_child(col)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.8
	net_wall.physics_material_override = mat
	add_child(net_wall)

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
		p.collision_mask = 3
		add_child(p)
		my_pills.append(p)

	for i in range(3):
		var p := Pill.new()
		p.team = "opponent"
		p.pill_index = i
		p.pill_color = opp_color
		p.pill_color_light = opp_color_light
		p.position = opp_starts[i]
		p.collision_mask = 3
		add_child(p)
		opp_pills.append(p)

func _build_hud():
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)

	score_label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.position = Vector2(vp.x / 2.0 - 200, 8)
	score_label.size = Vector2(400, 50)
	score_label.add_theme_font_size_override("font_size", 30)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	hud_layer.add_child(score_label)

	phase_label = Label.new()
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.position = Vector2(vp.x / 2.0 - 350, 38)
	phase_label.size = Vector2(700, 25)
	phase_label.add_theme_font_size_override("font_size", 16)
	phase_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	hud_layer.add_child(phase_label)

	timer_bar = ProgressBar.new()
	timer_bar.position = Vector2(vp.x / 2.0 - 300, vp.y - 35)
	timer_bar.size = Vector2(600, 16)
	timer_bar.min_value = 0.0
	timer_bar.max_value = Constants.VOLLEYBALL_AIM_TIME
	timer_bar.value = Constants.VOLLEYBALL_AIM_TIME
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
	center_msg.add_theme_font_size_override("font_size", 80)
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
