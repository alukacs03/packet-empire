# Reusing the network simulation in another game

The networking half of Packet Empire does not know it is in a tycoon game.
Nothing in it references contracts, customers, rivals, staff, money or the
campaign. If you want to build a different game on the same simulation (a
freelancer working through client sites, a training sandbox, a puzzle game
about outages), you can take the whole of it and supply your own economy.

## What you take

| File | Lines | What it is |
|---|---|---|
| `scripts/net.gd` | ~280 | The data model: sites, racks, devices, interfaces, links, plus address maths (v4 and v6) and port-range formatting. Pure data and pure functions; no dependency on anything else at all. |
| `scripts/netsim.gd` | ~1600 | The simulation: frames, MAC learning, VLAN tagging, spanning tree (STP/RSTP/MST), LACP and MLAG, ARP/NDP, ICMP with TTL, routing with longest-prefix, local-pref and ECMP, NAT, VRFs, DHCP, DNS with delegation and TTLs, BGP with policy and RPKI, OSPF, VRRP, tunnels, WireGuard, 802.1X, QoS, MTU, multicast, BFD, SNMP. |
| `scripts/cli.gd` | ~2100 | Two dialects: EOS/IOS-style (modes, abbreviation, interface ranges) and Linux (`ip`, `ping`, `tcpdump`, `dhclient`, …). |
| `scripts/cli_ros.gd` | ~1300 | The RouterOS dialect: menus, universal verbs, print shapes, `export`. |
| `scripts/cli_linux.gd` | ~1100 | The Linux host shell: iproute2, iputils, tcpdump, ISC DHCP, resolver files, wireguard-tools. |
| `scripts/pedia.gd` | ~70 | The encyclopedia articles. Text only; keep the ones that suit your game. |

That is roughly 4500 lines with no tycoon coupling.

## What you must provide

The simulation reads and writes the world through a single autoload named
`Game`. That is the only seam. Register your own script as `Game` in
`project.godot` and implement the following. Nothing else is called.

### State

| Member | Type | Meaning |
|---|---|---|
| `topology_changed` | `signal` | Emitted whenever anything about the world changes. The sim connects `Sim.flush_learned_state` to it, which is how MAC tables, ARP caches and spanning tree are invalidated. **Emit it or nothing will reconverge.** |
| `all_devices()` | `-> Array[Net.NDevice]` | Every device in the world. |
| `links` | `Array[Net.Link]` | Every cable. |
| `link_at(iface)` | `-> Net.Link` | The cable on an interface, or `null`. |
| `peer_label(iface)` | `-> String` | Human-readable far end, `""` if unplugged. Used by CLI output only. |
| `cycle` | `int` | A monotonically increasing tick. Used for DNS TTL expiry, BFD/STP convergence holds and log timestamps. Increment it however your game measures time. |
| `MODELS` | `Dictionary` | Device catalogue. The sim reads `label`, `ports`, `speed`, `os` and `type`. |
| `iface_speed(iface)` | `-> int` | Mbit/s of a port. |
| `link_latency_ms(link)` | `-> float` | Latency contribution, for ping timings. |
| `hijacks` | `Array` | Active BGP hijacks; `[]` is fine if your game has none. |

### Mutation

These exist so the CLI can change the world in exactly the same way the UI
does, which is what keeps the two from ever disagreeing.

`add_ip` · `remove_ip` · `add_vlan` · `remove_vlan` · `set_access_vlan` ·
`add_static_route` · `remove_static_route` · `add_svi` · `add_subiface` ·
`add_vrf` · `set_iface_vrf` · `add_tunnel` · `add_wireguard` ·
`rename_device` · `set_ssid` · `wifi_join` · `wifi_leave` ·
`create_vm` · `find_vm` · `migrate_vm` · `lb_health_check`

### Configuration management

`device_config` · `apply_device_config` · `config_diff` ·
`save_config_version` · `templates` · `save_template` · `apply_template`

These back `write memory`, `show run`, `configure replace` and the
version-rollback commands. If your game has no notion of saved configuration,
stub them: return `{}` and do nothing.

### Logging

`log_event(text)` · `device_log(device, text)`

`log_event` is world-level (what the player sees in a log panel);
`device_log` is per-device (what `show logging` prints). Both can be a single
`print` while you are getting started.

## What you leave behind

`game.gd`, `contracts.gd`, `market.gd`, `rivals.gd`, `staff.gd`, `drill.gd`,
`scenarios.gd`, `demo.gd`, and everything under the UI and isometric-floor
scripts. Those are this game.

## The seam is deliberate

Every fact about the network lives in `Net` objects, and both the CLI and the
UI mutate the same objects through `Game`. There is no second copy of the
state and no synchronisation step, which is why typing `switchport access
vlan 10` and clicking the same thing in a port editor cannot produce
different results. Keep that property in whatever you build on top: if you
add a UI control, have it call the same `Game` method the CLI calls.

## Tests come too

`scripts/test_sim.gd` is one headless suite of several hundred checks over
the simulation and all three dialects. Most of it constructs racks and
devices directly and asserts on `Sim` results, so it ports with the
simulation and tells you immediately whether your `Game` implementation is
complete enough.
