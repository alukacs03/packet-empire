class_name UIW
## Custom-drawn hardware widgets: rack U-slots that look like rack units,
## and a device faceplate that looks like real front-panel gear.

const TYPE_COLORS := {
	"switch": Color(0.2, 0.7, 0.75),
	"router": Color(0.85, 0.6, 0.3),
	"firewall": Color(0.85, 0.35, 0.35),
	"uplink": Color(0.7, 0.5, 0.9),
	"cooling": Color(0.5, 0.8, 0.95),
	"loadbalancer": Color(0.55, 0.85, 0.55),
	"server": Color(0.45, 0.55, 0.8),
}

static var _mono_shared: SystemFont

static func mono_font() -> SystemFont:
	if _mono_shared == null:
		_mono_shared = SystemFont.new()
		_mono_shared.font_names = PackedStringArray(["Menlo", "Consolas", "monospace"])
	return _mono_shared

# ================================================================== Graph ==

class Graph extends Control:
	## a small line chart over Game.history
	var key := "money"
	var colour := Color(0.5, 0.9, 0.6)
	var title := ""
	var _mono: SystemFont

	func setup(k: String, t: String, c: Color) -> Graph:
		key = k
		title = t
		colour = c
		_mono = UIW.mono_font()
		custom_minimum_size = Vector2(560, 90)
		return self

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.11))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.3, 0.38), false, 1.0)
		var pts: Array = []
		for h in Game.history:
			pts.append(float(h.get(key, 0)))
		if pts.size() < 2:
			draw_string(_mono, Vector2(10, size.y / 2.0),
				"%s: not enough history yet" % title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(0.5, 0.55, 0.65))
			return
		var lo: float = pts[0]
		var hi: float = pts[0]
		for v in pts:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		if is_equal_approx(lo, hi):
			hi = lo + 1.0
		var line := PackedVector2Array()
		for i in pts.size():
			var x := 8.0 + (size.x - 16.0) * float(i) / float(maxi(pts.size() - 1, 1))
			var y: float = size.y - 20.0 - (size.y - 34.0) * (float(pts[i]) - lo) / (hi - lo)
			line.append(Vector2(x, y))
		if lo < 0.0 and hi > 0.0:  # zero line, when the series crosses it
			var zy := size.y - 20.0 - (size.y - 34.0) * (0.0 - lo) / (hi - lo)
			draw_line(Vector2(8, zy), Vector2(size.x - 8, zy), Color(0.4, 0.44, 0.55, 0.6), 1.0)
		draw_polyline(line, colour, 2.0)
		draw_circle(line[line.size() - 1], 3.0, colour)
		draw_string(_mono, Vector2(10, 14), "%s   now %d   (min %d, max %d)" % [title,
			int(float(pts[pts.size() - 1])), int(lo), int(hi)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colour.lightened(0.2))

# ================================================================ TopoMap ==

class TopoMap extends Control:
	var on_dev: Callable  # (Net.NDevice)
	var _mono: SystemFont
	var _nodes := {}  # Net.NDevice -> Rect2

	func setup(cb: Callable) -> TopoMap:
		on_dev = cb
		_mono = UIW.mono_font()
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_preset(Control.PRESET_FULL_RECT)
		return self

	func _process(_dt: float) -> void:
		if visible:
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			for dev in _nodes:
				if _nodes[dev].has_point(e.position):
					on_dev.call(dev)
					return

	func _dev_info(dev: Net.NDevice) -> String:
		var bits: Array = []
		for i: Net.Iface in dev.ifaces:
			for cidr: String in i.ips:
				bits.append(cidr)
				if bits.size() >= 2:
					return ", ".join(PackedStringArray(bits))
		if dev.type == "switch":
			var vids := dev.vlans.keys()
			vids.sort()
			return "vlans " + ",".join(PackedStringArray(vids.map(func(v): return str(v))))
		return ", ".join(PackedStringArray(bits))

	func _draw() -> void:
		_nodes.clear()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.08, 0.97))
		var title_c := Color(0.5, 0.85, 0.95)
		draw_string(_mono, Vector2(30, 100), "LOGICAL TOPOLOGY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, title_c)
		draw_string(_mono, Vector2(30, 122), "click a device to open it · M or Esc to close",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.55, 0.65))
		# pack rack boxes into a grid that fills the window, floor order preserved
		const COL_W := 250.0
		const TOP := 145.0
		var cols: int = maxi(1, int((size.x - 60.0) / COL_W))
		var racks := Game.racks.duplicate()
		racks.sort_custom(func(x, y): return x.tile.x + x.tile.y * 100 < y.tile.x + y.tile.y * 100)
		var row_h := 0.0
		var col_i := 0
		var row_y := TOP
		for r in racks:
			var filled: Array = []
			for d in r.slots:
				if d:
					filled.append(d)
			var box_h := 34 + filled.size() * 40 + 8
			if col_i >= cols:
				col_i = 0
				row_y += row_h + 24
				row_h = 0.0
			var origin := Vector2(30 + col_i * COL_W, row_y)
			col_i += 1
			row_h = maxf(row_h, box_h)
			var box := Rect2(origin, Vector2(215, box_h))
			draw_rect(box, Color(0.09, 0.1, 0.14))
			draw_rect(box, Color(0.3, 0.34, 0.44), false, 1.0)
			var site_tag: String = "" if Game.site_count() <= 1 else "  ·  " + Game.site_name(r.site)
			draw_string(_mono, origin + Vector2(10, 22), "▤ " + r.name + site_tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.8, 0.9))
			var y := origin.y + 34
			for d in filled:
				_nodes[d] = Rect2(origin.x + 8, y, 199, 36)
				y += 40
		# links under nodes
		for l in Game.links:
			if not _nodes.has(l.a.dev) or not _nodes.has(l.b.dev):
				continue
			var pa: Vector2 = _nodes[l.a.dev].get_center()
			var pb: Vector2 = _nodes[l.b.dev].get_center()
			var col := Color(0.35, 0.7, 0.65, 0.8)
			var blocked := false
			if l.a.dev.type == "switch" and l.b.dev.type == "switch":
				col = Color(1.0, 0.62, 0.2, 0.85)
				blocked = Sim.stp_blocked(l.a) or Sim.stp_blocked(l.b)
			if l.a.name.begins_with("Management") or l.b.name.begins_with("Management"):
				col = Color(0.75, 0.55, 0.95, 0.85)
			var ls := Game.sites_of(l.a, l.b)
			if ls[0] != ls[1]:
				col = Color(0.4, 0.9, 1.0, 0.9)  # rides a WAN circuit
			var over: bool = Game.last_link_load.get(l, 0) > Game.link_capacity(l)
			if over:
				draw_line(pa, pb, Color(0.95, 0.3, 0.25, 0.9), 5.0)
				draw_string(_mono, (pa + pb) / 2.0 + Vector2(4, -4),
					"%d/%d Mbps" % [Game.last_link_load.get(l, 0), Game.link_capacity(l)],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.5, 0.45))
			elif blocked:
				var n := 14
				for k in n:
					if k % 2 == 0:
						draw_line(pa.lerp(pb, float(k) / n), pa.lerp(pb, float(k + 1) / n),
							Color(0.9, 0.4, 0.35, 0.9), 2.0)
			else:
				draw_line(pa, pb, col, 2.0)
		# nodes on top
		for dev: Net.NDevice in _nodes:
			var rect: Rect2 = _nodes[dev]
			var col: Color = UIW.TYPE_COLORS.get(dev.type, Color(0.5, 0.5, 0.6))
			draw_rect(rect, col.darkened(0.65))
			draw_rect(rect, col if dev.status == "active" else Color(0.6, 0.3, 0.3), false, 1.5)
			draw_string(_mono, rect.position + Vector2(8, 15), dev.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
			draw_string(_mono, rect.position + Vector2(8, 29), _dev_info(dev), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col.lightened(0.3))
		# legend
		var ly := size.y - 26
		draw_string(_mono, Vector2(30, ly), "- host link  : trunk/inter-switch   ┄ STP blocked  : management",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.55, 0.65))

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
			tooltip_text = "%s: open device" % d.name
			if Game.config_dirty(d):
				tooltip_text += "   (unsaved configuration)"
		else:
			tooltip_text = "Empty slot: install hardware"
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
			if i.name == "lo" or i.name.begins_with("Vlan") or i.parent != "":
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
		if Game.config_dirty(dev):  # unsaved configuration: amber dot by the status LED
			draw_circle(inner.position + Vector2(inner.size.x - 24, 10), 2.6, Color(1.0, 0.72, 0.3))
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
			if i.name != "lo" and not i.name.begins_with("Vlan") and i.parent == "":
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
					tooltip_text = "%s: %s" % [i.name,
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
