extends Control

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const LobbyFlow = preload("res://scripts/screens/LobbyFlow.gd")
const BattleFlow = preload("res://scripts/screens/BattleFlow.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const ReplayScreens = preload("res://scripts/screens/ReplayScreens.gd")
const AchievementsScreen = preload("res://scripts/screens/AchievementsScreen.gd")
const DraftScreen = preload("res://scripts/screens/DraftScreen.gd")
const MenuScreens = preload("res://scripts/screens/MenuScreens.gd")
const DeckScreen = preload("res://scripts/screens/DeckScreen.gd")
const SettingsScreen = preload("res://scripts/screens/SettingsScreen.gd")
const BattleHud = preload("res://scripts/screens/BattleHud.gd")
const ResultScreens = preload("res://scripts/screens/ResultScreens.gd")
const UpdateOverlay = preload("res://scripts/screens/UpdateOverlay.gd")
const Tutorial = preload("res://scripts/screens/Tutorial.gd")
const PracticeUI = preload("res://scripts/screens/PracticeUI.gd")
const LocalBattlePause = preload("res://scripts/screens/LocalBattlePause.gd")
const EndlessFlow = preload("res://scripts/screens/EndlessFlow.gd")
const ExpeditionFlow = preload("res://scripts/screens/ExpeditionFlow.gd")
const UnitPurchaseHold = preload("res://scripts/screens/UnitPurchaseHold.gd")
const PatchNotes = preload("res://scripts/PatchNotes.gd")
const MetaStats = preload("res://scripts/MetaStats.gd")

const TransportSecurity = preload("res://scripts/net/TransportSecurity.gd")
const CloudConflict = preload("res://scripts/screens/CloudConflict.gd")
const ResponsiveLayout = preload("res://scripts/ui/ResponsiveLayout.gd")

const OFFICIAL_SERVER_ADDRESS := TransportSecurity.OFFICIAL_HOSTNAME
const OFFICIAL_SERVER_FALLBACK_ADDRESS := TransportSecurity.OFFICIAL_FALLBACK_ADDRESS
const OFFICIAL_SERVER_LAN_ADDRESS := TransportSecurity.OFFICIAL_LAN_ADDRESS
const OFFICIAL_SERVER_PORT := 7777
const ANDROID_APK_URL := "https://gamparda.github.io/codingcircle/CatWar.apk"
const DEFAULT_SMOKE_ROOM_CODE := "CAT234"
const BATTLE_BGM := preload("res://assets/audio/battle_bgm.wav")

@onready var network: NetworkController = $NetworkController
@onready var updater: UpdateManager = $UpdateManager
var account := preload("res://scripts/accounts/ClientAccount.gd").new()
var cloud_sync := preload("res://scripts/accounts/CloudSync.gd").new()
## Same Wi-Fi / hotspot play: the in-app host and the search for hosts (LocalPlay).
var local_play := preload("res://scripts/net/LocalPlay.gd").new()
## Address of the local host the lobby plays on; empty for the official server.
var local_target := ""

var own_side := 0
var battle_view: BattleView
var resource_label: Label
var timer_label: Label
var base_label: Label
var blue_hp_bar: ProgressBar
var red_hp_bar: ProgressBar
var blue_hp_label: Label
var red_hp_label: Label
var status_label: Label
var current_snapshot: Dictionary = {}
var battle_active := false
var result_shown := false
var result_overlay: Control
var stats_overlay: Control
var battle_stats_state: Dictionary = {} # In-memory navigation for the current match only.
var root_background: ColorRect
var smoke_mode := false
var smoke_elapsed := 0.0
var connect_button_ref: Button
var quick_button_ref: Button
var ranked_button_ref: Button
var ranked_label: Label
## Last ranked profile from the server ({rating, wins, losses, draws, rank, leaderboard}); empty until one arrives.
var ranked_profile: Dictionary = {}
## Rating change of the last ranked match ({rating, delta, outcome}); empty until the server sends it.
var last_ranked_result: Dictionary = {}
var join_button_ref: Button
var local_ai_mode := false
var ai_smoke_mode := false
const CampaignBrief = preload("res://scripts/CampaignBrief.gd")
const PracticeTools = preload("res://scripts/PracticeTools.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
var practice = PracticeTools.new()
var practice_used_tools := false
var practice_pause_button: Button
var practice_speed_button: Button
var action_overlay: Control
var latency_label: Label
var recovery_label: Label
var network_paused := false
var awaiting_battle_snapshot := false # Transport recovery alone does not refresh battle resources.
var resuming_battle_ui := false
const BattleBindings = preload("res://scripts/BattleBindings.gd")
var binding_draft: Array = []
var binding_buttons: Array = []
var binding_capture_index := -1
var binding_hint: Label
var binding_capture_overlay: Control
var local_model: BattleModel
var local_ai # ServerAI or GhostOpponent (anything with update(model, delta))
var local_recorder = null # BattleReplay.Recorder for campaign battles
var local_step_accumulator := 0.0
var local_battle_skip_delta := false
var local_pause_overlay: Control
var local_pause_focus: Control
var local_battle_backgrounded := false
var last_replay_path := ""
var pending_battle_replays: Array = [] # finished battles awaiting a successful disk write
var replay_recording_error := ""
var replay_viewer = null
var replay_list_state: Dictionary = {} # Shelf filters, file/action focus and scroll anchor; never saved.
var recent_battles_state: Dictionary = {} # Public battle search, scroll and last received list; session only.
var records_state: Dictionary = {} # Records navigation survives watching a challenge replay.
var quick_wait_started_msec := 0
var battle_curve: Array = []
var battle_curve_samples: Array = [] # timestamped observations for the report; never saved or sent
var battle_contested := false # becomes true at the first attack; before that the momentum curve stays flat
var ghost_context: Dictionary = {}   # {"mode": "ghost" | "branch", "replay": Dictionary, "tick": int}
var finale_seconds := 1.4 # real seconds of base-collapse slow motion before the result; 0 disables it
var finale_active := false
var finale_serial := 0 # Invalidates delayed callbacks when the battle view changes.
var draft_context: Dictionary = {} # stage and decks while a drafted battle is running
var endless_run: Dictionary = {} # the endless-defense run while one is being played (EndlessFlow)
var expedition_run: Dictionary = {} # the expedition while its screens or battles are open (ExpeditionFlow)
var daily_challenge: Dictionary = {} # today's challenge while a daily battle is running
var curve_next_elapsed := 0.0
var current_ai_stage := 1
var bgm_player: AudioStreamPlayer
const CombatSounds = preload("res://scripts/CombatSounds.gd")
const Report = preload("res://scripts/BattleReport.gd")
var combat_sfx_players: Array = []
var sound_gate: Dictionary = {}
var base_warning_fired := false
var base_warning_label: Label
var cancel_build_button: Button
var report_overlay: Control
var battle_report_state: Dictionary = {} # navigation only; reset for each match
var client_purchase_gates: Dictionary = {}
var unit_purchase_hold := UnitPurchaseHold.new()
var latest_resources := 0.0
var rage_sfx_player: AudioStreamPlayer
var last_rage_sfx_msec := -1000
var running_as_server := false
var update_overlay: Control
var update_message_label: Label
var update_progress_bar: ProgressBar
var update_note_label: Label
var server_state_dir := ""
var server_status_accumulator := 0.0
var server_draining := false
var save_data: Dictionary = {}
var profile_save_pending := false
var result_sharing_elapsed := 0.0
var profile_load_warning := ""
var profile_load_details := ""
var campaign_mode := false
var result_recorded := false
var result_presentation: Dictionary = {} # Rewards captured when the result is first confirmed.
var placement_status_label: Label
var placement_hint_label: Label
var structure_count_label: Label
var army_count_labels: Dictionary = {} # Side-indexed HUD labels; never saved or sent.
var unit_capacity_label: Label
var placement_pending := false
var build_confirm_key := 0 # Suppress the rest of a placement-confirmation stroke.
var placement_message_serial := 0
var room_code_input: LineEdit
var multiplayer_screen := ""
var lobby_rows: VBoxContainer
var lobby_page_label: Label
var lobby_page := 0
var lobby_filter := "all"
## Features that need the server connect by themselves (ServerLink). Off in headless runs so tests never dial out.
var link_enabled := true
var link_port := 0 # 0 = the official server's port
var link_timeout := 8.0
var server_link_failed_at := -1000000
var quiet_connection := false # while connecting for such a feature, connection messages stay off the current screen
var lobby_total := 0
var lobby_data := {"rooms":[],"page":0,"total":0}
var lobby_previous_button: Button
var lobby_next_button: Button
var session_title: Label
var session_roster: VBoxContainer
var session_spectators: Label
var session_deck_selector: OptionButton
var session_deck_names: Label
var session_ready_button: Button
var session_start_button: Button
var room_create_dialog: ConfirmationDialog
var battle_preset: Dictionary = {}
var tutorial_step := -1
var tutorial_low_resource := 0.0
var tutorial_banner: Control
var tutorial_hint: Label
var structure_buttons: Array[Button] = []
var purchase_buttons: Array[Button] = []
var settings_touch_scroll: ScrollContainer
var settings_touch_index := -1
var settings_touch_dragged := false
var settings_touch_start := Vector2.ZERO

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		finale_seconds = 0.0
		link_enabled = false
	elif OS.get_name() == "Windows":
		add_child(preload("res://scripts/ImeFix.gd").new()) # Korean typing: see ImeFix.gd
	theme = UIKit.build_theme()
	if UIKit.is_touch():
		get_tree().node_added.connect(_enlarge_for_touch)
	# Wider or taller screens than 1280x720: hand-placed controls follow the screen edges.
	# Headless runs (tests, the server) have no real window: keep the fixed 1280x720 canvas there.
	# Set here too, not only in project.godot: installed apps take updates as content packs, which do
	# not replace the project settings the app started with.
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP if DisplayServer.get_name() == "headless" else Window.CONTENT_SCALE_ASPECT_EXPAND
	ResponsiveLayout.mark(self)
	get_tree().node_added.connect(ResponsiveLayout.on_node_added)
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	network.connection_status.connect(_on_connection_status)
	network.match_found.connect(_on_match_found)
	network.snapshot_received.connect(_on_snapshot)
	network.combat_events_received.connect(_on_combat_events)
	network.opponent_disconnected.connect(_on_opponent_left)
	network.structure_placement_result.connect(_on_structure_placement_result)
	network.room_created.connect(_on_room_created)
	network.room_join_failed.connect(_on_room_join_failed)
	network.room_list_received.connect(_on_room_list)
	network.session_changed.connect(_on_session_changed)
	network.session_error.connect(_on_session_error)
	network.server_ready.connect(_on_server_ready)
	network.result_report_saved.connect(_on_result_report_saved)
	network.daily_score_saved.connect(_on_daily_score_saved)
	network.quick_match_status.connect(_on_quick_match_status)
	network.ranked_profile_received.connect(func(data): LobbyFlow._on_ranked_profile(self, data))
	network.ranked_result_received.connect(_on_ranked_result)
	network.ban_phase_started.connect(func(data): preload("res://scripts/screens/BanDialog.gd").show(self, data))
	network.match_found.connect(func(_side): last_ranked_result = {})
	network.spectate_started.connect(_on_spectate_started)
	network.session_closed.connect(_on_session_closed)
	network.latency_updated.connect(_on_latency_updated)
	network.reconnect_status.connect(_on_reconnect_status)
	network.recovery_changed.connect(_on_recovery_changed)
	network.client_nickname = String(save_data.get("nickname","플레이어"))
	account.name = "ClientAccount"
	add_child(account)
	account.setup(network)
	cloud_sync.name = "CloudSync"
	add_child(cloud_sync)
	cloud_sync.setup(self)
	cloud_sync.conflict.connect(func(text: String):
		if not battle_active and is_instance_valid(root_background): CloudConflict.show(self, text))
	cloud_sync.applied.connect(_on_cloud_applied)
	local_play.name = "LocalPlay"
	add_child(local_play)
	account.changed.connect(_refresh_quick_button)
	updater.update_started.connect(_on_update_started)
	updater.update_status.connect(_on_update_status)
	updater.update_failed.connect(_on_update_failed)
	var args := OS.get_cmdline_user_args()
	smoke_mode = args.has("--smoke-client")
	ai_smoke_mode = args.has("--ai-smoke")
	var has_saved_profile := FileAccess.file_exists(SaveData.SAVE_PATH)
	if args.has("--server"):
		save_data = SaveData.default_data()
	else:
		_load_profile()
	if not args.has("--server") and not has_saved_profile:
		save_data.settings.language = Localization.normalize_locale(TranslationServer.get_locale())
	Localization.install("ko" if args.has("--server") else String(save_data.settings.language))
	if args.has("--server"):
		running_as_server = true
		# Headless mode has no display refresh rate to pace the main loop.
		# Cap it so an idle dedicated server does not spin a CPU core.
		Engine.max_fps = 60
		visible = false
		var port := _arg_int(args, "--port=", NetworkController.DEFAULT_PORT)
		server_state_dir = OS.get_environment("CATWAR_STATE_DIR").strip_edges()
		if server_state_dir.is_empty():
			server_state_dir = "user://server_state"
		DirAccess.make_dir_recursive_absolute(server_state_dir)
		if not network.start_dedicated_server(port):
			get_tree().quit(1)
			return
		network.configure_stats(server_state_dir)
		network.configure_accounts(server_state_dir)
		_update_server_lifecycle(1.0)
		updater.set_safe_to_update(_server_can_update())
		updater.check_for_update()
		return
	_apply_settings()
	_setup_bgm()
	_build_connect_screen()
	if apk_update_required(OS.get_name(), String(ProjectSettings.get_setting("application/config/version", "0.0.0")), build_binary_version()):
		_show_android_apk_notice()
	if args.has("--offline-ai") or ai_smoke_mode:
		_start_local_ai_battle(_arg_int(args, "--ai-stage=", 1))
		return
	var auto_address := _arg_string(args, "--connect=", "")
	var auto_fallback := _arg_string(args, "--fallback=", "")
	if smoke_connect_allowed(smoke_mode, auto_address) and (auto_fallback.is_empty() or smoke_connect_allowed(smoke_mode, auto_fallback)):
		network.set_room_request("enter", _arg_string(args, "--room-code=", DEFAULT_SMOKE_ROOM_CODE))
		network.connect_to_server(auto_address, _arg_int(args, "--port=", NetworkController.DEFAULT_PORT), auto_fallback)

static func official_connection_candidates(local_addresses) -> Array:
	# ENet uses the game server address directly, not the web proxy endpoint.
	var candidates: Array = [OFFICIAL_SERVER_FALLBACK_ADDRESS]
	for local_address in local_addresses:
		if String(local_address).begins_with("192.168.0."):
			candidates.append(OFFICIAL_SERVER_LAN_ADDRESS)
			break
	for address in [OFFICIAL_SERVER_ADDRESS, OFFICIAL_SERVER_FALLBACK_ADDRESS]:
		if not candidates.has(address):
			candidates.append(address)
	return candidates

static func smoke_connect_allowed(is_smoke: bool, address: String) -> bool:
	return is_smoke and (address.begins_with("127.") or address == "localhost" or address == "::1" or address.ends_with(".invalid") or address == OFFICIAL_SERVER_LAN_ADDRESS)

static func apk_update_required(os_name: String, binary_version: String, content_version: String) -> bool:
	return os_name == "Android" and UpdateManager.is_newer_version(content_version, binary_version)

func _arg_int(args: PackedStringArray, prefix: String, fallback: int) -> int:
	for arg in args:
		if arg.begins_with(prefix):
			return int(arg.trim_prefix(prefix))
	return fallback

func _arg_string(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		build_confirm_key = 0 # The OS may deliver the release to another window.
		unit_purchase_hold.reset()
		if is_instance_valid(battle_view): battle_view.structure_inspection.reset(battle_view)
		local_battle_backgrounded = true
		if DisplayServer.get_name() != "headless": LocalBattlePause.pause(self, true)
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		# Returning to the app never resumes the battle without player input.
		local_battle_backgrounded = false

func _process(delta: float) -> void:
	_advance_result_sharing(delta)
	if not local_ai_mode and battle_active and not current_snapshot.is_empty():
		var active_gate := false
		for deadline in client_purchase_gates.values():
			if float(deadline)>Time.get_ticks_msec(): active_gate = true; break
		if active_gate: _refresh_purchase_buttons(latest_resources)
	if running_as_server:
		_update_server_lifecycle(delta)
		updater.set_safe_to_update(_server_can_update())
	if local_ai_mode and battle_active and is_instance_valid(battle_view):
		var paused := LocalBattlePause.is_paused(self)
		battle_view.set_process(not paused or finale_active)
		if paused: local_battle_skip_delta = true
	if local_ai_mode and battle_active and is_instance_valid(local_model) and not LocalBattlePause.is_paused(self):
		# The first resumed frame can include time spent in the background or a
		# modal. Discard that delta without discarding the recorded tick remainder.
		var battle_delta := 0.0 if local_battle_skip_delta else delta
		local_battle_skip_delta = false
		if not endless_run.is_empty(): EndlessFlow.step(self, battle_delta)
		elif not expedition_run.is_empty(): ExpeditionFlow.step(self, battle_delta)
		elif campaign_mode or not ghost_context.is_empty() or not daily_challenge.is_empty() or (local_recorder != null and practice.speed == 1.0 and not practice.unlimited):
			# Fixed 30 Hz steps keep recorded battles deterministic, so their replays reproduce exactly.
			local_step_accumulator += minf(battle_delta, 0.25)
			var step := 1.0 / float(BattleReplay.DEFAULT_HZ)
			while local_step_accumulator >= step and local_model.winner == -1:
				local_ai.update(local_model, step); local_model.tick(step)
				if local_recorder != null: local_recorder.on_tick()
				local_step_accumulator -= step
		else: practice.advance(local_model,local_ai,battle_delta,own_side)
		_on_combat_events(local_model.drain_combat_events())
		_on_snapshot(local_model.snapshot())
		if not endless_run.is_empty() and is_instance_valid(local_model): EndlessFlow.refresh(self)
	if battle_active and is_instance_valid(battle_view): battle_view.structure_inspection.sync(self)
	unit_purchase_hold.advance(self)
	if smoke_mode or ai_smoke_mode:
		smoke_elapsed += delta
		if smoke_elapsed > 45.0:
			printerr("SMOKE_CLIENT_TIMEOUT")
			get_tree().quit(2)

func _input(event: InputEvent) -> void:
	if battle_active and is_instance_valid(battle_view) and battle_view.structure_inspection.handle_input(self, event):
		get_viewport().set_input_as_handled()
		return
	if unit_purchase_hold.handle_input(self, event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and build_confirm_key != 0:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == build_confirm_key:
			if not event.pressed: build_confirm_key = 0
			get_viewport().set_input_as_handled()
			return
	if binding_capture_index>=0 and event is InputEventKey:
		if not event.pressed or event.echo: get_viewport().set_input_as_handled(); return
		get_viewport().set_input_as_handled()
		if event.keycode==KEY_ESCAPE: _cancel_binding_capture(); return
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed:
			binding_hint.text="조합 키 대신 단일 키를 눌러주세요."; return
		var code: int = event.physical_keycode if event.physical_keycode!=0 else event.keycode
		var error: String = BattleBindings.assign(binding_draft,binding_capture_index,code)
		if not error.is_empty(): binding_hint.text=error; return
		_cancel_binding_capture(); _refresh_binding_buttons(); return
	if is_instance_valid(settings_touch_scroll):
		if event is InputEventScreenTouch:
			if event.pressed and settings_touch_index < 0 and settings_touch_scroll.get_global_rect().has_point(event.position):
				settings_touch_index = event.index
				settings_touch_dragged = false
				settings_touch_start = event.position
			elif not event.pressed and event.index == settings_touch_index:
				settings_touch_index = -1
				if settings_touch_dragged:
					get_viewport().set_input_as_handled()
				settings_touch_dragged = false
		elif event is InputEventScreenDrag and event.index == settings_touch_index:
			if not settings_touch_dragged and absf(event.position.y - settings_touch_start.y) < 12.0:
				return
			settings_touch_dragged = true
			settings_touch_scroll.scroll_vertical = maxi(0, settings_touch_scroll.scroll_vertical - roundi(event.relative.y))
			get_viewport().set_input_as_handled()
			return
	if battle_active and is_instance_valid(battle_view) and battle_view.build_touch_index >= 0:
		# Only capture a gesture that the battlefield itself started. HUD and modal
		# touches must reach their controls, even while a structure is selected.
		if not _battle_purchase_block_reason().is_empty() or placement_pending or is_instance_valid(stats_overlay) or is_instance_valid(report_overlay) or is_instance_valid(action_overlay):
			battle_view.reset_build_touch()
		elif event is InputEventScreenDrag:
			var local_position: Vector2 = battle_view.get_global_transform_with_canvas().affine_inverse() * event.position
			if battle_view.update_build_touch(event.index, local_position):
				get_viewport().set_input_as_handled()
				return
		elif event is InputEventScreenTouch and not event.pressed:
			var local_position: Vector2 = battle_view.get_global_transform_with_canvas().affine_inverse() * event.position
			if battle_view.finish_build_touch(event.index, local_position, event.canceled):
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and LocalBattlePause.handle_key(self, event):
		get_viewport().set_input_as_handled(); return
	if event is InputEventKey and is_instance_valid(report_overlay):
		var browser = report_overlay.get_node_or_null("BattleReportBrowser")
		if browser != null and browser.handle_key(event):
			get_viewport().set_input_as_handled()
		# Only the global fullscreen action may reach the rest of Main.
		if event.keycode != KEY_F11: return
	if event is InputEventKey and is_instance_valid(stats_overlay) and not is_instance_valid(local_pause_overlay) and not is_instance_valid(action_overlay) and not is_instance_valid(report_overlay):
		var browser = stats_overlay.get_node_or_null("BattleStatsBrowser")
		if browser == null: browser = stats_overlay.get_node_or_null("BattleArmyPanel")
		if browser == null: browser = stats_overlay.get_node_or_null("BattleStructurePanel")
		if browser != null and browser.handle_key(event):
			get_viewport().set_input_as_handled()
		# Unhandled keys go to the reference controls, never to battle hotkeys.
		return
	if event is InputEventKey and _battle_text_has_focus(): return
	if event is InputEventKey and BattleFlow._handle_build_key(self, event):
		get_viewport().set_input_as_handled(); return
	if event is InputEventKey and _handle_battle_hotkey(event):
		get_viewport().set_input_as_handled(); return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		_set_fullscreen(not bool(save_data.settings.fullscreen))
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and battle_active and is_instance_valid(battle_view) and not battle_view.selected_structure.is_empty():
		_cancel_build_selection()
		get_viewport().set_input_as_handled()

func _server_can_update() -> bool:
	return network.pending_persistence_count() == 0 and server_update_safe(network.models.values(), multiplayer.get_peers().size())

static func server_update_safe(models: Array, connected_peer_count: int) -> bool:
	if connected_peer_count > 0:
		return false
	for model in models:
		if model.winner == -1:
			return false
	return true

func _active_match_count() -> int:
	var count := 0
	for model in network.models.values():
		if model.winner == -1:
			count += 1
	return count

## Once a server is reachable: send what was queued while offline and refresh the community statistics.
func _on_server_ready() -> void:
	network.send_ranked_profile_request()
	lobby_filter = "all" # a new connection starts with the unfiltered list
	if MetaStats.sharing(save_data):
		MetaStats.install_id(save_data)
	MetaStats.prune_daily(save_data)
	if _save_profile():
		_flush_shared_results()
	network.send_stats_request([network.client_unit_deck])
	var identity := MetaStats.install_id(save_data) if MetaStats.sharing(save_data) else ""
	var daily := preload("res://scripts/DailyChallenge.gd")
	network.send_daily_board_request(daily.date_key(), identity)
	network.send_daily_board_request("w" + daily.week_key(), identity)

func _advance_result_sharing(delta: float) -> void:
	if running_as_server:
		return
	result_sharing_elapsed += delta
	if result_sharing_elapsed < MetaStats.RETRY_SECONDS:
		return
	result_sharing_elapsed = 0.0
	if MetaStats.prune_daily(save_data):
		_save_profile()
	_flush_shared_results()

func _flush_shared_results() -> void:
	if not profile_save_pending:
		MetaStats.flush(save_data, network)

func _on_result_report_saved(id: String, sequence: int) -> void:
	if MetaStats.acknowledge_report(save_data, id, sequence):
		_save_profile()
		result_sharing_elapsed = MetaStats.RETRY_SECONDS - 0.5

func _on_daily_score_saved(id: String, date: String, score: int, seconds: float, ruleset: String) -> void:
	if MetaStats.acknowledge_daily(save_data, id, date, score, seconds, ruleset):
		_save_profile()

func _update_server_lifecycle(delta: float) -> void:
	if server_state_dir.is_empty():
		return
	# The Linux updater asks for a drain with update.pending; a self-updating Windows server drains while its update waits.
	var draining := FileAccess.file_exists(server_state_dir.path_join("update.pending")) or updater.update_pending()
	if draining != server_draining:
		server_draining = draining
		network.set_accepting_players(not draining)
		print("SERVER_DRAINING enabled=%s" % draining)
		if draining:
			network.flush_persistence()
	server_status_accumulator += delta
	if server_status_accumulator < 1.0:
		return
	server_status_accumulator = 0.0
	if server_draining:
		# Players back in the lobby after their battle leave too, so the update is not held up by idle connections.
		for peer_id in multiplayer.get_peers():
			if network.peer_should_disconnect_for_drain(int(peer_id)):
				network._disconnect_peer(int(peer_id))
	var status := {
		"active_matches": _active_match_count(),
		"accepting_players": not server_draining,
		"accepting_matches": network.can_create_match(),
		"replay_backlog_full": network.replays.backlog_full(),
		"pending_replay_commands": network.replays.pending_command_count(),
		"safe_to_update": _server_can_update(),
		"pending_saves": network.pending_persistence_count(),
		"reported_result_capacity": network.stats.report_capacity_status(),
	}
	var status_path := server_state_dir.path_join("server-status.json")
	preload("res://scripts/ServerStats.gd").write_json(status_path, status)

func _exit_tree() -> void:
	unit_purchase_hold.reset()
	BattleFlow._cancel_finale(self)

func _clear_screen() -> void:
	unit_purchase_hold.reset()
	_remember_stats_view()
	BattleFlow._cancel_finale(self)
	LocalBattlePause.dismiss(self)
	local_battle_skip_delta = false
	awaiting_battle_snapshot = false
	_cancel_binding_capture()
	binding_buttons.clear(); binding_hint=null; binding_draft.clear()
	for player in combat_sfx_players:
		if is_instance_valid(player): player.stop()
	_dismiss_action_overlay()
	_dismiss_battle_report()
	practice_pause_button = null; practice_speed_button = null; latency_label = null; recovery_label = null
	base_warning_label = null; cancel_build_button = null
	session_roster = null; session_title = null
	for child in get_children():
		if child != network and child != updater and child != bgm_player and child != account and child != cloud_sync and child != local_play:
			child.queue_free()
	battle_view = null
	status_label = null
	replay_viewer = null
	lobby_rows = null
	lobby_page_label = null
	room_create_dialog = null
	result_overlay = null
	stats_overlay = null
	placement_status_label = null
	placement_hint_label = null
	structure_count_label = null
	army_count_labels.clear()
	unit_capacity_label = null
	connect_button_ref = null
	join_button_ref = null
	room_code_input = null
	settings_touch_scroll = null
	settings_touch_index = -1
	settings_touch_dragged = false
	settings_touch_start = Vector2.ZERO
	tutorial_banner = null
	tutorial_hint = null
	tutorial_step = -1
	placement_pending = false
	build_confirm_key = 0
	placement_message_serial += 1
	structure_buttons.clear()
	purchase_buttons.clear()

func _show_placement_status(message: String, duration: float = 2.5) -> void:
	if not is_instance_valid(placement_status_label):
		return
	placement_message_serial += 1
	var serial := placement_message_serial
	placement_status_label.text = Localization.text(message)
	if duration <= 0.0:
		return
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(func():
		if serial == placement_message_serial and is_instance_valid(placement_status_label):
			placement_status_label.text = ""
	)

static func build_version() -> String:
	var file := FileAccess.open("res://build_info.json", FileAccess.READ)
	if file == null:
		return "0.4.9"
	var data = JSON.parse_string(file.get_as_text())
	return String(data.get("version", "0.4.9")) if data is Dictionary else "0.4.9"

static func build_binary_version() -> String:
	var file := FileAccess.open("res://build_info.json", FileAccess.READ)
	if file == null:
		return "0.4.9"
	var data = JSON.parse_string(file.get_as_text())
	return String(data.get("binary_version", "0.4.9")) if data is Dictionary else "0.4.9"

func _active_preset() -> Dictionary:
	return save_data.deck_presets[clampi(int(save_data.last_deck), 0, SaveData.DECK_PRESETS - 1)]

func _apply_settings() -> void:
	var settings: Dictionary = save_data.settings
	if String(settings.graphics_quality) == "auto":
		SaveData.apply_graphics_profile(settings, "auto", OS.has_feature("mobile"), DisplayServer.screen_get_size())
	for pair in [["Master", settings.master_volume], ["BGM", settings.bgm_volume], ["SFX", settings.sfx_volume]]:
		_preview_bus_volume(float(pair[1]), String(pair[0]))
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, bool(settings.muted))
	Engine.max_fps = clampi(int(settings.fps_limit), 30, 240)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	if bool(settings.fullscreen):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var parts := String(settings.window_size).split("x")
		if parts.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))

func _preview_bus_volume(value: float, bus_name: String) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, -80.0 if value <= 0.0 else linear_to_db(value))

func _set_fullscreen(enabled: bool) -> void:
	save_data.settings.fullscreen = enabled
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
		if not enabled:
			var parts := String(save_data.settings.window_size).split("x")
			if parts.size() == 2:
				DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
	var toggle := find_child("FullscreenToggle", true, false) as CheckButton
	if toggle != null:
		toggle.set_pressed_no_signal(enabled)
	_save_profile()

## Main always covers the visible canvas (1280x720, or wider/taller with aspect "expand"),
## whatever its parent's size: screens anchor to it.
func _fit_to_viewport() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _make_background() -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color("#0b121c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ResponsiveLayout.mark(bg)
	add_child(bg)
	_refresh_save_warning(bg)
	return bg

func _load_profile(path: String = SaveData.SAVE_PATH) -> void:
	var loaded := SaveData.load_result(path)
	save_data = loaded.data
	profile_load_warning = loaded.warning
	profile_load_details = ProjectSettings.globalize_path(path)
	if not loaded.backup.is_empty():
		profile_load_details += "\n원본 보관: " + ProjectSettings.globalize_path(loaded.backup)
	elif loaded.status in ["invalid", "unreadable"]:
		profile_load_details += "\n복구 폴더: " + ProjectSettings.globalize_path(SaveData.recovery_dir(path))
	network.client_nickname = String(save_data.nickname)

## Keep automatic progress in memory on failure. Retrying only writes the current profile;
## it never replays achievement or match accounting.
func _save_profile() -> bool:
	profile_save_pending = not SaveData.save_data(save_data)
	_refresh_save_warning(root_background)
	if is_instance_valid(updater):
		updater.set_safe_to_update(_client_can_update())
	return not profile_save_pending

func _profile_saved() -> void:
	profile_save_pending = false
	_refresh_save_warning(root_background)
	updater.set_safe_to_update(_client_can_update())

func _client_can_update() -> bool:
	return not profile_save_pending and pending_battle_replays.is_empty() and (not battle_active or result_shown) and (not is_instance_valid(replay_viewer) or not replay_viewer.notes_dirty)

## Keep each finished replay independent of the next battle's model and recorder.
func _store_battle_replay(replay: Dictionary, name_hint: String) -> void:
	last_replay_path = ""
	if not BattleReplay.valid(replay):
		replay_recording_error = "리플레이 기록 한도를 넘거나 데이터가 올바르지 않아 이 전투의 리플레이를 저장할 수 없습니다."
		_refresh_save_warning(root_background)
		return
	pending_battle_replays.append({"replay": replay.duplicate(true), "hint": name_hint})
	_retry_battle_replays(false) # result accounting and its profile write must finish before updates resume

func _retry_battle_replays(update_safety: bool = true) -> void:
	while not pending_battle_replays.is_empty():
		var entry: Dictionary = pending_battle_replays[0]
		var path := BattleReplay.save(entry.replay, String(entry.hint))
		if path.is_empty():
			break
		last_replay_path = path
		pending_battle_replays.pop_front()
	_refresh_save_warning(root_background)
	if update_safety:
		updater.set_safe_to_update(_client_can_update())

func _refresh_save_warning(background: Control) -> void:
	if not is_instance_valid(background):
		return
	for node_name in ["ProfileLoadWarning", "ProfileSaveWarning", "ReplaySaveWarning"]:
		var old := background.get_node_or_null(node_name)
		if old != null:
			background.remove_child(old)
			old.queue_free()
	var y := 6.0
	if not profile_load_warning.is_empty():
		_add_save_warning(background, "ProfileLoadWarning", profile_load_warning, "DismissProfileLoadWarning", _dismiss_profile_load_warning, y, "확인", profile_load_details)
		y += 72.0
	if profile_save_pending:
		_add_save_warning(background, "ProfileSaveWarning", "진행도를 저장하지 못했습니다. 종료하면 변경 내용이 사라집니다.\n저장 공간과 파일 권한을 확인하고 다시 시도하세요.", "RetryProfileSave", _save_profile, y)
		y += 72.0
	if not pending_battle_replays.is_empty():
		_add_save_warning(background, "ReplaySaveWarning", "리플레이 %d개를 저장하지 못했습니다. 종료하면 기록이 사라집니다.\n저장 공간과 파일 권한을 확인하고 다시 시도하세요." % pending_battle_replays.size(), "RetryBattleReplaySave", _retry_battle_replays, y)
	elif not replay_recording_error.is_empty():
		_add_save_warning(background, "ReplaySaveWarning", replay_recording_error, "", Callable(), y)

func _dismiss_profile_load_warning() -> void:
	profile_load_warning = ""
	profile_load_details = ""
	_refresh_save_warning(root_background)

func _add_save_warning(background: Control, node_name: String, message: String, retry_name: String, callback: Callable, y: float, button_text: String = "저장 재시도", details: String = "") -> void:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.position = Vector2(290, y)
	panel.size = Vector2(700, 64)
	panel.z_index = 200
	panel.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE, UIKit.SURFACE, UIKit.DANGER, 12), 12, 3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = message
	label.tooltip_text = details
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	row.add_child(label)
	if callback.is_valid():
		var retry := _styled_button(button_text, UIKit.GOLD_DEEP)
		retry.name = retry_name
		retry.custom_minimum_size = Vector2(140, 58)
		retry.pressed.connect(callback)
		row.add_child(retry)
	panel.add_child(row)
	background.add_child(panel)

func _add_menu_portrait(parent: Control, texture_path: String, position_value: Vector2, accent: Color, label_text: String) -> void:
	MenuScreens._add_menu_portrait(self, parent, texture_path, position_value, accent, label_text)

func _build_connect_screen(message: String = "") -> void:
	if not account.unlocked():
		preload("res://scripts/screens/LoginGate.gd").show(self, message)
		return
	MenuScreens._build_connect_screen(self, message)
	if cloud_sync.phase == "conflict":
		CloudConflict.show(self, cloud_sync.conflict_text)

## Progress loaded from the server: refresh the menu so it shows it; other screens keep going.
func _on_cloud_applied(message: String) -> void:
	if not battle_active and multiplayer_screen == "" and is_instance_valid(root_background) and root_background.find_child("MenuColumn", true, false) != null:
		_build_connect_screen(message)
	elif is_instance_valid(status_label):
		status_label.text = message

func _normalize_room_code_input(value: String) -> void:
	if not is_instance_valid(room_code_input) or value == value.to_upper():
		return
	var caret := room_code_input.get_caret_column()
	room_code_input.text = value.to_upper()
	room_code_input.set_caret_column(caret)

func _campaign_growth_summary() -> String:
	var bonuses := BattleModel.campaign_bonuses(SaveData.campaign_growth_level(save_data))
	return Localization.text("원정 성장 %d · 병력 +%d%% · 자원 %.1f/초 · 최대 %d") % [int(bonuses.levels), roundi((float(bonuses.stat_scale) - 1.0) * 100.0), float(bonuses.income), int(bonuses.capacity)]

func _quit_game() -> void:
	get_tree().quit()

func _setup_bgm() -> void:
	if DisplayServer.get_name() == "headless" or is_instance_valid(bgm_player):
		return
	var stream := BATTLE_BGM.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * float(stream.mix_rate))
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BattleBGM"
	bgm_player.bus = &"BGM"
	bgm_player.stream = stream
	bgm_player.volume_db = 0.0
	add_child(bgm_player)
	bgm_player.play()

func _build_ai_stage_screen(as_campaign: bool = false) -> void:
	MenuScreens._build_ai_stage_screen(self, as_campaign)

func _submenu(title_text: String, subtitle_text: String, back: Callable = Callable(), back_name: String = "SubMenuBack") -> VBoxContainer:
	return MenuScreens._submenu(self, title_text, subtitle_text, back, back_name)

func _build_solo_screen() -> void:
	MenuScreens._build_solo_screen(self)

func _build_patch_notes_screen() -> void:
	MenuScreens._build_patch_notes_screen(self)

func _build_deck_screen(preset_index: int = -1) -> void:
	DeckScreen._build_deck_screen(self, preset_index)

## On touch devices every button gets a finger-sized minimum height as it enters the tree.
func _enlarge_for_touch(node: Node) -> void:
	if node is BaseButton and is_ancestor_of(node):
		var button := node as BaseButton
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, float(button.get_meta("touch_min_height", UIKit.TOUCH_MIN_HEIGHT)))
	elif node is Slider and is_ancestor_of(node):
		(node as Slider).custom_minimum_size.y = maxf((node as Slider).custom_minimum_size.y, 44.0)

func _build_draft_screen(stage: int = 3) -> void:
	DraftScreen._build_draft_screen(self, stage)

func _start_draft_battle(my_units: Array, enemy_units: Array, stage: int) -> void:
	BattleFlow._start_draft_battle(self, my_units, enemy_units, stage)

func _build_achievements_screen() -> void:
	AchievementsScreen._build_achievements_screen(self)

func _start_daily_challenge(period: String = "daily") -> void:
	BattleFlow._start_daily_challenge(self, period)

func _show_daily_brief(period: String = "daily") -> void:
	PracticeUI._show_daily_brief(self, period)

func _start_ghost_battle(replay: Dictionary) -> void:
	BattleFlow._start_ghost_battle(self, replay)

func _start_branch_battle(replay: Dictionary, tick: int) -> void:
	BattleFlow._start_branch_battle(self, replay, tick)

func _restart_context() -> void:
	BattleFlow._restart_context(self)

func _build_replay_list() -> void:
	ReplayScreens._build_replay_list(self)

func _play_replay(path: String) -> void:
	ReplayScreens._play_replay(self, path)

func _build_records_screen() -> void:
	MenuScreens._build_records_screen(self)

func _show_challenge_replays(period: String, date: String, ruleset: String, record: Dictionary) -> void:
	ReplayScreens._show_challenge_replays(self, period, date, ruleset, record)

func _build_settings_screen(mobile_layout_override: bool = false) -> void:
	SettingsScreen._build_settings_screen(self, mobile_layout_override)

func _add_settings_section(parent: VBoxContainer, title: String) -> void:
	SettingsScreen._add_settings_section(self, parent, title)

func _configure_deck_card(card: Button, base_text: String, color: Color, selected: bool) -> void:
	DeckScreen._configure_deck_card(self, card, base_text, color, selected)

func _refresh_deck_card(card: Button) -> void:
	DeckScreen._refresh_deck_card(self, card)

func _styled_button(text_value: String, color: Color, filled: bool = false) -> Button:
	var button := Button.new()
	button.text = Localization.text(text_value)
	button.custom_minimum_size = Vector2(120, 50)
	return UIKit.style_button(button, color, filled, 16)

func _on_connection_status(text: String) -> void:
	LobbyFlow._on_connection_status(self, text)

func _set_room_controls_disabled(disabled: bool) -> void:
	LobbyFlow._set_room_controls_disabled(self, disabled)

func _connect_for_room(mode: String, code: String = "") -> void:
	LobbyFlow._connect_for_room(self, mode, code)

func _on_room_created(code: String) -> void:
	LobbyFlow._on_room_created(self, code)

func _on_room_join_failed(error: String) -> void:
	LobbyFlow._on_room_join_failed(self, error)

func _on_match_found(side: int) -> void:
	BattleFlow._on_match_found(self, side)

func _start_local_ai_battle(stage: int = 1, reuse_deck: bool = false) -> void:
	BattleFlow._start_local_ai_battle(self, stage, reuse_deck)

func _build_battle_screen() -> void:
	BattleHud._build_battle_screen(self)

func _begin_tutorial() -> void:
	Tutorial._begin_tutorial(self)

func _update_tutorial_hint() -> void:
	Tutorial._update_tutorial_hint(self)

func _tutorial_advance(completed_step: int) -> void:
	Tutorial._tutorial_advance(self, completed_step)

func _finish_tutorial() -> void:
	Tutorial._finish_tutorial(self)

static func result_details(snapshot: Dictionary, side: int, deck_name: String) -> String:
	var bases: Array = snapshot.get("base_hp", [])
	var hp := maxi(0, int(bases[side])) if side >= 0 and side < bases.size() else 0
	var elapsed := maxi(0, int(snapshot.get("elapsed", 0.0)))
	return Localization.text("기지 체력 %d  ·  전투 시간 %02d:%02d\n사용 덱: %s") % [hp, elapsed / 60, elapsed % 60, deck_name]

func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(mini(radius, 8))
	if radius >= 8:
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.24)
		style.shadow_size = 8
	return style

func _create_hp_card(parent: Control, position_value: Vector2, side: int) -> void:
	BattleHud._create_hp_card(self, parent, position_value, side)

func _add_spawn_button(row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	BattleHud._add_spawn_button(self, row, title, kind, color)

func _decorate_battle_card(button: Button) -> void:
	BattleHud._decorate_battle_card(self, button)

func _show_structure_panel(navigation: Dictionary = {}) -> void:
	BattleHud._show_structure_panel(self, navigation)

func _show_army_panel(side: int, navigation: Dictionary = {}) -> void:
	BattleHud._show_army_panel(self, side, navigation)

func _show_stats_reference(section: int, kind: String, side: int, navigation: Dictionary) -> void:
	if not battle_active or result_shown or finale_active or not is_instance_valid(stats_overlay) or is_instance_valid(local_pause_overlay) or is_instance_valid(action_overlay) or is_instance_valid(report_overlay): return
	BattleHud._show_stats_panel(self, {"category": section, "kind": kind, "side": side, "navigation": navigation})

func _toggle_stats_panel() -> void:
	if is_instance_valid(stats_overlay):
		_dismiss_stats_panel()
	else:
		_show_stats_panel()

func _remember_stats_view() -> void:
	if is_instance_valid(stats_overlay):
		var browser = stats_overlay.get_node_or_null("BattleStatsBrowser")
		if browser != null: browser.capture_view_state()

func _dismiss_stats_panel() -> void:
	var was_open := is_instance_valid(stats_overlay)
	var return_focus: Control = stats_overlay.get_meta("return_focus", null) if was_open else null
	if was_open:
		_remember_stats_view()
		stats_overlay.hide()
		stats_overlay.queue_free()
	stats_overlay = null
	if was_open and battle_active and is_instance_valid(battle_view):
		if local_ai_mode:
			battle_view.set_process(not LocalBattlePause.is_paused(self) or finale_active)
			_refresh_purchase_buttons(latest_resources)
		if not LocalBattlePause.is_paused(self) and not is_instance_valid(action_overlay) and not is_instance_valid(report_overlay) and is_instance_valid(root_background):
			if is_instance_valid(return_focus) and return_focus.is_inside_tree() and return_focus.is_visible_in_tree():
				return_focus.grab_focus()
			else:
				var stats_button := root_background.find_child("UnitStatsButton", true, false) as Button
				if stats_button != null: stats_button.grab_focus()

func _show_stats_panel() -> void:
	BattleHud._show_stats_panel(self)

func _add_structure_button(row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	BattleHud._add_structure_button(self, row, title, kind, color)

func _refresh_structure_selection() -> void:
	BattleHud._refresh_structure_selection(self)

func _refresh_purchase_buttons(resources: float) -> void:
	BattleHud._refresh_purchase_buttons(self, resources)

func _battle_purchase_block_reason() -> String:
	return BattleHud._purchase_block_reason(self)

func _unit_production_limit_error() -> String:
	return BattleHud._unit_production_limit_error(self)

func _on_battlefield_clicked(world_x: float) -> void:
	BattleFlow._on_battlefield_clicked(self, world_x)

func _on_structure_placement_result(success: bool, error: String) -> void:
	BattleFlow._on_structure_placement_result(self, success, error)

func _on_snapshot(data: Dictionary) -> void:
	BattleFlow._on_snapshot(self, data)

func _on_rage_started(_unit_id: int) -> void:
	BattleFlow._on_rage_started(self, _unit_id)

func _on_combat_events(events: Array) -> void:
	BattleFlow._on_combat_events(self, events)

func _show_result(winner: int) -> void:
	ResultScreens._show_result(self, winner)

func _cancel_battle_finale() -> void:
	BattleFlow._cancel_finale(self)

func _reset_battle_result() -> void:
	BattleFlow._reset_result(self)

func _record_battle_result(winner: int) -> Dictionary:
	return ResultScreens._record_result(self, winner)

func _dismiss_result_overlay() -> void:
	if is_instance_valid(result_overlay):
		result_overlay.queue_free()
	result_overlay = null
	result_shown = false

func _exit_battle_to_menu() -> void:
	BattleFlow._exit_battle_to_menu(self)

func _exit_ai_battle() -> void:
	BattleFlow._exit_ai_battle(self)

func _on_update_started(version: String) -> void:
	UpdateOverlay._on_update_started(self, version)

func _show_android_apk_notice() -> void:
	UpdateOverlay._show_android_apk_notice(self)

func _on_update_status(message: String, progress: float) -> void:
	UpdateOverlay._on_update_status(self, message, progress)

func _on_update_failed(message: String) -> void:
	UpdateOverlay._on_update_failed(self, message)

func _on_opponent_left() -> void:
	LobbyFlow._on_opponent_left(self)

func _open_multiplayer() -> void:
	LobbyFlow._open_multiplayer(self)

func _build_lobby_screen() -> void:
	MultiplayerUI.browser(self)


func _toggle_quick_match() -> void:
	LobbyFlow._toggle_quick_match(self)

func _on_quick_match_status(state: String) -> void:
	LobbyFlow._on_quick_match_status(self, state)

func _toggle_ranked_match() -> void:
	LobbyFlow._toggle_ranked_match(self)

func _show_ranked_board() -> void:
	LobbyFlow._show_ranked_board(self)

func _on_ranked_result(data: Dictionary) -> void:
	last_ranked_result = data
	ResultScreens._show_ranked_result(self)
	network.send_ranked_profile_request()

func _refresh_quick_button() -> void:
	LobbyFlow._refresh_quick_button(self)

func _set_lobby_enabled(enabled: bool) -> void:
	LobbyFlow._set_lobby_enabled(self, enabled)

func _render_room_listing(data: Dictionary) -> void:
	MultiplayerUI.listing(self,data)


func _on_room_list(data: Dictionary) -> void:
	LobbyFlow._on_room_list(self, data)

func _show_create_room_dialog() -> void:
	MultiplayerUI.create_dialog(self)

func _build_waiting_room(code: String) -> void:
	LobbyFlow._build_waiting_room(self, code)

func _save_nickname(value: String) -> void:
	LobbyFlow._save_nickname(self, value)

func _active_deck_names() -> String:
	var preset := _active_preset()
	var names := PackedStringArray()
	for kind in preset.units: names.append(String(BattleModel.UNIT_NAMES[kind]))
	return " · ".join(names)

func _choose_session_deck(index: int, in_room: bool) -> void:
	LobbyFlow._choose_session_deck(self, index, in_room)

func _prompt_room_entry(room: Dictionary, spectator: bool) -> void:
	if network.client_connection_state != "lobby": return
	MultiplayerUI.entry_dialog(self,room,spectator)

func _join_session_entry(room: Dictionary, password: String, spectator: bool) -> void:
	LobbyFlow._join_session_entry(self, room, password, spectator)

func _self_session_member() -> Dictionary:
	for member in network.client_session.get("members",[]):
		if int(member.id)==network.multiplayer.get_unique_id(): return member
	return {}

func _on_session_changed(data: Dictionary) -> void:
	LobbyFlow._on_session_changed(self, data)

func _on_session_error(text: String) -> void:
	LobbyFlow._on_session_error(self, text)

func _on_session_closed(text: String) -> void:
	LobbyFlow._on_session_closed(self, text)

func _on_spectate_started() -> void:
	LobbyFlow._on_spectate_started(self)

func _battle_text_has_focus() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _handle_battle_hotkey(event: InputEventKey) -> bool:
	return BattleFlow._handle_battle_hotkey(self, event)

func _add_purchase_labels(button: Button, key_text: String) -> void:
	BattleHud._add_purchase_labels(self, button, key_text)

func _purchase_unit(kind: String) -> void:
	BattleFlow._purchase_unit(self, kind)

func _cancel_build_selection() -> void:
	if placement_pending:
		_show_placement_status("서버 확인 중입니다. 이미 요청한 설치는 취소할 수 없습니다.", 0.0)
		return
	if is_instance_valid(battle_view): battle_view.selected_structure = ""
	_refresh_structure_selection(); _show_placement_status("건설을 취소했습니다.")

func _play_combat_events(events: Array) -> void:
	BattleFlow._play_combat_events(self, events)

func _play_battle_sound(kind: String) -> bool:
	return BattleFlow._play_battle_sound(self, kind)

func _update_base_warning(data: Dictionary) -> void:
	BattleFlow._update_base_warning(self, data)

func _dismiss_battle_report() -> void:
	if is_instance_valid(report_overlay):
		var browser = report_overlay.get_node_or_null("BattleReportBrowser")
		if browser != null: browser.remember_before_close()
		report_overlay.hide()
		report_overlay.queue_free()
	report_overlay = null

func _report_side_name(side: int) -> String:
	return ResultScreens._report_side_name(self, side)

func _show_battle_report() -> void:
	ResultScreens._show_battle_report(self)

func _dismiss_action_overlay() -> void:
	if is_instance_valid(action_overlay): action_overlay.queue_free()
	action_overlay = null

func _action_panel(title: String, rect: Rect2) -> VBoxContainer:
	unit_purchase_hold.cancel()
	if is_instance_valid(battle_view): battle_view.reset_build_touch()
	_dismiss_action_overlay()
	action_overlay = ColorRect.new(); action_overlay.name = "BattleActionOverlay"; action_overlay.color = Color(0.02,0.03,0.05,0.95); action_overlay.size = Vector2(1280,720); action_overlay.z_index = 160; root_background.add_child(action_overlay)
	var column := MultiplayerUI.panel(self,action_overlay,"BattleActionPanel",rect)
	column.add_child(MultiplayerUI.label(title,26,MultiplayerUI.GOLD))
	return column

func _show_stage_brief(stage: int) -> void:
	PracticeUI._show_stage_brief(self, stage)

func _show_practice_deck() -> void:
	PracticeUI._show_practice_deck(self)

func _add_practice_controls(row: Control) -> void:
	PracticeUI._add_practice_controls(self, row)

func _toggle_practice_pause() -> void:
	BattleFlow._toggle_practice_pause(self)

func _resume_local_battle() -> void:
	LocalBattlePause.resume(self)

func _restart_practice() -> void:
	BattleFlow._restart_practice(self)

func _confirm_surrender() -> void:
	PracticeUI._confirm_surrender(self)

func _on_latency_updated(milliseconds: int) -> void:
	LobbyFlow._on_latency_updated(self, milliseconds)

func _on_reconnect_status(active: bool, remaining: float) -> void:
	LobbyFlow._on_reconnect_status(self, active, remaining)

func _on_recovery_changed(data: Dictionary) -> void:
	LobbyFlow._on_recovery_changed(self, data)

func _add_binding_settings(column: VBoxContainer) -> void:
	SettingsScreen._add_binding_settings(self, column)

func _refresh_binding_buttons() -> void:
	SettingsScreen._refresh_binding_buttons(self)

func _begin_binding_capture(index: int) -> void:
	SettingsScreen._begin_binding_capture(self, index)

func _cancel_binding_capture() -> void:
	SettingsScreen._cancel_binding_capture(self)
