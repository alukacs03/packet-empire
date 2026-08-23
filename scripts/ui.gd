class_name UILayer
extends CanvasLayer
## All UI: toolbar, rack view, device view (faceplate + console),
## interface editor, VLAN manager.

const ACCENT := Color(0.3, 0.75, 0.85)
const BG := Color(0.07, 0.08, 0.11, 0.97)
const PANEL := Color(0.11, 0.13, 0.17)
const DIM := Color(0.02, 0.02, 0.04, 0.72)
const MUTED := Color(0.55, 0.6, 0.7)

var mode_btns := {}
var rack_overlay: Control
var rack_title: Label
var slot_box: VBoxContainer

var dev_overlay: Control
var dev_title: Label
var name_edit: LineEdit
var name_hint: Label
var status_opt: OptionButton
var port_row: HBoxContainer
var conn_list: VBoxContainer
var cli_box: VBoxContainer
var cli_out: RichTextLabel
var cli_in: LineEdit
var cli_prompt: Label
var cli_toggle: Button

var if_overlay: Control
var if_title: Label
var if_mac: Label
var if_enabled: CheckButton
var if_mtu: LineEdit
var if_mode: OptionButton
var if_vlan: OptionButton
var if_vlan_row: HBoxContainer
var if_trunk_note: Label
var if_ip_box: VBoxContainer
var if_ip_in: LineEdit
var if_ip_hint: Label
var if_cable_lbl: Label
var if_cable_btn: Button

var vlan_section: VBoxContainer
var vlan_box: VBoxContainer
var vlan_vid_in: LineEdit
var vlan_name_in: LineEdit

var cur_rack: Net.Rack
var cur_dev: Net.NDevice
var cur_if: Net.Iface
var theme_res: Theme
var mono: SystemFont

func _ready() -> void:
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo", "Consolas", "monospace"])
	theme_res = _make_theme()
	_build_toolbar()
	_build_rack_overlay()
	_build_dev_overlay()
	_build_if_overlay()
	Game.topology_changed.connect(_refresh_open)

func _process(_dt: float) -> void:
	# focus watchdog: while the console is open, dropped focus/editing returns to it
	if cli_box and cli_box.visible and not if_overlay.visible:
		if get_viewport().gui_get_focus_owner() == null:
			cli_in.grab_focus()
		if cli_in.has_focus() and not cli_in.is_editing():
			cli_in.edit()

func is_open() -> bool:
	return rack_overlay.visible or dev_overlay.visible or if_overlay.visible

# ---------- theme / widget helpers ----------

func _make_theme() -> Theme:
	var t := Theme.new()
	var n := _sb(Color(0.15, 0.17, 0.22), Color(0.25, 0.28, 0.36))
	var h := _sb(Color(0.19, 0.22, 0.29), ACCENT * Color(1, 1, 1, 0.6))
	var p := _sb(Color(0.1, 0.22, 0.27), ACCENT)
	for cls in ["Button", "OptionButton"]:
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

func _mono_edit(width := 200.0) -> LineEdit:
	var e := LineEdit.new()
	e.custom_minimum_size = Vector2(width, 0)
	e.add_theme_font_override("font", mono)
	return e

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

func _menu(at: Control, items: Array, on_pick: Callable) -> void:
	var m := PopupMenu.new()
	m.add_theme_font_override("font", mono)
	for it in items:
		m.add_item(it)
	add_child(m)
	m.id_pressed.connect(on_pick)
	m.popup_hide.connect(m.queue_free)
	m.popup(Rect2i(Vector2i(at.get_screen_position() + Vector2(0, at.size.y + 4)), Vector2i.ZERO))

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
	v.add_child(_label("Click a device to open it, or an empty slot to install hardware.", 13, MUTED))
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
			for pi in dev.ifaces:
				if Game.link_at(pi):
					up += 1
			b.text = " U%-2d  %-8s %-8s %d/%d links" % [i + 1, dev.name, dev.type, up, dev.ifaces.size()]
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
	var v := _card(dev_overlay, 760)
	dev_title = _header(v, close_dev)

	var name_row := HBoxContainer.new()
	v.add_child(name_row)
	name_row.add_child(_label("Hostname:  ", 14, MUTED))
	name_edit = _mono_edit(220)
	name_edit.text_submitted.connect(_rename_dev)
	name_row.add_child(name_edit)
	name_row.add_child(_label("   Status:  ", 14, MUTED))
	status_opt = OptionButton.new()
	status_opt.add_item("active")
	status_opt.add_item("offline")
	status_opt.item_selected.connect(func(idx: int) -> void:
		cur_dev.status = "active" if idx == 0 else "offline")
	name_row.add_child(status_opt)
	name_hint = _label("", 13, Color(0.9, 0.5, 0.45))
	name_row.add_child(name_hint)

	v.add_child(_label("FRONT PANEL — click a port to configure it", 12, MUTED))
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _sb(Color(0.14, 0.15, 0.18), Color(0.35, 0.38, 0.45), 8, 14))
	v.add_child(plate)
	port_row = HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 10)
	port_row.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(port_row)

	conn_list = VBoxContainer.new()
	v.add_child(conn_list)

	vlan_section = VBoxContainer.new()
	v.add_child(vlan_section)
	vlan_section.add_child(HSeparator.new())
	vlan_section.add_child(_label("VLAN DATABASE (this switch)", 12, MUTED))
	vlan_box = VBoxContainer.new()
	vlan_section.add_child(vlan_box)
	var vrow := HBoxContainer.new()
	vlan_section.add_child(vrow)
	vlan_vid_in = _mono_edit(70)
	vlan_vid_in.placeholder_text = "VID"
	vrow.add_child(vlan_vid_in)
	vlan_name_in = _mono_edit(180)
	vlan_name_in.placeholder_text = "name (optional)"
	vrow.add_child(vlan_name_in)
	var vadd := Button.new()
	vadd.text = "Add VLAN"
	vadd.pressed.connect(func() -> void:
		if vlan_vid_in.text.is_valid_int() \
				and Game.add_vlan(cur_dev, int(vlan_vid_in.text), vlan_name_in.text):
			vlan_vid_in.clear()
			vlan_name_in.clear())
	vrow.add_child(vadd)

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
	cli_in.keep_editing_on_text_submit = true
	cli_in.text_submitted.connect(_cli_submit)
	cli_in.gui_input.connect(_cli_key)
	h.add_child(cli_in)

func open_dev(d: Net.NDevice) -> void:
	cur_dev = d
	_refresh_dev_header()
	cli_box.visible = false
	cli_toggle.text = "Open console  ▤"
	_refresh_ports()
	dev_overlay.visible = true

func close_dev() -> void:
	dev_overlay.visible = false
	cur_dev = null

func _refresh_dev_header() -> void:
	dev_title.text = "%s  /  %s — %s" % [Game.rack_of(cur_dev).name, cur_dev.name, cur_dev.type]
	name_edit.text = cur_dev.name
	status_opt.select(0 if cur_dev.status == "active" else 1)
	name_hint.text = ""

func _rename_dev(new_name: String) -> void:
	if Game.rename_device(cur_dev, new_name):
		_refresh_dev_header()
		if cli_box.visible:
			cli_prompt.text = cur_dev.name + "> "
	else:
		name_hint.text = "  invalid or taken"
		name_edit.text = cur_dev.name

func _refresh_ports() -> void:
	for c in port_row.get_children():
		c.queue_free()
	for c in conn_list.get_children():
		c.queue_free()
	for i: Net.Iface in cur_dev.ifaces:
		var connected := Game.link_at(i) != null
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 54)
		b.text = i.name
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 12)
		if not i.enabled:
			b.add_theme_stylebox_override("normal", _sb(Color(0.25, 0.1, 0.1), Color(0.6, 0.3, 0.3), 6))
			b.tooltip_text = "Disabled"
		elif connected:
			b.add_theme_stylebox_override("normal", _sb(Color(0.08, 0.25, 0.14), Color(0.35, 0.95, 0.5), 6))
			b.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
			b.tooltip_text = "Connected to " + Game.peer_label(i)
		else:
			b.tooltip_text = "Free port"
		b.pressed.connect(open_iface.bind(i))
		port_row.add_child(b)
		if connected:
			var extra := ""
			if not i.ips.is_empty():
				extra = "   [%s]" % ", ".join(i.ips)
			elif i.mode == "access":
				extra = "   vlan %d" % i.untagged_vlan
			conn_list.add_child(_label("  %s  ⇄  %s%s" % [i.name, Game.peer_label(i), extra],
				14, Color(0.55, 0.85, 0.65)))
	if conn_list.get_child_count() == 0:
		conn_list.add_child(_label("  no cables connected", 14, Color(0.45, 0.5, 0.6)))
	_refresh_vlans()

func _refresh_vlans() -> void:
	vlan_section.visible = cur_dev.type == "switch"
	if not vlan_section.visible:
		return
	for c in vlan_box.get_children():
		c.queue_free()
	var vids := cur_dev.vlans.keys()
	vids.sort()
	for vid in vids:
		var row := HBoxContainer.new()
		var ports: Array = []
		for i: Net.Iface in cur_dev.ifaces:
			if i.mode == "access" and i.untagged_vlan == vid:
				ports.append(i.name)
		var l := _label("  %-6d %-14s %s" % [vid, cur_dev.vlans[vid], ", ".join(ports)],
			14, Color(0.7, 0.8, 0.9))
		l.add_theme_font_override("font", mono)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if vid != 1:
			var x := Button.new()
			x.text = "remove"
			x.pressed.connect(func() -> void: Game.remove_vlan(cur_dev, vid))
			row.add_child(x)
		vlan_box.add_child(row)

# ---------- interface editor ----------

func _build_if_overlay() -> void:
	if_overlay = _overlay()
	var v := _card(if_overlay, 520)
	if_title = _header(v, close_iface)

	if_mac = _label("", 13, MUTED)
	if_mac.add_theme_font_override("font", mono)
	v.add_child(if_mac)

	var row1 := HBoxContainer.new()
	v.add_child(row1)
	if_enabled = CheckButton.new()
	if_enabled.text = "Enabled"
	if_enabled.toggled.connect(func(on: bool) -> void:
		cur_if.enabled = on
		Game.topology_changed.emit())
	row1.add_child(if_enabled)
	row1.add_child(_label("   MTU: ", 14, MUTED))
	if_mtu = _mono_edit(90)
	if_mtu.text_submitted.connect(func(t: String) -> void:
		if t.is_valid_int() and int(t) >= 576 and int(t) <= 9216:
			cur_if.mtu = int(t)
		if_mtu.text = str(cur_if.mtu))
	row1.add_child(if_mtu)

	var row2 := HBoxContainer.new()
	v.add_child(row2)
	row2.add_child(_label("Mode: ", 14, MUTED))
	if_mode = OptionButton.new()
	if_mode.add_item("access")
	if_mode.add_item("trunk")
	if_mode.item_selected.connect(func(idx: int) -> void:
		cur_if.mode = "access" if idx == 0 else "trunk"
		_refresh_iface())
	row2.add_child(if_mode)
	if_vlan_row = HBoxContainer.new()
	row2.add_child(if_vlan_row)
	if_vlan_row.add_child(_label("   VLAN: ", 14, MUTED))
	if_vlan = OptionButton.new()
	if_vlan.item_selected.connect(func(idx: int) -> void:
		Game.set_access_vlan(cur_if, if_vlan.get_item_id(idx)))
	if_vlan_row.add_child(if_vlan)
	if_trunk_note = _label("   carries all VLANs (tagged)", 13, MUTED)
	row2.add_child(if_trunk_note)

	v.add_child(HSeparator.new())
	v.add_child(_label("IP ADDRESSES", 12, MUTED))
	if_ip_box = VBoxContainer.new()
	v.add_child(if_ip_box)
	var ip_row := HBoxContainer.new()
	v.add_child(ip_row)
	if_ip_in = _mono_edit(200)
	if_ip_in.placeholder_text = "10.0.0.5/24"
	if_ip_in.text_submitted.connect(_add_ip)
	ip_row.add_child(if_ip_in)
	var add_btn := Button.new()
	add_btn.text = "Add IP"
	add_btn.pressed.connect(func() -> void: _add_ip(if_ip_in.text))
	ip_row.add_child(add_btn)
	if_ip_hint = _label("", 13, Color(0.9, 0.5, 0.45))
	ip_row.add_child(if_ip_hint)

	v.add_child(HSeparator.new())
	var cable_row := HBoxContainer.new()
	v.add_child(cable_row)
	if_cable_lbl = _label("", 14)
	if_cable_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cable_row.add_child(if_cable_lbl)
	if_cable_btn = Button.new()
	if_cable_btn.pressed.connect(_cable_action)
	cable_row.add_child(if_cable_btn)

func open_iface(i: Net.Iface) -> void:
	cur_if = i
	_refresh_iface()
	if_overlay.visible = true

func close_iface() -> void:
	if_overlay.visible = false
	cur_if = null
	if dev_overlay.visible:
		_refresh_ports()

func _refresh_iface() -> void:
	if_title.text = "%s / %s" % [cur_if.dev.name, cur_if.name]
	if_mac.text = "MAC %s" % cur_if.mac
	if_enabled.set_pressed_no_signal(cur_if.enabled)
	if_mtu.text = str(cur_if.mtu)
	var is_switch := cur_if.dev.type == "switch"
	if_mode.get_parent().visible = is_switch
	if_mode.select(0 if cur_if.mode == "access" else 1)
	if_vlan_row.visible = is_switch and cur_if.mode == "access"
	if_trunk_note.visible = is_switch and cur_if.mode == "trunk"
	if_vlan.clear()
	for vid in cur_if.dev.vlans:
		if_vlan.add_item("%d (%s)" % [vid, cur_if.dev.vlans[vid]], vid)
		if vid == cur_if.untagged_vlan:
			if_vlan.select(if_vlan.item_count - 1)
	for c in if_ip_box.get_children():
		c.queue_free()
	for cidr in cur_if.ips:
		var row := HBoxContainer.new()
		var l := _label("  " + cidr, 14, Color(0.7, 0.9, 0.75))
		l.add_theme_font_override("font", mono)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var x := Button.new()
		x.text = "remove"
		x.pressed.connect(func() -> void:
			Game.remove_ip(cur_if, cidr)
			_refresh_iface())
		row.add_child(x)
		if_ip_box.add_child(row)
	if cur_if.ips.is_empty():
		if_ip_box.add_child(_label("  none", 13, Color(0.45, 0.5, 0.6)))
	if_ip_hint.text = ""
	var peer := Game.peer_label(cur_if)
	if peer == "":
		if_cable_lbl.text = "Cable: not connected"
		if_cable_btn.text = "Run cable…"
	else:
		if_cable_lbl.text = "Cable: ⇄  " + peer
		if_cable_btn.text = "Disconnect"

func _add_ip(text: String) -> void:
	if Game.add_ip(cur_if, text):
		if_ip_in.clear()
		_refresh_iface()
	else:
		if_ip_hint.text = " invalid CIDR or duplicate"

func _cable_action() -> void:
	if Game.link_at(cur_if):
		Game.disconnect_iface(cur_if)
		_refresh_iface()
		return
	var targets := Game.free_ifaces(cur_if.dev)
	if targets.is_empty():
		_menu(if_cable_btn, ["(no free ports anywhere else)"], func(_id: int) -> void: pass)
		return
	var labels: Array = []
	for t: Net.Iface in targets:
		labels.append("%-4s %-8s %s" % [Game.rack_of(t.dev).name, t.dev.name, t.name])
	_menu(if_cable_btn, labels, func(id: int) -> void:
		Game.connect_ifaces(cur_if, targets[id])
		_refresh_iface())

# ---------- refresh / CLI ----------

func _refresh_open() -> void:
	if if_overlay.visible and cur_if:
		_refresh_iface()
	if dev_overlay.visible and cur_dev:
		_refresh_ports()
	if rack_overlay.visible and cur_rack:
		_refresh_slots()

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

func _cli_key(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_TAB:
		cli_in.accept_event()
		var text := cli_in.text
		var cands := CLI.complete(cur_dev, text)
		if cands.is_empty():
			return
		var start := text.rfind(" ") + 1
		var cur := text.substr(start)
		var common: String = cands[0]
		for c: String in cands:
			while not c.begins_with(common):
				common = common.left(common.length() - 1)
		if cands.size() == 1:
			common += " "
		if common.length() > cur.length():
			cli_in.text = text.left(start) + common
			cli_in.caret_column = cli_in.text.length()
		elif cands.size() > 1:
			cli_out.append_text("  ".join(PackedStringArray(cands)) + "\n")

func _cli_submit(cmd: String) -> void:
	cli_in.clear()
	cli_in.call_deferred("grab_focus")
	cli_out.append_text("%s> %s\n" % [cur_dev.name, cmd])
	cli_out.append_text(CLI.exec(cur_dev, cmd))
	cli_prompt.text = cur_dev.name + "> "  # hostname may have changed

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if if_overlay.visible:
			close_iface()
		elif dev_overlay.visible:
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
