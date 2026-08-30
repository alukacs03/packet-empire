class_name TitleScreen
extends CanvasLayer
## The front door. Continue, start something new, pick a save, change
## settings, leave. Nothing in here touches the world until the player
## chooses; the world only starts once a signal goes out.

signal start_requested(slot: int, company: String, difficulty: int, demo: bool)
signal continue_requested(slot: int)
signal settings_requested

const ACCENT: Color = UIW.COLORS["accent"]
const MUTED: Color = UIW.COLORS["muted"]

var root: Control
var menu_box: VBoxContainer
var panel_box: VBoxContainer  # the right-hand pane: slots, new game, credits
var pane_title: Label
var _mono: SystemFont

func _ready() -> void:
	layer = 90
	_mono = UIW.mono_font()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIW.make_theme()
	add_child(root)
	root.add_child(TitleBackdrop.new())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 40)
	root.add_child(margin)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	margin.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)

	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer_top)
	left.add_child(_wordmark())
	var eyebrow := _lbl("NETWORK OPERATIONS TYCOON", 12, UIW.colour("warm"))
	eyebrow.add_theme_font_override("font", _mono)
	left.add_child(eyebrow)
	left.add_child(_lbl("Build the network. Win the contract. Survive the traffic.", 18, UIW.colour("text")))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	left.add_child(gap)

	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 12)
	menu_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(menu_box)
	var spacer_bot := Control.new()
	spacer_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer_bot)
	left.add_child(_lbl("Real switches, real routing, real consequences.", 12,
		UIW.colour("muted")))

	var right := UIW.CommandPanel.new().setup("overlay", "warm", 28)
	right.custom_minimum_size = Vector2(390, 520)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 18)
	right.add_child(rv)
	pane_title = _lbl("", 20, ACCENT)
	rv.add_child(pane_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	panel_box = VBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 14)
	panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_box)
	rv.add_child(_lbl("ESC returns to this briefing.", 11, UIW.colour("muted")))

	_build_menu()
	show_intro()

func _wordmark() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var a := _lbl("PACKET ", 58, UIW.colour("text_strong"))
	a.add_theme_font_override("font", UIW.sans_font())
	h.add_child(a)
	var b := _lbl("EMPIRE", 58, UIW.colour("warm"))
	b.add_theme_font_override("font", UIW.sans_font())
	h.add_child(b)
	return h

func _lbl(text: String, size := 15, color := UIW.COLORS["text"]) -> Label:
	var l := UIW.make_text(text)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _sb(bg: Color, border: Color, radius := 6, margin := 8) -> StyleBoxFlat:
	return UIW.custom_box(bg, border, radius, margin)

func _menu_button(text: String, sub: String, primary: bool) -> Button:
	var mark := "%02d" % (menu_box.get_child_count() + 1)
	var b := UIW.ActionButton.new().setup(text, sub, primary, mark)
	b.tooltip_text = sub
	b.pressed.connect(func() -> void: Sfx.play("click"))
	return b

func _build_menu() -> void:
	for c in menu_box.get_children():
		c.queue_free()
	Game.import_legacy_save()
	var recent := _most_recent_slot()
	if recent >= 0:
		var info := Game.slot_info(recent)
		var cont := _menu_button("Continue", "%s, cycle %d" % [info["company"], info["cycle"]], true)
		cont.pressed.connect(func() -> void: continue_requested.emit(recent))
		menu_box.add_child(cont)
	var demo_b := _menu_button("Play the demo", "The opening arc, start to finish", recent < 0)
	demo_b.pressed.connect(func() -> void: show_new_game(true))
	menu_box.add_child(demo_b)
	var new_b := _menu_button("New game", "The full campaign", false)
	new_b.pressed.connect(func() -> void: show_new_game(false))
	menu_box.add_child(new_b)
	var load_b := _menu_button("Load game", "Pick a save slot", false)
	load_b.pressed.connect(show_slots)
	menu_box.add_child(load_b)
	var set_b := _menu_button("Settings", "Scale, speed, colour", false)
	set_b.pressed.connect(show_settings)
	menu_box.add_child(set_b)
	var quit_b := _menu_button("Quit", "", false)
	quit_b.pressed.connect(func() -> void: get_tree().quit())
	menu_box.add_child(quit_b)

func _most_recent_slot() -> int:
	## the slot the player was last in, so Continue means what it says
	var best := -1
	var best_key := ""
	for i in Game.SLOTS + 1:
		var info := Game.slot_info(i)
		if info.get("empty", true):
			continue
		var key := "%s|%04d" % [String(info.get("saved", "")), int(info.get("cycle", 0))]
		if best < 0 or key > best_key:
			best = i
			best_key = key
	return best

static func _money(v: int) -> String:
	## grouped, and a minus sign that reads like money rather than a typo
	var digits := str(absi(v))
	var grouped := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += ","
		grouped += digits[i]
	return ("-$%s" if v < 0 else "$%s") % grouped

func _clear_pane() -> void:
	for c in panel_box.get_children():
		c.queue_free()

func show_intro() -> void:
	_clear_pane()
	pane_title.text = "What this is"
	for para in [
		"You run a small network business. It starts with one rack in somebody else's building and a customer who wants two offices joined up.",
		"Everything under the hood is real: MAC learning, VLANs, spanning tree, routing, DHCP, BGP. The switches take Arista-style commands, the cheap gear takes RouterOS. Nothing is faked, so when a ping fails there is a reason and you can find it.",
		"The demo covers the opening arc, which is about half an hour. It ends at the point where the business game opens up.",
	]:
		panel_box.add_child(_para(para))
	var tips := VBoxContainer.new()
	tips.add_theme_constant_override("separation", 4)
	panel_box.add_child(tips)
	tips.add_child(_lbl("Worth knowing", 14, ACCENT))
	for tip in ["F1 opens help at any time.", "Escape steps back out of anything.",
			"The encyclopedia explains every concept the game uses.",
			"Nothing you do to a device is permanent until you save its configuration."]:
		tips.add_child(_lbl("  " + tip, 13, MUTED))

func _para(text: String) -> Control:
	var l := _lbl(text, 14, Color(0.78, 0.83, 0.9))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	return l

func show_new_game(is_demo: bool) -> void:
	_clear_pane()
	pane_title.text = "Play the demo" if is_demo else "New game"
	panel_box.add_child(_lbl("Company name", 13, MUTED))
	var name_in := LineEdit.new()
	name_in.text = "Packet Empire"
	panel_box.add_child(name_in)

	var diff := 1
	var diff_row := VBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 6)
	panel_box.add_child(diff_row)
	if is_demo:
		panel_box.add_child(_para("The demo runs on the standard difficulty so the pacing matches the walkthrough."))
	else:
		diff_row.add_child(_lbl("Difficulty", 13, MUTED))
		var group := ButtonGroup.new()
		for i in Game.DIFFICULTIES.size():
			var d: Dictionary = Game.DIFFICULTIES[i]
			var b := Button.new()
			b.text = "%s: %s" % [d["name"], d["blurb"]]
			b.toggle_mode = true
			b.button_group = group
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.button_pressed = i == 1
			b.add_theme_font_size_override("font_size", 12)
			b.pressed.connect(func() -> void: diff = i)
			diff_row.add_child(b)

	if not is_demo and not Legacy.epitaph.is_empty():
		panel_box.add_child(_lbl("The last company", 13, MUTED))
		panel_box.add_child(_para("%s ran for %d cycles, earned $%d, and %s. You may take two things with you."
			% [Legacy.epitaph.get("company", "It"), int(Legacy.epitaph.get("cycles", 0)),
				int(Legacy.epitaph.get("earned", 0)), Legacy.epitaph.get("why", "ended")]))
		for entry: Dictionary in Legacy.offered:
			var lb := Button.new()
			lb.toggle_mode = true
			lb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			lb.add_theme_font_size_override("font_size", 12)
			lb.text = String(entry["label"])
			lb.tooltip_text = String(entry["detail"])
			lb.button_pressed = String(entry["id"]) in Legacy.selected
			lb.toggled.connect(func(on: bool) -> void:
				var taken: bool = Legacy.carry_toggle(String(entry["id"]))
				if on and not taken:
					lb.set_pressed_no_signal(false))
			panel_box.add_child(lb)

	var go := Button.new()
	go.text = "Start" if not is_demo else "Start the demo"
	go.custom_minimum_size = Vector2(0, 40)
	UIW.style_button(go, "primary")
	go.pressed.connect(func() -> void:
		var slot := _free_slot()
		start_requested.emit(slot, name_in.text.strip_edges(), 1 if is_demo else diff, is_demo))
	panel_box.add_child(go)
	panel_box.add_child(_para("A new game takes the first free slot. If all three are full it overwrites the oldest, so rename or clear a slot first if you care about it."))

func _free_slot() -> int:
	var oldest := 0
	var oldest_key := "~"
	for i in Game.SLOTS:
		var info := Game.slot_info(i)
		if info.get("empty", true):
			return i
		var key := String(info.get("saved", ""))
		if key < oldest_key:
			oldest_key = key
			oldest = i
	return oldest

func show_settings() -> void:
	_clear_pane()
	pane_title.text = "Settings"
	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Prefs.fullscreen
	fs.toggled.connect(func(on: bool) -> void:
		Prefs.fullscreen = on
		Prefs.apply())
	panel_box.add_child(fs)
	var snd := CheckButton.new()
	snd.text = "Sound"
	snd.button_pressed = Prefs.sound
	snd.toggled.connect(func(on: bool) -> void:
		Prefs.sound = on
		Prefs.apply()
		Sfx.play("click"))
	panel_box.add_child(snd)
	var cb := CheckButton.new()
	cb.text = "Colourblind-friendly status colours"
	cb.button_pressed = Prefs.colourblind
	cb.toggled.connect(func(on: bool) -> void:
		Prefs.colourblind = on
		Prefs.apply())
	panel_box.add_child(cb)
	var motion := CheckButton.new()
	motion.text = "Reduce motion"
	motion.tooltip_text = "Replaces traveling highlights and decorative movement with static confirmations"
	motion.button_pressed = Prefs.reduced_motion
	motion.toggled.connect(func(on: bool) -> void:
		Prefs.reduced_motion = on
		Prefs.apply())
	panel_box.add_child(motion)
	var toolbox := CheckButton.new()
	toolbox.text = "Show the full toolbox from the start"
	toolbox.tooltip_text = "For experienced players: reveal every navigation area without waiting for campaign unlocks"
	toolbox.button_pressed = Prefs.show_everything
	toolbox.toggled.connect(func(on: bool) -> void:
		Prefs.show_everything = on
		Prefs.apply())
	panel_box.add_child(toolbox)
	panel_box.add_child(_lbl("Interface scale", 13, MUTED))
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 6)
	panel_box.add_child(scale_row)
	for step: float in [0.9, 1.0, 1.15, 1.3]:
		var b2 := Button.new()
		b2.text = "%d%%" % int(step * 100)
		b2.toggle_mode = true
		b2.button_pressed = absf(Prefs.ui_scale - step) < 0.01
		b2.pressed.connect(func() -> void:
			Prefs.ui_scale = step
			get_tree().root.content_scale_factor = step
			Prefs.apply()
			show_settings())
		scale_row.add_child(b2)
	panel_box.add_child(_para("You can change these again from the in-game menu."))
	settings_requested.emit()

func show_slots() -> void:
	_clear_pane()
	pane_title.text = "Save slots"
	for i in Game.SLOTS + 1:
		panel_box.add_child(_slot_row(i))
	panel_box.add_child(_para("The autosave is written every few cycles while you play. It is never used for a new game."))

func _slot_row(i: int) -> Control:
	var info := Game.slot_info(i)
	var pc := PanelContainer.new()
	UIW.style_panel(pc, "surface", "md")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	var head := "Autosave" if i >= Game.SLOTS else "Slot %d" % (i + 1)
	if info.get("empty", true):
		v.add_child(_lbl("%s: empty" % head, 14, MUTED))
		return pc
	v.add_child(_lbl("%s: %s" % [head, info["company"]], 15))
	var stage_name: String = Game.STAGES[mini(int(info["stage"]), Game.STAGES.size() - 1)]["name"]
	v.add_child(_lbl("cycle %d   %s   %s%s" % [int(info["cycle"]), stage_name,
		_money(int(info["money"])), "   demo" if info.get("demo", false) else ""],
		12, MUTED))
	if String(info.get("saved", "")) != "":
		v.add_child(_lbl(String(info["saved"]), 11, UIW.colour("subtle")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var load_b := Button.new()
	load_b.text = "Load"
	load_b.pressed.connect(func() -> void: continue_requested.emit(i))
	row.add_child(load_b)
	var del_b := Button.new()
	del_b.text = "Delete"
	del_b.add_theme_color_override("font_color", Color(0.9, 0.5, 0.45))
	del_b.pressed.connect(func() -> void:
		Game.delete_slot(i)
		_build_menu()
		show_slots())
	row.add_child(del_b)
	return pc

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		show_intro()
		get_viewport().set_input_as_handled()
