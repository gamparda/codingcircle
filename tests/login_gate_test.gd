extends SceneTree
## Android's mandatory sign-in: the menu stays behind LoginGate until the account is confirmed, signing out
## brings the gate back, and the PC version goes straight to the menu.

const ClientAccount = preload("res://scripts/accounts/ClientAccount.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var base := "user://login_gate_test"
	DirAccess.make_dir_recursive_absolute(base)
	ClientAccount.save_path = base + "/account.json"
	ClientAccount.required_override = 1
	var bootstrap := Control.new()
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	await process_frame
	check(main.find_child("LoginGate", true, false) != null and main.find_child("MenuColumn", true, false) == null, "Android opens on the sign-in gate, not the menu")
	check(main.find_child("AccountSignInButton", true, false) != null, "the gate offers Google sign-in")
	check(main.find_child("LoginGateRetry", true, false) != null and main.find_child("AccountPrivacyButton", true, false) != null, "the gate can reconnect and shows the privacy policy")

	main._build_settings_screen()
	await process_frame
	await process_frame
	check(main.find_child("LoginGate", true, false) != null and main.find_child("SettingsSaveButton", true, false) == null, "settings without a confirmed account fall back to the gate")

	# The server confirms the account (sign-in or a resumed session).
	main.account.session = "a".repeat(64)
	main.account.nickname = "마왕"
	main.account.state = "signed_in"
	main.account.verified = true
	main.account.changed.emit()
	await process_frame
	await process_frame
	check(main.find_child("LoginGate", true, false) == null and main.find_child("MenuColumn", true, false) != null, "a confirmed account opens the menu")

	main._build_settings_screen()
	await process_frame
	check(main.find_child("AccountSignOutButton", true, false) != null, "settings show the signed-in account")
	main.find_child("AccountSignOutButton", true, false).pressed.emit()
	await process_frame
	await process_frame
	check(main.find_child("LoginGate", true, false) != null, "signing out on Android returns to the gate")
	check(not FileAccess.file_exists(ClientAccount.save_path), "the sign-out forgets the device session")

	ClientAccount.required_override = 0
	main._build_connect_screen()
	await process_frame
	check(main.find_child("MenuColumn", true, false) != null and main.find_child("LoginGate", true, false) == null, "the PC version needs no sign-in")

	ClientAccount.required_override = -1
	DirAccess.remove_absolute(base)
	if failures == 0: print("PASS: login gate")
	quit(1 if failures else 0)
