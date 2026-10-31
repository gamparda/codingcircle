@tool
extends EditorPlugin
## Adds the in-app APK installer (android/plugins/keepfall_updater, built into bin/) to Gradle Android exports,
## except the ONE store build (feature "onestore"), which updates through the store and must not ask for
## REQUEST_INSTALL_PACKAGES.

var export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	## Relative to res://addons/.
	const LIBRARY := "keepfall_updater/bin/keepfall_updater-release.aar"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		var preset = get_export_preset()
		if preset != null:
			var features = preset.get_custom_features()
			var names: Array = Array(features) if features is PackedStringArray else Array(String(features).split(",", false))
			if names.map(func(name): return String(name).strip_edges()).has("onestore"):
				return PackedStringArray()
		return PackedStringArray([LIBRARY])

	func _get_name() -> String:
		return "KeepfallUpdater"
