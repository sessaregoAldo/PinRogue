class_name Multiball
extends Node
## Multiball Lock (major spare part). Each lock waits for the next boss hit,
## which auto-plunges one extra ball per lock up the shooter lane. For SAVE_TIME
## seconds after that, any drained ball is plunged back in. After that, extra
## balls that drain are simply gone; only the last ball on the table costs a
## life (GameManager.drain_ball).

const BALL_SCENE := preload("res://scenes/ball.tscn")
const SAVE_TIME := 20.0
const LAUNCH_SPEED := 1750.0
## Time between two balls plunged from the lane, so they don't overlap.
const LAUNCH_GAP := 0.45

var game: Node # game.gd
var _extras: Array[Ball] = []
var _next_launch_ms: int = 0


func _ready() -> void:
	GameManager.part_hit.connect(_on_part_hit)
	GameManager.ball_resave_requested.connect(_on_resave)
	GameManager.extra_ball_drained.connect(_on_extra_drained)
	GameManager.game_started.connect(_end)
	GameManager.ball_lost.connect(_end) # the last ball drained: multiball is over
	GameManager.round_continued.connect(func(_r: int) -> void: _end())
	GameManager.boss_beaten.connect(func(_info: Dictionary) -> void: _end())
	GameManager.victory.connect(func(_s: float) -> void: _end())
	GameManager.game_over.connect(func(_s: float) -> void: _end())


func _on_part_hit(part: Node) -> void:
	if not part is BossBumper or GameManager.multiball_locks <= 0 or GameManager.tilted:
		return
	var count := GameManager.multiball_locks
	GameManager.multiball_locks = 0
	GameManager.multiball_save_until_ms = Time.get_ticks_msec() + int(SAVE_TIME * 1000.0)
	if game and "hud" in game:
		game.hud.show_banner("MULTIBALL!", 1.0)
	Sfx.play("ramp_complete")
	for i in count:
		var ball: Ball = BALL_SCENE.instantiate()
		ball.name = "ExtraBall%d" % (_extras.size() + 1)
		game.add_child(ball)
		ball.set_bounce_mult(GameManager.ball_bounce_mult)
		_extras.append(ball)
		_plunge(ball)


## Shoot `ball` up the shooter lane, one at a time.
func _plunge(ball: Ball) -> void:
	var now := Time.get_ticks_msec()
	var at := maxi(now, _next_launch_ms)
	_next_launch_ms = at + int(LAUNCH_GAP * 1000.0)
	if at > now:
		await get_tree().create_timer((at - now) / 1000.0, false).timeout
	if not is_instance_valid(ball) or game == null or game.level == null:
		return
	ball.place(game.level.spawn_point, Vector2(0, -LAUNCH_SPEED))
	Sfx.play("launch")


func _on_resave(ball: Ball) -> void:
	if game and "hud" in game:
		game.hud.show_banner("BALL SAVED", 0.6)
	await get_tree().create_timer(0.5, false).timeout
	if is_instance_valid(ball) and not ball.in_play and not GameManager.is_game_over:
		_plunge(ball)


func _on_extra_drained(ball: Ball) -> void:
	if ball in _extras:
		_extras.erase(ball)
		ball.queue_free()
	# The main ball just waits off the table: it is plunged again (or respawned
	# in the launcher) when the last ball drains.


## Round over / run over: clear the extra balls and the save window.
func _end() -> void:
	GameManager.multiball_save_until_ms = 0
	_next_launch_ms = 0
	for ball in _extras:
		if is_instance_valid(ball):
			ball.queue_free()
	_extras.clear()


func active_balls() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("ball"):
		if node is Ball and node.in_play:
			n += 1
	return n
