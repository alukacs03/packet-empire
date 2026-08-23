class_name Scenarios
## Authored starting situations. A scenario replaces the world with a
## prepared one, states what it wants, and checks it against the live
## simulation exactly like a contract does. Your own datacenter is
## snapshotted and comes back when you leave.

static var _snap := ""
static var active := {}

static func all() -> Array:
	return [
		{
			"id": "broken_isp",
			"name": "The inherited ISP",
			"blurb": "You have taken over a small provider from someone who left in a hurry. Three customers, one network, and nothing works. Restore service to all of them.",
			"build": func() -> void: _build_broken_isp(),
			"goals": [
				{"d": "10.60.1.10 reaches its gateway", "t": func() -> bool: return _ping("10.60.1.10", "10.60.1.1")},
				{"d": "10.60.2.10 reaches its gateway", "t": func() -> bool: return _ping("10.60.2.10", "10.60.2.1")},
				{"d": "The two customer networks reach each other", "t": func() -> bool: return _ping("10.60.1.10", "10.60.2.10")},
			],
		},
		{
			"id": "campus",
			"name": "Campus in a summer",
			"blurb": "A college wants staff, students and guests on the same wireless and the same switches, and each group kept away from the others. Build it before term starts.",
			"build": func() -> void: _build_campus(),
			"goals": [
				{"d": "Three SSIDs on the access point", "t": func() -> bool: return _ap_ssid_count() >= 3},
				{"d": "Staff can reach the staff server at 10.61.10.10", "t": func() -> bool: return _ping("10.61.10.20", "10.61.10.10")},
				{"d": "Guests cannot reach the staff server", "t": func() -> bool: return not _ping("10.61.30.20", "10.61.10.10")},
			],
		},
		{
			"id": "audit",
			"name": "The auditor is coming",
			"blurb": "A regulated customer sends an auditor next week. Your network must isolate their segment, keep management off it, log centrally, and have nothing running on unsaved configuration.",
			"build": func() -> void: _build_audit(),
			"goals": [
				{"d": "A firewall denies traffic towards 10.62.9.0/24", "t": func() -> bool: return _fw_denies("10.62.9.0", 24)},
				{"d": "Their server cannot reach any management address", "t": func() -> bool: return not _ping("10.62.9.10", "10.62.0.2")},
				{"d": "A syslog collector is running and devices point at it", "t": func() -> bool: return _logging_configured()},
				{"d": "Every device configuration is saved", "t": func() -> bool: return _all_saved()},
			],
		},
	]

# ---------------- lifecycle ----------------

static func start(sc: Dictionary) -> void:
	_snap = Game.snapshot()
	Game.drill_active = true  # the business pauses while you work a scenario
	active = sc
	Game.racks = []
	Game.links = []
	Game.sites = []
	Game.current_site = 0
	sc["build"].call()
	Game.topology_changed.emit()

static func solved() -> bool:
	if active.is_empty():
		return false
	for g in active["goals"]:
		if not bool(g["t"].call()):
			return false
	return true

static func finish(success: bool) -> void:
	if _snap == "":
		return
	var name: String = active.get("name", "scenario")
	Game.drill_active = false
	Game.restore(_snap)
	if success:
		Game.log_event("SCENARIO passed: %s." % name)
		Game.reputation = mini(100, Game.reputation + 4)
	_snap = ""
	active = {}

# ---------------- checks ----------------

static func _ping(from_ip: String, to_ip: String) -> bool:
	var src := Sim._ip_owner(from_ip)
	return src != null and Sim.ping(src, to_ip)["ok"]

static func _ap_ssid_count() -> int:
	var best := 0
	for d in Game.all_devices():
		if d.type == "ap":
			best = maxi(best, d.ssids.size())
	return best

static func _fw_denies(prefix: String, plen: int) -> bool:
	for d in Game.all_devices():
		if d.type != "firewall":
			continue
		for rule in d.acls:
			if rule["action"] == "deny" and int(rule["dplen"]) >= plen \
					and Net.same_net(String(rule["dst"]), prefix, plen):
				return true
	return false

static func _logging_configured() -> bool:
	var collector := false
	for d in Game.all_devices():
		if d.services.has("syslog"):
			collector = true
	if not collector:
		return false
	for d in Game.all_devices():
		if d.type in ["switch", "router", "firewall"] and d.log_host != "":
			return true
	return false

static func _all_saved() -> bool:
	var any := false
	for d in Game.all_devices():
		if d.type in ["server", "uplink", "cooling"]:
			continue
		any = true
		if Game.config_dirty(d):
			return false
	return any

# ---------------- worlds ----------------

static func _build_broken_isp() -> void:
	Game.add_site("Inherited exchange", Vector2i(6, 6), "scenario", "Debrecen")
	var rack := Game.add_rack(Vector2i(1, 1), 0)
	var rack2 := Game.add_rack(Vector2i(3, 1), 0)
	var core := Game.new_device("rtr-edge")
	var sw_a := Game.new_device("sw-8")
	var sw_b := Game.new_device("sw-8")
	var cust_a := Game.new_device("srv-1")
	var cust_b := Game.new_device("srv-1")
	rack.slots[0] = core
	rack.slots[1] = sw_a
	rack.slots[2] = cust_a
	rack2.slots[0] = sw_b
	rack2.slots[1] = cust_b
	Game.connect_ifaces(cust_a.ifaces[0], sw_a.ifaces[0])
	Game.connect_ifaces(cust_b.ifaces[0], sw_b.ifaces[0])
	Game.connect_ifaces(core.ifaces[0], sw_a.ifaces[1])
	Game.connect_ifaces(core.ifaces[1], sw_b.ifaces[1])
	Game.add_ip(cust_a.ifaces[0], "10.60.1.10/24")
	Game.add_ip(cust_b.ifaces[0], "10.60.2.10/24")
	Game.add_ip(core.ifaces[0], "10.60.1.1/24")
	# and now the mess the previous engineer left behind
	Game.add_ip(core.ifaces[1], "10.60.3.1/24")     # wrong subnet on the second leg
	sw_b.ifaces[0].untagged_vlan = 1
	sw_b.ifaces[1].enabled = false                   # an uplink someone shut
	Game.add_static_route(cust_a, "0.0.0.0", 0, "10.60.1.1")
	# customer B has no default route at all
	for d in [core, sw_a, sw_b]:
		d.startup = Game.device_config(d)

static func _build_campus() -> void:
	Game.add_site("College", Vector2i(6, 6), "scenario", "Szeged")
	var rack := Game.add_rack(Vector2i(1, 1), 0)
	var sw := Game.new_device("sw-24")
	var ap := Game.new_device("ap-1")
	var staff_srv := Game.new_device("srv-1")
	var staff_pc := Game.new_device("srv-1")
	var guest_pc := Game.new_device("srv-1")
	rack.slots[0] = sw
	rack.slots[1] = ap
	rack.slots[2] = staff_srv
	rack.slots[3] = staff_pc
	rack.slots[4] = guest_pc
	Game.connect_ifaces(ap.ifaces[0], sw.ifaces[0])
	Game.connect_ifaces(staff_srv.ifaces[0], sw.ifaces[1])
	Game.add_ip(staff_srv.ifaces[0], "10.61.10.10/24")
	Game.add_ip(staff_pc.ifaces[0], "10.61.10.20/24")
	Game.add_ip(guest_pc.ifaces[0], "10.61.30.20/24")
	sw.ifaces[0].mode = "trunk"

static func _build_audit() -> void:
	Game.add_site("Audited floor", Vector2i(6, 6), "scenario", "Budapest")
	var rack := Game.add_rack(Vector2i(1, 1), 0)
	var sw := Game.new_device("sw-8")
	var fw := Game.new_device("fw-1")
	var client_srv := Game.new_device("srv-1")
	var ops_srv := Game.new_device("srv-1")
	rack.slots[0] = sw
	rack.slots[1] = fw
	rack.slots[2] = client_srv
	rack.slots[3] = ops_srv
	Game.connect_ifaces(client_srv.ifaces[0], fw.ifaces[0])
	Game.connect_ifaces(fw.ifaces[1], sw.ifaces[0])
	Game.connect_ifaces(ops_srv.ifaces[0], sw.ifaces[1])
	Game.add_ip(client_srv.ifaces[0], "10.62.9.10/24")
	Game.add_ip(fw.ifaces[0], "10.62.9.1/24")
	Game.add_ip(fw.ifaces[1], "10.62.0.1/24")
	Game.add_ip(ops_srv.ifaces[0], "10.62.0.10/24")
	Game.add_static_route(client_srv, "0.0.0.0", 0, "10.62.9.1")
	for mgmt: Net.Iface in sw.ifaces:
		if mgmt.name.begins_with("Management"):
			Game.connect_ifaces(mgmt, sw.ifaces[6])
			Game.add_ip(mgmt, "10.62.0.2/24")   # management sitting where customers can see it
