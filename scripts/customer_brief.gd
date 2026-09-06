class_name CustomerBrief

static func margin_text(headroom: int, peak: int) -> String:
	var margin := headroom - peak
	if margin < 0: return Loc.t("brief.forecast_short") % -margin
	if margin == 0: return Loc.t("brief.forecast_exact")
	return Loc.t("brief.forecast_spare") % margin

static func wave_reason(reason: String) -> String:
	var keys := {"Orders moving": "brief.reason_served", "Checkout unavailable": "brief.reason_unreachable",
		"Shared link congested": "brief.reason_congested", "Nobody was watching": "brief.reason_unobserved"}
	return Loc.t(keys[reason]) if keys.has(reason) else reason

static func paragraph(box: VBoxContainer, text: String, semantic := "text") -> void:
	var label := UIW.make_text(text, "small", semantic)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 290
	label.custom_minimum_size.y = UIW.sans_font().get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, 290, UIW.type_size("small")).y + 4
	box.add_child(label)

static func render(ui) -> void:
	ui.tutorial_panel.visible = true
	for child in ui.tutorial_box.get_children():
		ui.tutorial_box.remove_child(child)
		child.queue_free()
	var box: VBoxContainer = ui.tutorial_box
	var arc := FirstCustomer.state()
	var phase := String(arc.get("phase", "planning"))
	box.add_child(ui._tutorial_head(Loc.t("brief.title")))
	var deal := Game.guided_customer_deal()
	var f := FirstCustomer.forecast()
	if phase in ["planning", "countdown"]:
		if phase == "planning": paragraph(box, Loc.t("brief.invitation"))
		var available := UIW.make_text(Loc.t("brief.available") % int(f["headroom"]), "heading", "accent")
		available.tooltip_text = Loc.t("brief.forecast_note") + "\n" + String(f["bottleneck"])
		box.add_child(available)
	if phase == "planning":
		for key: String in FirstCustomer.PLANS:
			var plan: Dictionary = FirstCustomer.PLANS[key]
			var b := WorkspaceShell.button("%s · %d Mbps" % [Loc.t(String(plan["name"])), plan["demand"][1]], func() -> void:
				var err := FirstCustomer.choose(key)
				if err != "": ui.hud_toast(err)
				ui._refresh_tutorial(), key == "stagger")
			b.tooltip_text = Loc.t(String(plan["detail"]))
			box.add_child(b)
			paragraph(box, Loc.t("brief.plan_terms") % [plan["fee"], plan["bonus"]] + "\n" +
				margin_text(int(f["headroom"]), int(plan["demand"].max())),
				"warning" if int(f["headroom"]) <= int(plan["demand"].max()) else "muted")
	elif phase in ["countdown", "live"]:
		var plan: Dictionary = FirstCustomer.PLANS[String(arc["plan"])]
		var left := int(arc["starts"]) - Game.cycle
		paragraph(box, Loc.t("brief.starts_in") % left if left > 0 else Loc.t("brief.live_wave") % mini(3, Game.cycle - int(arc["starts"]) + 1), "warm")
		box.add_child(DemandChart.new().setup(plan["demand"], int(f["headroom"]), Game.cycle - int(arc["starts"]), arc.get("samples", [])))
		paragraph(box, margin_text(int(f["headroom"]), int(plan["demand"].max())),
			"warning" if int(f["headroom"]) <= int(plan["demand"].max()) else "muted")
		paragraph(box, Loc.t("brief.limiting_path") % String(f["bottleneck"]), "muted")
		var unreachable := deal.is_empty() or not bool(deal.get("healthy", false))
		paragraph(box, Loc.t("brief.restore_action" if unreachable else "brief.capacity_action"), "warning" if unreachable else "muted")
	elif phase == "debrief":
		var successes := int(arc["successes"])
		box.add_child(UIW.make_text(Loc.t("brief.carried") % successes, "heading", "accent" if successes == 3 else "warning"))
		paragraph(box, Loc.t("brief.all_night") if successes == 3 else Loc.t("brief.got_through"))
		for sample: Dictionary in arc["samples"]:
			paragraph(box, Loc.t("brief.cycle_reason") % [sample["cycle"], wave_reason(String(sample["reason"]))], "success" if sample["served"] else "warning")
		paragraph(box, Loc.t("brief.chose_bonus") % [Loc.t(String(FirstCustomer.PLANS[String(arc["plan"])]["name"])), arc["bonus"]])
		var before: Dictionary = arc.get("before", {})
		var after: Dictionary = arc.get("after", {})
		if int(after.get("headroom", 0)) > int(before.get("headroom", 0)):
			paragraph(box, Loc.t("brief.headroom_added") % (int(after["headroom"]) - int(before.get("headroom", 0))), "accent")
		box.add_child(WorkspaceShell.button(Loc.t("brief.keep_building"), func() -> void:
			FirstCustomer.acknowledge()
			ui._refresh_tutorial()
			ui.check_demo_end(), true))
	box.add_child(WorkspaceShell.button(Loc.t("brief.trace_network"), func() -> void: ui.focus_customer(deal)))
	box.add_child(WorkspaceShell.button(Loc.t("brief.continue_jobs"), func() -> void:
		ui.close_everything()
		ui.contracts_tab = "Jobs"
		ui.open_contracts()))

class DemandChart extends Control:
	var demand: Array = []
	var capacity := 0
	var current := -1
	var samples: Array = []
	func setup(values: Array, cap: int, step: int, observed: Array = []) -> DemandChart:
		demand = values
		capacity = cap
		current = step
		samples = observed.duplicate(true)
		custom_minimum_size = Vector2(290, 152)
		return self
	func wave_status(index: int) -> Dictionary:
		if index < samples.size():
			var served := bool(samples[index].get("served", false))
			return {"semantic": "success" if served else "warning",
				"label": Loc.t("brief.wave_ok" if served else "brief.wave_failed"), "observed": true}
		return {"semantic": "accent" if int(demand[index]) <= capacity else "warning",
			"label": Loc.t("brief.wave_forecast"), "observed": false}
	func _draw() -> void:
		var maximum := maxf(1100, capacity * 1.1)
		for i in demand.size():
			var height := float(demand[i]) / maximum * 80
			var x := 16 + i * (size.x - 24) / 3.0
			var status := wave_status(i)
			var col := UIW.colour(status["semantic"])
			draw_rect(Rect2(x, 100 - height, 52, height), Color(col, 0.9 if status["observed"] or i == current else 0.5))
			draw_string(UIW.mono_font(), Vector2(x, 118), str(demand[i]), HORIZONTAL_ALIGNMENT_LEFT, 60, 12, UIW.colour("text"))
			draw_string(UIW.sans_font(), Vector2(x - 4, 140), "%d · %s" % [i + 1, status["label"]], HORIZONTAL_ALIGNMENT_LEFT, (size.x - 24) / 3.0, 11, col)
		var y := 100 - capacity / maximum * 80
		draw_dashed_line(Vector2(8, y), Vector2(size.x - 8, y), UIW.colour("warm"), 1.0, 4)
		draw_string(UIW.sans_font(), Vector2(8, 14), Loc.t("brief.chart_legend"), HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 11, UIW.colour("muted"))
