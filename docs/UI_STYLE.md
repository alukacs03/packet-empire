# Packet Empire UI foundation

The shared visual language lives in `scripts/ui_widgets.gd` under `UIW`.
New screens should use those tokens and helpers instead of copying style-box
construction or literal colours.

## Tokens

- `UIW.colour(name)` provides surface, text, accent, focus, and semantic
  colours (`success`, `warning`, `danger`, `info`).
- `UIW.space(name)` uses `xs`, `sm`, `md`, `lg`, and `xl` spacing. Primary
  surfaces use at least `md` (16 px) internally and `lg` (24 px) between
  unrelated regions; empty space is part of the hierarchy, not unused room.
- `UIW.type_size(name)` uses `caption`, `small`, `body`, `body_large`,
  `heading`, `title`, and `display` type roles.
- `UIW.radius(name)` uses `sm`, `md`, and `lg` corner radii.

These names describe purpose rather than a particular screen. Add a token only
when an existing semantic role cannot express the design.

## Components

- `UIW.make_theme()` supplies normal, hover, pressed, focus, and disabled
  control states plus line-edit and tooltip styling.
- `UIW.style_button(button, variant)` supports `default`, `primary`, `quiet`,
  and `danger`.
- `UIW.style_panel(panel, variant, padding)` supports `surface`, `overlay`,
  `hud`, `console`, `positive`, `warning`, and `danger`.
- `UIW.CommandPanel` is the rounded, shadowed frame with a restrained accent edge for major screens;
  `UIW.ActionButton` is the numbered, two-level title/navigation action.
- `UIW.make_text`, `make_section`, `make_empty_state`, and `make_chip` cover
  the repeated text/status patterns.
- `UIW.custom_box` is the escape hatch for physical hardware art and other
  genuinely unique shapes. It should not be the first choice for application
  cards or controls.

## Example

```gdscript
var card := PanelContainer.new()
UIW.style_panel(card, "surface", "md")

var action := Button.new()
action.text = "Check requirements"
UIW.style_button(action, "primary")

card.add_child(UIW.make_empty_state("No alerts need attention."))
```

All interactive controls must retain a visible focus state. Semantic colour
must reinforce text or icons rather than being the only carrier of meaning.

## Workspace layout and customer decisions

The persistent left rail owns navigation; ordinary workspaces leave it and
the status bar clickable. Their remaining background consumes clicks so that
working in a panel cannot accidentally place hardware on the floor. Modal
menus retain the full scrim. Highlight the visible workspace, not the last
floor tool used.

Cards start after the rail and keep their preferred width. Use wrapping action
rows (`HFlowContainer`) when device actions would force a card wider. The
customer brief may share a wide viewport only when actual panel bounds leave
room for it; on smaller screens it returns when the workspace closes. The
status bar carries the active customer's deadline while the brief is hidden.
Hazards and outages still take priority.

Launch choices must display cost, peak demand, and success reward without a
hover or scroll at 1280×720. Keep story text phase-specific. Measure wrapped
paragraph height, and keep the brief's scroll position independent from the
console. Debrief claims use recorded sale evidence, never the current network.

## Rendered regression review

Use an isolated Godot user directory, configured with an ignored `override.cfg`,
so the review cannot touch a player's preferences or save:

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="Packet Empire Design Review"
```

Run the engine with `PACKET_REVIEW=/absolute/output/directory` to capture
twelve real game screens, including a mid-sale outage, and run layout/input assertions. Set
`PACKET_REVIEW_SIZE=1280` with `--resolution 1280x720` to test a genuinely
smaller logical viewport, not just a scaled 1600×900 image. Set
`PACKET_REVIEW_LANGUAGE=hu` to check Hungarian. Otherwise the review uses
English and the project viewport. A failing assertion exits nonzero.

This fixture-based review checks presentation and interactions, not whether
the campaign feels fun to a new player. Pair it with the human sessions in
`docs/PLAYTEST.md`; do not treat automated completion as a playtest result.

## Environmental progression

The facility is part of the campaign's feedback. Stage 0 uses the authored
`starter_colo_room.png`: worn concrete, edge clutter, warm practical fixtures,
and deliberately unstable light. Progress cross-fades toward
`mature_colo_room.png`: clean surfaces, managed cable paths, cold stable light,
and less visual noise. Racks, cable runs, labels, and floor accents interpolate
along the same warm-to-cold arc.

Do not place a second opaque floor slab over the starter environment. Its
placement grid is a low-opacity overlay painted directly onto the illustrated
floor. Raised modular flooring belongs to later facility stages, where it is a
visible upgrade rather than unexplained decoration.
