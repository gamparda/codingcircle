#!/bin/bash
# Builds the native battle engine for this machine (Linux x86_64) into native/bin/.
# GODOT_CPP_DIR: a godot-cpp checkout (tag godot-4.5-stable); cloned into native/godot-cpp when unset.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_CPP_DIR="${GODOT_CPP_DIR:-$ROOT/native/godot-cpp}"
if [ ! -d "$GODOT_CPP_DIR" ]; then
	git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp "$GODOT_CPP_DIR"
fi
BUILD="${BUILD_DIR:-$ROOT/native/build-linux}"
cmake -S "$ROOT/native" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DGODOT_CPP_DIR="$GODOT_CPP_DIR" -DBATTLE_TARGET_SUFFIX=linux.x86_64 > /dev/null
cmake --build "$BUILD" --parallel "$(nproc)" > "$BUILD/build.log" 2>&1 || { tail -40 "$BUILD/build.log"; exit 1; }
mkdir -p "$ROOT/native/bin"
cp "$BUILD/libbattle_native.linux.x86_64.so" "$ROOT/native/bin/"
echo "built native/bin/libbattle_native.linux.x86_64.so"
