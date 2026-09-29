class_name UiIcons
extends RefCounted

# Inline SVG icons (24×24 grid, 2-unit strokes) rasterised on demand at the
# screen's real pixel density, so they stay crisp under the phone UI scale.

const _PATHS := {
	pause    = '<rect x="6" y="5" width="4" height="14" rx="1" fill="#FFF"/><rect x="14" y="5" width="4" height="14" rx="1" fill="#FFF"/>',
	tune     = '<path d="M4 7h9M19 7h1M4 17h3M13 17h7" stroke="#FFF" stroke-width="2" stroke-linecap="round"/><circle cx="16" cy="7" r="2.6" stroke="#FFF" stroke-width="2" fill="none"/><circle cx="10" cy="17" r="2.6" stroke="#FFF" stroke-width="2" fill="none"/>',
	back     = '<path d="M20 12H5M11 5.5 4.5 12l6.5 6.5" stroke="#FFF" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
	close    = '<path d="M6 6l12 12M18 6 6 18" stroke="#FFF" stroke-width="2.2" stroke-linecap="round"/>',
	backspace = '<path d="M9 5h10.5A1.5 1.5 0 0 1 21 6.5v11a1.5 1.5 0 0 1-1.5 1.5H9l-6-7z" stroke="#FFF" stroke-width="2" fill="none" stroke-linejoin="round"/><path d="M11.5 9.5l5 5M16.5 9.5l-5 5" stroke="#FFF" stroke-width="2" stroke-linecap="round"/>',
	copy     = '<rect x="8.5" y="8.5" width="11" height="12" rx="1.5" stroke="#FFF" stroke-width="2" fill="none"/><path d="M5.5 15.5V5a1.5 1.5 0 0 1 1.5-1.5h8.5" stroke="#FFF" stroke-width="2" fill="none" stroke-linecap="round"/>',
	# Folded map (the section picker)
	map      = '<path d="M3 6.5 9 4l6 2.5L21 4v13.5L15 20l-6-2.5L3 20z" stroke="#FFF" stroke-width="2" fill="none" stroke-linejoin="round"/><path d="M9 4v13.5M15 6.5V20" stroke="#FFF" stroke-width="2"/>',
	# Two figures, head and shoulders (Friends and Foes)
	people   = '<circle cx="9" cy="8" r="3.4" stroke="#FFF" stroke-width="2" fill="none"/><path d="M2.5 20c.5-3.7 3.2-6 6.5-6s6 2.3 6.5 6" stroke="#FFF" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M15.5 4.9a3.2 3.2 0 0 1 0 6.2M18 14.5c1.9.8 3.2 2.8 3.5 5.5" stroke="#FFF" stroke-width="2" fill="none" stroke-linecap="round"/>',
	check    ='<path d="M5 12.5l4.5 4.5L19 7.5" stroke="#FFF" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
	# Touch actions
	# A slung stone in flight, speed lines trailing it
	sling    = '<circle cx="16" cy="8" r="4.6" fill="#FFF"/><path d="M3.5 20.5l7-7M2.5 14l4.5-4.5M10 21.5l4.5-4.5" stroke="#FFF" stroke-width="2.4" stroke-linecap="round"/>',
	# Two dressed stones on cupped hands (pick up · deliver · build)
	carry    = '<path fill="#FFF" fill-rule="evenodd" d="M6.5 3.5h11a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1zM5.5 8h13v1.4h-13zM11.3 3.5h1.4v4.5h-1.4z"/><path d="M2.5 13.5 7 17.5h10l4.5-4M7 17.5v3M17 17.5v3" stroke="#FFF" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
	# A bold arrow with speed lines trailing it
	dash     = '<path d="M11.2 4.6 18.6 12l-7.4 7.4-2.4-2.4 5-5-5-5z" fill="#FFF" stroke="#FFF" stroke-width="1" stroke-linejoin="round"/><path d="M2.5 8h5M1.5 12h8M2.5 16h5" stroke="#FFF" stroke-width="2.2" stroke-linecap="round"/>',
	# A stone falling to the ground
	drop     = '<rect x="8" y="2.5" width="8" height="6.5" rx="1" fill="#FFF"/><path d="M12 11.5v5.5M9 14.5l3 3 3-3M4.5 21h15" stroke="#FFF" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
	# Shofar: a ram's horn curling up from the mouthpiece to a flared bell
	horn     = '<path d="M4 18.5c3.5 1 8 .2 11-3.3 1.6-1.9 2.5-4.3 2.6-7" stroke="#FFF" stroke-width="2.4" fill="none" stroke-linecap="round"/><path d="M14.8 6.8 17.6 3l3.4 3.6z" fill="#FFF" stroke="#FFF" stroke-width="1.6" stroke-linejoin="round"/>',
}

static var _cache := {}

## White icon at `size` UI units; tint with modulate / Button icon colours
static func get_icon(name: String, size := 24.0) -> Texture2D:
	var px := maxi(roundi(size * density()), 8)
	var key := "%s@%d" % [name, px]
	if _cache.has(key):
		return _cache[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">%s</svg>' % _PATHS[name]
	var img := Image.new()
	img.load_svg_from_string(svg, px / 24.0)
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(roundi(size), roundi(size)))
	_cache[key] = tex
	return tex

static func density() -> float:
	var ml := Engine.get_main_loop() as SceneTree
	if ml and ml.root.has_node("Mobile"):
		return maxf(ml.root.get_node("Mobile").ui_scale, 1.0)
	return 1.0

## Square icon-only button (48×48 touch target by default)
static func button(name: String, tip := "", size := 48.0, variation := &"IconButton") -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	b.icon = get_icon(name, 24.0)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.custom_minimum_size = Vector2(size, size)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	return b
