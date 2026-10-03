class_name StoryData
extends RefCounted

# Story cards shown before a day begins (DayDirector plays them, StoryPlayer shows them).
# The prologue runs before day 1; every new wall section (Neh 3) gets a card, and the
# narrative beats of Neh 4–6 go in front of the section where the GDD pacing arc puts them.
#
# Slide keys (all optional except one of title/text):
#   eyebrow, title, text (narration, typed out), verse, ref
#   art   — texture path; the drawn backdrop (sky/built) stands in when it's missing
#   sky   — "night" | "dawn" | "day" | "dusk"   (drawn backdrop)
#   built — 0–1, how much of the wall stands     (drawn backdrop)
#   met   — Friends and Foes key this slide introduces (GameState.mark_met)
#   twist — a twist key (GameState.TWIST_INTRO): three drawn panels of how it works
#           (TwistCard); one per twist new to the section, after its card
#   choice — true: the crew picks a boon for the stretch (GameState.BOONS), sent to the
#           DayDirector (StoryPlayer.choice_made)
#   map   — section index: the circuit map instead of a backdrop (CircuitMap), sections
#           before it standing; "inspect": true for the night ride, every stretch broken;
#           "finale": true for the ending, the last stretch rises and the ring closes
#
# Scripture: World English Bible (public domain, ebible.org/eng-web), checked 27 Sep 2026.
# Adapted: Neh 4:14 reads "Yahweh" where the WEB has "the Lord", so credit it as
# "adapted from" the WEB (its trademark covers unchanged text only).
# Not the NWT: jw.org terms forbid its text in software or anything sold.

# Story illustrations live in assets/story.

const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]

# Narration for each section card (index = GameState.SECTIONS index), from Neh 3
const SECTION_LINES := [
	"Eliashib the high priest and his brothers the priests take up the work at the Sheep Gate.",
	"The sons of Hassenaah build the Fish Gate and lay its beams.",
	"Joiada and Meshullam repair the Gate of the Old City. Its stone lies in the burned rubble.",
	"Goldsmiths and ointment makers — craftsmen, not masons — repair the wall as far as the Broad Wall.",
	"Malchijah and Hasshub repair another section, and the Tower of the Bake Ovens.",
	"Hanun and the people of Zanoah rebuild the Valley Gate and a thousand cubits of wall.",
	"Malchijah son of Rechab repairs the Gate of the Ash Heaps, far from where the stone is stacked.",
	"Shallun repairs the Fountain Gate, down by the pool at the King's Garden.",
	"The temple servants living on Ophel work as far as the Water Gate. Guards keep watch by night.",
	"Above the Horse Gate the priests each repair in front of their own house.",
	"Shemaiah, the keeper of the East Gate, makes repairs.",
	"The last stretch: from the Inspection Gate back around to the Sheep Gate. Close the circuit.",
]

# Who built each stretch, in Neh 3's own "next to him" chain (index = GameState.SECTIONS
# index). Shown on the tally when the stretch stands. Names only, picked from the chapter's
# verses for that stretch — the real texture of the passage; trimmed to fit a line or two.
const BUILDERS := [
	"Eliashib the high priest and his brothers · next to him the men of Jericho · next to them Zaccur son of Imri",
	"The sons of Hassenaah · next to them Meremoth son of Uriah · next to him Meshullam son of Berechiah · next to him Zadok son of Baana",
	"Joiada son of Paseah and Meshullam son of Besodeiah · next to them Melatiah the Gibeonite and Jadon the Meronothite",
	"Uzziel the goldsmith · next to him Hananiah, one of the ointment makers · next to them Rephaiah son of Hur, ruler of half of Jerusalem",
	"Jedaiah son of Harumaph · next to him Hattush · Malchijah and Hasshub, with the Tower of the Ovens · next to him Shallum and his daughters",
	"Hanun and the people of Zanoah, a thousand cubits of wall to the Gate of the Ash Heaps",
	"Malchijah son of Rechab, ruler of the district of Beth-haccherem",
	"Shallun son of Col-hozeh, ruler of the district of Mizpah · next to him Nehemiah son of Azbuk",
	"The Levites Rehum, Hashabiah and Bavvai · Meremoth again · Palal, Pedaiah · the temple servants of Ophel · the Tekoites, a second portion",
	"The priests, each one in front of his own house · Zadok son of Immer",
	"Shemaiah son of Shecaniah, keeper of the East Gate · next to him Hananiah and Hanun · Meshullam opposite his chamber",
	"Malchijah the goldsmith · then the goldsmiths and the merchants, to the Sheep Gate",
]

# Beats that play before a section's card (section index → slides)
const BEATS := {
	0: [
		{ "eyebrow": "Shushan the citadel · Month of Chislev", "title": "Word from Judah", "art": "res://assets/story/judah.png",
		  "text": "Nehemiah, cupbearer to King Artaxerxes, asks about the Jews who returned to Jerusalem.",
		  "verse": "“The wall of Jerusalem is also broken down, and its gates are burned with fire.”",
		  "ref": "Nehemiah 1:3", "sky": "night", "built": 0.0 },
		{ "eyebrow": "Before the king · Month of Nisan", "title": "The request", "art": "res://assets/story/request.png",
		  "text": "He prays to the God of the heavens, then asks the king to send him to rebuild the city of his forefathers. The king grants it.",
		  "ref": "Nehemiah 2:4-8", "sky": "day", "built": 0.0 },
		{ "eyebrow": "Jerusalem · By night", "title": "The inspection", "art": "res://assets/story/inspection.png",
		  "text": "Telling no one, he rides out in the dark and inspects the broken walls and the burned gates.",
		  "ref": "Nehemiah 2:12-15", "sky": "night", "built": 0.0 },
		{ "eyebrow": "Jerusalem · 455 BCE", "title": "Let us build", "art": "res://assets/story/build.png",
		  "text": "He tells the people how the hand of his God has been with him.",
		  "verse": "“Let’s rise up and build.”",
		  "ref": "Nehemiah 2:18", "sky": "dawn", "built": 0.0 },
	],
	2: [
		{ "eyebrow": "Samaria", "title": "Sanballat scoffs", "art": "res://assets/story/sanballat.png", "met": "sanballat",
		  "text": "Sanballat the Horonite hears that the wall is going up. He is furious, and he mocks the Jews before his army.",
		  "verse": "“Will they revive the stones out of the heaps of rubbish, since they are burned?”",
		  "ref": "Nehemiah 4:1, 2", "sky": "dusk", "built": 0.15 },
	],
	3: [
		{ "eyebrow": "Beside Sanballat", "title": "Tobiah laughs", "art": "res://assets/story/tobiah.png", "met": "tobiah",
		  "verse": "“What they are building, if a fox climbed up it, he would break down their stone wall.”",
		  "text": "The work goes on. The wall is joined together up to half its height, for the people have a heart to work.",
		  "ref": "Nehemiah 4:3, 6", "sky": "dusk", "built": 0.3 },
	],
	5: [
		{ "eyebrow": "Sanballat · Tobiah · Geshem", "title": "The conspiracy", "art": "res://assets/story/conspiracy.png", "met": "geshem",
		  "text": "The enemies plot together to come and fight against Jerusalem and throw it into confusion.",
		  "ref": "Nehemiah 4:7, 8", "sky": "night", "built": 0.45 },
		{ "eyebrow": "Jerusalem · Day and night", "title": "We prayed, and set a watch",
		  "text": "The plot is no secret now. The builders answer it with prayer, and with a guard on the wall by day and by night.",
		  "verse": "“But we made our prayer to our God, and set a watch against them day and night.”",
		  "ref": "Nehemiah 4:9", "sky": "night", "built": 0.45 },
		{ "eyebrow": "On the wall", "title": "Keep Yahweh in mind", "art": "res://assets/story/remember.png",
		  "verse": "“Don’t be afraid of them! Remember Yahweh, who is great and awesome.”",
		  "ref": "Nehemiah 4:14", "sky": "dawn", "built": 0.45 },
		{ "eyebrow": "From that day on", "title": "Armed while building", "art": "res://assets/story/armed.png",
		  "text": "Half the men work, half hold the spears. The builders carry the loads with one hand and a weapon in the other. Where the horn sounds, gather.",
		  "ref": "Nehemiah 4:16-20", "sky": "day", "built": 0.45 },
	],
	7: [
		{ "eyebrow": "Jerusalem · Within the wall", "title": "The cry of the people",
		  "text": "The work has drawn the people from their fields. Hungry, in debt to their own brothers, some families are giving up their children as servants for grain. Nehemiah is very angry.",
		  "verse": "“Our flesh is as the flesh of our brothers, our children as their children.”",
		  "ref": "Nehemiah 5:1-6", "sky": "dusk", "built": 0.6 },
		{ "eyebrow": "A great assembly", "title": "Give it back",
		  "text": "He puts it to the nobles and the rulers: stop the interest, and give back the fields, the vineyards, the olive groves and the houses. They agree, and the people praise Yahweh.",
		  "verse": "“We will restore them, and will require nothing of them.”",
		  "ref": "Nehemiah 5:7-13", "sky": "day", "built": 0.6 },
		{ "eyebrow": "Twelve years as governor", "title": "Nehemiah’s table",
		  "text": "He never takes the governor’s food allowance. A hundred and fifty men eat at his table at his own cost, and he works on the wall with them. Today the valley is quiet.",
		  "verse": "“I didn’t demand the governor’s pay, because the bondage was heavy on this people.”",
		  "ref": "Nehemiah 5:14-18", "sky": "dawn", "built": 0.6 },
	],
	8: [
		{ "eyebrow": "Opposite the great tower", "title": "A second portion",
		  "text": "The Tekoites repair a second stretch of the wall. Their nobles would not put their necks to the work; the rest of the Tekoites more than make up for it.",
		  "ref": "Nehemiah 3:5, 27", "sky": "dusk", "built": 0.65 },
	],
	10: [
		{ "eyebrow": "A message from Sanballat and Geshem", "title": "Come down to Ono", "art": "res://assets/story/ono.png",
		  "text": "Four times they send the same invitation, meaning to harm him. Four times he gives the same answer.",
		  "verse": "“I am doing a great work, so that I can’t come down.”",
		  "ref": "Nehemiah 6:2-4", "sky": "day", "built": 0.85 },
		{ "eyebrow": "Sanballat’s servant", "title": "The open letter",
		  "text": "A fifth time he sends, this time with an open letter in his hand: a rumour that Nehemiah means to be king, and that it will be reported to the king.",
		  "verse": "“There are no such things done as you say, but you imagine them out of your own heart.”",
		  "ref": "Nehemiah 6:5-9", "sky": "day", "built": 0.85 },
	],
	11: [
		{ "eyebrow": "The house of Shemaiah", "title": "Hide in the temple",
		  "text": "A man shut in at home warns that they will come by night to kill Nehemiah: meet in the temple and shut its doors. It is a trap. He was hired to make Nehemiah afraid.",
		  "verse": "“Should a man like me flee? I will not go in.”",
		  "ref": "Nehemiah 6:10-13", "sky": "night", "built": 0.95 },
	],
}

# After day 52: the ring closes, the foes lose heart, the dedication. The end screen
# that follows carries Neh 6:15 itself, so the first card leaves the verse to it.
const ENDING := [
	{ "eyebrow": "Jerusalem · The twenty-fifth of Elul", "title": "Fifty-two days",
	  "text": "The last stone is set and the doors hang in their gates. From the Sheep Gate all the way around, the wall stands.",
	  "ref": "Nehemiah 6:15", "map": 11, "finale": true },
	{ "eyebrow": "Sanballat · Tobiah · Geshem", "title": "They lost heart", "art": "res://assets/story/lostheart.png",
	  "text": "The enemies hear of it, and all the nations around are afraid. Their schemes have come to nothing.",
	  "verse": "“They perceived that this work was done by our God.”",
	  "ref": "Nehemiah 6:16", "sky": "dusk", "built": 1.0 },
	{ "eyebrow": "The dedication of the wall", "title": "Heard far away", "art": "res://assets/story/dedication.png",
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
	# What's new here, drawn: the whole crew reads it before the work starts (the dawn
	# banner alone went unread with scouts coming)
	var before: Array = GameState.SECTIONS[i - 1].get("twists", []) if i > 0 else []
	for twist: String in section.get("twists", []):
		if twist in before or TwistCard.captions(twist).is_empty():
			continue
		slides.append({
			"eyebrow": TranslationServer.translate("New at the %s") % TranslationServer.translate(section["name"]),
			"title": TWIST_TITLES.get(twist, twist),
			"twist": twist,
		})
	if choice_offered(i):
		slides.append({
			"eyebrow": "Before the work",
			"title": "How will you meet it?",
			"text": "“We made our prayer to our God, and set a watch.” Choose how the crew meets this stretch; each way has its price. The crew's pick decides; the host breaks a tie.",
			"ref": "Nehemiah 4:9",
			"choice": true,
			"sky": "dawn", "built": 0.3,
		})
	return slides

## The last card before a new stretch asks how the crew will meet it (campaign only)
static func choice_offered(section_index: int) -> bool:
	return section_index > 0 and not GameState.is_replay() and not GameState.free_play() and not GameState.attract

const TWIST_TITLES := {
	"doors": "Hang the doors", "beams": "Beams take two", "salvage": "Stone from the rubble",
	"mixing": "Mix the mortar", "thick": "The Broad Wall", "ruins": "Old stones, burned timbers", "horn": "Sound the horn",
	"haul": "The long haul", "spring": "By the pool", "night": "The night watch",
	"cramped": "Narrow lanes", "schemes": "Come down to Ono",
}

## Debug builds: `-- --nostory` skips every card
static func disabled() -> bool:
	return GameState.free_play() or (OS.is_debug_build() and "--nostory" in OS.get_cmdline_user_args())
