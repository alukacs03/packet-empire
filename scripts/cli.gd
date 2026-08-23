class_name CLI
## Session-based device CLIs. Switches and routers speak Arista/Cisco-style
## EOS (modes, abbreviations, show running-config); servers speak Linux.
## Everything mutates the same Game state the web UI renders.

static func new_session(dev: Net.NDevice) -> Session:
	if Game.MODELS.get(dev.model, {}).get("os", "") == "ros":
		return ROS.new(dev)
	return EOS.new(dev) if dev.type in ["switch", "router", "firewall", "uplink",
		"loadbalancer", "ap"] else Linux.new(dev)

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

static func fmt_ping(dev: Net.NDevice, target: String, size := 64) -> String:
	var ip := Sim.resolve(dev, target)
	if ip == "":
		return "ping: %s: Name or service not known\n" % target
	var r := Sim.ping(dev, ip, 64, "", size)
	var out := "PING %s (%s) %d(%d) bytes of data.\n" % [target, ip, size, size + 28]
	if r["ok"]:
		var base: float = maxf(0.04, float(r.get("rtt", 0.1)))
		for seq in [1, 2, 3]:
			out += "%d bytes from %s: icmp_seq=%d ttl=64 time=%.2f ms\n" % [size, r["from"], seq,
				base * (1.0 + 0.04 * seq)]
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
		if hop == "*":
			out += "%2d  *\n" % n
		else:
			var probe := Sim.ping(dev, String(hop))
			out += "%2d  %-18s %.2f ms\n" % [n, hop, maxf(0.04, float(probe.get("rtt", 0.1)))]
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
	var ctx_if: Net.Iface  # the first of ctx_ifs, for single-interface commands
	var ctx_ifs: Array = []  # every interface the current context applies to
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
			{"m": ["priv"], "p": ["write", "memory"], "h": _write_mem},
			{"m": ["priv"], "p": ["copy", "running-config", "startup-config"], "h": _write_mem},
			{"m": ["priv"], "p": ["reload"], "h": _reload},
			{"m": ["priv"], "p": ["copy", "running-config", "template"], "h": _save_template},
			{"m": ["priv"], "p": ["copy", "template"], "h": _apply_template},
			{"m": EP, "p": ["show", "templates"], "h": _show_templates},
			{"m": EP, "p": ["show", "startup-config"], "h": _show_startup},
			{"m": EP, "p": ["show", "config", "versions"], "h": _show_versions},
			{"m": EP, "p": ["show", "config", "diff"], "h": _show_diff},
			{"m": ["priv"], "p": ["rollback"], "h": _rollback},
			{"m": ["priv"], "p": ["configure", "terminal"], "h": func(_r): mode = "config"; return ""},
			{"m": ["exec", "priv"], "p": ["ping"], "h": _ping},
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
			{"m": ["if"], "p": ["bfd"], "h": func(_r): return _bfd(true)},
			{"m": ["if"], "p": ["no", "bfd"], "h": func(_r): return _bfd(false)},
			{"m": EP, "p": ["show", "bfd"], "h": _show_bfd},
			{"m": ["config"], "p": ["spanning-tree", "mode"], "h": _stp_mode},
			{"m": ["config"], "p": ["spanning-tree", "priority"], "h": _stp_priority},
			{"m": ["config"], "p": ["spanning-tree", "mst"], "h": _stp_mst},
			{"m": EP, "p": ["show", "ip", "route"], "h": _show_ip_route},
			{"m": EP, "p": ["show", "ip", "interface", "brief"], "h": _show_ip_brief},
			{"m": ["priv", "config", "if", "vlan"], "p": ["show", "running-config"], "h": _show_run},
			{"m": ["config"], "p": ["hostname"], "h": func(r): return _hostname(r)},
			{"m": ["config"], "p": ["logging", "host"], "h": _cfg_logging},
			{"m": ["config"], "p": ["no", "logging", "host"], "h": _no_logging},
			{"m": ["config"], "p": ["ntp", "server"], "h": _cfg_ntp},
			{"m": EP, "p": ["show", "logging"], "h": _show_logging},
			{"m": EP, "p": ["show", "clock"], "h": _show_clock},
			{"m": ["config", "if", "vlan"], "p": ["vlan"], "h": _cfg_vlan, "dyn": _vlan_ids},
			{"m": ["config"], "p": ["no", "vlan"], "h": _cfg_no_vlan, "dyn": _vlan_ids},
			{"m": ["config", "if", "vlan", "router", "ospf"], "p": ["interface"], "h": _cfg_interface, "dyn": _if_names},
			{"m": ["config", "if", "vlan", "router", "ospf"], "p": ["interface", "range"], "h": _cfg_if_range},
			{"m": ["config"], "p": ["ip", "route"], "h": _cfg_ip_route},
			{"m": ["config"], "p": ["ip", "vrf"], "h": _cfg_vrf},
			{"m": ["config"], "p": ["ssid"], "h": _cfg_ssid},
			{"m": EP, "p": ["show", "ssid"], "h": _show_ssid},
			{"m": ["config"], "p": ["virtual-server"], "h": _cfg_vip},
			{"m": ["config"], "p": ["no", "virtual-server"], "h": _cfg_no_vip},
			{"m": EP, "p": ["show", "virtual-server"], "h": _show_vip},
			{"m": ["if"], "p": ["ip", "vrf", "forwarding"], "h": _if_vrf},
			{"m": EP, "p": ["show", "ip", "vrf"], "h": _show_vrf},
			{"m": ["config"], "p": ["firewall", "stateful"], "h": func(_r): return _set_stateful(true)},
			{"m": ["config"], "p": ["no", "firewall", "stateful"], "h": func(_r): return _set_stateful(false)},
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
			{"m": ["router"], "p": ["roa"], "h": _bgp_roa},
			{"m": ["router"], "p": ["network"], "h": _bgp_network},
			{"m": ["router"], "p": ["no", "network"], "h": _bgp_no_network},
			{"m": ["vlan"], "p": ["name"], "h": func(r): return _vlan_name(r)},
			{"m": ["if"], "p": ["switchport", "mode"], "h": _sw_mode, "dyn": func(): return ["access", "trunk"]},
			{"m": ["if"], "p": ["switchport", "access", "vlan"], "h": _sw_access_vlan, "dyn": _vlan_ids},
			{"m": ["if"], "p": ["switchport", "trunk", "allowed", "vlan"], "h": _sw_trunk_vlans},
			{"m": ["if"], "p": ["dot1x"], "h": func(_r): return _dot1x(true)},
			{"m": ["if"], "p": ["no", "dot1x"], "h": func(_r): return _dot1x(false)},
			{"m": ["config"], "p": ["radius-server", "host"], "h": _cfg_radius},
			{"m": EP, "p": ["show", "dot1x"], "h": _show_dot1x},
			{"m": ["if"], "p": ["switchport", "protected"], "h": func(_r): return _pvlan("isolated")},
			{"m": ["if"], "p": ["no", "switchport", "protected"], "h": func(_r): return _pvlan("")},
			{"m": ["if"], "p": ["storm-control", "broadcast"], "h": _storm},
			{"m": ["if"], "p": ["no", "storm-control", "broadcast"], "h": func(_r): return _storm([0])},
			{"m": ["if"], "p": ["switchport", "port-security"], "h": func(_r): return _port_sec(true)},
			{"m": ["if"], "p": ["no", "switchport", "port-security"], "h": func(_r): return _port_sec(false)},
			{"m": EP, "p": ["show", "port-security"], "h": _show_port_sec},
			{"m": ["config"], "p": ["mlag", "peer"], "h": func(r): return _mlag_peer(r[0] if r.size() > 0 else "")},
			{"m": ["config"], "p": ["no", "mlag"], "h": func(_r): return _mlag_peer("")},
			{"m": ["if"], "p": ["mlag", "peer-link"], "h": func(_r): return _mlag_if(-1)},
			{"m": ["if"], "p": ["mlag"], "h": func(r): return _mlag_if(int(r[0]) if r.size() > 0 else 0)},
			{"m": ["if"], "p": ["no", "mlag"], "h": func(_r): return _mlag_if(0)},
			{"m": EP, "p": ["show", "mlag"], "h": _show_mlag},
			{"m": ["config"], "p": ["snmp-server", "community"],
				"h": func(r): return _snmp(r[0] if r.size() > 0 else "")},
			{"m": ["config"], "p": ["no", "snmp-server"], "h": func(_r): return _snmp("")},
			{"m": EP, "p": ["show", "snmp"], "h": _show_snmp},
			{"m": EP, "p": ["show", "flows"], "h": _show_flows},
			{"m": ["config"], "p": ["clear", "flows"], "h": func(_r):
				dev.talkers.clear()
				return ""},
			{"m": ["config"], "p": ["ip", "igmp", "snooping"], "h": func(_r): return _igmp(true)},
			{"m": ["config"], "p": ["no", "ip", "igmp", "snooping"], "h": func(_r): return _igmp(false)},
			{"m": EP, "p": ["show", "ip", "igmp", "snooping"], "h": _show_igmp},
			{"m": ["config"], "p": ["ip", "dhcp", "snooping"], "h": func(_r): return _snoop(true)},
			{"m": ["config"], "p": ["no", "ip", "dhcp", "snooping"], "h": func(_r): return _snoop(false)},
			{"m": ["config"], "p": ["ip", "arp", "inspection"], "h": func(_r): return _dai(true)},
			{"m": ["config"], "p": ["no", "ip", "arp", "inspection"], "h": func(_r): return _dai(false)},
			{"m": ["if"], "p": ["ip", "dhcp", "snooping", "trust"], "h": func(_r): return _trust(true)},
			{"m": ["if"], "p": ["no", "ip", "dhcp", "snooping", "trust"], "h": func(_r): return _trust(false)},
			{"m": EP, "p": ["show", "ip", "dhcp", "snooping"], "h": _show_snoop},
			{"m": ["if"], "p": ["ip", "address"], "h": _if_ip},
			{"m": ["if"], "p": ["ipv6", "address"], "h": _if_ip},
			{"m": EP, "p": ["show", "ipv6", "interface", "brief"], "h": _show_v6_brief},
			{"m": EP, "p": ["show", "ipv6", "neighbors"], "h": _show_neighbors},
			{"m": ["if"], "p": ["ip", "nat"], "h": _if_nat, "dyn": func(): return ["inside", "outside"]},
			{"m": ["if"], "p": ["vrrp"], "h": _if_vrrp},
			{"m": ["if"], "p": ["channel-group"], "h": _if_lag},
			{"m": ["if"], "p": ["ip", "helper-address"], "h": _if_helper},
			{"m": ["if"], "p": ["no", "ip", "helper-address"], "h": func(_r): ctx_if.helper = ""; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "channel-group"], "h": func(_r): ctx_if.lag = 0; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "vrrp"], "h": func(_r): ctx_if.vrrp = {}; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "ip", "nat"], "h": func(_r): ctx_if.nat = ""; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "ip", "address"], "h": _if_no_ip},
			{"m": ["if"], "p": ["shutdown"], "h": func(_r): return _each(func(i): i.enabled = false; return "")},
			{"m": ["if"], "p": ["no", "shutdown"], "h": func(_r): return _each(func(i): i.enabled = true; return "")},
			{"m": ["if"], "p": ["mtu"], "h": _if_mtu},
			{"m": ["if"], "p": ["qos", "priority-queueing"], "h": func(_r): return _qos(true)},
			{"m": ["if"], "p": ["no", "qos", "priority-queueing"], "h": func(_r): return _qos(false)},
			{"m": EP, "p": ["show", "qos"], "h": _show_qos},
			{"m": ["if"], "p": ["encapsulation", "dot1q"], "h": _if_encap},
			{"m": ["if"], "p": ["wireguard", "peer"], "h": _wg_peer},
			{"m": ["if"], "p": ["no", "wireguard", "peer"], "h": _wg_no_peer},
			{"m": EP, "p": ["show", "wireguard"], "h": _show_wg},
			{"m": ["if"], "p": ["tunnel", "source"], "h": _tunnel_src},
			{"m": ["if"], "p": ["tunnel", "destination"], "h": _tunnel_dst},
			{"m": EP, "p": ["show", "tunnels"], "h": _show_tunnels},
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
		# an exactly typed keyword beats one that merely starts the same way,
		# so "ip address" is not ambiguous with "ipv6 address"
		var best_exact := -1
		for c in full:
			var exact := 0
			for k in mini(toks.size(), c["p"].size()):
				if String(c["p"][k]) == toks[k]:
					exact += 1
			best_exact = maxi(best_exact, exact)
		full = full.filter(func(c):
			var exact := 0
			for k in mini(toks.size(), c["p"].size()):
				if String(c["p"][k]) == toks[k]:
					exact += 1
			return exact == best_exact)
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
				if String(cmd["p"][k]) == toks[k] and String(c["p"][k]) != toks[k]:
					pref = false  # we typed that keyword exactly; this one is not it
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
		## ping <ip> [size <bytes>], the Arista-style spelling
		if r.size() == 3 and String(r[1]) == "size" and String(r[2]).is_valid_int():
			return CLI.fmt_ping(dev, String(r[0]), int(r[2]))
		if r.size() != 1:
			return "usage: ping <ip> [size <bytes>]\n"
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

	func _select_ifaces(list: Array) -> void:
		ctx_ifs = list
		ctx_if = list[0] if not list.is_empty() else null
		mode = "if"

	func _range_only(what: String) -> String:
		return "%% %s cannot be applied to a range of interfaces\n" % what

	func _each(fn: Callable) -> String:
		for i: Net.Iface in ctx_ifs:
			var err: String = fn.call(i)
			if err != "":
				return err
		Game.topology_changed.emit()
		return ""

	func _cfg_if_range(r: Array) -> String:
		## interface range Ethernet1-8  (or et1-8, or a comma list)
		if r.size() != 1:
			return "usage: interface range <first>-<last>[,<more>]\n"
		var picked: Array = []
		for part in String(r[0]).split(",", false):
			var bits := String(part).split("-")
			if bits.size() == 2:
				var pfx := String(bits[0]).rstrip("0123456789")
				var lo := int(String(bits[0]).substr(pfx.length()))
				var hi := int(bits[1])
				for n in range(lo, hi + 1):
					var found := _find_iface("%s%d" % [pfx, n])
					if found:
						picked.append(found)
			else:
				var one := _find_iface(String(part))
				if one:
					picked.append(one)
		if picked.is_empty():
			return "% no interfaces matched that range\n"
		_select_ifaces(picked)
		return ""

	func _find_iface(want_raw: String) -> Net.Iface:
		var want := want_raw.to_lower()
		var digits := want.lstrip("abcdefghijklmnopqrstuvwxyz")
		var letters := want.trim_suffix(digits)
		for i: Net.Iface in dev.ifaces:
			var idg := i.name.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
			if idg == digits and i.name.to_lower().begins_with(letters) and letters != "":
				return i
		return null

	func _cfg_interface(r: Array) -> String:
		if r.size() != 1:
			return "usage: interface <name>\n"
		var want := String(r[0]).to_lower()
		if want.begins_with("wg") and want.trim_prefix("wg").is_valid_int():
			var wif := Game.add_wireguard(dev, int(want.trim_prefix("wg")))
			if wif == null:
				return "% could not create the wireguard interface\n"
			_select_ifaces([wif])
			return ""
		if want.begins_with("tu") and want.lstrip("abcdefghijklmnopqrstuvwxyz").is_valid_int():
			if not dev.ip_forwarding:
				return "% tunnels need a router or firewall\n"
			var tnum := int(want.lstrip("abcdefghijklmnopqrstuvwxyz"))
			var tif := Game.add_tunnel(dev, tnum)
			if tif == null:
				return "% could not create the tunnel\n"
			_select_ifaces([tif])
			return ""
		if "." in want:  # 802.1Q subinterface, e.g. Ethernet1.10 or et1.10
			var bits := want.split(".")
			if bits.size() == 2 and String(bits[1]).is_valid_int():
				if not dev.ip_forwarding:
					return "% subinterfaces need a router or firewall\n"
				var parent_name := ""
				var pd := String(bits[0]).lstrip("abcdefghijklmnopqrstuvwxyz")
				for i: Net.Iface in dev.ifaces:
					if i.parent != "":
						continue
					var idg := i.name.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
					if idg == pd and i.name.to_lower().begins_with(String(bits[0]).trim_suffix(pd)):
						parent_name = i.name
				if parent_name == "":
					return "% no such parent interface\n"
				var sub_if := Game.add_subiface(dev, parent_name, int(bits[1]))
				if sub_if == null:
					return "% could not create the subinterface\n"
				_select_ifaces([sub_if])
				return ""
			return "% bad subinterface name\n"
		if want.begins_with("vl") and want.trim_prefix("vlan").trim_prefix("vl").is_valid_int():
			var vid := int(want.trim_prefix("vlan").trim_prefix("vl"))
			if not Game.is_l3_switch(dev):
				return "% this model has no L3 switching (SVIs need an Arivista-class switch)\n"
			if not dev.vlans.has(vid):
				return "%% VLAN %d does not exist yet: 'vlan %d' first\n" % [vid, vid]
			ctx_if = Game.add_svi(dev, vid)
			mode = "if"
			return ""
		for i: Net.Iface in dev.ifaces:
			var full := i.name.to_lower()
			var digits := i.name.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
			var letters := full.trim_suffix(digits.to_lower())
			var w_digits := want.lstrip("abcdefghijklmnopqrstuvwxyz")
			var w_letters := want.trim_suffix(w_digits)
			if w_digits == digits and w_letters != "" and letters.begins_with(w_letters):
				_select_ifaces([i])
				return ""
		return "% no such interface\n"

	func _sw_mode(r: Array) -> String:
		if dev.type != "switch":
			return "% switchport commands need a switch\n"
		for m in ["access", "trunk"]:
			if r.size() == 1 and m.begins_with(r[0]):
				return _each(func(i: Net.Iface) -> String:
					i.mode = m
					return "")
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
		return _each(func(i: Net.Iface) -> String:
			Game.set_access_vlan(i, vid)
			return "")

	func _dot1x(on: bool) -> String:
		if dev.type not in ["switch", "ap"]:
			return "% port authentication belongs on a switch or access point\n"
		return _each(func(i: Net.Iface) -> String:
			i.dot1x = on
			if not on:
				i.dot1x_ok = ""
			return "")

	func _cfg_radius(r: Array) -> String:
		if r.size() != 1 or not (r[0].is_valid_ip_address() or Net.is_v6(r[0])):
			return "usage: radius-server host <ip>\n"
		dev.radius = r[0]
		Game.topology_changed.emit()
		return ""

	func _show_dot1x(_r: Array) -> String:
		var out := "Authentication server: %s\n%-11s %-8s %s\n" % [
			dev.radius if dev.radius != "" else "(none)", "Port", "802.1X", "Authorised"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			if not i.dot1x:
				continue
			any = true
			out += "%-11s %-8s %s\n" % [EOS._short(i.name), "on",
				i.dot1x_ok if i.dot1x_ok != "" else "nobody yet"]
		return out if any else out + "  (no ports require authentication)\n"

	func _pvlan(role: String) -> String:
		if dev.type != "switch":
			return "% protected ports are a switch feature\n"
		return _each(func(i: Net.Iface) -> String:
			i.pvlan = role
			return "")

	func _storm(r: Array) -> String:
		if dev.type != "switch":
			return "% storm control is a switch feature\n"
		if r.size() != 1 or not String(r[0]).is_valid_int():
			return "usage: storm-control broadcast <frames>\n"
		return _each(func(i: Net.Iface) -> String:
			i.storm_limit = maxi(0, int(r[0]))
			return "")

	func _port_sec(on: bool) -> String:
		if dev.type != "switch":
			return "% port security is a switchport feature\n"
		return _each(func(i: Net.Iface) -> String:
			i.port_security = on
			if not on:
				i.secure_mac = ""
			return "")

	func _mlag_peer(other: String) -> String:
		if dev.type != "switch":
			return "% only switches pair up\n"
		if other == "":
			var was := dev.mlag_peer
			dev.mlag_peer = ""
			for d in Game.all_devices():
				if d.name == was:
					d.mlag_peer = ""
			Game.topology_changed.emit()
			return ""
		var peer: Net.NDevice = null
		for d in Game.all_devices():
			if d.name == other:
				peer = d
		if peer == null:
			return "% no device named %s\n" % other
		if peer == dev or peer.type != "switch":
			return "% the peer must be another switch\n"
		dev.mlag_peer = peer.name
		peer.mlag_peer = dev.name  # a pair is a pair from both sides
		Game.topology_changed.emit()
		return ""

	func _mlag_if(id: int) -> String:
		if dev.type != "switch":
			return "% only switches pair up\n"
		for i: Net.Iface in ctx_ifs:
			i.mlag_peerlink = id == -1
			i.mlag = 0 if id <= 0 else id
			if id > 0:
				i.mode = "access" if i.mode == "routed" else i.mode
		Game.topology_changed.emit()
		return ""

	func _show_mlag(_r: Array) -> String:
		if dev.mlag_peer == "":
			return "MLAG is not configured\n"
		var peer := Sim.mlag_peer_of(dev)
		var out := "peer      : %s (%s)\n" % [dev.mlag_peer, "up" if peer != null else "down"]
		var pl := Sim.mlag_peerlink(dev)
		out += "peer-link : %s\n" % (EOS._short(pl.name) if pl != null else "none: the pair cannot stay in step")
		out += "%-6s %-12s %s\n" % ["ID", "LOCAL", "PEER"]
		for i: Net.Iface in dev.ifaces:
			if i.mlag <= 0:
				continue
			var far := Sim.mlag_port(peer, i.mlag) if peer != null else null
			out += "%-6d %-12s %s\n" % [i.mlag, "%s %s" % [EOS._short(i.name),
				"up" if Game.link_at(i) != null and i.enabled else "down"],
				("%s %s" % [EOS._short(far.name), "up" if Game.link_at(far) != null and far.enabled else "down"]) if far != null else "missing"]
		return out

	func _show_flows(_r: Array) -> String:
		if not dev.ip_forwarding:
			return "% flow accounting is a routing feature\n"
		if dev.talkers.is_empty():
			return "no flows recorded yet\n"
		var rows: Array = []
		for key in dev.talkers:
			rows.append([String(key), int(dev.talkers[key])])
		rows.sort_custom(func(x, y): return int(x[1]) > int(y[1]))
		var out := "%-38s %10s\n" % ["SOURCE > DESTINATION", "PACKETS"]
		for row in rows.slice(0, 15):
			out += "%-38s %10d\n" % [row[0], row[1]]
		return out

	func _show_snmp(_r: Array) -> String:
		if dev.snmp == "":
			return "SNMP agent: not running\n"
		return "SNMP agent: community %s (read-only)\n" % dev.snmp

	func _snmp(community: String) -> String:
		dev.snmp = community
		Game.topology_changed.emit()
		return ""

	func _igmp(on: bool) -> String:
		if dev.type not in ["switch", "ap"]:
			return "% IGMP snooping is a switch feature\n"
		dev.igmp_snooping = on
		if not on:
			dev.mcast_ports.clear()
		Game.topology_changed.emit()
		return ""

	func _show_igmp(_r: Array) -> String:
		var out := "IGMP snooping: %s\n" % ("on" if dev.igmp_snooping else "off")
		if dev.mcast_ports.is_empty():
			return out + "  (no groups heard yet)\n"
		out += "%-18s %s\n" % ["GROUP", "PORTS"]
		for grp in dev.mcast_ports:
			var names: Array = []
			for port in dev.mcast_ports[grp]:
				names.append(EOS._short(port.name))
			out += "%-18s %s\n" % [grp, ", ".join(PackedStringArray(names))]
		return out

	func _snoop(on: bool) -> String:
		if dev.type != "switch":
			return "% DHCP snooping is a switch feature\n"
		dev.snooping = on
		if not on:
			dev.bindings.clear()
		Game.topology_changed.emit()
		return ""

	func _dai(on: bool) -> String:
		if dev.type != "switch":
			return "% ARP inspection is a switch feature\n"
		dev.dai = on
		Game.topology_changed.emit()
		return ""

	func _trust(on: bool) -> String:
		if dev.type != "switch":
			return "% trust applies to switchports\n"
		return _each(func(i: Net.Iface) -> String:
			i.dhcp_trusted = on
			return "")

	func _show_snoop(_r: Array) -> String:
		var out := "DHCP snooping: %s     ARP inspection: %s\n" % [
			"on" if dev.snooping else "off", "on" if dev.dai else "off"]
		var trusted: Array = []
		for i: Net.Iface in dev.ifaces:
			if i.dhcp_trusted:
				trusted.append(EOS._short(i.name))
		out += "Trusted ports: %s\n" % (", ".join(PackedStringArray(trusted)) if trusted else "(none)")
		if dev.bindings.is_empty():
			out += "Bindings: (none yet)\n"
		else:
			out += "%-19s %s\n" % ["MAC", "LEASED ADDRESS"]
			for m in dev.bindings:
				out += "%-19s %s\n" % [m, dev.bindings[m]]
		return out

	func _show_port_sec(_r: Array) -> String:
		var out := "%-11s %-9s %-19s %s\n" % ["Port", "Security", "Secure MAC", "Violations"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			if not i.port_security:
				continue
			any = true
			out += "%-11s %-9s %-19s %d%s\n" % [EOS._short(i.name), "enabled",
				i.secure_mac if i.secure_mac else "(none learned)", i.violations,
				"   [SHUTDOWN]" if not i.enabled else ""]
		return out if any else "  (no ports secured: 'switchport port-security' under an interface)\n"

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
		if ctx_ifs.size() > 1:
			return _range_only("an address")
		if dev.type == "switch" and not ctx_if.name.begins_with("Management") \
				and not ctx_if.name.begins_with("Vlan"):
			return "% SVIs are not supported yet: use the Management1 port or a router\n"
		if r.size() != 1:
			return "usage: ip address <a.b.c.d/len>\n"
		return "" if Game.add_ip(ctx_if, r[0]) else "% invalid CIDR or duplicate\n"

	func _if_helper(r: Array) -> String:
		if not dev.ip_forwarding:
			return "% DHCP relay needs a router or firewall\n"
		if r.size() == 1 and String(r[0]).is_valid_ip_address():
			ctx_if.helper = r[0]
			Game.topology_changed.emit()
			return ""
		return "usage: ip helper-address <dhcp-server-ip>\n"

	func _if_lag(r: Array) -> String:
		if dev.type != "switch":
			return "% port-channels need a switch\n"
		if r.size() == 1 and String(r[0]).is_valid_int() and int(r[0]) >= 1:
			return _each(func(i: Net.Iface) -> String:
				i.lag = int(r[0])
				return "")
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
		if ctx_ifs.size() > 1:
			return _range_only("a VRRP group")
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

	func _wg_peer(r: Array) -> String:
		## wireguard peer <public-key> endpoint <ip> allowed <cidr>[,<cidr>]
		if not ctx_if.name.begins_with("wg"):
			return "% that is not a wireguard interface\n"
		if r.size() != 5 or String(r[1]) != "endpoint" or String(r[3]) != "allowed":
			return "usage: wireguard peer <key> endpoint <ip> allowed <cidr>[,<cidr>]\n"
		var allowed: Array = []
		for c in String(r[4]).split(",", false):
			if not Net.valid_cidr(String(c).strip_edges()):
				return "%% '%s' is not a prefix\n" % c
			allowed.append(String(c).strip_edges())
		for existing in ctx_if.wg_peers.duplicate():
			if String(existing.get("key", "")) == String(r[0]):
				ctx_if.wg_peers.erase(existing)
		ctx_if.wg_peers.append({"key": String(r[0]), "endpoint": String(r[2]), "allowed": allowed})
		Game.topology_changed.emit()
		return ""

	func _wg_no_peer(r: Array) -> String:
		if r.size() != 1:
			return "usage: no wireguard peer <key>\n"
		for existing in ctx_if.wg_peers.duplicate():
			if String(existing.get("key", "")) == String(r[0]):
				ctx_if.wg_peers.erase(existing)
		Game.topology_changed.emit()
		return ""

	func _show_wg(_r: Array) -> String:
		var out := ""
		for i: Net.Iface in dev.ifaces:
			if not i.name.begins_with("wg"):
				continue
			out += "interface %s   public key %s\n" % [i.name, i.wg_key]
			if i.wg_peers.is_empty():
				out += "   (no peers)\n"
			for p in i.wg_peers:
				out += "   peer %-18s endpoint %-16s allowed %-24s %s\n" % [p.get("key", ""),
					p.get("endpoint", ""), ", ".join(PackedStringArray(p.get("allowed", []))),
					"handshake ok" if Sim.wg_handshake(i, p) else "no handshake"]
		return out if out != "" else "  (no wireguard interfaces: 'interface wg0' creates one)\n"

	func _tunnel_src(r: Array) -> String:
		if not ctx_if.name.begins_with("Tunnel"):
			return "% that is not a tunnel interface\n"
		if r.size() != 1:
			return "usage: tunnel source <local-ip>\n"
		ctx_if.tunnel_src = r[0]
		Game.topology_changed.emit()
		return ""

	func _tunnel_dst(r: Array) -> String:
		if not ctx_if.name.begins_with("Tunnel"):
			return "% that is not a tunnel interface\n"
		if r.size() != 1:
			return "usage: tunnel destination <remote-ip>\n"
		ctx_if.tunnel_dst = r[0]
		Game.topology_changed.emit()
		return ""

	func _show_tunnels(_r: Array) -> String:
		var out := "%-10s %-18s %-18s %s\n" % ["Tunnel", "Source", "Destination", "State"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			if not i.name.begins_with("Tunnel"):
				continue
			any = true
			out += "%-10s %-18s %-18s %s\n" % [i.name, i.tunnel_src, i.tunnel_dst,
				"up" if Sim.tunnel_up(i) else "down (underlay unreachable or no peer)"]
		return out if any else "  (no tunnels: 'interface Tunnel1' creates one)\n"

	func _if_encap(r: Array) -> String:
		if ctx_if.parent == "":
			return "% encapsulation applies to subinterfaces (interface Et1.10)\n"
		if r.size() == 1 and String(r[0]).is_valid_int():
			if int(r[0]) != ctx_if.dot1q:
				return "%% this subinterface carries VLAN %d (it is named for it)\n" % ctx_if.dot1q
			return ""
		return "usage: encapsulation dot1q <vlan-id>\n"

	func _qos(on: bool) -> String:
		return _each(func(i: Net.Iface) -> String:
			i.qos = on
			return "")

	func _show_qos(_r: Array) -> String:
		var out := "%-11s %s\n" % ["Interface", "Policy"]
		for i: Net.Iface in dev.ifaces:
			if i.name == "lo":
				continue
			out += "%-11s %s\n" % [EOS._short(i.name),
				"priority queueing (service levels first)" if i.qos else "first come, first served"]
		return out

	func _if_mtu(r: Array) -> String:
		if r.size() == 1 and String(r[0]).is_valid_int() and int(r[0]) >= 576 and int(r[0]) <= 9216:
			return _each(func(i: Net.Iface) -> String:
				i.mtu = int(r[0])
				return "")
		return "usage: mtu <576-9216>\n"

	func _set_stateful(on: bool) -> String:
		if dev.type != "firewall":
			return "% stateful inspection needs a firewall\n"
		dev.stateful = on
		Game.topology_changed.emit()
		return ""

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
		var out := "mode: %s\n" % ("stateful (return traffic auto-permitted)" if dev.stateful else "stateless")
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
			dev.bgp["neighbors"].append({"ip": r[0], "remote_as": int(r[2]),
				"local_pref": 100, "prepend": 0, "prefix_in": [], "prefix_out": []})
			Game.topology_changed.emit()
			return ""
		var nb := _find_nb(String(r[0]) if r.size() > 0 else "")
		if nb.is_empty():
			return "usage: neighbor <ip> remote-as <asn> | local-preference <n> | prepend <n> | prefix-list in|out <cidr>[,...]\n"
		if r.size() == 3 and "local-preference".begins_with(r[1]) and String(r[2]).is_valid_int():
			nb["local_pref"] = int(r[2])  # higher wins: which upstream WE use
			Game.topology_changed.emit()
			return ""
		if r.size() == 2 and String(r[1]) == "rpki":
			nb["rpki"] = true  # ask this upstream to check origins against ROAs
			Game.topology_changed.emit()
			return ""
		if r.size() == 3 and String(r[0]).is_valid_ip_address() and String(r[1]) == "no" \
				and String(r[2]) == "rpki":
			nb["rpki"] = false
			Game.topology_changed.emit()
			return ""
		if r.size() == 3 and String(r[1]) == "prepend" and String(r[2]).is_valid_int():
			nb["prepend"] = clampi(int(r[2]), 0, 10)  # longer path: how THEY reach us
			Game.topology_changed.emit()
			return ""
		if r.size() == 4 and "prefix-list".begins_with(r[1]) and String(r[2]) in ["in", "out"]:
			var list: Array = []
			for part in String(r[3]).split(","):
				if part.strip_edges() != "":
					list.append(part.strip_edges())
			nb["prefix_%s" % r[2]] = list
			Game.topology_changed.emit()
			return ""
		return "usage: neighbor <ip> remote-as <asn> | local-preference <n> | prepend <n> | prefix-list in|out <cidr>[,...]\n"

	func _bgp_roa(r: Array) -> String:
		## roa <cidr>: sign a prefix as ours, so an upstream can reject anyone
		## else announcing it
		if r.size() != 1 or not String(r[0]).contains("/"):
			return "usage: roa <prefix/len>\n"
		if String(r[0]) not in dev.bgp.get("networks", []):
			return "%% announce %s first; signing a prefix you do not originate is meaningless\n" % r[0]
		if not dev.bgp.has("roa"):
			dev.bgp["roa"] = []
		if String(r[0]) not in dev.bgp["roa"]:
			dev.bgp["roa"].append(String(r[0]))
		Game.topology_changed.emit()
		return ""

	func _find_nb(ip: String) -> Dictionary:
		for nb in dev.bgp.get("neighbors", []):
			if String(nb["ip"]) == ip:
				return nb
		return {}

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
			var policy: Array = []
			if int(nb.get("local_pref", 100)) != 100:
				policy.append("local-pref %d" % int(nb["local_pref"]))
			if int(nb.get("prepend", 0)) > 0:
				policy.append("prepend x%d" % int(nb["prepend"]))
			if not nb.get("prefix_in", []).is_empty():
				policy.append("in: %s" % ",".join(PackedStringArray(nb["prefix_in"])))
			if not nb.get("prefix_out", []).is_empty():
				policy.append("out: %s" % ",".join(PackedStringArray(nb["prefix_out"])))
			if bool(nb.get("rpki", false)):
				policy.append("rpki validating")
			if not policy.is_empty():
				out += "                 policy: %s\n" % "   ".join(PackedStringArray(policy))
		if not dev.bgp["networks"].is_empty():
			out += "Announcing: %s\n" % ", ".join(PackedStringArray(dev.bgp["networks"]))
		var roas: Array = dev.bgp.get("roa", [])
		out += "Signed (ROA): %s\n" % (", ".join(PackedStringArray(roas)) if not roas.is_empty()
			else "nothing: an unsigned prefix cannot be defended")
		for h in Game.hijacks:
			out += "HIJACK: %s/%d is being announced by %s\n" % [h["prefix"], int(h["plen"]), h["by"]]
		return out

	func _cfg_ssid(r: Array) -> String:
		## ssid <name> vlan <id>
		if r.size() != 3 or String(r[1]) != "vlan" or not String(r[2]).is_valid_int():
			return "usage: ssid <name> vlan <id>\n"
		var err := Game.set_ssid(dev, String(r[0]), int(r[2]))
		return "" if err == "" else "%% %s\n" % err

	func _show_ssid(_r: Array) -> String:
		if dev.type != "ap":
			return "% only an access point broadcasts an SSID\n"
		if dev.ssids.is_empty():
			return "  (no SSIDs: 'ssid <name> vlan <id>' creates one)\n"
		var out := "%-18s %-6s %s\n" % ["SSID", "VLAN", "ASSOCIATED"]
		for name in dev.ssids:
			var clients: Array = []
			for radio: Net.Iface in dev.ifaces:
				if not radio.name.begins_with("radio"):
					continue
				var l := Game.link_at(radio)
				if l and radio.untagged_vlan == int(dev.ssids[name]):
					clients.append(l.other(radio).dev.name)
			out += "%-18s %-6d %s\n" % [name, int(dev.ssids[name]),
				", ".join(PackedStringArray(clients)) if clients else "-"]
		return out

	func _cfg_vip(r: Array) -> String:
		## virtual-server <vip> members <ip>,<ip>
		if dev.type != "loadbalancer":
			return "% virtual servers live on a load balancer\n"
		if r.size() != 3 or String(r[1]) != "members":
			return "usage: virtual-server <vip> members <ip>,<ip>\n"
		var members: Array = []
		for m in String(r[2]).split(",", false):
			members.append(String(m).strip_edges())
		if members.is_empty():
			return "% name at least one pool member\n"
		dev.services["lb"] = {"vip": String(r[0]), "members": members, "healthy": []}
		Game.lb_health_check()
		Game.topology_changed.emit()
		return ""

	func _cfg_no_vip(_r: Array) -> String:
		dev.services.erase("lb")
		Game.topology_changed.emit()
		return ""

	func _show_vip(_r: Array) -> String:
		var svc: Dictionary = dev.services.get("lb", {})
		if svc.is_empty():
			return "  (no virtual server configured)\n"
		var out := "Virtual server %s\n%-18s %s\n" % [svc["vip"], "MEMBER", "STATE"]
		for m in svc["members"]:
			out += "%-18s %s\n" % [m, "in service" if m in svc.get("healthy", []) else "out of service"]
		return out

	func _cfg_vrf(r: Array) -> String:
		if r.size() != 1:
			return "usage: ip vrf <name>\n"
		if Game.add_vrf(dev, r[0]):
			return ""
		return "% could not create that table (routers only, and names are unique)\n"

	func _if_vrf(r: Array) -> String:
		if ctx_ifs.size() > 1:
			return _range_only("a routing table")
		if r.size() != 1:
			return "usage: ip vrf forwarding <name>\n"
		if Game.set_iface_vrf(ctx_if, r[0]):
			return "Interface moved to table '%s'. Its addresses were cleared.\n" % r[0]
		return "%% no table called '%s'\n" % r[0]

	func _show_vrf(_r: Array) -> String:
		if dev.vrfs.is_empty():
			return "  (only the global table)\n"
		var out := "%-14s %s\n" % ["TABLE", "INTERFACES"]
		for name in dev.vrfs:
			var members: Array = []
			for i: Net.Iface in dev.ifaces:
				if i.vrf == name:
					members.append(EOS._short(i.name))
			out += "%-14s %s\n" % [name, ", ".join(PackedStringArray(members))]
		return out

	func _cfg_ip_route(r: Array) -> String:
		if not dev.ip_forwarding:
			return "% static routing needs a router\n"
		# ip route <prefix/len> <next-hop> [vrf <name>]
		var vrf := ""
		if r.size() == 4 and String(r[2]) == "vrf":
			vrf = String(r[3])
			r = [r[0], r[1]]
		if r.size() == 2 and Net.valid_cidr(r[0]):
			var parts := String(r[0]).split("/")
			if Game.add_static_route(dev, parts[0], int(parts[1]), r[1], vrf):
				return ""
		return "usage: ip route <prefix/len> <next-hop> [vrf <name>]\n"

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
			out += "%-6d %-16s %s\n" % [vid, dev.vlans[vid], UILayer.compress_ports(ports)]
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

	func _bfd(on: bool) -> String:
		for i: Net.Iface in ctx_ifs:
			i.bfd = on
		Game.topology_changed.emit()
		return ""

	func _show_bfd(_r: Array) -> String:
		var out := "%-12s %-10s %s\n" % ["Interface", "Session", "Peer"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			if not i.bfd:
				continue
			any = true
			out += "%-12s %-10s %s\n" % [EOS._short(i.name), Sim.bfd_session(i),
				Game.peer_label(i) if Game.peer_label(i) != "" else "-"]
		return out if any else "no BFD sessions configured\n"

	func _stp_mode(r: Array) -> String:
		if dev.type != "switch":
			return "% spanning tree runs on switches\n"
		var want: String = String(r[0]).to_lower() if r.size() > 0 else ""
		if want not in ["stp", "rstp", "mst"]:
			return "usage: spanning-tree mode stp|rstp|mst\n"
		dev.stp_mode = want
		Sim.flush_learned_state()
		Game.topology_changed.emit()
		return ""

	func _stp_priority(r: Array) -> String:
		if dev.type != "switch":
			return "% spanning tree runs on switches\n"
		if r.size() < 1 or not String(r[0]).is_valid_int():
			return "usage: spanning-tree priority <0-61440>\n"
		dev.stp_priority = clampi(int(r[0]), 0, 61440)
		Sim.flush_learned_state()
		Game.topology_changed.emit()
		return ""

	func _stp_mst(r: Array) -> String:
		## spanning-tree mst instance <n> vlan <list>
		if dev.type != "switch":
			return "% spanning tree runs on switches\n"
		if r.size() < 4 or r[0] != "instance" or r[2] != "vlan":
			return "usage: spanning-tree mst instance <n> vlan <ids>\n"
		var vids: Array = []
		for part in String(r[3]).split(","):
			if part.is_valid_int():
				vids.append(int(part))
		if vids.is_empty():
			return "% no valid VLAN ids\n"
		dev.mst_instances[int(r[1])] = vids
		dev.stp_mode = "mst"
		Sim.flush_learned_state()
		Game.topology_changed.emit()
		return ""

	func _show_stp(_r: Array) -> String:
		if dev.type != "switch":
			return "% spanning tree runs on switches\n"
		var root := Sim.stp_root_of(dev)
		var out := "Mode: %s   priority %d\n" % [dev.stp_mode.to_upper(), dev.stp_priority]
		out += "Root bridge: %s%s\n" % [root.name if root else "-",
			"  (this switch)" if root == dev else ""]
		if dev.stp_mode == "mst" and not dev.mst_instances.is_empty():
			for inst in dev.mst_instances:
				out += "  instance %s: vlans %s\n" % [inst,
					",".join(PackedStringArray(dev.mst_instances[inst].map(func(v): return str(v))))]
		out += "%-11s %-11s %-12s %s\n" % ["Port", "Role", "State", "Instances"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			var l := Game.link_at(i)
			if l == null or l.other(i).dev.type != "switch":
				continue
			any = true
			var per: Array = []
			for inst2 in Sim.mst_instances():
				per.append("%s:%s" % [inst2,
					"disc" if Sim._stp_blocked_inst.get(inst2, {}).has(i) else "fwd"])
			var blocked := Sim.stp_blocked(i)
			out += "%-11s %-11s %-12s %s\n" % [EOS._short(i.name),
				"alternate" if blocked else "designated",
				"discarding" if blocked else "forwarding",
				" ".join(PackedStringArray(per))]
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
				out += "C  %s/%s is directly connected, %s%s\n" % [parts[0], parts[1],
					EOS._short(i.name), "" if i.vrf == "" else "   [vrf %s]" % i.vrf]
		for r in dev.static_routes:
			out += "S  %s/%d [1/0] via %s\n" % [r["prefix"], int(r["plen"]), r["via"]]
		for r in Sim._bgp_learned(dev):
			out += "B  %s/%d [20/0] via %s\n" % [r["prefix"], int(r["plen"]), r["via"]]
		for r in Sim._ospf_learned(dev):
			out += "O  %s/%d [110/%d] via %s\n" % [r["prefix"], int(r["plen"]),
				int(r.get("cost", 10)), r["via"]]
		return out if out else "  (no routes: configure ip addresses)\n"

	func _show_v6_brief(_r: Array) -> String:
		var out := "%-11s %-30s %-8s\n" % ["Interface", "IPv6 Address", "Status"]
		for i: Net.Iface in dev.ifaces:
			var v6 := "unassigned"
			for cidr: String in i.ips:
				if Net.is_v6(cidr):
					v6 = cidr
			out += "%-11s %-30s %-8s\n" % [EOS._short(i.name), v6, "up" if i.enabled else "admin-down"]
		return out

	func _show_neighbors(_r: Array) -> String:
		var out := "%-30s %s\n" % ["IPv6 Address", "Link Layer"]
		var any := false
		for ip in dev.arp:
			if Net.is_v6(String(ip)):
				any = true
				out += "%-30s %s\n" % [ip, dev.arp[ip]]
		return out if any else "  (no neighbors discovered yet)\n"

	func _show_ip_brief(_r: Array) -> String:
		var out := "%-11s %-18s %-8s\n" % ["Interface", "IP Address", "Status"]
		for i: Net.Iface in dev.ifaces:
			var ip: String = i.ips[0] if not i.ips.is_empty() else "unassigned"
			out += "%-11s %-18s %-8s\n" % [EOS._short(i.name), ip, "up" if i.enabled else "admin-down"]
		return out

	func _write_mem(_r: Array) -> String:
		dev.startup = Game.device_config(dev)
		var n := Game.save_config_version(dev)
		return "Copy completed successfully. (saved as version %d)\n" % n

	func _save_template(r: Array) -> String:
		if r.size() != 1:
			return "usage: copy running-config template <name>\n"
		var err := Game.save_template(dev, r[0])
		return "Saved as template '%s'.\n" % r[0] if err == "" else "%% %s\n" % err

	func _apply_template(r: Array) -> String:
		if r.is_empty():
			return "usage: copy template <name> [running-config]\n"
		var name := String(r[0])
		for t in Game.templates:
			if t["name"] == name:
				var err := Game.apply_template(dev, t)
				return "Applied '%s'. Addresses were not touched.\n" % name if err == "" \
					else "%% %s\n" % err
		return "%% no template called '%s'\n" % name

	func _show_templates(_r: Array) -> String:
		if Game.templates.is_empty():
			return "  (none: 'copy running-config template <name>' saves one)\n"
		var out := "%-18s %s\n" % ["NAME", "FOR"]
		for t in Game.templates:
			out += "%-18s %s\n" % [t["name"], t["type"]]
		return out

	func _no_logging(_r: Array) -> String:
		dev.log_host = ""
		return ""

	func _cfg_logging(r: Array) -> String:
		if r.size() != 1 or not (r[0].is_valid_ip_address() or Net.is_v6(r[0])):
			return "usage: logging host <ip>\n"
		dev.log_host = r[0]
		Game.device_log(dev, "logging destination set to %s" % r[0])
		return ""

	func _cfg_ntp(r: Array) -> String:
		if r.size() != 1 or not (r[0].is_valid_ip_address() or Net.is_v6(r[0])):
			return "usage: ntp server <ip>\n"
		dev.ntp_server = r[0]
		return ""

	func _show_logging(_r: Array) -> String:
		var out := ""
		if dev.services.has("syslog"):
			var msgs: Array = dev.services["syslog"]["messages"]
			out += "Collector: %d message(s) received\n" % msgs.size()
			for m in msgs.slice(maxi(0, msgs.size() - 20)):
				out += "  %s\n" % m
			out += "--\n"
		out += "Local buffer%s:\n" % ("" if dev.log_host == "" else " (shipping to %s)" % dev.log_host)
		if dev.logs.is_empty():
			out += "  (empty)\n"
		for l in dev.logs.slice(maxi(0, dev.logs.size() - 15)):
			out += "  %s\n" % l
		return out

	func _show_clock(_r: Array) -> String:
		var sync := "synchronised to %s" % dev.ntp_server if dev.ntp_server != "" else "free running"
		return "cycle %d (device believes %d, %s)\n" % [Game.cycle, Game.cycle + dev.clock_skew, sync]

	func _show_versions(_r: Array) -> String:
		if dev.versions.is_empty():
			return "  (no saved versions: 'write memory' keeps one)\n"
		var out := "%-4s %s\n" % ["VER", "SAVED AT"]
		var n := 1
		for v in dev.versions:
			out += "%-4d cycle %d\n" % [n, int(v["cycle"])]
			n += 1
		return out

	func _show_diff(r: Array) -> String:
		## show config diff [version]: running against startup, or a version
		var base: Dictionary = dev.startup
		var label := "startup-config"
		if r.size() == 1 and String(r[0]).is_valid_int():
			var idx := int(r[0]) - 1
			if idx < 0 or idx >= dev.versions.size():
				return "% no such version\n"
			base = dev.versions[idx]["cfg"]
			label = "version %d" % (idx + 1)
		if base.is_empty():
			return "% nothing saved to compare against\n"
		var diff := Game.config_diff(base, Game.device_config(dev))
		if diff.is_empty():
			return "running-config matches %s\n" % label
		return "running-config vs %s:\n  %s\n" % [label, "\n  ".join(PackedStringArray(diff))]

	func _rollback(r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_int():
			return "usage: rollback <version>   (see 'show config versions')\n"
		var idx := int(r[0]) - 1
		if idx < 0 or idx >= dev.versions.size():
			return "% no such version\n"
		Game.apply_device_config(dev, dev.versions[idx]["cfg"])
		mode = "priv"
		ctx_if = null
		ctx_ifs = []
		return "Rolled back to version %d.\n" % (idx + 1)

	func _reload(_r: Array) -> String:
		var had := not dev.startup.is_empty()
		Game.apply_device_config(dev, dev.startup)
		mode = "exec"
		ctx_if = null
		if had:
			return "%s reloading... restored from startup-config.\n" % dev.name
		return "%s reloading... NO startup-config: it came back blank. ('write memory' next time.)\n" % dev.name

	func _show_startup(_r: Array) -> String:
		if dev.startup.is_empty():
			return "% no saved configuration ('write memory' to save the running config)\n"
		var live := Game.device_config(dev)
		var same: bool = JSON.stringify(live) == JSON.stringify(dev.startup)
		return "startup-config saved.%s\n" % ("" if same else "  WARNING: running-config differs (unsaved changes)")

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
		if dev.stateful:
			out += "firewall stateful\n!\n"
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
			if i.name == "lo":
				continue
			out += "interface %s\n" % i.name
			if i.parent != "":
				out += "   encapsulation dot1q %d\n" % i.dot1q
			if i.tunnel_src != "":
				out += "   tunnel source %s\n   tunnel destination %s\n" % [i.tunnel_src, i.tunnel_dst]
			for wp in i.wg_peers:
				out += "   wireguard peer %s endpoint %s allowed %s\n" % [wp.get("key", ""),
					wp.get("endpoint", ""), ",".join(PackedStringArray(wp.get("allowed", [])))]
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
			if i.helper != "":
				out += "   ip helper-address %s\n" % i.helper
			if not i.vrrp.is_empty():
				out += "   vrrp %d ip %s\n" % [int(i.vrrp["group"]), i.vrrp["vip"]]
				if int(i.vrrp.get("priority", 100)) != 100:
					out += "   vrrp %d priority %d\n" % [int(i.vrrp["group"]), int(i.vrrp["priority"])]
			if i.lag > 0:
				out += "   channel-group %d\n" % i.lag
			if i.port_security:
				out += "   switchport port-security\n"
			if i.dhcp_trusted:
				out += "   ip dhcp snooping trust\n"
			if i.pvlan == "isolated":
				out += "   switchport protected\n"
			if i.dot1x:
				out += "   dot1x\n"
			if i.storm_limit > 0:
				out += "   storm-control broadcast %d\n" % i.storm_limit
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
				return "  ip addr [add|del <cidr> dev <if>]\n  ip link set <if> up|down\n  ip route [add <cidr>|default via <gw>] [del <cidr>|default]\n  ping [-s <bytes>] <ip|name>   traceroute <ip|name>   hostname <name>   tcpdump   clear\n  ip neigh | arp                       ARP table\n  syslogd | logging <ip> | logs        central logging\n  vm create|addr|migrate|list          virtual machines\n  wg up|addr|peer|show                 wireguard tunnels\n  wifi join|leave|status <ssid>        wireless\n  radiusd add|list <mac> [vlan]        who may join the network\n  igmp join|send|groups <group>        multicast\n  snmpd <community> | snmpd off        run a read-only SNMP agent\n  snmpwalk <addr> <community>          poll another device\n  flows                                what has been forwarded through here\n  bond <iface> <iface>                 one address over two cables\n  ntpd <ip>                            keep the clock honest\n  lldp                                 who is on the other end of my cables\n  dhclient <if>                        get an address automatically\n  dhcpd <if> <first> <last> <plen> [gw] [dns]   serve DHCP leases\n  dns add <name> <ip> [ttl]            host DNS records\n  dns delegate <zone> <ns-ip>          hand a subzone to another server\n  dns list | dns cache | dns flush     records, resolver cache, clear it\n  nslookup <name>   nameserver <ip>\n"
			"hostname":
				if t.size() == 1:
					return dev.name + "\n"
				return "" if Game.rename_device(dev, t[1]) else "hostname: invalid or duplicate name\n"
			"ping", "ping6":
				# ping -s <bytes> <target>, for finding an MTU mismatch
				var pargs := t.slice(1)
				var psize := 64
				if pargs.size() >= 2 and String(pargs[0]) == "-s" and String(pargs[1]).is_valid_int():
					psize = int(pargs[1])
					pargs = pargs.slice(2)
				if pargs.size() != 1:
					return "usage: ping [-s <bytes>] <ip|name>\n"
				return CLI.fmt_ping(dev, String(pargs[0]), psize)
			"traceroute":
				return CLI.fmt_traceroute(dev, t[1]) if t.size() == 2 else "usage: traceroute <ip>\n"
			"ip":
				var args6 := t.slice(1)
				if not args6.is_empty() and String(args6[0]) in ["-6", "-4"]:
					args6 = args6.slice(1)  # family flags are accepted and ignored
				return _ip(args6)
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
				return "dhcpd: serving %s-%s/%s on %s\n" % [t[2], t[3], t[4], t[1]]
			"vm":
				# vm create <name> | vm addr <name> <cidr> | vm migrate <name> <host> | vm list
				if t.size() >= 3 and t[1] == "create":
					var nic := Game.create_vm(dev, t[2])
					if nic == null:
						return "vm: could not create '%s' (servers only, names are unique)\n" % t[2]
					return "vm '%s' created with MAC %s\n" % [t[2], nic.mac]
				if t.size() == 4 and t[1] == "addr":
					var nic2 := Game.find_vm(t[2])
					if nic2 == null or nic2.dev != dev:
						return "vm: '%s' does not run here\n" % t[2]
					if Game.add_ip(nic2, t[3]):
						return ""
					return "vm: invalid or duplicate address\n"
				if t.size() == 4 and t[1] == "migrate":
					var target: Net.NDevice = null
					for d in Game.all_devices():
						if d.name == t[3]:
							target = d
					if target == null:
						return "vm: no host called '%s'\n" % t[3]
					var err := Game.migrate_vm(t[2], target)
					if err != "":
						return "vm: %s\n" % err
					return "vm '%s' now runs on %s. Its addresses came with it.\n" % [t[2], t[3]]
				if t.size() >= 2 and t[1] == "list":
					var out := ""
					for d in Game.all_devices():
						for i: Net.Iface in d.ifaces:
							if i.vm != "":
								out += "%-14s on %-10s %-19s %s\n" % [i.vm, d.name, i.mac,
									", ".join(PackedStringArray(i.ips))]
					return out if out != "" else "(no virtual machines)\n"
				return "usage: vm create <name> | vm addr <name> <cidr> | vm migrate <name> <host> | vm list\n"
			"bond":
				if t.size() < 3:
					return "usage: bond <iface> <iface> [...]  (one address, several cables)\n"
				var legs: Array = []
				for nm in t.slice(1):
					var found := _iface(String(nm))
					if found == null:
						return "bond: no interface %s\n" % nm
					legs.append(found)
				var gid := 1
				for i2: Net.Iface in dev.ifaces:
					gid = maxi(gid, i2.lag + 1)
				for idx in legs.size():
					var leg: Net.Iface = legs[idx]
					leg.lag = gid
					if idx > 0:
						leg.mac = legs[0].mac  # a bond presents one address
				Game.topology_changed.emit()
				return "bond%d: %s\n" % [gid, " ".join(PackedStringArray(t.slice(1)))]
			"snmpd":
				if t.size() >= 2 and t[1] == "off":
					dev.snmp = ""
					Game.topology_changed.emit()
					return "snmp agent stopped\n"
				if t.size() < 2:
					return "usage: snmpd <community> | snmpd off\n"
				dev.snmp = String(t[1])
				Game.topology_changed.emit()
				return "snmp agent listening, community %s\n" % t[1]
			"flows":
				if dev.talkers.is_empty():
					return "no flows recorded (this host does not forward traffic)\n"
				var frows: Array = []
				for fk in dev.talkers:
					frows.append([String(fk), int(dev.talkers[fk])])
				frows.sort_custom(func(x, y): return int(x[1]) > int(y[1]))
				var fout := "%-38s %10s\n" % ["SOURCE > DESTINATION", "PACKETS"]
				for frow in frows.slice(0, 15):
					fout += "%-38s %10d\n" % [frow[0], frow[1]]
				return fout
			"snmpwalk":
				if t.size() < 3:
					return "usage: snmpwalk <address> <community>\n"
				var poll := Sim.snmp_poll(dev, String(t[1]), String(t[2]))
				if not bool(poll["ok"]):
					return "snmpwalk: %s\n" % poll["why"]
				var out_s := "%s (%s) is %s\n" % [poll["name"], poll["model"], poll["status"]]
				out_s += "%-14s %-6s %10s %10s\n" % ["INTERFACE", "STATE", "TX", "RX"]
				for i3 in poll["ifaces"]:
					out_s += "%-14s %-6s %10d %10d\n" % [i3["name"],
						"up" if bool(i3["up"]) else "down", int(i3["tx"]), int(i3["rx"])]
				return out_s
			"igmp":
				if t.size() == 3 and t[1] == "join":
					var err := Sim.igmp_join(dev, t[2])
					return "joined %s\n" % t[2] if err == "" else "igmp: %s\n" % err
				if t.size() == 3 and t[1] == "send":
					var got := Sim.mcast_send(dev, t[2])
					return "sent to %s: %d member(s) received it\n" % [t[2], got]
				if t.size() >= 2 and t[1] == "groups":
					return "%s\n" % ", ".join(PackedStringArray(dev.mcast_groups)) \
						if not dev.mcast_groups.is_empty() else "(no groups joined)\n"
				return "usage: igmp join <group> | igmp send <group> | igmp groups\n"
			"radiusd":
				# radiusd add <mac> [vlan] | radiusd list
				if not dev.services.has("radius"):
					dev.services["radius"] = {"users": {}}
				if t.size() >= 3 and t[1] == "add":
					var vid := int(t[3]) if t.size() > 3 and String(t[3]).is_valid_int() else 0
					dev.services["radius"]["users"][t[2]] = vid
					Game.topology_changed.emit()
					return "radiusd: %s may join%s\n" % [t[2],
						" VLAN %d" % vid if vid > 0 else ""]
				if t.size() >= 2 and t[1] == "list":
					var users: Dictionary = dev.services["radius"]["users"]
					if users.is_empty():
						return "(nobody authorised yet)\n"
					var out := ""
					for u in users:
						out += "%-19s vlan %s\n" % [u, str(users[u]) if int(users[u]) > 0 else "-"]
					return out
				return "radiusd: collecting authentication requests\nusage: radiusd add <mac> [vlan] | radiusd list\n"
			"wifi":
				if t.size() == 3 and t[1] == "join":
					var err := Game.wifi_join(dev, t[2])
					return "associated with '%s'\n" % t[2] if err == "" else "wifi: %s\n" % err
				if t.size() >= 2 and t[1] == "leave":
					Game.wifi_leave(dev)
					return "disassociated\n"
				if t.size() >= 2 and t[1] == "status":
					return "associated with '%s'\n" % dev.wifi if dev.wifi != "" \
						else "not associated\n"
				return "usage: wifi join <ssid> | wifi leave | wifi status\n"
			"wg":
				# wg up <n> | wg addr <n> <cidr> | wg peer <n> <key> <endpoint> <allowed> | wg show
				if t.size() == 3 and t[1] == "up":
					var w := Game.add_wireguard(dev, int(t[2]))
					return "wg%s up with public key %s\n" % [t[2], w.wg_key] if w else "wg: failed\n"
				if t.size() == 4 and t[1] == "addr":
					var wi := _iface("wg%s" % t[2])
					if wi == null:
						return "wg: no such interface\n"
					return "" if Game.add_ip(wi, t[3]) else "wg: invalid address\n"
				if t.size() == 6 and t[1] == "peer":
					var wi2 := _iface("wg%s" % t[2])
					if wi2 == null:
						return "wg: no such interface\n"
					var allowed2: Array = []
					for c in String(t[5]).split(",", false):
						allowed2.append(String(c).strip_edges())
					wi2.wg_peers.append({"key": t[3], "endpoint": t[4], "allowed": allowed2})
					Game.topology_changed.emit()
					return ""
				if t.size() >= 2 and t[1] == "show":
					var out := ""
					for i: Net.Iface in dev.ifaces:
						if not i.name.begins_with("wg"):
							continue
						out += "%s  key %s  %s\n" % [i.name, i.wg_key,
							", ".join(PackedStringArray(i.ips))]
						for p in i.wg_peers:
							out += "  peer %s via %s allowed %s  %s\n" % [p.get("key", ""),
								p.get("endpoint", ""),
								",".join(PackedStringArray(p.get("allowed", []))),
								"handshake ok" if Sim.wg_handshake(i, p) else "no handshake"]
					return out if out != "" else "(no wireguard interfaces)\n"
				return "usage: wg up <n> | wg addr <n> <cidr> | wg peer <n> <key> <endpoint> <allowed> | wg show\n"
			"syslogd":
				dev.services["syslog"] = dev.services.get("syslog", {"messages": []})
				return "syslogd: collecting logs on this host\n"
			"logging":
				if t.size() == 2 and (t[1].is_valid_ip_address() or Net.is_v6(t[1])):
					dev.log_host = t[1]
					return ""
				return "usage: logging <collector-ip>\n"
			"ntpd":
				if t.size() == 2 and (t[1].is_valid_ip_address() or Net.is_v6(t[1])):
					dev.ntp_server = t[1]
					return "ntpd: syncing to %s\n" % t[1]
				return "usage: ntpd <server-ip>\n"
			"logs":
				var out := ""
				if dev.services.has("syslog"):
					var msgs: Array = dev.services["syslog"]["messages"]
					out += "collector: %d message(s)\n" % msgs.size()
					for m in msgs.slice(maxi(0, msgs.size() - 20)):
						out += "  %s\n" % m
				for l in dev.logs.slice(maxi(0, dev.logs.size() - 15)):
					out += "  %s\n" % l
				return out if out != "" else "(no logs)\n"
			"dns":
				if t.size() >= 4 and t[1] == "add" and String(t[3]).is_valid_ip_address():
					if not dev.services.has("dns"):
						dev.services["dns"] = {"records": {}}
					dev.services["dns"]["records"][t[2]] = t[3]
					if t.size() > 4 and String(t[4]).is_valid_int():
						if not dev.services["dns"].has("ttls"):
							dev.services["dns"]["ttls"] = {}
						dev.services["dns"]["ttls"][t[2]] = int(t[4])
					Game.topology_changed.emit()
					return ""
				if t.size() == 4 and t[1] == "delegate" and String(t[3]).is_valid_ip_address():
					if not dev.services.has("dns"):
						dev.services["dns"] = {"records": {}}
					if not dev.services["dns"].has("delegations"):
						dev.services["dns"]["delegations"] = {}
					dev.services["dns"]["delegations"][t[2]] = t[3]
					Game.topology_changed.emit()
					return "%s delegated to %s\n" % [t[2], t[3]]
				if t.size() == 2 and t[1] == "flush":
					dev.dns_cache.clear()
					return "resolver cache cleared\n"
				if t.size() == 2 and t[1] == "cache":
					if dev.dns_cache.is_empty():
						return "(cache empty)\n"
					var cout := "%-24s %-16s %s\n" % ["NAME", "ADDRESS", "EXPIRES"]
					for nm2 in dev.dns_cache:
						cout += "%-24s %-16s cycle %d\n" % [nm2, dev.dns_cache[nm2]["ip"],
							int(dev.dns_cache[nm2]["expires"])]
					return cout
				if t.size() == 2 and t[1] == "list":
					var svc_d: Dictionary = dev.services.get("dns", {})
					var recs: Dictionary = svc_d.get("records", {})
					var dels: Dictionary = svc_d.get("delegations", {})
					if recs.is_empty() and dels.is_empty():
						return "(no records: this host is not a DNS server yet)\n"
					var out := ""
					for k in recs:
						out += "%-24s A   %-16s ttl %d\n" % [k, recs[k],
							int(svc_d.get("ttls", {}).get(k, Sim.DEFAULT_TTL))]
					for z in dels:
						out += "%-24s NS  %s\n" % [z, dels[z]]
					return out
				return "usage: dns add <name> <ip> [ttl] | dns delegate <zone> <ns-ip> | dns list | dns cache | dns flush\n"
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
				opts = ["ip", "ping", "ping6", "traceroute", "hostname", "tcpdump", "dhclient", "dhcpd", "dns", "nslookup", "nameserver", "arp", "lldp", "ssh", "syslogd", "logging", "logs", "ntpd", "vm", "wg", "wifi", "radiusd", "igmp", "bond", "snmpd", "snmpwalk", "flows", "exit", "clear", "help"]
			1:
				if toks[0] == "ip":
					opts = ["addr", "link", "route", "neigh"]
				elif toks[0] == "vm":
					opts = ["create", "addr", "migrate", "list"]
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
