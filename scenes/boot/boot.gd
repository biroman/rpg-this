extends Control
## Launch screen. Checks GitHub Releases for a newer build, installs it, then
## hands the session over to the game.
##
## Set as `run/main_scene` so it is the first thing an exported build touches.
## Every failure path falls through to `_launch_game()` -- a broken update check
## must never stop anyone from playing.

const REPO := "biroman/rpg-this"
const ASSET_NAME := "FlatWorld-windows.zip"
const GAME_SCENE := "res://scenes/main/main.tscn"

const CHECK_TIMEOUT := 8.0
const DOWNLOAD_TIMEOUT := 600.0

const UPDATE_DIR := "user://update"
const STAGE_DIR := "user://update/staged"
const ZIP_PATH := "user://update/download.zip"
const APPLY_PATH := "user://update/apply.cmd"

## Waits for the game to exit, copies the staged build over the install folder,
## then relaunches. Written to disk with CRLF endings -- cmd.exe mis-parses
## `goto` in LF-only batch files.
const APPLY_TEMPLATE := """@echo off
setlocal
set "PID={pid}"
set "SRC={src}"
set "DST={dst}"
set "EXE={exe}"
set /a TRIES=0

:wait
if %TRIES% GEQ 60 goto install
tasklist /FI "PID eq %PID%" /NH 2>nul | find "%PID%" >nul || goto install
set /a TRIES+=1
timeout /t 1 /nobreak >nul
goto wait

:install
robocopy "%SRC%" "%DST%" /E /IS /IT /R:10 /W:2 /NP /NFL /NDL /NJH /NJS /NC /NS >nul
if errorlevel 8 goto relaunch
rmdir /s /q "%SRC%" >nul 2>&1

:relaunch
start "" "%EXE%"
exit /b 0
"""

@onready var _status: Label = %Status
@onready var _detail: Label = %Detail
@onready var _progress: ProgressBar = %Progress
@onready var _http: HTTPRequest = %HTTPRequest

var _new_version := ""


func _ready() -> void:
	_progress.visible = false
	_detail.text = ""
	# The editor runs from source, and the installer is Windows-only.
	if OS.has_feature("editor") or OS.get_name() != "Windows":
		_launch_game()
		return
	_check_for_update()


func _process(_delta: float) -> void:
	if not _progress.visible:
		return
	var total := _http.get_body_size()
	if total <= 0:
		return
	var done := _http.get_downloaded_bytes()
	_progress.value = float(done) / float(total) * 100.0
	_detail.text = "%s of %s" % [_format_size(done), _format_size(total)]


func _check_for_update() -> void:
	_status.text = "Checking for updates..."
	_http.timeout = CHECK_TIMEOUT
	_http.request_completed.connect(_on_release_info, CONNECT_ONE_SHOT)
	var url := "https://api.github.com/repos/%s/releases/latest" % REPO
	if _http.request(url, _api_headers()) != OK:
		_launch_game()


func _on_release_info(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# No releases yet, offline, rate limited -- all of these just mean "play".
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_launch_game()
		return

	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		_launch_game()
		return

	var release: Dictionary = data
	var tag := str(release.get("tag_name", ""))
	var current := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if _compare_versions(tag, current) <= 0:
		_launch_game()
		return

	var url := _find_asset_url(release)
	if url.is_empty():
		_launch_game()
		return

	_new_version = tag.lstrip("v")
	_download(url)


func _find_asset_url(release: Dictionary) -> String:
	for asset in release.get("assets", []):
		if typeof(asset) == TYPE_DICTIONARY and str(asset.get("name", "")) == ASSET_NAME:
			return str(asset.get("browser_download_url", ""))
	return ""


func _download(url: String) -> void:
	_status.text = "Downloading version %s" % _new_version
	_detail.text = ""
	_progress.value = 0.0
	_progress.visible = true

	_rm_rf(STAGE_DIR)
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)

	_http.timeout = DOWNLOAD_TIMEOUT
	_http.download_file = ZIP_PATH
	_http.request_completed.connect(_on_download_finished, CONNECT_ONE_SHOT)
	if _http.request(url, _api_headers()) != OK:
		_fail("Download could not start")


func _on_download_finished(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_progress.visible = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Download failed")
		return

	_status.text = "Installing version %s" % _new_version
	_detail.text = "Please do not close this window."
	await get_tree().process_frame

	if not _extract():
		_fail("Could not unpack the update")
		return
	DirAccess.remove_absolute(ZIP_PATH)

	if not _write_apply_script():
		_fail("Could not stage the update")
		return

	var comspec := OS.get_environment("COMSPEC")
	if comspec.is_empty():
		comspec = "cmd.exe"
	if OS.create_process(comspec, ["/c", ProjectSettings.globalize_path(APPLY_PATH)], false) == -1:
		_fail("Could not start the installer")
		return

	_status.text = "Restarting..."
	_detail.text = ""
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


func _extract() -> bool:
	var reader := ZIPReader.new()
	if reader.open(ZIP_PATH) != OK:
		return false

	var ok := true
	DirAccess.make_dir_recursive_absolute(STAGE_DIR)
	for entry in reader.get_files():
		var dest := STAGE_DIR.path_join(entry)
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(dest)
			continue
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var file := FileAccess.open(dest, FileAccess.WRITE)
		if file == null:
			ok = false
			break
		file.store_buffer(reader.read_file(entry))
		file.close()

	reader.close()
	return ok


func _write_apply_script() -> bool:
	var file := FileAccess.open(APPLY_PATH, FileAccess.WRITE)
	if file == null:
		return false
	var script := APPLY_TEMPLATE.format({
		"pid": OS.get_process_id(),
		"src": ProjectSettings.globalize_path(STAGE_DIR),
		"dst": OS.get_executable_path().get_base_dir(),
		"exe": OS.get_executable_path(),
	})
	file.store_string(script.replace("\r\n", "\n").replace("\n", "\r\n"))
	file.close()
	return true


func _fail(message: String) -> void:
	_progress.visible = false
	_status.text = message
	_detail.text = "Starting the installed version instead."
	await get_tree().create_timer(2.5).timeout
	_launch_game()


func _launch_game() -> void:
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


func _api_headers() -> PackedStringArray:
	return PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: FlatWorld-Updater",
	])


## Returns 1 when `a` is newer than `b`, -1 when older, 0 when equal.
static func _compare_versions(a: String, b: String) -> int:
	var left := a.lstrip("v").split(".")
	var right := b.lstrip("v").split(".")
	for i in maxi(left.size(), right.size()):
		var lv := left[i].to_int() if i < left.size() else 0
		var rv := right[i].to_int() if i < right.size() else 0
		if lv != rv:
			return 1 if lv > rv else -1
	return 0


static func _rm_rf(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var child := path.path_join(entry)
		if dir.current_is_dir():
			_rm_rf(child)
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


static func _format_size(bytes: int) -> String:
	return "%.1f MB" % (float(bytes) / 1048576.0)
