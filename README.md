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

## Play

- **Q** select · **R** place rack · right/middle-drag pan · scroll zoom · **Esc** back
- Click a rack → cabinet view → install hardware into U-slots
- Click a device → front panel; click a port → interface editor / run cables
- Every device has a working console (**Open console**), with tab completion
  and command history
- **Contracts** (top bar) drives the campaign: each mission's brief teaches the
  commands it needs. Marketplace customers arrive with needs and hidden
  budgets: quote a price per revenue cycle; delivery is verified against the
  live simulation every cycle, and only working services pay.

## What's simulated

- **L2**: MAC learning per VLAN, flooding, access/trunk tagging with allowed
  lists, spanning tree (root election, blocked ports, failover)
- **L3**: ARP, ICMP with TTL, longest-prefix routing (connected/static),
  routers and stateless-ACL firewalls, source NAT (masquerade)
- **Dynamic routing**: eBGP-lite to an ISP handoff (transit fees, prefix
  announcements, default via BGP) and single-area OSPF
- **Services**: DHCP over real broadcast, DNS with A records and resolvers
- **Ops**: power draw and cooling capacity (overheating trips gear), SLA
  re-verification, security incidents when customer machines can reach your
  management addresses, reputation that moves customer budgets

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

## Tests

```sh
PACKET_TEST=1 godot --headless --path . --quit-after 600
```

100+ integration checks over the sim, all three CLI dialects, contracts,
marketplace, save/load. Exit code 0 = green. Tests write their own save file
(`save_test.json`), never the player's.

## Contributing / roadmap

Work is tracked in GitHub issues. Every change request becomes an issue first;
commits close them.
