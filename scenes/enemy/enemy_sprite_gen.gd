class_name EnemySpriteGen
extends RefCounted

## Generates an 8-direction idle + walk SpriteFrames for enemies at runtime.
## Cached per armor color so each variant only pays the generation cost once.

const SIZE  := 32
const DIRS: Dictionary = {
	"down":       Vector2( 0.000,  1.000),
	"down_right": Vector2( 0.707,  0.707),
	"right":      Vector2( 1.000,  0.000),
	"up_right":   Vector2( 0.707, -0.707),
	"up":         Vector2( 0.000, -1.000),
	"up_left":    Vector2(-0.707, -0.707),
	"left":       Vector2(-1.000,  0.000),
	"down_left":  Vector2(-0.707,  0.707),
}

static var _cache: Dictionary = {}

static func get_frames(armor_color: Color) -> SpriteFrames:
	var key := armor_color.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var frames := _build(armor_color)
	_cache[key] = frames
	return frames

# ── Build ─────────────────────────────────────────────────────────────────────

static func _build(armor: Color) -> SpriteFrames:
	var frames   := SpriteFrames.new()
	var bobs     := [0, -2, 0, -1]   # walk bob y offsets
	for dir in DIRS:
		var v: Vector2 = DIRS[dir]
		_add(frames, "idle_" + dir, [_frame(armor, v, 0), _frame(armor, v, -1)], 3.0)
		_add(frames, "walk_" + dir,
			[_frame(armor, v, bobs[0]), _frame(armor, v, bobs[1]),
			 _frame(armor, v, bobs[2]), _frame(armor, v, bobs[3])], 8.0)
	return frames

static func _add(f: SpriteFrames, anim: String, textures: Array, spd: float) -> void:
	f.add_animation(anim)
	f.set_animation_loop(anim, true)
	f.set_animation_speed(anim, spd)
	for i in textures.size():
		f.add_frame(anim, textures[i], i)

# ── Frame rendering ───────────────────────────────────────────────────────────
# Canvas: 32×32  cx=16
# Y layout (bob=0):
#   shadow  cy=30 rx=7 ry=1
#   legs    y=20–28  (two columns, gap at cx)
#   armor   y=10–21  (trapezoid)
#   head    cy=7  r=5
#   helmet  top half of head + 1px brim

static func _frame(armor: Color, facing: Vector2, bob: int) -> ImageTexture:
	var img  := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var cx   := SIZE / 2  # 16

	var skin     := Color(0.65, 0.50, 0.34)
	var armor_hi := armor.lightened(0.22)
	var armor_dk := armor.darkened(0.38)
	var bronze   := Color(0.48, 0.34, 0.10)
	var bronze_hi:= Color(0.66, 0.50, 0.20)

	# Ground shadow
	_ellipse(img, cx, 30 + bob, 7, 1, Color(0, 0, 0, 0.38))

	# Legs — two armored columns
	for y in range(20 + bob, 29 + bob):
		if y < 0 or y >= SIZE: continue
		for x in range(cx - 8, cx - 1):   # left leg
			if x >= 0 and x < SIZE: img.set_pixel(x, y, armor_dk)
		for x in range(cx + 1, cx + 8):   # right leg
			if x >= 0 and x < SIZE: img.set_pixel(x, y, armor_dk)

	# Body armor (trapezoid — broad shoulders, slight taper)
	for y in range(10 + bob, 22 + bob):
		if y < 0 or y >= SIZE: continue
		var t  := float(y - (10 + bob)) / 12.0
		var hw := int(lerp(9.0, 6.0, t))
		for x in range(cx - hw, cx + hw + 1):
			if x < 0 or x >= SIZE: continue
			var col := armor_hi if abs(x - cx) <= 1 else armor
			img.set_pixel(x, y, col)

	# Head (skin, direction-offset so facing reads clearly)
	var hx := cx + int(facing.x * 2)
	var hy := 7  + bob
	_circle(img, hx, hy, 5, skin)

	# Helmet — bronze cap over top ~55% of head circle
	for y in range(hy - 5, hy + 1):
		if y < 0 or y >= SIZE: continue
		for x in range(hx - 5, hx + 6):
			if x < 0 or x >= SIZE: continue
			if (x - hx) * (x - hx) + (y - hy) * (y - hy) <= 25 and y <= hy:
				img.set_pixel(x, y, bronze)
	# Brim (1px, slightly wider)
	for x in range(hx - 6, hx + 7):
		var brim_y := hy + 1
		if x >= 0 and x < SIZE and brim_y >= 0 and brim_y < SIZE:
			img.set_pixel(x, brim_y, bronze)
	# Crest ridge down helmet centre
	for y in range(hy - 5, hy + 1):
		var rx := clampi(hx, 0, SIZE - 1)
		if y >= 0 and y < SIZE: img.set_pixel(rx, y, bronze_hi)

	# Face direction dot (lower face area, offset toward facing)
	_circle(img,
		clamp(hx + int(facing.x * 3), 0, SIZE - 1),
		clamp(hy + 3 + int(facing.y * 2), 0, SIZE - 1),
		1, skin.lightened(0.18))

	return ImageTexture.create_from_image(img)

# ── Pixel helpers ─────────────────────────────────────────────────────────────

static func _circle(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or x >= SIZE or y < 0 or y >= SIZE: continue
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				img.set_pixel(x, y, c)

static func _ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			if x < 0 or x >= SIZE or y < 0 or y >= SIZE: continue
			var nx := float(x - cx) / rx
			var ny := float(y - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(c))
