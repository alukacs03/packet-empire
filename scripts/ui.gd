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
var dev_faceplate: UIW.Faceplate
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
var if_note_ui := {}
var if_note_btn: Button
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
var unlock_intro_panel: PanelContainer
var unlock_intro_kicker: Label
var unlock_intro_title: Label
var unlock_intro_body: Label
var unlock_intro_where: Label
var unlock_intro_action: Button
var _unlock_intro_pending: Array[String] = []
var _unlock_intro_active := ""
var vlan_section: VBoxContainer
var vlan_box: VBoxContainer

const UNLOCK_INTROS := {
	"facility": {
		"kicker": "NEW GROUND  /  THE BUILDING",
		"title": "The building is yours to look after now.",
		"body": "Filters, an aircon service, a generator test, a battery check. None of it is urgent until the afternoon it is, and by then it is expensive.",
		"where": "OPS  /  FACILITY", "action": "See the schedule", "colour": "warm"},
	"renewals": {
		"kicker": "NEW DIARY  /  RENEWALS",
		"title": "Something is about to lapse.",
		"body": "Licences and contracts run out quietly. A lapsed licence does not break the device; it caps it, which is much harder to find.",
		"where": "OPS  /  RECORDS", "action": "Open the calendar", "colour": "warning"},
	"duties": {
		"kicker": "NEW BOARD  /  DUTIES",
		"title": "There are two of them now.",
		"body": "Chores can be handed over. What you give away costs money and a little control, and comes back done the way that person works.",
		"where": "OPS  /  AUTOMATION", "action": "Assign something", "colour": "accent"},
	"access": {
		"kicker": "NEW QUESTION  /  THE DOOR",
		"title": "Somebody who does not work here is on the floor.",
		"body": "An open floor is fastest and keeps no record of anything. Badges and escorts cost time on every visit and are the only reason you would ever know.",
		"where": "OPS  /  FACILITY", "action": "Decide the policy", "colour": "warm"},
	"compliance": {
		"kicker": "NEW SCRUTINY  /  CONTROLS",
		"title": "Somebody wants to see the paperwork.",
		"body": "Eight controls, each answered by the live network rather than a checkbox. What you can prove is worth money to the customers who ask.",
		"where": "OPS  /  RECORDS", "action": "Check readiness", "colour": "info"},
	"support": {
		"kicker": "NEW ROUTE  /  THE VENDOR",
		"title": "This one is not yours to fix.",
		"body": "A defect no configuration touches needs a case: evidence, a wait the length of your cover, and somebody who has seen it before.",
		"where": "OPS  /  HARDWARE", "action": "Open the case", "colour": "danger"},
	"map": {
		"kicker": "NEW TOOL  /  WALL MAP",
		"title": "The wall map is live.",
		"body": "One rack has become a network. Trace the path here before you crawl behind the cabinet.",
		"where": "MAP  ·  TOP TOOLBAR", "action": "Open Map", "colour": "accent"},
	"market": {
		"kicker": "NEW DESK  /  MARKET",
		"title": "The tender board is open.",
		"body": "Three clean jobs gave sales something to brag about. Qualify leads, price the risk, and choose who you work for.",
		"where": "COMPANY  /  MARKET", "action": "See the board", "colour": "warm"},
	"business": {
		"kicker": "NEW DESK  /  BUSINESS",
		"title": "The books have arrived.",
		"body": "A live customer turns blinking lights into invoices. Follow what was earned, billed, and actually paid.",
		"where": "COMPANY  /  BUSINESS", "action": "Open the books", "colour": "success"},
	"log": {
		"kicker": "NEW DESK  /  INCIDENT LOG",
		"title": "Start the incident clock.",
		"body": "The first unhappy packet deserves a paper trail. Record what customers heard and what the room did.",
		"where": "COMPANY  /  LOG", "action": "Read the log", "colour": "warning"},
	"ops": {
		"kicker": "NEW TOOL  /  OPERATIONS",
		"title": "You are on call now.",
		"body": "A paying service needs more than hope. Watch capacity, monitors, spares, and the work waiting for a pair of hands.",
		"where": "OPS  ·  TOP TOOLBAR", "action": "Open Ops", "colour": "danger"},
	"expand": {
		"kicker": "NEW OPTION  /  FACILITY",
		"title": "The tape measure is out.",
		"body": "This corner has proved itself. The next room brings more floor—and puts power and cooling on your books.",
		"where": "EXPAND  ·  TOP TOOLBAR", "action": "Point it out", "colour": "warm"},
}

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
var hud_ops_btn: Button
var hud_map_btn: Button
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
	_build_unlock_intro()
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
	Game.customer_service_changed.connect(_customer_service_feedback)
	Game.customer_cash_changed.connect(_customer_cash_feedback)
	Game.guided_outage_changed.connect(_refresh_tutorial)
	Prefs.changed.connect(_refresh_feature_discovery)
	get_viewport().size_changed.connect(_refresh_hud_layout)
	_refresh_money()
	_refresh_feature_discovery()
	_refresh_hud_layout()

func _feature_available(feature: String) -> bool:
	return Game.feature_unlocked(feature, Prefs.show_everything)

func _refresh_feature_discovery() -> void:
	for feature: String in Game.DISCOVERY_FEATURES:
		Game.observe_feature_unlock(feature)
	if hud_map_btn:
		hud_map_btn.visible = _feature_available("map")
	if hud_ops_btn:
		hud_ops_btn.visible = _feature_available("ops")
	if expand_btn:
		expand_btn.visible = Game.current_site == 0 and Game.stage < Game.STAGES.size() - 1 \
			and _feature_available("expand")
	for tab_name in contracts_tabs:
		contracts_tabs[tab_name].visible = _feature_available(String(tab_name).to_lower())
	_consider_unlock_intros()

func _build_unlock_intro() -> void:
	## A slim control-room dispatch, parked beneath the HUD and away from the
	## live brief. It informs without pausing the floor or dimming the room.
	unlock_intro_panel = PanelContainer.new()
	unlock_intro_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	unlock_intro_panel.position = Vector2(UIW.space("lg"), -250)
	unlock_intro_panel.custom_minimum_size = Vector2(430, 0)
	unlock_intro_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	unlock_intro_panel.theme = theme_res
	unlock_intro_panel.visible = false
	add_child(unlock_intro_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UIW.space("lg"))
	margin.add_theme_constant_override("margin_top", UIW.space("md"))
	margin.add_theme_constant_override("margin_right", UIW.space("lg"))
	margin.add_theme_constant_override("margin_bottom", UIW.space("md"))
	unlock_intro_panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UIW.space("sm"))
	margin.add_child(v)
	unlock_intro_kicker = _label("", 11, UIW.colour("accent"))
	unlock_intro_kicker.add_theme_font_override("font", mono)
	v.add_child(unlock_intro_kicker)
	unlock_intro_title = _label("", 20, Color(0.96, 0.97, 1.0))
	v.add_child(unlock_intro_title)
	unlock_intro_body = _wrap("", 13, UIW.colour("muted"), 382)
	v.add_child(unlock_intro_body)
	unlock_intro_where = _label("", 11, UIW.colour("muted"))
	unlock_intro_where.add_theme_font_override("font", mono)
	v.add_child(unlock_intro_where)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UIW.space("sm"))
	v.add_child(actions)
	unlock_intro_action = Button.new()
	_accent(unlock_intro_action)
	unlock_intro_action.pressed.connect(_follow_unlock_intro)
	actions.add_child(unlock_intro_action)
	var dismiss := Button.new()
	dismiss.text = "Got it"
	dismiss.pressed.connect(_dismiss_unlock_intro)
	actions.add_child(dismiss)

func _unlock_intro_suppressed() -> bool:
	return Game.sandbox or Prefs.show_everything or OS.get_environment("PACKET_SHOT") != ""

func _consider_unlock_intros() -> void:
	if unlock_intro_panel == null:
		return
	if _unlock_intro_suppressed():
		_unlock_intro_pending.clear()
		_unlock_intro_active = ""
		unlock_intro_panel.visible = false
		return
	for feature: String in Game.DISCOVERY_FEATURES:
		if _feature_available(feature) and feature not in Game.feature_intros_seen \
				and feature != _unlock_intro_active and feature not in _unlock_intro_pending:
			_unlock_intro_pending.append(feature)
	if _unlock_intro_active == "":
		_show_next_unlock_intro()

func _show_next_unlock_intro() -> void:
	if _unlock_intro_pending.is_empty():
		unlock_intro_panel.visible = false
		return
	_unlock_intro_active = _unlock_intro_pending.pop_front()
	var intro: Dictionary = UNLOCK_INTROS[_unlock_intro_active]
	var colour := UIW.colour(String(intro["colour"]))
	unlock_intro_panel.add_theme_stylebox_override("panel",
		_flat_sb(Color(0.045, 0.075, 0.11, 0.97), Color(colour, 0.8), 2, 0))
	unlock_intro_kicker.text = String(intro["kicker"])
	unlock_intro_kicker.add_theme_color_override("font_color", colour)
	unlock_intro_title.text = String(intro["title"])
	unlock_intro_body.text = String(intro["body"])
	unlock_intro_where.text = String(intro["where"])
	unlock_intro_action.text = String(intro["action"])
	unlock_intro_panel.modulate.a = 0.0
	unlock_intro_panel.visible = true
	Sfx.play("open")
	create_tween().tween_property(unlock_intro_panel, "modulate:a", 1.0, 0.18)

func _dismiss_unlock_intro() -> void:
	if _unlock_intro_active == "":
		return
	Game.acknowledge_feature_intro(_unlock_intro_active)
	_unlock_intro_active = ""
	unlock_intro_panel.visible = false
	_show_next_unlock_intro()

func _follow_unlock_intro() -> void:
	var feature := _unlock_intro_active
	_dismiss_unlock_intro()
	match feature:
		"map":
			toggle_map()
		"ops", "facility", "renewals", "duties", "access", "compliance", "support":
			toggle_ops()
		"market", "business", "log":
			contracts_tab = feature.capitalize()
			open_contracts()
		"expand":
			expand_btn.grab_focus()
			expand_btn.modulate = Color(1.25, 1.12, 0.72)
			create_tween().tween_property(expand_btn, "modulate", Color.WHITE, 0.7)
			hud_toast("EXPAND  /  The next room is ready when the cash and timing are right.", true)

func _money_flash() -> void:
	Sfx.play("money")
	money_lbl.modulate = Color(1.6, 1.6, 1.2)
	create_tween().tween_property(money_lbl, "modulate", Color.WHITE, 0.5)

func _customer_service_feedback(customer: String, state: String, fee: int) -> void:
	match state:
		"delivered":
			hud_toast("SERVICE LIVE  /  %s's promise is proven. Billing starts at $%d/cycle."
				% [customer, fee], true)
		"restored":
			hud_toast("SERVICE RESTORED  /  %s is reachable again. Billing resumes this cycle."
				% customer, true)
		"suspended":
			hud_toast("PAYMENT SUSPENDED  /  %s is down. No invoice until service returns."
				% customer)
	_refresh_tutorial()
	_refresh_open()

func _customer_cash_feedback(customer: String, state: String, amount: int) -> void:
	if state == "invoiced":
		hud_toast("INVOICE RAISED  /  %s owes $%d. Cash follows their payment terms."
			% [customer, amount], true)
	elif state == "collected":
		hud_toast("CASH ARRIVED  /  %s paid $%d. The working service remains yours to operate."
			% [customer, amount], true)
	_refresh_tutorial()
	_refresh_open()

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
		var quiet_line := Game.housekeeping_suggestion()
		if quiet_line != "":
			objective_lbl.text = "QUIET  ·  %s" % quiet_line
	if clock_lbl:
		var f := Game.day_factor()
		var shift_icon := "☀" if Game.day_slot() in [2, 3, 4, 5] else "☾"
		var coverage := ""
		if not Game.staff.is_empty() and not Staff.anyone_on_shift():
			coverage = "  ·  UNATTENDED"
		# the season decides cooling headroom, work rate and who is available,
		# so it belongs next to the clock rather than buried in a log line
		var season_icon := {"spring": "❀", "summer": "☼", "autumn": "❦",
			"winter": "❄"}.get(String(Game.season()["id"]), "")
		var season_mark := "  %s %s" % [season_icon, String(Game.season()["label"]).to_upper()]
		if Game.heat_wave():
			season_mark += "  HEAT WAVE"
		clock_lbl.text = "%s  %s  %d%%%s%s" % [shift_icon, Game.day_name().to_upper(),
			int(round(f * 100.0)), season_mark, coverage]
		clock_lbl.add_theme_color_override("font_color",
			UIW.colour("danger") if coverage != "" else
			(UIW.colour("warning") if f > 1.1 or Game.heat_wave() else UIW.colour("muted")))
		clock_lbl.tooltip_text = "Current shift, traffic level and season. The room lighting follows this clock; unattended hours leave incidents waiting for the next crew."
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
	_refresh_feature_discovery()

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
	hud_ops_btn = Button.new()
	hud_ops_btn.text = "OPS"
	hud_ops_btn.tooltip_text = "Operations dashboard (O)"
	hud_ops_btn.pressed.connect(toggle_ops)
	h.add_child(hud_ops_btn)
	hud_map_btn = Button.new()
	hud_map_btn.text = "MAP"
	hud_map_btn.tooltip_text = "Logical topology (M)"
	hud_map_btn.pressed.connect(toggle_map)
	h.add_child(hud_map_btn)
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
	clock_lbl.custom_minimum_size = Vector2(260, 0)
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

func _rack_cable_reject_reason(screen_pos: Vector2) -> String:
	for child in slot_box.get_children():
		if child is UIW.RackSlot:
			var candidate: Net.Iface = (child as UIW.RackSlot).port_at_screen(screen_pos)
			if candidate:
				if candidate.dev == rack_cable_from.dev:
					return "OTHER DEVICE REQUIRED"
				if Game.link_at(candidate):
					return "JACK ALREADY IN USE"
	return "FREE JACK REQUIRED"

func _rack_cable_release(screen_pos: Vector2) -> void:
	if rack_cable_from == null:
		rack_cable_layer.finish()
		return
	var target := _rack_target_at(screen_pos)
	var original_target: Net.Iface = rack_cable_old_link.other(rack_cable_from) if rack_cable_old_link else null
	rack_cable_layer.finish()
	if target == original_target:
		hud_toast("Plug reseated: %s %s." % [target.dev.name, target.name], true)
		rack_cable_layer.confirm(rack_cable_from, target)
	elif target and Game.can_link(rack_cable_from, target):
		if rack_cable_old_link:
			Game.disconnect_iface(rack_cable_from)
		if Game.cabling_documented:
			Game.connect_documented(rack_cable_from, target)
		else:
			Game.connect_ifaces(rack_cable_from, target)
		hud_toast("Cable run: %s %s ⇄ %s %s" % [rack_cable_from.dev.name,
			rack_cable_from.name, target.dev.name, target.name], true)
		_refresh_slots()
		rack_cable_layer.confirm(rack_cable_from, target)
	elif rack_cable_old_link:
		var loose_end := original_target
		Game.disconnect_iface(rack_cable_from)
		hud_toast("Unplugged %s %s from %s %s." % [rack_cable_from.dev.name,
			rack_cable_from.name, loose_end.dev.name, loose_end.name], true)
		_refresh_slots()
	else:
		rack_cable_layer.reject(screen_pos, _rack_cable_reject_reason(screen_pos))
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
		var delivery_credit := Game.delivery_credit_for_model(String(k))
		if delivery_credit > 0:
			line += "   CUSTOMER RESERVE $%d" % delivery_credit
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
		if not Game.try_buy_device(String(keys[id])):
			var available := Game.money + Game.delivery_credit_for_model(String(keys[id]))
			hud_toast("Not enough available for a %s ($%d, cash and protected delivery funds total $%d)." % [
				mod2["label"], int(mod2["price"]), available])
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
		var was_dirty := Game.config_dirty(cur_dev)
		cur_dev.startup = Game.device_config(cur_dev)
		_refresh_ports()
		if was_dirty:
			dev_faceplate.confirm_config_write()
			Sfx.play("good"))
	btn_row.add_child(save_cfg_btn)
	var confirm_btn := Button.new()
	confirm_btn.text = "Arm confirmed commit"
	confirm_btn.tooltip_text = "The change reverts in three cycles unless you come back and confirm it. This is what saves you when you cut your own path."
	confirm_btn.pressed.connect(func() -> void:
		var err: String = Game.arm_confirm(cur_dev) if not Game.confirm_commits.has(cur_dev.name) \
			else Game.confirm_commit(cur_dev)
		if err != "":
			_toast(err)
		else:
			hud_toast("Confirmed commit %s on %s." % [
				"armed" if Game.confirm_commits.has(cur_dev.name) else "confirmed", cur_dev.name],
				true))
	btn_row.add_child(confirm_btn)
	var uninstall := Button.new()
	uninstall.text = "Decommission…"
	uninstall.tooltip_text = "Pulling it is the fast half. What you skip is what an auditor asks about later."
	uninstall.pressed.connect(func() -> void:
		_menu(uninstall, [
			"Properly: wipe and certify, strip the cabling, reclaim the addresses (best resale)",
			"Wipe it, leave the rest (less back, and the addresses linger)",
			"Just pull it out (cheapest now, and there is no certificate)",
			"Hand it to a technician (they will do it their way)",
		], func(id: int) -> void:
			var dev := cur_dev
			close_dev()
			var out: Dictionary = {}
			match id:
				0:
					out = Game.decommission(dev, Game.DECOM_STEPS)
				1:
					out = Game.decommission(dev, ["wipe"])
				2:
					out = Game.decommission(dev, [])
				_:
					out = Game.decommission_by_tech(dev)
			hud_toast("Decommissioned for $%d.%s" % [int(out["value"]),
				"" if out["skipped"].is_empty() else "  Skipped %d step(s)." % out["skipped"].size()],
				out["skipped"].is_empty())
			_refresh_money()
			if cur_rack:
				_show_overlay(rack_overlay)))
	btn_row.add_child(uninstall)
	var hands := Button.new()
	hands.text = "Remote hands…"
	hands.tooltip_text = "Somebody else's hands, doing exactly what you wrote. Labels are what make that safe."
	hands.pressed.connect(func() -> void:
		var dev := cur_dev
		var facility: Dictionary = Game.remote_facility(
			int(Game.rack_of(dev).site) if Game.rack_of(dev) != null else 0)
		_menu(hands, [
			"Reseat the cable on the selected port ($%d)" % int(facility["cost"]),
			"Power cycle the device ($%d)" % int(facility["cost"]),
			"Look at the lights and report back ($%d)" % int(facility["cost"]),
		], func(id: int) -> void:
			var action: String = ["reseat", "power_cycle", "check"][id]
			var err: String = Game.request_remote_hands(dev, action,
				cur_if if cur_if != null and cur_if.dev == dev else null)
			hud_toast(err if err != "" else "Booked at %s. They will do exactly what is written (%d%% chance that is the right target)."
				% [facility["label"], int(Game.remote_precision(dev,
					cur_if if cur_if != null and cur_if.dev == dev else null) * 100.0)],
				err == "")
			_refresh_money()))
	btn_row.add_child(hands)

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
	dev_faceplate = UIW.Faceplate.new().setup(cur_dev, open_iface)
	center.add_child(dev_faceplate)
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
	if_note_ui = _note_card(v, func(text: String) -> void:
		Game.set_note(cur_if, text)
		_refresh_note_card(if_note_ui, cur_if, if_note_btn)
		_refresh_ports())
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
	var repair_btn := Button.new()
	repair_btn.text = "Physical work…"
	repair_btn.tooltip_text = "Reseat it, swap the optic, swap the lead. The wrong one costs the part and fixes nothing."
	repair_btn.pressed.connect(func() -> void:
		_menu(repair_btn, Game.GREY_REPAIRS, func(id: int) -> void:
			var err: String = Game.repair_grey(cur_if, String(Game.GREY_REPAIRS[id]))
			if err != "":
				_toast(err)
			_refresh_ports()
			_refresh_money()))
	cable_row.add_child(repair_btn)
	if_note_btn = Button.new()
	if_note_btn.text = "✎ TAG PORT"
	if_note_btn.tooltip_text = "Leave physical handover context on this jack"
	if_note_btn.pressed.connect(func() -> void: _open_note_card(if_note_ui))
	cable_row.add_child(if_note_btn)
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
	_refresh_note_card(if_note_ui, i, if_note_btn)
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
		var link := Game.link_at(cur_if)
		var far_iface: Net.Iface = link.other(cur_if)
		var local_rack := Game.rack_of(cur_if.dev)
		var same_rack := local_rack != null and Game.rack_of(far_iface.dev) == local_rack
		if same_rack:
			if_cable_lbl.text = "Physical patch: ⇄  " + peer
			if_cable_btn.text = "Open rack elevation"
			if_cable_btn.tooltip_text = "Pull the fitted plug from its jack to repatch or unplug it"
		else:
			if_cable_lbl.text = "Remote link: ⇄  " + peer
			if_cable_btn.text = "Disconnect"
			if_cable_btn.tooltip_text = "Remove this remote or circuit-backed link"
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
	var fitted := Game.link_at(cur_if)
	if fitted:
		var far_iface: Net.Iface = fitted.other(cur_if)
		var local_rack := Game.rack_of(cur_if.dev)
		if local_rack != null and Game.rack_of(far_iface.dev) == local_rack:
			close_iface()
			open_rack(local_rack)
			return
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
			if Game.cabling_documented:
				Game.connect_documented(cur_if, ports[id])
			else:
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
	for topic_i in Pedia.topics().size():
		var entry = Pedia.topics()[topic_i]
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
	if topic_i < 0 or topic_i >= Pedia.topics().size():
		return
	var entry = Pedia.topics()[topic_i]
	for button_i in pedia_topic_buttons.size():
		(pedia_topic_buttons[button_i] as Button).button_pressed = button_i == topic_i
	pedia_body.clear()
	pedia_body.append_text("[color=#39d9d0]FIELD MANUAL  /  CHAPTER %02d[/color]\n\n" % (topic_i + 1))
	pedia_body.append_text("[font_size=24][b]%s[/b][/font_size]\n\n" % entry[0])
	pedia_body.append_text("%s\n\n" % Pedia.article_text(entry))
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
			if why == "" and q in String(d.note.get("text", "")).to_lower():
				why = "note: %s" % d.note["text"]
			if why == "":
				for i2: Net.Iface in d.ifaces:
					if q in String(i2.note.get("text", "")).to_lower():
						why = "%s note: %s" % [i2.name, i2.note["text"]]
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
## Every section built into the Operations box belongs to exactly one tab.
## A section with no home is a bug, and the smoke pass says so.
const OPS_TABS := [
	["Capacity", ["CAPACITY", "POWER", "AIRFLOW"]],
	["Traffic", ["TOP TALKERS", "MONITORS"]],
	["Hardware", ["ASSETS AND SPARES", "DEVICES", "THE PARTS DRAWER", "RECEIVING",
		"VENDOR SUPPORT", "NOBODY CLAIMS THESE"]],
	["Facility", ["FIRE, SMOKE AND WATER", "FACILITY SCHEDULE", "WHO IS ON THE FLOOR"]],
	["Automation", ["PLAYBOOKS", "CERTIFICATES", "RUNBOOKS AND AUTOMATION", "STANDING DUTIES"]],
	["Records", ["DOCUMENTATION", "AUDIT READINESS", "RENEWALS CALENDAR", "UNREACHABLE",
		"WHAT YOU WROTE ABOUT THESE"]],
	["Company", ["WHAT KIND OF COMPANY THIS IS", "DECISIONS", "A VISIT IS BOOKED",
		"HOW THIS RUN ENDED", "RUNS BEFORE THIS ONE"]],
]
var ops_tab := "Capacity"
var ops_orphan_sections: Array = []  # sections with no tab: a bug, not a feature
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
	# anything before the first known heading is chrome that every tab keeps;
	# anything under an unknown heading is a section somebody forgot to place
	var current := ""
	ops_orphan_sections = []
	for child in ops_box.get_children():
		if child is Label and child.has_meta("section"):
			current = String(child.text)
			if current not in all_titles:
				ops_orphan_sections.append(current)
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
	if not Game.tour.is_empty():
		ops_box.add_child(_section("A VISIT IS BOOKED"))
		var kind: String = String(Game.tour["kind"])
		var tk: Dictionary = Game.TOUR_KINDS[kind]
		# the clock can be held (a drill, a scenario, a save opened past the
		# date), so never print a countdown that has gone the other way
		var due_in: int = int(Game.tour["cycle"]) - Game.cycle
		var when := "arrives in %d cycle(s)" % due_in if due_in > 0 else (
			"is walking the floor now" if due_in == 0 else "was due %d cycle(s) ago" % -due_in)
		ops_box.add_child(_wrap("  %s %s. They care about %s. On what they would see right now, you score %d%%."
			% [tk["label"], when, tk["cares"],
				int(Game.tour_score(kind) * 100.0)], 13, Color(1.0, 0.82, 0.5), 780))
		var cram_btn := Button.new()
		cram_btn.text = "Bring in a crew at short notice ($600)"
		cram_btn.tooltip_text = "It helps a little. It cannot fake months of neglect."
		cram_btn.pressed.connect(func() -> void:
			var err: String = Game.cram_for_tour()
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		ops_box.add_child(cram_btn)
	var past_you: Array = Game.incident_notes()
	if not past_you.is_empty():
		ops_box.add_child(_section("WHAT YOU WROTE ABOUT THESE"))
		for note_line: String in past_you:
			ops_box.add_child(_wrap("  %s" % note_line, 12, Color(1.0, 0.85, 0.55), 780))
	var stranded: Array = []
	for d_lock: Net.NDevice in Game.all_devices():
		# only a device that could be reached and now cannot: a device that was
		# never addressed for remote management is not locked out, it is new
		if Game.locked_out(d_lock) and bool(Game.lockout_state.get(d_lock.name, false)):
			stranded.append(d_lock)
	if not stranded.is_empty() or not Game.confirm_commits.is_empty():
		ops_box.add_child(_section("UNREACHABLE"))
	for d_lock2: Net.NDevice in stranded:
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 8)
		ops_box.add_child(lrow)
		var ll := _label("  %s is running and cannot be reached" % d_lock2.name, 12,
			Prefs.bad_colour())
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lrow.add_child(ll)
		var walk_btn := Button.new()
		var rack_lock := Game.rack_of(d_lock2)
		var far := rack_lock != null and int(rack_lock.site) != 0
		walk_btn.text = "Site visit ($350)" if far else "Walk to the rack"
		walk_btn.pressed.connect(func() -> void:
			var err: String = Game.walk_to_device(d_lock2)
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		lrow.add_child(walk_btn)
	for name_c: String in Game.confirm_commits:
		var crow2 := HBoxContainer.new()
		crow2.add_theme_constant_override("separation", 8)
		ops_box.add_child(crow2)
		var cl2 := _label("  %s: change reverts at cycle %d unless confirmed" % [name_c,
			int(Game.confirm_commits[name_c]["due"])], 12, Color(1.0, 0.82, 0.5))
		cl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow2.add_child(cl2)
		var conf := Button.new()
		conf.text = "Confirm"
		conf.pressed.connect(func() -> void:
			for d_conf: Net.NDevice in Game.all_devices():
				if d_conf.name == name_c:
					var err: String = Game.confirm_commit(d_conf)
					if err != "":
						_toast(err)
			_refresh_ops())
		crow2.add_child(conf)
	ops_box.add_child(_section("DOCUMENTATION"))
	ops_box.add_child(_wrap("  %d fact(s) on this floor no longer match what is written down. Documentation that is wrong is slower than none, because people believe it."
		% Game.site_drift(), 12,
		Color(1.0, 0.82, 0.5) if Game.drift_factor() > 0.3 else Color(0.72, 0.8, 0.88), 780))
	for r_doc: Net.Rack in Game.racks_on(Game.current_site):
		var drift_here: int = Game.rack_drift(r_doc)
		if drift_here == 0:
			continue
		var dr_row := HBoxContainer.new()
		dr_row.add_theme_constant_override("separation", 8)
		ops_box.add_child(dr_row)
		var drl := _label("  %-10s %d fact(s) adrift" % [r_doc.name, drift_here], 12,
			Color(0.78, 0.84, 0.9))
		drl.add_theme_font_override("font", mono)
		drl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dr_row.add_child(drl)
		var walk := Button.new()
		walk.text = "Walk it and write it up ($30)"
		walk.pressed.connect(func() -> void:
			var err: String = Game.reconcile_rack(r_doc)
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		dr_row.add_child(walk)
	var orphans: Array = Game.orphan_list()
	if not orphans.is_empty():
		ops_box.add_child(_section("NOBODY CLAIMS THESE"))
		for orphan: Dictionary in orphans:
			var orow := HBoxContainer.new()
			orow.add_theme_constant_override("separation", 8)
			ops_box.add_child(orow)
			var known: int = Game.orphan_intel_of(orphan)
			var suffix := ""
			if known >= 2:
				var bearing: String = Game.orphan_load_bearing(orphan)
				suffix = "   (%s)" % (bearing if bearing != "" else "nothing depends on it")
			var ol := _wrap("  %s%s" % [orphan["label"], suffix], 12,
				Color(1.0, 0.82, 0.5) if known < 2 else Color(0.72, 0.8, 0.88), 560)
			ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			orow.add_child(ol)
			if known < 2:
				var dig := Button.new()
				dig.text = "Investigate ($50)"
				dig.tooltip_text = "Counters, logs and asking somebody. Twice and you will know."
				dig.pressed.connect(func() -> void:
					var err: String = Game.investigate_orphan(orphan)
					if err != "":
						_toast(err)
					_refresh_ops()
					_refresh_money())
				orow.add_child(dig)
			var kill := Button.new()
			kill.text = "Turn it off"
			kill.tooltip_text = "Reclaims power, space and addresses. Assuming nothing needed it."
			kill.pressed.connect(func() -> void:
				var err: String = Game.retire_orphan(orphan)
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money())
			orow.add_child(kill)
	ops_box.add_child(_section("VENDOR SUPPORT"))
	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 8)
	ops_box.add_child(tier_row)
	tier_row.add_child(_label("  Cover: %s" % Game.SUPPORT_TIERS[Game.support_tier()]["label"],
		12, Color(0.72, 0.8, 0.88)))
	for tier_i in [1, 2]:
		var buy_tier := Button.new()
		buy_tier.text = "Buy %s ($%d)" % [Game.SUPPORT_TIERS[tier_i]["label"],
			int(Game.SUPPORT_TIERS[tier_i]["cost"])]
		buy_tier.tooltip_text = "Response in %d cycle(s), escalation in %d." % [
			int(Game.SUPPORT_TIERS[tier_i]["wait"]), int(Game.SUPPORT_TIERS[tier_i]["escalate"])]
		buy_tier.pressed.connect(func() -> void:
			var err: String = Game.buy_support(tier_i)
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		tier_row.add_child(buy_tier)
	for name_bug: String in Game.firmware_bugs:
		ops_box.add_child(_wrap("  %s is flapping a port with nothing in its configuration to explain it. No amount of your work will fix that one." % name_bug,
			12, Color(1.0, 0.72, 0.45), 780))
		var open_case := Button.new()
		open_case.text = "Open a case against %s" % name_bug
		open_case.pressed.connect(func() -> void:
			for d_case: Net.NDevice in Game.all_devices():
				if d_case.name == name_bug:
					var err: String = Game.open_tac_case(d_case, 2)
					if err != "":
						_toast(err)
			_refresh_ops())
		ops_box.add_child(open_case)
	for c: Dictionary in Game.tac_cases:
		if String(c["stage"]) == "closed":
			continue
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 8)
		ops_box.add_child(crow)
		var cl := _label("  %s  %s  severity %d  stage %s  (sent: %s)" % [c["id"], c["device"],
			int(c["severity"]), c["stage"],
			", ".join(PackedStringArray(c["evidence"])) if not c["evidence"].is_empty() else "nothing"],
			12, Color(0.78, 0.84, 0.9))
		cl.add_theme_font_override("font", mono)
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow.add_child(cl)
		if String(c["stage"]) in ["evidence", "level_one"]:
			for kind: String in Game.TAC_EVIDENCE:
				if kind in c["evidence"]:
					continue
				var ev := Button.new()
				ev.text = "Send %s" % kind
				ev.pressed.connect(func() -> void:
					var err: String = Game.attach_evidence(c, kind)
					if err != "":
						_toast(err)
					_refresh_ops())
				crow.add_child(ev)
				break
			var bundle_btn := Button.new()
			bundle_btn.text = "Attach a tech-support bundle"
			bundle_btn.tooltip_text = "'show tech-support' collects everything they asked for in one go"
			bundle_btn.pressed.connect(func() -> void:
				var err: String = Game.attach_bundle(c)
				if err != "":
					_toast(err)
				_refresh_ops())
			crow.add_child(bundle_btn)
			var hand := Button.new()
			hand.text = "Hand it to the team" if not bool(c.get("delegated", false)) else "Take it back"
			hand.tooltip_text = "They will work it, slowly, and they will not push back"
			hand.pressed.connect(func() -> void:
				c["delegated"] = not bool(c.get("delegated", false))
				_refresh_ops())
			crow.add_child(hand)
		elif String(c["stage"]) == "queued":
			var esc := Button.new()
			esc.text = "Escalate ($200)"
			esc.pressed.connect(func() -> void:
				var err: String = Game.escalate_case(c)
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money())
			crow.add_child(esc)
		elif String(c["stage"]) == "fix_ready":
			var load_btn := Button.new()
			load_btn.text = "Load the fixed image"
			load_btn.tooltip_text = "A reload. Inside a change window it is routine; outside one it is a decision."
			load_btn.pressed.connect(func() -> void:
				var err: String = Game.apply_firmware(c)
				if err != "":
					_toast(err)
				_refresh_ops())
			crow.add_child(load_btn)
	if not Game.renewals.is_empty():
		ops_box.add_child(_section("RENEWALS CALENDAR"))
		for item: Dictionary in Game.renewals:
			var due_in: int = Game.renewal_due_in(item)
			var rrow := HBoxContainer.new()
			rrow.add_theme_constant_override("separation", 8)
			ops_box.add_child(rrow)
			var state := "due in %d" % due_in
			if bool(item["lapsed"]):
				state = "LAPSED"
			elif due_in <= 0:
				state = "DUE NOW (%d cycle(s) of grace)" % (Game.RENEWAL_GRACE + due_in)
			var rl := _label("  %-34s %-28s $%d" % [item["label"], state,
				int(item["cost"]) * (2 if bool(item["lapsed"]) else 1)], 12,
				Prefs.bad_colour() if bool(item["lapsed"]) or due_in <= 0
				else Color(0.72, 0.8, 0.88))
			rl.add_theme_font_override("font", mono)
			rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rrow.add_child(rl)
			var pay := Button.new()
			pay.text = "Renew"
			pay.pressed.connect(func() -> void:
				var err: String = Game.renew_item(String(item["id"]))
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money())
			rrow.add_child(pay)
			var auto_r := Button.new()
			auto_r.toggle_mode = true
			auto_r.button_pressed = bool(item["auto"])
			auto_r.text = "Auto" if auto_r.button_pressed else "Manual"
			auto_r.tooltip_text = "Auto-renew takes the money when it takes it, whatever else is happening"
			auto_r.toggled.connect(func(on: bool) -> void:
				item["auto"] = on
				_refresh_ops())
			rrow.add_child(auto_r)
	if not Game.finale.is_empty():
		ops_box.add_child(_section("HOW THIS RUN ENDED"))
		for fin_line: String in Game.finale_report():
			var fl := _label("  %s" % fin_line, 12, Color(0.85, 0.9, 0.95))
			fl.add_theme_font_override("font", mono)
			ops_box.add_child(fl)
		for cmp_line: String in Game.compare_to_best(Game.finale.get("record", {})):
			ops_box.add_child(_label("  %s" % cmp_line, 12, Color(0.72, 0.84, 0.8)))
		var fin_copy := Button.new()
		fin_copy.text = "Copy the report"
		fin_copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set("\n".join(PackedStringArray(Game.finale_report())))
			hud_toast("The report is on your clipboard.", true))
		ops_box.add_child(fin_copy)
	elif Game.rank() == Game.RANKS[Game.RANKS.size() - 1][0]:
		var retire := Button.new()
		retire.text = "Retire at the top"
		retire.tooltip_text = "Freeze the run and read the report. Your save is not touched."
		retire.pressed.connect(func() -> void:
			var err: String = Game.end_run("retired")
			if err != "":
				_toast(err)
			_refresh_ops())
		ops_box.add_child(retire)
	var past_runs: Array = Game.run_history()
	if not past_runs.is_empty():
		ops_box.add_child(_section("RUNS BEFORE THIS ONE"))
		for row: Dictionary in past_runs.slice(0, 6):
			var rl := _label("  %-18s %-14s %-11s cycle %-5d score %d" % [row.get("company", ""),
				row.get("identity", ""), row.get("ending", ""), int(row.get("cycle", 0)),
				int(row.get("total", 0))], 12, Color(0.78, 0.84, 0.9))
			rl.add_theme_font_override("font", mono)
			ops_box.add_child(rl)
		var forget := Button.new()
		forget.text = "Clear the history"
		forget.tooltip_text = "History is not a save: clearing it costs you nothing but the table."
		forget.pressed.connect(func() -> void:
			Game.forget_all_runs()
			_refresh_ops())
		ops_box.add_child(forget)
	ops_box.add_child(_section("WHAT KIND OF COMPANY THIS IS"))
	if Game.identity == "":
		if Game.identity_offered():
			ops_box.add_child(_wrap("  You know the job now. Decide what sort of operation this is: each one changes the work that arrives, what it costs to run, and how the competition treats you.",
				13, Color(1.0, 0.85, 0.5), 780))
			for ident_id: String in Game.IDENTITIES:
				var ident: Dictionary = Game.IDENTITIES[ident_id]
				var irow2 := HBoxContainer.new()
				irow2.add_theme_constant_override("separation", 8)
				ops_box.add_child(irow2)
				var il2 := _wrap("  %s: %s  (%s)" % [ident["label"], ident["blurb"], ident["trade"]],
					12, Color(0.72, 0.8, 0.88), 560)
				il2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				irow2.add_child(il2)
				var ib := Button.new()
				ib.text = "Be this"
				ib.pressed.connect(func() -> void:
					Game.choose_identity(ident_id)
					_refresh_ops()
					_refresh_money())
				irow2.add_child(ib)
		else:
			ops_box.add_child(_label("  Finish the opening jobs first: the choice only means something once you know the loop.",
				12, MUTED))
	else:
		var mine: Dictionary = Game.IDENTITIES[Game.identity]
		ops_box.add_child(_wrap("  %s. %s  (%s)" % [mine["label"], mine["blurb"], mine["trade"]],
			12, Color(0.72, 0.84, 0.8), 780))
		var reb := Button.new()
		reb.text = "Rebrand ($5000 and some standing)…"
		reb.pressed.connect(func() -> void:
			var ids: Array = Game.IDENTITIES.keys()
			var opts_i: Array = []
			for id_o: String in ids:
				opts_i.append("%s: %s" % [Game.IDENTITIES[id_o]["label"],
					Game.IDENTITIES[id_o]["trade"]])
			_menu(reb, opts_i, func(id: int) -> void:
				var err: String = Game.rebrand(String(ids[id]))
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money()))
		ops_box.add_child(reb)
	ops_box.add_child(_section("WHO IS ON THE FLOOR"))
	ops_box.add_child(_wrap("  %s. %s%s" % [Game.ACCESS_POLICIES[Game.access_policy]["label"],
		Game.ACCESS_POLICIES[Game.access_policy]["blurb"],
		"  Cameras up." if Game.cameras else ""], 12, Color(0.72, 0.8, 0.88), 780))
	var acc_row := HBoxContainer.new()
	acc_row.add_theme_constant_override("separation", 8)
	ops_box.add_child(acc_row)
	for pol_id: String in Game.ACCESS_POLICIES:
		if pol_id == Game.access_policy:
			continue
		var polb := Button.new()
		polb.text = "%s ($%d)" % [Game.ACCESS_POLICIES[pol_id]["label"],
			int(Game.ACCESS_POLICIES[pol_id]["cost"])]
		polb.tooltip_text = String(Game.ACCESS_POLICIES[pol_id]["blurb"])
		polb.pressed.connect(func() -> void:
			var err: String = Game.set_access_policy(pol_id)
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		acc_row.add_child(polb)
	if not Game.cameras:
		var cam := Button.new()
		cam.text = "Put cameras in ($1200)"
		cam.tooltip_text = "They prevent nothing and explain everything."
		cam.pressed.connect(func() -> void:
			var err: String = Game.buy_cameras()
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		ops_box.add_child(cam)
	for vis: Dictionary in Game.visitors:
		ops_box.add_child(_label("  visitor: %s (%s)%s" % [vis["name"], vis["reason"],
			", escorted" if bool(vis["escorted"]) else ""], 12, Color(1.0, 0.82, 0.5)))
	var acc_lines: Array = Game.access_investigation()
	if acc_lines.is_empty():
		ops_box.add_child(_label("  Nothing on record. On an open floor there is nothing to have on record.",
			12, MUTED))
	for acc_line: String in acc_lines.slice(0, 6):
		ops_box.add_child(_label("      %s" % acc_line, 12, Color(0.68, 0.74, 0.82)))
	ops_box.add_child(_section("FIRE, SMOKE AND WATER"))
	for prot_id: String in Game.PROTECTION:
		var prot: Dictionary = Game.PROTECTION[prot_id]
		var prow2 := HBoxContainer.new()
		prow2.add_theme_constant_override("separation", 8)
		ops_box.add_child(prow2)
		var fitted: bool = bool(Game.protection.get(prot_id, {}).get("installed", false))
		var ready: bool = Game.protection_ready(prot_id)
		var pl2 := _label("  %-30s %s" % [prot["label"],
			("not fitted" if not fitted else ("in date" if ready else "OVERDUE INSPECTION"))], 12,
			Color(0.72, 0.84, 0.8) if ready else Color(1.0, 0.82, 0.5))
		pl2.add_theme_font_override("font", mono)
		pl2.tooltip_text = String(prot["blurb"])
		pl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prow2.add_child(pl2)
		var pbtn := Button.new()
		pbtn.text = ("Fit it ($%d)" % int(prot["cost"])) if not fitted \
			else ("Inspect ($%d)" % (int(prot["cost"]) / 6))
		pbtn.pressed.connect(func() -> void:
			var err: String = Game.buy_protection(prot_id) if not fitted \
				else Game.service_protection(prot_id)
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		prow2.add_child(pbtn)
	for r_risk: Net.Rack in Game.racks_on(Game.current_site):
		var risk_here: float = Game.hazard_risk(r_risk)
		if risk_here < 0.35:
			continue
		ops_box.add_child(_label("  %s is at %d%% hazard risk (heat, age, power, unserviced cooling)"
			% [r_risk.name, int(risk_here * 100.0)], 12, Color(1.0, 0.82, 0.5)))
	for haz_i: Dictionary in Game.hazards:
		ops_box.add_child(_label("  LIVE: %s in %s, severity %d%s" % [
			Game.HAZARD_KINDS[haz_i["kind"]]["label"], haz_i["rack"], int(haz_i["severity"]),
			"" if bool(haz_i["detected"]) else ", undetected"], 12, Prefs.bad_colour()))
	ops_box.add_child(_section("FACILITY SCHEDULE"))
	if Game.heat_wave():
		ops_box.add_child(_wrap("  HEAT WAVE  /  Cooling headroom is down a tenth while it lasts.",
			13, Color(1.0, 0.72, 0.45), 780))
	for task_id: String in Game.FACILITY_TASKS:
		var task: Dictionary = Game.FACILITY_TASKS[task_id]
		var due: int = Game.facility_due_in(task_id)
		var frow := HBoxContainer.new()
		frow.add_theme_constant_override("separation", 8)
		ops_box.add_child(frow)
		var fl := _label("  %-22s %s" % [task["label"],
			("due in %d cycle(s)" % due) if due > 0 else ("OVERDUE by %d" % -due)], 12,
			Color(0.72, 0.8, 0.88) if due > 0 else Color(1.0, 0.72, 0.45))
		fl.add_theme_font_override("font", mono)
		fl.tooltip_text = String(task["blurb"])
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frow.add_child(fl)
		var do_btn := Button.new()
		do_btn.text = "Do it ($%d)" % int(task["cost"])
		do_btn.pressed.connect(func() -> void:
			var err: String = Game.service_facility(task_id)
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		frow.add_child(do_btn)
		var auto_btn := Button.new()
		auto_btn.toggle_mode = true
		auto_btn.button_pressed = bool(Game.facility_auto.get(task_id, false))
		auto_btn.text = "On schedule" if auto_btn.button_pressed else "Delegate"
		auto_btn.tooltip_text = "Let the crew keep this one on schedule and bill you for it"
		auto_btn.toggled.connect(func(on: bool) -> void:
			Game.facility_auto[task_id] = on
			_refresh_ops())
		frow.add_child(auto_btn)
	if not Game.generator_ready():
		ops_box.add_child(_wrap("  The generator has not been load tested recently. If both feeds go and the battery runs out, you are hoping.",
			12, Color(1.0, 0.72, 0.45), 780))
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
	if not Game.decisions.is_empty():
		ops_box.add_child(_section("DECISIONS"))
		for dec: Dictionary in Game.decisions:
			var spec: Dictionary = Game.decision_by_id(String(dec["id"]))
			if spec.is_empty():
				continue
			ops_box.add_child(_wrap("  %s  —  %s" % [spec["title"], spec["text"]], 13,
				Color(1.0, 0.85, 0.5), 780))
			for fact: String in spec["facts"]:
				ops_box.add_child(_label("      · %s" % fact, 12, Color(0.72, 0.8, 0.88)))
			var decrow := HBoxContainer.new()
			decrow.add_theme_constant_override("separation", 8)
			ops_box.add_child(decrow)
			for opt_i in spec["options"].size():
				var ob := Button.new()
				ob.text = String(spec["options"][opt_i]["label"])
				ob.pressed.connect(func() -> void:
					Game.decide(String(dec["id"]), opt_i)
					_refresh_ops()
					_refresh_money())
				decrow.add_child(ob)
	if not Game.consequences.is_empty():
		ops_box.add_child(_label("  Waiting to land: %d decision(s) you have already made."
			% Game.consequences.size(), 12, MUTED))
	ops_box.add_child(_section("AUDIT READINESS"))
	ops_box.add_child(_wrap("  A teaching abstraction, not any real certification scheme: eight controls the simulation can actually prove.%s"
		% ("   Trust marker: earned." if Game.trust_marker else ""), 12, MUTED, 780))
	for ctrl: Dictionary in Game.audit_readiness():
		var ctrl_colour := Color(0.6, 0.85, 0.7)
		if String(ctrl["status"]) == "failing":
			ctrl_colour = Prefs.bad_colour()
		elif String(ctrl["status"]) != "compliant":
			ctrl_colour = Color(1.0, 0.82, 0.5)
		var cl3 := _label("  %-34s %-11s %s" % [ctrl["label"], ctrl["status"], ctrl["why"]], 12,
			ctrl_colour)
		cl3.add_theme_font_override("font", mono)
		cl3.tooltip_text = String(ctrl["blurb"])
		ops_box.add_child(cl3)
	if not Game.audit.is_empty():
		var aud: Dictionary = Game.audit
		ops_box.add_child(_wrap("  %s: a review of %s, worth $%d, sampled at cycle %d. The scope does not change once it starts."
			% [aud["customer"], ", ".join(PackedStringArray(aud["scope"])), int(aud["reward"]),
				int(aud["deadline"])], 13, Color(1.0, 0.85, 0.5), 780))
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 8)
		ops_box.add_child(arow)
		if String(aud["state"]) == "offered":
			for opt: Array in [["Accept", func() -> void: Game.accept_audit()],
					["Ask for more time", func() -> void: Game.delay_audit()],
					["Decline", func() -> void: Game.decline_audit()]]:
				var ab := Button.new()
				ab.text = String(opt[0])
				ab.pressed.connect(func() -> void:
					(opt[1] as Callable).call()
					_refresh_ops()
					_refresh_money())
				arow.add_child(ab)
		elif String(aud["state"]) == "findings":
			for f_i: Dictionary in aud["findings"]:
				ops_box.add_child(_label("      %s: %s (%s)" % [String(f_i["grade"]).to_upper(),
					f_i["control"], f_i["why"]], 12,
					Prefs.bad_colour() if String(f_i["grade"]) == "major finding"
					else Color(1.0, 0.82, 0.5)))
			var vb := Button.new()
			vb.text = "Ask them to re-verify"
			vb.pressed.connect(func() -> void:
				var err: String = Game.verify_audit()
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money())
			arow.add_child(vb)
	ops_box.add_child(_section("STANDING DUTIES"))
	if Game.staff.is_empty():
		ops_box.add_child(_label("  Nobody on the payroll: every chore here is yours by hand.",
			12, Color(0.72, 0.8, 0.88)))
	for duty_id: String in Game.DUTIES:
		var duty: Dictionary = Game.DUTIES[duty_id]
		var holder: String = Game.duty_holder(duty_id)
		var drow := HBoxContainer.new()
		drow.add_theme_constant_override("separation", 8)
		ops_box.add_child(drow)
		var dl := _label("  %-34s %s" % [duty["label"],
			("by hand" if holder == "" else "%s (%d%% as good as you)"
				% [holder, int(Game.duty_quality(duty_id) * 100.0)])], 12,
			Color(0.72, 0.8, 0.88) if holder == "" else Color(0.78, 0.86, 0.78))
		dl.add_theme_font_override("font", mono)
		dl.tooltip_text = String(duty["blurb"])
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		drow.add_child(dl)
		var assign := Button.new()
		assign.text = "Assign…" if holder == "" else "Take it back"
		assign.pressed.connect(func() -> void:
			if holder != "":
				Game.assign_duty(duty_id, "")
				_refresh_ops()
				return
			var names: Array = []
			var name_opts: Array = []
			for m_d: Dictionary in Game.staff:
				names.append(String(m_d["name"]))
				name_opts.append("%s  (%s, holding %d)" % [m_d["name"], Staff.label(m_d),
					Game.duty_load(String(m_d["name"]))])
			if name_opts.is_empty():
				_toast("nobody to give it to")
				return
			_menu(assign, name_opts, func(id: int) -> void:
				var err: String = Game.assign_duty(duty_id, String(names[id]))
				if err != "":
					_toast(err)
				_refresh_ops()))
		drow.add_child(assign)
	if not Game.last_digest.is_empty():
		ops_box.add_child(_label("  Last cycle: %s" % "; ".join(PackedStringArray(Game.last_digest)),
			12, Color(0.68, 0.74, 0.82)))
	ops_box.add_child(_section("THE PARTS DRAWER"))
	var parts_row := HBoxContainer.new()
	parts_row.add_theme_constant_override("separation", 8)
	ops_box.add_child(parts_row)
	var drawer: Array = []
	for kind_p: String in Game.PART_LABELS:
		drawer.append("%s %d" % [Game.PART_LABELS[kind_p], Game.parts_of(kind_p)])
	var drawer_lbl := _label("  %s%s" % [", ".join(PackedStringArray(drawer)),
		"   ·   %d improvised lead(s) still in place" % Game.cable_debt if Game.cable_debt > 0 else ""],
		12, Color(0.72, 0.8, 0.88))
	drawer_lbl.add_theme_font_override("font", mono)
	drawer_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_row.add_child(drawer_lbl)
	var buy_parts_btn := Button.new()
	buy_parts_btn.text = "Stock up…"
	buy_parts_btn.pressed.connect(func() -> void:
		var kinds: Array = Game.PART_LABELS.keys()
		var opts_p: Array = []
		for kind_o: String in kinds:
			opts_p.append("10 %s   $%d" % [Game.PART_LABELS[kind_o],
				int(Game.PART_PRICES[kind_o]) * 10])
		_menu(buy_parts_btn, opts_p, func(id: int) -> void:
			var err: String = Game.buy_parts(String(kinds[id]), 10)
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money()))
	parts_row.add_child(buy_parts_btn)
	var auto_parts := Button.new()
	auto_parts.toggle_mode = true
	auto_parts.button_pressed = Game.parts_auto
	auto_parts.text = "Standing order" if Game.parts_auto else "Order by hand"
	auto_parts.tooltip_text = "Keep the drawer topped up automatically, while there is money to do it"
	auto_parts.toggled.connect(func(on: bool) -> void:
		Game.parts_auto = on
		_refresh_ops())
	parts_row.add_child(auto_parts)
	var cabling_row := HBoxContainer.new()
	cabling_row.add_theme_constant_override("separation", 8)
	ops_box.add_child(cabling_row)
	cabling_row.add_child(_wrap("  Cable debt: %d traceable item(s). Cabling properly costs $25 and two labels a run; doing it fast costs nothing now."
		% Game.cable_debt_score(), 12,
		Color(1.0, 0.82, 0.5) if Game.cable_debt_score() > 4 else Color(0.72, 0.8, 0.88), 520))
	var cabling_btn := Button.new()
	cabling_btn.toggle_mode = true
	cabling_btn.button_pressed = Game.cabling_documented
	cabling_btn.text = "Cabling: documented" if Game.cabling_documented else "Cabling: expedient"
	cabling_btn.tooltip_text = "Documented runs label both ends and write themselves up as they go."
	cabling_btn.toggled.connect(func(on: bool) -> void:
		Game.cabling_documented = on
		_refresh_ops())
	cabling_row.add_child(cabling_btn)
	for debt_item: Dictionary in Game.cable_debt_items().slice(0, 5):
		ops_box.add_child(_label("      · %s  (%s)" % [debt_item["label"], debt_item["fix"]], 12,
			Color(0.68, 0.74, 0.82)))
	if Game.cable_debt > 0:
		var redo := Button.new()
		redo.text = "Redo the improvised leads (%d)" % Game.cable_debt
		redo.tooltip_text = "Proper lengths, out of the drawer. It shows on a tour."
		redo.pressed.connect(func() -> void:
			var err: String = Game.redo_cable_debt()
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		ops_box.add_child(redo)
	ops_box.add_child(_section("RECEIVING"))
	var order_btn := Button.new()
	order_btn.text = "Order hardware…"
	order_btn.tooltip_text = "Vendor tier decides the price and the wait. What turns up is a crate."
	order_btn.pressed.connect(func() -> void:
		var order_models: Array = []
		var order_opts: Array = []
		for m_id: String in Game.MODELS:
			order_models.append(m_id)
			order_opts.append("%s%s" % [Game.MODELS[m_id]["label"],
				"   (on back order)" if Game.stocked_out(m_id) else ""])
		_menu(order_btn, order_opts, func(id: int) -> void:
			var model_pick: String = String(order_models[id])
			var tiers: Array = Game.VENDOR_TIERS.keys()
			var tier_opts: Array = []
			for t_id: String in tiers:
				var spec: Dictionary = Game.VENDOR_TIERS[t_id]
				tier_opts.append("%s   $%d   %d-%d cycles   %s" % [spec["label"],
					Game.order_estimate(model_pick, t_id), int(spec["wait"][0]),
					int(spec["wait"][1]), spec["blurb"]])
			_menu(order_btn, tier_opts, func(tid: int) -> void:
				var err: String = Game.order_hardware(model_pick, 1, String(tiers[tid]))
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money())))
	ops_box.add_child(order_btn)
	if Game.aisle_blocked():
		ops_box.add_child(_wrap("  The receiving area is full and the aisle is not clear. Everything takes longer, and it is the first thing a visitor sees.",
			12, Color(1.0, 0.72, 0.45), 780))
	for r_rma: Dictionary in Game.rmas:
		ops_box.add_child(_label("  RMA: %s away with the vendor, replacement due in %d cycle(s)%s"
			% [Game.MODELS[r_rma["model"]]["label"], int(r_rma["due"]) - Game.cycle,
				" (advance replacement)" if bool(r_rma["advance"]) else ""], 12,
			Color(0.72, 0.8, 0.88)))
	for crate: Dictionary in Game.crates:
		var krow := HBoxContainer.new()
		krow.add_theme_constant_override("separation", 8)
		ops_box.add_child(krow)
		var state := "in transit, due in %d" % (int(crate["due"]) - Game.cycle)
		if int(crate["arrived"]) >= 0:
			state = "on the dock%s" % ("" if bool(crate["checked"]) else ", unchecked")
		var kl := _label("  crate: %-22s %s" % [Game.MODELS[crate["model"]]["label"], state], 12,
			Color(0.78, 0.84, 0.9))
		kl.add_theme_font_override("font", mono)
		kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		krow.add_child(kl)
		if int(crate["arrived"]) >= 0:
			if not bool(crate["checked"]):
				var chk := Button.new()
				chk.text = "Check against the order"
				chk.tooltip_text = "Damage and wrong items go back free. Discovered later, they do not."
				chk.pressed.connect(func() -> void:
					var err: String = Game.check_crate(crate)
					if err != "":
						_toast(err)
					_refresh_ops()
					_refresh_money())
				krow.add_child(chk)
			var unp := Button.new()
			unp.text = "Unpack"
			unp.pressed.connect(func() -> void:
				var err: String = Game.unpack_crate(crate)
				if err != "":
					_toast(err)
				_refresh_ops())
			krow.add_child(unp)
	if Game.packaging > 0:
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		ops_box.add_child(prow)
		prow.add_child(_label("  %d pile(s) of cardboard and wrap in the aisle" % Game.packaging,
			12, Color(1.0, 0.82, 0.5)))
		var clear_btn := Button.new()
		clear_btn.text = "Take it out"
		clear_btn.pressed.connect(func() -> void:
			Game.clear_packaging()
			_refresh_ops())
		prow.add_child(clear_btn)
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
		var rma_btn := Button.new()
		rma_btn.text = "Send it back (RMA)"
		rma_btn.tooltip_text = "Ship the dead unit to the vendor. With support cover the replacement comes first."
		rma_btn.pressed.connect(func() -> void:
			var err: String = Game.send_rma(d)
			if err != "":
				_toast(err)
			_refresh_ops()
			get_parent().rebuild_racks())
		frow.add_child(rma_btn)
	ops_box.add_child(_section("RUNBOOKS AND AUTOMATION"))
	var rb_new := Button.new()
	rb_new.text = "New runbook…"
	rb_new.tooltip_text = "A bounded action, a selector, and a blast radius. Nothing else."
	rb_new.pressed.connect(func() -> void:
		var actions: Array = Game.RUNBOOK_ACTIONS.keys()
		var act_opts: Array = []
		for act_id: String in actions:
			act_opts.append("%s: %s" % [Game.RUNBOOK_ACTIONS[act_id]["label"],
				Game.RUNBOOK_ACTIONS[act_id]["blurb"]])
		_menu(rb_new, act_opts, func(id: int) -> void:
			var target := cur_dev.name if cur_dev != null else ""
			Game.make_runbook("%s %s" % [Game.RUNBOOK_ACTIONS[actions[id]]["label"],
				target if target != "" else "(everything)"], String(actions[id]), target)
			_refresh_ops()))
	ops_box.add_child(rb_new)
	for rb_i: Dictionary in Game.runbooks:
		var rbrow := HBoxContainer.new()
		rbrow.add_theme_constant_override("separation", 8)
		ops_box.add_child(rbrow)
		var rbl := _label("  %-38s targets %d, may touch %d" % [rb_i["name"],
			Game.runbook_targets(rb_i).size(), int(rb_i["max_devices"])], 12,
			Color(0.78, 0.84, 0.9))
		rbl.add_theme_font_override("font", mono)
		rbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rbrow.add_child(rbl)
		var rb_dry := Button.new()
		rb_dry.text = "Dry run"
		rb_dry.pressed.connect(func() -> void:
			var out: Dictionary = Game.run_runbook(rb_i, true)
			for line: String in out["log"]:
				Game.log_event("DRY RUN: %s" % line)
			hud_toast("Dry run: %d planned, %d would be skipped." % [out["planned"].size(),
				out["skipped"].size()], String(out["refused"]) == "")
			_refresh_ops())
		rbrow.add_child(rb_dry)
		var rb_go := Button.new()
		rb_go.text = "Run it"
		rb_go.pressed.connect(func() -> void:
			var out: Dictionary = Game.run_runbook(rb_i, false, true)
			hud_toast(String(out["refused"]) if String(out["refused"]) != ""
				else "Applied to %d device(s)." % out["applied"].size(),
				String(out["refused"]) == "")
			_refresh_ops())
		rbrow.add_child(rb_go)
		var rb_bind := Button.new()
		rb_bind.text = "Bind to an alert…"
		rb_bind.pressed.connect(func() -> void:
			var mon_opts: Array = []
			for m_b: Dictionary in Game.monitors:
				mon_opts.append(Game.monitor_label(m_b))
			if mon_opts.is_empty():
				_toast("no checks to bind it to")
				return
			_menu(rb_bind, mon_opts, func(id: int) -> void:
				Game.bind_remediation(Game.monitors[id], rb_i)
				_refresh_ops()))
		rbrow.add_child(rb_bind)
	for m_t: Dictionary in Game.monitors:
		var rem_t: Dictionary = m_t.get("remediation", {})
		if rem_t.is_empty():
			continue
		ops_box.add_child(_label("  %s → '%s'" % [Game.monitor_label(m_t), rem_t["runbook"]],
			12, Color(0.72, 0.84, 0.8)))
		for line_t: String in rem_t.get("timeline", []):
			ops_box.add_child(_label("      %s" % line_t, 11, Color(0.68, 0.74, 0.82)))
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
	if not _feature_available("ops"):
		hud_toast("OPS unlocks when your first live customer creates an operational duty.")
		return
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
			"Reduced motion: %s" % ("on" if Prefs.reduced_motion else "off"),
			"Full toolbox from start: %s" % ("on" if Prefs.show_everything else "off"),
			"Language: %s" % Loc.language_label(Prefs.language),
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
				4:
					Prefs.reduced_motion = not Prefs.reduced_motion
				5:
					Prefs.show_everything = not Prefs.show_everything
				6:
					# immediate, and the whole interface is rebuilt around it
					var langs: Array = Loc.languages()
					var at := langs.find(Prefs.language)
					Prefs.language = String(langs[(at + 1) % langs.size()])
					Loc.language = Prefs.language
					_rebuild_localised()
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
	var puzzle_btn := Button.new()
	puzzle_btn.text = "Hand somebody this fault…"
	puzzle_btn.tooltip_text = "Copy the live topology, configs and symptom to the clipboard, or open one somebody sent you"
	puzzle_btn.pressed.connect(func() -> void:
		_menu(puzzle_btn, [
			"Copy it as \"solve this\"",
			"Copy it as \"what am I missing\"",
			"Copy it blind (an extra fault neither of us has seen)",
			"Open a puzzle from the clipboard",
			"Copy the fix I found" if Puzzle.active() else "Read a fix from the clipboard",
			"Close the puzzle and go home" if Puzzle.active() else "(no puzzle open)",
		], func(id: int) -> void:
			if id <= 2:
				DisplayServer.clipboard_set(Puzzle.export_state(
					"review" if id == 1 else "solve", id == 2))
				hud_toast("Copied. Paste it to whoever you are asking.", true)
			elif id == 3:
				var err: String = Puzzle.import_state(DisplayServer.clipboard_get())
				hud_toast(err if err != "" else "Puzzle open. Nothing here can cost you anything.",
					err == "")
				get_parent().rebuild_racks()
			elif id == 4 and Puzzle.active():
				DisplayServer.clipboard_set(Puzzle.solution())
				hud_toast("Your fix is on the clipboard. Send it back.", true)
			elif id == 4:
				var lines: Array = Puzzle.read_solution(DisplayServer.clipboard_get())
				for line: String in lines:
					Game.log_event("PUZZLE ANSWER: %s" % line)
				hud_toast("Read %d line(s) of answer into the log." % lines.size(),
					not lines.is_empty())
			elif Puzzle.active():
				Puzzle.close()
				get_parent().rebuild_racks()
				hud_toast("Back in your own datacenter.", true)))
	v.add_child(puzzle_btn)
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
	var workshop := Button.new()
	workshop.text = "Content workshop…  (%d pack(s))" % Pack.loaded.size()
	workshop.tooltip_text = "Packs are JSON files: what is on the floor, what has to become true, and what happens then."
	workshop.pressed.connect(func() -> void: _workshop_menu(workshop))
	v.add_child(workshop)
	var diagram := Button.new()
	diagram.text = "Export the topology (diagram + listing)"
	diagram.tooltip_text = "Mermaid for a picture, plain text for a report. Copied to the clipboard as well."
	diagram.pressed.connect(func() -> void:
		var body: String = Game.export_topology()
		if body == "":
			_toast("could not write the export")
			return
		DisplayServer.clipboard_set(body)
		menu_overlay.visible = false
		hud_toast("Topology exported and copied to the clipboard.", true))
	v.add_child(diagram)
	var chal_btn := Button.new()
	chal_btn.text = "Challenge…  (a drill anybody can reproduce from a code)"
	chal_btn.pressed.connect(func() -> void:
		_menu(chal_btn, [
			"Play today's featured code (%s)" % Challenge.daily_code(),
			"Play a code from the clipboard",
			"Copy this challenge's code" if not Challenge.active.is_empty() else "(no challenge running)",
			"Finish and copy the result card" if not Challenge.active.is_empty() else "(nothing to finish)",
		], func(id: int) -> void:
			if id == 0 or id == 1:
				menu_overlay.visible = false
				var code: String = Challenge.daily_code() if id == 0 else DisplayServer.clipboard_get()
				var err: String = Challenge.start(code)
				if err != "":
					_toast(err)
					return
				get_parent().rebuild_racks()
				_show_drill_banner()
			elif id == 2 and not Challenge.active.is_empty():
				DisplayServer.clipboard_set(String(Challenge.active["code"]))
				hud_toast("Code copied. The same code builds the same network.", true)
			elif id == 3 and not Challenge.active.is_empty():
				var result: Dictionary = Challenge.finish()
				var lines: Array = Challenge.card(result)
				for line: String in lines:
					Game.log_event(line)
				DisplayServer.clipboard_set("\n".join(PackedStringArray(lines)))
				get_parent().rebuild_racks()
				hud_toast("Scored %d. The card is on your clipboard." % int(result["total"]),
					bool(result["solved"]))))
	v.add_child(chal_btn)
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
	if not Drill.outcome.is_empty():
		# a services incident has no pair of static addresses to light up: the
		# thing to restore is what the customer asked for
		var client: Net.NDevice = Drill.outcome["client"]
		drill_box.add_child(_label("%s must get an address by DHCP, resolve %s and reach it."
			% [client.name, Drill.outcome["name"]], 13, Color(0.9, 0.88, 0.8)))
	drill_box.add_child(_label("Something is broken. Restore connectivity between:", 13, Color(0.85, 0.8, 0.78))
		if not Drill.targets.is_empty() else _label("Press Check when you believe it is fixed.",
			13, Color(0.85, 0.8, 0.78)))
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
		open_dev(dev),
		func(a: Net.NDevice, b: Net.NDevice) -> String:
			return Game.link_devices(a, b)))

func toggle_map() -> void:
	if not _feature_available("map"):
		hud_toast("MAP unlocks after the first rack is physically delivered.")
		return
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

func _next_waiting_customer() -> Dictionary:
	for deal: Dictionary in Game.deals:
		if not bool(deal.get("healthy", false)):
			return deal
	return {}

func _open_business_desk() -> void:
	contracts_tab = "Business"
	_refresh_contracts()
	_show_overlay(contracts_overlay)

func _guided_invoice(deal: Dictionary) -> Dictionary:
	for invoice: Dictionary in Game.invoices:
		if String(invoice.get("deal", "")) == String(deal.get("id", "")):
			return invoice
	return {}

func _render_guided_delivery(deal: Dictionary) -> void:
	tutorial_panel.visible = true
	for old in tutorial_box.get_children():
		old.queue_free()
	var ever_live := bool(deal.get("ever_healthy", false))
	var live := bool(deal.get("healthy", false))
	var invoiced := deal.has("first_invoice_cycle")
	var collected := deal.has("first_cash_cycle")
	if not ever_live:
		tutorial_box.add_child(_tutorial_head("DELIVER  /  %s" % String(deal["customer"]).to_upper()))
		tutorial_box.add_child(_wrap("Promise sold: %s" % String(deal["brief"]), 13,
			UIW.colour("text"), 290))
		for check: Dictionary in Market.delivery_checks(deal):
			var check_ok := bool(check["ok"])
			var copy := "%s  %s\n     FIELD WORK  /  %s" % ["●" if check_ok else "○",
				check["promise"], check["work"]]
			tutorial_box.add_child(_wrap(copy, 12,
				Color(0.48, 0.9, 0.62) if check_ok else UIW.colour("muted"), 290))
		var reserve := int(deal.get("delivery_credit", 0))
		if reserve > 0:
			tutorial_box.add_child(_wrap("PROTECTED  /  $%d customer reserve can only fund a server for this promise."
				% reserve, 11, UIW.colour("warm"), 290))
		var delivery_btn := Button.new()
		delivery_btn.text = "Open customer delivery brief"
		delivery_btn.pressed.connect(func() -> void:
			contracts_tab = "Jobs"
			open_contracts())
		tutorial_box.add_child(delivery_btn)
		return
	if not collected or not live:
		tutorial_box.add_child(_tutorial_head("BILL  /  %s" % String(deal["customer"]).to_upper()))
		tutorial_box.add_child(_label("%s  Service %s  ·  billing %s" % [
			"●" if live else "!", "live" if live else "down",
			"active" if live else "SUSPENDED"], 12,
			Color(0.48, 0.9, 0.62) if live else Prefs.bad_colour()))
		tutorial_box.add_child(_label("%s  First invoice raised" % ("●" if invoiced else "○"),
			12, Color(0.48, 0.9, 0.62) if invoiced else UIW.colour("muted")))
		tutorial_box.add_child(_label("%s  First cash collected" % ("●" if collected else "○"),
			12, Color(0.48, 0.9, 0.62) if collected else UIW.colour("muted")))
		var invoice := _guided_invoice(deal)
		if not invoice.is_empty() and not collected:
			var due_in := maxi(0, int(invoice["due"]) - Game.cycle)
			tutorial_box.add_child(_wrap("RECEIVABLE  /  $%d due in %d cycle%s. Revenue is earned; cash has not landed yet."
				% [int(invoice["amount"]), due_in, "" if due_in == 1 else "s"],
				11, UIW.colour("warm"), 290))
		var books_btn := Button.new()
		books_btn.text = "Open the business ledger"
		books_btn.pressed.connect(_open_business_desk)
		tutorial_box.add_child(books_btn)
		return
	tutorial_box.add_child(_tutorial_head("CUSTOMER LIVE  /  CASH MOVING"))
	for line in ["Promise translated into a working service",
			"First invoice raised on the customer terms",
			"First cash collected without removing the topology"]:
		tutorial_box.add_child(_label("●  " + line, 12, Color(0.48, 0.9, 0.62)))
	var continue_btn := Button.new()
	continue_btn.text = "Keep operating this customer"
	continue_btn.pressed.connect(func() -> void:
		Game.stats["guided_delivery_acknowledged"] = 1
		_refresh_tutorial())
	tutorial_box.add_child(continue_btn)

func _incident_button(text: String, action: Callable, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	if accent:
		_accent(button)
	button.pressed.connect(action)
	return button

func _render_guided_outage() -> void:
	tutorial_panel.visible = true
	for old in tutorial_box.get_children():
		old.queue_free()
	var incident: Dictionary = Game.guided_outage
	var state := String(incident.get("state", "alert"))
	var headline := "CUSTOMER DOWN  /  KISKACSA"
	if state == "recovered":
		headline = "INCIDENT RECOVERED  /  KISKACSA"
	elif state == "choice":
		headline = "HARDEN  /  KISKACSA"
	tutorial_box.add_child(_tutorial_head(headline))
	if state == "alert":
		tutorial_box.add_child(_wrap("MONITOR ALERT  /  The service at %s stopped answering. Pause, take ownership, then communicate before changing anything."
			% incident.get("target_ip", "the customer address"), 12, Prefs.bad_colour(), 290))
		tutorial_box.add_child(_incident_button("Acknowledge incident", func() -> void:
			Game.acknowledge_guided_outage(), true))
		return
	if state == "acknowledged":
		tutorial_box.add_child(_label("●  Alert owned by you", 12, Color(0.48, 0.9, 0.62)))
		tutorial_box.add_child(_wrap("CUSTOMER COMMS  /  Say what is affected, that you are investigating, and when you will update them again.",
			12, UIW.colour("text"), 290))
		tutorial_box.add_child(_wrap("Posting now makes the reputation loss visible and smaller: −2 instead of −4 per outage cycle.",
			11, UIW.colour("warm"), 290))
		tutorial_box.add_child(_incident_button("Open status page", func() -> void:
			contracts_tab = "Log"
			_refresh_contracts()
			_show_overlay(contracts_overlay), true))
		return
	if state in ["communicated", "investigating", "diagnosed", "repairing"]:
		tutorial_box.add_child(_label("●  Customer updated  ·  reputation protected", 12,
			Color(0.48, 0.9, 0.62)))
		var evidence: Array = incident.get("evidence", [])
		var ladder := [
			["monitor", "MONITOR", "Confirm scope from the failed check"],
			["physical", "PHYSICAL", "Verify that the patch is seated"],
			["l2", "L2", "Inspect the access-port state"],
		]
		for step: Array in ladder:
			var done: bool = String(step[0]) in evidence
			tutorial_box.add_child(_label("%s  %-10s %s" % ["●" if done else "○", step[1], step[2]],
				11, Color(0.48, 0.9, 0.62) if done else UIW.colour("muted")))
		if state not in ["diagnosed", "repairing"]:
			var next_layer := String(ladder[evidence.size()][0])
			tutorial_box.add_child(_incident_button("Gather next evidence", func() -> void:
				var err := Game.guided_outage_probe(next_layer)
				if err != "": _toast(err)
				_refresh_tutorial(), true))
			return
		tutorial_box.add_child(_wrap("ROOT CAUSE  /  %s %s is administratively disabled. The cable and addressing remain intact; routing and policy are not implicated."
			% [incident.get("device", "device"), incident.get("iface", "port")],
			12, UIW.colour("warm"), 290))
		var affected := Game.guided_outage_iface()
		if affected != null:
			var ros: bool = String(Game.MODELS[affected.dev.model].get("os", "")) == "ros"
			var command := "/interface set %s disabled=no" % affected.name if ros else \
				"interface %s  →  no shutdown" % affected.name
			tutorial_box.add_child(_wrap("REPAIR IN CONSOLE  /  %s" % command, 11,
				UIW.colour("text_strong"), 290))
			tutorial_box.add_child(_incident_button("Open affected port", func() -> void:
				_goto_device(affected.dev)
				open_iface(affected), true))
		tutorial_box.add_child(_label("○  Run one cycle after repair to verify recovery",
			11, UIW.colour("muted")))
		var give_up := _incident_button("Use teaching restore point", func() -> void:
			var err := Game.give_up_guided_outage()
			if err != "": _toast(err)
			_refresh_tutorial())
		give_up.tooltip_text = "Re-enables only the tutorial access port. No customer or topology is deleted."
		tutorial_box.add_child(give_up)
		return
	if state == "recovered":
		tutorial_box.add_child(_label("●  SERVICE RESTORED  ·  BILLING RESUMED", 12,
			Color(0.48, 0.9, 0.62)))
		tutorial_box.add_child(_section("INCIDENT TIMELINE"))
		for note: String in incident.get("timeline", []):
			tutorial_box.add_child(_wrap("•  " + note, 10, UIW.colour("muted"), 290))
		tutorial_box.add_child(_incident_button("Review and harden", func() -> void:
			Game.debrief_guided_outage(), true))
		return
	if state == "choice":
		tutorial_box.add_child(_wrap("WHAT CHANGES AFTER TONIGHT?  Pick one small resilience improvement. The customer and working topology remain yours.",
			12, UIW.colour("text"), 290))
		for option: Array in [
			["spare", "Put matching hardware on the spare shelf"],
			["monitor", "Keep a permanent reachability monitor"],
			["config", "Save the affected device configuration"],
		]:
			tutorial_box.add_child(_incident_button(String(option[1]), func() -> void:
				var err := Game.choose_guided_resilience(String(option[0]))
				if err != "": _toast(err)
				else: hud_toast("First outage closed. The network is stronger for it.", true)
				_refresh_tutorial()))

func _refresh_tutorial() -> void:
	if tutorial_panel == null:
		return
	if tutorial_hidden:
		tutorial_panel.visible = false
		return
	if Game.guided_outage_active():
		_render_guided_outage()
		return
	if "rackup" in Game.contracts_done:
		var guided := Game.guided_customer_deal()
		if not guided.is_empty() and int(Game.stats.get("guided_delivery_acknowledged", 0)) == 0:
			_render_guided_delivery(guided)
			return
		var waiting := _next_waiting_customer()
		if not waiting.is_empty():
			tutorial_panel.visible = true
			for old in tutorial_box.get_children():
				old.queue_free()
			tutorial_box.add_child(_tutorial_head("DELIVER  /  %s" % String(waiting["customer"]).to_upper()))
			var promise := _wrap("○  Promise sold: %s" % String(waiting["brief"]), 13,
				UIW.colour("text"), 290)
			tutorial_box.add_child(promise)
			tutorial_box.add_child(_label("○  Prove the live service, then let one billing cycle run.",
				12, UIW.colour("muted")))
			var desk_btn := Button.new()
			desk_btn.text = "Open customer delivery brief"
			desk_btn.pressed.connect(open_contracts)
			tutorial_box.add_child(desk_btn)
			return
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
	t.text = Loc.t("welcome.title")
	welcome_overlay.set_meta("title_label", t)
	var shift := _section(Loc.t("welcome.shift"))
	shift.add_theme_color_override("font_color", UIW.colour("warm"))
	v.add_child(shift)
	var body := _wrap(Loc.t("welcome.lede"), 17,
		UIW.colour("text_strong"), 620)
	welcome_overlay.set_meta("arrival_slot", true)
	welcome_overlay.set_meta("body_label", body)
	v.add_child(body)

	var modules := HBoxContainer.new()
	modules.add_theme_constant_override("separation", UIW.space("md"))
	v.add_child(modules)
	modules.add_child(_welcome_module("01", Loc.t("welcome.module1.title"),
		Loc.t("welcome.module1.body"), "info"))
	modules.add_child(_welcome_module("02", Loc.t("welcome.module2.title"),
		Loc.t("welcome.module2.body"), "warm"))
	modules.add_child(_welcome_module("03", Loc.t("welcome.module3.title"),
		Loc.t("welcome.module3.body"), "success"))

	var tip := UIW.style_panel(PanelContainer.new(), "console", "md")
	v.add_child(tip)
	var tip_row := HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", UIW.space("md"))
	tip.add_child(tip_row)
	var prompt := _label(">", 20, UIW.colour("accent"))
	prompt.add_theme_font_override("font", mono)
	tip_row.add_child(prompt)
	var tip_copy := _wrap(Loc.t("welcome.tip"), 13, UIW.colour("muted"), 560)
	tip_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_row.add_child(tip_copy)

	var go := Button.new()
	go.text = Loc.t("welcome.start")
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

func _rebuild_localised() -> void:
	## Changing language rebuilds the panels that carry copy, so nothing has to
	## be restarted and nothing is left in the old language.
	welcome_overlay.queue_free()
	_build_welcome()
	_refresh_tutorial()
	_refresh_contracts()
	if ops_overlay.visible:
		_refresh_ops()

func show_welcome() -> void:
	# the arrival lines are the first thing on the card, so the opening is a
	# place and a person rather than a list of buttons
	var arrival: Array = []
	for line: String in Game.events_by_severity("all").map(func(r): return String(r["line"])):
		if "ARRIVAL:" in line:
			arrival.append(line.substr(line.find("ARRIVAL:") + 9))
	if not arrival.is_empty():
		var head2 := welcome_overlay.get_meta("body_label") as Label
		if head2 != null:
			arrival.reverse()
			head2.text = " ".join(PackedStringArray(arrival))
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
		"Own the room, and everything in it: the power bill, the crew, the customers who remember.", "warm"))
	demo_overlay.set_meta("run_line", _wrap("", 13, UIW.colour("accent"), 700))
	v.add_child(demo_overlay.get_meta("run_line"))
	var beyond := UIW.style_panel(PanelContainer.new(), "console", "md")
	v.add_child(beyond)
	var beyond_box := VBoxContainer.new()
	beyond_box.add_theme_constant_override("separation", UIW.space("sm"))
	beyond.add_child(beyond_box)
	for line: String in [
		"THE NETWORK  /  DHCP · DNS · NAT · BGP · OSPF · VRRP · MLAG · IPv6 · NAT64 · VXLAN · EVPN · WIREGUARD · 802.1X · MULTI-SITE WAN",
		"THE BUSINESS  /  customers who remember how you treated them, rivals with grudges and favours, decisions whose bill arrives later",
		"THE BUILDING  /  power, cooling, filters, fire, water, badges, contractors, and the paperwork somebody eventually asks to see",
		"THE PEOPLE  /  a crew who copy your habits, standing duties, and who takes the blame when it was one of them",
		"THE RUN  /  it ends: sold, retired, or broke. It is scored, and something survives into the next one."]:
		var l3 := _wrap(line, 12, UIW.colour("muted"), 700)
		l3.add_theme_font_override("font", mono)
		beyond_box.add_child(l3)
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

func refresh_demo_end() -> void:
	## the card is about the shift they just worked, not a brochure
	var run_line := demo_overlay.get_meta("run_line") as Label
	if run_line != null:
		run_line.text = Game.demo_summary()

func check_demo_end() -> void:
	if not Demo.complete() or _demo_end_shown:
		return
	_demo_end_shown = true
	refresh_demo_end()
	_show_overlay(demo_overlay)

# ---------- contracts ----------

var contracts_tab := "Jobs"
var log_filter := "all"
var expanded_digest := -1  # which cycle's shift notes are open
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
	contracts_box.add_child(_section("LAST CYCLE  /  BUSINESS FLOW"))
	contracts_box.add_child(_wrap(
		"Revenue is what the network earned. An invoice makes it receivable; collection is when cash reaches the bank. Power and transit leave immediately.",
		12, UIW.colour("muted"), 600))
	var flow := GridContainer.new()
	flow.columns = 3
	flow.add_theme_constant_override("h_separation", UIW.space("sm"))
	flow.add_theme_constant_override("v_separation", UIW.space("sm"))
	contracts_box.add_child(flow)
	flow.add_child(_offer_fact("REVENUE EARNED", "+$%d\nservice delivered" % int(Game.last_business.get("revenue", 0)), "success"))
	flow.add_child(_offer_fact("INVOICES RAISED", "+$%d\nnow receivable" % int(Game.last_business.get("invoiced", 0)), "info"))
	flow.add_child(_offer_fact("CASH COLLECTED", "+$%d\nreached the bank" % int(Game.last_business.get("collected", 0)), "success"))
	flow.add_child(_offer_fact("POWER COST", "-$%d\npaid this cycle" % int(Game.last_business.get("power", 0)), "warning"))
	flow.add_child(_offer_fact("TRANSIT COST", "-$%d\nports and traffic" % int(Game.last_business.get("transit", 0)), "warning"))
	var cash_delta := int(Game.last_cycle_delta)
	flow.add_child(_offer_fact("NET CASH", "%s$%d\nactual bank movement" % [
		"+" if cash_delta >= 0 else "-", absi(cash_delta)], "success" if cash_delta >= 0 else "danger"))
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
	if not Game.pl_totals.is_empty():
		# where the money has actually gone, per system, across the whole run
		var totals: Array = []
		for k2 in Game.pl_totals:
			totals.append([String(k2), int(Game.pl_totals[k2])])
		totals.sort_custom(func(x, y): return absi(int(x[1])) > absi(int(y[1])))
		var total_parts: Array = []
		for row in totals.slice(0, 12):
			total_parts.append("%s %s$%d" % [row[0], "+" if int(row[1]) >= 0 else "-",
				absi(int(row[1]))])
		var run_pl := _label("      run to date:   " + "   ·   ".join(PackedStringArray(total_parts)),
			12, Color(0.6, 0.66, 0.78))
		run_pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		run_pl.custom_minimum_size = Vector2(560, 0)
		contracts_box.add_child(run_pl)
	var nr2 := Game.next_rank()
	contracts_box.add_child(_label("rank: %s%s" % [Game.rank(),
		"" if nr2.is_empty() else "   ·   %d points to %s" % [int(nr2[1]), nr2[0]]],
		13, Color(0.85, 0.8, 0.6)))
	contracts_box.add_child(_label("%s   ·   cycle %d   ·   lifetime earned $%d   ·   %d contracts, %d deals   ·   %d incidents, %d field faults" % [Game.identity_label(), Game.cycle, Game.stats["earned"], Game.stats["contracts"], Game.stats["deals"], Game.stats["incidents"], Game.stats["faults"]], 12, Color(0.5, 0.56, 0.68)))
	contracts_box.add_child(_section("CAREER PROFILE"))
	for line: String in Skills.profile():
		contracts_box.add_child(_wrap("  %s" % line, 12, Color(0.72, 0.8, 0.88), 640))
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
	var frozen: String = Game.freeze_reason()
	if Game.change_active():
		var cw: Dictionary = Game.change_window
		contracts_box.add_child(_wrap("  WINDOW RUNNING  /  \"%s\" on %s. Rollback point at cycle %d, window closes at %d. The work is %s."
			% [cw["summary"], ", ".join(PackedStringArray(cw["targets"])),
				int(cw["rollback_at"]), int(cw["ends"]),
				"finished" if Game.change_work_done() else "not finished"],
			13, Color(1.0, 0.85, 0.5), 780))
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 8)
		contracts_box.add_child(crow)
		var finish_btn := Button.new()
		finish_btn.text = "Close it out"
		finish_btn.pressed.connect(func() -> void:
			var err: String = Game.complete_change()
			if err != "":
				_toast(err)
			_refresh_contracts())
		crow.add_child(finish_btn)
		var abort_btn := Button.new()
		abort_btn.text = "Abort and revert"
		abort_btn.tooltip_text = "Back to what was running when the window opened. A wasted night, and nothing worse."
		abort_btn.pressed.connect(func() -> void:
			Game.abort_change()
			_refresh_contracts())
		crow.add_child(abort_btn)
		if not bool(cw["pushed"]):
			var push_btn := Button.new()
			push_btn.text = "Push on past the rollback point"
			push_btn.tooltip_text = "From here it has to work: there is no going back inside the window."
			_accent(push_btn)
			push_btn.pressed.connect(func() -> void:
				Game.push_on_change()
				_refresh_contracts())
			crow.add_child(push_btn)
	else:
		var plan_btn := Button.new()
		plan_btn.text = "Submit a change plan…"
		plan_btn.tooltip_text = "What you are touching, how long you need, and whether there is a backout plan"
		if frozen != "":
			contracts_box.add_child(_label("  Change freeze: %s. Overriding it is remembered." % frozen,
				12, Color(1.0, 0.72, 0.45)))
		plan_btn.pressed.connect(func() -> void:
			var targets: Array = []
			for d_c: Net.NDevice in Game.all_devices():
				if Game.config_dirty(d_c):
					targets.append(d_c.name)
			if targets.is_empty():
				for d_c2: Net.NDevice in Game.all_devices():
					if d_c2.type in ["switch", "router", "firewall"]:
						targets.append(d_c2.name)
						break
			_menu(plan_btn, [
				"Four cycles, with a backout plan",
				"Four cycles, no backout plan (faster to write, worse to explain)",
				"Eight cycles, with a backout plan",
				"Override the freeze and go now" if frozen != "" else "Two cycles, with a backout plan",
			], func(id: int) -> void:
				var minutes: int = [4, 4, 8, 2][id]
				var err: String = Game.submit_change("planned work on %s" % targets[0],
					targets, minutes, id != 1, id == 3 and frozen != "")
				if err != "":
					_toast(err)
				_refresh_contracts()))
		contracts_box.add_child(plan_btn)
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
		if Game.callout_ready():
			# the thing you actually do at three in the morning
			var callout := Button.new()
			callout.text = "Call somebody out ($%d)" % Game.CALLOUT_FEE
			callout.tooltip_text = "Phone the best-rested member of the crew and get them in for a cycle. It costs the fee and it costs their morale."
			_accent(callout)
			callout.pressed.connect(func() -> void:
				var err := Game.call_someone_out()
				if err != "":
					_toast(err)
				else:
					_refresh_contracts())
			contracts_box.add_child(callout)
	for m: Dictionary in Game.staff.duplicate():
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 6)
		contracts_box.add_child(srow)
		var under: bool = int(m["salary"]) < Staff.market_rate(m)
		var busy: int = int(m.get("training_left", 0))
		var state := "on a course, %d cycle(s) left" % busy if busy > 0 else \
			("on shift" if Staff.on_shift(m) else "off shift")
		if Staff.tired(m):
			state += ", tired"
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
		contracts_box.add_child(_wrap("      how they work: %s" % Staff.habit_read(m), 12,
			Color(0.6, 0.68, 0.78), 640))
		var oncall_btn := Button.new()
		oncall_btn.text = "☎ On call" if Staff.on_call(m) else "☎ Not on call"
		oncall_btn.tooltip_text = "Who carries the phone out of hours. The retainer is $%d a cycle, and calling them out is cheaper on the money and on them." % Staff.ONCALL_RETAINER
		if Staff.on_call(m):
			_accent(oncall_btn)
		oncall_btn.pressed.connect(func() -> void:
			Game.set_oncall("" if Staff.on_call(m) else String(m["name"]))
			_refresh_contracts()
			_refresh_money())
		srow.add_child(oncall_btn)
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
	var pipeline_anchor := VBoxContainer.new()
	pipeline_anchor.add_theme_constant_override("separation", UIW.space("sm"))
	contracts_box.add_child(pipeline_anchor)
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
	pipeline_anchor.add_child(_section("PIPELINE"))
	if Game.leads.is_empty():
		var pipeline_empty := UIW.make_empty_state(
			"Nothing in the pipeline. Bigger work arrives through people talking about you, so reputation, references and marketing all feed this.")
		pipeline_empty.custom_minimum_size.x = 560
		pipeline_anchor.add_child(pipeline_empty)
	for lead: Dictionary in Game.leads.duplicate():
		var card := PanelContainer.new()
		UIW.style_panel(card, "positive", "md")
		pipeline_anchor.add_child(card)
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", 6)
		card.add_child(lv)
		lv.add_child(_label("%s   ·   %s   ·   %s   ·   %s" % [lead["customer"],
			Market.TYPES.get(String(lead.get("ctype", "enterprise")), {}).get("label", "customer"),
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
		var serve := Market.cost_to_serve(lead)
		var qualify_facts := HBoxContainer.new()
		qualify_facts.add_theme_constant_override("separation", UIW.space("sm"))
		lv.add_child(qualify_facts)
		qualify_facts.add_child(_offer_fact("EXPECTED LOAD", "~%d Mbps\nPays %d cycle%s after invoice" % [
			int(lead["load"]), Game.payment_terms(lead), "" if Game.payment_terms(lead) == 1 else "s"], "info"))
		qualify_facts.add_child(_offer_fact("COST TO SERVE",
			"$%d setup  ·  $%d/cycle\n~$%d/cycle break-even over %d cycles" % [
				int(serve["setup"]), int(serve["running"]), int(serve["floor"]), int(serve["term"])], "warning"))
		qualify_facts.add_child(_offer_fact("COMPETITION",
			"Budget confidential. Reputation and references let you charge above the cheapest bid.", "warm"))
		if lead.has("coach"):
			var coaching := UIW.style_panel(PanelContainer.new(), "warning", "sm")
			var coaching_text := _wrap("PROPOSAL REVIEW  /  %s. Revise and send it again—this first customer will wait."
				% String(lead["coach"]).capitalize(), 12, UIW.colour("text_strong"), 600)
			coaching.add_child(coaching_text)
			lv.add_child(coaching)
		lv.add_child(_label("Tender closes in %d cycle(s)." % int(lead["ttl"]), 12, MUTED))
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		lv.add_child(prow)
		prow.add_child(_label("Your price:  $", 14))
		var pprice := _mono_edit(90)
		pprice.placeholder_text = str(int(serve["floor"]) + 18)
		pprice.tooltip_text = "A starting point above estimated break-even—not the customer's hidden budget."
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
			elif res.begins_with("retry:"):
				_toast("Not signed yet: %s. Kiskacsa will let you revise this first proposal."
					% res.trim_prefix("retry:"))
			elif res != "":
				_toast(res)
			else:
				hud_toast("%s is yours." % lead["customer"], true))
		prow.add_child(sbtn)
		var margin_lbl := _label("", 11, MUTED)
		margin_lbl.add_theme_font_override("font", mono)
		lv.add_child(margin_lbl)
		var refresh_margin := func(raw_price: String) -> void:
			var quote := int(serve["floor"]) + 18
			if raw_price.strip_edges().is_valid_int():
				quote = int(raw_price.strip_edges())
			var per_cycle := quote - int(serve["floor"])
			var direction := "above" if per_cycle >= 0 else "below"
			var term_shape := absi(per_cycle * int(serve["term"]))
			var term_word := "margin" if per_cycle >= 0 else "shortfall"
			margin_lbl.text = "PRICE SHAPE  /  $%d %s estimated break-even each cycle  ·  ~$%d %s over the initial %d-cycle term before incidents" % [
				absi(per_cycle), direction, term_shape, term_word, int(serve["term"])]
		pprice.text_changed.connect(refresh_margin)
		refresh_margin.call("")
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
		var temper: Dictionary = Rivals.temper_of(r)
		var standing := int(r.get("standing", 0))
		l.tooltip_text += "\n\n%s %s" % [temper["blurb"],
			"They are your nemesis: %s." % Game.nemesis_reason if String(r["name"]) == Game.nemesis
			else ("They owe you one." if standing >= 2
				else ("There is friction there." if standing <= -1 else ""))]
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
	if Game.upstream_active():
		contracts_box.add_child(_section("SOMEBODY ELSE'S OUTAGE"))
		contracts_box.add_child(_wrap("  %s is down and you cannot fix it. What is left is everything else: the case, the chasing, and telling your customers before they ask." % Game.upstream["party"],
			13, Color(1.0, 0.8, 0.5), 640))
		for line: String in Game.upstream_evidence():
			contracts_box.add_child(_wrap("      · %s" % line, 12, Color(0.7, 0.8, 0.85), 640))
		var urow := HBoxContainer.new()
		urow.add_theme_constant_override("separation", 8)
		contracts_box.add_child(urow)
		var case_btn := Button.new()
		case_btn.text = "Chase the case" if bool(Game.upstream.get("opened", false)) else "Open a case"
		_accent(case_btn)
		case_btn.pressed.connect(func() -> void:
			var err: String = Game.chase_upstream() if bool(Game.upstream.get("opened", false)) \
				else Game.open_upstream_case()
			if err != "":
				_toast(err)
			_refresh_contracts())
		urow.add_child(case_btn)
	var open_tickets: Array = []
	for t_i: Dictionary in Game.tickets:
		if String(t_i["state"]) != "closed":
			open_tickets.append(t_i)
	if not open_tickets.is_empty():
		contracts_box.add_child(_section("TICKETS"))
		contracts_box.add_child(_wrap("  Customers describe what they see, not what is wrong. Several of these may be one fault.",
			12, MUTED, 700))
		for t_i2: Dictionary in open_tickets:
			var trow := HBoxContainer.new()
			trow.add_theme_constant_override("separation", 8)
			contracts_box.add_child(trow)
			var tl := _wrap("  %s  %s: \"%s\"%s" % [t_i2["id"], t_i2["customer"], t_i2["text"],
				"   (reopened %d time(s))" % int(t_i2["reopened"]) if int(t_i2["reopened"]) > 0 else ""],
				12, Color(1.0, 0.82, 0.5) if String(t_i2["state"]) == "open"
				else Color(0.72, 0.84, 0.8), 520)
			tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			trow.add_child(tl)
			if String(t_i2["state"]) == "open":
				var tri := Button.new()
				tri.text = "Triage…"
				tri.tooltip_text = "Pick where to look. Looking in the wrong place costs an afternoon."
				tri.pressed.connect(func() -> void:
					_menu(tri, Game.TICKET_AREAS, func(id: int) -> void:
						var err: String = Game.triage_ticket(t_i2, String(Game.TICKET_AREAS[id]))
						if err != "":
							_toast(err)
						_refresh_contracts()
						_refresh_money()))
				trow.add_child(tri)
			var cbtn := Button.new()
			cbtn.text = "Close it"
			cbtn.tooltip_text = "Closing something that is still broken brings it back angrier."
			cbtn.pressed.connect(func() -> void:
				Game.close_ticket(t_i2)
				_refresh_contracts())
			trow.add_child(cbtn)
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
			if String(inc.get("by", "")) != "" and not inc.has("blame"):
				var brow := HBoxContainer.new()
				brow.add_theme_constant_override("separation", 8)
				contracts_box.add_child(brow)
				brow.add_child(_wrap("      The customer is on the phone. %s caused this."
					% ("You" if String(inc["by"]) == "you" else String(inc["by"])),
					13, Color(1.0, 0.72, 0.45), 420))
				for say: Array in Game.BLAME_CHOICES:
					var sbtn := Button.new()
					sbtn.text = String(say[1])
					sbtn.pressed.connect(func() -> void:
						Game.blame_incident(inc, String(say[0]))
						_refresh_contracts())
					brow.add_child(sbtn)
			elif inc.has("blame"):
				contracts_box.add_child(_label("      said: %s" % Game.blame_said(inc), 12, MUTED))
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
		if not ev.contains(Game.DIGEST_PREFIX):
			contracts_box.add_child(l)
			continue
		# a folded cycle: nothing is lost, it is one line until you ask
		var at := int(ev.substr(6, ev.find(":") - 6).strip_edges())
		var drow := HBoxContainer.new()
		drow.add_theme_constant_override("separation", 8)
		contracts_box.add_child(drow)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		drow.add_child(l)
		var open_btn := Button.new()
		open_btn.text = "Hide" if expanded_digest == at else "Read it"
		open_btn.pressed.connect(func() -> void:
			expanded_digest = -1 if expanded_digest == at else at
			_refresh_contracts())
		drow.add_child(open_btn)
		if expanded_digest == at:
			for folded: String in Game.digest_for(at):
				var fl := _label("      %s" % folded, 12, Color(0.62, 0.68, 0.78))
				fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				fl.custom_minimum_size = Vector2(560, 0)
				contracts_box.add_child(fl)

func _customer_eye_card(eye: Dictionary) -> PanelContainer:
	var state := String(eye.get("state", "waiting"))
	var semantic := "success"
	if state == "down":
		semantic = "danger"
	elif state in ["degraded", "waiting"]:
		semantic = "warning"
	var card := UIW.style_panel(PanelContainer.new(), "console", "lg")
	card.custom_minimum_size = Vector2(0, 188)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIW.space("md"))
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UIW.space("md"))
	box.add_child(head)
	var eyebrow := _section(String(eye.get("name", "CUSTOMER EYE")))
	eyebrow.add_theme_color_override("font_color", UIW.colour("accent"))
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(eyebrow)
	head.add_child(UIW.make_chip("%s  /  %s" % [String(eye.get("time", "NOW")), state.to_upper()], semantic))
	box.add_child(_wrap(String(eye.get("identity", "")), 13, UIW.colour("text"), 760))
	if String(eye.get("relationship", "")) != "":
		var story := HBoxContainer.new()
		story.add_theme_constant_override("separation", UIW.space("sm"))
		box.add_child(story)
		story.add_child(UIW.make_chip(String(eye["relationship"]), "warning"))
		var memory := _wrap(String(eye.get("memory", "")), 12, UIW.colour("muted"), 540)
		memory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		story.add_child(memory)
	var pulse := UIW.style_panel(PanelContainer.new(), "surface", "md")
	box.add_child(pulse)
	var pulse_box := VBoxContainer.new()
	pulse_box.add_theme_constant_override("separation", UIW.space("xs"))
	pulse.add_child(pulse_box)
	var metric := _label(String(eye.get("metric", "")), 15,
		Prefs.bad_colour() if state == "down" else UIW.colour("success") if state == "live" else UIW.colour("warm"))
	metric.add_theme_font_override("font", mono)
	pulse_box.add_child(metric)
	pulse_box.add_child(_wrap(String(eye.get("activity", "")), 12, UIW.colour("muted"), 720))
	var voice := _wrap(String(eye.get("voice", "")), 12, UIW.colour("warm"), 740)
	voice.add_theme_font_override("font", mono)
	box.add_child(voice)
	return card

func _build_jobs_tab() -> void:
	if not Game.night_call.is_empty():
		# the phone, ringing where the player already is
		var np := UIW.style_panel(PanelContainer.new(), "console", "md")
		contracts_box.add_child(np)
		var nb := VBoxContainer.new()
		nb.add_theme_constant_override("separation", UIW.space("sm"))
		np.add_child(nb)
		nb.add_child(_label("THE PHONE  /  OUT OF HOURS", 12, UIW.colour("warm")))
		nb.add_child(_wrap("“%s.”" % String(Game.night_call["reason"]).capitalize(), 14,
			UIW.colour("text_strong"), 620))
		var nrow := HBoxContainer.new()
		nrow.add_theme_constant_override("separation", 8)
		nb.add_child(nrow)
		var in_btn := Button.new()
		var oncall_now := Staff.by_name(Game.oncall)
		in_btn.text = "Get somebody in ($%d)" % (Game.CALLOUT_FEE / 2 if not oncall_now.is_empty()
			else Game.CALLOUT_FEE)
		in_btn.tooltip_text = "The person carrying the phone if there is one, otherwise whoever is best rested. They will be tired tomorrow."
		_accent(in_btn)
		in_btn.pressed.connect(func() -> void:
			var err := Game.answer_night_call(true)
			if err != "":
				_toast(err)
			_refresh_contracts()
			_refresh_money())
		nrow.add_child(in_btn)
		var wait_btn := Button.new()
		wait_btn.text = "It waits until morning"
		wait_btn.tooltip_text = "Costs nothing. Whatever it does overnight, it does."
		wait_btn.pressed.connect(func() -> void:
			Game.answer_night_call(false)
			_refresh_contracts())
		nrow.add_child(wait_btn)
	var customer_windows: Array = []
	for active_deal: Dictionary in Game.deals:
		var customer_view := Game.customer_eye(active_deal)
		if not customer_view.is_empty():
			customer_windows.append(customer_view)
	if not customer_windows.is_empty():
		var live_title := _section("CUSTOMER WINDOW  /  WHAT YOUR NETWORK IS CARRYING")
		live_title.add_theme_color_override("font_color", UIW.colour("warm"))
		contracts_box.add_child(live_title)
		for customer_view: Dictionary in customer_windows:
			contracts_box.add_child(_customer_eye_card(customer_view))
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
			var chip_txt := "BILLING"
			var chip_col := Color(0.4, 0.85, 0.5)
			var payment_copy := ""
			if not ok:
				var suspended := String(deal.get("payment_state", "waiting")) == "suspended"
				chip_txt = "SUSPENDED" if suspended else "WAITING"
				chip_col = Color(0.95, 0.45, 0.35)
				payment_copy = "   (service down: billing suspended)" if suspended \
					else "   (promise not delivered: no invoice yet)"
			elif deal.get("degraded", false):
				chip_txt = "SLOW"
				chip_col = Color(0.95, 0.75, 0.4)
				payment_copy = "   (congested: invoicing at half rate)"
			contracts_box.add_child(_chip_row(
				chip_txt,
				chip_col,
				"%s: %s   $%d/cycle%s" % [deal["customer"], Market.label_for(deal["kind"]), int(deal["fee"]),
					payment_copy],
				14, Color(0.55, 0.85, 0.62) if ok else Color(0.95, 0.6, 0.45)))
			if deal.has("call"):
				# somebody is on the phone: it waits here rather than interrupting
				var call_panel := UIW.style_panel(PanelContainer.new(), "console", "md")
				contracts_box.add_child(call_panel)
				var call_box := VBoxContainer.new()
				call_box.add_theme_constant_override("separation", UIW.space("sm"))
				call_panel.add_child(call_box)
				call_box.add_child(_label("THE PHONE  /  %s" % String(deal["customer"]).to_upper(),
					12, UIW.colour("warm")))
				call_box.add_child(_wrap("“%s”" % deal["call"]["words"], 14,
					UIW.colour("text_strong"), 620))
				var call_row := HBoxContainer.new()
				call_row.add_theme_constant_override("separation", 8)
				call_box.add_child(call_row)
				for option: Dictionary in Game.CALL_ANSWERS:
					var ob2 := Button.new()
					ob2.text = String(option["label"])
					ob2.tooltip_text = String(option["blurb"])
					ob2.pressed.connect(func() -> void:
						Game.answer_call(deal, String(option["id"]))
						_refresh_contracts())
					call_row.add_child(ob2)
			if deal.has("promised_by"):
				contracts_box.add_child(_label("      you promised them it would be back by cycle %d"
					% int(deal["promised_by"]), 12, Color(1.0, 0.82, 0.5)))
			var note_row := HBoxContainer.new()
			note_row.add_theme_constant_override("separation", 8)
			contracts_box.add_child(note_row)
			if not deal.get("note", {}).is_empty():
				note_row.add_child(_wrap("      note: \"%s\" (%d cycle(s) ago)"
					% [deal["note"]["text"], Game.deal_note_age(deal)], 12,
					Color(0.85, 0.8, 0.6), 520))
			var note_edit := LineEdit.new()
			note_edit.placeholder_text = "note about this customer (for you, never read by anything)"
			note_edit.custom_minimum_size = Vector2(320, 0)
			note_edit.text = String(deal.get("note", {}).get("text", ""))
			note_row.add_child(note_edit)
			var note_save := Button.new()
			note_save.text = "Keep"
			note_save.pressed.connect(func() -> void:
				Game.set_deal_note(deal, note_edit.text)
				_refresh_contracts())
			note_row.add_child(note_save)
			if deal.has("dispute"):
				var dis: Dictionary = deal["dispute"]
				var drow := HBoxContainer.new()
				drow.add_theme_constant_override("separation", 8)
				contracts_box.add_child(drow)
				drow.add_child(_label("      they are arguing: %s" % Game.dispute_kind(
					String(dis.get("kind", "")))["demand"], 13, Color(1.0, 0.72, 0.45)))
				if not bool(dis.get("warned", false)):
					var write_btn := Button.new()
					write_btn.text = "Put it in writing"
					write_btn.tooltip_text = "It does not stop the outage. It decides who wears it."
					write_btn.pressed.connect(func() -> void:
						Game.warn_customer(deal)
						_refresh_contracts())
					drow.add_child(write_btn)
				var give_btn := Button.new()
				give_btn.text = "Do it their way"
				give_btn.tooltip_text = "Keep the customer happy now."
				give_btn.pressed.connect(func() -> void:
					Game.concede_dispute(deal)
					_refresh_contracts())
				drow.add_child(give_btn)
				var firm_btn := Button.new()
				firm_btn.text = "Hold firm"
				firm_btn.tooltip_text = "Refuse. They may walk, and they may have been right."
				_accent(firm_btn)
				firm_btn.pressed.connect(func() -> void:
					Game.hold_firm(deal)
					_refresh_contracts())
				drow.add_child(firm_btn)
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
	var panel := UIW.style_panel(PanelContainer.new(), "console", "sm")
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

func _workshop_menu(at: Control) -> void:
	## Authored packs: what was found, what is in it, and how to get more.
	var rows: Array = Pack.workshop_rows()
	var opts: Array = []
	for row: Dictionary in rows:
		var summary: String = String(row["detail"])
		if bool(row["ok"]):
			summary = "%d scenario(s), by %s" % [row["scenarios"].size(), row["author"]]
		opts.append("%s %s — %s" % ["✓" if bool(row["ok"]) else "✗", row["name"], summary])
	opts.append("Reload packs from disk")
	opts.append("Import a pack from the clipboard")
	opts.append("Copy a diagnostic report")
	_menu(at, opts, func(id: int) -> void: _workshop_pick(id, rows))

func _workshop_pick(id: int, rows: Array) -> void:
	if id < rows.size():
		var row: Dictionary = rows[id]
		Game.log_event("PACK %s (%s)" % [row["name"], row["source"]])
		for line: String in row["scenarios"]:
			Game.log_event("  · %s" % line)
		for pack: Dictionary in Pack.loaded:
			if String(pack["id"]) != String(row["id"]):
				continue
			for scenario in pack["scenarios"]:
				for prev: String in Pack.preview(pack, scenario):
					Game.log_event("    %s" % prev)
		hud_toast("Pack details are in the log.", bool(row["ok"]))
		return
	if id == rows.size():
		Pack.load_all()
		var msg := "Reloaded: %d pack(s), %d problem(s)." % [Pack.loaded.size(),
			Pack.problems.size()]
		hud_toast(msg, Pack.problems.is_empty())
		return
	if id == rows.size() + 1:
		var err: String = Pack.import_text(DisplayServer.clipboard_get())
		hud_toast(err if err != "" else "Imported. It is in your contracts now.", err == "")
		return
	DisplayServer.clipboard_set(Pack.diagnostic_report())
	hud_toast("Diagnostics copied to the clipboard.", true)

func _toast(text: String) -> void:
	if _toast_lbl == null or not is_instance_valid(_toast_lbl):
		_toast_lbl = _label("", 14, Color(1.0, 0.85, 0.5))
		contracts_box.add_child(_toast_lbl)
		contracts_box.move_child(_toast_lbl, 0)
	_toast_lbl.text = text

func _build_contract_debrief(debrief: Dictionary) -> void:
	var card := UIW.style_panel(PanelContainer.new(), "surface", "lg")
	contracts_box.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIW.space("md"))
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UIW.space("md"))
	box.add_child(head)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_box)
	var eyebrow := _section("JOB COMPLETE  /  PROOF OF WORK")
	eyebrow.add_theme_color_override("font_color", UIW.colour("warm"))
	title_box.add_child(eyebrow)
	title_box.add_child(_label("%s  /  %s" % [debrief.get("title", "Contract"),
		debrief.get("customer", "customer")], 19, UIW.colour("text_strong")))
	head.add_child(UIW.make_chip("+$%d PAID" % int(debrief.get("reward", 0)), "success"))
	var proof := UIW.style_panel(PanelContainer.new(), "console", "md")
	box.add_child(proof)
	var proof_box := VBoxContainer.new()
	proof_box.add_theme_constant_override("separation", UIW.space("sm"))
	proof.add_child(proof_box)
	var proof_title := _section("LIVE SOLUTION SNAPSHOT")
	proof_title.add_theme_color_override("font_color", UIW.colour("accent"))
	proof_box.add_child(proof_title)
	for line: String in debrief.get("proof", []):
		var proof_line := _wrap("●  " + line, 12, UIW.colour("text"), 720)
		proof_line.add_theme_font_override("font", mono)
		proof_box.add_child(proof_line)
	var lessons := HBoxContainer.new()
	lessons.add_theme_constant_override("separation", UIW.space("sm"))
	box.add_child(lessons)
	lessons.add_child(_offer_fact("KEY CONCEPT", String(debrief.get("concept", "")), "accent"))
	lessons.add_child(_offer_fact("USEFUL PRACTICE", String(debrief.get("practice", "")), "info"))
	lessons.add_child(_offer_fact("FAILURE AVOIDED", String(debrief.get("avoided", "")), "warning"))
	var mastery := UIW.style_panel(PanelContainer.new(), "console", "md")
	box.add_child(mastery)
	var mastery_row := HBoxContainer.new()
	mastery_row.add_theme_constant_override("separation", UIW.space("md"))
	mastery.add_child(mastery_row)
	var mastered: bool = String(debrief.get("id", "")) in Game.mastered_contracts
	var mastery_copy := _wrap("%s  OPTIONAL MASTERY  /  %s" % ["●" if mastered else "◇",
		debrief.get("mastery", "")], 12,
		UIW.colour("success") if mastered else UIW.colour("muted"), 570)
	mastery_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mastery_row.add_child(mastery_copy)
	if not mastered:
		var mastery_btn := Button.new()
		mastery_btn.text = "Check mastery"
		mastery_btn.pressed.connect(func() -> void:
			var err := Game.check_contract_mastery(String(debrief["id"]))
			if err != "": _toast(err)
			_refresh_contracts())
		mastery_row.add_child(mastery_btn)
	var continue_btn := Button.new()
	continue_btn.text = "Continue operating"
	_accent(continue_btn)
	continue_btn.pressed.connect(func() -> void:
		Game.dismiss_contract_debrief()
		_refresh_contracts())
	box.add_child(continue_btn)

func _refresh_contracts() -> void:
	for c in contracts_box.get_children():
		c.queue_free()
	if not _feature_available(contracts_tab.to_lower()):
		contracts_tab = "Jobs"
	for k in contracts_tabs:
		contracts_tabs[k].visible = _feature_available(String(k).to_lower())
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
	if not Game.active_contract_debrief.is_empty():
		_build_contract_debrief(Game.active_contract_debrief)
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
		var contract_hint := Contracts.hint_for(c)
		if contract_hint != "":
			var hint_lbl := _label("", 13, Color(0.62, 0.75, 0.85))
			hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_lbl.custom_minimum_size = Vector2(560, 0)
			hint_lbl.visible = false
			var hint_btn := Button.new()
			hint_btn.text = "Stuck? Show me the commands"
			hint_btn.pressed.connect(func() -> void:
				Challenge.note_hint()
				hint_lbl.text = contract_hint
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
		if cur_dev != null and Game.locked_out(cur_dev):
			# it is running your new configuration and nothing can reach it
			cli_out.append_text("\n%% no route to %s: console server, a walk to the rack, or a site visit\n"
				% cur_dev.name)
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
	if cli_session != null and cur_dev != null and Game.locked_out(cur_dev):
		cli_out.append_text("% " + cur_dev.name + " is unreachable from here.\n")
		return
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
