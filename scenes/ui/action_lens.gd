class_name ActionLens
extends Control

# "What can I do here?" — hold [Tab] / View and every thing near you that answers a press
# gets a chip saying what: take stone, build, help up, take the other end, hand over...
# Playtest: friends didn't know what the game let them do (two to a beam, handing a load
# over, climbing a finished wall). One key answers all of it, whenever they wonder.

const RANGE     := 16.0    # metres from the local worker
const MAX_CHIPS := 16
const LIFT      := 2.2     # chip height over the thing, metres

var _chips: Array[Label] = []
var _veil: ColorRect
var _hint: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil = ColorRect.new()
	_veil.color = Color(UiStyle.DUSK, 0.18)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_hint = _chip()
	_hint.add_theme_font_override("font", UiStyle.SPECTRAL_ITALIC)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	visible = false

func _chip() -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", UiStyle.SPECTRAL_MEDIUM)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", UiStyle.INK)
	l.add_theme_stylebox_override("normal", UiStyle.bordered(UiStyle.plaque(Vector2(12, 4), 0.96), UiStyle.GOLD, 1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # set translated
	add_child(l)
	return l

func _process(_delta: float) -> void:
	var me := Player.local
	var on := me != null and is_instance_valid(me) and Input.is_action_pressed("reveal") \
		and not InputMode.gameplay_blocked() and not GameState.is_over() \
		and GameState.phase != GameState.Phase.STORY
	visible = on
	if not on:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var entries := _entries(me)
	entries.sort_custom(func(a, b): return a[2] < b[2])
	entries.resize(mini(entries.size(), MAX_CHIPS))
	while _chips.size() < entries.size():
		_chips.append(_chip())
	for i in _chips.size():
		var l := _chips[i]
		if i >= entries.size():
			l.visible = false
			continue
		var at: Vector3 = entries[i][0] + Vector3.UP * LIFT
		if cam.is_position_behind(at):
			l.visible = false
			continue
		l.visible = true
		l.text = entries[i][1]
		l.size = l.get_combined_minimum_size()
		l.position = cam.unproject_position(at) - Vector2(l.size.x * 0.5, l.size.y)
	_hint.text = tr("What you can do — let go of %s to carry on") % InputMode.key("reveal")
	_hint.size = _hint.get_combined_minimum_size()

## [world position, text, distance] for everything near `me` that answers a press
func _entries(me: Player) -> Array:
	var out := []
	var here := me.global_position
	var e := "[%s]" % InputMode.key("interact")
	var g := "[%s]" % InputMode.key("drop")
	var add := func(at: Vector3, text: String):
		var d := Vector2(at.x - here.x, at.z - here.z).length()
		if d <= RANGE:
			out.append([at, text, d])
	var carrying := me.carried_kind
	# Yourself: what the other buttons do right now
	if not carrying.is_empty() and carrying != "beam":
		add.call(here, tr("%s Drop it — beside a friend, it goes into their hands") % g)
	elif carrying == "beam":
		add.call(here, tr("A beam goes quicker with a partner on the other end"))
	else:
		add.call(here, tr("[%s] Sling · up close it's the sword") % InputMode.key("throw"))
	if GameState.has_twist("horn"):
		add.call(here + Vector3.UP * 0.7, tr("[%s] Sound the horn — whoever stands in its ring strikes harder") % InputMode.key("horn"))
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p == me:
			continue
		if p.downed:
			pass   # the "Help up" world tag over them already says it
		elif p.carried_kind == "beam" and p._beam_partner() == null and carrying.is_empty():
			add.call(p.global_position, tr("%s Take the other end") % e)
		elif not carrying.is_empty() and carrying != "beam" and p.carried_kind.is_empty() and p.helping_id == 0:
			add.call(p.global_position, tr("%s beside them: hand over the %s") % [g, _mat(carrying)])
	for pile: Node3D in get_tree().get_nodes_in_group("supply_piles"):
		if carrying.is_empty():
			add.call(pile.global_position, tr("%s Take %s") % [e, _mat(pile.kind)])
	for item: Node3D in get_tree().get_nodes_in_group("dropped_items"):
		if carrying.is_empty():
			add.call(item.global_position, tr("%s Pick up %s") % [e, _mat(item.kind)])
	for site: Node3D in get_tree().get_nodes_in_group("build_sites"):
		var at: Vector3 = site.approach_point(here, 0.0) if site.has_method("approach_point") else site.global_position
		var need: String = site.next_need()
		var post := site.is_in_group("watch_posts")
		if site.can_build():
			add.call(at, tr("%s Work it up") % e)
		elif not need.is_empty():
			if carrying == need:
				add.call(at, tr("%s Deliver the %s") % [e, _mat(need)])
			elif post:
				add.call(at, tr("Watch post: bring %s") % _mat(need))
			elif site.get("is_target") != false:
				add.call(at, tr("Bring %s") % _mat(need))
		elif site.has_method("blocks_workers") and site.blocks_workers():
			if at.distance_to(here) < 5.0:
				add.call(at, tr("%s Climb over") % e)
	for pile: Node3D in get_tree().get_nodes_in_group("scattered_piles"):
		add.call(pile.global_position, tr("%s Gather up the scattered %s — nothing to take until then") % [e, _mat(pile.kind)])
	if me.health < Player.MAX_HEALTH and Player.can_drink_now():
		for well: Node3D in get_tree().get_nodes_in_group("wells"):
			add.call(well.global_position + Vector3.UP * 0.7, tr("%s Drink — hands free, stand still to mend") % e if carrying.is_empty() \
				else tr("Set the load down, then drink at the well to mend"))
	for foe: Node3D in get_tree().get_nodes_in_group("enemies"):
		if foe.has_method("is_saboteur") and foe.is_saboteur():
			add.call(foe.global_position, tr("Saboteur — stop him before he scatters a pile"))
	for m: Node3D in get_tree().get_nodes_in_group("messengers"):
		add.call(m.global_position, tr("Don't go with him — just walk away"))
	return out

func _mat(kind: String) -> String:
	return tr({"beam": "beams"}.get(kind, kind))
