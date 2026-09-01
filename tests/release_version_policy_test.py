import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ContentOnlyReleaseTest(unittest.TestCase):
    def test_release_versions_are_ready_for_the_one_time_binary_migration(self):
        build_info = json.loads((ROOT / "build_info.json").read_text(encoding="utf-8"))
        self.assertEqual(build_info["version"], "0.4.9")
        self.assertEqual(build_info["binary_version"], "0.4.9")

        project = (ROOT / "project.godot").read_text(encoding="utf-8")
        self.assertRegex(project, r'config/version="0\.4\.9"')
        android_export = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        self.assertRegex(android_export, r'version/name="0\.4\.9"')

    def test_ci_can_reuse_android_while_still_updating_windows_and_content(self):
        workflow = (ROOT / ".github" / "workflows" / "build-and-deploy.yml").read_text(encoding="utf-8")
        self.assertIn('$contentVersion = "0.4.9"', workflow)
        self.assertIn('$windowsVersion = "0.4.9"', workflow)
        self.assertIn('$androidBinaryVersion = "0.4.9"', workflow)
        self.assertIn("--export-pack Android dist/CatWarContent.pck", workflow)
        self.assertIn("if: env.BUILD_ANDROID == 'true'", workflow)
        self.assertIn("--export-release Android dist/CatWar.apk", workflow)
        self.assertIn("build_release.ps1", workflow)
        self.assertIn("-ContentVersion $env:CONTENT_VERSION", workflow)
        self.assertIn("Invoke-WebRequest $previous.android_apk_url", workflow)
        self.assertIn("Reused APK hash changed", workflow)
        self.assertIn("version = $env:WINDOWS_VERSION", workflow)
        self.assertIn("android_binary_version = $env:ANDROID_BINARY_VERSION", workflow)
        self.assertIn("content_pack_version = $env:CONTENT_VERSION", workflow)

    def test_windows_build_tool_preserves_an_independent_android_binary_version(self):
        build_script = (ROOT / "tools" / "build_release.ps1").read_text(encoding="utf-8")
        self.assertIn('[string]$ContentVersion = ""', build_script)
        self.assertRegex(build_script, r"version\s*=\s*\$ContentVersion")
        self.assertIn('[string]$BinaryVersion = ""', build_script)
        self.assertRegex(build_script, r"binary_version\s*=\s*\$BinaryVersion")

    def test_android_notice_displays_required_binary_version(self):
        main_script = (ROOT / "scripts" / "Main.gd").read_text(encoding="utf-8")
        notice = main_script.split("func _show_android_apk_notice() -> void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("_on_update_started(build_binary_version())", notice)

    def test_pck_localization_does_not_require_a_new_global_class_cache(self):
        localized_scripts = [
            "BattleModel.gd",
            "BattleView.gd",
            "Bootstrap.gd",
            "Main.gd",
            "NetworkController.gd",
            "SaveData.gd",
            "ServerAI.gd",
            "UpdateManager.gd",
        ]
        preload_line = 'const Localization = preload("res://scripts/Localization.gd")'
        for name in localized_scripts:
            source = (ROOT / "scripts" / name).read_text(encoding="utf-8")
            self.assertIn(preload_line, source, name)
        localization_source = (ROOT / "scripts" / "Localization.gd").read_text(encoding="utf-8")
        self.assertNotIn("class_name Localization", localization_source)


if __name__ == "__main__":
    unittest.main()
