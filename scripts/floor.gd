extends Node2D
## Datacenter floor: iso tiles with subtle variation, a glowing boundary
## around the owned area, and a pulsing hover highlight.

var hover_tile := Vector2i(-1, -1)
const STARTER_ROOM: Texture2D = preload("res://assets/generated/starter_colo_room.png")
const MATURE_ROOM: Texture2D = preload("res://assets/generated/mature_colo_room.png")
const STARTER_ROOM_RECT := Rect2(-500, -210, 1000, 562)

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
	var progress := float(Game.stage) / maxf(float(Game.STAGES.size() - 1), 1.0)
	var facility_accent := UIW.colour("warm").lerp(UIW.colour("accent"), progress)
	_draw_room_atmosphere(grid)
	_draw_reliability_sign(progress)
	# The room is a raised, lit platform instead of a black void. The lower lip
	# and cast shadow make the buildable area read as a tangible toy-board.
	var deck := PackedVector2Array([
		Iso.tile_to_world(Vector2i(0, 0)) - Vector2(0, Iso.TILE_H / 2.0),
		Iso.tile_to_world(Vector2i(grid.x, 0)) - Vector2(0, Iso.TILE_H / 2.0),
		Iso.tile_to_world(Vector2i(grid.x, grid.y)) - Vector2(0, Iso.TILE_H / 2.0),
		Iso.tile_to_world(Vector2i(0, grid.y)) - Vector2(0, Iso.TILE_H / 2.0),
	])
	if progress >= 0.42:
		var shadow := PackedVector2Array()
		for p in deck:
			shadow.append(p + Vector2(14, 22))
		draw_colored_polygon(shadow, Color(0.015, 0.035, 0.075, 0.58))
		var south := deck[2]
		var west := deck[3]
		draw_colored_polygon(PackedVector2Array([deck[1], south, south + Vector2(0, 15), deck[1] + Vector2(0, 15)]), Color("322b25").lerp(Color("142b48"), progress))
		draw_colored_polygon(PackedVector2Array([south, west, west + Vector2(0, 15), south + Vector2(0, 15)]), Color("211d1b").lerp(Color("0d213b"), progress))
	if Game.site_count() > 1:  # which floor am I standing on
		var anchor := Iso.tile_to_world(Vector2i(0, grid.y)) + Vector2(-60, 40)
		draw_string(ThemeDB.fallback_font, anchor, Game.site_name(Game.current_site),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIW.colour("accent"))
	for y in grid.y:
		for x in grid.x:
			var t := Vector2i(x, y)
			var v := float((x * 7 + y * 13) % 5) / 5.0 * 0.025
			var c := Color("4b4339").lerp(Color("2b435d"), progress).lightened(v)
			if progress < 0.42:
				c.a = 0.16
			if (x + y) % 2 == 0:
				c = c.lightened(0.075)
			_draw_tile(t, c)
			# Cyan service channels and amber aisle ticks make the floor feel
			# planned and operational while preserving clear placement cells.
			if x == 0 and y % 2 == 0:
				var c0 := Iso.tile_to_world(t)
				draw_line(c0 + Vector2(-20, 0), c0 + Vector2(-7, 6), Color(facility_accent, 0.72), 2.5)
	_draw_room_lighting(grid)
	# pulsing hover
	if _in_grid(hover_tile):
		var pulse := 0.35 + 0.2 * sin(Time.get_ticks_msec() / 280.0)
		_draw_tile(hover_tile, Color(UIW.colour("accent"), pulse))
		_outline(hover_tile, UIW.colour("focus"), 2.5)
	# glowing boundary of the owned floor
	var corners := [Vector2i(0, 0), Vector2i(grid.x, 0), Vector2i(grid.x, grid.y), Vector2i(0, grid.y)]
	var pts := PackedVector2Array()
	for cnr in corners:
		pts.append(Iso.tile_to_world(cnr) - Vector2(0, Iso.TILE_H / 2.0))
	pts.append(pts[0])
	draw_polyline(pts, Color(facility_accent, 0.16), 12.0)
	draw_polyline(pts, Color(facility_accent, 0.78), 2.5)

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
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.48, 0.65, 0.78, 0.40), 1.0)
	# A small specular edge catches the room lighting without obscuring racks.
	draw_line(pts[0], pts[1], Color(0.73, 0.86, 0.92, 0.18), 1.0)

func _outline(t: Vector2i, color: Color, w: float) -> void:
	var pts := _tile_points(t)
	draw_polyline(pts + PackedVector2Array([pts[0]]), color, w)

func _draw_room_atmosphere(grid: Vector2i) -> void:
	## The facility is a character. Early stages are a rented, warm, slightly
	## unreliable colo; later stages become purpose-built and clinically cool.
	var progress := float(Game.stage) / maxf(float(Game.STAGES.size() - 1), 1.0)
	var warm_room := Color("171516")
	var cold_room := Color("071b30")
	draw_rect(Rect2(-2800, -1800, 5600, 3600), warm_room.lerp(cold_room, progress))
	# Cross-fading two matching authored rooms turns progression into a physical
	# renovation: clutter and amber hum gradually yield to cold, managed calm.
	var renovated := smoothstep(0.12, 0.88, progress)
	var slot := Game.day_slot()
	var daylight: float = [0.68, 0.80, 0.96, 1.0, 0.98, 0.90, 0.78, 0.66][slot]
	var clock := Time.get_ticks_msec() / 1000.0
	var old_fixture := 0.97 + 0.025 * sin(clock * 8.3) + 0.012 * sin(clock * 19.7)
	if fmod(clock, 7.1) < 0.075:
		old_fixture = 0.72
	var starter_level: float = lerpf(float(daylight), 1.0, 0.30) * old_fixture
	draw_texture_rect(STARTER_ROOM, STARTER_ROOM_RECT, false,
		Color(starter_level, starter_level, starter_level * 0.96, 1.0 - renovated))
	if renovated > 0.0:
		var mature_level: float = lerpf(float(daylight), 1.0, 0.62)
		draw_texture_rect(MATURE_ROOM, STARTER_ROOM_RECT, false,
			Color(mature_level * 0.96, mature_level, mature_level * 1.04, renovated))

func _draw_room_lighting(grid: Vector2i) -> void:
	var progress := float(Game.stage) / maxf(float(Game.STAGES.size() - 1), 1.0)
	var clock := Time.get_ticks_msec() / 1000.0
	var warm := Color("ffad5c")
	var cold := Color("9cecff")
	var light_col := warm.lerp(cold, progress)
	var fixtures := [Vector2(-138, 62), Vector2(138, 62)] if progress < 0.42 else [
		Iso.tile_to_world(Vector2i(0, 0)),
		Iso.tile_to_world(Vector2i(maxi(0, grid.x - 1), maxi(0, grid.y - 1))),
	]
	for i in fixtures.size():
		var center: Vector2 = fixtures[i]
		var instability := (1.0 - progress) * (0.78 + 0.15 * sin(clock * 7.0 + i * 2.1))
		if progress < 0.35 and fmod(clock + i * 0.61, 5.7) < 0.10:
			instability *= 0.18
		for layer in 7:
			var fade := 1.0 - float(layer) / 7.0
			var radius_x := 48.0 + layer * 22.0
			var radius_y := 20.0 + layer * 8.0
			var glow := PackedVector2Array()
			for k in 24:
				var a := TAU * float(k) / 24.0
				glow.append(center + Vector2(cos(a) * radius_x, sin(a) * radius_y))
			draw_colored_polygon(glow, Color(light_col, (0.010 + instability * 0.012) * fade))

func _draw_reliability_sign(progress: float) -> void:
	## A cheap wall-mounted counter that becomes part of the room's emotional
	## weather. It is deliberately not a HUD stat: the team has to walk past it.
	var rect := Rect2(-286, -136, 174, 70)
	var accent := UIW.colour("warm").lerp(UIW.colour("accent"), progress)
	var active := Game.customer_outage_active
	if active:
		accent = Color("ff5b50")
	var clock := Time.get_ticks_msec() / 1000.0
	var pulse := 0.42 + 0.14 * sin(clock * 8.0) if active else 0.20
	# Warm bloom against the old concrete; the upgraded sign becomes a tighter,
	# cooler lightbox as the facility matures.
	draw_rect(rect.grow(10), Color(accent, pulse * (1.0 - progress * 0.45)))
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(0.01, 0.015, 0.02, 0.58))
	draw_rect(rect, Color("211d1a").lerp(Color("0b1b2b"), progress))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4)), accent)
	draw_rect(rect, Color(accent, 0.68), false, 1.2)
	# Slightly overbuilt corner fasteners sell it as an object bolted to the wall.
	for screw in [rect.position + Vector2(7, 9), Vector2(rect.end.x - 7, rect.position.y + 9),
		Vector2(rect.position.x + 7, rect.end.y - 7), rect.end - Vector2(7, 7)]:
		draw_circle(screw, 1.8, Color("9b8872").lerp(Color("8eb8c9"), progress))
	var title := "CUSTOMER OUTAGE ACTIVE" if active else "NO CUSTOMER OUTAGE"
	draw_string(UIW.mono_font(), rect.position + Vector2(14, 19), title,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28, 9, accent)
	var streak := 0 if active else Game.cycles_since_customer_outage()
	draw_string(UIW.mono_font(), rect.position + Vector2(14, 47), "%03d" % streak,
		HORIZONTAL_ALIGNMENT_LEFT, 72, 23, UIW.colour("text_strong"))
	draw_string(UIW.mono_font(), rect.position + Vector2(94, 45), "CYCLES",
		HORIZONTAL_ALIGNMENT_LEFT, 64, 13, UIW.colour("text_strong"))
	draw_string(UIW.mono_font(), rect.position + Vector2(14, 61), "BEST %03d  ·  LIVE CUSTOMERS" \
		% Game.best_outage_streak, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28, 7,
		UIW.colour("muted"))
