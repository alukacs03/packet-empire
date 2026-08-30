extends Node
## Autoload "Prefs": display and accessibility options, kept outside the save
## so they follow the player rather than the game.

const PATH := "user://settings.json"

signal changed

var ui_scale := 1.0
var fullscreen := false
var colourblind := false
var sound := true
var reduced_motion := false
var show_everything := false
var language := "en"  # ui language; saves stay language-neutral

func _ready() -> void:
	load_prefs()
	apply()

func load_prefs() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data == null:
		return
	ui_scale = float(data.get("ui_scale", 1.0))
	fullscreen = bool(data.get("fullscreen", false))
	colourblind = bool(data.get("colourblind", false))
	sound = bool(data.get("sound", true))
	reduced_motion = bool(data.get("reduced_motion", false))
	show_everything = bool(data.get("show_everything", false))
	language = String(data.get("language", "en"))

func save_prefs() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"ui_scale": ui_scale, "fullscreen": fullscreen,
			"colourblind": colourblind, "sound": sound, "reduced_motion": reduced_motion,
			"show_everything": show_everything, "language": language}))

func apply() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)
	Sfx.muted = not sound
	Loc.language = language
	save_prefs()
	changed.emit()

## status colours, swapped for a palette that survives red/green blindness
func ok_colour() -> Color:
	return Color(0.35, 0.7, 1.0) if colourblind else Color(0.5, 0.95, 0.6)

func bad_colour() -> Color:
	return Color(1.0, 0.65, 0.0) if colourblind else Color(0.95, 0.5, 0.4)
