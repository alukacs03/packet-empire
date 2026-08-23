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

static func start(n_breaks := 3, rng_seed := -1) -> void:
	_snap = Game.snapshot()
	Game.drill_active = true
	Game.racks = []
	Game.links = []
	_build()
	_break(n_breaks, rng_seed)
	Game.topology_changed.emit()

static func _build() -> void:
	## two switched segments joined by a trunk, plus a routed second subnet
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
	var vict_sw: Net.NDevice = _cast["sw1"]
	var acc: Net.Iface = _cast["access_a"]
	pool.append(["%s %s was moved to a wrong VLAN" % [vict_sw.name, acc.name],
		func() -> void:
			Game.add_vlan(vict_sw, 99, "wrong")
			acc.untagged_vlan = 99
			_undo.append(func() -> void: acc.untagged_vlan = 1)])
	var gw_srv: Net.NDevice = _cast["b"]
	pool.append(["%s lost its default route" % gw_srv.name,
		func() -> void:
			var old: Array = gw_srv.static_routes.duplicate(true)
			gw_srv.static_routes = []
			_undo.append(func() -> void: gw_srv.static_routes = old)])
	var trunk_if: Net.Iface = _cast["trunk"]
	pool.append(["the inter-switch trunk was pruned to the wrong VLAN list",
		func() -> void:
			trunk_if.tagged_vlans = [42]
			_undo.append(func() -> void: trunk_if.tagged_vlans = [])])
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
	_cast = {}
	return revealed
