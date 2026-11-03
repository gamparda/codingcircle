extends RefCounted
## In-game notices (공지): announcements that ship with the game data, such as a privacy policy change before it
## takes effect. The main menu shows a 📢 button with the number of unread notices; an unread notice marked
## `important` opens by itself once when the menu appears. Read notices are remembered in the save
## (read_notices). Notices past their `until` date drop out of the list.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")

const MAX_READ := 60
const PRIVACY_URL := "https://gampa.xyz/privacy_policy.html"

## Newest first. id: stable and unique; date: posting day "YYYY-MM-DD"; until: last day shown ("" = always);
## important: opens once by itself; link: [button text, https URL] or [].
const NOTICES := [
	{"id": "privacy-2026-11-10", "date": "2026-11-03", "until": "2026-11-09", "important": true,
		"title": "개인정보 처리방침 개정 안내 (11월 10일 시행)",
		"body": "2026년 11월 10일(화)부터 개인정보 처리방침이 바뀝니다.\n\n[1] 계정 삭제 유예 (11월 10일부터)\n• 계정 삭제를 신청하면 바로 지우지 않고 30일 뒤에 완전히 삭제합니다.\n• 30일 안에 같은 Google 계정으로 다시 로그인하면 삭제가 취소되고 계정·진행도·랭크 기록·금화·꾸미기가 그대로 돌아옵니다. 예전 닉네임을 그 사이 다른 사람이 쓰고 있으면 새 닉네임만 정하면 됩니다.\n• 유예 기간에는 계정이 순위표·프로필 카드 등 어디에도 보이지 않고, 닉네임은 다른 이용자가 쓸 수 있게 풀립니다.\n• 실수로 지운 계정을 되돌리고, 삭제와 재가입을 반복해 랭크 기록 등을 초기화하는 부정 이용을 막기 위한 변경입니다.\n• 30일을 기다리지 않고 바로 삭제되기를 원하시면 개인정보 보호책임자에게 요청할 수 있습니다.\n\n[2] 게임 재화와 성장 정보 (11월 2일 반영분 안내)\n• 성장 기능(금화·임무·시즌 패스·꾸미기·도감·프로필 카드)을 위해 계정에 칭호, 금화, 임무·시즌 패스 진행도, 꾸미기, 유닛별 출전·처치 수, 서버가 확인한 전투 시간을 저장합니다.\n• 프로필 카드에는 닉네임·칭호·깃발·카드 테두리·랭크 점수·전투 시간·판수·주력 유닛·가입 연월이 다른 이용자에게 보입니다.\n• 금화는 게임 안에서만 얻고 쓰며 유료 결제는 없습니다.\n\n11월 9일까지는 이전 방침이 적용됩니다. 로그인하지 않고 플레이하면 위 정보는 서버에 저장되지 않습니다. 자세한 내용은 개인정보 처리방침 전문에서 확인할 수 있습니다.",
		"link": ["개인정보 처리방침 전문 보기", PRIVACY_URL]},
]

## Today in Korea (UTC+9), so a notice comes down at midnight Korean time after its `until` day.
static func _today() -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) + 9 * 3600)

## Notices still shown on `today` (YYYY-MM-DD), newest first.
static func active(today: String = "") -> Array:
	var day := today if not today.is_empty() else _today()
	return NOTICES.filter(func(notice): return String(notice.until).is_empty() or day <= String(notice.until))

static func is_read(save: Dictionary, id: String) -> bool:
	return save.get("read_notices", []).has(id)

static func unread(save: Dictionary, today: String = "") -> Array:
	return active(today).filter(func(notice): return not is_read(save, String(notice.id)))

static func mark_read(save: Dictionary, id: String) -> void:
	var read: Array = save.get("read_notices", [])
	if not read.has(id):
		read.append(id)
		while read.size() > MAX_READ:
			read.pop_front()
	save["read_notices"] = read

## The 📢 button for the main menu's corner row.
static func add_button(main, parent: Control) -> Button:
	var count := unread(main.save_data).size()
	var button = main._styled_button("📢  " + (Localization.text("공지 %d") % count if count > 0 else Localization.text("공지")), UIKit.GOLD_DEEP if count > 0 else UIKit.EDGE.lightened(0.25))
	button.name = "NoticesButton"
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(func(): show_list(main))
	parent.add_child(button)
	return button

## Opens the newest unread important notice, once, when the menu is up and nothing else covers it.
static func pop_important(main) -> void:
	for notice in unread(main.save_data):
		if bool(notice.important):
			show_notice(main, notice)
			return

static func show_list(main) -> void:
	var column = main._action_panel(Localization.text("공지"), Rect2(200, 50, 880, 620))
	main.action_overlay.name = "NoticesOverlay"
	var shown := active()
	if shown.is_empty():
		column.add_child(MultiplayerUI.label(Localization.text("지금은 공지가 없습니다."), 15, MultiplayerUI.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for notice in shown:
		var entry: Dictionary = notice
		var unread_now := not is_read(main.save_data, String(entry.id))
		var row = main._styled_button("%s%s  ·  %s" % ["● " if unread_now else "", Localization.text(String(entry.title)), String(entry.date)], UIKit.GOLD_DEEP if unread_now else Color("#7a6248"), false)
		row.name = "Notice_" + String(entry.id)
		row.custom_minimum_size = Vector2(0, 52)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.pressed.connect(func(): show_notice(main, entry))
		list.add_child(row)
	MultiplayerUI.button(main, column, Localization.text("닫기"), "CloseNotices", func(): _close(main))

static func show_notice(main, notice: Dictionary) -> void:
	var column = main._action_panel(Localization.text(String(notice.title)), Rect2(200, 50, 880, 620))
	main.action_overlay.name = "NoticeOverlay"
	column.add_child(MultiplayerUI.label(String(notice.date), 13, MultiplayerUI.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := MultiplayerUI.label(Localization.text(String(notice.body)), 16, UIKit.TEXT)
	body.name = "NoticeBody"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	mark_read(main.save_data, String(notice.id))
	main._save_profile()
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	var link: Array = notice.get("link", [])
	if link.size() == 2 and String(link[1]).begins_with("https://"):
		var open = main._styled_button(Localization.text(String(link[0])), UIKit.GOLD_DEEP, false)
		open.name = "NoticeLink"
		open.custom_minimum_size = Vector2(0, 48)
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.pressed.connect(func(): OS.shell_open(String(link[1])))
		buttons.add_child(open)
	var close = main._styled_button(Localization.text("확인"), UIKit.ACCENT, true)
	close.name = "CloseNotice"
	close.custom_minimum_size = Vector2(0, 48)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func(): _close(main))
	buttons.add_child(close)

## Back to the menu with the 📢 count up to date.
static func _close(main) -> void:
	main._dismiss_action_overlay()
	var button = main.root_background.find_child("NoticesButton", true, false) if is_instance_valid(main.root_background) else null
	if button != null:
		var count := unread(main.save_data).size()
		button.text = "📢  " + (Localization.text("공지 %d") % count if count > 0 else Localization.text("공지"))
