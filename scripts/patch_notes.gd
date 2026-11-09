class_name PatchNotes
extends RefCounted
## Player-facing patch notes, newest first (shown in Main Menu > Patch Notes).
## Keep them short and non-technical. Give each significant update a name.

const NOTES: Array[Dictionary] = [
	{
		"version": "0.13",
		"name": "Hall of Fame",
		"date": "Nov 9, 2026",
		"notes": [
			"The leaderboard is now global: your best runs go up against every player's.",
			"New Patch Notes page (you're reading it!).",
			"The leaderboard shows how each run ended: a star if the player walked away after beating a boss, a skull if they ran out of balls.",
			"Saving your name to the leaderboard now works on phones.",
			"The ball counter now shows spare balls. It drops as soon as you launch, and a red 0 means this is your last ball.",
			"When placing a multiplier, pointing at a bumper with the mouse highlights it.",
		],
	},
	{
		"version": "0.12",
		"name": "Pick Your Table",
		"date": "Nov 8, 2026",
		"notes": [
			"Endless runs can start on any machine you like, or on a Random one.",
		],
	},
	{
		"version": "0.11",
		"name": "Welcome Aboard",
		"date": "Nov 8, 2026",
		"notes": [
			"New game mode menu. Endless is ready to play; Story Mode, Daily Challenge and Boss Rush are on the way.",
			"A quick controls guide appears before your first ball, for keyboard or touch screen.",
		],
	},
	{
		"version": "0.10",
		"name": "Pinball in Your Pocket",
		"date": "Nov 8, 2026",
		"notes": [
			"Play on phones and tablets: hold the bottom of the screen to flip, pull the launcher down to shoot.",
			"Nudge by swiping, or by jolting your phone (Options > Controls).",
			"Later fixes: bigger flipper buttons, easier swipes, launch power that matches how far you pull, and clearer Fortress walls.",
		],
	},
	{
		"version": "0.9",
		"name": "Power Surge",
		"date": "Nov 8, 2026",
		"notes": [
			"Two more machines: Pinwheel and Gauntlet.",
			"Four new power-ups: Ball Saver, Turbo Ramps, Boss Magnet and Combo Master.",
			"Score multipliers can be upgraded: x1.25, then x1.5, then x2.",
			"Smoother ramps with shadows, and Classic's loops were rebuilt.",
			"Fortress is now guarded by a ring of walls you can break.",
		],
	},
	{
		"version": "0.8",
		"name": "More Maps!",
		"date": "Nov 8, 2026",
		"notes": [
			"Two new machines: Crossfire and Fortress.",
			"Beating a boss and continuing takes you to a different machine.",
			"New main menu, with a Machines page to look at every table.",
		],
	},
	{
		"version": "0.7",
		"name": "The Boss Returns",
		"date": "Nov 7, 2026",
		"notes": [
			"After beating the boss, keep going or end your run. Each new boss is tougher.",
			"Relaxing lo-fi music and a fresh color scheme.",
			"New top lanes and button banks with combos to chase.",
		],
	},
	{
		"version": "0.6",
		"name": "Opening Night",
		"date": "Nov 7, 2026",
		"notes": [
			"PinRogue goes live! Flippers, bumpers, ramps, nudging and a big boss bumper to take down.",
			"Pick power-ups as you play: extra balls, score multipliers, guards and more.",
			"An all-time leaderboard.",
		],
	},
]
