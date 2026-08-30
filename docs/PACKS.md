# Writing a content pack

A pack is one JSON file. Nothing in it is executed: the game reads it,
checks it, and evaluates the requirements against the live simulation, the
same way the built-in campaign is checked. That is the whole security model,
and it is why the vocabulary below is deliberately small.

Put your file in `user://packs/` (the game's user directory) or, if you are
working in the repository, in `packs/`. The content workshop in the system
menu lists what was found, reloads without a restart, imports a pack from the
clipboard, and copies a diagnostic report for anything that would not load.

## The smallest possible pack

```json
{
  "id": "classroom.minimal",
  "name": "Minimal classroom pack",
  "schema": 1,
  "author": "you",
  "description": "Copy this, change the objective, play it.",
  "scenarios": [
    {
      "id": "one_ping",
      "title": "One ping",
      "brief": "Make 10.90.0.10 reach 10.90.0.11.",
      "reward": 200,
      "requirements": [
        {"kind": "reachable", "from": "10.90.0.10", "to": "10.90.0.11"}
      ]
    }
  ]
}
```

Scenario ids are namespaced by the pack id, so `classroom.minimal.one_ping`
is stable across everybody's installs.

## Requirements

Every requirement is one of these, and they compose with `all`, `any`, `not`:

| kind | fields | means |
| --- | --- | --- |
| `device_count` | `type`, `min` | at least this many of a type or model are installed |
| `link_between` | `a`, `b` | those two devices are cabled together (through panels counts) |
| `reachable` | `from`, `to` | the address at `from` can ping `to` |
| `not_reachable` | `from`, `to` | and the isolation case, which is how you prove segmentation |
| `has_address` | `ip` | something on the floor holds that address |
| `vlan_access` | `vid` | there is a connected access port in that VLAN |
| `config_saved` | `device` | that device is not running an unsaved configuration |
| `money_at_least` | `amount` | the bank balance is at least that |
| `survives_link_loss` | `a`, `b`, `from`, `to` | `from` still reaches `to` with the `a`–`b` link down |
| `survives_device_loss` | `device` or `owner_of`, `from`, `to` | `from` still reaches `to` with that device switched off. Prefer `owner_of` (an address): naming a device by name breaks in somebody else's world |
| `resolves` | `from`, `name`, optional `to`, `v6`, `reach` | `from` looks the name up and (unless `reach` is false) reaches the answer; `to` pins the address, `v6` asks for AAAA |

Each one produces a readable line for the checklist and a specific reason
when it fails, so a player is told what is missing rather than that something
is wrong.

## Actions

`setup` runs when a scenario starts, `on_complete` when it is finished:

| kind | fields | does |
| --- | --- | --- |
| `message` | `text` | writes a line into the event log |
| `reward` | `amount` | pays the player |
| `break_link` | `device`, optional `iface` | takes one live port down, deterministically |
| `restore_links` | | brings every administratively down port back |

## Three shapes worth copying

The bundled `packs/starter.json` contains all three: a minimal mission
(`rack_and_stack`), a multi-step lab (`first_light`, `two_tenants`), and an
incident drill (`night_call`, which uses `setup` to break something and a
single reachability requirement to close it).

## Sharing

The workshop copies a pack to the clipboard with nothing about your machine
in it, and imports one the same way. A pack is plain JSON, so it also travels
fine in a gist, an email, or a classroom handout. Anything you write is yours;
the bundled starter pack is offered as a template to copy from freely.
