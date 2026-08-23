class_name UILayer
extends CanvasLayer
## All UI: toolbar, full-screen rack view, full-screen device view with
## faceplate + docked CLI.

const ACCENT := Color(0.3, 0.75, 0.85)
const BG := Color(0.07, 0.08, 0.11, 0.97)
const PANEL := Color(0.11, 0.13, 0.17)
const DIM := Color(0.02, 0.02, 0.04, 0.72)

var mode_btns := {}
var rack_overlay: Control
var rack_title: Label
var slot_box: VBoxContainer
var dev_overlay: Control
var dev_title: Label
var name_edit: LineEdit
var name_hint: Label
var port_row: HBoxContainer
var conn_list: VBoxContainer
var cli_box: VBoxContainer
var cli_out: RichTextLabel
var cli_in: LineEdit
var cli_prompt: Label
var cli_toggle: Button

var cur_rack: Net.Rack
var cur_dev: Net.NDevice
var theme_res: Theme
var mono: SystemFont

func _ready() -> void:
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo", "Consolas", "monospace"])
	theme_res = _make_theme()
	_build_toolbar()
	_build_rack_overlay()
	_build_dev_overlay()
	Game.topology_changed.connect(_refresh_open)

func _process(_dt: float) -> void:
	# focus watchdog: while the console is open, dropped focus returns to it
	if cli_box and cli_box.visible and get_viewport().gui_get_focus_owner() == null:
		cli_in.grab_focus()

func is_open() -> bool:
	return rack_overlay.visible or dev_overlay.visible

# ---------- theme ----------

func _make_theme() -> Theme:
	var t := Theme.new()
	var n := _sb(Color(0.15, 0.17, 0.22), Color(0.25, 0.28, 0.36))
	var h := _sb(Color(0.19, 0.22, 0.29), ACCENT * Color(1, 1, 1, 0.6))
	var p := _sb(Color(0.1, 0.22, 0.27), ACCENT)
	for cls in ["Button"]:
		t.set_stylebox("normal", cls, n)
		t.set_stylebox("hover", cls, h)
		t.set_stylebox("pressed", cls, p)
		t.set_stylebox("focus", cls, _sb(Color.TRANSPARENT, Color.TRANSPARENT))
		t.set_color("font_color", cls, Color(0.85, 0.89, 0.95))
		t.set_color("font_hover_color", cls, Color.WHITE)
	t.set_stylebox("panel", "PanelContainer", _sb(PANEL, Color(0.3, 0.34, 0.44), 10, 14))
	t.set_color("font_color", "Label", Color(0.85, 0.89, 0.95))
	return t

func _sb(bg: Color, border: Color, radius := 6, margin := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s

func _label(text: String, size := 15, color := Color(0.85, 0.89, 0.95)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _overlay() -> Control:
	var o := Control.new()
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	o.visible = false
	o.theme = theme_res
	var bg := ColorRect.new()
	bg.color = DIM
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.add_child(bg)
	add_child(o)
	return o

func _card(parent: Control, min_w: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_w, 0)
	panel.add_theme_stylebox_override("panel", _sb(BG, Color(0.32, 0.38, 0.5), 12, 20))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	return v

func _header(box: VBoxContainer, on_back: Callable) -> Label:
	var h := HBoxContainer.new()
	box.add_child(h)
	var title := _label("", 20, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title)
	var back := Button.new()
	back.text = "  Back (Esc)  "
	back.pressed.connect(on_back)
	h.add_child(back)
	box.add_child(HSeparator.new())
	return title

# ---------- toolbar ----------

func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.theme = theme_res
	bar.position = Vector2(20, 16)
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	bar.add_child(h)
	for m in [["Select (Q)", 0], ["Place rack (R)", 1]]:
		var b := Button.new()
		b.text = m[0]
		b.toggle_mode = true
		b.pressed.connect(func() -> void: get_parent().mode = m[1])
		h.add_child(b)
		mode_btns[m[1]] = b
	update_mode(0)

func update_mode(m: int) -> void:
	for k in mode_btns:
		mode_btns[k].button_pressed = k == m

# ---------- rack view ----------

func _build_rack_overlay() -> void:
	rack_overlay = _overlay()
	var v := _card(rack_overlay, 560)
	rack_title = _header(v, close_rack)
	v.add_child(_label("Click a device to open it, or an empty slot to install hardware.",
		13, Color(0.55, 0.6, 0.7)))
	slot_box = VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 4)
	v.add_child(slot_box)

func open_rack(r: Net.Rack) -> void:
	cur_rack = r
	dev_overlay.visible = false
	rack_title.text = "Rack %s" % r.name
	_refresh_slots()
	rack_overlay.visible = true

func close_rack() -> void:
	rack_overlay.visible = false
	cur_rack = null

func _refresh_slots() -> void:
	for c in slot_box.get_children():
		c.queue_free()
	for i in range(Net.Rack.SLOTS - 1, -1, -1):  # top of rack first
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 42)
		b.add_theme_font_override("font", mono)
		var dev: Net.NDevice = cur_rack.slots[i]
		if dev:
			var up := 0
			for pi in dev.nports:
				if Game.link_at(dev, pi):
					up += 1
			b.text = " U%-2d  %-6s %-8s %d/%d ports up" % [i + 1, dev.name, dev.type, up, dev.nports]
			b.add_theme_color_override("font_color",
				Color(0.4, 0.9, 0.95) if dev.type == "switch" else Color(0.6, 0.75, 1.0))
			b.pressed.connect(func() -> void: open_dev(dev))
		else:
			b.text = " U%-2d  — empty slot —" % [i + 1]
			b.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
			b.pressed.connect(func() -> void: _pick_new_device(i, b))
		slot_box.add_child(b)

func _pick_new_device(slot: int, at: Control) -> void:
	_menu(at, ["Install switch  (8 ports)", "Install server  (1 NIC)"], func(id: int) -> void:
		cur_rack.slots[slot] = Game.new_device("switch" if id == 0 else "server")
		cur_rack.visual.queue_redraw()
		_refresh_slots())

# ---------- device view ----------

func _build_dev_overlay() -> void:
	dev_overlay = _overlay()
	var v := _card(dev_overlay, 720)
	dev_title = _header(v, close_dev)

	var name_row := HBoxContainer.new()
	v.add_child(name_row)
	name_row.add_child(_label("Hostname:  ", 14, Color(0.55, 0.6, 0.7)))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.add_theme_font_override("font", mono)
	name_edit.text_submitted.connect(_rename_dev)
	name_row.add_child(name_edit)
	name_hint = _label("", 13, Color(0.9, 0.5, 0.45))
	name_row.add_child(name_hint)

	v.add_child(_label("FRONT PANEL", 12, Color(0.5, 0.55, 0.65)))
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _sb(Color(0.14, 0.15, 0.18), Color(0.35, 0.38, 0.45), 8, 14))
	v.add_child(plate)
	port_row = HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 10)
	port_row.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(port_row)

	conn_list = VBoxContainer.new()
	v.add_child(conn_list)

	cli_toggle = Button.new()
	cli_toggle.text = "Open console  ▤"
	cli_toggle.pressed.connect(_toggle_cli)
	v.add_child(cli_toggle)

	cli_box = VBoxContainer.new()
	cli_box.visible = false
	v.add_child(cli_box)
	cli_out = RichTextLabel.new()
	cli_out.custom_minimum_size = Vector2(0, 220)
	cli_out.scroll_following = true
	cli_out.add_theme_font_override("normal_font", mono)
	cli_out.add_theme_font_size_override("normal_font_size", 14)
	cli_out.add_theme_color_override("default_color", Color(0.75, 0.95, 0.8))
	var term_bg := PanelContainer.new()
	term_bg.add_theme_stylebox_override("panel", _sb(Color(0.03, 0.05, 0.05), Color(0.2, 0.35, 0.3), 6, 10))
	term_bg.add_child(cli_out)
	cli_box.add_child(term_bg)
	var h := HBoxContainer.new()
	cli_box.add_child(h)
	cli_prompt = _label("", 14, Color(0.5, 0.9, 0.6))
	cli_prompt.add_theme_font_override("font", mono)
	h.add_child(cli_prompt)
	cli_in = LineEdit.new()
	cli_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cli_in.add_theme_font_override("font", mono)
	cli_in.text_submitted.connect(_cli_submit)
	h.add_child(cli_in)

func open_dev(d: Net.NDevice) -> void:
	cur_dev = d
	_refresh_dev_header()
	cli_box.visible = false
	cli_toggle.text = "Open console  ▤"
	_refresh_ports()
	dev_overlay.visible = true

func _refresh_dev_header() -> void:
	dev_title.text = "%s  /  %s — %s" % [Game.rack_of(cur_dev).name, cur_dev.name, cur_dev.type]
	name_edit.text = cur_dev.name
	name_hint.text = ""

func _rename_dev(new_name: String) -> void:
	if Game.rename_device(cur_dev, new_name):
		_refresh_dev_header()
		if cli_box.visible:
			cli_prompt.text = cur_dev.name + "> "
	else:
		name_hint.text = "  invalid or taken (letters, digits, _, no spaces)"
		name_edit.text = cur_dev.name

func close_dev() -> void:
	dev_overlay.visible = false
	cur_dev = null

func _refresh_ports() -> void:
	for c in port_row.get_children():
		c.queue_free()
	for c in conn_list.get_children():
		c.queue_free()
	for i in cur_dev.nports:
		var connected := Game.link_at(cur_dev, i) != null
		var b := Button.new()
		b.custom_minimum_size = Vector2(54, 54)
		b.text = str(i + 1)
		b.add_theme_font_override("font", mono)
		if connected:
			b.add_theme_stylebox_override("normal", _sb(Color(0.08, 0.25, 0.14), Color(0.35, 0.95, 0.5), 6))
			b.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
			b.tooltip_text = "Connected to " + Game.peer_label(cur_dev, i)
			b.pressed.connect(_pick_disconnect.bind(i, b))
		else:
			b.tooltip_text = "Free port — click to run a cable"
			b.pressed.connect(_pick_cable_target.bind(i, b))
		port_row.add_child(b)
		if connected:
			conn_list.add_child(_label("  port %d  ⇄  %s" % [i + 1, Game.peer_label(cur_dev, i)],
				14, Color(0.55, 0.85, 0.65)))
	if conn_list.get_child_count() == 0:
		conn_list.add_child(_label("  no cables connected", 14, Color(0.45, 0.5, 0.6)))

func _pick_disconnect(i: int, at: Control) -> void:
	_menu(at, ["Disconnect cable  (⇄ %s)" % Game.peer_label(cur_dev, i)], func(_id: int) -> void:
		Game.disconnect_port(cur_dev, i))

func _pick_cable_target(i: int, at: Control) -> void:
	var targets := Game.free_ports(cur_dev)
	if targets.is_empty():
		_menu(at, ["(no free ports anywhere else)"], func(_id: int) -> void: pass)
		return
	var labels: Array = []
	for t in targets:
		labels.append("%s   %-6s port %d" % [Game.rack_of(t[0]).name, t[0].name, t[1] + 1])
	_menu(at, labels, func(id: int) -> void:
		Game.connect_ports(cur_dev, i, targets[id][0], targets[id][1]))

func _refresh_open() -> void:
	if dev_overlay.visible:
		_refresh_ports()
	if rack_overlay.visible:
		_refresh_slots()

func _menu(at: Control, items: Array, on_pick: Callable) -> void:
	var m := PopupMenu.new()
	m.add_theme_font_override("font", mono)
	for it in items:
		m.add_item(it)
	add_child(m)
	m.id_pressed.connect(on_pick)
	m.popup_hide.connect(m.queue_free)
	m.popup(Rect2i(Vector2i(at.get_screen_position() + Vector2(0, at.size.y + 4)), Vector2i.ZERO))

# ---------- CLI ----------

func _toggle_cli() -> void:
	cli_box.visible = not cli_box.visible
	if cli_box.visible:
		cli_toggle.text = "Close console  ▤"
		cli_prompt.text = cur_dev.name + "> "
		if cli_out.text == "":
			cli_out.text = "%s serial console — type 'help'\n" % cur_dev.name
		cli_in.call_deferred("grab_focus")
	else:
		cli_toggle.text = "Open console  ▤"
		cli_out.text = ""

func _cli_submit(cmd: String) -> void:
	cli_in.clear()
	cli_in.call_deferred("grab_focus")
	cli_out.append_text("%s> %s\n" % [cur_dev.name, cmd])
	var out := ""
	match cmd.strip_edges():
		"":
			pass
		"help":
			out = "Commands: help, show ports, show version\n"
		"show version":
			out = "%s — PacketOS 0.1 (%s, %d ports)\n" % [cur_dev.name, cur_dev.type, cur_dev.nports]
		"show ports":
			for i in cur_dev.nports:
				var peer := Game.peer_label(cur_dev, i)
				out += "port %-2d  %-4s  %s\n" % [i + 1, "up" if peer else "down", peer if peer else "-"]
		_:
			out = "%% Unknown command. Full networking CLI arrives with the packet sim.\n"
	cli_out.append_text(out)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if dev_overlay.visible:
			if cli_box.visible:
				_toggle_cli()
			else:
				close_dev()
				if cur_rack:
					rack_overlay.visible = true
		elif rack_overlay.visible:
			close_rack()
		else:
			return
		get_viewport().set_input_as_handled()
