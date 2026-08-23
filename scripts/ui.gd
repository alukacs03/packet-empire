class_name UILayer
extends CanvasLayer
## All 2D UI: toolbar, rack view, device view (ports + cabling), CLI.

var mode_btns := {}
var rack_panel: PanelContainer
var rack_title: Label
var slot_box: VBoxContainer
var dev_panel: PanelContainer
var dev_title: Label
var port_box: VBoxContainer
var cli_panel: PanelContainer
var cli_out: RichTextLabel
var cli_in: LineEdit
var cli_prompt: Label

var cur_rack: Net.Rack
var cur_dev: Net.NDevice
var cli_dev: Net.NDevice

func _ready() -> void:
	_build_toolbar()
	rack_panel = _panel(Vector2(20, 70), Vector2(260, 0))
	var rv := VBoxContainer.new()
	rack_panel.add_child(rv)
	rack_title = Label.new()
	rv.add_child(rack_title)
	slot_box = VBoxContainer.new()
	rv.add_child(slot_box)
	rv.add_child(_close_btn(close_rack))

	dev_panel = _panel(Vector2(300, 70), Vector2(300, 0))
	var dv := VBoxContainer.new()
	dev_panel.add_child(dv)
	dev_title = Label.new()
	dv.add_child(dev_title)
	port_box = VBoxContainer.new()
	dv.add_child(port_box)
	var cli_btn := Button.new()
	cli_btn.text = "Open CLI"
	cli_btn.pressed.connect(func() -> void: open_cli(cur_dev))
	dv.add_child(cli_btn)
	dv.add_child(_close_btn(close_dev))

	_build_cli()
	Game.topology_changed.connect(_refresh_open)

func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.position = Vector2(20, 16)
	add_child(bar)
	var h := HBoxContainer.new()
	bar.add_child(h)
	for m in [["Select (Q)", 0], ["Place rack (R)", 1]]:
		var b := Button.new()
		b.text = m[0]
		b.toggle_mode = true
		b.pressed.connect(func() -> void: get_parent().mode = m[1])
		h.add_child(b)
		mode_btns[m[1]] = b
	update_mode(0)

func update_mode(m: int) -> void:
	for k in mode_btns:
		mode_btns[k].button_pressed = k == m

func _panel(pos: Vector2, min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.custom_minimum_size = min_size
	p.visible = false
	add_child(p)
	return p

func _close_btn(cb: Callable) -> Button:
	var b := Button.new()
	b.text = "Close (Esc)"
	b.pressed.connect(cb)
	return b

# ---------- rack view ----------

func open_rack(r: Net.Rack) -> void:
	cur_rack = r
	close_dev()
	rack_title.text = "Rack %s  (top = slot %d)" % [r.name, Net.Rack.SLOTS]
	_refresh_slots()
	rack_panel.visible = true

func close_rack() -> void:
	close_dev()
	rack_panel.visible = false
	cur_rack = null

func _refresh_slots() -> void:
	for c in slot_box.get_children():
		c.queue_free()
	for i in range(Net.Rack.SLOTS - 1, -1, -1):  # top slot first, like a real rack
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var dev: Net.NDevice = cur_rack.slots[i]
		if dev:
			b.text = "U%d   %s  [%s]" % [i + 1, dev.name, dev.type]
			b.pressed.connect(func() -> void: open_dev(dev))
		else:
			b.text = "U%d   — empty —" % [i + 1]
			b.pressed.connect(func() -> void: _pick_new_device(i, b))
		slot_box.add_child(b)

func _pick_new_device(slot: int, at: Control) -> void:
	_menu(at, ["Install switch (8 ports)", "Install server (1 NIC)"], func(id: int) -> void:
		cur_rack.slots[slot] = Game.new_device("switch" if id == 0 else "server")
		cur_rack.visual.queue_redraw()
		_refresh_slots())

# ---------- device view ----------

func open_dev(d: Net.NDevice) -> void:
	cur_dev = d
	dev_title.text = "%s — %s in rack %s" % [d.name, d.type, Game.rack_of(d).name]
	_refresh_ports()
	dev_panel.visible = true

func close_dev() -> void:
	dev_panel.visible = false
	cur_dev = null

func _refresh_ports() -> void:
	for c in port_box.get_children():
		c.queue_free()
	for i in cur_dev.nports:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var peer := Game.peer_label(cur_dev, i)
		if peer == "":
			b.text = "Port %d   ·  free" % [i + 1]
			b.pressed.connect(_pick_cable_target.bind(i, b))
		else:
			b.text = "Port %d   ●  %s" % [i + 1, peer]
			b.modulate = Color(0.6, 1.0, 0.7)
			b.pressed.connect(func() -> void:
				_menu(b, ["Disconnect cable"], func(_id: int) -> void:
					Game.disconnect_port(cur_dev, i)))
		port_box.add_child(b)

func _pick_cable_target(i: int, at: Control) -> void:
	var targets := Game.free_ports(cur_dev)
	if targets.is_empty():
		_menu(at, ["(no free ports anywhere else)"], func(_id: int) -> void: pass)
		return
	var labels: Array = []
	for t in targets:
		labels.append("%s  %s port %d" % [Game.rack_of(t[0]).name, t[0].name, t[1] + 1])
	_menu(at, labels, func(id: int) -> void:
		Game.connect_ports(cur_dev, i, targets[id][0], targets[id][1]))

func _refresh_open() -> void:
	if dev_panel.visible:
		_refresh_ports()
	if rack_panel.visible:
		_refresh_slots()

func _menu(at: Control, items: Array, on_pick: Callable) -> void:
	var m := PopupMenu.new()
	for it in items:
		m.add_item(it)
	add_child(m)
	m.id_pressed.connect(on_pick)
	m.popup_hide.connect(m.queue_free)
	m.popup(Rect2i(Vector2i(at.get_screen_position() + Vector2(at.size.x, 0)), Vector2i.ZERO))

# ---------- CLI ----------

func _build_cli() -> void:
	cli_panel = _panel(Vector2(20, 0), Vector2(640, 260))
	cli_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cli_panel.position = Vector2(20, -280)
	var v := VBoxContainer.new()
	cli_panel.add_child(v)
	cli_out = RichTextLabel.new()
	cli_out.custom_minimum_size = Vector2(620, 190)
	cli_out.scroll_following = true
	cli_out.add_theme_font_override("normal_font", ThemeDB.fallback_font)
	v.add_child(cli_out)
	var h := HBoxContainer.new()
	v.add_child(h)
	cli_prompt = Label.new()
	h.add_child(cli_prompt)
	cli_in = LineEdit.new()
	cli_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cli_in.text_submitted.connect(_cli_submit)
	h.add_child(cli_in)
	v.add_child(_close_btn(close_cli))

func open_cli(d: Net.NDevice) -> void:
	cli_dev = d
	cli_prompt.text = d.name + ">"
	cli_out.text = "%s serial console — type 'help'\n" % d.name
	cli_panel.visible = true
	cli_in.grab_focus()

func close_cli() -> void:
	cli_panel.visible = false
	cli_dev = null

func _cli_submit(cmd: String) -> void:
	cli_in.clear()
	cli_out.append_text("%s> %s\n" % [cli_dev.name, cmd])
	var out := ""
	match cmd.strip_edges():
		"":
			pass
		"help":
			out = "Commands: help, show ports, show version\n"
		"show version":
			out = "%s — PacketOS 0.1 (%s, %d ports)\n" % [cli_dev.name, cli_dev.type, cli_dev.nports]
		"show ports":
			for i in cli_dev.nports:
				var peer := Game.peer_label(cli_dev, i)
				out += "port %-2d  %-4s  %s\n" % [i + 1, "up" if peer else "down", peer if peer else "-"]
		_:
			out = "%% Unknown command. Full networking CLI arrives with the packet sim.\n"
	cli_out.append_text(out)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if cli_panel.visible:
			close_cli()
		elif dev_panel.visible:
			close_dev()
		elif rack_panel.visible:
			close_rack()
		else:
			return
		get_viewport().set_input_as_handled()
