cmake_minimum_required(VERSION 3.17)
project(battle_native LANGUAGES CXX)
## Native battle engine (GDExtension). godot-cpp is fetched by tools/build_native.sh / CI at GODOT_CPP_DIR.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT GODOT_CPP_DIR)
	set(GODOT_CPP_DIR ${CMAKE_SOURCE_DIR}/godot-cpp)
endif()
add_subdirectory(${GODOT_CPP_DIR} godot-cpp)
# The rules hash ties this library to the BattleModel.gd it was translated from: BattleModel uses the library
# only when its own (generated) hash matches, so a game-data update with new rules falls back to GDScript.
# Line endings are dropped first, so a Windows checkout (CRLF) hashes the same as tools/update_rules_hash.py.
file(READ ${CMAKE_SOURCE_DIR}/../scripts/BattleModel.gd BATTLE_MODEL_SOURCE)
string(REPLACE "\r" "" BATTLE_MODEL_SOURCE "${BATTLE_MODEL_SOURCE}")
string(SHA256 BATTLE_RULES_HASH "${BATTLE_MODEL_SOURCE}")
add_library(battle_native SHARED src/register_types.cpp src/battle_core.cpp)
target_compile_definitions(battle_native PRIVATE BATTLE_RULES_HASH="${BATTLE_RULES_HASH}")
target_link_libraries(battle_native PRIVATE godot-cpp)
# Bit-identical doubles with GDScript on every platform: no fused multiply-add, no fast-math reassociation.
if(MSVC)
	target_compile_options(battle_native PRIVATE /fp:precise)
else()
	target_compile_options(battle_native PRIVATE -ffp-contract=off -fno-fast-math)
	# A missing definition is a build error, not a library that fails to load.
	if(NOT APPLE)
		target_link_options(battle_native PRIVATE -Wl,--no-undefined)
	endif()
endif()
set_target_properties(battle_native PROPERTIES PREFIX "lib" OUTPUT_NAME "battle_native.${BATTLE_TARGET_SUFFIX}")
