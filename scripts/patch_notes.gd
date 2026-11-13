class_name PatchNotes
extends RefCounted
## Player-facing patch notes, newest first (shown in Main Menu > Patch Notes).
## Keep them short and non-technical. Give each significant update a name.

const NOTES: Array[Dictionary] = [
	{
		"version": "0.13.7",
		"name": "Page One",
		"date": "Nov 13, 2026",
		"notes": [
			"Story Mode begins. You bought the machine from Sal. The first time it powers on, something is waiting for you inside.",
			"Every story run pays strange coins, win or lose. Spend them in the Workshop to unlock spare parts for Story runs.",
			"A Journal keeps track of everything you find along the way.",
		],
	},
	{
		"version": "0.13.6",
		"name": "Smooth Ride",
		"date": "Nov 11, 2026",
		"notes": [
			"Two new spare parts. Kickback (minor): a kicker in the outlane fires a draining ball back into play, then recharges after 10 boss hits or 20 bumper hits. Multiball Lock (major): your next boss hit launches an extra ball, and drained balls come back for 20 seconds.",
			"Smoother on phones: the machines take much less work to draw, and the music no longer crackles or stutters when the game is busy.",
			"Power-ups are now called spare parts: minor spare parts from the inlanes, major spare parts from the lights near the boss.",
			"Score multipliers can no longer go on the boss.",
			"A short 3-2-1 countdown plays before the game continues after a pause or a spare-part pick.",
			"Ball stuck somewhere? After a few seconds the game reminds you to nudge it free.",
			"After a run, your score shows up in the leaderboard right where it would land, with your name filling in as you type it.",
		],
	},
	{
		"version": "0.13.5",
		"name": "Mixtape",
		"date": "Nov 9, 2026",
		"notes": [
			"Three new, more upbeat tracks join the lo-fi tune: Sunny Tilt, Multiball Groove and Bumper Bounce. The music now shuffles between them with smooth crossfades.",
		],
	},
	{
		"version": "0.13.4",
		"name": "Meet Sal",
		"date": "Nov 9, 2026",
		"notes": [
			"New Tutorial mode: Sal, the machine's old owner, walks you through launching, flipping, saving a ball from the gutter, power-ups, the boss and tilt. The game pauses and shows you exactly what to press whenever it's your turn.",
			"The leaderboard always shows where you stand: if your best score isn't in the top 10, it appears below them with your position.",
			"Nudges recover a little faster, so you can shove the machine again sooner.",
			"Settings are now split into Audio and Controls tabs. On a keyboard you can bind every action to any key you like.",
			"Tap the star or the skull under the leaderboard to see the top 10 for just that kind of run. Tap it again to see everyone.",
		],
	},
	{
		"version": "0.13.3",
		"name": "Tell Us!",
		"date": "Nov 9, 2026",
		"notes": [
			"New Feedback button in the main menu and the pause menu: report a bug or suggest an idea without leaving the game.",
			"The online leaderboard now loads in browsers on phones (it showed \"network error 8\" before).",
			"Cleaner touch controls: the big button boxes are gone, so nothing covers the flippers or the launch lane. The touch areas are just as big as before.",
		],
	},
	{
		"version": "0.13.1",
		"name": "Quality of Life",
		"date": "Nov 9, 2026",
		"notes": [
			"Classic rebuilt: each loop drops the ball onto a lift kicker that fires it into the top lanes, so the top is finally within reach.",
			"Crossfire has four orbit lights instead of two, including one at the top of the arch.",
			"Fortress has four gates into the boss's ring, each with a light.",
			"Tougher bosses: each new boss's health now also grows with your score, so later bosses can't be beaten in a couple of hits. Fortress walls get tougher with your score too.",
			"Fortress walls fade out smoothly when they break (the ball bounces off first) and fade back in. A faint timer shows when each one comes back.",
			"Gauntlet: the bridge now drops onto a lift kicker that fires the ball back up the right side, plus two new lights beside the boss.",
			"Boss and wall health are easier to read: numbers stay short, like 999K, 1.0M or 12.5B.",
			"No more ceiling: scores and boss health keep growing in very long runs (past 1.0Q come Aa, Ab ... Az, Ba ...).",
			"Power-ups now come in two kinds. Light the inlanes behind the bottom slingshots for a minor power-up, or the lights near the boss for a major one.",
			"New major power-up: Mega Multiplier puts a x2 score multiplier straight on a part.",
			"New minor power-up: Bouncy Ball makes the ball bounce harder. It stacks.",
			"The Machines page has a new Spare Parts tab listing every power-up.",
			"Patch Notes moved to a small button in the corner of the main menu.",
		],
	},
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
