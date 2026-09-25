extends SceneTree

# Regenerates the project GUI theme from UiStyle tokens:
#   Godot --headless --path . --script res://tools/build_theme.gd
# Don't hand-edit assets/ui/theme.tres — it is overwritten here.

const OUT := "res://assets/ui/theme.tres"

func _initialize() -> void:
	var err := ResourceSaver.save(UiStyle.build_theme(), OUT)
	print("theme → ", OUT, " (err %d)" % err)
	quit(err)
