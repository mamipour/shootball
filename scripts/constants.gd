extends Node

# --- Field ---
var FIELD_RECT := Rect2(90, 60, 1100, 600)
const FIELD_COLOR := Color(0.133, 0.545, 0.133)
const FIELD_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.5)
const WALL_COLOR := Color(0.36, 0.20, 0.09)
const WALL_THICKNESS := 12.0

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

# --- Starting positions ---
# Formation: two "gate" pills forward, one shooter behind.
# The shooter can fire through the gate toward the opponent's goal.
var PLAYER_START := [
	Vector2(280, 280),   # forward upper (gate)
	Vector2(280, 440),   # forward lower (gate)
	Vector2(180, 360),   # back center  (shooter)
]
var AI_START := [
	Vector2(1000, 280),  # forward upper (gate)
	Vector2(1000, 440),  # forward lower (gate)
	Vector2(1100, 360),  # back center  (shooter)
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
