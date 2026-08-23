extends Camera2D
## Middle/right-drag to pan, scroll to zoom toward cursor.

const ZOOM_STEP := 1.1
const ZOOM_MIN := 0.4
const ZOOM_MAX := 2.5

func _ready() -> void:
	Game.topology_changed.connect(_maybe_refit)
	fit_to_floor()

var _fitted_grid := Vector2i.ZERO

func _maybe_refit() -> void:
	if Game.grid_size() != _fitted_grid:
		fit_to_floor()  # the floor grew: frame the new space

func fit_to_floor() -> void:
	## frame the owned floor with a margin, so a small colo does not sit
	## lost in a sea of black and a full datacenter still fits on screen
	var g: Vector2i = Game.grid_size()
	_fitted_grid = g
	position = Iso.tile_to_world(Vector2i(g.x, g.y)) * 0.5 - Vector2(0, Iso.TILE_H * 0.5)
	var span := Vector2((g.x + g.y) * Iso.TILE_W * 0.5, (g.x + g.y) * Iso.TILE_H * 0.5 + 160.0)
	var vp := get_viewport_rect().size
	var z := minf(vp.x / maxf(span.x + 260.0, 1.0), vp.y / maxf(span.y + 220.0, 1.0))
	zoom = Vector2.ONE * clampf(z, ZOOM_MIN, 1.6)

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
