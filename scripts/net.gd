class_name Net
## Data model, shaped after NetBox's DCIM/IPAM core:
## Rack > Device > Interface; Cable(=Link) terminates on interfaces;
## VLANs and IP addresses are configured per interface.

class Iface:
	var dev: NDevice
	var name: String
	var mac: String
	var enabled := true  # operational: passes frames right now
	var admin_down := false  # somebody typed shutdown
	var err_disabled := false  # the switch shut it (port security); shut/no shut clears it
	var fault := ""  # the physical reason it is down, if any; no shutdown cannot fix this
	var mtu := 1500
	var mode := "access"  # access | trunk | routed
	var untagged_vlan := 1
	var tagged_vlans: Array = []  # trunk allowed VIDs; empty = all
	var nat := ""  # "" | "inside" | "outside" (srcnat/masquerade toward outside)
	var vrrp := {}  # {"group": int, "vip": String, "priority": int}
	var lag := 0  # port-channel group id; 0 = standalone
	var helper := ""  # DHCP relay target (ip helper-address)
	var vrf := ""  # routing table this interface belongs to ("" = global)
	var qos := false  # when congested, serve traffic in service-level order
	var dot1x := false  # port-based authentication before any traffic passes
	var dot1x_ok := ""  # the MAC currently authorised on this port
	var pvlan := ""  # "" | "isolated" | "promiscuous": private VLAN role
	var storm_limit := 0  # broadcast frames allowed per operation, 0 = unlimited
	var storm_count := 0  # runtime counter within the current operation
	var vm := ""  # a virtual machine's NIC, hosted on this server
	var ra := false  # router: advertise this interface's v6 prefix to the segment
	var bfd := false  # watch the far end, and withdraw the route when it dies
	var mlag := 0  # member of a bundle shared with the peer switch
	var mlag_peerlink := false  # the link that keeps the two switches in step
	var dhcp_trusted := false  # a port allowed to carry DHCP server replies
	var tunnel_src := ""  # tunnel interfaces ride the underlay between two endpoints
	var tunnel_dst := ""
	var wg_key := ""  # WireGuard: this interface's public key
	var wg_peers: Array = []  # [{key, endpoint, allowed: ["10.0.0.0/24", ...]}]
	var port_security := false  # sticky-MAC lockdown on an access port
	var secure_mac := ""  # the MAC this port is locked to
	var violations := 0
	var parent := ""  # 802.1Q subinterface: name of the physical parent
	var dot1q := 0  # subinterface VLAN tag
	var tx_frames := 0  # runtime counters
	var rx_frames := 0
	var rx_errors := 0  # frames that arrived damaged: the first sign of a grey failure
	var rx_crc := 0  # of those, the ones with a bad checksum: a cable or optic problem
	var rx_giants := 0  # frames bigger than this port's MTU: a configuration problem
	var out_drops := 0  # frames the port could not send: no room on the wire
	var collisions := 0  # late collisions: the half-duplex side of a mismatch
	var duplex := "auto"  # auto | full | half; both ends must agree or the counters say so
	var light_dbm := -6.0  # optical receive level; drifts down as an optic dies
	var ips: Array = []  # CIDR strings, e.g. "10.0.0.5/24"
	var note := {}  # player-authored {text, cycle}; never interpreted by the simulation
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
	var static_routes: Array = []  # {"prefix", "plen", "via", optional "vrf"}
	var vrfs: Array = []  # named routing tables on this device
	var snooping := false  # DHCP snooping: only trusted ports may answer DHCP
	var dai := false  # dynamic ARP inspection, using the snooping bindings
	var bindings := {}  # mac -> address learned from a legitimate lease
	var stp_mode := "rstp"  # rstp (modern default), stp (slow) or mst
	var stp_priority := 32768  # lower wins the root election
	var mst_instances := {}  # instance id -> [vlan ids] when running MST
	var dns_cache := {}  # name -> {"ip": .., "expires": cycle}; why a change is not seen at once
	var vtep := {}  # {"src": ip, "peers": [ip], "map": {vlan: vni}, "evpn": bool}
	var remote_macs := {}  # vlan -> {mac: vtep ip}: what the overlay says is elsewhere
	var nat64_flows := {}  # translation state: flow id -> the IPv6 client waiting
	var talkers := {}  # "src>dst" -> packets forwarded, netflow-style
	var aaa := {}  # admin login: {"server": ip, "key": secret, "local": bool}
	var snmp := ""  # read community; empty means the agent is not running
	var psu := "A"  # which feed(s) this device is plugged into: A, B or AB
	var mlag_peer := ""  # switch: the name of the switch it shares bundles with
	var igmp_snooping := false  # forward multicast only where it was asked for
	var mcast_ports := {}  # group -> {Iface: true} learned from membership reports
	var mcast_groups: Array = []  # host: the groups it has joined
	var mcast_rx := 0  # host: multicast frames received, for the tests and the UI
	var radius := ""  # switch/AP: address of the authentication server
	var ssids := {}  # access point: SSID name -> VLAN id
	var wifi := ""  # host: the SSID it is associated with
	var acls: Array = []  # firewall rules {action, src, splen, dst, dplen}; first match wins
	var stateful := false  # track flows, auto-permit return traffic
	var startup := {}  # saved configuration ('write memory')
	var versions: Array = []  # [{cycle, cfg}] history for diff and rollback
	var acquired_from := ""  # inherited with a company you bought
	var installed_cycle := 0  # for ageing: hardware does not last forever
	var log_host := ""  # syslog collector
	var ntp_server := ""  # clock source
	var clock_skew := 0  # cycles of drift when the clock is unsynchronised
	var logs: Array = []  # local log buffer
	var note := {}  # player-authored {text, cycle}; never interpreted by the simulation
	var flows := {}  # runtime: "id|src|dst" of forwarded flows
	var bgp := {}  # {asn, neighbors: [{ip, remote_as}], networks: ["prefix/len"]}
	var ospf := {}  # {"networks": ["prefix/len"]}: single area 0, enabled when non-empty
	var services := {}  # "dhcp": {iface,start,end,plen,gw,dns,leases}, "dns": {records}
	var resolver := ""  # DNS server ip for this host
	var nat_flows := {}  # runtime: l4 id -> original private src ip
	# runtime state (not saved): learned tables
	var mac_table := {}  # vlan -> {mac -> Iface}: learned, and it ages out
	var mac_static := {}  # vlan -> {mac -> port name}: pinned by an engineer, never ages
	var arp := {}  # ip -> mac
	var capture: Array = []  # last frames seen (tcpdump-lite)
	func _init(t: String, n: String) -> void:
		type = t
		name = n

class Link:
	var a: Iface
	var b: Iface
	var note := {}  # player-authored {text, cycle}; the run itself, labelled
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
	## Slot index -> the device below that occupies it. A two-unit box sits in
	## one slot and takes the one above it, so iterating slots still sees each
	## device exactly once.
	var covered := {}
	var blanked := {}  # empty slot index -> true; fitted airflow blanking panels
	var note := {}  # player-authored {text, cycle}
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

static func eui64(mac: String) -> String:
	## the interface identifier a host builds from its own MAC: split it,
	## push fffe into the middle, and flip the universal/local bit
	var parts := mac.split(":")
	if parts.size() != 6:
		return "0000:0000:0000:0001"
	var first := "%02x" % (("0x" + parts[0]).hex_to_int() ^ 0x02)
	return "%s%s:%sff:fe%s:%s%s" % [first, parts[1], parts[2], parts[3], parts[4], parts[5]]

static func slaac_address(prefix: String, plen: int, mac: String) -> String:
	## prefix (first 64 bits) plus the host's own identifier
	var h := v6_hextets(prefix)
	if h.is_empty() or plen != 64:
		return ""
	var id := eui64(mac).split(":")
	var out: Array = []
	for i in 4:
		out.append("%x" % int(h[i]))
	for part in id:
		out.append(part)
	return v6_compress(":".join(PackedStringArray(out)))

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

static func compress_ports(names: Array) -> String:
	## Et1,Et2,Et3,Et7 -> "Et1-3,Et7" (what real switch output looks like).
	## Lives here rather than in the UI: switch CLIs print this, and the CLI
	## layer has no business knowing a UI exists.
	if names.is_empty():
		return ""
	var short: Array = []
	for n in names:
		short.append(String(n).replace("Ethernet", "Et").replace("Management", "Ma"))
	var out: Array = []
	var run_start := -1
	var run_prev := -1
	var run_pfx := ""
	for n in short + [""]:
		var digits := String(n).lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
		var pfx := String(n).trim_suffix(digits)
		var num := int(digits) if digits.is_valid_int() else -999
		if pfx == run_pfx and num == run_prev + 1:
			run_prev = num
			continue
		if run_start >= 0:
			out.append("%s%d" % [run_pfx, run_start] if run_start == run_prev
				else "%s%d-%d" % [run_pfx, run_start, run_prev])
		run_pfx = pfx
		run_start = num
		run_prev = num
	return ",".join(PackedStringArray(out))
