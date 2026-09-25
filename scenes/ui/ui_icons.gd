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
	check    = '<path d="M5 12.5l4.5 4.5L19 7.5" stroke="#FFF" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
	# Touch actions
	sling    = '<circle cx="16.5" cy="7.5" r="3.4" fill="#FFF"/><path d="M3.5 20.5C5 14 8.5 10.5 12.5 9" stroke="#FFF" stroke-width="2" fill="none" stroke-linecap="round" stroke-dasharray="0.1 3.6"/>',
	carry    = '<rect x="6" y="3.5" width="12" height="9.5" rx="1.2" fill="#FFF"/><path d="M3 16.5h4.5l2 2h5l2-2H21" stroke="#FFF" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
	dash     = '<path d="M5 6l6 6-6 6M12.5 6l6 6-6 6" stroke="#FFF" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
	drop     = '<path d="M12 3.5v11M7 10l5 5 5-5M5 20.5h14" stroke="#FFF" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
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
