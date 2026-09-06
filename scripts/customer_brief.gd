class_name CustomerBrief

static func paragraph(box: VBoxContainer, text: String, semantic := "text") -> void:
	var label := UIW.make_text(text, "body", semantic)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 290
	box.add_child(label)

static func render(ui) -> void:
	ui.tutorial_panel.visible = true
	for child in ui.tutorial_box.get_children():
		ui.tutorial_box.remove_child(child)
		child.queue_free()
	var box: VBoxContainer = ui.tutorial_box
	var arc := FirstCustomer.state()
	var phase := String(arc.get("phase", "planning"))
	box.add_child(ui._tutorial_head("Kiskacsa's big night"))
	box.add_child(UIW.make_chip("CUSTOMER STORY  /  01", "accent"))
	var deal := Game.guided_customer_deal()
	if not deal.is_empty():
		var eye := Game.customer_eye(deal)
		paragraph(box, String(eye["activity"]), "muted")
	var f := FirstCustomer.forecast()
	if phase in ["planning", "countdown"]:
		paragraph(box, Loc.t("brief.packed_stock"))
		box.add_child(UIW.make_text("%d Mbps available" % int(f["headroom"]), "title", "accent"))
		paragraph(box, Loc.t("brief.forecast_note"), "muted")
		paragraph(box, String(f["bottleneck"]), "muted")
	if phase == "planning":
		for key: String in FirstCustomer.PLANS:
			var plan: Dictionary = FirstCustomer.PLANS[key]
			paragraph(box, Loc.t(String(plan["detail"])))
			var b := WorkspaceShell.button("%s · %d Mbps" % [Loc.t(String(plan["name"])), plan["demand"][1]], func() -> void:
				var err := FirstCustomer.choose(key)
				if err != "": ui.hud_toast(err)
				ui._refresh_tutorial(), key == "stagger")
			b.tooltip_text = "$%d reservation. $%d bonus if all three waves run at full service." % [plan["fee"], plan["bonus"]]
			box.add_child(b)
	elif phase in ["countdown", "live"]:
		var plan: Dictionary = FirstCustomer.PLANS[String(arc["plan"])]
		var left := int(arc["starts"]) - Game.cycle
		paragraph(box, Loc.t("brief.starts_in") % left if left > 0 else Loc.t("brief.live_wave") % mini(3, Game.cycle - int(arc["starts"]) + 1), "warm")
		box.add_child(DemandChart.new().setup(plan["demand"], int(f["headroom"]), Game.cycle - int(arc["starts"])))
		paragraph(box, Loc.t("brief.your_plan") % Loc.t(String(plan["name"])))
		paragraph(box, Loc.t("brief.move_traffic"), "muted")
	elif phase == "debrief":
		var successes := int(arc["successes"])
		box.add_child(UIW.make_text("%d / 3 waves carried" % successes, "title", "accent" if successes == 3 else "warning"))
		paragraph(box, Loc.t("brief.all_night") if successes == 3 else Loc.t("brief.got_through"))
		for sample: Dictionary in arc["samples"]:
			paragraph(box, Loc.t("brief.cycle_reason") % [sample["cycle"], sample["reason"]], "success" if sample["served"] else "warning")
		paragraph(box, Loc.t("brief.chose_bonus") % [Loc.t(String(FirstCustomer.PLANS[String(arc["plan"])]["name"])), arc["bonus"]])
		var before: Dictionary = arc.get("before", {})
		if int(f["headroom"]) > int(before.get("headroom", 0)):
			paragraph(box, Loc.t("brief.headroom_added") % (int(f["headroom"]) - int(before.get("headroom", 0))), "accent")
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
	func setup(values: Array, cap: int, step: int) -> DemandChart:
		demand = values
		capacity = cap
		current = step
		custom_minimum_size = Vector2(290, 132)
		return self
	func _draw() -> void:
		var maximum := maxf(1100, capacity * 1.1)
		for i in demand.size():
			var height := float(demand[i]) / maximum * 80
			var x := 16 + i * (size.x - 24) / 3.0
			var col := UIW.colour("accent") if demand[i] <= capacity else UIW.colour("warning")
			draw_rect(Rect2(x, 100 - height, 52, height), Color(col, 0.9 if i == current else 0.5))
			draw_string(UIW.mono_font(), Vector2(x, 118), str(demand[i]), HORIZONTAL_ALIGNMENT_LEFT, 60, 12, UIW.colour("text"))
		var y := 100 - capacity / maximum * 80
		draw_dashed_line(Vector2(8, y), Vector2(size.x - 8, y), UIW.colour("warm"), 1.0, 4)
		draw_string(UIW.sans_font(), Vector2(8, 14), Loc.t("brief.chart_legend"), HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 11, UIW.colour("muted"))
