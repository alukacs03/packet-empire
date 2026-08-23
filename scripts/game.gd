extends Node
## Autoload "Game": the datacenter source of truth (racks, devices,
## interfaces, cables, per-switch VLANs, money). NetBox-style model.

signal topology_changed
signal money_changed

# Hardware catalog: fictional vendors, real tiers. New model = new entry.
const MODELS := {
	"sw-lite": {"speed": 1000, "tier": 0, "type": "switch", "label": "PacketTik SW5", "ports": 5, "price": 90, "os": "ros", "if_prefix": "ether"},
	"sw-8": {"speed": 1000, "tier": 1, "type": "switch", "label": "OpenRack S8", "ports": 8, "price": 250},
	"sw-24": {"speed": 10000, "tier": 2, "type": "switch", "label": "Arivista 7024", "ports": 24, "price": 900, "l3": true},
	"srv-1": {"speed": 1000, "tier": 0, "type": "server", "ports": 1, "label": "Dill R110", "price": 400},
	"srv-2": {"speed": 10000, "tier": 1, "type": "server", "ports": 2, "label": "Dill R220 (dual NIC)", "price": 700},
	"rtr-lite": {"speed": 1000, "tier": 0, "type": "router", "ports": 4, "label": "PacketTik R4", "price": 350, "os": "ros", "if_prefix": "ether"},
	"rtr-edge": {"speed": 10000, "tier": 2, "type": "router", "ports": 8, "label": "Junivista MX8", "price": 1200},
	"fw-1": {"speed": 1000, "tier": 1, "type": "firewall", "ports": 4, "label": "PacketSense FW4", "price": 800},
	"lb-1": {"speed": 10000, "tier": 2, "type": "loadbalancer", "ports": 4,
		"label": "Equipoise LB10", "price": 1400},
	"ap-1": {"speed": 1000, "tier": 1, "type": "ap", "ports": 9, "label": "AirTurul AP3",
		"price": 320},
	"isp-uplink": {"speed": 1000, "tier": 1, "type": "uplink", "ports": 1, "label": "ISP Handoff (AS64500)", "price": 200},
	"crac-1": {"speed": 0, "tier": 1, "type": "cooling", "ports": 0, "label": "CoolRow CRAC", "price": 600, "cools": 1500},
}
const WATTS := {"sw-lite": 10, "sw-8": 30, "sw-24": 80, "srv-1": 150, "srv-2": 250,
	"rtr-lite": 20, "rtr-edge": 90, "fw-1": 40, "isp-uplink": 5, "crac-1": 100, "lb-1": 120,
	"ap-1": 15}
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
	"uplink": "isp-uplink", "cooling": "crac-1", "loadbalancer": "lb-1", "ap": "ap-1"}
const TYPE_SPECS := {
	"switch": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "sw"},
	"server": {"if_prefix": "eth", "if_start": 0, "name_prefix": "srv"},
	"router": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "rtr"},
	"firewall": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "fw"},
	"uplink": {"if_prefix": "port", "if_start": 1, "name_prefix": "isp"},
	"cooling": {"if_prefix": "port", "if_start": 1, "name_prefix": "crac"},
	"loadbalancer": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "lb"},
	"ap": {"if_prefix": "radio", "if_start": 1, "name_prefix": "ap"},
}
const DIFFICULTIES := [
	{"name": "Apprentice", "cash": 4000, "aggression": 0.75, "faults": 0.5, "cycle": 60.0,
		"blurb": "More money, gentler competition, fewer failures, a slower clock."},
	{"name": "Operator", "cash": 2000, "aggression": 1.0, "faults": 1.0, "cycle": 45.0,
		"blurb": "The intended experience."},
	{"name": "On call", "cash": 1200, "aggression": 1.2, "faults": 1.8, "cycle": 32.0,
		"blurb": "Thin margins, hungry rivals, and things break often."},
]
const RACK_PRICE := 500
var save_path := "user://save.json"

var sites: Array = []  # [{name, grid: [w,h], kind}]; site 0 is your own floor
var current_site := 0
var racks: Array = []
var links: Array = []
var money := 2000
var stage := 0
var difficulty := 1
var contracts_done: Array = []
var cycle := 0
var reputation := 50  # 0-100; feeds customer budgets
var debt := 0  # bank loan principal
var stats := {"earned": 0, "incidents": 0, "faults": 0, "contracts": 0, "deals": 0}
var achievements: Array = []  # ids already earned

const ACHIEVEMENTS := [
	{"id": "first_light", "name": "First light", "how": "Complete your first contract."},
	{"id": "segmented", "name": "Good fences", "how": "Run at least three VLANs on one switch."},
	{"id": "on_the_internet", "name": "On the internet", "how": "Establish a BGP session with an upstream."},
	{"id": "no_spof", "name": "No single point of failure", "how": "Run a VRRP group with two members."},
	{"id": "empire", "name": "Two roofs", "how": "Operate two or more sites."},
	{"id": "acquirer", "name": "Acquirer", "how": "Buy a competitor."},
	{"id": "disciplined", "name": "Disciplined", "how": "Have every device's configuration saved at once."},
	{"id": "employer", "name": "Employer", "how": "Put three people on the payroll."},
	{"id": "steady", "name": "Steady hands", "how": "Reach cycle 50 with reputation at 80 or better."},
	{"id": "fabric", "name": "Fabric builder", "how": "Give a router two equal-cost paths to a destination."},
]

func _achievement_met(id: String) -> bool:
	match id:
		"first_light":
			return int(stats.get("contracts", 0)) >= 1
		"segmented":
			for d in all_devices():
				if d.type == "switch" and d.vlans.size() >= 3:
					return true
			return false
		"on_the_internet":
			# passive: a configured session towards a device that speaks BGP
			for d in all_devices():
				for nb in d.bgp.get("neighbors", []):
					var peer := Sim._ip_owner(nb["ip"])
					if peer != null and not peer.bgp.is_empty():
						return true
			return false
		"no_spof":
			var vips := {}
			for d in all_devices():
				for i: Net.Iface in d.ifaces:
					if not i.vrrp.is_empty():
						var k := "%s|%d" % [i.vrrp["vip"], int(i.vrrp["group"])]
						vips[k] = int(vips.get(k, 0)) + 1
						if int(vips[k]) >= 2:
							return true
			return false
		"empire":
			return site_count() >= 2
		"acquirer":
			for r in rivals:
				if not Rivals.alive(r) and not r.has("merged_into"):
					return true
			return false
		"disciplined":
			var any := false
			for d in all_devices():
				if d.type in ["server", "uplink", "cooling"]:
					continue
				any = true
				if config_dirty(d):
					return false
			return any
		"employer":
			return staff.size() >= 3
		"steady":
			return cycle >= 50 and reputation >= 80
		"fabric":
			# passive check: the same prefix learned through two next hops.
			# (deliberately does not probe the network, because evaluating an
			# achievement must never change the thing it is measuring)
			for d in all_devices():
				if not d.ip_forwarding:
					continue
				var vias := {}
				for r in Sim._ospf_learned(d):
					var key := "%s/%d" % [r["prefix"], int(r["plen"])]
					if not vias.has(key):
						vias[key] = {}
					vias[key][r["via"]] = true
					if vias[key].size() >= 2:
						return true
			return false
	return false

func check_achievements() -> Array:
	var newly: Array = []
	for a in ACHIEVEMENTS:
		if a["id"] in achievements:
			continue
		if _achievement_met(a["id"]):
			achievements.append(a["id"])
			newly.append(a)
			log_event("ACHIEVEMENT: %s (%s)" % [a["name"], a["how"]])
	return newly

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
var rivals: Array = []  # AI competitors
var market_intel := 0  # bids observed: the more you have seen, the tighter your estimate
var templates: Array = []  # golden configs: {name, type, cfg}
var blueprints: Array = []  # rack layouts: {name, slots: [model|null]}
var maintenance_until := -1  # cycle up to which planned work is excused
var maintenance_used := 0  # windows taken this quarter: customers notice
var incidents: Array = []  # things worth reviewing afterwards
var status_posts: Array = []  # public incident communication
var spares := {}  # model -> how many replacement units are on the shelf
var attacks: Array = []  # live DDoS events: {target, mbps, cycles_left}
var scrubbing := false  # upstream scrubbing service, billed per cycle
var insured := false  # insurance against hardware failure, billed per cycle
var marketing := 0  # spend per cycle to bring more work in
var sandbox := false  # free hardware, no bills, no events: a place to try things
const INSURANCE_FEE := 140
const MARKETING_STEP := 150
const SCRUB_FEE := 220
var monitors: Array = []  # player-defined checks: {kind, from, target, label, failing}
var history: Array = []  # per-cycle snapshot for the graphs
var reports: Array = []  # quarterly summaries
var staff: Array = []  # people on the payroll
var candidates: Array = []  # the current hiring market
var acquisitions: Array = []  # integration jobs from companies you bought
var circuits: Array = []  # leased WAN links between sites: {a, b, mbps, fee}
var offers: Array = []  # open marketplace offers
var deals: Array = []  # accepted: {id, customer, kind, params, fee, brief, healthy}
var _counter := {"switch": 0, "server": 0, "router": 0, "firewall": 0, "uplink": 0,
	"cooling": 0, "loadbalancer": 0, "ap": 0, "rack": 0, "mac": 0}

func _ensure_sites() -> void:
	if sites.is_empty():
		sites = [{"name": "Home floor", "grid": [0, 0], "kind": "own", "city": "Budapest"}]
	for s_i in sites:
		if not s_i.has("city"):
			s_i["city"] = CITIES[0]

func site_city(idx: int) -> String:
	_ensure_sites()
	if idx < 0 or idx >= sites.size():
		return CITIES[0]
	return String(sites[idx].get("city", CITIES[0]))

func site_distance_km(a: int, b: int) -> float:
	var pa: Array = CITY_POS.get(site_city(a), [0, 0])
	var pb: Array = CITY_POS.get(site_city(b), [0, 0])
	return Vector2(float(pa[0]), float(pa[1])).distance_to(Vector2(float(pb[0]), float(pb[1])))

func link_latency_ms(l: Net.Link) -> float:
	## inside a building a link is effectively instant; between buildings the
	## speed of light in fibre is about 200 km per millisecond, and carriers
	## never take the straight line
	var s := sites_of(l.a, l.b)
	if s[0] == s[1]:
		return 0.05
	return maxf(0.5, site_distance_km(s[0], s[1]) / 200.0 * 1.4)

func site_count() -> int:
	_ensure_sites()
	return sites.size()

func site_name(idx: int) -> String:
	_ensure_sites()
	if idx < 0 or idx >= sites.size():
		return "a site you no longer operate"
	return sites[idx]["name"]

func _scale_rival_aggression() -> void:
	var factor := float(DIFFICULTIES[difficulty]["aggression"])
	for r in rivals:
		r["aggression"] = float(r.get("base_aggression", r["aggression"])) * factor

func apply_difficulty(idx: int) -> void:
	difficulty = clampi(idx, 0, DIFFICULTIES.size() - 1)
	var d: Dictionary = DIFFICULTIES[difficulty]
	money = int(d["cash"])
	if cycle_timer:
		cycle_timer.wait_time = float(d["cycle"]) / maxf(1.0, float(speed))
	_scale_rival_aggression()
	money_changed.emit()

func fault_scale() -> float:
	return float(DIFFICULTIES[difficulty]["faults"])

func grid_size(site := -1) -> Vector2i:
	_ensure_sites()
	var idx := current_site if site < 0 else site
	if idx < 0 or idx >= sites.size():
		idx = 0
	if idx == 0:
		return STAGES[stage]["grid"]  # your own floor grows with your career
	var g: Array = sites[idx]["grid"]
	return Vector2i(int(g[0]), int(g[1]))

func switch_site(idx: int) -> void:
	if idx >= 0 and idx < site_count():
		current_site = idx
		topology_changed.emit()

func add_site(name: String, grid: Vector2i, kind := "acquired", city := "") -> int:
	_ensure_sites()
	if city == "":
		city = CITIES[sites.size() % CITIES.size()]
	sites.append({"name": name, "grid": [grid.x, grid.y], "kind": kind, "city": city})
	return sites.size() - 1

const CITIES := ["Budapest", "Debrecen", "Szeged", "Gyor", "Pecs", "Miskolc", "Vienna", "Bratislava"]
const CITY_POS := {  # rough relative positions, in kilometres from Budapest
	"Budapest": [0, 0], "Debrecen": [190, 20], "Szeged": [140, 130], "Gyor": [-110, -20],
	"Pecs": [30, 160], "Miskolc": [140, -110], "Vienna": [-215, -40], "Bratislava": [-160, -60],
}

const SITE_OFFERS := [
	{"label": "Small branch room", "grid": [5, 5], "setup": 9000, "rent": 120},
	{"label": "Regional server room", "grid": [8, 8], "setup": 22000, "rent": 300},
	{"label": "Second datacenter floor", "grid": [12, 12], "setup": 60000, "rent": 700},
]

func lease_site(offer_idx: int) -> String:
	var o: Dictionary = SITE_OFFERS[offer_idx]
	if not try_spend(int(o["setup"])):
		return "you cannot afford the $%d fit-out" % int(o["setup"])
	var g: Array = o["grid"]
	var idx := add_site("%s %d" % [o["label"], site_count()], Vector2i(int(g[0]), int(g[1])), "leased")
	sites[idx]["rent"] = int(o["rent"])
	log_event("SITE: leased a %s ($%d/cycle rent). Reaching it needs a circuit." % [o["label"], int(o["rent"])])
	topology_changed.emit()
	return ""

const CIRCUIT_GRADES := [
	{"label": "100 Mbit metro line", "mbps": 100, "setup": 1200, "fee": 60},
	{"label": "1 Gbit leased line", "mbps": 1000, "setup": 4000, "fee": 180},
	{"label": "10 Gbit dark fibre", "mbps": 10000, "setup": 14000, "fee": 500},
]

func circuit_between(site_a: int, site_b: int) -> Dictionary:
	for c in circuits:
		if (int(c["a"]) == site_a and int(c["b"]) == site_b) \
				or (int(c["a"]) == site_b and int(c["b"]) == site_a):
			return c
	return {}

func buy_circuit(site_a: int, site_b: int, grade: int) -> String:
	if site_a == site_b:
		return "a site does not need a circuit to itself"
	if not circuit_between(site_a, site_b).is_empty():
		return "those sites are already linked"
	var g: Dictionary = CIRCUIT_GRADES[grade]
	if not try_spend(int(g["setup"])):
		return "you cannot afford the $%d installation" % int(g["setup"])
	circuits.append({"a": site_a, "b": site_b, "mbps": int(g["mbps"]),
		"fee": int(g["fee"]), "label": g["label"]})
	log_event("CIRCUIT: %s ordered between %s and %s ($%d/cycle)." % [g["label"],
		site_name(site_a), site_name(site_b), int(g["fee"])])
	topology_changed.emit()
	return ""

func cancel_circuit(c: Dictionary) -> void:
	for l in links.duplicate():
		if rack_of(l.a.dev) and rack_of(l.b.dev) \
				and rack_of(l.a.dev).site != rack_of(l.b.dev).site:
			var cc := circuit_between(rack_of(l.a.dev).site, rack_of(l.b.dev).site)
			if cc == c:
				links.erase(l)  # the cables riding it go with it
	circuits.erase(c)
	log_event("CIRCUIT: cancelled %s." % c["label"])
	topology_changed.emit()

func sites_of(a: Net.Iface, b: Net.Iface) -> Array:
	var ra := rack_of(a.dev)
	var rb := rack_of(b.dev)
	return [ra.site if ra else 0, rb.site if rb else 0]

func can_link(a: Net.Iface, b: Net.Iface) -> bool:
	var s := sites_of(a, b)
	if s[0] == s[1]:
		return true
	return not circuit_between(s[0], s[1]).is_empty()

func racks_on(site: int) -> Array:
	var out: Array = []
	for r in racks:
		if r.site == site:
			out.append(r)
	return out

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

func is_l3_switch(dev: Net.NDevice) -> bool:
	return dev.type == "switch" and bool(MODELS.get(dev.model, {}).get("l3", false))

func set_ssid(ap: Net.NDevice, name: String, vid: int) -> String:
	if ap.type != "ap":
		return "only an access point broadcasts an SSID"
	if vid < 1 or vid > 4094:
		return "that is not a VLAN id"
	ap.ssids[name] = vid
	if not ap.vlans.has(vid):
		ap.vlans[vid] = name
	topology_changed.emit()
	return ""

func wifi_join(client: Net.NDevice, ssid: String) -> String:
	## associating is modelled as the radio link it is: the client ends up on
	## a port of the access point, in the VLAN that SSID maps to
	if client.type != "server":
		return "only a host associates with a network"
	wifi_leave(client)
	var client_rack := rack_of(client)
	for ap in all_devices():
		if ap.type != "ap" or not ap.ssids.has(ssid) or ap.status != "active":
			continue
		var ap_rack := rack_of(ap)
		if client_rack and ap_rack and client_rack.site != ap_rack.site:
			continue  # out of range: radios do not cross buildings
		for radio: Net.Iface in ap.ifaces:
			if radio.name.begins_with("radio") and link_at(radio) == null:
				radio.mode = "access"
				radio.untagged_vlan = int(ap.ssids[ssid])
				if connect_ifaces(client.ifaces[0], radio):
					client.wifi = ssid
					log_event("WIFI: %s associated with '%s' on %s." % [client.name, ssid, ap.name])
					return ""
	return "no access point in range is broadcasting '%s'" % ssid

func wifi_leave(client: Net.NDevice) -> void:
	for i: Net.Iface in client.ifaces:
		var l := link_at(i)
		if l and l.other(i).dev.type == "ap":
			disconnect_iface(i)
	client.wifi = ""

func create_vm(host: Net.NDevice, name: String) -> Net.Iface:
	## a virtual machine on a server: its own NIC, riding the host's uplink
	if host.type != "server" or name.strip_edges() == "":
		return null
	for d in all_devices():
		for i: Net.Iface in d.ifaces:
			if i.vm == name:
				return null  # names are unique across the estate
	var nic := Net.Iface.new(host, "vnic-%s" % name, _new_mac())
	nic.mode = "routed"
	nic.vm = name
	host.ifaces.append(nic)
	topology_changed.emit()
	return nic

func find_vm(name: String) -> Net.Iface:
	for d in all_devices():
		for i: Net.Iface in d.ifaces:
			if i.vm == name:
				return i
	return null

func migrate_vm(name: String, target: Net.NDevice) -> String:
	## live migration: the machine keeps its addresses and moves house. Whether
	## it still works afterwards is a question for the network, not the server.
	var nic := find_vm(name)
	if nic == null:
		return "no virtual machine called '%s'" % name
	if target.type != "server":
		return "virtual machines run on servers"
	if nic.dev == target:
		return "it already runs there"
	var source := nic.dev
	source.ifaces.erase(nic)
	nic.dev = target
	target.ifaces.append(nic)
	log_event("MIGRATION: %s moved from %s to %s, keeping %s."
		% [name, source.name, target.name,
			", ".join(PackedStringArray(nic.ips)) if not nic.ips.is_empty() else "no address"])
	topology_changed.emit()
	return ""

func add_wireguard(dev: Net.NDevice, num: int) -> Net.Iface:
	## a WireGuard interface: identified by a key, with peers rather than a
	## single far end, and an allowed-IPs list that is also its routing policy
	if not dev.ip_forwarding and dev.type != "server":
		return null
	var name := "wg%d" % num
	for i: Net.Iface in dev.ifaces:
		if i.name == name:
			return i
	var w := Net.Iface.new(dev, name, _new_mac())
	w.mode = "routed"
	w.wg_key = "%s-key-%d" % [dev.name.to_lower(), num]  # stands in for a real public key
	dev.ifaces.append(w)
	topology_changed.emit()
	return w

func add_tunnel(dev: Net.NDevice, num: int) -> Net.Iface:
	## a virtual point-to-point interface that rides whatever path exists
	if not dev.ip_forwarding:
		return null
	var name := "Tunnel%d" % num
	for i: Net.Iface in dev.ifaces:
		if i.name == name:
			return i
	var t := Net.Iface.new(dev, name, _new_mac())
	t.mode = "routed"
	dev.ifaces.append(t)
	topology_changed.emit()
	return t

func add_subiface(dev: Net.NDevice, parent_name: String, vid: int) -> Net.Iface:
	## 802.1Q subinterface: router-on-a-stick
	if not dev.ip_forwarding or vid < 1 or vid > 4094:
		return null
	var parent: Net.Iface = null
	for i: Net.Iface in dev.ifaces:
		if i.name == parent_name and i.parent == "":
			parent = i
	if parent == null:
		return null
	var sub_name := "%s.%d" % [parent_name, vid]
	for i: Net.Iface in dev.ifaces:
		if i.name == sub_name:
			return i
	var sub := Net.Iface.new(dev, sub_name, _new_mac())
	sub.mode = "routed"
	sub.parent = parent_name
	sub.dot1q = vid
	dev.ifaces.append(sub)
	topology_changed.emit()
	return sub

func add_svi(dev: Net.NDevice, vid: int) -> Net.Iface:
	## a virtual routed interface for VLAN vid on an L3 switch
	if not is_l3_switch(dev) or not dev.vlans.has(vid):
		return null
	for i: Net.Iface in dev.ifaces:
		if i.name == "Vlan%d" % vid:
			return i
	var svi := Net.Iface.new(dev, "Vlan%d" % vid, _new_mac())
	svi.mode = "routed"
	dev.ifaces.append(svi)
	dev.ip_forwarding = true  # an L3 switch routes between its SVIs
	topology_changed.emit()
	return svi

const RANKS := [
	["Cable monkey", 0],
	["Junior NOC operator", 3000],
	["Network engineer", 12000],
	["Senior network engineer", 30000],
	["Datacenter architect", 70000],
	["Packet Emperor", 150000],
]

func capacity(site: int) -> Dictionary:
	## headroom on one floor: space, power, cooling and switch ports
	var g := grid_size(site)
	var tiles: int = g.x * g.y
	var used_tiles := racks_on(site).size()
	var slots_total := used_tiles * Net.Rack.SLOTS
	var slots_used := 0
	var watts := 0
	var ports_total := 0
	var ports_used := 0
	for r in racks_on(site):
		for d in r.slots:
			if d == null:
				continue
			slots_used += 1
			if d.status == "active":
				watts += int(WATTS.get(d.model, 0))
			for i: Net.Iface in d.ifaces:
				if i.name == "lo" or i.name.begins_with("Vlan") or i.name.begins_with("Tunnel") \
						or i.parent != "":
					continue
				ports_total += 1
				if link_at(i) != null:
					ports_used += 1
	return {"tiles": tiles, "tiles_used": used_tiles,
		"slots": slots_total, "slots_used": slots_used,
		"watts": watts, "cooling": cooling_capacity() if site == 0 else 0,
		"ports": ports_total, "ports_used": ports_used}

func make_report() -> Dictionary:
	## a quarter is twelve revenue cycles
	var window: Array = history.slice(maxi(0, history.size() - 12))
	var net := 0
	for h in window:
		net += int(h.get("net", 0))
	var up := 0
	var deal_cycles := 0
	for h in window:
		up += int(h.get("up", 0))
		deal_cycles += int(h.get("deals", 0))
	var rep := {
		"quarter": int(cycle / 12), "cycle": cycle, "money": money, "net": net,
		"deals": deals.size(), "staff": staff.size(), "sites": site_count(),
		"reputation": reputation, "rank": rank(), "devices": all_devices().size(),
		"uptime": int(100.0 * float(up) / maxf(1.0, float(deal_cycles))),
	}
	reports.push_front(rep)
	if reports.size() > 8:
		reports.pop_back()
	log_event("QUARTER %d closed: net %s$%d, %d customers, %d%% delivered, rank %s."
		% [int(rep["quarter"]), "+" if net >= 0 else "-", absi(net), deals.size(),
			int(rep["uptime"]), rep["rank"]])
	return rep

func rank_score() -> int:
	## lifetime earnings, weighted by the scale and quality of the operation
	var base: int = int(stats.get("earned", 0))
	var bonus: int = int(stats.get("contracts", 0)) * 500 + int(stats.get("deals", 0)) * 250 \
		+ stage * 4000 + (reputation - 50) * 40
	return maxi(0, base + bonus)

func rank() -> String:
	var name: String = RANKS[0][0]
	for r in RANKS:
		if rank_score() >= int(r[1]):
			name = r[0]
	return name

func next_rank() -> Array:
	## -> [name, points_needed] or [] when at the top
	for r in RANKS:
		if rank_score() < int(r[1]):
			return [r[0], int(r[1]) - rank_score()]
	return []

func config_dirty(d: Net.NDevice) -> bool:
	## running config differs from what a reboot would restore
	if d.type in ["server", "uplink", "cooling"]:
		return false
	return JSON.stringify(device_config(d)) != JSON.stringify(d.startup)

func iface_speed(i: Net.Iface) -> int:
	## Mbps; management ports are 100M service ports
	if i.name.begins_with("Management") or i.name == "lo":
		return 100
	return int(MODELS[i.dev.model].get("speed", 1000))

func lag_members(l: Net.Link) -> Array:
	## all links in the same bundle as l (including l); [] means standalone
	if l.a.lag == 0 or l.b.lag == 0:
		return []
	var out: Array = []
	for m in links:
		if m.a.dev == l.a.dev and m.b.dev == l.b.dev and m.a.lag == l.a.lag and m.b.lag == l.b.lag:
			out.append(m)
		elif m.a.dev == l.b.dev and m.b.dev == l.a.dev and m.a.lag == l.b.lag and m.b.lag == l.a.lag:
			out.append(m)
	return out

func link_capacity(l: Net.Link) -> int:
	var s := sites_of(l.a, l.b)
	if s[0] != s[1]:
		var c := circuit_between(s[0], s[1])
		return int(c.get("mbps", 0)) if not c.is_empty() else 0
	var members := lag_members(l)
	if members.size() <= 1:
		return mini(iface_speed(l.a), iface_speed(l.b))
	var total := 0
	for m in members:
		if m.a.enabled and m.b.enabled:
			total += mini(iface_speed(m.a), iface_speed(m.b))
	return total

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
	if Contracts.SUPERSEDES.has(c["id"]):
		sla_status[Contracts.SUPERSEDES[c["id"]]] = true  # retire immediately, no stale breach
	stats["contracts"] += 1
	stats["earned"] += int(c["reward"])
	money += c["reward"]
	money_changed.emit()
	return true

const SLA_PERIOD := 45.0  # seconds per billing cycle

var sla_status := {}  # contract id -> bool (last billing check passed)
var last_link_load := {}  # Link -> Mbps, from the latest cycle
var last_cycle_delta := 0
var last_pl := {}  # line item -> amount, from the latest cycle
var cycle_timer: Timer
var speed := 1  # 0 = paused, otherwise a multiplier on the revenue cycle

signal speed_changed

func set_speed(v: int) -> void:
	speed = clampi(v, 0, 3)
	if cycle_timer:
		cycle_timer.paused = speed == 0
		if speed > 0:
			cycle_timer.wait_time = SLA_PERIOD / float(speed)
			if cycle_timer.is_stopped():
				cycle_timer.start()
	speed_changed.emit()

func toggle_pause() -> void:
	set_speed(0 if speed > 0 else 1)

func _ready() -> void:
	rivals = Rivals.spawn()
	_scale_rival_aggression()
	if OS.get_environment("PACKET_TEST") == "1":
		save_path = "user://save_test.json"  # never touch the real save from tests
	topology_changed.connect(Sim.flush_learned_state)
	cycle_timer = Timer.new()
	cycle_timer.wait_time = SLA_PERIOD
	cycle_timer.autostart = true
	cycle_timer.timeout.connect(sla_tick)
	add_child(cycle_timer)
	set_speed(speed)

func respond_offer(offer: Dictionary, quote: int) -> String:
	var result := Market.negotiate(offer, quote)
	# rivals bid first: a customer with somewhere else to go does not simply
	# walk away, they take their business to whoever is cheaper
	var rival := Rivals.best_bidder(offer)
	if not rival.is_empty():
		var bid: int = Rivals.bid_for(rival, offer)
		if bid <= int(offer["budget"]) and quote > bid:
			offers.erase(offer)
			rival["deals"] = int(rival["deals"]) + 1
			rival["revenue"] = int(rival["revenue"]) + bid
			market_intel += 1
			log_event("LOST: %s went to %s, who quoted $%d against your $%d. (You now know the market better.)"
				% [offer["customer"], rival["name"], bid, quote])
			return "undercut"
	match result:
		"accepted":
			_offer_to_deal(offer, quote)
		"counter":
			offer["state"] = "counter"
		"rejected":
			offers.erase(offer)
	return result

func add_monitor(kind: String, from_dev: String, target: String) -> String:
	for m in monitors:
		if m["kind"] == kind and m["from"] == from_dev and m["target"] == target:
			return "that check already exists"
	monitors.append({"kind": kind, "from": from_dev, "target": target, "failing": false})
	topology_changed.emit()
	return ""

func remove_monitor(m: Dictionary) -> void:
	monitors.erase(m)
	topology_changed.emit()

func monitor_ok(m: Dictionary) -> bool:
	match m["kind"]:
		"ping":
			var src: Net.NDevice = null
			for d in all_devices():
				if d.name == m["from"]:
					src = d
			if src == null:
				return false
			return Sim.ping(src, m["target"])["ok"]
		"link":
			for l in links:
				var a_name := "%s %s" % [l.a.dev.name, l.a.name]
				var b_name := "%s %s" % [l.b.dev.name, l.b.name]
				if m["target"] in [a_name, b_name]:
					return l.a.enabled and l.b.enabled \
						and l.a.dev.status == "active" and l.b.dev.status == "active"
			return false
	return false

func lb_health_check() -> void:
	## the load balancer keeps its pool honest: a member that stops answering
	## is taken out of rotation until it comes back
	for d in all_devices():
		var svc: Dictionary = d.services.get("lb", {})
		if svc.is_empty():
			continue
		var healthy: Array = []
		for member in svc.get("members", []):
			if Sim.ping(d, String(member))["ok"]:
				healthy.append(member)
		var was: Array = svc.get("healthy", [])
		if JSON.stringify(was) != JSON.stringify(healthy):
			device_log(d, "pool for %s now has %d healthy member(s) of %d"
				% [svc.get("vip", "?"), healthy.size(), svc.get("members", []).size()])
		svc["healthy"] = healthy

func _run_monitors() -> void:
	for m in monitors:
		var ok := monitor_ok(m)
		if ok == bool(m["failing"]):  # state changed
			m["failing"] = not ok
			if ok:
				log_event("MONITOR OK: %s" % monitor_label(m))
			else:
				log_event("MONITOR ALERT: %s is failing." % monitor_label(m))

func monitor_label(m: Dictionary) -> String:
	if m["kind"] == "ping":
		return "%s can reach %s" % [m["from"], m["target"]]
	return "link %s is up" % m["target"]

func refresh_candidates(force := false) -> void:
	if not candidates.is_empty() and not force:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	candidates = []
	for i in 3:
		candidates.append(Staff.make_candidate(rng))

func hire(candidate: Dictionary) -> String:
	if money < int(candidate["salary"]):
		return "you cannot cover even one cycle of their salary"
	candidates.erase(candidate)
	candidate["hired_cycle"] = cycle
	staff.append(candidate)
	log_event("HIRED: %s as %s at $%d/cycle." % [candidate["name"], Staff.label(candidate),
		int(candidate["salary"])])
	money_changed.emit()
	return ""

func fire(member: Dictionary) -> void:
	staff.erase(member)
	reputation = maxi(0, reputation - 1)
	log_event("LET GO: %s has left the company." % member["name"])
	money_changed.emit()

func market_estimate(offer: Dictionary) -> Array:
	## what rivals would likely charge: [low, high], or [] while you are blind
	if market_intel < 1:
		return []
	var rival := Rivals.best_bidder(offer)
	if rival.is_empty():
		return []
	var bid: float = float(Rivals.bid_for(rival, offer))
	var spread: float = clampf(0.35 - 0.04 * float(market_intel), 0.06, 0.35)
	if reputation >= 70:
		spread *= 0.75  # people talk to a supplier they trust
	return [int(bid * (1.0 - spread)), int(bid * (1.0 + spread))]

func buy_rival(r: Dictionary) -> String:
	## acquire a competitor: their book of business and their hardware
	if not Rivals.alive(r):
		return "already yours"
	var price := Rivals.asking_price(r)
	if money < price:
		return "you cannot afford %s ($%d)" % [r["name"], price]
	var target_site := current_site
	var free_tiles: Array = []
	if Rivals.has_site(r):
		# they own premises: you buy the building and everything in it
		var sg: Array = r["site"]["grid"]
		target_site = add_site(r["site"]["name"], Vector2i(int(sg[0]), int(sg[1])), r["site"]["kind"])
		free_tiles = _free_tiles(target_site)
	else:
		free_tiles = _free_tiles()
		if free_tiles.size() < Rivals.racks_needed(r):
			return "no floor space: %s runs from %d rack(s) that must move into your room, and you have %d free tile(s). Expand first." % [
				r["name"], Rivals.racks_needed(r), free_tiles.size()]
	money -= price
	r["bought"] = true
	var idx := 0
	var host_ips: Array = []
	var their_net: String = r.get("net", "10.0.0")
	var their_vlan: int = int(r.get("vlan", 1))
	for rack_models in r["racks"]:
		var rack := add_rack(free_tiles[idx], target_site)
		idx += 1
		var slot := 0
		var rack_switch: Net.NDevice = null
		for model in rack_models:
			var dev := new_device(model)
			dev.acquired_from = r["name"]
			rack.slots[slot] = dev
			slot += 1
			# wire and address it exactly as they ran it: their vlan, their subnet
			if dev.type == "switch":
				rack_switch = dev
				if their_vlan != 1:
					add_vlan(dev, their_vlan, "%s-core" % String(r["name"]).split(" ")[0].to_lower())
					for i: Net.Iface in dev.ifaces:
						if i.mode == "access":
							i.untagged_vlan = their_vlan
			elif rack_switch != null:
				var free_port: Net.Iface = null
				for i: Net.Iface in rack_switch.ifaces:
					if link_at(i) == null and not i.name.begins_with("Management"):
						free_port = i
						break
				if free_port and not dev.ifaces.is_empty():
					connect_ifaces(dev.ifaces[0], free_port)
				if dev.type == "server":
					# low host numbers: exactly the addresses a player is likely
					# to have used already, which is the point of the exercise
					var ip := "%s.%d" % [their_net, 1 + host_ips.size()]
					add_ip(dev.ifaces[0], ip + "/24")
					host_ips.append(ip)
				elif dev.type in ["router", "firewall"]:
					add_ip(dev.ifaces[0], "%s.254/24" % their_net)
		if rack_switch:
			rack_switch.startup = device_config(rack_switch)  # their gear was saved
	acquisitions.append({"rival": r["name"], "net": their_net, "vlan": their_vlan,
		"hosts": host_ips, "site": target_site, "done": false,
		"premises": Rivals.has_site(r)})
	for i in int(r["deals"]):  # inherited customers, hosted on their kit
		var served: String = host_ips[i % host_ips.size()] if not host_ips.is_empty() else ""
		deals.append({"id": "acq_%s_%d" % [r["name"], i], "customer": "%s customer %d" % [r["name"], i + 1],
			"kind": "hosting", "params": {"ip": served}, "fee": 90, "load": 150,
			"brief": "Inherited from %s: their server at %s must stay reachable." % [r["name"], served],
			"healthy": true, "acquired": true})
	reputation = mini(100, reputation + 5)
	if Rivals.has_site(r):
		log_event("ACQUISITION: you bought %s for $%d, including their site '%s' with %d racks and %d contracts."
			% [r["name"], price, r["site"]["name"], Rivals.racks_needed(r), int(r["deals"])])
	else:
		log_event("ACQUISITION: you bought %s for $%d and moved their %d rack(s) into your room, with %d contracts."
			% [r["name"], price, Rivals.racks_needed(r), int(r["deals"])])
	money_changed.emit()
	topology_changed.emit()
	return ""

func integration_status(a: Dictionary) -> Array:
	## live checks for a post-acquisition integration job
	var name: String = a["rival"]
	var theirs: Array = []
	var yours: Array = []
	for d in all_devices():
		if d.acquired_from == name:
			theirs.append(d)
		elif d.acquired_from == "":
			yours.append(d)
	var linked := false
	for l in links:
		var a_theirs: bool = l.a.dev.acquired_from == name
		var b_theirs: bool = l.b.dev.acquired_from == name
		if a_theirs != b_theirs:
			linked = true
			break
	var reachable := false
	for td in theirs:
		if td.type != "server":
			continue
		for ip in a["hosts"]:
			for yd in yours:
				if yd.type == "server" and Sim.ping(yd, ip)["ok"]:
					reachable = true
	var duplicates: Array = []
	var seen := {}
	for d in all_devices():
		for i: Net.Iface in d.ifaces:
			for cidr: String in i.ips:
				var ip: String = cidr.split("/")[0]
				if seen.has(ip) and seen[ip] != d:
					duplicates.append(ip)
				seen[ip] = d
	var unsaved := 0
	for td in theirs:
		if config_dirty(td):
			unsaved += 1
	return [
		{"d": "Their network is cabled to yours", "ok": linked},
		{"d": "No duplicate addresses across the merged estate", "ok": duplicates.is_empty(),
			"detail": "" if duplicates.is_empty() else "clashing: " + ", ".join(PackedStringArray(duplicates))},
		{"d": "Inherited customers reachable from your side", "ok": reachable},
		{"d": "Their gear has its configuration saved", "ok": unsaved == 0},
	]

func try_complete_integration(a: Dictionary) -> bool:
	if bool(a.get("done", false)):
		return false
	for req in integration_status(a):
		if not bool(req["ok"]):
			return false
	a["done"] = true
	var bonus := 1500
	money += bonus
	reputation = mini(100, reputation + 5)
	stats["earned"] = int(stats.get("earned", 0)) + bonus
	log_event("INTEGRATION complete: %s is now part of your network (+$%d)." % [a["rival"], bonus])
	money_changed.emit()
	return true

func _free_tiles(site := -1) -> Array:
	var idx := current_site if site < 0 else site
	var out: Array = []
	var g := grid_size(idx)
	for y in g.y:
		for x in g.x:
			if rack_at(Vector2i(x, y), idx) == null:
				out.append(Vector2i(x, y))
	return out

func accept_counter(offer: Dictionary) -> void:
	_offer_to_deal(offer, int(offer["budget"]))

func dismiss_offer(offer: Dictionary) -> void:
	offers.erase(offer)

func _offer_to_deal(offer: Dictionary, fee: int) -> void:
	offers.erase(offer)
	stats["deals"] += 1
	deals.append({"id": offer["id"], "customer": offer["customer"], "kind": offer["kind"],
		"params": offer["params"], "fee": fee, "brief": offer["brief"],
		"term": 14 + randi() % 10,  # how long before it comes up for renewal
		"budget": int(offer.get("budget", fee)),  # the market reference for poaching
		"ctype": offer.get("ctype", "enterprise"), "loyalty": float(offer.get("loyalty", 0.6)),
		"load": offer.get("load", 200), "sla": int(offer.get("sla", 0)),
		"cycles": 0, "up_cycles": 0, "healthy": false})
	money_changed.emit()

func device_log(dev: Net.NDevice, text: String) -> void:
	## a device records an event locally, and ships it to a collector if it has
	## one and can reach it. An unsynchronised clock stamps it wrongly, which
	## is exactly how correlating an incident goes wrong in real life.
	var stamp := cycle + dev.clock_skew
	var line := "[cycle %d] %s: %s" % [stamp, dev.name, text]
	dev.logs.append(line)
	if dev.logs.size() > 40:
		dev.logs.pop_front()
	if dev.log_host == "":
		return
	var collector := Sim._ip_owner(dev.log_host)
	if collector == null or not collector.services.has("syslog"):
		return
	if not Sim.ping(dev, dev.log_host)["ok"]:
		return  # logs that cannot reach the collector are simply lost
	var box: Array = collector.services["syslog"]["messages"]
	box.append(line)
	if box.size() > 200:
		box.pop_front()

func clock_tick() -> void:
	## clocks drift unless disciplined by a reachable NTP server
	for d in all_devices():
		if d.ntp_server != "" and Sim.ping(d, d.ntp_server)["ok"]:
			d.clock_skew = 0
		elif randf() < 0.25:
			d.clock_skew += (1 if randf() < 0.5 else -1)

func log_event(text: String) -> void:
	events.push_front("cycle %d: %s" % [cycle, text])
	if events.size() > 20:
		events.pop_back()

func _security_sweep() -> int:
	## Customer machines (marketplace deal servers) that can reach the IP of
	## your routers/firewalls are a breach waiting to happen: once per pair.
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
					stats["incidents"] += 1
					reputation = maxi(0, reputation - 5)
					log_event("SECURITY: %s's machine %s reached %s management at %s: incident response -$100. Isolate your management plane (firewall it off from customer networks)!"
						% [deal["customer"], srv.name, d.name, mgmt_ip])
					break
			if incidents_seen.has(key):
				break
	return cost

func _renewals_tick() -> void:
	## contracts do not run forever: when the term is up the customer decides
	## whether to stay, and what they think you are worth now
	for deal in deals:
		if deal.has("renewal") or int(deal.get("cycles", 0)) < int(deal.get("term", 14)):
			continue
		var uptime := float(deal.get("up_cycles", 0)) / maxf(1.0, float(deal.get("cycles", 1)))
		var factor := 1.0
		var mood := "they are content"
		if uptime > 0.95 and reputation >= 60:
			factor = 1.1
			mood = "you have earned a rise"
		elif uptime < 0.8:
			factor = 0.75
			mood = "they want a discount for the trouble"
		var proposed := int(float(deal["fee"]) * factor)
		deal["renewal"] = {"fee": proposed, "mood": mood, "uptime": int(uptime * 100)}
		log_event("RENEWAL: %s's contract is up. They propose $%d/cycle: %s."
			% [deal["customer"], proposed, mood])

func accept_renewal(deal: Dictionary) -> void:
	var r: Dictionary = deal.get("renewal", {})
	if r.is_empty():
		return
	deal["fee"] = int(r["fee"])
	deal["cycles"] = 0
	deal["up_cycles"] = 0
	deal["term"] = 14 + randi() % 10
	deal.erase("renewal")
	log_event("RENEWED: %s stays at $%d/cycle." % [deal["customer"], int(deal["fee"])])
	money_changed.emit()

func decline_renewal(deal: Dictionary) -> void:
	deals.erase(deal)
	reputation = maxi(0, reputation - 2)
	log_event("ENDED: %s's contract was not renewed." % deal["customer"])
	money_changed.emit()

func customer_growth(deal: Dictionary) -> void:
	## a startup that survives outgrows its contract, in fee and in traffic
	if deal.get("ctype", "") != "startup" or randf() >= 0.06:
		return
	deal["fee"] = int(int(deal["fee"]) * 1.25)
	deal["load"] = int(int(deal.get("load", 200)) * 1.4)
	log_event("GROWTH: %s is scaling up: their fee rises to $%d and their traffic with it."
		% [deal["customer"], int(deal["fee"])])

const MAINTENANCE_LENGTH := 3

func in_maintenance() -> bool:
	return cycle <= maintenance_until

func declare_maintenance() -> String:
	if in_maintenance():
		return "you are already in a window"
	if maintenance_used >= 2:
		return "customers will not accept a third window this quarter"
	maintenance_until = cycle + MAINTENANCE_LENGTH
	maintenance_used += 1
	log_event("MAINTENANCE: a planned window is open for %d cycles. Downtime in it is excused."
		% MAINTENANCE_LENGTH)
	return ""

func outage_open() -> bool:
	for deal in deals:
		if not bool(deal.get("healthy", false)):
			return true
	return false

func post_status(text: String) -> String:
	if text.strip_edges() == "":
		return "say something useful"
	status_posts.push_front({"cycle": cycle, "text": text.strip_edges()})
	if status_posts.size() > 12:
		status_posts.pop_back()
	log_event("STATUS PAGE: \"%s\"" % text.strip_edges())
	return ""

func status_posted_recently() -> bool:
	for p in status_posts:
		if cycle - int(p["cycle"]) <= 2:
			return true
	return false

func buy_spare(model: String) -> String:
	if not MODELS.has(model):
		return "no such model"
	var price := int(MODELS[model]["price"]) * 3 / 4  # a shelf unit, bought cold
	if not try_spend(price):
		return "a spare %s costs $%d" % [MODELS[model]["label"], price]
	spares[model] = int(spares.get(model, 0)) + 1
	log_event("SPARES: a %s is on the shelf." % MODELS[model]["label"])
	return ""

func swap_from_spares(dev: Net.NDevice) -> String:
	## a failed device is replaced from the shelf, keeping its configuration
	if dev.status == "active":
		return "%s is running" % dev.name
	if int(spares.get(dev.model, 0)) <= 0:
		return "no spare %s on the shelf" % MODELS[dev.model]["label"]
	spares[dev.model] = int(spares[dev.model]) - 1
	dev.status = "active"
	dev.installed_cycle = cycle
	if not dev.startup.is_empty():
		apply_device_config(dev, dev.startup)
	device_log(dev, "replaced from spares")
	log_event("SPARES: %s was swapped for a shelf unit%s." % [dev.name,
		" and restored from its saved configuration" if not dev.startup.is_empty()
		else ", but it had no saved configuration"])
	topology_changed.emit()
	return ""

func record_incident(kind: String, summary: String) -> void:
	for inc in incidents:
		if inc["kind"] == kind and inc["summary"] == summary and not bool(inc.get("reviewed", false)):
			return  # one open review per ongoing problem
	incidents.push_front({"kind": kind, "summary": summary, "cycle": cycle, "reviewed": false})
	if incidents.size() > 6:
		incidents.pop_back()

const REVIEW_CAUSES := [
	"a change nobody reviewed",
	"a single point of failure we knew about",
	"capacity we never planned for",
	"a monitor that did not exist",
	"a configuration that was never saved",
]

func review_incident(inc: Dictionary, cause_idx: int) -> String:
	if bool(inc.get("reviewed", false)):
		return "that one is already written up"
	inc["reviewed"] = true
	inc["cause"] = REVIEW_CAUSES[clampi(cause_idx, 0, REVIEW_CAUSES.size() - 1)]
	reputation = mini(100, reputation + 3)
	log_event("POST-MORTEM: %s. Contributing cause recorded as %s. Customers appreciate the candour."
		% [inc["summary"], inc["cause"]])
	return ""

func device_age(d: Net.NDevice) -> int:
	return maxi(0, cycle - d.installed_cycle)

func _ageing_tick() -> void:
	## hardware does not last forever: the chance of a failure climbs with age,
	## and insurance turns an unpredictable outage into a predictable fee
	for d in all_devices():
		if d.status != "active" or d.type == "cooling":
			continue
		var age := device_age(d)
		if age < 40:
			continue
		var chance := 0.002 * float(age - 40) / 10.0
		if randf() >= minf(chance, 0.05):
			continue
		d.status = "offline"
		device_log(d, "hardware failure after %d cycles in service" % age)
		record_incident("hardware", "%s failed after %d cycles" % [d.name, age])
		var payout := 0
		if insured:
			payout = int(MODELS[d.model]["price"]) / 2
			money += payout
			money_changed.emit()
		log_event("HARDWARE: %s failed after %d cycles.%s" % [d.name, age,
			"  Insurance paid $%d towards a replacement." % payout if insured
			else "  You are not insured."])

func _attack_tick() -> void:
	## volumetric attacks: they eat bandwidth on the path to the victim until
	## they are absorbed, blackholed, or simply burn out
	for a in attacks.duplicate():
		a["cycles_left"] = int(a["cycles_left"]) - 1
		if int(a["cycles_left"]) <= 0:
			attacks.erase(a)
			log_event("ATTACK over: the flood against %s has stopped." % a["target"])
	if stage < 1 or deals.is_empty() or attacks.size() >= 2 or randf() > 0.08:
		return
	var victim: Dictionary = deals[randi() % deals.size()]
	var ip: String = victim["params"].get("ip", "")
	if ip == "" or not bool(victim.get("healthy", false)):
		return
	attacks.append({"target": ip, "customer": victim["customer"],
		"mbps": 800 + randi() % 4000, "cycles_left": 3 + randi() % 4})
	log_event("ATTACK: a flood is hitting %s (%s). Options: upstream scrubbing, a blackhole route, or ride it out."
		% [ip, victim["customer"]])

func attack_on(ip: String) -> Dictionary:
	for a in attacks:
		if a["target"] == ip:
			return a
	return {}

func attack_blackholed(a: Dictionary) -> bool:
	## someone has routed the victim to null0: the flood stops, and so does
	## the customer's service
	for d in all_devices():
		for r in d.static_routes:
			if String(r["via"]) == "null0" and Net.same_net(a["target"], r["prefix"], int(r["plen"])):
				return true
	return false

func _maybe_poach() -> void:
	## an overpriced contract with a mediocre reputation is a target
	if deals.is_empty() or randf() > 0.2:
		return
	var deal: Dictionary = deals[randi() % deals.size()]
	if bool(deal.get("acquired", false)) or not bool(deal.get("healthy", false)):
		return  # rivals poach working business, not services you already broke
	if not deal.has("budget"):
		return  # no market reference for this contract
	var rival := Rivals.best_bidder({"budget": int(deal["budget"])})
	if rival.is_empty():
		return
	var their_price := Rivals.bid_for(rival, {"budget": int(deal["budget"])})
	# only an over-market price is worth switching for, and loyalty protects you
	if their_price >= int(deal["fee"]) * 0.85 or reputation >= 70:
		return
	if randf() < float(deal.get("loyalty", 0.6)):
		return  # this customer values the relationship more than the discount
	deals.erase(deal)
	rival["deals"] = int(rival["deals"]) + 1
	reputation = maxi(0, reputation - 4)
	log_event("POACHED: %s left for %s, who offered the same service for $%d instead of your $%d."
		% [deal["customer"], rival["name"], their_price, int(deal["fee"])])

func _field_fault() -> void:
	## the on-call life: a random in-use port develops a fault
	var candidates: Array = []
	for l in links:
		for i in [l.a, l.b]:
			if i.enabled and not i.name.begins_with("Management"):
				candidates.append(i)
	if candidates.is_empty():
		return
	if randf() < 0.3:  # power blip: a device reboots and loses unsaved config
		var devs := all_devices().filter(func(d): return d.type in ["switch", "router", "firewall"])
		if not devs.is_empty():
			var rebooted: Net.NDevice = devs[randi() % devs.size()]
			var had_startup := not rebooted.startup.is_empty()
			apply_device_config(rebooted, rebooted.startup)
			device_log(rebooted, "system restarted after a power event")
			stats["faults"] += 1
			log_event("FIELD: %s rebooted after a power blip: %s" % [rebooted.name,
				"startup-config restored it." if had_startup
				else "it had NO saved config and came back blank. Use 'write memory'!"])
			return
	var victim: Net.Iface = candidates[randi() % candidates.size()]
	victim.enabled = false
	device_log(victim.dev, "%s changed state to down (link fault)" % victim.name)
	stats["faults"] += 1
	log_event("FIELD: link fault on %s %s: port went down. Find it (Map, lldp, counters) and re-enable it!"
		% [victim.dev.name, victim.name])
	topology_changed.emit()

func _qos_protect(link_load: Dictionary, deal_links: Dictionary) -> Dictionary:
	## On a congested link with QoS enabled, bandwidth is not created, it is
	## allocated: the strictest service levels are served first and whatever
	## does not fit is what degrades.
	var protected := {}
	for l in link_load:
		if int(link_load[l]) <= link_capacity(l):
			continue
		if not (l.a.qos or l.b.qos):
			continue  # no policy: everyone shares the pain equally
		var riders: Array = []
		for deal in deals:
			if l in deal_links.get(deal["id"], []):
				riders.append(deal)
		riders.sort_custom(func(x, y):
			return int(x.get("sla", 0)) > int(y.get("sla", 0)))
		var budget := link_capacity(l)
		for deal in riders:
			var need: int = int(deal.get("load", 200))
			if budget - need >= 0:
				budget -= need
				protected[deal["id"]] = true
	return protected

func _deal_path_links(deal: Dictionary) -> Array:
	## where this customer's traffic actually flows: the sim path from their
	## server toward its default gateway (good-enough stand-in for its uplink)
	var ip: String = deal["params"].get("ip", "")
	var srv := Contracts._owner(ip) if ip != "" else null
	if srv == null:
		return []
	var gw := ""
	for r in srv.static_routes:
		if int(r["plen"]) == 0:
			gw = r["via"]
	if gw == "":
		return []
	Sim.ping(srv, gw)
	var seen := {}
	for hop in Sim.last_trace:
		var l := link_at(hop["a"])
		if l:
			seen[l] = true
	return seen.keys()

func sla_tick() -> void:
	## Completed contracts pay recurring service fees: but only while
	## their requirements still hold. Break the network, lose the revenue.
	if drill_active:
		return  # the economy pauses while you run a drill
	if sandbox:
		cycle += 1  # time passes, but nothing is billed and nothing breaks
		return
	cycle += 1
	var earned := 0
	last_pl = {}
	var incidents := _security_sweep()
	if incidents != 0:
		last_pl["security incidents"] = -incidents
	earned -= incidents
	if debt > 0:
		var interest := ceili(debt * LOAN_RATE)
		last_pl["loan interest"] = -interest
		earned -= interest
	if money < 0:
		reputation = maxi(0, reputation - 2)
		log_event("BANK: you are insolvent ($%d): reputation is bleeding." % money)
	for c in circuits:
		last_pl["wan circuits"] = int(last_pl.get("wan circuits", 0)) - int(c["fee"])
		earned -= int(c["fee"])
	for s_i in sites:
		var rent := int(s_i.get("rent", 0))
		if rent > 0:
			last_pl["site rent"] = int(last_pl.get("site rent", 0)) - rent
			earned -= rent
	if stage >= 1:  # colo includes power; your own room doesn't
		var power_bill := power_draw() / 10
		last_pl["power"] = -power_bill
		earned -= power_bill
	for c in Contracts.all():
		if c["id"] not in contracts_done:
			continue
		if Contracts.retired(c["id"]):
			sla_status[c["id"]] = true  # retired: no fee, no breach
			continue
		var ok := true
		for r in c["reqs"]:
			if not r["t"].call():
				ok = false
				break
		if sla_status.get(c["id"], true) and not ok:
			log_event("SLA BREACH: '%s' (%s) is down: fees suspended." % [c["title"], c["customer"]])
		sla_status[c["id"]] = ok
		if ok:
			var fee: int = int(c["reward"]) / 10
			last_pl["service fees"] = int(last_pl.get("service fees", 0)) + fee
			earned += fee
	for d in all_devices():  # transit invoices
		for nb in d.bgp.get("neighbors", []):
			if Sim.bgp_established(d, nb):
				last_pl["transit"] = int(last_pl.get("transit", 0)) - TRANSIT_FEE
				earned -= TRANSIT_FEE
	if overheating():
		# heat kills: one active device trips per cycle until capacity recovers
		for d in all_devices():
			if d.status == "active" and d.type != "cooling":
				d.status = "offline"
				topology_changed.emit()
				break
	Rivals.tick()
	_maybe_poach()
	_attack_tick()
	if scrubbing:
		last_pl["scrubbing"] = -SCRUB_FEE
		earned -= SCRUB_FEE
	if insured:
		last_pl["insurance"] = -INSURANCE_FEE
		earned -= INSURANCE_FEE
	if marketing > 0:
		last_pl["marketing"] = -marketing
		earned -= marketing
	_ageing_tick()
	lb_health_check()
	_run_monitors()
	clock_tick()
	check_achievements()
	if not staff.is_empty():
		var wages := Staff.payroll()
		last_pl["salaries"] = -wages
		earned -= wages
		Staff.work_cycle()
	if cycle % 4 == 0:
		refresh_candidates(true)  # the job market moves
	if stage >= 2 and randf() < 0.25 * fault_scale():
		_field_fault()
	var link_load := {}
	var deal_links := {}
	for deal in deals:
		deal["healthy"] = Market.check(deal["kind"], deal["params"])
		if deal["healthy"]:
			var used := _deal_path_links(deal)
			deal_links[deal["id"]] = used
			var load: int = int(deal.get("load", 200))
			var atk := attack_on(deal["params"].get("ip", ""))
			if not atk.is_empty() and not scrubbing and not attack_blackholed(atk):
				load += int(atk["mbps"])  # the flood rides the same path
			for l in used:
				link_load[l] = link_load.get(l, 0) + load
	last_link_load = link_load
	var protected := _qos_protect(link_load, deal_links)
	_renewals_tick()
	for deal in deals.duplicate():
		# a declared maintenance window excuses planned downtime: the cycle
		# only counts against uptime if the service was actually delivered
		if not in_maintenance() or deal["healthy"]:
			deal["cycles"] = int(deal.get("cycles", 0)) + 1
		if deal["healthy"]:
			customer_growth(deal)
			deal["up_cycles"] = int(deal.get("up_cycles", 0)) + 1
		var sla := Market.tier(int(deal.get("sla", 0)))
		var uptime := float(deal.get("up_cycles", 0)) / maxf(1.0, float(deal.get("cycles", 1)))
		if float(sla["uptime"]) > 0.0 and int(deal["cycles"]) >= 4 and uptime < float(sla["uptime"]):
			var penalty := int(float(deal["fee"]) * float(sla["penalty"]))
			last_pl["SLA penalties"] = int(last_pl.get("SLA penalties", 0)) - penalty
			earned -= penalty
			reputation = maxi(0, reputation - 3)
			if not bool(deal.get("penalised", false)):
				log_event("SLA PENALTY: %s is at %d%% uptime against a %s contract: $%d charged back."
					% [deal["customer"], int(uptime * 100), sla["label"], penalty])
				record_incident("sla", "%s missed their %s service level" % [deal["customer"], sla["label"]])
			deal["penalised"] = true
		else:
			deal["penalised"] = false
		if not deal["healthy"]:
			# customers forgive an outage they were told about far more readily
			reputation = maxi(0, reputation - (2 if status_posted_recently() else 4))
			deal["degraded"] = false
			deal["missed"] = int(deal.get("missed", 0)) + 1
			var missed: int = deal["missed"]
			if missed == 3:
				log_event("%s is losing patience: deliver their service or they walk in 2 cycles."
					% deal["customer"])
			elif missed >= 5:
				deals.erase(deal)
				reputation = maxi(0, reputation - 10)
				log_event("CANCELLED: %s gave up waiting and took their business elsewhere."
					% deal["customer"])
			continue
		deal["missed"] = 0
		var congested := false
		for l in deal_links.get(deal["id"], []):
			if link_load[l] > link_capacity(l) and not protected.has(deal["id"]):
				congested = true
		if congested and not deal.get("degraded", false):
			log_event("CONGESTION: %s's traffic exceeds a link's capacity: they pay half until you add bandwidth."
				% deal["customer"])
		deal["degraded"] = congested
		if deal.has("renewal"):
			continue  # nothing is billed while the customer is deciding
		var paid: int = int(deal["fee"]) / (2 if congested else 1)
		last_pl["customer deals"] = int(last_pl.get("customer deals", 0)) + paid
		earned += paid
		reputation = mini(100, reputation + 1)
	for offer in offers.duplicate():
		if not (offer is Dictionary) or not offer.has("ttl"):
			offers.erase(offer)  # defensive: drop malformed offers
			continue
		offer["ttl"] = int(offer["ttl"]) - 1
		if offer["ttl"] <= 0:
			offers.erase(offer)
	var offer_cap := 2 + int(marketing / MARKETING_STEP)
	var offer_chance := 0.7 + 0.06 * float(marketing) / float(MARKETING_STEP)
	if offers.size() < offer_cap and contracts_done.size() >= 2 and randf() < offer_chance:
		offers.append(Market.gen_offer())  # customers show up once you have a track record
	last_cycle_delta = earned
	if earned > 0:
		stats["earned"] += earned
	if earned != 0:
		money += earned
		money_changed.emit()
	var up_deals := 0
	for deal in deals:
		if deal["healthy"]:
			up_deals += 1
	history.append({"cycle": cycle, "money": money, "net": last_cycle_delta,
		"reputation": reputation, "deals": deals.size(), "up": up_deals,
		"devices": all_devices().size()})
	if history.size() > 120:
		history.pop_front()
	if cycle % 12 == 0 and cycle > 0:
		make_report()
		maintenance_used = 0  # a new quarter, a fresh allowance
	if cycle % 5 == 0:
		save_game()

# ---------- money ----------

func try_spend(amount: int) -> bool:
	if sandbox:
		return true  # nothing costs anything in a sandbox
	if money < amount:
		return false
	money -= amount
	money_changed.emit()
	return true

func _refund(amount: int) -> void:
	money += amount
	money_changed.emit()

# ---------- racks ----------

func add_rack(tile: Vector2i, site := -1) -> Net.Rack:
	_counter["rack"] += 1
	var r := Net.Rack.new("R%d" % _counter["rack"], tile)
	r.site = current_site if site < 0 else site
	racks.append(r)
	return r

func sell_rack(r: Net.Rack) -> bool:
	for d in r.slots:
		if d != null:
			return false
	racks.erase(r)
	if r.visual:
		r.visual.queue_free()
	_refund(RACK_PRICE / 2)
	topology_changed.emit()
	return true

func rack_at(tile: Vector2i, site := -1) -> Net.Rack:
	var idx := current_site if site < 0 else site
	for r in racks:
		if r.tile == tile and r.site == idx:
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
	d.installed_cycle = cycle
	if type == "switch":
		d.vlans = {1: "default"}
	if type in ["router", "firewall", "uplink", "loadbalancer"]:
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
	if type == "ap":
		# an access point is a small bridge: one wired uplink, the rest radio
		d.ifaces[0].name = "Ethernet1"
		d.ifaces[0].mode = "trunk"
		d.vlans = {1: "default"}
		d.ssids = {}
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

func connect_ifaces(a: Net.Iface, b: Net.Iface) -> bool:
	if not can_link(a, b):
		return false  # different sites need a leased circuit first
	links.append(Net.Link.new(a, b))
	topology_changed.emit()
	return true

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
			if link_at(i) == null and i.name != "lo" and not i.name.begins_with("Vlan") \
					and not i.name.begins_with("Tunnel") and not i.name.begins_with("wg") \
					and i.parent == "" and i.vm == "":
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

func add_vrf(dev: Net.NDevice, name: String) -> bool:
	if not dev.ip_forwarding or name.strip_edges() == "" or name in dev.vrfs:
		return false
	dev.vrfs.append(name.strip_edges())
	topology_changed.emit()
	return true

func set_iface_vrf(i: Net.Iface, name: String) -> bool:
	if name != "" and name not in i.dev.vrfs:
		return false
	i.vrf = name
	i.ips = []  # moving an interface between tables clears its addresses, as it does in real life
	topology_changed.emit()
	return true

func add_static_route(dev: Net.NDevice, prefix: String, plen: int, via: String, vrf := "") -> bool:
	var v6 := Net.is_v6(prefix)
	var max_len := 128 if v6 else 32
	var blackhole := via.to_lower() in ["null0", "blackhole", "discard"]
	if not blackhole and Net.is_v6(via) != v6:
		return false
	if not blackhole and not v6 and not via.is_valid_ip_address():
		return false
	if not blackhole and v6 and Net.v6_hextets(via).is_empty():
		return false
	if plen < 0 or plen > max_len:
		return false
	if not v6 and not prefix.is_valid_ip_address():
		return false
	if v6 and Net.v6_hextets(prefix).is_empty():
		return false
	if blackhole:
		via = "null0"
	remove_static_route(dev, prefix, plen, vrf)
	dev.static_routes.append({"prefix": prefix, "plen": plen, "via": via, "vrf": vrf})
	topology_changed.emit()
	return true

func remove_static_route(dev: Net.NDevice, prefix: String, plen: int, vrf := "") -> void:
	for r in dev.static_routes.duplicate():
		if r["prefix"] == prefix and int(r["plen"]) == plen and String(r.get("vrf", "")) == vrf:
			dev.static_routes.erase(r)
	topology_changed.emit()

# ---------- save / load ----------

var drill_active := false

func snapshot() -> String:
	return JSON.stringify(_serialize())

func restore(snap: String) -> void:
	_apply(JSON.parse_string(snap))

func save_game() -> void:
	if drill_active:
		return  # never write drill state over the real save
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(_serialize(), "  "))

func _serialize() -> Dictionary:
	var devs := {}  # name -> serialized (names are unique)
	var rack_data: Array = []
	for r in racks:
		var slot_names: Array = []
		for d in r.slots:
			slot_names.append(d.name if d else null)
			if d:
				devs[d.name] = _ser_device(d)
		rack_data.append({"name": r.name, "site": r.site, "tile": [r.tile.x, r.tile.y], "slots": slot_names})
	var link_data: Array = []
	for l in links:
		link_data.append([l.a.dev.name, l.a.name, l.b.dev.name, l.b.name])
	return {"money": money, "stage": stage, "cycle": cycle,
		"reputation": reputation, "debt": debt, "stats": stats, "rivals": rivals,
		"difficulty": difficulty, "achievements": achievements,
		"market_intel": market_intel, "staff": staff, "candidates": candidates,
		"monitors": monitors, "history": history, "templates": templates, "reports": reports,
		"attacks": attacks, "scrubbing": scrubbing, "insured": insured, "marketing": marketing,
		"sandbox": sandbox, "blueprints": blueprints,
		"maintenance_until": maintenance_until, "maintenance_used": maintenance_used,
		"status_posts": status_posts, "spares": spares,
		"incidents": incidents,
		"acquisitions": acquisitions, "sites": sites, "current_site": current_site,
		"circuits": circuits,
		"events": events, "incidents_seen": incidents_seen, "counters": _counter,
		"contracts_done": contracts_done, "offers": offers, "deals": deals,
		"racks": rack_data, "devices": devs, "links": link_data}

func device_config(d: Net.NDevice) -> Dictionary:
	## the part of a device that is "configuration" (what write memory keeps)
	var cfg := _ser_device(d).duplicate(true)  # deep copy: a snapshot must not alias the live device
	cfg.erase("startup")
	cfg.erase("versions")  # history is not configuration; keeping it made every save look dirty
	return cfg

func save_blueprint(r: Net.Rack, name: String) -> String:
	name = name.strip_edges()
	if name == "":
		return "a blueprint needs a name"
	var slots: Array = []
	var any := false
	for d in r.slots:
		slots.append(d.model if d != null else null)
		if d != null:
			any = true
	if not any:
		return "there is nothing in that rack to copy"
	for b in blueprints:
		if b["name"] == name:
			blueprints.erase(b)
			break
	blueprints.append({"name": name, "slots": slots})
	log_event("BLUEPRINT: saved '%s' from rack %s." % [name, r.name])
	return ""

func blueprint_price(b: Dictionary) -> int:
	var total := 0
	for m in b["slots"]:
		if m != null:
			total += int(MODELS[String(m)]["price"])
	return total

func apply_blueprint(r: Net.Rack, b: Dictionary) -> String:
	for d in r.slots:
		if d != null:
			return "that rack is not empty"
	var price := blueprint_price(b)
	if not try_spend(price):
		return "the hardware for '%s' costs $%d and you have $%d" % [b["name"], price, money]
	for idx in mini(r.slots.size(), b["slots"].size()):
		var m = b["slots"][idx]
		if m != null:
			r.slots[idx] = new_device(String(m))
	if r.visual:
		r.visual.queue_redraw()
	log_event("BLUEPRINT: built '%s' into rack %s for $%d." % [b["name"], r.name, price])
	topology_changed.emit()
	return ""

func save_template(d: Net.NDevice, name: String) -> String:
	name = name.strip_edges()
	if name == "":
		return "a template needs a name"
	for t in templates:
		if t["name"] == name:
			templates.erase(t)
			break
	templates.append({"name": name, "type": d.type, "cfg": device_config(d)})
	log_event("TEMPLATE: saved '%s' from %s." % [name, d.name])
	return ""

func apply_template(d: Net.NDevice, t: Dictionary) -> String:
	## a golden config carries policy, not identity: VLANs, port profiles,
	## security and services, never addresses or hostnames
	if t["type"] != d.type:
		return "'%s' is a %s template and %s is a %s" % [t["name"], t["type"], d.name, d.type]
	var cfg: Dictionary = t["cfg"]
	d.vlans = {}
	for vid in cfg.get("vlans", {}):
		d.vlans[int(vid)] = cfg["vlans"][vid]
	d.acls = cfg.get("acls", []).duplicate(true)
	d.stateful = bool(cfg.get("stateful", false))
	var src_ifs: Array = cfg.get("ifaces", [])
	for idx in d.ifaces.size():
		if idx >= src_ifs.size():
			break
		var si: Dictionary = src_ifs[idx]
		var target: Net.Iface = d.ifaces[idx]
		if target.name.begins_with("Vlan") or target.parent != "":
			continue
		target.mode = si.get("mode", target.mode)
		target.untagged_vlan = int(si.get("untagged_vlan", 1))
		target.tagged_vlans = si.get("tagged_vlans", []).duplicate()
		target.mtu = int(si.get("mtu", 1500))
		target.port_security = bool(si.get("port_security", false))
		target.lag = int(si.get("lag", 0))
	topology_changed.emit()
	log_event("TEMPLATE: applied '%s' to %s." % [t["name"], d.name])
	return ""

func save_config_version(d: Net.NDevice) -> int:
	## keep a rollback point; returns the version number
	d.versions.append({"cycle": cycle, "cfg": device_config(d)})
	if d.versions.size() > 10:
		d.versions.pop_front()
	return d.versions.size()

func config_diff(old_cfg: Dictionary, new_cfg: Dictionary) -> Array:
	## human-readable differences between two device configurations
	var out: Array = []
	var old_v: Dictionary = old_cfg.get("vlans", {})
	var new_v: Dictionary = new_cfg.get("vlans", {})
	for vid in new_v:
		if not old_v.has(vid):
			out.append("+ vlan %s (%s)" % [vid, new_v[vid]])
	for vid in old_v:
		if not new_v.has(vid):
			out.append("- vlan %s (%s)" % [vid, old_v[vid]])
	var old_r := JSON.stringify(old_cfg.get("static_routes", []))
	var new_r := JSON.stringify(new_cfg.get("static_routes", []))
	if old_r != new_r:
		out.append("~ static routes changed (%d -> %d)" % [
			old_cfg.get("static_routes", []).size(), new_cfg.get("static_routes", []).size()])
	if JSON.stringify(old_cfg.get("acls", [])) != JSON.stringify(new_cfg.get("acls", [])):
		out.append("~ firewall rules changed (%d -> %d)" % [
			old_cfg.get("acls", []).size(), new_cfg.get("acls", []).size()])
	if bool(old_cfg.get("stateful", false)) != bool(new_cfg.get("stateful", false)):
		out.append("~ firewall inspection: %s -> %s" % [
			"stateful" if old_cfg.get("stateful", false) else "stateless",
			"stateful" if new_cfg.get("stateful", false) else "stateless"])
	if JSON.stringify(old_cfg.get("bgp", {})) != JSON.stringify(new_cfg.get("bgp", {})):
		out.append("~ BGP configuration changed")
	if JSON.stringify(old_cfg.get("ospf", {})) != JSON.stringify(new_cfg.get("ospf", {})):
		out.append("~ OSPF configuration changed")
	var old_if := {}
	for i in old_cfg.get("ifaces", []):
		old_if[i["name"]] = i
	for ni in new_cfg.get("ifaces", []):
		var name: String = ni["name"]
		if not old_if.has(name):
			out.append("+ interface %s" % name)
			continue
		var oi: Dictionary = old_if[name]
		for field in ["mode", "untagged_vlan", "mtu", "enabled", "nat", "lag", "helper",
				"port_security", "tagged_vlans", "ips"]:
			var a := JSON.stringify(oi.get(field, null))
			var b := JSON.stringify(ni.get(field, null))
			if a != b:
				out.append("~ interface %s: %s %s -> %s" % [name, field, a, b])
	for name in old_if:
		var still := false
		for ni in new_cfg.get("ifaces", []):
			if ni["name"] == name:
				still = true
		if not still:
			out.append("- interface %s" % name)
	return out

func apply_device_config(d: Net.NDevice, cfg: Dictionary) -> void:
	## restore a saved configuration onto a live device (reload)
	if cfg.is_empty():
		d.vlans = {1: "default"} if d.type == "switch" else {}
		d.static_routes = []
		d.acls = []
		d.bgp = {} if d.type != "uplink" else d.bgp
		d.ospf = {}
		d.services = {}
		d.resolver = ""
		for i: Net.Iface in d.ifaces:
			i.ips = []
			i.mode = "access" if d.type == "switch" and not i.name.begins_with("Management") else "routed"
			i.untagged_vlan = 1
			i.tagged_vlans = []
			i.nat = ""
			i.vrrp = {}
			i.lag = 0
			i.helper = ""
			i.enabled = true
		topology_changed.emit()
		return
	d.vlans = {}
	for vid in cfg.get("vlans", {}):
		d.vlans[int(vid)] = cfg["vlans"][vid]
	d.static_routes = cfg.get("static_routes", []).duplicate(true)
	d.acls = cfg.get("acls", []).duplicate(true)
	d.stateful = cfg.get("stateful", false)
	d.bgp = cfg.get("bgp", {}).duplicate(true)
	d.ospf = cfg.get("ospf", {}).duplicate(true)
	d.services = cfg.get("services", {}).duplicate(true)
	d.resolver = cfg.get("resolver", "")
	d.ip_forwarding = cfg.get("ip_forwarding", d.ip_forwarding)
	var saved := {}
	for si in cfg.get("ifaces", []):
		saved[si["name"]] = si
	for i: Net.Iface in d.ifaces.duplicate():
		if not saved.has(i.name):
			if i.parent != "" or i.name.begins_with("Vlan"):
				d.ifaces.erase(i)  # virtual interfaces created after the save
			continue
	for si in cfg.get("ifaces", []):
		var target: Net.Iface = null
		for i: Net.Iface in d.ifaces:
			if i.name == si["name"]:
				target = i
		if target == null:  # a virtual interface that existed when saved
			target = Net.Iface.new(d, si["name"], si["mac"])
			target.parent = si.get("parent", "")
			target.dot1q = int(si.get("dot1q", 0))
			d.ifaces.append(target)
		target.ips = si["ips"].duplicate()
		target.enabled = si["enabled"]
		target.mtu = int(si["mtu"])
		target.mode = si["mode"]
		target.untagged_vlan = int(si["untagged_vlan"])
		target.tagged_vlans = si.get("tagged_vlans", []).duplicate()
		target.nat = si.get("nat", "")
		target.vrrp = si.get("vrrp", {}).duplicate(true)
		target.lag = int(si.get("lag", 0))
		target.helper = si.get("helper", "")
	topology_changed.emit()

func _ser_device(d: Net.NDevice) -> Dictionary:
	var ifs: Array = []
	for i: Net.Iface in d.ifaces:
		ifs.append({"name": i.name, "mac": i.mac, "enabled": i.enabled, "mtu": i.mtu,
			"mode": i.mode, "untagged_vlan": i.untagged_vlan, "tagged_vlans": i.tagged_vlans,
			"nat": i.nat, "vrrp": i.vrrp, "lag": i.lag, "helper": i.helper,
			"parent": i.parent, "dot1q": i.dot1q,
			"tunnel_src": i.tunnel_src, "tunnel_dst": i.tunnel_dst,
			"wg_key": i.wg_key, "wg_peers": i.wg_peers,
			"port_security": i.port_security, "secure_mac": i.secure_mac, "vrf": i.vrf, "qos": i.qos,
			"dhcp_trusted": i.dhcp_trusted, "vm": i.vm,
			"pvlan": i.pvlan, "storm_limit": i.storm_limit, "dot1x": i.dot1x,
			"ips": i.ips})
	return {"type": d.type, "model": d.model, "name": d.name, "status": d.status, "vlans": d.vlans,
		"ip_forwarding": d.ip_forwarding, "static_routes": d.static_routes,
		"services": d.services, "resolver": d.resolver, "acls": d.acls, "stateful": d.stateful, "bgp": d.bgp,
		"ospf": d.ospf, "vrfs": d.vrfs, "snooping": d.snooping, "dai": d.dai,
		"ssids": d.ssids, "wifi": d.wifi, "radius": d.radius,
		"igmp_snooping": d.igmp_snooping, "mcast_groups": d.mcast_groups,
		"startup": d.startup, "versions": d.versions,
		"acquired_from": d.acquired_from, "installed_cycle": d.installed_cycle,
		"log_host": d.log_host, "ntp_server": d.ntp_server,
		"ifaces": ifs}

func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data == null:
		return false
	_apply(data)
	return true

func _apply(data: Dictionary) -> void:
	racks = []
	links = []
	money = int(data["money"])
	contracts_done = data.get("contracts_done", [])
	stage = int(data.get("stage", 0))
	offers = data.get("offers", [])
	cycle = int(data.get("cycle", 0))
	reputation = int(data.get("reputation", 50))
	difficulty = int(data.get("difficulty", 1))
	achievements = data.get("achievements", [])
	acquisitions = data.get("acquisitions", [])
	circuits = data.get("circuits", [])
	sites = data.get("sites", [])
	_ensure_sites()
	current_site = mini(int(data.get("current_site", 0)), sites.size() - 1)
	market_intel = int(data.get("market_intel", 0))
	maintenance_until = int(data.get("maintenance_until", -1))
	maintenance_used = int(data.get("maintenance_used", 0))
	incidents = data.get("incidents", [])
	status_posts = data.get("status_posts", [])
	spares = data.get("spares", {})
	attacks = data.get("attacks", [])
	scrubbing = bool(data.get("scrubbing", false))
	insured = bool(data.get("insured", false))
	marketing = int(data.get("marketing", 0))
	sandbox = bool(data.get("sandbox", false))
	blueprints = data.get("blueprints", [])
	templates = data.get("templates", [])
	monitors = data.get("monitors", [])
	history = data.get("history", [])
	reports = data.get("reports", [])
	staff = data.get("staff", [])
	candidates = data.get("candidates", [])
	rivals = data.get("rivals", [])
	if rivals.is_empty():
		rivals = Rivals.spawn()
	debt = int(data.get("debt", 0))
	for k in data.get("stats", {}):
		stats[k] = int(data["stats"][k])
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
		d.stateful = sd.get("stateful", false)
		d.bgp = sd.get("bgp", {})
		d.ospf = sd.get("ospf", {})
		d.vrfs = sd.get("vrfs", [])
		d.snooping = bool(sd.get("snooping", false))
		d.dai = bool(sd.get("dai", false))
		for sk in sd.get("ssids", {}):
			d.ssids[sk] = int(sd["ssids"][sk])
		d.wifi = sd.get("wifi", "")
		d.radius = sd.get("radius", "")
		d.igmp_snooping = bool(sd.get("igmp_snooping", false))
		d.mcast_groups = sd.get("mcast_groups", [])
		d.startup = sd.get("startup", {})
		d.versions = sd.get("versions", [])
		d.acquired_from = sd.get("acquired_from", "")
		d.installed_cycle = int(sd.get("installed_cycle", 0))
		d.log_host = sd.get("log_host", "")
		d.ntp_server = sd.get("ntp_server", "")
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
			i.vrrp = si.get("vrrp", {})
			i.lag = int(si.get("lag", 0))
			i.helper = si.get("helper", "")
			i.vrf = si.get("vrf", "")
			i.qos = bool(si.get("qos", false))
			i.dhcp_trusted = bool(si.get("dhcp_trusted", false))
			i.vm = si.get("vm", "")
			i.pvlan = si.get("pvlan", "")
			i.dot1x = bool(si.get("dot1x", false))
			i.storm_limit = int(si.get("storm_limit", 0))
			i.port_security = si.get("port_security", false)
			i.secure_mac = si.get("secure_mac", "")
			i.tunnel_src = si.get("tunnel_src", "")
			i.tunnel_dst = si.get("tunnel_dst", "")
			i.wg_key = si.get("wg_key", "")
			i.wg_peers = si.get("wg_peers", [])
			i.parent = si.get("parent", "")
			i.dot1q = int(si.get("dot1q", 0))
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
		r.site = int(rd.get("site", 0))
		for si in rd["slots"].size():
			if rd["slots"][si] != null:
				r.slots[si] = by_name[rd["slots"][si]]
		racks.append(r)
	for ld in data["links"]:
		var a := _find_iface(by_name[ld[0]], ld[1])
		var b := _find_iface(by_name[ld[2]], ld[3])
		if a and b:
			links.append(Net.Link.new(a, b))
	while stage < STAGES.size() - 1 and _rack_outside_grid():
		stage += 1  # grandfather old saves placed on the bigger legacy floor
		log_event("Legacy floor grandfathered: you keep the %s you already built on." % STAGES[stage]["name"])
	money_changed.emit()
	topology_changed.emit()

func _rack_outside_grid() -> bool:
	for r in racks:
		var g := grid_size(r.site)
		if r.tile.x >= g.x or r.tile.y >= g.y:
			return true
	return false

func _find_iface(dev: Net.NDevice, ifname: String) -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if i.name == ifname:
			return i
	return null
