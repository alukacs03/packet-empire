class_name Sfx
extends Node
## Interface sound, generated rather than shipped. Every cue is a short
## enveloped tone built into an AudioStreamWAV at startup, so the game stays
## a single repository of code with no binary assets to keep in step.
##
## Keep the palette small and quiet: a click you stop noticing, a rising pair
## for something that worked, a flat low pair for something that did not.

const RATE := 22050
const VOL_DB := -14.0

static var _bank := {}
static var _players: Array = []
static var _node: Node = null
static var muted := false

static func install(parent: Node) -> void:
	## call once; safe to call again
	if _node != null and is_instance_valid(_node):
		return
	_node = Node.new()
	_node.name = "Sfx"
	parent.add_child(_node)
	for i in 6:  # a small pool: cues overlap, they do not queue
		var p := AudioStreamPlayer.new()
		p.volume_db = VOL_DB
		p.bus = "Master"
		_node.add_child(p)
		_players.append(p)
	_bank = {
		"click": _tone([[880.0, 0.035]], 0.6),
		"open": _tone([[520.0, 0.05], [780.0, 0.06]], 0.5),
		"back": _tone([[700.0, 0.05], [470.0, 0.06]], 0.45),
		"good": _tone([[660.0, 0.07], [880.0, 0.07], [1320.0, 0.11]], 0.55),
		"bad": _tone([[240.0, 0.09], [180.0, 0.13]], 0.6),
		"cable": _tone([[320.0, 0.03], [640.0, 0.04]], 0.7),
		"place": _tone([[150.0, 0.055], [82.0, 0.11]], 0.62),
		"alert": _tone([[990.0, 0.08], [740.0, 0.08], [990.0, 0.1]], 0.5),
		"money": _tone([[1180.0, 0.05], [1560.0, 0.05], [1980.0, 0.09]], 0.4),
	}

static func play(cue: String) -> void:
	if muted or _node == null or not is_instance_valid(_node) or not _bank.has(cue):
		return
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			p.stream = _bank[cue]
			p.play()
			return
	# every voice busy: drop the cue rather than cutting one off mid-note

static func _tone(segments: Array, gain: float) -> AudioStreamWAV:
	## segments: [[hz, seconds], ...] played back to back, each one enveloped
	## so nothing clicks at the joins
	var data := PackedByteArray()
	for seg: Array in segments:
		var hz: float = seg[0]
		var frames := int(RATE * float(seg[1]))
		for i in frames:
			var t := float(i) / RATE
			var progress := float(i) / float(maxi(frames - 1, 1))
			# quick attack, long-ish decay: reads as a soft blip, not a beep
			var env: float = minf(progress / 0.08, 1.0) * pow(1.0 - progress, 1.6)
			# a touch of the octave above keeps it from sounding like a test tone
			var v: float = sin(TAU * hz * t) * 0.8 + sin(TAU * hz * 2.0 * t) * 0.2
			var sample := int(clampf(v * env * gain, -1.0, 1.0) * 32767.0)
			data.append(sample & 0xFF)
			data.append((sample >> 8) & 0xFF)
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	return st
