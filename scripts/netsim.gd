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
const MAX_DEPTH := 400  # flood guard for misconfigurations STP cannot see

static var _depth := 0
static var _echo_id := 0
static var _echo_results: Array = []
static var rtt_ms := 0.0  # accumulated latency of the operation in flight
static var last_trace: Array = []  # [{a: Iface, b: Iface, kind}] of the last operation
static var _dns_results: Array = []
static var _dns_id := 0
static var _dhcp_offer := {}

# ---------- public operations ----------

static func ping(dev: Net.NDevice, dst_ip: String, ttl := 64, vrf := "") -> Dictionary:
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
	if _has_ip(dev, dst_ip):
		_echo_results = outer_results
		rtt_ms = outer_rtt
		return {"ok": true, "from": dst_ip, "detail": "", "rtt": 0.0}  # loopback: our own address
	var my_id := _echo_id
	var err := _send_ip(dev, dst_ip, ttl, {"proto": "icmp", "type": "echo", "id": my_id}, vrf)
	var result := {"ok": false, "from": "", "detail": "timeout"}
	if err != "":
		result = {"ok": false, "from": "", "detail": err}
	else:
		for r in _echo_results:
			if r["id"] != my_id:
				continue
			if r["type"] == "reply":
				result = {"ok": true, "from": r["from"], "detail": ""}
				break
			if r["type"] == "ttl-exceeded":
				result = {"ok": false, "from": r["from"], "detail": "ttl-exceeded"}
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
		hops.append(r["from"] if r["from"] != "" else "*")
		if r["detail"] != "ttl-exceeded" and r["from"] == "":
			break  # unreachable: no point probing further
	return hops

static func dhcp_request(dev: Net.NDevice, iface: Net.Iface) -> Dictionary:
	## Broadcast a DHCP discover on iface; a reachable DHCP server in the same
	## broadcast domain answers. On success the lease is applied to the iface.
	_dhcp_offer = {}
	if _depth == 0:
		last_trace = []
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

static func resolve(dev: Net.NDevice, name: String) -> String:
	## DNS lookup via the device's configured resolver. Returns "" on failure.
	if name.is_valid_ip_address():
		return name
	if dev.resolver == "":
		return ""
	_dns_id += 1
	_dns_results = []
	_send_ip(dev, dev.resolver, 64, {"proto": "dns", "q": name, "id": _dns_id})
	for r in _dns_results:
		if r["id"] == _dns_id and r["q"] == name:
			return r["answer"]
	return ""

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
			for net in peer.bgp.get("networks", []):
				var parts := String(net).split("/")
				out.append({"prefix": parts[0], "plen": int(parts[1]), "via": nb["ip"]})
	for other in Game.all_devices():
		if other == dev or other.bgp.is_empty():
			continue
		for onb in other.bgp.get("neighbors", []):
			if _owns_ip_anywhere(dev, onb["ip"]) and bgp_established(other, onb):
				var via := _ip_of_on_subnet(other, onb["ip"])
				if via == "":
					continue
				for net in other.bgp.get("networks", []):
					var parts := String(net).split("/")
					out.append({"prefix": parts[0], "plen": int(parts[1]), "via": via})
	return out

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
		if not i.enabled or i.vrf != vrf:
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
	var frontier: Array = []
	for nb in ospf_neighbors(dev):
		if not first_hop.has(nb["dev"]):
			first_hop[nb["dev"]] = []
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
					out.append({"prefix": netw["prefix"], "plen": netw["plen"], "via": via})
		for nb in ospf_neighbors(cur):
			if not visited.has(nb["dev"]):
				if not first_hop.has(nb["dev"]):
					first_hop[nb["dev"]] = first_hop[cur].duplicate()
				else:
					for via in first_hop[cur]:
						if via not in first_hop[nb["dev"]]:
							first_hop[nb["dev"]].append(via)
				frontier.append(nb["dev"])
	return out

static func flush_learned_state() -> void:
	_stp_dirty = true
	for d in Game.all_devices():
		d.mac_table.clear()
		d.arp.clear()
		d.nat_flows.clear()
		d.flows.clear()

static func stp_blocked(i: Net.Iface) -> bool:
	_stp_ensure()
	return _stp_blocked.has(i)

static func stp_root_of(dev: Net.NDevice) -> Net.NDevice:
	_stp_ensure()
	return _stp_roots.get(dev, dev)

static var _stp_roots := {}  # switch -> its component's root

static func _stp_ensure() -> void:
	## Simplified 802.1D: lowest-MAC switch is root; BFS spanning tree over
	## switch-switch links; every off-tree link blocks its far-from-root end.
	if not _stp_dirty:
		return
	_stp_dirty = false
	_stp_blocked = {}
	_stp_roots = {}
	var switches: Array = []
	for d in Game.all_devices():
		if d.type == "switch" and d.status == "active":
			switches.append(d)
	if switches.is_empty():
		return
	switches.sort_custom(func(x, y): return x.ifaces[0].mac < y.ifaces[0].mac)
	var sw_links: Array = []
	for l in Game.links:
		if l.a.dev.type == "switch" and l.b.dev.type == "switch" and l.a.enabled and l.b.enabled and not l.a.name.begins_with("Management") and not l.b.name.begins_with("Management") and l.a.dev.status == "active" and l.b.dev.status == "active":
			sw_links.append(l)
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
	for sw in switches:  # sorted by mac, so the first unseen switch roots its component
		if dist.has(sw):
			continue
		dist[sw] = 0
		var frontier: Array = [sw]
		while not frontier.is_empty():
			frontier.sort_custom(func(x, y): return x.ifaces[0].mac < y.ifaces[0].mac)
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
		if db > da or (db == da and e["b"].ifaces[0].mac > e["a"].ifaces[0].mac):
			victim_dev = e["b"]
		for l in e["links"]:
			_stp_blocked[l.a if l.a.dev == victim_dev else l.b] = true

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
	var cands := _all_routes(dev, dst_ip, vrf)
	var best_len := -1
	for c in cands:
		best_len = maxi(best_len, int(c["plen"]))
	if best_len < 0:
		return []
	var out: Array = []
	var seen := {}
	for cand in cands:
		if int(cand["plen"]) != best_len:
			continue
		var key := "%s|%s" % [str(cand["next_hop"]), str(cand["iface"])]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(cand)
	return out

static func _all_routes(dev: Net.NDevice, dst_ip: String, vrf := "") -> Array:
	## every candidate path in one routing table, with the prefix length used
	var out: Array = []
	var want_v6 := Net.is_v6(dst_ip)
	for i: Net.Iface in dev.ifaces:
		if not i.enabled or i.vrf != vrf:
			continue
		for cidr: String in i.ips:
			if Net.is_v6(cidr) != want_v6:
				continue
			var parts := cidr.split("/")
			if Net.same_net(dst_ip, parts[0], int(parts[1])):
				out.append({"iface": i, "next_hop": dst_ip, "plen": int(parts[1])})
	for r in dev.static_routes + _bgp_learned(dev) + _ospf_learned(dev):
		if Net.is_v6(String(r["prefix"])) != want_v6 or String(r.get("vrf", "")) != vrf:
			continue
		if not Net.same_net(dst_ip, r["prefix"], int(r["plen"])):
			continue
		if String(r["via"]) == "null0":
			out.append({"iface": null, "next_hop": "null0", "plen": int(r["plen"])})
			continue
		var via_if := _connected_iface(dev, String(r["via"]), vrf)
		if via_if:
			out.append({"iface": via_if, "next_hop": r["via"], "plen": int(r["plen"])})
	return out

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
	if _depth > MAX_DEPTH:
		return
	if not iface.enabled or iface.dev.status != "active":
		return
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
	var peer: Net.Iface = l.other(iface)
	if not peer.enabled or peer.dev.status != "active":
		return
	iface.tx_frames += 1
	peer.rx_frames += 1
	rtt_ms += Game.link_latency_ms(l)
	if last_trace.size() < 300:
		last_trace.append({"a": iface, "b": peer, "kind": frame["type"]})
	_cap(peer.dev, peer, frame)
	_depth += 1
	if peer.dev.type == "switch" and not peer.name.begins_with("Management"):
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
	var known: Net.Iface = table.get(frame["dst"])
	var outs: Array = [known] if (known != null and frame["dst"] != BCAST) else dev.ifaces
	var lags_done := {}
	for o: Net.Iface in outs:
		if o == svi or o.name.begins_with("Vlan") or o.name == "lo" or stp_blocked(o):
			continue
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
			f["vlan"] = vlan
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

static func _switch_rx(dev: Net.NDevice, in_if: Net.Iface, frame: Dictionary) -> void:
	if stp_blocked(in_if):
		return  # spanning tree: discarding state
	var vlan: int
	if in_if.mode == "access":
		if frame["vlan"] != 0:
			return  # tagged frame on access port: drop
		vlan = in_if.untagged_vlan
	else:  # trunk: native VLAN 1 for untagged
		vlan = frame["vlan"] if frame["vlan"] != 0 else 1
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
	if in_if.port_security:
		if in_if.secure_mac == "":
			in_if.secure_mac = frame["src"]  # sticky: learn the first device
		elif in_if.secure_mac != frame["src"]:
			in_if.violations += 1
			in_if.enabled = false
			Game.device_log(dev, "port-security violation on %s: saw %s" % [in_if.name, frame["src"]])
			Game.log_event("PORT SECURITY: %s %s saw %s instead of %s and shut down."
				% [dev.name, in_if.name, frame["src"], in_if.secure_mac])
			Game.topology_changed.emit()
			return
	dev.mac_table[vlan][frame["src"]] = in_if
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
	var known: Net.Iface = dev.mac_table[vlan].get(frame["dst"])
	var outs: Array = [known] if (known != null and frame["dst"] != BCAST) else dev.ifaces
	var lags_done := {}
	for o: Net.Iface in outs:
		if o == in_if or stp_blocked(o):
			continue
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
			f["vlan"] = vlan
		else:
			continue
		_tx(o, f)

static func _logical_rx_iface(phys: Net.Iface, frame: Dictionary) -> Net.Iface:
	## a tagged frame belongs to the matching 802.1Q subinterface, if any
	if int(frame.get("vlan", 0)) == 0:
		return phys
	for sub: Net.Iface in phys.dev.ifaces:
		if sub.parent == phys.name and sub.dot1q == int(frame["vlan"]) and sub.enabled:
			return sub
	return phys

static func _host_rx(dev: Net.NDevice, iface: Net.Iface, frame: Dictionary) -> void:
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
				"reply", "ttl-exceeded":
					_echo_results.append({"type": l4["type"], "id": l4["id"], "from": p["src_ip"]})
		elif l4["proto"] == "dns":
			var recs: Dictionary = dev.services.get("dns", {}).get("records", {})
			if recs.has(l4["q"]):
				_send_ip(dev, p["src_ip"], 64, {"proto": "dns-resp", "q": l4["q"], "answer": recs[l4["q"]], "id": l4["id"]})
			elif String(l4["q"]).is_valid_ip_address():
				for nm in recs:  # synthesized PTR from A records
					if recs[nm] == l4["q"]:
						_send_ip(dev, p["src_ip"], 64, {"proto": "dns-resp", "q": l4["q"], "answer": nm, "id": l4["id"]})
						break
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
			return  # filtered by firewall policy
		if dev.stateful:
			dev.flows["%s|%s|%s" % [str(p["l4"].get("id", 0)), p["src_ip"], p["dst_ip"]]] = true
		if p["ttl"] <= 1:
			_send_ip(dev, p["src_ip"], 64,
				{"proto": "icmp", "type": "ttl-exceeded", "id": p["l4"].get("id", 0)}, iface.vrf)
			return
		var rt := _route_lookup(dev, p["dst_ip"],
			"%s|%s|%s" % [p["src_ip"], p["dst_ip"], str(p["l4"].get("id", 0))], iface.vrf)
		if rt.is_empty() or rt.get("next_hop", "") == "null0":
			return  # no route, or deliberately discarded
		var out: Net.Iface = rt["iface"]
		var mac := _arp_resolve(dev, out, rt["next_hop"])
		if mac == "":
			return
		var fwd := p.duplicate(true)
		fwd["ttl"] -= 1
		if out.nat == "outside":
			# source NAT: hide the private source behind our outside address
			dev.nat_flows[fwd["l4"].get("id", 0)] = fwd["src_ip"]
			fwd["src_ip"] = _first_ip(out)
		_tx(out, {"src": out.mac, "dst": mac, "vlan": 0, "type": "ipv4", "pl": fwd})

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

static func _iface_owns_ip(iface: Net.Iface, ip: String) -> bool:
	for cidr: String in iface.ips:
		if Net.addr_eq(cidr.split("/")[0], ip):
			return true
	return false
