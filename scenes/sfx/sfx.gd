extends Node

# Sound effects. Every peer plays its own copy: call sites hang off things that
# already run everywhere (replicated setters, call_local RPCs, GameState signals).
# Each event picks a random variant with a little pitch jitter so repeats don't grate.
# Audio: Kenney CC0 packs — see assets/audio/CREDITS.md

const SFX := "res://assets/audio/sfx/"
const JINGLES := "res://assets/audio/jingles/"
const POOL_SIZE := 24
const MIN_GAP := 0.04          # same event can't stack within this (a crowd hitting one wall)
const UNIT_SIZE := 10.0        # full volume within ~this many metres of the listener
const MAX_DISTANCE := 40.0

# name: [files, volume_db, pitch_min, pitch_max]
var _defs := {
	"step":           [_n("footstep0%d", 0, 10), -20.0, 0.9, 1.1],
	"pickup":         [["handleSmallLeather", "handleSmallLeather2"], -2.0, 0.95, 1.1],
	"drop":           [["dropLeather"], -2.0, 0.9, 1.05],
	"dash":           [["cloth1", "cloth2", "cloth3", "cloth4"], -4.0, 1.15, 1.35],
	"throw":          [["clothBelt", "clothBelt2"], -8.0, 0.95, 1.1],
	"deposit_stone":  [_n("impactMining_%03d", 0, 5), -3.0, 0.9, 1.05],
	"deposit_wood":   [_n("impactWood_medium_%03d", 0, 5), -3.0, 0.9, 1.1],
	"deposit_mortar": [_n("impactSoft_medium_%03d", 0, 5), -2.0, 0.85, 1.0],
	"deposit_lime":   [_n("impactSoft_medium_%03d", 0, 5), -2.0, 1.0, 1.15],
	"deposit_water":  [_n("impactSoft_medium_%03d", 0, 5), -4.0, 0.6, 0.7],
	"mix_done":       [_n("impactPlank_medium_%03d", 0, 5), -6.0, 1.1, 1.25],
	"deposit_beam":   [_n("impactWood_heavy_%03d", 0, 5), -2.0, 0.85, 0.95],
	"deposit_branch": [["cloth1", "cloth2", "cloth3", "cloth4"], -3.0, 0.8, 0.95],
	"deposit_portion": [_n("impactSoft_medium_%03d", 0, 5), -4.0, 1.05, 1.2],
	"work_branch":    [_n("impactWood_medium_%03d", 0, 5), -9.0, 1.3, 1.5],
	"build":          [_n("impactPlank_medium_%03d", 0, 5), 0.0, 0.8, 0.95],
	# One strike of the working loop, by what is being worked
	"work_wood":      [_n("impactWood_medium_%03d", 0, 5), -8.0, 1.15, 1.35],
	"work_beam":      [_n("impactWood_medium_%03d", 0, 5), -8.0, 1.0, 1.15],
	"work_stone":     [_n("impactMining_%03d", 0, 5), -9.0, 1.2, 1.45],
	"work_mortar":    [_n("impactSoft_medium_%03d", 0, 5), -7.0, 1.2, 1.4],
	"wall_hit":       [_n("impactMining_%03d", 0, 5), -5.0, 0.6, 0.75],
	"wall_crumble":   [_n("impactWood_heavy_%03d", 0, 5), 0.0, 0.6, 0.7],
	"enemy_swing":    [["knifeSlice", "knifeSlice2"], -8.0, 0.85, 1.05],
	"enemy_hit":      [_n("impactPunch_medium_%03d", 0, 5), -3.0, 0.9, 1.1],
	"enemy_die":      [_n("impactPunch_heavy_%03d", 0, 5), -2.0, 0.75, 0.9],
	# Builder's sword (Neh. 4:18): the swing, higher and brighter than an enemy's
	"sword":          [["knifeSlice", "knifeSlice2"], -6.0, 1.15, 1.35],
	"sling_miss":     [_n("impactGeneric_light_%03d", 0, 5), -8.0, 0.8, 1.0],
	# The sling (GDD §5.16), synthesized by tools/synth_sling.py: one pass of the whirl
	# (pitched up as it speeds), the taut-cord ting of a true-shot window, the release
	# crack, a stone striking a body, and a true shot striking
	"sling_whirl":    [_n("sling_whirl_%03d", 0, 3), -19.0, 0.9, 1.0],
	"sling_glint":    [_n("sling_glint_%03d", 0, 2), -11.0, 0.98, 1.04],
	"sling_crack":    [_n("sling_crack_%03d", 0, 3), -7.0, 0.92, 1.08],
	"stone_thock":    [_n("stone_thock_%03d", 0, 4), -4.0, 0.9, 1.1],
	"true_hit":       [_n("true_hit_%03d", 0, 3), -1.0, 0.95, 1.05],
	# A foe drawing back to strike (the tell), and a strike knocked aside before it lands
	"enemy_tell":     [["handleSmallLeather", "handleSmallLeather2"], -9.0, 0.6, 0.72],
	"interrupt":      [_n("impactPlank_medium_%03d", 0, 5), -5.0, 1.35, 1.55],
	# Breakable props (Breakable): a clay jar shattering, its water, a reed basket crushed
	"shatter":        [_n("shatter_%03d", 0, 4), -6.0, 0.85, 1.15],
	"splash":         [_n("splash_%03d", 0, 3), -10.0, 0.9, 1.1],
	"basket_crush":   [_n("impactPlank_medium_%03d", 0, 5), -8.0, 1.45, 1.7],
	"pot_knock":      [_n("impactGeneric_light_%03d", 0, 5), -16.0, 1.5, 1.8],
	# Birds about the site (Birds): a flock taking off, sparrows, a rock dove
	"wings":          [_n("wings_%03d", 0, 3), -12.0, 0.9, 1.15],
	"chirp":          [_n("chirp_%03d", 0, 4), -22.0, 0.9, 1.15],
	"coo":            [_n("coo_%03d", 0, 3), -20.0, 0.92, 1.05],
	"hurt":           [_n("impactSoft_heavy_%03d", 0, 5), -2.0, 0.9, 1.1],
	"downed":         [_n("impactPunch_heavy_%03d", 0, 5), 0.0, 0.6, 0.7],
	"revive":         [["clothBelt", "clothBelt2"], 0.0, 0.9, 1.0],
	"breach":         [_n("impactBell_heavy_%03d", 0, 5), -4.0, 0.7, 0.75],
	# Off-screen trouble (HUD pointer): the breach bell, higher and lighter
	"alert":          [_n("impactBell_heavy_%03d", 0, 5), -10.0, 1.25, 1.3],
	# Ram's horn (Neh. 4:20), synthesized in-house — heard across the whole site
	"horn":           [_n("horn_%03d", 0, 3), -3.0, 0.97, 1.03],
	# Dusk tally: a light tap as each number starts counting, a wooden knock as it lands
	"tally":          [_n("impactGeneric_light_%03d", 0, 5), -10.0, 1.3, 1.45],
	"tally_land":     [_n("impactWood_medium_%03d", 0, 5), -7.0, 1.05, 1.2],
}
# Per-clip gain (dB) levelling the source files to ~-14 dB peak RMS, so variants of one
# event match and the quiet cloth/leather pack sits with the impacts. Measured by
# tools/audio_audit.py — rerun it after swapping a clip.
const TRIM := {
	"footstep00": -1.0, "footstep01": -1.5, "footstep02": 3.5, "footstep03": 2.5, "footstep04": 7.0,
	"footstep05": 2.0, "footstep06": -3.0, "footstep07": 0.0, "footstep08": -6.5, "footstep09": 5.0,
	"cloth1": 7.5, "cloth2": 13.0, "cloth3": 13.0, "cloth4": 18.0,
	"clothBelt": 16.5, "clothBelt2": 15.0,
	"handleSmallLeather": 18.5, "handleSmallLeather2": 24.0,
}
# Loud enough to put the birds up (Birds): event → reach in metres, 0 = the whole site
const STARTLES := {
	"sword": 3.5, "dash": 3.0, "shatter": 4.5, "sling_miss": 3.0, "wall_crumble": 8.0,
	"enemy_die": 4.0, "downed": 4.0, "horn": 0.0, "breach": 0.0, "sling_crack": 3.0,
}
# UI-level (non-positional) music stings
var _jingle_defs := {
	"day_start": ["jingles_PIZZI00"],
	"day_done":  ["jingles_PIZZI04"],
	"won":       ["jingles_PIZZI10"],
	"lost":      ["jingles_PIZZI08"],
}

# Background music — two moods, crossfaded by day phase (Overcooked-style lift when
# the work starts). Chosen to feel ancient and dignified: plucked strings over a drone
# at rest; a steady, warm pulse while building. No vocals, no battle anthems.
const MUSIC := "res://assets/audio/music/"
const MUSIC_FADE := 2.5
const MUSIC_BASE_DB := -6.0     # sits under the effects
const DUCK_DB := -10.0          # while a jingle plays
# mood: [[file, volume_db], …] — each time a mood comes back it picks another track,
# so 52 days don't wear one loop thin. alkakrab/ is gitignored (its license bars
# redistribution in a public repo): a clean checkout just has fewer tracks.
var _music_defs := {
	"calm": [
		["calm_caravan", 0.0],                        # "Desert theme" by yd — CC0
		["alkakrab/calm_dunes_of_silence", 0.0],      # AlkaKrab, Desert Fantasy Ambient
		["alkakrab/calm_canyon_echoes", 0.0],
		["alkakrab/calm_sunblade_horizon", 0.0],
	],
	"work": [
		["work_desert_of_dreams", -2.0],              # "Caryil, The Desert of Dreams" by insydnis — CC-BY 3.0
		["alkakrab/work_ash_and_oasis", 0.0],
		["alkakrab/work_scorchlight_mirage", 0.0],
		["alkakrab/work_whispers_in_the_sand", 0.0],
	],
}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_mood := ""
var _music_last := {}   # mood → index last played, so a mood never repeats back to back
var _music_tween: Tween
var _duck_tween: Tween

var _streams := {}      # name → Array[AudioStream]
var _last_played := {}  # name → msec
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _flat: AudioStreamPlayer
var _jingle: AudioStreamPlayer
var _listener: AudioListener3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for event: String in _defs:
		_streams[event] = _defs[event][0].map(func(f): return load(SFX + f + ".ogg"))
	for event: String in _jingle_defs:
		_streams[event] = _jingle_defs[event].map(func(f): return load(JINGLES + f + ".ogg"))
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = UNIT_SIZE
		p.max_distance = MAX_DISTANCE
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	# SFX bus is created by Settings (loaded after us); players resolve it by name at play time
	_flat = AudioStreamPlayer.new()
	_flat.bus = "SFX"
	add_child(_flat)
	_jingle = AudioStreamPlayer.new()
	_jingle.bus = "SFX"
	_jingle.volume_db = 0.0     # a short pluck; any lower and a deposit thud covers it
	add_child(_jingle)
	_listener = AudioListener3D.new()
	add_child(_listener)
	for mood: String in _music_defs:
		var tracks := []   # [stream, volume_db]
		for def: Array in _music_defs[mood]:
			var path: String = MUSIC + def[0] + ".ogg"
			if not ResourceLoader.exists(path):
				continue
			var s: AudioStreamOggVorbis = load(path)
			s.loop = true
			tracks.append([s, def[1]])
		_streams["music_" + mood] = tracks
	_music_a = _music_player()
	_music_b = _music_player()
	GameState.phase_changed.connect(_on_phase)
	# Deferred: Settings (loaded after us) creates the Music bus in its _ready
	play_music.call_deferred("calm")
	GameState.breaches_changed.connect(func(n: int): if n > 0 and not GameState.attract: play("breach"))

# Let go of streams (and live playbacks) so shutdown doesn't report them leaked
func _exit_tree() -> void:
	for p in _pool:
		p.stop()
		p.stream = null
	_flat.stream = null
	_jingle.stream = null
	for p in [_music_a, _music_b]:
		p.stop()
		p.stream = null
	_streams.clear()

# Hear the world from the local player's spot (the ortho camera sits ~35 m away),
# oriented like the camera so left/right panning matches the screen
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	if Player.local != null:
		at = Player.local.global_position + Vector3.UP * 2.0
	_listener.global_transform = Transform3D(cam.global_basis, at)
	if not _listener.is_current():
		_listener.make_current()

## Positional when `at` is given, otherwise straight to the mix. `pitch_mul` scales the
## event's own pitch range (the sling's whirl rises as it speeds up)
func play(event: String, at: Variant = null, pitch_mul := 1.0) -> void:
	var streams: Array = _streams.get(event, [])
	if streams.is_empty():
		push_warning("Sfx: unknown event '%s'" % event)
		return
	var now := Time.get_ticks_msec()
	if now - _last_played.get(event, -100000) < MIN_GAP * 1000.0:
		return
	_last_played[event] = now
	if STARTLES.has(event):
		get_tree().call_group("bird_set", "startle", at, STARTLES[event])
	var def: Array = _defs[event]
	var stream: AudioStream = streams.pick_random()
	var pitch := randf_range(def[2], def[3]) * pitch_mul
	var db: float = def[1] + TRIM.get(stream.resource_path.get_file().get_basename(), 0.0)
	if at is Vector3:
		var p := _pool[_next]
		_next = (_next + 1) % POOL_SIZE
		p.stream = stream
		p.volume_db = db
		p.pitch_scale = pitch
		p.global_position = at
		p.play()
	else:
		_flat.stream = stream
		_flat.volume_db = db
		_flat.pitch_scale = pitch
		_flat.play()

func play_jingle(event: String) -> void:
	var streams: Array = _streams.get(event, [])
	if streams.is_empty():
		return
	_jingle.stream = streams.pick_random()
	_jingle.play()
	# Duck the music under the sting, then bring it back
	if _duck_tween:
		_duck_tween.kill()
	var bus := AudioServer.get_bus_index("Music")
	if bus == -1:
		return
	var length := _jingle.stream.get_length()
	_duck_tween = create_tween()
	_duck_tween.tween_method(func(db: float): AudioServer.set_bus_volume_db(bus, _music_bus_db() + db), 0.0, DUCK_DB, 0.3)
	_duck_tween.tween_interval(maxf(length - 0.3, 0.2))
	_duck_tween.tween_method(func(db: float): AudioServer.set_bus_volume_db(bus, _music_bus_db() + db), DUCK_DB, 0.0, 1.5)

func _on_phase(phase: int) -> void:
	if GameState.attract:
		return  # the title screen keeps its own music; the world behind it stays hushed
	match phase:
		GameState.Phase.DAWN:
			play_jingle("day_start")
			play_music("calm")
		GameState.Phase.WORK:
			play_music("calm" if GameState.festival else "work")   # a feast day, not a work day
		GameState.Phase.DUSK:
			play_jingle("day_done")
			play_music("calm")
		GameState.Phase.GATHER, GameState.Phase.STORY:
			play_music("calm")
		GameState.Phase.WON:
			play_jingle("won")
			play_music("")
		GameState.Phase.LOST:
			play_jingle("lost")
			play_music("")

# ── Music ──────────────────────────────────────────────────

## Crossfade to a mood ("" = silence). Same mood again is a no-op — it keeps looping.
func play_music(mood: String) -> void:
	if mood == _music_mood:
		return
	_music_mood = mood
	# The quieter of the two players is the one we fade in on
	var incoming := _music_a if _music_a.volume_db < _music_b.volume_db else _music_b
	var outgoing := _music_b if incoming == _music_a else _music_a
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel()
	var tracks: Array = _streams.get("music_" + mood, [])
	if not tracks.is_empty():
		var i := randi() % tracks.size()
		if tracks.size() > 1 and i == _music_last.get(mood, -1):
			i = (i + 1) % tracks.size()
		_music_last[mood] = i
		incoming.stream = tracks[i][0]
		incoming.volume_db = -60.0
		incoming.play()
		_music_tween.tween_property(incoming, "volume_db", MUSIC_BASE_DB + tracks[i][1], MUSIC_FADE)
	_music_tween.tween_property(outgoing, "volume_db", -60.0, MUSIC_FADE)
	_music_tween.chain().tween_callback(outgoing.stop)

func _music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -60.0
	add_child(p)
	return p

func _music_bus_db() -> float:
	return linear_to_db(maxf(Settings.music_volume, 0.0001))

# "footstep0%d", 0, 10 → footstep00 … footstep09
static func _n(pattern: String, from: int, to: int) -> Array:
	var out := []
	for i in range(from, to):
		out.append(pattern % i)
	return out
