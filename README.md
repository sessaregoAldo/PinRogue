# Pinball (Godot 4.3)

Open this folder in Godot 4.3 and press F5.

## Controls
| Action | Keys |
|---|---|
| Left / right flipper | Z or Left Arrow / M, / or Right Arrow |
| Plunger (hold to charge, release to fire) | Space or Down Arrow |
| Nudge left / right / up | A / D / W |
| Restart | R, then R again or "Yes, restart" to confirm (Esc cancels) |
| Pause menu (Resume, Settings, Scoring, Restart, Exit) | Esc |
| Debug: drop ball at mouse | Ctrl + left click (turn off with `debug_mouse_drop` on Main) |

Rebind keys in Project Settings > Input Map. Any action you define there replaces the defaults in `game_manager.gd`.

## Layout
- `scripts/game_manager.gd`: autoload with score, balls, tilt and signals.
- `scenes/main_menu.tscn` / `scripts/main_menu.gd`: the main menu (Start Run, Options, Leaderboard, Machines, Exit). It is the project's main scene.
- `scenes/game.tscn` / `scripts/game.gd`: the game shell. It holds the ball, HUD, menus and power-ups, loads levels, and handles nudge/tilt and camera shake. Continue after a boss loads a random other level. **Debug builds: F9 / F10 switch level.**
- `scenes/levels/`: the table layouts ("machines"). Each inherits `level_base.tscn`, which holds the shared walls, launcher, slingshots, inlanes, flippers and drain. Register new ones in `scripts/level_registry.gd`. Current machines: Classic, Crossfire, Fortress, Pinwheel, Gauntlet.
- `scripts/breakable_wall.gd`: wall sections that take boss-style damage (HP = 10% of the boss's max HP), break, and rebuild 10-15 s later (the Fortress ring).
- `scripts/version_tag.gd`: the version and build time shown in the bottom-left corner. Bump `application/config/version` in Project Settings for releases.
- `scripts/sfx.gd`: autoload `Sfx`. It synthesizes the sound effects at startup, plays them on the "SFX" bus with `Sfx.play("name")`, and saves the volume settings to `user://settings.cfg`. To use real samples, replace entries in `_streams` with your own AudioStreams.
- `scripts/pause_menu.gd`: the Esc menu. It runs while the game is paused.
- `scripts/ball.gd`: the ball. Change its position and velocity only through `place()`, `kick()`, `add_impulse()` and `set_velocity_safe()`.
- `scripts/wall.gd`: polyline walls (`@tool`, so you can edit `points` in the inspector). Set `one_way` to make the shooter gate.
- `scripts/tunnel.gd`: raised tunnels/ramps. The rails are generated from the `path` centerline on their own physics layer, so playfield balls roll underneath. The ball is lifted only if it crosses the mouth (`path[0]`) going forward, faster than `min_entry_speed` and within `entry_angle_deg`. It then rides the rails under gravity, so weak shots roll back out. Tunnels that cross need different `rail_layer` and `z_index` values.
- `scripts/boss_bumper.gd`: the big middle bumper, which has a health bar (`max_hp` 100,000). With `damage_mode` = CURRENT_SCORE, each hit deals damage equal to your current total score. At 0 HP, `GameManager.declare_victory()` shows the victory screen.
- `scripts/score_popups.gd`: floating "+points" text. Turn it on or off in Pause, then Settings, then Score popups (saved). Award points with `GameManager.add_score(points, world_pos)` to get a popup there.
- `scripts/powerups.gd`: roguelike power-ups. Completing a rollover group (with `grants_powerup` on) pauses the game and offers 3 random picks that last for the run: Extra Ball, Score Multiplier (placed on a bumper or wall kicker; a hit multiplies your score by x1.25; pick again to upgrade a part to x1.5, then x2; 20 s cooldown), Gap Guard, Outlane Guards, Steady Hands, Boss Crusher, Ball Saver (a drain within 10 s of launch is forgiven; +10 s per stack), Turbo Ramps (boosters fire from the entrance, ramps score +100% per stack), Boss Magnet (the boss gently pulls nearby balls in; max 3 stacks) and Combo Master (+5% button combo bonus per stack). To add one, add an entry to `POWERUPS` and handle its id in `_apply()`.
- `scripts/guard.gd`: breakable barriers used by the guard power-ups.
- `scripts/leaderboard.gd`: autoload `Leaderboard`, the all-time high scores (names of 2-5 letters). Uses Supabase when `leaderboard_config.cfg` is filled in, otherwise this device. `scripts/end_screen.gd` shows it after GAME OVER or VICTORY, and the pause menu has a High Scores page. See **LEADERBOARD.md** for web hosting on GitHub Pages and the online board.
- `scripts/boss_menu.gd`: when the boss falls, choose **Continue** (keep score, balls and power-ups; the next boss has previous max HP × 5 × overkill ratio and a new red color) or **End Run** (victory screen). The HUD shows the round.
- `scripts/palette.gd`: shared colors. The boss uses reds; the flippers, bumpers and post use a cool blue/teal family.
- `tools/make_lofi.py` → `assets/music/lofi_loop.wav`: the background music, an original lo-fi loop composed in code (no third-party audio, free to use). Re-run with `py tools/make_lofi.py` to regenerate it. Its volume is under Pause → Settings → Music volume.
- `scripts/button_bank.gd` + `scripts/target_button.gd`: the 6 buttons in the top corners (they also turn the launched ball into the bumpers). A hit toggles a button and scores 25. Light exactly the diamond-marked ones for +10% of your score. Hit the gold button through all 6 for score x1.25.
- `scripts/rollover.gd`: lane switches. They light up when the ball rolls over them. When every rollover in a `group_name` is lit, the group pays `group_bonus` and resets (top lanes 2000, inlanes 1000).
- `flipper.gd`, `bumper.gd`, `slingshot.gd`, `tunnel.gd`, `plunger.gd`, `drain.gd`: one script per table part. Tune them through the inspector exports.

Physics runs at 240 Hz, gravity is 1100 px/s² (it stands in for the table's slope), and the ball uses continuous collision detection.
Physics layers: 1 = table, 2 = ball on playfield, 3 = ball on a tunnel, 4-8 = tunnel rails.
