extends Node
## NetworkManager — Autoload Singleton
## ─────────────────────────────────────────────────────────────────────────────
## File:   scenes/network_manager/network_manager.gd
## Autoload name: NetworkManager   (set in Project → Project Settings → Autoload)
##
## Responsibilities:
##   • Host or join a game via ENet (built-in Godot transport, no dependencies)
##   • Wire up ENetMultiplayerPeer to Godot's High-Level Multiplayer API
##   • Host a simple main-menu UI (built in code — no .tscn required)
##   • Emit clean game-level signals so other scenes never touch the transport directly
##
## NOTE: This is a temporary ENet dev build replacing GodotSteam while the
##       Steam Client Service is broken. Swap back to network_manager_steam.gd
##       when Steam is repaired.
## ─────────────────────────────────────────────────────────────────────────────


# ══════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ══════════════════════════════════════════════════════════════════════════════

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS:  int = 4


# ══════════════════════════════════════════════════════════════════════════════
# SIGNALS
# ══════════════════════════════════════════════════════════════════════════════

## Fired once the backend is ready.  username is a placeholder in ENet mode.
signal steam_initialized(username: String)

## Fired on the host when the server is open and the peer is ready.
signal lobby_created_success(lobby_id: int)

## Fired on the client when it has successfully connected to the host.
signal lobby_joined_success(lobby_id: int)

## Fired on any peer when a remote player fully joins the Godot multiplayer session.
signal player_connected(peer_id: int)

## Fired on any peer when a remote player leaves or is dropped.
signal player_disconnected(peer_id: int)

## Fired on clients when the host closes the session.
signal server_disconnected

## Fired when any connection attempt fails, with a human-readable reason.
signal connection_failed(reason: String)


# ══════════════════════════════════════════════════════════════════════════════
# PRIVATE STATE
# ══════════════════════════════════════════════════════════════════════════════

var _is_host: bool = false
var selected_role: String = "slinger"


# ══════════════════════════════════════════════════════════════════════════════
# UI NODE REFERENCES
# ══════════════════════════════════════════════════════════════════════════════

var _canvas_layer:    CanvasLayer
var _status_label:    Label
var _host_info_label: Label
var _host_button:     Button
var _join_button:     Button
var _ip_input:        LineEdit
var _port_input:      LineEdit
var _role_buttons:    Dictionary = {}
var _btn_style_normal:   StyleBoxFlat
var _btn_style_selected: StyleBoxFlat


# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_setup_ui()
	_init_backend()
	_connect_multiplayer_signals()


# ══════════════════════════════════════════════════════════════════════════════
# UI CONSTRUCTION
# ══════════════════════════════════════════════════════════════════════════════

func _setup_ui() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 10
	add_child(_canvas_layer)

	# CenterContainer fills the whole viewport and positions its single child
	# at the center automatically — no pixel math, SubViewport-safe.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(center)

	# PanelContainer sizes itself to its content; custom_minimum_size sets the
	# floor so the join row never feels cramped on short strings.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	# Ancient stone / parchment panel background.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.18, 0.14, 0.10)
	panel_style.border_color = Color(0.55, 0.42, 0.22)
	panel_style.border_width_left   = 2
	panel_style.border_width_right  = 2
	panel_style.border_width_top    = 2
	panel_style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# ── Title ─────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "Nehemiah: The Wall"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Make the title visually distinct without needing a theme font override.
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.50))
	vbox.add_child(title)

	# ── Host info (shown after hosting) ───────────────────────────────────────
	_host_info_label = Label.new()
	_host_info_label.text = ""
	_host_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_info_label.visible = false
	_host_info_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.50))
	vbox.add_child(_host_info_label)

	# Thin divider between title block and status
	var div := HSeparator.new()
	vbox.add_child(div)

	# ── Status label ──────────────────────────────────────────────────────────
	_status_label = Label.new()
	_status_label.text = "Initializing..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Reserve two lines of height so the panel doesn't jump when text wraps.
	_status_label.custom_minimum_size = Vector2(0, 52)
	vbox.add_child(_status_label)

	# Shared style for action buttons — slightly lighter stone than the panel.
	_btn_style_normal = StyleBoxFlat.new()
	_btn_style_normal.bg_color = Color(0.28, 0.22, 0.15)
	_btn_style_normal.border_color = Color(0.55, 0.42, 0.22)
	_btn_style_normal.border_width_left   = 2
	_btn_style_normal.border_width_right  = 2
	_btn_style_normal.border_width_top    = 2
	_btn_style_normal.border_width_bottom = 2

	# Highlighted style for the selected role button.
	_btn_style_selected = StyleBoxFlat.new()
	_btn_style_selected.bg_color = Color(0.45, 0.32, 0.10)
	_btn_style_selected.border_color = Color(0.85, 0.65, 0.25)
	_btn_style_selected.border_width_left   = 2
	_btn_style_selected.border_width_right  = 2
	_btn_style_selected.border_width_top    = 2
	_btn_style_selected.border_width_bottom = 2

	# ── Role selection ────────────────────────────────────────────────────────
	var role_lbl := Label.new()
	role_lbl.text = "Choose your calling:"
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	vbox.add_child(role_lbl)

	var role_row := HBoxContainer.new()
	role_row.add_theme_constant_override("separation", 8)
	role_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(role_row)

	for r: String in ["Builder", "Slinger", "Porter"]:
		var btn := Button.new()
		btn.text = r
		btn.custom_minimum_size = Vector2(100, 34)
		btn.add_theme_stylebox_override("normal", _btn_style_normal)
		btn.pressed.connect(_on_role_selected.bind(r))
		role_row.add_child(btn)
		_role_buttons[r] = btn

	_on_role_selected("Slinger")  # default

	# ── Host Game button (full width) ─────────────────────────────────────────
	_host_button = Button.new()
	_host_button.text = "Raise the Wall"
	_host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_button.custom_minimum_size = Vector2(0, 36)
	_host_button.pressed.connect(_on_host_button_pressed)
	_host_button.add_theme_stylebox_override("normal", _btn_style_normal)
	vbox.add_child(_host_button)

	# ── Join row: [IP ──────────────────] [Port~~] [Join Game] ────────────────
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "Builder's IP address"
	_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_input.custom_minimum_size = Vector2(0, 36)
	hbox.add_child(_ip_input)

	_port_input = LineEdit.new()
	_port_input.placeholder_text = "Port"
	_port_input.text = str(DEFAULT_PORT)
	_port_input.custom_minimum_size = Vector2(80, 36)
	# Prevent the port field from expanding and stealing space from the IP field.
	_port_input.size_flags_horizontal = Control.SIZE_SHRINK_END
	hbox.add_child(_port_input)

	_join_button = Button.new()
	_join_button.text = "Answer the Call"
	_join_button.custom_minimum_size = Vector2(0, 36)
	_join_button.pressed.connect(_on_join_button_pressed)
	_join_button.add_theme_stylebox_override("normal", _btn_style_normal)
	hbox.add_child(_join_button)


# ══════════════════════════════════════════════════════════════════════════════
# BACKEND INITIALIZATION
# ══════════════════════════════════════════════════════════════════════════════

func _init_backend() -> void:
	_set_status("Ready. Host a session or answer the call of another builder.")
	emit_signal("steam_initialized", "ENet Dev")


# ══════════════════════════════════════════════════════════════════════════════
# SIGNAL WIRING
# ══════════════════════════════════════════════════════════════════════════════

func _connect_multiplayer_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed_internal)
	multiplayer.server_disconnected.connect(_on_server_disconnected_internal)


# ══════════════════════════════════════════════════════════════════════════════
# UI BUTTON HANDLERS
# ══════════════════════════════════════════════════════════════════════════════

func _on_role_selected(role: String) -> void:
	selected_role = role.to_lower()
	for r: String in _role_buttons:
		var btn: Button = _role_buttons[r]
		btn.add_theme_stylebox_override("normal",
			_btn_style_selected if r == role else _btn_style_normal)


func _on_host_button_pressed() -> void:
	_disable_buttons()
	_set_status("Starting server...")

	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)

	if err != OK:
		_set_status("Failed to start server on port %d.\nIs the port already in use?" % DEFAULT_PORT)
		_enable_buttons()
		emit_signal("connection_failed", "ENetMultiplayerPeer.create_server failed.")
		return

	multiplayer.multiplayer_peer = peer
	_is_host = true

	_set_status("Hosting on port %d.\nShare your local IP with your friend." % DEFAULT_PORT)
	_host_info_label.text = "Port: %d" % DEFAULT_PORT
	_host_info_label.visible = true

	emit_signal("lobby_created_success", 0)
	hide_menu()


func _on_join_button_pressed() -> void:
	var ip: String       = _ip_input.text.strip_edges()
	var port_str: String = _port_input.text.strip_edges()

	if ip.is_empty():
		_set_status("Please enter the host's IP address.")
		return

	var port: int = DEFAULT_PORT
	if not port_str.is_empty() and port_str.is_valid_int():
		port = int(port_str)

	_disable_buttons()
	_set_status("Connecting to %s:%d..." % [ip, port])

	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(ip, port)

	if err != OK:
		_set_status("Failed to create client (error %d)." % err)
		_enable_buttons()
		multiplayer.multiplayer_peer = null
		emit_signal("connection_failed", "ENetMultiplayerPeer.create_client failed.")
		return

	multiplayer.multiplayer_peer = peer


# ══════════════════════════════════════════════════════════════════════════════
# GODOT HIGH-LEVEL MULTIPLAYER CALLBACKS
# ══════════════════════════════════════════════════════════════════════════════

func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer %d connected." % peer_id)
	emit_signal("player_connected", peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: Peer %d disconnected." % peer_id)
	emit_signal("player_disconnected", peer_id)


func _on_connected_to_server() -> void:
	_set_status("Connected!  Get ready...")
	hide_menu()
	emit_signal("lobby_joined_success", 0)


func _on_connection_failed_internal() -> void:
	_set_status("Connection failed.  Check the IP and port, and try again.")
	_enable_buttons()
	multiplayer.multiplayer_peer = null
	emit_signal("connection_failed", "ENet connection failed.")


func _on_server_disconnected_internal() -> void:
	_set_status("Host disconnected.  Returning to menu.")
	_is_host = false
	multiplayer.multiplayer_peer = null
	_enable_buttons()
	show_menu()
	emit_signal("server_disconnected")


# ══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ══════════════════════════════════════════════════════════════════════════════

func hide_menu() -> void:
	_canvas_layer.visible = false


func show_menu() -> void:
	_canvas_layer.visible = true


func disconnect_from_lobby() -> void:
	_is_host = false
	multiplayer.multiplayer_peer = null
	_enable_buttons()


func get_steam_id() -> int:
	return 0


func get_steam_username() -> String:
	return "LocalPlayer"


func get_lobby_id() -> int:
	return 0


func get_selected_role() -> String:
	return selected_role


func is_host() -> bool:
	return _is_host


# ══════════════════════════════════════════════════════════════════════════════
# INTERNAL HELPERS
# ══════════════════════════════════════════════════════════════════════════════

func _set_status(text: String) -> void:
	print("NetworkManager: " + text)
	if is_instance_valid(_status_label):
		_status_label.text = text


func _disable_buttons() -> void:
	if is_instance_valid(_host_button): _host_button.disabled = true
	if is_instance_valid(_join_button): _join_button.disabled = true


func _enable_buttons() -> void:
	if is_instance_valid(_host_button): _host_button.disabled = false
	if is_instance_valid(_join_button): _join_button.disabled = false
