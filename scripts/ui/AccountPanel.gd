extends VBoxContainer
## Settings → 계정: guest or signed-in state, Google sign-in (Android), sign-up nickname with the age
## check, rename, sign-out and account deletion. Actions take effect at once; "설정 저장" is not needed.
## With `gate` it is the sign-in screen that Android shows before the game (LoginGate).

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const ClientAccount = preload("res://scripts/accounts/ClientAccount.gd")

var main
var account
var delete_armed := false
var gate := false
var leaving := false

static func create(main_node, as_gate: bool = false) -> VBoxContainer:
	var panel = load("res://scripts/ui/AccountPanel.gd").new()
	panel.name = "AccountPanel"
	panel.gate = as_gate
	panel.main = main_node
	panel.account = main_node.account
	panel.add_theme_constant_override("separation", 10)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.account.changed.connect(panel.refresh)
	panel.refresh()
	return panel

func refresh() -> void:
	delete_armed = false
	# The gate opens the game once the account is confirmed; signing out or deleting on Android closes it again.
	if not leaving and account.unlocked() == gate:
		leaving = true
		main._build_connect_screen.call_deferred()
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var signed_in: bool = account.is_signed_in()
	var status := _label("", 17, UIKit.GOLD)
	status.name = "AccountStatus"
	if account.state == "busy":
		status.text = Localization.text("처리 중입니다…")
	elif account.state == "needs_nickname":
		status.text = Localization.text("새 계정 만들기")
	elif signed_in and gate:
		status.text = Localization.text("%s 님 · 계정 확인 중") % account.nickname
	elif signed_in:
		status.text = Localization.text("%s 님으로 로그인됨") % account.nickname
	else:
		status.text = Localization.text("로그인이 필요합니다" if gate else "게스트로 플레이 중")
	add_child(status)
	if gate:
		add_child(_note("Google 계정으로 로그인해야 플레이할 수 있습니다. 계정은 만 14세 이상만 만들 수 있고, Google 계정 식별값(암호화해 저장)과 닉네임만 보관합니다."))
	else:
		add_child(_note("계정이 있으면 랭크 게임(준비 중)에 참여하고 다른 기기에서도 같은 계정을 쓸 수 있습니다. 게스트도 다른 모드는 모두 할 수 있습니다." if not signed_in else "계정에는 Google 계정 식별값(암호화해 저장)과 닉네임만 보관합니다. 이메일과 이름은 받지 않습니다."))
	var blocker: String = account.blocker()
	if not blocker.is_empty() and account.state != "busy":
		add_child(_note(blocker, Color("#f0d592")))

	match account.state:
		"needs_nickname": _build_sign_up()
		"busy": pass
		_:
			if signed_in and gate: _build_sign_out_only()
			elif signed_in: _build_signed_in()
			else: _build_guest()

	if not String(account.message).is_empty():
		var result := _note(account.message, Color("#f0d592"))
		result.name = "AccountMessage"
		add_child(result)
	var privacy = main._styled_button(Localization.text("개인정보 처리방침"), Color("#596174"), false)
	privacy.name = "AccountPrivacyButton"
	privacy.pressed.connect(func(): OS.shell_open(ClientAccount.PRIVACY_URL))
	add_child(privacy)

func _build_guest() -> void:
	var sign_in = main._styled_button(Localization.text("Google로 로그인"), Color("#3d647d"), true)
	sign_in.name = "AccountSignInButton"
	sign_in.disabled = not account.can_sign_in() or not account.blocker().is_empty()
	sign_in.pressed.connect(func(): account.sign_in())
	add_child(sign_in)
	if not account.can_sign_in():
		add_child(_note("새 Android 앱을 설치해야 로그인할 수 있습니다." if gate else "Google 로그인은 Android 앱에서만 할 수 있습니다."))

## Gate with a saved account the server has not confirmed yet: it resumes on its own; this switches accounts.
func _build_sign_out_only() -> void:
	var sign_out = main._styled_button(Localization.text("다른 계정으로 로그인"), Color("#697386"), false)
	sign_out.name = "AccountSignOutButton"
	sign_out.pressed.connect(func(): account.sign_out())
	add_child(sign_out)

func _build_sign_up() -> void:
	add_child(_note("다른 플레이어에게 보이는 이름입니다. 나중에 바꿀 수 있습니다."))
	var name_edit := _nickname_edit("AccountNicknameEdit", "")
	add_child(name_edit)
	var age := CheckBox.new()
	age.name = "AccountAgeCheck"
	age.text = Localization.text("만 14세 이상입니다")
	add_child(age)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var cancel = main._styled_button(Localization.text("취소"), Color("#697386"), false)
	cancel.name = "AccountSignUpCancel"
	cancel.pressed.connect(func(): account.cancel_sign_up())
	row.add_child(cancel)
	var create = main._styled_button(Localization.text("계정 만들기"), Color("#5e6ad2"), true)
	create.name = "AccountCreateButton"
	create.disabled = true
	var update := func(_value = null): create.disabled = not age.button_pressed or name_edit.text.strip_edges().is_empty()
	age.toggled.connect(update)
	name_edit.text_changed.connect(update)
	create.pressed.connect(func(): account.create(name_edit.text, age.button_pressed))
	row.add_child(create)

func _build_signed_in() -> void:
	var available: bool = account.online and account.blocker().is_empty()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var name_edit := _nickname_edit("AccountRenameEdit", account.nickname)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_edit)
	var rename = main._styled_button(Localization.text("닉네임 변경"), Color("#3d647d"), false)
	rename.name = "AccountRenameButton"
	rename.disabled = not available
	rename.pressed.connect(func(): account.rename(name_edit.text))
	row.add_child(rename)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	add_child(actions)
	var sign_out = main._styled_button(Localization.text("로그아웃"), Color("#697386"), false)
	sign_out.name = "AccountSignOutButton"
	sign_out.pressed.connect(func(): account.sign_out())
	actions.add_child(sign_out)
	var delete = main._styled_button(Localization.text("계정 삭제"), Color("#8f3a4a"), false)
	delete.name = "AccountDeleteButton"
	delete.disabled = not available
	delete.tooltip_text = Localization.text("서버에서 계정과 닉네임을 바로 지웁니다. 되돌릴 수 없습니다.")
	delete.pressed.connect(func():
		if not delete_armed:
			delete_armed = true
			delete.text = Localization.text("한 번 더 누르면 삭제")
			return
		delete_armed = false
		account.delete_account())
	actions.add_child(delete)

func _nickname_edit(node_name: String, value: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = node_name
	edit.text = value
	edit.max_length = ClientAccount.AccountStore.SessionStore.MAX_NICKNAME
	edit.placeholder_text = Localization.text("닉네임")
	edit.custom_minimum_size.x = 240
	return edit

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _note(text: String, color: Color = Color("#9aa5c0")) -> Label:
	return _label(Localization.text(text), 14, color)
