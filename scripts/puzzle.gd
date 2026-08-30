class_name Puzzle
## Hand somebody your actual mess. An export is the live topology, the configs
## and the customer-facing symptom, with the money, the story and the company
## stripped out: a paste-sized text file, no server and no account. Importing
## one opens a scratch session where nothing the recipient does can cost
## anything, and the fix they arrive at travels back the same way.

const VERSION := 1
const FRAMINGS := {
	"solve": "Solve this: the customer says it is broken and I want to see if you find it.",
	"review": "Look at this and tell me what I am missing. I have been staring at it too long.",
}

static var _home := ""       # the player's real world, while a puzzle is loaded
static var loaded := {}       # the puzzle currently open in the scratch session
static var _before := {}      # port state at import, so the fix can be described

static func active() -> bool:
	return not loaded.is_empty()

static func symptom() -> String:
	## What the customer would say, taken from live delivery rather than from
	## whatever the exporter believes is wrong.
	for deal: Dictionary in Game.deals:
		if bool(deal.get("ever_healthy", false)) and not bool(deal.get("healthy", false)):
			var eye := Game.customer_eye(deal)
			return "%s: %s" % [deal["customer"], eye.get("activity", "their service is down")]
	for m: Dictionary in Game.monitors:
		if bool(m.get("failing", false)):
			return "monitor '%s' has been failing since before I started looking" % m.get("label", m.get("target", "check"))
	return "nothing is formally down; it just does not feel right"

static func export_state(framing := "solve", blind := false) -> String:
	## Everything needed to reproduce the fault, and nothing about the company.
	var world: Dictionary = JSON.parse_string(Game.snapshot())
	var payload := {
		"puzzle": VERSION,
		"framing": framing if FRAMINGS.has(framing) else "solve",
		"note": FRAMINGS.get(framing, FRAMINGS["solve"]),
		"symptom": symptom(),
		"cycle": Game.cycle,
		"sites": world.get("sites", []),
		"racks": world.get("racks", []),
		"devices": world.get("devices", {}),
		"links": world.get("links", []),
		"monitors": world.get("monitors", []),
		"blind": blind,
	}
	if blind:
		# an extra fault neither of you has seen, so both are troubleshooting
		payload["devices"] = _blind_fault(payload["devices"])
	return JSON.stringify(payload)

static func _blind_fault(devices: Dictionary) -> Dictionary:
	## devices is name -> serialized device, as the save writes it
	for name: String in devices:
		var dev: Dictionary = devices[name]
		for iface: Dictionary in dev.get("ifaces", []):
			if bool(iface.get("enabled", true)) and not String(iface.get("name", "")).begins_with("Management"):
				iface["enabled"] = false
				return devices
	return devices

static func import_state(text: String) -> String:
	## Open it in a scratch session. The player's own world is put aside whole.
	if active():
		return "close the puzzle you already have open first"
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary) or not (data as Dictionary).has("puzzle"):
		return "that is not a puzzle export"
	if int(data.get("puzzle", 0)) != VERSION:
		return "that puzzle was made by a different version of the game"
	_home = Game.snapshot()
	var world: Dictionary = JSON.parse_string(_home)
	for key: String in ["sites", "racks", "devices", "links", "monitors"]:
		world[key] = data.get(key, [])
	world["deals"] = []
	world["offers"] = []
	world["leads"] = []
	world["invoices"] = []
	world["events"] = []
	world["sandbox"] = true  # nothing here costs anything, and nothing breaks on its own
	Game.restore(JSON.stringify(world))
	loaded = data
	_before = _port_state()
	Game.log_event("PUZZLE: %s" % data.get("note", ""))
	Game.log_event("PUZZLE SYMPTOM: %s" % data.get("symptom", ""))
	Game.topology_changed.emit()
	return ""

static func _port_state() -> Dictionary:
	var out := {}
	for d: Net.NDevice in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			out["%s|%s" % [d.name, i.name]] = i.enabled
	return out

static func solution(note := "") -> String:
	## What the recipient actually changed, so the answer travels back as an
	## answer rather than a smug message.
	if not active():
		return ""
	var changed: Array = []
	var now := _port_state()
	for key: String in now:
		if _before.has(key) and bool(_before[key]) != bool(now[key]):
			changed.append("%s is now %s" % [key.replace("|", " "),
				"up" if bool(now[key]) else "shut down"])
	for d: Net.NDevice in Game.all_devices():
		if Game.config_dirty(d):
			changed.append("%s has a changed running configuration" % d.name)
	return JSON.stringify({"puzzle_solution": VERSION, "symptom": loaded.get("symptom", ""),
		"changed": changed, "note": note})

static func read_solution(text: String) -> Array:
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary) or not data.has("puzzle_solution"):
		return []
	var lines: Array = data.get("changed", []).duplicate()
	if String(data.get("note", "")) != "":
		lines.append("they said: %s" % data["note"])
	return lines

static func close() -> void:
	if not active():
		return
	Game.restore(_home)
	_home = ""
	loaded = {}
	_before = {}
	Game.topology_changed.emit()
