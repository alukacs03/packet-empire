class_name UIW
## Shared UI foundation plus custom-drawn hardware widgets. New screens should
## consume the named tokens and helpers here rather than copy colours/styles.

const COLORS := {
	"accent": Color("39d9d0"),
	"accent_soft": Color("174c5c"),
	"warm": Color("ffb45c"),
	"backdrop": Color(0.025, 0.055, 0.10, 0.76),
	"overlay": Color("13233b"),
	"surface": Color("192b47"),
	"surface_raised": Color("223957"),
	"surface_hover": Color("2b4969"),
	"console": Color("0b1728"),
	"border": Color("395a76"),
	"border_strong": Color("5683a0"),
	"focus": Color("8ff8f0"),
	"text": Color("d9e8f2"),
	"text_strong": Color("fff7e8"),
	"muted": Color("8da7ba"),
	"subtle": Color("66869d"),
	"success": Color("69e39a"),
	"warning": Color("ffb45c"),
	"danger": Color("ff6f68"),
	"info": Color("71b7ef"),
}

const SPACING := {"xs": 4, "sm": 8, "md": 16, "lg": 24, "xl": 36}
const TYPE_SCALE := {"caption": 11, "small": 12, "body": 14, "body_large": 15,
	"heading": 17, "title": 20, "display": 28}
const RADII := {"sm": 4, "md": 7, "lg": 11}

static func colour(token: String) -> Color:
	return COLORS.get(token, COLORS["text"])

static func space(token: String) -> int:
	return int(SPACING.get(token, SPACING["md"]))

static func type_size(token: String) -> int:
	return int(TYPE_SCALE.get(token, TYPE_SCALE["body"]))

static func radius(token: String) -> int:
	return int(RADII.get(token, RADII["md"]))

static func custom_box(bg: Color, border: Color, corner := 7, padding := 8) -> StyleBoxFlat:
	## Flat by default. Depth belongs to whole workspaces, not every nested
	## input, chip, button and metric inside them.
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(corner)
	style.set_content_margin_all(padding)
	style.shadow_size = 0
	return style

static func panel_box(variant := "surface", padding := "md") -> StyleBoxFlat:
	var bg := colour("surface")
	var edge := colour("border")
	var rounding := radius("md")
	match variant:
		"overlay":
			bg = colour("overlay")
			edge = colour("border_strong")
			rounding = radius("lg")
		"hud":
			bg = Color(0.055, 0.105, 0.175, 0.97)
			edge = Color(colour("accent"), 0.62)
			rounding = 0
		"console":
			bg = colour("console")
			edge = Color(colour("border_strong"), 0.8)
		"positive":
			bg = Color("153b38")
			edge = Color(colour("success"), 0.55)
		"warning":
			bg = Color("44351e")
			edge = Color(colour("warning"), 0.7)
		"danger":
			bg = Color("47252d")
			edge = Color(colour("danger"), 0.75)
	var style := custom_box(bg, edge, rounding, space(padding))
	if variant == "overlay":
		style.shadow_color = Color(0.01, 0.025, 0.06, 0.38)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 4)
	# Cards use a clipped technical silhouette and a stronger leading rail.
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.border_width_left = 3
	return style

static func style_panel(panel: PanelContainer, variant := "surface", padding := "md") -> PanelContainer:
	panel.add_theme_stylebox_override("panel", panel_box(variant, padding))
	return panel

static func _button_palette(variant: String) -> Dictionary:
	match variant:
		"primary":
			return {"base": Color("176775"), "edge": colour("accent"),
				"text": colour("text_strong")}
		"danger":
			return {"base": Color("6a2932"), "edge": Color(colour("danger"), 0.9),
				"text": Color(1.0, 0.82, 0.80)}
		"quiet":
			return {"base": Color(0.07, 0.13, 0.22, 0.80), "edge": Color(colour("border"), 0.85),
				"text": colour("text")}
	return {"base": colour("surface_raised"), "edge": colour("border"), "text": colour("text")}

static func style_button(button: Button, variant := "default") -> Button:
	var palette := _button_palette(variant)
	var base: Color = palette["base"]
	var edge: Color = palette["edge"]
	button.add_theme_stylebox_override("normal", custom_box(base, edge, radius("md"), space("sm")))
	button.add_theme_stylebox_override("hover", custom_box(base.lightened(0.10),
		colour("accent"), radius("md"), space("sm")))
	button.add_theme_stylebox_override("pressed", custom_box(base.darkened(0.15),
		colour("accent"), radius("md"), space("sm")))
	button.add_theme_stylebox_override("focus", custom_box(base.lightened(0.04),
		colour("focus"), radius("md"), space("sm")))
	button.add_theme_stylebox_override("disabled", custom_box(base.darkened(0.18),
		Color(edge, 0.35), radius("md"), space("sm")))
	button.add_theme_color_override("font_color", palette["text"])
	button.add_theme_color_override("font_hover_color", colour("text_strong"))
	button.add_theme_color_override("font_pressed_color", colour("text_strong"))
	button.add_theme_color_override("font_focus_color", colour("text_strong"))
	button.add_theme_color_override("font_disabled_color", Color(colour("muted"), 0.55))
	return button

static func make_text(text: String, role := "body", semantic := "text") -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", type_size(role))
	label.add_theme_color_override("font_color", colour(semantic))
	return label

static func make_section(text: String) -> Label:
	var label := make_text(text, "caption", "muted")
	label.text = text.to_upper()
	return label

static func make_empty_state(text: String) -> Label:
	var label := make_text(text, "small", "muted")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, 32)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

static func make_chip(text: String, semantic := "info") -> PanelContainer:
	var col := colour(semantic)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", custom_box(Color(col, 0.16), Color(col, 0.72),
		radius("sm"), space("xs")))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := make_text(text, "caption", semantic)
	label.add_theme_color_override("font_color", col.lightened(0.25))
	chip.add_child(label)
	return chip

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = sans_font()
	theme.default_font_size = type_size("body")
	var prototype := Button.new()
	style_button(prototype)
	for cls in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			theme.set_stylebox(state, cls, prototype.get_theme_stylebox(state))
		for state in ["font_color", "font_hover_color", "font_pressed_color",
				"font_focus_color", "font_disabled_color"]:
			theme.set_color(state, cls, prototype.get_theme_color(state))
	theme.set_stylebox("panel", "PanelContainer", panel_box())
	theme.set_color("font_color", "Label", colour("text"))
	theme.set_stylebox("normal", "LineEdit", panel_box("console", "sm"))
	theme.set_stylebox("focus", "LineEdit", custom_box(colour("console"), colour("focus"),
		radius("md"), space("sm")))
	theme.set_color("font_color", "LineEdit", colour("text"))
	theme.set_color("font_placeholder_color", "LineEdit", Color(colour("muted"), 0.7))
	theme.set_stylebox("panel", "TooltipPanel", panel_box("overlay", "sm"))
	theme.set_color("font_color", "TooltipLabel", colour("text_strong"))
	var scroll_track := custom_box(Color(0.025, 0.055, 0.095, 0.72), Color.TRANSPARENT, 4, 0)
	scroll_track.shadow_size = 0
	var scroll_grab := custom_box(Color(colour("border_strong"), 0.72), Color.TRANSPARENT, 4, 0)
	scroll_grab.shadow_size = 0
	var scroll_hot := custom_box(colour("accent_soft"), Color(colour("accent"), 0.55), 4, 0)
	scroll_hot.shadow_size = 0
	for cls in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", cls, scroll_track)
		theme.set_stylebox("scroll_focus", cls, scroll_track)
		theme.set_stylebox("grabber", cls, scroll_grab)
		theme.set_stylebox("grabber_highlight", cls, scroll_hot)
		theme.set_stylebox("grabber_pressed", cls, scroll_hot)
	# This prototype is never added to the scene tree, so queue_free() would
	# leave it waiting forever and leak its theme resources at shutdown.
	prototype.free()
	return theme

# =========================================================== CommandPanel ==

class CommandPanel extends PanelContainer:
	## A deliberately authored frame for primary screens. Chamfered geometry,
	## a strong identity rail, and small technical details keep overlays from
	## reading as stock engine dialogs while retaining normal container layout.
	var variant := "overlay"
	var accent := UIW.colour("accent")

	func setup(v := "overlay", accent_token := "accent", padding := 24) -> CommandPanel:
		variant = v
		accent = UIW.colour(accent_token)
		var inset := StyleBoxEmpty.new()
		inset.content_margin_left = padding
		inset.content_margin_right = padding
		inset.content_margin_top = padding
		inset.content_margin_bottom = padding
		add_theme_stylebox_override("panel", inset)
		return self

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 32.0 or h < 32.0:
			return
		var cut := 16.0
		var bg := UIW.colour("overlay")
		if variant == "surface":
			bg = UIW.colour("surface")
		elif variant == "console":
			bg = UIW.colour("console")
		# Broad offset silhouette, then a square technical plate. Diagonal corner
		# braces carry the chamfer motif without relying on polygon triangulation.
		draw_rect(Rect2(Vector2(8, 10), size), Color(0.01, 0.025, 0.06, 0.48))
		draw_rect(Rect2(Vector2.ZERO, size), bg)
		draw_rect(Rect2(Vector2.ZERO, size), Color(UIW.colour("border_strong"), 0.90), false, 1.25)
		draw_line(Vector2(0, 36), Vector2(0, h - 24), accent, 4.0)
		draw_line(Vector2(cut, 0), Vector2(110, 0), accent, 3.0)
		draw_line(Vector2(w - 36, 0), Vector2(w, 36), Color(accent, 0.60), 2.0)
		draw_line(Vector2(w - 16, h), Vector2(w, h - 16), Color(UIW.colour("border_strong"), 0.68), 1.25)
		for i in 3:
			draw_circle(Vector2(w - 22 - i * 10, 18), 2.0, Color(accent, 0.35 + i * 0.18))

# ============================================================ ActionButton ==

class ActionButton extends Button:
	## A menu action with its own hierarchy and navigation cue. Keeping the
	## subtitle visible removes tooltip hunting and lets each choice breathe.
	var heading := ""
	var detail := ""
	var glyph := "01"
	var primary := false

	func setup(title: String, subtitle: String, is_primary: bool, mark: String) -> ActionButton:
		heading = title
		detail = subtitle
		glyph = mark
		primary = is_primary
		text = ""
		custom_minimum_size = Vector2(430, 68 if subtitle != "" else 58)
		UIW.style_button(self, "primary" if primary else "quiet")
		return self

	func _draw() -> void:
		var accent_col := UIW.colour("warm") if primary else UIW.colour("accent")
		var center := Vector2(30, size.y * 0.5)
		draw_circle(center, 17, Color(accent_col, 0.14 if not is_hovered() else 0.26))
		draw_circle(center, 17, Color(accent_col, 0.72), false, 1.25)
		draw_string(UIW.mono_font(), center + Vector2(-8, 4), glyph,
			HORIZONTAL_ALIGNMENT_CENTER, 16, 10, accent_col)
		var title_y := 29.0 if detail != "" else size.y * 0.5 + 5
		draw_string(UIW.sans_font(), Vector2(58, title_y), heading,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 110, 17, UIW.colour("text_strong"))
		if detail != "":
			draw_string(UIW.sans_font(), Vector2(58, 49), detail,
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 110, 12, UIW.colour("muted"))
		draw_string(UIW.mono_font(), Vector2(size.x - 42, size.y * 0.5 + 5), "→",
			HORIZONTAL_ALIGNMENT_CENTER, 24, 16, accent_col)

const TYPE_COLORS := {
	"switch": Color("39d9d0"),
	"router": Color("ffb45c"),
	"firewall": Color("ff6f68"),
	"uplink": Color("b58cff"),
	"cooling": Color("70c8ff"),
	"loadbalancer": Color("69e39a"),
	"ap": Color("ffe079"),
	"server": Color("719cff"),
	"console": Color("e4c891"),
}

const MODEL_VISUALS := {
	"sw-lite": {"base": Color("d7d2c4"), "accent": Color("70b85c"), "ink": Color("24313a"), "mark": "packet"},
	"rtr-lite": {"base": Color("d7d2c4"), "accent": Color("e0a34d"), "ink": Color("24313a"), "mark": "packet"},
	"sw-8": {"base": Color("293743"), "accent": Color("57c9cb"), "ink": Color("e7f0f2"), "mark": "open"},
	"sw-24": {"base": Color("17334b"), "accent": Color("39d9d0"), "ink": Color("eef9fa"), "mark": "arivista"},
	"srv-1": {"base": Color("353e49"), "accent": Color("719cff"), "ink": Color("edf1f7"), "mark": "dill"},
	"srv-2": {"base": Color("303b4c"), "accent": Color("8cb1ff"), "ink": Color("edf1f7"), "mark": "dill"},
	"rtr-edge": {"base": Color("30294a"), "accent": Color("b58cff"), "ink": Color("f3ecff"), "mark": "junivista"},
	"fw-1": {"base": Color("482b31"), "accent": Color("ff6f68"), "ink": Color("fff0ed"), "mark": "shield"},
	"lb-1": {"base": Color("233e39"), "accent": Color("69e39a"), "ink": Color("effff5"), "mark": "balance"},
	"ap-1": {"base": Color("45402d"), "accent": Color("ffe079"), "ink": Color("fff9df"), "mark": "radio"},
	"isp-uplink": {"base": Color("332b48"), "accent": Color("b58cff"), "ink": Color("f5efff"), "mark": "uplink"},
	"con-1": {"base": Color("403b32"), "accent": Color("e4c891"), "ink": Color("fff8e8"), "mark": "console"},
	"crac-1": {"base": Color("233c4b"), "accent": Color("70c8ff"), "ink": Color("edfaff"), "mark": "cooling"},
}

static func model_visual(model: String) -> Dictionary:
	return MODEL_VISUALS.get(model, {"base": colour("surface_raised"),
		"accent": colour("info"), "ink": colour("text_strong"), "mark": "open"})

static var _mono_shared: SystemFont
static var _sans_shared: SystemFont

static func sans_font() -> SystemFont:
	if _sans_shared == null:
		_sans_shared = SystemFont.new()
		_sans_shared.font_names = PackedStringArray(["Avenir Next", "Inter", "SF Pro Display", "Arial"])
	return _sans_shared

static func mono_font() -> SystemFont:
	if _mono_shared == null:
		_mono_shared = SystemFont.new()
		_mono_shared.font_names = PackedStringArray(["Menlo", "Consolas", "monospace"])
	return _mono_shared

# ================================================================== Graph ==

class Graph extends Control:
	## a small line chart over Game.history
	var key := "money"
	var colour := Color(0.5, 0.9, 0.6)
	var title := ""
	var _mono: SystemFont

	func setup(k: String, t: String, c: Color) -> Graph:
		key = k
		title = t
		colour = c
		_mono = UIW.mono_font()
		custom_minimum_size = Vector2(560, 90)
		return self

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UIW.colour("console"))
		draw_rect(Rect2(Vector2.ZERO, size), UIW.colour("border"), false, 1.0)
		var pts: Array = []
		for h in Game.history:
			pts.append(float(h.get(key, 0)))
		if pts.size() < 2:
			draw_string(_mono, Vector2(10, size.y / 2.0),
				"%s: not enough history yet" % title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				UIW.colour("muted"))
			return
		var lo: float = pts[0]
		var hi: float = pts[0]
		for v in pts:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		if is_equal_approx(lo, hi):
			hi = lo + 1.0
		var line := PackedVector2Array()
		for i in pts.size():
			var x := 8.0 + (size.x - 16.0) * float(i) / float(maxi(pts.size() - 1, 1))
			var y: float = size.y - 20.0 - (size.y - 34.0) * (float(pts[i]) - lo) / (hi - lo)
			line.append(Vector2(x, y))
		if lo < 0.0 and hi > 0.0:  # zero line, when the series crosses it
			var zy := size.y - 20.0 - (size.y - 34.0) * (0.0 - lo) / (hi - lo)
			draw_line(Vector2(8, zy), Vector2(size.x - 8, zy), Color(UIW.colour("border_strong"), 0.6), 1.0)
		draw_polyline(line, Color(colour, 0.22), 7.0)
		draw_polyline(line, colour, 2.5)
		draw_circle(line[line.size() - 1], 4.0, colour)
		draw_string(_mono, Vector2(10, 14), "%s   now %d   (min %d, max %d)" % [title,
			int(float(pts[pts.size() - 1])), int(lo), int(hi)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colour.lightened(0.2))

# ================================================================ TopoMap ==

class TopoMap extends Control:
	var on_dev: Callable  # (Net.NDevice)
	var on_link: Callable  # (Net.NDevice, Net.NDevice) -> String: cable these two up
	var _mono: SystemFont
	var _nodes := {}  # Net.NDevice -> Rect2
	# dragging a run between two devices: cross-rack and cross-site cabling has
	# no single cabinet elevation to do it on, so it happens here
	var drag_from: Net.NDevice = null
	var drag_to := Vector2.ZERO
	var drag_note := ""
	var _reject_until := 0.0

	func setup(cb: Callable, link_cb := Callable()) -> TopoMap:
		on_dev = cb
		on_link = link_cb
		_mono = UIW.mono_font()
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_preset(Control.PRESET_FULL_RECT)
		return self

	func _process(_dt: float) -> void:
		if visible:
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion and drag_from != null:
			drag_to = e.position
			drag_note = _preview(_dev_at(e.position))
			return
		if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
			return
		if e.pressed:
			var hit := _dev_at(e.position)
			if hit == null:
				return
			if e.shift_pressed or e.ctrl_pressed:
				# a modifier starts a run rather than opening the device
				drag_from = hit
				drag_to = e.position
				drag_note = ""
				return
			on_dev.call(hit)
			return
		if drag_from == null:
			return
		var target := _dev_at(e.position)
		var from := drag_from
		drag_from = null
		drag_note = ""
		if target == null or target == from or on_link.is_null():
			return
		var err: String = on_link.call(from, target)
		if err != "":
			drag_note = err
			_reject_until = Time.get_ticks_msec() / 1000.0 + 2.0

	func _dev_at(at: Vector2) -> Net.NDevice:
		for dev in _nodes:
			if _nodes[dev].has_point(at):
				return dev
		return null

	func _preview(target: Net.NDevice) -> String:
		## What this run would be, before anybody commits to it: same site is
		## a cable, another site needs a circuit that exists.
		if drag_from == null or target == null or target == drag_from:
			return ""
		var a_site := Game.rack_of(drag_from)
		var b_site := Game.rack_of(target)
		if a_site == null or b_site == null:
			return "not racked"
		if int(a_site.site) != int(b_site.site):
			var circuit := Game.circuit_between(int(a_site.site), int(b_site.site))
			if circuit.is_empty():
				return "%s → %s needs a leased circuit first" % [Game.site_name(int(a_site.site)),
					Game.site_name(int(b_site.site))]
			return "over the %s circuit (%d Mbps)" % [circuit.get("carrier", "leased"),
				int(circuit.get("mbps", 0))]
		if a_site == b_site:
			return "same cabinet: a patch lead"
		return "cabinet to cabinet: a long run"

	func _dev_info(dev: Net.NDevice) -> String:
		var bits: Array = []
		for i: Net.Iface in dev.ifaces:
			for cidr: String in i.ips:
				bits.append(cidr)
				if bits.size() >= 2:
					return ", ".join(PackedStringArray(bits))
		if dev.type == "switch":
			var vids := dev.vlans.keys()
			vids.sort()
			return "vlans " + ",".join(PackedStringArray(vids.map(func(v): return str(v))))
		return ", ".join(PackedStringArray(bits))

	func _draw() -> void:
		_nodes.clear()
		draw_rect(Rect2(Vector2.ZERO, size), UIW.colour("console"))
		# A dim plotting grid makes this feel like an active NOC surface instead of
		# a collection of controls floating over an empty canvas.
		for x in range(24, int(size.x), 32):
			draw_line(Vector2(x, 74), Vector2(x, size.y - 58),
				Color(UIW.colour("border"), 0.10), 1.0)
		for y in range(74, int(size.y - 58), 32):
			draw_line(Vector2(0, y), Vector2(size.x, y),
				Color(UIW.colour("border"), 0.10), 1.0)
		# Command rail.
		draw_rect(Rect2(0, 0, size.x, 74), Color("0d1d31"))
		draw_line(Vector2(0, 73), Vector2(size.x, 73), Color(UIW.colour("accent"), 0.55), 1.0)
		draw_rect(Rect2(30, 18, 4, 38), UIW.colour("accent"))
		draw_string(_mono, Vector2(48, 31), "NETWORK MAP  /  LIVE ESTATE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIW.colour("accent"))
		draw_string(_mono, Vector2(48, 55), "LOGICAL TOPOLOGY",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UIW.colour("text_strong"))
		draw_string(_mono, Vector2(size.x - 176, 45), "M / ESC  CLOSE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIW.colour("muted"))

		var dev_count := Game.all_devices().size()
		var down_count := 0
		for dev: Net.NDevice in Game.all_devices():
			if dev.status != "active":
				down_count += 1
		var metrics := "%02d RACKS    %02d DEVICES    %02d LINKS    %s" % [Game.racks.size(),
			dev_count, Game.links.size(), "ALL SYSTEMS NOMINAL" if down_count == 0 else "%02d DEVICE ALERTS" % down_count]
		draw_string(_mono, Vector2(48, 108), metrics, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			UIW.colour("success") if down_count == 0 else UIW.colour("warning"))
		draw_string(_mono, Vector2(size.x - 292, 108), "SELECT A DEVICE TO INSPECT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIW.colour("muted"))

		# Pack uniform rack bays around the centre of the plotting surface.
		const CARD_W := 300.0
		const GAP_X := 54.0
		const GAP_Y := 34.0
		const TOP := 142.0
		var racks := Game.racks.duplicate()
		racks.sort_custom(func(x, y): return x.tile.x + x.tile.y * 100 < y.tile.x + y.tile.y * 100)
		var cols: int = mini(maxi(1, int((size.x - 96.0 + GAP_X) / (CARD_W + GAP_X))),
			maxi(1, racks.size()))
		var max_devices := 1
		for rack in racks:
			var n := 0
			for slot in rack.slots:
				if slot:
					n += 1
			max_devices = maxi(max_devices, n)
		var card_h := 54.0 + max_devices * 48.0 + 12.0
		var rows: int = maxi(1, ceili(float(racks.size()) / float(cols)))
		var plot_h := size.y - TOP - 76.0
		var total_h := rows * card_h + (rows - 1) * GAP_Y
		var start_y := TOP + maxf(0.0, (plot_h - total_h) * 0.42)
		for rack_i in racks.size():
			var r = racks[rack_i]
			var filled: Array = []
			for d in r.slots:
				if d:
					filled.append(d)
			var row_i: int = rack_i / cols
			var col_i: int = rack_i % cols
			var row_count: int = mini(cols, racks.size() - row_i * cols)
			var row_w := row_count * CARD_W + (row_count - 1) * GAP_X
			var row_x := (size.x - row_w) * 0.5
			var origin := Vector2(row_x + col_i * (CARD_W + GAP_X),
				start_y + row_i * (card_h + GAP_Y))
			var box := Rect2(origin, Vector2(CARD_W, card_h))
			draw_rect(box, UIW.colour("surface"))
			draw_rect(Rect2(box.position, Vector2(5, box.size.y)), UIW.colour("accent"))
			draw_rect(Rect2(box.position, Vector2(box.size.x, 42)), Color("203854"))
			draw_rect(box, UIW.colour("border_strong"), false, 1.0)
			draw_line(origin + Vector2(18, 42), origin + Vector2(CARD_W - 18, 42),
				Color(UIW.colour("accent"), 0.42), 1.0)
			var site_tag: String = "" if Game.site_count() <= 1 else "  ·  " + Game.site_name(r.site)
			draw_string(_mono, origin + Vector2(18, 27), "RACK  /  " + r.name + site_tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIW.colour("text_strong"))
			draw_string(_mono, origin + Vector2(CARD_W - 78, 27), "%02d NODES" % filled.size(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIW.colour("muted"))
			var y := origin.y + 52
			for d in filled:
				_nodes[d] = Rect2(origin.x + 12, y, CARD_W - 24, 40)
				y += 48
		# links under nodes
		for l in Game.links:
			if not _nodes.has(l.a.dev) or not _nodes.has(l.b.dev):
				continue
			var ra: Rect2 = _nodes[l.a.dev]
			var rb: Rect2 = _nodes[l.b.dev]
			var pa: Vector2 = ra.get_center()
			var pb: Vector2 = rb.get_center()
			if absf(pb.x - pa.x) > absf(pb.y - pa.y):
				pa.x = ra.end.x if pb.x > pa.x else ra.position.x
				pb.x = rb.position.x if pb.x > pa.x else rb.end.x
			else:
				pa.y = ra.end.y if pb.y > pa.y else ra.position.y
				pb.y = rb.position.y if pb.y > pa.y else rb.end.y
			var col := Color(0.35, 0.7, 0.65, 0.8)
			var blocked := false
			if l.a.dev.type == "switch" and l.b.dev.type == "switch":
				col = Color(1.0, 0.62, 0.2, 0.85)
				blocked = Sim.stp_blocked(l.a) or Sim.stp_blocked(l.b)
			if l.a.name.begins_with("Management") or l.b.name.begins_with("Management"):
				col = Color(0.75, 0.55, 0.95, 0.85)
			var ls := Game.sites_of(l.a, l.b)
			if ls[0] != ls[1]:
				col = Color(0.4, 0.9, 1.0, 0.9)  # rides a WAN circuit
			var over: bool = Game.last_link_load.get(l, 0) > Game.link_capacity(l)
			if over:
				draw_line(pa, pb, Color(0.95, 0.3, 0.25, 0.22), 8.0)
				draw_line(pa, pb, Color(0.95, 0.3, 0.25, 0.9), 3.0)
				draw_string(_mono, (pa + pb) / 2.0 + Vector2(4, -4),
					"%d/%d Mbps" % [Game.last_link_load.get(l, 0), Game.link_capacity(l)],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.5, 0.45))
			elif blocked:
				var n := 14
				for k in n:
					if k % 2 == 0:
						draw_line(pa.lerp(pb, float(k) / n), pa.lerp(pb, float(k + 1) / n),
							Color(0.9, 0.4, 0.35, 0.9), 2.0)
			else:
				draw_line(pa, pb, Color(col, 0.16), 7.0)
				draw_line(pa, pb, col, 2.0)
			if not blocked:
				_flow(pa, pb, col, int(Game.last_link_load.get(l, 0)), Game.link_capacity(l))
		# nodes on top
		for dev: Net.NDevice in _nodes:
			var rect: Rect2 = _nodes[dev]
			var identity: Dictionary = UIW.model_visual(dev.model)
			var col: Color = identity["accent"]
			draw_rect(rect, Color(identity["base"]).darkened(0.30))
			draw_rect(Rect2(rect.position, Vector2(5, rect.size.y)), col)
			draw_rect(rect, col if dev.status == "active" else UIW.colour("danger"), false, 1.5)
			draw_circle(rect.position + Vector2(rect.size.x - 16, 14), 3.5,
				UIW.colour("success") if dev.status == "active" else UIW.colour("danger"))
			var ink: Color = identity["ink"]
			draw_string(_mono, rect.position + Vector2(13, 17), dev.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
			draw_string(_mono, rect.position + Vector2(13, 32), _dev_info(dev), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				ink.darkened(0.20) if ink.get_luminance() > 0.55 else ink.lightened(0.35))
		# legend
		draw_rect(Rect2(0, size.y - 58, size.x, 58), Color("0d1d31"))
		draw_line(Vector2(0, size.y - 58), Vector2(size.x, size.y - 58),
			Color(UIW.colour("border"), 0.75), 1.0)
		var ly := size.y - 24
		draw_string(_mono, Vector2(30, ly),
			"— HOST LINK     — TRUNK / INTER-SWITCH     ┄ BLOCKED BY STP     ● LIVE DEVICE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIW.colour("muted"))
		draw_string(_mono, Vector2(30, ly - 16),
			"SHIFT-DRAG BETWEEN TWO DEVICES TO RUN A CABLE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(UIW.colour("accent"), 0.8))
		# a run being dragged, with what it would actually be written beside it
		if drag_from != null and _nodes.has(drag_from):
			var from_p: Vector2 = (_nodes[drag_from] as Rect2).get_center()
			draw_line(from_p, drag_to, Color(UIW.colour("accent"), 0.75), 2.0)
			draw_circle(drag_to, 4.0, UIW.colour("accent"))
			if drag_note != "":
				draw_string(_mono, drag_to + Vector2(10, -8), drag_note,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(1.0, 0.72, 0.45) if "needs" in drag_note or "not racked" in drag_note
					else UIW.colour("accent"))
		elif drag_note != "" and Time.get_ticks_msec() / 1000.0 < _reject_until:
			draw_string(_mono, Vector2(30, ly - 32), drag_note,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.55, 0.45))

	func _flow(pa: Vector2, pb: Vector2, col: Color, load: int, cap: int) -> void:
		## dots travelling the link, more of them the busier it is. A link
		## carrying nothing shows nothing, which is a diagnosis in itself.
		if load <= 0 or cap <= 0:
			return
		var share := clampf(float(load) / float(cap), 0.03, 1.0)
		var dots := 1 + int(share * 5.0)
		var speed := 0.18 + share * 0.5  # laps per second
		var t := Time.get_ticks_msec() / 1000.0
		for k in dots:
			var f := fmod(t * speed + float(k) / dots, 1.0)
			draw_circle(pa.lerp(pb, f), 2.6, Color(col.lightened(0.45), 0.9))

# ===================================================================== Bar ==

class Bar extends Control:
	## A labelled capacity bar. Amber past two thirds, red once it is full,
	## with the runway (cycles until it fills) on the right where there is one.
	var caption := ""
	var used := 0
	var total := 0
	var runway := -1
	var note := ""
	var _mono: SystemFont

	func setup(text: String, u: int, t: int, cycles := -1, extra := "") -> Bar:
		caption = text
		used = u
		total = t
		runway = cycles
		note = extra
		_mono = UIW.mono_font()
		custom_minimum_size = Vector2(560, 34)
		return self

	func _draw() -> void:
		var share := 0.0 if total <= 0 else clampf(float(used) / float(total), 0.0, 1.0)
		var col := UIW.colour("success")
		if share >= 1.0:
			col = Prefs.bad_colour()
		elif share > 0.66:
			col = UIW.colour("warning")
		draw_string(_mono, Vector2(0, 13), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			UIW.colour("text"))
		var right := "%d / %d" % [used, total]
		if note != "":
			right += "   " + note
		draw_string(_mono, Vector2(size.x - 250, 13), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			UIW.colour("muted"))
		if runway >= 0:
			draw_string(_mono, Vector2(size.x - 120, 13),
				"full now" if runway == 0 else "~%d cycles" % runway,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Prefs.bad_colour() if runway <= 6 else UIW.colour("muted"))
		var track := Rect2(0, 19, size.x - 4, 8)
		draw_rect(track, UIW.colour("console"))
		draw_rect(Rect2(track.position, Vector2(track.size.x * share, track.size.y)), col)
		# the two-thirds mark, which is where you should already be ordering
		var mark := track.position.x + track.size.x * 0.66
		draw_line(Vector2(mark, track.position.y - 2), Vector2(mark, track.end.y + 2),
			Color(UIW.colour("border_strong"), 0.8), 1.0)

# ================================================================ RackSlot ==

class RackSlot extends Control:
	signal cable_started(iface: Net.Iface, screen_pos: Vector2)
	signal cable_moved(screen_pos: Vector2)
	signal cable_released(screen_pos: Vector2)
	signal blanking_toggled(slot: int)
	var u_num := 0
	var upper_half := false  # the second unit of a 2U box, drawn as its top
	var dev: Net.NDevice
	var on_click: Callable
	var hovered := false
	var _mono: SystemFont
	var _drag_iface: Net.Iface
	var blanked := false

	func setup(u: int, d: Net.NDevice, cb: Callable, is_blanked := false) -> RackSlot:
		u_num = u
		dev = d
		on_click = cb
		blanked = is_blanked
		custom_minimum_size = Vector2(520, 46)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_mono = UIW.mono_font()
		if d:
			tooltip_text = "%s: click to inspect; drag a free port square to another device in this rack to cable it" % d.name
			if Game.config_dirty(d):
				tooltip_text += "   (unsaved configuration)"
		else:
			tooltip_text = ("Blanking panel fitted · right-click to remove · left-click to install hardware"
				if blanked else "Open rack gap · right-click to fit a blanking panel · left-click to install hardware")
		return self

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			hovered = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			hovered = false
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT \
				and e.pressed and dev == null:
			blanking_toggled.emit(u_num - 1)
			accept_event()
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				var port := port_at(e.position)
				var link := Game.link_at(port) if port else null
				var local_link := link and Game.rack_of(link.other(port).dev) == Game.rack_of(dev)
				if port and (link == null or local_link):
					_drag_iface = port
					cable_started.emit(port, port_screen_position(port))
					accept_event()
				else:
					on_click.call()
			else:
				if _drag_iface:
					_drag_iface = null
					cable_released.emit(get_global_mouse_position())
					accept_event()
		elif e is InputEventMouseMotion:
			var hovered_port := port_at(e.position)
			if hovered_port:
				var link := Game.link_at(hovered_port)
				var local_link := link and Game.rack_of(link.other(hovered_port).dev) == Game.rack_of(dev)
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if link == null or local_link \
					else Control.CURSOR_HELP
				var action := "FREE — DRAG TO PATCH"
				if local_link:
					action = "PATCHED — GRAB TO REPATCH OR UNPLUG"
				elif link:
					action = "REMOTE LINK — CLICK TO INSPECT"
				tooltip_text = "%s  /  %s  ·  %s" % [dev.name, hovered_port.name, action]
			else:
				mouse_default_cursor_shape = Control.CURSOR_ARROW
			if _drag_iface:
				cable_moved.emit(get_global_mouse_position())
				accept_event()

	func _physical_ports() -> Array:
		var out: Array = []
		if dev == null:
			return out
		for iface: Net.Iface in dev.ifaces:
			if iface.name == "lo" or iface.name.begins_with("Vlan") \
					or iface.name.begins_with("Tunnel") or iface.name.begins_with("wg") \
					or iface.parent != "" or iface.vm != "":
				continue
			out.append(iface)
		return out

	func _port_rect(iface: Net.Iface) -> Rect2:
		var ports := _physical_ports()
		var idx := ports.find(iface)
		if idx < 0:
			return Rect2()
		const RAIL := 30.0
		var inner := Rect2(RAIL + 2, 3, size.x - RAIL * 2 - 4, size.y - 6)
		# Real faceplates bank ports in rows. Keeping twelve per row gives every
		# jack a distinct socket and drag target, even on a 24-port switch.
		const PITCH := 17.0
		const JACK := Vector2(14, 11)
		var columns := mini(12, ports.size())
		var col := idx % 12
		var row := idx / 12
		var bank_w := (columns - 1) * PITCH + JACK.x
		var bank_x := inner.end.x - 18.0 - bank_w
		var bank_y := inner.position.y + (6.0 if ports.size() > 12 else (inner.size.y - JACK.y) * 0.5)
		return Rect2(Vector2(bank_x + col * PITCH, bank_y + row * 15.0), JACK)

	func port_at(local_pos: Vector2) -> Net.Iface:
		for iface: Net.Iface in _physical_ports():
			if _port_rect(iface).grow(2.0).has_point(local_pos):
				return iface
		return null

	func port_at_screen(screen_pos: Vector2) -> Net.Iface:
		return port_at(screen_pos - get_global_rect().position)

	func port_screen_position(iface: Net.Iface) -> Vector2:
		return get_global_rect().position + _port_rect(iface).get_center()

	func _process(_dt: float) -> void:
		if dev:
			queue_redraw()  # LEDs blink

	func _draw() -> void:
		var w := size.x
		var h := size.y
		const RAIL := 30.0
		# rails with screw holes
		for rx in [0.0, w - RAIL]:
			draw_rect(Rect2(rx, 0, RAIL, h), Color("203953"))
			draw_rect(Rect2(rx, 0, RAIL, h), UIW.colour("border"), false, 1.0)
			for hy in [h * 0.25, h * 0.75]:
				draw_circle(Vector2(rx + RAIL / 2.0, hy), 3.2, UIW.colour("console"))
				draw_circle(Vector2(rx + RAIL / 2.0, hy), 3.2, UIW.colour("border_strong"), false, 1.0)
		draw_string(_mono, Vector2(4, h / 2.0 + 4), "U%d" % u_num,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIW.colour("muted"))
		var inner := Rect2(RAIL + 2, 3, w - RAIL * 2 - 4, h - 6)
		if dev == null:
			if blanked:
				# A fitted steel blank: shallow ribs, corner screws and a clean
				# continuous face make the before/after obvious at rack scale.
				var panel := Color("3a4650")
				if hovered:
					panel = panel.lightened(0.08)
				draw_rect(inner, panel)
				draw_rect(inner, Color("71808b"), false, 1.0)
				for rib in 4:
					var ry := inner.position.y + 8.0 + rib * 7.0
					draw_line(Vector2(inner.position.x + 16, ry), Vector2(inner.end.x - 16, ry),
						Color(0.10, 0.14, 0.17, 0.56), 1.0)
				for screw in [inner.position + Vector2(8, 7), Vector2(inner.end.x - 8, inner.position.y + 7),
					Vector2(inner.position.x + 8, inner.end.y - 7), inner.end - Vector2(8, 7)]:
					draw_circle(screw, 1.8, Color("aab4ba"))
			else:
				# empty recess
				draw_rect(inner, UIW.colour("console"))
				draw_rect(inner, UIW.colour("border"), false, 1.0)
			if hovered and not blanked:
				draw_string(_mono, inner.position + Vector2(inner.size.x / 2.0 - 60, inner.size.y / 2.0 + 4),
					"+ INSTALL HARDWARE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIW.colour("accent"))
			return
		# device faceplate
		var visual := UIW.model_visual(dev.model)
		var col: Color = visual["accent"]
		var face: Color = visual["base"]
		if dev.status != "active":
			col = Color(0.4, 0.33, 0.33)
			face = Color(0.22, 0.20, 0.21)
		if hovered:
			face = face.lightened(0.10)
		draw_rect(inner, face)
		draw_rect(inner, col.lightened(0.1) if hovered else col.darkened(0.2), false, 1.5)
		draw_rect(Rect2(inner.position, Vector2(6, inner.size.y)), col)  # vendor stripe
		draw_string(_mono, inner.position + Vector2(14, 18), dev.name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, visual["ink"])
		draw_string(_mono, inner.position + Vector2(14, 33), Game.MODELS[dev.model]["label"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col.lightened(0.25))
		if not dev.note.is_empty():
			var sticky := Rect2(inner.position + Vector2(166, 6), Vector2(17, 20))
			draw_rect(Rect2(sticky.position + Vector2(2, 2), sticky.size), Color(0, 0, 0, 0.28))
			draw_rect(sticky, Color("e8c96f"))
			draw_colored_polygon(PackedVector2Array([sticky.end - Vector2(6, 0), sticky.end,
				sticky.end - Vector2(0, 6)]), Color("b49348"))
			draw_line(sticky.position + Vector2(4, 7), sticky.position + Vector2(13, 7),
				Color("67552c"), 1.0)
			draw_line(sticky.position + Vector2(4, 11), sticky.position + Vector2(11, 11),
				Color("67552c"), 1.0)
		# Ethernet sockets: recessed jack, metal lip, and a tiny link light.
		for i: Net.Iface in _physical_ports():
			var port_rect := _port_rect(i)
			if port_rect.size == Vector2.ZERO:
				continue
			var linked := Game.link_at(i) != null
			var pc := Color(0.35, 0.95, 0.5) if linked else Color(0.15, 0.18, 0.22)
			if not i.enabled:
				pc = Color(0.7, 0.3, 0.25)
			draw_rect(port_rect, Color("111821"))
			draw_rect(port_rect, col.darkened(0.25), false, 1.0)
			draw_rect(Rect2(port_rect.position + Vector2(3, 3), port_rect.size - Vector2(6, 5)), pc)
			draw_line(port_rect.position + Vector2(4, 2), port_rect.position + Vector2(10, 2),
				Color("aeb7bc"), 1.0)
			if not i.note.is_empty():
				# A sliver of labeling tape stays legible beside even the dense 24-port bank.
				draw_rect(Rect2(port_rect.position + Vector2(1, -3), Vector2(port_rect.size.x - 2, 2)),
					Color("e8c96f"))
			if not linked and hovered:
				draw_rect(port_rect.grow(2), Color(UIW.colour("accent"), 0.72), false, 1.0)
		if Game.config_dirty(dev):  # unsaved configuration: amber dot by the status LED
			draw_circle(inner.position + Vector2(inner.size.x - 24, 10), 2.6, Color(1.0, 0.72, 0.3))
		# status LED
		var t := Time.get_ticks_msec() / 1000.0
		var led := Color(0.9, 0.3, 0.2)
		if dev.status == "active":
			led = Color(0.4, 1.0, 0.5) if fmod(t * 1.7, 1.0) > 0.3 else Color(0.15, 0.4, 0.2)
		draw_circle(inner.position + Vector2(inner.size.x - 12, 10), 2.6, led)

class CablePull extends Control:
	var active := false
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var source_iface: Net.Iface
	var suppressed_link: Net.Link
	var valid_target := false
	var rack: Net.Rack
	var slot_box: VBoxContainer
	var feedback_a: Net.Iface
	var feedback_b: Net.Iface
	var feedback_elapsed := -1.0
	var reject_from := Vector2.ZERO
	var reject_to := Vector2.ZERO
	var reject_elapsed := -1.0
	var reject_reason := ""
	var _mono: SystemFont
	const CABLE_COLOURS := [Color("f2b84b"), Color("4dd5c8"), Color("75a7ff"),
		Color("e7748f"), Color("a78bfa"), Color("8ed081")]

	func setup() -> CablePull:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mono = UIW.mono_font()
		return self

	func watch(r: Net.Rack, slots: VBoxContainer) -> void:
		rack = r
		slot_box = slots
		queue_redraw()

	func begin(screen_from: Vector2, iface: Net.Iface, hide_link: Net.Link = null) -> void:
		active = true
		source_iface = iface
		suppressed_link = hide_link
		from = screen_from
		to = screen_from
		queue_redraw()

	func move_to(screen_to: Vector2, can_drop := false) -> void:
		to = screen_to
		valid_target = can_drop
		queue_redraw()

	func finish() -> void:
		active = false
		source_iface = null
		suppressed_link = null
		valid_target = false
		queue_redraw()

	func confirm(a: Net.Iface, b: Net.Iface) -> void:
		feedback_a = a
		feedback_b = b
		feedback_elapsed = 0.0
		queue_redraw()

	func reject(screen_to: Vector2, reason: String) -> void:
		reject_from = from - global_position
		reject_to = screen_to - global_position
		reject_reason = reason
		reject_elapsed = 0.0
		Sfx.play("bad")
		queue_redraw()

	func _process(dt: float) -> void:
		if feedback_elapsed >= 0.0:
			feedback_elapsed += dt
			var duration := 0.24 if Prefs.reduced_motion else 0.72
			if feedback_elapsed >= duration:
				feedback_elapsed = -1.0
				feedback_a = null
				feedback_b = null
		if reject_elapsed >= 0.0:
			reject_elapsed += dt
			var reject_duration := 0.32 if Prefs.reduced_motion else 0.52
			if reject_elapsed >= reject_duration:
				reject_elapsed = -1.0
				reject_reason = ""
		if visible:
			queue_redraw()

	func _port_positions() -> Dictionary:
		var positions := {}
		if slot_box == null:
			return positions
		for child in slot_box.get_children():
			if child is UIW.RackSlot and not child.is_queued_for_deletion():
				var slot := child as UIW.RackSlot
				for iface: Net.Iface in slot._physical_ports():
					if not positions.has(iface):
						positions[iface] = slot.port_screen_position(iface) - global_position
		return positions

	func _loose_points(a: Vector2, b: Vector2) -> PackedVector2Array:
		# While held, the lead hangs under the hand with a little gravity.
		var control := Vector2((a.x + b.x) * 0.5, maxf(a.y, b.y) + 30.0)
		var points := PackedVector2Array()
		for step in 25:
			var t := float(step) / 24.0
			var omt := 1.0 - t
			points.append(omt * omt * a + 2.0 * omt * t * control + t * t * b)
		return points

	func _dressed_points(a: Vector2, b: Vector2, lane := 0) -> PackedVector2Array:
		# Installed leads are dressed through the right-hand vertical manager.
		# Rounded elbows stop the run looking like a diagram connector.
		var gutter := maxf(a.x, b.x) + 24.0 + lane * 4.0
		var radius := minf(10.0, absf(b.y - a.y) * 0.22)
		var direction := signf(b.y - a.y)
		if is_zero_approx(direction):
			direction = 1.0
		var points := PackedVector2Array([a, Vector2(gutter - radius, a.y)])
		for step in range(1, 6):
			var t := float(step) / 5.0
			var omt := 1.0 - t
			var corner_a := Vector2(gutter, a.y)
			var end_a := Vector2(gutter, a.y + direction * radius)
			points.append(omt * omt * Vector2(gutter - radius, a.y) \
				+ 2.0 * omt * t * corner_a + t * t * end_a)
		points.append(Vector2(gutter, b.y - direction * radius))
		for step in range(1, 6):
			var t := float(step) / 5.0
			var omt := 1.0 - t
			var start_b := Vector2(gutter, b.y - direction * radius)
			var corner_b := Vector2(gutter, b.y)
			var end_b := Vector2(gutter - radius, b.y)
			points.append(omt * omt * start_b + 2.0 * omt * t * corner_b + t * t * end_b)
		points.append(b)
		return points

	func _draw_lead(a: Vector2, b: Vector2, colour: Color, preview := false, lane := 0) -> void:
		var points := _loose_points(a, b) if preview else _dressed_points(a, b, lane)
		draw_polyline(points, Color(0.005, 0.008, 0.012, 0.90), 7.0, true)
		draw_polyline(points, colour, 3.5, true)
		# Rubber boots make the endpoints read as plugs rather than dots.
		for end in [a, b]:
			draw_rect(Rect2(end - Vector2(3, 5), Vector2(9, 10)), Color("101820"))
			draw_rect(Rect2(end - Vector2(2, 4), Vector2(7, 8)), colour.darkened(0.12))
		if preview:
			draw_circle(b, 8.0, Color(colour, 0.16))
			draw_circle(b, 8.0, colour, false, 1.5)

	func _point_on_path(points: PackedVector2Array, progress: float) -> Vector2:
		var lengths := PackedFloat32Array()
		var total := 0.0
		for i in range(1, points.size()):
			var length := points[i - 1].distance_to(points[i])
			lengths.append(length)
			total += length
		var wanted := total * clampf(progress, 0.0, 1.0)
		for i in lengths.size():
			if wanted <= lengths[i]:
				return points[i].lerp(points[i + 1], wanted / maxf(lengths[i], 0.001))
			wanted -= lengths[i]
		return points[points.size() - 1]

	func _draw_confirmation(points: PackedVector2Array, colour: Color) -> void:
		var duration := 0.24 if Prefs.reduced_motion else 0.72
		var progress := clampf(feedback_elapsed / duration, 0.0, 1.0)
		var fade := 1.0 - progress
		# The plug boots briefly catch light as they seat. In reduced-motion mode
		# this static acknowledgement is the complete effect.
		for endpoint in [points[0], points[points.size() - 1]]:
			draw_circle(endpoint, 5.0 + progress * 5.0, Color(colour, fade * 0.34))
			draw_circle(endpoint, 5.0 + progress * 5.0, Color(colour, fade * 0.85), false, 1.4)
		if not Prefs.reduced_motion:
			var travel := clampf((progress - 0.08) / 0.78, 0.0, 1.0)
			var glint := _point_on_path(points, travel)
			draw_circle(glint, 6.0, Color(colour, fade * 0.18))
			draw_circle(glint, 2.3, colour.lightened(0.45))

	func _draw_rejection() -> void:
		var duration := 0.32 if Prefs.reduced_motion else 0.52
		var progress := clampf(reject_elapsed / duration, 0.0, 1.0)
		var fade := 1.0 - progress
		var danger := Color(Prefs.bad_colour(), fade)
		var end := reject_to
		if not Prefs.reduced_motion:
			# A quick ease-back reads as the loose plug physically refusing the drop.
			var recoil := 1.0 - pow(1.0 - progress, 2.4)
			end = reject_to.lerp(reject_from, recoil)
			var points := _loose_points(reject_from, end)
			draw_polyline(points, Color(0.005, 0.008, 0.012, fade * 0.8), 7.0, true)
			draw_polyline(points, danger, 3.5, true)
		draw_circle(reject_to, 7.0 + progress * 4.0, Color(danger, fade * 0.18))
		draw_circle(reject_to, 7.0 + progress * 4.0, danger, false, 1.5)
		draw_line(reject_to + Vector2(-4, -4), reject_to + Vector2(4, 4), danger, 1.4)
		draw_line(reject_to + Vector2(4, -4), reject_to + Vector2(-4, 4), danger, 1.4)
		if reject_elapsed < 0.34:
			draw_string(_mono, reject_to + Vector2(13, -10), reject_reason,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, danger)

	func _draw() -> void:
		var positions := _port_positions()
		var drawn := 0
		if rack:
			for link: Net.Link in Game.links:
				if link != suppressed_link and positions.has(link.a) and positions.has(link.b):
					var colour: Color = CABLE_COLOURS[drawn % CABLE_COLOURS.size()]
					var points := _dressed_points(positions[link.a], positions[link.b], drawn % 3)
					_draw_lead(positions[link.a], positions[link.b], colour, false, drawn % 3)
					if feedback_elapsed >= 0.0 and ((link.a == feedback_a and link.b == feedback_b) \
							or (link.a == feedback_b and link.b == feedback_a)):
						_draw_confirmation(points, colour)
					drawn += 1
		if reject_elapsed >= 0.0:
			_draw_rejection()
		if active:
			var a := from - global_position
			var b := to - global_position
			var colour := UIW.colour("success") if valid_target else UIW.colour("warm")
			_draw_lead(a, b, colour, true)
			if source_iface:
				draw_string(_mono, b + Vector2(13, -10), "%s  /  %s" % [source_iface.dev.name,
					source_iface.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, colour)

# =============================================================== Faceplate ==

class Faceplate extends Control:
	const JACK_W := 30.0
	const JACK_H := 26.0
	const GAP := 9.0
	const BRAND_W := 150.0

	var dev: Net.NDevice
	var on_port: Callable  # (Net.Iface)
	var hover_idx := -1
	var config_write_elapsed := -1.0
	var _mono: SystemFont
	var _ports: Array = []  # visible ifaces

	func setup(d: Net.NDevice, cb: Callable) -> Faceplate:
		dev = d
		on_port = cb
		_mono = UIW.mono_font()
		_ports = []
		for i: Net.Iface in d.ifaces:
			if i.name != "lo" and not i.name.begins_with("Vlan") \
					and not i.name.begins_with("Tunnel") and not i.name.begins_with("wg") \
					and i.parent == "":
				_ports.append(i)
		var cols := ceili(_ports.size() / 2.0) if _ports.size() > 6 else _ports.size()
		cols = maxi(cols, 1)
		var rows := 2 if _ports.size() > 6 else 1
		custom_minimum_size = Vector2(BRAND_W + cols * (JACK_W + GAP) + 30,
			maxf(64.0, rows * (JACK_H + 22) + 22))
		mouse_filter = Control.MOUSE_FILTER_STOP
		return self

	func _jack_rect(idx: int) -> Rect2:
		var rows := 2 if _ports.size() > 6 else 1
		var col := idx / rows
		var row := idx % rows
		var y0 := (size.y - (rows * (JACK_H + 22) - 22)) / 2.0 + 6
		return Rect2(BRAND_W + col * (JACK_W + GAP) + (6 if (col / 2) % 2 == 1 else 0),
			y0 + row * (JACK_H + 22), JACK_W, JACK_H)

	func _idx_at(pos: Vector2) -> int:
		for idx in _ports.size():
			if _jack_rect(idx).grow(3).has_point(pos):
				return idx
		return -1

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			var idx := _idx_at(e.position)
			if idx != hover_idx:
				hover_idx = idx
				if idx >= 0:
					var i: Net.Iface = _ports[idx]
					var peer := Game.peer_label(i)
					tooltip_text = "%s: %s" % [i.name,
						("connected to " + peer) if peer else ("free port" if i.enabled else "disabled")]
				else:
					tooltip_text = ""
				queue_redraw()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var idx := _idx_at(e.position)
			if idx >= 0:
				on_port.call(_ports[idx])

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hover_idx = -1
			queue_redraw()

	func confirm_config_write() -> void:
		config_write_elapsed = 0.0
		queue_redraw()

	func _process(dt: float) -> void:
		if config_write_elapsed >= 0.0:
			config_write_elapsed += dt
			if config_write_elapsed >= 0.78:
				config_write_elapsed = -1.0
		queue_redraw()  # link LEDs blink

	func _draw() -> void:
		var visual := UIW.model_visual(dev.model)
		var col: Color = visual["accent"]
		var ink: Color = visual["ink"]
		# brushed panel
		var panel := Rect2(Vector2.ZERO, size)
		draw_rect(panel, visual["base"])
		for k in int(size.y / 3):
			draw_line(Vector2(1, k * 3), Vector2(size.x - 1, k * 3), Color(1, 1, 1, 0.018))
		draw_rect(panel, col.darkened(0.28), false, 1.5)
		draw_rect(Rect2(0, 0, size.x, 5), col)  # vendor accent strip
		# corner screws
		for sx in [10.0, size.x - 10.0]:
			for sy in [10.0, size.y - 10.0]:
				draw_circle(Vector2(sx, sy), 3.5, UIW.colour("console"))
				draw_circle(Vector2(sx, sy), 3.5, UIW.colour("border_strong"), false, 1.0)
				draw_line(Vector2(sx - 2, sy), Vector2(sx + 2, sy), UIW.colour("border_strong"), 1.0)
		# Model-specific logo mark and silk-screen branding. These are fictional
		# vendors, but each has a consistent visual grammar across device tiers.
		_draw_vendor_mark(String(visual["mark"]), Vector2(28, size.y / 2.0), col, ink)
		draw_string(_mono, Vector2(58, size.y / 2.0 - 4), Game.MODELS[dev.model]["label"].split(" ")[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
		draw_string(_mono, Vector2(24, size.y / 2.0 + 13),
			" ".join(PackedStringArray(Array(Game.MODELS[dev.model]["label"].split(" ")).slice(1))),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ink, 0.68))
		if dev.type == "server":
			for bay in 3:
				var bx := 104.0 + bay * 12.0
				draw_rect(Rect2(bx, size.y * 0.5 - 9, 9, 18), visual["base"].darkened(0.35))
				draw_line(Vector2(bx + 2, size.y * 0.5 + 5), Vector2(bx + 7, size.y * 0.5 + 5), col, 1.0)
		# port jacks
		var t := Time.get_ticks_msec() / 1000.0
		for idx in _ports.size():
			var i: Net.Iface = _ports[idx]
			var r := _jack_rect(idx)
			var linked := Game.link_at(i) != null
			var body := UIW.colour("console")
			var border := UIW.colour("border_strong")
			if not i.enabled:
				border = Color(0.85, 0.4, 0.35)
			elif linked:
				border = Color(0.35, 0.9, 0.5)
			if idx == hover_idx:
				body = UIW.colour("surface_hover")
				border = UIW.colour("focus")
			draw_rect(r, body)
			draw_rect(r, border, false, 1.5)
			# RJ45 tab notch
			draw_rect(Rect2(r.position.x + r.size.x * 0.3, r.end.y - 5, r.size.x * 0.4, 4), body.lightened(0.15))
			draw_rect(Rect2(r.position.x + 4, r.position.y + 3, r.size.x - 8, 3), Color(0.75, 0.62, 0.3, 0.5))  # pins
			if not i.note.is_empty():
				var tape := Rect2(r.position + Vector2(2, -7), Vector2(r.size.x - 4, 5))
				draw_rect(tape, Color("e8c96f"))
				draw_line(tape.position + Vector2(4, 2), tape.end - Vector2(4, 3),
					Color("67552c"), 1.0)
			# link LED blinks
			var led := Color(0.2, 0.22, 0.26)
			if not i.enabled:
				led = Color(0.9, 0.35, 0.25)
			elif linked and fmod(t * (2.0 + idx * 0.37), 1.0) > 0.3:
				led = Color(0.4, 1.0, 0.5)
			draw_circle(r.position + Vector2(r.size.x + 0.0, -4), 2.2, led)
			# port label
			var num := i.name.replace("Management", "M").trim_prefix("Ethernet").trim_prefix("ether").trim_prefix("eth").trim_prefix("port")
			var below := (idx % 2 == 1) if _ports.size() > 6 else true
			var ty := r.end.y + 13 if below else r.position.y - 6
			draw_string(_mono, Vector2(r.position.x + r.size.x / 2.0 - 6, ty), num if num != "" else i.name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ink, 0.72))
		if config_write_elapsed >= 0.0:
			var p := clampf(config_write_elapsed / 0.78, 0.0, 1.0)
			var fade := 1.0 - p
			var saved := Color(UIW.colour("success"), fade)
			var saved_ink := Color(Color("245f43") if visual["base"].get_luminance() > 0.42 \
				else UIW.colour("success"), fade)
			# The chassis edge catches once, like a write/status LED rather than a
			# detached success banner.
			draw_rect(panel.grow(-2), Color(saved, fade * 0.12), false, 3.0)
			draw_circle(Vector2(size.x - 18, 16), 3.0 + p * 2.0, saved)
			if config_write_elapsed < 0.56:
				draw_string(_mono, Vector2(size.x - 136, 20), "CONFIG WRITTEN",
					HORIZONTAL_ALIGNMENT_LEFT, 110, 10, saved_ink)

	func _draw_vendor_mark(mark: String, p: Vector2, col: Color, ink: Color) -> void:
		match mark:
			"packet":
				draw_line(p + Vector2(-9, 6), p + Vector2(1, -6), col, 4.0)
				draw_line(p + Vector2(0, 6), p + Vector2(10, -6), col.darkened(0.18), 4.0)
			"arivista":
				for y in 2:
					for x in 2:
						draw_rect(Rect2(p + Vector2(-9 + x * 10, -9 + y * 10), Vector2(7, 7)), col)
			"dill":
				draw_circle(p, 10, Color(col, 0.18))
				draw_circle(p, 8, col, false, 3.0)
				draw_line(p + Vector2(0, -7), p + Vector2(0, 7), col, 2.0)
			"junivista":
				draw_polyline(PackedVector2Array([p + Vector2(-10, 7), p + Vector2(-3, -7),
					p + Vector2(2, 2), p + Vector2(7, -5), p + Vector2(11, 7)]), col, 2.5)
			"shield":
				draw_polyline(PackedVector2Array([p + Vector2(0, -10), p + Vector2(9, -6),
					p + Vector2(7, 5), p + Vector2(0, 11), p + Vector2(-7, 5),
					p + Vector2(-9, -6), p + Vector2(0, -10)]), col, 2.0)
			"balance":
				draw_line(p + Vector2(-10, 0), p + Vector2(10, 0), col, 2.0)
				draw_circle(p + Vector2(-7, -4), 4, col)
				draw_circle(p + Vector2(7, 4), 4, col)
			"radio":
				for radius in [5.0, 9.0]:
					draw_arc(p, radius, PI * 1.15, PI * 1.85, 10, col, 2.0)
				draw_circle(p + Vector2(0, 5), 2.5, col)
			_:
				draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), Color(ink, 0.12))
				draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), col, false, 2.0)
