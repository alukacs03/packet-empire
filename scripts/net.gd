class_name Net
## Data model, shaped after NetBox's DCIM/IPAM core:
## Rack > Device > Interface; Cable(=Link) terminates on interfaces;
## VLANs and IP addresses are configured per interface.

class Iface:
	var dev: NDevice
	var name: String
	var mac: String
	var enabled := true
	var mtu := 1500
	var mode := "access"  # access | trunk | routed
	var untagged_vlan := 1
	var tagged_vlans: Array = []  # trunk allowed VIDs; empty = all
	var nat := ""  # "" | "inside" | "outside" (srcnat/masquerade toward outside)
	var vrrp := {}  # {"group": int, "vip": String, "priority": int}
	var lag := 0  # port-channel group id; 0 = standalone
	var helper := ""  # DHCP relay target (ip helper-address)
	var port_security := false  # sticky-MAC lockdown on an access port
	var secure_mac := ""  # the MAC this port is locked to
	var violations := 0
	var parent := ""  # 802.1Q subinterface: name of the physical parent
	var dot1q := 0  # subinterface VLAN tag
	var tx_frames := 0  # runtime counters
	var rx_frames := 0
	var ips: Array = []  # CIDR strings, e.g. "10.0.0.5/24"
	func _init(d: NDevice, n: String, m: String) -> void:
		dev = d
		name = n
		mac = m

class NDevice:
	var type: String  # "switch" | "server" | "router"
	var model := ""  # key into Game.MODELS
	var name: String
	var status := "active"  # active | offline
	var ifaces: Array = []
	var vlans := {}  # vid -> name; per-device VLAN database (switches)
	var ip_forwarding := false  # routers forward, hosts don't
	var static_routes: Array = []  # {"prefix": "0.0.0.0", "plen": 0, "via": "10.0.0.1"}
	var acls: Array = []  # firewall rules {action, src, splen, dst, dplen}; first match wins
	var stateful := false  # track flows, auto-permit return traffic
	var startup := {}  # saved configuration ('write memory')
	var acquired_from := ""  # inherited with a company you bought
	var flows := {}  # runtime: "id|src|dst" of forwarded flows
	var bgp := {}  # {asn, neighbors: [{ip, remote_as}], networks: ["prefix/len"]}
	var ospf := {}  # {"networks": ["prefix/len"]}: single area 0, enabled when non-empty
	var services := {}  # "dhcp": {iface,start,end,plen,gw,dns,leases}, "dns": {records}
	var resolver := ""  # DNS server ip for this host
	var nat_flows := {}  # runtime: l4 id -> original private src ip
	# runtime state (not saved): learned tables
	var mac_table := {}  # vlan -> {mac -> Iface}
	var arp := {}  # ip -> mac
	var capture: Array = []  # last frames seen (tcpdump-lite)
	func _init(t: String, n: String) -> void:
		type = t
		name = n

class Link:
	var a: Iface
	var b: Iface
	func _init(pa: Iface, pb: Iface) -> void:
		a = pa
		b = pb
	func other(i: Iface) -> Iface:
		return b if i == a else a

class Rack:
	const SLOTS := 8
	var name: String
	var site := 0  # which site (floor) this rack stands on
	var tile: Vector2i
	var slots: Array = []
	var visual: Node2D
	func _init(n: String, t: Vector2i) -> void:
		name = n
		tile = t
		slots.resize(SLOTS)

# ---------- IPv6 ----------
# Addresses are kept as strings and compared hextet-wise, which covers every
# prefix length the game teaches (/128 down to /16 boundaries and anything in
# between via a masked hextet).

static func is_v6(addr: String) -> bool:
	return ":" in addr

static func v6_hextets(addr: String) -> Array:
	## expand an address (with or without ::) into 8 integers, [] if invalid
	var a := addr.strip_edges().to_lower()
	if a == "":
		return []
	var head: Array = []
	var tail: Array = []
	if "::" in a:
		var halves := a.split("::", true, 1)
		if "::" in halves[1]:
			return []  # only one :: is legal
		for g in halves[0].split(":", false):
			head.append(g)
		for g in halves[1].split(":", false):
			tail.append(g)
		if head.size() + tail.size() > 8:
			return []
	else:
		for g in a.split(":", false):
			head.append(g)
		if head.size() != 8:
			return []
	var out: Array = []
	for g in head:
		var v := _hex16(g)
		if v < 0:
			return []
		out.append(v)
	while out.size() + tail.size() < 8:
		out.append(0)
	for g in tail:
		var v := _hex16(g)
		if v < 0:
			return []
		out.append(v)
	return out if out.size() == 8 else []

static func _hex16(group: String) -> int:
	if group == "" or group.length() > 4:
		return -1
	var v := 0
	for ch in group:
		var d := "0123456789abcdef".find(ch)
		if d < 0:
			return -1
		v = v * 16 + d
	return v

static func v6_compress(addr: String) -> String:
	## canonical short form, so two spellings of one address compare equal
	var h := v6_hextets(addr)
	if h.is_empty():
		return addr
	var best_start := -1
	var best_len := 0
	var i := 0
	while i < 8:
		if int(h[i]) != 0:
			i += 1
			continue
		var j := i
		while j < 8 and int(h[j]) == 0:
			j += 1
		if j - i > best_len and j - i > 1:
			best_start = i
			best_len = j - i
		i = j
	var parts: Array = []
	i = 0
	while i < 8:
		if i == best_start:
			parts.append("")
			i += best_len
			continue
		parts.append("%x" % int(h[i]))
		i += 1
	var out := ":".join(PackedStringArray(parts))
	if best_start == 0:
		out = ":" + out
	if best_start >= 0 and best_start + best_len == 8:
		out += ":"
	return out

static func same_subnet6(a: String, b: String, plen: int) -> bool:
	var ha := v6_hextets(a)
	var hb := v6_hextets(b)
	if ha.is_empty() or hb.is_empty():
		return false
	if plen <= 0:
		return true
	var full := plen / 16
	for k in mini(full, 8):
		if int(ha[k]) != int(hb[k]):
			return false
	var rem := plen % 16
	if rem > 0 and full < 8:
		var mask := ((0xFFFF << (16 - rem)) & 0xFFFF)
		if (int(ha[full]) & mask) != (int(hb[full]) & mask):
			return false
	return true

static func valid_cidr6(s: String) -> bool:
	var parts := s.split("/")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return false
	var plen := int(parts[1])
	return not v6_hextets(parts[0]).is_empty() and plen >= 0 and plen <= 128

## family-aware helpers used by the simulation
static func same_net(addr: String, net: String, plen: int) -> bool:
	if is_v6(addr) != is_v6(net):
		return false
	return same_subnet6(addr, net, plen) if is_v6(addr) else same_subnet(addr, net, plen)

static func addr_eq(a: String, b: String) -> bool:
	if is_v6(a) != is_v6(b):
		return false
	return v6_compress(a) == v6_compress(b) if is_v6(a) else a == b

static func ip_to_int(ip: String) -> int:
	var v := 0
	for p in ip.split("."):
		v = v * 256 + int(p)
	return v

static func int_to_ip(v: int) -> String:
	return "%d.%d.%d.%d" % [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255]

static func network_of(cidr: String) -> Dictionary:
	var parts := cidr.split("/")
	var plen := int(parts[1])
	var mask := 0 if plen == 0 else (0xFFFFFFFF << (32 - plen)) & 0xFFFFFFFF
	return {"prefix": int_to_ip(ip_to_int(parts[0]) & mask), "plen": plen}

static func same_subnet(ip: String, net_ip: String, plen: int) -> bool:
	if plen <= 0:
		return true
	var mask := (0xFFFFFFFF << (32 - plen)) & 0xFFFFFFFF
	return (ip_to_int(ip) & mask) == (ip_to_int(net_ip) & mask)

static func valid_cidr(s: String) -> bool:
	if is_v6(s):
		return valid_cidr6(s)
	var parts := s.split("/")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return false
	var plen := int(parts[1])
	return parts[0].is_valid_ip_address() and not parts[0].contains(":") \
		and plen >= 0 and plen <= 32
