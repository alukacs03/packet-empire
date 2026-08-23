class_name TitleBackdrop
extends Control
## The moving picture behind the title screen: an isometric floor of racks
## drifting slowly past, drawn the same way the game draws its own world so
## the front door looks like the place it opens onto.

const TILE_W := 96.0
const TILE_H := 48.0
const ROWS := 7
const COLS := 9

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
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.045, 0.055, 0.075))
	# a cool wash from the top, warmer near the floor, so the page has depth
	for band in 24:
		var f := float(band) / 24.0
		draw_rect(Rect2(0, vp.y * f, vp.x, vp.y / 24.0 + 1.0),
			Color(0.06 + 0.02 * f, 0.09 + 0.01 * f, 0.14 - 0.04 * f, 0.5))
	var drift := fmod(t * 9.0, TILE_W)
	var origin := Vector2(vp.x * 0.72 - drift, vp.y * 0.74)
	for r in ROWS:
		for c in COLS:
			var s: Dictionary = seeds[r * COLS + c]
			if not s["filled"]:
				continue
			_rack(origin + _iso(float(c) - COLS * 0.5, float(r) - ROWS * 0.5), s)
	# a scrim down the left, so the menu never has to compete with the floor
	for band3 in 26:
		var f3 := float(band3) / 26.0
		draw_rect(Rect2(0, 0, vp.x * 0.62 * (1.0 - f3), vp.y), Color(0.04, 0.05, 0.07, 0.075))
	# vignette, so the buttons in the middle stay readable
	for band2 in 16:
		var f2 := float(band2) / 16.0
		draw_rect(Rect2(0, 0, vp.x, vp.y * 0.35 * (1.0 - f2)), Color(0.02, 0.02, 0.04, 0.055))
		draw_rect(Rect2(0, vp.y - vp.y * 0.4 * (1.0 - f2), vp.x, vp.y), Color(0.02, 0.02, 0.04, 0.05))

func _rack(pos: Vector2, s: Dictionary) -> void:
	var h := 74.0 * float(s["h"])
	var ex := TILE_W * 0.28
	var ey := TILE_H * 0.28
	var n := pos + Vector2(0, -ey)
	var e := pos + Vector2(ex, 0)
	var so := pos + Vector2(0, ey)
	var w := pos + Vector2(-ex, 0)
	var up := Vector2(0, -h)
	draw_colored_polygon(PackedVector2Array([w, so, so + up, w + up]), Color(0.10, 0.11, 0.15))
	draw_colored_polygon(PackedVector2Array([so, e, e + up, so + up]), Color(0.14, 0.16, 0.21))
	draw_colored_polygon(PackedVector2Array([n + up, e + up, so + up, w + up]), Color(0.19, 0.22, 0.28))
	# a few lit units per cabinet, blinking out of step with each other
	for u in 6:
		var frac := 0.12 + u * 0.14
		var lo: Vector2 = so.lerp(so + up, frac)
		var hi: Vector2 = e.lerp(e + up, frac)
		var lit: float = sin(t * (0.8 + u * 0.37) + float(s["phase"]) + u) * 0.5 + 0.5
		var col := Color(0.25, 0.75, 0.8, 0.25 + 0.5 * lit)
		if float(s["hue"]) > 0.72:
			col = Color(0.85, 0.6, 0.3, 0.25 + 0.5 * lit)
		draw_line(lo.lerp(hi, 0.15), lo.lerp(hi, 0.85), col, 1.6)
