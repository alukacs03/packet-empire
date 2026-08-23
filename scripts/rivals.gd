class_name Rivals
## AI-run competitors. They bid against the player for every customer,
## grow on their own revenue, poach overpriced contracts, and can be
## bought outright once the player can afford them.

const NAMES := ["Duna Systems", "Rackforge Kft", "Nimbus Hosting", "Vasgep Zrt"]
const STARTERS := [
	# net: the subnet THEY run on, vlan: THEIR vlan numbering. Deliberately
	# overlapping the ranges players tend to use, because that is the mess a
	# real acquisition hands you.
	{"cash": 2500, "aggression": 0.92, "capacity": 3, "net": "10.0.0", "vlan": 1,
		"racks": [["sw-8", "srv-1", "srv-1"]]},
	{"cash": 4000, "aggression": 0.85, "capacity": 4, "net": "10.0.0", "vlan": 10,
		"racks": [["sw-8", "srv-1"], ["rtr-lite", "srv-1"]]},
	{"cash": 6000, "aggression": 0.98, "capacity": 5, "net": "192.168.1", "vlan": 20,
		"racks": [["sw-24", "srv-2", "srv-1", "fw-1"]]},
	{"cash": 1800, "aggression": 1.05, "capacity": 2, "net": "172.16.5", "vlan": 5,
		"racks": [["sw-lite", "srv-1"]]},
]

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
	## goodwill on their book of business plus the hardware in their racks
	var hw := 0
	for rack in r["racks"]:
		hw += Game.RACK_PRICE
		for model in rack:
			hw += int(Game.MODELS[model]["price"])
	return int(r["cash"]) / 2 + int(r["deals"]) * 900 + hw

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
