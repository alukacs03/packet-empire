class_name Demo
## The demo build: the opening arc of the campaign, start to finish, and a
## closing card at the end of it. Everything here is a filter over the real
## campaign rather than a separate mode, so the demo is the actual game.

## The arc, in order: rack and stack, switching, VLANs, trunks, spanning tree,
## routing between subnets. Roughly half an hour, and it ends on a win.
const ARC := ["rackup", "first_ping", "two_tenants", "stretch_vlans",
	"redundant_core", "two_offices"]

## What the closing card promises, taken from what the full game actually has.
const BEYOND := [
	"DHCP, DNS, NAT and a real BGP session with an upstream",
	"IPv6, OSPF, VRRP, MLAG, WireGuard and 802.1X",
	"Customers who negotiate, rivals who undercut you, and companies you can buy",
	"Power, cooling, staff, insurance and a quarterly profit and loss",
	"Two more floors to grow into, and other cities to reach with WAN circuits",
	"A second building that is a different place: its own diary, its own fire protection, its own dock",
	"Nights somebody has to cover, a phone that rings at three, and the shift note the next crew reads",
	"A failover test you book, that takes your upstream away on purpose to find out whether any of it works",
]

static func begin() -> void:
	Game.demo = true
	Game.log_event("DEMO: the opening arc. Six jobs, then the demo ends.")

static func active() -> bool:
	return Game.demo

static func step() -> int:
	## how many arc jobs are behind you
	var done := 0
	for id in ARC:
		if id in Game.contracts_done:
			done += 1
	return done

static func complete() -> bool:
	return active() and step() >= ARC.size()

static func progress_text() -> String:
	return "Demo  %d/%d" % [step(), ARC.size()]

static func visible_contracts(all_of_them: Array) -> Array:
	## in the demo the campaign stops at the end of the arc, so nothing
	## dangles in the list that the player cannot reach
	if not active():
		return all_of_them
	var out: Array = []
	for c in all_of_them:
		if String(c["id"]) in ARC:
			out.append(c)
	return out
