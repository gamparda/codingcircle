#!/usr/bin/env python3
"""Single source of truth for release versions: release.json.

    python tools/release_meta.py sync        # propagate release.json into generated files
    python tools/release_meta.py check       # fail if any generated file drifted
    python tools/release_meta.py github-env  # print KEY=VALUE lines for $GITHUB_ENV
    python tools/release_meta.py get <field> # print one release.json field

Versions: content_version moves with every release. windows_version is the version of the installer/executable and moves
only when the executable itself must change (engine, export settings, installer, new native files): Windows clients
get every other release as a small game-data pack through the launcher.

Generated from release.json:
  build_info.json     version, windows_version, binary_version, update_url (commit is stamped at build time)
  project.godot       config/version            = android_binary_version
  export_presets.cfg  Windows file/product ver  = windows_version
                      Android version/name      = android_binary_version
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
FIELDS = ("content_version", "windows_version", "android_binary_version", "update_url")


def load() -> dict:
    data = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))
    for field in FIELDS:
        if field not in data:
            raise SystemExit(f"release.json is missing '{field}'")
    for field in FIELDS[:3]:
        if not SEMVER.match(str(data[field])):
            raise SystemExit(f"release.json '{field}' must be major.minor.patch, got {data[field]!r}")
    return data


def _regex_edits(release: dict) -> list:
    """(file, pattern, replacement) triples that pin generated files to release.json."""
    win, binary = release["windows_version"], release["android_binary_version"]
    return [
        ("project.godot", r'config/version="[^"]*"', f'config/version="{binary}"'),
        ("export_presets.cfg", r'application/file_version="[^"]*"', f'application/file_version="{win}"'),
        ("export_presets.cfg", r'application/product_version="[^"]*"', f'application/product_version="{win}"'),
        ("export_presets.cfg", r'version/name="[^"]*"', f'version/name="{binary}"'),
    ]


def _build_info(release: dict, commit: str) -> dict:
    return {
        "version": release["content_version"],
        "windows_version": release["windows_version"],
        "binary_version": release["android_binary_version"],
        "commit": commit,
        "update_url": release["update_url"],
    }


def _write(path: pathlib.Path, text: str) -> None:
    path.write_bytes(text.encode("utf-8"))


def sync(commit: str = "") -> None:
    release = load()
    info_path = ROOT / "build_info.json"
    existing = json.loads(info_path.read_text(encoding="utf-8")) if info_path.exists() else {}
    info = _build_info(release, commit or existing.get("commit", "development"))
    _write(info_path, json.dumps(info, indent=2) + "\n")
    for name, pattern, replacement in _regex_edits(release):
        path = ROOT / name
        text = path.read_text(encoding="utf-8")
        if not re.search(pattern, text):
            raise SystemExit(f"{name}: no match for {pattern}")
        _write(path, re.sub(pattern, replacement, text))


def check() -> list:
    release = load()
    problems = []
    info = json.loads((ROOT / "build_info.json").read_text(encoding="utf-8"))
    for key, value in _build_info(release, info.get("commit", "")).items():
        if info.get(key) != value:
            problems.append(f"build_info.json {key}={info.get(key)!r}, release.json wants {value!r}")
    for name, pattern, replacement in _regex_edits(release):
        text = (ROOT / name).read_text(encoding="utf-8")
        found = re.findall(pattern, text)
        if not found or any(item != replacement for item in found):
            problems.append(f"{name}: expected {replacement}, found {found}")
    return problems


def github_env(release: dict) -> list:
    return [
        f"CONTENT_VERSION={release['content_version']}",
        f"WINDOWS_VERSION={release['windows_version']}",
        f"ANDROID_BINARY_VERSION={release['android_binary_version']}",
        f"UPDATE_URL={release['update_url']}",
    ]


def main(argv: list) -> int:
    command = argv[1] if len(argv) > 1 else "check"
    if command == "sync":
        sync(argv[2] if len(argv) > 2 else "")
    elif command == "check":
        problems = check()
        for problem in problems:
            print("DRIFT:", problem)
        return 1 if problems else 0
    elif command == "github-env":
        print("\n".join(github_env(load())))
    elif command == "get":
        print(load()[argv[2]])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
