extends SceneTree
## Writes assets/voice/README.md: every story line with the file name its
## recording needs. Run after changing lines in scripts/story/story_data.gd:
##   godot --headless --path . -s tools/list_voice_lines.gd

func _initialize() -> void:
	var data = load("res://scripts/story/story_data.gd")
	var text := "# Voice-over files\n\n"
	text += "Save each recording in this folder under the file name below (mp3; ogg and wav also work).\n"
	text += "A line with no file is simply shown without sound, so recordings can be added a few at a time.\n"
	text += "After adding files, open the project in Godot once so they are imported.\n\n"
	text += "This list is generated from scripts/story/story_data.gd by tools/list_voice_lines.gd.\n\n"
	text += "| File | Speaker | Line |\n|---|---|---|\n"
	for line: Dictionary in data.voice_lines():
		text += "| `%s.mp3` | %s | %s |\n" % [line["id"], line["speaker"], str(line["text"]).replace("|", "/").replace("\n", " ")]
	var file := FileAccess.open("res://assets/voice/README.md", FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("wrote assets/voice/README.md (%d lines)" % data.voice_lines().size())
	quit()
