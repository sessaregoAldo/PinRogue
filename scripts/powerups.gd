class_name PowerupManager
extends Node2D
## Roguelike power-ups.
##
## When a rollover group is completed (see Rollover.grants_powerup), the game
## pauses and offers 3 random power-ups. The pick lasts for the rest of the run
## and stacks with earlier picks. Everything resets on restart.
##
## Two kinds ("tier"):
## - minor: earned from the inlane lights behind the bottom slingshots.
##   All three cards are minor.
## - major: earned from the machine's lights near the boss. At least two cards
##   are major; if fewer major ones are available, minor ones fill the rest.
##
## To add a power-up: add an entry to POWERUPS, handle its id in _apply(),
## and (optionally) in _is_available() and _status_lines(). The main menu's
## Spare Parts list reads POWERUPS too.

const POWERUPS := [
	# --- Major (lights near the boss) ---
	{"id": "extra_ball", "tier": "major", "title": "Extra Ball", "icon": "+1",
		"desc": "One more ball for this run.", "color": Color(0.4, 1.0, 0.5), "weight": 0.8},
	{"id": "mega_multiplier", "tier": "major", "title": "Mega Multiplier", "icon": "x2",
		"desc": "Put a x2 score multiplier on a bumper or wall kicker, or max out one you placed. 20 s cooldown.",
		"color": Color(0.3, 1.0, 0.95), "weight": 0.9},
	{"id": "boss_crusher", "tier": "major", "title": "Boss Crusher", "icon": "!!",
		"desc": "Boss hits deal +50% damage. Stacks.", "color": Color(1.0, 0.4, 0.5), "weight": 1.0},
	{"id": "boss_magnet", "tier": "major", "title": "Boss Magnet", "icon": "(o)",
		"desc": "The boss gently pulls nearby balls toward it for more boss hits. Stacks up to 3 times.",
		"color": Color(1.0, 0.45, 0.45), "weight": 0.9},
	{"id": "turbo_ramps", "tier": "major", "title": "Turbo Ramps", "icon": ">>",
		"desc": "Ramp boosters fire from the entrance, so any ramp you get into completes. Ramps score +100% per stack.",
		"color": Color(1.0, 0.7, 0.35), "weight": 0.9},
	{"id": "multiball_lock", "tier": "major", "title": "Multiball Lock", "icon": "oo",
		"desc": "Your next boss hit launches an extra ball. Drained balls return for 20 s. Holds 2.",
		"color": Color(1.0, 0.55, 0.85), "weight": 0.9},
	{"id": "upper_flipper", "tier": "major", "title": "Upper Flipper", "icon": "/",
		"desc": "An extra flipper on the side wall, worked by the same button. Left first, then right.",
		# Disabled for now: on most machines it knocks the ball into the nearest ramp entrance.
		"color": Color(0.5, 0.75, 1.0), "weight": 0.8, "disabled": true},
	# --- Minor (inlane lights) ---
	{"id": "multiplier", "tier": "minor", "title": "Score Multiplier", "icon": "x1.25",
		"desc": "Place on a bumper or wall kicker: hitting it multiplies your score by 1.25. Pick again to upgrade a part to x1.5. 20 s cooldown.",
		"color": Color(0.45, 1.0, 0.9), "weight": 1.2},
	{"id": "bouncy_ball", "tier": "minor", "title": "Bouncy Ball", "icon": "o^",
		"desc": "The ball bounces 0.1x harder off everything. Stacks up to x1.5.",
		"color": Color(0.55, 0.85, 1.0), "weight": 1.0},
	{"id": "gap_guard", "tier": "minor", "title": "Gap Guard", "icon": "==",
		"desc": "A barrier below the flipper gap pops the ball back up. Breaks after 2 saves.",
		"color": Color(0.4, 0.8, 1.0), "weight": 1.0},
	{"id": "outlane_guards", "tier": "minor", "title": "Outlane Guards", "icon": "| |",
		"desc": "Barriers across both outlanes. Each one saves the ball once.",
		"color": Color(0.6, 0.7, 1.0), "weight": 1.0},
	{"id": "ball_saver", "tier": "minor", "title": "Ball Saver", "icon": "<3",
		"desc": "For 10 s after each launch, a drained ball comes back. Each stack adds 10 s.",
		"color": Color(0.5, 1.0, 0.6), "weight": 0.9},
	{"id": "steady_hands", "tier": "minor", "title": "Steady Hands", "icon": "~",
		"desc": "One more nudge allowed before TILT.", "color": Color(1.0, 0.85, 0.4), "weight": 0.7},
	{"id": "combo_master", "tier": "minor", "title": "Combo Master", "icon": "+%",
		"desc": "Button combinations add +5% more of your score (10% -> 15%). Stacks.",
		"color": Color(0.75, 0.55, 1.0), "weight": 0.8},
	{"id": "kickback", "tier": "minor", "title": "Kickback", "icon": "^",
		"desc": "Kicks an outlane ball back into play. Recharges after 10 boss or 20 bumper hits.",
		"color": Color(0.45, 1.0, 0.6), "weight": 1.0},
]
## The three parts the tutorial's pick always shows.
const TUTORIAL_OFFER: Array[String] = ["turbo_ramps", "multiplier", "boss_crusher"]
## Kickback zones (bottom of each outlane) and the order the sides are added.
const KICKBACK_POS := {"L": Vector2(40, 945), "R": Vector2(520, 945)}
const KICKBACK_ORDER: Array[String] = ["L", "R"]
## Upper Flipper: order the sides are added (positions come from the level).
const UPPER_ORDER: Array[String] = ["L", "R"]
const UPPER_LENGTH := 56.0
const UPPER_REST_DEG := 30.0
const UPPER_ACTIVE_DEG := -25.0

const TIER_COLORS := {"major": Color(1.0, 0.75, 0.25), "minor": Color(0.55, 0.8, 1.0)}
## Bouncy Ball: +0.1x per stack, up to this.
const BOUNCE_MAX := 1.5
## Score multiplier tiers. Minor picks place x1.25 and upgrade to x1.5;
## Mega Multiplier jumps a part straight to x2.

const MULT_TIERS: Array[float] = [1.25, 1.5, 2.0]

@export_group("Multiplier")
@export var multiplier_cooldown: float = 20.0
@export_group("Gap Guard")
@export var gap_guard_a: Vector2 = Vector2(262, 1030)
@export var gap_guard_b: Vector2 = Vector2(298, 1030)
@export var gap_guard_saves: int = 2
@export var gap_guard_max: int = 4
@export_group("Outlane Guards")
@export var left_outlane_a: Vector2 = Vector2(26, 806)
@export var left_outlane_b: Vector2 = Vector2(55, 806)
@export var right_outlane_a: Vector2 = Vector2(505, 806)
@export var right_outlane_b: Vector2 = Vector2(534, 806)
@export var outlane_guard_saves: int = 1
@export var outlane_guard_max: int = 3

var _multipliers: Dictionary = {} # part (Node2D) -> {"mult": float, "ready_at": float}
var _kickbacks: Dictionary = {} # "L"/"R" -> Kickback
var _upper_flippers: Dictionary = {} # "L"/"R" -> Flipper
var _clock: float = 0.0 # game time; doesn't advance while paused
var _pulse: float = 0.0
var _pending_choices: Array[String] = [] # tiers of the picks waiting to be offered
var _offer_tier: String = "major"
var _place_mega: bool = false
var _choice_title: Label
var _gap_guard: Guard
var _left_guard: Guard
var _right_guard: Guard
var _steady_stacks: int = 0
var _crusher_stacks: int = 0

# Picker / placement state
var _offer: Array = []
var _placing: bool = false
var _place_targets: Array[Node2D] = []
var _place_index: int = 0

# UI
var _ui: CanvasLayer
var _choice_root: Control
var _cards_box: HBoxContainer
var _banner: Label
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # the picker runs while the game is paused
	z_as_relative = false
	z_index = 45 # multiplier rings draw above tunnels
	_build_ui()
	GameManager.powerup_choice_requested.connect(_on_choice_requested)
	GameManager.part_hit.connect(_on_part_hit)
	GameManager.game_started.connect(_reset_run)
	GameManager.level_changed.connect(_on_level_changed)
	# A lane set completed while the boss menu was open is offered after Continue.
	GameManager.round_continued.connect(func(_r: int) -> void:
		if not _pending_choices.is_empty() and not GameManager.choosing:
			_open_choice.call_deferred())
	_update_status()


func _process(delta: float) -> void:
	if not get_tree().paused:
		_clock += delta
	_pulse += delta
	if _placing or not _multipliers.is_empty():
		queue_redraw()


# --- Run lifecycle ------------------------------------------------------------

func _reset_run() -> void:
	_multipliers.clear()
	for node in _kickbacks.values() + _upper_flippers.values():
		if is_instance_valid(node):
			node.queue_free()
	_kickbacks.clear()
	_upper_flippers.clear()
	for guard in [_gap_guard, _left_guard, _right_guard]:
		if is_instance_valid(guard):
			guard.queue_free()
	_gap_guard = null
	_left_guard = null
	_right_guard = null
	_steady_stacks = 0
	_crusher_stacks = 0
	_pending_choices.clear()
	_placing = false
	_apply_bounce()
	_choice_root.visible = false
	_banner.visible = false
	if get_tree().paused and not _pause_menu_open():
		get_tree().paused = false
	_update_status()
	queue_redraw()


func _pause_menu_open() -> bool:
	var menu := get_parent().get_node_or_null("PauseMenu") as CanvasLayer
	return menu != null and menu.visible


# --- Picking ------------------------------------------------------------------

func _on_choice_requested(tier: String = "major") -> void:
	if GameManager.is_game_over:
		return
	_pending_choices.append(tier)
	if not GameManager.choosing:
		call_deferred("_open_choice") # not from inside a physics callback


func _open_choice() -> void:
	if _pending_choices.is_empty() or GameManager.is_game_over:
		return
	_offer_tier = _pending_choices.pop_front()
	_offer = _roll_offer(3, _offer_tier)
	if _offer.is_empty():
		return
	GameManager.choosing = true
	get_tree().paused = true
	_fill_cards()
	_choice_root.visible = true
	Sfx.play("powerup")


## Minor picks: all minor. Major picks: major cards first, minor ones only fill
## in when there aren't enough majors available.
func _roll_offer(count: int, tier: String) -> Array:
	# The tutorial always offers the same three, so the lesson plays the same way.
	if GameManager.game_mode == "tutorial":
		var fixed := []
		for id in TUTORIAL_OFFER:
			for p: Dictionary in POWERUPS:
				if p["id"] == id:
					fixed.append(p)
		return fixed
	var picked := _weighted_pick(_available_of(tier), count)
	if picked.size() < count and tier == "major":
		picked.append_array(_weighted_pick(_available_of("minor"), count - picked.size()))
	return picked


func _available_of(tier: String) -> Array:
	return POWERUPS.filter(func(p: Dictionary) -> bool:
		return p["tier"] == tier and not p.get("disabled", false) and _is_available(p["id"]))


func _weighted_pick(pool: Array, count: int) -> Array:
	var picked := []
	while picked.size() < count and not pool.is_empty():
		var total := 0.0
		for p in pool:
			total += float(p["weight"])
		var roll := randf() * total
		for i in pool.size():
			roll -= float(pool[i]["weight"])
			if roll <= 0.0 or i == pool.size() - 1:
				picked.append(pool[i])
				pool.remove_at(i)
				break
	return picked


func _is_available(id: String) -> bool:
	# Story mode only offers parts the player owns (Workshop unlocks).
	if GameManager.game_mode == "story" and not Story.is_unlocked(id):
		return false
	match id:
		"multiplier":
			return not _placeable_targets(false).is_empty()
		"mega_multiplier":
			return not _placeable_targets(true).is_empty()
		"bouncy_ball":
			# Not in the tutorial: Sal's scripted shots rely on the normal bounce.
			return GameManager.ball_bounce_mult < BOUNCE_MAX - 0.001 and GameManager.game_mode != "tutorial"
		"boss_magnet":
			return GameManager.boss_magnet < BossBumper.MAGNET_MAX_STACKS
		"gap_guard":
			return not is_instance_valid(_gap_guard) or _gap_guard.saves < gap_guard_max
		"outlane_guards":
			return not is_instance_valid(_left_guard) or not is_instance_valid(_right_guard) \
					or _left_guard.saves < outlane_guard_max or _right_guard.saves < outlane_guard_max
		"turbo_ramps":
			# Pointless on a machine with no ramps.
			return not get_tree().get_nodes_in_group("tunnels").is_empty()
		# Not in the tutorial: Sal's scripted shots expect the stock machine.
		"kickback":
			return _kickbacks.size() < KICKBACK_ORDER.size() and GameManager.game_mode != "tutorial"
		"upper_flipper":
			return _upper_flippers.size() < UPPER_ORDER.size() and GameManager.game_mode != "tutorial"
		"multiball_lock":
			return GameManager.multiball_locks < 2 and GameManager.game_mode != "tutorial"
	return true


func _choose(index: int) -> void:
	if index < 0 or index >= _offer.size() or not _choice_root.visible:
		return
	_choice_root.visible = false
	Sfx.play("click")
	_apply(_offer[index]["id"])


func _apply(id: String) -> void:
	match id:
		"extra_ball":
			GameManager.add_extra_ball()
		"multiplier":
			_start_placement(false)
			return # finishes after the player places it
		"mega_multiplier":
			_start_placement(true)
			return
		"bouncy_ball":
			GameManager.ball_bounce_mult = minf(BOUNCE_MAX, GameManager.ball_bounce_mult + 0.1)
			_apply_bounce()
		"gap_guard":
			_gap_guard = _grow_guard(_gap_guard, _guard_pos("gap_guard", 0, gap_guard_a), _guard_pos("gap_guard", 1, gap_guard_b), Vector2.UP, 450.0, 8.0, 16.0, gap_guard_saves, gap_guard_max)
		"outlane_guards":
			_left_guard = _grow_guard(_left_guard, _guard_pos("left_outlane_guard", 0, left_outlane_a), _guard_pos("left_outlane_guard", 1, left_outlane_b), Vector2(0.35, -1.0), 620.0, 0.0, 0.0, outlane_guard_saves, outlane_guard_max)
			_right_guard = _grow_guard(_right_guard, _guard_pos("right_outlane_guard", 0, right_outlane_a), _guard_pos("right_outlane_guard", 1, right_outlane_b), Vector2(-0.35, -1.0), 620.0, 0.0, 0.0, outlane_guard_saves, outlane_guard_max)
		"steady_hands":
			_steady_stacks += 1
			GameManager.tilt_limit_bonus += 1.0
		"boss_crusher":
			_crusher_stacks += 1
			GameManager.boss_damage_mult += 0.5
		"ball_saver":
			GameManager.ball_save_seconds += 10.0
		"turbo_ramps":
			GameManager.ramp_turbo += 1
		"boss_magnet":
			GameManager.boss_magnet += 1
		"combo_master":
			GameManager.combo_bonus_extra += 0.05
		"kickback":
			_add_kickback()
		"upper_flipper":
			_add_upper_flipper()
		"multiball_lock":
			GameManager.multiball_locks += 1
	_finish_choice()


func _finish_choice() -> void:
	_placing = false
	_banner.visible = false
	_update_status()
	queue_redraw()
	if not _pending_choices.is_empty() and not GameManager.is_game_over:
		_open_choice() # another lane set was completed meanwhile
		return
	GameManager.choosing = false
	GameManager.resume_play() # short countdown, then play


# --- Level switching ------------------------------------------------------------

var _level: Level


## A new layout was loaded: move each placed multiplier onto a part of the new
## level, preferring the same kind (e.g. "Pop bumper"), otherwise any free part.
## Guards stay: every level shares the same flipper/outlane area.
func _on_level_changed(new_level: Node) -> void:
	_level = new_level as Level
	for side: String in _upper_flippers:
		var f: Flipper = _upper_flippers[side]
		if is_instance_valid(f):
			f.position = _upper_flipper_pos(side)
	if _multipliers.is_empty():
		return
	var carried: Array = _multipliers.values()
	_multipliers.clear()
	for info: Dictionary in carried:
		var free := _free_targets()
		if free.is_empty():
			break
		var target: Node2D = free[randi() % free.size()]
		for t in free:
			if _legend_of(t) == info.get("legend", ""):
				target = t
				break
		info["legend"] = _legend_of(target)
		_multipliers[target] = info
	_update_status()
	queue_redraw()


func _legend_of(node: Node) -> String:
	return str(node.legend_name) if "legend_name" in node else str(node.name)


## Guard endpoint from the current level's exports, falling back to this node's.
func _guard_pos(property: String, index: int, fallback: Vector2) -> Vector2:
	if _level and property in _level:
		var points: PackedVector2Array = _level.get(property)
		if points.size() > index:
			return points[index]
	return fallback


# --- Kickback and Upper Flipper ------------------------------------------------

func _add_kickback() -> void:
	for side: String in KICKBACK_ORDER:
		if _kickbacks.has(side):
			continue
		var kb := Kickback.new()
		kb.side = side
		kb.position = KICKBACK_POS[side]
		kb.process_mode = Node.PROCESS_MODE_PAUSABLE
		kb.changed.connect(_update_status)
		get_parent().add_child.call_deferred(kb)
		_kickbacks[side] = kb
		return


func _upper_flipper_pos(side: String) -> Vector2:
	if _level:
		return _level.upper_flipper_left if side == "L" else _level.upper_flipper_right
	return Vector2(36, 720) if side == "L" else Vector2(524, 740)


func _add_upper_flipper() -> void:
	for side: String in UPPER_ORDER:
		if _upper_flippers.has(side):
			continue
		var f := Flipper.new()
		f.side = Flipper.FlipperSide.LEFT if side == "L" else Flipper.FlipperSide.RIGHT
		f.length = UPPER_LENGTH
		f.base_radius = 10.0
		f.tip_radius = 5.0
		f.rest_angle_deg = UPPER_REST_DEG
		f.active_angle_deg = UPPER_ACTIVE_DEG
		f.quiet = true # the main flipper on that side already plays the sound
		f.position = _upper_flipper_pos(side)
		f.name = "UpperFlipper" + side
		f.process_mode = Node.PROCESS_MODE_PAUSABLE
		get_parent().add_child.call_deferred(f)
		_upper_flippers[side] = f
		return


# --- Guards -------------------------------------------------------------------

func _grow_guard(existing: Guard, a: Vector2, b: Vector2, kick_dir: Vector2, kick: float,
		side_min: float, side_max: float, saves: int, max_saves: int) -> Guard:
	if is_instance_valid(existing) and not existing.is_queued_for_deletion():
		existing.add_saves(saves, max_saves)
		return existing
	var guard := Guard.new()
	guard.point_a = a
	guard.point_b = b
	guard.kick_direction = kick_dir
	guard.kick_speed = kick
	guard.side_angle_min_deg = side_min
	guard.side_angle_max_deg = side_max
	guard.saves = mini(saves, max_saves)
	guard.process_mode = Node.PROCESS_MODE_PAUSABLE
	guard.changed.connect(_update_status)
	guard.broken.connect(_update_status.call_deferred)
	get_parent().add_child.call_deferred(guard)
	return guard


# --- Multipliers --------------------------------------------------------------

func _free_targets() -> Array[Node2D]:
	var all: Array[Node2D] = []
	_collect_targets(get_parent(), all)
	var out: Array[Node2D] = []
	for n in all:
		if not _multipliers.has(n):
			out.append(n)
	return out


## Parts a multiplier pick can go on: free parts, plus parts whose multiplier
## can still be upgraded (minor picks stop at x1.5; Mega goes to x2).
func _placeable_targets(mega: bool) -> Array[Node2D]:
	var all: Array[Node2D] = []
	_collect_targets(get_parent(), all)
	var top_tier := MULT_TIERS.size() - 1 if mega else 1
	var out: Array[Node2D] = []
	for n in all:
		if not _multipliers.has(n) or int(_multipliers[n].get("tier", 0)) < top_tier:
			out.append(n)
	return out


## The tier a pick would give `target`.
func _next_tier(target: Node2D) -> int:
	if _place_mega:
		return MULT_TIERS.size() - 1
	if _multipliers.has(target):
		return mini(int(_multipliers[target]["tier"]) + 1, 1)
	return 0


## Bumpers and wall kickers. The boss never takes a multiplier, and the bottom
## slingshots are excluded (Slingshot.multiplier_target = false).
func _collect_targets(node: Node, out: Array[Node2D]) -> void:
	if (node is Bumper and not node is BossBumper and not node.has_meta("no_multiplier")) \
			or (node is Slingshot and node.multiplier_target):
		out.append(node)
	for child in node.get_children():
		_collect_targets(child, out)


func _mult_text(mult: float) -> String:
	return "x" + String.num(mult, 2)


## What placing on `target` would give: "x1.25" for a free part, or the next tier.
func _placement_label(target: Node2D) -> String:
	var text := _mult_text(MULT_TIERS[_next_tier(target)])
	return "%s (upgrade)" % text if _multipliers.has(target) else text + " here"


func _start_placement(mega: bool) -> void:
	_place_mega = mega
	_place_targets = _placeable_targets(mega)
	if _place_targets.is_empty():
		_finish_choice()
		return
	# Start on the target closest to the table's center for a predictable cursor.
	_place_targets.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return _target_center(a).x < _target_center(b).x)
	_place_index = 0
	var best := INF
	for i in _place_targets.size():
		var d := _target_center(_place_targets[i]).distance_to(Vector2(280, 400))
		if d < best:
			best = d
			_place_index = i
	_placing = true
	_banner.text = ("Place a x2 multiplier, or max out one you placed" if mega else "Place a x1.25 multiplier, or upgrade one you placed") \
			+ "\n<- / -> or point to choose   ·   Enter / Space or click to place"
	_banner.visible = true


func _confirm_placement() -> void:
	var target := _place_targets[_place_index]
	var tier := _next_tier(target)
	if _multipliers.has(target):
		_multipliers[target]["tier"] = tier
		_multipliers[target]["mult"] = MULT_TIERS[tier]
	else:
		_multipliers[target] = {"mult": MULT_TIERS[tier], "tier": tier, "ready_at": 0.0, "legend": _legend_of(target)}
	Sfx.play("multiplier")
	GameManager.popup(_mult_text(MULT_TIERS[tier]) + (" placed" if tier == 0 else "!"), _target_center(target), Color(0.45, 1.0, 0.9), true)
	_finish_choice()


func _on_part_hit(part: Node) -> void:
	if part is BossBumper and GameManager.multiball_locks > 0:
		_update_status.call_deferred() # the lock is used up by this hit (Multiball)
	if not _multipliers.has(part):
		return
	var m: Dictionary = _multipliers[part]
	if _clock < float(m["ready_at"]):
		return
	m["ready_at"] = _clock + multiplier_cooldown
	GameManager.multiply_score(float(m["mult"]), _target_center(part))
	Sfx.play("multiplier")


func _target_center(node: Node2D) -> Vector2:
	if node is Slingshot:
		var s := node as Slingshot
		return s.to_global((s.corner_a + s.corner_b + s.corner_c) / 3.0)
	return node.global_position


func _target_radius(node: Node2D) -> float:
	if node is Bumper:
		return (node as Bumper).radius
	if node is Slingshot:
		var s := node as Slingshot
		var c := (s.corner_a + s.corner_b + s.corner_c) / 3.0
		return maxf(c.distance_to(s.corner_a), maxf(c.distance_to(s.corner_b), c.distance_to(s.corner_c))) * 0.75
	return 20.0


# --- Input (works while paused) -----------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _choice_root.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.physical_keycode:
				KEY_1: _choose(0)
				KEY_2: _choose(1)
				KEY_3: _choose(2)
				_: return
			get_viewport().set_input_as_handled()
		return
	if not _placing:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("flipper_left"):
		_place_index = (_place_index - 1 + _place_targets.size()) % _place_targets.size()
		Sfx.play("click")
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("flipper_right"):
		_place_index = (_place_index + 1) % _place_targets.size()
		Sfx.play("click")
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("launch"):
		_confirm_placement()
	elif event is InputEventMouseMotion:
		var hovered := _target_at_mouse()
		if hovered >= 0 and hovered != _place_index:
			_place_index = hovered # same highlight as choosing with the arrows
			Sfx.play("click", -8.0)
		return
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var best := _target_at_mouse()
		if best >= 0:
			_place_index = best
			_confirm_placement()
	else:
		return
	get_viewport().set_input_as_handled()


## Index of the placeable part under (or within 60 px of) the mouse, or -1.
func _target_at_mouse() -> int:
	var mouse := get_global_mouse_position()
	var best := -1
	var best_d := 60.0
	for i in _place_targets.size():
		var d := _target_center(_place_targets[i]).distance_to(mouse) - _target_radius(_place_targets[i])
		if d < best_d:
			best_d = d
			best = i
	return best


# --- World drawing (multiplier rings, placement cursor) -----------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for part in _multipliers:
		if not is_instance_valid(part):
			continue
		var m: Dictionary = _multipliers[part]
		var center := _target_center(part)
		var r := _target_radius(part) + 7.0
		var remaining := clampf((float(m["ready_at"]) - _clock) / multiplier_cooldown, 0.0, 1.0)
		var label := _mult_text(float(m["mult"]))
		if remaining <= 0.0:
			var glow := 0.6 + 0.4 * sin(_pulse * 5.0)
			draw_arc(center, r, 0.0, TAU, 48, Color(0.45, 1.0, 0.9, glow), 3.0, true)
		else:
			draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 3.0, true)
			draw_arc(center, r, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - remaining), 48, Color(0.45, 1.0, 0.9, 0.6), 3.0, true)
		var pos := center + Vector2(-r, -r - 4.0)
		draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 14, 4, Color(0, 0, 0, 0.9))
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 14, Color(0.45, 1.0, 0.9) if remaining <= 0.0 else Color(0.7, 0.8, 0.85))
	if _placing:
		for i in _place_targets.size():
			var target := _place_targets[i]
			var center := _target_center(target)
			var r := _target_radius(target) + 8.0
			if i == _place_index:
				var grow := 3.0 * sin(_pulse * 8.0)
				draw_arc(center, r + grow, 0.0, TAU, 48, Color(1.0, 0.9, 0.3), 4.0, true)
				var label_y := -r - (24.0 if _multipliers.has(target) else 8.0)
				draw_string_outline(font, center + Vector2(-60, label_y), _placement_label(target), HORIZONTAL_ALIGNMENT_CENTER, 120, 15, 4, Color.BLACK)
				draw_string(font, center + Vector2(-60, label_y), _placement_label(target), HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(1.0, 0.9, 0.3))
			else:
				draw_arc(center, r, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 2.0, true)


# --- Status list --------------------------------------------------------------

func _update_status() -> void:
	if _status:
		_status.text = "\n".join(_status_lines())


func _status_lines() -> Array[String]:
	var lines: Array[String] = []
	for part in _multipliers:
		if is_instance_valid(part):
			var name_text: String = part.legend_name if "legend_name" in part else str(part.name)
			lines.append("%s on %s" % [_mult_text(float(_multipliers[part]["mult"])), name_text])
	if is_instance_valid(_gap_guard) and not _gap_guard.is_queued_for_deletion() and _gap_guard.saves > 0:
		lines.append("Gap Guard  %s" % "o".repeat(_gap_guard.saves))
	var l := _left_guard.saves if is_instance_valid(_left_guard) and not _left_guard.is_queued_for_deletion() else 0
	var r := _right_guard.saves if is_instance_valid(_right_guard) and not _right_guard.is_queued_for_deletion() else 0
	if l > 0 or r > 0:
		lines.append("Outlane Guards  L%s R%s" % ["o".repeat(l) if l > 0 else "-", "o".repeat(r) if r > 0 else "-"])
	if _steady_stacks > 0:
		lines.append("Steady Hands +%d" % _steady_stacks)
	if _crusher_stacks > 0:
		lines.append("Boss Crusher +%d%%" % (_crusher_stacks * 50))
	if GameManager.ball_save_seconds > 0.0:
		lines.append("Ball Saver %ds" % int(GameManager.ball_save_seconds))
	if GameManager.ramp_turbo > 0:
		lines.append("Turbo Ramps x%d" % GameManager.ramp_turbo)
	if GameManager.boss_magnet > 0:
		lines.append("Boss Magnet x%d" % GameManager.boss_magnet)
	if GameManager.combo_bonus_extra > 0.0:
		lines.append("Combo Master +%d%%" % int(round(GameManager.combo_bonus_extra * 100.0)))
	if GameManager.ball_bounce_mult > 1.001:
		lines.append("Bouncy Ball x%s" % String.num(GameManager.ball_bounce_mult, 1))
	for side: String in KICKBACK_ORDER:
		if _kickbacks.has(side) and is_instance_valid(_kickbacks[side]):
			lines.append("Kickback %s  %s" % [side, _kickbacks[side].status_text()])
	if not _upper_flippers.is_empty():
		lines.append("Upper Flipper %s" % " + ".join(_upper_flippers.keys()))
	if GameManager.multiball_locks > 0:
		lines.append("Multiball Lock x%d: hit the boss!" % GameManager.multiball_locks)
	return lines


func _apply_bounce() -> void:
	for ball in get_tree().get_nodes_in_group("ball"): # extra multiball balls too
		if ball.has_method("set_bounce_mult"):
			ball.set_bounce_mult(GameManager.ball_bounce_mult)


# --- UI construction ----------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 15 # above the HUD, below the pause menu
	add_child(_ui)

	_status = Label.new()
	_status.position = Vector2(8, 52)
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	_status.add_theme_constant_override("outline_size", 4)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_status)

	_banner = Label.new()
	_banner.position = Vector2(0, 720)
	_banner.size = Vector2(600, 60)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 18)
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_ui.add_child(_banner)

	_choice_root = Control.new()
	_choice_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_choice_root.visible = false
	_ui.add_child(_choice_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_root.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	var title := Label.new()
	_choice_title = title
	title.text = "CHOOSE A SPARE PART"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	column.add_child(title)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 10)
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_cards_box)
	var hint := Label.new()
	hint.text = "1 / 2 / 3, arrows + Enter, or click.\nIt lasts for the rest of the run."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	column.add_child(hint)


func _fill_cards() -> void:
	_choice_title.text = "MAJOR SPARE PART" if _offer_tier == "major" else "MINOR SPARE PART"
	if GameManager.game_mode == "tutorial":
		_choice_title.text = "SPARE PART" # its fixed offer mixes both kinds
	_choice_title.add_theme_color_override("font_color", TIER_COLORS[_offer_tier])
	for child in _cards_box.get_children():
		child.queue_free()
	var first: Button = null
	for i in _offer.size():
		var p: Dictionary = _offer[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(178, 240)
		card.focus_mode = Control.FOCUS_ALL
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.1, 0.11, 0.2, 0.97) if state != "hover" else Color(0.15, 0.17, 0.3, 0.97)
			style.border_color = (p["color"] as Color) if state != "normal" else (p["color"] as Color).darkened(0.4)
			style.set_border_width_all(4 if state == "focus" else 2)
			style.set_corner_radius_all(12)
			card.add_theme_stylebox_override(state, style)
		card.pressed.connect(_choose.bind(i))
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 12
		box.offset_right = -12
		box.offset_top = 12
		box.offset_bottom = -12
		box.add_theme_constant_override("separation", 10)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(box)
		_card_label(box, "[%d]  %s" % [i + 1, str(p["tier"]).to_upper()], 13, TIER_COLORS[p["tier"]])
		_card_label(box, p["icon"], 34, p["color"])
		_card_label(box, p["title"], 19, Color.WHITE)
		var desc := _card_label(box, p["desc"], 13, Color(0.8, 0.85, 0.95))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(150, 0)
		_cards_box.add_child(card)
		if first == null:
			first = card
	if first:
		first.grab_focus.call_deferred()


func _card_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
