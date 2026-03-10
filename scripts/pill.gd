class_name Pill
extends RigidBody2D

var team: String = "player"
var pill_index: int = 0
var pill_color: Color = Color.BLUE
var pill_color_light: Color = Color.CORNFLOWER_BLUE
var is_selected: bool = false
var avatar_texture: Texture2D = null

var _kick_velocity := Vector2.ZERO
var _has_kick := false
var _reset_pos := Vector2.ZERO
var _has_reset := false

func _ready():
	gravity_scale = 0.0
	can_sleep = false
	linear_damp = Constants.PILL_LINEAR_DAMP
	collision_layer = 1
	collision_mask = 1

	var mat = PhysicsMaterial.new()
	mat.bounce = Constants.PILL_BOUNCE
	mat.friction = Constants.PILL_FRICTION
	physics_material_override = mat

	var shape = CircleShape2D.new()
	shape.radius = Constants.PILL_RADIUS
	var col = CollisionShape2D.new()
	col.shape = shape
	add_child(col)

func kick(impulse: Vector2):
	_kick_velocity = impulse
	_has_kick = true

func reset_to(pos: Vector2):
	_reset_pos = pos
	_has_reset = true

func _integrate_forces(state: PhysicsDirectBodyState2D):
	if _has_reset:
		state.transform = Transform2D(0, _reset_pos)
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0
		_has_reset = false
	if _has_kick:
		state.linear_velocity = _kick_velocity
		_has_kick = false
		_kick_velocity = Vector2.ZERO

func _draw():
	var r: float = Constants.PILL_RADIUS
	draw_circle(Vector2(3, 3), r, Color(0.0, 0.0, 0.0, 0.25))
	if avatar_texture != null:
		var size: float = r * 2.0
		draw_texture_rect(avatar_texture, Rect2(Vector2(-r, -r), Vector2(size, size)), false)
	else:
		draw_circle(Vector2.ZERO, r, pill_color)
		draw_circle(Vector2(-4, -4), r * 0.55, pill_color_light)
	draw_arc(Vector2.ZERO, r, 0, TAU, 128, Color(1, 1, 1, 0.35), 1.5, true)
	if is_selected:
		draw_arc(Vector2.ZERO, r + 4, 0, TAU, 128, Color.YELLOW, 2.5, true)

func _process(_delta: float):
	queue_redraw()

func is_stopped() -> bool:
	return linear_velocity.length() < Constants.SETTLE_VELOCITY_THRESHOLD
