class_name Contracts
## Authored campaign contracts. Each requirement is a live check against
## Game/Sim state, so completion is verified by the actual simulation.
## Add a contract = add a dict here; helpers below cover common checks.

static func all() -> Array:
	return [
		{
			"id": "rackup",
			"title": "Rack and stack",
			"customer": "Your first colo",
			"reward": 400,
			"brief": "Welcome to your corner of the colo floor! Buy a rack (toolbar or R, click a floor tile), open it and install one switch and two servers, then cable both servers to the switch (click a server port, then 'Run cable…').",
			"reqs": [
				{"d": "A rack is placed", "t": func() -> bool: return Game.racks.size() >= 1},
				{"d": "One switch and two servers installed", "t": func() -> bool: return _count("switch") >= 1 and _count("server") >= 2},
				{"d": "Two servers are cabled to a switch", "t": func() -> bool: return _servers_on_switch() >= 2},
			],
		},
		{
			"id": "first_ping",
			"title": "First light",
			"customer": "Internal ops",
			"reward": 500,
			"brief": "Make your two servers talk. Both need an IP address in the same subnet: 10.0.0.1/24 on one and 10.0.0.2/24 on the other. Use each server's console — 'ip addr add 10.0.0.1/24 dev eth0' — or the port editor. Then verify with 'ping 10.0.0.2'. Same subnet = no router needed: this is switching.",
			"reqs": [
				{"d": "A server owns 10.0.0.1/24", "t": func() -> bool: return _owner("10.0.0.1") != null},
				{"d": "A server owns 10.0.0.2/24", "t": func() -> bool: return _owner("10.0.0.2") != null},
				{"d": "10.0.0.1 can ping 10.0.0.2", "t": func() -> bool: return _ping("10.0.0.1", "10.0.0.2", true)},
			],
		},
		{
			"id": "two_tenants",
			"title": "Two tenants, one switch",
			"customer": "Alfa Ltd & Beta Kft",
			"reward": 800,
			"brief": "Your two servers now belong to different customers who must NOT see each other — but they share the switch. That's what VLANs are for. Cisco-style gear: 'enable', 'configure terminal', 'vlan 10', then per port 'interface Ethernet1' → 'switchport access vlan 10'. PacketTik (RouterOS): '/interface bridge vlan add vlan-ids=10' and '/interface set ether1 pvid=10'. Put 10.0.0.1's port in VLAN 10 and 10.0.0.2's in VLAN 20 — the ping that worked before must now FAIL: separate VLANs are separate networks.",
			"reqs": [
				{"d": "A switch has VLANs 10 and 20", "t": func() -> bool: return _switch_with_vlans([10, 20]) != null},
				{"d": "Access ports assigned to both VLAN 10 and 20", "t": func() -> bool: return _access_port_in(10) and _access_port_in(20)},
				{"d": "10.0.0.1 can NO LONGER reach 10.0.0.2", "t": func() -> bool: return _ping("10.0.0.1", "10.0.0.2", false)},
			],
		},
		{
			"id": "stretch_vlans",
			"title": "Growing pains",
			"customer": "Alfa Ltd & Beta Kft",
			"reward": 1000,
			"brief": "Alfa and Beta grew — you need a second switch, and their VLANs must span both. Connect the two switches with a cable and make BOTH ends trunk ports (Cisco-style: 'switchport mode trunk'; PacketTik: '/interface set ether5 mode=trunk'): a trunk carries multiple VLANs with tags. Then put a new Alfa server (10.0.0.3/24, VLAN 10 access port) on the SECOND switch: it must reach Alfa's 10.0.0.1 across the trunk, while Beta's 10.0.0.2 stays walled off.",
			"reqs": [
				{"d": "Two switches joined by a trunk (both ends)", "t": func() -> bool: return _trunk_between_switches(10)},
				{"d": "10.0.0.3 reaches 10.0.0.1 across switches", "t": func() -> bool: return _ping("10.0.0.3", "10.0.0.1", true)},
				{"d": "Beta (10.0.0.2) is still isolated from Alfa", "t": func() -> bool: return _ping("10.0.0.1", "10.0.0.2", false)},
			],
		},
		{
			"id": "redundant_core",
			"title": "One cable from disaster",
			"customer": "Alfa Ltd (again)",
			"reward": 1100,
			"brief": "Last month a janitor unplugged your inter-switch cable and Alfa's network split in half. They demand redundancy: run a SECOND cable between your two switches. Two links between switches form a LOOP — broadcasts would circulate forever and melt the network, but spanning tree saves you: it automatically blocks the spare link and unblocks it when the primary dies. Check 'show spanning-tree' (or '/interface bridge port print') — one port must show discarding/blocked while pings still flow.",
			"reqs": [
				{"d": "Two links between the same pair of switches", "t": func() -> bool: return _parallel_sw_links() >= 2},
				{"d": "Spanning tree is blocking the spare", "t": func() -> bool: return _stp_blocking()},
				{"d": "Alfa's servers still reach each other", "t": func() -> bool: return _ping("10.0.0.3", "10.0.0.1", true)},
			],
		},
		{
			"id": "two_offices",
			"title": "Connect two offices",
			"customer": "Gamma Corp",
			"reward": 1200,
			"brief": "Gamma runs two offices on different networks: 192.168.1.0/24 and 192.168.2.0/24. Different subnets can only talk through a router. Set up a server in each network (192.168.1.10/24 and 192.168.2.10/24) and install a router with one leg in each subnet. On a PacketTik R4 (RouterOS style): '/ip address add address=192.168.1.1/24 interface=ether1' and the same for ether2 with 192.168.2.1/24. (On Junivista gear it's Cisco-style: 'conf t', 'interface Ethernet1', 'ip address ...'.) Then give each server its default gateway: 'ip route add default via 192.168.1.1'. Both servers must reach each other; try 'traceroute' to see the router hop.",
			"reqs": [
				{"d": "Servers own 192.168.1.10 and 192.168.2.10", "t": func() -> bool: return _owner("192.168.1.10") != null and _owner("192.168.2.10") != null},
				{"d": "A router owns 192.168.1.1 and 192.168.2.1", "t": func() -> bool: return _router_owns(["192.168.1.1", "192.168.2.1"])},
				{"d": "192.168.1.10 pings 192.168.2.10", "t": func() -> bool: return _ping("192.168.1.10", "192.168.2.10", true)},
				{"d": "192.168.2.10 pings 192.168.1.10", "t": func() -> bool: return _ping("192.168.2.10", "192.168.1.10", true)},
			],
		},
		{
			"id": "plug_and_play",
			"title": "Plug and play",
			"customer": "Delta Web Kft",
			"reward": 1500,
			"brief": "Delta keeps adding machines and refuses to type IP addresses. Give them DHCP: on one of their servers run a DHCP service — 'dhcpd eth0 10.2.0.10 10.2.0.99 24 10.2.0.1' (that's: interface, first and last lease, prefix length, gateway) — the DHCP server itself needs a static IP in that subnet (e.g. 10.2.0.5/24). Then install a NEW server on the same switch/VLAN and just type 'dhclient eth0' on it: it must receive a lease automatically. DHCP works by broadcast, so both must share a broadcast domain.",
			"reqs": [
				{"d": "A server runs a DHCP service", "t": func() -> bool: return _dhcp_server() != null},
				{"d": "At least one lease has been handed out", "t": func() -> bool: return _lease_count() >= 1},
				{"d": "A leased client can ping its DHCP server", "t": func() -> bool: return _leased_client_pings_server()},
			],
		},
		{
			"id": "names_not_numbers",
			"title": "Names, not numbers",
			"customer": "Delta Web Kft",
			"reward": 1800,
			"brief": "Nobody remembers 10.2.0.x. Delta wants DNS: pick a server to be the resolver, give it records — 'dns add www.delta.hu 10.2.0.10' — and point a client at it ('nameserver <dns-server-ip>', or hand it out via DHCP's dns field). Then 'nslookup www.delta.hu' and 'ping www.delta.hu' must work from the client.",
			"reqs": [
				{"d": "A DNS server has a record for www.delta.hu", "t": func() -> bool: return _dns_record("www.delta.hu") != ""},
				{"d": "A client resolves www.delta.hu via the network", "t": func() -> bool: return _client_resolves("www.delta.hu")},
				{"d": "That client can ping www.delta.hu by name", "t": func() -> bool: return _client_pings_name("www.delta.hu")},
			],
		},
		{
			"id": "lock_it_down",
			"title": "Lock it down",
			"customer": "Epsilon Bank",
			"reward": 2500,
			"brief": "Epsilon Bank demands segmentation: their office network 172.16.1.0/24 must reach the app server 172.16.2.10, but NEVER the vault server 172.16.2.20. Install a firewall (PacketSense FW4) between two networks: one leg 172.16.1.1/24, other leg 172.16.2.1/24, with an office host at 172.16.1.10 and both servers in 172.16.2.0/24 (default gateways as usual). Then on the firewall console: 'acl deny 172.16.1.0/24 172.16.2.20/32' — first match wins, everything else is permitted. Verify with 'show acl' and pings both ways.",
			"reqs": [
				{"d": "A firewall with at least one deny rule", "t": func() -> bool: return _fw_with_deny() != null},
				{"d": "Office 172.16.1.10 reaches app 172.16.2.10", "t": func() -> bool: return _ping("172.16.1.10", "172.16.2.10", true)},
				{"d": "Office 172.16.1.10 is blocked from vault 172.16.2.20", "t": func() -> bool: return _owner("172.16.2.20") != null and _ping("172.16.1.10", "172.16.2.20", false)},
			],
		},
		{
			"id": "join_internet",
			"title": "Join the Internet",
			"customer": "Zeta Hosting",
			"reward": 3000,
			"brief": "Zeta wants their servers on the actual Internet. Buy an ISP Handoff ($200 + $30/cycle transit!) and cable its port to a router. The handoff speaks BGP as AS 64500 from 100.64.0.1/30 — put 100.64.0.2/30 on your router's leg, then start BGP. PacketTik R4: '/routing bgp set as=65001', '/routing bgp peer add address=100.64.0.1 as=64500'. Junivista (Cisco-style): 'router bgp 65001', 'neighbor 100.64.0.1 remote-as 64500'. The session gives you a default route — but the Internet can't answer until you ANNOUNCE your prefix: network add prefix=<your-server-subnet>/24 (or 'network <p>/24'). Prove it: a server (default gateway = your router) must ping 8.8.8.8. Check with '/routing bgp print' or 'show ip bgp summary'.",
			"reqs": [
				{"d": "ISP handoff cabled to a router", "t": func() -> bool: return _uplink_cabled()},
				{"d": "eBGP session Established", "t": func() -> bool: return _bgp_up() != null},
				{"d": "A server reaches 8.8.8.8 (prefix announced)", "t": func() -> bool: return _server_pings("8.8.8.8")},
			],
		},
		{
			"id": "hide_the_internals",
			"title": "Hide the internals",
			"customer": "Zeta Hosting (again)",
			"reward": 2200,
			"brief": "Zeta's auditors noticed you ANNOUNCED their private 10.x prefix to the ISP — real upstreams filter RFC1918, and it leaks your addressing plan. Do it properly with NAT: stop announcing the private prefix ('no network <p>/24' under router bgp), then masquerade instead. Junivista: on the uplink-facing interface, 'ip nat outside'. PacketTik: '/ip firewall nat add chain=srcnat action=masquerade out-interface=ether1'. The router rewrites private sources to its own public address and untranslates the replies. A private server must still ping 8.8.8.8 — with NO announcement covering it.",
			"reqs": [
				{"d": "A NAT outside interface on a router", "t": func() -> bool: return _nat_router() != null},
				{"d": "A private (10.x) server reaches 8.8.8.8", "t": func() -> bool: return _private_pings_inet() != null},
				{"d": "That server's prefix is NOT announced upstream", "t": func() -> bool: return _nat_not_announced()},
			],
		},
		{
			"id": "dynamic_routing",
			"title": "Static spaghetti",
			"customer": "Gamma Corp (again)",
			"reward": 2600,
			"brief": "Gamma opened a third office and your static routes are becoming spaghetti — every new subnet means touching every router. Time for a routing protocol: OSPF. Build two offices behind two routers (servers 10.20.1.10/24 and 10.20.2.10/24, routers linked by a transit subnet, e.g. 10.20.9.1/30 and 10.20.9.2/30), then on EACH router enable OSPF and advertise its subnets. Junivista: 'router ospf', 'network 10.20.0.0/16 area 0'. PacketTik: '/routing ospf network add prefix=10.20.0.0/16'. NO static routes on the routers — OSPF learns the paths ('show ip ospf neighbor', look for O routes in 'show ip route').",
			"reqs": [
				{"d": "Servers own 10.20.1.10 and 10.20.2.10", "t": func() -> bool: return _owner("10.20.1.10") != null and _owner("10.20.2.10") != null},
				{"d": "Two routers share an OSPF adjacency", "t": func() -> bool: return _ospf_adjacency()},
				{"d": "Both servers reach each other — no static routes on routers", "t": func() -> bool: return _ospf_no_static_path()},
			],
		},
		{
			"id": "feel_the_heat",
			"title": "Feeling the heat",
			"customer": "Your own ops",
			"reward": 2000,
			"brief": "Now that you own the room (Server room stage), the racks dump heat into it and the bare walls only dissipate 400W. Exceed that and gear starts tripping offline every cycle. Buy a CoolRow CRAC unit ($600 — it cools 1500W but draws 100W itself) and keep total cooling capacity above total power draw. The HUD shows ⚡draw / ❄capacity.",
			"reqs": [
				{"d": "Own at least a Server room (Expand)", "t": func() -> bool: return Game.stage >= 1},
				{"d": "A CRAC unit is installed and active", "t": func() -> bool: return _has_active("cooling")},
				{"d": "Cooling capacity covers power draw", "t": func() -> bool: return not Game.overheating()},
			],
		},
	]

# ---------- check helpers ----------

static func _uplink_cabled() -> bool:
	for d in Game.all_devices():
		if d.type == "uplink":
			for i: Net.Iface in d.ifaces:
				var l := Game.link_at(i)
				if l and l.other(i).dev.type == "router":
					return true
	return false

static func _bgp_up() -> Net.NDevice:
	for d in Game.all_devices():
		for nb in d.bgp.get("neighbors", []):
			if Sim.bgp_established(d, nb):
				return d
	return null

static func _server_pings(ip: String) -> bool:
	for d in Game.all_devices():
		if d.type == "server" and Sim.ping(d, ip)["ok"]:
			return true
	return false

static func _nat_router() -> Net.NDevice:
	for d in Game.all_devices():
		if d.ip_forwarding:
			for i: Net.Iface in d.ifaces:
				if i.nat == "outside":
					return d
	return null

static func _private_pings_inet() -> Net.NDevice:
	for d in Game.all_devices():
		if d.type != "server":
			continue
		var has_private := false
		for i: Net.Iface in d.ifaces:
			for cidr: String in i.ips:
				if cidr.begins_with("10.") or cidr.begins_with("192.168."):
					has_private = true
		if has_private and Sim.ping(d, "8.8.8.8")["ok"]:
			return d
	return null

static func _nat_not_announced() -> bool:
	var srv := _private_pings_inet()
	if srv == null:
		return false
	for i: Net.Iface in srv.ifaces:
		for cidr: String in i.ips:
			var ip: String = cidr.split("/")[0]
			for d in Game.all_devices():
				for net in d.bgp.get("networks", []):
					if net != "0.0.0.0/0":
						var parts := String(net).split("/")
						if Net.same_subnet(ip, parts[0], int(parts[1])):
							return false
	return true

static func _ospf_adjacency() -> bool:
	for d in Game.all_devices():
		if not d.ospf.is_empty() and not Sim.ospf_neighbors(d).is_empty():
			return true
	return false

static func _ospf_no_static_path() -> bool:
	for d in Game.all_devices():
		if d.ip_forwarding and not d.ospf.is_empty() and not d.static_routes.is_empty():
			return false
	return _ping("10.20.1.10", "10.20.2.10", true) and _ping("10.20.2.10", "10.20.1.10", true)

static func _has_active(type: String) -> bool:
	for d in Game.all_devices():
		if d.type == type and d.status == "active":
			return true
	return false

static func _count(type: String) -> int:
	var n := 0
	for d in Game.all_devices():
		if d.type == type:
			n += 1
	return n

static func _servers_on_switch() -> int:
	var n := 0
	for d in Game.all_devices():
		if d.type != "server":
			continue
		for i: Net.Iface in d.ifaces:
			var l := Game.link_at(i)
			if l and l.other(i).dev.type == "switch":
				n += 1
				break
	return n

static func _owner(ip: String) -> Net.NDevice:
	for d in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			for cidr: String in i.ips:
				if cidr.split("/")[0] == ip:
					return d
	return null

static func _ping(from_ip: String, to_ip: String, expect_ok: bool) -> bool:
	var d := _owner(from_ip)
	if d == null:
		return false
	return Sim.ping(d, to_ip)["ok"] == expect_ok

static func _switch_with_vlans(vids: Array) -> Net.NDevice:
	for d in Game.all_devices():
		if d.type != "switch":
			continue
		var ok := true
		for v in vids:
			if not d.vlans.has(v):
				ok = false
		if ok:
			return d
	return null

static func _access_port_in(vid: int) -> bool:
	for d in Game.all_devices():
		if d.type != "switch":
			continue
		for i: Net.Iface in d.ifaces:
			if i.mode == "access" and i.untagged_vlan == vid and Game.link_at(i):
				return true
	return false

static func _dhcp_server() -> Net.NDevice:
	for d in Game.all_devices():
		if d.services.has("dhcp"):
			return d
	return null

static func _lease_count() -> int:
	var n := 0
	for d in Game.all_devices():
		if d.services.has("dhcp"):
			n += d.services["dhcp"]["leases"].size()
	return n

static func _leased_client_pings_server() -> bool:
	var srv := _dhcp_server()
	if srv == null:
		return false
	var srv_ip := ""
	for i: Net.Iface in srv.ifaces:
		if i.name == srv.services["dhcp"]["iface"] and not i.ips.is_empty():
			srv_ip = i.ips[0].split("/")[0]
	if srv_ip == "":
		return false
	for mac in srv.services["dhcp"]["leases"]:
		var client := _mac_owner(mac)
		if client and Sim.ping(client, srv_ip)["ok"]:
			return true
	return false

static func _mac_owner(mac: String) -> Net.NDevice:
	for d in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			if i.mac == mac:
				return d
	return null

static func _dns_record(name: String) -> String:
	for d in Game.all_devices():
		var recs: Dictionary = d.services.get("dns", {}).get("records", {})
		if recs.has(name):
			return recs[name]
	return ""

static func _client_resolves(name: String) -> bool:
	for d in Game.all_devices():
		if d.type == "server" and d.resolver != "" and not d.services.has("dns"):
			if Sim.resolve(d, name) != "":
				return true
	return false

static func _client_pings_name(name: String) -> bool:
	for d in Game.all_devices():
		if d.type == "server" and d.resolver != "" and not d.services.has("dns"):
			var ip := Sim.resolve(d, name)
			if ip != "" and Sim.ping(d, ip)["ok"]:
				return true
	return false

static func _trunk_between_switches(vid: int) -> bool:
	for l in Game.links:
		if l.a.dev.type == "switch" and l.b.dev.type == "switch" \
				and l.a.dev != l.b.dev \
				and l.a.mode == "trunk" and l.b.mode == "trunk" \
				and (l.a.tagged_vlans.is_empty() or vid in l.a.tagged_vlans) \
				and (l.b.tagged_vlans.is_empty() or vid in l.b.tagged_vlans):
			return true
	return false

static func _parallel_sw_links() -> int:
	var pair_count := {}
	var best := 0
	for l in Game.links:
		if l.a.dev.type == "switch" and l.b.dev.type == "switch" and l.a.enabled and l.b.enabled:
			var names := [l.a.dev.name, l.b.dev.name]
			names.sort()
			var key := "%s|%s" % [names[0], names[1]]
			pair_count[key] = pair_count.get(key, 0) + 1
			best = maxi(best, pair_count[key])
	return best

static func _stp_blocking() -> bool:
	for d in Game.all_devices():
		if d.type == "switch":
			for i: Net.Iface in d.ifaces:
				if Sim.stp_blocked(i):
					return true
	return false

static func _fw_with_deny() -> Net.NDevice:
	for d in Game.all_devices():
		if d.type == "firewall":
			for rule in d.acls:
				if rule["action"] == "deny":
					return d
	return null

static func _router_owns(ips: Array) -> bool:
	for d in Game.all_devices():
		if d.type != "router":
			continue
		var ok := true
		for ip in ips:
			var owner := _owner(ip)
			if owner != d:
				ok = false
		if ok:
			return true
	return false
