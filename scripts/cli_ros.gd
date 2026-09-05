class_name ROS
extends CLI.Session
## MikroTik RouterOS 7-style CLI for PacketTik gear: /path add|set|remove|print
## with key=value parameters and [find key=value] selectors. Paths, parameter
## names, print shapes, the menu prompt and the error texts follow the real
## thing, so what is learned here is what a real CHR expects. Same Game state
## as everything else.

const BRIDGE := "bridge1"  # every PacketTik switch runs one VLAN-filtering bridge
const VERSION := "7.14.2"

var cwd := ""  # the menu the prompt is in: path words joined by spaces

func banner() -> String:
	return "PacketTik RouterOS 7 %s: try '/interface print', '/ping <ip>', '?'\n" % dev.name

func prompt() -> String:
	if cwd == "":
		return "[admin@%s] >" % dev.name
	return "[admin@%s] /%s>" % [dev.name, cwd.replace(" ", "/")]

func _params(toks: Array) -> Dictionary:
	var out := {}
	for t in toks:
		if "=" in String(t):
			var kv := String(t).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out

func _iface(name: String) -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if i.name == name or _dname(i) == name:
			return i
	return null

func _dname(i: Net.Iface) -> String:
	## RouterOS names a VLAN interface itself (vlan60, or whatever name= said);
	## the model names it after its parent (ether1.60). Print the RouterOS name.
	if i.parent != "":
		return String(dev.services.get("vlan_names", {}).get(str(i.dot1q), "vlan%d" % i.dot1q))
	return i.name

func _itype(i: Net.Iface) -> String:
	if i.parent != "":
		return "vlan"
	if i.name.begins_with("wg"):
		return "wg"
	return "ether"

func _bridge_member(i: Net.Iface) -> bool:
	return dev.type == "switch" and i.parent == "" and not i.name.begins_with("Management") \
		and not i.name.begins_with("wg")

func _vrrp_iface(name: String) -> Net.Iface:
	## vrrp1 is the interface carrying VRRP group 1
	if not (name.begins_with("vrrp") and name.trim_prefix("vrrp").is_valid_int()):
		return null
	var group := int(name.trim_prefix("vrrp"))
	for i: Net.Iface in dev.ifaces:
		if int(i.vrrp.get("group", -1)) == group:
			return i
	return null

func _target(args: Array, p: Dictionary) -> Net.Iface:
	## the port a command is about: interface=, a bare name, or its number
	for key in ["interface", "name", "default-name"]:
		if p.has(key) and _iface(String(p[key])) != null:
			return _iface(String(p[key]))
	for a in args:
		if _iface(String(a)) != null:
			return _iface(String(a))
		if String(a).is_valid_int() and int(a) >= 0 and int(a) < dev.ifaces.size():
			return dev.ifaces[int(a)]
	return null

static func _vids(spec: String) -> Array:
	## "10,20,30-32" -> [10, 20, 30, 31, 32]; empty on anything odd
	var out: Array = []
	for part in spec.split(",", false):
		if "-" in part:
			var ab := part.split("-")
			if ab.size() != 2 or not ab[0].is_valid_int() or not ab[1].is_valid_int():
				return []
			for v in range(int(ab[0]), int(ab[1]) + 1):
				out.append(v)
		elif part.is_valid_int():
			out.append(int(part))
		else:
			return []
	for v in out:
		if v < 1 or v > 4094:
			return []
	return out

func _sorted_vids() -> Array:
	var vids := dev.vlans.keys()
	vids.sort()
	return vids

func _tagged_ports(vid: int) -> Array:
	var out: Array = []
	for i: Net.Iface in dev.ifaces:
		if i.mode == "trunk" and (i.tagged_vlans.is_empty() or vid in i.tagged_vlans):
			out.append(i.name)
	return out

func _untagged_ports(vid: int) -> Array:
	var out: Array = []
	for i: Net.Iface in dev.ifaces:
		if i.untagged_vlan == vid and not i.name.begins_with("Management"):
			out.append(i.name)
	return out

func _apply_vlan_ports(vid: int, tagged: String, untagged: String) -> String:
	for nm in tagged.split(",", false):
		var i := _iface(nm)
		if i == null:
			return "input does not match any value of tagged\n"
		if i.mode != "trunk":
			i.mode = "trunk"
			i.tagged_vlans = [vid]  # a tagged port carries exactly what is listed
		elif not i.tagged_vlans.is_empty() and vid not in i.tagged_vlans:
			i.tagged_vlans.append(vid)
			i.tagged_vlans.sort()
	for nm in untagged.split(",", false):
		var i := _iface(nm)
		if i == null:
			return "input does not match any value of untagged\n"
		if i.mode == "trunk":
			i.untagged_vlan = vid  # a trunk's untagged VLAN is its pvid
		else:
			Game.set_access_vlan(i, vid)
	return ""

# ---------- the console itself ----------

static func _menu_word(s: String) -> bool:
	## "/ip/address" is a menu spelled the 7.x way; "10.0.0.0/24" is not
	if "=" in s or "/" not in s or "." in s or ":" in s:
		return false
	var letters := 0
	for ch in s:
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
			letters += 1
		elif not (ch == "/" or ch == "-" or (ch >= "0" and ch <= "9")):
			return false
	return letters > 0

func exec(line: String) -> String:
	var pipe := line.find("|")
	if pipe > 0:
		var tail := line.substr(pipe + 1).strip_edges().split(" ", false)
		if tail.size() >= 2 and String(tail[0]) in ["include", "i", "grep"]:
			return CLI.filter_output(exec(line.substr(0, pipe).strip_edges()),
				" ".join(PackedStringArray(Array(tail).slice(1))))
	var raw := line.strip_edges()
	if raw == "":
		return ""
	if raw == "..":
		var up := Array(cwd.split(" ", false))
		up.pop_back()
		cwd = " ".join(PackedStringArray(up))
		return ""
	if raw == "/":
		cwd = ""
		return ""
	var asking := raw.ends_with("?")
	if asking:
		raw = raw.trim_suffix("?").strip_edges()
	if raw == "":
		return _help_for(cwd, true)
	var absolute := raw.begins_with("/")
	var slashed := raw.trim_prefix("/").contains("/") and _menu_word(raw.split(" ", false)[0])
	# [find key=value] selects an item: the key=value is all the model needs;
	# a double-quoted value keeps its spaces and loses its quotes
	var words: Array = []
	for t in _tokens(raw.replace("[", " ").replace("]", " ")):
		var s := String(t)
		if _menu_word(s):
			for w in s.split("/", false):
				words.append(w)
		else:
			words.append(s)
	while words.has("find"):
		words.erase("find")
	if not absolute and cwd != "":
		words = Array(cwd.split(" ", false)) + words
	if words.is_empty():
		return ""
	var path := ""
	var args: Array = []
	for t in words:
		var word := String(t)
		if "=" in word or not args.is_empty():
			args.append(t)
			continue
		if _is_path_word(path + (" " if path != "" else "") + word):
			path += (" " if path != "" else "") + word
			continue
		# any unique prefix of a command word is the word, as on a real box
		var matches: Array = _children(path).filter(func(c): return String(c).begins_with(word))
		if matches.size() == 1:
			path += (" " if path != "" else "") + String(matches[0])
		elif matches.size() > 1 and not _is_path_word(path):
			return "ambiguous command name %s (line 1 column %d)\n" % [word, raw.find(word) + 1]
		else:
			args.append(t)
	if asking:
		return _help_for(path, args.is_empty())
	var p := _params(args)
	# a parameter the menu does not have is a syntax error at its column
	if PARAMS.has(path):
		for k in p:
			if String(k) not in PARAMS[path]:
				var err := "syntax error (line 1 column %d)\n" % (raw.find(String(k) + "=") + 1)
				var hint := String(HINTS.get(path, {}).get(String(k), ""))
				return err + ("# %s\n" % hint if hint != "" else "")
	var is_print := path.ends_with(" print") or path.ends_with(" print stats")
	var opts := {"detail": false, "where": {}, "count": false}
	if is_print:
		for a in args:
			var w := String(a)
			if "=" in w:
				continue
			match w:
				"detail", "brief", "terse":
					opts["detail"] = w == "detail"
				"where":
					opts["where"] = p
				"count-only":
					opts["count"] = true
				_:
					return "expected end of command (line 1 column %d)\n" % (raw.find(w) + 1)
	var out: Variant = _run(path, args, p)
	if out == null:
		var nexts := _next_words(path)
		if not nexts.is_empty():
			if args.is_empty():
				cwd = path  # a menu with nothing after it: step into it
				return ""
			for a in args:
				if "=" not in String(a):
					# the slash spelling says directory; the space spelling says command
					if slashed:
						return "no such command or directory (%s)\n" % a
					return "bad command name %s (line 1 column %d)\n" % [a, raw.find(String(a)) + 1]
			return "syntax error (line 1 column %d)\n" % (raw.find(String(args[0])) + 1)
		var first := String(words[0])
		if path != "" and _is_path_word(path):
			return "expected end of command (line 1 column %d)\n" % (raw.find(String(args[0])) + 1 if not args.is_empty() else raw.length())
		return "bad command name %s (line 1 column %d)\n" % [first, maxi(1, raw.find(first) + 1)]
	var text := String(out)
	if text == "no such item\n":
		for a in args:
			if String(a).is_valid_int():
				text = "no such item (%s)\n" % a
				break
	if is_print:
		if not (opts["where"] as Dictionary).is_empty():
			text = _where(text, opts["where"])
		if bool(opts["count"]):
			return "%d\n" % _rows_of(text).size()
		if bool(opts["detail"]):
			text = _detail(text)
	return text

static func _tokens(text: String) -> Array:
	## split on spaces, but a double-quoted stretch is one token without its quotes
	var out: Array = []
	var cur := ""
	var quoted := false
	for ch in text:
		if ch == "\"":
			quoted = not quoted
		elif ch == " " and not quoted:
			if cur != "":
				out.append(cur)
			cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out

func _children(path: String) -> Array:
	## the words that can follow a menu path (every first word at the root)
	var seen := {}
	for c in PATHS:
		if path == "":
			seen[String(c).split(" ")[0]] = true
		elif c.begins_with(path + " "):
			seen[String(c.substr(path.length() + 1)).split(" ")[0]] = true
	return seen.keys()

const VERB_DESC := {"add": "Create a new item", "disable": "Disable items", "edit": "Edit value of item", "enable": "Enable items",
	"export": "Print or save an export script that can be used to restore configuration", "find": "Find items by value",
	"get": "Gets value of item's property", "print": "Print values of item properties", "remove": "Remove item", "set": "Change item properties",
	"monitor": "Monitor interface status", "reboot": "Reboot the router", "save": "Save the configuration", "load": "Load the configuration",
	"ping": "Send ICMP Echo packets", "traceroute": "Trace route to a host", "torch": "Realtime traffic monitor", "sniffer": "Packet sniffer",
	"stats": "Interface statistics", "detail": "Show details", "quick": "Quick sniff of packets"}
const PARAM_DESC := {"address": "IP address", "interface": "Interface name", "network": "Network address", "comment": "Short description of the item",
	"disabled": "Defines whether item is ignored or used", "gateway": "Gateway address or interface", "dst-address": "Destination address",
	"distance": "Route distance", "name": "Item name", "vlan-ids": "VLAN IDs", "tagged": "Interfaces that send tagged frames",
	"untagged": "Interfaces that send untagged frames", "pvid": "Port VLAN ID", "bridge": "Bridge name", "count": "Number of packets to send",
	"size": "Packet size", "chain": "Rule chain", "action": "Action to take", "protocol": "IP protocol", "dst-port": "Destination port",
	"src-address": "Source address", "in-interface": "Incoming interface", "out-interface": "Outgoing interface", "ranges": "Address ranges",
	"address-pool": "Address pool", "dns-server": "DNS server", "servers": "Server addresses", "enabled": "Whether the service is enabled",
	"password": "Password", "group": "User group", "port": "TCP port", "slaves": "Member interfaces", "mode": "Mode", "vlan-id": "VLAN ID",
	"vrid": "Virtual router ID", "priority": "Priority", "networks": "Networks", "area": "Area name", "router-id": "Router ID",
	"remote.address": "Remote address", "remote.as": "Remote AS", "as": "Local AS", "list": "List name", "copy-from": "Item to copy from"}

func _help_for(path: String, menu: bool) -> String:
	## '?' the RouterOS way: a menu lists what can follow with a word about
	## each; a command lists its parameters
	if PARAMS.has(path) and not menu or (PARAMS.has(path) and _children(path).is_empty()):
		var out := "%s\n\n" % VERB_DESC.get(path.split(" ")[-1], "")
		for k in PARAMS[path]:
			out += "%s -- %s\n" % [k, PARAM_DESC.get(String(k), "")]
		return out
	var kids := _children(path)
	kids.sort()
	var out := ""
	for k in kids:
		out += "%s -- %s\n" % [k, VERB_DESC.get(String(k), "")]
	return out if out != "" else "% no such menu\n"

func _next_words(path: String) -> Dictionary:
	var nexts := {}
	for c in PATHS:
		if path != "" and c.begins_with(path + " "):
			nexts[String(c.substr(path.length() + 1)).split(" ")[0]] = true
	return nexts

static func _is_header(l: String) -> bool:
	return l.begins_with("Flags:") or l.begins_with("Columns:") or l.strip_edges().begins_with("#")

static func _rows_of(text: String) -> Array:
	var rows: Array = []
	for l in text.split("\n", false):
		if not _is_header(l):
			rows.append(l)
	return rows

static func _where(text: String, cond: Dictionary) -> String:
	## print where key=value: the rows whose named column equals the value
	## (a substring test when the key is not a column), numbered as before
	var lines := text.split("\n", false)
	var cols: PackedStringArray = []
	var header := ""
	for l in lines:
		if l.begins_with("Columns: "):
			cols = l.trim_prefix("Columns: ").split(", ")
		elif l.strip_edges().begins_with("#") and header == "":
			header = l
	var offs: Array = []
	for c in cols:
		offs.append(header.find(c))
	var out := ""
	for l in lines:
		var keep := _is_header(l)
		if not keep:
			keep = true
			for k in cond:
				var want := String(cond[k]).replace("\"", "")
				var col := -1
				for ci in cols.size():
					if String(cols[ci]).to_lower() == String(k).to_lower():
						col = ci
				if col >= 0:
					var end: int = int(offs[col + 1]) if col + 1 < cols.size() else l.length()
					var val := l.substr(int(offs[col]), end - int(offs[col])).strip_edges()
					if val != want:
						keep = false
				elif ("%s=%s" % [k, want]) not in l and ("%s=\"%s\"" % [k, want]) not in l:
					keep = false
		if keep:
			out += l + "\n"
	return out

static func _detail(text: String) -> String:
	## print detail: the same items as key=value lines, one item per line,
	## the way RouterOS prints them. Sliced by the header's column positions.
	var lines := text.split("\n", false)
	var cols: PackedStringArray = []
	var header := ""
	for l in lines:
		if l.begins_with("Columns: "):
			cols = l.trim_prefix("Columns: ").split(", ")
		elif l.strip_edges().begins_with("#") and header == "":
			header = l
	if cols.is_empty() or header == "":
		return text  # already key=value
	var offs: Array = []
	for c in cols:
		offs.append(header.find(c))
	var out := ""
	for l in lines:
		if l.begins_with("Flags:"):
			out += l + "\n"
			continue
		if _is_header(l):
			continue
		var lead := l.substr(0, int(offs[0])).strip_edges()
		var parts := lead.split(" ", false)
		var num := parts[0] if parts.size() > 0 and String(parts[0]).is_valid_int() else ""
		var flags := " ".join(parts.slice(1)) if num != "" else lead
		var kv: Array = []
		for k in cols.size():
			var end: int = int(offs[k + 1]) if k + 1 < cols.size() else l.length()
			var val := l.substr(int(offs[k]), end - int(offs[k])).strip_edges()
			var key := String(cols[k]).to_lower()
			kv.append("%s=%s" % [key, ("\"%s\"" % val) if key in ["name", "comment", "host-name"] else val])
		out += "%2s %-3s %s\n" % [num, flags, " ".join(PackedStringArray(kv))]
	return out

static func _us(ms: float) -> String:
	## RouterOS prints round trips as 312us or 12ms345us
	var us := int(round(ms * 1000.0))
	if us < 1000:
		return "%dus" % us
	return "%dms%dus" % [us / 1000, us % 1000]

static func fmt_ping(dev: Net.NDevice, target: String, count: int, size: int) -> String:
	## /ping the RouterOS way: a row per probe, the failure in the STATUS
	## column, and a sent/received/packet-loss summary.
	var ip := Sim.resolve(dev, target)
	if ip == "":
		return "invalid value for argument address:\n    while resolving net address: could not get answer from dns server\n"
	count = clampi(count, 1, 50)
	var out := "  SEQ HOST                                     SIZE TTL TIME       STATUS\n"
	var received := 0
	var best := 9999.0
	var worst := 0.0
	var total := 0.0
	for seq in count:
		var r := Sim.ping(dev, ip, 64, "", size)
		if bool(r["ok"]):
			received += 1
			var rtt := maxf(0.04, float(r.get("rtt", 0.1))) * (1.0 + 0.04 * seq)
			best = minf(best, rtt)
			worst = maxf(worst, rtt)
			total += rtt
			out += "%5d %-40s %4d %3d %-10s\n" % [seq, r["from"], size - 8, int(r.get("ttl", 64)), _us(rtt)]
			continue
		var detail := String(r.get("detail", "timeout"))
		var status := "timeout"
		match detail:
			"ttl-exceeded":
				status = "TTL exceeded"
			"unreachable-host":
				status = "host unreachable"
			"unreachable-net":
				status = "net unreachable"
			"unreachable-admin":
				status = "packet filtered"
			"unreachable-port":
				status = "port unreachable"
		if status == "timeout":
			out += "%5d %-40s %4s %3s %-10s %s\n" % [seq, ip, "", "", "", status]
		else:
			out += "%5d %-40s %4d %3d %-10s %s\n" % [seq, r.get("from", ip), size + 20, 64,
				_us(maxf(0.04, float(r.get("rtt", 0.1)))), status]
	var lost := count - received
	out += "    sent=%d received=%d packet-loss=%d%%" % [count, received,
		int(round(100.0 * float(lost) / float(count)))]
	if received > 0:
		out += " min-rtt=%s avg-rtt=%s max-rtt=%s" % [_us(best), _us(total / float(received)), _us(worst)]
	return out + "\n"

static func fmt_traceroute(dev: Net.NDevice, target: String, count: int) -> String:
	var ip := Sim.resolve(dev, target)
	if ip == "":
		return "invalid value for argument address:\n    while resolving net address: could not get answer from dns server\n"
	count = clampi(count, 1, 10)
	var out := "Columns: ADDRESS, LOSS, SENT, LAST, AVG, BEST, WORST, STD-DEV, STATUS\n"
	out += "#  ADDRESS          LOSS  SENT  LAST     AVG   BEST  WORST  STD-DEV  STATUS\n"
	var n := 1
	for hop in Sim.traceroute(dev, ip):
		if hop == "*":
			out += "%-2d %-16s 100%%  %4d  timeout\n" % [n, "", count]
		else:
			var probe := Sim.ping(dev, String(hop))
			var rtt := maxf(0.04, float(probe.get("rtt", 0.1)))
			out += "%-2d %-16s 0%%    %4d  %-8s %-5s %-5s %-6s %s\n" % [n, hop, count, "%.1fms" % rtt,
				"%.1f" % rtt, "%.1f" % (rtt * 0.98), "%.1f" % (rtt * 1.03), "0"]
		n += 1
	return out

func _bare_target(args: Array, p: Dictionary) -> String:
	## address= or the one bare word, wherever it sits
	if p.has("address"):
		return String(p["address"])
	for a in args:
		if "=" not in String(a):
			return String(a)
	return ""

static func _dur(secs: int) -> String:
	## 10m, 1h5m12s, 2d3h: RouterOS drops the zero units in front
	if secs <= 0:
		return "0s"
	var parts: Array = []
	if secs >= 86400:
		parts.append("%dd" % (secs / 86400))
	if (secs / 3600) % 24 > 0 or not parts.is_empty():
		parts.append("%dh" % ((secs / 3600) % 24))
	if (secs / 60) % 60 > 0 or not parts.is_empty():
		parts.append("%dm" % ((secs / 60) % 60))
	if secs % 60 > 0 or parts.is_empty():
		parts.append("%ds" % (secs % 60))
	return "".join(PackedStringArray(parts))

func _empty(flags_line: String) -> String:
	## an empty list on RouterOS is silent, apart from the legend it would have
	return flags_line

func _uptime() -> String:
	var secs := Game.cycle * 3600
	return "%dh%dm%ds" % [secs / 3600, (secs / 60) % 60, secs % 60] if secs < 86400 \
		else "%dd%dh%dm%ds" % [secs / 86400, (secs / 3600) % 24, (secs / 60) % 60, secs % 60]

func _kv_block(pairs: Array) -> String:
	## the right-aligned key: value block RouterOS uses for single items
	var width := 0
	for pr in pairs:
		width = maxi(width, String(pr[0]).length())
	var out := ""
	for pr in pairs:
		out += "%*s: %s\n" % [width, pr[0], pr[1]]
	return out

func _run(path: String, args: Array, p: Dictionary) -> Variant:
	match path:
		"help":
			return _help()
		"export":
			return _export()
		"ping":
			var target := _bare_target(args, p)
			if target != "":
				var ping_size := int(p.get("size", 64)) \
					if String(p.get("size", "64")).is_valid_int() else 64
				var count := int(p["count"]) if String(p.get("count", "")).is_valid_int() else 3
				return fmt_ping(dev, target, count, ping_size)
			return "value of address must be specified\n"
		"tool traceroute":
			var target := _bare_target(args, p)
			if target != "":
				return fmt_traceroute(dev, target, int(p["count"]) if String(p.get("count", "")).is_valid_int() else 3)
			return "value of address must be specified\n"
		"tool torch":
			# the live pairs, the way torch shows them
			var out := "MAC-PROTOCOL  SRC-ADDRESS      DST-ADDRESS      TX-PACKET  RX-PACKET\n"
			var trows: Array = []
			for tk in dev.talkers:
				trows.append([String(tk), int(dev.talkers[tk])])
			trows.sort_custom(func(x, y): return int(x[1]) > int(y[1]))
			for trow in trows.slice(0, 15):
				var pair := String(trow[0]).split(">")
				out += "%-13s %-16s %-16s %9d  %9d\n" % ["ip", pair[0], pair[1] if pair.size() > 1 else "",
					int(trow[1]), 0]
			return out
		"tool sniffer quick":
			# the capture ring, one line per frame, as tcpdump would print it
			var out := ""
			for l in dev.capture:
				out += Sim.capture_line(String(l)) + "\n"
			return out
		"system ssh":
			return CLI.try_ssh(self, args[0]) if args.size() >= 1 else "value of address must be specified\n"
		"quit":
			wants_exit = true
			return ""
		"system identity set":
			if p.has("name") and Game.rename_device(dev, p["name"]):
				return ""
			return "invalid value for argument name\n"
		"system identity print":
			return "  name: %s\n" % dev.name
		"system resource print":
			return _kv_block([["uptime", _uptime()], ["version", "%s (stable)" % VERSION],
				["build-time", "2024-03-27 09:11:23"], ["factory-software", VERSION],
				["free-memory", "212.5MiB"], ["total-memory", "256.0MiB"], ["cpu", "QEMU"],
				["cpu-count", "1"], ["cpu-frequency", "2400MHz"], ["cpu-load", "%d%%" % mini(99, dev.talkers.size())],
				["free-hdd-space", "48.2MiB"], ["total-hdd-space", "64.0MiB"],
				["write-sect-since-reboot", "%d" % (Game.cycle * 37)], ["write-sect-total", "%d" % (Game.cycle * 41)],
				["architecture-name", "x86_64"], ["board-name", "CHR"], ["platform", "PacketTik"]])
		"system clock print":
			var stamp := Time.get_datetime_string_from_system(false, true)
			return _kv_block([["time", "%02d:00:00" % (Game.day_slot() * 3)], ["date", stamp.split(" ")[0]],
				["time-zone-autodetect", "yes"], ["time-zone-name", "Europe/Budapest"], ["gmt-offset", "+02:00"],
				["dst-active", "yes"]])
		"system package print":
			return "Columns: NAME, VERSION, BUILD-TIME, SIZE\n#  NAME     VERSION  BUILD-TIME           SIZE\n0  routeros %s   2024-03-27 09:11:23  12.5MiB\n" % VERSION
		"system reboot":
			return "Reboot, yes? [y/N]:\ny\n"
		"system backup save":
			var name := String(p.get("name", "%s-%s" % [dev.name, Time.get_date_string_from_system().replace("-", "")]))
			dev.versions.append({"cycle": Game.cycle, "cfg": Game.device_config(dev), "backup": name})
			return "Saving system configuration\nConfiguration backup saved\n"
		"system backup load":
			var wanted := String(p.get("name", ""))
			var found := {}
			for v in dev.versions:
				if v.has("backup") and (wanted == "" or String(v["backup"]) == wanted or String(v["backup"]) + ".backup" == wanted):
					found = v
			if found.is_empty():
				return "failure: no such file\n"
			Game.apply_device_config(dev, found["cfg"])
			return "Restore and reboot? [y/N]:\ny\nRestoring system configuration\nSystem configuration restored, rebooting now\n"
		"file print":
			var out := "Columns: NAME, TYPE, SIZE, CREATION-TIME\n#  NAME                 TYPE     SIZE     CREATION-TIME\n"
			var n := 0
			for v in dev.versions:
				if v.has("backup"):
					out += "%d  %-20s backup   14.2KiB  %s\n" % [n, String(v["backup"]) + ".backup", Time.get_datetime_string_from_system(false, true).replace("T", " ")]
					n += 1
			return out
		"log print":
			var out := ""
			var n := 0
			for l in dev.logs.slice(maxi(0, dev.logs.size() - 40)):
				out += "%02d:%02d:%02d system,info %s\n" % [(Game.day_slot() * 3) % 24, n % 60, (n * 7) % 60, l]
				n += 1
			return out
		"user print":
			var out := "Columns: NAME, GROUP, LAST-LOGGED-IN\n#   NAME   GROUP  LAST-LOGGED-IN\n0   admin  full   %s\n" % Time.get_datetime_string_from_system(false, true).replace("T", " ")
			var n := 1
			for u in dev.services.get("ros_users", {}):
				out += "%d   %-6s %-6s \n" % [n, u, dev.services["ros_users"][u]]
				n += 1
			return out
		"user add":
			if not p.has("name"):
				return "value of name must be specified\n"
			var users: Dictionary = dev.services.get("ros_users", {})
			users[String(p["name"])] = String(p.get("group", "read"))
			dev.services["ros_users"] = users
			return ""
		"user set", "password":
			return ""
		"user remove":
			var users: Dictionary = dev.services.get("ros_users", {})
			for a in args:
				users.erase(String(a))
			return ""
		"ip service set":
			var conf: Dictionary = dev.services.get("ros_services", {})
			var which := _bare_target(args, p)
			if which == "" and args.is_empty():
				return "no such item\n"
			var entry: Dictionary = conf.get(which, {})
			if p.has("port"):
				if not String(p["port"]).is_valid_int():
					return "invalid value for argument port\n"
				entry["port"] = int(p["port"])
			if p.has("disabled"):
				entry["disabled"] = String(p["disabled"]) == "yes"
			conf[which] = entry
			dev.services["ros_services"] = conf
			return ""
		"ip service disable", "ip service enable":
			var conf: Dictionary = dev.services.get("ros_services", {})
			for a in args:
				var entry: Dictionary = conf.get(String(a), {})
				entry["disabled"] = path.ends_with("disable")
				conf[String(a)] = entry
			dev.services["ros_services"] = conf
			return ""
		"ip service print":
			var out := "Flags: X - DISABLED, I - INVALID\nColumns: NAME, PORT, ADDRESS, CERTIFICATE\n#   NAME     PORT  ADDRESS  CERTIFICATE\n"
			var n := 0
			for svc in [["telnet", 23, true], ["ftp", 21, true], ["www", 80, false], ["ssh", 22, false],
					["www-ssl", 443, true], ["api", 8728, true], ["winbox", 8291, false], ["api-ssl", 8729, true]]:
				var conf: Dictionary = dev.services.get("ros_services", {}).get(String(svc[0]), {})
				out += "%d %s %-8s %5d          %s\n" % [n, "X" if bool(conf.get("disabled", svc[2])) else " ", svc[0], int(conf.get("port", svc[1])),
					"none" if String(svc[0]).ends_with("ssl") else ""]
				n += 1
			return out
		"ip dns print":
			return _kv_block([["servers", dev.resolver], ["dynamic-servers", ""], ["use-doh-server", ""],
				["verify-doh-cert", "no"], ["allow-remote-requests", "no"], ["max-udp-packet-size", "4096"],
				["query-server-timeout", "2s"], ["query-total-timeout", "10s"], ["max-concurrent-queries", "100"],
				["max-concurrent-tcp-sessions", "20"], ["cache-size", "2048KiB"], ["cache-max-ttl", "1w"],
				["cache-used", "%dKiB" % (9 + dev.dns_cache.size())]])
		"ip dns set":
			if p.has("servers"):
				dev.resolver = String(p["servers"]).split(",")[0]
				Game.topology_changed.emit()
			return ""
		"ip dns cache print":
			var out := "Flags: S - STATIC\nColumns: NAME, TYPE, DATA, TTL\n#   NAME                 TYPE  DATA             TTL\n"
			var n := 0
			for name in dev.dns_cache:
				out += "%-3d %-20s A     %-16s %s\n" % [n, name, dev.dns_cache[name].get("ip", ""),
					_dur(maxi(0, int(dev.dns_cache[name].get("expires", 0)) - Game.cycle) * 3600)]
				n += 1
			return out
		"ip dhcp-server print":
			var rd: Dictionary = dev.services.get("ros_dhcp", {})
			var svc: Dictionary = dev.services.get("dhcp", {})
			var out := "Columns: NAME, INTERFACE, ADDRESS-POOL, LEASE-TIME\n#   NAME   INTERFACE  ADDRESS-POOL  LEASE-TIME\n"
			if rd.has("server"):
				return out + "0   %-6s %-10s %-13s 10m\n" % [rd["server"]["name"], rd["server"]["iface"], rd["server"]["pool"]]
			if svc.is_empty():
				return out
			return out + "0   dhcp1  %-10s pool1         1d\n" % String(svc.get("iface", ""))
		"ip pool add":
			if not p.has("name") or not p.has("ranges"):
				return "value of %s must be specified\n" % ("name" if not p.has("name") else "ranges")
			var rng := String(p["ranges"]).split("-")
			if rng.size() != 2 or not String(rng[0]).is_valid_ip_address() or not String(rng[1]).is_valid_ip_address():
				return "invalid value for argument ranges\n"
			var rd: Dictionary = dev.services.get("ros_dhcp", {"pools": {}})
			if not rd.has("pools"):
				rd["pools"] = {}
			rd["pools"][String(p["name"])] = [String(rng[0]), String(rng[1])]
			dev.services["ros_dhcp"] = rd
			_ros_dhcp_assemble()
			return ""
		"ip pool print":
			var out := "Columns: NAME, RANGES\n#   NAME    RANGES\n"
			var n := 0
			for name in dev.services.get("ros_dhcp", {}).get("pools", {}):
				var rng: Array = dev.services["ros_dhcp"]["pools"][name]
				out += "%-3d %-7s %s-%s\n" % [n, name, rng[0], rng[1]]
				n += 1
			return out
		"ip dhcp-server add":
			if not p.has("interface"):
				return "value of interface must be specified\n"
			var on := String(p["interface"])
			if on != BRIDGE and _iface(on) == null:
				return "input does not match any value of interface\n"
			var rd: Dictionary = dev.services.get("ros_dhcp", {"pools": {}})
			rd["server"] = {"name": String(p.get("name", "dhcp1")), "iface": on, "pool": String(p.get("address-pool", "static-only")),
				"disabled": String(p.get("disabled", "no")) == "yes"}
			dev.services["ros_dhcp"] = rd
			_ros_dhcp_assemble()
			return ""
		"ip dhcp-server network add":
			if not p.has("address") or not Net.valid_cidr(String(p["address"])):
				return "value of address must be specified\n" if not p.has("address") else "invalid value for argument address\n"
			var rd: Dictionary = dev.services.get("ros_dhcp", {"pools": {}})
			rd["network"] = {"address": String(p["address"]), "gw": String(p.get("gateway", "")), "dns": String(p.get("dns-server", ""))}
			dev.services["ros_dhcp"] = rd
			_ros_dhcp_assemble()
			return ""
		"ip dhcp-server network print":
			var out := "Columns: ADDRESS, GATEWAY, DNS-SERVER\n#   ADDRESS         GATEWAY    DNS-SERVER\n"
			var nw: Dictionary = dev.services.get("ros_dhcp", {}).get("network", {})
			if not nw.is_empty():
				out += "0   %-15s %-10s %s\n" % [nw["address"], nw.get("gw", ""), nw.get("dns", "")]
			return out
		"ip dhcp-server setup":
			return "Select interface to run DHCP server on\n\ndhcp server interface: (this console cannot answer the wizard: use /ip pool add, /ip dhcp-server add and /ip dhcp-server network add)\n"
		"ip dhcp-client add":
			var ci := _iface(String(p.get("interface", "")))
			if ci == null:
				return "input does not match any value of interface\n"
			var got := Sim.dhcp_request(dev, ci)
			var clients: Dictionary = dev.services.get("dhcp_clients", {})
			clients[ci.name] = {"status": "bound" if not got.is_empty() else "searching...", "address": ("%s/%d" % [got["ip"], int(got["plen"])]) if not got.is_empty() else "",
				"peer-dns": String(p.get("use-peer-dns", "yes")), "default-route": String(p.get("add-default-route", "yes"))}
			dev.services["dhcp_clients"] = clients
			return ""
		"ip dhcp-server lease print":
			var svc: Dictionary = dev.services.get("dhcp", {})
			var out := "Columns: ADDRESS, MAC-ADDRESS, HOST-NAME, SERVER, STATUS, LAST-SEEN\n#    ADDRESS         MAC-ADDRESS        HOST-NAME  SERVER  STATUS  LAST-SEEN\n"
			var n := 0
			for mac in svc.get("leases", {}):
				out += "%d  D %-15s %-18s %-10s dhcp1   bound   %s\n" % [n, svc["leases"][mac], mac,
					Sim.reverse_lookup(dev, String(svc["leases"][mac])), _dur(60 + (Game.cycle - int(svc.get("since", {}).get(mac, Game.cycle))) * 3600)]
				n += 1
			return ("Flags: D - DYNAMIC\n" + out) if n > 0 else ""
		"ip dhcp-client print":
			var out := "Columns: INTERFACE, USE-PEER-DNS, ADD-DEFAULT-ROUTE, STATUS, ADDRESS\n#  INTERFACE  USE-PEER-DNS  ADD-DEFAULT-ROUTE  STATUS  ADDRESS\n"
			var n := 0
			for ifn in dev.services.get("dhcp_clients", {}):
				var c: Dictionary = dev.services["dhcp_clients"][ifn]
				out += "%d  %-10s %-13s %-18s %-7s %s\n" % [n, ifn, c.get("peer-dns", "yes"), c.get("default-route", "yes"), c.get("status", ""), c.get("address", "")]
				n += 1
			return out
		"ip firewall filter add":
			if not p.has("chain") or String(p["chain"]) not in ["input", "forward", "output"]:
				return "value of chain must be specified\n" if not p.has("chain") else "input does not match any value of chain\n"
			var action := String(p.get("action", "accept"))
			if action not in ["accept", "drop", "reject", "log", "passthrough", "fasttrack-connection", "jump", "return"]:
				return "input does not match any value of action\n"
			var rules: Array = dev.services.get("ros_filter", [])
			var rule := {"chain": String(p["chain"]), "action": action}
			for k in ["src-address", "dst-address", "protocol", "dst-port", "src-port", "in-interface", "out-interface", "connection-state", "comment", "in-interface-list"]:
				if p.has(k):
					rule[k] = String(p[k])
			rules.append(rule)
			dev.services["ros_filter"] = rules
			_ros_filter_apply()
			return ""
		"ip firewall filter remove":
			var rules: Array = dev.services.get("ros_filter", [])
			for a in args:
				if String(a).is_valid_int() and int(a) >= 0 and int(a) < rules.size():
					rules.remove_at(int(a))
					dev.services["ros_filter"] = rules
					_ros_filter_apply()
					return ""
			return "no such item\n"
		"ip firewall filter print":
			var out := "Flags: X - disabled, I - invalid; D - dynamic\n"
			var n := 0
			for rule in dev.services.get("ros_filter", []):
				var text := ""
				for k in ["chain", "action", "protocol", "src-address", "dst-address", "dst-port", "src-port", "in-interface", "out-interface", "in-interface-list", "connection-state", "comment"]:
					if rule.has(k):
						text += " %s=%s" % [k, ("\"%s\"" % rule[k]) if k == "comment" else rule[k]]
				out += " %d   %s log=no log-prefix=\"\"\n" % [n, text.strip_edges()]
				n += 1
			return out
		"interface list add":
			if not p.has("name"):
				return "value of name must be specified\n"
			var lists: Dictionary = dev.services.get("if_lists", {})
			if not lists.has(String(p["name"])):
				lists[String(p["name"])] = []
			dev.services["if_lists"] = lists
			return ""
		"interface list member add":
			var lists: Dictionary = dev.services.get("if_lists", {})
			if not lists.has(String(p.get("list", ""))):
				return "input does not match any value of list\n"
			if _iface(String(p.get("interface", ""))) == null:
				return "input does not match any value of interface\n"
			if String(p["interface"]) not in lists[String(p["list"])]:
				lists[String(p["list"])].append(String(p["interface"]))
			return ""
		"interface list print":
			var out := "Flags: * - builtin; D - dynamic\nColumns: NAME, INCLUDE, EXCLUDE\n#   NAME     INCLUDE  EXCLUDE\n0 * all\n1 * none\n2 * dynamic\n3 * static\n"
			var n := 4
			for name in dev.services.get("if_lists", {}):
				out += "%d   %s\n" % [n, name]
				n += 1
			return out
		"interface list member print":
			var out := "Flags: D - dynamic\nColumns: LIST, INTERFACE\n#   LIST  INTERFACE\n"
			var n := 0
			for name in dev.services.get("if_lists", {}):
				for ifn in dev.services["if_lists"][name]:
					out += "%-3d %-5s %s\n" % [n, name, ifn]
					n += 1
			return out
		"interface monitor-traffic":
			var mi := _target(args, p)
			if mi == null:
				return "input does not match any value of numbers\n"
			return _kv_block([["name", mi.name], ["rx-packets-per-second", str(mi.rx_frames / 60)], ["rx-bits-per-second", "%dkbps" % (mi.rx_frames * 148 * 8 / 60 / 1000)],
				["fp-rx-packets-per-second", str(mi.rx_frames / 60)], ["fp-rx-bits-per-second", "%dkbps" % (mi.rx_frames * 148 * 8 / 60 / 1000)],
				["rx-drops-per-second", "0"], ["rx-errors-per-second", str(mi.rx_errors / 60)], ["tx-packets-per-second", str(mi.tx_frames / 60)],
				["tx-bits-per-second", "%dkbps" % (mi.tx_frames * 148 * 8 / 60 / 1000)], ["fp-tx-packets-per-second", str(mi.tx_frames / 60)],
				["fp-tx-bits-per-second", "%dkbps" % (mi.tx_frames * 148 * 8 / 60 / 1000)], ["tx-drops-per-second", str(mi.out_drops / 60)],
				["tx-queue-drops-per-second", "0"], ["tx-errors-per-second", "0"]])
		"system ntp client set":
			if p.has("servers"):
				dev.ntp_server = String(p["servers"]).split(",")[0]
			if String(p.get("enabled", "")) == "no":
				dev.ntp_server = ""
			Game.topology_changed.emit()
			return ""
		"system ntp client print":
			return _kv_block([["enabled", "yes" if dev.ntp_server != "" else "no"], ["mode", "unicast"], ["servers", dev.ntp_server], ["vrf", "main"],
				["freq-drift", "0 PPM"], ["status", "synchronized" if dev.ntp_server != "" else "stopped"], ["synced-server", dev.ntp_server],
				["synced-stratum", "3" if dev.ntp_server != "" else "0"], ["system-offset", "0.12 ms" if dev.ntp_server != "" else "0 ms"]])
		"system logging print":
			return "Flags: X - disabled, I - invalid; * - default\nColumns: TOPICS, ACTION\n#   TOPICS    ACTION\n0 * info      memory\n1 * error     memory\n2 * warning   memory\n3 * critical  echo\n"
		"routing route print":
			return exec("/ip route print").replace("Flags: D - DYNAMIC; A - ACTIVE;", "Flags: D - DYNAMIC; A - ACTIVE, I - INACTIVE;")
		"interface bridge settings print":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			return _kv_block([["use-ip-firewall", "no"], ["use-ip-firewall-for-vlan", "no"], ["use-ip-firewall-for-pppoe", "no"], ["allow-fast-path", "yes"],
				["bridge-fast-path-active", "yes"], ["bridge-fast-path-packets", str(dev.ifaces[0].rx_frames if not dev.ifaces.is_empty() else 0)],
				["bridge-fast-path-bytes", str((dev.ifaces[0].rx_frames if not dev.ifaces.is_empty() else 0) * 148)], ["bridge-fast-forward-active", "no"],
				["bridge-fast-forward-packets", "0"], ["bridge-fast-forward-bytes", "0"]])
		"ip neighbor print":
			var out := "Columns: INTERFACE, ADDRESS, MAC-ADDRESS, IDENTITY, VERSION, BOARD\n#  INTERFACE  ADDRESS         MAC-ADDRESS        IDENTITY  VERSION  BOARD\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				var peer := Game.effective_peer(i)
				if peer == null:
					continue
				var pip := ""
				for cidr in peer.ips:
					if not Net.is_v6(cidr):
						pip = String(cidr).split("/")[0]
						break
				if pip == "":
					pip = CLI.first_ip_of(peer.dev)
				out += "%-2d %-10s %-15s %-18s %-9s %-8s %s\n" % [n, i.name, pip if pip != "0.0.0.0" else "", peer.mac.to_upper(), peer.dev.name,
					VERSION if Game.is_ros(peer.dev) else "4.28.3M", "CHR" if Game.is_ros(peer.dev) else String(Game.MODELS.get(peer.dev.model, {}).get("label", "")).split(" ")[0]]
				n += 1
			return out
		"ip neighbor discovery-settings print":
			return _kv_block([["discover-interface-list", "!dynamic"], ["lldp-med-net-policy-vlan", "disabled"], ["protocol", "cdp,lldp,mndp"], ["mode", "tx-and-rx"]])
		"ip firewall connection print":
			var out := "Columns: PROTOCOL, SRC-ADDRESS, DST-ADDRESS, TIMEOUT\n#   PROTOCOL  SRC-ADDRESS      DST-ADDRESS      TIMEOUT\n"
			var n := 0
			for tk in dev.talkers.keys().slice(0, 20):
				var pair := String(tk).split(">")
				out += "%-3d icmp      %-16s %-16s %ds\n" % [n, pair[0], pair[1] if pair.size() > 1 else "", 10]
				n += 1
			return out
		"snmp set":
			if p.has("community"):  # the old one-liner still works
				dev.snmp = String(p["community"])
			if String(p.get("enabled", "")) == "no":
				dev.snmp = ""
			elif String(p.get("enabled", "")) == "yes" and dev.snmp == "":
				dev.snmp = "public"  # the default community, until it is renamed
			if not p.has("enabled") and not p.has("community"):
				return ""
			Game.topology_changed.emit()
			return ""
		"snmp community set", "snmp community add":
			if p.has("name"):
				dev.snmp = String(p["name"])
				Game.topology_changed.emit()
				return ""
			return "value of name must be specified\n"
		"snmp community print":
			return "Flags: * - DEFAULT\nColumns: NAME, ADDRESSES, SECURITY, READ-ACCESS, WRITE-ACCESS\n#   NAME     ADDRESSES  SECURITY  READ-ACCESS  WRITE-ACCESS\n0 * %-8s ::/0       none      yes          no\n" % (dev.snmp if dev.snmp != "" else "public")
		"snmp print":
			return _kv_block([["enabled", "yes" if dev.snmp != "" else "no"], ["contact", ""], ["location", ""],
				["engine-id-suffix", ""], ["engine-id", "80003a8c04"], ["trap-target", ""],
				["trap-community", dev.snmp if dev.snmp != "" else "public"], ["trap-version", "1"],
				["trap-generators", ""], ["trap-interfaces", ""], ["src-address", "::"], ["vrf", "main"]])
		"ip traffic-flow print":
			return _kv_block([["enabled", "no"], ["interfaces", "all"], ["cache-entries", "4k"],
				["active-flow-timeout", "30m"], ["inactive-flow-timeout", "15s"], ["packet-sampling", "no"]])
		"routing bfd configuration add":
			var names := String(p.get("interfaces", "")).split(",", false)
			if names.is_empty():
				return "value of interfaces must be specified\n"
			for nm in names:
				if _iface(nm) == null:
					return "input does not match any value of interfaces\n"
			for nm in names:
				_iface(nm).bfd = String(p.get("disabled", "no")) != "yes"
			Game.topology_changed.emit()
			return ""
		"routing bfd configuration remove":
			for nm in String(p.get("interfaces", "")).split(",", false):
				if _iface(nm) != null:
					_iface(nm).bfd = false
			var n := 0
			for bi: Net.Iface in dev.ifaces:
				if bi.bfd:
					if str(n) in args:
						bi.bfd = false
					n += 1
			Game.topology_changed.emit()
			return ""
		"routing bfd configuration print":
			var bout := "Flags: X - disabled, I - inactive\nColumns: INTERFACES, DISABLED\n#  INTERFACES  DISABLED\n"
			var bn := 0
			for bi: Net.Iface in dev.ifaces:
				if bi.bfd:
					bout += "%d  %-11s no\n" % [bn, bi.name]
					bn += 1
			return bout if bn > 0 else _empty("Flags: X - disabled, I - inactive\n")
		"routing bfd session print":
			var bout := "Flags: U - up\nColumns: INTERFACE, STATE\n#    INTERFACE  STATE\n"
			var bn := 0
			for bi: Net.Iface in dev.ifaces:
				if not bi.bfd:
					continue
				var st := String(Sim.bfd_session(bi))
				bout += "%d %s  %-10s %s\n" % [bn, "U" if st == "up" else " ", bi.name, st]
				bn += 1
			return bout if bn > 0 else _empty("Flags: U - up\n")
		"interface vlan add":
			if not dev.ip_forwarding:
				return "failure: vlan interfaces need a router\n"
			var parent := _iface(String(p.get("interface", "")))
			if parent == null:
				return "input does not match any value of interface\n"
			if not String(p.get("vlan-id", "")).is_valid_int():
				return "value of vlan-id must be specified\n"
			var vsub := Game.add_subiface(dev, parent.name, int(p["vlan-id"]))
			if vsub == null:
				return "failure: could not create the vlan interface\n"
			if p.has("name"):
				var names: Dictionary = dev.services.get("vlan_names", {})
				names[str(vsub.dot1q)] = String(p["name"])
				dev.services["vlan_names"] = names
			return ""
		"interface vlan remove":
			var vi := _target(args, p)
			if vi == null or vi.parent == "":
				return "no such item\n"
			dev.ifaces.erase(vi)
			Game.topology_changed.emit()
			return ""
		"interface vlan print":
			var out := "Flags: R - RUNNING\nColumns: NAME, MTU, ARP, VLAN-ID, INTERFACE\n#   NAME     MTU   ARP      VLAN-ID  INTERFACE\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if i.parent != "":
					out += "%d R %-8s %-5d enabled  %-8d %s\n" % [n, _dname(i), i.mtu, i.dot1q, i.parent]
					n += 1
			return out if n > 0 else _empty("Flags: R - RUNNING\n")
		"interface vrrp add":
			if not dev.ip_forwarding:
				return "failure: vrrp needs a router\n"
			var on := _iface(String(p.get("interface", "")))
			if on == null:
				return "input does not match any value of interface\n"
			var vrid := int(p.get("vrid", "1")) if String(p.get("vrid", "1")).is_valid_int() else 1
			var prio := int(p.get("priority", "100")) if String(p.get("priority", "100")).is_valid_int() else 100
			on.vrrp = {"group": vrid, "vip": String(on.vrrp.get("vip", "")), "priority": clampi(prio, 1, 254),
				"preempt": String(p.get("preemption-mode", "yes")) != "no"}
			Game.topology_changed.emit()
			return ""
		"interface vrrp remove":
			var vi: Net.Iface = _vrrp_iface(String(p.get("name", args[0] if not args.is_empty() else "")))
			if vi == null:
				return "no such item\n"
			vi.vrrp = {}
			Game.topology_changed.emit()
			return ""
		"interface vrrp print":
			var out := "Flags: R - RUNNING; M - MASTER, B - BACKUP\nColumns: NAME, INTERFACE, VRID, PRIORITY, INTERVAL\n#    NAME   INTERFACE  VRID  PRIORITY  INTERVAL\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if i.vrrp.is_empty():
					continue
				var vip := String(i.vrrp.get("vip", ""))
				var flag := " "
				if vip != "":
					flag = "M" if Sim.vrrp_master(vip, int(i.vrrp["group"])) == dev else "B"
				out += "%d R%s vrrp%-3d %-10s %-5d %-9d 1s\n" % [n, flag, int(i.vrrp["group"]), i.name,
					int(i.vrrp["group"]), int(i.vrrp.get("priority", 100))]
				n += 1
			return out if n > 0 else _empty("Flags: R - RUNNING; M - MASTER, B - BACKUP\n")
		"interface wireguard add":
			var wname := String(p.get("name", "wg0"))
			if not (wname.begins_with("wg") and wname.trim_prefix("wg").is_valid_int()):
				return "invalid value for argument name\n"
			if Game.add_wireguard(dev, int(wname.trim_prefix("wg"))) == null:
				return "failure: wireguard needs a router\n"
			return ""
		"interface wireguard remove":
			var wi := _target(args, p)
			if wi == null or not wi.name.begins_with("wg"):
				return "no such item\n"
			dev.ifaces.erase(wi)
			Game.topology_changed.emit()
			return ""
		"interface wireguard print":
			var out := "Flags: X - disabled; R - running\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if i.name.begins_with("wg"):
					out += " %d  R name=\"%s\" mtu=1420 listen-port=13231 private-key=\"%s\" public-key=\"%s\"\n" % [n, i.name, i.wg_key.reverse(), i.wg_key]
					n += 1
			return out if n > 0 else _empty("Flags: X - disabled; R - running\n")
		"interface wireguard peers add":
			var wi := _iface(String(p.get("interface", "")))
			if wi == null or not wi.name.begins_with("wg"):
				return "input does not match any value of interface\n"
			for need in ["public-key", "endpoint-address", "allowed-address"]:
				if not p.has(need):
					return "value of %s must be specified\n" % need
			var allowed: Array = []
			for c in String(p["allowed-address"]).split(",", false):
				if not Net.valid_cidr(String(c).strip_edges()):
					return "invalid value for argument allowed-address\n"
				allowed.append(String(c).strip_edges())
			for existing in wi.wg_peers.duplicate():
				if String(existing.get("key", "")) == String(p["public-key"]):
					wi.wg_peers.erase(existing)
			wi.wg_peers.append({"key": String(p["public-key"]), "endpoint": String(p["endpoint-address"]),
				"allowed": allowed})
			Game.topology_changed.emit()
			return ""
		"interface wireguard peers remove":
			var n := 0
			for i: Net.Iface in dev.ifaces:
				for pr in i.wg_peers.duplicate():
					if String(pr.get("key", "")) == String(p.get("public-key", "")) or str(n) in args:
						i.wg_peers.erase(pr)
						Game.topology_changed.emit()
						return ""
					n += 1
			return "no such item\n"
		"interface wireguard peers print":
			var legend := "Flags: X - disabled; D - dynamic\n"
			var out := legend + "Columns: INTERFACE, PUBLIC-KEY, ENDPOINT-ADDRESS, ENDPOINT-PORT, CURRENT-ENDPOINT-ADDRESS, CURRENT-ENDPOINT-PORT, ALLOWED-ADDRESS\n#   INTERFACE  PUBLIC-KEY                                    ENDPOINT-ADDRESS  ENDPOINT-PORT  CURRENT-ENDPOINT-ADDRESS  CURRENT-ENDPOINT-PORT  ALLOWED-ADDRESS\n"
			var detail := "detail" in args
			var dout := legend
			var n := 0
			for i: Net.Iface in dev.ifaces:
				for pr in i.wg_peers:
					var up := Sim.wg_handshake(i, pr)
					out += "%-3d %-10s %-45s %-17s %-14d %-25s %-22s %s\n" % [n, i.name, pr.get("key", ""), pr.get("endpoint", ""),
						13231, pr.get("endpoint", "") if up else "", 13231 if up else 0,
						",".join(PackedStringArray(pr.get("allowed", [])))]
					dout += " %d   interface=%s public-key=\"%s\" endpoint-address=%s endpoint-port=13231 allowed-address=%s rx=%d tx=%d last-handshake=%s\n" % [
						n, i.name, pr.get("key", ""), pr.get("endpoint", ""),
						",".join(PackedStringArray(pr.get("allowed", []))), i.rx_frames * 148, i.tx_frames * 148,
						"5s" if up else "never"]
					n += 1
			if n == 0:
				return _empty(legend)
			return dout if detail else out
		"interface ethernet print":
			var out := "Flags: R - RUNNING; S - SLAVE\nColumns: NAME, MTU, MAC-ADDRESS, ARP, SWITCH\n#    NAME     MTU   MAC-ADDRESS        ARP      SWITCH\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if i.parent != "" or i.name.begins_with("wg"):
					continue
				out += "%-2d %s%s %-8s %-5d %-18s %-8s %s\n" % [n, _run_flag(i), "S" if _bridge_member(i) or i.lag > 0 else " ",
					i.name, i.mtu, i.mac, "proxy-arp" if i.name in dev.services.get("proxy_arp_ifaces", []) else "enabled",
					"switch1" if dev.type == "switch" else ""]
				n += 1
			return out
		"interface ethernet monitor":
			var i := _target(args, p)
			if i == null:
				return "input does not match any value of numbers\n"
			var link := Game.link_at(i)
			var up := i.enabled and link != null
			var pairs: Array = [["name", i.name], ["status", "link-ok" if up else "no-link"]]
			if up:
				var mbps := Game.iface_speed(i)
				pairs += [["auto-negotiation", "done"], ["rate", ("%dMbps" % mbps) if mbps < 1000 else ("%dGbps" % (mbps / 1000))],
					["full-duplex", "yes"], ["tx-flow-control", "no"], ["rx-flow-control", "no"],
					["advertising", "10M-baseT-half,10M-baseT-full,100M-baseT-half,100M-baseT-full,1G-baseT-full"],
					["link-partner-advertising", "10M-baseT-half,10M-baseT-full,100M-baseT-half,100M-baseT-full,1G-baseT-full"]]
			else:
				pairs += [["auto-negotiation", "incomplete"]]
			return _kv_block(pairs)
		"interface print stats":
			var out := "Columns: NAME, RX-BYTE, TX-BYTE, RX-PACKET, TX-PACKET, RX-DROP, TX-DROP, TX-QUEUE-DROP, RX-ERROR, TX-ERROR\n#   NAME       RX-BYTE     TX-BYTE  RX-PACKET  TX-PACKET  RX-DROP  TX-DROP  TX-QUEUE-DROP  RX-ERROR  TX-ERROR\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				out += "%-3d %-10s %9d  %10d  %9d  %9d  %7d  %7d  %13d  %8d  %8d\n" % [n, _dname(i), i.rx_frames * 148,
					i.tx_frames * 148, i.rx_frames, i.tx_frames, 0, 0, 0, i.rx_errors, 0]
				n += 1
			return out
		"interface print":
			return _interface_print()
		"interface disable", "interface enable":
			var i := _target(args, p)
			if i == null:
				return "input does not match any value of numbers\n"
			_set_disabled(i, path.ends_with("disable"))
			return ""
		"interface set", "interface ethernet set":
			var i := _target(args, p)
			if i == null:
				return "input does not match any value of numbers\n"
			if p.has("disabled"):
				if String(p["disabled"]) not in ["yes", "no"]:
					return "input does not match any value of disabled\n"
				_set_disabled(i, p["disabled"] == "yes")
			if p.has("mtu"):
				if not String(p["mtu"]).is_valid_int():
					return "invalid value for argument mtu\n"
				i.mtu = clampi(int(p["mtu"]), 576, 9216)
			if p.has("arp"):
				if String(p["arp"]) not in ["enabled", "proxy-arp", "reply-only", "disabled"]:
					return "input does not match any value of arp\n"
				var proxied: Array = dev.services.get("proxy_arp_ifaces", [])
				proxied.erase(i.name)
				if String(p["arp"]) == "proxy-arp":
					proxied.append(i.name)
				dev.services["proxy_arp_ifaces"] = proxied
			if p.has("name") and _iface(String(p["name"])) == null and i.parent != "":
				var names: Dictionary = dev.services.get("vlan_names", {})
				names[str(i.dot1q)] = String(p["name"])
				dev.services["vlan_names"] = names
			Game.topology_changed.emit()
			return ""
		"interface bonding add":
			if dev.type != "switch":
				return "failure: bonding needs a switch here\n"
			if not p.has("slaves"):
				return "value of slaves must be specified\n"
			var group := 1
			for i: Net.Iface in dev.ifaces:
				group = maxi(group, i.lag + 1)
			var names := String(p["slaves"]).split(",", false)
			for nm in names:
				if _iface(nm) == null:
					return "input does not match any value of slaves\n"
			for nm in names:
				_iface(nm).lag = group
				_iface(nm).lag_mode = "active" if String(p.get("mode", "balance-rr")) == "802.3ad" else "on"
			Game.topology_changed.emit()
			return ""
		"interface bonding remove":
			var groups := _bond_groups()
			var which := -1
			var wanted := String(p.get("name", args[0] if not args.is_empty() else ""))
			var n := 0
			for g in groups:
				if wanted == "bond%d" % g or wanted == str(n):
					which = int(g)
				n += 1
			if which < 0:
				return "no such item\n"
			for i: Net.Iface in dev.ifaces:
				if i.lag == which:
					i.lag = 0
					i.lag_mode = "on"
			Game.topology_changed.emit()
			return ""
		"interface bonding print":
			var out := "Flags: R - RUNNING\nColumns: NAME, MTU, MAC-ADDRESS, ARP, MODE, PRIMARY, SLAVES\n#   NAME   MTU   MAC-ADDRESS        ARP      MODE        PRIMARY  SLAVES\n"
			var groups := _bond_groups()
			var n := 0
			for g in groups:
				var lacp := false
				for i: Net.Iface in dev.ifaces:
					if i.lag == g and i.lag_mode != "on":
						lacp = true
				out += "%d R %-6s %-5d %-18s %-8s %-11s %-8s %s\n" % [n, "bond%d" % g, 1500, _iface(groups[g][0]).mac, "enabled",
					"802.3ad" if lacp else "balance-rr", "", ",".join(PackedStringArray(groups[g]))]
				n += 1
			return out if not groups.is_empty() else _empty("Flags: R - RUNNING\n")
		"interface bridge add", "interface bridge set":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			if p.has("protocol-mode"):
				if String(p["protocol-mode"]) not in ["none", "stp", "rstp", "mstp"]:
					return "input does not match any value of protocol-mode\n"
				if String(p["protocol-mode"]) != "none":
					dev.stp_mode = "mst" if p["protocol-mode"] == "mstp" else String(p["protocol-mode"])
					Sim.flush_learned_state()
			if p.has("priority"):
				var pr := String(p["priority"])
				var val := pr.hex_to_int() if pr.begins_with("0x") else (int(pr) if pr.is_valid_int() else -1)
				if val < 0 or val > 61440 or val % 4096 != 0:
					return "invalid value for argument priority\n"
				dev.stp_priority = val
				Sim.flush_learned_state()
			Game.topology_changed.emit()
			return ""
		"interface bridge print":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			return "Flags: X - disabled, R - running\n 0 R name=\"%s\" mtu=auto actual-mtu=1500 l2mtu=1592 arp=enabled arp-timeout=auto mac-address=%s protocol-mode=%s fast-forward=yes igmp-snooping=no auto-mac=yes ageing-time=5m priority=0x%x max-message-age=20s forward-delay=15s transmit-hold-count=6 vlan-filtering=yes pvid=1 frame-types=admit-all ingress-filtering=yes\n" % [
				BRIDGE, _bridge_mac(), "mstp" if dev.stp_mode == "mst" else dev.stp_mode, dev.stp_priority]
		"interface bridge vlan add":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			if not p.has("bridge"):
				return "value of bridge must be specified\n"
			if String(p["bridge"]) != BRIDGE:
				return "input does not match any value of bridge\n"
			var vids := _vids(String(p.get("vlan-ids", "")))
			if vids.is_empty():
				return "invalid value for argument vlan-ids\n" if p.has("vlan-ids") else "value of vlan-ids must be specified\n"
			var has_ports := p.has("tagged") or p.has("untagged")
			for vid in vids:
				if dev.vlans.has(vid) and not has_ports:
					return "failure: already have such vlan\n"
				if not dev.vlans.has(vid) and not Game.add_vlan(dev, vid, String(p.get("comment", ""))):
					return "invalid value for argument vlan-ids\n"
				var err := _apply_vlan_ports(vid, String(p.get("tagged", "")), String(p.get("untagged", "")))
				if err != "":
					return err
			Game.topology_changed.emit()
			return ""
		"interface bridge vlan set":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			var vids := _vids(String(p.get("vlan-ids", "")))
			for a in args:  # by item number, the way print numbers them
				if String(a).is_valid_int() and int(a) >= 0 and int(a) < _sorted_vids().size():
					vids.append(_sorted_vids()[int(a)])
			if vids.is_empty():
				return "no such item\n"
			for vid in vids:
				if not dev.vlans.has(vid):
					return "no such item\n"
				var err := _apply_vlan_ports(vid, String(p.get("tagged", "")), String(p.get("untagged", "")))
				if err != "":
					return err
			Game.topology_changed.emit()
			return ""
		"interface bridge vlan remove":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			var vids := _vids(String(p.get("vlan-ids", "")))
			if vids.is_empty():
				for a in args:  # by item number, the way print numbers them
					if String(a).is_valid_int() and int(a) >= 0 and int(a) < _sorted_vids().size():
						vids.append(_sorted_vids()[int(a)])
			if vids.is_empty():
				return "no such item\n"
			for vid in vids:
				if not Game.remove_vlan(dev, vid):
					return "failure: vlan %d cannot be removed\n" % vid
			return ""
		"interface bridge vlan print":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			var out := "Flags: D - DYNAMIC\nColumns: BRIDGE, VLAN-IDS, CURRENT-TAGGED, CURRENT-UNTAGGED\n#   BRIDGE   VLAN-IDS  CURRENT-TAGGED           CURRENT-UNTAGGED\n"
			var n := 0
			for vid in _sorted_vids():
					# a multi-valued column prints one value per line, as 7.x does
				var tagged := _tagged_ports(vid)
				var untagged := _untagged_ports(vid)
				var rows := maxi(1, maxi(tagged.size(), untagged.size()))
				for k in rows:
					if k == 0:
						out += "%-2d%s %-8s %8d  %-24s %s\n" % [n, "D" if vid == 1 else " ", BRIDGE, vid,
							tagged[0] if not tagged.is_empty() else "", untagged[0] if not untagged.is_empty() else ""]
					else:
						out += "%-23s %-24s %s\n" % ["", tagged[k] if k < tagged.size() else "", untagged[k] if k < untagged.size() else ""]
				n += 1
			return out
		"interface bridge port add", "interface bridge port set":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			var i := _target(args, p)
			if i == null:
				return "input does not match any value of interface\n" if path.ends_with("add") else "no such item\n"
			if p.has("bridge") and String(p["bridge"]) != BRIDGE:
				return "input does not match any value of bridge\n"
			if p.has("pvid"):
				if not String(p["pvid"]).is_valid_int() or int(p["pvid"]) < 1 or int(p["pvid"]) > 4094:
					return "invalid value for argument pvid\n"
				var vid := int(p["pvid"])
				if not dev.vlans.has(vid):
					Game.add_vlan(dev, vid, "")
				if i.mode == "trunk":
					i.untagged_vlan = vid  # the untagged VLAN of a tagged port
				else:
					Game.set_access_vlan(i, vid)
			if p.has("disabled"):
				_set_disabled(i, String(p["disabled"]) == "yes")
			Game.topology_changed.emit()
			return ""
		"interface bridge port disable", "interface bridge port enable":
			var i := _target(args, p)
			if i == null:
				return "no such item\n"
			_set_disabled(i, path.ends_with("disable"))
			return ""
		"interface bridge port print":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			var out := "Flags: I - INACTIVE; H - HW-OFFLOAD\nColumns: INTERFACE, BRIDGE, HW, PVID, PRIORITY, PATH-COST, INTERNAL-PATH-COST, HORIZON\n#     INTERFACE  BRIDGE   HW   PVID  PRIORITY  PATH-COST  INTERNAL-PATH-COST  HORIZON\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if not _bridge_member(i):
					continue
				out += "%-2d %s%s %-10s %-8s yes  %4d  0x80             10                  10  none\n" % [n,
					" " if i.enabled else "I", "H", i.name, BRIDGE, i.untagged_vlan]
				n += 1
			return out
		"interface bridge port monitor":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			var only := _target(args, p)
			var out := ""
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if not _bridge_member(i) or (only != null and i != only):
					continue
				var role := "disabled-port"
				if i.enabled:
					role = "%s-port" % Sim.stp_role(i)
				var blocked := role == "alternate-port"
				var l := Game.link_at(i)
				var edge := l != null and l.other(i).dev.type != "switch"
				out += "            interface: %s\n               status: %s\n          port-number: %d\n                 role: %s\n            edge-port: %s\n  edge-port-discovery: yes\n  point-to-point-port: yes\n         external-fdb: no\n         sending-rstp: %s\n             learning: %s\n           forwarding: %s\n\n" % [
					i.name, "in-bridge" if i.enabled else "inactive", n + 1, role,
					"yes" if edge else "no", "yes" if dev.stp_mode != "stp" else "no",
					"no" if blocked else "yes", "no" if blocked or not i.enabled else "yes"]
				n += 1
			return out
		"interface bridge host print":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			var out := "Flags: D - DYNAMIC\nColumns: MAC-ADDRESS, VID, ON-INTERFACE, BRIDGE\n#    MAC-ADDRESS        VID  ON-INTERFACE  BRIDGE\n"
			var vids := dev.mac_table.keys()
			vids.sort()
			var n := 0
			for vid in vids:
				for mac in dev.mac_table[vid]:
					out += "%-2d D %-18s %-4d %-13s %s\n" % [n, mac, vid, dev.mac_table[vid][mac].name, BRIDGE]
					n += 1
			return out if n > 0 else _empty("Flags: D - DYNAMIC\n")
		"ipv6 address add":
			if dev.type == "switch":
				return "failure: this switch has no L3 support\n"
			if not p.has("address"):
				return "value of address must be specified\n"
			if not p.has("interface") or _iface(p["interface"]) == null:
				return "input does not match any value of interface\n"
			if Game.add_ip(_iface(p["interface"]), p["address"]):
				return ""
			return "invalid value for argument address\n"
		"ipv6 address remove":
			var n := 0
			for i: Net.Iface in dev.ifaces:
				for cidr in i.ips.duplicate():
					if not Net.is_v6(cidr):
						continue
					if String(p.get("address", "")) == String(cidr) or str(n) in args:
						Game.remove_ip(i, cidr)
						return ""
					n += 1
			return "no such item\n"
		"ipv6 address print":
			var out := "Flags: D - DYNAMIC; G - GLOBAL, L - LINK-LOCAL\nColumns: ADDRESS, FROM-POOL, INTERFACE, ADVERTISE\n#    ADDRESS                        FROM-POOL  INTERFACE  ADVERTISE\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				var has_v6 := i.ra
				for cidr in i.ips:
					if Net.is_v6(cidr):
						has_v6 = true
				if not has_v6:
					continue
				out += "%-2d DL %-30s %-10s %-10s no\n" % [n, "fe80::%s/64" % Net.eui64(i.mac), "", _dname(i)]
				n += 1
				for cidr in i.ips:
					if Net.is_v6(cidr):
						out += "%-2d  G %-30s %-10s %-10s %s\n" % [n, cidr, "", _dname(i), "yes" if i.ra else "no"]
						n += 1
			return out
		"ipv6 nd add", "ipv6 nd set":
			var i := _target(args, p)
			if i == null or not dev.ip_forwarding:
				return "input does not match any value of interface\n"
			i.ra = String(p.get("disabled", "no")) != "yes"
			Game.topology_changed.emit()
			return ""
		"ipv6 nd remove":
			var i := _target(args, p)
			if i == null:
				return "no such item\n"
			i.ra = false
			Game.topology_changed.emit()
			return ""
		"ipv6 nd print":
			var out := "Flags: X - disabled, I - invalid; D - dynamic\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if i.ra:
					out += " %d   interface=%s ra-interval=3m20s-10m ra-lifetime=30m ra-delay=3s mtu=unspecified reachable-time=unspecified retransmit-interval=unspecified ra-preference=medium hop-limit=unspecified advertise-mac-address=yes advertise-dns=yes managed-address-configuration=no other-configuration=no\n" % [n, i.name]
					n += 1
			return out
		"ip address add":
			if dev.type == "switch" and not String(p.get("interface", "")).begins_with("Management"):
				return "failure: PacketTik switches route nothing (only the Management port takes an address)\n"
			if not p.has("address"):
				return "value of address must be specified\n"
			if _vrrp_iface(String(p.get("interface", ""))) != null:
				# the virtual address lives on the vrrp interface, RouterOS style
				var vi := _vrrp_iface(String(p["interface"]))
				var vip := String(p["address"]).split("/")[0]
				if not Net.valid_cidr(vip + "/32"):
					return "invalid value for argument address\n"
				vi.vrrp["vip"] = vip
				Game.topology_changed.emit()
				return ""
			if not p.has("interface") or _iface(p["interface"]) == null:
				return "input does not match any value of interface\n"
			for i: Net.Iface in dev.ifaces:
				if String(p["address"]) in i.ips:
					return "failure: already have such address\n"
			if Game.add_ip(_iface(p["interface"]), p["address"]):
				return ""
			return "invalid value for argument address\n"
		"ip address remove":
			var n := 0
			for i: Net.Iface in dev.ifaces:
				for cidr in i.ips.duplicate():
					if Net.is_v6(cidr):
						continue
					if String(p.get("address", "")) == String(cidr) or str(n) in args:
						Game.remove_ip(i, cidr)
						return ""
					n += 1
			return "no such item\n"
		"ip address set":
			var n := 0
			for i: Net.Iface in dev.ifaces:
				for cidr in i.ips.duplicate():
					if Net.is_v6(cidr):
						continue
					if str(n) in args:
						var to: Net.Iface = _iface(String(p.get("interface", i.name)))
						if to == null:
							return "input does not match any value of interface\n"
						Game.remove_ip(i, cidr)
						if not Game.add_ip(to, String(p.get("address", cidr))):
							Game.add_ip(i, cidr)
							return "invalid value for argument address\n"
						return ""
					n += 1
			return "no such item\n"
		"ip address print":
			var out := "Columns: ADDRESS, NETWORK, INTERFACE\n#   ADDRESS            NETWORK          INTERFACE\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				for cidr in i.ips:
					if Net.is_v6(cidr):
						continue
					out += "%-3d %-18s %-16s %s\n" % [n, cidr, Net.network_of(cidr)["prefix"], _dname(i)]
					n += 1
				if not i.vrrp.is_empty() and String(i.vrrp.get("vip", "")) != "":
					out += "%-3d %-18s %-16s vrrp%d\n" % [n, i.vrrp["vip"] + "/32", i.vrrp["vip"], int(i.vrrp["group"])]
					n += 1
			return out
		"ip arp print":
			var out := "Flags: D - DYNAMIC; C - COMPLETE\nColumns: ADDRESS, MAC-ADDRESS, INTERFACE\n#    ADDRESS         MAC-ADDRESS        INTERFACE\n"
			var n := 0
			for ip in dev.arp:
				out += "%d DC %-15s %-18s %s\n" % [n, ip, dev.arp[ip], CLI.arp_iface_name(dev, String(ip))]
				n += 1
			return out if n > 0 else _empty("Flags: D - DYNAMIC; C - COMPLETE\n")
		"system tech-support", "system sup-output":
			# PacketTik's readable bundle; a real box writes supout.rif for the vendor
			var out := "===== tech-support: %s at cycle %d =====\n" % [dev.name, Game.cycle]
			out += "\n/interface print\n" + exec("/interface print")
			out += "\n/ip address print\n" + exec("/ip address print")
			out += "\n/ip route print\n" + exec("/ip route print")
			out += "\n/ip arp print\n" + exec("/ip arp print")
			out += "\nconfiguration: saved (RouterOS writes every change to flash)\n"
			out += "\nlog\n"
			for log_line: String in dev.logs.slice(maxi(0, dev.logs.size() - 12)):
				out += log_line + "\n"
			return out + "===== end tech-support =====\n"
		"ip firewall nat add":
			if dev.type == "switch":
				return "failure: NAT needs a router\n"
			if String(p.get("chain", "")) != "srcnat":
				return "input does not match any value of chain\n"
			if String(p.get("action", "")) != "masquerade":
				return "input does not match any value of action\n"
			if _iface(String(p.get("out-interface", ""))) == null:
				return "input does not match any value of out-interface\n"
			_iface(p["out-interface"]).nat = "outside"
			if not dev.services.has("nat"):
				dev.services["nat"] = {"rules": [], "acls": {}}
			dev.services["nat"]["rules"].append({"kind": "masquerade", "iface": _iface(p["out-interface"]).name})
			Game.topology_changed.emit()
			return ""
		"ip firewall nat remove":
			var rules: Array = dev.services.get("nat", {}).get("rules", [])
			var n := 0
			for rule in rules.duplicate():
				if String(rule.get("kind", "")) != "masquerade":
					continue
				if str(n) in args:
					rules.erase(rule)
					if _iface(String(rule["iface"])) != null:
						_iface(String(rule["iface"])).nat = ""
					Game.topology_changed.emit()
					return ""
				n += 1
			return "no such item\n"
		"ip firewall nat print":
			var out := "Flags: X - disabled, I - invalid; D - dynamic\n"
			var n := 0
			for rule in Sim.nat_rules(dev):
				if String(rule.get("kind", "")) == "masquerade":
					out += " %d   chain=srcnat action=masquerade out-interface=%s\n" % [n, rule["iface"]]
					n += 1
			return out
		"ip firewall address-list add":
			var list_name := String(p.get("list", ""))
			var addr := String(p.get("address", ""))
			if list_name == "":
				return "value of list must be specified\n"
			if not Net.valid_cidr(addr):
				return "invalid value for argument address\n"
			if dev.bgp.is_empty():
				dev.bgp = {"asn": 0, "neighbors": [], "networks": [], "lists": {}}
			if not dev.bgp.has("lists"):
				dev.bgp["lists"] = {}
			if not dev.bgp["lists"].has(list_name):
				dev.bgp["lists"][list_name] = []
			if addr not in dev.bgp["lists"][list_name]:
				dev.bgp["lists"][list_name].append(addr)
			_bgp_sync_networks()
			Game.topology_changed.emit()
			return ""
		"ip firewall address-list remove":
			var lists: Dictionary = dev.bgp.get("lists", {})
			var n := 0
			for lname in lists.keys():
				for addr in Array(lists[lname]).duplicate():
					if str(n) in args or (String(p.get("list", lname)) == String(lname)
							and (not p.has("address") or String(p["address"]) == String(addr))):
						lists[lname].erase(addr)
					n += 1
				if lists[lname].is_empty():
					lists.erase(lname)
			if not dev.bgp.is_empty():
				_bgp_sync_networks()
			Game.topology_changed.emit()
			return ""
		"ip firewall address-list print":
			var lists: Dictionary = dev.bgp.get("lists", {})
			var out := "Flags: X - disabled, D - dynamic\nColumns: LIST, ADDRESS, CREATION-TIME\n#   LIST        ADDRESS            CREATION-TIME\n"
			var n := 0
			for lname in lists:
				for addr in lists[lname]:
					out += "%-3d %-11s %-18s %s\n" % [n, lname, addr, Time.get_datetime_string_from_system(false, true).replace("T", " ")]
					n += 1
			return out if n > 0 else _empty("Flags: X - disabled, D - dynamic\n")
		"ip route add":
			var dst: String = p.get("dst-address", "0.0.0.0/0")
			var ad := 1
			if p.has("distance"):
				if not String(p["distance"]).is_valid_int():
					return "invalid value for argument distance\n"
				ad = clampi(int(p["distance"]), 1, 255)
			if not p.has("gateway"):
				return "value of gateway must be specified\n"
			if not Net.valid_cidr(dst):
				return "invalid value for argument dst-address\n"
			var parts := dst.split("/")
			if Game.add_static_route(dev, parts[0], int(parts[1]), p["gateway"], "", ad):
				return ""
			return "invalid value for argument gateway\n"
		"ip route remove", "ip route set":
			var dst2: String = p.get("dst-address", "") if path.ends_with("remove") else ""
			var chosen := {}
			var n := 0
			for e in _route_rows():
				if e["src"] != "S":
					continue
				if str(n) in args or (dst2 != "" and dst2 == "%s/%d" % [e["prefix"], int(e["plen"])]):
					chosen = e
					break
				n += 1
			if chosen.is_empty():
				return "no such item\n"
			Game.remove_static_route(dev, chosen["prefix"], int(chosen["plen"]))
			if path.ends_with("set"):
				var dst3 := String(p.get("dst-address", "%s/%d" % [chosen["prefix"], int(chosen["plen"])]))
				var parts := dst3.split("/")
				var ad := int(p["distance"]) if String(p.get("distance", "")).is_valid_int() else int(chosen["ad"])
				if not Net.valid_cidr(dst3) or not Game.add_static_route(dev, parts[0], int(parts[1]),
						String(p.get("gateway", chosen["next_hop"])), "", ad):
					Game.add_static_route(dev, chosen["prefix"], int(chosen["plen"]), chosen["next_hop"], "", int(chosen["ad"]))
					return "invalid value for argument gateway\n"
			return ""
		"ip route print":
			var out := "Flags: D - DYNAMIC; A - ACTIVE; c - CONNECT, s - STATIC, o - OSPF, b - BGP\nColumns: DST-ADDRESS, GATEWAY, DISTANCE\n#      DST-ADDRESS        GATEWAY          DISTANCE\n"
			var n := 0
			for e in _route_rows():
				var flags := ("D" if e["src"] != "S" else " ") + ("A" if bool(e["active"]) else " ") + String(e["src"]).to_lower()
				var gw: String = e["iface"].name if e["src"] == "C" else String(e["next_hop"])
				# only what somebody added has a number; dynamic routes cannot be addressed
				var num := ""
				if e["src"] == "S":
					num = str(n)
					n += 1
				out += "%-2s %3s %-18s %-16s %8d\n" % [num, flags, "%s/%d" % [e["prefix"], int(e["plen"])], gw, int(e["ad"])]
			return out
		"routing ospf instance add":
			if not dev.ip_forwarding:
				return "failure: OSPF needs a router\n"
			if not p.has("name"):
				return "value of name must be specified\n"
			if dev.ospf.is_empty():
				dev.ospf = {"networks": [], "areas": {}}
			dev.ospf["instance"] = String(p["name"])
			if p.has("router-id"):
				dev.ospf["router_id"] = String(p["router-id"])
			Game.topology_changed.emit()
			return ""
		"routing ospf instance remove":
			if dev.ospf.is_empty():
				return "no such item\n"
			dev.ospf = {}
			Game.topology_changed.emit()
			return ""
		"routing ospf instance print":
			if dev.ospf.is_empty():
				return _empty("Flags: X - disabled\n")
			return "Flags: X - disabled\n 0   name=\"%s\" version=2 vrf=main router-id=%s\n" % [dev.ospf.get("instance", "default"),
				dev.ospf.get("router_id", _first_ip())]
		"routing ospf area add":
			if dev.ospf.is_empty():
				return "input does not match any value of instance\n"
			if not p.has("name"):
				return "value of name must be specified\n"
			dev.ospf["areas"][String(p["name"])] = String(p.get("area-id", "0.0.0.0"))
			return ""
		"routing ospf area remove":
			var areas: Dictionary = dev.ospf.get("areas", {})
			var n := 0
			for a in areas.keys():
				if String(p.get("name", "")) == String(a) or str(n) in args:
					areas.erase(a)
					return ""
				n += 1
			return "no such item\n"
		"routing ospf area print":
			var areas: Dictionary = dev.ospf.get("areas", {})
			if areas.is_empty():
				return _empty("Flags: X - disabled\n")
			var out := "Flags: X - disabled\nColumns: NAME, INSTANCE, AREA-ID\n#   NAME      INSTANCE  AREA-ID\n"
			var n := 0
			for a in areas:
				out += "%-3d %-9s %-9s %s\n" % [n, a, dev.ospf.get("instance", "default"), areas[a]]
				n += 1
			return out
		"routing ospf interface-template add":
			if dev.ospf.is_empty():
				return "input does not match any value of area\n"
			var area := String(p.get("area", ""))
			if not dev.ospf.get("areas", {}).has(area):
				return "input does not match any value of area\n"
			var nets := Array(String(p.get("networks", "")).split(",", false))
			if nets.is_empty() and not p.has("interfaces"):
				return "value of networks must be specified\n"
			for net in nets:
				if not Net.valid_cidr(String(net)):
					return "invalid value for argument networks\n"
			for ifn in String(p.get("interfaces", "")).split(",", false):
				var i := _iface(ifn)
				if i == null:
					return "input does not match any value of interfaces\n"
				for cidr in i.ips:  # interfaces= is the other spelling of the same thing
					if not Net.is_v6(cidr):
						nets.append(String(Net.network_of(cidr)["prefix"]) + "/" + String(cidr).split("/")[1])
			for net in nets:
				if net not in dev.ospf["networks"]:
					dev.ospf["networks"].append(net)
			Game.topology_changed.emit()
			return ""
		"routing ospf interface-template remove":
			if dev.ospf.is_empty():
				return "no such item\n"
			for net in String(p.get("networks", "")).split(",", false):
				dev.ospf["networks"].erase(net)
			for a in args:
				if String(a).is_valid_int() and int(a) >= 0 and int(a) < dev.ospf["networks"].size():
					dev.ospf["networks"].remove_at(int(a))
					break
			Game.topology_changed.emit()
			return ""
		"routing ospf interface-template print":
			if dev.ospf.is_empty() or dev.ospf.get("networks", []).is_empty():
				return _empty("Flags: X - disabled, I - inactive\n")
			var out := "Flags: X - disabled, I - inactive\n"
			var n := 0
			for net in dev.ospf["networks"]:
				out += " %d   area=%s networks=%s cost=1 priority=128 type=broadcast auth=none\n" % [n, _area_name(), net]
				n += 1
			return out
		"routing ospf neighbor print":
			if dev.ospf.is_empty():
				return ""
			var out := ""
			var seen := {}
			var n := 0
			for nb in Sim.ospf_neighbors(dev):
				if seen.has(nb["dev"]):
					continue
				seen[nb["dev"]] = true
				var rid: String = Sim.ospf_router_id(nb["dev"])
				var roles := Sim.ospf_segment_roles(dev, nb["iface"])
				var role := ""
				if not bool(roles.get("p2p", false)):
					role = " dr=%s bdr=%s" % [_segment_ip(roles.get("dr"), nb), _segment_ip(roles.get("bdr"), nb)]
				out += " %d D instance=%s area=%s address=%s priority=128 router-id=%s%s state=\"Full\" state-changes=5 adjacency=%s timeout=37s\n" % [
					n, dev.ospf.get("instance", "default"), _area_name(), nb["via_ip"], rid, role, _uptime()]
				n += 1
			return ("Flags: V - virtual; D - dynamic\n" + out) if n > 0 else ""
		"routing bgp template set":
			if dev.type != "router":
				return "failure: BGP needs a router\n"
			if not p.has("as"):
				return "value of as must be specified\n"
			if not String(p["as"]).is_valid_int():
				return "invalid value for argument as\n"
			if dev.bgp.is_empty():
				dev.bgp = {"asn": int(p["as"]), "neighbors": [], "networks": [], "lists": {}}
			else:
				dev.bgp["asn"] = int(p["as"])
			if p.has("router-id"):
				dev.bgp["router_id"] = String(p["router-id"])
			Game.topology_changed.emit()
			return ""
		"routing bgp template print":
			if dev.bgp.is_empty():
				return _empty("Flags: X - disabled, I - inactive\n")
			return "Flags: X - disabled, I - inactive\n 0   name=\"default\" as=%d%s\n" % [int(dev.bgp["asn"]),
				(" router-id=%s" % dev.bgp["router_id"]) if dev.bgp.has("router_id") else ""]
		"routing bgp connection add":
			if dev.type != "router":
				return "failure: BGP needs a router\n"
			if not p.has("remote.address"):
				return "value of remote.address must be specified\n"
			if not String(p.get("remote.as", "")).is_valid_int():
				return "invalid value for argument remote.as\n" if p.has("remote.as") else "value of remote.as must be specified\n"
			var asn := int(dev.bgp.get("asn", 0)) if not dev.bgp.is_empty() else 0
			if String(p.get("as", "")).is_valid_int():
				asn = int(p["as"])
			if asn <= 0:
				return "failure: no local AS: give as=<asn> here or /routing bgp template set default as=<asn>\n"
			if dev.bgp.is_empty():
				dev.bgp = {"asn": asn, "neighbors": [], "networks": [], "lists": {}}
			dev.bgp["asn"] = asn
			var nb := {"ip": String(p["remote.address"]), "remote_as": int(p["remote.as"]),
				"local_pref": 100, "prepend": 0, "prefix_in": [], "prefix_out": [],
				"name": String(p.get("name", "peer%d" % (dev.bgp["neighbors"].size() + 1))),
				"out_list": String(p.get("output.network", ""))}
			for existing in dev.bgp["neighbors"].duplicate():
				if String(existing["ip"]) == nb["ip"]:
					dev.bgp["neighbors"].erase(existing)
			dev.bgp["neighbors"].append(nb)
			_bgp_sync_networks()
			Game.topology_changed.emit()
			return ""
		"routing bgp connection remove":
			if dev.bgp.is_empty():
				return "no such item\n"
			var n := 0
			for nb in dev.bgp["neighbors"].duplicate():
				if String(nb.get("name", "")) == String(p.get("name", "")) or str(n) in args:
					dev.bgp["neighbors"].erase(nb)
					_bgp_sync_networks()
					Game.topology_changed.emit()
					return ""
				n += 1
			return "no such item\n"
		"routing bgp connection print":
			if dev.bgp.is_empty() or dev.bgp["neighbors"].is_empty():
				return _empty("Flags: X - disabled, I - inactive\n")
			var out := "Flags: X - disabled, I - inactive\n"
			var n := 0
			for nb in dev.bgp["neighbors"]:
				out += " %d   name=\"%s\" remote.address=%s .as=%d local.role=ebgp as=%d%s\n" % [n,
					nb.get("name", "peer"), nb["ip"], int(nb["remote_as"]), int(dev.bgp["asn"]),
					(" output.network=%s" % nb["out_list"]) if String(nb.get("out_list", "")) != "" else ""]
				n += 1
			return out
		"routing bgp session print":
			if dev.bgp.is_empty() or dev.bgp["neighbors"].is_empty():
				return _empty("Flags: E - established\n")
			var out := "Flags: E - established\n"
			var n := 0
			for nb in dev.bgp["neighbors"]:
				if not Sim.bgp_established(dev, nb):
					continue  # a session that never came up is not a session yet
				out += " %d E name=\"%s-1\" remote.address=%s .as=%d .id=%s .capabilities=mp,rr,gr,as4 .afi=ip .messages=%d .bytes=%d .eor=\"\"\n     local.role=ebgp .address=%s .as=%d .id=%s .capabilities=mp,rr,gr,as4 .messages=%d .bytes=%d .eor=\"\"\n     output.procid=20 .keep-sent-attributes=no\n     input.procid=20 ebgp\n     hold-time=3m keepalive-time=1m uptime=%s\n" % [n,
					nb.get("name", "peer"), nb["ip"], int(nb["remote_as"]), nb["ip"], Game.cycle + 3, (Game.cycle + 3) * 19,
					_local_addr_toward(String(nb["ip"])), int(dev.bgp["asn"]), dev.bgp.get("router_id", _first_ip()),
					Game.cycle + 4, (Game.cycle + 4) * 19, _uptime()]
				n += 1
			return out
		"routing bgp advertisements print":
			if dev.bgp.is_empty():
				return ""
			var out := ""
			var n := 0
			for nb in dev.bgp["neighbors"]:
				if not Sim.bgp_established(dev, nb):
					continue
				for net in dev.bgp["networks"]:
					out += " %d peer=%s-1 dst=%s afi=ip nexthop=%s origin=igp as-path=\"\"\n" % [n, nb.get("name", "peer"), net,
						_local_addr_toward(String(nb["ip"]))]
					n += 1
			return out
	return null

func _ros_dhcp_assemble() -> void:
	## pool + server + network together make the service this world serves
	var rd: Dictionary = dev.services.get("ros_dhcp", {})
	var srv: Dictionary = rd.get("server", {})
	var nw: Dictionary = rd.get("network", {})
	var pool: Array = rd.get("pools", {}).get(String(srv.get("pool", "")), [])
	if srv.is_empty() or nw.is_empty() or pool.is_empty() or bool(srv.get("disabled", false)):
		return
	var netw := Net.network_of(String(nw["address"]))
	var iface := String(srv.get("iface", ""))
	dev.services["dhcp"] = {"iface": "" if iface == BRIDGE else iface, "start": String(pool[0]), "end": String(pool[1]),
		"plen": int(netw["plen"]), "gw": String(nw.get("gw", "")), "dns": String(nw.get("dns", "")),
		"leases": dev.services.get("dhcp", {}).get("leases", {}), "since": dev.services.get("dhcp", {}).get("since", {}), "excluded": [], "running": true}
	Game.topology_changed.emit()

func _ros_filter_apply() -> void:
	## forward-chain rules filter what crosses the router: they become this
	## world's access list on every port; input-chain rules are kept for print
	dev.acls = dev.acls.filter(func(rule): return String(rule.get("list", "")) != "ros-forward")
	var seq := 10
	var any := false
	for rule in dev.services.get("ros_filter", []):
		if String(rule["chain"]) != "forward":
			continue
		any = true
		var entry := {"action": "permit" if String(rule["action"]) in ["accept", "fasttrack-connection", "passthrough"] else "deny",
			"src": "0.0.0.0", "splen": 0, "dst": "0.0.0.0", "dplen": 0, "list": "ros-forward", "seq": seq}
		seq += 10
		for side in [["src-address", "src", "splen"], ["dst-address", "dst", "dplen"]]:
			if rule.has(side[0]):
				var cidr := String(rule[side[0]])
				if "/" not in cidr:
					cidr += "/32"
				if Net.valid_cidr(cidr):
					entry[side[1]] = cidr.split("/")[0]
					entry[side[2]] = int(cidr.split("/")[1])
		if rule.has("protocol") and String(rule["protocol"]) in ["tcp", "udp", "icmp"]:
			entry["proto"] = String(rule["protocol"])
		if rule.has("dst-port") and String(rule["dst-port"]).is_valid_int():
			entry["port"] = int(rule["dst-port"])
		if String(rule.get("connection-state", "")).contains("established"):
			entry["established"] = true
		dev.acls.append(entry)
	var groups: Dictionary = dev.services.get("acl_groups", {})
	for i: Net.Iface in dev.ifaces:
		if any:
			groups[i.name] = "ros-forward"
		elif String(groups.get(i.name, "")) == "ros-forward":
			groups.erase(i.name)
	dev.services["acl_groups"] = groups
	Game.topology_changed.emit()

func _run_flag(i: Net.Iface) -> String:
	return "X" if i.admin_down else ("R" if i.enabled and Game.link_at(i) else " ")

func _set_disabled(i: Net.Iface, off: bool) -> void:
	i.admin_down = off
	if off:
		i.enabled = false
	else:
		i.err_disabled = false
		i.enabled = i.fault == ""
	Game.topology_changed.emit()

func _bond_groups() -> Dictionary:
	var groups := {}
	for i: Net.Iface in dev.ifaces:
		if i.lag > 0:
			if not groups.has(i.lag):
				groups[i.lag] = []
			groups[i.lag].append(i.name)
	return groups

func _bridge_mac() -> String:
	for i: Net.Iface in dev.ifaces:
		if _bridge_member(i):
			return i.mac
	return "00:00:00:00:00:00"

func _interface_print() -> String:
	## the bridge, the ports, the bonds and the vlans as one list; a port in
	## a bridge or a bond is a slave; the legend names only the flags in use
	var rows: Array = []
	if dev.type == "switch":
		rows.append(["R", " ", BRIDGE, "bridge", 1500, "1592", _bridge_mac()])
	var groups := _bond_groups()
	for i: Net.Iface in dev.ifaces:
		var slave := "S" if i.lag > 0 or _bridge_member(i) else " "
		var l2 := "1598" if i.parent == "" else "1594"
		if i.name.begins_with("wg"):
			l2 = ""
		rows.append([_run_flag(i), slave, _dname(i), _itype(i), i.mtu, l2, i.mac])
	for g in groups:
		rows.append(["R", " ", "bond%d" % g, "bond", 1500, "1598", _iface(groups[g][0]).mac])
	var used := {}
	for r in rows:
		used[r[0]] = true
		used[r[1]] = true
	# X and R share the first flag column, S has its own: ", " inside a column, "; " between
	var first: Array = []
	for f in [["X", "DISABLED"], ["R", "RUNNING"]]:
		if used.has(f[0]):
			first.append("%s - %s" % [f[0], f[1]])
	var groups_text: Array = []
	if not first.is_empty():
		groups_text.append(", ".join(PackedStringArray(first)))
	if used.has("S"):
		groups_text.append("S - SLAVE")
	var out := ""
	if not groups_text.is_empty():
		out += "Flags: %s\n" % "; ".join(PackedStringArray(groups_text))
	out += "Columns: NAME, TYPE, ACTUAL-MTU, L2MTU, MAC-ADDRESS\n#     NAME         TYPE       ACTUAL-MTU  L2MTU  MAC-ADDRESS\n"
	var n := 0
	for r in rows:
		out += "%-2d %s%s %-12s %-10s %10d  %5s  %s\n" % [n, r[0], r[1], r[2], r[3], r[4], r[5], r[6]]
		n += 1
	return out

func _segment_ip(d: Variant, nb: Dictionary) -> String:
	## the address a DR or BDR has on the segment the neighbour was heard on
	if d == null:
		return "0.0.0.0"
	if d == dev:
		var mine: Net.Iface = nb["iface"]
		for cidr in mine.ips:
			if not Net.is_v6(cidr):
				return String(cidr).split("/")[0]
	if d == nb["dev"]:
		return String(nb["via_ip"])
	for i: Net.Iface in (d as Net.NDevice).ifaces:
		for cidr in i.ips:
			if not Net.is_v6(cidr) and Net.same_net(String(nb["via_ip"]), String(cidr).split("/")[0], int(String(cidr).split("/")[1])):
				return String(cidr).split("/")[0]
	return "0.0.0.0"

func _first_ip() -> String:
	for i: Net.Iface in dev.ifaces:
		for cidr in i.ips:
			if not Net.is_v6(cidr):
				return String(cidr).split("/")[0]
	return "0.0.0.0"

func _local_addr_toward(peer_ip: String) -> String:
	for i: Net.Iface in dev.ifaces:
		for cidr in i.ips:
			if not Net.is_v6(cidr) and Net.same_net(peer_ip, String(cidr).split("/")[0], int(String(cidr).split("/")[1])):
				return String(cidr).split("/")[0]
	return "-"

func _area_name() -> String:
	for a in dev.ospf.get("areas", {}):
		return String(a)
	return "backbone"

func _bgp_sync_networks() -> void:
	## what gets announced is the union of every address-list a connection
	## names in output.network: the RouterOS 7 way of saying 'network'
	var nets: Array = []
	var lists: Dictionary = dev.bgp.get("lists", {})
	for nb in dev.bgp.get("neighbors", []):
		for addr in lists.get(String(nb.get("out_list", "")), []):
			if addr not in nets:
				nets.append(addr)
	dev.bgp["networks"] = nets

func _route_rows() -> Array:
	## the installed table first, then statics that lost (present, not active)
	var rows: Array = []
	for e in Sim.rib(dev):
		if String(e["vrf"]) != "":
			continue
		var row: Dictionary = e.duplicate()
		row["active"] = true
		rows.append(row)
	for r in dev.static_routes:
		var installed := false
		for e in rows:
			if e["src"] == "S" and String(e["prefix"]) == String(r["prefix"]) and int(e["plen"]) == int(r["plen"]) \
					and String(e["next_hop"]) == String(r["via"]):
				installed = true
		if not installed:
			rows.append({"src": "S", "prefix": r["prefix"], "plen": int(r["plen"]), "next_hop": r["via"],
				"ad": int(r.get("ad", 1)), "iface": null, "active": false})
	return rows

const PATHS := ["help", "export", "ping", "tool traceroute", "tool torch", "tool sniffer quick",
	"ip pool add", "ip pool print", "ip dhcp-server add", "ip dhcp-server network add", "ip dhcp-server network print", "ip dhcp-server setup",
	"ip dhcp-client add", "ip firewall filter add", "ip firewall filter remove",
	"user add", "user set", "user remove", "password", "ip service set", "ip service disable", "ip service enable",
	"interface list add", "interface list member add", "interface list print", "interface list member print",
	"interface monitor-traffic", "system ntp client set", "system ntp client print", "system logging print",
	"routing route print", "interface bridge settings print", "ip neighbor print", "ip neighbor discovery-settings print",
	"system ssh", "quit",
	"system backup save", "system backup load", "system reboot", "file print",
	"system identity set", "system identity print", "system resource print", "system clock print",
	"system package print", "system tech-support", "system sup-output", "log print", "user print",
	"snmp set", "snmp print", "snmp community set", "snmp community add", "snmp community print",
	"ip traffic-flow print", "ip service print", "ip dns print", "ip dns set", "ip dns cache print",
	"ip dhcp-server print", "ip dhcp-server lease print", "ip dhcp-client print",
	"ip firewall filter print", "ip firewall connection print",
	"routing bfd configuration add", "routing bfd configuration remove", "routing bfd configuration print",
	"routing bfd session print",
	"interface print", "interface print stats", "interface set", "interface disable", "interface enable",
	"interface ethernet print", "interface ethernet set", "interface ethernet monitor",
	"interface vlan add", "interface vlan remove", "interface vlan print",
	"interface vrrp add", "interface vrrp remove", "interface vrrp print",
	"interface wireguard add", "interface wireguard remove", "interface wireguard print",
	"interface wireguard peers add", "interface wireguard peers remove", "interface wireguard peers print",
	"interface bonding add", "interface bonding remove", "interface bonding print",
	"interface bridge add", "interface bridge set", "interface bridge print",
	"interface bridge vlan add", "interface bridge vlan set", "interface bridge vlan remove", "interface bridge vlan print",
	"interface bridge port add", "interface bridge port set", "interface bridge port disable",
	"interface bridge port enable", "interface bridge port print",
	"interface bridge port monitor", "interface bridge host print",
	"ip address add", "ip address remove", "ip address set", "ip address print", "ip arp print",
	"ipv6 address add", "ipv6 address remove", "ipv6 address print",
	"ipv6 nd add", "ipv6 nd set", "ipv6 nd remove", "ipv6 nd print",
	"ip route add", "ip route remove", "ip route set", "ip route print",
	"ip firewall nat add", "ip firewall nat remove", "ip firewall nat print",
	"ip firewall address-list add", "ip firewall address-list remove", "ip firewall address-list print",
	"routing ospf instance add", "routing ospf instance remove", "routing ospf instance print",
	"routing ospf area add", "routing ospf area remove", "routing ospf area print",
	"routing ospf interface-template add", "routing ospf interface-template remove",
	"routing ospf interface-template print", "routing ospf neighbor print",
	"routing bgp template set", "routing bgp template print",
	"routing bgp connection add", "routing bgp connection remove",
	"routing bgp connection print", "routing bgp session print", "routing bgp advertisements print"]

## The parameters each menu knows. A name outside its list is a syntax error
## at that column, which is what stops a learner shipping "addres=".
const PARAMS := {
	"ping": ["address", "count", "size", "interval", "ttl", "src-address", "interface"],
	"ip pool add": ["name", "ranges", "next-pool", "comment"],
	"ip dhcp-server add": ["name", "interface", "address-pool", "lease-time", "disabled", "authoritative", "comment"],
	"ip dhcp-server network add": ["address", "gateway", "dns-server", "netmask", "domain", "ntp-server", "comment"],
	"ip dhcp-client add": ["interface", "use-peer-dns", "use-peer-ntp", "add-default-route", "disabled", "comment"],
	"ip firewall filter add": ["chain", "action", "protocol", "src-address", "dst-address", "dst-port", "src-port", "in-interface", "out-interface", "in-interface-list", "out-interface-list", "connection-state", "comment", "disabled", "log", "log-prefix", "jump-target", "src-address-list", "dst-address-list"],
	"user add": ["name", "group", "password", "comment", "disabled"],
	"user set": ["name", "group", "password", "comment", "disabled"],
	"ip service set": ["port", "address", "disabled", "certificate"],
	"interface list add": ["name", "comment", "include", "exclude"],
	"interface list member add": ["list", "interface", "comment", "disabled"],
	"interface monitor-traffic": ["interface", "once", "duration"],
	"system ntp client set": ["enabled", "servers", "mode", "vrf"],
	"tool traceroute": ["address", "count", "size", "src-address", "max-hops", "protocol"],
	"tool torch": ["interface", "src-address", "dst-address", "port", "protocol"],
	"tool sniffer quick": ["interface", "ip-address", "ip-protocol", "port"],
	"system identity set": ["name"],
	"system backup save": ["name", "password", "dont-encrypt"],
	"system backup load": ["name", "password"],
	"snmp set": ["enabled", "contact", "location", "community", "trap-community", "trap-version", "trap-target"],
	"snmp community set": ["name", "addresses", "security", "read-access", "write-access", "default"],
	"snmp community add": ["name", "addresses", "security", "read-access", "write-access"],
	"ip dns set": ["servers", "allow-remote-requests", "cache-size"],
	"routing bfd configuration add": ["interfaces", "disabled", "addresses", "min-rx", "min-tx", "multiplier"],
	"routing bfd configuration remove": ["interfaces"],
	"interface set": ["disabled", "mtu", "arp", "name", "comment", "l2mtu"],
	"interface ethernet set": ["disabled", "mtu", "arp", "name", "comment", "l2mtu", "default-name", "speed", "auto-negotiation"],
	"interface vlan add": ["name", "vlan-id", "interface", "mtu", "arp", "disabled", "comment", "use-service-tag"],
	"interface vlan remove": ["name"],
	"interface vrrp add": ["name", "interface", "vrid", "priority", "preemption-mode", "interval", "version", "authentication", "password", "comment"],
	"interface vrrp remove": ["name"],
	"interface wireguard add": ["name", "listen-port", "mtu", "private-key", "comment"],
	"interface wireguard remove": ["name"],
	"interface wireguard peers add": ["interface", "public-key", "endpoint-address", "endpoint-port", "allowed-address", "persistent-keepalive", "preshared-key", "comment", "name"],
	"interface wireguard peers remove": ["public-key", "interface"],
	"interface bonding add": ["name", "slaves", "mode", "lacp-rate", "transmit-hash-policy", "mtu", "comment"],
	"interface bonding remove": ["name"],
	"interface bridge add": ["name", "protocol-mode", "vlan-filtering", "priority", "pvid", "frame-types", "ingress-filtering", "comment", "mtu", "arp"],
	"interface bridge set": ["name", "protocol-mode", "vlan-filtering", "priority", "pvid", "frame-types", "ingress-filtering", "comment", "mtu", "arp"],
	"interface bridge vlan add": ["bridge", "vlan-ids", "tagged", "untagged", "comment", "disabled"],
	"interface bridge vlan set": ["bridge", "vlan-ids", "tagged", "untagged", "comment", "disabled"],
	"interface bridge vlan remove": ["vlan-ids", "bridge"],
	"interface bridge port add": ["bridge", "interface", "pvid", "frame-types", "ingress-filtering", "edge", "path-cost", "internal-path-cost", "priority", "horizon", "comment", "disabled", "hw"],
	"interface bridge port set": ["bridge", "interface", "pvid", "frame-types", "ingress-filtering", "edge", "path-cost", "internal-path-cost", "priority", "horizon", "comment", "disabled", "hw"],
	"interface bridge port monitor": ["interface"],
	"ip address add": ["address", "interface", "network", "comment", "disabled"],
	"ip address set": ["address", "interface", "network", "comment", "disabled"],
	"ip address remove": ["address", "interface"],
	"ipv6 address add": ["address", "interface", "advertise", "eui-64", "from-pool", "comment", "disabled"],
	"ipv6 address remove": ["address", "interface"],
	"ipv6 nd add": ["interface", "advertise-dns", "advertise-mac-address", "ra-interval", "ra-lifetime", "disabled", "hop-limit", "mtu"],
	"ipv6 nd set": ["interface", "advertise-dns", "advertise-mac-address", "ra-interval", "ra-lifetime", "disabled", "hop-limit", "mtu"],
	"ipv6 nd remove": ["interface"],
	"ip route add": ["dst-address", "gateway", "distance", "comment", "disabled", "routing-table", "check-gateway", "scope", "target-scope", "pref-src"],
	"ip route set": ["dst-address", "gateway", "distance", "comment", "disabled", "routing-table", "check-gateway", "scope", "target-scope", "pref-src"],
	"ip route remove": ["dst-address", "gateway"],
	"ip firewall nat add": ["chain", "action", "out-interface", "in-interface", "src-address", "dst-address", "to-addresses", "to-ports", "protocol", "dst-port", "comment", "disabled"],
	"ip firewall address-list add": ["list", "address", "comment", "timeout", "disabled"],
	"ip firewall address-list remove": ["list", "address"],
	"routing ospf instance add": ["name", "router-id", "version", "vrf", "redistribute", "originate-default", "comment", "disabled"],
	"routing ospf instance remove": ["name"],
	"routing ospf area add": ["name", "area-id", "instance", "type", "comment", "disabled"],
	"routing ospf area remove": ["name"],
	"routing ospf interface-template add": ["networks", "interfaces", "area", "cost", "priority", "type", "auth", "auth-key", "passive", "comment", "disabled"],
	"routing ospf interface-template remove": ["networks", "interfaces"],
	"routing bgp template set": ["as", "router-id", "name", "disabled", "hold-time", "keepalive-time"],
	"routing bgp connection add": ["name", "remote.address", "remote.as", "remote.port", "local.address", "local.role", "as", "router-id", "templates", "output.network", "output.filter-chain", "input.filter", "hold-time", "keepalive-time", "comment", "disabled", "connect", "listen", "multihop"],
	"routing bgp connection remove": ["name"],
}

## What a learner from the other dialect types by reflex, and where it lives here.
const HINTS := {
	"interface set": {
		"pvid": "VLAN membership lives on the bridge: /interface bridge port set [find interface=X] pvid=N",
		"mode": "there is no port mode: tag it in /interface bridge vlan add tagged=X, untag it with pvid=N",
		"tagged": "tagging is per VLAN: /interface bridge vlan add bridge=bridge1 vlan-ids=N tagged=X",
		"bfd": "BFD is /routing bfd configuration add interfaces=X",
		"ra": "router advertisements are /ipv6 nd add interface=X"},
	"ip address add": {"addres": "address=", "ip": "address=a.b.c.d/len", "mask": "the prefix length rides on the address: a.b.c.d/24"},
	"ip route add": {"via": "gateway=", "dst": "dst-address=", "metric": "distance="},
}

func _is_path_word(prefix: String) -> bool:
	for c in PATHS:
		if c == prefix or c.begins_with(prefix + " "):
			return true
	return false

func _help() -> String:
	var out := ""
	for c in PATHS:
		if cwd == "" or c.begins_with(cwd + " "):
			out += "  /" + c + "\n"
	out += "\nA menu on its own steps into it (/ip address, then print). '..' goes up, '/' goes home.\n"
	return out

func _export() -> String:
	## the configuration as RouterOS 7 exports it: a header, then every menu
	## once with its add/set lines under it. Paste it into a real one.
	var groups := {}  # menu -> lines, in the order the product prints them
	var add := func(menu: String, line: String) -> void:
		if not groups.has(menu):
			groups[menu] = []
		groups[menu].append(line)
	if dev.type == "switch":
		add.call("/interface bridge", "add name=%s protocol-mode=%s vlan-filtering=yes" % [BRIDGE,
			"mstp" if dev.stp_mode == "mst" else dev.stp_mode])
	var bonds := _bond_groups()
	for g in bonds:
		add.call("/interface bonding", "add mode=802.3ad name=bond%d slaves=%s" % [g, ",".join(PackedStringArray(bonds[g]))])
	for i: Net.Iface in dev.ifaces:
		if i.parent != "":
			add.call("/interface vlan", "add interface=%s name=%s vlan-id=%d" % [i.parent, _dname(i), i.dot1q])
	for i: Net.Iface in dev.ifaces:
		if i.name.begins_with("wg"):
			add.call("/interface wireguard", "add listen-port=13231 mtu=1420 name=%s" % i.name)
	for i: Net.Iface in dev.ifaces:
		if not i.vrrp.is_empty():
			# alphabetical, defaults omitted, as compact export prints it
			var vrrp_line := "add interface=%s name=vrrp%d" % [i.name, int(i.vrrp["group"])]
			if not bool(i.vrrp.get("preempt", true)):
				vrrp_line += " preemption-mode=no"
			if int(i.vrrp.get("priority", 100)) != 100:
				vrrp_line += " priority=%d" % int(i.vrrp["priority"])
			if int(i.vrrp["group"]) != 1:
				vrrp_line += " vrid=%d" % int(i.vrrp["group"])
			add.call("/interface vrrp", vrrp_line)
	for i: Net.Iface in dev.ifaces:
		if i.parent != "" or i.name.begins_with("wg"):
			continue
		var settings := ""
		if i.admin_down:
			settings += " disabled=yes"
		if i.name in dev.services.get("proxy_arp_ifaces", []):
			settings += " arp=proxy-arp"
		if settings != "":
			add.call("/interface ethernet", "set [ find default-name=%s ]%s" % [i.name, settings])
	for i: Net.Iface in dev.ifaces:
		for pr in i.wg_peers:
			add.call("/interface wireguard peers", "add allowed-address=%s endpoint-address=%s endpoint-port=13231 interface=%s public-key=\"%s\"" % [
				",".join(PackedStringArray(pr.get("allowed", []))), pr.get("endpoint", ""), i.name, pr.get("key", "")])
	if dev.type == "switch":
		for i: Net.Iface in dev.ifaces:
			if _bridge_member(i):
				add.call("/interface bridge port", "add bridge=%s interface=%s%s" % [BRIDGE, i.name,
					(" pvid=%d" % i.untagged_vlan) if i.untagged_vlan != 1 else ""])
		for vid in _sorted_vids():
			if vid == 1:
				continue
			var tagged := _tagged_ports(vid)
			var untagged := _untagged_ports(vid)
			add.call("/interface bridge vlan", "add bridge=%s%s%s%s vlan-ids=%d" % [BRIDGE,
				(" comment=%s" % dev.vlans[vid]) if String(dev.vlans[vid]) != "" else "",
				(" tagged=%s" % ",".join(PackedStringArray(tagged))) if not tagged.is_empty() else "",
				(" untagged=%s" % ",".join(PackedStringArray(untagged))) if not untagged.is_empty() else "", vid])
	for i: Net.Iface in dev.ifaces:
		for cidr in i.ips:
			if Net.is_v6(cidr):
				add.call("/ipv6 address", "add address=%s advertise=%s interface=%s" % [cidr, "yes" if i.ra else "no", _dname(i)])
			else:
				add.call("/ip address", "add address=%s interface=%s network=%s" % [cidr, _dname(i), Net.network_of(cidr)["prefix"]])
		if not i.vrrp.is_empty() and String(i.vrrp.get("vip", "")) != "":
			add.call("/ip address", "add address=%s/32 interface=vrrp%d network=%s" % [i.vrrp["vip"], int(i.vrrp["group"]), i.vrrp["vip"]])
	if dev.resolver != "":
		add.call("/ip dns", "set servers=%s" % dev.resolver)
	if not dev.bgp.is_empty():
		var lists: Dictionary = dev.bgp.get("lists", {})
		for lname in lists:
			for addr in lists[lname]:
				add.call("/ip firewall address-list", "add address=%s list=%s" % [addr, lname])
	for rule in Sim.nat_rules(dev):
		if String(rule.get("kind", "")) == "masquerade":
			add.call("/ip firewall nat", "add action=masquerade chain=srcnat out-interface=%s" % rule["iface"])
	for r in dev.static_routes:
		add.call("/ip route", "add disabled=no distance=%d dst-address=%s/%d gateway=%s routing-table=main suppress-hw-offload=no" % [
			int(r.get("ad", 1)), r["prefix"], int(r["plen"]), r["via"]])
	for i: Net.Iface in dev.ifaces:
		if i.ra:
			add.call("/ipv6 nd", "add advertise-dns=yes interface=%s" % i.name)
	for i: Net.Iface in dev.ifaces:
		if i.bfd:
			add.call("/routing bfd configuration", "add disabled=no interfaces=%s" % i.name)
	if not dev.bgp.is_empty():
		add.call("/routing bgp template", "set default as=%d%s" % [int(dev.bgp["asn"]),
			(" router-id=%s" % dev.bgp["router_id"]) if dev.bgp.has("router_id") else ""])
		for nb in dev.bgp["neighbors"]:
			add.call("/routing bgp connection", "add as=%d local.role=ebgp name=%s%s remote.address=%s/32 .as=%d" % [
				int(dev.bgp["asn"]), nb.get("name", "peer"),
				(" output.network=%s" % nb["out_list"]) if String(nb.get("out_list", "")) != "" else "",
				nb["ip"], int(nb["remote_as"])])
	if not dev.ospf.is_empty():
		var inst := String(dev.ospf.get("instance", "default"))
		add.call("/routing ospf instance", "add disabled=no name=%s%s" % [inst,
			(" router-id=%s" % dev.ospf["router_id"]) if dev.ospf.has("router_id") else ""])
		var areas: Dictionary = dev.ospf.get("areas", {"backbone": "0.0.0.0"})
		if areas.is_empty():
			areas = {"backbone": "0.0.0.0"}
		for a in areas:
			add.call("/routing ospf area", "add area-id=%s disabled=no instance=%s name=%s" % [areas[a], inst, a])
		for net in dev.ospf.get("networks", []):
			add.call("/routing ospf interface-template", "add area=%s disabled=no networks=%s" % [_area_name(), net])
	if dev.snmp != "":
		add.call("/snmp community", "set [ find default=yes ] name=%s" % dev.snmp)
		add.call("/snmp", "set enabled=yes")
	var rd: Dictionary = dev.services.get("ros_dhcp", {})
	for pool_name in rd.get("pools", {}):
		add.call("/ip pool", "add name=%s ranges=%s-%s" % [pool_name, rd["pools"][pool_name][0], rd["pools"][pool_name][1]])
	if rd.has("server"):
		add.call("/ip dhcp-server", "add address-pool=%s interface=%s name=%s" % [rd["server"]["pool"], rd["server"]["iface"], rd["server"]["name"]])
	if rd.has("network"):
		var nw: Dictionary = rd["network"]
		add.call("/ip dhcp-server network", "add address=%s%s%s" % [nw["address"], (" dns-server=%s" % nw["dns"]) if String(nw.get("dns", "")) != "" else "",
			(" gateway=%s" % nw["gw"]) if String(nw.get("gw", "")) != "" else ""])
	for ifn in dev.services.get("dhcp_clients", {}):
		add.call("/ip dhcp-client", "add interface=%s" % ifn)
	for rule in dev.services.get("ros_filter", []):
		var text := "add"
		for k in ["action", "chain", "comment", "connection-state", "dst-address", "dst-port", "in-interface", "in-interface-list", "out-interface", "protocol", "src-address", "src-port"]:
			if rule.has(k):
				text += " %s=%s" % [k, ("\"%s\"" % rule[k]) if k == "comment" else rule[k]]
		add.call("/ip firewall filter", text)
	for lname in dev.services.get("if_lists", {}):
		add.call("/interface list", "add name=%s" % lname)
		for ifn in dev.services["if_lists"][lname]:
			add.call("/interface list member", "add interface=%s list=%s" % [ifn, lname])
	for sname in dev.services.get("ros_services", {}):
		var conf: Dictionary = dev.services["ros_services"][sname]
		var line := "set %s" % sname
		if conf.has("disabled"):
			line += " disabled=%s" % ("yes" if bool(conf["disabled"]) else "no")
		if conf.has("port"):
			line += " port=%d" % int(conf["port"])
		add.call("/ip service", line)
	if dev.ntp_server != "":
		add.call("/system ntp client", "set enabled=yes servers=%s" % dev.ntp_server)
	for u in dev.services.get("ros_users", {}):
		add.call("/user", "add group=%s name=%s" % [dev.services["ros_users"][u], u])
	add.call("/system identity", "set name=%s" % dev.name)
	var out := "# %s by RouterOS %s\n# software id = PKTK-T1K1\n#\n# model = CHR\n# serial number = %08X\n" % [
		Time.get_datetime_string_from_system(false, true).replace("T", " "), VERSION, dev.name.hash() % 0xFFFFFFFF]
	# the product prints menus in its own fixed order, not in the order they were built
	var order := ["/interface bridge", "/interface ethernet", "/interface bonding", "/interface vlan", "/interface wireguard", "/interface vrrp",
		"/interface list", "/ip pool", "/ip dhcp-server", "/routing bgp template", "/routing ospf instance", "/routing ospf area",
		"/interface bridge port", "/interface bridge vlan", "/interface list member", "/interface wireguard peers",
		"/ip address", "/ip dhcp-client", "/ip dhcp-server network", "/ip dns", "/ip firewall address-list", "/ip firewall filter", "/ip firewall nat",
		"/ip route", "/ip service", "/ipv6 address", "/ipv6 nd", "/routing bfd configuration", "/routing bgp connection",
		"/routing ospf interface-template", "/snmp", "/snmp community", "/system identity", "/system ntp client", "/user"]
	var menus: Array = []
	for menu in order:
		if groups.has(menu):
			menus.append(menu)
	for menu in groups:
		if menu not in menus:
			menus.append(menu)
	for menu in menus:
		out += menu + "\n"
		for line in groups[menu]:
			out += line + "\n"
	return out

func complete(line: String) -> Array:
	var raw := line.lstrip(" ")
	var absolute := raw.begins_with("/")
	raw = raw.trim_prefix("/")
	var ends_space := raw.ends_with(" ")
	var toks := Array(raw.split(" ", false))
	var cur: String = "" if ends_space or toks.is_empty() else toks.pop_back()
	if "=" in cur:
		return []  # param values aren't completed (yet)
	var ctx: Array = []
	if not absolute and cwd != "":
		ctx = Array(cwd.split(" ", false))
	for t in toks:
		if "=" not in String(t):
			ctx.append(t)
	var cands := {}
	for c in PATHS:
		var words: PackedStringArray = String(c).split(" ")
		if words.size() <= ctx.size():
			continue
		var okc := true
		for k in ctx.size():
			if not String(words[k]).begins_with(ctx[k]):
				okc = false
				break
		if okc and String(words[ctx.size()]).begins_with(cur):
			cands[words[ctx.size()]] = true
	var out := cands.keys()
	out.sort()
	return out
