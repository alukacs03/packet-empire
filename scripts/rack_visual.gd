class_name RackVisual
extends Node2D
## Isometric rack cabinet: drop shadow, gradient faces, per-device front
## strips with blinking activity LEDs, name badge.

const H := 104.0
const W := 0.86

var rack: Net.Rack
var highlighted := false:
	set(v):
		highlighted = v
		queue_redraw()

func setup(r: Net.Rack) -> RackVisual:
	rack = r
	r.visual = self
	position = Iso.tile_to_world(r.tile)
	z_index = r.tile.x + r.tile.y + 1
	return self

func top_anchor() -> Vector2:
	return position + Vector2(0, -H)

func _process(_dt: float) -> void:
	if highlighted:
		queue_redraw()
		return
	for d in rack.slots:
		if d != null:
			queue_redraw()  # LEDs blink
			return

func _dev_color(dev: Net.NDevice) -> Color:
	return UIW.TYPE_COLORS.get(dev.type, UIW.TYPE_COLORS["server"])

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
	# soft ground shadow
	var sh := PackedVector2Array()
	for p in [n, e, s, w]:
		sh.append(p * 1.35 + Vector2(4, 3))
	draw_colored_polygon(sh, Color(0.01, 0.025, 0.06, 0.48))
	# cabinet
	draw_colored_polygon(PackedVector2Array([w, s, s + up, w + up]), Color("211c1b").lerp(Color("102944"), progress))
	draw_colored_polygon(PackedVector2Array([s, e, e + up, s + up]), base)
	draw_colored_polygon(PackedVector2Array([n + up, e + up, s + up, w + up]), Color("786758").lerp(Color("456f8d"), progress))
	# top edge highlight
	draw_polyline(PackedVector2Array([w + up, n + up, e + up]), Color(0.72, 0.86, 0.94, 0.72), 1.5)
	# vertical frame rails silhouette the cabinet at game zoom.
	draw_line(s + Vector2(1, -3), s + up + Vector2(1, 3), Color("5b7890"), 2.2)
	draw_line(e + Vector2(-1, -2), e + up + Vector2(-1, 2), Color("182c42"), 2.2)
	# Recess the front face so the silhouette reads like a cabinet, not a box.
	var front_inset := PackedVector2Array([
		lerp(s, e, 0.08) + up * 0.08, lerp(s, e, 0.92) + up * 0.08,
		lerp(s, e, 0.92) + up * 0.94, lerp(s, e, 0.08) + up * 0.94,
	])
	draw_colored_polygon(front_inset, Color(0.035, 0.045, 0.055, 0.66))
	draw_polyline(front_inset + PackedVector2Array([front_inset[0]]), Color(0.78, 0.62, 0.44, 0.28).lerp(Color(UIW.colour("border_strong"), 0.48), progress), 1.0)
	# left-face vents
	for k in 5:
		var f := 0.15 + k * 0.16
		draw_line(lerp(w, s, 0.25) + up * f, lerp(w, s, 0.75) + up * f, base.darkened(0.7), 1.0)
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
		var lo := lerp(s, s + up, frac)
		var hi := lerp(e, e + up, frac)
		var dev: Net.NDevice = rack.slots[i]
		if dev:
			var col := _dev_color(dev)
			if dev.status != "active":
				col = Color(0.35, 0.3, 0.3)
			var lo2 := lerp(s, s + up, frac + 0.075)
			var hi2 := lerp(e, e + up, frac + 0.075)
			draw_colored_polygon(PackedVector2Array([
				lerp(lo, hi, 0.08), lerp(lo, hi, 0.92), lerp(lo2, hi2, 0.92), lerp(lo2, hi2, 0.08),
			]), col.darkened(0.12))
			draw_line(lerp(lo, hi, 0.08), lerp(lo, hi, 0.92), col.lightened(0.35), 1.0)
			draw_line(lerp(lo2, hi2, 0.08), lerp(lo2, hi2, 0.92), col.darkened(0.35), 1.0)
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
			var mid_lo := lerp(lo, hi, 0.85)
			var mid_hi := lerp(lo2, hi2, 0.85)
			draw_circle(mid_lo + (mid_hi - mid_lo) * 0.5, 1.8, led)
		else:
			draw_line(lerp(lo, hi, 0.1), lerp(lo, hi, 0.9), base.lightened(0.3), 1.0)
	# name badge
	var badge_pos := Vector2(-20, -H - 10)
	var plate_col := Color("47352a").lerp(Color("17314c"), progress)
	draw_rect(Rect2(badge_pos + Vector2(2, 2), Vector2(40, 17)), Color(0, 0, 0, 0.24))
	draw_rect(Rect2(badge_pos, Vector2(40, 17)), plate_col)
	draw_rect(Rect2(badge_pos, Vector2(3, 17)), UIW.colour("warm").lerp(UIW.colour("accent"), progress))
	draw_rect(Rect2(badge_pos, Vector2(40, 17)), Color(UIW.colour("border_strong"), 0.72), false, 1.0)
	draw_string(UIW.sans_font(), badge_pos + Vector2(8, 13), rack.name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIW.colour("text_strong"))
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
	# a hot cabinet glows at its base, so a bad row is visible from the floor
	if Game.rack_hot(rack):
		var pulse_h := 0.3 + 0.18 * sin(tms / 420.0)
		draw_colored_polygon(PackedVector2Array([n, e, s, w]), Color(1.0, 0.35, 0.2, pulse_h))
	if highlighted:
		var pulse := 0.55 + 0.35 * sin(tms / 240.0)
		draw_polyline(PackedVector2Array([n, e, s, w, n]), Color(0.5, 0.9, 1.0, pulse), 2.5)
