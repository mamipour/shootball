class_name AIPlayer
extends RefCounted

var difficulty: float = 0.7

func decide_shot(my_pills: Array, _opponent_pills: Array, target_goal_center: Vector2) -> Dictionary:
	var best: Dictionary = {"pill_index": -1, "direction": Vector2.ZERO, "power": 0.0}
	var best_score := -INF

	for i in range(my_pills.size()):
		var shooter: RigidBody2D = my_pills[i]
		var gate_a: Vector2 = my_pills[(i + 1) % 3].position
		var gate_b: Vector2 = my_pills[(i + 2) % 3].position
		var to_goal := (target_goal_center - shooter.position).normalized()

		# Sweep a wide range of angles to find valid through-gate shots
		for step in range(-20, 21):
			var offset := step * 0.05
			var dir := to_goal.rotated(offset)
			if not _ray_hits_segment(shooter.position, dir, gate_a, gate_b):
				continue
			var score := _score_shot(shooter.position, dir, target_goal_center)
			score -= absf(offset) * 0.1
			score += randf_range(-0.15, 0.15) * (1.0 - difficulty)
			if score > best_score:
				best_score = score
				best = {
					"pill_index": i,
					"direction": dir,
					"power": _pick_power(shooter.position, target_goal_center),
				}

	if best["pill_index"] == -1:
		best = _fallback_shot(my_pills, target_goal_center)
	return best

func _score_shot(from: Vector2, dir: Vector2, goal: Vector2) -> float:
	var to_goal := (goal - from).normalized()
	var alignment := dir.dot(to_goal)
	var dist_factor := 1.0 / (1.0 + from.distance_to(goal) / 500.0)
	return alignment * 0.7 + dist_factor * 0.3

func _pick_power(from: Vector2, target: Vector2) -> float:
	var dist := from.distance_to(target)
	var base := clampf(dist * 0.8, 250.0, Constants.MAX_POWER * 0.85)
	return base * randf_range(0.8, 1.1) * difficulty + 200.0 * (1.0 - difficulty)

func _fallback_shot(pills: Array, target_goal_center: Vector2) -> Dictionary:
	# Try any direction through any gate (not just toward goal)
	for i in range(pills.size()):
		var shooter: RigidBody2D = pills[i]
		var ga: Vector2 = pills[(i + 1) % 3].position
		var gb: Vector2 = pills[(i + 2) % 3].position
		var gate_mid := (ga + gb) / 2.0
		var to_gate := (gate_mid - shooter.position).normalized()
		if _ray_hits_segment(shooter.position, to_gate, ga, gb):
			return {"pill_index": i, "direction": to_gate, "power": randf_range(250, 450)}

	# Last resort: push a pill toward the opponent's goal even without gate validation
	var best_idx := 0
	var best_dist := pills[0].position.distance_to(target_goal_center)
	for i in range(1, pills.size()):
		var d := pills[i].position.distance_to(target_goal_center)
		if d < best_dist:
			best_dist = d
			best_idx = i
	var to_goal := (target_goal_center - pills[best_idx].position).normalized()
	return {"pill_index": best_idx, "direction": to_goal, "power": randf_range(200, 350)}

func _ray_hits_segment(origin: Vector2, dir: Vector2, a: Vector2, b: Vector2) -> bool:
	var d := dir.normalized()
	var ab := b - a
	var denom := d.x * ab.y - d.y * ab.x
	if absf(denom) < 0.001:
		return false
	var oa := a - origin
	var t := (oa.x * ab.y - oa.y * ab.x) / denom
	var s := (oa.x * d.y - oa.y * d.x) / denom
	return t > 0.0 and s > 0.05 and s < 0.95
