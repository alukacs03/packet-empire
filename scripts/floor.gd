extends Node2D
## Draws the datacenter floor: iso tile grid with a hovered-tile highlight.

const GRID_W := 12
const GRID_H := 12

var hover_tile := Vector2i(-1, -1)

func _process(_dt: float) -> void:
	var t := Iso.world_to_tile(get_global_mouse_position())
	if t != hover_tile:
		hover_tile = t
		queue_redraw()

func _draw() -> void:
	for y in GRID_H:
		for x in GRID_W:
			var t := Vector2i(x, y)
			var c := Color(0.16, 0.18, 0.23) if (x + y) % 2 == 0 else Color(0.14, 0.16, 0.21)
			if t == hover_tile:
				c = Color(0.25, 0.45, 0.55)
			_draw_tile(t, c)

func _draw_tile(t: Vector2i, color: Color) -> void:
	var c := Iso.tile_to_world(t)
	var pts := PackedVector2Array([
		c + Vector2(0, -Iso.TILE_H / 2.0),
		c + Vector2(Iso.TILE_W / 2.0, 0),
		c + Vector2(0, Iso.TILE_H / 2.0),
		c + Vector2(-Iso.TILE_W / 2.0, 0),
	])
	draw_colored_polygon(pts, color)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.3, 0.34, 0.42, 0.6), 1.5)
