extends Node
## Manages global and role-specific upgrades

signal upgrade_applied(upgrade_id: String)
signal gold_changed(new_total: int)

const UPGRADES: Dictionary = {
	"sling":      {"name": "Tempered Slings",    "desc": "Stone damage x1.5",         "cost": 10},
	"stone_cart": {"name": "Stone Cart",          "desc": "+3 max stones for all",     "cost": 15},
	"blessing":   {"name": "Nehemiah Blessing",  "desc": "Restore all player health", "cost": 20},
	"mortar":     {"name": "Thick Mortar",        "desc": "New wall blocks +25 HP",    "cost": 25},
}

var purchased: Dictionary = {} # upgrade_id -> bool
var team_gold: int = 0

func _ready():
	if multiplayer.is_server():
		NetworkManager.player_connected.connect(_on_player_connected)

func _on_player_connected(id: int):
	_sync_state.rpc_id(id, purchased, team_gold)

func add_gold(amount: int):
	if not multiplayer.is_server(): return
	team_gold += amount
	gold_changed.emit(team_gold)
	_sync_state.rpc(purchased, team_gold)

@rpc("any_peer", "reliable")
func request_purchase(upgrade_id: String):
	if not multiplayer.is_server(): return
	if purchased.get(upgrade_id, false): return
	var data = UPGRADES.get(upgrade_id)
	if not data: return
	
	if team_gold >= data.cost:
		team_gold -= data.cost
		purchased[upgrade_id] = true
		gold_changed.emit(team_gold)
		_apply_upgrade.rpc(upgrade_id)
		_sync_state.rpc(purchased, team_gold)

@rpc("authority", "call_local", "reliable")
func _apply_upgrade(upgrade_id: String):
	purchased[upgrade_id] = true
	upgrade_applied.emit(upgrade_id)
	
	# Actual logic application
	var main = get_tree().current_scene
	match upgrade_id:
		"sling":
			main.stone_damage_mult = 1.5
		"stone_cart":
			var players = main.get_node("Players")
			for p in players.get_children():
				if "max_stones" in p: p.max_stones += 3
		"mortar":
			var bm = main.get_node("BuildingManager")
			if "block_hp_bonus" in bm: bm.block_hp_bonus = 25.0
		"blessing":
			var players = main.get_node("Players")
			for p in players.get_children():
				if "health" in p: p.health = 100.0

@rpc("authority", "call_local", "reliable")
func _sync_state(p: Dictionary, g: int):
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
