class_name UILayer
extends CanvasLayer
## All UI: toolbar, rack view, device view (faceplate + console),
## interface editor, VLAN manager.

const ACCENT: Color = UIW.COLORS["accent"]
const BG: Color = UIW.COLORS["overlay"]
const PANEL: Color = UIW.COLORS["surface"]
const DIM: Color = UIW.COLORS["backdrop"]
const MUTED: Color = UIW.COLORS["muted"]

var mode_btns := {}
var rack_overlay: Control
var rack_title: Label
var slot_box: VBoxContainer
var rack_metric_values := {}
var rack_airflow_lbl: Label
var rack_cable_layer: UIW.CablePull
var rack_cable_from: Net.Iface
var rack_cable_old_link: Net.Link
var rack_note_ui := {}
var rack_note_btn: Button

var dev_overlay: Control
var dev_title: Label
var name_edit: LineEdit
var name_hint: Label
var status_opt: OptionButton
var psu_opt: OptionButton
var port_row: VBoxContainer
var dev_power_lbl: Label
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
var dev_note_ui := {}
var dev_note_btn: Button

var if_overlay: Control
var if_title: Label
var if_mac: Label
var if_vrrp_lbl: Label
var if_state_box: VBoxContainer
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
var pedia_topic_buttons: Array = []
var menu_overlay: Control
var map_overlay: Control
var welcome_overlay: Control
var tutorial_panel: PanelContainer
var tutorial_box: VBoxContainer
var tutorial_suppressed_by_overlay := false
var contracts_overlay: Control
var contracts_box: VBoxContainer
var contracts_tabs := {}
var _toast_lbl: Label
var vlan_section: VBoxContainer
var vlan_box: VBoxContainer

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
var clock_lbl: Label
var expand_btn: Button
var site_btn: Button
var speed_btns := {}
var hud_logo: Label
var hud_nav_row: HBoxContainer
var hud_status_row: HBoxContainer
var hud_alert_btn: Button
var hud_learn_btn: Button
var hud_shortcut_hint: Label
var hud_compact := false
var hud_msg: Label
var hud_msg_tween: Tween
var theme_res: Theme
var mono: SystemFont

func _ready() -> void:
	mono = UIW.mono_font()
	theme_res = _make_theme()
	_build_toolbar()
	_build_rack_overlay()
	_build_dev_overlay()
	_build_if_overlay()
	_build_contracts_overlay()
	_build_welcome()
	_build_demo_end()
	_build_map()
	_build_menu()
	_build_help()
	_build_ops()
	_build_search()
	_build_pedia()
	_build_tutorial()
	Game.topology_changed.connect(_refresh_tutorial)
	Game.money_changed.connect(_refresh_tutorial)
	Game.events_changed.connect(_refresh_attention)
	Game.topology_changed.connect(_refresh_open)
	Game.topology_changed.connect(_refresh_money)
	Game.money_changed.connect(_refresh_money)
	Game.speed_changed.connect(_refresh_speed)
	Game.money_changed.connect(_money_flash)
	get_viewport().size_changed.connect(_refresh_hud_layout)
	_refresh_money()
	_refresh_hud_layout()

func _money_flash() -> void:
	Sfx.play("money")
	money_lbl.modulate = Color(1.6, 1.6, 1.2)
	create_tween().tween_property(money_lbl, "modulate", Color.WHITE, 0.5)

func _refresh_attention() -> void:
	if contracts_btn == null:
		return
	var n := Game.offers.size()
	var urgent := ""
	for deal in Game.deals:
		if not deal["healthy"]:
			n += 1
			if urgent == "":
				urgent = "%s is down" % deal["customer"]
	for cid in Game.sla_status:
		if not Game.sla_status[cid] and not Contracts.retired(cid):
			n += 1
			urgent = "SLA breach: %s" % cid
	n += Game.unread_events
	if n > 0:
		contracts_btn.text = ("Co. (%d)" if hud_compact else "Company (%d!)") % n
		contracts_btn.modulate = Color(1.15, 0.95, 0.7)
	else:
		contracts_btn.text = "Co." if hud_compact else "Company"
		contracts_btn.modulate = Color.WHITE
	if hud_alert_btn:
		hud_alert_btn.visible = n > 0
		if n > 0:
			if urgent != "":
				hud_alert_btn.text = "! " + urgent
			elif Game.unread_events > 0:
				hud_alert_btn.text = "! %d new event%s" % [Game.unread_events,
					"" if Game.unread_events == 1 else "s"]
			elif Game.offers.size() > 0:
				hud_alert_btn.text = "! %d offer%s waiting" % [Game.offers.size(),
					"" if Game.offers.size() == 1 else "s"]
			else:
				hud_alert_btn.text = "! %d item%s need attention" % [n, "" if n == 1 else "s"]
			hud_alert_btn.tooltip_text = "Open Company to act on the highest-priority item."

func _refresh_hud_layout(width_override := -1.0) -> void:
	if hud_nav_row == null:
		return
	var width: float = width_override if width_override >= 0.0 \
		else get_viewport().get_visible_rect().size.x
	hud_compact = width < 1180.0
	hud_logo.visible = not hud_compact
	hud_learn_btn.text = "?" if hud_compact else "LEARN"
	mode_btns[0].text = "Q" if hud_compact else "CURSOR"
	mode_btns[0].tooltip_text = "Select mode (Q)"
	mode_btns[1].text = "R" if hud_compact else "＋ BUILD"
	mode_btns[1].tooltip_text = "Place a rack (R)"
	objective_lbl.custom_minimum_size.x = 150 if hud_compact else 260
	clock_lbl.visible = not hud_compact
	site_btn.custom_minimum_size.x = 80 if hud_compact else 120
	hud_shortcut_hint.visible = false
	_refresh_attention()
	_refresh_money()

func hud_toast(text: String, good := false) -> void:
	## a short message on the HUD, for actions that would otherwise fail silently
	Sfx.play("good" if good else "bad")
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
			objective_lbl.text = ("%s  ·  NEXT  %s" % [Demo.progress_text(), next_c]) if Demo.active() \
				else "NEXT  " + next_c
		else:
			var nr := Game.next_rank()
			objective_lbl.text = "★ %s" % Game.rank() if nr.is_empty() \
				else "★ %s  ·  $%d to %s" % [Game.rank(), int(nr[1]), nr[0]]
	if clock_lbl:
		var f := Game.day_factor()
		var shift_icon := "☀" if Game.day_slot() in [2, 3, 4, 5] else "☾"
		var coverage := ""
		if not Game.staff.is_empty() and not Staff.anyone_on_shift():
			coverage = "  ·  UNATTENDED"
		clock_lbl.text = "%s  %s  %d%%%s" % [shift_icon, Game.day_name().to_upper(),
			int(round(f * 100.0)), coverage]
		clock_lbl.add_theme_color_override("font_color",
			UIW.colour("danger") if coverage != "" else
			(UIW.colour("warning") if f > 1.1 else UIW.colour("muted")))
		clock_lbl.tooltip_text = "Current shift and traffic level. The room lighting follows this clock; unattended hours leave incidents waiting for the next crew."
	var power := ""
	if Game.stage >= 1:
		power = "  ⚡%d/❄%d" % [Game.power_draw(), Game.cooling_capacity()]
		if Game.overheating():
			power += " 🔥"
	var debt_s := ("  (debt $%d)" % Game.debt) if Game.debt > 0 else ""
	money_lbl.text = "%s$%d%s  ♦%d%s" % ["SANDBOX  " if Game.sandbox else "",
		Game.money, debt_s, Game.reputation, power]
	if Game.stage >= 1:
		money_lbl.tooltip_text = "Cash and reputation. Power: %dW nameplate, %dW billed at $%.3f per watt per cycle = $%d next cycle. Cooling capacity: %dW." % [
			Game.power_draw(), Game.effective_draw(), Game.energy_rate(), Game.power_bill(),
			Game.cooling_capacity()]
	else:
		money_lbl.tooltip_text = "Cash and reputation. Electricity and cooling are included in this colo lease."
	money_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.35) if Game.overheating() else Color(0.55, 0.95, 0.6))
	if site_btn:
		site_btn.text = Game.site_name(Game.current_site)
		site_btn.visible = Game.site_count() > 1
	if Game.current_site != 0:
		expand_btn.visible = false  # acquired floors come as they are
	elif Game.stage < Game.STAGES.size() - 1:
		var nxt: Dictionary = Game.STAGES[Game.stage + 1]
		expand_btn.text = ("+$%d" if hud_compact else "Expand ($%d)") % int(nxt["price"])
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
	# The live brief belongs to the floor, not on top of focused workspaces.
	# Remember whether we hid it so it can return after the overlay closes.
	if tutorial_panel:
		if is_open():
			if tutorial_panel.visible:
				tutorial_suppressed_by_overlay = true
				tutorial_panel.visible = false
		elif tutorial_suppressed_by_overlay:
			tutorial_suppressed_by_overlay = false
			_refresh_tutorial()
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
		or ops_overlay.visible or search_overlay.visible or demo_overlay.visible

# ---------- theme / widget helpers ----------

func _make_theme() -> Theme:
	return UIW.make_theme()

func _sb(bg: Color, border: Color, radius := 6, margin := 8) -> StyleBoxFlat:
	return UIW.custom_box(bg, border, radius, margin)

func _flat_sb(bg: Color, border: Color, radius := 0, margin := 8) -> StyleBoxFlat:
	## Authored physical surfaces (paper, labels, etched plates) should not inherit
	## the raised-card shadow used by interactive command panels.
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	style.shadow_size = 0
	return style

func _wrap(text: String, size := 14, color := Color(0.85, 0.89, 0.95), width := 560.0) -> Label:
	## a label that wraps instead of pushing its container sideways
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l

func _label(text: String, size := 15, color := Color(0.85, 0.89, 0.95)) -> Label:
	var l := UIW.make_text(text)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _accent(b: Button) -> Button:
	return UIW.style_button(b, "primary")


func _section(text: String) -> Label:
	return UIW.make_section(text)

func _show_overlay(o: Control) -> void:
	Sfx.play("open")
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
	var panel := UIW.CommandPanel.new().setup("overlay", "accent", UIW.space("lg"))
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(min_w, 0)
	scroll.add_theme_constant_override("scrollbar_v_separation", UIW.space("md"))
	panel.add_child(scroll)
	_card_scrolls.append(scroll)
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_right", UIW.space("lg"))
	content_margin.add_theme_constant_override("margin_bottom", UIW.space("sm"))
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content_margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UIW.space("lg"))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_child(v)
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
		var need_y := need.y
		if scroll.has_meta("visible_stack"):
			var stack := scroll.get_meta("visible_stack") as VBoxContainer
			var visible_count := 0
			need_y = 0.0
			for child in stack.get_children():
				if child is Control and child.visible:
					need_y += (child as Control).get_combined_minimum_size().y
					visible_count += 1
			need_y += maxf(0, visible_count - 1) * stack.get_theme_constant("separation")
			need_y += UIW.space("sm")
		scroll.custom_minimum_size = Vector2(
			minf(maxf(need.x, scroll.custom_minimum_size.x), vp.x - 160.0),
			minf(need_y, vp.y - 190.0))

func _header(box: VBoxContainer, on_back: Callable) -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)
	var title := _label("", 20, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title)
	var back := Button.new()
	back.text = "ESC  CLOSE"
	UIW.style_button(back, "quiet")
	back.pressed.connect(on_back)
	h.add_child(back)
	return title

func _note_card(box: VBoxContainer, on_save: Callable) -> Dictionary:
	var paper := PanelContainer.new()
	var paper_style := _flat_sb(Color("dfca8c"), Color("8d7948"), 2, 14)
	paper_style.border_width_top = 1
	paper_style.border_width_bottom = 2
	paper.add_theme_stylebox_override("panel", paper_style)
	paper.visible = false
	box.add_child(paper)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIW.space("md"))
	paper.add_child(row)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", UIW.space("xs"))
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var cap := _label("HANDOVER NOTE  /  PAST YOU WROTE", 10, Color("51462d"))
	cap.add_theme_font_override("font", mono)
	words.add_child(cap)
	var edit := LineEdit.new()
	edit.max_length = 140
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_override("font", mono)
	edit.add_theme_font_size_override("font_size", 13)
	edit.add_theme_color_override("font_color", Color("302a1e"))
	edit.add_theme_color_override("caret_color", Color("302a1e"))
	edit.add_theme_color_override("font_placeholder_color", Color("75694a"))
	var writing_line := _flat_sb(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 6)
	writing_line.border_color = Color("8d7948")
	writing_line.border_width_bottom = 1
	edit.add_theme_stylebox_override("normal", writing_line)
	var writing_focus := writing_line.duplicate() as StyleBoxFlat
	writing_focus.border_color = Color("554827")
	writing_focus.border_width_bottom = 2
	edit.add_theme_stylebox_override("focus", writing_focus)
	edit.placeholder_text = "Short context for whoever opens this next…"
	edit.text_submitted.connect(func(_text: String) -> void: on_save.call(edit.text))
	words.add_child(edit)
	var age := _label("", 9, Color("665939"))
	age.add_theme_font_override("font", mono)
	words.add_child(age)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", UIW.space("xs"))
	row.add_child(actions)
	var pin := _note_action("PIN")
	pin.pressed.connect(func() -> void: on_save.call(edit.text))
	actions.add_child(pin)
	var remove := _note_action("REMOVE")
	remove.pressed.connect(func() -> void: on_save.call(""))
	actions.add_child(remove)
	return {"panel": paper, "edit": edit, "age": age}

func _note_action(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.add_theme_font_override("font", mono)
	button.add_theme_font_size_override("font_size", 10)
	for state in ["font_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("51462d"))
	button.add_theme_color_override("font_hover_color", Color("241f16"))
	var normal := _flat_sb(Color(0, 0, 0, 0), Color("8d7948"), 0, 5)
	normal.border_width_top = 0
	normal.border_width_left = 0
	normal.border_width_right = 0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.12)
	hover.border_color = Color("51462d")
	for state in ["normal", "focus", "pressed"]:
		button.add_theme_stylebox_override(state, normal)
	button.add_theme_stylebox_override("hover", hover)
	return button

func _refresh_note_card(parts: Dictionary, target: Variant, trigger: Button) -> void:
	var note: Dictionary = target.note
	(parts["panel"] as PanelContainer).visible = not note.is_empty()
	trigger.text = "✎ EDIT NOTE" if not note.is_empty() else "✎ LEAVE NOTE"
	if note.is_empty():
		return
	(parts["edit"] as LineEdit).text = String(note.get("text", ""))
	var age := Game.note_age(target)
	(parts["age"] as Label).text = ("WRITTEN THIS CYCLE" if age == 0 else
		("STALE  ·  %d CYCLES OLD" % age if age >= 12 else "%d CYCLES OLD" % age))

func _open_note_card(parts: Dictionary) -> void:
	(parts["panel"] as PanelContainer).visible = true
	(parts["edit"] as LineEdit).grab_focus.call_deferred()

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
	var sb := UIW.panel_box("hud", "sm")
	sb.border_color = Color(0.25, 0.5, 0.6, 0.5)
	sb.border_width_bottom = 1
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	bar.add_theme_stylebox_override("panel", sb)
	add_child(bar)
	var hud_stack := VBoxContainer.new()
	hud_stack.add_theme_constant_override("separation", UIW.space("xs"))
	bar.add_child(hud_stack)
	hud_nav_row = HBoxContainer.new()
	hud_nav_row.add_theme_constant_override("separation", UIW.space("sm"))
	hud_stack.add_child(hud_nav_row)
	var h := hud_nav_row
	hud_logo = _label("PE  /  CONTROL ROOM", 15, ACCENT)
	hud_logo.add_theme_font_override("font", mono)
	h.add_child(hud_logo)
	h.add_child(VSeparator.new())
	for m in [["CURSOR", 0], ["＋ BUILD", 1]]:
		var b := Button.new()
		b.text = m[0]
		b.toggle_mode = true
		b.pressed.connect(func() -> void: get_parent().mode = m[1])
		h.add_child(b)
		mode_btns[m[1]] = b
	hud_learn_btn = Button.new()
	hud_learn_btn.text = "LEARN"
	hud_learn_btn.tooltip_text = "Networkopedia: every concept the game teaches"
	hud_learn_btn.pressed.connect(open_pedia)
	h.add_child(hud_learn_btn)
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
	opsb.text = "OPS"
	opsb.tooltip_text = "Operations dashboard (O)"
	opsb.pressed.connect(toggle_ops)
	h.add_child(opsb)
	var mapb := Button.new()
	mapb.text = "MAP"
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
	var nav_spacer := Control.new()
	nav_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nav_spacer)
	var save_btn := Button.new()
	save_btn.text = "💾"
	save_btn.tooltip_text = "Save the game"
	save_btn.pressed.connect(func() -> void: Game.save_game())
	h.add_child(save_btn)
	hud_status_row = HBoxContainer.new()
	hud_status_row.add_theme_constant_override("separation", UIW.space("sm"))
	hud_stack.add_child(hud_status_row)
	h = hud_status_row
	objective_lbl = _label("", 12, Color(0.65, 0.8, 0.9))
	objective_lbl.custom_minimum_size = Vector2(260, 0)
	objective_lbl.clip_text = true
	objective_lbl.tooltip_text = "Current campaign objective: details in Contracts"
	h.add_child(objective_lbl)
	hud_alert_btn = Button.new()
	hud_alert_btn.visible = false
	UIW.style_button(hud_alert_btn, "danger")
	hud_alert_btn.pressed.connect(open_contracts)
	h.add_child(hud_alert_btn)
	var status_spacer := Control.new()
	status_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(status_spacer)
	clock_lbl = _label("", 11, Color(0.55, 0.65, 0.78))
	clock_lbl.custom_minimum_size = Vector2(120, 0)
	clock_lbl.clip_text = true
	h.add_child(clock_lbl)
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
	update_mode(0)
	hud_shortcut_hint = _label("Space pause  ·  Q select  ·  R place rack  ·  F find  ·  O ops  ·  M map  ·  F1 keys  ·  Esc menu  ·  right-drag pan  ·  scroll zoom", 12, Color(0.45, 0.5, 0.62))
	hud_shortcut_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hud_shortcut_hint.position = Vector2(20, -30)
	hud_shortcut_hint.theme = theme_res
	add_child(hud_shortcut_hint)

func update_mode(m: int) -> void:
	for k in mode_btns:
		mode_btns[k].button_pressed = k == m

# ---------- rack view ----------

func _build_rack_overlay() -> void:
	rack_overlay = _overlay()
	var v := _card(rack_overlay, 640)
	rack_title = _header(v, close_rack)
	rack_note_ui = _note_card(v, func(text: String) -> void:
		Game.set_note(cur_rack, text)
		_refresh_note_card(rack_note_ui, cur_rack, rack_note_btn)
		_refresh_slots())
	var rack_metrics := HBoxContainer.new()
	rack_metrics.add_theme_constant_override("separation", UIW.space("sm"))
	v.add_child(rack_metrics)
	rack_metrics.add_child(_rack_metric("CABINET LOAD", "units", "accent"))
	rack_metrics.add_child(_rack_metric("POWER", "power", "warm"))
	rack_metrics.add_child(_rack_metric("FEED BALANCE", "feeds", "success"))
	rack_airflow_lbl = _label("", 11, UIW.colour("success"))
	rack_airflow_lbl.add_theme_font_override("font", mono)
	v.add_child(rack_airflow_lbl)
	var info_row := HBoxContainer.new()
	v.add_child(info_row)
	var info := _label("Click hardware to inspect. Grab any free jack and pull it to another device.", 13, MUTED)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(info)
	rack_note_btn = Button.new()
	rack_note_btn.text = "✎ LEAVE NOTE"
	rack_note_btn.tooltip_text = "Leave short context for yourself on this cabinet"
	rack_note_btn.pressed.connect(func() -> void: _open_note_card(rack_note_ui))
	info_row.add_child(rack_note_btn)
	var bp_btn := Button.new()
	bp_btn.text = "Blueprints"
	bp_btn.tooltip_text = "Save this rack's layout, or build a saved one into an empty rack"
	bp_btn.pressed.connect(func() -> void:
		var opts: Array = ["Save this rack as a blueprint…"]
		var usable: Array = []
		for b: Dictionary in Game.blueprints:
			opts.append("Build '%s'   ($%d of hardware)" % [b["name"], Game.blueprint_price(b)])
			usable.append(b)
		_menu(bp_btn, opts, func(id: int) -> void:
			if id == 0:
				var err: String = Game.save_blueprint(cur_rack, "rack %s layout" % cur_rack.name)
				hud_toast(err if err != "" else "Blueprint saved.", err == "")
			else:
				var err2: String = Game.apply_blueprint(cur_rack, usable[id - 1])
				hud_toast(err2 if err2 != "" else "Rack built from the blueprint.", err2 == "")
			_refresh_slots()))
	info_row.add_child(bp_btn)
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
	rack_cable_layer = UIW.CablePull.new().setup()
	rack_overlay.add_child(rack_cable_layer)

func _rack_metric(caption: String, key: String, semantic: String) -> PanelContainer:
	var panel := UIW.style_panel(PanelContainer.new(), "console", "sm")
	panel.custom_minimum_size = Vector2(190, 60)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIW.space("xs"))
	panel.add_child(box)
	var cap := _section(caption)
	box.add_child(cap)
	var value := _label("—", 13, UIW.colour(semantic))
	value.add_theme_font_override("font", mono)
	box.add_child(value)
	rack_metric_values[key] = value
	return panel

func open_rack(r: Net.Rack) -> void:
	cur_rack = r
	dev_overlay.visible = false
	rack_title.text = "Rack %s" % r.name
	_refresh_note_card(rack_note_ui, r, rack_note_btn)
	_refresh_slots()
	_show_overlay(rack_overlay)

func close_rack() -> void:
	rack_overlay.visible = false
	cur_rack = null

func _refresh_slots() -> void:
	for c in slot_box.get_children():
		c.queue_free()
	var occupied := 0
	var feed_a := 0
	var feed_b := 0
	var dual := 0
	for rack_i in Net.Rack.SLOTS:
		var rack_dev: Net.NDevice = cur_rack.slots[rack_i]
		if rack_dev:
			occupied += Game.model_height(rack_dev.model)
			match rack_dev.psu:
				"A": feed_a += 1
				"B": feed_b += 1
				"AB": dual += 1
	var rack_watts := Game.rack_watts(cur_rack)
	(rack_metric_values["units"] as Label).text = "%02d / %02d U OCCUPIED" % [occupied, Net.Rack.SLOTS]
	(rack_metric_values["power"] as Label).text = ("%d W  ·  INCLUDED" % rack_watts if Game.stage < 1 else
		"%d W  ·  ~$%d/CYCLE" % [rack_watts, int(round(float(rack_watts) *
			Game.efficiency_factor() * Game.energy_rate()))])
	(rack_metric_values["feeds"] as Label).text = "A %02d  /  B %02d  /  DUAL %02d" % [feed_a, feed_b, dual]
	var gaps := 0
	var blanks := 0
	for slot_i in Net.Rack.SLOTS:
		if cur_rack.slots[slot_i] == null and not cur_rack.covered.has(slot_i):
			gaps += 1
			if cur_rack.blanked.has(slot_i):
				blanks += 1
	var airflow_gain := int(round(Game.rack_airflow_seal(cur_rack) * 8.0))
	rack_airflow_lbl.text = "AIRFLOW SEAL  %02d / %02d UNUSED U  ·  %d%% LESS RECIRCULATION" \
		% [blanks, gaps, airflow_gain]
	rack_airflow_lbl.modulate = UIW.colour("success") if gaps > 0 and blanks == gaps else UIW.colour("muted")
	for i in range(Net.Rack.SLOTS - 1, -1, -1):  # top of rack first
		var dev: Net.NDevice = cur_rack.slots[i]
		var slot := UIW.RackSlot.new()
		if dev:
			slot.setup(i + 1, dev, func() -> void: open_dev(dev))
		elif cur_rack.covered.has(i):
			# the upper half of a two-unit box: part of the device below
			var below: Net.NDevice = cur_rack.covered[i]
			slot.setup(i + 1, below, func() -> void: open_dev(below))
			slot.upper_half = true
		else:
			var idx := i
			slot.setup(i + 1, null, func() -> void: _pick_new_device(idx, slot), cur_rack.blanked.has(i))
		slot.cable_started.connect(_rack_cable_start)
		slot.cable_moved.connect(_rack_cable_move)
		slot.cable_released.connect(_rack_cable_release)
		slot.blanking_toggled.connect(_toggle_rack_blanking)
		slot_box.add_child(slot)
	rack_cable_layer.watch(cur_rack, slot_box)

func _toggle_rack_blanking(slot: int) -> void:
	if Game.toggle_blanking(cur_rack, slot):
		var fitted := cur_rack.blanked.has(slot)
		hud_toast(("Blanking panel fitted at U%d. Hot-air recirculation reduced." if fitted \
			else "Blanking panel removed from U%d.") % (slot + 1), fitted)
		_refresh_slots()

func _rack_cable_start(iface: Net.Iface, screen_pos: Vector2) -> void:
	rack_cable_old_link = Game.link_at(iface)
	if rack_cable_old_link:
		# Pulling a fitted plug leaves the far end anchored. The loose end can be
		# dressed into another jack, or dropped away from the rack to unplug it.
		rack_cable_from = rack_cable_old_link.other(iface)
		var anchored_pos := _rack_port_position(rack_cable_from)
		rack_cable_layer.begin(anchored_pos, rack_cable_from, rack_cable_old_link)
	else:
		rack_cable_from = iface
		rack_cable_layer.begin(screen_pos, iface)

func _rack_port_position(iface: Net.Iface) -> Vector2:
	for child in slot_box.get_children():
		if child is UIW.RackSlot and (child as UIW.RackSlot).dev == iface.dev:
			return (child as UIW.RackSlot).port_screen_position(iface)
	return Vector2.ZERO

func _rack_target_at(screen_pos: Vector2) -> Net.Iface:
	for child in slot_box.get_children():
		if child is UIW.RackSlot:
			var candidate: Net.Iface = (child as UIW.RackSlot).port_at_screen(screen_pos)
			if candidate and candidate != rack_cable_from and candidate.dev != rack_cable_from.dev:
				if Game.link_at(candidate) == null:
					return candidate
				if rack_cable_old_link and candidate == rack_cable_old_link.other(rack_cable_from):
					return candidate  # putting the same plug back cancels the move
	return null

func _rack_cable_move(screen_pos: Vector2) -> void:
	rack_cable_layer.move_to(screen_pos, _rack_target_at(screen_pos) != null)

func _rack_cable_release(screen_pos: Vector2) -> void:
	if rack_cable_from == null:
		rack_cable_layer.finish()
		return
	var target := _rack_target_at(screen_pos)
	var original_target: Net.Iface = rack_cable_old_link.other(rack_cable_from) if rack_cable_old_link else null
	rack_cable_layer.finish()
	if target == original_target:
		hud_toast("Plug reseated: %s %s." % [target.dev.name, target.name], true)
	elif target and Game.can_link(rack_cable_from, target):
		if rack_cable_old_link:
			Game.disconnect_iface(rack_cable_from)
		Game.connect_ifaces(rack_cable_from, target)
		hud_toast("Cable run: %s %s ⇄ %s %s" % [rack_cable_from.dev.name,
			rack_cable_from.name, target.dev.name, target.name], true)
		_refresh_slots()
	elif rack_cable_old_link:
		var loose_end := original_target
		Game.disconnect_iface(rack_cable_from)
		hud_toast("Unplugged %s %s from %s %s." % [rack_cable_from.dev.name,
			rack_cable_from.name, loose_end.dev.name, loose_end.name], true)
		_refresh_slots()
	else:
		hud_toast("Drop the cable on a free port in this rack.")
	rack_cable_from = null
	rack_cable_old_link = null

func _pick_new_device(slot: int, at: Control) -> void:
	var keys := Game.MODELS.keys()
	var m := PopupMenu.new()
	m.add_theme_font_override("font", mono)
	for k in keys:
		var mod: Dictionary = Game.MODELS[k]
		var locked: bool = int(mod.get("tier", 0)) > Game.stage
		var height := Game.model_height(k)
		var watts := int(Game.WATTS.get(k, 0))
		var running_cost := "power incl." if Game.stage < 1 else "~$%d/cycle" % int(round(
			float(watts) * Game.efficiency_factor() * Game.energy_rate()))
		var line := "%-24s %-8s %dU %2d ports  $%-4d  %3dW %-12s" % [mod["label"],
			mod["type"], height, mod["ports"], mod["price"], watts, running_cost]
		var fits := Game.can_install(cur_rack, slot, k)
		if locked:
			line += "   🔒 needs %s" % Game.STAGES[int(mod["tier"])]["name"]
		elif not fits:
			line += "   ✋ needs %dU here" % height
		m.add_item(line)
		m.set_item_disabled(m.item_count - 1, locked or not fits)
	add_child(m)
	m.id_pressed.connect(func(id: int) -> void:
		var mod2: Dictionary = Game.MODELS[keys[id]]
		if int(mod2.get("tier", 0)) > Game.stage:
			hud_toast("%s needs the %s stage: expand first." % [mod2["label"],
				Game.STAGES[int(mod2["tier"])]["name"]])
			return
		if not Game.can_install(cur_rack, slot, keys[id]):
			hud_toast("A %s is %dU and will not fit there." % [mod2["label"],
				Game.model_height(keys[id])])
			return
		if not Game.try_spend(mod2["price"]):
			hud_toast("Not enough money for a %s ($%d, you have $%d)." % [mod2["label"],
				int(mod2["price"]), Game.money])
			return
		Game.install_device(cur_rack, slot, Game.new_device(keys[id]))
		cur_rack.visual.queue_redraw()
		_refresh_slots())
	m.popup_hide.connect(m.queue_free)
	m.popup(Rect2i(Vector2i(at.get_screen_position() + Vector2(0, at.size.y + 4)), Vector2i.ZERO))

# ---------- device view ----------

func _build_dev_overlay() -> void:
	dev_overlay = _overlay()
	var v := _card(dev_overlay, 760)
	(v.get_parent().get_parent() as ScrollContainer).set_meta("visible_stack", v)
	dev_title = _header(v, close_dev)
	dev_note_ui = _note_card(v, func(text: String) -> void:
		Game.set_note(cur_dev, text)
		_refresh_note_card(dev_note_ui, cur_dev, dev_note_btn)
		_refresh_ports())

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
	name_row.add_child(_label("   Power:  ", 14, MUTED))
	psu_opt = OptionButton.new()
	for feed in ["A", "B", "AB"]:
		psu_opt.add_item("feed " + feed if feed != "AB" else "both feeds")
	psu_opt.tooltip_text = "Which power feed this device is plugged into"
	psu_opt.item_selected.connect(func(idx: int) -> void:
		var err := Game.set_psu(cur_dev, ["A", "B", "AB"][idx])
		if err != "":
			_toast(err)
		_refresh_dev_header())
	name_row.add_child(psu_opt)
	name_hint = _label("", 13, Color(0.9, 0.5, 0.45))
	name_row.add_child(name_hint)

	v.add_child(_section("FRONT PANEL  /  CLICK A PORT TO INSPECT OR CABLE"))
	var plate := PanelContainer.new()
	var plate_sb := _sb(Color(0.1, 0.11, 0.14), Color(0.4, 0.44, 0.52), 10, 16)
	plate_sb.border_width_top = 3
	plate.add_theme_stylebox_override("panel", plate_sb)
	v.add_child(plate)
	port_row = VBoxContainer.new()
	port_row.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(port_row)
	dev_power_lbl = _label("", 12, UIW.colour("muted"))
	dev_power_lbl.add_theme_font_override("font", mono)
	v.add_child(dev_power_lbl)

	conn_list = VBoxContainer.new()
	v.add_child(conn_list)
	svc_lbl = _label("", 13, Color(0.6, 0.75, 0.65))
	v.add_child(svc_lbl)

	vlan_section = VBoxContainer.new()
	v.add_child(vlan_section)
	vlan_section.add_child(HSeparator.new())
	vlan_section.add_child(_section("OBSERVED VLAN DATABASE  /  CONFIGURE IN CONSOLE"))
	vlan_box = VBoxContainer.new()
	vlan_section.add_child(vlan_box)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	v.add_child(btn_row)
	dev_note_btn = Button.new()
	dev_note_btn.text = "✎ LEAVE NOTE"
	dev_note_btn.tooltip_text = "Leave short handover context on this device"
	dev_note_btn.pressed.connect(func() -> void: _open_note_card(dev_note_ui))
	btn_row.add_child(dev_note_btn)
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
		cap_out.custom_minimum_size.y = 170 if cap_box.visible else 0
		_refresh_capture()
		if cap_box.visible:
			_scroll_to_bottom.call_deferred()
		else:
			_fit_cards.call_deferred())
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
	cap_out.custom_minimum_size = Vector2.ZERO
	cap_out.add_theme_font_override("normal_font", mono)
	cap_out.add_theme_font_size_override("normal_font_size", 12)
	cap_out.add_theme_color_override("default_color", Color(0.75, 0.85, 0.95))
	var cap_bg := PanelContainer.new()
	UIW.style_panel(cap_bg, "console", "sm")
	cap_bg.add_child(cap_out)
	cap_box.add_child(cap_bg)
	cli_box = VBoxContainer.new()
	cli_box.visible = false
	v.add_child(cli_box)
	cli_out = RichTextLabel.new()
	cli_out.custom_minimum_size = Vector2.ZERO
	cli_out.scroll_following = true
	cli_out.add_theme_font_override("normal_font", mono)
	cli_out.add_theme_font_size_override("normal_font_size", 14)
	cli_out.add_theme_color_override("default_color", Color(0.75, 0.95, 0.8))
	var term_bg := PanelContainer.new()
	UIW.style_panel(term_bg, "console", "sm")
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
	_refresh_note_card(dev_note_ui, d, dev_note_btn)
	cli_box.visible = false
	cap_box.visible = false
	cli_out.custom_minimum_size.y = 0
	cap_out.custom_minimum_size.y = 0
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
	psu_opt.select(["A", "B", "AB"].find(cur_dev.psu))
	psu_opt.set_item_disabled(2, not Game.dual_psu(cur_dev))
	psu_opt.tooltip_text = "Two power supplies: it survives either feed failing" \
		if Game.dual_psu(cur_dev) else "One power supply. Spread single-supply gear across both feeds."
	status_opt.disabled = cur_dev.status == "nopower"
	status_opt.tooltip_text = "No power on feed %s. It comes back on its own." % cur_dev.psu \
		if cur_dev.status == "nopower" else "Take the device out of service"
	var watts := int(Game.WATTS.get(cur_dev.model, 0))
	dev_power_lbl.text = ("POWER PROFILE  /  %dW nameplate  /  electricity included in colo lease" % watts
		if Game.stage < 1 else
		"POWER PROFILE  /  %dW nameplate  /  ~$%d per cycle at $%.3f/W" % [watts,
			int(round(float(watts) * Game.efficiency_factor() * Game.energy_rate())),
			Game.energy_rate()])
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
		if i.name.begins_with("Vlan") or i.name.begins_with("Tunnel") \
				or i.name.begins_with("wg") or i.parent != "":
			var b := Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_override("font", mono)
			var kind_lbl := "802.1Q sub" if i.parent != "" else (
				"tunnel" if i.name.begins_with("Tunnel") else (
				"wireguard" if i.name.begins_with("wg") else "SVI"))
			b.text = "  %s (%s)   %s" % [i.name, kind_lbl,
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
		var ports: Array = []
		for i: Net.Iface in cur_dev.ifaces:
			if i.mode == "access" and i.untagged_vlan == vid:
				ports.append(i.name)
		var l := _label("  %-6d %-14s %s" % [vid, cur_dev.vlans[vid], Net.compress_ports(ports)],
			14, Color(0.7, 0.8, 0.9))
		l.add_theme_font_override("font", mono)
		vlan_box.add_child(l)

# ---------- interface editor ----------

func _build_if_overlay() -> void:
	if_overlay = _overlay()
	var v := _card(if_overlay, 600)
	if_title = _header(v, close_iface)
	var eyebrow := _section("PORT INSPECTOR  /  READ-ONLY LOGICAL STATE")
	eyebrow.add_theme_color_override("font_color", UIW.colour("accent"))
	v.add_child(eyebrow)
	if_mac = _label("", 13, MUTED)
	if_mac.add_theme_font_override("font", mono)
	v.add_child(if_mac)
	if_vrrp_lbl = _label("", 13, Color(0.7, 0.85, 0.75))
	if_vrrp_lbl.add_theme_font_override("font", mono)
	v.add_child(if_vrrp_lbl)
	var state_panel := UIW.style_panel(PanelContainer.new(), "console", "lg")
	v.add_child(state_panel)
	if_state_box = VBoxContainer.new()
	if_state_box.add_theme_constant_override("separation", UIW.space("sm"))
	state_panel.add_child(if_state_box)
	var console_note := HBoxContainer.new()
	console_note.add_theme_constant_override("separation", UIW.space("md"))
	v.add_child(console_note)
	var note := _wrap("Addressing, VLANs, MTU and policy are configured at the device console.",
		13, UIW.colour("muted"), 420)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	console_note.add_child(note)
	var console_btn := Button.new()
	console_btn.text = "OPEN DEVICE CONSOLE"
	_accent(console_btn)
	console_btn.pressed.connect(func() -> void:
		if_overlay.visible = false
		if not cli_box.visible:
			_toggle_cli())
	console_note.add_child(console_btn)

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
	for c in if_state_box.get_children():
		c.queue_free()
	if_state_box.add_child(_iface_state_line("LINK STATE",
		"UP / ENABLED" if cur_if.enabled else "ADMINISTRATIVELY DISABLED",
		"success" if cur_if.enabled else "danger"))
	if_state_box.add_child(_iface_state_line("FRAME SIZE", "MTU %d" % cur_if.mtu, "info"))
	if cur_if.dev.type == "switch":
		var switching := "ACCESS  /  VLAN %d" % cur_if.untagged_vlan if cur_if.mode == "access" else \
			"TRUNK  /  %s" % ("ALL VLANS" if cur_if.tagged_vlans.is_empty() else
			", ".join(PackedStringArray(cur_if.tagged_vlans.map(func(v): return str(v)))))
		if_state_box.add_child(_iface_state_line("SWITCHING", switching, "accent"))
	var address_text := "NONE"
	if not cur_if.ips.is_empty():
		address_text = ", ".join(PackedStringArray(cur_if.ips))
	if_state_box.add_child(_iface_state_line("IP ADDRESSES", address_text,
		"success" if not cur_if.ips.is_empty() else "muted"))
	var policies: Array = []
	if cur_if.nat != "": policies.append("NAT %s" % cur_if.nat.to_upper())
	if cur_if.qos: policies.append("QOS")
	if cur_if.port_security: policies.append("PORT SECURITY")
	if_state_box.add_child(_iface_state_line("POLICY",
		" / ".join(PackedStringArray(policies)) if not policies.is_empty() else "NONE", "warm"))
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
		if_cable_btn.text = "Run remote cable…"
		if_cable_btn.tooltip_text = "For devices in this rack, close to the rack view and drag directly between free ports."
		if_peer_btn.visible = false
	else:
		if_cable_lbl.text = "Cable: ⇄  " + peer
		if_cable_btn.text = "Disconnect"
		if_peer_btn.visible = true

func _iface_state_line(caption: String, value: String, semantic: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIW.space("md"))
	var cap := _label(caption, 11, UIW.colour("muted"))
	cap.add_theme_font_override("font", mono)
	cap.custom_minimum_size = Vector2(150, 0)
	row.add_child(cap)
	var val := _label(value, 13, UIW.colour(semantic))
	val.add_theme_font_override("font", mono)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)
	return row

func _cable_action() -> void:
	if Game.link_at(cur_if):
		Game.disconnect_iface(cur_if)
		_refresh_iface()
		return
	var targets: Array = []
	var source_rack := Game.rack_of(cur_if.dev)
	for candidate: Net.Iface in Game.free_ifaces(cur_if.dev):
		if Game.rack_of(candidate.dev) != source_rack:
			targets.append(candidate)
	if targets.is_empty():
		hud_toast("No remote free ports. For this rack, drag a cable between port squares in the rack view.")
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
			ports.size(), Net.compress_ports(names), suffix], sub.name)
		if not linkable:
			root.set_item_disabled(root.item_count - 1, true)
	root.popup(Rect2i(Vector2i(if_cable_btn.get_screen_position() + Vector2(0, if_cable_btn.size.y + 4)), Vector2i.ZERO))

# ---------- encyclopedia ----------

func _build_pedia() -> void:
	pedia_overlay = _overlay()
	var v := _card(pedia_overlay, 980)
	var t := _header(v, func() -> void: pedia_overlay.visible = false)
	t.text = "Network field manual"
	var eyebrow := _section("LEARN  /  REFERENCE  /  COMMAND LAB")
	eyebrow.add_theme_color_override("font_color", UIW.colour("accent"))
	v.add_child(eyebrow)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UIW.space("lg"))
	v.add_child(h)
	var nav_panel := UIW.style_panel(PanelContainer.new(), "console", "lg")
	nav_panel.custom_minimum_size = Vector2(304, 540)
	h.add_child(nav_panel)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", UIW.space("sm"))
	nav_panel.add_child(nav)
	var contents := _section("CHAPTER INDEX")
	contents.add_theme_color_override("font_color", UIW.colour("warm"))
	nav.add_child(contents)
	var topic_scroll := ScrollContainer.new()
	topic_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	topic_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topic_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	topic_scroll.add_theme_constant_override("scrollbar_v_separation", UIW.space("sm"))
	nav.add_child(topic_scroll)
	var topic_gutter := MarginContainer.new()
	topic_gutter.add_theme_constant_override("margin_right", UIW.space("sm"))
	topic_gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topic_scroll.add_child(topic_gutter)
	var topics := VBoxContainer.new()
	topics.add_theme_constant_override("separation", 2)
	topics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topic_gutter.add_child(topics)
	var article_panel := UIW.style_panel(PanelContainer.new(), "surface", "lg")
	article_panel.custom_minimum_size = Vector2(620, 540)
	article_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(article_panel)
	pedia_body = RichTextLabel.new()
	pedia_body.custom_minimum_size = Vector2(560, 490)
	pedia_body.bbcode_enabled = true
	pedia_body.scroll_active = true
	pedia_body.add_theme_font_size_override("normal_font_size", 15)
	pedia_body.add_theme_color_override("default_color", UIW.colour("text"))
	pedia_body.add_theme_constant_override("line_separation", 6)
	article_panel.add_child(pedia_body)
	for topic_i in Pedia.TOPICS.size():
		var entry = Pedia.TOPICS[topic_i]
		var b := Button.new()
		b.text = "%02d   %s" % [topic_i + 1, entry[0]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 12)
		var plain := StyleBoxEmpty.new()
		plain.content_margin_left = UIW.space("sm")
		plain.content_margin_right = UIW.space("sm")
		plain.content_margin_top = UIW.space("sm")
		plain.content_margin_bottom = UIW.space("sm")
		b.add_theme_stylebox_override("normal", plain)
		b.add_theme_stylebox_override("hover", UIW.panel_box("surface", "sm"))
		b.add_theme_stylebox_override("pressed", UIW.panel_box("positive", "sm"))
		b.add_theme_stylebox_override("focus", UIW.panel_box("surface", "sm"))
		b.add_theme_color_override("font_color", UIW.colour("muted"))
		b.add_theme_color_override("font_hover_color", UIW.colour("text_strong"))
		b.add_theme_color_override("font_pressed_color", UIW.colour("success"))
		b.pressed.connect(func() -> void:
			_show_pedia_entry(topic_i))
		topics.add_child(b)
		pedia_topic_buttons.append(b)
	_show_pedia_entry(0)

func _show_pedia_entry(topic_i: int) -> void:
	if topic_i < 0 or topic_i >= Pedia.TOPICS.size():
		return
	var entry = Pedia.TOPICS[topic_i]
	for button_i in pedia_topic_buttons.size():
		(pedia_topic_buttons[button_i] as Button).button_pressed = button_i == topic_i
	pedia_body.clear()
	pedia_body.append_text("[color=#39d9d0]FIELD MANUAL  /  CHAPTER %02d[/color]\n\n" % (topic_i + 1))
	pedia_body.append_text("[font_size=24][b]%s[/b][/font_size]\n\n" % entry[0])
	pedia_body.append_text("%s\n\n" % entry[1])
	pedia_body.append_text("[color=#8da7ba]Use the exact commands above in a device console. The simulation will respond to the configuration, not a scripted answer.[/color]")

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

## Which sections belong on which tab. Everything is still built in one pass;
## the tab only decides what stays visible, which keeps the section code as a
## plain sequence rather than a nest of conditionals.
const OPS_TABS := [
	["Capacity", ["CAPACITY", "POWER", "AIRFLOW"]],
	["Traffic", ["TOP TALKERS", "MONITORS"]],
	["Hardware", ["ASSETS AND SPARES", "DEVICES"]],
	["Automation", ["PLAYBOOKS", "CERTIFICATES"]],
]
var ops_tab := "Capacity"
var ops_tab_btns := {}
var ops_metric_values := {}
var ops_metric_notes := {}

func _build_ops() -> void:
	ops_overlay = _overlay()
	var v := _card(ops_overlay, 900)
	ops_title = _header(v, func() -> void: ops_overlay.visible = false)
	ops_title.text = "Network operations"
	var status_line := _section("LIVE ESTATE  /  CURRENT SHIFT")
	status_line.add_theme_color_override("font_color", UIW.colour("accent"))
	v.add_child(status_line)
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", UIW.space("md"))
	v.add_child(metrics)
	metrics.add_child(_ops_metric("DEVICES", "devices", "info"))
	metrics.add_child(_ops_metric("CABLE PLANT", "links", "accent"))
	metrics.add_child(_ops_metric("ATTENTION", "alerts", "warning"))
	metrics.add_child(_ops_metric("LIVE DRAW", "power", "success"))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", UIW.space("sm"))
	v.add_child(tabs)
	for entry in OPS_TABS:
		var tb := Button.new()
		tb.text = String(entry[0])
		tb.toggle_mode = true
		tb.pressed.connect(func() -> void:
			ops_tab = String(entry[0])
			_refresh_ops())
		tabs.add_child(tb)
		ops_tab_btns[String(entry[0])] = tb
	ops_box = VBoxContainer.new()
	ops_box.add_theme_constant_override("separation", UIW.space("sm"))
	v.add_child(ops_box)

func _ops_metric(caption: String, key: String, semantic: String) -> PanelContainer:
	var panel := UIW.style_panel(PanelContainer.new(), "surface", "md")
	panel.custom_minimum_size = Vector2(196, 104)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIW.space("xs"))
	panel.add_child(box)
	var cap := _section(caption)
	box.add_child(cap)
	var value := _label("—", 22, UIW.colour(semantic))
	value.add_theme_font_override("font", mono)
	box.add_child(value)
	var note := _label("", 11, UIW.colour("muted"))
	note.add_theme_font_override("font", mono)
	box.add_child(note)
	ops_metric_values[key] = value
	ops_metric_notes[key] = note
	return panel

func _ops_sections_for_tab() -> Array:
	for entry in OPS_TABS:
		if String(entry[0]) == ops_tab:
			return entry[1]
	return []

func _apply_ops_tab() -> void:
	## walk what was just built and hide the sections this tab does not own
	var wanted: Array = _ops_sections_for_tab()
	var all_titles: Array = []
	for entry in OPS_TABS:
		for t in entry[1]:
			all_titles.append(String(t))
	var current := ""
	for child in ops_box.get_children():
		if child is Label and String(child.text) in all_titles:
			current = String(child.text)
		if current != "":
			child.visible = current in wanted
	for name in ops_tab_btns:
		ops_tab_btns[name].button_pressed = name == ops_tab

func _refresh_ops() -> void:
	for c in ops_box.get_children():
		ops_box.remove_child(c)
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
	ops_title.text = "Network operations"
	var watts := 0
	for si in Game.site_count():
		watts += int(Game.capacity(si)["watts"])
	(ops_metric_values["devices"] as Label).text = "%02d ONLINE" % devs.size()
	(ops_metric_notes["devices"] as Label).text = "installed estate"
	(ops_metric_values["links"] as Label).text = "%02d / %02d UP" % [Game.links.size() - links_down,
		Game.links.size()]
	(ops_metric_notes["links"] as Label).text = "%d cable%s down" % [links_down,
		"" if links_down == 1 else "s"]
	(ops_metric_values["alerts"] as Label).text = "%02d %s" % [alerting,
		"CLEAR" if alerting == 0 else "OPEN"]
	(ops_metric_notes["alerts"] as Label).text = "device action queue"
	(ops_metric_values["alerts"] as Label).add_theme_color_override("font_color",
		UIW.colour("success") if alerting == 0 else UIW.colour("warning"))
	(ops_metric_values["power"] as Label).text = "%d W" % watts
	(ops_metric_notes["power"] as Label).text = ("included in colo lease" if Game.stage < 1 else
		"$%.3f/W  ·  $%d/cycle" % [Game.energy_rate(), Game.power_bill()])
	ops_box.add_child(_section("CAPACITY"))
	for si in Game.site_count():
		var cap: Dictionary = Game.capacity(si)
		if Game.site_count() > 1:
			ops_box.add_child(_label("  " + Game.site_name(si), 13, ACCENT))
		ops_box.add_child(UIW.Bar.new().setup("  Floor space (racks)",
			int(cap["tiles_used"]), int(cap["tiles"])))
		ops_box.add_child(UIW.Bar.new().setup("  Rack units",
			int(cap["slots_used"]), int(cap["slots"]),
			Game.capacity_runway("slots_used", int(cap["slots_used"]), int(cap["slots"])) if si == 0 else -1))
		ops_box.add_child(UIW.Bar.new().setup("  Switch and server ports",
			int(cap["ports_used"]), int(cap["ports"])))
		if si == 0 and Game.stage >= 1:
			ops_box.add_child(UIW.Bar.new().setup("  Cooling",
				int(cap["watts"]), maxi(1, int(cap["cooling"])),
				Game.capacity_runway("watts", int(cap["watts"]), maxi(1, int(cap["cooling"]))),
				"W"))
		elif si == 0:
			ops_box.add_child(_label("    Power draw %dW; the colo includes cooling."
				% int(cap["watts"]), 12, MUTED))
	var advice := _capacity_advice()
	if advice != "":
		ops_box.add_child(_wrap("  " + advice, 13, Color(1.0, 0.82, 0.5), 780))
	var meter := UIW.style_panel(PanelContainer.new(), "console", "md")
	ops_box.add_child(meter)
	var meter_copy := "COLO POWER INCLUDED  /  Your cost is $0 per watt in this cage. Reference rate for an owned room right now: $%.3f per watt per cycle." % Game.energy_rate()
	if Game.stage >= 1:
		meter_copy = "LIVE METER  /  %dW nameplate → %dW billed after efficiency  ×  $%.3f per watt per cycle  =  $%d next cycle" % [
			Game.power_draw(), Game.effective_draw(), Game.energy_rate(), Game.power_bill()]
	var meter_label := _wrap(meter_copy, 13,
		UIW.colour("warm") if Game.stage >= 1 else UIW.colour("muted"), 780)
	meter_label.add_theme_font_override("font", mono)
	meter.add_child(meter_label)
	if Game.stage >= 1:
		ops_box.add_child(_section("AIRFLOW"))
		var any_hot := false
		for r_air in Game.racks_on(Game.current_site):
			var heat := Game.rack_heat(r_air)
			var cool := Game.rack_cooling(r_air)
			if heat == 0:
				continue
			var hot := heat > cool
			any_hot = any_hot or hot
			var al := _label("  %-10s %5dW produced   %5dW removed   %s" % [r_air.name, heat, cool,
				"HOT" if hot else "ok"], 12,
				Prefs.bad_colour() if hot else Color(0.7, 0.78, 0.85))
			al.add_theme_font_override("font", mono)
			ops_box.add_child(al)
		if any_hot:
			ops_box.add_child(_wrap("  Cold air does not travel far. Put a cooling unit in or beside the hot row, and leave an aisle: cabinets pressed against each other recirculate their own exhaust.",
				12, Color(1.0, 0.82, 0.5), 780))
	var talkers := Game.top_talkers(6)
	if not talkers.is_empty():
		ops_box.add_child(_section("TOP TALKERS"))
		for row: Dictionary in talkers:
			var tl := _label("  %-40s %8d packets" % [row["pair"], int(row["packets"])],
				12, Color(0.72, 0.78, 0.86))
			tl.add_theme_font_override("font", mono)
			ops_box.add_child(tl)
		var clear_btn := Button.new()
		clear_btn.text = "Reset the counters"
		clear_btn.pressed.connect(func() -> void:
			Game.clear_talkers()
			_refresh_ops())
		ops_box.add_child(clear_btn)
	ops_box.add_child(_section("POWER"))
	for si2 in Game.site_count():
		if si2 == 0 and Game.stage < 1:
			ops_box.add_child(_label("  The colo provides power and cooling. Your own room will not.",
				12, MUTED))
			continue
		var f: Dictionary = Game.site_feeds(si2)
		var bits: Array = []
		for letter in ["A", "B"]:
			bits.append("feed %s %s" % [letter, "live" if bool(f[letter]) else "DOWN"])
		if Game.has_ups(si2):
			bits.append("UPS %d/%d cycles" % [int(Game.ups.get(si2, 0)), Game.UPS_CYCLES])
		var pl := _label("  %-22s %s" % [Game.site_name(si2), "   ".join(PackedStringArray(bits))],
			12, Prefs.bad_colour() if (not bool(f["A"]) or not bool(f["B"]))
			else Color(0.7, 0.78, 0.85))
		pl.add_theme_font_override("font", mono)
		ops_box.add_child(pl)
		var exposed: Array = Game.single_feed_exposure(si2)
		var on_a: Array = []
		var on_b: Array = []
		for d3: Net.NDevice in exposed:
			if d3.psu == "A":
				on_a.append(d3.name)
			else:
				on_b.append(d3.name)
		if not exposed.is_empty():
			ops_box.add_child(_wrap("    Single-supply gear: feed A carries %s; feed B carries %s. Losing one feed takes exactly those down."
				% [", ".join(PackedStringArray(on_a)) if not on_a.is_empty() else "nothing",
				", ".join(PackedStringArray(on_b)) if not on_b.is_empty() else "nothing"],
				12, Color(0.8, 0.75, 0.6), 780))
	if Game.stage >= 1 and not Game.has_ups(Game.current_site):
		var ups_btn := Button.new()
		ups_btn.text = "Install a UPS on this floor  ($%d)" % Game.UPS_PRICE
		ups_btn.tooltip_text = "Holds a dead feed up for %d cycles while the utility sorts itself out" % Game.UPS_CYCLES
		ups_btn.pressed.connect(func() -> void:
			var err := Game.buy_ups()
			if err != "":
				_toast(err)
			else:
				hud_toast("UPS installed.", true)
			_refresh_ops())
		ops_box.add_child(ups_btn)
	ops_box.add_child(_section("ASSETS AND SPARES"))
	var shelf: Array = []
	for m in Game.spares:
		if int(Game.spares[m]) > 0:
			shelf.append("%s x%d" % [Game.MODELS[m]["label"], int(Game.spares[m])])
	ops_box.add_child(_label("  On the shelf: %s" % (", ".join(PackedStringArray(shelf))
		if not shelf.is_empty() else "nothing"), 13, Color(0.75, 0.8, 0.85)))
	var spare_btn := Button.new()
	spare_btn.text = "Buy a spare…"
	spare_btn.pressed.connect(func() -> void:
		var models: Array = []
		var opts: Array = []
		var seen_models := {}
		for d in Game.all_devices():
			if seen_models.has(d.model):
				continue
			seen_models[d.model] = true
			models.append(d.model)
			opts.append("%s   $%d" % [Game.MODELS[d.model]["label"],
				int(Game.MODELS[d.model]["price"]) * 3 / 4])
		if opts.is_empty():
			_toast("nothing installed to keep spares for")
			return
		_menu(spare_btn, opts, func(id: int) -> void:
			var err: String = Game.buy_spare(String(models[id]))
			_refresh_ops()
			if err != "":
				_toast(err)))
	ops_box.add_child(spare_btn)
	for d in Game.all_devices():
		if d.status == "active":
			continue
		var frow := HBoxContainer.new()
		ops_box.add_child(frow)
		var fl := _label("  %s (%s) is down, %d cycles old" % [d.name,
			Game.MODELS[d.model]["label"], Game.device_age(d)], 13, Prefs.bad_colour())
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frow.add_child(fl)
		var swap := Button.new()
		swap.text = "Swap from spares"
		swap.pressed.connect(func() -> void:
			var err: String = Game.swap_from_spares(d)
			_refresh_ops()
			if err != "":
				_toast(err))
		frow.add_child(swap)
	ops_box.add_child(_section("PLAYBOOKS"))
	if Game.playbooks.is_empty():
		ops_box.add_child(_wrap("  Nothing saved yet. A playbook is a list of console commands you can run on many devices at once: the same thing you would type, typed for you.",
			12, MUTED, 780))
	for pb: Dictionary in Game.playbooks:
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		ops_box.add_child(prow)
		var pl := _label("  %-22s %d command(s)" % [pb["name"], pb["lines"].size()], 12,
			Color(0.75, 0.82, 0.9))
		pl.add_theme_font_override("font", mono)
		pl.tooltip_text = "\n".join(PackedStringArray(pb["lines"]))
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prow.add_child(pl)
		var run_btn := Button.new()
		run_btn.text = "Run on…"
		run_btn.pressed.connect(func() -> void:
			var opts: Array = []
			var filters: Array = []
			for f in ["all", "switch", "router", "server", "firewall"]:
				var n := Game.playbook_targets(f).size()
				if n == 0:
					continue
				opts.append("every %s (%d device%s)" % [f if f != "all" else "device", n,
					"" if n == 1 else "s"])
				filters.append(f)
			_menu(run_btn, opts, func(id: int) -> void:
				var res := Game.run_playbook(pb, Game.playbook_targets(String(filters[id])))
				hud_toast("Ran '%s' on %d device(s), %d with errors." % [pb["name"],
					int(res["ran"]), int(res["failed"])], int(res["failed"]) == 0)
				_refresh_ops()))
		prow.add_child(run_btn)
		var del_btn := Button.new()
		del_btn.text = "Delete"
		del_btn.pressed.connect(func() -> void:
			Game.delete_playbook(String(pb["name"]))
			_refresh_ops())
		prow.add_child(del_btn)
	var pb_name := _mono_edit(180)
	pb_name.placeholder_text = "playbook name"
	var pb_body := TextEdit.new()
	pb_body.custom_minimum_size = Vector2(560, 90)
	pb_body.placeholder_text = "one command per line, exactly as you would type it at a console"
	pb_body.add_theme_font_override("font", mono)
	pb_body.add_theme_font_size_override("font_size", 12)
	var pb_row := HBoxContainer.new()
	pb_row.add_theme_constant_override("separation", 8)
	ops_box.add_child(pb_row)
	pb_row.add_child(pb_name)
	var pb_save := Button.new()
	pb_save.text = "Save playbook"
	pb_save.pressed.connect(func() -> void:
		var err := Game.save_playbook(pb_name.text, Array(pb_body.text.split("\n")))
		if err != "":
			_toast(err)
		else:
			pb_name.clear()
			pb_body.text = ""
		_refresh_ops())
	pb_row.add_child(pb_save)
	ops_box.add_child(pb_body)
	var certs_due := Game.expiring_certs()
	if not certs_due.is_empty():
		ops_box.add_child(_section("CERTIFICATES"))
		for c_row: Dictionary in certs_due:
			var left: int = int(c_row["left"])
			var crow := HBoxContainer.new()
			crow.add_theme_constant_override("separation", 8)
			ops_box.add_child(crow)
			var cl2 := _label("  %-24s on %-10s %s%s" % [c_row["name"], c_row["dev"].name,
				"EXPIRED" if left <= 0 else "expires in %d cycle(s)" % left,
				"   (renews itself)" if bool(c_row["auto"]) else ""], 12,
				Prefs.bad_colour() if left <= 0 else Color(1.0, 0.8, 0.5))
			cl2.add_theme_font_override("font", mono)
			cl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			crow.add_child(cl2)
			if not bool(c_row["auto"]):
				var renew := Button.new()
				renew.text = "Renew"
				renew.pressed.connect(func() -> void:
					Game.issue_cert(c_row["dev"], String(c_row["name"]))
					_refresh_ops())
				crow.add_child(renew)
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
	_apply_ops_tab()

func _capacity_advice() -> String:
	## one sentence, and only when there is something worth saying
	var cap := Game.capacity(0)
	if int(cap["tiles_used"]) >= int(cap["tiles"]):
		return "No floor tiles left. Expanding to the next stage is the only way to add racks."
	if int(cap["slots"]) > 0 and int(cap["slots_used"]) >= int(cap["slots"]):
		return "Every rack unit is full. Buy another rack before the next contract needs hardware."
	if Game.overheating():
		return "You are drawing more heat than you can remove. Install a CRAC unit or things start tripping."
	var runway := Game.capacity_runway("slots_used", int(cap["slots_used"]), int(cap["slots"]))
	if runway >= 0 and runway <= 6:
		return "At the rate you have been filling them, you run out of rack units in about %d cycles. A rack costs $%d." % [runway, Game.RACK_PRICE]
	return ""

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
		["drag rack ports", "pull a cable between two devices in the same cabinet"],
		["click port", "inspect its state or arrange a remote cable run"],
		["Esc", "back one level"],
		["CONSOLE", ""],
		["configuration", "addresses, VLANs, routing and policy live here"],
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
	var save_as := Button.new()
	save_as.text = "Save to slot…"
	save_as.pressed.connect(func() -> void:
		var opts: Array = []
		for i in Game.SLOTS:
			var info := Game.slot_info(i)
			opts.append("Slot %d: %s" % [i + 1, "empty" if info.get("empty", true)
				else "%s, cycle %d" % [info["company"], int(info["cycle"])]])
		_menu(save_as, opts, func(id: int) -> void:
			Game.current_slot = id
			Game.save_game()
			hud_toast("Saved to slot %d." % (id + 1), true)))
	v.add_child(save_as)
	var title_btn := Button.new()
	title_btn.text = "Save and return to title"
	title_btn.pressed.connect(func() -> void:
		Game.save_game()
		menu_overlay.visible = false
		get_parent().show_title())
	v.add_child(title_btn)
	var scen_btn := Button.new()
	scen_btn.text = "Scenarios…"
	scen_btn.tooltip_text = "Authored situations to work through; your own datacenter waits for you"
	scen_btn.pressed.connect(func() -> void:
		var opts: Array = []
		for sc: Dictionary in Scenarios.all():
			opts.append("%s: %s" % [sc["name"], sc["blurb"]])
		_menu(scen_btn, opts, func(id: int) -> void:
			menu_overlay.visible = false
			Scenarios.start(Scenarios.all()[id])
			get_parent().rebuild_racks()
			_show_scenario_banner()))
	v.add_child(scen_btn)
	var sandbox_btn := Button.new()
	sandbox_btn.text = "Sandbox mode"
	sandbox_btn.tooltip_text = "Free hardware, no bills, no events: somewhere to try an idea"
	sandbox_btn.pressed.connect(func() -> void:
		Game.sandbox = not Game.sandbox
		Game.log_event("SANDBOX: %s." % ("on, nothing costs anything" if Game.sandbox
			else "off, the business is running again"))
		menu_overlay.visible = false
		hud_toast("Sandbox mode %s." % ("on" if Game.sandbox else "off"), Game.sandbox)
		_refresh_money())
	v.add_child(sandbox_btn)
	var prefs_btn := Button.new()
	prefs_btn.text = "Settings…"
	prefs_btn.pressed.connect(func() -> void:
		_menu(prefs_btn, [
			"Fullscreen: %s" % ("on" if Prefs.fullscreen else "off"),
			"Interface scale: %d%%" % int(Prefs.ui_scale * 100),
			"Colourblind-friendly status colours: %s" % ("on" if Prefs.colourblind else "off"),
			"Sound: %s" % ("on" if Prefs.sound else "off"),
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
				3:
					Prefs.sound = not Prefs.sound
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

# ---------- scenarios ----------

var scenario_panel: PanelContainer
var scenario_box: VBoxContainer

func _show_scenario_banner() -> void:
	if scenario_panel == null:
		scenario_panel = PanelContainer.new()
		scenario_panel.theme = theme_res
		scenario_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
		scenario_panel.position = Vector2(-280, 70)
		scenario_panel.custom_minimum_size = Vector2(560, 0)
		scenario_panel.add_theme_stylebox_override("panel",
			_sb(Color(0.08, 0.11, 0.14, 0.96), ACCENT * Color(1, 1, 1, 0.7), 8, 12))
		add_child(scenario_panel)
		scenario_box = VBoxContainer.new()
		scenario_box.add_theme_constant_override("separation", 5)
		scenario_panel.add_child(scenario_box)
	for c in scenario_box.get_children():
		c.queue_free()
	var sc: Dictionary = Scenarios.active
	if sc.is_empty():
		scenario_panel.visible = false
		return
	scenario_box.add_child(_label("SCENARIO: %s" % sc["name"], 16, Color(0.7, 0.9, 1.0)))
	var blurb := _label(sc["blurb"], 13, Color(0.78, 0.82, 0.88))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(520, 0)
	scenario_box.add_child(blurb)
	for g in sc["goals"]:
		var ok: bool = g["t"].call()
		scenario_box.add_child(_label("   %s  %s" % ["●" if ok else "○", g["d"]], 13,
			Prefs.ok_colour() if ok else Color(0.7, 0.7, 0.75)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	scenario_box.add_child(row)
	var check_btn := Button.new()
	check_btn.text = "Check"
	_accent(check_btn)
	check_btn.pressed.connect(func() -> void:
		if Scenarios.solved():
			var nm: String = Scenarios.active["name"]
			Scenarios.finish(true)
			get_parent().rebuild_racks()
			scenario_panel.visible = false
			hud_toast("Scenario passed: %s" % nm, true)
		else:
			_show_scenario_banner())
	row.add_child(check_btn)
	var leave_btn := Button.new()
	leave_btn.text = "Leave scenario"
	leave_btn.pressed.connect(func() -> void:
		Scenarios.finish(false)
		get_parent().rebuild_racks()
		scenario_panel.visible = false)
	row.add_child(leave_btn)
	scenario_panel.visible = true

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
	tutorial_panel = UIW.CommandPanel.new().setup("console", "warm", UIW.space("lg"))
	tutorial_panel.theme = theme_res
	tutorial_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tutorial_panel.position = Vector2(-380, 112)
	tutorial_panel.custom_minimum_size = Vector2(356, 0)
	add_child(tutorial_panel)
	tutorial_box = VBoxContainer.new()
	tutorial_box.add_theme_constant_override("separation", UIW.space("sm"))
	tutorial_panel.add_child(tutorial_box)
	_refresh_tutorial()

var tutorial_hidden := false

func _next_job() -> Dictionary:
	for c in Contracts.all():
		if c["id"] not in Game.contracts_done:
			return c
	return {}

func _refresh_tutorial() -> void:
	if tutorial_panel == null:
		return
	if tutorial_hidden:
		tutorial_panel.visible = false
		return
	if "rackup" in Game.contracts_done:
		# past the opening steps, the panel becomes a live checklist for
		# whatever job is currently open, so there is always a next thing
		var job := _next_job()
		if job.is_empty():
			tutorial_panel.visible = false
			return
		tutorial_panel.visible = true
		for c2 in tutorial_box.get_children():
			c2.queue_free()
		tutorial_box.add_child(_tutorial_head(String(job["title"]).to_upper()))
		for rq in job["reqs"]:
			var rq_ok: bool = rq["t"].call()
			var rl := _label("%s  %s" % ["●" if rq_ok else "○", rq["d"]], 13,
				Color(0.5, 0.9, 0.6) if rq_ok else Color(0.68, 0.72, 0.8))
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.custom_minimum_size = Vector2(290, 0)
			tutorial_box.add_child(rl)
		var open_btn := Button.new()
		open_btn.text = "Open the brief"
		open_btn.pressed.connect(open_contracts)
		tutorial_box.add_child(open_btn)
		return
	tutorial_panel.visible = true
	for c in tutorial_box.get_children():
		c.queue_free()
	tutorial_box.add_child(_tutorial_head("GETTING STARTED"))
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

func _tutorial_head(text: String) -> Control:
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 5)
	var eyebrow := _label("LIVE BRIEF  /  NEXT OBJECTIVE", 10, UIW.colour("warm"))
	eyebrow.add_theme_font_override("font", mono)
	shell.add_child(eyebrow)
	var h := HBoxContainer.new()
	shell.add_child(h)
	var sec := _section(text)
	sec.add_theme_font_size_override("font_size", 14)
	sec.add_theme_color_override("font_color", UIW.colour("text_strong"))
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sec)
	var x := Button.new()
	x.text = "×"
	x.tooltip_text = "Hide this panel for now"
	x.flat = true
	x.pressed.connect(func() -> void:
		tutorial_hidden = true
		_refresh_tutorial())
	h.add_child(x)
	return shell

# ---------- welcome ----------

func _build_welcome() -> void:
	welcome_overlay = _overlay()
	var v := _card(welcome_overlay, 680)
	var t := _header(v, func() -> void: welcome_overlay.visible = false)
	t.text = "Your first night on the floor"
	welcome_overlay.set_meta("title_label", t)
	var shift := _section("SHIFT 01  /  LEGACY COLO  /  02:13")
	shift.add_theme_color_override("font_color", UIW.colour("warm"))
	v.add_child(shift)
	var body := _wrap("One borrowed cage. Questionable wiring. Enough cash for one rack. Turn this forgotten corner into a network people can depend on.", 17,
		UIW.colour("text_strong"), 620)
	welcome_overlay.set_meta("body_label", body)
	v.add_child(body)

	var modules := HBoxContainer.new()
	modules.add_theme_constant_override("separation", UIW.space("md"))
	v.add_child(modules)
	modules.add_child(_welcome_module("01", "READ THE ROOM",
		"Drag to pan. Scroll to zoom. Every cable and blinking port is part of the simulation.", "info"))
	modules.add_child(_welcome_module("02", "BUILD FOR REAL",
		"Place a rack, install hardware, then wire ports. Cheap PacketTik gear speaks RouterOS.", "warm"))
	modules.add_child(_welcome_module("03", "KEEP IT ALIVE",
		"Contracts fund the floor. Diagnose failures at the console and earn the next expansion.", "success"))

	var tip := UIW.style_panel(PanelContainer.new(), "console", "md")
	v.add_child(tip)
	var tip_row := HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", UIW.space("md"))
	tip.add_child(tip_row)
	var prompt := _label(">", 20, UIW.colour("accent"))
	prompt.add_theme_font_override("font", mono)
	tip_row.add_child(prompt)
	var tip_copy := _wrap("The live brief stays on the right. It gives you the next objective without solving the network for you.",
		13, UIW.colour("muted"), 560)
	tip_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_row.add_child(tip_copy)

	var go := Button.new()
	go.text = "CLOCK IN  ·  OPEN FIRST CONTRACT"
	_accent(go)
	go.pressed.connect(func() -> void:
		welcome_overlay.visible = false
		open_contracts())
	v.add_child(go)

func _welcome_module(number: String, title: String, copy: String, semantic: String) -> PanelContainer:
	var card := UIW.style_panel(PanelContainer.new(), "surface", "md")
	card.custom_minimum_size = Vector2(196, 154)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIW.space("sm"))
	card.add_child(box)
	var number_label := _label(number, 20, UIW.colour(semantic))
	number_label.add_theme_font_override("font", mono)
	box.add_child(number_label)
	var heading := _label(title, 12, UIW.colour("text_strong"))
	heading.add_theme_font_override("font", mono)
	box.add_child(heading)
	var copy_label := _wrap(copy, 13, UIW.colour("muted"), 164)
	copy_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(copy_label)
	return card

func show_welcome() -> void:
	if Demo.active():
		var head := welcome_overlay.get_meta("title_label") as Label
		if head != null:
			head.text = "Your first night on the floor"
		var body := welcome_overlay.get_meta("body_label") as Label
		if body != null:
			body.text = "Six contracts. One tired colo cage. About half an hour to prove you can turn cheap hardware into a network people trust."
	_show_overlay(welcome_overlay)

# ---------- demo ----------

var demo_overlay: Control

func _build_demo_end() -> void:
	demo_overlay = _overlay()
	var v := _card(demo_overlay, 760)
	var t := _header(v, func() -> void: demo_overlay.visible = false)
	t.text = "Shift complete"
	var status := _section("OPENING ARC  /  NETWORK ONLINE  /  HANDOVER READY")
	status.add_theme_color_override("font_color", UIW.colour("success"))
	v.add_child(status)
	var body := _wrap("You walked into an empty cage. You leave behind a routed, redundant tenant network—and every packet reached its destination for a real reason.",
		17, UIW.colour("text_strong"), 700)
	v.add_child(body)
	var achieved := HBoxContainer.new()
	achieved.add_theme_constant_override("separation", UIW.space("md"))
	v.add_child(achieved)
	achieved.add_child(_welcome_module("✓", "YOU BUILT",
		"Two switches, isolated tenants, a resilient core and two offices routed together.", "success"))
	achieved.add_child(_welcome_module("✓", "YOU OPERATED",
		"Real MAC learning, VLAN tagging, spanning tree and longest-prefix routing.", "accent"))
	achieved.add_child(_welcome_module("→", "NEXT SHIFT",
		"Own the room. Pay for power. Hire a crew. Reach the internet—and survive it.", "warm"))
	var beyond := UIW.style_panel(PanelContainer.new(), "console", "md")
	v.add_child(beyond)
	var beyond_copy := _wrap("FULL CAMPAIGN  /  DHCP · DNS · NAT · BGP · IPv6 · OSPF · VRRP · MLAG · WIREGUARD · 802.1X · MULTI-SITE WAN",
		12, UIW.colour("muted"), 700)
	beyond_copy.add_theme_font_override("font", mono)
	beyond.add_child(beyond_copy)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIW.space("sm"))
	v.add_child(row)
	var keep := Button.new()
	keep.text = "STAY ON THE FLOOR"
	keep.tooltip_text = "The world stays exactly as it is; nothing new unlocks"
	keep.pressed.connect(func() -> void: demo_overlay.visible = false)
	_accent(keep)
	row.add_child(keep)
	var back := Button.new()
	back.text = "RETURN TO TITLE"
	back.pressed.connect(func() -> void:
		Game.save_game()
		demo_overlay.visible = false
		get_parent().show_title())
	row.add_child(back)

var _demo_end_shown := false

func check_demo_end() -> void:
	if not Demo.complete() or _demo_end_shown:
		return
	_demo_end_shown = true
	_show_overlay(demo_overlay)

# ---------- contracts ----------

var contracts_tab := "Jobs"
var log_filter := "all"
var replay_for := -1  # which incident's timeline is expanded

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
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	var semantic := "info"
	if col.r > col.g * 1.2:
		semantic = "danger"
	elif col.g > col.r * 1.2:
		semantic = "success"
	elif col.r > 0.7 and col.g > 0.5:
		semantic = "warning"
	return UIW.make_chip(text, semantic)

func _chip_row(chip_text: String, chip_col: Color, text: String, size: int, col: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(_chip(chip_text, chip_col))
	h.add_child(_label(text, size, col))
	return h

func _build_business_tab() -> void:
	contracts_box.add_child(_section("RECEIVABLES"))
	var owed := Game.receivables()
	var late := Game.overdue_invoices()
	contracts_box.add_child(_wrap(
		"Owed to you: $%d across %d invoice(s).%s" % [owed, Game.invoices.size(),
			"  %d of them are overdue." % late.size() if not late.is_empty() else ""],
		13, Prefs.bad_colour() if not late.is_empty() else Color(0.75, 0.82, 0.9), 560))
	if Game.invoices.is_empty():
		contracts_box.add_child(UIW.make_empty_state(
			"Nothing outstanding: everything you have billed has been paid."))
	for inv: Dictionary in Game.invoices.slice(0, 8):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		contracts_box.add_child(row)
		var due_in: int = int(inv["due"]) - Game.cycle
		var state := "overdue by %d" % -due_in if due_in < 0 else \
			("due now" if due_in == 0 else "due in %d" % due_in)
		var il := _label("  %-18s $%-7d %s" % [inv["customer"], int(inv["amount"]), state], 12,
			Prefs.bad_colour() if due_in < 0 else Color(0.72, 0.78, 0.86))
		il.add_theme_font_override("font", mono)
		row.add_child(il)
		if due_in <= 0 and not bool(inv["chased"]):
			var chase := Button.new()
			chase.text = "Chase"
			chase.tooltip_text = "They pay on the next cycle, and think slightly less of you for it"
			chase.pressed.connect(func() -> void:
				var err := Game.chase_invoice(inv)
				if err != "":
					_toast(err)
				_refresh_contracts())
			row.add_child(chase)
	if Game.invoices.size() > 8:
		contracts_box.add_child(_label("  ...and %d more." % (Game.invoices.size() - 8), 12, MUTED))
	contracts_box.add_child(_section("ENERGY AND THE BOOKS"))
	if Game.stage >= 1:
		contracts_box.add_child(_wrap(
			"Drawing %dW of a nameplate %dW. The %s rate is $%.3f per watt per cycle, so the next bill is $%d. Electricity is dearest exactly when your customers are busiest."
			% [Game.effective_draw(), Game.power_draw(),
				"fixed" if Game.fixed_tariff else "spot", Game.energy_rate(), Game.power_bill()],
			13, Color(0.75, 0.82, 0.9), 560))
		var e_row := HBoxContainer.new()
		e_row.add_theme_constant_override("separation", 8)
		contracts_box.add_child(e_row)
		var tariff_btn := Button.new()
		tariff_btn.text = "Switch to a spot tariff" if Game.fixed_tariff \
			else "Switch to a fixed tariff"
		tariff_btn.tooltip_text = "Fixed costs more on average and does not care what time it is."
		tariff_btn.pressed.connect(func() -> void:
			Game.set_fixed_tariff(not Game.fixed_tariff)
			_refresh_contracts())
		e_row.add_child(tariff_btn)
		var eff_btn := Button.new()
		eff_btn.text = "Efficiency retrofit  ($%d)" % (Game.EFFICIENCY_PRICE + Game.efficiency * 800)
		eff_btn.tooltip_text = "Removes %d%% of your draw, permanently." % int(Game.EFFICIENCY_STEP * 100.0)
		eff_btn.pressed.connect(func() -> void:
			var err := Game.buy_efficiency()
			if err != "":
				_toast(err)
			_refresh_contracts())
		e_row.add_child(eff_btn)
	else:
		contracts_box.add_child(_label("  The colo pays for power. Your own room will not.", 12, MUTED))
	contracts_box.add_child(_wrap(
		"This quarter: profit $%d, depreciation allowance $%d, tax as it stands $%d."
		% [Game.quarter_profit, Game.quarter_depreciation, Game.tax_due()],
		13, Color(0.75, 0.82, 0.9), 560))
	var acc_btn := Button.new()
	acc_btn.text = "Dismiss the accountant" if Game.accountant \
		else "Put an accountant on retainer  ($%d/cycle)" % Game.ACCOUNTANT_FEE
	acc_btn.tooltip_text = "Without one, only half your depreciation allowance is ever claimed."
	acc_btn.pressed.connect(func() -> void:
		Game.hire_accountant(not Game.accountant)
		_refresh_contracts())
	contracts_box.add_child(acc_btn)
	contracts_box.add_child(_section("ADDRESS SPACE"))
	contracts_box.add_child(_wrap(
		"You hold %d public IPv4 addresses and %d are spoken for. Customers who do not insist on one of their own sit behind shared translation and cost you nothing."
		% [Game.ipv4_total(), Game.ipv4_used()], 13,
		Prefs.bad_colour() if Game.ipv4_free() <= 0 else Color(0.75, 0.82, 0.9), 560))
	var ip_btn := Button.new()
	ip_btn.text = "Buy another /29  ($%d)" % Game.ipv4_price()
	ip_btn.tooltip_text = "Eight more addresses. The price goes up every time, because it does."
	ip_btn.pressed.connect(func() -> void:
		var err := Game.buy_ipv4_block()
		if err != "":
			_toast(err)
		_refresh_contracts())
	contracts_box.add_child(ip_btn)
	contracts_box.add_child(_section("TRANSIT AND PEERING"))
	var billed := Game.transit_billed_mbps()
	contracts_box.add_child(_wrap(
		"Transit is billed on the 95th percentile, not the average: right now %d Mbps at $%.2f per Mbps, which is $%d a cycle. Bursting is free five percent of the time; sustained traffic is not."
		% [billed, Game.TRANSIT_PER_MBPS, Game.transit_cost()], 13, Color(0.75, 0.82, 0.9), 560))
	if bool(Game.ixp.get("joined", false)):
		contracts_box.add_child(_label("  At the exchange: %d peering session(s), %d%% of traffic off transit, $%d/cycle port."
			% [int(Game.ixp.get("peers", 0)), int(Game.peering_share() * 100.0), Game.IXP_PORT_FEE],
			13, Color(0.65, 0.88, 0.72)))
		var peer_btn := Button.new()
		peer_btn.text = "Approach another network to peer with"
		peer_btn.pressed.connect(func() -> void:
			var err := Game.add_peering()
			if err != "":
				_toast(err)
			_refresh_contracts())
		contracts_box.add_child(peer_btn)
	else:
		var ixp_btn := Button.new()
		ixp_btn.text = "Take a port at the internet exchange  ($%d, then $%d/cycle)" % [
			Game.IXP_SETUP, Game.IXP_PORT_FEE]
		ixp_btn.tooltip_text = "Settlement-free peering. It only pays for itself past a certain volume, which is the decision."
		ixp_btn.pressed.connect(func() -> void:
			var err := Game.join_ixp()
			if err != "":
				_toast(err)
			_refresh_contracts())
		contracts_box.add_child(ixp_btn)
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
	contracts_box.add_child(_section("MARKETING AND COVER"))
	var mk_row := HBoxContainer.new()
	contracts_box.add_child(mk_row)
	mk_row.add_child(_label("  Marketing $%d/cycle   ·   more and better enquiries" % Game.marketing,
		13, Color(0.8, 0.85, 0.7) if Game.marketing > 0 else Color(0.75, 0.75, 0.8)))
	var mk_up := Button.new()
	mk_up.text = "Spend more"
	mk_up.pressed.connect(func() -> void:
		Game.marketing += Game.MARKETING_STEP
		_refresh_contracts())
	mk_row.add_child(mk_up)
	if Game.marketing > 0:
		var mk_down := Button.new()
		mk_down.text = "Cut back"
		mk_down.pressed.connect(func() -> void:
			Game.marketing = maxi(0, Game.marketing - Game.MARKETING_STEP)
			_refresh_contracts())
		mk_row.add_child(mk_down)
	var ins_row := HBoxContainer.new()
	contracts_box.add_child(ins_row)
	ins_row.add_child(_label("  Hardware insurance: %s   ($%d/cycle, pays half a replacement)" % [
		"ON" if Game.insured else "off", Game.INSURANCE_FEE], 13,
		Color(0.7, 0.9, 0.7) if Game.insured else Color(0.75, 0.75, 0.8)))
	var ins_btn := Button.new()
	ins_btn.text = "Cancel" if Game.insured else "Take cover"
	ins_btn.pressed.connect(func() -> void:
		Game.insured = not Game.insured
		_refresh_contracts())
	ins_row.add_child(ins_btn)
	contracts_box.add_child(_section("CHANGE MANAGEMENT"))
	var maint_row := HBoxContainer.new()
	contracts_box.add_child(maint_row)
	maint_row.add_child(_label("  %s   (%d of 2 windows used this quarter)" % [
		("Maintenance window open until cycle %d" % Game.maintenance_until) if Game.in_maintenance()
		else "No window open: downtime counts against your service levels",
		Game.maintenance_used], 13,
		Color(0.7, 0.9, 0.7) if Game.in_maintenance() else Color(0.75, 0.75, 0.8)))
	var maint_btn := Button.new()
	maint_btn.text = "Declare a window"
	maint_btn.tooltip_text = "Planned downtime in a window is excused by your customers"
	maint_btn.pressed.connect(func() -> void:
		var err: String = Game.declare_maintenance()
		_refresh_contracts()
		if err != "":
			_toast(err))
	maint_row.add_child(maint_btn)
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
	if not Game.reports.is_empty():
		contracts_box.add_child(_section("QUARTERLY REPORTS"))
		for rep: Dictionary in Game.reports.slice(0, 4):
			var rl := _label("  Q%-3d cash $%-8d net %s$%-7d %d customers · %d%% delivered · %d staff · %s" % [
				int(rep["quarter"]), int(rep["money"]),
				"+" if int(rep["net"]) >= 0 else "-", absi(int(rep["net"])),
				int(rep["deals"]), int(rep["uptime"]), int(rep["staff"]), rep["rank"]],
				12, Color(0.72, 0.8, 0.88))
			rl.add_theme_font_override("font", mono)
			contracts_box.add_child(rl)
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
	if not Game.staff.is_empty() and not Staff.anyone_on_shift():
		contracts_box.add_child(_wrap("  Nobody is on shift right now (it is %s). Whatever breaks in the next few cycles waits until somebody clocks on."
			% Game.day_name(), 13, Color(1.0, 0.8, 0.5), 560))
	for m: Dictionary in Game.staff.duplicate():
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 6)
		contracts_box.add_child(srow)
		var under: bool = int(m["salary"]) < Staff.market_rate(m)
		var busy: int = int(m.get("training_left", 0))
		var state := "on a course, %d cycle(s) left" % busy if busy > 0 else \
			("on shift" if Staff.on_shift(m) else "off shift")
		var sl := _label("  %-16s %-16s skill %d  $%d/cycle  morale %d  %s%s" % [m["name"],
			Staff.label(m), int(m["skill"]), int(m["salary"]), int(m.get("morale", 70)),
			state, "  (under market)" if under else ""], 12,
			Prefs.bad_colour() if int(m.get("morale", 70)) < 30 else Color(0.78, 0.85, 0.8))
		sl.add_theme_font_override("font", mono)
		sl.tooltip_text = "%s\nShift: %s\nMarket rate: $%d\nCertifications: %s" % [
			Staff.ROLES[m["role"]]["blurb"], Staff.SHIFTS[Staff.shift_of(m)]["label"],
			Staff.market_rate(m),
			", ".join(PackedStringArray(m.get("certs", []))) if not m.get("certs", []).is_empty()
			else "none"]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		srow.add_child(sl)
		var shift_btn := Button.new()
		shift_btn.text = Staff.SHIFTS[Staff.shift_of(m)]["label"]
		shift_btn.tooltip_text = "Which part of the day they cover. Nights cost a premium."
		shift_btn.pressed.connect(func() -> void:
			Staff.set_shift(m, "night" if Staff.shift_of(m) == "day" else "day")
			_refresh_contracts())
		srow.add_child(shift_btn)
		var raise_btn := Button.new()
		raise_btn.text = "Raise"
		raise_btn.tooltip_text = "Ten percent. Cheaper than replacing them."
		raise_btn.pressed.connect(func() -> void:
			Staff.give_raise(m, maxi(20, int(m["salary"]) / 10))
			_refresh_contracts())
		srow.add_child(raise_btn)
		var train_btn := Button.new()
		train_btn.text = "Train…"
		train_btn.disabled = busy > 0
		train_btn.pressed.connect(func() -> void:
			var opts: Array = []
			var keys: Array = []
			for course in Staff.COURSES:
				var c: Dictionary = Staff.COURSES[course]
				opts.append("%s   $%d, %d cycles off the floor" % [c["label"], int(c["cost"]),
					int(c["cycles"])])
				keys.append(course)
			_menu(train_btn, opts, func(id: int) -> void:
				var err := Staff.start_course(m, String(keys[id]))
				if err != "":
					_toast(err)
				_refresh_contracts()))
		srow.add_child(train_btn)
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
			opts.append("%-18s %-18s skill %d   asking $%d/cycle%s" % [c["name"], Staff.label(c),
				int(c["skill"]), int(c["ask"]),
				"   (they countered: $%d)" % int(c["counter"]) if c.has("counter") else ""])
		if opts.is_empty():
			_toast("no candidates right now: the market refreshes every few cycles")
			return
		_menu(hire_btn, opts, func(id: int) -> void:
			var cand: Dictionary = Game.candidates[id]
			# offer nine tenths of what they asked for and see what happens
			var offered := int(float(int(cand["ask"])) * 0.9)
			var res := Game.offer_job(cand, offered)
			_refresh_contracts()
			if res == "counter":
				_toast("%s says $%d and not a forint less." % [cand["name"],
					int(cand.get("counter", cand["ask"]))])
			elif res == "walked":
				_toast("%s took another offer." % cand["name"])
			elif res == "":
				hud_toast("%s starts at $%d/cycle." % [cand["name"], int(cand["salary"])], true)
			else:
				_toast(res)))
	contracts_box.add_child(hire_btn)
	contracts_box.add_child(_section("SITES"))
	for i in Game.site_count():
		var rent := int(Game.sites[i].get("rent", 0))
		contracts_box.add_child(_label("  %-24s %-11s %dx%d   %d racks%s" % [Game.site_name(i),
			Game.site_city(i), Game.grid_size(i).x, Game.grid_size(i).y, Game.racks_on(i).size(),
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
			var carrier_name := String(c.get("carrier", "?"))
			var carrier_ok := Game.carrier_up(carrier_name)
			var cl := _label("  %s: %s ⇄ %s   %s   $%d/cycle%s" % [c["label"],
				Game.site_name(int(c["a"])), Game.site_name(int(c["b"])), carrier_name,
				int(c["fee"]), "" if carrier_ok else "   CARRIER OUTAGE"],
				13, Color(0.7, 0.85, 0.9) if carrier_ok else Prefs.bad_colour())
			cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			crow.add_child(cl)
			var cancel := Button.new()
			cancel.text = "Cancel"
			cancel.tooltip_text = "Ends the circuit and any cables riding it"
			cancel.pressed.connect(func() -> void:
				Game.cancel_circuit(c)
				_refresh_contracts())
			crow.add_child(cancel)
		for i2 in Game.site_count():
			for j2 in range(i2 + 1, Game.site_count()):
				var route := Game.circuits_between(i2, j2)
				if route.size() >= 2 and not Game.carrier_diverse(i2, j2):
					contracts_box.add_child(_wrap(
						"  %s ⇄ %s has two circuits from the same carrier. That is one bad afternoon away from being no circuits at all."
						% [Game.site_name(i2), Game.site_name(j2)], 12, Color(1.0, 0.8, 0.5), 560))
				elif Game.carrier_diverse(i2, j2):
					contracts_box.add_child(_label(
						"  %s ⇄ %s is carrier diverse." % [Game.site_name(i2), Game.site_name(j2)],
						12, Color(0.6, 0.88, 0.7)))
		var order := Button.new()
		order.text = "Order a circuit…"
		order.pressed.connect(func() -> void:
			var pairs: Array = []
			var combos: Array = []
			for i in Game.site_count():
				for j in range(i + 1, Game.site_count()):
					var taken := {}
					for have: Dictionary in Game.circuits_between(i, j):
						taken[String(have.get("carrier", ""))] = true
					for carrier: String in Game.CARRIERS:
						if taken.has(carrier):
							continue
						for g in Game.CIRCUIT_GRADES.size():
							var gr: Dictionary = Game.CIRCUIT_GRADES[g]
							pairs.append("%s ⇄ %s (%d km)   %s   %s   $%d install, $%d/cycle" % [
								Game.site_name(i), Game.site_name(j),
								int(Game.site_distance_km(i, j)), carrier, gr["label"],
								int(gr["setup"]), int(gr["fee"])])
							combos.append([i, j, g, carrier])
			if pairs.is_empty():
				_toast("every carrier already runs a circuit on every route")
				return
			_menu(order, pairs, func(id: int) -> void:
				var pick: Array = combos[id]
				var err: String = Game.buy_circuit(int(pick[0]), int(pick[1]), int(pick[2]),
					String(pick[3]))
				_refresh_contracts()
				if err != "":
					_toast(err)))
		contracts_box.add_child(order)
	# (market moved to its own tab)

func _build_market_tab() -> void:
	if not Game.references.is_empty():
		contracts_box.add_child(_wrap("Willing to be a reference: %s. Customers who have been happy for a long time are worth more than any advertising."
			% ", ".join(PackedStringArray(Game.references)), 13, Color(0.65, 0.88, 0.72), 560))
	if Game.market_intel == 0:
		contracts_box.add_child(_label("You have no read on competitor pricing yet: lose a bid and you will learn.",
			13, Color(0.6, 0.62, 0.7)))
	else:
		contracts_box.add_child(_label("Market intelligence from %d observed bid(s)." % Game.market_intel,
			13, Color(0.65, 0.85, 0.6)))
	if not Game.buyout_offer.is_empty():
		contracts_box.add_child(_section("AN APPROACH"))
		contracts_box.add_child(_wrap(
			"%s would like to buy your company for $%d. They will wait %d more cycle(s). Your book, hardware and premises are worth about $%d on paper."
			% [Game.buyout_offer["rival"], int(Game.buyout_offer["price"]),
				int(Game.buyout_offer["ttl"]), Rivals.player_valuation()],
			14, Color(1.0, 0.85, 0.55), 560))
		var bo_row := HBoxContainer.new()
		bo_row.add_theme_constant_override("separation", 8)
		contracts_box.add_child(bo_row)
		var take := Button.new()
		take.text = "Sell the company"
		take.tooltip_text = "It ends here, with the money and the score you have earned."
		take.pressed.connect(func() -> void:
			_menu(take, ["Yes. Take the money and walk."], func(_id: int) -> void:
				Game.accept_buyout()
				_refresh_contracts()))
		bo_row.add_child(take)
		var refuse := Button.new()
		refuse.text = "Turn them down"
		refuse.tooltip_text = "They will compete harder for everything after this."
		refuse.pressed.connect(func() -> void:
			Game.decline_buyout()
			_refresh_contracts())
		_accent(refuse)
		bo_row.add_child(refuse)
	if Game.sold_out:
		contracts_box.add_child(_wrap("You sold the company. Everything still runs, and none of it is yours.",
			14, Color(0.7, 0.75, 0.85), 560))
	contracts_box.add_child(_section("PIPELINE"))
	if Game.leads.is_empty():
		var pipeline_empty := UIW.make_empty_state(
			"Nothing in the pipeline. Bigger work arrives through people talking about you, so reputation, references and marketing all feed this.")
		pipeline_empty.custom_minimum_size.x = 560
		contracts_box.add_child(pipeline_empty)
	for lead: Dictionary in Game.leads.duplicate():
		var card := PanelContainer.new()
		UIW.style_panel(card, "positive", "md")
		contracts_box.add_child(card)
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", 6)
		card.add_child(lv)
		lv.add_child(_label("%s   ·   %s   ·   %s" % [lead["customer"],
			Market.label_for(lead["kind"]),
			"a lead" if lead["stage"] == "lead" else "out to tender"], 16, Color.WHITE))
		if String(lead["stage"]) == "lead":
			lv.add_child(_wrap("Word is: %s. Nobody has asked them what they actually need yet."
				% lead["heard"], 13, Color(0.75, 0.8, 0.85)))
			lv.add_child(_label("Expires in %d cycle(s)." % int(lead["ttl"]), 12, MUTED))
			var qbtn := Button.new()
			qbtn.text = "Go and see them  ($%d)" % Market.LEAD_QUALIFY_COST
			qbtn.tooltip_text = "Some of them turn out to have no budget. That is what qualifying is for."
			_accent(qbtn)
			qbtn.pressed.connect(func() -> void:
				var err := Game.qualify_lead(lead)
				if err != "":
					_toast(err if err != "nothing there" else "%s had no budget after all." % lead["customer"])
				_refresh_contracts())
			lv.add_child(qbtn)
			continue
		lv.add_child(_wrap("They want: %s." % Market.rfp_requirements(lead), 13,
			Color(0.78, 0.83, 0.9)))
		lv.add_child(_label("Tender closes in %d cycle(s)." % int(lead["ttl"]), 12, MUTED))
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		lv.add_child(prow)
		prow.add_child(_label("Your price:  $", 14))
		var pprice := _mono_edit(90)
		pprice.placeholder_text = str(int(lead["size"]))
		prow.add_child(pprice)
		prow.add_child(_label("/cycle   commit to ", 14))
		var sla_opt := OptionButton.new()
		for ti in 3:
			sla_opt.add_item(Market.tier(ti)["label"])
		sla_opt.select(int(lead["sla"]))
		sla_opt.tooltip_text = "Commit to less than they asked for and the proposal is thrown out."
		prow.add_child(sla_opt)
		var sbtn := Button.new()
		sbtn.text = "Submit the proposal"
		_accent(sbtn)
		sbtn.pressed.connect(func() -> void:
			var txt := pprice.text.strip_edges()
			if not txt.is_valid_int():
				_toast("put a number on it")
				return
			var res := Game.submit_proposal(lead, int(txt), sla_opt.selected)
			_refresh_contracts()
			if res.begins_with("lost:"):
				_toast("Lost: %s." % res.trim_prefix("lost:"))
			elif res != "":
				_toast(res)
			else:
				hud_toast("%s is yours." % lead["customer"], true))
		prow.add_child(sbtn)
	contracts_box.add_child(_section("THE COMPETITION"))
	for r: Dictionary in Game.rivals:
		if not Rivals.alive(r):
			var fate: String = "acquired by %s" % r["merged_into"] if r.has("merged_into") else "acquired by you"
			contracts_box.add_child(_label("  %s: %s" % [r["name"], fate], 13,
				Color(0.6, 0.62, 0.68) if r.has("merged_into") else Color(0.5, 0.8, 0.6)))
			continue
		var price := Rivals.asking_price(r)
		var strat: Dictionary = Rivals.strategy_of(r)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		contracts_box.add_child(row)
		var premises: String = ("site %dx%d" % [int(r["site"]["grid"][0]),
			int(r["site"]["grid"][1])]) if Rivals.has_site(r) else "no premises"
		var l := _label("  %-16s %-11s %2d cust · %d racks · %-11s · $%d" % [r["name"],
			strat["label"], int(r["deals"]), Rivals.racks_needed(r), premises, price],
			13, Color(0.8, 0.78, 0.7))
		l.tooltip_text = ("%s\n\nBuying %s brings %d rack(s) and %d contract(s). %s" % [
			strat["blurb"], r["name"], Rivals.racks_needed(r), int(r["deals"]),
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
	contracts_box.add_child(_section("STATUS PAGE"))
	if Game.outage_open():
		contracts_box.add_child(_label("  A customer service is down. Saying so costs you less than being found out.",
			13, Color(1.0, 0.8, 0.5)))
	var post_row := HBoxContainer.new()
	contracts_box.add_child(post_row)
	var post_in := _mono_edit(380)
	post_in.placeholder_text = "what is happening, in plain language"
	post_row.add_child(post_in)
	var post_btn := Button.new()
	post_btn.text = "Post update"
	post_btn.pressed.connect(func() -> void:
		var err: String = Game.post_status(post_in.text)
		if err != "":
			_toast(err)
		_refresh_contracts())
	post_row.add_child(post_btn)
	for p: Dictionary in Game.status_posts.slice(0, 4):
		contracts_box.add_child(_label("  cycle %d: %s" % [int(p["cycle"]), p["text"]], 12,
			Color(0.7, 0.8, 0.85)))
	var open_reviews: Array = []
	for inc: Dictionary in Game.incidents:
		if not bool(inc.get("reviewed", false)):
			open_reviews.append(inc)
	if not open_reviews.is_empty():
		contracts_box.add_child(_section("INCIDENTS AWAITING A POST-MORTEM"))
		for inc: Dictionary in open_reviews:
			var irow := HBoxContainer.new()
			contracts_box.add_child(irow)
			var il := _label("  cycle %d: %s" % [int(inc["cycle"]), inc["summary"]], 13,
				Color(0.95, 0.72, 0.55))
			il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			irow.add_child(il)
			var replay_btn := Button.new()
			replay_btn.text = "Replay"
			replay_btn.tooltip_text = "What the estate looked like either side of it"
			replay_btn.pressed.connect(func() -> void:
				replay_for = int(inc["cycle"]) if replay_for != int(inc["cycle"]) else -1
				_refresh_contracts())
			irow.add_child(replay_btn)
			var rbtn := Button.new()
			rbtn.text = "Write it up"
			rbtn.pressed.connect(func() -> void:
				_menu(rbtn, Game.REVIEW_CAUSES, func(id: int) -> void:
					Game.review_incident(inc, id)
					_refresh_contracts()))
			irow.add_child(rbtn)
			if replay_for == int(inc["cycle"]):
				var frames := Game.replay_around(int(inc["cycle"]))
				if frames.is_empty():
					contracts_box.add_child(_label("      (nothing recorded that far back)", 12, MUTED))
				for frame: Dictionary in frames:
					var mark := "▸" if int(frame["cycle"]) == int(inc["cycle"]) else " "
					var rl2 := _label("      %s %s" % [mark, Game.replay_line(frame)], 12,
						Color(1.0, 0.8, 0.5) if int(frame["cycle"]) == int(inc["cycle"])
						else Color(0.68, 0.74, 0.82))
					rl2.add_theme_font_override("font", mono)
					contracts_box.add_child(rl2)
					for ev_line in frame["events"]:
						contracts_box.add_child(_wrap("           %s" % ev_line, 11,
							Color(0.58, 0.64, 0.72), 620))
	for inc2: Dictionary in Game.incidents:
		if bool(inc2.get("reviewed", false)):
			contracts_box.add_child(_label("  ✓ cycle %d: %s (cause: %s)" % [int(inc2["cycle"]),
				inc2["summary"], inc2.get("cause", "")], 12, Color(0.6, 0.75, 0.65)))

	Game.mark_events_read()
	if Game.events.is_empty():
		contracts_box.add_child(_label("Nothing has happened yet.", 13, MUTED))
		return
	contracts_box.add_child(_section("EVENT LOG"))
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	contracts_box.add_child(filter_row)
	for level in [["all", "Everything"], ["warning", "Problems"], ["critical", "Serious only"]]:
		var fb := Button.new()
		fb.text = level[1]
		fb.toggle_mode = true
		fb.button_pressed = log_filter == level[0]
		fb.pressed.connect(func() -> void:
			log_filter = String(level[0])
			_refresh_contracts())
		filter_row.add_child(fb)
	var rows := Game.events_by_severity(log_filter)
	if rows.is_empty():
		contracts_box.add_child(_label("  Nothing at that level. That is good news.", 12, MUTED))
	for row: Dictionary in rows:
		var ev: String = row["line"]
		var col := Color(0.72, 0.78, 0.86)
		match String(row["severity"]):
			"critical":
				col = Prefs.bad_colour()
			"warning":
				col = Color(0.95, 0.75, 0.45)
		var l := _label(ev, 12, col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(580, 0)
		contracts_box.add_child(l)

func _build_jobs_tab() -> void:
	if not Game.offers.is_empty():
		var desk := _section("BID DESK  /  INCOMING OPPORTUNITIES")
		desk.add_theme_color_override("font_color", UIW.colour("warm"))
		contracts_box.add_child(desk)
	for offer: Dictionary in Game.offers:
		var card := UIW.style_panel(PanelContainer.new(), "surface", "lg")
		contracts_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", UIW.space("md"))
		card.add_child(cv)
		var ct2: Dictionary = Market.TYPES.get(offer.get("ctype", "enterprise"), {})
		var offer_head := HBoxContainer.new()
		offer_head.add_theme_constant_override("separation", UIW.space("md"))
		cv.add_child(offer_head)
		var customer := _label(String(offer["customer"]), 18, UIW.colour("text_strong"))
		customer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		offer_head.add_child(customer)
		offer_head.add_child(UIW.make_chip("%s  /  %s" % [Market.label_for(offer["kind"]),
			ct2.get("label", "")], "info"))
		offer_head.add_child(UIW.make_chip("%d CYCLES LEFT" % int(offer["ttl"]),
			"warning" if int(offer["ttl"]) <= 2 else "accent"))
		if ct2.has("note"):
			cv.add_child(_wrap("%s  Market intel: %s" % [ct2["note"], offer["hint"]],
				13, UIW.colour("muted"), 620))

		var ask := UIW.style_panel(PanelContainer.new(), "console", "md")
		cv.add_child(ask)
		var ask_box := VBoxContainer.new()
		ask_box.add_theme_constant_override("separation", UIW.space("sm"))
		ask.add_child(ask_box)
		var ask_tag := _section("CLIENT ASK")
		ask_tag.add_theme_color_override("font_color", UIW.colour("accent"))
		ask_box.add_child(ask_tag)
		ask_box.add_child(_wrap(offer["brief"], 14, UIW.colour("text_strong"), 620))

		var otier := Market.tier(int(offer.get("sla", 0)))
		var facts := HBoxContainer.new()
		facts.add_theme_constant_override("separation", UIW.space("sm"))
		cv.add_child(facts)
		if float(otier["uptime"]) > 0.0:
			facts.add_child(_offer_fact("SERVICE LEVEL", "%s  ·  %.1fx penalty" % [otier["label"],
				float(otier["penalty"])], "warning"))
		else:
			facts.add_child(_offer_fact("SERVICE LEVEL", "Best effort  ·  no penalty", "success"))
		facts.add_child(_offer_fact("DELIVERY", String(offer["costs"]), "info"))
		var est: Array = Game.market_estimate(offer)
		var market_copy := "No rival bidder"
		if not Rivals.best_bidder(offer).is_empty():
			market_copy = ("No price signal yet" if est.is_empty() else "$%d–$%d likely" % [
				int(est[0]), int(est[1])])
		facts.add_child(_offer_fact("MARKET RANGE", market_copy,
			"success" if Rivals.best_bidder(offer).is_empty() else "warm"))
		if bool(offer.get("public", false)):
			var blocked := Game.can_accept_offer(offer)
			cv.add_child(_wrap("PUBLIC ADDRESS REQUIRED.%s"
				% ("" if blocked == "" else "  You have none free: buy a /29 or let this one go."),
				12, Prefs.bad_colour() if blocked != "" else UIW.colour("info"), 620))
		if offer["state"] == "counter":
			cv.add_child(_wrap("COUNTEROFFER  /  Best we can do is $%d per cycle." % int(offer["budget"]),
				14, UIW.colour("warm")))
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
				if res.begins_with("blocked:"):
					_toast(res.trim_prefix("blocked:"))
				elif res == "rejected":
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
			if deal.has("upsell"):
				var up: Dictionary = deal["upsell"]
				var urow := HBoxContainer.new()
				urow.add_theme_constant_override("separation", 8)
				contracts_box.add_child(urow)
				urow.add_child(_label("      they have grown: +%d Mbps for +$%d/cycle" % [
					int(up["load"]), int(up["fee"])], 13, Color(0.6, 0.9, 0.75)))
				var up_yes := Button.new()
				up_yes.text = "Take it"
				up_yes.tooltip_text = "More money, and more traffic on the same links tonight."
				_accent(up_yes)
				up_yes.pressed.connect(func() -> void:
					Game.accept_upsell(deal)
					_refresh_contracts())
				urow.add_child(up_yes)
				var up_no := Button.new()
				up_no.text = "Decline"
				up_no.tooltip_text = "They will remember it at renewal."
				up_no.pressed.connect(func() -> void:
					Game.decline_upsell(deal)
					_refresh_contracts())
				urow.add_child(up_no)
			if deal.has("renewal"):
				var rn: Dictionary = deal["renewal"]
				var rrow := HBoxContainer.new()
				rrow.add_theme_constant_override("separation", 8)
				contracts_box.add_child(rrow)
				rrow.add_child(_label("      up for renewal at $%d/cycle (%d%% uptime, %s)" % [
					int(rn["fee"]), int(rn["uptime"]), rn["mood"]], 13, Color(1.0, 0.85, 0.5)))
				var acc_btn := Button.new()
				acc_btn.text = "Renew"
				_accent(acc_btn)
				acc_btn.pressed.connect(func() -> void:
					Game.accept_renewal(deal)
					_refresh_contracts())
				rrow.add_child(acc_btn)
				var end_btn := Button.new()
				end_btn.text = "Let it end"
				end_btn.pressed.connect(func() -> void:
					Game.decline_renewal(deal)
					_refresh_contracts())
				rrow.add_child(end_btn)
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

func _offer_fact(caption: String, value: String, semantic: String) -> PanelContainer:
	var panel := UIW.style_panel(PanelContainer.new(), "overlay", "sm")
	panel.custom_minimum_size = Vector2(198, 76)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIW.space("xs"))
	panel.add_child(box)
	var cap := _section(caption)
	cap.add_theme_color_override("font_color", UIW.colour(semantic))
	box.add_child(cap)
	box.add_child(_wrap(value, 12, UIW.colour("text"), 180))
	return panel

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
		if String(c.get("hint", "")) != "":
			var hint_lbl := _label("", 13, Color(0.62, 0.75, 0.85))
			hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_lbl.custom_minimum_size = Vector2(560, 0)
			hint_lbl.visible = false
			var hint_btn := Button.new()
			hint_btn.text = "Stuck? Show me the commands"
			hint_btn.pressed.connect(func() -> void:
				hint_lbl.text = String(c["hint"])
				hint_lbl.visible = true
				hint_btn.visible = false)
			cv.add_child(hint_btn)
			cv.add_child(hint_lbl)
		var btn := Button.new()
		btn.text = "Check requirements & collect"
		_accent(btn)
		btn.pressed.connect(func() -> void:
			Game.try_complete_contract(c)
			_refresh_contracts()
			check_demo_end())
		cv.add_child(btn)
	if not found_active:
		contracts_box.add_child(_label("The demo arc is finished. The full game carries on from here."
			if Demo.active() else "All contracts complete! More arrive with future updates -\nsee the GitHub roadmap.",
			14, Color(0.7, 0.85, 0.75)))

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
		cli_out.custom_minimum_size.y = 220
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
		cli_out.custom_minimum_size.y = 0
		cli_toggle.text = "Open console  ▤"
		cli_out.clear()
		cli_session = null
		_fit_cards.call_deferred()

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
	if not visible:
		return  # the title screen is up; the game is not listening
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
