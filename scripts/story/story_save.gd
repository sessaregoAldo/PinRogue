extends Node
## Story mode progress (autoload "Story"), saved on this device in
## user://story.cfg (IndexedDB in browsers): coins, beaten chapters, unlocked
## spare parts, the coin tray and what the Journal has revealed.

signal changed

const COIN_TRAY_MAX := 60

## Tests point this at another file so real progress is never touched.
var save_path: String = "user://story.cfg"

var coins: int = 0
## Every coin ever earned (never goes down).
var coins_earned: int = 0
var intro_seen: bool = false
## Chapter ids, in the order they were first beaten.
var beaten: Array[String] = []
## Spare parts bought in the Workshop (the starting ones are always unlocked).
var unlocked: Array[String] = []
## Strange coins collected: [{year, text}], newest last.
var coin_tray: Array = []
## Best run per chapter id: {score, damage}.
var best: Dictionary = {}
var attempts: int = 0
## Main menu: open the Story page when it loads (set when a story run ends).
var return_to_hub: bool = false


func _ready() -> void:
	load_save()


func load_save() -> void:
	coins = 0
	coins_earned = 0
	intro_seen = false
	beaten = []
	unlocked = []
	coin_tray = []
	best = {}
	attempts = 0
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	coins = int(cfg.get_value("story", "coins", 0))
	coins_earned = int(cfg.get_value("story", "coins_earned", coins))
	intro_seen = bool(cfg.get_value("story", "intro_seen", false))
	for id in cfg.get_value("story", "beaten", []):
		beaten.append(str(id))
	for id in cfg.get_value("story", "unlocked", []):
		unlocked.append(str(id))
	var tray: Variant = cfg.get_value("story", "coin_tray", [])
	coin_tray = tray if tray is Array else []
	var best_value: Variant = cfg.get_value("story", "best", {})
	best = best_value if best_value is Dictionary else {}
	attempts = int(cfg.get_value("story", "attempts", 0))
	# Development coin reset (StoryData.COIN_RESET): coins back to 0, once.
	if int(cfg.get_value("story", "coin_reset", 0)) != StoryData.COIN_RESET:
		coins = 0
		save()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("story", "coins", coins)
	cfg.set_value("story", "coins_earned", coins_earned)
	cfg.set_value("story", "intro_seen", intro_seen)
	cfg.set_value("story", "beaten", beaten)
	cfg.set_value("story", "unlocked", unlocked)
	cfg.set_value("story", "coin_tray", coin_tray)
	cfg.set_value("story", "best", best)
	cfg.set_value("story", "attempts", attempts)
	cfg.set_value("story", "coin_reset", StoryData.COIN_RESET)
	cfg.save(save_path)
	changed.emit()


# --- Chapters -----------------------------------------------------------------------

func is_beaten(chapter_id: String) -> bool:
	return beaten.has(chapter_id)


## Index of the first chapter not beaten yet, or -1 when all are.
func next_chapter() -> int:
	for i in StoryData.CHAPTERS.size():
		if not is_beaten(StoryData.CHAPTERS[i]["id"]):
			return i
	return -1


## Returns true if this was the first time.
func beat_chapter(chapter_id: String) -> bool:
	if beaten.has(chapter_id):
		return false
	beaten.append(chapter_id)
	return true


func record_run(chapter_id: String, score: float, damage: float) -> void:
	attempts += 1
	var old: Dictionary = best.get(chapter_id, {})
	best[chapter_id] = {
		"score": maxf(score, float(old.get("score", 0.0))),
		"damage": maxf(damage, float(old.get("damage", 0.0))),
	}


# --- Coins and parts ----------------------------------------------------------------

## Adds coins and one strange coin for the tray. Returns that coin {year, text}.
func add_coins(amount: int) -> Dictionary:
	coins += amount
	coins_earned += amount
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var coin := StoryData.strange_coin(rng)
	coin_tray.append(coin)
	while coin_tray.size() > COIN_TRAY_MAX:
		coin_tray.pop_front()
	return coin


func is_unlocked(part_id: String) -> bool:
	return StoryData.STARTING_PARTS.has(part_id) or unlocked.has(part_id)


func price(part_id: String) -> int:
	return int(StoryData.PART_PRICES.get(part_id, -1))


## Buys a part. Returns false if it can't be afforded or isn't for sale.
func buy(part_id: String) -> bool:
	var cost := price(part_id)
	if cost < 0 or is_unlocked(part_id) or coins < cost:
		return false
	coins -= cost
	unlocked.append(part_id)
	save()
	return true
