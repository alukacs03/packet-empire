class_name DesignReview
## Deterministic rendered review, using the real workspaces and live state.
## Run only in an isolated user directory; it never opens a player save.

static func capture(world: Node, name: String) -> void:
	for _i in 10: await world.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("PACKET_REVIEW")
	DirAccess.make_dir_recursive_absolute(folder)
	world.get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))

static func run(world) -> void:
	Prefs.reduced_motion = true
	Prefs.show_everything = true
	Prefs.language = "en"
	Loc.language = "en"
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
	world.ui.close_everything()
	for _i in 6: Game.sla_tick()
	world.ui._refresh_tutorial()
	await capture(world, "11-sale-result")
	world.get_tree().quit()
