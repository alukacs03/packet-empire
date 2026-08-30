class_name Pack
## Authored content as data, not code. A pack is a JSON file describing
## scenarios: what starts on the floor, what the player has to make true, and
## what happens when they do. Nothing in a pack is executed; every requirement
## is a predicate this file knows how to evaluate against the live simulation.

const SCHEMA_VERSION := 1
const USER_DIR := "user://packs"
const BUNDLED_DIR := "res://packs"
const MAX_PROBES := 40  # a pack cannot make the game hang by asking for the world

static var loaded: Array = []      # every pack that validated
static var problems: Array = []    # why the others did not
static var _probes := 0

## ---------- loading ----------

static func load_all() -> Array:
	loaded = []
	problems = []
	for dir_path: String in [BUNDLED_DIR, USER_DIR]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file: String in dir.get_files():
			if not file.ends_with(".json"):
				continue
			var path := "%s/%s" % [dir_path, file]
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not (parsed is Dictionary):
				problems.append("%s: not a JSON object" % path)
				continue
			var errors := validate(parsed)
			if errors.is_empty():
				var pack: Dictionary = parsed
				pack["source"] = path
				loaded.append(pack)
			else:
				for e: String in errors:
					problems.append("%s: %s" % [path, e])
	return loaded

## ---------- validation ----------

const REQUIRED_PACK := ["id", "name", "schema", "scenarios"]
const REQUIRED_SCENARIO := ["id", "title", "brief", "requirements"]

static func validate(pack: Dictionary) -> Array:
	## Actionable errors with the field path, so an author can fix the file
	## rather than guess. Unknown fields are preserved, never rejected.
	var errors: Array = []
	for key: String in REQUIRED_PACK:
		if not pack.has(key):
			errors.append("missing field '%s'" % key)
	if errors.size() > 0:
		return errors
	if int(pack.get("schema", 0)) != SCHEMA_VERSION:
		return ["schema is version %s; this build reads version %d"
			% [pack.get("schema", "?"), SCHEMA_VERSION]]
	if not (pack["scenarios"] is Array) or (pack["scenarios"] as Array).is_empty():
		return ["'scenarios' must be a non-empty list"]
	var seen := {}
	for idx in (pack["scenarios"] as Array).size():
		var scenario = pack["scenarios"][idx]
		var where := "scenarios[%d]" % idx
		if not (scenario is Dictionary):
			errors.append("%s: not an object" % where)
			continue
		for key2: String in REQUIRED_SCENARIO:
			if not (scenario as Dictionary).has(key2):
				errors.append("%s: missing field '%s'" % [where, key2])
		var sid := "%s.%s" % [pack["id"], scenario.get("id", "?")]
		if seen.has(sid):
			errors.append("%s: duplicate scenario id '%s'" % [where, sid])
		seen[sid] = true
		if scenario.has("requirements"):
			if not (scenario["requirements"] is Array):
				errors.append("%s.requirements: must be a list" % where)
			else:
				for ridx in (scenario["requirements"] as Array).size():
					errors.append_array(_validate_predicate(scenario["requirements"][ridx],
						"%s.requirements[%d]" % [where, ridx]))
		for action_field: String in ["setup", "on_complete"]:
			if scenario.has(action_field):
				if not (scenario[action_field] is Array):
					errors.append("%s.%s: must be a list" % [where, action_field])
					continue
				for aidx in (scenario[action_field] as Array).size():
					errors.append_array(_validate_action(scenario[action_field][aidx],
						"%s.%s[%d]" % [where, action_field, aidx]))
	return errors

const PREDICATES := ["all", "any", "not", "device_count", "link_between", "reachable",
	"not_reachable", "has_address", "vlan_access", "config_saved", "money_at_least",
	"survives_link_loss"]

static func _validate_predicate(pred: Variant, where: String) -> Array:
	if not (pred is Dictionary):
		return ["%s: not an object" % where]
	var kind := String((pred as Dictionary).get("kind", ""))
	if kind not in PREDICATES:
		return ["%s: unknown requirement kind '%s'" % [where, kind]]
	var errors: Array = []
	match kind:
		"all", "any", "not":
			if not (pred.get("of") is Array):
				errors.append("%s: '%s' needs a list in 'of'" % [where, kind])
			else:
				for i in (pred["of"] as Array).size():
					errors.append_array(_validate_predicate(pred["of"][i], "%s.of[%d]" % [where, i]))
		"reachable", "not_reachable":
			for field: String in ["from", "to"]:
				if not _is_address(String(pred.get(field, ""))):
					errors.append("%s.%s: '%s' is not an address" % [where, field,
						pred.get(field, "")])
		"has_address":
			if not _is_address(String(pred.get("ip", ""))):
				errors.append("%s.ip: '%s' is not an address" % [where, pred.get("ip", "")])
		"vlan_access":
			var vid := int(pred.get("vid", 0))
			if vid < 1 or vid > 4094:
				errors.append("%s.vid: %d is not a VLAN id" % [where, vid])
		"device_count":
			if String(pred.get("type", "")) == "":
				errors.append("%s.type: name a device type" % where)
		"link_between", "survives_link_loss":
			for field2: String in ["a", "b"]:
				if String(pred.get(field2, "")) == "":
					errors.append("%s.%s: name a device" % [where, field2])
		"config_saved":
			if String(pred.get("device", "")) == "":
				errors.append("%s.device: name a device" % where)
		"money_at_least":
			if not (pred.get("amount") is float or pred.get("amount") is int):
				errors.append("%s.amount: needs a number" % where)
	return errors

const ACTIONS := ["message", "reward", "break_link", "restore_links"]

static func _validate_action(action: Variant, where: String) -> Array:
	if not (action is Dictionary):
		return ["%s: not an object" % where]
	var kind := String((action as Dictionary).get("kind", ""))
	if kind not in ACTIONS:
		return ["%s: unknown action '%s'" % [where, kind]]
	if kind == "message" and String(action.get("text", "")) == "":
		return ["%s.text: say something" % where]
	if kind == "reward" and not (action.get("amount") is float or action.get("amount") is int):
		return ["%s.amount: needs a number" % where]
	if kind in ["break_link", "restore_links"] and kind == "break_link" \
			and String(action.get("device", "")) == "":
		return ["%s.device: name a device" % where]
	return []

static func _is_address(text: String) -> bool:
	return text.is_valid_ip_address()

## ---------- evaluation ----------

static func evaluate(pred: Dictionary) -> Dictionary:
	## Returns {ok, why} so a checklist can say what is missing rather than
	## just going red.
	_probes = 0
	return _eval(pred)

static func _eval(pred: Dictionary) -> Dictionary:
	if _probes > MAX_PROBES:
		return {"ok": false, "why": "this requirement asked too much of the simulation"}
	_probes += 1
	match String(pred.get("kind", "")):
		"all":
			for sub in pred["of"]:
				var r := _eval(sub)
				if not bool(r["ok"]):
					return r
			return {"ok": true, "why": ""}
		"any":
			var reasons: Array = []
			for sub2 in pred["of"]:
				var r2 := _eval(sub2)
				if bool(r2["ok"]):
					return r2
				reasons.append(String(r2["why"]))
			return {"ok": false, "why": "none of: %s" % "; ".join(PackedStringArray(reasons))}
		"not":
			var inner := _eval(pred["of"][0])
			return {"ok": not bool(inner["ok"]),
				"why": "" if not bool(inner["ok"]) else "that is true and should not be"}
		"device_count":
			var want := int(pred.get("min", 1))
			var have := 0
			for d: Net.NDevice in Game.all_devices():
				if d.type == String(pred["type"]) or d.model == String(pred["type"]):
					have += 1
			return {"ok": have >= want,
				"why": "" if have >= want else "%d of %d %s(s) installed" % [have, want, pred["type"]]}
		"link_between":
			var a := _device(String(pred["a"]))
			var b := _device(String(pred["b"]))
			if a == null or b == null:
				return {"ok": false, "why": "both devices have to exist first"}
			for i: Net.Iface in a.ifaces:
				var peer := Game.effective_peer(i)
				if peer != null and peer.dev == b:
					return {"ok": true, "why": ""}
			return {"ok": false, "why": "%s is not cabled to %s" % [pred["a"], pred["b"]]}
		"reachable", "not_reachable":
			var want_ok := String(pred["kind"]) == "reachable"
			var src := Contracts._owner(String(pred["from"]))
			if src == null:
				return {"ok": false, "why": "nothing owns %s yet" % pred["from"]}
			var got: bool = Sim.ping(src, String(pred["to"]))["ok"]
			return {"ok": got == want_ok, "why": "" if got == want_ok
				else ("%s cannot reach %s" % [pred["from"], pred["to"]] if want_ok
					else "%s can reach %s and should not" % [pred["from"], pred["to"]])}
		"has_address":
			var owner := Contracts._owner(String(pred["ip"]))
			return {"ok": owner != null,
				"why": "" if owner != null else "nothing is addressed %s" % pred["ip"]}
		"vlan_access":
			var vid := int(pred["vid"])
			for d2: Net.NDevice in Game.all_devices():
				if d2.type != "switch":
					continue
				for i2: Net.Iface in d2.ifaces:
					if i2.mode == "access" and int(i2.untagged_vlan) == vid \
							and Game.link_at(i2) != null:
						return {"ok": true, "why": ""}
			return {"ok": false, "why": "no connected access port in VLAN %d" % vid}
		"config_saved":
			var dev := _device(String(pred["device"]))
			if dev == null:
				return {"ok": false, "why": "%s does not exist" % pred["device"]}
			return {"ok": not Game.config_dirty(dev),
				"why": "" if not Game.config_dirty(dev) else "%s has unsaved configuration" % dev.name}
		"money_at_least":
			var amount := int(pred["amount"])
			return {"ok": Game.money >= amount,
				"why": "" if Game.money >= amount else "you have $%d of $%d" % [Game.money, amount]}
		"survives_link_loss":
			var a2 := _device(String(pred["a"]))
			var b2 := _device(String(pred["b"]))
			var probe_from := String(pred.get("from", ""))
			var probe_to := String(pred.get("to", ""))
			if a2 == null or b2 == null or not _is_address(probe_from) or not _is_address(probe_to):
				return {"ok": false, "why": "name two devices and a pair of addresses to prove it"}
			var src2 := Contracts._owner(probe_from)
			if src2 == null:
				return {"ok": false, "why": "nothing owns %s yet" % probe_from}
			for i3: Net.Iface in a2.ifaces:
				var peer2 := Game.effective_peer(i3)
				if peer2 == null or peer2.dev != b2:
					continue
				var was := i3.enabled
				i3.enabled = false
				Sim.flush_learned_state()
				var still: bool = Sim.ping(src2, probe_to)["ok"]
				i3.enabled = was
				Sim.flush_learned_state()
				return {"ok": still, "why": "" if still
					else "%s stops reaching %s when that link goes" % [probe_from, probe_to]}
			return {"ok": false, "why": "%s and %s are not cabled together" % [pred["a"], pred["b"]]}
	return {"ok": false, "why": "unknown requirement"}

static func _device(name: String) -> Net.NDevice:
	for d: Net.NDevice in Game.all_devices():
		if d.name == name:
			return d
	return null

static func describe(pred: Dictionary) -> String:
	## A readable line for the checklist, built from the data itself.
	match String(pred.get("kind", "")):
		"all":
			var parts: Array = []
			for sub in pred["of"]:
				parts.append(describe(sub))
			return " and ".join(PackedStringArray(parts))
		"any":
			var parts2: Array = []
			for sub2 in pred["of"]:
				parts2.append(describe(sub2))
			return "either " + " or ".join(PackedStringArray(parts2))
		"not":
			return "not (%s)" % describe(pred["of"][0])
		"device_count":
			return "%d × %s installed" % [int(pred.get("min", 1)), pred.get("type", "device")]
		"link_between":
			return "%s cabled to %s" % [pred.get("a", ""), pred.get("b", "")]
		"reachable":
			return "%s reaches %s" % [pred.get("from", ""), pred.get("to", "")]
		"not_reachable":
			return "%s cannot reach %s" % [pred.get("from", ""), pred.get("to", "")]
		"has_address":
			return "something is addressed %s" % pred.get("ip", "")
		"vlan_access":
			return "a connected access port in VLAN %d" % int(pred.get("vid", 0))
		"config_saved":
			return "%s has its configuration saved" % pred.get("device", "")
		"money_at_least":
			return "at least $%d in the bank" % int(pred.get("amount", 0))
		"survives_link_loss":
			return "%s still reaches %s with the %s–%s link down" % [pred.get("from", ""),
				pred.get("to", ""), pred.get("a", ""), pred.get("b", "")]
	return "an unknown requirement"

## ---------- actions ----------

static func run_actions(actions: Array) -> Array:
	var done: Array = []
	for action in actions:
		if not (action is Dictionary):
			continue
		match String(action.get("kind", "")):
			"message":
				Game.log_event(String(action["text"]))
				done.append("message")
			"reward":
				Game.money += int(action["amount"])
				Game.money_changed.emit()
				done.append("reward")
			"break_link":
				var dev := _device(String(action.get("device", "")))
				if dev == null:
					continue
				for i: Net.Iface in dev.ifaces:
					if Game.link_at(i) != null and i.enabled \
							and (String(action.get("iface", "")) == "" or i.name == String(action["iface"])):
						i.enabled = false
						done.append("break_link")
						break
			"restore_links":
				for l: Net.Link in Game.links:
					l.a.enabled = true
					l.b.enabled = true
				done.append("restore_links")
	Game.topology_changed.emit()
	return done

## ---------- bridging into the campaign ----------

static func to_contract(pack: Dictionary, scenario: Dictionary) -> Dictionary:
	## An authored scenario looks exactly like a built-in contract to the rest
	## of the game, including the live checks.
	var reqs: Array = []
	for pred in scenario.get("requirements", []):
		reqs.append({"d": describe(pred), "t": func() -> bool: return bool(evaluate(pred)["ok"])})
	return {"id": "%s.%s" % [pack["id"], scenario["id"]], "title": scenario["title"],
		"customer": scenario.get("customer", pack.get("name", "an author")),
		"reward": int(scenario.get("reward", 500)), "brief": scenario["brief"],
		"hint": scenario.get("hint", ""), "reqs": reqs, "pack": pack["id"],
		"on_complete": scenario.get("on_complete", [])}

static func contracts() -> Array:
	var out: Array = []
	for pack: Dictionary in loaded:
		for scenario in pack["scenarios"]:
			out.append(to_contract(pack, scenario))
	return out

static func failure_reasons(scenario: Dictionary) -> Array:
	var out: Array = []
	for pred in scenario.get("requirements", []):
		var r := evaluate(pred)
		if not bool(r["ok"]):
			out.append(String(r["why"]))
	return out


## ---------- the workshop ----------

static func workshop_rows() -> Array:
	## What the interface shows: every pack found, whether it validated, and
	## what is in it.
	var rows: Array = []
	for pack: Dictionary in loaded:
		var scenarios: Array = []
		for scenario in pack["scenarios"]:
			scenarios.append("%s — %s" % [scenario["title"],
				"%d requirement(s)" % scenario.get("requirements", []).size()])
		rows.append({"id": pack["id"], "name": pack["name"], "ok": true,
			"author": pack.get("author", "unknown"), "source": pack.get("source", ""),
			"scenarios": scenarios,
			"detail": pack.get("description", "")})
	for problem: String in problems:
		rows.append({"id": problem.split(":")[0], "name": "(did not load)", "ok": false,
			"author": "", "source": problem.split(":")[0], "scenarios": [],
			"detail": problem})
	return rows

static func preview(pack: Dictionary, scenario: Dictionary) -> Array:
	## What a player is signing up for, before they start it.
	var lines: Array = ["%s  ·  %s" % [scenario["title"], pack.get("name", "")],
		String(scenario.get("brief", ""))]
	lines.append("Reward: $%d" % int(scenario.get("reward", 0)))
	lines.append("Roughly %d step(s):" % scenario.get("requirements", []).size())
	for pred in scenario.get("requirements", []):
		lines.append("  · %s" % describe(pred))
	if scenario.has("setup"):
		lines.append("Sets up: %d action(s) before you start" % (scenario["setup"] as Array).size())
	return lines

static func diagnostic_report() -> String:
	## Something an author can paste to whoever wrote the pack.
	var lines: Array = ["Packet Empire pack diagnostics (schema %d)" % SCHEMA_VERSION]
	for row: Dictionary in workshop_rows():
		lines.append("%s  %s  %s" % ["OK  " if bool(row["ok"]) else "FAIL", row["source"],
			row["name"]])
		if not bool(row["ok"]):
			lines.append("      %s" % row["detail"])
	if problems.is_empty():
		lines.append("Every pack found is valid.")
	return "\n".join(PackedStringArray(lines))

static func import_text(text: String, name := "imported") -> String:
	## Somebody pasted a pack. Validate it first, write it second, and never
	## execute anything in it.
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return "that is not a pack: it is not even JSON"
	var errors := validate(parsed)
	if not errors.is_empty():
		return "that pack is not valid: %s" % errors[0]
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var f := FileAccess.open("%s/%s.json" % [USER_DIR, name], FileAccess.WRITE)
	if f == null:
		return "could not write it into %s" % USER_DIR
	f.store_string(text)
	f = null
	load_all()
	return ""

static func share_text(pack: Dictionary) -> String:
	var copy := pack.duplicate(true)
	copy.erase("source")  # nothing about this machine goes with it
	return JSON.stringify(copy, "  ")
