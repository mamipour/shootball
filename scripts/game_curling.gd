extends Node2D

enum Phase { PLAYER_AIM, AI_THINKING, EXECUTING, SETTLING, END_SCORED, GAME_OVER }

# ── Nodes ──
var player_pills: Array = []
var ai_pills: Array = []

# ── HUD ──
var hud_layer: CanvasLayer
var score_label: Label
var timer_bar: ProgressBar
var timer_bar_style: StyleBoxFlat
var phase_label: Label
var turn_indicator: Label
var center_msg: Label
var restart_label: Label
var quit_btn: Button
var quit_confirm: Panel

# ── State ──
var phase: Phase = Phase.PLAYER_AIM
var player_score: int = 0
var ai_score: int = 0
var end_num: int = 0

# ── Turn tracking ──
var first_team: String = "player"
var shots_done: int = 0
var player_used: Array[int] = []
var ai_used: Array[int] = []

# ── Single-shot aiming (player) ──
var selected_pill: Pill = null
var dragging: bool = false
var drag_cur := Vector2.ZERO
var aim_dir := Vector2.ZERO
var aim_pow: float = 0.0

# ── AI ──
var ai_target_pill: Pill = null
var ai_aim_dir := Vector2.ZERO
var ai_aim_power: float = 0.0

# ── Timers ──
var aim_timer: float = 0.0
var ai_think_timer: float = 0.0
var settle_timer: float = 0.0
var end_timer: float = 0.0
var end_msg: String = ""

# ── Assets ──
var ice_texture: Texture2D = null

# ── Audio ──
var music: AudioStreamPlayer
var score_sfx: AudioStreamPlayer
var win_sfx: AudioStreamPlayer

const AI_THINK_TIME := 1.2

# ═══════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	ice_texture = load("res://assets/groundIce_wide_vector.svg")
	_setup_audio()
	_build_walls()
	_build_pills()
	_assign_avatars()
	_build_hud()
	_start_end()

func _setup_audio():
	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/sounds/stadium.mp3")
	music.volume_db = -10.0
	music.finished.connect(func(): if music.playing == false and phase != Phase.GAME_OVER: music.play())
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
		Phase.PLAYER_AIM:
			aim_timer -= delta
			if aim_timer <= 0.0:
				_player_timeout()

		Phase.AI_THINKING:
			ai_think_timer -= delta
			if ai_think_timer <= 0.0:
				_ai_fire()

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
				if player_score >= Constants.CURLING_WIN_SCORE or ai_score >= Constants.CURLING_WIN_SCORE:
					_show_game_over()
				else:
					_reset_all()
					_start_end()

		Phase.GAME_OVER:
			pass

	_update_hud()
	queue_redraw()

# ═══════════════════════════════════════════════════════════════
# TURN MANAGEMENT
# ═══════════════════════════════════════════════════════════════

func _current_team() -> String:
	if shots_done % 2 == 0:
		return first_team
	return "ai" if first_team == "player" else "player"

func _start_end():
	end_num += 1
	shots_done = 0
	player_used.clear()
	ai_used.clear()
	settle_timer = 0.0
	center_msg.visible = false
	restart_label.visible = false
	_clear_aim()
	_begin_turn()

func _begin_turn():
	settle_timer = 0.0
	_clear_aim()
	var team: String = _current_team()
	if team == "player":
		phase = Phase.PLAYER_AIM
		aim_timer = Constants.CURLING_AIM_TIME
	else:
		phase = Phase.AI_THINKING
		ai_think_timer = AI_THINK_TIME
		_ai_decide_single()

func _clear_aim():
	if selected_pill != null:
		selected_pill.is_selected = false
	selected_pill = null
	dragging = false
	aim_dir = Vector2.ZERO
	aim_pow = 0.0
	ai_target_pill = null

func _on_shot_settled():
	shots_done += 1
	if shots_done >= 6:
		_score_end()
	else:
		_begin_turn()

func _house_center() -> Vector2:
	var f: Rect2 = Constants.FIELD_RECT
	return Vector2(f.position.x + f.size.x / 2.0, f.position.y + f.size.y / 2.0)

# ═══════════════════════════════════════════════════════════════
# PLAYER SHOOTING
# ═══════════════════════════════════════════════════════════════

func _player_fire():
	if selected_pill == null or aim_pow < Constants.MIN_POWER:
		_player_timeout()
		return
	var pill_idx: int = player_pills.find(selected_pill)
	player_used.append(pill_idx)
	selected_pill.kick(aim_dir * aim_pow)
	selected_pill.is_selected = false
	selected_pill = null
	phase = Phase.EXECUTING
	settle_timer = 0.0

func _player_timeout():
	# No shot — use the first available pill and waste the turn
	var available := _player_available()
	if available.is_empty():
		shots_done += 1
		if shots_done >= 6:
			_score_end()
		else:
			_begin_turn()
		return
	var pill: Pill = available[0]
	var pill_idx: int = player_pills.find(pill)
	player_used.append(pill_idx)
	if selected_pill != null:
		selected_pill.is_selected = false
	selected_pill = null
	# Wasted turn — move on after brief settle
	phase = Phase.EXECUTING
	settle_timer = 0.0

func _player_available() -> Array:
	var result: Array = []
	for i in range(player_pills.size()):
		if i not in player_used:
			result.append(player_pills[i])
	return result

# ═══════════════════════════════════════════════════════════════
# AI
# ═══════════════════════════════════════════════════════════════

func _ai_available() -> Array:
	var result: Array = []
	for i in range(ai_pills.size()):
		if i not in ai_used:
			result.append(ai_pills[i])
	return result

func _ai_decide_single():
	var diff: int = Constants.ai_difficulty
	var center: Vector2 = _house_center()
	var available := _ai_available()
	if available.is_empty():
		return

	var best_pill: Pill = null
	var best_dir := Vector2.ZERO
	var best_power: float = 0.0
	var best_score: float = -9999.0

	var is_last_shot: bool = (shots_done == 5)

	for pill in available:
		var pill_dir := Vector2.ZERO
		var pill_power: float = 0.0
		var pill_score: float = 0.0

		# Strategy 1: aim for the button
		var to_center: Vector2 = center - pill.position
		var center_dist: float = to_center.length()
		var center_dir: Vector2 = to_center.normalized()

		var jitter := Vector2.ZERO
		if diff < 2:
			jitter = Vector2(randf_range(-20, 20), randf_range(-20, 20))
		var target: Vector2 = center + jitter
		var to_target: Vector2 = target - pill.position
		var target_dist: float = to_target.length()
		var target_dir: Vector2 = to_target.normalized()
		var power: float = clampf(target_dist * Constants.CURLING_PILL_DAMP * 1.8, 300.0, Constants.MAX_POWER)

		var score: float = 70.0
		score += (1.0 - clampf(center_dist / 500.0, 0.0, 1.0)) * 15.0
		if is_last_shot:
			score += 20.0

		var s1_dir := target_dir
		var s1_power := power
		var s1_score := score

		# Strategy 2: knock closest player pill out of house
		var knock_dir := Vector2.ZERO
		var knock_power_val: float = 0.0
		var knock_score: float = -999.0

		if diff >= 1:
			var closest_player_in_house: Pill = null
			var closest_player_dist: float = 9999.0
			for pp in player_pills:
				var pd: float = pp.position.distance_to(center)
				if pd <= Constants.HOUSE_RADIUS_OUTER and pd < closest_player_dist:
					closest_player_dist = pd
					closest_player_in_house = pp

			if closest_player_in_house != null:
				var to_pp: Vector2 = closest_player_in_house.position - pill.position
				var pp_dist_from_pill: float = to_pp.length()
				knock_dir = to_pp.normalized()
				knock_power_val = clampf(pp_dist_from_pill * Constants.CURLING_PILL_DAMP * 2.5, 500.0, Constants.MAX_POWER)

				knock_score = 55.0
				knock_score += (1.0 - clampf(closest_player_dist / Constants.HOUSE_RADIUS_OUTER, 0.0, 1.0)) * 45.0
				if diff >= 2 and closest_player_dist < Constants.HOUSE_RADIUS_INNER:
					knock_score += 25.0

				# Prefer knocking if player is closer to center than any AI pill
				var closest_ai_to_center: float = 9999.0
				for ap in ai_pills:
					var ad: float = ap.position.distance_to(center)
					if ad < closest_ai_to_center:
						closest_ai_to_center = ad
				if closest_player_dist < closest_ai_to_center:
					knock_score += 30.0

		# Strategy 3: guard (place in front of an AI pill near center)
		var guard_dir := Vector2.ZERO
		var guard_power_val: float = 0.0
		var guard_score: float = -999.0

		if diff >= 2 and not is_last_shot:
			var best_ai_in_house: Pill = null
			var best_ai_dist: float = 9999.0
			for ap in ai_pills:
				var ad: float = ap.position.distance_to(center)
				if ad <= Constants.HOUSE_RADIUS_MID and ad < best_ai_dist:
					best_ai_dist = ad
					best_ai_in_house = ap

			if best_ai_in_house != null and pill != best_ai_in_house:
				# Place between center and the closest player pill (or just in front)
				var guard_pos: Vector2 = best_ai_in_house.position.lerp(center, 0.3)
				guard_pos += Vector2(randf_range(-15, 15), randf_range(-15, 15))
				var to_guard: Vector2 = guard_pos - pill.position
				var guard_dist: float = to_guard.length()
				guard_dir = to_guard.normalized()
				guard_power_val = clampf(guard_dist * Constants.CURLING_PILL_DAMP * 1.5, 200.0, 600.0)
				guard_score = 50.0

		# Pick best strategy for this pill
		var chosen_dir := s1_dir
		var chosen_power := s1_power
		var chosen_score := s1_score

		if knock_score > chosen_score:
			chosen_dir = knock_dir
			chosen_power = knock_power_val
			chosen_score = knock_score

		if guard_score > chosen_score:
			chosen_dir = guard_dir
			chosen_power = guard_power_val
			chosen_score = guard_score

		if chosen_score > best_score:
			best_score = chosen_score
			best_pill = pill
			best_dir = chosen_dir
			best_power = chosen_power

	# Apply difficulty imperfections
	if diff == 0:
		best_dir = best_dir.rotated(randf_range(-0.15, 0.15))
		best_power *= randf_range(0.65, 0.85)
	elif diff == 1:
		best_dir = best_dir.rotated(randf_range(-0.06, 0.06))
		best_power *= randf_range(0.88, 1.06)

	best_power = clampf(best_power, 200.0, Constants.MAX_POWER)

	ai_target_pill = best_pill
	ai_aim_dir = best_dir.normalized()
	ai_aim_power = best_power

	if ai_target_pill != null:
		ai_target_pill.is_selected = true

func _ai_fire():
	if ai_target_pill == null:
		var avail := _ai_available()
		if avail.is_empty():
			shots_done += 1
			if shots_done >= 6:
				_score_end()
			else:
				_begin_turn()
			return
		ai_target_pill = avail[0]
		ai_aim_dir = (_house_center() - ai_target_pill.position).normalized()
		ai_aim_power = 500.0

	var pill_idx: int = ai_pills.find(ai_target_pill)
	ai_used.append(pill_idx)
	ai_target_pill.kick(ai_aim_dir * ai_aim_power)
	ai_target_pill.is_selected = false
	ai_target_pill = null
	phase = Phase.EXECUTING
	settle_timer = 0.0

# ═══════════════════════════════════════════════════════════════
# SCORING
# ═══════════════════════════════════════════════════════════════

func _score_end():
	var center: Vector2 = _house_center()
	var outer_r: float = Constants.HOUSE_RADIUS_OUTER

	var p_dists: Array[float] = []
	var a_dists: Array[float] = []
	for p in player_pills:
		var d: float = p.position.distance_to(center)
		if d <= outer_r:
			p_dists.append(d)
	for a in ai_pills:
		var d: float = a.position.distance_to(center)
		if d <= outer_r:
			a_dists.append(d)

	p_dists.sort()
	a_dists.sort()

	var points: int = 0
	var winner: String = ""

	if p_dists.is_empty() and a_dists.is_empty():
		end_msg = "Blank end!"
		phase = Phase.END_SCORED
		end_timer = 2.0
		center_msg.text = end_msg
		center_msg.visible = true
		# Blank end — first_team stays the same
		return

	if a_dists.is_empty():
		points = p_dists.size()
		winner = "player"
	elif p_dists.is_empty():
		points = a_dists.size()
		winner = "ai"
	elif p_dists[0] < a_dists[0]:
		winner = "player"
		for d in p_dists:
			if d < a_dists[0]:
				points += 1
			else:
				break
	else:
		winner = "ai"
		for d in a_dists:
			if d < p_dists[0]:
				points += 1
			else:
				break

	if winner == "player":
		player_score += points
		first_team = "player"
	else:
		ai_score += points
		first_team = "ai"

	end_msg = "%s +%d!" % [("You" if winner == "player" else "AI"), points]
	phase = Phase.END_SCORED
	end_timer = 2.5
	center_msg.text = end_msg
	center_msg.visible = true
	score_sfx.play()

func _all_stopped() -> bool:
	for pill in player_pills + ai_pills:
		if not pill.is_stopped():
			return false
	return true

func _show_game_over():
	phase = Phase.GAME_OVER
	center_msg.text = "YOU WIN!" if player_score >= Constants.CURLING_WIN_SCORE else "AI WINS!"
	center_msg.visible = true
	restart_label.visible = true
	music.stop()
	win_sfx.play()

func _reset_all():
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
			_restart_game()
		return

	if phase != Phase.PLAYER_AIM:
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
	var available := _player_available()
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

func _restart_game():
	player_score = 0
	ai_score = 0
	end_num = 0
	first_team = "player"
	_reset_all()
	_start_end()
	if not music.playing:
		music.play()

# ═══════════════════════════════════════════════════════════════
# DRAWING
# ═══════════════════════════════════════════════════════════════

func _draw():
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.08, 0.10, 0.14))
	_draw_field()
	_draw_house()
	_draw_shot_indicators()
	if phase == Phase.PLAYER_AIM and selected_pill != null and aim_pow > Constants.MIN_POWER:
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

func _draw_shot_indicators():
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)
	var f: Rect2 = Constants.FIELD_RECT
	var y_top: float = f.position.y - 5
	var dot_r := 6.0
	var gap := 18.0

	# Player shots — left side
	var px: float = f.position.x + 20
	for i in range(3):
		var col: Color
		if i in player_used:
			col = Color(Constants.PLAYER_COLOR, 0.3)
		else:
			col = Constants.PLAYER_COLOR
		draw_circle(Vector2(px + i * gap, y_top), dot_r, col)

	# AI shots — right side
	var ax: float = f.position.x + f.size.x - 20 - 2 * gap
	for i in range(3):
		var col: Color
		if i in ai_used:
			col = Color(Constants.AI_COLOR, 0.3)
		else:
			col = Constants.AI_COLOR
		draw_circle(Vector2(ax + i * gap, y_top), dot_r, col)

# ═══════════════════════════════════════════════════════════════
# HUD
# ═══════════════════════════════════════════════════════════════

func _update_hud():
	score_label.text = "YOU  %d  –  %d  AI    End %d" % [player_score, ai_score, end_num]
	var team: String = _current_team()

	match phase:
		Phase.PLAYER_AIM:
			timer_bar.visible = true
			timer_bar.value = aim_timer
			var pct: float = aim_timer / Constants.CURLING_AIM_TIME
			if pct > 0.5:
				timer_bar_style.bg_color = Color(0.2, 0.9, 0.2)
			elif pct > 0.25:
				timer_bar_style.bg_color = Color(0.95, 0.85, 0.1)
			else:
				timer_bar_style.bg_color = Color(0.95, 0.2, 0.15)
			var remaining: int = 3 - player_used.size()
			phase_label.text = "Your turn!  Drag a disc to shoot  ·  %d disc%s left" % [remaining, "" if remaining == 1 else "s"]
			turn_indicator.text = "▶ YOUR SHOT"
			turn_indicator.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))

		Phase.AI_THINKING:
			timer_bar.visible = false
			phase_label.text = "AI is thinking..."
			turn_indicator.text = "▶ AI SHOT"
			turn_indicator.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))

		Phase.EXECUTING, Phase.SETTLING:
			timer_bar.visible = false
			phase_label.text = ""
			turn_indicator.text = "Shot %d / 6" % shots_done if shots_done < 6 else ""

		Phase.END_SCORED:
			timer_bar.visible = false
			phase_label.text = end_msg
			turn_indicator.text = ""

		Phase.GAME_OVER:
			timer_bar.visible = false
			phase_label.text = ""
			turn_indicator.text = ""

# ═══════════════════════════════════════════════════════════════
# BUILD HELPERS
# ═══════════════════════════════════════════════════════════════

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
	mat.bounce = 0.5
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
		p.linear_damp = Constants.CURLING_PILL_DAMP
		player_pills.append(p)

	for i in range(3):
		var p := Pill.new()
		p.team = "ai"
		p.pill_index = i
		p.pill_color = Constants.AI_COLOR
		p.pill_color_light = Constants.AI_COLOR_LIGHT
		p.position = Constants.AI_START[i]
		add_child(p)
		p.linear_damp = Constants.CURLING_PILL_DAMP
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
	score_label.position = Vector2(vp.x / 2.0 - 250, 8 + Constants.safe_top)
	score_label.size = Vector2(500, 50)
	score_label.add_theme_font_size_override("font_size", 28)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	hud_layer.add_child(score_label)

	phase_label = Label.new()
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.position = Vector2(vp.x / 2.0 - 350, 38)
	phase_label.size = Vector2(700, 25)
	phase_label.add_theme_font_size_override("font_size", 16)
	phase_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	hud_layer.add_child(phase_label)

	turn_indicator = Label.new()
	turn_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_indicator.position = Vector2(vp.x / 2.0 - 150, 58 + Constants.safe_top)
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
