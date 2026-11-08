class_name LevelRegistry
## The list of table layouts ("machine configurations"). Index 0 is the
## machine every run starts on. To add a level: make a scene that inherits
## scenes/levels/level_base.tscn and add its path here.

const PATHS: Array[String] = [
	"res://scenes/levels/level_classic.tscn",
	"res://scenes/levels/level_crossfire.tscn",
	"res://scenes/levels/level_fortress.tscn",
]


static func count() -> int:
	return PATHS.size()


static func path(index: int) -> String:
	return PATHS[posmod(index, PATHS.size())]


static func instantiate(index: int) -> Level:
	return (load(path(index)) as PackedScene).instantiate() as Level


## A random level other than `current` (or `current` if it is the only one).
static func random_other(current: int) -> int:
	if PATHS.size() <= 1:
		return current
	var pick := randi() % (PATHS.size() - 1)
	return pick if pick < current else pick + 1
