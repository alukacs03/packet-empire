class_name ROS
extends CLI.Session
## MikroTik RouterOS-style CLI for PacketTik gear: /path print|add|set|remove
## with key=value parameters, /ping, export. Same Game state as everything.

func banner() -> String:
	return "PacketTik RouterOS %s: try '/interface print', '/ping <ip>', 'help'\n" % dev.name

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
	# RouterOS names a VLAN interface itself (vlan60); the model names it
	# after its parent (ether1.60). Accept the RouterOS name when it is unique.
	if name.begins_with("vlan") and name.trim_prefix("vlan").is_valid_int():
		var vid := int(name.trim_prefix("vlan"))
		var found: Net.Iface = null
		for i: Net.Iface in dev.ifaces:
			if i.parent != "" and i.dot1q == vid:
				if found != null:
					return null
				found = i
		return found
	return null

func _vrrp_iface(name: String) -> Net.Iface:
	## vrrp1 is the interface carrying VRRP group 1
	if not (name.begins_with("vrrp") and name.trim_prefix("vrrp").is_valid_int()):
		return null
	var group := int(name.trim_prefix("vrrp"))
	for i: Net.Iface in dev.ifaces:
		if int(i.vrrp.get("group", -1)) == group:
			return i
	return null

func exec(line: String) -> String:
	var pipe := line.find("|")
	if pipe > 0:
		var tail := line.substr(pipe + 1).strip_edges().split(" ", false)
		if tail.size() >= 2 and String(tail[0]) in ["include", "i", "grep"]:
			return CLI.filter_output(exec(line.substr(0, pipe).strip_edges()),
				" ".join(PackedStringArray(Array(tail).slice(1))))
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
			if args.size() >= 1:
				var ping_size := int(p.get("size", 64)) \
					if String(p.get("size", "64")).is_valid_int() else 64
				# count= is how PacketTik spells "keep going and tell me the loss"
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
		"snmp set":
			if p.has("community"):
				dev.snmp = String(p["community"])
				if String(p.get("enabled", "yes")) == "no":
					dev.snmp = ""
				Game.topology_changed.emit()
				return ""
			if String(p.get("enabled", "")) == "no":
				dev.snmp = ""
				Game.topology_changed.emit()
				return ""
			return "usage: /snmp set enabled=yes community=<name>\n"
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
		"routing bfd print":
			var bout := "%-12s %-10s\n" % ["INTERFACE", "SESSION"]
			var bany := false
			for bi: Net.Iface in dev.ifaces:
				if not bi.bfd:
					continue
				bany = true
				bout += "%-12s %-10s\n" % [bi.name, Sim.bfd_session(bi)]
			return bout if bany else "no bfd sessions\n"
		"snmp print":
			return "enabled: %s\ncommunity: %s\n" % ["yes" if dev.snmp != "" else "no",
				dev.snmp if dev.snmp != "" else "-"]
		"system backup save":
			dev.startup = Game.device_config(dev)
			return "configuration backup saved\n"
		"system backup load":
			if dev.startup.is_empty():
				return "failure: no backup found\n"
			Game.apply_device_config(dev, dev.startup)
			return "configuration restored from backup\n"
		"system reboot":
			var had := not dev.startup.is_empty()
			Game.apply_device_config(dev, dev.startup)
			return "rebooting... %s\n" % ("restored from backup" if had else "NO backup: configuration lost")
		"system identity print":
			return "name: %s\n" % dev.name
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
			var out := " NAME         VLAN-ID  INTERFACE\n"
			var any_v := false
			for i: Net.Iface in dev.ifaces:
				if i.parent != "":
					any_v = true
					out += " %-12s %-8d %s\n" % [i.name, i.dot1q, i.parent]
			return out if any_v else "no vlan interfaces\n"
		"interface vrrp add":
			if not dev.ip_forwarding:
				return "failure: vrrp needs a router\n"
			var on := _iface(String(p.get("interface", "")))
			if on == null:
				return "usage: /interface vrrp add interface=ether1 vrid=1 priority=100\n"
			var vrid := int(p.get("vrid", "1")) if String(p.get("vrid", "1")).is_valid_int() else 1
			var prio := int(p.get("priority", "100")) if String(p.get("priority", "100")).is_valid_int() else 100
			on.vrrp = {"group": vrid, "vip": String(on.vrrp.get("vip", "")), "priority": clampi(prio, 1, 254)}
			Game.topology_changed.emit()
			return ""
		"interface vrrp print":
			var out := " NAME    INTERFACE  VRID  PRIORITY  ADDRESS          STATE\n"
			var any_r := false
			for i: Net.Iface in dev.ifaces:
				if i.vrrp.is_empty():
					continue
				any_r = true
				var vip := String(i.vrrp.get("vip", ""))
				out += " vrrp%-3d %-10s %-5d %-9d %-16s %s\n" % [int(i.vrrp["group"]), i.name,
					int(i.vrrp["group"]), int(i.vrrp.get("priority", 100)),
					vip if vip != "" else "-", ("master" if Sim.vrrp_master(vip, int(i.vrrp["group"])) == dev else "backup") if vip != "" else "no address"]
			return out if any_r else "no vrrp interfaces\n"
		"interface wireguard add":
			var wname := String(p.get("name", "wg0"))
			if not (wname.begins_with("wg") and wname.trim_prefix("wg").is_valid_int()):
				return "usage: /interface wireguard add name=wg0\n"
			if Game.add_wireguard(dev, int(wname.trim_prefix("wg"))) == null:
				return "failure: wireguard needs a router\n"
			return ""
		"interface wireguard print":
			var out := " NAME   PUBLIC-KEY\n"
			var any_w := false
			for i: Net.Iface in dev.ifaces:
				if i.name.begins_with("wg"):
					any_w = true
					out += " %-6s %s\n" % [i.name, i.wg_key]
			return out if any_w else "no wireguard interfaces\n"
		"interface wireguard peers add":
			var wi := _iface(String(p.get("interface", "")))
			if wi == null or not wi.name.begins_with("wg") or not p.has("public-key") \
					or not p.has("endpoint-address") or not p.has("allowed-address"):
				return "usage: /interface wireguard peers add interface=wg0 public-key=<key> endpoint-address=<ip> allowed-address=<cidr>,<cidr>\n"
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
			var out := " INTERFACE  PUBLIC-KEY          ENDPOINT         ALLOWED-ADDRESS          HANDSHAKE\n"
			var any_p := false
			for i: Net.Iface in dev.ifaces:
				for pr in i.wg_peers:
					any_p = true
					out += " %-10s %-19s %-16s %-24s %s\n" % [i.name, pr.get("key", ""), pr.get("endpoint", ""),
						",".join(PackedStringArray(pr.get("allowed", []))),
						"ok" if Sim.wg_handshake(i, pr) else "none"]
			return out if any_p else "no peers\n"
		"interface print stats":
			var out := " NAME       RX-PACKET  TX-PACKET\n"
			for i: Net.Iface in dev.ifaces:
				out += " %-10s %9d  %9d\n" % [i.name, i.rx_frames, i.tx_frames]
			return out
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
				return "usage: /interface set <name> disabled=yes|no mtu=N pvid=N mode=access|trunk tagged=10,20|all bfd=yes|no\n"
			var i := _iface(args[0])
			if p.has("disabled"):
				i.enabled = p["disabled"] != "yes"
			if p.has("mtu") and String(p["mtu"]).is_valid_int():
				i.mtu = clampi(int(p["mtu"]), 576, 9216)
			if p.has("ra"):
				i.ra = String(p["ra"]) == "yes"
				Game.topology_changed.emit()
			if p.has("bfd"):
				i.bfd = String(p["bfd"]) == "yes"
				Game.topology_changed.emit()
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
			if p.has("tagged"):
				if dev.type != "switch" or i.mode != "trunk":
					return "tagged VLAN pruning is for switch trunk ports\n"
				if String(p["tagged"]) == "all":
					i.tagged_vlans = []
				else:
					var tagged_vids: Array = []
					for raw_vid in String(p["tagged"]).split(",", false):
						if not raw_vid.is_valid_int() or int(raw_vid) < 1 or int(raw_vid) > 4094:
							return "failure: tagged= expects VLAN IDs 1-4094 or all\n"
						tagged_vids.append(int(raw_vid))
					i.tagged_vlans = tagged_vids
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
				Game.topology_changed.emit()
				return ""
			return "usage: /interface bonding add slaves=ether2,ether3\n"
		"interface bonding print":
			var out := " GROUP  MEMBERS\n"
			var groups := {}
			for i: Net.Iface in dev.ifaces:
				if i.lag > 0:
					if not groups.has(i.lag):
						groups[i.lag] = []
					groups[i.lag].append(i.name)
			for g in groups:
				out += " %-6d %s\n" % [g, ",".join(PackedStringArray(groups[g]))]
			return out if not groups.is_empty() else "(no bonds)\n"
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
				out += " %-9d %-11s %s\n" % [vid, dev.vlans[vid], Net.compress_ports(ports)]
			return out
		"ipv6 address add":
			if dev.type == "switch":
				return "failure: this switch has no L3 support\n"
			if p.has("address") and p.has("interface") and _iface(p["interface"]):
				if Game.add_ip(_iface(p["interface"]), p["address"]):
					return ""
				return "failure: invalid or duplicate address\n"
			return "usage: /ipv6 address add address=<2001:db8::1/64> interface=<name>\n"
		"ipv6 address print":
			var out := " ADDRESS                        INTERFACE\n"
			for i: Net.Iface in dev.ifaces:
				for cidr in i.ips:
					if Net.is_v6(cidr):
						out += " %-30s %s\n" % [cidr, i.name]
			return out
		"ip address add":
			if dev.type == "switch":
				return "failure: this switch has no L3 support\n"
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
			return out if vids else " (empty: send some traffic first)\n"
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
		"ipv6 nat64 set":
			if not dev.ip_forwarding:
				return "nat64 runs on a router or firewall\n"
			var pfx := String(p.get("prefix", ""))
			var pool := String(p.get("pool", ""))
			if not pfx.ends_with("::") or not (pfx + "1").is_valid_ip_address():
				return "nat64: prefix must be an IPv6 prefix ending in ::\n"
			if not pool.is_valid_ip_address() or Net.is_v6(pool):
				return "nat64: pool must be an IPv4 address you own\n"
			dev.services["nat64"] = {"prefix": pfx, "pool": pool, "translated": 0,
				"returned": 0, "last_error": ""}
			Game.topology_changed.emit()
			return ""
		"ipv6 nat64 print":
			var cfg64: Dictionary = dev.services.get("nat64", {})
			if cfg64.is_empty():
				return "nat64 is not configured on this device\n"
			return " prefix=%s pool=%s translated=%d returned=%d state=%d last-error=%s\n" % [
				cfg64.get("prefix", ""), cfg64.get("pool", ""), int(cfg64.get("translated", 0)),
				int(cfg64.get("returned", 0)), dev.nat64_flows.size(),
				cfg64.get("last_error", "") if String(cfg64.get("last_error", "")) != "" else "none"]
		"ipv6 nat64 remove":
			dev.services.erase("nat64")
			dev.nat64_flows.clear()
			Game.topology_changed.emit()
			return ""
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
	var nexts := {}
	for c in PATHS:
		if path != "" and c.begins_with(path + " "):
			nexts[String(c.substr(path.length() + 1)).split(" ")[0]] = true
	if not nexts.is_empty():
		var opts := nexts.keys()
		opts.sort()
		return "incomplete command: next: %s\n" % ", ".join(PackedStringArray(opts))
	return "bad command name %s (try 'help')\n" % path.split(" ")[0]

const PATHS := ["help", "export", "ping", "tool traceroute", "system ssh", "quit",
	"system backup save", "system backup load", "system reboot",
	"ip arp print", "interface bridge host print", "interface bridge port print",
	"system identity set", "system identity print",
	"snmp set", "snmp print", "ip traffic-flow print", "routing bfd print",
	"interface print", "interface print stats", "interface set",
	"interface vlan add", "interface vlan print", "interface vrrp add", "interface vrrp print",
	"interface wireguard add", "interface wireguard print",
	"interface wireguard peers add", "interface wireguard peers print",
	"interface bonding add", "interface bonding print",
	"interface bridge vlan add", "interface bridge vlan remove", "interface bridge vlan print",
	"ip address add", "ip address remove", "ip address print",
	"ipv6 address add", "ipv6 address print",
	"ip route add", "ip route remove", "ip route print",
	"ip firewall nat add", "ip firewall nat print",
	"ipv6 nat64 set", "ipv6 nat64 print", "ipv6 nat64 remove", "system tech-support",
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
	if dev.snmp != "":
		out += "/snmp set enabled=yes community=%s\n" % dev.snmp
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
			if not i.tagged_vlans.is_empty():
				out += "/interface set %s tagged=%s\n" % [i.name,
					",".join(i.tagged_vlans.map(func(v): return str(v)))]
		if not i.enabled:
			out += "/interface set %s disabled=yes\n" % i.name
		if i.parent != "":
			out += "/interface vlan add name=vlan%d vlan-id=%d interface=%s\n" % [i.dot1q, i.dot1q, i.parent]
		if i.name.begins_with("wg"):
			out += "/interface wireguard add name=%s\n" % i.name
			for pr in i.wg_peers:
				out += "/interface wireguard peers add interface=%s public-key=%s endpoint-address=%s allowed-address=%s\n" % [
					i.name, pr.get("key", ""), pr.get("endpoint", ""), ",".join(PackedStringArray(pr.get("allowed", [])))]
		for cidr in i.ips:
			out += "/ip address add address=%s interface=%s\n" % [cidr, i.name]
		if not i.vrrp.is_empty():
			out += "/interface vrrp add interface=%s vrid=%d priority=%d\n" % [i.name, int(i.vrrp["group"]),
				int(i.vrrp.get("priority", 100))]
			if String(i.vrrp.get("vip", "")) != "":
				out += "/ip address add address=%s/32 interface=vrrp%d\n" % [i.vrrp["vip"], int(i.vrrp["group"])]
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
