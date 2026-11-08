class_name Palette
## Shared colors. The boss uses reds; the regular table parts (flippers,
## bumpers, mini bumpers, center post) share a cool blue/teal family so the
## boss always stands out.

# --- Boss (red family) ---------------------------------------------------------
const BOSS_START := Color(0.9, 0.16, 0.22) # crimson
## Picked from at random each new round (never the same as the current one).
const BOSS_REDS: Array[Color] = [
	Color(0.86, 0.08, 0.24), # crimson
	Color(1.0, 0.22, 0.1), # scarlet
	Color(0.89, 0.3, 0.18), # vermilion
	Color(0.88, 0.07, 0.37), # ruby
	Color(0.78, 0.1, 0.14), # cherry
	Color(1.0, 0.36, 0.32), # coral red
	Color(0.95, 0.32, 0.06), # blood orange
	Color(0.74, 0.06, 0.32), # raspberry
]

# --- Table parts (cool family) ------------------------------------------------
const FLIPPER := Color(0.28, 0.56, 1.0) # azure
const BUMPER := Color(0.2, 0.8, 1.0) # cyan
const MINI_BUMPER := Color(0.25, 0.95, 0.8) # teal
const POST := Color(0.55, 0.52, 1.0) # periwinkle


static func random_boss_color(current: Color) -> Color:
	var choices: Array[Color] = []
	for c in BOSS_REDS:
		if not c.is_equal_approx(current):
			choices.append(c)
	return choices[randi() % choices.size()]

# --- Target buttons -------------------------------------------------------------
const BUTTON_OFF := Color(0.34, 0.37, 0.55) # unlit
const BUTTON_LIT := Color(0.74, 0.52, 1.0) # violet
const BUTTON_SPECIAL := Color(1.0, 0.82, 0.25) # gold: the "chase" button
