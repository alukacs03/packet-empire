class_name CLI
## Device CLI. Mutates the same Game state the web UI shows, so both stay
## in sync for free. Add commands by extending the match tables below.

static func exec(dev: Net.NDevice, line: String) -> String:
	var args := line.strip_edges().split(" ", false)
	if args.is_empty():
		return ""
	match args[0]:
		"help":
			return _help(dev)
		"show":
			return _show(dev, args)
		"hostname":
			if args.size() != 2:
				return "usage: hostname <name>\n"
			return "" if Game.rename_device(dev, args[1]) else "% invalid or duplicate name\n"
		"vlan":
			return _vlan(dev, args)
		"set":
			return _cmd_set(dev, args)
	return "% Unknown command — try 'help'\n"

static func _help(dev: Net.NDevice) -> String:
	var out := "  show interfaces | show version | hostname <name>
  set <iface> ip add <a.b.c.d/len>   set <iface> ip del <cidr>
  set <iface> enable|disable         set <iface> mtu <bytes>
"
	if dev.type == "switch":
		out += "  show vlans
  vlan add <vid> [name]              vlan del <vid>
  set <iface> mode access|trunk      set <iface> vlan <vid>
"
	return out

static func _show(dev: Net.NDevice, args: PackedStringArray) -> String:
	var what := args[1] if args.size() > 1 else ""
	match what:
		"version":
			return "%s — PacketOS 0.2 (%s, %d interfaces)\n" % [dev.name, dev.type, dev.ifaces.size()]
		"interfaces", "int":
			var out := "%-6s %-5s %-6s %-18s %-19s %s\n" % ["name", "state", "mode", "addresses", "mac", "peer"]
			for i: Net.Iface in dev.ifaces:
				var peer := Game.peer_label(i)
				var state := "down"
				if not i.enabled:
					state = "admin"
				elif peer != "":
					state = "up"
				var mode_s := ("vl%d" % i.untagged_vlan) if i.mode == "access" else "trunk"
				var addrs := ",".join(i.ips) if not i.ips.is_empty() else "-"
				out += "%-6s %-5s %-6s %-18s %-19s %s\n" % [i.name, state, mode_s, addrs, i.mac, peer if peer else "-"]
			return out
		"vlans":
			if dev.type != "switch":
				return "% no VLAN database on this device\n"
			var out := "%-6s %-14s %s\n" % ["vid", "name", "access ports"]
			var vids := dev.vlans.keys()
			vids.sort()
			for vid in vids:
				var ports: Array = []
				for i: Net.Iface in dev.ifaces:
					if i.mode == "access" and i.untagged_vlan == vid:
						ports.append(i.name)
				out += "%-6d %-14s %s\n" % [vid, dev.vlans[vid], ", ".join(ports)]
			return out
	return "usage: show interfaces|vlans|version\n"

static func _vlan(dev: Net.NDevice, args: PackedStringArray) -> String:
	if dev.type != "switch":
		return "% no VLAN database on this device\n"
	if args.size() >= 3 and args[1] == "add" and args[2].is_valid_int():
		var name := args[3] if args.size() > 3 else ""
		if Game.add_vlan(dev, int(args[2]), name):
			return ""
		return "% invalid vid (1-4094) or vlan exists\n"
	if args.size() == 3 and args[1] == "del" and args[2].is_valid_int():
		if Game.remove_vlan(dev, int(args[2])):
			return ""
		return "% cannot remove (unknown vid, or vlan 1)\n"
	return "usage: vlan add <vid> [name] | vlan del <vid>\n"

static func _cmd_set(dev: Net.NDevice, args: PackedStringArray) -> String:
	if args.size() < 3:
		return "usage: set <iface> <property> ... — see 'help'\n"
	var iface: Net.Iface = null
	for i: Net.Iface in dev.ifaces:
		if i.name == args[1]:
			iface = i
	if iface == null:
		return "%% no such interface '%s'\n" % args[1]
	match args[2]:
		"enable", "disable":
			iface.enabled = args[2] == "enable"
			Game.topology_changed.emit()
			return ""
		"mtu":
			if args.size() == 4 and args[3].is_valid_int() \
					and int(args[3]) >= 576 and int(args[3]) <= 9216:
				iface.mtu = int(args[3])
				Game.topology_changed.emit()
				return ""
			return "usage: set <iface> mtu <576-9216>\n"
		"mode":
			if dev.type != "switch":
				return "% switchport mode is for switches\n"
			if args.size() == 4 and args[3] in ["access", "trunk"]:
				iface.mode = args[3]
				Game.topology_changed.emit()
				return ""
			return "usage: set <iface> mode access|trunk\n"
		"vlan":
			if dev.type != "switch":
				return "% switchport vlan is for switches\n"
			if args.size() == 4 and args[3].is_valid_int() \
					and Game.set_access_vlan(iface, int(args[3])):
				return ""
			return "% unknown vid — create it first: vlan add <vid>\n"
		"ip":
			if args.size() == 5 and args[3] == "add":
				if Game.add_ip(iface, args[4]):
					return ""
				return "% invalid CIDR (a.b.c.d/len) or duplicate\n"
			if args.size() == 5 and args[3] == "del":
				if args[4] in iface.ips:
					Game.remove_ip(iface, args[4])
					return ""
				return "% address not on interface\n"
			return "usage: set <iface> ip add|del <cidr>\n"
	return "%% unknown property '%s' — see 'help'\n" % args[2]
