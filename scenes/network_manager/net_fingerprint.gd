class_name NetFingerprint
extends RefCounted
## What two copies of the game must agree on to play together, as one md5.
##
## Godot numbers RPCs by their place in each script's sorted @rpc list, and replicates
## properties by their place in each synchronizer's config. Two builds whose lists differ
## still connect, then every call lands on the wrong method (8 Nov 2026: a stale build
## against a fresh one; pickups, sling stones and sword cuts vanished, the host ran in
## place). So peers swap this at connect (NetworkManager auth) and refuse a mismatch.
##
## Covered: every game script's RPCs (name, mode, arg count), its member variables
## (code-built synchronizers name them, see NetworkManager.add_sync), and the replication
## configs of the scenes in SYNCED_SCENES.

const ROOTS := ["res://scenes"]   # every game script and autoload lives here (tools/ doesn't ship)
## Scenes with a MultiplayerSynchronizer saved in them. Add any new one here.
const SYNCED_SCENES := [
	"res://scenes/player/player.tscn",
	"res://scenes/enemy/enemy.tscn",
	"res://scenes/messenger/messenger.tscn",
	"res://scenes/dropped_item/dropped_item.tscn",
]

static var _cached := ""
static var _keep: Array[Resource] = []   # the scripts read, kept loaded: the game wants them next

## Loads every game script (1.5 s or so), so NetworkManager asks when hosting or joining
## starts, in the menu, not when someone connects mid-game
static func get_hash() -> String:
	if _cached.is_empty():
		var text := describe()
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--net-salt="):   # tests: pose as another build
				text += a
		_cached = text.md5_text()
	return _cached

## The text that gets hashed, one line per fact (readable when two builds disagree)
static func describe() -> String:
	var lines := PackedStringArray()
	var paths: Array[String] = []
	for root: String in ROOTS:
		if DirAccess.dir_exists_absolute(root):
			_collect(root, paths)
	paths.sort()
	for path in paths:
		var s := load(path) as Script
		if s != null:
			_keep.append(s)
			_describe_script(path, s, lines)
	for path: String in SYNCED_SCENES:
		if ResourceLoader.exists(path):
			_describe_scene(path, lines)
	return "\n".join(lines)

static func _collect(dir: String, out: Array[String]) -> void:
	# list_directory sees through an export's remaps (.gd.remap / .gdc): names stay .gd
	for entry: String in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			_collect(dir.path_join(entry.trim_suffix("/")), out)
		elif entry.ends_with(".gd"):
			out.append(dir.path_join(entry))

static func _describe_script(path: String, s: Script, lines: PackedStringArray) -> void:
	var rpcs: Dictionary = s.get_rpc_config()
	var vars: Array[String] = []
	for p: Dictionary in s.get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			vars.append("%s:%d" % [p.name, p.type])
	if rpcs.is_empty() and vars.is_empty():
		return
	var args := {}
	for m: Dictionary in s.get_script_method_list():
		args[m.name] = m.args.size()
	var names: Array[String] = []
	for k in rpcs:
		names.append(String(k))
	names.sort()
	lines.append(path)
	for n in names:
		var c: Dictionary = rpcs[n]
		lines.append("  rpc %s(%d) mode=%d xfer=%d local=%s ch=%d" % [n, args.get(n, -1),
			c.get("rpc_mode", 0), c.get("transfer_mode", 0), c.get("call_local", false), c.get("channel", 0)])
	vars.sort()
	lines.append("  vars " + ",".join(vars))

static func _describe_scene(path: String, lines: PackedStringArray) -> void:
	var state := (load(path) as PackedScene).get_state()
	for i in state.get_node_count():
		for j in state.get_node_property_count(i):
			var v: Variant = state.get_node_property_value(i, j)
			if not v is SceneReplicationConfig:
				continue
			var cfg: SceneReplicationConfig = v
			lines.append("%s %s" % [path, state.get_node_path(i)])
			for prop: NodePath in cfg.get_properties():
				lines.append("  sync %s mode=%d spawn=%s" % [prop, cfg.property_get_replication_mode(prop),
					cfg.property_get_spawn(prop)])
