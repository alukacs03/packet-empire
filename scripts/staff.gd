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
		"ask": ask, "morale": 70, "hired_cycle": 0, "shift": "day",
		"training_left": 0, "certs": []}

static func label(member: Dictionary) -> String:
	return ROLES[member["role"]]["label"]

## Shifts map onto the working day. Somebody has to be awake when it breaks,
## and the people who are awake at three in the morning cost more.
const SHIFTS := {
	"day": {"label": "Day", "slots": [2, 3, 4, 5], "premium": 1.0},
	"night": {"label": "Night", "slots": [6, 7, 0, 1], "premium": 1.35},
}

const COURSES := {
	"switching": {"label": "Switching and VLANs", "cost": 900, "cycles": 3, "role": "noc"},
	"routing": {"label": "Routing and BGP", "cost": 1600, "cycles": 4, "role": "engineer"},
	"hardware": {"label": "Hardware and cabling", "cost": 700, "cycles": 2, "role": "tech"},
}

static func shift_of(member: Dictionary) -> String:
	return String(member.get("shift", "day"))

static func on_shift(member: Dictionary) -> bool:
	## training takes them off the floor entirely
	if int(member.get("training_left", 0)) > 0:
		return false
	return Game.day_slot() in SHIFTS[shift_of(member)]["slots"]

static func anyone_on_shift() -> bool:
	for m in Game.staff:
		if on_shift(m):
			return true
	return false

static func market_rate(member: Dictionary) -> int:
	## what this person could get elsewhere, which is what they compare against
	var base: int = int(ROLES[member["role"]]["base"])
	var rate := int(base * (0.7 + 0.18 * int(member["skill"])))
	return int(rate * float(SHIFTS[shift_of(member)]["premium"]))

static func set_shift(member: Dictionary, shift: String) -> String:
	if shift not in SHIFTS:
		return "there is no such shift"
	var was := shift_of(member)
	member["shift"] = shift
	if was != shift and shift == "night":
		member["morale"] = maxi(0, int(member.get("morale", 70)) - 8)
		member["salary"] = maxi(int(member["salary"]), market_rate(member))
		Game.log_event("ROTA: %s moves to nights, at $%d/cycle." % [member["name"],
			int(member["salary"])])
	return ""

static func start_course(member: Dictionary, course: String) -> String:
	if course not in COURSES:
		return "no such course"
	var c: Dictionary = COURSES[course]
	if int(member.get("training_left", 0)) > 0:
		return "%s is already on a course" % member["name"]
	if int(member["skill"]) >= 5:
		return "%s has nothing left to learn here" % member["name"]
	if not Game.try_spend(int(c["cost"])):
		return "the course costs $%d" % int(c["cost"])
	member["training_left"] = int(c["cycles"])
	member["training"] = course
	member["morale"] = mini(100, int(member.get("morale", 70)) + 10)  # being invested in helps
	Game.log_event("TRAINING: %s starts %s. Off the floor for %d cycles."
		% [member["name"], c["label"], int(c["cycles"])])
	return ""

static func give_raise(member: Dictionary, amount: int) -> String:
	if amount <= 0:
		return "that is not a raise"
	member["salary"] = int(member["salary"]) + amount
	member["morale"] = mini(100, int(member.get("morale", 70)) + 12)
	Game.log_event("PAY: %s now earns $%d/cycle." % [member["name"], int(member["salary"])])
	return ""

static func morale_tick(incidents_this_cycle: int) -> void:
	## People wear out. Too much going wrong with too few of them, or being paid
	## less than they are worth, and eventually they hand in their notice.
	if Game.staff.is_empty():
		return
	var pressure := float(incidents_this_cycle) / float(Game.staff.size())
	for m in Game.staff.duplicate():
		if int(m.get("training_left", 0)) > 0:
			m["training_left"] = int(m["training_left"]) - 1
			if int(m["training_left"]) == 0:
				m["skill"] = mini(5, int(m["skill"]) + 1)
				m["certs"] = m.get("certs", []) + [String(m.get("training", ""))]
				Game.log_event("TRAINING: %s is back, now skill %d." % [m["name"], int(m["skill"])])
			continue
		var drift := 0
		if pressure > 1.5:
			drift -= 6
		elif pressure > 0.5:
			drift -= 2
		else:
			drift += 3
		if int(m["salary"]) < market_rate(m):
			drift -= 4  # they have noticed what the market pays
		if shift_of(m) == "night":
			drift -= 1
		if bool(m.get("shielded", false)):
			drift += 2  # somebody took it for them, and they remember
		if bool(m.get("cautious", false)):
			drift -= 2  # they are still waiting for the next one to land on them
		m["morale"] = clampi(int(m.get("morale", 70)) + drift, 0, 100)
		if int(m["morale"]) <= 12 and randf() < 0.35:
			Game.staff.erase(m)
			Game.reputation = maxi(0, Game.reputation - 1)
			Game.log_event("STAFF: %s has resigned. Morale was %d and the pay was %s."
				% [m["name"], int(m["morale"]),
				"below market" if int(m["salary"]) < market_rate(m) else "not the problem"])
		elif int(m["morale"]) <= 25:
			Game.log_event("STAFF: %s is close to walking out." % m["name"])

static func payroll() -> int:
	var total := 0
	for m in Game.staff:
		total += int(m["salary"])
	return total

## How many repairs the team can attempt in one cycle, and how good they are.
## Only the people actually on shift count, which is the entire point of a rota.
static func repair_power() -> Array:
	var attempts := 0
	var skill := 0
	for m in Game.staff:
		if m["role"] in ["noc", "tech", "engineer"] and on_shift(m):
			attempts += 1
			skill = maxi(skill, int(m["skill"]))
			if int(m.get("morale", 70)) < 30:
				attempts -= 1  # going through the motions
	return [maxi(0, attempts), skill]

static func has_role(role: String, min_skill := 1) -> bool:
	for m in Game.staff:
		if m["role"] == role and int(m["skill"]) >= min_skill and on_shift(m):
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
	_maybe_slip(rng)
	# 2. an engineer keeps configurations saved, which is what saves you at 3am
	var eng := best_of("engineer")
	if not eng.is_empty():
		for d in Game.all_devices():
			if Game.config_dirty(d) and rng.randf() < 0.4 + 0.12 * int(eng["skill"]):
				d.startup = Game.device_config(d)
				Game.save_config_version(d)
				Game.log_event("STAFF: %s saved the configuration on %s." % [eng["name"], d.name])
				break

static func _maybe_slip(rng: RandomNumberGenerator) -> void:
	## People break things. A team that fears blame breaks them just as often
	## and says so later, which is the expensive part.
	var pool: Array = Game.staff.filter(func(m: Dictionary) -> bool: return on_shift(m))
	if pool.is_empty():
		return
	var who: Dictionary = pool[rng.randi() % pool.size()]
	var risk := 0.02 + 0.008 * float(5 - int(who.get("skill", 3)))
	if int(who.get("morale", 70)) < 40:
		risk += 0.03
	if rng.randf() > risk:
		return
	var live: Array = []
	for l in Game.links:
		for i in [l.a, l.b]:
			if i.enabled and not i.name.begins_with("Management"):
				live.append(i)
	if live.is_empty():
		return
	var victim: Net.Iface = live[rng.randi() % live.size()]
	victim.enabled = false
	Game.device_log(victim.dev, "%s changed state to down (configuration change)" % victim.name)
	Game.stats["faults"] = int(Game.stats.get("faults", 0)) + 1
	var delay: int = Game.blame_fear + (2 if bool(who.get("cautious", false)) else 0)
	Game.report_incident("human",
		"%s took %s %s down while working on it" % [who["name"], victim.dev.name, victim.name],
		String(who["name"]),
		"HANDS: %s took %s %s down during a change." % [who["name"], victim.dev.name, victim.name],
		delay)
	Game.topology_changed.emit()
