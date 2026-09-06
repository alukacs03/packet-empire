class_name FirstCustomer
## The opening's authored pressure event. State lives inside the existing
## customer_arcs save field; old companies are never enrolled retroactively.

const PLANS := {
	"stagger": {"name": "A steady launch", "fee": 0, "bonus": 250,
		"demand": [300, 650, 450],
		"detail": "Invite shoppers in groups. Less traffic, a smaller success bonus."},
	"premiere": {"name": "Everyone at once", "fee": 120, "bonus": 650,
		"demand": [500, 950, 750],
		"detail": "Reserve the promotion for $120. More orders, very little room on a shared gigabit link."},
}

static func state() -> Dictionary:
	return Game.customer_arcs.get("sale_night", {})

static func enabled() -> bool:
	return int(Game.stats.get("customer_arc_version", 0)) == 1

static func active() -> bool:
	return enabled() and String(state().get("phase", "")) in ["planning", "countdown", "live", "debrief"]

static func complete() -> bool:
	return String(state().get("phase", "")) == "complete"

const PROTECTED_CYCLES := 48  # the opening's quiet period ends on its own: a player who never finishes the arc is not muted forever

static func protected_time() -> bool:
	if not enabled() or Game.sandbox or Game.drill_active:
		return false
	if Game.cycle - int(Game.stats.get("customer_arc_cycle", 0)) > PROTECTED_CYCLES:
		return false
	return not complete() or Game.cycle <= int(state().get("quiet_until", -1))

static func path(deal: Dictionary) -> Array:
	if deal.is_empty():
		return []
	var routed := Game._deal_path_links(deal)
	if not routed.is_empty() or not enabled() or not bool(deal.get("guided", false)):
		return routed  # the access-lead fallback is the guided deal's; other customers keep the old accounting
	# Local hosting has no default route. Its access lead still has a finite
	# capacity, and is a real dependency even while that port is disabled.
	var host := Contracts._owner(String(deal.get("params", {}).get("ip", "")))
	var result: Array = []
	if host != null:
		for iface: Net.Iface in host.ifaces:
			var cable := Game.link_at(iface)
			if cable != null and cable not in result:
				result.append(cable)
	return result

static func forecast() -> Dictionary:
	var deal := Game.guided_customer_deal()
	var capacity := 0
	var background := 0
	var bottleneck := "No service path yet"
	for cable: Net.Link in path(deal):
		var cap := Game.link_capacity(cable)
		var other_load := 0
		for other: Dictionary in Game.deals:
			if other.get("id", "") != deal.get("id", "") and cable in path(other):
				other_load += int(ceil(float(other.get("load", 200)) * Game.peak_factor()))
		if capacity == 0 or cap - other_load < capacity - background:
			capacity = cap
			background = other_load
			bottleneck = "%s %s / %s %s" % [cable.a.dev.name, cable.a.name, cable.b.dev.name, cable.b.name]
	return {"capacity": capacity, "background": background,
		"headroom": maxi(0, capacity - background), "bottleneck": bottleneck}

static func choose(plan: String) -> String:
	var arc := state()
	if String(arc.get("phase", "")) != "planning" or not PLANS.has(plan):
		return Loc.t("arc.choose_when_invited")
	var spec: Dictionary = PLANS[plan]
	if not Game.try_spend(int(spec["fee"])):
		return Loc.t("arc.reservation_costs") % int(spec["fee"])
	arc["plan"] = plan
	arc["phase"] = "countdown"
	arc["starts"] = Game.cycle + 4
	arc["samples"] = []
	arc["before"] = forecast()
	Game.log_event("SALE NIGHT: Kiskacsa chose %s. Four cycles to prepare; peak demand %d Mbps." % [spec["name"], spec["demand"][1]])
	Game.topology_changed.emit()
	return ""

static func demand(deal: Dictionary, normal: int) -> int:
	if not active() or not bool(deal.get("guided", false)):
		return normal
	var arc := state()
	var step := Game.cycle - int(arc.get("starts", -100))
	if String(arc.get("phase", "")) not in ["countdown", "live"] or step < 0 or step >= 3:
		return normal
	return int(PLANS[String(arc["plan"])]["demand"][step])

static func tick() -> void:
	if not enabled() or Game.drill_active or Game.sandbox:
		return
	var arc := state()
	var deal := Game.guided_customer_deal()
	if arc.is_empty():
		if int(Game.stats.get("guided_outage_complete", 0)) == 0 or deal.is_empty():
			return
		Game.customer_arcs["sale_night"] = {"phase": "planning", "invited": Game.cycle}
		Game.log_event("KISKACSA: The checkout is back. We are planning our first big sale. Will you help us choose how to launch?")
		Game.topology_changed.emit()
		return
	if String(arc.get("phase", "")) not in ["countdown", "live"]:
		return
	var step := Game.cycle - int(arc["starts"])
	if step < 0 or int(arc.get("sampled_cycle", -1)) == Game.cycle:
		return
	arc["phase"] = "live"
	arc["sampled_cycle"] = Game.cycle
	while arc["samples"].size() < mini(step, 3):
		# a save loaded past a wave: the missed waves count as missed, not as never happened
		arc["samples"].append({"cycle": int(arc["starts"]) + arc["samples"].size(), "served": false,
			"reason": "Nobody was watching", "headroom": 0, "bottleneck": ""})
	if arc["samples"].size() >= 3:
		step = 2  # the window is full: close on this sample
	var healthy := not deal.is_empty() and bool(deal.get("healthy", false))
	var good := healthy and not bool(deal.get("degraded", false))
	var f := forecast()
	arc["samples"].append({"cycle": Game.cycle, "served": good,
		"reason": "Orders moving" if good else ("Checkout unavailable" if not healthy else "Shared link congested"),
		"headroom": f["headroom"], "bottleneck": f["bottleneck"]})
	if step >= 2 and arc["samples"].size() >= 3:
		var successes := 0
		for sample: Dictionary in arc["samples"]:
			if bool(sample["served"]): successes += 1
		arc["phase"] = "debrief"
		arc["successes"] = successes
		arc["bonus"] = int(PLANS[String(arc["plan"])]["bonus"]) if successes == 3 else 0
		if int(arc["bonus"]) > 0:
			Game.earn_on("Kiskacsa sale bonus", int(arc["bonus"]))
			deal["peaks_carried"] = int(deal.get("peaks_carried", 0)) + 1
		Game.log_event("SALE FINISHED: Kiskacsa carried %d of 3 waves at full service. Bonus $%d. Review the service timeline." % [successes, arc["bonus"]])
	Game.topology_changed.emit()

static func acknowledge() -> void:
	var arc := state()
	if String(arc.get("phase", "")) != "debrief": return
	arc["phase"] = "complete"
	arc["quiet_until"] = Game.cycle + 3
	Game.topology_changed.emit()

static func focus_devices(deal: Dictionary) -> Array:
	var result: Array = []
	var host := Contracts._owner(String(deal.get("params", {}).get("ip", "")))
	if host != null: result.append(host)
	for cable: Net.Link in path(deal):
		for dev: Net.NDevice in [cable.a.dev, cable.b.dev]:
			if dev not in result: result.append(dev)
	return result
