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
var port_row: VBoxContainer
var conn_list: VBoxContainer
var cap_box: VBoxContainer
var cap_out: RichTextLabel
var cap_toggle: Button
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
var if_nat: OptionButton
var if_nat_row: HBoxContainer
var if_mode: OptionButton
var if_vlan: OptionButton
var if_vlan_row: HBoxContainer
var if_trunk_note: Label
var if_trunk_edit: LineEdit
var if_ip_section: VBoxContainer
var if_ip_box: VBoxContainer
var if_ip_in: LineEdit
var if_ip_hint: Label
var if_cable_lbl: Label
var if_cable_btn: Button
var if_peer_btn: Button

var pedia_overlay: Control
var pedia_body: RichTextLabel
var menu_overlay: Control
var map_overlay: Control
var welcome_overlay: Control
var tutorial_panel: PanelContainer
var tutorial_box: VBoxContainer
var contracts_overlay: Control
var contracts_box: VBoxContainer
var vlan_section: VBoxContainer
var vlan_box: VBoxContainer
var vlan_vid_in: LineEdit
var vlan_name_in: LineEdit

var cur_rack: Net.Rack
var cur_dev: Net.NDevice
var cur_if: Net.Iface
var cli_session: CLI.Session
var cli_stack: Array = []  # ssh nesting
var cli_history: Array = []
var cli_hist_idx := 0
var money_lbl: Label
var cycle_lbl: Label
var contracts_btn: Button
var expand_btn: Button
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
	_build_contracts_overlay()
	_build_welcome()
	_build_map()
	_build_menu()
	_build_pedia()
	_build_tutorial()
	Game.topology_changed.connect(_refresh_tutorial)
	Game.money_changed.connect(_refresh_tutorial)
	Game.topology_changed.connect(_refresh_open)
	Game.topology_changed.connect(_refresh_money)
	Game.money_changed.connect(_refresh_money)
	Game.money_changed.connect(_money_flash)
	_refresh_money()

func _money_flash() -> void:
	money_lbl.modulate = Color(1.6, 1.6, 1.2)
	create_tween().tween_property(money_lbl, "modulate", Color.WHITE, 0.5)

func _refresh_attention() -> void:
	if contracts_btn == null:
		return
	var n := Game.offers.size()
	for deal in Game.deals:
		if not deal["healthy"]:
			n += 1
	for cid in Game.sla_status:
		if not Game.sla_status[cid]:
			n += 1
	if n > 0:
		contracts_btn.text = "Contracts (%d!)" % n
		contracts_btn.modulate = Color(1.15, 0.95, 0.7)
	else:
		contracts_btn.text = "Contracts"
		contracts_btn.modulate = Color.WHITE

func _refresh_money() -> void:
	_refresh_attention()
	var power := ""
	if Game.stage >= 1:
		power = "   ⚡%dW / ❄%dW" % [Game.power_draw(), Game.cooling_capacity()]
		if Game.overheating():
			power += "  🔥 OVERHEATING"
	var debt_s := ("  (debt $%d)" % Game.debt) if Game.debt > 0 else ""
	money_lbl.text = "  $%d%s   ♦%d%s" % [Game.money, debt_s, Game.reputation, power]
	money_lbl.tooltip_text = "Money · Reputation (drives customer budgets) · Power/Cooling"
	money_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.35) if Game.overheating() else Color(0.55, 0.95, 0.6))
	if Game.stage < Game.STAGES.size() - 1:
		var nxt: Dictionary = Game.STAGES[Game.stage + 1]
		expand_btn.text = "Expand: %s ($%d)" % [nxt["name"], nxt["price"]]
		expand_btn.tooltip_text = nxt["blurb"]
		expand_btn.visible = true
	else:
		expand_btn.visible = false

var _cycle_lbl_accum := 0.0

func _process(_dt: float) -> void:
	_cycle_lbl_accum += _dt
	if _cycle_lbl_accum > 0.5 and cycle_lbl:
		_cycle_lbl_accum = 0.0
		var t := Game.cycle_timer
		if t:
			cycle_lbl.text = "⏱ %ds" % int(ceil(t.time_left))
	# focus watchdog: while the console is open, dropped focus/editing returns to it
	if cli_box and cli_box.visible and not if_overlay.visible:
		if get_viewport().gui_get_focus_owner() == null:
			cli_in.grab_focus()
		if cli_in.has_focus() and not cli_in.is_editing():
			cli_in.edit()

func is_open() -> bool:
	return rack_overlay.visible or dev_overlay.visible or if_overlay.visible \
		or contracts_overlay.visible or welcome_overlay.visible or map_overlay.visible \
		or menu_overlay.visible or pedia_overlay.visible

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

func _accent(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", _sb(Color(0.1, 0.28, 0.34), ACCENT * Color(1, 1, 1, 0.8), 6))
	b.add_theme_stylebox_override("hover", _sb(Color(0.14, 0.36, 0.44), ACCENT, 6))
	b.add_theme_color_override("font_color", Color(0.8, 0.97, 1.0))
	return b

func _section(text: String) -> Label:
	return _label(text, 11, Color(0.5, 0.58, 0.72))

func _show_overlay(o: Control) -> void:
	o.modulate.a = 0.0
	o.visible = true
	create_tween().tween_property(o, "modulate:a", 1.0, 0.13)

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
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)
	var tick := ColorRect.new()
	tick.color = ACCENT
	tick.custom_minimum_size = Vector2(4, 24)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tick)
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
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var sb := _sb(Color(0.05, 0.06, 0.1, 0.92), Color.TRANSPARENT, 0, 10)
	sb.border_color = Color(0.25, 0.5, 0.6, 0.5)
	sb.border_width_bottom = 1
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	bar.add_theme_stylebox_override("panel", sb)
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	bar.add_child(h)
	var logo := _label("▦  PACKET EMPIRE", 17, ACCENT)
	logo.add_theme_font_override("font", mono)
	h.add_child(logo)
	h.add_child(VSeparator.new())
	for m in [["Select (Q)", 0], ["Place rack (R)", 1]]:
		var b := Button.new()
		b.text = m[0]
		b.toggle_mode = true
		b.pressed.connect(func() -> void: get_parent().mode = m[1])
		h.add_child(b)
		mode_btns[m[1]] = b
	var learnb := Button.new()
	learnb.text = "Learn"
	learnb.pressed.connect(open_pedia)
	h.add_child(learnb)
	var mapb := Button.new()
	mapb.text = "Map (M)"
	mapb.pressed.connect(toggle_map)
	h.add_child(mapb)
	contracts_btn = Button.new()
	contracts_btn.text = "Contracts"
	_accent(contracts_btn)
	contracts_btn.pressed.connect(open_contracts)
	h.add_child(contracts_btn)
	expand_btn = Button.new()
	expand_btn.pressed.connect(func() -> void:
		if Game.expand():
			_refresh_money())
	h.add_child(expand_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	cycle_lbl = _label("", 13, Color(0.5, 0.58, 0.7))
	cycle_lbl.add_theme_font_override("font", mono)
	cycle_lbl.tooltip_text = "Time to the next revenue cycle: fees, bills, SLA checks"
	h.add_child(cycle_lbl)
	money_lbl = _label("", 17, Color(0.55, 0.95, 0.6))
	money_lbl.add_theme_font_override("font", mono)
	h.add_child(money_lbl)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(func() -> void: Game.save_game())
	h.add_child(save_btn)
	update_mode(0)
	var hint := _label("Q select   ·   R place rack   ·   right-drag pan   ·   scroll zoom   ·   Esc back", 12, Color(0.45, 0.5, 0.62))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -30)
	hint.theme = theme_res
	add_child(hint)

func update_mode(m: int) -> void:
	for k in mode_btns:
		mode_btns[k].button_pressed = k == m

# ---------- rack view ----------

func _build_rack_overlay() -> void:
	rack_overlay = _overlay()
	var v := _card(rack_overlay, 560)
	rack_title = _header(v, close_rack)
	var info_row := HBoxContainer.new()
	v.add_child(info_row)
	var info := _label("Click a device to open it, or an empty slot to install hardware.", 13, MUTED)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(info)
	var sell := Button.new()
	sell.text = "Sell rack ($%d)" % (Game.RACK_PRICE / 2)
	sell.tooltip_text = "Only empty racks can be sold"
	sell.pressed.connect(func() -> void:
		if Game.sell_rack(cur_rack):
			close_rack())
	info_row.add_child(sell)
	var cabinet := PanelContainer.new()
	var cab_sb := _sb(Color(0.08, 0.09, 0.12), Color(0.38, 0.42, 0.5), 4, 6)
	cab_sb.border_width_top = 8
	cab_sb.border_width_bottom = 8
	cabinet.add_theme_stylebox_override("panel", cab_sb)
	v.add_child(cabinet)
	slot_box = VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 3)
	cabinet.add_child(slot_box)

func open_rack(r: Net.Rack) -> void:
	cur_rack = r
	dev_overlay.visible = false
	rack_title.text = "Rack %s" % r.name
	_refresh_slots()
	_show_overlay(rack_overlay)

func close_rack() -> void:
	rack_overlay.visible = false
	cur_rack = null

func _refresh_slots() -> void:
	for c in slot_box.get_children():
		c.queue_free()
	for i in range(Net.Rack.SLOTS - 1, -1, -1):  # top of rack first
		var dev: Net.NDevice = cur_rack.slots[i]
		var slot := UIW.RackSlot.new()
		if dev:
			slot.setup(i + 1, dev, func() -> void: open_dev(dev))
		else:
			var idx := i
			slot.setup(i + 1, null, func() -> void: _pick_new_device(idx, slot))
		slot_box.add_child(slot)

func _pick_new_device(slot: int, at: Control) -> void:
	var keys := Game.MODELS.keys()
	var m := PopupMenu.new()
	m.add_theme_font_override("font", mono)
	for k in keys:
		var mod: Dictionary = Game.MODELS[k]
		var locked: bool = int(mod.get("tier", 0)) > Game.stage
		var line := "%-24s %-8s %2d ports  $%d" % [mod["label"], mod["type"], mod["ports"], mod["price"]]
		if locked:
			line += "   🔒 needs %s" % Game.STAGES[int(mod["tier"])]["name"]
		m.add_item(line)
		m.set_item_disabled(m.item_count - 1, locked)
	add_child(m)
	m.id_pressed.connect(func(id: int) -> void:
		if not Game.try_spend(Game.MODELS[keys[id]]["price"]):
			return
		cur_rack.slots[slot] = Game.new_device(keys[id])
		cur_rack.visual.queue_redraw()
		_refresh_slots())
	m.popup_hide.connect(m.queue_free)
	m.popup(Rect2i(Vector2i(at.get_screen_position() + Vector2(0, at.size.y + 4)), Vector2i.ZERO))

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
		cur_dev.status = "active" if idx == 0 else "offline"
		Game.topology_changed.emit())
	name_row.add_child(status_opt)
	name_hint = _label("", 13, Color(0.9, 0.5, 0.45))
	name_row.add_child(name_hint)

	v.add_child(_section("FRONT PANEL — CLICK A PORT TO CONFIGURE"))
	var plate := PanelContainer.new()
	var plate_sb := _sb(Color(0.1, 0.11, 0.14), Color(0.4, 0.44, 0.52), 10, 16)
	plate_sb.border_width_top = 3
	plate.add_theme_stylebox_override("panel", plate_sb)
	v.add_child(plate)
	port_row = VBoxContainer.new()
	port_row.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(port_row)

	conn_list = VBoxContainer.new()
	v.add_child(conn_list)

	vlan_section = VBoxContainer.new()
	v.add_child(vlan_section)
	vlan_section.add_child(HSeparator.new())
	vlan_section.add_child(_section("VLAN DATABASE (THIS SWITCH)"))
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

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	v.add_child(btn_row)
	cli_toggle = Button.new()
	cli_toggle.text = "Open console  ▤"
	cli_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cli_toggle.pressed.connect(_toggle_cli)
	btn_row.add_child(cli_toggle)
	cap_toggle = Button.new()
	cap_toggle.text = "Packets ⇅"
	cap_toggle.tooltip_text = "Live capture (tcpdump) of this device"
	cap_toggle.pressed.connect(func() -> void:
		cap_box.visible = not cap_box.visible
		_refresh_capture())
	btn_row.add_child(cap_toggle)
	var uninstall := Button.new()
	uninstall.text = "Uninstall (50% refund)"
	uninstall.pressed.connect(func() -> void:
		var dev := cur_dev
		close_dev()
		Game.uninstall_device(dev)
		if cur_rack:
			_show_overlay(rack_overlay))
	btn_row.add_child(uninstall)

	cap_box = VBoxContainer.new()
	cap_box.visible = false
	v.add_child(cap_box)
	cap_out = RichTextLabel.new()
	cap_out.custom_minimum_size = Vector2(0, 170)
	cap_out.add_theme_font_override("normal_font", mono)
	cap_out.add_theme_font_size_override("normal_font_size", 12)
	cap_out.add_theme_color_override("default_color", Color(0.75, 0.85, 0.95))
	var cap_bg := PanelContainer.new()
	cap_bg.add_theme_stylebox_override("panel", _sb(Color(0.04, 0.05, 0.07), Color(0.3, 0.35, 0.45), 6, 10))
	cap_bg.add_child(cap_out)
	cap_box.add_child(cap_bg)
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
	cap_box.visible = false
	cli_toggle.text = "Open console  ▤"
	_refresh_ports()
	_show_overlay(dev_overlay)

func close_dev() -> void:
	dev_overlay.visible = false
	cur_dev = null

func _refresh_dev_header() -> void:
	dev_title.text = "%s  /  %s — %s" % [Game.rack_of(cur_dev).name, cur_dev.name, Game.MODELS[cur_dev.model]["label"]]
	name_edit.text = cur_dev.name
	status_opt.select(0 if cur_dev.status == "active" else 1)
	name_hint.text = ""

func _rename_dev(new_name: String) -> void:
	if Game.rename_device(cur_dev, new_name):
		_refresh_dev_header()
		if cli_box.visible and cli_session:
			cli_prompt.text = cli_session.prompt() + " "
	else:
		name_hint.text = "  invalid or taken"
		name_edit.text = cur_dev.name

func _refresh_ports() -> void:
	for c in port_row.get_children():
		c.queue_free()
	for c in conn_list.get_children():
		c.queue_free()
	var center := CenterContainer.new()
	center.add_child(UIW.Faceplate.new().setup(cur_dev, open_iface))
	port_row.add_child(center)
	for i: Net.Iface in cur_dev.ifaces:
		var connected := Game.link_at(i) != null
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
	if_nat_row = HBoxContainer.new()
	if_nat_row.add_child(_label("   NAT: ", 14, MUTED))
	if_nat = OptionButton.new()
	for opt in ["none", "inside", "outside"]:
		if_nat.add_item(opt)
	if_nat.item_selected.connect(func(idx: int) -> void:
		cur_if.nat = "" if idx == 0 else ["", "inside", "outside"][idx]
		Game.topology_changed.emit())
	if_nat_row.add_child(if_nat)
	row1.add_child(_label("   MTU: ", 14, MUTED))
	if_mtu = _mono_edit(90)
	if_mtu.text_submitted.connect(func(t: String) -> void:
		if t.is_valid_int() and int(t) >= 576 and int(t) <= 9216:
			cur_if.mtu = int(t)
		if_mtu.text = str(cur_if.mtu))
	row1.add_child(if_mtu)
	row1.add_child(if_nat_row)

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
	if_trunk_note = _label("   allowed VLANs: ", 13, MUTED)
	row2.add_child(if_trunk_note)
	if_trunk_edit = _mono_edit(110)
	if_trunk_edit.placeholder_text = "all"
	if_trunk_edit.tooltip_text = "Comma-separated VIDs allowed on this trunk; empty = all"
	if_trunk_edit.text_submitted.connect(func(t: String) -> void:
		var vids: Array = []
		for part in t.split(",", false):
			if part.strip_edges().is_valid_int():
				vids.append(int(part.strip_edges()))
		cur_if.tagged_vlans = vids
		Game.topology_changed.emit())
	row2.add_child(if_trunk_edit)

	if_ip_section = VBoxContainer.new()
	v.add_child(if_ip_section)
	if_ip_section.add_child(HSeparator.new())
	if_ip_section.add_child(_section("IP ADDRESSES"))
	if_ip_box = VBoxContainer.new()
	if_ip_section.add_child(if_ip_box)
	var ip_row := HBoxContainer.new()
	if_ip_section.add_child(ip_row)
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
	if_peer_btn = Button.new()
	if_peer_btn.text = "Go to other end ⇄"
	if_peer_btn.pressed.connect(func() -> void:
		var l := Game.link_at(cur_if)
		if l:
			var peer := l.other(cur_if)
			cur_dev = peer.dev
			cur_rack = Game.rack_of(peer.dev)
			_refresh_dev_header()
			_refresh_ports()
			open_iface(peer))
	cable_row.add_child(if_peer_btn)
	if_cable_btn = Button.new()
	if_cable_btn.pressed.connect(_cable_action)
	cable_row.add_child(if_cable_btn)

func open_iface(i: Net.Iface) -> void:
	cur_if = i
	_refresh_iface()
	_show_overlay(if_overlay)

func close_iface() -> void:
	if_overlay.visible = false
	cur_if = null
	if dev_overlay.visible:
		_refresh_ports()

func _refresh_iface() -> void:
	if_title.text = "%s / %s" % [cur_if.dev.name, cur_if.name]
	if_mac.text = "MAC %s      RX %d / TX %d frames" % [cur_if.mac, cur_if.rx_frames, cur_if.tx_frames]
	if_enabled.set_pressed_no_signal(cur_if.enabled)
	if_mtu.text = str(cur_if.mtu)
	var is_switch := cur_if.dev.type == "switch"
	if_nat_row.visible = cur_if.dev.ip_forwarding and cur_if.dev.type != "uplink"
	if_nat.select({"": 0, "inside": 1, "outside": 2}[cur_if.nat])
	if_ip_section.visible = not is_switch or cur_if.name.begins_with("Management")
	if_mode.get_parent().visible = is_switch
	if_mode.select(0 if cur_if.mode == "access" else 1)
	if_vlan_row.visible = is_switch and cur_if.mode == "access"
	if_trunk_note.visible = is_switch and cur_if.mode == "trunk"
	if_trunk_edit.visible = if_trunk_note.visible
	if_trunk_edit.text = ",".join(cur_if.tagged_vlans.map(func(v): return str(v)))
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
		if_peer_btn.visible = false
	else:
		if_cable_lbl.text = "Cable: ⇄  " + peer
		if_cable_btn.text = "Disconnect"
		if_peer_btn.visible = true

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

# ---------- encyclopedia ----------

func _build_pedia() -> void:
	pedia_overlay = _overlay()
	var v := _card(pedia_overlay, 860)
	var t := _header(v, func() -> void: pedia_overlay.visible = false)
	t.text = "Networkopedia"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	var topics := VBoxContainer.new()
	topics.add_theme_constant_override("separation", 2)
	topics.custom_minimum_size = Vector2(230, 480)
	h.add_child(topics)
	pedia_body = RichTextLabel.new()
	pedia_body.custom_minimum_size = Vector2(560, 480)
	pedia_body.add_theme_font_size_override("normal_font_size", 15)
	pedia_body.add_theme_color_override("default_color", Color(0.82, 0.86, 0.93))
	h.add_child(pedia_body)
	for entry in Pedia.TOPICS:
		var b := Button.new()
		b.text = entry[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			pedia_body.clear()
			pedia_body.append_text("[b]%s[/b]\n\n%s" % [entry[0], entry[1]]))
		topics.add_child(b)
	pedia_body.bbcode_enabled = true
	pedia_body.append_text("[b]Networkopedia[/b]\n\nPick a topic on the left. Every article ends with the exact in-game commands to try it yourself.")

func open_pedia() -> void:
	_show_overlay(pedia_overlay)

# ---------- system menu ----------

func _build_menu() -> void:
	menu_overlay = _overlay()
	var v := _card(menu_overlay, 340)
	var t := _header(v, func() -> void: menu_overlay.visible = false)
	t.text = "Packet Empire"
	var resume := Button.new()
	resume.text = "Resume"
	_accent(resume)
	resume.pressed.connect(func() -> void: menu_overlay.visible = false)
	v.add_child(resume)
	var save := Button.new()
	save.text = "Save game"
	save.pressed.connect(func() -> void:
		Game.save_game()
		menu_overlay.visible = false)
	v.add_child(save)
	var newg := Button.new()
	newg.text = "New game (wipes save!)"
	newg.pressed.connect(func() -> void:
		_menu(newg, ["Yes, start over — my datacenter will be GONE"], func(_id: int) -> void:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
			get_tree().reload_current_scene()))
	v.add_child(newg)
	var quit := Button.new()
	quit.text = "Save & quit"
	quit.pressed.connect(func() -> void:
		Game.save_game()
		get_tree().quit())
	v.add_child(quit)

func toggle_menu() -> void:
	if menu_overlay.visible:
		menu_overlay.visible = false
	elif not is_open():
		_show_overlay(menu_overlay)

# ---------- topology map ----------

func _build_map() -> void:
	map_overlay = _overlay()
	map_overlay.add_child(UIW.TopoMap.new().setup(func(dev: Net.NDevice) -> void:
		map_overlay.visible = false
		cur_rack = Game.rack_of(dev)
		open_dev(dev)))

func toggle_map() -> void:
	if map_overlay.visible:
		map_overlay.visible = false
	elif not is_open():
		_show_overlay(map_overlay)

# ---------- tutorial checklist ----------

func _build_tutorial() -> void:
	tutorial_panel = PanelContainer.new()
	tutorial_panel.theme = theme_res
	tutorial_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tutorial_panel.position = Vector2(-340, 70)
	tutorial_panel.custom_minimum_size = Vector2(320, 0)
	tutorial_panel.add_theme_stylebox_override("panel", _sb(Color(0.07, 0.09, 0.12, 0.94), ACCENT * Color(1, 1, 1, 0.5), 8, 12))
	add_child(tutorial_panel)
	tutorial_box = VBoxContainer.new()
	tutorial_box.add_theme_constant_override("separation", 5)
	tutorial_panel.add_child(tutorial_box)
	_refresh_tutorial()

func _refresh_tutorial() -> void:
	if tutorial_panel == null:
		return
	if "rackup" in Game.contracts_done:
		tutorial_panel.visible = false
		return
	tutorial_panel.visible = true
	for c in tutorial_box.get_children():
		c.queue_free()
	tutorial_box.add_child(_section("GETTING STARTED"))
	var servers := 0
	var cabled := 0
	for d in Game.all_devices():
		if d.type == "server":
			servers += 1
			for i: Net.Iface in d.ifaces:
				var l := Game.link_at(i)
				if l and l.other(i).dev.type == "switch":
					cabled += 1
					break
	var switches := 0
	for d in Game.all_devices():
		if d.type == "switch":
			switches += 1
	var steps := [
		["Buy a rack: press R, click a floor tile", Game.racks.size() >= 1],
		["Click the rack, install a switch", switches >= 1],
		["Install two servers (Dill R110)", servers >= 2],
		["Cable both servers: click a port, Run cable", cabled >= 2],
		["Open Contracts, collect 'Rack and stack'", false],
	]
	var next_found := false
	for st in steps:
		var done: bool = st[1]
		var mark := "●" if done else "○"
		var col := Color(0.5, 0.9, 0.6) if done else Color(0.6, 0.65, 0.75)
		if not done and not next_found:
			next_found = true
			col = Color(0.85, 0.95, 1.0)
			mark = "▸"
		var l := _label("%s  %s" % [mark, st[0]], 13, col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(290, 0)
		tutorial_box.add_child(l)

# ---------- welcome ----------

func _build_welcome() -> void:
	welcome_overlay = _overlay()
	var v := _card(welcome_overlay, 620)
	var t := _header(v, func() -> void: welcome_overlay.visible = false)
	t.text = "Welcome to Packet Empire"
	var body := _label("You run a tiny corner of a colocation floor, and you're going to grow it into a datacenter empire — by actually learning networking.\n\nHow to play:\n   •  Right/middle-drag pans, scroll zooms\n   •  Place rack (R), then click a rack to open it\n   •  Install switches and servers into rack slots\n   •  Click a port to configure it or run a cable\n   •  Every device has a real console (Open console)\n\nEverything costs money — contracts pay. Open Contracts (toolbar) and take the first job. The briefs teach you every command you need.", 15, Color(0.8, 0.85, 0.92))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	v.add_child(body)
	var go := Button.new()
	go.text = "Open Contracts"
	_accent(go)
	go.pressed.connect(func() -> void:
		welcome_overlay.visible = false
		open_contracts())
	v.add_child(go)

func show_welcome() -> void:
	_show_overlay(welcome_overlay)

# ---------- contracts ----------

func _build_contracts_overlay() -> void:
	contracts_overlay = _overlay()
	var v := _card(contracts_overlay, 640)
	var t := _header(v, close_contracts)
	t.text = "Contracts"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 480)
	v.add_child(scroll)
	contracts_box = VBoxContainer.new()
	contracts_box.add_theme_constant_override("separation", 10)
	contracts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(contracts_box)

func open_contracts() -> void:
	_refresh_contracts()
	_show_overlay(contracts_overlay)

func close_contracts() -> void:
	contracts_overlay.visible = false

func _chip(text: String, col: Color) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(Color(col, 0.18), Color(col, 0.75), 4, 4))
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := _label(text, 10, col.lightened(0.3))
	pc.add_child(l)
	return pc

func _chip_row(chip_text: String, chip_col: Color, text: String, size: int, col: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(_chip(chip_text, chip_col))
	h.add_child(_label(text, size, col))
	return h

func _build_market_section() -> void:
	var bank := HBoxContainer.new()
	bank.add_theme_constant_override("separation", 10)
	contracts_box.add_child(bank)
	bank.add_child(_label("BANK   debt $%d   (%d%%/cycle interest)" % [Game.debt, int(Game.LOAN_RATE * 100)],
		13, Color(0.7, 0.75, 0.85) if Game.debt == 0 else Color(0.95, 0.75, 0.5)))
	var borrow := Button.new()
	borrow.text = "Borrow $%d" % Game.LOAN_TRANCHE
	borrow.disabled = Game.debt + Game.LOAN_TRANCHE > Game.LOAN_MAX
	borrow.pressed.connect(func() -> void:
		Game.borrow()
		_refresh_contracts())
	bank.add_child(borrow)
	if Game.debt > 0:
		var repay := Button.new()
		repay.text = "Repay $%d" % mini(Game.LOAN_TRANCHE, Game.debt)
		repay.disabled = Game.money < mini(Game.LOAN_TRANCHE, Game.debt)
		repay.pressed.connect(func() -> void:
			Game.repay()
			_refresh_contracts())
		bank.add_child(repay)
	contracts_box.add_child(_label("cycle %d   ·   lifetime earned $%d   ·   %d contracts, %d deals   ·   %d incidents, %d field faults" % [Game.cycle, Game.stats["earned"], Game.stats["contracts"], Game.stats["deals"], Game.stats["incidents"], Game.stats["faults"]], 12, Color(0.5, 0.56, 0.68)))
	if not Game.events.is_empty():
		contracts_box.add_child(_section("EVENT LOG"))
		for ev in Game.events.slice(0, 4):
			var col := Color(0.75, 0.8, 0.88)
			if "SECURITY" in ev:
				col = Color(0.95, 0.55, 0.45)
			elif "OVERHEAT" in ev:
				col = Color(0.95, 0.7, 0.4)
			var l := _label(ev, 12, col)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(560, 0)
			contracts_box.add_child(l)
	if not Game.offers.is_empty():
		contracts_box.add_child(_section("INCOMING OFFERS — QUOTE A PRICE PER REVENUE CYCLE"))
	for offer: Dictionary in Game.offers:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _sb(Color(0.12, 0.1, 0.15), Color(0.6, 0.5, 0.8, 0.5), 8, 14))
		contracts_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		cv.add_child(_label("%s   (%s — they seem %s)" % [offer["customer"], offer["kind"], offer["hint"]],
			16, Color.WHITE))
		var brief := _label(offer["brief"], 14, Color(0.78, 0.8, 0.88))
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.custom_minimum_size = Vector2(560, 0)
		cv.add_child(brief)
		cv.add_child(_label("💡 " + offer["costs"], 13, Color(0.6, 0.65, 0.55)))
		cv.add_child(_label("Offer expires in %d cycle(s)." % int(offer["ttl"]), 12, MUTED))
		if offer["state"] == "counter":
			cv.add_child(_label("They countered: \"Best we can do is $%d per cycle.\"" % int(offer["budget"]),
				14, Color(1.0, 0.8, 0.4)))
			var row := HBoxContainer.new()
			cv.add_child(row)
			var acc := Button.new()
			acc.text = "Accept $%d/cycle" % int(offer["budget"])
			_accent(acc)
			acc.pressed.connect(func() -> void:
				Game.accept_counter(offer)
				_refresh_contracts())
			row.add_child(acc)
			var wa := Button.new()
			wa.text = "Walk away"
			wa.pressed.connect(func() -> void:
				Game.dismiss_offer(offer)
				_refresh_contracts())
			row.add_child(wa)
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			cv.add_child(row)
			row.add_child(_label("Your price:  $", 14))
			var quote := _mono_edit(90)
			quote.placeholder_text = "75"
			row.add_child(quote)
			row.add_child(_label("/cycle  ", 14, MUTED))
			var send := Button.new()
			send.text = "Send quote"
			_accent(send)
			send.pressed.connect(func() -> void:
				if not quote.text.strip_edges().is_valid_int():
					return
				var res: String = Game.respond_offer(offer, int(quote.text.strip_edges()))
				_refresh_contracts()
				if res == "rejected":
					_toast("%s: \"That's robbery. We're going elsewhere.\"" % offer["customer"])
				elif res == "accepted":
					_toast("%s signed at $%s/cycle. Now deliver it!" % [offer["customer"], quote.text.strip_edges()]))
			row.add_child(send)
			var dis := Button.new()
			dis.text = "Decline"
			dis.pressed.connect(func() -> void:
				Game.dismiss_offer(offer)
				_refresh_contracts())
			row.add_child(dis)
	if not Game.deals.is_empty():
		contracts_box.add_child(_section("ACTIVE DEALS"))
		for deal: Dictionary in Game.deals:
			var ok: bool = deal["healthy"]
			contracts_box.add_child(_chip_row(
				"PAYING" if ok else "DOWN",
				Color(0.4, 0.85, 0.5) if ok else Color(0.95, 0.45, 0.35),
				"%s — %s   $%d/cycle%s" % [deal["customer"], deal["kind"], int(deal["fee"]),
					"" if ok else "   (not delivered — not paying)"],
				14, Color(0.55, 0.85, 0.62) if ok else Color(0.95, 0.6, 0.45)))

var _toast_lbl: Label

func _toast(text: String) -> void:
	if _toast_lbl == null or not is_instance_valid(_toast_lbl):
		_toast_lbl = _label("", 14, Color(1.0, 0.85, 0.5))
		contracts_box.add_child(_toast_lbl)
		contracts_box.move_child(_toast_lbl, 0)
	_toast_lbl.text = text

func _refresh_contracts() -> void:
	for c in contracts_box.get_children():
		c.queue_free()
	_build_market_section()
	contracts_box.add_child(_section("CAMPAIGN"))
	var found_active := false
	for c in Contracts.all():
		var done: bool = c["id"] in Game.contracts_done
		if done:
			var healthy: bool = Game.sla_status.get(c["id"], true)
			var mrr: int = int(c["reward"]) / 10
			if healthy:
				contracts_box.add_child(_chip_row("DONE", Color(0.4, 0.85, 0.5),
					"%s — %s   service fee +$%d / cycle" % [c["title"], c["customer"], mrr],
					14, Color(0.55, 0.8, 0.6)))
			else:
				contracts_box.add_child(_chip_row("BREACH", Color(0.95, 0.45, 0.35),
					"%s — %s   SLA BREACH: service down, not paying!" % [c["title"], c["customer"]],
					14, Color(0.95, 0.55, 0.4)))
			continue
		if found_active:
			contracts_box.add_child(_label("🔒  (more contracts after the current one)", 13, Color(0.45, 0.5, 0.6)))
			break
		found_active = true
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _sb(Color(0.09, 0.12, 0.16), ACCENT * Color(1, 1, 1, 0.5), 8, 14))
		contracts_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		cv.add_child(_label("%s — %s      reward $%d" % [c["title"], c["customer"], c["reward"]], 17, Color.WHITE))
		var brief := _label(c["brief"], 14, Color(0.75, 0.8, 0.88))
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.custom_minimum_size = Vector2(560, 0)
		cv.add_child(brief)
		for r in c["reqs"]:
			var ok: bool = r["t"].call()
			cv.add_child(_label(("●  " if ok else "○  ") + r["d"], 14,
				Color(0.5, 0.95, 0.6) if ok else Color(0.65, 0.6, 0.55)))
		var btn := Button.new()
		btn.text = "Check requirements & collect"
		_accent(btn)
		btn.pressed.connect(func() -> void:
			Game.try_complete_contract(c)
			_refresh_contracts())
		cv.add_child(btn)
	if not found_active:
		contracts_box.add_child(_label("All contracts complete! More arrive with future updates —\nsee the GitHub roadmap.", 14, Color(0.7, 0.85, 0.75)))

# ---------- refresh / CLI ----------

func _refresh_capture() -> void:
	if cap_box == null or not cap_box.visible or cur_dev == null:
		return
	cap_out.clear()
	if cur_dev.capture.is_empty():
		cap_out.append_text("(no frames captured — generate some traffic, e.g. ping something)")
	else:
		cap_out.append_text("\n".join(PackedStringArray(cur_dev.capture.slice(-14))))

func _refresh_open() -> void:
	_refresh_capture()
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
		cli_session = CLI.new_session(cur_dev)
		cli_stack.clear()
		cli_history.clear()
		cli_hist_idx = 0
		cli_prompt.text = cli_session.prompt() + " "
		cli_out.clear()
		cli_out.append_text(cli_session.banner())
		cli_in.call_deferred("grab_focus")
	else:
		cli_toggle.text = "Open console  ▤"
		cli_out.clear()
		cli_session = null

func _cli_key(e: InputEvent) -> void:
	# the LineEdit consumes Escape (and the watchdog would re-grab editing),
	# so handle back-navigation here, before the LineEdit sees the key
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		cli_in.accept_event()
		_toggle_cli()
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_UP:
		cli_in.accept_event()
		if cli_history.is_empty():
			return
		cli_hist_idx = maxi(0, cli_hist_idx - 1)
		cli_in.text = cli_history[cli_hist_idx]
		cli_in.caret_column = cli_in.text.length()
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_DOWN:
		cli_in.accept_event()
		cli_hist_idx = mini(cli_history.size(), cli_hist_idx + 1)
		cli_in.text = "" if cli_hist_idx == cli_history.size() else cli_history[cli_hist_idx]
		cli_in.caret_column = cli_in.text.length()
		return
	if e is InputEventKey and e.pressed and e.unicode == 63:  # '?'
		cli_in.accept_event()
		var cands0 := cli_session.complete(cli_in.text)
		if cands0.is_empty():
			cli_out.append_text("%s %s?\n  <no completions here>\n" % [cli_session.prompt(), cli_in.text])
		else:
			cli_out.append_text("%s %s?\n  %s\n" % [cli_session.prompt(), cli_in.text,
				"  ".join(PackedStringArray(cands0))])
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_TAB:
		cli_in.accept_event()
		var text := cli_in.text
		var cands := cli_session.complete(text)
		if cands.is_empty():
			return
		var start := text.rfind(" ") + 1
		var keep := "/" if start == 0 and text.begins_with("/") else ""
		var cur := text.substr(start + keep.length())
		var common: String = cands[0]
		for c: String in cands:
			while not c.begins_with(common):
				common = common.left(common.length() - 1)
		if cands.size() == 1:
			common += " "
		if common.length() > cur.length():
			cli_in.text = text.left(start) + keep + common
			cli_in.caret_column = cli_in.text.length()
		elif cands.size() > 1:
			cli_out.append_text("  ".join(PackedStringArray(cands)) + "\n")

func _cli_submit(cmd: String) -> void:
	cli_in.clear()
	cli_in.call_deferred("grab_focus")
	if cmd.strip_edges() != "":
		cli_history.append(cmd)
		cli_hist_idx = cli_history.size()
	if cmd.strip_edges() == "clear":
		cli_out.clear()
		return
	cli_out.append_text("%s %s\n" % [cli_session.prompt(), cmd])
	Sim.last_trace = []
	cli_out.append_text(cli_session.exec(cmd))
	if cli_session.pending_ssh:
		var target: Net.NDevice = cli_session.pending_ssh
		cli_session.pending_ssh = null
		cli_stack.append(cli_session)
		cli_session = CLI.new_session(target)
		cli_out.append_text(cli_session.banner())
	elif cli_session.wants_exit:
		cli_session.wants_exit = false
		if cli_stack.is_empty():
			cli_out.append_text("logout (session stays open)\n")
		else:
			cli_session = cli_stack.pop_back()
			cli_out.append_text("Connection closed. Back on %s.\n" % cli_session.dev.name)
	cli_prompt.text = cli_session.prompt() + " "  # mode/hostname may have changed
	_refresh_capture()
	if not Sim.last_trace.is_empty():
		get_parent().play_trace(Sim.last_trace)

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
					_show_overlay(rack_overlay)
		elif pedia_overlay.visible:
			pedia_overlay.visible = false
		elif menu_overlay.visible:
			menu_overlay.visible = false
		elif map_overlay.visible:
			map_overlay.visible = false
		elif welcome_overlay.visible:
			welcome_overlay.visible = false
		elif contracts_overlay.visible:
			close_contracts()
		elif rack_overlay.visible:
			close_rack()
		else:
			toggle_menu()
		get_viewport().set_input_as_handled()
