extends Control

var avatar_textures: Array[Texture2D] = []
var buttons: Array[TextureButton] = []
var selected_idx: int = 0

func _ready():
	selected_idx = Constants.player_avatar_idx

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.10)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "Choose Your Avatar"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.set_anchors_preset(PRESET_TOP_WIDE)
	title.size = Vector2(0, 50)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	add_child(title)

	_build_avatar_grid()

	var back_btn := Button.new()
	back_btn.text = "  Back  "
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.custom_minimum_size = Vector2(200, 48)
	var vp_size := get_viewport().get_visible_rect().size
	back_btn.position = Vector2((vp_size.x - 200) / 2.0, vp_size.y - 60)
	back_btn.pressed.connect(_on_back)
	add_child(back_btn)

func _build_avatar_grid():
	var count := Constants.AVATAR_COUNT

	var cols_per_row := 6
	var btn_size := 90.0
	var spacing := 12.0
	var grid_w: float = cols_per_row * (btn_size + spacing) - spacing
	var total_rows := ceili(float(count) / cols_per_row)
	var grid_h: float = total_rows * (btn_size + spacing) - spacing
	var vp := get_viewport().get_visible_rect().size
	var offset_x: float = (vp.x - grid_w) / 2.0
	var offset_y: float = (vp.y - grid_h) / 2.0 + 15.0

	for i in range(count):
		var tex: Texture2D = load(Constants.AVATAR_DIR + "avatar_%02d.png" % i)
		avatar_textures.append(tex)

		var row := i / cols_per_row
		var col := i % cols_per_row
		var bx: float = offset_x + col * (btn_size + spacing)
		var by: float = offset_y + row * (btn_size + spacing)
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		
		

		var btn := TextureButton.new()
		btn.texture_normal = tex
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = Vector2(btn_size, btn_size)
		btn.position = Vector2(bx, by)
		btn.size = Vector2(btn_size, btn_size)
		btn.pressed.connect(_on_avatar_pressed.bind(i))
		add_child(btn)
		buttons.append(btn)

	_update_selection_highlight()

func _on_avatar_pressed(idx: int):
	selected_idx = idx
	Constants.player_avatar_idx = idx
	Constants.save_settings()

	_update_selection_highlight()

func _update_selection_highlight():
	for i in range(buttons.size()):
		if i == selected_idx:
			buttons[i].modulate = Color.WHITE
			buttons[i].self_modulate = Color.WHITE
		else:
			buttons[i].modulate = Color(0.6, 0.6, 0.6, 0.8)

func _on_back():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
