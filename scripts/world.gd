extends Node2D
## Floor-level interaction: place racks, open rack view, draw inter-rack cables.

enum Mode { SELECT, PLACE_RACK }

var mode := Mode.SELECT:
	set(v):
		mode = v
		if ui:
			ui.update_mode(v)
var hover: RackVisual = null
var ui: UILayer

func _ready() -> void:
	ui = UILayer.new()
	add_child(ui)
	Game.topology_changed.connect(queue_redraw)

func _process(_dt: float) -> void:
	if ui.is_open():
		if hover:
			hover.highlighted = false
			hover = null
		return
	var r := Game.rack_at(Iso.world_to_tile(get_global_mouse_position()))
	var v: RackVisual = r.visual if r else null
	if v != hover:
		if hover:
			hover.highlighted = false
		hover = v
		if hover:
			hover.highlighted = true

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		match e.keycode:
			KEY_Q:
				mode = Mode.SELECT
			KEY_R:
				mode = Mode.PLACE_RACK
			KEY_ESCAPE:
				mode = Mode.SELECT
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var tile := Iso.world_to_tile(get_global_mouse_position())
		match mode:
			Mode.PLACE_RACK:
				_place_rack(tile)
			Mode.SELECT:
				var r := Game.rack_at(tile)
				if r:
					ui.open_rack(r)

func _place_rack(tile: Vector2i) -> void:
	var f := $Floor
	if tile.x < 0 or tile.y < 0 or tile.x >= f.GRID_W or tile.y >= f.GRID_H:
		return
	if Game.rack_at(tile):
		return
	add_child(RackVisual.new().setup(Game.add_rack(tile)))
	queue_redraw()

func _draw() -> void:
	# overhead cable trays between racks that have at least one link
	for l in Game.links:
		var ra := Game.rack_of(l.a)
		var rb := Game.rack_of(l.b)
		if ra == null or rb == null or ra == rb:
			continue
		var p0: Vector2 = ra.visual.top_anchor()
		var p1: Vector2 = rb.visual.top_anchor()
		var mid := (p0 + p1) / 2.0 + Vector2(0, -36)
		var pts := PackedVector2Array()
		for i in 17:
			var t := i / 16.0
			pts.append(p0.lerp(mid, t).lerp(mid.lerp(p1, t), t))
		draw_polyline(pts, Color(1.0, 0.62, 0.2, 0.9), 2.0)
