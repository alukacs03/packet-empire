class_name DesignTests

static func fixture() -> Dictionary:
	Game._apply(Game._pristine.duplicate(true))
	Game.money = 12000
	Game.board_targets = false
	Game.parts = {"patch": 30, "optic": 10, "blank": 20, "power": 20}
	Game.rivals = []
	Game.stats["customer_arc_version"] = 1
	Game.stats["guided_delivery_acknowledged"] = 1
	Game.stats["guided_outage_complete"] = 1
	var rack := Game.add_rack(Vector2i(1, 1))
	var sw := Game.new_device("sw-lite")
	var a := Game.new_device("srv-1")
	var b := Game.new_device("srv-1")
	Game.install_device(rack, 0, sw)
	Game.install_device(rack, 2, a)
	Game.install_device(rack, 4, b)
	Game.connect_ifaces(sw.ifaces[0], a.ifaces[0])
	Game.connect_ifaces(sw.ifaces[1], b.ifaces[0])
	Game.add_ip(a.ifaces[0], "10.42.18.10/24")
	Game.add_ip(b.ifaces[0], "10.42.18.11/24")
	var deal := {"id": "design_kiskacsa", "customer": "Kiskacsa Kft", "guided": true,
		"kind": "hosting", "params": {"ip": "10.42.18.10"}, "healthy": true,
		"ever_healthy": true, "degraded": false, "fee": 118, "load": 150,
		"brief": "Keep our webshop reachable.", "ctype": "startup", "sla": 0,
		"cycles": 0, "up_cycles": 0, "term": 100, "loyalty": 0.75}
	Game.deals = [deal]
	Game.contracts_done = ["rackup", "first_ping", "two_tenants"]
	Game.guided_outage = {"state": "complete"}
	return {"rack": rack, "sw": sw, "a": a, "b": b, "deal": deal}

static func run() -> void:
	var before := Game.snapshot()
	SimTests.check(CustomerBrief.margin_text(1000, 650) == Loc.t("brief.forecast_spare") % 350 and
		CustomerBrief.margin_text(650, 650) == Loc.t("brief.forecast_exact") and
		CustomerBrief.margin_text(500, 950) == Loc.t("brief.forecast_short") % 450,
		"sale feedback: forecast distinguishes spare, exact capacity and shortfall")
	var observations := [{"served": false}, {"served": true}]
	var chart := CustomerBrief.DemandChart.new().setup([500, 950, 750], 1000, 1, observations)
	observations[0]["served"] = true
	chart.capacity = 0
	SimTests.check(chart.wave_status(0)["semantic"] == "warning" and chart.wave_status(1)["semantic"] == "success" and
		not chart.wave_status(2)["observed"] and chart.wave_status(2)["semantic"] == "warning",
		"sale feedback: historical outcomes are immutable while future waves reflect current capacity")
	chart.free()
	var translated := Loc.pseudo("Cycle %d: %s, $%.2f, %02d, %% {customer}")
	SimTests.check(translated.contains("%s") and translated.contains("{customer}") and
		(translated % [3, "healthy", 1.25, 4]).contains("healthy"),
		"localisation: pseudo text preserves formatting directives and named placeholders")
	var f := fixture()
	var test_link: Net.Link = Game.link_at(f["a"].ifaces[0])
	SimTests.check(not UIW.TopoMap.link_unavailable(test_link), "map feedback: a working physical link is available")
	test_link.a.admin_down = true
	SimTests.check(UIW.TopoMap.link_unavailable(test_link), "map feedback: administrative shutdown cannot show flowing traffic")
	test_link.a.admin_down = false
	test_link.b.enabled = false
	SimTests.check(UIW.TopoMap.link_unavailable(test_link), "map feedback: either disabled endpoint marks the link down")
	test_link.b.enabled = true
	test_link.b.dev.status = "offline"
	SimTests.check(UIW.TopoMap.link_unavailable(test_link), "map feedback: an offline endpoint marks the link down")
	test_link.b.dev.status = "active"
	Game.site_feeds(0)["A"] = false
	SimTests.check(UIW.TopoMap.link_unavailable(test_link), "map feedback: loss of facility power marks the link down")
	Game.site_feeds(0)["A"] = true
	var saved_blocks: Dictionary = Sim._stp_blocked.duplicate()
	Sim._stp_blocked[test_link.a] = true
	SimTests.check(not UIW.TopoMap.link_unavailable(test_link), "map feedback: intentional STP blocking is not a physical outage")
	Sim._stp_blocked = saved_blocks
	var remote_rack := Net.Rack.new("Remote", Vector2i(2, 1))
	remote_rack.site = 1
	var remote := Game.new_device("srv-1")
	remote_rack.slots[0] = remote
	Game.racks.append(remote_rack)
	var wan := Net.Link.new(f["sw"].ifaces[2], remote.ifaces[0])
	Game.links.append(wan)
	SimTests.check(UIW.TopoMap.link_unavailable(wan), "map feedback: a cross-site cable needs an available WAN circuit")
	Game.circuits = [{"a": 0, "b": 1, "mbps": 1000, "carrier": Game.CARRIERS[0]}]
	SimTests.check(not UIW.TopoMap.link_unavailable(wan), "map feedback: a working WAN circuit carries the cross-site cable")
	Game.carrier_outage[Game.CARRIERS[0]] = Game.cycle + 3
	SimTests.check(UIW.TopoMap.link_unavailable(wan), "map feedback: a carrier outage stops the cross-site flow")
	f = fixture()
	FirstCustomer.tick()
	SimTests.check(String(FirstCustomer.state()["phase"]) == "planning", "opening: a recovered customer invites the player to plan a sale")
	SimTests.check(FirstCustomer.path(f["deal"]).size() == 1 and int(FirstCustomer.forecast()["headroom"]) == 1000,
		"opening: local hosting has a real access path and finite capacity without a default route")
	var funds := Game.money
	SimTests.check(FirstCustomer.choose("premiere") == "" and Game.money == funds - 120, "opening: the ambitious launch reserves a promotion at a visible cost")
	SimTests.check(FirstCustomer.choose("premiere") != "" and Game.money == funds - 120, "opening: a plan cannot charge twice")
	var saved := Game.snapshot()
	Game.restore(saved)
	SimTests.check(FirstCustomer.state()["plan"] == "premiere" and int(FirstCustomer.state()["starts"]) == 4, "opening: reload preserves the chosen plan and deadline")
	for _n in 6: Game.sla_tick()
	SimTests.check(FirstCustomer.state()["phase"] == "debrief" and int(FirstCustomer.state()["successes"]) == 3,
		"opening: three actual billing cycles carry all three waves on a working gigabit service")
	SimTests.check(int(FirstCustomer.state()["bonus"]) == 650, "opening: a fully delivered launch earns its promised bonus")
	var paid := Game.money
	FirstCustomer.tick()
	SimTests.check(Game.money == paid, "opening: revisiting the debrief cannot pay the bonus twice")
	var evidence: Dictionary = FirstCustomer.state()["after"].duplicate(true)
	Game.links.clear()
	FirstCustomer.tick()
	SimTests.check(FirstCustomer.state()["after"] == evidence, "opening: post-sale network changes cannot rewrite the debrief evidence")
	FirstCustomer.acknowledge()
	SimTests.check(FirstCustomer.complete() and FirstCustomer.protected_time(), "opening: a completed night leaves a short quiet period")
	Game.cycle += 4
	SimTests.check(not FirstCustomer.protected_time(), "opening: the wider business resumes after the quiet period")
	for observed in [0, 1, 2]:
		fixture()
		FirstCustomer.tick()
		FirstCustomer.choose("stagger")
		for wave in observed:
			Game.cycle = int(FirstCustomer.state()["starts"]) + wave
			FirstCustomer.tick()
		Game.restore(Game.snapshot())
		Game.cycle = int(FirstCustomer.state()["starts"]) + 5
		var late_funds := Game.money
		FirstCustomer.tick()
		var late := FirstCustomer.state()
		SimTests.check(late["phase"] == "debrief" and late["samples"].size() == 3 and int(late["successes"]) == observed,
			"opening: late reload with %d observed waves closes exactly three waves" % observed)
		FirstCustomer.tick()
		SimTests.check(Game.money == late_funds and int(late["bonus"]) == 0 and int(late["after"]["headroom"]) == 0,
			"opening: missed waves cannot earn rewards or invented capacity evidence")
	f = fixture()
	FirstCustomer.tick()
	FirstCustomer.choose("stagger")
	for _n in 4: Game.sla_tick()
	var host: Net.NDevice = f["a"]
	host.ifaces[0].enabled = false
	host.ifaces[0].admin_down = true
	Game.sla_tick()
	host.ifaces[0].enabled = true
	host.ifaces[0].admin_down = false
	Game.sla_tick()
	SimTests.check(int(FirstCustomer.state()["successes"]) == 2 and int(FirstCustomer.state()["bonus"]) == 0,
		"opening: an actual outage during the middle wave is remembered even after recovery")
	f = fixture()
	var sw: Net.NDevice = f["sw"]
	Game.guided_outage = {"state": "communicated", "device": sw.name, "iface": sw.ifaces[0].name,
		"target_ip": "10.42.18.10", "deal": "design_kiskacsa", "evidence": [], "timeline": []}
	sw.ifaces[0].enabled = false
	sw.ifaces[0].admin_down = true
	SimTests.check(Game.guided_outage_probe("l2") == "" and Game.guided_outage_probe("physical") == "" and Game.guided_outage_probe("monitor") == "",
		"investigation: the player can begin with a port hypothesis and gather evidence in any order")
	var count: int = Game.guided_outage["timeline"].size()
	Game.guided_outage_probe("l2")
	SimTests.check(Game.guided_outage["timeline"].size() == count, "investigation: repeated evidence does not fabricate extra observations")
	Game.give_up_guided_outage()
	SimTests.check(sw.ifaces[0].enabled and bool(Game.guided_outage["assisted"]), "investigation: help restores the actual port and records assistance honestly")
	f = fixture()
	var source: Net.Rack = f["rack"]
	var capture_error := ServiceDesign.capture(source, "Small hosting LAN")
	SimTests.check(capture_error == "", "service standard: captures a proven LAN with hardware and cables (%s)" % capture_error)
	if capture_error != "":
		Game.restore(before)
		return
	var design: Dictionary = Game.blueprints.back()
	var target := Game.add_rack(Vector2i(2, 1))
	var plan := ServiceDesign.preview(target, design, "10.80.0", 100)
	SimTests.check(bool(plan["ok"]) and int(plan["price"]) == 902, "service standard: preview includes both hardware and patch leads")
	funds = Game.money
	SimTests.check(not ServiceDesign.preview(target, design, "10.42.18", 100)["ok"] and Game.money == funds,
		"service standard: overlapping prefixes are rejected before spending")
	SimTests.check(ServiceDesign.deploy(target, design, "10.80.0", 100) == "" and Game.money == funds - 902,
		"service standard: deploys the priced topology and verifies every host pair")
	var cloned := Contracts._owner("10.80.0.10")
	SimTests.check(cloned != null and cloned != f["a"] and Sim.ping(cloned, "10.80.0.11")["ok"], "service standard: fresh identities form a working independent LAN")
	if cloned != null: cloned.ifaces[0].ips.append("10.80.0.99/24")
	SimTests.check(f["a"].ifaces[0].ips.size() == 1, "service standard: changing a deployed service cannot mutate its source")
	funds = Game.money
	SimTests.check(ServiceDesign.deploy(target, design, "10.81.0", 101) != "" and Game.money == funds,
		"service standard: an occupied cabinet cannot be overwritten")
	Game.restore(before)
