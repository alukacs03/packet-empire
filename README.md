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

## What's simulated

- **L2**: MAC learning per VLAN, flooding, access/trunk tagging with allowed
  lists, spanning tree with bridge priority, RSTP and MST per-instance trees,
  LACP bundles, MLAG pairs for dual-homed servers, IGMP snooping for multicast
- **L3**: ARP, ICMP with TTL, longest-prefix routing (connected/static),
  routers and stateless-ACL firewalls, source NAT (masquerade)
- **Dynamic routing**: eBGP-lite to an ISP handoff (transit fees, prefix
  announcements, default via BGP), single-area OSPF, and BFD so a router
  notices that the far end of a link has died
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
| PacketTik (budget) | RouterOS-style (`/interface print`, `/ip address add …`, `export`) |
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
| `scripts/world.gd`, `floor.gd`, `rack_visual.gd`, `camera.gd`, `iso.gd` | Isometric floor scene |
| `scripts/test_sim.gd` | Integration suite |

CLI and UI mutate the same `Game` state: they can never disagree.

The simulation layer (`net.gd`, `netsim.gd`, `cli.gd`, `cli_ros.gd`,
`pedia.gd`, about 4500 lines) has no dependency on any tycoon system and can
be lifted into a different game wholesale. `docs/REUSE.md` lists exactly what
a host game has to provide.

## Tests

```sh
PACKET_TEST=1 godot --headless --path . --quit-after 600
```

674 integration checks over the sim, all three CLI dialects, contracts,
marketplace, save/load. Exit code 0 = green. Tests write their own save file
(`save_test.json`), never the player's.

## Contributing / roadmap

Work is tracked in GitHub issues. Every change request becomes an issue first;
commits close them.
