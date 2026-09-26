class_name CharAnim

# Animation timing shared by every CharacterRig, plus the 4-way facing used in the
# "<anim>_<dir>" names. Timings date from the LPC sprite sheets and gameplay beats
# (sling release frame, build strike, footfalls) are tuned to them, so keep the
# frame counts when changing the look of an animation.

const DIRS := ["up", "left", "down", "right"]

# cycle: frame indices (only the count matters to the rig), fps, loop
const ANIM_CFG: Dictionary = {
	"idle":      { "cycle": [0, 0, 0, 1],             "loop": true,  "fps": 4.0  },
	"walk":      { "cycle": [1, 2, 3, 4, 5, 6, 7, 8], "loop": true,  "fps": 10.0 },
	"run":       { "cycle": [0, 1, 2, 3, 4, 5, 6, 7], "loop": true,  "fps": 13.0 },
	"thrust":    { "cycle": [0, 1, 2, 3, 4, 5, 6, 7], "loop": false, "fps": 16.0 },
	"slash":     { "cycle": [0, 1, 2, 3, 4, 5],       "loop": false, "fps": 16.0 },
	# Sling wind-up: arm up, rocking while the sling whirls
	"windup":    { "cycle": [0, 1],                   "loop": true,  "fps": 5.0  },
	"halfslash": { "cycle": [0, 1, 2, 3, 4, 5],       "loop": false, "fps": 16.0 },
	# Working at the wall: overhand mallet swing on a loop, strike on frame 4
	"build":     { "cycle": [0, 1, 2, 3, 4, 5, 5, 0], "loop": true,  "fps": 12.0 },
	# Downed / death: fall to the ground and stay
	"collapse":  { "cycle": [0, 1, 2, 3, 4, 5],       "loop": false, "fps": 10.0 },
	# Day's work done: two hops with both arms thrown up
	"cheer":     { "cycle": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], "loop": false, "fps": 10.0 },
}

## Map a 3D velocity vector to a facing using the isometric camera axes.
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
