class_name Market
## Customer marketplace: generated offers with a hidden budget, price
## negotiation, and live sim-verified delivery checks for accepted deals.

const NAMES := ["Vertex", "Kiskacsa", "Nimbus", "Turul", "BlueFin", "Paprika",
	"Quantum", "Hollo", "Solaris", "Duna", "Astra", "Fecske"]
const SUFFIX := ["Kft", "Zrt", "Ltd", "GmbH", "Bt"]

# kind -> {base budget, spread, blurb template, cost guidance}
const KINDS := {
	"hosting": {"base": 60, "spread": 60,
		"brief": "We need you to host our application server at %s/24. It must be up and reachable over the network.",
		"costs": "You'll likely need: a server (from $400) + a switchport. Power draw ~150W once you pay for power."},
	"own_vlan": {"base": 45, "spread": 50,
		"brief": "We want our own isolated network segment: VLAN %d, with our server on an access port in it.",
		"costs": "Uses a switchport + a server. Cheap to deliver if you have free capacity."},
	"dhcp_pool": {"base": 80, "spread": 70,
		"brief": "We keep plugging in machines. Run DHCP for our subnet %s.0/24 — at least one client must hold a lease.",
		"costs": "A server running dhcpd (from $400). Little extra power."},
	"secure_host": {"base": 130, "spread": 110,
		"brief": "Compliance demands it: our server at %s must sit behind a firewall that explicitly blocks outside access to it.",
		"costs": "A firewall ($800) + a server. The expensive tier — quote accordingly."},
}

static var _next_id := 0

static func gen_offer() -> Dictionary:
	var kind: String = KINDS.keys()[randi() % KINDS.size()]
	var spec: Dictionary = KINDS[kind]
	var params := {}
	var subject := ""
	match kind:
		"hosting", "secure_host":
			params["ip"] = "10.%d.%d.10" % [randi() % 180 + 20, randi() % 250]
			subject = params["ip"]
		"own_vlan":
			params["vid"] = randi() % 900 + 100
			subject = str(params["vid"])
		"dhcp_pool":
			params["subnet"] = "10.%d.%d" % [randi() % 180 + 20, randi() % 250]
			subject = params["subnet"]
	var budget: int = spec["base"] + randi() % int(spec["spread"])
	var hint := "budget-conscious"
	if budget >= spec["base"] + spec["spread"] * 2 / 3:
		hint = "deep pockets"
	elif budget >= spec["base"] + spec["spread"] / 3:
		hint = "established business"
	_next_id += 1
	return {
		"id": "mkt_%d" % _next_id,
		"kind": kind,
		"customer": "%s %s" % [NAMES[randi() % NAMES.size()], SUFFIX[randi() % SUFFIX.size()]],
		"brief": (spec["brief"] % [subject]) if subject != "" else spec["brief"],
		"costs": spec["costs"],
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
