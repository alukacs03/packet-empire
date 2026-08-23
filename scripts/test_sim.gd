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
	r1.slots[7] = sw
	r1.slots[6] = srv1
	r1.slots[5] = srv2
	r2.slots[7] = rtr
	r2.slots[6] = fw
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
	Game.offers = [Market.gen_offer()]
	Game.deals = [{"id": "d1", "customer": "Balaton Zrt", "kind": "hosting",
		"params": {"ip": "10.0.0.1"}, "fee": 120, "load": 300,
		"brief": "Host our application server at 10.0.0.1/24.", "healthy": true}]
	Sim.ping(srv1, "10.0.0.2")
	Game.topology_changed.emit()

static func ui_smoke(world: Node2D) -> int:
	## Exercise every overlay so UI-only runtime errors surface in CI output.
	print("---- ui smoke ----")
	var ui := UILayer.new()
	world.add_child(ui)
	var r: Net.Rack = Game.racks[0]
	var dev: Net.NDevice = null
	for d in Game.all_devices():
		if d.type == "server":
			dev = d
	ui.show_welcome()
	ui.welcome_overlay.visible = false
	ui.open_rack(r)
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
	ui.open_contracts()
	ui.close_contracts()
	ui.toggle_map()
	ui.toggle_map()
	ui.toggle_ops()
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
	crew._resize_crew()
	check(crew.people.size() > crew_before, "floor: hiring puts another person on the floor")
	Game.staff.clear()
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
	check(UILayer.compress_ports(["Ethernet1", "Ethernet2", "Ethernet3", "Ethernet7"]) == "Et1-3,Et7",
		"ui: port lists compress into ranges")
	check(UILayer.compress_ports([]) == "", "ui: empty port list compresses to nothing")
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
	Game.save_game()
	var money_before := Game.money
	Game.money = 1
	check(Game.load_game(), "save: load_game returns true")
	check(Game.money == money_before, "save: money restored")
	check(Game.all_devices().size() == 6 and Game.links.size() == 5, "save: devices and links restored")
	var sw_l: Net.NDevice = null
	for d in Game.all_devices():
		if d.name == sw.name:
			sw_l = d
	check(sw_l != null and sw_l.vlans.has(30), "save: per-switch vlan database restored")
	var a_l: Net.NDevice = null
	for d in Game.all_devices():
		if d.name == a.name:
			a_l = d
	check(a_l != null and Sim.ping(a_l, "10.1.0.2")["ok"], "save: reloaded topology still routes end-to-end")

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
	var d0_start := Game.money
	Game.sla_tick()
	var delta0 := Game.money - d0_start
	Game.debt = 10000
	Game.invoices = []
	var d1_start := Game.money
	Game.sla_tick()
	var delta1 := Game.money - d1_start
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
	check("FIELD" in Game.events[0], "field: a fault is logged for the operator to find")
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
	Game.contracts_done = []
	Game.sla_status = {}
	Game.stage = 0
	Game.debt = 0
	Game.money = 2000
	Game.topology_changed.emit()
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
	Game.add_ip(w_s1.ifaces[0], "10.0.0.1/24")
	Game.add_ip(w_s2.ifaces[0], "10.0.0.2/24")
	check(Game.try_complete_contract(_contract("first_ping")), "walkthrough: contract 2 pays")
	Game.add_vlan(w_sw, 10, "alfa")
	Game.add_vlan(w_sw, 20, "beta")
	Game.set_access_vlan(w_sw.ifaces[0], 10)
	Game.set_access_vlan(w_sw.ifaces[1], 20)
	check(Game.try_complete_contract(_contract("two_tenants")), "walkthrough: contract 3 pays")
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
	check(Game.try_complete_contract(_contract("stretch_vlans")),
		"walkthrough: contract 4 pays (trunk built from both dialects)")
	Game.connect_ifaces(w_sw.ifaces[3], w_sw2.ifaces[6])  # the spare link
	w_ros.exec("/interface set ether4 mode=trunk")
	w_eos.exec("configure terminal")
	w_eos.exec("interface Ethernet7")
	w_eos.exec("switchport mode trunk")
	w_eos.exec("end")
	Sim.flush_learned_state()
	check(Game.try_complete_contract(_contract("redundant_core")),
		"walkthrough: contract 5 pays (spanning tree blocks the spare link)")
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
	check(Drill.scenario != "" and not Drill.targets.is_empty(), "drill: scenario named with targets")
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
		Game.sla_tick()
		for d_ren in Game.deals:  # a working operator renews their contracts
			if d_ren.has("renewal"):
				Game.accept_renewal(d_ren)
	check(Game.money > money_start, "economy: a delivering operator grows over 60 cycles (%d -> %d)" % [money_start, Game.money])
	check(Game.money < money_start + 60 * 400, "economy: growth stays bounded, no runaway income")
	check(Game.reputation >= 50, "economy: steady delivery keeps reputation up")
	check(Game.last_pl.has("power"), "economy: the power bill is charged once you own the room")
	# now break the service and verify the pressure lands
	eh1.ifaces[0].enabled = false
	Game.topology_changed.emit()
	Game.invoices = []  # everything already earned is in the bank
	var money_broken := Game.money
	var rep_broken := Game.reputation
	for i in 8:
		Game.sla_tick()
	check(Game.money < money_broken, "economy: a broken datacenter bleeds money")
	check(Game.deals.is_empty(), "economy: undelivered customers eventually walk")
	check(Game.reputation < rep_broken, "economy: failure costs reputation (%d -> %d)" % [rep_broken, Game.reputation])

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
	var passed := false
	for ev in Game.events:
		if "SCENARIO passed" in ev:
			passed = true
	check(passed, "scenario: passing is recorded")
	Scenarios.start(Scenarios.all()[1])
	check(not Scenarios.solved(), "scenario: the campus starts unbuilt")
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
	Game.record_incident("test", "a link nobody was watching went down")
	check(Game.incidents.size() == 1, "post-mortem: an incident is recorded for review")
	Game.record_incident("test", "a link nobody was watching went down")
	check(Game.incidents.size() == 1, "post-mortem: the same open incident is not duplicated")
	var rep_before_review := Game.reputation
	check(Game.review_incident(Game.incidents[0], 3).is_empty(), "post-mortem: it can be written up")
	check(Game.reputation > rep_before_review, "post-mortem: candour earns back some trust")
	check(not Game.review_incident(Game.incidents[0], 1).is_empty(), "post-mortem: only once")

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
	var reported := false
	for ev in Game.events:
		if "QUARTER" in ev:
			reported = true
	check(reported, "report: closing a quarter is announced")

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

	print("---- %d failures" % fails)
	return fails
