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
var svc_lbl: Label
var cap_box: VBoxContainer
var cap_out: RichTextLabel
var cap_toggle: Button
var save_cfg_btn: Button
var template_btn: Button
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
var if_vrrp_lbl: Label
var if_nat_row: HBoxContainer
var if_mode: OptionButton
var if_vlan: OptionButton
var if_vlan_row: HBoxContainer
var if_trunk_note: Label
var if_trunk_edit: LineEdit
var if_portsec: CheckButton
var if_qos: CheckButton
var if_ip_section: VBoxContainer
var if_ip_box: VBoxContainer
var if_ip_in: LineEdit
var if_ip_hint: Label
var if_cable_lbl: Label
var if_cable_btn: Button
var if_peer_btn: Button

var search_overlay: Control
var search_input: LineEdit
var search_box: VBoxContainer
var ops_overlay: Control
var ops_title: Label
var ops_box: VBoxContainer
var help_overlay: Control
var pedia_overlay: Control
var pedia_body: RichTextLabel
var menu_overlay: Control
var map_overlay: Control
var welcome_overlay: Control
var tutorial_panel: PanelContainer
var tutorial_box: VBoxContainer
var contracts_overlay: Control
var contracts_box: VBoxContainer
var contracts_tabs := {}
var _toast_lbl: Label
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
var objective_lbl: Label
var expand_btn: Button
var site_btn: Button
var speed_btns := {}
var hud_msg: Label
var hud_msg_tween: Tween
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
	_build_help()
	_build_ops()
	_build_search()
	_build_pedia()
	_build_tutorial()
	Game.topology_changed.connect(_refresh_tutorial)
	Game.money_changed.connect(_refresh_tutorial)
	Game.topology_changed.connect(_refresh_open)
	Game.topology_changed.connect(_refresh_money)
	Game.money_changed.connect(_refresh_money)
	Game.speed_changed.connect(_refresh_speed)
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
		if not Game.sla_status[cid] and not Contracts.retired(cid):
			n += 1
	if n > 0:
		contracts_btn.text = "Company (%d!)" % n
		contracts_btn.modulate = Color(1.15, 0.95, 0.7)
	else:
		contracts_btn.text = "Company"
		contracts_btn.modulate = Color.WHITE

func hud_toast(text: String, good := false) -> void:
	## a short message on the HUD, for actions that would otherwise fail silently
	if hud_msg == null:
		hud_msg = _label("", 15, Color(1.0, 0.8, 0.5))
		hud_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
		hud_msg.position = Vector2(-300, 78)
		hud_msg.custom_minimum_size = Vector2(600, 0)
		hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hud_msg.theme = theme_res
		add_child(hud_msg)
	hud_msg.text = text
	hud_msg.add_theme_color_override("font_color",
		Color(0.6, 0.95, 0.7) if good else Color(1.0, 0.8, 0.5))
	hud_msg.modulate.a = 1.0
	if hud_msg_tween and hud_msg_tween.is_running():
		hud_msg_tween.kill()
	hud_msg_tween = create_tween()
	hud_msg_tween.tween_interval(2.6)
	hud_msg_tween.tween_property(hud_msg, "modulate:a", 0.0, 0.8)

func _refresh_speed() -> void:
	for k in speed_btns:
		speed_btns[k].button_pressed = (k == Game.speed)

func _refresh_money() -> void:
	_refresh_speed()
	_refresh_attention()
	if objective_lbl:
		var next_c := ""
		for c in Contracts.all():
			if c["id"] not in Game.contracts_done:
				next_c = c["title"]
				break
		if next_c != "":
			objective_lbl.text = "▸ " + next_c
		else:
			var nr := Game.next_rank()
			objective_lbl.text = "★ %s" % Game.rank() if nr.is_empty() \
				else "★ %s  ·  $%d to %s" % [Game.rank(), int(nr[1]), nr[0]]
	var power := ""
	if Game.stage >= 1:
		power = "  ⚡%d/❄%d" % [Game.power_draw(), Game.cooling_capacity()]
		if Game.overheating():
			power += " 🔥"
	var debt_s := ("  (debt $%d)" % Game.debt) if Game.debt > 0 else ""
	money_lbl.text = "$%d%s  ♦%d%s" % [Game.money, debt_s, Game.reputation, power]
	money_lbl.tooltip_text = "Cash%s · reputation %d · power and cooling" % [
		"" if Game.debt == 0 else " (debt $%d)" % Game.debt, Game.reputation]
	money_lbl.tooltip_text = "Money · Reputation (drives customer budgets) · Power/Cooling"
	money_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.35) if Game.overheating() else Color(0.55, 0.95, 0.6))
	if site_btn:
		site_btn.text = Game.site_name(Game.current_site)
		site_btn.visible = Game.site_count() > 1
	if Game.current_site != 0:
		expand_btn.visible = false  # acquired floors come as they are
	elif Game.stage < Game.STAGES.size() - 1:
		var nxt: Dictionary = Game.STAGES[Game.stage + 1]
		expand_btn.text = "Expand ($%d)" % int(nxt["price"])
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
		if Game.speed == 0:
			cycle_lbl.text = "⏸ paused"
		elif t:
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
		or menu_overlay.visible or pedia_overlay.visible or help_overlay.visible \
		or ops_overlay.visible or search_overlay.visible

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

static func compress_ports(names: Array) -> String:
	## Et1,Et2,Et3,Et7 -> "Et1-3,Et7" (what real switch output looks like)
	if names.is_empty():
		return ""
	var short: Array = []
	for n in names:
		short.append(String(n).replace("Ethernet", "Et").replace("Management", "Ma"))
	var out: Array = []
	var run_start := -1
	var run_prev := -1
	var run_pfx := ""
	for n in short + [""]:
		var digits := String(n).lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
		var pfx := String(n).trim_suffix(digits)
		var num := int(digits) if digits.is_valid_int() else -999
		if pfx == run_pfx and num == run_prev + 1:
			run_prev = num
			continue
		if run_start >= 0:
			out.append("%s%d" % [run_pfx, run_start] if run_start == run_prev
				else "%s%d-%d" % [run_pfx, run_start, run_prev])
		run_pfx = pfx
		run_start = num
		run_prev = num
	return ",".join(PackedStringArray(out))

func _section(text: String) -> Label:
	return _label(text, 11, Color(0.5, 0.58, 0.72))

func _show_overlay(o: Control) -> void:
	o.modulate.a = 0.0
	o.visible = true
	_fit_cards.call_deferred()
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

var _card_scrolls: Array = []  # ScrollContainers to fit to the viewport

func _card(parent: Control, min_w: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(BG, Color(0.32, 0.38, 0.5), 12, 20))
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(min_w, 0)
	panel.add_child(scroll)
	_card_scrolls.append(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	return v

func _scroll_to_bottom() -> void:
	_fit_cards()
	for scroll: ScrollContainer in _card_scrolls:
		if scroll.is_visible_in_tree():
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func _fit_cards() -> void:
	## keep every card inside the window; content beyond that scrolls
	var vp := get_viewport().get_visible_rect().size
	for scroll: ScrollContainer in _card_scrolls:
		if scroll.get_child_count() == 0:
			continue
		var content: Control = scroll.get_child(0)
		var need := content.get_combined_minimum_size()
		scroll.custom_minimum_size = Vector2(
			minf(maxf(need.x, scroll.custom_minimum_size.x), vp.x - 120.0),
			minf(need.y, vp.y - 160.0))

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
	for m in [["Select", 0], ["+ Rack", 1]]:
		var b := Button.new()
		b.text = m[0]
		b.toggle_mode = true
		b.pressed.connect(func() -> void: get_parent().mode = m[1])
		h.add_child(b)
		mode_btns[m[1]] = b
	var learnb := Button.new()
	learnb.text = "Learn"
	learnb.tooltip_text = "Networkopedia: every concept the game teaches"
	learnb.pressed.connect(open_pedia)
	h.add_child(learnb)
	site_btn = Button.new()
	site_btn.tooltip_text = "Switch between the floors you operate"
	site_btn.custom_minimum_size = Vector2(120, 0)
	site_btn.pressed.connect(func() -> void:
		var names: Array = []
		for i in Game.site_count():
			names.append("%s%s  (%dx%d, %d racks)" % ["▸ " if i == Game.current_site else "   ",
				Game.site_name(i), Game.grid_size(i).x, Game.grid_size(i).y, Game.racks_on(i).size()])
		_menu(site_btn, names, func(id: int) -> void:
			Game.switch_site(id)
			_refresh_money()))
	h.add_child(site_btn)
	var opsb := Button.new()
	opsb.text = "Ops"
	opsb.tooltip_text = "Operations dashboard (O)"
	opsb.pressed.connect(toggle_ops)
	h.add_child(opsb)
	var mapb := Button.new()
	mapb.text = "Map"
	mapb.tooltip_text = "Logical topology (M)"
	mapb.pressed.connect(toggle_map)
	h.add_child(mapb)
	contracts_btn = Button.new()
	contracts_btn.text = "Company"
	contracts_btn.tooltip_text = "Jobs, business, market and log"
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
	objective_lbl = _label("", 12, Color(0.65, 0.8, 0.9))
	objective_lbl.custom_minimum_size = Vector2(210, 0)
	objective_lbl.clip_text = true
	objective_lbl.tooltip_text = "Current campaign objective: details in Contracts"
	h.add_child(objective_lbl)
	for spec in [["⏸", 0, "Pause (Space)"], ["▶", 1, "Normal speed (1)"],
			["▶▶", 2, "Fast (2)"], ["▶▶▶", 3, "Faster (3)"]]:
		var spd_btn := Button.new()
		spd_btn.text = spec[0]
		spd_btn.tooltip_text = spec[2]
		spd_btn.toggle_mode = true
		spd_btn.pressed.connect(func() -> void: Game.set_speed(spec[1]))
		h.add_child(spd_btn)
		speed_btns[spec[1]] = spd_btn
	cycle_lbl = _label("", 13, Color(0.5, 0.58, 0.7))
	cycle_lbl.add_theme_font_override("font", mono)
	cycle_lbl.tooltip_text = "Time to the next revenue cycle: fees, bills, SLA checks"
	h.add_child(cycle_lbl)
	money_lbl = _label("", 15, Color(0.55, 0.95, 0.6))
	money_lbl.add_theme_font_override("font", mono)
	h.add_child(money_lbl)
	var save_btn := Button.new()
	save_btn.text = "💾"
	save_btn.tooltip_text = "Save the game"
	save_btn.pressed.connect(func() -> void: Game.save_game())
	h.add_child(save_btn)
	update_mode(0)
	var hint := _label("Q select   ·   R place rack   ·   right-drag pan   ·   scroll zoom   ·   Esc back", 12, Color(0.45, 0.5, 0.62))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -30)
	hint.text = "Space pause  ·  Q select  ·  R place rack  ·  F find  ·  O ops  ·  M map  ·  F1 keys  ·  Esc menu  ·  right-drag pan  ·  scroll zoom"
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
		var mod2: Dictionary = Game.MODELS[keys[id]]
		if int(mod2.get("tier", 0)) > Game.stage:
			hud_toast("%s needs the %s stage: expand first." % [mod2["label"],
				Game.STAGES[int(mod2["tier"])]["name"]])
			return
		if not Game.try_spend(mod2["price"]):
			hud_toast("Not enough money for a %s ($%d, you have $%d)." % [mod2["label"],
				int(mod2["price"]), Game.money])
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

	v.add_child(_section("FRONT PANEL: CLICK A PORT TO CONFIGURE"))
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
	svc_lbl = _label("", 13, Color(0.6, 0.75, 0.65))
	v.add_child(svc_lbl)

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
		_refresh_capture()
		if cap_box.visible:
			_scroll_to_bottom.call_deferred())
	btn_row.add_child(cap_toggle)
	template_btn = Button.new()
	template_btn.text = "Templates"
	template_btn.tooltip_text = "Save this device as a standard, or apply one"
	template_btn.pressed.connect(func() -> void:
		var opts: Array = ["Save this device as a template…"]
		var applicable: Array = []
		for t: Dictionary in Game.templates:
			if t["type"] == cur_dev.type:
				opts.append("Apply '%s'" % t["name"])
				applicable.append(t)
		_menu(template_btn, opts, func(id: int) -> void:
			if id == 0:
				Game.save_template(cur_dev, "%s standard" % cur_dev.type)
				hud_toast("Saved '%s standard' as a template." % cur_dev.type, true)
			else:
				var err: String = Game.apply_template(cur_dev, applicable[id - 1])
				hud_toast(err if err != "" else "Template applied to %s." % cur_dev.name, err == "")
			_refresh_ports()))
	btn_row.add_child(template_btn)
	save_cfg_btn = Button.new()
	save_cfg_btn.text = "Save config"
	save_cfg_btn.tooltip_text = "write memory: survive a reboot"
	save_cfg_btn.pressed.connect(func() -> void:
		cur_dev.startup = Game.device_config(cur_dev)
		_refresh_ports())
	btn_row.add_child(save_cfg_btn)
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
	dev_title.text = "%s  /  %s: %s" % [Game.rack_of(cur_dev).name, cur_dev.name, Game.MODELS[cur_dev.model]["label"]]
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
	for i: Net.Iface in cur_dev.ifaces:
		if i.name.begins_with("Vlan") or i.parent != "":
			var b := Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_override("font", mono)
			b.text = "  %s (%s)   %s" % [i.name, "SVI" if i.parent == "" else "802.1Q sub",
				", ".join(PackedStringArray(i.ips)) if not i.ips.is_empty() else "no address"]
			b.pressed.connect(open_iface.bind(i))
			conn_list.add_child(b)
	var svc_bits: Array = []
	if cur_dev.services.has("dhcp"):
		var svc: Dictionary = cur_dev.services["dhcp"]
		svc_bits.append("dhcpd %s–%s (%d leases)" % [svc["start"], svc["end"], svc["leases"].size()])
	if cur_dev.services.has("dns"):
		svc_bits.append("dns (%d records)" % cur_dev.services["dns"]["records"].size())
	if cur_dev.resolver != "":
		svc_bits.append("resolver %s" % cur_dev.resolver)
	if not cur_dev.bgp.is_empty():
		svc_bits.append("bgp AS%d" % int(cur_dev.bgp["asn"]))
	if not cur_dev.ospf.is_empty():
		svc_bits.append("ospf")
	svc_lbl.text = ("  ⚙ " + "   ".join(PackedStringArray(svc_bits))) if not svc_bits.is_empty() else ""
	var dirty := Game.config_dirty(cur_dev)
	save_cfg_btn.visible = cur_dev.type not in ["server", "uplink", "cooling"]
	save_cfg_btn.text = "⚠ Save config" if dirty else "Save config"
	save_cfg_btn.modulate = Color(1.3, 1.0, 0.6) if dirty else Color.WHITE
	if dirty:
		svc_lbl.text += "      ⚠ unsaved configuration: a reboot would lose it"
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
		var l := _label("  %-6d %-14s %s" % [vid, cur_dev.vlans[vid], compress_ports(ports)],
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
	if_vrrp_lbl = _label("", 13, Color(0.7, 0.85, 0.75))
	if_vrrp_lbl.add_theme_font_override("font", mono)
	v.add_child(if_vrrp_lbl)

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
	if_qos = CheckButton.new()
	if_qos.text = "QoS"
	if_qos.tooltip_text = "When this link is congested, serve strict service levels first"
	if_qos.toggled.connect(func(on: bool) -> void:
		cur_if.qos = on
		Game.topology_changed.emit())
	row2.add_child(if_qos)
	if_portsec = CheckButton.new()
	if_portsec.tooltip_text = "Lock this port to the first device it sees"
	if_portsec.toggled.connect(func(on: bool) -> void:
		cur_if.port_security = on
		if not on:
			cur_if.secure_mac = ""
		Game.topology_changed.emit())
	row2.add_child(if_portsec)
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
	var dhcp_btn := Button.new()
	dhcp_btn.text = "DHCP"
	dhcp_btn.tooltip_text = "Get an address automatically (dhclient)"
	dhcp_btn.pressed.connect(func() -> void:
		var lease := Sim.dhcp_request(cur_if.dev, cur_if)
		if lease.is_empty():
			if_ip_hint.text = " no DHCP server answered"
		else:
			_refresh_iface())
	ip_row.add_child(dhcp_btn)
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
	var spd := Game.iface_speed(cur_if)
	if_mac.text = "MAC %s      %s      RX %d / TX %d frames" % [cur_if.mac,
		("%d Gbit" % (spd / 1000)) if spd >= 1000 else ("%d Mbit" % spd), cur_if.rx_frames, cur_if.tx_frames]
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
	if_qos.set_pressed_no_signal(cur_if.qos)
	if_portsec.visible = is_switch and cur_if.mode == "access"
	if_portsec.set_pressed_no_signal(cur_if.port_security)
	if_portsec.text = "Port security" + ("  (locked to %s)" % cur_if.secure_mac if cur_if.secure_mac else "")
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
	if cur_if.vrrp.is_empty():
		if_vrrp_lbl.text = ""
	else:
		var master := Sim.vrrp_master(cur_if.vrrp["vip"], int(cur_if.vrrp["group"]))
		if_vrrp_lbl.text = "VRRP group %d  vip %s  prio %d  (%s)" % [int(cur_if.vrrp["group"]),
			cur_if.vrrp["vip"], int(cur_if.vrrp.get("priority", 100)),
			"Master" if master == cur_if.dev else "Backup"]
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
	# group by device: one submenu per device, so a rack of 24-port switches
	# does not become a hundred-row flat list
	var by_dev := {}
	for t: Net.Iface in targets:
		if not by_dev.has(t.dev):
			by_dev[t.dev] = []
		by_dev[t.dev].append(t)
	var root := PopupMenu.new()
	root.add_theme_font_override("font", mono)
	add_child(root)
	root.popup_hide.connect(root.queue_free)
	for dev: Net.NDevice in by_dev:
		var ports: Array = by_dev[dev]
		var dev_rack := Game.rack_of(dev)
		var my_rack := Game.rack_of(cur_if.dev)
		var remote: bool = dev_rack != null and my_rack != null and dev_rack.site != my_rack.site
		var linkable: bool = ports.is_empty() or Game.can_link(cur_if, ports[0])
		var sub := PopupMenu.new()
		sub.add_theme_font_override("font", mono)
		sub.name = "sub_%s" % dev.name
		for t: Net.Iface in ports:
			sub.add_item(t.name)
		sub.id_pressed.connect(func(id: int) -> void:
			Game.connect_ifaces(cur_if, ports[id])
			root.hide()
			_refresh_iface())
		root.add_child(sub)
		var names: Array = []
		for t: Net.Iface in ports:
			names.append(t.name)
		var suffix := ""
		if remote:
			suffix = "   [%s%s]" % [Game.site_name(dev_rack.site),
				"" if linkable else ": no circuit"]
		root.add_submenu_item("%-4s %-8s %2d free: %s%s" % [Game.rack_of(dev).name, dev.name,
			ports.size(), compress_ports(names), suffix], sub.name)
		if not linkable:
			root.set_item_disabled(root.item_count - 1, true)
	root.popup(Rect2i(Vector2i(if_cable_btn.get_screen_position() + Vector2(0, if_cable_btn.size.y + 4)), Vector2i.ZERO))

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

# ---------- search ----------

func _build_search() -> void:
	search_overlay = _overlay()
	var v := _card(search_overlay, 620)
	var t := _header(v, func() -> void: search_overlay.visible = false)
	t.text = "Find"
	search_input = _mono_edit(560)
	search_input.placeholder_text = "device name, address, VLAN id, customer or site"
	search_input.text_changed.connect(func(_t: String) -> void: _refresh_search())
	v.add_child(search_input)
	search_box = VBoxContainer.new()
	search_box.add_theme_constant_override("separation", 3)
	v.add_child(search_box)

func toggle_search() -> void:
	if search_overlay.visible:
		search_overlay.visible = false
		return
	if is_open():
		return
	_show_overlay(search_overlay)
	search_input.text = ""
	_refresh_search()
	search_input.call_deferred("grab_focus")

func _goto_device(d: Net.NDevice) -> void:
	search_overlay.visible = false
	var rk := Game.rack_of(d)
	if rk and rk.site != Game.current_site:
		Game.switch_site(rk.site)
		get_parent().rebuild_racks()
	cur_rack = rk
	open_dev(d)

func _refresh_search() -> void:
	for c in search_box.get_children():
		c.queue_free()
	var q := search_input.text.strip_edges().to_lower()
	if q == "":
		search_box.add_child(_label("  Type to search across every site.", 13, MUTED))
		return
	var hits := 0
	for d in Game.all_devices():
		var why := ""
		if q in d.name.to_lower():
			why = "device"
		elif q in String(Game.MODELS[d.model]["label"]).to_lower():
			why = "model"
		else:
			for i: Net.Iface in d.ifaces:
				for cidr: String in i.ips:
					if q in cidr.to_lower():
						why = "address %s on %s" % [cidr, i.name]
				if q in i.name.to_lower() and why == "":
					why = "interface %s" % i.name
			for vid in d.vlans:
				if q == str(vid):
					why = "VLAN %s (%s)" % [vid, d.vlans[vid]]
		if why == "":
			continue
		hits += 1
		if hits > 12:
			continue
		var rk := Game.rack_of(d)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 12)
		b.text = "  %-10s %-16s %-10s %s" % [d.name, Game.MODELS[d.model]["label"],
			(Game.site_name(rk.site) if rk else "-"), why]
		b.pressed.connect(func() -> void: _goto_device(d))
		search_box.add_child(b)
	for deal: Dictionary in Game.deals:
		if q in String(deal["customer"]).to_lower():
			hits += 1
			search_box.add_child(_label("  customer: %s (%s, $%d/cycle)" % [deal["customer"],
				Market.label_for(deal["kind"]), int(deal["fee"])], 13, Color(0.7, 0.85, 0.75)))
	if hits == 0:
		search_box.add_child(_label("  Nothing matches that.", 13, Color(0.8, 0.6, 0.5)))
	elif hits > 12:
		search_box.add_child(_label("  ...and %d more matches." % (hits - 12), 12, MUTED))

# ---------- ops dashboard ----------

func _device_alerts(d: Net.NDevice) -> Array:
	var out: Array = []
	if d.status != "active":
		out.append("OFFLINE")
	var down := 0
	for i: Net.Iface in d.ifaces:
		if not i.enabled and Game.link_at(i):
			down += 1
		if i.violations > 0 and not i.enabled:
			out.append("port-security shutdown")
	if down > 0:
		out.append("%d cabled port(s) down" % down)
	if Game.config_dirty(d):
		out.append("unsaved config")
	for l in Game.links:
		if (l.a.dev == d or l.b.dev == d) and int(Game.last_link_load.get(l, 0)) > Game.link_capacity(l):
			out.append("congested link")
			break
	return out

func _build_ops() -> void:
	ops_overlay = _overlay()
	var v := _card(ops_overlay, 820)
	ops_title = _header(v, func() -> void: ops_overlay.visible = false)
	ops_title.text = "Operations"
	ops_box = VBoxContainer.new()
	ops_box.add_theme_constant_override("separation", 3)
	v.add_child(ops_box)

func _refresh_ops() -> void:
	for c in ops_box.get_children():
		c.queue_free()
	var devs := Game.all_devices()
	devs.sort_custom(func(x, y): return _device_alerts(x).size() > _device_alerts(y).size())
	var alerting := 0
	var links_down := 0
	for l in Game.links:
		if not l.a.enabled or not l.b.enabled:
			links_down += 1
	for d: Net.NDevice in devs:
		if not _device_alerts(d).is_empty():
			alerting += 1
	ops_title.text = "Operations   ·   %d devices   ·   %d cables (%d down)   ·   %d needing attention" % [
		devs.size(), Game.links.size(), links_down, alerting]
	ops_box.add_child(_section("MONITORS"))
	if Game.monitors.is_empty():
		ops_box.add_child(_label("  No checks defined: add one so you hear about failures.",
			13, Color(0.6, 0.62, 0.7)))
	for m: Dictionary in Game.monitors.duplicate():
		var mrow := HBoxContainer.new()
		ops_box.add_child(mrow)
		var failing: bool = m["failing"]
		var ml := _label("  %s %s" % ["○" if failing else "●", Game.monitor_label(m)], 13,
			Color(0.95, 0.55, 0.45) if failing else Color(0.55, 0.9, 0.6))
		ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mrow.add_child(ml)
		var del := Button.new()
		del.text = "Remove"
		del.pressed.connect(func() -> void:
			Game.remove_monitor(m)
			_refresh_ops())
		mrow.add_child(del)
	var add_mon := Button.new()
	add_mon.text = "Add a check…"
	add_mon.pressed.connect(func() -> void:
		var opts: Array = []
		var specs: Array = []
		for d in Game.all_devices():
			for i: Net.Iface in d.ifaces:
				for cidr: String in i.ips:
					var addr: String = cidr.split("/")[0]
					for src in Game.all_devices():
						if src == d or src.type != "server":
							continue
						opts.append("ping %s from %s" % [addr, src.name])
						specs.append(["ping", src.name, addr])
						break
		if opts.is_empty():
			_toast("configure some addresses first")
			return
		_menu(add_mon, opts.slice(0, 20), func(id: int) -> void:
			var sp: Array = specs[id]
			Game.add_monitor(sp[0], sp[1], sp[2])
			_refresh_ops()))
	ops_box.add_child(add_mon)
	ops_box.add_child(_section("DEVICES"))
	if devs.is_empty():
		ops_box.add_child(_label("  Nothing installed yet.", 14, MUTED))
		return
	var multi := Game.site_count() > 1
	var head := _label("  %-9s %-14s %-20s %-9s %-7s %-18s %s" % ["DEVICE",
		"SITE" if multi else "", "MODEL", "STATUS", "LINKS", "ADDRESSES", "ALERTS"],
		12, Color(0.5, 0.58, 0.72))
	head.add_theme_font_override("font", mono)
	ops_box.add_child(head)
	for d: Net.NDevice in devs:
		var up := 0
		var total := 0
		for i: Net.Iface in d.ifaces:
			if i.name == "lo" or i.name.begins_with("Vlan") or i.parent != "":
				continue
			total += 1
			if i.enabled and Game.link_at(i):
				up += 1
		var addrs: Array = []
		for i: Net.Iface in d.ifaces:
			for cidr: String in i.ips:
				if addrs.size() < 2:
					addrs.append(cidr)
		var alerts := _device_alerts(d)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 12)
		var rk := Game.rack_of(d)
		b.text = "  %-9s %-14s %-20s %-9s %-7s %-18s %s" % [d.name,
			(Game.site_name(rk.site) if (multi and rk) else ""),
			Game.MODELS[d.model]["label"], d.status, "%d/%d" % [up, total],
			", ".join(PackedStringArray(addrs)) if not addrs.is_empty() else "-",
			", ".join(PackedStringArray(alerts))]
		b.add_theme_color_override("font_color",
			Color(0.95, 0.6, 0.45) if not alerts.is_empty() else Color(0.7, 0.8, 0.75))
		b.pressed.connect(func() -> void:
			ops_overlay.visible = false
			var rk2 := Game.rack_of(d)
			if rk2 and rk2.site != Game.current_site:
				Game.switch_site(rk2.site)  # jump to the floor it stands on
				get_parent().rebuild_racks()
			cur_rack = rk2
			open_dev(d))
		ops_box.add_child(b)

func toggle_ops() -> void:
	if ops_overlay.visible:
		ops_overlay.visible = false
	elif not is_open():
		_refresh_ops()
		_show_overlay(ops_overlay)

# ---------- keyboard help ----------

func _build_help() -> void:
	help_overlay = _overlay()
	var v := _card(help_overlay, 620)
	var t := _header(v, func() -> void: help_overlay.visible = false)
	t.text = "Keys and controls"
	var rows := [
		["FLOOR", ""],
		["Q / R", "select mode / place-rack mode"],
		["Space", "pause and resume"],
		["1 / 2 / 3", "normal, fast and faster"],
		["O", "operations dashboard (device health)"],
		["F", "find a device, address, VLAN or customer"],
		["M", "logical topology map"],
		["F1", "this help"],
		["Esc", "system menu (save, new game, incident drill, quit)"],
		["right / middle drag", "pan the floor"],
		["scroll wheel", "zoom toward the cursor"],
		["VIEWS", ""],
		["click rack", "open the rack cabinet"],
		["click device", "open its front panel"],
		["click port", "interface editor (addresses, VLAN, cabling)"],
		["Esc", "back one level"],
		["CONSOLE", ""],
		["Tab", "complete the command or list candidates"],
		["?", "show what is possible at this point"],
		["Up / Down", "command history"],
		["clear", "wipe the screen"],
		["ssh <ip>", "jump into another device's CLI (exit returns)"],
		["Esc", "close the console"],
	]
	for row in rows:
		if row[1] == "":
			v.add_child(_section(row[0]))
			continue
		var h := HBoxContainer.new()
		var k := _label(row[0], 14, Color(0.6, 0.9, 1.0))
		k.add_theme_font_override("font", mono)
		k.custom_minimum_size = Vector2(180, 0)
		h.add_child(k)
		h.add_child(_label(row[1], 14, Color(0.78, 0.82, 0.9)))
		v.add_child(h)

func toggle_help() -> void:
	if help_overlay.visible:
		help_overlay.visible = false
	else:
		_show_overlay(help_overlay)

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
		_menu(newg, ["Yes, start over: my datacenter will be GONE"], func(_id: int) -> void:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
			get_tree().reload_current_scene()))
	v.add_child(newg)
	var prefs_btn := Button.new()
	prefs_btn.text = "Settings…"
	prefs_btn.pressed.connect(func() -> void:
		_menu(prefs_btn, [
			"Fullscreen: %s" % ("on" if Prefs.fullscreen else "off"),
			"Interface scale: %d%%" % int(Prefs.ui_scale * 100),
			"Colourblind-friendly status colours: %s" % ("on" if Prefs.colourblind else "off"),
		], func(id: int) -> void:
			match id:
				0:
					Prefs.fullscreen = not Prefs.fullscreen
				1:
					var steps := [0.9, 1.0, 1.15, 1.3]
					var idx := steps.find(snappedf(Prefs.ui_scale, 0.05))
					Prefs.ui_scale = steps[(idx + 1) % steps.size()] if idx >= 0 else 1.0
					get_tree().root.content_scale_factor = Prefs.ui_scale
				2:
					Prefs.colourblind = not Prefs.colourblind
			Prefs.apply()
			hud_toast("Setting applied.", true)))
	v.add_child(prefs_btn)
	var diff_btn := Button.new()
	diff_btn.text = "Difficulty…"
	diff_btn.pressed.connect(func() -> void:
		var opts: Array = []
		for i in Game.DIFFICULTIES.size():
			var d: Dictionary = Game.DIFFICULTIES[i]
			opts.append("%s%s: %s" % ["▸ " if i == Game.difficulty else "   ", d["name"], d["blurb"]])
		_menu(diff_btn, opts, func(id: int) -> void:
			Game.apply_difficulty(id)
			hud_toast("Difficulty set to %s. Starting cash reset." % Game.DIFFICULTIES[id]["name"], true)
			_refresh_money()))
	v.add_child(diff_btn)
	var drill_btn := Button.new()
	drill_btn.text = "Incident drill  (fix a broken network, +$%d)" % Drill.REWARD
	drill_btn.pressed.connect(func() -> void:
		if Game.drill_active:
			return
		menu_overlay.visible = false
		Drill.start(2 + Game.stage)  # bigger room, harder drills
		get_parent().rebuild_racks()
		_show_drill_banner())
	v.add_child(drill_btn)
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

# ---------- incident drill ----------

var drill_panel: PanelContainer
var drill_box: VBoxContainer

func _show_drill_banner() -> void:
	if drill_panel == null:
		drill_panel = PanelContainer.new()
		drill_panel.theme = theme_res
		drill_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
		drill_panel.position = Vector2(-240, 70)
		drill_panel.custom_minimum_size = Vector2(480, 0)
		drill_panel.add_theme_stylebox_override("panel",
			_sb(Color(0.14, 0.08, 0.08, 0.96), Color(0.9, 0.5, 0.4, 0.8), 8, 12))
		add_child(drill_panel)
		drill_box = VBoxContainer.new()
		drill_box.add_theme_constant_override("separation", 5)
		drill_panel.add_child(drill_box)
	for c in drill_box.get_children():
		c.queue_free()
	drill_box.add_child(_label("🚨 INCIDENT DRILL: this is NOT your datacenter", 15, Color(1.0, 0.7, 0.6)))
	drill_box.add_child(_label(Drill.scenario, 13, Color(0.9, 0.85, 0.8)))
	drill_box.add_child(_label("Something is broken. Restore connectivity between:", 13, Color(0.85, 0.8, 0.78)))
	for pair in Drill.targets:
		var a := Sim._ip_owner(pair[0])
		var ok: bool = a != null and Sim.ping(a, pair[1])["ok"] \
			and Sim._ip_owner(pair[1]) != null and Sim.ping(Sim._ip_owner(pair[1]), pair[0])["ok"]
		drill_box.add_child(_label("   %s  %s  ⇄  %s" % ["●" if ok else "○", pair[0], pair[1]],
			13, Color(0.55, 0.9, 0.6) if ok else Color(0.9, 0.88, 0.8)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	drill_box.add_child(row)
	var chk := Button.new()
	chk.text = "Check"
	_accent(chk)
	chk.pressed.connect(func() -> void:
		if Drill.solved():
			Drill.finish(true)
			get_parent().rebuild_racks()
			drill_panel.visible = false
		else:
			_show_drill_banner()  # re-renders per-pair status marks
			drill_box.add_child(_label("   ...still broken. ping/lldp/show run are your friends.", 12, Color(0.9, 0.6, 0.5))))
	row.add_child(chk)
	var give := Button.new()
	give.text = "Abandon (reveal faults)"
	give.pressed.connect(func() -> void:
		var revealed: Array = Drill.finish(false)
		for f in revealed:
			Game.log_event("DRILL debrief: " + str(f))
		get_parent().rebuild_racks()
		drill_panel.visible = false
		open_contracts())
	row.add_child(give)
	drill_panel.visible = true

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
	var body := _label("You run a tiny corner of a colocation floor, and you're going to grow it into a datacenter empire: by actually learning networking.\n\nHow to play:\n   •  Right/middle-drag pans, scroll zooms\n   •  Place rack (R), then click a rack to open it\n   •  Install switches and servers into rack slots\n   •  Click a port to configure it or run a cable\n   •  Every device has a real console (Open console)\n   •  Learn opens an encyclopedia, F1 lists every key\n\nEverything costs money: contracts pay, and rival companies are bidding for the same customers, so your prices have to beat the market. Later you can lease more sites, link them with WAN circuits, and buy competitors outright.\n\nOpen Contracts (toolbar) and take the first job. The briefs teach you every command you need.", 15, Color(0.8, 0.85, 0.92))
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

var contracts_tab := "Jobs"

func _build_contracts_overlay() -> void:
	contracts_overlay = _overlay()
	var v := _card(contracts_overlay, 660)
	var t := _header(v, close_contracts)
	t.text = "Your company"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	for name in ["Jobs", "Business", "Market", "Log"]:
		var tb := Button.new()
		tb.text = name
		tb.toggle_mode = true
		tb.pressed.connect(func() -> void:
			contracts_tab = name
			_refresh_contracts())
		tabs.add_child(tb)
		contracts_tabs[name] = tb
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

func _build_business_tab() -> void:
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
	var delta := Game.last_cycle_delta
	contracts_box.add_child(_label("last cycle: %s$%d net" % ["+" if delta >= 0 else "-", absi(delta)],
		13, Color(0.55, 0.9, 0.6) if delta >= 0 else Color(0.95, 0.6, 0.45)))
	if not Game.last_pl.is_empty():
		var parts: Array = []
		for k in Game.last_pl:
			var v: int = int(Game.last_pl[k])
			parts.append("%s %s$%d" % [k, "+" if v >= 0 else "-", absi(v)])
		var pl := _label("      " + "   ·   ".join(PackedStringArray(parts)), 12, Color(0.55, 0.6, 0.72))
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pl.custom_minimum_size = Vector2(560, 0)
		contracts_box.add_child(pl)
	var nr2 := Game.next_rank()
	contracts_box.add_child(_label("rank: %s%s" % [Game.rank(),
		"" if nr2.is_empty() else "   ·   %d points to %s" % [int(nr2[1]), nr2[0]]],
		13, Color(0.85, 0.8, 0.6)))
	contracts_box.add_child(_label("cycle %d   ·   lifetime earned $%d   ·   %d contracts, %d deals   ·   %d incidents, %d field faults" % [Game.cycle, Game.stats["earned"], Game.stats["contracts"], Game.stats["deals"], Game.stats["incidents"], Game.stats["faults"]], 12, Color(0.5, 0.56, 0.68)))
	contracts_box.add_child(_section("DEFENCE"))
	var scrub_row := HBoxContainer.new()
	contracts_box.add_child(scrub_row)
	scrub_row.add_child(_label("  Upstream scrubbing: %s   ($%d/cycle while enabled)" % [
		"ON" if Game.scrubbing else "off", Game.SCRUB_FEE], 13,
		Color(0.6, 0.9, 0.7) if Game.scrubbing else Color(0.75, 0.75, 0.8)))
	var scrub_btn := Button.new()
	scrub_btn.text = "Disable" if Game.scrubbing else "Enable"
	scrub_btn.pressed.connect(func() -> void:
		Game.scrubbing = not Game.scrubbing
		Game.log_event("SCRUBBING: %s." % ("enabled" if Game.scrubbing else "cancelled"))
		_refresh_contracts())
	scrub_row.add_child(scrub_btn)
	for a: Dictionary in Game.attacks:
		var blackholed := Game.attack_blackholed(a)
		var state := "absorbed by scrubbing" if Game.scrubbing else (
			"blackholed: the flood stops and so does their service" if blackholed
			else "hitting your network at %d Mbps" % int(a["mbps"]))
		contracts_box.add_child(_label("  ⚡ %s under attack (%s), %d cycle(s) to go: %s"
			% [a["target"], a["customer"], int(a["cycles_left"]), state], 13,
			Color(0.95, 0.6, 0.45) if not (Game.scrubbing or blackholed) else Color(0.85, 0.85, 0.6)))
	contracts_box.add_child(_section("ACHIEVEMENTS  (%d of %d)" % [Game.achievements.size(),
		Game.ACHIEVEMENTS.size()]))
	for a: Dictionary in Game.ACHIEVEMENTS:
		var got: bool = a["id"] in Game.achievements
		contracts_box.add_child(_label("  %s  %-26s %s" % ["★" if got else "☆", a["name"], a["how"]],
			12, Prefs.ok_colour() if got else Color(0.55, 0.58, 0.66)))
	contracts_box.add_child(_section("HISTORY"))
	if Game.history.size() < 2:
		contracts_box.add_child(_label("  Charts appear once a few revenue cycles have run.",
			13, Color(0.6, 0.62, 0.7)))
	else:
		for g in [["money", "Cash", Color(0.5, 0.95, 0.6)],
				["net", "Net per cycle", Color(0.6, 0.8, 1.0)],
				["reputation", "Reputation", Color(0.95, 0.8, 0.5)]]:
			contracts_box.add_child(UIW.Graph.new().setup(g[0], g[1], g[2]))
	contracts_box.add_child(_section("STAFF"))
	if Game.staff.is_empty():
		contracts_box.add_child(_label("  Nobody on the payroll: every fault is yours to fix.",
			13, Color(0.7, 0.7, 0.75)))
	for m: Dictionary in Game.staff.duplicate():
		var srow := HBoxContainer.new()
		contracts_box.add_child(srow)
		var sl := _label("  %-18s %-18s skill %d   $%d/cycle" % [m["name"], Staff.label(m),
			int(m["skill"]), int(m["salary"])], 13, Color(0.78, 0.85, 0.8))
		sl.tooltip_text = Staff.ROLES[m["role"]]["blurb"]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		srow.add_child(sl)
		var fire_btn := Button.new()
		fire_btn.text = "Let go"
		fire_btn.pressed.connect(func() -> void:
			Game.fire(m)
			_refresh_contracts())
		srow.add_child(fire_btn)
	Game.refresh_candidates()
	var hire_btn := Button.new()
	hire_btn.text = "Hire someone…   (payroll $%d/cycle)" % Staff.payroll()
	hire_btn.pressed.connect(func() -> void:
		var opts: Array = []
		for c: Dictionary in Game.candidates:
			opts.append("%-18s %-18s skill %d   asking $%d/cycle" % [c["name"], Staff.label(c),
				int(c["skill"]), int(c["salary"])])
		if opts.is_empty():
			_toast("no candidates right now: the market refreshes every few cycles")
			return
		_menu(hire_btn, opts, func(id: int) -> void:
			var err: String = Game.hire(Game.candidates[id])
			_refresh_contracts()
			if err != "":
				_toast(err)))
	contracts_box.add_child(hire_btn)
	contracts_box.add_child(_section("SITES"))
	for i in Game.site_count():
		var rent := int(Game.sites[i].get("rent", 0))
		contracts_box.add_child(_label("  %-26s %dx%d   %d racks%s" % [Game.site_name(i),
			Game.grid_size(i).x, Game.grid_size(i).y, Game.racks_on(i).size(),
			"   $%d/cycle rent" % rent if rent > 0 else ""], 13, Color(0.75, 0.8, 0.85)))
	var lease := Button.new()
	lease.text = "Lease another site…"
	lease.pressed.connect(func() -> void:
		var opts: Array = []
		for o: Dictionary in Game.SITE_OFFERS:
			opts.append("%-26s %dx%d   $%d fit-out, $%d/cycle" % [o["label"],
				int(o["grid"][0]), int(o["grid"][1]), int(o["setup"]), int(o["rent"])])
		_menu(lease, opts, func(id: int) -> void:
			var err: String = Game.lease_site(id)
			_refresh_contracts()
			if err != "":
				_toast(err)))
	contracts_box.add_child(lease)
	if Game.site_count() > 1:
		contracts_box.add_child(_section("WAN CIRCUITS"))
		for c: Dictionary in Game.circuits.duplicate():
			var crow := HBoxContainer.new()
			contracts_box.add_child(crow)
			var cl := _label("  %s: %s ⇄ %s   $%d/cycle" % [c["label"],
				Game.site_name(int(c["a"])), Game.site_name(int(c["b"])), int(c["fee"])],
				13, Color(0.7, 0.85, 0.9))
			cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			crow.add_child(cl)
			var cancel := Button.new()
			cancel.text = "Cancel"
			cancel.tooltip_text = "Ends the circuit and any cables riding it"
			cancel.pressed.connect(func() -> void:
				Game.cancel_circuit(c)
				_refresh_contracts())
			crow.add_child(cancel)
		var order := Button.new()
		order.text = "Order a circuit…"
		order.pressed.connect(func() -> void:
			var pairs: Array = []
			var combos: Array = []
			for i in Game.site_count():
				for j in range(i + 1, Game.site_count()):
					if not Game.circuit_between(i, j).is_empty():
						continue
					for g in Game.CIRCUIT_GRADES.size():
						var gr: Dictionary = Game.CIRCUIT_GRADES[g]
						pairs.append("%s ⇄ %s   %s   $%d install, $%d/cycle" % [
							Game.site_name(i), Game.site_name(j), gr["label"],
							int(gr["setup"]), int(gr["fee"])])
						combos.append([i, j, g])
			if pairs.is_empty():
				_toast("every pair of sites is already linked")
				return
			_menu(order, pairs, func(id: int) -> void:
				var pick: Array = combos[id]
				var err: String = Game.buy_circuit(int(pick[0]), int(pick[1]), int(pick[2]))
				_refresh_contracts()
				if err != "":
					_toast(err)))
		contracts_box.add_child(order)
	# (market moved to its own tab)

func _build_market_tab() -> void:
	if Game.market_intel == 0:
		contracts_box.add_child(_label("You have no read on competitor pricing yet: lose a bid and you will learn.",
			13, Color(0.6, 0.62, 0.7)))
	else:
		contracts_box.add_child(_label("Market intelligence from %d observed bid(s)." % Game.market_intel,
			13, Color(0.65, 0.85, 0.6)))
	contracts_box.add_child(_section("THE COMPETITION"))
	for r: Dictionary in Game.rivals:
		if not Rivals.alive(r):
			var fate: String = "acquired by %s" % r["merged_into"] if r.has("merged_into") else "acquired by you"
			contracts_box.add_child(_label("  %s: %s" % [r["name"], fate], 13,
				Color(0.6, 0.62, 0.68) if r.has("merged_into") else Color(0.5, 0.8, 0.6)))
			continue
		var price := Rivals.asking_price(r)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		contracts_box.add_child(row)
		var premises: String = ("site %dx%d" % [int(r["site"]["grid"][0]),
			int(r["site"]["grid"][1])]) if Rivals.has_site(r) else "no premises"
		var l := _label("  %-16s %2d cust · %d racks · %-11s · $%d" % [r["name"],
			int(r["deals"]), Rivals.racks_needed(r), premises, price], 13, Color(0.8, 0.78, 0.7))
		l.tooltip_text = ("Buying %s brings %d rack(s) and %d contract(s). %s" % [r["name"],
			Rivals.racks_needed(r), int(r["deals"]),
			("Their site '%s' comes with the company." % r["site"]["name"]) if Rivals.has_site(r)
			else "Their racks must fit on a floor you already have."])
		l.add_theme_font_override("font", mono)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var buy := Button.new()
		buy.text = "Acquire"
		buy.disabled = Game.money < price
		buy.pressed.connect(func() -> void:
			var err: String = Game.buy_rival(r)
			_refresh_contracts()
			if err != "":
				_toast(err)
			else:
				get_parent().rebuild_racks())
		row.add_child(buy)

func _build_log_tab() -> void:
	if Game.events.is_empty():
		contracts_box.add_child(_label("Nothing has happened yet.", 13, MUTED))
		return
	contracts_box.add_child(_section("EVENT LOG"))
	for ev in Game.events:
		var col := Color(0.75, 0.8, 0.88)
		if "SECURITY" in ev or "POACHED" in ev or "CANCELLED" in ev:
			col = Color(0.95, 0.55, 0.45)
		elif "OVERHEAT" in ev or "FIELD" in ev or "LOST:" in ev:
			col = Color(0.95, 0.7, 0.4)
		elif "ACQUISITION" in ev or "INTEGRATION" in ev or "CIRCUIT" in ev:
			col = Color(0.6, 0.9, 0.75)
		var l := _label(ev, 12, col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(580, 0)
		contracts_box.add_child(l)

func _build_jobs_tab() -> void:
	if not Game.offers.is_empty():
		contracts_box.add_child(_section("INCOMING OFFERS: QUOTE A PRICE PER REVENUE CYCLE"))
	for offer: Dictionary in Game.offers:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _sb(Color(0.12, 0.1, 0.15), Color(0.6, 0.5, 0.8, 0.5), 8, 14))
		contracts_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var ct2: Dictionary = Market.TYPES.get(offer.get("ctype", "enterprise"), {})
		cv.add_child(_label("%s   ·   %s   ·   %s" % [offer["customer"],
			Market.label_for(offer["kind"]), ct2.get("label", "")], 16, Color.WHITE))
		if ct2.has("note"):
			cv.add_child(_label(ct2["note"], 13, Color(0.7, 0.72, 0.8)))
		cv.add_child(_label("Word is: %s." % offer["hint"], 13, Color(0.75, 0.7, 0.85)))
		var otier := Market.tier(int(offer.get("sla", 0)))
		if float(otier["uptime"]) > 0.0:
			cv.add_child(_label("📜 Service level: %s. Miss it and they charge back %.1fx the fee."
				% [otier["label"], float(otier["penalty"])], 13, Color(1.0, 0.8, 0.5)))
		else:
			cv.add_child(_label("📜 Service level: best effort.", 13, Color(0.65, 0.7, 0.75)))
		var brief := _label(offer["brief"], 14, Color(0.78, 0.8, 0.88))
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.custom_minimum_size = Vector2(560, 0)
		cv.add_child(brief)
		cv.add_child(_label("💡 " + offer["costs"], 13, Color(0.6, 0.65, 0.55)))
		var est: Array = Game.market_estimate(offer)
		if Rivals.best_bidder(offer).is_empty():
			cv.add_child(_label("📉 No competitor is chasing this one: price it properly.",
				13, Color(0.7, 0.9, 0.65)))
		elif est.is_empty():
			cv.add_child(_label("📉 You have no read on what competitors charge yet.", 13, Color(0.6, 0.6, 0.7)))
		else:
			cv.add_child(_label("📉 Rivals would likely quote $%d to $%d for this." % [int(est[0]), int(est[1])],
				13, Color(0.7, 0.85, 0.6)))
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
			var chip_txt := "PAYING"
			var chip_col := Color(0.4, 0.85, 0.5)
			if not ok:
				chip_txt = "DOWN"
				chip_col = Color(0.95, 0.45, 0.35)
			elif deal.get("degraded", false):
				chip_txt = "SLOW"
				chip_col = Color(0.95, 0.75, 0.4)
			contracts_box.add_child(_chip_row(
				chip_txt,
				chip_col,
				"%s: %s   $%d/cycle%s" % [deal["customer"], Market.label_for(deal["kind"]), int(deal["fee"]),
					"" if ok else "   (not delivered: not paying)"],
				14, Color(0.55, 0.85, 0.62) if ok else Color(0.95, 0.6, 0.45)))
			var detail := String(deal.get("brief", ""))
			var spec_bits: Array = []
			for k in deal["params"]:
				spec_bits.append("%s: %s" % [k, str(deal["params"][k])])
			if not spec_bits.is_empty():
				detail += "   [" + ", ".join(PackedStringArray(spec_bits)) + "]"
			var dtier := Market.tier(int(deal.get("sla", 0)))
			if int(deal.get("cycles", 0)) > 0:
				var up_pct := 100.0 * float(deal.get("up_cycles", 0)) / float(deal["cycles"])
				detail += "   [%s, %d%% uptime over %d cycles]" % [dtier["label"], int(up_pct),
					int(deal["cycles"])]
			var missed_n: int = int(deal.get("missed", 0))
			if missed_n >= 3:
				detail += "   ⚠ undelivered %d cycles: they walk at 5" % missed_n
			if detail != "":
				var dl := _label("      " + detail, 12,
					Color(0.6, 0.66, 0.76) if ok else Color(0.8, 0.68, 0.6))
				dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				dl.custom_minimum_size = Vector2(560, 0)
				contracts_box.add_child(dl)

	for a: Dictionary in Game.acquisitions:
		if bool(a.get("done", false)):
			contracts_box.add_child(_chip_row("MERGED", Color(0.4, 0.85, 0.5),
				"%s is integrated into your network" % a["rival"], 13, Color(0.55, 0.8, 0.6)))
			continue
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _sb(Color(0.1, 0.12, 0.1), Color(0.5, 0.8, 0.5, 0.5), 8, 14))
		contracts_box.add_child(card)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		cv.add_child(_label("INTEGRATION: %s" % a["rival"], 16, Color.WHITE))
		var where: String = ("on their own site '%s' (switch floors in the HUD, and reaching it needs a leased circuit)"
			% Game.site_name(int(a.get("site", 0)))) if bool(a.get("premises", false)) else "moved into your room"
		var brief := _label(("Their kit is %s, but it still runs their way: subnet %s.0/24 on VLAN %d, "
			+ "cabled only to itself. Merge it into your network without breaking their customers, "
			+ "then save the configs.") % [where, a["net"], int(a["vlan"])], 13, Color(0.78, 0.82, 0.78))
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.custom_minimum_size = Vector2(560, 0)
		cv.add_child(brief)
		for req in Game.integration_status(a):
			var ok: bool = req["ok"]
			var txt: String = ("●  " if ok else "○  ") + String(req["d"])
			if not ok and String(req.get("detail", "")) != "":
				txt += "   (%s)" % req["detail"]
			cv.add_child(_label(txt, 13, Color(0.5, 0.95, 0.6) if ok else Color(0.7, 0.65, 0.6)))
		var btn := Button.new()
		btn.text = "Check integration & collect $1500"
		_accent(btn)
		btn.pressed.connect(func() -> void:
			Game.try_complete_integration(a)
			_refresh_contracts())
		cv.add_child(btn)

func _toast(text: String) -> void:
	if _toast_lbl == null or not is_instance_valid(_toast_lbl):
		_toast_lbl = _label("", 14, Color(1.0, 0.85, 0.5))
		contracts_box.add_child(_toast_lbl)
		contracts_box.move_child(_toast_lbl, 0)
	_toast_lbl.text = text

func _refresh_contracts() -> void:
	for c in contracts_box.get_children():
		c.queue_free()
	for k in contracts_tabs:
		contracts_tabs[k].button_pressed = (k == contracts_tab)
	match contracts_tab:
		"Business":
			_build_business_tab()
			return
		"Market":
			_build_market_tab()
			return
		"Log":
			_build_log_tab()
			return
	_build_jobs_tab()
	contracts_box.add_child(_section("CAMPAIGN"))
	var found_active := false
	var active_shown := 0
	for c in Contracts.all():
		var done: bool = c["id"] in Game.contracts_done
		if done:
			if Contracts.retired(c["id"]):
				contracts_box.add_child(_chip_row("RETIRED", Color(0.55, 0.6, 0.7),
					"%s: %s   superseded by a later job" % [c["title"], c["customer"]],
					14, Color(0.55, 0.6, 0.7)))
				continue
			var healthy: bool = Game.sla_status.get(c["id"], true)
			var mrr: int = int(c["reward"]) / 10
			if healthy:
				contracts_box.add_child(_chip_row("DONE", Color(0.4, 0.85, 0.5),
					"%s: %s   service fee +$%d / cycle" % [c["title"], c["customer"], mrr],
					14, Color(0.55, 0.8, 0.6)))
			else:
				contracts_box.add_child(_chip_row("BREACH", Color(0.95, 0.45, 0.35),
					"%s: %s   SLA BREACH: service down, not paying!" % [c["title"], c["customer"]],
					14, Color(0.95, 0.55, 0.4)))
				for rq in c["reqs"]:
					var rq_ok: bool = rq["t"].call()
					contracts_box.add_child(_label("      %s  %s" % ["●" if rq_ok else "○", rq["d"]],
						12, Color(0.5, 0.8, 0.55) if rq_ok else Color(0.95, 0.6, 0.45)))
			continue
		if active_shown >= 3:
			contracts_box.add_child(_label("🔒  more jobs unlock as you finish these", 13, Color(0.45, 0.5, 0.6)))
			break
		active_shown += 1
		found_active = true
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _sb(Color(0.09, 0.12, 0.16), ACCENT * Color(1, 1, 1, 0.5), 8, 14))
		contracts_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		cv.add_child(_label("%s: %s      reward $%d" % [c["title"], c["customer"], c["reward"]], 17, Color.WHITE))
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
		contracts_box.add_child(_label("All contracts complete! More arrive with future updates -\nsee the GitHub roadmap.", 14, Color(0.7, 0.85, 0.75)))

# ---------- refresh / CLI ----------

func _refresh_capture() -> void:
	if cap_box == null or not cap_box.visible or cur_dev == null:
		return
	cap_out.clear()
	if cur_dev.capture.is_empty():
		cap_out.append_text("(no frames captured: generate some traffic, e.g. ping something)")
	else:
		cap_out.append_text("\n".join(PackedStringArray(cur_dev.capture.slice(-14))))

func _refresh_open() -> void:
	_refresh_capture()
	_fit_cards.call_deferred()
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
		_scroll_to_bottom.call_deferred()
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
		elif search_overlay.visible:
			search_overlay.visible = false
		elif ops_overlay.visible:
			ops_overlay.visible = false
		elif help_overlay.visible:
			help_overlay.visible = false
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
