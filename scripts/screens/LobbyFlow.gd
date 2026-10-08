extends RefCounted
## LobbyFlow: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const OFFICIAL_SERVER_PORT := 7777

static func _on_connection_status(main, text: String) -> void:
	if main.quiet_connection:
		return
	if not main.local_ai_mode and main.network.client_connection_state == "idle" and main.multiplayer_screen == "session":
		main.lobby_data = {"rooms":[],"page":0,"total":0}; main._build_lobby_screen()
	if main.smoke_mode:
		print("SMOKE_STATUS %s" % text)
	if is_instance_valid(main.status_label):
		main.status_label.text = Localization.text(text)
	if main.network.client_connection_state == "idle":
		main._set_room_controls_disabled(false)
		if main.multiplayer_screen == "lobby":
			main._set_lobby_enabled(false)

static func _set_room_controls_disabled(main, disabled: bool) -> void:
	if is_instance_valid(main.connect_button_ref):
		main.connect_button_ref.disabled = disabled
	if is_instance_valid(main.join_button_ref):
		main.join_button_ref.disabled = disabled
	if is_instance_valid(main.room_code_input):
		main.room_code_input.editable = not disabled

static func _connect_for_room(main, mode: String, code: String = "") -> void:
	var normalized := code.strip_edges().to_upper()
	if not main.network.set_room_request(mode, normalized):
		main._on_connection_status(Localization.text("올바른 방 코드 6자리를 입력하세요."))
		return
	main._set_room_controls_disabled(true)
	var preset = main._active_preset()
	main.network.set_client_deck(preset.units, preset.structures)
	main.network.connect_to_candidates(main.official_connection_candidates(IP.get_local_addresses()), OFFICIAL_SERVER_PORT)

static func _on_room_created(main, code: String) -> void:
	if main.network.client_room_mode in ["lobby","session"]:
		main._build_waiting_room(code)
		return
	if is_instance_valid(main.room_code_input):
		main.room_code_input.text = code
		main.room_code_input.editable = false
		main.room_code_input.add_theme_font_size_override("font_size", 22)
		main.room_code_input.add_theme_color_override("font_color", Color("#f0d592"))
	main._on_connection_status(Localization.text("방 코드 %s · 상대가 참가하기를 기다리는 중...") % code)

static func _on_room_join_failed(main, error: String) -> void:
	if main.network.client_room_mode in ["lobby","session"]:
		main._on_connection_status(error)
		main.network.browse_rooms(main.lobby_page)
		main._set_lobby_enabled(main.network.client_connection_state == "lobby")
		return
	main.network.disconnect_from_server()
	main._on_connection_status(error)
	main._set_room_controls_disabled(false)

static func _on_opponent_left(main) -> void:
	if main.battle_active and not main.result_shown and not main.save_data.is_empty() and not main.network.client_is_spectator:
		main.save_data.stats.online_interrupted += 1; SaveData.save_data(main.save_data)
	main.local_ai_mode = false; main.battle_active = false
	main.network.disconnect_from_server()
	main.lobby_data = {"rooms":[],"page":0,"total":0}
	main._build_lobby_screen()
	main.status_label.text = "서버 연결이 끊겼습니다. 새로고침으로 다시 연결하세요."

static func _open_multiplayer(main) -> void:
	main.quiet_connection = false
	main._build_lobby_screen()
	main.network.set_room_request("session")
	var preset = main._active_preset()
	main.network.set_client_deck(preset.units,preset.structures)
	main.network.connect_to_candidates(main.official_connection_candidates(IP.get_local_addresses()),OFFICIAL_SERVER_PORT)

static func _toggle_quick_match(main) -> void:
	if main.network.client_connection_state == "queued": main.network.cancel_quick_match()
	elif main.network.start_quick_match():
		main._refresh_quick_button(); main._set_lobby_enabled(false)
		main.quick_wait_started_msec = Time.get_ticks_msec()
		_tick_quick_wait(main, main.quick_wait_started_msec)

const AI_HINT_AFTER_SECONDS := 20

static func _on_quick_match_status(main, state: String) -> void:
	main._refresh_quick_button()
	if main.multiplayer_screen != "lobby": return
	main._set_lobby_enabled(state != "queued")
	if state == "queued":
		main.quick_wait_started_msec = Time.get_ticks_msec()
		_tick_quick_wait(main, main.quick_wait_started_msec)
		return
	main.quick_wait_started_msec = 0
	if is_instance_valid(main.status_label):
		main.status_label.text = {"cancelled": "빠른 대전을 취소했습니다.", "timeout": "상대를 찾지 못했습니다. 다시 시도하거나 방을 만들어 보세요."}.get(state, "")

## Shows how long the player has been waiting and, after a while, suggests offline play.
static func _tick_quick_wait(main, started: int) -> void:
	if main.quick_wait_started_msec != started or main.network.client_connection_state != "queued":
		return
	var seconds := int((Time.get_ticks_msec() - started) / 1000)
	if is_instance_valid(main.status_label):
		var text := "상대를 찾는 중...  %d초  ·  다시 누르면 취소합니다." % seconds
		if seconds >= AI_HINT_AFTER_SECONDS:
			text += "\n아직 상대가 없어요. 기다리는 동안 AI 캠페인을 즐길 수도 있습니다."
		main.status_label.text = text
	main.get_tree().create_timer(1.0).timeout.connect(func(): _tick_quick_wait(main, started))

static func _refresh_quick_button(main) -> void:
	if not is_instance_valid(main.quick_button_ref): return
	var queued: bool = main.network.client_connection_state == "queued"
	main.quick_button_ref.text = Localization.text("✕ 대기 취소") if queued else Localization.text("⚡ 빠른 대전")
	main.quick_button_ref.disabled = not queued and main.network.client_connection_state != "lobby"

static func _set_lobby_enabled(main, enabled: bool) -> void:
	main._refresh_quick_button()
	if is_instance_valid(main.connect_button_ref): main.connect_button_ref.disabled = not enabled
	if is_instance_valid(main.lobby_rows):
		for button in main.lobby_rows.find_children("JoinRoomButton","Button",true,false): button.disabled = not enabled or not bool(button.get_meta("available",true))
		for button in main.lobby_rows.find_children("WatchRoomButton","Button",true,false): button.disabled = not enabled or not bool(button.get_meta("available",false))

static func _on_room_list(main, data: Dictionary) -> void:
	main.lobby_data = data.duplicate(true)
	if main.multiplayer_screen == "waiting" and main.network.client_connection_state == "lobby": main._build_lobby_screen()
	if main.multiplayer_screen != "lobby": return
	main._render_room_listing(data)
	main._set_lobby_enabled(main.network.client_connection_state == "lobby")
	if main.network.client_connection_state == "lobby": main.status_label.text = "참가할 방을 선택하세요."

static func _build_waiting_room(main, code: String) -> void:
	main._clear_screen()
	main.multiplayer_screen = "waiting"
	main.root_background = main._make_background()
	var panel := PanelContainer.new()
	panel.name = "WaitingRoomPanel"
	panel.position = Vector2(330,180)
	panel.size = Vector2(620,360)
	panel.add_theme_stylebox_override("panel",main._panel_style(Color("#131c29"),Color("#52658a"),24))
	main.root_background.add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",18); panel.add_child(column)
	var title := Label.new(); title.text = main.network.client_room_name; title.add_theme_font_size_override("font_size",28); column.add_child(title)
	var detail := Label.new(); detail.name = "WaitingRoomCode"; detail.text = "1 / 2  ·  방 코드 %s" % code; column.add_child(detail)
	main.status_label = Label.new(); main.status_label.text = "상대가 참가하기를 기다리는 중..."; column.add_child(main.status_label)
	var leave = main._styled_button("방 나가기",Color("#3d8f83"))
	leave.name = "LeaveRoomButton"
	leave.pressed.connect(func(): leave.disabled = true; main.network.leave_lobby_room())
	column.add_child(leave)

static func _save_nickname(main, value: String) -> void:
	value = value.strip_edges()
	if not preload("res://scripts/RoomSessions.gd").safe_text(value,16): return
	main.network.client_nickname = value
	if main.save_data.get("nickname","") != value:
		main.save_data.nickname = value; SaveData.save_data(main.save_data)

static func _choose_session_deck(main, index: int, in_room: bool) -> void:
	if index<0 or index>=main.save_data.deck_presets.size(): return
	main.save_data.last_deck = index; main.battle_preset = main._active_preset().duplicate(true); SaveData.save_data(main.save_data)
	if in_room:
		main.network.request_session_deck.rpc_id(1,main.battle_preset.units,main.battle_preset.structures)
		if is_instance_valid(main.session_deck_names): main.session_deck_names.text = main._active_deck_names()
	else:
		if main.network.client_connection_state == "lobby": main.network.request_lobby_deck.rpc_id(1,main.battle_preset.units,main.battle_preset.structures)
		var node = main.root_background.find_child("LobbyDeckNames",true,false)
		if node: node.text = main._active_deck_names()

static func _join_session_entry(main, room: Dictionary, password: String, spectator: bool) -> void:
	var accepted := false
	if room.has("state"): accepted = main.network.join_session_room(room.code,password,spectator)
	elif not spectator: accepted = main.network.join_lobby_room(room.code)
	if accepted:
		main._set_lobby_enabled(false); main.status_label.text = "방에 입장 중..."

static func _on_session_changed(main, data: Dictionary) -> void:
	if data.is_empty(): return
	var member = main._self_session_member()
	if data.phase == "waiting" or (data.phase == "finished" and member.get("returned",false)):
		main.resuming_battle_ui = false; main.network_paused = false
		if main.multiplayer_screen != "session": MultiplayerUI.room(main)
		else: MultiplayerUI.update_room(main,data)
	elif main.multiplayer_screen == "session": MultiplayerUI.update_room(main,data)

static func _on_session_error(main, text: String) -> void:
	main._refresh_quick_button()
	if is_instance_valid(main.status_label): main.status_label.text = text
	if main.multiplayer_screen == "lobby": main._set_lobby_enabled(main.network.client_connection_state == "lobby")

static func _on_session_closed(main, text: String) -> void:
	main.network_paused = false; main.resuming_battle_ui = false
	main.local_ai_mode = false; main.battle_active = false; main.battle_preset.clear()
	main.lobby_data = {"rooms":[],"page":0,"total":0}
	main._build_lobby_screen()
	if not text.is_empty(): main.status_label.text = text

static func _send_session_chat(main) -> void:
	if not is_instance_valid(main.session_chat_input) or main.network.client_session.is_empty(): return
	var text = main.session_chat_input.text.strip_edges()
	if not preload("res://scripts/RoomSessions.gd").safe_text(text,160): return
	var now := Time.get_ticks_msec()
	if now-main.last_chat_sent_msec<750: return
	main.last_chat_sent_msec = now
	main.network.request_session_chat.rpc_id(1,text); main.session_chat_input.text = ""

static func _on_spectate_started(main) -> void:
	main.local_ai_mode = false; main.campaign_mode = false; main.own_side = 0; main.multiplayer_screen = ""
	var players: Array = main.network.client_session.get("members",[]).filter(func(member): return member.role=="player")
	if not players.is_empty(): main.battle_preset = players[0].deck.duplicate(true)
	main._build_battle_screen()

static func _on_latency_updated(main, milliseconds: int) -> void:
	if not is_instance_valid(main.latency_label): return
	main.latency_label.text="지연 %dms"%milliseconds if milliseconds>=0 else "지연 측정 중"
	main.latency_label.tone = UIKit.DANGER if milliseconds>200 else (UIKit.GOLD if milliseconds>120 else UIKit.TEAL); main.latency_label.add_theme_color_override("font_color",main.latency_label.tone.lightened(0.5)); main.latency_label.refresh_style()

static func _on_reconnect_status(main, active: bool, remaining: float) -> void:
	if active:
		main.resuming_battle_ui = true
		if not main.network_paused:
			main.network_paused = true; main._refresh_purchase_buttons(main.latest_resources)
		var text := "연결 복구 중 · %d초"%ceili(remaining)
		if is_instance_valid(main.recovery_label) and main.recovery_label.text!=text: main.recovery_label.text=text
		elif is_instance_valid(main.status_label): main.status_label.text=text
	elif is_instance_valid(main.recovery_label): main.recovery_label.text=""

static func _on_recovery_changed(main, data: Dictionary) -> void:
	if main.local_ai_mode: return
	var paused: bool = data.get("paused",false) or main.network.client_reconnecting
	if main.network_paused!=paused:
		main.network_paused=paused; main._refresh_purchase_buttons(main.latest_resources)
	if is_instance_valid(main.recovery_label) and not main.network.client_reconnecting:
		main.recovery_label.text="상대 연결 복구 대기 · %d초"%ceili(float(data.get("reconnect_remaining",0))) if paused else ""
