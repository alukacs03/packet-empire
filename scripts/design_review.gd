class_name DesignReview
## Deterministic rendered review, using the real workspaces and live state.
## Run only in an isolated user directory; it never opens a player save.

static var failures := 0

static func check(ok: bool, description: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + "layout: " + description)
	if not ok: failures += 1

static func click(world: Node, position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		world.get_viewport().push_input(event, true)
		await world.get_tree().process_frame

static func capture(world: Node, name: String) -> void:
	world.ui._fit_cards.call_deferred()
	for _i in 10: await world.get_tree().process_frame
	var ui = world.ui
	var viewport := world.get_viewport().get_visible_rect()
	if ui.visible and ui.tutorial_panel.visible:
		check(viewport.encloses(ui.tutorial_panel.get_global_rect()), name + " brief stays inside viewport")
		if name == "03-customer-plan":
			var scroll: ScrollContainer = ui.tutorial_box.get_parent()
			for child in ui.tutorial_box.get_children():
				if child is Button:
					check(scroll.get_global_rect().encloses(child.get_global_rect()), name + " choice/action visible: " + child.text)
		for scroll in ui._card_scrolls:
			if is_instance_valid(scroll) and scroll.is_visible_in_tree() and not scroll.has_meta("customer_brief"):
				check(not scroll.get_parent().get_global_rect().intersects(ui.tutorial_panel.get_global_rect()), name + " workspace does not overlap brief")
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("PACKET_REVIEW")
	DirAccess.make_dir_recursive_absolute(folder)
	world.get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))

static func run(world) -> void:
	failures = 0
	if OS.get_environment("PACKET_REVIEW_SIZE") == "1280":
		world.get_window().content_scale_size = Vector2i(1280, 720)
	Prefs.reduced_motion = true
	Prefs.show_everything = true
	var language := OS.get_environment("PACKET_REVIEW_LANGUAGE")
	if language.is_empty(): language = "en"
	Prefs.language = language
	Loc.language = language
	Game.set_speed(0)
	world.show_title()
	await capture(world, "01-title")
	world.title.visible = false
	world.ui.visible = true
	Game._apply(Game._pristine.duplicate(true))
	Game.set_speed(0)
	world.rebuild_racks()
	world.ui._dismiss_unlock_intro()
	world.ui._refresh_tutorial()
	await capture(world, "02-first-move")
	var f := DesignTests.fixture()
	Game.set_speed(0)
	world.rebuild_racks()
	Game.feature_intros_seen = Game.DISCOVERY_FEATURES.duplicate()
	world.ui._dismiss_unlock_intro()
	FirstCustomer.tick()
	world.ui._refresh_tutorial()
	await capture(world, "03-customer-plan")
	FirstCustomer.choose("premiere")
	world.ui._refresh_tutorial()
	await capture(world, "04-sale-countdown")
	world.ui.open_rack(f["rack"])
	await capture(world, "05-rack")
	await click(world, world.ui.hud_map_btn.get_global_rect().get_center())
	check(world.ui.map_overlay.visible and not world.ui.rack_overlay.visible, "persistent navigation switches workspace with a real click")
	world.ui.close_everything()
	world.ui.open_rack(f["rack"])
	for _i in 3: await world.get_tree().process_frame
	var racks_before := Game.racks.size()
	world.mode = 1
	await click(world, Vector2(1100, 650))
	check(Game.racks.size() == racks_before, "workspace scrim prevents a click from building a rack on the floor")
	world.mode = 0
	world.ui.open_dev(f["a"])
	world.ui._toggle_cli()
	await capture(world, "06-console")
	world.ui.focus_customer(f["deal"])
	await capture(world, "07-service-network")
	world.ui.close_everything()
	world.ui.contracts_tab = "Business"
	world.ui.open_contracts()
	await capture(world, "08-company")
	world.ui.close_everything()
	world.ui.toggle_ops()
	await capture(world, "09-operations")
	world.ui.close_everything()
	world.ui.open_rack(f["rack"])
	ServiceDesign.capture(f["rack"], "Proven customer LAN")
	world.ui._open_service_standards()
	await capture(world, "10-service-standard")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	world.ui._unhandled_input(escape)
	check(not world.ui.service_overlay.visible and world.ui.rack_overlay.visible, "Escape closes service standards before their parent rack")
	world.ui.close_everything()
	for _i in 4:
		Game.sla_tick()
	var host: Net.NDevice = f["a"]
	host.ifaces[0].enabled = false
	host.ifaces[0].admin_down = true
	Game.sla_tick()
	world.ui._refresh_tutorial()
	await capture(world, "11-live-mixed-results")
	world.ui.focus_customer(f["deal"])
	await capture(world, "12-outage-network")
	world.ui.close_everything()
	host.ifaces[0].enabled = true
	host.ifaces[0].admin_down = false
	Game.sla_tick()

	world.ui._refresh_tutorial()
	await capture(world, "11-sale-result")
	print("---- %d layout failures" % failures)
	world.get_tree().quit(0 if failures == 0 else 1)
