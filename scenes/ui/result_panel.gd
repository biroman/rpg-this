extends Control
## The card that goes up when a level's target goes down.
##
## It does not stop the game. Clearing a level used to freeze the tree behind a
## modal panel, which meant the one thing worth watching - the target coming
## apart - happened where nobody could see it. So this sits off to one side of
## the crosshair, the range keeps running underneath it, and it waits: the
## player walks around, fires again, watches the replay, and leaves when they
## are done rather than when the panel says so.
##
## The mouse stays captured for exactly that reason, so the two ways on are
## keys rather than buttons.

## Score colours, picked to sit on a white card rather than on the dark HUD.
@export var color_direct: Color = Color(0.686275, 0.443137, 0.00784314)
@export var color_blast: Color = Color(0.780392, 0.227451, 0.333333)
@export var fade_in: float = 0.35

@onready var card: PanelContainer = %Card
@onready var header: Label = %Header
@onready var headline: Label = %Headline
@onready var score: Label = %Score
@onready var stat_keys: Label = %Keys
@onready var stat_values: Label = %Values
@onready var prompt_keys: Label = %PromptKeys
@onready var prompt_labels: Label = %PromptLabels

## The shot that cleared the level, held separately from `Replay.last_recording`
## because the player is free to keep firing while this is up.
var _recording: ShotRecording = null
## True between clearing a level and choosing a way out of it.
var _awaiting: bool = false

var _fade: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.level_started.connect(_on_level_started)
	EventBus.replay_active.connect(_on_replay_active)


func _unhandled_input(event: InputEvent) -> void:
	if not _awaiting or not visible:
		return

	if event.is_action_pressed("watch_replay"):
		if _recording == null or not _recording.is_valid():
			return
		visible = false
		EventBus.replay_requested.emit(_recording)
	elif event.is_action_pressed("next_level"):
		_dismiss()
		EventBus.next_level_requested.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_level_completed(index: int, report: Dictionary, attempts: int) -> void:
	_recording = Replay.last_recording
	_awaiting = true

	var direct: bool = bool(report.get("direct", false))
	header.text = "LEVEL %d CLEARED" % (index + 1)
	headline.text = _headline(report)
	# The result reads as plain text and only the points carry the colour, so
	# the card stays quiet until there is something to be pleased about.
	score.text = "+%d" % int(report.get("points", 0))
	score.add_theme_color_override("font_color", color_direct if direct else color_blast)
	_fill_stats(report, attempts)
	_fill_prompts()

	visible = true
	if _fade != null and _fade.is_valid():
		_fade.kill()
	card.modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(card, "modulate:a", 1.0, fade_in)


func _on_level_started(_index: int, _config: Dictionary) -> void:
	_dismiss()


func _dismiss() -> void:
	_awaiting = false
	_recording = null
	visible = false


func _headline(report: Dictionary) -> String:
	var direct: bool = bool(report.get("direct", false))
	var ring: String = String(report.get("ring", ""))
	var line: String = "DIRECT HIT" if direct else "BLAST HIT"
	if direct and ring != "":
		line += " - " + ring
	return line


## Two labels side by side rather than one padded block: the UI font is
## proportional, so spaces would not line the columns up.
func _fill_stats(report: Dictionary, attempts: int) -> void:
	var keys := PackedStringArray()
	var values := PackedStringArray()

	keys.append("Distance to target")
	values.append(_metres(float(report.get("range", 0.0))))
	keys.append("Rocket landed")
	values.append("%s from centre" % _metres(float(report.get("miss_distance", 0.0))))
	keys.append("Rockets fired")
	values.append(str(attempts))

	if _recording != null and _recording.is_valid():
		keys.append("Flight time")
		values.append("%.2f s" % _recording.flight_time())
		keys.append("Top speed")
		values.append("%d m/s" % roundi(_recording.top_speed()))
		keys.append("Apex")
		values.append(_metres(_recording.apex()))
		if not _recording.wind.is_zero_approx():
			keys.append("Crosswind")
			values.append("%d m/s" % roundi(_recording.wind.length()))

	stat_keys.text = "\n".join(keys)
	stat_values.text = "\n".join(values)


## Nothing to watch back if the shot filed no usable recording, in which case
## the replay line is simply not offered.
func _fill_prompts() -> void:
	var keys := PackedStringArray()
	var labels := PackedStringArray()
	if _recording != null and _recording.is_valid():
		keys.append("[E]")
		labels.append("WATCH THE REPLAY")
	keys.append("[ENTER]")
	labels.append("NEXT LEVEL")
	prompt_keys.text = "\n".join(keys)
	prompt_labels.text = "\n".join(labels)


func _metres(value: float) -> String:
	if value < 10.0:
		return "%.2f m" % value
	return "%.1f m" % value


## The replay takes the whole screen. Backing out of it drops the player onto
## the same cleared level, so the card comes back with it.
func _on_replay_active(is_active: bool) -> void:
	if is_active:
		visible = false
	elif _awaiting:
		visible = true
