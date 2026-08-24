class_name ReplayView
extends Node3D
## Watches a recorded shot back.
##
## Nothing here is simulated: every frame is a pure function of the scrub time,
## which is what makes the timeline, the slow motion and the dragging work. The
## tree is frozen while this is open (see `GameState.enter_cinematic`), so this
## node and its UI run on `PROCESS_MODE_ALWAYS`.
##
## The camera hangs off the rocket: it sits behind the current heading by
## default, always looks at the rocket, and the mouse orbits and zooms it.

## Rocket to borrow the flight model's visuals from, so the ghost never drifts
## out of sync with the real thing.
const ROCKET_SCENE: PackedScene = preload("res://scenes/weapons/rocket.tscn")

@export_group("Camera")
@export var start_distance: float = 5.0
## Opening framing, as an offset from directly behind the rocket. Straight
## behind is a bad shot: you see the trail end-on and nothing of the rocket.
@export var start_yaw_deg: float = 32.0
@export var start_pitch_deg: float = 13.0
@export var min_distance: float = 1.5
@export var max_distance: float = 80.0
@export var zoom_step: float = 1.12
@export var orbit_sensitivity: float = 0.008
## How fast the camera swings round to sit behind a turning rocket.
@export var heading_follow: float = 3.5
@export_range(5.0, 85.0, 0.5) var pitch_limit_deg: float = 82.0
## Never let the camera sink below this height, so it cannot end up underground.
@export var min_height: float = 0.5

@export_group("Trail")
@export var trail_color: Color = Color(1.0, 0.99, 0.97, 1.0)
@export var trail_head_width: float = 0.12
@export var trail_tail_width: float = 0.6
@export var arc_color: Color = Color(0.686275, 0.443137, 0.00784314, 0.5)
@export var ground_track_color: Color = Color(0.231373, 0.290196, 0.419608, 0.28)
## The chase camera flies through its own smoke. Trail within this distance of
## the lens fades out rather than filling the screen with a white slab.
@export var trail_near_fade: float = 12.0

@export_group("Blast")
@export var blast_grow_time: float = 0.26
@export var blast_fade_time: float = 0.95
@export var blast_flash_energy: float = 8.0
## The camera backs off to this multiple of the blast radius for the impact, so
## the fireball is something you watch rather than something you are inside.
@export var blast_standoff: float = 2.6
## How long before the impact the camera starts backing off. A recording knows
## the hit is coming, so the shot can be clear of the blast before it happens.
@export var blast_standoff_lead: float = 0.55

@onready var camera: Camera3D = $Camera
@onready var ghost: Node3D = $Ghost
@onready var trail: MeshInstance3D = $Trail
@onready var blast: Node3D = $Blast
@onready var blast_sphere: MeshInstance3D = $Blast/Sphere
@onready var blast_light: OmniLight3D = $Blast/Flash
@onready var impact_marker: Node3D = $ImpactMarker
@onready var impact_label: Label3D = $ImpactMarker/Distance
@onready var ui: ReplayUI = %ReplayUI

var recording: ShotRecording = null
var time: float = 0.0
var speed: float = 1.0
var is_playing: bool = false
var is_open: bool = false

var _orbit_yaw: float = 0.0
var _orbit_pitch: float = 0.0
var _heading_yaw: float = 0.0
var _distance: float = 7.0
var _dragging: bool = false
## Set once the player zooms, after which the camera stops moving itself.
var _zoomed: bool = false

var _trail_mesh: ImmediateMesh
var _trail_material: StandardMaterial3D
var _blast_material: StandardMaterial3D
var _ghost_flame: GPUParticles3D = null
var _ghost_light: OmniLight3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_trail()
	_build_blast_material()
	_build_ghost()
	_close_silently()

	EventBus.replay_requested.connect(open)
	ui.play_toggled.connect(toggle_play)
	ui.seek_requested.connect(seek)
	ui.speed_changed.connect(set_speed)
	ui.restart_requested.connect(restart)
	ui.next_requested.connect(_on_next_requested)


# --- open / close -------------------------------------------------------

func open(rec: ShotRecording) -> void:
	if rec == null or not rec.is_valid():
		push_warning("ReplayView: asked to play a recording with no frames.")
		EventBus.next_level_requested.emit()
		return

	recording = rec
	is_open = true
	# The replay borrows the camera and the mouse, so this is the point the game
	# actually freezes - clearing a level no longer does.
	GameState.enter_cinematic()
	time = 0.0
	speed = 1.0
	is_playing = true
	_distance = start_distance
	_orbit_yaw = deg_to_rad(start_yaw_deg)
	_orbit_pitch = deg_to_rad(start_pitch_deg)
	_dragging = false
	_zoomed = false

	visible = true
	camera.current = true
	set_process(true)
	set_process_unhandled_input(true)

	var player: Player = GameState.player as Player
	if player != null:
		player.set_viewmodel_visible(false)

	_prime_impact_marker()
	ui.open(rec)
	ui.set_speed(speed)
	ui.set_playing(true)
	_apply(0.0, true)
	EventBus.replay_active.emit(true)


func close() -> void:
	if not is_open:
		return
	_close_silently()
	EventBus.replay_active.emit(false)
	GameState.exit_cinematic()


func _close_silently() -> void:
	is_open = false
	is_playing = false
	recording = null
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	_dragging = false

	if ui != null:
		ui.close()

	var player: Player = GameState.player as Player
	if player != null:
		player.set_viewmodel_visible(true)
		player.make_camera_current()


# --- transport ----------------------------------------------------------

func toggle_play() -> void:
	if not is_open:
		return
	# Hitting play at the very end starts over rather than doing nothing.
	if not is_playing and time >= recording.duration() - 0.001:
		time = 0.0
	is_playing = not is_playing
	ui.set_playing(is_playing)


func restart() -> void:
	if not is_open:
		return
	time = 0.0
	is_playing = true
	ui.set_playing(true)
	_apply(0.0, true)


## Jumps the timeline. Scrubbing always pauses, the way a video editor does.
func seek(to: float) -> void:
	if not is_open:
		return
	time = clampf(to, 0.0, recording.duration())
	is_playing = false
	ui.set_playing(false)
	_apply(0.0, true)


func set_speed(value: float) -> void:
	speed = clampf(value, 0.02, 8.0)
	ui.set_speed(speed)


func step(seconds: float) -> void:
	seek(time + seconds)


# --- frame --------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open:
		return

	if is_playing:
		time += delta * speed
		if time >= recording.duration():
			time = recording.duration()
			is_playing = false
			ui.set_playing(false)

	_apply(delta, false)


func _apply(delta: float, instant: bool) -> void:
	var flight: float = minf(time, recording.flight_time())
	var frame: Dictionary = recording.sample(flight)

	_place_ghost(frame)
	_update_camera(frame, delta, instant)
	_rebuild_trail(flight)
	_update_blast()
	ui.set_time(time, recording.duration())
	ui.set_readout(frame, time, recording)


func _place_ghost(frame: Dictionary) -> void:
	# Once the rocket has detonated there is nothing left to draw.
	var gone: bool = recording.has_impact() and time >= recording.impact_time
	ghost.visible = not gone
	if gone:
		_set_motor(false)
		return

	ghost.global_transform = Transform3D(Basis(frame["rotation"]), frame["position"])
	_set_motor(bool(frame["burning"]))


func _set_motor(on: bool) -> void:
	if _ghost_flame != null:
		_ghost_flame.emitting = on
	if _ghost_light != null:
		_ghost_light.visible = on


func _update_camera(frame: Dictionary, delta: float, instant: bool) -> void:
	var focus: Vector3 = frame["position"]
	var velocity: Vector3 = frame["velocity"]

	# Default framing is from behind, so the camera trails the rocket. What the
	# player drags is an offset on top of that rather than a replacement.
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 2.0:
		var behind: float = atan2(-velocity.x, -velocity.z)
		if instant:
			_heading_yaw = behind
		else:
			_heading_yaw = lerp_angle(_heading_yaw, behind, clampf(heading_follow * delta, 0.0, 1.0))

	var yaw: float = _heading_yaw + _orbit_yaw
	var pitch: float = _orbit_pitch
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	) * _view_distance()

	var eye: Vector3 = focus + offset
	eye.y = maxf(eye.y, min_height)
	camera.global_position = eye
	if eye.distance_squared_to(focus) > 0.0001:
		camera.look_at(focus, Vector3.UP)


## A chase distance of a few metres puts the camera inside the fireball, so it
## pulls out to clear the blast once the rocket lands. Purely a function of the
## scrub time, so it does the same thing forwards, backwards and paused. Once
## the player has zoomed by hand, their distance is left alone.
func _view_distance() -> float:
	if _zoomed or not recording.has_impact():
		return _distance

	var clear: float = maxf(recording.blast_radius, 1.0) * blast_standoff
	if clear <= _distance:
		return _distance

	var lead: float = maxf(blast_standoff_lead, 0.001)
	var start: float = recording.impact_time - lead
	return lerpf(_distance, clear, smoothstep(start, recording.impact_time, time))


# --- trail --------------------------------------------------------------

func _build_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	trail.mesh = _trail_mesh
	trail.transform = Transform3D.IDENTITY

	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.vertex_color_use_as_albedo = true
	_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_material.albedo_color = Color.WHITE
	trail.material_override = _trail_material


## Rebuilt every frame: the smoke laid down so far as a camera-facing ribbon,
## the whole arc as a faint line, and that arc flattened onto the ground so the
## height of the shot reads at a glance.
func _rebuild_trail(until: float) -> void:
	_trail_mesh.clear_surfaces()

	var flown: PackedVector3Array = recording.path_until(until)
	var whole: PackedVector3Array = recording.path()

	_add_ribbon(flown)
	_add_line(whole, arc_color)
	_add_ground_track(whole)


func _add_ribbon(points: PackedVector3Array) -> void:
	var count: int = points.size()
	if count < 2:
		return

	var eye: Vector3 = camera.global_position
	var side: Vector3 = Vector3.RIGHT
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count:
		var here: Vector3 = points[i]
		var along: Vector3 = points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]
		if along.length_squared() < 0.000001:
			along = Vector3.FORWARD
		side = _ribbon_side(along, here - eye, side)

		# 0 at the muzzle end, 1 at the rocket: smoke spreads and thins with age.
		var fresh: float = float(i) / float(count - 1)
		var width: float = lerpf(trail_tail_width, trail_head_width, fresh)
		var colour: Color = trail_color
		colour.a = lerpf(0.04, 0.22, fresh) * _near_fade(here, eye)

		_trail_mesh.surface_set_color(colour)
		_trail_mesh.surface_add_vertex(here - side * width)
		_trail_mesh.surface_set_color(colour)
		_trail_mesh.surface_add_vertex(here + side * width)
	_trail_mesh.surface_end()


## Which way to spread the ribbon at one point: square to both the trail and the
## view, so it always faces the camera.
##
## Looking straight down the trail those two are parallel and the cross product
## collapses; normalising it there would twist the strip into a folded, opaque
## mess. The test has to be relative to the input lengths, because a segment
## 100 m from the lens has a huge cross product even when it is nearly parallel.
func _ribbon_side(along: Vector3, view: Vector3, previous: Vector3) -> Vector3:
	var side: Vector3 = along.cross(view)
	if side.length_squared() < 0.0004 * along.length_squared() * view.length_squared():
		return previous
	return side.normalized()


## 0 right at the lens, 1 once the smoke is far enough away to be scenery.
func _near_fade(point: Vector3, eye: Vector3) -> float:
	if trail_near_fade <= 0.0:
		return 1.0
	return clampf(point.distance_to(eye) / trail_near_fade, 0.0, 1.0)


func _add_line(points: PackedVector3Array, colour: Color) -> void:
	if points.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		_trail_mesh.surface_set_color(colour)
		_trail_mesh.surface_add_vertex(p)
	_trail_mesh.surface_end()


func _add_ground_track(points: PackedVector3Array) -> void:
	if points.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		_trail_mesh.surface_set_color(ground_track_color)
		_trail_mesh.surface_add_vertex(Vector3(p.x, 0.03, p.z))
	_trail_mesh.surface_end()


# --- impact -------------------------------------------------------------

func _build_blast_material() -> void:
	_blast_material = StandardMaterial3D.new()
	_blast_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blast_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blast_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_blast_material.albedo_color = Color(0.984314, 0.74902, 0.270588, 0.0)
	_blast_material.disable_receive_shadows = true
	blast_sphere.material_override = _blast_material


func _prime_impact_marker() -> void:
	if not recording.has_impact():
		blast.visible = false
		impact_marker.visible = false
		return

	blast.global_position = recording.impact_point
	impact_marker.global_position = recording.impact_point

	if recording.has_target:
		var miss: float = float(recording.result.get("miss_distance", 0.0))
		impact_label.text = "%.2f m from centre" % miss
	else:
		impact_label.text = "impact"


func _update_blast() -> void:
	if not recording.has_impact() or time < recording.impact_time:
		blast.visible = false
		impact_marker.visible = false
		return

	blast.visible = true
	impact_marker.visible = true

	var since: float = time - recording.impact_time
	var grow: float = clampf(since / maxf(blast_grow_time, 0.001), 0.0, 1.0)
	var radius: float = maxf(recording.blast_radius, 1.0) * (0.2 + 0.8 * sqrt(grow))
	blast_sphere.scale = Vector3.ONE * radius

	var fade: float = clampf(1.0 - since / maxf(blast_fade_time, 0.001), 0.0, 1.0)
	_blast_material.albedo_color.a = fade * 0.2
	blast_light.light_energy = fade * fade * blast_flash_energy
	blast_light.omni_range = maxf(radius * 2.5, 1.0)


# --- input --------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return

	if event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_orbit_yaw = wrapf(_orbit_yaw - motion.relative.x * orbit_sensitivity, -PI, PI)
		var limit: float = deg_to_rad(pitch_limit_deg)
		_orbit_pitch = clampf(_orbit_pitch + motion.relative.y * orbit_sensitivity, -limit, limit)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		_handle_key(event as InputEventKey)


func _handle_mouse_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_dragging = button.pressed
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_UP:
			if button.pressed:
				_zoom(1.0 / zoom_step)
		MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				_zoom(zoom_step)


func _handle_key(key: InputEventKey) -> void:
	match key.keycode:
		KEY_SPACE:
			toggle_play()
		KEY_LEFT:
			step(-0.05)
		KEY_RIGHT:
			step(0.05)
		KEY_R:
			restart()
		KEY_ESCAPE:
			# Back to the cleared level rather than on to the next one: the
			# range is still standing and the player may not be done with it.
			close()
		KEY_ENTER, KEY_KP_ENTER:
			_on_next_requested()
		_:
			return
	get_viewport().set_input_as_handled()


func _zoom(factor: float) -> void:
	_zoomed = true
	_distance = clampf(_distance * factor, min_distance, max_distance)
	get_viewport().set_input_as_handled()


func _on_next_requested() -> void:
	close()
	EventBus.next_level_requested.emit()


# --- ghost --------------------------------------------------------------

## Steals the rocket scene's `Visual` subtree rather than duplicating the model,
## so the replay always shows exactly the rocket that was fired. The rest of the
## instance never enters the tree, so its script never runs.
func _build_ghost() -> void:
	var template: Node = ROCKET_SCENE.instantiate()
	var visual: Node3D = template.get_node_or_null("Visual") as Node3D
	if visual == null:
		template.free()
		push_warning("ReplayView: rocket scene has no Visual node to borrow.")
		return

	template.remove_child(visual)
	template.free()

	ghost.add_child(visual)
	Rounded.soften(visual, 0.006)
	visual.transform = Transform3D.IDENTITY
	_ghost_flame = visual.get_node_or_null("Flame") as GPUParticles3D
	_ghost_light = visual.get_node_or_null("MotorLight") as OmniLight3D
	_set_motor(false)
