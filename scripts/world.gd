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
var title: TitleScreen

func _ready() -> void:
	if OS.get_environment("PACKET_TEST") == "1":
		var fails: int = SimTests.run()
		if fails == 0:
			fails = SimTests.ui_smoke(self)
		get_tree().quit(1 if fails > 0 else 0)
		return
	ui = UILayer.new()
	add_child(ui)
	get_tree().root.content_scale_factor = Prefs.ui_scale
	Game.topology_changed.connect(queue_redraw)
	if OS.get_environment("PACKET_SHOT") != "":
		_shoot_all.call_deferred()
		return
	Game.topology_changed.connect(_site_watch)
	show_title()

func show_title() -> void:
	## the front door: the world keeps running behind it but nobody can touch it
	if title != null:
		title.visible = true
		title._build_menu()
		title.show_intro()
		ui.visible = false
		Game.set_speed(0)
		return
	title = TitleScreen.new()
	add_child(title)
	ui.visible = false
	Game.set_speed(0)  # nothing ticks while nobody is playing
	title.start_requested.connect(_start_new)
	title.continue_requested.connect(_continue)


func _leave_title() -> void:
	title.visible = false
	ui.visible = true
	Game.set_speed(1)
	rebuild_racks()
	ui._refresh_money()
	ui._refresh_attention()

func _start_new(slot: int, company: String, diff: int, is_demo: bool) -> void:
	Game.reset_new(company, diff, is_demo)
	ui._demo_end_shown = false
	ui.tutorial_hidden = false
	Game.current_slot = slot
	Game.save_game()
	_leave_title()
	if is_demo:
		Demo.begin()
	ui.show_welcome()

func _continue(slot: int) -> void:
	if not Game.load_slot(slot):
		return
	_leave_title()

func _shoot_all() -> void:
	## PACKET_SHOT=<dir>: photograph every screen, then quit
	var dir := OS.get_environment("PACKET_SHOT")
	SimTests.demo_world()
	rebuild_racks()
	var r: Net.Rack = Game.racks[0]
	var dev: Net.NDevice = null
	var sw: Net.NDevice = null
	for d in Game.all_devices():
		if d.type == "server" and dev == null:
			dev = d
		if d.type == "switch" and sw == null:
			sw = d
	var shots: Array = [
		["title", func() -> void: show_title()],
		["title_slots", func() -> void: title.show_slots()],
		["title_new", func() -> void: title.show_new_game(true)],
		["floor", func() -> void:
			title.visible = false
			ui.visible = true],
		["rack", func() -> void: ui.open_rack(r)],
		["device", func() -> void: ui.open_dev(sw)],
		["console", func() -> void:
			ui._toggle_cli()
			ui._cli_submit("show interfaces")],
		["iface", func() -> void: ui.open_iface(sw.ifaces[0])],
		["contracts", func() -> void:
			ui.close_iface()
			ui.close_dev()
			ui.close_rack()
			ui.open_contracts()],
		["map", func() -> void:
			ui.close_contracts()
			ui.toggle_map()],
		["pedia", func() -> void:
			ui.toggle_map()
			ui.open_pedia()],
		["help", func() -> void:
			ui.pedia_overlay.visible = false
			ui.toggle_help()],
		["demo_end", func() -> void:
			ui.help_overlay.visible = false
			ui._show_overlay(ui.demo_overlay)],
		["ops", func() -> void:
			ui.demo_overlay.visible = false
			ui.help_overlay.visible = false
			ui.toggle_ops()],
	]
	for shot in shots:
		shot[1].call()
		for _f in 16:  # let fades and layout settle
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [dir, shot[0]])
		print("shot: ", shot[0])
	get_tree().quit()

func rebuild_racks() -> void:
	for child in get_children():
		if child is RackVisual:
			child.visible = false  # racks on other sites are not on this floor
			child.queue_free()
	for r in Game.racks_on(Game.current_site):
		add_child(RackVisual.new().setup(r))
	queue_redraw()

var _shown_site := 0

func _site_watch() -> void:
	if Game.current_site != _shown_site:
		_shown_site = Game.current_site
		rebuild_racks()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and ui:
		if Game.drill_active:
			Drill.finish(false)  # abandon: restore the real datacenter before saving
		Game.save_game()

func _process(dt: float) -> void:
	if ui == null:
		return
	if not _anims.is_empty():
		_anim_clock += dt
		queue_redraw()
		if _anim_clock > _anims[-1]["t0"] + 0.5:
			_anims.clear()
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
	if title != null and title.visible:
		return
	if e is InputEventKey and e.pressed:
		match e.keycode:
			KEY_Q:
				mode = Mode.SELECT
			KEY_R:
				mode = Mode.PLACE_RACK
			KEY_M:
				ui.toggle_map()
			KEY_O:
				ui.toggle_ops()
			KEY_F:
				ui.toggle_search()
			KEY_F1:
				ui.toggle_help()
			KEY_SPACE:
				Game.toggle_pause()
			KEY_1:
				Game.set_speed(1)
			KEY_2:
				Game.set_speed(2)
			KEY_3:
				Game.set_speed(3)
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
	var grid: Vector2i = Game.grid_size()
	if tile.x < 0 or tile.y < 0 or tile.x >= grid.x or tile.y >= grid.y:
		ui.hud_toast("That is outside %s. Expand the floor or pick another tile."
			% Game.site_name(Game.current_site))
		return
	if Game.rack_at(tile):
		ui.hud_toast("There is already a rack there.")
		return
	if not Game.try_spend(Game.RACK_PRICE):
		ui.hud_toast("A rack costs $%d and you have $%d." % [Game.RACK_PRICE, Game.money])
		return
	add_child(RackVisual.new().setup(Game.add_rack(tile)))
	queue_redraw()

var _anims: Array = []
var _anim_clock := 0.0

func play_trace(trace: Array) -> void:
	## Animate the last sim operation's inter-rack hops as moving packets.
	_anims.clear()
	_anim_clock = 0.0
	var idx := 0
	for hop in trace:
		var ra := Game.rack_of(hop["a"].dev)
		var rb := Game.rack_of(hop["b"].dev)
		if ra == null or rb == null or ra == rb or ra.visual == null or rb.visual == null:
			continue
		_anims.append({"p0": ra.visual.top_anchor(), "p1": rb.visual.top_anchor(),
			"t0": idx * 0.12,
			"col": Color(0.5, 0.9, 1.0) if hop["kind"] == "arp" else Color(1.0, 0.85, 0.3)})
		idx += 1
	if not _anims.is_empty():
		queue_redraw()

static func _tray(p0: Vector2, p1: Vector2, t: float) -> Vector2:
	var mid := (p0 + p1) / 2.0 + Vector2(0, -36)
	return p0.lerp(mid, t).lerp(mid.lerp(p1, t), t)

func _draw() -> void:
	# overhead cable trays; parallel links between the same racks fan out
	var pair_seen := {}
	for l in Game.links:
		var ra := Game.rack_of(l.a.dev)
		var rb := Game.rack_of(l.b.dev)
		if ra == null or rb == null or ra == rb or ra.visual == null or rb.visual == null \
				or ra.site != Game.current_site or rb.site != Game.current_site:
			continue
		var key := "%s|%s" % [mini(ra.tile.x * 100 + ra.tile.y, rb.tile.x * 100 + rb.tile.y),
			maxi(ra.tile.x * 100 + ra.tile.y, rb.tile.x * 100 + rb.tile.y)]
		var idx: int = pair_seen.get(key, 0)
		pair_seen[key] = idx + 1
		var p0: Vector2 = ra.visual.top_anchor()
		var p1: Vector2 = rb.visual.top_anchor()
		var perp := (p1 - p0).normalized().orthogonal() * (idx * 7.0)
		var pts := PackedVector2Array()
		for i in 17:
			pts.append(_tray(p0 + perp, p1 + perp, i / 16.0))
		draw_polyline(pts, Color(0, 0, 0, 0.25), 3.5)  # shadow line
		draw_polyline(pts, Color(1.0, 0.62, 0.2, 0.9), 2.0)
	# packets in flight
	const DUR := 0.3
	for a in _anims:
		var t: float = (_anim_clock - a["t0"]) / DUR
		if t < 0.0 or t > 1.0:
			continue
		var pos := _tray(a["p0"], a["p1"], t)
		draw_circle(pos, 9.0, Color(a["col"], 0.25))
		draw_circle(pos, 4.5, a["col"])
