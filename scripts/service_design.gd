class_name ServiceDesign
## A deliberately bounded first reusable service: a switched IPv4 LAN.
## It captures the working physical topology, then assigns fresh identities.
## Routed, multi-VLAN and application-service designs stay manual for now.

static func capture(rack: Net.Rack, title: String) -> String:
	if rack == null: return "Open the cabinet containing the service first."
	var devices: Array = []
	var hosts: Array = []
	var switches := 0
	var nodes: Array = []
	var slots: Array = []
	var vid := -1
	for dev in rack.slots:
		slots.append(dev.model if dev != null else null)
		if dev == null: continue
		if dev.model not in ["sw-lite", "sw-8", "srv-1"]:
			return "Save a small LAN: one SW5 or S8 and two to four R110 servers. Other designs use the existing hardware blueprints."
		if dev.status != "active": return "Bring every device online before saving a service."
		if dev.type == "switch": switches += 1
		else: hosts.append(dev)
		if not dev.static_routes.is_empty() or not dev.services.is_empty():
			return "This first service standard supports a local LAN without routes or application services."
		var ports: Array = []
		for iface: Net.Iface in dev.ifaces:
			if iface.name.begins_with("Management"): continue
			var link := Game.link_at(iface)
			if link != null:
				if Game.rack_of(link.other(iface).dev) != rack:
					return "The service must fit in this cabinet; an external cable would be left behind."
				if not iface.enabled or (dev.type == "switch" and iface.mode != "access"): return "Save a healthy access LAN; trunks and disabled ports need manual design."
				if dev.type == "switch":
					if vid != -1 and vid != iface.untagged_vlan: return "Use one customer VLAN per service standard."
					vid = iface.untagged_vlan
			ports.append({"name": iface.name, "vlan": iface.untagged_vlan})
		devices.append(dev)
		nodes.append({"model": dev.model, "slot": rack.slots.find(dev), "ports": ports})
	if switches != 1 or hosts.size() < 2 or hosts.size() > 4:
		return "A service standard needs one switch and two to four servers."
	for host: Net.NDevice in hosts:
		if host.ifaces[0].ips.size() != 1 or not String(host.ifaces[0].ips[0]).ends_with("/24"):
			return "Give each server one IPv4 /24 address before capturing the LAN."
		if ":" in String(host.ifaces[0].ips[0]): return "This standard uses IPv4 /24 addressing."
		for other: Net.NDevice in hosts:
			if host != other and not Sim.ping(host, String(other.ifaces[0].ips[0]).split("/")[0])["ok"]:
				return "The servers must reach each other before this service can become a standard."
	var cables: Array = []
	for link: Net.Link in Game.links:
		if link.a.dev in devices and link.b.dev in devices:
			cables.append({"a": devices.find(link.a.dev), "ap": link.a.name,
				"b": devices.find(link.b.dev), "bp": link.b.name})
	Game.blueprints.append({"name": Game.unique_name(title if title.strip_edges() != "" else "Customer LAN", Game.blueprints),
		"slots": slots, "service": {"version": 1, "nodes": nodes, "cables": cables}})
	Game.log_event("SERVICE STANDARD: saved a proven %d-server LAN with its cables and VLAN roles." % hosts.size())
	return ""

static func preview(rack: Net.Rack, design: Dictionary, prefix: String, vlan: int) -> Dictionary:
	var spec: Dictionary = design.get("service", {})
	if int(spec.get("version", 0)) != 1 or not spec.get("nodes", []) is Array or spec.get("nodes", []).is_empty():
		return {"ok": false, "why": "Choose a saved service standard; this entry is a plain hardware blueprint or an older format."}
	if rack == null or rack not in Game.racks: return {"ok": false, "why": "Open an empty target cabinet."}
	for dev in rack.slots:
		if dev != null: return {"ok": false, "why": "The target cabinet must be empty."}
	var parts := prefix.strip_edges().split(".")
	if parts.size() != 3: return {"ok": false, "why": "Enter three address octets, for example 10.80.0."}
	for octet: String in parts:
		if not octet.is_valid_int() or int(octet) < 0 or int(octet) > 255:
			return {"ok": false, "why": "Address octets must be between 0 and 255."}
	if int(parts[0]) == 0 or int(parts[0]) == 127 or int(parts[0]) >= 224:
		return {"ok": false, "why": "Choose a unicast LAN prefix, such as 10.80.0."}
	if vlan < 1 or vlan > 4094: return {"ok": false, "why": "Choose VLAN 1 to 4094."}
	var normalized := "%d.%d.%d" % [int(parts[0]), int(parts[1]), int(parts[2])]
	for dev: Net.NDevice in Game.all_devices():
		for iface: Net.Iface in dev.ifaces:
			for cidr: String in iface.ips:
				if cidr.begins_with(normalized + "."):
					return {"ok": false, "why": "That /24 is already in use. Choose a fresh prefix."}
	var price := 0
	var occupied: Array = []
	var host_count := 0
	for node: Dictionary in spec["nodes"]:
		var model := String(node.get("model", ""))
		var slot := int(node.get("slot", -1))
		if model not in ["sw-lite", "sw-8", "srv-1"] or slot in occupied or not Game.can_install(rack, slot, model):
			return {"ok": false, "why": "The saved hardware layout is invalid for this cabinet."}
		occupied.append(slot)
		price += int(Game.MODELS[model]["price"])
		if model == "srv-1": host_count += 1
	if host_count < 2 or host_count > 4 or spec["nodes"].size() != host_count + 1:
		return {"ok": false, "why": "This standard has %d servers and %d nodes; a service standard is one switch and two to four servers." % [host_count, spec["nodes"].size()]}
	var extra := 0
	for node: Dictionary in spec["nodes"]:
		extra += int(Game.MODELS[String(node["model"])].get("watts", 0))
	if Game.cooling_capacity(rack.site) > 0 and Game.power_draw(rack.site) + extra > Game.cooling_capacity(rack.site):
		return {"ok": false, "why": "This floor cannot cool another %d W: %d W drawn against %d W of cooling. Add cooling first." % [extra, Game.power_draw(rack.site), Game.cooling_capacity(rack.site)]}
	var endpoints: Array = []
	if spec.get("cables", []).size() != host_count:
		return {"ok": false, "why": "This standard holds %d cables for %d servers; every server needs exactly one lead to the switch." % [spec.get("cables", []).size(), host_count]}
	for cable: Dictionary in spec["cables"]:
		for side in ["a", "b"]:
			var idx := int(cable.get(side, -1))
			if idx < 0 or idx >= spec["nodes"].size():
				return {"ok": false, "why": "A cable in this standard points at a device that is not in it."}
			var model := String(spec["nodes"][idx]["model"])
			var port := String(cable.get(side + "p", ""))
			var legal: Array = []
			if model == "srv-1": legal = ["eth0"]
			else:
				for n in int(Game.MODELS[model]["ports"]): legal.append(("ether" if model == "sw-lite" else "Ethernet") + str(n + 1))
			var endpoint := "%d:%s" % [idx, port]
			if port not in legal:
				return {"ok": false, "why": "Port %s does not exist on a %s." % [port, Game.MODELS[model]["label"]]}
			if endpoint in endpoints:
				return {"ok": false, "why": "Port %s is cabled twice in this standard." % port}
			endpoints.append(endpoint)
		if String(spec["nodes"][int(cable["a"])]["model"]) == "srv-1" and String(spec["nodes"][int(cable["b"])]["model"]) == "srv-1":
			return {"ok": false, "why": "This standard cables two servers directly; every lead must end on the switch."}
	var leads := int(spec["cables"].size())
	price += leads * int(Game.PART_PRICES["patch"])
	if not Game.sandbox and Game.money < price: return {"ok": false, "why": "This service costs $%d including patch leads; cash available $%d." % [price, Game.money]}
	return {"ok": true, "why": "%d servers, one switch, %d patch leads. Addresses %s.10 to %d/24, VLAN %d. Total $%d." % [host_count, leads, normalized, 9 + host_count, vlan, price],
		"price": price, "prefix": normalized, "hosts": host_count, "leads": leads}

static func deploy(rack: Net.Rack, design: Dictionary, prefix: String, vlan: int) -> String:
	var plan := preview(rack, design, prefix, vlan)
	if not bool(plan["ok"]): return String(plan["why"])
	if not Game.try_spend(int(plan["price"])): return "The available cash changed. Preview again."
	var spec: Dictionary = design["service"]
	var created: Array = []
	var hosts: Array = []
	for node: Dictionary in spec["nodes"]:
		var dev := Game.new_device(String(node["model"]))
		Game.install_device(rack, int(node["slot"]), dev)
		created.append(dev)
		if dev.type == "server":
			dev.ifaces[0].ips = ["%s.%d/24" % [plan["prefix"], 10 + hosts.size()]]
			hosts.append(dev)
		else:
			if vlan != 1: dev.vlans[vlan] = "customer"
			for iface: Net.Iface in dev.ifaces:
				if not iface.name.begins_with("Management"): iface.untagged_vlan = vlan
	Game.parts["patch"] = Game.parts_of("patch") + int(plan["leads"])
	for cable: Dictionary in spec["cables"]:
		var a: Net.NDevice = created[int(cable["a"])]
		var b: Net.NDevice = created[int(cable["b"])]
		Game.connect_ifaces(port_named(a, String(cable["ap"])), port_named(b, String(cable["bp"])))
	for dev: Net.NDevice in created: dev.startup = Game.device_config(dev)
	var verified := true
	for host: Net.NDevice in hosts:
		for other: Net.NDevice in hosts:
			if host != other and not Sim.ping(host, String(other.ifaces[0].ips[0]).split("/")[0])["ok"]: verified = false
	Game.log_event("SERVICE DEPLOYED: %s into %s. %s" % [design["name"], rack.name,
		"Every server reaches every other server." if verified else "Connectivity check failed; inspect VLANs and facility power."])
	Game.topology_changed.emit()
	return "" if verified else "Hardware deployed, but connectivity failed. Check this floor's power and cooling before selling the service."

static func port_named(dev: Net.NDevice, name: String) -> Net.Iface:
	for iface: Net.Iface in dev.ifaces:
		if iface.name == name: return iface
	return null
