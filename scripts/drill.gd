class_name Drill
## Incident drills: snapshot the player's datacenter, swap in a generated
## known-good network with N hidden faults, let them fix it with real tools,
## then restore the world. The economy pauses while a drill runs.

const REWARD := 400

static var _snap := ""
static var _undo: Array = []  # Callables that revert each fault
static var faults: Array = []  # descriptions, revealed on abandon
static var _cast := {}  # role -> device/iface built by _build
static var targets: Array = []  # [[ip_a, ip_b], ...] pairs that must ping
## Some incidents are not a ping between two static addresses. When this is
## set, solved() judges the outcome the customer actually cares about.
static var outcome := {}  # {client, name, ip} for the services drill

static var scenario := ""

static func start(n_breaks := 3, rng_seed := -1, difficulty := 2) -> void:
	_snap = Game.snapshot()
	Game.drill_active = true
	Game.racks = []
	Game.links = []
	Game.current_site = 0  # a two-room drill rewrites the site list; the floor the player stood on may not exist in it
	Game.parts["patch"] = maxi(int(Game.parts.get("patch", 0)), 100)  # the build cables itself; the snapshot restores the drawer
	Game.parts["optic"] = maxi(int(Game.parts.get("optic", 0)), 20)
	outcome = {}
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	match rng.randi() % 6:
		0:
			_build()
		1:
			_build_tenants()
		2:
			_build_services()
		3:
			_build_two_rooms()
		4:
			_build_dynamic()
		_:
			_build_core()
	_break(n_breaks, rng_seed, difficulty)
	Game.topology_changed.emit()

static func _build_tenants() -> void:
	## two tenants in VLANs 10/20 stretched over a trunk between two switches
	scenario = "Two tenants, two switches: VLAN 10 must span the trunk."
	var r1 := Game.add_rack(Vector2i(0, 0))
	var r2 := Game.add_rack(Vector2i(1, 0))
	var sw1 := Game.new_device("sw-8")
	var sw2 := Game.new_device("sw-8")
	var a := Game.new_device("srv-1")
	var b := Game.new_device("srv-1")
	var beta := Game.new_device("srv-1")
	_place(r1, 0, sw1)
	_place(r1, 1, a)
	_place(r2, 0, sw2)
	_place(r2, 1, b)
	_place(r2, 2, beta)
	Game.connect_ifaces(a.ifaces[0], sw1.ifaces[0])
	Game.connect_ifaces(b.ifaces[0], sw2.ifaces[0])
	Game.connect_ifaces(beta.ifaces[0], sw2.ifaces[1])
	Game.connect_ifaces(sw1.ifaces[3], sw2.ifaces[3])
	for sw in [sw1, sw2]:
		Game.add_vlan(sw, 10, "alfa")
		Game.add_vlan(sw, 20, "beta")
		sw.ifaces[3].mode = "trunk"
	sw1.ifaces[0].untagged_vlan = 10
	sw2.ifaces[0].untagged_vlan = 10
	sw2.ifaces[1].untagged_vlan = 20
	Game.add_ip(a.ifaces[0], "10.71.0.10/24")
	Game.add_ip(b.ifaces[0], "10.71.0.20/24")
	Game.add_ip(beta.ifaces[0], "10.71.0.30/24")
	targets = [["10.71.0.10", "10.71.0.20"]]
	_cast = {"sw1": sw1, "sw2": sw2, "a": a, "b": b,
		"trunk": sw1.ifaces[3], "access_a": sw1.ifaces[0], "access_vlan": 10}

static func _build_services() -> void:
	## nothing is unplugged and every route is right: the client still gets no
	## address and the name goes nowhere
	scenario = "Services: the client must get a lease and reach app.pkt by name."
	var r1 := Game.add_rack(Vector2i(0, 0))
	var sw := Game.new_device("sw-8")
	var rtr := Game.new_device("rtr-lite")
	var svc := Game.new_device("srv-1")
	var app := Game.new_device("srv-1")
	var client := Game.new_device("srv-1")
	_place(r1, 0, sw)
	_place(r1, 1, rtr)
	_place(r1, 2, svc)
	_place(r1, 3, app)
	_place(r1, 4, client)
	Game.connect_ifaces(rtr.ifaces[0], sw.ifaces[0])
	Game.connect_ifaces(svc.ifaces[0], sw.ifaces[1])
	Game.connect_ifaces(app.ifaces[0], sw.ifaces[2])
	Game.connect_ifaces(client.ifaces[0], sw.ifaces[3])
	Game.add_ip(rtr.ifaces[0], "10.73.0.1/24")
	Game.add_ip(svc.ifaces[0], "10.73.0.5/24")
	Game.add_ip(app.ifaces[0], "10.73.0.20/24")
	Game.add_static_route(svc, "0.0.0.0", 0, "10.73.0.1")
	Game.add_static_route(app, "0.0.0.0", 0, "10.73.0.1")
	svc.services["dhcp"] = {"iface": svc.ifaces[0].name, "start": "10.73.0.50",
		"end": "10.73.0.99", "plen": 24, "gw": "10.73.0.1", "dns": "10.73.0.5",
		"leases": {}}
	svc.services["dns"] = {"records": {"app.pkt": "10.73.0.20"}}
	targets = []
	outcome = {"client": client, "name": "app.pkt", "ip": "10.73.0.20"}
	_cast = {"sw1": sw, "rtr": rtr, "svc": svc, "a": app, "client": client,
		"access_a": sw.ifaces[3], "access_vlan": 1}

static func _build_two_rooms() -> void:
	## two floors, one address, and a customer who only cares whether it is
	## still answering when a building goes dark
	scenario = "Two rooms: 10.75.0.10 must stay reachable from the client in Alpha room with Beta room dark, and with Alpha room's own copy switched off. The room the client stands in cannot judge itself."
	Game.sites = [{"name": "Alpha room", "grid": [4, 4], "kind": "own", "city": "Budapest"}]
	var other := Game.add_site("Beta room", Vector2i(4, 4), "leased", "Debrecen")
	Game.carrier_outage = {}
	Game.circuits.append({"a": 0, "b": other, "mbps": 1000, "fee": 0, "label": "drill circuit", "carrier": Game.CARRIERS[0]})  # the drill's own, not bought with the player's money
	var ra := Game.add_rack(Vector2i(1, 1), 0)
	var rb := Game.add_rack(Vector2i(1, 1), other)
	var sw_a := Game.new_device("sw-8")
	var sw_b := Game.new_device("sw-8")
	var copy_a := Game.new_device("srv-1")
	var copy_b := Game.new_device("srv-1")
	var client := Game.new_device("srv-1")
	_place(ra, 0, sw_a)
	_place(ra, 1, copy_a)
	_place(ra, 2, client)
	_place(rb, 0, sw_b)
	_place(rb, 1, copy_b)
	Game.buy_parts("optic", 6)
	Game.connect_ifaces(copy_a.ifaces[0], sw_a.ifaces[0])
	Game.connect_ifaces(client.ifaces[0], sw_a.ifaces[1])
	Game.connect_ifaces(copy_b.ifaces[0], sw_b.ifaces[0])
	Game.connect_ifaces(sw_a.ifaces[7], sw_b.ifaces[7])  # over the circuit
	Game.add_ip(copy_a.ifaces[0], "10.75.0.10/24")
	Game.add_ip(copy_b.ifaces[0], "10.75.0.10/24")  # the same service, twice
	Game.add_ip(client.ifaces[0], "10.75.0.20/24")
	targets = []
	outcome = {"survive_ip": "10.75.0.10", "from_ip": "10.75.0.20"}
	_cast = {"sw1": sw_a, "sw2": sw_b, "a": copy_a, "b": copy_b, "client": client,
		"access_a": sw_a.ifaces[0], "access_vlan": 1, "wan": sw_a.ifaces[7]}

static func _build_core() -> void:
	## three subnets behind two routers joined by a transit link
	scenario = "Routed core: three subnets, two routers, static routes."
	var r1 := Game.add_rack(Vector2i(0, 0))
	var r2 := Game.add_rack(Vector2i(1, 0))
	var rt1 := Game.new_device("rtr-lite")
	var rt2 := Game.new_device("rtr-lite")
	var sw1 := Game.new_device("sw-8")
	var a := Game.new_device("srv-1")
	var b := Game.new_device("srv-1")
	_place(r1, 0, rt1)
	_place(r1, 1, sw1)
	_place(r1, 2, a)
	_place(r2, 0, rt2)
	_place(r2, 1, b)
	Game.connect_ifaces(a.ifaces[0], sw1.ifaces[0])
	Game.connect_ifaces(rt1.ifaces[0], sw1.ifaces[1])
	Game.connect_ifaces(rt1.ifaces[1], rt2.ifaces[1])
	Game.connect_ifaces(b.ifaces[0], rt2.ifaces[0])
	Game.add_ip(a.ifaces[0], "10.72.1.10/24")
	Game.add_ip(rt1.ifaces[0], "10.72.1.1/24")
	Game.add_ip(rt1.ifaces[1], "10.72.9.1/30")
	Game.add_ip(rt2.ifaces[1], "10.72.9.2/30")
	Game.add_ip(rt2.ifaces[0], "10.72.2.1/24")
	Game.add_ip(b.ifaces[0], "10.72.2.10/24")
	Game.add_static_route(a, "0.0.0.0", 0, "10.72.1.1")
	Game.add_static_route(b, "0.0.0.0", 0, "10.72.2.1")
	Game.add_static_route(rt1, "10.72.2.0", 24, "10.72.9.2")
	Game.add_static_route(rt2, "10.72.1.0", 24, "10.72.9.1")
	targets = [["10.72.1.10", "10.72.2.10"]]
	_cast = {"sw1": sw1, "a": a, "b": b, "rtr": rt1, "rtr2": rt2,
		"access_a": sw1.ifaces[0], "route_dev": rt1}

static func _build_dynamic() -> void:
	## the same three subnets, but OSPF carries the routes and a firewall
	## guards the far office: what breaks here is configuration, not cable
	scenario = "Dynamic core: two routers running OSPF, a firewall in front of the second office."
	var r1 := Game.add_rack(Vector2i(0, 0))
	var r2 := Game.add_rack(Vector2i(1, 0))
	var rt1 := Game.new_device("rtr-edge")
	var rt2 := Game.new_device("rtr-edge")
	var fw := Game.new_device("fw-1")
	var a := Game.new_device("srv-1")
	var b := Game.new_device("srv-1")
	_place(r1, 0, rt1)
	_place(r1, 2, a)
	_place(r2, 0, rt2)
	_place(r2, 2, fw)
	_place(r2, 3, b)
	Game.connect_ifaces(a.ifaces[0], rt1.ifaces[0])
	Game.connect_ifaces(rt1.ifaces[1], rt2.ifaces[1])
	Game.connect_ifaces(rt2.ifaces[0], fw.ifaces[0])
	Game.connect_ifaces(fw.ifaces[1], b.ifaces[0])
	Game.add_ip(a.ifaces[0], "10.73.1.10/24")
	Game.add_ip(rt1.ifaces[0], "10.73.1.1/24")
	Game.add_ip(rt1.ifaces[1], "10.73.9.1/30")
	Game.add_ip(rt2.ifaces[1], "10.73.9.2/30")
	Game.add_ip(rt2.ifaces[0], "10.73.8.1/30")
	Game.add_ip(fw.ifaces[0], "10.73.8.2/30")
	Game.add_ip(fw.ifaces[1], "10.73.2.1/24")
	Game.add_ip(b.ifaces[0], "10.73.2.10/24")
	Game.add_static_route(a, "0.0.0.0", 0, "10.73.1.1")
	Game.add_static_route(b, "0.0.0.0", 0, "10.73.2.1")
	Game.add_static_route(fw, "0.0.0.0", 0, "10.73.8.1")
	rt1.ospf = {"networks": ["10.73.0.0/16"]}
	rt2.ospf = {"networks": ["10.73.0.0/16"]}
	# the office behind the firewall is a static on both routers: OSPF only
	# carries what the routers own, which is the transit and the near office
	Game.add_static_route(rt2, "10.73.2.0", 24, "10.73.8.2")
	Game.add_static_route(rt1, "10.73.2.0", 24, "10.73.9.2")
	fw.acls = [{"action": "permit", "src": "0.0.0.0", "splen": 0, "dst": "0.0.0.0", "dplen": 0}]
	targets = [["10.73.1.10", "10.73.2.10"]]
	_cast = {"a": a, "b": b, "rtr": rt1, "rtr2": rt2, "ospf_rtr": rt2, "fw": fw,
		"route_dev": rt2, "access_a": rt1.ifaces[0]}

static func _build() -> void:
	## two switched segments joined by a trunk, plus a routed second subnet
	scenario = "Flat LAN plus a routed subnet behind the gateway."
	var r1 := Game.add_rack(Vector2i(0, 0))
	var r2 := Game.add_rack(Vector2i(1, 0))
	var sw1 := Game.new_device("sw-8")
	var sw2 := Game.new_device("sw-8")
	var rtr := Game.new_device("rtr-lite")
	var a := Game.new_device("srv-1")
	var b := Game.new_device("srv-1")
	var c := Game.new_device("srv-1")
	_place(r1, 0, sw1)
	_place(r1, 1, a)
	_place(r1, 2, rtr)
	_place(r2, 0, sw2)
	_place(r2, 1, b)
	_place(r2, 2, c)
	Game.connect_ifaces(a.ifaces[0], sw1.ifaces[0])
	Game.connect_ifaces(b.ifaces[0], sw2.ifaces[0])
	Game.connect_ifaces(sw1.ifaces[3], sw2.ifaces[3])
	Game.connect_ifaces(rtr.ifaces[0], sw1.ifaces[1])
	Game.connect_ifaces(c.ifaces[0], rtr.ifaces[1])
	sw1.ifaces[3].mode = "trunk"
	sw2.ifaces[3].mode = "trunk"
	Game.add_ip(a.ifaces[0], "10.70.1.10/24")
	Game.add_ip(b.ifaces[0], "10.70.1.20/24")
	Game.add_ip(rtr.ifaces[0], "10.70.1.1/24")
	Game.add_ip(rtr.ifaces[1], "10.70.2.1/24")
	Game.add_ip(c.ifaces[0], "10.70.2.10/24")
	Game.add_static_route(a, "0.0.0.0", 0, "10.70.1.1")
	Game.add_static_route(b, "0.0.0.0", 0, "10.70.1.1")
	Game.add_static_route(c, "0.0.0.0", 0, "10.70.2.1")
	targets = [["10.70.1.10", "10.70.1.20"], ["10.70.1.10", "10.70.2.10"], ["10.70.1.20", "10.70.2.10"]]
	_cast = {"sw1": sw1, "sw2": sw2, "rtr": rtr, "a": a, "b": b, "c": c,
		"trunk": sw1.ifaces[3], "access_a": sw1.ifaces[0]}

static func _fault_tier(desc: String) -> int:
	for key in ["was unplugged (disabled)", "was moved to a wrong VLAN", "was left disabled on"]:
		if key in desc:
			return 0
	for key in ["lost a route it needs", "the DHCP scope was bound", "the DHCP pool was moved", "the app record was removed", "was readdressed into the wrong subnet", "was readdressed and nobody noticed"]:
		if key in desc:
			return 1
	return 2

static func _break(n: int, rng_seed: int, difficulty := 2) -> void:
	_undo = []
	faults = []
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	# fault pool: [description, apply(), implicit undo captured]
	var pool: Array = []
	var used: Array = []
	for l in Game.links:
		for ifc in [l.a, l.b]:
			used.append(ifc)
	if not used.is_empty():
		var port: Net.Iface = used[rng.randi() % used.size()]
		pool.append(["L1: %s %s was unplugged (disabled)" % [port.dev.name, port.name],
			func() -> void:
				port.enabled = false
				_undo.append(func() -> void: port.enabled = true)])
	if _cast.has("sw1") and _cast.has("access_a"):
		var vict_sw: Net.NDevice = _cast["sw1"]
		var acc: Net.Iface = _cast["access_a"]
		var good_vlan: int = int(_cast.get("access_vlan", 1))
		pool.append(["L2: %s %s was moved to a wrong VLAN" % [vict_sw.name, acc.name],
			func() -> void:
				Game.add_vlan(vict_sw, 99, "wrong")
				acc.untagged_vlan = 99
				_undo.append(func() -> void: acc.untagged_vlan = good_vlan)])
	for role in ["b", "route_dev"]:
		if _cast.has(role):
			var gw_srv: Net.NDevice = _cast[role]
			if not gw_srv.static_routes.is_empty():
				pool.append(["L3: %s lost a route it needs" % gw_srv.name,
					func() -> void:
						var old: Array = gw_srv.static_routes.duplicate(true)
						gw_srv.static_routes = []
						_undo.append(func() -> void: gw_srv.static_routes = old)])
	if _cast.has("svc"):
		var svc_dev: Net.NDevice = _cast["svc"]
		pool.append(["SERVICE: %s's DHCP scope was bound to an interface that does not exist" % svc_dev.name,
			func() -> void:
				var was: String = String(svc_dev.services["dhcp"]["iface"])
				svc_dev.services["dhcp"]["iface"] = "eth9"
				_undo.append(func() -> void: svc_dev.services["dhcp"]["iface"] = was)])
		pool.append(["SERVICE: %s's DHCP pool was moved into a subnet the segment cannot use" % svc_dev.name,
			func() -> void:
				var was_start: String = String(svc_dev.services["dhcp"]["start"])
				var was_end: String = String(svc_dev.services["dhcp"]["end"])
				svc_dev.services["dhcp"]["start"] = "192.168.44.50"
				svc_dev.services["dhcp"]["end"] = "192.168.44.99"
				_undo.append(func() -> void:
					svc_dev.services["dhcp"]["start"] = was_start
					svc_dev.services["dhcp"]["end"] = was_end)])
		pool.append(["SERVICE: the app record was removed from %s's zone" % svc_dev.name,
			func() -> void:
				var was_records: Dictionary = svc_dev.services["dns"]["records"].duplicate()
				svc_dev.services["dns"]["records"] = {}
				_undo.append(func() -> void:
					svc_dev.services["dns"]["records"] = was_records)])
	if _cast.has("wan") and _cast.has("b"):
		var wan_if: Net.Iface = _cast["wan"]
		var far_copy: Net.NDevice = _cast["b"]
		pool.append(["L1: the link between the two buildings was left disabled on %s" % wan_if.dev.name,
			func() -> void:
				wan_if.enabled = false
				_undo.append(func() -> void: wan_if.enabled = true)])
		pool.append(["L3: the second copy of the service (%s) was readdressed and nobody noticed" % far_copy.name,
			func() -> void:
				var old_far: Array = far_copy.ifaces[0].ips.duplicate()
				far_copy.ifaces[0].ips = ["10.75.9.10/24"]
				_undo.append(func() -> void: far_copy.ifaces[0].ips = old_far)])
	if _cast.has("trunk"):
		var trunk_if: Net.Iface = _cast["trunk"]
		pool.append(["L2: the inter-switch trunk on %s was pruned to the wrong VLAN list" % trunk_if.dev.name,
			func() -> void:
				trunk_if.tagged_vlans = [42]
				_undo.append(func() -> void: trunk_if.tagged_vlans = [])])
		if not _cast.has("access_a") or _cast["access_a"].untagged_vlan == trunk_if.untagged_vlan:
			# only where the target VLAN rides the trunk untagged does a native mismatch change anything
			pool.append(["L2: one end of the trunk (%s) was given a different native VLAN" % trunk_if.dev.name,
				func() -> void:
					var was_native: int = trunk_if.untagged_vlan
					trunk_if.untagged_vlan = 99
					_undo.append(func() -> void: trunk_if.untagged_vlan = was_native)])
	if _cast.has("ospf_rtr"):
		var ospf_dev: Net.NDevice = _cast["ospf_rtr"]
		pool.append(["L3: %s's OSPF network statement no longer covers the transit link" % ospf_dev.name,
			func() -> void:
				var was_nets: Array = ospf_dev.ospf["networks"].duplicate()
				ospf_dev.ospf["networks"] = ["10.73.2.0/24"]
				_undo.append(func() -> void: ospf_dev.ospf["networks"] = was_nets)])
	if _cast.has("fw"):
		var fw_dev: Net.NDevice = _cast["fw"]
		pool.append(["POLICY: a deny was inserted above the permit on %s" % fw_dev.name,
			func() -> void:
				var was_acls: Array = fw_dev.acls.duplicate(true)
				fw_dev.acls.insert(0, {"action": "deny", "src": "10.73.1.0", "splen": 24, "dst": "0.0.0.0", "dplen": 0})
				_undo.append(func() -> void: fw_dev.acls = was_acls)])
	if _cast.has("a"):
		var ip_srv: Net.NDevice = _cast["a"]
		pool.append(["L3: %s was readdressed into the wrong subnet" % ip_srv.name,
			func() -> void:
				var old_ips: Array = ip_srv.ifaces[0].ips.duplicate()
				ip_srv.ifaces[0].ips = ["10.77.1.10/24"]
				_undo.append(func() -> void: ip_srv.ifaces[0].ips = old_ips)])
	# the difficulty digit of a challenge code picks the pool: 0 is cables
	# and VLANs, 1 adds routes, DHCP, DNS and addressing, 2 adds the WAN,
	# trunks, OSPF and the firewall
	var tiered: Array = pool.filter(func(f): return _fault_tier(String(f[0])) <= difficulty)
	var widen := difficulty
	while tiered.size() < n and widen < 2:
		widen += 1  # one tier at a time, not straight to the whole pool
		tiered = pool.filter(func(f): return _fault_tier(String(f[0])) <= widen)
	if tiered.size() >= n:
		pool = tiered
	# apply n distinct faults
	var order := range(pool.size())
	for i in order.size():
		var j := rng.randi() % order.size()
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	for k in mini(n, pool.size()):
		var f: Array = pool[order[k]]
		faults.append(f[0])
		f[1].call()

static func solved() -> bool:
	if outcome.has("survive_ip"):
		# judged the way the customer judges it: with either room dark
		var asker := Sim._ip_owner(String(outcome["from_ip"]))
		if asker == null or not Sim.ping(asker, String(outcome["survive_ip"]))["ok"]:
			return false
		for room in Game.site_count():
			var kit := Game.devices_on(room)
			if kit.is_empty() or asker in kit:
				continue  # a room the customer is standing in cannot judge itself
			var was: Array = []
			for d: Net.NDevice in kit:
				was.append(d.status)
				d.status = "offline"
			Sim.flush_learned_state()
			var still: bool = Sim.ping(asker, String(outcome["survive_ip"]))["ok"]
			for k in kit.size():
				kit[k].status = String(was[k])
			Sim.flush_learned_state()
			if not still:
				return false
		return true
	if not outcome.is_empty():
		var client: Net.NDevice = outcome["client"]
		# the lease is the fix working, not a side effect of it: ask for one
		client.ifaces[0].ips = []
		client.static_routes = []
		client.dns_cache = {}
		if Sim.dhcp_request(client, client.ifaces[0]).is_empty():
			return false
		var found := Sim.resolve(client, String(outcome["name"]), false)
		if found != String(outcome["ip"]):
			return false
		return bool(Sim.ping(client, found)["ok"])
	for pair in targets:
		var a := Sim._ip_owner(pair[0])
		if a == null or not Sim.ping(a, pair[1])["ok"]:
			return false
		var b := Sim._ip_owner(pair[1])
		if b == null or not Sim.ping(b, pair[0])["ok"]:
			return false
	return true

static func cheat_fix() -> void:
	## test hook: revert every fault
	for u in _undo:
		u.call()
	Game.topology_changed.emit()

static func finish(success: bool) -> Array:
	## restore the real world; returns the fault list for the debrief
	if _snap == "":
		return []  # no drill running: nothing to restore
	var revealed: Array = []
	for k in faults.size():  # a numbered ladder, layer first, so the debrief reads as troubleshooting
		revealed.append("%d. %s" % [k + 1, faults[k]])
	Game.drill_active = false
	Game.restore(_snap)
	if success:
		Game.money += REWARD
		Game.stats["earned"] += REWARD
		Game.log_event("DRILL passed: incident response bonus +$%d." % REWARD)
		Game.money_changed.emit()
	_snap = ""
	_undo = []
	faults = []
	targets = []
	outcome = {}
	_cast = {}
	return revealed

static func _place(rack: Net.Rack, idx: int, dev: Net.NDevice) -> void:
	## through install_device, so tall gear reserves the unit above it; the
	## next free unit down when that one is already covered
	for k in range(idx, Net.Rack.SLOTS):
		if Game.install_device(rack, k, dev):
			return
	rack.slots[idx] = dev
