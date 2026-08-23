class_name Staff
## Hireable people. They cost a salary every cycle and, in exchange, handle
## the routine work the player would otherwise do by hand: restoring tripped
## links, saving configurations, and responding to incidents.

const FIRST := ["Anna", "Bence", "Csaba", "Dora", "Eszter", "Ferenc", "Gabor",
	"Hanna", "Istvan", "Julia", "Karoly", "Laszlo", "Marta", "Nora", "Peter", "Zsofia"]
const LAST := ["Kovacs", "Szabo", "Toth", "Varga", "Nagy", "Molnar", "Farkas",
	"Balogh", "Lukacs", "Fekete", "Racz", "Orban"]

const ROLES := {
	"noc": {"label": "NOC operator", "base": 260,
		"blurb": "Watches the network and restores tripped links."},
	"engineer": {"label": "Network engineer", "base": 420,
		"blurb": "Fixes faults faster and keeps configurations saved."},
	"tech": {"label": "Field technician", "base": 300,
		"blurb": "Repairs cabling and swaps failed hardware quickly."},
}

static func random_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [LAST[rng.randi() % LAST.size()], FIRST[rng.randi() % FIRST.size()]]

static func make_candidate(rng: RandomNumberGenerator) -> Dictionary:
	var role: String = ROLES.keys()[rng.randi() % ROLES.size()]
	var skill := rng.randi_range(1, 5)
	var base: int = int(ROLES[role]["base"])
	# better people cost more, and everyone has an opinion about their worth
	var ask := int(base * (0.7 + 0.18 * skill) * rng.randf_range(0.9, 1.15))
	return {"name": random_name(rng), "role": role, "skill": skill, "salary": ask,
		"morale": 70, "hired_cycle": 0}

static func label(member: Dictionary) -> String:
	return ROLES[member["role"]]["label"]

static func payroll() -> int:
	var total := 0
	for m in Game.staff:
		total += int(m["salary"])
	return total

## How many repairs the team can attempt in one cycle, and how good they are.
static func repair_power() -> Array:
	var attempts := 0
	var skill := 0
	for m in Game.staff:
		if m["role"] in ["noc", "tech", "engineer"]:
			attempts += 1
			skill = maxi(skill, int(m["skill"]))
	return [attempts, skill]

static func has_role(role: String, min_skill := 1) -> bool:
	for m in Game.staff:
		if m["role"] == role and int(m["skill"]) >= min_skill:
			return true
	return false

static func best_of(role: String) -> Dictionary:
	var best := {}
	for m in Game.staff:
		if m["role"] == role and (best.is_empty() or int(m["skill"]) > int(best["skill"])):
			best = m
	return best

## Called once per revenue cycle: the team works the queue.
static func work_cycle() -> void:
	var power := repair_power()
	var attempts: int = power[0]
	var skill: int = power[1]
	if attempts == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# 1. bring back links that are administratively down but cabled
	for l in Game.links:
		if attempts <= 0:
			break
		for ifc in [l.a, l.b]:
			if ifc.enabled or ifc.name.begins_with("Management"):
				continue
			if rng.randf() > 0.35 + 0.13 * skill:
				continue  # not everything gets fixed in one cycle
			ifc.enabled = true
			attempts -= 1
			var who: Dictionary = Game.staff[rng.randi() % Game.staff.size()]
			Game.log_event("STAFF: %s restored %s %s." % [who["name"], ifc.dev.name, ifc.name])
			Game.topology_changed.emit()
			break
	# 2. an engineer keeps configurations saved, which is what saves you at 3am
	var eng := best_of("engineer")
	if not eng.is_empty():
		for d in Game.all_devices():
			if Game.config_dirty(d) and rng.randf() < 0.4 + 0.12 * int(eng["skill"]):
				d.startup = Game.device_config(d)
				Game.save_config_version(d)
				Game.log_event("STAFF: %s saved the configuration on %s." % [eng["name"], d.name])
				break
