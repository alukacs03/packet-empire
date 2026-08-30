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
	add_child(Techs.new())
	Sfx.install(self)
	Sfx.muted = not Prefs.sound
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
	var shot_offers := Game.offers.duplicate(true)
	var shot_deals := Game.deals.duplicate(true)
	rebuild_racks()
	var r: Net.Rack = Game.racks[0]
	var dev: Net.NDevice = null
	var sw: Net.NDevice = null
	var packet_sw: Net.NDevice = null
	for d in Game.all_devices():
		if d.type == "server" and dev == null:
			dev = d
		if d.type == "switch" and sw == null:
			sw = d
		if d.model == "sw-lite":
			packet_sw = d
	add_child(Techs.new())
	var shots: Array = [
		["title", func() -> void: show_title()],
		["title_slots", func() -> void: title.show_slots()],
		["title_new", func() -> void: title.show_new_game(true)],
		["title_settings", func() -> void: title.show_settings()],
		["floor", func() -> void:
			title.visible = false
			ui.visible = true],
		["toolbar_fresh", func() -> void:
			Game.contracts_done = []
			Game.offers = []
			Game.deals = []
			Game.leads = []
			Game.invoices = []
			Game.guided_outage = {}
			Game.incidents = []
			Game.status_posts = []
			Game.monitors = []
			Game.spares = {}
			Game.stats["guided_delivery_complete"] = 0
			Game.stage = 0
			Game.sandbox = false
			Prefs.show_everything = false
			ui._refresh_money()
			ui._refresh_tutorial()],
		["company_fresh", func() -> void:
			ui.contracts_tab = "Jobs"
			ui.open_contracts()],
		["toolbar_experienced", func() -> void:
			ui.close_contracts()
			Prefs.show_everything = true
			ui._refresh_feature_discovery()],
		["toolbar_progressed", func() -> void:
			Prefs.show_everything = false
			Game.contracts_done = ["rackup", "first_ping", "two_tenants", "stretch_vlans",
				"redundant_core", "two_offices"]
			Game.offers = shot_offers
			Game.deals = shot_deals
			Game.stats["guided_delivery_complete"] = 1
			ui._refresh_money()
			ui._refresh_tutorial()],
		["rack_arrival", func() -> void:
			if r.visual:
				r.visual.begin_arrival()],
		["rack_place_rejected", func() -> void:
			$Floor.reject_tile(r.tile, "CELL OCCUPIED")],
		["floor_outage", func() -> void:
			Game.customer_outage_active = true
			Game.last_customer_outage_cycle = Game.cycle],
		["floor_receiving", func() -> void:
			# crates on the dock, cardboard nobody cleared, and a cabinet alight
			Game.crates = [
				{"model": "srv-1", "shipped": "srv-1", "ordered": Game.cycle, "due": Game.cycle,
					"arrived": Game.cycle, "checked": false, "damaged": false, "unpack_left": 1},
				{"model": "sw-24", "shipped": "sw-24", "ordered": Game.cycle, "due": Game.cycle,
					"arrived": Game.cycle, "checked": true, "damaged": false, "unpack_left": 2}]
			Game.packaging = 3
			if not Game.racks.is_empty():
				Game.hazards = [{"kind": "smoke", "rack": Game.racks[0].name, "site": 0,
					"tile": [Game.racks[0].tile.x, Game.racks[0].tile.y], "severity": 2,
					"started": Game.cycle, "detected": true, "zone": [Game.racks[0].name]}]
			$Floor.queue_redraw()],
		["floor_mature", func() -> void:
			Game.crates = []
			Game.packaging = 0
			Game.hazards = []
			Game.customer_outage_active = false
			Game.stage = Game.STAGES.size() - 1
			rebuild_racks()
			queue_redraw()],
		["floor_untidy", func() -> void:
			# a cabinet nobody dresses, next to one somebody does
			Game.stage = 0
			rebuild_racks()
			Game.cycle = 1
			if Game.racks.size() > 1:
				var kept: Net.Rack = Game.racks[1]
				for slot_i in Net.Rack.SLOTS:
					if kept.slots[slot_i] == null:
						kept.blanked[slot_i] = true
				var loose: Net.Rack = Game.racks[0]
				loose.blanked = {}
			Game.topology_changed.emit()
			$Floor.queue_redraw()],
		["floor_summer", func() -> void:
			# the season the cooling finds out about, with the borrowed fan
			Game.stage = 0
			rebuild_racks()
			Game.cycle = int(float(Game.SEASON_LENGTH) / 4.0) + 1
			$Floor.queue_redraw()],
		["floor_visitor", func() -> void:
			# somebody signed in at the door, with the escort policy in force
			Game.stage = 0
			rebuild_racks()
			Game.staff = []  # the two contractors, so the escort is visible
			Game.access_policy = "escorted"
			Game.visitors = []
			Game.admit_visitor("Vas Elektro", "aircon service")
			$Techs._resize_crew()
			$Floor.queue_redraw()],
		["welcome", func() -> void:
			Game.visitors = []
			$Techs._resize_crew()
			Game.stage = 0
			rebuild_racks()
			Game.customer_outage_active = false
			ui.show_welcome()],
		["rack", func() -> void:
			ui.welcome_overlay.visible = false
			ui.open_rack(r)],
		["rack_cable_feedback", func() -> void:
			for link: Net.Link in Game.links:
				if Game.rack_of(link.a.dev) == r and Game.rack_of(link.b.dev) == r:
					ui.rack_cable_layer.confirm(link.a, link.b)
					break],
		["rack_cable_rejected", func() -> void:
			var loose: Net.Iface = sw.ifaces[2]
			var jack := ui._rack_port_position(loose)
			ui.rack_cable_layer.begin(jack, loose)
			ui.rack_cable_layer.finish()
			ui.rack_cable_layer.reject(jack + Vector2(-72, 48), "FREE JACK REQUIRED")],
		["rack_tidy", func() -> void:
			for slot_i in Net.Rack.SLOTS:
				if Game.slot_free(r, slot_i):
					r.blanked[slot_i] = true
			ui._refresh_slots()],
		["rack_note", func() -> void:
			Game.set_note(r, "Temporary uplink. Remove after the tenant migration.")
			Game.set_note(sw, "Port 1 is the temporary tenant uplink.")
			Game.set_note(sw.ifaces[0], "Tenant handoff — remove after migration.")
			ui._refresh_note_card(ui.rack_note_ui, r, ui.rack_note_btn)
			ui._refresh_slots()],
		["device", func() -> void: ui.open_dev(sw)],
		["device_packet", func() -> void: ui.close_dev(); ui.open_dev(packet_sw)],
		["device_config_written", func() -> void:
			ui.dev_faceplate.confirm_config_write()],
		["console", func() -> void:
			ui._toggle_cli()
			ui._cli_submit("/interface print")],
		["iface", func() -> void: ui.open_iface(sw.ifaces[0])],
		["guided_lead", func() -> void:
			ui.close_iface()
			ui.close_dev()
			ui.close_rack()
			var guided := Market.guided_first_lead()
			guided["stage"] = "rfp"
			Game.leads = [guided]
			ui.contracts_tab = "Market"
			ui.open_contracts()],
		["guided_lead_retry", func() -> void:
			Game.leads[0]["coach"] = "your price was well over their budget"
			ui._refresh_contracts()],
		["guided_delivery", func() -> void:
			Game.leads = []
			Game.deals = [{"id": "guided_delivery", "customer": "Kiskacsa Kft",
				"kind": "hosting", "params": {"ip": "10.42.18.10"}, "fee": 72,
				"brief": "best effort is acceptable, about 150 Mbps", "healthy": false,
				"guided": true, "payment_state": "waiting", "delivery_credit": 400,
				"cycles": 0, "up_cycles": 0, "term": 18, "sla": 0,
				"ctype": "startup", "load": 150, "public": false}]
			ui.close_contracts()
			ui._refresh_tutorial()],
		["guided_billing", func() -> void:
			var deal: Dictionary = Game.deals[0]
			deal["healthy"] = true
			deal["ever_healthy"] = true
			deal["payment_state"] = "billing"
			deal["first_invoice_cycle"] = Game.cycle
			deal["first_invoice_amount"] = 72
			Game.invoices = [{"customer": "Kiskacsa Kft", "deal": "guided_delivery",
				"amount": 72, "raised": Game.cycle, "due": Game.cycle + 1, "chased": false}]
			ui._refresh_tutorial()],
		["guided_suspended", func() -> void:
			var deal: Dictionary = Game.deals[0]
			deal["healthy"] = false
			deal["payment_state"] = "suspended"
			ui.contracts_tab = "Jobs"
			ui.open_contracts()],
		["guided_cash", func() -> void:
			var deal: Dictionary = Game.deals[0]
			deal["healthy"] = true
			deal["payment_state"] = "billing"
			deal["first_cash_cycle"] = Game.cycle + 1
			deal["first_cash_amount"] = 72
			Game.invoices = []
			ui.close_contracts()
			ui._refresh_tutorial()],
		["incident_alert", func() -> void:
			Game.stats["guided_delivery_acknowledged"] = 1
			Game.guided_outage = {"state": "alert", "deal": "guided_delivery",
				"customer": "Kiskacsa Kft", "device": sw.name, "iface": sw.ifaces[0].name,
				"peer_device": dev.name, "peer_iface": dev.ifaces[0].name,
				"monitor_from": "srv2", "target_ip": "10.42.18.10",
				"started_cycle": Game.cycle, "evidence": [],
				"timeline": ["cycle %d · service monitor raised an availability alert" % Game.cycle]}
			sw.ifaces[0].enabled = false
			ui._refresh_tutorial()],
		["incident_diagnosis", func() -> void:
			Game.guided_outage["state"] = "diagnosed"
			Game.guided_outage["evidence"] = ["monitor", "physical", "l2"]
			Game.guided_outage["diagnosis"] = "access port administratively down"
			Game.guided_outage["downstream_clear"] = true
			Game.guided_outage["reputation_saved"] = 2
			ui._refresh_tutorial()],
		["incident_recovered", func() -> void:
			sw.ifaces[0].enabled = true
			Game.guided_outage["state"] = "recovered"
			Game.guided_outage["timeline"] = [
				"cycle 18 · service monitor raised an availability alert",
				"cycle 18 · alert acknowledged; investigation owner established",
				"cycle 18 · customer update posted; reputation loss reduced",
				"cycle 18 · physical cable seated; L2 access port found down",
				"cycle 19 · monitor green; delivery and billing restored"]
			ui._refresh_tutorial()],
		["incident_resilience", func() -> void:
			Game.guided_outage["state"] = "choice"
			ui._refresh_tutorial()],
		["customer_eye_live", func() -> void:
			Game.guided_outage["state"] = "complete"
			var deal: Dictionary = Game.deals[0]
			deal["healthy"] = true
			deal["ever_healthy"] = true
			deal["degraded"] = false
			deal["payment_state"] = "billing"
			ui.contracts_tab = "Jobs"
			ui.open_contracts()],
		["customer_eye_down", func() -> void:
			var deal: Dictionary = Game.deals[0]
			deal["healthy"] = false
			deal["payment_state"] = "suspended"
			ui._refresh_contracts()],
		["customer_eye_slow", func() -> void:
			var deal: Dictionary = Game.deals[0]
			deal["healthy"] = true
			deal["payment_state"] = "billing"
			deal["degraded"] = true
			ui._refresh_contracts()],
		["debrief_rackup", func() -> void:
			Game.active_contract_debrief = Game._opening_contract_debrief(Contracts.all()[0])
			Game.contract_debriefs["rackup"] = Game.active_contract_debrief
			ui.contracts_tab = "Jobs"
			ui._refresh_contracts()],
		["debrief_first_ping", func() -> void:
			Game.active_contract_debrief = Game._opening_contract_debrief(Contracts.all()[1])
			Game.contract_debriefs["first_ping"] = Game.active_contract_debrief
			ui._refresh_contracts()],
		["debrief_two_tenants", func() -> void:
			Game.set_access_vlan(sw.ifaces[0], 10)
			Game.set_access_vlan(sw.ifaces[1], 20)
			Game.active_contract_debrief = Game._opening_contract_debrief(Contracts.all()[2])
			Game.contract_debriefs["two_tenants"] = Game.active_contract_debrief
			ui._refresh_contracts()],
		["debrief_trunk", func() -> void:
			Game.active_contract_debrief = {"id": "stretch_vlans", "title": "Growing pains",
				"customer": "Alfa Ltd & Beta Kft", "reward": 1000,
				"proof": ["Tagged path: sw1 ether3 ⇄ sw2 Ethernet8; both ends are trunks.",
					"10.0.0.3 reaches 10.0.0.1 across that link while 10.0.0.2 remains isolated."],
				"concept": "802.1Q trunks carry several VLANs",
				"practice": "sw1: /interface bridge port print · sw2: show interfaces trunk",
				"avoided": "Both trunk ends agree; a one-sided trunk would drop tagged traffic.",
				"mastery": "Prune every inter-switch trunk to VLANs 10 and 20 only."}
			ui._refresh_contracts()],
		["debrief_failover", func() -> void:
			Game.active_contract_debrief = {"id": "redundant_core", "title": "One cable from disaster",
				"customer": "Alfa Ltd (again)", "reward": 1100,
				"proof": ["Parallel paths: sw1 ether3 ⇄ sw2 Ethernet8 / sw1 ether4 ⇄ sw2 Ethernet7.",
					"Spanning tree placed sw2 Ethernet7 in discarding state; Alfa still has one forwarding path."],
				"concept": "A loop-free spare path", "practice": "show spanning-tree",
				"avoided": "The second cable did not create a broadcast storm.",
				"mastery": "Disable the forwarding member and prove Alfa still crosses the spare."}
			ui._refresh_contracts()],
		["debrief_routing", func() -> void:
			Game.active_contract_debrief = {"id": "two_offices", "title": "Connect two offices",
				"customer": "Gamma Corp", "reward": 1200,
				"proof": ["office1 eth0 (192.168.1.10) → gateway rtr1 ether1 (192.168.1.1).",
					"rtr1 routes into ether2 (192.168.2.1) → office2 eth0 (192.168.2.10); replies return through the same router."],
				"concept": "A router joins different IP subnets",
				"practice": "/tool traceroute 192.168.2.10",
				"avoided": "Hosts do not pretend remote addresses are on their local wire.",
				"mastery": "Save the working configuration on rtr1."}
			ui._refresh_contracts()],
		["business_cashflow", func() -> void:
			Game.last_business = {"revenue": 162, "invoiced": 72, "collected": 72,
				"power": 34, "transit": 18}
			Game.last_cycle_delta = 20
			ui.contracts_tab = "Business"
			ui.open_contracts()],
		["night_call",
			func() -> void:
				# the phone, out of hours, with the floor empty
				Game.staff = []
				var ncrng := RandomNumberGenerator.new()
				ncrng.seed = 3
				Game.hire(Staff.make_candidate(ncrng, Game.habits))
				Staff.set_shift(Game.staff[0], "day")
				Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 7
				Game.hazards = [{"kind": "smoke", "rack": "R1", "site": 0, "tile": [0, 0],
					"severity": 2, "started": Game.cycle, "detected": true, "zone": ["R1"]}]
				Game.night_call = {}
				Game.night_call_tick()
				Game.active_contract_debrief = {}
				ui.contracts_tab = "Jobs"
				ui.open_contracts()],
		["business_staff",
			func() -> void:
				# the rota: shifts, who carries the phone, and who is tired
				var rng := RandomNumberGenerator.new()
				rng.seed = 11
				Game.staff = []
				for _i in 2:
					Game.hire(Staff.make_candidate(rng, Game.habits))
				if Game.staff.size() > 1:
					Game.set_oncall(String(Game.staff[0]["name"]))
					Game.staff[1]["tired_until"] = Game.cycle + 1
				ui.contracts_tab = "Business"
				ui.open_contracts(),
			func() -> void:
				ui._scroll_to_bottom()],  # the rota is at the bottom of the tab
		["contracts", func() -> void:
			ui.contracts_tab = "Jobs"
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
			ui.refresh_demo_end()
			ui._show_overlay(ui.demo_overlay)],
		["ops", func() -> void:
			ui.demo_overlay.visible = false
			ui.help_overlay.visible = false
			ui.toggle_ops()],
	]
	# and every Operations tab, with enough state in them to be worth looking at
	Game.decisions = [{"id": "workaround_vs_root", "raised": Game.cycle}]
	Game.audit = {"state": "offered", "customer": "Tisza Bank",
		"scope": ["incident_review", "config_history"], "reward": 4500,
		"deadline": Game.cycle + 6, "findings": [], "history": []}
	Game.tour = {"kind": "prospect", "cycle": Game.cycle + 3, "crammed": 0.0}
	Game.staff = [{"name": "Fekete Julia", "role": "engineer", "skill": 4, "salary": 480,
		"morale": 78, "shift": "day", "training_left": 0, "certs": [],
		"habits": {"saves": 0.8, "documents": 0.7, "windows": 0.6, "tidy": 0.7}}]
	Game.duties = {"parts": "Fekete Julia", "labels": "Fekete Julia"}
	Game.protection = {"detection": {"installed": true, "serviced_cycle": Game.cycle}}
	Game.crates = [{"model": "srv-1", "shipped": "srv-1", "ordered": Game.cycle,
		"due": Game.cycle + 2, "arrived": -1, "checked": false, "damaged": false,
		"unpack_left": 1}]
	Game.identity = "reliability"
	for tab_entry in UILayer.OPS_TABS:
		shots.append(["ops_%s" % String(tab_entry[0]).to_lower(), func() -> void:
			ui.ops_tab = String(tab_entry[0])
			if not ui.ops_overlay.visible:
				ui.toggle_ops()
			ui._refresh_ops()])
	shots.append(["finale", func() -> void:
		ui.toggle_ops()
		Game.end_run("retired")
		ui.toggle_ops()
		ui.ops_tab = "Company"
		ui._refresh_ops()])
	for shot in shots:
		shot[1].call()
		for _f in 16:  # let fades and layout settle
			await get_tree().process_frame
		if shot.size() > 2:
			# anything that needs real sizes (scroll positions) happens here,
			# once layout has actually run
			(shot[2] as Callable).call()
			for _f2 in 3:
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
	if not Game.last_link_load.is_empty():
		queue_redraw()  # traffic on the cables is animated, so keep painting
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
		($Floor as Node).reject_tile(tile, "OUTSIDE OWNED FLOOR")
		ui.hud_toast("That is outside %s. Expand the floor or pick another tile."
			% Game.site_name(Game.current_site))
		return
	if Game.rack_at(tile):
		($Floor as Node).reject_tile(tile, "CELL OCCUPIED")
		ui.hud_toast("There is already a rack there.")
		return
	if not Game.try_spend(Game.RACK_PRICE):
		($Floor as Node).reject_tile(tile, "NEED $%d" % Game.RACK_PRICE)
		ui.hud_toast("A rack costs $%d and you have $%d." % [Game.RACK_PRICE, Game.money])
		return
	add_child(RackVisual.new().setup(Game.add_rack(tile), true))
	Sfx.play("place")
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
	var progress := float(Game.stage) / maxf(float(Game.STAGES.size() - 1), 1.0)
	# Early installs sag between improvised rack runs; mature rooms route high,
	# neat, and out of the technicians' way.
	var mid := (p0 + p1) / 2.0 + Vector2(0, lerpf(-24.0, -64.0, progress))
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
		var blocked := Sim.stp_blocked(l.a) or Sim.stp_blocked(l.b)
		var progress := float(Game.stage) / maxf(float(Game.STAGES.size() - 1), 1.0)
		var live_cable := Color("db7948").lerp(Color("54d8dc"), progress)
		draw_polyline(pts, Color(0.55, 0.35, 0.3, 0.75) if blocked
			else Color(live_cable, 0.92), lerpf(2.6, 2.0, progress))
		if not blocked:
			_cable_flow(p0 + perp, p1 + perp, int(Game.last_link_load.get(l, 0)),
				Game.link_capacity(l))
	# packets in flight
	const DUR := 0.3
	for a in _anims:
		var t: float = (_anim_clock - a["t0"]) / DUR
		if t < 0.0 or t > 1.0:
			continue
		var pos := _tray(a["p0"], a["p1"], t)
		draw_circle(pos, 9.0, Color(a["col"], 0.25))
		draw_circle(pos, 4.5, a["col"])

func _cable_flow(p0: Vector2, p1: Vector2, load: int, cap: int) -> void:
	## a trickle of light along a cable that is carrying something, denser the
	## busier it is. A blocked or idle link shows nothing, which is the point.
	if load <= 0 or cap <= 0:
		return
	var share := clampf(float(load) / float(cap), 0.03, 1.0)
	var dots := 1 + int(share * 4.0)
	var clock := Time.get_ticks_msec() / 1000.0
	var col := Color(1.0, 0.85, 0.5) if share < 0.85 else Color(1.0, 0.45, 0.35)
	for k in dots:
		var f := fmod(clock * (0.15 + share * 0.35) + float(k) / dots, 1.0)
		draw_circle(_tray(p0, p1, f), 2.8, Color(col, 0.85))
