class_name StoryVoice
extends RefCounted
## Voice-over lookup for story lines. Every line has an id (see
## StoryData.voice_lines() and assets/voice/README.md). Drop a recording named
## <id>.mp3 into assets/voice/ and it plays with that line; lines without a file
## are simply silent, so recordings can arrive a few at a time.

const DIR := "res://assets/voice/"
const EXTENSIONS: Array[String] = [".mp3", ".ogg", ".wav"]
const BUS := "Voice"


## The recording for a line id, or null when there isn't one (yet).
static func stream_for(id: String) -> AudioStream:
	if id == "":
		return null
	for ext in EXTENSIONS:
		var path := DIR + id + ext
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


## A player on the Voice bus (its own bus, so the story's "silence" and the
## effects volume don't touch it).
static func make_player() -> AudioStreamPlayer:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, "Master")
	var player := AudioStreamPlayer.new()
	player.bus = BUS
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	return player
