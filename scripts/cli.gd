class_name CLI
## Session-based device CLIs. Switches and routers speak Arista/Cisco-style
## EOS (modes, abbreviations, show running-config); servers speak Linux.
## Everything mutates the same Game state the web UI renders.

static func new_session(dev: Net.NDevice) -> Session:
	if Game.MODELS.get(dev.model, {}).get("os", "") == "ros":
		return ROS.new(dev)
	return EOS.new(dev) if dev.type in ["switch", "router", "firewall", "uplink"] else Linux.new(dev)

static func try_ssh(session: Session, target: String) -> String:
	var ip := Sim.resolve(session.dev, target)
	if ip == "":
		ip = target
	if not ip.is_valid_ip_address():
		return "ssh: Could not resolve hostname %s\n" % target
	var owner := Sim._ip_owner(ip)
	if owner == null or owner == session.dev or not Sim.ping(session.dev, ip)["ok"]:
		return "ssh: connect to host %s: No route to host\n" % ip
	session.pending_ssh = owner
	return "Connected to %s (%s).\n" % [owner.name, ip]

static func fmt_ping(dev: Net.NDevice, target: String) -> String:
	var ip := Sim.resolve(dev, target)
	if ip == "":
		return "ping: %s: Name or service not known\n" % target
	var r := Sim.ping(dev, ip)
	var out := "PING %s (%s)\n" % [target, ip]
	if r["ok"]:
		for seq in [1, 2, 3]:
			out += "64 bytes from %s: icmp_seq=%d ttl=64 time=0.0%d ms\n" % [r["from"], seq, seq + 3]
		return out + "3 packets transmitted, 3 received, 0% packet loss\n"
	if r["detail"] == "ttl-exceeded":
		return out + "From %s: icmp_seq=1 Time to live exceeded\n" % r["from"]
	if r["detail"] == "timeout":
		return out + "3 packets transmitted, 0 received, 100% packet loss\n"
	return out + "ping: %s\n" % r["detail"]

static func fmt_traceroute(dev: Net.NDevice, target: String) -> String:
	var ip := Sim.resolve(dev, target)
	if ip == "":
		return "traceroute: %s: Name or service not known\n" % target
	var out := "traceroute to %s (%s), 16 hops max\n" % [target, ip]
	var n := 1
	for hop in Sim.traceroute(dev, ip):
		out += "%2d  %s\n" % [n, hop]
		n += 1
	return out

class Session:
	var dev: Net.NDevice
	var pending_ssh: Net.NDevice = null
	var wants_exit := false
	func _init(d: Net.NDevice) -> void:
		dev = d
	func banner() -> String:
		return ""
	func prompt() -> String:
		return "> "
	func exec(_line: String) -> String:
		return ""
	func complete(_line: String) -> Array:
		return []

# ============================================================== EOS ==

class EOS extends Session:
	var mode := "exec"  # exec | priv | config | if | vlan
	var ctx_if: Net.Iface
	var ctx_vlan := 0
	var _cmds: Array = []

	func _init(d: Net.NDevice) -> void:
		super(d)
		_build_cmds()

	func banner() -> String:
		return "%s: PacketOS EOS. Type '?' area: try 'enable', then 'configure terminal'.\n" % dev.name

	func prompt() -> String:
		match mode:
			"exec":
				return dev.name + ">"
			"priv":
				return dev.name + "#"
			"config":
				return dev.name + "(config)#"
			"if":
				return "%s(config-if-%s)#" % [dev.name, _short(ctx_if.name)]
			"vlan":
				return "%s(config-vlan-%d)#" % [dev.name, ctx_vlan]
			"router":
				return dev.name + "(config-router)#"
			"ospf":
				return dev.name + "(config-router-ospf)#"
		return dev.name + ">"

	static func _short(ifname: String) -> String:
		return ifname.replace("Ethernet", "Et")

	# ---- command table: {m: modes, p: path tokens, h: handler(rest)->String, dyn: Callable|null}
	func _build_cmds() -> void:
		var EP := ["exec", "priv", "config", "if", "vlan", "router", "ospf"]  # show/ping work everywhere via 'do'-free shortcut
		_cmds = [
			{"m": ["exec"], "p": ["enable"], "h": func(_r): mode = "priv"; return ""},
			{"m": ["priv"], "p": ["disable"], "h": func(_r): mode = "exec"; return ""},
			{"m": ["priv"], "p": ["configure", "terminal"], "h": func(_r): mode = "config"; return ""},
			{"m": ["exec", "priv"], "p": ["ping"], "h": _ping, "dyn": null},
			{"m": ["exec", "priv"], "p": ["traceroute"], "h": _traceroute},
			{"m": ["exec", "priv"], "p": ["ssh"], "h": _ssh},
			{"m": EP, "p": ["show", "version"], "h": _show_version},
			{"m": EP, "p": ["show", "interfaces"], "h": _show_interfaces},
			{"m": EP, "p": ["show", "vlan"], "h": _show_vlan},
			{"m": EP, "p": ["show", "mac", "address-table"], "h": _show_mac},
			{"m": EP, "p": ["show", "arp"], "h": _show_arp},
			{"m": EP, "p": ["show", "capture"], "h": _show_capture},
			{"m": EP, "p": ["show", "acl"], "h": _show_acl},
			{"m": EP, "p": ["show", "ip", "bgp", "summary"], "h": _show_bgp},
			{"m": EP, "p": ["show", "ip", "ospf", "neighbor"], "h": _show_ospf},
			{"m": EP, "p": ["show", "vrrp"], "h": _show_vrrp},
			{"m": EP, "p": ["show", "port-channel"], "h": _show_lag},
			{"m": EP, "p": ["show", "lldp", "neighbors"], "h": _show_lldp},
			{"m": EP, "p": ["show", "interfaces", "counters"], "h": _show_counters},
			{"m": ["priv"], "p": ["clear", "counters"], "h": _clear_counters},
			{"m": EP, "p": ["show", "spanning-tree"], "h": _show_stp},
			{"m": EP, "p": ["show", "ip", "route"], "h": _show_ip_route},
			{"m": EP, "p": ["show", "ip", "interface", "brief"], "h": _show_ip_brief},
			{"m": ["priv", "config", "if", "vlan"], "p": ["show", "running-config"], "h": _show_run},
			{"m": ["config"], "p": ["hostname"], "h": func(r): return _hostname(r)},
			{"m": ["config", "if", "vlan"], "p": ["vlan"], "h": _cfg_vlan, "dyn": _vlan_ids},
			{"m": ["config"], "p": ["no", "vlan"], "h": _cfg_no_vlan, "dyn": _vlan_ids},
			{"m": ["config", "if", "vlan", "router", "ospf"], "p": ["interface"], "h": _cfg_interface, "dyn": _if_names},
			{"m": ["config"], "p": ["ip", "route"], "h": _cfg_ip_route},
			{"m": ["config"], "p": ["acl", "permit"], "h": _cfg_acl.bind("permit")},
			{"m": ["config"], "p": ["acl", "deny"], "h": _cfg_acl.bind("deny")},
			{"m": ["config"], "p": ["no", "acl"], "h": _cfg_no_acl},
			{"m": ["config"], "p": ["no", "ip", "route"], "h": _cfg_no_ip_route},
			{"m": ["config"], "p": ["router", "bgp"], "h": _cfg_router_bgp},
			{"m": ["config"], "p": ["router", "ospf"], "h": _cfg_router_ospf},
			{"m": ["ospf"], "p": ["network"], "h": _ospf_network},
			{"m": ["ospf"], "p": ["no", "network"], "h": _ospf_no_network},
			{"m": ["router"], "p": ["neighbor"], "h": _bgp_neighbor},
			{"m": ["router"], "p": ["no", "neighbor"], "h": _bgp_no_neighbor},
			{"m": ["router"], "p": ["network"], "h": _bgp_network},
			{"m": ["router"], "p": ["no", "network"], "h": _bgp_no_network},
			{"m": ["vlan"], "p": ["name"], "h": func(r): return _vlan_name(r)},
			{"m": ["if"], "p": ["switchport", "mode"], "h": _sw_mode, "dyn": func(): return ["access", "trunk"]},
			{"m": ["if"], "p": ["switchport", "access", "vlan"], "h": _sw_access_vlan, "dyn": _vlan_ids},
			{"m": ["if"], "p": ["switchport", "trunk", "allowed", "vlan"], "h": _sw_trunk_vlans},
			{"m": ["if"], "p": ["ip", "address"], "h": _if_ip},
			{"m": ["if"], "p": ["ip", "nat"], "h": _if_nat, "dyn": func(): return ["inside", "outside"]},
			{"m": ["if"], "p": ["vrrp"], "h": _if_vrrp},
			{"m": ["if"], "p": ["channel-group"], "h": _if_lag},
			{"m": ["if"], "p": ["no", "channel-group"], "h": func(_r): ctx_if.lag = 0; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "vrrp"], "h": func(_r): ctx_if.vrrp = {}; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "ip", "nat"], "h": func(_r): ctx_if.nat = ""; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "ip", "address"], "h": _if_no_ip},
			{"m": ["if"], "p": ["shutdown"], "h": func(_r): ctx_if.enabled = false; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "shutdown"], "h": func(_r): ctx_if.enabled = true; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["mtu"], "h": _if_mtu},
			{"m": ["config", "if", "vlan", "router", "ospf"], "p": ["end"], "h": func(_r): mode = "priv"; return ""},
			{"m": EP, "p": ["exit"], "h": _exit},
			{"m": EP, "p": ["help"], "h": _help},
		]

	func exec(line: String) -> String:
		var toks := Array(line.strip_edges().split(" ", false))
		if toks.is_empty():
			return ""
		# resolve with per-token prefix matching (Cisco-style abbreviation)
		var full: Array = []
		for c in _cmds:
			if mode not in c["m"] or toks.size() < c["p"].size():
				continue
			var okc := true
			for k in c["p"].size():
				if not String(c["p"][k]).begins_with(toks[k]):
					okc = false
					break
			if okc:
				full.append(c)
		if full.is_empty():
			for c in _cmds:
				if mode not in c["m"]:
					continue
				var okc := true
				for k in mini(toks.size(), c["p"].size()):
					if not String(c["p"][k]).begins_with(toks[k]):
						okc = false
						break
				if okc:
					return "% Incomplete command\n"
			return "% Invalid input\n"
		var best_len := 0
		for c in full:
			best_len = maxi(best_len, c["p"].size())
		var winners := full.filter(func(c): return c["p"].size() == best_len)
		if winners.size() > 1:
			return "% Ambiguous command\n"
		var cmd: Dictionary = winners[0]
		# Cisco-style ambiguity: a longer command whose words diverge from the
		# winner within the typed tokens makes the abbreviation ambiguous
		# ("s" = ssh|show), while shared-prefix extensions don't
		# ("sh int" runs show interfaces even though ...counters exists).
		for c in _cmds:
			if mode not in c["m"] or c == cmd or toks.size() >= c["p"].size():
				continue
			var pref := true
			for k in toks.size():
				if not String(c["p"][k]).begins_with(toks[k]):
					pref = false
					break
			if not pref:
				continue
			for k in mini(toks.size(), cmd["p"].size()):
				if String(c["p"][k]) != String(cmd["p"][k]):
					return "% Ambiguous command\n"
		return cmd["h"].call(toks.slice(cmd["p"].size()))

	func complete(line: String) -> Array:
		var ends_space := line.ends_with(" ")
		var toks := Array(line.strip_edges().split(" ", false))
		var cur: String = "" if ends_space or toks.is_empty() else toks.pop_back()
		var cands := {}
		for c in _cmds:
			if mode not in c["m"]:
				continue
			var okc := true
			for k in mini(toks.size(), c["p"].size()):
				if not String(c["p"][k]).begins_with(toks[k]):
					okc = false
					break
			if not okc:
				continue
			if toks.size() < c["p"].size():
				cands[c["p"][toks.size()]] = true
			elif c.get("dyn") != null and toks.size() == c["p"].size():
				for opt in c["dyn"].call():
					cands[str(opt)] = true
		var out: Array = []
		for k in cands:
			if String(k).begins_with(cur):
				out.append(k)
		out.sort()
		return out

	# ---- handlers ----

	func _exit(_r: Array) -> String:
		match mode:
			"if", "vlan", "router", "ospf":
				mode = "config"
			"config":
				mode = "priv"
			"priv":
				mode = "exec"
			"exec":
				wants_exit = true
				return ""
		return ""

	func _help(_r: Array) -> String:
		var seen := {}
		for c in _cmds:
			if mode in c["m"]:
				seen[" ".join(PackedStringArray(c["p"]))] = true
		var keys := seen.keys()
		keys.sort()
		return "  " + "\n  ".join(PackedStringArray(keys)) + "\n"

	func _hostname(r: Array) -> String:
		if r.size() != 1:
			return "usage: hostname <name>\n"
		return "" if Game.rename_device(dev, r[0]) else "% invalid or duplicate name\n"

	func _ping(r: Array) -> String:
		if r.size() != 1:
			return "usage: ping <ip>\n"
		return CLI.fmt_ping(dev, r[0])

	func _traceroute(r: Array) -> String:
		if r.size() != 1:
			return "usage: traceroute <ip>\n"
		return CLI.fmt_traceroute(dev, r[0])

	func _ssh(r: Array) -> String:
		if r.size() != 1:
			return "usage: ssh <ip>\n"
		return CLI.try_ssh(self, r[0])

	func _vlan_ids() -> Array:
		var out: Array = []
		for vid in dev.vlans:
			out.append(str(vid))
		return out

	func _if_names() -> Array:
		var out: Array = []
		for i: Net.Iface in dev.ifaces:
			out.append(i.name)
		return out

	func _cfg_vlan(r: Array) -> String:
		if dev.type != "switch":
			return "% VLANs are configured on switches\n"
		if r.size() != 1 or not String(r[0]).is_valid_int():
			return "usage: vlan <1-4094>\n"
		var vid := int(r[0])
		if vid < 1 or vid > 4094:
			return "% invalid VLAN id\n"
		if not dev.vlans.has(vid):
			Game.add_vlan(dev, vid, "")
		ctx_vlan = vid
		mode = "vlan"
		return ""

	func _cfg_no_vlan(r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_int():
			return "usage: no vlan <vid>\n"
		return "" if Game.remove_vlan(dev, int(r[0])) else "% cannot remove (unknown vid, or vlan 1)\n"

	func _vlan_name(r: Array) -> String:
		if r.size() != 1:
			return "usage: name <word>\n"
		dev.vlans[ctx_vlan] = r[0]
		Game.topology_changed.emit()
		return ""

	func _cfg_interface(r: Array) -> String:
		if r.size() != 1:
			return "usage: interface <name>\n"
		var want := String(r[0]).to_lower()
		for i: Net.Iface in dev.ifaces:
			var full := i.name.to_lower()
			var digits := i.name.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
			var letters := full.trim_suffix(digits.to_lower())
			var w_digits := want.lstrip("abcdefghijklmnopqrstuvwxyz")
			var w_letters := want.trim_suffix(w_digits)
			if w_digits == digits and w_letters != "" and letters.begins_with(w_letters):
				ctx_if = i
				mode = "if"
				return ""
		return "% no such interface\n"

	func _sw_mode(r: Array) -> String:
		if dev.type != "switch":
			return "% switchport commands need a switch\n"
		for m in ["access", "trunk"]:
			if r.size() == 1 and m.begins_with(r[0]):
				ctx_if.mode = m
				Game.topology_changed.emit()
				return ""
		return "usage: switchport mode access|trunk\n"

	func _sw_access_vlan(r: Array) -> String:
		if dev.type != "switch":
			return "% switchport commands need a switch\n"
		if r.size() != 1 or not String(r[0]).is_valid_int():
			return "usage: switchport access vlan <vid>\n"
		var vid := int(r[0])
		if not dev.vlans.has(vid):
			if not Game.add_vlan(dev, vid, ""):  # IOS auto-creates the VLAN
				return "% invalid VLAN id\n"
		Game.set_access_vlan(ctx_if, vid)
		return ""

	func _sw_trunk_vlans(r: Array) -> String:
		if dev.type != "switch":
			return "% switchport commands need a switch\n"
		if r.size() != 1:
			return "usage: switchport trunk allowed vlan <v1,v2,...>|all\n"
		if r[0] == "all":
			ctx_if.tagged_vlans = []
			Game.topology_changed.emit()
			return ""
		var vids: Array = []
		for part in String(r[0]).split(",", false):
			if not part.is_valid_int() or int(part) < 1 or int(part) > 4094:
				return "% bad VLAN list: e.g. 10,20,30 or 'all'\n"
			vids.append(int(part))
		ctx_if.tagged_vlans = vids
		Game.topology_changed.emit()
		return ""

	func _if_ip(r: Array) -> String:
		if dev.type == "switch" and not ctx_if.name.begins_with("Management"):
			return "% SVIs are not supported yet: use the Management1 port or a router\n"
		if r.size() != 1:
			return "usage: ip address <a.b.c.d/len>\n"
		return "" if Game.add_ip(ctx_if, r[0]) else "% invalid CIDR or duplicate\n"

	func _if_lag(r: Array) -> String:
		if dev.type != "switch":
			return "% port-channels need a switch\n"
		if r.size() == 1 and String(r[0]).is_valid_int() and int(r[0]) >= 1:
			ctx_if.lag = int(r[0])
			Game.topology_changed.emit()
			return ""
		return "usage: channel-group <1-64>\n"

	func _show_lag(_r: Array) -> String:
		var groups := {}
		for i: Net.Iface in dev.ifaces:
			if i.lag > 0:
				if not groups.has(i.lag):
					groups[i.lag] = []
				groups[i.lag].append(i)
		if groups.is_empty():
			return "  (no port-channels: 'channel-group <n>' on member interfaces)\n"
		var out := "%-6s %-22s %s\n" % ["Group", "Members", "Peer"]
		var gids := groups.keys()
		gids.sort()
		for g in gids:
			var names: Array = []
			var peer := "-"
			for i: Net.Iface in groups[g]:
				names.append(EOS._short(i.name))
				var l := Game.link_at(i)
				if l:
					peer = l.other(i).dev.name
			out += "%-6d %-22s %s\n" % [g, ",".join(PackedStringArray(names)), peer]
		return out

	func _if_vrrp(r: Array) -> String:
		if not dev.ip_forwarding:
			return "% VRRP needs a router or firewall\n"
		# vrrp <group> ip <vip>   |   vrrp <group> priority <n>
		if r.size() == 3 and String(r[0]).is_valid_int():
			if "ip".begins_with(r[1]) and String(r[2]).is_valid_ip_address():
				ctx_if.vrrp = {"group": int(r[0]), "vip": r[2],
					"priority": int(ctx_if.vrrp.get("priority", 100))}
				Game.topology_changed.emit()
				return ""
			if "priority".begins_with(r[1]) and String(r[2]).is_valid_int():
				if ctx_if.vrrp.is_empty():
					return "% set the virtual IP first: vrrp <group> ip <vip>\n"
				ctx_if.vrrp["priority"] = int(r[2])
				Game.topology_changed.emit()
				return ""
		return "usage: vrrp <group> ip <vip>  |  vrrp <group> priority <1-254>\n"

	func _show_vrrp(_r: Array) -> String:
		var out := "%-11s %-6s %-16s %-9s %s\n" % ["Interface", "Group", "Virtual IP", "Priority", "State"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			if i.vrrp.is_empty():
				continue
			any = true
			var master := Sim.vrrp_master(i.vrrp["vip"], int(i.vrrp["group"]))
			out += "%-11s %-6d %-16s %-9d %s\n" % [EOS._short(i.name), int(i.vrrp["group"]),
				i.vrrp["vip"], int(i.vrrp.get("priority", 100)),
				"Master" if master == dev else ("Backup (master: %s)" % (master.name if master else "-"))]
		return out if any else "  (no VRRP groups configured)\n"

	func _if_nat(r: Array) -> String:
		if dev.type == "switch":
			return "% NAT needs a router or firewall\n"
		for m in ["inside", "outside"]:
			if r.size() == 1 and m.begins_with(r[0]):
				ctx_if.nat = m
				Game.topology_changed.emit()
				return ""
		return "usage: ip nat inside|outside\n"

	func _if_no_ip(r: Array) -> String:
		if r.size() == 1:
			Game.remove_ip(ctx_if, r[0])
		else:
			for cidr in ctx_if.ips.duplicate():
				Game.remove_ip(ctx_if, cidr)
		return ""

	func _if_mtu(r: Array) -> String:
		if r.size() == 1 and String(r[0]).is_valid_int() and int(r[0]) >= 576 and int(r[0]) <= 9216:
			ctx_if.mtu = int(r[0])
			Game.topology_changed.emit()
			return ""
		return "usage: mtu <576-9216>\n"

	func _cfg_acl(r: Array, action: String) -> String:
		if dev.type != "firewall":
			return "% ACLs need a firewall\n"
		if r.size() != 2:
			return "usage: acl %s <src-cidr|any> <dst-cidr|any>\n" % action
		var src := "0.0.0.0/0" if r[0] == "any" else String(r[0])
		var dst := "0.0.0.0/0" if r[1] == "any" else String(r[1])
		if not Net.valid_cidr(src) or not Net.valid_cidr(dst):
			return "% bad prefix: use a.b.c.d/len or 'any'\n"
		var sp := src.split("/")
		var dp := dst.split("/")
		dev.acls.append({"action": action, "src": sp[0], "splen": int(sp[1]),
			"dst": dp[0], "dplen": int(dp[1])})
		Game.topology_changed.emit()
		return ""

	func _cfg_no_acl(r: Array) -> String:
		if r.size() == 1 and String(r[0]).is_valid_int() and int(r[0]) >= 1 and int(r[0]) <= dev.acls.size():
			dev.acls.remove_at(int(r[0]) - 1)
			Game.topology_changed.emit()
			return ""
		return "usage: no acl <rule-number>   (see 'show acl')\n"

	func _show_acl(_r: Array) -> String:
		if dev.acls.is_empty():
			return "  (no rules: default permit)\n"
		var out := ""
		var n := 1
		for rule in dev.acls:
			out += "%2d  %-7s %s/%d -> %s/%d\n" % [n, rule["action"], rule["src"], int(rule["splen"]), rule["dst"], int(rule["dplen"])]
			n += 1
		return out + "    (first match wins; default permit)\n"

	func _cfg_router_ospf(r: Array) -> String:
		if not dev.ip_forwarding or dev.type == "uplink":
			return "% OSPF runs on routers and firewalls\n"
		if r.size() > 1:
			return "usage: router ospf [process-id]\n"
		if dev.ospf.is_empty():
			dev.ospf = {"networks": []}
		mode = "ospf"
		return ""

	func _ospf_network(r: Array) -> String:
		# accept: network <p/len> [area 0]
		if r.size() >= 1 and Net.valid_cidr(r[0]):
			if r[0] not in dev.ospf["networks"]:
				dev.ospf["networks"].append(r[0])
			Game.topology_changed.emit()
			return ""
		return "usage: network <prefix/len> area 0\n"

	func _ospf_no_network(r: Array) -> String:
		if r.size() >= 1:
			dev.ospf["networks"].erase(r[0])
			Game.topology_changed.emit()
			return ""
		return "usage: no network <prefix/len>\n"

	func _show_ospf(_r: Array) -> String:
		if dev.ospf.is_empty():
			return "% OSPF not running: 'router ospf' in config mode\n"
		var nbs := Sim.ospf_neighbors(dev)
		if nbs.is_empty():
			return "  (no neighbors: check network statements on both sides)\n"
		var out := "%-14s %-8s %s\n" % ["Neighbor", "State", "Address"]
		var seen := {}
		for nb in nbs:
			if seen.has(nb["dev"]):
				continue
			seen[nb["dev"]] = true
			out += "%-14s %-8s %s\n" % [nb["dev"].name, "FULL", nb["via_ip"]]
		return out

	func _cfg_router_bgp(r: Array) -> String:
		if dev.type != "router":
			return "% BGP runs on routers\n"
		if r.size() != 1 or not String(r[0]).is_valid_int():
			return "usage: router bgp <asn>\n"
		if dev.bgp.is_empty():
			dev.bgp = {"asn": int(r[0]), "neighbors": [], "networks": []}
		elif int(dev.bgp["asn"]) != int(r[0]):
			return "%% BGP is already running with AS %d\n" % int(dev.bgp["asn"])
		mode = "router"
		return ""

	func _bgp_neighbor(r: Array) -> String:
		if r.size() == 3 and String(r[0]).is_valid_ip_address() \
				and "remote-as".begins_with(r[1]) and String(r[2]).is_valid_int():
			_bgp_no_neighbor([r[0]])
			dev.bgp["neighbors"].append({"ip": r[0], "remote_as": int(r[2])})
			Game.topology_changed.emit()
			return ""
		return "usage: neighbor <ip> remote-as <asn>\n"

	func _bgp_no_neighbor(r: Array) -> String:
		if r.size() != 1:
			return "usage: no neighbor <ip>\n"
		for nb in dev.bgp["neighbors"].duplicate():
			if nb["ip"] == r[0]:
				dev.bgp["neighbors"].erase(nb)
		Game.topology_changed.emit()
		return ""

	func _bgp_network(r: Array) -> String:
		if r.size() == 1 and Net.valid_cidr(r[0]):
			if r[0] not in dev.bgp["networks"]:
				dev.bgp["networks"].append(r[0])
			Game.topology_changed.emit()
			return ""
		return "usage: network <prefix/len>   (announce your prefix upstream)\n"

	func _bgp_no_network(r: Array) -> String:
		if r.size() == 1:
			dev.bgp["networks"].erase(r[0])
			Game.topology_changed.emit()
			return ""
		return "usage: no network <prefix/len>\n"

	func _show_bgp(_r: Array) -> String:
		if dev.bgp.is_empty():
			return "% BGP not running: 'router bgp <asn>' in config mode\n"
		var out := "BGP router AS %d\n%-16s %-10s %s\n" % [int(dev.bgp["asn"]), "Neighbor", "Remote-AS", "State"]
		if dev.bgp["neighbors"].is_empty():
			out += "  (no neighbors configured)\n"
		for nb in dev.bgp["neighbors"]:
			var st := "Established" if Sim.bgp_established(dev, nb) else "Idle"
			out += "%-16s %-10d %s\n" % [nb["ip"], int(nb["remote_as"]), st]
		if not dev.bgp["networks"].is_empty():
			out += "Announcing: %s\n" % ", ".join(PackedStringArray(dev.bgp["networks"]))
		return out

	func _cfg_ip_route(r: Array) -> String:
		if not dev.ip_forwarding:
			return "% static routing needs a router\n"
		if r.size() == 2 and Net.valid_cidr(r[0]):
			var parts := String(r[0]).split("/")
			if Game.add_static_route(dev, parts[0], int(parts[1]), r[1]):
				return ""
		return "usage: ip route <prefix/len> <next-hop>\n"

	func _cfg_no_ip_route(r: Array) -> String:
		if r.size() >= 1 and Net.valid_cidr(r[0]):
			var parts := String(r[0]).split("/")
			Game.remove_static_route(dev, parts[0], int(parts[1]))
			return ""
		return "usage: no ip route <prefix/len>\n"

	# ---- show ----

	func _show_version(_r: Array) -> String:
		return "PacketOS EOS 0.3\nHardware: %s (%s), %d interfaces\n" % [dev.name, dev.type, dev.ifaces.size()]

	func _show_interfaces(_r: Array) -> String:
		var out := "%-11s %-6s %-7s %-8s %-18s %s\n" % ["Interface", "Status", "Speed", "Mode", "Addresses", "Peer"]
		for i: Net.Iface in dev.ifaces:
			var peer := Game.peer_label(i)
			var status := "disabled" if not i.enabled else ("up" if peer != "" else "notconnect")
			var mode_s := i.mode
			if i.mode == "access":
				mode_s = "access(%d)" % i.untagged_vlan
			var addrs := ",".join(i.ips) if not i.ips.is_empty() else "-"
			out += "%-11s %-6s %-7s %-8s %-18s %s\n" % [EOS._short(i.name), status,
				("%dG" % (Game.iface_speed(i) / 1000)) if Game.iface_speed(i) >= 1000 else "%dM" % Game.iface_speed(i),
				mode_s, addrs, peer if peer else "-"]
		return out

	func _show_vlan(_r: Array) -> String:
		if dev.type != "switch":
			return "% no VLAN database on this device\n"
		var out := "%-6s %-16s %s\n" % ["VLAN", "Name", "Ports"]
		var vids := dev.vlans.keys()
		vids.sort()
		for vid in vids:
			var ports: Array = []
			for i: Net.Iface in dev.ifaces:
				if i.mode == "trunk" or (i.mode == "access" and i.untagged_vlan == vid):
					ports.append(EOS._short(i.name))
			out += "%-6d %-16s %s\n" % [vid, dev.vlans[vid], ", ".join(PackedStringArray(ports))]
		return out

	func _show_mac(_r: Array) -> String:
		var out := "%-6s %-18s %s\n" % ["Vlan", "Mac Address", "Port"]
		var vlans := dev.mac_table.keys()
		vlans.sort()
		for vlan in vlans:
			for mac in dev.mac_table[vlan]:
				out += "%-6d %-18s %s\n" % [vlan, mac, EOS._short(dev.mac_table[vlan][mac].name)]
		return out if vlans else "  (empty: send some traffic first)\n"

	func _show_capture(_r: Array) -> String:
		if dev.capture.is_empty():
			return "  (no frames captured: generate some traffic)\n"
		return "\n".join(PackedStringArray(dev.capture.slice(-20))) + "\n"

	func _show_stp(_r: Array) -> String:
		if dev.type != "switch":
			return "% spanning tree runs on switches\n"
		var root := Sim.stp_root_of(dev)
		var out := "Root bridge: %s%s\n%-11s %-11s %s\n" % [root.name if root else "-",
			"  (this switch)" if root == dev else "", "Port", "Role", "State"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			var l := Game.link_at(i)
			if l == null or l.other(i).dev.type != "switch":
				continue
			any = true
			var blocked := Sim.stp_blocked(i)
			out += "%-11s %-11s %s\n" % [EOS._short(i.name),
				"alternate" if blocked else "designated",
				"discarding" if blocked else "forwarding"]
		return out if any else out + "  (no switch-to-switch links)\n"

	func _show_counters(_r: Array) -> String:
		var out := "%-11s %12s %12s\n" % ["Port", "InFrames", "OutFrames"]
		for i: Net.Iface in dev.ifaces:
			out += "%-11s %12d %12d\n" % [EOS._short(i.name), i.rx_frames, i.tx_frames]
		return out

	func _clear_counters(_r: Array) -> String:
		for i: Net.Iface in dev.ifaces:
			i.tx_frames = 0
			i.rx_frames = 0
		return ""

	func _show_lldp(_r: Array) -> String:
		var out := "%-11s %-14s %s\n" % ["Port", "Neighbor", "Neighbor Port"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			var l := Game.link_at(i)
			if l:
				any = true
				var peer := l.other(i)
				out += "%-11s %-14s %s\n" % [EOS._short(i.name), peer.dev.name, EOS._short(peer.name)]
		return out if any else "  (no neighbors detected)\n"

	func _show_arp(_r: Array) -> String:
		if dev.arp.is_empty():
			return "  (empty)\n"
		var out := "%-16s %s\n" % ["Address", "Hardware Addr"]
		for ip in dev.arp:
			out += "%-16s %s\n" % [ip, dev.arp[ip]]
		return out

	func _show_ip_route(_r: Array) -> String:
		var out := ""
		for i: Net.Iface in dev.ifaces:
			for cidr: String in i.ips:
				var parts := cidr.split("/")
				out += "C  %s/%s is directly connected, %s\n" % [parts[0], parts[1], EOS._short(i.name)]
		for r in dev.static_routes:
			out += "S  %s/%d [1/0] via %s\n" % [r["prefix"], int(r["plen"]), r["via"]]
		for r in Sim._bgp_learned(dev):
			out += "B  %s/%d [20/0] via %s\n" % [r["prefix"], int(r["plen"]), r["via"]]
		for r in Sim._ospf_learned(dev):
			out += "O  %s/%d [110/%d] via %s\n" % [r["prefix"], int(r["plen"]), 10, r["via"]]
		return out if out else "  (no routes: configure ip addresses)\n"

	func _show_ip_brief(_r: Array) -> String:
		var out := "%-11s %-18s %-8s\n" % ["Interface", "IP Address", "Status"]
		for i: Net.Iface in dev.ifaces:
			var ip: String = i.ips[0] if not i.ips.is_empty() else "unassigned"
			out += "%-11s %-18s %-8s\n" % [EOS._short(i.name), ip, "up" if i.enabled else "admin-down"]
		return out

	func _show_run(_r: Array) -> String:
		var out := "hostname %s\n!\n" % dev.name
		var vids := dev.vlans.keys()
		vids.sort()
		for vid in vids:
			if vid == 1:
				continue
			out += "vlan %d\n   name %s\n!\n" % [vid, dev.vlans[vid]]
		for r in dev.static_routes:
			out += "ip route %s/%d %s\n!\n" % [r["prefix"], int(r["plen"]), r["via"]]
		for rule in dev.acls:
			out += "acl %s %s/%d %s/%d\n!\n" % [rule["action"], rule["src"], int(rule["splen"]), rule["dst"], int(rule["dplen"])]
		if not dev.ospf.is_empty():
			out += "router ospf 1\n"
			for net in dev.ospf["networks"]:
				out += "   network %s area 0\n" % net
			out += "!\n"
		if not dev.bgp.is_empty() and dev.type == "router":
			out += "router bgp %d\n" % int(dev.bgp["asn"])
			for nb in dev.bgp["neighbors"]:
				out += "   neighbor %s remote-as %d\n" % [nb["ip"], int(nb["remote_as"])]
			for net in dev.bgp["networks"]:
				out += "   network %s\n" % net
			out += "!\n"
		for i: Net.Iface in dev.ifaces:
			out += "interface %s\n" % i.name
			if i.mode == "trunk":
				out += "   switchport mode trunk\n"
				if not i.tagged_vlans.is_empty():
					out += "   switchport trunk allowed vlan %s\n" % ",".join(i.tagged_vlans.map(func(v): return str(v)))
			elif i.mode == "access" and i.untagged_vlan != 1:
				out += "   switchport access vlan %d\n" % i.untagged_vlan
			for cidr in i.ips:
				out += "   ip address %s\n" % cidr
			if i.nat != "":
				out += "   ip nat %s\n" % i.nat
			if not i.vrrp.is_empty():
				out += "   vrrp %d ip %s\n" % [int(i.vrrp["group"]), i.vrrp["vip"]]
				if int(i.vrrp.get("priority", 100)) != 100:
					out += "   vrrp %d priority %d\n" % [int(i.vrrp["group"]), int(i.vrrp["priority"])]
			if i.lag > 0:
				out += "   channel-group %d\n" % i.lag
			if i.mtu != 1500:
				out += "   mtu %d\n" % i.mtu
			if not i.enabled:
				out += "   shutdown\n"
			out += "!\n"
		return out

# ============================================================ Linux ==

class Linux extends Session:
	func banner() -> String:
		return "Welcome to PacketLinux. Try 'ip addr', 'ip route', 'ping <ip>', 'help'.\n"

	func prompt() -> String:
		return "root@%s:~#" % dev.name

	func exec(line: String) -> String:
		var t := Array(line.strip_edges().split(" ", false))
		if t.is_empty():
			return ""
		match t[0]:
			"help":
				return "  ip addr [add|del <cidr> dev <if>]\n  ip link set <if> up|down\n  ip route [add <cidr>|default via <gw>] [del <cidr>|default]\n  ping <ip|name>   traceroute <ip|name>   hostname <name>   tcpdump   clear\n  ip neigh | arp                       ARP table\n  lldp                                 who is on the other end of my cables\n  dhclient <if>                        get an address automatically\n  dhcpd <if> <first> <last> <plen> [gw] [dns]   serve DHCP leases\n  dns add <name> <ip> | dns list       host DNS records\n  nslookup <name>   nameserver <ip>\n"
			"hostname":
				if t.size() == 1:
					return dev.name + "\n"
				return "" if Game.rename_device(dev, t[1]) else "hostname: invalid or duplicate name\n"
			"ping":
				return CLI.fmt_ping(dev, t[1]) if t.size() == 2 else "usage: ping <ip>\n"
			"traceroute":
				return CLI.fmt_traceroute(dev, t[1]) if t.size() == 2 else "usage: traceroute <ip>\n"
			"ip":
				return _ip(t.slice(1))
			"dhclient":
				if t.size() != 2:
					return "usage: dhclient <iface>\n"
				var ifc := _iface(t[1])
				if ifc == null:
					return "Cannot find device \"%s\"\n" % t[1]
				var lease := Sim.dhcp_request(dev, ifc)
				if lease.is_empty():
					return "dhclient: no DHCP server responded on %s\n" % t[1]
				return "bound to %s/%d  (gw %s, dns %s)\n" % [lease["ip"], int(lease["plen"]),
					lease.get("gw", "-"), lease.get("dns", "-")]
			"dhcpd":
				if t.size() < 5 or _iface(t[1]) == null or not Net.valid_cidr(t[2] + "/" + t[4]):
					return "usage: dhcpd <iface> <first-ip> <last-ip> <plen> [gw] [dns]\n     e.g. dhcpd eth0 10.2.0.10 10.2.0.99 24 10.2.0.1 10.2.0.5\n"
				dev.services["dhcp"] = {"iface": t[1], "start": t[2], "end": t[3],
					"plen": int(t[4]), "gw": t[5] if t.size() > 5 else "",
					"dns": t[6] if t.size() > 6 else "", "leases": {}}
				Game.topology_changed.emit()
				return "dhcpd: serving %s–%s/%s on %s\n" % [t[2], t[3], t[4], t[1]]
			"dns":
				if t.size() == 4 and t[1] == "add" and String(t[3]).is_valid_ip_address():
					if not dev.services.has("dns"):
						dev.services["dns"] = {"records": {}}
					dev.services["dns"]["records"][t[2]] = t[3]
					Game.topology_changed.emit()
					return ""
				if t.size() == 2 and t[1] == "list":
					var recs: Dictionary = dev.services.get("dns", {}).get("records", {})
					if recs.is_empty():
						return "(no records: this host is not a DNS server yet)\n"
					var out := ""
					for k in recs:
						out += "%-20s A  %s\n" % [k, recs[k]]
					return out
				return "usage: dns add <name> <ip> | dns list\n"
			"nslookup":
				if t.size() != 2:
					return "usage: nslookup <name|ip>\n"
				if String(t[1]).is_valid_ip_address():
					var nm := Sim.reverse_lookup(dev, t[1])
					if nm == "":
						return "** server can't find %s (no PTR)\n" % t[1]
					return "%s   name = %s\n" % [t[1], nm]
				var addr := Sim.resolve(dev, t[1])
				if addr == "":
					return "** server can't find %s (resolver: %s)\n" % [t[1], dev.resolver if dev.resolver else "none set"]
				return "Server:  %s\nName:    %s\nAddress: %s\n" % [dev.resolver, t[1], addr]
			"nameserver":
				if t.size() != 2 or not String(t[1]).is_valid_ip_address():
					return "usage: nameserver <ip>   (sets this host's DNS resolver)\n"
				dev.resolver = t[1]
				Game.topology_changed.emit()
				return ""
			"arp":
				return _ip(["neigh"])
			"lldp":
				var out := "%-8s %-14s %s\n" % ["Port", "Neighbor", "Neighbor Port"]
				var any := false
				for i: Net.Iface in dev.ifaces:
					var l := Game.link_at(i)
					if l:
						any = true
						out += "%-8s %-14s %s\n" % [i.name, l.other(i).dev.name, l.other(i).name]
				return out if any else "(no neighbors detected)\n"
			"ssh":
				return CLI.try_ssh(self, t[1]) if t.size() == 2 else "usage: ssh <ip|name>\n"
			"exit", "logout":
				wants_exit = true
				return ""
			"tcpdump":
				if dev.capture.is_empty():
					return "tcpdump: 0 packets captured (generate some traffic)\n"
				return "\n".join(PackedStringArray(dev.capture.slice(-20))) + "\n"
		return "%s: command not found\n" % t[0]

	func _iface(name: String) -> Net.Iface:
		for i: Net.Iface in dev.ifaces:
			if i.name == name:
				return i
		return null

	func _ip(t: Array) -> String:
		if t.is_empty():
			return "usage: ip addr|link|route ...\n"
		if String(t[0]).begins_with("a"):  # ip addr
			if t.size() == 1:
				var out := ""
				for i: Net.Iface in dev.ifaces:
					out += "%s: <%s> mtu %d\n    link/ether %s\n" % [i.name,
						"UP" if i.enabled else "DOWN", i.mtu, i.mac]
					for cidr in i.ips:
						out += "    inet %s\n" % cidr
					out += "    RX packets %d  TX packets %d\n" % [i.rx_frames, i.tx_frames]
				return out
			if t.size() == 5 and t[1] in ["add", "del"] and t[3] == "dev":
				var ifc := _iface(t[4])
				if ifc == null:
					return "Cannot find device \"%s\"\n" % t[4]
				if t[1] == "add":
					return "" if Game.add_ip(ifc, t[2]) else "Error: invalid or duplicate address\n"
				if t[2] in ifc.ips:
					Game.remove_ip(ifc, t[2])
					return ""
				return "Error: address not found\n"
			return "usage: ip addr [add|del <cidr> dev <if>]\n"
		if String(t[0]).begins_with("l"):  # ip link set IF up|down
			if t.size() == 4 and t[1] == "set" and t[3] in ["up", "down"]:
				var ifc := _iface(t[2])
				if ifc == null:
					return "Cannot find device \"%s\"\n" % t[2]
				ifc.enabled = t[3] == "up"
				Game.topology_changed.emit()
				return ""
			return "usage: ip link set <if> up|down\n"
		if String(t[0]).begins_with("n"):  # ip neigh
			if dev.arp.is_empty():
				return "(empty: no ARP entries yet)\n"
			var out := ""
			for ip in dev.arp:
				out += "%s dev %s lladdr %s REACHABLE\n" % [ip, dev.ifaces[0].name, dev.arp[ip]]
			return out
		if String(t[0]).begins_with("r"):  # ip route
			if t.size() == 1:
				var out := ""
				for r in dev.static_routes:
					if r["plen"] == 0:
						out += "default via %s\n" % r["via"]
					else:
						out += "%s/%d via %s\n" % [r["prefix"], int(r["plen"]), r["via"]]
				for i: Net.Iface in dev.ifaces:
					for cidr: String in i.ips:
						out += "%s dev %s scope link\n" % [cidr, i.name]
				return out if out else "(no routes)\n"
			if t.size() == 4 and t[1] == "add" and t[3] != "":
				if t[2] == "default" or Net.valid_cidr(t[2]):
					return "usage: ip route add default|<cidr> via <gw>\n"
			if t.size() == 5 and t[1] == "add" and t[3] == "via":
				var pfx := "0.0.0.0/0" if t[2] == "default" else String(t[2])
				if not Net.valid_cidr(pfx):
					return "Error: invalid prefix\n"
				var parts := pfx.split("/")
				return "" if Game.add_static_route(dev, parts[0], int(parts[1]), t[4]) \
					else "Error: invalid gateway\n"
			if t.size() == 3 and t[1] == "del":
				var pfx := "0.0.0.0/0" if t[2] == "default" else String(t[2])
				if Net.valid_cidr(pfx):
					var parts := pfx.split("/")
					Game.remove_static_route(dev, parts[0], int(parts[1]))
					return ""
				return "Error: invalid prefix\n"
			return "usage: ip route [add default|<cidr> via <gw> | del default|<cidr>]\n"
		return "usage: ip addr|link|route ...\n"

	func complete(line: String) -> Array:
		var ends_space := line.ends_with(" ")
		var toks := Array(line.strip_edges().split(" ", false))
		var cur: String = "" if ends_space or toks.is_empty() else toks.pop_back()
		var opts: Array = []
		match toks.size():
			0:
				opts = ["ip", "ping", "traceroute", "hostname", "tcpdump", "dhclient", "dhcpd", "dns", "nslookup", "nameserver", "arp", "lldp", "ssh", "exit", "clear", "help"]
			1:
				if toks[0] == "ip":
					opts = ["addr", "link", "route", "neigh"]
			2:
				if toks[0] == "ip" and String(toks[1]).begins_with("a"):
					opts = ["add", "del"]
				elif toks[0] == "ip" and String(toks[1]).begins_with("r"):
					opts = ["add", "del"]
				elif toks[0] == "ip" and String(toks[1]).begins_with("l"):
					opts = ["set"]
		var out: Array = []
		for o in opts:
			if String(o).begins_with(cur):
				out.append(o)
		out.sort()
		return out
