extends Node2D
## Datacenter floor: iso tiles with subtle variation, a glowing boundary
## around the owned area, and a pulsing hover highlight.

var hover_tile := Vector2i(-1, -1)

func _ready() -> void:
	Game.topology_changed.connect(queue_redraw)

func _process(_dt: float) -> void:
	var t := Iso.world_to_tile(get_global_mouse_position())
	if t != hover_tile:
		hover_tile = t
	queue_redraw()  # hover pulse animates continuously

func _in_grid(t: Vector2i) -> bool:
	var g: Vector2i = Game.grid_size()
	return t.x >= 0 and t.y >= 0 and t.x < g.x and t.y < g.y

func _draw() -> void:
	var grid: Vector2i = Game.grid_size()
	if Game.site_count() > 1:  # which floor am I standing on
		var anchor := Iso.tile_to_world(Vector2i(0, grid.y)) + Vector2(-60, 40)
		draw_string(ThemeDB.fallback_font, anchor, Game.site_name(Game.current_site),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.45, 0.7, 0.8, 0.8))
	for y in grid.y:
		for x in grid.x:
			var t := Vector2i(x, y)
			var v := float((x * 7 + y * 13) % 5) / 5.0 * 0.014  # concrete variation
			var c := Color(0.145 + v, 0.16 + v, 0.205 + v)
			if (x + y) % 2 == 0:
				c = c.lightened(0.05)
			_draw_tile(t, c)
	# pulsing hover
	if _in_grid(hover_tile):
		var pulse := 0.35 + 0.2 * sin(Time.get_ticks_msec() / 280.0)
		_draw_tile(hover_tile, Color(0.3, 0.62, 0.75, pulse))
		_outline(hover_tile, Color(0.55, 0.9, 1.0, 0.9), 2.0)
	# faint tease of the floor space the next stage unlocks (your own floor only)
	if Game.current_site == 0 and Game.stage < Game.STAGES.size() - 1:
		var nxt: Vector2i = Game.STAGES[Game.stage + 1]["grid"]
		for y in nxt.y:
			for x in nxt.x:
				if x < grid.x and y < grid.y:
					continue
				var pts_n := _tile_points(Vector2i(x, y))
				draw_polyline(pts_n + PackedVector2Array([pts_n[0]]), Color(0.3, 0.4, 0.5, 0.10), 1.0)
	# glowing boundary of the owned floor
	var corners := [Vector2i(0, 0), Vector2i(grid.x, 0), Vector2i(grid.x, grid.y), Vector2i(0, grid.y)]
	var pts := PackedVector2Array()
	for cnr in corners:
		pts.append(Iso.tile_to_world(cnr) - Vector2(0, Iso.TILE_H / 2.0))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.3, 0.75, 0.85, 0.10), 10.0)
	draw_polyline(pts, Color(0.4, 0.85, 0.95, 0.45), 2.0)

func _tile_points(t: Vector2i) -> PackedVector2Array:
	var c := Iso.tile_to_world(t)
	return PackedVector2Array([
		c + Vector2(0, -Iso.TILE_H / 2.0),
		c + Vector2(Iso.TILE_W / 2.0, 0),
		c + Vector2(0, Iso.TILE_H / 2.0),
		c + Vector2(-Iso.TILE_W / 2.0, 0),
	])

func _draw_tile(t: Vector2i, color: Color) -> void:
	var pts := _tile_points(t)
	draw_colored_polygon(pts, color)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.28, 0.32, 0.4, 0.35), 1.0)

func _outline(t: Vector2i, color: Color, w: float) -> void:
	var pts := _tile_points(t)
	draw_polyline(pts + PackedVector2Array([pts[0]]), color, w)
