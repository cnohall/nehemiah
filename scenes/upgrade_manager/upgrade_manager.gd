extends Node
## Manages global and role-specific upgrades

signal upgrade_applied(upgrade_id: String)
signal gold_changed(new_total: int)

const UPGRADES: Dictionary = {
	"sling":      {"name": "Tempered Slings",    "desc": "Stone damage x1.5",         "cost": 10},
	"fast_feet":  {"name": "Strong Backs",       "desc": "Carry speed +25%",          "cost": 15},
	"blessing":   {"name": "Nehemiah Blessing",  "desc": "Restore all player health", "cost": 20},
	"fortify":    {"name": "Reinforced Layers",  "desc": "Wall sabotage -50%",        "cost": 25},
}

var purchased: Dictionary = {} # upgrade_id -> bool
var team_gold: int = 0

func _ready() -> void:
	if multiplayer.is_server():
		NetworkManager.player_connected.connect(_on_player_connected)

func _on_player_connected(id: int) -> void:
	sync_state.rpc_id(id, purchased, team_gold)

func add_gold(amount: int) -> void:
	if not multiplayer.is_server(): return
	team_gold += amount
	gold_changed.emit(team_gold)
	sync_state.rpc(purchased, team_gold)

@rpc("any_peer", "reliable")
func request_purchase(upgrade_id: String) -> void:
	if not multiplayer.is_server(): return
	if purchased.get(upgrade_id, false): return
	var data = UPGRADES.get(upgrade_id)
	if not data: return
	
	if team_gold >= data.cost:
		team_gold -= data.cost
		purchased[upgrade_id] = true
		gold_changed.emit(team_gold)
		_apply_upgrade.rpc(upgrade_id)
		sync_state.rpc(purchased, team_gold)

@rpc("authority", "call_local", "reliable")
func _apply_upgrade(upgrade_id: String) -> void:
	purchased[upgrade_id] = true
	upgrade_applied.emit(upgrade_id)
	
	# Actual logic application
	var main = get_tree().current_scene
	match upgrade_id:
		"sling":
			if "stone_damage_mult" in main:
				main.stone_damage_mult = 1.5
		"fast_feet":
			# Handled in player.gd during speed calculation
			pass
		"fortify":
			# Handled in wall_section.gd during take_damage
			pass
		"blessing":
			var players = main.get_node_or_null("Players")
			if players:
				for p in players.get_children():
					if "health" in p: p.health = 100.0

@rpc("authority", "call_local", "reliable")
func sync_state(p: Dictionary, g: int) -> void:
	purchased = p
	team_gold = g
	var hud = _get_local_hud()
	if hud:
		hud.update_gold(team_gold)
		hud.update_upgrades(purchased, team_gold)

func _get_local_hud() -> CanvasLayer:
	var main = get_tree().current_scene
	if main.has_method("get_local_hud"):
		return main.get_local_hud()
	return null
