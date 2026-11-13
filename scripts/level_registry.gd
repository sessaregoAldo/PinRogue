class_name LevelRegistry
## The list of table layouts ("machine configurations"). Index 0 is the
## machine every run starts on. To add a level: make a scene that inherits
## scenes/levels/level_base.tscn and add its path here.
##
## A machine can be locked until a story chapter is beaten (LOCKS). Locked
## machines are listed in the menus with how to unlock them, but can't be
## picked and never come up at random. Story mode itself ignores the lock: a
## chapter always plays on its own machine.

const PATHS: Array[String] = [
	"res://scenes/levels/level_classic.tscn",
	"res://scenes/levels/level_crossfire.tscn",
	"res://scenes/levels/level_fortress.tscn",
	"res://scenes/levels/level_pinwheel.tscn",
	"res://scenes/levels/level_gauntlet.tscn",
	"res://scenes/levels/level_twin_lifts.tscn",
]

## Machine path -> what unlocks it: {chapter (story chapter id), text (shown in the menus)}.
const LOCKS := {
	"res://scenes/levels/level_twin_lifts.tscn": {
		"chapter": "splitter",
		"text": "Locked. Beat The Splitter in Story Mode to unlock this machine.",
	},
}


static func count() -> int:
	return PATHS.size()


static func path(index: int) -> String:
	return PATHS[posmod(index, PATHS.size())]


## Index of a machine by its scene path (-1 if it isn't listed).
static func index_of(scene_path: String) -> int:
	return PATHS.find(scene_path)


static func instantiate(index: int) -> Level:
	return (load(path(index)) as PackedScene).instantiate() as Level


## False while the machine's story chapter hasn't been beaten.
static func is_unlocked(index: int) -> bool:
	var lock: Dictionary = LOCKS.get(path(index), {})
	if lock.is_empty():
		return true
	var tree := Engine.get_main_loop() as SceneTree
	var story := tree.root.get_node_or_null("Story") if tree else null
	return story != null and story.is_beaten(str(lock["chapter"]))


## How to unlock a locked machine ("" if it has no lock).
static func lock_text(index: int) -> String:
	return str((LOCKS.get(path(index), {}) as Dictionary).get("text", ""))


static func unlocked() -> Array[int]:
	var out: Array[int] = []
	for i in PATHS.size():
		if is_unlocked(i):
			out.append(i)
	return out


## A random unlocked machine.
static func random_unlocked() -> int:
	var pool := unlocked()
	return pool[randi() % pool.size()] if not pool.is_empty() else 0


## A random unlocked level other than `current` (or `current` if there is no other).
static func random_other(current: int) -> int:
	var pool := unlocked()
	pool.erase(current)
	return pool[randi() % pool.size()] if not pool.is_empty() else current
