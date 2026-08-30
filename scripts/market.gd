class_name Market
## Customer marketplace: generated offers with a hidden budget, price
## negotiation, and live sim-verified delivery checks for accepted deals.

const NAMES := ["Vertex", "Kiskacsa", "Nimbus", "Turul", "BlueFin", "Paprika",
	"Quantum", "Hollo", "Solaris", "Duna", "Astra", "Fecske", "Balaton", "Mokus",
	"Northwind", "Csillag", "Ironclad", "Tisza", "Lumen", "Rakoczi", "Obsidian", "Puli"]
const SUFFIX := ["Kft", "Zrt", "Ltd", "GmbH", "Bt", "Nyrt", "e.V.", "s.r.o."]

## Customers are not interchangeable. Type shapes what they pay, how long
## they stay, how hard they push on price and what they demand of you.
const TYPES := {
	"startup": {"label": "startup", "pay": 0.75, "loyalty": 0.3, "sla_bias": -1,
		"note": "Cheap and impatient, but they grow fast if they survive."},
	"enterprise": {"label": "enterprise", "pay": 1.35, "loyalty": 0.85, "sla_bias": 1,
		"note": "Negotiates hard, then stays for years and expects paperwork."},
	"public": {"label": "public body", "pay": 1.15, "loyalty": 0.9, "sla_bias": 1,
		"note": "Slow, procedural and demanding about isolation and records."},
	"reseller": {"label": "reseller", "pay": 0.8, "loyalty": 0.5, "sla_bias": 0,
		"note": "Thin margins in exchange for volume: they bring more work."},
}

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

## What each customer is actually doing with the service. The player is not
## keeping a Mbps figure alive, they are keeping a shop, a clinic or a shift
## on the air, and the panel should say so in those words.
const BUSINESSES := [
	{"id": "shop", "what": "a small webshop packing orders from a back room",
		"unit": "orders", "who": "shoppers",
		"live": "Checkout is accepting orders; each one prints a shipping label at the packing table.",
		"slow": "Pages crawl and shoppers press pay twice. Orders arrive in bursts.",
		"down": "Checkout cannot submit an order. The packing table is quiet.",
		"peak": "sale night"},
	{"id": "clinic", "what": "a clinic whose reception books appointments on your service",
		"unit": "bookings", "who": "patients",
		"live": "Reception is booking appointments as fast as people ring.",
		"slow": "The booking screen hangs and reception has gone back to paper.",
		"down": "Nobody can book. Reception is writing names on a pad and apologising.",
		"peak": "Monday morning rush"},
	{"id": "school", "what": "a school running its lessons and registers online",
		"unit": "lessons", "who": "pupils",
		"live": "Registers are being taken and lessons are loading in every room.",
		"slow": "Video stalls mid-lesson and teachers are improvising.",
		"down": "The lesson stopped. Thirty pupils are watching a spinner.",
		"peak": "exam morning"},
	{"id": "streaming", "what": "a small streaming service with a loyal audience",
		"unit": "streams", "who": "viewers",
		"live": "Streams are running clean and nobody is thinking about the network.",
		"slow": "Playback is rebuffering and the chat has noticed.",
		"down": "Every stream dropped at once, mid-sentence.",
		"peak": "premiere night"},
	{"id": "factory", "what": "a factory line whose scanners talk to your service",
		"unit": "pallets", "who": "operators",
		"live": "Scanners are clearing pallets and the line is moving.",
		"slow": "Scanners retry and the line is running behind the belt.",
		"down": "The line has stopped. A shift supervisor is standing by a dead terminal.",
		"peak": "shipping deadline"},
]

static func business_for(deal: Dictionary) -> Dictionary:
	## Stable per customer, so the same people recur with the same business.
	if String(deal.get("customer", "")) == "Kiskacsa Kft":
		return BUSINESSES[0]
	var key := String(deal.get("customer", "")) + String(deal.get("kind", ""))
	return BUSINESSES[absi(key.hash()) % BUSINESSES.size()]

static func label_for(kind: String) -> String:
	return KIND_LABELS.get(kind, kind)

## Service levels a customer can buy. Higher tiers pay more and punish
## downtime with an actual penalty rather than a vague reputation hit.
const SLA_TIERS := [
	{"label": "best effort", "pay": 1.0, "uptime": 0.0, "penalty": 0.0},
	{"label": "99.9% uptime", "pay": 1.45, "uptime": 0.9, "penalty": 1.5},
	{"label": "99.99% uptime", "pay": 2.1, "uptime": 0.97, "penalty": 3.0},
]

static func tier(idx: int) -> Dictionary:
	return SLA_TIERS[clampi(idx, 0, SLA_TIERS.size() - 1)]

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
	var ctype: String = TYPES.keys()[randi() % TYPES.size()]
	var ct: Dictionary = TYPES[ctype]
	var sla_idx := 0
	var roll := randi() % 100 + int(ct["sla_bias"]) * 18
	if roll > 82:
		sla_idx = 2
	elif roll > 55:
		sla_idx = 1
	var budget: int = int((spec["base"] + randi() % int(spec["spread"]))
		* float(tier(sla_idx)["pay"]) * float(ct["pay"]))
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
		"loyalty": float(ct["loyalty"]),
		"brief": (spec["brief"] % [subject]) if subject != "" else spec["brief"],
		"costs": spec["costs"] + "  Expected load ~%d Mbps." % spec.get("load", 200),
		"load": spec.get("load", 200),
		"sla": sla_idx,
		"ctype": ctype,
		"params": params,
		"budget": budget,  # hidden from the UI until they counter
		"hint": hint,
		# some customers insist on an address of their own; the rest can sit
		# behind shared translation, which costs you nothing but an explanation
		"public": kind == "public_hosting" or (ctype in ["isp", "public"] and randi() % 3 == 0),
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
# ---------- the pipeline: leads, RFPs, proposals ----------

const LEAD_QUALIFY_COST := 220  # a visit, a survey, an afternoon of somebody's time

static func gen_lead() -> Dictionary:
	## A lead is a rumour with a company name on it. It has no budget yet
	## because nobody has asked them what they want.
	var offer := gen_offer()
	return {
		"id": "lead_" + String(offer["id"]),
		"customer": offer["customer"],
		"kind": offer["kind"],
		"ctype": offer["ctype"],
		"stage": "lead",
		"heard": offer["hint"],
		"size": int(offer["budget"]),  # what it will turn out to be worth
		"sla": int(offer["sla"]),
		"params": offer["params"],
		"load": int(offer["load"]),
		"public": bool(offer.get("public", false)),
		"ttl": 6,
	}

static func guided_first_lead() -> Dictionary:
	## A stable first sales story: friendly, small enough for the starter room,
	## and recoverable while the player learns what a proposal is made of.
	return {
		"id": "lead_guided_kiskacsa",
		"customer": "Kiskacsa Kft",
		"kind": "hosting",
		"ctype": "startup",
		"stage": "lead",
		"heard": "they have a real application, little infrastructure, and need someone patient",
		"size": 118,
		"sla": 0,
		"params": {"ip": "10.42.18.10"},
		"load": 150,
		"public": false,
		"ttl": 8,
		"guided": true,
		"attempts": 0,
	}

static func kiskacsa_referral_lead() -> Dictionary:
	## A fixed premium follow-on makes trust tangible: it asks for a firewall
	## and a new protected host, not just another paragraph of praise.
	return {
		"id": "lead_story_madaras",
		"customer": "Madaras Játék Kft",
		"kind": "secure_host",
		"ctype": "enterprise",
		"stage": "lead",
		"heard": "Kiskacsa gave them your number after you kept the shop informed through its first outage",
		"size": 310,
		"sla": 1,
		"params": {"ip": "10.42.24.10"},
		"load": 260,
		"public": false,
		"ttl": 12,
		"story_referral": "kiskacsa",
	}

static func legacy_referral_lead(customer: String) -> Dictionary:
	## The customer who followed you. Small on purpose: it opens a door, it
	## does not hand over the first act of the game.
	return {
		"id": "lead_legacy_%s" % customer.to_lower().replace(" ", "_"),
		"customer": customer,
		"kind": "hosting",
		"ctype": "smb",
		"stage": "lead",
		"heard": "they were your customer at the last company and followed you here",
		"size": 90,
		"sla": 0,
		"params": {"ip": "10.60.10.10"},
		"load": 90,
		"public": false,
		"ttl": 14,
		"legacy": true,
	}

static func rival_referral_lead(from_rival: String) -> Dictionary:
	## Work a competitor could not take. An ordinary contract, arriving through
	## a person rather than the market.
	return {
		"id": "lead_rival_%s" % from_rival.to_lower().replace(" ", "_"),
		"customer": "%s (referred)" % NAMES[absi(from_rival.hash()) % NAMES.size()],
		"kind": "hosting",
		"ctype": "smb",
		"stage": "lead",
		"heard": "%s could not take the job and passed on your number" % from_rival,
		"size": 140,
		"sla": 0,
		"params": {"ip": "10.61.10.10"},
		"load": 140,
		"public": false,
		"ttl": 12,
		"from_rival": from_rival,
	}

static func tour_lead(premium: bool) -> Dictionary:
	## What a good walk round the floor is actually worth: a real job to quote.
	return {
		"id": "lead_tour_%s" % ("premium" if premium else "modest"),
		"customer": "%s %s" % [NAMES[absi("tour".hash()) % NAMES.size()],
			SUFFIX[0 if premium else 1]],
		"kind": "secure_host" if premium else "hosting",
		"ctype": "enterprise" if premium else "smb",
		"stage": "lead",
		"heard": "they walked your floor and liked what they saw",
		"size": 340 if premium else 130,
		"sla": 1 if premium else 0,
		"params": {"ip": "10.62.10.10"},
		"load": 300 if premium else 120,
		"public": false,
		"ttl": 12,
		"from_tour": true,
	}

static func audit_lead(from_customer: String) -> Dictionary:
	## Passing a review is what puts you on the list for regulated work.
	return {
		"id": "lead_audit_%s" % from_customer.to_lower().replace(" ", "_"),
		"customer": "%s %s" % [NAMES[absi(from_customer.hash()) % NAMES.size()], SUFFIX[5]],
		"kind": "secure_host",
		"ctype": "enterprise",
		"stage": "lead",
		"heard": "%s told them you passed a controls review" % from_customer,
		"size": 420,
		"sla": 2,
		"params": {"ip": "10.63.10.10"},
		"load": 380,
		"public": false,
		"ttl": 12,
		"from_audit": true,
	}

static func cost_to_serve(lead: Dictionary) -> Dictionary:
	## An honest estimate, not an oracle. It amortises unavoidable hardware over
	## the initial 18-cycle term and leaves the customer's hidden budget hidden.
	var setup := 0
	var watts := 0
	match String(lead.get("kind", "")):
		"hosting", "dhcp_pool", "own_vlan", "managed_switch":
			setup = 400
			watts = 150
		"secure_host":
			setup = 1200
			watts = 220
		"public_hosting":
			setup = 1400
			watts = 260
		"redundant_gw":
			setup = 1200
			watts = 160
	var running := 0 if Game.stage < 1 else int(ceil(float(watts) * Game.efficiency_factor() * Game.energy_rate()))
	var floor_price := int(ceil(float(setup) / 18.0)) + running
	return {"setup": setup, "running": running, "floor": floor_price, "term": 18}

static func rfp_requirements(lead: Dictionary) -> String:
	var bits: Array = []
	var t := tier(int(lead["sla"]))
	if float(t["uptime"]) > 0.0:
		bits.append("%s availability" % t["label"])
	else:
		bits.append("best effort is acceptable")
	bits.append("about %d Mbps" % int(lead["load"]))
	if bool(lead.get("public", false)):
		bits.append("a public address of their own")
	return ", ".join(PackedStringArray(bits))

static func score_proposal(lead: Dictionary, price: int, committed_sla: int,
		reputation: int, references: int) -> Dictionary:
	## An RFP is not won on price alone, which is the point of running one.
	## -> {won: bool, why: String, rival: String}
	if committed_sla < int(lead["sla"]):
		return {"won": false, "rival": "",
			"why": "you committed to less availability than they asked for"}
	var budget := int(lead["size"])
	if price > int(float(budget) * 1.25):
		return {"won": false, "rival": "", "why": "your price was well over their budget"}
	var best_rival := Rivals.best_bidder({"budget": budget, "kind": lead["kind"]})
	var rival_price := budget
	if not best_rival.is_empty():
		rival_price = Rivals.bid_for(best_rival, {"budget": budget, "kind": lead["kind"]})
	# reputation and references are worth real money in a formal evaluation
	var advantage := 1.0 + float(reputation) / 250.0 + float(references) * 0.04
	if float(price) <= float(rival_price) * advantage:
		return {"won": true, "rival": String(best_rival.get("name", "")), "why": ""}
	return {"won": false, "rival": String(best_rival.get("name", "")),
		"why": "%s came in cheaper" % best_rival.get("name", "somebody else")}

static func check(kind: String, params: Dictionary) -> bool:
	match kind:
		"hosting":
			return _hosted_and_reachable(String(params.get("ip", "")))
		"public_hosting":
			var owner := Contracts._owner(String(params.get("ip", "")))
			if owner == null or owner.type != "server":
				return false
			for d in Game.all_devices():
				if d.type == "uplink" and Sim.ping(d, String(params.get("ip", "")))["ok"]:
					return true
			return false
		"own_vlan":
			var vid: int = int(params.get("vid", 0))
			for d in Game.all_devices():
				if d.type != "switch" or not d.vlans.has(vid):
					continue
				for i: Net.Iface in d.ifaces:
					if i.mode == "access" and i.untagged_vlan == vid and Game.link_at(i) \
							and Game.link_at(i).other(i).dev.type == "server":
						return true
			return false
		"redundant_gw":
			var vip: String = String(params.get("vip", ""))
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
			var vid2: int = int(params.get("vid", 0))
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
				if not svc.is_empty() and String(svc["start"]).begins_with(String(params.get("subnet", "?")) + ".") \
						and svc["leases"].size() >= 1:
					return true
			return false
		"secure_host":
			if Contracts._owner(String(params.get("ip", ""))) == null:
				return false
			for d in Game.all_devices():
				if d.type == "firewall":
					for rule in d.acls:
						if rule["action"] == "deny" and rule["dst"] == String(params.get("ip", "")) \
								and int(rule["dplen"]) == 32:
							return true
			return false
	return false

static func delivery_checks(deal: Dictionary) -> Array:
	## Turn the words in a sold promise into observable work. The guided first
	## customer is hosting; later deal kinds still receive an honest live check.
	if String(deal.get("kind", "")) != "hosting":
		return [{"promise": String(deal.get("brief", "Deliver the sold service")),
			"work": "Prove the complete service against the live network",
			"ok": check(String(deal.get("kind", "")), deal.get("params", {}))}]
	var ip := String(deal.get("params", {}).get("ip", ""))
	var owner := Contracts._owner(ip)
	var addressed := owner != null and owner.type == "server"
	var patched := false
	if addressed:
		for iface: Net.Iface in owner.ifaces:
			var link := Game.link_at(iface)
			if iface.enabled and link != null and link.other(iface).enabled:
				patched = true
				break
	var reachable := false
	var path_capacity := 0
	if addressed:
		for source in Game.all_devices():
			if source == owner:
				continue
			var source_addressed := false
			for iface: Net.Iface in source.ifaces:
				if not iface.ips.is_empty():
					source_addressed = true
			if not source_addressed or not Sim.ping(source, ip)["ok"]:
				continue
			reachable = true
			path_capacity = 1_000_000
			for hop in Sim.last_trace:
				var path_link := Game.link_at(hop["a"])
				if path_link != null:
					path_capacity = mini(path_capacity, Game.link_capacity(path_link))
			break
	var load := int(deal.get("load", 0))
	return [
		{"promise": "Host the application at %s" % ip,
			"work": "Address a server at %s/24" % ip, "ok": addressed},
		{"promise": "Keep the application on the network",
			"work": "Patch that server into an active rack port", "ok": patched},
		{"promise": "Make the application reachable",
			"work": "Prove a ping from another addressed device", "ok": reachable},
		{"promise": "Carry about %d Mbps" % load,
			"work": "Keep at least %d Mbps free across the proven path" % load,
			"ok": reachable and path_capacity >= load},
	]

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
