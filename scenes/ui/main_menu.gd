extends Control

@onready var host_btn:      Button   = $Layout/Buttons/HostButton
@onready var join_btn:      Button   = $Layout/Buttons/JoinButton
@onready var settings_btn:  Button   = $Layout/Buttons/SettingsButton
@onready var quit_btn:      Button   = $Layout/Buttons/QuitButton
@onready var join_panel:    Control  = $JoinPanel
@onready var address_input: LineEdit = $JoinPanel/Content/AddressInput
@onready var connect_btn:   Button   = $JoinPanel/Content/ConnectButton
@onready var back_btn:      Button   = $JoinPanel/Content/BackButton
@onready var status_label:  Label    = $JoinPanel/Content/StatusLabel

func _ready() -> void:
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	connect_btn.pressed.connect(_on_connect)
	back_btn.pressed.connect(_on_back)
	quit_btn.pressed.connect(get_tree().quit)
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	join_panel.hide()

func _on_host() -> void:
	NetworkManager.host()

func _on_join() -> void:
	join_panel.show()
	address_input.grab_focus()

func _on_connect() -> void:
	var addr := address_input.text.strip_edges()
	if addr.is_empty():
		return
	status_label.text = "Connecting…"
	connect_btn.disabled = true
	NetworkManager.join(addr)

func _on_back() -> void:
	join_panel.hide()
	status_label.text = ""
	connect_btn.disabled = false

func _on_lobby_created() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")

func _on_lobby_joined(success: bool) -> void:
	if success:
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	else:
		status_label.text = "Connection failed."
		connect_btn.disabled = false
