class_name ROS
extends CLI.Session
## MikroTik RouterOS-style CLI for PacketTik gear: /path print|add|set|remove
## with key=value parameters, /ping, export. Same Game state as everything.

func banner() -> String:
	return "PacketTik RouterOS %s — try '/interface print', '/ping <ip>', 'help'\n" % dev.name

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
		if i.name == name:
			return i
	return null

func exec(line: String) -> String:
	var toks := Array(line.strip_edges().trim_prefix("/").split(" ", false))
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
			return CLI.fmt_ping(dev, args[0]) if args.size() >= 1 else "usage: /ping <ip>\n"
		"tool traceroute":
			return CLI.fmt_traceroute(dev, args[0]) if args.size() >= 1 else "usage: /tool traceroute <ip>\n"
		"system identity set":
			if p.has("name") and Game.rename_device(dev, p["name"]):
				return ""
			return "usage: /system identity set name=<name>\n"
		"system identity print":
			return "name: %s\n" % dev.name
		"interface print":
			var out := "Flags: X - disabled, R - running\n # NAME       MTU  MAC\n"
			var n := 0
			for i: Net.Iface in dev.ifaces:
				var flag := "X" if not i.enabled else ("R" if Game.link_at(i) else " ")
				out += "%2d %s %-10s %-5d %s\n" % [n, flag, i.name, i.mtu, i.mac]
				n += 1
			return out
		"interface set":
			if args.is_empty() or _iface(args[0]) == null:
				return "usage: /interface set <name> disabled=yes|no mtu=N pvid=N mode=access|trunk\n"
			var i := _iface(args[0])
			if p.has("disabled"):
				i.enabled = p["disabled"] != "yes"
			if p.has("mtu") and String(p["mtu"]).is_valid_int():
				i.mtu = clampi(int(p["mtu"]), 576, 9216)
			if p.has("pvid") and String(p["pvid"]).is_valid_int():
				if dev.type != "switch":
					return "pvid is for switch ports\n"
				var vid := int(p["pvid"])
				if not dev.vlans.has(vid):
					Game.add_vlan(dev, vid, "")
				i.untagged_vlan = vid
				i.mode = "access"
			if p.has("mode") and p["mode"] in ["access", "trunk"]:
				if dev.type != "switch":
					return "mode is for switch ports\n"
				i.mode = p["mode"]
			Game.topology_changed.emit()
			return ""
		"interface bridge vlan add":
			if dev.type != "switch":
				return "no bridge on this device\n"
			if p.has("vlan-ids") and String(p["vlan-ids"]).is_valid_int():
				if Game.add_vlan(dev, int(p["vlan-ids"]), p.get("comment", "")):
					return ""
				return "failure: vlan already exists or invalid id\n"
			return "usage: /interface bridge vlan add vlan-ids=<1-4094> [comment=<name>]\n"
		"interface bridge vlan remove":
			if p.has("vlan-ids") and Game.remove_vlan(dev, int(p.get("vlan-ids", "0"))):
				return ""
			return "usage: /interface bridge vlan remove vlan-ids=<vid>\n"
		"interface bridge vlan print":
			if dev.type != "switch":
				return "no bridge on this device\n"
			var out := " VLAN-IDS  COMMENT     PORTS\n"
			var vids := dev.vlans.keys()
			vids.sort()
			for vid in vids:
				var ports: Array = []
				for i: Net.Iface in dev.ifaces:
					if i.mode == "trunk" or (i.mode == "access" and i.untagged_vlan == vid):
						ports.append(i.name)
				out += " %-9d %-11s %s\n" % [vid, dev.vlans[vid], ",".join(PackedStringArray(ports))]
			return out
		"ip address add":
			if dev.type == "switch":
				return "failure: this switch has no L3 support\n"
			if p.has("address") and p.has("interface") and _iface(p["interface"]):
				if Game.add_ip(_iface(p["interface"]), p["address"]):
					return ""
				return "failure: invalid or duplicate address\n"
			return "usage: /ip address add address=<a.b.c.d/len> interface=<name>\n"
		"ip address remove":
			for i: Net.Iface in dev.ifaces:
				if p.get("address", "") in i.ips:
					Game.remove_ip(i, p["address"])
					return ""
			return "usage: /ip address remove address=<cidr>\n"
		"ip address print":
			var out := " ADDRESS            INTERFACE\n"
			for i: Net.Iface in dev.ifaces:
				for cidr in i.ips:
					out += " %-18s %s\n" % [cidr, i.name]
			return out
		"ip arp print":
			if dev.arp.is_empty():
				return "(empty)\n"
			var out := " ADDRESS         MAC-ADDRESS\n"
			for ip in dev.arp:
				out += " %-15s %s\n" % [ip, dev.arp[ip]]
			return out
		"interface bridge port print":
			if dev.type != "switch":
				return "no bridge on this device\n"
			var out := " INTERFACE  PVID  MODE    STP-STATE\n"
			for i: Net.Iface in dev.ifaces:
				var st := "disabled"
				if i.enabled:
					st = "discarding" if Sim.stp_blocked(i) else "forwarding"
				out += " %-10s %-5d %-7s %s\n" % [i.name, i.untagged_vlan, i.mode, st]
			return out
		"interface bridge host print":
			if dev.type != "switch":
				return "no bridge on this device\n"
			var out := " VID  MAC-ADDRESS        ON-INTERFACE\n"
			var vids := dev.mac_table.keys()
			vids.sort()
			for vid in vids:
				for mac in dev.mac_table[vid]:
					out += " %-4d %-18s %s\n" % [vid, mac, dev.mac_table[vid][mac].name]
			return out if vids else " (empty — send some traffic first)\n"
		"ip firewall nat add":
			if dev.type == "switch":
				return "failure: NAT needs a router\n"
			if p.get("chain", "") == "srcnat" and p.get("action", "") == "masquerade" \
					and _iface(p.get("out-interface", "")) != null:
				_iface(p["out-interface"]).nat = "outside"
				Game.topology_changed.emit()
				return ""
			return "usage: /ip firewall nat add chain=srcnat action=masquerade out-interface=<if>\n"
		"ip firewall nat print":
			var out := ""
			for i: Net.Iface in dev.ifaces:
				if i.nat == "outside":
					out += " chain=srcnat action=masquerade out-interface=%s\n" % i.name
			return out if out != "" else "(no NAT rules)\n"
		"ip route add":
			var dst: String = p.get("dst-address", "0.0.0.0/0")
			if p.has("gateway") and Net.valid_cidr(dst):
				var parts := dst.split("/")
				if Game.add_static_route(dev, parts[0], int(parts[1]), p["gateway"]):
					return ""
			return "usage: /ip route add dst-address=<p/len> gateway=<ip>   (dst defaults to 0.0.0.0/0)\n"
		"ip route remove":
			var dst2: String = p.get("dst-address", "0.0.0.0/0")
			if Net.valid_cidr(dst2):
				var parts := dst2.split("/")
				Game.remove_static_route(dev, parts[0], int(parts[1]))
				return ""
			return "usage: /ip route remove dst-address=<p/len>\n"
		"ip route print":
			var out := " DST-ADDRESS        GATEWAY\n"
			for r in dev.static_routes:
				out += " %-18s %s\n" % ["%s/%d" % [r["prefix"], int(r["plen"])], r["via"]]
			for i: Net.Iface in dev.ifaces:
				for cidr in i.ips:
					out += " %-18s %s (connected)\n" % [cidr, i.name]
			for r in Sim._bgp_learned(dev):
				out += " %-18s %s (bgp)\n" % ["%s/%d" % [r["prefix"], int(r["plen"])], r["via"]]
			return out
		"routing ospf network add":
			if not dev.ip_forwarding:
				return "failure: OSPF needs a router\n"
			if Net.valid_cidr(p.get("prefix", "")):
				if dev.ospf.is_empty():
					dev.ospf = {"networks": []}
				if p["prefix"] not in dev.ospf["networks"]:
					dev.ospf["networks"].append(p["prefix"])
				Game.topology_changed.emit()
				return ""
			return "usage: /routing ospf network add prefix=<p/len>\n"
		"routing ospf network remove":
			if not dev.ospf.is_empty():
				dev.ospf["networks"].erase(p.get("prefix", ""))
				Game.topology_changed.emit()
			return ""
		"routing ospf print":
			if dev.ospf.is_empty():
				return "not configured\n"
			var out := "networks: %s\n NEIGHBOR       ADDRESS\n" % ", ".join(PackedStringArray(dev.ospf["networks"]))
			var seen := {}
			for nb in Sim.ospf_neighbors(dev):
				if not seen.has(nb["dev"]):
					seen[nb["dev"]] = true
					out += " %-14s %s\n" % [nb["dev"].name, nb["via_ip"]]
			return out
		"routing bgp set":
			if dev.type != "router":
				return "failure: BGP needs a router\n"
			if p.has("as") and String(p["as"]).is_valid_int():
				if dev.bgp.is_empty():
					dev.bgp = {"asn": int(p["as"]), "neighbors": [], "networks": []}
				else:
					dev.bgp["asn"] = int(p["as"])
				Game.topology_changed.emit()
				return ""
			return "usage: /routing bgp set as=<asn>\n"
		"routing bgp peer add":
			if dev.bgp.is_empty():
				return "failure: set your AS first: /routing bgp set as=<asn>\n"
			if p.has("address") and p.has("as"):
				dev.bgp["neighbors"].append({"ip": p["address"], "remote_as": int(p["as"])})
				Game.topology_changed.emit()
				return ""
			return "usage: /routing bgp peer add address=<ip> as=<asn>\n"
		"routing bgp network add":
			if dev.bgp.is_empty():
				return "failure: set your AS first\n"
			if Net.valid_cidr(p.get("prefix", "")):
				dev.bgp["networks"].append(p["prefix"])
				Game.topology_changed.emit()
				return ""
			return "usage: /routing bgp network add prefix=<p/len>\n"
		"routing bgp print":
			if dev.bgp.is_empty():
				return "not configured\n"
			var out := "as: %d\n PEER            REMOTE-AS  STATE\n" % int(dev.bgp["asn"])
			for nb in dev.bgp["neighbors"]:
				out += " %-15s %-10d %s\n" % [nb["ip"], int(nb["remote_as"]),
					"established" if Sim.bgp_established(dev, nb) else "idle"]
			if not dev.bgp["networks"].is_empty():
				out += "networks: %s\n" % ", ".join(PackedStringArray(dev.bgp["networks"]))
			return out
	return "bad command name %s (try 'help')\n" % path.split(" ")[0]

const PATHS := ["help", "export", "ping", "tool traceroute",
	"ip arp print", "interface bridge host print", "interface bridge port print",
	"system identity set", "system identity print",
	"interface print", "interface set",
	"interface bridge vlan add", "interface bridge vlan remove", "interface bridge vlan print",
	"ip address add", "ip address remove", "ip address print",
	"ip route add", "ip route remove", "ip route print",
	"ip firewall nat add", "ip firewall nat print",
	"routing bgp set", "routing bgp peer add", "routing bgp network add", "routing bgp print",
	"routing ospf network add", "routing ospf network remove", "routing ospf print"]

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
	var out := "# PacketTik export\n/system identity set name=%s\n" % dev.name
	var vids := dev.vlans.keys()
	vids.sort()
	for vid in vids:
		if vid != 1:
			out += "/interface bridge vlan add vlan-ids=%d comment=%s\n" % [vid, dev.vlans[vid]]
	for i: Net.Iface in dev.ifaces:
		if dev.type == "switch" and i.mode == "access" and i.untagged_vlan != 1:
			out += "/interface set %s pvid=%d\n" % [i.name, i.untagged_vlan]
		if dev.type == "switch" and i.mode == "trunk":
			out += "/interface set %s mode=trunk\n" % i.name
		if not i.enabled:
			out += "/interface set %s disabled=yes\n" % i.name
		for cidr in i.ips:
			out += "/ip address add address=%s interface=%s\n" % [cidr, i.name]
	for r in dev.static_routes:
		out += "/ip route add dst-address=%s/%d gateway=%s\n" % [r["prefix"], int(r["plen"]), r["via"]]
	if not dev.bgp.is_empty():
		out += "/routing bgp set as=%d\n" % int(dev.bgp["asn"])
		for nb in dev.bgp["neighbors"]:
			out += "/routing bgp peer add address=%s as=%d\n" % [nb["ip"], int(nb["remote_as"])]
		for net in dev.bgp["networks"]:
			out += "/routing bgp network add prefix=%s\n" % net
	return out

func complete(line: String) -> Array:
	var cur := line.strip_edges().trim_prefix("/")
	var out: Array = []
	var seen := {}
	for c in PATHS:
		if c.begins_with(cur):
			# complete only the next word
			var rest: String = c.substr(cur.rfind(" ") + 1 if " " in cur else 0)
			var word: String = rest.split(" ")[0]
			if not seen.has(word):
				seen[word] = true
				out.append(word)
	out.sort()
	return out
