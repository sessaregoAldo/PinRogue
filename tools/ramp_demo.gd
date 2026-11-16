extends SceneTree
## Live ramp replay for play-testing ramps.
##
## One table, one shot spot (fires straight up from --from, again and again):
##   godot --path . -s tools/ramp_demo.gd -- --level=<scene> [--from=x,y (default 512,580)] [--speed=1200] [--pause=2.5]
##
## Every machine, every ramp (fires into each ramp mouth in turn, twice, then
## the next machine):
##   godot --path . -s tools/ramp_demo.gd -- --all [--ahead=0.6] [--behind=0.3] [--speed=1200]
## --ahead / --behind: try the lookahead / lookbehind window on every ramp, as a
## share of that ramp's length (0 = off, the ramp shows whole while ridden), or
## in px with --ahead_px= / --behind_px= (they win over the shares).
## --shots=dir: save a screenshot of each ride (mid-way) into dir.

func _initialize() -> void:
	_run()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a == "--" + key:
			return "1"
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return fallback


func _run() -> void:
	var speed := float(_arg("speed", "1200"))
	var pause := float(_arg("pause", "2.5"))
	var gm = root.get_node("GameManager")
	gm.game_mode = "endless"
	gm.start_random = false
	change_scene_to_file("res://scenes/game.tscn") # game.gd picks up --level=
	for i in 30:
		await process_frame
	var game = current_scene
	var ball = game.get_node("Ball")
	if _arg("all", "") != "":
		await _all_machines(game, ball, gm, speed, pause)
		return
	var from_parts := _arg("from", "512,580").split(",")
	var from := Vector2(float(from_parts[0]), float(from_parts[1]))
	while true:
		gm.balls_left = 9
		gm.ball_launched = true
		ball.place(from, Vector2(0, -speed))
		await _ride(ball)
		await create_timer(pause).timeout


## Wait until the ball has ridden a ramp and is back on the table (or gave up).
func _ride(ball, shot: String = "") -> bool:
	var rode := false
	var t0 := Time.get_ticks_msec()
	var took := false
	while Time.get_ticks_msec() - t0 < 10000:
		await physics_frame
		if ball.ramp != null:
			if not rode:
				t0 = Time.get_ticks_msec()
			rode = true
			if shot != "" and not took and Time.get_ticks_msec() - t0 > 450:
				took = true
				root.get_texture().get_image().save_png(shot)
		elif rode:
			return true
		elif Time.get_ticks_msec() - t0 > 2500:
			return false # never got in
	return rode


func _all_machines(game, ball, gm, speed: float, pause: float) -> void:
	var ahead := float(_arg("ahead", "0.6"))
	var behind := float(_arg("behind", "0.3"))
	var shots := _arg("shots", "")
	var rounds := int(_arg("rounds", "0")) # 0 = forever
	var done := 0
	# Loaded here, not named up front: this script starts before the game's autoloads.
	var registry: Script = load("res://scripts/level_registry.gd")
	while rounds == 0 or done < rounds:
		done += 1
		for index in registry.count():
			game._load_level(index)
			for i in 10:
				await physics_frame
			var tunnels: Array = game.level.find_children("*", "Tunnel", true, false)
			for t in tunnels:
				if not t.table_entry or t.path.size() < 2:
					continue
				var length: float = t._length
				t.lookahead = ahead * length if ahead > 0.0 else -1.0
				t.lookbehind = behind * length if behind > 0.0 else -1.0
				if _arg("ahead_px", "") != "":
					t.lookahead = float(_arg("ahead_px", "-1"))
				if _arg("behind_px", "") != "":
					t.lookbehind = float(_arg("behind_px", "-1"))
				var mouth: Vector2 = t.to_global(t.path[0])
				var dir: Vector2 = (t.to_global(t.path[1]) - mouth).normalized()
				for k in 2:
					gm.balls_left = 9
					gm.ball_launched = true
					ball.place(mouth - dir * 40.0, dir * speed)
					var shot := ""
					if shots != "" and k == 0:
						shot = "%s/%s_%s.png" % [shots, game.level.level_name.replace(" ", "_"), t.name]
					var ok: bool = await _ride(ball, shot)
					print("%s / %s: %s" % [game.level.level_name, t.name, "rode it" if ok else "didn't get in"])
					await create_timer(pause).timeout
	quit()
