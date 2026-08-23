extends Node
## Autoload "Game": owns all racks, devices and links.

signal topology_changed

const PORTS := {"switch": 8, "server": 1}
const PREFIX := {"switch": "sw", "server": "srv"}

var racks: Array = []
var links: Array = []
var _counter := {"switch": 0, "server": 0, "rack": 0}

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

func new_device(type: String) -> Net.NDevice:
	_counter[type] += 1
	return Net.NDevice.new(type, PREFIX[type] + str(_counter[type]), PORTS[type])

func rack_of(dev: Net.NDevice) -> Net.Rack:
	for r in racks:
		if dev in r.slots:
			return r
	return null

func link_at(dev: Net.NDevice, i: int) -> Net.Link:
	for l in links:
		if (l.a == dev and l.ai == i) or (l.b == dev and l.bi == i):
			return l
	return null

func peer_label(dev: Net.NDevice, i: int) -> String:
	var l := link_at(dev, i)
	if l == null:
		return ""
	var pd: Net.NDevice = l.b if l.a == dev else l.a
	var pi: int = l.bi if l.a == dev else l.ai
	return "%s port %d" % [pd.name, pi + 1]

func connect_ports(a: Net.NDevice, ai: int, b: Net.NDevice, bi: int) -> void:
	links.append(Net.Link.new(a, ai, b, bi))
	topology_changed.emit()

func disconnect_port(dev: Net.NDevice, i: int) -> void:
	var l := link_at(dev, i)
	if l:
		links.erase(l)
		topology_changed.emit()

func free_ports(exclude: Net.NDevice) -> Array:
	# Every unconnected [device, port_index] in the datacenter, except exclude's.
	var out: Array = []
	for r in racks:
		for d in r.slots:
			if d == null or d == exclude:
				continue
			for i in d.nports:
				if link_at(d, i) == null:
					out.append([d, i])
	return out
