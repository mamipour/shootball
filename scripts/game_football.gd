extends Node2D

enum Phase { AIMING, EXECUTING, SETTLING, GOAL_SCORED, GAME_OVER }

class _BallBody extends RigidBody2D:
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
		var r: float = Constants.BALL_RADIUS
		draw_circle(Vector2(2, 2), r, Color(0.0, 0.0, 0.0, 0.2))
		if ball_texture != null:
			var size: float = r * 2.0
			draw_texture_rect(ball_texture, Rect2(Vector2(-r, -r), Vector2(size, size)), false)
		else:
			draw_circle(Vector2.ZERO, r, Color.WHITE)
		draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(0.3, 0.3, 0.3, 0.6), 2.0, true)
	func _process(_delta: float):
		queue_redraw()

# ── Nodes ──
var player_pills: Array = []
var ai_pills: Array = []
var ball: RigidBody2D

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

# ── Multi-shot aiming ──
var selected_pill: Pill = null
var shot_map: Dictionary = {}
var dragging: bool = false
var drag_start := Vector2.ZERO
var drag_cur := Vector2.ZERO
var aim_dir := Vector2.ZERO
var aim_pow: float = 0.0

# ── AI decisions ──
var ai_shots: Array = []
var ai_decided: bool = false

# ── Timer ──
var aim_timer: float = 0.0

# ── Settling ──
var settle_timer: float = 0.0

# ── Goal ──
var goal_timer: float = 0.0
var scorer: String = ""
var goal_this_round: bool = false

# ── Assets ──
var grass_texture: Texture2D = null
var goal_left_tex: Texture2D = null
var goal_right_tex: Texture2D = null
var ball_texture: Texture2D = null

# ── Audio ──
var stadium_music: AudioStreamPlayer
var goal_sfx: AudioStreamPlayer
var win_sfx: AudioStreamPlayer

# ═══════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	grass_texture = load("res://assets/groundGrass_mownWide_vector.svg")
	goal_left_tex = load("res://assets/goal_left.svg")
	goal_right_tex = load("res://assets/goal_right.svg")
	ball_texture = load("res://assets/Soccer_ball.svg")
	_setup_audio()
	_build_walls()
	_build_ball()
	_build_pills()
	_assign_avatars()
	_build_hud()
	_start_round()

func _setup_audio():
	stadium_music = AudioStreamPlayer.new()
	stadium_music.stream = load("res://assets/sounds/stadium.mp3")
	stadium_music.volume_db = -8.0
	stadium_music.finished.connect(func(): if stadium_music.playing == false and phase != Phase.GAME_OVER: stadium_music.play())
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
			_check_goals()
			if settle_timer > 0.5:
				phase = Phase.SETTLING
				settle_timer = 0.0
		Phase.SETTLING:
			_check_goals()
			if _all_stopped():
				settle_timer += delta
				if settle_timer >= Constants.SETTLE_GRACE_TIME:
					_end_round()
			else:
				settle_timer = 0.0
		Phase.GOAL_SCORED:
			goal_timer -= delta
			if goal_timer <= 0.0:
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
	aim_timer = Constants.FOOTBALL_AIM_TIME
	selected_pill = null
	shot_map.clear()
	dragging = false
	aim_pow = 0.0
	aim_dir = Vector2.ZERO
	ai_decided = false
	ai_shots.clear()
	settle_timer = 0.0
	goal_this_round = false
	center_msg.visible = false
	restart_label.visible = false

	for p in player_pills:
		p.is_selected = false

# ═══════════════════════════════════════════════════════════════
# AI — push the ball toward player's goal
# ═══════════════════════════════════════════════════════════════

func _ai_decide():
	ai_decided = true
	ai_shots.clear()
	var diff: int = Constants.ai_difficulty
	var f: Rect2 = Constants.FIELD_RECT
	var cy: float = f.position.y + f.size.y / 2.0
	var gh: float = Constants.GOAL_WIDTH / 2.0
	var alive_ai := _alive_pills(ai_pills)
	var alive_player := _alive_pills(player_pills)
	var ball_pos: Vector2 = ball.position

	var goal_center := Vector2(f.position.x, cy)
	var goal_targets: Array[Vector2] = [goal_center]
	if diff >= 1:
		goal_targets.append(Vector2(f.position.x, cy - gh * 0.4))
		goal_targets.append(Vector2(f.position.x, cy + gh * 0.4))

	var assigned_to_ball: bool = false

	for pill in alive_ai:
		var best_score: float = -999.0
		var best_dir := Vector2.ZERO
		var best_power: float = 0.0
		var best_action: String = ""

		# --- Phase 1: Push ball toward player's goal ---
		var to_ball: Vector2 = ball_pos - pill.position
		var ball_dist: float = to_ball.length()

		if not assigned_to_ball or diff >= 2:
			for target in goal_targets:
				var ball_to_goal: Vector2 = (target - ball_pos).normalized()
				var ideal_hit_pos: Vector2 = ball_pos - ball_to_goal * (Constants.PILL_RADIUS + Constants.BALL_RADIUS)
				var to_ideal: Vector2 = ideal_hit_pos - pill.position
				var ideal_dist: float = to_ideal.length()
				var dir: Vector2 = to_ideal.normalized()

				var score: float = 80.0
				var hit_alignment: float = dir.dot(ball_to_goal)
				score += hit_alignment * 40.0
				score -= ideal_dist / 500.0 * 20.0

				if ball_dist < 150.0:
					score += 25.0

				if diff >= 1:
					var blocked: bool = false
					for pp in alive_player:
						if _ai_is_in_path(pill.position, dir, pp.position, ideal_dist):
							blocked = true
							break
					if blocked:
						score -= 35.0
					for friendly in alive_ai:
						if friendly == pill:
							continue
						if _ai_is_in_path(pill.position, dir, friendly.position, ideal_dist):
							blocked = true
							break
					if blocked:
						score -= 25.0

				var power: float = clampf(ideal_dist * Constants.PILL_LINEAR_DAMP * 1.6, 350.0, Constants.MAX_POWER)

				if score > best_score:
					best_score = score
					best_dir = dir
					best_power = power
					best_action = "push_ball"

		# --- Phase 2: Defensive — push opponent away from our goal ---
		if diff >= 1:
			var our_goal := Vector2(f.position.x + f.size.x, cy)
			for pp in alive_player:
				var pp_dist_to_goal: float = pp.position.distance_to(our_goal)
				if pp_dist_to_goal > f.size.x * 0.5:
					continue
				var to_pp: Vector2 = pp.position - pill.position
				var pp_dist: float = to_pp.length()
				var dir: Vector2 = to_pp.normalized()

				var threat: float = 1.0 - clampf(pp_dist_to_goal / (f.size.x * 0.5), 0.0, 1.0)
				var score: float = 30.0 + threat * 40.0
				score -= pp_dist / 400.0 * 10.0

				var power: float = clampf(pp_dist * Constants.PILL_LINEAR_DAMP * 1.5, 300.0, Constants.MAX_POWER)

				if score > best_score:
					best_score = score
					best_dir = dir
					best_power = power
					best_action = "defend"

		# --- Phase 3: Reposition toward ball (hard) ---
		if diff >= 2 and best_score < 50.0:
			var behind_ball: Vector2 = ball_pos + (ball_pos - goal_center).normalized() * 120.0
			behind_ball.x = clampf(behind_ball.x, f.position.x + 40, f.position.x + f.size.x - 40)
			behind_ball.y = clampf(behind_ball.y, f.position.y + 40, f.position.y + f.size.y - 40)
			var move_dir: Vector2 = (behind_ball - pill.position).normalized()
			var move_dist: float = pill.position.distance_to(behind_ball)
			var score: float = 25.0 + clampf(move_dist / 300.0, 0.0, 1.0) * 15.0
			var power: float = clampf(move_dist * 0.6, 150.0, 500.0)

			if score > best_score:
				best_score = score
				best_dir = move_dir
				best_power = power
				best_action = "reposition"

		# --- Fallback ---
		if best_dir.length() < 0.1:
			best_dir = (ball_pos - pill.position).normalized()
			best_power = 400.0
			best_action = "fallback"

		# --- Difficulty imperfections ---
		if diff == 0:
			best_dir = best_dir.rotated(randf_range(-0.22, 0.22))
			best_power *= randf_range(0.45, 0.7)
		elif diff == 1:
			best_dir = best_dir.rotated(randf_range(-0.07, 0.07))
			best_power *= randf_range(0.85, 1.05)

		best_power = clampf(best_power, 200.0, Constants.MAX_POWER)
		ai_shots.append({"pill": pill, "dir": best_dir.normalized(), "power": best_power})

		if best_action == "push_ball":
			assigned_to_ball = true

func _ai_is_in_path(origin: Vector2, dir: Vector2, target_pos: Vector2, max_dist: float) -> bool:
	var to_target: Vector2 = target_pos - origin
	var proj: float = to_target.dot(dir.normalized())
	if proj < Constants.PILL_RADIUS or proj > max_dist:
		return false
	var closest: Vector2 = origin + dir.normalized() * proj
	return closest.distance_to(target_pos) < Constants.PILL_RADIUS * 2.5

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
		var impulse: Vector2 = shot.dir * shot.power
		pill.kick(impulse)

	for shot in ai_shots:
		var impulse: Vector2 = shot.dir * shot.power
		shot.pill.kick(impulse)

	for p in player_pills:
		p.is_selected = false
	selected_pill = null

# ═══════════════════════════════════════════════════════════════
# GOAL DETECTION
# ═══════════════════════════════════════════════════════════════

func _check_goals():
	if goal_this_round:
		return
	var f: Rect2 = Constants.FIELD_RECT
	var cy: float = f.position.y + f.size.y / 2.0
	var gh: float = Constants.GOAL_WIDTH / 2.0
	var bx: float = ball.position.x
	var by: float = ball.position.y

	if bx > f.position.x + f.size.x + 5.0 and by > cy - gh and by < cy + gh:
		goal_this_round = true
		scorer = "player"
		player_score += 1
	elif bx < f.position.x - 5.0 and by > cy - gh and by < cy + gh:
		goal_this_round = true
		scorer = "ai"
		ai_score += 1

func _all_stopped() -> bool:
	if not ball.linear_velocity.length() < Constants.SETTLE_VELOCITY_THRESHOLD:
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
	if goal_this_round:
		phase = Phase.GOAL_SCORED
		goal_timer = Constants.GOAL_DISPLAY_TIME
		center_msg.text = "GOAL!"
		center_msg.visible = true
		goal_sfx.play()
	else:
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
	var cx: float = f.position.x + f.size.x / 2.0
	var cy: float = f.position.y + f.size.y / 2.0
	_reset_ball(Vector2(cx, cy))
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
	_draw_field_lines()
	_draw_goal_pockets()
	if phase == Phase.AIMING:
		_draw_locked_arrows()
		if selected_pill != null and aim_pow > Constants.MIN_POWER:
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
			var pct: float = aim_timer / Constants.FOOTBALL_AIM_TIME
			if pct > 0.5:
				timer_bar_style.bg_color = Color(0.2, 0.9, 0.2)
			elif pct > 0.25:
				timer_bar_style.bg_color = Color(0.95, 0.85, 0.1)
			else:
				timer_bar_style.bg_color = Color(0.95, 0.2, 0.15)
			var locked_count: int = shot_map.size()
			phase_label.text = "Tap a disc to aim  ·  %d/3 aimed  ·  kick the ball into the goal!" % locked_count
		Phase.EXECUTING, Phase.SETTLING:
			timer_bar.visible = false
			phase_label.text = ""
		Phase.GOAL_SCORED:
			timer_bar.visible = false
			phase_label.text = "%s scored!" % ("You" if scorer == "player" else "AI")
		Phase.GAME_OVER:
			timer_bar.visible = false
			phase_label.text = ""

# ═══════════════════════════════════════════════════════════════
# BUILD HELPERS
# ═══════════════════════════════════════════════════════════════

func _build_ball():
	ball = _BallBody.new()
	ball.ball_texture = ball_texture
	ball.gravity_scale = 0.0
	ball.can_sleep = false
	ball.linear_damp = Constants.BALL_LINEAR_DAMP
	ball.collision_layer = 1
	ball.collision_mask = 1

	var mat := PhysicsMaterial.new()
	mat.bounce = Constants.BALL_BOUNCE
	mat.friction = Constants.BALL_FRICTION
	ball.physics_material_override = mat

	var shape := CircleShape2D.new()
	shape.radius = Constants.BALL_RADIUS
	var col := CollisionShape2D.new()
	col.shape = shape
	ball.add_child(col)

	var f: Rect2 = Constants.FIELD_RECT
	ball.position = Vector2(f.position.x + f.size.x / 2.0, f.position.y + f.size.y / 2.0)
	add_child(ball)

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

	_wall(Vector2(f.position.x + f.size.x / 2.0, f.position.y - wt / 2.0),
		Vector2(f.size.x + wt * 2, wt))
	_wall(Vector2(f.position.x + f.size.x / 2.0, f.position.y + f.size.y + wt / 2.0),
		Vector2(f.size.x + wt * 2, wt))

	_wall(Vector2(f.position.x - wt / 2.0, f.position.y + seg_top / 2.0),
		Vector2(wt, seg_top))
	_wall(Vector2(f.position.x - wt / 2.0, gb + seg_bot / 2.0),
		Vector2(wt, seg_bot))

	_wall(Vector2(rx + wt / 2.0, f.position.y + seg_top / 2.0),
		Vector2(wt, seg_top))
	_wall(Vector2(rx + wt / 2.0, gb + seg_bot / 2.0),
		Vector2(wt, seg_bot))

	_wall(Vector2(f.position.x - gd - wt / 2.0, cy),
		Vector2(wt, Constants.GOAL_WIDTH + wt * 2))
	_wall(Vector2(f.position.x - gd / 2.0, gt - wt / 2.0),
		Vector2(gd, wt))
	_wall(Vector2(f.position.x - gd / 2.0, gb + wt / 2.0),
		Vector2(gd, wt))

	_wall(Vector2(rx + gd + wt / 2.0, cy),
		Vector2(wt, Constants.GOAL_WIDTH + wt * 2))
	_wall(Vector2(rx + gd / 2.0, gt - wt / 2.0),
		Vector2(gd, wt))
	_wall(Vector2(rx + gd / 2.0, gb + wt / 2.0),
		Vector2(gd, wt))

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
	for i in range(3):
		var p := Pill.new()
		p.team = "player"
		p.pill_index = i
		p.pill_color = Constants.PLAYER_COLOR
		p.pill_color_light = Constants.PLAYER_COLOR_LIGHT
		p.position = Constants.PLAYER_START[i]
		add_child(p)
		player_pills.append(p)

	for i in range(3):
		var p := Pill.new()
		p.team = "ai"
		p.pill_index = i
		p.pill_color = Constants.AI_COLOR
		p.pill_color_light = Constants.AI_COLOR_LIGHT
		p.position = Constants.AI_START[i]
		add_child(p)
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
	timer_bar.max_value = Constants.FOOTBALL_AIM_TIME
	timer_bar.value = Constants.FOOTBALL_AIM_TIME
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
