extends Node
## Autoload "Game": the datacenter source of truth (racks, devices,
## interfaces, cables, per-switch VLANs, money). NetBox-style model.

signal topology_changed
signal money_changed

# per-type spec. New device type = new entry. (Vendor tiers: issue #13)
const DEVICE_SPECS := {
	"switch": {"if_prefix": "Ethernet", "if_start": 1, "ports": 8, "name_prefix": "sw", "price": 250},
	"server": {"if_prefix": "eth", "if_start": 0, "ports": 1, "name_prefix": "srv", "price": 400},
	"router": {"if_prefix": "Ethernet", "if_start": 1, "ports": 4, "name_prefix": "rtr", "price": 600},
}
const RACK_PRICE := 500
const SAVE_PATH := "user://save.json"

var racks: Array = []
var links: Array = []
var money := 2000
var _counter := {"switch": 0, "server": 0, "router": 0, "rack": 0, "mac": 0}

func _ready() -> void:
	topology_changed.connect(Sim.flush_learned_state)

# ---------- money ----------

func try_spend(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	money_changed.emit()
	return true

func _refund(amount: int) -> void:
	money += amount
	money_changed.emit()

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
	if type == "router":
		d.ip_forwarding = true
	for i in spec["ports"]:
		var ifc := Net.Iface.new(d, spec["if_prefix"] + str(spec["if_start"] + i), _new_mac())
		if type != "switch":
			ifc.mode = "routed"
		d.ifaces.append(ifc)
	return d

func uninstall_device(dev: Net.NDevice) -> void:
	for i: Net.Iface in dev.ifaces:
		disconnect_iface(i)
	var r := rack_of(dev)
	if r:
		r.slots[r.slots.find(dev)] = null
		if r.visual:
			r.visual.queue_redraw()
	_refund(DEVICE_SPECS[dev.type]["price"] / 2)
	topology_changed.emit()

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

# ---------- VLANs / IPAM ----------

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

func add_static_route(dev: Net.NDevice, prefix: String, plen: int, via: String) -> bool:
	if not via.is_valid_ip_address() or plen < 0 or plen > 32 or not prefix.is_valid_ip_address():
		return false
	remove_static_route(dev, prefix, plen)
	dev.static_routes.append({"prefix": prefix, "plen": plen, "via": via})
	topology_changed.emit()
	return true

func remove_static_route(dev: Net.NDevice, prefix: String, plen: int) -> void:
	for r in dev.static_routes.duplicate():
		if r["prefix"] == prefix and int(r["plen"]) == plen:
			dev.static_routes.erase(r)
	topology_changed.emit()

# ---------- save / load ----------

func save_game() -> void:
	var devs := {}  # name -> serialized (names are unique)
	var rack_data: Array = []
	for r in racks:
		var slot_names: Array = []
		for d in r.slots:
			slot_names.append(d.name if d else null)
			if d:
				devs[d.name] = _ser_device(d)
		rack_data.append({"name": r.name, "tile": [r.tile.x, r.tile.y], "slots": slot_names})
	var link_data: Array = []
	for l in links:
		link_data.append([l.a.dev.name, l.a.name, l.b.dev.name, l.b.name])
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"money": money, "counters": _counter,
		"racks": rack_data, "devices": devs, "links": link_data}, "  "))

func _ser_device(d: Net.NDevice) -> Dictionary:
	var ifs: Array = []
	for i: Net.Iface in d.ifaces:
		ifs.append({"name": i.name, "mac": i.mac, "enabled": i.enabled, "mtu": i.mtu,
			"mode": i.mode, "untagged_vlan": i.untagged_vlan, "ips": i.ips})
	return {"type": d.type, "name": d.name, "status": d.status, "vlans": d.vlans,
		"ip_forwarding": d.ip_forwarding, "static_routes": d.static_routes, "ifaces": ifs}

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data == null:
		return false
	racks = []
	links = []
	money = int(data["money"])
	for k in data["counters"]:
		_counter[k] = int(data["counters"][k])
	var by_name := {}
	for dname in data["devices"]:
		var sd: Dictionary = data["devices"][dname]
		var d := Net.NDevice.new(sd["type"], sd["name"])
		d.status = sd["status"]
		d.ip_forwarding = sd["ip_forwarding"]
		d.static_routes = sd["static_routes"]
		for vid in sd["vlans"]:
			d.vlans[int(vid)] = sd["vlans"][vid]
		for si in sd["ifaces"]:
			var i := Net.Iface.new(d, si["name"], si["mac"])
			i.enabled = si["enabled"]
			i.mtu = int(si["mtu"])
			i.mode = si["mode"]
			i.untagged_vlan = int(si["untagged_vlan"])
			i.ips = si["ips"]
			d.ifaces.append(i)
		by_name[d.name] = d
	for rd in data["racks"]:
		var r := Net.Rack.new(rd["name"], Vector2i(int(rd["tile"][0]), int(rd["tile"][1])))
		for si in rd["slots"].size():
			if rd["slots"][si] != null:
				r.slots[si] = by_name[rd["slots"][si]]
		racks.append(r)
	for ld in data["links"]:
		var a := _find_iface(by_name[ld[0]], ld[1])
		var b := _find_iface(by_name[ld[2]], ld[3])
		if a and b:
			links.append(Net.Link.new(a, b))
	money_changed.emit()
	topology_changed.emit()
	return true

func _find_iface(dev: Net.NDevice, ifname: String) -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if i.name == ifname:
			return i
	return null
