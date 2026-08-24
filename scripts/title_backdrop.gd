class_name TitleBackdrop
extends Control
## The moving picture behind the title screen: an isometric floor of racks
## drifting slowly past, drawn the same way the game draws its own world so
## the front door looks like the place it opens onto.

const TILE_W := 96.0
const TILE_H := 48.0
const ROWS := 7
const COLS := 9
const ART: Texture2D = preload("res://assets/generated/title_datacenter.png")

var t := 0.0
var seeds: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260824
	for r in ROWS:
		for c in COLS:
			# a sparse floor reads better than a full one: leave aisles
			var filled := rng.randf() < 0.55 and not (c == 3 or c == 6)
			seeds.append({"filled": filled, "h": rng.randf_range(0.75, 1.15),
				"phase": rng.randf() * TAU, "hue": rng.randf()})

func _process(dt: float) -> void:
	t += dt
	queue_redraw()

func _iso(c: float, r: float) -> Vector2:
	return Vector2((c - r) * TILE_W * 0.5, (c + r) * TILE_H * 0.5)

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_texture_rect(ART, Rect2(Vector2.ZERO, vp), false)
	# Calm the copy zone while preserving the authored painterly texture.
	for band in 24:
		var f := float(band) / 23.0
		draw_rect(Rect2(vp.x * f * 0.55, 0, vp.x * 0.55 / 23.0 + 2, vp.y),
			Color(0.02, 0.065, 0.12, 0.72 * (1.0 - f)))
	# Live packet sparks bind the key art to the simulated world.
	for lane in 3:
		var a := Vector2(vp.x * 0.55, vp.y * (0.63 + lane * 0.07))
		var b := Vector2(vp.x * 0.88, vp.y * (0.50 + lane * 0.04))
		var p := a.lerp(b, fmod(t * (0.08 + lane * 0.02) + lane * 0.27, 1.0))
		draw_circle(p, 3.0, Color(UIW.colour("accent"), 0.80))

func _rack(pos: Vector2, s: Dictionary) -> void:
	var h := 74.0 * float(s["h"])
	var ex := TILE_W * 0.28
	var ey := TILE_H * 0.28
	var n := pos + Vector2(0, -ey)
	var e := pos + Vector2(ex, 0)
	var so := pos + Vector2(0, ey)
	var w := pos + Vector2(-ex, 0)
	var up := Vector2(0, -h)
	draw_colored_polygon(PackedVector2Array([w, so, so + up, w + up]), Color("102943"))
	draw_colored_polygon(PackedVector2Array([so, e, e + up, so + up]), Color("294963"))
	draw_colored_polygon(PackedVector2Array([n + up, e + up, so + up, w + up]), Color("557992"))
	draw_polyline(PackedVector2Array([w + up, n + up, e + up]), Color(0.68, 0.88, 0.94, 0.5), 1.5)
	# a few lit units per cabinet, blinking out of step with each other
	for u in 6:
		var frac := 0.12 + u * 0.14
		var lo: Vector2 = so.lerp(so + up, frac)
		var hi: Vector2 = e.lerp(e + up, frac)
		var lit: float = sin(t * (0.8 + u * 0.37) + float(s["phase"]) + u) * 0.5 + 0.5
		var col := Color(UIW.colour("accent"), 0.38 + 0.57 * lit)
		if float(s["hue"]) > 0.72:
			col = Color(UIW.colour("warm"), 0.38 + 0.57 * lit)
		draw_line(lo.lerp(hi, 0.12), lo.lerp(hi, 0.88), col, 2.2)
