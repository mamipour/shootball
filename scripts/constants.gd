extends Node

# --- Field (recalculated in _ready based on viewport) ---
var FIELD_RECT := Rect2(90, 60, 1100, 600)
const FIELD_COLOR := Color(0.133, 0.545, 0.133)
const FIELD_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.5)
const WALL_COLOR := Color(0.36, 0.20, 0.09)
const WALL_THICKNESS := 12.0

# Base design dimensions (the field is designed for 1280x720)
const BASE_FIELD_W := 1100.0
const BASE_FIELD_H := 600.0

# --- Goals ---
const GOAL_WIDTH := 160.0
const GOAL_DEPTH := 45.0

# --- Pills ---
const PILL_RADIUS := 22.0
const PILL_LINEAR_DAMP := 2.5
const PILL_BOUNCE := 0.65
const PILL_FRICTION := 0.3
const PLAYER_COLOR := Color(0.15, 0.35, 0.85)
const PLAYER_COLOR_LIGHT := Color(0.35, 0.55, 1.0)
const AI_COLOR := Color(0.85, 0.15, 0.15)
const AI_COLOR_LIGHT := Color(1.0, 0.35, 0.35)

# --- Aiming ---
const AIM_TIME := 8.0
const MAX_POWER := 1400.0
const MIN_POWER := 30.0
const POWER_SCALE := 14.0
const AIM_VALID_COLOR := Color(0.2, 1.0, 0.2, 0.7)
const AIM_INVALID_COLOR := Color(1.0, 0.2, 0.2, 0.7)
const GATE_COLOR := Color(1.0, 1.0, 0.0, 0.6)

# --- Physics ---
const SETTLE_VELOCITY_THRESHOLD := 8.0
const SETTLE_GRACE_TIME := 0.3

# --- Scoring ---
const WIN_SCORE := 3
const GOAL_DISPLAY_TIME := 2.0

# --- Starting positions (recalculated in _ready) ---
var PLAYER_START := [
	Vector2(280, 280),
	Vector2(280, 440),
	Vector2(180, 360),
]
var AI_START := [
	Vector2(1000, 280),
	Vector2(1000, 440),
	Vector2(1100, 360),
]

# --- AI Difficulty (0=easy, 1=normal, 2=hard) ---
var ai_difficulty: int = 1

# --- Avatars ---
const AVATAR_COUNT := 30
const AVATAR_DIR := "res://assets/avatars/"
var player_avatar_idx: int = 0
var ai_avatar_idx: int = 1

const SETTINGS_PATH := "user://settings.cfg"

func _ready():
	_load_settings()
	_center_field()

func _center_field():
	var vp_size := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	var actual := get_viewport().get_visible_rect().size
	if actual.x > 0 and actual.y > 0:
		vp_size = actual
	var margin_x := (vp_size.x - BASE_FIELD_W) / 2.0
	var margin_y := (vp_size.y - BASE_FIELD_H) / 2.0
	FIELD_RECT = Rect2(margin_x, margin_y, BASE_FIELD_W, BASE_FIELD_H)
	var fx := FIELD_RECT.position.x
	var fy := FIELD_RECT.position.y
	var fw := FIELD_RECT.size.x
	var fh := FIELD_RECT.size.y
	var cy := fy + fh / 2.0
	PLAYER_START = [
		Vector2(fx + fw * 0.173, cy - 80),
		Vector2(fx + fw * 0.173, cy + 80),
		Vector2(fx + fw * 0.082, cy),
	]
	AI_START = [
		Vector2(fx + fw * 0.827, cy - 80),
		Vector2(fx + fw * 0.827, cy + 80),
		Vector2(fx + fw * 0.918, cy),
	]

func _load_settings():
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		player_avatar_idx = cfg.get_value("avatars", "player", 0)
		ai_difficulty = cfg.get_value("game", "difficulty", 1)

func save_settings():
	var cfg := ConfigFile.new()
	cfg.set_value("avatars", "player", player_avatar_idx)
	cfg.set_value("game", "difficulty", ai_difficulty)
	cfg.save(SETTINGS_PATH)
