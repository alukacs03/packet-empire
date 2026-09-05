# Conformance lab: the game's dialects against real network operating systems

The PacketTik CLI claims to be RouterOS 7 and the Junivista CLI claims to be
EOS/IOS. This lab is how those claims get checked: the same command scripts
run against real images in containerlab and against the game, and the two
outputs are diffed by eye.

## What you need

- A Linux host with Docker and containerlab (`bash -c "$(curl -sL https://get.containerlab.dev)"`).
- `/dev/kvm`: RouterOS CHR runs as a VM inside its container (vrnetlab).
- A RouterOS CHR disk image (free licence, 1 Mbit/s cap, fine for this) built
  into a `vrnetlab/mikrotik_ros` image: clone https://github.com/hellt/vrnetlab,
  drop `chr-7.x.img` into `routeros/`, `make`.
- Arista cEOS (`ceos:4.32...`) from an Arista account, or swap the `ceos` node
  for `frr` in the topology if you only want the RouterOS half checked.

Nothing here runs on macOS without a Linux VM: KVM is the blocker.

## Run

```
cd tools/lab
sudo containerlab deploy -t packet-lab.clab.yml
./replay.sh            # ssh into every node, run its script, capture to out/
./replay_game.sh       # the same scripts through the game, headless
diff out/r1.real.txt out/r1.game.txt
sudo containerlab destroy -t packet-lab.clab.yml
```

`replay.sh` needs `sshpass` (`apt install sshpass`). Default logins: RouterOS
`admin` with an empty password, cEOS `admin`/`admin`. The Linux host `h1` is
reached with `docker exec`; its script speaks to `eth1` because containerlab
keeps `eth0` for management. Give the container a Debian image with
iproute2, iputils-ping, tcpdump, dnsutils, traceroute and wireguard-tools
installed (`image: debian:12` plus an `apt install` in `exec`) or the
comparison stops at the first missing tool.

## Scripts

`scripts/<node>.txt` holds one command per line. `replay_game.sh` runs the
same file against a fresh game device of the model named on the first line
(`# model: rtr-lite`). Add a line, run both, compare.

Known gaps the game does not try to reproduce: item timing fields (uptime,
adjacency age), MAC addresses, and RouterOS's per-column line wrapping.
