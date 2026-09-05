class_name ROS
extends CLI.Session
## MikroTik RouterOS 7-style CLI for PacketTik gear: /path add|set|remove|print
## with key=value parameters and [find key=value] selectors. Paths, parameter
## names and print shapes follow the real thing, so what is learned here is
## what a real CHR expects. Same Game state as everything else.

const BRIDGE := "bridge1"  # every PacketTik switch runs one VLAN-filtering bridge

func banner() -> String:
	return "PacketTik RouterOS 7 %s: try '/interface print', '/ping <ip>', 'help'\n" % dev.name

func prompt() -> String:
	return "[admin@%s] >" % dev.name

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
	## RouterOS names a VLAN interface itself (vlan60); the model names it
	## after its parent (ether1.60). Print the RouterOS name.
	if i.parent != "":
		return "vlan%d" % i.dot1q
	return i.name

func _itype(i: Net.Iface) -> String:
	if i.parent != "":
		return "vlan"
	if i.name.begins_with("wg"):
		return "wireguard"
	if i.lag > 0:
		return "bond"
	return "ether"

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
	if p.has("interface") and _iface(String(p["interface"])) != null:
		return _iface(String(p["interface"]))
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
			return "failure: no such interface %s\n" % nm
		if i.mode != "trunk":
			i.mode = "trunk"
			i.tagged_vlans = [vid]  # a tagged port carries exactly what is listed
		elif not i.tagged_vlans.is_empty() and vid not in i.tagged_vlans:
			i.tagged_vlans.append(vid)
			i.tagged_vlans.sort()
	for nm in untagged.split(",", false):
		var i := _iface(nm)
		if i == null:
			return "failure: no such interface %s\n" % nm
		if i.mode == "trunk":
			i.untagged_vlan = vid  # a trunk's untagged VLAN is its pvid
		else:
			Game.set_access_vlan(i, vid)
	return ""

func exec(line: String) -> String:
	var pipe := line.find("|")
	if pipe > 0:
		var tail := line.substr(pipe + 1).strip_edges().split(" ", false)
		if tail.size() >= 2 and String(tail[0]) in ["include", "i", "grep"]:
			return CLI.filter_output(exec(line.substr(0, pipe).strip_edges()),
				" ".join(PackedStringArray(Array(tail).slice(1))))
	# [find key=value] selects an item: the key=value is all the model needs
	var cleaned := line.replace("[", " ").replace("]", " ").strip_edges().trim_prefix("/")
	var toks := Array(cleaned.split(" ", false))
	while toks.has("find"):
		toks.erase("find")
	if toks.is_empty():
		return ""
	var path := ""
	var args: Array = []
	for t in toks:
		if "=" in String(t) or (path != "" and not _is_path_word(path + " " + String(t))):
			args.append(t)
		else:
			path += (" " if path != "" else "") + String(t)
	var p := _params(args)
	match path:
		"help":
			return _help()
		"export":
			return _export()
		"ping":
			if args.size() >= 1:
				var ping_size := int(p.get("size", 64)) \
					if String(p.get("size", "64")).is_valid_int() else 64
				# count= is how RouterOS spells "keep going and tell me the loss"
				if String(p.get("count", "")).is_valid_int():
					return CLI.fmt_ping_repeat(dev, args[0], int(p["count"]), ping_size)
				return CLI.fmt_ping(dev, args[0], ping_size)
			return "usage: /ping <ip> [size=<bytes>] [count=<n>]\n"
		"tool traceroute":
			return CLI.fmt_traceroute(dev, args[0]) if args.size() >= 1 else "usage: /tool traceroute <ip>\n"
		"system ssh":
			return CLI.try_ssh(self, args[0]) if args.size() >= 1 else "usage: /system ssh <ip>\n"
		"quit":
			wants_exit = true
			return ""
		"system identity set":
			if p.has("name") and Game.rename_device(dev, p["name"]):
				return ""
			return "usage: /system identity set name=<name>\n"
		"system identity print":
			return "  name: %s\n" % dev.name
		"snmp set":
			if p.has("community"):  # the old one-liner still works
				dev.snmp = String(p["community"])
			if String(p.get("enabled", "")) == "no":
				dev.snmp = ""
			elif String(p.get("enabled", "")) == "yes" and dev.snmp == "":
				dev.snmp = "public"  # the default community, until it is renamed
			if not p.has("enabled") and not p.has("community"):
				return "usage: /snmp set enabled=yes\n"
			Game.topology_changed.emit()
			return ""
		"snmp community set", "snmp community add":
			if p.has("name"):
				dev.snmp = String(p["name"])
				Game.topology_changed.emit()
				return ""
			return "usage: /snmp community set [find default=yes] name=<community>\n"
		"snmp community print":
			return "Columns: NAME, ADDRESSES\n#  NAME     ADDRESSES\n0  %-8s ::/0\n" % (dev.snmp if dev.snmp != "" else "public")
		"snmp print":
			return "  enabled: %s\n  contact: \n  location: \n" % ("yes" if dev.snmp != "" else "no")
		"ip traffic-flow print":
			if dev.talkers.is_empty():
				return "no flows recorded yet\n"
			var trows: Array = []
			for tk in dev.talkers:
				trows.append([String(tk), int(dev.talkers[tk])])
			trows.sort_custom(func(x, y): return int(x[1]) > int(y[1]))
			var tout := "%-38s %10s\n" % ["SRC > DST", "PACKETS"]
			for trow in trows.slice(0, 15):
				tout += "%-38s %10d\n" % [trow[0], trow[1]]
			return tout
		"routing bfd configuration add":
			var names := String(p.get("interfaces", "")).split(",", false)
			if names.is_empty():
				return "usage: /routing bfd configuration add interfaces=ether1,ether2 disabled=no\n"
			for nm in names:
				if _iface(nm) == null:
					return "failure: no such interface %s\n" % nm
			for nm in names:
				_iface(nm).bfd = String(p.get("disabled", "no")) != "yes"
			Game.topology_changed.emit()
			return ""
		"routing bfd configuration print":
			var bout := "Columns: INTERFACES, DISABLED\n#  INTERFACES  DISABLED\n"
			var bn := 0
			for bi: Net.Iface in dev.ifaces:
				if bi.bfd:
					bout += "%d  %-11s no\n" % [bn, bi.name]
					bn += 1
			return bout if bn > 0 else "no bfd configuration\n"
		"routing bfd session print":
			var bout := "Columns: INTERFACE, STATE\n#  INTERFACE  STATE\n"
			var bany := false
			var bn := 0
			for bi: Net.Iface in dev.ifaces:
				if not bi.bfd:
					continue
				bany = true
				bout += "%d  %-10s %s\n" % [bn, bi.name, Sim.bfd_session(bi)]
				bn += 1
			return bout if bany else "no bfd sessions\n"
		"system backup save":
			dev.startup = Game.device_config(dev)
			return "Configuration backup saved\n"
		"system backup load":
			if dev.startup.is_empty():
				return "failure: no backup found\n"
			Game.apply_device_config(dev, dev.startup)
			return "Restoring system configuration\n"
		"system reboot":
			var had := not dev.startup.is_empty()
			Game.apply_device_config(dev, dev.startup)
			return "rebooting... %s\n" % ("restored from backup" if had else "NO backup: configuration lost")
		"interface vlan add":
			if not dev.ip_forwarding:
				return "failure: vlan interfaces need a router\n"
			var parent := _iface(String(p.get("interface", "")))
			if parent == null or not String(p.get("vlan-id", "")).is_valid_int():
				return "usage: /interface vlan add name=vlan60 vlan-id=60 interface=ether1\n"
			var vsub := Game.add_subiface(dev, parent.name, int(p["vlan-id"]))
			if vsub == null:
				return "failure: could not create the vlan interface\n"
			return ""
		"interface vlan print":
			var out := "Flags: R - RUNNING\nColumns: NAME, MTU, ARP, VLAN-ID, INTERFACE\n#   NAME     MTU   ARP      VLAN-ID  INTERFACE\n"
			var any_v := false
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if i.parent != "":
					any_v = true
					out += "%d R %-8s %-5d enabled  %-8d %s\n" % [n, _dname(i), i.mtu, i.dot1q, i.parent]
					n += 1
			return out if any_v else "no vlan interfaces\n"
		"interface vrrp add":
			if not dev.ip_forwarding:
				return "failure: vrrp needs a router\n"
			var on := _iface(String(p.get("interface", "")))
			if on == null:
				return "usage: /interface vrrp add name=vrrp1 interface=ether1 vrid=1 priority=100\n"
			var vrid := int(p.get("vrid", "1")) if String(p.get("vrid", "1")).is_valid_int() else 1
			var prio := int(p.get("priority", "100")) if String(p.get("priority", "100")).is_valid_int() else 100
			on.vrrp = {"group": vrid, "vip": String(on.vrrp.get("vip", "")), "priority": clampi(prio, 1, 254),
				"preempt": String(p.get("preemption-mode", "yes")) != "no"}
			Game.topology_changed.emit()
			return ""
		"interface vrrp print":
			var out := "Flags: R - RUNNING; M - MASTER, B - BACKUP\nColumns: NAME, INTERFACE, VRID, PRIORITY\n#     NAME   INTERFACE  VRID  PRIORITY\n"
			var any_r := false
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if i.vrrp.is_empty():
					continue
				any_r = true
				var vip := String(i.vrrp.get("vip", ""))
				var flag := " "
				if vip != "":
					flag = "M" if Sim.vrrp_master(vip, int(i.vrrp["group"])) == dev else "B"
				out += "%d R%s vrrp%-3d %-10s %-5d %d\n" % [n, flag, int(i.vrrp["group"]), i.name,
					int(i.vrrp["group"]), int(i.vrrp.get("priority", 100))]
				n += 1
			return out if any_r else "no vrrp interfaces\n"
		"interface wireguard add":
			var wname := String(p.get("name", "wg0"))
			if not (wname.begins_with("wg") and wname.trim_prefix("wg").is_valid_int()):
				return "usage: /interface wireguard add name=wg0 listen-port=13231\n"
			if Game.add_wireguard(dev, int(wname.trim_prefix("wg"))) == null:
				return "failure: wireguard needs a router\n"
			return ""
		"interface wireguard print":
			var out := "Flags: R - RUNNING\nColumns: NAME, MTU, LISTEN-PORT, PUBLIC-KEY\n#   NAME  MTU   LISTEN-PORT  PUBLIC-KEY\n"
			var any_w := false
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if i.name.begins_with("wg"):
					any_w = true
					out += "%d R %-5s 1420  13231        %s\n" % [n, i.name, i.wg_key]
					n += 1
			return out if any_w else "no wireguard interfaces\n"
		"interface wireguard peers add":
			var wi := _iface(String(p.get("interface", "")))
			if wi == null or not wi.name.begins_with("wg") or not p.has("public-key") \
					or not p.has("endpoint-address") or not p.has("allowed-address"):
				return "usage: /interface wireguard peers add interface=wg0 public-key=<key> endpoint-address=<ip> endpoint-port=13231 allowed-address=<cidr>,<cidr>\n"
			var allowed: Array = []
			for c in String(p["allowed-address"]).split(",", false):
				if not Net.valid_cidr(String(c).strip_edges()):
					return "failure: '%s' is not a prefix\n" % c
				allowed.append(String(c).strip_edges())
			for existing in wi.wg_peers.duplicate():
				if String(existing.get("key", "")) == String(p["public-key"]):
					wi.wg_peers.erase(existing)
			wi.wg_peers.append({"key": String(p["public-key"]), "endpoint": String(p["endpoint-address"]),
				"allowed": allowed})
			Game.topology_changed.emit()
			return ""
		"interface wireguard peers print":
			var out := "Columns: INTERFACE, PUBLIC-KEY, ENDPOINT-ADDRESS, ALLOWED-ADDRESS, LAST-HANDSHAKE\n#  INTERFACE  PUBLIC-KEY          ENDPOINT-ADDRESS  ALLOWED-ADDRESS          LAST-HANDSHAKE\n"
			var any_p := false
			var n := 0
			for i: Net.Iface in dev.ifaces:
				for pr in i.wg_peers:
					any_p = true
					out += "%d  %-10s %-19s %-17s %-24s %s\n" % [n, i.name, pr.get("key", ""), pr.get("endpoint", ""),
						",".join(PackedStringArray(pr.get("allowed", []))),
						"1s" if Sim.wg_handshake(i, pr) else "never"]
					n += 1
			return out if any_p else "no peers\n"
		"interface print stats":
			var out := "Columns: NAME, RX-PACKET, TX-PACKET, RX-ERROR\n#   NAME       RX-PACKET  TX-PACKET  RX-ERROR\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				out += "%-3d %-10s %9d  %9d  %8d\n" % [n, _dname(i), i.rx_frames, i.tx_frames, i.rx_errors]
				n += 1
			return out
		"interface print":
			var out := "Flags: R - RUNNING; S - SLAVE; X - DISABLED\nColumns: NAME, TYPE, ACTUAL-MTU, MAC-ADDRESS\n#     NAME       TYPE       ACTUAL-MTU  MAC-ADDRESS\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				var flag := "X" if i.admin_down else ("R" if i.enabled and Game.link_at(i) else " ")
				var slave := "S" if i.lag > 0 else " "
				out += "%-2d %s%s %-10s %-10s %10d  %s\n" % [n, flag, slave, _dname(i), _itype(i), i.mtu, i.mac]
				n += 1
			return out
		"interface set":
			var i := _target(args, p)
			if i == null:
				return "usage: /interface set <name> disabled=yes|no mtu=N\n"
			for old_key in ["pvid", "mode", "tagged"]:
				if p.has(old_key):
					return "failure: VLAN membership lives on the bridge: /interface bridge port set [find interface=%s] pvid=N and /interface bridge vlan add vlan-ids=N tagged=... untagged=...\n" % i.name
			if p.has("bfd"):
				return "failure: BFD is configured under /routing bfd configuration add interfaces=%s\n" % i.name
			if p.has("ra"):
				return "failure: router advertisements are /ipv6 nd add interface=%s\n" % i.name
			if p.has("disabled"):
				i.admin_down = p["disabled"] == "yes"
				if i.admin_down:
					i.enabled = false
				else:
					i.err_disabled = false
					i.enabled = i.fault == ""
			if p.has("mtu") and String(p["mtu"]).is_valid_int():
				i.mtu = clampi(int(p["mtu"]), 576, 9216)
			Game.topology_changed.emit()
			return ""
		"interface bonding add":
			if dev.type != "switch":
				return "failure: bonding needs a switch here\n"
			if p.has("slaves"):
				var group := 1
				for i: Net.Iface in dev.ifaces:
					group = maxi(group, i.lag + 1)
				var names := String(p["slaves"]).split(",", false)
				for nm in names:
					if _iface(nm) == null:
						return "failure: no interface %s\n" % nm
				for nm in names:
					_iface(nm).lag = group
					_iface(nm).lag_mode = "active" if String(p.get("mode", "balance-rr")) == "802.3ad" else "on"
				Game.topology_changed.emit()
				return ""
			return "usage: /interface bonding add name=bond1 slaves=ether2,ether3 mode=802.3ad\n"
		"interface bonding print":
			var out := "Flags: R - RUNNING\nColumns: NAME, MTU, MAC-ADDRESS, MODE, SLAVES\n#   NAME   MTU   MODE     SLAVES\n"
			var groups := {}
			for i: Net.Iface in dev.ifaces:
				if i.lag > 0:
					if not groups.has(i.lag):
						groups[i.lag] = []
					groups[i.lag].append(i.name)
			var n := 0
			for g in groups:
				var lacp := false
				for i: Net.Iface in dev.ifaces:
					if i.lag == g and i.lag_mode != "on":
						lacp = true
				out += "%d R bond%-2d 1500  %-10s %s\n" % [n, g, "802.3ad" if lacp else "balance-rr", ",".join(PackedStringArray(groups[g]))]
				n += 1
			return out if not groups.is_empty() else "no bonding interfaces\n"
		"interface bridge add", "interface bridge set":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			if String(p.get("protocol-mode", "")) in ["stp", "rstp", "mstp"]:
				dev.stp_mode = "mst" if p["protocol-mode"] == "mstp" else String(p["protocol-mode"])
				Sim.flush_learned_state()
			if p.has("priority"):
				var pr := String(p["priority"])
				var val := pr.hex_to_int() if pr.begins_with("0x") else (int(pr) if pr.is_valid_int() else -1)
				if val < 0 or val > 61440 or val % 4096 != 0:
					return "failure: priority is a multiple of 4096 between 0 and 0xF000\n"
				dev.stp_priority = val
				Sim.flush_learned_state()
			Game.topology_changed.emit()
			return ""
		"interface bridge print":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			return "Flags: R - RUNNING\n 0 R name=\"%s\" mtu=auto arp=enabled protocol-mode=%s vlan-filtering=yes priority=0x%X\n" % [
				BRIDGE, "mstp" if dev.stp_mode == "mst" else dev.stp_mode, dev.stp_priority]
		"interface bridge vlan add":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			var vids := _vids(String(p.get("vlan-ids", "")))
			if vids.is_empty():
				return "usage: /interface bridge vlan add bridge=%s vlan-ids=<1-4094> tagged=<ports> untagged=<ports> [comment=<name>]\n" % BRIDGE
			var has_ports := p.has("tagged") or p.has("untagged")
			for vid in vids:
				if dev.vlans.has(vid) and not has_ports:
					return "failure: vlan %d already exists\n" % vid
				if not dev.vlans.has(vid) and not Game.add_vlan(dev, vid, String(p.get("comment", ""))):
					return "failure: invalid vlan id %d\n" % vid
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
				return "usage: /interface bridge vlan remove [find vlan-ids=<vid>]\n"
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
				out += "%-2d%s %-8s %8d  %-24s %s\n" % [n, "D" if vid == 1 else " ", BRIDGE, vid,
					",".join(PackedStringArray(_tagged_ports(vid))),
					",".join(PackedStringArray(_untagged_ports(vid)))]
				n += 1
			return out
		"interface bridge port add", "interface bridge port set":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			var i := _target(args, p)
			if i == null:
				return "usage: /interface bridge port set [find interface=ether2] pvid=<vid>\n"
			if p.has("pvid"):
				if not String(p["pvid"]).is_valid_int() or int(p["pvid"]) < 1 or int(p["pvid"]) > 4094:
					return "failure: pvid is a VLAN id 1-4094\n"
				var vid := int(p["pvid"])
				if not dev.vlans.has(vid):
					Game.add_vlan(dev, vid, "")
				if i.mode == "trunk":
					i.untagged_vlan = vid  # the untagged VLAN of a tagged port
				else:
					Game.set_access_vlan(i, vid)
			Game.topology_changed.emit()
			return ""
		"interface bridge port print":
			if dev.type != "switch":
				return "failure: no bridge on this device\n"
			var out := "Flags: I - INACTIVE; H - HW-OFFLOAD\nColumns: INTERFACE, BRIDGE, HW, PVID, PRIORITY, PATH-COST\n#     INTERFACE  BRIDGE   HW   PVID  PRIORITY  PATH-COST\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if i.name.begins_with("Management"):
					continue
				out += "%-2d %s%s %-10s %-8s yes  %4d  0x80             10\n" % [n,
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
				if i.name.begins_with("Management") or (only != null and i != only):
					continue
				var blocked := i.enabled and Sim.stp_blocked(i)
				var l := Game.link_at(i)
				var edge := l != null and l.other(i).dev.type != "switch"
				out += "   interface: %s\n      status: %s\n port-number: %d\n        role: %s\n   edge-port: %s\n    learning: %s\n  forwarding: %s\n\n" % [
					i.name, "in-bridge" if i.enabled else "inactive", n + 1,
					"alternate-port" if blocked else ("designated-port" if i.enabled else "disabled-port"),
					"yes" if edge else "no", "no" if blocked else "yes", "no" if blocked or not i.enabled else "yes"]
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
			return out if n > 0 else " (empty: send some traffic first)\n"
		"ipv6 address add":
			if dev.type == "switch":
				return "failure: this switch has no L3 support\n"
			if p.has("address") and p.has("interface") and _iface(p["interface"]):
				if Game.add_ip(_iface(p["interface"]), p["address"]):
					return ""
				return "failure: invalid or duplicate address\n"
			return "usage: /ipv6 address add address=<2001:db8::1/64> interface=<name>\n"
		"ipv6 address print":
			var out := "Flags: D - DYNAMIC; G - GLOBAL, L - LINK-LOCAL\nColumns: ADDRESS, INTERFACE\n#    ADDRESS                        INTERFACE\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				for cidr in i.ips:
					if Net.is_v6(cidr):
						out += "%-2d G %-30s %s\n" % [n, cidr, _dname(i)]
						n += 1
			return out
		"ipv6 nd add", "ipv6 nd set":
			var i := _target(args, p)
			if i == null or not dev.ip_forwarding:
				return "usage: /ipv6 nd add interface=ether2 advertise-dns=yes   (routers only)\n"
			i.ra = String(p.get("disabled", "no")) != "yes"
			Game.topology_changed.emit()
			return ""
		"ipv6 nd print":
			var out := "Columns: INTERFACE, RA-INTERVAL, RA-LIFETIME\n#  INTERFACE  RA-INTERVAL  RA-LIFETIME\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				if i.ra:
					out += "%d  %-10s 3m20s-10m    30m\n" % [n, i.name]
					n += 1
			return out if n > 0 else "no router advertisement entries\n"
		"ip address add":
			if dev.type == "switch" and not String(p.get("interface", "")).begins_with("Management"):
				return "failure: this switch has no L3 support (only the Management port takes an address)\n"
			if p.has("address") and _vrrp_iface(String(p.get("interface", ""))) != null:
				# the virtual address lives on the vrrp interface, RouterOS style
				var vi := _vrrp_iface(String(p["interface"]))
				var vip := String(p["address"]).split("/")[0]
				if not Net.valid_cidr(vip + "/32"):
					return "failure: invalid address\n"
				vi.vrrp["vip"] = vip
				Game.topology_changed.emit()
				return ""
			if p.has("address") and p.has("interface") and _iface(p["interface"]):
				if Game.add_ip(_iface(p["interface"]), p["address"]):
					return ""
				return "failure: invalid or duplicate address\n"
			return "usage: /ip address add address=<a.b.c.d/len> interface=<name>\n"
		"ip address remove":
			var n := 0
			for i: Net.Iface in dev.ifaces:
				for cidr in i.ips.duplicate():
					if String(p.get("address", "")) == String(cidr) or str(n) in args:
						Game.remove_ip(i, cidr)
						return ""
					n += 1
			return "usage: /ip address remove [find address=<cidr>]\n"
		"ip address print":
			var out := "Flags: X - DISABLED, I - INVALID, D - DYNAMIC\nColumns: ADDRESS, NETWORK, INTERFACE\n#   ADDRESS            NETWORK          INTERFACE\n"
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
			if dev.arp.is_empty():
				return "(empty)\n"
			var out := "Flags: D - DYNAMIC; C - COMPLETE\nColumns: ADDRESS, MAC-ADDRESS, INTERFACE\n#    ADDRESS         MAC-ADDRESS        INTERFACE\n"
			var n := 0
			for ip in dev.arp:
				out += "%-2d DC %-15s %-18s %s\n" % [n, ip, dev.arp[ip], CLI.arp_iface_name(dev, String(ip))]
				n += 1
			return out
		"system tech-support":
			# the same bundle, in the shape PacketTik prints it
			var out := "===== tech-support: %s at cycle %d =====\n" % [dev.name, Game.cycle]
			out += "\n/interface print\n" + exec("/interface print")
			out += "\n/ip address print\n" + exec("/ip address print")
			out += "\n/ip route print\n" + exec("/ip route print")
			out += "\n/ip arp print\n" + exec("/ip arp print")
			out += "\nconfiguration: %s\n" % ("saved" if not Game.config_dirty(dev)
				else "NOT SAVED")
			out += "\nlog\n"
			for log_line: String in dev.logs.slice(maxi(0, dev.logs.size() - 12)):
				out += log_line + "\n"
			return out + "===== end tech-support =====\n"
		"ip firewall nat add":
			if dev.type == "switch":
				return "failure: NAT needs a router\n"
			if p.get("chain", "") == "srcnat" and p.get("action", "") == "masquerade" \
					and _iface(p.get("out-interface", "")) != null:
				_iface(p["out-interface"]).nat = "outside"
				if not dev.services.has("nat"):
					dev.services["nat"] = {"rules": [], "acls": {}}
				dev.services["nat"]["rules"].append({"kind": "masquerade", "iface": _iface(p["out-interface"]).name})
				Game.topology_changed.emit()
				return ""
			return "usage: /ip firewall nat add chain=srcnat action=masquerade out-interface=<if>\n"
		"ip firewall nat print":
			var out := "Flags: X - disabled, I - invalid; D - dynamic\n"
			var n := 0
			for rule in Sim.nat_rules(dev):
				if String(rule.get("kind", "")) == "masquerade":
					out += " %d   chain=srcnat action=masquerade out-interface=%s\n" % [n, rule["iface"]]
					n += 1
			return out if n > 0 else out + "(no NAT rules)\n"
		"ip firewall address-list add":
			var list_name := String(p.get("list", ""))
			var addr := String(p.get("address", ""))
			if list_name == "" or not Net.valid_cidr(addr):
				return "usage: /ip firewall address-list add list=<name> address=<prefix/len>\n"
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
		"ip firewall address-list print":
			var lists: Dictionary = dev.bgp.get("lists", {})
			var out := "Columns: LIST, ADDRESS\n#   LIST        ADDRESS\n"
			var n := 0
			for lname in lists:
				for addr in lists[lname]:
					out += "%-3d %-11s %s\n" % [n, lname, addr]
					n += 1
			return out if n > 0 else "no address lists\n"
		"ip route add":
			var dst: String = p.get("dst-address", "0.0.0.0/0")
			var ad := 1
			if String(p.get("distance", "1")).is_valid_int():
				ad = clampi(int(p["distance"]), 1, 255)
			if p.has("gateway") and Net.valid_cidr(dst):
				var parts := dst.split("/")
				if Game.add_static_route(dev, parts[0], int(parts[1]), p["gateway"], "", ad):
					return ""
			return "usage: /ip route add dst-address=<p/len> gateway=<ip> [distance=<1-255>]   (dst defaults to 0.0.0.0/0)\n"
		"ip route remove":
			var dst2: String = p.get("dst-address", "")
			if dst2 == "":
				for a in args:  # by the number print gave it
					if String(a).is_valid_int():
						var rows := _route_rows()
						if int(a) >= 0 and int(a) < rows.size() and rows[int(a)]["src"] == "S":
							dst2 = "%s/%d" % [rows[int(a)]["prefix"], int(rows[int(a)]["plen"])]
			if Net.valid_cidr(dst2):
				var parts := dst2.split("/")
				Game.remove_static_route(dev, parts[0], int(parts[1]))
				return ""
			return "usage: /ip route remove [find dst-address=<p/len>]\n"
		"ip route print":
			var out := "Flags: D - DYNAMIC; A - ACTIVE; c - CONNECT, s - STATIC, o - OSPF, b - BGP\nColumns: DST-ADDRESS, GATEWAY, DISTANCE\n#      DST-ADDRESS        GATEWAY          DISTANCE\n"
			var n := 0
			for e in _route_rows():
				var flags := ("D" if e["src"] != "S" else " ") + ("A" if bool(e["active"]) else " ") + String(e["src"]).to_lower()
				var gw: String = e["iface"].name if e["src"] == "C" else String(e["next_hop"])
				out += "%-2d %s  %-18s %-16s %8d\n" % [n, flags, "%s/%d" % [e["prefix"], int(e["plen"])], gw, int(e["ad"])]
				n += 1
			return out
		"routing ospf instance add":
			if not dev.ip_forwarding:
				return "failure: OSPF needs a router\n"
			if not p.has("name"):
				return "usage: /routing ospf instance add name=default router-id=<a.b.c.d>\n"
			if dev.ospf.is_empty():
				dev.ospf = {"networks": [], "areas": {}}
			dev.ospf["instance"] = String(p["name"])
			if p.has("router-id"):
				dev.ospf["router_id"] = String(p["router-id"])
			Game.topology_changed.emit()
			return ""
		"routing ospf instance print":
			if dev.ospf.is_empty():
				return "no ospf instances\n"
			return "Flags: X - disabled\n 0   name=\"%s\" version=2 router-id=%s\n" % [dev.ospf.get("instance", "default"),
				dev.ospf.get("router_id", _first_ip())]
		"routing ospf area add":
			if dev.ospf.is_empty():
				return "failure: no such instance: add one with /routing ospf instance add name=default\n"
			if not p.has("name"):
				return "usage: /routing ospf area add name=backbone area-id=0.0.0.0 instance=%s\n" % dev.ospf.get("instance", "default")
			dev.ospf["areas"][String(p["name"])] = String(p.get("area-id", "0.0.0.0"))
			return ""
		"routing ospf area print":
			var areas: Dictionary = dev.ospf.get("areas", {})
			if areas.is_empty():
				return "no ospf areas\n"
			var out := "Flags: X - disabled\nColumns: NAME, INSTANCE, AREA-ID\n#   NAME      INSTANCE  AREA-ID\n"
			var n := 0
			for a in areas:
				out += "%-3d %-9s %-9s %s\n" % [n, a, dev.ospf.get("instance", "default"), areas[a]]
				n += 1
			return out
		"routing ospf interface-template add":
			if dev.ospf.is_empty():
				return "failure: no such instance: add one with /routing ospf instance add name=default\n"
			var area := String(p.get("area", ""))
			if not dev.ospf.get("areas", {}).has(area):
				return "failure: no such area '%s': /routing ospf area add name=backbone area-id=0.0.0.0 instance=%s\n" % [
					area, dev.ospf.get("instance", "default")]
			var nets := String(p.get("networks", "")).split(",", false)
			if nets.is_empty():
				return "usage: /routing ospf interface-template add networks=<p/len>[,<p/len>] area=<area>\n"
			for net in nets:
				if not Net.valid_cidr(net):
					return "failure: '%s' is not a prefix\n" % net
			for net in nets:
				if net not in dev.ospf["networks"]:
					dev.ospf["networks"].append(net)
			Game.topology_changed.emit()
			return ""
		"routing ospf interface-template remove":
			if dev.ospf.is_empty():
				return ""
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
				return "no interface templates\n"
			var out := "Flags: X - disabled, I - inactive\n"
			var n := 0
			var area_name := "backbone"
			for a in dev.ospf.get("areas", {}):
				area_name = String(a)
				break
			for net in dev.ospf["networks"]:
				out += " %d   area=%s networks=%s\n" % [n, area_name, net]
				n += 1
			return out
		"routing ospf neighbor print":
			if dev.ospf.is_empty():
				return "no ospf neighbors: OSPF is not running here\n"
			var nbs := Sim.ospf_neighbors(dev)
			if nbs.is_empty():
				return "no ospf neighbors: check the interface templates on both sides\n"
			var out := ""
			var seen := {}
			var n := 0
			for nb in nbs:
				if seen.has(nb["dev"]):
					continue
				seen[nb["dev"]] = true
				var rid: String = String(nb["dev"].ospf.get("router_id", nb["via_ip"]))
				out += " %d instance=%s area=%s address=%s router-id=%s state=\"Full\" state-changes=2 adjacency=%s\n" % [
					n, dev.ospf.get("instance", "default"), _area_name(), nb["via_ip"], rid, "%dm" % maxi(1, Game.cycle % 60)]
				n += 1
			return out
		"routing bgp template set":
			if dev.type != "router":
				return "failure: BGP needs a router\n"
			if p.has("as") and String(p["as"]).is_valid_int():
				if dev.bgp.is_empty():
					dev.bgp = {"asn": int(p["as"]), "neighbors": [], "networks": [], "lists": {}}
				else:
					dev.bgp["asn"] = int(p["as"])
				if p.has("router-id"):
					dev.bgp["router_id"] = String(p["router-id"])
				Game.topology_changed.emit()
				return ""
			return "usage: /routing bgp template set default as=<asn> router-id=<a.b.c.d>\n"
		"routing bgp connection add":
			if dev.type != "router":
				return "failure: BGP needs a router\n"
			var usage := "usage: /routing bgp connection add name=isp remote.address=<ip> remote.as=<asn> as=<my-asn> local.role=ebgp output.network=<address-list>\n"
			if not p.has("remote.address") or not String(p.get("remote.as", "")).is_valid_int():
				return usage
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
				return ""
			var n := 0
			for nb in dev.bgp["neighbors"].duplicate():
				if String(nb.get("name", "")) == String(p.get("name", "")) or str(n) in args:
					dev.bgp["neighbors"].erase(nb)
					_bgp_sync_networks()
					Game.topology_changed.emit()
					return ""
				n += 1
			return "usage: /routing bgp connection remove [find name=<name>]\n"
		"routing bgp connection print":
			if dev.bgp.is_empty() or dev.bgp["neighbors"].is_empty():
				return "no bgp connections\n"
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
				return "no bgp sessions\n"
			var out := "Flags: E - established\n"
			var n := 0
			for nb in dev.bgp["neighbors"]:
				var up := Sim.bgp_established(dev, nb)
				out += " %d %s name=\"%s-1\" remote.address=%s .as=%d local.address=%s .as=%d uptime=%s\n" % [n,
					"E" if up else " ", nb.get("name", "peer"), nb["ip"], int(nb["remote_as"]),
					_local_addr_toward(String(nb["ip"])), int(dev.bgp["asn"]),
					("%dm" % maxi(1, Game.cycle % 60)) if up else "0s (Active)"]
				n += 1
			return out
		"routing bgp advertisements print":
			if dev.bgp.is_empty():
				return "no bgp sessions\n"
			var out := "Columns: PEER, DST, NEXTHOP, AS-PATH\n"
			var n := 0
			for nb in dev.bgp["neighbors"]:
				if not Sim.bgp_established(dev, nb):
					continue
				for net in dev.bgp["networks"]:
					out += " %d peer=%s-1 dst=%s nexthop=%s as-path=%s\n" % [n, nb.get("name", "peer"), net,
						_local_addr_toward(String(nb["ip"])), int(dev.bgp["asn"])]
					n += 1
			return out if n > 0 else "no advertisements: no established session or no address-list on output.network\n"
	var nexts := {}
	for c in PATHS:
		if path != "" and c.begins_with(path + " "):
			nexts[String(c.substr(path.length() + 1)).split(" ")[0]] = true
	if not nexts.is_empty():
		var opts := nexts.keys()
		opts.sort()
		return "incomplete command: next: %s\n" % ", ".join(PackedStringArray(opts))
	return "bad command name %s (line 1 column 1)\n" % path.split(" ")[0]

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

const PATHS := ["help", "export", "ping", "tool traceroute", "system ssh", "quit",
	"system backup save", "system backup load", "system reboot",
	"system identity set", "system identity print", "system tech-support",
	"snmp set", "snmp print", "snmp community set", "snmp community add", "snmp community print",
	"ip traffic-flow print",
	"routing bfd configuration add", "routing bfd configuration print", "routing bfd session print",
	"interface print", "interface print stats", "interface set",
	"interface vlan add", "interface vlan print", "interface vrrp add", "interface vrrp print",
	"interface wireguard add", "interface wireguard print",
	"interface wireguard peers add", "interface wireguard peers print",
	"interface bonding add", "interface bonding print",
	"interface bridge add", "interface bridge set", "interface bridge print",
	"interface bridge vlan add", "interface bridge vlan remove", "interface bridge vlan print",
	"interface bridge port add", "interface bridge port set", "interface bridge port print",
	"interface bridge port monitor", "interface bridge host print",
	"ip address add", "ip address remove", "ip address print", "ip arp print",
	"ipv6 address add", "ipv6 address print", "ipv6 nd add", "ipv6 nd set", "ipv6 nd print",
	"ip route add", "ip route remove", "ip route print",
	"ip firewall nat add", "ip firewall nat print",
	"ip firewall address-list add", "ip firewall address-list print",
	"routing ospf instance add", "routing ospf instance print",
	"routing ospf area add", "routing ospf area print",
	"routing ospf interface-template add", "routing ospf interface-template remove",
	"routing ospf interface-template print", "routing ospf neighbor print",
	"routing bgp template set", "routing bgp connection add", "routing bgp connection remove",
	"routing bgp connection print", "routing bgp session print", "routing bgp advertisements print"]

func _is_path_word(prefix: String) -> bool:
	for c in PATHS:
		if c == prefix or c.begins_with(prefix + " "):
			return true
	return false

func _help() -> String:
	var out := ""
	for c in PATHS:
		out += "  /" + c + "\n"
	return out

func _export() -> String:
	## the configuration as RouterOS 7 would export it: paste it into a real one
	var out := "# PacketTik RouterOS 7 export\n/system identity set name=%s\n" % dev.name
	if dev.snmp != "":
		out += "/snmp set enabled=yes\n/snmp community set [find default=yes] name=%s\n" % dev.snmp
	if dev.type == "switch":
		out += "/interface bridge add name=%s vlan-filtering=yes protocol-mode=%s\n" % [BRIDGE,
			"mstp" if dev.stp_mode == "mst" else dev.stp_mode]
		for i: Net.Iface in dev.ifaces:
			if i.name.begins_with("Management"):
				continue
			out += "/interface bridge port add bridge=%s interface=%s%s\n" % [BRIDGE, i.name,
				(" pvid=%d" % i.untagged_vlan) if i.untagged_vlan != 1 else ""]
		for vid in _sorted_vids():
			if vid == 1:
				continue
			var tagged := _tagged_ports(vid)
			var untagged := _untagged_ports(vid)
			out += "/interface bridge vlan add bridge=%s vlan-ids=%d%s%s%s\n" % [BRIDGE, vid,
				(" tagged=%s" % ",".join(PackedStringArray(tagged))) if not tagged.is_empty() else "",
				(" untagged=%s" % ",".join(PackedStringArray(untagged))) if not untagged.is_empty() else "",
				(" comment=%s" % dev.vlans[vid]) if String(dev.vlans[vid]) != "" else ""]
	var bonds := {}
	for i: Net.Iface in dev.ifaces:
		if i.lag > 0:
			if not bonds.has(i.lag):
				bonds[i.lag] = []
			bonds[i.lag].append(i.name)
	for g in bonds:
		out += "/interface bonding add name=bond%d slaves=%s mode=802.3ad\n" % [g, ",".join(PackedStringArray(bonds[g]))]
	for i: Net.Iface in dev.ifaces:
		if not i.enabled and i.admin_down:
			out += "/interface set %s disabled=yes\n" % i.name
		if i.parent != "":
			out += "/interface vlan add name=vlan%d vlan-id=%d interface=%s\n" % [i.dot1q, i.dot1q, i.parent]
		if i.name.begins_with("wg"):
			out += "/interface wireguard add name=%s listen-port=13231\n" % i.name
			for pr in i.wg_peers:
				out += "/interface wireguard peers add interface=%s public-key=%s endpoint-address=%s endpoint-port=13231 allowed-address=%s\n" % [
					i.name, pr.get("key", ""), pr.get("endpoint", ""), ",".join(PackedStringArray(pr.get("allowed", [])))]
		for cidr in i.ips:
			if Net.is_v6(cidr):
				out += "/ipv6 address add address=%s interface=%s\n" % [cidr, _dname(i)]
			else:
				out += "/ip address add address=%s interface=%s network=%s\n" % [cidr, _dname(i), Net.network_of(cidr)["prefix"]]
		if i.ra:
			out += "/ipv6 nd add interface=%s\n" % i.name
		if i.bfd:
			out += "/routing bfd configuration add interfaces=%s disabled=no\n" % i.name
		if not i.vrrp.is_empty():
			out += "/interface vrrp add name=vrrp%d interface=%s vrid=%d priority=%d%s\n" % [int(i.vrrp["group"]), i.name,
				int(i.vrrp["group"]), int(i.vrrp.get("priority", 100)),
				"" if bool(i.vrrp.get("preempt", true)) else " preemption-mode=no"]
			if String(i.vrrp.get("vip", "")) != "":
				out += "/ip address add address=%s/32 interface=vrrp%d\n" % [i.vrrp["vip"], int(i.vrrp["group"])]
		for rule in Sim.nat_rules(dev):
			if String(rule.get("kind", "")) == "masquerade" and String(rule["iface"]) == i.name:
				out += "/ip firewall nat add chain=srcnat action=masquerade out-interface=%s\n" % i.name
	for r in dev.static_routes:
		out += "/ip route add dst-address=%s/%d gateway=%s%s\n" % [r["prefix"], int(r["plen"]), r["via"],
			(" distance=%d" % int(r["ad"])) if int(r.get("ad", 1)) != 1 else ""]
	if not dev.ospf.is_empty():
		var inst := String(dev.ospf.get("instance", "default"))
		out += "/routing ospf instance add name=%s%s\n" % [inst,
			(" router-id=%s" % dev.ospf["router_id"]) if dev.ospf.has("router_id") else ""]
		var areas: Dictionary = dev.ospf.get("areas", {"backbone": "0.0.0.0"})
		if areas.is_empty():
			areas = {"backbone": "0.0.0.0"}
		for a in areas:
			out += "/routing ospf area add name=%s area-id=%s instance=%s\n" % [a, areas[a], inst]
		for net in dev.ospf.get("networks", []):
			out += "/routing ospf interface-template add networks=%s area=%s\n" % [net, _area_name()]
	if not dev.bgp.is_empty():
		var lists: Dictionary = dev.bgp.get("lists", {})
		for lname in lists:
			for addr in lists[lname]:
				out += "/ip firewall address-list add list=%s address=%s\n" % [lname, addr]
		out += "/routing bgp template set default as=%d\n" % int(dev.bgp["asn"])
		for nb in dev.bgp["neighbors"]:
			out += "/routing bgp connection add name=%s remote.address=%s remote.as=%d as=%d local.role=ebgp%s\n" % [
				nb.get("name", "peer"), nb["ip"], int(nb["remote_as"]), int(dev.bgp["asn"]),
				(" output.network=%s" % nb["out_list"]) if String(nb.get("out_list", "")) != "" else ""]
	return out

func complete(line: String) -> Array:
	var raw := line.lstrip(" ").trim_prefix("/")
	var ends_space := raw.ends_with(" ")
	var toks := Array(raw.split(" ", false))
	var cur: String = "" if ends_space or toks.is_empty() else toks.pop_back()
	if "=" in cur:
		return []  # param values aren't completed (yet)
	var ctx: Array = []
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
