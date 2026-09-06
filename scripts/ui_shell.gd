class_name WorkspaceShell
## Persistent navigation beside a compact status bar.

static func button(title: String, action: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = title
	b.custom_minimum_size.y = 40
	UIW.style_button(b, "primary" if primary else "quiet")
	b.pressed.connect(action)
	return b

static func build(ui) -> void:
	var bar := PanelContainer.new()
	ui.hud_bar = bar
	bar.theme = ui.theme_res
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	UIW.style_panel(bar, "hud", "md")
	bar.resized.connect(ui._refit_hangs)
	ui.add_child(bar)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	bar.add_child(rows)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	rows.add_child(top)
	ui.hud_logo = UIW.make_text("PACKET / EMPIRE", "heading", "accent")
	top.add_child(ui.hud_logo)
	ui.money_lbl = UIW.make_text("", "body_large")
	ui.money_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(ui.money_lbl)
	ui.clock_lbl = UIW.make_text("", "small", "muted")
	ui.clock_lbl.custom_minimum_size.x = 250
	ui.clock_lbl.clip_text = true
	top.add_child(ui.clock_lbl)
	for spec in [["Pause", 0], ["1×", 1], ["2×", 2], ["3×", 3]]:
		var b := button(spec[0], func() -> void: Game.set_speed(spec[1]))
		b.custom_minimum_size = Vector2(40, 32)
		b.toggle_mode = true
		b.tooltip_text = "Space pauses; number keys change speed."
		top.add_child(b)
		ui.speed_btns[spec[1]] = b
	ui.cycle_lbl = UIW.make_text("", "small", "muted")
	ui.cycle_lbl.custom_minimum_size.x = 90
	top.add_child(ui.cycle_lbl)
	top.add_child(button("Save", ui._save_with_feedback))
	ui.hud_status_row = HBoxContainer.new()
	rows.add_child(ui.hud_status_row)
	ui.objective_lbl = UIW.make_text("", "small", "muted")
	ui.objective_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.objective_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ui.objective_lbl.clip_text = true
	ui.objective_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.objective_lbl.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if not Game.hazards.is_empty():
				ui.ops_tab = "Facility"  # a live hazard: one click to where it is dealt with
				if not ui.ops_overlay.visible:
					ui.toggle_ops()
				return
			ui.tutorial_hidden = false
			ui._refresh_tutorial())
	ui.hud_status_row.add_child(ui.objective_lbl)
	ui.hud_alert_btn = button("", func() -> void:
		ui.close_everything()
		ui.contracts_tab = "Log" if Game.customer_down_now() else "Market"
		ui.open_contracts())
	ui.hud_alert_btn.custom_minimum_size.y = 28
	ui.hud_status_row.add_child(ui.hud_alert_btn)
	var rail := PanelContainer.new()
	rail.theme = ui.theme_res
	rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_left = 16
	rail.offset_top = 112
	rail.offset_right = 164
	rail.offset_bottom = -48
	UIW.style_panel(rail, "hud", "sm")
	ui.add_child(rail)
	ui.hud_nav_row = VBoxContainer.new()
	ui.hud_nav_row.add_theme_constant_override("separation", 8)
	rail.add_child(ui.hud_nav_row)
	var nav: VBoxContainer = ui.hud_nav_row
	nav.add_child(UIW.make_text("YOUR DATACENTER", "caption", "subtle"))
	ui.mode_btns[0] = button("Floor", func() -> void:
		ui.close_everything()
		ui.get_parent().mode = 0)
	nav.add_child(ui.mode_btns[0])
	ui.contracts_btn = button("Customers", func() -> void:
		ui.close_everything()
		ui.open_contracts(), true)
	nav.add_child(ui.contracts_btn)
	ui.hud_map_btn = button("Network", func() -> void:
		ui.close_everything()
		ui.toggle_map())
	ui.hud_map_btn.tooltip_text = "Network map (M). Select a customer to trace their service."
	nav.add_child(ui.hud_map_btn)
	ui.hud_ops_btn = button("Operations", func() -> void:
		ui.close_everything()
		ui.toggle_ops())
	nav.add_child(ui.hud_ops_btn)
	var gap := Control.new()
	gap.custom_minimum_size.y = 16
	nav.add_child(gap)
	nav.add_child(UIW.make_text("TOOLS", "caption", "subtle"))
	ui.mode_btns[1] = button("Build a rack", func() -> void:
		ui.close_everything()
		ui.get_parent().mode = 1)
	nav.add_child(ui.mode_btns[1])
	ui.hud_find_btn = button("Find anything", func() -> void:
		ui.close_everything()
		ui.toggle_search())
	nav.add_child(ui.hud_find_btn)
	ui.hud_learn_btn = button("Field manual", func() -> void:
		ui.close_everything()
		ui.open_pedia())
	nav.add_child(ui.hud_learn_btn)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(fill)
	ui.site_btn = button("", func() -> void:
		var names: Array = []
		for i in Game.site_count(): names.append(Game.site_name(i))
		ui._menu(ui.site_btn, names, func(i: int) -> void: Game.switch_site(i)))
	ui.site_btn.clip_text = true
	nav.add_child(ui.site_btn)
	ui.expand_btn = button("Expand", func() -> void:
		if Game.expand(): ui._refresh_money())
	ui.expand_btn.clip_text = true
	nav.add_child(ui.expand_btn)
	for key in ui.mode_btns: ui.mode_btns[key].toggle_mode = true
	ui.update_mode(0)
	ui.hud_shortcut_hint = UIW.make_text("Space  Pause     Q  Select     R  Build     F  Find     O  Ops     M  Network     F1  Keys     Esc  Back", "small", "muted")
	ui.hud_shortcut_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ui.hud_shortcut_hint.position = Vector2(184, -32)
	ui.add_child(ui.hud_shortcut_hint)
