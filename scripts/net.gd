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
	var bgp := {}  # {asn, neighbors: [{ip, remote_as}], networks: ["prefix/len"]}
	var services := {}  # "dhcp": {iface,start,end,plen,gw,dns,leases}, "dns": {records}
	var resolver := ""  # DNS server ip for this host
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
	var tile: Vector2i
	var slots: Array = []
	var visual: Node2D
	func _init(n: String, t: Vector2i) -> void:
		name = n
		tile = t
		slots.resize(SLOTS)

static func ip_to_int(ip: String) -> int:
	var v := 0
	for p in ip.split("."):
		v = v * 256 + int(p)
	return v

static func same_subnet(ip: String, net_ip: String, plen: int) -> bool:
	if plen <= 0:
		return true
	var mask := (0xFFFFFFFF << (32 - plen)) & 0xFFFFFFFF
	return (ip_to_int(ip) & mask) == (ip_to_int(net_ip) & mask)

static func valid_cidr(s: String) -> bool:
	var parts := s.split("/")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return false
	var plen := int(parts[1])
	return parts[0].is_valid_ip_address() and not parts[0].contains(":") \
		and plen >= 0 and plen <= 32
