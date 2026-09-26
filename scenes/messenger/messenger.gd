class_name Messenger
extends Node3D

# "schemes" twist (East Gate — Neh. 6:1-4): Sanballat and Geshem send a messenger with an
# invitation to "the plain of Ono". He walks up to a worker and waits beside them, in
# reach of [E]. A worker who goes with him is led away from the wall for a while and
# has to walk back; ignored, he gives up and leaves. The right answer, every time, is
# to keep working (6:3).
# Server moves him; clients mirror position / anim / state via the synchronizer.

enum State { COMING, WAITING, LEADING, LEAVING }

const SPEED      := 3.2    # slower than a running worker — you can walk away from him
const LEAD_SPEED := 3.4
const STAND_OFF  := 1.1
const WAIT_TIME  := 12.0   # standing beside someone, until he gives up
const MAX_STAY   := 30.0   # however long he's been chasing
const LEAD_TIME  := 7.0
const LEAVE_TIME := 4.0
const LABEL_RANGE := 7.0
const ROBE   := Color(0.34, 0.22, 0.44)   # court purple — not one of the crew
const SCROLL := Color(0.93, 0.88, 0.74)

var anim := "idle_down":
	set(value):
		anim = value
		if _figure != null and _figure.animation != value:
			_figure.play(value)
var state := State.COMING:
	set(value):
		state = value
		if is_node_ready():
			_refresh()

var _target: Node3D
var _led: Node3D
var _timer := 0.0
var _waited := 0.0
var _facing := "down"
var _exit := Vector3.ZERO
var _label: Label3D

@onready var _figure: CharacterRig = $Figure

func _ready() -> void:
	_figure.setup({
		"skin": Color(0.66, 0.46, 0.32), "robe": ROBE, "trim": ROBE.darkened(0.45),
		"sash": Color(0.80, 0.62, 0.26), "hat": "wrap", "hat_color": Color(0.86, 0.78, 0.56), "tool": false,
		"band": Color(0.80, 0.62, 0.26), "beard": "short", "hair": Color(0.12, 0.09, 0.07),
		"outline": Color(0.20, 0.12, 0.24),
	})
	_figure.play(anim)
	# The letter in his hand (6:5 — "an open letter")
	var scroll := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = 0.45
	scroll.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SCROLL
	scroll.material_override = mat
	scroll.position = Vector3(0.38, 1.25, 0.25)
	scroll.rotation.z = PI / 2.4
	add_child(scroll)
	_label = Label3D.new()
	_label.text = "Come down to the plain of Ono"
	UiStyle.world_label(_label, 30)
	_label.position.y = 3.0
	add_child(_label)
	GameState.phase_changed.connect(_on_phase_changed)
	_refresh()

func _refresh() -> void:
	# Only while he's asking can [E] take his invitation
	if state == State.COMING or state == State.WAITING:
		add_to_group("messengers")
	else:
		remove_from_group("messengers")

func _process(_delta: float) -> void:
	_label.visible = state == State.WAITING and _local_player_near()

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_timer += delta
	match state:
		State.COMING, State.WAITING:
			if _waited > WAIT_TIME or _timer > MAX_STAY:
				_leave()
				return
			_target = _pick_target()
			if _target == null:
				_walk_to(global_position, delta, SPEED)
				return
			var to := _target.global_position - global_position
			to.y = 0.0
			if to.length() > STAND_OFF + 0.3:
				state = State.COMING
				_walk_to(_target.global_position - to.normalized() * STAND_OFF, delta, SPEED)
			else:
				state = State.WAITING
				_waited += delta
				_face(to)
				anim = "idle_" + _facing
		State.LEADING:
			if _timer > LEAD_TIME or not is_instance_valid(_led):
				_release()
				queue_free()
				return
			_walk_to(_exit, delta, LEAD_SPEED)
		State.LEAVING:
			if _timer > LEAVE_TIME:
				queue_free()
				return
			_walk_to(_exit, delta, SPEED)

## Server: a worker took the invitation — lead them off toward Ono
func accept(worker: Node3D) -> void:
	if state == State.LEADING or state == State.LEAVING:
		return
	_led = worker
	_timer = 0.0
	_exit = _exit_point()
	state = State.LEADING
	worker.lead_away(self, LEAD_TIME)

func _leave() -> void:
	_timer = 0.0
	_exit = _exit_point()
	state = State.LEAVING

func _release() -> void:
	if is_instance_valid(_led):
		_led.release_from_lead()
	_led = null

# Out the nearer side of the site, along the inside of the wall
func _exit_point() -> Vector3:
	var side := -1.0 if global_position.x < 4.0 else 1.0
	return Vector3(side * 48.0, global_position.y, clampf(global_position.z, 6.0, 14.0))

func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p: Node3D in get_tree().get_nodes_in_group("players"):
		if p.downed or p.is_led():
			continue
		var d := p.global_position.distance_to(global_position)
		# Stay with the one we're pestering unless someone is much closer
		if p == _target:
			d -= 3.0
		if d < best_d:
			best_d = d
			best = p
	return best

func _walk_to(dest: Vector3, delta: float, speed: float) -> void:
	var step := dest - global_position
	step.y = 0.0
	if step.length() < 0.05:
		anim = "idle_" + _facing
		return
	_face(step)
	global_position += step.normalized() * minf(step.length(), speed * delta)
	anim = "walk_" + _facing

func _face(dir: Vector3) -> void:
	_facing = CharAnim.dir_from_velocity(dir, _facing)

func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase != GameState.Phase.WORK and multiplayer.is_server():
		_release()
		queue_free()

func _exit_tree() -> void:
	if multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_release()

func _local_player_near() -> bool:
	return Player.local != null and Player.local.global_position.distance_to(global_position) < LABEL_RANGE
