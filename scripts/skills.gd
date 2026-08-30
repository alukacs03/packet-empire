class_name Skills
## Recognition, not a stat. When the player does a real piece of engineering,
## the game says once what that thing is called in the trade, and remembers it
## so the end of a run can describe what they actually got good at. Nothing
## here grants a bonus, and nothing here fires during an incident.

const RELIABLE := 3  # doing it once is a story; doing it three times is a claim

const CATALOG := [
	{"id": "service_delivery", "name": "service turn-up",
		"line": "You took a written requirement and made it answer on the wire. In the trade that is a service turn-up, and it is the whole job in miniature.",
		"pedia": "IP addresses & subnets",
		"claim": "turns a specification into a service that actually answers"},
	{"id": "l2_isolation", "name": "layer 2 segmentation",
		"line": "Two customers on one switch, and neither can see the other. That is layer 2 segmentation, and the isolation you just built is the real thing.",
		"pedia": "VLANs",
		"claim": "separates tenants properly at layer 2 instead of trusting them to behave"},
	{"id": "resilient_design", "name": "designing for failure",
		"line": "A link died and nobody noticed. That is what designing for failure looks like from the outside: nothing happens.",
		"pedia": "Spanning tree",
		"claim": "builds paths that survive losing one of them"},
	{"id": "bgp_peering", "name": "external routing",
		"line": "You brought up an eBGP session with somebody else's network. That is external routing, and it is how the internet is actually assembled.",
		"pedia": "Routing & gateways",
		"claim": "runs external routing sessions rather than pointing a default at somebody and hoping"},
	{"id": "incident_comms", "name": "incident communication",
		"line": "You told the customer what was happening while it was still happening. Incident communication is a skill, and it is the one operators are judged on.",
		"pedia": "Spanning tree",
		"claim": "communicates during an incident instead of going quiet"},
	{"id": "change_window", "name": "change control",
		"line": "You did the work inside a window you agreed first. That is change control, and it is the difference between an engineer and a liability.",
		"pedia": "Routing & gateways",
		"claim": "works inside agreed change windows"},
]

const FUMBLES := {
	"saved_configs": "has lost a running configuration to a reboot that had no startup config saved",
	"incident_comms": "has gone quiet through an outage that customers were watching",
	"change_control": "has made a change they were warned about with nothing in writing",
}

static func entry(id: String) -> Dictionary:
	for e: Dictionary in CATALOG:
		if String(e["id"]) == id:
			return e
	return {}

static func observe(id: String) -> void:
	## Called from the place the thing actually happened, never from a menu.
	if entry(id).is_empty():
		return
	var log_entry: Dictionary = Game.skill_log.get(id, {"count": 0, "first_cycle": Game.cycle,
		"said": false})
	log_entry["count"] = int(log_entry["count"]) + 1
	Game.skill_log[id] = log_entry
	if bool(log_entry.get("said", false)):
		return
	# never in the middle of an incident: it waits until the floor is quiet
	Game.pending_recognition.append(id)

static func fumble(id: String) -> void:
	if not FUMBLES.has(id):
		return
	Game.skill_fumbles[id] = int(Game.skill_fumbles.get(id, 0)) + 1

static func recognition_tick() -> void:
	if Game.pending_recognition.is_empty() or Game.outage_open() or Game.upstream_active():
		return
	var id: String = Game.pending_recognition.pop_front()
	var e := entry(id)
	if e.is_empty() or bool(Game.skill_log.get(id, {}).get("said", false)):
		return
	Game.skill_log[id]["said"] = true
	Game.log_event("LEARNED: %s  (Learn → \"%s\")" % [e["line"], e["pedia"]])

static func profile() -> Array:
	## How it would be said about an engineer, including the parts that did not
	## go well. Every line traces to something that happened.
	var lines: Array = []
	for e: Dictionary in CATALOG:
		var seen: Dictionary = Game.skill_log.get(String(e["id"]), {})
		var count := int(seen.get("count", 0))
		if count == 0:
			continue
		lines.append("%s %s (%d time%s, first at cycle %d)"
			% ["Reliably" if count >= RELIABLE else "Has once", e["claim"],
				count, "" if count == 1 else "s", int(seen.get("first_cycle", 0))])
	for id: String in Game.skill_fumbles:
		if FUMBLES.has(id):
			lines.append("Also %s (%d time%s)" % [FUMBLES[id], int(Game.skill_fumbles[id]),
				"" if int(Game.skill_fumbles[id]) == 1 else "s"])
	if lines.is_empty():
		lines.append("Nothing demonstrated yet. The profile fills in from work, not from time served.")
	return lines
