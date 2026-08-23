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
			"brief": "Your two servers now belong to different customers who must NOT see each other — but they share the switch. That's what VLANs are for. On the switch console: 'enable', 'configure terminal', 'vlan 10' (then 'exit'), 'vlan 20', then put 10.0.0.1's switchport in VLAN 10 ('interface Ethernet1' → 'switchport access vlan 10') and 10.0.0.2's port in VLAN 20. The ping that worked before must now FAIL — separate VLANs are separate networks.",
			"reqs": [
				{"d": "A switch has VLANs 10 and 20", "t": func() -> bool: return _switch_with_vlans([10, 20]) != null},
				{"d": "Access ports assigned to both VLAN 10 and 20", "t": func() -> bool: return _access_port_in(10) and _access_port_in(20)},
				{"d": "10.0.0.1 can NO LONGER reach 10.0.0.2", "t": func() -> bool: return _ping("10.0.0.1", "10.0.0.2", false)},
			],
		},
		{
			"id": "two_offices",
			"title": "Connect two offices",
			"customer": "Gamma Corp",
			"reward": 1200,
			"brief": "Gamma runs two offices on different networks: 192.168.1.0/24 and 192.168.2.0/24. Different subnets can only talk through a router. Set up a server in each network (192.168.1.10/24 and 192.168.2.10/24), install a router with one leg in each subnet — router console: 'enable', 'configure terminal', 'interface Ethernet1', 'ip address 192.168.1.1/24' (Ethernet2 gets 192.168.2.1/24) — and give each server its default gateway: 'ip route add default via 192.168.1.1'. Both servers must reach each other; try 'traceroute' to see the router hop.",
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
	]

# ---------- check helpers ----------

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
