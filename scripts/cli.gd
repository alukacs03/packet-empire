class_name CLI
## Session-based device CLIs. Switches and routers speak Arista/Cisco-style
## EOS (modes, abbreviations, show running-config); servers speak Linux.
## Everything mutates the same Game state the web UI renders.

static func new_session(dev: Net.NDevice) -> Session:
	if Game.MODELS.get(dev.model, {}).get("os", "") == "ros":
		return ROS.new(dev)
	return EOS.new(dev) if dev.type in ["switch", "router", "firewall", "uplink",
		"loadbalancer", "ap"] else LinuxCLI.new(dev)

static func try_ssh(session: Session, target: String) -> String:
	var ip := Sim.resolve(session.dev, target)
	if ip == "":
		ip = target
	if not ip.is_valid_ip_address():
		return "ssh: Could not resolve hostname %s: Name or service not known\n" % target
	var owner := Sim._ip_owner(ip)
	if owner == null or owner == session.dev or not Sim.ping(session.dev, ip)["ok"]:
		return "ssh: connect to host %s port 22: No route to host\n" % ip
	var admit := Sim.aaa_admit(owner)
	if not bool(admit["ok"]):
		return "ssh: %s: authentication failed (%s)\n" % [owner.name, admit["why"]]
	session.pending_ssh = owner
	var note := "" if String(admit["why"]) == "" else "  [%s]" % admit["why"]
	var from := Sim._first_ip(Sim._connected_iface(session.dev, ip)) if Sim._connected_iface(session.dev, ip) != null else session.dev.name
	return "Last login: %s from %s%s\n" % [Time.get_datetime_string_from_system(false, true).replace("T", " "), from, note]

static func fmt_ping(dev: Net.NDevice, target: String, size := 64) -> String:
	var ip := Sim.resolve(dev, target)
	if ip == "":
		return "ping: %s: Name or service not known\n" % target
	var r := Sim.ping(dev, ip, 64, "", size)
	# Linux counts the payload in the header (56 by default) and the whole
	# ICMP message in the reply line (64): size here is the reply figure
	var out := "PING %s (%s) %d(%d) bytes of data.\n" % [target, ip, size - 8, size + 20]
	if r["ok"]:
		var base: float = maxf(0.04, float(r.get("rtt", 0.1)))
		var rtts: Array = []
		for seq in [1, 2, 3]:
			var rtt: float = base * (1.0 + 0.04 * seq)
			rtts.append(rtt)
			out += "%d bytes from %s: icmp_seq=%d ttl=%d time=%.2f ms\n" % [size, r["from"], seq,
				int(r.get("ttl", 64)), rtt]
		return out + "\n--- %s ping statistics ---\n3 packets transmitted, 3 received, 0%% packet loss, time 2003ms\nrtt min/avg/max/mdev = %.3f/%.3f/%.3f/%.3f ms\n" % [
			target, rtts[0], (rtts[0] + rtts[1] + rtts[2]) / 3.0, rtts[2], (rtts[2] - rtts[0]) / 2.0]
	if r["detail"] == "ttl-exceeded":
		return out + "From %s icmp_seq=1 Time to live exceeded\n\n--- %s ping statistics ---\n3 packets transmitted, 0 received, +3 errors, 100%% packet loss, time 2003ms\n" % [r["from"], target]
	if String(r["detail"]).begins_with("unreachable-"):
		return out + "From %s icmp_seq=1 %s\n3 packets transmitted, 0 received, +3 errors, 100%% packet loss\n" % [
			r["from"], unreachable_text(String(r["detail"]))]
	if r["detail"] == "timeout":
		return out + "\n--- %s ping statistics ---\n3 packets transmitted, 0 received, 100%% packet loss, time 2003ms\n" % target
	return out + "ping: %s\n" % r["detail"]

static func fold_mask(r: Array) -> Array:
	## IOS spells a prefix as "10.0.0.0 255.255.255.0"; turn that into 10.0.0.0/24
	## so the rest of the parser only ever sees CIDR.
	if r.size() >= 2 and String(r[0]).is_valid_ip_address() and not String(r[0]).contains(":") \
			and String(r[1]).is_valid_ip_address() and not String(r[1]).contains(":"):
		var plen := mask_to_plen(String(r[1]))
		if plen >= 0:
			var folded: Array = ["%s/%d" % [r[0], plen]]
			folded.append_array(r.slice(2))
			return folded
	return r

static func plen_to_mask(plen: int) -> String:
	## 24 -> 255.255.255.0, the way dhcpd.conf and IOS spell a prefix length
	var bits := ((1 << plen) - 1) << (32 - plen) if plen > 0 else 0
	return Net.int_to_ip(bits & 0xFFFFFFFF)

static func mask_to_plen(mask: String) -> int:
	## 255.255.255.0 -> 24; -1 for anything that is not a contiguous mask
	var v := Net.ip_to_int(mask)
	var plen := 0
	while plen < 32 and (v & (1 << (31 - plen))) != 0:
		plen += 1
	return plen if v == ((0xFFFFFFFF << (32 - plen)) & 0xFFFFFFFF if plen > 0 else 0) else -1

static func acl_rule_text(rule: Dictionary) -> String:
	## one rule the way show access-lists prints it
	var src := "any" if int(rule["splen"]) == 0 else "%s/%d" % [rule["src"], int(rule["splen"])]
	var dst := "any" if int(rule["dplen"]) == 0 else "%s/%d" % [rule["dst"], int(rule["dplen"])]
	var text := "%-7s %-5s %s -> %s" % [rule["action"], rule.get("proto", "ip"), src, dst]
	if int(rule.get("port", 0)) != 0:
		text += " eq %d" % int(rule["port"])
	if bool(rule.get("established", false)):
		text += " established"
	return text

static func acl_config_text(rule: Dictionary) -> String:
	## the same rule as a config line that the parser will take back
	var text := String(rule["action"])
	if String(rule.get("proto", "ip")) != "ip":
		text += " " + String(rule["proto"])
	for side in [["src", "splen"], ["dst", "dplen"]]:
		var plen := int(rule[side[1]])
		text += " any" if plen == 0 else " %s/%d" % [rule[side[0]], plen]
	if int(rule.get("port", 0)) != 0:
		text += " eq %d" % int(rule["port"])
	if bool(rule.get("established", false)):
		text += " established"
	return text

static func first_ip_of(dev: Net.NDevice) -> String:
	for i: Net.Iface in dev.ifaces:
		for cidr in i.ips:
			if not Net.is_v6(cidr):
				return String(cidr).split("/")[0]
	return "0.0.0.0"

static func dev_suffix(dev: Net.NDevice, via: String) -> String:
	## " dev eth0" for the interface a next hop sits behind, as iproute2 prints it
	var egress := Sim._connected_iface(dev, via)
	return (" dev %s" % egress.name) if egress != null else ""

static func unreachable_text(detail: String) -> String:
	## the words a Linux ping prints for each ICMP unreachable code
	match detail.trim_prefix("unreachable-"):
		"host": return "Destination Host Unreachable"
		"admin": return "Packet filtered"
	return "Destination Net Unreachable"

static func filter_output(text: String, needle: String) -> String:
	## Keeps the lines that match, and says so when none do, rather than
	## printing nothing and leaving somebody wondering.
	var kept: Array = []
	for line: String in text.split("\n"):
		if needle.to_lower() in line.to_lower():
			kept.append(line)
	if kept.is_empty():
		return "(no lines matching '%s')\n" % needle
	return "\n".join(PackedStringArray(kept)) + "\n"

static func fmt_ping_eos(dev: Net.NDevice, target: String, count: int, payload: int) -> String:
	## the ping an Arista box prints: Linux iputils with a 72-byte payload,
	## five probes 0.2 s apart, three-decimal times, and the ipg/ewma tail
	var ip := Sim.resolve(dev, target)
	if ip == "":
		return "ping: %s: Name or service not known\n" % target
	var out := "PING %s (%s) %d(%d) bytes of data.\n" % [target, ip, payload, payload + 28]
	var received := 0
	var errors := 0
	var rtts: Array = []
	for seq in count:
		var r := Sim.ping(dev, ip, 64, "", payload + 8)
		if bool(r["ok"]):
			received += 1
			var rtt := maxf(0.04, float(r.get("rtt", 0.1))) * (1.0 + 0.03 * seq)
			rtts.append(rtt)
			out += "%d bytes from %s: icmp_seq=%d ttl=%d time=%.3f ms\n" % [payload + 8, r["from"], seq + 1, int(r.get("ttl", 64)), rtt]
		else:
			var detail := String(r.get("detail", "timeout"))
			if detail == "no route to host":
				return "ping: connect: Network is unreachable\n"
			if detail == "ttl-exceeded":
				errors += 1
				out += "From %s icmp_seq=%d Time to live exceeded\n" % [r["from"], seq + 1]
			elif detail.begins_with("unreachable-"):
				errors += 1
				out += "From %s icmp_seq=%d %s\n" % [r["from"], seq + 1, unreachable_text(detail)]
			elif detail.begins_with("host unreachable"):
				errors += 1
				out += "From %s icmp_seq=%d Destination Host Unreachable\n" % [first_ip_of(dev), seq + 1]
	var lost := count - received
	out += "\n--- %s ping statistics ---\n%d packets transmitted, %d received, %s%d%% packet loss, time %dms\n" % [
		target, count, received, ("+%d errors, " % errors) if errors > 0 else "", int(round(100.0 * float(lost) / float(count))), (count - 1) * 200 + 2]
	if received > 0:
		var best := 9999.0
		var worst := 0.0
		var total := 0.0
		for v in rtts:
			best = minf(best, float(v))
			worst = maxf(worst, float(v))
			total += float(v)
		var avg := total / float(rtts.size())
		out += "rtt min/avg/max/mdev = %.3f/%.3f/%.3f/%.3f ms, ipg/ewma %.3f/%.3f ms\n" % [best, avg, worst, (worst - best) / 2.0, 200.0 + avg, avg]
	elif errors > 0:
		out += "pipe %d\n" % mini(count, 3)
	return out

static func fmt_ping_repeat(dev: Net.NDevice, target: String, count: int, size := 64) -> String:
	## Real loss statistics: each probe is a separate trip through the
	## simulation, so an intermittent fault shows up as intermittent.
	var ip := Sim.resolve(dev, target)
	if ip == "":
		return "ping: %s: Name or service not known\n" % target
	count = clampi(count, 1, 50)
	var out := "PING %s (%s) %d(%d) bytes of data.\n" % [target, ip, size, size + 28]
	var received := 0
	var best := 9999.0
	var worst := 0.0
	var total := 0.0
	var last_detail := ""
	for seq in count:
		var r := Sim.ping(dev, ip, 64, "", size)
		if bool(r["ok"]):
			received += 1
			var rtt := maxf(0.04, float(r.get("rtt", 0.1)))
			best = minf(best, rtt)
			worst = maxf(worst, rtt)
			total += rtt
			out += "%d bytes from %s: icmp_seq=%d ttl=%d time=%.2f ms\n" % [size, r["from"],
				seq + 1, int(r.get("ttl", 64)), rtt]
		else:
			last_detail = String(r.get("detail", "timeout"))
			if last_detail.begins_with("unreachable-"):
				out += "From %s icmp_seq=%d %s\n" % [r["from"], seq + 1, unreachable_text(last_detail)]
			else:
				out += "icmp_seq=%d %s\n" % [seq + 1, last_detail]
	var lost := count - received
	out += "%d packets transmitted, %d received, %d%% packet loss\n" % [count, received,
		int(round(100.0 * float(lost) / float(count)))]
	if received > 0:
		out += "rtt min/avg/max = %.2f/%.2f/%.2f ms\n" % [best, total / float(received), worst]
	elif last_detail != "":
		out += "every probe failed: %s\n" % last_detail
	return out

static func fmt_traceroute(dev: Net.NDevice, target: String, numeric := false) -> String:
	var ip := Sim.resolve(dev, target)
	if ip == "":
		return "traceroute: %s: Name or service not known\n" % target
	var out := "traceroute to %s (%s), 30 hops max, 60 byte packets\n" % [target, ip]
	var n := 1
	for hop in Sim.traceroute(dev, ip):
		if hop == "*":
			out += "%2d  * * *\n" % n
		else:
			var probe := Sim.ping(dev, String(hop))
			var rtt := maxf(0.04, float(probe.get("rtt", 0.1)))
			var name := "" if numeric else Sim.reverse_lookup(dev, String(hop))
			out += ("%2d  %s  %.3f ms  %.3f ms  %.3f ms\n" % [n, hop, rtt, rtt * 1.03, rtt * 0.98]) if numeric \
				else ("%2d  %s (%s)  %.3f ms  %.3f ms  %.3f ms\n" % [n, name if name != "" else hop, hop, rtt, rtt * 1.03, rtt * 0.98])
		n += 1
	return out

static func arp_iface_name(dev: Net.NDevice, ip: String) -> String:
	var i := Sim.arp_iface(dev, ip)
	if i != null:
		return i.name
	return dev.ifaces[0].name if not dev.ifaces.is_empty() else "-"

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
	var mode := "exec"  # exec | priv | config | if | vlan | router | ospf | dhcp | acl | dhcpsrv | dhcpsub
	var ctx_acl := ""  # the named access list being edited
	var ctx_po := 0  # the Port-Channel being configured: its members are ctx_ifs
	var ctx_rmap := ""  # the route-map being edited
	var ctx_rmap_seq := 10
	var ctx_subnet := ""  # the dhcp server subnet being edited
	var ctx_if: Net.Iface  # the first of ctx_ifs, for single-interface commands
	var ctx_ifs: Array = []  # every interface the current context applies to
	var ctx_vlan := 0
	var ctx_vlans: Array = []  # every VLAN the vlan context applies to
	var ctx_vlan_spec := ""  # how the range was typed, for the prompt
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
				if ctx_po > 0:
					return "%s(config-if-Po%d)#" % [dev.name, ctx_po]
				return "%s(config-if-%s)#" % [dev.name, _range_label()]
			"vlan":
				return "%s(config-vlan-%s)#" % [dev.name, ctx_vlan_spec if ctx_vlan_spec != "" else str(ctx_vlan)]
			"router":
				return dev.name + "(config-router-bgp)#"
			"ospf":
				return dev.name + "(config-router-ospf)#"
			"dhcp":
				return dev.name + "(dhcp-config)#"
			"acl":
				return "%s(config-acl-%s)#" % [dev.name, ctx_acl]
			"dhcpsrv":
				return dev.name + "(config-dhcp-server)#"
			"dhcpsub":
				return "%s(config-dhcp-server-subnet-%s)#" % [dev.name, ctx_subnet]
			"mlag":
				return dev.name + "(config-mlag)#"
			"mst":
				return dev.name + "(config-mst)#"
			"rmap":
				return "%s(config-route-map-%s)#" % [dev.name, ctx_rmap]
			"af":
				return dev.name + "(config-router-bgp-af)#"
			"vxlan":
				return dev.name + "(config-if-Vx1)#"
		return dev.name + ">"

	static func _short(ifname: String) -> String:
		for pair in [["Ethernet", "Et"], ["Management", "Ma"], ["Port-Channel", "Po"], ["Loopback", "Lo"],
				["Tunnel", "Tu"], ["Vlan", "Vl"], ["Vxlan", "Vx"]]:
			if ifname.begins_with(pair[0]):
				return pair[1] + ifname.trim_prefix(pair[0])
		return ifname

	func _range_label() -> String:
		## Et1-3 or Et1,3,5-6: the way the prompt names a range
		if ctx_ifs.size() <= 1:
			return _short(ctx_if.name)
		var prefix := ctx_if.name.rstrip("0123456789")
		var nums: Array = []
		for i: Net.Iface in ctx_ifs:
			if i.name.rstrip("0123456789") == prefix and i.name.substr(prefix.length()).is_valid_int():
				nums.append(int(i.name.substr(prefix.length())))
		if nums.size() != ctx_ifs.size():
			return _short(ctx_if.name) + ",..."
		nums.sort()
		var parts: Array = []
		var k := 0
		while k < nums.size():
			var j := k
			while j + 1 < nums.size() and int(nums[j + 1]) == int(nums[j]) + 1:
				j += 1
			parts.append(str(nums[k]) if j == k else "%d-%d" % [nums[k], nums[j]])
			k = j + 1
		return _short(prefix) + ",".join(PackedStringArray(parts))

	# ---- command table: {m: modes, p: path tokens, h: handler(rest)->String, dyn: Callable|null}
	func _build_cmds() -> void:
		var EP := ["exec", "priv", "config", "if", "vlan", "router", "ospf", "dhcp", "acl", "dhcpsrv", "dhcpsub", "mlag", "vxlan", "mst", "rmap", "af"]  # show/ping work everywhere via 'do'-free shortcut
		_cmds = [
			{"m": ["exec"], "p": ["enable"], "h": func(_r): mode = "priv"; return ""},
			{"m": ["config", "if", "vlan", "router", "ospf", "dhcp", "acl", "mlag", "vxlan", "mst", "rmap", "af"], "p": ["enable"], "h": func(_r): return ""},
			{"m": ["priv"], "p": ["disable"], "h": func(_r): mode = "exec"; return ""},
			{"m": ["priv"], "p": ["write", "memory"], "h": _write_mem},
			{"m": ["priv"], "p": ["write"], "h": _write_mem},
			{"m": ["priv"], "p": ["configure"], "h": func(_r): mode = "config"; return ""},
			{"m": ["if"], "p": ["description"], "h": _if_description},
			{"m": ["if"], "p": ["no", "description"], "h": func(_r): return _each(func(i): Game.set_note(i, ""); return "")},
			{"m": EP, "p": ["show", "interfaces", "description"], "h": _show_if_description},
			{"m": ["config"], "p": ["ip", "routing"], "h": func(_r): return "" if dev.ip_forwarding else "% IP routing is not supported on this platform\n"},
			{"m": EP, "p": ["show", "hostname"], "h": func(_r): return "Hostname: %s\nFQDN:     %s\n" % [dev.name, dev.name]},
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
			{"m": EP, "p": ["show", "ip", "arp"], "h": _show_arp},
			{"m": ["config"], "p": ["mac", "address-table", "static"], "h": _mac_static},
			{"m": ["config"], "p": ["no", "mac", "address-table", "static"], "h": _no_mac_static},
			{"m": ["priv"], "p": ["clear", "mac", "address-table", "dynamic"], "h": func(_r):
				dev.mac_table.clear()
				return ""},
			{"m": ["priv"], "p": ["clear", "arp-cache"], "h": func(_r):
				dev.arp.clear()
				return ""},
			{"m": EP, "p": ["show", "capture"], "h": _show_capture},
			{"m": EP, "p": ["show", "acl"], "h": _show_acl},
			{"m": EP, "p": ["show", "ip", "access-lists"], "h": _show_acl},
			{"m": EP, "p": ["show", "access-lists"], "h": _show_acl},
			{"m": EP, "p": ["show", "ip", "bgp", "summary"], "h": _show_bgp},
			{"m": EP, "p": ["show", "ip", "bgp"], "h": _show_bgp_table},
			{"m": EP, "p": ["show", "ip", "ospf", "neighbor"], "h": _show_ospf},
			{"m": EP, "p": ["show", "ip", "ospf", "interface"], "h": _show_ospf_interface},
			{"m": EP, "p": ["show", "ip", "ospf", "database"], "h": _show_ospf_database},
			{"m": ["if"], "p": ["ip", "ospf", "cost"], "h": func(r): return _if_ospf("costs", r, 1, 65535)},
			{"m": ["if"], "p": ["ip", "ospf", "priority"], "h": func(r): return _if_ospf("priorities", r, 0, 255)},
			{"m": EP, "p": ["show", "vrrp"], "h": _show_vrrp},
			{"m": EP, "p": ["show", "vrrp", "brief"], "h": _show_vrrp_brief},
			{"m": EP, "p": ["show", "interfaces", "trunk"], "h": _show_int_trunk},
			{"m": EP, "p": ["show", "port-channel"], "h": _show_lag},
			{"m": EP, "p": ["show", "port-channel", "summary"], "h": _show_lag},
			{"m": EP, "p": ["show", "etherchannel", "summary"], "h": _show_lag},
			{"m": EP, "p": ["show", "lldp", "neighbors"], "h": _show_lldp},
			{"m": EP, "p": ["show", "interfaces", "counters"], "h": _show_counters},
			{"m": EP, "p": ["show", "interfaces", "counters", "errors"], "h": _show_counter_errors},
			{"m": ["if"], "p": ["duplex"], "h": _if_duplex, "dyn": func(): return ["auto", "full", "half"]},
			{"m": ["priv"], "p": ["clear", "counters"], "h": _clear_counters},
			{"m": EP, "p": ["show", "spanning-tree"], "h": _show_stp},
			{"m": ["if"], "p": ["ipv6", "nd", "ra"], "h": func(_r): return _ra(true)},
			{"m": ["if"], "p": ["no", "ipv6", "nd", "ra"], "h": func(_r): return _ra(false)},
			{"m": ["if"], "p": ["bfd"], "h": func(_r): return _bfd(true)},
			{"m": ["if"], "p": ["no", "bfd"], "h": func(_r): return _bfd(false)},
			{"m": EP, "p": ["show", "bfd"], "h": _show_bfd},
			{"m": ["config"], "p": ["aaa", "authentication", "login"], "h": _aaa_login},
			{"m": ["config"], "p": ["no", "aaa"], "h": func(_r):
				dev.aaa = {}
				Game.topology_changed.emit()
				return ""},
			{"m": EP, "p": ["show", "aaa"], "h": _show_aaa},
			{"m": ["config"], "p": ["spanning-tree", "mode"], "h": _stp_mode},
			{"m": ["if"], "p": ["spanning-tree", "portfast"], "h": func(_r): return _stp_edge("portfast", true)},
			{"m": ["if"], "p": ["no", "spanning-tree", "portfast"], "h": func(_r): return _stp_edge("portfast", false)},
			{"m": ["if"], "p": ["spanning-tree", "bpduguard"], "h": func(r): return _stp_edge("bpduguard", r.is_empty() or String(r[0]) != "disable")},
			{"m": ["if"], "p": ["no", "spanning-tree", "bpduguard"], "h": func(_r): return _stp_edge("bpduguard", false)},
			{"m": ["config"], "p": ["spanning-tree", "priority"], "h": _stp_priority},
			{"m": ["config"], "p": ["spanning-tree", "mst", "configuration"], "h": func(_r):
				if dev.type != "switch":
					return "% Invalid input\n"
				mode = "mst"
				return ""},
			{"m": ["mst"], "p": ["instance"], "h": func(r): return _stp_mst(["instance"] + r)},
			{"m": ["mst"], "p": ["name"], "h": func(r):
				var mc: Dictionary = dev.services.get("mst", {})
				mc["name"] = " ".join(PackedStringArray(r))
				dev.services["mst"] = mc
				return ""},
			{"m": ["mst"], "p": ["revision"], "h": func(r):
				if r.size() != 1 or not String(r[0]).is_valid_int():
					return "% Incomplete command\n"
				var mc: Dictionary = dev.services.get("mst", {})
				mc["revision"] = int(r[0])
				dev.services["mst"] = mc
				return ""},
			{"m": EP, "p": ["show", "spanning-tree", "mst", "configuration"], "h": _show_mst_config},
			{"m": ["config"], "p": ["route-map"], "h": _cfg_route_map},
			{"m": ["config"], "p": ["no", "route-map"], "h": func(r):
				var maps: Dictionary = dev.services.get("route_maps", {})
				if r.size() >= 1:
					maps.erase(String(r[0]))
				return ""},
			{"m": ["rmap"], "p": ["set", "local-preference"], "h": func(r): return _rmap_set("local_pref", r)},
			{"m": ["rmap"], "p": ["set", "as-path", "prepend"], "h": func(r): return _rmap_set("prepend", [str(r.size())] if not r.is_empty() else [])},
			{"m": ["rmap"], "p": ["set", "community"], "h": func(_r): return ""},
			{"m": ["rmap"], "p": ["set", "metric"], "h": func(_r): return ""},
			{"m": ["rmap"], "p": ["match", "ip", "address", "prefix-list"], "h": func(r): return _rmap_set("prefix_list", r)},
			{"m": ["rmap"], "p": ["description"], "h": func(_r): return ""},
			{"m": EP, "p": ["show", "route-map"], "h": _show_route_maps},
			{"m": ["router"], "p": ["address-family", "ipv4"], "h": func(_r): mode = "af"; return ""},
			{"m": ["af"], "p": ["neighbor"], "h": _af_neighbor},
			{"m": ["config"], "p": ["spanning-tree", "mst"], "h": _stp_mst},
			{"m": EP, "p": ["show", "ip", "route"], "h": _show_ip_route},
			{"m": EP, "p": ["show", "ip", "route", "for"], "h": _show_route_for, "hidden": true},
			{"m": EP, "p": ["show", "ip", "interface", "brief"], "h": _show_ip_brief},
			{"m": ["priv", "config", "if", "vlan", "router", "ospf", "dhcp", "acl", "dhcpsrv", "dhcpsub", "mlag", "vxlan", "mst", "rmap", "af"], "p": ["show", "running-config"], "h": _show_run},
			{"m": EP, "p": ["show", "running-config", "interfaces"], "h": _show_run_interfaces},
			{"m": EP, "p": ["show", "running-config", "section"], "h": _show_run_section},
			{"m": EP, "p": ["show", "running-config", "diffs"], "h": func(_r): return _show_diff([])},
			{"m": ["config"], "p": ["hostname"], "h": func(r): return _hostname(r)},
			{"m": ["config"], "p": ["logging", "host"], "h": _cfg_logging},
			{"m": ["config"], "p": ["no", "logging", "host"], "h": _no_logging},
			{"m": ["config"], "p": ["ntp", "server"], "h": _cfg_ntp},
			{"m": EP, "p": ["show", "logging"], "h": _show_logging},
			{"m": EP, "p": ["show", "tech-support"], "h": _show_tech_support},
			{"m": EP, "p": ["show", "interfaces", "status"], "h": _show_if_status},
			{"m": EP, "p": ["show", "interfaces", "transceiver"], "h": _show_transceiver},
			{"m": EP, "p": ["show", "clock"], "h": _show_clock},
			{"m": ["config", "if", "vlan"], "p": ["vlan"], "h": _cfg_vlan, "dyn": _vlan_ids},
			{"m": ["config"], "p": ["no", "vlan"], "h": _cfg_no_vlan, "dyn": _vlan_ids},
			{"m": ["config", "if", "vlan", "router", "ospf", "dhcp", "acl", "dhcpsrv", "dhcpsub", "mlag", "vxlan", "mst", "rmap", "af"], "p": ["interface"], "h": _cfg_interface, "dyn": _if_names},
			{"m": ["config", "if", "vlan", "router", "ospf", "dhcp", "acl", "dhcpsrv", "dhcpsub", "mlag", "vxlan", "mst", "rmap", "af"], "p": ["interface", "range"], "h": _cfg_if_range},
			{"m": ["config"], "p": ["ip", "route"], "h": _cfg_ip_route},
			{"m": ["config"], "p": ["nat64", "prefix"], "h": _cfg_nat64},
			{"m": ["config"], "p": ["vxlan", "source"], "h": _cfg_vxlan_source},
			{"m": ["config"], "p": ["vxlan", "vlan"], "h": _cfg_vxlan_vlan},
			{"m": ["config"], "p": ["vxlan", "peer"], "h": _cfg_vxlan_peer},
			{"m": ["config"], "p": ["vxlan", "evpn"], "h": _cfg_vxlan_evpn},
			{"m": ["config"], "p": ["no", "vxlan"], "h": func(_r):
				dev.vtep = {}
				dev.remote_macs = {}
				Game.topology_changed.emit()
				return ""},
			{"m": EP, "p": ["show", "vxlan"], "h": _show_vxlan},
			{"m": ["config"], "p": ["no", "nat64"], "h": func(_r):
				dev.services.erase("nat64")
				dev.nat64_flows.clear()
				Game.topology_changed.emit()
				return ""},
			{"m": EP, "p": ["show", "nat64"], "h": _show_nat64},
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
			{"m": ["config"], "p": ["ip", "access-list"], "h": _cfg_ip_acl},
			{"m": ["config"], "p": ["no", "ip", "access-list"], "h": _cfg_no_ip_acl},
			{"m": ["acl"], "p": ["permit"], "h": func(r): return _cfg_acl(r, "permit", ctx_acl)},
			{"m": ["acl"], "p": ["deny"], "h": func(r): return _cfg_acl(r, "deny", ctx_acl)},
			{"m": ["if"], "p": ["ip", "access-group"], "h": _if_access_group},
			{"m": ["if"], "p": ["no", "ip", "access-group"], "h": func(_r): return _each(func(i):
				var groups: Dictionary = dev.services.get("acl_groups", {})
				groups.erase(i.name)
				dev.services["acl_groups"] = groups
				return "")},
			{"m": ["if"], "p": ["ip", "nat", "source"], "h": _if_nat_source},
			{"m": ["if"], "p": ["no", "ip", "nat", "source"], "h": func(_r): return _if_no_nat_source()},
			{"m": EP, "p": ["show", "ip", "nat", "translation"], "h": _show_nat_eos},
			{"m": ["config"], "p": ["dhcp", "server"], "h": _cfg_dhcp_server},
			{"m": ["config"], "p": ["no", "dhcp", "server"], "h": func(_r):
				dev.services.erase("dhcp")
				Game.topology_changed.emit()
				return ""},
			{"m": ["dhcpsrv"], "p": ["subnet"], "h": _dhcp_subnet},
			{"m": ["dhcpsrv"], "p": ["lease", "time"], "h": func(_r): return ""},
			{"m": ["dhcpsrv"], "p": ["dns", "server", "ipv4"], "h": func(r): return _dhcp_opt("dns", r)},
			{"m": ["dhcpsub"], "p": ["range"], "h": _dhcp_range},
			{"m": ["dhcpsub"], "p": ["default-gateway"], "h": func(r): return _dhcp_opt("gw", r)},
			{"m": ["dhcpsub"], "p": ["name-server"], "h": func(r): return _dhcp_opt("dns", r)},
			{"m": ["dhcpsub"], "p": ["lease", "time"], "h": func(_r): return ""},
			{"m": ["if"], "p": ["dhcp", "server", "ipv4"], "h": _if_dhcp_server},
			{"m": EP, "p": ["show", "dhcp", "server"], "h": _show_dhcp_server},
			{"m": EP, "p": ["show", "dhcp", "server", "leases"], "h": _show_dhcp_leases},
			{"m": ["config"], "p": ["vrf", "instance"], "h": _cfg_vrf},
			{"m": ["config"], "p": ["no", "vrf", "instance"], "h": func(r):
				if r.size() == 1 and String(r[0]) in dev.vrfs:
					dev.vrfs.erase(String(r[0]))
					for i: Net.Iface in dev.ifaces:
						if i.vrf == String(r[0]):
							Game.set_iface_vrf(i, "")
					Game.topology_changed.emit()
					return ""
				return "% Invalid input\n"},
			{"m": ["if"], "p": ["vrf"], "h": _if_vrf},
			{"m": ["if"], "p": ["no", "vrf"], "h": func(_r): return _if_vrf([""])},
			{"m": EP, "p": ["show", "vrf"], "h": _show_vrf},
			{"m": ["config"], "p": ["acl", "permit"], "h": func(r): return _cfg_acl(r, "permit", "")},
			{"m": ["config"], "p": ["acl", "deny"], "h": func(r): return _cfg_acl(r, "deny", "")},
			{"m": ["config"], "p": ["no", "acl"], "h": _cfg_no_acl},
			{"m": ["config"], "p": ["no", "ip", "route"], "h": _cfg_no_ip_route},
			{"m": ["config"], "p": ["router", "bgp"], "h": _cfg_router_bgp},
			{"m": ["config"], "p": ["router", "ospf"], "h": _cfg_router_ospf},
			{"m": ["config"], "p": ["ip", "dhcp", "pool"], "h": _cfg_dhcp_pool},
			{"m": ["config"], "p": ["ip", "proxy-arp"], "h": func(_r):
				dev.services.erase("proxy_arp")  # on, the IOS default
				return ""},
			{"m": ["config"], "p": ["no", "ip", "proxy-arp"], "h": func(_r):
				dev.services["proxy_arp"] = false
				return ""},
			{"m": ["config"], "p": ["no", "ip", "dhcp", "pool"], "h": func(_r):
				dev.services.erase("dhcp")
				Game.topology_changed.emit()
				return ""},
			{"m": ["config"], "p": ["ip", "dhcp", "excluded-address"], "h": _cfg_dhcp_excluded},
			{"m": ["dhcp"], "p": ["network"], "h": _dhcp_network},
			{"m": ["dhcp"], "p": ["default-router"], "h": func(r): return _dhcp_opt("gw", r)},
			{"m": ["dhcp"], "p": ["dns-server"], "h": func(r): return _dhcp_opt("dns", r)},
			{"m": EP, "p": ["show", "ip", "dhcp", "binding"], "h": _show_dhcp_binding},
			{"m": EP, "p": ["show", "ip", "dhcp", "pool"], "h": _show_dhcp_pool},
			{"m": EP, "p": ["show", "ip", "dhcp", "conflict"], "h": _show_dhcp_conflict},
			{"m": ["ospf"], "p": ["network"], "h": _ospf_network},
			{"m": ["ospf"], "p": ["router-id"], "h": _ospf_router_id},
			{"m": ["ospf"], "p": ["passive-interface"], "h": func(r): return _ospf_passive(r, true)},
			{"m": ["ospf"], "p": ["no", "passive-interface"], "h": func(r): return _ospf_passive(r, false)},
			{"m": ["ospf"], "p": ["auto-cost", "reference-bandwidth"], "h": _ospf_ref_bw},
			{"m": ["ospf"], "p": ["no", "network"], "h": _ospf_no_network},
			{"m": ["router"], "p": ["neighbor"], "h": _bgp_neighbor},
			{"m": ["router"], "p": ["no", "neighbor"], "h": _bgp_no_neighbor},
			{"m": ["router"], "p": ["roa"], "h": _bgp_roa, "hidden": true},
			{"m": ["router"], "p": ["network"], "h": _bgp_network},
			{"m": ["router"], "p": ["router-id"], "h": func(r):
				if r.size() != 1 or not String(r[0]).is_valid_ip_address():
					return "% Incomplete command\n" if r.is_empty() else "% Invalid input\n"
				dev.bgp["router_id"] = String(r[0])
				return ""},
			{"m": ["router"], "p": ["maximum-paths"], "h": func(r): return "" if r.size() >= 1 and String(r[0]).is_valid_int() else "% Incomplete command\n"},
			{"m": ["router"], "p": ["bgp", "log-neighbor-changes"], "h": func(_r): return ""},
			{"m": ["router"], "p": ["no", "bgp", "default", "ipv4-unicast"], "h": func(_r): return ""},
			{"m": ["router"], "p": ["no", "network"], "h": _bgp_no_network},
			{"m": ["vlan"], "p": ["name"], "h": func(r): return _vlan_name(r)},
			{"m": ["if"], "p": ["switchport", "mode"], "h": _sw_mode, "dyn": func(): return ["access", "trunk"]},
			{"m": ["if"], "p": ["no", "switchport"], "h": _no_switchport},
			{"m": ["if"], "p": ["switchport"], "h": _switchport_back},
			{"m": ["if"], "p": ["switchport", "access", "vlan"], "h": _sw_access_vlan, "dyn": _vlan_ids},
			{"m": ["if"], "p": ["switchport", "trunk", "allowed", "vlan"], "h": _sw_trunk_vlans},
			{"m": ["if"], "p": ["switchport", "trunk", "native", "vlan"], "h": _sw_trunk_native},
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
			{"m": ["config"], "p": ["mlag", "configuration"], "h": func(_r):
				if dev.type != "switch":
					return "% Invalid input\n"
				mode = "mlag"
				return ""},
			{"m": ["mlag"], "p": ["domain-id"], "h": func(r): return _mlag_set("domain", r)},
			{"m": ["mlag"], "p": ["local-interface"], "h": func(r): return _mlag_set("local_if", r)},
			{"m": ["mlag"], "p": ["peer-address"], "h": _mlag_peer_address},
			{"m": ["mlag"], "p": ["peer-link"], "h": _mlag_peer_link_cfg},
			{"m": ["mlag"], "p": ["reload-delay"], "h": func(_r): return ""},
			{"m": ["mlag"], "p": ["heartbeat-interval"], "h": func(_r): return ""},
			{"m": EP, "p": ["show", "mlag", "interfaces"], "h": _show_mlag_interfaces},
			{"m": ["vxlan"], "p": ["vxlan", "source-interface"], "h": _vxlan_source_if},
			{"m": ["vxlan"], "p": ["vxlan", "vlan"], "h": _cfg_vxlan_vlan},
			{"m": ["vxlan"], "p": ["vxlan", "flood", "vtep"], "h": _vxlan_flood},
			{"m": ["vxlan"], "p": ["no", "vxlan", "flood", "vtep"], "h": _vxlan_no_flood},
			{"m": ["vxlan"], "p": ["vxlan", "udp-port"], "h": func(_r): return ""},
			{"m": ["vxlan"], "p": ["vxlan", "evpn"], "h": _cfg_vxlan_evpn},
			{"m": EP, "p": ["show", "vxlan", "vtep"], "h": _show_vxlan_vtep},
			{"m": EP, "p": ["show", "vxlan", "vni"], "h": _show_vxlan_vni},
			{"m": EP, "p": ["show", "vxlan", "address-table"], "h": _show_vxlan_addr},
			{"m": ["config"], "p": ["ip", "prefix-list"], "h": _cfg_prefix_list},
			{"m": ["config"], "p": ["no", "ip", "prefix-list"], "h": func(r):
				var lists: Dictionary = dev.services.get("prefix_lists", {})
				if r.size() >= 1:
					lists.erase(String(r[0]))
				return ""},
			{"m": EP, "p": ["show", "ip", "prefix-list"], "h": _show_prefix_lists},
			{"m": EP, "p": ["show", "ip", "bgp", "neighbors"], "h": _show_bgp_neighbors},
			{"m": ["priv"], "p": ["configure", "checkpoint", "save"], "h": _checkpoint_save},
			{"m": ["priv"], "p": ["configure", "checkpoint", "restore"], "h": _checkpoint_restore},
			{"m": EP, "p": ["show", "configuration", "checkpoints"], "h": _show_checkpoints},
			{"m": ["config"], "p": ["dot1x", "system-auth-control"], "h": func(_r): return ""},
			{"m": ["if"], "p": ["dot1x", "pae", "authenticator"], "h": func(_r): return _dot1x(true)},
			{"m": ["if"], "p": ["dot1x", "port-control"], "h": func(r): return _dot1x(r.is_empty() or String(r[0]) != "force-authorized")},
			{"m": ["if"], "p": ["no", "dot1x", "pae"], "h": func(_r): return _dot1x(false)},
			{"m": ["if"], "p": ["no", "dot1x", "port-control"], "h": func(_r): return _dot1x(false)},
			{"m": ["config"], "p": ["aaa", "authentication", "login", "default"], "h": _aaa_login_default},
			{"m": ["if"], "p": ["storm-control", "broadcast", "level"], "h": _storm_level},
			{"m": ["if"], "p": ["ip", "proxy-arp"], "h": func(_r): return _if_proxy_arp(true)},
			{"m": ["if"], "p": ["no", "ip", "proxy-arp"], "h": func(_r): return _if_proxy_arp(false)},
			{"m": ["config"], "p": ["ip", "arp", "inspection", "vlan"], "h": func(_r): return _dai(true)},
			{"m": ["config"], "p": ["no", "ip", "arp", "inspection", "vlan"], "h": func(_r): return _dai(false)},
			{"m": ["if"], "p": ["ipv6", "nd", "ra", "disabled"], "h": func(_r): return _ra(false)},
			{"m": ["if"], "p": ["no", "ipv6", "nd", "ra", "disabled"], "h": func(_r): return _ra(true)},
			{"m": EP, "p": ["show", "inventory"], "h": _show_inventory},
			{"m": EP, "p": ["show", "environment"], "h": _show_environment},
			{"m": EP, "p": ["show", "environment", "temperature"], "h": _show_environment},
			{"m": EP, "p": ["show", "environment", "power"], "h": _show_environment},
			{"m": EP, "p": ["show", "users"], "h": func(_r): return "    Line     User     Roles       TTY   State  Session  Idle  Location\n*   1        admin    network-admin  vty1  E      00:%02d:%02d  00:00  10.0.0.9\n" % [(Game.cycle * 3) % 60, (Game.cycle * 7) % 60]},
			{"m": EP, "p": ["show", "ntp", "status"], "h": func(_r): return ("synchronised to NTP server (%s) at stratum 3\n   time correct to within 12 ms\n   polling server every 64 s\n" % dev.ntp_server) if dev.ntp_server != "" else "unsynchronised\n  time server re-starting\n   polling server every 8 s\n"},
			{"m": EP, "p": ["show", "ntp", "associations"], "h": func(_r): return "     remote           refid      st t when poll reach   delay   offset  jitter\n==============================================================================\n" + (("*%-16s 10.0.0.1         2 u   12   64  377    0.312    0.045   0.021\n" % dev.ntp_server) if dev.ntp_server != "" else "")},
			{"m": EP, "p": ["show", "hosts"], "h": func(_r): return "Default domain is not set\nName/address lookup uses domain service\nName servers are: %s\n\nStatic hostname to address mappings:\n" % (dev.resolver if dev.resolver != "" else "not set")},
			{"m": ["config"], "p": ["ip", "name-server"], "h": func(r):
				var ips: Array = r.filter(func(w): return String(w).is_valid_ip_address())
				if ips.is_empty():
					return "% Incomplete command\n" if r.is_empty() else "% Invalid input\n"
				dev.resolver = String(ips[0])
				Game.topology_changed.emit()
				return ""},
			{"m": ["config"], "p": ["username"], "h": _cfg_username},
			{"m": ["config"], "p": ["clock", "timezone"], "h": func(r):
				if r.is_empty():
					return "% Incomplete command\n"
				dev.services["timezone"] = String(r[0])
				return ""},
			{"m": ["config"], "p": ["ip", "domain-name"], "h": func(r):
				if r.is_empty():
					return "% Incomplete command\n"
				dev.services["domain"] = String(r[0])
				return ""},
			{"m": ["config"], "p": ["dns", "domain"], "h": func(r):
				if r.is_empty():
					return "% Incomplete command\n"
				dev.services["domain"] = String(r[0])
				return ""},
			{"m": ["config"], "p": ["errdisable", "recovery"], "h": func(r): return "" if not r.is_empty() else "% Incomplete command\n"},
			{"m": ["config"], "p": ["management", "ssh"], "h": func(_r): return ""},
			{"m": ["config"], "p": ["management", "api", "http-commands"], "h": func(_r): return ""},
			{"m": ["config"], "p": ["enable", "secret"], "h": func(r): return "" if not r.is_empty() else "% Incomplete command\n"},
			{"m": ["config"], "p": ["enable", "password"], "h": func(r): return "" if not r.is_empty() else "% Incomplete command\n"},
			{"m": ["config"], "p": ["banner", "motd"], "h": func(r):
				dev.services["motd"] = " ".join(PackedStringArray(r))
				return ""},
			{"m": ["config"], "p": ["lldp", "run"], "h": func(_r): dev.services.erase("lldp_off"); return ""},
			{"m": ["config"], "p": ["no", "lldp", "run"], "h": func(_r): dev.services["lldp_off"] = true; return ""},
			{"m": EP, "p": ["show", "lldp", "neighbors", "detail"], "h": _show_lldp_detail},
			{"m": EP, "p": ["show", "ip", "helper-address"], "h": func(_r):
				var out := "Interface      Helper-Address\n-------------- --------------\n"
				for i: Net.Iface in dev.ifaces:
					if i.helper != "":
						out += "%-14s %s\n" % [i.name, i.helper]
				return out},
			{"m": EP, "p": ["show", "boot-config"], "h": func(_r): return "Software image: flash:/EOS-4.28.3M.swi\nConsole speed: (not set)\nAboot password (encrypted): (not set)\nMemory test iterations: (not set)\n"},
			{"m": EP, "p": ["terminal", "length"], "h": func(_r): return ""},
			{"m": EP, "p": ["show", "ip", "route", "vrf"], "h": _show_ip_route_vrf},
			{"m": ["config"], "p": ["mlag", "peer"], "h": func(r): return _mlag_peer(r[0] if r.size() > 0 else "")},
			{"m": ["config"], "p": ["no", "mlag"], "h": func(_r): return _mlag_peer("")},
			{"m": ["if"], "p": ["mlag", "peer-link"], "h": func(_r): return _mlag_if(-1)},
			{"m": ["if"], "p": ["mlag"], "h": func(r): return _mlag_if(int(r[0]) if r.size() > 0 else 0)},
			{"m": ["if"], "p": ["no", "mlag"], "h": func(_r): return _mlag_if(0)},
			{"m": EP, "p": ["show", "mlag"], "h": _show_mlag},
			{"m": ["config"], "p": ["snmp-server", "community"],
				"h": func(r):
					if r.size() > 1 and String(r[1]) in ["ro", "rw"]:
						dev.services["snmp_mode"] = String(r[1])
					return _snmp(r[0] if r.size() > 0 else "")},
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
			{"m": ["config"], "p": ["ip", "nat", "inside", "source"], "h": _cfg_nat_source},
			{"m": ["config"], "p": ["no", "ip", "nat", "inside", "source"], "h": _cfg_no_nat_source},
			{"m": ["config"], "p": ["access-list"], "h": _cfg_std_acl},
			{"m": ["config"], "p": ["no", "access-list"], "h": _cfg_no_std_acl},
			{"m": EP, "p": ["show", "ip", "nat", "translations"], "h": _show_nat},
			{"m": EP, "p": ["show", "ip", "nat", "statistics"], "h": _show_nat_stats},
			{"m": ["priv"], "p": ["clear", "ip", "nat", "translation"], "h": func(_r):
				dev.nat_flows.clear()
				dev.nat_xlate.clear()
				return ""},
			{"m": ["if"], "p": ["vrrp"], "h": _if_vrrp},
			{"m": ["if"], "p": ["channel-group"], "h": _if_lag},
			{"m": ["if"], "p": ["ip", "helper-address"], "h": _if_helper},
			{"m": ["if"], "p": ["no", "ip", "helper-address"], "h": func(_r): ctx_if.helper = ""; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "channel-group"], "h": func(_r): ctx_if.lag = 0; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "vrrp"], "h": _if_no_vrrp},
			{"m": ["if"], "p": ["no", "ip", "nat"], "h": func(_r): ctx_if.nat = ""; Game.topology_changed.emit(); return ""},
			{"m": ["if"], "p": ["no", "ip", "address"], "h": _if_no_ip},
			{"m": ["if"], "p": ["shutdown"], "h": func(_r): return _each(func(i):
				i.admin_down = true
				i.enabled = false
				return "")},
			{"m": ["if"], "p": ["no", "shutdown"], "h": func(_r): return _each(func(i):
				# clears an administrative shutdown and an err-disable; a cut cable stays cut
				i.admin_down = false
				i.err_disabled = false
				i.enabled = i.fault == ""
				return "")},
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
			{"m": ["config", "if", "vlan", "router", "ospf", "dhcp", "acl", "dhcpsrv", "dhcpsub", "mlag", "vxlan", "mst", "rmap", "af"], "p": ["end"], "h": func(_r): mode = "priv"; return ""},
			{"m": EP, "p": ["exit"], "h": _exit},
			{"m": EP, "p": ["help"], "h": _help},
		]

	func exec(line: String) -> String:
		# output filtering, the way every real console has it
		var filter := ""
		var pipe := line.find("|")
		if pipe > 0:
			var tail := line.substr(pipe + 1).strip_edges()
			var parts := tail.split(" ", false)
			if parts.size() >= 2 and String(parts[0]) in ["include", "i", "grep"]:
				filter = " ".join(PackedStringArray(Array(parts).slice(1)))
				line = line.substr(0, pipe).strip_edges()
		var toks := Array(line.strip_edges().split(" ", false))
		if toks.is_empty():
			return ""
		if filter != "":
			return CLI.filter_output(exec(line), filter)
		if toks.size() > 1 and String(toks[0]) == "do" and mode not in ["exec", "priv"]:
			toks.pop_front()  # IOS needs 'do' for a show inside config; EOS tolerates it
			line = " ".join(PackedStringArray(toks))
		Sim.aaa_account(dev, line.strip_edges())  # the audit trail, before anything runs
		if mode in ["config", "if", "vlan", "router", "ospf", "dhcp", "acl", "dhcpsrv", "dhcpsub", "mlag", "vxlan", "mst", "rmap", "af"]:
			Challenge.note_change()  # a challenge counts what you changed, not what you typed
		if mode == "acl" and toks.size() >= 2 and String(toks[0]).is_valid_int():
			_acl_seq = int(toks[0])  # 10 permit ip any any: the sequence number leads
			toks.pop_front()
		elif mode == "acl" and toks.size() == 2 and String(toks[0]) == "no" and String(toks[1]).is_valid_int():
			return _acl_remove_seq(int(toks[1]))
		else:
			_acl_seq = 0
		# resolve with per-token prefix matching (Cisco-style abbreviation).
		# A global configuration command typed inside a sub-mode (interface,
		# router) is accepted and switches mode, exactly as IOS does.
		var modes: Array = [mode]
		if mode in ["if", "vlan", "router", "ospf", "dhcp", "acl", "dhcpsrv", "dhcpsub", "mlag", "vxlan", "mst", "rmap", "af"]:
			modes.append("config")
		if mode == "af":
			modes.append("router")  # the address family inherits the BGP commands
		if mode != "exec":
			modes.append("priv")  # EOS runs exec-level commands from any configuration mode
		var full: Array = []
		for c in _cmds:
			if toks.size() < c["p"].size() or not modes.any(func(m): return m in c["m"]):
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
				if not modes.any(func(m): return m in c["m"]):
					continue
				var okc := true
				for k in mini(toks.size(), c["p"].size()):
					if not String(c["p"][k]).begins_with(toks[k]):
						okc = false
						break
				if okc:
					return "% Incomplete command\n"
			if mode == "exec":
				for c in _cmds:
					if not ("priv" in c["m"] or "config" in c["m"]) or toks.size() < c["p"].size():
						continue
					var okp := true
					for k in c["p"].size():
						if not String(c["p"][k]).begins_with(toks[k]):
							okp = false
							break
					if okp:
						return "% Invalid input (privileged mode required)\n"
			return "% Invalid input\n"
		# the sub-mode's own commands win over a global one that happens to
		# start the same way ("ip address" on an interface, not "ip access-list")
		var own: Array = full.filter(func(c): return mode in c["m"])
		if not own.is_empty():
			full = own
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
		var result: String = cmd["h"].call(toks.slice(cmd["p"].size()))
		if dev.services.has("mlag") and dev.mlag_peer == "":
			_mlag_resolve()  # the peer may only now have its address
		return result

	func complete(line: String) -> Array:
		var ends_space := line.ends_with(" ")
		var toks := Array(line.strip_edges().split(" ", false))
		var cur: String = "" if ends_space or toks.is_empty() else toks.pop_back()
		var cands := {}
		for c in _cmds:
			if mode not in c["m"] or bool(c.get("hidden", false)):
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
			"if", "vlan", "router", "ospf", "dhcp", "acl", "dhcpsrv", "mlag", "vxlan", "mst", "rmap":
				mode = "config"
			"af":
				mode = "router"
			"dhcpsub":
				mode = "dhcpsrv"
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
			return "% Incomplete command\n"
		return "" if Game.rename_device(dev, r[0]) else "% invalid or duplicate name\n"

	func _ping(r: Array) -> String:
		## EOS runs Linux ping: five 72-byte probes 0.2 s apart. Accepts
		## ping [vrf NAME] X [repeat N] [size N] [source Y]
		var size := 72
		var repeat := 5
		var target := ""
		var idx := 0
		while idx < r.size():
			match String(r[idx]):
				"vrf", "source":
					idx += 2
					continue
				"size":
					if idx + 1 >= r.size() or not String(r[idx + 1]).is_valid_int():
						return "% Incomplete command\n"
					size = int(String(r[idx + 1]))
					idx += 2
					continue
				"repeat":
					if idx + 1 >= r.size() or not String(r[idx + 1]).is_valid_int():
						return "% Incomplete command\n"
					repeat = clampi(int(String(r[idx + 1])), 1, 20)
					idx += 2
					continue
				_:
					if target != "":
						return "% Invalid input\n"
					target = String(r[idx])
			idx += 1
		if target == "":
			return "% Incomplete command\n"
		return CLI.fmt_ping_eos(dev, target, repeat, size)

	func _traceroute(r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		return CLI.fmt_traceroute(dev, r[0])

	func _ssh(r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
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
		## vlan 10 | vlan 10-20 | vlan 10,20,30-32: all of them, and name applies to all
		if dev.type != "switch":
			return "% Invalid input\n"
		if r.size() != 1:
			return "% Incomplete command\n" if r.is_empty() else "% Invalid input\n"
		var vids := EOS.parse_vlan_list(String(r[0]))
		if vids.is_empty():
			return "% Invalid input\n"
		for vid in vids:
			if not dev.vlans.has(vid):
				Game.add_vlan(dev, vid, "")
		ctx_vlan = int(vids[0])
		ctx_vlans = vids
		ctx_vlan_spec = String(r[0])
		mode = "vlan"
		return ""

	func _cfg_no_vlan(r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		var vids := EOS.parse_vlan_list(String(r[0]))
		if vids.is_empty():
			return "% Invalid input\n"
		for vid in vids:
			if not Game.remove_vlan(dev, int(vid)):
				return "% Invalid input\n"
		return ""

	func _vlan_name(r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		for vid in ctx_vlans:
			if dev.vlans.has(int(vid)):
				dev.vlans[int(vid)] = r[0]
		Game.topology_changed.emit()
		return ""

	func _select_ifaces(list: Array) -> void:
		ctx_ifs = list
		ctx_if = list[0] if not list.is_empty() else null
		ctx_po = 0
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
			return "% Incomplete command\n"
		var picked: Array = []
		var last_pfx := "ethernet"  # Ethernet1,3,5-6: a bare number keeps the last prefix
		for part in String(r[0]).split(",", false):
			var bits := String(part).split("-")
			var head := String(bits[0])
			if head.rstrip("0123456789") == "":
				head = last_pfx + head
			else:
				last_pfx = head.rstrip("0123456789")
			if bits.size() == 2:
				var pfx := head.rstrip("0123456789")
				var lo := int(head.substr(pfx.length()))
				var hi := int(bits[1])
				for n in range(lo, hi + 1):
					var found := _find_iface("%s%d" % [pfx, n])
					if found:
						picked.append(found)
			else:
				var one := _find_iface(head)
				if one:
					picked.append(one)
		if picked.is_empty():
			return "% Invalid input\n"
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
		if r.size() == 2 and String(r[1]).is_valid_int():
			r = [String(r[0]) + String(r[1])]  # interface ethernet 1
		if r.size() != 1:
			return "% Incomplete command\n"
		var want := String(r[0]).to_lower()
		if ("-" in want or "," in want) and not want.begins_with("po"):
			return _cfg_if_range([want])  # Ethernet1-3, Ethernet1,3,5-6: no 'range' keyword on EOS
		if (want.begins_with("po") or want.begins_with("port-channel")) and want.lstrip("abcdefghijklmnopqrstuvwxyz-").is_valid_int():
			# a Port-Channel is its members: what is typed here lands on all of them
			if dev.type != "switch":
				return "% Invalid input\n"
			var group := int(want.lstrip("abcdefghijklmnopqrstuvwxyz-"))
			var members: Array = dev.ifaces.filter(func(i): return i.lag == group)
			_select_ifaces(members)  # empty until channel-group N names a member: EOS lets you configure it first
			ctx_po = group
			return ""
		if want.begins_with("vx") and want.lstrip("abcdefghijklmnopqrstuvwxyz") == "1":
			if dev.type != "switch":
				return "% Invalid input\n"
			_vtep()
			mode = "vxlan"
			return ""
		if want.begins_with("lo") and want.lstrip("abcdefghijklmnopqrstuvwxyz").is_valid_int() and not want.begins_with("lo."):
			if not dev.ip_forwarding and not Game.is_l3_switch(dev):
				return "% Invalid input\n"
			if Game.is_l3_switch(dev):
				dev.ip_forwarding = true  # a loopback is an L3 thing: the switch routes from here on
			var lo_name := "Loopback%d" % int(want.lstrip("abcdefghijklmnopqrstuvwxyz"))
			for i: Net.Iface in dev.ifaces:
				if i.name == lo_name:
					_select_ifaces([i])
					return ""
			var lo := Net.Iface.new(dev, lo_name, Game._new_mac())
			lo.mode = "routed"
			dev.ifaces.append(lo)
			Game.topology_changed.emit()
			_select_ifaces([lo])
			return ""
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
		return "% Invalid input\n"

	func _if_description(r: Array) -> String:
		if r.is_empty():
			return "% Incomplete command\n"
		var text := " ".join(PackedStringArray(r))
		return _each(func(i: Net.Iface) -> String:
			Game.set_note(i, text)
			return "")

	func _show_if_description(_r: Array) -> String:
		var out := "%-30s %-14s %-18s %s\n" % ["Interface", "Status", "Protocol", "Description"]
		for i: Net.Iface in dev.ifaces:
			if i.name == "lo":
				continue
			var up := i.enabled and Game.link_at(i) != null
			out += "%-30s %-14s %-18s %s\n" % [_short(i.name), "admin down" if i.admin_down else ("up" if up else "down"),
				"up" if up else "down", String(i.note.get("text", "")) if i.note is Dictionary else ""]
		return out

	# ---- MLAG the EOS way ----
	func _mlag_cfg() -> Dictionary:
		if not dev.services.has("mlag"):
			dev.services["mlag"] = {"domain": "", "local_if": "", "peer_addr": "", "peer_link": ""}
		return dev.services["mlag"]

	func _mlag_set(key: String, r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		_mlag_cfg()[key] = String(r[0])
		return ""

	func _mlag_peer_address(r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_ip_address():
			return "% Incomplete command\n" if r.is_empty() else "% Invalid input\n"
		_mlag_cfg()["peer_addr"] = String(r[0])
		_mlag_resolve()
		return ""

	func _mlag_resolve() -> void:
		## the peer is whoever answers at peer-address; it may not exist yet
		var addr := String(dev.services.get("mlag", {}).get("peer_addr", ""))
		if addr == "" or dev.mlag_peer != "":
			return
		var owner := Sim._ip_owner(addr)
		if owner != null and owner != dev and owner.type == "switch":
			_mlag_peer(owner.name)

	func _mlag_peer_link_cfg(r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		var want := String(r[0])
		_mlag_cfg()["peer_link"] = want
		var any := false
		for i: Net.Iface in dev.ifaces:
			var is_it := false
			if want.begins_with("Port-Channel") or want.begins_with("Po"):
				is_it = i.lag == int(want.lstrip("Port-Chanel"))
			else:
				is_it = _find_iface(want) == i
			if is_it:
				any = true
				i.mlag_peerlink = true
		if not any:
			return "% Invalid input\n"
		Game.topology_changed.emit()
		return ""

	func _show_mlag_interfaces(_r: Array) -> String:
		var peer := Sim.mlag_peer_of(dev)
		var out := "                                                                 local/remote\n   mlag       desc          state       local       remote          status\n---------- ---------- ----------------- ----------- ------------ ------------\n"
		for i: Net.Iface in dev.ifaces:
			if i.mlag <= 0:
				continue
			var far := Sim.mlag_port(peer, i.mlag) if peer != null else null
			var l_up := Game.link_at(i) != null and i.enabled
			var r_up := far != null and Game.link_at(far) != null and far.enabled
			out += "%10d %10s %17s %11s %12s %12s\n" % [i.mlag, "", "active-full" if l_up and r_up else ("active-partial" if l_up or r_up else "inactive"),
				EOS._short(i.name), EOS._short(far.name) if far != null else "-", "%s/%s" % ["up" if l_up else "down", "up" if r_up else "down"]]
		return out

	# ---- VXLAN under interface Vxlan1 ----
	func _vxlan_source_if(r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		var src := _find_iface(String(r[0]))
		if src == null:
			return "% Invalid input\n"
		_vtep()["src_if"] = src.name
		_vtep()["src"] = String(src.ips[0]).split("/")[0] if not src.ips.is_empty() else ""
		Game.topology_changed.emit()
		return ""

	func _vxlan_flood(r: Array) -> String:
		if r.is_empty():
			return "% Incomplete command\n"
		var peers: Array = _vtep()["peers"]
		for a in r:
			if not String(a).is_valid_ip_address():
				return "% Invalid input\n"
			if String(a) not in peers:
				peers.append(String(a))
		Game.topology_changed.emit()
		return ""

	func _vxlan_no_flood(r: Array) -> String:
		var peers: Array = _vtep()["peers"]
		if r.is_empty():
			peers.clear()
		for a in r:
			peers.erase(String(a))
		Game.topology_changed.emit()
		return ""

	func _show_vxlan_vtep(_r: Array) -> String:
		var peers: Array = dev.vtep.get("peers", [])
		var out := "Remote VTEPS for Vxlan1:\n\nVTEP           Tunnel Type(s)\n-------------- --------------\n"
		for pe in peers:
			out += "%-14s %s\n" % [pe, "unicast, flood"]
		return out + "\nTotal number of remote VTEPS:  %d\n" % peers.size()

	func _show_vxlan_vni(_r: Array) -> String:
		var out := "VNI to VLAN Mapping for Vxlan1\nVNI         VLAN       Source       Interface       802.1Q Tag\n----------- ---------- ------------ --------------- ----------\n"
		var map: Dictionary = dev.vtep.get("map", {})
		for v in map:
			out += "%-11d %-10d %-12s %-15s %d\n" % [int(map[v]), int(v), "static", "Vxlan1", int(v)]
		return out

	func _show_vxlan_addr(_r: Array) -> String:
		var out := "          Vxlan Mac Address Table\n----------------------------------------------------------------------\n\nVLAN  Mac Address     Type     Prt  VTEP             Moves   Last Move\n----  -----------     ----     ---  ----             -----   ---------\n"
		for v2: int in dev.remote_macs:
			for mac: String in dev.remote_macs[v2]:
				out += "%4d  %-15s EVPN     Vx1  %-16s 1       0:00:%02d ago\n" % [v2, Net.mac_dotted(mac), dev.remote_macs[v2][mac], (Game.cycle * 3) % 60]
		return out + "Total Remote Mac Addresses for this criterion: %d\n" % dev.remote_macs.values().reduce(func(a, m): return a + m.size(), 0)

	# ---- BGP policy objects and views ----
	func _cfg_prefix_list(r: Array) -> String:
		## ip prefix-list NAME [seq N] permit|deny P/len [ge N] [le N]
		if r.size() < 3:
			return "% Incomplete command\n"
		var name := String(r[0])
		var k := 1
		if String(r[k]) == "seq":
			k += 2
		if k + 1 >= r.size() or String(r[k]) not in ["permit", "deny"] or not Net.valid_cidr(String(r[k + 1])):
			return "% Invalid input\n"
		var lists: Dictionary = dev.services.get("prefix_lists", {})
		if not lists.has(name):
			lists[name] = []
		if String(r[k]) == "permit" and String(r[k + 1]) not in lists[name]:
			lists[name].append(String(r[k + 1]))
		dev.services["prefix_lists"] = lists
		return ""

	func _show_prefix_lists(_r: Array) -> String:
		var out := ""
		var lists: Dictionary = dev.services.get("prefix_lists", {})
		for name in lists:
			out += "ip prefix-list %s:\n" % name
			var seq := 10
			for pfx in lists[name]:
				out += "   seq %d permit %s\n" % [seq, pfx]
				seq += 10
		return out

	func _show_bgp_neighbors(_r: Array) -> String:
		if dev.bgp.is_empty():
			return ""
		var out := ""
		for nb in dev.bgp["neighbors"]:
			var up := Sim.bgp_established(dev, nb)
			out += "BGP neighbor is %s, remote AS %d, external link\n  BGP version 4, remote router ID %s, VRF default\n  BGP state is %s%s\n  Last state was %s\n" % [
				nb["ip"], int(nb["remote_as"]), nb["ip"] if up else "0.0.0.0", "Established" if up else "Active",
				(", up for 00:%02d:%02d" % [(Game.cycle * 3) % 60, (Game.cycle * 7) % 60]) if up else "", "OpenConfirm" if up else "Connect"]
			if not nb.get("prefix_in", []).is_empty():
				out += "  Inbound prefix list: %s\n" % ", ".join(PackedStringArray(nb["prefix_in"]))
			if not nb.get("prefix_out", []).is_empty():
				out += "  Outbound prefix list: %s\n" % ", ".join(PackedStringArray(nb["prefix_out"]))
			if int(nb.get("local_pref", 100)) != 100:
				out += "  Local preference applied inbound: %d\n" % int(nb["local_pref"])
			if int(nb.get("prepend", 0)) > 0:
				out += "  Outbound AS path prepend: %d\n" % int(nb["prepend"])
			if bool(nb.get("rpki", false)):
				out += "  RPKI origin validation: enabled\n"
			out += "  Hold time is 180, keepalive interval is 60 seconds\n\n"
		return out

	func _checkpoint_save(r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		Game.save_config_version(dev)
		dev.versions[dev.versions.size() - 1]["name"] = String(r[0])
		return ""

	func _checkpoint_restore(r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		for k in dev.versions.size():
			if String(dev.versions[k].get("name", "")) == String(r[0]):
				return _rollback([str(k + 1)]).replace("Rolled back to version %d." % (k + 1), "")
		return "% Invalid input\n"

	func _show_checkpoints(_r: Array) -> String:
		var out := "Maximum number of checkpoints: 20\n\n Name                         Time\n ---------------------------- ------------------------\n"
		for v in dev.versions:
			if v.has("name"):
				out += " %-28s cycle %d\n" % [v["name"], int(v["cycle"])]
		return out

	# ---- the EOS spellings of a few things IOS spells differently ----
	func _aaa_login_default(r: Array) -> String:
		## aaa authentication login default group radius [local]  |  ... default local
		if r.size() >= 1 and String(r[0]) == "local":
			dev.aaa = {}
			Game.topology_changed.emit()
			return ""
		if r.size() >= 2 and String(r[0]) == "group" and String(r[1]) in ["radius", "tacacs+"]:
			if dev.radius == "":
				return "% Invalid input\n"
			dev.aaa = {"server": dev.radius, "key": String(dev.services.get("radius_key", "")), "local": "local" in r}
			Game.topology_changed.emit()
			return ""
		return "% Invalid input\n"

	func _storm_level(r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_float():
			return "% Incomplete command\n"
		return _storm([str(int(float(r[0]) * 10.0))])  # a percentage of the port, in this world's frames

	func _if_proxy_arp(on: bool) -> String:
		if not dev.ip_forwarding:
			return "% Invalid input\n"
		var proxied: Array = dev.services.get("proxy_arp_ifaces", [])
		for i: Net.Iface in ctx_ifs:
			proxied.erase(i.name)
			if on:
				proxied.append(i.name)
		dev.services["proxy_arp_ifaces"] = proxied
		Game.topology_changed.emit()
		return ""

	func _cfg_username(r: Array) -> String:
		if r.is_empty():
			return "% Incomplete command\n"
		var users: Dictionary = dev.services.get("users", {})
		var role := ""
		var at := r.find("role")
		if at >= 0 and at + 1 < r.size():
			role = String(r[at + 1])
		users[String(r[0])] = {"privilege": 15 if "privilege" in r else 1, "role": role}
		dev.services["users"] = users
		return ""

	func _show_inventory(_r: Array) -> String:
		var label := String(Game.MODELS[dev.model]["label"])
		return "System information\n  Model                     Description\n  ------------------------- ----------------------------------------------\n  %-25s %s\n\n  HW Version  Serial Number  Mfg Date\n  ----------- -------------- ----------\n  01.02       JPE%08d    2024-03-01\n\nSystem has %d power supply slots\n  Slot Model            Serial Number\n  ---- ---------------- ---------------\n  1    PWR-460AC-F      %s\n" % [
			label, label, dev.name.hash() % 100000000, 1, "K%d" % (dev.name.hash() % 1000000)]

	func _show_environment(_r: Array) -> String:
		var watts := int(Game.MODELS[dev.model].get("watts", 100))
		return "System temperature status is: Ok\n\n  Sensor  Description            Temperature  Alert  Critical  Max Temp\n  ------- ---------------------- ------------ ------ --------- --------\n  1       Board sensor           %.1fC        %dC    %dC       %.1fC\n\nPower                              Input   Output  Output\nSupply  Model            Capacity Current Current Power   Status\n------- ---------------- -------- ------- ------- ------- --------\n1       PWR-460AC-F      460W     %.2fA   %.2fA   %dW     Ok\n" % [
			38.0 + (Game.cycle % 5), 55, 60, 45.0, watts / 230.0, watts / 12.0, watts]

	func _show_lldp_detail(_r: Array) -> String:
		var out := ""
		for i: Net.Iface in dev.ifaces:
			var peer := Game.effective_peer(i)
			if peer == null or dev.services.has("lldp_off"):
				continue
			out += "Interface %s detected 1 LLDP neighbors:\n\n  Neighbor \"%s\"/%s, age %d seconds\n  Discovered %d:%02d:%02d ago; Last changed %d:%02d:%02d ago\n  - Chassis ID type: MAC address (4)\n    Chassis ID     : %s\n  - Port ID type: Interface name (5)\n    Port ID        : \"%s\"\n  - Time To Live: 120 seconds\n  - System Name: \"%s\"\n  - System Description: \"%s\"\n\n" % [
				i.name, Net.mac_dotted(peer.dev.ifaces[0].mac), peer.name, (Game.cycle * 7) % 30, 0, (Game.cycle * 3) % 60, (Game.cycle * 17) % 60, 0, 0, (Game.cycle * 11) % 60,
				Net.mac_dotted(peer.dev.ifaces[0].mac), peer.name, peer.dev.name, String(Game.MODELS.get(peer.dev.model, {}).get("label", peer.dev.model))]
		return out

	func _show_ip_route_vrf(r: Array) -> String:
		if r.is_empty():
			return "% Incomplete command\n"
		var vrf := String(r[0])
		if vrf not in dev.vrfs:
			return "% Invalid input\n"
		var out := _show_ip_route([]).split("\n")[0].replace("VRF: default", "VRF: %s" % vrf) + "\n"
		out += ROUTE_CODES + "\nGateway of last resort is not set\n\n"
		for e in Sim.rib(dev):
			if String(e["vrf"]) != vrf:
				continue
			var pfx := "%s/%d" % [e["prefix"], int(e["plen"])]
			if e["src"] == "C":
				out += " %-8s %s is directly connected, %s\n" % [e["src"], pfx, e["iface"].name]
			else:
				out += " %-8s %s [%d/%d] via %s, %s\n" % ["B E" if e["src"] == "B" else String(e["src"]), pfx, int(e["ad"]), 0, e["next_hop"], e["iface"].name]
		return out

	func _show_run_interfaces(r: Array) -> String:
		if r.is_empty():
			return "% Incomplete command\n"
		var want := _find_iface(String(r[0]) + (String(r[1]) if r.size() > 1 and String(r[1]).is_valid_int() else ""))
		if want == null:
			return "% Invalid input\n"
		var out := ""
		var keep := false
		for line in _show_run([]).split("\n"):
			if line.begins_with("interface "):
				keep = line == "interface %s" % want.name
			elif line.begins_with("!") or not line.begins_with(" "):
				if keep:
					out += "!\n"
				keep = false
			if keep:
				out += line + "\n"
		return out

	func _show_run_section(r: Array) -> String:
		if r.is_empty():
			return "% Incomplete command\n"
		var needle := " ".join(PackedStringArray(r))
		var out := ""
		var keep := false
		for line in _show_run([]).split("\n"):
			if not line.begins_with(" ") and not line.begins_with("!"):
				keep = needle in line
			if keep and line != "":
				out += line + "\n"
		return out

	func _show_mst_config(_r: Array) -> String:
		var mc: Dictionary = dev.services.get("mst", {})
		var mapped := {}
		for inst in dev.mst_instances:
			for v in dev.mst_instances[inst]:
				mapped[int(v)] = int(inst)
		var out := "Name  [%s]\nRevision  %d   Instances configured %d\n\nInstance  Vlans mapped\n--------  ---------------------------------------------------------------------\n" % [
			String(mc.get("name", "")), int(mc.get("revision", 0)), dev.mst_instances.size() + 1]
		var rest: Array = []
		for v in range(1, 4095):
			if not mapped.has(v):
				rest.append(v)
		out += "%-9s %s\n" % ["0", Net.compress_ports(rest.map(func(v): return "v%d" % v)).replace("v", "")]
		for inst in dev.mst_instances:
			out += "%-9s %s\n" % [str(inst), ",".join(PackedStringArray(dev.mst_instances[inst].map(func(v): return str(v))))]
		return out + "-------------------------------------------------------------------------------\n"

	func _cfg_route_map(r: Array) -> String:
		## route-map NAME [permit|deny] [seq]
		if r.is_empty():
			return "% Incomplete command\n"
		ctx_rmap = String(r[0])
		var action := "permit"
		ctx_rmap_seq = 10
		if r.size() >= 2 and String(r[1]) in ["permit", "deny"]:
			action = String(r[1])
		if r.size() >= 3 and String(r[2]).is_valid_int():
			ctx_rmap_seq = int(r[2])
		var maps: Dictionary = dev.services.get("route_maps", {})
		if not maps.has(ctx_rmap):
			maps[ctx_rmap] = {}
		if not maps[ctx_rmap].has(str(ctx_rmap_seq)):
			maps[ctx_rmap][str(ctx_rmap_seq)] = {"action": action}
		dev.services["route_maps"] = maps
		mode = "rmap"
		return ""

	func _rmap_set(key: String, r: Array) -> String:
		if r.is_empty():
			return "% Incomplete command\n"
		var entry: Dictionary = dev.services["route_maps"][ctx_rmap][str(ctx_rmap_seq)]
		match key:
			"local_pref", "prepend":
				if not String(r[0]).is_valid_int():
					return "% Invalid input\n"
				entry[key] = int(r[0])
			"prefix_list":
				if not dev.services.get("prefix_lists", {}).has(String(r[0])):
					return "% Invalid input\n"
				entry[key] = String(r[0])
		return ""

	func _show_route_maps(_r: Array) -> String:
		var out := ""
		for name in dev.services.get("route_maps", {}):
			for seq in dev.services["route_maps"][name]:
				var e: Dictionary = dev.services["route_maps"][name][seq]
				out += "route-map %s %s %s\n" % [name, e.get("action", "permit"), seq]
				if e.has("prefix_list"):
					out += "  Match clauses:\n    match ip address prefix-list %s\n" % e["prefix_list"]
				out += "  Set clauses:\n"
				if e.has("local_pref"):
					out += "    set local-preference %d\n" % int(e["local_pref"])
				if e.has("prepend"):
					out += "    set as-path prepend %s\n" % " ".join(PackedStringArray(_asn_repeat(int(e["prepend"]))))
		return out

	func _asn_repeat(n: int) -> Array:
		var out: Array = []
		for k in n:
			out.append(str(int(dev.bgp.get("asn", 0))))
		return out

	func _apply_route_map(nb: Dictionary, name: String, dir: String) -> void:
		## the route-map's set and match clauses become this world's neighbour policy
		var entries: Dictionary = dev.services.get("route_maps", {}).get(name, {})
		for seq in entries:
			var e: Dictionary = entries[seq]
			if e.has("local_pref") and dir == "in":
				nb["local_pref"] = int(e["local_pref"])
			if e.has("prepend") and dir == "out":
				nb["prepend"] = clampi(int(e["prepend"]), 0, 10)
			if e.has("prefix_list"):
				nb["prefix_%s" % dir] = dev.services.get("prefix_lists", {}).get(String(e["prefix_list"]), []).duplicate()
		nb["rmap_%s" % dir] = name

	func _af_neighbor(r: Array) -> String:
		## address-family ipv4: neighbor X activate, and the same neighbor commands as outside it
		if r.size() == 2 and String(r[1]) == "activate":
			return "" if not _find_nb(String(r[0])).is_empty() else "% Invalid input\n"
		return _bgp_neighbor(r)

	func _show_port_channel_if(group: int) -> String:
		var members: Array = dev.ifaces.filter(func(i): return i.lag == group)
		if members.is_empty():
			return "% Invalid input\n"
		var up_members: Array = members.filter(func(i): return Sim.lag_bundled(i))
		var first: Net.Iface = members[0]
		var speed := 0
		var rx := 0
		var tx := 0
		for m: Net.Iface in up_members:
			speed += Game.iface_speed(m)
			rx += m.rx_frames
			tx += m.tx_frames
		var desc := String(first.note.get("text", "")) if first.note is Dictionary else ""
		var out := "Port-Channel%d is %s, line protocol is %s (%s)\n" % [group, "up" if not up_members.is_empty() else "down",
			"up" if not up_members.is_empty() else "lowerlayerdown", "connected" if not up_members.is_empty() else "notconnect"]
		if desc != "":
			out += "  Description: %s\n" % desc
		out += "  Hardware is Port-Channel, address is %s\n  Ethernet MTU %d bytes\n  Full-duplex, %s\n  Active members in this channel: %d\n" % [
			Net.mac_dotted(first.mac), first.mtu, ("%dGb/s" % (speed / 1000)) if speed >= 1000 else "%dMb/s" % speed, up_members.size()]
		for m: Net.Iface in members:
			out += "  ... %s, %s\n" % [m.name, "Full-duplex, %s" % (("%dGb/s" % (Game.iface_speed(m) / 1000)) if Game.iface_speed(m) >= 1000 else "%dMb/s" % Game.iface_speed(m)) if Sim.lag_bundled(m) else "down"]
		out += "     %d packets input, %d input errors\n     %d packets output, 0 output errors\n" % [rx, first.rx_errors, tx]
		return out

	func _no_switchport(_r: Array) -> String:
		## a routed port: the L3 switch treats it as a router interface
		if dev.type != "switch":
			return "% Invalid input\n"
		if not Game.is_l3_switch(dev):
			return "% this model has no L3 switching: a routed port needs an Arivista-class switch\n"
		return _each(func(i: Net.Iface) -> String:
			if i.name.begins_with("Vlan") or i.name.begins_with("Management"):
				return "% %s is not a switchport\n" % i.name
			i.mode = "routed"
			i.tagged_vlans = []
			Game.topology_changed.emit()
			return "")

	func _switchport_back(r: Array) -> String:
		if not r.is_empty():
			return "% Invalid input\n"
		return _each(func(i: Net.Iface) -> String:
			if i.mode == "routed":
				for cidr in i.ips.duplicate():
					Game.remove_ip(i, cidr)  # a switchport carries no address
				i.mode = "access"
				Game.topology_changed.emit()
			return "")

	func _sw_mode(r: Array) -> String:
		if dev.type != "switch":
			return "% Invalid input\n"
		if ctx_if != null and ctx_if.mode == "routed":
			return "% %s is a routed port: 'switchport' first\n" % ctx_if.name
		for m in ["access", "trunk"]:
			if r.size() == 1 and m.begins_with(r[0]):
				return _each(func(i: Net.Iface) -> String:
					i.mode = m
					return "")
		return "% Invalid input\n"

	func _sw_access_vlan(r: Array) -> String:
		if dev.type != "switch":
			return "% Invalid input\n"
		if r.size() != 1 or not String(r[0]).is_valid_int():
			return "% Incomplete command\n"
		var vid := int(r[0])
		if vid < 1 or vid > 4094:
			return "% Invalid input\n"
		# EOS does not create the VLAN for you: the port remembers the number
		# and sits inactive until 'vlan N' exists (show vlan will not list it)
		return _each(func(i: Net.Iface) -> String:
			if not Game.set_access_vlan(i, vid):
				i.untagged_vlan = vid
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
		## radius-server host <ip> [key <secret>]
		if r.is_empty() or not (r[0].is_valid_ip_address() or Net.is_v6(r[0])):
			return "% Incomplete command\n" if r.is_empty() else "% Invalid input\n"
		if r.size() >= 3 and String(r[1]) == "key":
			dev.services["radius_key"] = String(r[2])
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
			return "% Incomplete command\n"
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
			return "%% no device named %s\n" % other
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
		var mc: Dictionary = dev.services.get("mlag", {})
		var peer := Sim.mlag_peer_of(dev)
		var pl := Sim.mlag_peerlink(dev)
		var peer_addr := String(mc.get("peer_addr", ""))
		if peer_addr == "" and peer != null:
			peer_addr = CLI.first_ip_of(peer)
		var configured := 0
		var active_full := 0
		var active_partial := 0
		var inactive := 0
		for i: Net.Iface in dev.ifaces:
			if i.mlag <= 0:
				continue
			configured += 1
			var far := Sim.mlag_port(peer, i.mlag) if peer != null else null
			var l_up := Game.link_at(i) != null and i.enabled
			var r_up := far != null and Game.link_at(far) != null and far.enabled
			if l_up and r_up:
				active_full += 1
			elif l_up or r_up:
				active_partial += 1
			else:
				inactive += 1
		var out := "MLAG Configuration:\ndomain_id                          : %18s\nlocal-interface                    : %18s\npeer-address                       : %18s\npeer-link                          : %18s\npeer-config                        : %18s\n\n" % [
			String(mc.get("domain", dev.mlag_peer if dev.mlag_peer != "" else "")), String(mc.get("local_if", "")), peer_addr,
			String(mc.get("peer_link", ("Port-Channel%d" % pl.lag if pl.lag > 0 else pl.name) if pl != null else "")),
			"consistent" if peer != null else "unknown"]
		out += "MLAG Status:\nstate                              : %18s\nnegotiation status                 : %18s\npeer-link status                   : %18s\nlocal-int status                   : %18s\nsystem-id                          : %18s\ndual-primary detection             : %18s\n\n" % [
			"Active" if peer != null and pl != null else ("Inactive" if peer != null else "Disabled"),
			"Connected" if peer != null and pl != null else "Connecting", "Up" if pl != null else "Down",
			"Up" if peer != null else "Down", dev.ifaces[0].mac.to_lower() if not dev.ifaces.is_empty() else "-", "Disabled"]
		out += "MLAG Ports:\nDisabled                           : %18d\nConfigured                         : %18d\nInactive                           : %18d\nActive-partial                     : %18d\nActive-full                        : %18d\n" % [
			0, configured - active_full - active_partial - inactive, inactive, active_partial, active_full]
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

	func _sw_trunk_native(r: Array) -> String:
		## the VLAN this trunk sends and expects untagged; both ends must agree
		## or two VLANs quietly become one
		if dev.type != "switch":
			return "% Invalid input\n"
		if r.size() != 1 or not String(r[0]).is_valid_int() or int(r[0]) < 1 or int(r[0]) > 4094:
			return "% Incomplete command\n"
		return _each(func(i: Net.Iface) -> String:
			i.untagged_vlan = int(r[0])
			Game.topology_changed.emit()
			return "")

	static func parse_vlan_list(text: String) -> Array:
		## 10,20,30-35 -> [10, 20, 30, 31, 32, 33, 34, 35]; [] when malformed
		var vids: Array = []
		for part in text.split(",", false):
			var p := String(part).strip_edges()
			if "-" in p:
				var ends := p.split("-")
				if ends.size() != 2 or not ends[0].is_valid_int() or not ends[1].is_valid_int():
					return []
				var lo := int(ends[0])
				var hi := int(ends[1])
				if lo < 1 or hi > 4094 or lo > hi:
					return []
				for v in range(lo, hi + 1):
					vids.append(v)
			elif p.is_valid_int() and int(p) >= 1 and int(p) <= 4094:
				vids.append(int(p))
			else:
				return []
		return vids

	func _sw_trunk_vlans(r: Array) -> String:
		## switchport trunk allowed vlan <list>|all|add <list>|remove <list>|except <list>
		if dev.type != "switch":
			return "% Invalid input\n"
		var usage := "% Invalid input\n"
		if r.size() == 1 and String(r[0]) in ["all", "none"]:
			return _each(func(i: Net.Iface) -> String:
				i.tagged_vlans = [] if String(r[0]) == "all" else [4095]  # none: a list nothing is in
				return "")
		if r.size() == 1:
			var vids := EOS.parse_vlan_list(String(r[0]))
			if vids.is_empty():
				return usage
			return _each(func(i: Net.Iface) -> String:
				i.tagged_vlans = vids.duplicate()
				return "")
		if r.size() != 2 or String(r[0]) not in ["add", "remove", "except"]:
			return usage
		var change := EOS.parse_vlan_list(String(r[1]))
		if change.is_empty():
			return usage
		return _each(func(i: Net.Iface) -> String:
			match String(r[0]):
				"add":
					# 'all' is the empty list; adding to everything changes nothing
					if not i.tagged_vlans.is_empty():
						for v in change:
							if v not in i.tagged_vlans:
								i.tagged_vlans.append(v)
						i.tagged_vlans.sort()
				"remove":
					if i.tagged_vlans.is_empty():
						var everything: Array = dev.vlans.keys()
						everything.sort()
						i.tagged_vlans = everything
					for v in change:
						i.tagged_vlans.erase(v)
				"except":
					var keep: Array = []
					for v in dev.vlans.keys():
						if int(v) not in change:
							keep.append(int(v))
					keep.sort()
					i.tagged_vlans = keep
			return "")

	func _sync_vtep_src() -> void:
		## the VTEP address follows its source interface
		var src_if := String(dev.vtep.get("src_if", ""))
		if src_if == "":
			return
		for i: Net.Iface in dev.ifaces:
			if i.name == src_if and not i.ips.is_empty():
				dev.vtep["src"] = String(i.ips[0]).split("/")[0]

	func _if_ip(r: Array) -> String:
		if ctx_ifs.size() > 1:
			return _range_only("an address")
		if dev.type == "switch" and not ctx_if.name.begins_with("Management") \
				and not ctx_if.name.begins_with("Vlan") and ctx_if.mode != "routed":
			return "% a switchport carries no address: put it on an SVI (interface Vlan<n>), the Management1 port, or make this a routed port with 'no switchport'\n"
		r = CLI.fold_mask(r)
		if r.size() != 1:
			return "% Incomplete command\n"
		if not Game.add_ip(ctx_if, r[0]):
			return "% Invalid input\n"
		_sync_vtep_src()
		return ""

	func _if_helper(r: Array) -> String:
		if not dev.ip_forwarding:
			return "% DHCP relay needs a router or firewall\n"
		if r.size() == 1 and String(r[0]).is_valid_ip_address():
			ctx_if.helper = r[0]
			Game.topology_changed.emit()
			return ""
		return "% Invalid input\n"

	func _if_lag(r: Array) -> String:
		if dev.type != "switch":
			return "% Invalid input\n"
		var mode := "on"
		if r.size() == 1 and String(r[0]).is_valid_int():
			return "% Incomplete command\n"  # EOS wants the mode said out loud
		if r.size() == 3 and String(r[1]) == "mode" and String(r[2]) in ["active", "passive", "on"]:
			mode = String(r[2])
			r = [r[0]]
		if r.size() == 1 and String(r[0]).is_valid_int() and int(r[0]) >= 1:
			return _each(func(i: Net.Iface) -> String:
				i.lag = int(r[0])
				i.lag_mode = mode
				return "")
		return "% Invalid input\n"

	func _show_lag(_r: Array) -> String:
		## the EOS summary: the flag legend, the counts, then Port-Channel /
		## Protocol / Ports with the per-member flags
		var groups := {}
		for i: Net.Iface in dev.ifaces:
			if i.lag > 0:
				if not groups.has(i.lag):
					groups[i.lag] = []
				groups[i.lag].append(i)
		var out := "Flags\n------------------------ ---------------------------- -------------------------\n  a - LACP Active          p - LACP Passive           * - static fallback\n  F - Fallback enabled     f - Fallback configured    ^ - individual fallback\n  U - In Use               D - Down\n  + - In-Sync              - - Out-of-Sync            i - incompatible with agg\n  P - bundled in Po        s - suspended              G - Aggregable\n  I - Individual           S - ShortTimeout           w - wait for agg\n\n"
		var in_use := 0
		var rows := ""
		var gids := groups.keys()
		gids.sort()
		for g in gids:
			var names: Array = []
			var up := false
			var proto := "Static"
			for i: Net.Iface in groups[g]:
				var bundled := Sim.lag_bundled(i)
				up = up or bundled
				if i.lag_mode == "active":
					proto = "LACP(a)"
				elif i.lag_mode == "passive" and proto == "Static":
					proto = "LACP(p)"
				names.append("%s(%s)" % [EOS._short(i.name), "PG+" if bundled else ("I" if i.enabled else "D")])
			if up:
				in_use += 1
			rows += "   %-18s %-14s %s\n" % ["Po%d(%s)" % [g, "U" if up else "D"], proto, " ".join(PackedStringArray(names))]
		out += "Number of channels in use: %d\nNumber of aggregators: %d\n\n" % [in_use, groups.size()]
		out += "   Port-Channel       Protocol       Ports\n------------------ -------------- ------------------\n"
		return out + rows

	func _if_vrrp(r: Array) -> String:
		if ctx_ifs.size() > 1:
			return _range_only("a VRRP group")
		if not dev.ip_forwarding:
			return "% Invalid input\n"
		# vrrp <group> ipv4 <vip>   |   vrrp <group> priority-level <n>   (ip / priority accepted as aliases)
		if r.size() == 3 and String(r[0]).is_valid_int():
			if ("ipv4".begins_with(r[1]) or "ip" == String(r[1])) and String(r[2]).is_valid_ip_address():
				ctx_if.vrrp = {"group": int(r[0]), "vip": r[2],
					"priority": int(ctx_if.vrrp.get("priority", 100))}
				Game.topology_changed.emit()
				return ""
			if ("priority-level".begins_with(r[1]) or "priority".begins_with(r[1])) and String(r[2]).is_valid_int():
				if ctx_if.vrrp.is_empty():
					return "% set the virtual IP first: vrrp <group> ipv4 <vip>\n"
				ctx_if.vrrp["priority"] = int(r[2])
				Game.topology_changed.emit()
				return ""
		if r.size() == 2 and String(r[0]).is_valid_int() and "preempt".begins_with(r[1]):
			if ctx_if.vrrp.is_empty():
				return "% set the virtual IP first: vrrp <group> ipv4 <vip>\n"
			ctx_if.vrrp["preempt"] = true
			Game.topology_changed.emit()
			return ""
		return "% Invalid input\n"

	func _if_no_vrrp(r: Array) -> String:
		if r.size() == 2 and "preempt".begins_with(r[1]):
			if not ctx_if.vrrp.is_empty():
				ctx_if.vrrp["preempt"] = false  # keep a lower-priority master until it dies
				Game.topology_changed.emit()
			return ""
		ctx_if.vrrp = {}
		Game.topology_changed.emit()
		return ""

	func _show_vrrp(_r: Array) -> String:
		var out := ""
		for i: Net.Iface in dev.ifaces:
			if i.vrrp.is_empty():
				continue
			if out == "":
				out += "VRF: default\n"
			var master := Sim.vrrp_master(i.vrrp["vip"], int(i.vrrp["group"]))
			var master_ip := "0.0.0.0"
			if master != null:
				for mi: Net.Iface in master.ifaces:
					if int(mi.vrrp.get("group", -1)) == int(i.vrrp["group"]) and not mi.ips.is_empty():
						master_ip = String(mi.ips[0]).split("/")[0]
			out += "Interface: %s, IPv4 VRID: %d, Version: 2\n  Virtual Router: State %s\n    Virtual IP address: %s\n    Virtual MAC address: %s\n    Master Router: %s%s, Priority %d\n    Advertisement Interval: 1.000 seconds\n    Preempt: %s, Preempt Delay: 0 seconds\n    Master Advertisement interval: 1.000 seconds\n    Master Down Interval: %.3f seconds\n    Interface tracking: none\n\n" % [
				i.name, int(i.vrrp["group"]), "master" if master == dev else "backup", i.vrrp["vip"],
				Net.mac_dotted(Sim.vrrp_mac(int(i.vrrp["group"]))), master_ip, " (local)" if master == dev else "",
				int(master.ifaces.filter(func(mi): return int(mi.vrrp.get("group", -1)) == int(i.vrrp["group"]))[0].vrrp.get("priority", 100)) if master != null else int(i.vrrp.get("priority", 100)),
				"enabled" if bool(i.vrrp.get("preempt", true)) else "disabled", 3.0 + (256 - int(i.vrrp.get("priority", 100))) / 256.0]
		return out

	func _show_vrrp_brief(_r: Array) -> String:
		var out := "Interface                  VRID  Priority  State   Virtual IP\n"
		for i: Net.Iface in dev.ifaces:
			if i.vrrp.is_empty():
				continue
			var master := Sim.vrrp_master(i.vrrp["vip"], int(i.vrrp["group"]))
			out += "%-26s %-5d %-9d %-7s %s\n" % [i.name, int(i.vrrp["group"]), int(i.vrrp.get("priority", 100)),
				"master" if master == dev else "backup", i.vrrp["vip"]]
		return out

	func _if_nat(r: Array) -> String:
		if dev.type == "switch":
			return "% Invalid input\n"
		for m in ["inside", "outside"]:
			if r.size() == 1 and m.begins_with(r[0]):
				ctx_if.nat = m
				Game.topology_changed.emit()
				return ""
		return "% Invalid input\n"

	func _nat_cfg() -> Dictionary:
		if not dev.services.has("nat"):
			dev.services["nat"] = {"rules": [], "acls": {}}
		return dev.services["nat"]

	func _cfg_nat_source(r: Array) -> String:
		## ip nat inside source list <n> interface <if> overload
		## ip nat inside source static <inside> <outside>
		if dev.type == "switch":
			return "% Invalid input\n"
		var usage := "% Invalid input\n"
		var cfg := _nat_cfg()
		if r.size() == 3 and String(r[0]) == "static" and String(r[1]).is_valid_ip_address() and String(r[2]).is_valid_ip_address():
			cfg["rules"].append({"kind": "static", "inside": String(r[1]), "outside": String(r[2])})
			Game.topology_changed.emit()
			return ""
		if r.size() >= 4 and String(r[0]) == "list" and String(r[2]) == "interface":
			var target: Net.Iface = null
			for i: Net.Iface in dev.ifaces:
				if i.name.to_lower() == String(r[3]).to_lower() or EOS._short(i.name).to_lower() == String(r[3]).to_lower():
					target = i
			if target == null:
				return "% no interface %s\n" % r[3]
			if r.size() != 5 or String(r[4]) != "overload":
				return "% without 'overload' one public address serves one host: add overload for PAT\n"
			cfg["rules"].append({"kind": "overload", "list": String(r[1]), "iface": target.name})
			Game.topology_changed.emit()
			return ""
		return usage

	func _if_nat_source(r: Array) -> String:
		## ip nat source dynamic access-list NAME overload  |  ip nat source static A B
		## The interface it is typed on is the outside; EOS has no inside/outside marking.
		if dev.type == "switch":
			return "% Invalid input\n"
		if ctx_ifs.size() > 1:
			return _range_only("NAT")
		var cfg := _nat_cfg()
		if r.size() == 3 and String(r[0]) == "static" and String(r[1]).is_valid_ip_address() and String(r[2]).is_valid_ip_address():
			cfg["rules"].append({"kind": "static", "inside": String(r[1]), "outside": String(r[2]), "iface": ctx_if.name, "eos": true})
			ctx_if.nat = "outside"
			Game.topology_changed.emit()
			return ""
		if r.size() >= 3 and String(r[0]) == "dynamic" and String(r[1]) == "access-list":
			if r.size() != 4 or String(r[3]) != "overload":
				return "% Incomplete command\n"
			var list_name := String(r[2])
			var known: bool = cfg["acls"].has(list_name) or dev.acls.any(func(rule): return String(rule.get("list", "")) == list_name)
			if not known:
				return "% Invalid input\n"
			cfg["rules"].append({"kind": "overload", "list": list_name, "iface": ctx_if.name, "eos": true})
			ctx_if.nat = "outside"
			Game.topology_changed.emit()
			return ""
		return "% Incomplete command\n" if r.size() < 3 else "% Invalid input\n"

	func _if_no_nat_source() -> String:
		var cfg := _nat_cfg()
		cfg["rules"] = cfg["rules"].filter(func(rule): return String(rule.get("iface", "")) != ctx_if.name or not bool(rule.get("eos", false)))
		ctx_if.nat = ""
		dev.nat_flows.clear()
		dev.nat_xlate.clear()
		Game.topology_changed.emit()
		return ""

	func _show_nat_eos(_r: Array) -> String:
		var out := "Source IP       Source Port  Destination IP   Destination Port  Translated IP    Translated Port  Protocol  Type\n"
		for fid in dev.nat_xlate:
			var t: Dictionary = dev.nat_xlate[fid]
			var port := int(t["port"])
			var statics: Array = _nat_cfg()["rules"].filter(func(rule): return String(rule.get("kind", "")) == "static" and String(rule.get("inside", "")) == String(t["il"]))
			out += "%-15s %-12d %-16s %-17d %-16s %-16d %-9s %s\n" % [t["il"], port, t["ol"], port, t["ig"], port, t["proto"],
				"static" if not statics.is_empty() else "dynamic"]
		return out

	func _cfg_no_nat_source(_r: Array) -> String:
		_nat_cfg()["rules"] = []
		dev.nat_flows.clear()
		dev.nat_xlate.clear()
		Game.topology_changed.emit()
		return ""

	func _cfg_std_acl(r: Array) -> String:
		## access-list <n> permit|deny <net> <wildcard> | host <ip> | any
		var usage := "% Invalid input\n"
		if r.size() < 3 or not String(r[0]).is_valid_int() or String(r[1]) not in ["permit", "deny"]:
			return usage
		var entry := {"action": String(r[1]), "net": "0.0.0.0", "plen": 0}
		if String(r[2]) == "any":
			pass
		elif String(r[2]) == "host" and r.size() == 4 and String(r[3]).is_valid_ip_address():
			entry["net"] = String(r[3])
			entry["plen"] = 32
		elif r.size() == 4 and String(r[2]).is_valid_ip_address() and String(r[3]).is_valid_ip_address():
			var plen := CLI.mask_to_plen(Net.int_to_ip((~Net.ip_to_int(String(r[3]))) & 0xFFFFFFFF))
			if plen < 0:
				return "% that is not a contiguous wildcard mask\n"
			entry["net"] = String(r[2])
			entry["plen"] = plen
		else:
			return usage
		var cfg := _nat_cfg()
		if not cfg["acls"].has(String(r[0])):
			cfg["acls"][String(r[0])] = []
		cfg["acls"][String(r[0])].append(entry)
		Game.topology_changed.emit()
		return ""

	func _cfg_no_std_acl(r: Array) -> String:
		if r.size() >= 1:
			_nat_cfg()["acls"].erase(String(r[0]))
			Game.topology_changed.emit()
		return ""

	func _show_nat(_r: Array) -> String:
		if dev.nat_xlate.is_empty():
			return "  (no translations: nothing has been translated since the table was last cleared)\n"
		var out := "%-5s %-22s %-22s %-22s %s\n" % ["Pro", "Inside global", "Inside local", "Outside local", "Outside global"]
		for fid in dev.nat_xlate:
			var t: Dictionary = dev.nat_xlate[fid]
			var port := int(t["port"])
			out += "%-5s %-22s %-22s %-22s %s\n" % [t["proto"], "%s:%d" % [t["ig"], port], "%s:%d" % [t["il"], port],
				"%s:%d" % [t["ol"], port], "%s:%d" % [t["ol"], port]]
		return out

	func _show_nat_stats(_r: Array) -> String:
		var cfg: Dictionary = dev.services.get("nat", {})
		var inside: Array = []
		var outside: Array = []
		for i: Net.Iface in dev.ifaces:
			if i.nat == "inside":
				inside.append(EOS._short(i.name))
			elif i.nat == "outside":
				outside.append(EOS._short(i.name))
		var out := "Total active translations: %d\n" % dev.nat_xlate.size()
		out += "Outside interfaces: %s\nInside interfaces: %s\n" % [", ".join(PackedStringArray(outside)) if not outside.is_empty() else "(none)",
			", ".join(PackedStringArray(inside)) if not inside.is_empty() else "(none)"]
		for rule in cfg.get("rules", []):
			match String(rule.get("kind", "")):
				"overload": out += "Dynamic mapping: access-list %s interface %s overload\n" % [rule["list"], EOS._short(String(rule["iface"]))]
				"static": out += "Static mapping: %s -> %s\n" % [rule["inside"], rule["outside"]]
				"masquerade": out += "Masquerade on %s\n" % rule["iface"]
		return out

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
			return "% Incomplete command\n"
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
			return "% Incomplete command\n"
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
			return "% Incomplete command\n"
		ctx_if.tunnel_src = r[0]
		Game.topology_changed.emit()
		return ""

	func _tunnel_dst(r: Array) -> String:
		if not ctx_if.name.begins_with("Tunnel"):
			return "% that is not a tunnel interface\n"
		if r.size() != 1:
			return "% Incomplete command\n"
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
		if r.size() == 2 and String(r[0]) == "vlan":
			r = [r[1]]  # EOS: encapsulation dot1q vlan 60
		if r.size() == 1 and String(r[0]).is_valid_int():
			if int(r[0]) != ctx_if.dot1q:
				return "%% this subinterface carries VLAN %d (it is named for it)\n" % ctx_if.dot1q
			return ""
		return "% Invalid input\n"

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
		if r.size() == 1 and String(r[0]).is_valid_int() and int(r[0]) >= 68 and int(r[0]) <= 9214:
			return _each(func(i: Net.Iface) -> String:
				i.mtu = int(r[0])
				return "")
		return "% Invalid input\n"

	func _set_stateful(on: bool) -> String:
		if dev.type != "firewall":
			return "% stateful inspection needs a firewall\n"
		dev.stateful = on
		Game.topology_changed.emit()
		return ""

	var _acl_seq := 0  # the sequence number typed in front of a permit/deny, if any

	func _cfg_ip_acl(r: Array) -> String:
		## ip access-list NAME: enter the list, creating it if new. Routers and
		## firewalls both filter, as on EOS; a switch would need the L3 model.
		if not dev.ip_forwarding:
			return "% Invalid input\n"
		if r.size() != 1:
			return "% Incomplete command\n"
		ctx_acl = String(r[0])
		mode = "acl"
		return ""

	func _cfg_no_ip_acl(r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		dev.acls = dev.acls.filter(func(rule): return String(rule.get("list", "")) != String(r[0]))
		var groups: Dictionary = dev.services.get("acl_groups", {})
		for k in groups.keys():
			if String(groups[k]) == String(r[0]):
				groups.erase(k)
		Game.topology_changed.emit()
		return ""

	func _acl_remove_seq(seq: int) -> String:
		for rule in dev.acls.duplicate():
			if String(rule.get("list", "")) == ctx_acl and int(rule.get("seq", 0)) == seq:
				dev.acls.erase(rule)
				Game.topology_changed.emit()
				return ""
		return "% Invalid input\n"

	func _if_access_group(r: Array) -> String:
		## ip access-group NAME in|out: a list filters nothing until it is applied
		if not dev.ip_forwarding:
			return "% Invalid input\n"
		if r.size() != 2 or String(r[1]) not in ["in", "out"]:
			return "% Incomplete command\n" if r.size() < 2 else "% Invalid input\n"
		if not dev.acls.any(func(rule): return String(rule.get("list", "")) == String(r[0])):
			return "% Invalid input\n"
		return _each(func(i: Net.Iface) -> String:
			var groups: Dictionary = dev.services.get("acl_groups", {})
			groups[i.name] = String(r[0])
			dev.services["acl_groups"] = groups
			return "")

	func _cfg_acl(r: Array, action: String, list_name: String) -> String:
		if dev.type != "firewall" and (list_name == "" or not dev.ip_forwarding):
			return "% ACLs need a firewall\n" if list_name == "" else "% Invalid input\n"
		var usage := "% Invalid input\n"
		var proto := "ip"
		if not r.is_empty() and String(r[0]) in ["ip", "tcp", "udp", "icmp"]:
			proto = String(r.pop_front())
		var established := false
		if not r.is_empty() and String(r.back()) == "established":
			established = true
			r.pop_back()
		var port := 0
		if r.size() >= 2 and String(r[r.size() - 2]) == "eq":
			if not String(r.back()).is_valid_int() or proto not in ["tcp", "udp"]:
				return "% a port needs tcp or udp: acl %s tcp any any eq 22\n" % action
			port = int(r.back())
			r = r.slice(0, r.size() - 2)
		if established and proto not in ["ip", "tcp"]:
			return "% established describes tcp return traffic\n"
		# 'host a.b.c.d' is how IOS spells a /32
		var addrs: Array = []
		var i := 0
		while i < r.size():
			if String(r[i]) == "host" and i + 1 < r.size():
				addrs.append("%s/32" % r[i + 1])
				i += 2
			else:
				addrs.append("0.0.0.0/0" if String(r[i]) == "any" else String(r[i]))
				i += 1
		if addrs.size() != 2:
			return usage
		if not Net.valid_cidr(addrs[0]) or not Net.valid_cidr(addrs[1]):
			return "% bad prefix: use a.b.c.d/len, 'host a.b.c.d' or 'any'\n"
		var sp: PackedStringArray = String(addrs[0]).split("/")
		var dp: PackedStringArray = String(addrs[1]).split("/")
		var rule := {"action": action, "src": sp[0], "splen": int(sp[1]), "dst": dp[0], "dplen": int(dp[1])}
		if proto != "ip":
			rule["proto"] = proto
		if port != 0:
			rule["port"] = port
		if established:
			rule["established"] = true
		if list_name != "":
			rule["list"] = list_name
			var seq := _acl_seq
			if seq == 0:
				for other in dev.acls:  # EOS numbers by tens after the last entry
					if String(other.get("list", "")) == list_name:
						seq = maxi(seq, int(other.get("seq", 0)))
				seq += 10
			for other in dev.acls.duplicate():  # a repeated sequence number replaces
				if String(other.get("list", "")) == list_name and int(other.get("seq", 0)) == seq:
					dev.acls.erase(other)
			rule["seq"] = seq
			var at := dev.acls.size()
			for k in dev.acls.size():
				if String(dev.acls[k].get("list", "")) == list_name and int(dev.acls[k].get("seq", 0)) > seq:
					at = k
					break
			dev.acls.insert(at, rule)
		else:
			dev.acls.append(rule)
		Game.topology_changed.emit()
		return ""

	func _cfg_no_acl(r: Array) -> String:
		if r.size() == 1 and String(r[0]).is_valid_int() and int(r[0]) >= 1 and int(r[0]) <= dev.acls.size():
			dev.acls.remove_at(int(r[0]) - 1)
			Game.topology_changed.emit()
			return ""
		return "% Invalid input\n"

	func _show_acl(_r: Array) -> String:
		## named lists in the EOS shape; the old global rules keep their table
		var out := ""
		var names: Array = []
		for rule in dev.acls:
			var nm := String(rule.get("list", ""))
			if nm != "" and nm not in names:
				names.append(nm)
		for nm in names:
			out += "IP Access List %s\n" % nm
			for rule in dev.acls:
				if String(rule.get("list", "")) == nm:
					out += "        %d %s\n" % [int(rule.get("seq", 0)), CLI.acl_config_text(rule)]
		var legacy: Array = dev.acls.filter(func(rule): return String(rule.get("list", "")) == "")
		if legacy.is_empty():
			return out
		out += "mode: %s\n" % ("stateful (return traffic auto-permitted)" if dev.stateful else "stateless")
		var n := 1
		for rule in legacy:
			out += "%2d  %s\n" % [n, CLI.acl_rule_text(rule)]
			n += 1
		return out + "    (first match wins; implicit deny any any at the end)\n"

	func _dhcp_svc() -> Dictionary:
		if not dev.services.has("dhcp"):
			dev.services["dhcp"] = {"iface": "", "start": "", "end": "", "plen": 24, "gw": "", "dns": "",
				"leases": {}, "since": {}, "excluded": [], "name": ""}
		return dev.services["dhcp"]

	func _cfg_dhcp_server(_r: Array) -> String:
		if not dev.ip_forwarding:
			return "% a DHCP server lives on a router; a Linux host runs dhcpd\n"
		_dhcp_svc()
		mode = "dhcpsrv"
		return ""

	func _dhcp_subnet(r: Array) -> String:
		## subnet 10.0.10.0/24: the pool is the whole subnet until range says otherwise
		if r.size() != 1 or not Net.valid_cidr(String(r[0])):
			return "% Incomplete command\n" if r.is_empty() else "% Invalid input\n"
		var err := _dhcp_network([r[0]])
		if err != "":
			return err
		ctx_subnet = "%s/%d" % [Net.network_of(String(r[0]))["prefix"], int(Net.network_of(String(r[0]))["plen"])]
		mode = "dhcpsub"
		return ""

	func _dhcp_range(r: Array) -> String:
		if r.size() != 2 or not String(r[0]).is_valid_ip_address() or not String(r[1]).is_valid_ip_address():
			return "% Incomplete command\n" if r.size() < 2 else "% Invalid input\n"
		var svc := _dhcp_svc()
		var netw := Net.network_of(ctx_subnet)
		if not Net.same_net(String(r[0]), String(netw["prefix"]), int(netw["plen"])) or not Net.same_net(String(r[1]), String(netw["prefix"]), int(netw["plen"])):
			return "% Invalid input\n"
		svc["start"] = String(r[0])
		svc["end"] = String(r[1])
		Game.topology_changed.emit()
		return ""

	func _if_dhcp_server(_r: Array) -> String:
		## dhcp server ipv4: the interfaces the server answers on
		var svc := _dhcp_svc()
		var on: Array = svc.get("on", [])
		for i: Net.Iface in ctx_ifs:
			if i.name not in on:
				on.append(i.name)
		svc["on"] = on
		Game.topology_changed.emit()
		return ""

	func _show_dhcp_server(_r: Array) -> String:
		var svc: Dictionary = dev.services.get("dhcp", {})
		if svc.is_empty() or String(svc.get("start", "")) == "":
			return ""
		var netw := Net.network_of("%s/%d" % [svc["start"], int(svc["plen"])])
		var out := "DHCP Server Configuration\n  Enabled: yes\n  Lease time: 1 day\n  Subnets:\n    %s/%d\n      Range: %s - %s\n" % [
			netw["prefix"], int(svc["plen"]), svc["start"], svc["end"]]
		if String(svc.get("gw", "")) != "":
			out += "      Default gateway: %s\n" % svc["gw"]
		if String(svc.get("dns", "")) != "":
			out += "      Name server: %s\n" % svc["dns"]
		for ex in svc.get("excluded", []):
			out += "      Reserved: %s\n" % ex
		out += "  Interfaces: %s\n" % ", ".join(PackedStringArray(svc.get("on", [])))
		out += "  Leases: %d active\n" % svc.get("leases", {}).size()
		return out

	func _show_dhcp_leases(_r: Array) -> String:
		var svc: Dictionary = dev.services.get("dhcp", {})
		var out := "Subnet             IP Address      Client MAC         Hostname        Lease Expiry\n"
		if svc.is_empty():
			return out
		var netw := Net.network_of("%s/%d" % [svc.get("start", "0.0.0.0"), int(svc.get("plen", 24))])
		for mac in svc.get("leases", {}):
			var left: int = Sim.DHCP_LEASE - (Game.cycle - int(svc.get("since", {}).get(mac, Game.cycle)))
			out += "%-18s %-15s %-18s %-15s %s\n" % ["%s/%d" % [netw["prefix"], int(svc["plen"])], svc["leases"][mac], mac,
				Sim.reverse_lookup(dev, String(svc["leases"][mac])), "%d cycle(s)" % maxi(0, left)]
		return out

	func _cfg_dhcp_pool(r: Array) -> String:
		if not dev.ip_forwarding:
			return "% a DHCP pool lives on a router; a server runs dhcpd\n"
		if r.size() != 1:
			return "% Incomplete command\n"
		var svc := _dhcp_svc()
		svc["name"] = String(r[0])
		mode = "dhcp"
		return ""

	func _dhcp_network(r: Array) -> String:
		## network <addr>/<len>  |  network <addr> <mask>
		r = CLI.fold_mask(r)
		if r.size() != 1 or not Net.valid_cidr(r[0]):
			return "% Incomplete command\n"
		var netw := Net.network_of(String(r[0]))
		var plen := int(netw["plen"])
		if plen > 30:
			return "% a pool needs a subnet with room in it\n"
		var base := Net.ip_to_int(String(netw["prefix"]))
		var svc := _dhcp_svc()
		svc["plen"] = plen
		svc["start"] = Net.int_to_ip(base + 1)
		svc["end"] = Net.int_to_ip(base + (1 << (32 - plen)) - 2)  # everything but network and broadcast
		Game.topology_changed.emit()
		return ""

	func _dhcp_opt(key: String, r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_ip_address():
			return "% Incomplete command\n"
		_dhcp_svc()[key] = String(r[0])
		Game.topology_changed.emit()
		return ""

	func _cfg_dhcp_excluded(r: Array) -> String:
		## ip dhcp excluded-address <low> [<high>]
		if r.is_empty() or not String(r[0]).is_valid_ip_address() or (r.size() == 2 and not String(r[1]).is_valid_ip_address()) or r.size() > 2:
			return "% Invalid input\n"
		var svc := _dhcp_svc()
		var lo := Net.ip_to_int(String(r[0]))
		var hi := Net.ip_to_int(String(r[r.size() - 1]))
		if hi - lo > 1024:
			return "% that excludes more than a pool could hold\n"
		for n in range(lo, hi + 1):
			var ip := Net.int_to_ip(n)
			if ip not in svc["excluded"]:
				svc["excluded"].append(ip)
		return ""

	func _show_dhcp_binding(_r: Array) -> String:
		var svc: Dictionary = dev.services.get("dhcp", {})
		if svc.is_empty():
			return "% no DHCP pool on this device\n"
		if svc["leases"].is_empty():
			return "%-16s %-18s %-12s %s\n  (no bindings yet)\n" % ["IP address", "Client-ID/HW addr", "Lease left", "Type"]
		var out := "%-16s %-18s %-12s %s\n" % ["IP address", "Client-ID/HW addr", "Lease left", "Type"]
		for mac in svc["leases"]:
			var left: int = Sim.DHCP_LEASE - (Game.cycle - int(svc.get("since", {}).get(mac, Game.cycle)))
			out += "%-16s %-18s %-12s %s\n" % [svc["leases"][mac], mac, "%d cycle(s)" % maxi(0, left), "Automatic"]
		return out

	func _show_dhcp_pool(_r: Array) -> String:
		var svc: Dictionary = dev.services.get("dhcp", {})
		if svc.is_empty():
			return "% no DHCP pool on this device\n"
		var total := Net.ip_to_int(String(svc["end"])) - Net.ip_to_int(String(svc["start"])) + 1 if String(svc.get("start", "")) != "" else 0
		var out := "Pool %s :\n Utilization mark (high/low)    : 100 / 0\n Subnet size (first/next)       : 0 / 0\n" % svc.get("name", "dhcpd")
		out += " Total addresses                : %d\n Leased addresses               : %d\n Excluded addresses             : %d\n" % [
			total, svc["leases"].size(), svc.get("excluded", []).size()]
		out += " Default router                 : %s\n DNS server                     : %s\n" % [
			svc.get("gw", "") if String(svc.get("gw", "")) != "" else "-", svc.get("dns", "") if String(svc.get("dns", "")) != "" else "-"]
		return out

	func _show_dhcp_conflict(_r: Array) -> String:
		var svc: Dictionary = dev.services.get("dhcp", {})
		var conflicts: Array = svc.get("conflicts", [])
		if conflicts.is_empty():
			return "  (no conflicts detected)\n"
		var out := "%-16s %s\n" % ["IP address", "Detection method"]
		for ip in conflicts:
			out += "%-16s %s\n" % [ip, "ARP probe before offer"]
		return out

	func _cfg_router_ospf(r: Array) -> String:
		if not dev.ip_forwarding or dev.type == "uplink":
			return "% Invalid input\n"
		if r.size() != 1 or not String(r[0]).is_valid_int():
			return "% Incomplete command\n" if r.is_empty() else "% Invalid input\n"
		if dev.ospf.is_empty():
			dev.ospf = {"networks": []}
		mode = "ospf"
		return ""

	func _ospf_network(r: Array) -> String:
		# network <p/len> area <n>   |   network <addr> <wildcard> area <n>
		var usage := "% Invalid input\n"
		if r.size() >= 3 and String(r[0]).is_valid_ip_address() and String(r[1]).is_valid_ip_address():
			var plen := CLI.mask_to_plen(Net.int_to_ip((~Net.ip_to_int(String(r[1]))) & 0xFFFFFFFF))
			if plen < 0:
				return "% that is not a contiguous wildcard mask\n"
			r = ["%s/%d" % [r[0], plen]] + r.slice(2)
		if r.size() != 3 or String(r[1]) != "area" or not Net.valid_cidr(r[0]):
			return usage
		var area := String(r[2])
		if area.is_valid_int():
			area = Net.int_to_ip(int(area))  # area 0 is 0.0.0.0, area 1 is 0.0.0.1
		elif not area.is_valid_ip_address():
			return usage
		if r[0] not in dev.ospf["networks"]:
			dev.ospf["networks"].append(r[0])
		dev.ospf["areas"] = {"area": area}  # one area per router in this model
		Game.topology_changed.emit()
		return ""

	func _ospf_no_network(r: Array) -> String:
		if r.size() >= 1:
			dev.ospf["networks"].erase(r[0])
			Game.topology_changed.emit()
			return ""
		return "% Invalid input\n"

	func _show_ospf(_r: Array) -> String:
		## Neighbor ID / Instance / VRF / Pri / State / Dead Time / Address /
		## Interface, full interface names; nothing at all when OSPF is off
		if dev.ospf.is_empty():
			return ""
		var nbs := Sim.ospf_neighbors(dev)
		var out := "Neighbor ID     Instance VRF      Pri State                  Dead Time   Address         Interface\n"
		for nb in nbs:
			var far: Net.NDevice = nb["dev"]
			var far_if: Net.Iface = null
			for fi: Net.Iface in far.ifaces:
				if fi.ips.any(func(c): return String(c).split("/")[0] == String(nb["via_ip"])):
					far_if = fi
			out += "%-15s %-8d %-8s %-3d %-22s %-11s %-15s %s\n" % [Sim.ospf_router_id(far), 1, "default",
				Sim.ospf_priority(far_if) if far_if else 1, Sim.ospf_neighbor_state(dev, nb),
				"00:00:%02d" % (31 + (Game.cycle * 7 + nbs.find(nb)) % 9), nb["via_ip"], nb["iface"].name]
		return out

	func _show_ospf_interface(_r: Array) -> String:
		if dev.ospf.is_empty():
			return ""
		var out := ""
		for i: Net.Iface in Sim.ospf_covered_ifaces(dev):
			var roles := Sim.ospf_segment_roles(dev, i)
			var p2p: bool = bool(roles.get("p2p", false))
			var state := "P2P" if p2p else ("DR" if roles.get("dr") == dev
				else ("BDR" if roles.get("bdr") == dev else "DROTHER"))
			var nbrs := 0
			for nb in Sim.ospf_neighbors(dev):
				if nb["iface"] == i:
					nbrs += 1
			var up := i.enabled and Game.link_at(i) != null
			out += "%s is %s, line protocol is %s (%s)\n  Internet Address %s, VRF default, Area %s\n  Network Type %s, Cost: %d\n  Transmit Delay is 1 sec, State %s, Priority %d\n" % [
				i.name, "up" if i.enabled else "administratively down", "up" if up else "down", "connected" if up else "notconnect",
				i.ips[0] if not i.ips.is_empty() else "unassigned", Sim.ospf_area(dev),
				"Point-To-Point" if p2p else "Broadcast", Sim.ospf_cost(i), state, Sim.ospf_priority(i)]
			if not p2p:
				var dr = roles.get("dr")
				var bdr = roles.get("bdr")
				out += "  Designated Router is %s\n  Backup Designated Router is %s\n" % [
					Sim.ospf_router_id(dr) if dr != null else "0.0.0.0", Sim.ospf_router_id(bdr) if bdr != null else "0.0.0.0"]
			out += "  Timer intervals configured, Hello 10, Dead 40, Retransmit 5\n  Neighbor Count is %d\n%s" % [nbrs,
				"  Passive interface: no routing updates sent or received\n" if i.name in dev.ospf.get("passive", []) else ""]
		return out

	func _show_ospf_database(_r: Array) -> String:
		if dev.ospf.is_empty():
			return "% OSPF not running: 'router ospf' in config mode\n"
		var out := "            OSPF Router with ID (%s)\n\n                Router Link States (Area %s)\n\n%-16s %-16s %-8s %s\n" % [
			Sim.ospf_router_id(dev), Sim.ospf_area(dev), "Link ID", "ADV Router", "Age", "Link count"]
		var routers: Array = [dev]
		for nb in Sim.ospf_neighbors(dev):
			if nb["dev"] not in routers:
				routers.append(nb["dev"])
		for r in routers:
			out += "%-16s %-16s %-8d %d\n" % [Sim.ospf_router_id(r), Sim.ospf_router_id(r),
				(Game.cycle * 37) % 1800, Sim.ospf_covered_ifaces(r).size()]
		return out

	func _ospf_router_id(r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_ip_address():
			return "% Incomplete command\n"
		dev.ospf["router_id"] = String(r[0])
		Game.topology_changed.emit()
		return ""

	func _ospf_passive(r: Array, on: bool) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		var target: Net.Iface = null
		for i: Net.Iface in dev.ifaces:
			if i.name.to_lower() == String(r[0]).to_lower() or EOS._short(i.name).to_lower() == String(r[0]).to_lower():
				target = i
		if target == null:
			return "% no interface %s\n" % r[0]
		if not dev.ospf.has("passive"):
			dev.ospf["passive"] = []
		if on and target.name not in dev.ospf["passive"]:
			dev.ospf["passive"].append(target.name)
		elif not on:
			dev.ospf["passive"].erase(target.name)
		Game.topology_changed.emit()
		return ""

	func _ospf_ref_bw(r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_int() or int(r[0]) < 1:
			return "% Incomplete command\n"
		dev.ospf["ref_bw"] = int(r[0])
		Game.topology_changed.emit()
		return ""

	func _if_ospf(table: String, r: Array, lo: int, hi: int) -> String:
		if dev.ospf.is_empty():
			return "% OSPF not running: 'router ospf' in config mode\n"
		if r.size() != 1 or not String(r[0]).is_valid_int() or int(r[0]) < lo or int(r[0]) > hi:
			return "% Incomplete command\n"
		if not dev.ospf.has(table):
			dev.ospf[table] = {}
		for i: Net.Iface in ctx_ifs:
			dev.ospf[table][i.name] = int(r[0])
		Game.topology_changed.emit()
		return ""

	func _cfg_router_bgp(r: Array) -> String:
		if not (dev.type == "router" or Game.is_l3_switch(dev)):
			return "% Invalid input\n"
		if r.size() != 1 or not String(r[0]).is_valid_int():
			return "% Incomplete command\n"
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
			return "% Incomplete command\n"
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
		if r.size() == 4 and "route-map".begins_with(r[1]) and String(r[3]) in ["in", "out"]:
			if not dev.services.get("route_maps", {}).has(String(r[2])):
				return "% Invalid input\n"
			_apply_route_map(nb, String(r[2]), String(r[3]))
			Game.topology_changed.emit()
			return ""
		if r.size() >= 3 and String(r[1]) == "description":
			nb["description"] = " ".join(PackedStringArray(r.slice(2)))
			return ""
		if r.size() == 3 and String(r[1]) == "maximum-routes":
			return "" if String(r[2]).is_valid_int() else "% Invalid input\n"
		if r.size() == 3 and String(r[1]) == "update-source":
			return "" if _find_iface(String(r[2])) != null else "% Invalid input\n"
		if r.size() >= 2 and String(r[1]) in ["next-hop-self", "send-community", "ebgp-multihop", "activate", "soft-reconfiguration"]:
			return ""
		if r.size() == 4 and "prefix-list".begins_with(r[1]) and String(r[3]) in ["in", "out"]:
			# EOS order: neighbor X prefix-list NAME in
			var named: Dictionary = dev.services.get("prefix_lists", {})
			if not named.has(String(r[2])):
				return "% Invalid input\n"
			nb["prefix_%s" % r[3]] = named[String(r[2])].duplicate()
			nb["prefix_%s_name" % r[3]] = String(r[2])
			Game.topology_changed.emit()
			return ""
		if r.size() == 4 and "prefix-list".begins_with(r[1]) and String(r[2]) in ["in", "out"]:
			var list: Array = []
			for part in String(r[3]).split(","):
				if part.strip_edges() != "":
					list.append(part.strip_edges())
			nb["prefix_%s" % r[2]] = list
			nb.erase("prefix_%s_name" % r[2])
			Game.topology_changed.emit()
			return ""
		return "% Invalid input\n"

	func _bgp_roa(r: Array) -> String:
		## roa <cidr>: sign a prefix as ours, so an upstream can reject anyone
		## else announcing it
		if r.size() != 1 or not String(r[0]).contains("/"):
			return "% Incomplete command\n"
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
			return "% Incomplete command\n"
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
		return "% Invalid input\n"

	func _bgp_no_network(r: Array) -> String:
		if r.size() == 1:
			dev.bgp["networks"].erase(r[0])
			Game.topology_changed.emit()
			return ""
		return "% Invalid input\n"

	func _show_bgp(_r: Array) -> String:
		if dev.bgp.is_empty():
			return ""
		var out := "BGP summary information for VRF default\nRouter identifier %s, local AS number %d\nNeighbor Status Codes: m - Under maintenance\n" % [
			_bgp_router_id(), int(dev.bgp["asn"])]
		out += "  %-24s %16s %-2s %-12s %-9s %-8s %-4s %-5s %-9s %-7s %-6s %s\n" % ["Description", "Neighbor", "V", "AS", "MsgRcvd", "MsgSent", "InQ", "OutQ", "Up/Down", "State", "PfxRcd", "PfxAcc"]
		for nb in dev.bgp["neighbors"]:
			# Active: we are trying and the peer is on a wire we have; Idle: no
			# such subnet, so the router is not even trying. A number in the
			# State column is the good news, the way IOS has taught everybody
			var up := Sim.bgp_established(dev, nb)
			var st := "Estab" if up else \
				("Active" if Sim._connected_iface(dev, String(nb["ip"])) != null else "Idle")
			var received := 0
			for rt in Sim._bgp_learned(dev):
				if String(rt["via"]) == String(nb["ip"]):
					received += 1
			var msgs := 4 + Game.cycle % 97 if up else 0
			out += "  %-24s %16s %-2d %-12d %-9d %-8d %-4d %-5d %-9s %-7s %-6s %s\n" % [String(nb.get("description", "")), nb["ip"], 4, int(nb["remote_as"]),
				msgs, msgs + 1, 0, 0, ("00:%02d:%02d" % [(Game.cycle * 3) % 60, (Game.cycle * 7) % 60]) if up else "never",
				st, str(received) if up else "0", str(received) if up else "0"]
		return out

	func _bgp_router_id() -> String:
		## the configured id, else the highest loopback, else the first address
		if String(dev.bgp.get("router_id", "")) != "":
			return String(dev.bgp["router_id"])
		var best := ""
		for i: Net.Iface in dev.ifaces:
			if i.name.begins_with("Loopback"):
				for cidr in i.ips:
					if not Net.is_v6(cidr) and String(cidr).split("/")[0] > best:
						best = String(cidr).split("/")[0]
		return best if best != "" else CLI.first_ip_of(dev)

	func _show_bgp_table(_r: Array) -> String:
		## the table itself: every path, which one the router picked, and the
		## origin-validation code that tells a hijack from a legitimate path
		if dev.bgp.is_empty():
			return ""
		var out := "BGP routing table information for VRF default\nRouter identifier %s, local AS number %d\n" % [
			CLI.first_ip_of(dev), int(dev.bgp["asn"])]
		out += "Route status codes: s - suppressed, * - valid, > - active, E - ECMP head, e - ECMP\n                    S - Stale, c - Contributing to ECMP, b - backup, L - labeled-unicast\n                    % - Pending BGP convergence\nOrigin codes: i - IGP, e - EGP, ? - incomplete\nRPKI Origin Validation codes: V - valid, I - invalid, U - unknown\nAS Path Attributes: Or-ID - Originator ID, C-LST - Cluster List, LL Nexthop - Link Local Nexthop\n\n"
		out += "          %-22s %-21s %-7s %-10s %-7s %-7s %s\n" % ["Network", "Next Hop", "Metric", "AIGP", "LocPref", "Weight", "Path"]
		var installed := {}
		for e in Sim.rib(dev):
			if e["src"] == "B":
				installed["%s/%d|%s" % [e["prefix"], int(e["plen"]), e["next_hop"]]] = true
		var roas: Array = dev.bgp.get("roa", [])
		for net in dev.bgp.get("networks", []):
			out += " * > %s    %-22s %-21s %-7s %-10s %-7s %-7d %s\n" % ["V" if net in roas else "U", net, "-", "-", "-", "-", 0, "i"]
		for rt in Sim._bgp_learned(dev):
			var pfx := "%s/%d" % [rt["prefix"], int(rt["plen"])]
			var path: Array = []
			for k in 1 + int(rt.get("prepend", 0)):
				path.append(str(int(rt.get("asn", 0))))
			out += " * %s %s    %-22s %-21s %-7s %-10s %-7d %-7d %s i\n" % [">" if installed.has("%s|%s" % [pfx, rt["via"]]) else " ",
				"U", pfx, rt["via"], "-", "-", int(rt.get("pref", 100)), 0, " ".join(PackedStringArray(path))]
		for h in Game.hijacks:
			# somebody else's announcement of a prefix: valid to BGP, invalid to RPKI
			out += " *   I    %-22s %-21s %-7s %-10s %-7d %-7d %s i\n" % ["%s/%d" % [h["prefix"], int(h["plen"])], h["by"], "-", "-", 100, 0, "64666"]
		return out

	func _cfg_ssid(r: Array) -> String:
		## ssid <name> vlan <id>
		if r.size() != 3 or String(r[1]) != "vlan" or not String(r[2]).is_valid_int():
			return "% Incomplete command\n"
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
			return "% Incomplete command\n"
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
			return "% Incomplete command\n"
		if Game.add_vrf(dev, r[0]):
			return ""
		return "% could not create that table (routers only, and names are unique)\n"

	func _if_vrf(r: Array) -> String:
		if ctx_ifs.size() > 1:
			return _range_only("a routing table")
		if r.size() != 1:
			return "% Incomplete command\n"
		if Game.set_iface_vrf(ctx_if, r[0]):
			return ""  # EOS says nothing; the addresses were cleared, as on the real thing
		return "% Invalid input\n"

	func _show_vrf(_r: Array) -> String:
		var out := "   Maximum number of VRFs allowed: 1023\n   %-19s %-16s %-13s %s\n   %s %s %s %s\n" % ["VRF", "Protocols", "State", "Interfaces",
			"-".repeat(19), "-".repeat(16), "-".repeat(13), "-".repeat(20)]
		var names: Array = dev.vrfs.duplicate()
		names.sort()
		names.append("default")
		for name in names:
			var members: Array = []
			for i: Net.Iface in dev.ifaces:
				if i.name == "lo":
					continue
				if (name == "default" and i.vrf == "" and (not i.ips.is_empty() or i.mode == "routed")) or (name != "default" and i.vrf == name):
					members.append(i.name)
			out += "   %-19s %-16s %-13s %s\n" % [name, "IPv4", "routing" if dev.ip_forwarding else "no routing", ", ".join(PackedStringArray(members))]
		return out

	func _cfg_ip_route(r: Array) -> String:
		if not dev.ip_forwarding:
			return "% Invalid input\n"
		# ip route [vrf <name>] <prefix/len | prefix mask> <next-hop> [<distance>]   (EOS puts vrf first)
		var vrf := ""
		if r.size() >= 2 and String(r[0]) == "vrf":
			vrf = String(r[1])
			r = r.slice(2)
		elif r.size() >= 2 and String(r[r.size() - 2]) == "vrf":
			vrf = String(r[r.size() - 1])
			r = r.slice(0, r.size() - 2)
		r = CLI.fold_mask(r)
		var name_at := r.find("name")
		if name_at > 0:
			r = r.slice(0, name_at)  # ip route P NH name TEXT: the name is a comment
		var ad := 1
		if r.size() == 3 and String(r[2]).is_valid_int():
			ad = clampi(int(r[2]), 1, 255)
			r = [r[0], r[1]]
		if r.size() == 2 and Net.valid_cidr(r[0]):
			var parts := String(r[0]).split("/")
			var nh := String(r[1])
			if not nh.is_valid_ip_address() and nh.to_lower() != "null0":
				# an interface as the next hop: the route points out of that port
				var via_if := _find_iface(nh)
				if via_if == null:
					return "% Invalid input\n"
				var far := Game.effective_peer(via_if)
				if far == null or far.ips.is_empty():
					return "% Invalid input\n"
				nh = String(far.ips[0]).split("/")[0]
			if Game.add_static_route(dev, parts[0], int(parts[1]), nh, vrf, ad):
				return ""
		return "% Invalid input\n"

	func _cfg_no_ip_route(r: Array) -> String:
		r = CLI.fold_mask(r)
		if r.size() >= 1 and Net.valid_cidr(r[0]):
			var parts := String(r[0]).split("/")
			Game.remove_static_route(dev, parts[0], int(parts[1]))
			return ""
		return "% Invalid input\n"

	# ---- show ----

	func _show_version(_r: Array) -> String:
		## the Arista block, with this model's name in the first line
		var mac: String = dev.ifaces[0].mac.to_lower() if not dev.ifaces.is_empty() else "00:00:00:00:00:00"
		var secs := Game.cycle * 3600
		var parts: Array = []
		if secs >= 86400:
			parts.append("%d day%s" % [secs / 86400, "" if secs / 86400 == 1 else "s"])
		if (secs / 3600) % 24 > 0:
			parts.append("%d hour%s" % [(secs / 3600) % 24, "" if (secs / 3600) % 24 == 1 else "s"])
		parts.append("%d minute%s" % [(secs / 60) % 60, "" if (secs / 60) % 60 == 1 else "s"])
		var uptime: String = String(parts[0]) if parts.size() == 1 else (", ".join(PackedStringArray(parts.slice(0, parts.size() - 1))) + " and " + String(parts[parts.size() - 1]))
		return "%s\nHardware version:    01.02\nSerial number:       %s\nHardware MAC address: %s\nSystem MAC address:  %s\n\nSoftware image version: 4.28.3M\nArchitecture:           x86_64\nInternal build version: 4.28.3M-28837868.4283M\nInternal build ID:      %08x-packetos\nImage format version:   3.0\nImage optimization:     Default\n\nUptime:                 %s\nTotal memory:           3953860 kB\nFree memory:            2452768 kB\n" % [
			Game.MODELS[dev.model]["label"], "JPE%08d" % (dev.name.hash() % 100000000), mac, mac, dev.name.hash() % 0xFFFFFFFF, uptime]

	func _show_int_trunk(_r: Array) -> String:
		## the four EOS sections: mode/status/native, allowed, active, forwarding
		var trunks: Array = []
		for i: Net.Iface in dev.ifaces:
			if i.mode == "trunk":
				trunks.append(i)
		if trunks.is_empty():
			return ""
		var out := "%-11s %-8s %-14s %s\n" % ["Port", "Mode", "Status", "Native vlan"]
		for i: Net.Iface in trunks:
			var status := "not-trunking" if not i.enabled or Game.peer_label(i) == "" else "trunking"
			out += "%-11s %-8s %-14s %d\n" % [EOS._short(i.name), "on", status, i.untagged_vlan]
		out += "\n%-11s %s\n" % ["Port", "Vlans allowed"]
		for i: Net.Iface in trunks:
			out += "%-11s %s\n" % [EOS._short(i.name), "1-4094" if i.tagged_vlans.is_empty()
				else ",".join(i.tagged_vlans.map(func(v): return str(v)))]
		var vids := dev.vlans.keys()
		vids.sort()
		out += "\n%-11s %s\n" % ["Port", "Vlans allowed and active in management domain"]
		for i: Net.Iface in trunks:
			var active: Array = []
			for vid in vids:
				if i.tagged_vlans.is_empty() or vid in i.tagged_vlans:
					active.append(str(vid))
			out += "%-11s %s\n" % [EOS._short(i.name), ",".join(PackedStringArray(active))]
		out += "\n%-11s %s\n" % ["Port", "Vlans in spanning tree forwarding state and not pruned"]
		for i: Net.Iface in trunks:
			var fwd: Array = []
			for vid in vids:
				if (i.tagged_vlans.is_empty() or vid in i.tagged_vlans) and not Sim.stp_blocked_for(i, int(vid)):
					fwd.append(str(vid))
			out += "%-11s %s\n" % [EOS._short(i.name), ",".join(PackedStringArray(fwd))]
		return out

	func _show_interfaces(r: Array) -> String:
		## the EOS block: hardware and bia, description, the MTU line (L2 on a
		## switchport, the IP block on a routed port), duplex and speed, uptime,
		## the two rate lines and the six-line counter section
		if r.size() >= 2 and String(r[1]).is_valid_int():
			r = [String(r[0]) + String(r[1])] + r.slice(2)  # show interfaces ethernet 1
		if r.size() >= 1 and (String(r[0]).to_lower().begins_with("po")) and String(r[0]).lstrip("Port-Chanelpo").is_valid_int():
			return _show_port_channel_if(int(String(r[0]).lstrip("Port-Chanelpo")))
		var only: Net.Iface = _find_iface(String(r[0])) if r.size() >= 1 else null
		if r.size() >= 1 and only == null:
			return "% Invalid input\n"
		var out := ""
		for i: Net.Iface in dev.ifaces:
			if only != null and i != only:
				continue
			if i.name == "lo":
				continue
			var word := Game.iface_status_word(i)
			var line1 := ""
			match word:
				"connected": line1 = "up, line protocol is up (connected)"
				"disabled": line1 = "administratively down, line protocol is down (disabled)"
				"err-disabled": line1 = "down, line protocol is down (errdisabled)"
				_: line1 = "down, line protocol is notpresent (notconnect)"
			if i.name.begins_with("Loopback") or i.name.begins_with("Vlan"):
				line1 = "up, line protocol is up (connected)" if i.enabled else "administratively down, line protocol is down (disabled)"
			out += "%s is %s\n" % [i.name, line1]
			if i.name.begins_with("Loopback"):
				out += "  Hardware is Loopback\n"
			elif i.name.begins_with("Vlan"):
				out += "  Hardware is Vlan, address is %s (bia %s)\n" % [Net.mac_dotted(i.mac), Net.mac_dotted(i.mac)]
			else:
				out += "  Hardware is Ethernet, address is %s (bia %s)\n" % [Net.mac_dotted(i.mac), Net.mac_dotted(i.mac)]
			if i.note is Dictionary and String(i.note.get("text", "")) != "":
				out += "  Description: %s\n" % i.note["text"]
			var routed := i.mode == "routed" or not i.ips.is_empty() or i.name.begins_with("Management") or dev.type != "switch"
			if routed:
				for cidr in i.ips:
					if not Net.is_v6(cidr):
						out += "  Internet address is %s\n  Broadcast address is 255.255.255.255\n  Address determined by manual configuration\n" % cidr
				out += "  IP MTU %d bytes , BW %d kbit\n" % [i.mtu, Game.iface_speed(i) * 1000]
			else:
				out += "  Ethernet MTU %d bytes\n" % i.mtu
			var peer := Game.effective_peer(i)
			var duplex := Sim.effective_duplex(i, peer) if peer != null and i.duplex == "auto" else i.duplex
			var speed := Game.iface_speed(i)
			out += "  %s-duplex, %s, auto negotiation: %s, uni-link: n/a\n" % [duplex.capitalize() if duplex != "auto" else "Full",
				("%dGb/s" % (speed / 1000)) if speed >= 1000 else "%dMb/s" % speed, "on" if i.duplex == "auto" else "off"]
			var secs := maxi(0, Game.cycle - i.dev.installed_cycle) * 3600 + (i.rx_frames * 7) % 3600
			var parts: Array = []
			if secs >= 86400:
				parts.append("%d day%s" % [secs / 86400, "" if secs / 86400 == 1 else "s"])
			if (secs / 3600) % 24 > 0 or not parts.is_empty():
				parts.append("%d hour%s" % [(secs / 3600) % 24, "" if (secs / 3600) % 24 == 1 else "s"])
			parts.append("%d minute%s" % [(secs / 60) % 60, "" if (secs / 60) % 60 == 1 else "s"])
			parts.append("%d second%s" % [secs % 60, "" if secs % 60 == 1 else "s"])
			out += "  Up %s\n  Loopback Mode : None\n  %d link status changes since last clear\n  Last clearing of \"show interface\" counters never\n" % [
				", ".join(PackedStringArray(parts)), 1 if word == "connected" else 0]
			out += "  5 minutes input rate %d bps (0.0%% with framing overhead), %d packets/sec\n  5 minutes output rate %d bps (0.0%% with framing overhead), %d packets/sec\n" % [
				i.rx_frames * 148 * 8 / 300, i.rx_frames / 300, i.tx_frames * 148 * 8 / 300, i.tx_frames / 300]
			out += "     %d packets input, %d bytes\n     Received %d broadcasts, %d multicast\n     0 runts, %d giants\n     %d input errors, %d CRC, 0 alignment, 0 symbol, 0 input discards\n     0 PAUSE input\n" % [
				i.rx_frames, i.rx_frames * 148, i.rx_frames / 20, i.rx_frames / 50, i.rx_giants, i.rx_errors, i.rx_crc]
			out += "     %d packets output, %d bytes\n     Sent %d broadcasts, %d multicast\n     0 output errors, %d collisions\n     %d late collision, 0 deferred, %d output discards\n     0 PAUSE output\n" % [
				i.tx_frames, i.tx_frames * 148, i.tx_frames / 20, i.tx_frames / 50, i.collisions, i.collisions, i.out_drops]
		return out

	func _show_vlan(_r: Array) -> String:
		if dev.type != "switch":
			return "% Invalid input\n"
		## access ports only, every one spelled out: trunk membership is what
		## 'show interfaces trunk' is for
		var out := "%-5s %-32s %-9s %s\n%s %s %s %s\n" % ["VLAN", "Name", "Status", "Ports",
			"-".repeat(5), "-".repeat(32), "-".repeat(9), "-".repeat(31)]
		var vids := dev.vlans.keys()
		vids.sort()
		for vid in vids:
			# every port that carries the VLAN, trunks included, and Cpu when an SVI exists
			var ports: Array = []
			for i: Net.Iface in dev.ifaces:
				if i.name == "Vlan%d" % vid:
					ports.append("Cpu")
			var seen_lag := {}
			for i: Net.Iface in dev.ifaces:
				if i.name.begins_with("Management") or i.name.begins_with("Vlan"):
					continue
				var carries: bool = (i.mode == "access" and i.untagged_vlan == vid) \
					or (i.mode == "trunk" and (i.tagged_vlans.is_empty() or vid in i.tagged_vlans or i.untagged_vlan == vid))
				if not carries:
					continue
				if i.lag > 0:
					if not seen_lag.has(i.lag):
						seen_lag[i.lag] = true
						ports.append("Po%d" % i.lag)
					continue
				ports.append(EOS._short(i.name))
			out += "%-5d %-32s %-9s %s\n" % [vid, dev.vlans[vid], "active", ", ".join(PackedStringArray(ports))]
		return out

	func _show_mac(_r: Array) -> String:
		## the two EOS frames, unicast and multicast, each with its total
		var out := "          Mac Address Table\n------------------------------------------------------------------\n\nVlan    Mac Address       Type        Ports      Moves   Last Move\n----    -----------       ----        -----      -----   ---------\n"
		var vlans := {}
		for v in dev.mac_table:
			vlans[v] = true
		for v in dev.mac_static:
			vlans[v] = true
		var vids := vlans.keys()
		vids.sort()
		var rows := 0
		for vlan in vids:
			for mac in dev.mac_static.get(vlan, {}):
				rows += 1
				out += "%4d    %-17s %-11s %s\n" % [vlan, Net.mac_dotted(mac), "STATIC", EOS._short(String(dev.mac_static[vlan][mac]))]
			for mac in dev.mac_table.get(vlan, {}):
				if dev.mac_static.get(vlan, {}).has(mac):
					continue
				rows += 1
				out += "%4d    %-17s %-11s %-10s %-7d %d:%02d:%02d ago\n" % [vlan, Net.mac_dotted(mac), "DYNAMIC", EOS._short(dev.mac_table[vlan][mac].name), 1,
					0, (Game.cycle * 3) % 60, (String(mac).hash() % 60)]
		out += "Total Mac Addresses for this criterion: %d\n\n          Multicast Mac Address Table\n------------------------------------------------------------------\n\nVlan    Mac Address       Type        Ports\n----    -----------       ----        -----\nTotal Mac Addresses for this criterion: 0\n" % rows
		return out

	func _mac_static(r: Array) -> String:
		## mac address-table static <mac> vlan <vid> interface <port>
		if dev.type != "switch":
			return "% static MAC entries need a switch\n"
		if r.size() != 5 or String(r[1]) != "vlan" or String(r[3]) != "interface" \
				or not String(r[2]).is_valid_int():
			return "% Invalid input\n"
		var port := _find_iface(String(r[4]))
		if port == null:
			return "% Invalid input\n"
		var vid := int(r[2])
		if not dev.mac_static.has(vid):
			dev.mac_static[vid] = {}
		dev.mac_static[vid][Net.mac_colon(String(r[0]))] = port.name  # dotted or colon in; the simulation spells MACs upper-case colon
		Game.topology_changed.emit()
		return ""

	func _no_mac_static(r: Array) -> String:
		if r.size() < 3 or String(r[1]) != "vlan" or not String(r[2]).is_valid_int():
			return "% Incomplete command\n"
		var vid := int(r[2])
		if dev.mac_static.has(vid):
			dev.mac_static[vid].erase(String(r[0]).to_upper())
			if dev.mac_static[vid].is_empty():
				dev.mac_static.erase(vid)
		Game.topology_changed.emit()
		return ""

	func _show_capture(_r: Array) -> String:
		if dev.capture.is_empty():
			return "  (no frames captured: generate some traffic)\n"
		return "\n".join(PackedStringArray(dev.capture.slice(-20).map(func(l): return Sim.capture_line(String(l))))) + "\n"

	func _aaa_login(r: Array) -> String:
		## aaa authentication login radius <ip> key <secret> [local]
		## aaa authentication login local
		if r.size() == 1 and String(r[0]) == "local":
			if dev.aaa.is_empty():
				return "% no authentication server configured to fall back from\n"
			dev.aaa["local"] = true
			Game.topology_changed.emit()
			return ""
		if r.size() >= 4 and String(r[0]) in ["radius", "tacacs"] \
				and String(r[1]).is_valid_ip_address() and String(r[2]) == "key":
			dev.aaa = {"server": String(r[1]), "key": String(r[3]),
				"local": r.size() > 4 and String(r[4]) == "local"}
			Game.topology_changed.emit()
			return ""
		return "% Invalid input\n"

	func _show_aaa(_r: Array) -> String:
		if dev.aaa.is_empty():
			return "Administrative login: local only\n"
		var admit := Sim.aaa_admit(dev)
		var out := "Authentication server: %s\n" % dev.aaa.get("server", "-")
		out += "Local fallback: %s\n" % ("configured" if bool(dev.aaa.get("local", false))
			else "NONE: if the server goes away, so does your way in")
		out += "Right now: %s%s\n" % ["would admit you" if bool(admit["ok"]) else "would LOCK YOU OUT",
			"" if String(admit["why"]) == "" else " (%s)" % admit["why"]]
		return out

	func _ra(on: bool) -> String:
		if not dev.ip_forwarding:
			return "% only a router advertises prefixes\n"
		for i: Net.Iface in ctx_ifs:
			i.ra = on
		Game.topology_changed.emit()
		return ""

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

	func _stp_edge(what: String, on: bool) -> String:
		if dev.type != "switch":
			return "% Invalid input\n"
		for i: Net.Iface in ctx_ifs:
			if what == "portfast":
				i.portfast = on
			else:
				i.bpduguard = on
		Sim.flush_learned_state()
		Game.topology_changed.emit()
		return ""

	func _stp_mode(r: Array) -> String:
		if dev.type != "switch":
			return "% Invalid input\n"
		var want: String = String(r[0]).to_lower() if r.size() > 0 else ""
		# EOS keywords first; the older spellings still land where they meant
		var map := {"mstp": "mst", "rstp": "rstp", "rapid-pvst": "rstp", "none": "rstp", "stp": "stp", "mst": "mst"}
		if not map.has(want):
			return "% Incomplete command\n" if want == "" else "% Invalid input\n"
		dev.stp_mode = map[want]
		Sim.flush_learned_state()
		Game.topology_changed.emit()
		return ""

	func _stp_priority(r: Array) -> String:
		if dev.type != "switch":
			return "% Invalid input\n"
		if r.size() < 1 or not String(r[0]).is_valid_int():
			return "% Incomplete command\n"
		if int(r[0]) < 0 or int(r[0]) > 61440 or int(r[0]) % 4096 != 0:
			return "% Bridge Priority must be in increments of 4096 (0, 4096, 8192 ... 61440)\n"
		dev.stp_priority = int(r[0])
		Sim.flush_learned_state()
		Game.topology_changed.emit()
		return ""

	func _stp_mst(r: Array) -> String:
		## spanning-tree mst instance <n> vlan <list>
		if dev.type != "switch":
			return "% Invalid input\n"
		if r.size() < 4 or r[0] != "instance" or r[2] != "vlan":
			return "% Incomplete command\n"
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
		## the EOS block per instance: Root ID, Bridge ID, timers, then the
		## Interface / Role / State / Cost / Prio.Nbr / Type table
		if dev.type != "switch":
			return "% Invalid input\n"
		var root := Sim.stp_root_of(dev)
		var proto := "mstp" if dev.stp_mode == "mst" else "rstp"
		var out := ""
		var instances: Array = Sim.mst_instances() if dev.stp_mode == "mst" else [0]
		for inst in instances:
			out += "MST%d\n  Spanning tree enabled protocol %s\n" % [int(inst), proto]
			out += "  Root ID    Priority    %d\n             Address     %s\n" % [root.stp_priority if root else dev.stp_priority,
				Net.mac_dotted(root.ifaces[0].mac) if root and not root.ifaces.is_empty() else "0000.0000.0000"]
			if root == null or root == dev:
				out += "             This bridge is the root\n"
			else:
				var root_port: Net.Iface = null
				for i: Net.Iface in dev.ifaces:
					if i.enabled and Game.link_at(i) != null and Sim.stp_role(i) == "root":
						root_port = i
				out += "             Cost        %d\n             Port        %d (%s)\n" % [
					Sim.stp_port_cost(root_port) if root_port else 0,
					dev.ifaces.find(root_port) + 1 if root_port else 0, root_port.name if root_port else "none"]
			out += "  Bridge ID  Priority    %d  (priority %d sys-id-ext %d)\n             Address     %s\n             Hello Time  2.000 sec  Max Age 20 sec  Forward Delay 15 sec\n\n" % [
				dev.stp_priority + int(inst), dev.stp_priority, int(inst), Net.mac_dotted(dev.ifaces[0].mac) if not dev.ifaces.is_empty() else "0000.0000.0000"]
			out += "Interface        Role       State      Cost      Prio.Nbr Type\n---------------- ---------- ---------- --------- -------- --------------------\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				n += 1
				var l := Game.link_at(i)
				if l == null or i.name.begins_with("Management"):
					continue
				var role := Sim.stp_role(i) if i.enabled else "disabled"
				var blocked_here: bool = Sim._stp_blocked_inst.get(inst, {}).has(i) if dev.stp_mode == "mst" else role == "alternate"
				var state := "discarding" if blocked_here or role == "disabled" else "forwarding"
				if role != "disabled" and blocked_here:
					role = "alternate"
				var port_no := int(i.name.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-")) if i.name.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-").is_valid_int() else n
				out += "%-16s %-10s %-10s %-9d %-8s %s\n" % [EOS._short(i.name), role, state, Sim.stp_port_cost(i),
					"128.%d" % port_no, "P2p Edge" if i.portfast else "P2p"]
			out += "\n"
		return out

	func _vtep() -> Dictionary:
		if dev.vtep.is_empty():
			dev.vtep = {"src": "", "peers": [], "map": {}, "evpn": false}
		return dev.vtep

	func _cfg_vxlan_source(r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_ip_address():
			return "% Incomplete command\n"
		_vtep()["src"] = String(r[0])
		Game.topology_changed.emit()
		return ""

	func _cfg_vxlan_vlan(r: Array) -> String:
		# vxlan vlan <id> vni <id>
		if r.size() != 3 or String(r[1]) != "vni" or not String(r[0]).is_valid_int() \
				or not String(r[2]).is_valid_int():
			return "% Invalid input\n"
		if not dev.vlans.has(int(r[0])):
			return "%% vlan %s is not on this switch\n" % r[0]
		_vtep()["map"][int(r[0])] = int(r[2])
		Game.topology_changed.emit()
		return ""

	func _cfg_vxlan_peer(r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_ip_address():
			return "% Incomplete command\n"
		var peers: Array = _vtep()["peers"]
		if String(r[0]) not in peers:
			peers.append(String(r[0]))
		Game.topology_changed.emit()
		return ""

	func _cfg_vxlan_evpn(r: Array) -> String:
		_vtep()["evpn"] = r.is_empty() or String(r[0]) != "off"
		Game.topology_changed.emit()
		return ""

	func _show_vxlan(_r: Array) -> String:
		if dev.vtep.is_empty():
			return "vxlan is not configured on this device\n"
		var out := "source %s   control plane %s\n" % [dev.vtep.get("src", "-"),
			"evpn" if bool(dev.vtep.get("evpn", false)) else "flood-and-learn"]
		out += "peers %s\n" % ", ".join(PackedStringArray(dev.vtep.get("peers", [])))
		for v: int in dev.vtep.get("map", {}):
			out += "vlan %-6d vni %d\n" % [v, int(dev.vtep["map"][v])]
		var any := false
		for v2: int in dev.remote_macs:
			for mac: String in dev.remote_macs[v2]:
				if not any:
					out += "%-18s %-8s %s\n" % ["REMOTE MAC", "VLAN", "BEHIND VTEP"]
					any = true
				out += "%-18s %-8d %s\n" % [mac, v2, dev.remote_macs[v2][mac]]
		return out

	func _cfg_nat64(r: Array) -> String:
		# nat64 prefix <64:ff9b::> pool <ipv4>
		if not dev.ip_forwarding:
			return "% nat64 runs on a router or firewall\n"
		if r.size() < 3 or String(r[1]) != "pool":
			return "% Incomplete command\n"
		var prefix := String(r[0])
		var pool := String(r[2])
		if not prefix.ends_with("::") or not (prefix + "1").is_valid_ip_address():
			return "% nat64: the prefix must be an IPv6 prefix ending in ::\n"
		if not pool.is_valid_ip_address() or Net.is_v6(pool):
			return "% nat64: the pool must be an IPv4 address you own\n"
		dev.services["nat64"] = {"prefix": prefix, "pool": pool, "translated": 0,
			"returned": 0, "last_error": ""}
		Game.topology_changed.emit()
		return ""

	func _show_nat64(_r: Array) -> String:
		var cfg: Dictionary = dev.services.get("nat64", {})
		if cfg.is_empty():
			return "nat64 is not configured on this device\n"
		return ("prefix       %s\npool         %s\ntranslated   %d\nreturned     %d\nstate        %d flow(s)\nlast error   %s\n"
			% [cfg.get("prefix", ""), cfg.get("pool", ""), int(cfg.get("translated", 0)),
				int(cfg.get("returned", 0)), dev.nat64_flows.size(),
				cfg.get("last_error", "") if String(cfg.get("last_error", "")) != "" else "none"])

	func _show_counters(_r: Array) -> String:
		## the In block and the Out block, the way EOS splits them
		var out := "Port      InOctets     InUcastPkts   InMcastPkts   InBcastPkts\n"
		for i: Net.Iface in dev.ifaces:
			out += "%-9s %-12d %-13d %-13d %d\n" % [EOS._short(i.name), i.rx_frames * 148, i.rx_frames, i.rx_frames / 50, i.rx_frames / 20]
		out += "\nPort      OutOctets    OutUcastPkts  OutMcastPkts  OutBcastPkts\n"
		for i: Net.Iface in dev.ifaces:
			out += "%-9s %-12d %-13d %-13d %d\n" % [EOS._short(i.name), i.tx_frames * 148, i.tx_frames, i.tx_frames / 50, i.tx_frames / 20]
		return out

	func _clear_counters(_r: Array) -> String:
		for i: Net.Iface in dev.ifaces:
			i.tx_frames = 0
			i.rx_frames = 0
			i.rx_errors = 0
			i.rx_crc = 0
			i.rx_giants = 0
			i.out_drops = 0
			i.collisions = 0
		return ""

	func _show_counter_errors(_r: Array) -> String:
		## the read that separates the cable from the configuration: FCS errors
		## are the wire, FrameTooLongs an MTU, TxErr a full pipe
		var out := "Port      FCSErr   AlignErr   SymbolErr   RxErr   FrameTooShorts   FrameTooLongs   TxErr\n"
		for i: Net.Iface in dev.ifaces:
			out += "%-9s %-8d %-10d %-11d %-7d %-16d %-15d %d\n" % [EOS._short(i.name), i.rx_crc, i.collisions, 0,
				i.rx_errors, 0, i.rx_giants, i.out_drops]
		return out

	func _if_duplex(r: Array) -> String:
		if r.size() != 1 or String(r[0]) not in ["auto", "full", "half"]:
			return "% Incomplete command\n"
		return _each(func(i: Net.Iface) -> String:
			i.duplex = String(r[0])
			return "")

	func _show_lldp(_r: Array) -> String:
		## the EOS table: the five summary lines, then Port / Neighbor Device
		## ID / Neighbor Port ID / TTL, the far port unabbreviated
		var rows := ""
		var n := 0
		for i: Net.Iface in dev.ifaces:
			var peer := Game.effective_peer(i)
			if peer != null and not dev.services.has("lldp_off"):
				n += 1
				# LLDP hears the device at the far end, not the panel in between
				rows += "%-13s %-24s %-22s %d\n" % [EOS._short(i.name), peer.dev.name, peer.name, 120]
		var out := "Last table change time   : %d:%02d:%02d ago\nNumber of table inserts  : %d\nNumber of table deletes  : 0\nNumber of table drops    : 0\nNumber of table age-outs : 0\n\n" % [
			(Game.cycle * 3) / 60, (Game.cycle * 3) % 60, (Game.cycle * 17) % 60, n]
		out += "Port          Neighbor Device ID       Neighbor Port ID       TTL\n---------- ------------------------ ---------------------- ---\n"
		return out + rows

	func _show_arp(_r: Array) -> String:
		## Address / Age (sec) as h:mm:ss / Hardware Addr / Interface, full
		## names, the SVI then the physical port for an entry on a VLAN
		var out := "%-15s %9s  %-15s %s\n" % ["Address", "Age (sec)", "Hardware Addr", "Interface"]
		for ip in dev.arp:
			var age_cycles := Game.cycle - int(dev.arp_seen.get(ip, Game.cycle))
			var secs := maxi(0, age_cycles) * 60 + (int(String(ip).hash()) % 50)
			var ifn := CLI.arp_iface_name(dev, String(ip))
			var full := ifn
			for i: Net.Iface in dev.ifaces:
				if EOS._short(i.name) == ifn or i.name == ifn:
					full = i.name
			if full.begins_with("Vlan"):
				var phys := Sim._connected_iface(dev, String(ip))
				var via := ""
				for i: Net.Iface in dev.ifaces:
					if i.mode == "access" and full == "Vlan%d" % i.untagged_vlan and Game.link_at(i) != null:
						via = i.name
						break
				if via != "":
					full += ", " + via
			out += "%-15s %9s  %-15s %s\n" % [ip, "%d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60], Net.mac_dotted(String(dev.arp[ip])), full]
		return out

	const ROUTE_CODES := "Codes: C - connected, S - static, K - kernel,\n       O - OSPF, IA - OSPF inter area, E1 - OSPF external type 1,\n       E2 - OSPF external type 2, N1 - OSPF NSSA external type 1,\n       N2 - OSPF NSSA external type2, B - Other BGP Routes,\n       B I - iBGP, B E - eBGP, R - RIP, I L1 - IS-IS level 1,\n       I L2 - IS-IS level 2, O3 - OSPFv3, A B - BGP Aggregate,\n       A O - OSPF Summary, NG - Nexthop Group Static Route,\n       V - VXLAN Control Service, M - Martian,\n       DH - DHCP client installed default route,\n       DP - Dynamic Policy Route, L - VRF Leaked,\n       G  - gRIBI, RC - Route Cache Route,\n       CL - CBF Leaked Route\n"

	func _show_ip_route(r: Array) -> String:
		## Only installed routes: one winner per prefix (or several of equal
		## cost), chosen by longest prefix then administrative distance.
		## With an address after it, only the entry that address would use.
		var want := String(r[0]) if r.size() == 1 and String(r[0]).is_valid_ip_address() else ""
		var chosen := {}
		if want != "":
			for e in Sim.rib(dev):
				if String(e["vrf"]) == "" and Net.same_net(want, String(e["prefix"]), int(e["plen"])) \
						and (chosen.is_empty() or int(e["plen"]) > int(chosen["plen"])):
					chosen = e
		var out := "VRF: default\n" + ROUTE_CODES + "\n"
		var any := false
		var default_rows := ""
		var rows := ""
		for e in Sim.rib(dev):
			if String(e["vrf"]) != "":
				continue  # a VRF's table is 'show ip route vrf <name>'
			if want != "" and e != chosen:
				continue
			any = true
			var pfx := "%s/%d" % [e["prefix"], int(e["plen"])]
			var code := "B E" if e["src"] == "B" else String(e["src"])
			var row := ""
			if e["src"] == "C":
				row = " %-8s %s is directly connected, %s\n" % [code, pfx, e["iface"].name]
			elif String(e["next_hop"]) == "null0":
				row = " %-8s %s is directly connected, Null0\n" % [code, pfx]
			else:
				row = " %-8s %s [%d/%d] via %s, %s\n" % [code, pfx, int(e["ad"]),
					int(e["cost"]) if e["src"] == "O" else 0, e["next_hop"], e["iface"].name]
			if int(e["plen"]) == 0 and e["src"] != "C":
				default_rows += row  # the default lives under its own header
			else:
				rows += row
		out += ("Gateway of last resort:\n%s\n" % default_rows) if default_rows != "" else "Gateway of last resort is not set\n\n"
		return out + rows

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
		var out := "                                                                              Address\nInterface         IP Address           Status       Protocol           MTU    Owner\n----------------- -------------------- ------------ -------------- ----------- -------\n"
		for i: Net.Iface in dev.ifaces:
			if i.name == "lo":
				continue
			# a switchport has no IP interface: only routed ports, SVIs and the management port appear
			if dev.type == "switch" and i.mode != "routed" and i.ips.is_empty() \
					and not i.name.begins_with("Management") and not i.name.begins_with("Vlan"):
				continue
			var ip := "unassigned"
			for cidr in i.ips:
				if not Net.is_v6(cidr):
					ip = String(cidr)
					break
			var up := i.enabled and Game.link_at(i) != null
			out += "%-17s %-20s %-12s %-14s %11d\n" % [i.name, ip, "admin down" if i.admin_down else ("up" if i.enabled else "down"),
				"up" if up else "down", i.mtu]
		return out

	func _write_mem(_r: Array) -> String:
		dev.startup = Game.device_config(dev)
		Game.save_config_version(dev)
		return "Copy completed successfully.\n"

	func _save_template(r: Array) -> String:
		if r.size() != 1:
			return "% Incomplete command\n"
		var err := Game.save_template(dev, r[0])
		return "Saved as template '%s'.\n" % r[0] if err == "" else "%% %s\n" % err

	func _apply_template(r: Array) -> String:
		if r.is_empty():
			return "% Incomplete command\n"
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
			return "% Incomplete command\n"
		dev.log_host = r[0]
		Game.device_log(dev, "logging destination set to %s" % r[0])
		return ""

	func _cfg_ntp(r: Array) -> String:
		if r.size() != 1 or not (r[0].is_valid_ip_address() or Net.is_v6(r[0])):
			return "% Incomplete command\n"
		dev.ntp_server = r[0]
		return ""

	func _show_route_for(r: Array) -> String:
		## Longest prefix wins, and this says which one won and by how much.
		if r.size() != 1 or not String(r[0]).is_valid_ip_address():
			return "% Incomplete command\n"
		var dst := String(r[0])
		var cands := Sim._all_routes(dev, dst)
		var winners := Sim._best_of(cands)
		if winners.is_empty():
			return "no route to %s: nothing this device knows covers that address\n" % dst
		var best: Dictionary = winners[0]
		var names := {"C": "connected", "S": "static", "O": "ospf", "B": "bgp"}
		var via: String = best["iface"].name if best["src"] == "C" else String(best["next_hop"])
		var out := "%s is reached by the %s route %s/%d (%s) [%d/%d], chosen because /%d is the longest match\n" \
			% [dst, names[best["src"]], best["prefix"], int(best["plen"]), via, int(best["ad"]),
			int(best["cost"]), int(best["plen"])]
		# a same-length rival lost on administrative distance: say so, that is
		# the part of the lookup people get wrong
		for c in cands:
			if int(c["plen"]) == int(best["plen"]) and int(c["ad"]) > int(best["ad"]):
				out += "  over the %s route via %s, because distance %d beats %d\n" % [names[c["src"]],
					c["next_hop"], int(best["ad"]), int(c["ad"])]
		return out

	func _show_if_status(_r: Array) -> String:
		## Port / Name / Status / Vlan / Duplex / Speed / Type / Flags / Encapsulation;
		## a notconnect port negotiates nothing, so it says auto twice
		var out := "%-10s %-10s %-12s %-8s %-6s %-6s %-15s %-5s %s\n" % ["Port", "Name", "Status", "Vlan", "Duplex", "Speed", "Type", "Flags", "Encapsulation"]
		var groups: Array = []
		for i: Net.Iface in dev.ifaces:
			if i.name == "lo":
				continue
			var peer := Game.effective_peer(i)
			var status := Game.iface_status_word(i)
			var up := status == "connected"
			var duplex_word := ("a-%s" % Sim.effective_duplex(i, peer) if i.duplex == "auto" else i.duplex) if up else ("auto" if i.duplex == "auto" else i.duplex)
			var vlan_word := "routed" if i.mode == "routed" or i.name.begins_with("Management") or i.name.begins_with("Vlan") or i.name.begins_with("Loopback") else ("trunk" if i.mode == "trunk" else str(i.untagged_vlan))
			var speed := Game.iface_speed(i)
			var speed_text := ("%dG" % (speed / 1000)) if speed >= 1000 else "%dM" % speed
			var speed_word := ("a-%s" % speed_text if i.duplex == "auto" else speed_text) if up else "auto"
			var kind := "10GBASE-SR" if speed >= 10000 else "10/100/1000"
			if i.name.begins_with("Vlan") or i.name.begins_with("Loopback"):
				kind = "N/A"
			var label := String(i.note.get("text", "")).substr(0, 10) if i.note is Dictionary else ""
			out += "%-10s %-10s %-12s %-8s %-6s %-6s %-15s %-5s %s\n" % [EOS._short(i.name), label, status, vlan_word,
				duplex_word, speed_word, kind, "", ""]
			if i.lag > 0 and i.lag not in groups:
				groups.append(i.lag)
		for g in groups:
			var members: Array = dev.ifaces.filter(func(i): return i.lag == g)
			var bundled: Array = members.filter(func(i): return Sim.lag_bundled(i))
			var total := 0
			for m: Net.Iface in bundled:
				total += Game.iface_speed(m)
			var first: Net.Iface = members[0]
			out += "%-10s %-10s %-12s %-8s %-6s %-6s %-15s %-5s %s\n" % ["Po%d" % g, "", "connected" if not bundled.is_empty() else "notconnect",
				"trunk" if first.mode == "trunk" else str(first.untagged_vlan), "full" if not bundled.is_empty() else "auto",
				(("%dG" % (total / 1000)) if total >= 1000 else "%dM" % total) if not bundled.is_empty() else "auto", "N/A", "", ""]
		return out

	func _show_transceiver(_r: Array) -> String:
		## numbers only, the way the real one prints them; copper ports are
		## simply absent. Whether a level is bad is for the LEARN panel.
		var out := "                                                        Temp    Voltage  Bias    Optical   Optical\nPort        Vendor      Type                                (C)     (V)      (mA)    Tx Power  Rx Power   Last Update\n----------- ----------- ----------------------------------- ------- -------- ------- --------- ---------- ------------\n"
		var any := false
		for i: Net.Iface in dev.ifaces:
			if Game.link_at(i) == null or i.name.begins_with("Management"):
				continue
			any = true
			out += "%-11s %-11s %-35s %-7.2f %-8.2f %-7.2f %-9.2f %-10.2f %d:%02d:%02d ago\n" % [EOS._short(i.name), "Arista",
				"10GBASE-SR" if Game.iface_speed(i) >= 10000 else "1000BASE-SX",
				38.29 + (i.rx_frames % 7) * 0.1, 3.27, 6.12, -2.53, i.light_dbm, 0, 0, (Game.cycle * 3) % 60]
		return out if any else ""

	func _show_tech_support(_r: Array) -> String:
		## What a vendor asks for, collected once, read-only, and safe to run
		## while everything is on fire.
		var out := "===== tech-support: %s (%s) at cycle %d =====\n" % [dev.name,
			Game.MODELS[dev.model]["label"], Game.cycle]
		out += "\n--- interfaces ---\n" + _show_interfaces([])
		out += "\n--- counters ---\n" + _show_counters([])
		if dev.type == "switch":
			out += "\n--- vlans ---\n" + _show_vlan([])
			out += "\n--- mac address-table ---\n" + _show_mac([])
			out += "\n--- spanning-tree ---\n" + _show_stp([])
		out += "\n--- arp ---\n" + _show_arp([])
		if dev.ip_forwarding:
			out += "\n--- ip route ---\n" + _show_ip_route([])
		out += "\n--- lldp neighbors ---\n" + _show_lldp([])
		out += "\n--- configuration ---\n%s\n" % ("running configuration matches startup"
			if not Game.config_dirty(dev) else "RUNNING CONFIGURATION IS NOT SAVED")
		out += "\n--- log (most recent last) ---\n"
		for line: String in dev.logs.slice(maxi(0, dev.logs.size() - 12)):
			out += line + "\n"
		out += "===== end tech-support =====\n"
		return out

	func _show_logging(_r: Array) -> String:
		## the EOS header, then the buffer in syslog shape
		var out := "Syslog logging: enabled\n    Buffer logging: level debugging\n    Console logging: level errors\n    Monitor logging: level errors\n    Synchronous logging: disabled\n    Trap logging: level informational\n"
		if dev.log_host != "":
			out += "        Logging to '%s' port 514 in VRF default via udp\n" % dev.log_host
		out += "    Sequence numbers: disabled\n    Syslog facility: local4\n    Hostname format: Hostname only\n    Repeat logging interval: disabled\n\nLog Buffer:\n"
		var n := 0
		for l in dev.logs.slice(maxi(0, dev.logs.size() - 15)):
			out += "Sep %2d %02d:%02d:%02d %s %s\n" % [1 + Game.cycle % 28, (Game.cycle * 3) % 24, (n * 7) % 60, (n * 13) % 60, dev.name, _syslog_words(String(l))]
			n += 1
		if dev.services.has("syslog"):
			var msgs: Array = dev.services["syslog"]["messages"]
			for m in msgs.slice(maxi(0, msgs.size() - 20)):
				out += "Sep %2d %02d:%02d:%02d %s Rsyslog: %%SYS-6-COLLECTED: %s\n" % [1 + Game.cycle % 28, (Game.cycle * 3) % 24, (n * 7) % 60, (n * 13) % 60, dev.name, m]
				n += 1
		return out

	func _syslog_words(line: String) -> String:
		## the agent and mnemonic EOS puts in front of a message
		var low := line.to_lower()
		if "link" in low or "port" in low and ("up" in low or "down" in low):
			return "Ebra: %%LINEPROTO-5-UPDOWN: %s" % line
		if "config" in low or "saved" in low or "written" in low:
			return "ConfigAgent: %%SYS-5-CONFIG_I: %s" % line
		if "spanning" in low or "stp" in low or "bpdu" in low:
			return "Stp: %%SPANTREE-6-INTERFACE_ADD: %s" % line
		if "lldp" in low or "neighbo" in low:
			return "Lldp: %%LLDP-4-NEIGHBOR_NEW: %s" % line
		if "reboot" in low or "restart" in low or "power" in low:
			return "SuperServer: %%SYS-4-RESTART: %s" % line
		return "SuperServer: %%SYS-6-LOGMSG_INFO: %s" % line

	func _show_clock(_r: Array) -> String:
		var believed := Game.cycle + dev.clock_skew
		return "%s Sep %2d %02d:%02d:%02d 2026\nTimezone: %s\nClock source: %s\n" % [
			["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][believed % 7], 1 + believed % 28, (believed * 3) % 24, (believed * 7) % 60, (believed * 11) % 60,
			String(dev.services.get("timezone", "UTC")), ("NTP server (%s)" % dev.ntp_server) if dev.ntp_server != "" else "local"]

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
			return "% Incomplete command\n"
		var idx := int(r[0]) - 1
		if idx < 0 or idx >= dev.versions.size():
			return "% no such version\n"
		Game.apply_device_config(dev, dev.versions[idx]["cfg"])
		mode = "priv"
		ctx_if = null
		ctx_ifs = []
		return "Rolled back to version %d.\n" % (idx + 1)

	func _reload(_r: Array) -> String:
		## EOS asks twice; this console cannot wait for an answer, so it shows
		## the questions with the answers a hurried operator gives, then goes
		var out := ""
		if Game.config_dirty(dev):
			out += "System configuration has been modified. Save? [yes/no/cancel/diff]:no\n"
		out += "Proceed with reload? [confirm]\n\nBroadcast message from root@%s\n\nThe system is going down for reboot NOW!\n" % dev.name
		Game.apply_device_config(dev, dev.startup)
		mode = "exec"
		ctx_if = null
		return out

	func _show_startup(_r: Array) -> String:
		## the saved configuration, rendered by the same code as show run:
		## the startup config is applied to the device for the length of one
		## call and the live state put back, so the text is exactly what a
		## reload would produce (ponytail: a snapshot renderer would avoid the swap)
		if dev.startup.is_empty():
			return "! Command: show startup-config\n! No startup-config was found.\n"
		var live := Game.device_config(dev)
		Game.apply_device_config(dev, dev.startup)
		var text := _show_run([]).replace("! Command: show running-config", "! Command: show startup-config")
		Game.apply_device_config(dev, live)
		return text

	const IF_ORDER := ["Port-Channel", "Ethernet", "Loopback", "Management", "Tunnel", "Vlan", "Vxlan", "wg"]

	func _if_rank(name: String) -> int:
		for k in IF_ORDER.size():
			if name.begins_with(IF_ORDER[k]):
				return k
		return IF_ORDER.size()

	func _show_run(_r: Array) -> String:
		## the sections in the order EOS prints them: identity, spanning tree,
		## VLANs, interfaces, then routing and the services
		var out := "! Command: show running-config\n! device: %s (%s, PacketOS EOS 0.3)\n!\nno aaa root\n!\n" % [
			dev.name, Game.MODELS[dev.model]["label"]]
		for user in dev.services.get("users", {}):
			var role := String(dev.services["users"][user].get("role", ""))
			out += "username %s privilege %d%s secret sha512 (hidden)\n" % [user, int(dev.services["users"][user].get("privilege", 1)),
				(" role %s" % role) if role != "" else ""]
		if not dev.services.get("users", {}).is_empty():
			out += "!\n"
		out += "transceiver qsfp default-mode 4x10G\n!\nservice routing protocols model multi-agent\n!\nhostname %s\n!\n" % dev.name
		if dev.resolver != "":
			out += "ip name-server vrf default %s\n!\n" % dev.resolver
		if String(dev.services.get("domain", "")) != "":
			out += "ip domain-name %s\n!\n" % dev.services["domain"]
		if dev.ntp_server != "":
			out += "ntp server %s\n!\n" % dev.ntp_server
		if dev.log_host != "":
			out += "logging host %s\n!\n" % dev.log_host
		if dev.snmp != "":
			out += "snmp-server community %s %s\n!\n" % [dev.snmp, String(dev.services.get("snmp_mode", "ro"))]
		if String(dev.services.get("timezone", "")) != "":
			out += "clock timezone %s\n!\n" % dev.services["timezone"]
		if String(dev.services.get("motd", "")) != "":
			out += "banner motd\n%s\nEOF\n!\n" % dev.services["motd"]
		if dev.type == "switch":
			out += "spanning-tree mode %s\n!\n" % ("mstp" if dev.stp_mode == "mst" else "rstp")
			if dev.stp_priority != 32768:
				out += "spanning-tree priority %d\n!\n" % dev.stp_priority
			if not dev.mst_instances.is_empty() or dev.services.has("mst"):
				out += "spanning-tree mst configuration\n"
				if String(dev.services.get("mst", {}).get("name", "")) != "":
					out += "   name %s\n" % dev.services["mst"]["name"]
				if int(dev.services.get("mst", {}).get("revision", 0)) != 0:
					out += "   revision %d\n" % int(dev.services["mst"]["revision"])
				for inst in dev.mst_instances:
					out += "   instance %s vlan %s\n" % [inst, ",".join(PackedStringArray(dev.mst_instances[inst].map(func(v): return str(v))))]
				out += "!\n"
		var vids := dev.vlans.keys()
		vids.sort()
		for vid in vids:
			if vid == 1:
				continue
			out += "vlan %d\n" % vid
			if String(dev.vlans[vid]) != "VLAN%04d" % vid:
				out += "   name %s\n" % dev.vlans[vid]
			out += "!\n"
		for vrf_name in dev.vrfs:
			out += "vrf instance %s\n!\n" % vrf_name
		var plists: Dictionary = dev.services.get("prefix_lists", {})
		var rmaps_text := ""
		for rm_name in dev.services.get("route_maps", {}):
			for seq in dev.services["route_maps"][rm_name]:
				var e: Dictionary = dev.services["route_maps"][rm_name][seq]
				rmaps_text += "route-map %s %s %s\n" % [rm_name, e.get("action", "permit"), seq]
				if e.has("prefix_list"):
					rmaps_text += "   match ip address prefix-list %s\n" % e["prefix_list"]
				if e.has("local_pref"):
					rmaps_text += "   set local-preference %d\n" % int(e["local_pref"])
				if e.has("prepend"):
					rmaps_text += "   set as-path prepend %s\n" % " ".join(PackedStringArray(_asn_repeat(int(e["prepend"]))))
				rmaps_text += "!\n"
		var acl_names: Array = []
		for rule in dev.acls:
			var nm := String(rule.get("list", ""))
			if nm != "" and nm not in acl_names:
				acl_names.append(nm)
		var acl_text := ""
		for nm in acl_names:
			acl_text += "ip access-list %s\n" % nm
			for rule in dev.acls:
				if String(rule.get("list", "")) == nm:
					acl_text += "   %d %s\n" % [int(rule.get("seq", 0)), CLI.acl_config_text(rule)]
			acl_text += "!\n"
		var acl_groups: Dictionary = dev.services.get("acl_groups", {})
		var nat_rules_cfg: Array = dev.services.get("nat", {}).get("rules", [])
		var ordered: Array = dev.ifaces.filter(func(i): return i.name != "lo")
		ordered.sort_custom(func(a, b): return _if_rank(a.name) < _if_rank(b.name) if _if_rank(a.name) != _if_rank(b.name) else dev.ifaces.find(a) < dev.ifaces.find(b))
		# the Port-Channels first, as EOS prints them: the settings a member
		# carries are the channel's, so they are printed once, on the channel
		var groups: Array = []
		for i: Net.Iface in dev.ifaces:
			if i.lag > 0 and i.lag not in groups:
				groups.append(i.lag)
		groups.sort()
		for g in groups:
			var first: Net.Iface = dev.ifaces.filter(func(i): return i.lag == g)[0]
			out += "interface Port-Channel%d\n" % g
			if first.note is Dictionary and String(first.note.get("text", "")) != "":
				out += "   description %s\n" % first.note["text"]
			if first.mode == "trunk":
				if first.untagged_vlan != 1:
					out += "   switchport trunk native vlan %d\n" % first.untagged_vlan
				if not first.tagged_vlans.is_empty():
					out += "   switchport trunk allowed vlan %s\n" % ",".join(first.tagged_vlans.map(func(v): return str(v)))
				out += "   switchport mode trunk\n"
			elif first.mode == "access" and first.untagged_vlan != 1:
				out += "   switchport access vlan %d\n" % first.untagged_vlan
			if first.mlag > 0:
				out += "   mlag %d\n" % first.mlag
			out += "!\n"
		for i: Net.Iface in ordered:
			out += "interface %s\n" % i.name
			if i.lag > 0:
				# a member: its switching lives on the channel
				if i.admin_down:
					out += "   shutdown\n"
				if i.mtu != 1500:
					out += "   mtu %d\n" % i.mtu
				out += "   channel-group %d mode %s\n!\n" % [i.lag, i.lag_mode]
				continue
			if i.note is Dictionary and String(i.note.get("text", "")) != "":
				out += "   description %s\n" % i.note["text"]
			if i.admin_down:
				out += "   shutdown\n"
			if i.mtu != 1500:
				out += "   mtu %d\n" % i.mtu
			if i.parent != "":
				out += "   encapsulation dot1q vlan %d\n" % i.dot1q
			if dev.type == "switch" and i.mode == "routed" and not i.name.begins_with("Management") \
					and not i.name.begins_with("Vlan") and not i.name.begins_with("Loopback"):
				out += "   no switchport\n"  # first: the address below depends on it
			if i.mode == "trunk":
				if i.untagged_vlan != 1:
					out += "   switchport trunk native vlan %d\n" % i.untagged_vlan
				if not i.tagged_vlans.is_empty():
					out += "   switchport trunk allowed vlan %s\n" % ",".join(i.tagged_vlans.map(func(v): return str(v)))
				out += "   switchport mode trunk\n"
			elif i.mode == "access" and i.untagged_vlan != 1:
				out += "   switchport access vlan %d\n" % i.untagged_vlan
			if i.port_security:
				out += "   switchport port-security\n"
			if i.pvlan == "isolated":
				out += "   switchport protected\n"
			if i.lag > 0:
				out += "   channel-group %d mode %s\n" % [i.lag, i.lag_mode]
			if i.mlag > 0:
				out += "   mlag %d\n" % i.mlag
			if i.vrf != "":
				out += "   vrf %s\n" % i.vrf
			for cidr in i.ips:
				out += "   %s address %s\n" % ["ipv6" if Net.is_v6(cidr) else "ip", cidr]
			if acl_groups.has(i.name):
				out += "   ip access-group %s in\n" % acl_groups[i.name]
			var eos_nat := false
			for rule in nat_rules_cfg:
				if bool(rule.get("eos", false)) and String(rule.get("iface", "")) == i.name:
					eos_nat = true
					if String(rule.get("kind", "")) == "overload":
						out += "   ip nat source dynamic access-list %s overload\n" % rule["list"]
					elif String(rule.get("kind", "")) == "static":
						out += "   ip nat source static %s %s\n" % [rule["inside"], rule["outside"]]
			if i.nat != "" and not eos_nat:
				out += "   ip nat %s\n" % i.nat
			var dhcp_on: Array = dev.services.get("dhcp", {}).get("on", [])
			if i.name in dhcp_on:
				out += "   dhcp server ipv4\n"
			if dev.ospf.get("costs", {}).has(i.name):
				out += "   ip ospf cost %d\n" % int(dev.ospf["costs"][i.name])
			if dev.ospf.get("priorities", {}).has(i.name):
				out += "   ip ospf priority %d\n" % int(dev.ospf["priorities"][i.name])
			if i.helper != "":
				out += "   ip helper-address %s\n" % i.helper
			if i.tunnel_src != "":
				out += "   tunnel source %s\n   tunnel destination %s\n" % [i.tunnel_src, i.tunnel_dst]
			for wp in i.wg_peers:
				out += "   wireguard peer %s endpoint %s allowed %s\n" % [wp.get("key", ""),
					wp.get("endpoint", ""), ",".join(PackedStringArray(wp.get("allowed", [])))]
			if not i.vrrp.is_empty():
				if int(i.vrrp.get("priority", 100)) != 100:
					out += "   vrrp %d priority-level %d\n" % [int(i.vrrp["group"]), int(i.vrrp["priority"])]
				out += "   vrrp %d ipv4 %s\n" % [int(i.vrrp["group"]), i.vrrp["vip"]]
				if not bool(i.vrrp.get("preempt", true)):
					out += "   no vrrp %d preempt\n" % int(i.vrrp["group"])
			if i.portfast:
				out += "   spanning-tree portfast\n"
			if i.bpduguard:
				out += "   spanning-tree bpduguard enable\n"
			if i.dhcp_trusted:
				out += "   ip dhcp snooping trust\n"
			if i.dot1x:
				out += "   dot1x pae authenticator\n   dot1x port-control auto\n"
			if i.storm_limit > 0:
				out += "   storm-control broadcast level %s\n" % (str(i.storm_limit / 10) if i.storm_limit % 10 == 0 else "%.1f" % (i.storm_limit / 10.0))
			if i.duplex != "auto":
				out += "   duplex %s\n" % i.duplex
			out += "!\n"
		if not dev.vtep.is_empty() and (dev.vtep.has("src_if") or not dev.vtep.get("map", {}).is_empty()):
			out += "interface Vxlan1\n"
			if String(dev.vtep.get("src_if", "")) != "":
				out += "   vxlan source-interface %s\n" % dev.vtep["src_if"]
			out += "   vxlan udp-port 4789\n"
			for v in dev.vtep.get("map", {}):
				out += "   vxlan vlan %d vni %d\n" % [int(v), int(dev.vtep["map"][v])]
			if not dev.vtep.get("peers", []).is_empty():
				out += "   vxlan flood vtep %s\n" % " ".join(PackedStringArray(dev.vtep["peers"]))
			out += "!\n"
		var mlag_text := ""
		if dev.mlag_peer != "" or dev.services.has("mlag"):
			var mc: Dictionary = dev.services.get("mlag", {})
			mlag_text += "mlag configuration\n"
			if String(mc.get("domain", "")) != "":
				mlag_text += "   domain-id %s\n" % mc["domain"]
			if String(mc.get("local_if", "")) != "":
				mlag_text += "   local-interface %s\n" % mc["local_if"]
			var peer_addr := String(mc.get("peer_addr", ""))
			if peer_addr == "" and dev.mlag_peer != "":
				for d in Game.all_devices():
					if d.name == dev.mlag_peer:
						peer_addr = CLI.first_ip_of(d)
			if peer_addr != "" and peer_addr != "0.0.0.0":
				mlag_text += "   peer-address %s\n" % peer_addr
			var pl := Sim.mlag_peerlink(dev)
			if String(mc.get("peer_link", "")) != "":
				mlag_text += "   peer-link %s\n" % mc["peer_link"]
			elif pl != null:
				mlag_text += "   peer-link %s\n" % ("Port-Channel%d" % pl.lag if pl.lag > 0 else pl.name)
			mlag_text += "!\n"
		var static_vids := dev.mac_static.keys()
		static_vids.sort()
		for svid in static_vids:
			for smac in dev.mac_static[svid]:
				out += "mac address-table static %s vlan %d interface %s\n" % [Net.mac_dotted(smac), svid, dev.mac_static[svid][smac]]
		if not static_vids.is_empty():
			out += "!\n"
		out += acl_text
		if dev.ip_forwarding:
			out += "ip routing\n!\n"
		for pl_name in plists:
			out += "ip prefix-list %s\n" % pl_name
			var seq := 10
			for pfx in plists[pl_name]:
				out += "   seq %d permit %s\n" % [seq, pfx]
				seq += 10
			out += "!\n"
		out += mlag_text
		for r in dev.static_routes:
			out += "ip route %s%s/%d %s%s\n" % [("vrf %s " % r["vrf"]) if String(r.get("vrf", "")) != "" else "", r["prefix"], int(r["plen"]), r["via"],
				"" if int(r.get("ad", 1)) == 1 else " %d" % int(r["ad"])]
		if not dev.static_routes.is_empty():
			out += "!\n"
		var pool: Dictionary = dev.services.get("dhcp", {})
		if not pool.is_empty() and String(pool.get("iface", "")) == "" and String(pool.get("start", "")) != "":
			# the EOS block, whichever spelling built it
			var pnet := Net.network_of("%s/%d" % [pool["start"], int(pool["plen"])])
			out += "dhcp server\n   subnet %s/%d\n      range %s %s\n" % [pnet["prefix"], int(pool["plen"]), pool["start"], pool["end"]]
			if String(pool.get("gw", "")) != "":
				out += "      default-gateway %s\n" % pool["gw"]
			if String(pool.get("dns", "")) != "":
				out += "      name-server %s\n" % pool["dns"]
			for ex in pool.get("excluded", []):
				out += "      reserved-address %s\n" % ex
			out += "!\n"
		if dev.stateful:
			out += "firewall stateful\n!\n"
		for rule in dev.acls:
			if String(rule.get("list", "")) == "":
				out += "acl %s\n!\n" % CLI.acl_config_text(rule)
		if dev.ip_forwarding and dev.type != "switch" and not bool(dev.services.get("proxy_arp", true)):
			out += "no ip proxy-arp\n!\n"
		var nat_cfg: Dictionary = dev.services.get("nat", {})
		for list_id in nat_cfg.get("acls", {}):
			for entry in nat_cfg["acls"][list_id]:
				var where := "any" if int(entry["plen"]) == 0 else ("host %s" % entry["net"] if int(entry["plen"]) == 32
					else "%s %s" % [entry["net"], Net.int_to_ip((~(0xFFFFFFFF << (32 - int(entry["plen"])))) & 0xFFFFFFFF)])
				out += "access-list %s %s %s\n" % [list_id, entry["action"], where]
		for rule in nat_cfg.get("rules", []):
			if bool(rule.get("eos", false)):
				continue  # printed under its interface
			if String(rule.get("kind", "")) == "overload":
				out += "ip nat inside source list %s interface %s overload\n" % [rule["list"], rule["iface"]]
			elif String(rule.get("kind", "")) == "static":
				out += "ip nat inside source static %s %s\n" % [rule["inside"], rule["outside"]]
		out += rmaps_text
		if not dev.bgp.is_empty() and dev.type in ["router", "switch"]:
			out += "router bgp %d\n" % int(dev.bgp["asn"])
			if String(dev.bgp.get("router_id", "")) != "":
				out += "   router-id %s\n" % dev.bgp["router_id"]
			for nb in dev.bgp["neighbors"]:
				out += "   neighbor %s remote-as %d\n" % [nb["ip"], int(nb["remote_as"])]
				if String(nb.get("description", "")) != "":
					out += "   neighbor %s description %s\n" % [nb["ip"], nb["description"]]
				for dir in ["in", "out"]:
					if nb.has("rmap_%s" % dir):
						out += "   neighbor %s route-map %s %s\n" % [nb["ip"], nb["rmap_%s" % dir], dir]
					elif nb.has("prefix_%s_name" % dir):
						out += "   neighbor %s prefix-list %s %s\n" % [nb["ip"], nb["prefix_%s_name" % dir], dir]
			for net in dev.bgp["networks"]:
				out += "   network %s\n" % net
			out += "!\n"
		if not dev.ospf.is_empty():
			out += "router ospf 1\n"
			if String(dev.ospf.get("router_id", "")) != "":
				out += "   router-id %s\n" % dev.ospf["router_id"]
			if int(dev.ospf.get("ref_bw", 100)) != 100:
				out += "   auto-cost reference-bandwidth %d\n" % int(dev.ospf["ref_bw"])
			for pif in dev.ospf.get("passive", []):
				out += "   passive-interface %s\n" % pif
			for net in dev.ospf["networks"]:
				out += "   network %s area %s\n" % [net, Sim.ospf_area(dev)]
			out += "   max-lsa 12000\n!\n"
		out += "end\n"
		return out

	## What '?' says next to each word, the way EOS explains itself
	const DESC := {
		"enable": "Turn on privileged commands", "disable": "Turn off privileged commands",
		"configure": "Enter configuration mode", "terminal": "Configure from the terminal",
		"show": "Display details of switch operation", "interfaces": "Interface status and configuration",
		"ip": "IP information", "ipv6": "IPv6 information", "route": "IP routing table", "arp": "ARP table",
		"vlan": "VLAN status and configuration", "mac": "MAC address information", "address-table": "MAC address table",
		"spanning-tree": "Spanning tree", "lldp": "LLDP information", "port-channel": "Port-Channel information",
		"running-config": "Current operating configuration", "startup-config": "Contents of startup configuration",
		"version": "System hardware and software status", "clock": "System clock", "logging": "System logging (syslog)",
		"write": "Write running configuration to memory", "memory": "Write to NV memory", "copy": "Copy from one file to another",
		"reload": "Halt and perform a cold restart", "ping": "Send echo messages", "traceroute": "Trace route to destination",
		"ssh": "Open a Secure Shell client connection", "exit": "Exit from the current mode", "end": "Return to exec mode",
		"hostname": "Set system's network name", "interface": "Select an interface to configure",
		"switchport": "Set switching mode characteristics", "mode": "Set the trunking mode", "access": "Set access mode characteristics",
		"trunk": "Set trunking characteristics", "allowed": "Set allowed VLAN list", "native": "Set native VLAN",
		"shutdown": "Shutdown the selected interface", "no": "Negate a command or set its defaults",
		"description": "Interface specific description", "mtu": "Set the interface Maximum Transmission Unit (MTU)",
		"channel-group": "Configure port channel", "router": "Enable a routing process", "ospf": "Open Shortest Path First (OSPF)",
		"bgp": "Border Gateway Protocol (BGP)", "neighbor": "Specify a neighbor router", "network": "Specify a network to announce",
		"name": "Assign a name to the VLAN", "vrrp": "Virtual Router Redundancy Protocol", "helper-address": "Specify a destination address for UDP broadcasts",
		"nat": "Network Address Translation", "dhcp": "Dynamic Host Configuration Protocol", "snooping": "DHCP snooping",
		"clear": "Reset functions", "counters": "Interface counters", "brief": "Brief summary", "status": "Interface line status",
		"summary": "Summary of neighbor status", "detail": "Detailed information", "do": "Run an exec command from configuration mode",
		"priority": "Bridge priority", "portfast": "Move directly to forwarding on link up", "bpduguard": "BPDU guard",
		"cost": "Interface cost", "area": "OSPF area ID", "remote-as": "Neighbor AS number", "router-id": "Router ID",
		"passive-interface": "Suppress routing updates on an interface", "host": "Specify a host", "server": "Specify a server",
		"community": "Set community string", "snmp-server": "Modify SNMP engine parameters", "ntp": "Configure NTP",
		"radius-server": "RADIUS server configuration", "aaa": "Authentication, authorization and accounting", "mlag": "Multi-chassis link aggregation",
		"vxlan": "VXLAN configuration", "vrf": "VRF configuration", "tunnel": "Tunnel configuration", "wireguard": "WireGuard configuration",
		"encapsulation": "Set encapsulation type", "dot1q": "IEEE 802.1Q VLAN", "duplex": "Configure duplex operation",
		"qos": "Quality of service", "storm-control": "Storm control", "port-security": "Port security", "dot1x": "IEEE 802.1X port authentication",
		"protected": "Protected port", "static": "Static entry", "inspection": "ARP inspection", "igmp": "IGMP snooping",
		"proxy-arp": "Proxy ARP", "capture": "Packet capture", "flows": "Forwarded conversations", "tech-support": "Show system information for tech support",
		"transceiver": "Transceiver diagnostics", "errors": "Error counters", "tunnels": "Tunnel status", "templates": "Saved configuration templates",
		"template": "Configuration template", "rollback": "Roll back to a saved configuration version", "versions": "Saved configuration versions",
		"diff": "Difference against the saved configuration", "config": "Configuration", "acl": "Access control list", "access-lists": "Access lists",
		"firewall": "Firewall behaviour", "stateful": "Stateful inspection", "permit": "Specify packets to forward", "deny": "Specify packets to reject",
		"routing": "Enable IP routing", "neighbors": "Neighbor table", "database": "Database summary", "bfd": "Bidirectional Forwarding Detection",
		"address": "IP address", "help": "Description of the interactive help system", "excluded-address": "Prevent DHCP from assigning certain addresses",
		"pool": "Configure DHCP address pools", "default-router": "Default routers", "dns-server": "DNS servers", "reference-bandwidth": "Reference bandwidth",
		"auto-cost": "Calculate OSPF interface cost according to bandwidth", "forwarding": "VRF forwarding",
		"nd": "Neighbor discovery", "ra": "Router advertisement", "mst": "Multiple spanning tree", "peer": "Peer configuration",
		"peer-link": "Peer link", "source": "Source address", "destination": "Destination address", "prefix": "Prefix",
		"roa": "Route origin authorisation", "virtual-server": "Virtual server", "ssid": "Wireless SSID", "nat64": "NAT64 translation",
		"trust": "Trusted port", "broadcast": "Broadcast storm control", "priority-queueing": "Priority queueing"}

	func describe(line: String) -> String:
		## the '?' help: one candidate per line with its description, and <cr>
		## when what is typed already runs
		var toks := Array(line.strip_edges().split(" ", false))
		var cands := complete(line)
		var out := ""
		var typed_complete := false
		if not line.ends_with(" ") and not toks.is_empty():
			toks.pop_back()
		for c in _cmds:
			if mode not in c["m"] or toks.size() < c["p"].size():
				continue
			var okc := true
			for k in c["p"].size():
				if not String(c["p"][k]).begins_with(toks[k]):
					okc = false
					break
			if okc:
				typed_complete = true
		for w in cands:
			out += "  %-24s %s\n" % [w, DESC.get(String(w), "")]
		if typed_complete and line.ends_with(" "):
			out += "  <cr>\n"
		return out if out != "" else "% Invalid input\n"
# ============================================================ Linux ==
