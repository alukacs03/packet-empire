class_name Sim
## Packet-level network simulation. Frames propagate synchronously through
## the topology: switches learn MACs and flood/forward per VLAN, hosts and
## routers run a small IP stack (ARP, ICMP, TTL, static routing).
##
## Frame: {src, dst, vlan, type: "arp"|"ipv4", pl: Dictionary}
##   vlan 0 = untagged on the wire; switches assign the bridging VLAN.
## ARP pl:  {op: "req"|"rep", spa, sha, tpa}
## IPv4 pl: {src_ip, dst_ip, ttl, l4: {proto: "icmp"|"dns", ...}}
## DHCP pl: {op: "discover"|"ack", mac, ...lease fields}: pure L2 broadcast

const BCAST := "ff:ff:ff:ff:ff:ff"
const MCAST_PREFIX := "01:00:5e"
const MAX_DEPTH := 400  # flood guard for misconfigurations STP cannot see

static var _depth := 0
static var _echo_id := 0
static var _echo_results: Array = []
static var rtt_ms := 0.0  # accumulated latency of the operation in flight
static var last_trace: Array = []  # [{a: Iface, b: Iface, kind}] of the last operation
const DEFAULT_TTL := 4  # cycles a resolver is entitled to keep an answer
const MAX_REFERRALS := 4  # a delegation chain deeper than this is a loop

static func _delegation_for(zones: Dictionary, name: String) -> String:
	## the most specific delegated zone this name falls under
	var best := ""
	var best_len := -1
	for zone in zones:
		var z := String(zone)
		if (name == z or name.ends_with("." + z)) and z.length() > best_len:
			best_len = z.length()
			best = String(zones[zone])
	return best

const STD_MTU := 1500
static var last_mtu_drop := ""  # why the last oversized frame did not arrive
static var _dns_results: Array = []
static var _dns_id := 0
static var _dhcp_offer := {}

# ---------- public operations ----------

static func ping(dev: Net.NDevice, dst_ip: String, ttl := 64, vrf := "", size := 64) -> Dictionary:
	## -> {ok: bool, from: String (replier), detail: String}
	## Re-entrant: a ping can happen inside another one (a tunnel checking its
	## underlay while carrying traffic), so the outer results are preserved.
	var outer_results := _echo_results
	var outer_trace := last_trace
	var outer_rtt := rtt_ms
	rtt_ms = 0.0
	_echo_id += 1
	_echo_results = []
	if _depth == 0:
		last_trace = []
		_reset_storm_counters()
	if _has_ip(dev, dst_ip):
		_echo_results = outer_results
		rtt_ms = outer_rtt
		return {"ok": true, "from": dst_ip, "detail": "", "rtt": 0.0}  # loopback: our own address
	var my_id := _echo_id
	if _depth == 0:
		last_mtu_drop = ""
	var err := _send_ip(dev, dst_ip, ttl,
		{"proto": "icmp", "type": "echo", "id": my_id, "size": size}, vrf)
	var result := {"ok": false, "from": "", "detail":
		last_mtu_drop if last_mtu_drop != "" else "timeout"}
	if err != "":
		result = {"ok": false, "from": "", "detail": err}
	else:
		for r in _echo_results:
			if r["id"] != my_id:
				continue
			if r["type"] == "reply":
				result = {"ok": true, "from": r["from"], "detail": "", "ttl": int(r.get("ttl", 64))}
				break
			if r["type"] == "ttl-exceeded":
				result = {"ok": false, "from": r["from"], "detail": "ttl-exceeded"}
				break
			if r["type"] == "unreachable":
				# a router said why, the way real ones do: net, host or admin
				result = {"ok": false, "from": r["from"], "detail": "unreachable-%s" % r.get("code", "net")}
				break
	result["rtt"] = rtt_ms
	_echo_results = outer_results
	if _depth > 0:
		last_trace = outer_trace  # a nested probe does not rewrite the animation
		rtt_ms = outer_rtt
	return result

static func traceroute(dev: Net.NDevice, dst_ip: String, max_hops := 16) -> Array:
	## -> array of hop strings ("10.0.0.1" or "*"), last is dst on success
	var hops: Array = []
	for ttl in range(1, max_hops + 1):
		var r := ping(dev, dst_ip, ttl)
		if r["ok"]:
			hops.append(r["from"])
			break
		if r["detail"] != "ttl-exceeded":
			# unreachable: the router that complained is usually the last hop
			# already listed, so do not print it twice
			if r["from"] != "" and (hops.is_empty() or hops.back() != r["from"]):
				hops.append(r["from"])
			elif r["from"] == "":
				hops.append("*")
			break
		hops.append(r["from"] if r["from"] != "" else "*")
	return hops

static func dhcp_request(dev: Net.NDevice, iface: Net.Iface) -> Dictionary:
	## Broadcast a DHCP discover on iface; a reachable DHCP server in the same
	## broadcast domain answers. On success the lease is applied to the iface.
	_dhcp_offer = {}
	if _depth == 0:
		last_trace = []
		_reset_storm_counters()
	_tx(iface, {"src": iface.mac, "dst": BCAST, "vlan": 0, "type": "dhcp",
		"pl": {"op": "discover", "mac": iface.mac}})
	if _dhcp_offer.is_empty():
		return {}
	Game.add_ip(iface, "%s/%d" % [_dhcp_offer["ip"], int(_dhcp_offer["plen"])])
	if _dhcp_offer.get("gw", "") != "":
		Game.add_static_route(dev, "0.0.0.0", 0, _dhcp_offer["gw"])
	if _dhcp_offer.get("dns", "") != "":
		dev.resolver = _dhcp_offer["dns"]
	return _dhcp_offer

static func _dhcp_rx(dev: Net.NDevice, iface: Net.Iface, frame: Dictionary) -> void:
	var p: Dictionary = frame["pl"]
	if p["op"] == "discover" and dev.ip_forwarding and iface.helper != "":
		# DHCP relay: forward the broadcast as unicast IP with giaddr
		_send_ip(dev, iface.helper, 64, {"proto": "dhcp-relay", "op": "discover",
			"mac": p["mac"], "giaddr": _first_ip(iface)})
		return
	if p["op"] == "discover":
		var svc: Dictionary = dev.services.get("dhcp", {})
		if svc.is_empty() or svc.get("iface", "") != iface.name:
			return
		var leases: Dictionary = svc["leases"]
		var ip: String
		if leases.has(p["mac"]):
			ip = leases[p["mac"]]
		else:
			var next := Net.ip_to_int(svc["start"]) + leases.size()
			if next > Net.ip_to_int(svc["end"]):
				return  # pool exhausted
			ip = "%d.%d.%d.%d" % [next >> 24 & 255, next >> 16 & 255, next >> 8 & 255, next & 255]
			leases[p["mac"]] = ip
		_tx(iface, {"src": iface.mac, "dst": p["mac"], "vlan": 0, "type": "dhcp",
			"pl": {"op": "ack", "mac": p["mac"], "ip": ip, "plen": svc["plen"],
				"gw": svc.get("gw", ""), "dns": svc.get("dns", "")}})
	elif p["op"] == "ack":
		for i: Net.Iface in dev.ifaces:
			if i.mac == p["mac"]:
				_dhcp_offer = p

static func reverse_lookup(dev: Net.NDevice, ip: String) -> String:
	## PTR-style: ask the resolver which name maps to this address
	if dev.resolver == "":
		return ""
	_dns_id += 1
	_dns_results = []
	_send_ip(dev, dev.resolver, 64, {"proto": "dns", "q": ip, "id": _dns_id})
	for r in _dns_results:
		if r["id"] == _dns_id and r["q"] == ip:
			return r["answer"]
	return ""

static var last_answer_kind := ""  # "native" | "cached" | "synthesized" | ""

static func synth64(prefix: String, v4: String) -> String:
	## A DNS64 answer is the NAT64 prefix with the IPv4 address embedded in it,
	## which is why the result is deterministic and readable.
	if not prefix.ends_with("::") or Net.is_v6(v4) or not v4.is_valid_ip_address():
		return ""
	var octets := v4.split(".")
	if octets.size() != 4:
		return ""
	# the four octets become the last two groups, which is what RFC 6052 does
	var synth := "%s%x:%x" % [prefix,
		int(octets[0]) * 256 + int(octets[1]), int(octets[2]) * 256 + int(octets[3])]
	return synth if synth.is_valid_ip_address() else ""

static func extract64(prefix: String, v6: String) -> String:
	## The inverse of synth64: pull the embedded IPv4 address back out.
	if not prefix.ends_with("::") or not Net.is_v6(v6):
		return ""
	var head := prefix.trim_suffix("::")
	if not v6.begins_with(head + "::"):
		return ""
	var tail := v6.substr((head + "::").length())
	var groups := tail.split(":")
	if groups.size() != 2:
		return ""
	var hi := ("0x" + String(groups[0])).hex_to_int()
	var lo := ("0x" + String(groups[1])).hex_to_int()
	if hi < 0 or lo < 0 or hi > 65535 or lo > 65535:
		return ""
	return "%d.%d.%d.%d" % [hi / 256, hi % 256, lo / 256, lo % 256]

static func nat64_of(dev: Net.NDevice) -> Dictionary:
	return dev.services.get("nat64", {})

static func resolve(dev: Net.NDevice, name: String, use_cache := true, want_v6 := false) -> String:
	## DNS lookup via the device's configured resolver, following delegations
	## the way a real resolver does, and honouring the TTL it was given.
	last_answer_kind = ""
	if name.is_valid_ip_address():
		return name
	var cache_key := ("6|" if want_v6 else "") + name
	if use_cache:
		var hit: Dictionary = dev.dns_cache.get(cache_key, {})
		if not hit.is_empty() and Game.cycle < int(hit["expires"]):
			last_answer_kind = "cached"
			return String(hit["ip"])
	if dev.resolver == "":
		return ""
	var server: String = dev.resolver
	for _hop in MAX_REFERRALS:
		_dns_id += 1
		_dns_results = []
		_send_ip(dev, server, 64, {"proto": "dns", "q": name, "id": _dns_id, "v6": want_v6})
		var answered := ""
		var referred := ""
		var ttl := DEFAULT_TTL
		for r in _dns_results:
			if r["id"] != _dns_id or r["q"] != name:
				continue
			if r.has("referral"):
				referred = String(r["referral"])
			elif r.has("answer"):
				answered = String(r["answer"])
				ttl = int(r.get("ttl", DEFAULT_TTL))
				last_answer_kind = String(r.get("kind", "native"))
		if answered != "":
			dev.dns_cache[cache_key] = {"ip": answered, "expires": Game.cycle + maxi(0, ttl)}
			return answered
		if referred == "":
			return ""
		server = referred  # follow the delegation and ask the next one down
	return ""

static func dns_cached(dev: Net.NDevice, name: String) -> bool:
	var hit: Dictionary = dev.dns_cache.get(name, {})
	return not hit.is_empty() and Game.cycle < int(hit["expires"])

static func bgp_established(dev: Net.NDevice, nb: Dictionary) -> bool:
	## eBGP-lite: session is up when the neighbor IP is on a directly
	## connected subnet, ARP-reachable, speaks BGP, and either auto-accepts
	## (the ISP handoff) or has a matching neighbor statement back to us.
	var peer := _ip_owner(nb["ip"])
	if peer == null or peer == dev or peer.bgp.is_empty():
		return false
	if int(nb["remote_as"]) != int(peer.bgp.get("asn", -1)):
		return false
	var out := _connected_iface(dev, nb["ip"])
	if out == null:
		return false
	if _arp_resolve(dev, out, nb["ip"]) == "":
		return false
	if peer.type == "uplink":
		return true
	for pnb in peer.bgp.get("neighbors", []):
		if _owns_ip_anywhere(dev, pnb["ip"]):
			return true
	return false

static func _bgp_learned(dev: Net.NDevice) -> Array:
	## Routes this device learns from established sessions:
	## configured neighbors' networks, plus (for the passive/ISP side)
	## networks of peers that neighbor US. -> [{prefix, plen, via}]
	var out: Array = []
	if dev.bgp.is_empty():
		return out
	for nb in dev.bgp.get("neighbors", []):
		if bgp_established(dev, nb):
			var peer := _ip_owner(nb["ip"])
			var peer_nb := _neighbor_towards(peer, dev)
			for net in peer.bgp.get("networks", []):
				if not _policy_allows(peer_nb, "prefix_out", String(net)):
					continue  # the far side is not announcing it to us
				if not _policy_allows(nb, "prefix_in", String(net)):
					continue  # we are not accepting it from them
				var parts := String(net).split("/")
				out.append({"prefix": parts[0], "plen": int(parts[1]), "via": nb["ip"],
					"pref": int(nb.get("local_pref", 100)),
					"cost": 1 + int(peer_nb.get("prepend", 0))})
	for other in Game.all_devices():
		if other == dev or other.bgp.is_empty():
			continue
		for onb in other.bgp.get("neighbors", []):
			if _owns_ip_anywhere(dev, onb["ip"]) and bgp_established(other, onb):
				var via := _ip_of_on_subnet(other, onb["ip"])
				if via == "":
					continue
				var our_nb := _neighbor_towards(dev, other)
				for net in other.bgp.get("networks", []):
					if not _policy_allows(onb, "prefix_out", String(net)):
						continue
					if not _policy_allows(our_nb, "prefix_in", String(net)):
						continue
					var parts := String(net).split("/")
					# their prepending is how they ask us to prefer the other path
					out.append({"prefix": parts[0], "plen": int(parts[1]), "via": via,
						"pref": int(our_nb.get("local_pref", 100)),
						"cost": 1 + int(onb.get("prepend", 0))})
	return out

static func _neighbor_towards(dev: Net.NDevice, other: Net.NDevice) -> Dictionary:
	## the neighbour entry on dev that points at any address other owns
	for nb in dev.bgp.get("neighbors", []):
		if _owns_ip_anywhere(other, String(nb["ip"])):
			return nb
	return {}

static func _policy_allows(nb: Dictionary, key: String, cidr: String) -> bool:
	## an empty prefix list means no filter, which is how real gear behaves
	## before anybody writes a policy: everything goes everywhere
	if nb.is_empty():
		return true
	var list: Array = nb.get(key, [])
	if list.is_empty():
		return true
	return cidr in list

static func _ip_owner(ip: String) -> Net.NDevice:
	for d in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			for cidr: String in i.ips:
				if Net.addr_eq(cidr.split("/")[0], ip):
					return d
	return null

static func _owns_ip_anywhere(dev: Net.NDevice, ip: String) -> bool:
	for i: Net.Iface in dev.ifaces:
		for cidr: String in i.ips:
			if cidr.split("/")[0] == ip:
				return true
	return false

static func _connected_iface(dev: Net.NDevice, ip: String, vrf := "") -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if not i.enabled or i.vrf != vrf or bfd_down(i):
			continue
		for cidr: String in i.ips:
			var parts := cidr.split("/")
			if Net.same_subnet(ip, parts[0], int(parts[1])):
				return i
	return null

static func _ip_of_on_subnet(dev: Net.NDevice, peer_ip: String) -> String:
	for i: Net.Iface in dev.ifaces:
		for cidr: String in i.ips:
			var parts := cidr.split("/")
			if Net.same_subnet(peer_ip, parts[0], int(parts[1])):
				return parts[0]
	return ""

static var _stp_blocked := {}  # Iface -> true
static var _stp_dirty := true

static func ospf_covered_ifaces(dev: Net.NDevice) -> Array:
	## interfaces whose subnet is covered by a network statement
	var out: Array = []
	if dev.ospf.is_empty():
		return out
	for i: Net.Iface in dev.ifaces:
		if not i.enabled:
			continue
		for cidr: String in i.ips:
			for net in dev.ospf.get("networks", []):
				var parts := String(net).split("/")
				if Net.same_subnet(cidr.split("/")[0], parts[0], int(parts[1])):
					out.append(i)
	return out

static func ospf_neighbors(dev: Net.NDevice) -> Array:
	## -> [{dev, via_ip}] adjacent OSPF routers (shared covered subnet)
	var out: Array = []
	for other in Game.all_devices():
		if other == dev or other.ospf.is_empty() or not other.ip_forwarding 				or other.status != "active":
			continue
		for ia: Net.Iface in ospf_covered_ifaces(dev):
			for cidr_a: String in ia.ips:
				var pa := cidr_a.split("/")
				for ib: Net.Iface in ospf_covered_ifaces(other):
					for cidr_b: String in ib.ips:
						if Net.same_subnet(cidr_b.split("/")[0], pa[0], int(pa[1])):
							out.append({"dev": other, "via_ip": cidr_b.split("/")[0]})
	return out

static func _ospf_learned(dev: Net.NDevice) -> Array:
	## BFS shortest-path: every reachable OSPF router's covered subnets,
	## via the first-hop neighbor toward it. -> [{prefix, plen, via}]
	var out: Array = []
	if dev.ospf.is_empty() or not dev.ip_forwarding:
		return out
	var first_hop := {}  # router -> [via_ip, ...] equal-cost first hops
	var hops := {}  # router -> distance in hops, so nearer wins
	var frontier: Array = []
	for nb in ospf_neighbors(dev):
		if not first_hop.has(nb["dev"]):
			first_hop[nb["dev"]] = []
			hops[nb["dev"]] = 1
			frontier.append(nb["dev"])
		if nb["via_ip"] not in first_hop[nb["dev"]]:
			first_hop[nb["dev"]].append(nb["via_ip"])
	var visited := {dev: true}
	while not frontier.is_empty():
		var cur: Net.NDevice = frontier.pop_front()
		if visited.has(cur):
			continue
		visited[cur] = true
		for i: Net.Iface in ospf_covered_ifaces(cur):
			for cidr: String in i.ips:
				var netw := Net.network_of(cidr)
				for via in first_hop[cur]:
					out.append({"prefix": netw["prefix"], "plen": netw["plen"], "via": via,
						"cost": 10 * int(hops.get(cur, 1))})
		for nb in ospf_neighbors(cur):
			if not visited.has(nb["dev"]):
				var next_cost: int = int(hops.get(cur, 1)) + 1
				if not first_hop.has(nb["dev"]):
					first_hop[nb["dev"]] = first_hop[cur].duplicate()
					hops[nb["dev"]] = next_cost
				elif next_cost < int(hops.get(nb["dev"], 1 << 30)):
					first_hop[nb["dev"]] = first_hop[cur].duplicate()
					hops[nb["dev"]] = next_cost
				elif next_cost == int(hops.get(nb["dev"], 1 << 30)):
					for via in first_hop[cur]:
						if via not in first_hop[nb["dev"]]:
							first_hop[nb["dev"]].append(via)
				frontier.append(nb["dev"])
	return out

static func snmp_poll(station: Net.NDevice, target_ip: String, community: String) -> Dictionary:
	## One SNMP get, over the real network. It fails for exactly the reasons a
	## real one does: no route, the agent is not running, or the community is
	## wrong, and the caller is told which.
	var reach := ping(station, target_ip)
	if not reach["ok"]:
		return {"ok": false, "why": "unreachable: %s" % reach.get("detail", "no answer")}
	var target: Net.NDevice = null
	for d in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			if _iface_owns_ip(i, target_ip):
				target = d
	if target == null:
		return {"ok": false, "why": "nothing owns that address"}
	if target.snmp == "":
		return {"ok": false, "why": "no SNMP agent on %s" % target.name}
	if target.snmp != community:
		return {"ok": false, "why": "wrong community for %s" % target.name}
	var ifs: Array = []
	for i2: Net.Iface in target.ifaces:
		if i2.name == "lo" or i2.parent != "":
			continue
		ifs.append({"name": i2.name, "up": i2.enabled and Game.link_at(i2) != null,
			"tx": i2.tx_frames, "rx": i2.rx_frames})
	return {"ok": true, "name": target.name, "model": target.model,
		"status": target.status, "ifaces": ifs}

static func mlag_peer_of(dev: Net.NDevice) -> Net.NDevice:
	## the switch this one shares bundles with, if it is up
	if dev.mlag_peer == "":
		return null
	for d in Game.all_devices():
		if d.name == dev.mlag_peer and d.type == "switch" and d.status == "active":
			return d
	return null

static func mlag_port(dev: Net.NDevice, id: int) -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if i.mlag == id:
			return i
	return null

static func mlag_peerlink(dev: Net.NDevice) -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if i.mlag_peerlink and i.enabled and Game.link_at(i) != null:
			return i
	return null

static func leg_usable(port: Net.Iface) -> bool:
	## a cable is only useful when both ends are up
	if port == null or not port.enabled:
		return false
	var l := Game.link_at(port)
	if l == null:
		return false
	var far: Net.Iface = l.b if l.a == port else l.a
	return far.enabled and far.dev.status == "active"

static func _mlag_live(port: Net.Iface) -> bool:
	return leg_usable(port) and not stp_blocked(port)

static func _mlag_peer_covers(dev: Net.NDevice, id: int) -> bool:
	## true when the peer switch can deliver this bundle itself, which is why
	## a frame that came over the peer link must not be sent out again here
	var peer := mlag_peer_of(dev)
	return peer != null and _mlag_live(mlag_port(peer, id))

static func mcast_mac(group: String) -> String:
	## the link-layer address a multicast group maps to
	var parts := group.split(".")
	if parts.size() != 4:
		return BCAST
	return "%s:%02x:%02x:%02x" % [MCAST_PREFIX, int(parts[1]) & 0x7f, int(parts[2]), int(parts[3])]

static func igmp_join(host: Net.NDevice, group: String) -> String:
	## announce membership: the report floods the VLAN and any snooping switch
	## on the way records which port asked for it
	if not group.begins_with("2"):
		return "%s is not a multicast group" % group
	if group not in host.mcast_groups:
		host.mcast_groups.append(group)
	for i: Net.Iface in host.ifaces:
		if Game.link_at(i) != null and i.enabled:
			_tx(i, {"src": i.mac, "dst": BCAST, "vlan": 0, "type": "igmp",
				"pl": {"op": "report", "group": group, "src_ip": _first_ip(i),
					"dst_ip": group, "ttl": 1, "l4": {"proto": "igmp"}}})
			break
	return ""

static func mcast_send(host: Net.NDevice, group: String) -> int:
	## send one multicast frame and report how many members received it
	for d in Game.all_devices():
		d.mcast_rx = 0
	for i: Net.Iface in host.ifaces:
		if Game.link_at(i) != null and i.enabled:
			_depth = 0
			_tx(i, {"src": i.mac, "dst": mcast_mac(group), "vlan": 0, "type": "ipv4",
				"pl": {"src_ip": _first_ip(i), "dst_ip": group, "ttl": 8,
					"l4": {"proto": "udp", "type": "stream"}}})
			break
	var got := 0
	for d in Game.all_devices():
		if d.mcast_rx > 0:
			got += 1
	return got

static func static_port(dev: Net.NDevice, vlan: int, mac: String) -> Net.Iface:
	## a pinned entry wins over anything learned
	var name := String(dev.mac_static.get(vlan, {}).get(mac.to_upper(), ""))
	if name == "":
		return null
	for i: Net.Iface in dev.ifaces:
		if i.name == name:
			return i
	return null

static func flush_learned_state() -> void:
	## everything learned ages out: the world was rebuilt, or a cycle passed
	_stp_dirty = true
	for d in Game.all_devices():
		d.mac_table.clear()
		d.arp.clear()
		d.nat_flows.clear()
		d.nat64_flows.clear()
		d.flows.clear()

static func arp_iface(dev: Net.NDevice, ip: String) -> Net.Iface:
	## the interface whose subnet holds the neighbour: where the entry lives
	var key := ip.split("@")[0]  # per-VRF keys carry a suffix
	for i: Net.Iface in dev.ifaces:
		for cidr in i.ips:
			var bits := String(cidr).split("/")
			if Net.is_v6(String(cidr)) != Net.is_v6(key):
				continue
			if (Net.is_v6(key) and Net.same_subnet6(key, bits[0], int(bits[1]))) \
					or (not Net.is_v6(key) and Net.same_subnet(key, bits[0], int(bits[1]))):
				return i
	return null

static func topology_change() -> void:
	## a link came or went: spanning tree tells every bridge to forget what it
	## learned, exactly so that a moved host is found again by flooding
	for d in Game.all_devices():
		d.mac_table.clear()
	_stp_dirty = true

static func forget_mac(mac: String) -> void:
	## the host announced itself from somewhere new: every table relearns it
	for d in Game.all_devices():
		for vlan in d.mac_table:
			d.mac_table[vlan].erase(mac)

static func forget_ip(ip: String) -> void:
	## a gratuitous ARP: whoever cached this address hears the new owner
	for d in Game.all_devices():
		for key in d.arp.keys():
			if String(key).split("@")[0] == ip:
				d.arp.erase(key)

static func prune_learned_state() -> void:
	## A configuration changed somewhere. Real gear does not forget the whole
	## world for that: it drops only what can no longer be true, and the rest
	## ages out or is relearned when the host next speaks.
	_stp_dirty = true
	# who owns which MAC right now: an entry for a MAC whose owner is dead,
	# or has moved, is what a gratuitous ARP would have corrected
	var owner := {}
	for d in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			owner[i.mac] = i
	for d in Game.all_devices():
		for vlan in d.mac_table.keys():
			for mac in d.mac_table[vlan].keys():
				var port: Net.Iface = d.mac_table[vlan][mac]
				var link: Net.Link = Game.link_at(port) if port != null else null
				var own: Net.Iface = owner.get(mac)
				var gone: bool = port == null or port.dev != d or not port.enabled \
					or not d.ifaces.has(port) or link == null \
					or link.other(port).dev.status != "active" \
					or own == null or own.dev.status != "active" or not own.enabled \
					or (port.mode == "access" and port.untagged_vlan != vlan) \
					or (port.mode == "trunk" and not port.tagged_vlans.is_empty()
						and vlan not in port.tagged_vlans)
				if gone:
					d.mac_table[vlan].erase(mac)
		for ip in d.arp.keys():
			var own_a: Net.Iface = owner.get(String(d.arp[ip]))
			var bare := String(ip).split("@")[0]
			# no owner at all means the box is gone: nothing will ever answer to it
			var moved: bool = own_a == null or own_a.dev.status != "active" or not own_a.enabled \
				or (not own_a.ips.any(func(c): return String(c).split("/")[0] == bare)
					and String(own_a.vrrp.get("vip", "")) != bare)
			if arp_iface(d, String(ip)) == null or moved:
				d.arp.erase(ip)
		# translation and flow state rides on paths that may just have moved
		d.nat_flows.clear()
		d.nat64_flows.clear()
		d.flows.clear()

static func stp_blocked(i: Net.Iface) -> bool:
	_stp_ensure()
	return _stp_blocked.has(i)

static func stp_root_of(dev: Net.NDevice) -> Net.NDevice:
	_stp_ensure()
	return _stp_roots.get(dev, dev)

static var _stp_roots := {}  # switch -> its component's root

static func stp_id(d: Net.NDevice) -> String:
	## the bridge id a real switch elects on: priority first, then address
	return "%05d|%s" % [d.stp_priority, d.ifaces[0].mac]

static func mst_instances() -> Array:
	## every instance any switch has been told about, plus 0 for everything
	## that was not assigned to one
	var seen := {0: true}
	for d in Game.all_devices():
		if d.type == "switch":
			for inst in d.mst_instances:
				seen[int(inst)] = true
	var out: Array = seen.keys()
	out.sort()
	return out

static func instance_of_vlan(vlan: int) -> int:
	for d in Game.all_devices():
		if d.type != "switch":
			continue
		for inst in d.mst_instances:
			if vlan in d.mst_instances[inst]:
				return int(inst)
	return 0

static func stp_blocked_for(i: Net.Iface, vlan: int) -> bool:
	## MST runs a separate tree per instance, so a port can be forwarding for
	## one set of VLANs and discarding for another. That is the whole point of
	## it: two links between switches both carry traffic.
	_stp_ensure()
	var inst := instance_of_vlan(vlan)
	return _stp_blocked_inst.get(inst, {}).has(i)

static var _stp_blocked_inst := {}  # instance -> {Iface: true}
static var _stp_wanted_since := {}  # Iface -> cycle it first wanted to forward

static func _stp_ensure() -> void:
	## Simplified 802.1D/802.1s: the lowest bridge id is root; a spanning tree
	## per MST instance over switch-switch links; every off-tree link blocks
	## its far-from-root end.
	if not _stp_dirty:
		return
	_stp_dirty = false
	var before := _stp_blocked_inst.duplicate(true)
	_stp_blocked = {}
	_stp_blocked_inst = {}
	_stp_roots = {}
	for inst in mst_instances():
		_stp_blocked_inst[inst] = _stp_tree(int(inst))
	_stp_blocked = _stp_blocked_inst.get(0, {})
	if before != _stp_blocked_inst:
		# the tree moved: a topology change notification flushes every bridge's
		# table, so hosts are found again over the new path by flooding
		for d in Game.all_devices():
			d.mac_table.clear()

static func _stp_tree(instance: int) -> Dictionary:
	var blocked := {}
	var switches: Array = []
	for d in Game.all_devices():
		if d.type == "switch" and d.status == "active":
			switches.append(d)
	if switches.is_empty():
		return blocked
	switches.sort_custom(func(x, y): return stp_id(x) < stp_id(y))
	var sw_links: Array = []
	for l in Game.links:
		if l.a.dev.type == "switch" and l.b.dev.type == "switch" and l.a.enabled and l.b.enabled and not l.a.name.begins_with("Management") and not l.b.name.begins_with("Management") and l.a.dev.status == "active" and l.b.dev.status == "active":
			sw_links.append(l)
	# each instance walks the links in its own order, so the alternate port
	# lands on a different link per instance and both cables carry traffic
	if instance > 0:
		sw_links.reverse()
	# collapse lag bundles into single logical edges
	var edges := {}
	for l in sw_links:
		var key: String
		if l.a.lag > 0 and l.b.lag > 0:
			var ids := ["%s|%d" % [l.a.dev.name, l.a.lag], "%s|%d" % [l.b.dev.name, l.b.lag]]
			ids.sort()
			key = "lag:" + ids[0] + ":" + ids[1]
		else:
			key = "link:%d" % sw_links.find(l)
		if not edges.has(key):
			edges[key] = {"links": [], "a": l.a.dev, "b": l.b.dev}
		edges[key]["links"].append(l)
	# one spanning tree per connected component, rooted at its lowest MAC
	var dist := {}
	var tree := {}
	for sw in switches:  # sorted by bridge id, so the best one roots its component
		if dist.has(sw):
			continue
		dist[sw] = 0
		var frontier: Array = [sw]
		while not frontier.is_empty():
			frontier.sort_custom(func(x, y): return stp_id(x) < stp_id(y))
			var cur: Net.NDevice = frontier.pop_front()
			_stp_roots[cur] = sw
			for key in edges:
				if tree.has(key):
					continue
				var e: Dictionary = edges[key]
				var nb: Net.NDevice = null
				if e["a"] == cur:
					nb = e["b"]
				elif e["b"] == cur:
					nb = e["a"]
				if nb != null and not dist.has(nb):
					dist[nb] = dist[cur] + 1
					tree[key] = true
					frontier.append(nb)
	for key in edges:
		if tree.has(key):
			continue
		var e: Dictionary = edges[key]
		var da: int = dist.get(e["a"], 1 << 30)
		var db: int = dist.get(e["b"], 1 << 30)
		var victim_dev: Net.NDevice = e["a"]
		if db > da or (db == da and stp_id(e["b"]) > stp_id(e["a"])):
			victim_dev = e["b"]
		for l in e["links"]:
			var port: Net.Iface = l.a if l.a.dev == victim_dev else l.b
			blocked[port] = true
			_stp_wanted_since.erase(port)
	# classic 802.1D waits before it dares forward on a port that has just
	# become the best path. RSTP does not, which is the reason nobody runs the
	# old one any more.
	for port2 in _stp_prev_blocked(instance):
		if blocked.has(port2) or not is_instance_valid(port2.dev):
			continue
		if port2.dev.stp_mode != "stp":
			continue
		if not _stp_wanted_since.has(port2):
			_stp_wanted_since[port2] = Game.cycle
		if Game.cycle - int(_stp_wanted_since[port2]) < STP_HOLD:
			blocked[port2] = true  # still listening/learning
	return blocked

const STP_HOLD := 1  # cycles classic STP holds a port down before forwarding

static func _stp_prev_blocked(instance: int) -> Array:
	return _stp_blocked_inst.get(instance, {}).keys()

# ---------- IP stack (hosts & routers) ----------

static func _send_ip(dev: Net.NDevice, dst_ip: String, ttl: int, l4: Dictionary, vrf := "") -> String:
	if dev.status != "active":
		return "device is offline"
	var rt := _route_lookup(dev, dst_ip, "%s|%s|%s" % [dst_ip, str(l4.get("id", 0)), dev.name], vrf)
	if rt.is_empty():
		return "no route to host"
	if rt.get("next_hop", "") == "null0":
		return "blackholed by a discard route"
	var out: Net.Iface = rt["iface"]
	var src_ip := _first_ip(out, Net.is_v6(dst_ip))
	var mac := _arp_resolve(dev, out, rt["next_hop"])
	if mac == "":
		return "host unreachable (no ARP reply for %s)" % rt["next_hop"]
	_tx(out, {"src": out.mac, "dst": mac, "vlan": 0, "type": "ipv4",
		"pl": {"src_ip": src_ip, "dst_ip": dst_ip, "ttl": ttl, "l4": l4}})
	return ""

static func _route_lookup(dev: Net.NDevice, dst_ip: String, flow_key := "", vrf := "") -> Dictionary:
	## picks one path; with several of equal length the flow is hashed across
	## them, which is what makes a spine-leaf fabric use all its uplinks
	var paths := _route_paths(dev, dst_ip, vrf)
	if paths.is_empty():
		return {}
	if paths.size() == 1 or flow_key == "":
		return paths[0]
	return paths[hash(flow_key) % paths.size()]

static func _route_paths(dev: Net.NDevice, dst_ip: String, vrf := "") -> Array:
	return _best_of(_all_routes(dev, dst_ip, vrf))

static func _best_of(cands: Array) -> Array:
	## Longest prefix, then the most believable source (administrative
	## distance: connected 0, static 1, eBGP 20, OSPF 110), then the protocol's
	## own preference and metric. Ties are equal-cost paths.
	var best_len := -1
	for c in cands:
		best_len = maxi(best_len, int(c["plen"]))
	if best_len < 0:
		return []
	var best_ad := 1 << 30
	for c in cands:
		if int(c["plen"]) == best_len:
			best_ad = mini(best_ad, int(c.get("ad", 1)))
	# BGP decides on local preference before it looks at path length, which is
	# the whole reason local-pref exists: it is how you pick your own upstream
	var best_pref := -(1 << 30)
	for c in cands:
		if int(c["plen"]) == best_len and int(c.get("ad", 1)) == best_ad:
			best_pref = maxi(best_pref, int(c.get("pref", 100)))
	var best_cost := 1 << 30
	for c in cands:
		if int(c["plen"]) == best_len and int(c.get("ad", 1)) == best_ad \
				and int(c.get("pref", 100)) == best_pref:
			best_cost = mini(best_cost, int(c.get("cost", 1)))
	var out: Array = []
	var seen := {}
	for cand in cands:
		if int(cand["plen"]) != best_len or int(cand.get("ad", 1)) != best_ad \
				or int(cand.get("pref", 100)) != best_pref or int(cand.get("cost", 1)) != best_cost:
			continue
		var key := "%s|%s" % [str(cand["next_hop"]), str(cand["iface"])]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(cand)
	return out

static func slaac(host: Net.NDevice, iface: Net.Iface) -> Dictionary:
	## Solicit a router on this segment and configure from what it advertises.
	## No server, no leases, no state anywhere: the host builds its own address
	## out of the prefix it was told and its own MAC.
	## -> {ok, address, router, why}
	var l := Game.link_at(iface)
	if l == null or not iface.enabled:
		return {"ok": false, "why": "the cable is not connected", "address": "", "router": ""}
	for router in Game.all_devices():
		if not router.ip_forwarding or router.status != "active" or router == host:
			continue
		for ri: Net.Iface in router.ifaces:
			if not ri.ra or not ri.enabled:
				continue
			# the advertisement only reaches hosts in the same broadcast domain
			if not _same_segment(iface, ri):
				continue
			for cidr: String in ri.ips:
				if not Net.is_v6(cidr):
					continue
				var parts := cidr.split("/")
				if int(parts[1]) != 64:
					continue  # SLAAC needs a /64, which is not a convention, it is arithmetic
				var addr := Net.slaac_address(parts[0], 64, iface.mac)
				if addr == "":
					continue
				var full := "%s/64" % addr
				if full not in iface.ips:
					iface.ips.append(full)
				var via: String = parts[0]
				var already := false
				for r in host.static_routes:
					if String(r["prefix"]) == "::" and int(r["plen"]) == 0:
						already = true
				if not already:
					host.static_routes.append({"prefix": "::", "plen": 0, "via": via})
				Game.topology_changed.emit()
				return {"ok": true, "address": full, "router": router.name, "why": ""}
	return {"ok": false, "address": "", "router": "",
		"why": "no router advertisements on this segment"}

static func _same_segment(a: Net.Iface, b: Net.Iface) -> bool:
	## crude but honest: can a broadcast from a reach b?
	if a.dev == b.dev:
		return false
	var probe := {"src": a.mac, "dst": BCAST, "vlan": 0, "type": "arp",
		"pl": {"op": "req", "spa": "0.0.0.0", "sha": a.mac, "tpa": "0.0.0.0"}}
	var before: int = b.rx_frames
	_depth = 0
	_tx(a, probe)
	return b.rx_frames > before

static func aaa_admit(dev: Net.NDevice) -> Dictionary:
	## Can somebody log in to administer this device right now?
	## -> {ok: bool, how: String, why: String}
	if dev.aaa.is_empty():
		return {"ok": true, "how": "local", "why": ""}
	var server: String = String(dev.aaa.get("server", ""))
	var reachable: bool = server != "" and bool(ping(dev, server)["ok"])
	if reachable:
		var host := _ip_owner(server)
		var svc: Dictionary = host.services.get("aaa", {}) if host != null else {}
		if svc.is_empty():
			return {"ok": bool(dev.aaa.get("local", false)), "how": "local",
				"why": "nothing is answering AAA at %s" % server}
		if String(svc.get("key", "")) != String(dev.aaa.get("key", "")):
			return {"ok": false, "how": "", "why": "shared secret does not match %s" % server}
		return {"ok": true, "how": "aaa", "why": ""}
	# the server is unreachable: this is the moment the local account matters
	if bool(dev.aaa.get("local", false)):
		return {"ok": true, "how": "local fallback",
			"why": "%s is unreachable; falling back to the local account" % server}
	return {"ok": false, "how": "",
		"why": "%s is unreachable and no local fallback is configured" % server}

static func aaa_account(dev: Net.NDevice, command: String) -> void:
	## the audit trail: what was typed, on which device, recorded centrally
	if dev.aaa.is_empty():
		return
	var host := _ip_owner(String(dev.aaa.get("server", "")))
	if host == null or not host.services.has("aaa"):
		return
	var trail: Array = host.services["aaa"].get("log", [])
	trail.push_front("cycle %d  %s: %s" % [Game.cycle, dev.name, command])
	while trail.size() > 40:
		trail.pop_back()
	host.services["aaa"]["log"] = trail

static func route_via(dev: Net.NDevice, dst_ip: String) -> String:
	## the next hop this router would use, or "" if it has no usable path
	var rt := _route_lookup(dev, dst_ip, "%s|probe" % dst_ip)
	return String(rt.get("next_hop", "")) if not rt.is_empty() else ""

static func bfd_down(i: Net.Iface) -> bool:
	## A router only knows its own port is up. Without something watching the
	## far end, a failure out there leaves the route in place and the traffic
	## goes into a hole. BFD is what notices.
	if not i.bfd:
		return false
	var l := Game.link_at(i)
	if l == null:
		return true
	var far: Net.Iface = l.b if l.a == i else l.a
	if not far.bfd:
		return false  # a session needs both ends; one-sided BFD detects nothing
	return not far.enabled or far.dev.status != "active"

static func bfd_session(i: Net.Iface) -> String:
	if not i.bfd:
		return "down"
	var l := Game.link_at(i)
	if l == null:
		return "admin down"
	var far: Net.Iface = l.b if l.a == i else l.a
	if not far.bfd:
		return "no peer"
	return "down" if (not far.enabled or far.dev.status != "active") else "up"

static func _all_routes(dev: Net.NDevice, dst_ip: String, vrf := "") -> Array:
	## every candidate path in one routing table, with the prefix length used
	var out: Array = []
	var want_v6 := Net.is_v6(dst_ip)
	for e in _route_entries(dev, vrf):
		if Net.is_v6(String(e["prefix"])) != want_v6:
			continue
		if not Net.same_net(dst_ip, e["prefix"], int(e["plen"])):
			continue
		var c: Dictionary = e.duplicate()
		if e["src"] == "C":
			c["next_hop"] = dst_ip
		out.append(c)
	return out

static func _route_entries(dev: Net.NDevice, vrf := "") -> Array:
	## Every route this device could install in one table, usable or not
	## filtered out: shut interfaces, next hops nothing is connected to.
	## src is the show-ip-route code (C/S/B/O), ad the administrative distance.
	var out: Array = []
	for i: Net.Iface in dev.ifaces:
		if not i.enabled or i.vrf != vrf or bfd_down(i):
			continue
		for cidr: String in i.ips:
			var netw := Net.network_of(cidr) if not Net.is_v6(cidr) else {"prefix": cidr.split("/")[0], "plen": int(cidr.split("/")[1])}
			out.append({"src": "C", "ad": 0, "iface": i, "next_hop": "", "prefix": netw["prefix"],
				"plen": int(netw["plen"]), "cost": 0, "vrf": vrf})
	var sources := [["S", dev.static_routes], ["B", _bgp_learned(dev)], ["O", _ospf_learned(dev)]]
	for pair in sources:
		var code: String = pair[0]
		for r in pair[1]:
			if String(r.get("vrf", "")) != vrf:
				continue
			var ad := 1 if code == "S" else (20 if code == "B" else 110)
			ad = int(r.get("ad", ad))
			if String(r["via"]) == "null0":
				out.append({"src": code, "ad": ad, "iface": null, "next_hop": "null0", "prefix": r["prefix"],
					"plen": int(r["plen"]), "cost": 1, "vrf": vrf})
				continue
			var via_if := _connected_iface(dev, String(r["via"]), vrf)
			if via_if:
				out.append({"src": code, "ad": ad, "iface": via_if, "next_hop": r["via"], "prefix": r["prefix"],
					"plen": int(r["plen"]), "cost": int(r.get("cost", 1)), "pref": int(r.get("pref", 100)),
					"vrf": vrf})
	return out

static func rib(dev: Net.NDevice) -> Array:
	## The installed table: per prefix, only the route(s) that won. What
	## show ip route prints, across every VRF.
	var names: Array = [""]
	for v in dev.vrfs:
		names.append(String(v))
	var out: Array = []
	for vrf in names:
		var by_prefix := {}
		for e in _route_entries(dev, vrf):
			var key := "%s/%d" % [e["prefix"], int(e["plen"])]
			if not by_prefix.has(key):
				by_prefix[key] = []
			by_prefix[key].append(e)
		var keys: Array = by_prefix.keys()
		keys.sort_custom(func(a, b): return _prefix_sort_key(a) < _prefix_sort_key(b))
		for key in keys:
			out.append_array(_best_of(by_prefix[key]))
	return out

static func _prefix_sort_key(cidr: String) -> Array:
	var parts := cidr.split("/")
	if Net.is_v6(parts[0]):
		return [1, parts[0], int(parts[1])]
	return [0, Net.ip_to_int(parts[0]), int(parts[1])]

static func _route_lookup_single(dev: Net.NDevice, dst_ip: String) -> Dictionary:
	var best := {}
	var best_len := -1
	var want_v6 := Net.is_v6(dst_ip)
	for i: Net.Iface in dev.ifaces:
		if not i.enabled:
			continue
		for cidr: String in i.ips:
			if Net.is_v6(cidr) != want_v6:
				continue
			var parts := cidr.split("/")
			var plen := int(parts[1])
			if plen > best_len and Net.same_net(dst_ip, parts[0], plen):
				best_len = plen
				best = {"iface": i, "next_hop": dst_ip, "plen": plen}
	for r in dev.static_routes:
		if Net.is_v6(String(r["prefix"])) != want_v6:
			continue
		if int(r["plen"]) > best_len and Net.same_net(dst_ip, r["prefix"], int(r["plen"])):
			var via_rt := {}
			var via_len := -1
			for i: Net.Iface in dev.ifaces:
				if not i.enabled:
					continue
				for cidr: String in i.ips:
					if Net.is_v6(cidr) != Net.is_v6(String(r["via"])):
						continue
					var parts := cidr.split("/")
					if int(parts[1]) > via_len and Net.same_net(r["via"], parts[0], int(parts[1])):
						via_len = int(parts[1])
						via_rt = {"iface": i, "next_hop": r["via"]}
			if String(r["via"]) == "null0":
				best_len = int(r["plen"])
				best = {"iface": null, "next_hop": "null0", "plen": best_len}  # discard route
			elif not via_rt.is_empty():
				best_len = int(r["plen"])
				via_rt["plen"] = best_len
				best = via_rt
	for r in _bgp_learned(dev) + _ospf_learned(dev):
		if Net.is_v6(String(r["prefix"])) != want_v6:
			continue
		if int(r["plen"]) > best_len and Net.same_net(dst_ip, r["prefix"], int(r["plen"])):
			var out := _connected_iface(dev, r["via"])
			if out:
				best_len = int(r["plen"])
				best = {"iface": out, "next_hop": r["via"], "plen": best_len}
	return best

static func _neigh_key(iface: Net.Iface, ip: String) -> String:
	## neighbour caches are per routing table: two tenants may legitimately
	## use the same address, and they are not the same neighbour
	var base := Net.v6_compress(ip) if Net.is_v6(ip) else ip
	return base if iface.vrf == "" else "%s|%s" % [iface.vrf, base]

static func _arp_resolve(dev: Net.NDevice, iface: Net.Iface, ip: String) -> String:
	## ARP for IPv4, Neighbor Discovery for IPv6: same job, different name
	if iface.name.begins_with("Tunnel"):
		var peer := tunnel_peer(iface)
		return peer.mac if peer != null else ""  # point to point: the far end is the only neighbour
	if iface.name.begins_with("wg"):
		var wpeer := wg_peer_for(iface, ip)
		if wpeer.is_empty():
			return ""
		var remote := wg_remote(iface, wpeer)
		return remote.mac if remote != null else ""
	var key := _neigh_key(iface, ip)
	if dev.arp.has(key):
		return dev.arp[key]
	_tx(iface, {"src": iface.mac, "dst": BCAST, "vlan": 0,
		"type": "ndp" if Net.is_v6(ip) else "arp",
		"pl": {"op": "req", "spa": _first_ip(iface, Net.is_v6(ip)), "sha": iface.mac, "tpa": ip}})
	return dev.arp.get(key, "")

static func _first_ip(iface: Net.Iface, v6 := false) -> String:
	for cidr: String in iface.ips:
		if Net.is_v6(cidr) == v6:
			return cidr.split("/")[0]
	return "::" if v6 else "0.0.0.0"

static func _has_ip(dev: Net.NDevice, ip: String) -> bool:
	for i: Net.Iface in dev.ifaces:
		if i.enabled:
			for cidr: String in i.ips:
				if Net.addr_eq(cidr.split("/")[0], ip):
					return true
	return false

# ---------- wire / receive ----------

static func _tx(iface: Net.Iface, frame: Dictionary) -> void:
	if iface.lag > 0 and not leg_usable(iface):
		# a bond survives losing a leg: hand the frame to one that is still up
		for member: Net.Iface in bond_members(iface):
			if leg_usable(member):
				iface = member
				break
	if _depth > MAX_DEPTH:
		return
	if not iface.enabled or iface.dev.status != "active":
		return
	if _too_big(iface, frame):
		return  # the frame does not fit down this port; nothing is sent
	if iface.name.begins_with("Vlan"):
		_svi_tx(iface.dev, iface, frame)
		return
	if iface.vm != "":
		# the host bridges its machines onto its own uplink
		for phys: Net.Iface in iface.dev.ifaces:
			if phys.vm != "" or phys.name.begins_with("Vlan") or phys.name == "lo":
				continue
			if Game.link_at(phys) != null:
				var out_frame := frame.duplicate(true)
				out_frame["src"] = iface.mac
				_tx(phys, out_frame)
				return
		return
	if iface.name.begins_with("wg"):
		_wg_tx(iface, frame)
		return
	if iface.name.begins_with("Tunnel"):
		_tunnel_tx(iface, frame)
		return
	if iface.parent != "":  # 802.1Q subinterface: tag and leave via the parent
		for p_if: Net.Iface in iface.dev.ifaces:
			if p_if.name == iface.parent:
				var tagged := frame.duplicate(true)
				tagged["vlan"] = iface.dot1q
				tagged["src"] = iface.mac
				_tx(p_if, tagged)
				return
		return
	var l := Game.link_at(iface)
	if l == null:
		return
	# a patch panel is copper, not a device: the frame comes out the far side
	var peer: Net.Iface = Game.effective_peer(iface)
	if peer == null:
		return
	if not peer.enabled or peer.dev.status != "active":
		return
	iface.tx_frames += 1
	if Game.grey_drops(iface, peer, frame_size(frame)):
		# the link is up and the frame is gone: this is what a grey failure is
		peer.rx_errors += 1
		var kind := String(Game.grey_fault(iface).get("kind", Game.grey_fault(peer).get("kind", "")))
		if kind in ["dirty_optic", "loose_connector"]:
			peer.rx_crc += 1  # damage on the wire arrives as a bad checksum
		return
	if duplex_mismatch(iface, peer) and randf() < 0.35:
		# the half side hears collisions, the full side sees garbage; both
		# counters climb and throughput falls, which is exactly the tell
		var half: Net.Iface = iface if effective_duplex(iface, peer) == "half" else peer
		var full: Net.Iface = peer if half == iface else iface
		half.collisions += 1
		full.rx_errors += 1
		full.rx_crc += 1
		return
	peer.rx_frames += 1
	rtt_ms += Game.link_latency_ms(l)
	if last_trace.size() < 300:
		last_trace.append({"a": iface, "b": peer, "kind": frame["type"]})
	_cap(peer.dev, peer, frame)
	_depth += 1
	if peer.dev.type in ["switch", "ap"] and not peer.name.begins_with("Management"):
		_switch_rx(peer.dev, peer, frame)
	else:
		_host_rx(peer.dev, _logical_rx_iface(peer, frame), frame)
	_depth -= 1

static func wg_peer_for(w: Net.Iface, dst_ip: String) -> Dictionary:
	## the peer whose allowed IPs cover this destination: with WireGuard the
	## allowed-IPs list is both the access control and the routing table
	for p in w.wg_peers:
		for cidr in p.get("allowed", []):
			var parts := String(cidr).split("/")
			if parts.size() == 2 and Net.same_net(dst_ip, parts[0], int(parts[1])):
				return p
	return {}

static func wg_remote(w: Net.Iface, peer: Dictionary) -> Net.Iface:
	## the interface on the far side, if it exists and names us back
	for d in Game.all_devices():
		for other: Net.Iface in d.ifaces:
			if other == w or not other.name.begins_with("wg"):
				continue
			if other.wg_key != String(peer.get("key", "")):
				continue
			for back in other.wg_peers:
				if String(back.get("key", "")) == w.wg_key:
					return other  # both sides list each other: a handshake is possible
	return null

static func wg_handshake(w: Net.Iface, peer: Dictionary) -> bool:
	var remote := wg_remote(w, peer)
	if remote == null or not w.enabled or not remote.enabled:
		return false
	if w.dev.status != "active" or remote.dev.status != "active":
		return false
	var endpoint := String(peer.get("endpoint", ""))
	return endpoint != "" and ping(w.dev, endpoint)["ok"]

static func _wg_tx(w: Net.Iface, frame: Dictionary) -> void:
	if _depth > MAX_DEPTH:
		return
	var pl: Dictionary = frame["pl"]
	var dst: String = String(pl.get("dst_ip", ""))
	var peer := wg_peer_for(w, dst)
	if peer.is_empty():
		Game.device_log(w.dev, "wireguard dropped a packet for %s: no peer allows it" % dst)
		return  # not in anybody's allowed IPs: dropped, which is the point
	if not wg_handshake(w, peer):
		return
	var remote := wg_remote(w, peer)
	# the far side must also allow the source, or it drops what we send
	if wg_peer_for(remote, String(pl.get("src_ip", ""))).is_empty():
		Game.device_log(remote.dev, "wireguard dropped traffic from %s: not in allowed IPs"
			% pl.get("src_ip", ""))
		return
	w.tx_frames += 1
	remote.rx_frames += 1
	var inner := frame.duplicate(true)
	inner["dst"] = remote.mac
	_cap(remote.dev, remote, inner)
	_depth += 1
	_host_rx(remote.dev, remote, inner)
	_depth -= 1

static func tunnel_peer(t: Net.Iface) -> Net.Iface:
	## the far end: a tunnel whose endpoints mirror ours
	if t.tunnel_src == "" or t.tunnel_dst == "":
		return null
	for d in Game.all_devices():
		for other: Net.Iface in d.ifaces:
			if other == t or not other.name.begins_with("Tunnel"):
				continue
			if Net.addr_eq(other.tunnel_src, t.tunnel_dst) \
					and Net.addr_eq(other.tunnel_dst, t.tunnel_src):
				return other
	return null

static func tunnel_up(t: Net.Iface) -> bool:
	## the tunnel is only up while the underlay can carry it
	var peer := tunnel_peer(t)
	if peer == null or not t.enabled or not peer.enabled:
		return false
	if t.dev.status != "active" or peer.dev.status != "active":
		return false
	return ping(t.dev, t.tunnel_dst)["ok"]

static func _tunnel_tx(t: Net.Iface, frame: Dictionary) -> void:
	## encapsulate: the inner frame is delivered to the far end if the
	## underlay between the two endpoints is working
	if _depth > MAX_DEPTH:
		return
	var peer := tunnel_peer(t)
	if peer == null:
		return
	if not ping(t.dev, t.tunnel_dst)["ok"]:
		return  # the path is down, and so is the tunnel
	t.tx_frames += 1
	peer.rx_frames += 1
	var inner := frame.duplicate(true)
	inner["dst"] = peer.mac  # point to point: no neighbour discovery needed
	_cap(peer.dev, peer, inner)
	_depth += 1
	_host_rx(peer.dev, peer, inner)
	_depth -= 1

static func _svi_tx(dev: Net.NDevice, svi: Net.Iface, frame: Dictionary) -> void:
	## send a frame from an SVI into its VLAN: to the learned port, else flood
	var vlan := int(svi.name.trim_prefix("Vlan"))
	var table: Dictionary = dev.mac_table.get(vlan, {})
	var known: Net.Iface = static_port(dev, vlan, String(frame["dst"]))
	if known == null:
		known = table.get(frame["dst"])
	var outs: Array = [known] if (known != null and frame["dst"] != BCAST) else dev.ifaces
	var lags_done := {}
	for o: Net.Iface in outs:
		if o == svi or o.name.begins_with("Vlan") or o.name == "lo" or stp_blocked(o):
			continue
		if o.mlag > 0 and not _mlag_live(o):
			continue  # the peer link will carry it to the surviving member
		if o.lag > 0:
			if lags_done.has(o.lag):
				continue
			lags_done[o.lag] = true
		var f := frame.duplicate(true)
		if o.mode == "access":
			if o.untagged_vlan != vlan:
				continue
			f["vlan"] = 0
		elif o.mode == "trunk":
			if not o.tagged_vlans.is_empty() and vlan not in o.tagged_vlans:
				continue
			f["vlan"] = 0 if vlan == o.untagged_vlan else vlan  # 802.1Q: the native VLAN rides untagged
		else:
			continue
		_depth += 1
		var l := Game.link_at(o)
		if l and o.enabled:
			var peer: Net.Iface = l.other(o)
			if peer.enabled and peer.dev.status == "active":
				o.tx_frames += 1
				peer.rx_frames += 1
				_cap(peer.dev, peer, f)
				if peer.dev.type == "switch" and not peer.name.begins_with("Management"):
					_switch_rx(peer.dev, peer, f)
				else:
					_host_rx(peer.dev, peer, f)
		_depth -= 1

static func _dot1x_authorise(sw: Net.NDevice, port: Net.Iface, mac: String) -> bool:
	## ask the RADIUS server whether this machine is allowed on the network,
	## and let it say which VLAN the machine belongs in
	if sw.radius == "":
		Game.device_log(sw, "802.1X on %s but no authentication server configured" % port.name)
		return false
	var server := _ip_owner(sw.radius)
	if server == null or not server.services.has("radius"):
		return false
	if not ping(sw, sw.radius)["ok"]:
		Game.device_log(sw, "802.1X could not reach the authentication server")
		return false
	var users: Dictionary = server.services["radius"].get("users", {})
	if not users.has(mac):
		Game.device_log(sw, "802.1X rejected %s on %s" % [mac, port.name])
		return false
	port.dot1x_ok = mac
	var vid := int(users[mac])
	if vid > 0 and sw.vlans.has(vid):
		port.untagged_vlan = vid  # the server decides where you belong
	Game.device_log(sw, "802.1X authorised %s on %s%s" % [mac, port.name,
		" into VLAN %d" % vid if vid > 0 else ""])
	return true

static func _reset_storm_counters() -> void:
	for d in Game.all_devices():
		for i: Net.Iface in d.ifaces:
			i.storm_count = 0

static func _switch_rx(dev: Net.NDevice, in_if: Net.Iface, frame: Dictionary) -> void:
	if stp_blocked(in_if) and _rx_instance_blocked(dev, in_if, frame):
		return  # spanning tree: discarding state for this frame's instance
	var vlan: int
	if in_if.mode == "access":
		if frame["vlan"] != 0:
			return  # tagged frame on access port: drop
		vlan = in_if.untagged_vlan
	else:  # trunk: an untagged frame belongs to the port's native VLAN
		vlan = frame["vlan"] if frame["vlan"] != 0 else in_if.untagged_vlan
		if not in_if.tagged_vlans.is_empty() and vlan not in in_if.tagged_vlans:
			return  # VLAN not allowed on this trunk
	if not dev.vlans.has(vlan):
		return
	# DHCP snooping: only a trusted port may carry a server's answer
	if dev.snooping and frame["type"] == "dhcp":
		var dp: Dictionary = frame["pl"]
		if dp["op"] == "ack" and not in_if.dhcp_trusted:
			Game.device_log(dev, "DHCP snooping dropped a server reply on untrusted port %s"
				% in_if.name)
			return
		if dp["op"] == "ack":
			dev.bindings[dp["mac"]] = dp["ip"]  # remember the legitimate lease
	# dynamic ARP inspection: an address claim must match what we saw leased
	if dev.dai and frame["type"] == "arp":
		var ap: Dictionary = frame["pl"]
		var claimed: String = String(ap["spa"])
		var owner_mac: String = String(frame["src"])
		if dev.bindings.has(owner_mac) and String(dev.bindings[owner_mac]) != claimed and claimed != "0.0.0.0":
			Game.device_log(dev, "ARP inspection dropped %s claiming %s on %s"
				% [owner_mac, claimed, in_if.name])
			return
		for bound_mac in dev.bindings:
			if String(dev.bindings[bound_mac]) == claimed and bound_mac != owner_mac:
				Game.device_log(dev, "ARP inspection dropped %s spoofing %s on %s"
					% [owner_mac, claimed, in_if.name])
				return
	if not dev.mac_table.has(vlan):
		dev.mac_table[vlan] = {}
	# storm control: a port may only contribute so much broadcast per operation
	if frame["dst"] == BCAST and in_if.storm_limit > 0:
		in_if.storm_count += 1
		if in_if.storm_count > in_if.storm_limit:
			Game.device_log(dev, "storm control suppressed broadcast on %s" % in_if.name)
			return
	# 802.1X: nothing passes until the authentication server says who this is
	if in_if.dot1x and String(frame["src"]) != in_if.dot1x_ok:
		if not _dot1x_authorise(dev, in_if, String(frame["src"])):
			return
	if in_if.port_security:
		if in_if.secure_mac == "":
			in_if.secure_mac = frame["src"]  # sticky: learn the first device
		elif in_if.secure_mac != frame["src"]:
			in_if.violations += 1
			in_if.err_disabled = true
			in_if.enabled = false
			Game.device_log(dev, "port-security violation on %s: saw %s" % [in_if.name, frame["src"]])
			Game.log_event("PORT SECURITY: %s %s saw %s instead of %s and shut down."
				% [dev.name, in_if.name, frame["src"], in_if.secure_mac])
			Game.topology_changed.emit()
			return
	# membership reports teach a snooping switch where a group is wanted
	if frame["type"] == "igmp":
		var grp: String = String(frame["pl"]["group"])
		if not dev.mcast_ports.has(grp):
			dev.mcast_ports[grp] = {}
		dev.mcast_ports[grp][in_if] = true
	# multicast goes only where it was asked for, when snooping is on
	if dev.igmp_snooping and String(frame["dst"]).begins_with(MCAST_PREFIX):
		var wanted := {}
		for grp2 in dev.mcast_ports:
			if mcast_mac(String(grp2)) == String(frame["dst"]):
				for port in dev.mcast_ports[grp2]:
					wanted[port] = true
		dev.mac_table[vlan][frame["src"]] = in_if
		for o2: Net.Iface in wanted:
			if o2 == in_if or stp_blocked_for(o2, vlan) or not o2.enabled:
				continue
			if o2.mode == "access" and o2.untagged_vlan != vlan:
				continue
			var mf := frame.duplicate(true)
			mf["vlan"] = 0 if o2.mode == "access" or vlan == o2.untagged_vlan else vlan
			_tx(o2, mf)
		return
	var was_local: Net.Iface = dev.mac_table[vlan].get(frame["src"])
	dev.mac_table[vlan][frame["src"]] = in_if
	if was_local != in_if and String(frame.get("vxlan_from", "")) == "":
		# newly learned behind a local port: tell the other VTEPs about it
		evpn_advertise(dev, vlan, String(frame["src"]))
	if in_if.mlag > 0:
		# the pair keeps one view of the world: whatever one member learns,
		# the other must know about, pointing at its own side of the bundle
		var mpeer := mlag_peer_of(dev)
		if mpeer != null:
			var mport := mlag_port(mpeer, in_if.mlag)
			if mport != null:
				if not mpeer.mac_table.has(vlan):
					mpeer.mac_table[vlan] = {}
				mpeer.mac_table[vlan][frame["src"]] = mport
	for svi: Net.Iface in dev.ifaces:
		if not svi.name.begins_with("Vlan") or not svi.enabled:
			continue
		if int(svi.name.trim_prefix("Vlan")) != vlan:
			continue
		if frame["dst"] == svi.mac:
			_host_rx(dev, svi, frame)  # unicast to us: consumed here
			return
		if frame["dst"] == BCAST:
			_host_rx(dev, svi, frame)  # e.g. ARP for the gateway; still flooded below
	# VXLAN: this VLAN may extend over the routed network to other switches
	_vxlan_tx(dev, in_if, vlan, frame)
	var known: Net.Iface = static_port(dev, vlan, String(frame["dst"]))
	if known == null:
		known = dev.mac_table[vlan].get(frame["dst"])
	if known != null and known.mlag > 0 and not _mlag_live(known):
		known = mlag_peerlink(dev)  # our leg of the bundle is gone: go via the peer
	var outs: Array = [known] if (known != null and frame["dst"] != BCAST) else dev.ifaces
	var lags_done := {}
	var mlags_done := {}
	for o: Net.Iface in outs:
		if o == in_if or stp_blocked_for(o, vlan):
			continue
		# private VLANs: isolated ports may talk to the gateway, not to each other
		if in_if.pvlan == "isolated" and o.pvlan == "isolated":
			continue
		if o.mlag > 0:
			if mlags_done.has(o.mlag):
				continue
			mlags_done[o.mlag] = true
			if in_if.mlag_peerlink and _mlag_peer_covers(dev, o.mlag):
				continue  # the peer already delivered this; two copies is a bug
			if not _mlag_live(o):
				continue  # the peer link will carry it to the surviving member
		if o.lag > 0:
			if lags_done.has(o.lag) or (in_if.lag > 0 and in_if.lag == o.lag):
				continue
			if not (o.enabled and Game.link_at(o) != null):
				continue  # dead member: another member of this lag will carry it
			lags_done[o.lag] = true
		var f := frame.duplicate(true)
		if o.mode == "access":
			if o.untagged_vlan != vlan:
				continue
			f["vlan"] = 0
		elif o.mode == "trunk":
			if not o.tagged_vlans.is_empty() and vlan not in o.tagged_vlans:
				continue
			f["vlan"] = 0 if vlan == o.untagged_vlan else vlan  # 802.1Q: the native VLAN rides untagged
		else:
			continue
		_tx(o, f)

static func _rx_instance_blocked(_dev: Net.NDevice, in_if: Net.Iface, frame: Dictionary) -> bool:
	var vlan := int(frame.get("vlan", 0))
	if vlan == 0:
		vlan = in_if.untagged_vlan if in_if.mode == "access" else 1
	return stp_blocked_for(in_if, vlan)

static func _logical_rx_iface(phys: Net.Iface, frame: Dictionary) -> Net.Iface:
	## a tagged frame belongs to the matching 802.1Q subinterface, if any
	if int(frame.get("vlan", 0)) == 0:
		return phys
	for sub: Net.Iface in phys.dev.ifaces:
		if sub.parent == phys.name and sub.dot1q == int(frame["vlan"]) and sub.enabled:
			return sub
	return phys

static func _host_rx(dev: Net.NDevice, iface: Net.Iface, frame: Dictionary) -> void:
	if String(frame["dst"]).begins_with(MCAST_PREFIX):
		# a host only listens to the groups it joined
		var pl_m: Dictionary = frame["pl"]
		if String(pl_m.get("dst_ip", "")) in dev.mcast_groups:
			dev.mcast_rx += 1
			_cap(dev, iface, frame)
		return
	if frame["type"] == "igmp":
		return  # membership reports are for the switches
	# a frame for one of the host's virtual machines is that machine's business
	if iface.vm == "":
		for guest: Net.Iface in dev.ifaces:
			if guest.vm == "" or not guest.enabled:
				continue
			if frame["dst"] == guest.mac:
				_host_rx(dev, guest, frame)
				return
			if frame["dst"] == BCAST:
				_host_rx(dev, guest, frame)
	if frame["dst"] != iface.mac and frame["dst"] != BCAST:
		return
	var p: Dictionary = frame["pl"]
	if frame["type"] == "dhcp":
		_dhcp_rx(dev, iface, frame)
		return
	if frame["type"] == "arp" or frame["type"] == "ndp":
		var nkey := _neigh_key(iface, String(p["spa"]))
		if p["op"] == "req":
			var lb_vip: String = String(dev.services.get("lb", {}).get("vip", ""))
			if _iface_owns_ip(iface, p["tpa"]) or _vrrp_owns(dev, iface, p["tpa"]) \
					or (lb_vip != "" and Net.addr_eq(lb_vip, String(p["tpa"]))):
				dev.arp[nkey] = p["sha"]
				_tx(iface, {"src": iface.mac, "dst": p["sha"], "vlan": 0, "type": frame["type"],
					"pl": {"op": "rep", "spa": p["tpa"], "sha": iface.mac, "tpa": p["spa"]}})
		else:
			dev.arp[nkey] = p["sha"]
		return
	# ipv4
	if dev.ip_forwarding and _has_ip(dev, p["dst_ip"]):
		var flow_id: int = p["l4"].get("id", 0)
		var lb_svc: Dictionary = dev.services.get("lb", {})
		if not lb_svc.is_empty() and dev.nat_flows.has(flow_id):
			var back_lb := p.duplicate(true)
			back_lb["src_ip"] = String(dev.nat_flows[flow_id])  # answer as the virtual address
			back_lb["ttl"] = int(p["ttl"]) - 1
			var rt_back := _route_lookup(dev, back_lb["dst_ip"], "", iface.vrf)
			if not rt_back.is_empty():
				var mac_back := _arp_resolve(dev, rt_back["iface"], rt_back["next_hop"])
				if mac_back != "":
					_tx(rt_back["iface"], {"src": rt_back["iface"].mac, "dst": mac_back,
						"vlan": 0, "type": "ipv4", "pl": back_lb})
			return
		var n64_back := nat64_of(dev)
		if not n64_back.is_empty() and dev.nat64_flows.has(flow_id) \
				and Net.addr_eq(String(n64_back.get("pool", "")), String(p["dst_ip"])):
			var back64 := p.duplicate(true)
			back64["src_ip"] = synth64(String(n64_back.get("prefix", "")), String(p["src_ip"]))
			back64["dst_ip"] = String(dev.nat64_flows[flow_id])
			back64["ttl"] = int(p["ttl"]) - 1
			dev.nat64_flows.erase(flow_id)  # bounded state: one exchange, one entry
			n64_back["returned"] = int(n64_back.get("returned", 0)) + 1
			var rt64 := _route_lookup(dev, back64["dst_ip"], "", iface.vrf)
			if not rt64.is_empty():
				var mac64 := _arp_resolve(dev, rt64["iface"], rt64["next_hop"])
				if mac64 != "":
					_tx(rt64["iface"], {"src": rt64["iface"].mac, "dst": mac64, "vlan": 0,
						"type": "ipv4", "pl": back64})
			return
		var out_if := _nat_outside(dev)
		if out_if != null and dev.nat_flows.has(flow_id) and _iface_owns_ip(out_if, p["dst_ip"]):
			var back := p.duplicate(true)
			back["dst_ip"] = dev.nat_flows[flow_id]
			back["ttl"] -= 1
			var rt2 := _route_lookup(dev, back["dst_ip"])
			if not rt2.is_empty():
				var mac2 := _arp_resolve(dev, rt2["iface"], rt2["next_hop"])
				if mac2 != "":
					_tx(rt2["iface"], {"src": rt2["iface"].mac, "dst": mac2, "vlan": 0,
						"type": "ipv4", "pl": back})
			return
	# a load balancer answers for its virtual address and hands the work on
	var lb: Dictionary = dev.services.get("lb", {})
	if not lb.is_empty() and Net.addr_eq(String(lb.get("vip", "")), String(p["dst_ip"])):
		var pool: Array = lb.get("healthy", [])
		if pool.is_empty():
			return  # nothing healthy to serve it
		var pick: String = pool[hash("%s|%s" % [p["src_ip"], str(p["l4"].get("id", 0))]) % pool.size()]
		dev.nat_flows[int(p["l4"].get("id", 0))] = String(lb["vip"])
		var fwd_lb := p.duplicate(true)
		fwd_lb["dst_ip"] = pick
		fwd_lb["ttl"] = int(p["ttl"]) - 1
		var rt_lb := _route_lookup(dev, pick, "", iface.vrf)
		if rt_lb.is_empty():
			return
		var mac_lb := _arp_resolve(dev, rt_lb["iface"], rt_lb["next_hop"])
		if mac_lb == "":
			return
		_tx(rt_lb["iface"], {"src": rt_lb["iface"].mac, "dst": mac_lb, "vlan": 0,
			"type": "ipv4", "pl": fwd_lb})
		return
	var vrrp_local := _vrrp_owns(dev, iface, p["dst_ip"])
	if _has_ip(dev, p["dst_ip"]) or vrrp_local:
		var l4: Dictionary = p["l4"]
		if l4["proto"] == "icmp":
			match l4["type"]:
				"echo":
					_send_ip(dev, p["src_ip"], 64, {"proto": "icmp", "type": "reply", "id": l4["id"]},
						iface.vrf)
				"reply", "ttl-exceeded", "unreachable":
					_echo_results.append({"type": l4["type"], "id": l4["id"], "from": p["src_ip"],
						"ttl": int(p.get("ttl", 64)), "code": l4.get("code", "")})
		elif l4["proto"] == "dns":
			var svc_dns: Dictionary = dev.services.get("dns", {})
			var recs: Dictionary = svc_dns.get("records", {})
			var zones: Dictionary = svc_dns.get("delegations", {})
			var want6: bool = bool(l4.get("v6", false))
			var recs6: Dictionary = svc_dns.get("records6", {})
			var ttl_for := int(svc_dns.get("ttls", {}).get(l4["q"], DEFAULT_TTL))
			if want6 and recs6.has(l4["q"]):
				# a native AAAA always wins: synthesis is a last resort
				_send_ip(dev, p["src_ip"], 64, {"proto": "dns-resp", "q": l4["q"],
					"answer": recs6[l4["q"]], "id": l4["id"], "kind": "native", "ttl": ttl_for})
			elif want6 and recs.has(l4["q"]) and bool(svc_dns.get("dns64", {}).get("enabled", false)) \
					and synth64(String(svc_dns["dns64"].get("prefix", "")), String(recs[l4["q"]])) != "":
				_send_ip(dev, p["src_ip"], 64, {"proto": "dns-resp", "q": l4["q"],
					"answer": synth64(String(svc_dns["dns64"]["prefix"]), String(recs[l4["q"]])),
					"id": l4["id"], "kind": "synthesized", "ttl": ttl_for})
			elif want6:
				pass  # no AAAA, no synthesis: the query fails honestly
			elif recs.has(l4["q"]):
				_send_ip(dev, p["src_ip"], 64, {"proto": "dns-resp", "q": l4["q"],
					"answer": recs[l4["q"]], "id": l4["id"], "kind": "native",
					"ttl": ttl_for})
			elif _delegation_for(zones, String(l4["q"])) != "":
				# not ours, but we know who to ask: that is a referral
				_send_ip(dev, p["src_ip"], 64, {"proto": "dns-resp", "q": l4["q"],
					"referral": _delegation_for(zones, String(l4["q"])), "id": l4["id"]})
			elif String(l4["q"]).is_valid_ip_address():
				for nm in recs:  # synthesized PTR from A records
					if recs[nm] == l4["q"]:
						_send_ip(dev, p["src_ip"], 64, {"proto": "dns-resp", "q": l4["q"], "answer": nm, "id": l4["id"]})
						break
		elif l4["proto"] == "vxlan":
			_vxlan_rx(dev, String(p["src_ip"]), l4)
		elif l4["proto"] == "evpn":
			_evpn_rx(dev, String(p["src_ip"]), l4)
		elif l4["proto"] == "dns-resp":
			_dns_results.append(l4)
		elif l4["proto"] == "dhcp-relay" and l4["op"] == "discover":
			var svc2: Dictionary = dev.services.get("dhcp", {})
			if not svc2.is_empty() and Net.same_subnet(l4["giaddr"], svc2["start"], int(svc2["plen"])):
				var leases: Dictionary = svc2["leases"]
				var lease_ip: String
				if leases.has(l4["mac"]):
					lease_ip = leases[l4["mac"]]
				else:
					var nxt := Net.ip_to_int(svc2["start"]) + leases.size()
					if nxt > Net.ip_to_int(svc2["end"]):
						return
					lease_ip = Net.int_to_ip(nxt)
					leases[l4["mac"]] = lease_ip
				_send_ip(dev, p["src_ip"], 64, {"proto": "dhcp-relay", "op": "ack",
					"mac": l4["mac"], "ip": lease_ip, "plen": svc2["plen"],
					"gw": l4["giaddr"], "dns": svc2.get("dns", "")})
		elif l4["proto"] == "dhcp-relay" and l4["op"] == "ack":
			# the relay router: hand the lease back to the client as an L2 ack
			for i: Net.Iface in dev.ifaces:
				if i.helper != "" and _iface_owns_ip(i, l4["gw"]):
					_tx(i, {"src": i.mac, "dst": l4["mac"], "vlan": 0, "type": "dhcp",
						"pl": {"op": "ack", "mac": l4["mac"], "ip": l4["ip"],
							"plen": l4["plen"], "gw": l4["gw"], "dns": l4["dns"]}})
	elif dev.ip_forwarding:
		var flow_key := "%s|%s|%s" % [str(p["l4"].get("id", 0)), p["dst_ip"], p["src_ip"]]
		var is_return: bool = dev.stateful and dev.flows.has(flow_key)
		if not is_return and not _acl_permits(dev, p["src_ip"], p["dst_ip"]):
			_icmp_unreachable(dev, p, "admin", iface.vrf)  # filtered by firewall policy
			return
		if dev.stateful:
			dev.flows["%s|%s|%s" % [str(p["l4"].get("id", 0)), p["src_ip"], p["dst_ip"]]] = true
		if p["ttl"] <= 1:
			_send_ip(dev, p["src_ip"], 64,
				{"proto": "icmp", "type": "ttl-exceeded", "id": p["l4"].get("id", 0)}, iface.vrf)
			return
		# NAT64: an IPv6 packet addressed into the translation prefix leaves
		# here as IPv4, and the state to bring the answer back lives on us
		var n64 := nat64_of(dev)
		if not n64.is_empty() and Net.is_v6(String(p["dst_ip"])):
			var embedded := extract64(String(n64.get("prefix", "")), String(p["dst_ip"]))
			if embedded != "":
				if String(n64.get("pool", "")) == "":
					n64["last_error"] = "no IPv4 pool address configured"
					return
				if _route_lookup(dev, embedded, "", iface.vrf).is_empty():
					n64["last_error"] = "no IPv4 route to %s" % embedded
					return
				dev.nat64_flows[int(p["l4"].get("id", 0))] = String(p["src_ip"])
				n64["translated"] = int(n64.get("translated", 0)) + 1
				n64["last_error"] = ""
				p = p.duplicate(true)
				p["src_ip"] = String(n64["pool"])
				p["dst_ip"] = embedded
		var rt := _route_lookup(dev, p["dst_ip"],
			"%s|%s|%s" % [p["src_ip"], p["dst_ip"], str(p["l4"].get("id", 0))], iface.vrf)
		if rt.is_empty():
			_icmp_unreachable(dev, p, "net", iface.vrf)
			return
		if rt.get("next_hop", "") == "null0":
			return  # deliberately discarded: a blackhole is silent
		var out: Net.Iface = rt["iface"]
		var mac := _arp_resolve(dev, out, rt["next_hop"])
		if mac == "":
			_icmp_unreachable(dev, p, "host", iface.vrf)
			return
		# netflow-style accounting: who is actually pushing traffic through here
		var talk_key := "%s>%s" % [p["src_ip"], p["dst_ip"]]
		dev.talkers[talk_key] = int(dev.talkers.get(talk_key, 0)) + 1
		var fwd := p.duplicate(true)
		fwd["ttl"] -= 1
		if out.nat == "outside":
			# source NAT: hide the private source behind our outside address
			dev.nat_flows[fwd["l4"].get("id", 0)] = fwd["src_ip"]
			fwd["src_ip"] = _first_ip(out)
		_tx(out, {"src": out.mac, "dst": mac, "vlan": 0, "type": "ipv4", "pl": fwd})

static func frame_size(frame: Dictionary) -> int:
	## payload bytes plus the headers a real frame would carry
	var pl: Dictionary = frame.get("pl", {})
	if not (pl is Dictionary):
		return 0
	var l4: Dictionary = pl.get("l4", {})
	var payload := int(l4.get("size", 0)) if l4 is Dictionary else 0
	if payload <= 0:
		return 0  # control traffic: small enough that MTU never matters
	return payload + 28  # IP and ICMP headers

static func effective_duplex(i: Net.Iface, far: Net.Iface) -> String:
	## what this end actually runs: a forced setting wins; auto against ANY
	## forced end cannot negotiate and falls back to half, which is why
	## "one side hard-coded to full" is the classic mismatch; auto with auto is full
	if i.duplex != "auto":
		return i.duplex
	return "half" if far.duplex != "auto" else "full"

static func duplex_mismatch(a: Net.Iface, b: Net.Iface) -> bool:
	return effective_duplex(a, b) != effective_duplex(b, a)

static func _too_big(iface: Net.Iface, frame: Dictionary) -> bool:
	## A port silently drops what will not fit, and so does the far end if it
	## was configured with a smaller MTU. That asymmetry is the classic bug:
	## small packets work, large ones vanish, and nothing logs a thing.
	var size := frame_size(frame)
	if size <= 0:
		return false
	var limits: Array = [[iface, iface.mtu]]
	var l := Game.link_at(iface)
	if l != null:
		var far: Net.Iface = l.b if l.a == iface else l.a
		limits.append([far, far.mtu])
	for pair in limits:
		var port: Net.Iface = pair[0]
		var mtu: int = int(pair[1])
		if mtu > 0 and size > mtu:
			if port == iface:
				port.out_drops += 1  # would not go out: too big for this port
			else:
				port.rx_giants += 1  # arrived too big for the far end
			last_mtu_drop = "dropped: %d bytes will not fit the %d byte MTU on %s %s" % [
				size, mtu, port.dev.name, port.name]
			Game.device_log(port.dev, "MTU: dropped a %d byte frame on %s (MTU %d)"
				% [size, port.name, mtu])
			return true
	return false

static func _cap(dev: Net.NDevice, iface: Net.Iface, frame: Dictionary) -> void:
	## tcpdump-style one-liner for the device's capture ring
	var p: Dictionary = frame["pl"]
	var desc := ""
	match frame["type"]:
		"dhcp":
			desc = "DHCP %s %s" % [p["op"], p.get("mac", "")]
		"arp":
			desc = ("ARP who-has %s tell %s" % [p["tpa"], p["spa"]]) if p["op"] == "req" \
				else ("ARP reply %s is-at %s" % [p["spa"], p["sha"]])
		"ndp":
			desc = ("NDP solicit %s from %s" % [p["tpa"], p["spa"]]) if p["op"] == "req" \
				else ("NDP advert %s is-at %s" % [p["spa"], p["sha"]])
		_:
			var l4: Dictionary = p.get("l4", {})
			desc = "%s %s > %s %s %s ttl %d" % ["IP6" if Net.is_v6(String(p["src_ip"])) else "IP",
				p["src_ip"], p["dst_ip"], String(l4.get("proto", "?")).to_upper(),
				str(l4.get("type", l4.get("q", ""))), int(p["ttl"])]
	var vl := (" [vlan %d]" % frame["vlan"]) if frame["vlan"] != 0 else ""
	dev.capture.append("%-10s %s%s" % [iface.name, desc, vl])
	if dev.capture.size() > 50:
		dev.capture.pop_front()

static func vrrp_master(vip: String, group: int) -> Net.NDevice:
	## alive router with the highest priority (tie: highest real IP) wins
	var best: Net.NDevice = null
	var best_prio := -1
	var best_ip := -1
	for d in Game.all_devices():
		if not d.ip_forwarding or d.status != "active":
			continue
		for i: Net.Iface in d.ifaces:
			if not i.enabled or i.vrrp.is_empty():
				continue
			if i.vrrp.get("vip", "") != vip or int(i.vrrp.get("group", -1)) != group:
				continue
			var prio: int = int(i.vrrp.get("priority", 100))
			var ipn := Net.ip_to_int(_first_ip(i))
			if prio > best_prio or (prio == best_prio and ipn > best_ip):
				best = d
				best_prio = prio
				best_ip = ipn
	return best

static func _vrrp_owns(dev: Net.NDevice, iface: Net.Iface, ip: String) -> bool:
	if iface.vrrp.is_empty() or iface.vrrp.get("vip", "") != ip:
		return false
	return vrrp_master(ip, int(iface.vrrp.get("group", -1))) == dev

static func _icmp_unreachable(dev: Net.NDevice, p: Dictionary, code: String, vrf: String) -> void:
	## Destination Unreachable back to the sender. Never about another ICMP
	## error (RFC 1122), or two routers could bounce complaints forever.
	var l4: Dictionary = p.get("l4", {})
	if l4.get("proto", "") == "icmp" and l4.get("type", "") in ["ttl-exceeded", "unreachable"]:
		return
	_send_ip(dev, p["src_ip"], 64, {"proto": "icmp", "type": "unreachable", "code": code,
		"id": l4.get("id", 0)}, vrf)

static func _nat_outside(dev: Net.NDevice) -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if i.nat == "outside":
			return i
	return null

static func _acl_permits(dev: Net.NDevice, src_ip: String, dst_ip: String) -> bool:
	for rule in dev.acls:  # first match wins; default permit
		if Net.same_subnet(src_ip, rule["src"], int(rule["splen"])) \
				and Net.same_subnet(dst_ip, rule["dst"], int(rule["dplen"])):
			return rule["action"] == "permit"
	return true

static func bond_members(iface: Net.Iface) -> Array:
	## every leg of the same bond on this device, itself included
	if iface.lag <= 0:
		return [iface]
	var out: Array = []
	for i: Net.Iface in iface.dev.ifaces:
		if i.lag == iface.lag:
			out.append(i)
	return out

static func _iface_owns_ip(iface: Net.Iface, ip: String) -> bool:
	# a bond is one interface as far as addressing is concerned, so any leg
	# answers for an address configured on any other leg
	for member: Net.Iface in bond_members(iface):
		for cidr: String in member.ips:
			if Net.addr_eq(cidr.split("/")[0], ip):
				return true
	return false


## ---------- VXLAN: a layer 2 segment carried over the routed network ----------

static func vtep_vni(dev: Net.NDevice, vlan: int) -> int:
	return int(dev.vtep.get("map", {}).get(vlan, 0))

static func _vxlan_tx(dev: Net.NDevice, in_if: Net.Iface, vlan: int, frame: Dictionary) -> void:
	if dev.vtep.is_empty() or String(dev.vtep.get("src", "")) == "":
		return
	var vni := vtep_vni(dev, vlan)
	if vni == 0:
		return
	if String(frame.get("vxlan_from", "")) != "":
		return  # it arrived over the overlay: it does not go back out over it
	var payload := {"proto": "vxlan", "vni": vni, "frame": frame.duplicate(true),
		"id": int(frame.get("pl", {}).get("l4", {}).get("id", 0)) if frame.get("pl") is Dictionary
			else 0}
	var dst_mac := String(frame["dst"])
	var known_remote: String = String(dev.remote_macs.get(vlan, {}).get(dst_mac, ""))
	var targets: Array = []
	if dst_mac != BCAST and known_remote != "":
		targets.append(known_remote)  # the control plane knows exactly where it is
	elif dst_mac == BCAST or (not dev.mac_table.get(vlan, {}).has(dst_mac)
			and static_port(dev, vlan, dst_mac) == null):
		targets = dev.vtep.get("peers", []).duplicate()  # flood to the peers we know
	for peer: String in targets:
		if peer == String(dev.vtep["src"]):
			continue
		_send_ip(dev, peer, 64, payload)

static func _vxlan_rx(dev: Net.NDevice, from_ip: String, l4: Dictionary) -> void:
	if dev.vtep.is_empty():
		return
	var vni := int(l4.get("vni", 0))
	var vlan := 0
	for mapped_vlan: int in dev.vtep.get("map", {}):
		if int(dev.vtep["map"][mapped_vlan]) == vni:
			vlan = int(mapped_vlan)
	if vlan == 0 or not dev.vlans.has(vlan):
		return  # a VNI this switch does not carry: drop it, quietly, like real gear
	var inner: Dictionary = l4.get("frame", {}).duplicate(true)
	if inner.is_empty():
		return
	# whatever came out of the tunnel lives behind that VTEP, not behind a port
	if not dev.remote_macs.has(vlan):
		dev.remote_macs[vlan] = {}
	dev.remote_macs[vlan][String(inner["src"])] = from_ip
	inner["vxlan_from"] = from_ip
	inner["vlan"] = vlan
	for out_if: Net.Iface in dev.ifaces:
		if out_if.mode == "access" and out_if.untagged_vlan == vlan and out_if.enabled:
			var copy := inner.duplicate(true)
			copy["vlan"] = 0
			_tx(out_if, copy)
	for svi: Net.Iface in dev.ifaces:
		if svi.name == "Vlan%d" % vlan and svi.enabled:
			_host_rx(dev, svi, inner)

## ---------- EVPN-lite: telling the other VTEPs what is behind you ----------

static func evpn_advertise(dev: Net.NDevice, vlan: int, mac: String, withdraw := false) -> void:
	if dev.vtep.is_empty() or not bool(dev.vtep.get("evpn", false)):
		return
	var vni := vtep_vni(dev, vlan)
	if vni == 0:
		return
	for peer: String in dev.vtep.get("peers", []):
		if peer == String(dev.vtep.get("src", "")):
			continue
		_send_ip(dev, peer, 64, {"proto": "evpn", "op": "withdraw" if withdraw else "advertise",
			"vni": vni, "mac": mac, "vtep": String(dev.vtep["src"])})

static func _evpn_rx(dev: Net.NDevice, _from_ip: String, l4: Dictionary) -> void:
	if dev.vtep.is_empty():
		return
	var vni := int(l4.get("vni", 0))
	var vlan := 0
	for mapped_vlan: int in dev.vtep.get("map", {}):
		if int(dev.vtep["map"][mapped_vlan]) == vni:
			vlan = int(mapped_vlan)
	if vlan == 0:
		return
	if not dev.remote_macs.has(vlan):
		dev.remote_macs[vlan] = {}
	if String(l4.get("op", "")) == "withdraw":
		dev.remote_macs[vlan].erase(String(l4["mac"]))
	else:
		dev.remote_macs[vlan][String(l4["mac"])] = String(l4["vtep"])
