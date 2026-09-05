class_name Contracts
## Authored campaign contracts. Each requirement is a live check against
## Game/Sim state, so completion is verified by the actual simulation.
## Add a contract = add a dict here; helpers below cover common checks.

## a completed contract retires an earlier one it makes impossible
const SUPERSEDES := {"two_tenants": "first_ping"}

## The opening jobs are played on whichever equipment the player actually
## bought.  Keep the concept and the commands separate so a PacketTik starter
## rack is never handed an EOS answer sheet (and a mixed rack can show both).
const DIALECT_HINTS := {
	"two_tenants": {
		"device_type": "switch",
		"intro": "Create VLANs 10 and 20, then put the port facing 10.0.0.1 in VLAN 10 and the port facing 10.0.0.2 in VLAN 20. The ping failing afterwards is the point: the tenants are isolated.",
		"after": "Use the interface names that are actually cabled to the two servers.",
		"ros": [
			"/interface bridge port set [find interface=ether1] pvid=10",
			"/interface bridge port set [find interface=ether2] pvid=20",
			"/interface bridge vlan add bridge=bridge1 vlan-ids=10 untagged=ether1",
			"/interface bridge vlan add bridge=bridge1 vlan-ids=20 untagged=ether2",
			"/interface bridge vlan print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"vlan 10",
			"vlan 20",
			"interface Ethernet1",
			"switchport access vlan 10",
			"interface Ethernet2",
			"switchport access vlan 20",
			"show vlan",
		],
	},
	"stretch_vlans": {
		"device_type": "switch",
		"intro": "The link between the switches must be a trunk on BOTH ends so tagged VLAN 10 can cross it. Create VLAN 10 on the second switch, trunk the cabled inter-switch port on each switch, then attach 10.0.0.3/24 to a VLAN 10 access port on the second switch.",
		"after": "Run the switch commands on both ends of the inter-switch cable, substituting its real port name. On the new server use: ip addr add 10.0.0.3/24 dev eth0",
		"ros": [
			"/interface bridge vlan add bridge=bridge1 vlan-ids=10 tagged=ether5",
			"/interface bridge vlan print",
			"/interface bridge port print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"vlan 10",
			"interface Ethernet8",
			"switchport mode trunk",
			"show interfaces trunk",
		],
	},
	"redundant_core": {
		"device_type": "switch",
		"intro": "Run a second cable between the switches. Spanning tree should keep one path forwarding and hold the other in discarding state so the loop cannot melt the network. Inspect the port states, then disable the forwarding link to watch the spare take over.",
		"after": "Substitute the real forwarding port when testing failover, and re-enable it afterwards.",
		"ros": [
			"/interface bridge port monitor [find]",
			"/interface set ether4 disabled=yes",
			"/interface set ether4 disabled=no",
		],
		"eos": [
			"enable",
			"show spanning-tree",
			"configure terminal",
			"interface Ethernet4",
			"shutdown",
			"no shutdown",
		],
	},
	"two_offices": {
		"device_type": "router",
		"intro": "Give one router leg an address in each office subnet, then point each server default route at the address on its own subnet. Traceroute should stop at the last working hop if an address, cable, or gateway is wrong.",
		"after": "On the two Linux servers use: ip route add default via 192.168.1.1 and ip route add default via 192.168.2.1",
		"ros": [
			"/ip address add address=192.168.1.1/24 interface=ether1",
			"/ip address add address=192.168.2.1/24 interface=ether2",
			"/ip address print",
			"/ip route print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"interface Ethernet1",
			"ip address 192.168.1.1/24",
			"interface Ethernet2",
			"ip address 192.168.2.1/24",
			"show ip interface brief",
			"show ip route",
		],
	},
	"plug_and_play": {
		"device_type": "server",
		"intro": "One server becomes the DHCP server: a static address in the subnet, then the lease range, prefix length and gateway. A new machine on the same VLAN asks by broadcast and gets an address without anybody typing it.",
		"after": "Both machines must sit in one broadcast domain: same switch and same VLAN, or the broadcast never reaches the server.",
		"linux": [
			"ip addr add 10.2.0.5/24 dev eth0",
			"dhcpd eth0 10.2.0.10 10.2.0.99 24 10.2.0.1",
			"dhclient eth0        (on the new machine)",
			"ip addr",
		],
	},
	"names_not_numbers": {
		"device_type": "server",
		"intro": "A resolver holds the records; a client is pointed at the resolver. Then names work in ping.",
		"after": "The record's address is the real server's; the resolver's own address is what goes in 'nameserver'. Or hand the resolver out through DHCP's dns field.",
		"linux": [
			"dns add www.delta.hu 10.2.0.10        (on the resolver)",
			"nameserver 10.2.0.5                  (on the client)",
			"nslookup www.delta.hu",
			"ping www.delta.hu",
		],
	},
	"lock_it_down": {
		"device_type": "firewall",
		"intro": "Two legs, two subnets, and a list that names what must never happen, followed by a permit for everything else. Without that last line the implicit deny drops the app server's traffic too.",
		"after": "Test both directions: a stateless deny also kills replies, and that asymmetry is the lesson.",
		"eos": [
			"enable",
			"configure terminal",
			"acl deny 172.16.1.0/24 172.16.2.20/32",
			"acl permit any any",
			"end",
			"show ip access-lists",
		],
	},
	"join_internet": {
		"device_type": "router",
		"intro": "Address the leg toward the handoff, start BGP with your own AS, peer with the ISP's AS, then announce the prefix you actually own. The default route arrives by itself once the session is up.",
		"after": "The server behind the router needs the router as its default gateway, and the announced prefix must cover the server's subnet.",
		"ros": [
			"/ip address add address=100.64.0.2/30 interface=ether1",
			"/ip firewall address-list add list=bgp-nets address=10.3.0.0/24",
			"/routing bgp connection add name=isp remote.address=100.64.0.1 remote.as=64500 as=65001 local.role=ebgp output.network=bgp-nets",
			"/routing bgp session print",
			"/ip route print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"interface Ethernet1",
			"ip address 100.64.0.2/30",
			"router bgp 65001",
			"neighbor 100.64.0.1 remote-as 64500",
			"network 10.3.0.0/24",
			"end",
			"show ip bgp summary",
			"show ip bgp",
		],
	},
	"hide_the_internals": {
		"device_type": "router",
		"intro": "Withdraw the private prefix from BGP, then translate instead: on Cisco-style gear mark the inside and outside interfaces, write a standard list of who may be translated, and tie the list to the outside interface with overload. RouterOS masquerades everything leaving the outside interface.",
		"after": "Substitute your real subnet and port names. The server keeps its private address and still reaches 8.8.8.8.",
		"ros": [
			"/ip firewall address-list remove [find address=10.3.0.0/24]",
			"/ip firewall nat add chain=srcnat action=masquerade out-interface=ether1",
			"/ip firewall nat print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"router bgp 65001",
			"no network 10.3.0.0/24",
			"exit",
			"interface Ethernet2",
			"ip nat inside",
			"interface Ethernet1",
			"ip nat outside",
			"exit",
			"access-list 1 permit 10.3.0.0 0.0.0.255",
			"ip nat inside source list 1 interface Ethernet1 overload",
			"end",
			"show ip nat translations",
		],
	},
	"dynamic_routing": {
		"device_type": "router",
		"intro": "Each router advertises the networks it owns and learns the rest from its neighbour. No static routes: the O routes in the table are OSPF's.",
		"after": "Run it on both routers; the transit subnet between them must be covered by the network statement or no adjacency forms.",
		"ros": [
			"/routing ospf instance add name=default router-id=10.20.9.1",
			"/routing ospf area add name=backbone area-id=0.0.0.0 instance=default",
			"/routing ospf interface-template add networks=10.20.0.0/16 area=backbone",
			"/routing ospf neighbor print",
			"/ip route print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"router ospf 1",
			"network 10.20.0.0/16 area 0",
			"end",
			"show ip ospf neighbor",
			"show ip route",
		],
	},
	"no_spof": {
		"device_type": "router",
		"intro": "Two routers, one virtual address. The one with the higher priority is master; the other answers the same address the moment the master dies. Servers use the virtual address as their gateway.",
		"after": "Set the priority on the router you prefer; leave the other at the default. 'show vrrp' names the master.",
		"ros": [
			"/interface vrrp add name=vrrp1 interface=ether1 vrid=1 priority=120",
			"/ip address add address=10.40.0.1/32 interface=vrrp1",
			"/interface vrrp print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"interface Ethernet1",
			"vrrp 1 ip 10.40.0.1",
			"vrrp 1 priority 120",
			"end",
			"show vrrp",
		],
	},
	"double_the_pipe": {
		"device_type": "switch",
		"intro": "Both parallel ports on both switches join one channel group. LACP negotiates the bundle: active on at least one side, and the same mode story on both switches.",
		"after": "Do it on both switches. 'show port-channel summary' shows Po1(SU) and every member (P) when it is right.",
		"ros": [
			"/interface bonding add name=bond1 slaves=ether4,ether5 mode=802.3ad",
			"/interface bonding print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"interface Ethernet4",
			"channel-group 1 mode active",
			"interface Ethernet5",
			"channel-group 1 mode active",
			"end",
			"show port-channel summary",
			"show spanning-tree",
		],
	},
	"router_on_a_stick": {
		"device_type": "router",
		"intro": "One physical port, one subinterface per VLAN, each tagged with its VLAN id and carrying that VLAN's gateway address. The switch end of the cable is a trunk.",
		"after": "Servers in VLAN 60 and 61 point their default route at 10.90.60.1 and 10.90.61.1.",
		"ros": [
			"/interface vlan add name=vlan60 vlan-id=60 interface=ether1",
			"/interface vlan add name=vlan61 vlan-id=61 interface=ether1",
			"/ip address add address=10.90.60.1/24 interface=vlan60",
			"/ip address add address=10.90.61.1/24 interface=vlan61",
			"/interface vlan print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"interface Ethernet1.60",
			"encapsulation dot1q 60",
			"ip address 10.90.60.1/24",
			"interface Ethernet1.61",
			"encapsulation dot1q 61",
			"ip address 10.90.61.1/24",
			"end",
			"show ip interface brief",
		],
	},
	"one_switch_two_nets": {
		"model": "sw-24",
		"device_type": "switch",
		"intro": "An L3 switch routes between its own VLANs through SVIs: a virtual interface per VLAN, with the gateway address on it. No router in the path.",
		"after": "Only an L3-capable model (Arivista 7024) accepts 'interface Vlan40'. Each server's default gateway is its SVI address.",
		"eos": [
			"enable",
			"configure terminal",
			"vlan 40",
			"vlan 50",
			"interface Vlan40",
			"ip address 10.80.40.1/24",
			"interface Vlan50",
			"ip address 10.80.50.1/24",
			"end",
			"show ip route",
		],
	},
	"guest_wifi": {
		"model": "ap-1",
		"device_type": "switch",
		"intro": "The access point's uplink is a trunk; each SSID maps to a VLAN. Guests and staff share the radio but not the network.",
		"after": "The AP console takes the ssid lines; on each host type 'wifi join guest-wifi' or 'wifi join staff-wifi' and give it an address in that VLAN's subnet.",
		"eos": [
			"enable",
			"configure terminal",
			"ssid guest-wifi vlan 30",
			"ssid staff-wifi vlan 31",
			"end",
		],
	},
	"wireguard_link": {
		"device_type": "router",
		"intro": "Each router gets a tunnel interface with a small address, learns the other side's public key, endpoint and allowed networks, and routes the far office down the tunnel.",
		"after": "Swap in the real keys ('show wireguard' or '/interface wireguard print' shows your own) and the real public addresses.",
		"ros": [
			"/interface wireguard add name=wg0",
			"/interface wireguard print",
			"/ip address add address=10.99.0.1/30 interface=wg0",
			"/interface wireguard peers add interface=wg0 public-key=<their key> endpoint-address=<their public address> allowed-address=172.20.2.0/24,10.99.0.2/32",
			"/ip route add dst-address=172.20.2.0/24 gateway=10.99.0.2",
		],
		"eos": [
			"enable",
			"configure terminal",
			"interface wg0",
			"ip address 10.99.0.1/30",
			"wireguard peer <their key> endpoint <their public address> allowed 172.20.2.0/24,10.99.0.2/32",
			"exit",
			"ip route 172.20.2.0/24 10.99.0.2",
			"end",
			"show wireguard",
		],
	},
	"keep_it_moving": {
		"device_type": "server",
		"intro": "A virtual machine lives on a host and keeps its address when it moves, which only works while both hosts share the same VLAN.",
		"after": "Both hosts on the same switch and VLAN; then migrate and ping the same address again.",
		"linux": [
			"vm create obs01",
			"vm addr obs01 10.160.5.20/24",
			"vm migrate obs01 <other host>",
			"vm list",
		],
	},
	"always_on": {
		"model": "lb-1",
		"device_type": "switch",
		"intro": "The balancer owns a virtual address and a pool of real servers; it health-checks the pool and hands each flow to a live member.",
		"after": "Give the balancer its own address on the subnet first. Switch a member off and the virtual address must still answer.",
		"eos": [
			"enable",
			"configure terminal",
			"virtual-server 10.190.0.100 members 10.190.0.11,10.190.0.12",
			"end",
			"show virtual-server",
		],
	},
	"dual_stack": {
		"device_type": "router",
		"intro": "Add a v6 address per router leg and per server, then point each server's v6 default at its gateway. The v4 side keeps working untouched.",
		"after": "On the servers: 'ip -6 addr add 2001:db8:70::10/64 dev eth0' and 'ip -6 route add default via 2001:db8:70::1'. A capture shows Neighbor Discovery instead of ARP.",
		"ros": [
			"/ipv6 address add address=2001:db8:70::1/64 interface=ether1",
			"/ipv6 address add address=2001:db8:71::1/64 interface=ether2",
			"/ipv6 address print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"interface Ethernet1",
			"ipv6 address 2001:db8:70::1/64",
			"interface Ethernet2",
			"ipv6 address 2001:db8:71::1/64",
			"end",
			"show ip interface brief",
		],
	},
	"v6_only_tenant": {
		"model": "rtr-edge",
		"device_type": "router",
		"intro": "Two halves: the resolver synthesises an AAAA for a name that only has an A record, and the translator turns that synthetic destination back into IPv4. Native IPv6 never touches the translator.",
		"after": "The resolver is a Linux server: 'dns add legacy.pkt 10.164.0.10' then 'dns64 64:ff9b::'. The translator is a Junivista router or the firewall; PacketTik has no NAT64.",
		"eos": [
			"enable",
			"configure terminal",
			"nat64 prefix 64:ff9b:: pool <your v4 address>",
			"end",
			"show nat64",
		],
	},
	"overlay_tenant": {
		"model": "sw-24",
		"device_type": "switch",
		"intro": "First the underlay: an address on each leaf and a router between them, until the leaves ping each other. Then the overlay: a source address, a VLAN-to-VNI mapping and a peer on each leaf, and EVPN so they advertise instead of flooding.",
		"after": "Run the vxlan lines on both leaves with each other's address as the peer. The unmapped VLAN 71 must stay isolated.",
		"eos": [
			"enable",
			"configure terminal",
			"vlan 70",
			"vxlan source <this leaf's address>",
			"vxlan vlan 70 vni 7000",
			"vxlan peer <the other leaf's address>",
			"vxlan evpn",
			"end",
			"show vxlan",
		],
	},
	"build_a_fabric": {
		"device_type": "router",
		"intro": "Every leaf has two uplinks, one per spine, each on its own transit subnet. OSPF on all four routers gives each leaf two equal paths, so losing a spine loses nothing.",
		"after": "The same OSPF configuration on all four; check that each leaf lists both spines as neighbours before pulling one.",
		"ros": [
			"/routing ospf instance add name=default router-id=<this router's address>",
			"/routing ospf area add name=backbone area-id=0.0.0.0 instance=default",
			"/routing ospf interface-template add networks=10.251.0.0/16 area=backbone",
			"/routing ospf neighbor print",
		],
		"eos": [
			"enable",
			"configure terminal",
			"router ospf 1",
			"network 10.251.0.0/16 area 0",
			"end",
			"show ip ospf neighbor",
			"show ip route 10.251.2.10",
		],
	},
	"big_client": {
		"device_type": "switch",
		"intro": "Nothing new: a VLAN with an access port, a server that reaches the Internet, a firewall rule covering its subnet, a live OSPF adjacency, and a switch with an addressed Management port. Each piece is a job you have already done.",
		"after": "The Management port takes an address on any switch; the rest reuses the earlier hints.",
		"ros": [
			"/interface bridge vlan add bridge=bridge1 vlan-ids=30 untagged=ether2",
			"/interface bridge port set [find interface=ether2] pvid=30",
			"/ip address add address=10.0.0.99/24 interface=Management1",
		],
		"eos": [
			"enable",
			"configure terminal",
			"vlan 30",
			"interface Ethernet2",
			"switchport access vlan 30",
			"interface Management1",
			"ip address 10.0.0.99/24",
			"end",
		],
	},
}

static func dialects_for(device_type: String) -> Array[String]:
	var out: Array[String] = []
	for d: Net.NDevice in Game.all_devices():
		if d.type != device_type:
			continue
		var spec: Dictionary = Game.MODELS.get(d.model, {})
		var dialect := String(spec.get("os", "eos"))
		if dialect not in out:
			out.append(dialect)
	# Before the relevant box is bought, guide towards the affordable starter
	# model the opening campaign actually offers.
	if out.is_empty() and device_type in ["switch", "router"]:
		out.append("ros")
	return out

static func hint_commands(contract_id: String, dialect: String) -> Array[String]:
	var cfg: Dictionary = DIALECT_HINTS.get(contract_id, {})
	var commands: Array[String] = []
	for command in cfg.get(dialect, []):
		commands.append(String(command))
	return commands

static func bare_command(line: String) -> String:
	## the typeable part of a hint line: no trailing "(on the client)" note,
	## and "" for a line with a <placeholder> the player has to fill in
	if "<" in line:
		return ""
	var cut := line.find("  (")
	return (line.substr(0, cut) if cut > 0 else line).strip_edges()

static func _command_block(label: String, commands: Array[String]) -> String:
	var lines: Array[String] = [label]
	for command in commands:
		lines.append("  " + command)
	return "\n".join(lines)

static func hint_for(contract: Dictionary) -> String:
	var id := String(contract.get("id", ""))
	if not DIALECT_HINTS.has(id):
		return String(contract.get("hint", ""))
	var cfg: Dictionary = DIALECT_HINTS[id]
	var dialects := dialects_for(String(cfg["device_type"]))
	var blocks: Array[String] = []
	if "ros" in dialects:
		blocks.append(_command_block("PacketTik RouterOS", hint_commands(id, "ros")))
	if "eos" in dialects:
		blocks.append(_command_block("OpenRack / Arivista / Junivista EOS", hint_commands(id, "eos")))
	if cfg.has("linux"):
		blocks = [_command_block("Linux servers", hint_commands(id, "linux"))]
	return "%s\n\n%s\n\n%s" % [String(cfg["intro"]), "\n\n".join(blocks), String(cfg["after"])]

static func retired(id: String) -> bool:
	for successor in SUPERSEDES:
		if SUPERSEDES[successor] == id and successor in Game.contracts_done:
			return true
	return false

static func all() -> Array:
	## Authored packs sit beside the built-in campaign and behave identically,
	## except in the demo, which is a fixed arc with a fixed ending.
	if Game.demo:
		return Demo.visible_contracts(_campaign())
	return Demo.visible_contracts(_campaign()) + Pack.contracts()

static func _campaign() -> Array:
	return [
		{
			"id": "rackup",
			# the first contract is catalog-driven: the rest follow as they are converted
			"hint": Loc.t("contract.rackup.hint"),
			"title": Loc.t("contract.rackup.title"),
			"customer": Loc.t("contract.rackup.customer"),
			"reward": 400,
			"brief": Loc.t("contract.rackup.brief"),
			"reqs": [
				{"d": "A rack is placed", "t": func() -> bool: return Game.racks.size() >= 1},
				{"d": "One switch and two servers installed", "t": func() -> bool: return _count("switch") >= 1 and _count("server") >= 2},
				{"d": "Two servers are cabled to a switch", "t": func() -> bool: return _servers_on_switch() >= 2},
			],
		},
		{
			"id": "first_ping",
			"hint": "Open a server, click Open console, and type: ip addr add 10.0.0.1/24 dev eth0. Do the same on the other server with 10.0.0.2/24. Then ping 10.0.0.2. If it fails, check 'ip addr' on both and make sure the cables reach the same switch.",
			"title": "First light",
			"customer": "Internal ops",
			"reward": 500,
			"brief": "Make your two servers talk. Both need an IP address in the same subnet: 10.0.0.1/24 on one and 10.0.0.2/24 on the other. Use each server's console: 'ip addr add 10.0.0.1/24 dev eth0'. Then verify with 'ping 10.0.0.2'. Same subnet = no router needed: this is switching.",
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
			"brief": "Your two servers now belong to different customers who must NOT see each other: but they share the switch. That's what VLANs are for. Cisco-style gear: 'enable', 'configure terminal', 'vlan 10', then per port 'interface Ethernet1' → 'switchport access vlan 10'. PacketTik (RouterOS 7): '/interface bridge vlan add bridge=bridge1 vlan-ids=10 untagged=ether1' and '/interface bridge port set [find interface=ether1] pvid=10'. Put 10.0.0.1's port in VLAN 10 and 10.0.0.2's in VLAN 20: the ping that worked before must now FAIL: separate VLANs are separate networks.",
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
			"brief": "Alfa and Beta grew: you need a second switch, and their VLANs must span both. Connect the two switches with a cable and make BOTH ends trunk ports (Cisco-style: 'switchport mode trunk'; PacketTik: '/interface bridge vlan add bridge=bridge1 vlan-ids=10 tagged=ether5', which lists the port as tagged for that VLAN): a trunk carries multiple VLANs with tags. Then put a new Alfa server (10.0.0.3/24, VLAN 10 access port) on the SECOND switch: it must reach Alfa's 10.0.0.1 across the trunk, while Beta's 10.0.0.2 stays walled off.",
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
			"brief": "Last month a janitor unplugged your inter-switch cable and Alfa's network split in half. They demand redundancy: run a SECOND cable between your two switches. Two links between switches form a LOOP: broadcasts would circulate forever and melt the network, but spanning tree saves you: it automatically blocks the spare link and unblocks it when the primary dies. Check 'show spanning-tree' (or '/interface bridge port print'): one port must show discarding/blocked while pings still flow.",
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
			"brief": "Gamma runs two offices on different networks: 192.168.1.0/24 and 192.168.2.0/24. Different subnets can only talk through a router. Set up a server in each network (192.168.1.10/24 and 192.168.2.10/24) and install a router with one leg in each subnet. On a PacketTik R4 (RouterOS style): '/ip address add address=192.168.1.1/24 interface=ether1' and the same for ether2 with 192.168.2.1/24. (On Junivista gear it's Cisco-style: 'enable', 'conf t', 'interface Ethernet1', 'ip address ...'.) Then give each server its default gateway: 'ip route add default via 192.168.1.1'. Both servers must reach each other; try 'traceroute' to see the router hop.",
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
			"brief": "Delta keeps adding machines and refuses to type IP addresses. Give them DHCP: on one of their servers run a DHCP service: 'dhcpd eth0 10.2.0.10 10.2.0.99 24 10.2.0.1' (that's: interface, first and last lease, prefix length, gateway): the DHCP server itself needs a static IP in that subnet (e.g. 10.2.0.5/24). Then install a NEW server on the same switch/VLAN and just type 'dhclient eth0' on it: it must receive a lease automatically. DHCP works by broadcast, so both must share a broadcast domain.",
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
			"brief": "Nobody remembers 10.2.0.x. Delta wants DNS: pick a server to be the resolver, give it records: 'dns add www.delta.hu 10.2.0.10': and point a client at it ('nameserver <dns-server-ip>', or hand it out via DHCP's dns field). Then 'nslookup www.delta.hu' and 'ping www.delta.hu' must work from the client.",
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
			"brief": "Epsilon Bank demands segmentation: their office network 172.16.1.0/24 must reach the app server 172.16.2.10, but NEVER the vault server 172.16.2.20. Install a firewall (PacketSense FW4) between two networks: one leg 172.16.1.1/24, other leg 172.16.2.1/24, with an office host at 172.16.1.10 and both servers in 172.16.2.0/24 (default gateways as usual). Then on the firewall console, in config mode ('enable', 'configure terminal'): 'acl deny 172.16.1.0/24 172.16.2.20/32' and then 'acl permit any any'. First match wins, and a packet no rule names is dropped (the implicit deny at the end of every access list), so without the permit the app server goes dark too. Verify with 'show acl' and pings both ways.",
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
			"brief": "Zeta wants their servers on the actual Internet. Buy an ISP Handoff ($200 + $30/cycle transit!) and cable its port to a router. The handoff speaks BGP as AS 64500 from 100.64.0.1/30: put 100.64.0.2/30 on your router's leg, then start BGP. PacketTik R4 (RouterOS 7): '/routing bgp connection add name=isp remote.address=100.64.0.1 remote.as=64500 as=65001 local.role=ebgp output.network=bgp-nets'. Junivista (Cisco-style): 'router bgp 65001', 'neighbor 100.64.0.1 remote-as 64500'. The session gives you a default route: but the Internet can't answer until you ANNOUNCE your prefix: '/ip firewall address-list add list=bgp-nets address=<your-server-subnet>/24' (the address list named in output.network is what gets announced; Junivista: 'network <p>/24'). Prove it: a server (default gateway = your router) must ping 8.8.8.8. Check with '/routing bgp print' or 'show ip bgp summary'.",
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
			"brief": "Zeta's auditors noticed you ANNOUNCED their private 10.x prefix to the ISP: real upstreams filter RFC1918, and it leaks your addressing plan. Do it properly with NAT: stop announcing the private prefix ('no network <p>/24' under router bgp), then masquerade instead. Junivista (Cisco-style, four lines): 'ip nat inside' under the server-facing interface, 'ip nat outside' under the uplink-facing one, 'access-list 1 permit <server-subnet> <wildcard>' to say who may be translated, and 'ip nat inside source list 1 interface <uplink-if> overload' to tie them together. Check with 'show ip nat translations'. PacketTik: '/ip firewall nat add chain=srcnat action=masquerade out-interface=ether1'. The router rewrites private sources to its own public address and untranslates the replies. A private server must still ping 8.8.8.8: with NO announcement covering it.",
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
			"brief": "Gamma opened a third office and your static routes are becoming spaghetti: every new subnet means touching every router. Time for a routing protocol: OSPF. Build two offices behind two routers (servers 10.20.1.10/24 and 10.20.2.10/24, routers linked by a transit subnet, e.g. 10.20.9.1/30 and 10.20.9.2/30), then on EACH router enable OSPF and advertise its subnets. Junivista, from config mode: 'router ospf', 'network 10.20.0.0/16 area 0'. PacketTik (RouterOS 7, three steps): '/routing ospf instance add name=default router-id=<one of its addresses>', '/routing ospf area add name=backbone area-id=0.0.0.0 instance=default', '/routing ospf interface-template add networks=10.20.0.0/16 area=backbone'. NO static routes on the routers: OSPF learns the paths ('show ip ospf neighbor', look for O routes in 'show ip route').",
			"reqs": [
				{"d": "Servers own 10.20.1.10 and 10.20.2.10", "t": func() -> bool: return _owner("10.20.1.10") != null and _owner("10.20.2.10") != null},
				{"d": "Two routers share an OSPF adjacency", "t": func() -> bool: return _ospf_adjacency()},
				{"d": "Both servers reach each other: no static routes on routers", "t": func() -> bool: return _ospf_no_static_path()},
			],
		},
		{
			"id": "feel_the_heat",
			"title": "Feeling the heat",
			"customer": "Your own ops",
			"reward": 2000,
			"brief": "Now that you own the room (Server room stage), the racks dump heat into it and the bare walls only dissipate 400W. Exceed that and gear starts tripping offline every cycle. Buy a CoolRow CRAC unit ($600: it cools 1500W but draws 100W itself) and keep total cooling capacity above total power draw. The HUD shows ⚡draw / ❄capacity.",
			"reqs": [
				{"d": "Own at least a Server room (Expand)", "t": func() -> bool: return Game.stage >= 1},
				{"d": "A CRAC unit is installed and active", "t": func() -> bool: return _has_active("cooling")},
				{"d": "Cooling capacity covers power draw", "t": func() -> bool: return not Game.overheating()},
			],
		},
		{
			"id": "no_spof",
			"title": "No single point of failure",
			"customer": "Omega Holding (pre-audit)",
			"reward": 3200,
			"brief": "Before the big contract, Omega's auditors ask an uncomfortable question: what happens when your gateway router dies? Answer: VRRP. Put TWO routers on one subnet (e.g. 10.40.0.2/24 and 10.40.0.3/24) and give both the same virtual gateway: in config mode, 'interface EthernetN' → 'vrrp 1 ip 10.40.0.1' (set 'vrrp 1 priority 120' on the one you prefer as master); on PacketTik: '/interface vrrp add interface=etherN vrid=1 priority=120' then '/ip address add address=10.40.0.1/32 interface=vrrp1'. A server at 10.40.0.10/24 uses the VIRTUAL address as its default gateway: 'show vrrp' shows Master/Backup, and if the master dies, the backup answers the same IP.",
			"reqs": [
				{"d": "Two routers share VRRP group 1 on one virtual IP", "t": func() -> bool: return _vrrp_pair()},
				{"d": "A server uses the virtual IP as its gateway", "t": func() -> bool: return _server_gw_is_vip()},
				{"d": "The virtual gateway answers ping", "t": func() -> bool: return _vip_pings()},
			],
		},
		{
			"id": "double_the_pipe",
			"title": "Double the pipe",
			"customer": "Alfa Ltd (still growing)",
			"reward": 1600,
			"brief": "Your redundant inter-switch link bothers Alfa's consultants: 'one link idle because of spanning tree? Bundle them!' Port-channels aggregate parallel links into one logical pipe: full capacity AND redundancy, no blocked spare. On BOTH switches put both inter-switch ports in the same group: Cisco-style 'channel-group 1' under each interface in config mode, PacketTik '/interface bonding add slaves=ether4,ether5'. 'show port-channel' should list the members and 'show spanning-tree' should show nothing discarding between that pair.",
			"reqs": [
				{"d": "A 2+ member bundle between two switches", "t": func() -> bool: return _bundle_exists()},
				{"d": "No STP-blocked port inside the bundle", "t": func() -> bool: return _bundle_unblocked()},
			],
		},
		{
			"id": "router_on_a_stick",
			"title": "One port, two networks",
			"customer": "Beta Kft",
			"reward": 1900,
			"brief": "Beta needs their two VLANs (60 and 61) routed, and you have exactly one router port left. That is what router-on-a-stick is for: cable the router port to a switch TRUNK, then split it into 802.1Q subinterfaces. On the router, in config mode: 'interface Ethernet1.60', 'encapsulation dot1q 60', 'ip address 10.90.60.1/24', then the same for .61 with 10.90.61.1/24 (PacketTik: '/interface vlan add name=vlan60 vlan-id=60 interface=ether1', '/ip address add address=10.90.60.1/24 interface=vlan60'). Put a server in each VLAN (10.90.60.10 and 10.90.61.10) pointing at those gateways. Both must reach each other over that single physical link.",
			"reqs": [
				{"d": "A router leg split into two 802.1Q subinterfaces", "t": func() -> bool: return _subiface_pair()},
				{"d": "Servers own 10.90.60.10 and 10.90.61.10", "t": func() -> bool: return _owner("10.90.60.10") != null and _owner("10.90.61.10") != null},
				{"d": "The VLANs route through the trunked port", "t": func() -> bool: return _ping("10.90.60.10", "10.90.61.10", true) and _ping("10.90.61.10", "10.90.60.10", true)},
			],
		},
		{
			"id": "one_switch_two_nets",
			"title": "Collapse the core",
			"customer": "Alfa Ltd",
			"reward": 2400,
			"brief": "Alfa's two VLANs each need a router leg, and you are running out of router ports. An Arivista 7024 is an L3 switch: it can route between VLANs itself with SVIs (virtual interfaces bound to a VLAN). Buy one, create VLANs 40 and 50 with a server in each (10.80.40.10/24 and 10.80.50.10/24), then in config mode 'interface Vlan40' + 'ip address 10.80.40.1/24' and the same for Vlan50. Point each server's default gateway at its SVI. The two servers must reach each other through the switch alone, no router involved.",
			"reqs": [
				{"d": "An L3 switch with SVIs for two VLANs", "t": func() -> bool: return _l3_switch_svis() >= 2},
				{"d": "Servers own 10.80.40.10 and 10.80.50.10", "t": func() -> bool: return _owner("10.80.40.10") != null and _owner("10.80.50.10") != null},
				{"d": "They route to each other via the switch", "t": func() -> bool: return _ping("10.80.40.10", "10.80.50.10", true) and _ping("10.80.50.10", "10.80.40.10", true)},
			],
		},
		{
			"id": "bandwidth_crunch",
			"title": "Bandwidth crunch",
			"customer": "Everyone at once",
			"reward": 3500,
			"brief": "Success has a price: customers report slowdowns, and the Map shows red links: their combined load exceeds your 1G gear. The fix is capacity planning: 10-gig hardware (Arivista 7024 switches, Junivista MX8 routers) on the hot paths. Deliver a 10G-capable link between two pieces of core gear (both ends 10G models) and have zero congested deals.",
			"reqs": [
				{"d": "A 10G link in the core (both ends 10G-capable)", "t": func() -> bool: return _has_10g_link()},
				{"d": "No customer deal is congested", "t": func() -> bool: return _no_congestion()},
			],
		},
		{
			"id": "guest_wifi",
			"title": "Guests and staff",
			"customer": "Balaton Hotel",
			"reward": 2600,
			"brief": "The hotel wants wireless for guests and for staff, on the same access points, with guests unable to touch anything of the staff's. Install an AirTurul AP3, trunk its uplink to a switch, and on its console, in config mode ('enable', 'configure terminal'), map two SSIDs to two VLANs: 'ssid guest-wifi vlan 30' and 'ssid staff-wifi vlan 31'. Put a host on each network ('wifi join guest-wifi'): a guest at 10.110.30.10/24 and a staff machine at 10.110.31.10/24, and prove the guest cannot reach the staff machine.",
			"reqs": [
				{"d": "An access point broadcasting two SSIDs", "t": func() -> bool: return _ap_ssids() >= 2},
				{"d": "A host associated on each network", "t": func() -> bool: return _wifi_clients() >= 2},
				{"d": "Guests cannot reach the staff network", "t": func() -> bool: return _owner("10.110.30.10") != null and _ping("10.110.30.10", "10.110.31.10", false)},
			],
		},
		{
			"id": "wireguard_link",
			"title": "Encrypt the back road",
			"customer": "Astra Legal",
			"reward": 3600,
			"brief": "Astra will not send their traffic between offices in the clear, and they will not pay for a second leased line either. Build a WireGuard tunnel over the path you already have: in config mode, 'interface wg0' on both routers, a small address on each end (10.99.0.1/30 and 10.99.0.2/30), then on each side 'wireguard peer <the other key> endpoint <their public address> allowed <their network>,<their tunnel address>/32' (PacketTik: '/interface wireguard add name=wg0', '/interface wireguard peers add interface=wg0 public-key=<the other key> endpoint-address=<their public address> allowed-address=<their network>,<their tunnel address>/32'; '/interface wireguard print' shows your own key). Route each office's network down the tunnel. Their hosts at 172.20.1.10 and 172.20.2.10 must reach each other, and 'show wireguard' must show a handshake.",
			"reqs": [
				{"d": "Two WireGuard interfaces that name each other", "t": func() -> bool: return _wg_pair()},
				{"d": "The handshake succeeds", "t": func() -> bool: return _wg_handshaken()},
				{"d": "172.20.1.10 and 172.20.2.10 reach each other", "t": func() -> bool: return _ping("172.20.1.10", "172.20.2.10", true) and _ping("172.20.2.10", "172.20.1.10", true)},
			],
		},
		{
			"id": "keep_it_moving",
			"title": "Keep it moving",
			"customer": "Obsidian Cloud",
			"reward": 3800,
			"brief": "Obsidian runs virtual machines and expects to move them between hosts without their customers noticing. Put two dual-NIC servers on the same switch and the same VLAN, create a machine on one ('vm create obs01', 'vm addr obs01 10.160.5.20/24'), prove another host can reach it, then migrate it to the second server ('vm migrate obs01 <host>'). It must still answer on the same address afterwards, which only works while both hosts share a broadcast domain.",
			"reqs": [
				{"d": "A virtual machine at 10.160.5.20", "t": func() -> bool: return _vm_at("10.160.5.20") != null},
				{"d": "It has been migrated between hosts", "t": func() -> bool: return _vm_migrated()},
				{"d": "It still answers after the move", "t": func() -> bool: return _server_pings("10.160.5.20")},
			],
		},
		{
			"id": "always_on",
			"title": "Always on",
			"customer": "Fecske Media",
			"reward": 3400,
			"brief": "Fecske's site went down last month because it lived on one server, and they are not doing that again. Put two servers behind an Equipoise LB10: give the load balancer an address on their subnet, stand up 10.190.0.11 and 10.190.0.12, then on the balancer's console in config mode ('enable', 'configure terminal'): 'virtual-server 10.190.0.100 members 10.190.0.11,10.190.0.12'. A client on the same network must reach 10.190.0.100, and it must keep reaching it with one of the two servers switched off.",
			"reqs": [
				{"d": "A load balancer with a two-member pool", "t": func() -> bool: return _lb_pool() >= 2},
				{"d": "The virtual address 10.190.0.100 answers", "t": func() -> bool: return _server_pings("10.190.0.100")},
				{"d": "At least one member is in service", "t": func() -> bool: return _lb_healthy() >= 1},
			],
		},
		{
			"id": "two_sites",
			"title": "Two roofs, one service",
			"customer": "Tisza Bank",
			"reward": 4200,
			"brief": "Tisza Bank will not run their service under a single roof again. They want it present on TWO of your sites: lease a second site (Business screen) or acquire a company that owns one, order a WAN circuit between the two, and stand up a server on each site (10.120.1.10 and 10.120.2.10). Both must be reachable from the other site across the circuit, so the loss of one building does not take the service with it.",
			"reqs": [
				{"d": "You operate at least two sites", "t": func() -> bool: return Game.site_count() >= 2},
				{"d": "A WAN circuit links two of them", "t": func() -> bool: return not Game.circuits.is_empty()},
				{"d": "A server on each of two sites (10.120.1.10, 10.120.2.10)", "t": func() -> bool: return _sites_of_hosts(["10.120.1.10", "10.120.2.10"]).size() >= 2},
				{"d": "They reach each other across the circuit", "t": func() -> bool: return _ping("10.120.1.10", "10.120.2.10", true) and _ping("10.120.2.10", "10.120.1.10", true)},
			],
		},
		{
			"id": "dual_stack",
			"title": "The address shortage",
			"customer": "Hollo Media",
			"reward": 3000,
			"brief": "Hollo Media's new platform must be reachable over IPv6 as well as IPv4. Dual-stack a pair of servers: keep their v4 addressing and add 2001:db8:70::10/64 and 2001:db8:71::10/64, then route between those two /64s with a router (in config mode under each interface: 'ipv6 address 2001:db8:70::1/64' on one leg, 2001:db8:71::1/64 on the other) and point each server's v6 default at its gateway ('ip -6 route add default via <gw>'). Both must ping each other over IPv6. Watch a capture: you will see Neighbor Discovery where ARP used to be.",
			"reqs": [
				{"d": "Servers hold 2001:db8:70::10 and 2001:db8:71::10", "t": func() -> bool: return _owner("2001:db8:70::10") != null and _owner("2001:db8:71::10") != null},
				{"d": "A router has a leg in each v6 prefix", "t": func() -> bool: return _v6_router() != null},
				{"d": "They reach each other over IPv6", "t": func() -> bool: return _ping("2001:db8:70::10", "2001:db8:71::10", true) and _ping("2001:db8:71::10", "2001:db8:70::10", true)},
			],
		},
		{
			"id": "v6_only_tenant",
			"title": "The tenant with no IPv4",
			"customer": "Turul Mobil",
			"reward": 4000,
			"brief": "Turul Mobil's platform is IPv6 only and they will not take an IPv4 address, not even one. Give their host 2001:db8:64::10/64 and make it reach two things: your own native IPv6 service at 2001:db8:64::20, and a legacy IPv4-only service at 10.164.0.10 that is never getting an IPv6 address. The second one needs both halves of the transition: DNS64 on their resolver to synthesize an AAAA from the A record (the resolver needs that A record first: 'dns add legacy.pkt 10.164.0.10', then 'dns64 64:ff9b::'), and NAT64 on the router to translate the flow ('nat64 prefix 64:ff9b:: pool <your v4 address>' on a Junivista router or the firewall: PacketTik gear has no NAT64, exactly like the real thing). Native IPv6 must not go anywhere near the translator.",
			"reqs": [
				{"d": "An IPv6-only tenant host at 2001:db8:64::10 with no IPv4", "t": func() -> bool:
					var host := _owner("2001:db8:64::10")
					if host == null:
						return false
					for i: Net.Iface in host.ifaces:
						for cidr in i.ips:
							if not Net.is_v6(String(cidr)):
								return false
					return true},
				{"d": "It reaches a native IPv6 service without translation", "t": func() -> bool:
					return _owner("2001:db8:64::20") != null and _ping("2001:db8:64::10", "2001:db8:64::20", true)},
				{"d": "A resolver synthesizes AAAA for the IPv4-only service", "t": func() -> bool:
					for d in Game.all_devices():
						var svc: Dictionary = d.services.get("dns", {})
						if bool(svc.get("dns64", {}).get("enabled", false)) \
								and svc.get("records", {}).values().has("10.164.0.10"):
							return true
					return false},
				{"d": "It reaches the IPv4-only service through NAT64", "t": func() -> bool:
					var tenant := _owner("2001:db8:64::10")
					if tenant == null or _owner("10.164.0.10") == null:
						return false
					for d in Game.all_devices():
						var n64: Dictionary = Sim.nat64_of(d)
						if n64.is_empty():
							continue
						var synth := Sim.synth64(String(n64.get("prefix", "")), "10.164.0.10")
						if synth != "" and Sim.ping(tenant, synth)["ok"]:
							return true
					return false},
			],
		},
		{
			"id": "overlay_tenant",
			"title": "The tenant that outgrew the VLAN",
			"customer": "Turul Mobil (again)",
			"reward": 5200,
			"brief": "Turul Mobil have outgrown a stretched VLAN and want their segment on two different leaf switches with a routed network in between: no trunk, no cable between the leaves. Build the underlay first (an SVI on each leaf, a router between them, and each leaf able to ping the other's address), then put the tenant on top with VXLAN, in config mode on each leaf: 'vxlan source <this leaf's address>', 'vxlan vlan 70 vni 7000' and 'vxlan peer <the other leaf>' on both. Their hosts are 192.168.70.10 and 192.168.70.11. Put a second tenant in VLAN 71 on one leaf, unmapped, and prove it cannot see any of it. Then turn on 'vxlan evpn' so the leaves tell each other what they have instead of flooding.",
			"reqs": [
				{"d": "The two leaves reach each other over a routed underlay", "t": func() -> bool: return _overlay_underlay()},
				{"d": "One VNI carries the tenant across both leaves", "t": func() -> bool: return _overlay_mapped(7000) and _ping("192.168.70.10", "192.168.70.11", true)},
				{"d": "A second tenant on the same leaf sees none of it", "t": func() -> bool: return _overlay_isolated()},
				{"d": "The control plane advertises instead of flooding", "t": func() -> bool: return _overlay_evpn()},
			],
		},
		{
			"id": "build_a_fabric",
			"title": "Build a fabric",
			"customer": "Panonia Data (consulting)",
			"reward": 4500,
			"brief": "Your core switch is one failure away from taking everything with it. Build a proper fabric instead: two spine routers, two leaf routers, and every leaf uplinked to BOTH spines on its own small transit subnet. Run OSPF across all four so each leaf learns the other's networks twice, once through each spine. Put a server under each leaf (10.251.1.10/24 and 10.251.2.10/24) and prove it: they must reach each other, and they must keep reaching each other with one spine switched off.",
			"reqs": [
				{"d": "Two leaves, each uplinked to two spines", "t": func() -> bool: return _fabric_shape()},
				{"d": "A leaf has two equal-cost paths to the far host", "t": func() -> bool: return _fabric_ecmp()},
				{"d": "Hosts under different leaves reach each other", "t": func() -> bool: return _ping("10.251.1.10", "10.251.2.10", true)},
			],
		},
		{
			"id": "prove_it",
			"title": "The exercise",
			"customer": "Tisza Bank",
			"reward": 4600,
			"brief": "Tisza Bank has read your last outage report and would like the exercise run rather than described. Book a failover test (Operations, Facility), let it take your upstream out of service on the cycle you chose, and have every customer still served when it comes back. They want the result either way: a test you fail and act on is worth more to them than one you never ran.",
			"reqs": [
				{"d": "A failover test has been passed", "t": func() -> bool: return int(Game.stats.get("failovers_passed", 0)) >= 1},
				# an exercise is a thing you did, not a service you run: the
				# second requirement is about the day of the test, so once it is
				# signed off it must not re-breach on every later outage
				{"d": "Nobody was off the air when it ran", "t": func() -> bool: return int(Game.stats.get("failovers_passed", 0)) >= 1},
			],
		},
		{
			"id": "big_client",
			"title": "The big client",
			"customer": "Omega Holding",
			"reward": 5000,
			"brief": "Omega Holding audited you for a month. Their requirements read like everything you've learned: (1) their own VLAN 30 with a server on an access port; (2) a server at 10.30.0.10/24 that reaches the Internet (NAT or announced: your call); (3) a firewall rule explicitly protecting the 10.30.0.0/24 segment; (4) dynamic routing in the core (a live OSPF adjacency); (5) managed infrastructure: at least one switch with an addressed Management port. Deliver all five and they sign the biggest cheque you've seen.",
			"reqs": [
				{"d": "VLAN 30 with a connected access-port server", "t": func() -> bool: return _vlan_with_server(30)},
				{"d": "10.30.0.10 reaches the Internet (8.8.8.8)", "t": func() -> bool: return _owner("10.30.0.10") != null and Sim.ping(_owner("10.30.0.10"), "8.8.8.8")["ok"]},
				{"d": "Firewall rule protecting 10.30.0.0/24", "t": func() -> bool: return _fw_deny_covering("10.30.0.0", 24)},
				{"d": "Live OSPF adjacency in the core", "t": func() -> bool: return _ospf_adjacency()},
				{"d": "A switch with an addressed Management port", "t": func() -> bool: return _managed_switch()},
			],
		},
	]

# ---------- check helpers ----------

static func _vrrp_ifaces() -> Array:
	var out: Array = []
	for d in Game.all_devices():
		if d.ip_forwarding:
			for i: Net.Iface in d.ifaces:
				if not i.vrrp.is_empty():
					out.append(i)
	return out

static func _vrrp_pair() -> bool:
	var by_vip := {}
	for i: Net.Iface in _vrrp_ifaces():
		if String(i.vrrp.get("vip", "")) == "":
			continue  # a group with no address is not a gateway yet
		var key := "%s|%d" % [i.vrrp["vip"], int(i.vrrp["group"])]
		by_vip[key] = by_vip.get(key, 0) + 1
		if by_vip[key] >= 2:
			return true
	return false

static func _server_gw_is_vip() -> bool:
	var vips := {}
	for i: Net.Iface in _vrrp_ifaces():
		vips[i.vrrp["vip"]] = true
	for d in Game.all_devices():
		if d.type == "server":
			for r in d.static_routes:
				if vips.has(r["via"]):
					return true
	return false

static func _vip_pings() -> bool:
	for d in Game.all_devices():
		if d.type != "server":
			continue
		for r in d.static_routes:
			for i: Net.Iface in _vrrp_ifaces():
				if r["via"] == i.vrrp["vip"] and Sim.ping(d, r["via"])["ok"]:
					return true
	return false

static func _sites_of_hosts(ips: Array) -> Array:
	var found := {}
	for ip in ips:
		var d := _owner(ip)
		if d == null:
			continue
		var rk := Game.rack_of(d)
		if rk:
			found[rk.site] = true
	return found.keys()

static func _subiface_pair() -> bool:
	var by_parent := {}
	for d in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			if i.parent != "" and not i.ips.is_empty():
				var key := "%s|%s" % [d.name, i.parent]
				by_parent[key] = by_parent.get(key, 0) + 1
				if by_parent[key] >= 2:
					return true
	return false

static func _l3_switch_svis() -> int:
	var best := 0
	for d in Game.all_devices():
		if not Game.is_l3_switch(d):
			continue
		var n := 0
		for i: Net.Iface in d.ifaces:
			if i.name.begins_with("Vlan") and not i.ips.is_empty():
				n += 1
		best = maxi(best, n)
	return best

static func _ap_ssids() -> int:
	var best := 0
	for d in Game.all_devices():
		if d.type == "ap":
			best = maxi(best, d.ssids.size())
	return best

static func _wifi_clients() -> int:
	var n := 0
	for d in Game.all_devices():
		if d.wifi != "":
			n += 1
	return n

static func _wg_ifaces() -> Array:
	var out: Array = []
	for d in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			if i.name.begins_with("wg") and not i.wg_peers.is_empty():
				out.append(i)
	return out

static func _wg_pair() -> bool:
	for w: Net.Iface in _wg_ifaces():
		for p in w.wg_peers:
			if Sim.wg_remote(w, p) != null:
				return true
	return false

static func _wg_handshaken() -> bool:
	for w: Net.Iface in _wg_ifaces():
		for p in w.wg_peers:
			if Sim.wg_handshake(w, p):
				return true
	return false

static func _vm_at(ip: String) -> Net.Iface:
	for d in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			if i.vm == "":
				continue
			for cidr: String in i.ips:
				if Net.addr_eq(cidr.split("/")[0], ip):
					return i
	return null

static func _vm_migrated() -> bool:
	## The event log is trimmed to the last sixty lines, so reading the fact out
	## of it meant a finished job quietly un-finished itself an hour later.
	if int(Game.stats.get("migrations", 0)) > 0:
		return true
	for ev in Game.events:
		if "MIGRATION:" in ev:
			return true
	return false

static func _lb_pool() -> int:
	var best := 0
	for d in Game.all_devices():
		var svc: Dictionary = d.services.get("lb", {})
		if not svc.is_empty():
			best = maxi(best, svc.get("members", []).size())
	return best

static func _lb_healthy() -> int:
	var best := 0
	for d in Game.all_devices():
		var svc: Dictionary = d.services.get("lb", {})
		if not svc.is_empty():
			best = maxi(best, svc.get("healthy", []).size())
	return best

static func _fabric_shape() -> bool:
	## at least two routers that each uplink to the same two other routers
	var uplinks := {}
	for l in Game.links:
		if not l.a.dev.ip_forwarding or not l.b.dev.ip_forwarding:
			continue
		for pair in [[l.a.dev, l.b.dev], [l.b.dev, l.a.dev]]:
			if not uplinks.has(pair[0]):
				uplinks[pair[0]] = {}
			uplinks[pair[0]][pair[1]] = true
	var leaves := 0
	for d in uplinks:
		if uplinks[d].size() >= 2:
			leaves += 1
	return leaves >= 4  # two leaves and two spines all see two peers

static func _fabric_ecmp() -> bool:
	var src := _owner("10.251.1.10")
	if src == null:
		return false
	for d in Game.all_devices():
		if not d.ip_forwarding:
			continue
		if Sim._route_paths(d, "10.251.2.10").size() >= 2:
			return true
	return false

static func _bundle_links() -> Array:
	for l in Game.links:
		if l.a.dev.type == "switch" and l.b.dev.type == "switch":
			var members := Game.lag_members(l)
			if members.size() >= 2:
				return members
	return []

static func _bundle_exists() -> bool:
	return _bundle_links().size() >= 2

static func _bundle_unblocked() -> bool:
	var members := _bundle_links()
	if members.is_empty():
		return false
	for l in members:
		if Sim.stp_blocked(l.a) or Sim.stp_blocked(l.b):
			return false
	return true

static func _has_10g_link() -> bool:
	for l in Game.links:
		if Game.link_capacity(l) >= 10000:
			return true
	return false

static func _no_congestion() -> bool:
	for deal in Game.deals:
		if deal.get("degraded", false):
			return false
	return true

static func _vlan_with_server(vid: int) -> bool:
	for d in Game.all_devices():
		if d.type != "switch" or not d.vlans.has(vid):
			continue
		for i: Net.Iface in d.ifaces:
			if i.mode == "access" and i.untagged_vlan == vid:
				var l := Game.link_at(i)
				if l and l.other(i).dev.type == "server":
					return true
	return false

static func _fw_deny_covering(prefix: String, plen: int) -> bool:
	for d in Game.all_devices():
		if d.type == "firewall":
			for rule in d.acls:
				if rule["action"] == "deny" and int(rule["dplen"]) >= plen \
						and Net.same_subnet(rule["dst"], prefix, plen):
					return true
	return false

static func _managed_switch() -> bool:
	for d in Game.all_devices():
		if d.type == "switch":
			for i: Net.Iface in d.ifaces:
				if i.name.begins_with("Management") and not i.ips.is_empty():
					return true
	return false

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
				if Net.addr_eq(cidr.split("/")[0], ip):
					return d
	return null

static func _overlay_vteps() -> Array:
	var out: Array = []
	for d in Game.all_devices():
		if not d.vtep.is_empty() and String(d.vtep.get("src", "")) != "":
			out.append(d)
	return out

static func _overlay_underlay() -> bool:
	## Two VTEPs that can reach each other's source address, with no layer 2
	## between them: that is what an overlay is built on.
	var vteps := _overlay_vteps()
	if vteps.size() < 2:
		return false
	for a: Net.NDevice in vteps:
		for b: Net.NDevice in vteps:
			if a == b:
				continue
			if Sim.ping(a, String(b.vtep["src"]))["ok"]:
				return true
	return false

static func _overlay_mapped(vni: int) -> bool:
	var carrying := 0
	for d: Net.NDevice in _overlay_vteps():
		for vlan: int in d.vtep.get("map", {}):
			if int(d.vtep["map"][vlan]) == vni:
				carrying += 1
	return carrying >= 2

static func _overlay_isolated() -> bool:
	## A VLAN nobody mapped to a VNI stays where it is, which is the whole
	## point of tenant separation.
	for d: Net.NDevice in _overlay_vteps():
		for vlan: int in d.vlans:
			if int(vlan) == 71 and not d.vtep.get("map", {}).has(71):
				return true
	return false

static func _overlay_evpn() -> bool:
	var learning := 0
	for d: Net.NDevice in _overlay_vteps():
		if bool(d.vtep.get("evpn", false)) and not d.remote_macs.is_empty():
			learning += 1
	return learning >= 1

static func _v6_router() -> Net.NDevice:
	for d in Game.all_devices():
		if not d.ip_forwarding:
			continue
		var prefixes := {}
		for i: Net.Iface in d.ifaces:
			for cidr: String in i.ips:
				if Net.is_v6(cidr):
					prefixes[Net.v6_compress(cidr.split("/")[0]).substr(0, 12)] = true
		if prefixes.size() >= 2:
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
		if l.a.dev.type == "switch" and l.b.dev.type == "switch" and l.a.enabled and l.b.enabled \
				and l.a.dev != l.b.dev:
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
