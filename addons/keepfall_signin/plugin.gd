@tool
extends EditorPlugin
## Adds the Google sign-in Android plugin (android/plugins/keepfall_signin, built into bin/) to
## Gradle Android exports. Other platforms are unaffected.

var export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	## Relative to res://addons/.
	const LIBRARY := "keepfall_signin/bin/keepfall_signin-release.aar"
	## Keep in sync with android/plugins/keepfall_signin/build.gradle.
	const DEPENDENCIES := [
		"androidx.credentials:credentials:1.5.0",
		"androidx.credentials:credentials-play-services-auth:1.5.0",
		"com.google.android.libraries.identity.googleid:googleid:1.1.1",
	]

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([LIBRARY])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(DEPENDENCIES)

	func _get_name() -> String:
		return "KeepfallSignIn"
