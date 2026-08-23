class_name UIW
## Custom-drawn hardware widgets: rack U-slots that look like rack units,
## and a device faceplate that looks like real front-panel gear.

const TYPE_COLORS := {
	"switch": Color(0.2, 0.7, 0.75),
	"router": Color(0.85, 0.6, 0.3),
	"firewall": Color(0.85, 0.35, 0.35),
	"uplink": Color(0.7, 0.5, 0.9),
	"cooling": Color(0.5, 0.8, 0.95),
	"server": Color(0.45, 0.55, 0.8),
}

static func mono_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Menlo", "Consolas", "monospace"])
	return f

# ================================================================ RackSlot ==

class RackSlot extends Control:
	var u_num := 0
	var dev: Net.NDevice
	var on_click: Callable
	var hovered := false
	var _mono: SystemFont

	func setup(u: int, d: Net.NDevice, cb: Callable) -> RackSlot:
		u_num = u
		dev = d
		on_click = cb
		custom_minimum_size = Vector2(520, 46)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_mono = UIW.mono_font()
		if d:
			tooltip_text = "%s — open device" % d.name
		else:
			tooltip_text = "Empty slot — install hardware"
		return self

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			hovered = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			hovered = false
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_click.call()

	func _process(_dt: float) -> void:
		if dev:
			queue_redraw()  # LEDs blink

	func _draw() -> void:
		var w := size.x
		var h := size.y
		const RAIL := 30.0
		# rails with screw holes
		for rx in [0.0, w - RAIL]:
			draw_rect(Rect2(rx, 0, RAIL, h), Color(0.16, 0.17, 0.21))
			draw_rect(Rect2(rx, 0, RAIL, h), Color(0.3, 0.33, 0.4), false, 1.0)
			for hy in [h * 0.25, h * 0.75]:
				draw_circle(Vector2(rx + RAIL / 2.0, hy), 3.2, Color(0.05, 0.05, 0.07))
				draw_circle(Vector2(rx + RAIL / 2.0, hy), 3.2, Color(0.4, 0.44, 0.52), false, 1.0)
		draw_string(_mono, Vector2(4, h / 2.0 + 4), "U%d" % u_num,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.55, 0.65))
		var inner := Rect2(RAIL + 2, 3, w - RAIL * 2 - 4, h - 6)
		if dev == null:
			# empty recess
			draw_rect(inner, Color(0.055, 0.06, 0.085))
			draw_rect(inner, Color(0.2, 0.22, 0.28), false, 1.0)
			if hovered:
				draw_string(_mono, inner.position + Vector2(inner.size.x / 2.0 - 60, inner.size.y / 2.0 + 4),
					"+ install hardware", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.75, 0.85))
			return
		# device faceplate
		var col: Color = UIW.TYPE_COLORS.get(dev.type, Color(0.5, 0.5, 0.6))
		if dev.status != "active":
			col = Color(0.4, 0.33, 0.33)
		var face := col.darkened(0.62)
		if hovered:
			face = col.darkened(0.5)
		draw_rect(inner, face)
		draw_rect(inner, col.darkened(0.1) if hovered else col.darkened(0.3), false, 1.5)
		draw_rect(Rect2(inner.position, Vector2(4, inner.size.y)), col)  # vendor stripe
		draw_string(_mono, inner.position + Vector2(14, 18), dev.name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.95, 1.0))
		draw_string(_mono, inner.position + Vector2(14, 33), Game.MODELS[dev.model]["label"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col.lightened(0.25))
		# mini port squares, lit when linked
		var n := 0
		for i: Net.Iface in dev.ifaces:
			if i.name == "lo":
				continue
			var px := inner.position.x + inner.size.x - 26 - n * 13
			if px < inner.position.x + 190:
				break
			var linked := Game.link_at(i) != null
			var pc := Color(0.35, 0.95, 0.5) if linked else Color(0.2, 0.22, 0.28)
			if not i.enabled:
				pc = Color(0.7, 0.3, 0.25)
			draw_rect(Rect2(px, inner.position.y + inner.size.y / 2.0 - 4, 9, 8), pc)
			n += 1
		# status LED
		var t := Time.get_ticks_msec() / 1000.0
		var led := Color(0.9, 0.3, 0.2)
		if dev.status == "active":
			led = Color(0.4, 1.0, 0.5) if fmod(t * 1.7, 1.0) > 0.3 else Color(0.15, 0.4, 0.2)
		draw_circle(inner.position + Vector2(inner.size.x - 12, 10), 2.6, led)

# =============================================================== Faceplate ==

class Faceplate extends Control:
	const JACK_W := 30.0
	const JACK_H := 26.0
	const GAP := 9.0
	const BRAND_W := 150.0

	var dev: Net.NDevice
	var on_port: Callable  # (Net.Iface)
	var hover_idx := -1
	var _mono: SystemFont
	var _ports: Array = []  # visible ifaces

	func setup(d: Net.NDevice, cb: Callable) -> Faceplate:
		dev = d
		on_port = cb
		_mono = UIW.mono_font()
		_ports = []
		for i: Net.Iface in d.ifaces:
			if i.name != "lo":
				_ports.append(i)
		var cols := ceili(_ports.size() / 2.0) if _ports.size() > 6 else _ports.size()
		cols = maxi(cols, 1)
		var rows := 2 if _ports.size() > 6 else 1
		custom_minimum_size = Vector2(BRAND_W + cols * (JACK_W + GAP) + 30,
			maxf(64.0, rows * (JACK_H + 22) + 22))
		mouse_filter = Control.MOUSE_FILTER_STOP
		return self

	func _jack_rect(idx: int) -> Rect2:
		var rows := 2 if _ports.size() > 6 else 1
		var col := idx / rows
		var row := idx % rows
		var y0 := (size.y - (rows * (JACK_H + 22) - 22)) / 2.0 + 6
		return Rect2(BRAND_W + col * (JACK_W + GAP) + (6 if (col / 2) % 2 == 1 else 0),
			y0 + row * (JACK_H + 22), JACK_W, JACK_H)

	func _idx_at(pos: Vector2) -> int:
		for idx in _ports.size():
			if _jack_rect(idx).grow(3).has_point(pos):
				return idx
		return -1

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			var idx := _idx_at(e.position)
			if idx != hover_idx:
				hover_idx = idx
				if idx >= 0:
					var i: Net.Iface = _ports[idx]
					var peer := Game.peer_label(i)
					tooltip_text = "%s — %s" % [i.name,
						("connected to " + peer) if peer else ("free port" if i.enabled else "disabled")]
				else:
					tooltip_text = ""
				queue_redraw()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var idx := _idx_at(e.position)
			if idx >= 0:
				on_port.call(_ports[idx])

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hover_idx = -1
			queue_redraw()

	func _process(_dt: float) -> void:
		queue_redraw()  # link LEDs blink

	func _draw() -> void:
		var col: Color = UIW.TYPE_COLORS.get(dev.type, Color(0.5, 0.5, 0.6))
		# brushed panel
		var panel := Rect2(Vector2.ZERO, size)
		draw_rect(panel, Color(0.13, 0.14, 0.17))
		for k in int(size.y / 3):
			draw_line(Vector2(1, k * 3), Vector2(size.x - 1, k * 3), Color(1, 1, 1, 0.012))
		draw_rect(panel, Color(0.42, 0.46, 0.55), false, 1.5)
		draw_rect(Rect2(0, 0, size.x, 3), col.darkened(0.1))  # vendor accent strip
		# corner screws
		for sx in [10.0, size.x - 10.0]:
			for sy in [10.0, size.y - 10.0]:
				draw_circle(Vector2(sx, sy), 3.5, Color(0.07, 0.07, 0.1))
				draw_circle(Vector2(sx, sy), 3.5, Color(0.45, 0.5, 0.6), false, 1.0)
				draw_line(Vector2(sx - 2, sy), Vector2(sx + 2, sy), Color(0.45, 0.5, 0.6), 1.0)
		# silk-screen branding
		draw_string(_mono, Vector2(24, size.y / 2.0 - 4), Game.MODELS[dev.model]["label"].split(" ")[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.2))
		draw_string(_mono, Vector2(24, size.y / 2.0 + 13),
			" ".join(PackedStringArray(Array(Game.MODELS[dev.model]["label"].split(" ")).slice(1))),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.6, 0.7))
		# port jacks
		var t := Time.get_ticks_msec() / 1000.0
		for idx in _ports.size():
			var i: Net.Iface = _ports[idx]
			var r := _jack_rect(idx)
			var linked := Game.link_at(i) != null
			var body := Color(0.05, 0.06, 0.08)
			var border := Color(0.4, 0.44, 0.52)
			if not i.enabled:
				border = Color(0.85, 0.4, 0.35)
			elif linked:
				border = Color(0.35, 0.9, 0.5)
			if idx == hover_idx:
				body = Color(0.1, 0.14, 0.18)
				border = Color(0.6, 0.9, 1.0)
			draw_rect(r, body)
			draw_rect(r, border, false, 1.5)
			# RJ45 tab notch
			draw_rect(Rect2(r.position.x + r.size.x * 0.3, r.end.y - 5, r.size.x * 0.4, 4), body.lightened(0.15))
			draw_rect(Rect2(r.position.x + 4, r.position.y + 3, r.size.x - 8, 3), Color(0.75, 0.62, 0.3, 0.5))  # pins
			# link LED blinks
			var led := Color(0.2, 0.22, 0.26)
			if not i.enabled:
				led = Color(0.9, 0.35, 0.25)
			elif linked and fmod(t * (2.0 + idx * 0.37), 1.0) > 0.3:
				led = Color(0.4, 1.0, 0.5)
			draw_circle(r.position + Vector2(r.size.x + 0.0, -4), 2.2, led)
			# port label
			var num := i.name.replace("Management", "M").trim_prefix("Ethernet").trim_prefix("ether").trim_prefix("eth").trim_prefix("port")
			var below := (idx % 2 == 1) if _ports.size() > 6 else true
			var ty := r.end.y + 13 if below else r.position.y - 6
			draw_string(_mono, Vector2(r.position.x + r.size.x / 2.0 - 6, ty), num if num != "" else i.name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.7, 0.8))
