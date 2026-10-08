extends Control
## The assist server's window: connection, which kinds of work to accept, what is being computed right now, the
## state of the main server's queue, the finished results and a live log. Runs as the game's "--assist" mode.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const HpBar = preload("res://scripts/ui/HpBar.gd")
const AssistWorker = preload("res://scripts/assist/AssistWorker.gd")
const JobRunner = preload("res://scripts/jobs/JobRunner.gd")
const LogBuffer = preload("res://scripts/assist/LogBuffer.gd")
const Localization = preload("res://scripts/Localization.gd")

const CONFIG_PATH := "user://assist.json"
const REFRESH_SECONDS := 0.5
const LEVEL_COLORS := {"info": "#c9d3ea", "warn": "#ffd36a", "error": "#ff7b8d"}
## What the window offers. `ready` false = listed so the plan is visible, but not available yet.
const CAPABILITY_ROWS := [
	{"id": "balance", "label": "밸런스 실험", "ready": true},
	{"id": "replay", "label": "리플레이 검증", "ready": true},
	{"id": "selftest", "label": "연결 점검", "ready": true},
	{"id": "stats", "label": "통계 재계산 (준비 중)", "ready": false},
	{"id": "backup", "label": "데이터 백업 (준비 중)", "ready": false},
	{"id": "archive", "label": "리플레이 보관 (준비 중)", "ready": false},
]

var worker
var config_path := CONFIG_PATH
var address_input: LineEdit
var token_input: LineEdit
var name_input: LineEdit
var connect_button: Button
var status_label: Label
var uptime_label: Label
var cap_boxes: Dictionary = {}
var core_slider: HSlider
var core_label: Label
var auto_box: CheckButton
var running_rows: VBoxContainer
var queue_rows: VBoxContainer
var result_rows: VBoxContainer
var queue_summary: Label
var log_view: RichTextLabel
var log_filter: OptionButton
var pause_button: Button
var wrap_button: Button
var stop_button: Button
var job_type: OptionButton
var job_stage: SpinBox
var job_matches: SpinBox
var job_button: Button
var refresh_elapsed := 0.0
var quitting := false

func setup(network) -> void:
	name = "AssistApp"
	position = Vector2.ZERO
	size = Vector2(1280, 720)
	worker = AssistWorker.new()
	worker.name = "AssistWorker"
	add_child(worker)
	worker.setup(network)
	worker.journal.path = "user://assist.log" if config_path == CONFIG_PATH else ""
	_load_config()
	_build()
	_apply_config_to_widgets()
	worker.journal.line_added.connect(_on_log_line)
	worker.state_changed.connect(func(_state): _refresh())
	worker.job_result.connect(_on_job_result)
	worker.stopped.connect(_on_stopped)
	worker.journal.add("info", "보조 서버를 시작했습니다. 주소와 토큰을 확인하고 연결을 눌러 주세요.")
	_refresh()
	if bool(worker.config.auto_reconnect) and not String(worker.config.token).is_empty() and bool(auto_box.button_pressed):
		_connect_pressed()

# ---------- config ----------

func _load_config() -> void:
	if not FileAccess.file_exists(config_path):
		worker.config.cores = clampi(OS.get_processor_count() / 2, 1, 64)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not parsed is Dictionary:
		return
	if parsed.get("address") is String:
		worker.config.candidates = [String(parsed.address)]
	if parsed.get("token") is String:
		worker.config.token = parsed.token
	if parsed.get("name") is String and not String(parsed.name).is_empty():
		worker.config.name = String(parsed.name).left(24)
	if parsed.get("capabilities") is Array:
		worker.config.capabilities = parsed.capabilities.filter(func(entry): return entry is String)
	worker.config.cores = clampi(int(parsed.get("cores", 2)), 1, 64)
	worker.config.auto_reconnect = bool(parsed.get("auto_connect", true))

func _save_config() -> void:
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"address": String(worker.config.candidates[0]) if not worker.config.candidates.is_empty() else "", "token": worker.config.token,
		"name": worker.config.name, "capabilities": worker.config.capabilities, "cores": worker.config.cores, "auto_connect": worker.config.auto_reconnect}))
	file.close()

func _apply_config_to_widgets() -> void:
	address_input.text = String(worker.config.candidates[0]) if not worker.config.candidates.is_empty() else ""
	token_input.text = String(worker.config.token)
	name_input.text = String(worker.config.name)
	for id in cap_boxes:
		cap_boxes[id].button_pressed = worker.config.capabilities.has(id)
	core_slider.max_value = maxi(1, OS.get_processor_count())
	core_slider.value = clampi(int(worker.config.cores), 1, int(core_slider.max_value))
	auto_box.button_pressed = bool(worker.config.auto_reconnect)
	_update_core_label()

func _read_widgets() -> void:
	var host := address_input.text.strip_edges()
	var port := NetworkController.DEFAULT_PORT
	if host.contains(":") and host.rsplit(":", true, 1)[1].is_valid_int():
		port = int(host.rsplit(":", true, 1)[1])
		host = host.rsplit(":", true, 1)[0]
	worker.config.candidates = [host]
	worker.config.port = port
	worker.config.token = token_input.text.strip_edges()
	worker.config.name = name_input.text.strip_edges() if not name_input.text.strip_edges().is_empty() else "보조 서버"
	worker.config.cores = int(core_slider.value)
	worker.config.auto_reconnect = auto_box.button_pressed
	worker.config.capabilities = cap_boxes.keys().filter(func(id): return cap_boxes[id].button_pressed)

# ---------- building the window ----------

func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("#0b1020")
	background.size = size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var column := VBoxContainer.new()
	column.position = Vector2(18, 12)
	column.size = Vector2(1244, 696)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	column.add_child(_header())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	body.add_child(_left_panel())
	body.add_child(_centre_panel())
	column.add_child(_log_panel())
	column.add_child(_footer())

func _card(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, UIKit.EDGE_SOFT, 12, 1.0, 0.3, Color(0, 0, 0, 0), 0.08), 10, 6))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	panel.add_child(inner)
	var heading := Label.new()
	heading.text = Localization.text(title)
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", UIKit.GOLD)
	inner.add_child(heading)
	panel.set_meta("inner", inner)
	return inner

func _wrap(inner: VBoxContainer) -> Control:
	return inner.get_parent()

func _header() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, UIKit.EDGE, 12, 1.0, 0.4, Color(0, 0, 0, 0), 0.08), 16, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var title := Label.new()
	title.text = "KEEPFALL 보조 서버"
	UIKit.display(title, 24, UIKit.GOLD)
	row.add_child(title)
	status_label = Label.new()
	status_label.name = "AssistStatus"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_font_size_override("font_size", 15)
	row.add_child(status_label)
	uptime_label = Label.new()
	uptime_label.name = "AssistUptime"
	uptime_label.add_theme_font_size_override("font_size", 13)
	uptime_label.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	row.add_child(uptime_label)
	return panel

func _left_panel() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 360
	column.add_theme_constant_override("separation", 8)
	var connection := _card("메인 서버 연결")
	address_input = _line(connection, "AssistAddress", "주소 (예: 192.168.0.5 또는 주소:7777)")
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 6)
	connection.add_child(pair)
	token_input = _line(pair, "AssistToken", "토큰")
	token_input.secret = true
	token_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input = _line(pair, "AssistName", "컴퓨터 이름")
	name_input.max_length = 24
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var connect_row := HBoxContainer.new()
	connect_row.add_theme_constant_override("separation", 6)
	connection.add_child(connect_row)
	auto_box = CheckButton.new()
	auto_box.name = "AutoConnect"
	auto_box.text = Localization.text("자동 연결")
	auto_box.add_theme_font_size_override("font_size", 13)
	auto_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_box.toggled.connect(func(_on): _read_widgets(); _save_config())
	connect_row.add_child(auto_box)
	connect_button = _button("연결", "AssistConnectButton", UIKit.ACCENT, true)
	connect_button.custom_minimum_size = Vector2(120, 36)
	connect_button.pressed.connect(_connect_pressed)
	connect_row.add_child(connect_button)
	column.add_child(_wrap(connection))
	var capabilities := _card("받을 작업 선택")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 0)
	capabilities.add_child(grid)
	for row in CAPABILITY_ROWS:
		var box := CheckButton.new()
		box.name = "Cap_" + String(row.id)
		box.text = Localization.text(String(row.label))
		box.add_theme_font_size_override("font_size", 13)
		box.disabled = not bool(row.ready)
		box.toggled.connect(func(_on): _read_widgets(); _save_config(); _capabilities_changed())
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(box)
		if bool(row.ready):
			cap_boxes[String(row.id)] = box
	core_label = Label.new()
	core_label.name = "CoreLabel"
	core_label.add_theme_font_size_override("font_size", 13)
	capabilities.add_child(core_label)
	core_slider = HSlider.new()
	core_slider.name = "CoreSlider"
	core_slider.min_value = 1
	core_slider.step = 1
	core_slider.value_changed.connect(func(_value): _update_core_label(); _read_widgets(); _save_config())
	capabilities.add_child(core_slider)
	var note := Label.new()
	note.text = Localization.text("선택한 종류의 작업만 메인 서버가 맡깁니다. 연결 중에 바꾸면 다음 연결부터 적용됩니다.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	capabilities.add_child(note)
	column.add_child(_wrap(capabilities))
	return column

func _line(parent: Control, node_name: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = node_name
	edit.placeholder_text = Localization.text(placeholder)
	edit.custom_minimum_size.y = 32
	edit.text_submitted.connect(func(_text): _read_widgets(); _save_config())
	edit.focus_exited.connect(func(): _read_widgets(); _save_config())
	parent.add_child(edit)
	return edit

func _button(text: String, node_name: String, color: Color, primary: bool = false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = Localization.text(text)
	button.custom_minimum_size.y = 36
	UIKit.style_button(button, color, primary, 14)
	return button

func _centre_panel() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	var running := _card("지금 하는 일")
	running_rows = VBoxContainer.new()
	running_rows.name = "RunningRows"
	running_rows.add_theme_constant_override("separation", 4)
	running.add_child(running_rows)
	column.add_child(_wrap(running))
	var queue := _card("메인 서버의 작업 목록")
	queue_summary = Label.new()
	queue_summary.name = "QueueSummary"
	queue_summary.add_theme_font_size_override("font_size", 13)
	queue.add_child(queue_summary)
	queue_rows = VBoxContainer.new()
	queue_rows.name = "QueueRows"
	queue_rows.add_theme_constant_override("separation", 3)
	queue.add_child(queue_rows)
	column.add_child(_wrap(queue))
	var order := _card("새 작업 요청")
	var order_row := HBoxContainer.new()
	order_row.add_theme_constant_override("separation", 8)
	order.add_child(order_row)
	job_type = OptionButton.new()
	job_type.name = "NewJobType"
	job_type.add_item(Localization.text("밸런스 실험: 모든 병력 조합"), 0)
	job_type.add_item(Localization.text("연결 점검"), 1)
	job_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	order_row.add_child(job_type)
	var stage_label := Label.new()
	stage_label.text = Localization.text("단계")
	order_row.add_child(stage_label)
	job_stage = SpinBox.new()
	job_stage.name = "NewJobStage"
	job_stage.min_value = ServerAI.MIN_STAGE
	job_stage.max_value = ServerAI.MAX_STAGE
	job_stage.value = 3
	order_row.add_child(job_stage)
	var matches_label := Label.new()
	matches_label.text = Localization.text("판수")
	order_row.add_child(matches_label)
	job_matches = SpinBox.new()
	job_matches.name = "NewJobMatches"
	job_matches.min_value = 1
	job_matches.max_value = JobRunner.MAX_MATCHES
	job_matches.value = 20
	order_row.add_child(job_matches)
	job_button = _button("요청", "NewJobButton", UIKit.TEAL, false)
	job_button.custom_minimum_size.x = 80
	job_button.pressed.connect(_order_job)
	order_row.add_child(job_button)
	column.add_child(_wrap(order))
	var results := _card("최근 결과")
	result_rows = VBoxContainer.new()
	result_rows.name = "ResultRows"
	result_rows.add_theme_constant_override("separation", 2)
	results.add_child(result_rows)
	var result_wrap := _wrap(results)
	result_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(result_wrap)
	return column

func _log_panel() -> Control:
	var log_card := _card("실시간 로그")
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	log_card.add_child(tools)
	log_filter = OptionButton.new()
	log_filter.name = "LogFilter"
	log_filter.add_item(Localization.text("전체"), 0)
	log_filter.add_item(Localization.text("경고 이상"), 1)
	log_filter.add_item(Localization.text("오류만"), 2)
	log_filter.item_selected.connect(func(_index): _rebuild_log())
	tools.add_child(log_filter)
	var copy := _button("복사", "LogCopyButton", UIKit.TEAL, false)
	copy.custom_minimum_size = Vector2(80, 30)
	copy.pressed.connect(func(): DisplayServer.clipboard_set(worker.journal.as_text(["info", "warn", "error"][log_filter.selected])))
	tools.add_child(copy)
	var folder := _button("로그 폴더", "LogFolderButton", UIKit.GOLD_DEEP, false)
	folder.custom_minimum_size = Vector2(100, 30)
	folder.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path("user://")))
	tools.add_child(folder)
	log_view = RichTextLabel.new()
	log_view.name = "AssistLog"
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_view.custom_minimum_size.y = 120
	log_view.add_theme_font_size_override("normal_font_size", 12)
	log_card.add_child(log_view)
	return _wrap(log_card)

func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pause_button = _button("일시정지", "PauseButton", UIKit.ACCENT, false)
	pause_button.pressed.connect(func(): worker.set_paused(not worker.paused); _refresh())
	row.add_child(pause_button)
	wrap_button = _button("종료 (마무리 후)", "WrapUpButton", UIKit.GOLD_DEEP, true)
	wrap_button.pressed.connect(func(): worker.begin_wrap_up())
	row.add_child(wrap_button)
	stop_button = _button("즉시 종료", "StopNowButton", UIKit.DANGER, false)
	stop_button.pressed.connect(_confirm_stop_now)
	row.add_child(stop_button)
	for button in [pause_button, wrap_button, stop_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row

# ---------- behaviour ----------

func _update_core_label() -> void:
	core_label.text = Localization.text("사용할 CPU 코어  %d / %d") % [int(core_slider.value), int(core_slider.max_value)]

func _capabilities_changed() -> void:
	if worker.is_online():
		worker.journal.add("info", "받을 작업 종류를 바꿨습니다. 다음 연결부터 적용됩니다.")

func _connect_pressed() -> void:
	if worker.state in ["connecting", "joining", "idle", "working", "paused", "wrapping"]:
		worker.begin_wrap_up("연결을 해제합니다")
		return
	_read_widgets()
	_save_config()
	if String(worker.config.token).is_empty():
		worker.journal.add("warn", "토큰을 입력해 주세요. 메인 서버의 CATWAR_ASSIST_TOKEN과 같아야 합니다.")
		return
	if cap_boxes.values().all(func(box): return not box.button_pressed):
		worker.journal.add("warn", "받을 작업을 하나 이상 선택해 주세요.")
		return
	worker.start()

func _order_job() -> void:
	if job_type.selected == 1:
		worker.submit_job("selftest", {"chunks": 8}, "연결 점검")
		return
	worker.submit_job("balance", {"stage": int(job_stage.value), "matches": int(job_matches.value)}, "밸런스 실험 · %d단계 · 판수 %d" % [int(job_stage.value), int(job_matches.value)])

func _confirm_stop_now() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "StopNowDialog"
	dialog.title = Localization.text("즉시 종료")
	dialog.dialog_text = Localization.text("진행 중인 조각을 버리고 바로 종료합니다. 메인 서버가 그 조각을 다시 배정합니다. 계속할까요?")
	dialog.ok_button_text = Localization.text("즉시 종료")
	dialog.cancel_button_text = Localization.text("취소")
	dialog.confirmed.connect(func(): worker.stop_now(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(460, 150))

func _on_job_result(id: int, result: Dictionary) -> void:
	worker.journal.add("info", "작업 #%d 완료 · 결과를 받았습니다." % id)
	_show_result(id, result)

func _show_result(id: int, result: Dictionary) -> void:
	for child in result_rows.get_children():
		child.queue_free()
	var heading := Label.new()
	heading.text = Localization.text("작업 #%d") % id
	heading.add_theme_font_size_override("font_size", 13)
	result_rows.add_child(heading)
	if result.has("rows"):
		for index in mini(8, result.rows.size()):
			var row: Dictionary = result.rows[index]
			var line := Label.new()
			line.text = "%d. %s   승률 %d%%   %d판" % [index + 1, " · ".join(PackedStringArray(row.deck.map(func(kind): return String(BattleModel.UNIT_NAMES.get(kind, kind))))), roundi(float(row.win_rate) * 100.0), int(row.matches)]
			line.add_theme_font_size_override("font_size", 12)
			result_rows.add_child(line)
	else:
		var summary := Label.new()
		summary.text = JSON.stringify(result)
		summary.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		summary.add_theme_font_size_override("font_size", 12)
		result_rows.add_child(summary)

func _on_stopped() -> void:
	_refresh()
	if quitting:
		get_tree().quit()

## The window's close button: wrap up first, quit when the helper has said goodbye.
func request_close() -> void:
	if worker.state in ["offline", "stopped"]:
		get_tree().quit()
		return
	quitting = true
	worker.begin_wrap_up("창을 닫았습니다")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and worker != null:
		request_close()

# ---------- showing state ----------

func _process(delta: float) -> void:
	refresh_elapsed += delta
	if refresh_elapsed >= REFRESH_SECONDS:
		refresh_elapsed = 0.0
		_refresh()

const STATE_TEXT := {"offline": "● 연결 안 됨", "connecting": "● 연결하는 중...", "joining": "● 로그인하는 중...", "idle": "● 연결됨 · 대기 중",
	"working": "● 연결됨 · 작업 중", "paused": "● 연결됨 · 일시정지", "wrapping": "● 마무리하는 중...", "stopped": "● 종료됨"}

func _refresh() -> void:
	if worker == null or status_label == null:
		return
	var online: bool = worker.is_online()
	var tone := UIKit.SUCCESS if online and worker.state != "wrapping" else (UIKit.GOLD if worker.state in ["connecting", "joining", "wrapping"] else UIKit.TEXT_MUTED)
	status_label.text = Localization.text(String(STATE_TEXT.get(worker.state, worker.state)))
	if not worker.last_error.is_empty() and worker.state == "offline":
		status_label.text += "  ·  " + worker.last_error
	status_label.add_theme_color_override("font_color", tone)
	var seconds := int(float(Time.get_ticks_msec()) / 1000.0 - float(worker.stats.started))
	uptime_label.text = Localization.text("가동 %02d:%02d:%02d  ·  처리한 조각 %d개") % [seconds / 3600, (seconds / 60) % 60, seconds % 60, int(worker.stats.chunks)]
	connect_button.text = Localization.text("연결 해제" if online or worker.state == "connecting" else "연결")
	pause_button.text = Localization.text("재개" if worker.paused else "일시정지")
	pause_button.disabled = not online or worker.state == "wrapping"
	wrap_button.disabled = worker.state in ["offline", "stopped"]
	stop_button.disabled = worker.state in ["offline", "stopped"]
	job_button.disabled = not online or worker.state == "wrapping"
	_refresh_running()
	_refresh_queue()

func _refresh_running() -> void:
	for child in running_rows.get_children():
		child.queue_free()
	var list: Array = worker.running()
	if list.is_empty():
		var idle := Label.new()
		idle.text = Localization.text("하고 있는 작업이 없습니다.")
		idle.add_theme_font_size_override("font_size", 13)
		idle.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
		running_rows.add_child(idle)
		return
	for entry in list:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = "#%d · 조각 %d · %s" % [int(entry.job), int(entry.chunk) + 1, JobRunner.title_for(String(entry.type))]
		label.custom_minimum_size.x = 300
		label.add_theme_font_size_override("font_size", 13)
		line.add_child(label)
		var bar := HpBar.new()
		bar.color = UIKit.TEAL
		bar.pulse_below = 0.0
		bar.show_ticks = false
		bar.max_value = 1.0
		bar.value = float(entry.fraction)
		bar.custom_minimum_size = Vector2(240, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(bar)
		running_rows.add_child(line)

func _refresh_queue() -> void:
	for child in queue_rows.get_children():
		child.queue_free()
	var data: Dictionary = worker.overview
	if data.is_empty():
		queue_summary.text = Localization.text("연결되면 메인 서버의 작업 목록이 여기에 나옵니다.")
		return
	var totals: Dictionary = data.totals
	var helpers: Array = data.assists
	queue_summary.text = Localization.text("대기 %d · 진행 %d · 완료 %d 조각   |   연결된 도우미 %d대") % [int(totals.pending), int(totals.leased), int(totals.done), helpers.size()]
	for job in data.jobs:
		var line := Label.new()
		line.text = "#%d  %s   %d / %d 조각%s" % [int(job.id), String(job.title), int(job.done_chunks), int(job.total), "  ✓" if bool(job.done) else ""]
		line.add_theme_font_size_override("font_size", 12)
		line.add_theme_color_override("font_color", UIKit.SUCCESS if bool(job.done) else UIKit.TEXT)
		queue_rows.add_child(line)

func _on_log_line(entry: Dictionary) -> void:
	if log_view != null and _passes_filter(entry):
		_append_log(entry)

func _passes_filter(entry: Dictionary) -> bool:
	return LogBuffer.LEVELS.find(String(entry.level)) >= log_filter.selected

func _append_log(entry: Dictionary) -> void:
	log_view.append_text("[color=#7d879b]%s[/color]  [color=%s]%s[/color]\n" % [entry.time, LEVEL_COLORS.get(String(entry.level), "#c9d3ea"), _escape(String(entry.text))])

func _escape(text: String) -> String:
	return text.replace("[", "[lb]")

func _rebuild_log() -> void:
	log_view.clear()
	for entry in worker.journal.lines:
		if _passes_filter(entry):
			_append_log(entry)
