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
			"hint": "On the access point's console: 'ssid staff vlan 10', 'ssid students vlan 20', 'ssid guests vlan 30'. On the switch create VLANs 10, 20 and 30 (the AP's uplink is already a trunk) and move the staff server's port, Ethernet2, into VLAN 10 with 'switchport access vlan 10'. Then on the two machines: 'wifi join staff' and 'wifi join guests'.",
			"build": func() -> void: _build_campus(),
			"goals": [
				{"d": "Three SSIDs on the access point, each on its own VLAN", "t": func() -> bool: return _ap_ssid_count() >= 3},
				{"d": "Staff can reach the staff server at 10.61.10.10", "t": func() -> bool: return _ping("10.61.10.20", "10.61.10.10")},
				{"d": "Guests cannot reach the staff server", "t": func() -> bool: return not _ping("10.61.10.30", "10.61.10.10")},
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
		{
			"id": "v6_mandate",
			"name": "The address you were given",
			"blurb": "A customer has been handed an IPv6-only network and one legacy partner nobody will renumber. Their client must reach your web service natively, find it by name, and still get to the partner over IPv4.",
			"build": func() -> void: _build_v6(),
			"goals": [
				{"d": "The v6-only client reaches the web server over IPv6",
					"t": func() -> bool: return _ping("fd00:6::10", "fd00:6::20")},
				{"d": "The v6-only client reaches the legacy web server through the translator",
					"t": func() -> bool: return _ping("fd00:6::10", "64:ff9b::a06:14")},
				{"d": "web.pkt answers with an IPv6 address the client can reach",
					"t": func() -> bool: return _resolves6("fd00:6::10", "web.pkt")},
				{"d": "legacy.pkt is reachable from the v6-only client",
					"t": func() -> bool: return _resolves6("fd00:6::10", "legacy.pkt")},
			],
		},
		{
			"id": "inherited_fabric",
			"name": "The inherited fabric",
			"blurb": "Two offices, two routers, OSPF between them and a redundant gateway for the near office. The engineer who built it left a network statement short, a router in the wrong area and a backup that thinks it is master. Nothing is cabled wrong. Everything is configured wrong.",
			"build": func() -> void: _build_fabric(),
			"goals": [
				{"d": "Every router agrees on the area", "t": func() -> bool: return _same_area()},
				{"d": "The two routers are OSPF neighbours", "t": func() -> bool: return _ospf_neighbours("10.63.9.1")},
				{"d": "10.63.1.10 reaches 10.63.2.10 with no static routes on the routers", "t": func() -> bool: return _ping("10.63.1.10", "10.63.2.10") and _no_statics_on_routers()},
				{"d": "The preferred router (priority 120) is the VRRP master for 10.63.1.1", "t": func() -> bool: return _vrrp_master_is("10.63.1.1", "10.63.1.2")},
			],
		},
		{
			"id": "bad_friday",
			"name": "The webshop's bad Friday",
			"blurb": "A webshop behind a load balancer, half its pool dead, and a router that stopped translating the shop's private address on the way out. Sale night starts in an hour. Get the pool back to two live members and the shop back on the internet.",
			"build": func() -> void: _build_friday(),
			"hint": "Two things moved on Friday, not one: a member's port was shut, and the translation rule was re-bound. 'show running-config' on the router: the 'ip nat inside source ... interface' line names the leg it translates on; put it back on the uplink leg and take the stale one out.",
			"goals": [
				{"d": "The virtual address 10.64.0.100 answers", "t": func() -> bool: return _ping("10.64.0.20", "10.64.0.100")},
				{"d": "Both pool members are in service", "t": func() -> bool: return _lb_healthy_at("10.64.0.100") >= 2},
				{"d": "The shop at 10.64.0.11 reaches 8.8.8.8 through NAT", "t": func() -> bool: return _ping("10.64.0.11", "8.8.8.8")},
			],
		},
	]

# ---------------- lifecycle ----------------

static func start(sc: Dictionary) -> void:
	if Puzzle.active():
		return
	_snap = Game.snapshot()
	Game.drill_active = true  # the business pauses while you work a scenario
	active = sc
	Game.racks = []
	Game.links = []
	Game.sites = []
	Game.current_site = 0
	Game.parts["patch"] = maxi(int(Game.parts.get("patch", 0)), 100)  # the build cables itself; the snapshot restores the drawer
	Game.parts["optic"] = maxi(int(Game.parts.get("optic", 0)), 20)
	sc["build"].call()
	# add_site put a 0x0 "Home floor" in front of the scenario's own floor; the racks were placed on site 0
	if Game.sites.size() > 1 and Game.sites[0].get("grid", []) == [0, 0]:
		Game.sites.remove_at(0)
	Game.current_site = 0
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

static func _same_area() -> bool:
	var area := ""
	for d in Game.all_devices():
		if d.ospf.is_empty() or not d.ip_forwarding:
			continue
		if area == "":
			area = Sim.ospf_area(d)
		elif Sim.ospf_area(d) != area:
			return false
	return area != ""

static func _resolves6(from_ip: String, name: String) -> bool:
	## The customer's test is not "does DNS answer": it is whether the name
	## gets them to the service, whichever half of the transition answers.
	var src := Sim._ip_owner(from_ip)
	if src == null:
		return false
	var answer := Sim.resolve(src, name, false, true)
	if answer == "" or not Net.is_v6(answer):
		return false
	return bool(Sim.ping(src, answer)["ok"])

static func _ap_ssid_count() -> int:
	## SSIDs on distinct VLANs: three names on one VLAN are one network
	var best := 0
	for d in Game.all_devices():
		if d.type == "ap":
			var vids := {}
			for name in d.ssids:
				if int(d.ssids[name]) != 1:
					vids[int(d.ssids[name])] = true
			best = maxi(best, vids.size())
	return best

static func _fw_denies(prefix: String, plen: int) -> bool:
	for d in Game.all_devices():
		if d.type != "firewall":
			continue
		for rule in Sim.active_acls(d):  # bound lists only: an unapplied list is the auditor's favourite finding
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

static func _ospf_neighbours(via_ip: String) -> bool:
	var rtr := Sim._ip_owner(via_ip)
	if rtr == null:
		return false
	return not Sim.ospf_neighbors(rtr).is_empty()

static func _no_statics_on_routers() -> bool:
	for d in Game.all_devices():
		if d.type == "router" and not d.static_routes.is_empty():
			return false
	return true

static func _vrrp_master_is(vip: String, master_ip: String) -> bool:
	var master := Sim.vrrp_master(vip, 1)
	return master != null and master == Sim._ip_owner(master_ip)

static func _lb_healthy_at(vip: String) -> int:
	for d in Game.all_devices():
		var svc: Dictionary = d.services.get("lb", {})
		if String(svc.get("vip", "")) == vip:
			Game.lb_health_check()
			return svc.get("healthy", []).size()
	return 0

static func _build_fabric() -> void:
	Game.add_site("Inherited fabric", Vector2i(6, 6), "scenario", "Szeged")
	var rack := Game.add_rack(Vector2i(1, 1), 0)
	var rack2 := Game.add_rack(Vector2i(3, 1), 0)
	var r1 := Game.new_device("rtr-edge")
	var r1b := Game.new_device("rtr-edge")
	var r2 := Game.new_device("rtr-edge")
	var sw1 := Game.new_device("sw-8")
	var a := Game.new_device("srv-1")
	var b := Game.new_device("srv-1")
	_place(rack, 0, r1)
	_place(rack, 2, r1b)
	_place(rack, 4, sw1)
	_place(rack, 5, a)
	_place(rack2, 0, r2)
	_place(rack2, 2, b)
	Game.connect_ifaces(a.ifaces[0], sw1.ifaces[0])
	Game.connect_ifaces(r1.ifaces[0], sw1.ifaces[1])
	Game.connect_ifaces(r1b.ifaces[0], sw1.ifaces[2])
	Game.connect_ifaces(r1.ifaces[1], r2.ifaces[1])
	Game.connect_ifaces(r1b.ifaces[1], r2.ifaces[2])
	Game.connect_ifaces(b.ifaces[0], r2.ifaces[0])
	Game.add_ip(a.ifaces[0], "10.63.1.10/24")
	Game.add_ip(r1.ifaces[0], "10.63.1.2/24")
	Game.add_ip(r1b.ifaces[0], "10.63.1.3/24")
	Game.add_ip(r1.ifaces[1], "10.63.9.1/30")
	Game.add_ip(r2.ifaces[1], "10.63.9.2/30")
	Game.add_ip(r1b.ifaces[1], "10.63.9.5/30")
	Game.add_ip(r2.ifaces[2], "10.63.9.6/30")
	Game.add_ip(r2.ifaces[0], "10.63.2.1/24")
	Game.add_ip(b.ifaces[0], "10.63.2.10/24")
	Game.add_static_route(a, "0.0.0.0", 0, "10.63.1.1")
	Game.add_static_route(b, "0.0.0.0", 0, "10.63.2.1")
	# what the previous engineer left: a network statement that misses the
	# transit link, a router in the wrong area, and a backup with a higher
	# priority than the router everybody was told is the master
	r1.ospf = {"networks": ["10.63.1.0/24"]}
	r1b.ospf = {"networks": ["10.63.0.0/16"], "areas": {"backbone": "0.0.0.1"}}
	r2.ospf = {"networks": ["10.63.0.0/16"]}
	r1.ifaces[0].vrrp = {"group": 1, "vip": "10.63.1.1", "priority": 120}
	r1b.ifaces[0].vrrp = {"group": 1, "vip": "10.63.1.1", "priority": 150}
	for d in [r1, r1b, r2, sw1]:
		d.startup = Game.device_config(d)

static func _build_friday() -> void:
	Game.add_site("Webshop cage", Vector2i(6, 6), "scenario", "Budapest")
	var rack := Game.add_rack(Vector2i(1, 1), 0)
	var rack2 := Game.add_rack(Vector2i(3, 1), 0)
	var rtr := Game.new_device("rtr-edge")
	var upl := Game.new_device("isp-uplink")
	var sw := Game.new_device("sw-8")
	var lb := Game.new_device("lb-1")
	var web1 := Game.new_device("srv-1")
	var web2 := Game.new_device("srv-1")
	var client := Game.new_device("srv-1")
	_place(rack, 0, upl)
	_place(rack, 1, rtr)
	_place(rack, 3, sw)
	_place(rack, 4, lb)
	_place(rack2, 0, web1)
	_place(rack2, 1, web2)
	_place(rack2, 2, client)
	Game.connect_ifaces(upl.ifaces[0], rtr.ifaces[0])
	Game.connect_ifaces(rtr.ifaces[1], sw.ifaces[0])
	Game.connect_ifaces(lb.ifaces[0], sw.ifaces[1])
	Game.connect_ifaces(web1.ifaces[0], sw.ifaces[2])
	Game.connect_ifaces(web2.ifaces[0], sw.ifaces[3])
	Game.connect_ifaces(client.ifaces[0], sw.ifaces[4])
	Game.add_ip(rtr.ifaces[0], "100.64.0.2/30")
	Game.add_ip(rtr.ifaces[1], "10.64.0.1/24")
	Game.add_ip(lb.ifaces[0], "10.64.0.5/24")
	Game.add_ip(web1.ifaces[0], "10.64.0.11/24")
	Game.add_ip(web2.ifaces[0], "10.64.0.12/24")
	Game.add_ip(client.ifaces[0], "10.64.0.20/24")
	for h in [web1, web2, client, lb]:
		Game.add_static_route(h, "0.0.0.0", 0, "10.64.0.1")
	Game.add_static_route(rtr, "0.0.0.0", 0, "100.64.0.1")
	lb.services["lb"] = {"vip": "10.64.0.100", "members": ["10.64.0.11", "10.64.0.12"], "healthy": []}
	# Friday: one member's port was shut, and NAT was moved to the inside leg
	web2.ifaces[0].admin_down = true
	web2.ifaces[0].enabled = false
	rtr.ifaces[1].nat = "outside"
	rtr.ifaces[0].nat = "inside"
	rtr.services["nat"] = {"rules": [{"kind": "overload", "list": "1", "iface": rtr.ifaces[1].name}],
		"acls": {"1": [{"action": "permit", "net": "10.64.0.0", "plen": 24}]}}
	Game.lb_health_check()
	for d in [rtr, sw, lb]:
		d.startup = Game.device_config(d)

static func _build_broken_isp() -> void:
	Game.add_site("Inherited exchange", Vector2i(6, 6), "scenario", "Debrecen")
	var rack := Game.add_rack(Vector2i(1, 1), 0)
	var rack2 := Game.add_rack(Vector2i(3, 1), 0)
	var core := Game.new_device("rtr-edge")
	var sw_a := Game.new_device("sw-8")
	var sw_b := Game.new_device("sw-8")
	var cust_a := Game.new_device("srv-1")
	var cust_b := Game.new_device("srv-1")
	_place(rack, 0, core)
	_place(rack, 1, sw_a)
	_place(rack, 2, cust_a)
	_place(rack2, 0, sw_b)
	_place(rack2, 1, cust_b)
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
	_place(rack, 0, sw)
	_place(rack, 1, ap)
	_place(rack, 2, staff_srv)
	_place(rack, 3, staff_pc)
	_place(rack, 4, guest_pc)
	Game.connect_ifaces(ap.ifaces[0], sw.ifaces[0])
	Game.connect_ifaces(staff_srv.ifaces[0], sw.ifaces[1])
	Game.add_ip(staff_srv.ifaces[0], "10.61.10.10/24")
	Game.add_ip(staff_pc.ifaces[0], "10.61.10.20/24")
	Game.add_ip(guest_pc.ifaces[0], "10.61.10.30/24")  # the staff subnet on purpose: only the VLAN keeps guests out
	sw.ifaces[0].mode = "trunk"

static func _build_v6() -> void:
	Game.add_site("Transition floor", Vector2i(6, 6), "scenario", "Szeged")
	var rack := Game.add_rack(Vector2i(1, 1), 0)
	var sw := Game.new_device("sw-8")
	var rtr := Game.new_device("rtr-edge")
	var client := Game.new_device("srv-1")   # IPv6 only, and staying that way
	var web := Game.new_device("srv-1")      # your service, still IPv4 only
	var legacy := Game.new_device("srv-1")   # the partner nobody will renumber
	var dns := Game.new_device("srv-1")      # the resolver, which only knows v4
	_place(rack, 0, sw)
	_place(rack, 1, client)
	_place(rack, 2, web)
	_place(rack, 3, legacy)
	_place(rack, 4, dns)
	_place(rack, 6, rtr)  # two units, so it sits clear of the rest
	Game.connect_ifaces(client.ifaces[0], sw.ifaces[0])
	Game.connect_ifaces(web.ifaces[0], sw.ifaces[1])
	Game.connect_ifaces(legacy.ifaces[0], sw.ifaces[2])
	Game.connect_ifaces(dns.ifaces[0], sw.ifaces[3])
	Game.connect_ifaces(rtr.ifaces[0], sw.ifaces[4])
	Game.add_ip(client.ifaces[0], "fd00:6::10/64")
	Game.add_ip(rtr.ifaces[0], "fd00:6::1/64")
	Game.add_ip(rtr.ifaces[0], "10.6.0.1/24")
	Game.add_ip(web.ifaces[0], "10.6.0.20/24")
	Game.add_ip(legacy.ifaces[0], "10.6.0.30/24")
	Game.add_static_route(client, "::", 0, "fd00:6::1")
	Game.add_static_route(web, "0.0.0.0", 0, "10.6.0.1")
	Game.add_static_route(legacy, "0.0.0.0", 0, "10.6.0.1")
	Game.add_ip(dns.ifaces[0], "10.6.0.5/24")
	Game.add_ip(dns.ifaces[0], "fd00:6::5/64")
	Game.add_static_route(dns, "0.0.0.0", 0, "10.6.0.1")
	Game.add_static_route(dns, "::", 0, "fd00:6::1")
	# a resolver that only knows the IPv4 world, which is the whole problem
	dns.services["dns"] = {"records": {"web.pkt": "10.6.0.20", "legacy.pkt": "10.6.0.30"}}
	client.resolver = "fd00:6::5"

static func _build_audit() -> void:
	Game.add_site("Audited floor", Vector2i(6, 6), "scenario", "Budapest")
	var rack := Game.add_rack(Vector2i(1, 1), 0)
	var sw := Game.new_device("sw-8")
	var fw := Game.new_device("fw-1")
	var client_srv := Game.new_device("srv-1")
	var ops_srv := Game.new_device("srv-1")
	_place(rack, 0, sw)
	_place(rack, 1, fw)
	_place(rack, 2, client_srv)
	_place(rack, 3, ops_srv)
	Game.connect_ifaces(client_srv.ifaces[0], fw.ifaces[0])
	Game.connect_ifaces(fw.ifaces[1], sw.ifaces[0])
	Game.connect_ifaces(ops_srv.ifaces[0], sw.ifaces[1])
	Game.add_ip(client_srv.ifaces[0], "10.62.9.10/24")
	Game.add_ip(fw.ifaces[0], "10.62.9.1/24")
	Game.add_ip(fw.ifaces[1], "10.62.0.1/24")
	fw.acls = [{"action": "permit", "src": "0.0.0.0", "splen": 0, "dst": "0.0.0.0", "dplen": 0}]  # open until the player closes it: that is the leak
	Game.add_ip(ops_srv.ifaces[0], "10.62.0.10/24")
	Game.add_static_route(client_srv, "0.0.0.0", 0, "10.62.9.1")
	Game.add_static_route(ops_srv, "0.0.0.0", 0, "10.62.0.1")
	Game.add_static_route(sw, "0.0.0.0", 0, "10.62.0.1")  # the management port can answer the customer: that is the leak
	for mgmt: Net.Iface in sw.ifaces:
		if mgmt.name.begins_with("Management"):
			Game.connect_ifaces(mgmt, sw.ifaces[6])
			Game.add_ip(mgmt, "10.62.0.2/24")   # management sitting where customers can see it

static func _place(rack: Net.Rack, idx: int, dev: Net.NDevice) -> void:
	## through install_device, so tall gear reserves the unit above it; the
	## next free unit down when that one is already covered
	for k in range(idx, Net.Rack.SLOTS):
		if Game.install_device(rack, k, dev):
			return
	rack.slots[idx] = dev
