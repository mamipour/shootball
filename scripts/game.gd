extends Node2D

enum Phase { AIMING, EXECUTING, SETTLING, GOAL_SCORED, GAME_OVER }

# ── Nodes ──
var player_pills: Array = []
var ai_pills: Array = []

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

# ── Aiming (player) ──
var sel_idx: int = -1
var dragging: bool = false
var drag_start := Vector2.ZERO
var drag_cur := Vector2.ZERO
var aim_dir := Vector2.ZERO
var aim_pow: float = 0.0
var aim_valid: bool = false
var aim_locked: bool = false

# ── Timer ──
var aim_timer: float = 0.0

# ── AI decision (stored as plain vars, not Dictionary) ──
var ai_decided: bool = false
var ai_shot_idx: int = -1
var ai_shot_dir := Vector2.ZERO
var ai_shot_power: float = 0.0

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
var scorer: String = ""
var goal_this_round: bool = false

# ═══════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	grass_texture = load("res://assets/groundGrass_mownWide_vector.svg")
	goal_left_tex = load("res://assets/goal_left.svg")
	goal_right_tex = load("res://assets/goal_right.svg")
	_setup_audio()
	_build_walls()
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
	var path := Constants.AVATAR_DIR + "avatar_%02d.png" % idx
	return load(path)

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
			if not ai_decided and aim_timer <= 2.0:
				_ai_decide()
			if aim_timer <= 0.0:
				_fire_shots()
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
					_reset_pills()
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
	aim_timer = Constants.AIM_TIME
	sel_idx = -1
	dragging = false
	aim_locked = false
	aim_valid = false
	aim_pow = 0.0
	ai_decided = false
	ai_shot_idx = -1
	ai_shot_dir = Vector2.ZERO
	ai_shot_power = 0.0
	goal_this_round = false
	settle_timer = 0.0
	center_msg.visible = false
	restart_label.visible = false
	for p in player_pills:
		p.is_selected = false

# ═══════════════════════════════════════════════════════════════
# AI (smart multi-strategy)
# ═══════════════════════════════════════════════════════════════

func _ai_is_path_blocked(origin: Vector2, dir: Vector2, max_dist: float) -> bool:
	var d: Vector2 = dir.normalized()
	var r_buf: float = Constants.PILL_RADIUS * 2.2
	for pill in player_pills:
		var to_pill: Vector2 = pill.position - origin
		var proj: float = to_pill.dot(d)
		if proj < Constants.PILL_RADIUS or proj > max_dist:
			continue
		var closest: Vector2 = origin + d * proj
		if closest.distance_to(pill.position) < r_buf:
			return true
	return false

func _ai_find_gate_shot(shooter: Vector2, gate_a: Vector2, gate_b: Vector2, target: Vector2) -> Array:
	var to_target: Vector2 = (target - shooter).normalized()
	if _ray_hits_segment(shooter, to_target, gate_a, gate_b):
		return [true, to_target]
	for step in range(1, 40):
		for sign_v in [-1, 1]:
			var dir: Vector2 = to_target.rotated(sign_v * step * 0.015)
			if _ray_hits_segment(shooter, dir, gate_a, gate_b):
				return [true, dir]
	return [false, Vector2.ZERO]

func _ai_gate_quality(shooter: Vector2, dir: Vector2, gate_a: Vector2, gate_b: Vector2) -> float:
	var d: Vector2 = dir.normalized()
	var ab: Vector2 = gate_b - gate_a
	var denom: float = d.x * ab.y - d.y * ab.x
	if absf(denom) < 0.001:
		return 0.0
	var oa: Vector2 = gate_a - shooter
	var s: float = (oa.x * d.y - oa.y * d.x) / denom
	return maxf(0.0, 1.0 - absf(s - 0.5) * 2.0)

func _ai_calc_power(origin: Vector2, target: Vector2) -> float:
	var dist: float = origin.distance_to(target)
	var power: float = dist * Constants.PILL_LINEAR_DAMP * 1.5
	return clampf(power, 350.0, Constants.MAX_POWER)

func _ai_decide():
	var diff: int = Constants.ai_difficulty
	var f: Rect2 = Constants.FIELD_RECT
	var cy: float = f.position.y + f.size.y / 2.0
	var gh: float = Constants.GOAL_WIDTH / 2.0

	# Difficulty tuning: more targets = smarter shot selection
	var goal_targets: Array[Vector2] = [Vector2(f.position.x, cy)]
	if diff >= 1:
		goal_targets.append(Vector2(f.position.x, cy - gh * 0.5))
		goal_targets.append(Vector2(f.position.x, cy + gh * 0.5))
	if diff >= 2:
		goal_targets.append(Vector2(f.position.x, cy - gh * 0.3))
		goal_targets.append(Vector2(f.position.x, cy + gh * 0.3))

	var best_score: float = -999.0
	var best_idx: int = -1
	var best_dir: Vector2 = Vector2.ZERO
	var best_power: float = 0.0

	# --- Phase 1: goal shots ---
	for i in range(3):
		var shooter: Vector2 = ai_pills[i].position
		var gate_a: Vector2 = ai_pills[(i + 1) % 3].position
		var gate_b: Vector2 = ai_pills[(i + 2) % 3].position

		for target in goal_targets:
			var shot: Array = _ai_find_gate_shot(shooter, gate_a, gate_b, target)
			if not shot[0]:
				continue

			var dir: Vector2 = shot[1]
			var dist: float = shooter.distance_to(target)
			var power: float = _ai_calc_power(shooter, target)
			var score: float = 100.0

			score += _ai_gate_quality(shooter, dir, gate_a, gate_b) * 25.0

			if diff >= 1 and not _ai_is_path_blocked(shooter, dir, dist):
				score += 50.0
			elif diff >= 1:
				score -= 30.0

			score += maxf(0.0, (800.0 - dist) / 800.0) * 15.0

			if score > best_score:
				best_score = score
				best_idx = i
				best_dir = dir
				best_power = power

	# --- Phase 2: disruption (normal + hard only) ---
	if diff >= 1 and best_score < 80.0:
		var ai_goal_x: float = f.position.x + f.size.x
		for i in range(3):
			var shooter: Vector2 = ai_pills[i].position
			var gate_a: Vector2 = ai_pills[(i + 1) % 3].position
			var gate_b: Vector2 = ai_pills[(i + 2) % 3].position

			for pp in player_pills:
				var pp_pos: Vector2 = pp.position
				var threat: float = 1.0 - clampf((ai_goal_x - pp_pos.x) / f.size.x, 0.0, 1.0)
				if threat < 0.3:
					continue

				var shot: Array = _ai_find_gate_shot(shooter, gate_a, gate_b, pp_pos)
				if not shot[0]:
					continue

				var score: float = 40.0 + threat * 40.0
				var power: float = _ai_calc_power(shooter, pp_pos)

				if score > best_score:
					best_score = score
					best_idx = i
					best_dir = shot[1]
					best_power = power

	# --- Phase 3: repositioning (hard only) ---
	if diff >= 2 and best_score < 40.0:
		var ideal_x: float = f.position.x + f.size.x * 0.35

		for i in range(3):
			var shooter: Vector2 = ai_pills[i].position
			var gate_a: Vector2 = ai_pills[(i + 1) % 3].position
			var gate_b: Vector2 = ai_pills[(i + 2) % 3].position

			var target_y: float = cy - 80.0 if shooter.y < cy else cy + 80.0
			var target := Vector2(ideal_x, target_y)
			var dir: Vector2 = (target - shooter).normalized()
			var through_gate: bool = _ray_hits_segment(shooter, dir, gate_a, gate_b)

			var score: float = 20.0
			if through_gate:
				score += 15.0

			var dist_to_ideal: float = shooter.distance_to(target)
			score += clampf(dist_to_ideal / 400.0, 0.0, 1.0) * 10.0

			var power: float = clampf(dist_to_ideal * 0.6, 150.0, 500.0)

			if score > best_score:
				best_score = score
				best_idx = i
				best_dir = dir
				best_power = power

	# --- Fallback (no gate shot found at all) ---
	if best_idx < 0:
		best_idx = 2
		best_dir = Vector2(-1, 0)
		best_power = 400.0

	# --- Apply difficulty imperfections ---
	if diff == 0:
		# Easy: significant random angle wobble and underpowered shots
		best_dir = best_dir.rotated(randf_range(-0.18, 0.18))
		best_power *= randf_range(0.5, 0.75)
	elif diff == 1:
		# Normal: slight angle wobble and minor power variance
		best_dir = best_dir.rotated(randf_range(-0.06, 0.06))
		best_power *= randf_range(0.85, 1.05)

	best_power = clampf(best_power, 150.0, Constants.MAX_POWER)

	ai_shot_idx = best_idx
	ai_shot_dir = best_dir.normalized()
	ai_shot_power = best_power
	ai_decided = true

func _fire_shots():
	phase = Phase.EXECUTING
	settle_timer = 0.0

	if aim_locked and aim_valid and sel_idx >= 0:
		var impulse: Vector2 = aim_dir * aim_pow
		player_pills[sel_idx].kick(impulse)

	if ai_decided and ai_shot_idx >= 0:
		var impulse: Vector2 = ai_shot_dir * ai_shot_power
		ai_pills[ai_shot_idx].kick(impulse)

	for p in player_pills:
		p.is_selected = false
	sel_idx = -1

func _check_goals():
	if goal_this_round:
		return
	var f: Rect2 = Constants.FIELD_RECT
	var cy: float = f.position.y + f.size.y / 2.0
	var gh: float = Constants.GOAL_WIDTH / 2.0

	for pill in player_pills + ai_pills:
		var px: float = pill.position.x
		var py: float = pill.position.y
		if px > f.position.x + f.size.x + 5.0 and py > cy - gh and py < cy + gh:
			goal_this_round = true
			scorer = "player"
			player_score += 1
			return
		if px < f.position.x - 5.0 and py > cy - gh and py < cy + gh:
			goal_this_round = true
			scorer = "ai"
			ai_score += 1
			return

func _all_stopped() -> bool:
	for pill in player_pills + ai_pills:
		if not pill.is_stopped():
			return false
	return true

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

func _reset_pills():
	for i in range(3):
		player_pills[i].reset_to(Constants.PLAYER_START[i])
	for i in range(3):
		ai_pills[i].reset_to(Constants.AI_START[i])

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
			player_score = 0
			ai_score = 0
			round_num = 0
			_reset_pills()
			_start_round()
			if not stadium_music.playing:
				stadium_music.play()
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
	for i in range(player_pills.size()):
		if player_pills[i].position.distance_to(pos) < Constants.PILL_RADIUS * 2.5:
			for p in player_pills:
				p.is_selected = false
			sel_idx = i
			player_pills[i].is_selected = true
			dragging = true
			drag_start = pos
			drag_cur = pos
			aim_locked = false
			return

func _on_drag(pos: Vector2):
	if not dragging or sel_idx < 0:
		return
	drag_cur = pos
	var pill_pos: Vector2 = player_pills[sel_idx].position
	var pull: Vector2 = drag_cur - pill_pos
	if pull.length() < 5.0:
		aim_pow = 0.0
		return
	aim_dir = -pull.normalized()
	aim_pow = clampf(pull.length() * Constants.POWER_SCALE, 0, Constants.MAX_POWER)
	var ga: Vector2 = player_pills[(sel_idx + 1) % 3].position
	var gb: Vector2 = player_pills[(sel_idx + 2) % 3].position
	aim_valid = _ray_hits_segment(pill_pos, aim_dir, ga, gb)

func _on_release():
	if dragging and sel_idx >= 0 and aim_pow > Constants.MIN_POWER and aim_valid:
		aim_locked = true
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
	if phase == Phase.AIMING and sel_idx >= 0:
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
	var ga: Vector2 = player_pills[(sel_idx + 1) % 3].position
	var gb: Vector2 = player_pills[(sel_idx + 2) % 3].position
	draw_line(ga, gb, Constants.GATE_COLOR, 3.0)
	draw_circle(ga, 7, Constants.GATE_COLOR)
	draw_circle(gb, 7, Constants.GATE_COLOR)

func _draw_aim_arrow():
	var pill_pos: Vector2 = player_pills[sel_idx].position
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

# ═══════════════════════════════════════════════════════════════
# HUD
# ═══════════════════════════════════════════════════════════════

func _update_hud():
	score_label.text = "YOU  %d  –  %d  AI" % [player_score, ai_score]

	match phase:
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
			if aim_locked:
				phase_label.text = "Aim locked — waiting for timer …"
			elif sel_idx >= 0:
				phase_label.text = "Drag away from pill to aim  ·  release to lock"
			else:
				phase_label.text = "Tap one of your blue pills to select"
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

	score_label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.position = Vector2(440, 8 + Constants.safe_top)
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

	restart_label = Label.new()
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.position = Vector2(390, 480)
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
