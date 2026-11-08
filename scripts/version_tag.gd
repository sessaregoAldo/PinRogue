extends CanvasLayer
## Small version label in the bottom-left corner of every screen (autoload
## "VersionTag"), so you can tell which build is running, e.g. after a push.
## The version comes from Project Settings (application/config/version);
## the build time is written to res://build_info.cfg by tools/export_web.sh.
## Runs from the editor show "dev".

const BUILD_INFO := "res://build_info.cfg"

var text: String = ""


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var build := "dev"
	if not OS.is_debug_build():
		var cfg := ConfigFile.new()
		if cfg.load(BUILD_INFO) == OK:
			build = "build " + str(cfg.get_value("build", "time", "?"))
	text = "v%s · %s" % [version, build]
	var label := Label.new()
	label.text = text
	label.position = Vector2(6, 1100)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
