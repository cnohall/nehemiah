extends Node

# Epic Online Services: free cross-platform online play (PC + Android).
# Anonymous device login → the host opens a lobby tagged with a 5-letter room code →
# joiners look the code up, read the host's user id and open an EOS P2P connection
# (NAT punch-through with Epic's relay as fallback). Game traffic then runs over
# EOSGMultiplayerPeer, so RPCs/synchronizers work exactly as with ENet or Steam.
#
# Loaded by NetworkManager only when the EOSG extension is present.

signal status_changed

const CREDENTIALS := "res://eos_credentials.cfg"   # gitignored, see eos_credentials.cfg
const SOCKET      := "nehemiah"
const BUCKET      := "nehemiah:1"   # bump when the netcode changes so old builds don't match
const CODE_KEY    := "room"
const SEARCH_TRIES := 4
const SEARCH_RETRY := 1.5   # seconds between room lookups

var online := false   # logged in, can host/join
var error := ""       # why not, for the menu
var room_code := ""

var _lobby: HLobby

func _ready() -> void:
	HLog.log_level = HLog.LogLevel.WARN
	# Presence needs Epic accounts; we log in anonymously
	HLobbies.presence_enabled = false
	_setup()

func _setup() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CREDENTIALS) != OK:
		_fail("Online play not configured")
		return
	var creds := HCredentials.new()
	creds.product_name = "Nehemiah"
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	creds.product_version = version if not version.is_empty() else "0.1"   # SDK rejects ""
	for key in ["product_id", "sandbox_id", "deployment_id", "client_id", "client_secret", "encryption_key"]:
		creds.set(key, cfg.get_value("eos", key, ""))
	if not await HPlatform.setup_eos_async(creds):
		_fail("Online services failed to start")
		return
	# Device-bound anonymous account: no sign-up, no Epic account
	if not await HAuth.login_anonymous_async("Builder"):
		_fail("Online sign-in failed")
		return
	online = true
	status_changed.emit()

func _fail(msg: String) -> void:
	error = msg
	push_warning("EOS: " + msg)
	status_changed.emit()

## Host: open a coded lobby and a P2P server socket. Returns the peer, or null.
func host() -> MultiplayerPeer:
	var opts := EOS.Lobby.CreateLobbyOptions.new()
	opts.bucket_id = BUCKET
	opts.max_lobby_members = NetworkManager.MAX_PLAYERS
	opts.presence_enabled = false
	opts.local_user_id = HAuth.product_user_id
	_lobby = await HLobbies.create_lobby_async(opts)
	if _lobby == null:
		error = "Could not create an online room."
		return null
	room_code = _new_code()
	_lobby.add_attribute(CODE_KEY, room_code)
	if not await _lobby.update_async():
		await leave()
		error = "Could not publish the room code."
		return null
	var peer := EOSGMultiplayerPeer.new()
	if peer.create_server(SOCKET) != OK:
		await leave()
		error = "Could not open the online socket."
		return null
	return peer

## Join by room code. Returns the peer (still connecting), or null.
func join(code: String) -> MultiplayerPeer:
	# A fresh room takes a moment to show up in search — retry briefly
	var found = null
	for attempt in SEARCH_TRIES:
		found = await HLobbies.search_by_attribute_async({ key = CODE_KEY, value = code.to_upper() })
		if found:
			break
		await get_tree().create_timer(SEARCH_RETRY).timeout
	if not found:
		error = "No room with code %s." % code.to_upper()
		return null
	var host_id: String = found[0].owner_product_user_id
	var peer := EOSGMultiplayerPeer.new()
	if peer.create_client(SOCKET, host_id) != OK:
		error = "Could not reach the host."
		return null
	room_code = code.to_upper()
	return peer

func leave() -> void:
	room_code = ""
	var lobby := _lobby
	_lobby = null
	if lobby and lobby.is_owner():
		await lobby.destroy_async()

func _new_code() -> String:
	var chars := NetworkManager.ROOM_CODE_CHARS
	var code := ""
	for i in NetworkManager.ROOM_CODE_LEN:
		code += chars[randi() % chars.length()]
	return code
