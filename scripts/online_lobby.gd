extends Control

var status_label: Label
var find_btn: Button
var cancel_btn: Button
var back_btn: Button
var friends_btn: Button
var mode_buttons: Array[Button] = []
var selected_mode_idx: int = 0
var searching := false

const MODE_SCENES := {
	"coinball": "res://scenes/game_online.tscn",
	"football": "res://scenes/game_online_football.tscn",
	"battle": "res://scenes/game_online_battle.tscn",
	"volleyball": "res://scenes/game_online_volleyball.tscn",
	"curling": "res://scenes/game_online_curling.tscn",
}
const MODE_LABELS := ["CoinBall", "Football", "Battle Arena", "Volleyball", "Curling"]
const MODE_KEYS := ["coinball", "football", "battle", "volleyball", "curling"]

const COLOR_SELECTED := Color(1.0, 0.88, 0.25)
const COLOR_UNSELECTED := Color(0.55, 0.55, 0.65)
const COLOR_BG_SELECTED := Color(0.22, 0.20, 0.30)
const COLOR_BG_UNSELECTED := Color(0.12, 0.12, 0.16)

func _ready():
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.10)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "PLAY ONLINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	# Mode buttons row
	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 8)
	vbox.add_child(mode_row)

	var saved_idx := MODE_KEYS.find(Online.selected_mode)
	if saved_idx >= 0:
		selected_mode_idx = saved_idx

	for i in range(MODE_LABELS.size()):
		var btn := Button.new()
		btn.text = "  %s  " % MODE_LABELS[i]
		btn.add_theme_font_size_override("font_size", 17)
		btn.custom_minimum_size = Vector2(0, 38)
		btn.pressed.connect(_on_mode_btn_pressed.bind(i))
		mode_row.add_child(btn)
		mode_buttons.append(btn)

	_update_mode_buttons()

	var spacer1b := Control.new()
	spacer1b.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer1b)

	status_label = Label.new()
	status_label.text = "Ready to play"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	vbox.add_child(status_label)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer2)

	find_btn = Button.new()
	find_btn.text = "  Find Random Match  "
	find_btn.add_theme_font_size_override("font_size", 24)
	find_btn.custom_minimum_size = Vector2(300, 52)
	find_btn.pressed.connect(_on_find_match)
	vbox.add_child(find_btn)

	cancel_btn = Button.new()
	cancel_btn.text = "  Cancel Search  "
	cancel_btn.add_theme_font_size_override("font_size", 20)
	cancel_btn.custom_minimum_size = Vector2(300, 44)
	cancel_btn.visible = false
	cancel_btn.pressed.connect(_on_cancel)
	vbox.add_child(cancel_btn)

	friends_btn = Button.new()
	friends_btn.text = "  Friends (coming soon)  "
	friends_btn.add_theme_font_size_override("font_size", 20)
	friends_btn.custom_minimum_size = Vector2(300, 44)
	friends_btn.disabled = true
	vbox.add_child(friends_btn)

	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer3)

	back_btn = Button.new()
	back_btn.text = "  Back  "
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.custom_minimum_size = Vector2(300, 44)
	back_btn.pressed.connect(_on_back)
	vbox.add_child(back_btn)

	Online.matchmaker_found.connect(_on_matchmaker_found)
	Online.connection_error.connect(_on_error)

	_ensure_connected()

func _on_mode_btn_pressed(idx: int):
	selected_mode_idx = idx
	Online.selected_mode = MODE_KEYS[idx]
	_update_mode_buttons()

func _update_mode_buttons():
	for i in range(mode_buttons.size()):
		var btn: Button = mode_buttons[i]
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 4
		style.content_margin_bottom = 4

		if i == selected_mode_idx:
			style.bg_color = COLOR_BG_SELECTED
			style.border_color = COLOR_SELECTED
			style.border_width_bottom = 3
			btn.add_theme_color_override("font_color", COLOR_SELECTED)
		else:
			style.bg_color = COLOR_BG_UNSELECTED
			style.border_color = Color(0.3, 0.3, 0.38)
			style.border_width_bottom = 1
			btn.add_theme_color_override("font_color", COLOR_UNSELECTED)

		btn.add_theme_stylebox_override("normal", style)

		var hover_style := style.duplicate()
		hover_style.bg_color = COLOR_BG_SELECTED if i == selected_mode_idx else Color(0.16, 0.16, 0.22)
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style := style.duplicate()
		pressed_style.bg_color = Color(0.28, 0.26, 0.36)
		btn.add_theme_stylebox_override("pressed", pressed_style)

func _ensure_connected():
	if Online.user_id == "":
		status_label.text = "Connecting..."
		find_btn.disabled = true
		var ok := await Online.login_device()
		if not ok:
			status_label.text = "Connection failed. Check server."
			return
		status_label.text = "Connected as %s" % Online.display_name
		find_btn.disabled = false

func _on_find_match():
	searching = true
	find_btn.visible = false
	cancel_btn.visible = true
	for btn in mode_buttons:
		btn.disabled = true
	status_label.text = "Searching for %s opponent..." % MODE_LABELS[selected_mode_idx]
	await Online.find_match()

func _on_cancel():
	searching = false
	find_btn.visible = true
	cancel_btn.visible = false
	for btn in mode_buttons:
		btn.disabled = false
	status_label.text = "Ready to play"
	await Online.cancel_matchmaking()

func _on_matchmaker_found(_p_match_id: String, _opp_name: String, _side: String):
	status_label.text = "Match found! Loading..."
	var scene_path: String = MODE_SCENES.get(Online.selected_mode, "res://scenes/game_online.tscn")
	get_tree().change_scene_to_file(scene_path)

func _on_error(msg: String):
	status_label.text = "Error: %s" % msg
	searching = false
	find_btn.visible = true
	cancel_btn.visible = false
	for btn in mode_buttons:
		btn.disabled = false

func _on_back():
	if searching:
		await Online.cancel_matchmaking()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
