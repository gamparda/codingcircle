#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include "battle_core.h"

using namespace godot;

void battle_core_init_names();
void battle_core_free_names();

static void initialize(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	battle_core_init_names();
	GDREGISTER_CLASS(BattleCore);
}

static void uninitialize(ModuleInitializationLevel level) {
	if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		battle_core_free_names();
	}
}

extern "C" GDExtensionBool GDE_EXPORT battle_native_init(GDExtensionInterfaceGetProcAddress get_proc, const GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
	GDExtensionBinding::InitObject object(get_proc, library, init);
	object.register_initializer(initialize);
	object.register_terminator(uninitialize);
	object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return object.init();
}
