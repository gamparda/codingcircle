extends RefCounted
## The "같은 와이파이" dialog: host a friendly match on this device, pick a host found on the network, or type
## a host's address. Joining or hosting turns the lobby into that host's lobby (main.local_target).

const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const LocalPlay = preload("res://scripts/net/LocalPlay.gd")
const LobbyFlow = preload("res://scripts/screens/LobbyFlow.gd")

static func show(main) -> void:
	var dialog = main._action_panel("같은 와이파이 대전", Rect2(220, 50, 840, 620))
	main.action_overlay.name = "LocalPlayOverlay"
	var intro := MultiplayerUI.label("서버 없이 같은 와이파이나 휴대폰 핫스팟에 접속한 사람끼리 대전합니다. 핫스팟을 켠 사람이 방을 만들면 가장 잘 연결됩니다. 친선전이라 랭크에는 반영되지 않습니다.", 14, MultiplayerUI.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(intro)
	var host_button := MultiplayerUI.button(main, dialog, "📶 내 기기에서 방 만들기", "LocalHostButton", func(): host(main), true)
	host_button.custom_minimum_size.y = 52
	dialog.add_child(MultiplayerUI.label("주변에서 찾은 방", 16, MultiplayerUI.GOLD))
	var rows := VBoxContainer.new()
	rows.name = "LocalHostRows"
	rows.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	dialog.add_child(scroll)
	var manual := HBoxContainer.new()
	manual.add_theme_constant_override("separation", 8)
	dialog.add_child(manual)
	var address := LineEdit.new()
	address.name = "LocalAddressInput"
	address.placeholder_text = "방장 주소 (예: 192.168.43.1)"
	address.custom_minimum_size = Vector2(0, 48)
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	manual.add_child(address)
	var status := MultiplayerUI.label("", 13, MultiplayerUI.MUTED)
	status.name = "LocalPlayStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var join_typed := func():
		if not LocalPlay.valid_address(address.text):
			status.text = "주소를 숫자 네 묶음으로 입력하세요. 예: 192.168.43.1"
			return
		join(main, address.text.strip_edges())
	address.text_submitted.connect(func(_text): join_typed.call())
	MultiplayerUI.button(main, manual, "주소로 접속", "LocalAddressJoin", join_typed).custom_minimum_size = Vector2(150, 48)
	dialog.add_child(status)
	MultiplayerUI.button(main, dialog, "닫기", "CloseLocalPlay", func():
		main.local_play.stop_search()
		main._dismiss_action_overlay())
	if not main.local_play.start_search():
		status.text = "주변 방을 찾을 수 없습니다(포트 %d 사용 중). 방장 주소를 직접 입력하세요." % LocalPlay.DISCOVERY_PORT
	render(main, rows, main.local_play.host_list())
	var refresh := func(found: Array):
		if is_instance_valid(rows):
			render(main, rows, found)
	main.local_play.hosts_changed.connect(refresh)
	rows.tree_exiting.connect(func():
		if main.local_play.hosts_changed.is_connected(refresh):
			main.local_play.hosts_changed.disconnect(refresh))

static func render(main, rows: VBoxContainer, found: Array) -> void:
	for child in rows.get_children():
		child.queue_free()
	if found.is_empty():
		var empty := MultiplayerUI.label("찾는 중... 방장과 같은 와이파이(또는 방장의 핫스팟)에 접속해 있는지 확인하세요. 목록에 뜨지 않으면 방장 화면에 표시된 주소를 아래에 입력하세요.", 13, MultiplayerUI.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(empty)
		return
	for entry in found:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := MultiplayerUI.label("%s의 방 · %s%s" % [String(entry.name), String(entry.address), "" if entry.compatible else " · 게임 버전이 달라요"], 15, Color.WHITE if entry.compatible else MultiplayerUI.MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var target := String(entry.address)
		var button := MultiplayerUI.button(main, row, "참가", "LocalJoin_" + target.replace(".", "_"), func(): join(main, target), true)
		button.disabled = not bool(entry.compatible)
		rows.add_child(row)

static func host(main) -> void:
	main.network.disconnect_from_server()
	main.local_play.stop_search()
	if not main.local_play.start_host(main.network.client_nickname):
		main._dismiss_action_overlay()
		main._build_lobby_screen()
		main.status_label.text = "이 기기에서 방을 열지 못했습니다(포트 %d 사용 중). 앱을 다시 켜고 시도하세요." % LocalPlay.HOST_PORT
		return
	main.local_target = "127.0.0.1"
	main._dismiss_action_overlay()
	main._open_multiplayer()

static func join(main, address: String) -> void:
	main.network.disconnect_from_server()
	main.local_play.stop_search()
	main.local_play.stop_host()
	main.local_target = address
	main._dismiss_action_overlay()
	main._open_multiplayer()

## The lobby's line about same-Wi-Fi play, or "" on the official server.
static func lobby_note(main) -> String:
	if main.local_target.is_empty():
		return ""
	if main.local_play.hosting():
		var addresses: Array = LocalPlay.shareable_addresses(IP.get_local_addresses())
		var shown := ", ".join(PackedStringArray(addresses.slice(0, 2))) if not addresses.is_empty() else "확인할 수 없음"
		return "같은 와이파이 대전 · 내가 방장 · 내 주소 %s · 상대가 '같은 와이파이'에서 이 방을 고르면 둘 다 ⚡ 빠른 대전을 누르세요." % shown
	return "같은 와이파이 대전 · 방장 %s · 둘 다 ⚡ 빠른 대전을 누르면 바로 시작합니다." % main.local_target
