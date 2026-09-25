class_name LPCFrames

# LPC Universal Generator sheet constants (64px frames, 13 cols wide)
const FRAME_SZ := 64

# Direction row offsets within each animation block (matches generator DIRECTIONS order)
const DIRS := ["up", "left", "down", "right"]

# Animation config: base row, frame cycle (column indices), loop, fps, direction count.
# Rows follow the generator's standard sheet layout.
const ANIM_CFG: Dictionary = {
	"idle":      { "row": 22, "cycle": [0, 0, 0, 1],             "loop": true,  "fps": 4.0,  "dirs": 4 },
	"walk":      { "row": 8,  "cycle": [1, 2, 3, 4, 5, 6, 7, 8], "loop": true,  "fps": 10.0, "dirs": 4 },
	"run":       { "row": 38, "cycle": [0, 1, 2, 3, 4, 5, 6, 7], "loop": true,  "fps": 13.0, "dirs": 4 },
	"thrust":    { "row": 4,  "cycle": [0, 1, 2, 3, 4, 5, 6, 7], "loop": false, "fps": 16.0, "dirs": 4 },
	"slash":     { "row": 12, "cycle": [0, 1, 2, 3, 4, 5],       "loop": false, "fps": 16.0, "dirs": 4 },
	"halfslash": { "row": 50, "cycle": [0, 1, 2, 3, 4, 5],       "loop": false, "fps": 16.0, "dirs": 4 },
	# Row 20 is the generator's "hurt" — a full collapse to the ground. Used for downed/death.
	"collapse":  { "row": 20, "cycle": [0, 1, 2, 3, 4, 5],       "loop": false, "fps": 10.0, "dirs": 1 },
}

# SpriteFrames are identical for every instance of a sheet — build once, share.
static var _cache: Dictionary = {}

## Build (or fetch cached) SpriteFrames from an LPC sprite sheet texture.
## Pass anims=[] to include all, or a subset e.g. ["walk","idle"].
static func build(tex: Texture2D, anims: Array = []) -> SpriteFrames:
	var keys: Array = anims if not anims.is_empty() else ANIM_CFG.keys()
	var cache_key := "%s|%s" % [tex.resource_path, ",".join(keys)]
	if _cache.has(cache_key):
		return _cache[cache_key]

	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim: String in keys:
		if not ANIM_CFG.has(anim):
			continue
		var cfg: Dictionary = ANIM_CFG[anim]
		var dir_count: int = cfg["dirs"]

		for d in range(dir_count):
			var full_name: String = anim + ("_" + DIRS[d] if dir_count > 1 else "")
			sf.add_animation(full_name)
			sf.set_animation_speed(full_name, cfg["fps"])
			sf.set_animation_loop(full_name, cfg["loop"])

			for f: int in cfg["cycle"]:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(f * FRAME_SZ, (cfg["row"] + d) * FRAME_SZ, FRAME_SZ, FRAME_SZ)
				sf.add_frame(full_name, at)

	_cache[cache_key] = sf
	return sf

## Map a 3D velocity vector to an LPC direction string using the isometric camera axes.
## Returns current_dir unchanged when velocity is negligible (preserves facing).
static func dir_from_velocity(vel: Vector3, current_dir: String) -> String:
	if vel.length_squared() < 0.01:
		return current_dir
	var flat := Vector3(vel.x, 0.0, vel.z).normalized()
	# Isometric north = (-1,0,-1), east = (1,0,-1) — matches camera orientation
	var dn := flat.dot(Vector3(-0.707, 0.0, -0.707))
	var de := flat.dot(Vector3( 0.707, 0.0, -0.707))
	if absf(dn) >= absf(de):
		return "up" if dn > 0.0 else "down"
	return "right" if de > 0.0 else "left"
