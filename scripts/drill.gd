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

static func start(n_breaks := 3, rng_seed := -1) -> void:
	_snap = Game.snapshot()
	Game.drill_active = true
	Game.racks = []
	Game.links = []
	outcome = {}
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	match rng.randi() % 5:
		0:
			_build()
		1:
			_build_tenants()
		2:
			_build_services()
		3:
			_build_two_rooms()
		_:
			_build_core()
	_break(n_breaks, rng_seed)
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
	r1.slots[0] = sw1
	r1.slots[1] = a
	r2.slots[0] = sw2
	r2.slots[1] = b
	r2.slots[2] = beta
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
	r1.slots[0] = sw
	r1.slots[1] = rtr
	r1.slots[2] = svc
	r1.slots[3] = app
	r1.slots[4] = client
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
	scenario = "Two rooms: 10.75.0.10 must answer with either building dark."
	Game.sites = [{"name": "Alpha room", "grid": [4, 4], "kind": "own", "city": "Budapest"}]
	var other := Game.add_site("Beta room", Vector2i(4, 4), "leased", "Debrecen")
	Game.carrier_outage = {}
	Game.buy_circuit(0, other, 1)
	var ra := Game.add_rack(Vector2i(1, 1), 0)
	var rb := Game.add_rack(Vector2i(1, 1), other)
	var sw_a := Game.new_device("sw-8")
	var sw_b := Game.new_device("sw-8")
	var copy_a := Game.new_device("srv-1")
	var copy_b := Game.new_device("srv-1")
	var client := Game.new_device("srv-1")
	ra.slots[0] = sw_a
	ra.slots[1] = copy_a
	ra.slots[2] = client
	rb.slots[0] = sw_b
	rb.slots[1] = copy_b
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
	r1.slots[0] = rt1
	r1.slots[1] = sw1
	r1.slots[2] = a
	r2.slots[0] = rt2
	r2.slots[1] = b
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
	r1.slots[0] = sw1
	r1.slots[1] = a
	r1.slots[2] = rtr
	r2.slots[0] = sw2
	r2.slots[1] = b
	r2.slots[2] = c
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

static func _break(n: int, rng_seed: int) -> void:
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
	var port: Net.Iface = used[rng.randi() % used.size()]
	pool.append(["%s %s was unplugged (disabled)" % [port.dev.name, port.name],
		func() -> void:
			port.enabled = false
			_undo.append(func() -> void: port.enabled = true)])
	if _cast.has("sw1") and _cast.has("access_a"):
		var vict_sw: Net.NDevice = _cast["sw1"]
		var acc: Net.Iface = _cast["access_a"]
		var good_vlan: int = int(_cast.get("access_vlan", 1))
		pool.append(["%s %s was moved to a wrong VLAN" % [vict_sw.name, acc.name],
			func() -> void:
				Game.add_vlan(vict_sw, 99, "wrong")
				acc.untagged_vlan = 99
				_undo.append(func() -> void: acc.untagged_vlan = good_vlan)])
	for role in ["b", "route_dev"]:
		if _cast.has(role):
			var gw_srv: Net.NDevice = _cast[role]
			if not gw_srv.static_routes.is_empty():
				pool.append(["%s lost a route it needs" % gw_srv.name,
					func() -> void:
						var old: Array = gw_srv.static_routes.duplicate(true)
						gw_srv.static_routes = []
						_undo.append(func() -> void: gw_srv.static_routes = old)])
	if _cast.has("svc"):
		var svc_dev: Net.NDevice = _cast["svc"]
		pool.append(["the DHCP scope was bound to an interface that does not exist",
			func() -> void:
				var was: String = String(svc_dev.services["dhcp"]["iface"])
				svc_dev.services["dhcp"]["iface"] = "eth9"
				_undo.append(func() -> void: svc_dev.services["dhcp"]["iface"] = was)])
		pool.append(["the DHCP pool was moved into a subnet the segment cannot use",
			func() -> void:
				var was_start: String = String(svc_dev.services["dhcp"]["start"])
				var was_end: String = String(svc_dev.services["dhcp"]["end"])
				svc_dev.services["dhcp"]["start"] = "192.168.44.50"
				svc_dev.services["dhcp"]["end"] = "192.168.44.99"
				_undo.append(func() -> void:
					svc_dev.services["dhcp"]["start"] = was_start
					svc_dev.services["dhcp"]["end"] = was_end)])
		pool.append(["the app record was removed from the zone",
			func() -> void:
				var was_records: Dictionary = svc_dev.services["dns"]["records"].duplicate()
				svc_dev.services["dns"]["records"] = {}
				_undo.append(func() -> void:
					svc_dev.services["dns"]["records"] = was_records)])
	if _cast.has("wan") and _cast.has("b"):
		var wan_if: Net.Iface = _cast["wan"]
		var far_copy: Net.NDevice = _cast["b"]
		pool.append(["the link between the two buildings was left disabled",
			func() -> void:
				wan_if.enabled = false
				_undo.append(func() -> void: wan_if.enabled = true)])
		pool.append(["the second copy of the service was readdressed and nobody noticed",
			func() -> void:
				var old_far: Array = far_copy.ifaces[0].ips.duplicate()
				far_copy.ifaces[0].ips = ["10.75.9.10/24"]
				_undo.append(func() -> void: far_copy.ifaces[0].ips = old_far)])
	if _cast.has("trunk"):
		var trunk_if: Net.Iface = _cast["trunk"]
		pool.append(["the inter-switch trunk was pruned to the wrong VLAN list",
			func() -> void:
				trunk_if.tagged_vlans = [42]
				_undo.append(func() -> void: trunk_if.tagged_vlans = [])])
	if _cast.has("a"):
		var ip_srv: Net.NDevice = _cast["a"]
		pool.append(["%s was readdressed into the wrong subnet" % ip_srv.name,
			func() -> void:
				var old_ips: Array = ip_srv.ifaces[0].ips.duplicate()
				ip_srv.ifaces[0].ips = ["10.77.1.10/24"]
				_undo.append(func() -> void: ip_srv.ifaces[0].ips = old_ips)])
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
	var revealed := faults.duplicate()
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
