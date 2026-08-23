class_name Iso
## Isometric grid math. One source of truth for tile <-> world conversion.

const TILE_W := 128.0  # on-screen width of one floor tile
const TILE_H := 64.0   # on-screen height (2:1 iso)

static func tile_to_world(t: Vector2i) -> Vector2:
	return Vector2((t.x - t.y) * TILE_W / 2.0, (t.x + t.y) * TILE_H / 2.0)

static func world_to_tile(w: Vector2) -> Vector2i:
	var x := w.x / (TILE_W / 2.0)
	var y := w.y / (TILE_H / 2.0)
	return Vector2i(floori((x + y) / 2.0), floori((y - x) / 2.0))
