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
var pedia_search: LineEdit
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
	"second_site": {
		"kicker": "NEW GROUND  /  A SECOND BUILDING",
		"title": "Everything you own is in one room.",
		"body": "A second floor costs a fit-out and rent, splits the crew and doubles the diary. What it buys is the one thing another rack cannot: a service that is still there when this room is not, which is what the customers who ask about fires are paying for.",
		"where": "COMPANY  /  MARKET", "action": "See what is available", "colour": "warm"},
	"oncall": {
		"kicker": "NEW ARRANGEMENT  /  THE PHONE",
		"title": "The room is empty and something can still break.",
		"body": "Somebody can carry the phone for a retainer. When it rings it is them, it costs half, and it costs them less, because that is what the retainer bought.",
		"where": "COMPANY  /  BUSINESS", "action": "Put somebody on call", "colour": "warm"},
	"handover": {
		"kicker": "NEW HABIT  /  THE HANDOVER",
		"title": "The shift going home left you a note.",
		"body": "What happened, what is still open, and what to look at first. Notes nobody reads stop being true, and the next shift finds out the hard way.",
		"where": "COMPANY  /  LOG", "action": "Read it", "colour": "accent"},
	"failover": {
		"kicker": "NEW EXERCISE  /  PROVING IT",
		"title": "Redundancy you have never tested is a belief.",
		"body": "Book a failover test. The upstream goes away on purpose, at a cycle you chose, and the result is judged on whether any customer noticed.",
		"where": "OPS  /  FACILITY", "action": "Book one", "colour": "accent"},
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
		"body": "This corner has proved itself. The next room brings more floor, and puts power and cooling on your books.",
		"where": "EXPAND  ·  TOP TOOLBAR", "action": "Point it out", "colour": "warm"},
}

var cur_rack: Net.Rack
var cur_dev: Net.NDevice
var cur_if: Net.Iface
var cli_session: CLI.Session
var cli_stack: Array = []  # ssh nesting
var cli_learn_btn: Button
var _last_cli_line := ""
var _revealed_hints := {}  # contract id -> true once "show me the commands" was pressed; a refresh keeps it
var cli_sessions := {}  # device -> {session, stack}: a console survives closing the panel, like SSH does (keyed by the object: renames happen)
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
var hud_nav_row: VBoxContainer
var hud_status_row: HBoxContainer
var hud_alert_btn: Button
var hud_learn_btn: Button
var hud_ops_btn: Button
var hud_map_btn: Button
var hud_shortcut_hint: Label
var hud_find_btn: Button
var sell_btn: Button
var settings_overlay: Control
var service_overlay: Control
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
	get_viewport().size_changed.connect(func() -> void: _fit_cards.call_deferred())
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
	dismiss.text = Loc.t("btn.got_it")
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
	var uk := "unlock." + _unlock_intro_active + "."  # the table is the English; the catalogue carries the rest
	unlock_intro_kicker.text = Loc.t(uk + "kicker") if Loc.CATALOG.has(uk + "kicker") else String(intro["kicker"])
	unlock_intro_kicker.add_theme_color_override("font_color", colour)
	unlock_intro_title.text = Loc.t(uk + "title") if Loc.CATALOG.has(uk + "title") else String(intro["title"])
	unlock_intro_body.text = Loc.t(uk + "body") if Loc.CATALOG.has(uk + "body") else String(intro["body"])
	unlock_intro_where.text = Loc.t(uk + "where") if Loc.CATALOG.has(uk + "where") else String(intro["where"])
	unlock_intro_action.text = Loc.t(uk + "action") if Loc.CATALOG.has(uk + "action") else String(intro["action"])
	unlock_intro_panel.modulate.a = 0.0
	unlock_intro_panel.visible = true
	Sfx.play("open")
	if Prefs.reduced_motion:
		unlock_intro_panel.modulate.a = 1.0
	else:
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
			_flash(expand_btn, Color(1.25, 1.12, 0.72), 0.7)
			hud_toast(Loc.t("toast.expand_ready"), true)

func _money_flash() -> void:
	Sfx.play("money")
	_flash(money_lbl, Color(1.6, 1.6, 1.2), 0.5)

func _flash(ctrl: CanvasItem, colour: Color, dur: float) -> void:
	## a brief tint that settles back to white, or nothing at all under reduced motion
	if Prefs.reduced_motion:
		ctrl.modulate = Color.WHITE
		return
	ctrl.modulate = colour
	create_tween().tween_property(ctrl, "modulate", Color.WHITE, dur)

func _customer_service_feedback(customer: String, state: String, fee: int) -> void:
	match state:
		"delivered":
			hud_toast(Loc.t("toast.service_live")
				% [customer, fee], true)
		"restored":
			hud_toast(Loc.t("toast.service_restored")
				% customer, true)
		"suspended":
			hud_toast(Loc.t("toast.payment_suspended")
				% customer)
	_refresh_tutorial()
	_refresh_open()

func _customer_cash_feedback(customer: String, state: String, amount: int) -> void:
	if state == "invoiced":
		hud_toast(Loc.t("toast.invoice_raised")
			% [customer, amount], true)
	elif state == "collected":
		hud_toast(Loc.t("toast.cash_arrived")
			% [customer, amount], true)
	_refresh_tutorial()
	_refresh_open()

func _refresh_attention() -> void:
	if contracts_btn == null: return
	var outages := 0
	for deal: Dictionary in Game.deals:
		if bool(deal.get("ever_healthy", false)) and not bool(deal.get("healthy", false)): outages += 1
	if Game.guided_outage_active(): outages = maxi(1, outages)
	contracts_btn.text = Loc.t("btn.customers")
	contracts_btn.modulate = Color.WHITE
	if hud_alert_btn:
		hud_alert_btn.visible = outages > 0 or not Game.offers.is_empty() or Game.unread_events > 0
		if outages > 0:
			var first_down := ""
			for deal: Dictionary in Game.deals:
				if bool(deal.get("ever_healthy", false)) and not bool(deal.get("healthy", false)):
					first_down = String(deal.get("customer", ""))
					break
			if Game.guided_outage_active() and first_down == "":
				first_down = "Kiskacsa Kft"
			hud_alert_btn.text = ("%s is down" % first_down) if outages == 1 and first_down != "" else "%d services need you" % outages
			UIW.style_button(hud_alert_btn, "danger")
			hud_alert_btn.tooltip_text = Loc.t("tip.incidents")
		elif not Game.offers.is_empty():
			hud_alert_btn.text = "%d opportunities" % Game.offers.size()
			UIW.style_button(hud_alert_btn, "quiet")
			hud_alert_btn.tooltip_text = Loc.t("tip.leads")
		else:
			hud_alert_btn.text = "%d updates" % Game.unread_events
			UIW.style_button(hud_alert_btn, "quiet")
			hud_alert_btn.tooltip_text = Loc.t("tip.activity")

func _refresh_hud_layout(width_override := -1.0) -> void:
	if hud_nav_row == null:
		return
	var width: float = width_override if width_override >= 0.0 \
		else get_viewport().get_visible_rect().size.x
	hud_compact = width < 1200.0  # 1280x720 is a target size: it keeps the full bar and the shortcut list
	hud_logo.visible = true
	hud_learn_btn.text = Loc.t("btn.field_manual")
	if hud_find_btn:
		hud_find_btn.text = Loc.t("btn.find_anything")
	mode_btns[0].text = Loc.t("btn.floor")
	mode_btns[0].tooltip_text = Loc.t("tip.select_mode")
	mode_btns[1].text = Loc.t("btn.build_rack")
	mode_btns[1].tooltip_text = Loc.t("tip.place_rack")
	objective_lbl.custom_minimum_size.x = 150 if hud_compact else 260
	clock_lbl.visible = width >= 1450
	site_btn.custom_minimum_size.x = 80 if hud_compact else 120
	hud_shortcut_hint.visible = not hud_compact
	_refresh_attention()
	_refresh_money()

func hud_toast(text: String, good := false) -> void:
	text = Loc.tidy(text)
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
	hud_msg_tween.tween_interval(2.6 if not Prefs.reduced_motion else 3.4)
	if Prefs.reduced_motion:
		hud_msg_tween.tween_callback(func() -> void: hud_msg.modulate.a = 0.0)
	else:
		hud_msg_tween.tween_property(hud_msg, "modulate:a", 0.0, 0.8)

func _refresh_speed() -> void:
	for k in speed_btns:
		speed_btns[k].button_pressed = (k == Game.speed)

func _refresh_money() -> void:
	_refresh_speed()
	_refresh_attention()
	# the banner belongs to the drill, not to whoever happened to end it
	if drill_panel and drill_panel.visible and not Game.drill_active:
		drill_panel.visible = false
	if objective_lbl:
		var next_c := ""
		for c in Contracts.all():
			if c["id"] not in Game.contracts_done:
				next_c = Loc.t(String(c["title"]))
				break
		if next_c != "":
			objective_lbl.text = ("%s  ·  NEXT  %s" % [Demo.progress_text(), next_c]) if Demo.active() \
				else "NEXT  " + next_c
		else:
			var nr := Game.next_rank()
			objective_lbl.text = "★ %s" % Loc.t(Game.rank()) if nr.is_empty() \
				else "★ %s  ·  $%d to %s" % [Loc.t(Game.rank()), int(nr[1]), Loc.t(String(nr[0]))]
			var qgoal := Game.next_quarter_goal()
			if qgoal != "":
				objective_lbl.text = "TARGET  ·  %s" % qgoal
		# an outage or a hazard outranks everything else on this line: the
		# wall sign, the brief and the HUD must never disagree about it
		if Game.customer_down_now() or not Game.hazards.is_empty():
			var down := 0
			for deal in Game.deals:
				if not bool(deal.get("healthy", false)):
					down += 1
			if down == 0 and Game.guided_outage_active():
				down = 1  # the teaching outage is a real customer off the air
			if not Game.hazards.is_empty():
				var h: Dictionary = Game.hazards[0]
				objective_lbl.text = "HAZARD  ·  %s in %s  (click: Facility)" % [Loc.t(String(Game.HAZARD_KINDS[h["kind"]]["label"])), h["rack"]]
			else:
				objective_lbl.text = "OUTAGE  ·  %d customer%s off the air" % [down, "" if down == 1 else "s"]
		elif FirstCustomer.active():
			var arc := FirstCustomer.state()
			var phase := String(arc.get("phase", "planning"))
			var status := Loc.t("brief.choose_plan")
			if phase == "countdown": status = Loc.t("brief.starts_in") % maxi(0, int(arc["starts"]) - Game.cycle)
			elif phase == "live": status = Loc.t("brief.live_wave") % mini(3, Game.cycle - int(arc["starts"]) + 1)
			elif phase == "debrief": status = Loc.t("brief.carried") % int(arc["successes"])
			objective_lbl.text = Loc.t("brief.title") + "  ·  " + status
		else:
			var quiet_line := Game.housekeeping_suggestion()
			if quiet_line != "":
				objective_lbl.text = "QUIET  ·  %s" % quiet_line
		# the alert chip sits right after this label and eats its tail; say
		# so with an ellipsis and keep the whole line on hover
		objective_lbl.tooltip_text = objective_lbl.text
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
		clock_lbl.tooltip_text = Loc.t("tip.clock")
	var power := ""
	if Game.stage >= 1:
		power = "  ⚡%d/❄%d" % [Game.power_draw(), Game.cooling_capacity()]
		if Game.overheating():
			power += " 🔥"
	var debt_s := ("  (debt $%d)" % Game.debt) if Game.debt > 0 else ""
	money_lbl.text = "%s$%d%s  ♦%d%s" % ["SANDBOX  " if Game.sandbox else "",
		Game.money, debt_s, Game.reputation, power]
	if Game.stage >= 1:
		money_lbl.tooltip_text = Loc.t("tip.money_power") % [
			Game.power_draw_all(), Game.effective_draw(), Game.energy_rate(), Game.power_bill(),
			Game.cooling_capacity()]
	else:
		money_lbl.tooltip_text = Loc.t("tip.cash")
	money_lbl.add_theme_color_override("font_color",
		UIW.colour("danger") if Game.overheating() else UIW.colour("success"))
	if site_btn:
		site_btn.text = "AT  %s  ▾" % Game.site_name(Game.current_site).to_upper()
		site_btn.visible = Game.site_count() > 1
		# the same colour the floor itself is cast in, so the button and the
		# room agree about which building you are in
		site_btn.add_theme_color_override("font_color",
			Color.from_hsv(Game.site_hue(Game.current_site), 0.45, 1.0))
	if Game.current_site != 0:
		expand_btn.visible = false  # acquired floors come as they are
	elif Game.stage < Game.STAGES.size() - 1:
		var nxt: Dictionary = Game.STAGES[Game.stage + 1]
		expand_btn.text = ("+$%d" if hud_compact else "Expand ($%d)") % int(nxt["price"])
		expand_btn.disabled = Game.money < int(nxt["price"])
		expand_btn.tooltip_text = Loc.t(String(nxt["blurb"])) if not expand_btn.disabled \
			else Loc.t("%s   You are $%d short.") % [Loc.t(String(nxt["blurb"])), int(nxt["price"]) - Game.money]
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
	WorkspaceShell.refresh_navigation(self)
	# The live brief belongs to the floor, not on top of focused workspaces.
	# Remember whether we hid it so it can return after the overlay closes.
	if tutorial_panel:
		var crowded := get_viewport().get_visible_rect().size.x < 1480 or map_overlay.visible or welcome_overlay.visible or demo_overlay.visible or menu_overlay.visible
		for scroll in _card_scrolls:
			if is_instance_valid(scroll) and scroll.is_visible_in_tree() and not scroll.has_meta("customer_brief"):
				crowded = crowded or scroll.get_parent().get_global_rect().end.x > tutorial_panel.get_global_rect().position.x - 16
		if is_open() and crowded:
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

func close_everything() -> void:
	## Put the interface back to the bare floor. The screenshot harness needs a
	## known state, and a panel left open by the last shot silently blocks the
	## next one from opening anything.
	for panel in [rack_overlay, dev_overlay, if_overlay, contracts_overlay, welcome_overlay,
			map_overlay, menu_overlay, pedia_overlay, help_overlay, ops_overlay,
			search_overlay, demo_overlay, settings_overlay, service_overlay]:
		if panel != null and is_instance_valid(panel):
			panel.visible = false
	cur_dev = null
	cur_rack = null

func is_open() -> bool:
	return rack_overlay.visible or dev_overlay.visible or if_overlay.visible \
		or contracts_overlay.visible or welcome_overlay.visible or map_overlay.visible \
		or menu_overlay.visible or pedia_overlay.visible or help_overlay.visible \
		or ops_overlay.visible or search_overlay.visible or demo_overlay.visible \
		or (settings_overlay != null and is_instance_valid(settings_overlay) and settings_overlay.visible) \
		or (service_overlay != null and is_instance_valid(service_overlay) and service_overlay.visible)

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
	text = Loc.tidy(text)
	## a label that wraps instead of pushing its container sideways
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label reports the height of one line as its minimum, so a card
	# full of paragraphs was sized for a fraction of its content and then had
	# nothing to scroll: the bottom of the panel was unreachable. Measure the
	# wrapped height at the width we are about to give it.
	var font := l.get_theme_font("font")
	if font == null:
		font = UIW.sans_font()
	var wrapped := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, size)
	l.custom_minimum_size = Vector2(width, maxf(wrapped.y, float(size)))
	return l

func _label(text: String, size := 15, color := Color(0.85, 0.89, 0.95)) -> Label:
	text = Loc.tidy(text)
	var l := UIW.make_text(text)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _accent(b: Button) -> Button:
	return UIW.style_button(b, "primary")


func _on_off(on: bool) -> String:
	return Loc.t("settings.on") if on else Loc.t("settings.off")

func _section(text: String) -> Label:
	## the heading is written in English in the code and is the section's id;
	## what is shown follows the language when the catalogue has it
	var key := "section." + Loc.slug(text)
	var lbl := UIW.make_section(Loc.t(key) if Loc.CATALOG.has(key) else text)
	lbl.set_meta("section_id", text)
	return lbl

func _show_overlay(o: Control) -> void:
	Sfx.play("open")
	# Ordinary workspaces leave the persistent rail and clock reachable.
	# The rest of the scrim still consumes clicks, including bare floor.
	if o not in [welcome_overlay, demo_overlay, menu_overlay, settings_overlay]:
		var scrim := o.get_child(0) as ColorRect
		if scrim != null:
			scrim.offset_left = 176
			scrim.offset_top = card_top()
	o.modulate.a = 0.0
	o.visible = true
	_fit_cards.call_deferred()
	if Prefs.reduced_motion:
		o.modulate.a = 1.0
	else:
		create_tween().tween_property(o, "modulate:a", 1.0, 0.13)

func _mono_edit(width := 200.0) -> LineEdit:
	var e := LineEdit.new()
	e.custom_minimum_size = Vector2(width, 0)
	e.add_theme_font_override("font", mono)
	return e

func _overlay() -> Control:
	var o := Control.new()
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.visible = false
	o.theme = theme_res
	var bg := ColorRect.new()
	bg.color = DIM
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # the dim swallows clicks; the floor under a card is not clickable
	o.add_child(bg)
	add_child(o)
	return o

var _card_scrolls: Array = []  # ScrollContainers to fit to the viewport

const CARD_TOP := 72.0  # the fallback hang edge before the HUD has been laid out
var _hangs: Array = []  # every card's margin container, refitted when the HUD changes height

func card_top() -> float:
	## just under the HUD, whatever height it laid out at
	if hud_bar != null and hud_bar.size.y > 0.0:
		return hud_bar.size.y + 8.0
	return CARD_TOP

func _refit_hangs() -> void:
	_hangs = _hangs.filter(func(h): return is_instance_valid(h))  # rebuilt overlays leave dead entries behind
	for h in _hangs:
		if is_instance_valid(h):
			h.add_theme_constant_override("margin_top", int(card_top()))

func _card(parent: Control, min_w: float) -> VBoxContainer:
	var hang := MarginContainer.new()
	hang.set_anchors_preset(Control.PRESET_FULL_RECT)
	hang.add_theme_constant_override("margin_top", int(card_top()))
	hang.add_theme_constant_override("margin_left", 184)
	hang.add_theme_constant_override("margin_right", 24)
	hang.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hangs.append(hang)
	parent.add_child(hang)
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_BEGIN
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hang.add_child(center)
	var panel := UIW.CommandPanel.new().setup("overlay", "accent", UIW.space("lg"))
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(min_w, 0)
	scroll.set_meta("preferred_width", min_w)
	scroll.add_theme_constant_override("scrollbar_v_separation", UIW.space("md"))
	panel.add_child(scroll)
	panel.add_child(_more_hint(scroll))
	_card_scrolls.append(scroll)
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_right", UIW.space("lg"))
	content_margin.add_theme_constant_override("margin_bottom", UIW.space("sm"))
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content_margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UIW.space("md"))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_child(v)
	return v

func _more_hint(scroll: ScrollContainer) -> Label:
	## A scroll that clips a button must look scrollable: a bar you can see,
	## and a "more below" hint over the bottom edge until the end is reached.
	## Add the label as a sibling drawn after the scroll.
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 10
	var more := _label(Loc.t("body.more_below"), 11, UIW.colour("accent"))
	more.size_flags_vertical = Control.SIZE_SHRINK_END
	more.size_flags_horizontal = Control.SIZE_SHRINK_END
	more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	more.visible = false
	var update_more := func() -> void:
		more.visible = bar.max_value - bar.page > 1.0 and bar.value + bar.page < bar.max_value - 1.0
	bar.value_changed.connect(func(_v: float) -> void: update_more.call())
	bar.changed.connect(update_more)
	return more

func _scroll_to_bottom() -> void:
	_fit_cards()
	for scroll: ScrollContainer in _card_scrolls:
		if scroll.is_visible_in_tree() and not scroll.has_meta("customer_brief"):
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func _fit_cards() -> void:
	## keep every card inside the window; content beyond that scrolls
	_card_scrolls = _card_scrolls.filter(func(s): return is_instance_valid(s))  # rebuilt overlays leave dead entries behind
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
		# Autowrapped labels report the minimum height of a single line, so the
		# minimum-size sum understates a panel full of paragraphs: the card was
		# sized too short AND believed it had nothing to scroll, which put the
		# bottom of the panel out of reach entirely. Measure what was actually
		# laid out and take whichever is larger.
		need_y = maxf(need_y, _laid_out_height(content))
		if scroll.has_meta("customer_brief"):
			scroll.custom_minimum_size = Vector2(308, minf(need.y, vp.y - 200.0))
		else:
			scroll.custom_minimum_size = Vector2(
				minf(maxf(need.x, float(scroll.get_meta("preferred_width", 640))), vp.x - 280.0),
				minf(need_y, vp.y - card_top() - 60.0))

func _laid_out_height(content: Control) -> float:
	## The real height of what is in a card, after layout, including text that
	## wrapped onto more lines than its minimum size admitted to.
	var tallest := content.size.y
	for child in content.get_children():
		if child is Control and (child as Control).visible:
			var inner := child as Control
			var sum := 0.0
			for row in inner.get_children():
				if row is Control and (row as Control).visible:
					sum += (row as Control).size.y
			if inner is VBoxContainer:
				sum += maxf(0.0, float(inner.get_child_count() - 1)) \
					* float(inner.get_theme_constant("separation"))
			tallest = maxf(tallest, maxf(sum, inner.size.y))
	return tallest

func _header(box: VBoxContainer, on_back: Callable) -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)
	var title := _label("", 24, UIW.colour("text_strong"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title)
	var back := Button.new()
	back.text = Loc.t("btn.close_esc")
	UIW.style_button(back, "quiet")
	back.pressed.connect(on_back)
	h.add_child(back)
	title.set_meta("back", back)  # so a card stacked on top can hide the one underneath
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
	var cap := _label(Loc.t("body.handover_note"), 10, Color("51462d"))
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
	edit.placeholder_text = Loc.t("ph.handover_note")
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

var hud_bar: PanelContainer

func _build_toolbar() -> void:
	WorkspaceShell.build(self)

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
	rack_metrics.add_child(_rack_metric(Loc.t("rack.metric.load"), "units", "accent"))
	rack_metrics.add_child(_rack_metric(Loc.t("rack.metric.power"), "power", "warm"))
	rack_metrics.add_child(_rack_metric(Loc.t("rack.metric.feeds"), "feeds", "success"))
	rack_airflow_lbl = _label("", 11, UIW.colour("success"))
	rack_airflow_lbl.add_theme_font_override("font", mono)
	v.add_child(rack_airflow_lbl)
	var info_row := HBoxContainer.new()
	v.add_child(info_row)
	var info := _label(Loc.t("rack.info"), 13, MUTED)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 540
	v.add_child(info)
	rack_note_btn = Button.new()
	rack_note_btn.text = "✎ LEAVE NOTE"
	rack_note_btn.tooltip_text = Loc.t("rack.note.tip")
	rack_note_btn.pressed.connect(func() -> void: _open_note_card(rack_note_ui))
	info_row.add_child(rack_note_btn)
	var bp_btn := Button.new()
	bp_btn.text = Loc.t("rack.blueprints")
	bp_btn.tooltip_text = Loc.t("rack.blueprints.tip")
	bp_btn.pressed.connect(func() -> void:
		var opts: Array = [Loc.t("rack.blueprints.save")]
		var usable: Array = []
		for b: Dictionary in Game.blueprints:
			opts.append(Loc.t("rack.blueprints.build", {"name": b["name"], "price": Game.blueprint_price(b)}))
			usable.append(b)
		_menu(bp_btn, opts, func(id: int) -> void:
			if id == 0:
				var err: String = Game.save_blueprint(cur_rack, Game.unique_name("rack %s layout" % cur_rack.name, Game.blueprints))
				hud_toast(err if err != "" else Loc.t("rack.blueprints.saved"), err == "")
			else:
				var err2: String = Game.apply_blueprint(cur_rack, usable[id - 1])
				hud_toast(err2 if err2 != "" else Loc.t("rack.blueprints.built"), err2 == "")
			_refresh_slots()))
	info_row.add_child(bp_btn)
	var service_btn := Button.new()
	service_btn.text = Loc.t("rack.services")
	service_btn.tooltip_text = Loc.t("rack.services.tip")
	service_btn.pressed.connect(_open_service_standards)
	info_row.add_child(service_btn)
	var sell := Button.new()
	sell_btn = sell
	sell.text = Loc.t("rack.sell", {"price": Game.RACK_PRICE / 2})
	sell.tooltip_text = Loc.t("rack.sell.tip")
	sell.pressed.connect(func() -> void:
		if Game.sell_rack(cur_rack):
			hud_toast(Loc.t("rack.sold", {"price": Game.RACK_PRICE / 2}), true)
			close_rack()
		else:
			hud_toast(Loc.t("rack.sell.full"), false))
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

func _open_service_standards() -> void:
	var target := cur_rack
	if target == null: return
	if service_overlay != null and is_instance_valid(service_overlay): service_overlay.queue_free()
	service_overlay = _overlay()
	var box := _card(service_overlay, 660)
	_header(box, func() -> void: service_overlay.visible = false).text = Loc.t("rack.services")
	box.add_child(_wrap(Loc.t("services.lede"), 17, UIW.colour("text"), 600))
	box.add_child(_wrap(Loc.t("service.first_standard"), 14, UIW.colour("muted"), 600))
	var save := WorkspaceShell.button(Loc.t("services.save"), func() -> void:
		var err := ServiceDesign.capture(target, target.name + " customer LAN")
		hud_toast(err if err != "" else Loc.t("services.saved"), err == "")
		if err == "": _open_service_standards())
	box.add_child(save)
	var designs: Array = Game.blueprints.filter(func(b): return b.has("service"))
	if designs.is_empty():
		box.add_child(UIW.make_empty_state(Loc.t("services.none")))
	else:
		box.add_child(_section(Loc.t("services.deploy_into", {"rack": target.name})))
		var choose := OptionButton.new()
		for design: Dictionary in designs: choose.add_item(String(design["name"]))
		box.add_child(choose)
		var address := LineEdit.new()
		address.text = "10.80.0"
		address.placeholder_text = Loc.t("services.prefix.placeholder")
		box.add_child(_label(Loc.t("services.prefix")))
		box.add_child(address)
		var vlan := SpinBox.new()
		vlan.min_value = 1
		vlan.max_value = 4094
		vlan.value = 100
		box.add_child(_label(Loc.t("services.vlan")))
		box.add_child(vlan)
		var preview := _wrap("", 15, UIW.colour("text"), 600)
		box.add_child(preview)
		var deploy := WorkspaceShell.button(Loc.t("services.deploy"), func() -> void:
			var err := ServiceDesign.deploy(target, designs[choose.selected], address.text, int(vlan.value))
			hud_toast(err if err != "" else Loc.t("services.deployed"), err == "")
			_refresh_slots()
			_open_service_standards(), true)
		box.add_child(deploy)
		var refresh := func() -> void:
			var result := ServiceDesign.preview(target, designs[choose.selected], address.text, int(vlan.value))
			preview.text = String(result["why"])
			deploy.disabled = not bool(result["ok"])
		choose.item_selected.connect(func(_i: int) -> void: refresh.call())
		address.text_changed.connect(func(_s: String) -> void: refresh.call())
		vlan.value_changed.connect(func(_v: float) -> void: refresh.call())
		refresh.call()
	_show_overlay(service_overlay)

func _rack_metric(caption: String, key: String, semantic: String) -> PanelContainer:
	var panel := UIW.style_panel(PanelContainer.new(), "console", "sm")
	panel.custom_minimum_size = Vector2(190, 60)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIW.space("xs"))
	panel.add_child(box)
	var cap := _section(caption)
	box.add_child(cap)
	var value := _label("…", 13, UIW.colour(semantic))
	value.add_theme_font_override("font", mono)
	box.add_child(value)
	rack_metric_values[key] = value
	return panel

func open_rack(r: Net.Rack) -> void:
	cur_rack = r
	dev_overlay.visible = false
	rack_title.text = Loc.t("btn.rack_named") % r.name
	_refresh_note_card(rack_note_ui, r, rack_note_btn)
	_refresh_slots()
	_show_overlay(rack_overlay)

func close_rack() -> void:
	rack_overlay.visible = false
	cur_rack = null

func _refresh_slots() -> void:
	if rack_cable_from != null and rack_cable_layer.active:
		rack_cable_layer.finish()  # a refresh mid-pull: the slot that owns the drag is about to be freed, so end the pull and draw the cable again
		rack_cable_from = null
		rack_cable_old_link = null
	if sell_btn != null and cur_rack != null:
		var installed := 0
		for slot_dev in cur_rack.slots:
			if slot_dev != null:
				installed += 1
		sell_btn.disabled = installed > 0
		sell_btn.tooltip_text = Loc.t("tip.sell_empty_only") if installed == 0 \
			else Loc.t("tip.sell_empty_first") % installed
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
	var gaps := Net.Rack.SLOTS - occupied  # the same unit the elevation draws in
	var blanks := 0
	for slot_i in Net.Rack.SLOTS:
		if cur_rack.slots[slot_i] == null and not cur_rack.covered.has(slot_i):
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
		hud_toast((Loc.t("toast.blank_fitted") if fitted \
			else Loc.t("toast.blank_removed")) % (slot + 1), fitted)
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
	if target != null and target == original_target:  # a fresh cable dropped on nothing has no original to reseat
		hud_toast(Loc.t("toast.plug_reseated") % [target.dev.name, target.name], true)
		rack_cable_layer.confirm(rack_cable_from, target)
	elif target and Game.can_link(rack_cable_from, target):
		var ran := false
		if rack_cable_old_link:
			ran = Game.move_link(rack_cable_from, target)  # the same lead, re-dressed
		elif Game.cabling_documented:
			ran = Game.connect_documented(rack_cable_from, target)
		else:
			ran = Game.connect_ifaces(rack_cable_from, target)
		if ran:
			hud_toast(Loc.t("toast.cable_run") % [rack_cable_from.dev.name,
				rack_cable_from.name, target.dev.name, target.name], true)
		else:
			hud_toast(Loc.t("toast.no_lead"), false)  # the drawer, the money or the jack said no; nothing was unplugged
		_refresh_slots()
		rack_cable_layer.confirm(rack_cable_from, target)
	elif rack_cable_old_link:
		var loose_end := original_target
		Game.disconnect_iface(rack_cable_from)
		hud_toast(Loc.t("toast.unplugged") % [rack_cable_from.dev.name,
			rack_cable_from.name, loose_end.dev.name, loose_end.name], true)
		_refresh_slots()
	else:
		rack_cable_layer.reject(screen_pos, _rack_cable_reject_reason(screen_pos))
		hud_toast(Loc.t("toast.drop_free_port"))
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
			line += "   🔒 needs %s" % Loc.t(String(Game.STAGES[int(mod["tier"])]["name"]))
		elif not fits:
			line += "   ✋ needs %dU here" % height
		m.add_item(line)
		m.set_item_disabled(m.item_count - 1, locked or not fits)
	add_child(m)
	m.id_pressed.connect(func(id: int) -> void:
		var mod2: Dictionary = Game.MODELS[keys[id]]
		if int(mod2.get("tier", 0)) > Game.stage:
			hud_toast(Loc.t("toast.needs_stage") % [mod2["label"],
				Loc.t(String(Game.STAGES[int(mod2["tier"])]["name"]))])
			return
		if not Game.can_install(cur_rack, slot, keys[id]):
			hud_toast(Loc.t("toast.will_not_fit") % [mod2["label"],
				Game.model_height(keys[id])])
			return
		if not Game.try_buy_device(String(keys[id])):
			if Game.stocked_out(String(keys[id])):
				hud_toast(Loc.t("toast.back_order") % [
					mod2["label"], int(Game.stockouts[String(keys[id])])])
				return
			var available := Game.money + Game.delivery_credit_for_model(String(keys[id]))
			hud_toast(Loc.t("toast.not_enough_money") % [
				mod2["label"], Game.shop_price(String(keys[id])), available])
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
	# the actions sit under the hostname, above the faceplate and the port
	# list, so a long port list or a handover note never pushes them out of view
	var btn_row := HFlowContainer.new()
	btn_row.add_theme_constant_override("h_separation", 8)
	btn_row.add_theme_constant_override("v_separation", 8)
	v.add_child(btn_row)
	name_row.add_child(_label(Loc.t("dev.hostname") + ":  ", 14, MUTED))
	name_edit = _mono_edit(220)
	name_edit.placeholder_text = Loc.t("ph.hostname")
	name_edit.text_submitted.connect(_rename_dev)
	name_edit.focus_exited.connect(func() -> void:
		if cur_dev != null and name_edit.text.strip_edges() != cur_dev.name:
			name_edit.text = cur_dev.name)  # Enter applies, as the placeholder says; leaving reverts
	name_row.add_child(name_edit)
	name_row.add_child(_label(Loc.t("body.status_prefix"), 14, MUTED))
	status_opt = OptionButton.new()
	status_opt.add_item("active")
	status_opt.add_item("offline")
	status_opt.item_selected.connect(func(idx: int) -> void:
		cur_dev.status = "active" if idx == 0 else "offline"
		Game.topology_changed.emit())
	name_row.add_child(status_opt)
	name_row.add_child(_label(Loc.t("body.power_prefix"), 14, MUTED))
	psu_opt = OptionButton.new()
	for feed in ["A", "B", "AB"]:
		psu_opt.add_item("feed " + feed if feed != "AB" else "both feeds")
	psu_opt.tooltip_text = Loc.t("dev.psu.tip")
	psu_opt.item_selected.connect(func(idx: int) -> void:
		var err := Game.set_psu(cur_dev, ["A", "B", "AB"][idx])
		if err != "":
			_toast(err)
		_refresh_dev_header())
	name_row.add_child(psu_opt)
	name_hint = _label("", 13, Color(0.9, 0.5, 0.45))
	name_row.add_child(name_hint)

	v.add_child(_section(Loc.t("dev.section.front")))
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
	vlan_section.add_child(_section(Loc.t("dev.section.vlans")))
	vlan_box = VBoxContainer.new()
	vlan_section.add_child(vlan_box)

	dev_note_btn = Button.new()
	dev_note_btn.text = "✎ LEAVE NOTE"
	dev_note_btn.tooltip_text = Loc.t("dev.note.tip")
	dev_note_btn.pressed.connect(func() -> void: _open_note_card(dev_note_ui))
	btn_row.add_child(dev_note_btn)
	cli_toggle = Button.new()
	cli_toggle.text = Loc.t("dev.console.open") + "  ▤"
	_last_cli_line = ""
	if cli_learn_btn != null:
		cli_learn_btn.visible = false  # the chip belongs to what was typed here, not on the last box
	cli_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cli_toggle.pressed.connect(_toggle_cli)
	btn_row.add_child(cli_toggle)
	var cli_size_btn := Button.new()
	cli_size_btn.text = "▤ taller"
	cli_size_btn.tooltip_text = Loc.t("dev.console.size.tip")
	cli_size_btn.pressed.connect(func() -> void:
		if cli_session != null:
			cli_session.term_length = 0  # the button takes over from terminal length
		cli_rows_step = (cli_rows_step + 1) % 3
		cli_size_btn.text = ["▤ taller", "▤ tallest", "▤ shorter"][cli_rows_step]
		if cli_box.visible:
			cli_out.custom_minimum_size.y = _console_height()
			_fit_cards.call_deferred()
			_ensure_visible.call_deferred(cli_in))
	btn_row.add_child(cli_size_btn)
	cli_learn_btn = Button.new()
	cli_learn_btn.text = "LEARN ↗"
	cli_learn_btn.tooltip_text = Loc.t("dev.learn.tip")
	cli_learn_btn.visible = false
	cli_learn_btn.pressed.connect(func() -> void:
		var topic := CLI.topic_for(_last_cli_line)
		open_pedia()
		var topics := Pedia.topics()
		for ti in topics.size():
			if String(topics[ti][0]) == topic:
				_show_pedia_entry(ti)
				return)
	btn_row.add_child(cli_learn_btn)
	cap_toggle = Button.new()
	cap_toggle.text = Loc.t("btn.packets")
	cap_toggle.tooltip_text = Loc.t("dev.capture.tip")
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
	template_btn.text = Loc.t("dev.templates")
	template_btn.tooltip_text = Loc.t("dev.templates.tip")
	template_btn.pressed.connect(func() -> void:
		var opts: Array = [Loc.t("opt.save_template")]
		var applicable: Array = []
		for t: Dictionary in Game.templates:
			if t["type"] == cur_dev.type:
				opts.append("Apply '%s'" % t["name"])
				applicable.append(t)
		_menu(template_btn, opts, func(id: int) -> void:
			if id == 0:
				Game.save_template(cur_dev, Game.unique_name("%s standard" % cur_dev.type, Game.templates))
				hud_toast(Loc.t("toast.saved_template") % cur_dev.type, true)
			else:
				var err: String = Game.apply_template(cur_dev, applicable[id - 1])
				hud_toast(err if err != "" else Loc.t("toast.template_applied") % cur_dev.name, err == "")
			_refresh_ports()))
	btn_row.add_child(template_btn)
	save_cfg_btn = Button.new()
	save_cfg_btn.text = Loc.t("btn.save_config")
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
	confirm_btn.text = Loc.t("btn.arm_confirmed_commit")
	confirm_btn.tooltip_text = Loc.t("tip.confirmed_commit")
	confirm_btn.pressed.connect(func() -> void:
		var err: String = Game.arm_confirm(cur_dev) if not Game.confirm_commits.has(cur_dev.name) \
			else Game.confirm_commit(cur_dev)
		if err != "":
			_toast(err)
		else:
			hud_toast(Loc.t("toast.confirmed_commit") % [
				"armed" if Game.confirm_commits.has(cur_dev.name) else "confirmed", cur_dev.name],
				true))
	btn_row.add_child(confirm_btn)
	if Game.site_count() > 1:
		var move_btn := Button.new()
		move_btn.text = Loc.t("btn.send_other_floor")
		move_btn.tooltip_text = Loc.t("tip.send_floor")
		move_btn.pressed.connect(func() -> void:
			var move_targets: Array = []
			var move_names: Array = []
			for si in Game.site_count():
				if si == Game.site_of_device(cur_dev):
					continue
				move_targets.append(si)
				move_names.append("%s   (%d cycle(s) in transit)" % [Game.site_name(si),
					Game.TRANSIT_CYCLES])
			_menu(move_btn, move_names, func(id: int) -> void:
				var err := Game.send_device_to(cur_dev, int(move_targets[id]))
				if err != "":
					_toast(err)
				else:
					close_dev()
					get_parent().rebuild_racks()))
		btn_row.add_child(move_btn)
	var uninstall := Button.new()
	uninstall.text = Loc.t("btn.decommission")
	uninstall.tooltip_text = Loc.t("tip.decommission")
	uninstall.pressed.connect(func() -> void:
		_menu(uninstall, [
			"Properly: wipe and certify, strip the cabling, reclaim the addresses (best resale)",
			"Wipe it, leave the rest (less back, and the addresses linger)",
			Loc.t("opt.pull_out"),
			Loc.t("opt.hand_technician"),
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
			hud_toast(Loc.t("toast.decommissioned") % [int(out["value"]),
				"" if out["skipped"].is_empty() else "  Skipped %d step(s)." % out["skipped"].size()],
				out["skipped"].is_empty())
			_refresh_money()
			if cur_rack:
				_show_overlay(rack_overlay)))
	btn_row.add_child(uninstall)
	var hands := Button.new()
	hands.text = Loc.t("btn.remote_hands")
	hands.tooltip_text = Loc.t("tip.remote_hands")
	hands.pressed.connect(func() -> void:
		var dev := cur_dev
		var facility: Dictionary = Game.remote_facility(
			int(Game.rack_of(dev).site) if Game.rack_of(dev) != null else 0)
		_menu(hands, [
			Loc.t("opt.reseat_cable") % int(facility["cost"]),
			Loc.t("opt.power_cycle") % int(facility["cost"]),
			Loc.t("opt.look_lights") % int(facility["cost"]),
		], func(id: int) -> void:
			var action: String = ["reseat", "power_cycle", "check"][id]
			var err: String = Game.request_remote_hands(dev, action,
				cur_if if cur_if != null and cur_if.dev == dev else null)
			hud_toast(err if err != "" else Loc.t("toast.booked_hands")
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
	cli_toggle.text = Loc.t("dev.console.open") + "  ▤"
	_refresh_ports()
	_show_overlay(dev_overlay)

func close_dev() -> void:
	dev_overlay.visible = false
	cur_dev = null

func _refresh_dev_header() -> void:
	var away := Game.elsewhere(cur_dev)
	dev_title.text = "%s  /  %s: %s%s" % [Game.rack_of(cur_dev).name, cur_dev.name,
		Game.MODELS[cur_dev.model]["label"],
		"" if away == "" else "   ⚑ AT %s, NOT THIS FLOOR" % away.to_upper()]
	dev_title.add_theme_color_override("font_color",
		UIW.colour("warning") if away != "" else UIW.colour("text_strong"))
	name_edit.text = cur_dev.name
	status_opt.select(0 if cur_dev.status == "active" else 1)
	psu_opt.select(["A", "B", "AB"].find(cur_dev.psu))
	psu_opt.set_item_disabled(2, not Game.dual_psu(cur_dev))
	psu_opt.tooltip_text = Loc.t("tip.two_psu") \
		if Game.dual_psu(cur_dev) else Loc.t("tip.one_psu")
	status_opt.disabled = cur_dev.status == "nopower"
	status_opt.tooltip_text = Loc.t("tip.no_power_feed") % cur_dev.psu \
		if cur_dev.status == "nopower" else Loc.t("tip.take_out_of_service")
	var watts := int(Game.WATTS.get(cur_dev.model, 0))
	dev_power_lbl.text = ("POWER PROFILE  /  %dW nameplate  /  electricity included in colo lease" % watts
		if Game.stage < 1 else
		"POWER PROFILE  /  %dW nameplate  /  ~$%d per cycle at $%.3f/W" % [watts,
			int(round(float(watts) * Game.efficiency_factor() * Game.energy_rate())),
			Game.energy_rate()])
	name_hint.text = ""

func _rename_dev(new_name: String) -> void:
	var was := cur_dev.name
	if Game.rename_device(cur_dev, new_name):
		hud_toast(Loc.t("toast.renamed") % [was, cur_dev.name], true)
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
		conn_list.add_child(_label(Loc.t("body.no_cables"), 14, Color(0.45, 0.5, 0.6)))
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
		svc_bits.append("dhcpd %s to %s (%d leases)" % [svc["start"], svc["end"], svc["leases"].size()])
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
	save_cfg_btn.text = "⚠ Save config" if dirty else Loc.t("btn.save_config")
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
	var note := _wrap(Loc.t("device.console_note"),
		13, UIW.colour("muted"), 420)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	console_note.add_child(note)
	var console_btn := Button.new()
	console_btn.text = "OPEN DEVICE CONSOLE"
	_accent(console_btn)
	console_btn.pressed.connect(func() -> void:
		close_iface()  # puts the device card's close button back
		if not cli_box.visible:
			_toggle_cli())
	console_note.add_child(console_btn)

	v.add_child(HSeparator.new())
	var cable_row := HBoxContainer.new()
	v.add_child(cable_row)
	if_cable_lbl = _label("", 14)
	if_cable_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cable_row.add_child(if_cable_lbl)
	# the four actions get their own row: beside the patch text they were
	# squeezed until every one of them read as "Physical work…"
	var cable_btns := HBoxContainer.new()
	cable_btns.add_theme_constant_override("separation", 8)
	v.add_child(cable_btns)
	var repair_btn := Button.new()
	repair_btn.text = Loc.t("btn.physical_work")
	repair_btn.tooltip_text = Loc.t("tip.physical_work")
	repair_btn.pressed.connect(func() -> void:
		_menu(repair_btn, Game.GREY_REPAIRS, func(id: int) -> void:
			var err: String = Game.repair_grey(cur_if, String(Game.GREY_REPAIRS[id]))
			if err != "":
				_toast(err)
			_refresh_ports()
			_refresh_money()))
	cable_btns.add_child(repair_btn)
	if_note_btn = Button.new()
	if_note_btn.text = "✎ TAG PORT"
	if_note_btn.tooltip_text = Loc.t("tip.jack_note")
	if_note_btn.pressed.connect(func() -> void: _open_note_card(if_note_ui))
	cable_btns.add_child(if_note_btn)
	if_peer_btn = Button.new()
	if_peer_btn.text = Loc.t("btn.go_other_end")
	if_peer_btn.pressed.connect(func() -> void:
		var l := Game.link_at(cur_if)
		if l:
			var peer := l.other(cur_if)
			cur_dev = peer.dev
			cur_rack = Game.rack_of(peer.dev)
			_refresh_dev_header()
			_refresh_ports()
			open_iface(peer))
	cable_btns.add_child(if_peer_btn)
	if_cable_btn = Button.new()
	if_cable_btn.pressed.connect(_cable_action)
	cable_btns.add_child(if_cable_btn)

func open_iface(i: Net.Iface) -> void:
	cur_if = i
	_refresh_note_card(if_note_ui, i, if_note_btn)
	_refresh_iface()
	if dev_title and dev_title.has_meta("back"):
		(dev_title.get_meta("back") as Button).visible = false  # one ESC CLOSE on screen: the inspector's
	_show_overlay(if_overlay)

func close_iface() -> void:
	if_overlay.visible = false
	cur_if = null
	if dev_title and dev_title.has_meta("back"):
		(dev_title.get_meta("back") as Button).visible = true
	if dev_overlay.visible:
		_refresh_ports()

func _refresh_iface() -> void:
	if_title.text = "%s / %s" % [cur_if.dev.name, cur_if.name]
	var spd := Game.iface_speed(cur_if)
	if_mac.text = "MAC %s      %s      RX %d / TX %d frames" % [cur_if.mac,
		("%d Gbit" % (spd / 1000)) if spd >= 1000 else ("%d Mbit" % spd), cur_if.rx_frames, cur_if.tx_frames]
	for c in if_state_box.get_children():
		c.queue_free()
	var link_word := Loc.t("iface.state.up")
	if cur_if.admin_down:
		link_word = Loc.t("iface.state.admin_down")
	elif cur_if.err_disabled:
		link_word = Loc.t("iface.state.errdisabled")
	elif cur_if.fault != "":
		link_word = Loc.t("iface.state.down", {"fault": cur_if.fault.to_upper()})
	elif not cur_if.enabled:
		link_word = "DOWN"
	if_state_box.add_child(_iface_state_line("LINK STATE", link_word,
		"success" if cur_if.enabled else "danger"))
	if_state_box.add_child(_iface_state_line("FRAME SIZE", "MTU %d" % cur_if.mtu, "info"))
	if cur_if.dev.type == "switch":
		var switching := Loc.t("iface.access", {"vlan": cur_if.untagged_vlan}) if cur_if.mode == "access" else \
			Loc.t("iface.trunk", {"vlans": Loc.t("iface.all_vlans") if cur_if.tagged_vlans.is_empty() else
			", ".join(PackedStringArray(cur_if.tagged_vlans.map(func(v): return str(v))))})
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
	if_vrrp_lbl.visible = not cur_if.vrrp.is_empty()
	if cur_if.vrrp.is_empty():
		if_vrrp_lbl.text = ""
	else:
		var master := Sim.vrrp_master(cur_if.vrrp["vip"], int(cur_if.vrrp["group"]))
		if_vrrp_lbl.text = "VRRP group %d  vip %s  prio %d  (%s)" % [int(cur_if.vrrp["group"]),
			cur_if.vrrp["vip"], int(cur_if.vrrp.get("priority", 100)),
			"Master" if master == cur_if.dev else "Backup"]
	var peer := Game.peer_label(cur_if)
	if peer == "":
		if_cable_lbl.text = Loc.t("iface.cable.none")
		if_cable_btn.text = Loc.t("btn.run_cable")
		if_cable_btn.tooltip_text = Loc.t("tip.run_cable")
		if_peer_btn.visible = false
	else:
		var link := Game.link_at(cur_if)
		var far_iface: Net.Iface = link.other(cur_if)
		var local_rack := Game.rack_of(cur_if.dev)
		var same_rack := local_rack != null and Game.rack_of(far_iface.dev) == local_rack
		if same_rack:
			if_cable_lbl.text = Loc.t("iface.cable.patch") + " ⇄  " + peer
			if_cable_btn.text = Loc.t("iface.cable.open_rack")
			if_cable_btn.tooltip_text = Loc.t("iface.cable.open_rack.tip")
		else:
			if_cable_lbl.text = Loc.t("iface.cable.remote") + " ⇄  " + peer
			if_cable_btn.text = Loc.t("iface.cable.disconnect")
			if_cable_btn.tooltip_text = Loc.t("iface.cable.disconnect.tip")
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
	for candidate: Net.Iface in Game.free_ifaces(cur_if.dev):
		if candidate.name.begins_with("Management") and not cur_if.name.begins_with("Management") and cur_if.dev.type != "console":
			continue  # the out-of-band port is not a data port; a server patched there reaches nothing
		targets.append(candidate)  # this rack included: the first job says "click a port, Run cable"
	if targets.is_empty():
		hud_toast(Loc.t("toast.no_free_ports"))
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
	t.text = Loc.t("btn.field_manual")
	var eyebrow := _section("FIELD MANUAL  /  REFERENCE")
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
	pedia_search = _mono_edit(280)
	pedia_search.placeholder_text = Loc.t("ph.filter_chapters")
	pedia_search.text_changed.connect(func(needle: String) -> void:
		var n := needle.strip_edges().to_lower()
		for bi in pedia_topic_buttons.size():
			var btn: Button = pedia_topic_buttons[bi]
			btn.visible = n == "" or n in Loc.t(String(Pedia.topics()[bi][0])).to_lower() or n in Loc.t(String(Pedia.topics()[bi][1])).to_lower())
	nav.add_child(pedia_search)
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
		b.text = "%02d   %s" % [topic_i + 1, Loc.t(String(entry[0]))]
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
	pedia_body.append_text(("[color=#39d9d0]" + Loc.t("FIELD MANUAL  /  CHAPTER %02d") + "[/color]\n\n") % (topic_i + 1))
	pedia_body.append_text("[font_size=24][b]%s[/b][/font_size]\n\n" % Loc.t(String(entry[0])))
	pedia_body.append_text("%s\n\n" % Pedia.article_text(entry))
	pedia_body.append_text("[color=#8da7ba]" + Loc.t("Use the exact commands above in a device console. The simulation will respond to the configuration, not a scripted answer.") + "[/color]")

func open_pedia() -> void:
	_show_overlay(pedia_overlay)

# ---------- search ----------

func _build_search() -> void:
	search_overlay = _overlay()
	var v := _card(search_overlay, 620)
	var t := _header(v, func() -> void: search_overlay.visible = false)
	t.text = Loc.t("find.title")
	search_input = _mono_edit(560)
	search_input.placeholder_text = Loc.t("find.placeholder")
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
		hud_toast(Loc.t("toast.close_panel_find"))
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
		search_box.add_child(_label("  " + Loc.t("find.empty"), 13, MUTED))
		return
	var hits := 0
	for d in Game.all_devices():
		var why := ""
		if q in d.name.to_lower():
			why = Loc.t("find.why.device")
		elif q in String(Game.MODELS[d.model]["label"]).to_lower():
			why = Loc.t("find.why.model")
		else:
			for i: Net.Iface in d.ifaces:
				for cidr: String in i.ips:
					if q in cidr.to_lower():
						why = Loc.t("find.why.address", {"cidr": cidr, "iface": i.name})
				if q in i.name.to_lower() and why == "":
					why = Loc.t("find.why.iface", {"iface": i.name})
			for vid in d.vlans:
				if q == str(vid):
					why = "VLAN %s (%s)" % [vid, d.vlans[vid]]  # the protocol's own word
			if why == "" and q in String(d.note.get("text", "")).to_lower():
				why = Loc.t("find.why.note", {"text": d.note["text"]})
			if why == "":
				for i2: Net.Iface in d.ifaces:
					if q in String(i2.note.get("text", "")).to_lower():
						why = Loc.t("find.why.iface_note", {"iface": i2.name, "text": i2.note["text"]})
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
			search_box.add_child(_label("  " + Loc.t("find.customer", {"name": deal["customer"], "kind": Market.label_for(deal["kind"]), "fee": int(deal["fee"])}), 13, Color(0.7, 0.85, 0.75)))
	if hits == 0:
		search_box.add_child(_label(Loc.t("body.nothing_matches"), 13, Color(0.8, 0.6, 0.5)))
	elif hits > 12:
		search_box.add_child(_label(Loc.t("body.more_matches") % (hits - 12), 12, MUTED))

# ---------- ops dashboard ----------

func _device_alerts(d: Net.NDevice) -> Array:
	var out: Array = []
	if d.status != "active":
		out.append(Loc.t("find.tag.offline"))
	var down := 0
	for i: Net.Iface in d.ifaces:
		if not i.enabled and Game.link_at(i):
			down += 1
		if i.violations > 0 and not i.enabled:
			out.append(Loc.t("find.tag.psec"))
	if down > 0:
		out.append("%d cabled port(s) down" % down)
	if Game.config_dirty(d):
		out.append(Loc.t("find.tag.unsaved"))
	for l in Game.links:
		if (l.a.dev == d or l.b.dev == d) and int(Game.last_link_load.get(l, 0)) > Game.link_capacity(l):
			out.append(Loc.t("find.tag.congested"))
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
	["Facility", ["FIRE, SMOKE AND WATER", "FAILOVER TEST", "FACILITY SCHEDULE",
		"WHO IS ON THE FLOOR"]],
	["Automation", ["PLAYBOOKS", "CERTIFICATES", "RUNBOOKS AND AUTOMATION", "STANDING DUTIES"]],
	["Records", ["DOCUMENTATION", "AUDIT READINESS", "RENEWALS CALENDAR", "UNREACHABLE",
		"WHAT YOU WROTE ABOUT THESE"]],
	["Board", ["THIS QUARTER'S TARGETS", "HOW THE PLACE IS TRENDING", "WHAT KIND OF COMPANY THIS IS", "DECISIONS",
		"A VISIT IS BOOKED",
		"HOW THIS RUN ENDED", "RUNS BEFORE THIS ONE"]],
]
var ops_tab := "Capacity"
var ops_scope_lbl: Label  # says which floor the panel is describing
var ops_orphan_sections: Array = []  # sections with no tab: a bug, not a feature
var ops_tab_btns := {}
var ops_metric_values := {}
var ops_metric_notes := {}

func _build_ops() -> void:
	ops_overlay = _overlay()
	var v := _card(ops_overlay, 900)
	ops_title = _header(v, func() -> void: ops_overlay.visible = false)
	ops_title.text = Loc.t("ops.title")
	var status_line := _section("LIVE ESTATE  /  CURRENT SHIFT")
	status_line.add_theme_color_override("font_color", UIW.colour("accent"))
	ops_scope_lbl = status_line
	v.add_child(status_line)
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", UIW.space("md"))
	v.add_child(metrics)
	metrics.add_child(_ops_metric(Loc.t("ops.metric.devices"), "devices", "info"))
	metrics.add_child(_ops_metric(Loc.t("ops.metric.links"), "links", "accent"))
	metrics.add_child(_ops_metric(Loc.t("ops.metric.alerts"), "alerts", "warning"))
	metrics.add_child(_ops_metric(Loc.t("ops.metric.power"), "power", "success"))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", UIW.space("sm"))
	v.add_child(tabs)
	for entry in OPS_TABS:
		var tb := Button.new()
		tb.text = Loc.t("ops.tab." + String(entry[0]).to_lower())  # the id stays English; the label follows the language
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
	var value := _label("…", 22, UIW.colour(semantic))
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
			current = String(child.get_meta("section_id", child.text))
			if current not in all_titles:
				ops_orphan_sections.append(current)
		if current != "":
			child.visible = current in wanted
	for name in ops_tab_btns:
		ops_tab_btns[name].button_pressed = name == ops_tab

func _refresh_ops() -> void:
	if ops_scope_lbl:
		# with two floors, "live estate" reads as everything you own, and this
		# panel is only ever about the one you are standing on
		var one_floor := Game.site_count() < 2
		ops_scope_lbl.text = "LIVE ESTATE  /  CURRENT SHIFT" if one_floor \
			else "THIS FLOOR  /  %s" % Game.site_name(Game.current_site).to_upper()
		ops_scope_lbl.add_theme_color_override("font_color", UIW.colour("accent") if one_floor
			else Color.from_hsv(Game.site_hue(Game.current_site), 0.45, 1.0))
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
	ops_title.text = Loc.t("btn.network_operations")
	# the scope line says THIS FLOOR, so the card must not quietly sum every site
	var watts := int(Game.capacity(Game.current_site)["watts"])
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
	_ops_capacity()
	_ops_this_quarters_targets()
	_ops_a_visit_is_booked()
	_ops_what_you_wrote_about_these()
	_ops_unreachable()
	_ops_documentation()
	_ops_nobody_claims_these()
	_ops_vendor_support()
	_ops_renewals_calendar()
	_ops_how_this_run_ended()
	_ops_runs_before_this_one()
	_ops_how_the_place_is_trending()
	_ops_what_kind_of_company_this_is()
	_ops_who_is_on_the_floor()
	_ops_fire_smoke_and_water()
	_ops_failover_test()
	_ops_facility_schedule()
	_ops_airflow()
	_ops_top_talkers()
	_ops_power()
	_ops_decisions()
	_ops_audit_readiness()
	_ops_standing_duties()
	_ops_the_parts_drawer()
	_ops_receiving()
	_ops_assets_and_spares()
	_ops_runbooks_and_automation()
	_ops_playbooks()
	_ops_certificates()
	_ops_monitors()
	# with nothing installed the list stops short and the tab filter is left alone, as before
	if not _ops_devices(devs):
		return
	_apply_ops_tab()

func _ops_capacity() -> void:
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
			ops_box.add_child(_label(Loc.t("body.power_draw_colo")
				% int(cap["watts"]), 12, MUTED))
	var advice := _capacity_advice()
	if advice != "":
		ops_box.add_child(_wrap("  " + advice, 13, Color(1.0, 0.82, 0.5), 780))
	var meter := UIW.style_panel(PanelContainer.new(), "console", "md")
	ops_box.add_child(meter)
	var meter_copy := "COLO POWER INCLUDED  /  Your cost is $0 per watt in this cage. Reference rate for an owned room right now: $%.3f per watt per cycle." % Game.energy_rate()
	if Game.stage >= 1:
		meter_copy = "LIVE METER  /  %dW nameplate → %dW billed after efficiency  ×  $%.3f per watt per cycle  =  $%d next cycle" % [
			Game.power_draw_all(), Game.effective_draw(), Game.energy_rate(), Game.power_bill()]
	var meter_label := _wrap(meter_copy, 13,
		UIW.colour("warm") if Game.stage >= 1 else UIW.colour("muted"), 780)
	meter_label.add_theme_font_override("font", mono)
	meter.add_child(meter_label)

func _ops_this_quarters_targets() -> void:
	if Game.quarter_goals.is_empty() and Game.cycle > 0:
		Game.roll_quarter_goals()  # an older save, or a company that has not seen a quarter close yet
	if not Game.quarter_goals.is_empty():
		ops_box.add_child(_section("THIS QUARTER'S TARGETS"))
		ops_box.add_child(_wrap(Loc.t("body.board_asks") % (12 - Game.cycle % 12),
			12, MUTED, 780))
		for qg: Dictionary in Game.quarter_goals:
			var qp: Dictionary = Game.quarter_goal_progress(qg)
			var ql := _label("  %s %-58s %-16s $%d" % ["✓" if bool(qp["met"]) else "○", Game.quarter_goal_label(qg), qp["text"], int(qg["reward"])],
				12, Color(0.6, 0.85, 0.7) if bool(qp["met"]) else Color(0.78, 0.84, 0.9))
			ql.add_theme_font_override("font", mono)
			ops_box.add_child(ql)

func _ops_a_visit_is_booked() -> void:
	if not Game.tour.is_empty():
		ops_box.add_child(_section("A VISIT IS BOOKED"))
		var kind: String = String(Game.tour["kind"])
		var tk: Dictionary = Game.TOUR_KINDS[kind]
		# the clock can be held (a drill, a scenario, a save opened past the
		# date), so never print a countdown that has gone the other way
		var due_in: int = int(Game.tour["cycle"]) - Game.cycle
		var when := "arrives in %d cycle(s)" % due_in if due_in > 0 else (
			"is walking the floor now" if due_in == 0 else "was due %d cycle(s) ago" % -due_in)
		var who := String(tk["label"])
		who = who.substr(0, 1).to_upper() + who.substr(1)  # a sentence starts with a capital
		ops_box.add_child(_wrap(Loc.t("body.visitor_score")
			% [who, when, tk["cares"],
				int(Game.tour_score(kind) * 100.0)], 13, Color(1.0, 0.82, 0.5), 780))
		var cram_btn := Button.new()
		cram_btn.text = Loc.t("btn.crew_short_notice")
		cram_btn.tooltip_text = Loc.t("tip.crew_short_notice")
		cram_btn.pressed.connect(func() -> void:
			var err: String = Game.cram_for_tour()
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		ops_box.add_child(cram_btn)

func _ops_what_you_wrote_about_these() -> void:
	var past_you: Array = Game.incident_notes()
	if not past_you.is_empty():
		ops_box.add_child(_section("WHAT YOU WROTE ABOUT THESE"))
		for note_line: String in past_you:
			ops_box.add_child(_wrap("  %s" % note_line, 12, Color(1.0, 0.85, 0.55), 780))

func _ops_unreachable() -> void:
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
		var ll := _label(Loc.t("body.unreachable") % d_lock2.name, 12,
			Prefs.bad_colour())
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lrow.add_child(ll)
		var walk_btn := Button.new()
		var rack_lock := Game.rack_of(d_lock2)
		var far := rack_lock != null and int(rack_lock.site) != 0
		walk_btn.text = Loc.t("btn.site_visit") if far else Loc.t("btn.walk_to_rack")
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
		var cl2 := _label(Loc.t("body.reverts_unless") % [name_c,
			int(Game.confirm_commits[name_c]["due"])], 12, Color(1.0, 0.82, 0.5))
		cl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow2.add_child(cl2)
		var conf := Button.new()
		conf.text = Loc.t("btn.confirm")
		conf.pressed.connect(func() -> void:
			for d_conf: Net.NDevice in Game.all_devices():
				if d_conf.name == name_c:
					var err: String = Game.confirm_commit(d_conf)
					if err != "":
						_toast(err)
			_refresh_ops())
		crow2.add_child(conf)

func _ops_documentation() -> void:
	ops_box.add_child(_section("DOCUMENTATION"))
	ops_box.add_child(_wrap(Loc.t("body.facts_adrift_intro")
		% Game.site_drift(), 12,
		Color(1.0, 0.82, 0.5) if Game.drift_factor() > 0.3 else Color(0.72, 0.8, 0.88), 780))
	for r_doc: Net.Rack in Game.racks_on(Game.current_site):
		var drift_here: int = Game.rack_drift(r_doc)
		if drift_here == 0:
			continue
		var dr_row := HBoxContainer.new()
		dr_row.add_theme_constant_override("separation", 8)
		ops_box.add_child(dr_row)
		var drl := _label(Loc.t("body.facts_adrift") % [r_doc.name, drift_here], 12,
			Color(0.78, 0.84, 0.9))
		drl.add_theme_font_override("font", mono)
		drl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dr_row.add_child(drl)
		var walk := Button.new()
		walk.text = Loc.t("btn.walk_and_write")
		walk.pressed.connect(func() -> void:
			var err: String = Game.reconcile_rack(r_doc)
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		dr_row.add_child(walk)

func _ops_nobody_claims_these() -> void:
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
				dig.text = Loc.t("btn.investigate")
				dig.tooltip_text = Loc.t("tip.investigate")
				dig.pressed.connect(func() -> void:
					var err: String = Game.investigate_orphan(orphan)
					if err != "":
						_toast(err)
					_refresh_ops()
					_refresh_money())
				orow.add_child(dig)
			var kill := Button.new()
			kill.text = Loc.t("btn.turn_off")
			kill.tooltip_text = Loc.t("tip.turn_off")
			kill.pressed.connect(func() -> void:
				var err: String = Game.retire_orphan(orphan)
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money())
			orow.add_child(kill)

func _ops_vendor_support() -> void:
	ops_box.add_child(_section("VENDOR SUPPORT"))
	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 8)
	ops_box.add_child(tier_row)
	tier_row.add_child(_label(Loc.t("body.cover") % Game.SUPPORT_TIERS[Game.support_tier()]["label"],
		12, Color(0.72, 0.8, 0.88)))
	for tier_i in [1, 2]:
		var buy_tier := Button.new()
		buy_tier.text = Loc.t("btn.buy_model") % [Game.SUPPORT_TIERS[tier_i]["label"],
			int(Game.SUPPORT_TIERS[tier_i]["cost"])]
		buy_tier.tooltip_text = Loc.t("tip.support_response") % [
			int(Game.SUPPORT_TIERS[tier_i]["wait"]), int(Game.SUPPORT_TIERS[tier_i]["escalate"])]
		buy_tier.pressed.connect(func() -> void:
			var err: String = Game.buy_support(tier_i)
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		tier_row.add_child(buy_tier)
	for name_bug: String in Game.firmware_bugs:
		ops_box.add_child(_wrap(Loc.t("body.flapping") % name_bug,
			12, Color(1.0, 0.72, 0.45), 780))
		var open_case := Button.new()
		open_case.text = Loc.t("btn.open_case_against") % name_bug
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
		var cl := _label(Loc.t("body.case_row") % [c["id"], c["device"],
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
				ev.text = Loc.t("btn.send_to") % kind
				ev.pressed.connect(func() -> void:
					var err: String = Game.attach_evidence(c, kind)
					if err != "":
						_toast(err)
					_refresh_ops())
				crow.add_child(ev)
				break
			var bundle_btn := Button.new()
			bundle_btn.text = Loc.t("btn.attach_bundle")
			bundle_btn.tooltip_text = "'show tech-support' collects everything they asked for in one go"
			bundle_btn.pressed.connect(func() -> void:
				var err: String = Game.attach_bundle(c)
				if err != "":
					_toast(err)
				_refresh_ops())
			crow.add_child(bundle_btn)
			var hand := Button.new()
			hand.text = Loc.t("btn.hand_to_team") if not bool(c.get("delegated", false)) else Loc.t("btn.take_back")
			hand.tooltip_text = Loc.t("tip.support_bundle")
			hand.pressed.connect(func() -> void:
				c["delegated"] = not bool(c.get("delegated", false))
				_refresh_ops())
			crow.add_child(hand)
		elif String(c["stage"]) == "queued":
			var esc := Button.new()
			esc.text = Loc.t("btn.escalate")
			esc.pressed.connect(func() -> void:
				var err: String = Game.escalate_case(c)
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money())
			crow.add_child(esc)
		elif String(c["stage"]) == "fix_ready":
			var load_btn := Button.new()
			load_btn.text = Loc.t("btn.load_fixed_image")
			load_btn.tooltip_text = Loc.t("tip.fixed_image")
			load_btn.pressed.connect(func() -> void:
				var err: String = Game.apply_firmware(c)
				if err != "":
					_toast(err)
				_refresh_ops())
			crow.add_child(load_btn)

func _ops_renewals_calendar() -> void:
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
			pay.text = Loc.t("btn.renew")
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
			auto_r.text = Loc.t("btn.auto") if auto_r.button_pressed else Loc.t("btn.manual")
			auto_r.tooltip_text = Loc.t("tip.auto_renew")
			auto_r.toggled.connect(func(on: bool) -> void:
				item["auto"] = on
				_refresh_ops())
			rrow.add_child(auto_r)

func _ops_how_this_run_ended() -> void:
	if not Game.finale.is_empty():
		ops_box.add_child(_section("HOW THIS RUN ENDED"))
		for fin_line: String in Game.finale_report():
			var fl := _label("  %s" % fin_line, 12, Color(0.85, 0.9, 0.95))
			fl.add_theme_font_override("font", mono)
			ops_box.add_child(fl)
		for cmp_line: String in Game.compare_to_best(Game.finale.get("record", {})):
			ops_box.add_child(_label("  %s" % cmp_line, 12, Color(0.72, 0.84, 0.8)))
		var fin_copy := Button.new()
		fin_copy.text = Loc.t("btn.copy_report")
		fin_copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set("\n".join(PackedStringArray(Game.finale_report())))
			hud_toast(Loc.t("toast.report_clipboard"), true))
		ops_box.add_child(fin_copy)
		# the world keeps ticking after the report, but there is nothing left
		# to score: the honest next move is a second company, one notch harder
		var next_diff := mini(Game.difficulty + 1, Game.DIFFICULTIES.size() - 1)
		var again := Button.new()
		again.text = Loc.t("btn.second_company") % Loc.t(String(Game.DIFFICULTIES[next_diff]["name"]))
		again.tooltip_text = Loc.t("tip.second_company")
		_accent(again)
		again.pressed.connect(func() -> void:
			var world := get_parent()
			if world != null and world.has_method("_start_new"):
				world._start_new(Game.current_slot, "%s II" % Game.company_name, next_diff, false))
		ops_box.add_child(again)
	elif Game.rank() == Game.RANKS[Game.RANKS.size() - 1][0]:
		var retire := Button.new()
		retire.text = Loc.t("btn.retire")
		retire.tooltip_text = Loc.t("tip.retire")
		retire.pressed.connect(func() -> void:
			var err: String = Game.end_run("retired")
			if err != "":
				_toast(err)
			_refresh_ops())
		ops_box.add_child(retire)

func _ops_runs_before_this_one() -> void:
	var past_runs: Array = Game.run_history()
	if not past_runs.is_empty():
		ops_box.add_child(_section("RUNS BEFORE THIS ONE"))
		var head_row := _label("  %-18s %-14s %-10s %-11s %-11s %s" % ["COMPANY", "IDENTITY",
			"DIFFICULTY", "ENDING", "LASTED", "SCORE"], 11, UIW.colour("muted"))
		head_row.add_theme_font_override("font", mono)
		ops_box.add_child(head_row)
		for row: Dictionary in past_runs.slice(0, 6):
			var rl := _label(Loc.t("body.history_row") % [row.get("company", ""),
				Loc.t(String(row.get("identity", ""))), Loc.t(String(row.get("difficulty", ""))), Loc.t(String(Game.FINALE_ENDING_LABELS.get(String(row.get("ending", "")), row.get("ending", "")))), int(row.get("cycle", 0)),
				int(row.get("total", 0))], 12, Color(0.78, 0.84, 0.9))
			rl.add_theme_font_override("font", mono)
			ops_box.add_child(rl)
		var forget := Button.new()
		forget.text = Loc.t("btn.clear_history")
		forget.tooltip_text = Loc.t("tip.clear_history")
		forget.pressed.connect(func() -> void:
			Game.forget_all_runs()
			_refresh_ops())
		ops_box.add_child(forget)

func _ops_how_the_place_is_trending() -> void:
	ops_box.add_child(_section("HOW THE PLACE IS TRENDING"))
	for trend_line in Game.trend_read():
		ops_box.add_child(_wrap("  %s" % String(trend_line), 13,
			UIW.colour("text_strong"), 780))

func _ops_what_kind_of_company_this_is() -> void:
	ops_box.add_child(_section("WHAT KIND OF COMPANY THIS IS"))
	if Game.identity == "":
		if Game.identity_offered():
			ops_box.add_child(_wrap(Loc.t("body.choose_operation"),
				13, Color(1.0, 0.85, 0.5), 780))
			for ident_id: String in Game.IDENTITIES:
				var ident: Dictionary = Game.IDENTITIES[ident_id]
				var irow2 := HBoxContainer.new()
				irow2.add_theme_constant_override("separation", 8)
				ops_box.add_child(irow2)
				var il2 := _wrap("  %s: %s  (%s)" % [Loc.t(String(ident["label"])), Loc.t(String(ident["blurb"])), Loc.t(String(ident["trade"]))],
					12, Color(0.72, 0.8, 0.88), 560)
				il2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				irow2.add_child(il2)
				var ib := Button.new()
				ib.text = Loc.t("btn.be_this")
				ib.pressed.connect(func() -> void:
					Game.choose_identity(ident_id)
					_refresh_ops()
					_refresh_money())
				irow2.add_child(ib)
		else:
			ops_box.add_child(_label(Loc.t("body.finish_opening_first"),
				12, MUTED))
	else:
		var mine: Dictionary = Game.IDENTITIES[Game.identity]
		ops_box.add_child(_wrap("  %s. %s  (%s)" % [Loc.t(String(mine["label"])), Loc.t(String(mine["blurb"])), Loc.t(String(mine["trade"]))],
			12, Color(0.72, 0.84, 0.8), 780))
		var reb := Button.new()
		reb.text = Loc.t("btn.rebrand")
		reb.pressed.connect(func() -> void:
			var ids: Array = Game.IDENTITIES.keys()
			var opts_i: Array = []
			for id_o: String in ids:
				opts_i.append("%s: %s" % [Loc.t(String(Game.IDENTITIES[id_o]["label"])),
					Loc.t(String(Game.IDENTITIES[id_o]["trade"]))])
			_menu(reb, opts_i, func(id: int) -> void:
				var err: String = Game.rebrand(String(ids[id]))
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money()))
		ops_box.add_child(reb)

func _ops_who_is_on_the_floor() -> void:
	ops_box.add_child(_section("WHO IS ON THE FLOOR"))
	ops_box.add_child(_wrap("  %s. %s%s" % [Loc.t(String(Game.ACCESS_POLICIES[Game.access_policy]["label"])),
		Loc.t(String(Game.ACCESS_POLICIES[Game.access_policy]["blurb"])),
		"  Cameras up." if Game.cameras else ""], 12, Color(0.72, 0.8, 0.88), 780))
	var acc_row := HBoxContainer.new()
	acc_row.add_theme_constant_override("separation", 8)
	ops_box.add_child(acc_row)
	for pol_id: String in Game.ACCESS_POLICIES:
		if pol_id == Game.access_policy:
			continue
		var polb := Button.new()
		polb.text = "%s ($%d)" % [Loc.t(String(Game.ACCESS_POLICIES[pol_id]["label"])),
			int(Game.ACCESS_POLICIES[pol_id]["cost"])]
		polb.tooltip_text = Loc.t(String(Game.ACCESS_POLICIES[pol_id]["blurb"]))
		polb.pressed.connect(func() -> void:
			var err: String = Game.set_access_policy(pol_id)
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		acc_row.add_child(polb)
	if not Game.cameras:
		var cam := Button.new()
		cam.text = Loc.t("btn.cameras")
		cam.tooltip_text = Loc.t("tip.cameras")
		cam.pressed.connect(func() -> void:
			var err: String = Game.buy_cameras()
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		ops_box.add_child(cam)
	for vis: Dictionary in Game.visitors:
		ops_box.add_child(_label(Loc.t("body.visitor_row") % [vis["name"], vis["reason"],
			", escorted" if bool(vis["escorted"]) else ""], 12, Color(1.0, 0.82, 0.5)))
	var acc_lines: Array = Game.access_investigation()
	if acc_lines.is_empty():
		ops_box.add_child(_label(Loc.t("body.nothing_on_record"),
			12, MUTED))
	else:
		var acc_cap := _label(Loc.t("body.sign_in_log"), 11, MUTED)
		acc_cap.add_theme_font_override("font", mono)
		ops_box.add_child(acc_cap)
	for acc_line: String in acc_lines.slice(0, 6):
		ops_box.add_child(_label("      %s" % acc_line, 12, Color(0.68, 0.74, 0.82)))

func _ops_fire_smoke_and_water() -> void:
	ops_box.add_child(_section("FIRE, SMOKE AND WATER"))
	for prot_id: String in Game.PROTECTION:
		var prot: Dictionary = Game.PROTECTION[prot_id]
		var prow2 := HBoxContainer.new()
		prow2.add_theme_constant_override("separation", 8)
		ops_box.add_child(prow2)
		var fitted: bool = bool(Game.protection.get(prot_id, {}).get("installed", false))
		var ready: bool = Game.protection_ready(prot_id)
		var pl2 := _label("  %-30s %s" % [Loc.t(String(prot["label"])),
			("not fitted" if not fitted else ("in date" if ready else "OVERDUE INSPECTION"))], 12,
			Color(0.72, 0.84, 0.8) if ready else Color(1.0, 0.82, 0.5))
		pl2.add_theme_font_override("font", mono)
		pl2.tooltip_text = Loc.t(String(prot["blurb"]))
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
		ops_box.add_child(_label(Loc.t("body.hazard_risk")
			% [r_risk.name, int(risk_here * 100.0)], 12, Color(1.0, 0.82, 0.5)))
	for haz_i: Dictionary in Game.hazards:
		ops_box.add_child(_label(Loc.t("body.live_hazard") % [
			Loc.t(String(Game.HAZARD_KINDS[haz_i["kind"]]["label"])), haz_i["rack"], int(haz_i["severity"]),
			"" if bool(haz_i["detected"]) else ", undetected"], 12, Prefs.bad_colour()))
		var what_stops := Loc.t("body.suppression") if String(haz_i["kind"]) in ["smoke", "fire"] \
			else Loc.t("body.drainage")
		ops_box.add_child(_wrap(Loc.t("body.fitting_during") % what_stops, 12, MUTED, 600))
		if not Staff.anyone_on_shift() and not Game.staff.is_empty():
			var haz_call := Button.new()
			haz_call.text = Loc.t("btn.get_somebody") % Game.CALLOUT_FEE
			haz_call.tooltip_text = Loc.t("tip.call_out")
			haz_call.pressed.connect(func() -> void:
				var err := Game.call_someone_out()
				hud_toast(err if err != "" else Loc.t("toast.on_their_way"), err == "")
				_refresh_ops())
			ops_box.add_child(haz_call)

func _ops_failover_test() -> void:
	ops_box.add_child(_section("FAILOVER TEST"))
	if Game.dr_running():
		ops_box.add_child(_wrap(Loc.t("body.failover_running")
			% [", ".join(PackedStringArray(Game.dr_test["taken"])), int(Game.dr_test["ends"]),
				Loc.t("body.nothing_dropped") if Game.dr_test["failed"].is_empty()
				else Loc.t("body.already_down") % ", ".join(PackedStringArray(Game.dr_test["failed"]))],
			13, UIW.colour("warning"), 780))
	elif not Game.dr_test.is_empty():
		ops_box.add_child(_wrap(Loc.t("body.failover_booked")
			% [int(Game.dr_test["booked"]), Game.DR_LENGTH], 13, UIW.colour("text_strong"), 780))
		var dr_cancel := Button.new()
		dr_cancel.text = Loc.t("btn.cancel_it")
		dr_cancel.pressed.connect(func() -> void:
			var err := Game.cancel_dr_test()
			if err != "":
				_toast(err)
			_refresh_ops())
		ops_box.add_child(dr_cancel)
	else:
		ops_box.add_child(_wrap(Loc.t("body.failover_why"),
			13, UIW.colour("muted"), 780))
		var dr_book := Button.new()
		dr_book.text = Loc.t("btn.book_failover")
		dr_book.tooltip_text = "Announced %d cycles ahead. The upstream goes away for %d cycles and the test is judged on whether customers stayed served." % [Game.DR_NOTICE, Game.DR_LENGTH]
		_accent(dr_book)
		dr_book.pressed.connect(func() -> void:
			var err := Game.book_dr_test()
			if err != "":
				_toast(err)
			_refresh_ops())
		ops_box.add_child(dr_book)

func _ops_facility_schedule() -> void:
	ops_box.add_child(_section("FACILITY SCHEDULE"))
	if Game.heat_wave():
		ops_box.add_child(_wrap(Loc.t("body.heat_wave"),
			13, Color(1.0, 0.72, 0.45), 780))
	for task_id: String in Game.FACILITY_TASKS:
		var task: Dictionary = Game.FACILITY_TASKS[task_id]
		var due: int = Game.facility_due_in(task_id)
		var frow := HBoxContainer.new()
		frow.add_theme_constant_override("separation", 8)
		ops_box.add_child(frow)
		var fl := _label("  %-22s %s" % [Loc.t(String(task["label"])),
			("due in %d cycle(s)" % due) if due > 0 else ("OVERDUE by %d" % -due)], 12,
			Color(0.72, 0.8, 0.88) if due > 0 else Color(1.0, 0.72, 0.45))
		fl.add_theme_font_override("font", mono)
		fl.tooltip_text = Loc.t(String(task["blurb"]))
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frow.add_child(fl)
		var do_btn := Button.new()
		do_btn.text = Loc.t("btn.do_it_cost") % int(task["cost"])
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
		auto_btn.text = Loc.t("btn.on_schedule") if auto_btn.button_pressed else Loc.t("btn.delegate")
		auto_btn.tooltip_text = Loc.t("tip.delegate")
		auto_btn.toggled.connect(func(on: bool) -> void:
			Game.facility_auto[task_id] = on
			_refresh_ops())
		frow.add_child(auto_btn)
	if not Game.generator_ready():
		ops_box.add_child(_wrap(Loc.t("body.generator_untested"),
			12, Color(1.0, 0.72, 0.45), 780))

func _ops_airflow() -> void:
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
			var al := _label(Loc.t("body.cooling_row") % [r_air.name, heat, cool,
				"HOT" if hot else "ok"], 12,
				Prefs.bad_colour() if hot else Color(0.7, 0.78, 0.85))
			al.add_theme_font_override("font", mono)
			ops_box.add_child(al)
		if any_hot:
			ops_box.add_child(_wrap(Loc.t("body.cold_air"),
				12, Color(1.0, 0.82, 0.5), 780))

func _ops_top_talkers() -> void:
	var talkers := Game.top_talkers(6)
	if not talkers.is_empty():
		ops_box.add_child(_section("TOP TALKERS"))
		for row: Dictionary in talkers:
			var tl := _label(Loc.t("body.packets_row") % [row["pair"], int(row["packets"])],
				12, Color(0.72, 0.78, 0.86))
			tl.add_theme_font_override("font", mono)
			ops_box.add_child(tl)
		var clear_btn := Button.new()
		clear_btn.text = Loc.t("btn.reset_counters")
		clear_btn.pressed.connect(func() -> void:
			Game.clear_talkers()
			_refresh_ops())
		ops_box.add_child(clear_btn)

func _ops_power() -> void:
	ops_box.add_child(_section("POWER"))
	for si2 in Game.site_count():
		if si2 == 0 and Game.stage < 1:
			ops_box.add_child(_label(Loc.t("body.colo_provides"),
				12, MUTED))
			continue
		var f: Dictionary = Game.site_feeds(si2)
		var bits: Array = []
		for letter in ["A", "B"]:
			bits.append("feed %s %s" % [letter, "live" if bool(f[letter]) else "DOWN"])
		if Game.has_ups(si2):
			bits.append("UPS %d/%s" % [int(Game.ups.get(si2, 0)), Loc.cycles(Game.UPS_CYCLES)])
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
			ops_box.add_child(_wrap(Loc.t("body.single_supply")
				% [", ".join(PackedStringArray(on_a)) if not on_a.is_empty() else "nothing",
				", ".join(PackedStringArray(on_b)) if not on_b.is_empty() else "nothing"],
				12, Color(0.8, 0.75, 0.6), 780))
	if Game.stage >= 1 and not Game.has_ups(Game.current_site):
		var ups_btn := Button.new()
		ups_btn.text = Loc.t("btn.install_ups") % Game.UPS_PRICE
		ups_btn.tooltip_text = Loc.t("tip.ups") % Game.UPS_CYCLES
		ups_btn.pressed.connect(func() -> void:
			var err := Game.buy_ups()
			if err != "":
				_toast(err)
			else:
				hud_toast(Loc.t("toast.ups_installed"), true)
			_refresh_ops())
		ops_box.add_child(ups_btn)

func _ops_decisions() -> void:
	if not Game.decisions.is_empty():
		ops_box.add_child(_section("DECISIONS"))
		for dec: Dictionary in Game.decisions:
			var spec: Dictionary = Game.decision_by_id(String(dec["id"]))
			if spec.is_empty():
				continue
			ops_box.add_child(_wrap("  %s  ·  %s" % [Loc.t(String(spec["title"])), Loc.t(String(spec["text"]))], 13,
				Color(1.0, 0.85, 0.5), 780))
			for fact: String in spec["facts"]:
				ops_box.add_child(_label("      · %s" % Loc.t(fact), 12, Color(0.72, 0.8, 0.88)))
			var decrow := HBoxContainer.new()
			decrow.add_theme_constant_override("separation", 8)
			ops_box.add_child(decrow)
			for opt_i in spec["options"].size():
				var ob := Button.new()
				ob.text = Loc.t(String(spec["options"][opt_i]["label"]))
				ob.pressed.connect(func() -> void:
					Game.decide(String(dec["id"]), opt_i)
					_refresh_ops()
					_refresh_money())
				decrow.add_child(ob)
	if not Game.consequences.is_empty():
		ops_box.add_child(_label(Loc.t("body.waiting_to_land")
			% Game.consequences.size(), 12, MUTED))

func _ops_audit_readiness() -> void:
	ops_box.add_child(_section("AUDIT READINESS"))
	ops_box.add_child(_wrap(Loc.t("body.cert_abstraction")
		% ("   Trust marker: earned." if Game.trust_marker else ""), 12, MUTED, 780))
	if not Game.destruction_certs.is_empty() or not Game.data_risks.is_empty():
		# the paperwork an auditor asks for first: what left the building, and whether it was wiped
		var cert_line := _label(Loc.t("body.cert_destruction") % [Game.destruction_certs.size(),
			"   (%d unit(s) left without one)" % Game.data_risks.size() if not Game.data_risks.is_empty() else ""],
			12, Prefs.bad_colour() if not Game.data_risks.is_empty() else Color(0.6, 0.85, 0.7))
		cert_line.add_theme_font_override("font", mono)
		var cert_names: Array = []
		for cert: Dictionary in Game.destruction_certs.slice(-8):
			cert_names.append("%s (cycle %d)" % [cert.get("device", "?"), int(cert.get("cycle", 0))])
		cert_line.tooltip_text = ", ".join(PackedStringArray(cert_names)) if not cert_names.is_empty() else "none yet"
		ops_box.add_child(cert_line)
	for ctrl: Dictionary in Game.audit_readiness():
		var ctrl_colour := Color(0.6, 0.85, 0.7)
		if String(ctrl["status"]) == "failing":
			ctrl_colour = Prefs.bad_colour()
		elif String(ctrl["status"]) != "compliant":
			ctrl_colour = Color(1.0, 0.82, 0.5)
		# a long label used to push the status into the next column; the
		# columns are now real ones, and the label wraps inside its own
		var cl3_row := HBoxContainer.new()
		cl3_row.add_theme_constant_override("separation", 12)
		var cl3_label := _label("  " + Loc.t(String(ctrl["label"])), 12, ctrl_colour)
		cl3_label.custom_minimum_size = Vector2(300, 0)
		cl3_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl3_label.add_theme_font_override("font", mono)
		cl3_row.add_child(cl3_label)
		var cl3_status := _label(String(ctrl["status"]), 12, ctrl_colour)
		cl3_status.custom_minimum_size = Vector2(90, 0)
		cl3_status.add_theme_font_override("font", mono)
		cl3_row.add_child(cl3_status)
		var cl3_why := _label(String(ctrl["why"]), 12, ctrl_colour)
		cl3_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl3_why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cl3_why.add_theme_font_override("font", mono)
		cl3_row.add_child(cl3_why)
		cl3_row.tooltip_text = Loc.t(String(ctrl["blurb"]))
		ops_box.add_child(cl3_row)
	if not Game.audit.is_empty():
		var aud: Dictionary = Game.audit
		ops_box.add_child(_wrap(Loc.t("body.audit_review")
			% [aud["customer"], ", ".join(PackedStringArray(aud["scope"])), int(aud["reward"]),
				int(aud["deadline"])], 13, Color(1.0, 0.85, 0.5), 780))
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 8)
		ops_box.add_child(arow)
		if String(aud["state"]) == "offered":
			for opt: Array in [["Accept", func() -> void: Game.accept_audit()],
					[Loc.t("opt.more_time"), func() -> void: Game.delay_audit()],
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
			vb.text = Loc.t("btn.reverify")
			vb.pressed.connect(func() -> void:
				var err: String = Game.verify_audit()
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money())
			arow.add_child(vb)

func _ops_standing_duties() -> void:
	ops_box.add_child(_section("STANDING DUTIES"))
	if Game.staff.is_empty():
		ops_box.add_child(_label(Loc.t("body.no_payroll_chores"),
			12, Color(0.72, 0.8, 0.88)))
	for duty_id: String in Game.DUTIES:
		var duty: Dictionary = Game.DUTIES[duty_id]
		var holder: String = Game.duty_holder(duty_id)
		var drow := HBoxContainer.new()
		drow.add_theme_constant_override("separation", 8)
		ops_box.add_child(drow)
		var dl := _label("  %-34s %s" % [Loc.t(String(duty["label"])),
			("by hand" if holder == "" else "%s (%d%% as good as you)"
				% [holder, int(Game.duty_quality(duty_id) * 100.0)])], 12,
			Color(0.72, 0.8, 0.88) if holder == "" else Color(0.78, 0.86, 0.78))
		dl.add_theme_font_override("font", mono)
		dl.tooltip_text = Loc.t(String(duty["blurb"]))
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		drow.add_child(dl)
		var assign := Button.new()
		assign.text = Loc.t("btn.assign") if holder == "" else Loc.t("btn.take_back")
		assign.pressed.connect(func() -> void:
			if holder != "":
				Game.assign_duty(duty_id, "")
				_refresh_ops()
				return
			var names: Array = []
			var name_opts: Array = []
			for m_d: Dictionary in Game.staff:
				names.append(String(m_d["name"]))
				name_opts.append("%s  (%s, holding %d)" % [m_d["name"], Loc.t(Staff.label(m_d)),
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
		ops_box.add_child(_label(Loc.t("body.last_cycle") % "; ".join(PackedStringArray(Game.last_digest)),
			12, Color(0.68, 0.74, 0.82)))

func _ops_the_parts_drawer() -> void:
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
	buy_parts_btn.text = Loc.t("btn.stock_up")
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
	auto_parts.text = Loc.t("btn.standing_order") if Game.parts_auto else Loc.t("btn.order_by_hand")
	auto_parts.tooltip_text = Loc.t("tip.standing_order")
	auto_parts.toggled.connect(func(on: bool) -> void:
		Game.parts_auto = on
		_refresh_ops())
	parts_row.add_child(auto_parts)
	var cabling_row := HBoxContainer.new()
	cabling_row.add_theme_constant_override("separation", 8)
	ops_box.add_child(cabling_row)
	cabling_row.add_child(_wrap(Loc.t("body.cable_debt")
		% Game.cable_debt_score(), 12,
		Color(1.0, 0.82, 0.5) if Game.cable_debt_score() > 4 else Color(0.72, 0.8, 0.88), 520))
	var cabling_btn := Button.new()
	cabling_btn.toggle_mode = true
	cabling_btn.button_pressed = Game.cabling_documented
	cabling_btn.text = Loc.t("btn.cabling_documented") if Game.cabling_documented else Loc.t("btn.cabling_expedient")
	cabling_btn.tooltip_text = Loc.t("tip.cabling_documented")
	cabling_btn.toggled.connect(func(on: bool) -> void:
		Game.cabling_documented = on
		_refresh_ops())
	cabling_row.add_child(cabling_btn)
	var debt_items: Array = Game.cable_debt_items()
	if debt_items.size() > 5:
		ops_box.add_child(_label(Loc.t("body.showing_five") % debt_items.size(), 11, MUTED))
	for debt_item: Dictionary in debt_items.slice(0, 5):
		ops_box.add_child(_label("      · %s  (%s)" % [debt_item["label"], debt_item["fix"]], 12,
			Color(0.68, 0.74, 0.82)))
	if Game.cable_debt > 0:
		var redo := Button.new()
		redo.text = Loc.t("btn.redo_leads") % Game.cable_debt
		redo.tooltip_text = Loc.t("tip.redo_leads")
		redo.pressed.connect(func() -> void:
			var err: String = Game.redo_cable_debt()
			if err != "":
				_toast(err)
			_refresh_ops()
			_refresh_money())
		ops_box.add_child(redo)

func _ops_receiving() -> void:
	ops_box.add_child(_section("RECEIVING"))
	var order_btn := Button.new()
	order_btn.text = Loc.t("btn.order_hardware")
	order_btn.tooltip_text = Loc.t("tip.order_hardware")
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
				tier_opts.append("%s   $%d   %d-%d cycles   %s" % [Loc.t(String(spec["label"])),
					Game.order_estimate(model_pick, t_id), int(spec["wait"][0]),
					int(spec["wait"][1]), Loc.t(String(spec["blurb"]))])
			_menu(order_btn, tier_opts, func(tid: int) -> void:
				var err: String = Game.order_hardware(model_pick, 1, String(tiers[tid]))
				if err != "":
					_toast(err)
				_refresh_ops()
				_refresh_money())))
	ops_box.add_child(order_btn)
	if Game.aisle_blocked():
		ops_box.add_child(_wrap(Loc.t("body.receiving_full"),
			12, Color(1.0, 0.72, 0.45), 780))
	for r_rma: Dictionary in Game.rmas:
		ops_box.add_child(_label(Loc.t("body.rma_row")
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
		var kl := _label(Loc.t("body.crate_row") % [Game.MODELS[crate["model"]]["label"], state], 12,
			Color(0.78, 0.84, 0.9))
		kl.add_theme_font_override("font", mono)
		kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		krow.add_child(kl)
		if int(crate["arrived"]) >= 0:
			if not bool(crate["checked"]):
				var chk := Button.new()
				chk.text = Loc.t("btn.check_order")
				chk.tooltip_text = Loc.t("tip.check_order")
				chk.pressed.connect(func() -> void:
					var err: String = Game.check_crate(crate)
					if err != "":
						_toast(err)
					_refresh_ops()
					_refresh_money())
				krow.add_child(chk)
			var unp := Button.new()
			unp.text = Loc.t("btn.unpack")
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
		prow.add_child(_label(Loc.t("body.cardboard") % Game.packaging,
			12, Color(1.0, 0.82, 0.5)))
		var clear_btn := Button.new()
		clear_btn.text = Loc.t("btn.take_out")
		clear_btn.pressed.connect(func() -> void:
			Game.clear_packaging()
			_refresh_ops())
		prow.add_child(clear_btn)

func _ops_assets_and_spares() -> void:
	ops_box.add_child(_section("ASSETS AND SPARES"))
	var shelf: Array = []
	for m in Game.spares:
		if int(Game.spares[m]) > 0:
			shelf.append("%s x%d" % [Game.MODELS[m]["label"], int(Game.spares[m])])
	ops_box.add_child(_label(Loc.t("body.on_shelf") % (", ".join(PackedStringArray(shelf))
		if not shelf.is_empty() else "nothing"), 13, Color(0.75, 0.8, 0.85)))
	# what is on the shelf is half the answer; the rest is what is coming
	var in_transit: Array = []
	var on_dock := 0
	for c: Dictionary in Game.crates:
		if int(c["arrived"]) >= 0:
			if Game.crate_site(c) == Game.current_site:
				on_dock += 1
			continue
		in_transit.append("%s → %s, cycle %d" % [Game.MODELS[c["model"]]["label"],
			Game.site_name(Game.crate_site(c)), int(c["due"])])
	if not in_transit.is_empty():
		ops_box.add_child(_wrap("  On the way: %s" % ", ".join(PackedStringArray(in_transit)),
			13, Color(0.7, 0.8, 0.9), 780))
	if on_dock > 0:
		ops_box.add_child(_label(Loc.t("body.on_dock") % on_dock,
			13, UIW.colour("warning")))
	var back_order: Array = []
	for m_id: String in Game.stockouts:
		if Game.stocked_out(m_id):
			back_order.append("%s until cycle %d" % [Game.MODELS[m_id]["label"],
				int(Game.stockouts[m_id])])
	if not back_order.is_empty():
		ops_box.add_child(_wrap(Loc.t("body.nobody_sells") % ", ".join(PackedStringArray(back_order)),
			13, UIW.colour("warning"), 780))
	var spare_btn := Button.new()
	spare_btn.text = Loc.t("btn.buy_spare")
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
		var fl := _label(Loc.t("body.spare_down") % [d.name,
			Game.MODELS[d.model]["label"], Loc.cycles(int(Game.device_age(d)))], 13, Prefs.bad_colour())
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frow.add_child(fl)
		var swap := Button.new()
		swap.text = Loc.t("btn.swap_spares")
		swap.pressed.connect(func() -> void:
			var err: String = Game.swap_from_spares(d)
			_refresh_ops()
			if err != "":
				_toast(err))
		frow.add_child(swap)
		var rma_btn := Button.new()
		rma_btn.text = Loc.t("btn.rma")
		rma_btn.tooltip_text = Loc.t("tip.rma")
		rma_btn.pressed.connect(func() -> void:
			var err: String = Game.send_rma(d)
			if err != "":
				_toast(err)
			_refresh_ops()
			get_parent().rebuild_racks())
		frow.add_child(rma_btn)

func _ops_runbooks_and_automation() -> void:
	ops_box.add_child(_section("RUNBOOKS AND AUTOMATION"))
	var rb_new := Button.new()
	rb_new.text = Loc.t("btn.new_runbook")
	rb_new.tooltip_text = Loc.t("tip.new_runbook")
	rb_new.pressed.connect(func() -> void:
		var actions: Array = Game.RUNBOOK_ACTIONS.keys()
		var act_opts: Array = []
		for act_id: String in actions:
			act_opts.append("%s: %s" % [Loc.t(String(Game.RUNBOOK_ACTIONS[act_id]["label"])),
				Loc.t(String(Game.RUNBOOK_ACTIONS[act_id]["blurb"]))])
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
		var rbl := _label(Loc.t("body.playbook_targets") % [rb_i["name"],
			Game.runbook_targets(rb_i).size(), int(rb_i["max_devices"])], 12,
			Color(0.78, 0.84, 0.9))
		rbl.add_theme_font_override("font", mono)
		rbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rbrow.add_child(rbl)
		var rb_dry := Button.new()
		rb_dry.text = Loc.t("btn.dry_run")
		rb_dry.pressed.connect(func() -> void:
			var out: Dictionary = Game.run_runbook(rb_i, true)
			for line: String in out["log"]:
				Game.log_event("DRY RUN: %s" % line)
			hud_toast(Loc.t("toast.dry_run") % [out["planned"].size(),
				out["skipped"].size()], String(out["refused"]) == "")
			_refresh_ops())
		rbrow.add_child(rb_dry)
		var rb_go := Button.new()
		rb_go.text = Loc.t("btn.run_it")
		rb_go.pressed.connect(func() -> void:
			var out: Dictionary = Game.run_runbook(rb_i, false, true)
			hud_toast(String(out["refused"]) if String(out["refused"]) != ""
				else Loc.t("toast.applied_devices") % out["applied"].size(),
				String(out["refused"]) == "")
			_refresh_ops())
		rbrow.add_child(rb_go)
		var rb_bind := Button.new()
		rb_bind.text = Loc.t("btn.bind_alert")
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
	# what automation actually did, newest first, and the way back
	var real_runs: Array = Game.runbook_runs.filter(func(rr): return not bool(rr.get("dry_run", true)))
	if not real_runs.is_empty():
		ops_box.add_child(_label(Loc.t("body.recent_runs"), 11, UIW.colour("muted")))
	real_runs.reverse()
	for run_i: Dictionary in real_runs.slice(0, 5):
		var runrow := HBoxContainer.new()
		runrow.add_theme_constant_override("separation", 8)
		ops_box.add_child(runrow)
		var run_lbl := _label(Loc.t("body.run_row") % [int(run_i.get("cycle", 0)), String(run_i.get("runbook", "")),
			String(run_i["refused"]) if String(run_i.get("refused", "")) != ""
			else "%d applied, %d skipped" % [run_i.get("applied", []).size(), run_i.get("skipped", []).size()]],
			12, Color(0.72, 0.78, 0.86))
		run_lbl.add_theme_font_override("font", mono)
		run_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		runrow.add_child(run_lbl)
		if not run_i.get("applied", []).is_empty() and run_i.has("before"):
			var rb_back := Button.new()
			rb_back.text = Loc.t("btn.roll_back")
			rb_back.tooltip_text = Loc.t("tip.roll_back")
			rb_back.pressed.connect(func() -> void:
				var back_err: String = Game.rollback_runbook(run_i)
				hud_toast(back_err if back_err != "" else Loc.t("toast.rolled_back") % run_i["before"].size(),
					back_err == "")
				_refresh_ops())
			runrow.add_child(rb_back)
	for m_t: Dictionary in Game.monitors:
		var rem_t: Dictionary = m_t.get("remediation", {})
		if rem_t.is_empty():
			continue
		ops_box.add_child(_label("  %s → '%s'" % [Game.monitor_label(m_t), rem_t["runbook"]],
			12, Color(0.72, 0.84, 0.8)))
		for line_t: String in rem_t.get("timeline", []):
			ops_box.add_child(_label("      %s" % line_t, 11, Color(0.68, 0.74, 0.82)))

func _ops_playbooks() -> void:
	ops_box.add_child(_section("PLAYBOOKS"))
	if Game.playbooks.is_empty():
		ops_box.add_child(_wrap(Loc.t("body.no_playbooks"),
			12, MUTED, 780))
	for pb: Dictionary in Game.playbooks:
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		ops_box.add_child(prow)
		var pl := _label(Loc.t("body.playbook_row") % [pb["name"], pb["lines"].size()], 12,
			Color(0.75, 0.82, 0.9))
		pl.add_theme_font_override("font", mono)
		pl.tooltip_text = "\n".join(PackedStringArray(pb["lines"]))
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prow.add_child(pl)
		var run_btn := Button.new()
		run_btn.text = Loc.t("btn.run_on")
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
				hud_toast(Loc.t("toast.playbook_ran") % [pb["name"],
					int(res["ran"]), int(res["failed"])], int(res["failed"]) == 0)
				_refresh_ops()))
		prow.add_child(run_btn)
		var del_btn := Button.new()
		del_btn.text = Loc.t("btn.delete")
		del_btn.pressed.connect(func() -> void:
			Game.delete_playbook(String(pb["name"]))
			_refresh_ops())
		prow.add_child(del_btn)
	var pb_name := _mono_edit(180)
	pb_name.placeholder_text = Loc.t("ph.playbook_name")
	var pb_body := TextEdit.new()
	pb_body.custom_minimum_size = Vector2(560, 90)
	pb_body.placeholder_text = Loc.t("ph.playbook_commands")
	pb_body.add_theme_font_override("font", mono)
	pb_body.add_theme_font_size_override("font_size", 12)
	var pb_row := HBoxContainer.new()
	pb_row.add_theme_constant_override("separation", 8)
	ops_box.add_child(pb_row)
	pb_row.add_child(pb_name)
	var pb_save := Button.new()
	pb_save.text = Loc.t("btn.save_playbook")
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

func _ops_certificates() -> void:
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
				renew.text = Loc.t("btn.renew")
				renew.pressed.connect(func() -> void:
					Game.issue_cert(c_row["dev"], String(c_row["name"]))
					_refresh_ops())
				crow.add_child(renew)

func _ops_monitors() -> void:
	ops_box.add_child(_section("MONITORS"))
	if Game.monitors.is_empty():
		ops_box.add_child(_label(Loc.t("body.no_checks"),
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
		del.text = Loc.t("btn.remove")
		del.pressed.connect(func() -> void:
			Game.remove_monitor(m)
			_refresh_ops())
		mrow.add_child(del)
	var add_mon := Button.new()
	add_mon.text = Loc.t("btn.add_check")
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
			var mon_err := Game.add_monitor(sp[0], sp[1], sp[2])
			if mon_err != "":
				_toast(mon_err)
			_refresh_ops()))
	ops_box.add_child(add_mon)

func _ops_devices(devs: Array) -> bool:
	ops_box.add_child(_section("DEVICES"))
	if devs.is_empty():
		ops_box.add_child(_label(Loc.t("body.nothing_installed"), 14, MUTED))
		return false
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
	return true

func _capacity_advice() -> String:
	## one sentence, and only when there is something worth saying
	var cap := Game.capacity(0)
	if int(cap["tiles_used"]) >= int(cap["tiles"]):
		return Loc.t("advice.no_tiles")
	if int(cap["slots"]) > 0 and int(cap["slots_used"]) >= int(cap["slots"]):
		return Loc.t("advice.units_full")
	if Game.overheating():
		return Loc.t("advice.too_hot")
	var runway := Game.capacity_runway("slots_used", int(cap["slots_used"]), int(cap["slots"]))
	if runway >= 0 and runway <= 6:
		return Loc.t("advice.runway") % [runway, Game.RACK_PRICE]
	return ""

func toggle_ops() -> void:
	if not _feature_available("ops"):
		hud_toast(Loc.t("toast.ops_locked"))
		return
	if ops_overlay.visible:
		ops_overlay.visible = false
	elif not is_open():
		_refresh_ops()
		_show_overlay(ops_overlay)
	else:
		hud_toast(Loc.t("toast.close_panel_ops"))

# ---------- keyboard help ----------

func _build_help() -> void:
	help_overlay = _overlay()
	var v := _card(help_overlay, 620)
	var t := _header(v, func() -> void: help_overlay.visible = false)
	t.text = Loc.t("help.title")
	var rows := [
		[Loc.t("help.floor"), ""],
		["Q / R", Loc.t("help.h1")],
		["Space", Loc.t("help.h2")],
		["1 / 2 / 3", Loc.t("help.h3")],
		["O", Loc.t("help.h4")],
		["F", Loc.t("help.h5")],
		["M", Loc.t("help.h6")],
		["F1", Loc.t("help.h7")],
		["Esc", Loc.t("help.h8")],
		["💾", Loc.t("help.h9")],
		["right / middle drag", Loc.t("help.h10")],
		["scroll wheel", Loc.t("help.h11")],
		[Loc.t("help.views"), ""],
		["click rack", Loc.t("help.h12")],
		["click device", Loc.t("help.h13")],
		["drag rack ports", Loc.t("help.h14")],
		["click port", Loc.t("help.h15")],
		["right-click blank", Loc.t("help.h16")],
		["Shift-drag (map)", Loc.t("help.h17")],
		["Esc", Loc.t("help.h18")],
		[Loc.t("help.console"), ""],
		["configuration", Loc.t("help.h19")],
		["Tab", Loc.t("help.h20")],
		["?", Loc.t("help.h21")],
		["Up / Down", Loc.t("help.h22")],
		["Ctrl-Z", Loc.t("help.h23")],
		["Ctrl-A / Ctrl-E", Loc.t("help.h24")],
		["Ctrl-U / Ctrl-K / Ctrl-W", Loc.t("help.h25")],
		["Ctrl-L / Ctrl-C", Loc.t("help.h26")],
		["clear", Loc.t("help.h27")],
		["!!", Loc.t("help.h28")],
		["paste", Loc.t("help.h29")],
		["terminal length N", Loc.t("help.h30")],
		["ssh <ip> / vtysh", Loc.t("help.h31")],
		["Esc", Loc.t("help.h32")],
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
	t.text = Loc.t("btn.packet_empire")
	var resume := Button.new()
	resume.text = Loc.t("menu.resume")
	_accent(resume)
	resume.pressed.connect(func() -> void: menu_overlay.visible = false)
	v.add_child(resume)
	var save := Button.new()
	save.text = Loc.t("menu.save")
	save.pressed.connect(func() -> void:
		_save_with_feedback()
		menu_overlay.visible = false)
	v.add_child(save)
	var save_as := Button.new()
	save_as.text = Loc.t("menu.save_as")
	save_as.pressed.connect(func() -> void:
		var opts: Array = []
		for i in Game.SLOTS:
			var info := Game.slot_info(i)
			opts.append("Slot %d: %s" % [i + 1, "damaged (delete it from the title screen first)"
				if info.get("broken", false) else "empty" if info.get("empty", true)
				else "%s, cycle %d" % [info["company"], int(info["cycle"])]])
		_menu(save_as, opts, func(id: int) -> void:
			if Game.slot_info(id).get("broken", false):
				hud_toast(Loc.t("toast.damaged_slot") % (id + 1), false)
				return
			if Game.drill_active:
				hud_toast(Loc.t("toast.not_saved_drill"), false)
				return
			if Puzzle.active():
				hud_toast(Loc.t("toast.not_saved_puzzle"), false)
				return
			Game.current_slot = id
			Game.save_game()
			hud_toast(Loc.t("toast.saved_slot") % (id + 1), true)))
	v.add_child(save_as)
	var title_btn := Button.new()
	title_btn.text = Loc.t("menu.to_title")
	title_btn.pressed.connect(func() -> void:
		Game.leave_side_modes()  # a drill, scenario or puzzle is scratch: the real world comes back and is saved
		Game.save_game()
		menu_overlay.visible = false
		get_parent().show_title())
	v.add_child(title_btn)
	v.add_child(_section(Loc.t("menu.section.practice")))
	var scen_btn := Button.new()
	scen_btn.text = Loc.t("menu.scenarios")
	scen_btn.tooltip_text = Loc.t("menu.scenarios.tip")
	scen_btn.pressed.connect(func() -> void:
		var opts: Array = []
		for sc: Dictionary in Scenarios.all():
			opts.append("%s: %s" % [Loc.t(String(sc["name"])), Loc.t(String(sc["blurb"]))])
		_menu(scen_btn, opts, func(id: int) -> void:
			menu_overlay.visible = false
			if Game.drill_active:
				hud_toast(Loc.t("toast.finish_drill_first"))
				return
			Scenarios.start(Scenarios.all()[id])
			get_parent().rebuild_racks()
			_show_scenario_banner()))
	v.add_child(scen_btn)
	var sandbox_btn := Button.new()
	sandbox_btn.text = Loc.t("menu.sandbox")
	sandbox_btn.tooltip_text = Loc.t("menu.sandbox.tip")
	sandbox_btn.pressed.connect(func() -> void:
		Game.sandbox = not Game.sandbox
		Game.log_event("SANDBOX: %s." % ("on, nothing costs anything" if Game.sandbox
			else "off, the business is running again"))
		menu_overlay.visible = false
		hud_toast(Loc.t("toast.sandbox_mode") % ("on" if Game.sandbox else "off"), Game.sandbox)
		_refresh_money())
	v.add_child(sandbox_btn)
	var prefs_btn := Button.new()
	prefs_btn.text = Loc.t("menu.settings")
	prefs_btn.pressed.connect(func() -> void:
		menu_overlay.visible = false
		_open_settings_card())
	v.add_child(prefs_btn)
	var prefs_legacy_btn := Button.new()  # the cycling popup, kept for the smoke tests
	prefs_legacy_btn.visible = false
	prefs_legacy_btn.pressed.connect(func() -> void:
		_menu(prefs_legacy_btn, [
			"%s: %s" % [Loc.t("settings.fullscreen"), _on_off(Prefs.fullscreen)],
			"%s: %d%%" % [Loc.t("settings.scale"), int(Prefs.ui_scale * 100)],
			"%s: %s" % [Loc.t("settings.colourblind"), _on_off(Prefs.colourblind)],
			"%s: %s" % [Loc.t("settings.sound"), _on_off(Prefs.sound)],
			"%s: %s" % [Loc.t("settings.motion"), _on_off(Prefs.reduced_motion)],
			"%s: %s" % [Loc.t("settings.toolbox"), _on_off(Prefs.show_everything)],
			"%s: %s" % [Loc.t("settings.language"), Loc.language_label(Prefs.language)],
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
			hud_toast(Loc.t("toast.setting_applied"), true)))
	v.add_child(prefs_legacy_btn)
	var diff_btn := Button.new()
	diff_btn.text = Loc.t("menu.difficulty")
	diff_btn.pressed.connect(func() -> void:
		var opts: Array = []
		for i in Game.DIFFICULTIES.size():
			var d: Dictionary = Game.DIFFICULTIES[i]
			opts.append("%s%s: %s" % ["▸ " if i == Game.difficulty else "   ", Loc.t(String(d["name"])), Loc.t(String(d["blurb"]))])
		_menu(diff_btn, opts, func(id: int) -> void:
			Game.apply_difficulty(id, false)
			hud_toast(Loc.t("toast.difficulty_set") % Loc.t(String(Game.DIFFICULTIES[id]["name"])), true)
			_refresh_money()))
	v.add_child(diff_btn)
	v.add_child(_section(Loc.t("menu.section.share")))
	var puzzle_btn := Button.new()
	puzzle_btn.text = Loc.t("btn.hand_fault")
	puzzle_btn.tooltip_text = Loc.t("tip.hand_fault")
	puzzle_btn.pressed.connect(func() -> void:
		_menu(puzzle_btn, [
			"Copy it as \"solve this\"",
			"Copy it as \"what am I missing\"",
			Loc.t("opt.copy_blind"),
			Loc.t("opt.open_puzzle"),
			Loc.t("opt.copy_fix") if Puzzle.active() else Loc.t("opt.read_fix"),
			Loc.t("opt.close_puzzle") if Puzzle.active() else Loc.t("opt.no_puzzle"),
		], func(id: int) -> void:
			if id <= 2:
				DisplayServer.clipboard_set(Puzzle.export_state(
					"review" if id == 1 else "solve", id == 2))
				hud_toast(Loc.t("toast.question_copied"), true)
			elif id == 3:
				var err: String = Puzzle.import_state(DisplayServer.clipboard_get())
				hud_toast(err if err != "" else "Puzzle open. Nothing here can cost you anything.",
					err == "")
				get_parent().rebuild_racks()
			elif id == 4 and Puzzle.active():
				DisplayServer.clipboard_set(Puzzle.solution())
				hud_toast(Loc.t("toast.fix_copied"), true)
			elif id == 4:
				var lines: Array = Puzzle.read_solution(DisplayServer.clipboard_get())
				for line: String in lines:
					Game.log_event("PUZZLE ANSWER: %s" % line)
				hud_toast(Loc.t("toast.answer_read") % lines.size(),
					not lines.is_empty())
			elif Puzzle.active():
				Puzzle.close()
				get_parent().rebuild_racks()
				hud_toast(Loc.t("toast.back_home"), true)))
	v.add_child(puzzle_btn)
	var drill_btn := Button.new()
	drill_btn.text = Loc.t("btn.incident_drill") % Drill.REWARD
	drill_btn.pressed.connect(func() -> void:
		if Game.drill_active:
			return
		menu_overlay.visible = false
		Drill.start(2 + Game.stage)  # bigger room, harder drills
		get_parent().rebuild_racks()
		_show_drill_banner())
	v.add_child(drill_btn)
	var workshop := Button.new()
	workshop.text = Loc.t("btn.content_workshop") % Pack.loaded.size()
	workshop.tooltip_text = Loc.t("tip.content_workshop")
	workshop.pressed.connect(func() -> void: _workshop_menu(workshop))
	v.add_child(workshop)
	var diagram := Button.new()
	diagram.text = Loc.t("btn.export_topology")
	diagram.tooltip_text = Loc.t("tip.export_topology")
	diagram.pressed.connect(func() -> void:
		var body: String = Game.export_topology()
		if body == "":
			_toast("could not write the export")
			return
		DisplayServer.clipboard_set(body)
		menu_overlay.visible = false
		hud_toast(Loc.t("toast.topology_exported"), true))
	v.add_child(diagram)
	var clab := Button.new()
	clab.text = Loc.t("btn.export_clab")
	clab.tooltip_text = Loc.t("tip.export_clab")
	clab.pressed.connect(func() -> void:
		var yaml: String = Game.export_containerlab()
		if yaml == "":
			_toast("could not write the lab")
			return
		DisplayServer.clipboard_set(yaml)
		menu_overlay.visible = false
		hud_toast(Loc.t("toast.lab_written") % ProjectSettings.globalize_path("user://clab"), true))
	v.add_child(clab)
	var chal_btn := Button.new()
	chal_btn.text = Loc.t("btn.challenge_code")
	chal_btn.tooltip_text = Loc.t("tip.challenge_code")
	chal_btn.pressed.connect(func() -> void:
		_menu(chal_btn, [
			"Play today's featured code (%s)" % Challenge.daily_code(),
			Loc.t("opt.play_code"),
			Loc.t("opt.copy_code") if not Challenge.active.is_empty() else Loc.t("opt.no_challenge"),
			Loc.t("opt.finish_card") if not Challenge.active.is_empty() else Loc.t("opt.nothing_finish"),
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
				hud_toast(Loc.t("toast.code_copied"), true)
			elif id == 3 and not Challenge.active.is_empty():
				var result: Dictionary = Challenge.finish()
				var lines: Array = Challenge.card(result)
				for line: String in lines:
					Game.log_event(line)
				for fault in result.get("faults", []):
					Game.log_event("DRILL debrief: " + str(fault))
				DisplayServer.clipboard_set("\n".join(PackedStringArray(lines)))
				get_parent().rebuild_racks()
				hud_toast(Loc.t("toast.scored") % int(result["total"]),
					bool(result["solved"]))))
	v.add_child(chal_btn)
	var quit := Button.new()
	quit.text = Loc.t("menu.quit")
	quit.pressed.connect(func() -> void:
		Game.leave_side_modes()
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
	scenario_box.add_child(_label(Loc.t("body.scenario") % Loc.t(String(sc["name"])), 16, Color(0.7, 0.9, 1.0)))
	var blurb := _label(Loc.t(String(sc["blurb"])), 13, Color(0.78, 0.82, 0.88))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(520, 0)
	scenario_box.add_child(blurb)
	if String(sc.get("hint", "")) != "":
		var sc_hint := _label("", 13, Color(0.62, 0.75, 0.85))
		sc_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sc_hint.custom_minimum_size = Vector2(520, 0)
		sc_hint.visible = false
		var sc_hint_btn := Button.new()
		sc_hint_btn.text = Loc.t("btn.show_approach")
		sc_hint_btn.pressed.connect(func() -> void:
			Challenge.note_hint()
			sc_hint.text = Loc.t(String(sc["hint"]))
			sc_hint.visible = true
			sc_hint_btn.visible = false)
		scenario_box.add_child(sc_hint_btn)
		scenario_box.add_child(sc_hint)
	for g in sc["goals"]:
		var ok: bool = g["t"].call()
		scenario_box.add_child(_label("   %s  %s" % ["●" if ok else "○", Loc.t(String(g["d"]))], 13,
			Prefs.ok_colour() if ok else Color(0.7, 0.7, 0.75)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	scenario_box.add_child(row)
	var check_btn := Button.new()
	check_btn.text = Loc.t("btn.check")
	_accent(check_btn)
	check_btn.pressed.connect(func() -> void:
		if Scenarios.solved():
			var nm: String = Loc.t(String(Scenarios.active["name"]))
			Scenarios.finish(true)
			get_parent().rebuild_racks()
			scenario_panel.visible = false
			hud_toast(Loc.t("toast.scenario_passed") % nm, true)
		else:
			_show_scenario_banner())
	row.add_child(check_btn)
	var leave_btn := Button.new()
	leave_btn.text = Loc.t("btn.leave_scenario")
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
	drill_box.add_child(_label(Loc.t("body.drill_banner"), 15, Color(1.0, 0.7, 0.6)))
	drill_box.add_child(_label(Drill.scenario, 13, Color(0.9, 0.85, 0.8)))
	if Game.site_count() > 1:
		# a fault may be in the room they are not standing in, and a player who
		# has never seen a two-site world will hunt for a switch in another city
		var floor_set := {}
		for dr in Game.racks:
			floor_set[int(dr.site)] = true
		var floor_names: Array = []
		for si in floor_set:
			floor_names.append(Game.site_name(int(si)))
		if floor_set.size() > 1:
			drill_box.add_child(_wrap(Loc.t("drill.floors")
				% [floor_set.size(), ", ".join(PackedStringArray(floor_names))], 12,
				UIW.colour("warm"), 620))
	if Drill.outcome.has("survive_ip"):
		drill_box.add_child(_wrap(Loc.t("body.drill_reach_either")
			% [Drill.outcome["survive_ip"], Drill.outcome["from_ip"]], 13,
			Color(0.9, 0.88, 0.8), 620))
	elif not Drill.outcome.is_empty():
		# a services incident has no pair of static addresses to light up: the
		# thing to restore is what the customer asked for
		var client: Net.NDevice = Drill.outcome["client"]
		drill_box.add_child(_label(Loc.t("body.drill_dhcp")
			% [client.name, Drill.outcome["name"]], 13, Color(0.9, 0.88, 0.8)))
	drill_box.add_child(_label(Loc.t("drill.broken"), 13, Color(0.85, 0.8, 0.78))
		if not Drill.targets.is_empty() else _label(Loc.t("drill.press_check"),
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
	chk.text = Loc.t("btn.check")
	_accent(chk)
	chk.pressed.connect(func() -> void:
		if Drill.solved():
			if not Challenge.active.is_empty():
				var result: Dictionary = Challenge.finish()  # scored, faults logged, best kept
				for line: String in Challenge.card(result):
					Game.log_event(line)
				for fault in result.get("faults", []):
					Game.log_event("DRILL debrief: " + str(fault))
			else:
				Drill.finish(true)
			get_parent().rebuild_racks()
			drill_panel.visible = false
		else:
			_show_drill_banner()  # re-renders per-pair status marks
			drill_box.add_child(_label(Loc.t("body.still_broken"), 12, Color(0.9, 0.6, 0.5))))
	row.add_child(chk)
	var give := Button.new()
	give.text = Loc.t("btn.abandon_reveal")
	give.pressed.connect(func() -> void:
		Challenge.active = {}  # giving up is not a scored run
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
	var map := UIW.TopoMap.new().setup(func(dev: Net.NDevice) -> void:
		map_overlay.visible = false
		cur_rack = Game.rack_of(dev)
		open_dev(dev),
		func(a: Net.NDevice, b: Net.NDevice) -> String:
			return Game.link_devices(a, b))
	map_overlay.add_child(map)
	map.offset_left = 184
	map.offset_top = 112
	map.offset_right = -24
	map.offset_bottom = -48
	var customers := OptionButton.new()
	customers.position = Vector2(420, 24)
	customers.custom_minimum_size = Vector2(230, 36)
	customers.tooltip_text = Loc.t("tip.highlight_customer")
	map.add_child(customers)
	var refresh_customers := func() -> void:
		customers.clear()
		customers.add_item("All services")
		customers.set_item_metadata(0, "")
		for deal: Dictionary in Game.deals:
			customers.add_item(String(deal["customer"]))
			var idx := customers.item_count - 1
			customers.set_item_metadata(idx, String(deal["id"]))
			if String(deal["id"]) == map.focus_customer_id: customers.select(idx)
	customers.item_selected.connect(func(idx: int) -> void:
		map.focus_customer_id = String(customers.get_item_metadata(idx))
		map.refresh_focus())
	map.visibility_changed.connect(refresh_customers)
	Game.topology_changed.connect(refresh_customers)

func toggle_map() -> void:
	if not _feature_available("map"):
		hud_toast(Loc.t("toast.map_locked_short"))
		return
	if map_overlay.visible:
		map_overlay.visible = false
	elif not is_open():
		_show_overlay(map_overlay)
	else:
		hud_toast(Loc.t("toast.close_panel_map"))

# ---------- tutorial checklist ----------

func _build_tutorial() -> void:
	tutorial_panel = UIW.CommandPanel.new().setup("console", "warm", UIW.space("lg"))
	tutorial_panel.theme = theme_res
	tutorial_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tutorial_panel.position = Vector2(-380, 112)
	tutorial_panel.custom_minimum_size = Vector2(356, 0)
	add_child(tutorial_panel)
	var brief_scroll := ScrollContainer.new()
	brief_scroll.set_meta("customer_brief", true)
	brief_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	brief_scroll.custom_minimum_size = Vector2(308, clampf(get_viewport().get_visible_rect().size.y - 260.0, 300.0, 560.0))  # the plan buttons stay above the fold at 1280x720
	tutorial_panel.add_child(brief_scroll)
	tutorial_panel.add_child(_more_hint(brief_scroll))
	_card_scrolls.append(brief_scroll)
	tutorial_box = VBoxContainer.new()
	tutorial_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_box.add_theme_constant_override("separation", UIW.space("sm"))
	brief_scroll.add_child(tutorial_box)
	_refresh_tutorial()

var tutorial_hidden := false

func focus_customer(deal: Dictionary) -> void:
	if not _feature_available("map"):
		hud_toast(Loc.t("toast.map_locked"))
		return
	close_everything()
	for child in map_overlay.get_children():
		if child is UIW.TopoMap:
			child.focus_customer_id = String(deal.get("id", ""))
			child.refresh_focus()
	_show_overlay(map_overlay)

func _next_job() -> Dictionary:
	for c in Contracts.all():
		if c["id"] not in Game.contracts_done and not Contracts.retired(c["id"]):
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
		tutorial_box.add_child(_tutorial_head(Loc.t("brief.deliver", {"customer": String(deal["customer"]).to_upper()})))
		tutorial_box.add_child(_wrap(Loc.t("tutorial.promise_sold") % Market.brief_for(deal), 13,
			UIW.colour("text"), 290))
		for check: Dictionary in Market.delivery_checks(deal):
			var check_ok := bool(check["ok"])
			var copy := "%s  %s\n     FIELD WORK  /  %s" % ["●" if check_ok else "○",
				check["promise"], check["work"]]
			tutorial_box.add_child(_wrap(copy, 12,
				Color(0.48, 0.9, 0.62) if check_ok else UIW.colour("muted"), 290))
		var reserve := int(deal.get("delivery_credit", 0))
		if reserve > 0:
			tutorial_box.add_child(_wrap(Loc.t("body.protected_reserve")
				% reserve, 11, UIW.colour("warm"), 290))
		var delivery_btn := Button.new()
		delivery_btn.text = Loc.t("brief.open_delivery")
		delivery_btn.pressed.connect(func() -> void:
			contracts_tab = "Jobs"
			open_contracts())
		tutorial_box.add_child(delivery_btn)
		return
	if not collected or not live:
		tutorial_box.add_child(_tutorial_head("BILL  /  %s" % String(deal["customer"]).to_upper()))
		tutorial_box.add_child(_label(Loc.t("body.service_billing") % [
			"●" if live else "!", "live" if live else "down",
			"active" if live else "SUSPENDED"], 12,
			Color(0.48, 0.9, 0.62) if live else Prefs.bad_colour()))
		tutorial_box.add_child(_label(Loc.t("body.first_invoice") % ("●" if invoiced else "○"),
			12, Color(0.48, 0.9, 0.62) if invoiced else UIW.colour("muted")))
		tutorial_box.add_child(_label(Loc.t("body.first_cash") % ("●" if collected else "○"),
			12, Color(0.48, 0.9, 0.62) if collected else UIW.colour("muted")))
		var invoice := _guided_invoice(deal)
		if not invoice.is_empty() and not collected:
			var due_in := maxi(0, int(invoice["due"]) - Game.cycle)
			tutorial_box.add_child(_wrap(Loc.t("body.receivable")
				% [int(invoice["amount"]), due_in, "" if due_in == 1 else "s"],
				11, UIW.colour("warm"), 290))
		var books_btn := Button.new()
		books_btn.text = Loc.t("btn.open_ledger")
		books_btn.pressed.connect(_open_business_desk)
		tutorial_box.add_child(books_btn)
		return
	tutorial_box.add_child(_tutorial_head("CUSTOMER LIVE  /  CASH MOVING"))
	for line in [Loc.t("arc.step_promise"),
			Loc.t("arc.step_invoice"),
			Loc.t("arc.step_cash")]:
		tutorial_box.add_child(_label("●  " + line, 12, Color(0.48, 0.9, 0.62)))
	var continue_btn := Button.new()
	continue_btn.text = Loc.t("btn.keep_operating_customer")
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
		tutorial_box.add_child(_wrap(Loc.t("body.monitor_alert")
			% incident.get("target_ip", "the customer address"), 12, Prefs.bad_colour(), 290))
		tutorial_box.add_child(_incident_button(Loc.t("btn.ack_incident"), func() -> void:
			Game.acknowledge_guided_outage(), true))
		return
	if state == "acknowledged":
		tutorial_box.add_child(_label(Loc.t("body.alert_owned"), 12, Color(0.48, 0.9, 0.62)))
		tutorial_box.add_child(_wrap(Loc.t("body.customer_comms"),
			12, UIW.colour("text"), 290))
		tutorial_box.add_child(_wrap(Loc.t("tutorial.post_now"),
			11, UIW.colour("warm"), 290))
		tutorial_box.add_child(_incident_button(Loc.t("btn.open_status_page"), func() -> void:
			contracts_tab = "Log"
			_refresh_contracts()
			_show_overlay(contracts_overlay), true))
		return
	if state in ["communicated", "investigating", "diagnosed", "repairing"]:
		tutorial_box.add_child(_label(Loc.t("body.customer_updated"), 12,
			Color(0.48, 0.9, 0.62)))
		var evidence: Array = incident.get("evidence", [])
		var ladder := [
			["monitor", "MONITOR", Loc.t("arc.monitor_step")],
			["physical", "PHYSICAL", Loc.t("arc.physical_step")],
			["l2", "L2", Loc.t("arc.l2_step")],
		]
		for step: Array in ladder:
			var done: bool = String(step[0]) in evidence
			tutorial_box.add_child(_label("%s  %-10s %s" % ["●" if done else "○", step[1], step[2]],
				11, Color(0.48, 0.9, 0.62) if done else UIW.colour("muted")))
		for step: Array in ladder:
			if String(step[0]) in evidence: continue
			tutorial_box.add_child(_incident_button(String(step[2]), func() -> void:
				var err := Game.guided_outage_probe(String(step[0]))
				if err != "": _toast(err)
				_refresh_tutorial()))
		if state not in ["diagnosed", "repairing"]:
			tutorial_box.add_child(_incident_button(Loc.t("btn.inspect_service_network"), func() -> void:
				focus_customer(Game.guided_customer_deal()), true))
			tutorial_box.add_child(_incident_button(Loc.t("btn.restore_with_help"), func() -> void:
				var err := Game.give_up_guided_outage()
				if err != "": _toast(err)
				_refresh_tutorial()))
			return
		tutorial_box.add_child(_wrap(Loc.t("body.root_cause")
			% [incident.get("device", "device"), incident.get("iface", "port")],
			12, UIW.colour("warm"), 290))
		var affected := Game.guided_outage_iface()
		if affected != null:
			var ros: bool = String(Game.MODELS[affected.dev.model].get("os", "")) == "ros"
			var command := "/interface set %s disabled=no" % affected.name if ros else \
				"interface %s  →  no shutdown" % affected.name
			tutorial_box.add_child(_wrap(Loc.t("body.repair_console") % command, 11,
				UIW.colour("text_strong"), 290))
			tutorial_box.add_child(_incident_button(Loc.t("btn.open_affected_port"), func() -> void:
				_goto_device(affected.dev)
				open_iface(affected), true))
		tutorial_box.add_child(_label(Loc.t("body.verify_cycle"),
			11, UIW.colour("muted")))
		var give_up := _incident_button(Loc.t("btn.teaching_restore"), func() -> void:
			var err := Game.give_up_guided_outage()
			if err != "": _toast(err)
			_refresh_tutorial())
		give_up.tooltip_text = Loc.t("tip.teaching_restore")
		tutorial_box.add_child(give_up)
		return
	if state == "recovered":
		tutorial_box.add_child(_label(Loc.t("body.service_restored"), 12,
			Color(0.48, 0.9, 0.62)))
		tutorial_box.add_child(_section("INCIDENT TIMELINE"))
		for note: String in incident.get("timeline", []):
			tutorial_box.add_child(_wrap("•  " + note, 10, UIW.colour("muted"), 290))
		tutorial_box.add_child(_incident_button(Loc.t("btn.review_harden"), func() -> void:
			Game.debrief_guided_outage(), true))
		return
	if state == "choice":
		tutorial_box.add_child(_wrap(Loc.t("body.what_changes"),
			12, UIW.colour("text"), 290))
		for option: Array in [
			["spare", Loc.t("arc.harden_spare")],
			["monitor", Loc.t("arc.harden_monitor")],
			["config", Loc.t("arc.harden_config")],
		]:
			tutorial_box.add_child(_incident_button(String(option[1]), func() -> void:
				var err := Game.choose_guided_resilience(String(option[0]))
				if err != "": _toast(err)
				else: hud_toast(Loc.t("toast.first_outage_closed"), true)
				_refresh_tutorial()))

var _brief_hidden_for := ""  # what was on the brief when it was closed

func _brief_key() -> String:
	if Game.guided_outage_active():
		return "outage"
	if FirstCustomer.active():
		return "sale:" + String(FirstCustomer.state().get("phase", ""))
	var job := _next_job()
	return String(job.get("id", "")) if not job.is_empty() else ""

func _refresh_tutorial() -> void:
	if tutorial_panel == null:
		return
	if tutorial_hidden and _brief_key() != _brief_hidden_for:
		tutorial_hidden = false  # a new job or an outage: the brief has something new to say
	if tutorial_hidden:
		tutorial_panel.visible = false
		return
	if Game.guided_outage_active():
		_render_guided_outage()
		return
	if FirstCustomer.active():
		CustomerBrief.render(self)
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
			tutorial_box.add_child(_tutorial_head(Loc.t("brief.deliver", {"customer": String(waiting["customer"]).to_upper()})))
			var promise := _wrap(Loc.t("body.promise_sold_todo") % Market.brief_for(waiting), 13,
				UIW.colour("text"), 290)
			tutorial_box.add_child(promise)
			tutorial_box.add_child(_label(Loc.t("body.prove_live"),
				12, UIW.colour("muted")))
			var desk_btn := Button.new()
			desk_btn.text = Loc.t("brief.open_delivery")
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
		tutorial_box.add_child(_tutorial_head(Loc.t(String(job["title"])).to_upper()))
		for rq in job["reqs"]:
			var rq_ok: bool = rq["t"].call()
			var rl := _label("%s  %s" % ["●" if rq_ok else "○", Loc.t(String(rq["d"]))], 13,
				Color(0.5, 0.9, 0.6) if rq_ok else Color(0.68, 0.72, 0.8))
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.custom_minimum_size = Vector2(290, 0)
			tutorial_box.add_child(rl)
		var open_btn := Button.new()
		open_btn.text = Loc.t("brief.open")
		open_btn.pressed.connect(open_contracts)
		tutorial_box.add_child(open_btn)
		return
	tutorial_panel.visible = true
	for c in tutorial_box.get_children():
		c.queue_free()
	tutorial_box.add_child(_tutorial_head(Loc.t("brief.getting_started")))
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
		[Loc.t("brief.step.rack"), Game.racks.size() >= 1],
		[Loc.t("brief.step.switch"), switches >= 1],
		[Loc.t("brief.step.servers"), servers >= 2],
		[Loc.t("brief.step.cable"), cabled >= 2],
		[Loc.t("brief.step.collect"), false],
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
	var eyebrow := _label(Loc.t("brief.next_move"), 12, UIW.colour("accent"))
	eyebrow.add_theme_font_override("font", mono)
	shell.add_child(eyebrow)
	var h := HBoxContainer.new()
	shell.add_child(h)
	var sec := _section(text)
	sec.add_theme_font_size_override("font_size", 18)
	sec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sec.add_theme_color_override("font_color", UIW.colour("text_strong"))
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sec)
	var x := Button.new()
	x.text = "×"
	x.tooltip_text = Loc.t("brief.hide.tip")
	x.flat = true
	x.pressed.connect(func() -> void:
		tutorial_hidden = true
		_brief_hidden_for = _brief_key()
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
	# the system menu is where the language was changed from: it must not be
	# the one panel left in the old one
	var menu_was := menu_overlay.visible
	menu_overlay.queue_free()
	_build_menu()
	menu_overlay.visible = menu_was
	pedia_overlay.queue_free()  # the chapter list is baked from the topics: rebuild it in the new language
	_build_pedia()
	help_overlay.queue_free()
	_build_help()
	search_overlay.queue_free()
	_build_search()
	rack_overlay.queue_free()  # the inspectors bake their captions at build time
	_build_rack_overlay()
	dev_overlay.queue_free()
	_build_dev_overlay()
	if_overlay.queue_free()
	_build_if_overlay()
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
			head.text = Loc.t("demo.first_night")
		var body := welcome_overlay.get_meta("body_label") as Label
		if body != null:
			body.text = Loc.t("finale.intro")
	_show_overlay(welcome_overlay)

# ---------- demo ----------

var demo_overlay: Control

func _build_demo_end() -> void:
	demo_overlay = _overlay()
	var v := _card(demo_overlay, 760)
	var t := _header(v, func() -> void: demo_overlay.visible = false)
	t.text = Loc.t("demo.shift_complete")
	var status := _section("OPENING ARC  /  NETWORK ONLINE  /  HANDOVER READY")
	status.add_theme_color_override("font_color", UIW.colour("success"))
	v.add_child(status)
	var body := _wrap(Loc.t("finale.empty_cage"),
		17, UIW.colour("text_strong"), 700)
	v.add_child(body)
	var achieved := HBoxContainer.new()
	achieved.add_theme_constant_override("separation", UIW.space("md"))
	v.add_child(achieved)
	achieved.add_child(_welcome_module("✓", Loc.t("demo.built.title"), Loc.t("demo.built.body"), "success"))
	achieved.add_child(_welcome_module("✓", Loc.t("demo.operated.title"), Loc.t("demo.operated.body"), "accent"))
	achieved.add_child(_welcome_module("→", Loc.t("demo.next.title"), Loc.t("demo.next.body"), "warm"))
	demo_overlay.set_meta("run_line", _wrap("", 13, UIW.colour("accent"), 700))
	v.add_child(demo_overlay.get_meta("run_line"))
	var beyond := UIW.style_panel(PanelContainer.new(), "console", "md")
	v.add_child(beyond)
	var beyond_box := VBoxContainer.new()
	beyond_box.add_theme_constant_override("separation", UIW.space("sm"))
	beyond.add_child(beyond_box)
	for line: String in [
		Loc.t("demo.beyond.0"),
		Loc.t("demo.beyond.1"),
		Loc.t("demo.beyond.2"),
		Loc.t("demo.beyond.3"),
		Loc.t("demo.beyond.4"),
		Loc.t("demo.beyond.5"),
		Loc.t("demo.beyond.6"),
	]:
		var l3 := _wrap(line, 12, UIW.colour("muted"), 700)
		l3.add_theme_font_override("font", mono)
		beyond_box.add_child(l3)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIW.space("sm"))
	v.add_child(row)
	var keep := Button.new()
	keep.text = Loc.t("demo.stay")
	keep.tooltip_text = Loc.t("tip.keep_world")
	keep.pressed.connect(func() -> void: demo_overlay.visible = false)
	_accent(keep)
	row.add_child(keep)
	var back := Button.new()
	back.text = Loc.t("demo.back")
	back.pressed.connect(func() -> void:
		Game.save_game()
		demo_overlay.visible = false
		get_parent().show_title())
	row.add_child(back)

var _demo_end_shown := false

func enter_world() -> void:
	## a new or loaded company: no consoles left open on the old one, and the
	## per-run cards start over
	cli_sessions.clear()
	_demo_end_shown = false
	tutorial_hidden = false

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
	t.text = Loc.t("company.title")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	for name in ["Jobs", "Business", "Market", "Log"]:
		var tb := Button.new()
		tb.text = Loc.t("company.tab." + String(name).to_lower())  # the id stays English; the label follows the language
		tb.toggle_mode = true
		tb.pressed.connect(func() -> void:
			contracts_tab = name
			_refresh_contracts())
		tabs.add_child(tb)
		contracts_tabs[name] = tb
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var holder := MarginContainer.new()  # scroll and hint share one box so the hint overlays
	holder.add_child(scroll)
	holder.add_child(_more_hint(scroll))
	v.add_child(holder)
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
	_biz_business_flow()
	_biz_receivables()
	_biz_energy_and_the_books()
	_biz_address_space()
	_biz_transit_and_peering()
	_biz_career_profile()
	_biz_marketing_and_cover()
	_biz_change_management()
	_biz_defence()
	_biz_quarterly_reports()
	_biz_achievements()
	_biz_history()
	_biz_staff()
	_biz_sites()
	_biz_wan_circuits()
	# (market moved to its own tab)

func _biz_business_flow() -> void:
	contracts_box.add_child(_section(Loc.t("company.flow.section")))
	contracts_box.add_child(_wrap(Loc.t("company.flow.body"), 12, UIW.colour("muted"), 600))
	var flow := GridContainer.new()
	flow.columns = 3
	flow.add_theme_constant_override("h_separation", UIW.space("sm"))
	flow.add_theme_constant_override("v_separation", UIW.space("sm"))
	contracts_box.add_child(flow)
	flow.add_child(_offer_fact("REVENUE EARNED", "+$%d\nservice delivered" % int(Game.last_business.get("revenue", 0)), "success"))
	flow.add_child(_offer_fact("INVOICES RAISED", "+$%d\nnow receivable" % int(Game.last_business.get("invoiced", 0)), "info"))
	flow.add_child(_offer_fact("CASH COLLECTED", "+$%d\nreached the bank" % int(Game.last_business.get("collected", 0)), "success"))
	if Game.stage >= 1:
		flow.add_child(_offer_fact("POWER COST", "-$%d\npaid this cycle" % int(Game.last_business.get("power", 0)), "warning"))
	else:
		flow.add_child(_offer_fact("POWER COST", "$0\nthe colo pays", "info"))
	flow.add_child(_offer_fact("TRANSIT COST", "-$%d\nports and traffic" % int(Game.last_business.get("transit", 0)), "warning"))
	var cash_delta := int(Game.last_cycle_delta)
	flow.add_child(_offer_fact("NET CASH", "%s$%d\nactual bank movement" % [
		"+" if cash_delta >= 0 else "-", absi(cash_delta)], "success" if cash_delta >= 0 else "danger"))

func _biz_receivables() -> void:
	contracts_box.add_child(_section("RECEIVABLES"))
	var owed := Game.receivables()
	var late := Game.overdue_invoices()
	contracts_box.add_child(_wrap(
		Loc.t("body.owed") % [owed, Game.invoices.size(),
			Loc.t("body.overdue_count") % late.size() if not late.is_empty() else ""],
		13, Prefs.bad_colour() if not late.is_empty() else Color(0.75, 0.82, 0.9), 560))
	if Game.invoices.is_empty():
		contracts_box.add_child(UIW.make_empty_state(
			"Nothing outstanding: everything you have billed has been paid."))
	for inv: Dictionary in Game.invoices.slice(0, 8):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		contracts_box.add_child(row)
		var due_in: int = int(inv.get("first_due", inv["due"])) - Game.cycle
		var state := "overdue by %d" % -due_in if due_in < 0 else \
			("due now" if due_in == 0 else "due in %d" % due_in)
		var il := _label("  %-18s $%-7d %s" % [inv["customer"], int(inv["amount"]), state], 12,
			Prefs.bad_colour() if due_in < 0 else Color(0.72, 0.78, 0.86))
		il.add_theme_font_override("font", mono)
		row.add_child(il)
		if due_in <= 0 and not bool(inv["chased"]):
			var chase := Button.new()
			chase.text = Loc.t("btn.chase")
			chase.tooltip_text = Loc.t("tip.chase")
			chase.pressed.connect(func() -> void:
				var err := Game.chase_invoice(inv)
				if err != "":
					_toast(err)
				_refresh_contracts())
			row.add_child(chase)
	if Game.invoices.size() > 8:
		contracts_box.add_child(_label(Loc.t("body.and_more") % (Game.invoices.size() - 8), 12, MUTED))

func _biz_energy_and_the_books() -> void:
	contracts_box.add_child(_section("ENERGY AND THE BOOKS"))
	if Game.stage >= 1:
		contracts_box.add_child(_wrap(
			"Drawing %dW of a nameplate %dW. The %s rate is $%.3f per watt per cycle, so the next bill is $%d. Electricity is dearest exactly when your customers are busiest."
			% [Game.effective_draw(), Game.power_draw_all(),
				"fixed" if Game.fixed_tariff else "spot", Game.energy_rate(), Game.power_bill()],
			13, Color(0.75, 0.82, 0.9), 560))
		var e_row := HBoxContainer.new()
		e_row.add_theme_constant_override("separation", 8)
		contracts_box.add_child(e_row)
		var tariff_btn := Button.new()
		tariff_btn.text = Loc.t("btn.spot_tariff") if Game.fixed_tariff \
			else Loc.t("btn.fixed_tariff")
		tariff_btn.tooltip_text = Loc.t("tip.fixed_tariff") % int(round((Game.FIXED_PREMIUM - 1.02) * 100.0))
		tariff_btn.pressed.connect(func() -> void:
			Game.set_fixed_tariff(not Game.fixed_tariff)
			_refresh_contracts())
		e_row.add_child(tariff_btn)
		var eff_btn := Button.new()
		eff_btn.text = Loc.t("btn.efficiency_retrofit") % (Game.EFFICIENCY_PRICE + Game.efficiency * 800)
		var eff_price := Game.EFFICIENCY_PRICE + Game.efficiency * 800
		var eff_save := Game.efficiency_saving()
		eff_btn.tooltip_text = "Removes %d%% of your draw, permanently: about $%d per cycle at today's draw and rate, so it pays back in %s." % [
			int(Game.EFFICIENCY_STEP * 100.0), eff_save,
			"%d cycles" % int(ceil(float(eff_price) / float(eff_save))) if eff_save > 0 else "never, there is nothing drawing power"]
		eff_btn.pressed.connect(func() -> void:
			var err := Game.buy_efficiency()
			if err != "":
				_toast(err)
			_refresh_contracts())
		e_row.add_child(eff_btn)
	else:
		contracts_box.add_child(_label(Loc.t("body.colo_pays_power"), 12, MUTED))
	contracts_box.add_child(_wrap(
		"This quarter: profit $%d, depreciation allowance $%d, tax as it stands $%d."
		% [Game.quarter_profit, Game.quarter_depreciation, Game.tax_due()],
		13, Color(0.75, 0.82, 0.9), 560))
	var acc_btn := Button.new()
	acc_btn.text = Loc.t("btn.dismiss_accountant") if Game.accountant \
		else Loc.t("btn.accountant") % Game.ACCOUNTANT_FEE
	acc_btn.tooltip_text = Loc.t("tip.accountant")
	acc_btn.pressed.connect(func() -> void:
		Game.hire_accountant(not Game.accountant)
		_refresh_contracts())
	contracts_box.add_child(acc_btn)

func _biz_address_space() -> void:
	contracts_box.add_child(_section("ADDRESS SPACE"))
	contracts_box.add_child(_wrap(
		Loc.t("body.ipv4_held")
		% [Game.ipv4_total(), Game.ipv4_used()], 13,
		Prefs.bad_colour() if Game.ipv4_free() <= 0 else Color(0.75, 0.82, 0.9), 560))
	var ip_btn := Button.new()
	ip_btn.text = Loc.t("btn.buy_slash29") % Game.ipv4_price()
	ip_btn.tooltip_text = Loc.t("tip.slash29")
	ip_btn.pressed.connect(func() -> void:
		var err := Game.buy_ipv4_block()
		if err != "":
			_toast(err)
		_refresh_contracts())
	contracts_box.add_child(ip_btn)

func _biz_transit_and_peering() -> void:
	contracts_box.add_child(_section("TRANSIT AND PEERING"))
	var billed := Game.transit_billed_mbps()
	contracts_box.add_child(_wrap(
		Loc.t("body.transit_95")
		% [billed, Game.TRANSIT_PER_MBPS, Game.transit_cost()], 13, Color(0.75, 0.82, 0.9), 560))
	if bool(Game.ixp.get("joined", false)):
		contracts_box.add_child(_label(Loc.t("body.at_exchange")
			% [int(Game.ixp.get("peers", 0)), int(Game.peering_share() * 100.0), Game.IXP_PORT_FEE],
			13, Color(0.65, 0.88, 0.72)))
		var peer_btn := Button.new()
		peer_btn.text = Loc.t("btn.approach_peer")
		peer_btn.pressed.connect(func() -> void:
			var err := Game.add_peering()
			if err != "":
				_toast(err)
			_refresh_contracts())
		contracts_box.add_child(peer_btn)
	else:
		var ixp_btn := Button.new()
		ixp_btn.text = Loc.t("btn.ix_port") % [
			Game.IXP_SETUP, Game.IXP_PORT_FEE]
		ixp_btn.tooltip_text = Loc.t("tip.peering")
		ixp_btn.pressed.connect(func() -> void:
			var err := Game.join_ixp()
			if err != "":
				_toast(err)
			_refresh_contracts())
		contracts_box.add_child(ixp_btn)
	var bank := HBoxContainer.new()
	bank.add_theme_constant_override("separation", 10)
	contracts_box.add_child(bank)
	bank.add_child(_label(Loc.t("body.bank_debt") % [Game.debt, int(Game.LOAN_RATE * 100)],
		13, Color(0.7, 0.75, 0.85) if Game.debt == 0 else Color(0.95, 0.75, 0.5)))
	var borrow := Button.new()
	borrow.text = Loc.t("btn.borrow") % Game.LOAN_TRANCHE
	borrow.disabled = Game.debt + Game.LOAN_TRANCHE > Game.LOAN_MAX
	borrow.pressed.connect(func() -> void:
		Game.borrow()
		_refresh_contracts())
	bank.add_child(borrow)
	if Game.debt > 0:
		var repay := Button.new()
		repay.text = Loc.t("btn.repay") % mini(Game.LOAN_TRANCHE, Game.debt)
		repay.disabled = Game.money < mini(Game.LOAN_TRANCHE, Game.debt)
		repay.pressed.connect(func() -> void:
			Game.repay()
			_refresh_contracts())
		bank.add_child(repay)
	var delta := Game.last_cycle_delta
	contracts_box.add_child(_label(Loc.t("body.last_cycle_net") % ["+" if delta >= 0 else "-", absi(delta)],
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
		var run_pl := _label(Loc.t("body.run_to_date") + "   ·   ".join(PackedStringArray(total_parts)),
			12, Color(0.6, 0.66, 0.78))
		run_pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		run_pl.custom_minimum_size = Vector2(560, 0)
		contracts_box.add_child(run_pl)
	var nr2 := Game.next_rank()
	contracts_box.add_child(_label(Loc.t("body.rank") % [Loc.t(Game.rank()),
		"" if nr2.is_empty() else "   ·   %d points to %s" % [int(nr2[1]), Loc.t(String(nr2[0]))]],
		13, Color(0.85, 0.8, 0.6)))
	contracts_box.add_child(_wrap(Loc.t("body.company_summary") % [Loc.t(Game.identity_label()), Game.cycle, Game.stats["earned"], Game.stats["contracts"], Game.stats["deals"], Game.stats["incidents"], Game.stats["faults"]], 12, Color(0.5, 0.56, 0.68)))

func _biz_career_profile() -> void:
	contracts_box.add_child(_section("CAREER PROFILE"))
	for line: String in Skills.profile():
		contracts_box.add_child(_wrap("  %s" % line, 12, Color(0.72, 0.8, 0.88), 640))

func _biz_marketing_and_cover() -> void:
	contracts_box.add_child(_section("MARKETING AND COVER"))
	var mk_row := HBoxContainer.new()
	contracts_box.add_child(mk_row)
	mk_row.add_child(_wrap(Loc.t("body.marketing") % [Game.marketing,
		int(round((Game.marketing_budget_factor() - 1.0) * 100.0)), 2 + int(Game.marketing / Game.MARKETING_STEP),
		int(round((0.7 + 0.06 * float(Game.marketing) / float(Game.MARKETING_STEP)) * 100.0))],
		13, Color(0.8, 0.85, 0.7) if Game.marketing > 0 else Color(0.75, 0.75, 0.8)))
	var mk_up := Button.new()
	mk_up.text = Loc.t("btn.spend_more")
	mk_up.pressed.connect(func() -> void:
		Game.marketing += Game.MARKETING_STEP
		_refresh_contracts())
	mk_row.add_child(mk_up)
	if Game.marketing > 0:
		var mk_down := Button.new()
		mk_down.text = Loc.t("btn.cut_back")
		mk_down.pressed.connect(func() -> void:
			Game.marketing = maxi(0, Game.marketing - Game.MARKETING_STEP)
			_refresh_contracts())
		mk_row.add_child(mk_down)
	var ins_row := HBoxContainer.new()
	contracts_box.add_child(ins_row)
	ins_row.add_child(_wrap(Loc.t("body.insurance") % [
		"ON" if Game.insured else "off", Game.insurance_fee(), Game.estate_value()], 13,
		Color(0.7, 0.9, 0.7) if Game.insured else Color(0.75, 0.75, 0.8)))
	var ins_btn := Button.new()
	ins_btn.text = Loc.t("btn.cancel") if Game.insured else Loc.t("btn.take_cover")
	ins_btn.pressed.connect(func() -> void:
		Game.insured = not Game.insured
		_refresh_contracts())
	ins_row.add_child(ins_btn)

func _biz_change_management() -> void:
	contracts_box.add_child(_section("CHANGE MANAGEMENT"))
	var maint_row := HBoxContainer.new()
	contracts_box.add_child(maint_row)
	maint_row.add_child(_label(Loc.t("body.windows_used") % [
		(Loc.t("body.window_open") % Game.maintenance_until) if Game.in_maintenance()
		else Loc.t("body.no_window"),
		Game.maintenance_used], 13,
		Color(0.7, 0.9, 0.7) if Game.in_maintenance() else Color(0.75, 0.75, 0.8)))
	var maint_btn := Button.new()
	maint_btn.text = Loc.t("btn.declare_window")
	maint_btn.tooltip_text = Loc.t("tip.window")
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
		finish_btn.text = Loc.t("btn.close_out")
		finish_btn.pressed.connect(func() -> void:
			var err: String = Game.complete_change()
			if err != "":
				_toast(err)
			_refresh_contracts())
		crow.add_child(finish_btn)
		var abort_btn := Button.new()
		abort_btn.text = Loc.t("btn.abort_revert")
		abort_btn.tooltip_text = Loc.t("tip.abort_revert")
		abort_btn.pressed.connect(func() -> void:
			Game.abort_change()
			_refresh_contracts())
		crow.add_child(abort_btn)
		if not bool(cw["pushed"]):
			var push_btn := Button.new()
			push_btn.text = Loc.t("btn.push_past_rollback")
			push_btn.tooltip_text = Loc.t("tip.push_past")
			_accent(push_btn)
			push_btn.pressed.connect(func() -> void:
				Game.push_on_change()
				_refresh_contracts())
			crow.add_child(push_btn)
	else:
		var plan_btn := Button.new()
		plan_btn.text = Loc.t("btn.submit_change_plan")
		plan_btn.tooltip_text = Loc.t("tip.change_plan")
		if frozen != "":
			contracts_box.add_child(_label(Loc.t("body.change_freeze") % frozen,
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
				Loc.t("btn.override_freeze") if frozen != "" else Loc.t("btn.two_cycles_backout"),
			], func(id: int) -> void:
				var minutes: int = [4, 4, 8, 2][id]
				var err: String = Game.submit_change("planned work on %s" % targets[0],
					targets, minutes, id != 1, id == 3 and frozen != "")
				if err != "":
					_toast(err)
				_refresh_contracts()))
		contracts_box.add_child(plan_btn)

func _biz_defence() -> void:
	contracts_box.add_child(_section("DEFENCE"))
	var scrub_row := HBoxContainer.new()
	contracts_box.add_child(scrub_row)
	scrub_row.add_child(_label(Loc.t("body.scrubbing") % [
		"ON" if Game.scrubbing else "off", Game.SCRUB_FEE], 13,
		Color(0.6, 0.9, 0.7) if Game.scrubbing else Color(0.75, 0.75, 0.8)))
	var scrub_btn := Button.new()
	scrub_btn.text = Loc.t("btn.disable") if Game.scrubbing else Loc.t("btn.enable")
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
		contracts_box.add_child(_label(Loc.t("body.under_attack")
			% [a["target"], a["customer"], int(a["cycles_left"]), state], 13,
			Color(0.95, 0.6, 0.45) if not (Game.scrubbing or blackholed) else Color(0.85, 0.85, 0.6)))

func _biz_quarterly_reports() -> void:
	if not Game.reports.is_empty():
		contracts_box.add_child(_section("QUARTERLY REPORTS"))
		for rep: Dictionary in Game.reports.slice(0, 4):
			var rl := _label(Loc.t("body.quarter_row") % [
				int(rep["quarter"]), int(rep["money"]),
				"+" if int(rep["net"]) >= 0 else "-", absi(int(rep["net"])),
				int(rep["deals"]), int(rep["uptime"]), int(rep["staff"]), rep["rank"]],
				12, Color(0.72, 0.8, 0.88))
			rl.add_theme_font_override("font", mono)
			contracts_box.add_child(rl)

func _biz_achievements() -> void:
	contracts_box.add_child(_section("ACHIEVEMENTS  (%d of %d)" % [Game.achievements.size(),
		Game.ACHIEVEMENTS.size()]))
	for a: Dictionary in Game.ACHIEVEMENTS:
		var got: bool = a["id"] in Game.achievements
		contracts_box.add_child(_label("  %s  %-26s %s" % ["★" if got else "☆", Loc.t(String(a["name"])), Loc.t(String(a["how"]))],
			12, Prefs.ok_colour() if got else Color(0.55, 0.58, 0.66)))

func _biz_history() -> void:
	contracts_box.add_child(_section("HISTORY"))
	if Game.history.size() < 2:
		contracts_box.add_child(_label(Loc.t("body.charts_later"),
			13, Color(0.6, 0.62, 0.7)))
	else:
		for g in [["money", "Cash", UIW.colour("success")],
				["net", "Net per cycle", Color(0.6, 0.8, 1.0)],
				["reputation", "Reputation", Color(0.95, 0.8, 0.5)]]:
			contracts_box.add_child(UIW.Graph.new().setup(g[0], g[1], g[2]))

func _biz_staff() -> void:
	contracts_box.add_child(_section("STAFF"))
	if Game.staff.is_empty():
		contracts_box.add_child(_label(Loc.t("body.no_payroll_faults"),
			13, Color(0.7, 0.7, 0.75)))
	if not Game.staff.is_empty() and not Staff.anyone_on_shift():
		contracts_box.add_child(_wrap(Loc.t("body.nobody_on_shift")
			% Game.day_name(), 13, Color(1.0, 0.8, 0.5), 560))
		if Game.callout_ready():
			# the thing you actually do at three in the morning
			var callout := Button.new()
			callout.text = Loc.t("btn.call_somebody_out") % Game.CALLOUT_FEE
			callout.tooltip_text = Loc.t("tip.call_somebody_out")
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
		if Staff.on_call(m) and Game.oncall_stint() >= Game.ONCALL_STINT:
			state += ", on call %s" % Loc.cycles(Game.oncall_stint())
		# the row carries five buttons as well, so the text is kept to the name
		# and the numbers; the rest moves to the line underneath it
		var sl := _label(Loc.t("body.staff_row") % [m["name"],
			int(m["skill"]), int(m["salary"]), int(m.get("morale", 70))], 12,
			Prefs.bad_colour() if int(m.get("morale", 70)) < 30 else Color(0.78, 0.85, 0.8))
		sl.add_theme_font_override("font", mono)
		sl.tooltip_text = "%s\nShift: %s\nMarket rate: $%d\nCertifications: %s" % [
			Loc.t(String(Staff.ROLES[m["role"]]["blurb"])), Staff.SHIFTS[Staff.shift_of(m)]["label"],
			Staff.market_rate(m),
			", ".join(PackedStringArray(m.get("certs", []))) if not m.get("certs", []).is_empty()
			else "none"]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		srow.add_child(sl)
		contracts_box.add_child(_wrap(Loc.t("body.staff_detail") % [Loc.t(Staff.label(m)),
			state, "  (under market)" if under else "", Staff.habit_read(m)], 12,
			Color(0.6, 0.68, 0.78), 640))
		var oncall_btn := Button.new()
		oncall_btn.text = "☎ On call" if Staff.on_call(m) else "☎ Not on call"
		oncall_btn.tooltip_text = Loc.t("tip.oncall") % Staff.ONCALL_RETAINER
		if Staff.on_call(m):
			_accent(oncall_btn)
		oncall_btn.pressed.connect(func() -> void:
			Game.set_oncall("" if Staff.on_call(m) else String(m["name"]))
			_refresh_contracts()
			_refresh_money())
		srow.add_child(oncall_btn)
		var shift_btn := Button.new()
		shift_btn.text = Staff.SHIFTS[Staff.shift_of(m)]["label"]
		shift_btn.tooltip_text = Loc.t("tip.shift")
		shift_btn.pressed.connect(func() -> void:
			Staff.set_shift(m, "night" if Staff.shift_of(m) == "day" else "day")
			_refresh_contracts())
		srow.add_child(shift_btn)
		var raise_btn := Button.new()
		raise_btn.text = Loc.t("btn.raise")
		raise_btn.tooltip_text = Loc.t("tip.raise")
		raise_btn.pressed.connect(func() -> void:
			Staff.give_raise(m, maxi(20, int(m["salary"]) / 10))
			_refresh_contracts())
		srow.add_child(raise_btn)
		var train_btn := Button.new()
		train_btn.text = Loc.t("btn.train")
		train_btn.disabled = busy > 0
		train_btn.pressed.connect(func() -> void:
			var opts: Array = []
			var keys: Array = []
			for course in Staff.COURSES:
				var c: Dictionary = Staff.COURSES[course]
				var off_role: bool = String(c.get("role", "")) != "" and String(c["role"]) != String(m["role"])
				opts.append("%s   $%d, %d cycles off the floor%s" % [Loc.t(String(c["label"])),
					int(c["cost"]) * 3 / 2 if off_role else int(c["cost"]),
					int(c["cycles"]) + (1 if off_role else 0),
					"   (written for a %s: dearer and longer)" % Loc.t(String(Staff.ROLES[c["role"]]["label"])) if off_role else ""])
				keys.append(course)
			_menu(train_btn, opts, func(id: int) -> void:
				var err := Staff.start_course(m, String(keys[id]))
				if err != "":
					_toast(err)
				_refresh_contracts()))
		srow.add_child(train_btn)
		var fire_btn := Button.new()
		fire_btn.text = Loc.t("btn.let_go")
		fire_btn.pressed.connect(func() -> void:
			Game.fire(m)
			_refresh_contracts())
		srow.add_child(fire_btn)
	Game.refresh_candidates()
	var hire_btn := Button.new()
	var income_now := Game.recurring_income()
	hire_btn.text = Loc.t("btn.hire_someone") % [Staff.payroll(), income_now]
	hire_btn.tooltip_text = "A junior asks $230 to $580 a cycle. The floor bills $%d a cycle right now%s" % [income_now,
		": it cannot carry anybody yet" if income_now < 230 else ""]
	hire_btn.pressed.connect(func() -> void:
		var opts: Array = []
		for c: Dictionary in Game.candidates:
			opts.append("%-18s %-18s skill %d   asking $%d/cycle%s" % [c["name"], Loc.t(Staff.label(c)),
				int(c["skill"]), int(c["ask"]),
				"   (they countered: $%d)" % int(c["counter"]) if c.has("counter") else ""])
		if opts.is_empty():
			_toast("no candidates right now: the market refreshes every few cycles")
			return
		_menu(hire_btn, opts, func(id: int) -> void:
			var cand: Dictionary = Game.candidates[id]
			# offer nine tenths of what they asked for and see what happens; a counter on the table is paid
			var offered := int(cand["counter"]) if cand.has("counter") else int(float(int(cand["ask"])) * 0.9)
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

func _biz_sites() -> void:
	contracts_box.add_child(_section("SITES"))
	for i in Game.site_count():
		var rent := int(Game.sites[i].get("rent", 0))
		contracts_box.add_child(_label(Loc.t("body.site_row") % [Game.site_name(i),
			Game.site_city(i), Game.grid_size(i).x, Game.grid_size(i).y, Game.racks_on(i).size(),
			"   $%d/cycle rent" % rent if rent > 0 else ""], 13, Color(0.75, 0.8, 0.85)))
	var lease := Button.new()
	lease.text = Loc.t("btn.lease_site")
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

func _biz_wan_circuits() -> void:
	if Game.site_count() > 1:
		contracts_box.add_child(_section("WAN CIRCUITS"))
		for c: Dictionary in Game.circuits.duplicate():
			var crow := HBoxContainer.new()
			contracts_box.add_child(crow)
			var carrier_name := String(c.get("carrier", "?"))
			var carrier_ok := Game.carrier_up(carrier_name)
			var cl := _label(Loc.t("body.circuit_row") % [c["label"],
				Game.site_name(int(c["a"])), Game.site_name(int(c["b"])), carrier_name,
				int(c["fee"]), "" if carrier_ok else "   CARRIER OUTAGE"],
				13, Color(0.7, 0.85, 0.9) if carrier_ok else Prefs.bad_colour())
			cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			crow.add_child(cl)
			var cancel := Button.new()
			cancel.text = Loc.t("btn.cancel")
			cancel.tooltip_text = Loc.t("tip.cancel_circuit")
			cancel.pressed.connect(func() -> void:
				Game.cancel_circuit(c)
				_refresh_contracts())
			crow.add_child(cancel)
		for i2 in Game.site_count():
			for j2 in range(i2 + 1, Game.site_count()):
				var route := Game.circuits_between(i2, j2)
				if route.size() == 1:
					contracts_box.add_child(_wrap(
						"  %s ⇄ %s rides one circuit from %s. When they have a bad afternoon, so do you."
						% [Game.site_name(i2), Game.site_name(j2),
							String(route[0].get("carrier", "?"))], 12, Color(1.0, 0.8, 0.5), 560))
				elif route.size() >= 2 and not Game.carrier_diverse(i2, j2):
					contracts_box.add_child(_wrap(
						"  %s ⇄ %s has two circuits from the same carrier. That is one bad afternoon away from being no circuits at all."
						% [Game.site_name(i2), Game.site_name(j2)], 12, Color(1.0, 0.8, 0.5), 560))
				elif Game.carrier_diverse(i2, j2):
					contracts_box.add_child(_label(
						"  %s ⇄ %s is carrier diverse." % [Game.site_name(i2), Game.site_name(j2)],
						12, Color(0.6, 0.88, 0.7)))
		var order := Button.new()
		order.text = Loc.t("btn.order_circuit")
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

func _build_market_tab() -> void:
	var pipeline_anchor := VBoxContainer.new()
	pipeline_anchor.add_theme_constant_override("separation", UIW.space("sm"))
	contracts_box.add_child(pipeline_anchor)
	if not Game.references.is_empty():
		contracts_box.add_child(_wrap(Loc.t("business.reference")
			% ", ".join(PackedStringArray(Game.references)), 13, Color(0.65, 0.88, 0.72), 560))
	if Game.market_intel == 0:
		contracts_box.add_child(_label(Loc.t("business.no_intel"),
			13, Color(0.6, 0.62, 0.7)))
	else:
		contracts_box.add_child(_label(Loc.t("business.intel") % Game.market_intel,
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
		take.text = Loc.t("btn.sell_company")
		take.tooltip_text = Loc.t("tip.sell_company")
		take.pressed.connect(func() -> void:
			_menu(take, ["Yes. Take the money and walk."], func(_id: int) -> void:
				Game.accept_buyout()
				_refresh_contracts()))
		bo_row.add_child(take)
		var refuse := Button.new()
		refuse.text = Loc.t("btn.turn_down")
		refuse.tooltip_text = Loc.t("tip.turn_down")
		refuse.pressed.connect(func() -> void:
			Game.decline_buyout()
			_refresh_contracts())
		_accent(refuse)
		bo_row.add_child(refuse)
	if Game.sold_out:
		contracts_box.add_child(_wrap(Loc.t("business.sold_company"),
			14, Color(0.7, 0.75, 0.85), 560))
	pipeline_anchor.add_child(_section("PIPELINE"))
	if Game.leads.is_empty():
		var pipeline_empty := UIW.make_empty_state(
			Loc.t("body.pipeline_empty"))
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
			Loc.t(String(Market.TYPES.get(String(lead.get("ctype", "enterprise")), {}).get("label", "customer"))),
			Market.label_for(lead["kind"]),
			"a lead" if lead["stage"] == "lead" else "out to tender"], 16, Color.WHITE))
		if String(lead["stage"]) == "lead":
			lv.add_child(_wrap(Loc.t("market.word_is")
				% Loc.t(String(lead["heard"])), 13, Color(0.75, 0.8, 0.85)))
			lv.add_child(_label(Loc.t("market.expires") % int(lead["ttl"]), 12, MUTED))
			var qbtn := Button.new()
			qbtn.text = Loc.t("btn.go_see_them") % Market.LEAD_QUALIFY_COST
			qbtn.tooltip_text = Loc.t("tip.go_see")
			_accent(qbtn)
			qbtn.pressed.connect(func() -> void:
				var err := Game.qualify_lead(lead)
				if err != "":
					_toast(err if err != "nothing there" else "%s had no budget after all." % lead["customer"])
				_refresh_contracts())
			lv.add_child(qbtn)
			continue
		lv.add_child(_wrap(Loc.t("market.they_want") % Market.rfp_requirements(lead), 13,
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
			var coaching_text := _wrap(Loc.t("body.proposal_review")
				% Game.sentence(String(lead["coach"])), 12, UIW.colour("text_strong"), 600)
			coaching.add_child(coaching_text)
			lv.add_child(coaching)
		lv.add_child(_label(Loc.t("market.tender_closes") % int(lead["ttl"]), 12, MUTED))
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		lv.add_child(prow)
		prow.add_child(_label(Loc.t("market.your_price"), 14))
		var pprice := _mono_edit(90)
		pprice.placeholder_text = str(int(serve["floor"]) + 18)
		pprice.tooltip_text = Loc.t("tip.price_start")
		prow.add_child(pprice)
		prow.add_child(_label(Loc.t("body.per_cycle_commit"), 14))
		var sla_opt := OptionButton.new()
		for ti in 3:
			sla_opt.add_item(Market.tier(ti)["label"])
		sla_opt.select(int(lead["sla"]))
		sla_opt.tooltip_text = Loc.t("tip.sla_commit") % Market.tier(int(lead["sla"]))["label"]
		prow.add_child(sla_opt)
		var sbtn := Button.new()
		sbtn.text = Loc.t("btn.submit_proposal")
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
				_toast(Loc.t("toast.not_signed")
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
		var l := _label(Loc.t("body.competitor_row") % [r["name"],
			Loc.t(String(strat["label"])), int(r["deals"]), Rivals.racks_needed(r), premises, price],
			13, Color(0.8, 0.78, 0.7))
		l.tooltip_text = ("%s\n\nBuying %s brings %d rack(s) and %d contract(s). %s" % [
			Loc.t(String(strat["blurb"])), r["name"], Rivals.racks_needed(r), int(r["deals"]),
			(Loc.t("body.rival_site") % r["site"]["name"])
			if Rivals.has_site(r)
			else Loc.t("body.rival_racks_fit")])
		var temper: Dictionary = Rivals.temper_of(r)
		var standing := int(r.get("standing", 0))
		l.tooltip_text += "\n\n%s %s" % [Loc.t(String(temper["blurb"])),
			Loc.t("body.nemesis") % Game.nemesis_reason if String(r["name"]) == Game.nemesis
			else (Loc.t("body.owe_you") if standing >= 2
				else (Loc.t("body.friction") if standing <= -1 else ""))]
		l.add_theme_font_override("font", mono)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var buy := Button.new()
		buy.text = Loc.t("btn.acquire")
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
	if not Game.handover.is_empty():
		# what the shift going home left on the desk
		contracts_box.add_child(_section("HANDOVER  /  FROM THE %s SHIFT"
			% String(Game.handover["from"]).to_upper()))
		contracts_box.add_child(_label(Loc.t("body.written_at") % int(Game.handover["cycle"]),
			12, UIW.colour("muted")))
		for line in Game.handover["lines"]:
			contracts_box.add_child(_wrap("  · %s" % String(line), 13,
				UIW.colour("text_strong"), 640))
		if bool(Game.handover.get("read", false)):
			contracts_box.add_child(_label(Loc.t("body.read"), 12, UIW.colour("success")))
		else:
			var ho_btn := Button.new()
			ho_btn.text = Loc.t("btn.read_it")
			ho_btn.tooltip_text = Loc.t("tip.read_notes")
			ho_btn.pressed.connect(func() -> void:
				Game.read_handover()
				_refresh_contracts())
			contracts_box.add_child(ho_btn)
	if Game.upstream_active():
		contracts_box.add_child(_section("SOMEBODY ELSE'S OUTAGE"))
		contracts_box.add_child(_wrap(Loc.t("body.upstream_down") % Game.upstream["party"],
			13, Color(1.0, 0.8, 0.5), 640))
		for line: String in Game.upstream_evidence():
			contracts_box.add_child(_wrap("      · %s" % line, 12, Color(0.7, 0.8, 0.85), 640))
		var urow := HBoxContainer.new()
		urow.add_theme_constant_override("separation", 8)
		contracts_box.add_child(urow)
		var case_btn := Button.new()
		case_btn.text = Loc.t("btn.chase_case") if bool(Game.upstream.get("opened", false)) else Loc.t("btn.open_case")
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
		contracts_box.add_child(_wrap(Loc.t("body.customers_describe"),
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
				tri.text = Loc.t("btn.triage")
				tri.tooltip_text = Loc.t("tip.triage")
				tri.pressed.connect(func() -> void:
					_menu(tri, Game.TICKET_AREAS, func(id: int) -> void:
						var err: String = Game.triage_ticket(t_i2, String(Game.TICKET_AREAS[id]))
						if err != "":
							_toast(err)
						_refresh_contracts()
						_refresh_money()))
				trow.add_child(tri)
			var cbtn := Button.new()
			cbtn.text = Loc.t("btn.close_it")
			cbtn.tooltip_text = Loc.t("tip.close_it")
			cbtn.pressed.connect(func() -> void:
				Game.close_ticket(t_i2)
				_refresh_contracts())
			trow.add_child(cbtn)
	contracts_box.add_child(_section("STATUS PAGE"))
	if Game.outage_open():
		contracts_box.add_child(_label(Loc.t("body.say_so"),
			13, Color(1.0, 0.8, 0.5)))
	var post_row := HBoxContainer.new()
	contracts_box.add_child(post_row)
	var post_in := _mono_edit(380)
	post_in.placeholder_text = Loc.t("ph.status_update")
	post_row.add_child(post_in)
	var post_btn := Button.new()
	post_btn.text = Loc.t("btn.post_update")
	post_btn.pressed.connect(func() -> void:
		var err: String = Game.post_status(post_in.text)
		if err != "":
			_toast(err)
		_refresh_contracts())
	post_row.add_child(post_btn)
	for p: Dictionary in Game.status_posts.slice(0, 4):
		contracts_box.add_child(_label(Loc.t("body.cycle_note") % [int(p["cycle"]), p["text"]], 12,
			Color(0.7, 0.8, 0.85)))
	# what a written-up incident told you to do about it, kept where it happened
	for done_inc: Dictionary in Game.incidents:
		if bool(done_inc.get("reviewed", false)) and String(done_inc.get("follow_up", "")) != "":
			contracts_box.add_child(_wrap(Loc.t("body.written_up")
				% [Loc.t(String(done_inc.get("cause", ""))), Loc.t(String(done_inc["follow_up"]))], 12,
				Color(0.62, 0.82, 0.72), 640))
	var open_reviews: Array = []
	for inc: Dictionary in Game.incidents:
		if not bool(inc.get("reviewed", false)):
			open_reviews.append(inc)
	if not open_reviews.is_empty():
		contracts_box.add_child(_section("INCIDENTS AWAITING A POST-MORTEM"))
		for inc: Dictionary in open_reviews:
			var irow := HBoxContainer.new()
			contracts_box.add_child(irow)
			var il := _label(Loc.t("body.cycle_note") % [int(inc["cycle"]), inc["summary"]], 13,
				Color(0.95, 0.72, 0.55))
			il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			irow.add_child(il)
			var replay_btn := Button.new()
			replay_btn.text = Loc.t("btn.replay")
			replay_btn.tooltip_text = Loc.t("tip.replay")
			replay_btn.pressed.connect(func() -> void:
				replay_for = int(inc["cycle"]) if replay_for != int(inc["cycle"]) else -1
				_refresh_contracts())
			irow.add_child(replay_btn)
			var rbtn := Button.new()
			rbtn.text = Loc.t("btn.write_up")
			rbtn.pressed.connect(func() -> void:
				_menu(rbtn, Game.REVIEW_CAUSES.map(func(c): return Loc.t(String(c))), func(id: int) -> void:
					Game.review_incident(inc, id)
					_refresh_contracts()))
			irow.add_child(rbtn)
			if String(inc.get("by", "")) != "" and not inc.has("blame"):
				var brow := HBoxContainer.new()
				brow.add_theme_constant_override("separation", 8)
				contracts_box.add_child(brow)
				brow.add_child(_wrap(Loc.t("body.phone_caused")
					% ("You" if String(inc["by"]) == "you" else String(inc["by"])),
					13, Color(1.0, 0.72, 0.45), 420))
				for say: Array in Game.BLAME_CHOICES:
					var sbtn := Button.new()
					sbtn.text = Loc.t(String(say[1]))
					sbtn.pressed.connect(func() -> void:
						var blame_err := Game.blame_incident(inc, String(say[0]))
						if blame_err != "":
							_toast(blame_err)
						_refresh_contracts())
					brow.add_child(sbtn)
			elif inc.has("blame"):
				contracts_box.add_child(_label(Loc.t("body.said") % Game.blame_said(inc), 12, MUTED))
			if replay_for == int(inc["cycle"]):
				var frames := Game.replay_around(int(inc["cycle"]))
				if frames.is_empty():
					contracts_box.add_child(_label(Loc.t("body.nothing_that_far"), 12, MUTED))
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
			contracts_box.add_child(_label(Loc.t("body.resolved_row") % [int(inc2["cycle"]),
				inc2["summary"], inc2.get("cause", "")], 12, Color(0.6, 0.75, 0.65)))

	Game.mark_events_read()
	if Game.events.is_empty():
		contracts_box.add_child(_label(Loc.t("log.nothing_yet"), 13, MUTED))
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
		contracts_box.add_child(_label(Loc.t("body.nothing_at_level"), 12, MUTED))
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
		open_btn.text = "Hide" if expanded_digest == at else Loc.t("btn.read_it")
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
		nb.add_child(_label(Loc.t("body.phone_out_of_hours") % String(Game.DAY_NAMES[
			int(Game.night_call.get("cycle", Game.cycle)) % Game.DAY_CYCLES]).to_upper(),
			12, UIW.colour("warm")))
		nb.add_child(_wrap("“%s.”" % Game.sentence(String(Game.night_call["reason"])), 14,
			UIW.colour("text_strong"), 620))
		var nrow := HBoxContainer.new()
		nrow.add_theme_constant_override("separation", 8)
		nb.add_child(nrow)
		var in_btn := Button.new()
		var oncall_now := Staff.by_name(Game.oncall)
		in_btn.text = Loc.t("btn.get_somebody") % (Game.CALLOUT_FEE / 2 if not oncall_now.is_empty()
			else Game.CALLOUT_FEE)
		in_btn.tooltip_text = Loc.t("tip.get_somebody")
		_accent(in_btn)
		in_btn.pressed.connect(func() -> void:
			var err := Game.answer_night_call(true)
			if err != "":
				_toast(err)
			_refresh_contracts()
			_refresh_money())
		nrow.add_child(in_btn)
		var wait_btn := Button.new()
		wait_btn.text = Loc.t("btn.waits_morning")
		wait_btn.tooltip_text = Loc.t("tip.waits_morning")
		wait_btn.pressed.connect(func() -> void:
			Game.answer_night_call(false)
			_refresh_contracts())
		nrow.add_child(wait_btn)
	_jobs_customer_window()
	_jobs_bid_desk()
	_jobs_active_deals()
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
		cv.add_child(_label(Loc.t("body.integration") % a["rival"], 16, Color.WHITE))
		var where: String = ("on their own site '%s' (switch floors in the HUD, and reaching it needs a leased circuit)"
			% Game.site_name(int(a.get("site", 0)))) if bool(a.get("premises", false)) else "moved into your room"
		var brief := _label(Loc.t("body.acquired_kit") % [where, a["net"], int(a["vlan"])], 13, Color(0.78, 0.82, 0.78))
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.custom_minimum_size = Vector2(560, 0)
		cv.add_child(brief)
		for req in Game.integration_status(a):
			var ok: bool = req["ok"]
			var txt: String = ("●  " if ok else "○  ") + String(req["d"])
			if not ok and String(req.get("detail", "")) != "":
				txt += "   (%s)" % req["detail"]
			cv.add_child(_label(txt, 13, UIW.colour("success") if ok else Color(0.7, 0.65, 0.6)))
		var btn := Button.new()
		btn.text = Loc.t("btn.check_integration")
		_accent(btn)
		btn.pressed.connect(func() -> void:
			Game.try_complete_integration(a)
			_refresh_contracts())
		cv.add_child(btn)

func _jobs_customer_window() -> void:
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

func _jobs_bid_desk() -> void:
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
			Loc.t(String(ct2.get("label", "")))], "info"))
		offer_head.add_child(UIW.make_chip("%d CYCLES LEFT" % int(offer["ttl"]),
			"warning" if int(offer["ttl"]) <= 2 else "accent"))
		if ct2.has("note"):
			cv.add_child(_wrap(Loc.t("body.market_intel") % [Loc.t(String(ct2["note"])), Loc.t(String(offer["hint"]))],
				13, UIW.colour("muted"), 620))

		var ask := UIW.style_panel(PanelContainer.new(), "console", "md")
		cv.add_child(ask)
		var ask_box := VBoxContainer.new()
		ask_box.add_theme_constant_override("separation", UIW.space("sm"))
		ask.add_child(ask_box)
		var ask_tag := _section("CLIENT ASK")
		ask_tag.add_theme_color_override("font_color", UIW.colour("accent"))
		ask_box.add_child(ask_tag)
		ask_box.add_child(_wrap(Market.brief_for(offer), 14, UIW.colour("text_strong"), 620))

		var otier := Market.tier(int(offer.get("sla", 0)))
		var facts := HBoxContainer.new()
		facts.add_theme_constant_override("separation", UIW.space("sm"))
		cv.add_child(facts)
		if float(otier["uptime"]) > 0.0:
			facts.add_child(_offer_fact("SERVICE LEVEL", "%s  ·  %.1fx penalty" % [otier["label"],
				float(otier["penalty"])], "warning"))
		else:
			facts.add_child(_offer_fact("SERVICE LEVEL", Loc.t("fact.best_effort"), "success"))
		facts.add_child(_offer_fact("DELIVERY", Market.costs_for(offer), "info"))
		var est: Array = Game.market_estimate(offer)
		var market_copy := Loc.t("body.no_rival_bidder")
		if not Rivals.best_bidder(offer).is_empty():
			market_copy = (Loc.t("body.no_price_signal") if est.is_empty() else Loc.t("body.price_likely") % [
				int(est[0]), int(est[1])])
		facts.add_child(_offer_fact("MARKET RANGE", market_copy,
			"success" if Rivals.best_bidder(offer).is_empty() else "warm"))
		if bool(offer.get("public", false)):
			var blocked := Game.can_accept_offer(offer)
			cv.add_child(_wrap(Loc.t("body.public_address")
				% ("" if blocked == "" else "  You have none free: buy a /29 or let this one go."),
				12, Prefs.bad_colour() if blocked != "" else UIW.colour("info"), 620))
		if offer["state"] == "counter":
			cv.add_child(_wrap(Loc.t("body.counteroffer") % int(offer["budget"]),
				14, UIW.colour("warm")))
			var row := HBoxContainer.new()
			cv.add_child(row)
			var acc := Button.new()
			acc.text = Loc.t("btn.accept_per_cycle") % int(offer["budget"])
			_accent(acc)
			acc.pressed.connect(func() -> void:
				Game.accept_counter(offer)
				_refresh_contracts())
			row.add_child(acc)
			var wa := Button.new()
			wa.text = Loc.t("btn.walk_away")
			wa.pressed.connect(func() -> void:
				Game.dismiss_offer(offer)
				_refresh_contracts())
			row.add_child(wa)
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			cv.add_child(row)
			row.add_child(_label(Loc.t("market.your_price"), 14))
			var quote := _mono_edit(90)
			quote.placeholder_text = "75"
			row.add_child(quote)
			row.add_child(_label(Loc.t("body.per_cycle"), 14, MUTED))
			var send := Button.new()
			send.text = Loc.t("btn.send_quote")
			_accent(send)
			quote.text_submitted.connect(func(_t: String) -> void: send.pressed.emit())
			send.pressed.connect(func() -> void:
				if not quote.text.strip_edges().is_valid_int():
					_toast(Loc.t("toast.whole_dollar"))
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
			dis.text = Loc.t("btn.decline")
			dis.pressed.connect(func() -> void:
				Game.dismiss_offer(offer)
				_refresh_contracts())
			row.add_child(dis)

func _jobs_active_deals() -> void:
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
				call_box.add_child(_label(Loc.t("body.the_phone") % String(deal["customer"]).to_upper(),
					12, UIW.colour("warm")))
				call_box.add_child(_wrap("“%s”" % deal["call"]["words"], 14,
					UIW.colour("text_strong"), 620))
				var call_row := HBoxContainer.new()
				call_row.add_theme_constant_override("separation", 8)
				call_box.add_child(call_row)
				for option: Dictionary in Game.CALL_ANSWERS:
					var ob2 := Button.new()
					ob2.text = Loc.t(String(option["label"]))
					ob2.tooltip_text = Loc.t(String(option["blurb"]))
					ob2.pressed.connect(func() -> void:
						Game.answer_call(deal, String(option["id"]))
						_refresh_contracts())
					call_row.add_child(ob2)
			if deal.has("dr_due") and not bool(deal.get("dr_done", false)):
				contracts_box.add_child(_label(Loc.t("body.want_failover")
					% int(deal["dr_due"]), 12, UIW.colour("warning")))
			if deal.has("promised_by"):
				contracts_box.add_child(_label(Loc.t("body.promised_back")
					% int(deal["promised_by"]), 12, Color(1.0, 0.82, 0.5)))
			var note_row := HBoxContainer.new()
			note_row.add_theme_constant_override("separation", 8)
			contracts_box.add_child(note_row)
			if not deal.get("note", {}).is_empty():
				note_row.add_child(_wrap("      note: \"%s\" (%d cycle(s) ago)"
					% [deal["note"]["text"], Game.deal_note_age(deal)], 12,
					Color(0.85, 0.8, 0.6), 520))
			var note_edit := LineEdit.new()
			note_edit.placeholder_text = Loc.t("ph.customer_note")
			note_edit.custom_minimum_size = Vector2(320, 0)
			note_edit.text = String(deal.get("note", {}).get("text", ""))
			note_row.add_child(note_edit)
			var note_save := Button.new()
			note_save.text = Loc.t("btn.keep")
			note_save.pressed.connect(func() -> void:
				Game.set_deal_note(deal, note_edit.text)
				_refresh_contracts())
			note_row.add_child(note_save)
			if deal.has("dispute"):
				var dis: Dictionary = deal["dispute"]
				var drow := HBoxContainer.new()
				drow.add_theme_constant_override("separation", 8)
				contracts_box.add_child(drow)
				var dis_lbl := _label(Loc.t("body.arguing") % Game.dispute_kind(
					String(dis.get("kind", "")))["demand"], 13, Color(1.0, 0.72, 0.45))
				# the demand is a sentence: wrap it, or the three buttons after it
				# walk off the right edge of the card
				dis_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				dis_lbl.custom_minimum_size = Vector2(420, 0)
				dis_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				drow.add_child(dis_lbl)
				if not bool(dis.get("warned", false)):
					var write_btn := Button.new()
					write_btn.text = Loc.t("btn.put_in_writing")
					write_btn.tooltip_text = Loc.t("tip.put_in_writing")
					write_btn.pressed.connect(func() -> void:
						Game.warn_customer(deal)
						_refresh_contracts())
					drow.add_child(write_btn)
				var give_btn := Button.new()
				give_btn.text = Loc.t("btn.their_way")
				give_btn.tooltip_text = Loc.t("tip.their_way")
				give_btn.pressed.connect(func() -> void:
					Game.concede_dispute(deal)
					_refresh_contracts())
				drow.add_child(give_btn)
				var firm_btn := Button.new()
				firm_btn.text = Loc.t("btn.hold_firm")
				firm_btn.tooltip_text = Loc.t("tip.hold_firm")
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
				urow.add_child(_label(Loc.t("body.grown") % [
					int(up["load"]), int(up["fee"])], 13, Color(0.6, 0.9, 0.75)))
				var up_yes := Button.new()
				up_yes.text = Loc.t("btn.take_it")
				up_yes.tooltip_text = Loc.t("tip.take_it")
				_accent(up_yes)
				up_yes.pressed.connect(func() -> void:
					Game.accept_upsell(deal)
					_refresh_contracts())
				urow.add_child(up_yes)
				var up_no := Button.new()
				up_no.text = Loc.t("btn.decline")
				up_no.tooltip_text = Loc.t("tip.decline_remember")
				up_no.pressed.connect(func() -> void:
					Game.decline_upsell(deal)
					_refresh_contracts())
				urow.add_child(up_no)
			if deal.has("renewal"):
				var rn: Dictionary = deal["renewal"]
				var rrow := HBoxContainer.new()
				rrow.add_theme_constant_override("separation", 8)
				contracts_box.add_child(rrow)
				rrow.add_child(_label(Loc.t("body.up_for_renewal") % [
					int(rn["fee"]), int(rn["uptime"]), rn["mood"]], 13, Color(1.0, 0.85, 0.5)))
				var acc_btn := Button.new()
				acc_btn.text = Loc.t("btn.renew")
				_accent(acc_btn)
				acc_btn.pressed.connect(func() -> void:
					Game.accept_renewal(deal)
					_refresh_contracts())
				rrow.add_child(acc_btn)
				var end_btn := Button.new()
				end_btn.text = Loc.t("btn.let_end")
				end_btn.pressed.connect(func() -> void:
					Game.decline_renewal(deal)
					_refresh_contracts())
				rrow.add_child(end_btn)
			var detail := Market.brief_for(deal)
			var spec_bits: Array = []
			for k in deal["params"]:
				spec_bits.append("%s: %s" % [k, str(deal["params"][k])])
			if not spec_bits.is_empty():
				detail += "   [" + ", ".join(PackedStringArray(spec_bits)) + "]"
			var dtier := Market.tier(int(deal.get("sla", 0)))
			if int(deal.get("cycles", 0)) > 0:
				var up_pct := 100.0 * float(deal.get("up_cycles", 0)) / float(deal["cycles"])
				detail += "   [%s, %d%% uptime over %s]" % [dtier["label"], int(up_pct),
					Loc.cycles(int(deal["cycles"]))]
			var missed_n: int = int(deal.get("missed", 0))
			if missed_n >= 3:
				detail += "   ⚠ undelivered %d cycles: they walk at 5" % missed_n
			if detail != "":
				var dl := _label("      " + detail, 12,
					Color(0.6, 0.66, 0.76) if ok else Color(0.8, 0.68, 0.6))
				dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				dl.custom_minimum_size = Vector2(560, 0)
				contracts_box.add_child(dl)

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
		opts.append("%s %s: %s" % ["✓" if bool(row["ok"]) else "✗", row["name"], summary])
	opts.append(Loc.t("opt.reload_packs"))
	opts.append(Loc.t("opt.import_pack"))
	opts.append(Loc.t("opt.copy_diag"))
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
		hud_toast(Loc.t("toast.pack_details"), bool(row["ok"]))
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
	hud_toast(Loc.t("toast.diagnostics_copied"), true)

func _open_settings_card() -> void:
	## the same switches the title screen has, in a card, so three settings
	## are three clicks and 90% can be picked directly
	if settings_overlay != null and is_instance_valid(settings_overlay):
		settings_overlay.queue_free()
	settings_overlay = _overlay()
	var v := _card(settings_overlay, 420)
	var t := _header(v, func() -> void: settings_overlay.visible = false)
	t.text = Loc.t("title.settings")
	var rows := [
		["settings.fullscreen", func() -> bool: return Prefs.fullscreen, func(on: bool) -> void: Prefs.fullscreen = on, ""],
		["settings.sound", func() -> bool: return Prefs.sound, func(on: bool) -> void: Prefs.sound = on, ""],
		["settings.colourblind", func() -> bool: return Prefs.colourblind, func(on: bool) -> void: Prefs.colourblind = on, ""],
		["settings.motion", func() -> bool: return Prefs.reduced_motion, func(on: bool) -> void: Prefs.reduced_motion = on, Loc.t("settings.motion.desc")],
		["settings.toolbox", func() -> bool: return Prefs.show_everything, func(on: bool) -> void: Prefs.show_everything = on, Loc.t("settings.toolbox.desc")],
		["settings.hints", func() -> bool: return Prefs.learner_hints, func(on: bool) -> void: Prefs.learner_hints = on, "A comment line under a console error that says what to try, and a LEARN chip that opens the field manual. Off for the real thing."],
	]
	for row in rows:
		var cbtn := CheckButton.new()
		cbtn.text = Loc.t(String(row[0]))
		cbtn.tooltip_text = String(row[3])
		cbtn.button_pressed = bool((row[1] as Callable).call())
		cbtn.toggled.connect(func(on: bool) -> void:
			(row[2] as Callable).call(on)
			Prefs.apply()
			_rebuild_localised())
		v.add_child(cbtn)
	for slider_spec in [["settings.volume", func() -> int: return Prefs.volume, func(val: int) -> void: Prefs.volume = val],
			["settings.music", func() -> int: return Prefs.music_volume, func(val: int) -> void: Prefs.music_volume = val]]:
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 6)
		v.add_child(srow)
		srow.add_child(_label(Loc.t(String(slider_spec[0])), 13, MUTED))
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.step = 5
		sl.value = int((slider_spec[1] as Callable).call())
		sl.custom_minimum_size = Vector2(180, 0)
		sl.value_changed.connect(func(val: float) -> void:
			(slider_spec[2] as Callable).call(int(val))
			Prefs.apply()
			Sfx.play("click"))
		srow.add_child(sl)
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 6)
	v.add_child(lang_row)
	lang_row.add_child(_label(Loc.t("settings.language"), 13, MUTED))
	for code: String in Loc.languages():
		var lb := Button.new()
		lb.text = Loc.language_label(code)
		lb.toggle_mode = true
		lb.button_pressed = Prefs.language == code
		lb.pressed.connect(func() -> void:
			Prefs.language = code
			Loc.language = code
			Prefs.apply()
			_rebuild_localised()
			_open_settings_card())
		lang_row.add_child(lb)
	v.add_child(_label(Loc.t("settings.scale"), 13, MUTED))
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 6)
	v.add_child(scale_row)
	for step: float in [0.9, 1.0, 1.15, 1.3]:
		var b2 := Button.new()
		b2.text = "%d%%" % int(step * 100)
		b2.toggle_mode = true
		b2.button_pressed = absf(Prefs.ui_scale - step) < 0.01
		b2.pressed.connect(func() -> void:
			Prefs.ui_scale = step
			get_tree().root.content_scale_factor = step
			Prefs.apply()
			_open_settings_card())
		scale_row.add_child(b2)
	_show_overlay(settings_overlay)

func _save_with_feedback() -> void:
	## the save button says what it did, and when it did nothing
	if Game.drill_active:
		hud_toast(Loc.t("toast.not_saved_drill"), false)
		return
	if Puzzle.active():
		hud_toast(Loc.t("toast.not_saved_puzzle"), false)
		return
	Game.save_game()
	var slot_name := "the autosave" if Game.current_slot >= Game.SLOTS else "slot %d" % (Game.current_slot + 1)
	hud_toast(Loc.t("toast.saved_to") % [slot_name, Time.get_time_string_from_system()], true)

func _toast(text: String) -> void:
	## an error where the player is looking: inside the Company panel when
	## that is what is open, otherwise on the HUD, never into a hidden box
	if contracts_overlay != null and contracts_overlay.visible:
		if _toast_lbl == null or not is_instance_valid(_toast_lbl):
			_toast_lbl = _label("", 14, Color(1.0, 0.85, 0.5))
			contracts_box.add_child(_toast_lbl)
			contracts_box.move_child(_toast_lbl, 0)
		_toast_lbl.text = text
		_ensure_visible.call_deferred(_toast_lbl)  # the sender sits far down a long panel
		Sfx.play("bad")
		return
	hud_toast(text, false)

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
	title_box.add_child(_label("%s  /  %s" % [Loc.t(String(debrief.get("title", "Contract"))),
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
	var mastery_copy := _wrap(Loc.t("body.optional_mastery") % ["●" if mastered else "◇",
		debrief.get("mastery", "")], 12,
		UIW.colour("success") if mastered else UIW.colour("muted"), 570)
	mastery_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mastery_row.add_child(mastery_copy)
	if not mastered:
		var mastery_btn := Button.new()
		mastery_btn.text = Loc.t("btn.check_mastery")
		mastery_btn.pressed.connect(func() -> void:
			var err := Game.check_contract_mastery(String(debrief["id"]))
			if err != "": _toast(err)
			_refresh_contracts())
		mastery_row.add_child(mastery_btn)
	var continue_btn := Button.new()
	continue_btn.text = Loc.t("btn.continue_operating")
	_accent(continue_btn)
	continue_btn.pressed.connect(func() -> void:
		Game.dismiss_contract_debrief()
		_refresh_contracts())
	box.add_child(continue_btn)

func _refresh_contracts() -> void:
	_refresh_money()  # reputation moved by a panel action shows in the header at once
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
	var rank_shown := 0
	for c in Contracts.all():
		var done: bool = c["id"] in Game.contracts_done
		if done:
			if Contracts.retired(c["id"]):
				contracts_box.add_child(_chip_row("RETIRED", Color(0.55, 0.6, 0.7),
					"%s: %s   superseded by a later job" % [Loc.t(String(c["title"])), c["customer"]],
					14, Color(0.55, 0.6, 0.7)))
				continue
			var healthy: bool = Game.sla_status.get(c["id"], true)
			var mrr: int = Game.contract_fee(c)
			if healthy:
				contracts_box.add_child(_chip_row("DONE", Color(0.4, 0.85, 0.5),
					"%s: %s   service fee +$%d / cycle" % [Loc.t(String(c["title"])), c["customer"], mrr],
					14, Color(0.55, 0.8, 0.6)))
			else:
				contracts_box.add_child(_chip_row("BREACH", Color(0.95, 0.45, 0.35),
					"%s: %s   SLA BREACH: service down, not paying!" % [Loc.t(String(c["title"])), c["customer"]],
					14, Color(0.95, 0.55, 0.4)))
				for rq in c["reqs"]:
					var rq_ok: bool = rq["t"].call()
					contracts_box.add_child(_label("      %s  %s" % ["●" if rq_ok else "○", Loc.t(String(rq["d"]))],
						12, Color(0.5, 0.8, 0.55) if rq_ok else Color(0.95, 0.6, 0.45)))
			continue
		if active_shown >= 3:
			contracts_box.add_child(_label(Loc.t("body.more_jobs"), 13, Color(0.45, 0.5, 0.6)))
			break
		if Contracts.rank_locked(c):
			rank_shown += 1
			if rank_shown > 3:
				continue  # a few rank chips say what is coming; they do not use up the job window
			contracts_box.add_child(_chip_row("RANK", Color(0.75, 0.65, 0.4),
				"%s: %s   comes to a %s; you are a %s" % [Loc.t(String(c["title"])), c["customer"], Loc.t(String(c["rank"])), Loc.t(Game.rank())],
				14, Color(0.75, 0.7, 0.55)))
			continue
		active_shown += 1
		found_active = true
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _sb(Color(0.09, 0.12, 0.16), ACCENT * Color(1, 1, 1, 0.5), 8, 14))
		contracts_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		cv.add_child(_label(Loc.t("body.job_reward") % [Loc.t(String(c["title"])), c["customer"], c["reward"]], 17, Color.WHITE))
		var need_model := Contracts.needs_model(c)
		if need_model != "" and Game.MODELS.has(need_model):
			cv.add_child(_label(Loc.t("demo.needs") % [Game.MODELS[need_model]["label"], int(Game.MODELS[need_model]["price"])], 13, Color(0.85, 0.8, 0.6)))
		var brief := _label(Loc.t(String(c["brief"])), 14, Color(0.75, 0.8, 0.88))
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.custom_minimum_size = Vector2(560, 0)
		cv.add_child(brief)
		for r in c["reqs"]:
			var ok: bool = r["t"].call()
			cv.add_child(_label(("●  " if ok else "○  ") + Loc.t(String(r["d"])), 14,
				UIW.colour("success") if ok else Color(0.65, 0.6, 0.55)))
		var contract_hint := Contracts.hint_for(c)
		if contract_hint != "":
			var hint_lbl := _label("", 13, Color(0.62, 0.75, 0.85))
			hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_lbl.custom_minimum_size = Vector2(560, 0)
			hint_lbl.visible = false
			var hint_btn := Button.new()
			hint_btn.text = Loc.t("btn.show_commands")
			var hint_id := String(c.get("id", ""))
			if _revealed_hints.has(hint_id):
				hint_lbl.text = contract_hint
				hint_lbl.visible = true
				hint_btn.visible = false
			hint_btn.pressed.connect(func() -> void:
				Challenge.note_hint()
				_revealed_hints[hint_id] = true
				hint_lbl.text = contract_hint
				hint_lbl.visible = true
				hint_btn.visible = false)
			cv.add_child(hint_btn)
			cv.add_child(hint_lbl)
		var btn := Button.new()
		var all_met := true
		var first_unmet := ""
		for r in c["reqs"]:
			if not r["t"].call():
				all_met = false
				if first_unmet == "":
					first_unmet = Loc.t(String(r["d"]))
		btn.text = Loc.t("btn.collect") % int(c["reward"]) if all_met else Loc.t("btn.check_requirements")
		_accent(btn)
		btn.pressed.connect(func() -> void:
			if not Game.try_complete_contract(c):
				var why := ""
				for r in c["reqs"]:
					if not r["t"].call():
						why = Loc.t(String(r["d"]))
						break
				hud_toast(Loc.t("toast.not_yet") % why if why != "" else "Not yet.", false)
			_refresh_contracts()
			check_demo_end())
		cv.add_child(btn)
	if not found_active:
		contracts_box.add_child(_wrap(Loc.t("demo.finished")
			if Demo.active() else Loc.t("body.campaign_done"),
			14, Color(0.7, 0.85, 0.75), 640))

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

func _ensure_visible(ctrl: Control) -> void:
	## scroll whichever card holds this control until it is in view
	var node: Node = ctrl.get_parent()
	while node != null and not (node is ScrollContainer):
		node = node.get_parent()
	if node != null:
		(node as ScrollContainer).call_deferred("ensure_control_visible", ctrl)

var cli_rows_step := 0  # the taller/shorter toggle: 0 default, 1 tall, 2 very tall

func _console_height() -> float:
	## terminal length N sets rows; the toggle steps through sizes; the card's
	## remaining room is the ceiling in every case
	var room := get_viewport().get_visible_rect().size.y - card_top() - 300.0
	var want: float = [220.0, 380.0, 560.0][cli_rows_step]
	if cli_session != null and int(cli_session.term_length) > 0:
		want = float(cli_session.term_length) * 18.0
	return clampf(minf(want, room), 120.0, 900.0)

func _toggle_cli() -> void:
	cli_box.visible = not cli_box.visible
	if cli_box.visible:
		cli_out.custom_minimum_size.y = _console_height()
		_ensure_visible(cli_box)  # the console opens below the fold otherwise
		cli_toggle.text = Loc.t("dev.console.close") + "  ▤"
		var kept: Dictionary = cli_sessions.get(cur_dev, {})
		var kept_base: CLI.Session = (kept["stack"][0] if not kept.get("stack", []).is_empty() else kept.get("session")) if not kept.is_empty() else null
		var resumed: bool = kept_base != null and is_instance_valid(kept_base.dev) and kept_base.dev == cur_dev  # an ssh hop kept open comes back too
		if resumed:
			cli_session = kept["session"]
			cli_stack = kept["stack"]
		else:
			cli_session = CLI.new_session(cur_dev)
			cli_stack = []
			cli_sessions[cur_dev] = {"session": cli_session, "stack": cli_stack}
		cli_history = cli_session.history
		cli_hist_idx = cli_history.size()
		cli_prompt.text = cli_session.prompt() + " "
		cli_out.clear()
		if resumed:
			cli_out.append_text("(session resumed: %s)\n" % cli_session.prompt())
		else:
			cli_out.append_text(cli_session.banner())
		var cli_away := Game.elsewhere(cur_dev)
		if cli_away != "":
			# you are typing at a machine in another building
			cli_out.append_text("\n[!] this console is on %s, not the floor you are standing on\n"
				% cli_away)
		if cur_dev != null and Game.locked_out(cur_dev):
			# it is running your new configuration and nothing can reach it
			cli_out.append_text("\n%% no route to %s: console server, a walk to the rack, or a site visit\n"
				% cur_dev.name)
		cli_in.call_deferred("grab_focus")
		_scroll_to_bottom.call_deferred()
		_ensure_visible.call_deferred(cli_in)  # the input line, not the box: the box is taller than the fold
	else:
		cli_out.custom_minimum_size.y = 0
		cli_toggle.text = Loc.t("dev.console.open") + "  ▤"
		cli_out.clear()
		cli_session = null  # the session object stays in cli_sessions until logout or exit
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
	if e is InputEventKey and e.pressed and e.keycode == KEY_Z and e.ctrl_pressed and cli_session != null:
		cli_in.accept_event()
		_cli_submit("end")  # Ctrl-Z: back to privileged exec, the way a real console does it
		return
	if e is InputEventKey and e.pressed and e.ctrl_pressed and e.keycode in [KEY_A, KEY_E, KEY_U, KEY_K, KEY_W, KEY_L, KEY_C]:
		# the readline keys every operator's fingers know
		cli_in.accept_event()
		var col := cli_in.caret_column
		match e.keycode:
			KEY_A:
				cli_in.caret_column = 0
			KEY_E:
				cli_in.caret_column = cli_in.text.length()
			KEY_U:
				cli_in.text = cli_in.text.substr(col)
				cli_in.caret_column = 0
			KEY_K:
				cli_in.text = cli_in.text.substr(0, col)
				cli_in.caret_column = cli_in.text.length()
			KEY_W:
				var head := cli_in.text.substr(0, col).rstrip(" ")
				var cut := head.rfind(" ")
				cli_in.text = (head.substr(0, cut + 1) if cut >= 0 else "") + cli_in.text.substr(col)
				cli_in.caret_column = cut + 1 if cut >= 0 else 0
			KEY_L:
				cli_out.clear()
			KEY_C:
				cli_out.append_text("%s %s^C\n" % [cli_session.prompt() if cli_session else "", cli_in.text])
				cli_in.text = ""
				cli_in.caret_column = 0
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_DOWN:
		cli_in.accept_event()
		cli_hist_idx = mini(cli_history.size(), cli_hist_idx + 1)
		cli_in.text = "" if cli_hist_idx == cli_history.size() else cli_history[cli_hist_idx]
		cli_in.caret_column = cli_in.text.length()
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_V and (e.ctrl_pressed or e.meta_pressed):
		# a pasted block runs line by line, the way copying a config between boxes works
		var clip := DisplayServer.clipboard_get()
		if clip.contains("\n"):
			cli_in.accept_event()
			for pasted_line in clip.split("\n"):
				var pl := String(pasted_line).strip_edges()
				if pl != "":
					_cli_submit(pl)
			return
	if e is InputEventKey and e.pressed and e.unicode == 63 and cli_session is LinuxCLI:
		return  # bash has no ? help: the character is typed, like any other
	if e is InputEventKey and e.pressed and e.unicode == 63:  # '?'
		cli_in.accept_event()
		if cli_session.has_method("describe"):
			cli_out.append_text("%s %s?\n%s" % [cli_session.prompt(), cli_in.text, cli_session.describe(cli_in.text)])
			return
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
	if cmd.strip_edges() == "!!" and not cli_history.is_empty():
		cmd = String(cli_history[-1])  # bash: the previous command again
	if cmd.strip_edges() != "":
		cli_history.append(cmd)
		cli_hist_idx = cli_history.size()
	if cmd.strip_edges() == "clear":
		cli_out.clear()
		return
	cli_out.append_text("%s %s\n" % [cli_session.prompt(), cmd])
	Sim.last_trace = []
	var cli_result: String = cli_session.exec(cmd)
	cli_out.append_text(cli_result)
	_last_cli_line = cmd
	if Prefs.learner_hints:
		var hint := CLI.learner_hint(CLI.dialect_of(cli_session), cmd, cli_result)
		if hint != "":
			cli_out.append_text("[color=#8da7ba]%s[/color]" % hint)
	if cli_learn_btn != null:
		var topic := CLI.topic_for(cmd)
		cli_learn_btn.visible = topic != ""  # the field manual is reference, not coaching: it stays with hints off
		cli_learn_btn.text = "LEARN: %s ↗" % topic if topic != "" else "LEARN ↗"
	if cli_session.pending_ssh:
		var target: Net.NDevice = cli_session.pending_ssh
		cli_session.pending_ssh = null
		cli_stack.append(cli_session)
		cli_session = CLI.new_session(target)
		cli_history = cli_session.history  # the far box has its own history
		cli_hist_idx = 0
		cli_out.append_text(cli_session.banner())
	elif cli_session.pending_sub != null:
		var sub: CLI.Session = cli_session.pending_sub  # vtysh: a shell inside the shell, same box
		cli_session.pending_sub = null
		cli_stack.append(cli_session)
		cli_session = sub
		cli_history = cli_session.history
		cli_hist_idx = 0
		cli_out.append_text(cli_session.banner())
	elif cli_session.wants_exit:
		cli_session.wants_exit = false
		if cli_stack.is_empty():
			cli_out.append_text("logout\n")
			cli_sessions.erase(cur_dev)  # a real logout: the next open starts fresh
			cli_session = CLI.new_session(cur_dev)
			cli_sessions[cur_dev] = {"session": cli_session, "stack": cli_stack}
			cli_history = cli_session.history
			cli_hist_idx = 0
			cli_out.append_text(cli_session.banner())
		else:
			var left: CLI.Session = cli_session
			cli_session = cli_stack.pop_back()
			cli_history = cli_session.history
			cli_hist_idx = cli_history.size()
			if left.dev != cli_session.dev:
				cli_out.append_text("Connection closed. Back on %s.\n" % cli_session.dev.name)
	cli_prompt.text = cli_session.prompt() + " "  # mode/hostname may have changed
	if cli_box.visible and int(cli_session.term_length) > 0:
		cli_out.custom_minimum_size.y = _console_height()  # terminal length just changed the pane
	_refresh_capture()
	if not Sim.last_trace.is_empty():
		get_parent().play_trace(Sim.last_trace)

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return  # the title screen is up; the game is not listening
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if service_overlay != null and is_instance_valid(service_overlay) and service_overlay.visible:
			service_overlay.visible = false
		elif if_overlay.visible:
			close_iface()
		elif dev_overlay.visible:
			if cli_box.visible:
				_toggle_cli()
			else:
				close_dev()
				if cur_rack:
					open_rack(cur_rack)  # reached through Find or the map: the elevation is rebuilt for this rack
		elif search_overlay.visible:
			search_overlay.visible = false
		elif ops_overlay.visible:
			ops_overlay.visible = false
		elif help_overlay.visible:
			help_overlay.visible = false
		elif pedia_overlay.visible:
			pedia_overlay.visible = false
		elif settings_overlay != null and is_instance_valid(settings_overlay) and settings_overlay.visible:
			settings_overlay.visible = false
		elif demo_overlay.visible:
			demo_overlay.visible = false
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
		elif get_parent().mode != get_parent().Mode.SELECT:
			get_parent().mode = get_parent().Mode.SELECT  # ESC leaves build mode before it opens anything
			Sfx.play("back")
		else:
			toggle_menu()
		get_viewport().set_input_as_handled()
