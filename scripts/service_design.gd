class_name ServiceDesign
## A deliberately bounded first reusable service: a switched IPv4 LAN.
## It captures the working physical topology, then assigns fresh identities.
## Routed, multi-VLAN and application-service designs stay manual for now.

static func capture(rack: Net.Rack, title: String) -> String:
	if rack == null: return Loc.t("design.open_cabinet")
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
			return Loc.t("design.small_lan")
		if dev.status != "active": return Loc.t("design.online_first")
		if dev.type == "switch": switches += 1
		else: hosts.append(dev)
		if not dev.static_routes.is_empty() or not dev.services.is_empty():
			return Loc.t("design.no_routes")
		var ports: Array = []
		for iface: Net.Iface in dev.ifaces:
			if iface.name.begins_with("Management"): continue
			var link := Game.link_at(iface)
			if link != null:
				if Game.rack_of(link.other(iface).dev) != rack:
					return Loc.t("design.fit_cabinet")
				if not iface.enabled or (dev.type == "switch" and iface.mode != "access"): return Loc.t("design.access_only")
				if dev.type == "switch":
					if vid != -1 and vid != iface.untagged_vlan: return Loc.t("design.one_vlan")
					vid = iface.untagged_vlan
			ports.append({"name": iface.name, "vlan": iface.untagged_vlan})
		devices.append(dev)
		nodes.append({"model": dev.model, "slot": rack.slots.find(dev), "ports": ports})
	if switches != 1 or hosts.size() < 2 or hosts.size() > 4:
		return Loc.t("design.one_switch")
	for host: Net.NDevice in hosts:
		if host.ifaces[0].ips.size() != 1 or not String(host.ifaces[0].ips[0]).ends_with("/24"):
			return Loc.t("design.ipv4_24")
		if ":" in String(host.ifaces[0].ips[0]): return Loc.t("design.ipv4_only")
		for other: Net.NDevice in hosts:
			if host != other and not Sim.ping(host, String(other.ifaces[0].ips[0]).split("/")[0])["ok"]:
				return Loc.t("design.reach_each_other")
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
		return {"ok": false, "why": Loc.t("design.choose_standard")}
	if rack == null or rack not in Game.racks: return {"ok": false, "why": Loc.t("design.empty_target")}
	for dev in rack.slots:
		if dev != null: return {"ok": false, "why": Loc.t("design.target_empty")}
	var parts := prefix.strip_edges().split(".")
	if parts.size() != 3: return {"ok": false, "why": Loc.t("design.three_octets")}
	for octet: String in parts:
		if not octet.is_valid_int() or int(octet) < 0 or int(octet) > 255:
			return {"ok": false, "why": Loc.t("design.octet_range")}
	if int(parts[0]) == 0 or int(parts[0]) == 127 or int(parts[0]) >= 224:
		return {"ok": false, "why": Loc.t("design.unicast_prefix")}
	if vlan < 1 or vlan > 4094: return {"ok": false, "why": Loc.t("design.vlan_range")}
	var normalized := "%d.%d.%d" % [int(parts[0]), int(parts[1]), int(parts[2])]
	for dev: Net.NDevice in Game.all_devices():
		for iface: Net.Iface in dev.ifaces:
			for cidr: String in iface.ips:
				if cidr.begins_with(normalized + "."):
					return {"ok": false, "why": Loc.t("design.prefix_in_use")}
	var price := 0
	var occupied: Array = []
	var host_count := 0
	for node: Dictionary in spec["nodes"]:
		var model := String(node.get("model", ""))
		var slot := int(node.get("slot", -1))
		if model not in ["sw-lite", "sw-8", "srv-1"] or slot in occupied or not Game.can_install(rack, slot, model):
			return {"ok": false, "why": Loc.t("design.layout_invalid")}
		occupied.append(slot)
		price += int(Game.MODELS[model]["price"])
		if model == "srv-1": host_count += 1
	if host_count < 2 or host_count > 4 or spec["nodes"].size() != host_count + 1:
		return {"ok": false, "why": Loc.t("design.node_count") % [host_count, spec["nodes"].size()]}
	var extra := 0
	for node: Dictionary in spec["nodes"]:
		extra += int(Game.WATTS.get(String(node["model"]), 0))  # the draw table, not the catalogue
	if Game.stage >= 1 and Game.power_draw(rack.site) + extra > Game.cooling_capacity(rack.site):  # in a colo the cooling is theirs
		return {"ok": false, "why": Loc.t("design.cannot_cool") % [extra, Game.power_draw(rack.site), Game.cooling_capacity(rack.site)]}
	var endpoints: Array = []
	if spec.get("cables", []).size() != host_count:
		return {"ok": false, "why": Loc.t("design.cable_count") % [spec.get("cables", []).size(), host_count]}
	for cable: Dictionary in spec["cables"]:
		for side in ["a", "b"]:
			var idx := int(cable.get(side, -1))
			if idx < 0 or idx >= spec["nodes"].size():
				return {"ok": false, "why": Loc.t("design.cable_outside")}
			var model := String(spec["nodes"][idx]["model"])
			var port := String(cable.get(side + "p", ""))
			var legal: Array = []
			if model == "srv-1": legal = ["eth0"]
			else:
				for n in int(Game.MODELS[model]["ports"]): legal.append(("ether" if model == "sw-lite" else "Ethernet") + str(n + 1))
			var endpoint := "%d:%s" % [idx, port]
			if port not in legal:
				return {"ok": false, "why": Loc.t("design.no_such_port") % [port, Game.MODELS[model]["label"]]}
			if endpoint in endpoints:
				return {"ok": false, "why": Loc.t("design.port_twice") % port}
			endpoints.append(endpoint)
		if String(spec["nodes"][int(cable["a"])]["model"]) == "srv-1" and String(spec["nodes"][int(cable["b"])]["model"]) == "srv-1":
			return {"ok": false, "why": Loc.t("design.server_to_server")}
	var leads := int(spec["cables"].size())
	price += leads * int(Game.PART_PRICES["patch"])
	if not Game.sandbox and Game.money < price: return {"ok": false, "why": Loc.t("design.costs") % [price, Game.money]}
	return {"ok": true, "why": Loc.t("design.summary") % [host_count, leads, normalized, 9 + host_count, vlan, price],
		"price": price, "prefix": normalized, "hosts": host_count, "leads": leads}

static func deploy(rack: Net.Rack, design: Dictionary, prefix: String, vlan: int) -> String:
	var plan := preview(rack, design, prefix, vlan)
	if not bool(plan["ok"]): return String(plan["why"])
	if not Game.try_spend(int(plan["price"])): return Loc.t("design.cash_changed")
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
		Loc.t("design.all_reach") if verified else Loc.t("design.check_failed")])
	Game.topology_changed.emit()
	return "" if verified else Loc.t("design.deployed_failed")

static func port_named(dev: Net.NDevice, name: String) -> Net.Iface:
	for iface: Net.Iface in dev.ifaces:
		if iface.name == name: return iface
	return null
