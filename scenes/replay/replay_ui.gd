class_name ReplayUI
extends Control
## Transport controls for the replay: scrubbable timeline, playback speed and
## the way out of the replay.
##
## It owns no playback state. `ReplayView` pushes the current time in and this
## reports what the player did back out through signals, so the two can never
## disagree about where the playhead is.

## Emitted when the play/pause button or the space bar is used.
signal play_toggled()
## The player dragged or clicked the timeline. Value is in seconds.
signal seek_requested(seconds: float)
signal speed_changed(multiplier: float)
signal restart_requested()
## The player wants out of the replay and on to the next level.
signal next_requested()

## Playback rates offered, slowest first. 1.0 has to be in here, and
## `SPEED_LABELS` has to line up with it.
const SPEEDS: Array[float] = [0.1, 0.25, 0.5, 1.0, 2.0]
const SPEED_LABELS: Array[String] = ["0.1x", "0.25x", "0.5x", "1x", "2x"]

@export var launch_marker_color: Color = Color(0.231373, 0.290196, 0.419608, 0.9)
@export var impact_marker_color: Color = Color(0.956863, 0.321569, 0.431373, 1)

@onready var title: Label = %Title
@onready var readout_keys: Label = %Keys
@onready var readout_values: Label = %Values
@onready var timeline: HSlider = %Timeline
@onready var play_button: Button = %PlayButton
@onready var time_label: Label = %TimeLabel
@onready var speed_row: HBoxContainer = %SpeedRow
@onready var restart_button: Button = %RestartButton
@onready var next_button: Button = %NextButton

var _recording: ShotRecording = null
## True while this node is writing to the slider, so its own change signal is
## not mistaken for the player scrubbing.
var _syncing: bool = false
var _speed_buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_build_speed_buttons()
	timeline.value_changed.connect(_on_timeline_changed)
	timeline.resized.connect(queue_redraw)
	resized.connect(queue_redraw)
	play_button.pressed.connect(func() -> void: play_toggled.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	next_button.pressed.connect(func() -> void: next_requested.emit())


# --- driven by ReplayView ----------------------------------------------

func open(recording: ShotRecording) -> void:
	_recording = recording
	visible = true

	var level: String = recording.level_name
	if level == "":
		title.text = "SHOT REPLAY"
	else:
		title.text = "REPLAY - LEVEL %d  %s" % [recording.level_index + 1, level]

	_syncing = true
	timeline.min_value = 0.0
	timeline.max_value = maxf(recording.duration(), 0.01)
	timeline.step = 0.001
	timeline.value = 0.0
	_syncing = false

	set_speed(1.0)
	queue_redraw()


func close() -> void:
	visible = false
	_recording = null


func set_playing(playing: bool) -> void:
	play_button.text = "PAUSE" if playing else "PLAY"


func set_time(seconds: float, duration: float) -> void:
	_syncing = true
	timeline.value = seconds
	_syncing = false
	time_label.text = "%.2f / %.2f s" % [seconds, duration]
	queue_redraw()


func set_speed(multiplier: float) -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(is_equal_approx(SPEEDS[i], multiplier))


## The stats panel in the corner: what the rocket was doing at this instant.
## Time is shown relative to the impact, so the interesting moment is zero.
func set_readout(frame: Dictionary, seconds: float, recording: ShotRecording) -> void:
	var keys := PackedStringArray(["phase", "t", "speed", "altitude"])
	var values := PackedStringArray([
		_phase(seconds, recording),
		"%+.2f s" % (seconds - maxf(recording.impact_time, 0.0)),
		"%d m/s" % roundi(float(frame["speed"])),
		"%.1f m" % Vector3(frame["position"]).y,
	])

	if recording.has_target:
		keys.append("to target")
		values.append("%.1f m" % recording.distance_to_target(minf(seconds, recording.flight_time())))
	if not recording.wind.is_zero_approx():
		keys.append("crosswind")
		values.append("%d m/s" % roundi(recording.wind.length()))

	readout_keys.text = "\n".join(keys)
	readout_values.text = "\n".join(values)


func _phase(seconds: float, recording: ShotRecording) -> String:
	if recording.has_impact() and seconds >= recording.impact_time:
		return "IMPACT"
	if bool(recording.sample(seconds)["burning"]):
		return "MOTOR"
	return "COAST"


# --- timeline ----------------------------------------------------------

func _on_timeline_changed(value: float) -> void:
	if _syncing:
		return
	seek_requested.emit(value)


## Ticks for launch and impact painted over the slider, so the moment the rocket
## lands is findable without hunting for it.
func _draw() -> void:
	if _recording == null or _recording.duration() <= 0.0:
		return

	var track := Rect2(timeline.global_position - global_position, timeline.size)
	if track.size.x <= 1.0:
		return

	_draw_tick(track, 0.0, launch_marker_color)
	if _recording.has_impact():
		_draw_tick(track, _recording.impact_time, impact_marker_color)


func _draw_tick(track: Rect2, at: float, colour: Color) -> void:
	var f: float = clampf(at / _recording.duration(), 0.0, 1.0)
	# The grabber needs room at both ends, so inset the usable span to match.
	var inset: float = 8.0
	var x: float = track.position.x + inset + (track.size.x - inset * 2.0) * f
	draw_rect(Rect2(x - 1.0, track.position.y + 2.0, 2.0, track.size.y - 4.0), colour)


# --- speed buttons -----------------------------------------------------

func _build_speed_buttons() -> void:
	var group := ButtonGroup.new()
	for i in SPEEDS.size():
		var multiplier: float = SPEEDS[i]
		var button := Button.new()
		button.text = SPEED_LABELS[i]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(56.0, 0.0)
		button.pressed.connect(func() -> void: speed_changed.emit(multiplier))
		speed_row.add_child(button)
		_speed_buttons.append(button)
