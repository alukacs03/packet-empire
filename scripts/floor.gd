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
		var anchor := Iso.tile_to_world(Vector2i(0, grid.y)) + Vector2(-60, 40)
		draw_string(ThemeDB.fallback_font, anchor, Game.site_name(Game.current_site),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIW.colour("accent"))
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
	# glowing boundary of the owned floor
	var corners := [Vector2i(0, 0), Vector2i(grid.x, 0), Vector2i(grid.x, grid.y), Vector2i(0, grid.y)]
	var pts := PackedVector2Array()
	for cnr in corners:
		pts.append(Iso.tile_to_world(cnr) - Vector2(0, Iso.TILE_H / 2.0))
	pts.append(pts[0])
	draw_polyline(pts, Color(facility_accent, 0.11), 7.0)
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
