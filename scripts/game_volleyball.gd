extends Node2D

enum Phase { AIMING, EXECUTING, SETTLING, POINT_SCORED, GAME_OVER }

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
var player_pills: Array = []
var ai_pills: Array = []
var ball: RigidBody2D
var net_wall: StaticBody2D

# ── HUD ──
var hud_layer: CanvasLayer
var score_label: Label
var timer_bar: ProgressBar
var timer_bar_style: StyleBoxFlat
var phase_label: Label
var center_msg: Label
var restart_label: Label
var quit_btn: Button
var quit_confirm: Panel

# ── State ──
var phase: Phase = Phase.AIMING
var player_score: int = 0
var ai_score: int = 0
var round_num: int = 0
var ball_side: String = "player"
var ball_start_side: String = "player"

# ── Multi-shot aiming ──
var selected_pill: Pill = null
var shot_map: Dictionary = {}
var dragging: bool = false
var drag_start := Vector2.ZERO
var drag_cur := Vector2.ZERO
var aim_dir := Vector2.ZERO
var aim_pow: float = 0.0

# ── AI ──
var ai_shots: Array = []
var ai_decided: bool = false

# ── Timer ──
var aim_timer: float = 0.0

# ── Settling ──
var settle_timer: float = 0.0

# ── Point ──
var point_timer: float = 0.0
var scorer: String = ""

# ── Assets ──
var sand_texture: Texture2D = null
var ball_texture: Texture2D = null

# ── Audio ──
var stadium_music: AudioStreamPlayer
var point_sfx: AudioStreamPlayer
var win_sfx: AudioStreamPlayer

# ═══════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	sand_texture = load("res://assets/groundSand_wide_vector.svg")
	ball_texture = load("res://assets/volleyball.svg")
	_setup_audio()
	_build_walls()
	_build_net()
	_build_ball()
	_build_pills()
	_assign_avatars()
	_build_hud()
	ball_side = "player" if randi() % 2 == 0 else "ai"
	_reset_all()
	_start_round()

func _setup_audio():
	stadium_music = AudioStreamPlayer.new()
	stadium_music.stream = load("res://assets/sounds/stadium.mp3")
	stadium_music.volume_db = -8.0
	stadium_music.finished.connect(func(): if stadium_music.playing == false and phase != Phase.GAME_OVER: stadium_music.play())
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

func _pick_random_ai_avatar():
	var count := Constants.AVATAR_COUNT
	var ai_idx := randi() % count
	while ai_idx == Constants.player_avatar_idx:
		ai_idx = randi() % count
	Constants.ai_avatar_idx = ai_idx

func _assign_avatars():
	_pick_random_ai_avatar()
	var p_atlas := _load_avatar(Constants.player_avatar_idx)
	var a_atlas := _load_avatar(Constants.ai_avatar_idx)
	for pill in player_pills:
		pill.avatar_texture = p_atlas
	for pill in ai_pills:
		pill.avatar_texture = a_atlas

func _process(delta: float):
	if get_tree().paused:
		return
	match phase:
		Phase.AIMING:
			aim_timer -= delta
			if not ai_decided and aim_timer <= 3.0:
				_ai_decide()
			if aim_timer <= 0.0:
				_fire_all_shots()
		Phase.EXECUTING:
			settle_timer += delta
			if settle_timer > 0.5:
				phase = Phase.SETTLING
				settle_timer = 0.0
		Phase.SETTLING:
			if _all_stopped():
				settle_timer += delta
				if settle_timer >= Constants.SETTLE_GRACE_TIME:
					_end_round()
			else:
				settle_timer = 0.0
		Phase.POINT_SCORED:
			point_timer -= delta
			if point_timer <= 0.0:
				if player_score >= Constants.WIN_SCORE or ai_score >= Constants.WIN_SCORE:
					_show_game_over()
				else:
					_reset_all()
					_start_round()
		Phase.GAME_OVER:
			pass

	_update_hud()
	queue_redraw()

# ═══════════════════════════════════════════════════════════════
# ROUND MANAGEMENT
# ═══════════════════════════════════════════════════════════════

func _start_round():
	round_num += 1
	phase = Phase.AIMING
	aim_timer = Constants.VOLLEYBALL_AIM_TIME
	selected_pill = null
	shot_map.clear()
	dragging = false
	aim_pow = 0.0
	aim_dir = Vector2.ZERO
	ai_decided = false
	ai_shots.clear()
	settle_timer = 0.0
	center_msg.visible = false
	restart_label.visible = false
	ball_start_side = ball_side

	for p in player_pills:
		p.is_selected = false

# ═══════════════════════════════════════════════════════════════
# AI
# ═══════════════════════════════════════════════════════════════

func _ai_decide():
	ai_decided = true
	ai_shots.clear()
	var diff: int = Constants.ai_difficulty
	var f: Rect2 = Constants.FIELD_RECT
	var cx: float = f.position.x + f.size.x / 2.0
	var cy: float = f.position.y + f.size.y / 2.0
	var alive_ai := _alive_pills(ai_pills)
	var ball_pos: Vector2 = ball.position
	var ball_on_ai_side: bool = ball_pos.x > cx

	if ball_on_ai_side:
		_ai_attack(alive_ai, ball_pos, f, cx, cy, diff)
	else:
		_ai_defend(alive_ai, ball_pos, f, cx, cy, diff)

func _ai_attack(alive_ai: Array, ball_pos: Vector2, f: Rect2, cx: float, cy: float, diff: int):
	# Sort pills by how directly they are BEHIND the ball (rightward = better push left)
	# A pill directly to the right of the ball has the best push angle
	var sorted_pills: Array = alive_ai.duplicate()
	sorted_pills.sort_custom(func(a, b):
		var dir_a: Vector2 = (ball_pos - a.position).normalized()
		var dir_b: Vector2 = (ball_pos - b.position).normalized()
		# More negative x = better horizontal push
		return dir_a.x < dir_b.x
	)

	# How many pills attack vs reposition
	var num_attackers: int = 2
	if diff >= 2:
		num_attackers = 3

	for idx in range(sorted_pills.size()):
		var pill: Pill = sorted_pills[idx]

		if idx < num_attackers:
			_ai_shoot_at_ball(pill, ball_pos, f, cx, cy, diff)
		else:
			_ai_reposition_defense(pill, ball_pos, f, cx, cy, diff)

func _ai_shoot_at_ball(pill: Pill, ball_pos: Vector2, f: Rect2, cx: float, cy: float, diff: int):
	# Simple and direct: aim at the ball, high power
	var aim_dir: Vector2 = (ball_pos - pill.position).normalized()
	var dist: float = pill.position.distance_to(ball_pos)

	# High power — needs to push ball across the entire half of the field
	var power: float = clampf(dist * 4.0 + 700.0, 900.0, Constants.MAX_POWER)

	# Difficulty imperfections
	if diff == 0:
		aim_dir = aim_dir.rotated(randf_range(-0.10, 0.10))
		power *= randf_range(0.75, 0.95)
	elif diff == 1:
		aim_dir = aim_dir.rotated(randf_range(-0.04, 0.04))
		power *= randf_range(0.92, 1.05)

	power = clampf(power, 800.0, Constants.MAX_POWER)
	ai_shots.append({"pill": pill, "dir": aim_dir.normalized(), "power": power})

func _ai_reposition_defense(pill: Pill, ball_pos: Vector2, f: Rect2, cx: float, cy: float, diff: int):
	var guard_y: float = clampf(cy + randf_range(-120, 120), f.position.y + 50, f.position.y + f.size.y - 50)
	var guard_pos := Vector2(cx + 60, guard_y)
	var move_dir: Vector2 = (guard_pos - pill.position).normalized()
	var move_dist: float = pill.position.distance_to(guard_pos)
	var power: float = clampf(move_dist * 0.7, 100.0, 400.0)
	ai_shots.append({"pill": pill, "dir": move_dir.normalized(), "power": power})

func _ai_defend(alive_ai: Array, ball_pos: Vector2, f: Rect2, cx: float, cy: float, diff: int):
	# Ball is on player's side — spread pills defensively near the net
	var guard_positions: Array[Vector2] = [
		Vector2(cx + 50, cy),
		Vector2(cx + 70, f.position.y + f.size.y * 0.25),
		Vector2(cx + 70, f.position.y + f.size.y * 0.75),
	]

	if diff >= 1:
		guard_positions[0].y = clampf(ball_pos.y, f.position.y + 50, f.position.y + f.size.y - 50)

	for idx in range(alive_ai.size()):
		var pill: Pill = alive_ai[idx]
		var target: Vector2 = guard_positions[idx % guard_positions.size()]
		var move_dir: Vector2 = (target - pill.position).normalized()
		var move_dist: float = pill.position.distance_to(target)

		if move_dist < 20.0:
			ai_shots.append({"pill": pill, "dir": Vector2(-1, 0), "power": 100.0})
			continue

		var power: float = clampf(move_dist * 0.8, 100.0, 500.0)
		ai_shots.append({"pill": pill, "dir": move_dir.normalized(), "power": power})

# ═══════════════════════════════════════════════════════════════
# FIRING
# ═══════════════════════════════════════════════════════════════

func _fire_all_shots():
	phase = Phase.EXECUTING
	settle_timer = 0.0

	if not ai_decided:
		_ai_decide()

	for pill in shot_map:
		var shot: Dictionary = shot_map[pill]
		pill.kick(shot.dir * shot.power)

	for shot in ai_shots:
		shot.pill.kick(shot.dir * shot.power)

	for p in player_pills:
		p.is_selected = false
	selected_pill = null

# ═══════════════════════════════════════════════════════════════
# SCORING — ball on your side = you lose the point
# ═══════════════════════════════════════════════════════════════

func _check_ball_side() -> String:
	var f: Rect2 = Constants.FIELD_RECT
	var cx: float = f.position.x + f.size.x / 2.0
	if ball.position.x < cx:
		return "player"
	else:
		return "ai"

func _all_stopped() -> bool:
	if ball.linear_velocity.length() >= Constants.SETTLE_VELOCITY_THRESHOLD:
		return false
	for pill in player_pills + ai_pills:
		if not pill.is_stopped():
			return false
	return true

func _alive_pills(pills: Array) -> Array:
	var result: Array = []
	for p in pills:
		if p.visible:
			result.append(p)
	return result

func _end_round():
	var current_side: String = _check_ball_side()

	if current_side == ball_start_side:
		# Ball stayed on same side → that side failed → opponent scores
		if current_side == "player":
			scorer = "ai"
			ai_score += 1
			ball_side = "ai"
		else:
			scorer = "player"
			player_score += 1
			ball_side = "player"
		phase = Phase.POINT_SCORED
		point_timer = Constants.GOAL_DISPLAY_TIME
		center_msg.text = "%s scores!" % ("You" if scorer == "player" else "AI")
		center_msg.visible = true
		point_sfx.play()
	else:
		# Ball crossed the net — rally continues, no score, no reset
		ball_side = current_side
		_start_round()

func _show_game_over():
	phase = Phase.GAME_OVER
	center_msg.text = "YOU WIN!" if player_score >= Constants.WIN_SCORE else "AI WINS!"
	center_msg.visible = true
	restart_label.visible = true
	stadium_music.stop()
	win_sfx.play()

func _reset_all():
	var f: Rect2 = Constants.FIELD_RECT
	var cy: float = f.position.y + f.size.y / 2.0
	var ball_x: float
	if ball_side == "player":
		ball_x = f.position.x + f.size.x * 0.25
	else:
		ball_x = f.position.x + f.size.x * 0.75
	_reset_ball(Vector2(ball_x, cy))
	for i in range(3):
		player_pills[i].reset_to(Constants.PLAYER_START[i])
	for i in range(3):
		ai_pills[i].reset_to(Constants.AI_START[i])

func _reset_ball(pos: Vector2):
	ball.reset_to(pos)

# ═══════════════════════════════════════════════════════════════
# INPUT
# ═══════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if quit_confirm.visible:
			_on_quit_cancel()
		else:
			_on_quit_pressed()
		return

	if phase == Phase.GAME_OVER:
		if _is_tap(event):
			_restart_game()
		return

	if phase != Phase.AIMING:
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

func _is_tap(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton:
		return ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT
	if ev is InputEventScreenTouch:
		return ev.pressed
	return false

func _on_press(pos: Vector2):
	var alive := _alive_pills(player_pills)
	var closest_pill: Pill = null
	var closest_dist: float = Constants.PILL_RADIUS * 3.0
	for pill in alive:
		var dist: float = pill.position.distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_pill = pill
	if closest_pill != null:
		for p in player_pills:
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

func _restart_game():
	player_score = 0
	ai_score = 0
	round_num = 0
	ball_side = "player" if randi() % 2 == 0 else "ai"
	_reset_all()
	_start_round()
	if not stadium_music.playing:
		stadium_music.play()

# ═══════════════════════════════════════════════════════════════
# DRAWING
# ═══════════════════════════════════════════════════════════════

func _draw():
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.06, 0.06, 0.10))
	_draw_field()
	_draw_net_visual()
	if phase == Phase.AIMING:
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

# ═══════════════════════════════════════════════════════════════
# HUD
# ═══════════════════════════════════════════════════════════════

func _update_hud():
	score_label.text = "YOU  %d  –  %d  AI" % [player_score, ai_score]

	match phase:
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
			var locked_count: int = shot_map.size()
			var side_hint: String = "push the ball past the net!" if ball_start_side == "player" else "return the ball!"
			phase_label.text = "Tap a disc to aim  ·  %d/3 aimed  ·  %s" % [locked_count, side_hint]
		Phase.EXECUTING, Phase.SETTLING:
			timer_bar.visible = false
			phase_label.text = ""
		Phase.POINT_SCORED:
			timer_bar.visible = false
			phase_label.text = "%s scored!" % ("You" if scorer == "player" else "AI")
		Phase.GAME_OVER:
			timer_bar.visible = false
			phase_label.text = ""

# ═══════════════════════════════════════════════════════════════
# BUILD HELPERS
# ═══════════════════════════════════════════════════════════════

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
	_wall(Vector2(f.position.x + f.size.x / 2.0, f.position.y - wt / 2.0),
		Vector2(f.size.x + wt * 2, wt))
	_wall(Vector2(f.position.x + f.size.x / 2.0, f.position.y + f.size.y + wt / 2.0),
		Vector2(f.size.x + wt * 2, wt))
	_wall(Vector2(f.position.x - wt / 2.0, f.position.y + f.size.y / 2.0),
		Vector2(wt, f.size.y + wt * 2))
	_wall(Vector2(f.position.x + f.size.x + wt / 2.0, f.position.y + f.size.y / 2.0),
		Vector2(wt, f.size.y + wt * 2))

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
	for i in range(3):
		var p := Pill.new()
		p.team = "player"
		p.pill_index = i
		p.pill_color = Constants.PLAYER_COLOR
		p.pill_color_light = Constants.PLAYER_COLOR_LIGHT
		p.position = Constants.PLAYER_START[i]
		add_child(p)
		p.collision_mask = 3
		player_pills.append(p)

	for i in range(3):
		var p := Pill.new()
		p.team = "ai"
		p.pill_index = i
		p.pill_color = Constants.AI_COLOR
		p.pill_color_light = Constants.AI_COLOR_LIGHT
		p.position = Constants.AI_START[i]
		add_child(p)
		p.collision_mask = 3
		ai_pills.append(p)

func _build_hud():
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)

	score_label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.position = Vector2(vp.x / 2.0 - 200, 8 + Constants.safe_top)
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

	restart_label = Label.new()
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.position = Vector2(vp.x / 2.0 - 250, vp.y / 2.0 + 70)
	restart_label.size = Vector2(500, 30)
	restart_label.add_theme_font_size_override("font_size", 20)
	restart_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	restart_label.text = "Tap anywhere to play again  ·  ESC for menu"
	restart_label.visible = false
	hud_layer.add_child(restart_label)

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
	msg.text = "Return to main menu?"
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
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_quit_cancel():
	quit_confirm.visible = false
	get_tree().paused = false
