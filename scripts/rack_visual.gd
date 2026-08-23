class_name RackVisual
extends Node2D
## Isometric rack cabinet on the floor. Filled U-slots glow on the front face.

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

func _draw() -> void:
	var base := Color(0.22, 0.24, 0.3)
	var ex := Iso.TILE_W / 2.0 * W
	var ey := Iso.TILE_H / 2.0 * W
	var n := Vector2(0, -ey)
	var e := Vector2(ex, 0)
	var s := Vector2(0, ey)
	var w := Vector2(-ex, 0)
	var up := Vector2(0, -H)
	draw_colored_polygon(PackedVector2Array([w, s, s + up, w + up]), base.darkened(0.45))
	draw_colored_polygon(PackedVector2Array([s, e, e + up, s + up]), base.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([n + up, e + up, s + up, w + up]), base.lightened(0.15))
	# front face (s-e) slot rows, bottom slot = index 0
	for i in Net.Rack.SLOTS:
		var frac := 0.08 + float(i) / Net.Rack.SLOTS * 0.84
		var lo := lerp(s, s + up, frac)
		var hi := lerp(e, e + up, frac)
		var dev: Net.NDevice = rack.slots[i]
		if dev:
			var col := Color(0.45, 0.55, 0.8)
			if dev.type == "switch":
				col = Color(0.2, 0.7, 0.75)
			elif dev.type == "router":
				col = Color(0.85, 0.6, 0.3)
			var lo2 := lerp(s, s + up, frac + 0.07)
			var hi2 := lerp(e, e + up, frac + 0.07)
			draw_colored_polygon(PackedVector2Array([
				lerp(lo, hi, 0.1), lerp(lo, hi, 0.9), lerp(lo2, hi2, 0.9), lerp(lo2, hi2, 0.1),
			]), col)
		else:
			draw_line(lerp(lo, hi, 0.1), lerp(lo, hi, 0.9), base.lightened(0.25), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(-14, -H - 10), rack.name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.78, 0.9))
	if highlighted:
		draw_polyline(PackedVector2Array([n, e, s, w, n]), Color(0.5, 0.9, 1.0), 2.0)
