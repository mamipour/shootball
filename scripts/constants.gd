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
var master_volume: float = 0.5

# --- Avatars ---
const AVATAR_COUNT := 30
const AVATAR_DIR := "res://assets/avatars/"
var player_avatar_idx: int = 0
var ai_avatar_idx: int = 1

# ═══════════════════════════════════════════════════════════════
# FOOTBALL MODE
# ═══════════════════════════════════════════════════════════════
const FOOTBALL_AIM_TIME := 10.0
const BALL_RADIUS := 18.0
const BALL_LINEAR_DAMP := 1.8
const BALL_BOUNCE := 0.75
const BALL_FRICTION := 0.2

# ═══════════════════════════════════════════════════════════════
# VOLLEYBALL
# ═══════════════════════════════════════════════════════════════
const VOLLEYBALL_AIM_TIME := 10.0
const VB_BALL_LINEAR_DAMP := 1.6
const VB_BALL_BOUNCE := 0.8
const VB_BALL_FRICTION := 0.15
const VB_BALL_RADIUS := 20.0

# ═══════════════════════════════════════════════════════════════
# CURLING
# ═══════════════════════════════════════════════════════════════
const CURLING_AIM_TIME := 10.0
const CURLING_PILL_DAMP := 1.5
const CURLING_WIN_SCORE := 5
const HOUSE_RADIUS_OUTER := 130.0
const HOUSE_RADIUS_MID := 85.0
const HOUSE_RADIUS_INNER := 45.0
const HOUSE_RADIUS_BUTTON := 12.0

# ═══════════════════════════════════════════════════════════════
# BATTLE ARENA
# ═══════════════════════════════════════════════════════════════
const ARENA_COLOR := Color(0.42, 0.36, 0.26)
const ARENA_LINE_COLOR := Color(0.7, 0.6, 0.45, 0.4)
const ARENA_WALL_COLOR := Color(0.30, 0.25, 0.18)
const ARENA_CORNER_RADIUS := 80.0

const PIT_RADIUS := 55.0
const PIT_COLOR := Color(0.08, 0.06, 0.04)
const PIT_EDGE_COLOR := Color(0.18, 0.14, 0.10)
const PIT_PULL_RADIUS := 85.0
const PIT_PULL_STRENGTH := 400.0

const BATTLE_AIM_TIME := 10.0
const BATTLE_PILL_COUNT := 3

var BATTLE_ARENA_RECT := Rect2(90, 60, 1100, 600)
const BASE_ARENA_W := 1100.0
const BASE_ARENA_H := 600.0

var BATTLE_PLAYER_START := [
	Vector2(250, 200),
	Vector2(250, 520),
	Vector2(180, 360),
]
var BATTLE_AI_START := [
	Vector2(1030, 200),
	Vector2(1030, 520),
	Vector2(1100, 360),
]

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
	_center_arena(vp_size)

func _center_arena(vp_size: Vector2):
	var mx := (vp_size.x - BASE_ARENA_W) / 2.0
	var my := (vp_size.y - BASE_ARENA_H) / 2.0
	BATTLE_ARENA_RECT = Rect2(mx, my, BASE_ARENA_W, BASE_ARENA_H)
	var ax := BATTLE_ARENA_RECT.position.x
	var ay := BATTLE_ARENA_RECT.position.y
	var aw := BATTLE_ARENA_RECT.size.x
	var ah := BATTLE_ARENA_RECT.size.y
	var acy := ay + ah / 2.0
	BATTLE_PLAYER_START = [
		Vector2(ax + aw * 0.16, acy - ah * 0.27),
		Vector2(ax + aw * 0.16, acy + ah * 0.27),
		Vector2(ax + aw * 0.08, acy),
	]
	BATTLE_AI_START = [
		Vector2(ax + aw * 0.84, acy - ah * 0.27),
		Vector2(ax + aw * 0.84, acy + ah * 0.27),
		Vector2(ax + aw * 0.92, acy),
	]

func _load_settings():
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		player_avatar_idx = cfg.get_value("avatars", "player", 0)
		ai_difficulty = cfg.get_value("game", "difficulty", 1)
		master_volume = cfg.get_value("audio", "volume", 0.5)
	_apply_volume()

func save_settings():
	var cfg := ConfigFile.new()
	cfg.set_value("avatars", "player", player_avatar_idx)
	cfg.set_value("game", "difficulty", ai_difficulty)
	cfg.set_value("audio", "volume", master_volume)
	cfg.save(SETTINGS_PATH)

func _apply_volume():
	var bus_idx := AudioServer.get_bus_index("Master")
	if master_volume <= 0.01:
		AudioServer.set_bus_mute(bus_idx, true)
	else:
		AudioServer.set_bus_mute(bus_idx, false)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(master_volume))
