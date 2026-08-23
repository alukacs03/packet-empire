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

## How each company actually competes. A market where everyone behaves the
## same way is a market with one opponent in it, seven times over.
const STRATEGIES := {
	"budget": {"label": "cut-price", "bid": 0.78, "min": 0.5, "quality": 0.6,
		"blurb": "Undercuts everyone and delivers accordingly."},
	"premium": {"label": "premium", "bid": 1.22, "min": 1.6, "quality": 1.4,
		"blurb": "Expensive, and their customers stay."},
	"volume": {"label": "volume", "bid": 0.94, "min": 0.7, "quality": 0.9,
		"blurb": "Takes everything, grows fast, stretched thin."},
	"specialist": {"label": "specialist", "bid": 1.1, "min": 1.2, "quality": 1.25,
		"blurb": "Only bids on work it is good at, and wins it."},
	"predator": {"label": "acquisitive", "bid": 1.0, "min": 1.0, "quality": 1.0,
		"blurb": "Would rather buy a competitor than out-bid one."},
}
## What a specialist actually specialises in.
const NICHES := ["secure_host", "public_hosting", "redundant_gw", "own_vlan"]

## Rivals run on their own random stream. Their background behaviour must not
## shift the sequence the rest of the simulation draws from, or every test
## downstream of a competitor getting lucky becomes a coin flip.
static var _rng := RandomNumberGenerator.new()
static var _rng_ready := false

static func _roll() -> float:
	if not _rng_ready:
		_rng_ready = true
		_rng.seed = 771103
	return _rng.randf()

static func strategy_of(r: Dictionary) -> Dictionary:
	return STRATEGIES.get(String(r.get("strategy", "volume")), STRATEGIES["volume"])

static func has_site(r: Dictionary) -> bool:
	return r.has("site")

static func spawn() -> Array:
	var out: Array = []
	for i in NAMES.size():
		var s: Dictionary = STARTERS[i].duplicate(true)
		s["name"] = NAMES[i]
		s["deals"] = 0
		s["revenue"] = 0
		s["base_aggression"] = s["aggression"]  # difficulty scales this later
		s["strategy"] = STRATEGIES.keys()[i % STRATEGIES.size()]
		if s["strategy"] == "specialist":
			s["niche"] = NICHES[i % NICHES.size()]
		out.append(s)
	return out

static func alive(r: Dictionary) -> bool:
	return not bool(r.get("bought", false))

## What a rival would charge for this job: their aggression against the
## customer budget, plus a nudge for how loaded they already are.
static func bid_for(r: Dictionary, offer: Dictionary) -> int:
	var load_factor := 1.0 + 0.12 * float(r["deals"])
	var strat := strategy_of(r)
	var price := float(int(offer["budget"])) * float(r["aggression"]) * load_factor \
		* float(strat["bid"])
	# a specialist bids hard on its own patch and barely bothers elsewhere
	if String(r.get("strategy", "")) == "specialist":
		price *= 0.82 if String(offer.get("kind", "")) == String(r.get("niche", "")) else 1.4
	return int(price)

static func will_bid(r: Dictionary, offer: Dictionary) -> bool:
	if String(r.get("strategy", "")) == "specialist":
		return String(offer.get("kind", "")) == String(r.get("niche", ""))
	return true

## The smallest job a company will get out of bed for: big operators do not
## chase a two-hundred-forint VLAN, which is the niche a new shop lives in.
static func min_job(r: Dictionary) -> int:
	return int(float(int(r["capacity"]) * 14) * float(strategy_of(r)["min"]))

## The cheapest rival able and willing to take the job, or {} if none.
static func best_bidder(offer: Dictionary) -> Dictionary:
	var best := {}
	var best_bid := 1 << 30
	for r in Game.rivals:
		if not alive(r) or int(r["deals"]) >= int(r["capacity"]):
			continue
		if int(offer.get("budget", 0)) < min_job(r):
			continue  # beneath them
		if not will_bid(r, offer):
			continue  # not their kind of work
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

static func player_valuation() -> int:
	## what your book of business, hardware and premises are worth to somebody
	## who wants them without building them
	var hw := 0
	for d in Game.all_devices():
		hw += int(Game.MODELS[d.model]["price"]) / 2  # second hand
	var premises := 0
	for i in Game.site_count():
		var g: Vector2i = Game.grid_size(i)
		premises += g.x * g.y * 220
	var goodwill := Game.deals.size() * 1100 + Game.contracts_done.size() * 400
	goodwill = int(float(goodwill) * (0.6 + float(Game.reputation) / 100.0))
	return maxi(0, hw + premises + goodwill - Game.debt)

static func would_buy_player(r: Dictionary) -> bool:
	## They make an approach when they can afford you and you look gettable:
	## short of cash, carrying debt, or simply worth more than you are earning.
	if not alive(r) or String(r.get("strategy", "")) != "predator":
		return false
	var price := player_valuation()
	if price <= 0 or int(r["cash"]) < price:
		return false
	return Game.money < price / 4 or Game.debt > 0 or Game.reputation < 45

static func maybe_offer_for_player() -> void:
	if Game.buyout_offer != null and not Game.buyout_offer.is_empty():
		return
	if Game.contracts_done.size() < 4 or _roll() > 0.05:
		return
	for r in Game.rivals:
		if not would_buy_player(r):
			continue
		var price := int(float(player_valuation()) * (0.9 + _roll() * 0.4))
		Game.buyout_offer = {"rival": String(r["name"]), "price": price,
			"ttl": 4, "cycle": Game.cycle}
		Game.log_event("APPROACH: %s would like to buy your company for $%d. It is on the table for a few cycles."
			% [r["name"], price])
		return

static func racks_needed(r: Dictionary) -> int:
	return r["racks"].size()

## Each cycle: rivals bank revenue from their book and slowly get bolder.
static func tick() -> void:
	for r in Game.rivals:
		if not alive(r):
			continue
		r["cash"] = int(r["cash"]) + int(r["deals"]) * 90
		# they win business on their own too
		if int(r["deals"]) < int(r["capacity"]) and _roll() < 0.06:
			r["deals"] = int(r["deals"]) + 1
		if String(r.get("strategy", "")) == "volume" and int(r["deals"]) < int(r["capacity"]) \
				and _roll() < 0.08:
			r["deals"] = int(r["deals"]) + 1  # they will take anything
		if int(r["cash"]) > 9000 and int(r["capacity"]) < 12:
			r["cash"] = int(r["cash"]) - 3000
			r["capacity"] = int(r["capacity"]) + 1
			r["racks"].append(["sw-8", "srv-1"])
		# a flush operator eventually needs premises of its own
		if int(r["cash"]) > 22000 and not has_site(r):
			r["cash"] = int(r["cash"]) - 15000
			r["site"] = {"name": "%s room" % String(r["name"]).split(" ")[0],
				"grid": [6, 6], "kind": "room"}
			Game.log_event("MARKET: %s moved into premises of their own." % r["name"])
	_maybe_consolidate()

static func _maybe_consolidate() -> void:
	## the market consolidates: a rich rival swallows a struggling one
	if _roll() > 0.04:
		return
	var buyer := {}
	var prey := {}
	for r in Game.rivals:
		if not alive(r):
			continue
		# an acquisitive company goes shopping much sooner than the others
		var threshold := 12000 if String(r.get("strategy", "")) == "predator" else 20000
		if int(r["cash"]) > threshold and (buyer.is_empty() or int(r["cash"]) > int(buyer["cash"])):
			buyer = r
		if int(r["deals"]) <= 1 and int(r["cash"]) < 2500 and prey.is_empty():
			prey = r
	if buyer.is_empty() or prey.is_empty() or buyer == prey:
		return
	buyer["cash"] = int(buyer["cash"]) - 8000
	buyer["deals"] = int(buyer["deals"]) + int(prey["deals"])
	buyer["capacity"] = int(buyer["capacity"]) + int(prey["capacity"])
	for rack in prey["racks"]:
		buyer["racks"].append(rack)
	prey["bought"] = true
	prey["merged_into"] = buyer["name"]
	Game.log_event("MARKET: %s acquired %s. The field is getting smaller."
		% [buyer["name"], prey["name"]])
