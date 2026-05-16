extends CanvasLayer

@onready var day_number:  Label = $TopCenter/DayPanel/VBox/DayNumber
@onready var day_section: Label = $TopCenter/DayPanel/VBox/DaySection
@onready var enemy_count: Label = $WavePanel/VBox/EnemyCount

@onready var player_panels: Array = [
	$PlayersPanel/Player1,
	$PlayersPanel/Player2,
	$PlayersPanel/Player3,
	$PlayersPanel/Player4,
]

func _ready() -> void:
	GameState.day_changed.connect(refresh_day)
	refresh_day(GameState.current_day)

# ── Day / Section ──────────────────────────────────────────

func refresh_day(day: int) -> void:
	var section := GameState.get_section_for_day(day)
	day_number.text  = "Day %d of %d" % [day, GameState.TOTAL_DAYS]
	day_section.text = "%s · %s" % [section["name"], section["ref"]]

# ── Enemy count ────────────────────────────────────────────

func set_enemy_count(count: int) -> void:
	enemy_count.text = str(count)

# ── Player panels ──────────────────────────────────────────

func set_player_health(slot: int, pct: float) -> void:
	if slot >= player_panels.size():
		return
	var bar: ProgressBar = player_panels[slot].get_node_or_null("VBox/HealthBar")
	if bar:
		bar.value = pct * 100.0

func set_player_carry(slot: int, item_name: String) -> void:
	if slot >= player_panels.size():
		return
	var lbl: Label = player_panels[slot].get_node_or_null("VBox/CarryLabel")
	if lbl:
		lbl.text = item_name
