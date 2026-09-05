# Packet Empire

A datacenter-tycoon game that teaches real network engineering, built with
Godot 4. You start with a few rack units in a colocation corner and grow into
your own datacenter floor: by actually configuring switches, routers,
firewalls and servers, on real(istic) CLIs, over a real packet-level
simulation.

## Run

```sh
godot --path .          # or open in the Godot 4 editor (4.7+)
```

macOS: `/Applications/Godot.app/Contents/MacOS/Godot --path .`

## The demo

Picking **Play the demo** on the title screen runs the opening arc of the
campaign: rack and stack, first ping, VLAN isolation, trunking two switches,
a redundant core that survives a cut cable, and routing two offices together.
Six jobs, roughly half an hour, ending on a card that says what the full game
carries on into. Every job has a live checklist in the corner and a hint you
can ask for if you get stuck.

Saves live in three named slots plus an autosave written every five cycles.

## Play

- **Q** select · **R** place rack · right/middle-drag pan · scroll zoom · **Esc** back
- Click a rack → cabinet view → install hardware into U-slots
- Click a device → front panel; click a port → interface editor / run cables
- Every device has a working console (**Open console**), with tab completion
  and command history
- **Map (M)** shows the logical topology: trunks, STP-blocked links,
  congestion; **Learn** opens the in-game encyclopedia; **ssh** between
  devices from any console; **?** lists possibilities Cisco-style
- **Contracts** (top bar) drives the campaign: each mission's brief teaches the
  commands it needs. Marketplace customers arrive with needs and hidden
  budgets: quote a price per revenue cycle; delivery is verified against the
  live simulation every cycle, and only working services pay.

## Running the place

The network is half the job. The other half is the company around it:

- **Customers who remember.** Named accounts arrive, grow, ask for something
  specific, and either become a reference or leave saying why. They describe
  faults the way customers do (`"the internet is broken"`), so a ticket queue
  sits between the complaint and the cause. Their busy night is announced four
  cycles ahead, and carrying it is worth more than the money it pays.
- **Incidents that are not always yours.** Grey failures (a dirty optic, a
  loose connector, a damaged pair, an MTU somebody changed) stay up and lie,
  and are diagnosed from counters, light levels and `ping -s`. Upstream
  outages you cannot fix at all, only communicate. Firmware defects that need
  a vendor case, evidence, and level one asking for the log bundle again.
- **The facility.** Filters, aircon service, generator load tests and UPS
  checks on a visible schedule; fire, smoke and water with detection,
  suppression and drainage; badges, cameras and contractors on the floor.
- **The paperwork.** Documentation that drifts out of date and makes
  everything slower, renewals and licences that lapse quietly, compliance
  controls proved from the live simulation, and an audit that grades them.
- **The people.** Staff with shifts, morale, and habits copied from what they
  watch you do; a standing duties board that trades money and control for
  time; blame after a human outage, which decides who reports the next one.
  When nobody is on shift and something is live, you can phone somebody at
  three in the morning: it costs a call-out fee and it costs their morale.
- **More than one room.** Each floor keeps its own facility diary, its own
  fire and water protection, its own heat and draw, and its own dock; hardware
  moves between them on a van rather than by teleport, and every panel says
  which floor it is talking about.
- **Proving it.** A failover test you book, announced ahead so it can be
  prepared for: the upstream goes away on purpose and the result is judged on
  whether customers noticed. Strict-tier customers ask for it in writing, an
  auditor asks when it last passed, and a shift that ends leaves a handover
  for the one coming in, which costs you if nobody reads it.
- **A room that shows how it is run.** Tidiness is read off real things
  (blanked gaps, labelled ports, saved configurations) and the floor and the
  cabinets wear it: undressed leads, a carton nobody broke down, a cup on the
  slab, all of it gone once the team keeps on top of it. Somebody signed in at
  the door is a figure with a visitor badge, following an escort if the access
  policy says so. Seasons move cooling headroom, work rate and who is
  available, and the clock and the room say which one you are in.
- **The company.** Four identities that change what work arrives and what it
  costs, decisions whose consequences land cycles later, rivals with grudges
  and favours, an ending with a scored report, and a table of past runs.

## Making it yours

- **Content packs.** Scenarios are JSON: requirements written as data and
  verified against the live simulation, with a workshop that validates,
  previews, reloads and imports them. See `docs/PACKS.md`.
- **Drills and scenarios.** Incident drills rebuild a known-good network with
  hidden faults, including a services incident where nothing is unplugged and
  the client still gets no address and no name. The set pieces are longer: an
  inherited ISP, a campus wireless build, an audit, and an IPv6-only customer
  who needs native v6, a name that answers, and a translator for the partner
  nobody will renumber.
- **Challenges.** Any drill is a short code (`PE1-31-abc`) that rebuilds the
  same network and faults anywhere, scored on recovery, time, configuration
  changes, hints and collateral.
- **Export.** The topology exports as a Mermaid diagram and a plain listing;
  a broken network exports as a puzzle somebody else can load and hand back.
- **Language.** A catalogue with English and Hungarian, switchable at runtime
  from the title screen or in game, and a pseudo-locale for finding clipped
  layouts. The title, settings and onboarding copy are translated; the
  operational panels are still English, and the catalogue is where to add them.

## What's simulated

- **L2**: MAC learning per VLAN, flooding, access/trunk tagging with allowed
  lists, spanning tree with bridge priority, RSTP and MST per-instance trees,
  LACP bundles, MLAG pairs for dual-homed servers, IGMP snooping for multicast
- **L3**: ARP, ICMP with TTL, longest-prefix routing (connected/static),
  routers and stateless-ACL firewalls, source NAT (masquerade)
- **Dynamic routing**: eBGP-lite to an ISP handoff (transit fees, prefix
  announcements, default via BGP), single-area OSPF, and BFD so a router
  notices that the far end of a link has died
- **Overlays**: VXLAN VTEPs with VLAN-to-VNI mapping over a routed underlay,
  and EVPN-lite so the leaves advertise what is behind them instead of
  flooding; passive patch panels that are invisible to packets and traceable
  by hand
- **IPv6 transition**: dual stack, DNS64 synthesis from A records, and a
  stateful NAT64 translator with its own counters and failure reasons
- **Services**: DHCP over real broadcast, DNS with A records and resolvers
- **HA & scale**: VRRP virtual gateways with priority election and failover,
  link speeds (1G/10G/100M) with per-cycle load placement and congestion
- **Ops**: A and B power feeds with dual-supply gear and a UPS, power draw and
  cooling capacity (overheating trips gear), SNMP agents and a station that
  polls them, netflow-style top talkers, invoicing with real payment terms, SLA
  re-verification, security incidents when customer machines can reach your
  management addresses (switches have OOB Management ports), on-call field
  faults, reputation that moves customer budgets, bank loans with interest

## Vendor dialects

The CLI depends on what you buy, like real life:

| Gear | Dialect |
|---|---|
| PacketTik (budget) | RouterOS 7 (`/interface bridge vlan add …`, `/routing ospf interface-template add …`, `/routing bgp connection add …`, `export`); the syntax is the real one, so it transfers to a CHR |
| OpenRack / Arivista / Junivista / PacketSense | EOS/IOS-style (`conf t`, `show run`, abbreviations) |
| Dill servers | Linux (`ip addr`, `ping`, `dhclient`, `tcpdump`, …) |

## Architecture

| File | Role |
|---|---|
| `scripts/net.gd` | Data model (NetBox-style: racks → devices → interfaces; cables terminate on interfaces) |
| `scripts/game.gd` | Autoload: single source of truth, money/stages, save/load, revenue cycle |
| `scripts/netsim.gd` | The packet simulation (frames, ARP, ICMP, STP, BGP, OSPF, NAT, DHCP, DNS) |
| `scripts/cli.gd` / `cli_ros.gd` | EOS + Linux sessions / RouterOS sessions |
| `scripts/contracts.gd` / `market.gd` | Campaign missions / generated customer offers |
| `scripts/ui.gd` / `ui_widgets.gd` | All UI / custom-drawn rack & faceplate widgets |
| `scripts/pack.gd` / `loc.gd` / `challenge.gd` | Authored content, localisation catalogue, reproducible drills |
| `scripts/legacy.gd` / `puzzle.gd` / `skills.gd` | What survives a run, exported outages, named skills |
| `scripts/world.gd`, `floor.gd`, `rack_visual.gd`, `camera.gd`, `iso.gd` | Isometric floor scene |
| `scripts/test_sim.gd` | Integration suite |

CLI and UI mutate the same `Game` state: they can never disagree.

The simulation layer (`net.gd`, `netsim.gd`, `cli.gd`, `cli_ros.gd`,
`pedia.gd`, about 4500 lines) has no dependency on any tycoon system and can
be lifted into a different game wholesale. `docs/REUSE.md` lists exactly what
a host game has to provide.

## Recording a showcase

`./run_film.sh /tmp/film packet-empire.mp4` plays a scripted tour of the game
and records every rendered frame with a caption strip: the floor and the people
on it, cabinets that wear their own tidiness, a second building with its own
colour and its own dock, the map, a booked failover test, the phone ringing out
of hours, the handover, an incident spanning two rooms, and the trend read. It
needs ffmpeg; the frames are deleted afterwards.

## Tests

```sh
PACKET_TEST=1 godot --headless --path . --quit-after 600
```

Or `./run_tests.sh`, which is the same thing with the exit code checked.
`PACKET_TEST=probe` runs `SimTests.probe()` alone (a scratch scenario for
chasing one failure fast), and `PACKET_TEST=replay PACKET_REPLAY=<file>` runs
a command script against a fresh device and prints the transcript, which is
what `tools/lab/` uses to diff the game's dialects against real RouterOS and
cEOS in containerlab.

Over 2100 integration checks across the simulation, all three CLI dialects,
the campaign, the marketplace, every operational system above, and a UI smoke
pass that opens every screen (including in pseudo-localisation). Exit code 0 =
green. Tests write their own save, history and pack files, never the
player's.

## Contributing / roadmap

Work is tracked in GitHub issues. Every change request becomes an issue first;
commits close them.
