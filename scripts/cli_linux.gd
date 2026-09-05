class_name LinuxCLI
extends CLI.Session
## The shell on a PacketLinux server: iproute2, iputils, tcpdump, the ISC
## DHCP pair, the resolver files, wireguard-tools and systemd's front doors,
## in the shapes a Debian box prints them. What is learned here works on a
## real host. The game-only verbs (vm, cert, aaad, ...) are kept apart in
## help so nobody memorises them as Linux.

const KERNEL := "6.1.0-18-amd64"

func banner() -> String:
	return "Welcome to PacketLinux. Try 'ip addr', 'ip route', 'ping -c 3 <ip>', 'help'.\n"

func prompt() -> String:
	return "root@%s:~#" % dev.name

func exec(line: String) -> String:
	# a pipe into grep, head, tail or wc filters the left side's output
	var pipe := line.find("|")
	if pipe > 0 and not line.begins_with("wg genkey"):
		var tail := Array(line.substr(pipe + 1).strip_edges().split(" ", false))
		var left := exec(line.substr(0, pipe).strip_edges())
		return _pipe(left, tail)
	var t := Array(line.strip_edges().split(" ", false))
	if t.is_empty():
		return ""
	if String(t[0]) == "sudo":
		t = t.slice(1)
		if t.is_empty():
			return "usage: sudo -h | -K | -k | -V\nusage: sudo -v [-ABkNnS] [-g group] [-h host] [-p prompt] [-u user]\nusage: sudo -l [-ABkNnS] [-g group] [-h host] [-p prompt] [-U user] [-u user] [command [arg ...]]\nusage: sudo [-ABbEHkNnPS] [-r role] [-t type] [-C num] [-D directory] [-g group] [-h host] [-p prompt] [-R directory] [-T timeout] [-u user] [VAR=value] [-i | -s] [command [arg ...]]\nusage: sudo -e [-ABkNnS] [-r role] [-t type] [-C num] [-D directory] [-g group] [-h host] [-p prompt] [-R directory] [-T timeout] [-u user] file ...\n"
	# the one shell redirect a network engineer types: writing a config file
	if ">" in t or ">>" in t:
		if String(t[0]) == "wg" and "genkey" in t:
			return _wg(["genkey", "|"])
		return _redirect(t)
	match String(t[0]):
		"help":
			return _help()
		"hostname":
			if t.size() == 1:
				return dev.name + "\n"
			return "" if Game.rename_device(dev, t[1]) else "hostname: the specified hostname is invalid\n"
		"hostnamectl":
			if t.size() >= 3 and String(t[1]) == "set-hostname":
				return "" if Game.rename_device(dev, String(t[2])) else "Could not set static hostname: Invalid argument\n"
			return "   Static hostname: %s\n         Icon name: computer-server\n           Chassis: server\n        Machine ID: 8c5e2d1f4a3b4c6d9e0f1a2b3c4d5e6f\n           Boot ID: 1a2b3c4d5e6f4a7b8c9d0e1f2a3b4c5d\n  Operating System: Debian GNU/Linux 12 (bookworm)\n            Kernel: Linux %s\n      Architecture: x86-64\n" % [dev.name, KERNEL]
		"uname":
			if "-a" in t:
				return "Linux %s %s #1 SMP PREEMPT_DYNAMIC Debian 6.1.76-1 (2024-02-01) x86_64 GNU/Linux\n" % [dev.name, KERNEL]
			if "-r" in t:
				return KERNEL + "\n"
			return "Linux\n"
		"pwd":
			return "/root\n"
		"whoami":
			return "root\n"
		"id":
			return "uid=0(root) gid=0(root) groups=0(root)\n"
		"date":
			return _when() + "\n"
		"which":
			return ("/usr/sbin/%s\n" % t[1]) if t.size() > 1 and String(t[1]) in ["ip", "tcpdump", "dhclient", "dhcpd", "ss", "sysctl", "wg", "nft"] else (("/usr/bin/%s\n" % t[1]) if t.size() > 1 and String(t[1]) in ["ping", "traceroute", "dig", "host", "nslookup", "curl", "nc", "ssh", "cat", "echo", "grep", "systemctl", "journalctl", "hostnamectl"] else "")
		"cd":
			return "" if t.size() == 1 or String(t[1]) in ["/", "~", "/root", "/etc", "/etc/dhcp", "/var/log", "/etc/wireguard", ".."] else "-bash: cd: %s: No such file or directory\n" % t[1]
		"grep", "less", "tail", "head":
			if t.size() >= 2 and String(t[-1]).begins_with("/"):
				var text := _cat([String(t[-1])])
				return _pipe(text, t.slice(0, t.size() - 1)) if String(t[0]) != "less" else text
			return "Usage: %s [OPTION]... [FILE]...\n" % t[0]
		"nano", "vi", "vim", "apt", "apt-get":
			return "-bash: %s: command not found\n# this shell has no editor or package manager: write a file with echo ... > /path (a game limitation, not Linux)\n" % t[0]
		"ls":
			var path := ""
			for a in t.slice(1):
				if not String(a).begins_with("-"):
					path = String(a)
			match path:
				"/etc/dhcp":
					return "dhclient.conf  dhclient-enter-hooks.d  dhclient-exit-hooks.d%s\n" % ("  dhcpd.conf" if dev.services.has("dhcp") else "")
				"/etc/wireguard":
					var confs: Array = dev.ifaces.filter(func(i): return i.name.begins_with("wg")).map(func(i): return i.name + ".conf")
					return ("  ".join(PackedStringArray(confs)) + "\n") if not confs.is_empty() else ""
				"/var/log":
					return "auth.log  btmp  daemon.log  dpkg.log  kern.log  lastlog  messages  syslog  wtmp\n"
				"/etc":
					return "default  dhcp  hostname  hosts  network  resolv.conf  ssh  systemd  wireguard\n"
			var files: Array = []
			if dev.services.has("wg_keys"):
				files += ["privatekey", "publickey"]
			return ("  ".join(PackedStringArray(files)) + "\n") if not files.is_empty() else ""
		"echo":
			return " ".join(PackedStringArray(t.slice(1))).replace("\"", "").replace("'", "") + "\n"
		"man":
			return ("What manual page do you want?\nFor example, try 'man man'.\n" if t.size() == 1
				else "No manual entry for %s\n" % t[1])
		"clear":
			return ""
		"cat":
			return _cat(t.slice(1))
		"ping", "ping6":
			return _ping(t.slice(1), String(t[0]) == "ping6")
		"traceroute":
			var targets: Array = []
			var skip := false
			for a in t.slice(1):
				if skip:
					skip = false
					continue
				if String(a) in ["-m", "-q", "-w", "-p", "-i", "-f"]:
					skip = true
				elif not String(a).begins_with("-"):
					targets.append(a)
			if targets.is_empty():
				return "Usage:\n  traceroute [ -46dFITnreAUDV ] [ -f first_ttl ] [ -g gate,... ] [ -i device ] [ -m max_ttl ] [ -N squeries ] [ -p port ] [ -t tos ] [ -l flow_label ] [ -w MAX,HERE,NEAR ] [ -q nqueries ] [ -s src_addr ] [ -z sendwait ] [ --fwmark=num ] host [ packetlen ]\n"
			return CLI.fmt_traceroute(dev, String(targets[0]), "-n" in t)
		"tracepath":
			return _tracepath(t.slice(1))
		"mtr":
			return "mtr: this shell has no curses; use 'traceroute -n <host>' or 'tracepath <host>'\n"
		"ip":
			return _ip_cmd(t.slice(1))
		"ss", "netstat":
			if String(t[0]) == "netstat":
				return _apt_hint("netstat", "net-tools")
			return _ss(t.slice(1))
		"ifconfig", "route", "arp":
			return _apt_hint(String(t[0]), "net-tools")
		"sysctl":
			return _sysctl(t.slice(1))
		"systemctl":
			return _systemctl(t.slice(1))
		"journalctl":
			return _journalctl(t.slice(1))
		"dhclient":
			return _dhclient(t.slice(1))
		"dhcpd":
			return _dhcpd(t.slice(1))
		"subnet":
			return _dhcpd_conf_line(t)
		"resolvectl":
			return _resolvectl(t.slice(1))
		"nslookup":
			return _nslookup(t.slice(1))
		"dig":
			return _dig(t.slice(1))
		"host":
			if t.size() < 2:
				return "Usage: host [-aCdilrTvVw] [-c class] [-N ndots] [-t type] [-W time]\n            [-R number] [-m flag] [-p port] hostname [server]\n"
			if String(t[1]).is_valid_ip_address():
				var oct := String(t[1]).split(".")
				oct.reverse()
				var arpa := ".".join(oct) + ".in-addr.arpa"
				var pname := Sim.reverse_lookup(dev, String(t[1]))
				return ("%s domain name pointer %s.\n" % [arpa, pname]) if pname != "" else "Host %s not found: 3(NXDOMAIN)\n" % arpa
			var hip := Sim.resolve(dev, String(t[1]))
			if hip == "":
				return "Host %s not found: 3(NXDOMAIN)\n" % t[1]
			return "%s has address %s\n" % [t[1], hip]
		"getent":
			if t.size() == 3 and String(t[1]) == "hosts":
				var gip := Sim.resolve(dev, String(t[2]))
				return ("%-15s %s\n" % [gip, t[2]]) if gip != "" else ""
			return "Usage: getent [OPTION...] database [key ...]\n"
		"curl":
			return _curl(t.slice(1))
		"nc", "ncat":
			return _nc(t.slice(1))
		"telnet":
			return _telnet(t.slice(1))
		"iptables":
			return "Chain INPUT (policy ACCEPT 0 packets, 0 bytes)\n pkts bytes target     prot opt in     out     source               destination\n\nChain FORWARD (policy ACCEPT 0 packets, 0 bytes)\n pkts bytes target     prot opt in     out     source               destination\n\nChain OUTPUT (policy ACCEPT 0 packets, 0 bytes)\n pkts bytes target     prot opt in     out     source               destination\n"
		"nft":
			return "" if "list" in t else "nft: command requires an argument\n"
		"ufw":
			return "-bash: ufw: command not found\n"
		"wg":
			return _wg(t.slice(1))
		"wg-quick":
			if t.size() == 3 and String(t[1]) in ["up", "down"]:
				var wq := _iface(String(t[2]))
				if String(t[1]) == "up":
					if wq != null:
						return "wg-quick: `%s' already exists\n" % t[2]
					var conf: Dictionary = dev.services.get("wg_conf", {}).get(String(t[2]), {})
					if conf.is_empty():
						return "wg-quick: `/etc/wireguard/%s.conf' does not exist\n" % t[2]
					var made := Game.add_wireguard(dev, int(String(t[2]).trim_prefix("wg")))
					if made == null:
						return "wg-quick: `%s' could not be created\n" % t[2]
					for cidr in conf.get("address", []):
						Game.add_ip(made, String(cidr))
					for pr in conf.get("peers", []):
						_wg_add_peer(made, pr)
					Game.topology_changed.emit()
					return "[#] ip link add %s type wireguard\n[#] wg setconf %s /dev/fd/63\n[#] ip -4 address add %s dev %s\n[#] ip link set mtu 1420 up dev %s\n" % [t[2], t[2],
						" ".join(PackedStringArray(made.ips)), t[2], t[2]]
				if wq == null:
					return "wg-quick: `%s' is not a WireGuard interface\n" % t[2]
				dev.ifaces.erase(wq)
				Game.topology_changed.emit()
				return "[#] ip link delete dev %s\n" % t[2]
			return "Usage: wg-quick [ up | down | save | strip ] [ CONFIG_FILE | INTERFACE ]\n"
		"lldpcli":
			return _lldpcli()
		"chronyc":
			if dev.ntp_server == "":
				return "506 Cannot talk to daemon\n"
			return "MS Name/IP address         Stratum Poll Reach LastRx Last sample\n===============================================================================\n^* %-25s     2   6   377    12   +0.000ms[+0.000ms] +/-  1ms\n" % dev.ntp_server
		"timedatectl":
			return "               Local time: %s\n           Universal time: %s\n                 RTC time: n/a\n                Time zone: Europe/Budapest (CEST, +0200)\nSystem clock synchronized: %s\n              NTP service: %s\n          RTC in local TZ: no\n" % [
				Time.get_datetime_string_from_system(false, true), Time.get_datetime_string_from_system(true, true),
				"yes" if dev.ntp_server != "" else "no", "active" if dev.ntp_server != "" else "inactive"]
		"tcpdump":
			return _tcpdump(t.slice(1))
		"ssh":
			return CLI.try_ssh(self, t[1]) if t.size() == 2 else "usage: ssh [-46AaCfGgKkMNnqsTtVvXxYy] [-B bind_interface] [-b bind_address]\n           [-c cipher_spec] [-D [bind_address:]port] [-E log_file]\n           [-e escape_char] [-F configfile] [-I pkcs11] [-i identity_file]\n           [-J destination] [-L address] [-l login_name] [-m mac_spec]\n           [-O ctl_cmd] [-o option] [-P tag] [-p port] [-R address]\n           [-S ctl_path] [-W host:port] [-w local_tun[:remote_tun]]\n           destination [command [argument ...]]\n"
		"exit", "logout":
			wants_exit = true
			return ""
		# ---- game verbs: services this world has, spelled short ----
		"nameserver":
			if t.size() != 2 or not String(t[1]).is_valid_ip_address():
				return "usage: nameserver <ip>   (the real file is /etc/resolv.conf: echo nameserver <ip> > /etc/resolv.conf)\n"
			dev.resolver = t[1]
			Game.topology_changed.emit()
			return ""
		"vm":
			return _vm(t)
		"bond":
			return _bond(t)
		"autoconf":
			var ac_if: Net.Iface = _iface(String(t[1])) if t.size() > 1 else dev.ifaces[0]
			if ac_if == null:
				return "autoconf: no interface %s\n" % t[1]
			var res := Sim.slaac(dev, ac_if)
			if not bool(res["ok"]):
				return "autoconf: %s\n" % res["why"]
			return "%s: configured %s from a router advertisement by %s\n" \
				% [ac_if.name, res["address"], res["router"]]
		"cert":
			return _cert(t)
		"aaad":
			if t.size() >= 2 and t[1] == "off":
				dev.services.erase("aaa")
				Game.topology_changed.emit()
				return "aaa service stopped\n"
			if t.size() < 2:
				return "usage: aaad <shared-secret> | aaad off | aaad log\n"
			if t[1] == "log":
				var trail: Array = dev.services.get("aaa", {}).get("log", [])
				if trail.is_empty():
					return "(no administrative commands recorded)\n"
				var lout := ""
				for entry in trail:
					lout += "  %s\n" % entry
				return lout
			dev.services["aaa"] = {"key": String(t[1]),
				"log": dev.services.get("aaa", {}).get("log", [])}
			Game.topology_changed.emit()
			return "aaa service listening (shared secret set)\n"
		"snmpd":
			if t.size() >= 2 and t[1] == "off":
				dev.snmp = ""
				Game.topology_changed.emit()
				return "snmp agent stopped\n"
			if t.size() < 2:
				return "usage: snmpd <community> | snmpd off   (rocommunity <community> in /etc/snmp/snmpd.conf)\n"
			dev.snmp = String(t[1])
			Game.topology_changed.emit()
			return "snmp agent listening, community %s\n" % t[1]
		"flows":
			if dev.talkers.is_empty():
				return "no flows recorded (this host does not forward traffic)\n"
			var frows: Array = []
			for fk in dev.talkers:
				frows.append([String(fk), int(dev.talkers[fk])])
			frows.sort_custom(func(x, y): return int(x[1]) > int(y[1]))
			var fout := "%-38s %10s\n" % ["SOURCE > DESTINATION", "PACKETS"]
			for frow in frows.slice(0, 15):
				fout += "%-38s %10d\n" % [frow[0], frow[1]]
			return fout
		"console":
			return _console(t)
		"snmpwalk":
			return _snmpwalk(t.slice(1))
		"igmp":
			if t.size() == 3 and t[1] == "join":
				var err := Sim.igmp_join(dev, t[2])
				return "joined %s\n" % t[2] if err == "" else "igmp: %s\n" % err
			if t.size() == 3 and t[1] == "send":
				var got := Sim.mcast_send(dev, t[2])
				return "sent to %s: %d member(s) received it\n" % [t[2], got]
			if t.size() >= 2 and t[1] == "groups":
				return "%s\n" % ", ".join(PackedStringArray(dev.mcast_groups)) \
					if not dev.mcast_groups.is_empty() else "(no groups joined)\n"
			return "usage: igmp join <group> | igmp send <group> | igmp groups   (ip maddr show lists them)\n"
		"radiusd":
			if not dev.services.has("radius"):
				dev.services["radius"] = {"users": {}}
			if t.size() >= 3 and t[1] == "add":
				var vid := int(t[3]) if t.size() > 3 and String(t[3]).is_valid_int() else 0
				dev.services["radius"]["users"][t[2]] = vid
				Game.topology_changed.emit()
				return "radiusd: %s may join%s\n" % [t[2],
					" VLAN %d" % vid if vid > 0 else ""]
			if t.size() >= 2 and t[1] == "list":
				var users: Dictionary = dev.services["radius"]["users"]
				if users.is_empty():
					return "(nobody authorised yet)\n"
				var out := ""
				for u in users:
					out += "%-19s vlan %s\n" % [u, str(users[u]) if int(users[u]) > 0 else "-"]
				return out
			return "radiusd: collecting authentication requests\nusage: radiusd add <mac> [vlan] | radiusd list\n"
		"wifi", "nmcli":
			return _wifi(t)
		"syslogd":
			dev.services["syslog"] = dev.services.get("syslog", {"messages": []})
			return "syslogd: collecting logs on this host\n"
		"logging":
			if t.size() == 2 and (t[1].is_valid_ip_address() or Net.is_v6(t[1])):
				dev.log_host = t[1]
				return ""
			return "usage: logging <collector-ip>   (*.* @<ip> in /etc/rsyslog.d/remote.conf)\n"
		"ntpd":
			if t.size() == 2 and (t[1].is_valid_ip_address() or Net.is_v6(t[1])):
				dev.ntp_server = t[1]
				return "ntpd: syncing to %s\n" % t[1]
			return "usage: ntpd <server-ip>   (server <ip> iburst in /etc/chrony/chrony.conf)\n"
		"logs":
			return _journalctl([])
		"dns64":
			t = ["dns", "dns64"] + t.slice(1)
			return exec(" ".join(PackedStringArray(t)))
		"dns":
			return _dns(t)
		"lldp":
			var out := "%-8s %-14s %s\n" % ["Port", "Neighbor", "Neighbor Port"]
			var any := false
			for i: Net.Iface in dev.ifaces:
				var l := Game.link_at(i)
				if l:
					any = true
					out += "%-8s %-14s %s\n" % [i.name, l.other(i).dev.name, l.other(i).name]
			return out if any else "(no neighbors detected)\n"
	return "-bash: %s: command not found\n" % t[0]

func _pipe(text: String, tail: Array) -> String:
	## grep, grep -v, head, tail, wc -l: the filters people put after a command
	if tail.is_empty():
		return text
	var cmd := String(tail[0])
	var lines := Array(text.split("\n", false))
	match cmd:
		"grep", "egrep":
			var invert := "-v" in tail
			var needles: Array = tail.slice(1).filter(func(w): return not String(w).begins_with("-"))
			if needles.is_empty():
				return "Usage: grep [OPTION]... PATTERNS [FILE]...\nTry 'grep --help' for more information.\n"
			var needle := String(needles[0]).replace("\"", "").replace("'", "")
			var out := ""
			for l in lines:
				var hit := needle in String(l) if "-i" not in tail else needle.to_lower() in String(l).to_lower()
				if hit != invert:
					out += String(l) + "\n"
			return out
		"head", "tail":
			var n := 10
			for k in tail.size():
				if String(tail[k]) == "-n" and k + 1 < tail.size():
					n = int(tail[k + 1])
				elif String(tail[k]).begins_with("-") and String(tail[k]).substr(1).is_valid_int():
					n = int(String(tail[k]).substr(1))
			var picked: Array = lines.slice(0, n) if cmd == "head" else lines.slice(maxi(0, lines.size() - n))
			return ("\n".join(PackedStringArray(picked)) + "\n") if not picked.is_empty() else ""
		"wc":
			if "-l" in tail:
				return "%d\n" % lines.size()
			var words := 0
			for l in lines:
				words += String(l).split(" ", false).size()
			return "%7d %7d %7d\n" % [lines.size(), words, text.length()]
		"less", "more", "cat":
			return text
	return "-bash: %s: command not found\n" % cmd

func _help() -> String:
	return ("Linux tools (they work the same on a real host):\n"
		+ "  ip addr [show|add <cidr> dev <if>|del ...]   ip link set <if> up|down   ip -br addr\n"
		+ "  ip route [show|get <ip>|add default via <gw>|del ...]   ip -6 route   ip neigh\n"
		+ "  ping -c 3 <host>   traceroute -n <host>   tracepath <host>   tcpdump -i eth0 -n [icmp|arp|port 53]\n"
		+ "  nslookup <name>   dig <name>   host <name>   cat /etc/resolv.conf   resolvectl status\n"
		+ "  dhclient -v eth0   dhclient -r eth0   cat /etc/dhcp/dhcpd.conf   systemctl start isc-dhcp-server\n"
		+ "  journalctl -u isc-dhcp-server   cat /var/lib/dhcp/dhcpd.leases   ss -tlnp   sysctl net.ipv4.ip_forward\n"
		+ "  wg genkey   ip link add wg0 type wireguard   wg set wg0 ...   wg show   lldpcli show neighbors\n"
		+ "  hostname   hostnamectl   uname -a   curl <url>   nc -zv <host> <port>   ssh <host>   exit\n"
		+ "\nGame-only verbs (this world's services, spelled short; not Linux commands):\n"
		+ "  subnet ... { ... }   paste a dhcpd.conf subnet block on one line\n"
		+ "  dhcpd <if> <first> <last> <plen> [gw] [dns]   shorthand for the block above\n"
		+ "  dns add <name> <ip> [ttl] | dns delegate <zone> <ns> | dns list | dns64 <prefix>   host records\n"
		+ "  vm create|addr|migrate|list   bond <if> <if>   autoconf <if>   cert issue|renew|auto|list\n"
		+ "  aaad <secret>   radiusd add <mac> [vlan]   snmpd <community>   snmpwalk <addr> <community>\n"
		+ "  igmp join|send|groups   wifi join|leave|status   console list|<device>   flows   logs\n"
		+ "  syslogd   logging <ip>   ntpd <ip>   nameserver <ip>\n")

func _apt_hint(cmd: String, _pkg: String) -> String:
	## Debian has no command-not-found handler: net-tools is simply absent
	return "-bash: %s: command not found\n" % cmd

func _iface(name: String) -> Net.Iface:
	for i: Net.Iface in dev.ifaces:
		if i.name == name:
			return i
	return null

func _up(i: Net.Iface) -> bool:
	return i.enabled and Game.link_at(i) != null

func _fe80(i: Net.Iface) -> String:
	return Net.v6_compress("fe80::%s" % Net.eui64(i.mac))

func _first_v4() -> String:
	for i: Net.Iface in dev.ifaces:
		for cidr in i.ips:
			if not Net.is_v6(cidr):
				return String(cidr).split("/")[0]
	return "0.0.0.0"

func _on_link(gw: String) -> Net.Iface:
	## the interface whose subnet holds the gateway, or null
	for i: Net.Iface in dev.ifaces:
		for cidr in i.ips:
			if Net.is_v6(cidr) != Net.is_v6(gw):
				continue
			if Net.same_net(gw, String(cidr).split("/")[0], int(String(cidr).split("/")[1])):
				return i
	return null

static func _kv(args: Array) -> Dictionary:
	## iproute2 grammar: keywords followed by a value, plus bare words
	var out := {"_": []}
	var k := 0
	while k < args.size():
		var w := String(args[k])
		if w in ["dev", "via", "mtu", "src", "metric", "table", "type", "master", "brd", "scope", "proto"] and k + 1 < args.size():
			out[w] = String(args[k + 1])
			k += 2
		else:
			out["_"].append(w)
			k += 1
	return out

# ---------- ip ----------

func _ip_cmd(args: Array) -> String:
	var family := 0
	var brief := false
	var stats := false
	while not args.is_empty() and String(args[0]).begins_with("-"):
		match String(args[0]):
			"-4":
				family = 4
			"-6":
				family = 6
			"-br", "-brief":
				brief = true
			"-s", "-stats", "-statistics":
				stats = true
			"-c", "-color", "-n", "-numeric", "-d", "-details":
				pass
			_:
				return "Option \"%s\" is unknown, try \"ip -help\".\n" % args[0]
		args = args.slice(1)
	if args.is_empty():
		return "Usage: ip [ OPTIONS ] OBJECT { COMMAND | help }\n       ip [ -force ] -batch filename\nwhere  OBJECT := { address | addrlabel | fou | help | ila | l2tp | link |\n                   macsec | maddress | monitor | mptcp | mroute | mrule |\n                   neighbor | neighbour | netconf | netns | nexthop | ntable |\n                   ntbl | route | rule | sr | tap | tcpmetrics |\n                   token | tunnel | tuntap | vrf | xdp }\n       OPTIONS := { -V[ersion] | -s[tatistics] | -d[etails] | -r[esolve] |\n                    -h[uman-readable] | -iec | -j[son] | -p[retty] |\n                    -f[amily] { inet | inet6 | mpls | bridge | link } |\n                    -4 | -6 | -M | -B | -0 |\n                    -l[oops] { maximum-addr-flush-attempts } | -br[ief] |\n                    -o[neline] | -t[imestamp] | -ts[hort] | -b[atch] [filename] |\n                    -rc[vbuf] [size] | -n[etns] name | -N[umeric] | -a[ll] |\n                    -c[olor]}\n"
	var obj := String(args[0])
	var rest: Array = args.slice(1)
	if obj.begins_with("a") and not obj.begins_with("addrl"):
		return _ip_addr(rest, family, brief)
	if obj.begins_with("l"):
		return _ip_link(rest, brief, stats)
	if obj.begins_with("n"):
		return _ip_neigh(rest, family)
	if obj.begins_with("r"):
		return _ip_route(rest, family)
	if obj.begins_with("m"):
		return _ip_maddr()
	if obj == "help":
		return _ip_cmd([])
	return "Object \"%s\" is unknown, try \"ip help\".\n" % obj

func _addr_block(i: Net.Iface, n: int, family: int, link_only: bool) -> String:
	if i.name.begins_with("wg"):
		var wout := "%d: %s: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN%s group default qlen 1000\n    link/none \n" % [n, i.name, " mode DEFAULT" if link_only else ""]
		if not link_only:
			for cidr in i.ips:
				if family != 6 and not Net.is_v6(cidr):
					wout += "    inet %s scope global %s\n       valid_lft forever preferred_lft forever\n" % [cidr, i.name]
		return wout
	var out := "%d: %s: <%s> mtu %d qdisc fq_codel state %s%s group default qlen 1000\n    link/ether %s brd ff:ff:ff:ff:ff:ff\n" % [
		n, i.name, _link_flags(i), i.mtu, "UP" if _up(i) else "DOWN", " mode DEFAULT" if link_only else "", i.mac.to_lower()]
	if link_only:
		return out
	for cidr in i.ips:
		if Net.is_v6(cidr):
			if family != 4:
				out += "    inet6 %s scope global\n       valid_lft forever preferred_lft forever\n" % cidr
		elif family != 6:
			var lease: Dictionary = dev.services.get("dhcp_lease", {})
			var dyn: bool = String(lease.get("cidr", "")) == String(cidr)
			var brd: String = (" brd %s" % _bcast(cidr)) if dyn or String(cidr) in dev.services.get("brd", []) else ""
			out += "    inet %s%s scope global%s %s\n       valid_lft %s preferred_lft %s\n" % [cidr, brd, " dynamic" if dyn else "", i.name,
				"1789sec" if dyn else "forever", "1789sec" if dyn else "forever"]
	if family != 4 and _up(i) and not i.name.begins_with("wg"):
		out += "    inet6 %s/64 scope link\n       valid_lft forever preferred_lft forever\n" % _fe80(i)
	return out

func _lo_block(family: int, link_only: bool) -> String:
	var out := "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN%s group default qlen 1000\n    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00\n" % (" mode DEFAULT" if link_only else "")
	if link_only:
		return out
	if family != 6:
		out += "    inet 127.0.0.1/8 scope host lo\n       valid_lft forever preferred_lft forever\n"
	if family != 4:
		out += "    inet6 ::1/128 scope host noprefixroute\n       valid_lft forever preferred_lft forever\n"
	return out

func _ip_addr(rest: Array, family: int, brief: bool) -> String:
	var kv := _kv(rest)
	var words: Array = kv["_"]
	var verb := String(words[0]) if not words.is_empty() else "show"
	if verb in ["show", "list", "ls", "s", "sh", "l"] or verb.begins_with("s") and verb != "set":
		var only := String(kv.get("dev", words[1] if words.size() > 1 else ""))
		if only != "" and only != "lo" and _iface(only) == null:
			return "Device \"%s\" does not exist.\n" % only
		if brief:
			var out := ""
			if only == "" or only == "lo":
				out += "%-16s %-14s %s\n" % ["lo", "UNKNOWN", " ".join(PackedStringArray(
					([] if family == 6 else ["127.0.0.1/8"]) + ([] if family == 4 else ["::1/128"])))]
			for i: Net.Iface in dev.ifaces:
				if only != "" and i.name != only:
					continue
				var addrs: Array = []
				for cidr in i.ips:
					if (family == 4 and Net.is_v6(cidr)) or (family == 6 and not Net.is_v6(cidr)):
						continue
					addrs.append(cidr)
				if family != 4 and _up(i) and not i.name.begins_with("wg"):
					addrs.append(_fe80(i) + "/64")
				out += "%-16s %-14s %s\n" % [i.name, "UNKNOWN" if i.name.begins_with("wg") else ("UP" if _up(i) else "DOWN"), " ".join(PackedStringArray(addrs))]
			return out
		var out := ""
		if only == "" or only == "lo":
			out += _lo_block(family, false)
		var n := 2
		for i: Net.Iface in dev.ifaces:
			if only == "" or i.name == only:
				out += _addr_block(i, n, family, false)
			n += 1
		return out
	if verb in ["add", "del", "delete", "a", "d", "replace"]:
		var cidr := String(words[1]) if words.size() > 1 else ""
		if cidr == "":
			return "Command line is not complete. Try option \"help\"\n"
		if not kv.has("dev"):
			return "Not enough information: \"dev\" argument is required.\n"
		var ifc := _iface(String(kv["dev"]))
		if ifc == null:
			return "Cannot find device \"%s\"\n" % kv["dev"]
		if "/" not in cidr and cidr.is_valid_ip_address():
			cidr += "/128" if Net.is_v6(cidr) else "/32"  # the classic trap: no length means a host route
		if not Net.valid_cidr(cidr):
			return "Error: any valid prefix is expected rather than \"%s\".\n" % cidr
		if verb.begins_with("a") or verb == "replace":
			if cidr in ifc.ips:
				return "" if verb == "replace" else "RTNETLINK answers: File exists\n"
			if not Game.add_ip(ifc, cidr):
				return "RTNETLINK answers: File exists\n"
			if kv.has("brd") or "brd" in words:
				var brds: Array = dev.services.get("brd", [])
				brds.append(cidr)
				dev.services["brd"] = brds
			return ""
		if cidr in ifc.ips:
			Game.remove_ip(ifc, cidr)
			return ""
		return "RTNETLINK answers: Cannot assign requested address\n"
	if verb == "flush":
		var ifc := _iface(String(kv.get("dev", "")))
		if ifc == null:
			return "Flush requires arguments.\n" if not kv.has("dev") else "Cannot find device \"%s\"\n" % kv["dev"]
		for cidr in ifc.ips.duplicate():
			Game.remove_ip(ifc, cidr)
		return ""
	return "Command \"%s\" is unknown, try \"ip address help\".\n" % verb

func _ip_link(rest: Array, brief: bool, stats: bool) -> String:
	var kv := _kv(rest)
	var words: Array = kv["_"]
	var verb := String(words[0]) if not words.is_empty() else "show"
	if verb in ["show", "list", "ls", "s", "sh", "l"]:
		var only := String(kv.get("dev", words[1] if words.size() > 1 else ""))
		if brief:
			var out := "%-16s %-14s %-18s <LOOPBACK,UP,LOWER_UP>\n" % ["lo", "UNKNOWN", "00:00:00:00:00:00"]
			for i: Net.Iface in dev.ifaces:
				if only == "" or i.name == only:
					out += "%-16s %-14s %-18s <%s>\n" % [i.name, "UP" if _up(i) else "DOWN", i.mac.to_lower(), _link_flags(i)]
			return out
		var out := _lo_block(0, true) if only == "" else ""
		if stats and only == "":
			out += "    RX:  bytes packets errors dropped  missed   mcast\n              0       0      0       0       0       0\n    TX:  bytes packets errors dropped carrier collsns\n              0       0      0       0       0       0\n"
		var n := 2
		for i: Net.Iface in dev.ifaces:
			if only == "" or i.name == only:
				out += _addr_block(i, n, 0, true)
				if stats:
					out += "    RX:  bytes packets errors dropped  missed   mcast\n    %10d %7d %6d %7d %7d %7d\n    TX:  bytes packets errors dropped carrier collsns\n    %10d %7d %6d %7d %7d %7d\n" % [
						i.rx_frames * 148, i.rx_frames, i.rx_errors, 0, 0, 0, i.tx_frames * 148, i.tx_frames, 0, i.out_drops, 0, 0]
			n += 1
		if only != "" and out == "":
			return "Device \"%s\" does not exist.\n" % only
		return out
	if verb == "set":
		var name := String(kv.get("dev", words[1] if words.size() > 1 else ""))
		var ifc := _iface(name)
		if ifc == null:
			return "Cannot find device \"%s\"\n" % name
		if kv.has("mtu"):
			if not String(kv["mtu"]).is_valid_int() or int(kv["mtu"]) < 68:
				return "Error: argument \"%s\" is wrong: Invalid \"mtu\" value\n" % kv["mtu"]
			ifc.mtu = clampi(int(kv["mtu"]), 68, 9216)
		if "up" in words:
			ifc.enabled = ifc.fault == ""
			ifc.admin_down = false
		elif "down" in words:
			ifc.enabled = false
			ifc.admin_down = true
		if kv.has("master"):
			return _enslave(ifc, String(kv["master"]))
		Game.topology_changed.emit()
		return ""
	if verb == "add":
		var name := String(kv.get("dev", words[1] if words.size() > 1 else ""))
		if String(kv.get("type", "")) == "wireguard":
			if not (name.begins_with("wg") and name.trim_prefix("wg").is_valid_int()):
				return "RTNETLINK answers: Operation not supported\n"
			if _iface(name) != null:
				return "RTNETLINK answers: File exists\n"
			return "" if Game.add_wireguard(dev, int(name.trim_prefix("wg"))) != null else "RTNETLINK answers: Operation not supported\n"
		if String(kv.get("type", "")) == "bond":
			dev.services["bond_pending"] = name
			return ""
		return "RTNETLINK answers: Operation not supported\n"
	if verb in ["del", "delete"]:
		var name := String(kv.get("dev", words[1] if words.size() > 1 else ""))
		var ifc := _iface(name)
		if ifc == null:
			return "Cannot find device \"%s\"\n" % name
		if not name.begins_with("wg"):
			return "RTNETLINK answers: Operation not supported\n"
		dev.ifaces.erase(ifc)
		Game.topology_changed.emit()
		return ""
	return "Command \"%s\" is unknown, try \"ip link help\".\n" % verb

func _enslave(ifc: Net.Iface, master: String) -> String:
	## ip link set eth1 master bond0: the bond is whatever ports share it
	if ifc.enabled and not ifc.admin_down:
		return "Error: Device can not be enslaved while up.\n"
	var gid := 1
	var first: Net.Iface = null
	for i2: Net.Iface in dev.ifaces:
		if i2.lag > 0 and i2 != ifc:
			gid = i2.lag
			first = i2
	if first == null:
		for i2: Net.Iface in dev.ifaces:
			gid = maxi(gid, i2.lag + 1)
	ifc.lag = gid
	if first != null:
		ifc.mac = first.mac  # a bond presents one address
	dev.services.erase("bond_pending")
	Game.topology_changed.emit()
	return ""

func _ip_neigh(rest: Array, family: int) -> String:
	var kv := _kv(rest)
	var words: Array = kv["_"]
	var verb := String(words[0]) if not words.is_empty() else "show"
	if verb == "flush":
		if "all" not in words and not kv.has("dev"):
			return "Flush requires arguments.\n"
		dev.arp.clear()
		return ""
	if verb in ["show", "list", "ls", "s", "sh"]:
		var out := ""
		for ip in dev.services.get("arp_failed", []):
			if not dev.arp.has(ip):
				out += "%s dev %s FAILED\n" % [ip, dev.ifaces[0].name if not dev.ifaces.is_empty() else "eth0"]
		for ip in dev.arp:
			if (family == 4 and Net.is_v6(String(ip))) or (family == 6 and not Net.is_v6(String(ip))):
				continue
			var ifn := CLI.arp_iface_name(dev, String(ip))
			if kv.has("dev") and String(kv["dev"]) != ifn:
				continue
			var seen := int(dev.arp_seen.get(ip, dev.arp_seen.get("%s|" % ip, Game.cycle)))
			out += "%s dev %s lladdr %s %s\n" % [ip, ifn, String(dev.arp[ip]).to_lower(),
				"REACHABLE" if Game.cycle - seen <= 0 else "STALE"]
		return out
	return "Command \"%s\" is unknown, try \"ip neigh help\".\n" % verb

func _ip_maddr() -> String:
	var out := "1:\tlo\n\tinet  224.0.0.1\n\tinet6 ff02::1\n\tinet6 ff01::1\n"
	var n := 2
	for i: Net.Iface in dev.ifaces:
		out += "%d:\t%s\n\tlink  01:00:5e:00:00:01\n\tinet  224.0.0.1\n" % [n, i.name]
		for g in dev.mcast_groups:
			out += "\tinet  %s\n" % g
		out += "\tinet6 ff02::1\n\tinet6 ff01::1\n"
		n += 1
	return out

func _route_line(r: Dictionary, v6: bool) -> String:
	var dst := "default" if int(r["plen"]) == 0 else "%s/%d" % [r["prefix"], int(r["plen"])]
	if String(r.get("via", "")) == "":
		return "%s dev %s scope link\n" % [dst, r.get("dev", "eth0")]
	var egress := Sim._connected_iface(dev, String(r["via"]))
	var line := "%s via %s%s" % [dst, r["via"], CLI.dev_suffix(dev, String(r["via"]))]
	if v6:
		line += " metric 1024 pref medium"
	if egress != null and Game.link_at(egress) == null:
		line += " linkdown"
	return line + "\n"

func _ip_route_show(family: int) -> String:
	## the kernel's order: default first, then by prefix; a route through a
	## downed interface is gone, one through a dead cable says linkdown
	var v6 := family == 6
	var rows: Array = []
	if v6:
		rows.append(["::1", "::1 dev lo proto kernel metric 256 pref medium\n"])
	for r in dev.static_routes:
		if String(r.get("vrf", "")) != "":
			continue
		var via := String(r.get("via", ""))
		if via != "" and Net.is_v6(via) != v6:
			continue
		if via == "" and Net.is_v6(String(r["prefix"])) != v6:
			continue
		var egress := Sim._connected_iface(dev, via) if via != "" else _iface(String(r.get("dev", "")))
		if egress != null and not egress.enabled:
			continue
		var key := ("~" if v6 else "") + ("" if int(r["plen"]) == 0 else String(r["prefix"]))
		if v6 and int(r["plen"]) == 0:
			key = "~~~"  # v6 default last
		rows.append([key, _route_line(r, v6)])
	for i: Net.Iface in dev.ifaces:
		if not i.enabled:
			continue
		for cidr: String in i.ips:
			if Net.is_v6(cidr) != v6:
				continue
			var netw := Net.network_of(cidr)
			var down := " linkdown" if Game.link_at(i) == null and not i.name.begins_with("wg") else ""
			if v6:
				rows.append([String(netw["prefix"]), "%s/%d dev %s proto kernel metric 256 pref medium%s\n" % [netw["prefix"], int(netw["plen"]), i.name, down]])
			else:
				rows.append([String(netw["prefix"]), "%s/%d dev %s proto kernel scope link src %s%s\n" % [netw["prefix"], int(netw["plen"]), i.name, String(cidr).split("/")[0], down]])
		if v6 and _up(i) and not i.name.begins_with("wg"):
			rows.append(["fe80::", "fe80::/64 dev %s proto kernel metric 256 pref medium\n" % i.name])
	rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	var out := ""
	for row in rows:
		out += String(row[1])
	return out

func _ip_route(rest: Array, family: int) -> String:
	var kv := _kv(rest)
	var words: Array = kv["_"]
	var verb := String(words[0]) if not words.is_empty() else "show"
	if verb in ["show", "list", "ls", "s", "sh", "l"]:
		if kv.has("table") and String(kv["table"]) not in ["main", "254", "all"]:
			return ""
		return _ip_route_show(family)
	if verb == "get":
		if words.size() < 2:
			return "Command line is not complete. Try option \"help\"\n"
		var target := String(words[1])
		if not target.is_valid_ip_address():
			return "Error: any valid address is expected rather than \"%s\".\n" % target
		var ip := target
		var best := {}
		for e in Sim.rib(dev):
			if String(e["vrf"]) != "" or Net.is_v6(String(e["prefix"])) != Net.is_v6(ip):
				continue
			if Net.same_net(ip, String(e["prefix"]), int(e["plen"])) and (best.is_empty() or int(e["plen"]) > int(best["plen"])):
				best = e
		if best.is_empty():
			return "RTNETLINK answers: Network is unreachable\n"
		var egress: Net.Iface = best["iface"]
		var src := Sim._first_ip(egress, Net.is_v6(ip)) if egress != null else _first_v4()
		if best["src"] == "C":
			return "%s dev %s src %s uid 0\n    cache\n" % [ip, egress.name, src]
		return "%s via %s dev %s src %s uid 0\n    cache\n" % [ip, best["next_hop"], egress.name if egress != null else "?", src]
	if verb in ["add", "replace", "append", "change"]:
		if words.size() < 2:
			return "Command line is not complete. Try option \"help\"\n"
		var dst := String(words[1])
		var v6 := family == 6 or (kv.has("via") and Net.is_v6(String(kv["via"])))
		var pfx := ("::/0" if v6 else "0.0.0.0/0") if dst == "default" else dst
		if "/" not in pfx and pfx.is_valid_ip_address():
			pfx += "/128" if Net.is_v6(pfx) else "/32"
		if not Net.valid_cidr(pfx):
			return "Error: any valid prefix is expected rather than \"%s\".\n" % dst
		if not kv.has("via"):
			if not kv.has("dev"):
				return "RTNETLINK answers: No such device\n"
			var onlink := _iface(String(kv["dev"]))
			if onlink == null:
				return "Cannot find device \"%s\"\n" % kv["dev"]
			# an on-link route: the prefix is reachable through the wire itself
			var parts0 := pfx.split("/")
			for r in dev.static_routes:
				if String(r["prefix"]) == parts0[0] and int(r["plen"]) == int(parts0[1]) and String(r.get("vrf", "")) == "":
					if verb == "add":
						return "RTNETLINK answers: File exists\n"
					Game.remove_static_route(dev, parts0[0], int(parts0[1]))
			dev.static_routes.append({"prefix": parts0[0], "plen": int(parts0[1]), "via": "", "ad": 1, "dev": onlink.name})
			Game.topology_changed.emit()
			return ""
		var gw := String(kv["via"])
		if not gw.is_valid_ip_address():
			return "Error: any valid address is expected rather than \"%s\".\n" % gw
		var egress := _on_link(gw)
		if egress == null:
			return "Error: Nexthop has invalid gateway.\n"
		if kv.has("dev") and String(kv["dev"]) != egress.name:
			return "Error: Nexthop has invalid gateway.\n" if _iface(String(kv["dev"])) != null else "Cannot find device \"%s\"\n" % kv["dev"]
		var parts := pfx.split("/")
		for r in dev.static_routes:
			if String(r["prefix"]) == parts[0] and int(r["plen"]) == int(parts[1]) and String(r.get("vrf", "")) == "":
				if verb == "add" or verb == "append":
					return "RTNETLINK answers: File exists\n"
				Game.remove_static_route(dev, parts[0], int(parts[1]))
				break
		return "" if Game.add_static_route(dev, parts[0], int(parts[1]), gw) else "RTNETLINK answers: Invalid argument\n"
	if verb in ["del", "delete", "d"]:
		if words.size() < 2:
			return "Command line is not complete. Try option \"help\"\n"
		var dst := String(words[1])
		var pfx := ("::/0" if family == 6 else "0.0.0.0/0") if dst == "default" else dst
		if "/" not in pfx and pfx.is_valid_ip_address():
			pfx += "/128" if Net.is_v6(pfx) else "/32"
		if not Net.valid_cidr(pfx):
			return "Error: any valid prefix is expected rather than \"%s\".\n" % dst
		var parts := pfx.split("/")
		for r in dev.static_routes:
			if String(r["prefix"]) == parts[0] and int(r["plen"]) == int(parts[1]) \
					and (not kv.has("via") or String(kv["via"]) == String(r["via"])):
				Game.remove_static_route(dev, parts[0], int(parts[1]))
				return ""
		return "RTNETLINK answers: No such process\n"
	if verb == "flush":
		for r in dev.static_routes.duplicate():
			Game.remove_static_route(dev, String(r["prefix"]), int(r["plen"]))
		return ""
	return "Command \"%s\" is unknown, try \"ip route help\".\n" % verb

func _link_flags(i: Net.Iface) -> String:
	if not i.enabled:
		return "BROADCAST,MULTICAST"
	if Game.link_at(i) == null:
		return "NO-CARRIER,BROADCAST,MULTICAST,UP"
	return "BROADCAST,MULTICAST,UP,LOWER_UP"

func _bcast(cidr: String) -> String:
	var parts := cidr.split("/")
	var plen := int(parts[1])
	var host_bits := 32 - plen
	return Net.int_to_ip((Net.ip_to_int(parts[0]) | ((1 << host_bits) - 1)) & 0xFFFFFFFF) if plen < 32 else parts[0]

# ---------- ping, traceroute ----------

func _ping(args: Array, force6: bool) -> String:
	var count := 3  # no Ctrl-C in this terminal, so a bare ping behaves like -c 3
	var payload := 56
	var df := false
	var v6 := force6
	var target := ""
	var k := 0
	while k < args.size():
		var a := String(args[k])
		match a:
			"-c", "-s", "-W", "-i", "-I", "-w", "-t", "-l", "-M", "-Q":
				var v := String(args[k + 1]) if k + 1 < args.size() else ""
				if a == "-c":
					if not v.is_valid_int() or int(v) < 1:
						return "ping: invalid argument: '%s': out of range: 1 <= value <= 9223372036854775807\n" % v
					count = clampi(int(v), 1, 20)
				elif a == "-s":
					if not v.is_valid_int() or int(v) < 0:
						return "ping: invalid argument: '%s'\n" % v
					payload = int(v)
				elif a == "-M":
					if v not in ["do", "dont", "want", "probe"]:
						return "ping: invalid -M argument: %s\n" % v
					df = v == "do"
				elif a == "-I" and _iface(v) == null and not v.is_valid_ip_address():
					return "ping: %s: No such device\n" % v
				k += 2
				continue
			"-6":
				v6 = true
			"-4":
				v6 = false
			"-n", "-q", "-v", "-D", "-O", "-b", "-f", "-A", "-a", "-U", "-d", "-R":
				pass
			_:
				if a.begins_with("-"):
					return "ping: invalid option -- '%s'\n" % a.trim_prefix("-")
				target = a
		k += 1
	if target == "":
		return "ping: usage error: Destination address required\n"
	var ip := Sim.resolve(dev, target, true, v6)
	if ip == "" and (target.is_valid_ip_address()):
		ip = target
	if ip == "":
		return "ping: %s: Name or service not known\n" % target
	var reply_bytes := payload + 8
	var from_if := ""
	for k2 in args.size():
		if String(args[k2]) == "-I" and k2 + 1 < args.size():
			from_if = String(args[k2 + 1])
	var out := "PING %s (%s) %s%d(%d) bytes of data.\n" % [target, ip,
		("from %s %s: " % [Sim._first_ip(_iface(from_if)) if _iface(from_if) != null else from_if, from_if]) if from_if != "" else "", payload, payload + 28]
	var rname := Sim.reverse_lookup(dev, ip) if "-n" not in args else ""
	var received := 0
	var errors := 0
	var rtts: Array = []
	var run_id := Sim.next_echo_id()
	for seq in count:
		var r := Sim.ping(dev, ip, 64, "", reply_bytes, run_id, seq + 1)
		var detail := String(r.get("detail", ""))
		var frag_line := ""
		if not bool(r["ok"]) and detail.begins_with("dropped:"):
			# "dropped: N bytes will not fit the M byte MTU on DEV PORT": who
			# dropped it decides what, if anything, comes back
			var words := detail.split(" ")
			var mtu := int(words[7]) if words.size() > 7 else 1500
			var who := String(words[11]) if words.size() > 11 else dev.name
			var who_type := _device_type(who)
			if who == dev.name:
				if df:
					frag_line = "ping: local error: message too long, mtu=%d\n" % mtu
				else:
					r = Sim.ping(dev, ip, 64, "", 64)  # the kernel fragments to its own MTU
					detail = String(r.get("detail", ""))
			elif who_type in ["router", "firewall", "server", "loadbalancer"]:
				if df:
					frag_line = "From %s icmp_seq=%d Frag needed and DF set (mtu = %d)\n" % [_device_ip(who), seq + 1, mtu]
				else:
					r = Sim.ping(dev, ip, 64, "", 64)  # a router fragments what it may
					detail = String(r.get("detail", ""))
			else:
				detail = "timeout"  # a switch says nothing: the frame is simply gone
		if bool(r["ok"]):
			received += 1
			var rtt := maxf(0.04, float(r.get("rtt", 0.1))) * (1.0 + 0.04 * seq)
			rtts.append(rtt)
			var who := ("%s (%s)" % [rname, r["from"]]) if rname != "" and String(r["from"]) == ip else String(r["from"])
			out += "%d bytes from %s: icmp_seq=%d ttl=%d%s\n" % [reply_bytes, who, seq + 1, int(r.get("ttl", 64)),
				(" time=%s ms" % _ping_time(rtt)) if payload >= 16 else ""]
			continue
		if detail == "no route to host" or detail == "device is offline":
			return "ping: connect: Network is unreachable\n"
		if detail == "blackholed by a discard route":
			return "ping: connect: Invalid argument\n" if seq == 0 else out
		errors += 1
		if frag_line != "":
			out += frag_line
		elif detail.begins_with("host unreachable"):
			var failed: Array = dev.services.get("arp_failed", [])
			var who_failed := detail.trim_prefix("host unreachable (no ARP reply for ").trim_suffix(")")
			if who_failed not in failed:
				failed.append(who_failed)
			dev.services["arp_failed"] = failed
			out += "From %s icmp_seq=%d Destination Host Unreachable\n" % [_first_v4(), seq + 1]
		elif detail == "ttl-exceeded":
			out += "From %s icmp_seq=%d Time to live exceeded\n" % [r["from"], seq + 1]
		elif detail.begins_with("unreachable-"):
			out += "From %s icmp_seq=%d %s\n" % [r["from"], seq + 1, CLI.unreachable_text(detail)]
		else:
			errors -= 1  # a plain timeout prints nothing per probe
	var lost := count - received
	var loss := 100.0 * float(lost) / float(count)
	var loss_text := str(int(loss)) if absf(loss - roundf(loss)) < 0.0001 else ("%.4f" % loss)
	var last_rtt: float = float(rtts[rtts.size() - 1]) if not rtts.is_empty() else 0.0
	out += "\n--- %s ping statistics ---\n%d packets transmitted, %d received, %s%s%% packet loss, time %dms\n" % [
		target, count, received, ("+%d errors, " % errors) if errors > 0 else "",
		loss_text, (count - 1) * 1000 + int(last_rtt)]
	if received > 0 and payload >= 16:
		var best := 9999.0
		var worst := 0.0
		var total := 0.0
		for v in rtts:
			best = minf(best, float(v))
			worst = maxf(worst, float(v))
			total += float(v)
		var avg := total / float(rtts.size())
		var sq := 0.0
		for v in rtts:
			sq += (float(v) - avg) * (float(v) - avg)
		out += "rtt min/avg/max/mdev = %.3f/%.3f/%.3f/%.3f ms%s\n" % [best, avg, worst, sqrt(sq / float(rtts.size())),
			(", pipe %d" % mini(count, 3)) if errors > 0 else ""]
	elif errors > 0:
		out += "pipe %d\n" % mini(count, 3)
	return out

static func _ping_time(ms: float) -> String:
	## iputils keeps three significant digits: 0.312, 1.23, 12.3, 123
	if ms < 1.0:
		return "%.3f" % ms
	if ms < 10.0:
		return "%.2f" % ms
	if ms < 100.0:
		return "%.1f" % ms
	return "%d" % int(round(ms))

func _device_type(name: String) -> String:
	for d: Net.NDevice in Game.all_devices():
		if d.name == name:
			return d.type
	return ""

func _device_ip(name: String) -> String:
	for d: Net.NDevice in Game.all_devices():
		if d.name == name:
			for i: Net.Iface in d.ifaces:
				for cidr in i.ips:
					if not Net.is_v6(cidr):
						return String(cidr).split("/")[0]
	return name

func _tracepath(args: Array) -> String:
	var target := ""
	for a in args:
		if not String(a).begins_with("-"):
			target = String(a)
	if target == "":
		return "Usage\n  tracepath [options] <destination>\n"
	var ip := Sim.resolve(dev, target)
	if ip == "":
		return "tracepath: %s: Name or service not known\n" % target
	var out := " 1?: [LOCALHOST]                      pmtu 1500\n"
	var n := 1
	for hop in Sim.traceroute(dev, ip):
		if hop == "*":
			out += "%2d:  no reply\n" % n
		else:
			var probe := Sim.ping(dev, String(hop))
			var rtt := maxf(0.04, float(probe.get("rtt", 0.1)))
			var name := Sim.reverse_lookup(dev, String(hop))
			var shown := name if name != "" else String(hop)
			if n == 1:
				out += "%2d:  %-52s %.3fms \n" % [n, shown, rtt * 1.15]  # the first hop answers twice: two probes at ttl 1
			out += "%2d:  %-52s %.3fms%s\n" % [n, shown, rtt, " reached" if String(hop) == ip else " "]
		n += 1
	return out + "     Resume: pmtu 1500 hops %d back %d \n" % [n - 1, n - 1]

# ---------- tcpdump ----------

func _tcpdump(args: Array) -> String:
	var iface := ""
	var limit := 0
	var show_link := false
	var filt: Array = []
	var k := 0
	while k < args.size():
		var a := String(args[k])
		if a == "-i" and k + 1 < args.size():
			iface = String(args[k + 1])
			k += 2
			continue
		if a == "-c" and k + 1 < args.size():
			limit = int(args[k + 1])
			k += 2
			continue
		if a in ["-w", "-r", "-s", "-G", "-W", "-C"] and k + 1 < args.size():
			k += 2
			continue
		if a.begins_with("-"):
			if "e" in a:
				show_link = true
			k += 1
			continue
		filt.append(a)
		k += 1
	if iface == "":
		iface = dev.ifaces[0].name if not dev.ifaces.is_empty() else "eth0"
	if iface != "any" and _iface(iface) == null:
		return "tcpdump: %s: No such device exists\n(SIOCGIFHWADDR: No such device)\n" % iface
	var out := "tcpdump: verbose output suppressed, use -v[v]... for full protocol decode\nlistening on %s, link-type %s, snapshot length 262144 bytes\n" % [
		iface, "LINUX_SLL2 (Linux cooked v2)" if iface == "any" else "EN10MB (Ethernet)"]
	var shown := 0
	var seen := 0
	for l in dev.capture:
		var line := String(l)
		var stamp := line.substr(0, 15)
		var on := line.substr(16, 8).strip_edges()
		var rest := line.substr(25)
		# "Out|src>dst|desc" carries the direction and the link header
		var dir := "In"
		var link := ""
		if rest.begins_with("Out|") or rest.begins_with("In|"):
			var bits := rest.split("|", true, 2)
			dir = String(bits[0])
			link = String(bits[1])
			rest = String(bits[2])
		var desc := rest
		if iface != "any" and on != iface:
			continue
		var tagged := desc.begins_with("vlan ")
		if not _bpf_match(filt, desc):
			continue
		seen += 1
		if limit > 0 and shown >= limit:
			continue
		shown += 1
		var body := desc
		if show_link and link != "":
			# with -e the link header leads and the IP token goes
			var proto_len := 98 if "ICMP" in desc else (42 if desc.begins_with("ARP") else 74)
			if tagged:
				body = "%s, ethertype 802.1Q (0x8100), length %d: %s" % [link, proto_len + 4, desc.replace("IP ", "").replace("IP6 ", "")]
			else:
				var ethertype := "ARP (0x0806)" if desc.begins_with("ARP") else ("IPv6 (0x86dd)" if desc.begins_with("IP6") else "IPv4 (0x0800)")
				body = "%s, ethertype %s, length %d: %s" % [link, ethertype, proto_len, desc.replace("IP ", "").replace("IP6 ", "")]
		out += ("%s %s %-3s %s\n" % [stamp, on.rpad(5), dir, body]) if iface == "any" else ("%s %s\n" % [stamp, body])
	return out + "%s%d packets captured\n%d packets received by filter\n0 packets dropped by kernel\n" % ["" if limit > 0 else "\n", shown, seen]

static func _bpf_match(filt: Array, desc: String) -> bool:
	## the handful of BPF words people type: 'or' splits alternatives, the
	## words inside an alternative are ANDed
	var alternatives: Array = [[]]
	for w in filt:
		if String(w).to_lower() in ["or", "||"]:
			alternatives.append([])
		else:
			alternatives[alternatives.size() - 1].append(w)
	for alt in alternatives:
		if _bpf_match_all(alt, desc):
			return true
	return false

static func _bpf_match_all(filt: Array, desc: String) -> bool:
	var k := 0
	var negate := false
	while k < filt.size():
		var w := String(filt[k]).to_lower()
		var hit := true
		match w:
			"and", "&&":
				k += 1
				continue
			"not", "!":
				negate = true
				k += 1
				continue
			"icmp":
				hit = "ICMP " in desc or "ICMP6" in desc
			"icmp6", "ip6":
				hit = "IP6" in desc
			"ip":
				hit = desc.begins_with("IP ")
			"arp":
				hit = desc.begins_with("ARP")
			"udp":
				hit = ".53:" in desc or ".53 " in desc or "BOOTP" in desc or "UDP" in desc
			"tcp":
				hit = "TCP" in desc or "Flags [" in desc
			"port", "host", "src", "dst", "net":
				var v := String(filt[k + 1]) if k + 1 < filt.size() else ""
				if v == "host" or v == "port":  # src host X / dst port N
					k += 1
					v = String(filt[k + 1]) if k + 1 < filt.size() else ""
				hit = (".%s:" % v in desc or ".%s " % v in desc or ".%s>" % v in desc) if (w == "port" or v.is_valid_int()) else (v in desc)
				k += 1
			"vlan":
				hit = "vlan" in desc
			_:
				hit = w in desc.to_lower()
		if negate:
			hit = not hit
			negate = false
		if not hit:
			return false
		k += 1
	return true

# ---------- files ----------

func _cat(args: Array) -> String:
	if args.is_empty():
		return ""
	var path := String(args[0])
	match path:
		"/etc/resolv.conf":
			return ("nameserver %s\n" % dev.resolver) if dev.resolver != "" else ""
		"/etc/hosts":
			var out := "127.0.0.1\tlocalhost\n127.0.1.1\t%s\n\n::1     localhost ip6-localhost ip6-loopback\nff02::1 ip6-allnodes\nff02::2 ip6-allrouters\n" % dev.name
			for h in dev.services.get("hosts", []):
				out += "%s\n" % h
			return out
		"/etc/hostname":
			return dev.name + "\n"
		"/etc/os-release":
			return "PRETTY_NAME=\"Debian GNU/Linux 12 (bookworm)\"\nNAME=\"Debian GNU/Linux\"\nVERSION_ID=\"12\"\nVERSION=\"12 (bookworm)\"\nVERSION_CODENAME=bookworm\nID=debian\nHOME_URL=\"https://www.debian.org/\"\nSUPPORT_URL=\"https://www.debian.org/support\"\nBUG_REPORT_URL=\"https://bugs.debian.org/\"\n"
		"/etc/network/interfaces":
			var out := "# This file describes the network interfaces available on your system\n# and how to activate them. For more information, see interfaces(5).\n\nsource /etc/network/interfaces.d/*\n\n# The loopback network interface\nauto lo\niface lo inet loopback\n"
			for i: Net.Iface in dev.ifaces:
				if i.name.begins_with("wg"):
					continue
				var v4: Array = i.ips.filter(func(c): return not Net.is_v6(c))
				if v4.is_empty():
					continue
				out += "\n# The primary network interface\nauto %s\niface %s inet static\n    address %s\n" % [i.name, i.name, v4[0]]
				for r in dev.static_routes:
					if int(r["plen"]) == 0 and String(r.get("via", "")) != "" and Sim._connected_iface(dev, String(r["via"])) == i:
						out += "    gateway %s\n" % r["via"]
			return out
		"/proc/sys/net/ipv4/ip_forward":
			return "1\n" if dev.ip_forwarding else "0\n"
		"/proc/net/bonding/bond0":
			return _bond_status()
		"/etc/dhcp/dhcpd.conf":
			return _dhcpd_conf()
		"/var/lib/dhcp/dhcpd.leases":
			return _leases_file()
		"/etc/dnsmasq.conf", "/etc/dnsmasq.d/local.conf":
			return _dnsmasq_conf()
		"privatekey":
			return String(dev.services.get("wg_keys", {}).get("private", "")) + "\n" if dev.services.has("wg_keys") else "cat: privatekey: No such file or directory\n"
		"publickey":
			return String(dev.services.get("wg_keys", {}).get("public", "")) + "\n" if dev.services.has("wg_keys") else "cat: publickey: No such file or directory\n"
		"/var/log/syslog", "/var/log/messages":
			return _journalctl([])
	if path.begins_with("/etc/wireguard/") and path.ends_with(".conf"):
		var wi := _iface(path.get_file().trim_suffix(".conf"))
		if wi == null:
			return "cat: %s: No such file or directory\n" % path
		var out := "[Interface]\nPrivateKey = %s\nAddress = %s\nListenPort = 51820\n" % [_fake_key(dev.name + "priv"), ", ".join(PackedStringArray(wi.ips))]
		for p in wi.wg_peers:
			out += "\n[Peer]\nPublicKey = %s\nEndpoint = %s:51820\nAllowedIPs = %s\n" % [p.get("key", ""), p.get("endpoint", ""), ", ".join(PackedStringArray(p.get("allowed", [])))]
		return out
	return "cat: %s: No such file or directory\n" % path

func _redirect(t: Array) -> String:
	## echo <words> > <file>: the few files a network engineer writes by hand.
	## > replaces the file, >> appends to it, as on any shell.
	var append := ">>" in t
	var at := t.find(">>") if append else t.find(">")
	var target := String(t[at + 1]) if at + 1 < t.size() else ""
	var content: Array = t.slice(1 if String(t[0]) == "echo" else 0, at)
	var text := " ".join(PackedStringArray(content)).replace("\"", "").replace("'", "")
	match target:
		"/etc/resolv.conf":
			var parts := text.split(" ", false)
			if parts.size() >= 2 and String(parts[0]) == "nameserver" and String(parts[1]).is_valid_ip_address():
				dev.resolver = String(parts[1])
				Game.topology_changed.emit()
				return ""
			return "" if text.strip_edges() == "" else "bash: /etc/resolv.conf: a nameserver line is what goes here\n"
		"/proc/sys/net/ipv4/ip_forward":
			dev.ip_forwarding = text.strip_edges() == "1"
			Game.topology_changed.emit()
			return ""
		"/etc/hosts":
			var hosts: Array = dev.services.get("hosts", []) if append else []
			hosts.append(text)
			dev.services["hosts"] = hosts
			return ""
		"/etc/hostname":
			return "" if Game.rename_device(dev, text.strip_edges()) else "hostname: the specified hostname is invalid\n"
		"/etc/dhcp/dhcpd.conf":
			return _dhcpd_conf_line(Array(text.split(" ", false)))
		"publickey", "privatekey":
			return ""
	if target.begins_with("/etc/wireguard/") and target.ends_with(".conf"):
		# the whole file on one line: [Interface] Address = X ListenPort = N [Peer] PublicKey = K Endpoint = E AllowedIPs = P
		var name := target.get_file().trim_suffix(".conf")
		var confs: Dictionary = dev.services.get("wg_conf", {})
		var conf: Dictionary = confs.get(name, {"address": [], "peers": []}) if append else {"address": [], "peers": []}
		var words := text.replace("=", " = ").split(" ", false)
		var k := 0
		var peer := {}
		while k < words.size():
			var w := String(words[k])
			var v := String(words[k + 2]) if k + 2 < words.size() and String(words[k + 1]) == "=" else ""
			match w:
				"[Peer]":
					if not peer.is_empty():
						conf["peers"].append(peer)
					peer = {"key": "", "endpoint": "", "allowed": []}
				"Address":
					conf["address"].append(v.trim_suffix(","))
				"PublicKey":
					peer["key"] = v
				"Endpoint":
					peer["endpoint"] = v.split(":")[0] if v.count(":") == 1 else v
				"AllowedIPs":
					peer["allowed"] = Array(v.split(",", false))
			k += 3 if v != "" else 1
		if not peer.is_empty():
			conf["peers"].append(peer)
		confs[name] = conf
		dev.services["wg_conf"] = confs
		return ""
	if target == "":
		return "bash: syntax error near unexpected token `newline'\n"
	return "bash: %s: Permission denied\n" % target

func _sysctl(args: Array) -> String:
	var expr := ""
	for a in args:
		if not String(a).begins_with("-"):
			expr = String(a)
	if expr == "":
		return "sysctl: no variable specified\n" if "-w" in args else "net.ipv4.ip_forward = %d\nnet.ipv6.conf.all.forwarding = %d\n" % [1 if dev.ip_forwarding else 0, 1 if dev.ip_forwarding else 0]
	var key := expr.split("=")[0]
	if key not in ["net.ipv4.ip_forward", "net.ipv6.conf.all.forwarding", "net.ipv4.conf.all.forwarding"]:
		return "sysctl: cannot stat /proc/sys/%s: No such file or directory\n" % key.replace(".", "/")
	if "=" in expr:
		dev.ip_forwarding = expr.split("=")[1] == "1"
		Game.topology_changed.emit()
	return "%s = %d\n" % [key, 1 if dev.ip_forwarding else 0]

# ---------- services ----------

func _services() -> Array:
	## [name, unit, running, proto, port]
	var dhcp: Dictionary = dev.services.get("dhcp", {})
	return [["sshd", "ssh", true, "tcp", 22],
		["dhcpd", "isc-dhcp-server", not dhcp.is_empty() and bool(dhcp.get("running", true)), "udp", 67],
		["dnsmasq", "dnsmasq", dev.services.has("dns"), "udp", 53],
		["snmpd", "snmpd", dev.snmp != "", "udp", 161],
		["rsyslogd", "rsyslog", dev.services.has("syslog"), "udp", 514],
		["freeradius", "freeradius", dev.services.has("radius"), "udp", 1812],
		["tac_plus", "tacacs", dev.services.has("aaa"), "tcp", 49],
		["chronyd", "chrony", dev.ntp_server != "", "udp", 123]]

func _ss(args: Array) -> String:
	## Netid only when more than one family is asked for; sshd also on [::]:22
	var flags := " ".join(PackedStringArray(args))
	var want_tcp := "t" in flags or not ("u" in flags)
	var want_udp := "u" in flags or not ("t" in flags)
	var netid := want_tcp and want_udp
	var out := ("%-6s " % "Netid" if netid else "") + "%-7s %-7s %-7s %26s %21s %s\n" % ["State", "Recv-Q", "Send-Q", "Local Address:Port", "Peer Address:Port", "Process"]
	var pid := 600
	for s in _services():
		pid += 37
		if not bool(s[2]):
			continue
		if (s[3] == "tcp" and not want_tcp) or (s[3] == "udp" and not want_udp):
			continue
		var locals: Array = [["0.0.0.0:%d" % int(s[4]), "0.0.0.0:*", 3]]
		if s[0] == "sshd":
			locals.append(["[::]:%d" % int(s[4]), "[::]:*", 4])
		for loc in locals:
			out += ("%-6s " % s[3] if netid else "") + "%-7s %-7d %-7d %26s %21s %s\n" % ["LISTEN" if s[3] == "tcp" else "UNCONN", 0, 128 if s[3] == "tcp" else 0,
				loc[0], loc[1], "users:((\"%s\",pid=%d,fd=%d))" % [s[0], pid, int(loc[2])]]
	return out

func _systemctl(args: Array) -> String:
	if args.is_empty():
		return "  UNIT                       LOAD   ACTIVE SUB     DESCRIPTION\n  ssh.service                loaded active running OpenBSD Secure Shell server\n"
	var verb := String(args[0])
	var unit := ""
	for a in args.slice(1):
		if not String(a).begins_with("-"):
			unit = String(a).trim_suffix(".service")
			break
	if verb == "daemon-reload":
		return ""
	if unit == "":
		return "Too few arguments.\n"
	var svc: Array = []
	for s in _services():
		if s[1] == unit:
			svc = s
	if unit == "networking" or unit == "systemd-networkd" or unit == "NetworkManager":
		svc = ["networking", unit, true, "", 0]
	if svc.is_empty():
		return "Unit %s.service could not be found.\n" % unit
	match verb:
		"status":
			var running: bool = bool(svc[2])
			var failed: bool = String(dev.services.get("failed_unit", "")) == unit and not running
			var stamp := _when().replace("CEST ", "").replace(" %d" % Time.get_datetime_dict_from_system().get("year", 2026), " %d CEST" % Time.get_datetime_dict_from_system().get("year", 2026))
			var out := "%s %s.service - %s\n     Loaded: loaded (/lib/systemd/system/%s.service; enabled; preset: enabled)\n     Active: %s\n" % [
				"×" if failed else ("●" if running else "○"), unit, _unit_desc(unit), unit,
				("active (running) since %s; %dmin ago" % [stamp, 1 + Game.cycle % 59]) if running else (("failed (Result: exit-code) since %s; 1min ago" % stamp) if failed else "inactive (dead)")]
			if failed:
				out += "    Process: 812 ExecStart=/usr/sbin/dhcpd -4 -q -cf /etc/dhcp/dhcpd.conf (code=exited, status=1/FAILURE)\n   Main PID: 812 (code=exited, status=1/FAILURE)\n        CPU: 12ms\n\n%s %s dhcpd[812]: Can't open /etc/dhcp/dhcpd.conf: No such file or directory\n%s %s systemd[1]: %s.service: Failed with result 'exit-code'.\n" % [
					stamp.substr(4, 6), dev.name, stamp.substr(4, 6), dev.name, unit]
			return out
		"start", "restart", "reload":
			if unit == "isc-dhcp-server":
				if not dev.services.has("dhcp"):
					dev.services["failed_unit"] = unit
					return "Job for isc-dhcp-server.service failed because the control process exited with error code.\nSee \"systemctl status isc-dhcp-server.service\" and \"journalctl -xeu isc-dhcp-server.service\" for details.\n"
				dev.services.erase("failed_unit")
				dev.services["dhcp"]["running"] = true
				Game.topology_changed.emit()
			return ""
		"stop":
			if unit == "isc-dhcp-server" and dev.services.has("dhcp"):
				dev.services["dhcp"]["running"] = false
				Game.topology_changed.emit()
			return ""
		"enable", "disable":
			var out := "" if verb == "disable" else "Created symlink /etc/systemd/system/multi-user.target.wants/%s.service → /lib/systemd/system/%s.service.\n" % [unit, unit]
			if verb == "enable" and "--now" in args:
				out += _systemctl(["start", unit])
			return out
	return "Unknown command verb %s.\n" % verb

static func _unit_desc(unit: String) -> String:
	return {"ssh": "OpenBSD Secure Shell server", "isc-dhcp-server": "ISC DHCP IPv4 server", "dnsmasq": "dnsmasq - A lightweight DHCP and caching DNS server",
		"snmpd": "Simple Network Management Protocol (SNMP) Daemon.", "rsyslog": "System Logging Service", "freeradius": "FreeRADIUS multi-protocol policy server",
		"tacacs": "TACACS+ authentication daemon", "chrony": "chrony, an NTP client/server", "networking": "Raise network interfaces"}.get(unit, unit)

func _journalctl(args: Array) -> String:
	var unit := ""
	for k in args.size():
		var a := String(args[k])
		if a.begins_with("--unit="):
			unit = a.substr(7).trim_suffix(".service")
		elif a.begins_with("-") and not a.begins_with("--") and a.ends_with("u") and k + 1 < args.size():
			unit = String(args[k + 1]).trim_suffix(".service")  # -u, -xeu, -fu
	var stamp := "Sep %02d %02d:%02d:%02d" % [1 + Game.cycle % 28, (Game.cycle * 3) % 24, (Game.cycle * 7) % 60, (Game.cycle * 11) % 60]
	if unit == "isc-dhcp-server":
		var svc: Dictionary = dev.services.get("dhcp", {})
		var out := "%s %s dhcpd[812]: Internet Systems Consortium DHCP Server 4.4.3-P1\n" % [stamp, dev.name]
		for mac in svc.get("leases", {}):
			var ip := String(svc["leases"][mac])
			var ifn := String(svc.get("iface", "eth0"))
			out += "%s %s dhcpd[812]: DHCPDISCOVER from %s via %s\n%s %s dhcpd[812]: DHCPOFFER on %s to %s via %s\n%s %s dhcpd[812]: DHCPREQUEST for %s (%s) from %s via %s\n%s %s dhcpd[812]: DHCPACK on %s to %s via %s\n" % [
				stamp, dev.name, mac, ifn, stamp, dev.name, ip, mac, ifn, stamp, dev.name, ip, _first_v4(), mac, ifn, stamp, dev.name, ip, mac, ifn]
		return out
	var out := ""
	if dev.services.has("syslog"):
		var msgs: Array = dev.services["syslog"]["messages"]
		for m in msgs.slice(maxi(0, msgs.size() - 20)):
			out += "%s %s rsyslogd[404]: %s\n" % [stamp, dev.name, m]
	for l in dev.logs.slice(maxi(0, dev.logs.size() - 15)):
		out += "%s %s systemd[1]: %s\n" % [stamp, dev.name, l]
	return out if out != "" else "-- No entries --\n"

# ---------- DHCP ----------

func _dhclient(args: Array) -> String:
	var verbose := "-v" in args
	var release := "-r" in args
	var ifn := ""
	for a in args:
		if not String(a).begins_with("-"):
			ifn = String(a)
	if ifn == "":
		ifn = dev.ifaces[0].name if not dev.ifaces.is_empty() else "eth0"
	var ifc := _iface(ifn)
	if ifc == null:
		return "Cannot find device \"%s\"\n" % ifn
	var head := ""
	if verbose:
		head = "Internet Systems Consortium DHCP Client 4.4.3-P1\nCopyright 2004-2022 Internet Systems Consortium.\nAll rights reserved.\nFor info, please visit https://www.isc.org/software/dhcp/\n\nListening on LPF/%s/%s\nSending on   LPF/%s/%s\nSending on   Socket/fallback\n" % [ifn, ifc.mac.to_lower(), ifn, ifc.mac.to_lower()]
	if release:
		var lease: Dictionary = dev.services.get("dhcp_lease", {})
		if String(lease.get("iface", "")) == ifn:
			var cidr := String(lease.get("cidr", ""))
			if cidr in ifc.ips:
				Game.remove_ip(ifc, cidr)
			if String(lease.get("gw", "")) != "":
				Game.remove_static_route(dev, "0.0.0.0", 0)
			dev.services.erase("dhcp_lease")
			return head + ("DHCPRELEASE of %s on %s to %s port 67 (xid=0x%08x)\n" % [cidr.split("/")[0], ifn, lease.get("server", ""), (Game.cycle * 2654435761 + ifc.mac.hash()) % 0xFFFFFFFF] if verbose else "")
		return head
	var xid := "0x%08x" % ((Game.cycle * 2654435761 + ifc.mac.hash()) % 0xFFFFFFFF)
	var got := Sim.dhcp_request(dev, ifc)
	if got.is_empty():
		return head + ("DHCPDISCOVER on %s to 255.255.255.255 port 67 interval 3 (xid=%s)\nDHCPDISCOVER on %s to 255.255.255.255 port 67 interval 7 (xid=%s)\nNo DHCPOFFERS received.\nNo working leases in persistent database - sleeping.\n" % [ifn, xid, ifn, xid] if verbose else "")
	var server := String(got.get("server", got.get("gw", "0.0.0.0")))
	dev.services["dhcp_lease"] = {"iface": ifn, "cidr": "%s/%d" % [got["ip"], int(got["plen"])], "gw": String(got.get("gw", "")), "server": server}
	if not verbose:
		return ""
	return head + "DHCPDISCOVER on %s to 255.255.255.255 port 67 interval 3 (xid=%s)\nDHCPOFFER of %s from %s\nDHCPREQUEST for %s on %s to 255.255.255.255 port 67 (xid=%s)\nDHCPACK of %s from %s (xid=%s)\nbound to %s -- renewal in 1800 seconds.\n" % [
		ifn, xid, got["ip"], server, got["ip"], ifn, xid, got["ip"], server, xid, got["ip"]]

func _dhcpd(args: Array) -> String:
	## dhcpd <if>: start the server on its config file; the old six-word
	## shorthand still writes the block and starts it in one go
	if args.size() >= 4 and _iface(String(args[0])) != null and String(args[3]).is_valid_int():
		if not Net.valid_cidr(String(args[1]) + "/" + String(args[3])):
			return "dhcpd: %s/%s is not a valid range\n" % [args[1], args[3]]
		dev.services["dhcp"] = {"iface": String(args[0]), "start": String(args[1]), "end": String(args[2]),
			"plen": int(args[3]), "gw": String(args[4]) if args.size() > 4 else "",
			"dns": String(args[5]) if args.size() > 5 else "", "leases": {}, "running": true}
		Game.topology_changed.emit()
		return _dhcpd_banner(String(args[0]))
	var ifn := ""
	for a in args:
		if not String(a).begins_with("-"):
			ifn = String(a)
	var svc: Dictionary = dev.services.get("dhcp", {})
	if svc.is_empty():
		return "Internet Systems Consortium DHCP Server 4.4.3-P1\nCopyright 2004-2022 Internet Systems Consortium.\nAll rights reserved.\nFor info, please visit https://www.isc.org/software/dhcp/\nCan't open /etc/dhcp/dhcpd.conf: No such file or directory\n\nIf you think you have received this message due to a bug rather\nthan a configuration issue please read the section on submitting\nbugs on either our web page at www.isc.org or in the README file\nbefore submitting a bug.  These pages explain the proper\nprocess and the information we find helpful for debugging.\n\nexiting.\n"
	if ifn == "":
		ifn = String(svc.get("iface", "eth0"))
	var listen := _iface(ifn)
	if listen == null:
		return "Cannot find device \"%s\"\n" % ifn
	var netw := Net.network_of(String(svc.get("start", "0.0.0.0")) + "/" + str(int(svc.get("plen", 24))))
	var covered := false
	for cidr in listen.ips:
		if not Net.is_v6(cidr) and Net.same_net(String(cidr).split("/")[0], String(netw["prefix"]), int(svc.get("plen", 24))):
			covered = true
	if not covered:
		return "Internet Systems Consortium DHCP Server 4.4.3-P1\nCopyright 2004-2022 Internet Systems Consortium.\nAll rights reserved.\nFor info, please visit https://www.isc.org/software/dhcp/\nConfig file: /etc/dhcp/dhcpd.conf\nDatabase file: /var/lib/dhcp/dhcpd.leases\nPID file: /var/run/dhcpd.pid\nWrote 0 leases to leases file.\n\nNo subnet declaration for %s (%s).\n** Ignoring requests on %s.  If this is not what\n   you want, please write a subnet declaration\n   in your dhcpd.conf file for the network segment\n   to which interface %s is attached. **\n\n\nNot configured to listen on any interfaces!\n\nIf you think you have received this message due to a bug rather\nthan a configuration issue please read the section on submitting\nbugs on either our web page at www.isc.org or in the README file\nbefore submitting a bug.  These pages explain the proper\nprocess and the information we find helpful for debugging.\n\nexiting.\n" % [
			ifn, String(listen.ips[0]).split("/")[0] if not listen.ips.is_empty() else "no address", ifn, ifn]
	svc["iface"] = ifn
	svc["running"] = true
	Game.topology_changed.emit()
	return _dhcpd_banner(ifn)

func _dhcpd_banner(ifn: String) -> String:
	var svc: Dictionary = dev.services.get("dhcp", {})
	var ifc := _iface(ifn)
	var net := "%s/%d" % [Net.network_of(String(svc.get("start", "0.0.0.0")) + "/" + str(int(svc.get("plen", 24))))["prefix"], int(svc.get("plen", 24))]
	return "Internet Systems Consortium DHCP Server 4.4.3-P1\nCopyright 2004-2022 Internet Systems Consortium.\nAll rights reserved.\nFor info, please visit https://www.isc.org/software/dhcp/\nConfig file: /etc/dhcp/dhcpd.conf\nDatabase file: /var/lib/dhcp/dhcpd.leases\nPID file: /var/run/dhcpd.pid\nWrote %d leases to leases file.\nListening on LPF/%s/%s/%s\nSending on   LPF/%s/%s/%s\nSending on   Socket/fallback/fallback-net\n" % [
		svc.get("leases", {}).size(), ifn, ifc.mac.to_lower(), net, ifn, ifc.mac.to_lower(), net]

func _dhcpd_conf_line(t: Array) -> String:
	## subnet A netmask M { range F L; option routers G; option domain-name-servers D; }
	var words: Array = []
	for w in t:
		var s := String(w).replace("{", " ").replace("}", " ").replace(";", " ")
		for part in s.split(" ", false):
			words.append(part)
	if words.size() < 6 or String(words[0]) != "subnet" or String(words[2]) != "netmask":
		return "/etc/dhcp/dhcpd.conf line 1: expecting a parameter or declaration\n"
	var plen := CLI.mask_to_plen(String(words[3]))
	var cfg := {"iface": "", "start": "", "end": "", "plen": plen, "gw": "", "dns": "", "leases": {}, "running": false}
	var k := 4
	while k < words.size():
		var w := String(words[k])
		if w == "range" and k + 2 < words.size():
			cfg["start"] = String(words[k + 1])
			cfg["end"] = String(words[k + 2])
			k += 3
		elif w == "option" and k + 2 < words.size():
			if String(words[k + 1]) == "routers":
				cfg["gw"] = String(words[k + 2])
			elif String(words[k + 1]) == "domain-name-servers":
				cfg["dns"] = String(words[k + 2]).trim_suffix(",")
			k += 3
		else:
			k += 1
	if cfg["start"] == "" or not Net.valid_cidr(String(cfg["start"]) + "/" + str(plen)):
		return "/etc/dhcp/dhcpd.conf line 1: expecting a range declaration\n"
	for i: Net.Iface in dev.ifaces:
		for cidr in i.ips:
			if not Net.is_v6(cidr) and Net.same_net(String(cfg["start"]), String(cidr).split("/")[0], int(String(cidr).split("/")[1])):
				cfg["iface"] = i.name
	if cfg["iface"] == "":
		cfg["iface"] = dev.ifaces[0].name if not dev.ifaces.is_empty() else "eth0"
	dev.services["dhcp"] = cfg
	Game.topology_changed.emit()
	return ""

func _dhcpd_conf() -> String:
	var svc: Dictionary = dev.services.get("dhcp", {})
	if svc.is_empty():
		return "cat: /etc/dhcp/dhcpd.conf: No such file or directory\n"
	var plen := int(svc.get("plen", 24))
	var net := String(Net.network_of(String(svc["start"]) + "/" + str(plen))["prefix"])
	var out := "default-lease-time 600;\nmax-lease-time 7200;\nauthoritative;\n\nsubnet %s netmask %s {\n  range %s %s;\n" % [net, CLI.plen_to_mask(plen), svc["start"], svc["end"]]
	if String(svc.get("gw", "")) != "":
		out += "  option routers %s;\n" % svc["gw"]
	if String(svc.get("dns", "")) != "":
		out += "  option domain-name-servers %s;\n" % svc["dns"]
	return out + "}\n"

func _leases_file() -> String:
	var svc: Dictionary = dev.services.get("dhcp", {})
	var out := "# The format of this file is documented in the dhcpd.leases(5) manual page.\n# This lease file was written by isc-dhcp-4.4.3-P1\n\n# authoring-byte-order entry is generated, DO NOT DELETE\nauthoring-byte-order little-endian;\n\nserver-duid \"\\000\\001\\000\\001-\\247\\032\\214\\002PE\\000\\000\\001\";\n\n"
	var d := Time.get_datetime_dict_from_system()
	var wday := int(d.get("weekday", 6))
	for mac in svc.get("leases", {}):
		var since := int(svc.get("since", {}).get(mac, Game.cycle))
		var hh := since % 24
		var mm := (since * 7) % 50
		out += "lease %s {\n  starts %d %d/%02d/%02d %02d:%02d:00;\n  ends %d %d/%02d/%02d %02d:%02d:00;\n  cltt %d %d/%02d/%02d %02d:%02d:00;\n  binding state active;\n  next binding state free;\n  rewind binding state free;\n  hardware ethernet %s;\n  uid \"\\001%s\";\n}\n" % [
			svc["leases"][mac], wday, int(d.get("year", 2026)), int(d.get("month", 9)), int(d.get("day", 5)), hh, mm,
			wday, int(d.get("year", 2026)), int(d.get("month", 9)), int(d.get("day", 5)), hh, mm + 10,
			wday, int(d.get("year", 2026)), int(d.get("month", 9)), int(d.get("day", 5)), hh, mm, String(mac).to_lower(),
			String(mac).to_lower().replace(":", "")]
	return out

# ---------- DNS ----------

func _resolvectl(args: Array) -> String:
	## plain Debian: no systemd-resolved, the resolver is the file
	if not dev.services.has("resolved"):
		if args.size() >= 3 and String(args[0]) == "dns" and String(args[2]).is_valid_ip_address():
			return "Failed to set DNS configuration: Unit dbus-org.freedesktop.resolve1.service not found.\n"
		return "Failed to get global data: Unit dbus-org.freedesktop.resolve1.service not found.\n"
	if args.is_empty() or String(args[0]) == "status":
		var out := "Global\n         Protocols: -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported\n  resolv.conf mode: stub\n"
		if dev.resolver != "":
			out += "Current DNS Server: %s\n       DNS Servers: %s\n" % [dev.resolver, dev.resolver]
		var n := 2
		for i: Net.Iface in dev.ifaces:
			out += "\nLink %d (%s)\n    Current Scopes: %s\n         Protocols: +DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported\n" % [n, i.name, "DNS" if dev.resolver != "" else "none"]
			if dev.resolver != "":
				out += "Current DNS Server: %s\n       DNS Servers: %s\n" % [dev.resolver, dev.resolver]
			n += 1
		return out
	if String(args[0]) == "dns" and args.size() >= 3 and String(args[2]).is_valid_ip_address():
		if _iface(String(args[1])) == null:
			return "Failed to resolve interface \"%s\", ignoring: No such device\n" % args[1]
		dev.resolver = String(args[2])
		Game.topology_changed.emit()
		return ""
	if String(args[0]) == "flush-caches":
		dev.dns_cache.clear()
		return ""
	if String(args[0]) == "statistics":
		return "DNSSEC supported by current servers: no\n\nTransactions\nCurrent Transactions: 0\n  Total Transactions: %d\n\nCache\n  Current Cache Size: %d\n          Cache Hits: 0\n        Cache Misses: %d\n" % [dev.dns_cache.size() * 2, dev.dns_cache.size(), dev.dns_cache.size()]
	if String(args[0]) == "query" and args.size() >= 2:
		var qip := Sim.resolve(dev, String(args[1]))
		if qip == "":
			return "%s: resolve call failed: '%s' not found\n" % [args[1], args[1]]
		return "%s: %s\n\n-- Information acquired via protocol DNS in 1.2ms.\n-- Data is authenticated: no; Data was acquired via local or encrypted transport: no\n-- Data from: network\n" % [args[1], qip]
	return "Unknown command verb %s.\n" % args[0]

func _authoritative(name: String) -> bool:
	## true when the resolver we ask is the server that owns the record
	var owner := Sim._ip_owner(dev.resolver)
	if owner == null:
		return false
	var svc: Dictionary = owner.services.get("dns", {})
	return svc.get("records", {}).has(name) or svc.get("records6", {}).has(name)

func _nslookup(args: Array) -> String:
	var qtype := ""
	var name := ""
	var server := dev.resolver
	for a in args:
		var s := String(a)
		if s.begins_with("-type=") or s.begins_with("-query=") or s.begins_with("-q="):
			qtype = s.split("=")[1].to_upper()
		elif s == "-6":
			qtype = "AAAA"  # not a real flag; tolerated, taught as -type=AAAA
		elif s.begins_with("-"):
			pass
		elif name == "":
			name = s
		else:
			server = s
	if name == "":
		return "Usage:\n   nslookup [-opt ...]             # interactive mode using default server\n   nslookup [-opt ...] - server    # interactive mode using 'server'\n   nslookup [-opt ...] host        # just look up 'host' using default server\n   nslookup [-opt ...] host server # just look up 'host' using 'server'\n"
	if server == "":
		return ";; communications error to 127.0.0.1#53: connection refused\n;; communications error to 127.0.0.1#53: connection refused\n;; communications error to 127.0.0.1#53: connection refused\n;; no servers could be reached\n\n"
	var head := "Server:\t\t%s\nAddress:\t%s#53\n\n" % [server, server]
	if name.is_valid_ip_address() or qtype == "PTR":
		var nm := Sim.reverse_lookup(dev, name)
		var octets := name.split(".")
		octets.reverse()
		var arpa := ".".join(octets) + ".in-addr.arpa"
		if nm == "":
			return head + "** server can't find %s: NXDOMAIN\n" % arpa
		return head + "%s\tname = %s.\n" % [arpa, nm]
	var v4 := Sim.resolve(dev, name) if qtype != "AAAA" else ""
	var v6 := Sim.resolve(dev, name, true, true) if qtype != "A" else ""
	if v4 == "" and v6 == "":
		return head + "** server can't find %s: NXDOMAIN\n" % name
	var out := head + ("" if _authoritative(name) else "Non-authoritative answer:\n")
	if v4 != "":
		out += "Name:\t%s\nAddress: %s\n" % [name, v4]
	if v6 != "":
		out += "Name:\t%s\nAddress: %s\n" % [name, v6]
	return out

func _dig(args: Array) -> String:
	var name := ""
	var qtype := "A"
	var server := dev.resolver
	var short := false
	for a in args:
		var s := String(a)
		if s.begins_with("@"):
			server = s.substr(1)
		elif s == "+short":
			short = true
		elif s.begins_with("+"):
			pass
		elif s.to_upper() in ["A", "AAAA", "PTR", "MX", "NS", "TXT", "ANY"]:
			qtype = s.to_upper()
		elif name == "":
			name = s
	if name == "":
		name = "."
	if server == "":
		return ";; communications error to 127.0.0.1#53: connection refused\n;; communications error to 127.0.0.1#53: connection refused\n;; communications error to 127.0.0.1#53: connection refused\n;; no servers could be reached\n\n"
	var reverse := false
	if "-x" in args:
		reverse = true
		qtype = "PTR"
		for a in args:
			if String(a).is_valid_ip_address():
				name = String(a)
	var answer := ""
	var qname := name
	if reverse:
		var oct := name.split(".")
		oct.reverse()
		qname = ".".join(oct) + ".in-addr.arpa"
		answer = Sim.reverse_lookup(dev, name)
	elif name != ".":
		answer = Sim.resolve(dev, name, true, qtype == "AAAA") if qtype in ["A", "AAAA"] else ""
	if short:
		return (answer + "\n") if answer != "" else ""
	var status := "NOERROR" if answer != "" or name == "." else "NXDOMAIN"
	var out := "\n; <<>> DiG 9.18.24-1-Debian <<>> %s\n;; global options: +cmd\n;; Got answer:\n;; ->>HEADER<<- opcode: QUERY, status: %s, id: %d\n;; flags: qr%s rd ra; QUERY: 1, ANSWER: %d, AUTHORITY: 0, ADDITIONAL: 1\n\n;; OPT PSEUDOSECTION:\n; EDNS: version: 0, flags:; udp: 1232\n;; QUESTION SECTION:\n;%s.\t\t\tIN\t%s\n\n" % [
		" ".join(PackedStringArray(args)), status, (name.hash() + Game.cycle) % 65536, " aa" if _authoritative(name) else "", 1 if answer != "" else 0, qname, qtype]
	if answer != "":
		out += ";; ANSWER SECTION:\n%s.\t\t%d\tIN\t%s\t%s%s\n\n" % [qname, Sim.DEFAULT_TTL * 60, qtype, answer, "." if reverse else ""]
	return out + ";; Query time: 1 msec\n;; SERVER: %s#53(%s) (UDP)\n;; WHEN: %s\n;; MSG SIZE  rcvd: %d\n\n" % [server, server, _when(), 56 + qname.length()]

func _when() -> String:
	## Sat Sep 05 12:34:56 CEST 2026, the way dig and systemctl date things
	var d := Time.get_datetime_dict_from_system()
	var days := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %s %02d %02d:%02d:%02d CEST %d" % [days[int(d.get("weekday", 0))], months[int(d.get("month", 1)) - 1], int(d.get("day", 1)),
		int(d.get("hour", 0)), int(d.get("minute", 0)), int(d.get("second", 0)), int(d.get("year", 2026))]

func _dnsmasq_conf() -> String:
	var svc: Dictionary = dev.services.get("dns", {})
	if svc.is_empty():
		return "cat: /etc/dnsmasq.conf: No such file or directory\n"
	var out := "# dnsmasq: local records\ndomain-needed\nbogus-priv\n"
	for k in svc.get("records", {}):
		out += "address=/%s/%s\n" % [k, svc["records"][k]]
	for k6 in svc.get("records6", {}):
		out += "address=/%s/%s\n" % [k6, svc["records6"][k6]]
	for z in svc.get("delegations", {}):
		out += "server=/%s/%s\n" % [z, svc["delegations"][z]]
	var cfg64: Dictionary = svc.get("dns64", {})
	if bool(cfg64.get("enabled", false)):
		out += "# dns64 %s (bind: dns64 %s/96 { };)\n" % [cfg64.get("prefix", ""), cfg64.get("prefix", "")]
	return out

func _dns(t: Array) -> String:
	if t.size() >= 4 and t[1] == "add" and String(t[3]).is_valid_ip_address():
		if not dev.services.has("dns"):
			dev.services["dns"] = {"records": {}}
		if Net.is_v6(String(t[3])):
			if not dev.services["dns"].has("records6"):
				dev.services["dns"]["records6"] = {}
			dev.services["dns"]["records6"][t[2]] = t[3]
		else:
			dev.services["dns"]["records"][t[2]] = t[3]
		if t.size() > 4 and String(t[4]).is_valid_int():
			if not dev.services["dns"].has("ttls"):
				dev.services["dns"]["ttls"] = {}
			dev.services["dns"]["ttls"][t[2]] = int(t[4])
		Game.topology_changed.emit()
		return ""
	if t.size() == 4 and t[1] == "delegate" and String(t[3]).is_valid_ip_address():
		if not dev.services.has("dns"):
			dev.services["dns"] = {"records": {}}
		if not dev.services["dns"].has("delegations"):
			dev.services["dns"]["delegations"] = {}
		dev.services["dns"]["delegations"][t[2]] = t[3]
		Game.topology_changed.emit()
		return "%s delegated to %s\n" % [t[2], t[3]]
	if t.size() >= 2 and t[1] == "dns64":
		if not dev.services.has("dns"):
			dev.services["dns"] = {"records": {}}
		if t.size() == 3 and t[2] == "off":
			dev.services["dns"]["dns64"] = {"prefix": "", "enabled": false}
			return "dns64 disabled\n"
		if t.size() == 3:
			if not String(t[2]).ends_with("::") or not (String(t[2]) + "1").is_valid_ip_address():
				return "dns64: prefix must be an IPv6 prefix ending in :: (e.g. 64:ff9b::)\n"
			dev.services["dns"]["dns64"] = {"prefix": String(t[2]), "enabled": true}
			return "dns64 synthesizing AAAA answers from %s\n" % t[2]
		var cfg64: Dictionary = dev.services["dns"].get("dns64", {})
		return "dns64: %s\n" % ("off" if not bool(cfg64.get("enabled", false))
			else "on, prefix %s" % cfg64.get("prefix", ""))
	if t.size() == 2 and t[1] == "flush":
		dev.dns_cache.clear()
		return "resolver cache cleared\n"
	if t.size() == 2 and t[1] == "cache":
		if dev.dns_cache.is_empty():
			return "(cache empty)\n"
		var cout := "%-24s %-16s %s\n" % ["NAME", "ADDRESS", "EXPIRES"]
		for nm2 in dev.dns_cache:
			cout += "%-24s %-16s cycle %d\n" % [nm2, dev.dns_cache[nm2]["ip"],
				int(dev.dns_cache[nm2]["expires"])]
		return cout
	if t.size() == 2 and t[1] == "list":
		var svc_d: Dictionary = dev.services.get("dns", {})
		var recs: Dictionary = svc_d.get("records", {})
		var dels: Dictionary = svc_d.get("delegations", {})
		if recs.is_empty() and dels.is_empty():
			return "(no records: this host is not a DNS server yet)\n"
		var out := ""
		for k in recs:
			out += "%-24s A   %-16s ttl %d\n" % [k, recs[k],
				int(svc_d.get("ttls", {}).get(k, Sim.DEFAULT_TTL))]
		for k6 in svc_d.get("records6", {}):
			out += "%-24s AAAA %-15s ttl %d\n" % [k6, svc_d["records6"][k6],
				int(svc_d.get("ttls", {}).get(k6, Sim.DEFAULT_TTL))]
		var cfg_show: Dictionary = svc_d.get("dns64", {})
		if bool(cfg_show.get("enabled", false)):
			out += "dns64                    ON   prefix %s\n" % cfg_show.get("prefix", "")
		for z in dels:
			out += "%-24s NS  %s\n" % [z, dels[z]]
		return out
	return "usage: dns add <name> <ip> [ttl] | dns delegate <zone> <ns-ip> | dns64 <prefix>|off | dns list | dns cache | dns flush   (the real file is /etc/dnsmasq.conf)\n"

# ---------- reaching services ----------

func _host_of(url: String) -> String:
	var h := url
	for scheme in ["http://", "https://"]:
		h = h.trim_prefix(scheme)
	h = h.split("/")[0]
	if ":" in h and not Net.is_v6(h):
		h = h.split(":")[0]
	return h

func _curl(args: Array) -> String:
	var url := ""
	var head_only := false
	for a in args:
		if String(a) in ["-I", "--head"]:
			head_only = true
		elif not String(a).begins_with("-"):
			url = String(a)
	if url == "":
		return "curl: try 'curl --help' or 'curl --manual' for more information\n"
	var host := _host_of(url)
	var ip := Sim.resolve(dev, host)
	if ip == "" and host.is_valid_ip_address():
		ip = host
	if ip == "":
		return "curl: (6) Could not resolve host: %s\n" % host
	var r := Sim.ping(dev, ip)
	if not bool(r["ok"]):
		return "curl: (7) Failed to connect to %s port 80 after 3001 ms: Couldn't connect to server\n" % host
	var owner := Sim._ip_owner(ip)
	var title := owner.name if owner != null else host
	if head_only:
		return "HTTP/1.1 200 OK\nServer: nginx/1.22.1\nDate: %s\nContent-Type: text/html\nContent-Length: %d\nConnection: keep-alive\n\n" % [Time.get_datetime_string_from_system(true, true), 60 + title.length()]
	return "<!DOCTYPE html>\n<html><head><title>%s</title></head>\n<body><h1>%s</h1><p>It works.</p></body></html>\n" % [title, title]

func _nc(args: Array) -> String:
	var words: Array = []
	for a in args:
		if not String(a).begins_with("-"):
			words.append(String(a))
	if words.size() < 2:
		return "usage: nc [-46CDdFhklNnrStUuvZz] [-I length] [-i interval] [-M ttl]\n\t  [-m minttl] [-O length] [-P proxy_username] [-p source_port]\n\t  [-q seconds] [-s sourceaddr] [-T keyword] [-V rtable] [-W recvlimit]\n\t  [-w timeout] [-X proxy_protocol] [-x proxy_address[:port]]\n\t  [destination] [port]\n"
	var host := String(words[0])
	var port := String(words[1])
	var ip := Sim.resolve(dev, host)
	if ip == "" and host.is_valid_ip_address():
		ip = host
	if ip == "":
		return "nc: getaddrinfo for host \"%s\" port %s: Name or service not known\n" % [host, port]
	if not bool(Sim.ping(dev, ip)["ok"]):
		return "nc: connect to %s port %s (tcp) failed: No route to host\n" % [ip, port]
	var open := _port_open(ip, int(port))
	if open:
		return "Connection to %s %s port [tcp/%s] succeeded!\n" % [host, port, _port_name(int(port))]
	return "nc: connect to %s port %s (tcp) failed: Connection refused\n" % [ip, port]

func _telnet(args: Array) -> String:
	if args.is_empty():
		return "telnet> (no host given)\n"
	var host := String(args[0])
	var port := int(args[1]) if args.size() > 1 and String(args[1]).is_valid_int() else 23
	var ip := Sim.resolve(dev, host)
	if ip == "" and host.is_valid_ip_address():
		ip = host
	if ip == "":
		return "telnet: could not resolve %s/telnet: Name or service not known\n" % host
	var out := "Trying %s...\n" % ip
	if not bool(Sim.ping(dev, ip)["ok"]):
		return out + "telnet: Unable to connect to remote host: No route to host\n"
	if not _port_open(ip, port):
		return out + "telnet: Unable to connect to remote host: Connection refused\n"
	return out + "Connected to %s.\nEscape character is '^]'.\nConnection closed by foreign host.\n" % host

func _port_open(ip: String, port: int) -> bool:
	var owner := Sim._ip_owner(ip)
	if owner == null:
		return false
	if port == 22:
		return true
	if port in [80, 443]:
		return owner.type == "server" or owner.type == "loadbalancer"
	if port == 53:
		return owner.services.has("dns")
	if port == 161:
		return owner.snmp != ""
	return false

static func _port_name(port: int) -> String:
	return {22: "ssh", 53: "domain", 80: "http", 443: "https", 161: "snmp", 23: "telnet", 25: "smtp", 123: "ntp", 514: "syslog", 3306: "mysql", 5432: "postgresql", 8080: "http-alt"}.get(port, "*")

# ---------- wireguard ----------

func _wg(args: Array) -> String:
	if args.is_empty() or String(args[0]) == "show":
		return _wg_show(String(args[1]) if args.size() > 1 else "")
	match String(args[0]):
		"genkey":
			var keys := {"private": _fake_key(dev.name + "priv"), "public": _fake_key(dev.name + "pub")}
			dev.services["wg_keys"] = keys
			return "" if "|" in args or "tee" in args else String(keys["private"]) + "\n"
		"pubkey":
			return String(dev.services.get("wg_keys", {}).get("public", _fake_key(dev.name + "pub"))) + "\n"
		"set":
			if args.size() < 2:
				return "Usage: wg set <interface> [listen-port <port>] [fwmark <mark>] [private-key <file path>] [peer <base64 public key> [remove] [preshared-key <file path>] [endpoint <ip>:<port>] [persistent-keepalive <interval seconds>] [allowed-ips <ip1>/<cidr1>[,<ip2>/<cidr2>]...] ]...\n"
			var wi := _iface(String(args[1]))
			if wi == null or not wi.name.begins_with("wg"):
				return "Unable to access interface: No such device\n"
			var k := 2
			var peer := {}
			while k < args.size():
				var w := String(args[k])
				var v := String(args[k + 1]) if k + 1 < args.size() else ""
				match w:
					"listen-port", "private-key", "fwmark", "persistent-keepalive", "preshared-key":
						k += 2
					"peer":
						if not peer.is_empty():
							_wg_add_peer(wi, peer)
						peer = {"key": v, "endpoint": "", "allowed": []}
						k += 2
					"endpoint":
						peer["endpoint"] = v.split(":")[0] if v.count(":") == 1 else v
						k += 2
					"allowed-ips":
						var allowed: Array = []
						for c in v.split(",", false):
							allowed.append(String(c).strip_edges())
						peer["allowed"] = allowed
						k += 2
					"remove":
						for existing in wi.wg_peers.duplicate():
							if String(existing.get("key", "")) == String(peer.get("key", "")):
								wi.wg_peers.erase(existing)
						peer = {}
						k += 1
					_:
						return "Invalid argument: %s\n" % w
			if not peer.is_empty():
				_wg_add_peer(wi, peer)
			Game.topology_changed.emit()
			return ""
		# ---- the old short verbs, kept for saved worlds ----
		"up":
			if args.size() < 2:
				return "wg up <n>: the real steps are ip link add wg0 type wireguard, wg set wg0 ..., ip link set wg0 up\n"
			var w := Game.add_wireguard(dev, int(args[1]))
			return "wg%s up with public key %s\n" % [args[1], w.wg_key] if w else "wg: failed\n"
		"addr":
			var wi := _iface("wg%s" % args[1]) if args.size() > 2 else null
			if wi == null:
				return "wg: no such interface\n"
			return "" if Game.add_ip(wi, String(args[2])) else "wg: invalid address\n"
		"peer":
			if args.size() != 5:
				return "wg peer <n> <key> <endpoint> <allowed>   (real: wg set wg0 peer KEY endpoint IP:51820 allowed-ips P)\n"
			var wi2 := _iface("wg%s" % args[1])
			if wi2 == null:
				return "wg: no such interface\n"
			var allowed2: Array = []
			for c in String(args[4]).split(",", false):
				allowed2.append(String(c).strip_edges())
			_wg_add_peer(wi2, {"key": String(args[2]), "endpoint": String(args[3]), "allowed": allowed2})
			Game.topology_changed.emit()
			return ""
	return "Invalid subcommand: `%s'\nUsage: wg <cmd> [<args>]\n\nAvailable subcommands:\n  show: Shows the current configuration and device information\n  showconf: Shows the current configuration of a given WireGuard interface, for use with `setconf'\n  set: Change the current configuration, add peers, remove peers, or change peers\n  setconf: Applies a configuration file to a WireGuard interface\n  addconf: Appends a configuration file to a WireGuard interface\n  syncconf: Synchronizes a configuration file to a WireGuard interface\n  genkey: Generates a new private key and writes it to stdout\n  genpsk: Generates a new preshared key and writes it to stdout\n  pubkey: Reads a private key from stdin and writes a public key to stdout\n" % args[0]

func _wg_add_peer(wi: Net.Iface, peer: Dictionary) -> void:
	for existing in wi.wg_peers.duplicate():
		if String(existing.get("key", "")) == String(peer.get("key", "")):
			wi.wg_peers.erase(existing)
	wi.wg_peers.append(peer)

static func _fake_key(seed: String) -> String:
	var alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	var out := ""
	var h := seed.hash()
	for k in 43:
		h = (h * 1103515245 + 12345) % 2147483648
		out += alphabet[h % 64]
	return out + "="

func _wg_show(only: String) -> String:
	var out := ""
	for i: Net.Iface in dev.ifaces:
		if not i.name.begins_with("wg") or (only != "" and i.name != only):
			continue
		if out != "":
			out += "\n"
		out += "interface: %s\n  public key: %s\n  private key: (hidden)\n  listening port: 51820\n" % [i.name, i.wg_key]
		for p in i.wg_peers:
			var up := Sim.wg_handshake(i, p)
			out += "\npeer: %s\n  endpoint: %s:51820\n  allowed ips: %s\n" % [p.get("key", ""), p.get("endpoint", ""), ", ".join(PackedStringArray(p.get("allowed", [])))]
			if up:
				out += "  latest handshake: %d seconds ago\n  transfer: %.2f KiB received, %.2f KiB sent\n" % [5 + Game.cycle % 50, i.rx_frames * 0.148, i.tx_frames * 0.148]
			else:
				out += "  transfer: 0 B received, %.2f KiB sent\n" % (i.tx_frames * 0.148)
	if only != "" and out == "":
		return "Unable to access interface: No such device\n"
	return out

# ---------- neighbours, bonds ----------

func _lldpcli() -> String:
	var rule := "-------------------------------------------------------------------------------\n"
	var out := rule + "LLDP neighbors:\n" + rule
	var any := false
	for i: Net.Iface in dev.ifaces:
		var l := Game.link_at(i)
		if l == null:
			continue
		any = true
		var far := l.other(i)
		out += "Interface:    %s, via: LLDP, RID: 1, Time: 0 day, 00:%02d:%02d\n  Chassis:\n    ChassisID:    mac %s\n    SysName:      %s\n    SysDescr:     %s\n    Capability:   %s, on\n  Port:\n    PortID:       ifname %s\n    PortDescr:    %s\n    TTL:          120\n" % [
			i.name, (Game.cycle * 3) % 60, (Game.cycle * 17) % 60, far.dev.ifaces[0].mac.to_lower(), far.dev.name,
			String(Game.MODELS.get(far.dev.model, {}).get("label", far.dev.model)),
			"Bridge" if far.dev.type == "switch" else ("Router" if far.dev.type in ["router", "firewall"] else "Station"), far.name, far.name]
		out += rule
	return out if any else rule + "LLDP neighbors:\n" + rule

func _bond(t: Array) -> String:
	if t.size() < 3:
		return "bond <iface> <iface>   (real: ip link add bond0 type bond mode 802.3ad; ip link set eth0 master bond0)\n"
	var legs: Array = []
	for nm in t.slice(1):
		var found := _iface(String(nm))
		if found == null:
			return "bond: no interface %s\n" % nm
		legs.append(found)
	var gid := 1
	for i2: Net.Iface in dev.ifaces:
		gid = maxi(gid, i2.lag + 1)
	for idx in legs.size():
		var leg: Net.Iface = legs[idx]
		leg.lag = gid
		if idx > 0:
			leg.mac = legs[0].mac  # a bond presents one address
	Game.topology_changed.emit()
	return "bond%d: %s\n" % [gid, " ".join(PackedStringArray(t.slice(1)))]

func _bond_status() -> String:
	var members: Array = []
	for i: Net.Iface in dev.ifaces:
		if i.lag > 0:
			members.append(i)
	if members.is_empty():
		return "cat: /proc/net/bonding/bond0: No such file or directory\n"
	var out := "Ethernet Channel Bonding Driver: v%s\n\nBonding Mode: IEEE 802.3ad Dynamic link aggregation\nTransmit Hash Policy: layer2 (0)\nMII Status: up\nMII Polling Interval (ms): 100\nUp Delay (ms): 0\nDown Delay (ms): 0\n\n802.3ad info\nLACP active: on\nLACP rate: slow\nMin links: 0\nAggregator selection policy (ad_select): stable\n" % KERNEL
	for m in members:
		out += "\nSlave Interface: %s\nMII Status: %s\nSpeed: %d Mbps\nDuplex: full\nLink Failure Count: 0\nPermanent HW addr: %s\nSlave queue ID: 0\nAggregator ID: 1\n" % [m.name, "up" if _up(m) else "down", Game.iface_speed(m), m.mac.to_lower()]
	return out

# ---------- game verbs ----------

func _vm(t: Array) -> String:
	if t.size() >= 3 and t[1] == "create":
		var nic := Game.create_vm(dev, t[2])
		if nic == null:
			return "vm: could not create '%s' (servers only, names are unique)\n" % t[2]
		return "vm '%s' created with MAC %s\n" % [t[2], nic.mac]
	if t.size() == 4 and t[1] == "addr":
		var nic2 := Game.find_vm(t[2])
		if nic2 == null or nic2.dev != dev:
			return "vm: '%s' does not run here\n" % t[2]
		if Game.add_ip(nic2, t[3]):
			return ""
		return "vm: invalid or duplicate address\n"
	if t.size() == 4 and t[1] == "migrate":
		var target: Net.NDevice = null
		for d in Game.all_devices():
			if d.name == t[3]:
				target = d
		if target == null:
			return "vm: no host called '%s'\n" % t[3]
		var err := Game.migrate_vm(t[2], target)
		if err != "":
			return "vm: %s\n" % err
		return "vm '%s' now runs on %s. Its addresses came with it.\n" % [t[2], t[3]]
	if t.size() >= 2 and t[1] == "list":
		var out := ""
		for d in Game.all_devices():
			for i: Net.Iface in d.ifaces:
				if i.vm != "":
					out += "%-14s on %-10s %-19s %s\n" % [i.vm, d.name, i.mac,
						", ".join(PackedStringArray(i.ips))]
		return out if out != "" else "(no virtual machines)\n"
	return "usage: vm create <name> | vm addr <name> <cidr> | vm migrate <name> <host> | vm list\n"

func _cert(t: Array) -> String:
	var certs: Dictionary = Game.certs_on(dev)
	if t.size() >= 3 and t[1] == "issue":
		var life := int(t[3]) if t.size() > 3 and String(t[3]).is_valid_int() \
			else Game.CERT_LIFE
		var cerr := Game.issue_cert(dev, String(t[2]), life)
		return "cert: %s\n" % cerr if cerr != "" \
			else "issued %s, good for %d cycles\n" % [t[2], life]
	if t.size() == 3 and t[1] == "renew":
		if not certs.has(t[2]):
			return "cert: no certificate named %s\n" % t[2]
		Game.issue_cert(dev, String(t[2]))
		return "renewed %s\n" % t[2]
	if t.size() == 4 and t[1] == "auto" and String(t[3]) in ["on", "off"]:
		if not certs.has(t[2]):
			return "cert: no certificate named %s\n" % t[2]
		certs[t[2]]["auto"] = String(t[3]) == "on"
		Game.topology_changed.emit()
		return "%s renewal for %s\n" % ["automatic" if t[3] == "on" else "manual", t[2]]
	if t.size() >= 2 and t[1] == "list" or t.size() == 1:
		if certs.is_empty():
			return "(no certificates on this host)\n"
		var cout := "%-24s %-10s %s\n" % ["NAME", "EXPIRES", "RENEWAL"]
		for cname in certs:
			var left: int = int(certs[cname]["expires"]) - Game.cycle
			cout += "%-24s %-10s %s\n" % [cname,
				"EXPIRED" if left <= 0 else "%d cycles" % left,
				"automatic" if bool(certs[cname].get("auto", false)) else "by hand"]
		return cout
	return "usage: cert issue <name> [cycles] | cert renew <name> | cert auto <name> on|off | cert list\n"

func _console(t: Array) -> String:
	if dev.type != "console":
		return "console: this is not a console server\n"
	var attached: Array = []
	for ci: Net.Iface in dev.ifaces:
		if not ci.name.begins_with("console"):
			continue
		var cl := Game.link_at(ci)
		if cl == null:
			continue
		attached.append([ci.name, cl.other(ci).dev])
	if t.size() >= 2 and t[1] == "list" or t.size() == 1:
		if attached.is_empty():
			return "no serial cables: run one from a console port to a device\n"
		var cout := "%-12s %s\n" % ["PORT", "DEVICE"]
		for row in attached:
			cout += "%-12s %s\n" % [row[0], row[1].name]
		return cout
	if t.size() == 2:
		for row2 in attached:
			var target: Net.NDevice = row2[1]
			if target.name == String(t[1]):
				# a serial console does not care about IP at all,
				# which is the entire reason it is worth having
				pending_ssh = target
				return "Connected to %s over %s. Press Ctrl-D or 'exit' to return.\n" \
					% [target.name, row2[0]]
		return "console: nothing named %s is cabled to this console server\n" % t[1]
	return "usage: console list | console <device>\n"

func _snmpwalk(args: Array) -> String:
	## snmpwalk -v2c -c <community> <address>, or the old positional pair
	var community := ""
	var addr := ""
	var k := 0
	while k < args.size():
		var a := String(args[k])
		if a == "-c" and k + 1 < args.size():
			community = String(args[k + 1])
			k += 2
			continue
		if a.begins_with("-v") or a.begins_with("-"):
			k += 1
			continue
		if addr == "":
			addr = a
		elif community == "":
			community = a
		k += 1
	if addr == "" or community == "":
		return "USAGE: snmpwalk [OPTIONS] AGENT [OID]\n  snmpwalk -v2c -c <community> <address>\n"
	var poll := Sim.snmp_poll(dev, addr, community)
	if not bool(poll["ok"]):
		return "snmpwalk: %s\n" % poll["why"]
	var out_s := "iso.3.6.1.2.1.1.1.0 = STRING: \"%s\"\niso.3.6.1.2.1.1.5.0 = STRING: \"%s\"\niso.3.6.1.2.1.1.3.0 = Timeticks: (%d) %s\n" % [
		poll["model"], poll["name"], Game.cycle * 360000, "%d:00:00.00" % Game.cycle]
	var n := 1
	for i3 in poll["ifaces"]:
		out_s += "iso.3.6.1.2.1.2.2.1.2.%d = STRING: \"%s\"\niso.3.6.1.2.1.2.2.1.8.%d = INTEGER: %s\niso.3.6.1.2.1.2.2.1.10.%d = Counter32: %d\niso.3.6.1.2.1.2.2.1.16.%d = Counter32: %d\n" % [
			n, i3["name"], n, "up(1)" if bool(i3["up"]) else "down(2)", n, int(i3["rx"]) * 148, n, int(i3["tx"]) * 148]
		n += 1
	return out_s

func _wifi(t: Array) -> String:
	if String(t[0]) == "nmcli":
		# nmcli dev wifi connect SSID
		if t.size() >= 5 and String(t[1]).begins_with("d") and String(t[2]) == "wifi" and String(t[3]) == "connect":
			var err := Game.wifi_join(dev, String(t[4]))
			return "Device 'wlan0' successfully activated with '%s'.\n" % _fake_key(t[4]).substr(0, 8).to_lower() if err == "" else "Error: Connection activation failed: (7) %s\n" % err
		if t.size() >= 3 and String(t[1]).begins_with("d") and String(t[2]) == "wifi":
			return "IN-USE  BSSID              SSID          MODE   CHAN  RATE        SIGNAL  BARS  SECURITY\n%s       02:50:45:ac:ce:55  %-13s Infra  6     130 Mbit/s  80      ▂▄▆_  WPA2\n" % ["*" if dev.wifi != "" else " ", dev.wifi if dev.wifi != "" else "(none)"]
		if t.size() >= 4 and String(t[1]).begins_with("d") and String(t[2]) == "disconnect":
			Game.wifi_leave(dev)
			return "Device 'wlan0' successfully disconnected.\n"
		return "Usage: nmcli dev wifi [list | connect <ssid>] | nmcli dev disconnect wlan0\n"
	if t.size() == 3 and t[1] == "join":
		var err := Game.wifi_join(dev, t[2])
		return "associated with '%s'\n" % t[2] if err == "" else "wifi: %s\n" % err
	if t.size() >= 2 and t[1] == "leave":
		Game.wifi_leave(dev)
		return "disassociated\n"
	if t.size() >= 2 and t[1] == "status":
		return "associated with '%s'\n" % dev.wifi if dev.wifi != "" \
			else "not associated\n"
	return "usage: wifi join <ssid> | wifi leave | wifi status   (real: nmcli dev wifi connect <ssid>)\n"

func complete(line: String) -> Array:
	var ends_space := line.ends_with(" ")
	var toks := Array(line.strip_edges().split(" ", false))
	var cur: String = "" if ends_space or toks.is_empty() else toks.pop_back()
	var opts: Array = []
	match toks.size():
		0:
			opts = ["ip", "ping", "ping6", "traceroute", "tracepath", "hostname", "hostnamectl", "tcpdump", "dhclient", "dhcpd",
				"dns", "nslookup", "dig", "host", "cat", "echo", "resolvectl", "ss", "sysctl", "systemctl", "journalctl",
				"curl", "nc", "telnet", "lldp", "lldpcli", "ssh", "syslogd", "logging", "logs", "ntpd", "chronyc", "vm", "wg", "wg-quick",
				"wifi", "nmcli", "radiusd", "igmp", "bond", "snmpd", "snmpwalk", "flows", "console", "aaad", "cert", "autoconf",
				"uname", "sudo", "iptables", "nft", "ufw", "exit", "clear", "help"]
		1:
			match String(toks[0]):
				"ip":
					opts = ["addr", "link", "route", "neigh", "maddr", "-br", "-6", "-4", "-s"]
				"vm":
					opts = ["create", "addr", "migrate", "list"]
				"systemctl":
					opts = ["status", "start", "stop", "restart", "enable", "disable"]
				"cat":
					opts = ["/etc/resolv.conf", "/etc/hosts", "/etc/dhcp/dhcpd.conf", "/var/lib/dhcp/dhcpd.leases", "/proc/sys/net/ipv4/ip_forward", "/etc/wireguard/wg0.conf"]
				"wg":
					opts = ["show", "set", "genkey", "pubkey"]
				"resolvectl":
					opts = ["status", "dns", "flush-caches", "query"]
		2:
			if toks[0] == "ip" and String(toks[1]).begins_with("a"):
				opts = ["show", "add", "del", "flush"]
			elif toks[0] == "ip" and String(toks[1]).begins_with("r"):
				opts = ["show", "get", "add", "del", "replace"]
			elif toks[0] == "ip" and String(toks[1]).begins_with("l"):
				opts = ["show", "set", "add"]
			elif toks[0] == "ip" and String(toks[1]).begins_with("n"):
				opts = ["show", "flush"]
			elif toks[0] == "systemctl":
				opts = ["isc-dhcp-server", "dnsmasq", "ssh", "rsyslog", "chrony", "snmpd"]
		_:
			if toks.size() >= 2 and (String(toks[-1]) == "dev" or String(toks[-1]) == "-i"):
				for i: Net.Iface in dev.ifaces:
					opts.append(i.name)
	var out: Array = []
	for o in opts:
		if String(o).begins_with(cur):
			out.append(o)
	out.sort()
	return out
