class_name SimTests
## Integration checks for the packet sim + CLIs. Run headless:
##   PACKET_TEST=1 godot --headless --path . --quit-after 600
## Exit code 0 = all pass.

static var fails := 0

static func _dev_named(n: String) -> Net.NDevice:
	for d in Game.all_devices():
		if d.name == n:
			return d
	return null

static func _contract(id: String) -> Dictionary:
	for c in Contracts.all():
		if c["id"] == id:
			return c
	return {}

static func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

static func ui_smoke(world: Node2D) -> int:
	## Exercise every overlay so UI-only runtime errors surface in CI output.
	print("---- ui smoke ----")
	var ui := UILayer.new()
	world.add_child(ui)
	var r: Net.Rack = Game.racks[0]
	var dev: Net.NDevice = null
	for d in Game.all_devices():
		if d.type == "server":
			dev = d
	ui.show_welcome()
	ui.welcome_overlay.visible = false
	ui.open_rack(r)
	ui.open_dev(dev)
	ui._toggle_cli()
	ui.cli_in.text = "ip addr"
	ui._cli_submit("ip addr")
	ui._cli_submit("ssh 10.40.0.2")
	ui._cli_submit("exit")
	ui._toggle_cli()
	ui.open_iface(dev.ifaces[0])
	ui.close_iface()
	ui.close_dev()
	ui.close_rack()
	ui.open_contracts()
	ui.close_contracts()
	ui.toggle_map()
	ui.toggle_map()
	ui.toggle_help()
	ui.toggle_help()
	ui.open_pedia()
	ui.pedia_overlay.visible = false
	ui.toggle_menu()
	ui.menu_overlay.visible = false
	ui._refresh_tutorial()
	ui._refresh_money()
	print("PASS  ui: all overlays opened and refreshed without script errors")
	check(true, "ui: smoke complete")
	return fails

static func run() -> int:
	fails = 0
	Game.money = 1000000

	# --- topology: two servers on one switch ---
	var r := Game.add_rack(Vector2i(0, 0))
	var sw := Game.new_device("switch")
	var a := Game.new_device("server")
	var b := Game.new_device("server")
	r.slots[0] = sw
	r.slots[1] = a
	r.slots[2] = b
	Game.connect_ifaces(a.ifaces[0], sw.ifaces[0])
	Game.connect_ifaces(b.ifaces[0], sw.ifaces[1])
	Game.add_ip(a.ifaces[0], "10.0.0.1/24")
	Game.add_ip(b.ifaces[0], "10.0.0.2/24")

	check(Sim.ping(a, "10.0.0.2")["ok"], "L2: ping across a switch, same subnet")
	check(sw.mac_table.has(1) and sw.mac_table[1].size() == 2, "L2: switch learned both MACs in vlan 1")
	check(not Sim.ping(a, "10.0.0.99")["ok"], "L2: ping to absent host fails")

	# --- vlan isolation ---
	Game.add_vlan(sw, 10, "ten")
	Game.set_access_vlan(sw.ifaces[1], 10)
	check(not Sim.ping(a, "10.0.0.2")["ok"], "VLAN: different access vlans isolate hosts")
	Game.set_access_vlan(sw.ifaces[1], 1)
	check(Sim.ping(a, "10.0.0.2")["ok"], "VLAN: same vlan again, ping works")

	# --- disabled port ---
	sw.ifaces[0].enabled = false
	Game.topology_changed.emit()
	check(not Sim.ping(a, "10.0.0.2")["ok"], "link: disabled switchport blocks traffic")
	sw.ifaces[0].enabled = true
	Game.topology_changed.emit()

	# --- L3 across a router ---
	var sw2 := Game.new_device("switch")
	var c := Game.new_device("server")
	var rtr := Game.new_device("router")
	r.slots[3] = sw2
	r.slots[4] = c
	r.slots[5] = rtr
	Game.connect_ifaces(c.ifaces[0], sw2.ifaces[0])
	Game.connect_ifaces(rtr.ifaces[0], sw.ifaces[2])
	Game.connect_ifaces(rtr.ifaces[1], sw2.ifaces[1])
	Game.add_ip(c.ifaces[0], "10.1.0.2/24")
	Game.add_ip(rtr.ifaces[0], "10.0.0.254/24")
	Game.add_ip(rtr.ifaces[1], "10.1.0.254/24")
	Game.add_static_route(a, "0.0.0.0", 0, "10.0.0.254")
	Game.add_static_route(c, "0.0.0.0", 0, "10.1.0.254")

	check(Sim.ping(a, "10.1.0.2")["ok"], "L3: ping across router with gateways")
	check(Sim.ping(rtr, "10.0.0.1")["ok"], "L3: router pings a host directly")
	var tr := Sim.traceroute(a, "10.1.0.2")
	check(tr == ["10.0.0.254", "10.1.0.2"], "L3: traceroute shows router hop then destination (got %s)" % str(tr))
	var ttl1 := Sim.ping(a, "10.1.0.2", 1)
	check(ttl1["detail"] == "ttl-exceeded" and ttl1["from"] == "10.0.0.254", "L3: ttl=1 dies at the router")
	Game.remove_static_route(a, "0.0.0.0", 0)
	check(not Sim.ping(a, "10.1.0.2")["ok"], "L3: no default route, no reply (return path intact)")
	Game.add_static_route(a, "0.0.0.0", 0, "10.0.0.254")

	# --- EOS CLI ---
	var s := CLI.new_session(sw)
	s.exec("en")
	s.exec("conf t")
	check(s.prompt().ends_with("(config)#"), "EOS: 'en'+'conf t' abbreviations reach config mode")
	s.exec("int et4")
	check(s.prompt().contains("config-if-Et4"), "EOS: interface context prompt")
	s.exec("switchport access vlan 30")
	check(sw.vlans.has(30) and sw.ifaces[3].untagged_vlan == 30, "EOS: access vlan auto-creates vlan 30")
	s.exec("end")
	check(s.exec("sh vlan").contains("30"), "EOS: 'sh vlan' lists vlan 30")
	check(s.exec("sh run").begins_with("hostname"), "EOS: show running-config renders")
	check(s.exec("s").begins_with("% Ambiguous"), "EOS: bare 's' is ambiguous (ssh vs show)")
	check(s.exec("sh").begins_with("% Incomplete"), "EOS: 'sh' alone is an incomplete command")
	check("interface" in s.exec("help"), "EOS: help lists config commands in config-reachable mode")

	# --- Linux CLI ---
	var ls := CLI.new_session(c)
	check(ls.prompt().begins_with("root@"), "Linux: prompt")
	ls.exec("ip addr add 192.168.9.1/24 dev eth0")
	check("192.168.9.1/24" in c.ifaces[0].ips, "Linux: ip addr add")
	ls.exec("ip addr del 192.168.9.1/24 dev eth0")
	check("192.168.9.1/24" not in c.ifaces[0].ips, "Linux: ip addr del")
	var ping_out := ls.exec("ping 10.0.0.1")
	check(ping_out.contains(" 3 received"), "Linux: ping via CLI succeeds end-to-end (got: %s)" % ping_out.replace("\n", " | "))
	check(ls.exec("ip route").contains("default via 10.1.0.254"), "Linux: ip route shows default")

	# --- save / load roundtrip ---
	Game.save_game()
	var money_before := Game.money
	Game.money = 1
	check(Game.load_game(), "save: load_game returns true")
	check(Game.money == money_before, "save: money restored")
	check(Game.all_devices().size() == 6 and Game.links.size() == 5, "save: devices and links restored")
	var sw_l: Net.NDevice = null
	for d in Game.all_devices():
		if d.name == sw.name:
			sw_l = d
	check(sw_l != null and sw_l.vlans.has(30), "save: per-switch vlan database restored")
	var a_l: Net.NDevice = null
	for d in Game.all_devices():
		if d.name == a.name:
			a_l = d
	check(a_l != null and Sim.ping(a_l, "10.1.0.2")["ok"], "save: reloaded topology still routes end-to-end")

	# --- trunk allowed-vlan pruning (uses reloaded devices) ---
	var a2 := _dev_named(a.name)
	var sw_a := _dev_named(sw.name)
	var sw_b := _dev_named(sw2.name)
	var b2 := _dev_named(b.name)
	# move b onto sw2 through an inter-switch trunk, same vlan 1
	Game.disconnect_iface(b2.ifaces[0])
	Game.connect_ifaces(b2.ifaces[0], sw_b.ifaces[2])
	Game.connect_ifaces(sw_a.ifaces[3], sw_b.ifaces[3])
	sw_a.ifaces[3].mode = "trunk"
	sw_a.ifaces[3].untagged_vlan = 1
	sw_b.ifaces[3].mode = "trunk"
	Game.topology_changed.emit()
	check(Sim.ping(a2, "10.0.0.2")["ok"], "trunk: vlan 1 crosses inter-switch trunk")
	sw_a.ifaces[3].tagged_vlans = [30]
	Game.topology_changed.emit()
	check(not Sim.ping(a2, "10.0.0.2")["ok"], "trunk: pruning vlan 1 off the trunk blocks it")
	sw_a.ifaces[3].tagged_vlans = []
	Game.topology_changed.emit()

	# --- spanning tree over a redundant loop ---
	Game.connect_ifaces(sw_a.ifaces[1], sw_b.ifaces[4])
	Game.topology_changed.emit()
	check(Sim.ping(a2, "10.0.0.2")["ok"], "stp: redundant switch loop doesn't storm, ping still works")
	var blocked_n := 0
	for ifc in [sw_a.ifaces[1], sw_a.ifaces[3], sw_b.ifaces[3], sw_b.ifaces[4]]:
		if Sim.stp_blocked(ifc):
			blocked_n += 1
	check(blocked_n == 1, "stp: exactly one port of the loop is discarding (got %d)" % blocked_n)
	var ses := CLI.new_session(sw_a)
	check(ses.exec("show spanning-tree").contains("Root bridge"), "stp: show spanning-tree renders")
	sw_a.ifaces[3].enabled = false
	Game.topology_changed.emit()
	check(Sim.ping(a2, "10.0.0.2")["ok"], "stp: primary link dies, blocked spare takes over")
	sw_a.ifaces[3].enabled = true
	Game.topology_changed.emit()

	# --- capture ---
	Sim.ping(a2, "10.0.0.2")
	check(not a2.capture.is_empty() and "ICMP" in "\n".join(PackedStringArray(a2.capture)),
		"capture: tcpdump buffer records ICMP frames")

	# --- contracts ---
	var money0 := Game.money
	check(Game.try_complete_contract(_contract("rackup")), "contracts: rack-and-stack completes against live state")
	check(Game.try_complete_contract(_contract("first_ping")), "contracts: first-ping completes (sim-verified)")
	check(not Game.try_complete_contract(_contract("two_tenants")), "contracts: vlan-isolation contract not yet satisfiable")
	check(not Game.try_complete_contract(_contract("rackup")), "contracts: no double collection")
	check(Game.money == money0 + 900, "contracts: rewards paid once")

	# --- DHCP + DNS ---
	var r2: Net.Rack = Game.racks[0]
	var dhcp_srv := Game.new_device("server")
	var client := Game.new_device("server")
	r2.slots[6] = dhcp_srv
	r2.slots[7] = client
	var sw_c := _dev_named(sw.name)
	Game.connect_ifaces(dhcp_srv.ifaces[0], sw_c.ifaces[4])
	Game.connect_ifaces(client.ifaces[0], sw_c.ifaces[5])
	var dls := CLI.new_session(dhcp_srv)
	dls.exec("ip addr add 10.2.0.5/24 dev eth0")
	dls.exec("dhcpd eth0 10.2.0.10 10.2.0.99 24 10.2.0.5 10.2.0.5")
	dls.exec("dns add www.delta.hu 10.2.0.10")
	var cls_ := CLI.new_session(client)
	var lease_out: String = cls_.exec("dhclient eth0")
	check("bound to 10.2.0.10/24" in lease_out, "dhcp: client got the first lease (got: %s)" % lease_out.strip_edges())
	check(client.resolver == "10.2.0.5", "dhcp: lease delivered the DNS resolver")
	check(Sim.ping(client, "10.2.0.5")["ok"], "dhcp: leased address is routable")
	check(cls_.exec("dhclient eth0").contains("10.2.0.10"), "dhcp: same MAC keeps its lease")
	check(Sim.resolve(client, "www.delta.hu") == "10.2.0.10", "dns: client resolves via the network")
	check(cls_.exec("ping www.delta.hu").contains("3 received"), "dns: ping by name works (client owns the A record)")
	check(cls_.exec("nslookup nope.example").contains("can't find"), "dns: unknown name fails cleanly")

	# --- superseded contracts retire instead of breaching ---
	check(not Contracts.retired("first_ping"), "retire: first_ping active before two_tenants")
	Game.contracts_done.append("two_tenants")
	check(Contracts.retired("first_ping"), "retire: two_tenants supersedes first_ping")
	Game.sla_tick()
	check(Game.sla_status.get("first_ping", false), "retire: retired contract never breaches")
	Game.contracts_done.erase("two_tenants")
	Game.sla_status.erase("two_tenants")

	# --- SLA recurring revenue ---
	var m1 := Game.money
	Game.sla_tick()
	check(Game.money == m1 + 40 + 50, "sla: healthy contracts pay recurring fees")
	var a3 := _dev_named(a.name)
	a3.ifaces[0].enabled = false
	Game.topology_changed.emit()
	var m2 := Game.money
	Game.sla_tick()
	check(Game.money < m2 + 90, "sla: broken network stops (part of) the revenue")
	check(Game.sla_status.values().has(false), "sla: breach is flagged for the UI")
	a3.ifaces[0].enabled = true
	Game.topology_changed.emit()

	# --- firewall ACLs ---
	var r3 := Game.add_rack(Vector2i(1, 0))
	var fw := Game.new_device("fw-1")
	var office := Game.new_device("server")
	var vault := Game.new_device("server")
	r3.slots[0] = fw
	r3.slots[1] = office
	r3.slots[2] = vault
	Game.connect_ifaces(office.ifaces[0], fw.ifaces[0])
	Game.connect_ifaces(vault.ifaces[0], fw.ifaces[1])
	Game.add_ip(office.ifaces[0], "172.16.1.10/24")
	Game.add_ip(vault.ifaces[0], "172.16.2.20/24")
	Game.add_ip(fw.ifaces[0], "172.16.1.1/24")
	Game.add_ip(fw.ifaces[1], "172.16.2.1/24")
	Game.add_static_route(office, "0.0.0.0", 0, "172.16.1.1")
	Game.add_static_route(vault, "0.0.0.0", 0, "172.16.2.1")
	check(Sim.ping(office, "172.16.2.20")["ok"], "fw: default permit forwards")
	var fs := CLI.new_session(fw)
	fs.exec("en")
	fs.exec("conf t")
	fs.exec("acl deny 172.16.1.0/24 172.16.2.20/32")
	check(not Sim.ping(office, "172.16.2.20")["ok"], "fw: deny rule blocks office->vault")
	check(not Sim.ping(vault, "172.16.1.10")["ok"],
		"fw: stateless: vault->office echo passes but its reply is filtered (the classic lesson)")
	check(fs.exec("end") == "" and fs.exec("show acl").contains("deny"), "fw: show acl lists the rule")
	fs.exec("conf t")
	fs.exec("no acl 1")
	check(Sim.ping(office, "172.16.2.20")["ok"], "fw: removing the rule restores traffic")
	fs.exec("acl deny 172.16.1.0/24 172.16.2.20/32")

	# --- stateful firewall ---
	var fw_ss := CLI.new_session(fw)
	fw_ss.exec("en")
	fw_ss.exec("conf t")
	fw_ss.exec("firewall stateful")
	fw_ss.exec("end")
	check(Sim.ping(vault, "172.16.1.10")["ok"],
		"fw: stateful mode lets the vault's outbound flow get its replies")
	check(not Sim.ping(office, "172.16.2.20")["ok"], "fw: the deny still blocks unsolicited office->vault")
	check(fw_ss.exec("show acl").contains("stateful"), "fw: show acl reports the mode")
	fw_ss.exec("conf t")
	fw_ss.exec("no firewall stateful")
	fw_ss.exec("end")

	# --- stages & power ---
	check(Game.grid_size() == Vector2i(3, 3), "stage: colo corner is 3x3")
	check(Game.power_draw() > 0, "stage: hardware draws watts")
	var m3 := Game.money
	check(Game.expand(), "stage: expansion purchasable")
	check(Game.money == m3 - 5000 and Game.grid_size() == Vector2i(7, 7), "stage: server room paid and unlocked")
	var crac1 := Game.new_device("crac-1")
	var crac2 := Game.new_device("crac-1")
	r3.slots[6] = crac1
	r3.slots[7] = crac2
	check(Game.cooling_capacity() >= 3000 and not Game.overheating(), "heat: CRACs cover the room")
	var m4 := Game.money
	Game.sla_tick()
	check(Game.money - m4 < 90 + 40 + 50, "stage: power bill now reduces cycle income")

	# --- marketplace negotiation & delivery ---
	var off := {"id": "t1", "kind": "hosting", "customer": "TestCo", "brief": "", "costs": "",
		"params": {"ip": "10.9.9.10"}, "budget": 100, "hint": "", "state": "open", "ttl": 5}
	Game.offers.append(off)
	check(Game.respond_offer(off, 200) == "rejected" and not (off in Game.offers),
		"market: greedy quote is rejected, customer walks")
	var off2 := off.duplicate(true)
	off2["state"] = "open"
	Game.offers.append(off2)
	check(Game.respond_offer(off2, 120) == "counter" and off2["state"] == "counter",
		"market: near-budget quote draws a counteroffer")
	Game.accept_counter(off2)
	check(Game.deals.size() == 1 and int(Game.deals[0]["fee"]) == 100,
		"market: counter signs at their budget")
	Game.incidents_seen["%s|%s" % [b2.name, rtr.name]] = true  # security tested separately below
	Game.sla_tick()
	check(Game.deals[0]["healthy"] == false, "market: undelivered deal does not pay")
	Game.add_ip(b2.ifaces[0], "10.9.9.10/24")
	Game.add_ip(a2.ifaces[0], "10.9.9.11/24")
	var m6 := Game.money
	Game.sla_tick()
	check(Game.deals[0]["healthy"], "market: delivering the service marks the deal healthy")
	check(Game.money > m6, "market: healthy deal fee lands in the cycle income")
	var off3 := off.duplicate(true)
	off3["state"] = "open"
	Game.offers.append(off3)
	check(Game.respond_offer(off3, 90) == "accepted" and Game.deals.size() == 2,
		"market: fair quote accepted directly")

	# --- security sweep: exposed management plane ---
	Game.incidents_seen.clear()
	var m7 := Game.money
	var ev0 := Game.events.size()
	Game.sla_tick()  # deal server b2 can reach rtr's 10.0.0.254 -> one-shot incident
	check(Game.events.size() > ev0 and "SECURITY" in Game.events[0], "sec: exposed management logs an incident")
	var m8 := Game.money
	var ev1 := Game.events.size()
	Game.sla_tick()
	check(Game.events.size() == ev1 or "SECURITY" not in Game.events[0], "sec: same exposure doesn't bill twice")
	check(m8 > m7 - 200, "sec: incident cost bounded")

	# --- RouterOS CLI (PacketTik gear) ---
	var mkt_sw := Game.new_device("sw-lite")
	var mkt_rtr := Game.new_device("rtr-lite")
	r3.slots[3] = mkt_sw
	r3.slots[4] = mkt_rtr
	var rs := CLI.new_session(mkt_sw)
	check(rs is ROS and rs.prompt().begins_with("[admin@"), "ros: PacketTik gear speaks RouterOS")
	check(mkt_sw.ifaces[0].name == "ether1", "ros: PacketTik ports are etherN")
	rs.exec("/interface bridge vlan add vlan-ids=50 comment=lab")
	check(mkt_sw.vlans.has(50), "ros: bridge vlan add creates vlan")
	rs.exec("/interface set ether2 pvid=50")
	check(mkt_sw.ifaces[1].untagged_vlan == 50 and mkt_sw.ifaces[1].mode == "access", "ros: pvid assigns access vlan")
	check(rs.exec("export").contains("vlan-ids=50"), "ros: export renders config")
	var rr := CLI.new_session(mkt_rtr)
	rr.exec("/ip address add address=10.7.0.1/24 interface=ether1")
	check("10.7.0.1/24" in mkt_rtr.ifaces[0].ips, "ros: ip address add")
	rr.exec("/routing bgp set as=65010")
	rr.exec("/routing bgp peer add address=100.64.0.9 as=64500")
	check(mkt_rtr.bgp["neighbors"].size() == 1, "ros: bgp peer configured")

	# --- BGP to the internet (EOS router) ---
	var r4 := Game.add_rack(Vector2i(2, 0))
	var upl := Game.new_device("isp-uplink")
	var edge := Game.new_device("rtr-edge")
	var web := Game.new_device("server")
	r4.slots[0] = upl
	r4.slots[1] = edge
	r4.slots[2] = web
	Game.connect_ifaces(upl.ifaces[0], edge.ifaces[0])
	Game.connect_ifaces(web.ifaces[0], edge.ifaces[1])
	Game.add_ip(edge.ifaces[0], "100.64.0.2/30")
	Game.add_ip(edge.ifaces[1], "10.3.0.1/24")
	Game.add_ip(web.ifaces[0], "10.3.0.10/24")
	Game.add_static_route(web, "0.0.0.0", 0, "10.3.0.1")
	var es := CLI.new_session(edge)
	es.exec("en")
	es.exec("conf t")
	es.exec("router bgp 65001")
	es.exec("neighbor 100.64.0.1 remote-as 64500")
	es.exec("end")
	check(es.exec("show ip bgp summary").contains("Established"), "bgp: session establishes with the handoff")
	check(Sim.ping(edge, "8.8.8.8")["ok"], "bgp: router reaches the internet via learned default")
	check(not Sim.ping(web, "8.8.8.8")["ok"], "bgp: server fails until prefix announced (no return path)")
	es.exec("conf t")
	es.exec("router bgp 65001")
	es.exec("network 10.3.0.0/24")
	es.exec("end")
	check(Sim.ping(web, "8.8.8.8")["ok"], "bgp: announcing the prefix opens the return path")
	check(Game.try_complete_contract(_contract("join_internet")), "bgp: join-the-internet contract verifies")

	# --- NAT masquerade ---
	es.exec("conf t")
	es.exec("router bgp 65001")
	es.exec("no network 10.3.0.0/24")
	es.exec("end")
	check(not Sim.ping(web, "8.8.8.8")["ok"], "nat: withdrawn announcement kills unNATed reachability")
	es.exec("conf t")
	es.exec("int et1")
	es.exec("ip nat outside")
	es.exec("end")
	check(Sim.ping(web, "8.8.8.8")["ok"], "nat: masquerade restores internet for the private server")
	check(es.exec("sh run").contains("ip nat outside"), "nat: rendered in running-config")
	check(Game.try_complete_contract(_contract("hide_the_internals")), "nat: contract verifies")

	# --- overheating trips gear ---
	crac1.status = "offline"
	crac2.status = "offline"
	Game.topology_changed.emit()
	check(Game.overheating(), "heat: losing cooling overheats the room")
	Game.sla_tick()
	var tripped: Net.NDevice = null
	for d in Game.all_devices():
		if d.status == "offline" and d.type != "cooling":
			tripped = d
	check(tripped != null, "heat: overheating trips a device offline")
	tripped.status = "active"
	crac1.status = "active"
	crac2.status = "active"
	Game.topology_changed.emit()
	check(not Game.overheating(), "heat: cooling restored")
	check(Game.try_complete_contract(_contract("feel_the_heat")), "heat: feeling-the-heat contract verifies")

	# --- discovery/diagnostic commands ---
	var es2 := CLI.new_session(edge)
	check(es2.exec("sh lldp neighbors").contains(upl.name), "cli: EOS lldp lists the uplink neighbor")
	var wls := CLI.new_session(web)
	Sim.ping(web, "10.3.0.1")
	check(wls.exec("ip neigh").contains("10.3.0.1"), "cli: Linux ip neigh shows the gateway ARP entry")
	check(wls.exec("lldp").contains(edge.name), "cli: Linux lldp sees the router")
	var rs2 := CLI.new_session(mkt_sw)
	check("bridge host" in rs2.exec("help"), "cli: ROS help lists bridge host print")
	check("print" in rs2.complete("/interface ") and "set" in rs2.complete("/interface "),
		"cli: ROS tab completes next word after a full token")
	check(rs2.complete("/ip ad") == ["address"], "cli: ROS tab completes partial second token")
	check("arp" in rs2.complete("/ip a") and "address" in rs2.complete("/ip a"),
		"cli: ROS tab lists all matching branches")
	check("add" in rs2.complete("/ip address vlan-ids=5 "), "cli: ROS tab ignores key=value args")
	check(rs2.exec("routing bgp").begins_with("incomplete command"), "cli: ROS partial path lists what can follow")

	# --- OSPF dynamic routing ---
	var r5 := Game.add_rack(Vector2i(0, 1))
	var o_r1 := Game.new_device("rtr-edge")
	var o_r2 := Game.new_device("rtr-lite")
	var t1 := Game.new_device("server")
	var t2 := Game.new_device("server")
	r5.slots[0] = o_r1
	r5.slots[1] = o_r2
	r5.slots[2] = t1
	r5.slots[3] = t2
	Game.connect_ifaces(t1.ifaces[0], o_r1.ifaces[1])
	Game.connect_ifaces(o_r1.ifaces[2], o_r2.ifaces[1])
	Game.connect_ifaces(t2.ifaces[0], o_r2.ifaces[2])
	Game.add_ip(t1.ifaces[0], "10.20.1.10/24")
	Game.add_ip(o_r1.ifaces[1], "10.20.1.1/24")
	Game.add_ip(o_r1.ifaces[2], "10.20.9.1/30")
	Game.add_ip(o_r2.ifaces[1], "10.20.9.2/30")
	Game.add_ip(o_r2.ifaces[2], "10.20.2.1/24")
	Game.add_ip(t2.ifaces[0], "10.20.2.10/24")
	Game.add_static_route(t1, "0.0.0.0", 0, "10.20.1.1")
	Game.add_static_route(t2, "0.0.0.0", 0, "10.20.2.1")
	check(not Sim.ping(t1, "10.20.2.10")["ok"], "ospf: no routes yet, offices can't talk")
	var os1 := CLI.new_session(o_r1)
	os1.exec("en")
	os1.exec("conf t")
	os1.exec("router ospf")
	os1.exec("network 10.20.0.0/16 area 0")
	os1.exec("end")
	var os2 := CLI.new_session(o_r2)
	os2.exec("/routing ospf network add prefix=10.20.0.0/16")
	check(os1.exec("show ip ospf neighbor").contains(o_r2.name), "ospf: adjacency comes up (EOS side)")
	check(os2.exec("/routing ospf print").contains(o_r1.name), "ospf: adjacency visible from RouterOS side")
	check(Sim.ping(t1, "10.20.2.10")["ok"] and Sim.ping(t2, "10.20.1.10")["ok"],
		"ospf: cross-office ping with zero static routes on routers")
	check(os1.exec("sh ip route").contains("O  10.20.2.0/24"), "ospf: O route in show ip route")
	check(Game.try_complete_contract(_contract("dynamic_routing")), "ospf: contract verifies")
	os1.exec("conf t")
	os1.exec("router ospf")
	os1.exec("no network 10.20.0.0/16")
	os1.exec("end")
	check(not Sim.ping(t1, "10.20.2.10")["ok"], "ospf: withdrawing networks drops the adjacency and the routes")
	os1.exec("conf t")
	os1.exec("router ospf")
	os1.exec("network 10.20.0.0/16 area 0")
	os1.exec("end")

	# --- reputation & public hosting ---
	var rep0 := Game.reputation
	Game.sla_tick()
	check(Game.reputation != rep0 or Game.reputation in [0, 100], "rep: cycles move reputation")
	es.exec("conf t")
	es.exec("router bgp 65001")
	es.exec("network 10.3.0.0/24")
	es.exec("end")
	check(Market.check("public_hosting", {"ip": "10.3.0.10"}), "market: public hosting verified from the uplink side (needs the announcement back)")
	check(not Market.check("public_hosting", {"ip": "10.0.0.1"}), "market: unreachable-from-internet host fails the check")

	# --- traffic counters ---
	var s_cnt := CLI.new_session(sw_a)
	s_cnt.exec("en")
	s_cnt.exec("clear counters")
	Sim.ping(a2, "10.0.0.2")
	check(sw_a.ifaces[0].rx_frames > 0, "counters: switch port counted rx frames")
	check(s_cnt.exec("show interfaces counters").contains("InFrames"), "counters: EOS table renders")
	s_cnt.exec("clear counters")
	check(sw_a.ifaces[0].rx_frames == 0, "counters: clear counters resets")

	# --- OOB management + ssh ---
	var mg: Net.Iface = null
	for ifc: Net.Iface in sw_a.ifaces:
		if ifc.name.begins_with("Management"):
			mg = ifc
	check(mg != null, "mgmt: save migration added Management1 to old switches")
	Game.connect_ifaces(mg, sw_b.ifaces[5])
	var ms := CLI.new_session(sw_a)
	ms.exec("en")
	ms.exec("conf t")
	ms.exec("int man1")
	check(ms.prompt().contains("Management1"), "mgmt: interface Management1 reachable by abbreviation")
	ms.exec("ip address 10.0.0.99/24")
	ms.exec("end")
	check(Sim.ping(a2, "10.0.0.99")["ok"], "mgmt: switch answers ping on its mgmt address")
	check(Sim.ping(sw_a, "10.0.0.1")["ok"], "mgmt: switch pings out via mgmt")
	var blocked_after := 0
	for ifc in [sw_a.ifaces[1], sw_a.ifaces[3], sw_b.ifaces[3], sw_b.ifaces[4]]:
		if Sim.stp_blocked(ifc):
			blocked_after += 1
	check(blocked_after == 1, "mgmt: mgmt link doesn't disturb spanning tree")
	var ssh_ls := CLI.new_session(a2)
	var ssh_out: String = ssh_ls.exec("ssh 10.0.0.99")
	check("Connected to" in ssh_out and ssh_ls.pending_ssh == sw_a, "ssh: server reaches switch mgmt")
	var inner := CLI.new_session(ssh_ls.pending_ssh)
	check(inner.prompt().begins_with(sw_a.name), "ssh: nested session lands on the switch")
	inner.exec("exit")
	check(inner.wants_exit, "ssh: exit flags return to the outer session")
	check("No route" in ssh_ls.exec("ssh 172.31.9.9"), "ssh: unreachable target refused")
	Game.incidents_seen.clear()
	Game.sla_tick()
	var found_sw_event := false
	for ev in Game.events:
		if "SECURITY" in ev and sw_a.name in ev:
			found_sw_event = true
	check(found_sw_event, "mgmt: exposed switch management triggers a security incident")

	# --- loans ---
	var money_b := Game.money
	check(Game.borrow() and Game.money == money_b + 1000 and Game.debt == 1000, "bank: borrow lands a tranche")
	Game.debt = 0
	var d0_start := Game.money
	Game.sla_tick()
	var delta0 := Game.money - d0_start
	Game.debt = 10000
	var d1_start := Game.money
	Game.sla_tick()
	var delta1 := Game.money - d1_start
	check(delta0 - delta1 == 500, "bank: interest bites exactly debt*rate (got %d)" % (delta0 - delta1))
	Game.debt = 1000
	check(Game.repay() and Game.debt == 0, "bank: repay clears the tranche")

	# --- capstone contract ---
	var sw_bb := _dev_named(sw2.name)
	Game.add_vlan(sw_bb, 30, "omega")
	Game.set_access_vlan(sw_bb.ifaces[2], 30)  # b2's port
	Game.add_ip(_dev_named(web.name).ifaces[0], "10.30.0.10/24")
	var fs2 := CLI.new_session(_dev_named(fw.name))
	fs2.exec("en")
	fs2.exec("conf t")
	fs2.exec("acl deny any 10.30.0.0/24")
	fs2.exec("end")
	check(Game.try_complete_contract(_contract("big_client")), "capstone: the big client signs")

	for ifc: Net.Iface in sw_bb.ifaces:
		if ifc.name.begins_with("Management"):
			Game.add_ip(ifc, "10.0.0.98/24")
	check(Market.check("managed_switch", {"vid": 30}), "market: managed-switch kind verifies (vlan 30 + addressed mgmt)")
	check(not Market.check("managed_switch", {"vid": 777}), "market: managed-switch fails for absent vlan")

	# --- VRRP failover ---
	var r6 := Game.add_rack(Vector2i(1, 1))
	var vr1 := Game.new_device("rtr-edge")
	var vr2 := Game.new_device("rtr-edge")
	var vsw := Game.new_device("sw-8")
	var vcl := Game.new_device("server")
	r6.slots[0] = vr1
	r6.slots[1] = vr2
	r6.slots[2] = vsw
	r6.slots[3] = vcl
	Game.connect_ifaces(vr1.ifaces[0], vsw.ifaces[0])
	Game.connect_ifaces(vr2.ifaces[0], vsw.ifaces[1])
	Game.connect_ifaces(vcl.ifaces[0], vsw.ifaces[2])
	Game.add_ip(vr1.ifaces[0], "10.40.0.2/24")
	Game.add_ip(vr2.ifaces[0], "10.40.0.3/24")
	Game.add_ip(vcl.ifaces[0], "10.40.0.10/24")
	Game.add_static_route(vcl, "0.0.0.0", 0, "10.40.0.1")
	var v1 := CLI.new_session(vr1)
	v1.exec("en")
	v1.exec("conf t")
	v1.exec("int et1")
	v1.exec("vrrp 1 ip 10.40.0.1")
	v1.exec("vrrp 1 priority 120")
	v1.exec("end")
	var v2 := CLI.new_session(vr2)
	v2.exec("en")
	v2.exec("conf t")
	v2.exec("int et1")
	v2.exec("vrrp 1 ip 10.40.0.1")
	v2.exec("end")
	check(Sim.vrrp_master("10.40.0.1", 1) == vr1, "vrrp: higher priority wins mastership")
	check(Sim.ping(vcl, "10.40.0.1")["ok"], "vrrp: client pings the virtual gateway")
	check(v1.exec("show vrrp").contains("Master"), "vrrp: show vrrp reports Master")
	check(v2.exec("show vrrp").contains("Backup"), "vrrp: show vrrp reports Backup")
	check(Game.try_complete_contract(_contract("no_spof")), "vrrp: no-SPOF contract verifies")
	vr1.status = "offline"
	Game.topology_changed.emit()
	check(Sim.vrrp_master("10.40.0.1", 1) == vr2, "vrrp: backup takes over when master dies")
	check(Sim.ping(vcl, "10.40.0.1")["ok"], "vrrp: virtual IP survives the master's death")
	vr1.status = "active"
	Game.topology_changed.emit()

	# --- field faults, redundant-gw offers, reverse DNS ---
	Game._field_fault()
	var faulted: Net.Iface = null
	for l in Game.links:
		for ifc in [l.a, l.b]:
			if not ifc.enabled and not ifc.name.begins_with("Management"):
				faulted = ifc
	check(faulted != null and "FIELD" in Game.events[0], "field: a fault takes a port down and logs it")
	if faulted:
		faulted.enabled = true
		Game.topology_changed.emit()
	check(Market.check("redundant_gw", {"vip": "10.40.0.1"}), "market: redundant-gw kind verifies the VRRP setup")
	check(not Market.check("redundant_gw", {"vip": "10.99.99.1"}), "market: redundant-gw fails for absent vip")
	check(cls_.exec("nslookup 10.2.0.10").contains("www.delta.hu"), "dns: reverse lookup finds the name")
	check(cls_.exec("nslookup 10.2.0.77").contains("no PTR"), "dns: reverse lookup fails cleanly")

	# --- rack selling ---
	var r_sell := Game.add_rack(Vector2i(2, 1))
	var m_sell := Game.money
	check(Game.sell_rack(r_sell) and Game.money == m_sell + Game.RACK_PRICE / 2, "rack: empty rack sells for half")
	check(not Game.sell_rack(Game.racks[0]), "rack: occupied rack refuses to sell")

	# --- grandfathering ---
	Game.add_rack(Vector2i(8, 8))
	Game.stage = 0
	check(Game._rack_outside_grid(), "legacy: racks outside a 3x3 colo are detected")
	Game.save_game()
	Game.load_game()
	check(not Game._rack_outside_grid(), "legacy: load grandfathers the stage until racks fit")

	# --- economy walkthrough: the colo arc must be affordable ---
	Game.racks = []
	Game.links = []
	Game.deals = []
	Game.offers = []
	Game.contracts_done = []
	Game.sla_status = {}
	Game.stage = 0
	Game.debt = 0
	Game.money = 2000
	Game.topology_changed.emit()
	var w_rack := Game.add_rack(Vector2i(0, 0))
	check(Game.try_spend(Game.RACK_PRICE), "walkthrough: rack affordable at start")
	var w_sw := Game.new_device("sw-lite")
	var w_s1 := Game.new_device("srv-1")
	var w_s2 := Game.new_device("srv-1")
	check(Game.try_spend(90 + 400 + 400), "walkthrough: tier-0 starter kit affordable")
	w_rack.slots[0] = w_sw
	w_rack.slots[1] = w_s1
	w_rack.slots[2] = w_s2
	Game.connect_ifaces(w_s1.ifaces[0], w_sw.ifaces[0])
	Game.connect_ifaces(w_s2.ifaces[0], w_sw.ifaces[1])
	check(Game.try_complete_contract(_contract("rackup")), "walkthrough: contract 1 pays")
	Game.add_ip(w_s1.ifaces[0], "10.0.0.1/24")
	Game.add_ip(w_s2.ifaces[0], "10.0.0.2/24")
	check(Game.try_complete_contract(_contract("first_ping")), "walkthrough: contract 2 pays")
	Game.add_vlan(w_sw, 10, "alfa")
	Game.add_vlan(w_sw, 20, "beta")
	Game.set_access_vlan(w_sw.ifaces[0], 10)
	Game.set_access_vlan(w_sw.ifaces[1], 20)
	check(Game.try_complete_contract(_contract("two_tenants")), "walkthrough: contract 3 pays")
	check(Game.money > 0, "walkthrough: never broke during the colo arc (have $%d)" % Game.money)
	var cycles := 0
	while Game.money < 5000 + 1500 and cycles < 40:
		Game.sla_tick()
		cycles += 1
	check(cycles < 40, "walkthrough: expansion affordable within %d cycles" % cycles)

	# --- port-channels ---
	var lsw1 := Game.new_device("sw-8")
	var lsw2 := Game.new_device("sw-8")
	var lh1 := Game.new_device("server")
	var lh2 := Game.new_device("server")
	var r7 := Game.add_rack(Vector2i(3, 1))
	r7.slots[0] = lsw1
	r7.slots[1] = lsw2
	r7.slots[2] = lh1
	r7.slots[3] = lh2
	Game.connect_ifaces(lh1.ifaces[0], lsw1.ifaces[0])
	Game.connect_ifaces(lh2.ifaces[0], lsw2.ifaces[0])
	Game.connect_ifaces(lsw1.ifaces[1], lsw2.ifaces[1])
	Game.connect_ifaces(lsw1.ifaces[2], lsw2.ifaces[2])
	Game.add_ip(lh1.ifaces[0], "10.50.0.1/24")
	Game.add_ip(lh2.ifaces[0], "10.50.0.2/24")
	Game.topology_changed.emit()
	var pre_blocked := Sim.stp_blocked(lsw1.ifaces[1]) or Sim.stp_blocked(lsw1.ifaces[2]) \
		or Sim.stp_blocked(lsw2.ifaces[1]) or Sim.stp_blocked(lsw2.ifaces[2])
	check(pre_blocked, "lag: without bundling, STP blocks the parallel link")
	var lag_s := CLI.new_session(lsw1)
	lag_s.exec("en")
	lag_s.exec("conf t")
	lag_s.exec("int et2")
	lag_s.exec("channel-group 1")
	lag_s.exec("int et3")
	lag_s.exec("channel-group 1")
	lag_s.exec("end")
	var lag_s2 := CLI.new_session(lsw2)
	lag_s2.exec("en")
	lag_s2.exec("conf t")
	lag_s2.exec("int et2")
	lag_s2.exec("channel-group 1")
	lag_s2.exec("int et3")
	lag_s2.exec("channel-group 1")
	lag_s2.exec("end")
	var post_blocked := Sim.stp_blocked(lsw1.ifaces[1]) or Sim.stp_blocked(lsw1.ifaces[2]) \
		or Sim.stp_blocked(lsw2.ifaces[1]) or Sim.stp_blocked(lsw2.ifaces[2])
	check(not post_blocked, "lag: bundled links form one logical edge, nothing blocked")
	check(Sim.ping(lh1, "10.50.0.2")["ok"], "lag: traffic flows over the bundle")
	check(Game.link_capacity(Game.link_at(lsw1.ifaces[1])) == 2000, "lag: bundle capacity sums members")
	check(lag_s.exec("show port-channel").contains("Et2,Et3"), "lag: show port-channel lists members")
	lsw1.ifaces[1].enabled = false
	Game.topology_changed.emit()
	check(Sim.ping(lh1, "10.50.0.2")["ok"], "lag: member death fails over inside the bundle")
	lsw1.ifaces[1].enabled = true
	Game.topology_changed.emit()

	check(Game.try_complete_contract(_contract("double_the_pipe")), "lag: double-the-pipe contract verifies")
	var ros_bond := CLI.new_session(mkt_sw)
	ros_bond.exec("/interface bonding add slaves=ether3,ether4")
	check(mkt_sw.ifaces[2].lag > 0 and mkt_sw.ifaces[2].lag == mkt_sw.ifaces[3].lag,
		"lag: RouterOS bonding maps to the same model")

	# --- DHCP relay ---
	var rel_r := Game.new_device("rtr-edge")
	var rel_srv := Game.new_device("server")
	var rel_cli := Game.new_device("server")
	r7.slots[4] = rel_r
	r7.slots[5] = rel_srv
	r7.slots[6] = rel_cli
	Game.connect_ifaces(rel_cli.ifaces[0], rel_r.ifaces[0])
	Game.connect_ifaces(rel_srv.ifaces[0], rel_r.ifaces[1])
	Game.add_ip(rel_r.ifaces[0], "10.60.0.1/24")
	Game.add_ip(rel_r.ifaces[1], "10.61.0.1/24")
	Game.add_ip(rel_srv.ifaces[0], "10.61.0.5/24")
	Game.add_static_route(rel_srv, "0.0.0.0", 0, "10.61.0.1")
	var rel_ss := CLI.new_session(rel_srv)
	rel_ss.exec("dhcpd eth0 10.60.0.50 10.60.0.99 24 10.60.0.1 10.61.0.5")
	var rel_es := CLI.new_session(rel_r)
	rel_es.exec("en")
	rel_es.exec("conf t")
	rel_es.exec("int et1")
	rel_es.exec("ip helper-address 10.61.0.5")
	rel_es.exec("end")
	var rel_out: String = CLI.new_session(rel_cli).exec("dhclient eth0")
	check("bound to 10.60.0.50/24" in rel_out, "relay: client leased across the router (got: %s)" % rel_out.strip_edges())
	check(Sim.ping(rel_cli, "10.61.0.5")["ok"], "relay: leased client routes to the central DHCP server")

	# --- capacity planning ---
	check(Game.iface_speed(vr1.ifaces[0]) == 10000, "capacity: Junivista port is 10G")
	check(Game.iface_speed(mkt_sw.ifaces[0]) == 1000, "capacity: PacketTik port is 1G")
	Game.stage = 1  # no random field faults during deterministic capacity checks
	Game.racks.append(r6)  # the walkthrough reset dropped the VRRP rack; bring it back
	Game.connect_ifaces(vr1.ifaces[0], vsw.ifaces[0])
	Game.connect_ifaces(vr2.ifaces[0], vsw.ifaces[1])
	Game.connect_ifaces(vcl.ifaces[0], vsw.ifaces[2])
	for l in Game.links:
		l.a.enabled = true
		l.b.enabled = true
	Game.topology_changed.emit()
	var cap_deal := {"id": "cap1", "customer": "LoadCo", "kind": "hosting",
		"params": {"ip": "10.40.0.10"}, "fee": 100, "brief": "", "load": 1500, "healthy": false}
	Game.deals.append(cap_deal)
	Game.sla_tick()
	check(cap_deal["healthy"] and cap_deal.get("degraded", false),
		"capacity: 1500 Mbps through 1G access link degrades the deal")
	cap_deal["load"] = 200
	Game.sla_tick()
	check(not cap_deal.get("degraded", true), "capacity: modest load fits, deal recovers")
	Game.connect_ifaces(vr1.ifaces[1], vr2.ifaces[1])  # 10G Junivista-to-Junivista core link
	check(Game.try_complete_contract(_contract("bandwidth_crunch")), "capacity: bandwidth-crunch contract verifies")
	Game.deals.erase(cap_deal)

	# --- undelivered deals cancel ---
	var ghost := {"id": "ghost", "customer": "NoShow Kft", "kind": "hosting",
		"params": {"ip": "10.222.222.10"}, "fee": 50, "brief": "", "load": 100, "healthy": false}
	Game.deals.append(ghost)
	for i in 4:
		Game.sla_tick()
	check(ghost in Game.deals and int(ghost["missed"]) == 4, "deal: undelivered deal accrues missed cycles")
	Game.sla_tick()
	check(not (ghost in Game.deals), "deal: five undelivered cycles cancels the deal")
	var cancelled := false
	for ev in Game.events:
		if "CANCELLED" in ev:
			cancelled = true
	check(cancelled, "deal: cancellation is logged")

	# --- incident drills ---
	var pre_devs := Game.all_devices().size()
	var pre_money := Game.money
	Drill.start(3, 42)
	check(Game.drill_active and Drill.faults.size() >= 2, "drill: starts with hidden faults")
	check(Drill.scenario != "" and not Drill.targets.is_empty(), "drill: scenario named with targets")
	check(not Drill.solved(), "drill: the generated network is actually broken")
	var pre_cycle := Game.cycle
	Game.sla_tick()
	check(Game.cycle == pre_cycle, "drill: the economy pauses during a drill")
	Drill.cheat_fix()
	check(Drill.solved(), "drill: reverting the faults restores all pings")
	var revealed: Array = Drill.finish(true)
	check(not Game.drill_active and revealed.size() >= 2, "drill: finish reveals the fault list")
	check(Game.all_devices().size() == pre_devs, "drill: the real datacenter came back intact")
	check(Game.money == pre_money + Drill.REWARD, "drill: passing pays the bonus")
	check(Drill.finish(false).is_empty(), "drill: finishing with no drill running is a no-op")
	for sc_seed in [1, 2, 3, 4, 5, 6]:  # every scenario must be solvable from its faults
		Drill.start(3, sc_seed)
		Drill.cheat_fix()
		var ok_sc: bool = Drill.solved()
		Drill.finish(false)
		check(ok_sc, "drill: scenario (seed %d) is solvable after reverting faults" % sc_seed)
	Drill.start(2, 7)
	var during := Game.all_devices().size()
	Drill.finish(false)  # the quit path: abandon restores before saving
	check(Game.all_devices().size() == pre_devs and during != pre_devs,
		"drill: abandoning restores the real datacenter")

	print("---- %d failures" % fails)
	return fails
