extends SceneTree

# Music moods: every pool loads, "work" resolves by stretch (plain → dark → finale),
# phases pick the right mood, and a track that runs out is followed by another from
# the same pool (never the same one twice running).
#   Godot --headless --path . --script res://tools/music_test.gd
# Exit code 0 = all good.

var _frame := 0
var _done_at := 0
var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false   # Sfx's deferred "menu" start runs first
	if _done_at > 0:
		if _frame < _done_at + 5:
			return false   # let the audio thread drop its playbacks, or they leak at exit
		print("PASS" if _fails.is_empty() else "FAIL: %s" % ", ".join(_fails))
		quit(0 if _fails.is_empty() else 1)
		return true
	# Mark done up front: a script error mid-way then ends the run as a FAIL instead of
	# re-running this block every frame
	_done_at = _frame
	_fails.append("aborted by a script error")
	var sfx: Node = root.get_node("Sfx")
	var gs: Node = root.get_node("GameState")
	# Loaded, not named: naming StoryData here compiles it before the autoloads exist
	var story_data: GDScript = load("res://scenes/story/story_data.gd")
	for mood in ["menu", "story", "calm", "work", "work_dark", "finale"]:
		var n: int = sfx._streams.get("music_" + mood, []).size()
		_check(n > 0, "%s pool has tracks (%d)" % [mood, n])
	_check(sfx._streams["music_work_dark"].size() > sfx._streams["music_work"].size(), "dark pool = work + dark")
	_check(sfx._music_mood == "menu", "starts on the menu mood")
	_check(sfx._music_loaded.size() == 1, "only the menu track loaded at boot (%d)" % sfx._music_loaded.size())

	var last: int = gs.SECTIONS.size() - 1
	for c in [[0, "work"], [sfx.DARK_FROM_SECTION - 1, "work"], [sfx.DARK_FROM_SECTION, "work_dark"],
			[last - 1, "work_dark"], [last, "finale"]]:
		gs.current_section_index = c[0]
		_check(sfx._resolve_mood("work") == c[1], "section %d work → %s" % [c[0], c[1]])
	_check(sfx._resolve_mood("calm") == "calm", "other moods pass through")

	gs.current_section_index = 0
	gs.phase = gs.Phase.GATHER   # as GameState.reset() leaves it: no phase_changed
	sfx.sync_music()
	_check(sfx._music_mood == "calm", "game load in GATHER leaves the menu theme for calm")
	sfx._on_phase(gs.Phase.WON)
	_check(sfx._music_mood == ("story" if story_data.plays_ending() else ""), "won: the ending is read over story music")
	sfx._on_phase(gs.Phase.LOST)
	_check(sfx._music_mood == "", "lost: silence")
	sfx._on_phase(gs.Phase.STORY)
	_check(sfx._music_mood == "story", "story phase → story")
	sfx._on_phase(gs.Phase.WORK)
	_check(sfx._music_mood == ("calm" if gs.festival else "work"), "work phase → work")
	gs.current_section_index = last
	sfx._music_mood = ""
	sfx._on_phase(gs.Phase.WORK)
	_check(sfx._music_mood == "finale", "last stretch work phase → finale")

	# Chaining: the current player running out plays a different track of the same pool
	sfx.play_music("calm")
	var p: AudioStreamPlayer = sfx._music_cur
	_check(p != null and p.playing, "calm is playing")
	var before: AudioStream = p.stream
	sfx._on_music_finished(p)
	_check(p.playing and p.stream != before, "finished track → another calm track")
	_check(sfx._follow_tween != null and sfx._follow_tween.is_running(), "follow-on track eases in")
	var other: AudioStreamPlayer = sfx._music_a if p == sfx._music_b else sfx._music_b
	var was: AudioStream = other.stream
	sfx._on_music_finished(other)
	_check(other.stream == was, "a fading-out player stays quiet when it ends")
	_check(not (p.stream as AudioStreamOggVorbis).loop, "tracks don't self-loop")

	# Narration: every story line has a recording, it plays on the Voice bus and dips the music
	var missing := []
	for slides: Array in story_data.BEATS.values() + [story_data.ENDING]:
		for slide: Dictionary in slides:
			if slide.has("text") and sfx.narration_for(slide["text"]) == null:
				missing.append(slide["text"].left(40))
	for line: String in story_data.SECTION_LINES:
		if sfx.narration_for(line) == null:
			missing.append(line.left(40))
	_check(missing.is_empty(), "every story line is recorded %s" % str(missing))
	_check(sfx.narration_for("A line nobody recorded.") == null, "an unrecorded line is silent")
	_check(AudioServer.get_bus_index("Voice") != -1, "Voice bus exists")
	sfx.narrate(story_data.SECTION_LINES[0])
	_check(sfx.is_narrating() and sfx._voice.bus == "Voice", "narrate plays on the Voice bus")
	_check(sfx._voice_dip != null and sfx._voice_tween.is_running(), "music dips under the voice")
	sfx.narrate("")
	_check(not sfx.is_narrating(), "a slide without narration stops the last one")
	sfx.narrate(story_data.SECTION_LINES[1])
	sfx.stop_narration()
	_check(not sfx.is_narrating(), "stop_narration stops it")
	TranslationServer.set_locale("de")
	_check(sfx.narration_for(story_data.SECTION_LINES[0]) == null, "no English voice over German text")
	TranslationServer.set_locale("en")

	for pl: AudioStreamPlayer in [sfx._music_a, sfx._music_b]:
		pl.stop()
	_fails.erase("aborted by a script error")
	return false
