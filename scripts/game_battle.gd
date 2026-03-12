extends Node2D

enum Phase { AIMING, EXECUTING, SETTLING, ELIMINATION, GAME_OVER }

# ── Nodes ──
var player_pills: Array = []
var ai_pills: Array = []

# ── HUD ──
var hud_layer: CanvasLayer
var status_label: Label
var timer_bar: ProgressBar
var timer_bar_style: StyleBoxFlat
var center_msg: Label
var restart_label: Label
var quit_btn: Button
var quit_confirm: Panel

# ── State ──
var phase: Phase = Phase.AIMING
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

# ── Elimination display ──
var elim_timer: float = 0.0
var elim_message: String = ""

# ── Pit ──
var pit_center := Vector2.ZERO
var pit_area: Area2D

# ── Audio ──
# ── Assets ──
var arena_texture: Texture2D = null

# ── Audio ──
var battle_music: AudioStreamPlayer
var elim_sfx: AudioStreamPlayer
var win_sfx: AudioStreamPlayer

# ═══════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	arena_texture = load("res://assets/arena_dust_floor.svg")
	var ar: Rect2 = Constants.BATTLE_ARENA_RECT
	pit_center = ar.position + ar.size / 2.0
	_setup_audio()
	_build_arena_walls()
	_build_pit()
	_build_pills()
	_assign_avatars()
	_build_hud()
	_start_round()

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
					_check_pit_eliminations()
			else:
				settle_timer = 0.0
		Phase.ELIMINATION:
			elim_timer -= delta
			if elim_timer <= 0.0:
				var alive_player := _alive_pills(player_pills)
				var alive_ai := _alive_pills(ai_pills)
				if alive_player.size() == 0 or alive_ai.size() == 0:
					_show_game_over()
				else:
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
	aim_timer = Constants.BATTLE_AIM_TIME
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
	for p in player_pills:
		p.is_selected = false

# ═══════════════════════════════════════════════════════════════
# AI
# ═══════════════════════════════════════════════════════════════

func _ai_decide():
	ai_decided = true
	ai_shots.clear()
	var diff: int = Constants.ai_difficulty
	var alive_ai := _alive_pills(ai_pills)
	var alive_player := _alive_pills(player_pills)
	var ar: Rect2 = Constants.BATTLE_ARENA_RECT

	var assigned_targets: Array = []

	for pill in alive_ai:
		var pill_pit_dist: float = pill.position.distance_to(pit_center)
		var best_action: String = ""
		var best_score: float = -999.0
		var best_dir := Vector2.ZERO
		var best_power: float = 0.0

		# --- Phase 1: Self-preservation ---
		# If this pill is in danger zone, escape is top priority
		var danger_radius: float = Constants.PIT_PULL_RADIUS * 1.8
		if diff >= 2:
			danger_radius = Constants.PIT_PULL_RADIUS * 2.2
		if pill_pit_dist < danger_radius:
			var urgency: float = 1.0 - (pill_pit_dist / danger_radius)
			var escape_dir: Vector2 = (pill.position - pit_center).normalized()
			# Find best escape angle: away from pit AND toward a safe wall
			var best_escape_score: float = -999.0
			var best_escape_dir: Vector2 = escape_dir
			var angle_steps: int = 8 if diff == 0 else (16 if diff == 1 else 24)
			for step in range(angle_steps):
				var angle: float = -PI + TAU * step / angle_steps
				var test_dir: Vector2 = Vector2(cos(angle), sin(angle))
				var away_dot: float = test_dir.dot(escape_dir)
				if away_dot < 0.2:
					continue
				# Prefer directions that lead away from pit AND stay on the field
				var end_pos: Vector2 = pill.position + test_dir * 200.0
				var in_field: bool = ar.has_point(end_pos)
				var e_score: float = away_dot * 60.0
				if in_field:
					e_score += 20.0
				# Avoid directions toward player pills (they might knock us back)
				var blocked: bool = false
				for pp in alive_player:
					if _ai_is_in_path(pill.position, test_dir, pp.position, 150.0):
						blocked = true
						break
				if blocked and diff >= 1:
					e_score -= 25.0
				if e_score > best_escape_score:
					best_escape_score = e_score
					best_escape_dir = test_dir

			var escape_score: float = 80.0 + urgency * 70.0
			var escape_power: float = clampf(300.0 + urgency * 500.0, 300.0, Constants.MAX_POWER)
			if escape_score > best_score:
				best_score = escape_score
				best_dir = best_escape_dir
				best_power = escape_power
				best_action = "escape"

		# --- Phase 2: Offensive — knock opponent into pit ---
		for target in alive_player:
			if target in assigned_targets and diff >= 1:
				continue
			var to_target: Vector2 = target.position - pill.position
			var dist: float = to_target.length()
			var dir: Vector2 = to_target.normalized()
			var target_pit_dist: float = target.position.distance_to(pit_center)

			# How well does hitting this target push it toward the pit?
			var hit_push_dir: Vector2 = dir
			var target_to_pit: Vector2 = (pit_center - target.position).normalized()
			var alignment: float = hit_push_dir.dot(target_to_pit)

			var score: float = 0.0

			# Strong bonus for good alignment (our hit pushes target toward pit)
			score += alignment * 60.0

			# Bonus for targets already near the pit
			var pit_proximity: float = maxf(0.0, 1.0 - target_pit_dist / 400.0)
			score += pit_proximity * 50.0

			# Penalty for long distance (less accurate, less force on impact)
			score -= (dist / 500.0) * 15.0

			# Bonus for very close targets (easy to hit hard)
			if dist < 200.0:
				score += 20.0

			# Check if path is blocked by friendly pills
			if diff >= 1:
				var path_blocked: bool = false
				for friendly in alive_ai:
					if friendly == pill:
						continue
					if _ai_is_in_path(pill.position, dir, friendly.position, dist):
						path_blocked = true
						break
				if path_blocked:
					score -= 40.0

			# Hard mode: consider ricochet angles and secondary hits
			if diff >= 2:
				# Bonus if target is between us and the pit
				var our_pit_dist: float = pill.position.distance_to(pit_center)
				if target_pit_dist < our_pit_dist:
					score += 15.0
				# Bonus if target is near the edge (can be knocked out to pit pull zone)
				var edge_dist: float = _ai_dist_to_arena_edge(target.position, ar)
				if edge_dist < 80.0:
					score += 10.0

			# Power: hit harder when target is close to pit, scale with distance
			var power: float = clampf(dist * Constants.PILL_LINEAR_DAMP * 1.8, 350.0, Constants.MAX_POWER)
			if target_pit_dist < Constants.PIT_PULL_RADIUS * 2.0:
				power = clampf(power * 1.3, 350.0, Constants.MAX_POWER)

			if score > best_score:
				best_score = score
				best_dir = dir
				best_power = power
				best_action = "attack"

		# --- Phase 3: Disruption — push opponent toward danger zone ---
		if diff >= 1 and best_score < 50.0:
			for target in alive_player:
				var to_target: Vector2 = target.position - pill.position
				var dist: float = to_target.length()
				var target_pit_dist: float = target.position.distance_to(pit_center)

				# Try angled shots that push target toward pit zone
				var target_to_pit: Vector2 = (pit_center - target.position).normalized()
				for angle_off in [-0.3, -0.15, 0.0, 0.15, 0.3]:
					var dir: Vector2 = to_target.normalized().rotated(angle_off)
					var push_result: Vector2 = dir
					var push_alignment: float = push_result.dot(target_to_pit)

					var score: float = push_alignment * 40.0
					score += maxf(0.0, 1.0 - target_pit_dist / 500.0) * 25.0
					score -= dist / 500.0 * 10.0

					var power: float = clampf(dist * Constants.PILL_LINEAR_DAMP * 1.5, 300.0, Constants.MAX_POWER * 0.8)

					if score > best_score:
						best_score = score
						best_dir = dir
						best_power = power
						best_action = "disrupt"

		# --- Phase 4: Repositioning (hard only) ---
		if diff >= 2 and best_score < 30.0:
			# Move to a strategic position: behind an opponent relative to the pit
			for target in alive_player:
				var target_to_pit: Vector2 = (pit_center - target.position).normalized()
				var ideal_pos: Vector2 = target.position - target_to_pit * 180.0
				# Clamp to arena
				ideal_pos.x = clampf(ideal_pos.x, ar.position.x + 40, ar.position.x + ar.size.x - 40)
				ideal_pos.y = clampf(ideal_pos.y, ar.position.y + 40, ar.position.y + ar.size.y - 40)
				# Don't reposition into the pit zone
				if ideal_pos.distance_to(pit_center) < Constants.PIT_PULL_RADIUS * 1.5:
					continue
				var move_dir: Vector2 = (ideal_pos - pill.position).normalized()
				var move_dist: float = pill.position.distance_to(ideal_pos)
				var score: float = 20.0 + clampf(move_dist / 300.0, 0.0, 1.0) * 15.0
				var power: float = clampf(move_dist * 0.7, 150.0, 500.0)

				if score > best_score:
					best_score = score
					best_dir = move_dir
					best_power = power
					best_action = "reposition"

		# --- Fallback ---
		if best_dir.length() < 0.1:
			var away: Vector2 = (pill.position - pit_center).normalized()
			best_dir = away.rotated(randf_range(-0.4, 0.4))
			best_power = 400.0
			best_action = "fallback"

		# --- Apply difficulty imperfections ---
		if diff == 0:
			best_dir = best_dir.rotated(randf_range(-0.22, 0.22))
			best_power *= randf_range(0.45, 0.7)
		elif diff == 1:
			best_dir = best_dir.rotated(randf_range(-0.07, 0.07))
			best_power *= randf_range(0.85, 1.05)

		best_power = clampf(best_power, 200.0, Constants.MAX_POWER)
		ai_shots.append({"pill": pill, "dir": best_dir.normalized(), "power": best_power})

		# Track assigned targets so multiple pills don't aim at the same one
		if best_action == "attack" and diff >= 1:
			for target in alive_player:
				var dir_to: Vector2 = (target.position - pill.position).normalized()
				if best_dir.dot(dir_to) > 0.9:
					assigned_targets.append(target)
					break

func _ai_is_in_path(origin: Vector2, dir: Vector2, target_pos: Vector2, max_dist: float) -> bool:
	var to_target: Vector2 = target_pos - origin
	var proj: float = to_target.dot(dir.normalized())
	if proj < Constants.PILL_RADIUS or proj > max_dist:
		return false
	var closest: Vector2 = origin + dir.normalized() * proj
	return closest.distance_to(target_pos) < Constants.PILL_RADIUS * 2.5

func _ai_dist_to_arena_edge(pos: Vector2, ar: Rect2) -> float:
	var dl: float = pos.x - ar.position.x
	var dr: float = ar.position.x + ar.size.x - pos.x
	var dt: float = pos.y - ar.position.y
	var db: float = ar.position.y + ar.size.y - pos.y
	return minf(minf(dl, dr), minf(dt, db))

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
# PIT MECHANICS
# ═══════════════════════════════════════════════════════════════

func _apply_pit_gravity(delta: float):
	for pill in player_pills + ai_pills:
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

func _check_pit_eliminations():
	var had_elimination := false
	for pill in player_pills + ai_pills:
		if not pill.visible:
			continue
		if pill.position.distance_to(pit_center) < Constants.PIT_RADIUS * 0.6:
			_eliminate_pill(pill)
			had_elimination = true

	var alive_player := _alive_pills(player_pills)
	var alive_ai := _alive_pills(ai_pills)

	if had_elimination:
		elim_sfx.play()
		phase = Phase.ELIMINATION
		elim_timer = 1.5
		var p_lost := 3 - alive_player.size()
		var a_lost := 3 - alive_ai.size()
		elim_message = "Units — You: %d   AI: %d" % [alive_player.size(), alive_ai.size()]
		center_msg.text = elim_message
		center_msg.visible = true
	elif alive_player.size() == 0 or alive_ai.size() == 0:
		_show_game_over()
	else:
		_start_round()

func _alive_pills(pills: Array) -> Array:
	var result: Array = []
	for p in pills:
		if p.visible:
			result.append(p)
	return result

func _all_stopped() -> bool:
	for pill in player_pills + ai_pills:
		if pill.visible and not pill.is_stopped():
			return false
	return true

# ═══════════════════════════════════════════════════════════════
# GAME OVER
# ═══════════════════════════════════════════════════════════════

func _show_game_over():
	phase = Phase.GAME_OVER
	var alive_player := _alive_pills(player_pills)
	center_msg.text = "YOU WIN!" if alive_player.size() > 0 else "AI WINS!"
	center_msg.visible = true
	restart_label.visible = true
	battle_music.stop()
	win_sfx.play()

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
			_restart_battle()
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


func _restart_battle():
	for p in player_pills:
		p.visible = true
		p.freeze = false
	for p in ai_pills:
		p.visible = true
		p.freeze = false
	for i in range(3):
		player_pills[i].reset_to(Constants.BATTLE_PLAYER_START[i])
	for i in range(3):
		ai_pills[i].reset_to(Constants.BATTLE_AI_START[i])
	round_num = 0
	_start_round()
	if not battle_music.playing:
		battle_music.play()

# ═══════════════════════════════════════════════════════════════
# DRAWING
# ═══════════════════════════════════════════════════════════════

func _draw():
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.18, 0.15, 0.12))
	_draw_arena()
	_draw_pit()
	_draw_arena_lines()
	if phase == Phase.AIMING:
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

# ═══════════════════════════════════════════════════════════════
# HUD
# ═══════════════════════════════════════════════════════════════

func _update_hud():
	var alive_p := _alive_pills(player_pills).size()
	var alive_a := _alive_pills(ai_pills).size()
	status_label.text = "YOU: %d units   —   AI: %d units" % [alive_p, alive_a]

	match phase:
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
			pass
		Phase.EXECUTING, Phase.SETTLING:
			timer_bar.visible = false
		Phase.ELIMINATION:
			timer_bar.visible = false
		Phase.GAME_OVER:
			timer_bar.visible = false


# ═══════════════════════════════════════════════════════════════
# BUILD HELPERS
# ═══════════════════════════════════════════════════════════════

func _build_arena_walls():
	var ar: Rect2 = Constants.BATTLE_ARENA_RECT
	var wt: float = Constants.WALL_THICKNESS
	var cr: float = Constants.ARENA_CORNER_RADIUS

	_wall(Vector2(ar.position.x + ar.size.x / 2.0, ar.position.y - wt / 2.0),
		Vector2(ar.size.x - cr * 2, wt))
	_wall(Vector2(ar.position.x + ar.size.x / 2.0, ar.position.y + ar.size.y + wt / 2.0),
		Vector2(ar.size.x - cr * 2, wt))

	_wall(Vector2(ar.position.x - wt / 2.0, ar.position.y + ar.size.y / 2.0),
		Vector2(wt, ar.size.y - cr * 2))
	_wall(Vector2(ar.position.x + ar.size.x + wt / 2.0, ar.position.y + ar.size.y / 2.0),
		Vector2(wt, ar.size.y - cr * 2))

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
	for i in range(3):
		var p := Pill.new()
		p.team = "player"
		p.pill_index = i
		p.pill_color = Constants.PLAYER_COLOR
		p.pill_color_light = Constants.PLAYER_COLOR_LIGHT
		p.position = Constants.BATTLE_PLAYER_START[i]
		add_child(p)
		player_pills.append(p)

	for i in range(3):
		var p := Pill.new()
		p.team = "ai"
		p.pill_index = i
		p.pill_color = Constants.AI_COLOR
		p.pill_color_light = Constants.AI_COLOR_LIGHT
		p.position = Constants.BATTLE_AI_START[i]
		add_child(p)
		ai_pills.append(p)

func _build_hud():
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.position = Vector2(vp.x / 2.0 - 200, 8 + Constants.safe_top)
	status_label.size = Vector2(400, 50)
	status_label.add_theme_font_size_override("font_size", 26)
	status_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	hud_layer.add_child(status_label)

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
