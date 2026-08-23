class_name Sim
## Packet-level network simulation. Frames propagate synchronously through
## the topology: switches learn MACs and flood/forward per VLAN, hosts and
## routers run a small IP stack (ARP, ICMP, TTL, static routing).
##
## Frame: {src, dst, vlan, type: "arp"|"ipv4", pl: Dictionary}
##   vlan 0 = untagged on the wire; switches assign the bridging VLAN.
## ARP pl:  {op: "req"|"rep", spa, sha, tpa}
## IPv4 pl: {src_ip, dst_ip, ttl, icmp: {type: "echo"|"reply"|"ttl-exceeded", id}}

const BCAST := "ff:ff:ff:ff:ff:ff"
const MAX_DEPTH := 400  # loop guard until STP exists (issue #18)

static var _depth := 0
static var _echo_id := 0
static var _echo_results: Array = []
static var last_trace: Array = []  # [{a: Iface, b: Iface, kind}] of the last operation

# ---------- public operations ----------

static func ping(dev: Net.NDevice, dst_ip: String, ttl := 64) -> Dictionary:
	## -> {ok: bool, from: String (replier), detail: String}
	_echo_id += 1
	_echo_results = []
	if _depth == 0:
		last_trace = []
	var err := _send_ip(dev, dst_ip, ttl, {"type": "echo", "id": _echo_id})
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

static func flush_learned_state() -> void:
	for d in Game.all_devices():
		d.mac_table.clear()
		d.arp.clear()

# ---------- IP stack (hosts & routers) ----------

static func _send_ip(dev: Net.NDevice, dst_ip: String, ttl: int, icmp: Dictionary) -> String:
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
		"pl": {"src_ip": src_ip, "dst_ip": dst_ip, "ttl": ttl, "icmp": icmp}})
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
	if peer.dev.type == "switch":
		_switch_rx(peer.dev, peer, frame)
	else:
		_host_rx(peer.dev, peer, frame)
	_depth -= 1

static func _switch_rx(dev: Net.NDevice, in_if: Net.Iface, frame: Dictionary) -> void:
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
		if o == in_if:
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
	if _has_ip(dev, p["dst_ip"]):
		match p["icmp"]["type"]:
			"echo":
				_send_ip(dev, p["src_ip"], 64, {"type": "reply", "id": p["icmp"]["id"]})
			"reply", "ttl-exceeded":
				_echo_results.append({"type": p["icmp"]["type"], "id": p["icmp"]["id"], "from": p["src_ip"]})
	elif dev.ip_forwarding:
		if p["ttl"] <= 1:
			_send_ip(dev, p["src_ip"], 64, {"type": "ttl-exceeded", "id": p["icmp"]["id"]})
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
		_tx(out, {"src": out.mac, "dst": mac, "vlan": 0, "type": "ipv4", "pl": fwd})

static func _cap(dev: Net.NDevice, iface: Net.Iface, frame: Dictionary) -> void:
	var p: Dictionary = frame["pl"]
	var desc: String
	if frame["type"] == "arp":
		if p["op"] == "req":
			desc = "ARP who-has %s tell %s" % [p["tpa"], p["spa"]]
		else:
			desc = "ARP reply %s is-at %s" % [p["spa"], p["sha"]]
	else:
		desc = "IP %s > %s ICMP %s ttl %d" % [p["src_ip"], p["dst_ip"], p["icmp"]["type"], p["ttl"]]
	var vl := (" [vlan %d]" % frame["vlan"]) if frame["vlan"] != 0 else ""
	dev.capture.append("%-10s %s%s" % [iface.name, desc, vl])
	if dev.capture.size() > 50:
		dev.capture.pop_front()

static func _iface_owns_ip(iface: Net.Iface, ip: String) -> bool:
	for cidr: String in iface.ips:
		if cidr.split("/")[0] == ip:
			return true
	return false
