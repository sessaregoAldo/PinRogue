class_name StoryData
extends RefCounted
## Story mode content, as data. Rewrite any line here without touching code.
## To add a chapter: add an entry to CHAPTERS (and a gimmick script if its boss
## needs one; see StoryDirector._start_gimmick).
##
## Voices: the Ghost (and his journal) calls the machine "she" / "her". The
## narrator ("switch", "reveal", "machine_change", INTRO_JOURNAL) never does: it
## calls it "It" / "Its", with a capital I, as if It were a name. Menus and
## other game text just say "the machine".
## Write the narrator's It as {It} / {Its}, and the Ghost's she / her (meaning
## the machine) as {she} / {her} / {herself}: any {word} is drawn in MACHINE_FONT
## (see rich_label). Sal's "she" is just how people talk about old machines: no marks.

const GHOST := "The Ghost"
const GHOST_UNKNOWN := "???"
const SAL := "Sal"

## HP of the ordinary-looking bumper the boss hides behind (phase 1). Twice the
## first Endless boss. A chapter can set its own ("phase_one_hp").
const PHASE_ONE_HP := 200000.0
## Boss HP at the reveal = the player's score x this. Endless scales by x12, so
## 192 is sixteen times harder.
const BOSS_HP_SCORE_FACTOR := 192.0
## The boss never has less than this, however low the score at the reveal.
const BOSS_HP_MIN := 1000000.0
## Every story boss beaten adds this to all scoring in story runs (a passive
## upgrade, so each chapter's bigger boss health is a little less of a wall).
const SCORE_BONUS_PER_BOSS := 0.15

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
## Development, debug builds only (running from the editor, never the released
## game): raise this number to mark every chapter as not beaten again the next
## time the save loads. Used to replay chapters while they are being changed.
const BEATEN_RESET := 2

## Spare parts every story run can offer from the start.
const STARTING_PARTS: Array[String] = ["extra_ball", "outlane_guards", "steady_hands", "multiplier", "boss_crusher"]
## Workshop prices (coins) for the rest. Turbo Ramps isn't sold yet: the only
## story ramp so far is the Showroom's lift, in chapter 2.
const PART_PRICES := {
	"bouncy_ball": 40,
	"gap_guard": 45,
	"ball_saver": 45,
	"combo_master": 60,
	"kickback": 70,
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
## Shown after the eye opens in the dark and the Journal slides out.
const INTRO_JOURNAL: Array[String] = [
	"A slot you never noticed opens under the coin door. A journal slides out, already open to page one. The ink is still wet.",
]
const INTRO_GHOST: Array[String] = [
	"Oh! Oh, there's somebody there. Hello. Don't mind the eye in the dark, that's only me.",
	"I built {her}. I'm sure of that much, the way you're sure of your own hands. Every post, every spring. Very nearly finished, I think.",
	"The rest is fog. My name, my years, how I came to be in here. It all went into the gears somewhere, along with the rest of me.",
	"You can call me the Ghost. Nobody else seems to call me anything anymore.",
	"But {she} remembers. I can feel it. There's a face in every bumper, and every face is a piece of me I've lost.",
	"So: you be my hands, and I'll be your instructions. I'll write to you in the journal. Help me finish {her}, and perhaps I'll remember what {she} cost me.",
	"Start simple. Give that center bumper a few good knocks. {She} always did wake up slowly.",
]

## The ghost's note at the start of a run (after the first one).
const WHISPER_START := "Center bumper first. Let's see what {she's} hiding today."
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
		"person": "Corwin, my old partner", # who the boss was (Journal)
		# Music (tools/make_music.py): before the reveal, then the boss fight.
		"music_stage": ["res://assets/music/partner_stage.wav"],
		"music_boss": ["res://assets/music/partner_boss.wav"],
		# The chapter's own machine. Beating the chapter unlocks it for Endless
		# (LevelRegistry.LOCKS).
		"scene": "res://scenes/levels/level_twin_lifts.tscn",
		"gimmick": "splitter",
		"art": "splitter",
		"reveal": "Something behind the bumper comes loose. The cap cracks down the middle.",
		"briefing": [
			"That crack. I know that crack... Corwin. Corwin! I'd lost his name until this very moment.",
			"My partner. \"Fifty-fifty,\" he'd say, and then he'd count, and somehow his fifty was always the bigger one.",
			"While I was building something that mattered, he sat at the books, counting, complaining, calling my best work a waste of time.",
			"And when I needed him most, he split the company in two and walked off with the half that paid. The Splitter. He earned that name.",
			"Knock him three times and he comes apart in two, each half holding its share. Hit one half, then the other, quick as you can. He never could stand being caught on both sides.",
		],
		"hint": "Every third hit splits him in two. Hit one half, then the other, for double damage.",
		"defeat": [
			"Not this time. Go on, Corwin, count your winnings. You always did.",
			"Take the coins. Odd things, aren't they? I never minted them. I don't know who did.",
		],
		"victory": [
			"There. He's quiet now. And now that he is... I remember his laugh. It used to fill the whole workshop.",
			"He didn't take the half that paid. He took the half I'd stopped looking after, and kept it alive for both of us. I'm the one who split.",
			"I think... I think I miss him. Don't write that down. Oh. It's already written down.",
		],
		"journal": "Corwin kept the books and I kept the workshop, and for eleven good years we built the finest machines on the coast. Then {she} came along, and {she} took my evenings, then my weekends, then the orders we'd promised. Corwin kept the shop alive while I disappeared into {her}.\n\nIn the end he split the company so that half of it would survive me. I built his face into the center bumper so I'd have somebody to be angry at. It is easier to hit a man than to admit he was right.",
		"machine_change": "The center bumper keeps its crack. Each time the Ghost says Corwin's name, {It} glows a little brighter, as if {It} likes the sound.",
		"tint": Color(0.86, 0.93, 1.0),
		"hub_line": "One piece of me back. I remember a workshop now, and a friend in it. I'd like to remember the rest, even the parts I won't like.",
	},
	{
		"id": "collector",
		"number": 2,
		"title": "The Patron",
		"boss": "The Collector",
		"person": "Ambrose Pell, my patron",
		"music_stage": ["res://assets/music/collector_stage.wav"],
		"music_boss": ["res://assets/music/collector_boss.wav"],
		# A prelude on the last chapter's machine: after "phase_one_hits" hits on
		# its center bumper the table drops away and "boss_scene" (which beating
		# the chapter unlocks) rises in its place. There phase 1 ("phase_one_hp")
		# and the boss are played as in chapter 1.
		"scene": "res://scenes/levels/level_twin_lifts.tscn",
		"boss_scene": "res://scenes/levels/level_showroom.tscn",
		"phase_one_hits": 3,
		# The prelude's bumper is the beaten Splitter: it cracks a little more with each hit.
		"phase_one_art": "splitter",
		# Each chapter is 2.5x the one before (chapter 1: 200K, score x192, at
		# least 1M): blue bumper, the reveal's score factor and its minimum.
		"phase_one_hp": 500000.0,
		"boss_hp_factor": 480.0,
		"boss_hp_min": 2500000.0,
		# The Showroom's bumper before the reveal: blue, with a round health dial.
		"plain_art": "plain_dial",
		"gimmick": "collector",
		"art": "collector",
		# Played instead of Sal's handover when the chapter starts.
		"opening": [
			"The Splitter's table again. Don't let {her} fool you. {She's} been restless since you put him down.",
			"Clanking in the night. Pieces I don't remember making, rolling about inside {her} like loose change.",
			"Give his old cap a few knocks. Something under there is waiting for a customer.",
		],
		# Narration while the prelude's table shakes, before it drops away.
		"switch": "{It} shudders under your hands. Bolts rattle loose, and somewhere underneath, something lets go.",
		# The ghost, once the new table has risen (the deck tour follows).
		"arrival": [
			"Oh, I know this table. I drew this table, on the back of an invoice. For a customer... his name is right on the tip of my tongue.",
			"Center bumper first, same as before. Whatever's waiting under that one, I'd like a look at it.",
		],
		"reveal": "The bumper's cap flips over like a coin on a counter. The other side is gold, with a jeweller's loupe screwed into it.",
		"briefing": [
			"Pell. Ambrose Pell. I'd forgotten him completely, and now I can smell his cigar smoke. He ran the arcade at the end of the old pier, and he owned everything on it.",
			"He bought everything I built, and he always wanted more. One night he leaned over my bench and demanded one table that could be every table. A Tuesday machine and a Saturday machine, all in one.",
			"He paid in advance so I couldn't say no, then hung that commission round my neck and watched me drown in it. Everything {she} cost me, {she} cost me for him.",
			"He can't keep his eyes off a fine piece. When the ball comes out of the Till's sparkling door, he stops to admire it: hit him then. And anything that falls on him from the gallery up top hurts twice over.",
		],
		# Said while the table's second floor (and the ramps up to it) are shown.
		"deck_tour": [
			"And that's the gallery, up there. A second floor. Whoever I drew it for liked his best pieces where the public could see them, and never touch them.",
			"You'll only see it while the ball's up there. Ride the lift on the right to reach it. It has flippers of its own, and a hole that drops the ball straight down onto the center bumper.",
		],
		"hint": "A ball out of the Till's sparkling exit deals triple damage on its next hit. One dropped from the gallery onto him deals double. At two-thirds and one-third health the table rearranges itself.",
		"whispers": {
			"rearrange": "There, {she's} moving again. Pieces sliding about with nobody's hands on them. I never built that.",
			"showpiece": "The sparkling door! He's admiring it. Hit him now!",
			"gallery": "Straight down from the gallery. He never could resist looking up.",
		},
		# Extra lines on the result page: [label, stats key].
		"stat_rows": [["Rearrangements", "rearranged"], ["Showpiece hits", "showpiece_hits"], ["Gallery hits", "gallery_hits"]],
		"defeat": [
			"He always did outlast me in a shop. He'd just stand there, looking, until I named a lower price.",
			"Take the coins. He'd want you to have something for your trouble. He'd want a receipt, too.",
		],
		"victory": [
			"There. He's still. Looking at something, I think. He always had that look when a machine was finished.",
			"He didn't demand anything. He asked, once, and smiled, and told me to take all the time I needed. He waited at the pier for years, because I told him to.",
			"It wasn't his fault, you know. He only asked. I'm the one who couldn't stop.",
		],
		"journal": "Ambrose Pell ran the arcade at the end of the pier and bought every machine I built, paid in advance so I'd never have to choose between a commission and a meal. He was the kindest customer I ever had.

One night he asked for a table that could be every table. He meant it as a compliment. I took it as a dare, and I have been building {her} ever since. The pier closed. He waited anyway. If he'd never asked, I'd have gone home that night. I don't think I ever went home again.",
		"machine_change": "{Its} lights keep a little of the Showroom's gold. While the Ghost wrote about Pell, {Its} coin door was warm to the touch, like something leaning close to listen.",
		"tint": Color(1.0, 0.95, 0.84),
		"hub_line": "Two pieces back: a friend I failed, and a kind man who asked for too much without knowing it. And {she} rebuilt {herself} in front of us. I never taught {her} that.",
	},
	{
		"id": "timekeeper",
		"number": 3,
		"title": "The Master",
		"boss": "The Timekeeper",
		"person": "Silas Ward, my old master",
		"music_stage": ["res://assets/music/clock_stage.wav", "res://assets/music/clock_stage_slow.wav"],
		"music_boss": ["res://assets/music/clock_boss.wav", "res://assets/music/clock_boss_mid.wav"],
		# Played on its own machine from the start. The clock (ClockFace in the
		# scene) runs slower before the reveal and turns back to the last hour
		# at it; its tilting chimes are the chapter's gimmick.
		"scene": "res://scenes/levels/level_clock_tower.tscn",
		"phase_one_art": "plain_dial",
		# Starts as the blue bumper even when replayed (the clock watches for its reveal).
		"keep_face": false,
		# 2.5x chapter 2.
		"phase_one_hp": 1250000.0,
		"boss_hp_factor": 1200.0,
		"boss_hp_min": 6250000.0,
		"gimmick": "",
		"art": "clock",
		"opening": [
			"This one ticks. Can you hear it? Under the music, under the bumpers. Something in me already hates that sound.",
			"Every hour {she} rings, and every time {she} rings, the whole table shakes. At twelve {she} rings twelve times, and that will shake you right off {her}.",
			"Center bumper first, as always. Keep your hands steady, and keep watching the clock.",
		],
		"reveal": "The blue cap bursts apart. Underneath, the bumper is bare and white, and two dark marks on it begin to turn after the ball.",
		"briefing": [
			"Silas Ward. Master Ward. He kept the tower clock in Haverly, and he never let me forget whose clock it was.",
			"Nothing was ever good enough for him. A tooth a hair too wide, a second lost in a year, and he'd sweep my work off the bench in front of everyone. He drove me out of that shop.",
			"And he's been in my ear ever since. Too slow. Too loose. Every corner of {her} I couldn't get right, that was him. Well, {she} ticks truer than his tower ever did. Let him count that.",
			"Mind the hours: every one he strikes shakes the table, and if he gets to twelve he'll tilt it out from under you.",
		],
		"hint": "Every hour the clock strikes, the table shakes once per chime, and twelve chimes in a row tilt the machine. The hands circle the clock and hide its hour lights. The winding ramp on the right wall loops all the way round the clock.",
		"defeat": [
			"Too slow, he'd say. Always too slow.",
			"Take the coins. Wind yourself up and try again; he'll keep the time for you.",
		],
		"victory": [
			"There. The hands have stopped. I don't think I ever saw them still.",
			"He never swept my work off the bench. He kept every piece I made, in a drawer, with notes on how to make it better. I found that drawer once. I burned it.",
			"I built {her} to prove him wrong, and went looking for something beyond the gears to do it. That voice in my ear was never his.",
			"Wait. Corwin's crack. Pell's commission. Ward's voice over my shoulder. {She} was there every time, wasn't {she}? Long before I ever drew {her}.",
		],
		"journal": "Silas Ward kept the tower clock above Haverly square and taught me every secret of the gear: patience, precision, the tooth that has to be exactly right. I told myself nothing I made was ever good enough for him. It wasn't true. He kept every piece I made, with notes on how to make it better, and I took his care for contempt. I stopped trying and took my hands to pinball, where a machine only has to be fun.

Then I started {her}, and I heard him again. Too slow. Too loose. I made {her} tick truer than his tower ever did, and when brass and springs couldn't take {her} any further, I went looking for something that could. I found it. I don't remember what it asked for in return.

Reading these pages back, I see {her} everywhere. The late nights with Corwin, the commission from Pell, the voice I took for Ward's. Every turn of my life bent toward {her}, as if {she} had drawn the map {herself} and only let me hold the pen.",
		"machine_change": "On the hour {It} ticks once, very softly, though nothing inside {It} is a clock. The Ghost hasn't noticed that {It} ticks loudest while he grieves.",
		"tint": Color(0.95, 0.97, 1.0),
		"hub_line": "Three pieces back, and I don't like how they fit together. {She} was steering me long before I built a single post of {her}. I went looking for something beyond the gears, and I think it was waiting for me. I think it's still in here with us.",
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
			out.append({"id": "%s_%d" % [prefix, first + i], "speaker": speaker, "text": plain(str(lines[i]))})
	add.call("intro_sal", SAL, INTRO_SAL)
	add.call("intro_narration", "Narration", INTRO_JOURNAL)
	add.call("intro_ghost", GHOST, INTRO_GHOST)
	out.append({"id": "whisper_start", "speaker": GHOST, "text": plain(WHISPER_START)})
	for key: String in WHISPERS:
		out.append({"id": "whisper_" + key, "speaker": GHOST, "text": plain(WHISPERS[key])})
	for ch: Dictionary in CHAPTERS:
		var id: String = ch["id"]
		if ch.has("opening"):
			add.call(id + "_opening", GHOST, ch["opening"])
		for key: String in ch.get("whispers", {}):
			out.append({"id": "%s_whisper_%s" % [id, key], "speaker": GHOST, "text": plain(ch["whispers"][key])})
		if ch.has("switch"):
			add.call(id + "_switch", "Narration", [ch["switch"]])
		if ch.has("arrival"):
			add.call(id + "_arrival", GHOST, ch["arrival"])
		add.call(id + "_reveal", "Narration", [ch["reveal"]])
		add.call(id + "_briefing", GHOST, ch["briefing"])
		if ch.has("deck_tour"):
			add.call(id + "_deck", GHOST, ch["deck_tour"])
		add.call(id + "_defeat", GHOST, ch["defeat"])
		add.call(id + "_victory", GHOST, ch["victory"])
	return out


## The typeface of the machine's names (the narrator's It, the Ghost's she / her):
## blocky pixel letters, like something that isn't quite from here.
const MACHINE_FONT := "res://assets/fonts/Silkscreen-Bold.ttf"
## Pixel letters are only sharp at multiples of this size, so those words snap
## to the nearest multiple to the text around them.
const MACHINE_FONT_GRID := 8


## A line with its {word} marks turned into plain words (voice list, logs).
static func plain(text: String) -> String:
	return _marks().sub(text, "$1", true)


## A line as RichTextLabel BBCode: each {word} in MACHINE_FONT, the rest as is.
static func bbcode(text: String, font_size: int) -> String:
	var out := text.replace("[", "[lb]")
	var tag := "[font=%s][font_size=%d]$1[/font_size][/font]" % [MACHINE_FONT, maxi(roundi(float(font_size) / MACHINE_FONT_GRID), 1) * MACHINE_FONT_GRID]
	return _marks().sub(out, tag, true)


static func _marks() -> RegEx:
	var re := RegEx.new()
	re.compile("[{]([A-Za-z']+)[}]")
	return re


## A wrapping text block that shows each {word} in MACHINE_FONT; used for story
## lines wherever they appear (journal pages, the result page).
static func rich_label(text: String, font_size: int, color: Color, width: float, base_font: Font = null) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", color)
	if base_font:
		label.add_theme_font_override("normal_font", base_font)
	label.text = bbcode(text, font_size)
	return label


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
