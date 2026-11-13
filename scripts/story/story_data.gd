class_name StoryData
extends RefCounted
## Story mode content, as data. Rewrite any line here without touching code.
## To add a chapter: add an entry to CHAPTERS (and a gimmick script if its boss
## needs one; see StoryDirector._start_gimmick).

const GHOST := "The Craftsman"
const GHOST_UNKNOWN := "???"
const SAL := "Sal"

## HP of the ordinary-looking bumper the boss hides behind (phase 1). Twice the
## first Endless boss.
const PHASE_ONE_HP := 200000.0
## Boss HP at the reveal = the player's score x this. Endless scales by x12, so
## 192 is sixteen times harder.
const BOSS_HP_SCORE_FACTOR := 192.0
## The boss never has less than this, however low the score at the reveal.
const BOSS_HP_MIN := 1000000.0

# --- Coins --------------------------------------------------------------------------
## Up to this many coins for the share of the first bumper's HP removed.
const COINS_PHASE_ONE := 5
## Up to this many for the share of the boss's HP removed.
const COINS_BOSS := 15
const COINS_FIRST_DEFEAT := 20
const COINS_REPEAT_DEFEAT := 5
## Development: raise this number to set every player's coins back to 0 the next
## time their save loads (used while prices and payouts are being tuned).
const COIN_RESET := 2

## Spare parts every story run can offer from the start.
const STARTING_PARTS: Array[String] = ["extra_ball", "outlane_guards", "steady_hands", "multiplier", "turbo_ramps"]
## Workshop prices (coins) for the rest.
const PART_PRICES := {
	"bouncy_ball": 40,
	"gap_guard": 45,
	"ball_saver": 45,
	"combo_master": 60,
	"kickback": 70,
	"boss_crusher": 90,
	"boss_magnet": 90,
	"multiball_lock": 120,
	"mega_multiplier": 140,
}

# --- Intro --------------------------------------------------------------------------
const INTRO_SAL: Array[String] = [
	"There she is. All yours now.",
	"Don't ask me where she's from. Came across her at an estate sale, under a sheet. No maker's plate, no serial number, nothing.",
	"Never got her to do much, to be honest. But you've got that look. Go on, plug her in.",
]
## Shown after the face flickers in the glass and the Journal slides out.
const INTRO_JOURNAL: Array[String] = [
	"A slot you never noticed opens under the coin door. A journal slides out, already open to page one. The ink is still wet.",
]
const INTRO_GHOST: Array[String] = [
	"Oh! Oh, there's somebody there. Hello. Don't mind the face in the glass, that's only me.",
	"I built her. Every post, every spring. I was very nearly finished, too. I have been very nearly finished for... well. A while.",
	"I'd shake your hand, but mine went into the gears somewhere along the way. The rest of me followed. That's the trouble with loving a thing too much.",
	"So: you be my hands, and I'll be your instructions. I'll write to you in the journal. Help me finish her, and perhaps she lets me go.",
	"Start simple. Give that center bumper a few good knocks. She always did wake up slowly.",
]

## The ghost's note at the start of a run (after the first one).
const WHISPER_START := "Center bumper first. Let's see what she's hiding today."
## When a beaten boss shows up again on a replay.
const REMATCH_LINE := "Back for another round, is he? He never did know when a meeting was over."
## Short lines the ghost writes during play (they don't stop the game).
const WHISPERS := {
	"first_launch": "That plunger spring is original. I wound it myself, on a Tuesday.",
	"first_bumper": "Hear that? Solid brass under the cap. You can't buy that sound anymore.",
	"half_hp": "Something's stirring in there. I don't remember building anything that stirs.",
	"ball_lost": "Never mind. I lost a few thousand of those myself.",
	"boss_half": "He's wobbling! He always did hate being pushed.",
	"split": "There he goes, in two! Quick, both halves, one after the other!",
}

# --- Chapters -----------------------------------------------------------------------
const CHAPTERS: Array[Dictionary] = [
	{
		"id": "splitter",
		"number": 1,
		"title": "The Partner",
		"boss": "The Splitter",
		"level": 0, # LevelRegistry index (Classic)
		"gimmick": "splitter",
		"art": "splitter",
		"reveal": "Something behind the bumper comes loose. The cap cracks down the middle.",
		"briefing": [
			"Ah. I know that crack. That's Corwin. I called him The Splitter, though never to his face.",
			"My business partner. \"Fifty-fifty,\" he'd say, and then he'd count, and somehow his fifty was always the bigger one.",
			"He split everything. The profits, the workshop, the blame. In the end he split the company and took the half with the customers in it.",
			"I should tell you I let him. I was busy. I had a machine to finish.",
			"Mind the bumpers up top: knock one and he comes apart in two, each half holding its share. Hit one half, then the other, quick as you can. He never could stand being caught on both sides.",
		],
		"hint": "Top bumpers split him in two. Hit one half, then the other, for double damage.",
		"defeat": [
			"Not this time. He was always the better talker.",
			"Take the coins. Odd things, aren't they? I never minted them. I don't know who did.",
		],
		"victory": [
			"There. He's quiet now. First time in forty years he hasn't had the last word.",
			"I think... I think I miss him, a little. Don't write that down. Oh. It's already written down.",
		],
		"journal": "Corwin kept the books and I kept the workshop, and for eleven years that was a fair split. Then the machine started taking my evenings, then my weekends, then the invoices I was meant to send. He didn't steal the company. He picked it up off the floor where I'd dropped it.\n\nI built his face into the center bumper so I'd have somebody to be angry at. It is easier to hit a man than to admit he was right.",
		"machine_change": "The center bumper keeps its crack, and the table's lights run a little colder.",
		"tint": Color(0.86, 0.93, 1.0),
		"hub_line": "One piece of the past put down. I feel lighter. Is that possible, for a man with no weight?",
	},
]

## The ghost's line on the Story menu before anything is beaten.
const HUB_LINE_START := "Whenever you're ready. I'm not going anywhere. That is rather the problem."
## Shown on the Story menu when every available chapter is beaten.
const MORE_SOON := "The next pages of the journal are still blank. More chapters are on the way."

# --- Strange coins ------------------------------------------------------------------
const COIN_METALS: Array[String] = [
	"a grey metal that is warm to the touch", "something like silver, but it hums", "green glass with a gold core",
	"a black alloy that weighs nothing", "brass that never tarnishes", "a pale metal that smells of rain",
	"bone-white ceramic, ice cold", "copper with veins of blue light",
]
const COIN_RULERS: Array[String] = [
	"King Osric the Unborn", "Empress Veyla II", "the Regent of the Ninth Tide", "Queen Maud the Returning",
	"the Twin Kings of Harrowmere", "Stadtholder Ilse the Patient", "the Last Elector", "King Tomas, Third and First",
]
const COIN_REALMS: Array[String] = [
	"a country that isn't on any map", "a republic that has not been founded", "the Free Ports of Sarn",
	"a kingdom the history books skip", "the Lower Provinces of somewhere", "an empire with no neighbors",
]
const COIN_EDGES: Array[String] = [
	"The edge is milled with tiny letters you can almost read.", "The reverse shows this machine, finished.",
	"The reverse shows a door with no building around it.", "It has a hole in the middle that isn't always there.",
	"The portrait's eyes are closed. They weren't a minute ago.", "The date is stamped twice, and the two dates disagree.",
	"There is a fingerprint in the metal, as if it was pressed while soft.", "It spins a little longer than a coin should.",
]


## Every spoken line with its voice-over id: [{id, speaker, text}].
## A recording saved as assets/voice/<id>.mp3 plays with that line.
static func voice_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var add := func(prefix: String, speaker: String, lines: Array, first: int = 1) -> void:
		for i in lines.size():
			out.append({"id": "%s_%d" % [prefix, first + i], "speaker": speaker, "text": str(lines[i])})
	add.call("intro_sal", SAL, INTRO_SAL)
	add.call("intro_narration", "Narration", INTRO_JOURNAL)
	add.call("intro_ghost", GHOST, INTRO_GHOST)
	out.append({"id": "whisper_start", "speaker": GHOST, "text": WHISPER_START})
	for key: String in WHISPERS:
		out.append({"id": "whisper_" + key, "speaker": GHOST, "text": WHISPERS[key]})
	for ch: Dictionary in CHAPTERS:
		var id: String = ch["id"]
		add.call(id + "_reveal", "Narration", [ch["reveal"]])
		add.call(id + "_briefing", GHOST, ch["briefing"])
		add.call(id + "_again", GHOST, [REMATCH_LINE, ch["hint"]])
		add.call(id + "_defeat", GHOST, ch["defeat"])
		add.call(id + "_victory", GHOST, ch["victory"])
	return out


static func chapter(index: int) -> Dictionary:
	return CHAPTERS[clampi(index, 0, CHAPTERS.size() - 1)]


## A coin that shouldn't exist: {year, text}.
static func strange_coin(rng: RandomNumberGenerator) -> Dictionary:
	var year := rng.randi_range(2090, 2611)
	var text := "Dated %d. Struck in %s for %s, of %s. %s" % [
		year,
		COIN_METALS[rng.randi() % COIN_METALS.size()],
		COIN_RULERS[rng.randi() % COIN_RULERS.size()],
		COIN_REALMS[rng.randi() % COIN_REALMS.size()],
		COIN_EDGES[rng.randi() % COIN_EDGES.size()],
	]
	return {"year": year, "text": text}
