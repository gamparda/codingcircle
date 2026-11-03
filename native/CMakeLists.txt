cmake_minimum_required(VERSION 3.17)
project(battle_native LANGUAGES CXX)
## Native battle engine (GDExtension). godot-cpp is fetched by tools/build_native.sh / CI at GODOT_CPP_DIR.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT GODOT_CPP_DIR)
	set(GODOT_CPP_DIR ${CMAKE_SOURCE_DIR}/godot-cpp)
endif()
add_subdirectory(${GODOT_CPP_DIR} godot-cpp)
# The rules hash ties this library to the GDScript it translates (tools/update_rules_hash.py: the battle rule
# functions of BattleModel.gd, constants excluded since they are passed at run time). BattleModel uses the library
# only when its generated BattleRulesHash.gd matches, so changed rules in a game-data update fall back to GDScript.
find_package(Python3 COMPONENTS Interpreter REQUIRED)
execute_process(
	COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/../tools/update_rules_hash.py --print
	OUTPUT_VARIABLE BATTLE_RULES_HASH
	OUTPUT_STRIP_TRAILING_WHITESPACE
	RESULT_VARIABLE BATTLE_RULES_HASH_RESULT)
if(NOT BATTLE_RULES_HASH_RESULT EQUAL 0 OR NOT BATTLE_RULES_HASH MATCHES "^[0-9a-f]+$")
	message(FATAL_ERROR "tools/update_rules_hash.py --print failed")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
	${CMAKE_SOURCE_DIR}/../scripts/BattleModel.gd ${CMAKE_SOURCE_DIR}/../scripts/BattleReport.gd ${CMAKE_SOURCE_DIR}/../tools/update_rules_hash.py)
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
