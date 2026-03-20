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
## ─────────────────────────────────────────────────────────────────────────────


# ══════════════════════════════════════════════════════════════════════════════
# SIGNALS
# ══════════════════════════════════════════════════════════════════════════════

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
# CONSTANTS
# ════════════════════════════════════════════════════════════─
# ══════════════════════════════════════════════════════════════════════════════

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS:  int = 4


# ══════════════════════════════════════════════════════════════════════════════
# PRIVATE STATE
# ══════════════════════════════════════════════════════════════════════════════

var _is_host: bool = false

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
var _btn_style_normal:   StyleBoxFlat


# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_setup_ui()
	_connect_multiplayer_signals()
	_set_status("")


# ══════════════════════════════════════════════════════════════════════════════
# UI CONSTRUCTION
# ══════════════════════════════════════════════════════════════════════════════

func _setup_ui() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 10
	add_child(_canvas_layer)

	# Full-screen root so child anchors resolve correctly
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(root)

	# Solid parchment background — hides the 3D scene behind the menu
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.88, 0.80, 0.62)
	root.add_child(bg)

	# Subtle vignette overlay
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.0, 0.0, 0.0, 0.25)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	# Panel
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	panel.add_theme_stylebox_override("panel",
		_make_style(Color(0.13, 0.10, 0.07, 0.97), Color(0.62, 0.48, 0.24), 2, 6))

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 40)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	# ── Title ─────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "NEHEMIAH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.96, 0.88, 0.60))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The Wall"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.74, 0.52))
	vbox.add_child(subtitle)

	# ── Scripture quote ────────────────────────────────────────────────────────
	var quote := Label.new()
	quote.text = "\"Let us rebuild the wall of Jerusalem, so that we may no longer\nbe an object of reproach.\"\n— Nehemiah 2:17"
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.add_theme_font_size_override("font_size", 12)
	quote.add_theme_color_override("font_color", Color(0.74, 0.66, 0.50))
	vbox.add_child(quote)

	var div1 := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.50, 0.40, 0.20, 0.5)
	sep_style.content_margin_top = 2
	div1.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(div1)

	# Shared button styles
	_btn_style_normal = _make_style(Color(0.28, 0.20, 0.12), Color(0.62, 0.48, 0.24))
	var btn_hover := _make_style(Color(0.40, 0.30, 0.18), Color(0.85, 0.68, 0.36))

	# ── Host section ──────────────────────────────────────────────────────────
	var host_label := Label.new()
	host_label.text = "HOST"
	host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_label.add_theme_font_size_override("font_size", 11)
	host_label.add_theme_color_override("font_color", Color(0.72, 0.62, 0.42))
	vbox.add_child(host_label)

	_host_button = Button.new()
	_host_button.text = "Raise the Wall"
	_host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_button.custom_minimum_size = Vector2(0, 48)
	_host_button.add_theme_font_size_override("font_size", 18)
	_host_button.add_theme_color_override("font_color", Color(0.96, 0.88, 0.60))
	_host_button.pressed.connect(_on_host_button_pressed)
	_host_button.add_theme_stylebox_override("normal", _btn_style_normal)
	_host_button.add_theme_stylebox_override("hover", btn_hover)
	_host_button.add_theme_stylebox_override("pressed", _btn_style_normal)
	vbox.add_child(_host_button)

	var div2 := HSeparator.new()
	div2.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(div2)

	# ── Join section ──────────────────────────────────────────────────────────
	var join_label := Label.new()
	join_label.text = "JOIN"
	join_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_label.add_theme_font_size_override("font_size", 11)
	join_label.add_theme_color_override("font_color", Color(0.72, 0.62, 0.42))
	vbox.add_child(join_label)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "Host IP address"
	_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_input.custom_minimum_size = Vector2(0, 40)
	_ip_input.add_theme_font_size_override("font_size", 14)
	hbox.add_child(_ip_input)

	_port_input = LineEdit.new()
	_port_input.placeholder_text = "Port"
	_port_input.text = str(DEFAULT_PORT)
	_port_input.custom_minimum_size = Vector2(72, 40)
	_port_input.size_flags_horizontal = Control.SIZE_SHRINK_END
	_port_input.add_theme_font_size_override("font_size", 14)
	hbox.add_child(_port_input)

	_join_button = Button.new()
	_join_button.text = "Answer the Call"
	_join_button.custom_minimum_size = Vector2(0, 40)
	_join_button.add_theme_font_size_override("font_size", 14)
	_join_button.add_theme_color_override("font_color", Color(0.96, 0.88, 0.60))
	_join_button.pressed.connect(_on_join_button_pressed)
	_join_button.add_theme_stylebox_override("normal", _btn_style_normal)
	_join_button.add_theme_stylebox_override("hover", btn_hover)
	_join_button.add_theme_stylebox_override("pressed", _btn_style_normal)
	hbox.add_child(_join_button)

	# ── Status label ──────────────────────────────────────────────────────────
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 36)
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.44))
	vbox.add_child(_status_label)

	# ── Host info (shown after hosting) ───────────────────────────────────────
	_host_info_label = Label.new()
	_host_info_label.text = ""
	_host_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_info_label.visible = false
	_host_info_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.50))
	vbox.add_child(_host_info_label)

	# ── Quit button ───────────────────────────────────────────────────────────
	var div3 := HSeparator.new()
	div3.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(div3)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.custom_minimum_size = Vector2(120, 36)
	quit_btn.add_theme_font_size_override("font_size", 13)
	quit_btn.add_theme_color_override("font_color", Color(0.80, 0.70, 0.52))
	quit_btn.pressed.connect(func(): get_tree().quit())
	quit_btn.add_theme_stylebox_override("normal", _btn_style_normal)
	quit_btn.add_theme_stylebox_override("hover", btn_hover)
	quit_btn.add_theme_stylebox_override("pressed", _btn_style_normal)
	vbox.add_child(quit_btn)


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

func _on_host_button_pressed() -> void:
	_disable_buttons()
	_set_status("Starting server...")

	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)

	if err != OK:
		_set_status("Failed to start server on port %d.\nIs the port already in use?" % DEFAULT_PORT)
		_enable_buttons()
		connection_failed.emit("ENetMultiplayerPeer.create_server failed.")
		return

	multiplayer.multiplayer_peer = peer
	_is_host = true

	_set_status("Hosting on port %d.\nShare your local IP with your friend." % DEFAULT_PORT)
	if is_instance_valid(_host_info_label):
		_host_info_label.text = "Port: %d" % DEFAULT_PORT
		_host_info_label.visible = true

	lobby_created_success.emit(0)
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
		connection_failed.emit("ENetMultiplayerPeer.create_client failed.")
		return

	multiplayer.multiplayer_peer = peer


# ══════════════════════════════════════════════════════════════════════════════
# GODOT HIGH-LEVEL MULTIPLAYER CALLBACKS
# ══════════════════════════════════════════════════════════════════════════════

func _on_peer_connected(peer_id: int) -> void:
	if OS.is_debug_build():
		print("NetworkManager: Peer %d connected." % peer_id)
	player_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if OS.is_debug_build():
		print("NetworkManager: Peer %d disconnected." % peer_id)
	player_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	_set_status("Connected!  Get ready...")
	hide_menu()
	lobby_joined_success.emit(0)


func _on_connection_failed_internal() -> void:
	_set_status("Connection failed.  Check the IP and port, and try again.")
	_enable_buttons()
	multiplayer.multiplayer_peer = null
	connection_failed.emit("ENet connection failed.")


func _on_server_disconnected_internal() -> void:
	_set_status("Host disconnected.  Returning to menu.")
	_is_host = false
	multiplayer.multiplayer_peer = null
	_enable_buttons()
	show_menu()
	server_disconnected.emit()


# ══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ══════════════════════════════════════════════════════════════════════════════

func hide_menu() -> void:
	if is_instance_valid(_canvas_layer):
		_canvas_layer.visible = false


func show_menu() -> void:
	if is_instance_valid(_canvas_layer):
		_canvas_layer.visible = true


func disconnect_from_lobby() -> void:
	_is_host = false
	multiplayer.multiplayer_peer = null
	_enable_buttons()


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


func _make_style(bg: Color, border: Color, border_w: int = 1, corner_r: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left   = border_w
	s.border_width_right  = border_w
	s.border_width_top    = border_w
	s.border_width_bottom = border_w
	s.corner_radius_top_left     = corner_r
	s.corner_radius_top_right    = corner_r
	s.corner_radius_bottom_left  = corner_r
	s.corner_radius_bottom_right = corner_r
	return s
