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
const HEIGHT := 84.0

var people: Array = []  # Person nodes
var _rng := RandomNumberGenerator.new()
var _shown_slot := -1

class Person extends Node2D:
	var target := Vector2.ZERO
	var dwell := 0.0
	var phase := 0.0
	var kit := Color("39a6bc")
	var idx := 0
	var crew: Techs
	var facing := 1.0

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
				var travel := (target - position).normalized()
				if absf(travel.x) > 0.05:
					facing = signf(travel.x)
				position += travel * step
			# sort against the cabinets by the tile underfoot, exactly as
			# RackVisual does, so standing behind one puts you behind it
			var t := Iso.world_to_tile(position)
			z_index = t.x + t.y + 2
		queue_redraw()

	func _draw() -> void:
		var clock := Time.get_ticks_msec() / 1000.0
		var working := dwell > 0.0
		var animated := not Prefs.reduced_motion
		var bob := 0.0 if working or not animated else sin(clock * 6.0 + phase) * 1.3
		var stride := 0.0 if working or not animated else sin(clock * 6.0 + phase) * 7.0
		# an iso-flattened shadow, so nobody looks like they are hovering
		var shadow := PackedVector2Array()
		for k in 12:
			var a := TAU * k / 12.0
			shadow.append(Vector2(cos(a) * 13.0, sin(a) * 6.5))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.24))
		var hip := Vector2(0, -HEIGHT * 0.39 + bob)
		# Boots and separated legs preserve the walk cycle at tiny scale.
		draw_line(hip + Vector2(-4, 0), Vector2(-stride - 4, -2), Color("33434c"), 8.0)
		draw_line(hip + Vector2(4, 0), Vector2(stride + 4, 0), Color("1a2831"), 8.0)
		draw_line(hip + Vector2(-6, 2), Vector2(-stride - 5, -1), Color(0.55, 0.65, 0.68, 0.25), 1.4)
		draw_line(Vector2(-stride - 7, -1), Vector2(-stride + 1, -1), Color("13191e"), 5.0)
		draw_line(Vector2(stride + 1, 1), Vector2(stride + 9, 1), Color("13191e"), 5.0)
		# Neck sits behind the jacket collar; the skin shade is warmer under the
		# starter room lamps and keeps the head from reading as a plain circle.
		draw_rect(Rect2(Vector2(-3 + facing, -HEIGHT * 0.80 + bob), Vector2(7, 10)), Color("b77e5c"))
		# Jacket silhouette, shoulder seam, and a small utility pack make these
		# people characters rather than animated measurement sticks.
		var torso := PackedVector2Array([
			Vector2(-10, -HEIGHT * 0.73 + bob), Vector2(8, -HEIGHT * 0.75 + bob),
			Vector2(12, -HEIGHT * 0.43 + bob), Vector2(6, -HEIGHT * 0.36 + bob),
			Vector2(-7, -HEIGHT * 0.37 + bob), Vector2(-12, -HEIGHT * 0.47 + bob),
		])
		draw_colored_polygon(torso, kit)
		var jacket_shadow := PackedVector2Array([
			Vector2(0, -HEIGHT * 0.74 + bob), Vector2(8, -HEIGHT * 0.75 + bob),
			Vector2(12, -HEIGHT * 0.43 + bob), Vector2(5, -HEIGHT * 0.36 + bob),
			Vector2(0, -HEIGHT * 0.38 + bob)])
		draw_colored_polygon(jacket_shadow, kit.darkened(0.16))
		draw_line(Vector2(-8, -HEIGHT * 0.60 + bob), Vector2(9, -HEIGHT * 0.62 + bob), kit.lightened(0.26), 2.0)
		draw_rect(Rect2(Vector2(-13 * facing, -HEIGHT * 0.67 + bob), Vector2(7 * facing, 19)), kit.darkened(0.38))
		# Collar, lanyard and badge are identity cues that survive at normal zoom.
		draw_line(Vector2(-4, -HEIGHT * 0.72 + bob), Vector2(0, -HEIGHT * 0.63 + bob), Color("d8d2bb"), 1.2)
		draw_line(Vector2(4, -HEIGHT * 0.72 + bob), Vector2(0, -HEIGHT * 0.63 + bob), Color("d8d2bb"), 1.2)
		draw_rect(Rect2(Vector2(-2, -HEIGHT * 0.61 + bob), Vector2(5, 5)), Color("e7d59b"))
		draw_line(Vector2(-8, -HEIGHT * 0.40 + bob), Vector2(8, -HEIGHT * 0.40 + bob), Color("11191f"), 2.2)
		if idx % 2 == 1:
			draw_rect(Rect2(Vector2(7, -HEIGHT * 0.47 + bob), Vector2(4, 8)), Color("d0a84d"))
		# Arms angle toward a laptop while working and swing gently while walking.
		var hand_y := -HEIGHT * (0.48 if working else 0.43) + bob
		draw_line(Vector2(-8, -HEIGHT * 0.68 + bob), Vector2(-14 - stride * 0.25, hand_y), kit.darkened(0.08), 6.0)
		draw_line(Vector2(8, -HEIGHT * 0.68 + bob), Vector2(15 + stride * 0.25, hand_y), kit.darkened(0.08), 6.0)
		var head := Vector2(2 * facing, -HEIGHT * 0.86 + bob)
		draw_circle(head, HEIGHT * 0.11, Color("d7ab82"))
		draw_arc(head + Vector2(-2 * facing, 2), HEIGHT * 0.10, -PI * 0.48, PI * 0.48,
			8, Color(0.38, 0.20, 0.14, 0.20), 3.0)
		draw_circle(head + Vector2(-8 * facing, 1), 2.4, Color("bd8766"))
		# Hair/hat alternates by crew member so contractors do not look cloned.
		if idx % 2 == 0:
			draw_arc(head + Vector2(-1 * facing, -2), HEIGHT * 0.10, PI, TAU, 10, Color("3a271d"), 5.0)
		else:
			draw_line(head + Vector2(-9, -5), head + Vector2(9, -5), kit.lightened(0.20), 5.0)
			draw_line(head + Vector2(-7 * facing, -6), head + Vector2(10 * facing, -2), kit.darkened(0.16), 2.0)
		draw_circle(head + Vector2(7 * facing, 0), 1.5, Color("272229"))
		draw_line(head + Vector2(9 * facing, 2), head + Vector2(11 * facing, 3), Color("8e5f49"), 1.0)
		if idx % 3 == 0:
			# One operator wears a compact single-ear radio headset.
			draw_arc(head, HEIGHT * 0.115, PI * 1.1, PI * 1.9, 8, Color("17232b"), 1.8)
			draw_circle(head + Vector2(-9 * facing, 1), 2.2, Color("223844"))
		if working:
			# a laptop lid catching the light, so you can see where the work is
			var glow := 0.55 if not animated else 0.45 + 0.20 * sin(clock * 3.0 + phase)
			var near := Vector2(10 * facing, -HEIGHT * 0.58)
			var far := Vector2(26 * facing, -HEIGHT * 0.55)
			draw_colored_polygon(PackedVector2Array([near, far, far + Vector2(0, 11),
				near + Vector2(0, 8)]), Color("263743"))
			draw_line(near + Vector2(2 * facing, 1), far + Vector2(-2 * facing, 1),
				Color(0.5, 0.9, 1.0, glow), 1.8)
			draw_circle(near.lerp(far, 0.55) + Vector2(0, 5), 1.2, Color(0.45, 0.8, 0.88, glow))

func _ready() -> void:
	_rng.seed = 4242
	Game.topology_changed.connect(_resize_crew)
	_shown_slot = Game.day_slot()
	_resize_crew()

func _process(_dt: float) -> void:
	if Game.day_slot() != _shown_slot:
		_shown_slot = Game.day_slot()
		_resize_crew()

func _crew_size() -> int:
	# two contractors keep the colo from looking abandoned; after that the
	# floor contains only the people actually clocked in. An empty night shift
	# is therefore visible before the player reads the rota warning.
	if Game.staff.is_empty():
		return 2
	var active := 0
	for member in Game.staff:
		if Staff.on_shift(member):
			active += 1
	return active

func _resize_crew() -> void:
	while people.size() > _crew_size():
		var gone: Person = people.pop_back()
		gone.queue_free()
	while people.size() < _crew_size():
		var p := Person.new()
		p.crew = self
		p.idx = people.size()
		# start people apart: two figures spawning on the same tile look like one
		p.position = _random_spot() + Vector2(-30.0 + p.idx % 3 * 30.0, 0.0)
		p.target = _work_spot(p.idx)
		p.phase = _rng.randf() * TAU
		var spawn_tile := Iso.world_to_tile(p.position)
		p.z_index = spawn_tile.x + spawn_tile.y + 2
		p.kit = Color("39a6bc") if people.size() % 2 == 0 \
			else Color("d98b45")
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
	# Stable assignment keeps a visible operator attached to the fault they are
	# depicting; additional crew members fan out across additional cabinets.
	var r2: Net.Rack = pool[idx % pool.size()]
	# stand on the tile in front of the cabinet, which in isometric means one
	# step along BOTH axes, not simply further down the screen
	var g2: Vector2i = Game.grid_size()
	var spot := r2.tile + Vector2i(1, 1)
	if spot.x >= g2.x or spot.y >= g2.y:
		spot = r2.tile - Vector2i(1, 1)  # against the far wall: stand behind it
	spot.x = clampi(spot.x, 0, maxi(0, g2.x - 1))
	spot.y = clampi(spot.y, 0, maxi(0, g2.y - 1))
	# Step into the diamond before applying a horizontal lane. tile_to_world()
	# lands on an isometric boundary; offsetting sideways from that boundary can
	# otherwise make the operator belong to a second-neighbour tile.
	return Iso.tile_to_world(spot) \
		+ Vector2(-30.0 + idx % 3 * 30.0 + _rng.randf_range(-5.0, 5.0),
			Iso.TILE_H * 0.375)
