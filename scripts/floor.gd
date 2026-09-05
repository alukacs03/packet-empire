extends Node2D
## Datacenter floor: iso tiles with subtle variation, a glowing boundary
## around the owned area, and a pulsing hover highlight.

var hover_tile := Vector2i(-1, -1)
var reject_overlay: RejectOverlay
const STARTER_ROOM: Texture2D = preload("res://assets/generated/starter_colo_room.png")
const MATURE_ROOM: Texture2D = preload("res://assets/generated/mature_colo_room.png")
const STARTER_ROOM_RECT := Rect2(-500, -210, 1000, 562)

func _ready() -> void:
	Game.topology_changed.connect(queue_redraw)
	reject_overlay = RejectOverlay.new()
	reject_overlay.z_index = 200
	reject_overlay.z_as_relative = false  # above the cabinets, whatever their own order
	add_child(reject_overlay)

func reject_tile(tile: Vector2i, reason: String) -> void:
	reject_overlay.show_rejection(tile, reason)
	Sfx.play("bad")

var _sound_clock := 0.0

func _process(dt: float) -> void:
	var t := Iso.world_to_tile(get_global_mouse_position())
	if t != hover_tile:
		hover_tile = t
	queue_redraw()  # hover pulse animates continuously
	_sound_clock -= dt
	if _sound_clock > 0.0:
		return
	_sound_clock = 2.5
	var audio: Dictionary = Game.audio_state()
	Sfx.ambient_tick(float(audio["load"]), float(audio["heat"]))
	Sfx.score_tick(Game.score_state())
	# a cue repeats while its condition holds, from the cabinet responsible
	var cues: Array = audio["cues"]
	for cue: String in cues:
		var where: Variant = audio.get("where")
		if cue == "thermal" and where != null:
			Sfx.play_at(cue, self, Iso.tile_to_world(where.tile))
		else:
			Sfx.play(cue)

func _in_grid(t: Vector2i) -> bool:
	var g: Vector2i = Game.grid_size()
	return t.x >= 0 and t.y >= 0 and t.x < g.x and t.y < g.y

func _draw() -> void:
	var grid: Vector2i = Game.grid_size()
	var progress := float(Game.stage) / maxf(float(Game.STAGES.size() - 1), 1.0)
	var facility_accent := UIW.colour("warm").lerp(UIW.colour("accent"), progress)
	_draw_room_atmosphere(grid)
	_draw_reliability_sign(progress)
	_draw_receiving(grid)
	# Build cells are service-floor paint projected over the authored concrete.
	# They never become a second raised board as the facility expands.
	if Game.site_count() > 1:  # which floor am I standing on
		_draw_site_plate(grid)
	for y in grid.y:
		for x in grid.x:
			var t := Vector2i(x, y)
			var v := float((x * 7 + y * 13) % 5) / 5.0 * 0.025
			var c := Color("4b4339").lerp(Color("2b435d"), progress).lightened(v)
			c.a = lerpf(0.14, 0.20, progress)
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
	_draw_season_cast(grid)
	_draw_settled_room(grid)
	_draw_owned_edge(grid, progress)
	_draw_building_exits(grid)
	_draw_housekeeping(grid, progress)

func _draw_owned_edge(grid: Vector2i, progress: float) -> void:
	## Where the owned floor stops is a painted safety line, not an overlay:
	## worn cage yellow while the space is rented, cool aisle white once the
	## facility is purpose-built. Hatching sells it as paint on concrete.
	var corners := [Vector2i(0, 0), Vector2i(grid.x, 0), Vector2i(grid.x, grid.y), Vector2i(0, grid.y)]
	var pts := PackedVector2Array()
	for cnr in corners:
		pts.append(Iso.tile_to_world(cnr) - Vector2(0, Iso.TILE_H / 2.0))
	pts.append(pts[0])
	var paint := Color("d8a33a").lerp(Color("cfe9f5"), progress)
	draw_polyline(pts, Color(paint, 0.10), 9.0)  # the halo the paint throws
	draw_polyline(pts, Color(paint, 0.30), 5.0)  # worn edges of the stripe
	draw_polyline(pts, Color(paint, 0.72), 2.0)  # the stripe itself
	# hazard hatching, leaning into the floor rather than across it
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var span := a.distance_to(b)
		var dir := (b - a) / maxf(span, 1.0)
		var step := 26.0
		var k := step * 0.5
		while k < span:
			var base := a + dir * k
			var lean := Vector2(dir.y, -dir.x) * 7.0 + dir * 5.0
			draw_line(base - lean, base + lean, Color(paint, 0.34), 2.0)
			k += step

func _draw_housekeeping(grid: Vector2i, progress: float) -> void:
	## The state of the floor is the team's habits made visible. Positions are
	## derived from the tile index, so the mess sits still between frames and
	## keeps to the aisle side of a cell rather than under a cabinet.
	var mess := Game.housekeeping_mess()
	if mess <= 0:
		return
	var shade := Color("8a6a3c").lerp(Color("7d8794"), progress)
	for i in mess:
		var t := Vector2i((i * 7 + 3) % maxi(grid.x, 1), (i * 11 + 5) % maxi(grid.y, 1))
		if Game.rack_at(t) != null:
			continue
		var jitter := Vector2(float((i * 13) % 7 - 3) * 5.0, float((i * 5) % 5 - 2) * 3.0)
		var c := Iso.tile_to_world(t) + Vector2(0, Iso.TILE_H * 0.5) + jitter
		# a flat contact shadow, so the thing sits on the slab in the same
		# projection as everything else rather than reading as a floor drain
		var shadow := PackedVector2Array()
		for k in 16:
			var sa := TAU * float(k) / 16.0
			shadow.append(c + Vector2(cos(sa) * 13.0, 3.0 + sin(sa) * 5.0))
		draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.20))
		match i % 3:
			0:  # a coil of patch cable nobody dressed
				for ring in 3:
					var rr := 7.0 + ring * 3.5
					var loop := PackedVector2Array()
					for k in 14:
						var a := TAU * float(k) / 14.0
						loop.append(c + Vector2(cos(a) * rr, sin(a) * rr * 0.5))
					draw_polyline(loop, Color(shade.lightened(0.22), 0.85), 2.0)
			1:  # a flattened carton left where it was opened
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-16, 0), c + Vector2(0, -8),
					c + Vector2(16, 0), c + Vector2(0, 8),
				]), Color(shade, 0.85))
			_:  # a cup, and the ring it will leave
				draw_circle(c + Vector2(0, 2), 6.0, Color(shade.darkened(0.25), 0.35))
				draw_circle(c, 5.0, Color(shade.lightened(0.45), 0.95))

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

class RejectOverlay extends Node2D:
	var tile := Vector2i(-999, -999)
	var reason := ""
	var elapsed := -1.0

	func show_rejection(at: Vector2i, why: String) -> void:
		tile = at
		reason = why
		elapsed = 0.0
		queue_redraw()

	func _process(dt: float) -> void:
		if elapsed < 0.0:
			return
		elapsed += dt
		if elapsed >= 0.62:
			elapsed = -1.0
			reason = ""
		queue_redraw()

	func _draw() -> void:
		if elapsed < 0.0:
			return
		var p := clampf(elapsed / 0.62, 0.0, 1.0)
		var fade := 1.0 - p
		var pulse := 1.0 if Prefs.reduced_motion else 0.72 + 0.28 * sin(p * PI * 3.0)
		var danger := Color(Prefs.bad_colour(), fade * pulse)
		var center := Iso.tile_to_world(tile)
		var points := PackedVector2Array([
			center + Vector2(0, -Iso.TILE_H / 2.0), center + Vector2(Iso.TILE_W / 2.0, 0),
			center + Vector2(0, Iso.TILE_H / 2.0), center + Vector2(-Iso.TILE_W / 2.0, 0)])
		draw_colored_polygon(points, Color(danger, fade * 0.12))
		draw_polyline(points + PackedVector2Array([points[0]]), danger, 2.5)
		draw_line(center + Vector2(-7, -4), center + Vector2(7, 4), danger, 2.0)
		draw_line(center + Vector2(7, -4), center + Vector2(-7, 4), danger, 2.0)
		if elapsed < 0.42:
			draw_string(UIW.mono_font(), center + Vector2(14, -10), reason,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, danger)

func _draw_room_atmosphere(grid: Vector2i) -> void:
	## The facility is a character. Early stages are a rented, warm, slightly
	## unreliable colo; later stages become purpose-built and clinically cool.
	var progress := float(Game.stage) / maxf(float(Game.STAGES.size() - 1), 1.0)
	var warm_room := Color("171516")
	var cold_room := Color("071b30")
	draw_rect(Rect2(-2800, -1800, 5600, 3600), warm_room.lerp(cold_room, progress))
	_draw_floor_slab(grid, progress)
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
		# the bigger room is the same photograph, enlarged to stand around the
		# floor the player actually owns rather than a corner of it
		var mature_level: float = lerpf(float(daylight), 1.0, 0.62)
		draw_texture_rect(MATURE_ROOM, _room_rect_for(grid), false,
			Color(mature_level * 0.96, mature_level, mature_level * 1.04, renovated))

func _room_rect_for(grid: Vector2i) -> Rect2:
	## Grow the authored room with the floor, anchored so its back wall stays
	## behind the top corner of the grid.
	var span := float(maxi(grid.x, grid.y))
	var scale := clampf(span / 3.0, 1.0, 2.9)
	var size := STARTER_ROOM_RECT.size * scale
	var centre := Iso.tile_to_world(Vector2i(int(grid.x / 2), int(grid.y / 2)))
	return Rect2(centre - Vector2(size.x * 0.5, size.y * 0.62), size)

func _floor_corners(grid: Vector2i, margin: float) -> PackedVector2Array:
	## The owned floor as a diamond in world space, with a little apron so the
	## slab reaches past the outermost buildable cell.
	var mx := Iso.TILE_W * 0.5 * margin
	var my := Iso.TILE_H * 0.5 * margin
	var n := Iso.tile_to_world(Vector2i(0, 0)) + Vector2(0, -my)
	var e := Iso.tile_to_world(Vector2i(grid.x - 1, 0)) \
		+ Vector2(mx + Iso.TILE_W * 0.5, Iso.TILE_H * 0.5 + my * 0.5)
	var sth := Iso.tile_to_world(Vector2i(grid.x - 1, grid.y - 1)) \
		+ Vector2(0, Iso.TILE_H + my)
	var w := Iso.tile_to_world(Vector2i(0, grid.y - 1)) \
		+ Vector2(-mx - Iso.TILE_W * 0.5, Iso.TILE_H * 0.5 + my * 0.5)
	return PackedVector2Array([n, e, sth, w])

func _draw_floor_slab(grid: Vector2i, progress: float) -> void:
	## The buildable area always stands on something. Without this, a floor
	## bigger than the authored room leaves the grid hanging over the
	## background, which reads as an interface rather than a room.
	var slab := _floor_corners(grid, 1.4)
	var concrete := Color("2a2622").lerp(Color("39434c"), progress)
	draw_colored_polygon(slab, concrete)
	# a slightly lighter inner field, so the slab has a surface rather than
	# being one flat fill
	var inner := _floor_corners(grid, 0.9)
	draw_colored_polygon(inner, concrete.lightened(0.05))
	var edge := PackedVector2Array(slab)
	edge.append(slab[0])
	draw_polyline(edge, concrete.darkened(0.45), 3.0)

func _draw_site_plate(grid: Vector2i) -> void:
	## With more than one floor, the worst mistake available is doing the right
	## thing in the wrong building. Each site gets a cast of its own, keyed off
	## its name so it is the same every time, and a plate you cannot miss.
	var name := Game.site_name(Game.current_site)
	var hue := Game.site_hue(Game.current_site)
	var cast := Color.from_hsv(hue, 0.55, 0.9, 0.05)
	draw_colored_polygon(_floor_corners(grid, 2.2), cast)
	var font := UIW.mono_font()
	var text_w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var plate := Rect2(Iso.tile_to_world(Vector2i(0, grid.y - 1)) + Vector2(-190, 40),
		Vector2(text_w + 28.0, 30))
	draw_rect(plate, Color(0.02, 0.03, 0.04, 0.72))
	draw_rect(Rect2(plate.position, Vector2(5, plate.size.y)), Color.from_hsv(hue, 0.6, 1.0))
	draw_rect(plate, Color.from_hsv(hue, 0.4, 1.0, 0.55), false, 1.0)
	draw_string(font, plate.position + Vector2(14, 20), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIW.colour("text_strong"))

func _draw_settled_room(grid: Vector2i) -> void:
	## A room that has been run well for a long time looks it: the aisle is
	## marked out properly, the floor has been kept, and somebody has put down
	## the anti-static matting they kept meaning to buy.
	var settled := Game.room_maturity()
	if settled < 0.35:
		return
	var tone := Color(0.68, 0.82, 0.9, 0.06 + 0.10 * settled)
	# a walked aisle down the middle of the floor, worn clean, with the centre
	# line somebody finally got round to painting
	var mid := int(maxi(1, grid.y / 2))
	for x in grid.x:
		_draw_tile(Vector2i(x, mid), tone)
	var from := Iso.tile_to_world(Vector2i(0, mid))
	var to := Iso.tile_to_world(Vector2i(maxi(0, grid.x - 1), mid))
	draw_line(from, to, Color(0.75, 0.85, 0.9, 0.20 + 0.25 * settled), 2.0)
	if settled < 0.5:
		return
	# matting at the head of the aisle, once the place is genuinely kept
	var mat_at := Iso.tile_to_world(Vector2i(0, mid)) + Vector2(-Iso.TILE_W * 0.55, 0)
	var mat := PackedVector2Array([
		mat_at + Vector2(0, -Iso.TILE_H * 0.42), mat_at + Vector2(Iso.TILE_W * 0.42, 0),
		mat_at + Vector2(0, Iso.TILE_H * 0.42), mat_at + Vector2(-Iso.TILE_W * 0.42, 0)])
	draw_colored_polygon(mat, Color(0.10, 0.13, 0.15, 0.55))
	draw_polyline(mat + PackedVector2Array([mat[0]]), Color(0.55, 0.72, 0.78, 0.45), 1.5)

func _draw_building_exits(grid: Vector2i) -> void:
	## A cable to another city has no far end on this screen. Show where it
	## leaves the room, where it is going, and whether the carrier behind it is
	## up, so a digger through a duct is visible here and not only in the log.
	var seen := {}
	for l in Game.links:
		var ra := Game.rack_of(l.a.dev)
		var rb := Game.rack_of(l.b.dev)
		if ra == null or rb == null or ra.site == rb.site:
			continue
		var here: Net.Rack = ra if ra.site == Game.current_site else rb
		var there: Net.Rack = rb if here == ra else ra
		if here.site != Game.current_site:
			continue
		var key := "%s|%d" % [here.name, there.site]
		if seen.has(key):
			continue
		seen[key] = true
		var from := Iso.tile_to_world(here.tile) + Vector2(0, Iso.TILE_H * 0.5)
		var duct := Iso.tile_to_world(Vector2i(0, maxi(0, grid.y - 1))) + Vector2(-96, -26)
		var live := Game.link_capacity(l) > 0
		var col := Color("54d8dc") if live else Color(0.92, 0.42, 0.36)
		draw_polyline(PackedVector2Array([from, from.lerp(duct, 0.5) + Vector2(0, -12), duct]),
			Color(col, 0.75), 2.0)
		# the duct itself: a plate on the wall where the fibre leaves
		draw_rect(Rect2(duct - Vector2(9, 9), Vector2(18, 18)), Color(0.03, 0.05, 0.06, 0.85))
		draw_rect(Rect2(duct - Vector2(9, 9), Vector2(18, 18)), col, false, 1.5)
		draw_line(duct + Vector2(-5, 0), duct + Vector2(5, 0), col, 1.5)
		var label := "→ %s" % Game.site_name(there.site)
		if not live:
			label += "  CARRIER DOWN"
		# right-aligned so it ends at the duct rather than running into the room
		draw_string(UIW.mono_font(), duct + Vector2(-234, 4), label,
			HORIZONTAL_ALIGNMENT_RIGHT, 220, 12, col)

func _draw_season_cast(grid: Vector2i) -> void:
	## A season you can see. Summer hangs warm and close over the floor and
	## puts a borrowed fan by the door; winter reads cold and dry. Spring and
	## autumn are deliberately almost nothing, so the two that matter land.
	var id := String(Game.season()["id"])
	var cast := {
		"summer": Color(1.0, 0.72, 0.38, 0.055),
		"winter": Color(0.62, 0.82, 1.0, 0.055),
		"autumn": Color(0.95, 0.78, 0.52, 0.022),
		"spring": Color(0.86, 0.96, 0.86, 0.018),
	}.get(id, Color(0, 0, 0, 0)) as Color
	if Game.heat_wave():
		cast.a += 0.045
	if cast.a <= 0.0:
		return
	draw_colored_polygon(_floor_corners(grid, 2.4), cast)
	if id != "summer":
		return
	# a floor fan somebody carried in, pointed down the aisle
	var spot := Iso.tile_to_world(Vector2i(0, maxi(0, grid.y - 1))) + Vector2(-74, 26)
	draw_colored_polygon(PackedVector2Array([spot + Vector2(-11, 4), spot + Vector2(11, 4),
		spot + Vector2(8, 10), spot + Vector2(-8, 10)]), Color("2f3339"))
	var blades := PackedVector2Array()
	for k in 18:
		var a := TAU * float(k) / 18.0
		blades.append(spot + Vector2(cos(a) * 15.0, -8.0 + sin(a) * 13.0))
	draw_colored_polygon(blades, Color("454b52"))
	draw_polyline(blades, Color("6c757e"), 1.5)
	draw_line(spot + Vector2(-9, -12), spot + Vector2(9, -4), Color("878f97"), 1.5)
	draw_line(spot + Vector2(-9, -4), spot + Vector2(9, -12), Color("878f97"), 1.5)

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
	var active := Game.customer_down_now()
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
		% Game.best_streak(), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28, 7,
		UIW.colour("muted"))


func _draw_receiving(grid: Vector2i) -> void:
	## Everything here is reading something the simulation already tracks: what
	## is on the dock, what nobody has taken out, and which cabinet is in
	## trouble. No new state, and nothing invented.
	var dock := Iso.tile_to_world(Vector2i(0, maxi(0, grid.y - 1))) + Vector2(-118, 26)
	var waiting: int = Game.crates_waiting().size()
	for i in mini(waiting, 4):
		var at := dock + Vector2(i * 26 - 12, -i * 7)
		# a crate: a flat lid, a body, and a strap, drawn small on purpose
		draw_colored_polygon(PackedVector2Array([at + Vector2(2, 22), at + Vector2(26, 34),
			at + Vector2(50, 22), at + Vector2(26, 10)]), Color(0, 0, 0, 0.28))  # shadow
		draw_colored_polygon(PackedVector2Array([at, at + Vector2(24, 12),
			at + Vector2(24, 30), at + Vector2(0, 18)]), Color("6b563a"))
		draw_colored_polygon(PackedVector2Array([at, at + Vector2(24, 12),
			at + Vector2(48, 0), at + Vector2(24, -12)]), Color("8a7048"))
		draw_line(at + Vector2(6, 8), at + Vector2(30, -4), Color("cbb488"), 1.5)
	for i in mini(Game.packaging, 5):
		# flattened cardboard, lying in the aisle where nobody took it out
		var at2 := dock + Vector2(104 + i * 6, 30 - i * 4)
		var sheet := PackedVector2Array([at2, at2 + Vector2(34, 17),
			at2 + Vector2(16, 26), at2 + Vector2(-18, 9)])
		draw_colored_polygon(sheet, Color("8f7449").lightened(0.05 * i))
		draw_polyline(sheet + PackedVector2Array([at2]), Color("5d4a2c", 0.8), 1.0)
	if Game.aisle_blocked():
		draw_string(ThemeDB.fallback_font, dock + Vector2(-6, 54), "AISLE BLOCKED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.72, 0.45, 0.85))
	# the cabinet itself carries the hazard mark; the floor only shows the tile
	for haz: Dictionary in Game.hazards:
		if int(haz.get("site", 0)) != Game.current_site:
			continue
		var tile := Vector2i(int(haz["tile"][0]), int(haz["tile"][1]))
		var pulse := 0.35 + 0.2 * sin(Time.get_ticks_msec() / 220.0)
		_draw_tile(tile, Color(0.95, 0.45, 0.25, pulse * 0.5) if String(haz["kind"]) != "water"
			else Color(0.35, 0.72, 1.0, pulse * 0.5))
