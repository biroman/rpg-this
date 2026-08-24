extends Node
## Keeps the shots that have been recorded so the replay viewer can find them.
##
## Autoloaded as `Replay`. Rockets push finished recordings in; nothing else
## has to know a recorder exists.

## How many past shots to keep around.
const MAX_HISTORY: int = 16

var last_recording: ShotRecording = null
var history: Array[ShotRecording] = []


func submit(recording: ShotRecording) -> void:
	if recording == null or not recording.is_valid():
		return
	last_recording = recording
	history.append(recording)
	if history.size() > MAX_HISTORY:
		history.remove_at(0)
	EventBus.shot_recorded.emit(recording)


func clear() -> void:
	last_recording = null
	history.clear()
