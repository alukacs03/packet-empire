## PACKET_FILM=<dir>: record the game running, one JPEG per rendered frame,
## with a caption naming what is on screen. Scenes are the same fixtures the
## screenshot harness uses, held long enough for the room to move: people walk,
## lights blink, packets travel, so the result is footage rather than a slideshow.
##
## ffmpeg turns the frames into a video; nothing here encodes anything.

const FPS := 30
static var _frame := 0
static var _dir := ""
static var caption_title: Label = null
static var caption_body: Label = null

static func active() -> bool:
	return OS.get_environment("PACKET_FILM") != ""

static func _install_caption(world: Node) -> void:
	## A caption strip along the bottom, over everything, so a viewer knows what
	## they are looking at without a voice-over.
	var layer := CanvasLayer.new()
	layer.layer = 200
	world.add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.position = Vector2(0, -96)
	panel.custom_minimum_size = Vector2(0, 96)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.06, 0.86)
	style.border_color = Color(0.33, 0.85, 0.86, 0.85)
	style.border_width_top = 2
	style.content_margin_left = 44.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	caption_title = Label.new()
	caption_title.add_theme_font_size_override("font_size", 26)
	caption_title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	box.add_child(caption_title)
	caption_body = Label.new()
	caption_body.add_theme_font_size_override("font_size", 16)
	caption_body.add_theme_color_override("font_color", Color(0.62, 0.78, 0.86))
	box.add_child(caption_body)

static func say(title: String, body: String) -> void:
	if caption_title:
		caption_title.text = title
	if caption_body:
		caption_body.text = body

static func _capture(world: Node) -> void:
	var img := world.get_viewport().get_texture().get_image()
	img.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	img.save_jpg("%s/f%05d.jpg" % [_dir, _frame], 0.86)
	_frame += 1

static func hold(world: Node, seconds: float) -> void:
	## Let the world run and record every frame of it. Anything that wants to
	## introduce itself over the shot is dismissed first.
	var ui = world.get("ui")
	if ui != null and ui.has_method("_dismiss_unlock_intro"):
		ui._dismiss_unlock_intro()
	var frames := int(seconds * FPS)
	for i in frames:
		await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		_capture(world)

static func begin(dir: String) -> void:
	_dir = dir
	_frame = 0
	DirAccess.make_dir_recursive_absolute(dir)

static func frames() -> int:
	return _frame
