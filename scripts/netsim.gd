class_name Sim
## Packet-level network simulation. Frames propagate synchronously through
## the topology: switches learn MACs and flood/forward per VLAN, hosts and
## routers run a small IP stack (ARP, ICMP, TTL, static routing).
##
## Frame: {src, dst, vlan, type: "arp"|"ipv4", pl: Dictionary}
##   vlan 0 = untagged on the wire; switches assign the bridging VLAN.
## ARP pl:  {op: "req"|"rep", spa, sha, tpa}
## IPv4 pl: {src_ip, dst_ip, ttl, l4: {proto: "icmp"|"dns", ...}}
## DHCP pl: {op: "discover"|"ack", mac, ...lease fields} — pure L2 broadcast

const BCAST := "ff:ff:ff:ff:ff:ff"
const MAX_DEPTH := 400  # loop guard until STP exists (issue #18)

static var _depth := 0
static var _echo_id := 0
static var _echo_results: Array = []
static var last_trace: Array = []  # [{a: Iface, b: Iface, kind}] of the last operation
static var _dns_results: Array = []
static var _dns_id := 0
static var _dhcp_offer := {}

# ---------- public operations ----------

static func ping(dev: Net.NDevice, dst_ip: String, ttl := 64) -> Dictionary:
	## -> {ok: bool, from: String (replier), detail: String}
	_echo_id += 1
	_echo_results = []
	if _depth == 0:
		last_trace = []
	if _has_ip(dev, dst_ip):
		return {"ok": true, "from": dst_ip, "detail": ""}  # loopback: our own address
	var err := _send_ip(dev, dst_ip, ttl, {"proto": "icmp", "type": "echo", "id": _echo_id})
	if err != "":
		return {"ok": false, "from": "", "detail": err}
	for r in _echo_results:
		if r["id"] != _echo_id:
			continue
		if r["type"] == "reply":
			return {"ok": true, "from": r["from"], "detail": ""}
		if r["type"] == "ttl-exceeded":
			return {"ok": false, "from": r["from"], "detail": "ttl-exceeded"}
	return {"ok": false, "from": "", "detail": "timeout"}

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
			break  # unreachable — no point probing further
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
				if cidr.split("/")[0] == ip:
					return d
	return null

static func _owns_ip_anywhere(dev: Net.NDevice, ip: String) -> bool:
	for i: Net.Iface in dev.ifaces:
		for cidr: String in i.ips:
			if cidr.split("/")[0] == ip:
				return true
	return false

static func _connected_iface(dev: Net.NDevice, ip: String) -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if not i.enabled:
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
	var first_hop := {}  # router -> via_ip of dev's first hop
	var frontier: Array = []
	for nb in ospf_neighbors(dev):
		if not first_hop.has(nb["dev"]):
			first_hop[nb["dev"]] = nb["via_ip"]
			frontier.append(nb["dev"])
	var visited := {dev: true}
	while not frontier.is_empty():
		var cur: Net.NDevice = frontier.pop_front()
		if visited.has(cur):
			continue
		visited[cur] = true
		for i: Net.Iface in ospf_covered_ifaces(cur):
			for cidr: String in i.ips:
				var netw := Net.network_of(cidr)
				out.append({"prefix": netw["prefix"], "plen": netw["plen"], "via": first_hop[cur]})
		for nb in ospf_neighbors(cur):
			if not visited.has(nb["dev"]):
				if not first_hop.has(nb["dev"]):
					first_hop[nb["dev"]] = first_hop[cur]
				frontier.append(nb["dev"])
	return out

static func flush_learned_state() -> void:
	_stp_dirty = true
	for d in Game.all_devices():
		d.mac_table.clear()
		d.arp.clear()
		d.nat_flows.clear()

static func stp_blocked(i: Net.Iface) -> bool:
	_stp_ensure()
	return _stp_blocked.has(i)

static func stp_root() -> Net.NDevice:
	_stp_ensure()
	return _stp_root

static var _stp_root: Net.NDevice = null

static func _stp_ensure() -> void:
	## Simplified 802.1D: lowest-MAC switch is root; BFS spanning tree over
	## switch-switch links; every off-tree link blocks its far-from-root end.
	if not _stp_dirty:
		return
	_stp_dirty = false
	_stp_blocked = {}
	_stp_root = null
	var switches: Array = []
	for d in Game.all_devices():
		if d.type == "switch" and d.status == "active":
			switches.append(d)
	if switches.is_empty():
		return
	switches.sort_custom(func(x, y): return x.ifaces[0].mac < y.ifaces[0].mac)
	_stp_root = switches[0]
	var sw_links: Array = []
	for l in Game.links:
		if l.a.dev.type == "switch" and l.b.dev.type == "switch" 				and l.a.enabled and l.b.enabled 				and l.a.dev.status == "active" and l.b.dev.status == "active":
			sw_links.append(l)
	var dist := {_stp_root: 0}
	var tree := {}
	var frontier: Array = [_stp_root]
	while not frontier.is_empty():
		frontier.sort_custom(func(x, y): return x.ifaces[0].mac < y.ifaces[0].mac)
		var cur: Net.NDevice = frontier.pop_front()
		for l in sw_links:
			if tree.has(l):
				continue
			var nb: Net.NDevice = null
			if l.a.dev == cur:
				nb = l.b.dev
			elif l.b.dev == cur:
				nb = l.a.dev
			if nb != null and not dist.has(nb):
				dist[nb] = dist[cur] + 1
				tree[l] = true
				frontier.append(nb)
	for l in sw_links:
		if tree.has(l):
			continue
		var da: int = dist.get(l.a.dev, 1 << 30)
		var db: int = dist.get(l.b.dev, 1 << 30)
		var victim: Net.Iface = l.a
		if db > da or (db == da and l.b.dev.ifaces[0].mac > l.a.dev.ifaces[0].mac):
			victim = l.b
		_stp_blocked[victim] = true

# ---------- IP stack (hosts & routers) ----------

static func _send_ip(dev: Net.NDevice, dst_ip: String, ttl: int, l4: Dictionary) -> String:
	if dev.status != "active":
		return "device is offline"
	var rt := _route_lookup(dev, dst_ip)
	if rt.is_empty():
		return "no route to host"
	var out: Net.Iface = rt["iface"]
	var src_ip := _first_ip(out)
	var mac := _arp_resolve(dev, out, rt["next_hop"])
	if mac == "":
		return "host unreachable (no ARP reply for %s)" % rt["next_hop"]
	_tx(out, {"src": out.mac, "dst": mac, "vlan": 0, "type": "ipv4",
		"pl": {"src_ip": src_ip, "dst_ip": dst_ip, "ttl": ttl, "l4": l4}})
	return ""

static func _route_lookup(dev: Net.NDevice, dst_ip: String) -> Dictionary:
	var best := {}
	var best_len := -1
	for i: Net.Iface in dev.ifaces:
		if not i.enabled:
			continue
		for cidr: String in i.ips:
			var parts := cidr.split("/")
			var plen := int(parts[1])
			if plen > best_len and Net.same_subnet(dst_ip, parts[0], plen):
				best_len = plen
				best = {"iface": i, "next_hop": dst_ip}
	for r in dev.static_routes:
		if int(r["plen"]) > best_len and Net.same_subnet(dst_ip, r["prefix"], int(r["plen"])):
			var via_rt := {}
			var via_len := -1
			for i: Net.Iface in dev.ifaces:
				if not i.enabled:
					continue
				for cidr: String in i.ips:
					var parts := cidr.split("/")
					if int(parts[1]) > via_len and Net.same_subnet(r["via"], parts[0], int(parts[1])):
						via_len = int(parts[1])
						via_rt = {"iface": i, "next_hop": r["via"]}
			if not via_rt.is_empty():
				best_len = int(r["plen"])
				best = via_rt
	for r in _bgp_learned(dev) + _ospf_learned(dev):
		if int(r["plen"]) > best_len and Net.same_subnet(dst_ip, r["prefix"], int(r["plen"])):
			var out := _connected_iface(dev, r["via"])
			if out:
				best_len = int(r["plen"])
				best = {"iface": out, "next_hop": r["via"]}
	return best

static func _arp_resolve(dev: Net.NDevice, iface: Net.Iface, ip: String) -> String:
	if dev.arp.has(ip):
		return dev.arp[ip]
	_tx(iface, {"src": iface.mac, "dst": BCAST, "vlan": 0, "type": "arp",
		"pl": {"op": "req", "spa": _first_ip(iface), "sha": iface.mac, "tpa": ip}})
	return dev.arp.get(ip, "")

static func _first_ip(iface: Net.Iface) -> String:
	return iface.ips[0].split("/")[0] if not iface.ips.is_empty() else "0.0.0.0"

static func _has_ip(dev: Net.NDevice, ip: String) -> bool:
	for i: Net.Iface in dev.ifaces:
		if i.enabled:
			for cidr: String in i.ips:
				if cidr.split("/")[0] == ip:
					return true
	return false

# ---------- wire / receive ----------

static func _tx(iface: Net.Iface, frame: Dictionary) -> void:
	if _depth > MAX_DEPTH:
		return
	if not iface.enabled or iface.dev.status != "active":
		return
	var l := Game.link_at(iface)
	if l == null:
		return
	var peer: Net.Iface = l.other(iface)
	if not peer.enabled or peer.dev.status != "active":
		return
	if last_trace.size() < 300:
		last_trace.append({"a": iface, "b": peer, "kind": frame["type"]})
	_cap(peer.dev, peer, frame)
	_depth += 1
	if peer.dev.type == "switch" and frame["type"] != "bgp":
		_switch_rx(peer.dev, peer, frame)
	else:
		_host_rx(peer.dev, peer, frame)
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
	if not dev.mac_table.has(vlan):
		dev.mac_table[vlan] = {}
	dev.mac_table[vlan][frame["src"]] = in_if
	var known: Net.Iface = dev.mac_table[vlan].get(frame["dst"])
	var outs: Array = [known] if (known != null and frame["dst"] != BCAST) else dev.ifaces
	for o: Net.Iface in outs:
		if o == in_if or stp_blocked(o):
			continue
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

static func _host_rx(dev: Net.NDevice, iface: Net.Iface, frame: Dictionary) -> void:
	if frame["dst"] != iface.mac and frame["dst"] != BCAST:
		return
	var p: Dictionary = frame["pl"]
	if frame["type"] == "dhcp":
		_dhcp_rx(dev, iface, frame)
		return
	if frame["type"] == "arp":
		if p["op"] == "req":
			if _iface_owns_ip(iface, p["tpa"]):
				dev.arp[p["spa"]] = p["sha"]
				_tx(iface, {"src": iface.mac, "dst": p["sha"], "vlan": 0, "type": "arp",
					"pl": {"op": "rep", "spa": p["tpa"], "sha": iface.mac, "tpa": p["spa"]}})
		else:
			dev.arp[p["spa"]] = p["sha"]
		return
	# ipv4
	if dev.ip_forwarding and _has_ip(dev, p["dst_ip"]):
		var flow_id: int = p["l4"].get("id", 0)
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
	if _has_ip(dev, p["dst_ip"]):
		var l4: Dictionary = p["l4"]
		if l4["proto"] == "icmp":
			match l4["type"]:
				"echo":
					_send_ip(dev, p["src_ip"], 64, {"proto": "icmp", "type": "reply", "id": l4["id"]})
				"reply", "ttl-exceeded":
					_echo_results.append({"type": l4["type"], "id": l4["id"], "from": p["src_ip"]})
		elif l4["proto"] == "dns":
			var recs: Dictionary = dev.services.get("dns", {}).get("records", {})
			if recs.has(l4["q"]):
				_send_ip(dev, p["src_ip"], 64, {"proto": "dns-resp", "q": l4["q"], "answer": recs[l4["q"]], "id": l4["id"]})
		elif l4["proto"] == "dns-resp":
			_dns_results.append(l4)
	elif dev.ip_forwarding:
		if not _acl_permits(dev, p["src_ip"], p["dst_ip"]):
			return  # filtered by firewall policy
		if p["ttl"] <= 1:
			_send_ip(dev, p["src_ip"], 64, {"proto": "icmp", "type": "ttl-exceeded", "id": p["l4"].get("id", 0)})
			return
		var rt := _route_lookup(dev, p["dst_ip"])
		if rt.is_empty():
			return  # ponytail: silently drop; ICMP net-unreachable later
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
	var p: Dictionary = frame["pl"]
	var desc: String
	if frame["type"] == "dhcp":
		_dhcp_rx(dev, iface, frame)
		return
	if frame["type"] == "arp":
		if p["op"] == "req":
			desc = "ARP who-has %s tell %s" % [p["tpa"], p["spa"]]
		else:
			desc = "ARP reply %s is-at %s" % [p["spa"], p["sha"]]
	else:
		desc = "IP %s > %s %s %s ttl %d" % [p["src_ip"], p["dst_ip"],
			String(p["l4"]["proto"]).to_upper(), str(p["l4"].get("type", p["l4"].get("q", ""))), p["ttl"]]
	var vl := (" [vlan %d]" % frame["vlan"]) if frame["vlan"] != 0 else ""
	dev.capture.append("%-10s %s%s" % [iface.name, desc, vl])
	if dev.capture.size() > 50:
		dev.capture.pop_front()

static func _acl_permits(dev: Net.NDevice, src_ip: String, dst_ip: String) -> bool:
	for rule in dev.acls:  # first match wins; default permit
		if Net.same_subnet(src_ip, rule["src"], int(rule["splen"])) \
				and Net.same_subnet(dst_ip, rule["dst"], int(rule["dplen"])):
			return rule["action"] == "permit"
	return true

static func _nat_outside(dev: Net.NDevice) -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if i.nat == "outside":
			return i
	return null

static func _iface_owns_ip(iface: Net.Iface, ip: String) -> bool:
	for cidr: String in iface.ips:
		if cidr.split("/")[0] == ip:
			return true
	return false
