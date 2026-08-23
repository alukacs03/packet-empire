class_name Rivals
## AI-run competitors. They bid against the player for every customer,
## grow on their own revenue, poach overpriced contracts, and can be
## bought outright once the player can afford them.

const NAMES := ["Kabel Bela Bt", "Duna Systems", "Rackforge Kft", "Nimbus Hosting",
	"Vasgep Zrt", "Alfold Telekom", "Panonia Data"]
## net/vlan: the addressing and VLAN numbering THEY run, deliberately
## overlapping the ranges players use. "site" describes premises that come
## with the company: a one-rack shop gets relocated into your room, but a
## company with its own room or floor is bought together with the building.
const STARTERS := [
	{"cash": 900, "aggression": 1.08, "capacity": 1, "net": "192.168.0", "vlan": 1,
		"racks": [["sw-lite", "srv-1"]]},
	{"cash": 2500, "aggression": 0.92, "capacity": 3, "net": "10.0.0", "vlan": 1,
		"racks": [["sw-8", "srv-1", "srv-1"]]},
	{"cash": 4000, "aggression": 0.85, "capacity": 4, "net": "10.0.0", "vlan": 10,
		"racks": [["sw-8", "srv-1"], ["rtr-lite", "srv-1"]],
		"site": {"name": "Rackforge room", "grid": [5, 5], "kind": "room"}},
	{"cash": 6000, "aggression": 0.98, "capacity": 5, "net": "192.168.1", "vlan": 20,
		"racks": [["sw-24", "srv-2", "srv-1", "fw-1"]],
		"site": {"name": "Nimbus room", "grid": [6, 6], "kind": "room"}},
	{"cash": 1800, "aggression": 1.05, "capacity": 2, "net": "172.16.5", "vlan": 5,
		"racks": [["sw-lite", "srv-1"]]},
	{"cash": 15000, "aggression": 0.9, "capacity": 8, "net": "10.10.0", "vlan": 100,
		"racks": [["sw-24", "srv-2", "srv-2", "fw-1"], ["sw-24", "srv-2", "rtr-edge"],
			["sw-8", "srv-1", "srv-1"]],
		"site": {"name": "Alfold DC floor", "grid": [10, 10], "kind": "floor"}},
	{"cash": 26000, "aggression": 0.88, "capacity": 10, "net": "172.20.0", "vlan": 200,
		"racks": [["sw-24", "srv-2", "srv-2", "fw-1"], ["sw-24", "rtr-edge", "srv-2"],
			["sw-24", "srv-2", "srv-1"], ["sw-8", "srv-1", "crac-1"]],
		"site": {"name": "Panonia DC floor", "grid": [12, 12], "kind": "floor"}},
]

static func has_site(r: Dictionary) -> bool:
	return r.has("site")

static func spawn() -> Array:
	var out: Array = []
	for i in NAMES.size():
		var s: Dictionary = STARTERS[i].duplicate(true)
		s["name"] = NAMES[i]
		s["deals"] = 0
		s["revenue"] = 0
		out.append(s)
	return out

static func alive(r: Dictionary) -> bool:
	return not bool(r.get("bought", false))

## What a rival would charge for this job: their aggression against the
## customer budget, plus a nudge for how loaded they already are.
static func bid_for(r: Dictionary, offer: Dictionary) -> int:
	var load_factor := 1.0 + 0.12 * float(r["deals"])
	return int(int(offer["budget"]) * float(r["aggression"]) * load_factor)

## The cheapest rival able to take the job, or {} if all are full.
static func best_bidder(offer: Dictionary) -> Dictionary:
	var best := {}
	var best_bid := 1 << 30
	for r in Game.rivals:
		if not alive(r) or int(r["deals"]) >= int(r["capacity"]):
			continue
		var bid := bid_for(r, offer)
		if bid < best_bid:
			best_bid = bid
			best = r
	return best

static func asking_price(r: Dictionary) -> int:
	## goodwill on their book of business, the hardware in their racks, and
	## the premises if the company owns any
	var hw := 0
	for rack in r["racks"]:
		hw += Game.RACK_PRICE
		for model in rack:
			hw += int(Game.MODELS[model]["price"])
	var premises := 0
	if has_site(r):
		var g: Array = r["site"]["grid"]
		premises = int(g[0]) * int(g[1]) * 260
	return int(r["cash"]) / 2 + int(r["deals"]) * 900 + hw + premises

static func racks_needed(r: Dictionary) -> int:
	return r["racks"].size()

## Each cycle: rivals bank revenue from their book and slowly get bolder.
static func tick() -> void:
	for r in Game.rivals:
		if not alive(r):
			continue
		r["cash"] = int(r["cash"]) + int(r["deals"]) * 90
		if int(r["cash"]) > 9000 and int(r["capacity"]) < 8:
			r["cash"] = int(r["cash"]) - 3000
			r["capacity"] = int(r["capacity"]) + 1
			r["racks"].append(["sw-8", "srv-1"])
