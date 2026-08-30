class_name RackVisual
extends Node2D
## Isometric rack cabinet: drop shadow, gradient faces, per-device front
## strips with blinking activity LEDs, name badge.

const H := 104.0
const W := 0.86

var rack: Net.Rack
var base_position := Vector2.ZERO
var arriving := false
var arrival_elapsed := 0.0
var highlighted := false:
	set(v):
		highlighted = v
		queue_redraw()

func setup(r: Net.Rack, play_arrival := false) -> RackVisual:
	rack = r
	r.visual = self
	base_position = Iso.tile_to_world(r.tile)
	position = base_position
	z_index = r.tile.x + r.tile.y + 1
	if play_arrival:
		begin_arrival()
	return self

func begin_arrival() -> void:
	arriving = true
	arrival_elapsed = 0.0
	modulate = Color(1, 1, 1, 0.35)
	queue_redraw()

func top_anchor() -> Vector2:
	return position + Vector2(0, -H)

func _process(dt: float) -> void:
	if arriving:
		arrival_elapsed += dt
		var duration := 0.28 if Prefs.reduced_motion else 0.58
		var p := clampf(arrival_elapsed / duration, 0.0, 1.0)
		modulate.a = lerpf(0.35, 1.0, minf(p * 2.2, 1.0))
		if Prefs.reduced_motion:
			position = base_position
			scale = Vector2.ONE
		else:
			var settle := 1.0 - pow(1.0 - p, 3.0)
			position = base_position + Vector2(0, -34.0 * (1.0 - settle))
			var impact := maxf(0.0, 1.0 - absf(p - 0.78) / 0.13)
			scale = Vector2(1.0 + impact * 0.025, 1.0 - impact * 0.045)
		queue_redraw()
		if p >= 1.0:
			arriving = false
			position = base_position
			scale = Vector2.ONE
			modulate = Color.WHITE
	if highlighted:
		queue_redraw()
		return
	for d in rack.slots:
		if d != null:
			queue_redraw()  # LEDs blink
			return

func _dev_color(dev: Net.NDevice) -> Color:
	return UIW.TYPE_COLORS.get(dev.type, UIW.TYPE_COLORS["server"])

func _front_point(s: Vector2, e: Vector2, up: Vector2, x: float, y: float) -> Vector2:
	return s.lerp(e, x) + up * y

func _front_quad(s: Vector2, e: Vector2, up: Vector2, x0: float, x1: float,
		y0: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([
		_front_point(s, e, up, x0, y0), _front_point(s, e, up, x1, y0),
		_front_point(s, e, up, x1, y1), _front_point(s, e, up, x0, y1),
	])

const LEAD_COLOURS := [Color("2f6f8f"), Color("8a5a3c"), Color("5f7a3c"), Color("7a3c58")]

func _draw_loose_leads(e: Vector2, s: Vector2, up: Vector2) -> void:
	## A cabinet nobody dresses wears it: patch leads left hanging down the
	## side, as many as the tidiness score is short by. Everything is derived
	## from the cabinet name, so the mess stands still.
	var slack := 1.0 - Game.rack_tidiness(rack)
	var count := int(round(clampf(slack, 0.0, 1.0) * 5.0))
	if count <= 0:
		return
	var seed_h := hash(rack.name)
	for i in count:
		var h := (seed_h >> (i * 3)) & 0xff
		# down the near-right face, clear of the badge and the note tab
		var along := 0.22 + float(h % 5) * 0.14
		var top := (s.lerp(e, along)) + up * (0.32 + float((h >> 3) % 4) * 0.11)
		var drop := 16.0 + float((h >> 5) % 5) * 7.0
		var sway := 5.0 + float(h % 4) * 3.5
		var col: Color = LEAD_COLOURS[(h + i) % LEAD_COLOURS.size()]
		var curve := PackedVector2Array()
		for k in 7:
			var t := float(k) / 6.0
			curve.append(top + Vector2(sway * sin(t * PI) * (1.0 if i % 2 == 0 else -1.0),
				drop * t))
		draw_polyline(curve, Color(col, 0.85), 1.6)
		draw_circle(curve[curve.size() - 1], 1.4, Color(col.lightened(0.25), 0.9))

func _draw() -> void:
	var progress := float(Game.stage) / maxf(float(Game.STAGES.size() - 1), 1.0)
	var base := Color("493f3a").lerp(Color("294b67"), progress)
	var ex := Iso.TILE_W / 2.0 * W
	var ey := Iso.TILE_H / 2.0 * W
	var n := Vector2(0, -ey)
	var e := Vector2(ex, 0)
	var s := Vector2(0, ey)
	var w := Vector2(-ex, 0)
	var up := Vector2(0, -H)
	if arriving:
		var duration := 0.28 if Prefs.reduced_motion else 0.58
		var arrival_p := clampf(arrival_elapsed / duration, 0.0, 1.0)
		var contact := clampf((arrival_p - 0.58) / 0.42, 0.0, 1.0)
		if contact > 0.0:
			var ring := PackedVector2Array()
			for p in [n, e, s, w, n]:
				ring.append(p * lerpf(0.72, 1.28, contact))
			draw_polyline(ring, Color(UIW.colour("warm"), (1.0 - contact) * 0.72), 2.0)
	# Layered contact shadow and small levelling feet anchor the cabinet to the
	# concrete instead of making it hover above the room illustration.
	var sh := PackedVector2Array()
	for p in [n, e, s, w]:
		sh.append(p * 1.30 + Vector2(6, 5))
	draw_colored_polygon(sh, Color(0.005, 0.008, 0.01, 0.30))
	draw_colored_polygon(PackedVector2Array([w * 1.04, e * 1.04, s * 1.08, w]),
		Color(0.005, 0.008, 0.01, 0.40))
	for foot in [w.lerp(s, 0.16), s.lerp(e, 0.16), s.lerp(e, 0.84)]:
		draw_line(foot + Vector2(0, -2), foot + Vector2(0, 4), Color("11171b"), 4.0)
		draw_line(foot + Vector2(-3, 4), foot + Vector2(3, 4), Color("050709"), 2.0)
	# cabinet
	var side_col := Color("211e1b").lerp(Color("10283c"), progress)
	var frame_col := Color("3b3530").lerp(Color("27475f"), progress)
	draw_colored_polygon(PackedVector2Array([w, s, s + up, w + up]), side_col)
	draw_colored_polygon(PackedVector2Array([s, e, e + up, s + up]), frame_col)
	draw_colored_polygon(PackedVector2Array([n + up, e + up, s + up, w + up]),
		Color("65594d").lerp(Color("385f78"), progress))
	# top edge highlight
	draw_polyline(PackedVector2Array([w + up, n + up, e + up, s + up]),
		Color(0.72, 0.80, 0.82, 0.56), 1.25)
	# A stamped cap seam and exhaust grille give the top actual construction.
	draw_polyline(PackedVector2Array([
		(w + up).lerp(n + up, 0.18), (n + up).lerp(e + up, 0.18),
		(e + up).lerp(s + up, 0.18)]), Color(0.08, 0.10, 0.11, 0.50), 1.0)
	for grille in 3:
		var gy := 0.36 + grille * 0.12
		draw_line((w + up).lerp(n + up, gy).lerp((s + up).lerp(e + up, gy), 0.38),
			(w + up).lerp(n + up, gy).lerp((s + up).lerp(e + up, gy), 0.64),
			Color(0.05, 0.07, 0.08, 0.62), 1.0)
	# vertical frame rails silhouette the cabinet at game zoom.
	draw_line(s + Vector2(1, -3), s + up + Vector2(1, 3), Color("5b7890"), 2.2)
	draw_line(e + Vector2(-1, -2), e + up + Vector2(-1, 2), Color("182c42"), 2.2)
	# Recess the front face so the silhouette reads like a cabinet, not a box.
	var front_inset := _front_quad(s, e, up, 0.07, 0.93, 0.07, 0.95)
	draw_colored_polygon(front_inset, Color("0b1014"))
	draw_polyline(front_inset + PackedVector2Array([front_inset[0]]), Color(0.78, 0.62, 0.44, 0.28).lerp(Color(UIW.colour("border_strong"), 0.48), progress), 1.0)
	# Raised rack rails, complete with fastening holes. These stay visible around
	# equipment and make the face read as a real 19-inch cabinet.
	for rail_x in [0.075, 0.885]:
		draw_colored_polygon(_front_quad(s, e, up, rail_x, rail_x + 0.04, 0.08, 0.94),
			Color("364047").lerp(Color("42647a"), progress))
		for hole in Net.Rack.SLOTS:
			var hy := 0.125 + float(hole) / Net.Rack.SLOTS * 0.78
			draw_circle(_front_point(s, e, up, rail_x + 0.02, hy), 0.85, Color("070a0c"))
	# left-face vents
	var side_inset := PackedVector2Array([
		w.lerp(s, 0.10) + up * 0.09, w.lerp(s, 0.90) + up * 0.09,
		w.lerp(s, 0.90) + up * 0.91, w.lerp(s, 0.10) + up * 0.91])
	draw_polyline(side_inset + PackedVector2Array([side_inset[0]]), Color(0.52, 0.48, 0.42, 0.22), 1.0)
	for k in 6:
		var f := 0.18 + k * 0.115
		draw_line(lerp(w, s, 0.25) + up * f, lerp(w, s, 0.74) + up * f,
			Color(0.03, 0.035, 0.04, 0.72), 1.0)
	# Starter cabinets are visibly second-hand; later facilities replace the
	# scuffs with a clean illuminated asset rail.
	if progress < 0.45:
		for scratch in 4:
			var y := -22.0 - scratch * 17.0
			draw_line(Vector2(-ex * 0.82, y), Vector2(-ex * (0.42 + scratch * 0.06), y + 4), Color(0.82, 0.62, 0.42, 0.24), 1.0)
	else:
		draw_line(w + up + Vector2(3, 7), s + up + Vector2(-3, 7), Color(UIW.colour("accent"), 0.65), 2.0)
	# front slots, bottom = U1
	var tms := Time.get_ticks_msec()
	for i in Net.Rack.SLOTS:
		var frac := 0.08 + float(i) / Net.Rack.SLOTS * 0.84
		var lo := _front_point(s, e, up, 0.12, frac)
		var hi := _front_point(s, e, up, 0.88, frac)
		var dev: Net.NDevice = rack.slots[i]
		if dev:
			var col := _dev_color(dev)
			if dev.status != "active":
				col = Color(0.35, 0.3, 0.3)
			var height := 0.075
			var lo2 := _front_point(s, e, up, 0.12, frac + height)
			var hi2 := _front_point(s, e, up, 0.88, frac + height)
			var plate := PackedVector2Array([lo, hi, hi2, lo2])
			draw_colored_polygon(plate, Color("182027") if dev.status == "active" else Color("292326"))
			draw_line(lo, hi, Color(0.70, 0.74, 0.74, 0.50), 1.0)
			draw_line(lo, lo2, col, 2.6)
			# Ports and fan perforations are small, but they stop hardware reading as
			# a stack of coloured status bars at room scale.
			for detail in 4:
				var x := 0.34 + detail * 0.10
				var p := lo.lerp(hi, x) + (lo2 - lo) * 0.52
				draw_rect(Rect2(p - Vector2(1.8, 1.1), Vector2(3.6, 2.2)), col.darkened(0.22))
			# activity LED: green blink when linked, red when offline
			var linked := false
			for ifc: Net.Iface in dev.ifaces:
				if Game.link_at(ifc):
					linked = true
					break
			var led := Color(0.25, 0.25, 0.25)
			if dev.status != "active":
				led = Color(0.9, 0.3, 0.2)
			elif linked and fmod(tms / 1000.0 * (1.4 + i * 0.31), 1.0) > 0.35:
				led = Color(0.4, 1.0, 0.5)
			var mid_lo := lerp(lo, hi, 0.88)
			var mid_hi := lerp(lo2, hi2, 0.88)
			draw_circle(mid_lo + (mid_hi - mid_lo) * 0.5, 1.8, led)
		elif rack.blanked.has(i):
			var blank := _front_quad(s, e, up, 0.12, 0.88, frac + 0.006, frac + 0.069)
			draw_colored_polygon(blank, Color("303a3f").lerp(Color("344e5e"), progress))
			for rib in 3:
				var ry := frac + 0.018 + rib * 0.015
				draw_line(_front_point(s, e, up, 0.17, ry), _front_point(s, e, up, 0.83, ry),
					Color(0.62, 0.67, 0.68, 0.28), 0.8)
		else:
			draw_line(lo, hi, Color(0.28, 0.32, 0.34, 0.58), 0.8)
	# somebody else's kit, still wearing their asset tag
	var inherited := ""
	for slot_dev in rack.slots:
		if slot_dev != null and String(slot_dev.acquired_from) != "":
			inherited = String(slot_dev.acquired_from)
			break
	if inherited != "":
		var tag := Rect2(Vector2(-4, -H + 34), Vector2(22, 9))
		draw_rect(tag, Color("d9c27a"))
		draw_rect(tag, Color("6b5a2c"), false, 1.0)
		draw_line(tag.position + Vector2(3, 4), tag.position + Vector2(19, 4),
			Color("6b5a2c"), 1.0)
		draw_line(tag.position + Vector2(3, 6), tag.position + Vector2(14, 6),
			Color("6b5a2c"), 1.0)
	# name badge
	var badge_pos := Vector2(-16, -H - 7)
	var plate_col := Color("47352a").lerp(Color("17314c"), progress)
	draw_rect(Rect2(badge_pos, Vector2(32, 14)), plate_col)
	draw_rect(Rect2(badge_pos, Vector2(2, 14)), UIW.colour("warm").lerp(UIW.colour("accent"), progress))
	draw_rect(Rect2(badge_pos, Vector2(32, 14)), Color(0.72, 0.76, 0.76, 0.42), false, 1.0)
	draw_string(UIW.sans_font(), badge_pos + Vector2(6, 11), rack.name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIW.colour("text_strong"))
	if not rack.note.is_empty():
		# A tiny folded paper tab is readable as human context even at floor zoom.
		var paper := Rect2(Vector2(-ex * 0.78, -H + 12), Vector2(16, 19))
		draw_rect(Rect2(paper.position + Vector2(2, 2), paper.size), Color(0, 0, 0, 0.28))
		draw_rect(paper, Color("e8c96f"))
		draw_colored_polygon(PackedVector2Array([paper.end - Vector2(5, 0), paper.end,
			paper.end - Vector2(0, 5)]), Color("b49348"))
		draw_line(paper.position + Vector2(3, 7), paper.position + Vector2(12, 7),
			Color("67552c"), 1.0)
		draw_line(paper.position + Vector2(3, 11), paper.position + Vector2(10, 11),
			Color("67552c"), 1.0)
	_draw_loose_leads(e, s, up)
	# a cabinet with something actually happening in it says so on the cabinet
	for haz: Dictionary in Game.hazards:
		if String(haz.get("rack", "")) != rack.name:
			continue
		var pulse := 0.45 + 0.3 * sin(Time.get_ticks_msec() / 200.0)
		var haz_col := Color(0.35, 0.72, 1.0, pulse) if String(haz["kind"]) == "water" \
			else Color(0.98, 0.45, 0.22, pulse)
		for ring_i in 2:
			var halo := PackedVector2Array()
			for p2 in [n, e, s, w, n]:
				halo.append(p2 * (1.05 + 0.12 * ring_i) + up * 0.05)
			draw_polyline(halo, Color(haz_col, pulse * (0.8 - 0.3 * ring_i)), 2.5)
		var label := String(haz["kind"]).to_upper()
		if not bool(haz.get("detected", false)):
			label += " ?"  # nothing on this floor is watching for it
		draw_string(UIW.sans_font(), Vector2(-ex * 0.5, -H - 16), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(haz_col, 0.95))
		break
	# a hot cabinet glows at its base, so a bad row is visible from the floor
	if Game.rack_hot(rack):
		var pulse_h := 0.3 + 0.18 * sin(tms / 420.0)
		draw_colored_polygon(PackedVector2Array([n, e, s, w]), Color(1.0, 0.35, 0.2, pulse_h))
	if highlighted:
		var pulse := 0.55 + 0.35 * sin(tms / 240.0)
		draw_polyline(PackedVector2Array([n, e, s, w, n]), Color(0.5, 0.9, 1.0, pulse), 2.5)
