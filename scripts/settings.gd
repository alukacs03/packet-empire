extends Node
## Autoload "Prefs": display and accessibility options, kept outside the save
## so they follow the player rather than the game.

static var PATH := "user://settings_test.json" if OS.get_environment("PACKET_TEST") == "1" else "user://settings.json"  # tests keep their hands off the player's settings

signal changed

var ui_scale := 1.0
var fullscreen := false
var colourblind := false
var sound := true
var reduced_motion := false
var show_everything := false
var learner_hints := true  # a comment line under a console error, and the LEARN chip
var volume := 80  # 0-100, the master bus
var music_volume := 60  # 0-100, the ambient hum and the score, under the master
var language := "en"  # ui language; saves stay language-neutral

func _ready() -> void:
	load_prefs()
	apply()

func load_prefs() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	ui_scale = clampf(float(data.get("ui_scale", 1.0)), 0.75, 2.0)
	if ui_scale == 0.0 or is_nan(ui_scale):
		ui_scale = 1.0
	fullscreen = bool(data.get("fullscreen", false))
	colourblind = bool(data.get("colourblind", false))
	sound = bool(data.get("sound", true))
	reduced_motion = bool(data.get("reduced_motion", false))
	show_everything = bool(data.get("show_everything", false))
	learner_hints = bool(data.get("learner_hints", true))
	volume = clampi(int(data.get("volume", 80)), 0, 100)
	music_volume = clampi(int(data.get("music_volume", 60)), 0, 100)
	language = String(data.get("language", "en"))
	if language not in Loc.languages():
		language = "en"

func save_prefs() -> void:
	Game.write_text_atomic(PATH, JSON.stringify({"ui_scale": ui_scale, "fullscreen": fullscreen,
		"colourblind": colourblind, "sound": sound, "reduced_motion": reduced_motion,
		"show_everything": show_everything, "learner_hints": learner_hints, "language": language,
		"volume": volume, "music_volume": music_volume}))

func apply() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)
	Sfx.muted = not sound
	Sfx.apply_volumes(volume, music_volume)
	Loc.language = language
	save_prefs()
	changed.emit()

## status colours, swapped for a palette that survives red/green blindness
func ok_colour() -> Color:
	return Color(0.35, 0.7, 1.0) if colourblind else Color(0.5, 0.95, 0.6)

func bad_colour() -> Color:
	return Color(1.0, 0.65, 0.0) if colourblind else Color(0.95, 0.5, 0.4)
