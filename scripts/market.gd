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
	"two_rooms": {"load": 800, "base": 320, "spread": 220,
		"brief": "Our board asked what happens if your building burns down. Serve us from two rooms: %s must still answer with either one of them out of service.",
		"costs": "Two sites, kit in both, and a path between them. The most expensive thing you can sell, and the only one that survives a digger."},
	"v6_host": {"load": 350, "base": 150, "spread": 120,
		"brief": "Our clients are IPv6 only. Host our service at %s and make sure it answers there, natively: we are not interested in promises about later.",
		"costs": "A server with an IPv6 address on a segment your gateway routes. No new hardware if your addressing is in order."},
	"bonded_uplink": {"load": 700, "base": 240, "spread": 170,
		"brief": "Feed our cabinet at %s with TWO links bundled into one (LACP). We are buying the part where you pull one out and nothing happens.",
		"costs": "Two ports on each switch, two leads, and a channel-group on both ends. Premium tier."},
	"secure_host": {"load": 250, "base": 130, "spread": 110,
		"brief": "Compliance demands it: our server at %s must sit behind a firewall that explicitly blocks outside access to it.",
		"costs": "A firewall ($800) + a server. The expensive tier: quote accordingly."},
	# the second round: what the late campaign taught, sold again and again
	"site_vpn": {"load": 300, "base": 200, "spread": 150,
		"brief": "Our machine at %s must only be reached through an encrypted tunnel: a WireGuard link with a live handshake, and the address answering through it.",
		"costs": "Two routers with WireGuard interfaces and a route down the tunnel. No new hardware if both ends exist."},
	"balanced": {"load": 500, "base": 260, "spread": 180,
		"brief": "Put our service behind a load balancer at %s with at least two members. We will switch one off during the audit and expect not to notice.",
		"costs": "An Equipoise LB10 ($1200) and two servers. Premium tier."},
	"overlay_segment": {"load": 400, "base": 240, "spread": 160,
		"brief": "Carry our segment as VNI %s across two of your leaf switches over a routed underlay: no stretched VLAN, no cable between the leaves.",
		"costs": "Two L3 leaves with VXLAN and a router between them. Expensive to build, and it sells twice."},
	"v6_only": {"load": 300, "base": 170, "spread": 130,
		"brief": "Our estate is IPv6 only. Make the legacy IPv4 service at %s reachable for us: DNS64 on the resolver, NAT64 on a translator, and an IPv6-only host of ours that proves it.",
		"costs": "A translator (Junivista router or firewall), a resolver with DNS64, and a v6-only host. Mostly configuration."},
	"guest_wifi": {"load": 200, "base": 120, "spread": 100,
		"brief": "We run events. Give our guests a wireless network called %s on its own VLAN, walled off from everything of the staff's.",
		"costs": "An AirTurul AP3 ($700) trunked to a switch, and an SSID per VLAN. Cheap once the AP exists."},
}

## kinds that only come up once the campaign has taught the skill
const SECOND_ROUND := {"site_vpn": "wireguard_link", "balanced": "always_on",
	"overlay_segment": "overlay_tenant", "v6_only": "v6_only_tenant", "guest_wifi": "guest_wifi"}

const KIND_LABELS := {
	"hosting": "Server hosting",
	"public_hosting": "Public web presence",
	"own_vlan": "Private VLAN",
	"managed_switch": "Managed switch",
	"dhcp_pool": "DHCP service",
	"secure_host": "Firewalled host",
	"redundant_gw": "Redundant gateway",
	"v6_host": "IPv6 hosting",
	"two_rooms": "Served from two rooms",
	"bonded_uplink": "Bundled uplink",
	"site_vpn": "Encrypted site link",
	"balanced": "Load-balanced service",
	"overlay_segment": "Overlay segment",
	"v6_only": "IPv6-only access to legacy",
	"guest_wifi": "Guest wireless",
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
	if Game.site_count() < 2:
		kinds.erase("two_rooms")  # nobody asks for a second room you do not have
	if Game.stage < 1:
		kinds.erase("redundant_gw")  # colo customers aren't that fancy
		kinds.erase("bonded_uplink")  # and they are not paying for two of anything
	for kind2 in SECOND_ROUND:
		if String(SECOND_ROUND[kind2]) not in Game.contracts_done or Game.rank_index() < 2:
			kinds.erase(kind2)  # nobody asks a cable monkey for what you have not yet shown you can do
	var kind: String = kinds[randi() % kinds.size()]
	var spec: Dictionary = KINDS[kind]
	var params := {}
	var subject := ""
	match kind:
		"hosting", "secure_host", "public_hosting", "bonded_uplink", "two_rooms", "site_vpn", "v6_only":
			params["ip"] = "10.%d.%d.10" % [randi() % 180 + 20, randi() % 250]
			subject = params["ip"]
		"balanced":
			params["vip"] = "10.%d.%d.100" % [randi() % 180 + 20, randi() % 250]
			subject = params["vip"]
		"overlay_segment":
			params["vni"] = 10000 + randi() % 9000
			subject = str(params["vni"])
		"guest_wifi":
			params["ssid"] = "guest-%d" % (randi() % 900 + 100)
			subject = params["ssid"]
		"v6_host":
			params["ip"] = "fd%02x:%x::10" % [randi() % 256, randi() % 65535]
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

static func gen_lead(only_kinds: Array = []) -> Dictionary:
	## A lead is a rumour with a company name on it. It has no budget yet
	## because nobody has asked them what they want.
	var offer := gen_offer()
	for _try in 8:
		if only_kinds.is_empty() or String(offer["kind"]) in only_kinds:
			break
		offer = gen_offer()
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

static func identity_lead(identity: String) -> Dictionary:
	## The one piece of work that only makes sense for the company you became.
	var spec := {
		"budget": ["hosting", "Sok Kis Ugyfel Bt", "a hundred small sites nobody else will quote", 150],
		"reliability": ["redundant_gw", "Duna Bank Zrt", "they audit their suppliers and pay for it", 520],
		"green": ["hosting", "Zold Halo Kft", "they buy the tariff, not the rack", 300],
		"boutique": ["managed_switch", "Panonia Kutato", "a fabric nobody else wanted to design", 460],
	}.get(identity, ["hosting", "Valaki Kft", "somebody heard of you", 200])
	return {
		"id": "lead_identity_%s" % identity,
		"customer": String(spec[1]),
		"kind": String(spec[0]),
		"ctype": "enterprise",
		"stage": "lead",
		"heard": String(spec[2]),
		"size": int(spec[3]),
		"sla": 1,
		"params": {"ip": "10.66.10.10", "vid": 66},
		"load": int(spec[3]),
		"public": false,
		"ttl": 16,
		"identity": identity,
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

static func story_customer_lead(customer: String) -> Dictionary:
	## One of the named few, arriving as ordinary work. What they turn into
	## depends entirely on how the service goes.
	var kinds: Array = ["hosting", "secure_host", "own_vlan"]
	var kind: String = kinds[absi(customer.hash()) % kinds.size()]
	return {
		"id": "lead_named_%s" % customer.to_lower().replace(" ", "_"),
		"customer": customer,
		"kind": kind,
		"ctype": "smb",
		"stage": "lead",
		"heard": "they asked around and your name came up",
		"size": 200,
		"sla": 1,
		"params": {"ip": "10.65.%d.10" % (absi(customer.hash()) % 200)},
		"load": 190,
		"public": false,
		"ttl": 14,
		"story": true,
	}

static func story_referral_lead(from_customer: String) -> Dictionary:
	## A relationship that went well is worth a door somebody opens for you.
	return {
		"id": "lead_story_%s" % from_customer.to_lower().replace(" ", "_"),
		"customer": "%s %s" % [NAMES[absi((from_customer + "ref").hash()) % NAMES.size()], SUFFIX[0]],
		"kind": "hosting",
		"ctype": "smb",
		"stage": "lead",
		"heard": "%s told them what you did for them" % from_customer,
		"size": 180,
		"sla": 1,
		"params": {"ip": "10.64.10.10"},
		"load": 170,
		"public": false,
		"ttl": 12,
		"from_story": from_customer,
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
		"site_vpn", "v6_only":
			setup = 600
			watts = 180
		"balanced", "overlay_segment":
			setup = 1600
			watts = 300
		"guest_wifi":
			setup = 900
			watts = 120
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
		"v6_host":
			# native, not "we will do it next quarter": something on the floor
			# has to answer at that address over IPv6
			return _hosted_and_reachable(String(params.get("ip", "")))
		"two_rooms":
			# the promise is survival, so prove it the only honest way: take a
			# room out of service, see if the service is still there, put it back
			if Game.site_count() < 2:
				return false
			var addr := String(params.get("ip", ""))
			if not _hosted_and_reachable(addr):
				return false
			for room in Game.site_count():
				var kit := Game.devices_on(room)
				if kit.is_empty():
					continue
				var was_status: Array = []
				for d: Net.NDevice in kit:
					was_status.append(d.status)
					d.status = "offline"
				Sim.flush_learned_state()
				var survived := _hosted_and_reachable(addr)
				for k in kit.size():
					kit[k].status = String(was_status[k])
				Sim.flush_learned_state()
				if not survived:
					return false
			return true
		"bonded_uplink":
			var host := Contracts._owner(String(params.get("ip", "")))
			if host == null or host.type != "server":
				return false
			var seen_bundles: Array = []
			for l in Game.links:
				var bundle := Game.lag_members(l)
				if bundle.size() < 2 or bundle[0] in seen_bundles:
					continue
				seen_bundles.append(bundle[0])
				var was: Array = []
				for m in bundle:
					was.append([m.a.enabled, m.b.enabled])
					m.a.enabled = false
					m.b.enabled = false
				Sim.flush_learned_state()
				# a bundle only counts if the customer is actually behind it
				var on_path := not _hosted_and_reachable(String(params.get("ip", "")))
				for k in bundle.size():
					bundle[k].a.enabled = bool(was[k][0])
					bundle[k].b.enabled = bool(was[k][1])
				Sim.flush_learned_state()
				if not on_path:
					continue
				# and it only delivers if losing one member changes nothing
				bundle[0].a.enabled = false
				bundle[0].b.enabled = false
				Sim.flush_learned_state()
				var survived := _hosted_and_reachable(String(params.get("ip", "")))
				bundle[0].a.enabled = bool(was[0][0])
				bundle[0].b.enabled = bool(was[0][1])
				Sim.flush_learned_state()
				if survived:
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
		"site_vpn":
			# the address must answer, and the path there must be a tunnel that
			# has actually completed a handshake
			return _hosted_and_reachable(String(params.get("ip", ""))) and Contracts._wg_handshaken()
		"balanced":
			var vip := String(params.get("vip", ""))
			for d in Game.all_devices():
				var svc: Dictionary = d.services.get("lb", {})
				if not svc.is_empty() and String(svc.get("vip", "")) == vip and svc.get("members", []).size() >= 2:
					return Contracts._server_pings(vip)
			return false
		"overlay_segment":
			return Contracts._overlay_underlay() and Contracts._overlay_mapped(int(params.get("vni", 0)))
		"v6_only":
			var legacy := String(params.get("ip", ""))
			if Contracts._owner(legacy) == null:
				return false
			for d in Game.all_devices():
				var n64 := Sim.nat64_of(d)
				if n64.is_empty():
					continue
				var synth := Sim.synth64(String(n64.get("prefix", "")), legacy)
				for h in Game.all_devices():
					if h.type == "server" and _v6_only(h) and Sim.ping(h, synth)["ok"]:
						return true
			return false
		"guest_wifi":
			var ssid := String(params.get("ssid", ""))
			for d in Game.all_devices():
				if d.type == "ap" and d.ssids.has(ssid):
					for other in d.ssids:
						if String(other) != ssid and int(d.ssids[other]) != int(d.ssids[ssid]):
							return true  # a second network, on a different VLAN
			return false
	return false

static func _v6_only(h: Net.NDevice) -> bool:
	var v6 := false
	for i: Net.Iface in h.ifaces:
		for cidr in i.ips:
			if Net.is_v6(cidr):
				v6 = true
			else:
				return false
	return v6

static func delivery_checks(deal: Dictionary) -> Array:
	## Turn the words in a sold promise into observable work. The guided first
	## customer is hosting; later deal kinds still receive an honest live check.
	var kind := String(deal.get("kind", ""))
	if kind != "hosting":
		var steps := _steps_for(kind, deal.get("params", {}))
		steps.append({"promise": String(deal.get("brief", "Deliver the sold service")),
			"work": "Prove the complete service against the live network",
			"ok": check(kind, deal.get("params", {}))})
		return steps
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

static func _steps_for(kind: String, params: Dictionary) -> Array:
	## The build sheet for a sold promise: what has to exist before the whole
	## thing can pass, each read off the live network rather than remembered.
	var ip := String(params.get("ip", ""))
	var owner := Contracts._owner(ip)
	var addressed := owner != null and owner.type == "server"
	match kind:
		"v6_host":
			return [{"promise": "Give them an address that is theirs",
				"work": "Address a server at %s" % ip, "ok": addressed}]
		"bonded_uplink":
			var bundled := false
			for l in Game.links:
				if Game.lag_members(l).size() >= 2:
					bundled = true
					break
			return [
				{"promise": "Put their cabinet on the network",
					"work": "Address a server at %s" % ip, "ok": addressed},
				{"promise": "Feed it twice",
					"work": "Put two links in one channel-group on both ends", "ok": bundled},
			]
		"two_rooms":
			var rooms := Game.site_count()
			var stocked := 0
			for room in rooms:
				if not Game.devices_on(room).is_empty():
					stocked += 1
			return [
				{"promise": "Host them at all",
					"work": "Address a server at %s" % ip, "ok": addressed},
				{"promise": "Have somewhere for the second copy to live",
					"work": "Operate two floors with kit on both", "ok": stocked >= 2},
			]
		"public_hosting":
			return [
				{"promise": "Host their site",
					"work": "Address a server at %s" % ip, "ok": addressed},
				{"promise": "Be on the internet at all",
					"work": "Have an upstream on the floor", "ok": _has_uplink()},
			]
		"secure_host":
			var firewalled := false
			for d in Game.all_devices():
				if d.type == "firewall":
					firewalled = true
					break
			return [
				{"promise": "Host their server",
					"work": "Address a server at %s" % ip, "ok": addressed},
				{"promise": "Put something in front of it",
					"work": "Install a firewall", "ok": firewalled},
			]
		"own_vlan", "managed_switch":
			var vid := int(params.get("vid", 0))
			var declared := false
			for d in Game.all_devices():
				if d.type == "switch" and d.vlans.has(vid):
					declared = true
					break
			return [{"promise": "Give them VLAN %d" % vid,
				"work": "Declare VLAN %d on a switch" % vid, "ok": declared}]
		"dhcp_pool":
			var serving := false
			for d in Game.all_devices():
				if not d.services.get("dhcp", {}).is_empty():
					serving = true
					break
			return [{"promise": "Hand out addresses",
				"work": "Run dhcpd for %s.0/24 on a server" % String(params.get("subnet", "?")),
				"ok": serving}]
		"redundant_gw":
			var speaking := 0
			for d in Game.all_devices():
				for i: Net.Iface in d.ifaces:
					if i.vrrp.get("vip", "") == String(params.get("vip", "")):
						speaking += 1
			return [{"promise": "Two routers, one address",
				"work": "Configure the VRRP virtual address on a second router",
				"ok": speaking >= 2}]
	return []

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
