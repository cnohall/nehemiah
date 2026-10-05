extends Node

# Player preferences — persisted to user://settings.cfg and applied at boot.
# UI edits a field, then calls apply() + save().

const PATH := "user://settings.cfg"

var fullscreen := false
var vsync := true
# 3D render resolution as a fraction of the window (the UI stays at full resolution), and
# a graphics preset: index into QUALITIES. Defaults are lower on web / mobile.
var render_scale := 1.0
var quality := 2
# True until the player picks a scale: a sustained low frame rate then steps it down
var auto_scale := true
# Windowed size picked by the player (WINDOW_SIZES), or ZERO to leave the window as the game opens it
var window_size := Vector2i.ZERO
var _sized := Vector2i.ZERO        # the size last applied, so a hand-dragged window is left alone
var _mode_pending := false         # a fullscreen / windowed change is still being confirmed
var volume := 0.8   # master bus, linear 0..1
var music_volume := 0.6   # Music bus (created here), linear 0..1
var sfx_volume := 0.8     # SFX bus (created here) — effects + jingles, linear 0..1
var screen_shake := true
# Drawn look over the world, on trial with playtesters: index into ART_STYLES (LookPass)
signal art_style_changed
const ART_STYLES := ["Standard", "Lithograph", "Cel"]
var art_style := 0:
	set(v):
		if v != art_style:
			art_style = v
			art_style_changed.emit()
# Day, progress and threats told by the world (sun, scribe, watchmen) — false brings
# back the day plaque and the threat plaque
var diegetic_hud := true
# Camera holds the whole stretch in view (Overcooked-style) instead of following you
var fixed_camera := false
# Turn the view on every stretch so north sits up-screen, the wall lying as it does on the
# map (as Explore Jerusalem does) — off keeps the game's one view, outside always far
var turn_to_map := false
var rumble := true
var toggle_charge := false   # sling: press to start, press again to throw (instead of hold)
# Keyboard / mouse rebinds: action → {"key": physical keycode} or {"mouse": button index}.
# Only an action's primary key / mouse event is rebindable; pad remaps go through Steam Input.
var bindings := {}
# UI language: a locale from LANGUAGES, or "" to follow the OS / browser
var language := ""
# Bots on the host's crew (BotBrain): how many fill the empty places, and how good they are
var bot_count := 0
var bot_skill := 1   # index into BotBrain.SKILLS
# How hard the enemy presses (host's choice; only the server reads it): index into DIFFICULTIES
var difficulty := 1
# This player's trade (Trade), or -1 for their place in the crew's own
var trade := -1
# Experimental (GDD §5.21), off by default; the host's choice rules the crew like difficulty
var exp_forecast := false    # wave forecast: how many and what, ~22 s ahead, spot ringed on the ground
var exp_call_early := false  # [Horn] brings the next wave forward for a short work boost

# pace: multiplies enemy numbers and spawn rate (on top of each section's pressure)
# harm: multiplies every enemy blow, on workers and on the wall
const DIFFICULTIES := [
	{ "name": "Gentle",   "pace": 0.7, "harm": 0.7,  "about": "Fewer enemies, lighter blows" },
	{ "name": "Standard", "pace": 1.0, "harm": 1.0,  "about": "The wall as it was built" },
	{ "name": "Hard",     "pace": 1.3, "harm": 1.25, "about": "More enemies, heavier blows" },
]

const RENDER_SCALES := [0.5, 0.67, 0.75, 1.0]
const WINDOW_SIZES := [Vector2i(1024, 768), Vector2i(1280, 720), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440)]

# Bundled costs: shadow atlas, soft-shadow filter, SSAO, MSAA. Index 2 is the look the
# game is tuned on (project.godot values).
const QUALITIES := [
	{ "name": "Low",    "shadow": 2048, "soft": 1, "ssao": 0, "msaa": Viewport.MSAA_DISABLED },
	{ "name": "Medium", "shadow": 4096, "soft": 2, "ssao": 1, "msaa": Viewport.MSAA_2X },
	{ "name": "High",   "shadow": 8192, "soft": 3, "ssao": 2, "msaa": Viewport.MSAA_2X },
]

# Auto step-down: this many seconds under LOW_FPS before the scale drops one notch
const LOW_FPS := 40.0
const LOW_FPS_SECS := 10.0
var _low_time := 0.0
var _gfx_applied := []

# Shipped translations (locale/*.po; the English text is the key), in picker order.
# Names are written in their own language so anyone can find theirs.
const LANGUAGES := [
	["en", "English"], ["es", "Español"], ["pt_BR", "Português (Brasil)"],
	["de", "Deutsch"], ["ko", "한국어"],
]
# Cinzel and Spectral have no Hangul: these subsets (tools/i18n/subset_kr_font.py)
# stand behind every UI font. Desktop could fall back to a system font, the web can't.
const KR_REGULAR := "res://assets/fonts/NotoSerifKR/NotoSerifKR-Medium-subset.ttf"
const KR_BOLD    := "res://assets/fonts/NotoSerifKR/NotoSerifKR-Bold-subset.ttf"

const REBINDABLE := ["move_north", "move_west", "move_south", "move_east",
	"interact", "drop", "dash", "throw_charge", "horn", "reveal"]

func _ready() -> void:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		render_scale = 0.75
		# Phones: Low (2048 shadows, no MSAA) — Medium's 4096 atlas costs a tile GPU dearly
		quality = 0 if OS.has_feature("mobile") else 1
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
		vsync      = cfg.get_value("display", "vsync", vsync)
		render_scale = clampf(cfg.get_value("display", "render_scale", render_scale), RENDER_SCALES[0], 1.0)
		quality    = clampi(cfg.get_value("display", "quality", quality), 0, QUALITIES.size() - 1)
		auto_scale = cfg.get_value("display", "auto_scale", auto_scale)
		window_size = Vector2i(cfg.get_value("display", "window_w", 0), cfg.get_value("display", "window_h", 0))
		volume    = cfg.get_value("audio", "volume", volume)
		music_volume = cfg.get_value("audio", "music_volume", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
		screen_shake = cfg.get_value("display", "screen_shake", screen_shake)
		art_style = clampi(cfg.get_value("display", "art_style", art_style), 0, ART_STYLES.size() - 1)
		diegetic_hud = cfg.get_value("display", "diegetic_hud", diegetic_hud)
		fixed_camera = cfg.get_value("display", "fixed_camera", fixed_camera)
		turn_to_map = cfg.get_value("display", "turn_to_map", turn_to_map)
		rumble = cfg.get_value("controls", "rumble", rumble)
		toggle_charge = cfg.get_value("controls", "toggle_charge", toggle_charge)
		bindings = cfg.get_value("controls", "bindings", bindings)
		language = cfg.get_value("general", "language", language)
		bot_count = cfg.get_value("bots", "count", bot_count)
		bot_skill = cfg.get_value("bots", "skill", bot_skill)
		difficulty = clampi(cfg.get_value("general", "difficulty", difficulty), 0, DIFFICULTIES.size() - 1)
		trade = clampi(cfg.get_value("general", "trade", trade), -1, CharacterRig.TRADES.size() - 1)
		exp_forecast = cfg.get_value("experimental", "forecast", exp_forecast)
		exp_call_early = cfg.get_value("experimental", "call_early", exp_call_early)
	_apply_bindings()
	_add_font_fallbacks()
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var bus := AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, bus_name)
			AudioServer.set_bus_send(bus, "Master")
	apply()
	get_tree().root.size_changed.connect(_fit_ui)
	get_tree().root.size_changed.connect(_sync_mode)
	_fit_ui()

# canvas_items stretch shrinks the UI with the window: at 1280×800 (Steam Deck) body
# text came out ~11 px. Below ~0.85 of the 1080p layout, scale the 2D back up so text
# stays readable; the 3D view is unaffected.
const UI_MIN_SCALE := 0.85
const UI_MAX_BOOST := 1.35

func _fit_ui() -> void:
	var win := get_tree().root
	if Mobile.enabled():
		# Phones size the UI in dp (Mobile); a boost on top would outgrow a 720p screen
		win.content_scale_factor = 1.0
		return
	var s := minf(win.size.x / 1920.0, win.size.y / 1080.0)
	win.content_scale_factor = clampf(UI_MIN_SCALE / s, 1.0, UI_MAX_BOOST) if s > 0.0 else 1.0

func apply() -> void:
	TranslationServer.set_locale(language if not language.is_empty() else OS.get_locale())
	# Embedded/headless runs have no real window to resize
	if OS.has_feature("mobile"):
		# Fullscreen = immersive on Android (system bars hidden); no vsync choice
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.get_name() != "headless":
		if can_change_window() and not Mobile.enabled():   # --touch preview keeps its --resolution
			_apply_window()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync
			else DisplayServer.VSYNC_DISABLED)
	_apply_graphics()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.0)
	var music := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(music, linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_mute(music, music_volume <= 0.0)
	var sfx := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_mute(sfx, sfx_volume <= 0.0)

# ── Window ─────────────────────────────────────────────────

func _is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

## False while the game runs inside the editor's Game tab: the editor owns that window,
## so size and fullscreen requests go nowhere (the settings picker greys them out)
func can_change_window() -> bool:
	return not Engine.is_embedded_in_editor()

## Window sizes that fit the screen the window is on (a picker for windowed play)
func available_window_sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var room := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	for s: Vector2i in WINDOW_SIZES:
		if s.x <= room.x and s.y <= room.y:
			out.append(s)
	return out

# Touches the window only where it differs from what was asked: apply() runs on every
# slider tick and language change, and re-sending WINDOWED would un-maximize the window.
func _apply_window() -> void:
	if _is_fullscreen() != fullscreen:
		_mode_pending = true   # before the call: size_changed may fire inside it
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)
		_verify_window()
	elif not fullscreen and window_size != Vector2i.ZERO and window_size != _sized:
		_resize_window()

# The OS applies a mode change a moment later and can drop one that lands mid-click or
# while focus moves (overlay, alt-tab): look again shortly and ask once more.
func _verify_window() -> void:
	_mode_pending = true
	await get_tree().create_timer(0.35).timeout
	if _is_fullscreen() != fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)
		await get_tree().create_timer(0.35).timeout
	_mode_pending = false
	if not fullscreen and window_size != Vector2i.ZERO and window_size != _sized:
		_resize_window()
	_sync_mode()

## Something else changed the mode (OS shortcut, driver): follow it so the picker never lies
func _sync_mode() -> void:
	if _mode_pending or DisplayServer.get_name() == "headless" or not can_change_window():
		return
	if _is_fullscreen() != fullscreen:
		fullscreen = _is_fullscreen()

func _resize_window() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.window_get_current_screen()
	var room := DisplayServer.screen_get_usable_rect(screen)
	var size := Vector2i(mini(window_size.x, room.size.x), mini(window_size.y, room.size.y))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(room.position + (room.size - size) / 2)
	_sized = window_size

## The Compatibility renderer (web) ignores 3D scaling, so the picker is hidden there
func can_scale_3d() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"

func _apply_graphics() -> void:
	# apply() runs on every slider tick; resizing the shadow atlas each time would hitch
	var sig := [quality, render_scale]
	if sig == _gfx_applied:
		return
	_gfx_applied = sig
	var q: Dictionary = QUALITIES[clampi(quality, 0, QUALITIES.size() - 1)]
	var root := get_tree().root
	root.msaa_3d = q["msaa"]
	if can_scale_3d():
		root.scaling_3d_scale = render_scale
		# FSR1 sharpens an upscale; at full scale plain bilinear costs nothing
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if render_scale >= 1.0 \
			else Viewport.SCALING_3D_MODE_FSR
		root.texture_mipmap_bias = log(render_scale) / log(2.0)
	RenderingServer.directional_shadow_atlas_set_size(q["shadow"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(q["soft"])
	RenderingServer.environment_set_ssao_quality(q["ssao"], true, 0.5, 2, 50.0, 300.0)

func _process(delta: float) -> void:
	# Only while playing on a real window that has focus, and only until the player chooses
	if not auto_scale or not can_scale_3d() or DisplayServer.get_name() == "headless" \
			or not get_window().has_focus() or get_tree().paused:
		_low_time = 0.0
		return
	if Engine.get_frames_per_second() >= LOW_FPS:
		_low_time = 0.0
		return
	_low_time += delta
	if _low_time < LOW_FPS_SECS:
		return
	_low_time = 0.0
	for i in range(RENDER_SCALES.size() - 1, -1, -1):
		if RENDER_SCALES[i] < render_scale - 0.01:
			render_scale = RENDER_SCALES[i]
			apply()
			save()
			return
	auto_scale = false   # already at the floor

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "render_scale", render_scale)
	cfg.set_value("display", "quality", quality)
	cfg.set_value("display", "auto_scale", auto_scale)
	cfg.set_value("display", "window_w", window_size.x)
	cfg.set_value("display", "window_h", window_size.y)
	cfg.set_value("display", "screen_shake", screen_shake)
	cfg.set_value("display", "art_style", art_style)
	cfg.set_value("display", "diegetic_hud", diegetic_hud)
	cfg.set_value("display", "fixed_camera", fixed_camera)
	cfg.set_value("display", "turn_to_map", turn_to_map)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("controls", "rumble", rumble)
	cfg.set_value("controls", "toggle_charge", toggle_charge)
	cfg.set_value("controls", "bindings", bindings)
	cfg.set_value("general", "language", language)
	cfg.set_value("bots", "count", bot_count)
	cfg.set_value("bots", "skill", bot_skill)
	cfg.set_value("general", "difficulty", difficulty)
	cfg.set_value("general", "trade", trade)
	cfg.set_value("experimental", "forecast", exp_forecast)
	cfg.set_value("experimental", "call_early", exp_call_early)
	cfg.save(PATH)

## The chosen difficulty's row of DIFFICULTIES
func diff() -> Dictionary:
	return DIFFICULTIES[clampi(difficulty, 0, DIFFICULTIES.size() - 1)]

# ── Language ───────────────────────────────────────────────

## Locale actually in use, matched to a shipped one ("en" when nothing matches)
func current_language() -> String:
	var best := "en"
	var best_score := 0
	for row: Array in LANGUAGES:
		var score := TranslationServer.compare_locales(TranslationServer.get_locale(), row[0])
		if score > best_score:
			best = row[0]
			best_score = score
	return best

func _add_font_fallbacks() -> void:
	var regular := load(KR_REGULAR) as Font
	var bold := load(KR_BOLD) as Font
	if regular == null or bold == null:
		return
	var fonts: Array[Font] = [UiStyle.CINZEL, UiStyle.CINZEL_SEMI, UiStyle.CINZEL_BOLD, UiStyle.CINZEL_XBOLD,
		UiStyle.SPECTRAL, UiStyle.SPECTRAL_MEDIUM, UiStyle.SPECTRAL_ITALIC, UiStyle.WORLD_FONT, ThemeDB.fallback_font]
	var theme := ThemeDB.get_project_theme()
	if theme != null:
		if theme.default_font != null:
			fonts.append(theme.default_font)
		for type in theme.get_font_type_list():
			for font_name in theme.get_font_list(type):
				fonts.append(theme.get_font(font_name, type))
	for f: Font in fonts:
		# A variation shares its base font's fallbacks
		while f is FontVariation and (f as FontVariation).base_font != null:
			f = (f as FontVariation).base_font
		if f == null or f.fallbacks.has(regular) or f.fallbacks.has(bold):
			continue
		var heavy := f is FontFile and (f as FontFile).font_weight >= 600
		var fb := f.fallbacks
		fb.append(bold if heavy else regular)
		f.fallbacks = fb

# ── Bindings ───────────────────────────────────────────────

## First keyboard / mouse event on an action (what the hints show and rebinding replaces)
func primary_event(action: String) -> InputEvent:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			return e
	return null

## Put `event` on `action` as its primary. If another action already uses it, that
## action gets our old primary (a swap), so no binding is ever lost.
func rebind(action: String, event: InputEvent) -> void:
	var old := primary_event(action)
	for other: String in REBINDABLE:
		if other == action:
			continue
		for e in InputMap.action_get_events(other):
			if _same(e, event):
				if old != null and e == primary_event(other):
					_set_primary(other, old)
					bindings[other] = _encode(old)
				else:
					InputMap.action_erase_event(other, e)
	_set_primary(action, event)
	bindings[action] = _encode(event)
	save()

func reset_bindings() -> void:
	bindings.clear()
	# Only the rebindable actions; a full reload would drop the pad events InputMode adds
	for action: String in REBINDABLE:
		InputMap.action_erase_events(action)
		for e: InputEvent in ProjectSettings.get_setting("input/" + action)["events"]:
			InputMap.action_add_event(action, e)
	save()

func _apply_bindings() -> void:
	for action: String in bindings:
		if action in REBINDABLE:
			var e := _decode(bindings[action])
			if e != null:
				_set_primary(action, e)

func _set_primary(action: String, event: InputEvent) -> void:
	var events := InputMap.action_get_events(action)
	var old := primary_event(action)
	InputMap.action_erase_events(action)
	var placed := false
	for e in events:
		if e == old:
			InputMap.action_add_event(action, event)
			placed = true
		else:
			InputMap.action_add_event(action, e)
	if not placed:
		InputMap.action_add_event(action, event)

static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.physical_keycode == b.physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false

static func _encode(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		return {"key": e.physical_keycode}
	return {"mouse": e.button_index}

static func _decode(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = d["key"]
		return k
	if d.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = d["mouse"]
		return m
	return null
