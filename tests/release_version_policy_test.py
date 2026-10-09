import json
import pathlib
import re
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReleasePolicyTest(unittest.TestCase):
    def test_release_json_is_the_single_version_source(self):
        release = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))
        for key in ("content_version", "windows_version", "android_binary_version"):
            self.assertRegex(release[key], r"^\d+\.\d+\.\d+$", key)
        result = subprocess.run([sys.executable, str(ROOT / "tools" / "release_meta.py"), "check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, "generated version files drifted: run `python tools/release_meta.py sync`: " + result.stdout)

    def test_workflow_reads_versions_from_release_json(self):
        workflow = (ROOT / ".github" / "workflows" / "build-and-deploy.yml").read_text(encoding="utf-8")
        self.assertIn("tools/release_meta.py github-env", workflow)
        self.assertNotRegex(workflow, r'\$(content|windows)Version = "\d')
        self.assertNotRegex(workflow, r'\$androidBinaryVersion = "\d')
        self.assertIn("python tools/run_suite.py ${{ matrix.suite }}", workflow)
        suites = json.loads((ROOT / "tests" / "suites.json").read_text(encoding="utf-8"))
        default = [name for name in suites if name not in ("render", "production")]
        matrix = re.search(r"suite: \[([^\]]+)\]", workflow).group(1)
        self.assertEqual([item.strip() for item in matrix.split(",")], default, "CI matrix must list every default suite")
        self.assertIn("needs: [tests, multiplayer-preview]", workflow)
        self.assertIn("--export-pack Android dist/CatWarContent.pck", workflow)
        self.assertIn('--export-pack "Windows Desktop" dist/CatWarDesktop.pck', workflow)
        self.assertIn("desktop_pack_version = $env:CONTENT_VERSION", workflow)
        self.assertIn("desktop_pack_sha256 = $desktopSha", workflow)
        self.assertIn("--export-release Android dist/CatWar.apk", workflow)
        self.assertIn("-ContentVersion $env:CONTENT_VERSION", workflow)
        self.assertIn("Reused APK hash changed", workflow)
        self.assertIn("version = $env:WINDOWS_VERSION", workflow)
        self.assertIn("android_binary_version = $env:ANDROID_BINARY_VERSION", workflow)
        self.assertIn("content_pack_version = $env:CONTENT_VERSION", workflow)

    def test_tagged_releases_are_immutable(self):
        workflow = (ROOT / ".github" / "workflows" / "build-and-deploy.yml").read_text(encoding="utf-8")
        self.assertNotIn("--clobber", workflow, "a published version tag must never be overwritten")
        self.assertNotIn("gh release upload", workflow)
        self.assertIn("gh release create $tag", workflow)
        self.assertRegex(workflow, r"actions/upload-artifact@v[0-9]+")
        self.assertIn("dev-build", workflow)

    def test_windows_build_tool_reads_release_json(self):
        build_script = (ROOT / "tools" / "build_release.ps1").read_text(encoding="utf-8")
        self.assertIn("release_meta.py", build_script)
        self.assertNotIn("binary_version = $BinaryVersion", build_script)

    def test_android_notice_displays_required_binary_version(self):
        overlay = (ROOT / "scripts" / "screens" / "UpdateOverlay.gd").read_text(encoding="utf-8")
        notice = overlay.split("static func _show_android_apk_notice(main) -> void:", 1)[1].split("\nstatic func ", 1)[0]
        self.assertIn("main._on_update_started(main.build_binary_version())", notice)

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
        for path in sorted((ROOT / "scripts" / "screens").glob("*.gd")):
            source = path.read_text(encoding="utf-8")
            if "Localization." in source:
                self.assertIn(preload_line, source, path.name)
            self.assertNotIn("class_name", source, path.name)
        localization_source = (ROOT / "scripts" / "Localization.gd").read_text(encoding="utf-8")
        self.assertNotIn("class_name Localization", localization_source)


if __name__ == "__main__":
    unittest.main()
