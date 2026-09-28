class_name StoryData
extends RefCounted

# Story cards shown before a day begins (DayDirector plays them, StoryPlayer shows them).
# The prologue runs before day 1; every new wall section (Neh 3) gets a card, and the
# narrative beats of Neh 4–6 go in front of the section where the GDD pacing arc puts them.
#
# Slide keys (all optional except one of title/text):
#   eyebrow, title, text (narration, typed out), verse, ref
#   art   — texture path; until it exists the drawn backdrop stands in
#   sky   — "night" | "dawn" | "day" | "dusk"   (drawn backdrop)
#   built — 0–1, how much of the wall stands     (drawn backdrop)
#   met   — Friends and Foes key this slide introduces (GameState.mark_met)
#   map   — section index: the circuit map instead of a backdrop (CircuitMap), sections
#           before it standing; "inspect": true for the night ride, every stretch broken;
#           "finale": true for the ending, the last stretch rises and the ring closes
#
# Scripture: World English Bible (public domain, ebible.org/eng-web), checked 27 Sep 2026.
# Adapted: Neh 4:14 reads "Yahweh" where the WEB has "the Lord", so credit it as
# "adapted from" the WEB (its trademark covers unchanged text only).
# Not the NWT: jw.org terms forbid its text in software or anything sold.

const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]

# Narration for each section card (index = GameState.SECTIONS index), from Neh 3
const SECTION_LINES := [
	"Eliashib the high priest and his brothers the priests take up the work at the Sheep Gate.",
	"The sons of Hassenaah build the Fish Gate and lay its beams.",
	"Joiada and Meshullam repair the Gate of the Old City. Its stone lies in the burned rubble.",
	"Goldsmiths and ointment makers — craftsmen, not masons — repair the wall as far as the Broad Wall.",
	"Malchijah and Hasshub repair another section, and the Tower of the Bake Ovens.",
	"Hanun and the people of Zanoah rebuild the Valley Gate and a thousand cubits of wall.",
	"Malchijah son of Rechab repairs the Dung Gate, far from where the stone is stacked.",
	"Shallun repairs the Fountain Gate, down by the pool at the King's Garden.",
	"The temple servants living on Ophel work as far as the Water Gate. Guards keep watch by night.",
	"Above the Horse Gate the priests each repair in front of their own house.",
	"Shemaiah, the keeper of the East Gate, makes repairs.",
	"The last stretch: from the Inspection Gate back around to the Sheep Gate. Close the circuit.",
]

# Beats that play before a section's card (section index → slides)
const BEATS := {
	0: [
		{ "eyebrow": "Shushan the citadel · Month of Chislev", "title": "Word from Judah",
		  "text": "Nehemiah, cupbearer to King Artaxerxes, asks about the Jews who returned to Jerusalem.",
		  "verse": "“The wall of Jerusalem is also broken down, and its gates are burned with fire.”",
		  "ref": "Nehemiah 1:3", "sky": "night", "built": 0.0 },
		{ "eyebrow": "Before the king · Month of Nisan", "title": "The request",
		  "text": "He prays to the God of the heavens, then asks the king to send him to rebuild the city of his forefathers. The king grants it.",
		  "ref": "Nehemiah 2:4-8", "sky": "day", "built": 0.0 },
		{ "eyebrow": "Jerusalem · By night", "title": "The inspection",
		  "text": "Telling no one, he rides out in the dark and inspects the broken walls and the burned gates.",
		  "ref": "Nehemiah 2:12-15", "map": 0, "inspect": true },
		{ "eyebrow": "Jerusalem · 455 BCE", "title": "Let us build",
		  "text": "He tells the people how the hand of his God has been with him.",
		  "verse": "“Let’s rise up and build.”",
		  "ref": "Nehemiah 2:18", "sky": "dawn", "built": 0.0 },
	],
	2: [
		{ "eyebrow": "Samaria", "title": "Sanballat scoffs", "met": "sanballat",
		  "text": "Sanballat the Horonite hears that the wall is going up. He is furious, and he mocks the Jews before his army.",
		  "verse": "“Will they revive the stones out of the heaps of rubbish, since they are burned?”",
		  "ref": "Nehemiah 4:1, 2", "sky": "dusk", "built": 0.15 },
	],
	3: [
		{ "eyebrow": "Beside Sanballat", "title": "Tobiah laughs", "met": "tobiah",
		  "verse": "“What they are building, if a fox climbed up it, he would break down their stone wall.”",
		  "text": "The work goes on. The wall is joined together up to half its height, for the people have a heart to work.",
		  "ref": "Nehemiah 4:3, 6", "sky": "dusk", "built": 0.3 },
	],
	5: [
		{ "eyebrow": "Sanballat · Tobiah · Geshem", "title": "The conspiracy", "met": "geshem",
		  "text": "The enemies plot together to come and fight against Jerusalem and throw it into confusion.",
		  "ref": "Nehemiah 4:7, 8", "sky": "night", "built": 0.45 },
		{ "eyebrow": "On the wall", "title": "Keep Yahweh in mind",
		  "verse": "“Don’t be afraid of them! Remember Yahweh, who is great and awesome.”",
		  "ref": "Nehemiah 4:14", "sky": "dawn", "built": 0.45 },
		{ "eyebrow": "From that day on", "title": "Armed while building",
		  "text": "Half the men work, half hold the spears. The builders carry the loads with one hand and a weapon in the other. Where the horn sounds, gather.",
		  "ref": "Nehemiah 4:16-20", "sky": "day", "built": 0.45 },
	],
	10: [
		{ "eyebrow": "A message from Sanballat and Geshem", "title": "Come down to Ono",
		  "text": "Four times they send the same invitation, meaning to harm him. Four times he gives the same answer.",
		  "verse": "“I am doing a great work, so that I can’t come down.”",
		  "ref": "Nehemiah 6:2-4", "sky": "day", "built": 0.85 },
	],
}

# After day 52: the ring closes, the foes lose heart, the dedication. The end screen
# that follows carries Neh 6:15 itself, so the first card leaves the verse to it.
const ENDING := [
	{ "eyebrow": "Jerusalem · The twenty-fifth of Elul", "title": "Fifty-two days",
	  "text": "The last stone is set and the doors hang in their gates. From the Sheep Gate all the way around, the wall stands.",
	  "ref": "Nehemiah 6:15", "map": 11, "finale": true },
	{ "eyebrow": "Sanballat · Tobiah · Geshem", "title": "They lost heart",
	  "text": "The enemies hear of it, and all the nations around are afraid. Their schemes have come to nothing.",
	  "verse": "“They perceived that this work was done by our God.”",
	  "ref": "Nehemiah 6:16", "sky": "dusk", "built": 1.0 },
	{ "eyebrow": "The dedication of the wall", "title": "Heard far away",
	  "text": "Two great choirs of thanksgiving go in procession on top of the wall, one to the right and one to the left, and meet at the house of God.",
	  "verse": "“The joy of Jerusalem was heard even far away.”",
	  "ref": "Nehemiah 12:31-43", "sky": "dawn", "built": 1.0 },
]

## Campaign won: the ending plays before the end screen (not after a replay)
static func plays_ending() -> bool:
	return not GameState.is_replay() and not disabled()

## Slides to play before `day` starts; empty when the day has no story
static func slides_for_day(day: int) -> Array:
	var i := GameState._section_index_for_day(day)
	var section: Dictionary = GameState.SECTIONS[i]
	if section["days"][0] != day:
		return []
	# A replay goes straight to the section's own card — the story beats belong to the campaign
	var slides: Array = [] if GameState.is_replay() else BEATS.get(i, []).duplicate()
	slides.append({
		"eyebrow": TranslationServer.translate("Section %s of %s · Day %d") % [ROMAN[i], ROMAN[GameState.SECTIONS.size() - 1], day],
		"title": section["name"],
		"text": SECTION_LINES[i],
		"ref": section["ref"],
		"map": i,
	})
	return slides

## Debug builds: `-- --nostory` skips every card
static func disabled() -> bool:
	return OS.is_debug_build() and "--nostory" in OS.get_cmdline_user_args()
