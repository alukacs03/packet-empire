class_name Techs
extends Node2D
## People on the floor. One figure per person on the payroll, plus a couple of
## contractors early on so the room is never dead. They walk to whatever needs
## attention (a dead device, an unsaved configuration) and stand there working,
## which makes the floor readable at a glance as well as alive.
##
## Each person is its own node so it sorts against the cabinets by the tile it
## is standing on: walk behind a rack and the rack hides you.

const SPEED := 46.0  # world units per second
const DWELL := Vector2(3.0, 9.0)  # seconds spent standing at a destination
## A rack is about two metres and stands 96 units tall on screen, so a person
## at roughly 1.75m lands a little under eighty.
const HEIGHT := 78.0

var people: Array = []  # Person nodes
var _rng := RandomNumberGenerator.new()

class Person extends Node2D:
	var target := Vector2.ZERO
	var dwell := 0.0
	var phase := 0.0
	var kit := Color(0.35, 0.62, 0.75)
	var idx := 0
	var crew: Techs

	func _process(dt: float) -> void:
		if dwell > 0.0:
			dwell -= dt
		else:
			var step := SPEED * dt
			if position.distance_to(target) <= step:
				position = target
				dwell = crew._rng.randf_range(DWELL.x, DWELL.y)
				target = crew._work_spot(idx)
			else:
				position += (target - position).normalized() * step
			# sort against the cabinets by the tile underfoot, exactly as
			# RackVisual does, so standing behind one puts you behind it
			var t := Iso.world_to_tile(position)
			z_index = t.x + t.y + 2
		queue_redraw()

	func _draw() -> void:
		var clock := Time.get_ticks_msec() / 1000.0
		var working := dwell > 0.0
		var bob := 0.0 if working else sin(clock * 6.0 + phase) * 2.0
		var stride := 0.0 if working else sin(clock * 6.0 + phase) * 9.0
		# an iso-flattened shadow, so nobody looks like they are hovering
		var shadow := PackedVector2Array()
		for k in 12:
			var a := TAU * k / 12.0
			shadow.append(Vector2(cos(a) * 13.0, sin(a) * 6.5))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
		var hip := Vector2(0, -HEIGHT * 0.42 + bob)
		draw_line(hip, Vector2(-stride, 0), kit.darkened(0.4), 8.0)
		draw_line(hip, Vector2(stride, 0), kit.darkened(0.4), 8.0)
		draw_line(hip, Vector2(0, -HEIGHT * 0.79 + bob), kit, 13.0)
		draw_circle(Vector2(0, -HEIGHT * 0.9 + bob), HEIGHT * 0.115,
			Color(0.86, 0.78, 0.68))
		if working:
			# a laptop lid catching the light, so you can see where the work is
			var glow := 0.45 + 0.25 * sin(clock * 3.0 + phase)
			draw_line(Vector2(9, -HEIGHT * 0.5), Vector2(24, -HEIGHT * 0.58),
				Color(0.5, 0.9, 1.0, glow), 3.0)

func _ready() -> void:
	_rng.seed = 4242
	Game.topology_changed.connect(_resize_crew)
	_resize_crew()

func _crew_size() -> int:
	# two contractors keep the colo from looking abandoned; after that the
	# floor fills up with the people you actually hired
	return maxi(2, Game.staff.size())

func _resize_crew() -> void:
	while people.size() > _crew_size():
		var gone: Person = people.pop_back()
		gone.queue_free()
	while people.size() < _crew_size():
		var p := Person.new()
		p.crew = self
		p.idx = people.size()
		p.position = _random_spot()
		p.target = _random_spot()
		p.phase = _rng.randf() * TAU
		var spawn_tile := Iso.world_to_tile(p.position)
		p.z_index = spawn_tile.x + spawn_tile.y + 2
		p.kit = Color(0.35, 0.62, 0.75) if people.size() % 2 == 0 \
			else Color(0.75, 0.55, 0.3)
		add_child(p)
		people.append(p)

func _random_spot() -> Vector2:
	var g: Vector2i = Game.grid_size()
	return Iso.tile_to_world(Vector2i(_rng.randi_range(0, maxi(0, g.x - 1)),
		_rng.randi_range(0, maxi(0, g.y - 1))))

func _work_spot(idx := 0) -> Vector2:
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
	# stand on the tile in front of the cabinet, which in isometric means one
	# step along BOTH axes, not simply further down the screen
	var g2: Vector2i = Game.grid_size()
	var spot := r2.tile + Vector2i(1, 1)
	if spot.x >= g2.x or spot.y >= g2.y:
		spot = r2.tile - Vector2i(1, 1)  # against the far wall: stand behind it
	spot.x = clampi(spot.x, 0, maxi(0, g2.x - 1))
	spot.y = clampi(spot.y, 0, maxi(0, g2.y - 1))
	# each person keeps their own lane so two never occupy the same body
	return Iso.tile_to_world(spot) \
		+ Vector2(-30.0 + idx % 3 * 30.0 + _rng.randf_range(-5.0, 5.0), 0.0)
