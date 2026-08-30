class_name Legacy
## What survives a company. A run that ends leaves an epitaph and a short list
## of things the player earned; the next run may carry two of them. It softens
## the opening. It never skips the game.

static var path := "user://legacy.json"  # tests point this somewhere harmless
const CARRY_LIMIT := 2

static var epitaph := {}       # the previous company: name, cycles, earned, why
static var offered: Array = []  # what was earned: [{id, kind, label, detail, data}]
static var selected: Array = []  # ids the player chose to carry into the next run

static func load_file() -> void:
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		return
	epitaph = data.get("epitaph", {})
	offered = data.get("offered", [])

static func save_file() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"epitaph": epitaph, "offered": offered}))

static func harvest(why: String) -> void:
	## Read the run that is ending for the few things worth keeping. Everything
	## here comes from what actually happened, including the consolation.
	if Game.demo or Game.cycle < 10:
		return
	epitaph = {"company": Game.company_name, "cycles": Game.cycle, "profile": Skills.profile(),
		"earned": int(Game.stats.get("earned", 0)), "reputation": Game.reputation,
		"deals": int(Game.stats.get("deals", 0)), "why": why}
	offered = []
	var best := {}
	for m: Dictionary in Game.staff:
		if best.is_empty() or int(m.get("skill", 0)) > int(best.get("skill", 0)):
			best = m
	if not best.is_empty():
		offered.append({"id": "colleague", "kind": "colleague",
			"label": "%s, %s" % [best["name"], Staff.label(best)],
			"detail": "Worked for you until the end. Skill %d, and as tired as you left them."
				% int(best.get("skill", 1)),
			"data": {"name": best["name"], "role": best["role"], "skill": int(best.get("skill", 1)),
				"salary": int(best.get("salary", 300)), "morale": mini(60, int(best.get("morale", 70))),
				"habits": Staff.habits_of(best).duplicate(true)}})
	if not Game.references.is_empty():
		var ref := String(Game.references[0])
		offered.append({"id": "reference", "kind": "reference", "label": ref,
			"detail": "They will follow you to the next company: a small contract early, and they will say so out loud.",
			"data": {"customer": ref}})
	if not Game.templates.is_empty() or not Game.blueprints.is_empty():
		offered.append({"id": "runbooks", "kind": "runbooks",
			"label": "Your runbooks (%d config template(s), %d rack layout(s))"
				% [Game.templates.size(), Game.blueprints.size()],
			"detail": "The documentation you actually wrote. It travels; the network it described does not.",
			"data": {"templates": Game.templates.duplicate(true),
				"blueprints": Game.blueprints.duplicate(true)}})
	if not Game.rivals.is_empty():
		var them: Dictionary = Game.rivals[0]
		var friendly := Game.reputation >= 55
		offered.append({"id": "rival", "kind": "rival",
			"label": "%s remembers you" % them["name"],
			"detail": ("They thought you ran it well and will bid softly against you."
				if friendly else "They watched you go under and will come at your customers harder."),
			"data": {"name": String(them["name"]), "friendly": friendly}})
	# Losing badly still leaves something: somebody thought you did right by
	# them under the circumstances.
	offered.append({"id": "lesson", "kind": "lesson", "label": "What the last one taught you",
		"detail": "Nothing material. A contact who vouches for you, and a shorter way to the same mistake.",
		"data": {"reputation": 3}})
	selected = []
	save_file()

static func carry_toggle(id: String) -> bool:
	if id in selected:
		selected.erase(id)
		return false
	if selected.size() >= CARRY_LIMIT:
		return false
	selected.append(id)
	return true

static func item(id: String) -> Dictionary:
	for entry: Dictionary in offered:
		if String(entry.get("id", "")) == id:
			return entry
	return {}

static func apply_carried() -> void:
	## Called on a fresh run, after the pristine state is restored.
	for id: String in selected:
		var entry := item(id)
		if entry.is_empty():
			continue
		var data: Dictionary = entry.get("data", {})
		match String(entry["kind"]):
			"colleague":
				var member := {"name": data["name"], "role": data["role"],
					"skill": int(data["skill"]), "salary": int(data["salary"]),
					"ask": int(data["salary"]), "morale": int(data["morale"]),
					"hired_cycle": 0, "shift": "day", "training_left": 0, "certs": [],
					"habits": data.get("habits", {})}
				Game.staff.append(member)
				Game.log_event("LEGACY: %s heard you were starting again and came back." % data["name"])
			"reference":
				Game.references.append(String(data["customer"]))
				Game.reputation = mini(100, Game.reputation + 5)
				Game.leads.append(Market.legacy_referral_lead(String(data["customer"])))
				Game.log_event("LEGACY: %s followed you here, and they are telling people."
					% data["customer"])
			"runbooks":
				Game.templates = data.get("templates", []).duplicate(true)
				Game.blueprints = data.get("blueprints", []).duplicate(true)
				Game.log_event("LEGACY: your runbooks came with you. The network they described did not.")
			"rival":
				for r in Game.rivals:
					if String(r["name"]) == String(data["name"]):
						r["remembers"] = "friend" if bool(data["friendly"]) else "grudge"
						# lower aggression means a cheaper bid, so a friend
						# leaves you room and a grudge undercuts you
						r["aggression"] = clampf(float(r.get("aggression", 1.0))
							+ (0.15 if bool(data["friendly"]) else -0.2), 0.4, 1.6)
						Game.log_event("LEGACY: %s remembers the last company, and %s."
							% [r["name"], "is inclined to be decent about it"
								if bool(data["friendly"]) else "is not being decent about it"])
						break
			"lesson":
				Game.reputation = mini(100, Game.reputation + int(data.get("reputation", 3)))
				Game.log_event("LEGACY: somebody from the last company vouched for you. That is what you left with.")
	selected = []
