extends Control

var diff_label: Label
var vol_slider: HSlider
var vol_label: Label
var music_player: AudioStreamPlayer
var main_vbox: VBoxContainer
var solo_vbox: VBoxContainer
const DIFF_NAMES := ["Easy", "Normal", "Hard"]
const DIFF_COLORS := [Color(0.3, 0.85, 0.3), Color(0.95, 0.85, 0.1), Color(0.95, 0.25, 0.2)]

func _ready():
	music_player = AudioStreamPlayer.new()
	music_player.stream = load("res://assets/sounds/menu.mp3")
	music_player.volume_db = -6.0
	music_player.finished.connect(func(): music_player.play())
	add_child(music_player)
	music_player.play()

	var bg_tex: Texture2D = load("res://assets/menu-bg2.jpg")
	var bg := TextureRect.new()
	bg.texture = bg_tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.45)
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 0)
	center.add_child(root_box)

	_build_main_menu(root_box)
	_build_solo_menu(root_box)
	solo_vbox.visible = false


func _build_main_menu(root: VBoxContainer):
	main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	root.add_child(main_vbox)

	var title := Label.new()
	title.text = "DISC ARENA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	main_vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Penny Football — Reimagined"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	main_vbox.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	main_vbox.add_child(spacer)

	var solo_btn := Button.new()
	solo_btn.text = "  Play Solo  "
	solo_btn.add_theme_font_size_override("font_size", 26)
	solo_btn.custom_minimum_size = Vector2(260, 56)
	solo_btn.pressed.connect(_show_solo_menu)
	main_vbox.add_child(solo_btn)

	var online_btn := Button.new()
	online_btn.text = "  Play Online  "
	online_btn.add_theme_font_size_override("font_size", 24)
	online_btn.custom_minimum_size = Vector2(260, 52)
	online_btn.pressed.connect(_on_play_online)
	main_vbox.add_child(online_btn)

	var avatar_btn := Button.new()
	avatar_btn.text = "  Select Avatar  "
	avatar_btn.add_theme_font_size_override("font_size", 22)
	avatar_btn.custom_minimum_size = Vector2(260, 48)
	avatar_btn.pressed.connect(_on_avatar)
	main_vbox.add_child(avatar_btn)

	# Volume row
	var vol_row := HBoxContainer.new()
	vol_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vol_row.add_theme_constant_override("separation", 10)
	main_vbox.add_child(vol_row)

	var vol_icon := Label.new()
	vol_icon.text = "Vol"
	vol_icon.add_theme_font_size_override("font_size", 18)
	vol_icon.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	vol_row.add_child(vol_icon)

	vol_slider = HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.value = Constants.master_volume
	vol_slider.custom_minimum_size = Vector2(180, 30)
	vol_slider.value_changed.connect(_on_volume_changed)
	vol_row.add_child(vol_slider)

	vol_label = Label.new()
	vol_label.add_theme_font_size_override("font_size", 18)
	vol_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	vol_label.custom_minimum_size = Vector2(40, 30)
	vol_row.add_child(vol_label)
	_update_vol_label()


func _build_solo_menu(root: VBoxContainer):
	solo_vbox = VBoxContainer.new()
	solo_vbox.add_theme_constant_override("separation", 12)
	root.add_child(solo_vbox)

	var title := Label.new()
	title.text = "PLAY SOLO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	solo_vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	solo_vbox.add_child(spacer)

	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 10)
	solo_vbox.add_child(diff_row)

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

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 6)
	solo_vbox.add_child(spacer2)

	var coinball_btn := Button.new()
	coinball_btn.text = "  CoinBall  "
	coinball_btn.add_theme_font_size_override("font_size", 24)
	coinball_btn.custom_minimum_size = Vector2(260, 52)
	coinball_btn.pressed.connect(_on_play)
	solo_vbox.add_child(coinball_btn)

	var football_btn := Button.new()
	football_btn.text = "  Football  "
	football_btn.add_theme_font_size_override("font_size", 24)
	football_btn.custom_minimum_size = Vector2(260, 52)
	football_btn.pressed.connect(_on_football)
	solo_vbox.add_child(football_btn)

	var volley_btn := Button.new()
	volley_btn.text = "  Volleyball  "
	volley_btn.add_theme_font_size_override("font_size", 24)
	volley_btn.custom_minimum_size = Vector2(260, 52)
	volley_btn.pressed.connect(_on_volleyball)
	solo_vbox.add_child(volley_btn)

	var battle_btn := Button.new()
	battle_btn.text = "  Battle Arena  "
	battle_btn.add_theme_font_size_override("font_size", 24)
	battle_btn.custom_minimum_size = Vector2(260, 52)
	battle_btn.pressed.connect(_on_battle)
	solo_vbox.add_child(battle_btn)

	var curling_btn := Button.new()
	curling_btn.text = "  Curling  "
	curling_btn.add_theme_font_size_override("font_size", 24)
	curling_btn.custom_minimum_size = Vector2(260, 52)
	curling_btn.pressed.connect(_on_curling)
	solo_vbox.add_child(curling_btn)

	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(0, 6)
	solo_vbox.add_child(spacer3)

	var back_btn := Button.new()
	back_btn.text = "  ← Back  "
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.custom_minimum_size = Vector2(260, 44)
	back_btn.pressed.connect(_show_main_menu)
	solo_vbox.add_child(back_btn)

func _show_solo_menu():
	main_vbox.visible = false
	solo_vbox.visible = true

func _show_main_menu():
	solo_vbox.visible = false
	main_vbox.visible = true

func _on_play():
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_football():
	get_tree().change_scene_to_file("res://scenes/game_football.tscn")

func _on_volleyball():
	get_tree().change_scene_to_file("res://scenes/game_volleyball.tscn")

func _on_battle():
	get_tree().change_scene_to_file("res://scenes/game_battle.tscn")

func _on_curling():
	get_tree().change_scene_to_file("res://scenes/game_curling.tscn")

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

func _on_volume_changed(value: float):
	Constants.master_volume = value
	Constants._apply_volume()
	Constants.save_settings()
	_update_vol_label()

func _update_vol_label():
	vol_label.text = "%d%%" % int(Constants.master_volume * 100)
