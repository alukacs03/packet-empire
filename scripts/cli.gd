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
			"dhcp":
				return dev.name + "(dhcp-config)#"
		return dev.name + ">"

	static func _short(ifname: String) -> String:
		return ifname.replace("Ethernet", "Et")

	# ---- command table: {m: modes, p: path tokens, h: handler(rest)->String, dyn: Callable|null}
	func _build_cmds() -> void:
		var EP := ["exec", "priv", "config", "if", "vlan", "router", "ospf", "dhcp"]  # show/ping work everywhere via 'do'-free shortcut
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
			{"m": EP, "p": ["show", "ip", "arp"], "h": _show_arp},
			{"m": ["config"], "p": ["mac", "address-table", "static"], "h": _mac_static},
			{"m": ["config"], "p": ["no", "mac", "address-table", "static"], "h": _no_mac_static},
			{"m": ["priv"], "p": ["clear", "mac", "address-table"], "h": func(_r):
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
			{"m": ["config"], "p": ["spanning-tree", "mst"], "h": _stp_mst},
			{"m": EP, "p": ["show", "ip", "route"], "h": _show_ip_route},
			{"m": EP, "p": ["show", "ip", "route", "for"], "h": _show_route_for},
			{"m": EP, "p": ["show", "ip", "interface", "brief"], "h": _show_ip_brief},
			{"m": ["priv", "config", "if", "vlan"], "p": ["show", "running-config"], "h": _show_run},
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
			{"m": ["config", "if", "vlan", "router", "ospf", "dhcp"], "p": ["interface"], "h": _cfg_interface, "dyn": _if_names},
			{"m": ["config", "if", "vlan", "router", "ospf", "dhcp"], "p": ["interface", "range"], "h": _cfg_if_range},
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
			{"m": ["config"], "p": ["acl", "permit"], "h": _cfg_acl.bind("permit")},
			{"m": ["config"], "p": ["acl", "deny"], "h": _cfg_acl.bind("deny")},
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
			{"m": ["router"], "p": ["roa"], "h": _bgp_roa},
			{"m": ["router"], "p": ["network"], "h": _bgp_network},
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
			{"m": ["config", "if", "vlan", "router", "ospf", "dhcp"], "p": ["end"], "h": func(_r): mode = "priv"; return ""},
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
		if mode in ["config", "if", "vlan", "router", "ospf", "dhcp"]:
			Challenge.note_change()  # a challenge counts what you changed, not what you typed
		# resolve with per-token prefix matching (Cisco-style abbreviation).
		# A global configuration command typed inside a sub-mode (interface,
		# router) is accepted and switches mode, exactly as IOS does.
		var modes: Array = [mode]
		if mode in ["if", "vlan", "router", "ospf", "dhcp"]:
			modes.append("config")
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
			"if", "vlan", "router", "ospf", "dhcp":
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
		## ping <ip> [size <bytes>] [repeat <n>], the Arista-style spelling
		var size := 64
		var repeat := 0
		var target := String(r[0]) if not r.is_empty() else ""
		var idx := 1
		while idx + 1 < r.size():
			match String(r[idx]):
				"size":
					size = int(String(r[idx + 1]))
				"repeat":
					repeat = int(String(r[idx + 1]))
				_:
					return "usage: ping <ip> [size <bytes>] [repeat <n>]\n"
			idx += 2
		if target == "" or idx != r.size():
			return "usage: ping <ip> [size <bytes>] [repeat <n>]\n"
		if repeat > 0:
			return CLI.fmt_ping_repeat(dev, target, repeat, size)
		return CLI.fmt_ping(dev, target, size)

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

	func _no_switchport(_r: Array) -> String:
		## a routed port: the L3 switch treats it as a router interface
		if dev.type != "switch":
			return "% switchport commands need a switch\n"
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
			return "% switchport commands need a switch\n"
		if ctx_if != null and ctx_if.mode == "routed":
			return "% %s is a routed port: 'switchport' first\n" % ctx_if.name
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

	func _sw_trunk_native(r: Array) -> String:
		## the VLAN this trunk sends and expects untagged; both ends must agree
		## or two VLANs quietly become one
		if dev.type != "switch":
			return "% switchport commands need a switch\n"
		if r.size() != 1 or not String(r[0]).is_valid_int() or int(r[0]) < 1 or int(r[0]) > 4094:
			return "usage: switchport trunk native vlan <vid>\n"
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
			return "% switchport commands need a switch\n"
		var usage := "usage: switchport trunk allowed vlan <10,20,30-35>|all|add <list>|remove <list>|except <list>\n"
		if r.size() == 1 and r[0] == "all":
			ctx_if.tagged_vlans = []
			Game.topology_changed.emit()
			return ""
		if r.size() == 1:
			var vids := EOS.parse_vlan_list(String(r[0]))
			if vids.is_empty():
				return usage
			ctx_if.tagged_vlans = vids
			Game.topology_changed.emit()
			return ""
		if r.size() != 2 or String(r[0]) not in ["add", "remove", "except"]:
			return usage
		var change := EOS.parse_vlan_list(String(r[1]))
		if change.is_empty():
			return usage
		match String(r[0]):
			"add":
				# 'all' is the empty list; adding to everything changes nothing
				if not ctx_if.tagged_vlans.is_empty():
					for v in change:
						if v not in ctx_if.tagged_vlans:
							ctx_if.tagged_vlans.append(v)
					ctx_if.tagged_vlans.sort()
			"remove":
				if ctx_if.tagged_vlans.is_empty():
					var everything: Array = dev.vlans.keys()
					everything.sort()
					ctx_if.tagged_vlans = everything
				for v in change:
					ctx_if.tagged_vlans.erase(v)
			"except":
				var keep: Array = []
				for v in dev.vlans.keys():
					if int(v) not in change:
						keep.append(int(v))
				keep.sort()
				ctx_if.tagged_vlans = keep
		Game.topology_changed.emit()
		return ""
		Game.topology_changed.emit()
		return ""

	func _if_ip(r: Array) -> String:
		if ctx_ifs.size() > 1:
			return _range_only("an address")
		if dev.type == "switch" and not ctx_if.name.begins_with("Management") \
				and not ctx_if.name.begins_with("Vlan") and ctx_if.mode != "routed":
			return "% a switchport carries no address: put it on an SVI (interface Vlan<n>), the Management1 port, or make this a routed port with 'no switchport'\n"
		r = CLI.fold_mask(r)
		if r.size() != 1:
			return "usage: ip address <a.b.c.d/len | a.b.c.d mask>\n"
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
		var mode := "on"
		if r.size() == 3 and String(r[1]) == "mode" and String(r[2]) in ["active", "passive", "on"]:
			mode = String(r[2])
			r = [r[0]]
		if r.size() == 1 and String(r[0]).is_valid_int() and int(r[0]) >= 1:
			return _each(func(i: Net.Iface) -> String:
				i.lag = int(r[0])
				i.lag_mode = mode
				return "")
		return "usage: channel-group <1-64> mode active|passive|on\n"

	func _show_lag(_r: Array) -> String:
		var groups := {}
		for i: Net.Iface in dev.ifaces:
			if i.lag > 0:
				if not groups.has(i.lag):
					groups[i.lag] = []
				groups[i.lag].append(i)
		if groups.is_empty():
			return "  (no port-channels: 'channel-group <n> mode active' on member interfaces)\n"
		var out := "Flags:  S - Layer2   U - in use   D - down   P - bundled in Po   I - individual/suspended\n"
		out += "%-6s %-14s %-9s %-28s %s\n" % ["Group", "Port-Channel", "Protocol", "Ports", "Peer"]
		var gids := groups.keys()
		gids.sort()
		for g in gids:
			var names: Array = []
			var peer := "-"
			var up := false
			var proto := "-"
			for i: Net.Iface in groups[g]:
				var bundled := Sim.lag_bundled(i)
				up = up or bundled
				if i.lag_mode != "on":
					proto = "LACP"
				names.append("%s(%s)" % [EOS._short(i.name), "P" if bundled else ("I" if i.enabled else "D")])
				var l := Game.link_at(i)
				if l:
					peer = l.other(i).dev.name
			out += "%-6d %-14s %-9s %-28s %s\n" % [g, "Po%d(%s)" % [g, "SU" if up else "SD"], proto,
				" ".join(PackedStringArray(names)), peer]
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
		if r.size() == 2 and String(r[0]).is_valid_int() and "preempt".begins_with(r[1]):
			if ctx_if.vrrp.is_empty():
				return "% set the virtual IP first: vrrp <group> ip <vip>\n"
			ctx_if.vrrp["preempt"] = true
			Game.topology_changed.emit()
			return ""
		return "usage: vrrp <group> ip <vip>  |  vrrp <group> priority <1-254>  |  [no] vrrp <group> preempt\n"

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
		var any := false
		for i: Net.Iface in dev.ifaces:
			if i.vrrp.is_empty():
				continue
			any = true
			var master := Sim.vrrp_master(i.vrrp["vip"], int(i.vrrp["group"]))
			var master_ip := "-"
			if master != null:
				for mi: Net.Iface in master.ifaces:
					if int(mi.vrrp.get("group", -1)) == int(i.vrrp["group"]) and not mi.ips.is_empty():
						master_ip = String(mi.ips[0]).split("/")[0]
			out += "VRRP Group %d on %s:\n  State is %s\n  Virtual IP address is %s\n  Virtual MAC address is %s\n  Advertisement interval is 1.000s\n  Preemption is %s\n  Priority is %d\n  Master router is %s%s\n\n" % [
				int(i.vrrp["group"]), i.name, "Master" if master == dev else "Backup", i.vrrp["vip"],
				Net.mac_dotted(Sim.vrrp_mac(int(i.vrrp["group"]))),
				"enabled" if bool(i.vrrp.get("preempt", true)) else "disabled", int(i.vrrp.get("priority", 100)),
				master_ip, " (local)" if master == dev else ""]
		return out if any else "  (no VRRP groups configured)\n"

	func _show_vrrp_brief(_r: Array) -> String:
		## the IOS one-liner per group
		var out := "%-11s %-4s %-4s %-6s %-4s %-4s %-7s %-16s %s\n" % ["Interface", "Grp", "Pri", "Time", "Own", "Pre", "State", "Master addr", "Group addr"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			if i.vrrp.is_empty():
				continue
			any = true
			var master := Sim.vrrp_master(i.vrrp["vip"], int(i.vrrp["group"]))
			var master_ip := "-"
			if master != null:
				for mi: Net.Iface in master.ifaces:
					if int(mi.vrrp.get("group", -1)) == int(i.vrrp["group"]) and not mi.ips.is_empty():
						master_ip = String(mi.ips[0]).split("/")[0]
			out += "%-11s %-4d %-4d %-6d %-4s %-4s %-7s %-16s %s\n" % [EOS._short(i.name), int(i.vrrp["group"]),
				int(i.vrrp.get("priority", 100)), 3609, " ", "Y" if bool(i.vrrp.get("preempt", true)) else " ",
				"Master" if master == dev else "Backup", master_ip, i.vrrp["vip"]]
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

	func _nat_cfg() -> Dictionary:
		if not dev.services.has("nat"):
			dev.services["nat"] = {"rules": [], "acls": {}}
		return dev.services["nat"]

	func _cfg_nat_source(r: Array) -> String:
		## ip nat inside source list <n> interface <if> overload
		## ip nat inside source static <inside> <outside>
		if dev.type == "switch":
			return "% NAT needs a router or firewall\n"
		var usage := "usage: ip nat inside source list <acl> interface <if> overload  |  ip nat inside source static <inside-ip> <outside-ip>\n"
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

	func _cfg_no_nat_source(_r: Array) -> String:
		_nat_cfg()["rules"] = []
		dev.nat_flows.clear()
		dev.nat_xlate.clear()
		Game.topology_changed.emit()
		return ""

	func _cfg_std_acl(r: Array) -> String:
		## access-list <n> permit|deny <net> <wildcard> | host <ip> | any
		var usage := "usage: access-list <1-99> permit|deny <network> <wildcard-mask> | host <ip> | any\n"
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
		var usage := "usage: acl %s [ip|tcp|udp|icmp] <src-cidr|any|host a.b.c.d> <dst-cidr|any|host a.b.c.d> [eq <port>] [established]\n" % action
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
		dev.acls.append(rule)
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
			return "  (no access list: nothing is filtered)\n"
		var out := "mode: %s\n" % ("stateful (return traffic auto-permitted)" if dev.stateful else "stateless")
		var n := 1
		for rule in dev.acls:
			out += "%2d  %s\n" % [n, CLI.acl_rule_text(rule)]
			n += 1
		return out + "    (first match wins; implicit deny any any at the end)\n"

	func _dhcp_svc() -> Dictionary:
		if not dev.services.has("dhcp"):
			dev.services["dhcp"] = {"iface": "", "start": "", "end": "", "plen": 24, "gw": "", "dns": "",
				"leases": {}, "since": {}, "excluded": [], "name": ""}
		return dev.services["dhcp"]

	func _cfg_dhcp_pool(r: Array) -> String:
		if not dev.ip_forwarding:
			return "% a DHCP pool lives on a router; a server runs dhcpd\n"
		if r.size() != 1:
			return "usage: ip dhcp pool <name>\n"
		var svc := _dhcp_svc()
		svc["name"] = String(r[0])
		mode = "dhcp"
		return ""

	func _dhcp_network(r: Array) -> String:
		## network <addr>/<len>  |  network <addr> <mask>
		r = CLI.fold_mask(r)
		if r.size() != 1 or not Net.valid_cidr(r[0]):
			return "usage: network <address> <mask>   (or <address>/<len>)\n"
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
			return "usage: %s <ip>\n" % ("default-router" if key == "gw" else "dns-server")
		_dhcp_svc()[key] = String(r[0])
		Game.topology_changed.emit()
		return ""

	func _cfg_dhcp_excluded(r: Array) -> String:
		## ip dhcp excluded-address <low> [<high>]
		if r.is_empty() or not String(r[0]).is_valid_ip_address() or (r.size() == 2 and not String(r[1]).is_valid_ip_address()) or r.size() > 2:
			return "usage: ip dhcp excluded-address <low> [<high>]\n"
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
			return "% OSPF runs on routers and firewalls\n"
		if r.size() > 1:
			return "usage: router ospf [process-id]\n"
		if dev.ospf.is_empty():
			dev.ospf = {"networks": []}
		mode = "ospf"
		return ""

	func _ospf_network(r: Array) -> String:
		# network <p/len> area <n>   |   network <addr> <wildcard> area <n>
		var usage := "usage: network <prefix/len> area <n>   (or network <address> <wildcard> area <n>)\n"
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
		return "usage: no network <prefix/len>\n"

	func _show_ospf(_r: Array) -> String:
		if dev.ospf.is_empty():
			return "% OSPF not running: 'router ospf' in config mode\n"
		var nbs := Sim.ospf_neighbors(dev)
		if nbs.is_empty():
			return "  (no neighbors: check network statements, areas and cables on both sides)\n"
		var out := "%-16s %-4s %-14s %-10s %-16s %s\n" % ["Neighbor ID", "Pri", "State", "Dead Time", "Address", "Interface"]
		for nb in nbs:
			var far: Net.NDevice = nb["dev"]
			var far_if: Net.Iface = null
			for fi: Net.Iface in far.ifaces:
				if fi.ips.any(func(c): return String(c).split("/")[0] == String(nb["via_ip"])):
					far_if = fi
			out += "%-16s %-4d %-14s %-10s %-16s %s\n" % [Sim.ospf_router_id(far),
				Sim.ospf_priority(far_if) if far_if else 1, Sim.ospf_neighbor_state(dev, nb),
				"00:00:%02d" % (31 + (Game.cycle * 7 + nbs.find(nb)) % 9), nb["via_ip"], EOS._short(nb["iface"].name)]
		return out

	func _show_ospf_interface(_r: Array) -> String:
		if dev.ospf.is_empty():
			return "% OSPF not running: 'router ospf' in config mode\n"
		var out := "Router ID %s, area %s, reference bandwidth %d Mbps\n" % [Sim.ospf_router_id(dev), Sim.ospf_area(dev),
			int(dev.ospf.get("ref_bw", 100))]
		for i: Net.Iface in Sim.ospf_covered_ifaces(dev):
			var roles := Sim.ospf_segment_roles(dev, i)
			var state := "P2P" if bool(roles.get("p2p", false)) else ("DR" if roles.get("dr") == dev
				else ("BDR" if roles.get("bdr") == dev else "DROTHER"))
			var nbrs := 0
			for nb in Sim.ospf_neighbors(dev):
				if nb["iface"] == i:
					nbrs += 1
			out += "%s is up, line protocol is %s\n  Internet Address %s, Area %s\n  Cost: %d, State %s, Priority %d%s\n  Neighbor Count is %d\n" % [
				i.name, "up" if i.enabled else "down", i.ips[0] if not i.ips.is_empty() else "-", Sim.ospf_area(dev),
				Sim.ospf_cost(i), state, Sim.ospf_priority(i),
				"  (passive)" if i.name in dev.ospf.get("passive", []) else "", nbrs]
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
			return "usage: router-id <a.b.c.d>\n"
		dev.ospf["router_id"] = String(r[0])
		Game.topology_changed.emit()
		return ""

	func _ospf_passive(r: Array, on: bool) -> String:
		if r.size() != 1:
			return "usage: [no] passive-interface <interface>\n"
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
			return "usage: auto-cost reference-bandwidth <Mbps>   (100 by default: 1G and 10G both cost 1 until you raise it)\n"
		dev.ospf["ref_bw"] = int(r[0])
		Game.topology_changed.emit()
		return ""

	func _if_ospf(table: String, r: Array, lo: int, hi: int) -> String:
		if dev.ospf.is_empty():
			return "% OSPF not running: 'router ospf' in config mode\n"
		if r.size() != 1 or not String(r[0]).is_valid_int() or int(r[0]) < lo or int(r[0]) > hi:
			return "usage: ip ospf %s <%d-%d>\n" % ["cost" if table == "costs" else "priority", lo, hi]
		if not dev.ospf.has(table):
			dev.ospf[table] = {}
		for i: Net.Iface in ctx_ifs:
			dev.ospf[table][i.name] = int(r[0])
		Game.topology_changed.emit()
		return ""

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

	func _show_bgp_table(_r: Array) -> String:
		## the table itself: every path, and which one the router picked
		if dev.bgp.is_empty():
			return "% BGP not running: 'router bgp <asn>' in config mode\n"
		var out := "BGP routing table information for VRF default\nRouter identifier %s, local AS number %d\n" % [
			CLI.first_ip_of(dev), int(dev.bgp["asn"])]
		out += "Origin codes: i - IGP, e - EGP, ? - incomplete\n"
		out += "    %-20s %-16s %-7s %-8s %-7s %s\n" % ["Network", "Next Hop", "Metric", "LocPref", "Weight", "Path"]
		var installed := {}
		for e in Sim.rib(dev):
			if e["src"] == "B":
				installed["%s/%d|%s" % [e["prefix"], int(e["plen"]), e["next_hop"]]] = true
		var any := false
		for net in dev.bgp.get("networks", []):
			any = true
			out += " *> %-20s %-16s %-7d %-8d %-7d %s\n" % [net, "0.0.0.0", 0, 100, 32768, "i"]
		for rt in Sim._bgp_learned(dev):
			any = true
			var pfx := "%s/%d" % [rt["prefix"], int(rt["plen"])]
			var path: Array = []
			for k in 1 + int(rt.get("prepend", 0)):
				path.append(str(int(rt.get("asn", 0))))
			out += " %s %-20s %-16s %-7d %-8d %-7d %s i\n" % ["*>" if installed.has("%s|%s" % [pfx, rt["via"]]) else "* ",
				pfx, rt["via"], 0, int(rt.get("pref", 100)), 0, " ".join(PackedStringArray(path))]
		return out if any else out + "  (no prefixes: no session is established)\n"

	func _show_bgp(_r: Array) -> String:
		if dev.bgp.is_empty():
			return "% BGP not running: 'router bgp <asn>' in config mode\n"
		var out := "BGP summary information for VRF default\nRouter identifier %s, local AS number %d\n" % [
			CLI.first_ip_of(dev), int(dev.bgp["asn"])]
		out += "  %-16s %-2s %-6s %-8s %-8s %-4s %-5s %-9s %-7s %s\n" % ["Neighbor", "V", "AS", "MsgRcvd", "MsgSent", "InQ", "OutQ", "Up/Down", "State", "PfxRcd"]
		if dev.bgp["neighbors"].is_empty():
			out += "  (no neighbors configured)\n"
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
			out += "  %-16s %-2d %-6d %-8d %-8d %-4d %-5d %-9s %-7s %s\n" % [nb["ip"], 4, int(nb["remote_as"]),
				msgs, msgs + 1, 0, 0, ("00:%02d:%02d" % [(Game.cycle * 3) % 60, (Game.cycle * 7) % 60]) if up else "never",
				st, str(received) if up else "0"]
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
		# ip route <prefix/len | prefix mask> <next-hop> [<distance>] [vrf <name>]
		var vrf := ""
		if r.size() >= 2 and String(r[r.size() - 2]) == "vrf":
			vrf = String(r[r.size() - 1])
			r = r.slice(0, r.size() - 2)
		r = CLI.fold_mask(r)
		var ad := 1
		if r.size() == 3 and String(r[2]).is_valid_int():
			ad = clampi(int(r[2]), 1, 255)
			r = [r[0], r[1]]
		if r.size() == 2 and Net.valid_cidr(r[0]):
			var parts := String(r[0]).split("/")
			if Game.add_static_route(dev, parts[0], int(parts[1]), r[1], vrf, ad):
				return ""
		return "usage: ip route <prefix/len | prefix mask> <next-hop> [distance] [vrf <name>]\n"

	func _cfg_no_ip_route(r: Array) -> String:
		r = CLI.fold_mask(r)
		if r.size() >= 1 and Net.valid_cidr(r[0]):
			var parts := String(r[0]).split("/")
			Game.remove_static_route(dev, parts[0], int(parts[1]))
			return ""
		return "usage: no ip route <prefix/len>\n"

	# ---- show ----

	func _show_version(_r: Array) -> String:
		return "PacketOS EOS 0.3\nHardware: %s (%s), %d interfaces\n" % [dev.name, dev.type, dev.ifaces.size()]

	func _show_int_trunk(_r: Array) -> String:
		## the two things a trunk mismatch is diagnosed from: which ports are
		## trunking, and which VLANs each of them will actually carry
		var trunks: Array = []
		for i: Net.Iface in dev.ifaces:
			if i.mode == "trunk":
				trunks.append(i)
		if trunks.is_empty():
			return "(no trunking interfaces: 'switchport mode trunk' makes one)\n"
		var out := "%-11s %-8s %-13s %-12s %s\n" % ["Port", "Mode", "Encapsulation", "Status", "Native vlan"]
		for i: Net.Iface in trunks:
			var status := "not-trunking" if not i.enabled or Game.peer_label(i) == "" else "trunking"
			out += "%-11s %-8s %-13s %-12s %d\n" % [i.name, "on", "802.1q", status, i.untagged_vlan]
		out += "\n%-11s %s\n" % ["Port", "Vlans allowed on trunk"]
		for i: Net.Iface in trunks:
			out += "%-11s %s\n" % [i.name, "1-4094" if i.tagged_vlans.is_empty()
				else ",".join(i.tagged_vlans.map(func(v): return str(v)))]
		return out

	func _show_interfaces(r: Array) -> String:
		## the block form real gear prints: the "is up, line protocol is up"
		## line CCNA people are quizzed on, then hardware, address, duplex,
		## speed and the counters that tell a grey failure from a good link
		var only: Net.Iface = _find_iface(String(r[0])) if r.size() >= 1 else null
		if r.size() >= 1 and only == null:
			return "% no interface %s\n" % r[0]
		var out := ""
		for i: Net.Iface in dev.ifaces:
			if only != null and i != only:
				continue
			var word := Game.iface_status_word(i)
			var line1 := ""
			match word:
				"connected": line1 = "up, line protocol is up (connected)"
				"disabled": line1 = "administratively down, line protocol is down (disabled)"
				"err-disabled": line1 = "down, line protocol is down (errdisabled)"
				_: line1 = "down, line protocol is notpresent (notconnect)"
			out += "%s is %s\n" % [i.name, line1]
			out += "  Hardware is Ethernet, address is %s\n" % Net.mac_dotted(i.mac)
			for cidr in i.ips:
				out += "  Internet address is %s\n" % cidr
			var peer := Game.effective_peer(i)
			var duplex := Sim.effective_duplex(i, peer) if peer != null and i.duplex == "auto" else i.duplex
			var speed := Game.iface_speed(i)
			out += "  %s-duplex, %s, auto negotiation: %s\n" % [duplex.capitalize() if duplex != "auto" else "Full",
				("%dGb/s" % (speed / 1000)) if speed >= 1000 else "%dMb/s" % speed, "on" if i.duplex == "auto" else "off"]
			out += "  MTU %d bytes\n" % i.mtu
			out += "     %d packets input, %d input errors, %d CRC, %d giants\n" % [i.rx_frames, i.rx_errors, i.rx_crc, i.rx_giants]
			out += "     %d packets output, %d output drops, %d late collisions\n" % [i.tx_frames, i.out_drops, i.collisions]
		return out

	func _show_vlan(_r: Array) -> String:
		if dev.type != "switch":
			return "% no VLAN database on this device\n"
		## access ports only, every one spelled out: trunk membership is what
		## 'show interfaces trunk' is for
		var out := "%-5s %-32s %-9s %s\n%s %s %s %s\n" % ["VLAN", "Name", "Status", "Ports",
			"-".repeat(5), "-".repeat(32), "-".repeat(9), "-".repeat(31)]
		var vids := dev.vlans.keys()
		vids.sort()
		for vid in vids:
			var ports: Array = []
			for i: Net.Iface in dev.ifaces:
				if i.mode == "access" and i.untagged_vlan == vid and not i.name.begins_with("Management"):
					ports.append(EOS._short(i.name))
			out += "%-5d %-32s %-9s %s\n" % [vid, dev.vlans[vid], "active", ", ".join(PackedStringArray(ports))]
		return out

	func _show_mac(_r: Array) -> String:
		var out := "%-6s %-18s %-8s %s\n" % ["Vlan", "Mac Address", "Type", "Port"]
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
				out += "%-6d %-18s %-8s %s\n" % [vlan, Net.mac_dotted(mac), "STATIC", EOS._short(String(dev.mac_static[vlan][mac]))]
			for mac in dev.mac_table.get(vlan, {}):
				if dev.mac_static.get(vlan, {}).has(mac):
					continue
				rows += 1
				out += "%-6d %-18s %-8s %s\n" % [vlan, Net.mac_dotted(mac), "DYNAMIC", EOS._short(dev.mac_table[vlan][mac].name)]
		return out if rows > 0 else "  (empty: send some traffic first)\n"

	func _mac_static(r: Array) -> String:
		## mac address-table static <mac> vlan <vid> interface <port>
		if dev.type != "switch":
			return "% static MAC entries need a switch\n"
		if r.size() != 5 or String(r[1]) != "vlan" or String(r[3]) != "interface" \
				or not String(r[2]).is_valid_int():
			return "usage: mac address-table static <mac> vlan <vid> interface <port>\n"
		var port := _find_iface(String(r[4]))
		if port == null:
			return "% no such interface\n"
		var vid := int(r[2])
		if not dev.mac_static.has(vid):
			dev.mac_static[vid] = {}
		dev.mac_static[vid][Net.mac_colon(String(r[0]))] = port.name  # dotted or colon in; the simulation spells MACs upper-case colon
		Game.topology_changed.emit()
		return ""

	func _no_mac_static(r: Array) -> String:
		if r.size() < 3 or String(r[1]) != "vlan" or not String(r[2]).is_valid_int():
			return "usage: no mac address-table static <mac> vlan <vid>\n"
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
		return "\n".join(PackedStringArray(dev.capture.slice(-20))) + "\n"

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
		return "usage: aaa authentication login radius <ip> key <secret> [local]\n       aaa authentication login local\n"

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
			return "% spanning tree runs on switches\n"
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
		if int(r[0]) < 0 or int(r[0]) > 61440 or int(r[0]) % 4096 != 0:
			return "% Bridge Priority must be in increments of 4096 (0, 4096, 8192 ... 61440)\n"
		dev.stp_priority = int(r[0])
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
		out += "Bridge ID:   priority %d  address %s\n" % [dev.stp_priority, dev.ifaces[0].mac if not dev.ifaces.is_empty() else "-"]
		if root and root != dev:
			out += "Root ID:     priority %d  address %s\n" % [root.stp_priority, root.ifaces[0].mac if not root.ifaces.is_empty() else "-"]
		out += "%-11s %-11s %-12s %-8s %-6s %s\n" % ["Port", "Role", "State", "Cost", "Type", "Instances"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			var l := Game.link_at(i)
			if l == null or i.name.begins_with("Management"):
				continue
			any = true
			var per: Array = []
			for inst2 in Sim.mst_instances():
				per.append("%s:%s" % [inst2,
					"disc" if Sim._stp_blocked_inst.get(inst2, {}).has(i) else "fwd"])
			var role := Sim.stp_role(i) if i.enabled else "disabled"
			var state := "discarding" if role in ["alternate", "disabled"] else "forwarding"
			out += "%-11s %-11s %-12s %-8d %-6s %s\n" % [EOS._short(i.name), role, state, Sim.stp_port_cost(i),
				"Edge" if i.portfast else "P2p", " ".join(PackedStringArray(per))]
		return out if any else out + "  (no cabled ports)\n"

	func _vtep() -> Dictionary:
		if dev.vtep.is_empty():
			dev.vtep = {"src": "", "peers": [], "map": {}, "evpn": false}
		return dev.vtep

	func _cfg_vxlan_source(r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_ip_address():
			return "% usage: vxlan source <this switch's own address>\n"
		_vtep()["src"] = String(r[0])
		Game.topology_changed.emit()
		return ""

	func _cfg_vxlan_vlan(r: Array) -> String:
		# vxlan vlan <id> vni <id>
		if r.size() != 3 or String(r[1]) != "vni" or not String(r[0]).is_valid_int() \
				or not String(r[2]).is_valid_int():
			return "% usage: vxlan vlan <vlan-id> vni <vni>\n"
		if not dev.vlans.has(int(r[0])):
			return "%% vlan %s is not on this switch\n" % r[0]
		_vtep()["map"][int(r[0])] = int(r[2])
		Game.topology_changed.emit()
		return ""

	func _cfg_vxlan_peer(r: Array) -> String:
		if r.size() != 1 or not String(r[0]).is_valid_ip_address():
			return "% usage: vxlan peer <remote vtep address>\n"
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
			return "% usage: nat64 prefix <ipv6-prefix::> pool <ipv4-address>\n"
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
		# input errors and receive light are where a grey failure shows itself
		var out := "%-11s %12s %12s %10s %9s\n" % ["Port", "InFrames", "OutFrames",
			"InErrors", "Rx(dBm)"]
		for i: Net.Iface in dev.ifaces:
			out += "%-11s %12d %12d %10d %9.1f\n" % [EOS._short(i.name), i.rx_frames,
				i.tx_frames, i.rx_errors, i.light_dbm]
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
		## the read that separates the cable from the configuration: CRCs are
		## the wire, giants are an MTU, drops are a full pipe, collisions a duplex
		var out := "%-11s %8s %8s %8s %10s %10s\n" % ["Port", "InErrors", "CRC", "Giants", "OutDrops", "Collisions"]
		for i: Net.Iface in dev.ifaces:
			out += "%-11s %8d %8d %8d %10d %10d\n" % [EOS._short(i.name), i.rx_errors, i.rx_crc,
				i.rx_giants, i.out_drops, i.collisions]
		return out

	func _if_duplex(r: Array) -> String:
		if r.size() != 1 or String(r[0]) not in ["auto", "full", "half"]:
			return "usage: duplex auto|full|half\n"
		return _each(func(i: Net.Iface) -> String:
			i.duplex = String(r[0])
			return "")

	func _show_lldp(_r: Array) -> String:
		var out := "%-11s %-14s %s\n" % ["Port", "Neighbor", "Neighbor Port"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			var peer := Game.effective_peer(i)
			if peer != null:
				any = true
				# LLDP hears the device at the far end, not the panel in between
				out += "%-11s %-14s %s\n" % [EOS._short(i.name), peer.dev.name, EOS._short(peer.name)]
		return out if any else "  (no neighbors detected)\n"

	func _show_arp(_r: Array) -> String:
		if dev.arp.is_empty():
			return "  (empty)\n"
		var out := "%-16s %-10s %-18s %-6s %s\n" % ["Address", "Age (min)", "Hardware Addr", "Type", "Interface"]
		for ip in dev.arp:
			var age := Game.cycle - int(dev.arp_seen.get(ip, Game.cycle))
			out += "%-16s %-10s %-18s %-6s %s\n" % [ip, "-" if age <= 0 else str(age), Net.mac_dotted(String(dev.arp[ip])), "ARPA",
				CLI.arp_iface_name(dev, String(ip))]
		return out

	func _show_ip_route(_r: Array) -> String:
		## Only installed routes: one winner per prefix (or several of equal
		## cost), chosen by longest prefix then administrative distance.
		var out := "Codes: C - connected, S - static, O - OSPF, B - BGP\n"
		var any := false
		var gateway := ""
		var rows := ""
		for e in Sim.rib(dev):
			if String(e["vrf"]) != "":
				continue  # a VRF's table is 'show ip route vrf <name>'
			any = true
			var pfx := "%s/%d" % [e["prefix"], int(e["plen"])]
			if int(e["plen"]) == 0 and gateway == "" and e["src"] != "C":
				gateway = String(e["next_hop"])
			if e["src"] == "C":
				rows += "%-7s%s is directly connected, %s\n" % [e["src"], pfx, EOS._short(e["iface"].name)]
			elif String(e["next_hop"]) == "null0":
				rows += "%-7s%s is directly connected, Null0\n" % [e["src"], pfx]
			else:
				rows += "%-7s%s [%d/%d] via %s, %s\n" % [e["src"], pfx, int(e["ad"]),
					int(e["cost"]) if e["src"] == "O" else 0, e["next_hop"], EOS._short(e["iface"].name)]
		out += ("Gateway of last resort is %s to network 0.0.0.0\n\n" % gateway) if gateway != "" else "Gateway of last resort is not set\n\n"
		return out + rows if any else out + "  (no routes: configure ip addresses)\n"

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

	func _show_route_for(r: Array) -> String:
		## Longest prefix wins, and this says which one won and by how much.
		if r.size() != 1 or not String(r[0]).is_valid_ip_address():
			return "usage: show ip route for <address>\n"
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
		## One line per port, in the columns people scan a switch by. The
		## neighbour lives in show lldp neighbors, the errors in show interfaces.
		var out := "%-11s %-12s %-12s %-8s %-7s %-7s %s\n" % ["Port", "Name", "Status", "Vlan", "Duplex", "Speed", "Type"]
		for i: Net.Iface in dev.ifaces:
			var peer := Game.effective_peer(i)
			var status := Game.iface_status_word(i)
			var duplex_word := "a-%s" % Sim.effective_duplex(i, peer) if peer != null and i.duplex == "auto" else i.duplex
			var vlan_word := "routed" if i.mode == "routed" else ("trunk" if i.mode == "trunk" else str(i.untagged_vlan))
			var speed := Game.iface_speed(i)
			var speed_word := ("%dG" % (speed / 1000)) if speed >= 1000 else "%dM" % speed
			var kind := "10GBASE-SR" if speed >= 10000 else ("1000BASE-T" if speed >= 1000 else "100BASE-T")
			var label := String(i.note.get("text", "")).substr(0, 12) if i.note is Dictionary else ""
			out += "%-11s %-12s %-12s %-8s %-7s %-7s %s\n" % [EOS._short(i.name), label, status, vlan_word,
				duplex_word, speed_word, kind]
		return out

	func _show_transceiver(_r: Array) -> String:
		## The optic, and whether its receive level is where it should be.
		var out := "%-11s %-9s %-9s %s\n" % ["Port", "Rx(dBm)", "State", "Note"]
		var any := false
		for i: Net.Iface in dev.ifaces:
			if Game.link_at(i) == null or i.name.begins_with("Management"):
				continue
			any = true
			var state := "ok"
			var note := ""
			if i.light_dbm < -14.0:
				state = "LOW"
				note = "receive level is falling: a contaminated or dying optic looks like this"
			elif i.rx_errors > 0:
				note = "%d input error(s) since the counters were cleared" % i.rx_errors
			out += "%-11s %-9.1f %-9s %s\n" % [EOS._short(i.name), i.light_dbm, state, note]
		return out if any else "  (no cabled ports on this device)\n"

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
		var out := "! Command: show running-config\n! device: %s (%s, PacketOS EOS 0.3)\n!\nhostname %s\n!\n" % [
			dev.name, Game.MODELS[dev.model]["label"], dev.name]
		var vids := dev.vlans.keys()
		vids.sort()
		for vid in vids:
			if vid == 1:
				continue
			out += "vlan %d\n   name %s\n!\n" % [vid, dev.vlans[vid]]
		var static_vids := dev.mac_static.keys()
		static_vids.sort()
		for svid in static_vids:
			for smac in dev.mac_static[svid]:
				out += "mac address-table static %s vlan %d interface %s\n" % [Net.mac_dotted(smac), svid, dev.mac_static[svid][smac]]
		var pool: Dictionary = dev.services.get("dhcp", {})
		if not pool.is_empty() and String(pool.get("iface", "")) == "" and String(pool.get("start", "")) != "":
			for ex in pool.get("excluded", []):
				out += "ip dhcp excluded-address %s\n" % ex
			out += "ip dhcp pool %s\n   network %s/%d\n" % [pool.get("name", "LAN"),
				Net.network_of("%s/%d" % [pool["start"], int(pool["plen"])])["prefix"], int(pool["plen"])]
			if String(pool.get("gw", "")) != "":
				out += "   default-router %s\n" % pool["gw"]
			if String(pool.get("dns", "")) != "":
				out += "   dns-server %s\n" % pool["dns"]
			out += "!\n"
		for r in dev.static_routes:
			out += "ip route %s/%d %s%s\n!\n" % [r["prefix"], int(r["plen"]), r["via"],
				"" if int(r.get("ad", 1)) == 1 else " %d" % int(r["ad"])]
		if dev.stateful:
			out += "firewall stateful\n!\n"
		for rule in dev.acls:
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
			if String(rule.get("kind", "")) == "overload":
				out += "ip nat inside source list %s interface %s overload\n" % [rule["list"], rule["iface"]]
			elif String(rule.get("kind", "")) == "static":
				out += "ip nat inside source static %s %s\n" % [rule["inside"], rule["outside"]]
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
			if dev.type == "switch" and i.mode == "routed" and not i.name.begins_with("Management") and not i.name.begins_with("Vlan"):
				out += "   no switchport\n"  # first: the address below depends on it
			if i.parent != "":
				out += "   encapsulation dot1q %d\n" % i.dot1q
			if i.tunnel_src != "":
				out += "   tunnel source %s\n   tunnel destination %s\n" % [i.tunnel_src, i.tunnel_dst]
			for wp in i.wg_peers:
				out += "   wireguard peer %s endpoint %s allowed %s\n" % [wp.get("key", ""),
					wp.get("endpoint", ""), ",".join(PackedStringArray(wp.get("allowed", [])))]
			if i.mode == "trunk":
				out += "   switchport mode trunk\n"
				if i.untagged_vlan != 1:
					out += "   switchport trunk native vlan %d\n" % i.untagged_vlan
				if not i.tagged_vlans.is_empty():
					out += "   switchport trunk allowed vlan %s\n" % ",".join(i.tagged_vlans.map(func(v): return str(v)))
			elif i.mode == "access" and i.untagged_vlan != 1:
				out += "   switchport access vlan %d\n" % i.untagged_vlan
			for cidr in i.ips:
				out += "   ip address %s\n" % cidr
			if i.nat != "":
				out += "   ip nat %s\n" % i.nat
			if dev.ospf.get("costs", {}).has(i.name):
				out += "   ip ospf cost %d\n" % int(dev.ospf["costs"][i.name])
			if dev.ospf.get("priorities", {}).has(i.name):
				out += "   ip ospf priority %d\n" % int(dev.ospf["priorities"][i.name])
			if i.helper != "":
				out += "   ip helper-address %s\n" % i.helper
			if not i.vrrp.is_empty():
				out += "   vrrp %d ip %s\n" % [int(i.vrrp["group"]), i.vrrp["vip"]]
				if not bool(i.vrrp.get("preempt", true)):
					out += "   no vrrp %d preempt\n" % int(i.vrrp["group"])
				if int(i.vrrp.get("priority", 100)) != 100:
					out += "   vrrp %d priority %d\n" % [int(i.vrrp["group"]), int(i.vrrp["priority"])]
			if i.lag > 0:
				out += "   channel-group %d mode %s\n" % [i.lag, i.lag_mode]
			if i.port_security:
				out += "   switchport port-security\n"
			if i.portfast:
				out += "   spanning-tree portfast\n"
			if i.bpduguard:
				out += "   spanning-tree bpduguard enable\n"
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
			if i.duplex != "auto":
				out += "   duplex %s\n" % i.duplex
			if i.admin_down:
				out += "   shutdown\n"
			out += "!\n"
		out += "end\n"
		return out

# ============================================================ Linux ==
