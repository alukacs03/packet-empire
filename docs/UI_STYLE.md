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
- `UIW.CommandPanel` is the authored chamfered frame for major screens;
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
