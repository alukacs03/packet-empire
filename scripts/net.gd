class_name Net
## Plain data model. No behavior beyond structure; the packet sim comes later.

class NDevice:
	var type: String  # "switch" | "server"
	var name: String
	var nports: int
	func _init(t: String, n: String, p: int) -> void:
		type = t
		name = n
		nports = p

class Link:
	var a: NDevice
	var ai: int
	var b: NDevice
	var bi: int
	func _init(pa: NDevice, pai: int, pb: NDevice, pbi: int) -> void:
		a = pa
		ai = pai
		b = pb
		bi = pbi

class Rack:
	const SLOTS := 8
	var name: String
	var tile: Vector2i
	var slots: Array = []  # NDevice or null per U-slot
	var visual: Node2D
	func _init(n: String, t: Vector2i) -> void:
		name = n
		tile = t
		slots.resize(SLOTS)
