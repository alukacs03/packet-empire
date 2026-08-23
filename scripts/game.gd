extends Node
## Autoload "Game": the datacenter source of truth (racks, devices,
## interfaces, cables, VLANs). NetBox-style: config lives on interfaces.

signal topology_changed

# per-type spec: interface naming + count. New device type = new entry.
const DEVICE_SPECS := {
	"switch": {"if_prefix": "swp", "if_start": 1, "ports": 8, "name_prefix": "sw"},
	"server": {"if_prefix": "eth", "if_start": 0, "ports": 1, "name_prefix": "srv"},
}

var racks: Array = []
var links: Array = []
var _counter := {"switch": 0, "server": 0, "rack": 0, "mac": 0}

# ---------- racks ----------

func add_rack(tile: Vector2i) -> Net.Rack:
	_counter["rack"] += 1
	var r := Net.Rack.new("R%d" % _counter["rack"], tile)
	racks.append(r)
	return r

func rack_at(tile: Vector2i) -> Net.Rack:
	for r in racks:
		if r.tile == tile:
			return r
	return null

func rack_of(dev: Net.NDevice) -> Net.Rack:
	for r in racks:
		if dev in r.slots:
			return r
	return null

# ---------- devices ----------

func new_device(type: String) -> Net.NDevice:
	var spec: Dictionary = DEVICE_SPECS[type]
	_counter[type] += 1
	var d := Net.NDevice.new(type, spec["name_prefix"] + str(_counter[type]))
	if type == "switch":
		d.vlans = {1: "default"}
	for i in spec["ports"]:
		d.ifaces.append(Net.Iface.new(d, spec["if_prefix"] + str(spec["if_start"] + i), _new_mac()))
	return d

func _new_mac() -> String:
	_counter["mac"] += 1
	return "02:50:45:00:%02X:%02X" % [_counter["mac"] / 256, _counter["mac"] % 256]

func all_devices() -> Array:
	var out: Array = []
	for r in racks:
		for d in r.slots:
			if d:
				out.append(d)
	return out

func rename_device(dev: Net.NDevice, new_name: String) -> bool:
	new_name = new_name.strip_edges()
	if new_name == "" or not new_name.is_valid_ascii_identifier():
		return false
	for d in all_devices():
		if d != dev and d.name == new_name:
			return false
	dev.name = new_name
	topology_changed.emit()
	return true

# ---------- cables ----------

func link_at(i: Net.Iface) -> Net.Link:
	for l in links:
		if l.a == i or l.b == i:
			return l
	return null

func peer_label(i: Net.Iface) -> String:
	var l := link_at(i)
	if l == null:
		return ""
	var p := l.other(i)
	return "%s %s" % [p.dev.name, p.name]

func connect_ifaces(a: Net.Iface, b: Net.Iface) -> void:
	links.append(Net.Link.new(a, b))
	topology_changed.emit()

func disconnect_iface(i: Net.Iface) -> void:
	var l := link_at(i)
	if l:
		links.erase(l)
		topology_changed.emit()

func free_ifaces(exclude: Net.NDevice) -> Array:
	var out: Array = []
	for d in all_devices():
		if d == exclude:
			continue
		for i in d.ifaces:
			if link_at(i) == null:
				out.append(i)
	return out

# ---------- IPAM ----------

func add_vlan(dev: Net.NDevice, vid: int, name: String) -> bool:
	name = name.strip_edges()
	if name == "":
		name = "vlan%d" % vid
	if dev.type != "switch" or vid < 1 or vid > 4094 or dev.vlans.has(vid):
		return false
	dev.vlans[vid] = name
	topology_changed.emit()
	return true

func remove_vlan(dev: Net.NDevice, vid: int) -> bool:
	if vid == 1 or not dev.vlans.has(vid):
		return false  # default VLAN stays
	dev.vlans.erase(vid)
	for i in dev.ifaces:
		if i.untagged_vlan == vid:
			i.untagged_vlan = 1
	topology_changed.emit()
	return true

func set_access_vlan(i: Net.Iface, vid: int) -> bool:
	if not i.dev.vlans.has(vid):
		return false
	i.untagged_vlan = vid
	topology_changed.emit()
	return true

func add_ip(i: Net.Iface, cidr: String) -> bool:
	cidr = cidr.strip_edges()
	if not Net.valid_cidr(cidr) or cidr in i.ips:
		return false
	i.ips.append(cidr)
	topology_changed.emit()
	return true

func remove_ip(i: Net.Iface, cidr: String) -> void:
	i.ips.erase(cidr)
	topology_changed.emit()
