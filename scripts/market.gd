class_name Market
## Customer marketplace: generated offers with a hidden budget, price
## negotiation, and live sim-verified delivery checks for accepted deals.

const NAMES := ["Vertex", "Kiskacsa", "Nimbus", "Turul", "BlueFin", "Paprika",
	"Quantum", "Hollo", "Solaris", "Duna", "Astra", "Fecske", "Balaton", "Mokus",
	"Northwind", "Csillag", "Ironclad", "Tisza", "Lumen", "Rakoczi", "Obsidian", "Puli"]
const SUFFIX := ["Kft", "Zrt", "Ltd", "GmbH", "Bt", "Nyrt", "e.V.", "s.r.o."]

# kind -> {base budget, spread, blurb template, cost guidance}
const KINDS := {
	"hosting": {"load": 300, "base": 60, "spread": 60,
		"brief": "We need you to host our application server at %s/24. It must be up and reachable over the network.",
		"costs": "You'll likely need: a server (from $400) + a switchport. Power draw ~150W once you pay for power."},
	"own_vlan": {"load": 150, "base": 45, "spread": 50,
		"brief": "We want our own isolated network segment: VLAN %s, with our server on an access port in it.",
		"costs": "Uses a switchport + a server. Cheap to deliver if you have free capacity."},
	"dhcp_pool": {"load": 100, "base": 80, "spread": 70,
		"brief": "We keep plugging in machines. Run DHCP for our subnet %s.0/24: at least one client must hold a lease.",
		"costs": "A server running dhcpd (from $400). Little extra power."},
	"public_hosting": {"load": 600, "base": 220, "spread": 160,
		"brief": "We want a public web presence: host our server at %s and make it reachable FROM THE INTERNET (your upstream must be able to reach it: think BGP announcement or NAT... announcement, since it must accept inbound).",
		"costs": "A server + working transit (uplink, BGP session, prefix announced). Premium tier."},
	"redundant_gw": {"load": 400, "base": 260, "spread": 180,
		"brief": "After last month's outage we demand a redundant gateway: virtual IP %s served by TWO routers (VRRP), and our server must use it as its default gateway.",
		"costs": "Two routers + VRRP config. Expensive to build, princely to rent."},
	"managed_switch": {"load": 150, "base": 110, "spread": 90,
		"brief": "We want a managed network segment: our own VLAN %s on one of your switches: and we insist the switch itself is properly managed (an addressed Management port). We audit.",
		"costs": "A switchport + VLAN + OOB management on that switch. Cheap if your house is in order."},
	"secure_host": {"load": 250, "base": 130, "spread": 110,
		"brief": "Compliance demands it: our server at %s must sit behind a firewall that explicitly blocks outside access to it.",
		"costs": "A firewall ($800) + a server. The expensive tier: quote accordingly."},
}

const KIND_LABELS := {
	"hosting": "Server hosting",
	"public_hosting": "Public web presence",
	"own_vlan": "Private VLAN",
	"managed_switch": "Managed switch",
	"dhcp_pool": "DHCP service",
	"secure_host": "Firewalled host",
	"redundant_gw": "Redundant gateway",
}

static func label_for(kind: String) -> String:
	return KIND_LABELS.get(kind, kind)

static var _next_id := 0

static func gen_offer() -> Dictionary:
	var kinds: Array = KINDS.keys()
	if not _has_uplink():
		kinds.erase("public_hosting")  # nobody asks before you have transit
	if Game.stage < 1:
		kinds.erase("redundant_gw")  # colo customers aren't that fancy
	var kind: String = kinds[randi() % kinds.size()]
	var spec: Dictionary = KINDS[kind]
	var params := {}
	var subject := ""
	match kind:
		"hosting", "secure_host", "public_hosting":
			params["ip"] = "10.%d.%d.10" % [randi() % 180 + 20, randi() % 250]
			subject = params["ip"]
		"redundant_gw":
			params["vip"] = "10.%d.%d.1" % [randi() % 180 + 20, randi() % 250]
			subject = params["vip"]
		"own_vlan", "managed_switch":
			params["vid"] = randi() % 900 + 100
			subject = str(params["vid"])
		"dhcp_pool":
			params["subnet"] = "10.%d.%d" % [randi() % 180 + 20, randi() % 250]
			subject = params["subnet"]
	var budget: int = spec["base"] + randi() % int(spec["spread"])
	budget = int(budget * (0.6 + Game.reputation / 100.0 * 0.8))  # reputation sells
	var hint := "they are watching every forint"
	if budget >= spec["base"] + spec["spread"] * 2 / 3:
		hint = "money does not seem to be their problem"
	elif budget >= spec["base"] + spec["spread"] / 3:
		hint = "an established business, they can pay fairly"
	_next_id += 1
	return {
		"id": "mkt_%d" % _next_id,
		"kind": kind,
		"customer": "%s %s" % [NAMES[randi() % NAMES.size()], SUFFIX[randi() % SUFFIX.size()]],
		"brief": (spec["brief"] % [subject]) if subject != "" else spec["brief"],
		"costs": spec["costs"] + "  Expected load ~%d Mbps." % spec.get("load", 200),
		"load": spec.get("load", 200),
		"params": params,
		"budget": budget,  # hidden from the UI until they counter
		"hint": hint,
		"state": "open",  # open | counter
		"ttl": 5,  # offers expire after this many revenue cycles
	}

## Negotiation: quote at/below budget = accepted; a bit above = counteroffer
## at their budget; too greedy = they walk.
static func negotiate(offer: Dictionary, quote: int) -> String:
	if quote <= offer["budget"]:
		return "accepted"
	if quote <= int(offer["budget"] * 1.25):
		return "counter"
	return "rejected"

## Is an accepted deal actually being delivered right now?
static func check(kind: String, params: Dictionary) -> bool:
	match kind:
		"hosting":
			return _hosted_and_reachable(params["ip"])
		"public_hosting":
			var owner := Contracts._owner(params["ip"])
			if owner == null or owner.type != "server":
				return false
			for d in Game.all_devices():
				if d.type == "uplink" and Sim.ping(d, params["ip"])["ok"]:
					return true
			return false
		"own_vlan":
			var vid: int = int(params["vid"])
			for d in Game.all_devices():
				if d.type != "switch" or not d.vlans.has(vid):
					continue
				for i: Net.Iface in d.ifaces:
					if i.mode == "access" and i.untagged_vlan == vid and Game.link_at(i) \
							and Game.link_at(i).other(i).dev.type == "server":
						return true
			return false
		"redundant_gw":
			var vip: String = params["vip"]
			var members := 0
			for d in Game.all_devices():
				if d.ip_forwarding:
					for i: Net.Iface in d.ifaces:
						if i.vrrp.get("vip", "") == vip:
							members += 1
			if members < 2:
				return false
			for d in Game.all_devices():
				if d.type == "server":
					for r in d.static_routes:
						if r["via"] == vip and Sim.ping(d, vip)["ok"]:
							return true
			return false
		"managed_switch":
			var vid2: int = int(params["vid"])
			for d in Game.all_devices():
				if d.type != "switch" or not d.vlans.has(vid2):
					continue
				var managed := false
				for i: Net.Iface in d.ifaces:
					if i.name.begins_with("Management") and not i.ips.is_empty():
						managed = true
				if not managed:
					continue
				for i: Net.Iface in d.ifaces:
					if i.mode == "access" and i.untagged_vlan == vid2 and Game.link_at(i):
						return true
			return false
		"dhcp_pool":
			for d in Game.all_devices():
				var svc: Dictionary = d.services.get("dhcp", {})
				if not svc.is_empty() and String(svc["start"]).begins_with(params["subnet"] + ".") \
						and svc["leases"].size() >= 1:
					return true
			return false
		"secure_host":
			if Contracts._owner(params["ip"]) == null:
				return false
			for d in Game.all_devices():
				if d.type == "firewall":
					for rule in d.acls:
						if rule["action"] == "deny" and rule["dst"] == params["ip"] and int(rule["dplen"]) == 32:
							return true
			return false
	return false

static func _has_uplink() -> bool:
	for d in Game.all_devices():
		if d.type == "uplink":
			return true
	return false

static func _hosted_and_reachable(ip: String) -> bool:
	var owner := Contracts._owner(ip)
	if owner == null or owner.type != "server":
		return false
	for d in Game.all_devices():
		if d == owner:
			continue
		var has_ip := false
		for i: Net.Iface in d.ifaces:
			if not i.ips.is_empty():
				has_ip = true
		if has_ip and Sim.ping(d, ip)["ok"]:
			return true
	return false
