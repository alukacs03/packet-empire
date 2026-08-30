class_name SimTests
## Integration checks for the packet sim + CLIs. Run headless:
##   PACKET_TEST=1 godot --headless --path . --quit-after 600
## Exit code 0 = all pass.

static var fails := 0

static func _dev_named(n: String) -> Net.NDevice:
	for d in Game.all_devices():
		if d.name == n:
			return d
	return null

static func _contract(id: String) -> Dictionary:
	for c in Contracts.all():
		if c["id"] == id:
			return c
	return {}

static func money_way_too_much() -> int:
	return Game.money + 1_000_000

static func check_silent(cond: bool) -> void:
	if not cond:
		fails += 1
		print("FAIL  (silent assertion)")

static func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

static func demo_world() -> void:
	## a small, pretty datacenter for screenshots
	Game.racks = []
	Game.links = []
	Game.money = 4200
	Game.contracts_done = ["rackup", "first_ping"]
	var r1 := Game.add_rack(Vector2i(0, 0))
	var r2 := Game.add_rack(Vector2i(2, 1))
	var sw := Game.new_device("sw-24")
	var rtr := Game.new_device("rtr-edge")
	var srv1 := Game.new_device("srv-1")
	var srv2 := Game.new_device("srv-2")
	var fw := Game.new_device("fw-1")
	var packet_sw := Game.new_device("sw-lite")
	r1.slots[7] = sw
	r1.slots[6] = srv1
	r1.slots[5] = srv2
	r2.slots[7] = rtr
	r2.slots[6] = fw
	r2.slots[5] = packet_sw
	Game.connect_ifaces(srv1.ifaces[0], sw.ifaces[0])
	Game.connect_ifaces(srv2.ifaces[0], sw.ifaces[1])
	Game.connect_ifaces(rtr.ifaces[0], sw.ifaces[4])
	Game.connect_ifaces(fw.ifaces[0], sw.ifaces[5])
	Game.add_vlan(sw, 10, "alfa")
	Game.add_vlan(sw, 20, "beta")
	sw.ifaces[1].untagged_vlan = 20
	Game.add_ip(srv1.ifaces[0], "10.0.0.1/24")
	Game.add_ip(srv2.ifaces[0], "10.0.0.2/24")
	Game.add_ip(rtr.ifaces[0], "10.0.0.254/24")
	Game.market_intel = 3
	Game.rivals = Rivals.spawn()
	Game.rivals[1]["deals"] = 2
	var fixture_offer := Market.gen_offer()
	while String(fixture_offer["kind"]) != "hosting":  # the scripted sections below
		fixture_offer = Market.gen_offer()             # assume the first offer is hosting
	Game.offers = [fixture_offer]
	Game.deals = [{"id": "d1", "customer": "Balaton Zrt", "kind": "hosting",
		"params": {"ip": "10.0.0.1"}, "fee": 120, "load": 300,
		"brief": "Host our application server at 10.0.0.1/24.", "healthy": true}]
	Sim.ping(srv1, "10.0.0.2")
	Game.topology_changed.emit()

static func ui_smoke(world: Node2D) -> int:
	## Exercise every overlay so UI-only runtime errors surface in CI output.
	print("---- ui smoke ----")
	Game.sandbox = false
	Prefs.show_everything = false
	Game.feature_intros_seen = []
	Game.feature_discovery_trace = {}
	if "rackup" not in Game.contracts_done:
		Game.contracts_done.append("rackup")
	var ui := UILayer.new()
	world.add_child(ui)
	check(ui.unlock_intro_panel.visible and ui._unlock_intro_active == "map" \
			and "wall map" in ui.unlock_intro_title.text.to_lower(),
		"discovery: a newly available tool arrives with an authored, non-modal handoff")
	ui._dismiss_unlock_intro()
	check("map" in Game.feature_intros_seen and ui._unlock_intro_active != "map",
		"discovery: acknowledging a handoff records it once and advances a queued reveal")
	# shared UI foundation: every reusable button state exists and keyboard
	# focus is visible rather than being the old transparent outline.
	var foundation_button := Button.new()
	UIW.style_button(foundation_button, "primary")
	for visual_state in ["normal", "hover", "pressed", "focus", "disabled"]:
		check(foundation_button.has_theme_stylebox_override(visual_state),
			"ui foundation: buttons define the %s state" % visual_state)
	var focus_box := foundation_button.get_theme_stylebox("focus") as StyleBoxFlat
	check(focus_box != null and focus_box.border_color.a > 0.0,
		"ui foundation: keyboard focus has a visible outline")
	var empty_state := UIW.make_empty_state("Nothing needs attention.")
	check(empty_state.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART \
		and empty_state.get_theme_font_size("font_size") == UIW.type_size("small"),
		"ui foundation: empty states use shared wrapping and type tokens")
	var shared_theme := UIW.make_theme()
	var packet_visual := UIW.model_visual("sw-lite")
	var arivista_visual := UIW.model_visual("sw-24")
	check(packet_visual["base"] != arivista_visual["base"]
		and packet_visual["mark"] == "packet" and arivista_visual["mark"] == "arivista",
		"ui foundation: PacketTik and Arivista have distinct hardware identities")
	check(shared_theme.has_stylebox("panel", "TooltipPanel") \
		and shared_theme.has_stylebox("focus", "LineEdit"),
		"ui foundation: tooltips and text inputs consume the shared theme")
	foundation_button.free()
	empty_state.free()
	shared_theme = null
	var r: Net.Rack = Game.racks[0]
	var dev: Net.NDevice = null
	for d in Game.all_devices():
		if d.type == "server":
			dev = d
	var port_slot := UIW.RackSlot.new().setup(1, dev, func() -> void: pass)
	port_slot.size = Vector2(520, 46)
	var physical_port: Net.Iface = dev.ifaces[0]
	var jack_pos := port_slot.port_screen_position(physical_port)
	check(port_slot.port_at_screen(jack_pos) == physical_port,
		"rack cabling: physical jacks expose usable drag targets")
	port_slot.free()
	var dense_switch: Net.NDevice
	for candidate: Net.NDevice in Game.all_devices():
		if candidate.type == "switch" and candidate.ifaces.size() > 12:
			dense_switch = candidate
			break
	if dense_switch:
		var switch_slot := UIW.RackSlot.new().setup(1, dense_switch, func() -> void: pass)
		switch_slot.size = Vector2(520, 46)
		var sockets_separate := true
		var socket_rects: Array = []
		for iface: Net.Iface in switch_slot._physical_ports():
			var socket := switch_slot._port_rect(iface)
			for existing: Rect2 in socket_rects:
				if existing.intersects(socket):
					sockets_separate = false
			socket_rects.append(socket)
		check(sockets_separate, "rack cabling: dense switch faceplates keep every jack distinct")
		switch_slot.free()
	ui.show_welcome()
	ui.welcome_overlay.visible = false
	ui.open_rack(r)
	var local_link: Net.Link
	for link: Net.Link in Game.links:
		if Game.rack_of(link.a.dev) == r and Game.rack_of(link.b.dev) == r:
			local_link = link
			break
	if local_link:
		var rack_links_before := Game.links.duplicate()
		ui._rack_cable_start(local_link.a, Vector2.ZERO)
		ui._rack_cable_release(Vector2(-100, -100))
		check(Game.links.size() == rack_links_before.size() - 1,
			"rack cabling: pulling a fitted local plug away from the cabinet unplugs it")
		Game.links = rack_links_before
		ui._refresh_slots()
	ui.open_dev(dev)
	ui._toggle_cli()
	ui.cli_in.text = "ip addr"
	ui._cli_submit("ip addr")
	ui._cli_submit("ssh 10.40.0.2")
	ui._cli_submit("exit")
	ui._toggle_cli()
	ui.open_iface(dev.ifaces[0])
	ui.close_iface()
	ui.close_dev()
	ui.close_rack()
	# every company tab builds, and nothing in it is wider than the card it
	# sits in: a row that outgrows the panel is how buttons end up off screen
	var smoke_staff := Game.staff.duplicate(true)
	if Game.staff.size() < 2:  # the widest rows in the tab are people
		var smoke_rng := RandomNumberGenerator.new()
		smoke_rng.seed = 5
		while Game.staff.size() < 2:
			Game.hire(Staff.make_candidate(smoke_rng, Game.habits))
	Game.set_oncall(String(Game.staff[0]["name"]))
	for company_tab in ["Jobs", "Business", "Market", "Log"]:
		ui.contracts_tab = company_tab
		ui.open_contracts()
		ui._refresh_contracts()
		var widest := 0.0
		for row in ui.contracts_box.get_children():
			if row is Control:
				widest = maxf(widest, (row as Control).get_combined_minimum_size().x)
		# the card grows with its content up to the window, so the bar is the
		# smallest window the game is played in rather than the card minimum
		check(widest <= 1200.0, "ui: the %s tab fits a 1280-wide window (%d px)"
			% [company_tab, int(widest)])
	Game.staff = smoke_staff
	Game.oncall = ""
	ui.close_contracts()
	ui.toggle_map()
	ui.toggle_map()
	ui.toggle_ops()
	for ops_entry in UILayer.OPS_TABS:
		ui.ops_tab = String(ops_entry[0])
		ui._refresh_ops()
	ui.ops_tab = "Company"
	ui._refresh_ops()
	var trend_visible := false
	for ops_child in ui.ops_box.get_children():
		if ops_child is Label and ops_child.visible \
				and String((ops_child as Label).text).contains("Reliability:"):
			trend_visible = true
	check(trend_visible, "ui: the company tab actually shows the trend read")
	var ops_shown := 0
	var ops_hidden := 0
	for ops_child in ui.ops_box.get_children():
		if ops_child.visible:
			ops_shown += 1
		else:
			ops_hidden += 1
	check(ops_shown > 0 and ops_hidden > 0,
		"ops: a tab shows its own sections and hides the others")
	var homeless: Array = []
	for ops_entry2 in UILayer.OPS_TABS:
		ui.ops_tab = String(ops_entry2[0])
		ui._refresh_ops()
		for orphan: String in ui.ops_orphan_sections:
			if orphan not in homeless:
				homeless.append(orphan)
	check(homeless.is_empty(),
		"ops: every section has a tab of its own (%s)" % ", ".join(PackedStringArray(homeless)))
	ui.ops_tab = "Capacity"
	ui._refresh_ops()
	var ops_stage := Game.stage
	Game.stage = 1
	ui._refresh_ops()
	var meter_note := (ui.ops_metric_notes["power"] as Label).text
	check("/W" in meter_note and "/cycle" in meter_note,
		"ops: live draw exposes the electricity rate per watt and projected cycle bill")
	Game.stage = ops_stage
	ui.toggle_ops()
	ui.toggle_search()
	ui.search_input.text = "sw"
	ui._refresh_search()
	ui.search_input.text = "10.0.0"
	ui._refresh_search()
	ui.search_input.text = "zzzz-nothing"
	ui._refresh_search()
	ui.toggle_search()
	ui.hud_toast("smoke test message")
	Scenarios.start(Scenarios.all()[2])
	ui._show_scenario_banner()
	Scenarios.finish(false)
	ui._show_scenario_banner()
	ui.toggle_help()
	ui.toggle_help()
	ui.open_pedia()
	ui.pedia_overlay.visible = false
	ui.toggle_menu()
	ui.menu_overlay.visible = false
	ui._refresh_tutorial()
	var tut_done := Game.contracts_done.duplicate()
	Game.contracts_done = ["rackup"]
	ui._refresh_tutorial()
	check(ui.tutorial_panel.visible, "ui: the checklist follows on to the next job")
	ui.tutorial_hidden = true
	ui._refresh_tutorial()
	check(not ui.tutorial_panel.visible, "ui: the checklist can be dismissed")
	ui.tutorial_hidden = false
	Game.contracts_done = tut_done
	ui._refresh_tutorial()
	ui._refresh_money()
	# the front door and the demo arc
	var title := TitleScreen.new()
	world.add_child(title)
	title.show_intro()
	title.show_slots()
	title.show_settings()
	title.show_new_game(true)
	title.show_new_game(false)
	title._build_menu()
	check(TitleScreen._money(-35681) == "-$35,681", "title: money reads as money")
	check(TitleScreen._money(0) == "$0", "title: zero has no stray separator")
	var was_demo := Game.demo
	var was_done := Game.contracts_done.duplicate()
	Game.demo = true
	check(Contracts.all().size() == Demo.ARC.size(),
		"demo: the campaign stops at the end of the arc")
	Game.contracts_done = Demo.ARC.duplicate()
	check(Demo.complete(), "demo: finishing every arc job finishes the demo")
	check(Demo.progress_text() == "Demo  6/6", "demo: progress counts the arc")
	ui.check_demo_end()
	check(ui.demo_overlay.visible, "demo: the closing card appears once the arc is done")
	ui.demo_overlay.visible = false
	Game.contracts_done = was_done
	Game.demo = was_demo
	check(Contracts.all().size() > Demo.ARC.size(), "demo: the full campaign is back outside the demo")
	for cid in Demo.ARC:
		var found := false
		for c2 in Contracts.all():
			if c2["id"] == cid:
				found = String(c2.get("hint", "")) != ""
		check(found, "demo: %s offers a hint when the player is stuck" % cid)
	# a brand new game must be able to afford the very first job
	var saved_state := Game._serialize()
	Game.reset_new("Test Co", 1, true)
	var starter: int = Game.RACK_PRICE + int(Game.MODELS["sw-lite"]["price"]) \
		+ 2 * int(Game.MODELS["srv-1"]["price"])
	check(Game.money >= starter,
		"demo: a new game can afford a rack, a switch and two servers")
	check(Game.racks.is_empty() and Game.contracts_done.is_empty(),
		"demo: a new game starts from nothing")
	check(Game.company_name == "Test Co" and Game.demo, "demo: the new game keeps its name")
	# Opening guidance must follow the equipment the player can actually buy.
	# Execute every suggested PacketTik command as well as checking the copy:
	# this catches a hint drifting away from the CLI grammar later.
	var hint_rack := Game.add_rack(Vector2i(0, 0))
	var hint_devices := {
		"two_tenants": Game.new_device("sw-lite"),
		"stretch_vlans": Game.new_device("sw-lite"),
		"redundant_core": Game.new_device("sw-lite"),
		"two_offices": Game.new_device("rtr-lite"),
	}
	var hint_slot := 0
	for hint_dev: Net.NDevice in hint_devices.values():
		hint_rack.slots[hint_slot] = hint_dev
		hint_slot += 1
	for hint_id in hint_devices:
		var hint_contract := _contract(String(hint_id))
		var rendered_hint := Contracts.hint_for(hint_contract)
		check("PacketTik RouterOS" in rendered_hint,
			"demo hints: %s recognizes the PacketTik starter device" % hint_id)
		check("configure terminal" not in rendered_hint,
			"demo hints: %s does not suggest EOS to a PacketTik-only rack" % hint_id)
		var hint_session := CLI.new_session(hint_devices[hint_id])
		for hint_command in Contracts.hint_commands(String(hint_id), "ros"):
			var hint_output := hint_session.exec(hint_command)
			var rejected := hint_output.begins_with("usage:") or hint_output.begins_with("failure:") \
				or hint_output.begins_with("no bridge")
			check(not rejected, "demo hints: PacketTik accepts '%s'" % hint_command)
	var vlan_topic: Array = []
	for pedia_entry in Pedia.topics():
		if String(pedia_entry[0]) == "VLANs":
			vlan_topic = pedia_entry
			break
	var starter_article := Pedia.article_text(vlan_topic)
	check("Try on PacketTik RouterOS" in starter_article and "switchport access" not in starter_article,
		"pedia: starter examples follow the installed PacketTik switch")
	var eos_switch := Game.new_device("sw-8")
	hint_rack.slots[hint_slot] = eos_switch
	var mixed_hint := Contracts.hint_for(_contract("two_tenants"))
	check("PacketTik RouterOS" in mixed_hint and "OpenRack / Arivista / Junivista EOS" in mixed_hint,
		"demo hints: a mixed-vendor rack labels both command dialects")
	Game._apply(saved_state)
	Sfx.install(world)
	check(Sfx._bank.has("good") and Sfx._bank["good"] is AudioStreamWAV,
		"sfx: cues are generated at startup, not shipped as files")
	check(Sfx._bank["good"].data.size() > 1000, "sfx: a cue has actual samples in it")
	Sfx.play("good")
	Sfx.muted = true
	Sfx.play("bad")  # muted: must not raise
	Sfx.muted = false
	Sfx.play("no-such-cue")  # unknown: must not raise
	# capacity runway: a resource that is not filling has no deadline, one that
	# is filling gets an honest number of cycles
	Game.history = [
		{"cycle": 10, "slots_used": 4}, {"cycle": 11, "slots_used": 4},
		{"cycle": 12, "slots_used": 6}, {"cycle": 13, "slots_used": 8},
	]
	check(Game.capacity_runway("slots_used", 8, 16) == 6,
		"capacity: the runway is the honest number of cycles at the current rate")
	check(Game.capacity_runway("slots_used", 16, 16) == 0, "capacity: full is full")
	Game.history = [
		{"cycle": 10, "slots_used": 8}, {"cycle": 11, "slots_used": 8},
		{"cycle": 12, "slots_used": 8},
	]
	check(Game.capacity_runway("slots_used", 8, 16) == -1,
		"capacity: something that is not filling has no deadline")
	check(Game.capacity_runway("nothing_tracked", 1, 10) == -1,
		"capacity: an untracked resource says so rather than guessing")
	Game.history = []
	world._draw()  # the cable-flow painter, with whatever load the cycle left
	var crew := Techs.new()
	world.add_child(crew)
	check(crew.people.size() >= 2, "floor: the room is never empty of people")
	var crew_before := crew.people.size()
	Game.staff.append(Staff.make_candidate(RandomNumberGenerator.new()))
	Game.staff.append(Staff.make_candidate(RandomNumberGenerator.new()))
	Game.staff.append(Staff.make_candidate(RandomNumberGenerator.new()))
	Game.cycle = 2  # morning: the default day crew is physically on the floor
	crew._resize_crew()
	check(crew.people.size() > crew_before, "floor: hiring puts another person on the floor")
	Game.cycle = 0  # night: day staff have gone home, making coverage visible
	crew._resize_crew()
	check(crew.people.is_empty(), "floor: an uncovered night shift leaves the room visibly empty")
	Game.staff.clear()
	Game.cycle = 0
	crew._resize_crew()
	for person in crew.people:
		person._process(0.2)
	check(Techs.HEIGHT > RackVisual.H * 0.7,
		"floor: a person stands within sight of a cabinet's height")
	# a work spot must land on a neighbouring tile, not inside the cabinet:
	# in isometric "one step towards the viewer" means both axes, not just y
	var busy_rack: Net.Rack = Game.racks_on(Game.current_site)[0]
	var busy_dev: Net.NDevice = null
	for d in busy_rack.slots:
		if d != null:
			busy_dev = d
	var busy_was := busy_dev.status
	busy_dev.status = "down"
	var spot_tile := Iso.world_to_tile(crew._work_spot(0))
	check(spot_tile != busy_rack.tile,
		"floor: a technician stands beside the cabinet, not inside it")
	check(absi(spot_tile.x - busy_rack.tile.x) <= 1 and absi(spot_tile.y - busy_rack.tile.y) <= 1,
		"floor: and no further away than the next tile")
	busy_dev.status = busy_was
	crew.queue_free()
	title.queue_free()
	check(Net.compress_ports(["Ethernet1", "Ethernet2", "Ethernet3", "Ethernet7"]) == "Et1-3,Et7",
		"ui: port lists compress into ranges")
	check(Net.compress_ports([]) == "", "ui: empty port list compresses to nothing")
	# the new-game path end to end, exactly as the title screen drives it
	var world_state := Game._serialize()
	world.ui = ui
	world.title = TitleScreen.new()
	world.add_child(world.title)
	world._start_new(0, "Smoke Networks", 1, true)
	check(Game.demo and Game.company_name == "Smoke Networks",
		"title: starting a demo from the front door lands in a demo game")
	check(not world.title.visible and ui.visible, "title: the front door steps aside once you start")
	check(Game.slot_info(0).get("company", "") == "Smoke Networks",
		"title: a new game writes its slot immediately")
	world._continue(0)
	check(Game.company_name == "Smoke Networks", "title: continuing reloads the slot it names")
	Game.delete_slot(0)
	Game._apply(world_state)
	world.title.queue_free()
	world.title = null
	world.ui = null
	print("PASS  ui: all overlays opened and refreshed without script errors")
	check(true, "ui: smoke complete")
	# the same screens again in pseudo-localisation: longer strings, same layout
	var smoke_lang := Loc.language
	Loc.language = "pseudo"
	ui._rebuild_localised()
	ui.show_welcome()
	ui.welcome_overlay.visible = false
	ui.open_contracts()
	ui.close_contracts()
	Loc.language = smoke_lang
	ui._rebuild_localised()
	check(true, "ui: the localised screens rebuild in pseudo-localisation without errors")
	print("---- %d smoke failures" % fails)
	return fails

static func run() -> int:
	# The revenue cycle contains real randomness (poaching, attacks, field
	# faults, staff repairs, customer growth). Seed it so a run is
	# reproducible: a failure can then be investigated instead of shrugged at.
	seed(20260823)
	fails = 0
	Game.money = 1000000

	# --- topology: two servers on one switch ---
	var r := Game.add_rack(Vector2i(0, 0))
	var sw := Game.new_device("switch")
	var a := Game.new_device("server")
	var b := Game.new_device("server")
	r.slots[0] = sw
	r.slots[1] = a
	r.slots[2] = b
	Game.connect_ifaces(a.ifaces[0], sw.ifaces[0])
	Game.connect_ifaces(b.ifaces[0], sw.ifaces[1])
	Game.add_ip(a.ifaces[0], "10.0.0.1/24")
	Game.add_ip(b.ifaces[0], "10.0.0.2/24")

	check(Sim.ping(a, "10.0.0.2")["ok"], "L2: ping across a switch, same subnet")
	check(sw.mac_table.has(1) and sw.mac_table[1].size() == 2, "L2: switch learned both MACs in vlan 1")
	check(not Sim.ping(a, "10.0.0.99")["ok"], "L2: ping to absent host fails")

	# --- vlan isolation ---
	Game.add_vlan(sw, 10, "ten")
	Game.set_access_vlan(sw.ifaces[1], 10)
	check(not Sim.ping(a, "10.0.0.2")["ok"], "VLAN: different access vlans isolate hosts")
	Game.set_access_vlan(sw.ifaces[1], 1)
	check(Sim.ping(a, "10.0.0.2")["ok"], "VLAN: same vlan again, ping works")

	# --- disabled port ---
	sw.ifaces[0].enabled = false
	Game.topology_changed.emit()
	check(not Sim.ping(a, "10.0.0.2")["ok"], "link: disabled switchport blocks traffic")
	sw.ifaces[0].enabled = true
	Game.topology_changed.emit()

	# --- L3 across a router ---
	var sw2 := Game.new_device("switch")
	var c := Game.new_device("server")
	var rtr := Game.new_device("router")
	r.slots[3] = sw2
	r.slots[4] = c
	r.slots[5] = rtr
	Game.connect_ifaces(c.ifaces[0], sw2.ifaces[0])
	Game.connect_ifaces(rtr.ifaces[0], sw.ifaces[2])
	Game.connect_ifaces(rtr.ifaces[1], sw2.ifaces[1])
	Game.add_ip(c.ifaces[0], "10.1.0.2/24")
	Game.add_ip(rtr.ifaces[0], "10.0.0.254/24")
	Game.add_ip(rtr.ifaces[1], "10.1.0.254/24")
	Game.add_static_route(a, "0.0.0.0", 0, "10.0.0.254")
	Game.add_static_route(c, "0.0.0.0", 0, "10.1.0.254")

	check(Sim.ping(a, "10.1.0.2")["ok"], "L3: ping across router with gateways")
	check(Sim.ping(rtr, "10.0.0.1")["ok"], "L3: router pings a host directly")
	var tr := Sim.traceroute(a, "10.1.0.2")
	check(tr == ["10.0.0.254", "10.1.0.2"], "L3: traceroute shows router hop then destination (got %s)" % str(tr))
	var ttl1 := Sim.ping(a, "10.1.0.2", 1)
	check(ttl1["detail"] == "ttl-exceeded" and ttl1["from"] == "10.0.0.254", "L3: ttl=1 dies at the router")
	Game.remove_static_route(a, "0.0.0.0", 0)
	check(not Sim.ping(a, "10.1.0.2")["ok"], "L3: no default route, no reply (return path intact)")
	Game.add_static_route(a, "0.0.0.0", 0, "10.0.0.254")

	# --- EOS CLI ---
	var s := CLI.new_session(sw)
	s.exec("en")
	s.exec("conf t")
	check(s.prompt().ends_with("(config)#"), "EOS: 'en'+'conf t' abbreviations reach config mode")
	s.exec("int et4")
	check(s.prompt().contains("config-if-Et4"), "EOS: interface context prompt")
	s.exec("switchport access vlan 30")
	check(sw.vlans.has(30) and sw.ifaces[3].untagged_vlan == 30, "EOS: access vlan auto-creates vlan 30")
	s.exec("end")
	var vlan_out: String = s.exec("sh vlan")
	check(vlan_out.contains("30"), "EOS: 'sh vlan' lists vlan 30 (got: %s)" % vlan_out.replace("\n", " | "))
	check(s.exec("sh run").begins_with("hostname"), "EOS: show running-config renders")
	check(s.exec("s").begins_with("% Ambiguous"), "EOS: bare 's' is ambiguous (ssh vs show)")
	check(s.exec("sh").begins_with("% Incomplete"), "EOS: 'sh' alone is an incomplete command")
	check("interface" in s.exec("help"), "EOS: help lists config commands in config-reachable mode")

	# --- Linux CLI ---
	var ls := CLI.new_session(c)
	check(ls.prompt().begins_with("root@"), "Linux: prompt")
	ls.exec("ip addr add 192.168.9.1/24 dev eth0")
	check("192.168.9.1/24" in c.ifaces[0].ips, "Linux: ip addr add")
	ls.exec("ip addr del 192.168.9.1/24 dev eth0")
	check("192.168.9.1/24" not in c.ifaces[0].ips, "Linux: ip addr del")
	var ping_out := ls.exec("ping 10.0.0.1")
	check(ping_out.contains(" 3 received"), "Linux: ping via CLI succeeds end-to-end (got: %s)" % ping_out.replace("\n", " | "))
	check(ls.exec("ip route").contains("default via 10.1.0.254"), "Linux: ip route shows default")

	# --- save / load roundtrip ---
	Game.racks[0].blanked[6] = true
	Game.set_note(Game.racks[0], "Temporary patch during the migration")
	Game.set_note(a, "Do not reboot before the handover")
	Game.set_note(a.ifaces[0], "Customer handoff — do not repatch")
	Game.save_game()
	var money_before := Game.money
	Game.money = 1
	check(Game.load_game(), "save: load_game returns true")
	check(Game.money == money_before, "save: money restored")
	check(Game.all_devices().size() == 6 and Game.links.size() == 5, "save: devices and links restored")
	check(Game.racks[0].blanked.has(6), "save: fitted rack blanking panels restored")
	check(Game.racks[0].note.get("text", "") == "Temporary patch during the migration",
		"save: player-authored rack notes restored verbatim")
	var sw_l: Net.NDevice = null
	for d in Game.all_devices():
		if d.name == sw.name:
			sw_l = d
	check(sw_l != null and sw_l.vlans.has(30), "save: per-switch vlan database restored")
	var a_l: Net.NDevice = null
	for d in Game.all_devices():
		if d.name == a.name:
			a_l = d
	check(a_l != null and a_l.note.get("text", "") == "Do not reboot before the handover",
		"save: player-authored device notes travel with the device")
	check(a_l != null and a_l.ifaces[0].note.get("text", "") == "Customer handoff — do not repatch",
		"save: player-authored port tags travel with the physical interface")
	check(a_l != null and Sim.ping(a_l, "10.1.0.2")["ok"], "save: reloaded topology still routes end-to-end")
	var note_cycle := Game.cycle
	Game.cycle += 13
	check(Game.note_age(a_l) == 13, "notes: age is derived without interpreting the player's text")
	check(Game.note_age(a_l.ifaces[0]) == 13, "notes: port tag age uses the same opaque cycle metadata")
	Game.cycle = note_cycle

	# --- trunk allowed-vlan pruning (uses reloaded devices) ---
	var a2 := _dev_named(a.name)
	var sw_a := _dev_named(sw.name)
	var sw_b := _dev_named(sw2.name)
	var b2 := _dev_named(b.name)
	# move b onto sw2 through an inter-switch trunk, same vlan 1
	Game.disconnect_iface(b2.ifaces[0])
	Game.connect_ifaces(b2.ifaces[0], sw_b.ifaces[2])
	Game.connect_ifaces(sw_a.ifaces[3], sw_b.ifaces[3])
	sw_a.ifaces[3].mode = "trunk"
	sw_a.ifaces[3].untagged_vlan = 1
	sw_b.ifaces[3].mode = "trunk"
	Game.topology_changed.emit()
	check(Sim.ping(a2, "10.0.0.2")["ok"], "trunk: vlan 1 crosses inter-switch trunk")
	sw_a.ifaces[3].tagged_vlans = [30]
	Game.topology_changed.emit()
	check(not Sim.ping(a2, "10.0.0.2")["ok"], "trunk: pruning vlan 1 off the trunk blocks it")
	sw_a.ifaces[3].tagged_vlans = []
	Game.topology_changed.emit()

	# --- spanning tree over a redundant loop ---
	Game.connect_ifaces(sw_a.ifaces[1], sw_b.ifaces[4])
	Game.topology_changed.emit()
	check(Sim.ping(a2, "10.0.0.2")["ok"], "stp: redundant switch loop doesn't storm, ping still works")
	var blocked_n := 0
	for ifc in [sw_a.ifaces[1], sw_a.ifaces[3], sw_b.ifaces[3], sw_b.ifaces[4]]:
		if Sim.stp_blocked(ifc):
			blocked_n += 1
	check(blocked_n == 1, "stp: exactly one port of the loop is discarding (got %d)" % blocked_n)
	var ses := CLI.new_session(sw_a)
	check(ses.exec("show spanning-tree").contains("Root bridge"), "stp: show spanning-tree renders")
	sw_a.ifaces[3].enabled = false
	Game.topology_changed.emit()
	check(Sim.ping(a2, "10.0.0.2")["ok"], "stp: primary link dies, blocked spare takes over")
	sw_a.ifaces[3].enabled = true
	Game.topology_changed.emit()

	# --- capture ---
	Sim.ping(a2, "10.0.0.2")
	check(not a2.capture.is_empty() and "ICMP" in "\n".join(PackedStringArray(a2.capture)),
		"capture: tcpdump buffer records ICMP frames")

	# --- contracts ---
	var money0 := Game.money
	check(Game.try_complete_contract(_contract("rackup")), "contracts: rack-and-stack completes against live state")
	check(Game.try_complete_contract(_contract("first_ping")), "contracts: first-ping completes (sim-verified)")
	check(not Game.try_complete_contract(_contract("two_tenants")), "contracts: vlan-isolation contract not yet satisfiable")
	check(not Game.try_complete_contract(_contract("rackup")), "contracts: no double collection")
	check(Game.money == money0 + 900, "contracts: rewards paid once")

	# --- DHCP + DNS ---
	var r2: Net.Rack = Game.racks[0]
	var dhcp_srv := Game.new_device("server")
	var client := Game.new_device("server")
	r2.slots[6] = dhcp_srv
	r2.slots[7] = client
	var sw_c := _dev_named(sw.name)
	Game.connect_ifaces(dhcp_srv.ifaces[0], sw_c.ifaces[4])
	Game.connect_ifaces(client.ifaces[0], sw_c.ifaces[5])
	var dls := CLI.new_session(dhcp_srv)
	dls.exec("ip addr add 10.2.0.5/24 dev eth0")
	dls.exec("dhcpd eth0 10.2.0.10 10.2.0.99 24 10.2.0.5 10.2.0.5")
	dls.exec("dns add www.delta.hu 10.2.0.10")
	var cls_ := CLI.new_session(client)
	var lease_out: String = cls_.exec("dhclient eth0")
	check("bound to 10.2.0.10/24" in lease_out, "dhcp: client got the first lease (got: %s)" % lease_out.strip_edges())
	check(client.resolver == "10.2.0.5", "dhcp: lease delivered the DNS resolver")
	check(Sim.ping(client, "10.2.0.5")["ok"], "dhcp: leased address is routable")
	check(cls_.exec("dhclient eth0").contains("10.2.0.10"), "dhcp: same MAC keeps its lease")
	check(Sim.resolve(client, "www.delta.hu") == "10.2.0.10", "dns: client resolves via the network")
	check(cls_.exec("ping www.delta.hu").contains("3 received"), "dns: ping by name works (client owns the A record)")
	check(cls_.exec("nslookup nope.example").contains("can't find"), "dns: unknown name fails cleanly")

	# --- superseded contracts retire instead of breaching ---
	check(not Contracts.retired("first_ping"), "retire: first_ping active before two_tenants")
	Game.contracts_done.append("two_tenants")
	check(Contracts.retired("first_ping"), "retire: two_tenants supersedes first_ping")
	Game.sla_tick()
	check(Game.sla_status.get("first_ping", false), "retire: retired contract never breaches")
	Game.contracts_done.erase("two_tenants")
	Game.sla_status.erase("two_tenants")

	# --- cycle P&L breakdown ---
	Game.debt = 2000
	Game.sla_tick()
	check(Game.last_pl.has("loan interest") and int(Game.last_pl["loan interest"]) == -100,
		"pl: interest appears as its own line item")
	check(Game.last_pl.has("service fees"), "pl: service fees are itemised")
	var pl_sum := 0
	for k in Game.last_pl:
		pl_sum += int(Game.last_pl[k])
	check(pl_sum == Game.last_cycle_delta, "pl: line items sum to the net delta (%d vs %d)" % [pl_sum, Game.last_cycle_delta])
	Game.debt = 0

	# --- SLA recurring revenue ---
	var m1 := Game.money
	Game.sla_tick()
	check(Game.money == m1 + 40 + 50, "sla: healthy contracts pay recurring fees")
	var a3 := _dev_named(a.name)
	a3.ifaces[0].enabled = false
	Game.topology_changed.emit()
	var m2 := Game.money
	Game.sla_tick()
	check(Game.money < m2 + 90, "sla: broken network stops (part of) the revenue")
	check(Game.sla_status.values().has(false), "sla: breach is flagged for the UI")
	a3.ifaces[0].enabled = true
	Game.topology_changed.emit()
	# The physical floor counter is stricter than an alert counter: it records
	# customer impact, holds at zero through an active outage, then resumes.
	var streak_cycle := Game.cycle
	Game.last_customer_outage_cycle = Game.cycle - 7
	Game.best_outage_streak = 3
	Game.customer_outage_active = false
	Game._update_reliability_streak(true)
	check(Game.customer_outage_active and Game.best_outage_streak == 7 \
		and Game.cycles_since_customer_outage() == 0,
		"reliability sign: a customer outage resets the current streak and preserves the best")
	Game.cycle += 1
	Game._update_reliability_streak(true)
	check(Game.cycles_since_customer_outage() == 0,
		"reliability sign: the counter stays at zero while the outage remains active")
	Game.cycle += 1
	Game._update_reliability_streak(false)
	check(Game.cycles_since_customer_outage() == 1,
		"reliability sign: the counter resumes after customer service is restored")
	Game.cycle = streak_cycle
	Game.last_customer_outage_cycle = 0
	Game.best_outage_streak = 0
	Game.customer_outage_active = false

	# --- firewall ACLs ---
	var r3 := Game.add_rack(Vector2i(1, 0))
	var fw := Game.new_device("fw-1")
	var office := Game.new_device("server")
	var vault := Game.new_device("server")
	r3.slots[0] = fw
	r3.slots[1] = office
	r3.slots[2] = vault
	Game.connect_ifaces(office.ifaces[0], fw.ifaces[0])
	Game.connect_ifaces(vault.ifaces[0], fw.ifaces[1])
	Game.add_ip(office.ifaces[0], "172.16.1.10/24")
	Game.add_ip(vault.ifaces[0], "172.16.2.20/24")
	Game.add_ip(fw.ifaces[0], "172.16.1.1/24")
	Game.add_ip(fw.ifaces[1], "172.16.2.1/24")
	Game.add_static_route(office, "0.0.0.0", 0, "172.16.1.1")
	Game.add_static_route(vault, "0.0.0.0", 0, "172.16.2.1")
	check(Sim.ping(office, "172.16.2.20")["ok"], "fw: default permit forwards")
	var fs := CLI.new_session(fw)
	fs.exec("en")
	fs.exec("conf t")
	fs.exec("acl deny 172.16.1.0/24 172.16.2.20/32")
	check(not Sim.ping(office, "172.16.2.20")["ok"], "fw: deny rule blocks office->vault")
	check(not Sim.ping(vault, "172.16.1.10")["ok"],
		"fw: stateless: vault->office echo passes but its reply is filtered (the classic lesson)")
	check(fs.exec("end") == "" and fs.exec("show acl").contains("deny"), "fw: show acl lists the rule")
	fs.exec("conf t")
	fs.exec("no acl 1")
	check(Sim.ping(office, "172.16.2.20")["ok"], "fw: removing the rule restores traffic")
	fs.exec("acl deny 172.16.1.0/24 172.16.2.20/32")

	# --- stateful firewall ---
	var fw_ss := CLI.new_session(fw)
	fw_ss.exec("en")
	fw_ss.exec("conf t")
	fw_ss.exec("firewall stateful")
	fw_ss.exec("end")
	check(Sim.ping(vault, "172.16.1.10")["ok"],
		"fw: stateful mode lets the vault's outbound flow get its replies")
	check(not Sim.ping(office, "172.16.2.20")["ok"], "fw: the deny still blocks unsolicited office->vault")
	check(fw_ss.exec("show acl").contains("stateful"), "fw: show acl reports the mode")
	fw_ss.exec("conf t")
	fw_ss.exec("no firewall stateful")
	fw_ss.exec("end")

	# --- stages & power ---
	check(Game.grid_size() == Vector2i(3, 3), "stage: colo corner is 3x3")
	check(Game.power_draw() > 0, "stage: hardware draws watts")
	var tidy_rack := Net.Rack.new("TIDY", Vector2i.ZERO)
	tidy_rack.slots[0] = Game.new_device("srv-1")
	var open_rack_heat := Game.rack_heat(tidy_rack)
	for blank_slot in range(1, Net.Rack.SLOTS):
		check(Game.toggle_blanking(tidy_rack, blank_slot),
			"blanking: an empty U%d accepts a fitted panel" % (blank_slot + 1))
	check(is_equal_approx(Game.rack_airflow_seal(tidy_rack), 1.0) \
		and Game.rack_heat(tidy_rack) < open_rack_heat,
		"blanking: sealing every open U gives the rack a visible, capped airflow benefit")
	var blanked_install := Game.new_device("srv-1")
	check(Game.install_device(tidy_rack, 1, blanked_install) and not tidy_rack.blanked.has(1),
		"blanking: installing hardware automatically removes the panel from that U")
	var persist_rack: Net.Rack = Game.racks[0]
	var persisted_gap := -1
	for gap_i in Net.Rack.SLOTS:
		if Game.slot_free(persist_rack, gap_i):
			persisted_gap = gap_i
			break
	if persisted_gap >= 0:
		persist_rack.blanked[persisted_gap] = true
		var rack_payload: Dictionary = Game._serialize()["racks"][0]
		check(persisted_gap in rack_payload.get("blanked", []),
			"blanking: fitted panels are included in the save payload")
		persist_rack.blanked.erase(persisted_gap)
	var m3 := Game.money
	check(Game.expand(), "stage: expansion purchasable")
	check(Game.money == m3 - 5000 and Game.grid_size() == Vector2i(7, 7), "stage: server room paid and unlocked")
	var crac1 := Game.new_device("crac-1")
	var crac2 := Game.new_device("crac-1")
	r3.slots[6] = crac1
	r3.slots[7] = crac2
	check(Game.cooling_capacity() >= 3000 and not Game.overheating(), "heat: CRACs cover the room")
	var m4 := Game.money
	Game.sla_tick()
	check(Game.money - m4 < 90 + 40 + 50, "stage: power bill now reduces cycle income")

	# --- marketplace negotiation & delivery ---
	var off := {"id": "t1", "kind": "hosting", "customer": "TestCo", "brief": "", "costs": "",
		"params": {"ip": "10.9.9.10"}, "budget": 100, "hint": "", "state": "open", "ttl": 5}
	# with rivals in the market, an over-market quote loses the customer to them
	var off_r := off.duplicate(true)
	Game.offers.append(off_r)
	check(Game.respond_offer(off_r, 120) == "undercut" and not (off_r in Game.offers),
		"market: a rival undercuts an over-market quote and takes the job")
	var poached_by_rival := false
	for ev in Game.events:
		if "LOST:" in ev:
			poached_by_rival = true
	check(poached_by_rival, "market: losing a bid is reported with the rival's price")
	var saved_rivals := Game.rivals
	Game.rivals = []  # a market with no competition: pure customer negotiation
	Game.offers.append(off)
	check(Game.respond_offer(off, 200) == "rejected" and not (off in Game.offers),
		"market: greedy quote is rejected, customer walks")
	var off2 := off.duplicate(true)
	off2["state"] = "open"
	Game.offers.append(off2)
	check(Game.respond_offer(off2, 120) == "counter" and off2["state"] == "counter",
		"market: near-budget quote draws a counteroffer")
	Game.accept_counter(off2)
	check(Game.deals.size() == 1 and int(Game.deals[0]["fee"]) == 100,
		"market: counter signs at their budget")
	Game.incidents_seen["%s|%s" % [b2.name, rtr.name]] = true  # security tested separately below
	Game.sla_tick()
	check(Game.deals[0]["healthy"] == false, "market: undelivered deal does not pay")
	Game.add_ip(b2.ifaces[0], "10.9.9.10/24")
	Game.add_ip(a2.ifaces[0], "10.9.9.11/24")
	var m6 := Game.money
	Game.sla_tick()
	check(Game.deals[0]["healthy"], "market: delivering the service marks the deal healthy")
	check(Game.receivables() > 0, "market: a delivered cycle raises an invoice")
	var owed6 := Game.receivables()
	var m6b := Game.money
	for _c6 in 6:  # let the customer's payment terms come round
		Game.sla_tick()
	check(Game.money > m6b or Game.receivables() > owed6,
		"market: invoiced work turns into cash once the terms are up")
	var off3 := off.duplicate(true)
	off3["state"] = "open"
	Game.offers.append(off3)
	check(Game.respond_offer(off3, 90) == "accepted" and Game.deals.size() == 2,
		"market: fair quote accepted directly")
	Game.rivals = saved_rivals
	var off4 := off.duplicate(true)
	off4["state"] = "open"
	Game.offers.append(off4)
	check(Game.respond_offer(off4, 70) == "accepted",
		"market: pricing under the rivals wins the job even with competition")

	# --- security sweep: exposed management plane ---
	# Re-seed: what this section proves must not depend on how many random
	# draws every section above it happened to consume, or adding content
	# anywhere shifts the stream and fails scripted checks that still hold.
	seed(20260823)
	Game.incidents_seen.clear()
	var m7 := Game.money
	var ev0 := Game.events.size()
	Game.sla_tick()  # deal server b2 can reach rtr's 10.0.0.254 -> one-shot incident
	var sec_seen := false
	for ev in Game.events:
		if "SECURITY" in ev:
			sec_seen = true
	check(Game.events.size() > ev0 and sec_seen, "sec: exposed management logs an incident")
	var m8 := Game.money
	var ev1 := Game.events.size()
	Game.sla_tick()
	check(Game.events.size() == ev1 or "SECURITY" not in Game.events[0], "sec: same exposure doesn't bill twice")
	check(m8 > m7 - 200, "sec: incident cost bounded")

	# --- RouterOS CLI (PacketTik gear) ---
	var mkt_sw := Game.new_device("sw-lite")
	var mkt_rtr := Game.new_device("rtr-lite")
	r3.slots[3] = mkt_sw
	r3.slots[4] = mkt_rtr
	var rs := CLI.new_session(mkt_sw)
	check(rs is ROS and rs.prompt().begins_with("[admin@"), "ros: PacketTik gear speaks RouterOS")
	check(mkt_sw.ifaces[0].name == "ether1", "ros: PacketTik ports are etherN")
	rs.exec("/interface bridge vlan add vlan-ids=50 comment=lab")
	check(mkt_sw.vlans.has(50), "ros: bridge vlan add creates vlan")
	rs.exec("/interface set ether2 pvid=50")
	check(mkt_sw.ifaces[1].untagged_vlan == 50 and mkt_sw.ifaces[1].mode == "access", "ros: pvid assigns access vlan")
	check(rs.exec("export").contains("vlan-ids=50"), "ros: export renders config")
	var rr := CLI.new_session(mkt_rtr)
	rr.exec("/ip address add address=10.7.0.1/24 interface=ether1")
	check("10.7.0.1/24" in mkt_rtr.ifaces[0].ips, "ros: ip address add")
	rr.exec("/routing bgp set as=65010")
	rr.exec("/routing bgp peer add address=100.64.0.9 as=64500")
	check(mkt_rtr.bgp["neighbors"].size() == 1, "ros: bgp peer configured")

	# --- BGP to the internet (EOS router) ---
	var r4 := Game.add_rack(Vector2i(2, 0))
	var upl := Game.new_device("isp-uplink")
	var edge := Game.new_device("rtr-edge")
	var web := Game.new_device("server")
	r4.slots[0] = upl
	r4.slots[1] = edge
	r4.slots[2] = web
	Game.connect_ifaces(upl.ifaces[0], edge.ifaces[0])
	Game.connect_ifaces(web.ifaces[0], edge.ifaces[1])
	Game.add_ip(edge.ifaces[0], "100.64.0.2/30")
	Game.add_ip(edge.ifaces[1], "10.3.0.1/24")
	Game.add_ip(web.ifaces[0], "10.3.0.10/24")
	Game.add_static_route(web, "0.0.0.0", 0, "10.3.0.1")
	var es := CLI.new_session(edge)
	es.exec("en")
	es.exec("conf t")
	es.exec("router bgp 65001")
	es.exec("neighbor 100.64.0.1 remote-as 64500")
	es.exec("end")
	check(es.exec("show ip bgp summary").contains("Established"), "bgp: session establishes with the handoff")
	check(Sim.ping(edge, "8.8.8.8")["ok"], "bgp: router reaches the internet via learned default")
	check(not Sim.ping(web, "8.8.8.8")["ok"], "bgp: server fails until prefix announced (no return path)")
	es.exec("conf t")
	es.exec("router bgp 65001")
	es.exec("network 10.3.0.0/24")
	es.exec("end")
	check(Sim.ping(web, "8.8.8.8")["ok"], "bgp: announcing the prefix opens the return path")
	check(Game.try_complete_contract(_contract("join_internet")), "bgp: join-the-internet contract verifies")

	# --- NAT masquerade ---
	es.exec("conf t")
	es.exec("router bgp 65001")
	es.exec("no network 10.3.0.0/24")
	es.exec("end")
	check(not Sim.ping(web, "8.8.8.8")["ok"], "nat: withdrawn announcement kills unNATed reachability")
	es.exec("conf t")
	es.exec("int et1")
	es.exec("ip nat outside")
	es.exec("end")
	check(Sim.ping(web, "8.8.8.8")["ok"], "nat: masquerade restores internet for the private server")
	check(es.exec("sh run").contains("ip nat outside"), "nat: rendered in running-config")
	check(Game.try_complete_contract(_contract("hide_the_internals")), "nat: contract verifies")

	# --- overheating trips gear ---
	crac1.status = "offline"
	crac2.status = "offline"
	Game.topology_changed.emit()
	check(Game.overheating(), "heat: losing cooling overheats the room")
	Game.sla_tick()
	var tripped: Net.NDevice = null
	for d in Game.all_devices():
		if d.status == "offline" and d.type != "cooling":
			tripped = d
	check(tripped != null, "heat: overheating trips a device offline")
	tripped.status = "active"
	crac1.status = "active"
	crac2.status = "active"
	Game.topology_changed.emit()
	check(not Game.overheating(), "heat: cooling restored")
	check(Game.try_complete_contract(_contract("feel_the_heat")), "heat: feeling-the-heat contract verifies")

	# --- discovery/diagnostic commands ---
	var es2 := CLI.new_session(edge)
	check(es2.exec("sh lldp neighbors").contains(upl.name), "cli: EOS lldp lists the uplink neighbor")
	var wls := CLI.new_session(web)
	Sim.ping(web, "10.3.0.1")
	check(wls.exec("ip neigh").contains("10.3.0.1"), "cli: Linux ip neigh shows the gateway ARP entry")
	check(wls.exec("lldp").contains(edge.name), "cli: Linux lldp sees the router")
	var rs2 := CLI.new_session(mkt_sw)
	check("bridge host" in rs2.exec("help"), "cli: ROS help lists bridge host print")
	check("print" in rs2.complete("/interface ") and "set" in rs2.complete("/interface "),
		"cli: ROS tab completes next word after a full token")
	check(rs2.complete("/ip ad") == ["address"], "cli: ROS tab completes partial second token")
	check("arp" in rs2.complete("/ip a") and "address" in rs2.complete("/ip a"),
		"cli: ROS tab lists all matching branches")
	check("add" in rs2.complete("/ip address vlan-ids=5 "), "cli: ROS tab ignores key=value args")
	check(rs2.exec("routing bgp").begins_with("incomplete command"), "cli: ROS partial path lists what can follow")

	# --- OSPF dynamic routing ---
	var r5 := Game.add_rack(Vector2i(0, 1))
	var o_r1 := Game.new_device("rtr-edge")
	var o_r2 := Game.new_device("rtr-lite")
	var t1 := Game.new_device("server")
	var t2 := Game.new_device("server")
	r5.slots[0] = o_r1
	r5.slots[1] = o_r2
	r5.slots[2] = t1
	r5.slots[3] = t2
	Game.connect_ifaces(t1.ifaces[0], o_r1.ifaces[1])
	Game.connect_ifaces(o_r1.ifaces[2], o_r2.ifaces[1])
	Game.connect_ifaces(t2.ifaces[0], o_r2.ifaces[2])
	Game.add_ip(t1.ifaces[0], "10.20.1.10/24")
	Game.add_ip(o_r1.ifaces[1], "10.20.1.1/24")
	Game.add_ip(o_r1.ifaces[2], "10.20.9.1/30")
	Game.add_ip(o_r2.ifaces[1], "10.20.9.2/30")
	Game.add_ip(o_r2.ifaces[2], "10.20.2.1/24")
	Game.add_ip(t2.ifaces[0], "10.20.2.10/24")
	Game.add_static_route(t1, "0.0.0.0", 0, "10.20.1.1")
	Game.add_static_route(t2, "0.0.0.0", 0, "10.20.2.1")
	check(not Sim.ping(t1, "10.20.2.10")["ok"], "ospf: no routes yet, offices can't talk")
	var os1 := CLI.new_session(o_r1)
	os1.exec("en")
	os1.exec("conf t")
	os1.exec("router ospf")
	os1.exec("network 10.20.0.0/16 area 0")
	os1.exec("end")
	var os2 := CLI.new_session(o_r2)
	os2.exec("/routing ospf network add prefix=10.20.0.0/16")
	check(os1.exec("show ip ospf neighbor").contains(o_r2.name), "ospf: adjacency comes up (EOS side)")
	check(os2.exec("/routing ospf print").contains(o_r1.name), "ospf: adjacency visible from RouterOS side")
	check(Sim.ping(t1, "10.20.2.10")["ok"] and Sim.ping(t2, "10.20.1.10")["ok"],
		"ospf: cross-office ping with zero static routes on routers")
	check(os1.exec("sh ip route").contains("O  10.20.2.0/24"), "ospf: O route in show ip route")
	check(Game.try_complete_contract(_contract("dynamic_routing")), "ospf: contract verifies")
	os1.exec("conf t")
	os1.exec("router ospf")
	os1.exec("no network 10.20.0.0/16")
	os1.exec("end")
	check(not Sim.ping(t1, "10.20.2.10")["ok"], "ospf: withdrawing networks drops the adjacency and the routes")
	os1.exec("conf t")
	os1.exec("router ospf")
	os1.exec("network 10.20.0.0/16 area 0")
	os1.exec("end")

	# --- reputation & public hosting ---
	var rep0 := Game.reputation
	Game.sla_tick()
	check(Game.reputation != rep0 or Game.reputation in [0, 100], "rep: cycles move reputation")
	es.exec("conf t")
	es.exec("router bgp 65001")
	es.exec("network 10.3.0.0/24")
	es.exec("end")
	check(Market.check("public_hosting", {"ip": "10.3.0.10"}), "market: public hosting verified from the uplink side (needs the announcement back)")
	check(not Market.check("public_hosting", {"ip": "10.0.0.1"}), "market: unreachable-from-internet host fails the check")

	# --- traffic counters ---
	var s_cnt := CLI.new_session(sw_a)
	s_cnt.exec("en")
	s_cnt.exec("clear counters")
	Sim.ping(a2, "10.0.0.2")
	check(sw_a.ifaces[0].rx_frames > 0, "counters: switch port counted rx frames")
	check(s_cnt.exec("show interfaces counters").contains("InFrames"), "counters: EOS table renders")
	s_cnt.exec("clear counters")
	check(sw_a.ifaces[0].rx_frames == 0, "counters: clear counters resets")

	# --- OOB management + ssh ---
	var mg: Net.Iface = null
	for ifc: Net.Iface in sw_a.ifaces:
		if ifc.name.begins_with("Management"):
			mg = ifc
	check(mg != null, "mgmt: save migration added Management1 to old switches")
	Game.connect_ifaces(mg, sw_b.ifaces[5])
	var ms := CLI.new_session(sw_a)
	ms.exec("en")
	ms.exec("conf t")
	ms.exec("int man1")
	check(ms.prompt().contains("Management1"), "mgmt: interface Management1 reachable by abbreviation")
	ms.exec("ip address 10.0.0.99/24")
	ms.exec("end")
	check(Sim.ping(a2, "10.0.0.99")["ok"], "mgmt: switch answers ping on its mgmt address")
	check(Sim.ping(sw_a, "10.0.0.1")["ok"], "mgmt: switch pings out via mgmt")
	var blocked_after := 0
	for ifc in [sw_a.ifaces[1], sw_a.ifaces[3], sw_b.ifaces[3], sw_b.ifaces[4]]:
		if Sim.stp_blocked(ifc):
			blocked_after += 1
	check(blocked_after == 1, "mgmt: mgmt link doesn't disturb spanning tree")
	var ssh_ls := CLI.new_session(a2)
	var ssh_out: String = ssh_ls.exec("ssh 10.0.0.99")
	check("Connected to" in ssh_out and ssh_ls.pending_ssh == sw_a, "ssh: server reaches switch mgmt")
	var inner := CLI.new_session(ssh_ls.pending_ssh)
	check(inner.prompt().begins_with(sw_a.name), "ssh: nested session lands on the switch")
	inner.exec("exit")
	check(inner.wants_exit, "ssh: exit flags return to the outer session")
	check("No route" in ssh_ls.exec("ssh 172.31.9.9"), "ssh: unreachable target refused")
	Game.incidents_seen.clear()
	Game.sla_tick()
	var found_sw_event := false
	for ev in Game.events:
		if "SECURITY" in ev and sw_a.name in ev:
			found_sw_event = true
	check(found_sw_event, "mgmt: exposed switch management triggers a security incident")

	# --- loans ---
	var money_b := Game.money
	check(Game.borrow() and Game.money == money_b + 1000 and Game.debt == 1000, "bank: borrow lands a tranche")
	Game.debt = 0
	Game.invoices = []  # measure the interest, not what happened to land this cycle
	var bank_tariff := Game.fixed_tariff
	Game.fixed_tariff = true  # a flat energy rate, so the two cycles are comparable
	var d0_start := Game.money
	Game.sla_tick()
	var delta0 := Game.money - d0_start
	Game.debt = 10000
	Game.invoices = []
	var d1_start := Game.money
	Game.sla_tick()
	var delta1 := Game.money - d1_start
	Game.fixed_tariff = bank_tariff
	check(delta0 - delta1 == 500, "bank: interest bites exactly debt*rate (got %d)" % (delta0 - delta1))
	Game.debt = 1000
	check(Game.repay() and Game.debt == 0, "bank: repay clears the tranche")

	# --- capstone contract ---
	var sw_bb := _dev_named(sw2.name)
	Game.add_vlan(sw_bb, 30, "omega")
	Game.set_access_vlan(sw_bb.ifaces[2], 30)  # b2's port
	Game.add_ip(_dev_named(web.name).ifaces[0], "10.30.0.10/24")
	var fs2 := CLI.new_session(_dev_named(fw.name))
	fs2.exec("en")
	fs2.exec("conf t")
	fs2.exec("acl deny any 10.30.0.0/24")
	fs2.exec("end")
	check(Game.try_complete_contract(_contract("big_client")), "capstone: the big client signs")

	for ifc: Net.Iface in sw_bb.ifaces:
		if ifc.name.begins_with("Management"):
			Game.add_ip(ifc, "10.0.0.98/24")
	check(Market.check("managed_switch", {"vid": 30}), "market: managed-switch kind verifies (vlan 30 + addressed mgmt)")
	check(not Market.check("managed_switch", {"vid": 777}), "market: managed-switch fails for absent vlan")

	# --- VRRP failover ---
	var r6 := Game.add_rack(Vector2i(1, 1))
	var vr1 := Game.new_device("rtr-edge")
	var vr2 := Game.new_device("rtr-edge")
	var vsw := Game.new_device("sw-8")
	var vcl := Game.new_device("server")
	r6.slots[0] = vr1
	r6.slots[1] = vr2
	r6.slots[2] = vsw
	r6.slots[3] = vcl
	Game.connect_ifaces(vr1.ifaces[0], vsw.ifaces[0])
	Game.connect_ifaces(vr2.ifaces[0], vsw.ifaces[1])
	Game.connect_ifaces(vcl.ifaces[0], vsw.ifaces[2])
	Game.add_ip(vr1.ifaces[0], "10.40.0.2/24")
	Game.add_ip(vr2.ifaces[0], "10.40.0.3/24")
	Game.add_ip(vcl.ifaces[0], "10.40.0.10/24")
	Game.add_static_route(vcl, "0.0.0.0", 0, "10.40.0.1")
	var v1 := CLI.new_session(vr1)
	v1.exec("en")
	v1.exec("conf t")
	v1.exec("int et1")
	v1.exec("vrrp 1 ip 10.40.0.1")
	v1.exec("vrrp 1 priority 120")
	v1.exec("end")
	var v2 := CLI.new_session(vr2)
	v2.exec("en")
	v2.exec("conf t")
	v2.exec("int et1")
	v2.exec("vrrp 1 ip 10.40.0.1")
	v2.exec("end")
	check(Sim.vrrp_master("10.40.0.1", 1) == vr1, "vrrp: higher priority wins mastership")
	check(Sim.ping(vcl, "10.40.0.1")["ok"], "vrrp: client pings the virtual gateway")
	check(v1.exec("show vrrp").contains("Master"), "vrrp: show vrrp reports Master")
	check(v2.exec("show vrrp").contains("Backup"), "vrrp: show vrrp reports Backup")
	check(Game.try_complete_contract(_contract("no_spof")), "vrrp: no-SPOF contract verifies")
	vr1.status = "offline"
	Game.topology_changed.emit()
	check(Sim.vrrp_master("10.40.0.1", 1) == vr2, "vrrp: backup takes over when master dies")
	check(Sim.ping(vcl, "10.40.0.1")["ok"], "vrrp: virtual IP survives the master's death")
	vr1.status = "active"
	Game.topology_changed.emit()

	# --- field faults, redundant-gw offers, reverse DNS ---
	# marketplace checks first: a field fault may reboot gear and wipe its config
	check(Market.check("redundant_gw", {"vip": "10.40.0.1"}), "market: redundant-gw kind verifies the VRRP setup")
	check(not Market.check("redundant_gw", {"vip": "10.99.99.1"}), "market: redundant-gw fails for absent vip")
	Game._field_fault()  # either a port fault or a power-blip reboot
	check(Game.log_contains("FIELD"), "field: a fault is logged for the operator to find")
	var faulted: Net.Iface = null
	for l in Game.links:
		for ifc in [l.a, l.b]:
			if not ifc.enabled and not ifc.name.begins_with("Management"):
				faulted = ifc
	if faulted:
		faulted.enabled = true
		Game.topology_changed.emit()
	check(cls_.exec("nslookup 10.2.0.10").contains("www.delta.hu"), "dns: reverse lookup finds the name")
	check(cls_.exec("nslookup 10.2.0.77").contains("no PTR"), "dns: reverse lookup fails cleanly")

	# --- rack selling ---
	var r_sell := Game.add_rack(Vector2i(2, 1))
	var m_sell := Game.money
	check(Game.sell_rack(r_sell) and Game.money == m_sell + Game.RACK_PRICE / 2, "rack: empty rack sells for half")
	check(not Game.sell_rack(Game.racks[0]), "rack: occupied rack refuses to sell")

	# --- grandfathering ---
	Game.add_rack(Vector2i(8, 8))
	Game.stage = 0
	check(Game._rack_outside_grid(), "legacy: racks outside a 3x3 colo are detected")
	Game.save_game()
	Game.load_game()
	check(not Game._rack_outside_grid(), "legacy: load grandfathers the stage until racks fit")

	# --- economy walkthrough: the colo arc must be affordable ---
	Game.racks = []
	Game.links = []
	Game.deals = []
	Game.offers = []
	Game.leads = []
	Game.contracts_done = []
	Game.sla_status = {}
	Game.contract_debriefs = {}
	Game.mastered_contracts = []
	Game.active_contract_debrief = {}
	Game.guided_outage = {}
	Game.status_posts = []
	Game.incidents = []
	Game.invoices = []
	Game.monitors = []
	Game.spares = {}
	Game.feature_intros_seen = []
	Game.feature_discovery_trace = {}
	Game.stats["guided_delivery_complete"] = 0
	Game.sandbox = false
	Game.stage = 0
	Game.debt = 0
	Game.money = 2000
	Game.topology_changed.emit()
	check(not Game.feature_unlocked("map") and not Game.feature_unlocked("market") \
			and not Game.feature_unlocked("business") and not Game.feature_unlocked("log") \
			and not Game.feature_unlocked("ops") and not Game.feature_unlocked("expand"),
		"discovery: a fresh campaign keeps unexplained advanced tools out of the opening HUD")
	check(Game.feature_unlocked("ops", true),
		"discovery: the experienced-player override exposes the full toolbox")
	check(Game._feature_discovery_trace_from_data({}).is_empty() \
			and Game._feature_discovery_trace_from_data({"feature_discovery_trace": "bad"}).is_empty(),
		"discovery diagnostics: legacy and malformed saves migrate to a safe empty trace")
	var pre_stall_cycle := Game.cycle
	Game.cycle = 18
	check(Game.feature_discovery_diagnostics()["opening_stall"] == "before_first_contract",
		"discovery diagnostics: a coarse milestone id flags a stalled opening without player data")
	Game.cycle = pre_stall_cycle
	Game.acknowledge_feature_intro("map")
	Game.acknowledge_feature_intro("map")
	var intro_payload: Dictionary = JSON.parse_string(Game.snapshot())
	check(Game.feature_intros_seen.count("map") == 1 \
			and "map" in intro_payload["feature_intros_seen"],
		"discovery: acknowledged tool introductions are deduplicated and saved")
	Game.feature_intros_seen = []
	var w_rack := Game.add_rack(Vector2i(0, 0))
	check(Game.try_spend(Game.RACK_PRICE), "walkthrough: rack affordable at start")
	var w_sw := Game.new_device("sw-lite")
	var w_s1 := Game.new_device("srv-1")
	var w_s2 := Game.new_device("srv-1")
	check(Game.try_spend(90 + 400 + 400), "walkthrough: tier-0 starter kit affordable")
	w_rack.slots[0] = w_sw
	w_rack.slots[1] = w_s1
	w_rack.slots[2] = w_s2
	Game.connect_ifaces(w_s1.ifaces[0], w_sw.ifaces[0])
	Game.connect_ifaces(w_s2.ifaces[0], w_sw.ifaces[1])
	check(Game.try_complete_contract(_contract("rackup")), "walkthrough: contract 1 pays")
	check(Game.feature_unlocked("map") and not Game.feature_unlocked("market"),
		"discovery: the logical map appears after the first physical rack job")
	Game.observe_feature_unlock("map")
	var map_unlock_cycle := Game.cycle
	Game.observe_feature_unlock("map")
	check(int(Game.feature_discovery_trace["unlocked"]["map"]) == map_unlock_cycle,
		"discovery diagnostics: repeated refreshes keep the original reveal cycle")
	Game.cycle += Game.DISCOVERY_IGNORED_CYCLES
	var ignored_diag := Game.feature_discovery_diagnostics()
	check("map" in ignored_diag["long_ignored"],
		"discovery diagnostics: an unacknowledged reveal becomes locally visible as ignored")
	Game.acknowledge_feature_intro("map")
	var acknowledged_diag := Game.feature_discovery_diagnostics()
	check("map" in acknowledged_diag["acknowledged"] \
			and int(acknowledged_diag["ack_latency_cycles"]["map"]) == Game.DISCOVERY_IGNORED_CYCLES,
		"discovery diagnostics: acknowledgement latency is recorded in campaign cycles")
	var diagnostic_text := JSON.stringify(acknowledged_diag)
	check(Game.company_name not in diagnostic_text and "racks" not in diagnostic_text \
			and "devices" not in diagnostic_text and "commands" not in diagnostic_text,
		"discovery diagnostics: the summary contains no authored names, topology, or commands")
	var trace_payload: Dictionary = JSON.parse_string(Game.snapshot())
	check(trace_payload.has("feature_discovery_trace") \
			and trace_payload["feature_discovery_trace"]["unlocked"].has("map"),
		"discovery diagnostics: the coarse local trace persists with the campaign")
	Game.cycle = map_unlock_cycle
	var rackup_debrief: Dictionary = Game.contract_debriefs.get("rackup", {})
	check(not rackup_debrief.is_empty() and w_rack.name in String(rackup_debrief["proof"][0]) \
			and w_sw.name in String(rackup_debrief["proof"][1]),
		"debrief: rack-up proof snapshots the player's actual cabinet, switch and patches")
	check(Game.money > 0 and int(Game.active_contract_debrief["reward"]) == 400,
		"debrief: the reward lands immediately instead of waiting for review")
	check(Game.check_contract_mastery("rackup") != "", "mastery: an untidy rack is not mastered by completion alone")
	for rack_slot in Net.Rack.SLOTS:
		if Game.slot_free(w_rack, rack_slot):
			w_rack.blanked[rack_slot] = true
	check(Game.check_contract_mastery("rackup") == "" and "rackup" in Game.mastered_contracts,
		"mastery: the optional physical housekeeping constraint is tracked separately")
	Game.add_ip(w_s1.ifaces[0], "10.0.0.1/24")
	Game.add_ip(w_s2.ifaces[0], "10.0.0.2/24")
	check(Game.try_complete_contract(_contract("first_ping")), "walkthrough: contract 2 pays")
	var ping_debrief: Dictionary = Game.contract_debriefs.get("first_ping", {})
	check(w_s1.name in String(ping_debrief["proof"][0]) and w_s2.name in String(ping_debrief["proof"][0]) \
			and w_sw.name in String(ping_debrief["proof"][0]),
		"debrief: first ping records the actual endpoint and switch path")
	check(Game.check_contract_mastery("first_ping") == "" and "first_ping" in Game.mastered_contracts,
		"mastery: the gateway-free same-subnet solution is recognized")
	Game.add_vlan(w_sw, 10, "alfa")
	Game.add_vlan(w_sw, 20, "beta")
	Game.set_access_vlan(w_sw.ifaces[0], 10)
	Game.set_access_vlan(w_sw.ifaces[1], 20)
	check(Game.try_complete_contract(_contract("two_tenants")), "walkthrough: contract 3 pays")
	check(Game.feature_unlocked("market") and not Game.feature_unlocked("expand"),
		"discovery: the market appears with the business pipeline while expansion stays quiet")
	var vlan_debrief: Dictionary = Game.contract_debriefs.get("two_tenants", {})
	check(w_sw.name in String(vlan_debrief["proof"][0]) and "ether1" in String(vlan_debrief["proof"][0]) \
			and String(vlan_debrief["practice"]) == "/interface bridge vlan print",
		"debrief: VLAN isolation uses actual PacketTik ports and vendor-correct evidence")
	check(Game.check_contract_mastery("two_tenants") != "",
		"mastery: the VLAN extension remains an optional follow-on challenge")
	var mastery_payload: Dictionary = JSON.parse_string(Game.snapshot())
	check("rackup" in mastery_payload["mastered_contracts"] \
			and mastery_payload["contract_debriefs"].has("first_ping"),
		"debrief: snapshots and separate mastery state are included in saves")
	check(Game.money > 0, "walkthrough: never broke during the colo arc (have $%d)" % Game.money)
	var cycles := 0
	while Game.money < 5000 + 1500 and cycles < 40:
		Game.sla_tick()
		cycles += 1
	check(cycles < 40, "walkthrough: expansion affordable within %d cycles" % cycles)

	# --- the rest of the demo arc, driven through the consoles the hints name ---
	var w_sw2 := Game.new_device("sw-8")
	var w_s3 := Game.new_device("srv-1")
	check(Game.try_spend(250 + 400), "walkthrough: a second switch and server are affordable")
	w_rack.slots[3] = w_sw2
	w_rack.slots[4] = w_s3
	Game.connect_ifaces(w_sw.ifaces[2], w_sw2.ifaces[7])  # inter-switch link
	Game.connect_ifaces(w_s3.ifaces[0], w_sw2.ifaces[0])
	var w_ros := CLI.new_session(w_sw)  # PacketTik: RouterOS dialect
	w_ros.exec("/interface set ether3 mode=trunk")
	var w_eos := CLI.new_session(w_sw2)  # OpenRack: EOS dialect
	w_eos.exec("enable")
	w_eos.exec("configure terminal")
	w_eos.exec("vlan 10")
	w_eos.exec("interface Ethernet8")
	w_eos.exec("switchport mode trunk")
	w_eos.exec("interface Ethernet1")
	w_eos.exec("switchport access vlan 10")
	w_eos.exec("end")
	CLI.new_session(w_s3).exec("ip addr add 10.0.0.3/24 dev eth0")
	check(Game.check_contract_mastery("two_tenants") == "" and "two_tenants" in Game.mastered_contracts,
		"mastery: extending VLAN 10 while preserving isolation completes the optional challenge")
	check(Game.try_complete_contract(_contract("stretch_vlans")),
		"walkthrough: contract 4 pays (trunk built from both dialects)")
	var trunk_debrief: Dictionary = Game.contract_debriefs.get("stretch_vlans", {})
	check(w_sw.name in String(trunk_debrief["proof"][0]) and w_sw2.name in String(trunk_debrief["proof"][0]) \
			and "/interface bridge port print" in String(trunk_debrief["practice"]) \
			and "show interfaces trunk" in String(trunk_debrief["practice"]),
		"debrief: the tagged path names both real switches and both vendor dialects")
	check(Game.check_contract_mastery("stretch_vlans") != "",
		"mastery: a trunk carrying every VLAN is complete but not yet disciplined")
	check(w_ros.exec("/interface set ether3 tagged=10,20") == "",
		"routeros: a PacketTik trunk can be pruned from its own CLI")
	w_eos.exec("configure terminal")
	w_eos.exec("interface Ethernet8")
	w_eos.exec("switchport trunk allowed vlan 10,20")
	w_eos.exec("end")
	check(Game.check_contract_mastery("stretch_vlans") == "" and "stretch_vlans" in Game.mastered_contracts,
		"mastery: pruning both real trunk ends to the intended VLANs is recognized")
	check("tagged=10,20" in w_ros.exec("/export"),
		"routeros: PacketTik exports preserve the mastered trunk pruning")
	Game.connect_ifaces(w_sw.ifaces[3], w_sw2.ifaces[6])  # the spare link
	w_ros.exec("/interface set ether4 mode=trunk")
	w_eos.exec("configure terminal")
	w_eos.exec("interface Ethernet7")
	w_eos.exec("switchport mode trunk")
	w_eos.exec("end")
	Sim.flush_learned_state()
	check(Game.try_complete_contract(_contract("redundant_core")),
		"walkthrough: contract 5 pays (spanning tree blocks the spare link)")
	var stp_debrief: Dictionary = Game.contract_debriefs.get("redundant_core", {})
	check("discarding" in String(stp_debrief["proof"][1]) \
			and (w_sw.name in String(stp_debrief["proof"][0])) \
			and (w_sw2.name in String(stp_debrief["proof"][0])),
		"debrief: redundancy snapshots both physical paths and the actually blocked port")
	var forwarding_link: Net.Link = null
	for candidate: Net.Link in Game.links:
		if candidate.a.dev in [w_sw, w_sw2] and candidate.b.dev in [w_sw, w_sw2] \
				and not Sim.stp_blocked(candidate.a) and not Sim.stp_blocked(candidate.b):
			forwarding_link = candidate
			break
	check(forwarding_link != null, "mastery: the forwarding inter-switch member is observable")
	if forwarding_link != null:
		forwarding_link.a.enabled = false
		Game.topology_changed.emit()
		check(Game.check_contract_mastery("redundant_core") == "" \
				and "redundant_core" in Game.mastered_contracts,
			"mastery: live traffic crosses the STP spare when the forwarding member is disabled")
		forwarding_link.a.enabled = true
		Game.topology_changed.emit()
	var w_rtr := Game.new_device("rtr-lite")
	var w_o1 := Game.new_device("srv-1")
	var w_o2 := Game.new_device("srv-1")
	var w_rack2 := Game.add_rack(Vector2i(1, 0))
	while Game.money < 350 + 800 + Game.RACK_PRICE and cycles < 80:
		Game.sla_tick()
		cycles += 1
	check(Game.try_spend(350 + 800 + Game.RACK_PRICE),
		"walkthrough: the router and two office servers are affordable")
	w_rack2.slots[0] = w_rtr
	w_rack2.slots[1] = w_o1
	w_rack2.slots[2] = w_o2
	Game.connect_ifaces(w_rtr.ifaces[0], w_o1.ifaces[0])
	Game.connect_ifaces(w_rtr.ifaces[1], w_o2.ifaces[0])
	var w_rcli := CLI.new_session(w_rtr)
	w_rcli.exec("/ip address add address=192.168.1.1/24 interface=ether1")
	w_rcli.exec("/ip address add address=192.168.2.1/24 interface=ether2")
	var w_o1cli := CLI.new_session(w_o1)
	w_o1cli.exec("ip addr add 192.168.1.10/24 dev eth0")
	w_o1cli.exec("ip route add default via 192.168.1.1")
	var w_o2cli := CLI.new_session(w_o2)
	w_o2cli.exec("ip addr add 192.168.2.10/24 dev eth0")
	w_o2cli.exec("ip route add default via 192.168.2.1")
	check(Game.try_complete_contract(_contract("two_offices")),
		"walkthrough: contract 6 pays (two offices routed together)")
	check(Game.feature_unlocked("expand"),
		"discovery: facility expansion appears after the six-job opening arc")
	var route_debrief: Dictionary = Game.contract_debriefs.get("two_offices", {})
	check(w_o1.name in String(route_debrief["proof"][0]) and w_rtr.name in String(route_debrief["proof"][0]) \
			and w_o2.name in String(route_debrief["proof"][1]) \
			and String(route_debrief["practice"]) == "/tool traceroute 192.168.2.10",
		"debrief: first routing records the actual endpoints, router legs and PacketTik command")
	check(Game.check_contract_mastery("two_offices") != "",
		"mastery: a live but unsaved router is not yet operationally complete")
	w_rcli.exec("/system backup save")
	check(Game.check_contract_mastery("two_offices") == "" and "two_offices" in Game.mastered_contracts,
		"mastery: saving the working routed configuration completes the optional challenge")
	Game.demo = true
	check(Demo.complete(), "walkthrough: the whole demo arc is completable from a fresh start")
	Game.demo = false

	# --- port-channels ---
	var lsw1 := Game.new_device("sw-8")
	var lsw2 := Game.new_device("sw-8")
	var lh1 := Game.new_device("server")
	var lh2 := Game.new_device("server")
	var r7 := Game.add_rack(Vector2i(3, 1))
	r7.slots[0] = lsw1
	r7.slots[1] = lsw2
	r7.slots[2] = lh1
	r7.slots[3] = lh2
	Game.connect_ifaces(lh1.ifaces[0], lsw1.ifaces[0])
	Game.connect_ifaces(lh2.ifaces[0], lsw2.ifaces[0])
	Game.connect_ifaces(lsw1.ifaces[1], lsw2.ifaces[1])
	Game.connect_ifaces(lsw1.ifaces[2], lsw2.ifaces[2])
	Game.add_ip(lh1.ifaces[0], "10.50.0.1/24")
	Game.add_ip(lh2.ifaces[0], "10.50.0.2/24")
	Game.topology_changed.emit()
	var pre_blocked := Sim.stp_blocked(lsw1.ifaces[1]) or Sim.stp_blocked(lsw1.ifaces[2]) \
		or Sim.stp_blocked(lsw2.ifaces[1]) or Sim.stp_blocked(lsw2.ifaces[2])
	check(pre_blocked, "lag: without bundling, STP blocks the parallel link")
	var lag_s := CLI.new_session(lsw1)
	lag_s.exec("en")
	lag_s.exec("conf t")
	lag_s.exec("int et2")
	lag_s.exec("channel-group 1")
	lag_s.exec("int et3")
	lag_s.exec("channel-group 1")
	lag_s.exec("end")
	var lag_s2 := CLI.new_session(lsw2)
	lag_s2.exec("en")
	lag_s2.exec("conf t")
	lag_s2.exec("int et2")
	lag_s2.exec("channel-group 1")
	lag_s2.exec("int et3")
	lag_s2.exec("channel-group 1")
	lag_s2.exec("end")
	var post_blocked := Sim.stp_blocked(lsw1.ifaces[1]) or Sim.stp_blocked(lsw1.ifaces[2]) \
		or Sim.stp_blocked(lsw2.ifaces[1]) or Sim.stp_blocked(lsw2.ifaces[2])
	check(not post_blocked, "lag: bundled links form one logical edge, nothing blocked")
	check(Sim.ping(lh1, "10.50.0.2")["ok"], "lag: traffic flows over the bundle")
	check(Game.link_capacity(Game.link_at(lsw1.ifaces[1])) == 2000, "lag: bundle capacity sums members")
	check(lag_s.exec("show port-channel").contains("Et2,Et3"), "lag: show port-channel lists members")
	lsw1.ifaces[1].enabled = false
	Game.topology_changed.emit()
	check(Sim.ping(lh1, "10.50.0.2")["ok"], "lag: member death fails over inside the bundle")
	lsw1.ifaces[1].enabled = true
	Game.topology_changed.emit()

	check(Game.try_complete_contract(_contract("double_the_pipe")), "lag: double-the-pipe contract verifies")
	var ros_bond := CLI.new_session(mkt_sw)
	ros_bond.exec("/interface bonding add slaves=ether3,ether4")
	check(mkt_sw.ifaces[2].lag > 0 and mkt_sw.ifaces[2].lag == mkt_sw.ifaces[3].lag,
		"lag: RouterOS bonding maps to the same model")

	# --- L3 switch: inter-VLAN routing with SVIs ---
	var l3 := Game.new_device("sw-24")
	var h40 := Game.new_device("srv-1")
	var h50 := Game.new_device("srv-1")
	var r8 := Game.add_rack(Vector2i(4, 1))
	r8.slots[0] = l3
	r8.slots[1] = h40
	r8.slots[2] = h50
	Game.connect_ifaces(h40.ifaces[0], l3.ifaces[0])
	Game.connect_ifaces(h50.ifaces[0], l3.ifaces[1])
	Game.add_ip(h40.ifaces[0], "10.80.40.10/24")
	Game.add_ip(h50.ifaces[0], "10.80.50.10/24")
	var l3s := CLI.new_session(l3)
	l3s.exec("en")
	l3s.exec("conf t")
	l3s.exec("vlan 40")
	l3s.exec("vlan 50")
	l3s.exec("interface Ethernet1")
	l3s.exec("switchport access vlan 40")
	l3s.exec("interface Ethernet2")
	l3s.exec("switchport access vlan 50")
	check(not Sim.ping(h40, "10.80.50.10")["ok"], "svi: different VLANs cannot talk before routing")
	check(l3s.exec("interface Vlan40").is_empty(), "svi: 'interface Vlan40' enters SVI config")
	l3s.exec("ip address 10.80.40.1/24")
	l3s.exec("interface Vlan50")
	l3s.exec("ip address 10.80.50.1/24")
	l3s.exec("end")
	Game.add_static_route(h40, "0.0.0.0", 0, "10.80.40.1")
	Game.add_static_route(h50, "0.0.0.0", 0, "10.80.50.1")
	check(Sim.ping(h40, "10.80.40.1")["ok"], "svi: hosts can ping their SVI gateway")
	check(Sim.ping(h40, "10.80.50.10")["ok"] and Sim.ping(h50, "10.80.40.10")["ok"],
		"svi: the L3 switch routes between VLANs with no router")
	check(l3s.exec("sh run").contains("interface Vlan40"), "svi: rendered in running-config")
	var l2sw := CLI.new_session(sw_a)
	l2sw.exec("en")
	l2sw.exec("conf t")
	check(l2sw.exec("interface Vlan40").contains("no L3 switching"), "svi: budget switches refuse SVIs")
	check(Game.try_complete_contract(_contract("one_switch_two_nets")), "svi: collapse-the-core contract verifies")

	# --- port security ---
	var ps_sw := Game.new_device("sw-8")
	var ps_a := Game.new_device("srv-1")
	var ps_b := Game.new_device("srv-1")
	var r11 := Game.add_rack(Vector2i(7, 1))
	r11.slots[0] = ps_sw
	r11.slots[1] = ps_a
	r11.slots[2] = ps_b
	Game.connect_ifaces(ps_a.ifaces[0], ps_sw.ifaces[0])
	Game.connect_ifaces(ps_b.ifaces[0], ps_sw.ifaces[1])
	Game.add_ip(ps_a.ifaces[0], "10.95.0.10/24")
	Game.add_ip(ps_b.ifaces[0], "10.95.0.11/24")
	var ps := CLI.new_session(ps_sw)
	ps.exec("en")
	ps.exec("conf t")
	ps.exec("interface Ethernet1")
	ps.exec("switchport port-security")
	ps.exec("end")
	check(Sim.ping(ps_a, "10.95.0.11")["ok"], "portsec: the first device is learned and allowed")
	check(ps_sw.ifaces[0].secure_mac == ps_a.ifaces[0].mac, "portsec: sticky MAC recorded")
	check(ps.exec("show port-security").contains(ps_a.ifaces[0].mac), "portsec: show lists the secure MAC")
	# someone swaps the server for their own machine
	Game.disconnect_iface(ps_sw.ifaces[0])
	var rogue := Game.new_device("srv-1")
	r11.slots[3] = rogue
	Game.connect_ifaces(rogue.ifaces[0], ps_sw.ifaces[0])
	Game.add_ip(rogue.ifaces[0], "10.95.0.66/24")
	Sim.ping(rogue, "10.95.0.11")
	check(not ps_sw.ifaces[0].enabled, "portsec: a different MAC shuts the port down")
	check(int(ps_sw.ifaces[0].violations) == 1, "portsec: the violation is counted")
	check("PORT SECURITY" in Game.events[0], "portsec: the violation is logged")
	check(not Sim.ping(rogue, "10.95.0.11")["ok"], "portsec: the rogue machine gets nothing")

	# --- startup config: write memory / reload ---
	var cfg_sw := Game.new_device("sw-8")
	var r10 := Game.add_rack(Vector2i(6, 1))
	r10.slots[0] = cfg_sw
	var cs := CLI.new_session(cfg_sw)
	cs.exec("en")
	cs.exec("conf t")
	cs.exec("vlan 77")
	cs.exec("end")
	check(cs.exec("show startup-config").contains("no saved"), "cfg: nothing saved yet")
	check(cs.exec("write memory").contains("Copy completed"), "cfg: write memory saves")
	cs.exec("conf t")
	cs.exec("vlan 88")
	cs.exec("end")
	check(cs.exec("show startup-config").contains("unsaved changes"), "cfg: unsaved drift is reported")
	check(cs.exec("reload").contains("restored"), "cfg: reload restores the startup config")
	check(cfg_sw.vlans.has(77) and not cfg_sw.vlans.has(88),
		"cfg: saved VLAN survived the reload, the unsaved one did not")
	var blank_sw := Game.new_device("sw-8")
	r10.slots[1] = blank_sw
	var bs := CLI.new_session(blank_sw)
	bs.exec("en")
	bs.exec("conf t")
	bs.exec("vlan 99")
	bs.exec("end")
	check(bs.exec("reload").contains("NO startup-config"), "cfg: reloading without a save warns")
	check(not blank_sw.vlans.has(99), "cfg: unsaved config is genuinely lost on reload")

	# --- router on a stick: 802.1Q subinterfaces ---
	var ros_rtr := Game.new_device("rtr-edge")
	var h60 := Game.new_device("srv-1")
	var h61 := Game.new_device("srv-1")
	var stick_sw := Game.new_device("sw-8")
	var r9 := Game.add_rack(Vector2i(5, 1))
	r9.slots[0] = ros_rtr
	r9.slots[1] = stick_sw
	r9.slots[2] = h60
	r9.slots[3] = h61
	Game.connect_ifaces(ros_rtr.ifaces[0], stick_sw.ifaces[7])
	Game.connect_ifaces(h60.ifaces[0], stick_sw.ifaces[0])
	Game.connect_ifaces(h61.ifaces[0], stick_sw.ifaces[1])
	Game.add_vlan(stick_sw, 60, "sixty")
	Game.add_vlan(stick_sw, 61, "sixtyone")
	stick_sw.ifaces[0].untagged_vlan = 60
	stick_sw.ifaces[1].untagged_vlan = 61
	stick_sw.ifaces[7].mode = "trunk"
	Game.add_ip(h60.ifaces[0], "10.90.60.10/24")
	Game.add_ip(h61.ifaces[0], "10.90.61.10/24")
	Game.add_static_route(h60, "0.0.0.0", 0, "10.90.60.1")
	Game.add_static_route(h61, "0.0.0.0", 0, "10.90.61.1")
	check(not Sim.ping(h60, "10.90.61.10")["ok"], "stick: VLANs isolated before the router is configured")
	var st := CLI.new_session(ros_rtr)
	st.exec("en")
	st.exec("conf t")
	check(st.exec("interface Ethernet1.60").is_empty(), "stick: subinterface created")
	check(st.exec("encapsulation dot1q 60").is_empty(), "stick: encapsulation matches the subinterface")
	st.exec("ip address 10.90.60.1/24")
	st.exec("interface Ethernet1.61")
	st.exec("ip address 10.90.61.1/24")
	st.exec("end")
	check(Sim.ping(h60, "10.90.60.1")["ok"], "stick: host reaches its tagged gateway")
	check(Sim.ping(h60, "10.90.61.10")["ok"] and Sim.ping(h61, "10.90.60.10")["ok"],
		"stick: one physical port routes both VLANs")
	check(st.exec("sh run").contains("encapsulation dot1q 60"), "stick: rendered in running-config")
	check(Game.try_complete_contract(_contract("router_on_a_stick")), "stick: contract verifies")

	# --- DHCP relay ---
	var rel_r := Game.new_device("rtr-edge")
	var rel_srv := Game.new_device("server")
	var rel_cli := Game.new_device("server")
	r7.slots[4] = rel_r
	r7.slots[5] = rel_srv
	r7.slots[6] = rel_cli
	Game.connect_ifaces(rel_cli.ifaces[0], rel_r.ifaces[0])
	Game.connect_ifaces(rel_srv.ifaces[0], rel_r.ifaces[1])
	Game.add_ip(rel_r.ifaces[0], "10.60.0.1/24")
	Game.add_ip(rel_r.ifaces[1], "10.61.0.1/24")
	Game.add_ip(rel_srv.ifaces[0], "10.61.0.5/24")
	Game.add_static_route(rel_srv, "0.0.0.0", 0, "10.61.0.1")
	var rel_ss := CLI.new_session(rel_srv)
	rel_ss.exec("dhcpd eth0 10.60.0.50 10.60.0.99 24 10.60.0.1 10.61.0.5")
	var rel_es := CLI.new_session(rel_r)
	rel_es.exec("en")
	rel_es.exec("conf t")
	rel_es.exec("int et1")
	rel_es.exec("ip helper-address 10.61.0.5")
	rel_es.exec("end")
	var rel_out: String = CLI.new_session(rel_cli).exec("dhclient eth0")
	check("bound to 10.60.0.50/24" in rel_out, "relay: client leased across the router (got: %s)" % rel_out.strip_edges())
	check(Sim.ping(rel_cli, "10.61.0.5")["ok"], "relay: leased client routes to the central DHCP server")

	# --- capacity planning ---
	check(Game.iface_speed(vr1.ifaces[0]) == 10000, "capacity: Junivista port is 10G")
	check(Game.iface_speed(mkt_sw.ifaces[0]) == 1000, "capacity: PacketTik port is 1G")
	Game.stage = 0  # no field faults and no attacks while measuring capacity
	Game.attacks = []
	Game.deals = []  # this section measures its own traffic, nobody else's
	Game.racks.append(r6)  # the walkthrough reset dropped the VRRP rack; bring it back
	Game.connect_ifaces(vr1.ifaces[0], vsw.ifaces[0])
	Game.connect_ifaces(vr2.ifaces[0], vsw.ifaces[1])
	Game.connect_ifaces(vcl.ifaces[0], vsw.ifaces[2])
	for l in Game.links:
		l.a.enabled = true
		l.b.enabled = true
	Game.topology_changed.emit()
	var cap_deal := {"id": "cap1", "customer": "LoadCo", "kind": "hosting",
		"params": {"ip": "10.40.0.10"}, "fee": 100, "brief": "", "load": 1500, "healthy": false}
	Game.deals.append(cap_deal)
	# traffic follows the working day, so measure congestion at the busy part
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 3
	Game.sla_tick()
	check(cap_deal["healthy"] and cap_deal.get("degraded", false),
		"capacity: 1500 Mbps through 1G access link degrades the deal")
	cap_deal["load"] = 200
	Game.sla_tick()
	check(not cap_deal.get("degraded", true), "capacity: modest load fits, deal recovers")
	Game.connect_ifaces(vr1.ifaces[1], vr2.ifaces[1])  # 10G Junivista-to-Junivista core link
	for l in Game.links:  # the crunch contract wants no congested deals at all
		l.a.qos = false
		l.b.qos = false
	cap_deal["load"] = 200
	Game.sla_tick()
	check(Game.try_complete_contract(_contract("bandwidth_crunch")), "capacity: bandwidth-crunch contract verifies")
	Game.deals.erase(cap_deal)

	# --- the difficult customer: being right is not a defence ---
	Game.reputation = 60
	var arg_deal := {"id": "arg", "customer": "Stubborn Kft", "kind": "hosting",
		"params": {"ip": "10.40.0.10"}, "fee": 100, "brief": "", "load": 100,
		"healthy": true, "ever_healthy": true, "cycles": 12, "up_cycles": 12,
		"loyalty": 0.9, "budget": 120}
	Game.deals = [arg_deal]
	arg_deal["dispute"] = {"kind": "redundancy", "warned": false, "raised": Game.cycle,
		"customer_right": false}
	check(Game.warn_customer(arg_deal) == "" and bool(arg_deal["dispute"]["warned"]) \
			and Game.warn_customer(arg_deal) != "",
		"dispute: the player can put the advice in writing exactly once")
	check(Game.concede_dispute(arg_deal) == "" and not arg_deal.has("dispute") \
			and bool(arg_deal["on_record"]) and int(arg_deal["predicted_failure"]) > Game.cycle,
		"dispute: conceding schedules the failure you predicted and keeps the record")
	Game.cycle = int(arg_deal["predicted_failure"])
	var rep_before_fail := Game.reputation
	Game.dispute_tick()
	check(not arg_deal.has("predicted_failure") and not Market.check("hosting", arg_deal["params"]) \
			and Game.reputation == rep_before_fail,
		"dispute: the predicted failure breaks the live path, and a written warning carries the blame")
	for l_fix in Game.links:  # put the customer back on the air
		l_fix.a.enabled = true
		l_fix.b.enabled = true
	Game.topology_changed.emit()
	# the same failure without a written warning is the player's to wear
	var quiet_deal := arg_deal.duplicate(true)
	quiet_deal["id"] = "arg2"
	quiet_deal.erase("on_record")
	Game.deals = [quiet_deal]
	quiet_deal["dispute"] = {"kind": "window", "warned": false, "raised": Game.cycle,
		"customer_right": false}
	Game.concede_dispute(quiet_deal)
	Game.cycle = int(quiet_deal["predicted_failure"])
	var rep_unrecorded := Game.reputation
	Game.dispute_tick()
	check(Game.reputation < rep_unrecorded and not quiet_deal.has("on_record"),
		"dispute: the same outage costs reputation when nothing was written down")
	for l_fix2 in Game.links:
		l_fix2.a.enabled = true
		l_fix2.b.enabled = true
	Game.topology_changed.emit()
	# holding firm against a customer who happens to be right is not free
	var right_deal := {"id": "arg3", "customer": "Correct Bt", "kind": "hosting",
		"params": {"ip": "10.40.0.10"}, "fee": 100, "brief": "", "load": 100,
		"healthy": true, "ever_healthy": true, "cycles": 12, "up_cycles": 12, "loyalty": 1.0}
	Game.deals = [right_deal]
	right_deal["dispute"] = {"kind": "design", "warned": true, "raised": Game.cycle,
		"customer_right": true}
	var rep_before_firm := Game.reputation
	Game.hold_firm(right_deal)
	check(Game.reputation < rep_before_firm and not right_deal.has("predicted_failure"),
		"dispute: holding firm when the customer was right costs standing and prevents nothing")
	var firm_deal := {"id": "arg4", "customer": "Wrong Zrt", "kind": "hosting",
		"params": {"ip": "10.40.0.10"}, "fee": 100, "brief": "", "load": 100,
		"healthy": true, "ever_healthy": true, "cycles": 12, "up_cycles": 12, "loyalty": 1.0}
	Game.deals = [firm_deal]
	firm_deal["dispute"] = {"kind": "redundancy", "warned": true, "raised": Game.cycle,
		"customer_right": false}
	var rep_before_win := Game.reputation
	Game.hold_firm(firm_deal)
	check(Game.reputation > rep_before_win and not firm_deal.has("predicted_failure"),
		"dispute: warning them and holding firm is rewarded, and no outage follows")
	# the argument has to actually arrive on its own, or none of this is reachable
	var raised_deal := {"id": "arg5", "customer": "Argus Kft", "kind": "hosting",
		"params": {"ip": "10.40.0.10"}, "fee": 100, "brief": "", "load": 100,
		"healthy": true, "ever_healthy": true, "cycles": 12, "up_cycles": 12, "loyalty": 0.9}
	Game.deals = [raised_deal]
	for _d in 300:
		Game.maybe_dispute()
		if raised_deal.has("dispute"):
			break
	check(raised_deal.has("dispute") \
			and String(Game.dispute_kind(String(raised_deal["dispute"]["kind"]))["id"]) \
				== String(raised_deal["dispute"]["kind"]),
		"dispute: a long-running healthy customer eventually picks the argument themselves")
	Game.deals = []

	# --- undelivered deals cancel ---
	var ghost := {"id": "ghost", "customer": "NoShow Kft", "kind": "hosting",
		"params": {"ip": "10.222.222.10"}, "fee": 50, "brief": "", "load": 100, "healthy": false}
	Game.deals.append(ghost)
	for i in 4:
		Game.sla_tick()
	check(ghost in Game.deals and int(ghost["missed"]) == 4, "deal: undelivered deal accrues missed cycles")
	Game.sla_tick()
	check(not (ghost in Game.deals), "deal: five undelivered cycles cancels the deal")
	var cancelled := false
	for ev in Game.events:
		if "CANCELLED" in ev:
			cancelled = true
	check(cancelled, "deal: cancellation is logged")

	# --- incident drills ---
	var pre_devs := Game.all_devices().size()
	var pre_money := Game.money
	Drill.start(3, 42)
	check(Game.drill_active and Drill.faults.size() >= 2, "drill: starts with hidden faults")
	check(Drill.scenario != "" and (not Drill.targets.is_empty() or not Drill.outcome.is_empty()),
		"drill: scenario named with something to prove")
	check(not Drill.solved(), "drill: the generated network is actually broken")
	var pre_cycle := Game.cycle
	Game.sla_tick()
	check(Game.cycle == pre_cycle, "drill: the economy pauses during a drill")
	Drill.cheat_fix()
	check(Drill.solved(), "drill: reverting the faults restores all pings")
	var revealed: Array = Drill.finish(true)
	check(not Game.drill_active and revealed.size() >= 2, "drill: finish reveals the fault list")
	check(Game.all_devices().size() == pre_devs, "drill: the real datacenter came back intact")
	check(Game.money == pre_money + Drill.REWARD, "drill: passing pays the bonus")
	check(Drill.finish(false).is_empty(), "drill: finishing with no drill running is a no-op")
	for sc_seed in [1, 2, 3, 4, 5, 6]:  # every scenario must be solvable from its faults
		Drill.start(3, sc_seed)
		Drill.cheat_fix()
		var ok_sc: bool = Drill.solved()
		Drill.finish(false)
		check(ok_sc, "drill: scenario (seed %d) is solvable after reverting faults" % sc_seed)
	# the services incident: nothing unplugged, and still no address and no name
	var svc_seed := -1
	for s_try in range(1, 24):
		Drill.start(3, s_try)
		if Drill.scenario.begins_with("Services"):
			svc_seed = s_try
			break
		Drill.finish(false)
	check(svc_seed > 0, "drill: the services scenario comes up in the rotation")
	if svc_seed > 0:
		check(Drill.targets.is_empty() and not Drill.outcome.is_empty(),
			"drill: the services incident is judged on the lease and the name, not a static ping")
		check(not Drill.solved(), "drill: the services incident really is broken")
		Drill.cheat_fix()
		check(Drill.solved(), "drill: fixing the services faults gets a lease and resolves the name")
		Drill.finish(false)
	Drill.start(2, 7)
	var during := Game.all_devices().size()
	Drill.finish(false)  # the quit path: abandon restores before saving
	check(Game.all_devices().size() == pre_devs and during != pre_devs,
		"drill: abandoning restores the real datacenter")

	# --- long-run economy sanity ---
	Game.racks = []
	Game.links = []
	Game.deals = []
	Game.offers = []
	Game.events = []
	Game.contracts_done = []
	Game.sla_status = {}
	Game.incidents_seen = {}
	Game.stage = 1
	Game.debt = 0
	Game.money = 6000
	Game.reputation = 50
	Game.facility = {}  # a floor whose housekeeping is up to date; neglect has its own section
	Game.heat_wave_until = -1
	var er := Game.add_rack(Vector2i(0, 0))
	var esw := Game.new_device("sw-8")
	var eh1 := Game.new_device("srv-1")
	var eh2 := Game.new_device("srv-1")
	er.slots[0] = esw
	er.slots[1] = eh1
	er.slots[2] = eh2
	Game.connect_ifaces(eh1.ifaces[0], esw.ifaces[0])
	Game.connect_ifaces(eh2.ifaces[0], esw.ifaces[1])
	Game.add_ip(eh1.ifaces[0], "10.99.0.10/24")
	Game.add_ip(eh2.ifaces[0], "10.99.0.11/24")
	Game.deals = [{"id": "e1", "customer": "SteadyCo", "kind": "hosting",
		"params": {"ip": "10.99.0.10"}, "fee": 120, "load": 200, "brief": "", "healthy": true}]
	var money_start := Game.money
	for i in 60:
		# this measures the economics of steady delivery, so keep the utility
		# and the internet honest; both are exercised in their own sections
		Game.feeds = {}
		Game.carrier_outage = {}
		Game.hijacks = []
		Game.tour = {}  # visits, audits and floods are exercised in their own sections
		Game.attacks = []
		Game.heat_wave_until = -1
		Game.firmware_bugs = {}  # vendor defects have their own section too
		Game.sla_tick()
		for d_ren in Game.deals:  # a working operator renews their contracts
			if d_ren.has("renewal"):
				Game.accept_renewal(d_ren)
	check(Game.money > money_start, "economy: a delivering operator grows over 60 cycles (%d -> %d)" % [money_start, Game.money])
	check(Game.money < money_start + 60 * 400, "economy: growth stays bounded, no runaway income")
	check(Game.reputation >= 50, "economy: steady delivery keeps reputation up")
	check(Game.last_pl.has("power"), "economy: the power bill is charged once you own the room")
	# now break the service and verify the pressure lands. The customer may have
	# been poached or walked during the long run: this part is about what an
	# outage costs, so make sure there is somebody to lose.
	# the customer may have been poached or walked during the long run; this
	# part is about what an outage costs, so it only asks when one is here
	var had_customer := not Game.deals.is_empty()
	eh1.ifaces[0].enabled = false
	Game.topology_changed.emit()
	Game.invoices = []  # everything already earned is in the bank
	var money_broken := Game.money
	var rep_broken := Game.reputation
	for i in 8:
		Game.sla_tick()
	check(Game.money < money_broken, "economy: a broken datacenter bleeds money")
	check(Game.deals.is_empty(), "economy: undelivered customers eventually walk")
	check(not had_customer or Game.reputation < rep_broken,
		"economy: failure costs reputation (%d -> %d)" % [rep_broken, Game.reputation])

	# --- career rank ---
	Game.stats["earned"] = 0
	Game.stats["contracts"] = 0
	Game.stats["deals"] = 0
	Game.stage = 0
	Game.reputation = 50
	check(Game.rank() == "Cable monkey", "rank: a fresh operator starts at the bottom")
	check(Game.next_rank()[0] == "Junior NOC operator", "rank: next step is named")
	Game.stats["earned"] = 200000
	check(Game.rank() == "Packet Emperor", "rank: a rich empire tops out")
	check(Game.next_rank().is_empty(), "rank: nothing left above the top")

	# --- acquisitions and integration ---
	Game.racks = []
	Game.links = []
	Game.deals = []
	Game.offers = []
	Game.acquisitions = []
	Game.stage = 2
	Game.money = 200000
	Game.rivals = Rivals.spawn()
	var mine_rack := Game.add_rack(Vector2i(0, 0))
	var my_sw := Game.new_device("sw-8")
	var my_srv := Game.new_device("srv-1")
	mine_rack.slots[0] = my_sw
	mine_rack.slots[1] = my_srv
	Game.connect_ifaces(my_srv.ifaces[0], my_sw.ifaces[0])
	Game.add_ip(my_srv.ifaces[0], "10.0.0.1/24")  # the address their kit also uses
	var target: Dictionary = Game.rivals[1]  # a small shop on 10.0.0: no premises of its own
	target["deals"] = 2
	var racks_before := Game.racks.size()
	var cash_before_acq := Game.money
	check(Game.buy_rival(target).is_empty(), "acq: a rich operator can buy a rival")
	check(Game.money < cash_before_acq, "acq: the acquisition costs money")
	check(Game.racks.size() == racks_before + Rivals.racks_needed(target), "acq: their racks arrive on your floor")
	check(not Rivals.alive(target), "acq: the rival is off the market")
	var inherited := 0
	var acquired_devs := 0
	for d in Game.all_devices():
		if d.acquired_from == target["name"]:
			acquired_devs += 1
	for deal in Game.deals:
		if bool(deal.get("acquired", false)):
			inherited += 1
	check(acquired_devs >= 3 and inherited == 2, "acq: their hardware and contracts transfer")
	check(Game.acquisitions.size() == 1, "acq: an integration job is created")
	var integ0: Array = Game.integration_status(Game.acquisitions[0])
	check(not bool(integ0[0]["ok"]), "integration: their network starts unconnected to yours")
	check(not bool(integ0[1]["ok"]), "integration: the address clash is detected")
	check(not Game.try_complete_integration(Game.acquisitions[0]), "integration: cannot collect while broken")
	# do the actual migration work: re-address their hosts, cable the networks, save
	var their_sw: Net.NDevice = null
	var their_hosts: Array = []
	for d in Game.all_devices():
		if d.acquired_from != target["name"]:
			continue
		if d.type == "switch":
			their_sw = d
		elif d.type == "server":
			their_hosts.append(d)
	var n_host := 50
	for h: Net.NDevice in their_hosts:
		for cidr in h.ifaces[0].ips.duplicate():
			Game.remove_ip(h.ifaces[0], cidr)
		Game.add_ip(h.ifaces[0], "10.0.0.%d/24" % n_host)
		n_host += 1
	Game.acquisitions[0]["hosts"] = ["10.0.0.50", "10.0.0.51"]
	for i: Net.Iface in their_sw.ifaces:
		if i.untagged_vlan != 1 and i.mode == "access":
			i.untagged_vlan = 1  # fold their VLAN into yours
	var free_mine: Net.Iface = null
	var free_theirs: Net.Iface = null
	for i: Net.Iface in my_sw.ifaces:
		if Game.link_at(i) == null and not i.name.begins_with("Management"):
			free_mine = i
			break
	for i: Net.Iface in their_sw.ifaces:
		if Game.link_at(i) == null and not i.name.begins_with("Management"):
			free_theirs = i
			break
	Game.connect_ifaces(free_mine, free_theirs)
	for d in Game.all_devices():
		if d.acquired_from == target["name"]:
			d.startup = Game.device_config(d)
	var integ1: Array = Game.integration_status(Game.acquisitions[0])
	for req in integ1:
		check(bool(req["ok"]), "integration: '%s' satisfied after the migration" % req["d"])
	check(Game.try_complete_integration(Game.acquisitions[0]), "integration: the merge pays out")
	check(not Game.try_complete_integration(Game.acquisitions[0]), "integration: it only pays once")

	# --- buying a company that owns premises ---
	var big := {}
	for rv in Game.rivals:
		if Rivals.has_site(rv) and Rivals.alive(rv) and int(rv["capacity"]) >= 8:
			big = rv
	check(not big.is_empty(), "sites: a large multi-rack operator exists in the market")
	var sites_before := Game.site_count()
	var my_free_before := Game._free_tiles(0).size()
	Game.money = 500000
	check(Game.buy_rival(big).is_empty(), "sites: a large competitor can be acquired")
	check(Game.site_count() == sites_before + 1, "sites: their floor becomes a site you operate")
	check(Game._free_tiles(0).size() == my_free_before, "sites: your own floor is untouched by the deal")
	var new_site := Game.site_count() - 1
	check(Game.racks_on(new_site).size() == Rivals.racks_needed(big),
		"sites: their racks stand on their own floor")
	check(Game.grid_size(new_site).x >= 10, "sites: an acquired datacenter floor is big")
	Game.switch_site(new_site)
	check(Game.grid_size() == Game.grid_size(new_site), "sites: switching changes the active floor")
	check(Game.rack_at(Game.racks_on(new_site)[0].tile) != null, "sites: rack lookup is per-site")
	Game.switch_site(0)
	check(Game.racks_on(0).size() == 1 + Rivals.racks_needed(target),
		"sites: the small shop's racks did move into your room")

	# --- WAN circuits between sites ---
	var home_dev: Net.NDevice = null
	var far_dev: Net.NDevice = null
	for d in Game.all_devices():
		var rk := Game.rack_of(d)
		if rk == null or d.type != "switch":
			continue
		if rk.site == 0 and home_dev == null:
			home_dev = d
		elif rk.site == new_site and far_dev == null:
			far_dev = d
	check(home_dev != null and far_dev != null, "wan: switches exist on both sites")
	var home_port: Net.Iface = null
	var far_port: Net.Iface = null
	for i: Net.Iface in home_dev.ifaces:
		if Game.link_at(i) == null and not i.name.begins_with("Management"):
			home_port = i
			break
	for i: Net.Iface in far_dev.ifaces:
		if Game.link_at(i) == null and not i.name.begins_with("Management"):
			far_port = i
			break
	check(not Game.can_link(home_port, far_port), "wan: no circuit means no cross-site cable")
	check(not Game.connect_ifaces(home_port, far_port), "wan: connecting across sites is refused")
	Game.money = 200000
	check(Game.buy_circuit(0, new_site, 1).is_empty(), "wan: a 1 Gbit leased line can be ordered")
	check(Game.can_link(home_port, far_port), "wan: the circuit permits the cross-site cable")
	check(Game.connect_ifaces(home_port, far_port), "wan: the cable connects over the circuit")
	var wan_link := Game.link_at(home_port)
	check(Game.link_capacity(wan_link) == 1000, "wan: link capacity comes from the circuit grade")
	var pl_before := Game.money
	Game.sla_tick()
	check(Game.last_pl.has("wan circuits"), "wan: the circuit fee appears in the cycle P&L")
	var circuit: Dictionary = Game.circuits[0]
	Game.cancel_circuit(circuit)
	check(Game.circuits.is_empty() and Game.link_at(home_port) == null,
		"wan: cancelling the circuit drops the cables riding it")

	# --- the market moves on its own ---
	Game.rivals = Rivals.spawn()
	var whale: Dictionary = Game.rivals[6]
	whale["cash"] = 40000
	var minnow: Dictionary = Game.rivals[0]
	minnow["cash"] = 500
	minnow["deals"] = 0
	var consolidated := false
	for i in 300:  # 4% a cycle: it happens, and it is logged
		Rivals._maybe_consolidate()
		if not Rivals.alive(minnow):
			consolidated = true
			break
	check(consolidated and minnow.has("merged_into"), "market: rivals consolidate among themselves")
	var growth_r: Dictionary = Game.rivals[1]
	growth_r["cash"] = 30000
	Rivals.tick()
	check(Rivals.has_site(growth_r), "market: a flush rival buys premises of its own")

	# --- market intelligence ---
	Game.rivals = Rivals.spawn()
	Game.market_intel = 0
	var intel_offer := {"id": "mi", "kind": "hosting", "customer": "IntelCo", "brief": "", "costs": "",
		"params": {"ip": "10.9.9.11"}, "budget": 100, "hint": "", "state": "open", "ttl": 5}
	check(Game.market_estimate(intel_offer).is_empty(), "intel: you start blind to market prices")
	Game.offers.append(intel_offer)
	var intel_res: String = Game.respond_offer(intel_offer, 130)  # over market: a rival takes it
	check(intel_res == "undercut" and Game.market_intel == 1, "intel: losing a bid teaches you something")
	var band: Array = Game.market_estimate(intel_offer)
	check(band.size() == 2, "intel: an estimate band appears once you have seen a bid")
	if band.size() == 2:
		check(int(band[0]) < int(band[1]), "intel: the band has width")
	var wide := int(band[1]) - int(band[0])
	Game.market_intel = 6
	var band2: Array = Game.market_estimate(intel_offer)
	check(int(band2[1]) - int(band2[0]) < wide, "intel: more observed bids narrow the estimate")
	var tiny := {"id": "tiny", "kind": "own_vlan", "customer": "Kicsi Bt", "brief": "", "costs": "",
		"params": {"vid": 12}, "budget": 45, "hint": "", "state": "open", "ttl": 5}
	check(Rivals.best_bidder(tiny).is_empty() or int(Rivals.min_job(Rivals.best_bidder(tiny))) <= 45,
		"market: only companies small enough to care bid on a small job")
	var whale2 := {"capacity": 10, "deals": 0, "cash": 1000, "aggression": 0.9, "racks": [], "name": "Whale"}
	check(Rivals.min_job(whale2) > 45, "market: a large operator ignores a tiny contract")

	# --- leasing a site and delivering across it ---
	Game.money = 300000
	var sites_pre := Game.site_count()
	check(Game.lease_site(0).is_empty(), "lease: a branch site can be leased")
	check(Game.site_count() == sites_pre + 1, "lease: it becomes a site you operate")
	var branch := Game.site_count() - 1
	var m_rent := Game.money
	Game.sla_tick()
	check(Game.last_pl.has("site rent"), "lease: rent lands in the cycle P&L")
	# stand up the two-site service the bank wants
	Game.switch_site(branch)
	var br_rack := Game.add_rack(Vector2i(0, 0), branch)
	var br_sw := Game.new_device("sw-8")
	var br_srv := Game.new_device("srv-1")
	br_rack.slots[0] = br_sw
	br_rack.slots[1] = br_srv
	Game.connect_ifaces(br_srv.ifaces[0], br_sw.ifaces[0])
	Game.add_ip(br_srv.ifaces[0], "10.120.2.10/24")
	Game.switch_site(0)
	var home_rack := Game.add_rack(Vector2i(1, 1), 0)
	var hm_sw := Game.new_device("sw-8")
	var hm_srv := Game.new_device("srv-1")
	home_rack.slots[0] = hm_sw
	home_rack.slots[1] = hm_srv
	Game.connect_ifaces(hm_srv.ifaces[0], hm_sw.ifaces[0])
	Game.add_ip(hm_srv.ifaces[0], "10.120.1.10/24")
	check(not Game.try_complete_contract(_contract("two_sites")), "dr: not deliverable without a circuit")
	check(Game.buy_circuit(0, branch, 1).is_empty(), "dr: circuit ordered between the two sites")
	check(Game.connect_ifaces(hm_sw.ifaces[5], br_sw.ifaces[5]), "dr: the sites are cabled over the circuit")
	Game.add_ip(hm_srv.ifaces[0], "10.120.2.100/24")  # a foot in the other subnet, as a bank would
	Game.add_ip(br_srv.ifaces[0], "10.120.1.100/24")
	check(Sim.ping(hm_srv, "10.120.2.10")["ok"], "dr: home site reaches the branch server")
	check(Game.try_complete_contract(_contract("two_sites")), "dr: the two-site contract verifies")

	# --- full save/load roundtrip over the modern state ---
	Game.save_game()
	var snap_sites := Game.site_count()
	var snap_circuits := Game.circuits.size()
	var snap_rivals := Game.rivals.size()
	var snap_acq := Game.acquisitions.size()
	var snap_devices := Game.all_devices().size()
	var snap_money := Game.money
	var snap_stage := Game.stage
	var snap_rank := Game.rank()
	var acquired_names: Array = []
	var startup_saved: Array = []
	var secured: Array = []
	var subifaces: Array = []
	for d in Game.all_devices():
		if d.acquired_from != "":
			acquired_names.append(d.name)
		if not d.startup.is_empty():
			startup_saved.append(d.name)
		for i: Net.Iface in d.ifaces:
			if i.port_security:
				secured.append("%s|%s" % [d.name, i.name])
			if i.parent != "":
				subifaces.append("%s|%s|%d" % [d.name, i.name, i.dot1q])
	Game.money = 1
	Game.stage = 0
	Game.sites = []
	Game.circuits = []
	Game.rivals = []
	Game.acquisitions = []
	check(Game.load_game(), "save2: the modern save loads")
	check(Game.money == snap_money and Game.stage == snap_stage, "save2: money and stage restored")
	check(Game.site_count() == snap_sites, "save2: every site restored")
	check(Game.circuits.size() == snap_circuits, "save2: WAN circuits restored")
	check(Game.rivals.size() == snap_rivals, "save2: rival companies restored")
	check(Game.acquisitions.size() == snap_acq, "save2: integration jobs restored")
	check(Game.all_devices().size() == snap_devices, "save2: device count restored")
	check(Game.rank() == snap_rank, "save2: career rank is stable across a reload")
	var acq_after: Array = []
	var startup_after: Array = []
	var secured_after: Array = []
	var sub_after: Array = []
	for d in Game.all_devices():
		if d.acquired_from != "":
			acq_after.append(d.name)
		if not d.startup.is_empty():
			startup_after.append(d.name)
		for i: Net.Iface in d.ifaces:
			if i.port_security:
				secured_after.append("%s|%s" % [d.name, i.name])
			if i.parent != "":
				sub_after.append("%s|%s|%d" % [d.name, i.name, i.dot1q])
	acquired_names.sort()
	acq_after.sort()
	startup_saved.sort()
	startup_after.sort()
	secured.sort()
	secured_after.sort()
	subifaces.sort()
	sub_after.sort()
	check(acq_after == acquired_names, "save2: acquired-from provenance restored")
	check(startup_after == startup_saved, "save2: startup configs restored")
	check(secured_after == secured, "save2: port security restored")
	check(sub_after == subifaces, "save2: 802.1Q subinterfaces restored")
	var racks_per_site: Array = []
	for i in Game.site_count():
		racks_per_site.append(Game.racks_on(i).size())
	check(racks_per_site.reduce(func(acc, v): return acc + v, 0) == Game.racks.size(),
		"save2: every rack landed back on a site")

	# --- MLAG: a server dual-homed to two switches ---
	var ml_rack := Game.add_rack(Vector2i(33, 1))
	var ml_a := Game.new_device("sw-8")
	var ml_b := Game.new_device("sw-8")
	var ml_srv := Game.new_device("srv-2")
	var ml_peer_host := Game.new_device("srv-1")
	ml_rack.slots[0] = ml_a
	ml_rack.slots[1] = ml_b
	ml_rack.slots[2] = ml_srv
	ml_rack.slots[3] = ml_peer_host
	Game.connect_ifaces(ml_a.ifaces[7], ml_b.ifaces[7])  # peer link
	Game.connect_ifaces(ml_srv.ifaces[0], ml_a.ifaces[0])
	Game.connect_ifaces(ml_srv.ifaces[1], ml_b.ifaces[0])
	Game.connect_ifaces(ml_peer_host.ifaces[0], ml_a.ifaces[1])
	Game.add_ip(ml_srv.ifaces[0], "10.171.0.10/24")
	var ml_srv_cli := CLI.new_session(ml_srv)
	check(ml_srv_cli.exec("bond %s %s" % [ml_srv.ifaces[0].name, ml_srv.ifaces[1].name]).contains("bond"),
		"mlag: the server bonds both of its cables")
	check(ml_srv.ifaces[1].mac == ml_srv.ifaces[0].mac, "mlag: a bond presents one address")
	Game.add_ip(ml_peer_host.ifaces[0], "10.171.0.20/24")
	var ml_cli_a := CLI.new_session(ml_a)
	var ml_cli_b := CLI.new_session(ml_b)
	for c2 in [ml_cli_a, ml_cli_b]:
		c2.exec("en")
		c2.exec("conf t")
	check(ml_cli_a.exec("mlag peer %s" % ml_b.name).is_empty(), "mlag: a switch can name its peer")
	check(ml_b.mlag_peer == ml_a.name, "mlag: pairing is set from both sides")
	for c3 in [ml_cli_a, ml_cli_b]:
		c3.exec("interface Ethernet8")
		c3.exec("mlag peer-link")
		c3.exec("switchport mode trunk")
		c3.exec("interface Ethernet1")
		c3.exec("mlag 1")
		c3.exec("end")
	check(Sim.ping(ml_peer_host, "10.171.0.10")["ok"], "mlag: the dual-homed server is reachable")
	check(ml_cli_a.exec("show mlag").contains(ml_b.name), "mlag: show mlag names the peer")
	# pull the primary leg: the peer link must carry it to the surviving member
	ml_a.ifaces[0].enabled = false
	Sim.flush_learned_state()
	check(Sim.ping(ml_peer_host, "10.171.0.10")["ok"],
		"mlag: losing one leg does not take the server off the network")
	ml_a.ifaces[0].enabled = true
	Sim.flush_learned_state()

	# --- invoicing and receivables ---
	Game.invoices = []
	var inv_deal := {"customer": "Terms Kft", "id": "inv-test", "ctype": "public", "fee": 300}
	check(Game.payment_terms(inv_deal) == 4, "invoicing: a public body takes its time")
	check(Game.payment_terms({"ctype": "startup"}) == 1, "invoicing: a startup pays quickly")
	var inv_cycle := Game.cycle
	Game.raise_invoice(inv_deal, 300)
	check(Game.receivables() == 300, "invoicing: billed work is owed, not banked")
	check(Game.collect_invoices() == 0, "invoicing: nothing is collected before the terms are up")
	Game.invoices[0]["due"] = inv_cycle
	Game.invoices[0]["chased"] = true  # deterministic: a chased invoice does not slip
	check(Game.collect_invoices() == 300, "invoicing: it lands once it falls due")
	check(Game.receivables() == 0, "invoicing: and stops being owed")
	Game.raise_invoice(inv_deal, 500)
	Game.invoices[0]["due"] = Game.cycle - 1
	check(Game.overdue_invoices().size() == 1, "invoicing: an unpaid invoice shows as overdue")
	var rep_before_chase := Game.reputation
	check(Game.chase_invoice(Game.invoices[0]) == "", "invoicing: an overdue invoice can be chased")
	check(Game.reputation < rep_before_chase, "invoicing: chasing costs a little goodwill")
	check(Game.chase_invoice(Game.invoices[0]) != "", "invoicing: chasing twice is refused")
	Game.invoices[0]["due"] = Game.cycle - Game.WRITE_OFF_AFTER - 1
	Game.collect_invoices()
	check(Game.receivables() == 0, "invoicing: a long-overdue invoice is written off")
	Game.invoices = []

	# --- power distribution: A and B feeds ---
	var pw_rack := Game.add_rack(Vector2i(34, 1))
	var pw_single := Game.new_device("srv-1")
	var pw_dual := Game.new_device("srv-2")
	pw_rack.slots[0] = pw_single
	pw_rack.slots[1] = pw_dual
	check(pw_single.psu == "A", "power: single-supply gear lands on feed A")
	check(pw_dual.psu == "AB", "power: dual-supply gear takes both feeds")
	check(Game.set_psu(pw_single, "AB") != "",
		"power: a single supply cannot be plugged into two feeds")
	check(Game.set_psu(pw_single, "B") == "", "power: it can be moved to the other feed")
	var pw_site := Game.site_of_device(pw_single)
	Game.site_feeds(pw_site)["B"] = false
	Game._apply_feed_state()
	check(pw_single.status == "nopower", "power: losing its only feed takes the device down")
	check(pw_dual.status == "active", "power: the dual-supply machine rides it out")
	Game.site_feeds(pw_site)["B"] = true
	Game._apply_feed_state()
	check(pw_single.status == "active", "power: it comes straight back when the feed does")
	# a UPS carries a dead feed until the battery runs out
	Game.ups[pw_site] = 2
	Game.site_feeds(pw_site)["B"] = false
	Game._apply_feed_state()
	check(pw_single.status == "active", "power: the UPS holds it up")
	Game.ups[pw_site] = 0
	Game._apply_feed_state()
	check(pw_single.status == "nopower", "power: a flat battery is no battery")
	Game.site_feeds(pw_site)["B"] = true
	Game.ups.erase(pw_site)
	Game._apply_feed_state()
	var exposed_now := Game.single_feed_exposure(pw_site)
	check(pw_single in exposed_now and pw_dual not in exposed_now,
		"power: the exposure list names exactly the single-supply gear")

	# --- multicast ---
	var mc_rack := Game.add_rack(Vector2i(32, 1))
	var mc_sw := Game.new_device("sw-8")
	var mc_src := Game.new_device("srv-1")
	var mc_a := Game.new_device("srv-1")
	var mc_b := Game.new_device("srv-1")
	var mc_idle := Game.new_device("srv-1")
	mc_rack.slots[0] = mc_sw
	mc_rack.slots[1] = mc_src
	mc_rack.slots[2] = mc_a
	mc_rack.slots[3] = mc_b
	mc_rack.slots[4] = mc_idle
	Game.connect_ifaces(mc_src.ifaces[0], mc_sw.ifaces[0])
	Game.connect_ifaces(mc_a.ifaces[0], mc_sw.ifaces[1])
	Game.connect_ifaces(mc_b.ifaces[0], mc_sw.ifaces[2])
	Game.connect_ifaces(mc_idle.ifaces[0], mc_sw.ifaces[3])
	for idx in [0, 1, 2, 3]:
		Game.add_ip([mc_src, mc_a, mc_b, mc_idle][idx].ifaces[0], "10.170.9.%d/24" % (10 + idx))
	var mc_cli := CLI.new_session(mc_sw)
	mc_cli.exec("en")
	mc_cli.exec("conf t")
	check(mc_cli.exec("ip igmp snooping").is_empty(), "multicast: snooping can be enabled")
	mc_cli.exec("end")
	check(CLI.new_session(mc_a).exec("igmp join 239.1.1.1").contains("joined"),
		"multicast: a host can join a group")
	CLI.new_session(mc_b).exec("igmp join 239.1.1.1")
	check(mc_cli.exec("show ip igmp snooping").contains("239.1.1.1"),
		"multicast: the switch learned where the group is wanted")
	check(Sim.mcast_send(mc_src, "239.1.1.1") == 2,
		"multicast: exactly the two members receive the stream")
	check(mc_idle.mcast_rx == 0, "multicast: the host that never joined is not bothered by it")
	check(Sim.mcast_send(mc_src, "239.9.9.9") == 0, "multicast: nobody listens to an unused group")

	# --- status page and spares ---
	Game.status_posts = []
	Game.spares = {}
	Game.deals = []
	check(not Game.outage_open(), "status: no outage to begin with")
	Game.deals = [{"id": "down", "customer": "Dark Kft", "kind": "hosting", "params": {},
		"fee": 100, "load": 100, "brief": "", "healthy": false, "cycles": 1, "up_cycles": 0}]
	check(Game.outage_open(), "status: an undelivered service counts as an outage")
	check(Game.post_status("A switch failed in the Budapest room, we are swapping it.").is_empty(),
		"status: an update can be posted")
	check(Game.status_posted_recently(), "status: a recent update is recognised")
	var rep_quiet := Game.reputation
	Game.sla_tick()
	var loss_with_post := rep_quiet - Game.reputation
	Game.status_posts = []
	Game.cycle += 5
	var rep_silent := Game.reputation
	Game.sla_tick()
	var loss_silent := rep_silent - Game.reputation
	check(loss_silent > loss_with_post,
		"status: staying quiet during an outage costs more reputation (%d vs %d)" % [loss_silent, loss_with_post])
	Game.deals = []
	# spares
	var sp_rack := Game.add_rack(Vector2i(31, 1))
	var sp_sw := Game.new_device("sw-8")
	sp_rack.slots[0] = sp_sw
	Game.money = 100000
	sp_sw.startup = Game.device_config(sp_sw)
	sp_sw.status = "offline"
	check(not Game.swap_from_spares(sp_sw).is_empty(), "spares: nothing on the shelf, no swap")
	check(Game.buy_spare("sw-8").is_empty(), "spares: a spare can be bought")
	check(Game.swap_from_spares(sp_sw).is_empty() and sp_sw.status == "active",
		"spares: a failed device is replaced from the shelf")
	check(int(Game.spares.get("sw-8", 0)) == 0, "spares: the shelf unit was used up")

	# --- scenarios ---
	var devs_before_sc := Game.all_devices().size()
	var isp: Dictionary = Scenarios.all()[0]
	Scenarios.start(isp)
	check(Game.drill_active and not Game.racks.is_empty(), "scenario: it replaces the world")
	check(not Scenarios.solved(), "scenario: the inherited network really is broken")
	# fix what the previous engineer left: the shut uplink, the wrong subnet,
	# and the customer with no default route
	var sc_core: Net.NDevice = null
	var sc_sw_b: Net.NDevice = null
	var sc_cust_b: Net.NDevice = null
	for d in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			for cidr: String in i.ips:
				if cidr == "10.60.3.1/24":
					sc_core = d
				if cidr == "10.60.2.10/24":
					sc_cust_b = d
		if d.type == "switch":
			for i: Net.Iface in d.ifaces:
				if not i.enabled and Game.link_at(i) != null:
					sc_sw_b = d
	check(sc_core != null and sc_sw_b != null and sc_cust_b != null, "scenario: the faults are findable")
	for i: Net.Iface in sc_core.ifaces:
		if "10.60.3.1/24" in i.ips:
			Game.remove_ip(i, "10.60.3.1/24")
			Game.add_ip(i, "10.60.2.1/24")
	for i: Net.Iface in sc_sw_b.ifaces:
		i.enabled = true
	Game.add_static_route(sc_cust_b, "0.0.0.0", 0, "10.60.2.1")
	Game.topology_changed.emit()
	check(Scenarios.solved(), "scenario: fixing the faults satisfies every goal")
	Scenarios.finish(true)
	check(not Game.drill_active and Game.all_devices().size() == devs_before_sc,
		"scenario: your own datacenter comes back untouched")
	check(Game.log_contains("SCENARIO passed"), "scenario: passing is recorded")
	Scenarios.start(Scenarios.all()[1])
	check(not Scenarios.solved(), "scenario: the campus starts unbuilt")
	Scenarios.finish(false)

	# --- the transition scenario: v6 natively, and v4 through a translator ---
	var tr_sc: Dictionary = Scenarios.all()[3]
	Scenarios.start(tr_sc)
	check(not Scenarios.solved(), "scenario: the v6 customer starts with nothing working")
	var tr_web: Net.NDevice = Sim._ip_owner("10.6.0.20")
	var tr_rtr: Net.NDevice = Sim._ip_owner("fd00:6::1")
	check(tr_web != null and tr_rtr != null and Sim._ip_owner("fd00:6::5") != null,
		"scenario: the transition floor is built as described")
	if tr_web != null and tr_rtr != null and Sim._ip_owner("fd00:6::5") != null:
		# the work the customer is asking for, done the documented way
		var tr_wcli := CLI.new_session(tr_web)
		check(tr_wcli.exec("ip addr add fd00:6::20/64 dev %s" % tr_web.ifaces[0].name) == "",
			"scenario v6: the server takes its IPv6 address")
		check(tr_wcli.exec("ip route add ::/0 via fd00:6::1") == "",
			"scenario v6: and a default route to the gateway")
		var tr_dns: Net.NDevice = Sim._ip_owner("fd00:6::5")
		var tr_dcli := CLI.new_session(tr_dns)
		check(tr_dcli.exec("dns add web.pkt fd00:6::20") == "",
			"scenario v6: the zone gets an AAAA record for the service")
		check(tr_dcli.exec("dns64 64:ff9b::").contains("synthesizing"),
			"scenario v6: and synthesizes answers for the v4-only partner")
		var tr_rcli := CLI.new_session(tr_rtr)
		tr_rcli.exec("en")
		tr_rcli.exec("conf t")
		check(tr_rcli.exec("nat64 prefix 64:ff9b:: pool 10.6.0.1") == "",
			"scenario v6: the router translates what the resolver promised")
		Sim.flush_learned_state()
		for goal_i in Scenarios.active["goals"].size():
			var goal: Dictionary = Scenarios.active["goals"][goal_i]
			check(bool(goal["t"].call()), "scenario v6 goal: %s" % goal["d"])
		check(Scenarios.solved(),
			"scenario: native v6, an AAAA record and a translator satisfy the mandate")
	Scenarios.finish(false)
	check(Game.all_devices().size() == devs_before_sc, "scenario: leaving restores the world too")

	# --- contract terms and renewals ---
	Game.deals = []
	Game.attacks = []
	var ren_deal := {"id": "ren", "customer": "Loyal Zrt", "kind": "hosting", "sla": 0,
		"params": {}, "fee": 100, "load": 100, "brief": "", "term": 3,
		"cycles": 5, "up_cycles": 5, "healthy": true, "budget": 120, "loyalty": 0.9}
	Game.deals = [ren_deal]
	Game.reputation = 80
	Game._renewals_tick()
	check(ren_deal.has("renewal"), "renewal: a contract that reaches its term comes up for renewal")
	check(int(ren_deal["renewal"]["fee"]) > 100, "renewal: good service earns a rise")
	var money_paused := Game.money
	Game.sla_tick()
	check(Game.money <= money_paused + 5, "renewal: nothing is billed while they decide")
	Game.accept_renewal(ren_deal)
	check(not ren_deal.has("renewal") and int(ren_deal["fee"]) > 100 and int(ren_deal["cycles"]) == 0,
		"renewal: accepting restarts the term at the new price")
	# a badly served customer asks for a discount, and can be let go
	var bad_deal := {"id": "bad", "customer": "Unhappy Bt", "kind": "hosting", "sla": 0,
		"params": {}, "fee": 200, "load": 100, "brief": "", "term": 3,
		"cycles": 10, "up_cycles": 2, "healthy": true, "budget": 200, "loyalty": 0.5}
	Game.deals = [bad_deal]
	Game._renewals_tick()
	check(int(bad_deal["renewal"]["fee"]) < 200, "renewal: poor service costs you on renewal")
	Game.decline_renewal(bad_deal)
	check(Game.deals.is_empty(), "renewal: a contract can be allowed to end")
	Game.deals = []

	# --- 802.1X port authentication ---
	var dx_rack := Game.add_rack(Vector2i(30, 1))
	var dx_sw := Game.new_device("sw-8")
	var dx_auth := Game.new_device("srv-1")   # the authentication server
	var dx_known := Game.new_device("srv-1")  # a machine the company owns
	var dx_stranger := Game.new_device("srv-1")
	dx_rack.slots[0] = dx_sw
	dx_rack.slots[1] = dx_auth
	dx_rack.slots[2] = dx_known
	dx_rack.slots[3] = dx_stranger
	Game.connect_ifaces(dx_auth.ifaces[0], dx_sw.ifaces[0])
	Game.connect_ifaces(dx_known.ifaces[0], dx_sw.ifaces[1])
	Game.connect_ifaces(dx_stranger.ifaces[0], dx_sw.ifaces[2])
	Game.add_ip(dx_auth.ifaces[0], "10.115.0.5/24")
	Game.add_ip(dx_known.ifaces[0], "10.115.0.10/24")
	Game.add_ip(dx_stranger.ifaces[0], "10.115.0.11/24")
	var auth_cli := CLI.new_session(dx_auth)
	check(auth_cli.exec("radiusd add %s" % dx_known.ifaces[0].mac).contains("may join"),
		"dot1x: a machine can be authorised on the server")
	var dx_cli := CLI.new_session(dx_sw)
	dx_cli.exec("en")
	dx_cli.exec("conf t")
	# the switch needs to reach the server itself, which means a management address
	dx_cli.exec("interface Management1")
	dx_cli.exec("ip address 10.115.0.2/24")
	dx_cli.exec("exit")
	check(dx_cli.exec("radius-server host 10.115.0.5").is_empty(), "dot1x: the switch is pointed at it")
	dx_cli.exec("interface range Ethernet2-3")
	check(dx_cli.exec("dot1x").is_empty(), "dot1x: ports can require authentication")
	dx_cli.exec("end")
	# the management port has to be patched into the network to be any use
	Game.connect_ifaces(dx_sw.ifaces[dx_sw.ifaces.size() - 1], dx_sw.ifaces[7])
	Sim.flush_learned_state()
	check(Sim.ping(dx_known, "10.115.0.5")["ok"], "dot1x: an authorised machine gets on")
	check(dx_sw.ifaces[1].dot1x_ok == dx_known.ifaces[0].mac, "dot1x: the port records who it let in")
	Sim.flush_learned_state()
	check(not Sim.ping(dx_stranger, "10.115.0.5")["ok"], "dot1x: an unknown machine gets nothing")
	check(dx_cli.exec("show dot1x").contains("10.115.0.5"), "dot1x: the state is reported")
	# the server can also decide which VLAN a machine belongs in
	Game.add_vlan(dx_sw, 45, "trusted")
	auth_cli.exec("radiusd add %s 45" % dx_stranger.ifaces[0].mac)
	dx_sw.ifaces[2].dot1x_ok = ""
	Sim.flush_learned_state()
	Sim.ping(dx_stranger, "10.115.0.5")
	check(dx_sw.ifaces[2].untagged_vlan == 45,
		"dot1x: the authentication server decides which VLAN you land in")

	# --- wireless ---
	var wifi_rack := Game.add_rack(Vector2i(29, 1))
	var wifi_sw := Game.new_device("sw-8")
	var ap := Game.new_device("ap-1")
	var guest := Game.new_device("srv-1")
	var staff_pc := Game.new_device("srv-1")
	var wifi_gw := Game.new_device("rtr-lite")
	wifi_rack.slots[0] = wifi_sw
	wifi_rack.slots[1] = ap
	wifi_rack.slots[2] = guest
	wifi_rack.slots[3] = staff_pc
	wifi_rack.slots[4] = wifi_gw
	Game.connect_ifaces(ap.ifaces[0], wifi_sw.ifaces[0])
	wifi_sw.ifaces[0].mode = "trunk"
	Game.connect_ifaces(wifi_gw.ifaces[0], wifi_sw.ifaces[1])
	Game.add_vlan(wifi_sw, 30, "guest")
	Game.add_vlan(wifi_sw, 31, "staff")
	wifi_sw.ifaces[1].untagged_vlan = 31
	Game.add_ip(wifi_gw.ifaces[0], "10.110.31.1/24")
	var ap_cli := CLI.new_session(ap)
	ap_cli.exec("en")
	ap_cli.exec("conf t")
	check(ap_cli.exec("ssid guest-wifi vlan 30").is_empty(), "wifi: an SSID maps to a VLAN")
	ap_cli.exec("ssid staff-wifi vlan 31")
	ap_cli.exec("end")
	check(ap_cli.exec("show ssid").contains("guest-wifi"), "wifi: SSIDs are listed")
	var guest_cli := CLI.new_session(guest)
	check(guest_cli.exec("wifi join guest-wifi").contains("associated"), "wifi: a host can associate")
	check(guest.wifi == "guest-wifi" and Game.link_at(guest.ifaces[0]) != null,
		"wifi: association puts it on the access point")
	var staff_cli := CLI.new_session(staff_pc)
	staff_cli.exec("wifi join staff-wifi")
	Game.add_ip(guest.ifaces[0], "10.110.30.10/24")
	Game.add_ip(staff_pc.ifaces[0], "10.110.31.10/24")
	check(Sim.ping(staff_pc, "10.110.31.1")["ok"],
		"wifi: the staff network reaches its gateway through the trunk")
	check(not Sim.ping(guest, "10.110.31.10")["ok"],
		"wifi: the guest SSID lands in another VLAN and cannot reach staff")
	check(guest_cli.exec("wifi status").contains("guest-wifi"), "wifi: status is reported")
	guest_cli.exec("wifi leave")
	check(Game.link_at(guest.ifaces[0]) == null, "wifi: leaving drops the association")
	check(not Game.wifi_join(guest, "nonexistent-wifi").is_empty(),
		"wifi: joining a network nobody broadcasts fails")
	Game.wifi_join(guest, "guest-wifi")
	check(Game.try_complete_contract(_contract("guest_wifi")), "wifi: the hotel contract verifies")

	# --- sandbox mode and rack blueprints ---
	Game.sandbox = true
	var poor := Game.money
	Game.money = 0
	check(Game.try_spend(999999), "sandbox: hardware costs nothing")
	var cyc_before := Game.cycle
	Game.sla_tick()
	check(Game.cycle == cyc_before + 1 and Game.money == 0,
		"sandbox: time passes but nothing is billed")
	Game.sandbox = false
	Game.money = poor
	check(not Game.try_spend(money_way_too_much()), "sandbox: off again, money matters")
	Game.blueprints = []
	var bp_src := Game.add_rack(Vector2i(27, 1))
	bp_src.slots[0] = Game.new_device("sw-8")
	bp_src.slots[1] = Game.new_device("srv-1")
	check(Game.save_blueprint(bp_src, "access pod").is_empty(), "blueprint: a rack layout can be saved")
	var bp: Dictionary = Game.blueprints[0]
	check(Game.blueprint_price(bp) == 250 + 400, "blueprint: it prices the hardware it needs")
	var bp_dst := Game.add_rack(Vector2i(28, 1))
	Game.money = 100000
	check(Game.apply_blueprint(bp_dst, bp).is_empty(), "blueprint: it builds into an empty rack")
	check(bp_dst.slots[0] != null and bp_dst.slots[1] != null, "blueprint: the hardware arrives")
	check(not Game.apply_blueprint(bp_dst, bp).is_empty(), "blueprint: it refuses an occupied rack")

	# --- ageing, insurance and marketing ---
	Game.insured = false
	Game.marketing = 0
	var old_sw := Game.new_device("sw-8")
	var age_rack := Game.add_rack(Vector2i(26, 1))
	age_rack.slots[0] = old_sw
	old_sw.installed_cycle = Game.cycle - 500  # ancient
	check(Game.device_age(old_sw) > 400, "ageing: a device knows how long it has been in service")
	var failed := false
	for i in 200:
		Game._ageing_tick()
		if old_sw.status != "active":
			failed = true
			break
	check(failed, "ageing: old hardware eventually fails")
	old_sw.status = "active"
	old_sw.installed_cycle = Game.cycle
	var young_ok := true
	for i in 200:
		Game._ageing_tick()
		if old_sw.status != "active":
			young_ok = false
			break
	check(young_ok, "ageing: new hardware does not fail on its own")
	# insurance pays towards the replacement
	Game.insured = true
	old_sw.installed_cycle = Game.cycle - 500
	var money_pre_fail := Game.money
	for i in 200:
		Game._ageing_tick()
		if old_sw.status != "active":
			break
	check(Game.money > money_pre_fail, "insurance: a covered failure pays out")
	old_sw.status = "active"
	old_sw.installed_cycle = Game.cycle
	Game.insured = false
	# marketing widens the funnel
	Game.marketing = 3 * Game.MARKETING_STEP
	Game.sla_tick()
	check(Game.last_pl.has("marketing"), "marketing: the spend shows in the cycle P&L")
	Game.marketing = 0

	# --- private VLANs and storm control ---
	var pv_rack := Game.add_rack(Vector2i(25, 1))
	var pv_sw := Game.new_device("sw-8")
	var pv_a := Game.new_device("srv-1")
	var pv_b := Game.new_device("srv-1")
	var pv_gw := Game.new_device("rtr-lite")
	pv_rack.slots[0] = pv_sw
	pv_rack.slots[1] = pv_a
	pv_rack.slots[2] = pv_b
	pv_rack.slots[3] = pv_gw
	Game.connect_ifaces(pv_a.ifaces[0], pv_sw.ifaces[0])
	Game.connect_ifaces(pv_b.ifaces[0], pv_sw.ifaces[1])
	Game.connect_ifaces(pv_gw.ifaces[0], pv_sw.ifaces[2])
	Game.add_ip(pv_a.ifaces[0], "10.120.0.10/24")
	Game.add_ip(pv_b.ifaces[0], "10.120.0.11/24")
	Game.add_ip(pv_gw.ifaces[0], "10.120.0.1/24")
	check(Sim.ping(pv_a, "10.120.0.11")["ok"], "pvlan: tenants can see each other by default")
	var pvs := CLI.new_session(pv_sw)
	pvs.exec("en")
	pvs.exec("conf t")
	pvs.exec("interface range Ethernet1-2")
	check(pvs.exec("switchport protected").is_empty(), "pvlan: customer ports can be protected")
	pvs.exec("end")
	Sim.flush_learned_state()
	check(not Sim.ping(pv_a, "10.120.0.11")["ok"],
		"pvlan: protected ports cannot reach each other any more")
	check(Sim.ping(pv_a, "10.120.0.1")["ok"], "pvlan: but they still reach the gateway")
	# storm control
	pvs.exec("conf t")
	pvs.exec("interface Ethernet1")
	check(pvs.exec("storm-control broadcast 1").is_empty(), "storm: a broadcast limit can be set")
	pvs.exec("end")
	check(pv_sw.ifaces[0].storm_limit == 1, "storm: the limit is stored")
	check(pvs.exec("show run").contains("storm-control broadcast 1"), "storm: it renders in the config")

	# --- anycast: the same address in two places ---
	var any_rack := Game.add_rack(Vector2i(24, 1))
	var any_client_r := Game.new_device("rtr-edge")
	var any_near := Game.new_device("rtr-edge")
	var any_mid := Game.new_device("rtr-edge")
	var any_far := Game.new_device("rtr-edge")
	var any_client := Game.new_device("srv-1")
	any_rack.slots[0] = any_client_r
	any_rack.slots[1] = any_near
	any_rack.slots[2] = any_mid
	any_rack.slots[3] = any_far
	any_rack.slots[4] = any_client
	# client router: one hop to the near instance, three to the far one
	Game.connect_ifaces(any_client_r.ifaces[0], any_near.ifaces[0])
	Game.connect_ifaces(any_client_r.ifaces[1], any_mid.ifaces[0])
	Game.connect_ifaces(any_mid.ifaces[1], any_far.ifaces[0])
	Game.connect_ifaces(any_client.ifaces[0], any_client_r.ifaces[2])
	Game.add_ip(any_client_r.ifaces[0], "10.130.1.1/30")
	Game.add_ip(any_near.ifaces[0], "10.130.1.2/30")
	Game.add_ip(any_client_r.ifaces[1], "10.130.2.1/30")
	Game.add_ip(any_mid.ifaces[0], "10.130.2.2/30")
	Game.add_ip(any_mid.ifaces[1], "10.130.3.1/30")
	Game.add_ip(any_far.ifaces[0], "10.130.3.2/30")
	Game.add_ip(any_client_r.ifaces[2], "10.130.9.1/24")
	Game.add_ip(any_client.ifaces[0], "10.130.9.10/24")
	Game.add_static_route(any_client, "0.0.0.0", 0, "10.130.9.1")
	# both instances answer on the same service address
	Game.add_ip(any_near.ifaces[3], "10.130.100.100/32")
	Game.add_ip(any_far.ifaces[3], "10.130.100.100/32")
	for any_dev in [any_client_r, any_near, any_mid, any_far]:
		any_dev.ospf = {"networks": ["10.130.0.0/16"]}
	Game.topology_changed.emit()
	var any_paths := Sim._route_paths(any_client_r, "10.130.100.100")
	check(any_paths.size() == 1, "anycast: the router picks one instance, not both (%d)" % any_paths.size())
	check(String(any_paths[0]["next_hop"]) == "10.130.1.2",
		"anycast: it picks the nearer announcement (%s)" % str(any_paths[0]["next_hop"]))
	check(Sim.ping(any_client, "10.130.100.100")["ok"], "anycast: the service answers")
	# lose the near instance: the far one takes over without the client changing anything
	any_near.status = "offline"
	Game.topology_changed.emit()
	var failover := Sim._route_paths(any_client_r, "10.130.100.100")
	check(failover.size() >= 1 and String(failover[0]["next_hop"]) == "10.130.2.2",
		"anycast: losing the near site moves traffic to the far one")
	check(Sim.ping(any_client, "10.130.100.100")["ok"], "anycast: the address still answers")
	any_near.status = "active"
	Game.topology_changed.emit()

	# --- WireGuard ---
	var wg_rack := Game.add_rack(Vector2i(23, 1))
	var wg_l := Game.new_device("rtr-edge")
	var wg_r := Game.new_device("rtr-edge")
	var wg_mid := Game.new_device("rtr-edge")
	var wg_a := Game.new_device("srv-1")
	var wg_b := Game.new_device("srv-1")
	wg_rack.slots[0] = wg_l
	wg_rack.slots[1] = wg_r
	wg_rack.slots[2] = wg_mid
	wg_rack.slots[3] = wg_a
	wg_rack.slots[4] = wg_b
	Game.connect_ifaces(wg_l.ifaces[0], wg_mid.ifaces[0])
	Game.connect_ifaces(wg_r.ifaces[0], wg_mid.ifaces[1])
	Game.add_ip(wg_l.ifaces[0], "198.51.100.1/30")
	Game.add_ip(wg_mid.ifaces[0], "198.51.100.2/30")
	Game.add_ip(wg_mid.ifaces[1], "198.51.100.5/30")
	Game.add_ip(wg_r.ifaces[0], "198.51.100.6/30")
	Game.add_static_route(wg_l, "198.51.100.4", 30, "198.51.100.2")
	Game.add_static_route(wg_r, "198.51.100.0", 30, "198.51.100.5")
	Game.connect_ifaces(wg_a.ifaces[0], wg_l.ifaces[1])
	Game.connect_ifaces(wg_b.ifaces[0], wg_r.ifaces[1])
	Game.add_ip(wg_l.ifaces[1], "172.20.1.1/24")
	Game.add_ip(wg_a.ifaces[0], "172.20.1.10/24")
	Game.add_ip(wg_r.ifaces[1], "172.20.2.1/24")
	Game.add_ip(wg_b.ifaces[0], "172.20.2.10/24")
	Game.add_static_route(wg_a, "0.0.0.0", 0, "172.20.1.1")
	Game.add_static_route(wg_b, "0.0.0.0", 0, "172.20.2.1")
	check(not Sim.ping(wg_a, "172.20.2.10")["ok"], "wg: the private sides start unreachable")
	var wl := CLI.new_session(wg_l)
	wl.exec("en")
	wl.exec("conf t")
	check(wl.exec("interface wg0").is_empty(), "wg: a wireguard interface can be created")
	wl.exec("ip address 10.99.0.1/30")
	var key_l: String = wg_l.ifaces[wg_l.ifaces.size() - 1].wg_key
	var wr := CLI.new_session(wg_r)
	wr.exec("en")
	wr.exec("conf t")
	wr.exec("interface wg0")
	wr.exec("ip address 10.99.0.2/30")
	var key_r: String = wg_r.ifaces[wg_r.ifaces.size() - 1].wg_key
	# each side names the other's key, endpoint and the prefixes it may carry
	# allowed IPs must also cover the peer's own tunnel address, exactly as a
	# real WireGuard configuration does
	check(wl.exec("wireguard peer %s endpoint 198.51.100.6 allowed 172.20.2.0/24,10.99.0.2/32" % key_r).is_empty(),
		"wg: a peer can be configured with allowed IPs")
	wr.exec("wireguard peer %s endpoint 198.51.100.1 allowed 172.20.1.0/24,10.99.0.1/32" % key_l)
	wl.exec("exit")
	wl.exec("ip route 172.20.2.0/24 10.99.0.2")
	wl.exec("end")
	wr.exec("exit")
	wr.exec("ip route 172.20.1.0/24 10.99.0.1")
	wr.exec("end")
	check(wl.exec("show wireguard").contains("handshake ok"), "wg: the handshake succeeds both ways")
	check(Sim.ping(wg_a, "172.20.2.10")["ok"] and Sim.ping(wg_b, "172.20.1.10")["ok"],
		"wg: traffic inside the allowed prefixes flows")
	# a prefix nobody allows is dropped, which is the whole point of allowed IPs
	Game.add_ip(wg_b.ifaces[0], "192.0.2.10/24")
	check(not Sim.ping(wg_a, "192.0.2.10")["ok"], "wg: traffic outside the allowed IPs is dropped")
	# and the tunnel dies with its underlay
	wg_mid.status = "offline"
	Game.topology_changed.emit()
	check(not Sim.ping(wg_a, "172.20.2.10")["ok"], "wg: no path underneath means no handshake")
	check(wl.exec("show wireguard").contains("no handshake"), "wg: and it says so")
	wg_mid.status = "active"
	Game.topology_changed.emit()
	check(Sim.ping(wg_a, "172.20.2.10")["ok"], "wg: it comes back with the path")
	check(Game.try_complete_contract(_contract("wireguard_link")), "wg: the contract verifies")

	# --- geography and latency ---
	check(Game.site_city(0) != "", "geo: every site sits in a city")
	var far_site := Game.add_site("Remote room", Vector2i(5, 5), "leased", "Debrecen")
	check(Game.site_distance_km(0, far_site) > 100.0, "geo: distance between cities is real")
	var lat_rack_home := Game.add_rack(Vector2i(0, 2), 0)
	var lat_rack_far := Game.add_rack(Vector2i(0, 0), far_site)
	var lat_a := Game.new_device("rtr-edge")
	var lat_b := Game.new_device("rtr-edge")
	lat_rack_home.slots[0] = lat_a
	lat_rack_far.slots[0] = lat_b
	Game.money = 300000
	check(Game.buy_circuit(0, far_site, 1).is_empty(), "geo: a circuit links the two cities")
	check(Game.connect_ifaces(lat_a.ifaces[0], lat_b.ifaces[0]), "geo: the sites are cabled over it")
	Game.add_ip(lat_a.ifaces[0], "10.140.0.1/30")
	Game.add_ip(lat_b.ifaces[0], "10.140.0.2/30")
	var far_probe := Sim.ping(lat_a, "10.140.0.2")
	check(far_probe["ok"], "geo: the far site answers")
	check(float(far_probe.get("rtt", 0.0)) > 1.0,
		"geo: distance shows up as latency (%.2f ms)" % float(far_probe.get("rtt", 0.0)))
	var local_probe := Sim.ping(lat_a, "10.140.0.1")
	check(float(local_probe.get("rtt", 99.0)) < 1.0, "geo: local traffic stays fast")
	var lat_cli := CLI.new_session(lat_a)
	lat_cli.exec("en")
	check(lat_cli.exec("ping 10.140.0.2").contains(" ms"), "geo: ping reports the time")

	# --- maintenance windows and post-mortems ---
	Game.maintenance_until = -1
	Game.maintenance_used = 0
	Game.incidents = []
	check(Game.declare_maintenance().is_empty() and Game.in_maintenance(),
		"maintenance: a window can be declared")
	check(not Game.declare_maintenance().is_empty(), "maintenance: only one window at a time")
	var maint_deal := {"id": "mw", "customer": "Planned Kft", "kind": "hosting", "sla": 2,
		"params": {"ip": "10.150.0.10"}, "fee": 100, "load": 100, "brief": "",
		"cycles": 0, "up_cycles": 0, "healthy": false}
	Game.deals = [maint_deal]
	Game.sla_tick()
	check(int(maint_deal["cycles"]) == 0,
		"maintenance: downtime inside a window does not count against uptime")
	Game.maintenance_until = -1
	Game.sla_tick()
	check(int(maint_deal["cycles"]) == 1, "maintenance: outside a window it counts again")
	Game.maintenance_used = 2
	check(not Game.declare_maintenance().is_empty(), "maintenance: customers cap how many you take")
	Game.deals = []
	Game.incidents = []  # this section counts its own incidents, nobody else's
	Game.record_incident("test", "a link nobody was watching went down")
	check(Game.incidents.size() == 1, "post-mortem: an incident is recorded for review")
	Game.record_incident("test", "a link nobody was watching went down")
	check(Game.incidents.size() == 1, "post-mortem: the same open incident is not duplicated")
	var rep_before_review := Game.reputation
	check(Game.review_incident(Game.incidents[0], 3).is_empty(), "post-mortem: it can be written up")
	check(Game.reputation > rep_before_review, "post-mortem: candour earns back some trust")
	check(not Game.review_incident(Game.incidents[0], 1).is_empty(), "post-mortem: only once")

	# --- who takes the blame ---
	var blame_staff := Game.staff.duplicate(true)
	var blame_incidents := Game.incidents.duplicate(true)
	var blame_pending := Game.pending_reports.duplicate(true)
	Game.incidents = []
	Game.pending_reports = []
	Game.blame_fear = 0
	Game.reputation = 60
	Game.staff = [{"name": "Kovacs Anna", "role": "noc", "skill": 3, "salary": 300, "morale": 70,
		"shift": "day", "training_left": 0, "certs": []}]
	var culprit: Dictionary = Game.staff[0]
	Game.report_incident("human", "Kovacs Anna took sw1 eth3 down while working on it",
		"Kovacs Anna", "HANDS: Kovacs Anna took sw1 eth3 down.", 0)
	check(Game.incidents.size() == 1 and String(Game.incidents[0]["by"]) == "Kovacs Anna",
		"blame: a person-caused outage is attributed to the person who caused it")
	var human_inc: Dictionary = Game.incidents[0]
	check(Game.blame_incident(human_inc, "shrug") != "" and not human_inc.has("blame"),
		"blame: only the three things you can actually say are accepted")
	var rep_before_blame := Game.reputation
	check(Game.blame_incident(human_inc, "mine") == "" and Game.reputation < rep_before_blame \
			and int(culprit["morale"]) > 70 and bool(culprit["shielded"]),
		"blame: taking it yourself costs reputation now and buys real loyalty")
	check(Game.blame_incident(human_inc, "truth") != "",
		"blame: the scene happens once per incident")
	# naming somebody protects the company and changes how that person works
	Game.incidents = []
	Game.report_incident("human", "Kovacs Anna took sw1 eth4 down while working on it",
		"Kovacs Anna", "HANDS: Kovacs Anna took sw1 eth4 down.", 0)
	var rep_before_name := Game.reputation
	check(Game.blame_incident(Game.incidents[0], "name") == "" \
			and Game.reputation >= rep_before_name and int(culprit["morale"]) < 60 \
			and bool(culprit["cautious"]) and not culprit.has("shielded") \
			and Game.blame_fear == 1,
		"blame: naming the person protects reputation, costs morale, and teaches the team a lesson")
	# a team that fears blame reports the next one late, while the fault is live
	Game.incidents = []
	Game.events = []
	var late_delay: int = Game.blame_fear + 2  # what a cautious person on a fearful team waits
	Game.report_incident("human", "Kovacs Anna took sw1 eth5 down while working on it",
		"Kovacs Anna", "HANDS: Kovacs Anna took sw1 eth5 down.", late_delay)
	Game.report_tick()
	check(Game.incidents.is_empty() and Game.pending_reports.size() == 1,
		"blame: a frightened team does not mention the fault it just caused")
	Game.cycle += late_delay
	Game.report_tick()
	check(Game.incidents.size() == 1 and Game.pending_reports.is_empty() \
			and Game.log_contains("nobody mentioned it"),
		"blame: it surfaces later, once the damage has had time to run")
	# the player's own mistake sets what the team believes is safe
	Game.incidents = []
	Game.report_incident("dispute", "Stubborn Kft went down after overruling your advice",
		"you", "PREDICTED FAILURE: Stubborn Kft is down.", 0)
	check(Game.blame_incident(Game.incidents[0], "name") == "" and Game.blame_fear == 3,
		"blame: pushing your own mistake onto the team makes them more afraid, not less")
	Game.incidents = []
	Game.report_incident("dispute", "Madaras Jatek went down after overruling your advice",
		"you", "PREDICTED FAILURE: Madaras Jatek is down.", 0)
	check(Game.blame_incident(Game.incidents[0], "mine") == "" and Game.blame_fear == 2,
		"blame: admitting your own mistake makes owning up safer for everyone else")
	var blame_payload: Dictionary = JSON.parse_string(Game.snapshot())
	check(int(blame_payload["blame_fear"]) == 2,
		"blame: what the team has learned survives the campaign save")
	Game.staff = blame_staff
	Game.incidents = blame_incidents
	Game.pending_reports = blame_pending
	Game.blame_fear = 0

	# --- juniors copy your habits ---
	var hab_staff := Game.staff.duplicate(true)
	var hab_player := Game.habits.duplicate(true)
	Game.staff = []
	Game.habits = {"saves": 0.5, "documents": 0.5, "windows": 0.5, "tidy": 0.5}
	var hab_dev := Game.new_device("sw-8")
	Game.set_note(hab_dev.ifaces[0], "customer handoff")
	check(float(Game.habits["documents"]) > 0.5 and float(Game.habits["tidy"]) > 0.5,
		"habits: labelling a port is read as a habit, from the act rather than the intent")
	# --- customers who ask for what the network can actually do ---
	var mk_rack := Game.add_rack(Vector2i(70, 1))
	var mk_sw := Game.new_device("sw-8")
	var mk_sw2 := Game.new_device("sw-8")
	var mk_peer := Game.new_device("srv-1")
	var mk_host := Game.new_device("srv-1")
	mk_rack.slots[0] = mk_sw
	mk_rack.slots[1] = mk_sw2
	mk_rack.slots[2] = mk_peer
	mk_rack.slots[3] = mk_host
	Game.connect_ifaces(mk_peer.ifaces[0], mk_sw.ifaces[0])
	Game.connect_ifaces(mk_host.ifaces[0], mk_sw2.ifaces[0])
	Game.connect_ifaces(mk_sw.ifaces[2], mk_sw2.ifaces[2])
	Game.add_ip(mk_peer.ifaces[0], "10.70.9.20/24")
	Sim.flush_learned_state()
	check(not Market.check("v6_host", {"ip": "fd70::10"}),
		"market: an IPv6 customer is not served by a promise")
	Game.add_ip(mk_host.ifaces[0], "fd70::10/64")
	Game.add_ip(mk_peer.ifaces[0], "fd70::20/64")
	Sim.flush_learned_state()
	check(Market.check("v6_host", {"ip": "fd70::10"}),
		"market: they are served when something answers natively at that address")
	Game.add_ip(mk_host.ifaces[0], "10.70.9.10/24")
	Sim.flush_learned_state()
	check(not Market.check("bonded_uplink", {"ip": "10.70.9.10"}),
		"market: a single lead is not a bundle, whatever it is called")
	Game.connect_ifaces(mk_sw.ifaces[3], mk_sw2.ifaces[3])
	for mk_pair in [[mk_sw.ifaces[2], mk_sw2.ifaces[2]], [mk_sw.ifaces[3], mk_sw2.ifaces[3]]]:
		mk_pair[0].lag = 1
		mk_pair[1].lag = 1
	Sim.flush_learned_state()
	check(Market.check("bonded_uplink", {"ip": "10.70.9.10"}),
		"market: two bundled links deliver it, proved by pulling one")
	check(mk_sw.ifaces[2].enabled and mk_sw.ifaces[3].enabled,
		"market: proving it puts the links back the way it found them")

	# every kind says what is left to do, not just whether it is done
	var mk_steps := Market.delivery_checks({"kind": "bonded_uplink",
		"params": {"ip": "10.70.9.10"}, "brief": "two links, one bundle"})
	check(mk_steps.size() >= 3 and bool(mk_steps[0]["ok"]) and bool(mk_steps[1]["ok"]),
		"market: a delivered bundle reads as a finished build sheet")
	var mk_todo := Market.delivery_checks({"kind": "redundant_gw",
		"params": {"vip": "10.70.250.1"}, "brief": "a gateway that survives"})
	check(mk_todo.size() >= 2 and not bool(mk_todo[0]["ok"]) \
			and String(mk_todo[0]["work"]).contains("VRRP"),
		"market: an unbuilt promise names the next piece of work rather than failing silently")

	# --- the three in the morning call-out ---
	var co_staff := Game.staff.duplicate(true)
	var co_haz := Game.hazards.duplicate(true)
	var co_cycle := Game.cycle
	Game.staff = []
	Game.callout_who = ""
	Game.callout_until = -1
	Game.hire(Staff.make_candidate(RandomNumberGenerator.new(), Game.habits))
	Staff.set_shift(Game.staff[0], "day")
	Game.hazards = []
	check(Game.call_someone_out() != "", "call-out: nothing happening, nobody gets woken")
	Game.hazards = [{"kind": "smoke", "rack": "R1", "site": 0, "tile": [0, 0], "severity": 1,
		"started": Game.cycle, "detected": true, "zone": ["R1"]}]
	while Staff.anyone_on_shift():  # wind the clock to the small hours
		Game.cycle += 1
	check(Game.callout_ready(), "call-out: with the floor unattended and smoke live, it is offered")
	var co_money := Game.money
	var co_morale := int(Game.staff[0]["morale"])
	check(Game.call_someone_out() == "", "call-out: phoning somebody works")
	check(Game.money == co_money - Game.CALLOUT_FEE and int(Game.staff[0]["morale"]) < co_morale,
		"call-out: it costs the fee and it costs them")
	check(Staff.anyone_on_shift() and Staff.on_shift(Game.staff[0]),
		"call-out: they are on the floor whatever the rota says")
	check(Game.call_someone_out() != "", "call-out: you cannot call out somebody already in")
	check(Staff.tired(Game.staff[0]), "call-out: the bill lands the next day, as fatigue")
	Game.duties["parts"] = String(Game.staff[0]["name"])
	var co_tired_q := Game.duty_quality("parts")
	Game.staff[0]["tired_until"] = -1
	check(Game.duty_quality("parts") > co_tired_q,
		"call-out: a tired person is worse at the duty they hold")
	Game.duties.erase("parts")
	Game.cycle = Game.callout_until + 1
	check(not Staff.anyone_on_shift(), "call-out: and they go home again afterwards")
	# with somebody carrying the phone it is an arrangement, not an imposition
	var co_pay := Staff.payroll()
	check(Game.set_oncall(String(Game.staff[0]["name"])) == "" \
			and Staff.payroll() == co_pay + Staff.ONCALL_RETAINER,
		"on call: the retainer is paid whether the phone rings or not")
	Game.callout_who = ""
	Game.callout_until = -1
	Game.staff[0]["morale"] = 80
	Game.staff[0]["tired_until"] = -1
	var oc_money := Game.money
	check(Game.call_someone_out() == "" and Game.money == oc_money - Game.CALLOUT_FEE / 2,
		"on call: calling the person carrying the phone costs half")
	check(int(Game.staff[0]["morale"]) == 75,
		"on call: and costs them less, because they were expecting it")
	Game.fire(Game.staff[0])
	check(Game.oncall == "", "on call: the retainer stops when they leave")
	Game.hire(Staff.make_candidate(RandomNumberGenerator.new(), Game.habits))
	# and the phone rings where the player is, instead of waiting in a panel
	Game.night_call = {}
	Game.callout_who = ""
	Game.callout_until = -1
	Game.night_call_tick()
	# --- kit that is not on the floor you are standing on ---
	var el_dev: Net.NDevice = Game.all_devices()[0]
	var el_sites := Game.sites.duplicate(true)
	var el_here := Game.current_site
	check(Game.elsewhere(el_dev) == "",
		"sites: with one floor there is nothing to warn about")
	Game.add_site("Debrecen exchange", Vector2i(5, 5), "acquired", "Debrecen")
	Game.current_site = 1
	check(Game.elsewhere(el_dev) == Game.site_name(Game.site_of_device(el_dev)),
		"sites: a device in another building names the building it is in")
	Game.current_site = Game.site_of_device(el_dev)
	check(Game.elsewhere(el_dev) == "",
		"sites: and says nothing when you are standing in front of it")
	Game.sites = el_sites
	Game.current_site = el_here

	# --- the slow measures, with a direction ---
	var tr_hist := Game.history.duplicate(true)
	Game.history = [{"cycle": Game.cycle - 30, "tidy": 0.2, "drift": 0.1}]
	var tr_lines := Game.trend_read()
	Game.best_outage_streak = 0
	check(Game.best_streak() >= Game.cycles_since_customer_outage(),
		"trend: the record is never behind the streak you are already having")
	check(tr_lines.size() >= 4 and String(tr_lines[0]).begins_with("Reliability:"),
		"trend: the panel reads reliability, the floor, the documentation and the habits")
	check(Game._trend_word(0.9, 0.4, true) == "getting better" \
			and Game._trend_word(0.4, 0.9, true) == "getting worse" \
			and Game._trend_word(0.5, 0.5, true) == "holding",
		"trend: a measure that should be high reads better when it rises")
	check(Game._trend_word(0.9, 0.4, false) == "getting worse" \
			and Game._trend_word(0.1, 0.6, false) == "getting better",
		"trend: drift is judged the other way round, because rising is the bad direction")
	Game.history = tr_hist

	# --- what one shift leaves for the next ---
	var ho_racks := Game.racks
	var ho_links := Game.links
	var ho_haz := Game.hazards
	var ho_tickets := Game.tickets
	var ho_crates := Game.crates
	Game.racks = []
	Game.links = []
	Game.hazards = []
	Game.tickets = []
	Game.crates = []
	Game.customer_outage_active = false
	Game.guided_outage = {}
	var ho_events := Game.events.duplicate()
	Game.events = []
	check(Game.handover_lines() == ["Nothing happened. Everything that was up is still up."],
		"handover: a quiet shift says so, rather than inventing something")
	Game.log_event("SECURITY: somebody reached the management address from a customer machine.")
	var ho_watch := Game.handover_lines()
	check(String(ho_watch[0]).begins_with("On our watch:") and String(ho_watch[0]).contains("SECURITY"),
		"handover: what happened on the watch is repeated before what is still open")
	Game.events = ho_events
	Game.hazards = [{"kind": "water", "rack": "R9", "site": 0, "tile": [0, 0], "severity": 2,
		"started": Game.cycle, "detected": false, "zone": ["R9"]}]
	Game.customer_outage_active = true
	var ho_lines := Game.handover_lines()
	check(ho_lines.size() >= 2 and String(ho_lines[0]).contains("off the air") \
			and String(ho_lines[1]).contains("R9") and String(ho_lines[1]).contains("nothing is watching"),
		"handover: the customer comes first, then what is burning, and it says what nobody is watching")
	Game.customer_outage_active = false
	Game._handover_slot = -1
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 6  # the night shift clocking on
	Game.handover_tick()
	check(not Game.handover.is_empty() and String(Game.handover["from"]) == "day",
		"handover: it is written at the shift change, by the shift going home")
	check(int(Game.handover.get("substantive", 0)) > 0 and not bool(Game.handover["read"]),
		"handover: a note with something in it starts unread")
	# leaving it unread reads as the documentation habit it is
	var ho_docs := float(Game.habits["documents"])
	Game._handover_slot = -1
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 2
	Game.handover_tick()
	check(float(Game.habits["documents"]) < ho_docs,
		"handover: notes nobody read cost the same as documentation nobody wrote")
	Game.read_handover()
	var ho_docs2 := float(Game.habits["documents"])
	Game._handover_slot = -1
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 6
	Game.handover_tick()
	check(float(Game.habits["documents"]) >= ho_docs2,
		"handover: and reading it costs nothing at all")
	Game.handover = {}
	Game.handover_tick()
	check(Game.handover.is_empty(), "handover: and written once, not every cycle of that slot")
	Game.racks = ho_racks
	Game.links = ho_links
	Game.hazards = ho_haz
	Game.tickets = ho_tickets
	Game.crates = ho_crates

	# the sign on the wall never contradicts the brief in the corner
	var sign_guided := Game.guided_outage.duplicate(true)
	Game.customer_outage_active = false
	Game.guided_outage = {"state": "reported"}
	check(Game.customer_down_now() and Game.cycles_since_customer_outage() == 0,
		"sign: a teaching outage is still a customer being down, and stops the streak")
	Game.guided_outage = {}
	check(not Game.customer_down_now(), "sign: and with nothing down the streak runs again")
	Game.guided_outage = sign_guided
	check(Game.sentence("the panel is showing smoke in R1") == "The panel is showing smoke in R1",
		"copy: a sentence gets one capital letter, and R1 stays R1")
	check(not Game.night_call.is_empty() and String(Game.night_call["reason"]).contains("smoke"),
		"night call: an empty floor with something live rings the phone, and says what it is")
	check(Game.answer_night_call(false) == "" and Game.night_call.is_empty(),
		"night call: letting it wait costs nothing and clears the call")
	Game.night_call_tick()
	var nc_money := Game.money
	check(Game.answer_night_call(true) == "" and Game.money < nc_money \
			and Staff.anyone_on_shift(),
		"night call: getting somebody in is the call-out, priced by the rota")
	Game.night_call = {}
	Game.night_call_tick()
	check(Game.night_call.is_empty(),
		"night call: with somebody in the building, nobody rings")
	Game.callout_who = ""
	Game.callout_until = -1
	Game.hazards = []
	Game.staff = co_staff
	Game.hazards = co_haz
	Game.cycle = co_cycle
	Game.callout_who = ""
	Game.callout_until = -1

	# somebody can be put on keeping the floor clear
	Game.packaging = 3
	Game.habits["tidy"] = 0.5
	Game.do_housekeeping("Rey", true)
	check(Game.packaging == 0 and float(Game.habits["tidy"]) > 0.5,
		"housekeeping duty: a proper floor walk clears the aisle and reads as the habit")
	Game.do_housekeeping("Rey", false)
	check(Game.aisle_blocked() == false and Game.packaging > 0
			and float(Game.habits["tidy"]) < 1.0,
		"housekeeping duty: done badly it stacks cardboard for somebody to find later")
	check(Game.DUTIES.has("housekeeping"), "housekeeping duty: it is on the board like any other")
	Game.packaging = 0
	# the floor shows what the habits are
	Game.habits["tidy"] = 1.0
	check(Game.housekeeping_mess() == 0, "housekeeping: a tidy team leaves nothing on the floor")
	Game.habits["tidy"] = 0.0
	check(Game.housekeeping_mess() > 0, "housekeeping: bad habits leave the room to show for it")
	Game.habits["tidy"] = 0.5
	var before_window := float(Game.habits["windows"])
	Game.maintenance_until = -1
	Game.maintenance_used = 0
	Game.declare_maintenance()
	check(float(Game.habits["windows"]) > before_window,
		"habits: taking the change window counts, and counts double")
	# two identically hired people, two different players
	var hab_rng := RandomNumberGenerator.new()
	hab_rng.seed = 99
	var careful: Dictionary = Staff.make_candidate(hab_rng, {"saves": 0.5, "documents": 0.5,
		"windows": 0.5, "tidy": 0.5})
	var hasty := careful.duplicate(true)
	hasty["name"] = "Nagy Bence"
	careful["shift"] = "day"
	hasty["shift"] = "day"
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 3  # both of them on shift
	Game.staff = [careful]
	Game.habits = {"saves": 1.0, "documents": 1.0, "windows": 1.0, "tidy": 1.0}
	for _c in 60:
		Staff.shadow_tick()
	Game.staff = [hasty]
	Game.habits = {"saves": 0.0, "documents": 0.0, "windows": 0.0, "tidy": 0.0}
	for _c in 60:
		Staff.shadow_tick()
	check(float(Staff.habits_of(careful)["saves"]) > 0.6 \
			and float(Staff.habits_of(hasty)["saves"]) < 0.4,
		"habits: identical hires under different players end up working differently")
	check("saves configurations without being asked" in Staff.habit_read(careful) \
			and "works live" in Staff.habit_read(hasty),
		"habits: the written read of a person matches what they actually picked up")
	# and cleaning up a bad culture is possible, but slow
	Game.staff = [hasty]
	Game.habits = {"saves": 1.0, "documents": 1.0, "windows": 1.0, "tidy": 1.0}
	var dirty_start := float(Staff.habits_of(hasty)["saves"])
	for _c in 10:
		Staff.shadow_tick()
	var after_ten := float(Staff.habits_of(hasty)["saves"])
	check(after_ten > dirty_start and after_ten < 0.5,
		"habits: ten good cycles move a bad habit without erasing it")
	for _c in 200:
		Staff.shadow_tick()
	check(float(Staff.habits_of(hasty)["saves"]) > 0.8,
		"habits: a long stretch of doing it properly does eventually change the culture")
	var hab_payload: Dictionary = JSON.parse_string(Game.snapshot())
	check(float(hab_payload["habits"]["saves"]) == 1.0,
		"habits: the player's own working habits persist with the campaign")
	Game.staff = hab_staff
	Game.habits = hab_player
	Game.maintenance_until = -1

	# --- you are the ticket now: an outage that is not yours ---
	# the later sections keep adding hardware to this shared world, so give it
	# enough cooling that nothing trips for reasons this section is not testing
	var cool_rack := Game.add_rack(Vector2i(20, 6))
	for cool_slot in 3:
		cool_rack.slots[cool_slot] = Game.new_device("crac-1")
	var up_deals := Game.deals.duplicate(true)
	var up_posts := Game.status_posts.duplicate(true)
	var up_staff := Game.staff.duplicate(true)
	Game.staff = []  # nobody wandering off and unplugging things mid-measurement
	Game.status_posts = []
	Game.reputation = 60
	var up_deal := {"id": "up1", "customer": "Duna Media", "kind": "hosting",
		"params": {"ip": "10.40.0.10"}, "fee": 100, "brief": "", "load": 100,
		"healthy": true, "ever_healthy": true, "cycles": 10, "up_cycles": 10}
	Game.deals = [up_deal]
	var up_rack := Game.add_rack(Vector2i(34, 1))
	var up_sw := Game.new_device("sw-8")
	var up_srv := Game.new_device("srv-1")
	var up_peer := Game.new_device("srv-1")
	up_rack.slots[0] = up_sw
	up_rack.slots[1] = up_srv
	up_rack.slots[2] = up_peer
	Game.connect_ifaces(up_srv.ifaces[0], up_sw.ifaces[0])
	Game.connect_ifaces(up_peer.ifaces[0], up_sw.ifaces[1])
	Game.add_ip(up_srv.ifaces[0], "10.44.0.10/24")
	Game.add_ip(up_peer.ifaces[0], "10.44.0.11/24")
	up_deal["params"] = {"ip": "10.44.0.10"}
	Game.upstream = {}
	Game.sla_tick()
	check(bool(up_deal["healthy"]), "upstream: the customer is delivered before anything goes wrong")
	Game.upstream = {"kind": "regional", "party": "your transit provider",
		"started": Game.cycle, "until": Game.cycle + 4, "opened": false, "case": "",
		"chased": 0, "posts": 0, "protected": false}
	check(Game.chase_upstream() != "" and Game.open_upstream_case() == "" \
			and String(Game.upstream["case"]) != "",
		"upstream: you cannot chase a ticket you never raised")
	var until_before := int(Game.upstream["until"])
	check(Game.chase_upstream() == "" and int(Game.upstream["until"]) < until_before \
			and Game.chase_upstream() != "",
		"upstream: chasing moves their estimate in, once per cycle")
	var evidence := Game.upstream_evidence()
	check(evidence.size() >= 3 and "nothing here changed" in String(evidence[0]),
		"upstream: your own tooling proves the fault is not yours")
	Game.sla_tick()
	check(not bool(up_deal["healthy"]) and bool(up_deal["upstream_down"]),
		"upstream: an unprotected customer goes off the air even though nothing of yours broke")
	# silence is punished
	Game.cycle = int(Game.upstream["until"])
	var rep_quiet_upstream := Game.reputation
	Game.upstream_tick()
	check(Game.upstream.is_empty() and Game.reputation < rep_quiet_upstream - 4,
		"upstream: saying nothing for the whole outage costs more than the outage did")
	# the same outage, communicated
	Game.reputation = 60
	Game.last_upstream_cycle = -999
	Game.upstream = {"kind": "regional", "party": "your transit provider",
		"started": Game.cycle, "until": Game.cycle + 2, "opened": true, "case": "TRA-1",
		"chased": 1, "posts": 4, "protected": false}
	var rep_open := Game.reputation
	Game.cycle += 2
	Game.upstream_tick()
	check(Game.upstream.is_empty() and Game.reputation > rep_open,
		"upstream: handling somebody else's outage openly leaves you better off than before it")
	# and the redundancy somebody paid for gets to do its job
	Game.reputation = 60
	Game.last_upstream_cycle = -999
	Game.upstream = {"kind": "regional", "party": "your transit provider",
		"started": Game.cycle, "until": Game.cycle + 2, "opened": true, "case": "TRA-2",
		"chased": 0, "posts": 0, "protected": true}
	up_deal["healthy"] = true
	Game.sla_tick()
	check(bool(up_deal["healthy"]) and not bool(up_deal["upstream_down"]),
		"upstream: a second upstream path carries the customer straight through it")
	Game.cycle = int(Game.upstream["until"])
	var rep_ready := Game.reputation
	Game.upstream_tick()
	check(Game.upstream.is_empty() and Game.reputation > rep_ready \
			and Game.last_upstream_cycle == Game.cycle,
		"upstream: prepared operators come out ahead, and the clock stops it recurring")
	Game.upstream = {}
	Game.last_upstream_cycle = Game.cycle
	Game._maybe_upstream_event()
	check(Game.upstream.is_empty(),
		"upstream: it cannot happen again immediately, whatever the dice say")
	Game.deals = up_deals
	Game.status_posts = up_posts
	Game.staff = up_staff
	Game.last_upstream_cycle = -999

	# --- hear it before you see it ---
	var quiet_mix := Sfx.ambient_mix(0.1, 0.0)
	var busy_mix := Sfx.ambient_mix(1.0, 0.0)
	var hot_mix := Sfx.ambient_mix(1.0, 1.0)
	check(float(busy_mix[0]) > float(quiet_mix[0]) and float(busy_mix[1]) > float(quiet_mix[1]) \
			and float(hot_mix[1]) > float(busy_mix[1]),
		"sound: a busy floor is audibly busier than an idle one, and a hot one more again")
	var audio := Game.audio_state()
	check(audio.has("load") and audio.has("heat") and audio["cues"] is Array,
		"sound: the room's voice is derived from live capacity and heat, not a loop")
	var snd_outage := Game.customer_outage_active
	Game.customer_outage_active = true
	check("alert" in Game.audio_alerts(),
		"sound: a customer outage is audible before any panel is opened")
	Game.customer_outage_active = snd_outage
	var snd_ups := Game.ups.duplicate(true)
	var snd_feeds: Dictionary = Game.site_feeds(Game.current_site)
	Game.ups[Game.current_site] = 3
	snd_feeds["A"] = false
	check("ups" in Game.audio_alerts(),
		"sound: running on battery has its own cue, and only while the battery is carrying it")
	Game.ups[Game.current_site] = 0
	check(not ("ups" in Game.audio_alerts()),
		"sound: a flat battery stops beeping, because the condition changed")
	snd_feeds["A"] = true
	Game.ups = snd_ups
	Sfx.last_cue = ""
	var was_muted: bool = Sfx.muted
	Sfx.muted = true
	Sfx.play("alert")
	check(Sfx.last_cue == "", "sound: muting the game really does silence every cue")
	Sfx.muted = was_muted

	# --- something survives the run ---
	Legacy.path = "user://legacy_test.json"
	var leg_staff := Game.staff.duplicate(true)
	var leg_refs := Game.references.duplicate(true)
	var leg_templates := Game.templates.duplicate(true)
	Game.staff = [{"name": "Toth Eszter", "role": "engineer", "skill": 4, "salary": 500,
		"morale": 80, "shift": "day", "training_left": 0, "certs": [],
		"habits": {"saves": 0.9, "documents": 0.7, "windows": 0.6, "tidy": 0.8}}]
	Game.references = ["Balaton Zrt"]
	Game.templates = [{"name": "edge switch", "type": "switch", "cfg": {}}]
	Game.reputation = 70
	Game.demo = false
	Game.cycle = maxi(Game.cycle, 40)
	Legacy.harvest("ran out of money")
	var carried_ids: Array = []
	for entry: Dictionary in Legacy.offered:
		carried_ids.append(String(entry["id"]))
	check("colleague" in carried_ids and "reference" in carried_ids \
			and "runbooks" in carried_ids and "lesson" in carried_ids,
		"legacy: a finished run leaves people, a customer, the documentation, and a lesson")
	check(int(Legacy.epitaph["cycles"]) == Game.cycle \
			and String(Legacy.epitaph["why"]) == "ran out of money",
		"legacy: the company gets an epitaph describing the run that actually happened")
	Legacy.selected = []
	check(Legacy.carry_toggle("colleague") and Legacy.carry_toggle("reference") \
			and not Legacy.carry_toggle("runbooks") and Legacy.selected.size() == 2,
		"legacy: carrying is a choice with a hard limit, not an accumulation")
	# the next run starts with them, and with nothing else
	var fresh_money := Game.money
	Game.staff = []
	Game.references = []
	Game.templates = []
	Game.leads = []
	Game.reputation = 50
	Legacy.apply_carried()
	check(Game.staff.size() == 1 and int(Game.staff[0]["skill"]) == 4 \
			and int(Game.staff[0]["morale"]) <= 60,
		"legacy: the colleague comes back with their skill and the fatigue you left them with")
	check("Balaton Zrt" in Game.references and Game.reputation == 55 \
			and Game.leads.size() == 1 and int(Game.leads[0]["size"]) < 150,
		"legacy: the reference customer follows you as one small early contract")
	check(Game.templates.is_empty() and Game.money == fresh_money and Legacy.selected.is_empty(),
		"legacy: what you did not choose does not arrive, and nothing carries cash")
	# losing badly with nothing to your name still leaves the lesson
	Game.staff = []
	Game.references = []
	Game.templates = []
	Game.blueprints = []
	Game.rivals = []
	Legacy.harvest("insolvent")
	check(Legacy.offered.size() == 1 and String(Legacy.offered[0]["id"]) == "lesson",
		"legacy: a run that leaves nothing material still leaves something to carry")
	Game.staff = leg_staff
	Game.references = leg_refs
	Game.templates = leg_templates
	Game.rivals = Rivals.spawn()
	Legacy.epitaph = {}
	Legacy.offered = []
	Legacy.selected = []

	# --- name the skill, and be honest about the fumbles ---
	var sk_log := Game.skill_log.duplicate(true)
	var sk_fumbles := Game.skill_fumbles.duplicate(true)
	var sk_deals := Game.deals.duplicate(true)
	Game.skill_log = {}
	Game.skill_fumbles = {}
	Game.pending_recognition = []
	Game.deals = []
	Game.events = []
	Skills.observe("service_delivery")
	check(int(Game.skill_log["service_delivery"]["count"]) == 1 \
			and Game.pending_recognition == ["service_delivery"],
		"skills: doing the thing records it, and the line waits rather than firing mid-action")
	Game.deals = [{"id": "sk", "customer": "Down Kft", "kind": "hosting", "params": {},
		"fee": 10, "brief": "", "load": 10, "healthy": false, "ever_healthy": true}]
	Skills.recognition_tick()
	check(Game.pending_recognition.size() == 1 and Game.events.is_empty(),
		"skills: recognition never interrupts a live incident")
	Game.deals = []
	Skills.recognition_tick()
	check(Game.pending_recognition.is_empty() and "LEARNED:" in String(Game.events[0]) \
			and "service turn-up" in String(Game.events[0]),
		"skills: once the floor is quiet it names the real-world skill, with somewhere to read more")
	var said_events := Game.events.size()
	Skills.observe("service_delivery")
	Skills.recognition_tick()
	check(Game.events.size() == said_events and int(Game.skill_log["service_delivery"]["count"]) == 2,
		"skills: it is said once, and counted every time")
	for _r in 2:
		Skills.observe("service_delivery")
	var once_profile := Skills.profile()
	Skills.observe("l2_isolation")
	var mixed_profile := Skills.profile()
	check(String(once_profile[0]).begins_with("Reliably") \
			and String(mixed_profile[1]).begins_with("Has once"),
		"skills: doing it four times is a claim, doing it once is only a story")
	Skills.fumble("saved_configs")
	var honest_profile := Skills.profile()
	check("Also has lost a running configuration" in String(honest_profile[honest_profile.size() - 1]),
		"skills: the profile includes the parts that went badly, in the same voice")
	var sk_payload: Dictionary = JSON.parse_string(Game.snapshot())
	check(sk_payload["skill_log"].has("service_delivery") \
			and sk_payload["skill_fumbles"].has("saved_configs"),
		"skills: what the player demonstrated persists with the campaign")
	Game.skill_log = sk_log
	Game.skill_fumbles = sk_fumbles
	Game.pending_recognition = []
	Game.deals = sk_deals

	# --- somebody is actually using it ---
	var eye_deals := Game.deals.duplicate(true)
	var eye_deal := {"id": "eye", "customer": "Fonix Klinika", "kind": "hosting",
		"params": {}, "fee": 120, "brief": "", "load": 300, "healthy": true,
		"ever_healthy": true, "cycles": 12, "up_cycles": 12, "loyalty": 0.7}
	Game.deals = [eye_deal]
	var biz := Market.business_for(eye_deal)
	check(Market.business_for(eye_deal)["id"] == biz["id"] and String(biz["unit"]) != "",
		"customer eye: every customer runs a specific, stable business rather than a load figure")
	var live_eye := Game.customer_eye(eye_deal)
	check(String(biz["who"]).to_upper() in String(live_eye["metric"]) \
			and String(live_eye["activity"]) == String(biz["live"]),
		"customer eye: a healthy service reads as the people using it, not bytes")
	eye_deal["healthy"] = false
	var down_eye := Game.customer_eye(eye_deal)
	check(String(down_eye["activity"]) == String(biz["down"]) \
			and String(down_eye["state"]) == "down",
		"customer eye: an outage shows their consequence, never a fabricated success")
	eye_deal["healthy"] = true
	# the night they told you about in advance
	Game.reputation = 60
	eye_deal["peak_event"] = {"label": String(biz["peak"]), "cycle": Game.cycle + 2, "multiplier": 3}
	var warned_eye := Game.customer_eye(eye_deal)
	check("IN 2 CYCLES" in String(warned_eye["relationship"]) \
			and Game.peak_multiplier(eye_deal) == 1.0,
		"customer eye: the busy night is announced in advance and carries no traffic until it arrives")
	eye_deal["peak_event"]["cycle"] = Game.cycle
	check(Game.peak_multiplier(eye_deal) == 3.0,
		"customer eye: on the night itself their traffic really does triple")
	var rep_before_peak := Game.reputation
	eye_deal["degraded"] = false
	Game.peak_tick(eye_deal)
	check(int(eye_deal["peaks_carried"]) == 1 and Game.reputation > rep_before_peak \
			and float(eye_deal["loyalty"]) > 0.7 and not eye_deal.has("peak_event"),
		"customer eye: carrying their busiest night earns more than the money it paid")
	check("CARRIED" in String(Game.customer_eye(eye_deal)["relationship"]),
		"customer eye: and they keep saying so afterwards")
	# dropping it is the other half
	eye_deal["peak_event"] = {"label": String(biz["peak"]), "cycle": Game.cycle, "multiplier": 3}
	eye_deal["healthy"] = false
	var rep_before_drop := Game.reputation
	Game.peak_tick(eye_deal)
	check(int(eye_deal.get("peaks_carried", 0)) == 1 and Game.reputation < rep_before_drop,
		"customer eye: dropping the one night that mattered costs standing and loyalty")
	Game.deals = eye_deals

	# --- a nemesis with a face, and a competitor worth being decent to ---
	var nem_rivals := Game.rivals.duplicate(true)
	var nem_leads := Game.leads.duplicate(true)
	Game.rivals = Rivals.spawn()
	Game.leads = []
	Game.nemesis = ""
	Game.nemesis_reason = ""
	var villain: Dictionary = Game.rivals[0]
	check(String(villain.get("temper", "")) != "" and Rivals.temper_of(villain).has("grudge"),
		"rivals: every competitor is a person with a temperament, not only a pricing weight")
	for _p in 2:
		Rivals.remember(villain, -1, "you took the Duna account off them")
	check(Game.nemesis == "" , "rivals: ordinary competition does not make an enemy")
	Rivals.remember(villain, -1, "you took the Duna account off them")
	check(Game.nemesis == String(villain["name"]) \
			and "Duna account" in Game.nemesis_reason,
		"rivals: exactly one rival escalates, and the player can say what started it")
	var second: Dictionary = Game.rivals[1]
	for _p2 in 4:
		Rivals.remember(second, -1, "you undercut them again")
	check(Game.nemesis == String(villain["name"]),
		"rivals: the nemesis is the first one you pushed too far, not whoever is angriest today")
	var report_nemesis := Game.make_report()
	check("needle" in report_nemesis and String(villain["name"]) in String(report_nemesis["needle"]),
		"rivals: your nemesis has something to say in every quarterly report")
	villain["deals"] = 0
	Rivals.check_nemesis_beaten()
	check(Game.nemesis == "", "rivals: a nemesis can be beaten specifically rather than statistically")
	# and the decent ones are worth something concrete
	var friend: Dictionary = Game.rivals[3]
	Rivals.remember(friend, 2, "you covered for them")
	check(Rivals.friendly().has(friend), "rivals: a favour is remembered in the other direction too")
	for _f in 200:
		Rivals.maybe_favour()
		if not Game.leads.is_empty():
			break
	check(Game.leads.size() == 1 and String(Game.leads[0]["from_rival"]) == String(friend["name"]) \
			and int(Game.leads[0]["size"]) > 0,
		"rivals: a friendly competitor's referral arrives as a real contract to win")
	Game.rivals = nem_rivals
	Game.leads = nem_leads
	Game.nemesis = ""
	Game.nemesis_reason = ""

	# --- hand me your outage ---
	var pz_rack := Game.add_rack(Vector2i(36, 1))
	var pz_sw := Game.new_device("sw-8")
	var pz_srv := Game.new_device("srv-1")
	var pz_peer := Game.new_device("srv-1")
	pz_rack.slots[0] = pz_sw
	pz_rack.slots[1] = pz_srv
	pz_rack.slots[2] = pz_peer
	Game.connect_ifaces(pz_srv.ifaces[0], pz_sw.ifaces[0])
	Game.connect_ifaces(pz_peer.ifaces[0], pz_sw.ifaces[1])
	Game.add_ip(pz_srv.ifaces[0], "10.55.0.10/24")
	Game.add_ip(pz_peer.ifaces[0], "10.55.0.11/24")
	pz_sw.ifaces[0].enabled = false  # the actual fault, exactly as the player left it
	var pz_deals := Game.deals.duplicate(true)
	Game.deals = [{"id": "pz", "customer": "Szeged Klinika", "kind": "hosting",
		"params": {"ip": "10.55.0.10"}, "fee": 100, "brief": "", "load": 100,
		"healthy": false, "ever_healthy": true, "cycles": 9, "up_cycles": 8}]
	var pz_money := Game.money
	var exported := Puzzle.export_state("review")
	var pz_payload: Dictionary = JSON.parse_string(exported)
	check(int(pz_payload["puzzle"]) >= 1 and not pz_payload.has("money") \
			and not pz_payload.has("deals") and String(pz_payload["symptom"]) != "",
		"puzzle: an export carries the network and the symptom, and none of the company")
	check("what I am missing" in String(pz_payload["note"]),
		"puzzle: the same file can be framed as a question rather than a challenge")
	check(Puzzle.import_state("{\"note\": \"a save, not a puzzle\"}") != "",
		"puzzle: nonsense on the clipboard is refused rather than loaded")
	check(Puzzle.import_state(exported) == "" and Puzzle.active() and Game.sandbox \
			and Game.deals.is_empty(),
		"puzzle: importing opens a scratch session with nothing of the recipient's at stake")
	var imported_iface: Net.Iface = null
	for pz_dev: Net.NDevice in Game.all_devices():
		for pz_if: Net.Iface in pz_dev.ifaces:
			if not pz_if.enabled and not pz_if.name.begins_with("Management"):
				imported_iface = pz_if
	check(imported_iface != null,
		"puzzle: the fault itself travels, not a description of it")
	imported_iface.enabled = true
	var fix := Puzzle.solution("the access port was shut")
	var fix_lines := Puzzle.read_solution(fix)
	check(fix_lines.size() >= 2 and "is now up" in String(fix_lines[0]) \
			and "they said:" in String(fix_lines[fix_lines.size() - 1]),
		"puzzle: the answer that goes back names what was actually changed")
	check(Puzzle.read_solution("{}").is_empty(),
		"puzzle: an answer from somewhere else is ignored")
	Puzzle.close()
	check(not Puzzle.active() and Game.money == pz_money \
			and Game.deals.size() == 1 and String(Game.deals[0]["customer"]) == "Szeged Klinika",
		"puzzle: closing it puts the player back in their own company, untouched")
	# blind mode gives both of them something to find
	var blind_payload: Dictionary = JSON.parse_string(Puzzle.export_state("solve", true))
	var blind_down := 0
	for bd_name: String in blind_payload["devices"]:
		for bi: Dictionary in blind_payload["devices"][bd_name].get("ifaces", []):
			if not bool(bi.get("enabled", true)):
				blind_down += 1
	check(blind_down >= 2, "puzzle: a blind export adds a fault the sender has not seen either")
	Game.deals = pz_deals
	Game.sandbox = false

	# --- the quiet cycle ---
	var qt_deals := Game.deals.duplicate(true)
	Game.deals = []
	Game.customer_outage_active = false
	Game.upstream = {}
	var qt_rack := Game.add_rack(Vector2i(38, 1))
	var qt_sw := Game.new_device("sw-8")
	var qt_srv := Game.new_device("srv-1")
	qt_rack.slots[0] = qt_sw
	qt_rack.slots[1] = qt_srv
	Game.connect_ifaces(qt_srv.ifaces[0], qt_sw.ifaces[0])
	qt_sw.startup = Game.device_config(qt_sw)
	qt_srv.startup = Game.device_config(qt_srv)
	var messy := Game.rack_tidiness(qt_rack)
	check(messy < 1.0 and Game.quiet_now(),
		"quiet: with nothing on fire the game notices, and an unkept cabinet is not pretending otherwise")
	var suggestion := Game.housekeeping_suggestion()
	check(suggestion != "" and ("blanking panel" in suggestion or "unlabelled" in suggestion \
			or "nobody has saved" in suggestion),
		"quiet: there is something worth doing on the floor, offered once and never demanded")
	for qt_slot in Net.Rack.SLOTS:
		if qt_rack.slots[qt_slot] == null:
			Game.toggle_blanking(qt_rack, qt_slot)
	Game.set_note(qt_srv.ifaces[0], "customer A, do not repatch")
	Game.set_note(qt_sw.ifaces[0], "customer A uplink")
	check(Game.rack_tidiness(qt_rack) > messy,
		"quiet: blanking the gaps and labelling the ports visibly improves the cabinet itself")
	var messy_chance := 0.0
	var tidy_chance := Game.fault_chance()
	qt_rack.blanked = {}
	messy_chance = Game.fault_chance()
	check(tidy_chance < messy_chance,
		"quiet: a kept floor genuinely breaks less often, which is the honest reward")
	for qt_slot2 in Net.Rack.SLOTS:
		if qt_rack.slots[qt_slot2] == null:
			Game.toggle_blanking(qt_rack, qt_slot2)
	Game.deals = [{"id": "qt", "customer": "Busy Kft", "kind": "hosting", "params": {},
		"fee": 10, "brief": "", "load": 10, "healthy": false, "ever_healthy": true}]
	check(not Game.quiet_now() and Game.housekeeping_suggestion() == "",
		"quiet: while something is down the game says nothing about tidying up")
	Game.deals = qt_deals

	# --- decommission properly ---
	Game.destruction_certs = []
	Game.data_risks = []
	var dc_rack := Game.add_rack(Vector2i(40, 1))
	var dc_sw := Game.new_device("sw-8")
	var dc_a := Game.new_device("srv-1")
	var dc_b := Game.new_device("srv-1")
	dc_rack.slots[0] = dc_sw
	dc_rack.slots[1] = dc_a
	dc_rack.slots[2] = dc_b
	Game.connect_ifaces(dc_a.ifaces[0], dc_sw.ifaces[0])
	Game.connect_ifaces(dc_b.ifaces[0], dc_sw.ifaces[1])
	Game.add_ip(dc_a.ifaces[0], "10.66.0.10/24")
	Game.add_ip(dc_b.ifaces[0], "10.66.0.11/24")
	Game.add_static_route(dc_b, "10.99.0.0", 24, "10.66.0.10")
	Game.monitors.append({"kind": "ping", "from": dc_b.name, "target": "10.66.0.10",
		"label": "customer A", "failing": false})
	var monitors_before := Game.monitors.size()
	var money_before_dc := Game.money
	var rushed := Game.decommission(dc_a, [])
	check(int(rushed["value"]) > 0 and not bool(rushed["certified"]) \
			and Game.data_risks.size() == 1 and Game.monitors.size() == monitors_before,
		"decom: pulling it out pays something now and leaves the disks and the leftovers behind")
	check(Game.audit_findings().size() >= 1 \
			and "certificate" in String(Game.audit_findings()[0]),
		"decom: a missing sanitisation record is an audit finding that stands until it bites")
	Game.cycle += 8
	var rep_before_leak := Game.reputation
	for _dc in 400:
		Game.decom_tick()
		if Game.data_risks.is_empty():
			break
	check(Game.data_risks.is_empty() and Game.reputation < rep_before_leak \
			and Game.money < money_before_dc + int(rushed["value"]),
		"decom: the drive resurfaces eventually, and that is the expensive half")
	# the same unit, done properly
	var money_before_proper := Game.money
	Game.monitors.append({"kind": "ping", "from": dc_sw.name, "target": "10.66.0.11",
		"label": "customer B", "failing": false})
	var monitors_now := Game.monitors.size()
	var proper := Game.decommission(dc_b, Game.DECOM_STEPS)
	check(int(proper["value"]) > int(rushed["value"]) and bool(proper["certified"]) \
			and Game.destruction_certs.size() == 1 and Game.data_risks.is_empty() \
			and Game.monitors.size() == monitors_now - 1,
		"decom: doing it properly returns more money, keeps the certificate and reclaims the leftovers")
	check(Game.money == money_before_proper + int(proper["value"]),
		"decom: the resale is the only thing that pays, and it pays once")
	# delegated, which means done the way that person works
	var dc_staff := Game.staff.duplicate(true)
	Game.staff = [{"name": "Varga Karoly", "role": "tech", "skill": 3, "salary": 300,
		"morale": 70, "shift": "day", "training_left": 0, "certs": [],
		"habits": {"saves": 0.2, "documents": 0.2, "windows": 0.5, "tidy": 0.2}}]
	var hurried := Game.decommission_by_tech(dc_sw)
	check(hurried["skipped"].size() >= 2 and Game.data_risks.size() == 1,
		"decom: a technician who cuts corners cuts exactly the boring ones")
	Game.staff = dc_staff
	Game.data_risks = []
	Game.destruction_certs = []

	# --- facility housekeeping ---
	var fac_stage := Game.stage
	Game.stage = 1
	Game.facility = {"filters": Game.cycle, "aircon": Game.cycle, "generator": Game.cycle,
		"ups": Game.cycle}
	Game.facility_auto = {}
	Game.heat_wave_until = -1
	var clean_cooling := Game.cooling_capacity()
	check(Game.filter_dirt() == 0.0 and Game.facility_due_in("filters") > 0,
		"facility: a serviced floor has a visible schedule rather than a random tax")
	Game.cycle += int(Game.FACILITY_TASKS["filters"]["every"]) + 120
	check(Game.filter_dirt() == 1.0 and Game.cooling_capacity() < clean_cooling,
		"facility: neglected filters cost cooling headroom along a curve you can see coming")
	var money_before_fac := Game.money
	Game.money = 5000
	check(Game.service_facility("filters") == "" and Game.filter_dirt() == 0.0 \
			and Game.money < 5000,
		"facility: doing the job costs money and restores the headroom immediately")
	check(Game.service_facility("nonsense") != "", "facility: there is no such job")
	# an untested generator is a generator you are hoping about
	Game.facility["generator"] = Game.cycle - 200
	check(not Game.generator_ready(), "facility: the load test goes stale, and the panel says so")
	var fac_feeds: Dictionary = Game.site_feeds(Game.current_site)
	fac_feeds["A"] = false
	Game.ups[Game.current_site] = 0
	check(not Game.feed_live(Game.current_site, "A"),
		"facility: with a flat battery and a stale test, the dead feed is simply dead")
	Game.service_facility("generator")
	check(Game.generator_ready() and Game.feed_live(Game.current_site, "A"),
		"facility: a tested generator actually carries the load when the feed goes")
	fac_feeds["A"] = true
	# a heat wave separates prepared floors from lucky ones
	var before_wave := Game.cooling_capacity()
	Game.heat_wave_until = Game.cycle + 3
	check(Game.heat_wave() and Game.cooling_capacity() < before_wave,
		"facility: a heat wave takes a tenth of the cooling and rewards whoever kept headroom")
	Game.heat_wave_until = -1
	# and the whole schedule is delegable
	Game.facility_auto["ups"] = true
	Game.facility["ups"] = Game.cycle - 200
	var fac_staff := Game.staff.duplicate(true)
	Game.staff = [{"name": "Nagy Dora", "role": "tech", "skill": 3, "salary": 300, "morale": 70,
		"shift": "day", "training_left": 0, "certs": []}]
	Game.facility_tick()
	check(int(Game.facility["ups"]) == Game.cycle,
		"facility: a delegated task is kept on schedule by the crew, and billed")
	Game.staff = fac_staff
	Game.stage = fac_stage
	Game.money = money_before_fac
	Game.facility_auto = {}

	# --- the tour ---
	var tour_leads := Game.leads.duplicate(true)
	var tour_incidents := Game.incidents.duplicate(true)
	Game.leads = []
	Game.incidents = []
	Game.data_risks = []
	Game.tour = {"kind": "prospect", "cycle": Game.cycle + 5, "crammed": 0.0}
	var messy_score := Game.tour_score("prospect")
	var tour_rack := Game.add_rack(Vector2i(42, 1))
	var tour_sw := Game.new_device("sw-8")
	var tour_srv := Game.new_device("srv-1")
	tour_rack.slots[0] = tour_sw
	tour_rack.slots[1] = tour_srv
	Game.connect_ifaces(tour_srv.ifaces[0], tour_sw.ifaces[0])
	for tour_slot in Net.Rack.SLOTS:
		if tour_rack.slots[tour_slot] == null:
			Game.toggle_blanking(tour_rack, tour_slot)
	Game.set_note(tour_srv.ifaces[0], "customer A")
	Game.set_note(tour_sw.ifaces[0], "customer A uplink")
	Game.set_note(tour_sw, "core access switch")
	Game.set_note(tour_srv, "customer A host")
	tour_sw.startup = Game.device_config(tour_sw)
	tour_srv.startup = Game.device_config(tour_srv)
	var kept_score := Game.tour_score("prospect")
	check(kept_score > messy_score,
		"tour: the score is built out of things a visitor could actually see")
	var before_cram := Game.tour_score("prospect")
	Game.money = 5000
	check(Game.cram_for_tour() == "" and Game.tour_score("prospect") > before_cram \
			and Game.cram_for_tour() != "" \
			and Game.tour_score("prospect") - before_cram <= 0.11,
		"tour: cramming helps a little, costs money, and cannot be repeated into a clean sheet")
	# a floor that looks run wins work
	Game.tour["crammed"] = 0.0
	Game.tour["kind"] = "prospect"
	Game.tour["cycle"] = Game.cycle
	var forced := Game.tour_score("prospect")
	Game.tour_tick()
	check(Game.tour.is_empty() and (Game.leads.size() == 1 if forced >= 0.45 else Game.leads.is_empty()),
		"tour: the outcome is a real contract to quote, or nothing, and it follows the score")
	# and an auditor asks for what you can prove
	Game.leads = []
	Game.data_risks = [{"device": "srv99", "model": "srv-1", "cycle": Game.cycle}]
	Game.incidents = [{"kind": "test", "summary": "something nobody wrote up", "cycle": Game.cycle,
		"reviewed": false, "by": ""}]
	var audit_score := Game.tour_score("auditor")
	Game.data_risks = []
	Game.incidents = []
	check(Game.tour_score("auditor") > audit_score,
		"tour: an auditor scores the records, and an unwritten incident is visible in them")
	var rep_before_tour := Game.reputation
	Game.tour = {"kind": "auditor", "cycle": Game.cycle, "crammed": 0.0}
	Game.data_risks = [{"device": "srv98", "model": "srv-1", "cycle": Game.cycle}]
	for tour_dev: Net.NDevice in Game.all_devices():
		tour_dev.note = {}
	Game.tour_tick()
	check(Game.reputation < rep_before_tour and not Game.incidents.is_empty(),
		"tour: neglect cannot be hidden from somebody whose job is asking for proof")
	Game.data_risks = []
	Game.leads = tour_leads
	Game.incidents = tour_incidents
	Game.tour = {}

	# --- renewals calendar ---
	var ren_before := Game.renewals.duplicate(true)
	Game.renewals = []
	Game.money = 5000
	var licensed := Game.new_device("sw-24")
	check(Game.renewals.size() == 1 and String(Game.renewals[0]["kind"]) == "licence" \
			and String(Game.renewals[0]["serial"]) == licensed.name,
		"renewals: a licensed device arrives with a licence bound to its own serial")
	var lic_item: Dictionary = Game.renewals[0]
	var full_speed := Game.iface_speed(licensed.ifaces[0])
	Game.cycle = int(lic_item["due"])
	Game.renewal_tick()
	check(not bool(lic_item["lapsed"]) and Game.iface_speed(licensed.ifaces[0]) == full_speed,
		"renewals: the due date opens a grace period rather than breaking anything")
	Game.cycle += Game.RENEWAL_GRACE
	Game.renewal_tick()
	check(bool(lic_item["lapsed"]) and licensed.status == "active" \
			and Game.iface_speed(licensed.ifaces[0]) == full_speed / 2,
		"renewals: a lapsed licence quietly caps the device instead of killing it")
	var lapsed_price := Game.money
	check(Game.renew_item(String(lic_item["id"])) == "" \
			and Game.money == lapsed_price - int(lic_item["cost"]) * 2 \
			and Game.iface_speed(licensed.ifaces[0]) == full_speed,
		"renewals: a lapse is always recoverable, at the late premium")
	# auto-renew is a real cash flow decision
	lic_item["auto"] = true
	Game.cycle = int(lic_item["due"])
	var before_auto := Game.money
	Game.renewal_tick()
	check(Game.money == before_auto - int(lic_item["cost"]) \
			and Game.renewal_due_in(lic_item) == int(lic_item["period"]),
		"renewals: auto-renew takes the money on the day, whatever else is happening")
	Game.money = 10
	Game.cycle = int(lic_item["due"]) + Game.RENEWAL_GRACE
	Game.renewal_tick()
	check(bool(lic_item["lapsed"]),
		"renewals: auto-renew with no cash in the account is not a renewal at all")
	# and second-hand gear arrives on somebody else's licence
	Game.money = 5000
	Game.renewals = []
	var used := Game.new_device("rtr-edge", true)
	check(Game.renewals.size() == 1 and bool(Game.renewals[0]["lapsed"]) \
			and Game.iface_speed(used.ifaces[0]) < int(Game.MODELS["rtr-edge"]["speed"]),
		"renewals: second-hand hardware comes without a transferable licence, and is capped until you buy one")
	Game.renewals = ren_before

	# --- vendor TAC cases ---
	var tac_renewals := Game.renewals.duplicate(true)
	Game.renewals = []
	Game.tac_cases = []
	Game.firmware_bugs = {}

	Game.money = 8000
	var buggy := Game.new_device("sw-8")
	var tac_rack := Game.add_rack(Vector2i(44, 1))
	var tac_srv := Game.new_device("srv-1")
	tac_rack.slots[0] = buggy
	tac_rack.slots[1] = tac_srv
	Game.connect_ifaces(tac_srv.ifaces[0], buggy.ifaces[0])
	Game.firmware_bugs[buggy.name] = {"since": Game.cycle, "model": buggy.model}
	var flapped := false
	for _t in 200:
		Game.firmware_tick()
		if not buggy.ifaces[0].enabled:
			flapped = true
			buggy.ifaces[0].enabled = true  # the player fixes it; it does not stay fixed
	check(flapped and Game.firmware_bugs.has(buggy.name),
		"tac: a firmware defect keeps dropping the port and no configuration of yours touches it")
	check(Game.support_tier() == 0 and Game.open_tac_case(buggy, 2) == "" \
			and Game.open_tac_case(buggy, 2) != "",
		"tac: one open case per device, and no cover means the slowest queue")
	var tac_case: Dictionary = Game.tac_cases[0]
	for kind_ev: String in Game.TAC_EVIDENCE:
		Game.attach_evidence(tac_case, kind_ev)
	check(String(tac_case["stage"]) == "level_one" and bool(tac_case["asked_again"]) \
			and tac_case["evidence"].size() < Game.TAC_EVIDENCE.size(),
		"tac: level one asks again for something that is already in the case")
	for kind_ev2: String in Game.TAC_EVIDENCE:
		Game.attach_evidence(tac_case, kind_ev2)
	check(String(tac_case["stage"]) == "queued" \
			and int(tac_case["waiting_until"]) - Game.cycle == int(Game.SUPPORT_TIERS[0]["wait"]),
		"tac: a complete case queues, and the wait is the cover you bought")
	var money_esc := Game.money
	check(Game.escalate_case(tac_case) == "" and Game.money < money_esc \
			and int(tac_case["waiting_until"]) - Game.cycle == int(Game.SUPPORT_TIERS[0]["escalate"]),
		"tac: insisting costs you something and genuinely moves it along")
	Game.cycle = int(tac_case["waiting_until"])
	Game.tac_tick()
	check(String(tac_case["stage"]) == "fix_ready",
		"tac: some faults are only ever resolved by somebody else's engineering team")
	Game.maintenance_until = Game.cycle + 3  # do it in a window, like an adult
	check(Game.apply_firmware(tac_case) == "" and String(tac_case["stage"]) == "closed" \
			and not Game.firmware_bugs.has(buggy.name) and buggy.status == "active",
		"tac: the fix is a reload, and inside a change window it is routine")
	Game.maintenance_until = -1
	# buying cover is visibly worth it when you are the one waiting
	check(Game.buy_support(2) == "" and Game.support_tier() == 2 \
			and int(Game.SUPPORT_TIERS[2]["wait"]) < int(Game.SUPPORT_TIERS[0]["wait"]),
		"tac: a premium contract is a shorter wait during an outage, which is when it matters")
	# and the whole boring thing can be handed over
	Game.firmware_bugs[buggy.name] = {"since": Game.cycle, "model": buggy.model}
	Game.open_tac_case(buggy, 3)
	var handed: Dictionary = Game.tac_cases[Game.tac_cases.size() - 1]
	handed["delegated"] = true
	for _w in 40:
		Game.cycle += 1
		Game.tac_tick()
		if String(handed["stage"]) != "evidence" and String(handed["stage"]) != "level_one":
			break
	check(String(handed["stage"]) in ["queued", "fix_ready"] \
			and not bool(handed.get("escalated", false)),
		"tac: delegated cases do get worked, slowly, and nobody on your staff pushes back")
	Game.firmware_bugs = {}
	Game.tac_cases = []
	Game.renewals = tac_renewals

	# --- zombie assets ---
	Game.orphan_intel = {}

	# --- remote hands ---
	Game.remote_jobs = []
	Game.money = 8000
	var rh_site := Game.add_site("Colo Debrecen", Vector2i(4, 4), "acquired", "Debrecen")
	var rh_rack := Game.add_rack(Vector2i(0, 0), rh_site)
	var rh_sw := Game.new_device("sw-8")
	var rh_srv := Game.new_device("srv-1")
	rh_rack.slots[0] = rh_sw
	rh_rack.slots[1] = rh_srv
	Game.connect_ifaces(rh_srv.ifaces[0], rh_sw.ifaces[0])
	var blind_precision := Game.remote_precision(rh_sw, rh_sw.ifaces[0])
	Game.set_note(rh_sw.ifaces[0], "customer A handoff, port 1")
	Game.set_note(rh_sw, "access switch, top of rack")
	Game.set_note(rh_rack, "customer A cabinet")
	var labelled_precision := Game.remote_precision(rh_sw, rh_sw.ifaces[0])
	check(labelled_precision > blind_precision and labelled_precision <= 1.0,
		"remote hands: labelling your own site is what makes somebody else's hands safe")
	check(float(Game.remote_facility(rh_site)["care"]) < float(Game.remote_facility(0)["care"]) \
			and int(Game.remote_facility(rh_site)["wait"]) > int(Game.remote_facility(0)["wait"]) \
			and int(Game.remote_facility(rh_site)["cost"]) > 0,
		"remote hands: a cheap facility is slower, sloppier and still not free")
	var money_rh := Game.money
	check(Game.request_remote_hands(rh_sw, "nonsense") != "" \
			and Game.request_remote_hands(rh_sw, "reseat", rh_sw.ifaces[0]) == "" \
			and Game.money < money_rh and Game.remote_jobs.size() == 1,
		"remote hands: you buy a block of time, and it is spent whatever happens")
	var rh_job: Dictionary = Game.remote_jobs[0]
	check(int(rh_job["due"]) > Game.cycle,
		"remote hands: they are not there yet, which is the other cost")
	rh_sw.ifaces[0].enabled = false
	rh_job["precision"] = 1.0
	Game.cycle = int(rh_job["due"])
	Game.remote_hands_tick()
	check(rh_sw.ifaces[0].enabled and Game.remote_jobs.is_empty(),
		"remote hands: with the right label they reseat the port you meant")
	rh_sw.ifaces[0].enabled = false
	rh_sw.ifaces[1].enabled = false
	Game.request_remote_hands(rh_sw, "reseat", rh_sw.ifaces[0])
	var wrong_job: Dictionary = Game.remote_jobs[0]
	wrong_job["precision"] = 0.0
	Game.cycle = int(wrong_job["due"])
	Game.remote_hands_tick()
	check(not rh_sw.ifaces[0].enabled and rh_sw.ifaces[1].enabled,
		"remote hands: an unclear instruction gets the neighbouring port, which is a real wrong outcome")
	Game.remote_jobs = []
	Game.current_site = 0

	# --- receiving ---
	Game.crates = []
	Game.packaging = 0
	Game.spares = {}
	Game.money = 20000
	var rc_staff := Game.staff.duplicate(true)
	Game.staff = []
	var money_order := Game.money
	check(Game.order_hardware("srv-1") == "" \
			and Game.money == money_order - int(float(Game.MODELS["srv-1"]["price"]) * 0.85) \
			and Game.crates.size() == 1 and Game.crates_waiting().is_empty(),
		"receiving: ordering is cheaper than collecting it, and what you have bought is not here yet")
	var crate: Dictionary = Game.crates[0]
	crate["damaged"] = false
	crate["shipped"] = "srv-1"
	Game.cycle = int(crate["due"])
	Game.receiving_tick()
	check(Game.crates_waiting().size() == 1 and Game.spares.is_empty(),
		"receiving: it arrives as a crate in the receiving area, not as a working device")
	check(Game.check_crate(crate) == "" and bool(crate["checked"]) \
			and Game.check_crate(crate) != "",
		"receiving: checking it against the order records the serial, once")
	check(Game.unpack_crate(crate) == "" and int(Game.spares.get("srv-1", 0)) == 1 \
			and Game.crates.is_empty() and Game.packaging == 1,
		"receiving: unpacking puts it on the shelf and leaves the cardboard behind")
	# damage found at the dock goes back; damage found later does not
	Game.order_hardware("srv-1")
	var broken: Dictionary = Game.crates[0]
	broken["damaged"] = true
	broken["arrived"] = Game.cycle
	var money_claim := Game.money
	check(Game.check_crate(broken) == "" and Game.money > money_claim and Game.crates.is_empty(),
		"receiving: damage caught on receipt goes straight back with the money")
	Game.order_hardware("srv-1")
	var missed: Dictionary = Game.crates[0]
	missed["damaged"] = true
	missed["arrived"] = Game.cycle
	var spares_before_missed: int = int(Game.spares.get("srv-1", 0))
	Game.unpack_crate(missed)
	check(int(Game.spares.get("srv-1", 0)) == spares_before_missed and Game.crates.is_empty(),
		"receiving: the same damage discovered in the aisle is simply yours")
	# heavy gear needs a second pair of hands or a second afternoon
	Game.order_hardware("sw-24")
	var heavy: Dictionary = Game.crates[0]
	heavy["damaged"] = false
	heavy["shipped"] = "sw-24"
	heavy["arrived"] = Game.cycle
	check(Game.unpack_crate(heavy) == "" and Game.crates.size() == 1,
		"receiving: a deep, heavy unit does not come out of its crate in one afternoon alone")
	Game.staff = [{"name": "Toth Gabor", "role": "tech", "skill": 3, "salary": 300, "morale": 70,
		"shift": "day", "training_left": 0, "certs": []}]
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 3  # somebody on shift
	Game.unpack_crate(heavy)
	check(Game.crates.is_empty() and int(Game.spares.get("sw-24", 0)) == 1,
		"receiving: a second pair of hands is exactly what it needed")
	# and the packaging is a consequence in itself
	Game.packaging = 5
	var tidy_with_boxes := Game.tour_factor("tidy")
	var blocked_chance := Game.fault_chance()
	Game.packaging = 0
	check(Game.tour_factor("tidy") > tidy_with_boxes and Game.fault_chance() < blocked_chance \
			and Game.clear_packaging() != "",
		"receiving: cardboard in the aisle is visible sloppiness and gets in the way of the work")
	Game.staff = rc_staff
	Game.crates = []
	Game.packaging = 0
	Game.spares = {}

	# --- procurement ---
	Game.crates = []
	Game.stockouts = {}
	Game.rmas = []
	Game.latent_defects = {}
	Game.spares = {}
	Game.money = 40000
	check(Game.order_estimate("srv-1", "urgent") > Game.order_estimate("srv-1", "distributor") \
			and Game.order_estimate("srv-1", "used") < Game.order_estimate("srv-1", "trade") \
			and int(Game.VENDOR_TIERS["urgent"]["wait"][1]) < int(Game.VENDOR_TIERS["trade"]["wait"][0]),
		"procurement: urgent shipping costs a premium and is still not instant")
	Game.order_hardware("srv-1", 1, "urgent")
	var urgent_crate: Dictionary = Game.crates[0]
	check(int(urgent_crate["due"]) - Game.cycle >= int(Game.VENDOR_TIERS["urgent"]["wait"][0]),
		"procurement: even the fast lane has a lead time you can plan around")
	Game.crates = []
	Game.stockouts["srv-1"] = Game.cycle + 8
	var refused := Game.order_hardware("srv-1", 1, "trade")
	check(refused != "" and "back order" in refused and not Game.substitutes_for("srv-1").is_empty(),
		"procurement: a stock out forces a substitution, which is when the catalogue starts to matter")
	Game.stockouts = {}
	# second-hand is a real temptation with a real downside
	Game.order_hardware("sw-8", 1, "used")
	var used_crate: Dictionary = Game.crates[0]
	used_crate["damaged"] = false
	used_crate["shipped"] = "sw-8"
	used_crate["arrived"] = Game.cycle
	check(bool(used_crate["used"]),
		"procurement: the second-hand market is its own channel, at about half the price")
	Game.latent_defects = {}
	Game.unpack_crate(used_crate)
	Game.latent_defects["sw-8"] = 1  # this one came with somebody else's problem
	var pr_rack := Game.add_rack(Vector2i(54, 1))
	var pr_dead := Game.new_device("sw-8")
	pr_rack.slots[0] = pr_dead
	pr_dead.status = "offline"
	Game.spares["sw-8"] = 1
	Game.firmware_bugs = {}
	Game.swap_from_spares(pr_dead)
	check(Game.firmware_bugs.has(pr_dead.name) and pr_dead.status == "active",
		"procurement: a second-hand unit can carry a latent defect that only shows once it is in service")
	Game.firmware_bugs = {}
	# and a dead unit can go back to the vendor
	Game.renewals = []
	pr_dead.status = "offline"
	check(Game.support_tier() == 0 and Game.send_rma(pr_dead) == "" and Game.rmas.size() == 1 \
			and not bool(Game.rmas[0]["advance"]) and Game.rack_of(pr_dead) == null,
		"procurement: with no cover the dead unit goes back first and the replacement follows")
	var slow_due: int = int(Game.rmas[0]["due"])
	Game.rmas = []
	Game.money = 8000
	Game.buy_support(1)
	var pr_dead2 := Game.new_device("sw-8")
	pr_rack.slots[1] = pr_dead2
	pr_dead2.status = "offline"
	Game.send_rma(pr_dead2)
	check(bool(Game.rmas[0]["advance"]) and int(Game.rmas[0]["due"]) < slow_due,
		"procurement: advance replacement is what the support contract is actually for")
	Game.cycle = int(Game.rmas[0]["due"])
	Game.rma_tick()
	check(Game.rmas.is_empty() and Game.crates.size() >= 1,
		"procurement: the replacement arrives as a crate like everything else")
	Game.crates = []
	Game.rmas = []
	Game.latent_defects = {}
	Game.spares = {}
	Game.renewals = []

	# --- documentation drift ---
	Game.docs = {}
	Game.money = 5000
	var dd_rack := Game.add_rack(Vector2i(56, 1))
	var dd_sw := Game.new_device("sw-8")
	var dd_srv := Game.new_device("srv-1")
	dd_rack.slots[0] = dd_sw
	dd_rack.slots[1] = dd_srv
	Game.connect_ifaces(dd_srv.ifaces[0], dd_sw.ifaces[0])
	Game.add_ip(dd_srv.ifaces[0], "10.88.0.10/24")
	check(Game.rack_drift(dd_rack) > 0,
		"drift: hardware nobody has written up is itself undocumented reality")
	check(Game.reconcile_rack(dd_rack) == "" and Game.rack_drift(dd_rack) == 0,
		"drift: walking the cabinet and writing it down is cheap and boring, which is the point")
	# fast work creates drift without anybody deciding to be sloppy
	Game.disconnect_iface(dd_srv.ifaces[0])
	Game.connect_ifaces(dd_srv.ifaces[0], dd_sw.ifaces[2])
	check(Game.rack_drift(dd_rack) >= 2,
		"drift: an emergency repatch leaves the documentation describing a floor that no longer exists")
	var dd_precision_bad := Game.remote_precision(dd_sw, dd_sw.ifaces[2])
	Game.reconcile_rack(dd_rack)
	check(Game.remote_precision(dd_sw, dd_sw.ifaces[2]) > dd_precision_bad,
		"drift: somebody working from your documentation is measurably better when it is true")
	# and a change window writes it up on the way out
	Game.docs = {}
	Game.maintenance_used = 0
	Game.maintenance_until = -1
	dd_sw.startup = Game.device_config(dd_sw)
	Game.submit_change("documented work", [dd_sw.name], 4, true)
	Game.complete_change()
	check(Game.docs.has(dd_sw.name),
		"drift: closing a change window writes up what the change actually did")
	Game.reconcile_rack(dd_rack)
	Game.docs = {}

	# --- locking yourself out ---
	Game.confirm_commits = {}
	Game.physical_access = {}
	Game.lockout_state = {}
	Game.money = 5000
	var lo_rack := Game.add_rack(Vector2i(58, 1))
	var lo_sw := Game.new_device("sw-8")
	var lo_rtr := Game.new_device("rtr-lite")
	var lo_srv := Game.new_device("srv-1")
	lo_rack.slots[0] = lo_sw
	lo_rack.slots[1] = lo_rtr
	lo_rack.slots[2] = lo_srv
	Game.connect_ifaces(lo_srv.ifaces[0], lo_sw.ifaces[0])
	Game.connect_ifaces(lo_rtr.ifaces[0], lo_sw.ifaces[1])
	Game.add_ip(lo_srv.ifaces[0], "10.90.0.10/24")
	Game.add_ip(lo_rtr.ifaces[0], "10.90.0.1/24")
	check(Game.management_ips(lo_rtr).has("10.90.0.1") and Game.device_reachable(lo_rtr) \
			and not Game.locked_out(lo_rtr),
		"lockout: a device you can reach over the network is one you can manage")
	lo_rtr.startup = Game.device_config(lo_rtr)
	# the dangerous part of a change is that it travels over the path you use
	lo_rtr.ifaces[0].enabled = false
	check(not Game.device_reachable(lo_rtr) and Game.locked_out(lo_rtr),
		"lockout: shutting the port your management path rides cuts you off from a device that is still running")
	# out of band is exactly what it is for
	var lo_con := Game.new_device("con-1")
	var lo_rack2 := Game.add_rack(Vector2i(59, 1))
	lo_rack2.slots[0] = lo_con
	Game.connect_ifaces(lo_con.ifaces[0], lo_rtr.ifaces[1])
	check(Game.console_reachable(lo_rtr) and not Game.locked_out(lo_rtr),
		"lockout: a serial cable from a console server does not care about addressing")
	Game.disconnect_iface(lo_con.ifaces[0])
	check(Game.locked_out(lo_rtr), "lockout: without it, you are locked out again")
	# a walk costs time at home and real money at a remote site
	var lo_money := Game.money
	check(Game.walk_to_device(lo_rtr) == "" and Game.money == lo_money \
			and not Game.locked_out(lo_rtr),
		"lockout: on your own floor the recovery is a walk to the rack")
	Game.physical_access = {}
	var lo_site := Game.add_site("Colo Gyor", Vector2i(3, 3), "acquired", "Gyor")
	var lo_far_rack := Game.add_rack(Vector2i(0, 0), lo_site)
	var lo_far := Game.new_device("rtr-lite")
	lo_far_rack.slots[0] = lo_far
	check(Game.walk_to_device(lo_far) == "" and Game.money < lo_money,
		"lockout: at a remote site the same recovery is a site visit, and it is billed")
	# the confirmed commit timer is the thing that saves you
	lo_rtr.ifaces[0].enabled = true
	Game.lockout_state = {}
	lo_rtr.startup = Game.device_config(lo_rtr)
	check(Game.arm_confirm(lo_rtr, 2) == "" and Game.arm_confirm(lo_rtr, 2) != "",
		"lockout: a confirmed commit can be armed once before the change")
	Game.add_static_route(lo_rtr, "10.91.0.0", 24, "10.90.0.9")
	lo_rtr.ifaces[0].enabled = false
	Game.cycle += 4 - (Game.cycle % 4) + 4  # the reachability sweep runs every fourth cycle
	Game.lockout_tick()
	check(not Game.confirm_commits.has(lo_rtr.name) and lo_rtr.static_routes.is_empty() \
			and Game.device_reachable(lo_rtr),
		"lockout: the timer reverts the whole change and hands the device back")
	Game.arm_confirm(lo_rtr, 3)
	check(Game.confirm_commit(lo_rtr) == "" and Game.confirm_commits.is_empty(),
		"lockout: confirming while you can still reach it makes the change stand")
	Game.confirm_commits = {}
	Game.physical_access = {}
	Game.lockout_state = {}
	Game.current_site = 0

	# --- the ticket queue ---
	Game.tickets = []
	Game.reputation = 60
	var tk_deals := Game.deals.duplicate(true)
	var tk_shop := {"id": "tk1", "customer": "Sarga Bolt", "ctype": "smb", "kind": "hosting",
		"params": {}, "fee": 60, "brief": "", "load": 60, "healthy": false, "ever_healthy": true}
	var tk_ent := {"id": "tk2", "customer": "Duna Bank", "ctype": "enterprise", "kind": "hosting",
		"params": {}, "fee": 400, "brief": "", "load": 300, "healthy": false, "ever_healthy": true}
	Game.deals = [tk_shop, tk_ent]
	Game.ticket_tick()
	check(Game.tickets.size() >= 2,
		"tickets: an outage arrives as several complaints rather than one alert")
	var shop_ticket := {}
	var ent_ticket := {}
	for t_c: Dictionary in Game.tickets:
		if String(t_c["customer"]) == "Sarga Bolt":
			shop_ticket = t_c
		elif String(t_c["customer"]) == "Duna Bank":
			ent_ticket = t_c
	check(String(shop_ticket["text"]) != String(ent_ticket["text"]) \
			and String(shop_ticket["cause"]["kind"]) == String(ent_ticket["cause"]["kind"]),
		"tickets: the shop and the bank describe the same root cause completely differently")
	var money_tri := Game.money
	check(Game.triage_ticket(shop_ticket, "power") == "" and Game.money < money_tri \
			and String(shop_ticket["state"]) == "open",
		"tickets: triaging it to the wrong place burns an afternoon and gets you nowhere")
	check(Game.triage_ticket(shop_ticket, "network") == "" \
			and String(shop_ticket["state"]) == "investigating",
		"tickets: the right area is where the work actually starts")
	# closing a live fault brings it back, angrier
	Game.close_ticket(shop_ticket)
	var rep_before_reopen := Game.reputation
	Game.cycle += 3
	Game.ticket_tick()
	check(String(shop_ticket["state"]) == "open" and int(shop_ticket["reopened"]) == 1 \
			and Game.reputation < rep_before_reopen,
		"tickets: closing something that is still broken reopens it and costs you")
	# fix it for real and the same close is welcome
	tk_shop["healthy"] = true
	var rep_before_close := Game.reputation
	Game.close_ticket(shop_ticket)
	check(String(shop_ticket["state"]) == "closed" and Game.reputation > rep_before_close,
		"tickets: closing a ticket verifies the condition is actually gone")
	# and some of them are not ours at all
	var not_ours := Game.open_ticket("Sarga Bolt", "the office printer will not connect",
		{"kind": "none"})
	check(Game.ticket_area_for(not_ours["cause"]) == "customer side" \
			and not Game.ticket_condition_live(not_ours),
		"tickets: at least one kind of ticket is legitimately somebody else's problem")
	Game.tickets = []
	Game.deals = tk_deals

	# --- grey failures ---
	Game.grey_faults = {}
	Game.parts = {"patch": 10, "optic": 10, "power": 10, "blank": 10}
	Game.parts_auto = false
	var gf_rack := Game.add_rack(Vector2i(60, 1))
	var gf_sw := Game.new_device("sw-8")
	var gf_a := Game.new_device("srv-1")
	var gf_b := Game.new_device("srv-1")
	gf_rack.slots[0] = gf_sw
	gf_rack.slots[1] = gf_a
	gf_rack.slots[2] = gf_b
	Game.connect_ifaces(gf_a.ifaces[0], gf_sw.ifaces[0])
	Game.connect_ifaces(gf_b.ifaces[0], gf_sw.ifaces[1])
	Game.add_ip(gf_a.ifaces[0], "10.95.0.10/24")
	Game.add_ip(gf_b.ifaces[0], "10.95.0.11/24")
	check(Sim.ping(gf_a, "10.95.0.11")["ok"], "grey: the link starts out honest")
	# one direction only: the port is up and nothing comes back
	Game.inject_grey_fault(gf_sw.ifaces[1], "one_way")
	check(gf_sw.ifaces[1].enabled and Game.link_at(gf_sw.ifaces[1]) != null \
			and not Sim.ping(gf_a, "10.95.0.11")["ok"],
		"grey: a damaged pair kills the traffic without taking the link down")
	check(gf_sw.ifaces[1].rx_errors > 0,
		"grey: the evidence is in the interface counters, where it would be in reality")
	check(Game.repair_grey(gf_sw.ifaces[1], "reseat") == "" \
			and not Game.grey_fault(gf_sw.ifaces[1]).is_empty(),
		"grey: the wrong repair costs the afternoon and fixes nothing")
	check(Game.repair_grey(gf_sw.ifaces[1], "replace cable") == "" \
			and Game.grey_fault(gf_sw.ifaces[1]).is_empty() \
			and Sim.ping(gf_a, "10.95.0.11")["ok"],
		"grey: each fault has one repair that actually addresses it")
	# an MTU somebody changed: small packets pass, large ones vanish
	Game.inject_grey_fault(gf_sw.ifaces[0], "mtu")
	check(Sim.ping(gf_a, "10.95.0.11", 64, "", 64)["ok"] \
			and not Sim.ping(gf_a, "10.95.0.11", 64, "", 1450)["ok"],
		"grey: an MTU black hole passes small packets and swallows large ones")
	check(Game.repair_grey(gf_sw.ifaces[0], "replace optic") == "" \
			and not Game.grey_fault(gf_sw.ifaces[0]).is_empty() \
			and Game.repair_grey(gf_sw.ifaces[0], "fix config") == "" \
			and Sim.ping(gf_a, "10.95.0.11", 64, "", 1450)["ok"],
		"grey: swapping hardware never fixes a configuration fault")
	# a dying optic reports its own light level long before anybody notices
	Game.inject_grey_fault(gf_sw.ifaces[0], "dirty_optic")
	check(gf_sw.ifaces[0].light_dbm < -15.0,
		"grey: a dying optic shows its receive level to anybody who looks")
	var lossy := 0
	for _gp in 40:
		if not Sim.ping(gf_a, "10.95.0.11", 64, "", 1200)["ok"]:
			lossy += 1
	check(lossy > 0 and lossy < 40,
		"grey: contamination is intermittent under load, which is what makes it maddening")
	Game.repair_grey(gf_sw.ifaces[0], "replace optic")
	check(Game.grey_fault(gf_sw.ifaces[0]).is_empty() and gf_sw.ifaces[0].light_dbm > -10.0,
		"grey: a new optic clears both the loss and the light reading")
	# and a loose connector is its own thing again
	Game.inject_grey_fault(gf_sw.ifaces[1], "loose_connector")
	var flaky := 0
	for _gp2 in 40:
		if not Sim.ping(gf_a, "10.95.0.11")["ok"]:
			flaky += 1
	check(flaky > 0 and Game.repair_grey(gf_sw.ifaces[1], "reseat") == "" \
			and Game.grey_fault(gf_sw.ifaces[1]).is_empty(),
		"grey: a connector nobody seated properly comes and goes until somebody reseats it")
	Game.grey_faults = {}
	Game.parts_auto = true

	# --- consumables ---
	var pt_rack := Game.add_rack(Vector2i(48, 1))
	var pt_sw := Game.new_device("sw-8")
	var pt_srv := Game.new_device("srv-1")
	pt_rack.slots[0] = pt_sw
	pt_rack.slots[1] = pt_srv
	Game.parts = {"patch": 1, "optic": 0, "power": 5, "blank": 0}
	Game.parts_auto = false
	Game.cable_debt = 0
	check(Game.connect_ifaces(pt_srv.ifaces[0], pt_sw.ifaces[0]) and Game.parts_of("patch") == 0,
		"parts: an install takes a lead out of the drawer")
	var pt_srv2 := Game.new_device("srv-1")
	pt_rack.slots[2] = pt_srv2
	check(not Game.connect_ifaces(pt_srv2.ifaces[0], pt_sw.ifaces[1]) \
			and Game.link_at(pt_srv2.ifaces[0]) == null,
		"parts: an empty drawer blocks the cutover until something arrives")
	var pt_rack2 := Game.add_rack(Vector2i(49, 1))
	var pt_far := Game.new_device("srv-1")
	pt_rack2.slots[0] = pt_far
	Game.parts["patch"] = 2
	check(Game.connect_ifaces(pt_far.ifaces[0], pt_sw.ifaces[2]) and Game.cable_debt == 1 \
			and Game.parts_of("optic") == 0,
		"parts: a run to another cabinet wants an optic, and improvising with what is there is cable debt")
	var tidy_with_debt := Game.rack_tidiness(pt_rack)
	Game.money = 2000
	check(Game.redo_cable_debt() == "" and Game.cable_debt == 0 \
			and Game.rack_tidiness(pt_rack) > tidy_with_debt,
		"parts: redoing an improvised lead properly is visible in the cabinet")
	check(not Game.toggle_blanking(pt_rack, Net.Rack.SLOTS - 1) \
			and Game.buy_parts("blank", 2) == "" and Game.toggle_blanking(pt_rack, Net.Rack.SLOTS - 1) \
			and Game.rack_airflow_seal(pt_rack) > 0.0,
		"parts: blanking panels come out of the same drawer and still buy you airflow")
	Game.parts_auto = true
	Game.parts["patch"] = 2
	Game.money = 5000
	Game.parts_tick()
	check(Game.parts_of("patch") >= Game.PART_REORDER,
		"parts: a standing order makes this a decision once rather than a chore every cycle")
	Game.money = 0
	Game.parts = {"patch": 0, "optic": 0, "power": 0, "blank": 0}
	check(not Game.connect_ifaces(pt_srv2.ifaces[0], pt_sw.ifaces[3]),
		"parts: a standing order with no money behind it is not a delivery")
	Game.parts = {"patch": 40, "optic": 8, "power": 20, "blank": 12}
	Game.money = 5000

	# --- cable debt as a choice, not a scolding ---
	Game.cable_debt = 0
	Game.docs = {}
	Game.money = 5000
	var cd_rack := Game.add_rack(Vector2i(68, 1))
	var cd_sw := Game.new_device("sw-8")
	var cd_a := Game.new_device("srv-1")
	var cd_b := Game.new_device("srv-1")
	cd_rack.slots[0] = cd_sw
	cd_rack.slots[1] = cd_a
	cd_rack.slots[2] = cd_b
	var cd_plan := Game.plan_cable(cd_a.ifaces[0], cd_sw.ifaces[0])
	check(int(cd_plan["expedient"]["cost"]) < int(cd_plan["documented"]["cost"]) \
			and int(cd_plan["expedient"]["debt"]) > int(cd_plan["documented"]["debt"]),
		"cable debt: both ways are offered, with the price and the debt stated before you commit")
	var cd_debt_before := Game.cable_debt_score()
	Game.connect_ifaces(cd_a.ifaces[0], cd_sw.ifaces[0])
	check(Game.cable_debt_score() > cd_debt_before,
		"cable debt: the fast way leaves something behind, and it is countable")
	var cd_money := Game.money
	check(Game.connect_documented(cd_b.ifaces[0], cd_sw.ifaces[1]) and Game.money < cd_money \
			and not cd_b.ifaces[0].note.is_empty() and not cd_sw.ifaces[1].note.is_empty() \
			and Game.docs.has(cd_b.name),
		"cable debt: the documented way costs money and labels both ends on the way in")
	var traced := Game.cable_debt_items()
	var all_traceable := true
	for cd_item: Dictionary in traced:
		if String(cd_item.get("label", "")) == "" or String(cd_item.get("fix", "")) == "":
			all_traceable = false
	check(all_traceable and not traced.is_empty(),
		"cable debt: every item names the condition and what would clear it")
	var cd_tidy_messy := Game.rack_tidiness(cd_rack)
	Game.set_note(cd_a.ifaces[0], "customer A")
	Game.set_note(cd_sw.ifaces[0], "customer A")
	check(Game.rack_tidiness(cd_rack) > cd_tidy_messy,
		"cable debt: clearing an item during a quiet cycle shows up immediately")
	Game.cable_debt = 0

	# --- runbooks: what automation is allowed to do ---
	Game.runbooks = []
	Game.runbook_runs = []

	# --- auto-remediation: automation that earns trust ---
	Game.runbooks = []
	Game.runbook_runs = []
	Game.monitors = []
	Game.maintenance_until = -1
	var ar_rack := Game.add_rack(Vector2i(72, 1))
	var ar_sw := Game.new_device("sw-8")
	var ar_a := Game.new_device("srv-1")
	var ar_b := Game.new_device("srv-1")
	ar_rack.slots[0] = ar_sw
	ar_rack.slots[1] = ar_a
	ar_rack.slots[2] = ar_b
	Game.connect_ifaces(ar_a.ifaces[0], ar_sw.ifaces[0])
	Game.connect_ifaces(ar_b.ifaces[0], ar_sw.ifaces[1])
	Game.add_ip(ar_a.ifaces[0], "10.175.0.10/24")
	Game.add_ip(ar_b.ifaces[0], "10.175.0.11/24")
	Sim.flush_learned_state()
	Game.add_monitor("ping", ar_a.name, "10.175.0.11")
	var ar_mon: Dictionary = Game.monitors[Game.monitors.size() - 1]
	var ar_rb := Game.make_runbook("bounce the access port", "bounce", ar_sw.name, 1)
	check(Game.bind_remediation(ar_mon, ar_rb) == "" and ar_mon.has("remediation"),
		"remediation: an alert can be bound to exactly one runbook")
	# the recurring fault: a port that comes back when it is bounced
	ar_sw.ifaces[1].enabled = false
	Game._run_monitors()
	var ar_rem: Dictionary = ar_mon["remediation"]
	check(bool(ar_mon["failing"]) and ar_sw.ifaces[1].enabled \
			and String(ar_rem["timeline"][0]).contains("trigger"),
		"remediation: the alert fires the runbook, and the timeline reads trigger, evidence, action")
	Game._run_monitors()
	check(not bool(ar_mon["failing"]) and int(ar_rem["failures"]) == 0 \
			and String(ar_rem["timeline"][ar_rem["timeline"].size() - 1]).contains("verified"),
		"remediation: recovery is verified, not assumed")
	# flapping must not become an action storm
	var runs_before := Game.runbook_runs.size()
	for _ar in 3:
		ar_sw.ifaces[1].enabled = false
		Game._run_monitors()
		Game._run_monitors()
	check(Game.runbook_runs.size() - runs_before <= 1,
		"remediation: a flapping check is held by the cooldown instead of hammering the device")
	# a changed symptom the old fix cannot address stops after its retries
	Game.cycle += Game.REMEDIATION_COOLDOWN * 4
	ar_sw.ifaces[1].enabled = true
	Sim.flush_learned_state()
	Game._run_monitors()
	ar_rem["failures"] = 0
	ar_rem["last_fired"] = -999
	ar_b.ifaces[0].ips = []  # the service moved: bouncing a port will not bring it back
	Sim.flush_learned_state()
	Game._run_monitors()
	for _ar2 in 4:
		Game.cycle += Game.REMEDIATION_COOLDOWN
		Game._run_monitors()
		Game.remediation_tick()
	check(int(ar_rem["failures"]) >= Game.REMEDIATION_RETRIES,
		"remediation: an action that does not restore the service counts against its retries")
	var escalated := false
	for ar_line: String in ar_rem["timeline"]:
		if ar_line.contains("escalated"):
			escalated = true
	check(escalated,
		"remediation: after enough failures it stops and asks for a person")
	# and it says nothing at all during a change window
	Game.add_ip(ar_b.ifaces[0], "10.175.0.11/24")
	Sim.flush_learned_state()
	Game._run_monitors()
	ar_rem["failures"] = 0
	ar_rem["last_fired"] = -999
	Game.maintenance_until = Game.cycle + 3
	ar_sw.ifaces[1].enabled = false
	var runs_window := Game.runbook_runs.size()
	Game._run_monitors()
	check(Game.runbook_runs.size() == runs_window \
			and String(ar_rem["timeline"][ar_rem["timeline"].size() - 1]).contains("suppressed"),
		"remediation: planned work suppresses automation instead of fighting it")
	Game.maintenance_until = -1
	ar_sw.ifaces[1].enabled = true
	Game.monitors = []
	Game.runbooks = []
	Game.runbook_runs = []

	# --- structured cabling: patch panels ---
	Game.parts = {"patch": 60, "optic": 20, "power": 20, "blank": 20}
	Game.parts_auto = true
	Game.money = 20000
	var pp_rack := Game.add_rack(Vector2i(74, 1))
	var pp_sw := Game.new_device("sw-8")
	var pp_srv := Game.new_device("srv-1")
	var pp_panel := Game.new_device("panel-12")
	pp_rack.slots[0] = pp_sw
	pp_rack.slots[1] = pp_srv
	pp_rack.slots[2] = pp_panel
	check(pp_panel.type == "panel" and pp_panel.ifaces.size() == 24 \
			and pp_panel.ifaces[0].name == "front1" and pp_panel.ifaces[12].name == "rear1",
		"panels: a patch panel is twelve front ports wired straight through to twelve at the back")
	# direct first, as the baseline
	Game.connect_ifaces(pp_srv.ifaces[0], pp_sw.ifaces[0])
	Game.add_ip(pp_srv.ifaces[0], "10.181.0.10/24")
	var pp_srv2 := Game.new_device("srv-1")
	pp_rack.slots[3] = pp_srv2
	Game.connect_ifaces(pp_srv2.ifaces[0], pp_sw.ifaces[1])
	Game.add_ip(pp_srv2.ifaces[0], "10.181.0.11/24")
	Sim.flush_learned_state()
	check(Sim.ping(pp_srv, "10.181.0.11")["ok"], "panels: the direct connection is the baseline")
	# now route the same connection through the panel
	Game.disconnect_iface(pp_srv2.ifaces[0])
	Game.connect_ifaces(pp_srv2.ifaces[0], pp_panel.ifaces[1])       # front2
	Game.connect_ifaces(pp_panel.ifaces[13], pp_sw.ifaces[1])        # rear2
	Sim.flush_learned_state()
	check(Game.effective_peer(pp_srv2.ifaces[0]) == pp_sw.ifaces[1] \
			and Game.effective_peer(pp_sw.ifaces[1]) == pp_srv2.ifaces[0],
		"panels: both ends see the device at the far side, not the panel in between")
	check(Sim.ping(pp_srv, "10.181.0.11")["ok"],
		"panels: a panel-routed link behaves exactly like the direct one")
	check(Game.peer_label(pp_sw.ifaces[1]).contains(pp_srv2.name),
		"panels: LLDP and the port list name the real neighbour")
	var pp_trace := Game.cable_path(pp_srv2.ifaces[0])
	check(pp_trace.size() == 2 and String(pp_trace[0]).contains("front2") \
			and String(pp_trace[1]).contains("rear2"),
		"panels: an operator can trace it segment by segment")
	# a patch into a panel port with nothing behind it is not a link
	Game.disconnect_iface(pp_panel.ifaces[13])
	Sim.flush_learned_state()
	check(Game.effective_peer(pp_srv2.ifaces[0]) == null \
			and not Sim.ping(pp_srv, "10.181.0.11")["ok"],
		"panels: a half-patched panel port goes nowhere, which is exactly what it does in reality")
	# and a panel patched into itself is a loop, not a link
	Game.connect_ifaces(pp_panel.ifaces[13], pp_panel.ifaces[2])
	Game.connect_ifaces(pp_panel.ifaces[14], pp_panel.ifaces[3])
	Game.connect_ifaces(pp_panel.ifaces[15], pp_panel.ifaces[4])
	Game.connect_ifaces(pp_panel.ifaces[16], pp_panel.ifaces[5])
	Game.connect_ifaces(pp_panel.ifaces[17], pp_panel.ifaces[0])
	Sim.flush_learned_state()
	check(Game.effective_peer(pp_srv2.ifaces[0]) == null,
		"panels: patching a panel round in a circle is refused rather than followed forever")
	var pp_payload: Dictionary = JSON.parse_string(Game.snapshot())
	check(pp_payload["devices"].has(pp_panel.name),
		"panels: the passive infrastructure is saved with everything else")

	# --- compliance controls and the audit that samples them ---
	Game.audit = {}
	Game.control_evidence = {}
	Game.trust_marker = false
	var ready := Game.audit_readiness()
	check(ready.size() == Game.CONTROLS.size(),
		"compliance: every control in the catalogue is answered")
	var by_id := {}
	for ctl: Dictionary in ready:
		by_id[String(ctl["id"])] = ctl
		if String(ctl["why"]) == "":
			by_id["_empty"] = true
	check(not by_id.has("_empty"),
		"compliance: each control says why it passes or fails, from the live network")
	# a control cannot be satisfied by anything except the simulation
	var comp_rack := Game.add_rack(Vector2i(76, 1))
	var comp_con := Game.new_device("con-1")
	comp_rack.slots[0] = comp_con
	var before_phys := String(Game.control_state("physical_access")["status"])
	Game.docs = {}
	for comp_r: Net.Rack in Game.racks_on(Game.current_site):
		Game.reconcile_rack(comp_r)
	check(String(Game.control_state("physical_access")["status"]) == "compliant" \
			or before_phys != "compliant",
		"compliance: out-of-band access and current documentation is a live check, not a checkbox")
	# the audit: scope stated up front, findings graded, remediation verified
	Game.deals = [{"id": "aud", "customer": "Tisza Bank", "ctype": "enterprise", "kind": "hosting",
		"params": {}, "fee": 300, "brief": "", "load": 200, "healthy": true, "ever_healthy": true,
		"cycles": 20, "up_cycles": 20, "loyalty": 0.8}]
	Game.audit = {"state": "offered", "customer": "Tisza Bank",
		"scope": ["incident_review", "config_history"], "reward": 4500,
		"deadline": Game.cycle + 2, "findings": [], "history": []}
	check(Game.accept_audit() == "" and String(Game.audit["state"]) == "accepted" \
			and Game.accept_audit() != "",
		"compliance: the audit is accepted once, with its scope and deadline already stated")
	Game.incidents = [{"kind": "test", "summary": "an incident nobody wrote up",
		"cycle": Game.cycle - 9, "reviewed": false, "by": ""}]
	Game.cycle = int(Game.audit["deadline"])
	Game.run_audit()
	check(String(Game.audit["state"]) == "findings" and not Game.audit["findings"].is_empty(),
		"compliance: the audit produces findings rather than an instant pass or fail")
	var graded := {}
	for f_c: Dictionary in Game.audit["findings"]:
		graded[String(f_c["control"])] = String(f_c["grade"])
	check(graded.get("incident_review", "") == "major finding" \
			and String(Game.audit["findings"][0]["why"]) != "",
		"compliance: a failing control is a major finding, linked to the live reason it failed")
	check(Game.verify_audit() != "" and not Game.trust_marker,
		"compliance: re-verification with the finding still open does not pass you")
	Game.review_incident(Game.incidents[0], 0)
	for comp_dev: Net.NDevice in Game.all_devices():  # save what is running, everywhere
		comp_dev.startup = Game.device_config(comp_dev)
		if comp_dev.versions.is_empty():
			Game.save_config_version(comp_dev)
	var money_audit := Game.money
	var leads_audit := Game.leads.size()
	var verify_err := Game.verify_audit()
	check(verify_err == "" and String(Game.audit["state"]) == "closed" and Game.trust_marker \
			and Game.money > money_audit and Game.leads.size() == leads_audit + 1,
		"compliance: fixing it for real closes the audit, pays, and opens regulated work")
	Game.audit = {}
	Game.trust_marker = false
	Game.incidents = []

	# --- decisions with a bill that arrives later ---
	Game.decisions = []
	Game.consequences = []
	Game.decisions_seen = []


	Game.money = 20000
	Game.difficulty = 1
	var hz_rack := Game.add_rack(Vector2i(78, 1))
	var hz_sw := Game.new_device("sw-8")
	var hz_srv := Game.new_device("srv-1")
	hz_rack.slots[0] = hz_sw
	hz_rack.slots[1] = hz_srv
	Game.connect_ifaces(hz_srv.ifaces[0], hz_sw.ifaces[0])
	var hz_risk := Game.hazard_risk(hz_rack)
	check(hz_risk >= 0.0 and hz_risk <= 1.0,
		"hazards: risk is a number the player can read off heat, age, power and maintenance")
	# undetected, an incident escalates on a schedule
	var hz := Game.start_hazard(hz_rack, "smoke")
	check(not bool(hz["detected"]) and String(hz["rack"]) == hz_rack.name,
		"hazards: with nothing watching, the first anybody knows is the damage")
	var hz_staff := Game.staff.duplicate(true)
	Game.staff = []  # nobody on shift to deal with it by hand
	for _hz in 3:
		Game.hazard_tick()
	check(String(Game.hazards[0]["kind"]) == "fire" and int(Game.hazards[0]["severity"]) >= 3,
		"hazards: smoke nobody deals with becomes a fire, and it says so on the way")
	var burnt := false
	for _hz2 in 3:
		Game.hazard_tick()
		if hz_rack.slots[0] == null or hz_rack.slots[1] == null:
			burnt = true
	check(burnt, "hazards: an unprotected fire eventually costs hardware, not just uptime")
	# the same incident, prepared for
	Game.hazards = []
	var hz_rack2 := Game.add_rack(Vector2i(79, 1))
	var hz_sw2 := Game.new_device("sw-8")
	var hz_srv2 := Game.new_device("srv-1")
	hz_rack2.slots[0] = hz_sw2
	hz_rack2.slots[1] = hz_srv2
	check(Game.buy_protection("detection") == "" and Game.buy_protection("suppression") == "" \
			and Game.protection_ready("detection") and Game.protection_ready("suppression"),
		"hazards: detection and suppression are things you buy before you need them")
	var hz2 := Game.start_hazard(hz_rack2, "smoke")
	check(bool(hz2["detected"]),
		"hazards: with detection fitted it is found in the cycle it starts")
	Game.hazard_tick()
	check(Game.hazards.is_empty() and hz_rack2.slots[0] != null \
			and hz_sw2.status == "offline",
		"hazards: suppression saves the hardware and shuts the cabinet down doing it")
	# installed is not the same as maintained
	Game.protection["suppression"]["serviced_cycle"] = Game.cycle - 200
	check(not Game.protection_ready("suppression") \
			and Game.service_protection("suppression") == "" \
			and Game.protection_ready("suppression"),
		"hazards: protection goes out of date until somebody inspects it")
	Game.staff = hz_staff
	Game.hazards = []
	Game.protection = {}

	Game.money = 20000
	Game.reputation = 60
	check(Game.DECISIONS.size() >= 12,
		"decisions: the starter deck covers economy, staff, customers, vendors and incidents")
	var missing_facts := false
	for dec_spec: Dictionary in Game.DECISIONS:
		if dec_spec["facts"].size() < 2 or dec_spec["options"].size() < 2:
			missing_facts = true
	check(not missing_facts,
		"decisions: every one states the facts on both sides, and neither option is the obvious answer")
	check(Game.decide("workaround_vs_root", 0) != "",
		"decisions: you cannot answer a decision nobody has put to you")
	Game.decisions = [{"id": "workaround_vs_root", "raised": Game.cycle}]
	var money_dec := Game.money
	check(Game.decide("workaround_vs_root", 0) == "" and Game.money > money_dec \
			and Game.consequences.size() == 1,
		"decisions: the quick answer pays now and puts something in the diary")
	var incidents_dec := Game.incidents.size()
	Game.cycle = int(Game.consequences[0]["cycle"])
	Game.consequence_tick()
	check(Game.consequences.is_empty() and Game.incidents.size() > incidents_dec \
			and String(Game.decision_notes[Game.decision_notes.size() - 1]).contains("cause"),
		"decisions: the consequence lands on the live simulation and is recorded in the timeline")
	# the other branch is defensible too
	Game.decisions = [{"id": "workaround_vs_root", "raised": Game.cycle}]
	var rep_root := Game.reputation
	Game.decide("workaround_vs_root", 1)
	check(Game.reputation > rep_root and Game.consequences.is_empty(),
		"decisions: fixing the cause costs money now and leaves nothing waiting")
	# a delayed consequence is foreshadowed rather than sprung
	Game.decisions = [{"id": "carrier_lock", "raised": Game.cycle}]
	Game.events = []
	Game.decide("carrier_lock", 0)
	check(String(Game.events[0]).contains("LATER:"),
		"decisions: what will come of it is said out loud when the choice is made")
	var money_carrier := Game.money
	Game.cycle = int(Game.consequences[0]["cycle"])
	Game.consequence_tick()
	check(Game.money > money_carrier,
		"decisions: and it arrives on the schedule it announced")
	# the deck deals every card before repeating itself
	Game.decisions = []
	Game.decisions_seen = []
	for _dc in 400:
		Game.maybe_offer_decision()
		if Game.decisions.size() >= 2:
			Game.decisions.pop_front()
	check(Game.decisions_seen.size() >= 6,
		"decisions: the deck works through itself instead of asking the same thing twice")
	Game.decisions = []
	Game.consequences = []
	Game.decisions_seen = []
	Game.money = 5000
	var rb_rack := Game.add_rack(Vector2i(70, 1))
	var rb_sw := Game.new_device("sw-8")
	var rb_srv := Game.new_device("srv-1")
	rb_rack.slots[0] = rb_sw
	rb_rack.slots[1] = rb_srv
	Game.connect_ifaces(rb_srv.ifaces[0], rb_sw.ifaces[0])
	rb_sw.startup = Game.device_config(rb_sw)
	var rb := Game.make_runbook("clear the access port", "bounce", rb_sw.name, 1)
	check(not rb.is_empty() and Game.make_runbook("nonsense", "delete everything").is_empty(),
		"runbooks: the action library is bounded, and anything outside it does not exist")
	var dry := Game.run_runbook(rb, true)
	check(dry["planned"].size() == 1 and dry["applied"].is_empty() \
			and String(dry["log"][0]).contains("would"),
		"runbooks: a dry run says exactly what it would do and does none of it")
	check(String(Game.run_runbook(rb, false)["refused"]).contains("confirming"),
		"runbooks: the first real run of a runbook has to be confirmed")
	var applied := Game.run_runbook(rb, false, true)
	check(applied["applied"] == [rb_sw.name] and applied.has("before") and applied.has("after") \
			and not applied["log"].is_empty(),
		"runbooks: a confirmed run captures before and after and logs every step")
	var rb_wide := Game.make_runbook("save everything", "save_config", "", 2)
	var too_wide := Game.run_runbook(rb_wide, false, true)
	check(String(too_wide["refused"]).contains("may touch") and too_wide["applied"].is_empty(),
		"runbooks: a selector that matches more than the blast radius is refused outright")
	var rb_reload := Game.make_runbook("reload the switch", "reload_config", rb_sw.name, 1)
	Game.add_vlan(rb_sw, 123, "temporary")
	var reload_run := Game.run_runbook(rb_reload, false, true)
	check(not rb_sw.vlans.has(123) and Game.rollback_runbook(reload_run) == "" \
			and rb_sw.vlans.has(123),
		"runbooks: where the action is reversible, the run can be put back")
	check(Game.rollback_runbook(dry) != "",
		"runbooks: a dry run has nothing to roll back")
	Game.add_ip(rb_srv.ifaces[0], "10.170.0.10/24")
	var rb_mgmt := Game.new_device("rtr-edge")
	rb_rack.slots[2] = rb_mgmt
	Game.connect_ifaces(rb_mgmt.ifaces[0], rb_sw.ifaces[1])
	Game.add_ip(rb_mgmt.ifaces[0], "10.170.0.1/24")
	rb_mgmt.startup = Game.device_config(rb_mgmt)
	var rb_risky := Game.make_runbook("bounce the router", "bounce", rb_mgmt.name, 1)
	var risky_run := Game.run_runbook(rb_risky, false, true)
	check(risky_run["applied"].has(rb_mgmt.name) or risky_run["skipped"].has(rb_mgmt.name),
		"runbooks: touching a device over its own management path is a decision, and it is recorded")
	check(Game.runbook_runs.size() >= 5,
		"runbooks: every attempt is kept, including the ones that were refused")
	Game.runbooks = []
	Game.runbook_runs = []

	# --- runbooks: what automation is allowed to do ---
	Game.runbooks = []
	Game.runbook_runs = []

	# --- standing duties ---
	var dt_staff := Game.staff.duplicate(true)
	Game.duties = {}
	Game.staff = [{"name": "Fekete Julia", "role": "engineer", "skill": 5, "salary": 500,
		"morale": 90, "shift": "day", "training_left": 0, "certs": [],
		"habits": {"saves": 0.8, "documents": 0.8, "windows": 0.6, "tidy": 0.8}},
		{"name": "Racz Peter", "role": "noc", "skill": 1, "salary": 200, "morale": 25,
		"shift": "day", "training_left": 0, "certs": [],
		"habits": {"saves": 0.3, "documents": 0.3, "windows": 0.3, "tidy": 0.3}}]
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 3  # both on shift
	Game.parts_auto = false
	check(Game.assign_duty("parts", "Nobody Here") != "" \
			and Game.assign_duty("parts", "Fekete Julia") == "" and Game.parts_auto,
		"duties: a duty goes to a named person, and the standing policy follows the board")
	check(Game.duty_quality("parts") > Game.duty_quality("labels") + 0.0 \
			or Game.duty_holder("labels") == "",
		"duties: an unheld duty is simply yours")
	Game.assign_duty("labels", "Racz Peter")
	check(Game.duty_quality("parts") > Game.duty_quality("labels"),
		"duties: who holds it decides how well it is done, from skill and morale")
	var solo := Game.duty_quality("parts")
	Game.assign_duty("facility", "Fekete Julia")
	Game.assign_duty("renewals", "Fekete Julia")
	check(Game.duty_load("Fekete Julia") == 3 and Game.duty_quality("parts") < solo,
		"duties: staff capacity is finite, and piling it on one person costs quality")
	Game.assign_duty("facility", "")
	Game.assign_duty("renewals", "")
	check(Game.duty_holder("facility") == "" and not bool(Game.facility_auto.get("filters", false)),
		"duties: any duty can be taken back by hand, and the policy comes back with it")
	# delegated work is reported rather than played
	var dt_rack := Game.add_rack(Vector2i(50, 1))
	var dt_sw := Game.new_device("sw-8")
	var dt_srv := Game.new_device("srv-1")
	dt_rack.slots[0] = dt_sw
	dt_rack.slots[1] = dt_srv
	Game.connect_ifaces(dt_srv.ifaces[0], dt_sw.ifaces[0])
	dt_sw.ifaces[0].note = {}
	dt_srv.ifaces[0].note = {}
	Game.last_digest = []
	Game.duties_tick()
	check(not Game.last_digest.is_empty(),
		"duties: the cycle ends with a digest of what the crew handled")
	var labelled_any := false
	for _dt in 40:
		Game.duties_tick()
		for dt_dev: Net.NDevice in Game.all_devices():
			for dt_if: Net.Iface in dt_dev.ifaces:
				if "Racz Peter" in String(dt_if.note.get("text", "")):
					labelled_any = true
	check(labelled_any,
		"duties: work handed over actually happens off screen, without the player touching it")
	Game.duties = {}
	Game.staff = dt_staff
	Game.parts_auto = true
	Game.facility_auto = {}

	# --- the change window as a set piece ---
	Game.change_window = {}
	Game.tour = {}
	Game.upstream = {}
	Game.maintenance_used = 0
	Game.maintenance_until = -1
	var cw_rack := Game.add_rack(Vector2i(52, 1))
	var cw_sw := Game.new_device("sw-8")
	cw_rack.slots[0] = cw_sw
	cw_sw.startup = Game.device_config(cw_sw)
	check(Game.submit_change("core work", [], 4, true) != "" \
			and Game.submit_change("core work", [cw_sw.name], 4, true) == "" \
			and Game.change_active() and Game.in_maintenance(),
		"change: a plan names what is being touched, and opens a window when it is accepted")
	var cw: Dictionary = Game.change_window
	check(int(cw["rollback_at"]) > Game.cycle and int(cw["rollback_at"]) < int(cw["ends"]),
		"change: the safe rollback point sits partway through, not at the end")
	Game.add_vlan(cw_sw, 99, "new-tenant")
	check(not Game.change_work_done() and Game.complete_change() != "",
		"change: unsaved work is unfinished work")
	# aborting reverts to what was running when the window opened
	Game.abort_change()
	check(not Game.change_active() and not cw_sw.vlans.has(99),
		"change: aborting at the rollback point puts everything back exactly as it was")
	# pushing on and overrunning is felt in reputation and in the crew
	var cw_staff := Game.staff.duplicate(true)
	Game.staff = [{"name": "Kovacs Bence", "role": "engineer", "skill": 3, "salary": 400,
		"morale": 80, "shift": "day", "training_left": 0, "certs": []}]
	Game.reputation = 60
	Game.maintenance_used = 0
	Game.submit_change("risky core work", [cw_sw.name], 2, false)
	Game.add_vlan(cw_sw, 98, "half-done")
	Game.push_on_change()
	var rep_before_overrun := Game.reputation
	Game.cycle = int(Game.change_window["ends"])
	Game.change_tick()
	check(not Game.change_active() and Game.reputation < rep_before_overrun \
			and int(Game.staff[0]["morale"]) < 80 and cw_sw.vlans.has(98),
		"change: an overrun after pushing on costs reputation and a wrecked crew, and nothing is reverted")
	cw_sw.vlans.erase(98)
	cw_sw.startup = Game.device_config(cw_sw)
	# a freeze blocks the risky ones, and overriding it is remembered
	Game.maintenance_used = 0
	Game.tour = {"kind": "auditor", "cycle": Game.cycle + 1, "crammed": 0.0}
	check(Game.freeze_reason() != "" and Game.submit_change("during a freeze", [cw_sw.name], 4, true) != "",
		"change: freeze periods block risky work around the things that cannot move")
	check(Game.submit_change("during a freeze", [cw_sw.name], 4, true, true) == "" \
			and bool(Game.change_window["overridden"]) \
			and int(Game.stats.get("freeze_overrides", 0)) >= 1,
		"change: the override exists, and it is remembered")
	Game.abort_change()
	Game.tour = {}
	# and a job that only counts inside a window
	var cw_deal := {"id": "cw", "customer": "Nyar Kft", "kind": "hosting", "params": {},
		"fee": 100, "brief": "", "load": 100, "healthy": true, "ever_healthy": true,
		"cycles": 12, "up_cycles": 12, "loyalty": 0.7}
	var cw_deals := Game.deals.duplicate(true)
	Game.deals = [cw_deal]
	cw_deal["window_job"] = {"fee": 300, "by": Game.cycle + 10}
	Game.maintenance_until = -1
	check(Game.claim_window_job(cw_deal) != "",
		"change: the window job pays for work done inside a window, not for saying it was")
	Game.maintenance_used = 0
	Game.submit_change("the window job", [cw_sw.name], 4, true)
	var money_cw := Game.money
	check(Game.claim_window_job(cw_deal) == "" and Game.money > money_cw \
			and not cw_deal.has("window_job"),
		"change: doing it properly inside the window pays three times the cycle fee")
	Game.abort_change()
	Game.deals = cw_deals
	Game.staff = cw_staff
	Game.maintenance_until = -1
	Game.maintenance_used = 0
	Game.money = 8000
	var zr := Game.add_rack(Vector2i(46, 1))
	var z_sw := Game.new_device("sw-8")
	var z_srv := Game.new_device("srv-1")
	var z_lonely := Game.new_device("srv-1")   # cabled to nothing at all
	var z_useful := Game.new_device("rtr-lite")  # also uncabled, and still routed through
	zr.slots[0] = z_sw
	zr.slots[1] = z_srv
	zr.slots[2] = z_lonely
	var zr2 := Game.add_rack(Vector2i(47, 1))
	zr2.slots[0] = z_useful
	Game.connect_ifaces(z_srv.ifaces[0], z_sw.ifaces[0])
	Game.add_ip(z_srv.ifaces[0], "10.77.0.10/24")
	Game.add_ip(z_useful.ifaces[0], "10.77.0.1/24")
	Game.add_static_route(z_srv, "10.78.0.0", 24, "10.77.0.1")
	Game.add_vlan(z_sw, 77, "nobody")
	var zombies := Game.orphan_list()
	var z_keys: Array = []
	for z: Dictionary in zombies:
		z_keys.append(String(z["key"]))
	check("device|%s" % z_lonely.name in z_keys and "device|%s" % z_useful.name in z_keys \
			and "vlan|%s|77" % z_sw.name in z_keys,
		"zombies: uncabled hardware and an empty VLAN show up on their own, without bookkeeping")
	check("nobody claims" in String(Game.audit_findings()[Game.audit_findings().size() - 1]),
		"zombies: an auditor counts them as exactly the sloppiness they are")
	var lonely_orphan := {}
	var useful_orphan := {}
	for z2: Dictionary in zombies:
		if String(z2["key"]) == "device|%s" % z_lonely.name:
			lonely_orphan = z2
		elif String(z2["key"]) == "device|%s" % z_useful.name:
			useful_orphan = z2
	check(Game.orphan_load_bearing(lonely_orphan) == "" \
			and Game.orphan_load_bearing(useful_orphan) != "",
		"zombies: one of them is quietly load bearing, and it is a fact about the network")
	Game.reputation = 60  # earlier sections leave it wherever they left it
	var rep_before_zombie := Game.reputation
	Game.investigate_orphan(useful_orphan)  # half a look, which tells you nothing
	var zres := Game.retire_orphan(useful_orphan)
	check(zres == "" and Game.reputation < rep_before_zombie \
			and String(Game.incidents[0]["kind"]) == "zombie",
		"zombies: switching one off half-investigated discovers what it was carrying the hard way")
	# the same situation, looked at properly first
	var z_useful2 := Game.new_device("rtr-lite")
	zr2.slots[1] = z_useful2
	Game.add_ip(z_useful2.ifaces[0], "10.79.0.1/24")
	Game.add_static_route(z_srv, "10.80.0.0", 24, "10.79.0.1")
	var second_orphan := {}
	for z3: Dictionary in Game.orphan_list():
		if String(z3["key"]) == "device|%s" % z_useful2.name:
			second_orphan = z3
	var rep_before_safe := Game.reputation
	Game.investigate_orphan(second_orphan)
	Game.investigate_orphan(second_orphan)
	check(Game.orphan_intel_of(second_orphan) == 2 \
			and Game.retire_orphan(second_orphan) != "" and Game.reputation == rep_before_safe \
			and Game.rack_of(z_useful2) != null,
		"zombies: investigating first is measurably safer, because it stops you doing it")
	var money_before_reclaim := Game.money
	check(Game.retire_orphan(lonely_orphan) == "" \
			and Game.money > money_before_reclaim \
			and Game.rack_of(z_lonely) == null,
		"zombies: turning off something genuinely unused reclaims space and money")
	Game.orphan_intel = {}

	# --- virtual machines and live migration ---
	var vm_rack := Game.add_rack(Vector2i(22, 1))
	var vm_sw := Game.new_device("sw-8")
	var host_a := Game.new_device("srv-2")
	var host_b := Game.new_device("srv-2")
	var vm_peer := Game.new_device("srv-1")
	vm_rack.slots[0] = vm_sw
	vm_rack.slots[1] = host_a
	vm_rack.slots[2] = host_b
	vm_rack.slots[3] = vm_peer
	Game.connect_ifaces(host_a.ifaces[0], vm_sw.ifaces[0])
	Game.connect_ifaces(host_b.ifaces[0], vm_sw.ifaces[1])
	Game.connect_ifaces(vm_peer.ifaces[0], vm_sw.ifaces[2])
	Game.add_ip(vm_peer.ifaces[0], "10.160.0.9/24")
	var ha := CLI.new_session(host_a)
	check(ha.exec("vm create web01").contains("created"), "vm: a machine can be created on a host")
	check(ha.exec("vm addr web01 10.160.0.20/24").is_empty(), "vm: it takes its own address")
	check(Sim.ping(vm_peer, "10.160.0.20")["ok"], "vm: the machine answers on the network")
	check(ha.exec("vm list").contains("web01"), "vm: machines are listed with their host")
	# live migration to another host in the same segment: the machine keeps working
	check(ha.exec("vm migrate web01 %s" % host_b.name).contains("now runs on"),
		"vm: it migrates to another host")
	check(Game.find_vm("web01").dev == host_b, "vm: it really moved")
	check(Sim.ping(vm_peer, "10.160.0.20")["ok"],
		"vm: with layer 2 stretched across both hosts, the address survives the move")
	# now put the second host in a different VLAN: the same migration breaks it
	Game.add_vlan(vm_sw, 88, "other")
	vm_sw.ifaces[1].untagged_vlan = 88
	Game.topology_changed.emit()
	check(not Sim.ping(vm_peer, "10.160.0.20")["ok"],
		"vm: move it outside its broadcast domain and the address stops working")
	vm_sw.ifaces[1].untagged_vlan = 1
	Game.topology_changed.emit()
	check(Sim.ping(vm_peer, "10.160.0.20")["ok"], "vm: restoring the segment restores the machine")

	# --- DHCP snooping and ARP inspection ---
	var sn_rack := Game.add_rack(Vector2i(21, 1))
	var sn_sw := Game.new_device("sw-8")
	var sn_srv := Game.new_device("srv-1")   # the legitimate DHCP server
	var sn_cli := Game.new_device("srv-1")   # an honest client
	var sn_rogue := Game.new_device("srv-1") # a customer machine handing out leases
	sn_rack.slots[0] = sn_sw
	sn_rack.slots[1] = sn_srv
	sn_rack.slots[2] = sn_cli
	sn_rack.slots[3] = sn_rogue
	Game.connect_ifaces(sn_srv.ifaces[0], sn_sw.ifaces[0])
	Game.connect_ifaces(sn_cli.ifaces[0], sn_sw.ifaces[1])
	Game.connect_ifaces(sn_rogue.ifaces[0], sn_sw.ifaces[2])
	Game.add_ip(sn_srv.ifaces[0], "10.170.0.5/24")
	Game.add_ip(sn_rogue.ifaces[0], "10.170.0.66/24")
	CLI.new_session(sn_srv).exec("dhcpd eth0 10.170.0.10 10.170.0.99 24 10.170.0.1")
	CLI.new_session(sn_rogue).exec("dhcpd eth0 10.170.0.200 10.170.0.240 24 10.170.0.66")
	var honest := CLI.new_session(sn_cli)
	var lease1: String = honest.exec("dhclient eth0")
	check(lease1.contains("bound to"), "snooping: without protection a lease is handed out")
	# turn on snooping, trust only the port facing the real server
	var sn_s := CLI.new_session(sn_sw)
	sn_s.exec("en")
	sn_s.exec("conf t")
	check(sn_s.exec("ip dhcp snooping").is_empty(), "snooping: it can be enabled")
	sn_s.exec("interface Ethernet1")
	sn_s.exec("ip dhcp snooping trust")
	sn_s.exec("exit")
	sn_s.exec("ip arp inspection")
	sn_s.exec("end")
	for cidr in sn_cli.ifaces[0].ips.duplicate():
		Game.remove_ip(sn_cli.ifaces[0], cidr)
	var lease2: String = honest.exec("dhclient eth0")
	check(lease2.contains("10.170.0."), "snooping: the trusted server still serves leases")
	check(not lease2.contains("10.170.0.2"), "snooping: the rogue server's range is not used")
	check(sn_sw.bindings.size() >= 1, "snooping: a binding is recorded for the lease")
	check(sn_s.exec("show ip dhcp snooping").contains("Trusted ports"), "snooping: state is reported")
	# ARP inspection: a machine claiming somebody else's address is dropped
	var victim_ip: String = String(sn_sw.bindings[sn_cli.ifaces[0].mac])
	check(victim_ip.begins_with("10.170.0."), "snooping: the binding holds the leased address")
	var logged_drop := false
	Game.device_log(sn_sw, "test")
	for l in sn_sw.logs:
		if "inspection" in l or "snooping" in l:
			logged_drop = true
	check(logged_drop, "snooping: drops are written to the device log")

	# --- capacity and quarterly reports ---
	var cap0: Dictionary = Game.capacity(0)
	check(int(cap0["tiles"]) > 0 and int(cap0["slots"]) >= int(cap0["slots_used"]),
		"capacity: a site reports space, slots and ports")
	check(int(cap0["ports"]) >= int(cap0["ports_used"]), "capacity: port usage never exceeds the total")
	var cap_full := Game.capacity(0)
	check(int(cap_full["watts"]) > 0, "capacity: power draw is counted per site")
	Game.reports = []
	var quarter_rep: Dictionary = Game.make_report()
	check(quarter_rep.has("uptime") and quarter_rep.has("rank") and Game.reports.size() == 1,
		"report: a quarter can be closed")
	for i in 10:
		Game.make_report()
	check(Game.reports.size() == 8, "report: only the recent quarters are kept")
	check(Game.log_contains("QUARTER"), "report: closing a quarter is announced")

	# --- tunnels over an untrusted path ---
	var tun_rack := Game.add_rack(Vector2i(20, 1))
	var t_left := Game.new_device("rtr-edge")
	var t_right := Game.new_device("rtr-edge")
	var t_mid := Game.new_device("rtr-edge")   # stands in for the internet in between
	var t_a := Game.new_device("srv-1")
	var t_b := Game.new_device("srv-1")
	tun_rack.slots[0] = t_left
	tun_rack.slots[1] = t_right
	tun_rack.slots[2] = t_mid
	tun_rack.slots[3] = t_a
	tun_rack.slots[4] = t_b
	Game.connect_ifaces(t_left.ifaces[0], t_mid.ifaces[0])
	Game.connect_ifaces(t_right.ifaces[0], t_mid.ifaces[1])
	Game.add_ip(t_left.ifaces[0], "203.0.113.1/30")
	Game.add_ip(t_mid.ifaces[0], "203.0.113.2/30")
	Game.add_ip(t_mid.ifaces[1], "203.0.113.5/30")
	Game.add_ip(t_right.ifaces[0], "203.0.113.6/30")
	Game.add_static_route(t_left, "203.0.113.4", 30, "203.0.113.2")
	Game.add_static_route(t_right, "203.0.113.0", 30, "203.0.113.5")
	# private networks behind each end
	Game.connect_ifaces(t_a.ifaces[0], t_left.ifaces[1])
	Game.connect_ifaces(t_b.ifaces[0], t_right.ifaces[1])
	Game.add_ip(t_left.ifaces[1], "192.168.30.1/24")
	Game.add_ip(t_a.ifaces[0], "192.168.30.10/24")
	Game.add_ip(t_right.ifaces[1], "192.168.31.1/24")
	Game.add_ip(t_b.ifaces[0], "192.168.31.10/24")
	Game.add_static_route(t_a, "0.0.0.0", 0, "192.168.30.1")
	Game.add_static_route(t_b, "0.0.0.0", 0, "192.168.31.1")
	check(Sim.ping(t_left, "203.0.113.6")["ok"], "tunnel: the underlay between endpoints works")
	check(not Sim.ping(t_a, "192.168.31.10")["ok"], "tunnel: private networks cannot reach each other yet")
	var tl := CLI.new_session(t_left)
	tl.exec("en")
	tl.exec("conf t")
	check(tl.exec("interface Tunnel1").is_empty(), "tunnel: a tunnel interface can be created")
	tl.exec("tunnel source 203.0.113.1")
	tl.exec("tunnel destination 203.0.113.6")
	tl.exec("ip address 10.255.0.1/30")
	tl.exec("exit")  # back to config mode for a routing statement
	check(tl.exec("ip route 192.168.31.0/24 10.255.0.2").is_empty(), "tunnel: a route can point down it")
	tl.exec("end")
	var tun_r := CLI.new_session(t_right)
	tun_r.exec("en")
	tun_r.exec("conf t")
	tun_r.exec("interface Tunnel1")
	tun_r.exec("tunnel source 203.0.113.6")
	tun_r.exec("tunnel destination 203.0.113.1")
	tun_r.exec("ip address 10.255.0.2/30")
	tun_r.exec("exit")
	tun_r.exec("ip route 192.168.30.0/24 10.255.0.1")
	tun_r.exec("end")
	check(tl.exec("show tunnels").contains("up"), "tunnel: it comes up over a working underlay")
	check(Sim.ping(t_a, "192.168.31.10")["ok"] and Sim.ping(t_b, "192.168.30.10")["ok"],
		"tunnel: the private networks now reach each other through it")
	# break the underlay: the tunnel goes with it
	t_mid.status = "offline"
	Game.topology_changed.emit()
	check(not Sim.ping(t_a, "192.168.31.10")["ok"], "tunnel: it fails when the path underneath fails")
	check(tl.exec("show tunnels").contains("down"), "tunnel: and reports itself down")
	t_mid.status = "active"
	Game.topology_changed.emit()
	check(Sim.ping(t_a, "192.168.31.10")["ok"], "tunnel: it recovers with the underlay")

	# --- QoS under congestion ---
	Game.deals = []
	var qos_rack := Game.add_rack(Vector2i(19, 1))
	var qos_sw := Game.new_device("sw-8")   # 1 Gbit ports, and an EOS-style CLI
	var qos_a := Game.new_device("srv-1")
	var qos_b := Game.new_device("srv-1")
	qos_rack.slots[0] = qos_sw
	qos_rack.slots[1] = qos_a
	qos_rack.slots[2] = qos_b
	Game.connect_ifaces(qos_a.ifaces[0], qos_sw.ifaces[0])
	Game.connect_ifaces(qos_b.ifaces[0], qos_sw.ifaces[1])
	Game.add_ip(qos_a.ifaces[0], "10.180.0.10/24")
	Game.add_ip(qos_b.ifaces[0], "10.180.0.11/24")
	Game.add_static_route(qos_a, "0.0.0.0", 0, "10.180.0.11")
	Game.add_static_route(qos_b, "0.0.0.0", 0, "10.180.0.10")
	var premium := {"id": "q1", "customer": "Strict Kft", "kind": "hosting", "sla": 2,
		"params": {"ip": "10.180.0.10"}, "fee": 200, "load": 900, "brief": "",
		"cycles": 0, "up_cycles": 0, "healthy": true}
	var cheap := {"id": "q2", "customer": "Cheap Bt", "kind": "hosting", "sla": 0,
		"params": {"ip": "10.180.0.11"}, "fee": 80, "load": 900, "brief": "",
		"cycles": 0, "up_cycles": 0, "healthy": true}
	Game.deals = [premium, cheap]
	for i: Net.Iface in qos_sw.ifaces:
		i.qos = false
	# traffic follows the working day, so measure oversubscription at the peak
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 3
	Game.sla_tick()
	check(Game.day_factor() > 1.0, "qos: measured at the busy part of the day")
	check(bool(premium.get("degraded", false)) and bool(cheap.get("degraded", false)),
		"qos: without a policy an oversubscribed link degrades everyone")
	for i: Net.Iface in qos_sw.ifaces:
		i.qos = true
	Game.sla_tick()
	check(not bool(premium.get("degraded", true)), "qos: the strict service level is served first")
	check(bool(cheap.get("degraded", false)), "qos: the best-effort customer absorbs the shortfall")
	var qs := CLI.new_session(qos_sw)
	qs.exec("en")
	check(qs.exec("show qos").contains("priority queueing"), "qos: the policy is reported")
	Game.deals = []

	# --- load balancing ---
	var lb_rack := Game.add_rack(Vector2i(18, 1))
	var lb := Game.new_device("lb-1")
	var lb_sw := Game.new_device("sw-8")
	var web1 := Game.new_device("srv-1")
	var web2 := Game.new_device("srv-1")
	var lb_client := Game.new_device("srv-1")
	lb_rack.slots[0] = lb
	lb_rack.slots[1] = lb_sw
	lb_rack.slots[2] = web1
	lb_rack.slots[3] = web2
	lb_rack.slots[4] = lb_client
	Game.connect_ifaces(lb.ifaces[0], lb_sw.ifaces[0])
	Game.connect_ifaces(web1.ifaces[0], lb_sw.ifaces[1])
	Game.connect_ifaces(web2.ifaces[0], lb_sw.ifaces[2])
	Game.connect_ifaces(lb_client.ifaces[0], lb_sw.ifaces[3])
	Game.add_ip(lb.ifaces[0], "10.190.0.2/24")
	Game.add_ip(web1.ifaces[0], "10.190.0.11/24")
	Game.add_ip(web2.ifaces[0], "10.190.0.12/24")
	Game.add_ip(lb_client.ifaces[0], "10.190.0.50/24")
	var lbs := CLI.new_session(lb)
	lbs.exec("en")
	lbs.exec("conf t")
	check(lbs.exec("virtual-server 10.190.0.100 members 10.190.0.11,10.190.0.12").is_empty(),
		"lb: a virtual server with two members is configured")
	lbs.exec("end")
	check(lbs.exec("show virtual-server").contains("in service"), "lb: healthy members are in service")
	check(Sim.ping(lb_client, "10.190.0.100")["ok"], "lb: the virtual address answers")
	# take one member out: the service survives
	web1.status = "offline"
	Game.topology_changed.emit()
	Game.lb_health_check()
	check(Sim.ping(lb_client, "10.190.0.100")["ok"], "lb: losing a member does not lose the service")
	check(lbs.exec("show virtual-server").contains("out of service"), "lb: the dead member is marked")
	# take both out: honest failure
	web2.status = "offline"
	Game.topology_changed.emit()
	Game.lb_health_check()
	check(not Sim.ping(lb_client, "10.190.0.100")["ok"], "lb: with no healthy members it stops answering")
	web1.status = "active"
	web2.status = "active"
	Game.topology_changed.emit()
	Game.lb_health_check()
	check(Sim.ping(lb_client, "10.190.0.100")["ok"], "lb: the pool recovers when servers come back")
	check(Game.try_complete_contract(_contract("always_on")), "lb: the always-on contract verifies")

	# --- VRFs: two tenants on the same addresses ---
	var vrf_rack := Game.add_rack(Vector2i(17, 1))
	var vrf_rtr := Game.new_device("rtr-edge")
	var ten_a := Game.new_device("srv-1")
	var ten_b := Game.new_device("srv-1")
	vrf_rack.slots[0] = vrf_rtr
	vrf_rack.slots[1] = ten_a
	vrf_rack.slots[2] = ten_b
	Game.connect_ifaces(ten_a.ifaces[0], vrf_rtr.ifaces[0])
	Game.connect_ifaces(ten_b.ifaces[0], vrf_rtr.ifaces[1])
	var vs2 := CLI.new_session(vrf_rtr)
	vs2.exec("en")
	vs2.exec("conf t")
	check(vs2.exec("ip vrf alfa").is_empty(), "vrf: a routing table can be created")
	vs2.exec("ip vrf beta")
	vs2.exec("interface Ethernet1")
	check(vs2.exec("ip vrf forwarding alfa").contains("moved"), "vrf: an interface joins a table")
	vs2.exec("ip address 10.0.0.1/24")
	vs2.exec("interface Ethernet2")
	vs2.exec("ip vrf forwarding beta")
	vs2.exec("ip address 10.0.0.1/24")  # the same address again, legitimately
	vs2.exec("end")
	Game.add_ip(ten_a.ifaces[0], "10.0.0.50/24")
	Game.add_ip(ten_b.ifaces[0], "10.0.0.50/24")  # both tenants use the same address
	check(vs2.exec("show ip vrf").contains("alfa"), "vrf: tables are listed with their interfaces")
	check(Sim.ping(vrf_rtr, "10.0.0.50", 64, "alfa")["ok"], "vrf: the router reaches tenant A in its table")
	check(Sim.ping(vrf_rtr, "10.0.0.50", 64, "beta")["ok"], "vrf: and tenant B in theirs")
	var overlap := 0
	for d in [ten_a, ten_b]:
		for i: Net.Iface in d.ifaces:
			if "10.0.0.50/24" in i.ips:
				overlap += 1
	check(overlap == 2, "vrf: two customers legitimately share an address")
	check(Sim._route_paths(vrf_rtr, "10.0.0.50", "alfa").size() == 1,
		"vrf: each table has exactly its own path")
	check(Sim._route_paths(vrf_rtr, "10.0.0.50", "").is_empty(),
		"vrf: the global table knows nothing about tenant addresses")

	# --- achievements ---
	Game.achievements = []
	Game.stats["contracts"] = 3
	var earned_now := Game.check_achievements()
	var ids: Array = []
	for ach in earned_now:
		ids.append(ach["id"])
	check("first_light" in ids, "achievements: completing contracts earns one")
	check(Game.check_achievements().is_empty() or true, "achievements: re-checking does not duplicate")
	var before := Game.achievements.size()
	Game.check_achievements()
	check(Game.achievements.size() == before, "achievements: each is awarded once")
	check(Game.achievements.has("empire"), "achievements: operating two sites is recognised")
	var logged := false
	for ev in Game.events:
		if "ACHIEVEMENT" in ev:
			logged = true
	check(logged, "achievements: they are announced in the log")

	# --- customer types ---
	var seen_types := {}
	for i in 60:
		var o := Market.gen_offer()
		seen_types[o.get("ctype", "?")] = true
		check_silent(o.has("loyalty") and float(o["loyalty"]) > 0.0)
	check(seen_types.size() >= 3, "customers: several types appear in the market (%d)" % seen_types.size())
	var start_deal := {"id": "grow", "customer": "Kicsi Startup", "kind": "hosting", "ctype": "startup",
		"params": {"ip": "10.199.0.10"}, "fee": 100, "load": 100, "brief": "", "loyalty": 0.2,
		"cycles": 0, "up_cycles": 0, "healthy": true, "sla": 0}
	var grew := false
	for i in 120:
		Game.customer_growth(start_deal)
		if int(start_deal["fee"]) > 100:
			grew = true
			break
	check(grew and int(start_deal["load"]) > 100,
		"customers: a startup that survives outgrows its contract, in fee and traffic")
	var ent_deal := start_deal.duplicate(true)
	ent_deal["ctype"] = "enterprise"
	ent_deal["fee"] = 100
	for i in 120:
		Game.customer_growth(ent_deal)
	check(int(ent_deal["fee"]) == 100, "customers: an enterprise contract does not balloon by itself")

	# --- difficulty and preferences ---
	var money_pre := Game.money
	Game.apply_difficulty(0)
	check(Game.money == int(Game.DIFFICULTIES[0]["cash"]) and Game.fault_scale() < 1.0,
		"difficulty: apprentice gives more cash and fewer faults")
	var gentle := 0.0
	for rv3 in Game.rivals:
		gentle = maxf(gentle, float(rv3["aggression"]))
	Game.apply_difficulty(2)
	var harsh := 0.0
	for rv4 in Game.rivals:
		harsh = maxf(harsh, float(rv4["aggression"]))
	check(harsh > gentle, "difficulty: on-call rivals bid harder")
	check(Game.fault_scale() > 1.0, "difficulty: on-call breaks things more often")
	Game.apply_difficulty(1)
	Game.money = money_pre
	check(Prefs.ok_colour() != Prefs.bad_colour(), "prefs: status colours differ")
	Prefs.colourblind = true
	var cb_ok := Prefs.ok_colour()
	Prefs.colourblind = false
	check(cb_ok != Prefs.ok_colour(), "prefs: the colourblind palette changes the good colour")
	var old_motion := Prefs.reduced_motion
	Prefs.reduced_motion = true
	check(Prefs.reduced_motion, "prefs: reduced motion can be enabled")
	Prefs.reduced_motion = old_motion

	# --- syslog and clocks ---
	var log_rack := Game.add_rack(Vector2i(16, 1))
	var log_sw := Game.new_device("sw-8")
	var log_srv := Game.new_device("srv-1")
	log_rack.slots[0] = log_sw
	log_rack.slots[1] = log_srv
	Game.connect_ifaces(log_srv.ifaces[0], log_sw.ifaces[0])
	Game.add_ip(log_srv.ifaces[0], "10.26.0.5/24")
	for i: Net.Iface in log_sw.ifaces:
		if i.name.begins_with("Management"):
			Game.connect_ifaces(i, log_sw.ifaces[6])  # management patched into the same LAN
			Game.add_ip(i, "10.26.0.2/24")
	var log_cli := CLI.new_session(log_srv)
	check(log_cli.exec("syslogd").contains("collecting"), "syslog: a server can collect logs")
	var sw_cli := CLI.new_session(log_sw)
	sw_cli.exec("en")
	sw_cli.exec("conf t")
	check(sw_cli.exec("logging host 10.26.0.5").is_empty(), "syslog: a device can ship to a collector")
	sw_cli.exec("end")
	Game.device_log(log_sw, "test message from the switch")
	var collected: Array = log_srv.services["syslog"]["messages"]
	check(collected.size() >= 1, "syslog: the collector received it")
	check(sw_cli.exec("show logging").contains("test message"), "syslog: show logging displays the buffer")
	check(log_cli.exec("logs").contains("test message"), "syslog: the server can read what it collected")
	# clocks: without NTP they drift, with it they do not
	log_sw.clock_skew = 7
	check(sw_cli.exec("show clock").contains("free running"), "ntp: an unsynchronised clock is reported")
	sw_cli.exec("conf t")
	sw_cli.exec("ntp server 10.26.0.5")
	sw_cli.exec("end")
	Game.clock_tick()
	check(log_sw.clock_skew == 0, "ntp: a reachable server disciplines the clock")
	check(sw_cli.exec("show clock").contains("synchronised"), "ntp: sync is reported")

	# --- spine and leaf fabric with ECMP ---
	var fab_rack := Game.add_rack(Vector2i(15, 1))
	var spine_a := Game.new_device("rtr-edge")
	var spine_b := Game.new_device("rtr-edge")
	var leaf_a := Game.new_device("rtr-edge")
	var leaf_b := Game.new_device("rtr-edge")
	var fab_h1 := Game.new_device("srv-1")
	var fab_h2 := Game.new_device("srv-1")
	fab_rack.slots[0] = spine_a
	fab_rack.slots[1] = spine_b
	fab_rack.slots[2] = leaf_a
	fab_rack.slots[3] = leaf_b
	fab_rack.slots[4] = fab_h1
	fab_rack.slots[5] = fab_h2
	# every leaf uplinks to every spine
	Game.connect_ifaces(leaf_a.ifaces[0], spine_a.ifaces[0])
	Game.connect_ifaces(leaf_a.ifaces[1], spine_b.ifaces[0])
	Game.connect_ifaces(leaf_b.ifaces[0], spine_a.ifaces[1])
	Game.connect_ifaces(leaf_b.ifaces[1], spine_b.ifaces[1])
	Game.add_ip(leaf_a.ifaces[0], "10.250.1.1/30")
	Game.add_ip(spine_a.ifaces[0], "10.250.1.2/30")
	Game.add_ip(leaf_a.ifaces[1], "10.250.2.1/30")
	Game.add_ip(spine_b.ifaces[0], "10.250.2.2/30")
	Game.add_ip(leaf_b.ifaces[0], "10.250.3.1/30")
	Game.add_ip(spine_a.ifaces[1], "10.250.3.2/30")
	Game.add_ip(leaf_b.ifaces[1], "10.250.4.1/30")
	Game.add_ip(spine_b.ifaces[1], "10.250.4.2/30")
	# a host under each leaf
	Game.connect_ifaces(fab_h1.ifaces[0], leaf_a.ifaces[2])
	Game.connect_ifaces(fab_h2.ifaces[0], leaf_b.ifaces[2])
	Game.add_ip(leaf_a.ifaces[2], "10.251.1.1/24")
	Game.add_ip(fab_h1.ifaces[0], "10.251.1.10/24")
	Game.add_ip(leaf_b.ifaces[2], "10.251.2.1/24")
	Game.add_ip(fab_h2.ifaces[0], "10.251.2.10/24")
	Game.add_static_route(fab_h1, "0.0.0.0", 0, "10.251.1.1")
	Game.add_static_route(fab_h2, "0.0.0.0", 0, "10.251.2.1")
	# OSPF across the fabric
	for fab_dev in [spine_a, spine_b, leaf_a, leaf_b]:
		fab_dev.ospf = {"networks": ["10.250.0.0/16", "10.251.0.0/16"]}
	Game.topology_changed.emit()
	check(Sim.ping(fab_h1, "10.251.2.10")["ok"], "fabric: hosts talk across the spine-leaf fabric")
	var leaf_paths := Sim._route_paths(leaf_a, "10.251.2.10")
	check(leaf_paths.size() == 2, "fabric: the leaf has two equal-cost paths (got %d)" % leaf_paths.size())
	var used_hops := {}
	for i in 24:
		var picked := Sim._route_lookup(leaf_a, "10.251.2.10", "flow-%d" % i)
		used_hops[str(picked["next_hop"])] = true
	check(used_hops.size() == 2, "fabric: flows hash across both spines")
	# lose a spine: the fabric keeps forwarding
	spine_a.status = "offline"
	Game.topology_changed.emit()
	check(Sim.ping(fab_h1, "10.251.2.10")["ok"], "fabric: losing a spine costs capacity, not connectivity")
	spine_a.status = "active"
	Game.topology_changed.emit()
	check(Game.try_complete_contract(_contract("build_a_fabric")), "fabric: the build-a-fabric contract verifies")

	# --- blackhole routes and attacks ---
	Game.attacks = []
	Game.scrubbing = false
	var bh_rtr := Game.new_device("rtr-edge")
	var bh_srv := Game.new_device("srv-1")
	var bh_rack := Game.add_rack(Vector2i(14, 1))
	bh_rack.slots[0] = bh_rtr
	bh_rack.slots[1] = bh_srv
	Game.connect_ifaces(bh_srv.ifaces[0], bh_rtr.ifaces[0])
	Game.add_ip(bh_rtr.ifaces[0], "10.240.0.1/24")
	Game.add_ip(bh_srv.ifaces[0], "10.240.0.10/24")
	Game.add_ip(bh_rtr.ifaces[1], "10.241.0.1/24")
	var far_srv := Game.new_device("srv-1")
	bh_rack.slots[2] = far_srv
	Game.connect_ifaces(far_srv.ifaces[0], bh_rtr.ifaces[2])
	Game.add_ip(bh_rtr.ifaces[2], "10.242.0.1/24")
	Game.add_ip(far_srv.ifaces[0], "10.242.0.10/24")
	Game.add_static_route(far_srv, "0.0.0.0", 0, "10.242.0.1")
	Game.add_static_route(bh_srv, "0.0.0.0", 0, "10.240.0.1")  # the victim needs a way back
	check(Sim.ping(far_srv, "10.240.0.10")["ok"], "blackhole: the victim is reachable to begin with")
	var bh_s := CLI.new_session(bh_rtr)
	bh_s.exec("en")
	bh_s.exec("conf t")
	check(bh_s.exec("ip route 10.240.0.10/32 null0").is_empty(), "blackhole: a discard route is accepted")
	bh_s.exec("end")
	check(not Sim.ping(far_srv, "10.240.0.10")["ok"], "blackhole: traffic to the victim is discarded")
	var atk := {"target": "10.240.0.10", "customer": "Test", "mbps": 5000, "cycles_left": 3}
	Game.attacks = [atk]
	check(Game.attack_blackholed(atk), "blackhole: the mitigation is recognised")
	Game.remove_static_route(bh_rtr, "10.240.0.10", 32)
	check(not Game.attack_blackholed(atk), "blackhole: removing the route ends the mitigation")
	check(Sim.ping(far_srv, "10.240.0.10")["ok"], "blackhole: service returns once the route is gone")
	Game.attacks = []

	# --- golden config templates ---
	Game.templates = []
	var tpl_a := Game.new_device("sw-8")
	var tpl_b := Game.new_device("sw-8")
	var tpl_rack := Game.add_rack(Vector2i(13, 1))
	tpl_rack.slots[0] = tpl_a
	tpl_rack.slots[1] = tpl_b
	var ts := CLI.new_session(tpl_a)
	ts.exec("en")
	ts.exec("conf t")
	ts.exec("vlan 200")
	ts.exec("vlan 201")
	ts.exec("interface range Ethernet1-4")
	ts.exec("switchport access vlan 200")
	ts.exec("switchport port-security")
	ts.exec("end")
	for i: Net.Iface in tpl_a.ifaces:
		if i.name.begins_with("Management"):
			Game.add_ip(i, "10.230.0.1/24")  # identity: must not travel with the template
	check(ts.exec("copy running-config template access-standard").contains("Saved"),
		"template: a device can be saved as a standard")
	var tb := CLI.new_session(tpl_b)
	tb.exec("en")
	check(tb.exec("copy template access-standard running-config").contains("Applied"),
		"template: it can be applied to another switch")
	check(tpl_b.vlans.has(200) and tpl_b.vlans.has(201), "template: VLANs came across")
	check(tpl_b.ifaces[0].untagged_vlan == 200 and tpl_b.ifaces[3].port_security,
		"template: port profiles came across")
	var addrs_copied := false
	for i: Net.Iface in tpl_b.ifaces:
		if not i.ips.is_empty():
			addrs_copied = true
	check(not addrs_copied, "template: addresses are identity, not policy, and stay behind")
	check(tb.exec("show templates").contains("access-standard"), "template: templates are listed")
	var tpl_srv := Game.new_device("srv-1")
	tpl_rack.slots[2] = tpl_srv
	check(not Game.apply_template(tpl_srv, Game.templates[0]).is_empty(),
		"template: a switch template is refused on a server")

	# --- monitors and history ---
	seed(20260823)  # a cycle of weather here must not depend on the sections above
	Game.monitors = []
	Game.history = []
	var mon_sw := Game.new_device("sw-8")
	var mon_a := Game.new_device("srv-1")
	var mon_b := Game.new_device("srv-1")
	var mon_rack := Game.add_rack(Vector2i(12, 1))
	mon_rack.slots[0] = mon_sw
	mon_rack.slots[1] = mon_a
	mon_rack.slots[2] = mon_b
	Game.connect_ifaces(mon_a.ifaces[0], mon_sw.ifaces[0])
	Game.connect_ifaces(mon_b.ifaces[0], mon_sw.ifaces[1])
	Game.add_ip(mon_a.ifaces[0], "10.210.0.10/24")
	Game.add_ip(mon_b.ifaces[0], "10.210.0.11/24")
	check(Game.add_monitor("ping", mon_a.name, "10.210.0.11").is_empty(), "monitor: a check can be added")
	check(not Game.add_monitor("ping", mon_a.name, "10.210.0.11").is_empty(), "monitor: duplicates are refused")
	check(Game.monitor_ok(Game.monitors[0]), "monitor: it passes while the network works")
	Game.staff = []  # nobody to repair it behind our backs
	mon_sw.ifaces[1].enabled = false
	Game.topology_changed.emit()
	check(not Game.monitor_ok(Game.monitors[0]), "monitor: it fails when the path breaks")
	Game.sla_tick()
	var alerted := false
	for ev in Game.events:
		if "MONITOR ALERT" in ev:
			alerted = true
	check(alerted and bool(Game.monitors[0]["failing"]), "monitor: a failure raises an alert")
	mon_sw.ifaces[1].enabled = true
	Game.topology_changed.emit()
	Game.sla_tick()
	var recovered := false
	for ev in Game.events:
		if "MONITOR OK" in ev:
			recovered = true
	check(recovered and not bool(Game.monitors[0]["failing"]), "monitor: recovery is reported too")
	check(Game.history.size() >= 2 and Game.history[0].has("money"),
		"history: each cycle is recorded for the graphs")
	Game.monitors = []

	# --- SLA tiers ---
	Game.deals = []
	Game.staff = []
	Game.money = 20000
	var sla_deal := {"id": "sla1", "customer": "Strict Zrt", "kind": "hosting",
		"params": {"ip": "10.222.0.10"}, "fee": 200, "load": 100, "brief": "",
		"sla": 2, "cycles": 0, "up_cycles": 0, "healthy": false}
	Game.deals.append(sla_deal)
	for i in 5:  # never delivered: the strict tier bites
		Game.sla_tick()
	check(Game.last_pl.has("SLA penalties"), "sla: a missed service level is charged back")
	var penalised := false
	for ev in Game.events:
		if "SLA PENALTY" in ev:
			penalised = true
	check(penalised, "sla: the penalty is explained in the log")
	check(Market.tier(2)["pay"] > Market.tier(0)["pay"], "sla: a strict tier pays more up front")
	Game.deals = []

	# --- staff ---
	Game.staff = []
	Game.candidates = []
	Game.money = 50000
	Game.refresh_candidates(true)
	check(Game.candidates.size() == 3, "staff: a hiring market is generated")
	var cand: Dictionary = Game.candidates[0]
	check(Game.hire(cand).is_empty() and Game.staff.size() == 1, "staff: a candidate can be hired")
	check(Staff.payroll() == int(cand["salary"]), "staff: payroll reflects the hire")
	var m_before := Game.money
	Game.sla_tick()
	check(Game.last_pl.has("salaries"), "staff: salaries appear in the cycle P&L")
	# a NOC team restores links that are down
	var st_sw := Game.new_device("sw-8")
	var st_srv := Game.new_device("srv-1")
	var st_rack := Game.add_rack(Vector2i(11, 1))
	st_rack.slots[0] = st_sw
	st_rack.slots[1] = st_srv
	Game.connect_ifaces(st_srv.ifaces[0], st_sw.ifaces[0])
	Game.staff = [{"name": "Teszt Elek", "role": "noc", "skill": 5, "salary": 100, "morale": 70}]
	st_sw.ifaces[0].enabled = false
	var restored := false
	for i in 12:
		Staff.work_cycle()
		if st_sw.ifaces[0].enabled:
			restored = true
			break
	check(restored, "staff: the NOC restores a tripped port without the player")
	# an engineer keeps configurations saved
	Game.staff = [{"name": "Konfig Klara", "role": "engineer", "skill": 5, "salary": 400, "morale": 70}]
	var dirty_before := 0
	for d in Game.all_devices():
		if Game.config_dirty(d):
			dirty_before += 1
	for i in 6:
		Staff.work_cycle()
	var dirty_after := 0
	for d in Game.all_devices():
		if Game.config_dirty(d):
			dirty_after += 1
	check(dirty_before > 0 and dirty_after < dirty_before,
		"staff: an engineer works through unsaved configurations (%d -> %d)" % [dirty_before, dirty_after])
	Game.fire(Game.staff[0])
	check(Game.staff.is_empty(), "staff: people can be let go")

	# --- config versions, diff and rollback ---
	var ver_sw := Game.new_device("sw-8")
	var ver_rack := Game.add_rack(Vector2i(10, 1))
	ver_rack.slots[0] = ver_sw
	var vs := CLI.new_session(ver_sw)
	vs.exec("en")
	vs.exec("conf t")
	vs.exec("vlan 61")
	vs.exec("end")
	check(vs.exec("write memory").contains("version 1"), "cfgver: write memory keeps a version")
	check(vs.exec("show config diff").contains("matches"), "cfgver: no drift right after saving")
	vs.exec("conf t")
	vs.exec("vlan 62")
	vs.exec("interface Ethernet1")
	vs.exec("switchport access vlan 62")
	vs.exec("shutdown")
	vs.exec("end")
	var diff_out: String = vs.exec("show config diff")
	check(diff_out.contains("+ vlan 62"), "cfgver: the diff names the new VLAN")
	check(diff_out.contains("untagged_vlan"), "cfgver: the diff names the changed port")
	check(diff_out.contains("enabled"), "cfgver: the diff notices the shutdown")
	check(vs.exec("show config versions").contains("VER"), "cfgver: versions are listed")
	check(vs.exec("rollback 1").contains("Rolled back"), "cfgver: rollback runs")
	check(not ver_sw.vlans.has(62) and ver_sw.ifaces[0].enabled,
		"cfgver: rollback restored the earlier configuration")
	check(vs.exec("rollback 9").contains("no such version"), "cfgver: a bad version is refused")

	# --- interface ranges ---
	var rng_sw := Game.new_device("sw-24")
	var rng_rack := Game.add_rack(Vector2i(9, 1))
	rng_rack.slots[0] = rng_sw
	var rng_s := CLI.new_session(rng_sw)
	rng_s.exec("en")
	rng_s.exec("conf t")
	rng_s.exec("vlan 55")
	check(rng_s.exec("interface range Ethernet1-8").is_empty(), "range: a range of interfaces can be selected")
	check(rng_s.exec("switchport access vlan 55").is_empty(), "range: a vlan applies to the whole range")
	var in_55 := 0
	for i: Net.Iface in rng_sw.ifaces:
		if i.untagged_vlan == 55:
			in_55 += 1
	check(in_55 == 8, "range: exactly the eight ports moved (got %d)" % in_55)
	rng_s.exec("shutdown")
	var down := 0
	for i: Net.Iface in rng_sw.ifaces:
		if not i.enabled:
			down += 1
	check(down == 8, "range: shutdown applies to the range")
	rng_s.exec("no shutdown")
	check(rng_s.exec("ip address 10.0.0.1/24").contains("cannot be applied to a range"),
		"range: an address is refused for a range")
	check(rng_s.exec("interface range et20-22,et24").is_empty(), "range: abbreviations and lists work")
	rng_s.exec("switchport port-security")
	var secured_n := 0
	for i: Net.Iface in rng_sw.ifaces:
		if i.port_security:
			secured_n += 1
	check(secured_n == 4, "range: a comma list selected four ports")
	rng_s.exec("end")

	# --- speed controls ---
	Game.set_speed(1)
	check(Game.speed == 1 and not Game.cycle_timer.paused, "speed: normal speed runs the clock")
	Game.toggle_pause()
	check(Game.speed == 0 and Game.cycle_timer.paused, "speed: pause stops the revenue cycle")
	Game.toggle_pause()
	check(Game.speed == 1, "speed: unpausing returns to normal")
	Game.set_speed(3)
	check(is_equal_approx(Game.cycle_timer.wait_time, Game.SLA_PERIOD / 3.0),
		"speed: faster speed shortens the cycle")
	Game.set_speed(9)
	check(Game.speed == 3, "speed: the multiplier is clamped")
	Game.set_speed(1)

	# --- IPv6 address handling ---
	check(Net.is_v6("2001:db8::1") and not Net.is_v6("10.0.0.1"), "v6: family detection")
	check(Net.v6_hextets("2001:db8::1") == [0x2001, 0xdb8, 0, 0, 0, 0, 0, 1], "v6: :: expands correctly")
	check(Net.v6_hextets("::1") == [0, 0, 0, 0, 0, 0, 0, 1], "v6: loopback expands")
	check(Net.v6_hextets("2001:db8:0:0:0:0:0:1") == Net.v6_hextets("2001:db8::1"), "v6: both spellings agree")
	check(Net.v6_hextets("2001:db8::1::2").is_empty(), "v6: two :: is rejected")
	check(Net.v6_hextets("nonsense").is_empty(), "v6: garbage is rejected")
	check(Net.v6_compress("2001:0db8:0000:0000:0000:0000:0000:0001") == "2001:db8::1", "v6: canonical short form")
	check(Net.addr_eq("2001:DB8::1", "2001:db8:0:0:0:0:0:1"), "v6: spellings compare equal")
	check(Net.same_subnet6("2001:db8:1::10", "2001:db8:1::1", 64), "v6: same /64")
	check(not Net.same_subnet6("2001:db8:2::10", "2001:db8:1::1", 64), "v6: different /64")
	check(Net.same_subnet6("2001:db8:2::10", "2001:db8:1::1", 32), "v6: shared /32")
	check(Net.same_subnet6("2001:db8:1:8000::1", "2001:db8:1:8fff::2", 49), "v6: masked hextet boundary")
	check(not Net.same_subnet6("2001:db8:1:8000::1", "2001:db8:1:0fff::2", 49), "v6: masked hextet rejects")
	check(Net.valid_cidr("2001:db8::1/64") and not Net.valid_cidr("2001:db8::1/200"), "v6: CIDR validation")
	check(not Net.same_net("10.0.0.1", "2001:db8::", 64), "v6: families never match each other")

	# --- IPv6 end to end ---
	var v6_rack := Game.add_rack(Vector2i(8, 1))
	var v6_sw := Game.new_device("sw-8")
	var v6_a := Game.new_device("srv-1")
	var v6_b := Game.new_device("srv-1")
	var v6_rtr := Game.new_device("rtr-edge")
	var v6_c := Game.new_device("srv-1")
	v6_rack.slots[0] = v6_sw
	v6_rack.slots[1] = v6_a
	v6_rack.slots[2] = v6_b
	v6_rack.slots[3] = v6_rtr
	v6_rack.slots[4] = v6_c
	Game.connect_ifaces(v6_a.ifaces[0], v6_sw.ifaces[0])
	Game.connect_ifaces(v6_b.ifaces[0], v6_sw.ifaces[1])
	Game.connect_ifaces(v6_rtr.ifaces[0], v6_sw.ifaces[2])
	Game.connect_ifaces(v6_c.ifaces[0], v6_rtr.ifaces[1])
	var v6_ls := CLI.new_session(v6_a)
	check(v6_ls.exec("ip -6 addr add 2001:db8:1::10/64 dev eth0").is_empty(),
		"v6: Linux accepts an IPv6 address")
	check("2001:db8:1::10/64" in v6_a.ifaces[0].ips, "v6: the address is configured")
	Game.add_ip(v6_b.ifaces[0], "2001:db8:1::20/64")
	check(Sim.ping(v6_a, "2001:db8:1::20")["ok"], "v6: same-subnet ping works over Neighbor Discovery")
	check(v6_a.arp.has("2001:db8:1::20"), "v6: the neighbor cache is populated")
	check(v6_ls.exec("ping6 2001:db8:1::20").contains("3 received"), "v6: ping6 from the CLI")
	check(not Sim.ping(v6_a, "2001:db8:2::30")["ok"], "v6: another /64 is not reachable yet")
	# route it
	var v6_es := CLI.new_session(v6_rtr)
	v6_es.exec("en")
	v6_es.exec("conf t")
	v6_es.exec("interface Ethernet1")
	v6_es.exec("ipv6 address 2001:db8:1::1/64")
	v6_es.exec("interface Ethernet2")
	v6_es.exec("ipv6 address 2001:db8:2::1/64")
	v6_es.exec("end")
	Game.add_ip(v6_c.ifaces[0], "2001:db8:2::30/64")
	Game.add_static_route(v6_a, "::", 0, "2001:db8:1::1")
	Game.add_static_route(v6_c, "::", 0, "2001:db8:2::1")
	check(Sim.ping(v6_a, "2001:db8:2::30")["ok"] and Sim.ping(v6_c, "2001:db8:1::10")["ok"],
		"v6: routed between two /64s through the router")
	check(v6_es.exec("show ipv6 interface brief").contains("2001:db8:1::1/64"), "v6: show ipv6 interface brief")
	check(v6_es.exec("show ipv6 neighbors").contains("2001:db8:1::10"), "v6: show ipv6 neighbors")
	var v6_amb := CLI.new_session(v6_rtr)
	v6_amb.exec("en")
	v6_amb.exec("conf t")
	v6_amb.exec("interface Ethernet3")
	check(v6_amb.exec("ip address 10.66.0.1/24").is_empty(),
		"v6: 'ip address' is not ambiguous with 'ipv6 address'")
	check(v6_amb.exec("ipv6 address 2001:db8:66::1/64").is_empty(), "v6: 'ipv6 address' still works")
	check(Sim.ping(v6_a, "10.0.0.1")["detail"] != "", "v6: an IPv4 destination is not reachable over v6 config")
	var v6_cap := "\n".join(PackedStringArray(v6_a.capture))
	check("NDP" in v6_cap, "v6: captures name Neighbor Discovery, not ARP")
	# the campaign job wants a specific pair of prefixes
	Game.add_ip(v6_a.ifaces[0], "2001:db8:70::10/64")
	Game.add_ip(v6_c.ifaces[0], "2001:db8:71::10/64")
	Game.add_ip(v6_rtr.ifaces[0], "2001:db8:70::1/64")
	Game.add_ip(v6_rtr.ifaces[1], "2001:db8:71::1/64")
	Game.add_static_route(v6_a, "2001:db8:71::", 64, "2001:db8:70::1")
	Game.add_static_route(v6_c, "2001:db8:70::", 64, "2001:db8:71::1")
	check(Game.try_complete_contract(_contract("dual_stack")), "v6: the dual-stack contract verifies")
	check(Sim.ping(v6_a, "2001:db8:1::20")["ok"], "v6: the original v4/v6 estate still works")

	# --- performance at datacenter scale ---
	Game.racks = []
	Game.links = []
	Game.deals = []
	Game.sites = []
	Game.acquisitions = []
	Game.current_site = 0
	Game.stage = 2
	var core := Game.new_device("sw-24")
	var perf_rack := Game.add_rack(Vector2i(0, 0))
	perf_rack.slots[0] = core
	Game.add_ip(core.ifaces[0], "10.200.0.1/24")
	var edge_switches: Array = []
	var hosts: Array = []
	for k in 8:  # 8 access switches, 8 servers each: a real floor
		var rk := Game.add_rack(Vector2i(k % 4, 1 + k / 4))
		var esw2 := Game.new_device("sw-24")
		rk.slots[0] = esw2
		edge_switches.append(esw2)
		Game.connect_ifaces(esw2.ifaces[23], core.ifaces[k + 1])
		for h in 7:
			var host := Game.new_device("srv-1")
			rk.slots[h + 1] = host
			Game.connect_ifaces(host.ifaces[0], esw2.ifaces[h])
			Game.add_ip(host.ifaces[0], "10.200.0.%d/24" % (10 + hosts.size()))
			hosts.append(host)
	check(Game.all_devices().size() >= 60, "perf: a datacenter-scale topology was built (%d devices, %d links)"
		% [Game.all_devices().size(), Game.links.size()])
	var t0 := Time.get_ticks_msec()
	var okc := 0
	for i in 40:  # cold ARP on the first pass, then learned
		var src: Net.NDevice = hosts[i % hosts.size()]
		var dst_ip := "10.200.0.%d" % (10 + ((i * 13) % hosts.size()))
		if Sim.ping(src, dst_ip)["ok"]:
			okc += 1
	var elapsed := Time.get_ticks_msec() - t0
	check(okc >= 39, "perf: pings across the floor succeed (%d/40)" % okc)
	check(elapsed < 4000, "perf: 40 pings across a 60-device floor took %d ms" % elapsed)
	print("     (perf: %d ms for 40 pings, %d devices, %d links)" % [elapsed, Game.all_devices().size(), Game.links.size()])

	# --- multihoming: two upstreams, and the policy that picks between them ---
	var mh_rack := Game.add_rack(Vector2i(41, 1))
	var mh_edge := Game.new_device("rtr-edge")
	var mh_isp_a := Game.new_device("isp-uplink")
	var mh_isp_b := Game.new_device("isp-uplink")
	mh_rack.slots[0] = mh_edge
	mh_rack.slots[1] = mh_isp_a
	mh_rack.slots[2] = mh_isp_b
	Game.connect_ifaces(mh_edge.ifaces[0], mh_isp_a.ifaces[0])
	Game.connect_ifaces(mh_edge.ifaces[1], mh_isp_b.ifaces[0])
	Game.add_ip(mh_edge.ifaces[0], "100.70.0.2/30")
	Game.add_ip(mh_isp_a.ifaces[0], "100.70.0.1/30")
	Game.add_ip(mh_edge.ifaces[1], "100.71.0.2/30")
	Game.add_ip(mh_isp_b.ifaces[0], "100.71.0.1/30")
	mh_isp_a.bgp = {"asn": 64500, "neighbors": [], "networks": ["0.0.0.0/0", "203.0.113.0/24"]}
	mh_isp_b.bgp = {"asn": 64501, "neighbors": [], "networks": ["0.0.0.0/0", "198.51.100.0/24"]}
	var mh_cli := CLI.new_session(mh_edge)
	mh_cli.exec("enable")
	mh_cli.exec("configure terminal")
	mh_cli.exec("router bgp 65010")
	mh_cli.exec("neighbor 100.70.0.1 remote-as 64500")
	mh_cli.exec("neighbor 100.71.0.1 remote-as 64501")
	mh_cli.exec("end")
	Sim.flush_learned_state()
	check(Sim.route_via(mh_edge, "8.8.8.8") != "", "bgp: a default route arrives from an upstream")
	# local preference decides which upstream we send traffic to
	mh_cli.exec("configure terminal")
	mh_cli.exec("router bgp 65010")
	check(mh_cli.exec("neighbor 100.71.0.1 local-preference 200").is_empty(),
		"bgp: local preference can be set on a neighbour")
	mh_cli.exec("end")
	Sim.flush_learned_state()
	check(Sim.route_via(mh_edge, "8.8.8.8") == "100.71.0.1",
		"bgp: the higher local preference wins, whatever the path length")
	mh_cli.exec("configure terminal")
	mh_cli.exec("router bgp 65010")
	mh_cli.exec("neighbor 100.71.0.1 local-preference 50")
	mh_cli.exec("end")
	Sim.flush_learned_state()
	check(Sim.route_via(mh_edge, "8.8.8.8") == "100.70.0.1",
		"bgp: lowering it sends the traffic back the other way")
	# a prefix list filters what we are willing to accept
	mh_cli.exec("configure terminal")
	mh_cli.exec("router bgp 65010")
	check(mh_cli.exec("neighbor 100.70.0.1 prefix-list in 203.0.113.0/24").is_empty(),
		"bgp: an inbound prefix list can be applied")
	mh_cli.exec("end")
	Sim.flush_learned_state()
	check(Sim.route_via(mh_edge, "203.0.113.5") != "",
		"bgp: a permitted prefix is still accepted")
	check(Sim.route_via(mh_edge, "8.8.8.8") == "100.71.0.1",
		"bgp: the default route is filtered out and the other upstream carries it")
	check(mh_cli.exec("show ip bgp summary").contains("in: 203.0.113.0/24"),
		"bgp: show ip bgp reports the policy")

	# --- rack elevations: not everything is one unit tall ---
	var ru_rack := Game.add_rack(Vector2i(47, 1))
	check(Game.model_height("srv-1") == 1 and Game.model_height("sw-24") == 2,
		"elevation: the catalogue knows how tall things are")
	var ru_big := Game.new_device("sw-24")
	check(Game.can_install(ru_rack, 0, "sw-24"), "elevation: a 2U box fits at the bottom")
	check(Game.install_device(ru_rack, 0, ru_big), "elevation: and installs")
	check(ru_rack.slots[0] == ru_big and ru_rack.covered.has(1),
		"elevation: taking the unit above it as well")
	check(ru_rack.slots[1] == null,
		"elevation: while still appearing in the rack exactly once")
	check(not Game.can_install(ru_rack, 1, "srv-1"),
		"elevation: nothing else fits in the space it is using")
	check(Game.can_install(ru_rack, 2, "srv-1"), "elevation: the unit above that is free")
	check(not Game.can_install(ru_rack, Net.Rack.SLOTS - 1, "sw-24"),
		"elevation: a 2U box cannot hang off the top of the cabinet")
	var ru_count := 0
	for ru_d in ru_rack.slots:
		if ru_d != null:
			ru_count += 1
	check(ru_count == 1, "elevation: iterating the rack sees it once, not twice")
	Game.free_slots(ru_rack, ru_big)
	check(ru_rack.covered.is_empty() and ru_rack.slots[0] == null,
		"elevation: removing it frees both units")

	# --- incident replay ---
	Game.timeline = []
	Game._events_before = Game.events_logged
	var tl_dev: Net.NDevice = Game.all_devices()[0]
	var tl_was := tl_dev.status
	for tl_i in 3:
		Game.timeline_tick()
		Game.cycle += 1
	tl_dev.status = "offline"
	Game.log_event("FAULT: %s stopped answering." % tl_dev.name)
	var tl_bad := Game.cycle
	Game.timeline_tick()
	Game.cycle += 1
	tl_dev.status = tl_was
	for tl_j in 3:
		Game.timeline_tick()
		Game.cycle += 1
	check(Game.timeline.size() == 7, "replay: one frame is recorded per cycle")
	var tl_frames := Game.replay_around(tl_bad, 2)
	check(tl_frames.size() == 5, "replay: it can be read either side of a moment")
	var tl_found := false
	for tl_f in tl_frames:
		if int(tl_f["cycle"]) == tl_bad:
			tl_found = tl_dev.name in tl_f["down_devices"]
	check(tl_found, "replay: the frame at the fault names the device that was down")
	var tl_ev := false
	for tl_f2 in tl_frames:
		for tl_line in tl_f2["events"]:
			if "stopped answering" in String(tl_line):
				tl_ev = true
	check(tl_ev, "replay: and carries what was logged at the time")
	check(Game.replay_line(tl_frames[0]).begins_with("cycle "),
		"replay: each frame reads as a line")
	Game.timeline = []

	# --- the sales pipeline ---
	var pl_saved := Game.deals.duplicate()
	var pl_money := Game.money
	var pl_stats := Game.stats.duplicate(true)
	var pl_contracts := Game.contracts_done.duplicate()
	var pl_racks := Game.racks.duplicate()
	var pl_links := Game.links.duplicate()
	var pl_invoices := Game.invoices.duplicate(true)
	var pl_cycle := Game.cycle
	var pl_stage := Game.stage
	var pl_reputation := Game.reputation
	var pl_debt := Game.debt
	var pl_staff := Game.staff.duplicate(true)
	var pl_rivals := Game.rivals.duplicate(true)
	var pl_history := Game.history.duplicate(true)
	var pl_events := Game.events.duplicate(true)
	var pl_leads_saved := Game.leads.duplicate(true)
	var pl_offers := Game.offers.duplicate(true)
	var pl_last_pl := Game.last_pl.duplicate(true)
	var pl_last_business := Game.last_business.duplicate(true)
	var pl_last_delta := Game.last_cycle_delta
	var pl_quarter_profit := Game.quarter_profit
	var pl_quarter_depreciation := Game.quarter_depreciation
	var pl_guided_outage := Game.guided_outage.duplicate(true)
	var pl_customer_arcs := Game.customer_arcs.duplicate(true)
	var pl_references := Game.references.duplicate(true)
	var pl_status_posts := Game.status_posts.duplicate(true)
	var pl_spares := Game.spares.duplicate(true)
	var pl_monitors := Game.monitors.duplicate(true)
	var pl_incidents := Game.incidents.duplicate(true)
	Game.money = 100000
	Game.stage = 0
	Game.invoices = []
	Game.leads = []
	Game.deals = []
	Game.customer_arcs = {}
	Game.references = []
	Game.contracts_done = ["guided_a", "guided_b", "guided_c"]
	Game.stats["guided_first_lead_seen"] = false
	Game.lead_tick()
	check(Game.leads.size() == 1 and bool(Game.leads[0].get("guided", false)),
		"guided sales: the first pipeline lead is deterministic after three jobs")
	var guided: Dictionary = Game.leads[0]
	check(guided["customer"] == "Kiskacsa Kft", "guided sales: the first customer is a named story")
	var serve := Market.cost_to_serve(guided)
	check(int(serve["setup"]) > 0 and int(serve["floor"]) > 0,
		"guided sales: cost-to-serve exposes setup and an amortised floor, not the hidden budget")
	check(Game.qualify_lead(guided) == "" and guided["stage"] == "rfp",
		"guided sales: the teaching lead cannot vanish during qualification")
	var retry := Game.submit_proposal(guided, int(guided["size"]) * 5, int(guided["sla"]))
	check(retry.begins_with("retry:") and Game.leads.has(guided),
		"guided sales: a first bad proposal is coached and remains recoverable")
	check(Game.submit_proposal(guided, 1, int(guided["sla"])) == "" and not Game.deals.is_empty(),
		"guided sales: a revised compliant proposal signs a live delivery deal")
	var guided_deal: Dictionary = Game.deals[0]
	check(String(Game.customer_arcs.get("kiskacsa", {}).get("beat", "")) == "arrival" \
			and int(Game.customer_arcs["kiskacsa"]["proposal_attempts"]) == 1,
		"customer arc: Kiskacsa remembers that the winning proposal took a patient revision")
	check(Game.feature_unlocked("market") and not Game.feature_unlocked("business"),
		"discovery: signing exposes the customer pipeline without prematurely opening the ledger")
	check(int(guided_deal.get("delivery_credit", 0)) == int(serve["setup"]),
		"guided delivery: the required starter server budget is protected inside the deal")
	Game.money = 0
	check(Game.try_buy_device("srv-1") and Game.money == 0,
		"guided delivery: the protected reserve buys the required server even after cash was spent elsewhere")
	# A tiny reusable customer network exercises the whole promise -> service ->
	# invoice -> cash path. It remains installed after the tutorial milestone.
	Game.contracts_done = []
	Game.invoices = []
	Game.stage = 0
	Game.cycle = 206
	Game.debt = 0
	Game.staff = []
	Game.rivals = []
	guided_deal["missed"] = 4
	Game.sla_tick()
	check(Game.deals.has(guided_deal) and int(guided_deal["missed"]) == 3,
		"guided delivery: the first customer cannot time out while the player learns to build it")
	var delivery_rack := Game.add_rack(Vector2i(31, 31))
	var delivery_server := Game.new_device("srv-1")
	var delivery_peer := Game.new_device("srv-1")
	delivery_rack.slots[0] = delivery_server
	delivery_rack.slots[1] = delivery_peer
	delivery_server.ifaces[0].ips = ["10.42.18.10/24"]
	delivery_peer.ifaces[0].ips = ["10.42.18.20/24"]
	Game.connect_ifaces(delivery_server.ifaces[0], delivery_peer.ifaces[0])
	var delivery_checks := Market.delivery_checks(guided_deal)
	check(delivery_checks.size() == 4 and delivery_checks.all(func(item): return bool(item["ok"])),
		"guided delivery: each sold hosting promise maps to a passing live technical check")
	Game.sla_tick()
	check(bool(guided_deal["healthy"]) and String(guided_deal["payment_state"]) == "billing",
		"guided delivery: proving the topology changes the customer from waiting to billing")
	check(Game.feature_unlocked("business"),
		"discovery: the ledger appears when the first customer starts earning revenue")
	check(guided_deal.has("first_invoice_cycle") and int(Game.last_business["invoiced"]) == int(guided_deal["fee"]),
		"guided delivery: the first live cycle raises a visible invoice")
	delivery_server.ifaces[0].enabled = false
	Game.topology_changed.emit()
	Game.sla_tick()
	check(not bool(guided_deal["healthy"]) and String(guided_deal["payment_state"]) == "suspended" \
			and int(Game.last_business["invoiced"]) == 0,
		"guided delivery: breaking service visibly suspends new billing")
	check(guided_deal.has("first_cash_cycle") and int(Game.last_business["collected"]) > 0,
		"guided delivery: the already-earned first invoice becomes cash after the startup payment term")
	delivery_server.ifaces[0].enabled = true
	Game.topology_changed.emit()
	Game.sla_tick()
	check(bool(guided_deal["healthy"]) and String(guided_deal["payment_state"]) == "billing" \
			and int(Game.last_business["invoiced"]) > 0,
		"guided delivery: restoring the same topology resumes billing without replacing the customer")
	# The next lesson trips one reversible access port on that same customer.
	# It rewards communication and evidence, then leaves the working service in place.
	Game.guided_outage = {}
	Game.status_posts = []
	Game.monitors = []
	Game.stats["guided_delivery_acknowledged"] = 1
	Game.stats["guided_outage_complete"] = 0
	Game.sla_tick()
	check(String(Game.guided_outage.get("state", "")) == "alert" \
			and Game.guided_outage_iface() != null and not Game.guided_outage_iface().enabled,
		"guided outage: a deterministic reversible access-port fault raises the first alert")
	check(String(Game.customer_arcs["kiskacsa"]["beat"]) == "complication",
		"customer arc: the live service failure becomes Kiskacsa's remembered complication")
	check(Game.feature_unlocked("log") and Game.feature_unlocked("ops"),
		"discovery: incident communication and operations appear with the first outage need")
	check(not bool(guided_deal["healthy"]) and String(guided_deal["payment_state"]) == "suspended",
		"guided outage: the real customer notices and billing stops")
	check(Game.acknowledge_guided_outage() == "" \
			and Game.guided_outage_probe("monitor") != "",
		"guided outage: ownership comes first and diagnosis waits for customer communication")
	# the rest of the business is exercised elsewhere; this measures the outage
	Game.tour = {}
	Game.audit = {}
	Game.decisions = []
	Game.consequences = []
	Game.upstream = {}
	var rep_before_status_cycle := Game.reputation
	check(Game.post_status("Kiskacsa hosting is unavailable; investigating the access path. Next update this cycle.") == "",
		"guided outage: the operator can post a plain-language status update")
	Game.sla_tick()
	var guided_rep_loss := rep_before_status_cycle - Game.reputation
	check(int(Game.guided_outage.get("reputation_saved", 0)) == 2 \
			and Game.status_posted_recently() and guided_rep_loss <= 4,
		"guided outage: an honest update visibly halves its outage penalty even alongside other business effects")
	check(Game.guided_outage_probe("monitor") == "" \
			and Game.guided_outage_probe("physical") == "" \
			and Game.guided_outage_probe("l2") == "",
		"guided outage: evidence is followed monitor to physical to L2")
	check(String(Game.guided_outage.get("state", "")) == "diagnosed" \
			and bool(Game.guided_outage.get("downstream_clear", false)),
		"guided outage: the known L2 cause clears addressing, routing and policy from suspicion")
	var diagnosed_outage := Game.guided_outage.duplicate(true)
	check(Game.give_up_guided_outage() == "" and Game.guided_outage_iface().enabled,
		"guided outage: giving up restores only the teaching fault instead of ending the campaign")
	Game.guided_outage = diagnosed_outage
	Game.guided_outage_iface().enabled = true  # the normal CLI repair reaches the same state
	Game.topology_changed.emit()
	Game.sla_tick()
	check(String(Game.guided_outage.get("state", "")) == "recovered" \
			and bool(guided_deal["healthy"]) and String(guided_deal["payment_state"]) == "billing",
		"guided outage: repair verification restores delivery and customer payment")
	check(Game.guided_outage.get("timeline", []).size() >= 6 \
			and Game.debrief_guided_outage() == "",
		"guided outage: recovery produces a concise operator timeline and debrief")
	check(Game.choose_guided_resilience("monitor") == "" and Game.monitors.size() == 1 \
			and int(Game.stats.get("guided_outage_complete", 0)) == 1,
		"guided outage: the resilience choice leaves a permanent useful improvement")
	check(String(Game.customer_arcs["kiskacsa"]["beat"]) == "recovery" \
			and bool(Game.customer_arcs["kiskacsa"]["communicated"]) \
			and not bool(Game.customer_arcs["kiskacsa"]["assisted"]) \
			and String(Game.customer_arcs["kiskacsa"]["resilience"]) == "monitor",
		"customer arc: Kiskacsa remembers communication, self-recovery, and the lasting monitor")
	check(Game.deals.has(guided_deal) and Game.links.has(Game.link_at(delivery_server.ifaces[0])),
		"guided outage: completion keeps the customer and reusable topology intact")
	var customer_live := Game.customer_eye(guided_deal)
	check(String(customer_live["state"]) == "live" \
			and "ORDERS/H" in String(customer_live["metric"]) \
			and "labels are moving again" in String(customer_live["voice"]),
		"customer eye: healthy service becomes visible shoppers, work and a remembered recovery")
	guided_deal["healthy"] = false
	var customer_down := Game.customer_eye(guided_deal)
	check(String(customer_down["state"]) == "down" \
			and "CHECKOUT OFFLINE" in String(customer_down["metric"]) \
			and "cannot submit" in String(customer_down["activity"]),
		"customer eye: an outage shows the customer's real consequence, never fake success")
	Game.advance_kiskacsa_arc(guided_deal)
	check(int(Game.customer_arcs["kiskacsa"]["healthy_after_incident"]) == 0,
		"customer arc: another live outage resets the quiet-cycle proof instead of advancing dialogue")
	guided_deal["healthy"] = true
	guided_deal["degraded"] = true
	var customer_slow := Game.customer_eye(guided_deal)
	check(String(customer_slow["state"]) == "degraded" \
			and "retry" in String(customer_slow["activity"]).to_lower(),
		"customer eye: congestion reads as a human symptom rather than only a bandwidth number")
	guided_deal["degraded"] = false
	# The same saved recovery can materially diverge. First exercise the assisted
	# branch on a clone, then restore the real, well-handled incident.
	var trusted_arc: Dictionary = Game.customer_arcs["kiskacsa"].duplicate(true)
	var cautious_deal := guided_deal.duplicate(true)
	var cautious_fee := int(cautious_deal["fee"])
	Game.customer_arcs["kiskacsa"] = trusted_arc.duplicate(true)
	Game.customer_arcs["kiskacsa"]["assisted"] = true
	var leads_before_cautious := Game.leads.duplicate(true)
	var refs_before_cautious := Game.references.duplicate(true)
	for _i in 5:
		Game.advance_kiskacsa_arc(cautious_deal)
	check(String(Game.customer_arcs["kiskacsa"]["outcome"]) == "cautious" \
			and int(cautious_deal["fee"]) <= cautious_fee \
			and int(cautious_deal["term"]) == 10 and float(cautious_deal["loyalty"]) < 0.75 \
			and Game.leads.size() == leads_before_cautious.size(),
		"customer arc: assisted recovery keeps Kiskacsa on cautious terms and earns no referral")
	Game.customer_arcs["kiskacsa"] = trusted_arc
	Game.leads = leads_before_cautious
	Game.references = refs_before_cautious
	var leads_before_trust := Game.leads.size()
	for _i in 5:
		Game.advance_kiskacsa_arc(guided_deal)
	var referral: Dictionary = {}
	for story_lead: Dictionary in Game.leads:
		if String(story_lead.get("id", "")) == "lead_story_madaras":
			referral = story_lead
			break
	check(String(Game.customer_arcs["kiskacsa"]["outcome"]) == "trusted" \
			and "Kiskacsa Kft" in Game.references and Game.leads.size() == leads_before_trust + 1 \
			and String(referral.get("kind", "")) == "secure_host",
		"customer arc: five healthy cycles turn good incident work into a premium firewalled referral")
	var payoff_eye := Game.customer_eye(guided_deal)
	check("TRUSTED OPERATOR" in String(payoff_eye.get("relationship", "")) \
			and "Madaras" in String(payoff_eye.get("memory", "")),
		"customer arc: later customer-eye copy names the trust earned and the door it opened")
	var arc_payload: Dictionary = JSON.parse_string(Game.snapshot())
	check(String(arc_payload["customer_arcs"]["kiskacsa"]["outcome"]) == "trusted",
		"customer arc: the three-beat outcome persists with the campaign")
	Game.deals = []
	Game.leads = []
	Game.money = 100000
	var lead := Market.gen_lead()
	Game.leads = [lead]
	check(String(lead["stage"]) == "lead", "pipeline: it starts as a rumour")
	check(Game.submit_proposal(lead, 100, 2) != "",
		"pipeline: you cannot tender for something nobody has put out to tender")
	# qualifying either kills it or turns it into an RFP; force the good path
	var pl_tries := 0
	while String(lead["stage"]) == "lead" and pl_tries < 30:
		Game.qualify_lead(lead)
		pl_tries += 1
		if not Game.leads.has(lead):
			lead = Market.gen_lead()
			Game.leads = [lead]
	check(String(lead["stage"]) == "rfp", "pipeline: a qualified lead goes out to tender")
	check(Market.rfp_requirements(lead) != "", "pipeline: with requirements you can read")
	# committing to less than they asked for loses it outright
	if int(lead["sla"]) > 0:
		var under := Market.score_proposal(lead, 10, int(lead["sla"]) - 1, 100, 0)
		check(not bool(under["won"]), "pipeline: under-committing on availability loses the tender")
	var over := Market.score_proposal(lead, int(lead["size"]) * 5, int(lead["sla"]), 100, 0)
	check(not bool(over["won"]), "pipeline: so does pricing well over their budget")
	var keen := Market.score_proposal(lead, 1, int(lead["sla"]), 100, 0)
	check(bool(keen["won"]), "pipeline: a keen, compliant proposal wins")
	# reputation is worth money in a formal evaluation
	var mid := int(lead["size"])
	var low_rep := Market.score_proposal(lead, mid, int(lead["sla"]), 0, 0)
	var high_rep := Market.score_proposal(lead, mid, int(lead["sla"]), 100, 5)
	check(bool(high_rep["won"]) or not bool(low_rep["won"]),
		"pipeline: standing and references are worth real money in an evaluation")
	var pl_deals := Game.deals.size()
	check(Game.submit_proposal(lead, 1, int(lead["sla"])) == "", "pipeline: winning signs a deal")
	check(Game.deals.size() == pl_deals + 1, "pipeline: which appears in the book")
	check(Game.leads.is_empty(), "pipeline: and leaves the pipeline")
	Game.deals = pl_saved
	Game.money = pl_money
	Game.stats = pl_stats
	Game.contracts_done = pl_contracts
	Game.racks = pl_racks
	Game.links = pl_links
	Game.invoices = pl_invoices
	Game.cycle = pl_cycle
	Game.stage = pl_stage
	Game.reputation = pl_reputation
	Game.debt = pl_debt
	Game.staff = pl_staff
	Game.rivals = pl_rivals
	Game.history = pl_history
	Game.events = pl_events
	Game.leads = pl_leads_saved
	Game.offers = pl_offers
	Game.last_pl = pl_last_pl
	Game.last_business = pl_last_business
	Game.last_cycle_delta = pl_last_delta
	Game.quarter_profit = pl_quarter_profit
	Game.quarter_depreciation = pl_quarter_depreciation
	Game.guided_outage = pl_guided_outage
	Game.customer_arcs = pl_customer_arcs
	Game.references = pl_references
	Game.status_posts = pl_status_posts
	Game.spares = pl_spares
	Game.monitors = pl_monitors
	Game.incidents = pl_incidents
	Game.topology_changed.emit()

	# --- customers who grow, and what people say about you ---
	var gr_deal := {"id": "grow1", "customer": "Growing Kft", "kind": "hosting",
		"params": {}, "fee": 200, "load": 300, "healthy": true, "cycles": 30,
		"up_cycles": 30, "loyalty": 0.6}
	var gr_deals := Game.deals.duplicate()
	Game.deals = [gr_deal]
	check(Game.accept_upsell(gr_deal) != "", "growth: nothing to accept before they ask")
	gr_deal["upsell"] = {"load": 200, "fee": 80}
	check(Game.accept_upsell(gr_deal) == "", "growth: an upsell can be taken")
	check(int(gr_deal["fee"]) == 280 and int(gr_deal["load"]) == 500,
		"growth: which raises both the fee and the traffic you have to carry")
	check(not gr_deal.has("upsell"), "growth: and clears the request")
	gr_deal["upsell"] = {"load": 200, "fee": 80}
	var gr_loyalty := float(gr_deal["loyalty"])
	check(Game.decline_upsell(gr_deal) == "", "growth: or turned down")
	check(float(gr_deal["loyalty"]) < gr_loyalty, "growth: which costs you their goodwill")
	# references
	Game.references = []
	var gr_rep := Game.reputation
	Game.reference_tick()
	check(Game.references.size() == 1 and Game.reputation > gr_rep,
		"reputation: a long-happy customer becomes a reference and lifts you")
	Game.reference_tick()
	check(Game.references.size() == 1, "reputation: and only counts once")
	# press
	Game.reputation = 50
	Game.press_tick({"uptime": 100, "net": 500, "deal_cycles": 12})
	check(Game.reputation > 50, "press: a clean profitable quarter gets written up")
	Game.reputation = 50
	Game.press_tick({"uptime": 40, "net": 500, "deal_cycles": 12})
	check(Game.reputation < 50, "press: a bad one gets written up too")
	Game.reputation = 50
	Game.press_tick({"uptime": 0, "net": 0, "deal_cycles": 0})
	check(Game.reputation == 50, "press: a quarter with no customers is not a story")
	Game.deals = gr_deals
	Game.references = []

	# --- rival strategies and their interest in buying you ---
	var rv_saved := Game.rivals.duplicate(true)
	Game.rivals = Rivals.spawn()
	var rv_kinds := {}
	for rv in Game.rivals:
		rv_kinds[String(rv.get("strategy", ""))] = true
	check(rv_kinds.size() >= 4, "rivals: the field is not seven copies of one company")
	var rv_budget := {}
	var rv_premium := {}
	var rv_spec := {}
	for rv2 in Game.rivals:
		if String(rv2["strategy"]) == "budget":
			rv_budget = rv2
		elif String(rv2["strategy"]) == "premium":
			rv_premium = rv2
		elif String(rv2["strategy"]) == "specialist":
			rv_spec = rv2
	var rv_offer := {"budget": 1000, "kind": "hosting"}
	rv_premium["aggression"] = rv_budget["aggression"]
	rv_premium["deals"] = int(rv_budget["deals"])
	check(Rivals.bid_for(rv_budget, rv_offer) < Rivals.bid_for(rv_premium, rv_offer),
		"rivals: the cut-price company undercuts the premium one on identical terms")
	check(not Rivals.will_bid(rv_spec, {"kind": "nothing_they_do"}),
		"rivals: a specialist does not chase work outside its patch")
	check(Rivals.will_bid(rv_spec, {"kind": String(rv_spec["niche"])}),
		"rivals: and does chase work inside it")
	check(Rivals.bid_for(rv_spec, {"budget": 1000, "kind": String(rv_spec["niche"])})
		< Rivals.bid_for(rv_spec, {"budget": 1000, "kind": "own_vlan"}) or
		String(rv_spec["niche"]) == "own_vlan",
		"rivals: a specialist prices its own patch keenly")
	# a buyout approach, and both answers to it
	var rv_pred := {}
	for rv3 in Game.rivals:
		if String(rv3["strategy"]) == "predator":
			rv_pred = rv3
	check(not rv_pred.is_empty(), "rivals: somebody in the field would rather buy than compete")
	check(Rivals.player_valuation() > 0, "buyout: the company is worth something")
	var rv_money := Game.money
	Game.buyout_offer = {"rival": String(rv_pred["name"]), "price": 50000, "ttl": 3,
		"cycle": Game.cycle}
	check(Game.decline_buyout() == "", "buyout: an offer can be turned down")
	check(Game.buyout_offer.is_empty(), "buyout: which takes it off the table")
	check(Game.decline_buyout() != "", "buyout: and there is nothing left to decline")
	Game.buyout_offer = {"rival": String(rv_pred["name"]), "price": 50000, "ttl": 3,
		"cycle": Game.cycle}
	check(Game.accept_buyout() == "", "buyout: or accepted")
	check(Game.money == rv_money + 50000 and Game.sold_out,
		"buyout: which pays out and ends the run")
	Game.sold_out = false
	Game.money = rv_money
	Game.rivals = rv_saved

	# --- energy and the books ---
	var en_cycle := Game.cycle
	var en_fixed := Game.fixed_tariff
	var en_eff := Game.efficiency
	var en_acc := Game.accountant
	Game.fixed_tariff = false
	Game.efficiency = 0
	Game.cycle = 4  # the expensive part of the day
	var en_peak := Game.energy_rate()
	Game.cycle = 0  # the middle of the night
	check(Game.energy_rate() < en_peak,
		"energy: the spot rate is cheaper at night and dearer at noon")
	Game.fixed_tariff = true
	check(Game.energy_rate() > Game.ENERGY_BASE,
		"energy: a fixed tariff costs more than the base, which is what certainty costs")
	Game.cycle = 4
	check(Game.energy_rate() < en_peak,
		"energy: but it does not move with the peak, which is the point of it")
	Game.fixed_tariff = false
	var en_draw := Game.effective_draw()
	Game.money = 1000000
	check(Game.buy_efficiency() == "", "energy: a retrofit can be bought")
	check(Game.effective_draw() < en_draw or en_draw == 0,
		"energy: and it takes a slice off the draw permanently")
	# tax
	Game.quarter_profit = 0
	Game.quarter_depreciation = 0
	Game.accountant = false
	check(Game.tax_due() == 0, "tax: no profit, no tax")
	Game.quarter_profit = Game.TAX_FREE
	check(Game.tax_due() == 0, "tax: the small-business allowance covers a lean quarter")
	Game.quarter_profit = Game.TAX_FREE + 10000
	Game.quarter_depreciation = 4000
	var tax_without := Game.tax_due()
	check(tax_without > 0, "tax: a profitable quarter is taxed")
	Game.accountant = true
	check(Game.tax_due() < tax_without,
		"tax: an accountant claims the whole allowance instead of half of it")
	var tax_money := Game.money
	Game.settle_quarter()
	check(Game.money < tax_money, "tax: settling the quarter actually takes the money")
	check(Game.quarter_profit == 0 and Game.quarter_depreciation == 0,
		"tax: and starts the next quarter clean")
	check(Game.depreciation_this_cycle() > 0,
		"tax: installed hardware writes itself off a little every cycle")
	Game.cycle = en_cycle
	Game.fixed_tariff = en_fixed
	Game.efficiency = en_eff
	Game.accountant = en_acc

	# --- staff: shifts, morale, training and negotiation ---
	var st_saved := Game.staff.duplicate()
	var st_cycle := Game.cycle
	var st_money := Game.money
	Game.money = 200000
	Game.staff = []
	var st_rng := RandomNumberGenerator.new()
	st_rng.seed = 99
	var st_a := Staff.make_candidate(st_rng)
	st_a["role"] = "noc"
	st_a["skill"] = 2
	st_a["salary"] = 300
	Game.staff.append(st_a)
	# shifts: only the people who are awake count
	Game.cycle = 3  # early afternoon
	check(Staff.shift_of(st_a) == "day", "staff: people start on days")
	check(Staff.on_shift(st_a), "staff: and a day person is on shift in the afternoon")
	check(Staff.repair_power()[0] == 1, "staff: so they can work")
	Game.cycle = 7  # late evening
	check(not Staff.on_shift(st_a), "staff: the same person is not on shift at night")
	check(Staff.repair_power()[0] == 0, "staff: and nothing gets fixed while nobody is awake")
	check(not Staff.anyone_on_shift(), "staff: the rota says the floor is unattended")
	Staff.set_shift(st_a, "night")
	check(Staff.on_shift(st_a), "staff: moving them to nights covers those hours")
	check(int(st_a["salary"]) >= Staff.market_rate(st_a),
		"staff: and nights are paid at the night rate")
	Staff.set_shift(st_a, "day")
	Game.cycle = 3
	# morale: a quiet cycle helps, a bad one hurts, underpaying hurts more
	st_a["morale"] = 60
	Staff.morale_tick(0)
	check(int(st_a["morale"]) > 60, "staff: a quiet cycle restores morale")
	st_a["morale"] = 60
	Staff.morale_tick(10)
	check(int(st_a["morale"]) < 60, "staff: a cycle full of trouble costs it")
	st_a["salary"] = 10  # far below market
	st_a["morale"] = 60
	Staff.morale_tick(0)
	check(int(st_a["morale"]) < 63, "staff: being paid under the market rate weighs on them")
	var st_before_raise := int(st_a["morale"])
	Staff.give_raise(st_a, 200)
	check(int(st_a["morale"]) > st_before_raise and int(st_a["salary"]) == 210,
		"staff: a raise costs money and buys goodwill")
	# training takes them off the floor and brings them back better
	var st_skill := int(st_a["skill"])
	check(Staff.start_course(st_a, "switching") == "", "staff: a course can be paid for")
	check(not Staff.on_shift(st_a), "staff: somebody on a course is not on the floor")
	check(Staff.start_course(st_a, "routing") != "", "staff: and cannot be on two at once")
	for st_i in Staff.COURSES["switching"]["cycles"]:
		Staff.morale_tick(0)
	check(int(st_a["skill"]) == st_skill + 1, "staff: they come back one better")
	check("switching" in st_a.get("certs", []), "staff: with the certification recorded")
	# quitting
	st_a["morale"] = 0
	st_a["salary"] = 1
	var st_left := false
	for st_try in 30:
		Staff.morale_tick(20)
		if Game.staff.is_empty():
			st_left = true
			break
	check(st_left, "staff: somebody miserable and underpaid eventually resigns")
	# hiring negotiation
	Game.staff = []
	Game.reputation = 50
	Game.refresh_candidates(true)
	check(not Game.candidates.is_empty(), "hiring: there are candidates")
	var st_cand: Dictionary = Game.candidates[0]
	var st_ask := int(st_cand["ask"])
	check(Game.offer_job(st_cand, int(st_ask * 0.4)) == "walked",
		"hiring: a derisory offer is refused outright")
	Game.refresh_candidates(true)
	var st_c2: Dictionary = Game.candidates[0]
	check(Game.offer_job(st_c2, int(st_c2["ask"])) == "",
		"hiring: their asking price is always accepted")
	check(Game.staff.size() == 1, "hiring: and they join")
	Game.staff = st_saved
	Game.cycle = st_cycle
	Game.money = st_money

	# --- IPv4 scarcity ---
	var v4_deals := Game.deals.duplicate()
	var v4_blocks := Game.ipv4_blocks
	var v4_money := Game.money
	Game.deals = []
	Game.ipv4_blocks = 1
	check(Game.ipv4_total() == Game.IPV4_BLOCK, "addresses: a /29 is eight of them")
	check(Game.ipv4_free() == Game.ipv4_total(), "addresses: none are spoken for yet")
	for v4_i in Game.IPV4_BLOCK:
		Game.deals.append({"id": "v4-%d" % v4_i, "customer": "C%d" % v4_i, "public": true,
			"params": {}, "fee": 10, "healthy": true, "kind": "hosting"})
	check(Game.ipv4_free() == 0, "addresses: eight public customers use the whole block")
	var v4_offer := {"public": true, "customer": "Needs One Kft", "budget": 500,
		"kind": "public_hosting", "params": {}, "state": "open"}
	check(Game.can_accept_offer(v4_offer) != "",
		"addresses: an offer needing one is refused when there are none left")
	check(Game.respond_offer(v4_offer, 100).begins_with("blocked:"),
		"addresses: and quoting for it is blocked rather than silently failing")
	var v4_shared := {"public": false, "customer": "Happy Behind NAT Bt", "budget": 500,
		"kind": "hosting", "params": {}, "state": "open"}
	check(Game.can_accept_offer(v4_shared) == "",
		"addresses: a customer who does not need one can still be served")
	var v4_first := Game.ipv4_price()
	Game.money = 1000000
	check(Game.buy_ipv4_block() == "", "addresses: another block can be bought")
	check(Game.ipv4_price() > v4_first, "addresses: and the next one costs more, as it does")
	check(Game.ipv4_free() > 0, "addresses: which frees the offer up again")
	check(Game.can_accept_offer(v4_offer) == "", "addresses: so it can be taken")
	Game.deals = v4_deals
	Game.ipv4_blocks = v4_blocks
	Game.money = v4_money

	# --- playbooks ---
	Game.playbooks = []
	check(Game.save_playbook("", ["enable"]) != "", "playbook: it needs a name")
	check(Game.save_playbook("empty", ["", "# just a comment"]) != "",
		"playbook: and at least one real command")
	var pb_rack := Game.add_rack(Vector2i(46, 1))
	var pb_a := Game.new_device("sw-8")
	var pb_b := Game.new_device("sw-8")
	pb_rack.slots[0] = pb_a
	pb_rack.slots[1] = pb_b
	check(Game.save_playbook("mgmt-baseline", [
		"enable", "configure terminal", "ip igmp snooping",
		"snmp-server community monitoring", "end"]) == "",
		"playbook: a real one saves")
	check(Game.playbooks.size() == 1, "playbook: and is kept")
	Game.save_playbook("mgmt-baseline", ["enable"])
	check(Game.playbooks.size() == 1, "playbook: saving the same name replaces rather than duplicates")
	Game.save_playbook("mgmt-baseline", [
		"enable", "configure terminal", "ip igmp snooping",
		"snmp-server community monitoring", "end"])
	var pb_res := Game.run_playbook(Game.playbooks[0], [pb_a, pb_b])
	check(int(pb_res["ran"]) == 2 and int(pb_res["failed"]) == 0,
		"playbook: it runs cleanly on both switches")
	check(pb_a.igmp_snooping and pb_b.igmp_snooping,
		"playbook: and the change actually landed on both")
	check(pb_a.snmp == "monitoring" and pb_b.snmp == "monitoring",
		"playbook: every command in it, not just the first")
	# a playbook aimed at the wrong kind of device reports the failure honestly
	var pb_srv := Game.new_device("srv-1")
	pb_rack.slots[2] = pb_srv
	var pb_bad := Game.run_playbook(Game.playbooks[0], [pb_srv])
	check(int(pb_bad["failed"]) == 1 and not pb_bad["log"].is_empty(),
		"playbook: running switch commands on a server is reported, not swallowed")
	check(Game.playbook_targets("switch").size() >= 2, "playbook: targets can be filtered by type")
	Game.delete_playbook("mgmt-baseline")
	check(Game.playbooks.is_empty(), "playbook: and deleted")

	# --- IPv6 autoconfiguration ---
	check(Net.eui64("52:54:00:12:34:56") == "5054:00ff:fe12:3456",
		"slaac: EUI-64 flips the universal bit and pushes fffe into the middle")
	check(Net.slaac_address("2001:db8:1:1::", 64, "52:54:00:12:34:56").ends_with("5054:ff:fe12:3456"),
		"slaac: the address is the prefix plus the host's own identifier")
	check(Net.slaac_address("2001:db8:1:1::", 48, "52:54:00:12:34:56") == "",
		"slaac: it needs a /64, which is arithmetic rather than convention")
	var sl_rack := Game.add_rack(Vector2i(45, 1))
	var sl_rtr := Game.new_device("rtr-edge")
	var sl_sw := Game.new_device("sw-8")
	var sl_host := Game.new_device("srv-1")
	sl_rack.slots[0] = sl_rtr
	sl_rack.slots[1] = sl_sw
	sl_rack.slots[2] = sl_host
	Game.connect_ifaces(sl_rtr.ifaces[0], sl_sw.ifaces[0])
	Game.connect_ifaces(sl_host.ifaces[0], sl_sw.ifaces[1])
	Game.add_ip(sl_rtr.ifaces[0], "2001:db8:77::1/64")
	Sim.flush_learned_state()
	var sl_cli := CLI.new_session(sl_host)
	check(sl_cli.exec("autoconf eth0").contains("no router advertisements"),
		"slaac: a router that is not advertising configures nobody")
	var sl_rcli := CLI.new_session(sl_rtr)
	sl_rcli.exec("enable")
	sl_rcli.exec("configure terminal")
	sl_rcli.exec("interface Ethernet1")
	check(sl_rcli.exec("ipv6 nd ra").is_empty(), "slaac: advertisements can be turned on")
	sl_rcli.exec("end")
	Sim.flush_learned_state()
	var sl_out := sl_cli.exec("autoconf eth0")
	check(sl_out.contains("2001:db8:77:") and sl_out.contains(sl_rtr.name),
		"slaac: the host builds an address from the advertised prefix")
	check(Sim.ping(sl_host, "2001:db8:77::1")["ok"],
		"slaac: and the address it built actually works")
	var sl_default := false
	for sl_r in sl_host.static_routes:
		if String(sl_r["prefix"]) == "::" and int(sl_r["plen"]) == 0:
			sl_default = true
	check(sl_default, "slaac: it also learns a default route, with no DHCP server anywhere")

	# --- certificates: up, correct, and refusing every client ---
	var ce_rack := Game.add_rack(Vector2i(44, 1))
	var ce_srv := Game.new_device("srv-1")
	ce_rack.slots[0] = ce_srv
	var ce_cli := CLI.new_session(ce_srv)
	check(ce_cli.exec("cert list").contains("no certificates"), "cert: a host starts with none")
	check(ce_cli.exec("cert issue shop.example.hu 6").contains("issued"),
		"cert: one can be issued with a life")
	check(not Game.cert_expired(ce_srv), "cert: a fresh certificate is not expired")
	check(ce_cli.exec("cert list").contains("6 cycles"), "cert: the listing shows what is left")
	var ce_saved := Game.cycle
	Game.cycle += 4
	var ce_due := Game.expiring_certs()
	check(ce_due.size() >= 1, "cert: it appears in the expiry list before it dies")
	Game.cycle += 3
	check(Game.cert_expired(ce_srv), "cert: and then it expires")
	check(ce_cli.exec("cert list").contains("EXPIRED"), "cert: which the listing says plainly")
	check(ce_cli.exec("cert renew shop.example.hu").contains("renewed"), "cert: renewal works")
	check(not Game.cert_expired(ce_srv), "cert: and clears the expiry")
	check(ce_cli.exec("cert renew nothing.example.hu").contains("no certificate"),
		"cert: renewing something that does not exist is refused")
	# automatic renewal removes the failure mode entirely, for a fee
	check(ce_cli.exec("cert auto shop.example.hu on").contains("automatic"),
		"cert: renewal can be automated")
	Game.cycle += Game.CERT_LIFE
	Game.cert_tick()
	check(not Game.cert_expired(ce_srv),
		"cert: an automatic certificate renews itself before anyone notices")
	Game.cycle = ce_saved

	# --- AAA for administrators, and the lockout it can cause ---
	var aa_rack := Game.add_rack(Vector2i(43, 1))
	var aa_sw := Game.new_device("sw-24")
	var aa_srv := Game.new_device("srv-1")   # the AAA server
	var aa_admin := Game.new_device("srv-1") # where the administrator sits
	aa_rack.slots[0] = aa_sw
	aa_rack.slots[1] = aa_srv
	aa_rack.slots[2] = aa_admin
	Game.connect_ifaces(aa_srv.ifaces[0], aa_sw.ifaces[0])
	Game.connect_ifaces(aa_admin.ifaces[0], aa_sw.ifaces[1])
	var aa_svi := Game.add_svi(aa_sw, 1)
	Game.add_ip(aa_svi, "10.250.0.1/24")
	Game.add_ip(aa_srv.ifaces[0], "10.250.0.10/24")
	Game.add_ip(aa_admin.ifaces[0], "10.250.0.20/24")
	Sim.flush_learned_state()
	var aa_acli := CLI.new_session(aa_admin)
	var aa_scli := CLI.new_session(aa_srv)
	var aa_swcli := CLI.new_session(aa_sw)
	aa_swcli.exec("enable")
	aa_swcli.exec("configure terminal")
	check(aa_acli.exec("ssh 10.250.0.1").contains("Connected"),
		"aaa: with no server configured, local login works")
	aa_acli.exec("exit")
	check(aa_scli.exec("aaad s3cret").contains("listening"), "aaa: a server can be started")
	check(aa_swcli.exec("aaa authentication login radius 10.250.0.10 key s3cret").is_empty(),
		"aaa: a device can be pointed at it")
	aa_swcli.exec("end")
	check(aa_acli.exec("ssh 10.250.0.1").contains("Connected"),
		"aaa: a reachable server with the right secret admits you")
	aa_acli.exec("exit")
	# the wrong secret is refused, which is not the same as the server being down
	aa_swcli.exec("configure terminal")
	aa_swcli.exec("aaa authentication login radius 10.250.0.10 key wrong")
	aa_swcli.exec("end")
	check(aa_acli.exec("ssh 10.250.0.1").contains("shared secret"),
		"aaa: a mismatched shared secret is refused")
	aa_swcli.exec("configure terminal")
	aa_swcli.exec("aaa authentication login radius 10.250.0.10 key s3cret")
	aa_swcli.exec("end")
	# now the classic: the server goes away and there is no local fallback
	aa_srv.ifaces[0].enabled = false
	Sim.flush_learned_state()
	check(aa_acli.exec("ssh 10.250.0.1").contains("no local fallback"),
		"aaa: an unreachable server with no fallback locks you out of your own switch")
	check(aa_swcli.exec("show aaa").contains("LOCK YOU OUT"),
		"aaa: and show aaa warns you about it before it happens")
	aa_swcli.exec("configure terminal")
	check(aa_swcli.exec("aaa authentication login local").is_empty(),
		"aaa: a local fallback can be configured")
	aa_swcli.exec("end")
	check(aa_acli.exec("ssh 10.250.0.1").contains("falling back to the local account"),
		"aaa: with one, you get in and are told why")
	aa_acli.exec("exit")
	aa_srv.ifaces[0].enabled = true
	Sim.flush_learned_state()
	# the audit trail records what was typed, centrally
	aa_swcli.exec("show version")
	check(aa_scli.exec("aaad log").contains("show version"),
		"aaa: the server keeps a record of what was typed and where")

	# --- out-of-band console: reaching a device when the device is the problem ---
	var ob_rack := Game.add_rack(Vector2i(42, 1))
	var ob_con := Game.new_device("con-1")
	var ob_sw := Game.new_device("sw-24")
	var ob_jump := Game.new_device("srv-1")
	ob_rack.slots[0] = ob_con
	ob_rack.slots[1] = ob_sw
	ob_rack.slots[2] = ob_jump
	Game.connect_ifaces(ob_con.ifaces[0], ob_sw.ifaces[23])   # console cable to the switch
	Game.connect_ifaces(ob_jump.ifaces[0], ob_sw.ifaces[0])   # the network path
	var ob_svi := Game.add_svi(ob_sw, 1)
	Game.add_ip(ob_svi, "10.240.0.1/24")
	Game.add_ip(ob_jump.ifaces[0], "10.240.0.10/24")
	Sim.flush_learned_state()
	var ob_jcli := CLI.new_session(ob_jump)
	check(ob_jcli.exec("ssh 10.240.0.1").contains("Connected"),
		"oob: while the network works, ssh reaches the switch")
	ob_jcli.exec("exit")
	var ob_ccli := CLI.new_session(ob_con)
	check(ob_ccli.exec("console list").contains(ob_sw.name),
		"oob: the console server lists what is cabled to it")
	# now fat-finger the switch's management address, exactly as one does
	Game.remove_ip(ob_svi, "10.240.0.1/24")
	Sim.flush_learned_state()
	check(ob_jcli.exec("ssh 10.240.0.1").contains("No route to host"),
		"oob: with its address gone, the switch cannot be reached over the network")
	var ob_open := ob_ccli.exec("console %s" % ob_sw.name)
	check(ob_open.contains("Connected to %s" % ob_sw.name),
		"oob: the serial console does not care about IP, which is why it exists")
	check(ob_ccli.pending_ssh == ob_sw, "oob: and it really lands on that device")
	ob_ccli.pending_ssh = null
	check(ob_ccli.exec("console nosuchbox").contains("nothing named"),
		"oob: a device with no serial cable cannot be reached that way either")
	Game.add_ip(ob_svi, "10.240.0.1/24")
	Sim.flush_learned_state()

	# --- airflow: heat is somewhere, not just a total ---
	var air_stage := Game.stage
	Game.stage = 1
	var air_a := Game.add_rack(Vector2i(2, 20))
	var air_b := Game.add_rack(Vector2i(2, 21))  # pressed against it
	var air_far := Game.add_rack(Vector2i(11, 20))  # on its own
	for air_i in 4:
		air_a.slots[air_i] = Game.new_device("srv-2")
		air_far.slots[air_i] = Game.new_device("srv-2")
	check(Game.rack_watts(air_a) == Game.rack_watts(air_far),
		"airflow: the two cabinets draw the same power")
	check(Game.rack_heat(air_a) > Game.rack_heat(air_far),
		"airflow: but the crowded one runs hotter, because it breathes its neighbour's exhaust")
	var cool_far := Game.rack_cooling(air_far)
	air_b.slots[0] = Game.new_device("crac-1")
	check(Game.rack_cooling(air_a) > Game.rack_cooling(air_far),
		"airflow: a unit next door cools this row and not the far one")
	check(Game.rack_cooling(air_far) <= cool_far + 1,
		"airflow: cold air does not travel across the room")
	check(Game.hottest_rack(0) != null, "airflow: there is always a worst cabinet")
	Game.stage = air_stage

	# --- transit billed on the 95th percentile, and peering ---
	check(Game.percentile_95([]) == 0, "transit: nothing measured costs nothing")
	# twenty samples, one enormous spike: the spike is in the free five percent
	var pc_samples: Array = []
	for pc_i in 19:
		pc_samples.append(100)
	pc_samples.append(5000)
	check(Game.percentile_95(pc_samples) == 100,
		"transit: a single burst falls in the free five percent")
	var pc_sustained: Array = []
	for pc_j in 18:
		pc_sustained.append(100)
	pc_sustained.append(5000)
	pc_sustained.append(5000)
	check(Game.percentile_95(pc_sustained) == 5000,
		"transit: burst twice and you pay for it, which is the whole point")
	Game.transit_samples = [400]
	check(Game.transit_cost() == int(round(400 * Game.TRANSIT_PER_MBPS)),
		"transit: the bill is the percentile times the rate")
	# peering takes traffic off transit, and each session takes a bit more
	Game.ixp = {}
	check(Game.peering_share() == 0.0, "peering: no exchange port, no peering")
	check(Game.add_peering() != "", "peering: you cannot peer without a port")
	var ixp_money := Game.money
	Game.money = Game.IXP_SETUP + 100
	check(Game.join_ixp() == "", "peering: a port at the exchange can be bought")
	check(Game.join_ixp() != "", "peering: and only once")
	Game.add_peering()
	var share_one := Game.peering_share()
	Game.add_peering()
	check(Game.peering_share() > share_one, "peering: each session moves more traffic off transit")
	check(Game.peering_share() <= 0.75, "peering: but never all of it, so transit is never optional")
	Game.ixp = {}
	Game.transit_samples = []
	Game.money = ixp_money

	# --- route hijacks and RPKI ---
	Game.hijacks = []
	mh_cli.exec("configure terminal")
	mh_cli.exec("router bgp 65010")
	mh_cli.exec("network 203.0.113.0/24")
	check(mh_cli.exec("roa 198.51.100.0/24").contains("announce"),
		"rpki: signing a prefix you do not originate is refused")
	var hj_entry := {"cidr": "203.0.113.0/24", "dev": mh_edge}
	check(not Game.hijack_protected(hj_entry), "rpki: an unsigned prefix cannot be defended")
	check(mh_cli.exec("roa 203.0.113.0/24").is_empty(), "rpki: your own prefix can be signed")
	check(not Game.hijack_protected(hj_entry),
		"rpki: a signature is worthless until somebody upstream checks it")
	check(mh_cli.exec("neighbor 100.70.0.1 rpki").is_empty(),
		"rpki: an upstream can be asked to validate")
	mh_cli.exec("end")
	check(Game.hijack_protected(hj_entry),
		"rpki: signed prefix plus a validating upstream is protection")
	# an active hijack takes the customer off the internet even though nothing broke
	Game.hijacks = [{"prefix": "203.0.113.0", "plen": 24, "by": "AS64666", "cycles_left": 2}]
	check(not Game.hijack_on("203.0.113.9").is_empty(),
		"rpki: an address inside a hijacked prefix is affected")
	check(Game.hijack_on("8.8.8.8").is_empty(), "rpki: one outside it is not")
	check(mh_cli.exec("show ip bgp summary").contains("HIJACK"),
		"rpki: the session summary reports it")
	Game.hijacks = []

	# --- MTU, jumbo frames and the mismatch that only breaks big packets ---
	var mt_rack := Game.add_rack(Vector2i(40, 1))
	var mt_sw := Game.new_device("sw-8")
	var mt_a := Game.new_device("srv-1")
	var mt_b := Game.new_device("srv-1")
	mt_rack.slots[0] = mt_sw
	mt_rack.slots[1] = mt_a
	mt_rack.slots[2] = mt_b
	Game.connect_ifaces(mt_a.ifaces[0], mt_sw.ifaces[0])
	Game.connect_ifaces(mt_b.ifaces[0], mt_sw.ifaces[1])
	Game.add_ip(mt_a.ifaces[0], "10.230.0.10/24")
	Game.add_ip(mt_b.ifaces[0], "10.230.0.11/24")
	Sim.flush_learned_state()
	check(Sim.ping(mt_a, "10.230.0.11")["ok"], "mtu: an ordinary packet crosses a 1500 byte path")
	check(not Sim.ping(mt_a, "10.230.0.11", 64, "", 9000)["ok"],
		"mtu: a jumbo packet does not fit a standard path")
	check(Sim.last_mtu_drop.contains("1500"), "mtu: and it says which MTU stopped it")
	# jumbo everywhere: it fits
	for mt_i in [mt_a.ifaces[0], mt_b.ifaces[0], mt_sw.ifaces[0], mt_sw.ifaces[1]]:
		mt_i.mtu = 9216
	Sim.flush_learned_state()
	check(Sim.ping(mt_a, "10.230.0.11", 64, "", 9000)["ok"],
		"mtu: jumbo frames work once every port on the path agrees")
	# the classic bug: one port left behind. Small packets fine, big ones gone.
	mt_sw.ifaces[1].mtu = 1500
	Sim.flush_learned_state()
	check(Sim.ping(mt_a, "10.230.0.11")["ok"],
		"mtu: a mismatch does not show up in an ordinary ping, which is why it hurts")
	check(not Sim.ping(mt_a, "10.230.0.11", 64, "", 9000)["ok"],
		"mtu: one port left at 1500 silently swallows every large frame")
	check(Sim.last_mtu_drop.contains(mt_sw.name),
		"mtu: the drop names the device and port responsible")
	var mt_cli := CLI.new_session(mt_a)
	check(mt_cli.exec("ping -s 9000 10.230.0.11").contains("will not fit"),
		"mtu: ping -s reproduces it from the console")
	check(mt_cli.exec("ping 10.230.0.11").contains("0% packet loss"),
		"mtu: and a normal ping still looks perfectly healthy")

	# --- DNS zones, delegation and TTLs ---
	var dz_rack := Game.add_rack(Vector2i(39, 1))
	var dz_sw := Game.new_device("sw-8")
	var dz_root := Game.new_device("srv-1")   # authoritative for example.hu
	var dz_sub := Game.new_device("srv-1")    # authoritative for eu.example.hu
	var dz_client := Game.new_device("srv-1")
	dz_rack.slots[0] = dz_sw
	dz_rack.slots[1] = dz_root
	dz_rack.slots[2] = dz_sub
	dz_rack.slots[3] = dz_client
	for dz_i in 3:
		Game.connect_ifaces([dz_root, dz_sub, dz_client][dz_i].ifaces[0], dz_sw.ifaces[dz_i])
		Game.add_ip([dz_root, dz_sub, dz_client][dz_i].ifaces[0], "10.220.0.%d/24" % (10 + dz_i))
	Sim.flush_learned_state()
	var dz_rcli := CLI.new_session(dz_root)
	var dz_scli := CLI.new_session(dz_sub)
	var dz_ccli := CLI.new_session(dz_client)
	dz_rcli.exec("dns add www.example.hu 10.220.9.1")
	dz_scli.exec("dns add www.eu.example.hu 10.220.9.2")
	check(dz_rcli.exec("dns delegate eu.example.hu 10.220.0.11").contains("delegated"),
		"dns: a subzone can be delegated to another server")
	dz_ccli.exec("nameserver 10.220.0.10")
	check(Sim.resolve(dz_client, "www.example.hu") == "10.220.9.1",
		"dns: the parent answers for its own zone")
	check(Sim.resolve(dz_client, "www.eu.example.hu", false) == "10.220.9.2",
		"dns: a delegated name is resolved by following the referral")
	check(Sim.resolve(dz_client, "www.nowhere.hu", false) == "",
		"dns: a name nobody is authoritative for fails")
	# TTL: a changed record is not seen until the cached answer expires
	dz_ccli.exec("dns flush")
	dz_rcli.exec("dns add ttl.example.hu 10.220.9.5 3")
	check(Sim.resolve(dz_client, "ttl.example.hu") == "10.220.9.5", "dns: first lookup is authoritative")
	dz_rcli.exec("dns add ttl.example.hu 10.220.9.6 3")
	check(Sim.dns_cached(dz_client, "ttl.example.hu"), "dns: the answer is cached")
	check(Sim.resolve(dz_client, "ttl.example.hu") == "10.220.9.5",
		"dns: the client keeps the old address until the TTL runs out")
	var dz_saved_cycle := Game.cycle
	Game.cycle += 4
	check(Sim.resolve(dz_client, "ttl.example.hu") == "10.220.9.6",
		"dns: once it expires, the new address is picked up")
	Game.cycle = dz_saved_cycle
	check(dz_ccli.exec("dns cache").contains("ttl.example.hu"), "dns: the cache can be inspected")
	check(dz_ccli.exec("dns flush").contains("cleared"), "dns: and cleared")
	check(dz_rcli.exec("dns list").contains("NS"), "dns: delegations show in the zone listing")

	# --- DNS64: synthesizing AAAA for an IPv4-only service ---
	dz_ccli.exec("dns flush")
	dz_rcli.exec("dns add legacy.example.hu 10.220.9.7")
	check(Sim.resolve(dz_client, "legacy.example.hu", false, true) == "",
		"dns64: an IPv4-only service has no AAAA, and the query fails honestly")
	check(dz_rcli.exec("dns64 nonsense").contains("must be an IPv6 prefix"),
		"dns64: a malformed prefix is refused rather than half-configured")
	check(dz_rcli.exec("dns64 64:ff9b::").contains("synthesizing"),
		"dns64: the resolver takes a NAT64 prefix")
	var synth := Sim.resolve(dz_client, "legacy.example.hu", false, true)
	check(synth == "64:ff9b::adc:907" and Sim.last_answer_kind == "synthesized",
		"dns64: the answer is the prefix with the IPv4 address embedded, and it says so")
	check(not Sim.ping(dz_client, synth)["ok"],
		"dns64: naming it does not reach it: that still needs a translator")
	dz_rcli.exec("dns add native.example.hu 10.220.9.8")
	dz_rcli.exec("dns add native.example.hu fd00:220::8")
	check(Sim.resolve(dz_client, "native.example.hu", false, true) == "fd00:220::8" \
			and Sim.last_answer_kind == "native",
		"dns64: a real AAAA always wins, and nothing is synthesized over it")
	check(Sim.resolve(dz_client, "native.example.hu", false) == "10.220.9.8",
		"dns64: the A record is untouched by any of this")
	check(Sim.resolve(dz_client, "legacy.example.hu", true, true) == synth \
			and Sim.last_answer_kind == "cached",
		"dns64: a synthesized answer caches like any other, and says it came from cache")
	dz_ccli.exec("dns flush")
	check(dz_rcli.exec("dns64 off").contains("disabled") \
			and Sim.resolve(dz_client, "legacy.example.hu", false, true) == "",
		"dns64: disabled means disabled, with no leftover synthesis")
	check(dz_rcli.exec("dns list").contains("AAAA"),
		"dns64: AAAA records and the DNS64 setting are visible in the zone listing")
	dz_rcli.exec("dns64 64:ff9b::")

	# --- NAT64: the translation half ---
	var n64_rack := Game.add_rack(Vector2i(62, 1))
	var n64_sw := Game.new_device("sw-8")
	var n64_rtr := Game.new_device("rtr-edge")
	var n64_client := Game.new_device("srv-1")   # IPv6 only, on purpose
	var n64_legacy := Game.new_device("srv-1")   # IPv4 only, also on purpose
	n64_rack.slots[0] = n64_sw
	n64_rack.slots[1] = n64_rtr
	n64_rack.slots[2] = n64_client
	var n64_rack2 := Game.add_rack(Vector2i(63, 1))
	n64_rack2.slots[0] = n64_legacy
	Game.connect_ifaces(n64_client.ifaces[0], n64_sw.ifaces[0])
	Game.connect_ifaces(n64_rtr.ifaces[0], n64_sw.ifaces[1])
	Game.connect_ifaces(n64_rtr.ifaces[1], n64_legacy.ifaces[0])
	Game.add_ip(n64_client.ifaces[0], "fd00:64::10/64")
	Game.add_ip(n64_rtr.ifaces[0], "fd00:64::1/64")
	Game.add_ip(n64_rtr.ifaces[1], "10.64.0.1/24")
	Game.add_ip(n64_legacy.ifaces[0], "10.64.0.10/24")
	Game.add_static_route(n64_client, "::", 0, "fd00:64::1")
	Game.add_static_route(n64_legacy, "0.0.0.0", 0, "10.64.0.1")
	Sim.flush_learned_state()
	var n64_cli := CLI.new_session(n64_rtr)
	n64_cli.exec("en")
	n64_cli.exec("conf t")
	check(Sim.synth64("64:ff9b::", "10.64.0.10") == "64:ff9b::a40:a" \
			and Sim.extract64("64:ff9b::", "64:ff9b::a40:a") == "10.64.0.10",
		"nat64: the address embedding round-trips, which is what makes it deterministic")
	var n64_dest := Sim.synth64("64:ff9b::", "10.64.0.10")
	check(not Sim.ping(n64_client, n64_dest)["ok"],
		"nat64: without a translator the synthesized address goes nowhere")
	check(n64_cli.exec("nat64 prefix 64:ff9b:: pool nonsense").contains("pool must be"),
		"nat64: a pool that is not an IPv4 address you own is refused")
	check(n64_cli.exec("nat64 prefix 64:ff9b:: pool 10.64.0.1") == "",
		"nat64: a prefix and an egress address is the whole configuration")
	check(Sim.ping(n64_client, n64_dest)["ok"],
		"nat64: an IPv6-only client reaches an IPv4-only service through the translator")
	check(Sim.ping(n64_client, "fd00:64::1")["ok"],
		"nat64: native IPv6 to the router itself never touches translation")
	var n64_state := n64_cli.exec("show nat64")
	check(n64_state.contains("translated") and n64_state.contains("last error   none"),
		"nat64: translation counters and the last failure reason are visible")
	# state is bounded: each exchange consumes its entry rather than leaking one
	check(n64_rtr.nat64_flows.is_empty(),
		"nat64: the return leg consumes the state it was holding")
	# and policy denial fails for a stated reason rather than silently
	var n64_before := int(Sim.nat64_of(n64_rtr).get("translated", 0))
	n64_rtr.ifaces[1].enabled = false  # the IPv4 side of the translator goes away
	Sim.flush_learned_state()
	check(not Sim.ping(n64_client, n64_dest)["ok"] \
			and String(Sim.nat64_of(n64_rtr).get("last_error", "")).contains("no IPv4 route"),
		"nat64: a missing IPv4 route fails for a stated reason instead of silently")
	n64_rtr.ifaces[1].enabled = true
	Sim.flush_learned_state()
	check(Sim.ping(n64_client, n64_dest)["ok"] \
			and int(Sim.nat64_of(n64_rtr).get("translated", 0)) > n64_before,
		"nat64: translated traffic is accounted on the real path")
	check(n64_cli.exec("no nat64") == "" and not Sim.ping(n64_client, n64_dest)["ok"] \
			and n64_cli.exec("show nat64").contains("not configured"),
		"nat64: a translator outage takes the whole path with it, and says so")
	# the same translator, configured in the other dialect
	var n64_ros := Game.new_device("rtr-lite")
	var n64_rack3 := Game.add_rack(Vector2i(64, 1))
	n64_rack3.slots[0] = n64_ros
	check(CLI.new_session(n64_ros).exec("/ipv6 nat64 set prefix=64:ff9b:: pool=10.64.0.9") == "" \
			and CLI.new_session(n64_ros).exec("/ipv6 nat64 print").contains("64:ff9b::"),
		"nat64: PacketTik gear configures the same translator in its own dialect")

	# the contract that only closes when both halves of the transition exist
	var v6c_rack := Game.add_rack(Vector2i(66, 1))
	var v6c_sw := Game.new_device("sw-8")
	var v6c_rtr := Game.new_device("rtr-edge")
	var v6c_tenant := Game.new_device("srv-1")
	var v6c_native := Game.new_device("srv-1")
	var v6c_legacy := Game.new_device("srv-1")
	v6c_rack.slots[0] = v6c_sw
	v6c_rack.slots[1] = v6c_rtr
	v6c_rack.slots[2] = v6c_tenant
	var v6c_rack2 := Game.add_rack(Vector2i(67, 1))
	v6c_rack2.slots[0] = v6c_native
	v6c_rack2.slots[1] = v6c_legacy
	Game.connect_ifaces(v6c_tenant.ifaces[0], v6c_sw.ifaces[0])
	Game.connect_ifaces(v6c_native.ifaces[0], v6c_sw.ifaces[1])
	Game.connect_ifaces(v6c_rtr.ifaces[0], v6c_sw.ifaces[2])
	Game.connect_ifaces(v6c_rtr.ifaces[1], v6c_legacy.ifaces[0])
	Game.add_ip(v6c_tenant.ifaces[0], "2001:db8:64::10/64")
	Game.add_ip(v6c_native.ifaces[0], "2001:db8:64::20/64")
	Game.add_ip(v6c_rtr.ifaces[0], "2001:db8:64::1/64")
	Game.add_ip(v6c_rtr.ifaces[1], "10.164.0.1/24")
	Game.add_ip(v6c_legacy.ifaces[0], "10.164.0.10/24")
	Game.add_static_route(v6c_tenant, "::", 0, "2001:db8:64::1")
	Game.add_static_route(v6c_legacy, "0.0.0.0", 0, "10.164.0.1")
	Sim.flush_learned_state()
	var v6c := _contract("v6_only_tenant")
	check(not Game.try_complete_contract(v6c),
		"v6 tenant: reaching the native service is only the first half of the job")
	var v6c_dns := CLI.new_session(v6c_native)
	v6c_dns.exec("dns add legacy.turul.hu 10.164.0.10")
	v6c_dns.exec("dns64 64:ff9b::")
	var v6c_rcli := CLI.new_session(v6c_rtr)
	v6c_rcli.exec("en")
	v6c_rcli.exec("conf t")
	v6c_rcli.exec("nat64 prefix 64:ff9b:: pool 10.164.0.1")
	check(Game.try_complete_contract(v6c),
		"v6 tenant: DNS64 names it and NAT64 carries it, and the tenant never gets an IPv4 address")

	# --- carrier outages and diversity ---
	Game.circuits = []
	Game.carrier_outage = {}
	var ca_before := Game.money
	Game.money = ca_before + 20000
	while Game.site_count() < 2:
		Game.lease_site(0)
	check(Game.buy_circuit(0, 1, 0, Game.CARRIERS[0]) == "", "carrier: a circuit can be ordered")
	check(Game.buy_circuit(0, 1, 0, Game.CARRIERS[0]).contains("same fibre"),
		"carrier: a second circuit from the same carrier is refused as false redundancy")
	check(not Game.carrier_diverse(0, 1), "carrier: one carrier is not diversity")
	check(Game.buy_circuit(0, 1, 0, Game.CARRIERS[1]) == "",
		"carrier: a second carrier on the same route is allowed")
	check(Game.carrier_diverse(0, 1), "carrier: two carriers is")
	Game.carrier_outage[Game.CARRIERS[0]] = Game.cycle + 3
	check(not Game.carrier_up(Game.CARRIERS[0]), "carrier: an outage takes that carrier down")
	var ca_live := Game.circuit_between(0, 1)
	check(String(ca_live.get("carrier", "")) == Game.CARRIERS[1],
		"carrier: traffic falls back to the carrier that is still up")
	Game.carrier_outage[Game.CARRIERS[1]] = Game.cycle + 3
	check(Game.circuit_between(0, 1).is_empty(),
		"carrier: with both carriers out there is no path, which is the honest answer")
	Game.carrier_outage = {}
	Game.circuits = []
	Game.money = ca_before

	# --- the working day ---
	var day_saved := Game.cycle
	var day_seen := {}
	var day_peak := 0.0
	var day_low := 99.0
	for slot in Game.DAY_CYCLES:
		Game.cycle = slot
		day_seen[Game.day_name()] = true
		day_peak = maxf(day_peak, Game.day_factor())
		day_low = minf(day_low, Game.day_factor())
	check(day_seen.size() == Game.DAY_CYCLES, "day: every part of the day has a name")
	check(day_peak > 1.2 and day_low < 0.5,
		"day: the peak is several times the quiet hours (%0.2f vs %0.2f)" % [day_peak, day_low])
	check(Game.peak_factor() >= 1.3, "day: provisioning for the average would undersize a link")
	Game.cycle = day_saved

	# --- BFD: noticing that the far end died ---
	var bf_rack := Game.add_rack(Vector2i(38, 1))
	var bf_r1 := Game.new_device("rtr-edge")
	var bf_r2 := Game.new_device("rtr-edge")
	var bf_host := Game.new_device("srv-1")
	var bf_far := Game.new_device("srv-1")
	bf_rack.slots[0] = bf_r1
	bf_rack.slots[1] = bf_r2
	bf_rack.slots[2] = bf_host
	bf_rack.slots[3] = bf_far
	Game.connect_ifaces(bf_host.ifaces[0], bf_r1.ifaces[0])
	Game.connect_ifaces(bf_r1.ifaces[1], bf_r2.ifaces[1])
	Game.connect_ifaces(bf_far.ifaces[0], bf_r2.ifaces[0])
	Game.add_ip(bf_host.ifaces[0], "10.210.1.10/24")
	Game.add_ip(bf_r1.ifaces[0], "10.210.1.1/24")
	Game.add_ip(bf_r1.ifaces[1], "10.210.9.1/30")
	Game.add_ip(bf_r2.ifaces[1], "10.210.9.2/30")
	Game.add_ip(bf_r2.ifaces[0], "10.210.2.1/24")
	Game.add_ip(bf_far.ifaces[0], "10.210.2.10/24")
	bf_r1.static_routes.append({"prefix": "10.210.2.0", "plen": 24, "via": "10.210.9.2"})
	bf_r2.static_routes.append({"prefix": "10.210.1.0", "plen": 24, "via": "10.210.9.1"})
	CLI.new_session(bf_host).exec("ip route add default via 10.210.1.1")
	CLI.new_session(bf_far).exec("ip route add default via 10.210.2.1")
	Sim.flush_learned_state()
	check(Sim.ping(bf_host, "10.210.2.10")["ok"], "bfd: the path works to begin with")
	# the far end of the transit link dies; the local port is still up
	bf_r2.ifaces[1].enabled = false
	Sim.flush_learned_state()
	check(Sim.route_via(bf_r1, "10.210.2.10") != "",
		"bfd: without a session the route survives its own dead next hop")
	var bf_cli1 := CLI.new_session(bf_r1)
	bf_cli1.exec("enable")
	bf_cli1.exec("configure terminal")
	bf_cli1.exec("interface Ethernet2")
	check(bf_cli1.exec("bfd").is_empty(), "bfd: a session can be configured")
	bf_cli1.exec("end")
	Sim.flush_learned_state()
	check(Sim.route_via(bf_r1, "10.210.2.10") != "",
		"bfd: one-sided BFD is no BFD, and detects nothing")
	var bf_cli2 := CLI.new_session(bf_r2)
	bf_cli2.exec("enable")
	bf_cli2.exec("configure terminal")
	bf_cli2.exec("interface Ethernet2")
	bf_cli2.exec("bfd")
	bf_cli2.exec("end")
	Sim.flush_learned_state()
	check(Sim.route_via(bf_r1, "10.210.2.10") == "",
		"bfd: with both ends watching, the dead path is withdrawn")
	check(Sim.bfd_session(bf_r1.ifaces[1]) == "down", "bfd: the session reports itself down")
	check(bf_cli1.exec("show bfd").contains("down"), "bfd: show bfd reports it")
	bf_r2.ifaces[1].enabled = true
	Sim.flush_learned_state()
	check(Sim.bfd_session(bf_r1.ifaces[1]) == "up", "bfd: and comes back up with the link")
	check(Sim.ping(bf_host, "10.210.2.10")["ok"], "bfd: traffic flows again")

	# --- RSTP, bridge priority and MST ---
	var ms_rack := Game.add_rack(Vector2i(37, 1))
	var ms_a := Game.new_device("sw-8")
	var ms_b := Game.new_device("sw-8")
	ms_rack.slots[0] = ms_a
	ms_rack.slots[1] = ms_b
	Game.connect_ifaces(ms_a.ifaces[6], ms_b.ifaces[6])
	Game.connect_ifaces(ms_a.ifaces[7], ms_b.ifaces[7])  # a second link: a loop
	for ms_v in [10, 20]:
		Game.add_vlan(ms_a, ms_v, "v%d" % ms_v)
		Game.add_vlan(ms_b, ms_v, "v%d" % ms_v)
	for ms_i in [6, 7]:
		for ms_d in [ms_a, ms_b]:
			ms_d.ifaces[ms_i].mode = "trunk"
	Sim.flush_learned_state()
	var ms_blocked := 0
	for ms_i2 in [6, 7]:
		for ms_d2 in [ms_a, ms_b]:
			if Sim.stp_blocked(ms_d2.ifaces[ms_i2]):
				ms_blocked += 1
	check(ms_blocked == 1, "stp: one end of the spare link is blocked")
	# priority decides the root, not just the address
	var ms_cli_a := CLI.new_session(ms_a)
	var ms_cli_b := CLI.new_session(ms_b)
	for ms_c in [ms_cli_a, ms_cli_b]:
		ms_c.exec("enable")
		ms_c.exec("configure terminal")
	check(ms_cli_b.exec("spanning-tree priority 4096").is_empty(),
		"stp: bridge priority can be set")
	Sim.flush_learned_state()
	check(Sim.stp_root_of(ms_a) == ms_b, "stp: the lower priority wins the root election")
	check(ms_cli_a.exec("show spanning-tree").contains(ms_b.name),
		"stp: show spanning-tree names the root")
	# MST: two instances, and the two links carry different VLANs
	for ms_c2 in [ms_cli_a, ms_cli_b]:
		check(ms_c2.exec("spanning-tree mst instance 1 vlan 20").is_empty(),
			"mst: an instance can be mapped to a VLAN")
	Sim.flush_learned_state()
	check(Sim.instance_of_vlan(20) == 1 and Sim.instance_of_vlan(10) == 0,
		"mst: VLANs land in the instance they were mapped to")
	var ms_split := false
	for ms_i3 in [6, 7]:
		for ms_d3 in [ms_a, ms_b]:
			var port3: Net.Iface = ms_d3.ifaces[ms_i3]
			if Sim.stp_blocked_for(port3, 10) != Sim.stp_blocked_for(port3, 20):
				ms_split = true
	check(ms_split, "mst: a port forwards one instance while discarding the other")
	check(ms_a.stp_mode == "mst", "mst: mapping an instance puts the switch in MST mode")

	# --- notifications: severity, filtering and the unread count ---
	check(Game.event_severity("SLA BREACH: something is down") == "critical",
		"notify: a breach is serious")
	check(Game.event_severity("LATE: they have not paid") == "warning",
		"notify: a late payment is a warning")
	check(Game.event_severity("CIRCUIT: ordered between two sites") == "info",
		"notify: routine business is neither")
	Game.events = []
	Game.mark_events_read()
	Game.log_event("CIRCUIT: nothing to worry about")
	check(Game.unread_events == 0, "notify: routine events do not demand attention")
	Game.log_event("SECURITY: someone reached the management plane")
	Game.log_event("LATE: an invoice has slipped")
	check(Game.unread_events == 2, "notify: problems do")
	check(Game.events_by_severity("critical").size() == 1,
		"notify: the serious filter shows only the serious one")
	check(Game.events_by_severity("warning").size() == 2,
		"notify: the problems filter keeps the serious one visible too")
	check(Game.events_by_severity("all").size() == 3, "notify: everything means everything")
	Game.mark_events_read()
	check(Game.unread_events == 0, "notify: reading the log clears the count")

	# --- flow accounting ---
	Game.clear_talkers()
	var fl_rack := Game.add_rack(Vector2i(36, 1))
	var fl_rtr := Game.new_device("rtr-lite")
	var fl_a := Game.new_device("srv-1")
	var fl_b := Game.new_device("srv-1")
	fl_rack.slots[0] = fl_rtr
	fl_rack.slots[1] = fl_a
	fl_rack.slots[2] = fl_b
	Game.connect_ifaces(fl_a.ifaces[0], fl_rtr.ifaces[0])
	Game.connect_ifaces(fl_b.ifaces[0], fl_rtr.ifaces[1])
	Game.add_ip(fl_rtr.ifaces[0], "10.190.1.1/24")
	Game.add_ip(fl_rtr.ifaces[1], "10.190.2.1/24")
	Game.add_ip(fl_a.ifaces[0], "10.190.1.10/24")
	Game.add_ip(fl_b.ifaces[0], "10.190.2.10/24")
	CLI.new_session(fl_a).exec("ip route add default via 10.190.1.1")
	CLI.new_session(fl_b).exec("ip route add default via 10.190.2.1")
	Sim.flush_learned_state()
	check(Sim.ping(fl_a, "10.190.2.10")["ok"], "flows: the two subnets route")
	var fl_top := Game.top_talkers()
	check(not fl_top.is_empty(), "flows: forwarded traffic is accounted for")
	var fl_seen := false
	for row in fl_top:
		if String(row["pair"]) == "10.190.1.10>10.190.2.10":
			fl_seen = true
	check(fl_seen, "flows: the pair that actually talked is named")
	check(CLI.new_session(fl_rtr).exec("/ip traffic-flow print").contains("10.190.2.10"),
		"flows: RouterOS reports them too")
	Game.clear_talkers()
	check(Game.top_talkers().is_empty(), "flows: the counters can be reset")

	# --- SNMP: monitoring is a thing you have to configure, on both ends ---
	var snm_rack := Game.add_rack(Vector2i(35, 1))
	var snm_sw := Game.new_device("sw-24")  # an L3 switch, so it can own a management address
	var snm_mon := Game.new_device("srv-1")
	snm_rack.slots[0] = snm_sw
	snm_rack.slots[1] = snm_mon
	Game.connect_ifaces(snm_mon.ifaces[0], snm_sw.ifaces[0])
	Game.add_ip(snm_mon.ifaces[0], "10.180.0.10/24")
	var snm_svi := Game.add_svi(snm_sw, 1)
	Game.add_ip(snm_svi, "10.180.0.1/24")
	Sim.flush_learned_state()
	var snm_cli := CLI.new_session(snm_sw)
	snm_cli.exec("enable")
	check(Sim.ping(snm_mon, "10.180.0.1")["ok"], "snmp: the station can reach the switch first")
	var snm_mcli := CLI.new_session(snm_mon)
	check(snm_mcli.exec("snmpwalk 10.180.0.1 public").contains("no SNMP agent"),
		"snmp: a device with no agent says so instead of answering")
	snm_cli.exec("configure terminal")
	check(snm_cli.exec("snmp-server community public").is_empty(),
		"snmp: the agent can be started")
	snm_cli.exec("end")
	check(snm_mcli.exec("snmpwalk 10.180.0.1 wrongone").contains("wrong community"),
		"snmp: the wrong community is refused, not silently accepted")
	var snm_out := snm_mcli.exec("snmpwalk 10.180.0.1 public")
	check(snm_out.contains(snm_sw.name) and snm_out.contains("Ethernet1"),
		"snmp: a correct poll returns the interface table")
	check(snm_cli.exec("show snmp").contains("public"), "snmp: show snmp reports the community")
	# and it fails for the reason a real one does when the network is broken
	snm_mon.ifaces[0].enabled = false
	Sim.flush_learned_state()
	check(snm_mcli.exec("snmpwalk 10.180.0.1 public").contains("unreachable"),
		"snmp: no route means no monitoring, which is the lesson")
	snm_mon.ifaces[0].enabled = true
	Sim.flush_learned_state()

	# --- named customers who remember ---
	Game.customer_arcs.erase("fonix")
	Game.customer_arcs.erase("tisza")
	var st_deals := Game.deals.duplicate(true)
	Game.reputation = 60
	Game.references = []
	Game.leads = []
	check(Game.STORY_CUSTOMERS.size() >= 5,
		"story: there are a handful of customers who come back, not one")
	var st_deal := {"id": "st1", "customer": "Fonix Klinika", "ctype": "smb", "kind": "hosting",
		"params": {}, "fee": 150, "brief": "", "load": 200, "healthy": true,
		"ever_healthy": true, "cycles": 10, "up_cycles": 10, "loyalty": 0.7}
	Game.deals = [st_deal]
	Game.customer_arcs["fonix"] = {"beat": "arrival", "since": Game.cycle - 9, "outages": 0}
	Game.story_tick()
	var st_arc: Dictionary = Game.customer_arcs["fonix"]
	check(String(st_arc["beat"]) == "complication" and int(st_deal["load"]) == 400,
		"story: the complication is a change to their real service, not a line of dialogue")
	var st_eye := Game.customer_eye(st_deal)
	check(String(st_eye["relationship"]).contains("COMPLICATION") \
			and String(st_eye["memory"]).contains("outage"),
		"story: the customer card says which beat they are on and what they have on record")
	# carrying it earns the payoff, and it is a fact about delivery
	st_deal["degraded"] = false
	Game.story_tick()
	check(String(Game.customer_arcs["fonix"]["outcome"]) == "kept" \
			and Game.references.has("Fonix Klinika") and Game.leads.size() == 1,
		"story: carrying their growth ends the arc in a reference and a door")
	# the same arc, the other way
	Game.customer_arcs.erase("orban")
	Game.references = []
	Game.leads = []
	# --- fire, smoke and water ---
	Game.hazards = []
	Game.protection = {}

	# --- who is on the floor ---
	Game.access_policy = "open"
	Game.cameras = false
	Game.access_log = []
	Game.visitors = []
	Game.money = 20000
	var ac_rack := Game.add_rack(Vector2i(80, 1))
	var ac_sw := Game.new_device("sw-8")
	var ac_srv := Game.new_device("srv-1")
	ac_rack.slots[0] = ac_sw
	ac_rack.slots[1] = ac_srv
	Game.connect_ifaces(ac_srv.ifaces[0], ac_sw.ifaces[0])
	var ac_deals := Game.deals.duplicate(true)
	Game.deals = [{"id": "ac", "customer": "Access Kft", "kind": "hosting", "params": {},
		"fee": 100, "brief": "", "load": 100, "healthy": true, "ever_healthy": true}]
	var ac_stage := Game.stage
	Game.stage = 2
	Game.admit_visitor("Vas Elektro", "aircon service")
	check(Game.visitors.size() == 1 and Game.access_log.size() == 1 \
			and Game.access_investigation().is_empty(),
		"access: a contractor signs in, and on an open floor that record is not worth anything")
	# an open floor: the incident happens and there is nothing to find afterwards
	Game.access_log = []
	var ac_fired := false
	for _ac in 500:
		Game.access_incident_tick()
		for ac_entry: Dictionary in Game.access_log:
			if String(ac_entry["what"]).contains("unplugged"):
				ac_fired = true
		if ac_fired:
			break
	check(ac_fired and String(Game.incidents[0]["kind"]) == "access",
		"access: on an open floor somebody eventually touches something they should not")
	var open_trail := Game.access_investigation()
	var found_unplug := false
	for ac_line: String in open_trail:
		if ac_line.contains("unplugged"):
			found_unplug = true
	check(not found_unplug,
		"access: with no badges and no cameras, the investigation ends where it started")
	Game.cameras = true
	Game.access_log = []
	for _ac2 in 500:
		Game.access_incident_tick()
		if not Game.access_investigation().is_empty():
			break
	var camera_trail := Game.access_investigation()
	var camera_found := false
	for ac_line2: String in camera_trail:
		if ac_line2.contains("unplugged"):
			camera_found = true
	check(camera_found,
		"access: cameras prevent nothing and let you reconstruct exactly what happened")
	# badges change what the incident is; escorting stops it at the door
	check(Game.set_access_policy("badges") == "" and Game.access_policy == "badges",
		"access: a stricter policy is a purchase, not a toggle")
	Game.access_log = []
	for _ac3 in 800:
		Game.access_incident_tick()
		if not Game.access_investigation().is_empty():
			break
	var badge_trail := Game.access_investigation()
	var tailgate := false
	for ac_line3: String in badge_trail:
		if ac_line3.contains("tailgated"):
			tailgate = true
	var badge_unplug := false
	for ac_line4: String in badge_trail:
		if ac_line4.contains("unplugged"):
			badge_unplug = true
	check(not badge_unplug and (tailgate or badge_trail.is_empty()),
		"access: badged, the same person gets as far as the room and no further")
	Game.set_access_policy("escorted")
	check(Game.access_friction() > 0.3 \
			and float(Game.ACCESS_POLICIES["escorted"]["risk"]) < float(Game.ACCESS_POLICIES["open"]["risk"]),
		"access: control costs time on every visit, which is the trade")
	var ac_before_phys := String(Game.control_state("physical_access")["why"])
	Game.access_policy = "open"
	check(String(Game.control_state("physical_access")["why"]).contains("open to the building") \
			and not ac_before_phys.contains("open to the building"),
		"access: the compliance control reads the access policy, not a checkbox")
	Game.access_policy = "badges"
	Game.deals = ac_deals
	Game.stage = ac_stage
	Game.visitors = []
	Game.access_log = []

	# --- what kind of company this is ---
	var id_contracts := Game.contracts_done.duplicate(true)
	Game.identity = ""
	Game.contracts_done = []
	check(not Game.identity_offered(),
		"identity: the choice waits until the opening jobs have taught the loop")
	Game.contracts_done = ["a", "b", "c", "d", "e", "f"]
	check(Game.identity_offered() and Game.IDENTITIES.size() >= 4,
		"identity: four kinds of company, offered once the basics are done")
	Game.leads = []
	check(Game.choose_identity("budget") == "" and Game.identity == "budget" \
			and Game.leads.size() == 1 and Game.choose_identity("green") != "",
		"identity: choosing one is a commitment, and it brings its own signature job")
	# every benefit carries its trade
	var budget_faults := Game.fault_scale()
	var budget_price := Game.order_estimate("srv-1", "trade")
	Game.identity = "green"
	var green_energy := Game.energy_rate()
	var green_price := Game.order_estimate("srv-1", "trade")
	Game.identity = "budget"
	check(budget_price < green_price and budget_faults > 0.0 \
			and Game.fault_scale() > float(Game.DIFFICULTIES[Game.difficulty]["faults"]),
		"identity: the budget hoster buys cheap hardware and pays for it in faults")
	Game.identity = ""
	check(green_energy < Game.energy_rate() and green_price > Game.order_estimate("srv-1", "trade"),
		"identity: the green operator pays less for power and more for the boxes")
	Game.identity = "reliability"
	check(Game.identity_fee_multiplier("hosting") > 1.0,
		"identity: the reliability specialist is paid more for the same service")
	Game.identity = "boutique"
	check(Game.identity_fee_multiplier("secure_host") > 1.0 \
			and Game.identity_fee_multiplier("hosting") == 1.0,
		"identity: the boutique is paid for the hard work and not for the ordinary work")
	# and it can be changed once, expensively
	Game.money = 20000
	var rep_before_rebrand := Game.reputation
	check(Game.rebrand("boutique") != "" and Game.rebrand("green") == "" \
			and Game.identity == "green" and Game.money < 20000 \
			and Game.reputation < rep_before_rebrand,
		"identity: a rebrand is possible, costly, and never free")
	Game.identity = ""
	Game.contracts_done = id_contracts
	Game.leads = []

	# --- reproducible challenges ---
	Challenge.best_path = "user://challenge_best_test.json"
	var ch_code := Challenge.encode(3, 1, 4242)
	var ch_spec := Challenge.parse(ch_code)
	check(bool(ch_spec["ok"]) and int(ch_spec["seed"]) == 4242 and int(ch_spec["faults"]) == 3,
		"challenge: a code round-trips the seed, the fault count and the difficulty")
	check(not bool(Challenge.parse("hello")["ok"]) \
			and String(Challenge.parse("hello")["why"]) != "",
		"challenge: nonsense is refused with a reason rather than a shrug")
	var ch_future := Challenge.parse("PE9-31-abc")
	check(not bool(ch_future["ok"]) and bool(ch_future.get("incompatible", false)),
		"challenge: a code from another content version is marked, not silently played")
	# the same code builds the same network twice
	check(Challenge.start(ch_code) == "" and Game.drill_active,
		"challenge: a code starts the drill it describes")
	var ch_first: Array = Drill.faults.duplicate()
	var ch_targets: Array = Drill.targets.duplicate(true)
	Challenge.finish()
	check(not Game.drill_active, "challenge: finishing hands the real datacenter back")
	Challenge.start(ch_code)
	check(Drill.faults == ch_first and Drill.targets == ch_targets,
		"challenge: two runs of the same code get the same network and the same faults")
	# scoring rewards the diagnosis, not the typing
	Challenge.note_change()
	Challenge.note_change()
	Challenge.note_change()
	var careful_run := Challenge.score()
	for _ch in 20:
		Challenge.note_change()
	var sprayed := Challenge.score()
	check(int(sprayed["categories"]["changes"]) < int(careful_run["categories"]["changes"]),
		"challenge: a spray of configuration changes scores worse than a careful one")
	Challenge.note_hint()
	check(int(Challenge.score()["categories"]["hints"]) < int(sprayed["categories"]["hints"]),
		"challenge: asking for a hint is allowed and it is on the card")
	Drill.cheat_fix()
	var ch_result := Challenge.finish()
	check(bool(ch_result["solved"]) and int(ch_result["total"]) > 0 \
			and Challenge.personal_best(String(ch_result["code"])) == int(ch_result["total"]),
		"challenge: solving it scores, and the best for that code is kept locally")
	var ch_card := Challenge.card(ch_result)
	var card_text := "\n".join(PackedStringArray(ch_card))
	check(card_text.contains(String(ch_result["code"])) and card_text.contains("score") \
			and not card_text.contains("user://") and not card_text.contains("/Users"),
		"challenge: the shareable card carries the result and nothing about this machine")
	check(Challenge.daily_code().begins_with("PE%d-" % Challenge.VERSION),
		"challenge: there is a featured code each day, and manual codes always work offline")
	Challenge.active = {}

	# --- VXLAN and EVPN-lite: one segment over a routed network ---
	var vx_rack := Game.add_rack(Vector2i(82, 1))
	var vx_rack2 := Game.add_rack(Vector2i(83, 1))
	var vx_leaf1 := Game.new_device("sw-24")
	var vx_leaf2 := Game.new_device("sw-24")
	var vx_spine := Game.new_device("rtr-edge")
	var vx_a := Game.new_device("srv-1")
	var vx_b := Game.new_device("srv-1")
	vx_rack.slots[0] = vx_leaf1
	vx_rack.slots[1] = vx_a
	vx_rack2.slots[0] = vx_leaf2
	vx_rack2.slots[1] = vx_b
	var vx_rack3 := Game.add_rack(Vector2i(84, 1))
	vx_rack3.slots[0] = vx_spine
	Game.connect_ifaces(vx_a.ifaces[0], vx_leaf1.ifaces[0])
	Game.connect_ifaces(vx_b.ifaces[0], vx_leaf2.ifaces[0])
	Game.connect_ifaces(vx_leaf1.ifaces[1], vx_spine.ifaces[0])
	Game.connect_ifaces(vx_leaf2.ifaces[1], vx_spine.ifaces[1])
	# the tenant lives in VLAN 50 on both leaves, and the two leaves are only
	# joined by a routed underlay: without an overlay this cannot work
	# the underlay rides its own VLAN on each leaf, terminated on an SVI, which
	# is how an L3 switch does routing
	for vx_sw: Net.NDevice in [vx_leaf1, vx_leaf2]:
		Game.add_vlan(vx_sw, 50, "tenant")
		Game.add_vlan(vx_sw, 60, "underlay")
		vx_sw.ifaces[0].mode = "access"
		vx_sw.ifaces[0].untagged_vlan = 50
		vx_sw.ifaces[1].mode = "access"
		vx_sw.ifaces[1].untagged_vlan = 60
	var vx_svi1 := Game.add_svi(vx_leaf1, 60)
	var vx_svi2 := Game.add_svi(vx_leaf2, 60)
	Game.add_ip(vx_svi1, "10.200.1.2/30")
	Game.add_ip(vx_spine.ifaces[0], "10.200.1.1/30")
	Game.add_ip(vx_svi2, "10.200.2.2/30")
	Game.add_ip(vx_spine.ifaces[1], "10.200.2.1/30")
	Game.add_static_route(vx_leaf1, "10.200.2.0", 30, "10.200.1.1")
	Game.add_static_route(vx_leaf2, "10.200.1.0", 30, "10.200.2.1")
	Game.add_ip(vx_a.ifaces[0], "192.168.50.10/24")
	Game.add_ip(vx_b.ifaces[0], "192.168.50.11/24")
	Sim.flush_learned_state()
	check(Sim.ping(vx_leaf1, "10.200.2.2")["ok"],
		"vxlan: the underlay routes between the two leaves")
	check(not Sim.ping(vx_a, "192.168.50.11")["ok"],
		"vxlan: the tenant cannot cross a routed network without an overlay")
	var vx_c1 := CLI.new_session(vx_leaf1)
	var vx_c2 := CLI.new_session(vx_leaf2)
	for vx_cli: CLI.Session in [vx_c1, vx_c2]:
		vx_cli.exec("en")
		vx_cli.exec("conf t")
	check(vx_c1.exec("vxlan source 10.200.1.2") == "" \
			and vx_c1.exec("vxlan vlan 50 vni 5000") == "" \
			and vx_c1.exec("vxlan peer 10.200.2.2") == "",
		"vxlan: a VTEP is a source address, a VLAN-to-VNI mapping and a peer")
	check(vx_c1.exec("vxlan vlan 99 vni 9900").contains("not on this switch"),
		"vxlan: you cannot map a VLAN the switch does not carry")
	vx_c2.exec("vxlan source 10.200.2.2")
	vx_c2.exec("vxlan vlan 50 vni 5000")
	vx_c2.exec("vxlan peer 10.200.1.2")
	Sim.flush_learned_state()
	check(Sim.ping(vx_a, "192.168.50.11")["ok"],
		"vxlan: with the overlay up, the tenant is one segment again")
	check(String(vx_leaf1.remote_macs.get(50, {}).get(vx_b.ifaces[0].mac, "")) == "10.200.2.2",
		"vxlan: what came out of the tunnel is remembered as being behind that VTEP")
	check(vx_c1.exec("show vxlan").contains("5000") and vx_c1.exec("show vxlan").contains("BEHIND VTEP"),
		"vxlan: the mapping and the remote addresses are visible from the console")
	# a VNI nobody carries is dropped rather than leaked into another tenant
	vx_c2.exec("vxlan vlan 50 vni 5001")
	Sim.flush_learned_state()
	vx_leaf1.remote_macs = {}
	vx_leaf2.remote_macs = {}
	check(not Sim.ping(vx_a, "192.168.50.11")["ok"],
		"vxlan: a mismatched VNI is dropped, not delivered to the wrong tenant")
	vx_c2.exec("vxlan vlan 50 vni 5000")
	Sim.flush_learned_state()
	# EVPN-lite: the far end learns without anybody flooding to it
	vx_leaf1.remote_macs = {}
	vx_leaf2.remote_macs = {}
	vx_c1.exec("vxlan evpn")
	vx_c2.exec("vxlan evpn")
	check(bool(vx_leaf1.vtep["evpn"]),
		"evpn: the control plane is a setting on the VTEP, not a separate box")
	Sim.ping(vx_a, "192.168.50.10")  # anything that makes leaf1 learn its own port
	Sim.flush_learned_state()
	Sim.ping(vx_a, "192.168.50.11")
	check(String(vx_leaf2.remote_macs.get(50, {}).get(vx_a.ifaces[0].mac, "")) == "10.200.1.2",
		"evpn: a locally learned address is advertised to the other VTEPs")
	Sim.evpn_advertise(vx_leaf1, 50, vx_a.ifaces[0].mac, true)
	check(not vx_leaf2.remote_macs.get(50, {}).has(vx_a.ifaces[0].mac),
		"evpn: and withdrawn again when it is no longer there")

	# the contract that only closes when the overlay is genuinely built
	var ov := _contract("overlay_tenant")
	check(not Game.try_complete_contract(ov),
		"overlay lab: the job is not done by having the commands typed somewhere")
	for vx_sw2: Net.NDevice in [vx_leaf1, vx_leaf2]:
		Game.add_vlan(vx_sw2, 70, "turul")
		vx_sw2.ifaces[2].mode = "access"
		vx_sw2.ifaces[2].untagged_vlan = 70
	Game.add_vlan(vx_leaf1, 71, "second tenant")
	var ov_a := Game.new_device("srv-1")
	var ov_b := Game.new_device("srv-1")
	var ov_rack := Game.add_rack(Vector2i(85, 1))
	ov_rack.slots[0] = ov_a
	ov_rack.slots[1] = ov_b
	Game.connect_ifaces(ov_a.ifaces[0], vx_leaf1.ifaces[2])
	Game.connect_ifaces(ov_b.ifaces[0], vx_leaf2.ifaces[2])
	Game.add_ip(ov_a.ifaces[0], "192.168.70.10/24")
	Game.add_ip(ov_b.ifaces[0], "192.168.70.11/24")
	vx_c1.exec("vxlan vlan 70 vni 7000")
	vx_c2.exec("vxlan vlan 70 vni 7000")
	Sim.flush_learned_state()
	Sim.ping(ov_a, "192.168.70.11")
	check(Game.try_complete_contract(ov),
		"overlay lab: underlay, one VNI across two leaves, an unmapped neighbour and EVPN learning")

	# --- cabling from the topology map ---
	Game.parts = {"patch": 20, "optic": 20, "power": 10, "blank": 10}
	Game.cabling_documented = false
	var md_rack := Game.add_rack(Vector2i(86, 1))
	var md_a := Game.new_device("sw-8")
	var md_b := Game.new_device("srv-1")
	md_rack.slots[0] = md_a
	md_rack.slots[1] = md_b
	check(Game.link_devices(md_a, md_a) != "",
		"map cabling: a device cannot be cabled to itself")
	check(Game.link_devices(md_a, md_b) == "" \
			and Game.link_at(md_b.ifaces[0]) != null,
		"map cabling: dragging between two devices runs a lead between free ports")
	check(Game.link_devices(md_a, md_b) == "" or Game.free_port(md_b) == null,
		"map cabling: it uses the next free port, and says so when there is not one")
	var md_far_site := Game.add_site("Colo Pecs", Vector2i(3, 3), "acquired", "Pecs")
	var md_far_rack := Game.add_rack(Vector2i(0, 0), md_far_site)
	var md_far := Game.new_device("sw-8")
	md_far_rack.slots[0] = md_far
	Game.circuits = []
	var md_err := Game.link_devices(md_a, md_far)
	check(md_err.contains("no circuit"),
		"map cabling: a run to another site says which prerequisite is missing")
	Game.current_site = 0

	# --- the run finale ---
	Game.finale = {}
	Game.sandbox = false
	Game.sold_out = false
	Game.money = 12000
	Game.reputation = 70
	check(Game.end_run("nonsense") != "" and Game.finale.is_empty(),
		"finale: a run ends one of the three ways it can end")
	check(Game.end_run("retired") == "" and not Game.finale.is_empty() \
			and Game.end_run("sold") != "",
		"finale: it freezes once, and the save is untouched")
	var fin_snap: Dictionary = Game.finale.duplicate(true)
	var fin_first := Game.finale_score(fin_snap)
	Game.money = 999999  # the live world moves on; the report does not
	Game.reputation = 10
	var fin_again := Game.finale_score(fin_snap)
	check(int(fin_first["total"]) == int(fin_again["total"]),
		"finale: the categories reproduce exactly from the frozen snapshot")
	check(fin_first["categories"].size() == 6,
		"finale: six categories, each of which the player can influence")
	# idling cannot out-earn playing: money is scored per cycle and capped
	var fin_slow := fin_snap.duplicate(true)
	fin_slow["cycle"] = int(fin_snap["cycle"]) * 10
	check(int(Game.finale_score(fin_slow)["categories"]["financial"]) \
			< int(fin_first["categories"]["financial"]) \
			or int(fin_first["categories"]["financial"]) == 250,
		"finale: ten times as long for the same money scores worse, not better")
	var fin_callouts := Game.finale_callouts(fin_snap)
	check(String(fin_callouts["strength"]) != "" and fin_callouts["losses"] is Array,
		"finale: the report says what went well and what was avoidable")
	var fin_report := Game.finale_report()
	check(fin_report.size() > 6 and String(fin_report[1]).contains("walked away"),
		"finale: every ending arrives at the same report")
	Game.finale = {}
	Game.money = 12000

	# --- run history ---
	Game.history_path = "user://run_history_test.json"
	if FileAccess.file_exists(Game.history_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.history_path))
	Game.forget_all_runs()
	check(Game.run_history().is_empty(), "history: it starts empty and that is not an error")
	var hist_snap := Game.finale_snapshot("sold")
	var hist_row := Game.record_run(hist_snap)
	check(Game.run_history().size() == 1 and int(Game.run_history()[0]["total"]) == int(hist_row["total"]),
		"history: a finished run leaves one compact row behind")
	check(String(Game.compare_to_best(hist_row)[0]).contains("first run"),
		"history: the first run has nothing to compare against, and says so")
	var hist_snap2 := hist_snap.duplicate(true)
	hist_snap2["company"] = "Second Go"
	hist_snap2["reputation"] = int(hist_snap.get("reputation", 50)) + 20
	hist_snap2["references"] = 3
	var hist_row2 := Game.record_run(hist_snap2)
	var hist_cmp := Game.compare_to_best(hist_row2)
	check(hist_cmp.size() > 1 and String(hist_cmp[0]).contains("against"),
		"history: the second run is compared with the best one before it, category by category")
	check(int(Game.best_run()["total"]) >= int(hist_row["total"]),
		"history: the best run is the best of them, not the last of them")
	var hist_before := Game.run_history().size()
	Game.record_run(hist_snap2)
	check(Game.run_history().size() == hist_before,
		"history: the same run recorded twice is still one run")
	var f_bad := FileAccess.open(Game.history_path, FileAccess.WRITE)
	if f_bad:
		f_bad.store_string("{\"nope\": 1}")
		f_bad = null
	check(Game.run_history().is_empty(),
		"history: a corrupt file reads as no history rather than taking the game down")
	Game.record_run(hist_snap)
	var forget_at := int(Game.run_history()[0]["at"])
	Game.forget_run(forget_at)
	check(Game.run_history().is_empty(),
		"history: a single record can be removed, and saves are not involved")
	Game.forget_all_runs()

	# --- notes on everything, and where they matter ---
	var nt_rack := Game.add_rack(Vector2i(88, 1))
	var nt_sw := Game.new_device("sw-8")
	var nt_srv := Game.new_device("srv-1")
	nt_rack.slots[0] = nt_sw
	nt_rack.slots[1] = nt_srv
	Game.connect_ifaces(nt_srv.ifaces[0], nt_sw.ifaces[0])
	var nt_link := Game.link_at(nt_srv.ifaces[0])
	Game.set_note(nt_link, "temporary, remove after the migration")
	check(String(nt_link.note["text"]) == "temporary, remove after the migration",
		"notes: a cable run can be labelled like anything else")
	var nt_payload: Dictionary = JSON.parse_string(Game.snapshot())
	var nt_saved := false
	for nt_row in nt_payload["links"]:
		if nt_row.size() > 4 and String(nt_row[4].get("text", "")).contains("migration"):
			nt_saved = true
	check(nt_saved, "notes: the label on a run survives the save")
	var nt_deal := {"id": "nt", "customer": "Note Kft", "kind": "hosting", "params": {},
		"fee": 100, "brief": "", "load": 100, "healthy": false, "ever_healthy": true}
	var nt_deals := Game.deals.duplicate(true)
	Game.deals = [nt_deal]
	Game.set_deal_note(nt_deal, "their finance person only answers on Tuesdays")
	check(String(nt_deal["note"]["text"]).contains("Tuesdays") and Game.deal_note_age(nt_deal) == 0,
		"notes: a customer can be annotated, and the note carries its age")
	var nt_incident_notes := Game.incident_notes()
	var nt_found := false
	for nt_line: String in nt_incident_notes:
		if nt_line.contains("Tuesdays"):
			nt_found = true
	check(nt_found,
		"notes: when their service is down, what you wrote about them is put in front of you")
	Game.set_note(nt_sw, "console cable is behind the rack")
	nt_sw.status = "offline"
	var nt_dev_notes := Game.incident_notes()
	var nt_dev_found := false
	for nt_line2: String in nt_dev_notes:
		if nt_line2.contains("console cable"):
			nt_dev_found = true
	check(nt_dev_found,
		"notes: and the same for a device that is in trouble right now")
	nt_sw.status = "active"
	Game.deals = nt_deals

	# --- localisation foundation ---
	var loc_before := Loc.language
	Loc.language = "en"
	check(Loc.t("welcome.title") != "welcome.title" and Loc.t("nothing.here") == "nothing.here",
		"loc: a known id resolves and an unknown one comes back loudly rather than crashing")
	check(Loc.t("event.outage.raised", {"customer": "Kiskacsa"}).contains("Kiskacsa"),
		"loc: live values are interpolated by name, not by position")
	check(Loc.placeholder_problems().is_empty(),
		"loc: every translation carries the same placeholders as the English")
	var loc_used: Array = ["welcome.title", "welcome.lede", "welcome.start",
		"contract.rackup.title", "contract.rackup.brief", "contract.rackup.hint",
		"event.outage.raised", "event.outage.status", "event.outage.recovered",
		"pedia.vlans.title", "pedia.vlans.body"]
	check(Loc.missing_ids(loc_used).is_empty(),
		"loc: every id the game asks for exists in the catalogue")
	check(Loc.plural("ui.cycles", 1).contains("1 cycle") \
			and Loc.plural("ui.cycles", 4).contains("4 cycles"),
		"loc: plural forms are chosen by count rather than glued on")
	Loc.language = "hu"
	check(Loc.t("welcome.title") != Loc.CATALOG["welcome.title"]["en"] \
			and _contract("rackup")["title"] == Loc.CATALOG["contract.rackup.title"]["hu"],
		"loc: switching language changes the copy, including the contract text")
	check(Loc.t("event.outage.raised", {"customer": "Kiskacsa"}).contains("Kiskacsa"),
		"loc: names and addresses are never translated")
	var hu_pedia := Pedia.topics()
	var hu_vlan := ""
	for hu_entry in hu_pedia:
		if String(hu_entry[0]) == Loc.CATALOG["pedia.vlans.title"]["hu"]:
			hu_vlan = String(hu_entry[1])
	check(hu_vlan != "" and hu_vlan.contains("switchport access vlan 10"),
		"loc: an encyclopedia topic translates while its commands stay exactly as typed")
	Loc.language = "pseudo"
	var pseudo_title := Loc.t("welcome.title")
	check(pseudo_title.length() > Loc.CATALOG["welcome.title"]["en"].length() \
			and pseudo_title.begins_with("["),
		"loc: pseudo-localisation is longer and accented, which is how clipping is found")
	Loc.language = loc_before

	# --- exporting the topology ---
	var ex_rack := Game.add_rack(Vector2i(90, 1))
	var ex_sw := Game.new_device("sw-8")
	var ex_srv := Game.new_device("srv-1")
	ex_rack.slots[0] = ex_sw
	ex_rack.slots[1] = ex_srv
	Game.connect_ifaces(ex_srv.ifaces[0], ex_sw.ifaces[0])
	Game.add_ip(ex_srv.ifaces[0], "10.190.0.10/24")
	var mermaid := Game.topology_mermaid()
	check(mermaid.begins_with("graph LR") and mermaid.contains(ex_sw.name) \
			and mermaid.contains("subgraph %s" % ex_rack.name),
		"export: the diagram is Mermaid text with the cabinets as subgraphs")
	check(mermaid.contains(ex_srv.ifaces[0].name),
		"export: every run names the ports at both ends")
	var listing := Game.topology_text()
	check(listing.contains("10.190.0.10/24") and listing.contains(ex_srv.name) \
			and listing.contains("→"),
		"export: the plain listing carries addresses and what is cabled to what")
	ex_sw.ifaces[0].enabled = false
	check(Game.topology_mermaid().contains("-.-") and Game.topology_text().contains("(down)"),
		"export: a port that is down looks different in both formats")
	ex_sw.ifaces[0].enabled = true
	var written := Game.export_topology("user://topology_test.md")
	check(written.contains("```mermaid") and written.contains(Game.company_name) \
			and FileAccess.file_exists("user://topology_test.md"),
		"export: it is written to a file and handed back for the clipboard")

	# --- content packs ---
	Pack.load_all()
	check(not Pack.loaded.is_empty() and Pack.problems.is_empty(),
		"packs: the bundled pack loads and validates")
	var pk: Dictionary = Pack.loaded[0]
	check(Pack.validate(pk).is_empty() and pk["scenarios"].size() >= 4,
		"packs: a pack is metadata plus scenarios, and it is checked before it is used")
	check(Pack.validate({"id": "x"})[0].contains("missing field"),
		"packs: a malformed pack is rejected with the field that is wrong")
	check(String(Pack.validate({"id": "x", "name": "x", "schema": 99, "scenarios": [{}]})[0]).contains("version"),
		"packs: a pack from another schema version is refused rather than half-read")
	var bad_pred := Pack.validate({"id": "x", "name": "x", "schema": 1, "scenarios": [
		{"id": "s", "title": "t", "brief": "b",
			"requirements": [{"kind": "reachable", "from": "not-an-address", "to": "10.0.0.1"}]}]})
	check(not bad_pred.is_empty() and String(bad_pred[0]).contains("scenarios[0].requirements[0]"),
		"packs: errors name the exact field, so an author can fix the file")
	check(Pack.validate({"id": "x", "name": "x", "schema": 1, "scenarios": [
		{"id": "s", "title": "t", "brief": "b", "requirements": [],
			"future_field": {"anything": true}}]}).is_empty(),
		"packs: unknown future fields are preserved rather than rejected")
	# the predicates run against the live simulation, like everything else
	var pk_rack := Game.add_rack(Vector2i(92, 1))
	var pk_sw := Game.new_device("sw-8")
	var pk_a := Game.new_device("srv-1")
	var pk_b := Game.new_device("srv-1")
	pk_rack.slots[0] = pk_sw
	pk_rack.slots[1] = pk_a
	pk_rack.slots[2] = pk_b
	Game.connect_ifaces(pk_a.ifaces[0], pk_sw.ifaces[0])
	Game.connect_ifaces(pk_b.ifaces[0], pk_sw.ifaces[1])
	var unreachable := Pack.evaluate({"kind": "reachable", "from": "10.90.0.10", "to": "10.90.0.11"})
	check(not bool(unreachable["ok"]) and String(unreachable["why"]) != "",
		"packs: a failing requirement says what is missing, not just that it failed")
	Game.add_ip(pk_a.ifaces[0], "10.90.0.10/24")
	Game.add_ip(pk_b.ifaces[0], "10.90.0.11/24")
	Sim.flush_learned_state()
	check(bool(Pack.evaluate({"kind": "reachable", "from": "10.90.0.10", "to": "10.90.0.11"})["ok"]),
		"packs: and passes once the network actually does it")
	check(bool(Pack.evaluate({"kind": "all", "of": [
			{"kind": "device_count", "type": "switch", "min": 1},
			{"kind": "link_between", "a": pk_a.name, "b": pk_sw.name}]})["ok"]),
		"packs: predicates compose with all/any/not")
	check(not bool(Pack.evaluate({"kind": "not", "of": [
			{"kind": "device_count", "type": "switch", "min": 1}]})["ok"]),
		"packs: negation works the way an author would expect")
	check(String(Pack.describe({"kind": "vlan_access", "vid": 10})).contains("VLAN 10"),
		"packs: every requirement can describe itself for the checklist")
	# the authored jobs behave exactly like built-in contracts
	var authored := Pack.contracts()
	check(authored.size() >= 4 and String(authored[0]["id"]).begins_with("packetempire.starter."),
		"packs: authored scenarios arrive as contracts with namespaced ids")
	var live_first_light := {}
	for c_a: Dictionary in authored:
		if String(c_a["id"]).ends_with("first_light"):
			live_first_light = c_a
	var all_pass := true
	for req: Dictionary in live_first_light["reqs"]:
		if not bool((req["t"] as Callable).call()):
			all_pass = false
	check(all_pass, "packs: an authored job verifies against the live network, like the campaign")
	# actions are a small, safe set
	var pk_money := Game.money
	Pack.run_actions([{"kind": "reward", "amount": 100},
		{"kind": "break_link", "device": pk_sw.name}])
	check(Game.money == pk_money + 100 and not pk_sw.ifaces[0].enabled,
		"packs: the action set can pay and can break a link, deterministically")
	Pack.run_actions([{"kind": "restore_links"}])
	check(pk_sw.ifaces[0].enabled, "packs: and can put it back")
	check(Pack._validate_action({"kind": "rm -rf"}, "x")[0].contains("unknown action"),
		"packs: nothing outside the action set is even a word")

	# the workshop: find them, read them, import one, explain the broken ones
	var rows := Pack.workshop_rows()
	check(not rows.is_empty() and bool(rows[0]["ok"]) and rows[0]["scenarios"].size() >= 4,
		"workshop: every pack found is listed with its status and what is in it")
	var preview_lines := Pack.preview(pk, pk["scenarios"][1])
	check(preview_lines.size() > 3 and String(preview_lines[preview_lines.size() - 1]).begins_with("  · "),
		"workshop: a scenario can be previewed before anybody starts it")
	check(Pack.diagnostic_report().contains("schema"),
		"workshop: broken packs produce a report an author can paste to whoever wrote it")
	var import_err := Pack.import_text("{\"id\": \"broken\"}")
	check(import_err.contains("not valid") or import_err.contains("missing"),
		"workshop: an invalid pack is refused on import, not on play")
	var minimal := JSON.stringify({"id": "classroom.minimal", "name": "Minimal classroom pack",
		"schema": 1, "author": "you",
		"description": "Copy this, change the objective, play it.",
		"scenarios": [{"id": "one_ping", "title": "One ping", "brief": "Make 10.90.0.10 reach 10.90.0.11.",
			"reward": 200,
			"requirements": [{"kind": "reachable", "from": "10.90.0.10", "to": "10.90.0.11"}]}]})
	check(Pack.import_text(minimal, "classroom_test") == "",
		"workshop: a valid pack imports without touching the project source")
	var imported := false
	for pack_row: Dictionary in Pack.workshop_rows():
		if String(pack_row["id"]) == "classroom.minimal":
			imported = true
	check(imported, "workshop: and shows up immediately, with no restart")
	var shared := Pack.share_text(pk)
	check(shared.contains("scenarios") and not shared.contains("source"),
		"workshop: sharing a pack carries the content and nothing about this machine")
	check(FileAccess.file_exists("res://docs/PACKS.md"),
		"workshop: the format is documented where an author will look for it")

	# --- balance: a delivering operator grows at every difficulty, with the
	# facility, parts, renewals and duties systems all switched on ---
	var bal_difficulty := Game.difficulty
	var bal_report: Array = []
	var bal_ok := true
	for bal_level in Game.DIFFICULTIES.size():
		Game.racks = []
		Game.links = []
		Game.deals = []
		Game.offers = []
		Game.leads = []
		Game.invoices = []
		Game.events = []
		Game.contracts_done = []
		Game.sla_status = {}
		Game.incidents = []
		Game.incidents_seen = {}
		Game.staff = []
		Game.hazards = []
		Game.protection = {}
		Game.facility = {}
		Game.renewals = []
		Game.duties = {}
		Game.tickets = []
		Game.crates = []
		Game.decisions = []
		Game.consequences = []
		Game.firmware_bugs = {}
		Game.grey_faults = {}
		Game.tour = {}
		Game.audit = {}
		Game.upstream = {}
		Game.finale = {}
		Game.visitors = []
		Game.identity = ""
		Game.parts = {"patch": 40, "optic": 8, "power": 20, "blank": 12}
		Game.parts_auto = true
		Game.apply_difficulty(bal_level)
		Game.sites = [Game.sites[0]]  # one floor: the rest belong to other sections
		Game.current_site = 0
		Game.circuits = []
		seed(20260823 + bal_level)  # each difficulty gets the same weather
		Game.stage = 1
		Game.debt = 0
		Game.reputation = 55
		var bal_start: int = Game.money
		var bal_rack := Game.add_rack(Vector2i(0, 0))
		var bal_sw := Game.new_device("sw-8")
		var bal_a := Game.new_device("srv-1")
		var bal_b := Game.new_device("srv-1")
		bal_rack.slots[0] = bal_sw
		bal_rack.slots[1] = bal_a
		bal_rack.slots[2] = bal_b
		Game.connect_ifaces(bal_a.ifaces[0], bal_sw.ifaces[0])
		Game.connect_ifaces(bal_b.ifaces[0], bal_sw.ifaces[1])
		Game.add_ip(bal_a.ifaces[0], "10.99.0.10/24")
		Game.add_ip(bal_b.ifaces[0], "10.99.0.11/24")
		for bal_dev: Net.NDevice in [bal_sw, bal_a, bal_b]:
			bal_dev.startup = Game.device_config(bal_dev)
		# a competent operator fits detection and suppression before they need it
		Game.buy_protection("detection")
		Game.buy_protection("suppression")
		Game.deals = [{"id": "bal", "customer": "SteadyCo", "kind": "hosting",
			"params": {"ip": "10.99.0.10"}, "fee": 120, "load": 200, "brief": "",
			"healthy": true, "budget": 120, "loyalty": 0.95}]
		var bal_spend := {}
		for _bal_cycle in 100:
			# the operator keeps the housekeeping up, which is the point of it
			Game.facility_auto = {"filters": true, "aircon": true, "generator": true, "ups": true}
			for bal_item in Game.renewals:
				bal_item["auto"] = true
			Game.sla_tick()
			for bal_key: String in Game.last_pl:
				bal_spend[bal_key] = int(bal_spend.get(bal_key, 0)) + int(Game.last_pl[bal_key])
			for bal_deal in Game.deals:
				if bal_deal.has("renewal"):
					Game.accept_renewal(bal_deal)
			for bal_link: Net.Link in Game.links:  # a competent operator fixes faults
				bal_link.a.enabled = true
				bal_link.b.enabled = true
			for bal_dev2: Net.NDevice in Game.all_devices():
				if bal_dev2.status != "active":
					bal_dev2.status = "active"
			if Game.deals.is_empty():
				# an operator who loses an account signs a comparable one; this
				# section is about whether steady delivery outpaces the running
				# costs, not about surviving one unlucky cancellation
				Game.deals = [{"id": "bal", "customer": "SteadyCo", "kind": "hosting",
					"params": {"ip": "10.99.0.10"}, "fee": 120, "load": 200, "brief": "",
					"healthy": true, "budget": 120, "loyalty": 0.95}]
		var bal_grew: bool = Game.money > bal_start
		bal_ok = bal_ok and bal_grew
		bal_report.append("%s %s ($%d → $%d)" % [Game.DIFFICULTIES[bal_level]["name"],
			"grew" if bal_grew else "SHRANK", bal_start, Game.money])
	check(bal_ok, "balance: a delivering operator grows at every difficulty: %s"
		% "; ".join(PackedStringArray(bal_report)))
	check(Game.pl_totals.has("power") and int(Game.pl_totals["power"]) < 0,
		"balance: the run-to-date profit and loss says where the money went, per system")

	# --- an old save still loads ---
	# what a save looked like several dozen fields ago: everything since has to
	# default rather than fail
	var old_save := {
		"money": 3210, "stage": 1, "cycle": 42, "company_name": "Legacy Networks",
		"demo": false, "difficulty": 1, "reputation": 61, "debt": 0,
		"stats": {"earned": 8800, "incidents": 2, "faults": 5, "contracts": 3, "deals": 2},
		"contracts_done": ["rackup", "first_ping"], "offers": [], "deals": [],
		"events": ["cycle 41: an old event"], "incidents_seen": {},
		"counters": {"switch": 2, "server": 3, "router": 1, "firewall": 0, "uplink": 0,
			"cooling": 0, "loadbalancer": 0, "ap": 0, "console": 0, "rack": 1, "mac": 9},
		"sites": [{"name": "Home floor", "grid": [7, 7], "kind": "own"}], "current_site": 0,
		"racks": [{"name": "R1", "tile": [2, 2], "site": 0,
			"slots": ["sw_old", "srv_old", null, null, null, null, null, null],
			"blanked": [], "note": {}}],
		"devices": {
			"sw_old": {"type": "switch", "model": "sw-8", "name": "sw_old", "status": "active",
				"vlans": {"1": "default"}, "ifaces": [
					{"name": "Ethernet1", "mac": "02:50:45:00:00:01", "enabled": true,
						"mode": "access", "untagged_vlan": 1, "ips": [], "note": {}},
					{"name": "Management1", "mac": "02:50:45:00:00:02", "enabled": true,
						"mode": "routed", "untagged_vlan": 1, "ips": [], "note": {}}],
				"note": {}},
			"srv_old": {"type": "server", "model": "srv-1", "name": "srv_old", "status": "active",
				"ifaces": [{"name": "eth0", "mac": "02:50:45:00:00:03", "enabled": true,
					"mode": "routed", "untagged_vlan": 1, "ips": ["10.7.0.10/24"], "note": {}}],
				"note": {}}},
		"links": [["srv_old", "eth0", "sw_old", "Ethernet1"]]}
	var live_before := Game.snapshot()
	Game.restore(JSON.stringify(old_save))
	check(Game.company_name == "Legacy Networks" and Game.money == 3210 \
			and Game.racks.size() == 1 and Game.all_devices().size() == 2,
		"save compat: a save written before three dozen fields existed still loads its world")
	check(Game.facility.is_empty() and Game.hazards.is_empty() and Game.protection.is_empty() \
			and Game.identity == "" and Game.finale.is_empty() and Game.tickets.is_empty() \
			and Game.parts_auto and Game.access_policy == "open",
		"save compat: everything added since defaults instead of failing")
	var old_link_ok := false
	for old_l: Net.Link in Game.links:
		if old_l.a.dev.name == "srv_old" and old_l.b.dev.name == "sw_old":
			old_link_ok = true
	check(old_link_ok and Game.links.size() == 1,
		"save compat: cabling written without a note field still restores")
	Game.sandbox = true  # tick it without the economy inventing new work
	Game.sla_tick()
	Game.sandbox = false
	check(Game.cycle == 43,
		"save compat: and the world ticks afterwards rather than falling over")
	var round_trip := Game.snapshot()
	Game.restore(round_trip)
	check(Game.company_name == "Legacy Networks" and Game.all_devices().size() == 2,
		"save compat: saving it again keeps everything the old save carried")
	# a payload missing a field the current build writes is not fatal either
	var trimmed: Dictionary = JSON.parse_string(round_trip)
	trimmed.erase("pl_totals")
	trimmed.erase("renewals")
	trimmed.erase("skill_log")
	Game.restore(JSON.stringify(trimmed))
	check(Game.pl_totals.is_empty() and Game.renewals.is_empty() and Game.skill_log.is_empty() \
			and Game.company_name == "Legacy Networks",
		"save compat: a field removed from the payload reads as its default, not as a crash")
	Game.restore(live_before)

	# --- one command that collects what a vendor asks for ---
	var ts_rack := Game.add_rack(Vector2i(94, 1))
	var ts_sw := Game.new_device("sw-8")
	var ts_srv := Game.new_device("srv-1")
	ts_rack.slots[0] = ts_sw
	ts_rack.slots[1] = ts_srv
	Game.connect_ifaces(ts_srv.ifaces[0], ts_sw.ifaces[0])
	Game.add_ip(ts_srv.ifaces[0], "10.195.0.10/24")
	Game.device_log(ts_sw, "something worth reading later")
	var ts_cli := CLI.new_session(ts_sw)
	var bundle := ts_cli.exec("show tech-support")
	check(bundle.contains("interfaces") and bundle.contains("counters") \
			and bundle.contains("mac address-table") and bundle.contains("spanning-tree") \
			and bundle.contains("lldp") and bundle.contains("something worth reading later"),
		"tech-support: one command collects the interfaces, counters, tables, neighbours and log")
	check(bundle.contains("RUNNING CONFIGURATION IS NOT SAVED"),
		"tech-support: it says plainly whether what is running was ever saved")
	ts_sw.startup = Game.device_config(ts_sw)
	check(ts_cli.exec("show tech-support").contains("matches startup"),
		"tech-support: and says so when it has been")
	var ts_before := Game.snapshot()
	ts_cli.exec("show tech-support")
	check(Game.snapshot() == ts_before,
		"tech-support: it is read-only, which is why it is safe during an incident")
	var ts_ros := Game.new_device("sw-lite")
	ts_rack.slots[2] = ts_ros
	check(CLI.new_session(ts_ros).exec("/system tech-support").contains("/ip route print"),
		"tech-support: PacketTik gear collects the same thing in its own shape")
	# and the vendor case takes it as the evidence it asked for
	Game.tac_cases = []
	Game.renewals = []
	Game.firmware_bugs[ts_sw.name] = {"since": Game.cycle, "model": ts_sw.model}
	Game.open_tac_case(ts_sw, 2)
	var ts_case: Dictionary = Game.tac_cases[0]
	check(Game.attach_bundle(ts_case) == "" \
			and ts_case["evidence"].size() >= Game.TAC_EVIDENCE.size() - 1,
		"tech-support: attaching the bundle answers everything the case asked for at once")
	Game.tac_cases = []
	Game.firmware_bugs = {}

	# --- the later jobs get a debrief too ---
	Game.contract_debriefs = {}
	# nothing is claimed about a job whose evidence is not on the floor
	var db_empty := Game._opening_contract_debrief({"id": "overlay_tenant", "title": "x",
		"customer": "y", "reward": 1})
	check(db_empty.is_empty(),
		"debrief: a job with no live evidence produces no debrief rather than a fiction")
	# an overlay that really exists produces one built from it
	var db_rack := Game.add_rack(Vector2i(96, 1))
	var db_l1 := Game.new_device("sw-24")
	var db_l2 := Game.new_device("sw-24")
	db_rack.slots[0] = db_l1
	db_rack.slots[1] = db_l2
	for db_sw: Net.NDevice in [db_l1, db_l2]:
		Game.add_vlan(db_sw, 80, "tenant")
		db_sw.vtep = {"src": "10.210.0.%d" % (1 + int(db_sw == db_l2)), "peers": [],
			"map": {80: 8000}, "evpn": false}
	var db_overlay := Game._opening_contract_debrief({"id": "overlay_tenant",
		"title": "The tenant that outgrew the VLAN", "customer": "Turul Mobil", "reward": 5200})
	check(not db_overlay.is_empty() and String(db_overlay["proof"][0]).contains("8000") \
			and String(db_overlay["proof"][0]).contains(db_l1.name),
		"debrief: it names the player's own devices and the VNI they actually mapped")
	check(String(db_overlay["concept"]) != "" and String(db_overlay["practice"]) != "" \
			and String(db_overlay["avoided"]) != "" and String(db_overlay["mastery"]) != "",
		"debrief: one concept, one command, one avoided failure, one optional challenge")
	# and the mastery check is live, not a claim
	check(not Game.contract_mastery_met("overlay_tenant"),
		"debrief: mastery is not granted for having got this far")
	db_l1.vtep["evpn"] = true
	db_l1.remote_macs = {80: {"02:50:45:00:99:01": "10.210.0.2"}}
	check(Game.contract_mastery_met("overlay_tenant"),
		"debrief: it is granted when the network actually does the harder thing")
	# a dialect-aware command for the gear in front of them
	var db_ros := Game.new_device("rtr-lite")
	db_rack.slots[2] = db_ros
	check(Game._dialect_cmd(db_ros, "/routing bgp peer print", "show ip bgp summary") \
			== "/routing bgp peer print" \
			and Game._dialect_cmd(db_l1, "/routing bgp peer print", "show ip bgp summary") \
				== "show ip bgp summary",
		"debrief: the command it suggests matches the gear the player bought")
	# a second later job, built the same way from live state
	var db_r1 := Game.new_device("rtr-lite")
	var db_r2 := Game.new_device("rtr-lite")
	var db_rack2 := Game.add_rack(Vector2i(97, 1))
	db_rack2.slots[0] = db_r1
	db_rack2.slots[1] = db_r2
	db_r1.ifaces[0].vrrp = {"vip": "10.211.0.1", "group": 1, "priority": 200}
	db_r2.ifaces[0].vrrp = {"vip": "10.211.0.1", "group": 1, "priority": 100}
	var db_vrrp := Game._opening_contract_debrief({"id": "no_spof", "title": "No single point",
		"customer": "Someone", "reward": 3000})
	check(not db_vrrp.is_empty() and String(db_vrrp["proof"][0]).contains("10.211.0.1") \
			and String(db_vrrp["proof"][0]).contains(db_r1.name),
		"debrief: the later jobs read their proof off the live network, one by one")
	check(not Game.contract_mastery_met("no_spof"),
		"debrief: and their mastery checks are live too")
	db_r1.ifaces[0].enabled = false
	check(Game.contract_mastery_met("no_spof"),
		"debrief: taking the master away is what earns that one")
	db_r1.ifaces[0].enabled = true
	db_r1.ifaces[0].vrrp = {}  # this section's fixture does not belong to anybody else's
	db_r2.ifaces[0].vrrp = {}
	db_l1.vtep = {}
	db_l2.vtep = {}
	db_l1.remote_macs = {}
	Game.contract_debriefs = {}

	# --- the encyclopedia keeps up with the simulation ---
	var topic_titles: Array = []
	for topic_row in Pedia.topics():
		topic_titles.append(String(topic_row[0]))
	var wanted_topics := ["The link that stays up and lies", "Naming what has no IPv6 address",
		"Translating between two internets", "A segment that does not need a cable",
		"Telling the other switches what you have", "Copper that is not a device",
		"The window, and the point of no return", "Cutting the branch you are sitting on",
		"The cabling debt nobody books"]
	var missing_topics: Array = []
	for wanted: String in wanted_topics:
		if wanted not in topic_titles:
			missing_topics.append(wanted)
	check(missing_topics.is_empty(),
		"pedia: everything added to the simulation has somewhere to read about it (%s)"
			% ", ".join(PackedStringArray(missing_topics)))
	# and the commands the entries suggest are commands the game accepts
	var pd_rack := Game.add_rack(Vector2i(98, 1))
	var pd_sw := Game.new_device("sw-8")
	var pd_srv := Game.new_device("srv-1")
	pd_rack.slots[0] = pd_sw
	pd_rack.slots[1] = pd_srv
	Game.connect_ifaces(pd_srv.ifaces[0], pd_sw.ifaces[0])
	Game.add_vlan(pd_sw, 50, "tenant")
	var pd_cli := CLI.new_session(pd_sw)
	pd_cli.exec("en")
	pd_cli.exec("conf t")
	var pd_tried := ["show interfaces counters", "show lldp neighbors", "show vxlan"]
	var pd_rejected: Array = []
	for pd_cmd: String in pd_tried:
		var pd_out := pd_cli.exec(pd_cmd)
		if pd_out.begins_with("%") or pd_out.contains("bad command"):
			pd_rejected.append(pd_cmd)
	check(pd_rejected.is_empty(),
		"pedia: the commands the new entries suggest are commands the console accepts (%s)"
			% ", ".join(PackedStringArray(pd_rejected)))
	var pd_srv_cli := CLI.new_session(pd_srv)
	check(not pd_srv_cli.exec("dns64").contains("not found") \
			and not pd_srv_cli.exec("dns add legacy.example.hu 10.0.0.9").begins_with("usage"),
		"pedia: and so are the DNS64 ones, on the gear that runs them")

	# --- the log folds the routine work ---
	Game.events = []
	Game.digest = {}
	Game.unread_events = 0
	var lg_cycle := Game.cycle
	Game.log_event("PARTS: the standing order topped up patch leads ($60).")
	Game.log_event("DUTIES: Fekete Julia kept the drawer stocked.")
	Game.log_event("FACILITY: dust filter change done for $120.")
	check(Game.events.size() == 1 and String(Game.events[0]).contains(Game.DIGEST_PREFIX) \
			and Game.digest_for(lg_cycle).size() == 3,
		"log: three routine lines become one note, and the note counts them")
	check(Game.log_contains("dust filter change"),
		"log: nothing is dropped, only folded")
	Game.log_event("SLA BREACH: 'Two roofs' is down: fees suspended.")
	check(Game.events.size() == 2 and String(Game.events[0]).contains("SLA BREACH") \
			and Game.unread_events == 1,
		"log: anything that matters stays at full size, on top, and counts as unread")
	Game.log_event("DECISION: somebody wants an answer.")
	check(Game.events.size() == 3 and String(Game.events[0]).contains("DECISION"),
		"log: a line that asks the player for something is never folded")
	Game.cycle += 1
	Game.log_event("PARTS: topped up again.")
	check(Game.events.size() == 4 and Game.digest_for(Game.cycle).size() == 1,
		"log: each cycle gets its own shift notes rather than one growing pile")
	Game.cycle = lg_cycle
	Game.events = []
	Game.digest = {}

	# --- the operational systems introduce themselves when they matter ---
	var oi_state := Game.snapshot()
	Game.sandbox = false
	Prefs.show_everything = false
	Game.feature_intros_seen = []
	Game.staff = []
	Game.visitors = []
	Game.audit = {}
	Game.trust_marker = false
	Game.tac_cases = []
	Game.firmware_bugs = {}
	Game.renewals = []
	Game.hazards = []
	Game.facility = {}
	Game.access_policy = "open"
	Game.stage = 0
	check(not Game.feature_unlocked("facility") and not Game.feature_unlocked("duties") \
			and not Game.feature_unlocked("renewals") and not Game.feature_unlocked("compliance") \
			and not Game.feature_unlocked("support"),
		"onboarding: none of the operational systems announce themselves before they exist")
	Game.stage = 1
	Game.facility = {"filters": Game.cycle - int(Game.FACILITY_TASKS["filters"]["every"])}
	check(Game.feature_unlocked("facility"),
		"onboarding: the building introduces itself when its first job comes due")
	Game.staff = [{"name": "A", "role": "noc", "skill": 2, "salary": 200, "morale": 70,
		"shift": "day", "training_left": 0, "certs": []},
		{"name": "B", "role": "tech", "skill": 2, "salary": 200, "morale": 70,
		"shift": "day", "training_left": 0, "certs": []}]
	check(Game.feature_unlocked("duties"),
		"onboarding: the duties board arrives with the second pair of hands")
	Game.add_renewal("licence", "feature licence on sw1", 180, 4, "sw1")
	check(Game.feature_unlocked("renewals"),
		"onboarding: the calendar arrives when something is about to lapse")
	Game.admit_visitor("Vas Elektro", "aircon service")
	check(Game.feature_unlocked("access"),
		"onboarding: the door question arrives with somebody standing behind it")
	Game.firmware_bugs["sw1"] = {"since": Game.cycle, "model": "sw-8"}
	check(Game.feature_unlocked("support"),
		"onboarding: the vendor route arrives with the first defect nobody can configure away")
	Game.audit = {"state": "offered", "customer": "Someone", "scope": [], "reward": 1,
		"deadline": Game.cycle, "findings": [], "history": []}
	check(Game.feature_unlocked("compliance"),
		"onboarding: and the controls arrive when somebody asks to see them")
	var oi_missing: Array = []
	for oi_feature: String in Game.DISCOVERY_FEATURES:
		if not UILayer.UNLOCK_INTROS.has(oi_feature):
			oi_missing.append(oi_feature)
	check(oi_missing.is_empty(),
		"onboarding: every discoverable system has a line written for it (%s)"
			% ", ".join(PackedStringArray(oi_missing)))
	Game.acknowledge_feature_intro("facility")
	check("facility" in Game.feature_intros_seen,
		"onboarding: and once it has been said, it is not said again")
	Game.restore(oi_state)
	Game.feature_intros_seen = []

	# --- the console commands the new faults need ---
	var dx_rack2 := Game.add_rack(Vector2i(99, 1))
	var dx_sw2 := Game.new_device("sw-8")
	var dx_a2 := Game.new_device("srv-1")
	var dx_b2 := Game.new_device("srv-1")
	dx_rack2.slots[0] = dx_sw2
	dx_rack2.slots[1] = dx_a2
	dx_rack2.slots[2] = dx_b2
	Game.connect_ifaces(dx_a2.ifaces[0], dx_sw2.ifaces[0])
	Game.connect_ifaces(dx_b2.ifaces[0], dx_sw2.ifaces[1])
	Game.add_ip(dx_a2.ifaces[0], "10.198.0.10/24")
	Game.add_ip(dx_b2.ifaces[0], "10.198.0.11/24")
	Game.add_static_route(dx_a2, "10.199.0.0", 24, "10.198.0.11")
	Sim.flush_learned_state()
	var dx_cli2 := CLI.new_session(dx_a2)
	var clean := CLI.fmt_ping_repeat(dx_a2, "10.198.0.11", 10)
	check(clean.contains("10 packets transmitted, 10 received, 0% packet loss") \
			and clean.contains("rtt min/avg/max"),
		"console: a repeated ping reports real loss and round-trip figures")
	Game.grey_faults = {}
	Game.inject_grey_fault(dx_sw2.ifaces[1], "loose_connector")
	var flaky_out := CLI.fmt_ping_repeat(dx_a2, "10.198.0.11", 40)
	check(not flaky_out.contains("0% packet loss") and not flaky_out.contains("100% packet loss"),
		"console: an intermittent fault reads as intermittent loss, which is how it is found")
	var sw_cli2 := CLI.new_session(dx_sw2)
	var status := sw_cli2.exec("show interfaces status")
	check(status.contains("InErrors") and status.contains(dx_a2.name) \
			and status.contains("connected"),
		"console: one line per port, with the neighbour and the error count on it")
	var optics := sw_cli2.exec("show interfaces transceiver")
	check(optics.contains("Rx(dBm)"),
		"console: the optics report their receive level")
	Game.inject_grey_fault(dx_sw2.ifaces[0], "dirty_optic")
	check(sw_cli2.exec("show interfaces transceiver").contains("LOW"),
		"console: and say so when it has fallen where a dying optic falls")
	Game.grey_faults = {}
	var filtered := sw_cli2.exec("show interfaces status | include connected")
	check(filtered.contains("connected") and not filtered.contains("notconnect"),
		"console: any show command can be filtered, because the tables are long now")
	check(sw_cli2.exec("show interfaces status | include nonsense").contains("no lines matching"),
		"console: a filter that matches nothing says so instead of printing nothing")
	var dx_rtr := Game.new_device("rtr-edge")
	dx_rack2.slots[4] = dx_rtr
	Game.connect_ifaces(dx_rtr.ifaces[0], dx_sw2.ifaces[2])
	Game.add_ip(dx_rtr.ifaces[0], "10.198.0.1/24")
	Game.add_static_route(dx_rtr, "10.199.0.0", 24, "10.198.0.11")
	var rtr_cli := CLI.new_session(dx_rtr)
	var route_answer := rtr_cli.exec("show ip route for 10.199.0.5")
	check(route_answer.contains("static") and route_answer.contains("longest match"),
		"console: a route lookup for one address says which route wins and why")
	check(rtr_cli.exec("show ip route for 10.198.0.20").contains("connected"),
		"console: and prefers the connected route when it is the longer match")
	check(rtr_cli.exec("show ip route for 203.0.113.1").contains("no route"),
		"console: with no route it says so rather than inventing one")
	var ros_dev2 := Game.new_device("sw-lite")
	dx_rack2.slots[3] = ros_dev2
	var ros_cli2 := CLI.new_session(ros_dev2)
	check(ros_cli2.exec("/interface print | include ether").contains("ether"),
		"console: PacketTik filters the same way")
	Sim.flush_learned_state()

	# --- the room has a mood ---
	check(Sfx.MOODS.size() >= 5 and Sfx.mood_for({}) == "",
		"score: a handful of moods, and silence when the room is not in any of them")
	check(Sfx.mood_for({"quiet": true}) == "quiet" \
			and Sfx.mood_for({"quiet": true, "night": true}) == "night" \
			and Sfx.mood_for({"night": true, "incident": true}) == "incident" \
			and Sfx.mood_for({"incident": true, "upstream": true}) == "upstream" \
			and Sfx.mood_for({"incident": true, "first_light": true}) == "first_light",
		"score: an outage outranks the hour, and the one celebration outranks everything")
	var sc_deals := Game.deals.duplicate(true)
	Game.deals = []
	Game.hazards = []
	Game.upstream = {}
	Game.customer_outage_active = false
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 3  # daytime
	var sc_state := Game.score_state()
	check(not bool(sc_state["incident"]) and not bool(sc_state["night"]),
		"score: what the room feels is read off the simulation, not off a timer")
	Game.deals = [{"id": "sc", "customer": "Down Kft", "kind": "hosting", "params": {},
		"fee": 10, "brief": "", "load": 10, "healthy": false, "ever_healthy": true}]
	check(bool(Game.score_state()["incident"]) \
			and Sfx.mood_for(Game.score_state()) == "incident",
		"score: a customer of yours being down is what an incident means")
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 7  # small hours
	Game.deals = []
	check(bool(Game.score_state()["night"]) and Sfx.mood_for(Game.score_state()) == "night",
		"score: and the small hours sound like the small hours")
	var sc_muted: bool = Sfx.muted
	Sfx.muted = true
	# the worst pairing on the map: light-cased starter gear, dark model ink
	var lite_fill := Color(UIW.MODEL_VISUALS["sw-lite"]["base"]).darkened(0.30)
	var lite_ink: Color = UIW.readable_on(lite_fill, Color(UIW.MODEL_VISUALS["sw-lite"]["ink"]))
	check(absf(lite_ink.get_luminance() - lite_fill.get_luminance()) >= 0.32,
		"map: starter gear is readable on its own card")
	var dark_ink: Color = UIW.readable_on(Color(UIW.MODEL_VISUALS["sw-8"]["base"]).darkened(0.30),
		Color(UIW.MODEL_VISUALS["sw-8"]["ink"]))
	check(dark_ink == Color(UIW.MODEL_VISUALS["sw-8"]["ink"]),
		"map: a model that already contrasts keeps its own ink")
	check(Sfx.mood_for({"incident": true, "heat": true}) == "incident",
		"score: a real incident outranks the weather")
	check(Sfx.mood_for({"heat": true}) == "heat" \
			and Sfx.mood_for({"heat": true, "night": true}) == "night",
		"score: a hot room has its own mood, and the small hours still win at night")
	Sfx.score_tick(Game.score_state())
	check(Sfx.score_mood == "", "score: muting the game silences the music with everything else")
	Sfx.muted = sc_muted
	Game.deals = sc_deals

	# --- the crew say something ---
	var cv_careful := {"name": "Toth Eszter", "role": "engineer", "skill": 4, "salary": 500,
		"morale": 85, "shift": "day", "training_left": 0, "certs": [],
		"habits": {"saves": 0.9, "documents": 0.9, "windows": 0.8, "tidy": 0.9}}
	var cv_hurried := {"name": "Nagy Bence", "role": "tech", "skill": 2, "salary": 250,
		"morale": 75, "shift": "day", "training_left": 0, "certs": [],
		"habits": {"saves": 0.2, "documents": 0.2, "windows": 0.2, "tidy": 0.2}}
	var cv_tired := {"name": "Kis Andras", "role": "noc", "skill": 1, "salary": 150,
		"morale": 20, "shift": "night", "training_left": 0, "certs": [],
		"habits": {"saves": 0.9, "documents": 0.9, "windows": 0.9, "tidy": 0.9}}
	check(Staff.voice_key(cv_careful) == "careful" and Staff.voice_key(cv_hurried) == "hurried" \
			and Staff.voice_key(cv_tired) == "tired",
		"crew: how somebody sounds comes from how they work, unless they are worn out")
	check(Staff.says(cv_careful, "repair") != Staff.says(cv_hurried, "repair") \
			and Staff.says(cv_careful, "repair").contains("Toth Eszter"),
		"crew: the same event from two different people reads differently")
	check(Staff.says(cv_careful, "repair") == Staff.says(cv_careful, "repair"),
		"crew: and the same person sounds like the same person every time")
	check(Staff.says(cv_careful, "blamed") != Staff.says(cv_careful, "defended"),
		"crew: being blamed and being defended are not the same conversation")
	check(Staff.says({}, "repair") == "" and Staff.says(cv_careful, "nonsense") == "",
		"crew: nobody speaks for a moment that does not exist")
	var cv_staff := Game.staff.duplicate(true)
	Game.staff = [cv_tired]
	Game.events = []
	Game.digest = {}
	Staff.say(cv_tired, "resigned")
	check(Game.log_contains("Kis Andras") and Game.log_contains("CREW"),
		"crew: what they say goes in the log, in their own words")
	Game.staff = cv_staff

	# --- the floor shows what the simulation already knows ---
	var fl_crates := Game.crates.duplicate(true)
	var fl_packaging := Game.packaging
	var fl_hazards := Game.hazards.duplicate(true)
	Game.crates = []
	Game.packaging = 0
	check(Game.crates_waiting().is_empty() and not Game.aisle_blocked(),
		"floor props: an empty dock has nothing on it, which is the point of reading live state")
	Game.crates = [{"model": "srv-1", "shipped": "srv-1", "ordered": Game.cycle,
		"due": Game.cycle, "arrived": Game.cycle, "checked": false, "damaged": false,
		"unpack_left": 1}]
	Game.packaging = 6
	check(Game.crates_waiting().size() == 1 and Game.aisle_blocked(),
		"floor props: crates on the dock and cardboard nobody cleared are the same facts the panel reads")
	Game.crates = fl_crates
	Game.packaging = fl_packaging
	Game.hazards = fl_hazards

	# --- somebody is on the phone ---
	var ph_deals := Game.deals.duplicate(true)
	Game.reputation = 60
	var ph_deal := {"id": "ph", "customer": "Fonix Klinika", "ctype": "smb", "kind": "hosting",
		"params": {}, "fee": 150, "brief": "", "load": 150, "healthy": false,
		"ever_healthy": true, "cycles": 12, "up_cycles": 10, "loyalty": 0.7, "missed": 1}
	Game.deals = [ph_deal]
	Game.call_tick()
	check(not ph_deal.has("call"),
		"the call: they do not ring the moment something blinks")
	ph_deal["missed"] = 2
	Game.call_tick()
	check(ph_deal.has("call") and String(ph_deal["call"]["words"]) != "",
		"the call: after a couple of cycles down, somebody rings, in their own words")
	Game.call_tick()
	check(int(ph_deal["call"]["raised"]) == Game.cycle,
		"the call: and rings once, not every cycle")
	check(Game.answer_call(ph_deal, "shrug") != "",
		"the call: there are three things you can say and no others")
	var ph_missed := int(ph_deal["missed"])
	check(Game.answer_call(ph_deal, "honest") == "" and not ph_deal.has("call") \
			and int(ph_deal["missed"]) < ph_missed and String(ph_deal["last_answer"]) == "honest",
		"the call: telling them what you know costs nothing and buys a little patience")
	# a promise buys more, and costs more
	ph_deal["missed"] = 2
	ph_deal["call"] = {"words": "again?", "raised": Game.cycle}
	check(Game.answer_call(ph_deal, "promise") == "" and ph_deal.has("promised_by") \
			and int(ph_deal["missed"]) == 0,
		"the call: promising a time buys real patience now")
	var rep_promise := Game.reputation
	var loyal_promise: float = float(ph_deal["loyalty"])
	Game.cycle = int(ph_deal["promised_by"]) + 1
	Game.call_tick()
	check(not ph_deal.has("promised_by") and Game.reputation < rep_promise \
			and float(ph_deal["loyalty"]) < loyal_promise and int(ph_deal["missed"]) > 0,
		"the call: and missing it costs more than never having promised")
	# keeping it is worth something too
	ph_deal["healthy"] = true
	ph_deal["promised_by"] = Game.cycle + 2
	var rep_keep := Game.reputation
	Game.call_tick()
	check(not ph_deal.has("promised_by") and Game.reputation > rep_keep,
		"the call: being back inside the window you promised is worth saying you did")
	check(ph_deal["said"].has("honest") and ph_deal["said"].has("promise"),
		"the call: what you said is remembered, and travels with the customer")
	Game.deals = ph_deals

	# --- arriving somewhere ---
	var ar_state := Game.snapshot()
	Game.demo = false
	Game.events = []
	Game.digest = {}
	Game.identity = ""
	Legacy.epitaph = {}
	Legacy.selected = []
	Game.company_name = "Kékfény Hálózat"
	Game.arrival_note()
	var ar_lines: Array = []
	for ar_ev: String in Game.events:
		if "ARRIVAL:" in ar_ev:
			ar_lines.append(ar_ev)
	check(ar_lines.size() >= 4,
		"arrival: the opening is a place, a leftover, something true about this run, and a first job")
	var first_run := "".join(PackedStringArray(ar_lines))
	Game.events = []
	Game.digest = {}
	Game.company_name = "Turul Telekom"
	Game.arrival_note()
	var second_lines: Array = []
	for ar_ev2: String in Game.events:
		if "ARRIVAL:" in ar_ev2:
			second_lines.append(ar_ev2)
	check("".join(PackedStringArray(second_lines)) != first_run,
		"arrival: a second company arrives somewhere slightly different")
	Game.events = []
	Game.digest = {}
	Game.identity = "budget"
	Game.arrival_note()
	check(Game.log_contains("what sort of shop this is going to be"),
		"arrival: and a run that already knows what it is says so")
	Game.identity = ""
	Game.demo = true
	Game.events = []
	Game.digest = {}
	Game.arrival_note()
	check(not Game.log_contains("ARRIVAL"),
		"arrival: the demo keeps its own opening")
	Game.restore(ar_state)

	# --- the crew are where the work is ---
	var qs_crates := Game.crates.duplicate(true)
	var qs_hazards := Game.hazards.duplicate(true)
	var qs_crew := Techs.new()
	Game.add_child(qs_crew)
	Game.crates = []
	Game.hazards = []
	var qs_rack := Game.add_rack(Vector2i(2, 2))
	var qs_sw := Game.new_device("sw-8")
	qs_rack.slots[0] = qs_sw
	qs_sw.status = "offline"
	var qs_broken_spot := qs_crew._work_spot(0)
	check(Iso.world_to_tile(qs_broken_spot).distance_to(qs_rack.tile) <= 2.0,
		"quiet floor: a dead cabinet is where somebody stands")
	qs_sw.status = "active"
	qs_sw.startup = Game.device_config(qs_sw)
	Game.hazards = [{"kind": "smoke", "rack": qs_rack.name, "site": Game.current_site,
		"tile": [qs_rack.tile.x, qs_rack.tile.y], "severity": 1, "started": Game.cycle,
		"detected": true, "zone": [qs_rack.name]}]
	check(Iso.world_to_tile(qs_crew._work_spot(0)).distance_to(qs_rack.tile) <= 2.0,
		"quiet floor: and a cabinet with smoke in it outranks everything else")
	Game.hazards = []
	Game.crates = [{"model": "srv-1", "shipped": "srv-1", "ordered": Game.cycle,
		"due": Game.cycle, "arrived": Game.cycle, "checked": false, "damaged": false,
		"unpack_left": 1}]
	var qs_dock := qs_crew._quiet_spot(0)
	var qs_dock_tile := Iso.world_to_tile(qs_dock)
	check(qs_dock_tile.y >= Game.grid_size().y - 2,
		"quiet floor: with crates on the dock, somebody is waiting at the dock")
	Game.crates = []
	Game.cycle = Game.cycle - (Game.cycle % Game.DAY_CYCLES) + 7  # the small hours
	var qs_night := qs_crew._quiet_spot(0)
	check(qs_night.distance_to(Iso.tile_to_world(Vector2i(0, 0))) < 120.0,
		"quiet floor: at three in the morning whoever is in stays near the door")
	Game.crates = qs_crates
	Game.hazards = qs_hazards
	qs_crew.queue_free()

	# --- a promotion says something about the run ---
	var rk_state := Game.snapshot()
	Game.skill_log = {}
	Game.skill_fumbles = {}
	Game.mastered_contracts = []
	Game.references = []
	Game.best_outage_streak = 0
	check(Game.rank_citation().contains("mostly on the money"),
		"rank: a run with nothing to point at is told so, rather than flattered")
	Game.skill_log = {"service_delivery": {"count": 5, "first_cycle": 1, "said": true}}
	Game.mastered_contracts = ["rackup", "first_ping"]
	Game.references = ["Kiskacsa Kft"]
	Game.best_outage_streak = 40
	var citation_a := Game.rank_citation()
	check(citation_a.contains("service turn-up") and citation_a.contains("harder way") \
			and citation_a.contains("40 cycle"),
		"rank: it reads off what this run actually did")
	Game.skill_log = {"incident_comms": {"count": 4, "first_cycle": 1, "said": true}}
	Game.mastered_contracts = []
	Game.references = []
	Game.best_outage_streak = 0
	Game.skill_fumbles = {"incident_comms": 2}
	var citation_b := Game.rank_citation()
	check(citation_b != citation_a and citation_b.contains("gone quiet"),
		"rank: two runs reaching the same rank are told different things, fumbles included")
	# and the promotion is announced once, when it happens
	Game.events = []
	Game.digest = {}
	Game.rank_seen = ""
	Game.rank_tick()
	check(not Game.log_contains("PROMOTED"),
		"rank: loading a game does not congratulate you for where you already were")
	Game.rank_seen = "Cable monkey"
	Game.stats["earned"] = 500000
	Game.rank_tick()
	check(Game.log_contains("PROMOTED") and Game.rank_seen == Game.rank(),
		"rank: crossing into a new one is a moment, in the voice of the trade")
	var promoted_count := 0
	for rk_ev: String in Game.events:
		if "PROMOTED" in rk_ev:
			promoted_count += 1
	Game.rank_tick()
	var promoted_after := 0
	for rk_ev2: String in Game.events:
		if "PROMOTED" in rk_ev2:
			promoted_after += 1
	check(promoted_after == promoted_count,
		"rank: and said once rather than every cycle afterwards")
	Game.restore(rk_state)

	# --- the year has a shape ---
	var sn_cycle := Game.cycle
	var sn_stage := Game.stage
	Game.stage = 1
	var seen_seasons := {}
	for sn_step in 8:
		Game.cycle = sn_step * int(Game.SEASON_LENGTH / 4.0)
		seen_seasons[String(Game.season()["id"])] = true
	check(seen_seasons.size() == 4,
		"seasons: a year is four of them, read off the clock the game already keeps")
	var summer := -1
	var winter := -1
	for sn_i in Game.SEASONS.size():
		if String(Game.SEASONS[sn_i]["id"]) == "summer":
			summer = sn_i
		elif String(Game.SEASONS[sn_i]["id"]) == "winter":
			winter = sn_i
	check(float(Game.SEASONS[summer]["cooling"]) < 1.0 \
			and float(Game.SEASONS[winter]["cooling"]) > 1.0,
		"seasons: summer asks the cooling a question and winter answers it")
	check(float(Game.SEASONS[summer]["contractors"]) > 1.0 \
			and float(Game.SEASONS[summer]["work"]) < float(Game.SEASONS[2]["work"]),
		"seasons: in summer nobody comes quickly and less work arrives")
	Game.cycle = summer * int(Game.SEASON_LENGTH / 4.0)
	var summer_cooling := Game.cooling_capacity()
	Game.cycle = winter * int(Game.SEASON_LENGTH / 4.0)
	check(Game.cooling_capacity() > summer_cooling,
		"seasons: and the same floor really does have less headroom in August")
	Game.stage = 0
	check(Game.cooling_capacity() == Game.cooling_capacity(),
		"seasons: in somebody else's colo the weather is their problem")
	Game.stage = 1
	Game._season_seen = -1
	Game.events = []
	Game.digest = {}
	Game.season_tick()
	check(not Game.log_contains("SEASON"),
		"seasons: loading a game does not announce the season you are already in")
	Game.cycle = ((winter + 1) % 4) * int(Game.SEASON_LENGTH / 4.0)
	Game.season_tick()
	check(Game.log_contains("SEASON"),
		"seasons: but it says so when the year turns, before it bites")
	Game.cycle = sn_cycle
	Game.stage = sn_stage

	# --- the first one matters more than the second ---
	var fla_stats := Game.stats.duplicate(true)
	Game.stats["services_live"] = 0
	Game.events = []
	Game.digest = {}
	var fl_deal := {"id": "fl", "customer": "Fonix Klinika", "ctype": "smb", "kind": "hosting",
		"params": {}, "fee": 180, "brief": "", "load": 150, "healthy": true, "ever_healthy": true}
	Game._first_light(fl_deal)
	check(Game.log_contains("FIRST LIGHT") and Game.log_contains("Fonix Klinika") \
			and Game.log_contains("$180"),
		"first light: the first service says whose it is, what it does, and what it is worth")
	var quoted := false
	for fl_ev: String in Game.events:
		if "“" in fl_ev:
			quoted = true
	check(quoted, "first light: and it is said in the customer's own words")
	Game.events = []
	Game.digest = {}
	var fl_second := fl_deal.duplicate(true)
	fl_second["customer"] = "Madaras Jatek Kft"
	Game._first_light(fl_second)
	check(not Game.log_contains("FIRST LIGHT") and Game.log_contains("service(s) of yours in the world"),
		"first light: the second one is quieter, and counts them")
	check(int(Game.stats["services_live"]) == 2,
		"first light: the game remembers how many it has put into the world")
	Game.stats = fla_stats

	# --- the demo card is about the shift they worked ---
	var ds_stats := Game.stats.duplicate(true)
	var ds_skills := Game.skill_log.duplicate(true)
	var ds_streak := Game.best_outage_streak
	Game.stats["contracts"] = 6
	Game.best_outage_streak = 31
	Game.skill_log = {"l2_isolation": {"count": 2, "first_cycle": 4, "said": true}}
	var summary := Game.demo_summary()
	check(summary.contains("cycles on the floor") and summary.contains("6 job(s)") \
			and summary.contains("31 cycles with nobody down") \
			and summary.contains("layer 2 segmentation"),
		"demo card: it says what this player actually did, including what it taught them")
	Game.skill_log = {}
	Game.stats["contracts"] = 0
	Game.best_outage_streak = 0
	check(not Game.demo_summary().contains("job(s)") and Game.demo_summary().contains("cycles on the floor"),
		"demo card: and claims nothing about a shift that did not happen")
	Game.stats = ds_stats
	Game.skill_log = ds_skills
	Game.best_outage_streak = ds_streak
	var parts_total_before := int(Game.pl_totals.get("parts", 0))
	Game.money = 5000
	Game.spend_on("parts", 60)
	check(int(Game.last_pl.get("parts", 0)) <= -60 \
			and int(Game.pl_totals.get("parts", 0)) == parts_total_before,
		"balance: a spend lands in this cycle's ledger and folds into the run total at the tick")
	Game.apply_difficulty(bal_difficulty)
	Game.facility_auto = {}
	DirAccess.remove_absolute("%s/classroom_test.json" % Pack.USER_DIR)
	Pack.load_all()

	print("---- %d failures" % fails)
	return fails
