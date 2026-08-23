extends Camera2D
## Middle/right-drag to pan, scroll to zoom toward cursor.

const ZOOM_STEP := 1.1
const ZOOM_MIN := 0.4
const ZOOM_MAX := 2.5

func _ready() -> void:
	position = Iso.tile_to_world(Vector2i(6, 6))

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and (e.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)):
		position -= e.relative / zoom
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(e.position, ZOOM_STEP)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(e.position, 1.0 / ZOOM_STEP)

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := get_canvas_transform().affine_inverse() * screen_pos
	zoom = (zoom * factor).clamp(Vector2.ONE * ZOOM_MIN, Vector2.ONE * ZOOM_MAX)
	var after := get_canvas_transform().affine_inverse() * screen_pos
	position += before - after
