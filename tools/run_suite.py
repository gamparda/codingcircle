#!/usr/bin/env python3
"""Run test suites declared in tests/suites.json.

    python tools/run_suite.py all              # every suite except the manual ones (render, production)
    python tools/run_suite.py unit network     # selected suites
    python tools/run_suite.py render           # needs a real display (xvfb/GPU)
    python tools/run_suite.py production       # talks to the live game server; its RPC set must match this build

The Godot console binary comes from $GODOT_CONSOLE, then PATH, then the winget install.
Exit code is 1 if any test failed; every failing test is listed at the end.
"""
import glob
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
SUITES = json.loads((ROOT / "tests" / "suites.json").read_text(encoding="utf-8"))
# Not part of "all": these need a display or the live production server.
MANUAL = {"render", "production"}
DEFAULT = [name for name in SUITES if name not in MANUAL]


def find_godot() -> str:
    explicit = os.environ.get("GODOT_CONSOLE")
    if explicit:
        return explicit
    for name in ("godot", "godot4", "Godot_v4.7.2-stable_linux.x86_64"):
        found = shutil.which(name)
        if found:
            return found
    local = os.environ.get("LOCALAPPDATA", "")
    hits = glob.glob(os.path.join(local, "Microsoft", "WinGet", "Packages", "GodotEngine*", "*console*.exe"))
    if hits:
        return hits[0]
    raise SystemExit("Godot not found: set GODOT_CONSOLE")


def ensure_imported(godot: str) -> None:
    if not (ROOT / ".godot" / "imported").exists():
        subprocess.run([godot, "--headless", "--editor", "--import", "--path", str(ROOT)],
                       cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)


def run_one(godot: str, test: str, timeout: int) -> tuple:
    if test.endswith(".py"):
        cmd = [sys.executable, test]
    else:
        cmd = [godot, "--headless", "--single-threaded-scene", "--path", str(ROOT), "--script", "res://" + test]
    started = time.time()
    try:
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
                              env={**os.environ, "PYTHONUTF8": "1"}, timeout=timeout)
        return proc.returncode, (proc.stdout + proc.stderr), time.time() - started
    except subprocess.TimeoutExpired:
        return 124, "timed out", time.time() - started


def main(argv: list) -> int:
    wanted = argv[1:] or ["all"]
    names = DEFAULT if wanted == ["all"] else wanted
    unknown = [n for n in names if n not in SUITES]
    if unknown:
        print("unknown suite(s):", ", ".join(unknown), "- available:", ", ".join(SUITES))
        return 2
    godot = find_godot()
    ensure_imported(godot)
    failures = []
    for name in names:
        print(f"== {name} ==", flush=True)
        for test in SUITES[name]:
            code, output, seconds = run_one(godot, test, int(os.environ.get("TEST_TIMEOUT", "180")))
            print(f"  {'ok  ' if code == 0 else 'FAIL'} {test} ({seconds:.1f}s)", flush=True)
            if code != 0:
                failures.append(test)
                print("\n".join("      " + line for line in output.strip().splitlines()[-8:]))
    print(f"\n{sum(len(SUITES[n]) for n in names) - len(failures)} passed, {len(failures)} failed")
    for test in failures:
        print("  failed:", test)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
