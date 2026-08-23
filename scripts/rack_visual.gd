class_name RackVisual
extends Node2D
## Isometric rack cabinet: drop shadow, gradient faces, per-device front
## strips with blinking activity LEDs, name badge.

const H := 96.0
const W := 0.7

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
	match dev.type:
		"switch":
			return Color(0.2, 0.7, 0.75)
		"router":
			return Color(0.85, 0.6, 0.3)
		"firewall":
			return Color(0.85, 0.35, 0.35)
		"uplink":
			return Color(0.7, 0.5, 0.9)
		"cooling":
			return Color(0.5, 0.8, 0.95)
		"loadbalancer":
			return Color(0.55, 0.85, 0.55)
		"ap":
			return Color(0.9, 0.8, 0.45)
	return Color(0.45, 0.55, 0.8)

func _draw() -> void:
	var base := Color(0.2, 0.22, 0.28)
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
	draw_colored_polygon(sh, Color(0, 0, 0, 0.28))
	# cabinet
	draw_colored_polygon(PackedVector2Array([w, s, s + up, w + up]), base.darkened(0.5))
	draw_colored_polygon(PackedVector2Array([s, e, e + up, s + up]), base.darkened(0.22))
	draw_colored_polygon(PackedVector2Array([n + up, e + up, s + up, w + up]), base.lightened(0.18))
	# top edge highlight
	draw_polyline(PackedVector2Array([w + up, n + up, e + up]), Color(0.5, 0.58, 0.7, 0.5), 1.5)
	# left-face vents
	for k in 5:
		var f := 0.15 + k * 0.16
		draw_line(lerp(w, s, 0.25) + up * f, lerp(w, s, 0.75) + up * f, base.darkened(0.7), 1.0)
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
			var lo2 := lerp(s, s + up, frac + 0.07)
			var hi2 := lerp(e, e + up, frac + 0.07)
			draw_colored_polygon(PackedVector2Array([
				lerp(lo, hi, 0.08), lerp(lo, hi, 0.92), lerp(lo2, hi2, 0.92), lerp(lo2, hi2, 0.08),
			]), col.darkened(0.25))
			draw_line(lerp(lo2, hi2, 0.08), lerp(lo2, hi2, 0.92), col.lightened(0.2), 1.0)
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
	var badge_pos := Vector2(-20, -H - 26)
	draw_rect(Rect2(badge_pos, Vector2(40, 17)), Color(0.05, 0.06, 0.09, 0.85))
	draw_rect(Rect2(badge_pos, Vector2(40, 17)), Color(0.35, 0.42, 0.55, 0.7), false, 1.0)
	draw_string(ThemeDB.fallback_font, badge_pos + Vector2(7, 13), rack.name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.87, 0.97))
	# a hot cabinet glows at its base, so a bad row is visible from the floor
	if Game.rack_hot(rack):
		var pulse_h := 0.3 + 0.18 * sin(tms / 420.0)
		draw_colored_polygon(PackedVector2Array([n, e, s, w]), Color(1.0, 0.35, 0.2, pulse_h))
	if highlighted:
		var pulse := 0.55 + 0.35 * sin(tms / 240.0)
		draw_polyline(PackedVector2Array([n, e, s, w, n]), Color(0.5, 0.9, 1.0, pulse), 2.5)
