extends RefCounted

const UIKit = preload("res://scripts/ui/UIKit.gd")

const INK := Color("#101a29")
const EDGE := Color("#2b415c")
const MUTED := Color("#92a3bc")
const GOLD := Color("#f0d592")

static func label(text: String, size: int = 16, color: Color = Color.WHITE) -> Label:
	var node := Label.new(); node.text = text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	if size >= 24: node.add_theme_font_override("font",UIKit.display_font())
	return node

static func panel(main, parent: Node, name: String, bounds: Rect2, padding: int = 24) -> VBoxContainer:
	var box := PanelContainer.new(); box.name = name; box.position = bounds.position; box.size = bounds.size
	box.add_theme_stylebox_override("panel",UIKit.with_margins(UIKit.panel_box(),padding,padding)); parent.add_child(box)
	UIKit.reveal(box,0.28,10.0)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation",12); box.add_child(content)
	return content

static func button(main, parent: Node, text: String, name: String, callback: Callable, primary: bool = false) -> Button:
	var node: Button = main._styled_button(text,Color("#6375d2") if primary else Color("#3d647d"),primary)
	node.name = name; node.custom_minimum_size.y = 44; node.pressed.connect(callback); parent.add_child(node)
	return node

static func browser(main) -> void:
	main._clear_screen(); main.multiplayer_screen = "lobby"; main.battle_active = false
	main.root_background = main._make_background()
	var backdrop := MenuBackdrop.new(); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.modulate = Color(0.45,0.5,0.65,0.24); main.root_background.add_child(backdrop)
	var column := panel(main,main.root_background,"RoomBrowserPanel",Rect2(64,28,1152,664))
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation",12); column.add_child(header)
	var heading := VBoxContainer.new(); heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(heading)
	heading.add_child(label("멀티플레이",30,GOLD)); heading.add_child(label("대기방과 진행 중인 전투",13,MUTED))
	button(main,header,"새로고침","RefreshRoomsButton",func():
		if main.network.client_connection_state == "idle": main._open_multiplayer()
		else: main.network.browse_rooms(main.lobby_page))
	main.connect_button_ref = button(main,header,"＋ 방 만들기","CreateRoomButton",main._show_create_room_dialog,true)
	column.add_child(HSeparator.new())
	var body := HBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",20); column.add_child(body)
	var list_column := VBoxContainer.new(); list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list_column.add_theme_constant_override("separation",10); body.add_child(list_column)
	list_column.add_child(label("공개 방 목록",16,GOLD))
	var filters := HBoxContainer.new(); filters.name = "RoomFilters"; filters.add_theme_constant_override("separation",8); list_column.add_child(filters)
	var filter_group := ButtonGroup.new()
	for entry in [["all","전체"],["waiting","대기 중"],["live","라이브 전투"]]:
		var chip: Button = main._styled_button(String(entry[1]),UIKit.ACCENT,false)
		chip.name = "RoomFilter_" + String(entry[0]); chip.toggle_mode = true; chip.button_group = filter_group; chip.custom_minimum_size = Vector2(120,36)
		chip.set_pressed_no_signal(main.lobby_filter == String(entry[0]))
		var filter_id := String(entry[0])
		chip.pressed.connect(func(): main.lobby_filter = filter_id; main.network.set_room_filter(filter_id))
		filters.add_child(chip)
	var scroll := ScrollContainer.new(); scroll.name = "RoomListScroll"; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; list_column.add_child(scroll)
	main.lobby_rows = VBoxContainer.new(); main.lobby_rows.name = "RoomRows"; main.lobby_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL; main.lobby_rows.add_theme_constant_override("separation",10); scroll.add_child(main.lobby_rows)
	var side := VBoxContainer.new(); side.custom_minimum_size.x = 238; side.add_theme_constant_override("separation",12); body.add_child(side)
	side.add_child(label("내 플레이어",16,GOLD))
	var nickname := LineEdit.new(); nickname.name = "NicknameInput"; nickname.max_length = 16; nickname.text = main.network.client_nickname; nickname.placeholder_text = "닉네임"; nickname.custom_minimum_size.y = 44; side.add_child(nickname)
	nickname.focus_exited.connect(func(): main._save_nickname(nickname.text))
	nickname.text_submitted.connect(func(value): main._save_nickname(value); nickname.release_focus())
	side.add_child(label("출전 덱",13,MUTED))
	var selector := deck_selector(main); selector.name = "LobbyDeckSelector"; side.add_child(selector)
	selector.item_selected.connect(func(index): main._choose_session_deck(index,false))
	var units := label(main._active_deck_names(),14,MUTED); units.name = "LobbyDeckNames"; units.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; side.add_child(units)
	var space := Control.new(); space.size_flags_vertical = Control.SIZE_EXPAND_FILL; side.add_child(space)
	main.quick_button_ref = button(main,side,"⚡ 빠른 대전","QuickMatchButton",main._toggle_quick_match,true)
	main.quick_button_ref.custom_minimum_size.y = 56
	side.add_child(label("버튼 하나로 상대를 자동 매칭합니다.",12,MUTED))
	side.add_child(label("잠긴 방은 비밀번호로 입장합니다.",12,MUTED))
	main.status_label = label("서버에 연결 중...",13,MUTED); main.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(main.status_label)
	var footer := HBoxContainer.new(); footer.add_theme_constant_override("separation",10); column.add_child(footer)
	button(main,footer,"← 메인 메뉴","LobbyBackButton",func(): main.network.disconnect_from_server(); main._build_connect_screen())
	var stretch := Control.new(); stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL; footer.add_child(stretch)
	main.lobby_previous_button = button(main,footer,"이전","PreviousRoomsButton",func(): main.network.browse_rooms(main.lobby_page-1))
	main.lobby_page_label = label("1 / 1",14,MUTED); main.lobby_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; main.lobby_page_label.custom_minimum_size.x = 100; footer.add_child(main.lobby_page_label)
	main.lobby_next_button = button(main,footer,"다음","NextRoomsButton",func(): main.network.browse_rooms(main.lobby_page+1))
	main._render_room_listing(main.lobby_data); main._set_lobby_enabled(main.network.client_connection_state in ["lobby","queued"])
	main.updater.set_safe_to_update(false)

static func deck_selector(main) -> OptionButton:
	var selector := OptionButton.new(); selector.custom_minimum_size = Vector2(0,44)
	for preset in main.save_data.deck_presets: selector.add_item(String(preset.name))
	selector.select(int(main.save_data.last_deck)); return selector

static func listing(main, data: Dictionary) -> void:
	if not is_instance_valid(main.lobby_rows): return
	for child in main.lobby_rows.get_children(): main.lobby_rows.remove_child(child); child.queue_free()
	main.lobby_page = int(data.page); main.lobby_total = int(data.total)
	var pages := maxi(1,(main.lobby_total+NetworkController.ROOM_LIST_PAGE_SIZE-1)/NetworkController.ROOM_LIST_PAGE_SIZE)
	main.lobby_page_label.text = "%d / %d · %d개" % [main.lobby_page+1,pages,main.lobby_total]
	main.lobby_previous_button.disabled = main.lobby_page <= 0
	main.lobby_next_button.disabled = main.lobby_page+1 >= pages
	if data.rooms.is_empty():
		var empty := VBoxContainer.new(); empty.name = "NoRoomsLabel"; empty.custom_minimum_size.y = 230; empty.add_theme_constant_override("separation",12); main.lobby_rows.add_child(empty)
		var icon := label("◇",56,GOLD); icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; empty.add_child(icon)
		var title := label("첫 번째 방을 열어 보세요",22); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; empty.add_child(title)
		var note := label("대기 중인 방이 없습니다. 오른쪽 위에서 방을 만들 수 있습니다.",13,MUTED); note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; empty.add_child(note)
	for room in data.rooms:
		var card := PanelContainer.new(); card.name = "RoomRow"; card.custom_minimum_size.y = 78
		card.add_theme_stylebox_override("panel",UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI,UIKit.SURFACE,Color(EDGE.r,EDGE.g,EDGE.b,0.8),12,1.0,0.35,Color(0,0,0,0),0.08),16,10)); main.lobby_rows.add_child(card)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation",12); card.add_child(row)
		var details := VBoxContainer.new(); details.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(details)
		var name_label := label(("▣  " if room.get("locked",false) else "◇  ")+String(room.name),18); name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; details.add_child(name_label)
		var phase := String(room.get("state","waiting"))
		var phase_text := "전투 중" if phase == "playing" else ("결과 확인 중" if phase == "finished" else "대기 중")
		var meta_row := HBoxContainer.new(); meta_row.add_theme_constant_override("separation",10); details.add_child(meta_row)
		var phase_tone := UIKit.DANGER if phase == "playing" else (UIKit.GOLD if phase == "finished" else UIKit.SUCCESS)
		var chip := PanelContainer.new(); chip.add_theme_stylebox_override("panel",UIKit.with_margins(UIKit.box(Color(phase_tone.r,phase_tone.g,phase_tone.b,0.22),Color(phase_tone.r,phase_tone.g,phase_tone.b,0.10),Color(phase_tone.r,phase_tone.g,phase_tone.b,0.8),10,1.0,0.0,Color(0,0,0,0),0.0),10,2)); meta_row.add_child(chip)
		chip.add_child(label("●  "+phase_text,12,phase_tone.lightened(0.35)))
		var pips := label("●".repeat(int(room.players))+"○".repeat(maxi(0,2-int(room.players))),12,UIKit.TEXT_MUTED); meta_row.add_child(pips)
		meta_row.add_child(label("%s  ·  %d / 2  ·  관전 %d" % [phase_text,int(room.players),int(room.get("spectators",0))],12,MUTED))
		if room.has("live"):
			card.custom_minimum_size.y = 108
			var live: Dictionary = room.live
			var seconds := int(float(live.elapsed))
			var live_row := HBoxContainer.new(); live_row.name = "RoomLiveInfo"; live_row.add_theme_constant_override("separation",4); details.add_child(live_row)
			live_row.add_child(label("%s  vs  %s  ·  %02d:%02d  " % [String(live.names[0]),String(live.names[1]),seconds/60,seconds%60],13,UIKit.TEXT))
			for side in 2:
				for kind in live.units[side]:
					var icon := TextureRect.new(); icon.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
					icon.custom_minimum_size = Vector2(22,30); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					live_row.add_child(icon)
				if side == 0: live_row.add_child(label(" VS ",11,UIKit.TEXT_DIM))
		var join := button(main,row,"참가","JoinRoomButton",func(): main._prompt_room_entry(room,false),true); join.set_meta("room_code",room.code)
		join.set_meta("available",phase=="waiting" and int(room.players)<2)
		join.disabled = main.network.client_connection_state != "lobby" or not bool(join.get_meta("available"))
		var watch := button(main,row,"관전","WatchRoomButton",func(): main._prompt_room_entry(room,true)); watch.set_meta("available",room.has("state")); watch.disabled = not room.has("state") or main.network.client_connection_state != "lobby"

static func room(main) -> void:
	main._clear_screen(); main.multiplayer_screen = "session"; main.battle_active = false; main.result_shown = false
	main.root_background = main._make_background()
	var column := panel(main,main.root_background,"SessionRoomPanel",Rect2(64,28,1152,664))
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation",12); column.add_child(header)
	main.session_title = label("대기실",28,GOLD); main.session_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(main.session_title)
	var code_chip := Button.new(); code_chip.name = "SessionRoomCode"; code_chip.focus_mode = Control.FOCUS_NONE; code_chip.tooltip_text = "클릭하면 방 코드를 복사합니다"
	UIKit.style_button(code_chip,UIKit.TEAL,false,14); code_chip.custom_minimum_size = Vector2(190,44)
	code_chip.pressed.connect(func(): DisplayServer.clipboard_set(String(main.network.client_session.get("code",""))); code_chip.text = "복사됨 ✓")
	header.add_child(code_chip)
	button(main,header,"방 나가기","LeaveSessionButton",func(): main.network.request_session_leave.rpc_id(1))
	column.add_child(HSeparator.new())
	var body := HBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",20); column.add_child(body)
	var left := VBoxContainer.new(); left.size_flags_horizontal = Control.SIZE_EXPAND_FILL; left.add_theme_constant_override("separation",14); body.add_child(left)
	left.add_child(label("출전 플레이어",16,GOLD))
	main.session_roster = VBoxContainer.new(); main.session_roster.add_theme_constant_override("separation",12); left.add_child(main.session_roster)
	main.session_spectators = label("관전 0명",13,MUTED); main.session_spectators.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; left.add_child(main.session_spectators)
	left.add_child(label("내 출전 덱",13,MUTED))
	main.session_deck_selector = deck_selector(main); left.add_child(main.session_deck_selector)
	main.session_deck_selector.item_selected.connect(func(index): main._choose_session_deck(index,true))
	main.session_deck_names = label(main._active_deck_names(),14,MUTED); main.session_deck_names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; left.add_child(main.session_deck_names)
	var fill := Control.new(); fill.size_flags_vertical = Control.SIZE_EXPAND_FILL; left.add_child(fill)
	main.status_label = label("준비 후 방장이 전투를 시작합니다.",13,MUTED); main.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; left.add_child(main.status_label)
	var actions := HBoxContainer.new(); actions.add_theme_constant_override("separation",12); left.add_child(actions)
	main.session_ready_button = button(main,actions,"준비","SessionReadyButton",func():
		var member: Dictionary = main._self_session_member()
		main.network.request_session_ready.rpc_id(1,not bool(member.get("ready",false))))
	main.session_start_button = button(main,actions,"전투 시작","SessionStartButton",func(): main.network.request_session_start.rpc_id(1),true)
	var chat_column := VBoxContainer.new(); chat_column.custom_minimum_size.x = 360; chat_column.add_theme_constant_override("separation",10); body.add_child(chat_column)
	chat_column.add_child(label("방 채팅",16,GOLD))
	main.session_chat_log = RichTextLabel.new(); main.session_chat_log.name = "SessionChatLog"; main.session_chat_log.bbcode_enabled = false; main.session_chat_log.scroll_following = true; main.session_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL; main.session_chat_log.add_theme_font_size_override("normal_font_size",14); main.session_chat_log.add_theme_stylebox_override("normal",UIKit.with_margins(UIKit.box(Color("#0b1220"),Color("#09101c"),UIKit.EDGE_SOFT,12,1.0,0.0,Color(0,0,0,0),0.0),12,10)); chat_column.add_child(main.session_chat_log)
	var chat_row := HBoxContainer.new(); chat_row.add_theme_constant_override("separation",8); chat_column.add_child(chat_row)
	main.session_chat_input = LineEdit.new(); main.session_chat_input.name = "SessionChatInput"; main.session_chat_input.placeholder_text = "메시지 입력"; main.session_chat_input.max_length = 160; main.session_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; main.session_chat_input.custom_minimum_size.y = 44; chat_row.add_child(main.session_chat_input)
	main.session_chat_input.text_submitted.connect(func(_text): main._send_session_chat())
	button(main,chat_row,"전송","SendChatButton",main._send_session_chat)
	update_room(main,main.network.client_session); main.updater.set_safe_to_update(false)

static func update_room(main, data: Dictionary) -> void:
	if not is_instance_valid(main.session_roster) or data.is_empty(): return
	main.session_title.text = ("▣  " if data.locked else "◇  ")+String(data.name)
	for child in main.session_roster.get_children(): main.session_roster.remove_child(child); child.queue_free()
	var players: Array = []; var spectators: Array = []
	for member in data.members:
		if member.role == "player": players.append(member)
		else: spectators.append(member.nickname)
	var code_chip_node = main.find_child("SessionRoomCode",true,false)
	if code_chip_node is Button: code_chip_node.text = "코드  %s  ⧉" % String(data.get("code",""))
	for index in 2:
		var team := UIKit.TEAM_BLUE if index == 0 else UIKit.TEAM_RED
		var slot := PanelContainer.new(); slot.custom_minimum_size.y = 112
		var filled: bool = index < players.size()
		slot.add_theme_stylebox_override("panel",UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI.lerp(team,0.10 if filled else 0.0),UIKit.SURFACE.darkened(0.1),Color(team.r,team.g,team.b,0.65 if filled else 0.25),14,1.0,0.35,Color(0,0,0,0),0.08),18,14)); main.session_roster.add_child(slot)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation",16); slot.add_child(row)
		var avatar := PanelContainer.new(); avatar.custom_minimum_size = Vector2(64,64); avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ring := StyleBoxFlat.new(); ring.bg_color = Color(team.r,team.g,team.b,0.28 if filled else 0.08); ring.border_color = team if filled else Color(team.r,team.g,team.b,0.3); ring.set_border_width_all(2); ring.set_corner_radius_all(32); ring.anti_aliasing = true
		avatar.add_theme_stylebox_override("panel",ring); row.add_child(avatar)
		var initial := Label.new(); initial.text = String(players[index].nickname).left(1).to_upper() if filled else "?"; initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UIKit.display(initial,28,team.lightened(0.4)); avatar.add_child(initial)
		var text := VBoxContainer.new(); text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; text.alignment = BoxContainer.ALIGNMENT_CENTER; text.add_theme_constant_override("separation",6); row.add_child(text)
		if filled:
			var member: Dictionary = players[index]
			text.add_child(label(String(member.nickname)+("  ·  방장" if int(member.id)==int(data.owner) else ""),20))
			var status := label("준비 완료" if member.ready else ("결과 확인 중" if not member.returned else "준비 대기"),13,Color("#8ad4bb") if member.ready else MUTED)
			if member.ready: status.text = "✓ " + status.text
			text.add_child(status)
			var deck_row := HBoxContainer.new(); deck_row.add_theme_constant_override("separation",6); row.add_child(deck_row)
			for kind in member.deck.units:
				var icon := TextureRect.new(); icon.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
				icon.custom_minimum_size = Vector2(52,70); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				icon.tooltip_text = String(BattleModel.UNIT_NAMES.get(kind,kind)); deck_row.add_child(icon)
		else: text.add_child(label("상대 플레이어를 기다리고 있습니다",16,MUTED))
	main.session_spectators.text = "관전 %d명" % spectators.size() + ("  ·  " + ", ".join(spectators.slice(0,8)) if not spectators.is_empty() else "")
	var self_member: Dictionary = main._self_session_member()
	var observer: bool = self_member.get("role","")=="spectator"
	main.session_deck_selector.disabled = observer or data.phase != "waiting"
	main.session_ready_button.visible = not observer
	main.session_ready_button.disabled = data.phase != "waiting"
	main.session_ready_button.text = "준비 해제" if self_member.get("ready",false) else "준비"
	main.session_start_button.visible = int(data.owner)==main.network.multiplayer.get_unique_id()
	main.session_start_button.disabled = data.phase != "waiting" or players.size()!=2 or not players.all(func(member): return member.ready)
	main.status_label.text = "관전 중에는 병력 구매와 건설을 할 수 없습니다." if observer else ("상대가 결과 확인을 마치기를 기다리는 중..." if data.phase == "finished" else "준비 후 방장이 전투를 시작합니다.")
	chat(main)

static func chat(main) -> void:
	if not is_instance_valid(main.session_chat_log): return
	var lines := PackedStringArray()
	for message in main.network.client_session.get("messages",[]):
		lines.append(("[관전] " if message.role == "spectator" else "")+String(message.nickname)+": "+String(message.text))
	main.session_chat_log.text = "\n".join(lines)

static func create_dialog(main) -> void:
	if main.network.client_connection_state != "lobby" or is_instance_valid(main.room_create_dialog): return
	main.room_create_dialog = ConfirmationDialog.new(); main.room_create_dialog.name = "CreateRoomDialog"; main.room_create_dialog.title = "새 방 만들기"; main.room_create_dialog.ok_button_text = "방 만들기"; main.room_create_dialog.cancel_button_text = "취소"
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation",10); main.room_create_dialog.add_child(body)
	body.add_child(label("방 이름",14,MUTED))
	var title := LineEdit.new(); title.name = "RoomNameInput"; title.placeholder_text = "방 이름"; title.text = "함께 대전해요"; title.max_length = 24; title.custom_minimum_size = Vector2(460,44); body.add_child(title)
	body.add_child(label("비밀번호 · 선택",14,MUTED))
	var password := LineEdit.new(); password.name = "RoomPasswordInput"; password.secret = true; password.placeholder_text = "게임용 비밀번호"; password.max_length = 32; password.custom_minimum_size.y = 44; body.add_child(password)
	main.add_child(main.room_create_dialog)
	var validate := func(_value): main.room_create_dialog.get_ok_button().disabled = not NetworkController.is_valid_room_name(title.text)
	title.text_changed.connect(validate)
	var submit := func():
		if main.network.create_session_room(title.text,password.text):
			main._set_lobby_enabled(false); main.status_label.text = "방을 만드는 중..."
		else: main.status_label.text = "방 이름과 닉네임을 확인하세요."
		password.text = ""; main.room_create_dialog.queue_free()
	main.room_create_dialog.confirmed.connect(submit)
	title.text_submitted.connect(func(_value):
		if not main.room_create_dialog.get_ok_button().disabled: submit.call())
	password.text_submitted.connect(func(_value):
		if not main.room_create_dialog.get_ok_button().disabled: submit.call())
	main.room_create_dialog.canceled.connect(func(): password.text = ""; main.room_create_dialog.queue_free())
	main.room_create_dialog.popup_centered(Vector2i(500,280)); title.grab_focus(); title.select_all()

static func entry_dialog(main, room_data: Dictionary, spectator: bool) -> void:
	if not room_data.get("locked",false): main._join_session_entry(room_data,"",spectator); return
	var dialog := ConfirmationDialog.new(); dialog.name = "RoomEntryDialog"; dialog.title = "잠긴 방 · "+String(room_data.name); dialog.ok_button_text = "관전 입장" if spectator else "참가"; dialog.cancel_button_text = "취소"
	var input := LineEdit.new(); input.secret = true; input.max_length = 32; input.placeholder_text = "방 비밀번호"; input.custom_minimum_size = Vector2(420,48); dialog.add_child(input); main.add_child(dialog)
	var submit := func(): main._join_session_entry(room_data,input.text,spectator); input.text = ""; dialog.queue_free()
	dialog.confirmed.connect(submit); input.text_submitted.connect(func(_text): submit.call()); dialog.canceled.connect(func(): input.text = ""; dialog.queue_free())
	dialog.popup_centered(Vector2i(460,150)); input.grab_focus()
