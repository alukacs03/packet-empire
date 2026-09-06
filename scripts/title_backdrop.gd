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

