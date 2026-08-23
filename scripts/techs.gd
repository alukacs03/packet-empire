class_name Techs
extends Node2D
## People on the floor. One figure per person on the payroll, plus a couple of
## contractors early on so the room is never dead. They walk to whatever needs
## attention (a dead device, an unsaved configuration) and stand there working,
## which makes the floor readable at a glance as well as alive.

const SPEED := 46.0  # world units per second
const DWELL := Vector2(3.0, 9.0)  # seconds spent standing at a destination

var people: Array = []  # {pos, target, dwell, phase, kit, name}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	z_index = 4000  # people walk in front of the cabinets
	_rng.seed = 4242
	Game.topology_changed.connect(_resize_crew)
	_resize_crew()

func _crew_size() -> int:
	# two contractors keep the colo from looking abandoned; after that the
	# floor fills up with the people you actually hired
	return maxi(2, Game.staff.size())

func _resize_crew() -> void:
	while people.size() > _crew_size():
		people.pop_back()
	while people.size() < _crew_size():
		var idx := people.size()
		people.append({
			"pos": _random_spot(), "target": _random_spot(), "dwell": 0.0,
			"phase": _rng.randf() * TAU,
			"kit": Color(0.35, 0.62, 0.75) if idx % 2 == 0 else Color(0.75, 0.55, 0.3),
		})

func _random_spot() -> Vector2:
	var g: Vector2i = Game.grid_size()
	return Iso.tile_to_world(Vector2i(_rng.randi_range(0, maxi(0, g.x - 1)),
		_rng.randi_range(0, maxi(0, g.y - 1))))

func _work_spot() -> Vector2:
	## somewhere that deserves a person: a dead device first, then an unsaved
	## configuration, then anywhere at all
	var broken: Array = []
	var untidy: Array = []
	for r in Game.racks_on(Game.current_site):
		for d in r.slots:
			if d == null:
				continue
			if d.status != "active":
				broken.append(r)
			elif Game.config_dirty(d):
				untidy.append(r)
	var pool: Array = broken if not broken.is_empty() else untidy
	if pool.is_empty():
		return _random_spot()
	var r2: Net.Rack = pool[_rng.randi() % pool.size()]
	# stand beside the cabinet rather than inside it
	return Iso.tile_to_world(r2.tile) + Vector2(_rng.randf_range(-34.0, 34.0), 18.0)

func _process(dt: float) -> void:
	if people.is_empty():
		return
	for p: Dictionary in people:
		if float(p["dwell"]) > 0.0:
			p["dwell"] = float(p["dwell"]) - dt
			continue
		var pos: Vector2 = p["pos"]
		var to: Vector2 = p["target"]
		var step := SPEED * dt
		if pos.distance_to(to) <= step:
			p["pos"] = to
			p["dwell"] = _rng.randf_range(DWELL.x, DWELL.y)
			p["target"] = _work_spot()
		else:
			p["pos"] = pos + (to - pos).normalized() * step
	queue_redraw()

func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for p: Dictionary in people:
		var pos: Vector2 = p["pos"]
		var working: bool = float(p["dwell"]) > 0.0
		var bob := 0.0 if working else sin(t * 7.0 + float(p["phase"])) * 1.4
		var kit: Color = p["kit"]
		draw_circle(pos + Vector2(0, 2), 6.0, Color(0, 0, 0, 0.3))  # shadow
		# body: a torso and a head is enough at this scale, and reads instantly
		draw_line(pos + Vector2(0, -7 + bob), pos + Vector2(0, -20 + bob), kit, 5.0)
		draw_circle(pos + Vector2(0, -24 + bob), 4.0, Color(0.86, 0.78, 0.68))
		# legs, which stop moving when they stop moving
		var stride := 0.0 if working else sin(t * 7.0 + float(p["phase"])) * 3.5
		# two lines beat a skeleton at this size
		draw_line(pos + Vector2(0, -7 + bob), pos + Vector2(-stride, 0), kit.darkened(0.35), 3.0)
		draw_line(pos + Vector2(0, -7 + bob), pos + Vector2(stride, 0), kit.darkened(0.35), 3.0)
		if working:
			# a laptop lid catching the light, so you can see where the work is
			var glow := 0.45 + 0.25 * sin(t * 3.0 + float(p["phase"]))
			draw_line(pos + Vector2(4, -12), pos + Vector2(11, -15),
				Color(0.5, 0.9, 1.0, glow), 2.0)
