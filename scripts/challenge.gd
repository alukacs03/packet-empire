class_name Challenge
## A drill anybody can reproduce from a short code, scored so that careful
## diagnosis beats typing quickly. No servers, no accounts: the code is the
## whole payload, and it contains nothing about the player's own save.

const VERSION := 1
static var active := {}   # {code, started_cycle, changes, hints, seed, faults, difficulty}
static var best_path := "user://challenge_best.json"

static func encode(faults: int, difficulty: int, seed_value: int) -> String:
	## PE<version>-<faults><difficulty>-<seed in base 36>. Short enough to read
	## out over the phone, and it round-trips exactly.
	var body := "%d%d" % [clampi(faults, 1, 9), clampi(difficulty, 0, 2)]
	return "PE%d-%s-%s" % [VERSION, body, _base36(maxi(0, seed_value))]

static func _base36(n: int) -> String:
	const DIGITS := "0123456789abcdefghijklmnopqrstuvwxyz"
	if n == 0:
		return "0"
	var out := ""
	while n > 0:
		out = DIGITS[n % 36] + out
		n /= 36
	return out

static func _from36(text: String) -> int:
	const DIGITS := "0123456789abcdefghijklmnopqrstuvwxyz"
	var n := 0
	for c in text.to_lower():
		var idx := DIGITS.find(c)
		if idx < 0:
			return -1
		n = n * 36 + idx
	return n

static func parse(code: String) -> Dictionary:
	## Returns {ok, why} on failure so the interface can say what is wrong
	## rather than shrugging.
	var parts := code.strip_edges().to_lower().split("-")
	if parts.size() != 3 or not String(parts[0]).begins_with("pe"):
		return {"ok": false, "why": "that is not a challenge code"}
	var version := int(String(parts[0]).substr(2))
	if version != VERSION:
		return {"ok": false, "why": "that code is from content version %d; this build reads version %d"
			% [version, VERSION], "incompatible": true}
	if String(parts[1]).length() != 2 or not String(parts[1]).is_valid_int():
		return {"ok": false, "why": "the difficulty and fault count are unreadable"}
	var seed_value := _from36(String(parts[2]))
	if seed_value < 0:
		return {"ok": false, "why": "the seed is unreadable"}
	return {"ok": true, "faults": int(String(parts[1]).substr(0, 1)),
		"difficulty": int(String(parts[1]).substr(1, 1)), "seed": seed_value}

static func daily_code() -> String:
	## One featured challenge a day, from UTC, so two people on the same day
	## get the same one without anybody running a server.
	var day := int(Time.get_unix_time_from_system() / 86400.0)
	return encode(3, 1, day % 100000)

static func start(code: String) -> String:
	var spec := parse(code)
	if not bool(spec.get("ok", false)):
		return String(spec["why"])
	if Game.drill_active:
		return "a drill is already running"
	Drill.start(int(spec["faults"]), int(spec["seed"]))
	active = {"code": code.strip_edges().to_upper(), "started_cycle": Game.cycle,
		"changes": 0, "hints": 0, "seed": int(spec["seed"]), "faults": int(spec["faults"]),
		"difficulty": int(spec["difficulty"])}
	Game.log_event("CHALLENGE %s: %d fault(s) in a network you have never seen." % [active["code"],
		int(spec["faults"])])
	return ""

static func note_change() -> void:
	## Every configuration change is counted, which is what stops a spray of
	## commands scoring as well as a diagnosis.
	if not active.is_empty():
		active["changes"] = int(active["changes"]) + 1

static func note_hint() -> void:
	if not active.is_empty():
		active["hints"] = int(active["hints"]) + 1

static func collateral() -> int:
	## Anything left administratively down that the challenge did not break.
	var count := 0
	for l: Net.Link in Game.links:
		for i: Net.Iface in [l.a, l.b]:
			if not i.enabled:
				count += 1
	return maxi(0, count - int(active.get("faults", 0)))

static func score() -> Dictionary:
	## Categories are shown separately so a player can see where they lost it.
	if active.is_empty():
		return {}
	var solved := Drill.solved()
	var elapsed := maxi(0, Game.cycle - int(active["started_cycle"]))
	var change_penalty := maxi(0, int(active["changes"]) - int(active["faults"])) * 25
	var categories := {
		"recovery": 600 if solved else 0,
		"time": maxi(0, 200 - elapsed * 20),
		"changes": maxi(0, 200 - change_penalty),
		"hints": maxi(0, 100 - int(active["hints"]) * 50),
		"collateral": maxi(0, 100 - collateral() * 50),
	}
	var total := 0
	for k: String in categories:
		total += int(categories[k])
	return {"code": active["code"], "total": total, "categories": categories, "solved": solved,
		"elapsed": elapsed, "changes": int(active["changes"]), "hints": int(active["hints"]),
		"collateral": collateral()}

static func personal_best(code: String) -> int:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(best_path)) \
		if FileAccess.file_exists(best_path) else null
	if not (data is Dictionary):
		return 0
	return int((data as Dictionary).get(code, 0))

static func finish() -> Dictionary:
	## Ends the drill, keeps the best score for this code, and hands back the
	## card. Nothing here contains a file path or anything about the save.
	if active.is_empty():
		return {}
	var result := score()
	var data: Dictionary = {}
	if FileAccess.file_exists(best_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(best_path))
		if parsed is Dictionary:
			data = parsed
	var code := String(result["code"])
	result["previous_best"] = int(data.get(code, 0))
	if int(result["total"]) > int(data.get(code, 0)):
		data[code] = int(result["total"])
		var f := FileAccess.open(best_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(data))
	Drill.finish(bool(result["solved"]))
	active = {}
	return result

static func card(result: Dictionary) -> Array:
	## The shareable result, as plain text lines anybody can read or paste.
	if result.is_empty():
		return []
	var lines: Array = [
		"PACKET EMPIRE  ·  CHALLENGE %s" % result["code"],
		"%s in %d cycle(s)" % ["SOLVED" if bool(result["solved"]) else "NOT SOLVED",
			int(result["elapsed"])],
		"score %d   (best here: %d)" % [int(result["total"]), int(result["previous_best"])],
	]
	for k: String in result["categories"]:
		lines.append("  %-11s %d" % [k, int(result["categories"][k])])
	lines.append("Same code, same network: PE%d builds only match PE%d codes." % [VERSION, VERSION])
	return lines
