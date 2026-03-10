extends Control

var diff_label: Label
var music_player: AudioStreamPlayer
const DIFF_NAMES := ["Easy", "Normal", "Hard"]
const DIFF_COLORS := [Color(0.3, 0.85, 0.3), Color(0.95, 0.85, 0.1), Color(0.95, 0.25, 0.2)]

func _ready():
	# Menu music (looping)
	music_player = AudioStreamPlayer.new()
	music_player.stream = load("res://assets/sounds/menu.mp3")
	music_player.volume_db = -6.0
	music_player.finished.connect(func(): music_player.play())
	add_child(music_player)
	music_player.play()

	# Background image
	var bg_tex: Texture2D = load("res://assets/menu-bg2.jpg")
	var bg := TextureRect.new()
	bg.texture = bg_tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Dark overlay so text stays readable
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.45)
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	add_child(overlay)

	# Center layout
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "SHOOTBALL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	vbox.add_child(title)

	# Subtitle
	var sub := Label.new()
	sub.text = "Penny Football — Reimagined"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	vbox.add_child(sub)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 45)
	vbox.add_child(spacer)

	# Play button
	var play_btn := Button.new()
	play_btn.text = "  Play vs AI  "
	play_btn.add_theme_font_size_override("font_size", 26)
	play_btn.custom_minimum_size = Vector2(260, 56)
	play_btn.pressed.connect(_on_play)
	vbox.add_child(play_btn)

	# Difficulty row
	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 10)
	vbox.add_child(diff_row)

	var diff_left := Button.new()
	diff_left.text = " < "
	diff_left.add_theme_font_size_override("font_size", 22)
	diff_left.custom_minimum_size = Vector2(44, 44)
	diff_left.pressed.connect(_on_diff_change.bind(-1))
	diff_row.add_child(diff_left)

	diff_label = Label.new()
	diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diff_label.custom_minimum_size = Vector2(160, 44)
	diff_label.add_theme_font_size_override("font_size", 22)
	diff_row.add_child(diff_label)
	_update_diff_label()

	var diff_right := Button.new()
	diff_right.text = " > "
	diff_right.add_theme_font_size_override("font_size", 22)
	diff_right.custom_minimum_size = Vector2(44, 44)
	diff_right.pressed.connect(_on_diff_change.bind(1))
	diff_row.add_child(diff_right)

	# Play Online button
	var online_btn := Button.new()
	online_btn.text = "  Play Online  "
	online_btn.add_theme_font_size_override("font_size", 24)
	online_btn.custom_minimum_size = Vector2(260, 52)
	online_btn.pressed.connect(_on_play_online)
	vbox.add_child(online_btn)

	# Avatar button
	var avatar_btn := Button.new()
	avatar_btn.text = "  Select Avatar  "
	avatar_btn.add_theme_font_size_override("font_size", 22)
	avatar_btn.custom_minimum_size = Vector2(260, 48)
	avatar_btn.pressed.connect(_on_avatar)
	vbox.add_child(avatar_btn)

	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer2)

	# Quit button
	var quit_btn := Button.new()
	quit_btn.text = "  Quit  "
	quit_btn.add_theme_font_size_override("font_size", 20)
	quit_btn.custom_minimum_size = Vector2(260, 44)
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	# How-to-play hint at the bottom
	var hint := Label.new()
	hint.text = "Select a pill  →  drag back to aim (slingshot)  →  shot must pass between your other two pills  →  first to 3 goals wins"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.78, 0.78, 0.85))
	hint.set_anchors_preset(PRESET_BOTTOM_WIDE)
	hint.offset_top = -50
	hint.offset_left = 120
	hint.offset_right = -120
	add_child(hint)

func _on_play():
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_play_online():
	get_tree().change_scene_to_file("res://scenes/online_lobby.tscn")

func _on_avatar():
	get_tree().change_scene_to_file("res://scenes/avatar_select.tscn")

func _on_diff_change(delta: int):
	Constants.ai_difficulty = clampi(Constants.ai_difficulty + delta, 0, 2)
	Constants.save_settings()
	_update_diff_label()

func _update_diff_label():
	var d: int = Constants.ai_difficulty
	diff_label.text = DIFF_NAMES[d]
	diff_label.add_theme_color_override("font_color", DIFF_COLORS[d])

func _on_quit():
	get_tree().quit()
