extends Node
## Autoload "Game": the datacenter source of truth (racks, devices,
## interfaces, cables, per-switch VLANs, money). NetBox-style model.

signal events_changed
signal topology_changed
signal money_changed
signal customer_service_changed(customer: String, state: String, fee: int)
signal customer_cash_changed(customer: String, state: String, amount: int)
signal guided_outage_changed

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
	"con-1": {"speed": 100, "tier": 1, "type": "console", "ports": 9,
		"label": "OutOfBand C8", "price": 550,
		"blurb": "Eight serial ports and its own way in. The box you reach a device from when the device is the problem."},
	"panel-12": {"speed": 10000, "tier": 0, "type": "panel", "ports": 24, "price": 120,
		"label": "PassThru P12 patch panel",
		"blurb": "Twelve front ports wired straight through to twelve at the back. It switches nothing; it only makes cabling traceable."},
	"crac-1": {"speed": 0, "tier": 1, "type": "cooling", "ports": 0, "label": "CoolRow CRAC", "price": 600, "cools": 1500},
}
## How many rack units each model occupies. Everything not listed is 1U.
const HEIGHTS := {"sw-24": 2, "srv-2": 2, "rtr-edge": 2, "crac-1": 2, "lb-1": 2}

## Which models ship with two power supplies. Everything else has one, and a
## single-supply device is only as reliable as the feed you plugged it into.
const DUAL_PSU := ["sw-24", "srv-2", "rtr-edge", "fw-1", "lb-1"]

const WATTS := {"con-1": 15, "sw-lite": 10, "sw-8": 30, "sw-24": 80, "srv-1": 150, "srv-2": 250,
	"rtr-lite": 20, "rtr-edge": 90, "fw-1": 40, "isp-uplink": 5, "crac-1": 100, "lb-1": 120,
	"ap-1": 15}
const TRANSIT_FEE := 30  # port charge per cycle per established upstream session
## Transit is not billed on what you average, it is billed on the 95th
## percentile of what you burst to: drop the worst five percent of samples and
## pay for the highest of what is left.
const TRANSIT_PER_MBPS := 0.35
const TRANSIT_WINDOW := 20  # samples kept for the percentile
const IXP_SETUP := 3500
const IXP_PORT_FEE := 90  # per cycle, and settlement-free once you are on it
const IXP_PEER_SHARE := 0.12  # fraction of traffic each peering session takes off transit
const BASE_COOLING := 400  # watts the bare room can dissipate
const STAGES := [
	{"name": "Colo corner", "grid": Vector2i(3, 3), "price": 0,
		"blurb": "A few tiles in someone else's colo. Power included."},
	{"name": "Server room", "grid": Vector2i(7, 7), "price": 5000,
		"blurb": "Your own room: more floor, but the power bill is yours now."},
	{"name": "Datacenter floor", "grid": Vector2i(12, 12), "price": 25000,
		"blurb": "A real floor. Grow the empire."},
	{"name": "Campus hall", "grid": Vector2i(18, 18), "price": 80000,
		"blurb": "A hall built for you. Room for a fabric, and for the late campaign to happen somewhere."},
]
const TYPE_DEFAULTS := {"switch": "sw-8", "server": "srv-1", "router": "rtr-lite", "firewall": "fw-1",
	"uplink": "isp-uplink", "cooling": "crac-1", "loadbalancer": "lb-1", "ap": "ap-1",
	"console": "con-1", "panel": "panel-12"}
const TYPE_SPECS := {
	"switch": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "sw"},
	"server": {"if_prefix": "eth", "if_start": 0, "name_prefix": "srv"},
	"router": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "rtr"},
	"firewall": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "fw"},
	"uplink": {"if_prefix": "port", "if_start": 1, "name_prefix": "isp"},
	"cooling": {"if_prefix": "port", "if_start": 1, "name_prefix": "crac"},
	"loadbalancer": {"if_prefix": "Ethernet", "if_start": 1, "name_prefix": "lb"},
	"ap": {"if_prefix": "radio", "if_start": 1, "name_prefix": "ap"},
	"console": {"if_prefix": "console", "if_start": 1, "name_prefix": "con"},
	"panel": {"if_prefix": "front", "if_start": 1, "name_prefix": "pp"},
}
const DIFFICULTIES := [
	{"name": "Apprentice", "cash": 4000, "aggression": 0.75, "faults": 0.5, "cycle": 60.0,
		"prices": 0.9, "score": 0.85,
		"blurb": "More money, cheaper gear, rivals who bid high, fewer failures, a slower clock. Scores count 85%."},
	{"name": "Operator", "cash": 2000, "aggression": 1.0, "faults": 1.0, "cycle": 45.0,
		"prices": 1.0, "score": 1.0,
		"blurb": "The intended experience."},
	{"name": "On call", "cash": 1200, "aggression": 1.2, "faults": 1.8, "cycle": 32.0,
		"prices": 1.15, "score": 1.2,
		"blurb": "Thin margins, dearer gear, rivals who undercut, and things break often. Scores count 120%."},
]
const RACK_PRICE := 500
const SLOTS := 3  # named slots, plus one autosave that lives at index SLOTS
var save_path := "user://save.json"  # the original single save; imported once, then left alone
var current_slot := 0
var slot_prefix := "user://slot"
var company_name := "Packet Empire"
var demo := false  # the demo build stops after the opening arc

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
var last_customer_outage_cycle := 0
var best_outage_streak := 0
var customer_outage_active := false
var guided_outage := {}  # deterministic opening incident and its evidence timeline
var contract_debriefs := {}  # contract id -> truthful completion snapshot
var mastered_contracts: Array = []
var active_contract_debrief := {}
var feature_intros_seen: Array = []  # one-time authored handoffs for newly revealed tools
var feature_discovery_trace := {}  # counts/cycles only; never player-authored content
var customer_arcs := {}  # stable customer id -> remembered story beats and outcomes

const DISCOVERY_FEATURES := ["map", "market", "business", "log", "ops", "expand",
	"facility", "renewals", "duties", "access", "compliance", "support",
	"oncall", "handover", "failover", "second_site"]
const DISCOVERY_IGNORED_CYCLES := 6

const ACHIEVEMENTS := [
	{"id": "first_light", "name": "First light", "how": "Complete your first contract."},
	{"id": "segmented", "name": "Good fences", "how": "Run five customer VLANs on one switch."},
	{"id": "on_the_internet", "name": "On the internet", "how": "Establish a BGP session with an upstream."},
	{"id": "no_spof", "name": "No single point of failure", "how": "Run a VRRP group with two members."},
	{"id": "empire", "name": "Two roofs", "how": "Operate two or more sites."},
	{"id": "acquirer", "name": "Acquirer", "how": "Buy a competitor."},
	{"id": "disciplined", "name": "Disciplined", "how": "Have every device's configuration saved at once."},
	{"id": "employer", "name": "Employer", "how": "Put three people on the payroll."},
	{"id": "steady", "name": "Steady hands", "how": "Reach cycle 50 with reputation at 80 or better."},
	{"id": "fabric", "name": "Fabric builder", "how": "Give a router two equal-cost paths to a destination."},
	{"id": "proved_it", "name": "Proved it", "how": "Pass a failover test with no customer noticing."},
	{"id": "two_rooms", "name": "It exists somewhere else", "how": "Serve one address from two buildings."},
	{"id": "dual_stack", "name": "The address you were given", "how": "Answer a service natively over IPv6."},
	{"id": "bundled", "name": "Two of everything", "how": "Run two links in one bundle between switches."},
	{"id": "covered", "name": "Somebody is awake", "how": "Have somebody on call while nobody is on shift."},
	{"id": "overlaid", "name": "Nothing stretched", "how": "Carry a tenant between two leaves over VXLAN with EVPN."},
	{"id": "tunnelled", "name": "Nobody read it", "how": "Complete a WireGuard handshake between two routers."},
	{"id": "migrated", "name": "Still answering", "how": "Move a virtual machine to another host without changing its address."},
	{"id": "balanced", "name": "Half of it can die", "how": "Serve a virtual address from a two-member pool."},
	{"id": "translated", "name": "Both internets", "how": "Carry an IPv6-only client to an IPv4-only service through NAT64."},
	{"id": "overlapping", "name": "Same address, twice", "how": "Route a tenant in its own VRF."},
	{"id": "paired", "name": "Pull either cable", "how": "Pair two switches with MLAG."},
	{"id": "watched", "name": "Knowing it died", "how": "Bring up a BFD session on a routed link."},
	{"id": "badged", "name": "Only the badged", "how": "Authorise a machine through 802.1X."},
	{"id": "veteran", "name": "Two hundred cycles", "how": "Keep the company running to cycle 200."},
]

func _achievement_met(id: String) -> bool:
	match id:
		"first_light":
			return int(stats.get("contracts", 0)) >= 1
		"proved_it":
			return int(stats.get("failovers_passed", 0)) >= 1
		"two_rooms":
			if site_count() < 2:
				return false
			var served := {}  # address -> the sites that answer at it
			for d in all_devices():
				for i: Net.Iface in d.ifaces:
					for cidr: String in i.ips:
						var addr := String(cidr).split("/")[0]
						var at := site_of_device(d)
						var rooms: Array = served.get(addr, [])
						if at not in rooms:
							rooms.append(at)
						served[addr] = rooms
			for addr: String in served:
				if (served[addr] as Array).size() >= 2:
					return true
			return false
		"dual_stack":
			for d in all_devices():
				if d.type != "server":
					continue
				for i: Net.Iface in d.ifaces:
					for cidr: String in i.ips:
						if Net.is_v6(String(cidr)) and link_at(i) != null:
							return true
			return false
		"bundled":
			for l in links:
				if lag_members(l).size() >= 2:
					return true
			return false
		"covered":
			return oncall != "" and not staff.is_empty() and not Staff.anyone_on_shift()
		"segmented":
			for d in all_devices():
				if d.type == "switch" and d.vlans.size() >= 6:  # VLAN 1 and five of the customers'
					return true
			return false
		"overlaid":
			return Contracts._overlay_vteps().size() >= 2 and Contracts._overlay_evpn()
		"tunnelled":
			return Contracts._wg_handshaken()
		"migrated":
			return Contracts._vm_migrated()
		"balanced":
			return Contracts._lb_pool() >= 2 and Contracts._lb_healthy() >= 1
		"translated":
			for d in all_devices():
				if int(Sim.nat64_of(d).get("translated", 0)) > 0:
					return true
			return false
		"overlapping":
			for d in all_devices():
				if d.vrfs.is_empty():
					continue
				for i: Net.Iface in d.ifaces:
					if i.vrf != "" and not i.ips.is_empty():
						return true
			return false
		"paired":
			for d in all_devices():
				if d.mlag_peer != "":
					for other in all_devices():
						if other.name == d.mlag_peer and other.mlag_peer == d.name:
							return true
			return false
		"watched":
			for d in all_devices():
				for i: Net.Iface in d.ifaces:
					if i.bfd and Sim.bfd_session(i) == "up":
						return true
			return false
		"badged":
			for d in all_devices():
				for i: Net.Iface in d.ifaces:
					if i.dot1x and i.dot1x_ok != "":
						return true
			return false
		"veteran":
			return cycle >= 200
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
const LOAN_RATE := 0.015  # per revenue cycle: a bridge while invoices land, not a trap

func borrow() -> bool:
	if debt + LOAN_TRANCHE > LOAN_MAX:
		return false
	debt += LOAN_TRANCHE
	money += LOAN_TRANCHE
	log_event("BANK: borrowed $%d (debt $%d, %.1f%% interest per cycle)" % [LOAN_TRANCHE, debt, LOAN_RATE * 100.0])
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
var nemesis := ""  # the one rival who took it personally, and why
var nemesis_reason := ""
var market_intel := 0  # bids observed: the more you have seen, the tighter your estimate
var templates: Array = []  # golden configs: {name, type, cfg}
var blueprints: Array = []  # rack layouts: {name, slots: [model|null]}
var maintenance_until := -1  # cycle up to which planned work is excused
var maintenance_used := 0  # windows taken this quarter: customers notice
var incidents: Array = []  # things worth reviewing afterwards
const HABITS := ["saves", "documents", "windows", "tidy"]
const HABIT_ALPHA := 0.06  # what you did today barely moves what you are
var habits := {"saves": 0.5, "documents": 0.5, "windows": 0.5, "tidy": 0.5}
var skill_log := {}  # skill id -> {count, first_cycle, said}: what the player has demonstrated
var skill_fumbles := {}  # skill id -> how many times it went the other way
var pending_recognition: Array = []  # lines waiting for a quiet moment
var change_window := {}  # the plan, the clock, and the point of no safe return
var duties := {}  # duty id -> the name of whoever holds it
var last_digest: Array = []  # what the crew handled, skipped, or needs you for
var parts := {"patch": 40, "optic": 8, "power": 20, "blank": 12}  # the parts drawer
var parts_auto := true  # a standing order, which never spends the last of the money
const PARTS_CASH_FLOOR := 500  # the drawer is not worth going insolvent over
var cable_debt := 0  # wrong-length leads somebody improvised with
var cabling_documented := false  # cable it properly on the way in, or clean it up later
var latent_defects := {}  # model -> shelf units carrying somebody else's problem
var stockouts := {}  # model -> the cycle supply comes back
var rmas: Array = []  # dead units in transit, and what is coming back
var crates: Array = []  # what the courier left in the receiving area
var packaging := 0  # cardboard and pallet wrap nobody has taken out yet
var oncall := ""         # who is carrying the phone this rota, if anyone
var oncall_since := -1   # the cycle they picked it up, so a long stint can tell
var callout_who := ""    # who was phoned out of hours, if anyone
var callout_until := -1  # the last cycle they are counted as being on the floor
var remote_jobs: Array = []  # somebody else's hands, doing exactly what you wrote
var lockout_state := {}  # device name -> was it unreachable last cycle
var grey_faults := {}  # "device|iface" -> {kind, since}: up, and lying
var calls: Array = []  # customers on the phone, waiting for an answer
var tickets: Array = []  # what customers say, which is not what is wrong
var _ticket_seq := 0
var confirm_commits := {}  # device name -> {cfg, due}: revert unless somebody confirms
var physical_access := {}  # device name -> cycle until somebody is standing at it
var docs := {}  # device name -> what the documentation claims is racked and patched
var orphan_intel := {}  # orphan key -> how much digging the player has done (0-2)
var tac_cases: Array = []  # vendor support cases and how far each one has got
var firmware_bugs := {}  # device name -> a fault no configuration of yours will fix
var renewals: Array = []  # dated obligations: domains, allocations, support, licences
var identity := ""  # the kind of company this is, chosen once the basics are learned
var access_policy := "open"  # open | badges | escorted: convenience against control
var access_log: Array = []  # who approached what, and whether anybody could tell
var cameras := false
var visitors: Array = []  # contractors on the floor right now
var hazards: Array = []  # fire, smoke and water, with a place and a clock
var protection := {}  # kind -> {installed, serviced_cycle}: what is fitted, and how fresh it is
var decisions: Array = []  # decisions waiting on the player, oldest first
var consequences: Array = []  # what a past decision will do, and when
var decisions_seen: Array = []
var decision_notes: Array = []  # what past decisions turned into, in order
var audit := {}  # a scoped compliance audit: offered, accepted, findings, closed
var control_evidence := {}  # control id -> the cycle it last passed
var trust_marker := false  # the customers who ask for this can see it
var tour := {}  # a scheduled visit: who is coming, and when
var facility := {}  # task id -> the cycle it was last done
var facility_auto := {}  # task id -> the crew keeps it on schedule
var heat_wave_until := -1  # the weather does not care how busy you are
var destruction_certs: Array = []  # proof a disk was wiped before it left
var data_risks: Array = []  # drives that left with their data on them
var upstream := {}  # a live fault that is somebody else's to fix
var last_upstream_cycle := -999
const UPSTREAM_GAP := 60  # rare by design: this is spice, not a staple
var blame_fear := 0  # how unsafe the team feels about owning up (0-5)
var pending_reports: Array = []  # slips nobody has mentioned yet
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
var quarter_goals: Array = []  # what the board asked for this quarter: [{id, label, target, reward, base, done}]
var board_targets := true  # the suite switches the board off where it measures money exactly

# ---------- quarterly targets: a goal source that never runs out ----------
## The campaign ends; the board does not. Every quarter it picks three
## measurable things from this pool, scaled to the company, and pays for them.
const QUARTER_GOAL_POOL := [
	{"id": "uptime", "label": "Deliver at least %d%% of customer-cycles this quarter", "reward": 600},
	{"id": "new_customers", "label": "Sign %d new customer(s)", "reward": 500},
	{"id": "reviews", "label": "Close the quarter with every incident written up", "reward": 400},
	{"id": "failover", "label": "Pass a booked failover test", "reward": 700},
	{"id": "tidy", "label": "Have the floor at least %d%% kept at quarter end", "reward": 300},
	{"id": "docs", "label": "Keep documentation drift under %d%% at quarter end", "reward": 300},
	{"id": "streak", "label": "Reach a clean streak of %d cycles", "reward": 500},
	{"id": "handover", "label": "Read %d shift handover(s)", "reward": 250},
	{"id": "saved", "label": "Close the quarter with every configuration saved", "reward": 350},
	# engineering targets: the board has read the trade press
	{"id": "bundled_trunks", "label": "Have every switch-to-switch link in a bundle at quarter end", "reward": 600},
	{"id": "bfd_links", "label": "Run BFD on every routed link at quarter end", "reward": 500},
	{"id": "guarded_ports", "label": "Guard every customer port (port security or a protected port)", "reward": 450},
	{"id": "strict", "label": "Sign %d customer(s) on the strict service tier", "reward": 650},
]

func roll_quarter_goals() -> void:
	## three targets, picked with a roll of their own seeded from the quarter,
	## so a save replays the same and nothing else's randomness moves
	var pool := QUARTER_GOAL_POOL.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s-%d" % [company_name, cycle / 12])
	quarter_goals = []
	while quarter_goals.size() < 3 and not pool.is_empty():
		var pick: Dictionary = pool[rng.randi() % pool.size()]
		pool.erase(pick)
		if String(pick["id"]) == "failover" and site_count() < 2 and staff.is_empty():
			continue  # nothing to prove yet
		var g := {"id": pick["id"], "reward": int(pick["reward"]), "done": false, "target": 0, "base": 0}
		match String(pick["id"]):
			"uptime":
				g["target"] = 97 if deals.size() < 4 else 99
			"new_customers":
				g["target"] = 1 if deals.size() < 4 else 2
				g["base"] = int(stats.get("deals", 0))
			"tidy":
				g["target"] = 70
			"docs":
				g["target"] = 30
			"streak":
				g["target"] = 12 if best_streak() < 12 else 24
			"handover":
				g["target"] = 2
				g["base"] = int(stats.get("handovers_read", 0))
			"failover":
				g["base"] = int(stats.get("failovers_passed", 0))
			"bundled_trunks":
				if _switch_links().is_empty():
					continue  # nothing to bundle yet
			"bfd_links":
				if _routed_links().is_empty():
					continue
			"guarded_ports":
				if _customer_ports().is_empty():
					continue
			"strict":
				g["target"] = 1
				g["base"] = _strict_deals()
		g["label"] = String(pick["label"]) % int(g["target"]) if "%d" in String(pick["label"]) else String(pick["label"])
		quarter_goals.append(g)

func quarter_goal_progress(g: Dictionary) -> Dictionary:
	## -> {met: bool, text: String}: measured live, so the panel can be watched
	match String(g["id"]):
		"uptime":
			var window: Array = history.slice(maxi(0, history.size() - (cycle % 12 if cycle % 12 > 0 else 12)))
			var up := 0
			var dc := 0
			for h in window:
				up += int(h.get("up", 0))
				dc += int(h.get("deals", 0))
			var pct := int(100.0 * float(up) / maxf(1.0, float(dc))) if dc > 0 else 100
			return {"met": pct >= int(g["target"]), "text": "%d%% so far" % pct}
		"new_customers":
			var n := int(stats.get("deals", 0)) - int(g["base"])
			return {"met": n >= int(g["target"]), "text": "%d of %d" % [n, int(g["target"])]}
		"reviews":
			var open_n := 0
			for inc: Dictionary in incidents:
				if not bool(inc.get("reviewed", false)):
					open_n += 1
			return {"met": open_n == 0, "text": "%d open" % open_n}
		"failover":
			var n := int(stats.get("failovers_passed", 0)) - int(g["base"])
			return {"met": n >= 1, "text": "passed" if n >= 1 else "not yet"}
		"tidy":
			var pct := int(floor_tidiness() * 100.0)
			return {"met": pct >= int(g["target"]), "text": "%d%% now" % pct}
		"docs":
			var pct := int(drift_factor() * 100.0)
			return {"met": pct < int(g["target"]), "text": "%d%% drift now" % pct}
		"streak":
			var s := cycles_since_customer_outage()
			return {"met": s >= int(g["target"]), "text": "%d cycles" % s}
		"handover":
			var n := int(stats.get("handovers_read", 0)) - int(g["base"])
			return {"met": n >= int(g["target"]), "text": "%d of %d" % [n, int(g["target"])]}
		"saved":
			var dirty := 0
			for d in all_devices():
				if config_dirty(d):
					dirty += 1
			return {"met": dirty == 0, "text": "%d unsaved" % dirty}
		"bundled_trunks":
			var sw_links := _switch_links()
			var bundled := 0
			for l in sw_links:
				if lag_members(l).size() >= 2:
					bundled += 1
			return {"met": not sw_links.is_empty() and bundled == sw_links.size(),
				"text": "%d of %d bundled" % [bundled, sw_links.size()]}
		"bfd_links":
			var routed := _routed_links()
			var watched := 0
			for l in routed:
				if l.a.bfd and l.b.bfd:
					watched += 1
			return {"met": not routed.is_empty() and watched == routed.size(),
				"text": "%d of %d watched" % [watched, routed.size()]}
		"guarded_ports":
			var ports := _customer_ports()
			var guarded := 0
			for i: Net.Iface in ports:
				if i.port_security or i.pvlan != "" or i.dot1x:
					guarded += 1
			return {"met": not ports.is_empty() and guarded == ports.size(),
				"text": "%d of %d guarded" % [guarded, ports.size()]}
		"strict":
			var n := _strict_deals() - int(g["base"])
			return {"met": n >= int(g["target"]), "text": "%d of %d" % [n, int(g["target"])]}
	return {"met": false, "text": ""}

func _switch_links() -> Array:
	var out: Array = []
	for l in links:
		if l.a.dev.type == "switch" and l.b.dev.type == "switch" and l.a.dev != l.b.dev \
				and not l.a.name.begins_with("Management") and not l.b.name.begins_with("Management"):
			out.append(l)
	return out

func _routed_links() -> Array:
	var out: Array = []
	for l in links:
		if l.a.dev.ip_forwarding and l.b.dev.ip_forwarding and l.a.dev.type != "switch" \
				and l.b.dev.type != "switch" and l.a.dev.type != "uplink" and l.b.dev.type != "uplink":
			out.append(l)
	return out

func _customer_ports() -> Array:
	## access ports with a customer's server on the other end
	var out: Array = []
	for l in links:
		for port: Net.Iface in [l.a, l.b]:
			var far: Net.Iface = l.other(port)
			if port.dev.type == "switch" and port.mode == "access" and far.dev.type == "server":
				out.append(port)
	return out

func _strict_deals() -> int:
	var n := 0
	for deal in deals:
		if int(deal.get("sla", 0)) >= 2:
			n += 1
	return n

func settle_quarter_goals() -> void:
	## the board reads the numbers at quarter end, pays, and asks again
	var met_n := 0
	var paid := 0
	for g: Dictionary in quarter_goals:
		var p := quarter_goal_progress(g)
		g["done"] = bool(p["met"])
		if g["done"]:
			met_n += 1
			paid += int(g["reward"])
	if not quarter_goals.is_empty():
		money += paid
		reputation = clampi(reputation + met_n * 2 - (quarter_goals.size() - met_n), 0, 100)
		stats["quarter_goals_met"] = int(stats.get("quarter_goals_met", 0)) + met_n
		log_event("BOARD: %d of %d quarterly targets met%s." % [met_n, quarter_goals.size(),
			", $%d in bonuses" % paid if paid > 0 else ""])
		money_changed.emit()
	roll_quarter_goals()
	if not quarter_goals.is_empty():
		var names: Array = []
		for g2: Dictionary in quarter_goals:
			names.append(String(g2["label"]))
		log_event("BOARD: this quarter's targets: %s." % "; ".join(PackedStringArray(names)))

func next_quarter_goal() -> String:
	## the first target still open, for the status line once the campaign is done
	for g: Dictionary in quarter_goals:
		if not bool(quarter_goal_progress(g)["met"]):
			return String(g["label"])
	return ""
var staff: Array = []  # people on the payroll
var candidates: Array = []  # the current hiring market
var acquisitions: Array = []  # integration jobs from companies you bought
var circuits: Array = []  # leased WAN links between sites: {a, b, mbps, fee}
var offers: Array = []  # open marketplace offers
var deals: Array = []  # accepted: {id, customer, kind, params, fee, brief, healthy}
var _counter := {"switch": 0, "server": 0, "router": 0, "firewall": 0, "uplink": 0,
	"cooling": 0, "loadbalancer": 0, "ap": 0, "console": 0, "panel": 0, "rack": 0, "mac": 0}

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

func feature_unlocked(feature: String, reveal_all := false) -> bool:
	## A control appears when the campaign has created its first meaningful
	## need. Sandbox and the experienced-player preference bypass this map.
	if reveal_all or sandbox:
		return true
	match feature:
		"jobs", "learn":
			return true
		"map":
			return "rackup" in contracts_done
		"market":
			return contracts_done.size() >= 3 or not leads.is_empty() \
				or not offers.is_empty() or not deals.is_empty()
		"business":
			if stage >= 1 or not invoices.is_empty():
				return true
			for deal: Dictionary in deals:
				if bool(deal.get("ever_healthy", false)):
					return true
			return false
		"log":
			return not guided_outage.is_empty() or not incidents.is_empty() \
				or not status_posts.is_empty()
		"ops":
			return int(stats.get("guided_delivery_complete", 0)) > 0 \
				or not guided_outage.is_empty() or stage >= 1 \
				or not monitors.is_empty() or not spares.is_empty()
		"expand":
			return "two_offices" in contracts_done or stage > 0
		"facility":
			# your own room: the building is your problem from here
			if stage < 1:
				return false
			if not hazards.is_empty():
				return true
			for task: String in FACILITY_TASKS:
				if facility_due_in(task) <= 4:
					return true
			return false
		"renewals":
			for item: Dictionary in renewals:
				if renewal_due_in(item) <= 6 or bool(item.get("lapsed", false)):
					return true
			return false
		"duties":
			return staff.size() >= 2
		"access":
			return not visitors.is_empty() or access_policy != "open" or stage >= 2
		"compliance":
			return not audit.is_empty() or trust_marker
		"support":
			return not tac_cases.is_empty() or not firmware_bugs.is_empty()
		"oncall":
			# the first time the room is empty with somebody on the payroll
			return not staff.is_empty() and not Staff.anyone_on_shift()
		"handover":
			return not handover.is_empty()
		"failover":
			return not dr_candidates().is_empty() and (stage >= 1 or deals.size() >= 2)
		"second_site":
			# the room is full, or the money is there and the customers are the
			# sort who ask what happens when a building burns down
			if site_count() > 1:
				return false
			var cap := capacity(0)
			var full := int(cap.get("slots_used", 0)) >= int(cap.get("slots", 1)) - 2
			return stage >= 1 and (full or (money > SITE_OFFERS[0]["setup"] * 2 and deals.size() >= 3))
	return false

func acknowledge_feature_intro(feature: String) -> void:
	## Unlock cards are campaign history, not a global preference: a fresh
	## company should meet its tools again, while a loaded company should not.
	if feature not in feature_intros_seen:
		feature_intros_seen.append(feature)
	observe_feature_unlock(feature)
	if not feature_discovery_trace.get("unlocked", {}).has(feature):
		return
	var acknowledged: Dictionary = feature_discovery_trace.get("acknowledged", {})
	if not acknowledged.has(feature):
		acknowledged[feature] = cycle
	feature_discovery_trace["acknowledged"] = acknowledged

func observe_feature_unlock(feature: String) -> void:
	## This trace stays deliberately coarse: tool id and campaign cycle only.
	## It must never absorb names, commands, addresses, or topology details.
	if sandbox or feature not in DISCOVERY_FEATURES or not feature_unlocked(feature):
		return
	var unlocked: Dictionary = feature_discovery_trace.get("unlocked", {})
	if not unlocked.has(feature):
		unlocked[feature] = cycle
	feature_discovery_trace["unlocked"] = unlocked
	if not feature_discovery_trace.has("acknowledged"):
		feature_discovery_trace["acknowledged"] = {}

func feature_discovery_diagnostics() -> Dictionary:
	## Local QA summary. Values are intentionally aggregate or enum-like so a
	## save can diagnose pacing without reproducing anything the player wrote.
	var unlocked_cycles: Dictionary = feature_discovery_trace.get("unlocked", {})
	var acknowledged_cycles: Dictionary = feature_discovery_trace.get("acknowledged", {})
	var unlocked: Array = []
	var acknowledged: Array = []
	var long_ignored: Array = []
	var latency_cycles := {}
	for feature: String in DISCOVERY_FEATURES:
		if unlocked_cycles.has(feature):
			unlocked.append(feature)
			if acknowledged_cycles.has(feature):
				acknowledged.append(feature)
				latency_cycles[feature] = maxi(0,
					int(acknowledged_cycles[feature]) - int(unlocked_cycles[feature]))
			elif cycle - int(unlocked_cycles[feature]) >= DISCOVERY_IGNORED_CYCLES:
				long_ignored.append(feature)
	var stall := ""
	if contracts_done.is_empty() and cycle >= 6:
		stall = "before_first_contract"
	elif contracts_done.size() < 3 and cycle >= 18:
		stall = "before_market"
	elif contracts_done.size() >= 3 and deals.is_empty() \
			and unlocked_cycles.has("market") \
			and cycle - int(unlocked_cycles["market"]) >= 18:
		stall = "before_first_customer"
	return {"cycle": cycle, "contracts_completed": contracts_done.size(),
		"unlocked": unlocked, "acknowledged": acknowledged,
		"long_ignored": long_ignored, "ack_latency_cycles": latency_cycles,
		"opening_stall": stall}

func _feature_discovery_trace_from_data(data: Dictionary) -> Dictionary:
	## Old and damaged saves both migrate to an empty trace; unlock state is
	## rediscovered from campaign milestones the next time the HUD refreshes.
	var loaded: Variant = data.get("feature_discovery_trace", {})
	return loaded if typeof(loaded) == TYPE_DICTIONARY else {}

func site_name(idx: int) -> String:
	_ensure_sites()
	if idx < 0 or idx >= sites.size():
		return "a site you no longer operate"
	return sites[idx]["name"]

func _scale_rival_aggression() -> void:
	# a rival's aggression is the multiplier on its bid: lower means it
	# undercuts you. A harder preset therefore divides, not multiplies.
	var factor := float(DIFFICULTIES[difficulty]["aggression"])
	for r in rivals:
		r["aggression"] = float(r.get("base_aggression", r["aggression"])) / factor

func price_scale() -> float:
	return float(DIFFICULTIES[difficulty].get("prices", 1.0))

func apply_difficulty(idx: int) -> void:
	difficulty = clampi(idx, 0, DIFFICULTIES.size() - 1)
	var d: Dictionary = DIFFICULTIES[difficulty]
	money = int(d["cash"])
	if cycle_timer:
		cycle_timer.wait_time = float(d["cycle"]) / maxf(1.0, float(speed))
	_scale_rival_aggression()
	money_changed.emit()

func fault_scale() -> float:
	# a budget operation runs older, cheaper hardware, and it shows
	return float(DIFFICULTIES[difficulty]["faults"]) * (1.3 if identity_is("budget") else 1.0)

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

## Carriers dig up the same streets everyone else does. Two circuits from the
## same one share the same fibre, the same duct and the same bad afternoon.
const CARRIERS := ["Danube Telecom", "Karpat Networks", "Vertex Fibre"]

const CIRCUIT_GRADES := [
	{"label": "100 Mbit metro line", "mbps": 100, "setup": 1200, "fee": 60},
	{"label": "1 Gbit leased line", "mbps": 1000, "setup": 4000, "fee": 180},
	{"label": "10 Gbit dark fibre", "mbps": 10000, "setup": 14000, "fee": 500},
]

var carrier_outage := {}  # carrier name -> cycle it expects to be back

func carrier_up(name: String) -> bool:
	return cycle >= int(carrier_outage.get(name, 0))

func circuits_between(site_a: int, site_b: int) -> Array:
	var out: Array = []
	for c in circuits:
		if (int(c["a"]) == site_a and int(c["b"]) == site_b) \
				or (int(c["a"]) == site_b and int(c["b"]) == site_a):
			out.append(c)
	return out

func circuit_between(site_a: int, site_b: int) -> Dictionary:
	## the first circuit that is actually carrying traffic right now
	var all_of_them := circuits_between(site_a, site_b)
	for c in all_of_them:
		if carrier_up(String(c.get("carrier", ""))):
			return c
	return {}

func carrier_tick() -> void:
	## somebody puts a digger through a duct now and then
	for name in CARRIERS:
		if not carrier_up(name):
			if cycle == int(carrier_outage[name]):
				log_event("CARRIER: %s is back. Circuits on them are up." % name)
			continue
		var uses := 0
		for c in circuits:
			if String(c.get("carrier", "")) == name:
				uses += 1
		if uses == 0:
			continue
		if randf() < 0.02 * DIFFICULTIES[difficulty]["faults"]:
			carrier_outage[name] = cycle + randi_range(1, 4)
			log_event("CARRIER: %s has an outage. Every circuit you buy from them is down."
				% name)
			topology_changed.emit()

func buy_circuit(site_a: int, site_b: int, grade: int, carrier := "") -> String:
	if site_a == site_b:
		return "a site does not need a circuit to itself"
	if carrier == "":
		carrier = CARRIERS[0]
	if carrier not in CARRIERS:
		return "no such carrier"
	for existing in circuits_between(site_a, site_b):
		if String(existing.get("carrier", "")) == carrier:
			return "%s already runs a circuit on that route; a second one from them shares the same fibre" % carrier
	var g: Dictionary = CIRCUIT_GRADES[grade]
	if not try_spend(int(g["setup"])):
		return "you cannot afford the $%d installation" % int(g["setup"])
	circuits.append({"a": site_a, "b": site_b, "mbps": int(g["mbps"]),
		"fee": int(g["fee"]), "label": g["label"], "carrier": carrier})
	log_event("CIRCUIT: %s from %s ordered between %s and %s ($%d/cycle)." % [g["label"],
		carrier, site_name(site_a), site_name(site_b), int(g["fee"])])
	topology_changed.emit()
	return ""

func carrier_diverse(site_a: int, site_b: int) -> bool:
	## two circuits on a route is only redundancy when they are not the same
	## company's fibre, which is the expensive lesson this exists to teach
	var seen := {}
	for c in circuits_between(site_a, site_b):
		seen[String(c.get("carrier", ""))] = true
	return seen.size() >= 2

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

const CHANGE_FREEZE_REASONS := ["a visit is booked", "a customer has a busy night coming",
	"there is an upstream outage running"]

func freeze_reason() -> String:
	## Risky work is blocked around the things that cannot be moved.
	if not tour.is_empty() and int(tour["cycle"]) - cycle <= 2:
		return CHANGE_FREEZE_REASONS[0]
	for deal in deals:
		var event := peak_event(deal)
		if not event.is_empty() and int(event["cycle"]) - cycle <= 2:
			return CHANGE_FREEZE_REASONS[1]
	if upstream_active():
		return CHANGE_FREEZE_REASONS[2]
	return ""

func change_active() -> bool:
	return not change_window.is_empty()

func submit_change(summary: String, targets: Array, duration: int, backout: bool,
		override := false) -> String:
	## The plan is the thing you are judged on afterwards, not the intention.
	if change_active():
		return "there is a window running already"
	if targets.is_empty():
		return "name what you are touching"
	var frozen := freeze_reason()
	if frozen != "" and not override:
		return "change freeze: %s" % frozen
	duration = clampi(duration, 2, 12)
	change_window = {"summary": summary, "targets": targets, "duration": duration,
		"backout": backout, "started": cycle, "rollback_at": cycle + int(duration / 2),
		"ends": cycle + duration, "pushed": false, "done": false,
		"overridden": frozen != "", "snapshots": {}}
	for name: String in targets:
		for d: Net.NDevice in all_devices():
			if d.name == name:
				save_config_version(d)
				change_window["snapshots"][name] = device_config(d)
	maintenance_until = cycle + duration
	maintenance_used += 1
	log_event("CHANGE WINDOW: \"%s\" open for %d cycles on %s. Safe rollback point at cycle %d.%s%s"
		% [summary, duration, ", ".join(PackedStringArray(targets)),
			int(change_window["rollback_at"]),
			"  No backout plan was submitted." if not backout else "",
			"  Freeze overridden: %s." % frozen if frozen != "" else ""])
	if frozen != "":
		stats["freeze_overrides"] = int(stats.get("freeze_overrides", 0)) + 1
	return ""

func change_work_done() -> bool:
	## The work counts as finished when every device you named is running the
	## configuration it is meant to keep.
	if not change_active():
		return false
	for name: String in change_window["targets"]:
		for d: Net.NDevice in all_devices():
			if d.name == name and config_dirty(d):
				return false
	return true

func complete_change() -> String:
	if not change_active():
		return "no window is running"
	if not change_work_done():
		return "something you named is still running an unsaved configuration"
	var overridden: bool = bool(change_window["overridden"])
	change_window["done"] = true
	reputation = mini(100, reputation + (3 if bool(change_window["backout"]) else 1))
	log_event("CHANGE COMPLETE: \"%s\" finished inside the window.%s"
		% [change_window["summary"],
			"  Overriding the freeze went unpunished this time." if overridden else ""])
	reconcile_after_change(change_window["targets"])
	change_window = {}
	maintenance_until = cycle
	return ""

func abort_change() -> String:
	## Back out to what was running when the window opened. A wasted night, and
	## nothing worse.
	if not change_active():
		return "no window is running"
	for name: String in change_window["snapshots"]:
		for d: Net.NDevice in all_devices():
			if d.name == name:
				apply_device_config(d, change_window["snapshots"][name])
				d.startup = device_config(d)
	log_event("ROLLED BACK: \"%s\" reverted at the rollback point. Everything is as it was, and the night is gone."
		% change_window["summary"])
	change_window = {}
	maintenance_until = cycle
	topology_changed.emit()
	return ""

func push_on_change() -> String:
	if not change_active():
		return "no window is running"
	change_window["pushed"] = true
	log_event("PUSHING ON: past the safe rollback point on \"%s\". From here it has to work."
		% change_window["summary"])
	return ""

func change_tick() -> void:
	if not change_active():
		return
	if cycle == int(change_window["rollback_at"]) and not change_work_done() \
			and not bool(change_window["pushed"]):
		log_event("ROLLBACK POINT: \"%s\" is not finished. Abort and revert, or push on past the point of safe return."
			% change_window["summary"])
	if cycle < int(change_window["ends"]):
		return
	if change_work_done():
		complete_change()
		return
	# an overrun: the excuse expires, the customers are exposed, and the people
	# who sat up all night are worse at their jobs tomorrow
	var pushed: bool = bool(change_window["pushed"])
	var overridden: bool = bool(change_window["overridden"])
	reputation = maxi(0, reputation - (6 if overridden else 3) - (2 if not bool(change_window["backout"]) else 0))
	for m in staff:
		m["morale"] = maxi(0, int(m.get("morale", 70)) - 8)
	record_incident("change", "a change window overran on %s" % change_window["summary"])
	log_event("OVERRUN: \"%s\" is still open and the window has closed. %sCustomers are exposed, the crew are wrecked, and this is on the record."
		% [change_window["summary"],
			"You pushed past the rollback point. " if pushed else ""])
	if not pushed:
		abort_change()
	else:
		change_window = {}
	maintenance_until = cycle

func maybe_window_job() -> void:
	## A job that can only be delivered inside a window, and is genuinely tight.
	for deal in deals:
		if deal.has("window_job") or not bool(deal.get("healthy", false)):
			continue
		if int(deal.get("cycles", 0)) < 10 or biz_roll() > 0.03:
			continue
		deal["window_job"] = {"fee": int(deal["fee"]) * 3, "by": cycle + 10}
		log_event("WINDOW JOB: %s will pay $%d for a change they can only take inside an agreed window, finished within 10 cycles."
			% [deal["customer"], int(deal["window_job"]["fee"])])
		return

func window_job_tick() -> void:
	for deal in deals:
		var job: Dictionary = deal.get("window_job", {})
		if job.is_empty():
			continue
		if change_active() and bool(change_window.get("done", false)):
			continue
		if cycle > int(job["by"]):
			deal.erase("window_job")
			deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - 0.1)
			log_event("WINDOW JOB MISSED: %s wanted it done inside a window and it never happened."
				% deal["customer"])

func claim_window_job(deal: Dictionary) -> String:
	## Paid only if the work really did happen inside an agreed window.
	var job: Dictionary = deal.get("window_job", {})
	if job.is_empty():
		return "they have not asked for anything"
	if not in_maintenance():
		return "that work only counts inside an agreed change window"
	if change_active() and not change_work_done():
		return "the window is open and the work is not finished"
	deal.erase("window_job")
	money += int(job["fee"])
	money_changed.emit()
	deal["loyalty"] = minf(1.0, float(deal.get("loyalty", 0.6)) + 0.1)
	log_event("WINDOW JOB DONE: %s paid $%d for work done properly, inside the window."
		% [deal["customer"], int(job["fee"])])
	return ""

const DUTIES := {
	"parts": {"label": "Keep the parts drawer stocked",
		"blurb": "Standing order for leads, optics and panels."},
	"facility": {"label": "Keep the facility schedule",
		"blurb": "Filters, service visits, load tests and battery checks."},
	"renewals": {"label": "Handle the renewals",
		"blurb": "Auto-renew everything on the calendar before it lapses."},
	"receiving": {"label": "Work the receiving area",
		"blurb": "Check crates against the order, unpack them, clear the cardboard."},
	"labels": {"label": "Label and document what changes",
		"blurb": "Tag the ports somebody patched and save what is running."},
	"housekeeping": {"label": "Walk the floor and keep it clear",
		"blurb": "Coils dressed, cardboard broken down, cups off the slab."},
}
const DUTY_CAPACITY := 2  # what one person can actually hold and still do well

func duty_holder(id: String) -> String:
	return String(duties.get(id, ""))

func duty_load(name: String) -> int:
	var held := 0
	for id: String in duties:
		if String(duties[id]) == name:
			held += 1
	return held

func assign_duty(id: String, name: String) -> String:
	if not DUTIES.has(id):
		return "there is no such duty"
	if name == "":
		duties.erase(id)
		_sync_duty_policies()
		return ""
	if Staff.by_name(name).is_empty():
		return "%s is not on the payroll" % name
	duties[id] = name
	_sync_duty_policies()
	Staff.say(Staff.by_name(name), "duty")
	if duty_load(name) > DUTY_CAPACITY:
		log_event("DUTIES: %s now holds %d standing duties. Something will be done badly."
			% [name, duty_load(name)])
	return ""

func _sync_duty_policies() -> void:
	## The board is the single place these policies live.
	parts_auto = duty_holder("parts") != ""
	for task: String in FACILITY_TASKS:
		facility_auto[task] = duty_holder("facility") != ""
	for item in renewals:
		item["auto"] = duty_holder("renewals") != ""

func do_housekeeping(name: String, good: bool) -> String:
	## A floor walk, done well or done to look done. Failure is not a penalty
	## here, it is cardboard in an aisle that somebody meets later.
	if good:
		clear_packaging()
		observe_habit("tidy", true, 1.5)
		return "%s walked the floor and cleared it" % name
	packaging += 2
	observe_habit("tidy", false)
	return "%s tidied up by stacking it in the aisle" % name

const CALLOUT_FEE := 220  # what it costs to wake somebody and get them in

func callout_ready() -> bool:
	## Only worth waking somebody for something that is actually happening.
	if staff.is_empty() or Staff.anyone_on_shift():
		return false
	if customer_outage_active or not hazards.is_empty():
		return true
	for d in all_devices():
		if d.status != "active":
			return true
	return false

const ONCALL_STINT := 12  # cycles before carrying the phone starts to tell

func oncall_stint() -> int:
	## How long the same person has been reachable without a break.
	if oncall == "" or oncall_since < 0:
		return 0
	return maxi(0, cycle - oncall_since)

func oncall_tick() -> void:
	## Nobody minds carrying the phone. Everybody minds carrying it for two
	## months, and that is how a good engineer is lost slowly.
	if oncall == "":
		return
	var who := Staff.by_name(oncall)
	if who.is_empty():
		oncall = ""
		return
	var stint := oncall_stint()
	if stint > 0 and stint % ONCALL_STINT == 0:
		who["morale"] = maxi(0, int(who.get("morale", 70)) - 4)
		log_event("ROTA: %s has been on call for %d cycles without a break. It is starting to tell."
			% [oncall, stint])

func set_oncall(name: String) -> String:
	## One person carries the phone. It is paid for, and it is why a call-out
	## at three in the morning is an arrangement rather than an imposition.
	if name == "":
		oncall = ""
		oncall_since = -1
		return ""
	if Staff.by_name(name).is_empty():
		return "nobody by that name works here"
	oncall = name
	oncall_since = cycle
	log_event("ROTA: %s is on call. The retainer is $%d a cycle." % [name, Staff.ONCALL_RETAINER])
	return ""

func call_someone_out() -> String:
	## The thing every operator does at three in the morning: phone somebody.
	## It costs money and it costs them, which is what makes thin nights a bet.
	if staff.is_empty():
		return "there is nobody to call"
	if Staff.anyone_on_shift():
		return "somebody is already on shift"
	if not callout_ready():
		return "nothing is happening that is worth waking somebody for"
	# whoever is carrying the phone expects it; anybody else is being imposed on
	var picked: Dictionary = Staff.by_name(oncall)
	var expected := not picked.is_empty()
	if not expected:
		for m in staff:
			if picked.is_empty() or int(m.get("morale", 70)) > int(picked.get("morale", 70)):
				picked = m
	var fee := CALLOUT_FEE / 2 if expected else CALLOUT_FEE
	if not spend_on("call-out", fee):
		return "a call-out costs $%d and the account will not carry it" % fee
	picked["morale"] = maxi(0, int(picked.get("morale", 70)) - (5 if expected else 12))
	picked["tired_until"] = cycle + 2  # the real cost arrives tomorrow
	callout_who = String(picked["name"])
	callout_until = cycle + 1
	log_event("CALL-OUT: %s was phoned at %s and is coming in. It cost $%d%s."
		% [callout_who, day_name(), fee,
			", which is what the retainer is for" if expected else ", and it cost them"])
	Sfx.play("phone")
	return ""

func duty_quality(id: String) -> float:
	## Skill, tiredness, how much they are carrying, and how well the place is
	## documented. Never quite as good as doing it yourself.
	var who := Staff.by_name(duty_holder(id))
	if who.is_empty():
		return 0.0
	var q := 0.35 + 0.1 * float(int(who.get("skill", 1)))
	q += 0.15 * (float(int(who.get("morale", 70))) / 100.0)
	q -= 0.15 * float(maxi(0, duty_load(String(who["name"])) - DUTY_CAPACITY))
	q += 0.1 * floor_tidiness()
	if Staff.tired(who):
		q -= 0.2  # delegated work is the first thing to suffer
	return clampf(q, 0.05, 0.95)

func duties_tick() -> void:
	## Delegated work happens off screen and is reported, not played. When it
	## goes wrong it surfaces as an ordinary fault, later.
	last_digest = []
	for id: String in DUTIES:
		var name := duty_holder(id)
		if name == "":
			continue
		var who := Staff.by_name(name)
		if who.is_empty() or not Staff.on_shift(who):
			last_digest.append("%s: nobody on shift to do it" % DUTIES[id]["label"])
			continue
		var good := randf() < duty_quality(id)
		match id:
			"parts":
				if good:
					last_digest.append("%s kept the drawer stocked" % name)
				else:
					# the wrong lengths, ordered in good faith
					buy_parts("power", 5)
					last_digest.append("%s restocked, and got the wrong parts in" % name)
			"facility":
				last_digest.append("%s is keeping the facility schedule" % name if good
					else "%s let a facility job slide this cycle" % name)
				if not good:
					for task: String in FACILITY_TASKS:
						facility_auto[task] = false
					facility_auto["filters"] = true
			"renewals":
				last_digest.append("%s is watching the renewals calendar" % name)
			"receiving":
				var waiting := crates_waiting()
				if waiting.is_empty():
					last_digest.append("%s: nothing on the dock" % name)
				elif good:
					check_crate(waiting[0])
					if waiting[0] in crates:  # a damaged one went straight back
						unpack_crate(waiting[0])
					last_digest.append("%s checked and unpacked a crate" % name)
				else:
					unpack_crate(waiting[0])
					last_digest.append("%s unpacked a crate without checking it against the order"
						% name)
			"housekeeping":
				last_digest.append(do_housekeeping(name, good))
			"labels":
				var done := false
				for d: Net.NDevice in all_devices():
					for i: Net.Iface in d.ifaces:
						if link_at(i) == null or not i.note.is_empty() \
								or i.name.begins_with("Management"):
							continue
						if good:
							i.note = {"text": "%s: patched %s" % [name, d.name], "cycle": cycle}
							var lbl_rack := rack_of(d)
							note_crew_focus(lbl_rack.name if lbl_rack != null else "", "labelling")
							last_digest.append("%s labelled %s %s" % [name, d.name, i.name])
						else:
							# a tired tech puts the label on the wrong port, which
							# is worse than no label and is found much later
							var wrong: Net.Iface = d.ifaces[(d.ifaces.find(i) + 1) % d.ifaces.size()]
							wrong.note = {"text": "%s: patched %s" % [name, d.name], "cycle": cycle}
							last_digest.append("%s labelled a port on %s" % [name, d.name])
						done = true
						break
					if done:
						break
				if not done:
					last_digest.append("%s: everything is labelled" % name)
	if not last_digest.is_empty():
		log_event("DUTIES: %s." % "; ".join(PackedStringArray(last_digest)))

func cable_debt_items() -> Array:
	## Every penalty traces to one of these, and each is visible on the floor.
	var out: Array = []
	for i in cable_debt:
		out.append({"kind": "improvised", "label": "an improvised lead of the wrong length",
			"fix": "redo it with a proper lead"})
	for l: Net.Link in links:
		for i: Net.Iface in [l.a, l.b]:
			if i.name.begins_with("Management"):
				continue
			if i.note.is_empty():
				out.append({"kind": "unlabelled", "iface": i,
					"label": "%s %s is patched and carries no label" % [i.dev.name, i.name],
					"fix": "label it"})
		if rack_of(l.a.dev) != rack_of(l.b.dev) and docs.get(l.a.dev.name, {}).is_empty():
			out.append({"kind": "undocumented_run", "iface": l.a,
				"label": "%s to %s runs between cabinets and is in nobody's documentation"
					% [l.a.dev.name, l.b.dev.name],
				"fix": "walk the cabinet and write it up"})
	return out

func cable_debt_score() -> int:
	return cable_debt_items().size()

func plan_cable(a: Net.Iface, b: Net.Iface) -> Dictionary:
	## What each way of doing it costs, before anybody commits to either.
	var cross := rack_of(a.dev) != rack_of(b.dev)
	return {
		"expedient": {"cost": 0, "parts": "one %s" % ("optic" if cross else "patch lead"),
			"debt": 2 if cross else 1,
			"why": "in now, labelled never, and it counts against you until somebody comes back"},
		"documented": {"cost": 25, "parts": "one %s and two labels" % ("optic" if cross else "patch lead"),
			"debt": 0,
			"why": "both ends labelled and written up on the way in"},
	}

func connect_documented(a: Net.Iface, b: Net.Iface) -> bool:
	## The slower way: it costs a little money and leaves nothing to come back to.
	if not spend_on("cabling", 25):
		return false
	if not connect_ifaces(a, b):
		_refund(25)
		return false
	a.note = {"text": "patched to %s %s" % [b.dev.name, b.name], "cycle": cycle}
	b.note = {"text": "patched to %s %s" % [a.dev.name, a.name], "cycle": cycle}
	document_device(a.dev)
	document_device(b.dev)
	return true

const PART_PRICES := {"patch": 6, "optic": 45, "power": 8, "blank": 12}
const PART_LABELS := {"patch": "patch leads", "optic": "optics", "power": "power cords",
	"blank": "blanking panels"}
const PART_REORDER := 8  # top the drawer back up to this when it runs low

func parts_of(kind: String) -> int:
	return int(parts.get(kind, 0))

func buy_parts(kind: String, qty := 10) -> String:
	if not PART_PRICES.has(kind):
		return "there is no such part"
	var price := int(PART_PRICES[kind]) * qty
	if not spend_on("parts", price):
		return "%d %s cost $%d" % [qty, PART_LABELS[kind], price]
	parts[kind] = parts_of(kind) + qty
	log_event("PARTS: %d %s into the drawer for $%d." % [qty, PART_LABELS[kind], price])
	return ""

func take_part(kind: String) -> bool:
	var refill_cost := int(PART_PRICES.get(kind, 0)) * PART_REORDER
	if parts_of(kind) <= 0 and parts_auto and money - refill_cost >= PARTS_CASH_FLOOR:
		# the standing order exists precisely so this is not a chore every cycle
		money -= refill_cost
		last_pl["parts"] = int(last_pl.get("parts", 0)) - refill_cost
		money_changed.emit()
		parts[kind] = PART_REORDER
		log_event("PARTS: the drawer ran out of %s and the standing order refilled it."
			% PART_LABELS[kind])
	if parts_of(kind) <= 0:
		return false
	parts[kind] = parts_of(kind) - 1
	return true

func improvise_part(kind: String) -> void:
	## The wrong length, at two in the morning. It works, and it is visible for
	## as long as it stays there.
	cable_debt += 1
	log_event("IMPROVISED: no %s of the right sort in the drawer, so something else went in. That is cable debt now."
		% PART_LABELS[kind])

func redo_cable_debt() -> String:
	if cable_debt <= 0:
		return "there is nothing improvised in there"
	if not take_part("patch"):
		return "there is nothing in the drawer to redo it with"
	cable_debt -= 1
	log_event("CABLING: one improvised lead replaced with the right length.")
	topology_changed.emit()
	return ""

func parts_tick() -> void:
	if not parts_auto:
		return
	for kind: String in PART_PRICES:
		if parts_of(kind) >= PART_REORDER:
			continue
		var qty := PART_REORDER * 2 - parts_of(kind)
		var price := int(PART_PRICES[kind]) * qty
		if money - price < PARTS_CASH_FLOOR:
			continue  # the drawer is not worth going insolvent over
		money -= price
		last_pl["parts"] = int(last_pl.get("parts", 0)) - price
		money_changed.emit()
		parts[kind] = parts_of(kind) + qty
		log_event("PARTS: the standing order topped up %s ($%d). It runs itself until the money does not."
			% [PART_LABELS[kind], price])

const VENDOR_TIERS := {
	"trade": {"label": "trade supplier", "price": 0.85, "wait": [4, 7],
		"blurb": "Cheapest, and you wait."},
	"distributor": {"label": "distributor", "price": 1.0, "wait": [2, 4],
		"blurb": "The usual channel."},
	"urgent": {"label": "urgent shipping", "price": 1.35, "wait": [1, 2],
		"blurb": "Costs a premium, and is still not instant."},
	"used": {"label": "second-hand", "price": 0.55, "wait": [2, 5],
		"blurb": "Cheap, no warranty, somebody else's serial, and sometimes somebody else's problem."},
}

func stocked_out(model: String) -> bool:
	return cycle < int(stockouts.get(model, -1))

func substitutes_for(model: String) -> Array:
	## What you can have instead when the popular one is on back order.
	var out: Array = []
	for other: String in MODELS:
		if other != model and String(MODELS[other]["type"]) == String(MODELS[model]["type"]) \
				and not stocked_out(other):
			out.append(other)
	return out

func stockout_tick() -> void:
	if biz_roll() > 0.03:
		return
	var models: Array = MODELS.keys()
	var model: String = models[int(biz_roll() * models.size()) % models.size()]
	if stocked_out(model):
		return
	stockouts[model] = cycle + 6 + int(biz_roll() * 8.0)
	log_event("SUPPLY: %s is on back order until around cycle %d. Everybody wants that one."
		% [MODELS[model]["label"], int(stockouts[model])])

func order_estimate(model: String, tier: String) -> int:
	var spec: Dictionary = VENDOR_TIERS.get(tier, VENDOR_TIERS["distributor"])
	return int(float(MODELS[model]["price"]) * float(spec["price"]) * identity_hardware_multiplier() * price_scale())

func send_rma(dev: Net.NDevice) -> String:
	## Ship the dead one back. With cover you get the replacement first.
	if dev.status == "active":
		return "%s is running" % dev.name
	var advance := support_tier() >= 1
	var wait := 2 if advance else 5
	rmas.append({"model": dev.model, "device": dev.name, "due": cycle + wait,
		"advance": advance})
	uninstall_device(dev, false)
	log_event("RMA: %s shipped back to the vendor.%s" % [dev.name,
		"  Advance replacement is on its way on your support contract."
		if advance else "  The replacement follows when they have seen it."])
	topology_changed.emit()
	return ""

func rma_tick() -> void:
	for r in rmas.duplicate():
		if cycle < int(r["due"]):
			continue
		rmas.erase(r)
		crates.append({"model": r["model"], "shipped": r["model"], "ordered": cycle,
			"due": cycle, "arrived": cycle, "checked": false, "damaged": false,
			"unpack_left": 2 if String(r["model"]) in HEAVY_MODELS else 1})
		log_event("RMA: the replacement %s is on the dock." % MODELS[r["model"]]["label"])

const RECEIVING_SPACE := 4  # crates the receiving area holds before it is an aisle problem
const HEAVY_MODELS := ["sw-24", "srv-2", "rtr-edge", "crac-1", "lb-1"]

func order_hardware(model: String, qty := 1, tier := "trade") -> String:
	## Ordering is cheaper than collecting it yourself, and what turns up is a
	## pallet rather than a working device.
	if not MODELS.has(model):
		return "no such model"
	if not VENDOR_TIERS.has(tier):
		return "nobody sells it like that"
	if stocked_out(model):
		var alts := substitutes_for(model)
		return "%s is on back order until cycle %d%s" % [MODELS[model]["label"],
			int(stockouts[model]),
			"; they can send a %s instead" % MODELS[alts[0]]["label"] if not alts.is_empty() else ""]
	qty = clampi(qty, 1, 4)
	var spec: Dictionary = VENDOR_TIERS[tier]
	var price := order_estimate(model, tier) * qty
	if not spend_on("hardware orders", price):
		return "that order comes to $%d" % price
	for i in qty:
		# a small proportion of every delivery is wrong or broken, and you only
		# find out if somebody checks it against the order
		var damaged := randf() < 0.1
		var wrong := "" if damaged or randf() > 0.1 else _wrong_model(model)
		crates.append({"model": model, "shipped": wrong if wrong != "" else model,
			"paid": order_estimate(model, tier),
			"ordered": cycle, "site": current_site,
			"due": cycle + randi_range(int(spec["wait"][0]), int(spec["wait"][1])), "arrived": -1,
			"checked": false, "damaged": damaged, "used": tier == "used",
			"unpack_left": 2 if model in HEAVY_MODELS else 1})
	log_event("ORDERED: %d x %s from the %s for $%d, expected in %d to %d cycles."
		% [qty, MODELS[model]["label"], spec["label"], price,
			int(spec["wait"][0]), int(spec["wait"][1])])
	return ""

func _wrong_model(model: String) -> String:
	for other: String in MODELS:
		if other != model and String(MODELS[other]["type"]) == String(MODELS[model]["type"]):
			return other
	return model

func crate_site(c: Dictionary) -> int:
	return int(c.get("site", 0))  # crates from before floors were separate sat at home

func crates_waiting(site := -1) -> Array:
	## A crate sits on a dock in a building, not in the company.
	var idx := current_site if site < 0 else site
	var out: Array = []
	for c: Dictionary in crates:
		if int(c["arrived"]) >= 0 and crate_site(c) == idx:
			out.append(c)
	return out

func aisle_blocked() -> bool:
	## Crates and cardboard occupy the room whether you look at them or not.
	return crates_waiting().size() + packaging > RECEIVING_SPACE

func check_crate(crate: Dictionary) -> String:
	if int(crate["arrived"]) < 0:
		return "it has not arrived yet"
	if bool(crate["checked"]):
		return "you have already checked that one"
	crate["checked"] = true
	if bool(crate["damaged"]):
		log_event("RECEIVING: the %s arrived damaged. Checked on receipt, so it goes straight back and the money comes with it."
			% MODELS[crate["model"]]["label"])
		crates.erase(crate)
		_refund(int(float(crate.get("paid", MODELS[crate["model"]]["price"])) * 0.85))
		return ""
	if String(crate["shipped"]) != String(crate["model"]):
		log_event("RECEIVING: they shipped a %s instead of a %s. Caught at the dock; the right one is on its way."
			% [MODELS[crate["shipped"]]["label"], MODELS[crate["model"]]["label"]])
		crate["shipped"] = crate["model"]
		crate["due"] = cycle + 3
		crate["arrived"] = -1
		return ""
	log_event("RECEIVING: the %s matches the order and the serial is written down."
		% MODELS[crate["model"]]["label"])
	return ""

func unpack_crate(crate: Dictionary) -> String:
	## Heavy gear needs a second pair of hands or a second afternoon.
	if int(crate["arrived"]) < 0:
		return "it has not arrived yet"
	var hands := 1
	for m: Dictionary in staff:
		if Staff.on_shift(m):
			hands += 1
	crate["unpack_left"] = int(crate["unpack_left"]) - (2 if hands >= 2 else 1)
	if int(crate["unpack_left"]) > 0:
		log_event("RECEIVING: the %s is half out of its crate. It is deep, and it is heavy."
			% MODELS[crate["model"]]["label"])
		return ""
	crates.erase(crate)
	packaging += 1
	if bool(crate["damaged"]) and not bool(crate["checked"]):
		log_event("RECEIVING: the %s came out of the crate with a bent chassis. Nobody checked it at the dock, so that is now yours."
			% MODELS[crate["model"]]["label"])
		return ""
	var model := String(crate["shipped"])
	spares[model] = int(spares.get(model, 0)) + 1
	if bool(crate.get("used", false)) and randf() < 0.35:
		# no warranty, old firmware, and something the last owner knew about
		latent_defects[model] = int(latent_defects.get(model, 0)) + 1
	log_event("RECEIVING: a %s is unpacked and on the shelf.%s" % [MODELS[model]["label"],
		"" if model == String(crate["model"])
		else "  It is not what you ordered, and nobody noticed at the dock."])
	return ""

const TRANSIT_CYCLES := 2  # a van, not a teleport

func send_device_to(dev: Net.NDevice, site: int) -> String:
	## Stocking a second room means moving gear out of the first one. It leaves
	## the rack now and turns up on the other dock as a crate like any other.
	## ponytail: the spares shelf is company-wide, so what arrives is a spare of
	## that model rather than this exact box; per-site stock if it ever matters.
	if dev == null:
		return "there is nothing there"
	var r := rack_of(dev)
	if r == null:
		return "that is not racked anywhere"
	if site < 0 or site >= site_count():
		return "there is no such floor"
	if site == int(r.site):
		return "it is already on that floor"
	for i: Net.Iface in dev.ifaces:
		if link_at(i) != null:
			return "unplug it first: it is still cabled"
	var from_name := site_name(int(r.site))
	free_slots(r, dev)
	crates.append({"model": dev.model, "shipped": dev.model, "ordered": cycle,
		"due": cycle + TRANSIT_CYCLES, "arrived": -1, "checked": true, "damaged": false,
		"used": false, "site": site, "from": from_name,
		"unpack_left": 2 if dev.model in HEAVY_MODELS else 1})
	log_event("TRANSFER: %s left %s for %s. Its configuration stayed with the rack it came out of."
		% [dev.name, from_name, site_name(site)])
	topology_changed.emit()
	return ""

func clear_packaging() -> String:
	if packaging <= 0:
		return "the aisle is clear"
	packaging = 0
	log_event("RECEIVING: the cardboard and pallet wrap are out of the aisle.")
	return ""

func receiving_tick() -> void:
	for c in crates:
		if int(c["arrived"]) < 0 and cycle >= int(c["due"]):
			c["arrived"] = cycle
			log_event("DELIVERY: a crate is in the receiving area. Check it against the order before it is unpacked.")
	# the crew absorb this work when they have hands free
	if not staff.is_empty() and Staff.anyone_on_shift() and cycle % 2 == 0:
		var waiting := crates_waiting()
		if not waiting.is_empty():
			unpack_crate(waiting[0])
		elif packaging > 0:
			clear_packaging()

const REMOTE_ACTIONS := {
	"reseat": "reseat the cable in",
	"power_cycle": "power cycle",
	"check": "look at the lights on",
}

func remote_facility(site: int) -> Dictionary:
	## Your own floor has your own hands. Anywhere else you are buying them,
	## and cheap facilities are slower and sloppier.
	_ensure_sites()
	if site == 0:
		return {"label": "your own floor", "cost": 0, "wait": 0, "care": 1.0}
	if site < 0 or site >= sites.size():
		# a floor that is no longer in the list: a drill restored underneath it,
		# or a site was given up. Treat it as somebody else's building.
		return {"label": "a cheap colo", "cost": 120, "wait": 3, "care": 0.8}
	var kind := String(sites[site].get("kind", "acquired"))
	if kind == "floor":
		return {"label": "a staffed datacenter", "cost": 220, "wait": 1, "care": 1.0}
	return {"label": "a cheap colo", "cost": 120, "wait": 3, "care": 0.8}

func remote_precision(dev: Net.NDevice, iface: Net.Iface) -> float:
	## They follow the instruction literally, so the instruction is only as
	## good as your labels. This is what documentation is worth at distance.
	var site := 0
	var rack := rack_of(dev)
	if rack != null:
		site = int(rack.site)
	var care := float(remote_facility(site)["care"])
	var score := 0.5
	if iface != null and not iface.note.is_empty():
		score += 0.25
	if not dev.note.is_empty():
		score += 0.15
	if rack != null and not rack.note.is_empty():
		score += 0.1
	# what matters is whether the documentation for this cabinet is still true
	var local_drift := clampf(float(rack_drift(rack)) / 6.0, 0.0, 1.0) if rack != null else 0.0
	return clampf(score * care * (1.0 - 0.3 * local_drift), 0.0, 1.0)

func request_remote_hands(dev: Net.NDevice, action: String, iface: Net.Iface = null) -> String:
	if not REMOTE_ACTIONS.has(action):
		return "they will not do that"
	var rack := rack_of(dev)
	if rack == null:
		return "that device is not racked anywhere"
	var facility := remote_facility(int(rack.site))
	if not spend_on("remote hands", int(facility["cost"])):
		return "a block of remote hands at %s costs $%d" % [facility["label"], int(facility["cost"])]
	remote_jobs.append({"device": dev.name, "iface": iface.name if iface != null else "",
		"action": action,
		"due": cycle + int(round(float(facility["wait"]) * season_contractor_delay())),
		"precision": remote_precision(dev, iface), "site": int(rack.site)})
	log_event("REMOTE HANDS: asked %s to %s %s%s. They arrive in %d cycle(s) and will do exactly what is written."
		% [facility["label"], REMOTE_ACTIONS[action], dev.name,
			" %s" % iface.name if iface != null else "", int(facility["wait"])])
	return ""

func _remote_neighbour(dev: Net.NDevice, iface: Net.Iface) -> Array:
	## What they touch when the label is missing: the thing next to it.
	if iface != null:
		var idx := dev.ifaces.find(iface)
		if idx >= 0 and dev.ifaces.size() > 1:
			return [dev, dev.ifaces[(idx + 1) % dev.ifaces.size()]]
	var rack := rack_of(dev)
	if rack != null:
		for d in rack.slots:
			if d != null and d != dev:
				return [d, null]
	return [dev, iface]

func remote_hands_tick() -> void:
	for job in remote_jobs.duplicate():
		if cycle < int(job["due"]):
			continue
		remote_jobs.erase(job)
		var dev: Net.NDevice = null
		for d: Net.NDevice in all_devices():
			if d.name == String(job["device"]):
				dev = d
		if dev == null:
			log_event("REMOTE HANDS: they could not find %s. That is the job, and it is billed."
				% job["device"])
			continue
		var iface: Net.Iface = null
		for i: Net.Iface in dev.ifaces:
			if i.name == String(job["iface"]):
				iface = i
		var right := randf() < float(job["precision"])
		var target_dev := dev
		var target_iface := iface
		if not right:
			var wrong := _remote_neighbour(dev, iface)
			target_dev = wrong[0]
			target_iface = wrong[1]
		match String(job["action"]):
			"reseat":
				if target_iface != null:
					link_restore(target_iface)
					device_log(target_dev, "%s reseated by remote hands" % target_iface.name)
			"power_cycle":
				target_dev.status = "active"
				apply_device_config(target_dev, target_dev.startup)
				device_log(target_dev, "power cycled by remote hands")
			"check":
				log_event("REMOTE HANDS REPORT: %s %s: link light is %s." % [target_dev.name,
					target_iface.name if target_iface != null else "chassis",
					"on" if target_iface != null and target_iface.enabled else "off"])
		if right:
			log_event("REMOTE HANDS: done, on the device you meant.")
		else:
			log_event("REMOTE HANDS: they did it to %s%s. That is what the label said, or rather did not."
				% [target_dev.name, " %s" % target_iface.name if target_iface != null else ""])
		topology_changed.emit()

const GREY_KINDS := {
	"dirty_optic": {"label": "contaminated or third-party optic",
		"symptom": "input errors climbing and big packets going missing under load",
		"repair": "replace optic"},
	"loose_connector": {"label": "a connector that was never quite seated",
		"symptom": "intermittent loss in both directions, and it comes and goes",
		"repair": "reseat"},
	"one_way": {"label": "a damaged pair in the patch lead",
		"symptom": "traffic leaves and nothing comes back on that port",
		"repair": "replace cable"},
	"mtu": {"label": "an MTU somebody changed and nobody wrote down",
		"symptom": "small packets pass and large ones vanish, with no error anywhere",
		"repair": "fix config"},
}
const GREY_REPAIRS := ["reseat", "replace optic", "replace cable", "fix config"]

func iface_key(i: Net.Iface) -> String:
	return "%s|%s" % [i.dev.name, i.name]

func grey_fault(i: Net.Iface) -> Dictionary:
	return grey_faults.get(iface_key(i), {})

func grey_drops(from_if: Net.Iface, to_if: Net.Iface, bytes: int) -> bool:
	## Called on every hop, so it costs nothing at all when nothing is wrong.
	if grey_faults.is_empty():
		return false
	for pair: Array in [[from_if, "tx"], [to_if, "rx"]]:
		var fault: Dictionary = grey_fault(pair[0])
		if fault.is_empty():
			continue
		match String(fault["kind"]):
			"dirty_optic":
				if randf() < (0.45 if bytes > 512 else 0.12):
					return true
			"loose_connector":
				if randf() < 0.3:
					return true
			"one_way":
				# one direction only, which is what makes it so confusing
				if String(pair[1]) == "rx":
					return true
	return false

func inject_grey_fault(i: Net.Iface, kind: String) -> String:
	if not GREY_KINDS.has(kind):
		return "there is no such fault"
	grey_faults[iface_key(i)] = {"kind": kind, "since": cycle, "was_mtu": i.mtu}
	if kind == "dirty_optic":
		i.light_dbm = -18.5  # a dying receive level, visible to anybody who looks
	elif kind == "mtu":
		i.mtu = 1400  # quietly, and nothing goes red
	device_log(i.dev, "%s: no change logged" % i.name)
	return ""

func repair_grey(i: Net.Iface, action: String) -> String:
	## The wrong repair costs the part and the afternoon, and fixes nothing.
	if action not in GREY_REPAIRS:
		return "that is not something you can do to a port"
	var fault := grey_fault(i)
	if action == "replace optic" and not take_part("optic"):
		return "no optics in the drawer"
	if action == "replace cable" and not take_part("patch"):
		return "no patch leads in the drawer"
	if fault.is_empty():
		log_event("MAINTENANCE: %s %s %s. Nothing was wrong with it."
			% [i.dev.name, i.name, action])
		return ""
	if action != String(GREY_KINDS[fault["kind"]]["repair"]):
		log_event("NO CHANGE: %s on %s %s, and the errors are still climbing."
			% [action.capitalize(), i.dev.name, i.name])
		return ""
	grey_faults.erase(iface_key(i))
	i.rx_errors = 0
	i.light_dbm = -6.0
	if String(fault["kind"]) == "mtu":
		i.mtu = int(fault.get("was_mtu", 1500))
	log_event("FIXED: %s on %s %s cleared the fault. The counters stop moving."
		% [action.capitalize(), i.dev.name, i.name])
	topology_changed.emit()
	return ""

func _maybe_grey_fault() -> void:
	## Aging hardware, a third-party optic, an improvised patch lead. Never
	## announced, and never red.
	# a fault like this belongs to an estate with some age on it
	if stage < 2 or grey_faults.size() >= 2 or biz_roll() > 0.02 * fault_scale():
		return
	var candidates: Array = []
	for l: Net.Link in links:
		for i: Net.Iface in [l.a, l.b]:
			if i.enabled and not i.name.begins_with("Management") and grey_fault(i).is_empty():
				candidates.append(i)
	if candidates.is_empty():
		return
	var victim: Net.Iface = candidates[int(biz_roll() * candidates.size()) % candidates.size()]
	var kinds: Array = GREY_KINDS.keys()
	var kind: String = kinds[int(biz_roll() * kinds.size()) % kinds.size()]
	if cable_debt > 0 and biz_roll() < 0.5:
		kind = "one_way"  # the improvised lead somebody put in at 2am
	inject_grey_fault(victim, kind)

## Somebody rings while you are still working out what is wrong. Three answers,
## all defensible, and the one you give is remembered.
const CALL_ANSWERS := [
	{"id": "honest", "label": "Tell them what you know so far",
		"blurb": "Costs nothing, buys a little patience, and is true."},
	{"id": "promise", "label": "Promise them a time",
		"blurb": "Buys real patience now, and costs double if you miss it."},
	{"id": "callback", "label": "Say you will call back",
		"blurb": "Cheapest thing to say, and the worst thing to have said if this drags."},
]

func _call_words(deal: Dictionary) -> String:
	var biz := Market.business_for(deal)
	var arc := story_arc(story_key(String(deal.get("customer", ""))))
	if not arc.is_empty() and int(arc.get("outages", 0)) > 2:
		return "This is the third time. I am not asking you to grovel, I am asking what is happening."
	return "%s What do I tell people?" % String(biz["down"])

func maybe_call(deal: Dictionary) -> void:
	## They ring when it has gone on long enough to be somebody's problem, and
	## only once per outage.
	if int(deal.get("missed", 0)) != 2 or deal.has("call"):
		return
	deal["call"] = {"words": _call_words(deal), "raised": cycle}
	log_event("THE PHONE: %s is on the line about their service." % deal["customer"])
	Sfx.play("phone")

func answer_call(deal: Dictionary, answer: String) -> String:
	var call: Dictionary = deal.get("call", {})
	if call.is_empty():
		return "nobody is on the phone"
	var known := false
	for option: Dictionary in CALL_ANSWERS:
		if String(option["id"]) == answer:
			known = true
	if not known:
		return "that is not one of the things you can say"
	deal.erase("call")
	deal["last_answer"] = answer
	var said: Array = deal.get("said", [])
	said.append(answer)
	deal["said"] = said
	match answer:
		"honest":
			deal["missed"] = maxi(0, int(deal.get("missed", 0)) - 1)
			deal["loyalty"] = minf(1.0, float(deal.get("loyalty", 0.6)) + 0.03)
			log_event("YOU SAID: what you actually knew. %s will wait a little longer for that."
				% deal["customer"])
		"promise":
			deal["missed"] = maxi(0, int(deal.get("missed", 0)) - 2)
			deal["promised_by"] = cycle + 3
			log_event("YOU SAID: it will be back within three cycles. %s wrote that down."
				% deal["customer"])
		"callback":
			deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - 0.05)
			log_event("YOU SAID: you would call back. %s is still waiting to hear from somebody."
				% deal["customer"])
	return ""

var night_call := {}  # {reason, cycle} : the phone ringing on an empty floor

func night_call_tick() -> void:
	## Somebody rings you when the room is empty and something is live. The
	## option to get out of bed has to arrive where the player is, not be
	## found later in a panel.
	if not night_call.is_empty():
		# the moment passes: somebody clocked on, or it fixed itself
		if not callout_ready():
			night_call = {}
		return
	if not callout_ready():
		return
	var reason := ""
	if customer_outage_active:
		reason = "a customer of yours is off the air and there is nobody in the building"
	elif not hazards.is_empty():
		var h: Dictionary = hazards[0]
		reason = "the panel is showing %s in %s and the floor is empty" % [
			HAZARD_KINDS[h["kind"]]["label"], h["rack"]]
	else:
		for d in all_devices():
			if d.status != "active":
				reason = "%s has dropped off the network and there is nobody in" % d.name
				break
	if reason == "":
		return
	night_call = {"reason": reason, "cycle": cycle}
	log_event("THE PHONE: %s." % sentence(reason))
	Sfx.play("phone")

func answer_night_call(get_them_in: bool) -> String:
	if night_call.is_empty():
		return "nobody is on the phone"
	if not get_them_in:
		night_call = {}
		log_event("THE PHONE: you said it waits until morning. Whatever it does overnight, it does.")
		return ""
	var err := call_someone_out()
	if err != "":
		return err
	night_call = {}
	return ""

var handover := {}      # what the shift going home left for the one coming in
var _handover_slot := -1

var crew_focus := {}  # {rack, cycle, what}: where the crew's last real job was

func note_crew_focus(rack_name: String, what: String) -> void:
	## Work that happens during the tick still happens somewhere. The floor
	## reads this so the person doing it is standing in the right place.
	if rack_name == "":
		return
	crew_focus = {"rack": rack_name, "cycle": cycle, "what": what}

func crew_focus_rack() -> String:
	## Only for the cycle it happened in: a stale focus is just a place.
	if crew_focus.is_empty() or int(crew_focus.get("cycle", -1)) != cycle:
		return ""
	return String(crew_focus.get("rack", ""))

func handover_lines() -> Array:
	## What a person would actually write at the end of a long night, read off
	## the floor rather than from a script, most urgent first.
	var lines: Array = []
	# what actually happened on the watch, before what is still open: four
	# cycles is one shift, and only what somebody would bother repeating
	# only what has happened since the last note was written: a handover that
	# repeats itself stops being read, and then it costs you
	var since := cycle - 4
	if not handover.is_empty():
		since = maxi(since, int(handover.get("cycle", since)) + 1)
	var happened: Array = []
	for ev in events:
		var parts := String(ev).split(": ", true, 1)
		if parts.size() < 2 or not String(parts[0]).begins_with("cycle "):
			continue
		if int(String(parts[0]).substr(6)) < since:
			break  # the log is newest first
		if event_severity(String(parts[1])) == "info":
			continue
		if String(parts[1]).begins_with("HANDOVER"):
			continue  # a note that quotes the last note is not a note
		happened.append(String(parts[1]))
		if happened.size() >= 3:
			break
	for h in happened:
		lines.append("On our watch: %s" % h)
	if customer_down_now():
		lines.append("A customer is off the air. That is the first thing.")
	for h: Dictionary in hazards:
		lines.append("%s in %s, severity %d%s." % [HAZARD_KINDS[h["kind"]]["label"], h["rack"],
			int(h["severity"]), "" if bool(h.get("detected", false)) else ", nothing is watching for it"])
	var dead: Array = []
	for d in all_devices():
		if d.status != "active":
			dead.append(d.name)
	if not dead.is_empty():
		lines.append("Down and not back: %s." % ", ".join(PackedStringArray(dead)))
	var down_links := 0
	for l in links:
		if not l.a.enabled or not l.b.enabled:
			down_links += 1
	if down_links > 0:
		lines.append("%d port(s) left disabled. Somebody should find out why." % down_links)
	if not tickets.is_empty():
		lines.append("%d ticket(s) still open." % tickets.size())
	var waiting := crates_waiting().size()
	if waiting > 0:
		lines.append("%d crate(s) on the dock, unchecked against the order." % waiting)
	var unsaved: Array = []
	for d2 in all_devices():
		if config_dirty(d2):
			unsaved.append(d2.name)
	if not unsaved.is_empty():
		lines.append("Running on unsaved configuration: %s." % ", ".join(PackedStringArray(unsaved)))
	if lines.is_empty():
		lines.append("Nothing happened. Everything that was up is still up.")
	return lines

func handover_tick() -> void:
	## A shift ends the way real ones do: with somebody writing down what the
	## next person needs to know before they take their coat off.
	var slot := day_slot()
	if slot not in [2, 6] or slot == _handover_slot:
		if slot not in [2, 6]:
			_handover_slot = -1
		return
	_handover_slot = slot
	# a note nobody reads stops being true, which is the same failure the
	# documentation drift models: the next shift finds out the hard way
	if not handover.is_empty() and not bool(handover.get("read", false)) \
			and int(handover.get("substantive", 0)) > 0:
		observe_habit("documents", false)
		log_event("HANDOVER: last shift's notes went unread, and the crew coming on found out the hard way.")
	var going := "night" if slot == 2 else "day"
	var written := handover_lines()
	handover = {"cycle": cycle, "from": going, "lines": written, "read": false,
		"substantive": 0 if written.size() == 1 and String(written[0]).begins_with("Nothing")
			else written.size()}
	log_event("HANDOVER: the %s shift left %d note(s) for the %s shift."
		% [going, handover["lines"].size(), "day" if going == "night" else "night"])

const TREND_WINDOW := 20  # far enough back that a slow measure has moved

func _trend_word(now: float, before: float, higher_is_better: bool, slack := 0.04) -> String:
	if absf(now - before) < slack:
		return "holding"
	var better := (now > before) == higher_is_better
	return "getting better" if better else "getting worse"

func room_maturity() -> float:
	## How settled the room looks: a long clear run, documentation that still
	## describes the floor, a tidy estate and a redundancy somebody has tested.
	## Nothing here is time alone, so an idle run does not age into a good one.
	var streak := clampf(float(cycles_since_customer_outage()) / 60.0, 0.0, 1.0)
	var kept := floor_tidiness()
	var described := 1.0 - drift_factor()
	var proved := 1.0 if int(stats.get("failovers_passed", 0)) > 0 else 0.0
	return clampf(streak * 0.3 + kept * 0.3 + described * 0.25 + proved * 0.15, 0.0, 1.0)

func trend_read() -> Array:
	## The slow measures, with a direction, while there is still time to do
	## something about them. Everything here is read off state the game keeps.
	var then := {}
	for h in history:
		if int(h.get("cycle", 0)) <= cycle - TREND_WINDOW:
			then = h
	var out: Array = []
	out.append("Reliability: %d cycle(s) clear, best %d." % [cycles_since_customer_outage(),
		best_streak()])
	var tidy := floor_tidiness()
	out.append("The floor: %d%% kept, %s." % [int(tidy * 100.0),
		_trend_word(tidy, float(then.get("tidy", tidy)), true)])
	var drift := drift_factor()
	out.append("Documentation: %d%% of it no longer matches the floor, %s." % [int(drift * 100.0),
		_trend_word(drift, float(then.get("drift", drift)), false)])
	var best_habit := ""
	var worst_habit := ""
	for habit: String in HABITS:
		if best_habit == "" or float(habits[habit]) > float(habits[best_habit]):
			best_habit = habit
		if worst_habit == "" or float(habits[habit]) < float(habits[worst_habit]):
			worst_habit = habit
	if best_habit != "" and worst_habit != "":
		out.append("What the team copies from you: %s most (%d%%), %s least (%d%%)." % [
			best_habit, int(float(habits[best_habit]) * 100.0),
			worst_habit, int(float(habits[worst_habit]) * 100.0)])
	# the four above are also what the room itself looks like, which is worth
	# saying out loud, because the floor is where the player actually is
	var settled := room_maturity()
	var room_word := "still new: nothing about it says anybody has been here long"
	if settled >= 0.6:
		room_word = "settled: the aisle is walked clean and the matting is down"
	elif settled >= 0.35:
		room_word = "starting to look kept: there is a walked aisle down the middle"
	out.append("The room reads as %s." % room_word)
	return out

func read_handover() -> void:
	if not handover.is_empty() and not bool(handover.get("read", false)):
		handover["read"] = true
		stats["handovers_read"] = int(stats.get("handovers_read", 0)) + 1

func call_tick() -> void:
	## A promise is only worth what it costs to miss it.
	for deal in deals:
		if bool(deal.get("healthy", false)):
			if deal.has("promised_by") and cycle <= int(deal["promised_by"]):
				deal.erase("promised_by")
				deal["loyalty"] = minf(1.0, float(deal.get("loyalty", 0.6)) + 0.12)
				reputation = mini(100, reputation + 2)
				log_event("KEPT IT: %s was back inside the window you promised them."
					% deal["customer"])
			deal.erase("promised_by")
			continue
		maybe_call(deal)
		if deal.has("promised_by") and cycle > int(deal["promised_by"]):
			deal.erase("promised_by")
			deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - 0.25)
			reputation = maxi(0, reputation - 6)
			deal["missed"] = int(deal.get("missed", 0)) + 2
			log_event("BROKEN PROMISE: you told %s three cycles. It has been longer, and they heard it from you rather than found it out."
				% deal["customer"])
			record_incident("promise", "a repair time promised to %s was missed" % deal["customer"])

const TICKET_AREAS := ["network", "power", "customer side", "upstream"]
const TICKET_WORDS := {
	"down_smb": ["the internet is broken", "nothing works this morning", "we are completely off"],
	"down_ent": ["our monitoring shows the service unreachable since %d minutes past",
		"we have lost all connectivity to the hosted service"],
	"slow_smb": ["everything is really slow today", "it keeps spinning and then works"],
	"slow_ent": ["we are seeing elevated latency and retransmits on the link"],
	"upstream": ["we cannot reach anything outside", "half the internet is down for us"],
	"none": ["email has been slow since this morning", "the office printer will not connect",
		"our site works from my phone but not from the desk"],
}

func _ticket_text(deal: Dictionary, kind: String) -> String:
	var enterprise := String(deal.get("ctype", "smb")) == "enterprise"
	var key := kind
	if kind in ["down", "slow"]:
		key = "%s_%s" % [kind, "ent" if enterprise else "smb"]
	var options: Array = TICKET_WORDS.get(key, TICKET_WORDS["none"])
	var text: String = options[absi((String(deal.get("customer", "")) + kind).hash()) % options.size()]
	return text % cycle if "%d" in text else text

func open_ticket(customer: String, text: String, cause: Dictionary) -> Dictionary:
	for t: Dictionary in tickets:
		if String(t["customer"]) == customer and String(t["state"]) == "open" \
				and JSON.stringify(t["cause"]) == JSON.stringify(cause):
			return t  # they are not going to file it twice
	_ticket_seq += 1
	var ticket := {"id": "T%03d" % _ticket_seq, "customer": customer, "text": text,
		"cause": cause, "opened": cycle, "state": "open", "triaged": "", "reopened": 0}
	tickets.push_front(ticket)
	log_event("TICKET %s from %s: \"%s\"" % [ticket["id"], customer, text])
	return ticket

func ticket_area_for(cause: Dictionary) -> String:
	match String(cause.get("kind", "")):
		"deal_down", "congestion":
			return "network"
		"upstream":
			return "upstream"
		"none":
			return "customer side"
	return "network"

func triage_ticket(t: Dictionary, area: String) -> String:
	## Guessing costs the one thing an incident does not give you: time.
	if String(t["state"]) != "open":
		return "that ticket is not open"
	if area not in TICKET_AREAS:
		return "that is not somewhere to look"
	t["triaged"] = area
	if area == ticket_area_for(t["cause"]):
		t["state"] = "investigating"
		log_event("TICKET %s: triaged to %s, which is where it actually is.%s" % [t["id"], area,
			"  %s" % _ticket_hint(t["cause"])])
		return ""
	money -= 40  # somebody's afternoon, spent looking in the wrong place
	money_changed.emit()
	log_event("TICKET %s: triaged to %s. That is not where it is, and the clock kept running."
		% [t["id"], area])
	return ""

func _ticket_hint(cause: Dictionary) -> String:
	match String(cause.get("kind", "")):
		"deal_down":
			return "Their service is genuinely not reachable from here."
		"congestion":
			return "The path is up and over capacity: it is a bandwidth problem, not a fault."
		"upstream":
			return "Your own tooling says the fault is past your edge."
		"none":
			return "Everything of yours is healthy. This one is theirs."
	return ""

func ticket_condition_live(t: Dictionary) -> bool:
	## Is the thing they are complaining about still true?
	var cause: Dictionary = t["cause"]
	match String(cause.get("kind", "")):
		"deal_down":
			for deal in deals:
				if String(deal.get("id", "")) == String(cause.get("deal", "")):
					return not bool(deal.get("healthy", false))
			return false
		"congestion":
			for deal in deals:
				if String(deal.get("id", "")) == String(cause.get("deal", "")):
					return bool(deal.get("degraded", false))
			return false
		"upstream":
			return upstream_active()
	return false

func close_ticket(t: Dictionary) -> String:
	if String(t["state"]) == "closed":
		return "that one is closed"
	t["state"] = "closed"
	t["closed"] = cycle
	if ticket_condition_live(t):
		log_event("TICKET %s closed. Nothing about it has actually changed." % t["id"])
	else:
		reputation = mini(100, reputation + 1)
		log_event("TICKET %s closed: %s can see it working again." % [t["id"], t["customer"]])
	return ""

func ticket_tick() -> void:
	## Tickets come from real conditions, several can share one root cause, and
	## some of them are not ours at all.
	for deal in deals:
		if not bool(deal.get("ever_healthy", false)):
			continue
		if not bool(deal.get("healthy", false)):
			open_ticket(String(deal["customer"]), _ticket_text(deal, "down"),
				{"kind": "deal_down", "deal": String(deal.get("id", ""))})
		elif bool(deal.get("degraded", false)):
			open_ticket(String(deal["customer"]), _ticket_text(deal, "slow"),
				{"kind": "congestion", "deal": String(deal.get("id", ""))})
	if upstream_active():
		for deal in deals:
			open_ticket(String(deal["customer"]), _ticket_text(deal, "upstream"), {"kind": "upstream"})
	if not deals.is_empty() and biz_roll() < 0.06:
		var deal: Dictionary = deals[int(biz_roll() * deals.size()) % deals.size()]
		open_ticket(String(deal["customer"]), _ticket_text(deal, "none"), {"kind": "none"})
	for t in tickets:
		if String(t["state"]) == "closed" and ticket_condition_live(t) \
				and cycle - int(t.get("closed", cycle)) >= 3:
			t["state"] = "open"
			t["reopened"] = int(t["reopened"]) + 1
			reputation = maxi(0, reputation - 3)
			log_event("TICKET %s reopened by %s, and they are not being polite about it. It was never fixed."
				% [t["id"], t["customer"]])
	if tickets.size() > 12:
		# keep every open ticket, cap the closed tail: trimming an open one
		# only made it come back next cycle under a new number
		var kept: Array = []
		var closed_kept := 0
		for t2 in tickets:
			if String(t2.get("state", "")) != "closed":
				kept.append(t2)
			elif closed_kept < 12:
				kept.append(t2)
				closed_kept += 1
		tickets = kept

func management_ips(d: Net.NDevice) -> Array:
	var out: Array = []
	for i: Net.Iface in d.ifaces:
		if d.type == "switch" and not i.name.begins_with("Management"):
			continue
		for cidr in i.ips:
			out.append(String(cidr).split("/")[0])
	return out

func console_reachable(d: Net.NDevice) -> bool:
	## Out of band: a serial cable from a console server does not care about
	## addressing at all, which is the entire reason it is worth having.
	for i: Net.Iface in d.ifaces:
		var l := link_at(i)
		if l != null and l.other(i).dev.type == "console" and l.other(i).dev.status == "active":
			return true
	return false

func device_reachable(d: Net.NDevice) -> bool:
	var ips := management_ips(d)
	if ips.is_empty():
		return true  # never addressed for remote management: you are at its console
	# a few vantage points answer "can anything reach it" without pinging the
	# whole estate: its neighbours first, since that is who talks to it
	var vantage: Array = []
	var rack := rack_of(d)
	if rack != null:
		for other in rack.slots:
			if other != null and other != d and other.status == "active":
				vantage.append(other)
	for other: Net.NDevice in all_devices():
		if vantage.size() >= 6:
			break
		if other != d and other.status == "active" and not (other in vantage):
			vantage.append(other)
	for other: Net.NDevice in vantage:
		for ip: String in ips:
			if Sim.ping(other, ip)["ok"]:
				return true
	return false

func locked_out(d: Net.NDevice) -> bool:
	if cycle < int(physical_access.get(d.name, -1)):
		return false
	return not device_reachable(d) and not console_reachable(d)

func arm_confirm(d: Net.NDevice, cycles := 3) -> String:
	## The counter-mechanic real gear gives you: the change reverts unless you
	## come back and say it worked.
	if confirm_commits.has(d.name):
		return "there is already a confirmation pending on %s" % d.name
	confirm_commits[d.name] = {"cfg": device_config(d), "due": cycle + maxi(1, cycles)}
	log_event("CONFIRMED COMMIT armed on %s: it reverts in %d cycles unless you confirm."
		% [d.name, maxi(1, cycles)])
	return ""

func confirm_commit(d: Net.NDevice) -> String:
	if not confirm_commits.has(d.name):
		return "nothing is pending on %s" % d.name
	if locked_out(d):
		return "you cannot confirm a change on a device you cannot reach"
	confirm_commits.erase(d.name)
	d.startup = device_config(d)
	log_event("CONFIRMED: the change on %s stands." % d.name)
	return ""

func walk_to_device(d: Net.NDevice) -> String:
	## Somebody has to stand in front of it. How far that is depends on where
	## you put it.
	var rack := rack_of(d)
	var site := int(rack.site) if rack != null else 0
	var cost := 0 if site == 0 else 350
	var label := "a walk across the floor" if site == 0 else "a site visit to %s" % site_name(site)
	if cost > 0 and not try_spend(cost):
		return "%s costs $%d" % [label, cost]
	physical_access[d.name] = cycle + 2 - (1 if access_friction() > 0.3 else 0)
	log_event("PHYSICAL ACCESS: %s. You are at %s's console for the next couple of cycles.%s"
		% [label.capitalize(), d.name, "" if cost == 0 else "  That cost $%d." % cost])
	return ""

func lockout_tick() -> void:
	# reachability is expensive to compute, and a lockout is not urgent news
	if cycle % 4 != 0:
		return
	for d: Net.NDevice in all_devices():
		var pending: Dictionary = confirm_commits.get(d.name, {})
		if not pending.is_empty() and cycle >= int(pending["due"]):
			confirm_commits.erase(d.name)
			apply_device_config(d, pending["cfg"])
			log_event("REVERTED: nobody confirmed the change on %s, so it rolled back to what was running before. That is what the timer is for."
				% d.name)
			topology_changed.emit()
			continue
		var first_sight := not lockout_state.has(d.name)
		var was: bool = bool(lockout_state.get(d.name, false))
		var now := locked_out(d)
		lockout_state[d.name] = now
		# only a device that could be reached and now cannot has locked you out
		if now and not was and not first_sight:
			log_event("LOCKED OUT: %s is running its new configuration and nothing can reach it. %s"
				% [d.name, "There is a console cable on it." if console_reachable(d)
					else "Console server, a walk to the rack, or a site visit."])
			record_incident("lockout", "%s was cut off by its own configuration" % d.name)

func _device_facts(d: Net.NDevice) -> Dictionary:
	## The handful of things people actually document about a device.
	var ports := {}
	for i: Net.Iface in d.ifaces:
		if i.name.begins_with("Management") or i.name == "lo":
			continue
		var l := link_at(i)
		ports[i.name] = {"to": "%s %s" % [l.other(i).dev.name, l.other(i).name] if l != null else "",
			"ips": i.ips.duplicate()}
	return {"model": d.model, "rack": rack_of(d).name if rack_of(d) != null else "", "ports": ports}

func document_device(d: Net.NDevice) -> void:
	docs[d.name] = _device_facts(d)

func device_drift(d: Net.NDevice) -> int:
	## How many documented facts are no longer true, plus anything undocumented.
	var claimed: Dictionary = docs.get(d.name, {})
	if claimed.is_empty():
		return 1 + _device_facts(d)["ports"].size()  # nothing about it is written down
	var facts := _device_facts(d)
	var drift := 0
	if String(claimed.get("rack", "")) != String(facts["rack"]):
		drift += 1
	var claimed_ports: Dictionary = claimed.get("ports", {})
	for port_name: String in facts["ports"]:
		var now: Dictionary = facts["ports"][port_name]
		var was: Dictionary = claimed_ports.get(port_name, {})
		if was.is_empty():
			drift += 1
		elif String(was.get("to", "")) != String(now["to"]) \
				or JSON.stringify(was.get("ips", [])) != JSON.stringify(now["ips"]):
			drift += 1
	return drift

func rack_drift(r: Net.Rack) -> int:
	var drift := 0
	for d in r.slots:
		if d != null:
			drift += device_drift(d)
	return drift

func site_drift(site := -1) -> int:
	var drift := 0
	for r: Net.Rack in racks_on(site if site >= 0 else current_site):
		drift += rack_drift(r)
	return drift

func drift_factor() -> float:
	## 0 when the documentation matches the floor, approaching 1 when it is
	## fiction. Everything that depends on knowing the estate reads this.
	var devs := 0
	for r: Net.Rack in racks_on(current_site):
		for d in r.slots:
			if d != null:
				devs += 1
	if devs == 0:
		return 0.0
	return clampf(float(site_drift()) / float(devs * 3), 0.0, 1.0)

func reconcile_rack(r: Net.Rack) -> String:
	## Cheap, boring, and exactly what a quiet afternoon is for.
	var drift := rack_drift(r)
	if drift == 0:
		return "%s already matches the documentation" % r.name
	if not spend_on("documentation", 30):
		return "walking the cabinet and writing it down costs $30"
	for d in r.slots:
		if d != null:
			document_device(d)
	log_event("DOCUMENTATION: %s walked and written up. %d fact(s) corrected." % [r.name, drift])
	return ""

func reconcile_after_change(targets: Array) -> void:
	## Offered right after emergency work, because that is when it is skipped.
	for name: String in targets:
		for d: Net.NDevice in all_devices():
			if d.name == name:
				document_device(d)

func orphan_list() -> Array:
	## Things nobody claims: read off the live estate rather than remembered.
	var out: Array = []
	for r: Net.Rack in racks_on(current_site):
		for d in r.slots:
			if d == null or d.status != "active" or d.type == "cooling":
				continue
			var cabled := false
			for i: Net.Iface in d.ifaces:
				if link_at(i) != null:
					cabled = true
			if not cabled:
				out.append({"kind": "device", "key": "device|%s" % d.name, "ref": d.name,
					"label": "%s (%s) is racked, powered and cabled to nothing"
						% [d.name, MODELS[d.model]["label"]]})
	for d: Net.NDevice in all_devices():
		if d.type != "switch":
			continue
		for vid: int in d.vlans:
			if int(vid) == 1:
				continue
			var used := false
			for i: Net.Iface in d.ifaces:
				if i.mode == "access" and int(i.untagged_vlan) == int(vid) and link_at(i) != null:
					used = true
				elif i.mode == "trunk" and link_at(i) != null:
					used = true
			if not used:
				out.append({"kind": "vlan", "key": "vlan|%s|%d" % [d.name, vid], "ref": d.name,
					"vid": int(vid),
					"label": "VLAN %d on %s has no member port and no traffic" % [vid, d.name]})
	for m: Dictionary in monitors:
		if Contracts._owner(String(m.get("target", ""))) == null:
			out.append({"kind": "monitor", "key": "monitor|%s" % m.get("target", ""), "ref": m,
				"label": "a check is still watching %s, which nothing serves" % m.get("target", "")})
	return out

func orphan_load_bearing(orphan: Dictionary) -> String:
	## The truth, computed from the live network. Investigation reveals it;
	## switching things off blind discovers it the hard way.
	match String(orphan["kind"]):
		"device":
			for d: Net.NDevice in all_devices():
				if d.name == String(orphan["ref"]):
					var ips: Array = []
					for i: Net.Iface in d.ifaces:
						for cidr in i.ips:
							ips.append(String(cidr).split("/")[0])
					for other: Net.NDevice in all_devices():
						if other == d:
							continue
						for route in other.static_routes:
							if String(route.get("via", "")) in ips:
								return "%s still routes through it" % other.name
					for m: Dictionary in monitors:
						if String(m.get("target", "")) in ips:
							return "a live check is pointed at it"
			return ""
		"vlan":
			for d: Net.NDevice in all_devices():
				if d.type != "switch" or d.name == String(orphan["ref"]):
					continue
				if d.vlans.has(int(orphan["vid"])):
					for i: Net.Iface in d.ifaces:
						if i.mode == "access" and int(i.untagged_vlan) == int(orphan["vid"]) \
								and link_at(i) != null:
							return "%s carries customer ports in that VLAN" % d.name
			return ""
	return ""

func orphan_intel_of(orphan: Dictionary) -> int:
	return int(orphan_intel.get(String(orphan["key"]), 0))

func investigate_orphan(orphan: Dictionary) -> String:
	## Uses the tools already here: counters, logs, and asking somebody.
	var level := orphan_intel_of(orphan)
	if level >= 2:
		return "you already know what that is"
	if not spend_on("investigation", 50):
		return "an afternoon of somebody's time costs $50"
	orphan_intel[String(orphan["key"])] = level + 1
	if level + 1 < 2:
		log_event("INVESTIGATION: counters and logs pulled for %s. Nothing conclusive yet."
			% orphan["label"])
		return ""
	var bearing := orphan_load_bearing(orphan)
	log_event("INVESTIGATION: %s. %s" % [orphan["label"],
		("It is load bearing: %s." % bearing) if bearing != ""
		else "Nothing has touched it and nothing depends on it. It can go."])
	return ""

func retire_orphan(orphan: Dictionary) -> String:
	var bearing := orphan_load_bearing(orphan)
	if bearing != "" and orphan_intel_of(orphan) >= 2:
		return "you know what that is carrying: %s" % bearing
	match String(orphan["kind"]):
		"device":
			for d: Net.NDevice in all_devices():
				if d.name == String(orphan["ref"]):
					decommission(d, DECOM_STEPS)
					break
		"vlan":
			for d: Net.NDevice in all_devices():
				if d.name == String(orphan["ref"]):
					d.vlans.erase(int(orphan["vid"]))
					break
		"monitor":
			monitors.erase(orphan["ref"])
	orphan_intel.erase(String(orphan["key"]))
	if bearing == "":
		log_event("RECLAIMED: %s. Power, space and addresses back." % orphan["label"])
	else:
		# diagnosable, and exactly what the investigation would have told you
		reputation = maxi(0, reputation - 3)
		log_event("IT WAS LOAD BEARING: %s. %s. Nobody looked first."
			% [orphan["label"], bearing.capitalize()])
		record_incident("zombie", "something nobody claimed turned out to be carrying traffic")
	topology_changed.emit()
	return ""

const SUPPORT_TIERS := [
	{"label": "no contract", "cost": 0, "wait": 8, "escalate": 4},
	{"label": "business hours", "cost": 900, "wait": 4, "escalate": 2},
	{"label": "24x7 premium", "cost": 2400, "wait": 1, "escalate": 1},
]

func support_tier() -> int:
	var best := 0
	for item: Dictionary in renewals:
		if String(item["kind"]) == "support" and not bool(item["lapsed"]):
			best = maxi(best, int(item.get("tier", 1)))
	return best

func buy_support(tier: int) -> String:
	tier = clampi(tier, 1, SUPPORT_TIERS.size() - 1)
	if support_tier() >= tier:
		return "you already have that cover"
	if not spend_on("support contract", int(SUPPORT_TIERS[tier]["cost"])):
		return "that contract costs $%d" % int(SUPPORT_TIERS[tier]["cost"])
	var item := add_renewal("support", "vendor support: %s" % SUPPORT_TIERS[tier]["label"],
		int(SUPPORT_TIERS[tier]["cost"]) / 4, 40)
	item["tier"] = tier
	log_event("SUPPORT: %s cover bought. Cases get a response in %d cycle(s)."
		% [SUPPORT_TIERS[tier]["label"], int(SUPPORT_TIERS[tier]["wait"])])
	return ""

func _maybe_firmware_bug() -> void:
	## A fault class no amount of player configuration fixes. Rare, and it does
	## not look like anything else: the port comes back and then goes again.
	# a defect like this belongs to an estate big enough to have one
	if stage < 2 or not firmware_bugs.is_empty() or cycle < 50 \
			or randf() > 0.004 * fault_scale():
		return
	var devs := all_devices().filter(func(d: Net.NDevice) -> bool:
		return d.type in ["switch", "router", "firewall"])
	if devs.is_empty():
		return
	var victim: Net.NDevice = devs[randi() % devs.size()]
	firmware_bugs[victim.name] = {"since": cycle, "model": victim.model}
	log_event("FIRMWARE: %s keeps dropping a port and bringing it straight back. Nothing in its configuration explains it. This is one for the vendor."
		% victim.name)
	record_incident("firmware", "%s is flapping a port for no configurable reason" % victim.name)

func firmware_tick() -> void:
	for name: String in firmware_bugs.keys():
		var dev: Net.NDevice = null
		for d: Net.NDevice in all_devices():
			if d.name == name:
				dev = d
		if dev == null:
			firmware_bugs.erase(name)
			continue
		if randf() > 0.25:
			continue
		for i: Net.Iface in dev.ifaces:
			if i.enabled and link_at(i) != null and not i.name.begins_with("Management"):
				link_fault(i, "firmware")
				device_log(dev, "%s changed state to down (no reason logged)" % i.name)
				topology_changed.emit()
				break

func open_tac_case(dev: Net.NDevice, severity: int) -> String:
	for c: Dictionary in tac_cases:
		if String(c["device"]) == dev.name and String(c["stage"]) != "closed":
			return "there is already an open case on %s" % dev.name
	var tier := support_tier()
	tac_cases.append({"id": "TAC-%d" % (tac_cases.size() + 1), "device": dev.name,
		"severity": clampi(severity, 1, 4), "stage": "evidence", "evidence": [],
		"opened": cycle, "tier": tier, "waiting_until": -1, "asked_again": false,
		"delegated": false})
	log_event("CASE %s opened against %s (severity %d, %s). They want a log bundle, a show command and a repro."
		% [tac_cases[tac_cases.size() - 1]["id"], dev.name, severity,
			SUPPORT_TIERS[tier]["label"]])
	return ""

const TAC_EVIDENCE := ["logs", "show", "repro"]

func attach_bundle(c: Dictionary) -> String:
	## One command produced everything they asked for, so it counts as all of
	## it: that is the point of collecting it in one go.
	if String(c["stage"]) not in ["evidence", "level_one"]:
		return "they are not waiting on you"
	for kind: String in TAC_EVIDENCE:
		if kind not in c["evidence"]:
			attach_evidence(c, kind)
	log_event("CASE %s: a full tech-support bundle attached in one go." % c["id"])
	return ""

func attach_evidence(c: Dictionary, kind: String) -> String:
	if String(c["stage"]) not in ["evidence", "level_one"]:
		return "they are not waiting on you"
	if kind not in TAC_EVIDENCE:
		return "they did not ask for that"
	var have: Array = c["evidence"]
	if kind in have:
		return "you have already sent that"
	have.append(kind)
	c["evidence"] = have
	if have.size() < TAC_EVIDENCE.size():
		return ""
	if not bool(c["asked_again"]):
		# level one asks for something you already sent. Everybody knows.
		c["asked_again"] = true
		c["stage"] = "level_one"
		c["evidence"] = TAC_EVIDENCE.slice(0, 2)
		log_event("CASE %s: level one has asked for the log bundle again. It is in the case already."
			% c["id"])
		return ""
	c["stage"] = "queued"
	c["waiting_until"] = cycle + int(SUPPORT_TIERS[int(c["tier"])]["wait"])
	log_event("CASE %s: complete and queued. Response expected in %d cycle(s) on your cover."
		% [c["id"], int(SUPPORT_TIERS[int(c["tier"])]["wait"])])
	return ""

func escalate_case(c: Dictionary) -> String:
	if String(c["stage"]) != "queued":
		return "there is nothing to escalate yet"
	if bool(c.get("escalated", false)):
		return "it is already with the escalation team"
	if not spend_on("support cases", 200):
		return "insisting costs $200 of somebody's afternoon"
	c["escalated"] = true
	c["waiting_until"] = cycle + int(SUPPORT_TIERS[int(c["tier"])]["escalate"])
	log_event("CASE %s escalated. Somebody who has seen this before is now reading it." % c["id"])
	return ""

func tac_tick() -> void:
	_maybe_firmware_bug()
	firmware_tick()
	for c in tac_cases:
		if String(c["stage"]) == "queued" and cycle >= int(c["waiting_until"]):
			c["stage"] = "fix_ready"
			log_event("CASE %s: confirmed as a known firmware defect. A fixed image is available; it needs a reload."
				% c["id"])
		elif bool(c.get("delegated", false)) and String(c["stage"]) in ["evidence", "level_one"]:
			# staff work the case, slowly, and they will not push back
			if cycle % 3 != 0:
				continue
			for kind: String in TAC_EVIDENCE:
				if kind not in c["evidence"]:
					attach_evidence(c, kind)
					break

func apply_firmware(c: Dictionary) -> String:
	## The fix is a reload, which is a change like any other: inside a window
	## it is routine, outside one it is a decision.
	if String(c["stage"]) != "fix_ready":
		return "there is no image to load yet"
	var dev: Net.NDevice = null
	for d: Net.NDevice in all_devices():
		if d.name == String(c["device"]):
			dev = d
	if dev == null:
		return "that device is not here any more"
	c["stage"] = "closed"
	firmware_bugs.erase(dev.name)
	apply_device_config(dev, dev.startup)
	if not in_maintenance() and randf() < 0.3:
		dev.status = "offline"
		log_event("FIRMWARE UPGRADE: %s did not come back cleanly, and you did it outside a window. It is offline."
			% dev.name)
		record_incident("firmware", "%s went down during an unplanned firmware upgrade" % dev.name)
		return ""
	log_event("FIRMWARE UPGRADE: %s reloaded on the fixed image. The flapping is gone, and case %s is closed."
		% [dev.name, c["id"]])
	topology_changed.emit()
	return ""

const RENEWAL_GRACE := 4  # a lapse is always recoverable, at a price
const LICENSED_MODELS := ["sw-24", "rtr-edge", "fw-1"]

func add_renewal(kind: String, label: String, cost: int, period: int, serial := "") -> Dictionary:
	var item := {"id": "%s_%d" % [kind, renewals.size()], "kind": kind, "label": label,
		"cost": cost, "period": period, "due": cycle + period, "auto": false,
		"serial": serial, "lapsed": false}
	renewals.append(item)
	return item

func renewal_by_id(id: String) -> Dictionary:
	for item: Dictionary in renewals:
		if String(item["id"]) == id:
			return item
	return {}

func renewal_due_in(item: Dictionary) -> int:
	return int(item["due"]) - cycle

func renew_item(id: String) -> String:
	var item := renewal_by_id(id)
	if item.is_empty():
		return "there is no such renewal"
	# a lapse is recoverable, at the premium everybody charges for late payment
	var price := int(item["cost"]) * (2 if bool(item["lapsed"]) else 1)
	if not spend_on("renewals", price):
		return "that renewal costs $%d and you do not have it" % price
	item["due"] = cycle + int(item["period"])
	var was_lapsed: bool = item["lapsed"]
	item["lapsed"] = false
	log_event("RENEWED: %s for $%d%s." % [item["label"], price,
		", out of lapse" if was_lapsed else ""])
	topology_changed.emit()
	return ""

func licence_capped(dev: Net.NDevice) -> bool:
	## A lapsed feature licence does not kill the device: it quietly caps it,
	## which is exactly the kind of failure that is hard to find.
	for item: Dictionary in renewals:
		if String(item["kind"]) == "licence" and String(item["serial"]) == dev.name \
				and bool(item["lapsed"]):
			return true
	return false

func support_lapsed() -> bool:
	for item: Dictionary in renewals:
		if String(item["kind"]) == "support" and bool(item["lapsed"]):
			return true
	return false

func renewal_tick() -> void:
	for item in renewals:
		var overdue := cycle - int(item["due"])
		if overdue < 0:
			continue
		if bool(item["auto"]) and not bool(item["lapsed"]):
			# auto-renew is a real cash flow decision: it takes the money when
			# it takes it, whatever else is happening that cycle
			if money >= int(item["cost"]):
				money -= int(item["cost"])
				last_pl["renewals"] = int(last_pl.get("renewals", 0)) - int(item["cost"])
				money_changed.emit()
				item["due"] = cycle + int(item["period"])
				log_event("AUTO-RENEWED: %s, $%d taken." % [item["label"], int(item["cost"])])
				continue
		if overdue == 0:
			log_event("DUE: %s is due now ($%d). There are %d cycles of grace after that."
				% [item["label"], int(item["cost"]), RENEWAL_GRACE])
		elif overdue == RENEWAL_GRACE and not bool(item["lapsed"]):
			item["lapsed"] = true
			match String(item["kind"]):
				"licence":
					log_event("LAPSED: the licence on %s has expired. The device is still up, and it is not running at the speed you think it is."
						% item["serial"])
				"support":
					log_event("LAPSED: %s. Hardware failures are now yours to pay for in full."
						% item["label"])
				_:
					log_event("LAPSED: %s. This gets more expensive and more visible from here."
						% item["label"])
			topology_changed.emit()
		elif bool(item["lapsed"]) and overdue % 4 == 0 \
				and String(item["kind"]) in ["domain", "addresses"]:
			# only the customer-facing lapses are visible from outside
			reputation = maxi(0, reputation - 1)

## Four kinds of company. Each one changes what work arrives, what it costs to
## run, and how the competition behaves. None of them is simply easier.
const IDENTITIES := {
	"budget": {"label": "Budget hoster",
		"blurb": "Second-hand gear at a third off, thin margins, and more of everything going wrong.",
		"trade": "hardware is cheap; faults are 30% more frequent and used gear is riskier",
		"signature": "A hundred small customers nobody else wants"},
	"reliability": {"label": "Reliability specialist",
		"blurb": "Strict service levels that pay a premium, and punish an outage twice as hard.",
		"trade": "service fees +20%; every outage costs double the reputation",
		"signature": "The bank that audits its suppliers"},
	"green": {"label": "Green operator",
		"blurb": "Efficient power and a renewable contract, on hardware that costs more to buy.",
		"trade": "electricity is a quarter cheaper; every purchase is 15% dearer",
		"signature": "A tenant who buys the tariff, not the rack"},
	"boutique": {"label": "Network boutique",
		"blurb": "Few customers, hard problems, and work nobody else will quote.",
		"trade": "complex work pays 30% more; ordinary hosting leads go elsewhere",
		"signature": "A fabric nobody else wanted to design"},
}

func identity_is(id: String) -> bool:
	return identity == id

func identity_offered() -> bool:
	return identity == "" and contracts_done.size() >= 6

func choose_identity(id: String) -> String:
	if not IDENTITIES.has(id):
		return "there is no such company"
	if identity != "":
		return "you are already a %s: a rebrand is what changes that" % IDENTITIES[identity]["label"]
	identity = id
	log_event("IDENTITY: you are a %s now. %s" % [IDENTITIES[id]["label"], IDENTITIES[id]["trade"]])
	leads.append(Market.identity_lead(id))
	return ""

func rebrand(id: String) -> String:
	## Expensive on purpose: it is a decision, and it is not a free respec.
	if not IDENTITIES.has(id):
		return "there is no such company"
	if id == identity:
		return "that is what you already are"
	if not try_spend(5000):
		return "a rebrand costs $5000 and a hit to your standing"
	reputation = maxi(0, reputation - 5)
	identity = id
	log_event("REBRAND: the sign says %s now, and the market will take a while to believe it."
		% IDENTITIES[id]["label"])
	leads.append(Market.identity_lead(id))
	return ""

func identity_hardware_multiplier() -> float:
	if identity_is("green"):
		return 1.15
	if identity_is("budget"):
		return 0.75
	return 1.0

func identity_fee_multiplier(kind: String) -> float:
	if identity_is("reliability"):
		return 1.2
	if identity_is("boutique") and kind in ["secure_host", "redundant_gw", "managed_switch"]:
		return 1.3
	return 1.0

## The human half of physical security. Strict access slows the work down;
## loose access is what makes the incidents possible in the first place.
const ACCESS_POLICIES := {
	"open": {"label": "Open floor", "cost": 0, "friction": 0.0, "risk": 1.0,
		"blurb": "Anybody who is in the building is on the floor. Nothing to badge, nothing to log."},
	"badges": {"label": "Badged zones", "cost": 700, "friction": 0.15, "risk": 0.45,
		"blurb": "Staff badge into the room, and every approach is written down."},
	"escorted": {"label": "Badged and escorted", "cost": 1400, "friction": 0.35, "risk": 0.15,
		"blurb": "Nobody who does not work here walks the floor alone. It costs you time on every visit."},
}

func set_access_policy(policy: String) -> String:
	if not ACCESS_POLICIES.has(policy):
		return "there is no such policy"
	if policy == access_policy:
		return "that is already the policy"
	var cost := int(ACCESS_POLICIES[policy]["cost"])
	if cost > 0 and not try_spend(cost):
		return "%s costs $%d to put in" % [ACCESS_POLICIES[policy]["label"], cost]
	access_policy = policy
	log_event("ACCESS: the floor is now %s. %s" % [ACCESS_POLICIES[policy]["label"].to_lower(),
		ACCESS_POLICIES[policy]["blurb"]])
	return ""

func buy_cameras() -> String:
	if cameras:
		return "the cameras are already up"
	if not spend_on("physical security", 1200):
		return "camera coverage costs $1200"
	cameras = true
	log_event("ACCESS: cameras cover the aisles. They prevent nothing and explain everything.")
	return ""

func access_note(who: String, what: String, authorised: bool) -> void:
	access_log.push_front({"cycle": cycle, "who": who, "what": what, "authorised": authorised,
		"seen": cameras or access_policy != "open"})
	if access_log.size() > 20:
		access_log.pop_back()

func admit_visitor(name: String, reason: String) -> String:
	## A contractor on the floor is useful and is also somebody you do not know.
	visitors.append({"name": name, "reason": reason, "since": cycle,
		"escorted": access_policy == "escorted"})
	access_note(name, "signed in: %s" % reason, true)
	log_event("VISITOR: %s is on the floor (%s)%s." % [name, reason,
		", escorted" if access_policy == "escorted" else ""])
	return ""

func visitor_leaves(name: String) -> void:
	for v in visitors.duplicate():
		if String(v["name"]) == name:
			visitors.erase(v)
			access_note(name, "signed out", true)

func access_incident_tick() -> void:
	## Rare, and never invisible: what happens depends on the policy, and what
	## you can find out afterwards depends on the cameras and the log.
	# somebody who does not work here has to be on the floor for any of this
	if guided_outage_active() or stage < 2 or racks.is_empty() or visitors.is_empty():
		return
	if biz_roll() > 0.02 * float(ACCESS_POLICIES[access_policy]["risk"]):
		return
	# whatever they touch has to be something that is actually plugged in
	var candidates: Array = []
	for cand: Net.Rack in racks_on(current_site):
		for d_c in cand.slots:
			if d_c == null:
				continue
			for i_c: Net.Iface in d_c.ifaces:
				if link_at(i_c) != null and not i_c.name.begins_with("Management"):
					candidates.append(cand)
					break
			break
	if candidates.is_empty():
		return
	var r: Net.Rack = candidates[int(biz_roll() * float(candidates.size())) % candidates.size()]
	var who: String = String(visitors[0]["name"]) if not visitors.is_empty() \
		else "somebody nobody recognised"
	match access_policy:
		"escorted":
			access_note(who, "turned back at the door to %s" % r.name, false)
			log_event("ACCESS: %s tried to follow somebody in and was turned back. Escorting works, and it is why every visit takes longer."
				% who)
			return
		"badges":
			access_note(who, "tailgated into the room, near %s" % r.name, false)
			log_event("ACCESS: the badge log shows a tailgate near %s. Nothing was touched, and you know it happened."
				% r.name)
			return
		_:
			pass
	# an open floor: somebody touched something, and the only question is
	# whether anything on this floor can tell you who
	for d in r.slots:
		if d == null:
			continue
		for i: Net.Iface in d.ifaces:
			if link_at(i) != null and not i.name.begins_with("Management"):
				link_fault(i, "unplugged")
				access_note(who, "unplugged %s %s" % [d.name, i.name], false)
				device_log(d, "%s changed state to down (no change logged)" % i.name)
				record_incident("access", "a cable was pulled in %s and nobody was badged" % r.name)
				log_event("ACCESS: something in %s was unplugged. %s" % [r.name,
					"The cameras have it." if cameras
					else "There is no badge log and no camera, so that is where the investigation ends."])
				topology_changed.emit()
				return

func access_investigation(since := 12) -> Array:
	## What you can actually reconstruct afterwards.
	var out: Array = []
	for entry: Dictionary in access_log:
		if cycle - int(entry["cycle"]) > since:
			continue
		if not bool(entry["seen"]):
			continue
		out.append("cycle %d · %s %s%s" % [int(entry["cycle"]), entry["who"], entry["what"],
			"" if bool(entry["authorised"]) else "  (not authorised)"])
	return out

func access_friction() -> float:
	return float(ACCESS_POLICIES[access_policy]["friction"])

## Environmental hazards: bounded, telegraphed, and always traceable to a
## reason the player could have seen coming.
const HAZARD_KINDS := {
	"smoke": {"label": "smoke", "spread": 1, "damage": "power",
		"causes": "an overloaded feed or a cabinet running far too hot"},
	"fire": {"label": "fire", "spread": 2, "damage": "device",
		"causes": "smoke nobody dealt with, or ageing gear in a hot cabinet"},
	"water": {"label": "water under the floor", "spread": 1, "damage": "power",
		"causes": "cooling nobody has serviced"},
}
const PROTECTION := {
	"detection": {"label": "Smoke and leak detection", "cost": 900, "service": 40,
		"blurb": "Finds it in the cycle it starts instead of the cycle it spreads."},
	"suppression": {"label": "Gas suppression", "cost": 2600, "service": 60,
		"blurb": "Puts a fire out and shuts the affected cabinets down doing it."},
	"drainage": {"label": "Under-floor drainage", "cost": 1100, "service": 50,
		"blurb": "Water goes somewhere other than into the bottom of a rack."},
}

func protection_key(kind: String, site := -1) -> String:
	## Fitted in a room, not in a company. An existing save keeps what it paid
	## for on the floor it bought it for.
	var idx := current_site if site < 0 else site
	if idx == 0 and protection.has(kind):
		return kind
	return kind if idx == 0 else "%d|%s" % [idx, kind]

func protection_fitted(kind: String, site := -1) -> bool:
	return bool(protection.get(protection_key(kind, site), {}).get("installed", false))

func protection_ready(kind: String, site := -1) -> bool:
	var p: Dictionary = protection.get(protection_key(kind, site), {})
	if p.is_empty() or not bool(p.get("installed", false)):
		return false
	# installed is not the same as maintained
	return cycle - int(p.get("serviced_cycle", -999)) <= int(PROTECTION[kind]["service"])

func buy_protection(kind: String) -> String:
	if not PROTECTION.has(kind):
		return "there is no such system"
	if protection_fitted(kind):
		return "%s is already fitted on this floor" % PROTECTION[kind]["label"]
	if not spend_on("fire and water protection", int(PROTECTION[kind]["cost"])):
		return "%s costs $%d" % [PROTECTION[kind]["label"], int(PROTECTION[kind]["cost"])]
	protection[protection_key(kind)] = {"installed": true, "serviced_cycle": cycle}
	log_event("FACILITY: %s fitted. It is only worth what its last inspection says it is."
		% PROTECTION[kind]["label"])
	return ""

func service_protection(kind: String) -> String:
	if not protection_fitted(kind):
		return "that is not fitted on this floor"
	if not spend_on("facility", int(PROTECTION[kind]["cost"]) / 6):
		return "the inspection costs $%d" % (int(PROTECTION[kind]["cost"]) / 6)
	protection[protection_key(kind)]["serviced_cycle"] = cycle
	log_event("FACILITY: %s inspected and signed off." % PROTECTION[kind]["label"])
	return ""

func hazard_risk(r: Net.Rack) -> float:
	## Everything here is something the player can already see: heat, an
	## overloaded feed, ageing hardware, and cooling nobody has serviced.
	var risk := 0.0
	if rack_hot(r):
		risk += 0.5
	risk += 0.2 * clampf(float(rack_heat(r)) / maxf(1.0, float(rack_cooling(r))) - 0.7, 0.0, 1.0)
	var oldest := 0
	for d in r.slots:
		if d != null:
			oldest = maxi(oldest, device_age(d))
	risk += 0.25 * clampf(float(oldest - 60) / 80.0, 0.0, 1.0)
	risk += 0.25 * clampf(float(facility_overdue("aircon", int(r.site))) / 60.0, 0.0, 1.0)
	if not bool(site_feeds(int(r.site)).get("A", true)) or not bool(site_feeds(int(r.site)).get("B", true)):
		risk += 0.15
	return clampf(risk, 0.0, 1.0)

func start_hazard(r: Net.Rack, kind: String) -> Dictionary:
	var haz := {"kind": kind, "rack": r.name, "site": int(r.site), "tile": [r.tile.x, r.tile.y],
		"severity": 1, "started": cycle, "detected": protection_ready("detection", int(r.site)),
		"zone": [r.name]}
	hazards.append(haz)
	if bool(haz["detected"]):
		log_event("ALARM: %s detected in %s. The panel found it in the cycle it started."
			% [HAZARD_KINDS[kind]["label"], r.name])
		Sfx.play("alert")
	else:
		log_event("SOMETHING IS WRONG in %s, and nothing on this floor is watching for it."
			% r.name)
	record_incident("hazard", "%s in %s" % [HAZARD_KINDS[kind]["label"], r.name])
	return haz

func _hazard_rack(name: String) -> Net.Rack:
	for r: Net.Rack in racks:
		if r.name == name:
			return r
	return null

func visitor_tick() -> void:
	for v in visitors.duplicate():
		if cycle - int(v["since"]) >= 3:
			visitor_leaves(String(v["name"]))

func hazard_tick() -> void:
	## Ignition is a slow function of visible risk, and Apprentice difficulty
	## keeps a floor under how bad it can get.
	if guided_outage_active():
		return  # the teaching incident owns the floor while it is running
	if hazards.is_empty() and stage >= 1:
		for r: Net.Rack in racks_on(current_site):
			var risk := hazard_risk(r)
			if risk < 0.5 or biz_roll() > 0.02 * risk * fault_scale():
				continue
			var kind := "water" if facility_overdue("aircon") > 40 else "smoke"
			start_hazard(r, kind)
			break
	for haz in hazards.duplicate():
		var rack := _hazard_rack(String(haz["rack"]))
		if rack == null:
			hazards.erase(haz)
			continue
		var haz_site := int(haz.get("site", 0))
		if not bool(haz["detected"]) and protection_ready("detection", haz_site):
			haz["detected"] = true
			log_event("ALARM: the panel has picked up the %s in %s."
				% [HAZARD_KINDS[haz["kind"]]["label"], haz["rack"]])
		var responded := false
		if String(haz["kind"]) in ["smoke", "fire"] and protection_ready("suppression", haz_site) \
				and bool(haz["detected"]):
			responded = true
			for d in rack.slots:
				if d != null and d.status == "active":
					d.status = "offline"  # suppression shuts the cabinet down doing its job
			log_event("SUPPRESSION: the system discharged in %s. Everything in that cabinet is down, and the building is not on fire."
				% haz["rack"])
		elif String(haz["kind"]) == "water" and protection_ready("drainage", haz_site) \
				and bool(haz["detected"]):
			responded = true
			log_event("DRAINAGE: the water went under the floor and out, which is what it is for.")
		if responded:
			hazards.erase(haz)
			topology_changed.emit()
			continue
		# nobody is dealing with it: it gets worse on a schedule you can watch
		if Staff.anyone_on_shift() and bool(haz["detected"]) and biz_roll() < 0.4:
			hazards.erase(haz)
			log_event("RESPONSE: the crew dealt with the %s in %s by hand."
				% [HAZARD_KINDS[haz["kind"]]["label"], haz["rack"]])
			continue
		haz["severity"] = int(haz["severity"]) + 1
		var cap := 3 if difficulty == 0 else 5  # Apprentice keeps a floor under it
		if int(haz["severity"]) > cap:
			haz["severity"] = cap
		if String(haz["kind"]) == "smoke" and int(haz["severity"]) >= 3:
			haz["kind"] = "fire"
			log_event("FIRE: the smoke in %s has become a fire." % haz["rack"])
		match String(HAZARD_KINDS[haz["kind"]]["damage"]):
			"power":
				for d in rack.slots:
					if d != null and d.status == "active":
						d.status = "offline"
						log_event("HAZARD: %s in %s took %s down."
							% [HAZARD_KINDS[haz["kind"]]["label"], haz["rack"], d.name])
						break
			"device":
				for d in rack.slots:
					if d != null:
						# it goes, and so does every cable that was in it
						uninstall_device(d, false)
						log_event("LOST: %s did not survive the fire in %s." % [d.name, haz["rack"]])
						break
		topology_changed.emit()

## Decisions where both answers are defensible and the bill arrives later.
const DECISIONS := [
	{"id": "vendor_early_swap", "title": "An early replacement, cheap",
		"text": "Your vendor will swap the ageing gear now at a discount, or you can wait two months for the revision that fixes the known fault.",
		"facts": ["the discount is real money now", "the current revision has a defect they have admitted to"],
		"options": [
			{"label": "Take the cheap swap now", "effect": "swap_now"},
			{"label": "Wait for the fixed revision", "effect": "swap_wait"}]},
	{"id": "emergency_work", "title": "Work outside the window",
		"text": "A customer wants a change done tonight, outside any agreed window, because their launch moved.",
		"facts": ["you have no window open", "refusing is defensible and they will not enjoy it"],
		"options": [
			{"label": "Do it tonight", "effect": "emergency_yes"},
			{"label": "Hold them to the process", "effect": "emergency_no"}]},
	{"id": "workaround_vs_root", "title": "A workaround or the root cause",
		"text": "Your engineers disagree: ship the workaround this afternoon, or spend two cycles fixing what actually causes it.",
		"facts": ["the workaround genuinely works", "the cause will still be there afterwards"],
		"options": [
			{"label": "Ship the workaround", "effect": "workaround"},
			{"label": "Fix the cause properly", "effect": "root_cause"}]},
	{"id": "carrier_lock", "title": "A long carrier contract",
		"text": "A carrier offers a long fixed-price contract, and their salesperson is unusually keen about it.",
		"facts": ["fixed price for a long time", "they know something about where prices are going"],
		"options": [
			{"label": "Sign the long contract", "effect": "carrier_sign"},
			{"label": "Stay on the current terms", "effect": "carrier_wait"}]},
	{"id": "press_early", "title": "A journalist, before the postmortem",
		"text": "A trade journalist wants a comment on last week's outage. The review is not finished.",
		"facts": ["you do not yet know the cause", "silence is also a quote"],
		"options": [
			{"label": "Comment now", "effect": "press_now"},
			{"label": "Wait for the postmortem", "effect": "press_wait"}]},
	{"id": "poach_engineer", "title": "Somebody else's engineer",
		"text": "An engineer at a competitor wants to come to you, and hints they would bring work with them.",
		"facts": ["they are good", "their employer will notice, and so will the industry"],
		"options": [
			{"label": "Hire them", "effect": "poach_yes"},
			{"label": "Turn them down politely", "effect": "poach_no"}]},
	{"id": "bulk_parts", "title": "A pallet of cheap optics",
		"text": "A broker has a pallet of optics at a third of list price, no warranty, no questions.",
		"facts": ["your drawer is never full enough", "third-party optics are where dirty-optic faults come from"],
		"options": [
			{"label": "Buy the pallet", "effect": "optics_yes"},
			{"label": "Pay list price for known parts", "effect": "optics_no"}]},
	{"id": "overtime_push", "title": "A long week",
		"text": "You can hit the delivery date by working the crew hard for a week.",
		"facts": ["the date is real", "so is the exhaustion afterwards"],
		"options": [
			{"label": "Push for the date", "effect": "overtime_yes"},
			{"label": "Move the date", "effect": "overtime_no"}]},
	{"id": "customer_discount", "title": "A discount for an early renewal",
		"text": "A large customer will renew early, for less money per cycle.",
		"facts": ["a longer term is worth something", "so is the revenue you would give up"],
		"options": [
			{"label": "Take the early renewal", "effect": "discount_yes"},
			{"label": "Hold your price", "effect": "discount_no"}]},
	{"id": "insurance_upsell", "title": "Better cover, more premium",
		"text": "Your broker offers hardware cover at a higher premium after seeing your estate's age.",
		"facts": ["your gear is getting old", "premiums are certain and failures are not"],
		"options": [
			{"label": "Take the cover", "effect": "insure_yes"},
			{"label": "Carry the risk yourself", "effect": "insure_no"}]},
	{"id": "intern_program", "title": "A junior nobody else will take",
		"text": "A local college asks whether you would take somebody with no experience at all.",
		"facts": ["they cost money before they are useful", "they learn from whatever they watch you do"],
		"options": [
			{"label": "Take them on", "effect": "intern_yes"},
			{"label": "Not this year", "effect": "intern_no"}]},
	{"id": "green_power", "title": "A cleaner tariff",
		"text": "The utility offers a renewable tariff at a premium, and a certificate customers can see.",
		"facts": ["it costs more per watt", "some customers genuinely care"],
		"options": [
			{"label": "Switch tariff", "effect": "green_yes"},
			{"label": "Stay on the cheap tariff", "effect": "green_no"}]},
]

func decision_by_id(id: String) -> Dictionary:
	for d: Dictionary in DECISIONS:
		if String(d["id"]) == id:
			return d
	return {}

func maybe_offer_decision() -> void:
	if decisions.size() >= 2 or cycle < 12 or biz_roll() > 0.08:
		return
	var pool: Array = []
	for d: Dictionary in DECISIONS:
		if String(d["id"]) not in decisions_seen:
			pool.append(d)
	if pool.is_empty():
		decisions_seen = []  # the deck comes round again
		pool = DECISIONS.duplicate()
	var pick: Dictionary = pool[int(biz_roll() * pool.size()) % pool.size()]
	decisions_seen.append(String(pick["id"]))
	decisions.append({"id": String(pick["id"]), "raised": cycle})
	log_event("DECISION: %s. %s" % [pick["title"], pick["text"]])

func schedule_consequence(after: int, kind: String, note: String, data := {}) -> void:
	## Foreshadowed on purpose: the player is told something will come of this.
	consequences.append({"cycle": cycle + after, "kind": kind, "note": note, "data": data})
	log_event("LATER: %s" % note)

func decide(id: String, option: int) -> String:
	var spec := decision_by_id(id)
	if spec.is_empty():
		return "there is no such decision"
	var live := {}
	for d in decisions:
		if String(d["id"]) == id:
			live = d
	if live.is_empty():
		return "that decision is not open"
	decisions.erase(live)
	var effect := String(spec["options"][clampi(option, 0, spec["options"].size() - 1)]["effect"])
	_apply_decision(effect)
	return ""

func _apply_decision(effect: String) -> void:
	match effect:
		"swap_now":
			money -= 900
			money_changed.emit()
			latent_defects["sw-8"] = int(latent_defects.get("sw-8", 0)) + 1
			schedule_consequence(10, "note", "the discounted units carry the fault the vendor admitted to")
		"swap_wait":
			schedule_consequence(8, "spares", "the fixed revision arrives, and one lands on your shelf")
		"emergency_yes":
			for deal in deals:
				deal["loyalty"] = minf(1.0, float(deal.get("loyalty", 0.6)) + 0.05)
			schedule_consequence(3, "risk", "unplanned work has a way of surfacing a few cycles later")
		"emergency_no":
			for deal in deals:
				deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - 0.05)
			reputation = mini(100, reputation + 2)
		"workaround":
			money += 400
			money_changed.emit()
			schedule_consequence(12, "incident", "the cause you did not fix is still there")
		"root_cause":
			money -= 300
			money_changed.emit()
			reputation = mini(100, reputation + 2)
		"carrier_sign":
			schedule_consequence(14, "money", "the fixed carrier price is now below the market", {"amount": 1200})
		"carrier_wait":
			schedule_consequence(14, "money", "carrier prices moved the way their salesperson expected", {"amount": -800})
		"press_now":
			reputation = mini(100, reputation + 3)
			schedule_consequence(6, "press_risk", "you said something before you knew the cause")
		"press_wait":
			reputation = maxi(0, reputation - 1)
			schedule_consequence(6, "reputation", "the postmortem lands, and it reads well", {"amount": 4})
		"poach_yes":
			var rng := RandomNumberGenerator.new()
			rng.seed = cycle
			var hire := Staff.make_candidate(rng)
			hire["skill"] = 5
			hire["name"] = "Szabo Marta"
			staff.append(hire)
			for r in rivals:
				Rivals.remember(r, -2, "you took their engineer")
				break
		"poach_no":
			reputation = mini(100, reputation + 2)
			for r2 in rivals:
				Rivals.remember(r2, 1, "you did not take their engineer")
				break
		"optics_yes":
			parts["optic"] = parts_of("optic") + 20
			money -= 300
			money_changed.emit()
			schedule_consequence(9, "grey", "cheap optics are where dirty-optic faults come from")
		"optics_no":
			money -= 900
			parts["optic"] = parts_of("optic") + 20
			money_changed.emit()
		"overtime_yes":
			money += 800
			money_changed.emit()
			schedule_consequence(4, "morale", "the week you asked for catches up with everybody", {"amount": -18})
		"overtime_no":
			schedule_consequence(4, "morale", "a crew that was not run into the ground", {"amount": 6})
		"discount_yes":
			for deal in deals:
				deal["fee"] = maxi(1, int(float(int(deal["fee"])) * 0.9))
				deal["term"] = int(deal.get("term", 18)) + 12
				deal["loyalty"] = minf(1.0, float(deal.get("loyalty", 0.6)) + 0.15)
				break
		"discount_no":
			for deal in deals:
				deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - 0.1)
				break
		"insure_yes":
			insured = true
			schedule_consequence(10, "note", "the premium is being paid whether anything fails or not")
		"insure_no":
			insured = false
			schedule_consequence(10, "hardware", "an unlucky failure with nothing behind it")
		"intern_yes":
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = cycle + 7
			var junior := Staff.make_candidate(rng2)
			junior["skill"] = 1
			junior["salary"] = 120
			junior["name"] = "Kis Andras"
			staff.append(junior)
			schedule_consequence(15, "skill", "the junior you took on has been watching you work")
		"intern_no":
			pass
		"green_yes":
			marketing += 40
			reputation = mini(100, reputation + 3)
			schedule_consequence(12, "reputation", "customers who asked about the tariff signed", {"amount": 3})
		"green_no":
			pass

func consequence_tick() -> void:
	for c in consequences.duplicate():
		if cycle < int(c["cycle"]):
			continue
		consequences.erase(c)
		match String(c["kind"]):
			"money":
				money += int(c["data"].get("amount", 0))
				money_changed.emit()
			"reputation":
				reputation = clampi(reputation + int(c["data"].get("amount", 0)), 0, 100)
			"morale":
				for m in staff:
					m["morale"] = clampi(int(m.get("morale", 70)) + int(c["data"].get("amount", 0)),
						0, 100)
			"spares":
				spares["sw-8"] = int(spares.get("sw-8", 0)) + 1
			"incident":
				record_incident("decision", "the workaround you shipped has come back")
				reputation = maxi(0, reputation - 3)
			"press_risk":
				reputation = clampi(reputation + (-5 if randf() < 0.5 else 3), 0, 100)
			"grey":
				for l: Net.Link in links:
					if grey_fault(l.a).is_empty() and l.a.enabled:
						inject_grey_fault(l.a, "dirty_optic")
						break
			"hardware":
				for d: Net.NDevice in all_devices():
					if d.status == "active" and d.type != "cooling":
						d.status = "offline"
						record_incident("hardware", "%s failed, uninsured" % d.name)
						break
			"risk":
				if randf() < 0.4:
					record_incident("decision", "the unplanned work came back as an incident")
					reputation = maxi(0, reputation - 2)
			"skill":
				for m2 in staff:
					if int(m2.get("skill", 1)) <= 2:
						m2["skill"] = int(m2["skill"]) + 1
						break
			"note":
				pass
		log_event("CONSEQUENCE: %s." % c["note"])
		record_timeline_note(String(c["note"]))

func record_timeline_note(text: String) -> void:
	decision_notes.append("cycle %d · %s" % [cycle, text])
	if decision_notes.size() > 12:
		decision_notes.pop_front()

## A teaching abstraction, not any real certification scheme: eight controls
## that map onto things the simulation can actually prove.
const CONTROLS := [
	{"id": "segmentation", "label": "Tenant segmentation",
		"blurb": "Customer machines sit in their own VLAN rather than the default one."},
	{"id": "mgmt_isolation", "label": "Management isolation",
		"blurb": "Nothing a customer runs can reach the management plane."},
	{"id": "central_auth", "label": "Central administrative authentication",
		"blurb": "Admin logins are authenticated somewhere central, with an audit trail."},
	{"id": "logging_time", "label": "Logging and time synchronisation",
		"blurb": "Devices ship logs somewhere and agree what time it is."},
	{"id": "config_history", "label": "Configuration history",
		"blurb": "What is running is saved, and previous versions still exist."},
	{"id": "physical_access", "label": "Physical and out-of-band access",
		"blurb": "There is a way in when the network is the problem, and the floor is documented."},
	{"id": "incident_review", "label": "Incident review",
		"blurb": "Incidents are written up rather than left open."},
	{"id": "failover", "label": "Proved failover",
		"blurb": "The redundancy has been tested on purpose, recently, and it held."},
	{"id": "patching", "label": "Maintenance and known defects",
		"blurb": "Nothing is running on a lapsed licence or a known unfixed defect."},
]
const EVIDENCE_STALE := 12  # cycles after which evidence needs collecting again

func control_devices() -> Array:
	return all_devices()

func control_state(id: String) -> Dictionary:
	## Every control is answered by the live simulation. Nothing here can be
	## satisfied by a checkbox somewhere in the interface.
	var passing := false
	var why := ""
	match id:
		"failover":
			var proved := int(control_evidence.get("failover", -999))
			passing = proved > 0 and cycle - proved <= EVIDENCE_STALE * 2
			why = "no failover test has been passed" if proved <= 0 else \
				"last passed at cycle %d" % proved
		"segmentation":
			var tenanted := 0
			for d: Net.NDevice in control_devices():
				if d.type != "switch":
					continue
				for i: Net.Iface in d.ifaces:
					if i.mode == "access" and link_at(i) != null and int(i.untagged_vlan) > 1:
						tenanted += 1
			passing = tenanted >= 2
			why = "%d customer port(s) in a VLAN of their own" % tenanted
		"mgmt_isolation":
			var exposed := 0
			for deal in deals:
				var ip: String = deal["params"].get("ip", "")
				var srv := Contracts._owner(ip) if ip != "" else null
				if srv == null:
					continue
				for d: Net.NDevice in control_devices():
					if not d.ip_forwarding and d.type != "switch":
						continue
					for mgmt: String in management_ips(d):
						if Sim.ping(srv, mgmt)["ok"]:
							exposed += 1
			passing = exposed == 0
			why = "no customer machine reaches the management plane" if passing \
				else "%d customer-to-management path(s) open" % exposed
		"central_auth":
			for d: Net.NDevice in control_devices():
				if not d.aaa.is_empty() and String(d.aaa.get("server", "")) != "":
					passing = true
			why = "an authentication server is configured" if passing \
				else "every device authenticates locally"
		"logging_time":
			var logged := 0
			var timed := 0
			for d: Net.NDevice in control_devices():
				if d.log_host != "":
					logged += 1
				if d.ntp_server != "":
					timed += 1
			passing = logged > 0 and timed > 0
			why = "%d device(s) shipping logs, %d with a clock source" % [logged, timed]
		"config_history":
			var dirty := 0
			var versioned := 0
			for d: Net.NDevice in control_devices():
				if config_dirty(d):
					dirty += 1
				if d.versions.size() > 0:
					versioned += 1
			passing = dirty == 0 and versioned > 0
			why = "%d unsaved configuration(s), %d device(s) with history" % [dirty, versioned]
		"physical_access":
			var console := false
			var badged := access_policy != "open"
			for d: Net.NDevice in control_devices():
				if d.type == "console" and d.status == "active":
					console = true
			passing = console and badged and drift_factor() < 0.4
			why = "%s, access %s, documentation %s" % ["a console server is on the floor" if console
				else "no out-of-band access", "controlled" if badged else "open to the building",
				"current" if drift_factor() < 0.4 else "adrift"]
		"incident_review":
			var open_old := 0
			for inc: Dictionary in incidents:
				if not bool(inc.get("reviewed", false)) and cycle - int(inc.get("cycle", cycle)) >= 5:
					open_old += 1
			passing = open_old == 0
			why = "%d incident(s) still unwritten after five cycles" % open_old
		"patching":
			var lapsed := 0
			for item: Dictionary in renewals:
				if bool(item.get("lapsed", false)):
					lapsed += 1
			passing = lapsed == 0 and firmware_bugs.is_empty()
			why = "%d lapsed renewal(s), %d known defect(s) open" % [lapsed, firmware_bugs.size()]
	if passing:
		control_evidence[id] = cycle
	var last := int(control_evidence.get(id, -999))
	var status := "failing"
	if passing:
		status = "compliant"
	elif last > -999 and cycle - last <= EVIDENCE_STALE:
		status = "stale"
	elif last > -999:
		status = "incomplete"
	return {"id": id, "status": status, "why": why, "evidence_cycle": last}

func audit_readiness() -> Array:
	var out: Array = []
	for c: Dictionary in CONTROLS:
		var st := control_state(String(c["id"]))
		st["label"] = c["label"]
		st["blurb"] = c["blurb"]
		out.append(st)
	return out

func maybe_offer_audit() -> void:
	if not audit.is_empty() or deals.is_empty() or cycle < 40 or biz_roll() > 0.02:
		return
	var scope: Array = []
	var pool: Array = CONTROLS.duplicate()
	for i in 4:
		var pick: Dictionary = pool[int(biz_roll() * pool.size()) % pool.size()]
		if String(pick["id"]) not in scope:
			scope.append(String(pick["id"]))
	var customer := String(deals[int(biz_roll() * deals.size()) % deals.size()]["customer"])
	audit = {"state": "offered", "customer": customer, "scope": scope, "reward": 4500,
		"deadline": cycle + 10, "findings": [], "history": []}
	log_event("AUDIT OFFERED: %s wants a compliance review of %s, worth $%d if you pass. This is a teaching abstraction, not a real certification."
		% [customer, ", ".join(PackedStringArray(scope)), int(audit["reward"])])

func accept_audit() -> String:
	if audit.get("state", "") != "offered":
		return "there is nothing on the table"
	audit["state"] = "accepted"
	log_event("AUDIT ACCEPTED: %s samples %d control(s) at cycle %d. The scope is fixed from now on."
		% [audit["customer"], audit["scope"].size(), int(audit["deadline"])])
	return ""

func delay_audit() -> String:
	if audit.get("state", "") != "offered":
		return "there is nothing to move"
	audit["deadline"] = cycle + 20
	audit["state"] = "accepted"
	reputation = maxi(0, reputation - 3)
	for deal in deals:
		if String(deal["customer"]) == String(audit["customer"]):
			deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - 0.1)
	log_event("AUDIT DELAYED: %s moved the window out, and noticed that you asked."
		% audit["customer"])
	return ""

func decline_audit() -> String:
	if audit.get("state", "") != "offered":
		return "there is nothing to decline"
	log_event("AUDIT DECLINED: %s will take their compliance work elsewhere." % audit["customer"])
	for deal in deals:
		if String(deal["customer"]) == String(audit["customer"]):
			deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - 0.15)
	audit = {}
	return ""

func _audit_sample() -> Array:
	var findings: Array = []
	for id: String in audit["scope"]:
		var st := control_state(id)
		var grade := "pass"
		match String(st["status"]):
			"failing":
				grade = "major finding"
			"incomplete":
				grade = "minor finding"
			"stale":
				grade = "observation"
		findings.append({"control": id, "grade": grade, "why": st["why"]})
	return findings

func run_audit() -> void:
	if audit.get("state", "") != "accepted" or cycle < int(audit["deadline"]):
		return
	audit["findings"] = _audit_sample()
	audit["state"] = "findings"
	audit["remediation_until"] = cycle + 8
	var majors := 0
	for f: Dictionary in audit["findings"]:
		if String(f["grade"]) == "major finding":
			majors += 1
	log_event("AUDIT RESULT: %d finding(s), %d of them major. You have 8 cycles to remediate before it closes."
		% [audit["findings"].size(), majors])
	for f2: Dictionary in audit["findings"]:
		log_event("AUDIT %s: %s (%s)" % [String(f2["grade"]).to_upper(), f2["control"], f2["why"]])

func verify_audit() -> String:
	## The same controls, re-checked against the live network. Nothing moves.
	if audit.get("state", "") != "findings":
		return "there is nothing to verify"
	audit["findings"] = _audit_sample()
	var majors := 0
	for f: Dictionary in audit["findings"]:
		if String(f["grade"]) == "major finding":
			majors += 1
	if majors > 0:
		log_event("AUDIT REVERIFICATION: %d major finding(s) still open." % majors)
		return "%d major finding(s) are still open" % majors
	audit["state"] = "closed"
	trust_marker = true
	money += int(audit["reward"])
	money_changed.emit()
	reputation = mini(100, reputation + 6)
	leads.append(Market.audit_lead(String(audit["customer"])))
	log_event("AUDIT PASSED: $%d, a visible trust marker, and the kind of customer who asks for this now has your number."
		% int(audit["reward"]))
	audit = {}  # the next auditor can now be offered; the marker is what stays
	return ""

func audit_tick() -> void:
	maybe_offer_audit()
	if audit.get("state", "") == "accepted" and cycle >= int(audit["deadline"]):
		run_audit()
	elif audit.get("state", "") == "findings" and cycle > int(audit.get("remediation_until", 0)):
		var majors := 0
		for f: Dictionary in audit["findings"]:
			if String(f["grade"]) == "major finding":
				majors += 1
		if majors > 0:
			reputation = maxi(0, reputation - 5)
			log_event("AUDIT CLOSED: the remediation window ran out with %d major finding(s) open."
				% majors)
		audit = {}

const TOUR_KINDS := {
	"prospect": {"label": "a prospective enterprise customer",
		"cares": "how the floor looks and whether the racks look deliberate",
		"weights": {"tidy": 0.5, "deliberate": 0.35, "docs": 0.15}},
	"investor": {"label": "an investor",
		"cares": "whether this looks like a business or a hobby",
		"weights": {"tidy": 0.35, "deliberate": 0.35, "docs": 0.3}},
	"auditor": {"label": "an auditor",
		"cares": "documentation, records and what you can prove",
		"weights": {"docs": 0.6, "records": 0.4}},
	"press": {"label": "a journalist",
		"cares": "the picture they will publish",
		"weights": {"tidy": 0.6, "deliberate": 0.4}},
}

func tour_factor(name: String) -> float:
	## Every input is something a visitor could actually see or ask for.
	match name:
		"tidy":
			# open crates and cardboard in the aisle are the first thing anybody sees
			return clampf(floor_tidiness() - 0.15 * float(packaging)
				- (0.2 if aisle_blocked() else 0.0), 0.0, 1.0)
		"deliberate":
			var racked := 0
			var orphaned := 0
			for r: Net.Rack in racks_on(current_site):
				for d in r.slots:
					if d == null:
						continue
					racked += 1
					var cabled := false
					for i: Net.Iface in d.ifaces:
						if link_at(i) != null:
							cabled = true
					if not cabled:
						orphaned += 1
			return 1.0 if racked == 0 else clampf(1.0 - float(orphaned) / float(racked), 0.0, 1.0)
		"docs":
			var devs := all_devices()
			if devs.is_empty():
				return 1.0
			var documented := 0
			for d: Net.NDevice in devs:
				if not d.note.is_empty() and not config_dirty(d):
					documented += 1
			return clampf(float(documented) / float(devs.size()) - drift_factor(), 0.0, 1.0)
		"records":
			var open_reviews := 0
			for inc: Dictionary in incidents:
				if not bool(inc.get("reviewed", false)):
					open_reviews += 1
			var score := 1.0 - 0.15 * float(open_reviews) - 0.2 * float(audit_findings().size())
			return clampf(score, 0.0, 1.0)
	return 0.5

func tour_score(kind: String) -> float:
	var weights: Dictionary = TOUR_KINDS[kind]["weights"]
	var total := 0.0
	for name: String in weights:
		total += float(weights[name]) * tour_factor(name)
	return clampf(total + float(tour.get("crammed", 0.0)), 0.0, 1.0)

func maybe_schedule_tour() -> void:
	if not tour.is_empty() or deals.is_empty() or cycle < 30 or biz_roll() > 0.03:
		return
	var kinds: Array = TOUR_KINDS.keys()
	var kind: String = kinds[int(biz_roll() * kinds.size()) % kinds.size()]
	tour = {"kind": kind, "cycle": cycle + 5, "crammed": 0.0}
	log_event("VISIT BOOKED: %s is walking the floor in 5 cycles. They care about %s."
		% [TOUR_KINDS[kind]["label"], TOUR_KINDS[kind]["cares"]])

func cram_for_tour() -> String:
	## A frantic tidy-up before a visit. It helps, and it cannot fake months.
	if tour.is_empty():
		return "nobody is coming"
	if float(tour.get("crammed", 0.0)) >= 0.1:
		return "the place is as presentable as money can make it today"
	if not spend_on("visit preparation", 600):
		return "a crew at this notice costs $600"
	tour["crammed"] = 0.1
	log_event("SCRAMBLE: cleaners, cable ties and a skip, at short notice and full price. It will show, a little.")
	return ""

func tour_tick() -> void:
	if tour.is_empty() or cycle < int(tour["cycle"]):
		return
	var kind := String(tour["kind"])
	var score := tour_score(kind)
	tour = {}
	var verdict := "impressed" if score >= 0.7 else ("unconvinced" if score >= 0.45 else "alarmed")
	log_event("VISIT: %s walked the floor and left %s (%d%%)."
		% [TOUR_KINDS[kind]["label"], verdict, int(score * 100.0)])
	match kind:
		"prospect":
			if score >= 0.7:
				leads.append(Market.tour_lead(true))
				log_event("VISIT RESULT: they want a quote, on their terms and at their size. A floor that looks run wins work.")
			elif score >= 0.45:
				leads.append(Market.tour_lead(false))
			else:
				reputation = maxi(0, reputation - 2)
				log_event("VISIT RESULT: they will not be sending anything here. You could see them deciding it in the aisle.")
		"investor":
			if score >= 0.7:
				money += 6000
				money_changed.emit()
				log_event("VISIT RESULT: a $6000 tranche, because it looks like a business rather than a hobby.")
			else:
				log_event("VISIT RESULT: no money. They have seen enough rooms to know what a tidy one means.")
		"auditor":
			if score >= 0.6:
				reputation = mini(100, reputation + 5)
				log_event("VISIT RESULT: no findings. Everything you claimed, you could show.")
			else:
				reputation = maxi(0, reputation - 6)
				money -= 900
				money_changed.emit()
				record_incident("audit", "an audit found documentation and records wanting")
				log_event("VISIT RESULT: findings raised and $900 of remediation. You could not show what you said you did.")
		"press":
			reputation = clampi(reputation + (4 if score >= 0.7 else -4), 0, 100)
			log_event("VISIT RESULT: the photograph they chose is %s."
				% ("a room that looks run" if score >= 0.7 else "the cable spaghetti behind rack one"))

const FACILITY_TASKS := {
	"filters": {"label": "Dust filter change", "every": 40, "cost": 120,
		"blurb": "Clogged filters cost you cooling headroom before they cost you anything else."},
	"aircon": {"label": "Aircon service visit", "every": 60, "cost": 450,
		"blurb": "A contractor on the floor for an afternoon. Unserviced units fail sooner."},
	"generator": {"label": "Generator load test", "every": 80, "cost": 260,
		"blurb": "A deliberate transfer to backup power. It can go wrong, which is the point of doing it."},
	"ups": {"label": "UPS battery check", "every": 50, "cost": 90,
		"blurb": "Batteries die quietly and are discovered loudly."},
}

func facility_key(task: String, site := -1) -> String:
	## One diary per floor. An existing save keeps its plain keys, which belong
	## to the floor it was keeping them on, and every other site gets its own.
	var idx := current_site if site < 0 else site
	if idx == 0 and facility.has(task):
		return task
	return task if idx == 0 else "%d|%s" % [idx, task]

func facility_due_in(task: String, site := -1) -> int:
	var key := facility_key(task, site)
	if not facility.has(key):
		facility[key] = cycle  # the schedule starts the first time anyone looks at it
	return int(facility[key]) + int(FACILITY_TASKS[task]["every"]) - cycle

func facility_overdue(task: String, site := -1) -> int:
	return maxi(0, -facility_due_in(task, site))

func filter_dirt(site := -1) -> float:
	## Neglect degrades along a curve the player can watch, not a coin flip.
	return clampf(float(facility_overdue("filters", site)) / 120.0, 0.0, 1.0)

func heat_wave() -> bool:
	return cycle <= heat_wave_until

func devices_on(site := -1) -> Array:
	## Everything racked on one floor. Heat and power are properties of a room.
	var idx := current_site if site < 0 else site
	var out: Array = []
	for r: Net.Rack in racks_on(idx):
		for d in r.slots:
			if d != null and d not in out:
				out.append(d)
	return out

func cooling_capacity(site := -1) -> int:
	var c := BASE_COOLING
	for d in devices_on(site):
		if d.type == "cooling" and d.status == "active":
			c += int(MODELS[d.model].get("cools", 0))
	c = int(round(float(c) * (1.0 - 0.2 * filter_dirt(site))))  # dirty filters cost headroom first
	if stage >= 1:
		# in somebody else's colo the cooling is their problem; in your own room
		# the outside air is part of it
		c = int(round(float(c) * season_cooling()))
	if heat_wave():
		c = int(round(float(c) * 0.9))  # the outside air is against you this week
	return maxi(BASE_COOLING / 4, c)

func service_facility(task: String) -> String:
	if not FACILITY_TASKS.has(task):
		return "there is no such job"
	var cost := int(FACILITY_TASKS[task]["cost"])
	if not spend_on("facility", cost):
		return "that costs $%d and you do not have it" % cost
	facility[facility_key(task)] = cycle
	if task == "generator":
		facility["generator_tests"] = int(facility.get("generator_tests", 0)) + 1
		# a real transfer to backup power, with the risk that goes with it
		if randf() < 0.12:
			for d in all_devices():
				if d.status == "active" and d.type != "cooling":
					d.status = "offline"
					log_event("GENERATOR TEST: the transfer dropped %s. That is what a test day is for: better today than during a real cut."
						% d.name)
					record_incident("facility", "a device did not survive the generator transfer")
					topology_changed.emit()
					break
		else:
			log_event("GENERATOR TEST: clean transfer to backup power and back. It will start when you need it.")
	else:
		if task == "aircon":
			admit_visitor("Vas Elektro", "aircon service")
		log_event("FACILITY: %s done for $%d." % [FACILITY_TASKS[task]["label"], cost])
	return ""

func generator_ready() -> bool:
	## An untested generator is a generator you are hoping about.
	return facility_overdue("generator") < 30

func facility_tick() -> void:
	## Seasonal pressure, delegated schedules, and the slow costs of neglect.
	if not heat_wave() and biz_roll() < 0.01:
		heat_wave_until = cycle + 5
		log_event("HEAT WAVE: the next few cycles are hot. Cooling headroom is down a tenth: a prepared floor will not notice.")
	for task: String in FACILITY_TASKS:
		if not bool(facility_auto.get(task, false)) or facility_due_in(task) > 0:
			continue
		if Game.staff.is_empty() or money < int(FACILITY_TASKS[task]["cost"]):
			continue
		service_facility(task)
	if facility_overdue("aircon") > 40 and randf() < 0.02:
		for d in all_devices():
			if d.type == "cooling" and d.status == "active":
				d.status = "offline"
				log_event("FACILITY: the unserviced cooling unit %s has failed. Nobody has looked at it in %d cycles."
					% [d.name, cycle - int(facility.get("aircon", 0))])
				record_incident("facility", "an unserviced cooling unit failed")
				topology_changed.emit()
				break
	if facility_overdue("ups") > 30 and int(ups.get(current_site, 0)) > 0 and randf() < 0.03:
		ups[current_site] = 0
		log_event("FACILITY: the UPS battery on %s was flat when it was needed. Nobody had checked it."
			% site_name(current_site))

func overheating(site := -1) -> bool:
	return stage >= 1 and power_draw(site) > cooling_capacity(site)

# ---------- airflow: where the heat is, not just how much ----------

const CRAC_REACH := 3.0  # tiles a cooling unit meaningfully serves
const CROWDING_PENALTY := 0.18  # extra heat per directly adjacent rack

func rack_watts(r: Net.Rack) -> int:
	var w := 0
	for d in r.slots:
		if d != null and d.status == "active":
			w += int(WATTS.get(d.model, 0))
	return w

func rack_heat(r: Net.Rack) -> int:
	## a rack's own draw, plus a penalty for every cabinet pressed against it.
	## Racks in a solid block recirculate each other's exhaust; an aisle is
	## what stops that, and an aisle is just an empty tile.
	var neighbours := 0
	for other in racks_on(r.site):
		if other == r:
			continue
		var off: Vector2i = other.tile - r.tile
		if absi(off.x) <= 1 and absi(off.y) <= 1:
			neighbours += 1
	var recirculation := 1.0 - rack_airflow_seal(r) * 0.08
	return int(round(float(rack_watts(r)) * (1.0 + CROWDING_PENALTY * neighbours) * recirculation))

func rack_airflow_seal(r: Net.Rack) -> float:
	## Blanks stop exhaust returning through unused U spaces. The reward is
	## intentionally small and capped: layout and actual cooling still matter.
	var gaps := 0
	var sealed := 0
	for idx in Net.Rack.SLOTS:
		if r.slots[idx] == null and not r.covered.has(idx):
			gaps += 1
			if r.blanked.has(idx):
				sealed += 1
	return 0.0 if gaps == 0 else float(sealed) / float(gaps)

func toggle_blanking(r: Net.Rack, idx: int) -> bool:
	if not slot_free(r, idx):
		return false
	if r.blanked.has(idx):
		r.blanked.erase(idx)
	else:
		if not take_part("blank"):
			log_event("BLOCKED: no blanking panels left in the drawer.")
			return false
		r.blanked[idx] = true
	observe_habit("tidy", r.blanked.get(idx, false))
	Sfx.play("cable")
	topology_changed.emit()
	return true

func deal_note_age(deal: Dictionary) -> int:
	var note: Dictionary = deal.get("note", {})
	return maxi(0, cycle - int(note.get("cycle", cycle))) if not note.is_empty() else 0

func set_deal_note(deal: Dictionary, text: String) -> void:
	## Customers get the same opaque note as everything else.
	text = text.strip_edges().left(140)
	if text == "":
		deal.erase("note")
	else:
		deal["note"] = {"text": text, "cycle": cycle}
	observe_habit("documents", text != "")

func incident_notes() -> Array:
	## Whatever past-you wrote on the things that are currently in trouble.
	var out: Array = []
	var seen := {}
	var trouble: Array = []
	for haz: Dictionary in hazards:
		var r := _hazard_rack(String(haz["rack"]))
		if r != null:
			trouble.append(r)
	for name: String in firmware_bugs:
		for d: Net.NDevice in all_devices():
			if d.name == name:
				trouble.append(d)
	for key: String in grey_faults:
		for d2: Net.NDevice in all_devices():
			for i: Net.Iface in d2.ifaces:
				if iface_key(i) == key:
					trouble.append(i)
	for d3: Net.NDevice in all_devices():
		if locked_out(d3) or d3.status != "active":
			trouble.append(d3)
	for deal in deals:
		if bool(deal.get("ever_healthy", false)) and not bool(deal.get("healthy", false)) \
				and not deal.get("note", {}).is_empty():
			out.append("%s: \"%s\" (written %d cycle(s) ago)" % [deal["customer"],
				deal["note"]["text"], deal_note_age(deal)])
	for thing in trouble:
		if seen.has(thing) or thing.note.is_empty():
			continue
		seen[thing] = true
		var label: String = String(thing.name) if not (thing is Net.Iface) \
			else "%s %s" % [(thing as Net.Iface).dev.name, (thing as Net.Iface).name]
		out.append("%s: \"%s\" (written %d cycle(s) ago)" % [label, thing.note["text"],
			note_age(thing)])
	return out

func set_note(target: Variant, text: String) -> void:
	## Notes are deliberately opaque. No keyword, date, or promise written here
	## ever changes the simulation; it is past-you talking to future-you.
	text = text.strip_edges().left(140)
	if text == "":
		target.note = {}
	else:
		target.note = {"text": text, "cycle": cycle}
	topology_changed.emit()
	observe_habit("documents", text.strip_edges() != "")
	if target is Net.Iface:
		observe_habit("tidy", text.strip_edges() != "")

func note_age(target: Variant) -> int:
	return maxi(0, cycle - int(target.note.get("cycle", cycle))) if not target.note.is_empty() else 0

func rack_cooling(r: Net.Rack) -> int:
	## cold air does not teleport: a unit on the far side of the room is worth
	## much less than one at the end of the row
	var total := float(BASE_COOLING) / maxf(1.0, float(racks_on(r.site).size()))
	for other in racks_on(r.site):
		for d in other.slots:
			if d == null or d.type != "cooling" or d.status != "active":
				continue
			var dist := Vector2(r.tile - other.tile).length()
			if dist > CRAC_REACH:
				continue
			total += float(MODELS[d.model].get("cools", 0)) * (1.0 - dist / (CRAC_REACH + 1.0))
	return int(round(total))

func rack_hot(r: Net.Rack) -> bool:
	return stage >= 1 and rack_heat(r) > rack_cooling(r)

func hottest_rack(site: int) -> Net.Rack:
	var worst: Net.Rack = null
	var worst_margin := -(1 << 30)
	for r in racks_on(site):
		var margin := rack_heat(r) - rack_cooling(r)
		if margin > worst_margin:
			worst_margin = margin
			worst = r
	return worst

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
	Sim.forget_mac(nic.mac)  # the moved machine announces itself from its new host
	stats["migrations"] = int(stats.get("migrations", 0)) + 1  # the log is trimmed; this is not
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

# ---------- invoicing and receivables ----------

func payment_terms(deal: Dictionary) -> int:
	## how many cycles this customer takes to pay. Big organisations are
	## slower, which is the trade you make when you sign one.
	match String(deal.get("ctype", "enterprise")):
		"startup":
			return 1
		"public":
			return 4
		"isp":
			return 3
	return 2

func raise_invoice(deal: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	var terms := payment_terms(deal)
	invoices.append({"customer": String(deal["customer"]), "deal": String(deal["id"]),
		"amount": amount, "raised": cycle, "due": cycle + terms, "chased": false})
	last_business["revenue"] = int(last_business.get("revenue", 0)) + amount
	last_business["invoiced"] = int(last_business.get("invoiced", 0)) + amount
	if bool(deal.get("guided", false)) and not deal.has("first_invoice_cycle"):
		deal["first_invoice_cycle"] = cycle
		deal["first_invoice_amount"] = amount
		customer_cash_changed.emit(String(deal["customer"]), "invoiced", amount)
		log_event("INVOICE: %s now owes $%d, due in %d cycle(s). Revenue is earned; cash has not arrived yet."
			% [deal["customer"], amount, terms])

func deal_by_id(id: String) -> Dictionary:
	for deal: Dictionary in deals:
		if String(deal.get("id", "")) == id:
			return deal
	return {}

func collect_invoices() -> int:
	## money that has actually landed this cycle, plus the ones that slipped
	var collected := 0
	for inv in invoices.duplicate():
		if int(inv["due"]) > cycle:
			continue
		var deal := deal_by_id(String(inv["deal"]))
		var guided_first_payment := not deal.is_empty() and bool(deal.get("guided", false)) \
			and not deal.has("first_cash_cycle")
		# a customer who has not been chased sometimes simply pays late
		if not guided_first_payment and not bool(inv["chased"]) and randf() < 0.18:
			inv["due"] = int(inv["due"]) + randi_range(1, 2)
			if not bool(inv.get("slipped", false)):
				inv["slipped"] = true
				log_event("LATE: %s has not paid the $%d they owe." % [inv["customer"], int(inv["amount"])])
			continue
		var amount := int(inv["amount"])
		collected += amount
		last_business["collected"] = int(last_business.get("collected", 0)) + amount
		if String(inv["deal"]).begins_with("contract:"):
			# campaign service fees keep their own line when the cash lands
			last_pl["service fees"] = int(last_pl.get("service fees", 0)) + amount
		if not deal.is_empty() and bool(deal.get("guided", false)) \
				and not deal.has("first_cash_cycle"):
			deal["first_cash_cycle"] = cycle
			deal["first_cash_amount"] = amount
			stats["guided_delivery_complete"] = 1
			customer_cash_changed.emit(String(deal["customer"]), "collected", amount)
			log_event("CASH: %s paid their first $%d invoice. The service stays live and keeps billing."
				% [deal["customer"], amount])
		invoices.erase(inv)
	for inv2 in invoices.duplicate():
		var deal2 := deal_by_id(String(inv2["deal"]))
		var expected := int(inv2.get("raised", int(inv2["due"]))) + (payment_terms(deal2) if not deal2.is_empty() else 0)
		if cycle - expected > WRITE_OFF_AFTER:
			invoices.erase(inv2)
			reputation = maxi(0, reputation - 2)
			log_event("WRITTEN OFF: $%d from %s is never arriving." % [int(inv2["amount"]), inv2["customer"]])
	var deal_cash := collected - int(last_pl.get("service fees", 0))
	if deal_cash > 0:
		last_pl["cash collected"] = int(last_pl.get("cash collected", 0)) + deal_cash
	return collected

# ---------- the working day ----------

const DAY_CYCLES := 8  # one working day, so a quarter is a couple of weeks
## What fraction of a customer's traffic is actually flowing, hour by hour.
## Provisioning for the average is the mistake this exists to punish.
const DAY_CURVE := [0.35, 0.45, 0.9, 1.25, 1.35, 1.15, 0.85, 0.5]
const DAY_NAMES := ["night", "early morning", "morning", "late morning",
	"early afternoon", "afternoon", "evening", "late evening"]

## A year is twelve working days of eight cycles: ninety-six cycles, four
## seasons, read off the clock that already exists rather than a new one.
const SEASON_LENGTH := DAY_CYCLES * 12
const SEASONS := [
	{"id": "spring", "label": "spring", "cooling": 1.0, "work": 1.08, "contractors": 1.0,
		"line": "Spring: the quarter everybody wants their project finished in."},
	{"id": "summer", "label": "summer", "cooling": 0.92, "work": 0.9, "contractors": 1.4,
		"line": "Summer: hot enough to find out what your cooling is really worth, and half the country is away."},
	{"id": "autumn", "label": "autumn", "cooling": 1.04, "work": 1.12, "contractors": 1.0,
		"line": "Autumn: budgets reopen and the work comes back."},
	{"id": "winter", "label": "winter", "cooling": 1.08, "work": 0.97, "contractors": 1.2,
		"line": "Winter: cold enough that the generator gets asked a question, and nobody travels quickly."},
]

func season_index() -> int:
	return int(float(cycle) / (float(SEASON_LENGTH) / 4.0)) % SEASONS.size()

func season() -> Dictionary:
	return SEASONS[season_index()]

func season_cooling() -> float:
	return float(season()["cooling"])

func season_work() -> float:
	return float(season()["work"])

func season_contractor_delay() -> float:
	return float(season()["contractors"])

var _season_seen := -1

func season_tick() -> void:
	## Said in the log when it turns, so it is legible before it bites.
	var now := season_index()
	if now == _season_seen:
		return
	var first := _season_seen < 0
	_season_seen = now
	if not first:
		log_event("SEASON: %s" % season()["line"])

func day_slot() -> int:
	return int(cycle) % DAY_CYCLES

func day_factor() -> float:
	## the seasonal part rides on top: business picks up towards year end
	var seasonal := season_work()
	return DAY_CURVE[day_slot()] * seasonal

func day_name() -> String:
	return DAY_NAMES[day_slot()]

func _first_light(deal: Dictionary) -> void:
	## The moment somebody's shop starts working because of something you built.
	## Once per customer, in their words, and quieter every time after the first.
	var biz := Market.business_for(deal)
	var earlier := int(stats.get("services_live", 0))
	stats["services_live"] = earlier + 1
	if earlier == 0:
		log_event("FIRST LIGHT: %s is live. %s Somebody's %s is working because of a cable you ran and a configuration you wrote."
			% [deal["customer"], String(biz["live"]),
				String(biz["what"]).trim_prefix("a ").trim_prefix("an ")])
		log_event("FIRST LIGHT: “%s”, and it is worth $%d every cycle it stays that way."
			% [_first_light_words(deal), int(deal["fee"])])
		Sfx.play("money")
	else:
		log_event("LIVE: %s is answering. %s That is %d service(s) of yours in the world now."
			% [deal["customer"], String(biz["live"]), earlier + 1])

func _first_light_words(deal: Dictionary) -> String:
	match String(Market.business_for(deal)["id"]):
		"clinic":
			return "Reception rang. They have booked eleven people since you left."
		"school":
			return "The registers went in on time this morning. Nobody mentioned the network, which is the compliment."
		"streaming":
			return "We are live and the chat has stopped complaining. Thank you."
		"factory":
			return "The line is moving. The supervisor says to tell you it is moving."
	return "The first order came through while I was watching. The label printer made that noise."

func customer_eye(deal: Dictionary) -> Dictionary:
	## Translate a real service state into the small human thing it carries.
	## This is deliberately derived at read time: the UI can never celebrate
	## orders while the simulation says the customer is down.
	if String(deal.get("customer", "")) != "Kiskacsa Kft":
		return _general_customer_eye(deal)
	var delivered := bool(deal.get("ever_healthy", false))
	var healthy := bool(deal.get("healthy", false))
	var degraded := bool(deal.get("degraded", false))
	var current_load := maxi(0, int(round(float(int(deal.get("load", 0))) * day_factor())))
	var eye := {
		"name": "KISKACSA / CUSTOMER EYE",
		"identity": "A small Budapest children's shop. Its web checkout sends each paid order straight to the label printer beside the packing table.",
		"time": day_name().to_upper(),
		"state": "waiting",
		"metric": "NO LIVE ORDERS YET",
		"activity": "Their team is preparing products and waiting for the promised service.",
		"voice": "“Tell us when it is ready; we would rather launch once than apologise twice.”",
	}
	var arc: Dictionary = customer_arcs.get("kiskacsa", {})
	match String(arc.get("beat", "arrival")):
		"arrival":
			eye["relationship"] = "ARRIVAL  /  FIRST PROMISE"
			var attempts := int(arc.get("proposal_attempts", 0))
			eye["memory"] = ("They remember that you revised the proposal instead of walking away."
				if attempts > 0 else "They chose you for the first launch and are watching how you operate.")
		"complication":
			eye["relationship"] = "COMPLICATION  /  FIRST OUTAGE"
			eye["memory"] = ("You told them what was happening before touching the network."
				if guided_outage.has("status_cycle") else "They are still waiting to hear what is happening.")
		"recovery":
			eye["relationship"] = "RECOVERY  /  PROVING THE FIX"
			eye["memory"] = "They remember the %s you left behind. Trust now depends on several quiet, healthy cycles." \
				% _kiskacsa_resilience_name(String(arc.get("resilience", "improvement")))
		"payoff":
			if String(arc.get("outcome", "")) == "trusted":
				eye["relationship"] = "PAYOFF  /  TRUSTED OPERATOR"
				eye["memory"] = "You communicated, repaired without a rescue, and proved the fix. Kiskacsa has sent Madaras Játék to your door."
			else:
				eye["relationship"] = "PAYOFF  /  CAUTIOUS CUSTOMER"
				eye["memory"] = "Service is steady again, but the assisted restore made them renew cautiously and keep referrals close."
	if not delivered:
		return eye
	if not healthy:
		eye["state"] = "down"
		eye["metric"] = "CHECKOUT OFFLINE"
		eye["activity"] = "Shoppers can browse cached pages, but checkout cannot submit an order. The packing table is quiet and new labels are not arriving."
		eye["voice"] = "“We have paused the promotion. Please keep us updated; people are asking whether their order went through.”"
		return eye
	var shoppers := maxi(2, int(round(float(current_load) / 6.0)))
	var orders := maxi(1, int(round(float(current_load) / 28.0)))
	if degraded:
		eye["state"] = "degraded"
		eye["metric"] = "~%d SHOPPERS / CHECKOUT RETRYING" % shoppers
		eye["activity"] = "Pages are slow and some shoppers retry payment. Orders reach the packing table in bursts instead of a steady queue."
		eye["voice"] = "“It is working, but customers are pressing the button twice. Can you steady it?”"
		return eye
	eye["state"] = "live"
	eye["metric"] = "~%d SHOPPERS  ·  ~%d ORDERS/H" % [shoppers, orders]
	eye["activity"] = "Checkout is accepting orders. Each success becomes a fresh shipping label at the packing table."
	if String(guided_outage.get("state", "")) in ["recovered", "choice", "complete"]:
		eye["voice"] = "“The labels are moving again. Thank you for telling us what was happening while you fixed it.”"
	else:
		eye["voice"] = "“The next label just printed. That little sound means the shop is working.”"
	return eye

## Five customers who come back, remember, and want different things. The
## beats advance on live delivery, never on a line of dialogue.
const STORY_CUSTOMERS := {
	"kiskacsa": {"customer": "Kiskacsa Kft"},
	"fonix": {"customer": "Fonix Klinika", "need": "capacity",
		"complication": "their booking system has doubled its traffic and they will not tolerate a slow morning",
		"payoff": "they put your name in front of the other two clinics in the group",
		"failure": "they moved the booking system somewhere with more headroom"},
	"madaras": {"customer": "Madaras Jatek Kft", "need": "protection",
		"complication": "an attempted break-in has made them ask what actually sits in front of their server",
		"payoff": "their board now treats your firewall as the reason they are still trading",
		"failure": "they hired somebody else to do the security review, and then the hosting"},
	"tisza": {"customer": "Tisza Logisztika", "need": "second_site",
		"complication": "one warehouse burned an afternoon offline and they want the other site carrying it",
		"payoff": "the two-site build is the thing they show visitors",
		"failure": "they split the contract and gave the second half to somebody with two rooms"},
	"orban": {"customer": "Orban es Tarsa", "need": "reliability",
		"complication": "after a bad quarter they are counting every outage you have",
		"payoff": "they stopped counting, which is the highest praise this trade offers",
		"failure": "they left, politely, with a spreadsheet of every cycle you were down"},
}

func story_key(customer: String) -> String:
	for key: String in STORY_CUSTOMERS:
		if String(STORY_CUSTOMERS[key].get("customer", "")) == customer:
			return key
	return ""

func story_arc(key: String) -> Dictionary:
	return customer_arcs.get(key, {})

func _story_need_met(key: String, deal: Dictionary) -> bool:
	## Every one of these is a fact about the network or the service, not a
	## conversation the player had.
	match String(STORY_CUSTOMERS[key].get("need", "")):
		"capacity":
			# they doubled: the service has to still be delivered, undegraded
			return bool(deal.get("healthy", false)) and not bool(deal.get("degraded", false)) \
				and int(deal.get("load", 0)) >= int(deal.get("story_load", 0))
		"protection":
			var host := Contracts._owner(String(deal["params"].get("ip", "")))
			if host == null:
				return false
			for d: Net.NDevice in all_devices():
				if d.type == "firewall" and d.status == "active" and not d.acls.is_empty():
					return true
			return false
		"second_site":
			return site_count() > 1 and not circuits.is_empty()
		"reliability":
			return int(deal.get("cycles", 0)) > 0 \
				and float(deal.get("up_cycles", 0)) / float(maxi(1, int(deal.get("cycles", 1)))) >= 0.95
	return false

func story_tick() -> void:
	for deal in deals:
		var key := story_key(String(deal.get("customer", "")))
		if key == "" or key == "kiskacsa":
			continue  # the guided customer has an arc of its own
		var arc: Dictionary = customer_arcs.get(key, {"beat": "arrival", "since": cycle,
			"outages": 0, "helped": false})
		if not bool(deal.get("healthy", false)):
			arc["outages"] = int(arc.get("outages", 0)) + 1
		match String(arc.get("beat", "arrival")):
			"arrival":
				if cycle - int(arc.get("since", cycle)) >= 8 and bool(deal.get("ever_healthy", false)):
					arc["beat"] = "complication"
					arc["since"] = cycle
					arc["deadline"] = cycle + 12
					if String(STORY_CUSTOMERS[key].get("need", "")) == "capacity":
						deal["load"] = int(deal.get("load", 200)) * 2
						arc["story_load"] = int(deal["load"])
						deal["story_load"] = int(deal["load"])
					log_event("STORY: %s. %s" % [deal["customer"],
						STORY_CUSTOMERS[key]["complication"]])
			"complication":
				if _story_need_met(key, deal):
					arc["beat"] = "payoff"
					arc["outcome"] = "kept"
					deal["loyalty"] = minf(1.0, float(deal.get("loyalty", 0.6)) + 0.2)
					reputation = mini(100, reputation + 4)
					if String(deal["customer"]) not in references:
						references.append(String(deal["customer"]))
					leads.append(Market.story_referral_lead(String(deal["customer"])))
					log_event("STORY PAYOFF: %s. %s" % [deal["customer"],
						STORY_CUSTOMERS[key]["payoff"]])
				elif cycle > int(arc.get("deadline", cycle + 12)):
					arc["beat"] = "payoff"
					arc["outcome"] = "lost"
					deals.erase(deal)
					reputation = maxi(0, reputation - 4)
					log_event("STORY ENDING: %s. %s" % [deal["customer"],
						STORY_CUSTOMERS[key]["failure"]])
		customer_arcs[key] = arc

func _general_customer_eye(deal: Dictionary) -> Dictionary:
	## Every customer is somebody doing something. Read off live state only:
	## the panel can never celebrate orders while the service is down.
	if deal.is_empty() or not deal.has("customer"):
		return {}
	var biz := Market.business_for(deal)
	var delivered := bool(deal.get("ever_healthy", false))
	var healthy := bool(deal.get("healthy", false))
	var event := peak_event(deal)
	var multiplier := peak_multiplier(deal)
	var current_load := maxi(0, int(round(float(int(deal.get("load", 0))) * day_factor() * multiplier)))
	var eye := {
		"name": "%s  /  CUSTOMER EYE" % String(deal["customer"]).to_upper(),
		"identity": "%s: %s." % [deal["customer"], biz["what"]],
		"time": day_name().to_upper(),
		"state": "waiting",
		"metric": "NOT LIVE YET",
		"activity": "They are waiting for the service they were promised.",
		"voice": "“Tell us when it is ready.”",
	}
	var story := story_key(String(deal.get("customer", "")))
	if story != "" and not story_arc(story).is_empty():
		var arc: Dictionary = story_arc(story)
		eye["relationship"] = "%s  /  %s" % [String(arc.get("beat", "arrival")).to_upper(),
			String(STORY_CUSTOMERS[story].get("need", "service")).to_upper()]
		if String(arc.get("beat", "")) == "complication":
			eye["memory"] = "%s They have %d outage(s) of yours on record." \
				% [STORY_CUSTOMERS[story]["complication"], int(arc.get("outages", 0))]
		elif String(arc.get("outcome", "")) == "kept":
			eye["memory"] = STORY_CUSTOMERS[story]["payoff"]
		else:
			eye["memory"] = "They are watching how this one goes."
	if not event.is_empty():
		eye["relationship"] = "%s  /  IN %d CYCLE%s" % [String(event["label"]).to_upper(),
			int(event["cycle"]) - cycle, "" if int(event["cycle"]) - cycle == 1 else "S"]
		eye["memory"] = "They have told you in advance: %s carries about %d times their normal traffic. They will remember how it went." \
			% [event["label"], int(event["multiplier"])]
	elif int(deal.get("peaks_carried", 0)) > 0:
		eye["relationship"] = "CARRIED  /  %d BUSY NIGHT%s" % [int(deal["peaks_carried"]),
			"" if int(deal["peaks_carried"]) == 1 else "S"]
		eye["memory"] = "You held their busiest hours together, and they have said so out loud."
	if not delivered:
		return eye
	if not healthy:
		eye["state"] = "down"
		eye["metric"] = "%s STOPPED" % String(biz["unit"]).to_upper()
		eye["activity"] = String(biz["down"])
		eye["voice"] = "“Please keep us updated; people are asking.”"
		return eye
	var people := maxi(2, int(round(float(current_load) / 6.0)))
	var units := maxi(1, int(round(float(current_load) / 28.0)))
	if bool(deal.get("degraded", false)):
		eye["state"] = "degraded"
		eye["metric"] = "~%d %s / RETRYING" % [people, String(biz["who"]).to_upper()]
		eye["activity"] = String(biz["slow"])
		eye["voice"] = "“It works, but only just. Can you steady it?”"
		return eye
	eye["state"] = "live"
	eye["metric"] = "~%d %s  ·  ~%d %s/H" % [people, String(biz["who"]).to_upper(), units,
		String(biz["unit"]).to_upper()]
	eye["activity"] = String(biz["live"])
	eye["voice"] = "“Nobody here is thinking about the network, which is how we like it.”"
	return eye

func peak_event(deal: Dictionary) -> Dictionary:
	var event: Dictionary = deal.get("peak_event", {})
	return event if not event.is_empty() and int(event.get("cycle", -1)) >= cycle else {}

func peak_multiplier(deal: Dictionary) -> float:
	var event: Dictionary = deal.get("peak_event", {})
	return float(event.get("multiplier", 1.0)) if int(event.get("cycle", -1)) == cycle else 1.0

func maybe_announce_peak() -> void:
	## The night they have been planning for. Announced in advance, on purpose:
	## the content is the preparation, not the surprise.
	for deal in deals:
		if deal.has("peak_event") or not bool(deal.get("ever_healthy", false)):
			continue
		if int(deal.get("cycles", 0)) < 6 or biz_roll() > 0.05:
			continue
		var biz := Market.business_for(deal)
		var event := {"label": String(biz["peak"]), "cycle": cycle + 4, "multiplier": 3}
		deal["peak_event"] = event
		log_event("HEADS UP: %s has a %s in 4 cycles. Expect about three times their usual traffic; they will remember how it goes."
			% [deal["customer"], biz["peak"]])
		return

func peak_tick(deal: Dictionary) -> void:
	## Resolved on the night itself, against live delivery.
	var event: Dictionary = deal.get("peak_event", {})
	if event.is_empty() or int(event.get("cycle", -1)) != cycle:
		return
	deal.erase("peak_event")
	if bool(deal.get("healthy", false)) and not bool(deal.get("degraded", false)):
		deal["peaks_carried"] = int(deal.get("peaks_carried", 0)) + 1
		deal["loyalty"] = minf(1.0, float(deal.get("loyalty", 0.6)) + 0.15)
		reputation = mini(100, reputation + 3)
		log_event("CARRIED IT: %s's %s went through your network without a wobble. They have written to say so."
			% [deal["customer"], event["label"]])
	else:
		deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - 0.2)
		reputation = maxi(0, reputation - 4)
		log_event("DROPPED IT: %s's %s was the one night that mattered, and your network did not carry it."
			% [deal["customer"], event["label"]])

func _kiskacsa_resilience_name(choice: String) -> String:
	match choice:
		"spare":
			return "cold spare"
		"monitor":
			return "permanent monitor"
		"config":
			return "saved recovery configuration"
	return "resilience improvement"

func peak_factor() -> float:
	return DAY_CURVE.max()

func top_talkers(limit := 8) -> Array:
	## the busiest source and destination pairs across every router, newest
	## counters first. Answers "what is filling that link" without guessing.
	var merged := {}
	for d in all_devices():
		for key in d.talkers:
			merged[key] = int(merged.get(key, 0)) + int(d.talkers[key])
	var rows: Array = []
	for key in merged:
		rows.append({"pair": key, "packets": int(merged[key])})
	rows.sort_custom(func(x, y): return int(x["packets"]) > int(y["packets"]))
	return rows.slice(0, limit)

func clear_talkers() -> void:
	for d in all_devices():
		d.talkers.clear()

func receivables() -> int:
	var total := 0
	for inv in invoices:
		total += int(inv["amount"])
	return total

func overdue_invoices() -> Array:
	var out: Array = []
	for inv in invoices:
		if int(inv["due"]) < cycle:
			out.append(inv)
	return out

func chase_invoice(inv: Dictionary) -> String:
	if bool(inv["chased"]):
		return "you have already chased that one"
	inv["chased"] = true
	inv["due"] = cycle  # it will be collected on the next cycle
	reputation = maxi(0, reputation - CHASE_REPUTATION)
	log_event("CHASED: %s has been asked for the $%d they owe." % [inv["customer"], int(inv["amount"])])
	return ""

# ---------- power distribution ----------

static func default_psu(model: String) -> String:
	## dual-supply gear takes both feeds out of the box, which is the whole
	## reason it costs more
	return "AB" if model in DUAL_PSU else "A"

func dual_psu(d: Net.NDevice) -> bool:
	return d.model in DUAL_PSU

func set_psu(d: Net.NDevice, which: String) -> String:
	if which == "AB" and not dual_psu(d):
		return "%s has one power supply; it can take A or B, not both" % d.name
	if which not in ["A", "B", "AB"]:
		return "a device plugs into feed A, feed B, or both"
	d.psu = which
	topology_changed.emit()
	_apply_feed_state()
	return ""

func site_feeds(site: int) -> Dictionary:
	if not feeds.has(site):
		feeds[site] = {"A": true, "B": true}
	return feeds[site]

func feed_live(site: int, which: String) -> bool:
	## a dead feed is carried while the battery holds, and after that only by a
	## generator somebody has actually tested
	if bool(site_feeds(site).get(which, true)) or int(ups.get(site, 0)) > 0:
		return true
	return stage >= 1 and int(facility.get("generator_tests", 0)) > 0 and generator_ready()

func device_powered(d: Net.NDevice) -> bool:
	var site := site_of_device(d)
	for letter in d.psu:
		if feed_live(site, letter):
			return true
	return false

func site_of_device(d: Net.NDevice) -> int:
	var r := rack_of(d)
	return r.site if r != null else 0

func site_hue(site: int) -> float:
	## One colour per site, spread around the wheel by index rather than hashed
	## from the name: two hashed names can land on the same green, and then the
	## colour tells the player nothing. Shared by the floor, the switcher, the
	## operations header and the map, so they cannot disagree.
	return fmod(float(maxi(0, site)) * 0.618 + 0.11, 1.0)

func elsewhere(d: Net.NDevice) -> String:
	## Where this device physically is, when that is not where you are. Acting
	## on another building's kit by accident is the expensive mistake.
	if d == null or site_count() < 2:
		return ""
	var at := site_of_device(d)
	if at == current_site:
		return ""
	return site_name(at)

const DR_NOTICE := 3   # cycles of warning, so it can be prepared for
const DR_LENGTH := 2   # how long the upstream stays away

var dr_test := {}  # {booked, ends, taken: [device names], failed: [customers]}

func dr_candidates() -> Array:
	## What a failover test can take away: your upstreams on this floor.
	var out: Array = []
	for d in all_devices():
		if d.type == "uplink" and d.status == "active" and site_of_device(d) == current_site:
			out.append(d)
	return out

func dr_request_tick() -> void:
	## The customers who pay for a strict service level are the ones who ask,
	## once, in writing, and remember the answer either way.
	for deal in deals:
		if int(deal.get("sla", 0)) < 2 or deal.has("dr_asked") or not bool(deal.get("healthy", false)):
			continue
		if biz_roll() > 0.05:
			continue
		deal["dr_asked"] = cycle
		deal["dr_due"] = cycle + 12
		log_event("%s wants the failover tested and the result sent to them, by cycle %d."
			% [deal["customer"], int(deal["dr_due"])])
	for deal2 in deals:
		if not deal2.has("dr_due") or bool(deal2.get("dr_done", false)):
			continue
		var proved := int(control_evidence.get("failover", -999))
		if proved >= int(deal2["dr_asked"]):
			deal2["dr_done"] = true
			deal2["loyalty"] = minf(1.0, float(deal2.get("loyalty", 0.6)) + 0.15)
			reputation = mini(100, reputation + 2)
			log_event("%s has the failover result they asked for. They did not want it to be interesting, and it was not."
				% deal2["customer"])
		elif cycle > int(deal2["dr_due"]):
			deal2.erase("dr_due")
			deal2["loyalty"] = maxf(0.0, float(deal2.get("loyalty", 0.6)) - 0.2)
			log_event("%s asked for a failover test and never got one. They have written that down."
				% deal2["customer"])

func book_dr_test() -> String:
	## Announced, not sprung: the point of a test is that everybody knew.
	if not dr_test.is_empty():
		return "a failover test is already in the diary"
	if dr_candidates().is_empty():
		return "there is nothing here to take away yet"
	dr_test = {"booked": cycle + DR_NOTICE, "ends": -1, "taken": [], "failed": []}
	log_event("FAILOVER TEST: booked for cycle %d. The upstream on this floor goes away for %d cycle(s)."
		% [int(dr_test["booked"]), DR_LENGTH])
	return ""

func cancel_dr_test() -> String:
	if dr_test.is_empty():
		return "nothing is booked"
	if int(dr_test.get("ends", -1)) > 0:
		return "it is running: it finishes when it finishes"
	dr_test = {}
	log_event("FAILOVER TEST: cancelled. Nothing was proved, which is the same as before.")
	return ""

func dr_running() -> bool:
	return not dr_test.is_empty() and int(dr_test.get("ends", -1)) > 0

func dr_tick() -> void:
	if dr_test.is_empty():
		return
	if not dr_running():
		if cycle < int(dr_test["booked"]):
			return
		# never run a test into a room that is already in trouble: that is not
		# a test, it is a second incident
		if customer_down_now() or upstream_active() or not hazards.is_empty():
			if not bool(dr_test.get("held", false)):
				dr_test["held"] = true
				log_event("FAILOVER TEST: held. The floor is already dealing with something; it runs when that is over.")
			return
		dr_test["held"] = false
		var taken: Array = []
		for d in dr_candidates():
			d.status = "offline"
			taken.append(d.name)
		if taken.is_empty():
			dr_test = {}
			log_event("FAILOVER TEST: nothing left to take away. Cancelled.")
			return
		dr_test["taken"] = taken
		dr_test["ends"] = cycle + DR_LENGTH
		log_event("FAILOVER TEST: %s is out of service on purpose. Everything that is meant to survive it should now."
			% ", ".join(PackedStringArray(taken)))
		topology_changed.emit()
		return
	# running: judge it on customers, which is the only thing that counts
	for deal in deals:
		if bool(deal.get("ever_healthy", false)) and not bool(deal.get("healthy", false)):
			var who := String(deal.get("customer", ""))
			if who not in dr_test["failed"]:
				dr_test["failed"].append(who)
	if cycle < int(dr_test["ends"]):
		return
	for name: String in dr_test["taken"]:
		for back in all_devices():
			if back.name == name and back.status == "offline":
				back.status = "active"
	var failed: Array = dr_test["failed"]
	if failed.is_empty():
		reputation = mini(100, reputation + 5)
		control_evidence["failover"] = cycle
		stats["failovers_passed"] = int(stats.get("failovers_passed", 0)) + 1
		log_event("FAILOVER TEST: passed. The upstream was gone for %d cycle(s) and no customer noticed."
			% DR_LENGTH)
	else:
		reputation = maxi(0, reputation - 3)
		log_event("FAILOVER TEST: failed. %s went down while the upstream was away, which is what the test was for."
			% ", ".join(PackedStringArray(failed)))
	dr_test = {}
	topology_changed.emit()

func buy_ups() -> String:
	if ups.has(current_site) and int(ups.get(current_site, 0)) > 0:
		return "there is already a UPS on this floor"
	if stage < 1 and current_site == 0:
		return "the colo provides its own power; a UPS is for your own room"
	if not try_spend(UPS_PRICE):
		return "you cannot afford the $%d UPS" % UPS_PRICE
	ups[current_site] = UPS_CYCLES
	log_event("POWER: a UPS is installed on %s, good for %d cycles of one dead feed."
		% [site_name(current_site), UPS_CYCLES])
	topology_changed.emit()
	return ""

func has_ups(site: int) -> bool:
	return ups.has(site)

func _apply_feed_state() -> void:
	## a device with no live feed is off, and comes straight back when power does
	for d in all_devices():
		if device_powered(d):
			if d.status == "nopower":
				d.status = "active"
		elif d.status == "active":
			d.status = "nopower"
	topology_changed.emit()

func power_tick() -> void:
	## utility feeds fail occasionally, and the battery drains while one is out
	for site in site_count():
		var f := site_feeds(site)
		for letter in ["A", "B"]:
			var key := "%d|%s" % [site, letter]
			if not bool(f[letter]):
				if cycle >= int(feed_out_until.get(key, 0)):
					f[letter] = true
					feed_out_until.erase(key)
					log_event("POWER: feed %s on %s is back." % [letter, site_name(site)])
				continue
			# the colo's power is somebody else's problem; your own room is not
			if site == 0 and stage < 1:
				continue
			if randf() < 0.012 * DIFFICULTIES[difficulty]["faults"]:
				f[letter] = false
				feed_out_until[key] = cycle + randi_range(1, 3)
				log_event("POWER: feed %s on %s has dropped." % [letter, site_name(site)])
		var any_out := not bool(f["A"]) or not bool(f["B"])
		if any_out and int(ups.get(site, 0)) > 0:
			ups[site] = int(ups[site]) - 1
			if int(ups[site]) == 0:
				log_event("POWER: the UPS on %s is flat. Anything on the dead feed is going down."
					% site_name(site))
		elif not any_out and ups.has(site) and int(ups[site]) < UPS_CYCLES:
			ups[site] = mini(UPS_CYCLES, int(ups[site]) + 1)  # recharging
	_apply_feed_state()

func single_feed_exposure(site: int) -> Array:
	## every device that one feed failure would take out, and which feed
	var out: Array = []
	for r in racks_on(site):
		for d in r.slots:
			if d != null and d.psu.length() == 1:
				out.append(d)
	return out

func capacity_runway(key: String, used: int, total: int, window := 12) -> int:
	## how many cycles until this resource is full at the rate it has been
	## filling. -1 means "not filling", which is a perfectly good answer.
	if total <= 0 or used >= total:
		return 0 if used >= total and total > 0 else -1
	var samples: Array = []
	for h in history:
		if h.has(key):
			samples.append(h)
	if samples.size() < 3:
		return -1
	var recent: Array = samples.slice(maxi(0, samples.size() - window))
	var span: int = int(recent[-1]["cycle"]) - int(recent[0]["cycle"])
	var grew: int = int(recent[-1][key]) - int(recent[0][key])
	if span <= 0 or grew <= 0:
		return -1
	var per_cycle := float(grew) / float(span)
	return int(ceil(float(total - used) / per_cycle))

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
		"watts": watts, "cooling": cooling_capacity(site),
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
		"deal_cycles": deal_cycles,
	}
	reports.push_front(rep)
	if reports.size() > 8:
		reports.pop_back()
	log_event("QUARTER %d closed: net %s$%d, %d customers, %d%% delivered, rank %s."
		% [int(rep["quarter"]), "+" if net >= 0 else "-", absi(net), deals.size(),
			int(rep["uptime"]), rep["rank"]])
	if nemesis != "":
		# they never miss a quarter without a comment
		rep["needle"] = Rivals.nemesis_line()
		log_event("QUARTERLY NEEDLE: %s" % rep["needle"])
	return rep

func accept_buyout() -> String:
	if buyout_offer.is_empty():
		return "there is nothing on the table"
	var price := int(buyout_offer["price"])
	money += price  # the sale is cash in the bank, and is scored as that, not as trading
	sold_out = true
	log_event("SOLD: %s bought the company for $%d. That is the end of it."
		% [buyout_offer["rival"], price])
	buyout_offer = {}
	money_changed.emit()
	topology_changed.emit()
	return ""

func decline_buyout() -> String:
	if buyout_offer.is_empty():
		return "there is nothing on the table"
	var who := String(buyout_offer["rival"])
	buyout_offer = {}
	# turning somebody down makes them a worse neighbour
	for r in rivals:
		if String(r["name"]) == who:
			r["aggression"] = maxf(0.6, float(r["aggression"]) - 0.12)
			r["cash"] = int(r["cash"]) + 4000
	log_event("APPROACH: you turned %s down. They are going to compete harder for it." % who)
	return ""

const FINALE_ENDINGS := {
	"sold": "You sold the company.",
	"retired": "You reached the top of the trade and walked away from it.",
	"insolvent": "The money ran out.",
}

func finale_snapshot(ending: String) -> Dictionary:
	## Frozen at the moment it ends, so the report can be recomputed exactly
	## without the live world having to stand still.
	var up := 0
	var deal_cycles := 0
	for h: Dictionary in history:
		up += int(h.get("up", 0))
		deal_cycles += int(h.get("deals", 0))
	var techs := {}
	for d: Net.NDevice in all_devices():
		if not d.bgp.get("neighbors", []).is_empty():
			techs["bgp"] = true
		if not d.vtep.is_empty():
			techs["vxlan"] = true
		if d.type == "firewall":
			techs["firewall"] = true
		if not d.ospf.is_empty():
			techs["ospf"] = true
		if not d.vrfs.is_empty():
			techs["vrf"] = true
		if not d.services.get("lb", {}).is_empty():
			techs["loadbalancer"] = true
		if not Sim.nat64_of(d).is_empty():
			techs["nat64"] = true
		if not Sim.nat_rules(d).is_empty():
			techs["nat"] = true
		if d.type == "ap" and d.ssids.size() >= 2:
			techs["wireless"] = true
		for i: Net.Iface in d.ifaces:
			if i.mlag > 0:
				techs["mlag"] = true
			if i.vrrp.get("vip", "") != "":
				techs["vrrp"] = true
			if i.name.begins_with("wg") and not i.wg_peers.is_empty():
				techs["wireguard"] = true
			if i.lag > 0:
				techs["lacp"] = true
			if i.bfd:
				techs["bfd"] = true
			if i.dot1x:
				techs["dot1x"] = true
			if i.qos:
				techs["qos"] = true
			if i.vm != "":
				techs["vm"] = true
			if i.tunnel_dst != "" and not i.name.begins_with("wg"):
				techs["tunnel"] = true
			for cidr in i.ips:
				if Net.is_v6(String(cidr)):
					techs["ipv6"] = true
	var open_reviews := 0
	for inc: Dictionary in incidents:
		if not bool(inc.get("reviewed", false)):
			open_reviews += 1
	var controls_passing := 0
	for c: Dictionary in CONTROLS:
		if String(control_state(String(c["id"]))["status"]) == "compliant":
			controls_passing += 1
	return {"ending": ending, "cycle": cycle, "company": company_name,
		"identity": identity_label(), "difficulty": DIFFICULTIES[difficulty]["name"],
		"earned": int(stats.get("earned", 0)), "money": money, "reputation": reputation,
		"references": references.size(), "deals": deals.size(),
		"contracts": int(stats.get("contracts", 0)), "sites": site_count(),
		"racks": racks.filter(func(r): return r.slots.any(func(d): return d != null)).size(),  # empty cabinets are not growth
		"staff": staff.size(), "stage": stage,
		"uptime": int(100.0 * float(up) / maxf(1.0, float(deal_cycles))),
		"streak": best_streak(),
		"techs": techs.keys(), "open_reviews": open_reviews,
		"controls": controls_passing, "tidiness": floor_tidiness(),
		"drift": drift_factor(), "faults": int(stats.get("faults", 0)),
		"incidents": int(stats.get("incidents", 0)), "data_risks": data_risks.size(),
		"destruction_certs": destruction_certs.size(),
		"cable_debt": cable_debt_score(), "best_streak": best_streak(),
		"trust_marker": trust_marker,
		# what was actually practised, not only what was built
		"failovers_passed": int(stats.get("failovers_passed", 0)),
		"oncall_covered": 1 if oncall != "" else 0,
		"handovers_read": int(stats.get("handovers_read", 0))}

func finale_score(snap: Dictionary) -> Dictionary:
	## Six categories, each capped, and the money one measured per cycle so a
	## long idle run cannot out-score a short sharp one.
	var cycles := maxf(1.0, float(int(snap.get("cycle", 1))))
	var per_cycle := float(int(snap.get("earned", 0))) / cycles
	var categories := {
		# what the company earned per cycle, plus what it kept: a hoard is
		# worth something, and a sale is worth exactly what it left in the bank
		"financial": clampi(int(per_cycle * 2.0) + maxi(0, int(snap.get("money", 0))) / 500, 0, 250),
		# uptime is per customer-cycle; the floor sign's streak counts too, so a
		# long clean run scores above zero even when no customer was ever billed
		"reliability": clampi(int(snap.get("uptime", 0)) * 2 + mini(int(snap.get("streak", 0)) / 4, 50), 0, 200),
		"trust": clampi(int(snap.get("reputation", 0)) + int(snap.get("references", 0)) * 10
			+ (20 if bool(snap.get("trust_marker", false)) else 0), 0, 200),
		# breadth: the cap of 200 needs most of the twenty technologies, not six
		"ambition": clampi(int(snap.get("techs", []).size()) * 10
			+ int(snap.get("contracts", 0)) * 4, 0, 200),
		"discipline": clampi(int(float(snap.get("tidiness", 0.0)) * 80.0)
			+ int((1.0 - float(snap.get("drift", 0.0))) * 60.0)
			+ int(snap.get("controls", 0)) * 8
			# things that are only true because somebody practised them
			+ mini(int(snap.get("failovers_passed", 0)), 3) * 12
			+ int(snap.get("oncall_covered", 0)) * 10
			+ mini(int(snap.get("handovers_read", 0)), 10) * 2
			+ mini(int(snap.get("destruction_certs", 0)), 5) * 4
			- int(snap.get("open_reviews", 0)) * 10
			- int(snap.get("data_risks", 0)) * 15 - int(snap.get("cable_debt", 0)) * 2, 0, 200),
		"growth": clampi(int(snap.get("stage", 0)) * 40 + int(snap.get("sites", 1)) * 20
			+ int(snap.get("racks", 0)) * 4 + int(snap.get("staff", 0)) * 10, 0, 200),
	}
	var total := 0
	for k: String in categories:
		total += int(categories[k])
	# a harder preset is worth more; Apprentice runs do not top the table
	var diff_factor := 1.0
	for d: Dictionary in DIFFICULTIES:
		if String(d["name"]) == String(snap.get("difficulty", "")):
			diff_factor = float(d.get("score", 1.0))
	return {"categories": categories, "total": int(total * diff_factor), "difficulty_factor": diff_factor}

func finale_callouts(snap: Dictionary) -> Dictionary:
	## What went well, and what it cost to do the things that did not.
	var score := finale_score(snap)
	var best := ""
	var best_val := -1
	for k: String in score["categories"]:
		if int(score["categories"][k]) > best_val:
			best_val = int(score["categories"][k])
			best = k
	var losses: Array = []
	if int(snap.get("open_reviews", 0)) > 0:
		losses.append("%d incident(s) never written up" % int(snap["open_reviews"]))
	if int(snap.get("data_risks", 0)) > 0:
		losses.append("%d unit(s) decommissioned without a certificate" % int(snap["data_risks"]))
	if int(snap.get("destruction_certs", 0)) > 0 and int(snap.get("data_risks", 0)) == 0:
		losses.append("(every drive that left was wiped first: %d certificate(s) on file)" % int(snap["destruction_certs"]))
	if int(snap.get("cable_debt", 0)) > 4:
		losses.append("%d pieces of cable debt nobody went back for" % int(snap["cable_debt"]))
	if float(snap.get("drift", 0.0)) > 0.4:
		losses.append("documentation that stopped describing the floor")
	if int(snap.get("uptime", 0)) < 95:
		losses.append("%d%% uptime across the run" % int(snap.get("uptime", 0)))
	if int(snap.get("failovers_passed", 0)) == 0 and int(snap.get("sites", 1)) > 1:
		losses.append("two rooms, and the failover never once tested")
	if int(snap.get("oncall_covered", 0)) == 0 and int(snap.get("staff", 0)) > 0:
		losses.append("nobody was ever asked to carry the phone")
	return {"strength": best, "losses": losses}

const HISTORY_PATH := "user://run_history.json"
static var history_path := HISTORY_PATH  # tests point this somewhere harmless

func run_history() -> Array:
	## Old or corrupt records are dropped rather than trusted.
	if not FileAccess.file_exists(history_path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(history_path))
	if not (parsed is Array):
		return []
	var out: Array = []
	for entry in parsed:
		if entry is Dictionary and entry.has("total") and entry.has("ending"):
			out.append(entry)
	return out

func _write_history(rows: Array) -> void:
	var f := FileAccess.open(history_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rows))

func record_run(snap: Dictionary) -> Dictionary:
	## One compact row per finished run. Nothing here is a save, so deleting
	## history never costs anybody a game.
	var scored := finale_score(snap)
	var row := {"company": snap.get("company", ""), "identity": snap.get("identity", ""),
		"difficulty": snap.get("difficulty", ""), "ending": snap.get("ending", ""),
		"cycle": int(snap.get("cycle", 0)), "rank": rank(), "total": int(scored["total"]),
		"categories": scored["categories"], "at": int(Time.get_unix_time_from_system()),
		"money_at_end": int(snap.get("money", 0)), "reputation_at_end": int(snap.get("reputation", 0))}
	var rows := run_history()
	# the same run ended twice (a reopened save, a harness that replays the
	# finale) is one run, not two: identical in company, ending, cycle and
	# score means it is the row already at the top
	if not rows.is_empty():
		var top: Dictionary = rows[0]
		if String(top.get("company", "")) == String(row["company"]) \
				and String(top.get("ending", "")) == String(row["ending"]) \
				and int(top.get("cycle", -1)) == int(row["cycle"]) \
				and int(top.get("total", -1)) == int(row["total"]):
			return top
	# wall-clock seconds are not unique enough to order two quick runs
	var seq := 0
	for prior: Dictionary in rows:
		seq = maxi(seq, int(prior.get("seq", 0)))
	row["seq"] = seq + 1
	rows.push_front(row)
	if rows.size() > 25:
		rows.resize(25)
	_write_history(rows)
	return row

func best_run(difficulty_name := "") -> Dictionary:
	var best := {}
	for row: Dictionary in run_history():
		if difficulty_name != "" and String(row.get("difficulty", "")) != difficulty_name:
			continue
		if best.is_empty() or int(row["total"]) > int(best["total"]):
			best = row
	return best

func compare_to_best(row: Dictionary) -> Array:
	## What this run did better and worse than the best one before it.
	var out: Array = []
	var previous := {}
	for other: Dictionary in run_history():
		# strictly earlier runs only: a run does not compete with itself, and
		# only on the same difficulty: Apprentice does not compete with On call
		if int(other.get("seq", 0)) >= int(row.get("seq", 0)):
			continue
		if String(other.get("difficulty", "")) != String(row.get("difficulty", "")):
			continue
		if previous.is_empty() or int(other["total"]) > int(previous["total"]):
			previous = other
	if previous.is_empty():
		return ["This is the first run on record; the next one has something to beat."]
	out.append("against %s (%d): %s%d overall" % [previous.get("company", "the last one"),
		int(previous["total"]), "+" if int(row["total"]) >= int(previous["total"]) else "",
		int(row["total"]) - int(previous["total"])])
	for k: String in row["categories"]:
		var delta := int(row["categories"][k]) - int(previous.get("categories", {}).get(k, 0))
		if delta != 0:
			out.append("  %-12s %s%d" % [k, "+" if delta > 0 else "", delta])
	return out

func forget_run(at: int) -> void:
	var rows := run_history()
	for row: Dictionary in rows.duplicate():
		if int(row.get("at", 0)) == at:
			rows.erase(row)
	_write_history(rows)

func forget_all_runs() -> void:
	_write_history([])

func topology_mermaid(site := -1) -> String:
	## The estate as a Mermaid diagram: text anybody can paste into a document,
	## a wiki or a chat window and get a picture out of.
	var target := current_site if site < 0 else site
	var lines: Array = ["graph LR"]
	var ids := {}
	for r: Net.Rack in racks_on(target):
		var members: Array = []
		for d in r.slots:
			if d == null:
				continue
			var id := "n%d" % ids.size()
			ids[d] = id
			var addr := ""
			for i: Net.Iface in d.ifaces:
				if not i.ips.is_empty():
					addr = String(i.ips[0])
					break
			members.append("    %s[\"%s<br/>%s%s\"]" % [id, d.name, MODELS[d.model]["label"],
				"<br/>" + addr if addr != "" else ""])
		if members.is_empty():
			continue
		lines.append("  subgraph %s" % r.name)
		lines.append_array(members)
		lines.append("  end")
	for l: Net.Link in links:
		if not ids.has(l.a.dev) or not ids.has(l.b.dev):
			continue
		var style := "---"
		if not (l.a.enabled and l.b.enabled):
			style = "-.-"  # administratively down
		lines.append("  %s %s|%s ↔ %s| %s" % [ids[l.a.dev], style, l.a.name, l.b.name,
			ids[l.b.dev]])
	return "\n".join(PackedStringArray(lines))

func topology_text(site := -1) -> String:
	## The same thing as plain text, for a report or somebody's notes.
	var target := current_site if site < 0 else site
	var lines: Array = ["%s, %s, cycle %d" % [company_name, site_name(target), cycle]]
	for r: Net.Rack in racks_on(target):
		lines.append("%s:" % r.name)
		for idx in Net.Rack.SLOTS:
			var d = r.slots[idx]
			if d == null:
				continue
			var addrs: Array = []
			for i: Net.Iface in d.ifaces:
				for cidr in i.ips:
					addrs.append(String(cidr))
			lines.append("  U%d  %-10s %-22s %s" % [idx + 1, d.name, MODELS[d.model]["label"],
				", ".join(PackedStringArray(addrs))])
			for i2: Net.Iface in d.ifaces:
				var peer := effective_peer(i2)
				if peer != null:
					lines.append("        %-10s → %s %s%s" % [i2.name, peer.dev.name, peer.name,
						"" if i2.enabled and peer.enabled else "   (down)"])
	return "\n".join(PackedStringArray(lines))

func export_topology(path := "user://topology.md") -> String:
	## Written where the player can find it, and handed back so the interface
	## can put it on the clipboard as well.
	var body := "# %s\n\n```mermaid\n%s\n```\n\n```\n%s\n```\n" % [company_name,
		topology_mermaid(), topology_text()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(body)
	log_event("EXPORTED: the topology is written out as a diagram and a plain listing.")
	return body

func export_containerlab(dir := "user://clab") -> String:
	## The floor as a containerlab topology plus one startup configuration per
	## node, so what was built here can be promoted to real network operating
	## systems: RouterOS CHR for PacketTik gear, cEOS for the rest, Linux for
	## the servers. Pure files; nothing here needs Docker.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var lab := company_name.to_lower().replace(" ", "-")
	var nodes: Array = []
	var yaml := "name: %s\ntopology:\n  kinds:\n    mikrotik_ros:\n      image: vrnetlab/mikrotik_ros:7.16\n    ceos:\n      image: ceos:4.32.0F\n    linux:\n      image: alpine:3.20\n  nodes:\n" % lab
	for d in all_devices():
		if d.type in ["cooling", "panel", "console"]:
			continue
		var node: String = d.name.to_lower()
		nodes.append(d.name)
		var kind := "linux"
		if d.type in ["switch", "router", "firewall", "loadbalancer", "ap"]:
			kind = "mikrotik_ros" if String(MODELS[d.model].get("os", "eos")) == "ros" else "ceos"
		yaml += "    %s:\n      kind: %s\n" % [node, kind]
		var cfg := ""
		match kind:
			"mikrotik_ros":
				cfg = CLI.new_session(d).exec("/export")
				yaml += "      startup-config: %s.rsc\n" % node
			"ceos":
				var ses := CLI.new_session(d)
				ses.exec("enable")
				cfg = ses.exec("show running-config")
				yaml += "      startup-config: %s.cfg\n" % node
			"linux":
				var lines: Array = []
				for i: Net.Iface in d.ifaces:
					var eth := _clab_iface(i)
					if eth == "":
						continue
					for cidr in i.ips:
						lines.append("ip addr add %s dev %s" % [cidr, eth])
				for r in d.static_routes:
					lines.append("ip route add %s via %s" % ["default" if int(r["plen"]) == 0 else "%s/%d" % [r["prefix"], int(r["plen"])], r["via"]])
				if not lines.is_empty():
					yaml += "      exec:\n"
					for line in lines:
						yaml += "        - %s\n" % line
		if cfg != "":
			var f := FileAccess.open("%s/%s.%s" % [dir, node, "rsc" if kind == "mikrotik_ros" else "cfg"], FileAccess.WRITE)
			if f != null:
				f.store_string(cfg)
	yaml += "  links:\n"
	for l in links:
		var a := _clab_iface(l.a)
		var b := _clab_iface(l.b)
		if a == "" or b == "" or l.a.dev.name not in nodes or l.b.dev.name not in nodes:
			continue
		yaml += "    - endpoints: [\"%s:%s\", \"%s:%s\"]\n" % [l.a.dev.name.to_lower(), a, l.b.dev.name.to_lower(), b]
	var yf := FileAccess.open("%s/%s.clab.yml" % [dir, lab], FileAccess.WRITE)
	if yf == null:
		return ""
	yf.store_string(yaml)
	log_event("EXPORTED: the floor is written out as a containerlab topology in %s." % dir)
	return yaml

func _clab_iface(i: Net.Iface) -> String:
	## containerlab keeps eth0 for management, so a device's first data port is eth1
	if i.name.begins_with("Management") or i.name == "lo" or i.name.begins_with("wg") \
			or i.name.begins_with("Vlan") or i.parent != "" or i.name.begins_with("radio"):
		return ""
	var digits := ""
	for ch in i.name:
		if ch.is_valid_int():
			digits += ch
	if digits == "":
		return ""
	var n := int(digits)
	if i.name.begins_with("eth"):
		n += 1  # Linux eth0 -> eth1
	return "eth%d" % n

func end_run(ending: String) -> String:
	## Freeze it. The save is untouched: this is a report, not a deletion.
	if not FINALE_ENDINGS.has(ending):
		return "that is not an ending"
	if not finale.is_empty():
		return "this run has already finished"
	finale = finale_snapshot(ending)
	var scored := finale_score(finale)
	finale["score"] = scored
	finale["record"] = record_run(finale)
	log_event("THE END: %s  %s scored %d." % [FINALE_ENDINGS[ending], company_name,
		int(scored["total"])])
	Legacy.harvest(FINALE_ENDINGS[ending])
	return ""

func finale_report() -> Array:
	if finale.is_empty():
		return []
	var scored := finale_score(finale)
	var callouts := finale_callouts(finale)
	var lines: Array = [
		"%s  ·  %s  ·  %s" % [finale["company"], finale["identity"], finale["difficulty"]],
		FINALE_ENDINGS.get(String(finale["ending"]), "It ended."),
		"cycle %d   ·   score %d" % [int(finale["cycle"]), int(scored["total"])],
	]
	for k: String in scored["categories"]:
		lines.append("  %-12s %d" % [k, int(scored["categories"][k])])
	lines.append("Customers at the end %d   ·   faults %d   ·   incidents %d   ·   longest clean streak %d cycles   ·   cash $%d" % [
		int(finale.get("deals", 0)), int(finale.get("faults", 0)), int(finale.get("incidents", 0)),
		int(finale.get("best_streak", 0)), int(finale.get("money", 0))])
	lines.append("Strongest: %s" % callouts["strength"])
	for loss: String in callouts["losses"]:
		lines.append("Avoidable: %s" % loss)
	return lines

func maybe_end_run() -> void:
	## Insolvency is an ending, not a slow bleed: it needs a real hole and a
	## few cycles of nobody fixing it.
	if not finale.is_empty() or sandbox or drill_active:
		return
	if sold_out:
		end_run("sold")
		return
	if money < -3000:
		stats["insolvent_cycles"] = int(stats.get("insolvent_cycles", 0)) + 1
		if int(stats["insolvent_cycles"]) >= 5:
			end_run("insolvent")
	else:
		stats["insolvent_cycles"] = 0

func rank_score() -> int:
	## lifetime earnings, weighted by the scale and quality of the operation
	var base: int = int(stats.get("earned", 0))
	var bonus: int = int(stats.get("contracts", 0)) * 500 + int(stats.get("deals", 0)) * 250 \
		+ stage * 4000 + (reputation - 50) * 40
	return maxi(0, base + bonus)

func identity_label() -> String:
	return IDENTITIES[identity]["label"] if identity != "" else "General operator"

func rank_index() -> int:
	var idx := 0
	for k in RANKS.size():
		if rank_score() >= int(RANKS[k][1]):
			idx = k
	return idx

func rank() -> String:
	var name: String = RANKS[0][0]
	for r in RANKS:
		if rank_score() >= int(r[1]):
			name = r[0]
	return name

func demo_summary() -> String:
	## One honest paragraph about the shift just worked, from what was recorded
	## while they worked it.
	var named: Array = []
	for entry: Dictionary in Skills.CATALOG:
		if int(skill_log.get(String(entry["id"]), {}).get("count", 0)) > 0:
			named.append(String(entry["name"]))
	var bits: Array = ["%d cycles on the floor" % cycle]
	if int(stats.get("contracts", 0)) > 0:
		bits.append("%d job(s) signed off" % int(stats.get("contracts", 0)))
	if best_outage_streak > 0:
		bits.append("a best run of %d cycles with nobody down" % best_outage_streak)
	if not named.is_empty():
		bits.append("and along the way you did %s" % ", ".join(PackedStringArray(named)))
	return "This shift: " + ", ".join(PackedStringArray(bits)) + "."

func rank_citation() -> String:
	## What this particular run did to earn it. Read off what the game already
	## keeps, so two players reaching the same rank are told different things.
	var bits: Array = []
	var reliable: Array = []
	for entry: Dictionary in Skills.CATALOG:
		var seen: Dictionary = skill_log.get(String(entry["id"]), {})
		if int(seen.get("count", 0)) >= Skills.RELIABLE:
			reliable.append(String(entry["name"]))
	if not reliable.is_empty():
		bits.append("you do %s without thinking about it now" % reliable[reliable.size() - 1])
	if mastered_contracts.size() >= 2:
		bits.append("%d job(s) finished the harder way" % mastered_contracts.size())
	if references.size() > 0:
		bits.append("%d customer(s) who will say so out loud" % references.size())
	if best_outage_streak >= 20:
		bits.append("a %d cycle stretch with nobody down" % best_outage_streak)
	if not skill_fumbles.is_empty():
		var fumble_ids: Array = skill_fumbles.keys()
		bits.append("and %s, which the trade also notices"
			% Skills.FUMBLES.get(String(fumble_ids[0]), "the odd bad night"))
	if bits.is_empty():
		return "mostly on the money, which is one way to do it"
	return ", ".join(PackedStringArray(bits))

func rank_tick() -> void:
	## A promotion is a moment, not a number crossing a line.
	var now := rank()
	if rank_seen == "":
		rank_seen = now
		return
	if now == rank_seen:
		return
	rank_seen = now
	log_event("PROMOTED: they would call you a %s now. Not for the money: %s."
		% [now.to_lower(), rank_citation()])
	Sfx.play("good")

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
	var speed := int(MODELS[i.dev.model].get("speed", 1000))
	return speed / 2 if licence_capped(i.dev) else speed

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

func power_draw(site := -1) -> int:
	## The draw of one floor. The bill is the company's; the heat is the room's.
	var w := 0
	for d in devices_on(site):
		if d.status == "active":
			w += WATTS.get(d.model, 0)
	return w

func power_draw_all() -> int:
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
	Sfx.play("good")
	if Contracts.SUPERSEDES.has(c["id"]):
		sla_status[Contracts.SUPERSEDES[c["id"]]] = true  # retire immediately, no stale breach
	stats["contracts"] += 1
	stats["earned"] += int(c["reward"])
	money += c["reward"]
	var debrief := _opening_contract_debrief(c)
	if not debrief.is_empty():
		contract_debriefs[String(c["id"])] = debrief
		active_contract_debrief = debrief
		log_event("DEBRIEF READY: %s is complete. The proof records what made it work." % c["title"])
	money_changed.emit()
	return true

func _iface_with_ip(ip: String) -> Net.Iface:
	var owner := Contracts._owner(ip)
	if owner == null:
		return null
	for iface: Net.Iface in owner.ifaces:
		for cidr: String in iface.ips:
			if cidr.split("/")[0] == ip:
				return iface
	return null

func _switch_link_for(dev: Net.NDevice) -> Dictionary:
	for iface: Net.Iface in dev.ifaces:
		var link := link_at(iface)
		if link == null:
			continue
		var far := link.other(iface)
		if far.dev.type == "switch":
			return {"local": iface, "switch": far.dev, "port": far}
	return {}

func _parallel_switch_group() -> Array:
	var groups := {}
	for link: Net.Link in links:
		if link.a.dev.type != "switch" or link.b.dev.type != "switch":
			continue
		var names := [link.a.dev.name, link.b.dev.name]
		names.sort()
		var key := "%s|%s" % names
		if not groups.has(key):
			groups[key] = []
		groups[key].append(link)
	var best: Array = []
	for key in groups:
		if groups[key].size() > best.size():
			best = groups[key]
	return best if best.size() >= 2 else []

func _opening_contract_debrief(c: Dictionary) -> Dictionary:
	var cid := String(c["id"])
	var base := {"id": cid, "title": String(c["title"]), "customer": String(c["customer"]),
		"reward": int(c["reward"]), "proof": []}
	match cid:
		"rackup":
			var rack: Net.Rack = racks[0] if not racks.is_empty() else null
			if rack == null:
				return {}
			var patches: Array = []
			for link: Net.Link in links:
				var server_end: Net.Iface = null
				var switch_end: Net.Iface = null
				if link.a.dev.type == "server" and link.b.dev.type == "switch":
					server_end = link.a; switch_end = link.b
				elif link.b.dev.type == "server" and link.a.dev.type == "switch":
					server_end = link.b; switch_end = link.a
				if server_end != null:
					patches.append("%s %s  ⇄  %s %s" % [server_end.dev.name, server_end.name,
						switch_end.dev.name, switch_end.name])
			base["proof"] = ["%s is physically installed with %d occupied device slots." % [rack.name,
				rack.slots.filter(func(d): return d != null).size()], "Two seated access patches: %s." % ",  ".join(PackedStringArray(patches.slice(0, 2)))]
			base["concept"] = "Physical layer first"
			base["practice"] = "Trace and label both ends before configuring a protocol."
			base["avoided"] = "No logical fix can rescue a server that is not physically patched."
			base["mastery"] = "Fit blanking panels in every unused rack unit."
		"first_ping":
			var left := _iface_with_ip("10.0.0.1")
			var right := _iface_with_ip("10.0.0.2")
			if left == null or right == null:
				return {}
			var left_path := _switch_link_for(left.dev)
			var right_path := _switch_link_for(right.dev)
			var path := "%s %s (10.0.0.1)  →  switched network  →  %s %s (10.0.0.2)" % [
				left.dev.name, left.name, right.dev.name, right.name]
			if not left_path.is_empty() and not right_path.is_empty() \
					and left_path["switch"] == right_path["switch"]:
				path = "%s %s  →  %s %s / %s  →  %s %s" % [left.dev.name, left.name,
					left_path["switch"].name, left_path["port"].name, right_path["port"].name,
					right.dev.name, right.name]
			base["proof"] = [path, "10.0.0.1 reached 10.0.0.2 on the live /24 without a gateway hop."]
			base["concept"] = "Same-subnet switching"
			base["practice"] = "ping 10.0.0.2"
			base["avoided"] = "A router was not added where one broadcast domain was enough."
			base["mastery"] = "Keep both server route tables empty; this path needs no gateway."
		"two_tenants":
			var sw: Net.NDevice = null
			for dev in all_devices():
				if dev.type == "switch" and dev.vlans.has(10) and dev.vlans.has(20):
					sw = dev; break
			if sw == null:
				return {}
			var vlan10: Array = []
			var vlan20: Array = []
			for iface: Net.Iface in sw.ifaces:
				if iface.mode != "access":
					continue
				var peer := peer_label(iface)
				if iface.untagged_vlan == 10:
					vlan10.append("%s%s" % [iface.name, " ⇄ " + peer if peer != "" else ""])
				elif iface.untagged_vlan == 20:
					vlan20.append("%s%s" % [iface.name, " ⇄ " + peer if peer != "" else ""])
			base["proof"] = ["%s keeps VLAN 10 on %s." % [sw.name, ", ".join(PackedStringArray(vlan10))],
				"%s keeps VLAN 20 on %s; the former ping is now correctly blocked." % [sw.name,
					", ".join(PackedStringArray(vlan20))]]
			base["concept"] = "Separate broadcast domains"
			base["practice"] = "/interface bridge vlan print" if String(MODELS[sw.model].get("os", "")) == "ros" else "show vlan"
			base["avoided"] = "Sharing an IPv4 prefix did not punch through the VLAN boundary."
			base["mastery"] = "Add 10.0.0.3 to VLAN 10 while keeping VLAN 20 isolated."
		"stretch_vlans":
			var trunk: Net.Link = null
			for link: Net.Link in links:
				if link.a.dev.type == "switch" and link.b.dev.type == "switch" \
						and link.a.mode == "trunk" and link.b.mode == "trunk":
					trunk = link; break
			if trunk == null:
				return {}
			var commands: Array = []
			for trunk_dev: Net.NDevice in [trunk.a.dev, trunk.b.dev]:
				commands.append("%s: %s" % [trunk_dev.name,
					"/interface bridge port print" if String(MODELS[trunk_dev.model].get("os", "")) == "ros"
					else "show interfaces trunk"])
			base["proof"] = ["Tagged path: %s %s  ⇄  %s %s; both ends are trunks." % [trunk.a.dev.name,
				trunk.a.name, trunk.b.dev.name, trunk.b.name],
				"10.0.0.3 reaches 10.0.0.1 across that link while 10.0.0.2 remains isolated."]
			base["concept"] = "802.1Q trunks carry several VLANs"
			base["practice"] = "  ·  ".join(PackedStringArray(commands))
			base["avoided"] = "Both trunk ends agree; a one-sided trunk would silently drop tagged traffic."
			base["mastery"] = "Prune every inter-switch trunk to VLANs 10 and 20 only."
		"redundant_core":
			var pair_links := _parallel_switch_group()
			if pair_links.size() < 2:
				return {}
			var paths: Array = []
			var blocked := ""
			for link: Net.Link in pair_links:
				paths.append("%s %s ⇄ %s %s" % [link.a.dev.name, link.a.name, link.b.dev.name, link.b.name])
				if Sim.stp_blocked(link.a):
					blocked = "%s %s" % [link.a.dev.name, link.a.name]
				elif Sim.stp_blocked(link.b):
					blocked = "%s %s" % [link.b.dev.name, link.b.name]
			var observe_dev: Net.NDevice = pair_links[0].a.dev
			base["proof"] = ["Parallel paths: %s." % "  /  ".join(PackedStringArray(paths)),
				"Spanning tree placed %s in discarding state; Alfa still has one forwarding path." % blocked]
			base["concept"] = "A loop-free spare path"
			base["practice"] = "/interface bridge port print" if String(MODELS[observe_dev.model].get("os", "")) == "ros" else "show spanning-tree"
			base["avoided"] = "The second cable did not create a broadcast storm."
			base["mastery"] = "Disable the forwarding member and prove Alfa still crosses the spare."
		"two_offices":
			var office_a := _iface_with_ip("192.168.1.10")
			var office_b := _iface_with_ip("192.168.2.10")
			var gw_a := _iface_with_ip("192.168.1.1")
			var gw_b := _iface_with_ip("192.168.2.1")
			if office_a == null or office_b == null or gw_a == null or gw_b == null \
					or gw_a.dev != gw_b.dev:
				return {}
			var router := gw_a.dev
			base["proof"] = ["%s %s (192.168.1.10)  →  gateway %s %s (192.168.1.1)." % [
				office_a.dev.name, office_a.name, router.name, gw_a.name],
				"%s routes into %s (192.168.2.1)  →  %s %s (192.168.2.10); replies return through the same router." % [
					router.name, gw_b.name, office_b.dev.name, office_b.name]]
			base["concept"] = "A router joins different IP subnets"
			base["practice"] = "/tool traceroute 192.168.2.10" if String(MODELS[router.model].get("os", "")) == "ros" else "traceroute 192.168.2.10"
			base["avoided"] = "The hosts do not pretend remote addresses are on their local wire."
			base["mastery"] = "Save the working configuration on %s." % router.name
		_:
			return _later_contract_debrief(c, base)
	return base

func _later_contract_debrief(c: Dictionary, base: Dictionary) -> Dictionary:
	## The same rule as the opening six: every line is read off the player's own
	## devices, and a job whose evidence is not there returns nothing at all.
	var cid := String(base["id"])
	match cid:
		"join_internet":
			var speaker: Net.NDevice = null
			var neighbour := ""
			for d: Net.NDevice in all_devices():
				for nb in d.bgp.get("neighbors", []):
					if Sim.bgp_established(d, nb):
						speaker = d
						neighbour = String(nb.get("ip", ""))
			if speaker == null:
				return {}
			base["proof"] = ["%s holds an established eBGP session with %s." % [speaker.name,
				neighbour],
				"Its table carries %d announced prefix(es), and a default arrives from upstream."
					% speaker.bgp.get("networks", []).size()]
			base["concept"] = "Somebody else's network, on purpose"
			base["practice"] = _dialect_cmd(speaker, "/routing bgp session print", "show ip bgp summary")
			base["avoided"] = "The default route is learned, not invented, so it disappears when the session does."
			base["mastery"] = "Keep the session up while announcing your own prefix."
		"hide_the_internals":
			var outside: Net.Iface = null
			for d2: Net.NDevice in all_devices():
				for i: Net.Iface in d2.ifaces:
					if i.nat == "outside":
						outside = i
			if outside == null:
				return {}
			base["proof"] = ["%s %s is the outside interface; private sources leave as %s." % [
				outside.dev.name, outside.name,
				outside.ips[0] if not outside.ips.is_empty() else "its own address"],
				"Return traffic is matched back to the machine that sent it, which is why one address serves many."]
			base["concept"] = "Source NAT, and the state it keeps"
			base["practice"] = _dialect_cmd(outside.dev, "/ip firewall nat print", "show ip nat translations")
			base["avoided"] = "Nothing inside had to be renumbered to reach the internet."
			base["mastery"] = "Reach the internet from two machines behind the same address."
		"dynamic_routing":
			var ospf_devs: Array = []
			for d3: Net.NDevice in all_devices():
				if not d3.ospf.is_empty():
					ospf_devs.append(d3.name)
			if ospf_devs.size() < 2:
				return {}
			base["proof"] = ["%s are running OSPF and have formed an adjacency." % ", ".join(
					PackedStringArray(ospf_devs.slice(0, 3))),
				"Routes appear and disappear on their own, which is the entire difference from static."]
			base["concept"] = "Routers telling each other what they know"
			base["practice"] = "show ip ospf neighbor"
			base["avoided"] = "Nobody has to remember to add a static route when the topology changes."
			base["mastery"] = "Break one path and watch the table reconverge without you."
		"no_spof":
			var vip := ""
			var members: Array = []
			for d4: Net.NDevice in all_devices():
				for i2: Net.Iface in d4.ifaces:
					if String(i2.vrrp.get("vip", "")) != "":
						vip = String(i2.vrrp["vip"])
						members.append("%s %s (priority %d)" % [d4.name, i2.name,
							int(i2.vrrp.get("priority", 100))])
			if members.size() < 2:
				return {}
			base["proof"] = ["Virtual address %s is served by %s." % [vip,
					" and ".join(PackedStringArray(members))],
				"The hosts point at one gateway address that outlives either router."]
			base["concept"] = "A gateway that is not a single box"
			base["practice"] = "show vrrp"
			base["avoided"] = "Nothing had to be reconfigured on the hosts when the master changed."
			base["mastery"] = "Take the master away and keep the hosts online."
		"double_the_pipe":
			var bundle: Array = []
			for l: Net.Link in links:
				if l.a.lag > 0 and l.b.lag > 0:
					bundle.append("%s %s ⇄ %s %s" % [l.a.dev.name, l.a.name, l.b.dev.name, l.b.name])
			if bundle.size() < 2:
				return {}
			base["proof"] = ["One logical link over %d members: %s." % [bundle.size(),
					"  /  ".join(PackedStringArray(bundle.slice(0, 3)))],
				"Capacity is the sum of the live members, and losing one is a slowdown rather than an outage."]
			base["concept"] = "Bundling links instead of blocking them"
			base["practice"] = "show port-channel summary"
			base["avoided"] = "Spanning tree did not throw the second cable away."
			base["mastery"] = "Pull one member and keep the traffic flowing."
		"two_sites":
			if circuits.is_empty() or site_count() < 2:
				return {}
			var circuit: Dictionary = circuits[0]
			base["proof"] = ["A %d Mbps circuit from %s joins %s and %s." % [
					int(circuit.get("mbps", 0)), circuit.get("carrier", "a carrier"),
					site_name(int(circuit.get("a", 0))), site_name(int(circuit.get("b", 1)))],
				"The two floors are one network, and the circuit is billed whether you use it or not."]
			base["concept"] = "Somebody else's fibre, rented by the cycle"
			base["practice"] = "traceroute across the circuit and watch the latency"
			base["avoided"] = "Neither site pretends the other is on its own wire."
			base["mastery"] = "Keep both sites delivering while one carrier is down."
		"dual_stack":
			var v6 := _iface_with_ip("2001:db8:70::10")
			if v6 == null:
				return {}
			base["proof"] = ["%s %s holds 2001:db8:70::10 alongside its IPv4 address." % [
					v6.dev.name, v6.name],
				"Neighbour Discovery does the work ARP used to, on the same wire, at the same time."]
			base["concept"] = "Two protocols, one network"
			base["practice"] = "show ipv6 neighbors"
			base["avoided"] = "Nothing had to be turned off to add the second family."
			base["mastery"] = "Reach the far host over IPv6 with the IPv4 path shut."
		"v6_only_tenant":
			var translator: Net.NDevice = null
			for d5: Net.NDevice in all_devices():
				if not Sim.nat64_of(d5).is_empty():
					translator = d5
			if translator == null:
				return {}
			var n64 := Sim.nat64_of(translator)
			base["proof"] = ["%s translates %s into IPv4 from the pool %s." % [translator.name,
					n64.get("prefix", ""), n64.get("pool", "")],
				"The tenant never received an IPv4 address, and the legacy service never learned IPv6."]
			base["concept"] = "Naming and translation are two separate halves"
			base["practice"] = "show nat64"
			base["avoided"] = "No dual-stack was forced on either end to make them talk."
			base["mastery"] = "Keep native IPv6 traffic out of the translator entirely."
		"overlay_tenant":
			var vteps: Array = []
			for d6: Net.NDevice in all_devices():
				if not d6.vtep.is_empty() and String(d6.vtep.get("src", "")) != "":
					vteps.append(d6)
			if vteps.size() < 2:
				return {}
			var first: Net.NDevice = vteps[0]
			var vni := 0
			for vlan: int in first.vtep.get("map", {}):
				vni = int(first.vtep["map"][vlan])
			base["proof"] = ["%s and %s carry VNI %d over a routed underlay." % [vteps[0].name,
					vteps[1].name, vni],
				"The tenant's segment crosses a network that has no idea it is carrying layer 2."]
			base["concept"] = "A segment that does not need a cable between the switches"
			base["practice"] = "show vxlan"
			base["avoided"] = "Nobody had to stretch a VLAN across the fabric to do it."
			base["mastery"] = "Let the control plane advertise instead of flooding."
		"big_client":
			var fw: Net.NDevice = null
			for d7: Net.NDevice in all_devices():
				if d7.type == "firewall" and not d7.acls.is_empty():
					fw = d7
			if fw == null:
				return {}
			base["proof"] = ["%s enforces %d rule(s) in front of the customer segment." % [fw.name,
					fw.acls.size()],
				"Everything they audited (their VLAN, their address, the rule, the routing, the managed switch) is live at once."]
			base["concept"] = "An estate, rather than a collection of devices"
			base["practice"] = "show ip access-lists"
			base["avoided"] = "No single requirement was met by breaking another one."
			base["mastery"] = "Keep every one of their requirements true for a full quarter."
		_:
			return {}
	return base

func _dialect_cmd(dev: Net.NDevice, ros: String, eos: String) -> String:
	return ros if String(MODELS[dev.model].get("os", "")) == "ros" else eos

func contract_mastery_met(cid: String) -> bool:
	match cid:
		"join_internet":
			var announced := false
			for d: Net.NDevice in all_devices():
				for nb in d.bgp.get("neighbors", []):
					if Sim.bgp_established(d, nb) and not d.bgp.get("networks", []).is_empty():
						announced = true
			return announced
		"hide_the_internals":
			var behind := 0
			for d2: Net.NDevice in all_devices():
				if d2.type != "server":
					continue
				for i2: Net.Iface in d2.ifaces:
					for cidr in i2.ips:
						if String(cidr).begins_with("10.") or String(cidr).begins_with("192.168."):
							behind += 1
							break
			return behind >= 2
		"no_spof":
			for d3: Net.NDevice in all_devices():
				for i3: Net.Iface in d3.ifaces:
					if String(i3.vrrp.get("vip", "")) != "" and not i3.enabled:
						return true  # the master is away and the address is still served
			return false
		"double_the_pipe":
			for l: Net.Link in links:
				if l.a.lag > 0 and (not l.a.enabled or not l.b.enabled):
					return true  # a member is down and the bundle is still up
			return false
		"dual_stack":
			var v6_owner := Contracts._owner("2001:db8:71::10")
			return v6_owner != null and Sim.ping(v6_owner, "2001:db8:70::10")["ok"]
		"v6_only_tenant":
			for d4: Net.NDevice in all_devices():
				if not Sim.nat64_of(d4).is_empty() and int(Sim.nat64_of(d4).get("translated", 0)) > 0:
					return true
			return false
		"overlay_tenant":
			for d5: Net.NDevice in all_devices():
				if not d5.vtep.is_empty() and bool(d5.vtep.get("evpn", false)) \
						and not d5.remote_macs.is_empty():
					return true
			return false
		"rackup":
			for rack: Net.Rack in racks:
				for slot in Net.Rack.SLOTS:
					if slot_free(rack, slot) and not rack.blanked.has(slot):
						return false
			return not racks.is_empty()
		"first_ping":
			var left := Contracts._owner("10.0.0.1")
			var right := Contracts._owner("10.0.0.2")
			return left != null and right != null and left.static_routes.is_empty() \
				and right.static_routes.is_empty() and Sim.ping(left, "10.0.0.2")["ok"]
		"two_tenants":
			return Contracts._owner("10.0.0.3") != null \
				and Sim.ping(Contracts._owner("10.0.0.3"), "10.0.0.1")["ok"] \
				and not Sim.ping(Contracts._owner("10.0.0.3"), "10.0.0.2")["ok"]
		"stretch_vlans":
			var any := false
			for link: Net.Link in links:
				if link.a.dev.type != "switch" or link.b.dev.type != "switch" \
						or link.a.mode != "trunk" or link.b.mode != "trunk":
					continue
				any = true
				for end: Net.Iface in [link.a, link.b]:
					var allowed := end.tagged_vlans.duplicate()
					allowed.sort()
					if allowed != [10, 20]:
						return false
			return any
		"redundant_core":
			var pair_links := _parallel_switch_group()
			if pair_links.size() < 2:
				return false
			var disabled_member := false
			for link: Net.Link in pair_links:
				if not link.a.enabled or not link.b.enabled:
					disabled_member = true
			var alfa := Contracts._owner("10.0.0.1")
			return disabled_member and alfa != null and Sim.ping(alfa, "10.0.0.3")["ok"]
		"two_offices":
			var gw_a := _iface_with_ip("192.168.1.1")
			var gw_b := _iface_with_ip("192.168.2.1")
			return gw_a != null and gw_b != null and gw_a.dev == gw_b.dev \
				and not gw_a.dev.startup.is_empty()
	return false

func check_contract_mastery(cid: String) -> String:
	if not contract_debriefs.has(cid):
		return "complete the contract before attempting mastery"
	if cid in mastered_contracts:
		return ""
	if not contract_mastery_met(cid):
		return "mastery condition is not live yet"
	mastered_contracts.append(cid)
	log_event("MASTERED: %s was completed with the optional operating constraint." % cid)
	money_changed.emit()
	return ""

func dismiss_contract_debrief() -> void:
	active_contract_debrief = {}

const SLA_PERIOD := 45.0  # seconds per billing cycle

var sla_status := {}  # contract id -> bool (last billing check passed)
var last_link_load := {}  # Link -> Mbps, from the latest cycle
var last_cycle_delta := 0
var invoices: Array = []  # money billed but not yet in the bank
const CHASE_REPUTATION := 1  # nagging a customer costs a little goodwill
const WRITE_OFF_AFTER := 8  # cycles past due before it is never coming
var feeds := {}  # site -> {"A": true, "B": true}; false while that feed is out
var feed_out_until := {}  # "site|feed" -> cycle the utility expects to be back
var ups := {}  # site -> cycles of battery the UPS can still cover
const UPS_PRICE := 1800
const UPS_CYCLES := 3  # how long a full battery holds a dead feed up
var _pristine := {}  # what a brand new game looks like
var last_pl := {}  # line item -> amount, from the latest cycle
var last_business := {"revenue": 0, "invoiced": 0, "collected": 0,
	"power": 0, "transit": 0}  # profit and cash timing are related, not identical
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
		slot_prefix = "user://slot_test"
		Legacy.path = "user://legacy_test.json"
		history_path = "user://run_history_test.json"
	Legacy.load_file()
	Pack.load_all()  # authored content, if anybody has written any
	topology_changed.connect(Sim.prune_learned_state)
	cycle_timer = Timer.new()
	cycle_timer.wait_time = SLA_PERIOD
	cycle_timer.autostart = true
	cycle_timer.timeout.connect(sla_tick)
	add_child(cycle_timer)
	set_speed(speed)
	_ensure_sites()
	_pristine = _serialize()  # a snapshot of an untouched game, for New Game

func reset_run_state() -> void:
	## per-run state that is never carried over: without this a second company
	## inherits the first one's totals, its breach flags and its ticket numbers
	stats = {"earned": 0, "incidents": 0, "faults": 0, "contracts": 0, "deals": 0}
	sla_status = {}
	digest = {}
	lockout_state = {}
	unread_events = 0

func reset_new(company: String, diff: int, is_demo: bool) -> void:
	## start over from the state the game boots into, rather than trying to
	## remember by hand which of the several dozen fields need clearing
	Legacy.harvest("the company was wound up")  # the outgoing run, before it is gone
	_apply(_pristine.duplicate(true))
	company_name = company if company.strip_edges() != "" else "Packet Empire"
	demo = is_demo
	apply_difficulty(diff)
	rivals = Rivals.spawn()
	_scale_rival_aggression()
	Legacy.apply_carried()
	arrival_note()
	topology_changed.emit()

const ARRIVAL_LANDLORDS := [
	{"who": "Bergendy, who owns the building and three others like it",
		"line": "Bergendy shows you the corner, points at the meter, and leaves. The lease says the power is included; the lease is four years old."},
	{"who": "a facilities manager who calls this cage 'the old bay'",
		"line": "The facilities manager unlocks the cage, says the old bay has been empty since the last lot went under, and does not say why."},
	{"who": "somebody from the colo who hands you a key and a fire briefing",
		"line": "The colo hands you a key, a fire briefing nobody reads, and the number of a technician who no longer works here."},
]
const ARRIVAL_LEFTOVERS := [
	"A coil of somebody else's patch cable is still hanging on the cage wall.",
	"There is a rack rail and no rack, and a label that says PLEASE DO NOT REMOVE.",
	"Someone left a chair, a kettle, and a printed diagram of a network that no longer exists.",
]

func arrival_note() -> void:
	## The first two minutes are a place and a person, not a menu. Everything
	## here is authored, deterministic per company name, and never blocking.
	if demo:
		return
	var seed_key := absi((company_name + DIFFICULTIES[difficulty]["name"]).hash())
	var landlord: Dictionary = ARRIVAL_LANDLORDS[seed_key % ARRIVAL_LANDLORDS.size()]
	log_event("ARRIVAL: %s" % landlord["line"])
	log_event("ARRIVAL: %s" % ARRIVAL_LEFTOVERS[(seed_key / 3) % ARRIVAL_LEFTOVERS.size()])
	# one line that is true only for this run
	if identity != "":
		log_event("ARRIVAL: you already know what sort of shop this is going to be: %s."
			% IDENTITIES[identity]["label"].to_lower())
	elif not Legacy.selected.is_empty() or not Legacy.epitaph.is_empty():
		log_event("ARRIVAL: %s ran for %d cycles before this. Some of it came with you."
			% [Legacy.epitaph.get("company", "The last company"),
				int(Legacy.epitaph.get("cycles", 0))])
	else:
		log_event("ARRIVAL: %s, on the %s footing: %s"
			% [company_name, String(DIFFICULTIES[difficulty]["name"]).to_lower(),
				DIFFICULTIES[difficulty]["blurb"]])
	log_event("ARRIVAL: your first job is on the contracts board, and the customer is already waiting.")

func respond_offer(offer: Dictionary, quote: int) -> String:
	var blocked := can_accept_offer(offer)
	if blocked != "":
		return "blocked:" + blocked
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
			if not rival.is_empty():
				Rivals.remember(rival, -1, "you took %s off them" % offer["customer"])
				log_event("MARKET: %s heard you won %s. %s" % [rival["name"], offer["customer"],
					Rivals.temper_of(rival)["win"]])
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
				_remediation_verify(m, true)
			else:
				log_event("MONITOR ALERT: %s is failing." % monitor_label(m))
				_remediation_fire(m)  # act at once, then keep working it in the tick

const REMEDIATION_COOLDOWN := 6  # cycles before the same alert may act again
const REMEDIATION_RETRIES := 2  # attempts before it stops and asks for a person

func bind_remediation(m: Dictionary, rb: Dictionary) -> String:
	## One monitor, one runbook. Automation that fans out is not automation you
	## can explain afterwards.
	if rb.is_empty():
		m.erase("remediation")
		return ""
	m["remediation"] = {"runbook": String(rb["name"]), "last_fired": -999, "failures": 0,
		"timeline": []}
	log_event("AUTOMATION: '%s' is now bound to the alert '%s'." % [rb["name"], monitor_label(m)])
	return ""

func _remediation_note(m: Dictionary, text: String) -> void:
	var rem: Dictionary = m.get("remediation", {})
	if rem.is_empty():
		return
	var line: Array = rem.get("timeline", [])
	line.append("cycle %d · %s" % [cycle, text])
	if line.size() > 12:
		line.pop_front()
	rem["timeline"] = line

func _remediation_fire(m: Dictionary) -> void:
	var rem: Dictionary = m.get("remediation", {})
	if rem.is_empty():
		return
	_remediation_note(m, "trigger: %s went down" % monitor_label(m))
	if in_maintenance():
		_remediation_note(m, "suppressed: a change window is open")
		return
	if cycle - int(rem["last_fired"]) < REMEDIATION_COOLDOWN:
		# a flapping check must not become an action storm
		_remediation_note(m, "held: inside the cooldown from the last attempt")
		return
	if int(rem["failures"]) >= REMEDIATION_RETRIES:
		_remediation_note(m, "escalated: it has tried twice and stopped")
		log_event("AUTOMATION: '%s' has stopped trying and wants a person." % rem["runbook"])
		return
	var rb := {}
	for entry: Dictionary in runbooks:
		if String(entry["name"]) == String(rem["runbook"]):
			rb = entry
	if rb.is_empty():
		_remediation_note(m, "skipped: the runbook it names no longer exists")
		return
	rem["last_fired"] = cycle
	_remediation_note(m, "evidence: %s" % monitor_label(m))
	var run := run_runbook(rb, false, true)
	if String(run.get("refused", "")) != "":
		_remediation_note(m, "refused: %s" % run["refused"])
		return
	rem["pending"] = true
	_remediation_note(m, "action: %s on %s" % [RUNBOOK_ACTIONS[rb["action"]]["label"],
		", ".join(PackedStringArray(run["applied"]))])

func _remediation_verify(m: Dictionary, recovered: bool) -> void:
	var rem: Dictionary = m.get("remediation", {})
	if rem.is_empty() or not bool(rem.get("pending", false)):
		return
	rem["pending"] = false
	if recovered:
		rem["failures"] = 0
		_remediation_note(m, "verified: the service came back")
		log_event("AUTOMATION: '%s' fixed it, hands off." % rem["runbook"])
	else:
		rem["failures"] = int(rem["failures"]) + 1
		_remediation_note(m, "unverified: still failing after the action")

func remediation_tick() -> void:
	## Automation works the alert while it is active, not only at the moment it
	## fired, and an action that did not restore the service counts against it.
	for m in monitors:
		var rem: Dictionary = m.get("remediation", {})
		if rem.is_empty():
			continue
		if bool(rem.get("pending", false)) and cycle - int(rem["last_fired"]) >= 2:
			_remediation_verify(m, not bool(m.get("failing", false)))
		if bool(m.get("failing", false)) and not bool(rem.get("pending", false)):
			_remediation_fire(m)

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
	# a company people have heard good things about attracts better applicants
	var pool := 3 + int(reputation / 40)
	for i in pool:
		var c := Staff.make_candidate(rng)
		if reputation >= 65 and rng.randf() < 0.4:
			c["skill"] = mini(5, int(c["skill"]) + 1)
			c["ask"] = int(float(c["ask"]) * 1.15)
			c["salary"] = c["ask"]
		candidates.append(c)

func offer_job(candidate: Dictionary, salary: int) -> String:
	## Negotiating: below their asking price they may take it, push back, or
	## walk. A good reputation makes people want to work for you.
	if salary >= int(candidate["ask"]):
		candidate["salary"] = salary
		return hire(candidate)
	var gap := float(int(candidate["ask"]) - salary) / float(maxi(1, int(candidate["ask"])))
	var tolerance := 0.08 + float(reputation) / 100.0 * 0.22
	if gap <= tolerance:
		candidate["salary"] = salary
		log_event("HIRING: %s accepted $%d, below their asking price." % [candidate["name"], salary])
		return hire(candidate)
	if gap <= tolerance * 2.0:
		candidate["counter"] = int(round(float(int(candidate["ask"])) * (1.0 - tolerance * 0.5)))
		return "counter"
	candidates.erase(candidate)
	log_event("HIRING: %s turned you down and took something else." % candidate["name"])
	return "walked"

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

func drop_duties_of(name: String) -> void:
	for k in duties.keys():
		if String(duties[k]) == name:
			duties.erase(k)
	_sync_duty_policies()

func fire(member: Dictionary) -> void:
	staff.erase(member)
	drop_duties_of(String(member.get("name", "")))
	if String(member.get("name", "")) == oncall:
		oncall = ""  # nobody is carrying the phone until somebody else is asked
	if String(member.get("name", "")) == callout_who:
		callout_who = ""  # and nobody who has left is still in the building
		callout_until = -1
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

func _inherit_neglect(site: int, from_whom: String) -> void:
	## You are not buying a room, you are buying somebody else's habits. The
	## diary arrives with their last service dates on it, not with yours.
	var overdue: Array = []
	var spread := 0
	for task: String in FACILITY_TASKS:
		var every := int(FACILITY_TASKS[task]["every"])
		# between one and one and a half periods overdue: bad, not ruinous.
		# Derived rather than rolled, so buying a company does not disturb the
		# seeded business stream every other event is drawn from.
		spread += 1
		var behind := every + (site * 7 + spread * 11) % maxi(1, every / 2)
		facility[facility_key(task, site)] = cycle - behind
		if facility_due_in(task, site) < 0:
			overdue.append(String(FACILITY_TASKS[task]["label"]).to_lower())
	if not overdue.is_empty():
		log_event("ACQUISITION: %s's building comes with %s's diary: %s all overdue. Their protection was never fitted either."
			% [from_whom, from_whom, ", ".join(PackedStringArray(overdue))])

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
		_inherit_neglect(target_site, String(r["name"]))
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
			var dev := new_device(model, true)  # their serials, not your licences
			dev.acquired_from = r["name"]
			install_device(rack, slot, dev)
			slot += model_height(model)
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
	# Inherited customers are not blank: they were somebody's customers, and
	# they have an opinion about the company that just bought them.
	var standing := int(r.get("standing", 0))
	var struggling := int(r.get("deals", 0)) <= 1 or not Rivals.has_site(r)
	var stance := 0.55
	if struggling:
		stance += 0.15  # they were being let down and are willing to be pleased
	stance += clampf(float(standing) * 0.05, -0.15, 0.15)
	stance += clampf(float(reputation - 50) / 200.0, -0.15, 0.15)
	stance = clampf(stance, 0.2, 0.9)
	for i in int(r["deals"]):  # inherited customers, hosted on their kit
		var served: String = host_ips[i % host_ips.size()] if not host_ips.is_empty() else ""
		deals.append({"id": "acq_%s_%d" % [r["name"], i], "customer": "%s customer %d" % [r["name"], i + 1],
			"kind": "hosting", "params": {"ip": served}, "fee": 90, "load": 150,
			"brief": "Inherited from %s: their server at %s must stay reachable." % [r["name"], served],
			"healthy": true, "acquired": true, "loyalty": stance})
	if int(r["deals"]) > 0:
		log_event("ACQUISITION: %s's customers have been told. %s" % [r["name"],
			"They were not being looked after and are prepared to like you."
			if stance >= 0.65 else ("They are watching to see whether this was good news."
			if stance >= 0.45 else "They did not ask to be sold, and it shows.")])
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
	fee = int(round(float(fee) * identity_fee_multiplier(String(offer.get("kind", "")))))
	stats["deals"] += 1
	deals.append({"id": offer["id"], "customer": offer["customer"], "kind": offer["kind"],
		"params": offer["params"], "fee": fee, "brief": offer["brief"],
		"term": 14 + randi() % 10,  # how long before it comes up for renewal
		"budget": int(offer.get("budget", fee)),  # the market reference for poaching
		"ctype": offer.get("ctype", "enterprise"), "loyalty": float(offer.get("loyalty", 0.6)),
		"public": bool(offer.get("public", false)),
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

## Words that decide how loudly an event should be shouted. Matched against
## the start of the message, which is why every log line leads with a tag.
const SEVERE := ["SLA BREACH", "SLA PENALTY", "SECURITY", "WRITTEN OFF", "LOST", "PORT SECURITY",
	"FAULT", "ATTACK", "POWER", "FIRE", "DATA INCIDENT", "LOCKED OUT", "HAZARD",
	"PREDICTED FAILURE", "OVERRUN", "CANCELLED", "THE PHONE"]
const WARNING := ["LATE", "CONGESTION", "RENEWAL", "POACH", "STAFF", "HEAT",
	"STORM CONTROL", "DHCP snooping", "ARP inspection", "RIVAL", "MONITOR ALERT", "MONITOR OK", "FIELD",
	"ACHIEVEMENT", "UPSTREAM", "ALARM", "LAPSED", "DUE", "BLAME", "DISPUTE", "ACCESS",
	"FIRMWARE", "SUPPLY", "IMPROVISED", "BLOCKED", "GENERATOR TEST", "SUPPRESSION",
	"CALL-OUT", "HANDOVER", "FAILOVER TEST", "TRANSFER", "CARRIER", "ROTA"]

static func event_severity(text: String) -> String:
	var body := text
	var colon := body.find(": ")
	var head := body.substr(0, colon) if colon > 0 else body
	for word in SEVERE:
		if head.begins_with(word) or body.begins_with(word):
			return "critical"
	for word2 in WARNING:
		if head.begins_with(word2) or body.begins_with(word2):
			return "warning"
	return "info"

var unread_events := 0  # since the player last looked at the log

var events_logged := 0  # monotonic: events is capped, so its size cannot count

const DIGEST_PREFIX := "SHIFT NOTES"
## Lines that are routine on their own but must never be folded away: anything
## that asks for a decision, names a customer, or is the game teaching.
const DIGEST_EXEMPT := ["ARRIVAL", "PROMOTED", "SEASON", "FIRST LIGHT", "LIVE", "CREW", "THE PHONE", "YOU SAID", "KEPT IT", "DECISION", "STORY", "STORY PAYOFF", "STORY ENDING", "LEARNED",
	"TICKET", "VISIT", "VISIT BOOKED", "AUDIT", "AUDIT OFFERED", "AUDIT RESULT", "DEBRIEF READY",
	"RELATIONSHIP", "THE END", "CHALLENGE", "PACK", "HEADS UP", "CARRIED IT", "DROPPED IT",
	"CONSEQUENCE", "LATER", "IDENTITY", "NEMESIS", "REFERRAL", "MASTERED"]
var digest := {}  # cycle -> the routine lines folded into that cycle's note

func _digest_exempt(text: String) -> bool:
	var head := text.substr(0, maxi(0, text.find(":")))
	return head in DIGEST_EXEMPT

func _digest_line(at: int) -> String:
	var lines: Array = digest.get(at, [])
	var preview: Array = []
	for line: String in lines.slice(0, 2):
		var cut := String(line)
		if cut.length() > 48:
			var at_space := cut.rfind(" ", 48)
			cut = cut.substr(0, at_space if at_space > 20 else 48) + "…"
		preview.append(cut)
	return "cycle %d: %s: %d routine thing(s) handled: %s" % [at, DIGEST_PREFIX, lines.size(),
		"; ".join(PackedStringArray(preview))]

func log_event(text: String) -> void:
	events_logged += 1
	if event_severity(text) == "info" and not _digest_exempt(text):
		# routine work folds into one note per cycle: nothing is dropped, and
		# the log stops burying the line that mattered
		var lines: Array = digest.get(cycle, [])
		lines.append(text)
		digest[cycle] = lines
		for idx in events.size():
			if String(events[idx]).begins_with("cycle %d: %s" % [cycle, DIGEST_PREFIX]):
				events[idx] = _digest_line(cycle)
				events_changed.emit()
				return
		events.push_front(_digest_line(cycle))
	else:
		events.push_front("cycle %d: %s" % [cycle, text])
		if event_severity(text) != "info":
			unread_events += 1
	if events.size() > 60:
		events.pop_back()
	if digest.size() > 40:
		var oldest := cycle
		for key in digest:
			oldest = mini(oldest, int(key))
		digest.erase(oldest)
	events_changed.emit()

func digest_for(at: int) -> Array:
	return digest.get(at, [])

func log_contains(text: String) -> bool:
	## Folded lines are still in the log, which is the promise: nothing is
	## dropped, only tucked into the cycle's shift notes.
	## Recent history only: the log keeps sixty lines, so never use this to
	## decide whether something ever happened. Count it in stats instead.
	for e: String in events:
		if text in e:
			return true
	for at in digest:
		for line: String in digest[at]:
			if text in line:
				return true
	return false

func mark_events_read() -> void:
	unread_events = 0
	events_changed.emit()

func events_by_severity(level: String) -> Array:
	## level: "all", "critical" or "warning" (warning includes critical, since
	## nobody filtering for problems wants the worse ones hidden)
	var out: Array = []
	for e: String in events:
		var body := String(e)
		var at := body.find(": ")
		var msg := body.substr(at + 2) if at > 0 else body
		var sev := event_severity(msg)
		if level == "all" or sev == "critical" or (level == "warning" and sev == "warning"):
			out.append({"line": body, "severity": sev})
	return out

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
	observe_habit("windows", true, 2.0)
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
	if outage_open() or upstream_active():
		Skills.observe("incident_comms")
	status_posts.push_front({"cycle": cycle, "text": text.strip_edges()})
	if status_posts.size() > 12:
		status_posts.pop_back()
	log_event("STATUS PAGE: \"%s\"" % text.strip_edges())
	if guided_outage_active() and String(guided_outage.get("state", "")) in ["acknowledged", "investigating"]:
		guided_outage["state"] = "communicated"
		guided_outage["status_cycle"] = cycle
		guided_outage["reputation_saved"] = 2
		_guided_outage_note("cycle %d · customer update posted; reputation loss reduced by 2 each outage cycle" % cycle)
		log_event(Loc.t("event.outage.status", {"customer": "Kiskacsa"}))
		guided_outage_changed.emit()
	return ""

func status_posted_recently() -> bool:
	for p in status_posts:
		if cycle - int(p["cycle"]) <= 2:
			return true
	return false

func guided_outage_active() -> bool:
	return not guided_outage.is_empty() and String(guided_outage.get("state", "")) not in ["", "complete"]

func _guided_outage_note(text: String) -> void:
	var notes: Array = guided_outage.get("timeline", [])
	notes.append(text)
	guided_outage["timeline"] = notes

func _named_iface(dev_name: String, iface_name: String) -> Net.Iface:
	for d in all_devices():
		if d.name != dev_name:
			continue
		for iface: Net.Iface in d.ifaces:
			if iface.name == iface_name:
				return iface
	return null

func guided_outage_iface() -> Net.Iface:
	return _named_iface(String(guided_outage.get("device", "")),
		String(guided_outage.get("iface", "")))

func _maybe_start_guided_outage() -> void:
	if int(stats.get("guided_delivery_acknowledged", 0)) == 0 \
			or int(stats.get("guided_outage_complete", 0)) != 0 or not guided_outage.is_empty():
		return
	var deal := guided_customer_deal()
	if deal.is_empty() or not bool(deal.get("healthy", false)):
		return
	var host := Contracts._owner(String(deal["params"].get("ip", "")))
	if host == null:
		return
	# Trip the access port opposite the tutorial host. It is deterministic,
	# reversible, and never rewrites addressing, VLANs, routes, or player cables.
	var chosen: Net.Iface = null
	var host_iface: Net.Iface = null
	for iface: Net.Iface in host.ifaces:
		var link := link_at(iface)
		if link == null or not iface.enabled:
			continue
		var far := link.other(iface)
		if not far.enabled:
			continue
		var carries_other_customer := false
		for other: Dictionary in deals:
			if other == deal or not bool(other.get("healthy", false)):
				continue
			if link in _deal_path_links(other):
				carries_other_customer = true
				break
		if carries_other_customer:
			continue  # the teaching fault is never allowed collateral damage
		chosen = far
		host_iface = iface
		break
	if chosen == null:
		return
	var source := ""
	var target_ip := String(deal["params"].get("ip", ""))
	for d in all_devices():
		if d != host and Sim.ping(d, target_ip)["ok"]:
			source = d.name
			break
	guided_outage = {"state": "alert", "deal": String(deal["id"]),
		"customer": String(deal["customer"]), "device": chosen.dev.name,
		"iface": chosen.name, "peer_device": host.name, "peer_iface": host_iface.name,
		"monitor_from": source, "target_ip": target_ip, "started_cycle": cycle,
		"evidence": [], "timeline": []}
	var arc: Dictionary = customer_arcs.get("kiskacsa", {})
	arc["beat"] = "complication"
	arc["outage_cycle"] = cycle
	customer_arcs["kiskacsa"] = arc
	chosen.admin_down = true  # the story is an administrative mistake, and show run says so
	chosen.enabled = false
	_guided_outage_note("cycle %d · service monitor raised an availability alert" % cycle)
	log_event(Loc.t("event.outage.raised", {"customer": "Kiskacsa"}))
	record_incident("guided-outage", "Kiskacsa lost service when an access port tripped")
	topology_changed.emit()
	guided_outage_changed.emit()

func acknowledge_guided_outage() -> String:
	if String(guided_outage.get("state", "")) != "alert":
		return "there is no unacknowledged tutorial alert"
	guided_outage["state"] = "acknowledged"
	guided_outage["acknowledged_cycle"] = cycle
	_guided_outage_note("cycle %d · alert acknowledged; investigation owner established" % cycle)
	log_event("INCIDENT ACKNOWLEDGED: Kiskacsa has an owner. Post a plain-language status update before touching the network.")
	guided_outage_changed.emit()
	return ""

func guided_outage_probe(layer: String) -> String:
	if not guided_outage_active():
		return "there is no guided outage to investigate"
	if String(guided_outage.get("state", "")) not in ["communicated", "investigating", "diagnosed"]:
		return "acknowledge the alert and update the customer first"
	var order := ["monitor", "physical", "l2"]
	if layer not in order:
		return "that evidence layer is not part of this incident"
	var evidence: Array = guided_outage.get("evidence", [])
	var idx := order.find(layer)
	if idx > evidence.size():
		return "follow the evidence in order"
	if layer in evidence:
		return ""
	var iface := guided_outage_iface()
	match layer:
		"monitor":
			_guided_outage_note("cycle %d · monitor confirms %s is unreachable from %s" % [cycle,
				guided_outage.get("target_ip", "the service"),
				guided_outage.get("monitor_from", "the network")])
		"physical":
			_guided_outage_note("cycle %d · physical cable is seated at both ends" % cycle)
		"l2":
			_guided_outage_note("cycle %d · L2 evidence: %s %s is administratively down" % [cycle,
				guided_outage.get("device", "device"), guided_outage.get("iface", "port")])
			guided_outage["state"] = "diagnosed"
			guided_outage["diagnosis"] = "access port administratively down"
			guided_outage["downstream_clear"] = iface != null and not iface.enabled
	evidence.append(layer)
	guided_outage["evidence"] = evidence
	if String(guided_outage.get("state", "")) != "diagnosed":
		guided_outage["state"] = "investigating"
	guided_outage_changed.emit()
	return ""

func _guided_outage_check_recovery() -> void:
	if not guided_outage_active() or String(guided_outage.get("state", "")) in ["recovered", "choice"]:
		return
	var deal := deal_by_id(String(guided_outage.get("deal", "")))
	if deal.is_empty() or not bool(deal.get("healthy", false)):
		return
	guided_outage["state"] = "recovered"
	guided_outage["recovered_cycle"] = cycle
	_guided_outage_note("cycle %d · monitor green; customer delivery and billing restored" % cycle)
	log_event("INCIDENT RECOVERED: Kiskacsa is reachable and billing has resumed. Review the short timeline, then harden one weak spot.")
	guided_outage_changed.emit()

func debrief_guided_outage() -> String:
	if String(guided_outage.get("state", "")) != "recovered":
		return "restore and verify the service first"
	guided_outage["state"] = "choice"
	guided_outage_changed.emit()
	return ""

func choose_guided_resilience(choice: String) -> String:
	if String(guided_outage.get("state", "")) != "choice":
		return "finish the incident debrief first"
	var iface := guided_outage_iface()
	if iface == null and choice != "monitor":
		return "the affected device is no longer installed"
	match choice:
		"spare":
			spares[iface.dev.model] = int(spares.get(iface.dev.model, 0)) + 1
			_guided_outage_note("resilience · one %s placed on the spare shelf" % MODELS[iface.dev.model]["label"])
		"monitor":
			var source := String(guided_outage.get("monitor_from", ""))
			if source == "":
				return "no independent monitoring source is available"
			var err := add_monitor("ping", source, String(guided_outage.get("target_ip", "")))
			if err != "" and err != "that check already exists":
				return err
			_guided_outage_note("resilience · permanent customer reachability monitor installed")
		"config":
			iface.dev.startup = device_config(iface.dev)
			_guided_outage_note("resilience · affected device configuration saved for recovery")
		_:
			return "choose a spare, monitor, or saved configuration"
	guided_outage["choice"] = choice
	guided_outage["state"] = "complete"
	stats["guided_outage_complete"] = 1
	var arc: Dictionary = customer_arcs.get("kiskacsa", {})
	arc["beat"] = "recovery"
	arc["communicated"] = guided_outage.has("status_cycle")
	arc["assisted"] = bool(guided_outage.get("assisted", false))
	arc["resilience"] = choice
	arc["recovered_cycle"] = int(guided_outage.get("recovered_cycle", cycle))
	arc["healthy_after_incident"] = 0
	customer_arcs["kiskacsa"] = arc
	log_event(Loc.t("event.outage.recovered", {"customer": "Kiskacsa"}))
	topology_changed.emit()
	guided_outage_changed.emit()
	return ""

func advance_kiskacsa_arc(deal: Dictionary) -> void:
	## Beat three is earned by the live service staying healthy. Dialogue alone
	## cannot manufacture trust, and a fresh outage resets the proof clock.
	var arc: Dictionary = customer_arcs.get("kiskacsa", {})
	if String(arc.get("beat", "")) != "recovery":
		return
	if not bool(deal.get("healthy", false)):
		arc["healthy_after_incident"] = 0
		customer_arcs["kiskacsa"] = arc
		return
	arc["healthy_after_incident"] = int(arc.get("healthy_after_incident", 0)) + 1
	if int(arc["healthy_after_incident"]) < 5:
		customer_arcs["kiskacsa"] = arc
		return
	arc["beat"] = "payoff"
	arc["payoff_cycle"] = cycle
	var trusted := bool(arc.get("communicated", false)) and not bool(arc.get("assisted", false))
	if trusted:
		arc["outcome"] = "trusted"
		if "Kiskacsa Kft" not in references:
			references.append("Kiskacsa Kft")
			reputation = mini(100, reputation + 4)
		var already_referred := false
		for lead: Dictionary in leads:
			if String(lead.get("id", "")) == "lead_story_madaras":
				already_referred = true
				break
		if not already_referred:
			leads.append(Market.kiskacsa_referral_lead())
		log_event("RELATIONSHIP: Kiskacsa remembers the honest outage response and five quiet cycles. They will be your reference, and sent Madaras Játék's firewalled hosting job.")
	else:
		arc["outcome"] = "cautious"
		deal["fee"] = maxi(1, int(round(float(int(deal["fee"])) * 0.9)))
		deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.75)) - 0.2)
		deal["term"] = mini(int(deal.get("term", 18)), 10)
		log_event("RELATIONSHIP: Kiskacsa stayed after five healthy cycles, but the assisted restore left them cautious: ten percent less fee and no referral.")
	customer_arcs["kiskacsa"] = arc
	topology_changed.emit()

func give_up_guided_outage() -> String:
	if not guided_outage_active():
		return "there is no guided outage to restore"
	var iface := guided_outage_iface()
	if iface == null:
		return "the guided restore point cannot find its port"
	iface.admin_down = false
	link_restore(iface)
	guided_outage["assisted"] = true
	guided_outage["state"] = "repairing"
	_guided_outage_note("cycle %d · assisted restore re-enabled the known-safe access port" % cycle)
	log_event("ASSISTED RESTORE: the access port is back up. Run one cycle to verify customer recovery; the campaign continues.")
	topology_changed.emit()
	guided_outage_changed.emit()
	return ""

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
	if int(latent_defects.get(dev.model, 0)) > 0:
		latent_defects[dev.model] = int(latent_defects[dev.model]) - 1
		firmware_bugs[dev.name] = {"since": cycle, "model": dev.model}
		log_event("SECOND-HAND: the shelf unit that went into %s has a fault the last owner never mentioned."
			% dev.name)
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

func record_incident(kind: String, summary: String, by := "") -> void:
	for inc in incidents:
		if inc["kind"] == kind and inc["summary"] == summary and not bool(inc.get("reviewed", false)):
			return  # one open review per ongoing problem
	incidents.push_front({"kind": kind, "summary": summary, "cycle": cycle, "reviewed": false,
		"by": by})
	if incidents.size() > 6:
		incidents.pop_back()

const REVIEW_CAUSES := [
	"a change nobody reviewed",
	"a single point of failure we knew about",
	"capacity we never planned for",
	"a monitor that did not exist",
	"a configuration that was never saved",
]

const REVIEW_FOLLOW_UP := {
	"a change nobody reviewed": "The answer is not more care, it is a change window: declare one, do the work inside it, and let the log say when it started.",
	"a single point of failure we knew about": "Pick the one you knew about and fix it, then book a failover test and take it away on purpose to find out whether you actually did.",
	"capacity we never planned for": "The capacity panel has the runway figures. The one that runs out first is the one to buy, and it is cheaper before it runs out.",
	"a monitor that did not exist": "Add the check that would have told you first. A monitor you add after an outage is the cheapest thing in this game.",
	"a configuration that was never saved": "Save what is running, and put somebody on the labelling and documentation duty so it stops being your job to remember.",
}

func cause_supported(cause: String) -> bool:
	## Does the floor bear the story out? Everything here is something the
	## simulation already knows, so a write-up cannot be a formality.
	match cause:
		"a change nobody reviewed":
			return not in_maintenance() or float(habits.get("windows", 0.5)) < 0.5
		"a single point of failure we knew about":
			var redundant := false
			for l in links:
				if lag_members(l).size() >= 2:
					redundant = true
			for d in all_devices():
				for i: Net.Iface in d.ifaces:
					if i.vrrp.get("vip", "") != "":
						redundant = true
			return not redundant
		"capacity we never planned for":
			var cap := capacity(current_site)
			return int(cap.get("slots_used", 0)) * 4 >= int(cap.get("slots", 1)) * 3 \
				or overheating()
		"a monitor that did not exist":
			return monitors.is_empty()
		"a configuration that was never saved":
			for d2 in all_devices():
				if config_dirty(d2):
					return true
			return false
	return false

func review_incident(inc: Dictionary, cause_idx: int) -> String:
	if bool(inc.get("reviewed", false)):
		return "that one is already written up"
	inc["reviewed"] = true
	observe_habit("documents", true)
	inc["cause"] = REVIEW_CAUSES[clampi(cause_idx, 0, REVIEW_CAUSES.size() - 1)]
	# a cause the floor bears out is worth more than one that was convenient
	var supported := cause_supported(String(inc["cause"]))
	inc["supported"] = supported
	reputation = mini(100, reputation + (3 if supported else 1))
	log_event("POST-MORTEM: %s. Contributing cause recorded as %s. %s"
		% [inc["summary"], inc["cause"], "Customers appreciate the candour."
			if supported else "Nothing on the floor says that is what happened, and it reads that way."])
	# the one moment the player is thinking about why: answer with the thing
	# that would actually catch it next time, and name a tool that exists
	var follow := String(REVIEW_FOLLOW_UP.get(String(inc["cause"]), ""))
	if follow != "":
		inc["follow_up"] = follow
		log_event("POST-MORTEM: %s" % follow)
	return ""

func report_incident(kind: String, summary: String, by: String, text: String, delay: int) -> void:
	## A fault is live the moment it happens; whether anyone says so is a
	## separate question, and the answer is set by how the last blame landed.
	if delay <= 0:
		record_incident(kind, summary, by)
		log_event(text)
		return
	pending_reports.append({"cycle": cycle + delay, "kind": kind, "summary": summary,
		"by": by, "text": text})

func report_tick() -> void:
	for pending: Dictionary in pending_reports.duplicate():
		if cycle < int(pending["cycle"]):
			continue
		pending_reports.erase(pending)
		record_incident(String(pending["kind"]), String(pending["summary"]), String(pending["by"]))
		log_event("%s (nobody mentioned it at the time)" % pending["text"])

func staff_named(name: String) -> Dictionary:
	for member: Dictionary in staff:
		if String(member.get("name", "")) == name:
			return member
	return {}

const BLAME_CHOICES := [
	["truth", "Tell them what actually happened"],
	["mine", "Take it yourself"],
	["name", "Name the person who did it"],
]

func blame_incident(inc: Dictionary, choice: String) -> String:
	## One line of dialogue, one real price. Nothing here is free.
	if String(inc.get("by", "")) == "":
		return "nobody caused that one; it was the hardware"
	if inc.has("blame"):
		return "you have already answered for that one"
	var who := staff_named(String(inc["by"]))
	var mine := String(inc["by"]) == "you"
	match choice:
		"truth":
			reputation = mini(100, reputation + 2)
			if not who.is_empty():
				who["morale"] = maxi(0, int(who.get("morale", 70)) - 4)
			log_event("BLAME: you told the customer what actually happened. Candour is cheaper than a story that unravels.")
		"mine":
			reputation = maxi(0, reputation - 4)
			blame_fear = maxi(0, blame_fear - 1)
			if not who.is_empty():
				who["morale"] = mini(100, int(who.get("morale", 70)) + 12)
				who["shielded"] = true
				who.erase("cautious")
				log_event("BLAME: you took it for %s. They will not forget that, and neither will the rest of the team."
					% who["name"])
				Staff.say(who, "defended")
			else:
				log_event("BLAME: you said it was yours, because it was. The team heard that too.")
		"name":
			if mine:
				blame_fear = mini(5, blame_fear + 2)
				reputation = mini(100, reputation + 1)
				log_event("BLAME: your mistake landed on the team. They noticed exactly what that means for theirs.")
			elif who.is_empty():
				return "they are not on the payroll any more"
			else:
				blame_fear = mini(5, blame_fear + 1)
				who["morale"] = maxi(0, int(who.get("morale", 70)) - 25)
				who["cautious"] = true
				who.erase("shielded")
				log_event("BLAME: you gave the customer %s's name. Your reputation is intact and %s will be very careful what they mention from now on."
					% [who["name"], who["name"]])
				Staff.say(who, "blamed")
		_:
			return "that is not one of the things you can say"
	inc["blame"] = choice
	return ""

func score_state() -> Dictionary:
	## What the room should be feeling, from things the simulation already
	## knows. The music never invents a mood the game is not in.
	var incident := customer_outage_active or guided_outage_active() or not hazards.is_empty()
	for deal in deals:
		if bool(deal.get("ever_healthy", false)) and not bool(deal.get("healthy", false)):
			incident = true
	var celebrating := false
	for deal2 in deals:
		if bool(deal2.get("ever_healthy", false)) and int(deal2.get("cycles", 99)) <= 1:
			celebrating = true
	return {"incident": incident, "upstream": upstream_active(),
		"heat": heat_wave() or overheating(),
		"night": day_slot() in [6, 7, 0, 1], "quiet": quiet_now(),
		"first_light": celebrating}

func audio_state() -> Dictionary:
	## What the room should sound like right now, derived from live state only.
	## Nothing here is decorative: every number and every cue is confirmable
	## with the visual tools.
	var cap := capacity(current_site)
	var watts := float(int(cap["watts"]))
	var cooling := maxf(1.0, float(cooling_capacity()))
	var load := clampf(watts / cooling, 0.0, 1.5) * day_factor()
	var hot := hottest_rack(current_site)
	var heat := 0.0
	if hot != null:
		heat = clampf(float(rack_heat(hot)) / maxf(1.0, float(rack_cooling(hot))) - 0.6, 0.0, 1.5)
	return {"load": clampf(load, 0.0, 1.5), "heat": heat, "cues": audio_alerts(),
		"where": hot}

func audio_alerts() -> Array:
	## Each cue names a condition the player can go and confirm.
	var cues: Array = []
	var feeds := site_feeds(current_site)
	if (not bool(feeds["A"]) or not bool(feeds["B"])) and int(ups.get(current_site, 0)) > 0:
		cues.append("ups")  # running on battery: the beep every operator knows
	if overheating() or (hottest_rack(current_site) != null and rack_hot(hottest_rack(current_site))):
		cues.append("thermal")
	if customer_outage_active:
		cues.append("alert")
	return cues

const DECOM_STEPS := ["wipe", "cabling", "reclaim"]

func decommission(dev: Net.NDevice, steps: Array) -> Dictionary:
	## Turning it off is the fast half. Each step here can be skipped, is
	## cheaper to skip, and has one specific consequence later.
	var price := int(MODELS[dev.model]["price"])
	var wiped := "wipe" in steps
	var tidy := "cabling" in steps
	var reclaimed := "reclaim" in steps
	# resale rewards gear that is wiped and complete, and punishes the rest
	var value := int(round(float(price) * (0.6 if wiped and tidy else (0.45 if wiped else 0.3))))
	var left_behind: Array = []
	if wiped:
		destruction_certs.append({"device": dev.name, "model": dev.model, "cycle": cycle})
	else:
		data_risks.append({"device": dev.name, "model": dev.model, "cycle": cycle})
		left_behind.append("no certificate of destruction")
		log_event("DECOM: %s left the building with its disks intact. There is no certificate for it."
			% dev.name)
	if reclaimed:
		var ips: Array = []
		for i: Net.Iface in dev.ifaces:
			for cidr in i.ips:
				ips.append(String(cidr).split("/")[0])
		for m in monitors.duplicate():
			if String(m.get("target", "")) in ips:
				monitors.erase(m)
		for other: Net.NDevice in all_devices():
			if other == dev:
				continue
			for route in other.static_routes.duplicate():
				if String(route.get("via", "")) in ips:
					other.static_routes.erase(route)
	else:
		left_behind.append("addresses, routes and checks still pointing at it")
		log_event("DECOM: %s is gone but its addresses, routes and checks are not. Somebody will find those later."
			% dev.name)
	if not tidy:
		left_behind.append("its patch leads still in the cabinet")
	uninstall_device(dev, false)
	_refund(value)
	log_event("DECOM: %s decommissioned for $%d.%s" % [dev.name, value,
		"" if left_behind.is_empty() else " Skipped: %s." % ", ".join(PackedStringArray(left_behind))])
	return {"value": value, "skipped": left_behind, "certified": wiped}

func decommission_by_tech(dev: Net.NDevice) -> Dictionary:
	## Delegated, which means done the way that person works: the boring steps
	## are exactly the ones a hurried technician drops.
	var who: Dictionary = Staff.best_of("tech")
	if who.is_empty():
		who = Staff.best_of("engineer")
	if who.is_empty():
		return decommission(dev, DECOM_STEPS)
	var habits := Staff.habits_of(who)
	var steps: Array = []
	if float(habits.get("documents", 0.5)) > 0.5:
		steps.append("wipe")
	if float(habits.get("tidy", 0.5)) > 0.5:
		steps.append("cabling")
	if float(habits.get("saves", 0.5)) > 0.5:
		steps.append("reclaim")
	log_event("DECOM: %s took the decommission of %s. They did it their way."
		% [who["name"], dev.name])
	return decommission(dev, steps)

func audit_findings() -> Array:
	var out: Array = []
	if not data_risks.is_empty():
		out.append("%d unit(s) left without a certificate of destruction" % data_risks.size())
	elif not destruction_certs.is_empty():
		out.append("%d certificate(s) of destruction on file, nothing left without one" % destruction_certs.size())
	if drift_factor() > 0.4:
		out.append("documentation that no longer describes the floor (%d fact(s) adrift)" % site_drift())
	if packaging > 2 or aisle_blocked():
		out.append("cardboard and crates in the aisle: a fire load and a trip hazard")
	var orphans := orphan_list().size()
	if orphans > 0:
		out.append("%d thing(s) on the floor that nobody claims" % orphans)
	var orphan := 0
	for m in monitors:
		if bool(m.get("failing", false)) and m.get("orphan", false):
			orphan += 1
	if orphan > 0:
		out.append("%d check(s) watching addresses nobody serves any more" % orphan)
	return out

func decom_tick() -> void:
	## A drive that left with its data on it does not stay gone forever.
	for risk in data_risks.duplicate():
		if cycle - int(risk["cycle"]) < 6 or randf() > 0.02:
			continue
		data_risks.erase(risk)
		reputation = maxi(0, reputation - 12)
		money -= 1500
		money_changed.emit()
		record_incident("data", "a disk from %s resurfaced with customer data on it" % risk["device"])
		log_event("DATA INCIDENT: a disk from the decommissioned %s turned up on a resale site with customer data still on it. $1500 and a great deal of trust."
			% risk["device"])
		return

func sentence(text: String) -> String:
	## First letter up, everything else left alone. capitalize() Title Cases a
	## whole sentence and splits identifiers like R1 into "R 1".
	return text.substr(0, 1).to_upper() + text.substr(1)

func housekeeping_mess() -> int:
	## How much the room shows the team's habits: coils nobody dressed, a
	## carton nobody broke down, a cup on the slab. A tidy team leaves none.
	## ponytail: one number drives the whole floor; per-item state would only
	## be worth it if the player could pick things up.
	var tidy: float = float(habits.get("tidy", 0.5))
	var cells := grid_size()
	var room := clampf(float(cells.x * cells.y) * 0.10, 2.0, 9.0)
	return int(round(clampf(1.0 - tidy, 0.0, 1.0) * room))

func rack_tidiness(r: Net.Rack) -> float:
	## How well kept one cabinet is, read off the real thing: blanked gaps,
	## labelled live ports, and configurations that are actually saved.
	var points := 0.0
	var total := 0.0
	for idx in Net.Rack.SLOTS:
		if r.slots[idx] == null:
			total += 1.0
			points += 1.0 if bool(r.blanked.get(idx, false)) else 0.0
	for d in r.slots:
		if d == null:
			continue
		total += 1.0
		points += 0.0 if config_dirty(d) else 1.0
		for i: Net.Iface in d.ifaces:
			if link_at(i) == null or i.name.begins_with("Management"):
				continue
			total += 1.0
			points += 1.0 if not i.note.is_empty() else 0.0
	# only this cabinet's own untidiness counts against this cabinet
	var local_debt := 0
	for item: Dictionary in cable_debt_items():
		var owner: Variant = item.get("iface")
		if owner is Net.Iface and rack_of((owner as Net.Iface).dev) == r:
			local_debt += 1
	# improvised leads are somewhere on this floor, so they count everywhere
	return 1.0 if total == 0.0 else clampf(points / total - 0.03 * float(local_debt)
		- 0.02 * float(cable_debt), 0.0, 1.0)

func floor_tidiness() -> float:
	var racks_here := racks_on(current_site)
	if racks_here.is_empty():
		return 1.0
	var sum := 0.0
	for r: Net.Rack in racks_here:
		sum += rack_tidiness(r)
	return sum / float(racks_here.size())

func quiet_now() -> bool:
	## No incident, nobody waiting, nothing upstream. The hours the job is
	## actually made of.
	if guided_outage_active() or upstream_active() or customer_outage_active:
		return false
	for deal in deals:
		if bool(deal.get("ever_healthy", false)) and not bool(deal.get("healthy", false)):
			return false
		if deal.has("dispute") or not peak_event(deal).is_empty():
			return false
	return true

func housekeeping_suggestion() -> String:
	## Offered once, quietly, and only when there is nothing on fire. Ignoring
	## it forever is a valid way to play.
	if not quiet_now():
		return ""
	for r: Net.Rack in racks_on(current_site):
		for idx in Net.Rack.SLOTS:
			if r.slots[idx] == null and not bool(r.blanked.get(idx, false)):
				return "%s has an open gap at U%d. A blanking panel would stop it breathing its own exhaust." \
					% [r.name, idx + 1]
		for d in r.slots:
			if d == null:
				continue
			if config_dirty(d):
				return "%s is running a configuration nobody has saved." % d.name
			for i: Net.Iface in d.ifaces:
				if link_at(i) != null and not i.name.begins_with("Management") and i.note.is_empty():
					return "%s %s is patched and unlabelled. Future you will not remember what it is." \
						% [d.name, i.name]
	return "The floor is in order. Walk it, watch the traffic move, and enjoy it."

func fault_chance() -> float:
	## A kept floor genuinely breaks less: cables are seated, gaps are blanked,
	## and the person who fixes it knows where everything is.
	var blocked := 1.35 if aisle_blocked() else 1.0  # you cannot work around a pallet
	return 0.25 * fault_scale() * (1.0 - 0.4 * floor_tidiness()) * blocked

func housekeeping_tick() -> void:
	if not quiet_now():
		return
	var tidy := floor_tidiness()
	if tidy < 0.75:
		return
	for member in staff:
		member["morale"] = mini(100, int(member.get("morale", 70)) + 1)
	if not bool(stats.get("tidy_noted", false)):
		stats["tidy_noted"] = true
		Sfx.play("good")
		log_event("QUIET: the floor is dressed, blanked and labelled. Faults are rarer here and repairs are quicker.")
	elif tidy < 0.95:
		stats["tidy_noted"] = false

func multihomed() -> bool:
	## two established upstream sessions is what survives one of them going away
	var sessions := 0
	for d: Net.NDevice in all_devices():
		for nb in d.bgp.get("neighbors", []):
			if Sim.bgp_established(d, nb):
				sessions += 1
	return sessions >= 2

func upstream_active() -> bool:
	return not upstream.is_empty()

func _maybe_upstream_event() -> void:
	## Occasionally the fault is entirely outside the player's reach. Never
	## during another crisis, and never twice in quick succession.
	if upstream_active() or cycle - last_upstream_cycle < UPSTREAM_GAP:
		return
	if customer_outage_active or guided_outage_active() or deals.is_empty() or cycle < 40:
		return
	if randf() > 0.015 * DIFFICULTIES[difficulty]["faults"]:
		return
	var carriers_in_use: Array = []
	for c in circuits:
		if String(c.get("carrier", "")) != "" and String(c["carrier"]) not in carriers_in_use:
			carriers_in_use.append(String(c["carrier"]))
	var kind := "carrier" if not carriers_in_use.is_empty() and randf() < 0.5 else "regional"
	var party: String = carriers_in_use[randi() % carriers_in_use.size()] if kind == "carrier" \
		else "your transit provider"
	upstream = {"kind": kind, "party": party, "started": cycle, "until": cycle + randi_range(2, 5),
		"opened": false, "case": "", "chased": 0, "posts": 0,
		"protected": multihomed() if kind == "regional" else carrier_diverse(0, 0)}
	if kind == "carrier":
		carrier_outage[party] = int(upstream["until"])
	var friends := Rivals.friendly()
	if not friends.is_empty():
		log_event("HEADS UP: %s rang first: their circuits went the same way ten minutes ago. %s"
			% [friends[0]["name"], Rivals.temper_of(friends[0])["favour"]])
	log_event("UPSTREAM: %s. This one is not yours to fix: open a case, chase it, and tell your customers before they ask."
		% ("%s has a regional failure" % party if kind == "regional"
			else "%s is down across the region" % party))
	topology_changed.emit()

func upstream_evidence() -> Array:
	## The small satisfaction available: your own tooling says it is not you.
	if not upstream_active():
		return []
	var lines: Array = ["your devices are up, your links are up, and nothing here changed"]
	if String(upstream["kind"]) == "carrier":
		lines.append("every circuit you buy from %s is down; circuits on other carriers are not"
			% upstream["party"])
	else:
		lines.append("traffic leaves your edge correctly and dies past the handoff at %s"
			% upstream["party"])
	lines.append("case with %s: %s" % [upstream["party"],
		upstream["case"] if bool(upstream.get("opened", false)) else "not opened yet"])
	if bool(upstream.get("protected", false)):
		lines.append("the second path you paid for is carrying the traffic")
	return lines

func open_upstream_case() -> String:
	if not upstream_active():
		return "there is nothing upstream to chase"
	if bool(upstream["opened"]):
		return "the case is already open"
	upstream["opened"] = true
	upstream["case"] = "%s-%d" % [String(upstream["party"]).substr(0, 3).to_upper(), cycle]
	log_event("UPSTREAM: case %s raised with %s. Now you wait, and chase." % [upstream["case"],
		upstream["party"]])
	return ""

func chase_upstream() -> String:
	if not upstream_active():
		return "there is nothing upstream to chase"
	if not bool(upstream["opened"]):
		return "open a case first; nobody chases a ticket that does not exist"
	if int(upstream.get("chased_cycle", -1)) == cycle:
		return "you have already chased them this cycle"
	upstream["chased_cycle"] = cycle
	upstream["chased"] = int(upstream["chased"]) + 1
	if int(upstream["until"]) > cycle + 1:
		upstream["until"] = int(upstream["until"]) - 1
		log_event("UPSTREAM: you pushed %s for an update. Their estimate moved in." % upstream["party"])
	else:
		log_event("UPSTREAM: %s says they are nearly there. They always say that." % upstream["party"])
	return ""

func upstream_tick() -> void:
	_maybe_upstream_event()
	if not upstream_active():
		return
	if status_posted_recently():
		upstream["posts"] = int(upstream["posts"]) + 1
	if cycle < int(upstream["until"]):
		return
	var kept_talking := int(upstream["posts"]) * 2 >= cycle - int(upstream["started"])
	var protected := bool(upstream.get("protected", false))
	if protected:
		reputation = mini(100, reputation + 2)
		log_event("UPSTREAM CLEARED: %s is back. Your second path carried the traffic through it, which is exactly what you bought it for."
			% upstream["party"])
	elif kept_talking:
		reputation = mini(100, reputation + 2)
		log_event("UPSTREAM CLEARED: %s is back. Your customers watched you handle somebody else's outage openly, and they will remember that."
			% upstream["party"])
	else:
		reputation = maxi(0, reputation - 8)
		Skills.fumble("incident_comms")
		log_event("UPSTREAM CLEARED: %s is back. You said nothing for %d cycles and your customers had to ask. That is the part they will remember."
			% [upstream["party"], cycle - int(upstream["started"])])
	record_incident("upstream", "%s failed upstream of you for %d cycles"
		% [upstream["party"], cycle - int(upstream["started"])])
	last_upstream_cycle = cycle
	upstream = {}
	topology_changed.emit()

func observe_habit(habit: String, good: bool, weight := 1.0) -> void:
	## Habits are read off what the player actually did, never off intent, and
	## they move slowly in both directions.
	if habit not in HABITS:
		return
	var a := clampf(HABIT_ALPHA * weight, 0.0, 1.0)
	habits[habit] = clampf(lerpf(float(habits.get(habit, 0.5)), 1.0 if good else 0.0, a), 0.0, 1.0)

func habit_tick() -> void:
	## Once a cycle, the standing state of the estate is itself a habit: what
	## is left unsaved, and what is left unexplained.
	var devs := all_devices()
	if not devs.is_empty():
		var dirty := 0
		for d: Net.NDevice in devs:
			if config_dirty(d):
				dirty += 1
		observe_habit("saves", dirty == 0)
	for inc: Dictionary in incidents:
		if not bool(inc.get("reviewed", false)) and cycle - int(inc.get("cycle", cycle)) >= 5:
			observe_habit("documents", false)
			break
	if in_maintenance():
		observe_habit("windows", true, 0.5)

func blame_said(inc: Dictionary) -> String:
	for say: Array in BLAME_CHOICES:
		if String(say[0]) == String(inc.get("blame", "")):
			return String(say[1])
	return "nothing"

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
			if support_lapsed():
				payout = payout / 2  # no maintenance agreement, no help with the bill
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

# ---------- the timeline, for working out what actually happened ----------

const TIMELINE_KEEP := 48
var timeline: Array = []  # one entry per cycle: state, plus what was logged
var _events_before := 0

func timeline_tick() -> void:
	## A snapshot per cycle of the things you would want to know afterwards,
	## plus whatever was logged during it. Reconstructing an outage from a
	## flat log is guesswork; reconstructing it from state over time is not.
	var down_devices: Array = []
	for d in all_devices():
		if d.status != "active":
			down_devices.append(d.name)
	var down_links := 0
	for l in links:
		if not l.a.enabled or not l.b.enabled:
			down_links += 1
	var unhealthy: Array = []
	for deal in deals:
		if not bool(deal.get("healthy", false)) and not deal.has("renewal"):
			unhealthy.append(String(deal["customer"]))
	var fresh: Array = []
	var added := events_logged - _events_before
	if added > 0:
		for i in mini(added, events.size()):
			fresh.append(String(events[i]))  # newest first, which is how they are stored
	_events_before = events_logged
	timeline.append({
		"cycle": cycle,
		"down_devices": down_devices,
		"down_links": down_links,
		"unhealthy": unhealthy,
		"events": fresh,
	})
	while timeline.size() > TIMELINE_KEEP:
		timeline.pop_front()

func replay_around(target_cycle: int, span := 4) -> Array:
	var out: Array = []
	for entry in timeline:
		var c := int(entry["cycle"])
		if c >= target_cycle - span and c <= target_cycle + span:
			out.append(entry)
	return out

func replay_line(entry: Dictionary) -> String:
	## one readable line per cycle of the replay
	var bits: Array = []
	if not entry["down_devices"].is_empty():
		bits.append("%d device(s) down: %s" % [entry["down_devices"].size(),
			", ".join(PackedStringArray(entry["down_devices"]))])
	if int(entry["down_links"]) > 0:
		bits.append("%d link(s) down" % int(entry["down_links"]))
	if not entry["unhealthy"].is_empty():
		bits.append("not delivering: %s" % ", ".join(PackedStringArray(entry["unhealthy"])))
	if bits.is_empty():
		bits.append("everything delivering")
	return "cycle %d  ·  %s" % [int(entry["cycle"]), "   ".join(PackedStringArray(bits))]

# ---------- the sales pipeline ----------

## Background commercial events (leads arriving, customers growing) run on
## their own random stream. They must not shift the sequence the network
## simulation draws from, or adding a business feature silently changes the
## outcome of an unrelated technical test.
var _biz_rng := RandomNumberGenerator.new()
var _fault_watch := -1  # the cycle a field fault landed
var _biz_ready := false

func biz_roll() -> float:
	if not _biz_ready:
		_biz_ready = true
		_biz_rng.seed = 5150218
	return _biz_rng.randf()

var leads: Array = []

func lead_tick() -> void:
	for l in leads.duplicate():
		l["ttl"] = int(l["ttl"]) - 1
		if int(l["ttl"]) <= 0:
			leads.erase(l)
			log_event("PIPELINE: %s went quiet. Somebody else got there first." % l["customer"])
	# The first pipeline lead is a named teaching story; once it has appeared,
	# the normal uncertain word-of-mouth market takes over permanently.
	if contracts_done.size() >= 3 and not bool(stats.get("guided_first_lead_seen", false)) \
			and leads.is_empty() and deals.is_empty():
		leads.append(Market.guided_first_lead())
		stats["guided_first_lead_seen"] = true
		log_event("PIPELINE: Kiskacsa Kft was referred by your first customers. Go and learn what they need.")
		return
	# bigger work arrives through people talking, not through a web form
	var cap := 2 + int(marketing / MARKETING_STEP) + references.size()
	if leads.size() < cap and contracts_done.size() >= 3 and biz_roll() < 0.35 * season_work():
		# one in four of them is somebody who will still be here in fifty
		# cycles, with a story of their own
		if identity_is("boutique") and biz_roll() < 0.5:
			leads.append(Market.gen_lead(["secure_host", "redundant_gw", "managed_switch"]))
			return
		var named := _unmet_story_customer()
		if named != "" and biz_roll() < 0.25:
			leads.append(Market.story_customer_lead(named))
		else:
			leads.append(Market.gen_lead())

func _unmet_story_customer() -> String:
	for key: String in STORY_CUSTOMERS:
		if key == "kiskacsa" or customer_arcs.has(key):
			continue
		var name := String(STORY_CUSTOMERS[key]["customer"])
		var busy := false
		for deal in deals:
			if String(deal.get("customer", "")) == name:
				busy = true
		for lead: Dictionary in leads:
			if String(lead.get("customer", "")) == name:
				busy = true
		if not busy:
			return name
	return ""

func qualify_lead(lead: Dictionary) -> String:
	## Go and find out what they actually want. Some of it turns out to be
	## nothing, which is what qualifying is for.
	if String(lead["stage"]) != "lead":
		return "you have already been out to see them"
	if not try_spend(Market.LEAD_QUALIFY_COST):
		return "a site visit costs $%d" % Market.LEAD_QUALIFY_COST
	if not bool(lead.get("guided", false)) and biz_roll() < 0.22:
		leads.erase(lead)
		log_event("PIPELINE: %s turned out to have no budget. That is the job."
			% lead["customer"])
		return "nothing there"
	lead["stage"] = "rfp"
	lead["ttl"] = 5
	log_event("PIPELINE: %s has put the work out to tender. %s"
		% [lead["customer"], Market.rfp_requirements(lead)])
	return ""

func submit_proposal(lead: Dictionary, price: int, committed_sla: int) -> String:
	if String(lead["stage"]) != "rfp":
		return "there is no tender to answer yet"
	var blocked := can_accept_offer(lead)
	if blocked != "":
		return blocked
	var result := Market.score_proposal(lead, price, committed_sla, reputation, references.size())
	if not bool(result["won"]):
		market_intel += 1
		if bool(lead.get("guided", false)):
			lead["attempts"] = int(lead.get("attempts", 0)) + 1
			lead["ttl"] = 5
			lead["coach"] = String(result["why"])
			log_event("PROPOSAL REVIEW: Kiskacsa did not sign yet: %s. Revise and resubmit."
				% sentence(String(result["why"])))
			return "retry:" + String(result["why"])
		leads.erase(lead)
		log_event("LOST TENDER: %s. %s." % [lead["customer"], sentence(String(result["why"]))])
		return "lost:" + String(result["why"])
	leads.erase(lead)
	var deal := {
		"id": "rfp_%d%s" % [cycle, String(lead["customer"]).substr(0, 3)],
		"customer": lead["customer"], "kind": lead["kind"], "params": lead["params"],
		"fee": price, "brief": Market.rfp_requirements(lead), "healthy": false,
		"payment_state": "waiting",
		"cycles": 0, "up_cycles": 0, "term": 18, "sla": committed_sla,
		"ctype": lead.get("ctype", "enterprise"), "loyalty": 0.75,
		"load": int(lead["load"]), "public": bool(lead.get("public", false)),
	}
	if bool(lead.get("guided", false)):
		deal["guided"] = true
		deal["delivery_credit"] = int(Market.cost_to_serve(lead)["setup"])
		customer_arcs["kiskacsa"] = {"beat": "arrival", "arrival_cycle": cycle,
			"proposal_attempts": int(lead.get("attempts", 0)), "promised_sla": committed_sla,
			"agreed_fee": price}
		log_event("DELIVERY RESERVE: Kiskacsa set aside $%d for the server. It cannot be spent on anything else."
			% int(deal["delivery_credit"]))
	deals.append(deal)
	stats["deals"] = int(stats.get("deals", 0)) + 1
	reputation = mini(100, reputation + 2)
	log_event("WON TENDER: %s at $%d/cycle on a %s commitment. Now deliver it."
		% [lead["customer"], price, Market.tier(committed_sla)["label"]])
	topology_changed.emit()
	return ""

# ---------- customers who grow, and what people say about you ----------

const UPSELL_AFTER := 8  # cycles of good service before they ask for more
var references: Array = []  # customer names who will vouch for you

func maybe_upsell() -> void:
	## A customer whose service has been solid for a while grows into it, and
	## growth means more traffic than you agreed to carry.
	for deal in deals:
		if deal.has("upsell") or deal.has("renewal"):
			continue
		if int(deal.get("cycles", 0)) < UPSELL_AFTER or not bool(deal.get("healthy", false)):
			continue
		if float(deal.get("up_cycles", 0)) / maxf(1.0, float(deal.get("cycles", 1))) < 0.9:
			continue
		if biz_roll() > 0.06:
			continue
		var extra_load := int(float(int(deal.get("load", 200))) * (0.4 + biz_roll() * 0.5))
		var extra_fee := int(float(int(deal["fee"])) * (0.25 + biz_roll() * 0.25))
		deal["upsell"] = {"load": extra_load, "fee": extra_fee}
		log_event("GROWTH: %s wants %d Mbps more for $%d/cycle more. Can you carry it?"
			% [deal["customer"], extra_load, extra_fee])
		return

const DISPUTE_KINDS := [
	{"id": "window",
		"demand": "refuses the maintenance window: they want the work done live, at their busiest hour",
		"stance": "no work happens outside an agreed window"},
	{"id": "redundancy",
		"demand": "has struck the second uplink off your quote: one path is good enough for them",
		"stance": "the service is not delivered on a single path"},
	{"id": "design",
		"demand": "insists on the flat design you already advised against, because their last provider did it that way",
		"stance": "the design you were told to build is the one you will not sign off"},
]

func dispute_kind(id: String) -> Dictionary:
	for k: Dictionary in DISPUTE_KINDS:
		if String(k["id"]) == id:
			return k
	return DISPUTE_KINDS[0]

func maybe_dispute() -> void:
	## The customer who argues. Being right does not prevent the outage: what
	## the player controls is who is holding the paperwork afterwards.
	for deal in deals:
		if deal.has("dispute") or deal.has("upsell") or deal.has("renewal"):
			continue
		if deal.has("predicted_failure") or int(deal.get("cycles", 0)) < 8:
			continue
		if not bool(deal.get("healthy", false)) or bool(deal.get("guided", false)):
			continue
		if biz_roll() > 0.04:
			continue
		var kind: Dictionary = DISPUTE_KINDS[int(biz_roll() * DISPUTE_KINDS.size()) % DISPUTE_KINDS.size()]
		# Sometimes they are simply right, so "always hold firm" cannot be
		# played on autopilot.
		deal["dispute"] = {"kind": String(kind["id"]), "warned": false, "raised": cycle,
			"customer_right": biz_roll() < 0.25}
		log_event("DISPUTE: %s %s. Put your advice in writing, concede, or hold firm."
			% [deal["customer"], kind["demand"]])
		return

func warn_customer(deal: Dictionary) -> String:
	if not deal.has("dispute"):
		return "they are not arguing with you"
	var dispute: Dictionary = deal["dispute"]
	if bool(dispute.get("warned", false)):
		return "your advice is already in writing"
	dispute["warned"] = true
	deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - 0.05)
	log_event("ON RECORD: you wrote to %s explaining the risk. Nobody enjoys receiving that email."
		% deal["customer"])
	return ""

func concede_dispute(deal: Dictionary) -> String:
	if not deal.has("dispute"):
		return "they are not arguing with you"
	var dispute: Dictionary = deal["dispute"]
	deal.erase("dispute")
	if bool(dispute.get("customer_right", false)):
		deal["loyalty"] = minf(1.0, float(deal.get("loyalty", 0.6)) + 0.1)
		log_event("CONCEDED: %s got their way, and they were right. Nothing breaks."
			% deal["customer"])
		return ""
	if bool(dispute.get("warned", false)):
		deal["on_record"] = true
	deal["predicted_failure"] = cycle + 3 + int(biz_roll() * 5.0)
	log_event("CONCEDED: %s gets what they asked for. It will fail the way you said it would."
		% deal["customer"])
	return ""

func hold_firm(deal: Dictionary) -> String:
	if not deal.has("dispute"):
		return "they are not arguing with you"
	var dispute: Dictionary = deal["dispute"]
	var kind := dispute_kind(String(dispute.get("kind", "")))
	deal.erase("dispute")
	var right := bool(dispute.get("customer_right", false))
	# whether they walk is judged on the relationship as it stood before the
	# argument, not on the dent the argument just made in it
	var leave_chance := 0.3 - float(deal.get("loyalty", 0.6)) * 0.3
	deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - (0.25 if right else 0.1))
	if right:
		reputation = maxi(0, reputation - 3)
		log_event("HELD FIRM: you told %s that %s. They were right and you were not: that costs you."
			% [deal["customer"], kind["stance"]])
	else:
		reputation = mini(100, reputation + (2 if bool(dispute.get("warned", false)) else 0))
		log_event("HELD FIRM: %s backed down. The outage you predicted never happens, which nobody thanks you for."
			% deal["customer"])
	if biz_roll() < leave_chance:
		deals.erase(deal)
		reputation = maxi(0, reputation - 2)
		log_event("LOST: %s took their business somewhere less argumentative." % deal["customer"])
	return ""

func dispute_tick() -> void:
	## The predicted failure arrives on its own schedule, and lands on whoever
	## the paperwork says it lands on.
	for deal in deals:
		if not deal.has("predicted_failure") or cycle < int(deal["predicted_failure"]):
			continue
		deal.erase("predicted_failure")
		if not _break_deal_path(deal):
			continue
		stats["faults"] = int(stats.get("faults", 0)) + 1
		if bool(deal.get("on_record", false)):
			log_event("PREDICTED FAILURE: %s is down exactly as you warned them in writing. This one is theirs."
				% deal["customer"])
		else:
			reputation = maxi(0, reputation - 4)
			Skills.fumble("change_control")
			log_event("PREDICTED FAILURE: %s is down the way you expected. You never wrote it down, so it is yours."
				% deal["customer"])
		record_incident("dispute", "%s went down after overruling your advice" % deal["customer"],
			"" if bool(deal.get("on_record", false)) else "you")
		topology_changed.emit()

func _break_deal_path(deal: Dictionary) -> bool:
	for l: Net.Link in _deal_path_links(deal):
		for i: Net.Iface in [l.a, l.b]:
			if i.enabled and not i.name.begins_with("Management"):
				link_fault(i, "link fault")
				device_log(i.dev, "%s changed state to down (link fault)" % i.name)
				return true
	return false

func accept_upsell(deal: Dictionary) -> String:
	if not deal.has("upsell"):
		return "they have not asked for anything"
	var up: Dictionary = deal["upsell"]
	deal["load"] = int(deal.get("load", 200)) + int(up["load"])
	deal["fee"] = int(deal["fee"]) + int(up["fee"])
	deal.erase("upsell")
	reputation = mini(100, reputation + 1)
	log_event("GROWTH: %s upgraded to $%d/cycle. Their traffic goes up tonight."
		% [deal["customer"], int(deal["fee"])])
	return ""

func decline_upsell(deal: Dictionary) -> String:
	if not deal.has("upsell"):
		return "they have not asked for anything"
	deal.erase("upsell")
	deal["loyalty"] = maxf(0.0, float(deal.get("loyalty", 0.6)) - 0.2)
	log_event("GROWTH: you turned %s down. They will remember that at renewal."
		% deal["customer"])
	return ""

func reference_tick() -> void:
	## A customer you have kept happy for a long time will say so out loud,
	## which is worth more than any amount of marketing.
	for deal in deals:
		if String(deal["customer"]) in references:
			continue
		if int(deal.get("cycles", 0)) < 20:
			continue
		if float(deal.get("up_cycles", 0)) / maxf(1.0, float(deal.get("cycles", 1))) < 0.97:
			continue
		references.append(String(deal["customer"]))
		reputation = mini(100, reputation + 6)
		log_event("REPUTATION: %s is willing to be a reference. That opens doors."
			% deal["customer"])
		return

func press_tick(rep: Dictionary) -> void:
	## the trade press notices a quarter, for better or worse
	if int(rep.get("deal_cycles", 0)) <= 0:
		return  # a quarter with no customers is not a story either way
	var uptime := int(rep.get("uptime", 100))
	var net := int(rep.get("net", 0))
	if uptime >= 98 and net > 0:
		reputation = mini(100, reputation + 4)
		log_event("PRESS: a trade piece names you as one to watch. %d%% delivered on the quarter."
			% uptime)
	elif uptime < 80:
		reputation = maxi(0, reputation - 3)
		log_event("PRESS: a piece about operators who overpromise. You are in it, at %d%% delivered."
			% uptime)

# ---------- tax, depreciation and the meter ----------

const TAX_RATE := 0.18
## Small-business relief: the first slice of quarterly profit is untaxed, so a
## company that is barely making rent is not taxed out of existence.
const TAX_FREE := 1500
const DEPRECIATION_LIFE := 60  # cycles over which a device writes itself off
const ACCOUNTANT_FEE := 55  # per cycle; they make the allowances stick
const ENERGY_BASE := 0.10  # dollars per watt per cycle at the flat rate
## What the meter charges by the hour. Electricity is dearest exactly when
## your customers are busiest, which is not a coincidence.
const ENERGY_CURVE := [0.55, 0.6, 1.15, 1.45, 1.5, 1.25, 0.95, 0.7]
const EFFICIENCY_STEP := 0.09  # draw removed per upgrade
const EFFICIENCY_PRICE := 2600

var buyout_offer := {}  # a rival's standing offer to buy you out
var sold_out := false  # you took it; the game is over and the score is final
var rank_seen := ""  # the last rank the player was told about
var pl_totals := {}  # what each system has cost or earned across the run
var finale := {}  # the frozen ending: how it ended, and the numbers it ended on
var accountant := false
var fixed_tariff := false  # a flat rate: dearer on average, immune to peaks
var efficiency := 0  # upgrades bought
var quarter_profit := 0
var quarter_depreciation := 0

func energy_multiplier() -> float:
	return 1.0 if fixed_tariff else ENERGY_CURVE[day_slot()]

func energy_rate() -> float:
	## the flat contract is priced above the average of the spot curve, which
	## is what you pay for not having to think about it
	var green := 0.75 if identity_is("green") else 1.0
	return ENERGY_BASE * (1.18 if fixed_tariff else energy_multiplier()) * green

func efficiency_factor() -> float:
	return maxf(0.55, 1.0 - EFFICIENCY_STEP * float(efficiency))

func effective_draw() -> int:
	return int(round(float(power_draw_all()) * efficiency_factor()))

func power_bill() -> int:
	return int(round(float(effective_draw()) * energy_rate()))

func buy_efficiency() -> String:
	if efficiency >= 5:
		return "there is nothing left worth retrofitting"
	var price := EFFICIENCY_PRICE + efficiency * 800
	if not try_spend(price):
		return "the retrofit costs $%d" % price
	efficiency += 1
	log_event("ENERGY: efficiency retrofit fitted. Draw is now %d%% of nameplate."
		% int(efficiency_factor() * 100.0))
	topology_changed.emit()
	return ""

func set_fixed_tariff(on: bool) -> void:
	fixed_tariff = on
	log_event("ENERGY: switched to a %s tariff." % ("fixed" if on else "spot"))

func depreciation_this_cycle() -> int:
	var total := 0
	for d in all_devices():
		if device_age(d) < DEPRECIATION_LIFE:
			total += int(MODELS[d.model]["price"]) / DEPRECIATION_LIFE
	return total

func hire_accountant(on: bool) -> void:
	accountant = on
	log_event("BOOKS: an accountant is %s." % ("on retainer" if on else "no longer retained"))

func tax_due() -> int:
	## profit for the quarter, less what the equipment wrote off. Without an
	## accountant only half the allowance is claimed, because nobody filed it.
	var allowance := quarter_depreciation if accountant else quarter_depreciation / 2
	var taxable := quarter_profit - allowance - TAX_FREE
	return maxi(0, int(round(float(taxable) * TAX_RATE)))

func settle_quarter() -> void:
	var tax := tax_due()
	if tax > 0:
		money -= tax
		last_pl["tax"] = -tax
		log_event("TAX: $%d on a quarter's profit of $%d (allowances $%d)."
			% [tax, quarter_profit, quarter_depreciation if accountant else quarter_depreciation / 2])
		money_changed.emit()
	quarter_profit = 0
	quarter_depreciation = 0

# ---------- IPv4 scarcity ----------

const IPV4_BLOCK := 8  # a /29: eight addresses, six of them usable in practice
const IPV4_BASE_PRICE := 900
var ipv4_blocks := 1  # what your first upstream gave you

func ipv4_total() -> int:
	return ipv4_blocks * IPV4_BLOCK

func ipv4_used() -> int:
	## every customer who insisted on an address of their own
	var used := 0
	for d in deals:
		if bool(d.get("public", false)):
			used += 1
	return used

func ipv4_free() -> int:
	return maxi(0, ipv4_total() - ipv4_used())

func ipv4_price() -> int:
	## the market for addresses only goes one way
	return int(round(float(IPV4_BASE_PRICE) * pow(1.6, float(ipv4_blocks - 1))))

func buy_ipv4_block() -> String:
	var price := ipv4_price()
	if not try_spend(price):
		return "a /29 now costs $%d and you do not have it" % price
	ipv4_blocks += 1
	log_event("ADDRESSES: bought a /29 for $%d. You now hold %d addresses."
		% [price, ipv4_total()])
	topology_changed.emit()
	return ""

func can_accept_offer(offer: Dictionary) -> String:
	## why you cannot take this one, or "" if you can
	if bool(offer.get("public", false)) and ipv4_free() <= 0:
		return "they need a public address of their own and you have none left"
	return ""

# ---------- playbooks: write it once, run it everywhere ----------

var playbooks: Array = []  # [{name, lines: [String]}]
var runbooks: Array = []  # bounded, reversible automation: what it may do, and to how much
var runbook_runs: Array = []  # every attempt, with before/after state for the rollback

func save_playbook(name: String, lines: Array) -> String:
	name = name.strip_edges()
	if name == "":
		return "a playbook needs a name"
	var clean: Array = []
	for l in lines:
		var line := String(l).strip_edges()
		if line != "" and not line.begins_with("#"):
			clean.append(line)
	if clean.is_empty():
		return "a playbook needs at least one command"
	for pb in playbooks:
		if String(pb["name"]) == name:
			pb["lines"] = clean
			log_event("PLAYBOOK: '%s' updated (%d commands)." % [name, clean.size()])
			return ""
	playbooks.append({"name": name, "lines": clean})
	log_event("PLAYBOOK: '%s' saved (%d commands)." % [name, clean.size()])
	return ""

func delete_playbook(name: String) -> void:
	for pb in playbooks.duplicate():
		if String(pb["name"]) == name:
			playbooks.erase(pb)

func playbook_targets(filter: String) -> Array:
	## "switch", "router", "server", "all", or a substring of the device name
	var out: Array = []
	for d in all_devices():
		if filter == "all" or d.type == filter or (filter != "" and filter in d.name):
			out.append(d)
	return out

const RUNBOOK_ACTIONS := {
	"bounce": {"label": "bounce the interface", "reversible": true,
		"blurb": "Shut and unshut a port. Reversible, and useless against most real faults."},
	"reload_config": {"label": "reload the saved configuration", "reversible": true,
		"blurb": "Put the device back on its startup config."},
	"save_config": {"label": "save the running configuration", "reversible": false,
		"blurb": "Write memory. Safe, and not undoable."},
	"dispatch": {"label": "send somebody to look at it", "reversible": false,
		"blurb": "Hands on the device, which costs time and sometimes money."},
}
const RUNBOOK_MAX_DEVICES := 3  # a blast radius somebody has to raise on purpose

func make_runbook(name: String, action: String, match_name := "", max_devices := RUNBOOK_MAX_DEVICES,
		confirm := true) -> Dictionary:
	if not RUNBOOK_ACTIONS.has(action):
		return {}
	var rb := {"name": name, "action": action, "match": match_name,
		"max_devices": maxi(1, max_devices), "confirm": confirm, "runs": 0}
	runbooks.append(rb)
	return rb

func runbook_targets(rb: Dictionary) -> Array:
	## Selectors pick devices by name fragment, and nothing else: an automation
	## that can address the whole estate by accident is not a safe one.
	var out: Array = []
	for d: Net.NDevice in all_devices():
		if String(rb.get("match", "")) == "" or String(rb["match"]) in d.name:
			out.append(d)
	return out

func run_runbook(rb: Dictionary, dry_run := true, confirmed := false) -> Dictionary:
	## Every run is planned first, refused if it is too broad, and logged in
	## full whether it changed anything or not.
	var result := {"planned": [], "applied": [], "skipped": [], "refused": "", "log": [],
		"dry_run": dry_run, "id": runbook_runs.size(), "cycle": cycle, "runbook": String(rb["name"])}
	var targets := runbook_targets(rb)
	for d: Net.NDevice in targets:
		result["planned"].append(d.name)
	if targets.size() > int(rb["max_devices"]):
		result["refused"] = "%d device(s) match and this runbook may touch %d" \
			% [targets.size(), int(rb["max_devices"])]
		result["log"].append("REFUSED: " + String(result["refused"]))
		log_event("RUNBOOK '%s' refused: %s" % [rb["name"], result["refused"]])
		runbook_runs.append(result)
		return result
	if targets.is_empty():
		result["refused"] = "nothing matches that selector"
		runbook_runs.append(result)
		return result
	if not dry_run and bool(rb.get("confirm", true)) and not confirmed and int(rb.get("runs", 0)) == 0:
		result["refused"] = "first run of a runbook needs confirming"
		result["log"].append("REFUSED: " + String(result["refused"]))
		runbook_runs.append(result)
		return result
	var before := {}
	for d: Net.NDevice in targets:
		# automation that cuts the path it is working over is the classic own goal
		if String(rb["action"]) in ["bounce", "reload_config"] and not console_reachable(d) \
				and not management_ips(d).is_empty() and not confirmed:
			result["skipped"].append(d.name)
			result["log"].append("%s: skipped, this would ride the path it manages" % d.name)
			continue
		before[d.name] = device_config(d)
		if dry_run:
			result["log"].append("%s: would %s" % [d.name, RUNBOOK_ACTIONS[rb["action"]]["label"]])
			continue
		match String(rb["action"]):
			"bounce":
				# shut and unshut: the port that is down is the one worth bouncing
				var pick: Net.Iface = null
				for i: Net.Iface in d.ifaces:
					if link_at(i) == null or i.name.begins_with("Management"):
						continue
					if not i.enabled:
						pick = i
						break
					if pick == null:
						pick = i
				if pick != null:
					pick.err_disabled = false  # shut / no shut clears an err-disable
					pick.enabled = pick.fault == "" and not pick.admin_down
					result["log"].append("%s: bounced %s" % [d.name, pick.name])
			"reload_config":
				apply_device_config(d, d.startup)
				result["log"].append("%s: reloaded the saved configuration" % d.name)
			"save_config":
				d.startup = device_config(d)
				save_config_version(d)
				result["log"].append("%s: running configuration saved" % d.name)
			"dispatch":
				walk_to_device(d)
				result["log"].append("%s: somebody is standing at it" % d.name)
		result["applied"].append(d.name)
	if not dry_run:
		rb["runs"] = int(rb.get("runs", 0)) + 1
		result["before"] = before
		var after := {}
		for name: String in before:
			for d2: Net.NDevice in all_devices():
				if d2.name == name:
					after[name] = device_config(d2)
		result["after"] = after
		log_event("RUNBOOK '%s': %d applied, %d skipped." % [rb["name"],
			result["applied"].size(), result["skipped"].size()])
	runbook_runs.append(result)
	if runbook_runs.size() > 20:
		runbook_runs.pop_front()
	return result

func rollback_runbook(run: Dictionary) -> String:
	## Only where the underlying action can actually be taken back.
	if bool(run.get("dry_run", true)) or not run.has("before"):
		return "there is nothing to roll back"
	if run.get("applied", []).is_empty():
		return "that run changed nothing"
	for name: String in run["before"]:
		for d: Net.NDevice in all_devices():
			if d.name == name:
				apply_device_config(d, run["before"][name])
	log_event("RUNBOOK ROLLBACK: %d device(s) put back the way they were."
		% run["before"].size())
	topology_changed.emit()
	return ""

func run_playbook(pb: Dictionary, targets: Array) -> Dictionary:
	## Runs every line on every target through a real CLI session, so a
	## playbook can do exactly what a person at a console can do and no more.
	## -> {ran, failed, log: [String]}
	var ran := 0
	var failed := 0
	var trail: Array = []
	for d: Net.NDevice in targets:
		var session := CLI.new_session(d)
		var bad := 0
		for line: String in pb["lines"]:
			var out := String(session.exec(line))
			# a real console answers an unusable command with a % or an error
			if out.begins_with("%") or out.begins_with("usage:") or "nvalid" in out \
					or out.contains("not known") or out.begins_with("ssh:"):
				bad += 1
				trail.append("%s: %s -> %s" % [d.name, line, out.strip_edges()])
		ran += 1
		if bad > 0:
			failed += 1
	log_event("PLAYBOOK: ran '%s' on %d device(s), %d with errors." % [pb["name"], ran, failed])
	topology_changed.emit()
	return {"ran": ran, "failed": failed, "log": trail}

# ---------- certificates ----------

const CERT_LIFE := 24  # cycles a freshly issued certificate is good for
const CERT_WARN := 4  # how far ahead the warnings start
const CERT_AUTO_FEE := 8  # per cycle, per automatically renewed certificate

func certs_on(d: Net.NDevice) -> Dictionary:
	return d.services.get("tls", {})

func issue_cert(d: Net.NDevice, name: String, life := CERT_LIFE) -> String:
	if name.strip_edges() == "":
		return "a certificate needs a name"
	if not d.services.has("tls"):
		d.services["tls"] = {}
	d.services["tls"][name] = {"expires": cycle + life,
		"auto": bool(d.services["tls"].get(name, {}).get("auto", false))}
	topology_changed.emit()
	return ""

func cert_expired(d: Net.NDevice) -> bool:
	for name in certs_on(d):
		if cycle >= int(certs_on(d)[name]["expires"]):
			return true
	return false

func expiring_certs() -> Array:
	## everything due to expire soon or already dead, worst first
	var out: Array = []
	for d in all_devices():
		for name in certs_on(d):
			var left: int = int(certs_on(d)[name]["expires"]) - cycle
			if left <= CERT_WARN:
				out.append({"dev": d, "name": String(name), "left": left,
					"auto": bool(certs_on(d)[name].get("auto", false))})
	out.sort_custom(func(x, y): return int(x["left"]) < int(y["left"]))
	return out

func cert_tick() -> void:
	var auto_cost := 0
	for d in all_devices():
		for name in certs_on(d):
			var rec: Dictionary = certs_on(d)[name]
			var left: int = int(rec["expires"]) - cycle
			if bool(rec.get("auto", false)):
				auto_cost += CERT_AUTO_FEE
				if left <= 2:
					rec["expires"] = cycle + CERT_LIFE  # renewed without anyone noticing
				continue
			if left == CERT_WARN:
				log_event("CERTIFICATE: %s on %s expires in %d cycles."
					% [name, d.name, CERT_WARN])
			elif left == 0:
				log_event("CERTIFICATE: %s on %s has EXPIRED. The service is up and every client refuses to talk to it."
					% [name, d.name])
	if auto_cost > 0:
		last_pl["certificates"] = int(last_pl.get("certificates", 0)) - auto_cost
		money -= auto_cost

# ---------- route hijacks and RPKI ----------

var hijacks: Array = []  # [{prefix, plen, by, cycles_left}]

func announced_prefixes() -> Array:
	var out: Array = []
	for d in all_devices():
		for net in d.bgp.get("networks", []):
			if String(net) != "0.0.0.0/0":
				out.append({"cidr": String(net), "dev": d})
	return out

func roa_registered(dev: Net.NDevice, cidr: String) -> bool:
	return cidr in dev.bgp.get("roa", [])

func upstream_validates(dev: Net.NDevice) -> bool:
	## at least one session where we asked the upstream to check origins
	for nb in dev.bgp.get("neighbors", []):
		if bool(nb.get("rpki", false)):
			return true
	return false

func hijack_protected(entry: Dictionary) -> bool:
	## a signed prefix is only protected when somebody upstream is checking
	var d: Net.NDevice = entry["dev"]
	return roa_registered(d, String(entry["cidr"])) and upstream_validates(d)

func hijack_on(ip: String) -> Dictionary:
	for h in hijacks:
		if Net.same_net(ip, String(h["prefix"]), int(h["plen"])):
			return h
	return {}

func hijack_tick() -> void:
	for h in hijacks.duplicate():
		h["cycles_left"] = int(h["cycles_left"]) - 1
		if int(h["cycles_left"]) <= 0:
			hijacks.erase(h)
			log_event("SECURITY: the bogus announcement of %s/%d has been withdrawn."
				% [h["prefix"], int(h["plen"])])
	var mine := announced_prefixes()
	if mine.is_empty() or not hijacks.is_empty() or randf() > 0.05:
		return
	var entry: Dictionary = mine[randi() % mine.size()]
	var parts := String(entry["cidr"]).split("/")
	var culprit := "AS%d" % (64600 + randi() % 300)
	if hijack_protected(entry):
		log_event("SECURITY: %s announced %s and was rejected: your ROA says it is not theirs."
			% [culprit, entry["cidr"]])
		return
	hijacks.append({"prefix": parts[0], "plen": int(parts[1]), "by": culprit,
		"cycles_left": 2 + randi() % 4})
	log_event("SECURITY: %s is announcing %s. Traffic for it is going to them, not you. Sign the prefix with a ROA and ask an upstream to validate."
		% [culprit, entry["cidr"]])

# ---------- transit and peering ----------

var transit_samples: Array = []  # Mbps across upstream links, most recent last
var ixp := {}  # {"joined": bool, "peers": int}

func transit_mbps_now() -> int:
	## everything riding a link that touches an upstream handoff
	var total := 0
	for l in last_link_load:
		if l.a.dev.type == "uplink" or l.b.dev.type == "uplink":
			total += int(last_link_load[l])
	return total

func peering_share() -> float:
	## each peering session at the exchange takes some traffic off transit;
	## in reality this is where most of it goes, and it is why exchanges exist
	if not bool(ixp.get("joined", false)):
		return 0.0
	return minf(0.75, IXP_PEER_SHARE * float(int(ixp.get("peers", 0))))

func percentile_95(samples: Array) -> int:
	## drop the top five percent and bill the highest of what is left
	if samples.is_empty():
		return 0
	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	var idx := int(floor(float(sorted_samples.size()) * 0.95)) - 1
	return int(sorted_samples[clampi(idx, 0, sorted_samples.size() - 1)])

func transit_billed_mbps() -> int:
	return percentile_95(transit_samples)

func transit_cost() -> int:
	return int(round(float(transit_billed_mbps()) * TRANSIT_PER_MBPS))

func sample_transit() -> void:
	var billable := int(round(float(transit_mbps_now()) * (1.0 - peering_share())))
	transit_samples.append(billable)
	while transit_samples.size() > TRANSIT_WINDOW:
		transit_samples.pop_front()

func join_ixp() -> String:
	if bool(ixp.get("joined", false)):
		return "you already have a port at the exchange"
	if not try_spend(IXP_SETUP):
		return "you cannot afford the $%d cross-connect and port" % IXP_SETUP
	ixp = {"joined": true, "peers": 0}
	log_event("PEERING: you have a port at the exchange ($%d/cycle). Now find networks to peer with."
		% IXP_PORT_FEE)
	topology_changed.emit()
	return ""

func add_peering() -> String:
	if not bool(ixp.get("joined", false)):
		return "you need a port at the exchange first"
	if int(ixp.get("peers", 0)) >= 6:
		return "you are peering with everyone worth peering with here"
	ixp["peers"] = int(ixp.get("peers", 0)) + 1
	log_event("PEERING: another network agreed to peer. %d%% of your traffic now bypasses transit."
		% int(peering_share() * 100.0))
	topology_changed.emit()
	return ""

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
	if nemesis != "" and randf() < 0.6:
		var personal := Rivals.by_name(nemesis)
		if not personal.is_empty() and Rivals.alive(personal):
			rival = personal  # they are not bidding on the market, they are bidding at you
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
			Sfx.play("reboot")
			stats["faults"] += 1
			log_event("FIELD: %s rebooted after a power blip: %s" % [rebooted.name,
				"startup-config restored it." if had_startup
				else "it had NO saved config and came back blank. Use 'write memory'!"])
			if not had_startup:
				Skills.fumble("saved_configs")
			return
	var victim: Net.Iface = candidates[randi() % candidates.size()]
	link_fault(victim, "link fault")
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

func autosave_due() -> void:
	## a quiet safety net every few cycles, so a crash costs minutes not hours
	if drill_active or cycle == 0 or cycle % 5 != 0:
		return
	save_game(SLOTS)

func sla_tick() -> void:
	## Completed contracts pay recurring service fees: but only while
	## their requirements still hold. Break the network, lose the revenue.
	autosave_due()
	if not sandbox and not drill_active:
		power_tick()
		carrier_tick()
		hijack_tick()
	if drill_active:
		return  # the economy pauses while you run a drill
	if sandbox:
		cycle += 1  # time passes, but nothing is billed and nothing breaks
		return
	cycle += 1
	var customer_outage_now := false
	var earned := 0
	last_pl = {}
	last_business = {"revenue": 0, "invoiced": 0, "collected": 0,
		"power": 0, "transit": 0}
	cert_tick()  # after the reset, so its line shows up in this cycle's P&L
	Sim.dhcp_tick()
	_maybe_start_guided_outage()
	dispute_tick()
	report_tick()
	habit_tick()
	facility_tick()
	renewal_tick()
	tac_tick()
	remote_hands_tick()
	lockout_tick()
	ticket_tick()
	call_tick()
	oncall_tick()
	dr_tick()
	dr_request_tick()
	handover_tick()
	night_call_tick()
	rank_tick()
	season_tick()
	remediation_tick()
	_maybe_grey_fault()
	receiving_tick()
	stockout_tick()
	rma_tick()
	parts_tick()
	duties_tick()
	change_tick()
	maybe_window_job()
	window_job_tick()
	maybe_schedule_tour()
	tour_tick()
	audit_tick()
	maybe_offer_decision()
	consequence_tick()
	story_tick()
	maybe_end_run()
	hazard_tick()
	access_incident_tick()
	visitor_tick()
	decom_tick()
	housekeeping_tick()
	Skills.recognition_tick()
	upstream_tick()
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
		var bill := power_bill()
		last_pl["power"] = -bill
		last_business["power"] = bill
		earned -= bill
	if accountant:
		last_pl["accountant"] = -ACCOUNTANT_FEE
		earned -= ACCOUNTANT_FEE
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
		if not ok:
			customer_outage_now = true
		if ok:
			# earned this cycle, owed on the customer's terms: a campaign
			# customer is still a customer, and the cash arrives when it arrives
			var fee: int = int(c["reward"]) / 10
			raise_invoice({"customer": String(c["customer"]), "id": "contract:%s" % c["id"],
				"ctype": "startup" if String(c["customer"]) == "Internal ops" else "enterprise"}, fee)
	for d in all_devices():  # transit invoices
		for nb in d.bgp.get("neighbors", []):
			if Sim.bgp_established(d, nb):
				Skills.observe("bgp_peering")
				last_pl["transit ports"] = int(last_pl.get("transit ports", 0)) - TRANSIT_FEE
				last_business["transit"] = int(last_business.get("transit", 0)) + TRANSIT_FEE
				earned -= TRANSIT_FEE
	if overheating():
		# heat kills, and it kills where the heat is: the hottest cabinet loses
		# a device first, which is what makes CRAC placement a decision
		var hot := hottest_rack(0)
		var tripped := false
		if hot != null:
			for d in hot.slots:
				if d != null and d.status == "active" and d.type != "cooling":
					d.status = "offline"
					log_event("HEAT: %s in %s tripped. That cabinet is running at %dW against %dW of cooling."
						% [d.name, hot.name, rack_heat(hot), rack_cooling(hot)])
					topology_changed.emit()
					tripped = true
					break
		if not tripped:
			for d in all_devices():
				if d.status == "active" and d.type != "cooling":
					d.status = "offline"
					topology_changed.emit()
					break
	Rivals.tick()
	if not buyout_offer.is_empty():
		buyout_offer["ttl"] = int(buyout_offer["ttl"]) - 1
		if int(buyout_offer["ttl"]) <= 0:
			log_event("APPROACH: %s has withdrawn their offer." % buyout_offer["rival"])
			buyout_offer = {}
	Rivals.maybe_offer_for_player()
	Rivals.maybe_favour()
	Rivals.check_nemesis_beaten()
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
		Staff.shadow_tick()
		# how hard a cycle it was for them: broken links, dead kit, breaches
		var trouble := 0
		for l in links:
			if not l.a.enabled or not l.b.enabled:
				trouble += 1
		for d in all_devices():
			if d.status != "active":
				trouble += 1
		for cid in sla_status:
			if not sla_status[cid]:
				trouble += 1
		Staff.morale_tick(trouble)
	if cycle % 4 == 0:
		refresh_candidates(true)  # the job market moves
	if stage >= 2 and randf() < fault_chance():
		_field_fault()
		_fault_watch = cycle
	var link_load := {}
	var deal_links := {}
	var delivered_this_cycle := false
	for deal in deals:
		var was_healthy := bool(deal.get("healthy", false))
		deal["healthy"] = Market.check(deal["kind"], deal["params"])
		var deal_host := Contracts._owner(String(deal["params"].get("ip", "")))
		if deal["healthy"] and deal_host != null and cert_expired(deal_host):
			# nothing is broken and nothing will connect, which is the point
			deal["healthy"] = false
			deal["cert_expired"] = true
		else:
			deal["cert_expired"] = false
		if deal["healthy"] and upstream_active() and String(upstream["kind"]) == "regional" \
				and not bool(upstream.get("protected", false)):
			# nothing here is broken; the road out of the building is
			deal["healthy"] = false
			deal["upstream_down"] = true
		else:
			deal["upstream_down"] = false
		if deal["healthy"] and not hijack_on(String(deal["params"].get("ip", ""))).is_empty():
			# the service is fine; the internet is simply sending its traffic
			# somewhere else, which the customer experiences as an outage
			deal["healthy"] = false
			deal["hijacked"] = true
		else:
			deal["hijacked"] = false
		if deal["healthy"]:
			var first_delivery := not bool(deal.get("ever_healthy", false))
			deal["ever_healthy"] = true
			deal["payment_state"] = "billing"
			if not was_healthy:
				if first_delivery:
					Skills.observe("service_delivery")
					_first_light(deal)
				var state := "delivered" if first_delivery else "restored"
				customer_service_changed.emit(String(deal["customer"]), state, int(deal["fee"]))
				deal.erase("on_record")
				log_event("SERVICE %s: %s is reachable. Billing %s at $%d/cycle."
					% [state.to_upper(), deal["customer"], "started" if first_delivery else "resumed",
						int(deal["fee"])])
		elif bool(deal.get("ever_healthy", false)) and not deal.has("renewal"):
			customer_outage_now = true
			deal["payment_state"] = "suspended"
			if was_healthy:
				customer_service_changed.emit(String(deal["customer"]), "suspended", int(deal["fee"]))
				log_event("PAYMENT SUSPENDED: %s is down. No invoice will be raised until service returns."
					% deal["customer"])
		else:
			deal["payment_state"] = "waiting"
		if deal["healthy"]:
			var used := _deal_path_links(deal)
			deal_links[deal["id"]] = used
			# traffic follows the working day: quiet at night, heaviest at noon
			var load := int(round(float(int(deal.get("load", 200))) * day_factor()
				* peak_multiplier(deal)))
			var atk := attack_on(deal["params"].get("ip", ""))
			if not atk.is_empty() and not scrubbing and not attack_blackholed(atk):
				load += int(atk["mbps"])  # the flood rides the same path
			for l in used:
				link_load[l] = link_load.get(l, 0) + load
	if _fault_watch == cycle and not deals.is_empty():
		# a link died this cycle: if every customer is still up, the redundancy
		# the player built is what did that
		var all_up := true
		for deal_check in deals:
			if bool(deal_check.get("ever_healthy", false)) and not bool(deal_check.get("healthy", false)):
				all_up = false
		if all_up:
			Skills.observe("resilient_design")
	_guided_outage_check_recovery()
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
			var rep_hit := 2 if status_posted_recently() else 4
			if identity_is("reliability"):
				rep_hit *= 2  # you sold them strictness, and this is what that costs
			if bool(deal.get("on_record", false)):
				rep_hit = maxi(1, rep_hit / 2)  # you warned them, in writing
			reputation = maxi(0, reputation - rep_hit)
			deal["degraded"] = false
			if bool(deal.get("upstream_down", false)):
				# somebody else's outage: they do not walk over it, and they
				# certainly do not walk over one you kept them informed about
				deal["missed"] = mini(int(deal.get("missed", 0)), 3)
				continue
			deal["missed"] = int(deal.get("missed", 0)) + 1
			var missed: int = deal["missed"]
			if bool(deal.get("guided", false)) and not bool(deal.get("ever_healthy", false)):
				if missed == 3:
					log_event("DELIVERY COACH: Kiskacsa is still waiting. Their protected server reserve and contract remain open while you finish the service.")
				deal["missed"] = mini(missed, 3)
			elif missed == 3:
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
				# a full pipe shows on the port as output drops, not as errors
				var over := 1 + int((link_load[l] - link_capacity(l)) / 50.0)
				l.a.out_drops += over
				l.b.out_drops += over
		if congested and not deal.get("degraded", false):
			log_event("CONGESTION: %s's traffic exceeds a link's capacity: they pay half until you add bandwidth."
				% deal["customer"])
		deal["degraded"] = congested
		if deal.has("renewal"):
			continue  # nothing is billed while the customer is deciding
		var paid: int = int(deal["fee"]) / (2 if congested else 1)
		# the work is done and the money is owed, which is not the same as
		# having it: it goes out as an invoice on the customer's terms
		raise_invoice(deal, paid)
		delivered_this_cycle = true
		if bool(deal.get("guided", false)):
			advance_kiskacsa_arc(deal)
	if delivered_this_cycle and not customer_outage_now:
		# a company that delivered to everybody today is thought a little better
		# of, once: six happy customers do not outrun one who is down
		reputation = mini(100, reputation + 1)
	for deal_peak in deals:
		peak_tick(deal_peak)  # the night they warned you about, judged on live delivery
	for pl_key: String in last_pl:
		pl_totals[pl_key] = int(pl_totals.get(pl_key, 0)) + int(last_pl[pl_key])
	_update_reliability_streak(customer_outage_now)
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
	# transit is billed on the 95th percentile of what you burst to, so the
	# sample has to be taken after this cycle's link loads are known
	sample_transit()
	var transit_bill := transit_cost()
	if transit_bill > 0:
		last_pl["transit (95th)"] = int(last_pl.get("transit (95th)", 0)) - transit_bill
		last_business["transit"] = int(last_business.get("transit", 0)) + transit_bill
		earned -= transit_bill
	if bool(ixp.get("joined", false)):
		last_pl["exchange port"] = int(last_pl.get("exchange port", 0)) - IXP_PORT_FEE
		last_business["transit"] = int(last_business.get("transit", 0)) + IXP_PORT_FEE
		earned -= IXP_PORT_FEE
	earned += collect_invoices()
	last_cycle_delta = earned
	if earned > 0:
		stats["earned"] += earned
	if earned != 0:
		money += earned
		money_changed.emit()
	var up_deals := 0
	var billed_deals := 0
	for deal in deals:
		if deal.has("renewal"):
			continue  # nothing is being delivered or billed while they decide
		billed_deals += 1
		if deal["healthy"]:
			up_deals += 1
	var cap_now := capacity(0)
	history.append({"cycle": cycle, "money": money, "net": last_cycle_delta,
		"reputation": reputation, "deals": billed_deals, "up": up_deals,
		"devices": all_devices().size(),
		# the slow measures, so the room can be shown getting quieter or worse
		"tidy": floor_tidiness(), "drift": drift_factor(),
		"slots_used": int(cap_now["slots_used"]), "watts": int(cap_now["watts"])})
	if history.size() > 120:
		history.pop_front()
	quarter_profit += last_cycle_delta
	quarter_depreciation += depreciation_this_cycle()
	maybe_upsell()
	maybe_dispute()
	maybe_announce_peak()
	reference_tick()
	lead_tick()
	timeline_tick()
	if cycle % 12 == 0 and cycle > 0:
		var rep_now := make_report()
		press_tick(rep_now)
		settle_quarter()
		if board_targets and not sandbox and not drill_active:
			settle_quarter_goals()
		maintenance_used = 0  # a new quarter, a fresh allowance
	if cycle % 5 == 0:
		save_game()
	# a cycle is long enough for every MAC and ARP entry to age out; what is
	# still true is relearned the moment a host speaks
	Sim.flush_learned_state()

func customer_down_now() -> bool:
	## Somebody's service is off the air, whatever put it there: the flag the
	## economy sets, or the teaching outage that is just as real to look at.
	return customer_outage_active or guided_outage_active()

func best_streak() -> int:
	## The record cannot be behind the run you are having: a streak in progress
	## that is already longer than the best is the best.
	return maxi(best_outage_streak, cycles_since_customer_outage())

func cycles_since_customer_outage() -> int:
	## A streak starts at founding and resets only when an established live
	## customer service is actually unavailable. Alerts and congestion do not.
	return 0 if customer_down_now() else maxi(0, cycle - last_customer_outage_cycle)

func _update_reliability_streak(outage_now: bool) -> void:
	var current := cycles_since_customer_outage()
	if outage_now and not customer_outage_active:
		best_outage_streak = maxi(best_outage_streak, current)
		last_customer_outage_cycle = cycle
		customer_outage_active = true
		for member: Dictionary in staff:
			member["morale"] = maxi(0, int(member.get("morale", 70)) - 3)
		log_event("FLOOR SIGN: customer outage. The %d-cycle reliability streak is over." % current)
		Sfx.play("alert")
	elif outage_now:
		last_customer_outage_cycle = cycle  # an active outage keeps the counter at zero
	elif not outage_now:
		var recovered := customer_outage_active
		customer_outage_active = false
		best_outage_streak = maxi(best_outage_streak, cycles_since_customer_outage())
		if recovered:
			log_event("FLOOR SIGN: customer service restored. The counter is moving again.")
		# A long quiet run becomes a small shared source of pride, not an
		# exploitable morale engine: one point at sparse ten-cycle milestones.
		if cycle > 0 and cycle % 10 == 0 and cycles_since_customer_outage() >= 10:
			for member: Dictionary in staff:
				member["morale"] = mini(100, int(member.get("morale", 70)) + 1)

# ---------- money ----------

func guided_customer_deal() -> Dictionary:
	for deal: Dictionary in deals:
		if bool(deal.get("guided", false)):
			return deal
	return {}

func delivery_credit_for_model(model: String) -> int:
	var deal := guided_customer_deal()
	if deal.is_empty() or bool(deal.get("ever_healthy", false)) or not MODELS.has(model):
		return 0
	if String(deal.get("kind", "")) == "hosting" and String(MODELS[model]["type"]) == "server":
		return mini(int(MODELS[model]["price"]), int(deal.get("delivery_credit", 0)))
	return 0

func shop_price(model: String) -> int:
	## what the instant shop charges: list price under the company's identity
	return int(float(MODELS[model]["price"]) * identity_hardware_multiplier() * price_scale())

func try_buy_device(model: String) -> bool:
	if not MODELS.has(model) or stocked_out(model):
		return false  # on back order: the dock is the only way to get one
	var price := shop_price(model)
	var credit := delivery_credit_for_model(model)
	if money + credit < price:
		return false
	if credit <= 0:
		return try_spend(price)
	var deal := guided_customer_deal()
	deal["delivery_credit"] = int(deal.get("delivery_credit", 0)) - credit
	money -= price - credit
	log_event("DELIVERY RESERVE: $%d funded %s for %s; $%d remains protected."
		% [credit, MODELS[model]["label"], deal["customer"], int(deal["delivery_credit"])])
	money_changed.emit()
	return true

func try_spend(amount: int) -> bool:
	if sandbox:
		return true  # nothing costs anything in a sandbox
	if money < amount:
		return false
	money -= amount
	money_changed.emit()
	return true

func spend_on(category: String, amount: int) -> bool:
	## The same spend, recorded in the cycle's profit and loss, so the Business
	## panel can say where the money actually went.
	if not try_spend(amount):
		return false
	last_pl[category] = int(last_pl.get(category, 0)) - amount
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

func new_device(model: String, second_hand := false) -> Net.NDevice:
	if not MODELS.has(model):
		model = TYPE_DEFAULTS[model]  # accept a bare type, pick its default model
	var m: Dictionary = MODELS[model]
	var type: String = m["type"]
	var spec: Dictionary = TYPE_SPECS[type]
	_counter[type] += 1
	var d := Net.NDevice.new(type, spec["name_prefix"] + str(_counter[type]))
	d.model = model
	d.psu = default_psu(model)
	d.installed_cycle = cycle
	if type == "switch":
		d.vlans = {1: "default"}
	if type in ["router", "firewall", "uplink", "loadbalancer"]:
		d.ip_forwarding = true
	if type == "uplink":
		# the ISP side is preconfigured: handoff /30 + anycast internet, announces default.
		# A second handoff is a second carrier: its own AS and its own /30
		var second := false
		for other in all_devices():
			if other.type == "uplink":
				second = true
		d.bgp = {"asn": 64501 if second else 64500, "neighbors": [], "networks": ["0.0.0.0/0"]}
		d.set_meta("second_carrier", second)
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
	if type == "panel":
		# half the ports are the front, half the back, and each front port is
		# wired straight through to the one behind it
		d.ifaces.clear()
		var pairs: int = int(m["ports"]) / 2
		for n in pairs:
			d.ifaces.append(Net.Iface.new(d, "front%d" % (n + 1), _new_mac()))
		for n2 in pairs:
			d.ifaces.append(Net.Iface.new(d, "rear%d" % (n2 + 1), _new_mac()))
	if type == "switch":
		var mgmt := Net.Iface.new(d, "Management1", _new_mac())
		mgmt.mode = "routed"
		d.ifaces.append(mgmt)
	if type == "uplink":
		d.ifaces[0].ips.append("100.65.0.1/30" if bool(d.get_meta("second_carrier", false)) else "100.64.0.1/30")
		var lo := Net.Iface.new(d, "lo", _new_mac())
		lo.mode = "routed"
		lo.ips = ["8.8.8.8/32", "1.1.1.1/32"]  # "the internet"
		d.ifaces.append(lo)
	if model in LICENSED_MODELS:
		var lic := add_renewal("licence", "feature licence on %s" % d.name, 180, 60, d.name)
		if second_hand:
			# licences follow serials, and a second-hand serial is somebody
			# else's licence: this one arrives already expired
			lic["due"] = cycle - RENEWAL_GRACE
			lic["lapsed"] = true
			log_event("LICENCE: %s came second-hand with no transferable licence. It is capped until you buy one."
				% d.name)
	return d

static func model_height(model: String) -> int:
	return int(HEIGHTS.get(model, 1))

func slot_free(rack: Net.Rack, idx: int) -> bool:
	if idx < 0 or idx >= Net.Rack.SLOTS:
		return false
	return rack.slots[idx] == null and not rack.covered.has(idx)

func can_install(rack: Net.Rack, idx: int, model: String) -> bool:
	## a 2U box needs the slot above it as well, and cannot hang off the top
	for k in model_height(model):
		if not slot_free(rack, idx + k):
			return false
	return true

func install_device(rack: Net.Rack, idx: int, dev: Net.NDevice) -> bool:
	if not can_install(rack, idx, dev.model):
		return false
	rack.slots[idx] = dev
	rack.blanked.erase(idx)
	for k in range(1, model_height(dev.model)):
		rack.covered[idx + k] = dev
		rack.blanked.erase(idx + k)
	topology_changed.emit()
	return true

func free_slots(rack: Net.Rack, dev: Net.NDevice) -> void:
	var at := rack.slots.find(dev)
	if at >= 0:
		rack.slots[at] = null
	for key in rack.covered.keys():
		if rack.covered[key] == dev:
			rack.covered.erase(key)

func _restore_vtep(d: Net.NDevice, src: Dictionary) -> void:
	## JSON turned the vlan->vni map keys into strings
	d.vtep = src.get("vtep", {}).duplicate(true)
	if d.vtep.has("map"):
		var fixed := {}
		for k in d.vtep["map"]:
			fixed[int(k)] = int(d.vtep["map"][k])
		d.vtep["map"] = fixed

func forget_device_state(name: String) -> void:
	## everything keyed by a device name, for a device that is leaving. The
	## documentation is deliberately left alone: stale docs are a lesson
	for table in [physical_access, confirm_commits, lockout_state, firmware_bugs]:
		table.erase(name)
	for key in grey_faults.keys():
		if String(key).begins_with(name + "|"):
			grey_faults.erase(key)
	for ren in renewals.duplicate():
		if String(ren.get("serial", "")) == name:
			renewals.erase(ren)
	for tc in tac_cases:
		if String(tc.get("device", "")) == name and String(tc.get("stage", "")) != "closed":
			tc["stage"] = "closed"  # the vendor is not going to fix hardware you no longer have
	if String(guided_outage.get("device", "")) == name and String(guided_outage.get("state", "")) in ["choice", "recovered"]:
		guided_outage["state"] = "complete"

func rekey_device_state(old_name: String, new_name: String) -> void:
	## the same tables, following a rename
	for table in [physical_access, confirm_commits, lockout_state, firmware_bugs]:
		if table.has(old_name):
			table[new_name] = table[old_name]
			table.erase(old_name)
	for key in grey_faults.keys():
		if String(key).begins_with(old_name + "|"):
			grey_faults[new_name + String(key).substr(old_name.length())] = grey_faults[key]
			grey_faults.erase(key)
	for ren in renewals:
		if String(ren.get("serial", "")) == old_name:
			ren["serial"] = new_name
	for tc in tac_cases:
		if String(tc.get("device", "")) == old_name:
			tc["device"] = new_name
	for m in monitors:
		for field in ["from", "target"]:
			if String(m.get(field, "")) == old_name:
				m[field] = new_name
	if String(guided_outage.get("device", "")) == old_name:
		guided_outage["device"] = new_name

func uninstall_device(dev: Net.NDevice, refund := true) -> void:
	for i: Net.Iface in dev.ifaces:
		disconnect_iface(i)
	forget_device_state(dev.name)
	var r := rack_of(dev)
	if r:
		free_slots(r, dev)
		if r.visual:
			r.visual.queue_redraw()
	if refund:
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
	rekey_device_state(dev.name, new_name)
	dev.name = new_name
	topology_changed.emit()
	return true

# ---------- cables ----------

func recurring_income() -> int:
	## what a working floor bills per cycle right now: campaign service fees
	## plus live customer fees, before anything is spent
	var total := 0
	for c in Contracts.all():
		if c["id"] in contracts_done and not Contracts.retired(c["id"]) and bool(sla_status.get(c["id"], true)):
			total += int(c["reward"]) / 10
	for deal in deals:
		if bool(deal.get("healthy", true)) and not deal.has("renewal"):
			total += int(deal["fee"]) / (2 if bool(deal.get("degraded", false)) else 1)
	return total

func link_fault(i: Net.Iface, reason: String) -> void:
	## the port went down for a physical reason: down/down, not admin down
	i.fault = reason
	i.enabled = false

func link_restore(i: Net.Iface) -> void:
	## the physical problem is gone; an administrative shutdown still holds
	i.fault = ""
	i.err_disabled = false
	i.enabled = not i.admin_down

func iface_status_word(i: Net.Iface) -> String:
	## the word real gear prints in show interfaces status
	if i.admin_down:
		return "disabled"
	if i.err_disabled:
		return "err-disabled"
	if not i.enabled or effective_peer(i) == null:
		return "notconnect"
	return "connected"

func link_at(i: Net.Iface) -> Net.Link:
	for l in links:
		if l.a == i or l.b == i:
			return l
	return null

func panel_partner(i: Net.Iface) -> Net.Iface:
	## The port on the other side of a passive panel: front3 is rear3, always.
	if i.dev.type != "panel":
		return null
	var mate := i.name.replace("front", "rear") if i.name.begins_with("front") \
		else i.name.replace("rear", "front")
	for other: Net.Iface in i.dev.ifaces:
		if other.name == mate:
			return other
	return null

func effective_peer(i: Net.Iface) -> Net.Iface:
	## What is really on the far end of this cable once the passive panels in
	## the middle are followed through. Bounded, so a patch loop cannot hang us.
	var l := link_at(i)
	if l == null:
		return null
	var far := l.other(i)
	for _hop in 8:
		if far.dev.type != "panel":
			return far
		var through := panel_partner(far)
		if through == null:
			return null
		var next_link := link_at(through)
		if next_link == null:
			return null  # patched into a panel port with nothing behind it
		far = next_link.other(through)
	return null  # patched round in a circle: that is not a link

func cable_path(i: Net.Iface) -> Array:
	## Every segment, front to back, for somebody tracing it by hand.
	var out: Array = []
	var here := i
	for _hop in 8:
		var l := link_at(here)
		if l == null:
			break
		var far := l.other(here)
		out.append("%s %s → %s %s" % [here.dev.name, here.name, far.dev.name, far.name])
		if far.dev.type != "panel":
			break
		var through := panel_partner(far)
		if through == null:
			break
		here = through
	return out

func peer_label(i: Net.Iface) -> String:
	var p := effective_peer(i)
	if p == null:
		var l := link_at(i)
		return "%s %s" % [l.other(i).dev.name, l.other(i).name] if l != null else ""
	return "%s %s" % [p.dev.name, p.name]

func free_port(dev: Net.NDevice) -> Net.Iface:
	## The first port on this device that could take a run, ignoring the
	## service ports nobody patches customers into.
	for i: Net.Iface in dev.ifaces:
		if i.name.begins_with("Management") or i.name.begins_with("Vlan") or i.name == "lo" \
				or i.parent != "" or i.name.begins_with("wg") or i.name.begins_with("Tunnel"):
			continue
		if link_at(i) == null:
			return i
	return null

func link_devices(a: Net.NDevice, b: Net.NDevice) -> String:
	## Cable two devices from the map, where neither is necessarily in a
	## cabinet you can see. Says why, when it cannot.
	if a == b:
		return "that is the same device"
	var rack_a := rack_of(a)
	var rack_b := rack_of(b)
	if rack_a == null or rack_b == null:
		return "both ends have to be racked somewhere"
	if int(rack_a.site) != int(rack_b.site) and circuit_between(int(rack_a.site), int(rack_b.site)).is_empty():
		return "%s and %s are on different floors and there is no circuit between them" \
			% [site_name(int(rack_a.site)), site_name(int(rack_b.site))]
	var port_a := free_port(a)
	var port_b := free_port(b)
	if port_a == null:
		return "%s has no free port" % a.name
	if port_b == null:
		return "%s has no free port" % b.name
	var ok := connect_documented(port_a, port_b) if cabling_documented \
		else connect_ifaces(port_a, port_b)
	if not ok:
		return "there is nothing in the drawer to make that run with"
	log_event("CABLED: %s %s to %s %s." % [a.name, port_a.name, b.name, port_b.name])
	return ""

func connect_ifaces(a: Net.Iface, b: Net.Iface) -> bool:
	if not can_link(a, b):
		return false  # different sites need a leased circuit first
	# every run eats a lead: a different cabinet means a long one, and there is
	# nothing to improvise with when the drawer is genuinely empty
	var kind := "patch" if rack_of(a.dev) == rack_of(b.dev) else "optic"
	if not take_part(kind):
		if not take_part("patch"):
			log_event("BLOCKED: no %s left in the drawer. The run waits for a delivery."
				% PART_LABELS[kind])
			return false
		improvise_part(kind)
	links.append(Net.Link.new(a, b))
	Sfx.play("cable")
	Sim.topology_change()
	topology_changed.emit()
	observe_habit("windows", in_maintenance())
	if in_maintenance():
		Skills.observe("change_window")
	return true

func disconnect_iface(i: Net.Iface) -> void:
	var l := link_at(i)
	if l:
		links.erase(l)
		Sim.topology_change()
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
	var vlans_here := {}
	for other: Net.Iface in i.dev.ifaces:
		if other.mode == "access" and int(other.untagged_vlan) > 0 and link_at(other) != null:
			vlans_here[int(other.untagged_vlan)] = true
	if vlans_here.size() >= 2:
		Skills.observe("l2_isolation")
	return true

func add_ip(i: Net.Iface, cidr: String) -> bool:
	cidr = cidr.strip_edges()
	if not Net.valid_cidr(cidr) or cidr in i.ips:
		return false
	i.ips.append(cidr)
	Sim.forget_ip(cidr.split("/")[0])  # the new owner announces itself
	Sim.forget_mac(i.mac)
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

func add_static_route(dev: Net.NDevice, prefix: String, plen: int, via: String, vrf := "", ad := 1) -> bool:
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
	# a second static to the same prefix with a different distance is a
	# floating static: it waits in the wings until the better one goes
	for r in dev.static_routes.duplicate():
		if r["prefix"] == prefix and int(r["plen"]) == plen and String(r.get("vrf", "")) == vrf \
				and (int(r.get("ad", 1)) == ad or r["via"] == via):
			dev.static_routes.erase(r)
	dev.static_routes.append({"prefix": prefix, "plen": plen, "via": via, "vrf": vrf, "ad": ad})
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

func slot_path(i: int) -> String:
	return "%s_auto.json" % slot_prefix if i >= SLOTS else "%s%d.json" % [slot_prefix, i]

func slot_info(i: int) -> Dictionary:
	## what the title screen shows on a slot button
	var path := slot_path(i)
	if not FileAccess.file_exists(path):
		return {"empty": true, "auto": i >= SLOTS}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {"empty": true, "auto": i >= SLOTS, "broken": true}
	var d: Dictionary = data
	return {"empty": false, "auto": i >= SLOTS,
		"company": String(d.get("company_name", "Packet Empire")),
		"cycle": int(d.get("cycle", 0)), "money": int(d.get("money", 0)),
		"stage": int(d.get("stage", 0)), "demo": bool(d.get("demo", false)),
		"saved": String(d.get("saved_at", ""))}

func any_save() -> bool:
	for i in SLOTS + 1:
		if FileAccess.file_exists(slot_path(i)):
			return true
	return FileAccess.file_exists(save_path)

func import_legacy_save() -> void:
	## the single old save becomes slot 1 the first time we see it, so nobody
	## loses the game they were in the middle of
	if not FileAccess.file_exists(save_path) or FileAccess.file_exists(slot_path(0)):
		return
	var raw := FileAccess.get_file_as_string(save_path)
	var f := FileAccess.open(slot_path(0), FileAccess.WRITE)
	if f != null:
		f.store_string(raw)

func delete_slot(i: int) -> void:
	var path := slot_path(i)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func load_slot(i: int) -> bool:
	var path := slot_path(i)
	if not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	current_slot = i
	_apply(data)
	return true

func save_game(slot := -1) -> void:
	if drill_active:
		return  # never write drill state over the real save
	if slot < 0:
		slot = current_slot
	var payload := _serialize()
	payload["saved_at"] = Time.get_datetime_string_from_system(false, true)
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "  "))

func _serialize() -> Dictionary:
	var devs := {}  # name -> serialized (names are unique)
	var rack_data: Array = []
	for r in racks:
		var slot_names: Array = []
		for d in r.slots:
			slot_names.append(d.name if d else null)
			if d:
				devs[d.name] = _ser_device(d)
		rack_data.append({"name": r.name, "site": r.site, "tile": [r.tile.x, r.tile.y],
			"slots": slot_names, "blanked": r.blanked.keys(), "note": r.note})
	var link_data: Array = []
	for l in links:
		link_data.append([l.a.dev.name, l.a.name, l.b.dev.name, l.b.name, l.note])
	return {"money": money, "stage": stage, "cycle": cycle,
		"company_name": company_name, "demo": demo,
		"last_customer_outage_cycle": last_customer_outage_cycle,
		"best_outage_streak": best_outage_streak,
		"customer_outage_active": customer_outage_active,
		"feeds": feeds, "feed_out_until": feed_out_until, "ups": ups,
		"carrier_outage": carrier_outage, "hijacks": hijacks,
		"transit_samples": transit_samples, "ixp": ixp, "playbooks": playbooks, "runbooks": runbooks,
		"runbook_runs": runbook_runs,
		"buyout_offer": buyout_offer, "sold_out": sold_out, "references": references,
		"leads": leads, "timeline": timeline,
		"ipv4_blocks": ipv4_blocks, "accountant": accountant, "fixed_tariff": fixed_tariff,
		"efficiency": efficiency, "quarter_profit": quarter_profit,
		"quarter_depreciation": quarter_depreciation,
		"invoices": invoices,
		"reputation": reputation, "debt": debt, "stats": stats, "rivals": rivals,
		"difficulty": difficulty, "achievements": achievements,
		"market_intel": market_intel, "nemesis": nemesis, "nemesis_reason": nemesis_reason, "staff": staff, "candidates": candidates,
		"monitors": monitors, "history": history, "templates": templates, "reports": reports,
		"attacks": attacks, "scrubbing": scrubbing, "insured": insured, "marketing": marketing,
		"sandbox": sandbox, "blueprints": blueprints,
		"maintenance_until": maintenance_until, "maintenance_used": maintenance_used,
		"callout_who": callout_who, "callout_until": callout_until, "oncall": oncall,
		"oncall_since": oncall_since,
		"night_call": night_call, "handover": handover, "dr_test": dr_test,
		"status_posts": status_posts, "spares": spares,
		"guided_outage": guided_outage,
		"customer_arcs": customer_arcs,
		"feature_intros_seen": feature_intros_seen,
		"feature_discovery_trace": feature_discovery_trace,
		"contract_debriefs": contract_debriefs, "mastered_contracts": mastered_contracts,
		"active_contract_debrief": active_contract_debrief,
		"incidents": incidents, "blame_fear": blame_fear,
		"destruction_certs": destruction_certs, "data_risks": data_risks, "quarter_goals": quarter_goals,
		"facility": facility, "facility_auto": facility_auto, "tour": tour, "renewals": renewals, "audit": audit, "decisions": decisions, "consequences": consequences, "hazards": hazards,
		"protection": protection, "access_policy": access_policy, "identity": identity, "finale": finale, "pl_totals": pl_totals, "rank_seen": rank_seen, "season_seen": _season_seen, "cameras": cameras,
		"access_log": access_log, "visitors": visitors,
		"decisions_seen": decisions_seen, "decision_notes": decision_notes,
		"control_evidence": control_evidence, "trust_marker": trust_marker, "tac_cases": tac_cases, "orphan_intel": orphan_intel, "docs": docs,
		"confirm_commits": confirm_commits, "tickets": tickets, "grey_faults": grey_faults, "physical_access": physical_access, "remote_jobs": remote_jobs, "crates": crates, "packaging": packaging, "stockouts": stockouts, "rmas": rmas,
		"latent_defects": latent_defects, "parts": parts,
		"parts_auto": parts_auto, "cable_debt": cable_debt,
		"cabling_documented": cabling_documented, "duties": duties, "change_window": change_window,
		"firmware_bugs": firmware_bugs, "heat_wave_until": heat_wave_until, "habits": habits,
		"upstream": upstream, "last_upstream_cycle": last_upstream_cycle,
		"skill_log": skill_log, "skill_fumbles": skill_fumbles, "pending_reports": pending_reports,
		"acquisitions": acquisitions, "sites": sites, "current_site": current_site,
		"circuits": circuits,
		"events": events, "incidents_seen": incidents_seen, "counters": _counter, "digest": digest,
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
	_restore_vtep(d, cfg)
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
		for field in ["mode", "untagged_vlan", "mtu", "admin_down", "duplex", "nat", "lag", "mlag", "helper",
				"port_security", "tagged_vlans", "ips"]:
			var a := JSON.stringify(oi.get(field, null))
			var b := JSON.stringify(ni.get(field, null))
			if a != b:
				out.append("~ interface %s: %s %s -> %s" % [name,
					"shutdown" if field == "admin_down" else field, a, b])
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
			i.admin_down = false
			link_restore(i)
		topology_changed.emit()
		return
	d.vlans = {}
	for vid in cfg.get("vlans", {}):
		d.vlans[int(vid)] = cfg["vlans"][vid]
	_restore_vtep(d, cfg)
	d.mac_static = {}
	for vid in cfg.get("mac_static", {}):
		d.mac_static[int(vid)] = Dictionary(cfg["mac_static"][vid]).duplicate()
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
		# a saved configuration carries the administrative state; it cannot
		# mend a cable, and it does not pretend to
		target.admin_down = bool(si.get("admin_down", not bool(si.get("enabled", true))))
		target.duplex = String(si.get("duplex", "auto"))
		target.enabled = not target.admin_down and target.fault == "" and not target.err_disabled
		target.mtu = int(si["mtu"])
		target.mode = si["mode"]
		target.untagged_vlan = int(si["untagged_vlan"])
		target.tagged_vlans = si.get("tagged_vlans", []).duplicate()
		target.nat = si.get("nat", "")
		target.vrrp = si.get("vrrp", {}).duplicate(true)
		target.lag = int(si.get("lag", 0))
		target.mlag = int(si.get("mlag", 0))
		target.bfd = bool(si.get("bfd", false))
		target.ra = bool(si.get("ra", false))
		target.mlag_peerlink = bool(si.get("mlag_peerlink", false))
		target.helper = si.get("helper", "")
	topology_changed.emit()

func _ser_device(d: Net.NDevice) -> Dictionary:
	var ifs: Array = []
	for i: Net.Iface in d.ifaces:
		ifs.append({"name": i.name, "mac": i.mac, "enabled": i.enabled, "mtu": i.mtu,
			"admin_down": i.admin_down, "err_disabled": i.err_disabled, "fault": i.fault, "duplex": i.duplex,
			"mode": i.mode, "untagged_vlan": i.untagged_vlan, "tagged_vlans": i.tagged_vlans,
			"nat": i.nat, "vrrp": i.vrrp, "lag": i.lag, "lag_mode": i.lag_mode, "helper": i.helper,
			"mlag": i.mlag, "mlag_peerlink": i.mlag_peerlink, "bfd": i.bfd, "ra": i.ra,
			"parent": i.parent, "dot1q": i.dot1q,
			"tunnel_src": i.tunnel_src, "tunnel_dst": i.tunnel_dst,
			"wg_key": i.wg_key, "wg_peers": i.wg_peers,
			"port_security": i.port_security, "secure_mac": i.secure_mac, "vrf": i.vrf, "qos": i.qos,
			"portfast": i.portfast, "bpduguard": i.bpduguard,
			"dhcp_trusted": i.dhcp_trusted, "vm": i.vm,
			"pvlan": i.pvlan, "storm_limit": i.storm_limit, "dot1x": i.dot1x,
			"ips": i.ips, "note": i.note})
	return {"type": d.type, "model": d.model, "name": d.name, "status": d.status, "vlans": d.vlans, "vtep": d.vtep,
		"mac_static": d.mac_static, "note": d.note,
		"ip_forwarding": d.ip_forwarding, "static_routes": d.static_routes,
		"services": d.services, "resolver": d.resolver, "acls": d.acls, "stateful": d.stateful, "bgp": d.bgp,
		"ospf": d.ospf, "vrfs": d.vrfs, "snooping": d.snooping, "dai": d.dai,
		"ssids": d.ssids, "wifi": d.wifi, "radius": d.radius,
		"igmp_snooping": d.igmp_snooping, "mcast_groups": d.mcast_groups,
		"mlag_peer": d.mlag_peer, "psu": d.psu, "snmp": d.snmp, "aaa": d.aaa,
		"stp_mode": d.stp_mode, "stp_priority": d.stp_priority,
		"mst_instances": d.mst_instances,
		"startup": d.startup, "versions": d.versions,
		"acquired_from": d.acquired_from, "installed_cycle": d.installed_cycle,
		"log_host": d.log_host, "ntp_server": d.ntp_server,
		"ifaces": ifs}

func load_game() -> bool:
	## the current slot if it exists, otherwise the original single save
	if FileAccess.file_exists(slot_path(current_slot)):
		return load_slot(current_slot)
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
	last_cycle_delta = 0
	last_pl = {}
	last_business = {"revenue": 0, "invoiced": 0, "collected": 0,
		"power": 0, "transit": 0}
	money = int(data["money"])
	company_name = String(data.get("company_name", "Packet Empire"))
	demo = bool(data.get("demo", false))
	feeds = {}
	for k in data.get("feeds", {}):
		feeds[int(k)] = data["feeds"][k]
	feed_out_until = data.get("feed_out_until", {})
	invoices = data.get("invoices", [])
	carrier_outage = data.get("carrier_outage", {})
	hijacks = data.get("hijacks", [])
	transit_samples = data.get("transit_samples", [])
	ixp = data.get("ixp", {})
	playbooks = data.get("playbooks", [])
	runbooks = data.get("runbooks", [])
	runbook_runs = data.get("runbook_runs", [])
	ipv4_blocks = int(data.get("ipv4_blocks", 1))
	buyout_offer = data.get("buyout_offer", {})
	sold_out = bool(data.get("sold_out", false))
	references = data.get("references", [])
	leads = data.get("leads", [])
	timeline = data.get("timeline", [])
	accountant = bool(data.get("accountant", false))
	fixed_tariff = bool(data.get("fixed_tariff", false))
	efficiency = int(data.get("efficiency", 0))
	quarter_profit = int(data.get("quarter_profit", 0))
	quarter_depreciation = int(data.get("quarter_depreciation", 0))
	ups = {}
	for k2 in data.get("ups", {}):
		ups[int(k2)] = int(data["ups"][k2])
	contracts_done = data.get("contracts_done", [])
	stage = int(data.get("stage", 0))
	offers = data.get("offers", [])
	cycle = int(data.get("cycle", 0))
	last_customer_outage_cycle = int(data.get("last_customer_outage_cycle", 0))
	best_outage_streak = int(data.get("best_outage_streak", 0))
	customer_outage_active = bool(data.get("customer_outage_active", false))
	reputation = int(data.get("reputation", 50))
	difficulty = int(data.get("difficulty", 1))
	achievements = data.get("achievements", [])
	acquisitions = data.get("acquisitions", [])
	circuits = data.get("circuits", [])
	sites = data.get("sites", [])
	_ensure_sites()
	current_site = mini(int(data.get("current_site", 0)), sites.size() - 1)
	market_intel = int(data.get("market_intel", 0))
	nemesis = String(data.get("nemesis", ""))
	nemesis_reason = String(data.get("nemesis_reason", ""))
	maintenance_until = int(data.get("maintenance_until", -1))
	maintenance_used = int(data.get("maintenance_used", 0))
	oncall = String(data.get("oncall", ""))
	oncall_since = int(data.get("oncall_since", -1))
	night_call = data.get("night_call", {})
	handover = data.get("handover", {})
	dr_test = data.get("dr_test", {})
	callout_who = String(data.get("callout_who", ""))
	callout_until = int(data.get("callout_until", -1))
	incidents = data.get("incidents", [])
	blame_fear = int(data.get("blame_fear", 0))
	facility = data.get("facility", {})
	tour = data.get("tour", {})
	audit = data.get("audit", {})
	decisions = data.get("decisions", [])
	hazards = data.get("hazards", [])
	access_policy = String(data.get("access_policy", "open"))
	identity = String(data.get("identity", ""))
	finale = data.get("finale", {})
	pl_totals = data.get("pl_totals", {})
	rank_seen = String(data.get("rank_seen", ""))
	_season_seen = int(data.get("season_seen", -1))
	cameras = bool(data.get("cameras", false))
	access_log = data.get("access_log", [])
	visitors = data.get("visitors", [])
	protection = data.get("protection", {})
	consequences = data.get("consequences", [])
	decisions_seen = data.get("decisions_seen", [])
	decision_notes = data.get("decision_notes", [])
	control_evidence = data.get("control_evidence", {})
	trust_marker = bool(data.get("trust_marker", false))
	renewals = data.get("renewals", [])
	tac_cases = data.get("tac_cases", [])
	orphan_intel = data.get("orphan_intel", {})
	docs = data.get("docs", {})
	confirm_commits = data.get("confirm_commits", {})
	tickets = data.get("tickets", [])
	for dk in data.get("digest", {}):
		digest[int(dk)] = data["digest"][dk]  # JSON turned the cycle keys into strings
	_ticket_seq = 0
	for t0 in tickets:
		var tid := String(t0.get("id", "T0")).trim_prefix("T")
		if tid.is_valid_int():
			_ticket_seq = maxi(_ticket_seq, int(tid))
	grey_faults = data.get("grey_faults", {})
	physical_access = data.get("physical_access", {})
	remote_jobs = data.get("remote_jobs", [])
	crates = data.get("crates", [])
	stockouts = data.get("stockouts", {})
	rmas = data.get("rmas", [])
	latent_defects = data.get("latent_defects", {})
	parts = data.get("parts", {"patch": 40, "optic": 8, "power": 20, "blank": 12})
	parts_auto = bool(data.get("parts_auto", true))
	duties = data.get("duties", {})
	change_window = data.get("change_window", {})
	cable_debt = int(data.get("cable_debt", 0))
	cabling_documented = bool(data.get("cabling_documented", false))
	packaging = int(data.get("packaging", 0))
	firmware_bugs = data.get("firmware_bugs", {})
	facility_auto = data.get("facility_auto", {})
	heat_wave_until = int(data.get("heat_wave_until", -1))
	destruction_certs = data.get("destruction_certs", [])
	quarter_goals = data.get("quarter_goals", [])
	data_risks = data.get("data_risks", [])
	upstream = data.get("upstream", {})
	skill_log = data.get("skill_log", {})
	skill_fumbles = data.get("skill_fumbles", {})
	pending_recognition = []
	last_upstream_cycle = int(data.get("last_upstream_cycle", -999))
	habits = data.get("habits", {"saves": 0.5, "documents": 0.5, "windows": 0.5, "tidy": 0.5})
	pending_reports = data.get("pending_reports", [])
	status_posts = data.get("status_posts", [])
	spares = data.get("spares", {})
	guided_outage = data.get("guided_outage", {})
	customer_arcs = data.get("customer_arcs", {})
	feature_intros_seen = data.get("feature_intros_seen", [])
	feature_discovery_trace = _feature_discovery_trace_from_data(data)
	contract_debriefs = data.get("contract_debriefs", {})
	mastered_contracts = data.get("mastered_contracts", [])
	active_contract_debrief = data.get("active_contract_debrief", {})
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
	# a name is not a person: whoever the rota named may have left since
	if callout_who != "" and Staff.by_name(callout_who).is_empty():
		callout_who = ""
		callout_until = -1
	if oncall != "" and Staff.by_name(oncall).is_empty():
		oncall = ""
	for k in duties.keys():
		if Staff.by_name(String(duties[k])).is_empty():
			duties.erase(k)
	candidates = data.get("candidates", [])
	rivals = data.get("rivals", [])
	if rivals.is_empty():
		rivals = Rivals.spawn()
	debt = int(data.get("debt", 0))
	reset_run_state()
	for k in data.get("stats", {}):
		stats[k] = int(data["stats"][k])
	events = data.get("events", [])
	incidents_seen = data.get("incidents_seen", {})
	deals = data.get("deals", [])
	for k in _counter.keys():
		_counter[k] = 0  # a new company numbers its first switch sw1 again
	for k in data["counters"]:
		_counter[k] = int(data["counters"][k])
	var by_name := {}
	for dname in data["devices"]:
		var sd: Dictionary = data["devices"][dname]
		var d := Net.NDevice.new(sd["type"], sd["name"])
		d.model = sd.get("model", TYPE_DEFAULTS[sd["type"]])
		# every field defaults: a save written before one existed still loads
		d.status = String(sd.get("status", "active"))
		d.ip_forwarding = bool(sd.get("ip_forwarding", d.type in ["router", "firewall", "uplink",
			"loadbalancer"]))
		d.static_routes = sd.get("static_routes", [])
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
		d.mlag_peer = sd.get("mlag_peer", "")
		d.psu = String(sd.get("psu", default_psu(d.model)))
		d.snmp = String(sd.get("snmp", ""))
		d.aaa = sd.get("aaa", {}).duplicate(true)
		d.stp_mode = String(sd.get("stp_mode", "rstp"))
		d.stp_priority = int(sd.get("stp_priority", 32768))
		d.mst_instances = sd.get("mst_instances", {}).duplicate(true)
		d.igmp_snooping = bool(sd.get("igmp_snooping", false))
		d.mcast_groups = sd.get("mcast_groups", [])
		d.startup = sd.get("startup", {})
		d.versions = sd.get("versions", [])
		d.acquired_from = sd.get("acquired_from", "")
		d.installed_cycle = int(sd.get("installed_cycle", 0))
		d.log_host = sd.get("log_host", "")
		d.ntp_server = sd.get("ntp_server", "")
		d.note = sd.get("note", {}).duplicate(true)
		d.resolver = sd.get("resolver", "")
		for vid in sd.get("vlans", {}):
			d.vlans[int(vid)] = sd["vlans"][vid]
		_restore_vtep(d, sd)
		for vid in sd.get("mac_static", {}):
			d.mac_static[int(vid)] = Dictionary(sd["mac_static"][vid]).duplicate()
		for si in sd.get("ifaces", []):
			var i := Net.Iface.new(d, String(si["name"]), String(si.get("mac", _new_mac())))
			i.enabled = bool(si.get("enabled", true))
			i.admin_down = bool(si.get("admin_down", false))
			i.err_disabled = bool(si.get("err_disabled", false))
			i.fault = String(si.get("fault", ""))
			i.duplex = String(si.get("duplex", "auto"))
			i.mtu = int(si.get("mtu", 1500))
			i.mode = String(si.get("mode", "access"))
			i.untagged_vlan = int(si.get("untagged_vlan", 1))
			for tv in si.get("tagged_vlans", []):
				i.tagged_vlans.append(int(tv))
			i.nat = si.get("nat", "")
			i.vrrp = si.get("vrrp", {})
			i.lag = int(si.get("lag", 0))
			i.lag_mode = String(si.get("lag_mode", "on"))
			i.mlag = int(si.get("mlag", 0))
			i.bfd = bool(si.get("bfd", false))
			i.ra = bool(si.get("ra", false))
			i.mlag_peerlink = bool(si.get("mlag_peerlink", false))
			i.helper = si.get("helper", "")
			i.vrf = si.get("vrf", "")
			i.qos = bool(si.get("qos", false))
			i.dhcp_trusted = bool(si.get("dhcp_trusted", false))
			i.vm = si.get("vm", "")
			i.pvlan = si.get("pvlan", "")
			i.dot1x = bool(si.get("dot1x", false))
			i.storm_limit = int(si.get("storm_limit", 0))
			i.port_security = si.get("port_security", false)
			i.portfast = bool(si.get("portfast", false))
			i.bpduguard = bool(si.get("bpduguard", false))
			i.secure_mac = si.get("secure_mac", "")
			i.tunnel_src = si.get("tunnel_src", "")
			i.tunnel_dst = si.get("tunnel_dst", "")
			i.wg_key = si.get("wg_key", "")
			i.wg_peers = si.get("wg_peers", [])
			i.parent = si.get("parent", "")
			i.dot1q = int(si.get("dot1q", 0))
			i.ips = si.get("ips", [])
			i.note = si.get("note", {}).duplicate(true)
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
		r.note = rd.get("note", {}).duplicate(true)
		for blanked_slot in rd.get("blanked", []):
			r.blanked[int(blanked_slot)] = true
		for si in rd.get("slots", []).size():
			if rd["slots"][si] != null:
				var loaded_dev: Net.NDevice = by_name[rd["slots"][si]]
				r.slots[si] = loaded_dev
				r.blanked.erase(si)
				for covered_i in range(1, model_height(loaded_dev.model)):
					if si + covered_i < Net.Rack.SLOTS:
						r.covered[si + covered_i] = loaded_dev
						r.blanked.erase(si + covered_i)
		racks.append(r)
	for ld in data["links"]:
		var a := _find_iface(by_name[ld[0]], ld[1])
		var b := _find_iface(by_name[ld[2]], ld[3])
		if a and b:
			var restored := Net.Link.new(a, b)
			if ld.size() > 4 and ld[4] is Dictionary:
				restored.note = (ld[4] as Dictionary).duplicate(true)  # the label on the run
			links.append(restored)
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
