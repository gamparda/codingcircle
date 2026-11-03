#pragma once
// Native battle engine: BattleModel.tick translated line by line from scripts/BattleModel.gd so a battle comes
// out bit-for-bit the same (tests/determinism_golden_test.gd runs the corpus on both). Units live here in plain
// structs; BattleModel keeps every other piece of state (small arrays and dictionaries this code edits in place)
// and sees units as dictionaries only when it asks (get_units), which this code reads back before the next tick.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <vector>

namespace godot {

struct KindInfo {
	String name;
	bool known = false;
	bool summon = false; // SUMMON_STATS
	Dictionary stats;
	double hp = 0.0, damage = 0.0, heal = 0.0, interval = 0.0, speed = 0.0, range = 0.0;
	bool has_heal = false;
	bool guard = false, target_rearmost = false, skill_on_self = false;
	bool has_skill = false, has_souls = false, can_revive = false, has_undead_bonus = false, has_knockback = false;
	double skill_cooldown = 0.0, skill_radius = 0.0, skill_damage = 0.0, skill_knockback = 0.0;
	double soul_radius = 0.0, soul_heal_fraction = 0.0, soul_damage_step = 0.0;
	int64_t soul_max = 0, field_limit = 0;
	double revive_delay = 0.0, revive_hp_fraction = 0.5, undead_bonus = 1.0;
	PackedStringArray smite_tags;
	PackedStringArray tags;
	int scope = 0; // 0 none, 1 melee, 2 ranged
	double formation_offset = 0.0;
};

struct Unit {
	int64_t id = 0;
	int64_t side = 0;
	int kind = -1;
	double x = 0.0, hp = 0.0, max_hp = 0.0, damage = 0.0, heal = 0.0, interval = 0.0, cooldown = 0.0, speed = 0.0, range = 0.0;
	int64_t support_stacks = 0;
	bool has_support_stacks = true;
	bool has_summon = false, has_skill = false, has_souls = false, has_frozen = false, has_blessed = false, has_revive = false;
	double summon_remaining = 0.0, skill_remaining = 0.0, frozen_remaining = 0.0, blessed_remaining = 0.0, revive_remaining = 0.0;
	int64_t souls = 0;
	bool has_revived = false;
	Variant revived;
	bool has_muster = false;
	Variant muster;
	// Keys this engine does not know, kept as they came.
	Dictionary extra;
	// The dictionary GDScript holds for this unit (once it asked for it): kept in step both ways, so a reference
	// taken before a tick sees the unit after it, as with the GDScript engine.
	Dictionary handle;
	bool has_handle = false;
};

class BattleCore : public RefCounted {
	GDCLASS(BattleCore, RefCounted)

protected:
	static void _bind_methods();

public:
	static String rules_hash();
	bool configure(const Dictionary &unit_stats, const Dictionary &summon_stats, const Dictionary &structure_stats, const Array &report_kinds, const Dictionary &constants);
	void set_units(const Array &values);
	Array get_units();
	int64_t unit_count();
	int64_t side_count(int64_t side);
	Array export_units();
	int64_t count_units(int64_t side, bool include_downed);
	int64_t fielded(int64_t side, const String &kind);
	bool has_marching(int64_t side);
	void clear_muster(int64_t side);
	Dictionary last_unit();
	void append_unit(const Dictionary &value);
	void tick(Object *model, double delta);
	int kind_of_public(const String &name);
	void write_back(Unit &unit);

private:
	std::vector<KindInfo> kinds;
	Dictionary kind_index; // name -> index
	Dictionary structure_stats;
	Array report_kinds;
	std::vector<Unit> units;
	// The array handed out by get_units (it may have been edited: entries added, removed, replaced) and whether
	// it still describes the current units; read back before the next tick.
	Array exposed;
	bool has_exposed = false;

	int kind_of(const String &name);
	Dictionary to_dictionary(const Unit &unit) const;
	void write_into(Dictionary &target, const Unit &unit) const;
	Unit from_dictionary(const Dictionary &value);
	Dictionary handle_of(Unit &unit);

public:
	void sync_in();
	void sync_out();
};

} // namespace godot
