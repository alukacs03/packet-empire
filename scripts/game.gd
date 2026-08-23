extends Node
## Autoload "Game": the datacenter source of truth (racks, devices,
## interfaces, cables, per-switch VLANs, money). NetBox-style model.

signal topology_changed
signal money_changed

# Hardware catalog: fictional vendors, real tiers. New model = new entry.
const MODELS := {
	"sw-lite": {"tier": 0, "type": "switch", "label": "PacketTik SW5", "ports": 5, "price": 90, "os": "ros", "if_prefix": "ether"},
	"sw-8": {"tier": 1, "type": "switch", "label": "OpenRack S8", "ports": 8, "price": 250},
	"sw-24": {"tier": 2, "type": "switch", "label": "Arivista 7024", "ports": 24, "price": 900},
	"srv-1": {"tier": 0, "type": "server", "ports": 1, "label": "Dill R110", "price": 400},
	"srv-2": {"tier": 1, "type": "server", "ports": 2, "label": "Dill R220 (dual NIC)", "price": 700},
	"rtr-lite": {"tier": 0, "type": "router", "ports": 4, "label": "PacketTik R4", "price": 350, "os": "ros", "if_prefix": "ether"},
	"rtr-edge": {"tier": 2, "type": "router", "ports": 8, "label": "Junivista MX8", "price": 1200},
	"fw-1": {"tier": 1, "type": "firewall", "ports": 4, "label": "PacketSense FW4", "price": 800},
	"isp-uplink": {"tier": 1, "type": "uplink", "ports": 1, "label": "ISP Handoff (AS64500)", "price": 200},
	"crac-1": {"tier": 1, "type": "cooling", "ports": 0, "label": "CoolRow CRAC", "price": 600, "cools": 1500},
}
const WATTS := {"sw-lite": 10, "sw-8": 30, "sw-24": 80, "srv-1": 150, "srv-2": 250,
	"rtr-lite": 20, "rtr-edge": 90, "fw-1": 40, "isp-uplink": 5, "crac-1": 100}
const TRANSIT_FEE := 30  # per cycle per established upstream BGP session
const BASE_COOLING := 400  # watts the bare room can dissipate
const STAGES := [
	{"name": "Colo corner", "grid": Vector2i(3, 3), "price": 0,
		"blurb": "A few tiles in someone else's colo. Power included."},
	{"name": "Server room", "grid": Vector2i(7, 7), "price": 5000,
		"blurb": "Your own room: more floor, but the power bill is yours now."},
	{"name": "Datacenter floor", "grid": Vector2i(12, 12), "price": 25000,
		"blurb": "A real floor. Grow the empire."},
]
const TYPE_DEFAULTS := {"switch": "sw-8", "server": "srv-1", "router": "rtr-lite", "firewall": "fw-1",
	"uplink": "isp-uplink", "cooling": "crac-1"}
const TYPE_SPECS := {
	"switch": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "sw"},
	"server": {"if_prefix": "eth", "if_start": 0, "name_prefix": "srv"},
	"router": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "rtr"},
	"firewall": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "fw"},
	"uplink": {"if_prefix": "port", "if_start": 1, "name_prefix": "isp"},
	"cooling": {"if_prefix": "port", "if_start": 1, "name_prefix": "crac"},
}
const RACK_PRICE := 500
var save_path := "user://save.json"

var racks: Array = []
var links: Array = []
var money := 2000
var stage := 0
var contracts_done: Array = []
var cycle := 0
var reputation := 50  # 0-100; feeds customer budgets
var debt := 0  # bank loan principal

const LOAN_TRANCHE := 1000
const LOAN_MAX := 10000
const LOAN_RATE := 0.05  # per revenue cycle

func borrow() -> bool:
	if debt + LOAN_TRANCHE > LOAN_MAX:
		return false
	debt += LOAN_TRANCHE
	money += LOAN_TRANCHE
	log_event("BANK: borrowed $%d (debt $%d, %d%% interest per cycle)" % [LOAN_TRANCHE, debt, int(LOAN_RATE * 100)])
	money_changed.emit()
	return true

func repay() -> bool:
	var amount := mini(LOAN_TRANCHE, debt)
	if amount <= 0 or money < amount:
		return false
	debt -= amount
	money -= amount
	money_changed.emit()
	return true
var events: Array = []  # operational event log (newest first)
var incidents_seen := {}  # "srv|dev" -> true, one breach per exposed pair
var offers: Array = []  # open marketplace offers
var deals: Array = []  # accepted: {id, customer, kind, params, fee, brief, healthy}
var _counter := {"switch": 0, "server": 0, "router": 0, "firewall": 0, "uplink": 0,
	"cooling": 0, "rack": 0, "mac": 0}

func grid_size() -> Vector2i:
	return STAGES[stage]["grid"]

func expand() -> bool:
	if stage >= STAGES.size() - 1:
		return false
	if not try_spend(STAGES[stage + 1]["price"]):
		return false
	stage += 1
	topology_changed.emit()
	return true

func cooling_capacity() -> int:
	var c := BASE_COOLING
	for d in all_devices():
		if d.type == "cooling" and d.status == "active":
			c += int(MODELS[d.model].get("cools", 0))
	return c

func overheating() -> bool:
	return stage >= 1 and power_draw() > cooling_capacity()

func power_draw() -> int:
	var w := 0
	for d in all_devices():
		if d.status == "active":
			w += WATTS.get(d.model, 0)
	return w

func try_complete_contract(c: Dictionary) -> bool:
	if c["id"] in contracts_done:
		return false
	for r in c["reqs"]:
		if not r["t"].call():
			return false
	contracts_done.append(c["id"])
	money += c["reward"]
	money_changed.emit()
	return true

const SLA_PERIOD := 45.0  # seconds per billing cycle

var sla_status := {}  # contract id -> bool (last billing check passed)
var cycle_timer: Timer

func _ready() -> void:
	if OS.get_environment("PACKET_TEST") == "1":
		save_path = "user://save_test.json"  # never touch the real save from tests
	topology_changed.connect(Sim.flush_learned_state)
	cycle_timer = Timer.new()
	cycle_timer.wait_time = SLA_PERIOD
	cycle_timer.autostart = true
	cycle_timer.timeout.connect(sla_tick)
	add_child(cycle_timer)

func respond_offer(offer: Dictionary, quote: int) -> String:
	var result := Market.negotiate(offer, quote)
	match result:
		"accepted":
			_offer_to_deal(offer, quote)
		"counter":
			offer["state"] = "counter"
		"rejected":
			offers.erase(offer)
	return result

func accept_counter(offer: Dictionary) -> void:
	_offer_to_deal(offer, int(offer["budget"]))

func dismiss_offer(offer: Dictionary) -> void:
	offers.erase(offer)

func _offer_to_deal(offer: Dictionary, fee: int) -> void:
	offers.erase(offer)
	deals.append({"id": offer["id"], "customer": offer["customer"], "kind": offer["kind"],
		"params": offer["params"], "fee": fee, "brief": offer["brief"], "healthy": false})
	money_changed.emit()

func log_event(text: String) -> void:
	events.push_front("cycle %d: %s" % [cycle, text])
	if events.size() > 20:
		events.pop_back()

func _security_sweep() -> int:
	## Customer machines (marketplace deal servers) that can reach the IP of
	## your routers/firewalls are a breach waiting to happen — once per pair.
	var cost := 0
	for deal in deals:
		var ip: String = deal["params"].get("ip", "")
		if ip == "":
			continue
		var srv := Contracts._owner(ip)
		if srv == null or srv.type != "server":
			continue
		for d in all_devices():
			if d.type == "uplink" or not (d.ip_forwarding or d.type == "switch"):
				continue
			var key := "%s|%s" % [srv.name, d.name]
			if incidents_seen.has(key):
				continue
			for i: Net.Iface in d.ifaces:
				if i.name == "lo" or i.ips.is_empty():
					continue
				var mgmt_ip: String = i.ips[0].split("/")[0]
				if Sim.ping(srv, mgmt_ip)["ok"]:
					incidents_seen[key] = true
					cost += 100
					reputation = maxi(0, reputation - 5)
					log_event("SECURITY: %s's machine %s reached %s management at %s — incident response -$100. Isolate your management plane (firewall it off from customer networks)!"
						% [deal["customer"], srv.name, d.name, mgmt_ip])
					break
			if incidents_seen.has(key):
				break
	return cost

func sla_tick() -> void:
	## Completed contracts pay recurring service fees — but only while
	## their requirements still hold. Break the network, lose the revenue.
	cycle += 1
	var earned := 0
	earned -= _security_sweep()
	if debt > 0:
		earned -= ceili(debt * LOAN_RATE)
	if money < 0:
		reputation = maxi(0, reputation - 2)
		log_event("BANK: you are insolvent ($%d) — reputation is bleeding." % money)
	if stage >= 1:  # colo includes power; your own room doesn't
		earned -= power_draw() / 10
	for c in Contracts.all():
		if c["id"] not in contracts_done:
			continue
		var ok := true
		for r in c["reqs"]:
			if not r["t"].call():
				ok = false
				break
		if sla_status.get(c["id"], true) and not ok:
			log_event("SLA BREACH: '%s' (%s) is down — fees suspended." % [c["title"], c["customer"]])
		sla_status[c["id"]] = ok
		if ok:
			earned += int(c["reward"]) / 10
	for d in all_devices():  # transit invoices
		for nb in d.bgp.get("neighbors", []):
			if Sim.bgp_established(d, nb):
				earned -= TRANSIT_FEE
	if overheating():
		# heat kills: one active device trips per cycle until capacity recovers
		for d in all_devices():
			if d.status == "active" and d.type != "cooling":
				d.status = "offline"
				topology_changed.emit()
				break
	for deal in deals:
		deal["healthy"] = Market.check(deal["kind"], deal["params"])
		if deal["healthy"]:
			earned += int(deal["fee"])
			reputation = mini(100, reputation + 1)
		else:
			reputation = maxi(0, reputation - 3)
	for offer in offers.duplicate():
		if not (offer is Dictionary) or not offer.has("ttl"):
			offers.erase(offer)  # defensive: drop malformed offers
			continue
		offer["ttl"] = int(offer["ttl"]) - 1
		if offer["ttl"] <= 0:
			offers.erase(offer)
	if offers.size() < 2 and contracts_done.size() >= 2 and randf() < 0.7:
		offers.append(Market.gen_offer())  # customers show up once you have a track record
	if earned != 0:
		money += earned
		money_changed.emit()

# ---------- money ----------

func try_spend(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	money_changed.emit()
	return true

func _refund(amount: int) -> void:
	money += amount
	money_changed.emit()

# ---------- racks ----------

func add_rack(tile: Vector2i) -> Net.Rack:
	_counter["rack"] += 1
	var r := Net.Rack.new("R%d" % _counter["rack"], tile)
	racks.append(r)
	return r

func rack_at(tile: Vector2i) -> Net.Rack:
	for r in racks:
		if r.tile == tile:
			return r
	return null

func rack_of(dev: Net.NDevice) -> Net.Rack:
	for r in racks:
		if dev in r.slots:
			return r
	return null

# ---------- devices ----------

func new_device(model: String) -> Net.NDevice:
	if not MODELS.has(model):
		model = TYPE_DEFAULTS[model]  # accept a bare type, pick its default model
	var m: Dictionary = MODELS[model]
	var type: String = m["type"]
	var spec: Dictionary = TYPE_SPECS[type]
	_counter[type] += 1
	var d := Net.NDevice.new(type, spec["name_prefix"] + str(_counter[type]))
	d.model = model
	if type == "switch":
		d.vlans = {1: "default"}
	if type in ["router", "firewall", "uplink"]:
		d.ip_forwarding = true
	if type == "uplink":
		# the ISP side is preconfigured: handoff /30 + anycast internet, announces default
		d.bgp = {"asn": 64500, "neighbors": [], "networks": ["0.0.0.0/0"]}
	for i in m["ports"]:
		var pfx: String = m.get("if_prefix", spec["if_prefix"])
		var ifc := Net.Iface.new(d, pfx + str(spec["if_start"] + i), _new_mac())
		if type != "switch":
			ifc.mode = "routed"
		d.ifaces.append(ifc)
	if type == "switch":
		var mgmt := Net.Iface.new(d, "Management1", _new_mac())
		mgmt.mode = "routed"
		d.ifaces.append(mgmt)
	if type == "uplink":
		d.ifaces[0].ips.append("100.64.0.1/30")
		var lo := Net.Iface.new(d, "lo", _new_mac())
		lo.mode = "routed"
		lo.ips = ["8.8.8.8/32", "1.1.1.1/32"]  # "the internet"
		d.ifaces.append(lo)
	return d

func uninstall_device(dev: Net.NDevice) -> void:
	for i: Net.Iface in dev.ifaces:
		disconnect_iface(i)
	var r := rack_of(dev)
	if r:
		r.slots[r.slots.find(dev)] = null
		if r.visual:
			r.visual.queue_redraw()
	_refund(MODELS[dev.model]["price"] / 2)
	topology_changed.emit()

func _new_mac() -> String:
	_counter["mac"] += 1
	return "02:50:45:00:%02X:%02X" % [_counter["mac"] / 256, _counter["mac"] % 256]

func all_devices() -> Array:
	var out: Array = []
	for r in racks:
		for d in r.slots:
			if d:
				out.append(d)
	return out

func rename_device(dev: Net.NDevice, new_name: String) -> bool:
	new_name = new_name.strip_edges()
	if new_name == "" or not new_name.is_valid_ascii_identifier():
		return false
	for d in all_devices():
		if d != dev and d.name == new_name:
			return false
	dev.name = new_name
	topology_changed.emit()
	return true

# ---------- cables ----------

func link_at(i: Net.Iface) -> Net.Link:
	for l in links:
		if l.a == i or l.b == i:
			return l
	return null

func peer_label(i: Net.Iface) -> String:
	var l := link_at(i)
	if l == null:
		return ""
	var p := l.other(i)
	return "%s %s" % [p.dev.name, p.name]

func connect_ifaces(a: Net.Iface, b: Net.Iface) -> void:
	links.append(Net.Link.new(a, b))
	topology_changed.emit()

func disconnect_iface(i: Net.Iface) -> void:
	var l := link_at(i)
	if l:
		links.erase(l)
		topology_changed.emit()

func free_ifaces(exclude: Net.NDevice) -> Array:
	var out: Array = []
	for d in all_devices():
		if d == exclude:
			continue
		for i in d.ifaces:
			if link_at(i) == null and i.name != "lo":
				out.append(i)
	return out

# ---------- VLANs / IPAM ----------

func add_vlan(dev: Net.NDevice, vid: int, name: String) -> bool:
	name = name.strip_edges()
	if name == "":
		name = "vlan%d" % vid
	if dev.type != "switch" or vid < 1 or vid > 4094 or dev.vlans.has(vid):
		return false
	dev.vlans[vid] = name
	topology_changed.emit()
	return true

func remove_vlan(dev: Net.NDevice, vid: int) -> bool:
	if vid == 1 or not dev.vlans.has(vid):
		return false  # default VLAN stays
	dev.vlans.erase(vid)
	for i in dev.ifaces:
		if i.untagged_vlan == vid:
			i.untagged_vlan = 1
	topology_changed.emit()
	return true

func set_access_vlan(i: Net.Iface, vid: int) -> bool:
	if not i.dev.vlans.has(vid):
		return false
	i.untagged_vlan = vid
	topology_changed.emit()
	return true

func add_ip(i: Net.Iface, cidr: String) -> bool:
	cidr = cidr.strip_edges()
	if not Net.valid_cidr(cidr) or cidr in i.ips:
		return false
	i.ips.append(cidr)
	topology_changed.emit()
	return true

func remove_ip(i: Net.Iface, cidr: String) -> void:
	i.ips.erase(cidr)
	topology_changed.emit()

func add_static_route(dev: Net.NDevice, prefix: String, plen: int, via: String) -> bool:
	if not via.is_valid_ip_address() or plen < 0 or plen > 32 or not prefix.is_valid_ip_address():
		return false
	remove_static_route(dev, prefix, plen)
	dev.static_routes.append({"prefix": prefix, "plen": plen, "via": via})
	topology_changed.emit()
	return true

func remove_static_route(dev: Net.NDevice, prefix: String, plen: int) -> void:
	for r in dev.static_routes.duplicate():
		if r["prefix"] == prefix and int(r["plen"]) == plen:
			dev.static_routes.erase(r)
	topology_changed.emit()

# ---------- save / load ----------

func save_game() -> void:
	var devs := {}  # name -> serialized (names are unique)
	var rack_data: Array = []
	for r in racks:
		var slot_names: Array = []
		for d in r.slots:
			slot_names.append(d.name if d else null)
			if d:
				devs[d.name] = _ser_device(d)
		rack_data.append({"name": r.name, "tile": [r.tile.x, r.tile.y], "slots": slot_names})
	var link_data: Array = []
	for l in links:
		link_data.append([l.a.dev.name, l.a.name, l.b.dev.name, l.b.name])
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"money": money, "stage": stage, "cycle": cycle,
		"reputation": reputation, "debt": debt,
		"events": events, "incidents_seen": incidents_seen, "counters": _counter,
		"contracts_done": contracts_done, "offers": offers, "deals": deals,
		"racks": rack_data, "devices": devs, "links": link_data}, "  "))

func _ser_device(d: Net.NDevice) -> Dictionary:
	var ifs: Array = []
	for i: Net.Iface in d.ifaces:
		ifs.append({"name": i.name, "mac": i.mac, "enabled": i.enabled, "mtu": i.mtu,
			"mode": i.mode, "untagged_vlan": i.untagged_vlan, "tagged_vlans": i.tagged_vlans,
			"nat": i.nat, "ips": i.ips})
	return {"type": d.type, "model": d.model, "name": d.name, "status": d.status, "vlans": d.vlans,
		"ip_forwarding": d.ip_forwarding, "static_routes": d.static_routes,
		"services": d.services, "resolver": d.resolver, "acls": d.acls, "bgp": d.bgp,
		"ospf": d.ospf, "ifaces": ifs}

func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data == null:
		return false
	racks = []
	links = []
	money = int(data["money"])
	contracts_done = data.get("contracts_done", [])
	stage = int(data.get("stage", 0))
	offers = data.get("offers", [])
	cycle = int(data.get("cycle", 0))
	reputation = int(data.get("reputation", 50))
	debt = int(data.get("debt", 0))
	events = data.get("events", [])
	incidents_seen = data.get("incidents_seen", {})
	deals = data.get("deals", [])
	for k in data["counters"]:
		_counter[k] = int(data["counters"][k])
	var by_name := {}
	for dname in data["devices"]:
		var sd: Dictionary = data["devices"][dname]
		var d := Net.NDevice.new(sd["type"], sd["name"])
		d.model = sd.get("model", TYPE_DEFAULTS[sd["type"]])
		d.status = sd["status"]
		d.ip_forwarding = sd["ip_forwarding"]
		d.static_routes = sd["static_routes"]
		d.services = sd.get("services", {})
		d.acls = sd.get("acls", [])
		d.bgp = sd.get("bgp", {})
		d.ospf = sd.get("ospf", {})
		d.resolver = sd.get("resolver", "")
		for vid in sd["vlans"]:
			d.vlans[int(vid)] = sd["vlans"][vid]
		for si in sd["ifaces"]:
			var i := Net.Iface.new(d, si["name"], si["mac"])
			i.enabled = si["enabled"]
			i.mtu = int(si["mtu"])
			i.mode = si["mode"]
			i.untagged_vlan = int(si["untagged_vlan"])
			for tv in si.get("tagged_vlans", []):
				i.tagged_vlans.append(int(tv))
			i.nat = si.get("nat", "")
			i.ips = si["ips"]
			d.ifaces.append(i)
		if d.type == "switch":
			var has_mgmt := false
			for i: Net.Iface in d.ifaces:
				if i.name.begins_with("Management"):
					has_mgmt = true
			if not has_mgmt:  # migrate saves from before OOB management
				var mgmt := Net.Iface.new(d, "Management1", _new_mac())
				mgmt.mode = "routed"
				d.ifaces.append(mgmt)
		by_name[d.name] = d
	for rd in data["racks"]:
		var r := Net.Rack.new(rd["name"], Vector2i(int(rd["tile"][0]), int(rd["tile"][1])))
		for si in rd["slots"].size():
			if rd["slots"][si] != null:
				r.slots[si] = by_name[rd["slots"][si]]
		racks.append(r)
	for ld in data["links"]:
		var a := _find_iface(by_name[ld[0]], ld[1])
		var b := _find_iface(by_name[ld[2]], ld[3])
		if a and b:
			links.append(Net.Link.new(a, b))
	money_changed.emit()
	topology_changed.emit()
	return true

func _find_iface(dev: Net.NDevice, ifname: String) -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if i.name == ifname:
			return i
	return null
