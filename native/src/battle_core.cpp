#include "battle_core.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <limits>
#include <unordered_map>
#include <utility>

using namespace godot;

#ifndef BATTLE_RULES_HASH
#define BATTLE_RULES_HASH "unknown"
#endif

namespace {

// BattleModel.gd constants, handed over by configure() (BattleModel.native_constants()): a balance change in
// the game data reaches the engine without an app update.
double FIELD_LEFT = 0.0;
double FIELD_RIGHT = 0.0;
double MIN_ATTACK_INTERVAL = 0.0;
double SUPPORT_INCREMENT = 0.0;
double SUPPORT_COOLDOWN = 0.0;
double SUPPORT_FOLLOW_DISTANCE = 0.0;
double CURSE_RADIUS = 0.0;
double CURSE_DURATION = 0.0;
double CURSE_SPEED_SCALE = 0.0;
double SUMMON_INTERVAL = 0.0;
double RAGE_HP_FRACTION = 0.0;
double RAGE_SPEED_MULTIPLIER = 0.0;
double KNOCKBACK_FRACTION = 0.0;
double KNOCKBACK_DISTANCE = 0.0;
double CASTLE_RANGE = 0.0;
double CASTLE_INTERVAL = 0.0;
double CASTLE_DAMAGE = 0.0;
double CASTLE_DESPERATION = 0.0;
double GUARD_SPOT = 0.0;
double FORMATION_MELEE = 0.0;
double MUSTER_INSET = 0.0;
double FORMATION_RANGED_MIN = 0.0;
double FORMATION_RANGED_MAX = 0.0;
int64_t SUPPORT_MAX_STACKS = 0;
int64_t MAX_SKELETONS_PER_NECROMANCER = 0;
int64_t SIDE_UNIT_LIMIT = 0;
int64_t MAX_FALLEN = 0;
constexpr double EPS = 0.000001;
constexpr double INF = std::numeric_limits<double>::infinity();

// Godot's own comparisons, so even signed zeros and ties come out the same as in GDScript.
inline double gd_max(double a, double b) { return a < b ? b : a; } // max(): (a < b) ? b : a
inline double gd_min(double a, double b) { return b < a ? b : a; } // min(): (b < a) ? b : a
inline double gd_maxf(double a, double b) { return a > b ? a : b; } // MAX macro
inline double gd_minf(double a, double b) { return a < b ? a : b; } // MIN macro
inline double gd_clamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline int64_t gd_mini(int64_t a, int64_t b) { return a < b ? a : b; }
inline int64_t gd_maxi(int64_t a, int64_t b) { return a > b ? a : b; }

// PackedFloat64Array.bsearch(value, true) / (value, false).
inline int64_t lower(const std::vector<double> &xs, double value) {
	return std::lower_bound(xs.begin(), xs.end(), value) - xs.begin();
}
inline int64_t upper(const std::vector<double> &xs, double value) {
	return std::upper_bound(xs.begin(), xs.end(), value) - xs.begin();
}
inline int64_t run_start(const std::vector<double> &xs, int64_t at) { return lower(xs, xs[at]); }

struct Lane {
	std::vector<double> xs;
	std::vector<int> order; // index into units
	std::vector<double> guard_xs;
	std::vector<int> guard_order;
};

struct NeedyLane {
	std::vector<double> xs;
	std::vector<int> order; // index into needy
};

// What an attack hits or comes from: a unit (index), a structure dictionary, or a castle.
struct Target {
	int unit = -1;
	Dictionary structure;
	bool valid() const { return unit >= 0 || !structure.is_empty(); }
};

struct PendingAttack {
	int attacker_unit = -1; // unit attacker (has "speed")
	Dictionary attacker;    // turret structure or castle stand-in
	Target target;
	double damage = 0.0;
};

struct PendingHit {
	int attacker = -1;
	double damage = 0.0;
	double x = 0.0;
};

// Interned keys, made when the library is initialised (a StringName cannot be built while the library is
// still being loaded, before Godot has handed over its interface).
struct Names {
	StringName id = StringName("id");
	StringName side = StringName("side");
	StringName kind = StringName("kind");
	StringName x = StringName("x");
	StringName hp = StringName("hp");
	StringName max_hp = StringName("max_hp");
	StringName damage = StringName("damage");
	StringName heal = StringName("heal");
	StringName interval = StringName("interval");
	StringName cooldown = StringName("cooldown");
	StringName support_stacks = StringName("support_stacks");
	StringName speed = StringName("speed");
	StringName range = StringName("range");
	StringName summon_remaining = StringName("summon_remaining");
	StringName skill_remaining = StringName("skill_remaining");
	StringName souls = StringName("souls");
	StringName frozen = StringName("frozen_remaining");
	StringName blessed = StringName("blessed_remaining");
	StringName revive = StringName("revive_remaining");
	StringName revived = StringName("revived");
	StringName muster = StringName("muster");
	StringName type = StringName("type");
	StringName expires_at = StringName("expires_at");
	StringName source_id = StringName("source_id");
	StringName lands_at = StringName("lands_at");
	StringName blink = StringName("blink_remaining");
	StringName stall = StringName("stall_remaining");
	StringName blink_bonus = StringName("blink_bonus");
	StringName leaderless = StringName("leaderless");
	StringName plunder = StringName("plunder_remaining");
	StringName convert = StringName("convert_remaining");
	StringName gift = StringName("gift");
	StringName converted = StringName("converted");
};
Names *N = nullptr;

} // namespace

// ----------------------------------------------------------------------------------------------------------------

void battle_core_init_names() {
	if (N == nullptr) N = new Names();
}

void battle_core_free_names() {
	delete N;
	N = nullptr;
}

void BattleCore::_bind_methods() {
	ClassDB::bind_static_method("BattleCore", D_METHOD("rules_hash"), &BattleCore::rules_hash);
	ClassDB::bind_method(D_METHOD("configure", "unit_stats", "summon_stats", "structure_stats", "report_kinds", "constants"), &BattleCore::configure);
	ClassDB::bind_method(D_METHOD("set_units", "values"), &BattleCore::set_units);
	ClassDB::bind_method(D_METHOD("get_units"), &BattleCore::get_units);
	ClassDB::bind_method(D_METHOD("unit_count"), &BattleCore::unit_count);
	ClassDB::bind_method(D_METHOD("side_count", "side"), &BattleCore::side_count);
	ClassDB::bind_method(D_METHOD("tick", "model", "delta"), &BattleCore::tick);
	ClassDB::bind_method(D_METHOD("probe", "model", "what", "args"), &BattleCore::probe);
	ClassDB::bind_method(D_METHOD("export_units"), &BattleCore::export_units);
	ClassDB::bind_method(D_METHOD("count_units", "side", "include_downed"), &BattleCore::count_units);
	ClassDB::bind_method(D_METHOD("fielded", "side", "kind"), &BattleCore::fielded);
	ClassDB::bind_method(D_METHOD("has_marching", "side"), &BattleCore::has_marching);
	ClassDB::bind_method(D_METHOD("clear_muster", "side"), &BattleCore::clear_muster);
	ClassDB::bind_method(D_METHOD("last_unit"), &BattleCore::last_unit);
	ClassDB::bind_method(D_METHOD("append_unit", "value"), &BattleCore::append_unit);
}

String BattleCore::rules_hash() { return String(BATTLE_RULES_HASH); }

static double num(const Variant &value, double fallback = 0.0) {
	return value.get_type() == Variant::NIL ? fallback : double(value);
}

bool BattleCore::configure(const Dictionary &unit_stats, const Dictionary &summon_stats, const Dictionary &structure_stats_value, const Array &kinds_for_report, const Dictionary &constants) {
	// Every constant the rules use must come in; a model that does not hand one over keeps GDScript.
	const char *floats[] = {"FIELD_LEFT", "FIELD_RIGHT", "MIN_ATTACK_INTERVAL", "SUPPORT_INCREMENT", "SUPPORT_COOLDOWN", "SUPPORT_FOLLOW_DISTANCE", "CURSE_RADIUS", "CURSE_DURATION", "CURSE_SPEED_SCALE", "SUMMON_INTERVAL", "RAGE_HP_FRACTION", "RAGE_SPEED_MULTIPLIER", "KNOCKBACK_FRACTION", "KNOCKBACK_DISTANCE", "CASTLE_RANGE", "CASTLE_INTERVAL", "CASTLE_DAMAGE", "CASTLE_DESPERATION", "GUARD_SPOT", "FORMATION_MELEE", "MUSTER_INSET", "FORMATION_RANGED_MIN", "FORMATION_RANGED_MAX"};
	double *float_targets[] = {&FIELD_LEFT, &FIELD_RIGHT, &MIN_ATTACK_INTERVAL, &SUPPORT_INCREMENT, &SUPPORT_COOLDOWN, &SUPPORT_FOLLOW_DISTANCE, &CURSE_RADIUS, &CURSE_DURATION, &CURSE_SPEED_SCALE, &SUMMON_INTERVAL, &RAGE_HP_FRACTION, &RAGE_SPEED_MULTIPLIER, &KNOCKBACK_FRACTION, &KNOCKBACK_DISTANCE, &CASTLE_RANGE, &CASTLE_INTERVAL, &CASTLE_DAMAGE, &CASTLE_DESPERATION, &GUARD_SPOT, &FORMATION_MELEE, &MUSTER_INSET, &FORMATION_RANGED_MIN, &FORMATION_RANGED_MAX};
	for (size_t i = 0; i < sizeof(floats) / sizeof(floats[0]); i++) {
		Variant value = constants.get(floats[i], Variant());
		if (value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT) return false;
		*float_targets[i] = double(value);
	}
	const char *ints[] = {"SUPPORT_MAX_STACKS", "MAX_SKELETONS_PER_NECROMANCER", "SIDE_UNIT_LIMIT", "MAX_FALLEN"};
	int64_t *int_targets[] = {&SUPPORT_MAX_STACKS, &MAX_SKELETONS_PER_NECROMANCER, &SIDE_UNIT_LIMIT, &MAX_FALLEN};
	for (size_t i = 0; i < sizeof(ints) / sizeof(ints[0]); i++) {
		Variant value = constants.get(ints[i], Variant());
		if (value.get_type() != Variant::INT) return false;
		*int_targets[i] = int64_t(value);
	}
	kinds.clear();
	kind_index.clear();
	structure_stats = structure_stats_value;
	report_kinds = kinds_for_report;
	for (int pass = 0; pass < 2; pass++) {
		const Dictionary &table = pass == 0 ? unit_stats : summon_stats;
		Array keys = table.keys();
		for (int64_t i = 0; i < keys.size(); i++) {
			String name = keys[i];
			if (kind_index.has(name)) {
				continue; // trait_value() looks in UNIT_STATS first
			}
			KindInfo info;
			info.name = name;
			info.known = true;
			info.summon = pass == 1;
			info.stats = table[name];
			const Dictionary &stats = info.stats;
			info.hp = num(stats.get("hp", Variant()));
			info.damage = num(stats.get("damage", Variant()));
			info.has_heal = stats.has("heal");
			info.heal = num(stats.get("heal", 0.0));
			info.interval = num(stats.get("interval", Variant()));
			info.speed = num(stats.get("speed", Variant()));
			info.range = num(stats.get("range", 0.0));
			info.guard = bool(stats.get("guard", false));
			info.target_rearmost = bool(stats.get("target_rearmost", false));
			info.skill_on_self = bool(stats.get("skill_on_self", false));
			info.has_skill = stats.has("skill_cooldown") && stats["skill_cooldown"].get_type() != Variant::NIL;
			info.skill_cooldown = num(stats.get("skill_cooldown", 0.0));
			info.skill_radius = num(stats.get("skill_radius", 0.0));
			info.skill_damage = num(stats.get("skill_damage", 0.0));
			info.has_knockback = stats.has("skill_knockback");
			info.skill_knockback = num(stats.get("skill_knockback", 0.0));
			info.has_souls = stats.has("soul_max") && stats["soul_max"].get_type() != Variant::NIL;
			info.soul_max = int64_t(num(stats.get("soul_max", 0)));
			info.soul_radius = num(stats.get("soul_radius", 0.0));
			info.soul_heal_fraction = num(stats.get("soul_heal_fraction", 0.0));
			info.soul_damage_step = num(stats.get("soul_damage_step", 0.0));
			info.can_revive = stats.has("revive_delay") && stats["revive_delay"].get_type() != Variant::NIL;
			info.revive_delay = num(stats.get("revive_delay", 0.0));
			info.revive_hp_fraction = num(stats.get("revive_hp_fraction", 0.5));
			info.has_undead_bonus = stats.has("undead_bonus") && stats["undead_bonus"].get_type() != Variant::NIL;
			info.undead_bonus = num(stats.get("undead_bonus", 1.0));
			info.field_limit = int64_t(num(stats.get("field_limit", 0)));
			info.has_blink = stats.has("blink_cooldown") && stats["blink_cooldown"].get_type() != Variant::NIL;
			info.blink_cooldown = num(stats.get("blink_cooldown", 0.0));
			info.blink_range = num(stats.get("blink_range", 0.0));
			info.blink_stall = num(stats.get("blink_stall", 0.0));
			info.blink_bonus = num(stats.get("blink_bonus", 1.0));
			info.blast_radius = num(stats.get("blast_radius", 0.0));
			info.has_blast = info.blast_radius > 0.0;
			info.blast_structure_damage = num(stats.get("blast_structure_damage", 0.0));
			info.control_weakness = num(stats.get("control_weakness", 1.0));
			info.leaderless_damage = num(stats.get("leaderless_damage", 1.0));
			info.has_leaderless = info.leaderless_damage != 1.0;
			info.cost = num(stats.get("cost", 0.0));
			info.aura_radius = num(stats.get("aura_radius", 0.0));
			info.has_aura = info.aura_radius > 0.0;
			info.aura_attack_speed = num(stats.get("aura_attack_speed", 0.0));
			info.aura_cap = num(stats.get("aura_cap", 0.0));
			info.plunder_fraction = num(stats.get("plunder_fraction", 0.0));
			info.has_plunder = info.plunder_fraction > 0.0;
			info.plunder_cap = num(stats.get("plunder_cap", 0.0));
			info.plunder_cooldown = num(stats.get("plunder_cooldown", 0.0));
			Variant gifts = stats.get("gift_kinds", Variant());
			if (gifts.get_type() != Variant::NIL) info.gift_kinds = PackedStringArray(gifts);
			info.has_gift = !info.gift_kinds.is_empty();
			info.convert_radius = num(stats.get("convert_radius", 0.0));
			info.has_convert = info.convert_radius > 0.0;
			info.convert_max_cost = num(stats.get("convert_max_cost", 0.0));
			info.convert_cooldown = num(stats.get("convert_cooldown", 0.0));
			info.convert_hp = num(stats.get("convert_hp", 0.5));
			info.convert_limit = int64_t(num(stats.get("convert_limit", 0)));
			Variant smite = stats.get("smite_tags", Variant());
			if (smite.get_type() == Variant::NIL) {
				info.smite_tags.push_back("undead");
			} else {
				info.smite_tags = PackedStringArray(smite);
			}
			Variant tags = stats.get("tags", Array());
			info.tags = PackedStringArray(Array(tags));
			info.scope = info.range <= 60.0 ? 1 : (info.range >= 200.0 ? 2 : 0);
			if (info.guard) {
				info.formation_offset = 0.0;
			} else if (info.scope == 2) {
				info.formation_offset = gd_clamp(info.range * 0.5, FORMATION_RANGED_MIN, FORMATION_RANGED_MAX);
			} else {
				info.formation_offset = info.scope == 1 ? FORMATION_MELEE : 0.0;
			}
			kind_index[name] = int64_t(kinds.size());
			kinds.push_back(info);
		}
	}
	return true;
}

int BattleCore::kind_of(const String &name) {
	Variant found = kind_index.get(name, Variant());
	if (found.get_type() != Variant::NIL) {
		return int(int64_t(found));
	}
	KindInfo info; // not a unit kind (a spell caster stand-in): no traits
	info.name = name;
	kind_index[name] = int64_t(kinds.size());
	kinds.push_back(info);
	return int(kinds.size() - 1);
}

Dictionary BattleCore::to_dictionary(const Unit &u) const {
	Dictionary d;
	d[N->id] = u.id;
	d[N->side] = u.side;
	d[N->kind] = kinds[u.kind].name;
	d[N->x] = u.x;
	d[N->hp] = u.hp;
	d[N->max_hp] = u.max_hp;
	d[N->damage] = u.damage;
	d[N->heal] = u.heal;
	d[N->interval] = u.interval;
	d[N->cooldown] = u.cooldown;
	if (u.has_support_stacks) d[N->support_stacks] = u.support_stacks;
	d[N->speed] = u.speed;
	d[N->range] = u.range;
	if (u.has_summon) d[N->summon_remaining] = u.summon_remaining;
	if (u.has_skill) d[N->skill_remaining] = u.skill_remaining;
	if (u.has_souls) d[N->souls] = u.souls;
	if (u.has_frozen) d[N->frozen] = u.frozen_remaining;
	if (u.has_blessed) d[N->blessed] = u.blessed_remaining;
	if (u.has_revive) d[N->revive] = u.revive_remaining;
	if (u.has_revived) d[N->revived] = u.revived;
	if (u.has_muster) d[N->muster] = u.muster;
	if (u.has_blink) d[N->blink] = u.blink_remaining;
	if (u.has_stall) d[N->stall] = u.stall_remaining;
	if (u.has_blink_bonus) d[N->blink_bonus] = true;
	if (u.has_leaderless) d[N->leaderless] = true;
	if (u.has_plunder_cd) d[N->plunder] = u.plunder_remaining;
	if (u.has_convert_cd) d[N->convert] = u.convert_remaining;
	if (u.has_gift) d[N->gift] = kinds[u.gift].name;
	if (u.has_converted) d[N->converted] = true;
	if (!u.extra.is_empty()) {
		Array keys = u.extra.keys();
		for (int64_t i = 0; i < keys.size(); i++) d[keys[i]] = u.extra[keys[i]];
	}
	return d;
}

Unit BattleCore::from_dictionary(const Dictionary &d) {
	Unit u;
	Array keys = d.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		StringName key = keys[i];
		const Variant &v = d[keys[i]];
		if (key == N->id) u.id = int64_t(v);
		else if (key == N->side) u.side = int64_t(v);
		else if (key == N->kind) u.kind = kind_of(String(v));
		else if (key == N->x) u.x = double(v);
		else if (key == N->hp) u.hp = double(v);
		else if (key == N->max_hp) u.max_hp = double(v);
		else if (key == N->damage) u.damage = double(v);
		else if (key == N->heal) u.heal = double(v);
		else if (key == N->interval) u.interval = double(v);
		else if (key == N->cooldown) u.cooldown = double(v);
		else if (key == N->support_stacks) { u.has_support_stacks = true; u.support_stacks = int64_t(v); }
		else if (key == N->speed) u.speed = double(v);
		else if (key == N->range) u.range = double(v);
		else if (key == N->summon_remaining) { u.has_summon = true; u.summon_remaining = double(v); }
		else if (key == N->skill_remaining) { u.has_skill = true; u.skill_remaining = double(v); }
		else if (key == N->souls) { u.has_souls = true; u.souls = int64_t(v); }
		else if (key == N->frozen) { u.has_frozen = true; u.frozen_remaining = double(v); }
		else if (key == N->blessed) { u.has_blessed = true; u.blessed_remaining = double(v); }
		else if (key == N->revive) { u.has_revive = true; u.revive_remaining = double(v); }
		else if (key == N->revived) { u.has_revived = true; u.revived = v; }
		else if (key == N->muster) { u.has_muster = true; u.muster = v; }
		else if (key == N->blink) { u.has_blink = true; u.blink_remaining = double(v); }
		else if (key == N->stall) { u.has_stall = true; u.stall_remaining = double(v); }
		else if (key == N->blink_bonus) u.has_blink_bonus = true;
		else if (key == N->leaderless) u.has_leaderless = true;
		else if (key == N->plunder) { u.has_plunder_cd = true; u.plunder_remaining = double(v); }
		else if (key == N->convert) { u.has_convert_cd = true; u.convert_remaining = double(v); }
		else if (key == N->gift) { u.has_gift = true; u.gift = kind_of(String(v)); }
		else if (key == N->converted) u.has_converted = true;
		else u.extra[keys[i]] = v;
	}
	if (!d.has(N->support_stacks)) u.has_support_stacks = false;
	if (u.kind < 0) u.kind = kind_of("");
	return u;
}

void BattleCore::write_into(Dictionary &d, const Unit &u) const {
	d[N->id] = u.id;
	d[N->side] = u.side;
	d[N->kind] = kinds[u.kind].name;
	d[N->x] = u.x;
	d[N->hp] = u.hp;
	d[N->max_hp] = u.max_hp;
	d[N->damage] = u.damage;
	d[N->heal] = u.heal;
	d[N->interval] = u.interval;
	d[N->cooldown] = u.cooldown;
	if (u.has_support_stacks) d[N->support_stacks] = u.support_stacks;
	else d.erase(N->support_stacks);
	d[N->speed] = u.speed;
	d[N->range] = u.range;
	if (u.has_summon) d[N->summon_remaining] = u.summon_remaining;
	else d.erase(N->summon_remaining);
	if (u.has_skill) d[N->skill_remaining] = u.skill_remaining;
	else d.erase(N->skill_remaining);
	if (u.has_souls) d[N->souls] = u.souls;
	else d.erase(N->souls);
	if (u.has_frozen) d[N->frozen] = u.frozen_remaining;
	else d.erase(N->frozen);
	if (u.has_blessed) d[N->blessed] = u.blessed_remaining;
	else d.erase(N->blessed);
	if (u.has_revive) d[N->revive] = u.revive_remaining;
	else d.erase(N->revive);
	if (u.has_revived) d[N->revived] = u.revived;
	else d.erase(N->revived);
	if (u.has_muster) d[N->muster] = u.muster;
	else d.erase(N->muster);
	if (u.has_blink) d[N->blink] = u.blink_remaining;
	else d.erase(N->blink);
	if (u.has_stall) d[N->stall] = u.stall_remaining;
	else d.erase(N->stall);
	if (u.has_blink_bonus) d[N->blink_bonus] = true;
	else d.erase(N->blink_bonus);
	if (u.has_leaderless) d[N->leaderless] = true;
	else d.erase(N->leaderless);
	if (u.has_plunder_cd) d[N->plunder] = u.plunder_remaining;
	else d.erase(N->plunder);
	if (u.has_convert_cd) d[N->convert] = u.convert_remaining;
	else d.erase(N->convert);
	if (u.has_gift) d[N->gift] = kinds[u.gift].name;
	else d.erase(N->gift);
	if (u.has_converted) d[N->converted] = true;
	else d.erase(N->converted);
}

Dictionary BattleCore::handle_of(Unit &u) {
	if (!u.has_handle) {
		u.handle = to_dictionary(u);
		u.has_handle = true;
	}
	return u.handle;
}

void BattleCore::set_units(const Array &values) {
	units.clear();
	units.reserve(values.size());
	for (int64_t i = 0; i < values.size(); i++) {
		Dictionary d = values[i];
		Unit u = from_dictionary(d);
		u.handle = d; // `units = values`: these dictionaries are the units now
		u.has_handle = true;
		units.push_back(u);
	}
	exposed = values;
	has_exposed = true;
}

Array BattleCore::get_units() {
	if (!has_exposed) {
		exposed = Array();
		for (Unit &u : units) exposed.push_back(handle_of(u));
		has_exposed = true;
	}
	return exposed;
}

// Reads back what GDScript may have changed: the handed-out array (entries added, removed or replaced) and
// every unit dictionary it holds.
void BattleCore::sync_in() {
	if (has_exposed) {
		Array values = exposed;
		std::vector<Unit> rebuilt;
		rebuilt.reserve(values.size());
		size_t cursor = 0;
		for (int64_t i = 0; i < values.size(); i++) {
			Dictionary d = values[i];
			Unit u = from_dictionary(d);
			u.handle = d;
			u.has_handle = true;
			(void)cursor;
			rebuilt.push_back(u);
		}
		units.swap(rebuilt); // the array stays handed out (and valid) until the next tick replaces it
		return;
	}
	for (Unit &u : units) {
		if (u.has_handle) {
			Dictionary d = u.handle;
			Unit fresh = from_dictionary(d);
			fresh.handle = d;
			fresh.has_handle = true;
			u = fresh;
		}
	}
}

// Writes the engine's units back into the dictionaries GDScript holds.
void BattleCore::sync_out() {
	for (Unit &u : units) {
		if (u.has_handle) write_into(u.handle, u);
	}
}

int64_t BattleCore::unit_count() {
	sync_in();
	return int64_t(units.size());
}

int64_t BattleCore::side_count(int64_t side) {
	sync_in();
	int64_t count = 0;
	for (const Unit &u : units) {
		if (u.side == side) count++;
	}
	return count;
}

Array BattleCore::export_units() {
	sync_in();
	Array values;
	for (const Unit &u : units) values.push_back(to_dictionary(u));
	return values;
}

int64_t BattleCore::count_units(int64_t side, bool include_downed) {
	sync_in();
	int64_t count = 0;
	for (const Unit &u : units) {
		if (u.side == side && (u.hp > 0.0 || (include_downed && u.has_revive))) count++;
	}
	return count;
}

int64_t BattleCore::fielded(int64_t side, const String &kind) {
	sync_in();
	int k = kind_of(kind);
	int64_t count = 0;
	for (const Unit &u : units) {
		if (u.side == side && u.kind == k && (u.hp > 0.0 || u.has_revive)) count++;
	}
	return count;
}

bool BattleCore::has_marching(int64_t side) {
	sync_in();
	for (const Unit &u : units) {
		if (u.side == side && u.hp > 0.0 && !u.has_muster) return true;
	}
	return false;
}

void BattleCore::clear_muster(int64_t side) {
	sync_in();
	for (Unit &u : units) {
		if (u.side == side) {
			u.has_muster = false;
			u.muster = Variant();
		}
	}
	sync_out();
}

void BattleCore::append_unit(const Dictionary &value) {
	if (has_exposed) {
		exposed.push_back(value); // part of the handed-out array: read back with it
		return;
	}
	units.push_back(from_dictionary(value));
}

Dictionary BattleCore::last_unit() {
	sync_in();
	if (units.empty()) return Dictionary();
	return handle_of(units.back());
}

// ----------------------------------------------------------------------------------------------------------------
// The tick. State other than units belongs to the GDScript model and is edited in place.

namespace {

struct Tick {
	BattleCore *core = nullptr;
	std::vector<KindInfo> *kinds = nullptr;
	std::vector<Unit> *units = nullptr;
	Object *model = nullptr;
	Dictionary structure_stats;
	double delta = 0.0;
	double elapsed = 0.0;
	int64_t winner = -1;
	int64_t next_unit_id = 1;
	Array cheats, curses, structures, resources, spawn_cooldowns, spell_cooldowns, spell_uses, base_hp, base_max_hp,
			invulnerable_bases, castle_cooldowns, modifiers, shelter, advance_limit, formation, combat_events, battle_report,
			fallen, spell_casts;
	Dictionary structure_expirations, structure_cooldowns, summon_timers, summon_owners, revive_used, knocked_back,
			first_struck, cheat_saved, announced_deaths, announced_structure_deaths;
	bool curses_replaced = false, structures_replaced = false, casts_replaced = false;
	Lane lanes[2];
	std::vector<double> curse_xs[2];
	int fronts[2] = {-1, -1};
	std::vector<int> needy[2];
	NeedyLane needy_lanes[2];
	bool supports_moved = false;
	int healer = -1, necromancer = -1, skeleton = -1, berserker = -1, warlock = -1, zombie = -1, paladin = -1;
	std::vector<int> auras[2];

	std::vector<Unit> &U() { return *units; }
	const KindInfo &K(int kind) { return (*kinds)[kind]; }

	Variant modifier(int64_t side, const String &key, const Variant &fallback) {
		if (side < 0 || side >= 2) return fallback;
		Dictionary m = modifiers[side];
		return m.get(key, fallback);
	}

	bool sheltered(const Unit &u) {
		double depth = double(shelter[u.side]);
		if (depth <= 0.0) return false;
		return u.side == 0 ? u.x < FIELD_LEFT + depth : u.x > FIELD_RIGHT - depth;
	}
	bool targetable(const Unit &u) { return !sheltered(u); }

	double curse_speed_scale(int64_t side, double x) {
		const std::vector<double> &xs = curse_xs[1 - side];
		int64_t at = lower(xs, x);
		if ((at < int64_t(xs.size()) && std::fabs(xs[at] - x) <= CURSE_RADIUS) || (at > 0 && std::fabs(xs[at - 1] - x) <= CURSE_RADIUS)) {
			return CURSE_SPEED_SCALE;
		}
		return 1.0;
	}

	bool is_enraged(const Unit &u) {
		return (u.kind == berserker || (u.has_gift && u.gift == berserker)) && u.hp > 0.0 && u.hp <= u.max_hp * RAGE_HP_FRACTION;
	}

	// The kind whose revive trait a unit uses (its own, or a preacher's zombie gift), or -1.
	int revive_kind(const Unit &u) {
		if (K(u.kind).can_revive) return u.kind;
		if (u.has_gift && K(u.gift).can_revive) return u.gift;
		return -1;
	}

	double support_attack_speed(const Unit &u) {
		if (u.hp <= 0.0) return 1.0;
		double curse = curse_speed_scale(u.side, u.x);
		if (u.kind == healer) return curse;
		int64_t stacks = u.has_support_stacks ? u.support_stacks : 0;
		double multiplier = 1.0 + double(gd_mini(SUPPORT_MAX_STACKS, gd_maxi(0, stacks))) * SUPPORT_INCREMENT;
		// A hero's aura (the strongest in reach; auras do not stack) adds to mage stacks, up to the aura's cap.
		double aura = 0.0, cap = 0.0;
		for (int index : auras[u.side]) {
			const Unit &hero = U()[index];
			const KindInfo &info = K(hero.kind);
			if (std::fabs(hero.x - u.x) <= info.aura_radius && info.aura_attack_speed > aura) {
				aura = info.aura_attack_speed;
				cap = info.aura_cap;
			}
		}
		if (aura > 0.0) multiplier = gd_minf(multiplier + aura, 1.0 + cap);
		if (u.has_blessed) {
			Dictionary blessing = structure_stats["blessing"];
			multiplier *= double(blessing["attack_speed"]);
		}
		return multiplier * (is_enraged(u) ? RAGE_SPEED_MULTIPLIER : 1.0) * curse;
	}

	double swamp_scale(const Unit &u) {
		Dictionary swamp = structure_stats["swamp"];
		for (int64_t i = 0; i < structures.size(); i++) {
			Dictionary s = structures[i];
			if (String(s[N->kind]) == "swamp" && int64_t(s[N->side]) != u.side && double(s[N->hp]) > 0.0 && std::fabs(double(s[N->x]) - u.x) <= double(swamp["radius"])) {
				double scale = double(swamp["speed_scale"]);
				double weakness = K(u.kind).control_weakness;
				return weakness == 1.0 ? scale : gd_maxf(0.0, 1.0 - (1.0 - scale) * weakness);
			}
		}
		return 1.0;
	}

	Dictionary blocking_wall(int64_t side, double origin, double target_x) {
		Dictionary best;
		double best_distance = INF;
		for (int64_t i = 0; i < structures.size(); i++) {
			Dictionary s = structures[i];
			if (int64_t(s[N->side]) == side || String(s[N->kind]) != "wall" || double(s[N->hp]) <= 0.0) continue;
			double wall_x = double(s[N->x]);
			bool between = (origin < wall_x && wall_x < target_x) || (target_x < wall_x && wall_x < origin);
			double distance = std::fabs(wall_x - origin);
			if (between && distance < best_distance) {
				best = s;
				best_distance = distance;
			}
		}
		return best;
	}

	void record_damage(int64_t side, const String &attacker_kind, double amount, bool killed) {
		String kind = attacker_kind == "skeleton" ? String("necromancer") : (attacker_kind == "royal_guard" ? String("king") : attacker_kind);
		if (side < 0 || side > 1) return;
		Dictionary report = battle_report[side];
		Dictionary rows = report["units"];
		if (!rows.has(kind)) return;
		report["damage"] = double(report["damage"]) + amount;
		Dictionary row = rows[kind];
		row["damage"] = double(row["damage"]) + amount;
		if (killed) {
			report["kills"] = int64_t(report["kills"]) + 1;
			row["kills"] = int64_t(row["kills"]) + 1;
		}
	}

	void event(const Dictionary &e) { combat_events.push_back(e); }

	void install_curse(const Unit &caster, double x) {
		Array kept;
		for (int64_t i = 0; i < curses.size(); i++) {
			Dictionary c = curses[i];
			if (int64_t(c[N->source_id]) != caster.id) kept.push_back(c);
		}
		curses = kept;
		curses_replaced = true;
		Dictionary curse;
		curse[N->source_id] = caster.id;
		curse[N->side] = caster.side;
		curse[N->x] = x;
		curse[N->expires_at] = elapsed + CURSE_DURATION;
		curses.push_back(curse);
		Dictionary e;
		e[N->type] = "CURSE";
		e[N->source_id] = caster.id;
		e[N->x] = x;
		event(e);
	}

	bool has_tag(int kind, const String &tag) { return K(kind).tags.has(tag); }

	// attacker: a unit (attacker_unit >= 0) or a spell caster stand-in (id 0, side, kind, x).
	void damage_target(int attacker_unit, int64_t caster_side, const String &caster_kind, double caster_x, int64_t caster_id, const Target &target, double damage, bool show_attack) {
		int attacker_kind = attacker_unit >= 0 ? U()[attacker_unit].kind : core_kind(caster_kind);
		const KindInfo &ak = K(attacker_kind);
		// A preacher's paladin gift smites like a paladin.
		const KindInfo &smiter = (attacker_unit >= 0 && U()[attacker_unit].has_gift && K(U()[attacker_unit].gift).has_undead_bonus) ? K(U()[attacker_unit].gift) : ak;
		bool target_is_unit = target.unit >= 0;
		bool smites_undead = false;
		if (smiter.has_undead_bonus && target_is_unit) {
			for (int64_t i = 0; i < smiter.smite_tags.size(); i++) {
				if (has_tag(U()[target.unit].kind, smiter.smite_tags[i])) {
					smites_undead = true;
					break;
				}
			}
		}
		if (smites_undead) damage *= smiter.undead_bonus;
		double target_hp = target_is_unit ? U()[target.unit].hp : double(target.structure[N->hp]);
		double before = gd_maxf(0.0, target_hp);
		double effective = gd_minf(before, gd_maxf(0.0, damage));
		int64_t a_side = attacker_unit >= 0 ? U()[attacker_unit].side : caster_side;
		record_damage(a_side, ak.name, effective, target_is_unit && before > 0.0 && effective >= before);
		double new_hp = gd_max(0.0, target_hp - damage);
		int64_t target_id;
		double target_x;
		if (target_is_unit) {
			Unit &t = U()[target.unit];
			t.hp = new_hp;
			if (smites_undead && t.hp <= 0.0) revive_used[t.id] = true;
			target_id = t.id;
			target_x = t.x;
			if (before > 0.0 && t.hp <= 0.0 && attacker_unit >= 0) on_kill(attacker_unit, target.unit);
		} else {
			Dictionary s = target.structure;
			s[N->hp] = new_hp;
			target_id = int64_t(s[N->id]);
			target_x = double(s[N->x]);
		}
		if (show_attack) {
			Dictionary e;
			e[N->type] = "ATTACK";
			e["attacker_id"] = attacker_unit >= 0 ? U()[attacker_unit].id : caster_id;
			e["target_id"] = target_is_unit ? Variant(target_id) : target.structure[N->id];
			e["attack_kind"] = ak.name;
			e[N->x] = attacker_unit >= 0 ? U()[attacker_unit].x : caster_x;
			event(e);
		}
		{
			Dictionary e;
			e[N->type] = "DAMAGE";
			e["target_id"] = target_is_unit ? Variant(target_id) : target.structure[N->id];
			e["amount"] = damage;
			e[N->x] = target_is_unit ? Variant(target_x) : target.structure[N->x];
			event(e);
		}
		if (target_is_unit) {
			Unit &t = U()[target.unit];
			if (t.hp > 0.0 && t.hp <= t.max_hp * KNOCKBACK_FRACTION && !knocked_back.has(t.id)) {
				knocked_back[t.id] = true;
				double away = t.side == 0 ? -1.0 : 1.0;
				t.x = gd_clamp(t.x + away * KNOCKBACK_DISTANCE * double(modifier(t.side, "knockback", 1.0)), FIELD_LEFT, FIELD_RIGHT);
				Dictionary e;
				e[N->type] = "KNOCKBACK";
				e["target_id"] = t.id;
				e[N->x] = t.x;
				event(e);
			}
		}
		if (attacker_unit >= 0 && U()[attacker_unit].kind == warlock) {
			double x = target_is_unit ? U()[target.unit].x : double(target.structure[N->x]);
			install_curse(U()[attacker_unit], x);
		}
	}

	int core_kind(const String &name);

	// A unit's attack felled `victim`: a raider takes some of the enemy's resources, a preacher takes the
	// victim's ability.
	void on_kill(int killer, int victim) {
		Unit &k = U()[killer];
		const KindInfo &info = K(k.kind);
		const Unit &v = U()[victim];
		if (info.has_plunder && !k.has_plunder_cd && !K(v.kind).summon) {
			int64_t enemy = 1 - k.side;
			double amount = gd_minf(gd_minf(info.plunder_cap, K(v.kind).cost * info.plunder_fraction), double(resources[enemy]));
			if (amount > 0.0) {
				resources[enemy] = double(resources[enemy]) - amount;
				double capacity = double(model->call("resource_capacity", k.side));
				resources[k.side] = gd_minf(capacity, double(resources[k.side]) + amount);
				k.has_plunder_cd = true;
				k.plunder_remaining = info.plunder_cooldown;
				Dictionary e;
				e[N->type] = "PLUNDER";
				e[N->source_id] = k.id;
				e[N->x] = k.x;
				e["from_x"] = v.x;
				e["amount"] = amount;
				event(e);
			}
		}
		if (info.has_gift && info.gift_kinds.has(K(v.kind).name)) {
			k.has_gift = true;
			k.gift = v.kind;
			Dictionary e;
			e[N->type] = "GIFT";
			e[N->source_id] = k.id;
			e[N->kind] = K(v.kind).name;
			e[N->x] = k.x;
			event(e);
		}
	}

	// ---------- indexes ----------

	void index_curses() {
		for (int side = 0; side < 2; side++) {
			std::vector<double> xs;
			for (int64_t i = 0; i < curses.size(); i++) {
				Dictionary c = curses[i];
				if (int64_t(c[N->side]) == side && double(c[N->expires_at]) > elapsed) xs.push_back(double(c[N->x]));
			}
			std::sort(xs.begin(), xs.end());
			curse_xs[side] = xs;
		}
	}

	void index_lanes() {
		std::vector<std::pair<double, int>> keyed[2];
		double left_zone = double(shelter[0]) > 0.0 ? FIELD_LEFT + double(shelter[0]) : -INF;
		double right_zone = double(shelter[1]) > 0.0 ? FIELD_RIGHT - double(shelter[1]) : INF;
		for (int i = 0; i < int(U().size()); i++) {
			const Unit &u = U()[i];
			if (u.hp > 0.0) {
				if (u.side == 0 ? u.x >= left_zone : u.x <= right_zone) keyed[u.side].push_back({u.x, i});
			}
		}
		for (int side = 0; side < 2; side++) {
			std::sort(keyed[side].begin(), keyed[side].end());
			Lane &lane = lanes[side];
			lane.xs.clear();
			lane.order.clear();
			lane.guard_xs.clear();
			lane.guard_order.clear();
			for (auto &entry : keyed[side]) {
				lane.xs.push_back(entry.first);
				lane.order.push_back(entry.second);
				if (K(U()[entry.second].kind).guard) {
					lane.guard_xs.push_back(entry.first);
					lane.guard_order.push_back(entry.second);
				}
			}
		}
	}

	void index_fronts() {
		auras[0].clear();
		auras[1].clear();
		for (int i = 0; i < int(U().size()); i++) {
			if (U()[i].hp > 0.0 && K(U()[i].kind).has_aura) auras[U()[i].side].push_back(i);
		}
		fronts[0] = fronts[1] = -1;
		needy[0].clear();
		needy[1].clear();
		for (int i = 0; i < int(U().size()); i++) {
			const Unit &u = U()[i];
			if (u.kind == healer || u.hp <= 0.0) continue;
			int64_t stacks = u.has_support_stacks ? u.support_stacks : 0;
			if (stacks < SUPPORT_MAX_STACKS) needy[u.side].push_back(i);
			double direction = u.side == 0 ? 1.0 : -1.0;
			if (fronts[u.side] < 0 || direction * u.x > direction * U()[fronts[u.side]].x) fronts[u.side] = i;
		}
		for (int side = 0; side < 2; side++) {
			std::vector<std::pair<double, int>> keyed;
			for (int i = 0; i < int(needy[side].size()); i++) keyed.push_back({U()[needy[side][i]].x, i});
			std::sort(keyed.begin(), keyed.end());
			NeedyLane &lane = needy_lanes[side];
			lane.xs.clear();
			lane.order.clear();
			for (auto &entry : keyed) {
				lane.xs.push_back(entry.first);
				lane.order.push_back(entry.second);
			}
		}
	}

	// ---------- targeting ----------

	int nearest_enemy(const Unit &u) {
		const Lane &lane = lanes[1 - u.side];
		const std::vector<double> &xs = lane.xs;
		if (xs.empty()) return -1;
		double x = u.x, reach = u.range;
		int best = -1;
		double best_distance = INF;
		int best_order = 1 << 30;
		int64_t right = lower(xs, x);
		if (right < int64_t(xs.size()) && std::fabs(xs[right] - x) <= reach) {
			best = lane.order[right];
			best_distance = std::fabs(xs[right] - x);
			best_order = lane.order[right];
		}
		if (right > 0) {
			int64_t left = run_start(xs, right - 1);
			double distance = std::fabs(xs[left] - x);
			if (distance <= reach && (distance < best_distance || (distance == best_distance && lane.order[left] < best_order))) {
				best = lane.order[left];
			}
		}
		return best;
	}

	int guard_beside(const Unit &u, int nearest) {
		if (K(U()[nearest].kind).guard) return nearest;
		double x = u.x, reach = u.range, spot = U()[nearest].x;
		int best = nearest;
		double best_distance = INF;
		const Lane &lane = lanes[1 - u.side];
		const std::vector<double> &gxs = lane.guard_xs;
		int64_t low = lower(gxs, spot - GUARD_SPOT);
		int64_t high = upper(gxs, spot + GUARD_SPOT);
		if (low >= high) return best;
		int64_t split = lower(gxs, x);
		split = split < low ? low : (split > high ? high : split);
		int best_order = 1 << 30;
		if (split < high) {
			double distance = std::fabs(gxs[split] - x);
			if (distance <= reach) {
				best = lane.guard_order[split];
				best_distance = distance;
				best_order = lane.guard_order[split];
			}
		}
		if (split > low) {
			int64_t left = std::max(low, run_start(gxs, split - 1));
			double distance = std::fabs(gxs[left] - x);
			if (distance <= reach && (distance < best_distance || (distance == best_distance && lane.guard_order[left] < best_order))) {
				best = lane.guard_order[left];
			}
		}
		return best;
	}

	int rearmost_enemy(const Unit &u) {
		const Lane &lane = lanes[1 - u.side];
		const std::vector<double> &xs = lane.xs;
		double x = u.x, reach = u.range;
		int64_t size = int64_t(xs.size());
		int64_t low = lower(xs, x - reach);
		while (low < size && std::fabs(xs[low] - x) > reach && xs[low] < x) low++;
		int64_t high = upper(xs, x + reach) - 1;
		while (high >= 0 && std::fabs(xs[high] - x) > reach && xs[high] > x) high--;
		if (low >= size || high < 0 || low > high) return -1;
		int best = lane.order[low];
		double best_distance = std::fabs(xs[low] - x);
		int best_order = lane.order[low];
		int64_t far = run_start(xs, high);
		double distance = std::fabs(xs[far] - x);
		if (distance > best_distance || (distance == best_distance && lane.order[far] < best_order)) best = lane.order[far];
		return best;
	}

	bool enemy_ahead(const Unit &u, double reach) {
		const std::vector<double> &xs = lanes[1 - u.side].xs;
		double x = u.x;
		if (u.side == 0) {
			int64_t at = lower(xs, x);
			return at < int64_t(xs.size()) && std::fabs(xs[at] - x) <= reach;
		}
		int64_t behind = upper(xs, x) - 1;
		return behind >= 0 && std::fabs(xs[behind] - x) <= reach;
	}

	bool has_health(const String &kind) {
		Dictionary stats = structure_stats.get(kind, Dictionary());
		return double(stats.get("hp", 0.0)) > 0.0;
	}

	Target find_target(int index) {
		const Unit &u = U()[index];
		Target result;
		if (K(u.kind).target_rearmost) {
			int rearmost = rearmost_enemy(u);
			if (rearmost >= 0) {
				result.unit = rearmost;
				return result;
			}
		}
		int best_unit = nearest_enemy(u);
		if (best_unit >= 0) {
			best_unit = guard_beside(u, best_unit);
			Dictionary wall = blocking_wall(u.side, u.x, U()[best_unit].x);
			if (!wall.is_empty()) {
				if (std::fabs(double(wall[N->x]) - u.x) <= u.range + 12.0) result.structure = wall;
				return result;
			}
			result.unit = best_unit;
			return result;
		}
		Dictionary best_structure;
		double best_distance = INF;
		for (int64_t i = 0; i < structures.size(); i++) {
			Dictionary s = structures[i];
			if (int64_t(s[N->side]) == u.side || double(s[N->hp]) <= 0.0 || !has_health(String(s[N->kind]))) continue;
			double distance = std::fabs(double(s[N->x]) - u.x);
			if (distance <= u.range + 12.0 && distance < best_distance) {
				Dictionary wall = blocking_wall(u.side, u.x, double(s[N->x]));
				best_structure = wall.is_empty() ? s : wall;
				best_distance = std::fabs(double(best_structure[N->x]) - u.x);
			}
		}
		result.structure = best_structure;
		return result;
	}

	double held_stride(const Unit &u, double stride, double direction) {
		int64_t side = u.side;
		double limit = double(advance_limit[side]);
		if (u.has_muster) {
			limit = side == 0 ? FIELD_LEFT + double(shelter[side]) - MUSTER_INSET : FIELD_RIGHT - double(shelter[side]) + MUSTER_INSET;
		} else if (bool(formation[side])) {
			limit -= direction * K(u.kind).formation_offset;
		}
		if (direction * (stride - limit) <= 0.0) return stride;
		double x = u.x;
		if (direction * (x - limit) <= 0.0) return limit;
		double back = x - direction * u.speed * swamp_scale(u) * delta;
		return side == 0 ? gd_maxf(back, limit) : gd_minf(back, limit);
	}

	double attack_damage(const Unit &u) {
		double damage = u.damage * (1.0 + double(u.has_souls ? u.souls : 0) * K(u.kind).soul_damage_step);
		if (u.has_leaderless) damage *= K(u.kind).leaderless_damage;
		return damage;
	}

	double strike_damage(Unit &u) {
		double damage = attack_damage(u);
		if (double(modifier(u.side, "first_strike", 0.0)) > 0.0 && !first_struck.has(u.id)) {
			first_struck[u.id] = true;
			damage *= 2.0;
		}
		if (u.has_blink_bonus) {
			u.has_blink_bonus = false;
			damage *= K(u.kind).blink_bonus;
		}
		return damage;
	}

	// _blink_mark: the enemy deepest behind the enemy line within blink range, past the blinker's own reach.
	int blink_mark(const Unit &u) {
		double reach = K(u.kind).blink_range;
		double direction = u.side == 0 ? 1.0 : -1.0;
		int best = -1;
		double best_depth = -INF;
		for (int i = 0; i < int(U().size()); i++) {
			const Unit &enemy = U()[i];
			if (enemy.side == u.side || enemy.hp <= 0.0 || !targetable(enemy)) continue;
			double ahead = direction * (enemy.x - u.x);
			if (ahead <= u.range + 20.0 || ahead > reach) continue;
			if (ahead > best_depth) {
				best = i;
				best_depth = ahead;
			}
		}
		return best;
	}

	void blink(int index, double mark_x) {
		Unit &u = U()[index];
		if (u.hp <= 0.0) return;
		double direction = u.side == 0 ? 1.0 : -1.0;
		double from_x = u.x;
		double x = gd_clamp(mark_x - direction * 18.0, FIELD_LEFT, FIELD_RIGHT);
		x = u.side == 0 ? gd_minf(x, double(advance_limit[0])) : gd_maxf(x, double(advance_limit[1]));
		u.x = x;
		u.has_stall = true;
		u.stall_remaining = K(u.kind).blink_stall;
		u.has_blink_bonus = true;
		Dictionary e;
		e[N->type] = "BLINK";
		e["unit_id"] = u.id;
		e["from_x"] = from_x;
		e[N->x] = x;
		event(e);
	}

	void blast(int index) {
		const KindInfo &info = K(U()[index].kind);
		int64_t side = U()[index].side;
		double x = U()[index].x;
		double radius = info.blast_radius;
		double damage = attack_damage(U()[index]);
		double growth = U()[index].damage / gd_maxf(0.01, info.damage);
		double heavy = info.blast_structure_damage * growth;
		U()[index].hp = 0.0;
		{
			Dictionary e;
			e[N->type] = "BLAST";
			e[N->source_id] = U()[index].id;
			e[N->kind] = info.name;
			e[N->x] = x;
			e["radius"] = radius;
			event(e);
		}
		for (int i = 0; i < int(U().size()); i++) {
			if (U()[i].hp <= 0.0 || std::fabs(U()[i].x - x) > radius) continue;
			if (U()[i].side != side) {
				if (targetable(U()[i])) {
					Target t;
					t.unit = i;
					damage_target(index, 0, String(), 0.0, 0, t, damage, false);
				}
			} else {
				Unit &ally = U()[i];
				ally.hp = gd_maxf(0.0, ally.hp - damage);
				Dictionary e;
				e[N->type] = "DAMAGE";
				e["target_id"] = ally.id;
				e["amount"] = damage;
				e[N->x] = ally.x;
				event(e);
			}
		}
		for (int64_t i = 0; i < structures.size(); i++) {
			Dictionary s = structures[i];
			if (int64_t(s[N->side]) == side || double(s[N->hp]) <= 0.0 || std::fabs(double(s[N->x]) - x) > radius) continue;
			double before = double(s[N->hp]);
			record_damage(side, info.name, gd_minf(before, heavy), false);
			s[N->hp] = gd_maxf(0.0, before - heavy);
			Dictionary e;
			e[N->type] = "DAMAGE";
			e["target_id"] = s[N->id];
			e["amount"] = heavy;
			e[N->x] = s[N->x];
			event(e);
		}
		int64_t enemy_side = 1 - side;
		double enemy_base_x = side == 0 ? FIELD_RIGHT : FIELD_LEFT;
		if (std::fabs(enemy_base_x - x) <= radius) {
			record_damage(side, info.name, gd_minf(heavy, double(base_hp[enemy_side])), false);
			if (!bool(invulnerable_bases[enemy_side])) {
				base_hp[enemy_side] = gd_maxf(0.0, double(base_hp[enemy_side]) - heavy);
				Dictionary e;
				e[N->type] = "BASE_HIT";
				e[N->side] = enemy_side;
				e["amount"] = heavy;
				e[N->x] = enemy_base_x;
				event(e);
			}
		}
	}

	// ---------- supports ----------

	void tick_support(int index) {
		Unit &u = U()[index];
		if (u.cooldown <= 0.0) {
			bool cast = false;
			const NeedyLane &lane = needy_lanes[u.side];
			double x = u.x;
			double reach = u.range + 0.001;
			int64_t low = lower(lane.xs, x - reach);
			int64_t high = upper(lane.xs, x + reach);
			if (low < high) {
				std::vector<int> picked;
				for (int64_t i = low; i < high; i++) picked.push_back(lane.order[i]);
				std::sort(picked.begin(), picked.end());
				for (int p : picked) {
					Unit &ally = U()[needy[u.side][p]];
					if (ally.side == u.side && ally.kind != healer && ally.hp > 0.0 && std::fabs(ally.x - U()[index].x) <= U()[index].range) {
						int64_t stacks = ally.has_support_stacks ? ally.support_stacks : 0;
						if (stacks < SUPPORT_MAX_STACKS) {
							ally.support_stacks = stacks + 1;
							ally.has_support_stacks = true;
							Dictionary e;
							e[N->type] = "SUPPORT_BUFF";
							e[N->source_id] = U()[index].id;
							e["target_id"] = ally.id;
							e["stacks"] = ally.support_stacks;
							e[N->x] = ally.x;
							event(e);
							cast = true;
						}
					}
				}
			}
			if (cast) U()[index].cooldown = SUPPORT_COOLDOWN;
		}
		Unit &s = U()[index];
		double direction = s.side == 0 ? 1.0 : -1.0;
		int frontline = fronts[s.side];
		double step = s.speed * swamp_scale(s) * delta;
		if (sheltered(s) && !s.has_muster) {
			supports_moved = true;
			s.x = held_stride(s, gd_clamp(s.x + direction * step, FIELD_LEFT, FIELD_RIGHT), direction);
			return;
		}
		if (frontline >= 0 && direction * (U()[frontline].x - s.x) <= SUPPORT_FOLLOW_DISTANCE) return;
		bool ahead = enemy_ahead(s, gd_max(s.range, step));
		if (ahead || !blocking_wall(s.side, s.x, s.x + direction * step).is_empty() || find_target(index).valid()) return;
		double enemy_base_x = s.side == 0 ? FIELD_RIGHT : FIELD_LEFT;
		if (std::fabs(s.x - enemy_base_x) <= s.range) return;
		double destination = s.x + direction * step;
		if (frontline >= 0) {
			double follow_x = U()[frontline].x - direction * SUPPORT_FOLLOW_DISTANCE;
			destination = direction > 0.0 ? gd_min(destination, follow_x) : gd_max(destination, follow_x);
		}
		supports_moved = true;
		s.x = held_stride(s, gd_clamp(destination, FIELD_LEFT, FIELD_RIGHT), direction);
	}

	// ---------- units appearing and leaving ----------

	bool side_full(int64_t side) {
		int64_t count = 0;
		for (const Unit &u : U()) {
			if (u.side == side) count++;
		}
		Dictionary on = cheats[side];
		return count >= (on.has("army_cap") ? SIDE_UNIT_LIMIT * 2 : SIDE_UNIT_LIMIT);
	}

	void create_unit(int64_t side, int kind, double hp_scale, double damage_scale, double x) {
		const KindInfo &info = K(kind);
		Unit u;
		u.id = next_unit_id;
		u.side = side;
		u.kind = kind;
		u.x = gd_clamp(x, FIELD_LEFT, FIELD_RIGHT);
		u.hp = info.hp * hp_scale;
		u.max_hp = info.hp * hp_scale;
		u.damage = info.damage * damage_scale;
		u.heal = info.heal * damage_scale;
		u.interval = info.interval;
		u.cooldown = kind == healer ? 0.0 : gd_max(MIN_ATTACK_INTERVAL, info.interval);
		u.support_stacks = 0;
		u.has_support_stacks = true;
		u.speed = info.speed;
		u.range = info.range + (info.scope == 2 ? double(modifier(side, "range:ranged", 0.0)) : 0.0);
		if (kind == necromancer) {
			summon_timers[next_unit_id] = SUMMON_INTERVAL;
			u.has_summon = true;
			u.summon_remaining = SUMMON_INTERVAL;
		}
		if (info.has_skill) {
			u.has_skill = true;
			u.skill_remaining = info.skill_cooldown;
		}
		if (info.has_souls) {
			u.has_souls = true;
			u.souls = 0;
		}
		if (info.has_blink) {
			u.has_blink = true;
			u.blink_remaining = info.blink_cooldown;
		}
		U().push_back(u);
		next_unit_id += 1;
	}

	void land_spells() {
		Array due, kept;
		for (int64_t i = 0; i < spell_casts.size(); i++) {
			Dictionary c = spell_casts[i];
			if (double(c[N->lands_at]) <= elapsed + EPS) due.push_back(c);
			else kept.push_back(c);
		}
		if (due.is_empty()) return;
		spell_casts = kept;
		casts_replaced = true;
		for (int64_t i = 0; i < due.size(); i++) land_spell(due[i]);
	}

	void land_spell(const Dictionary &cast) {
		int64_t side = int64_t(cast[N->side]);
		String kind = cast[N->kind];
		double x = double(cast[N->x]);
		Dictionary stats = structure_stats[kind];
		double radius = double(stats.get("radius", 0.0));
		double caster_x = x;
		Array targets;
		String effect = stats.get("effect", kind);
		if (effect == "strike") {
			int strongest = -1;
			for (int i = 0; i < int(U().size()); i++) {
				const Unit &e = U()[i];
				if (e.side != side && e.hp > 0.0 && std::fabs(e.x - x) <= radius) {
					if (strongest < 0 || e.hp > U()[strongest].hp) strongest = i;
				}
			}
			if (strongest >= 0) {
				x = U()[strongest].x;
				targets.push_back(U()[strongest].id);
				Target t;
				t.unit = strongest;
				damage_target(-1, side, kind, caster_x, 0, t, double(stats["damage"]), false);
			}
		} else if (effect == "blast") {
			for (int i = 0; i < int(U().size()); i++) {
				if (U()[i].side != side && U()[i].hp > 0.0 && std::fabs(U()[i].x - x) <= radius) {
					targets.push_back(U()[i].id);
					Target t;
					t.unit = i;
					damage_target(-1, side, kind, caster_x, 0, t, double(stats["damage"]), false);
				}
			}
		} else if (effect == "freeze") {
			for (Unit &e : U()) {
				if (e.side != side && e.hp > 0.0 && std::fabs(e.x - x) <= radius) {
					targets.push_back(e.id);
					e.has_frozen = true;
					e.frozen_remaining = double(stats["duration"]) * K(e.kind).control_weakness;
				}
			}
		} else if (effect == "bless") {
			for (Unit &a : U()) {
				if (a.side == side && a.hp > 0.0 && std::fabs(a.x - x) <= radius) {
					targets.push_back(a.id);
					a.has_blessed = true;
					a.blessed_remaining = double(stats["duration"]);
					a.hp = gd_minf(a.max_hp, a.hp + a.max_hp * double(stats.get("heal_fraction", 0.0)));
				}
			}
		} else if (effect == "resurrect") {
			Array side_fallen = fallen[side];
			int64_t count = gd_mini(int64_t(stats["revive_count"]), side_fallen.size());
			Array raised = side_fallen.slice(side_fallen.size() - count);
			fallen[side] = side_fallen.slice(0, side_fallen.size() - count);
			double fraction = double(stats["revive_fraction"]);
			for (int64_t index = 0; index < raised.size(); index++) {
				if (side_full(side)) break;
				Dictionary entry = raised[index];
				double spread = (double(index) - double(raised.size() - 1) * 0.5) * 14.0;
				create_unit(side, core_kind(String(entry[N->kind])), double(entry["hp_scale"]) * fraction, double(entry["damage_scale"]) * fraction, x + spread);
				Unit &raised_unit = U().back();
				raised_unit.has_revived = true;
				raised_unit.revived = true;
				revive_used[raised_unit.id] = true;
				targets.push_back(raised_unit.id);
			}
		}
		Dictionary e;
		e[N->type] = "SPELL_LAND";
		e[N->side] = side;
		e[N->kind] = kind;
		e[N->x] = x;
		e["radius"] = radius;
		e["targets"] = targets;
		event(e);
	}

	void remember_fallen(const Unit &u) {
		const KindInfo &info = K(u.kind);
		if (!info.known || info.summon || u.has_converted || (u.has_revived && u.revived.booleanize()) || info.field_limit > 0) return;
		double damage_scale = info.damage > 0.0 ? u.damage / info.damage : 1.0;
		Array side_fallen = fallen[u.side];
		Dictionary entry;
		entry[N->kind] = info.name;
		entry["hp_scale"] = u.max_hp / gd_maxf(0.01, info.hp);
		entry["damage_scale"] = damage_scale;
		side_fallen.push_back(entry);
		if (side_fallen.size() > MAX_FALLEN) side_fallen.pop_front();
	}

	void harvest_soul(int fallen_index) {
		const Unit fallen_unit = U()[fallen_index];
		for (Unit &lord : U()) {
			if (lord.side == fallen_unit.side || lord.hp <= 0.0 || !lord.has_souls) continue;
			const KindInfo &info = K(lord.kind);
			if (std::fabs(lord.x - fallen_unit.x) > info.soul_radius) continue;
			lord.souls = gd_mini(info.soul_max, lord.souls + 1);
			double healed = gd_minf(lord.max_hp - lord.hp, lord.max_hp * info.soul_heal_fraction);
			lord.hp = lord.hp + healed;
			Dictionary e;
			e[N->type] = "SOUL";
			e[N->source_id] = lord.id;
			e["unit_id"] = fallen_unit.id;
			e[N->x] = lord.x;
			e["from_x"] = fallen_unit.x;
			e[N->souls] = lord.souls;
			event(e);
			if (healed > 0.0) {
				Dictionary h;
				h[N->type] = "HEAL";
				h["target_id"] = lord.id;
				h["amount"] = healed;
				h[N->x] = lord.x;
				event(h);
			}
		}
	}

	void cast_skill(int caster, double x) {
		const Unit c = U()[caster];
		const KindInfo &info = K(c.kind);
		if (info.skill_on_self) x = c.x;
		double growth = c.damage / gd_maxf(0.01, info.damage);
		double radius = info.skill_radius;
		double knockback = info.skill_knockback * (c.side == 0 ? 1.0 : -1.0);
		Dictionary e;
		e[N->type] = "SKILL";
		e[N->source_id] = c.id;
		e[N->kind] = info.name;
		e[N->x] = x;
		e["radius"] = radius;
		event(e);
		for (int i = 0; i < int(U().size()); i++) {
			if (U()[i].side != c.side && U()[i].hp > 0.0 && std::fabs(U()[i].x - x) <= radius) {
				Target t;
				t.unit = i;
				damage_target(caster, 0, String(), 0.0, 0, t, info.skill_damage * growth, false);
				if (knockback != 0.0 && U()[i].hp > 0.0) U()[i].x = gd_clamp(U()[i].x + knockback, FIELD_LEFT, FIELD_RIGHT);
			}
		}
	}

	void apply_cheats() {
		for (int side = 0; side < 2; side++) {
			Dictionary on = cheats[side];
			if (on.is_empty()) continue;
			if (on.has("resources")) resources[side] = model->call("resource_capacity", side);
			if (on.has("cooldowns")) {
				Dictionary(spawn_cooldowns[side]).clear();
				Dictionary(spell_cooldowns[side]).clear();
				Dictionary(spell_uses[side]).clear();
			}
			if (on.has("castle")) base_hp[side] = base_max_hp[side];
			for (Unit &u : U()) {
				if (u.hp <= 0.0) continue;
				if (u.side == side) {
					if (on.has("immortal")) u.hp = u.max_hp;
					const char *stats[2] = {nullptr, nullptr};
					int n = 0;
					if (on.has("one_hit")) stats[n++] = "damage";
					if (on.has("haste")) stats[n++] = "speed";
					for (int k = 0; k < n; k++) {
						String stat = stats[k];
						Dictionary saved = cheat_saved.get(u.id, Dictionary());
						if (!saved.has(stat)) {
							saved[stat] = stat == "damage" ? u.damage : u.speed;
							cheat_saved[u.id] = saved;
							if (stat == "damage") u.damage = 100000.0;
							else u.speed = u.speed * 2.0;
						}
					}
				} else if (on.has("freeze")) {
					u.frozen_remaining = gd_maxf(u.has_frozen ? u.frozen_remaining : 0.0, 0.2);
					u.has_frozen = true;
				}
			}
		}
	}

	bool cheats_empty() { return Dictionary(cheats[0]).is_empty() && Dictionary(cheats[1]).is_empty(); }

	void run();
};

int Tick::core_kind(const String &name) {
	return core->kind_of_public(name);
}

void Tick::run() {
	if (!cheats_empty()) apply_cheats();
	{
		Array kept;
		for (int64_t i = 0; i < curses.size(); i++) {
			Dictionary c = curses[i];
			if (double(c[N->expires_at]) > elapsed) kept.push_back(c);
		}
		curses = kept;
		curses_replaced = true;
	}
	for (int64_t i = 0; i < structures.size(); i++) {
		Dictionary s = structures[i];
		Variant id = s[N->id];
		if (structure_expirations.has(id) && elapsed >= double(structure_expirations[id])) {
			s[N->hp] = 0.0;
			structure_expirations.erase(id);
		}
	}
	Dictionary generator = structure_stats["generator"];
	for (int side = 0; side < 2; side++) {
		double income = double(model->call("resource_income", side));
		for (int64_t i = 0; i < structures.size(); i++) {
			Dictionary s = structures[i];
			if (int64_t(s[N->side]) == side && String(s[N->kind]) == "generator" && double(s[N->hp]) > 0.0) income += double(generator["income"]);
		}
		double capacity = double(model->call("resource_capacity", side));
		resources[side] = gd_min(capacity, double(resources[side]) + income * delta);
		Dictionary spawns = spawn_cooldowns[side];
		Array spawn_keys = spawns.keys();
		for (int64_t k = 0; k < spawn_keys.size(); k++) spawns[spawn_keys[k]] = gd_max(0.0, double(spawns[spawn_keys[k]]) - delta);
		Dictionary spells = spell_cooldowns[side];
		Array spell_keys = spells.keys();
		for (int64_t k = 0; k < spell_keys.size(); k++) {
			double left = gd_maxf(0.0, double(spells[spell_keys[k]]) - delta);
			spells[spell_keys[k]] = left;
			if (left <= 0.0) spells.erase(spell_keys[k]);
		}
	}
	for (Unit &u : U()) {
		if (u.has_frozen) {
			u.frozen_remaining = u.frozen_remaining - delta;
			if (u.frozen_remaining <= EPS) u.has_frozen = false;
		}
		if (u.has_blessed) {
			u.blessed_remaining = u.blessed_remaining - delta;
			if (u.blessed_remaining <= EPS) u.has_blessed = false;
		}
		if (u.has_stall) {
			u.stall_remaining = u.stall_remaining - delta;
			if (u.stall_remaining <= EPS) u.has_stall = false;
		}
		if (u.has_plunder_cd) {
			u.plunder_remaining = u.plunder_remaining - delta;
			if (u.plunder_remaining <= EPS) u.has_plunder_cd = false;
		}
		if (u.has_convert_cd) {
			u.convert_remaining = u.convert_remaining - delta;
			if (u.convert_remaining <= EPS) u.has_convert_cd = false;
		}
	}
	// _tick_revives
	for (Unit &u : U()) {
		if (!u.has_revive) continue;
		u.revive_remaining = gd_maxf(0.0, u.revive_remaining - delta);
		if (u.revive_remaining > EPS) continue;
		u.has_revive = false;
		u.hp = u.max_hp * K(revive_kind(u) >= 0 ? revive_kind(u) : u.kind).revive_hp_fraction;
		u.cooldown = gd_max(MIN_ATTACK_INTERVAL, u.interval);
		Dictionary e;
		e[N->type] = "REVIVE";
		e["unit_id"] = u.id;
		e[N->x] = u.x;
		event(e);
	}
	land_spells();
	index_curses();
	index_lanes();
	index_fronts();

	std::vector<PendingAttack> pending_attacks;
	std::vector<PendingHit> pending_base_hits;
	std::vector<std::pair<int, double>> pending_moves;
	// _tick_turrets
	{
		Dictionary turret = structure_stats["turret"];
		double turret_interval = double(turret["interval"]);
		double turret_range = double(turret["range"]);
		for (int64_t i = 0; i < structures.size(); i++) {
			Dictionary s = structures[i];
			if (String(s[N->kind]) != "turret" || double(s[N->hp]) <= 0.0) continue;
			int64_t id = int64_t(s[N->id]);
			int64_t side = int64_t(s[N->side]);
			double sx = double(s[N->x]);
			double cooldown = gd_max(0.0, double(structure_cooldowns.get(id, turret_interval)) - delta * curse_speed_scale(side, sx));
			structure_cooldowns[id] = cooldown;
			if (cooldown > 0.0) continue;
			Target target;
			double nearest = INF;
			for (int j = 0; j < int(U().size()); j++) {
				const Unit &enemy = U()[j];
				if (enemy.side == side || enemy.hp <= 0.0 || !targetable(enemy)) continue;
				double enemy_distance = std::fabs(enemy.x - sx);
				if (enemy_distance > turret_range) continue;
				Dictionary wall = blocking_wall(side, sx, enemy.x);
				double candidate_distance = wall.is_empty() ? std::fabs(enemy.x - sx) : std::fabs(double(wall[N->x]) - sx);
				if (candidate_distance < nearest) {
					target = Target();
					if (wall.is_empty()) target.unit = j;
					else target.structure = wall;
					nearest = candidate_distance;
				}
			}
			if (target.valid()) {
				PendingAttack attack;
				attack.attacker = s;
				attack.target = target;
				attack.damage = double(turret["damage"]);
				pending_attacks.push_back(attack);
				structure_cooldowns[id] = turret_interval;
			}
		}
	}
	// _tick_castles
	for (int side = 0; side < 2; side++) {
		if (bool(invulnerable_bases[side])) continue;
		castle_cooldowns[side] = gd_maxf(0.0, double(castle_cooldowns[side]) - delta);
		if (double(castle_cooldowns[side]) > 0.0) continue;
		double castle_x = side == 0 ? FIELD_LEFT : FIELD_RIGHT;
		int target = -1;
		double nearest = INF;
		for (int j = 0; j < int(U().size()); j++) {
			const Unit &enemy = U()[j];
			if (enemy.side == side || enemy.hp <= 0.0 || !targetable(enemy)) continue;
			double distance = std::fabs(enemy.x - castle_x);
			if (distance <= CASTLE_RANGE && distance < nearest) {
				target = j;
				nearest = distance;
			}
		}
		if (target >= 0) {
			PendingAttack attack;
			Dictionary castle;
			castle[N->id] = int64_t(-1 - side);
			castle[N->side] = int64_t(side);
			castle[N->kind] = "castle";
			castle[N->x] = castle_x;
			attack.attacker = castle;
			attack.target.unit = target;
			double lost = 1.0 - gd_clamp(double(base_hp[side]) / gd_maxf(1.0, double(base_max_hp[side])), 0.0, 1.0);
			attack.damage = CASTLE_DAMAGE * (1.0 + (CASTLE_DESPERATION - 1.0) * lost);
			pending_attacks.push_back(attack);
			castle_cooldowns[side] = CASTLE_INTERVAL;
		}
	}
	std::vector<int64_t> pending_summons; // owner ids
	std::unordered_map<int64_t, int64_t> live_skeletons;
	for (const Unit &u : U()) {
		if (u.kind == skeleton && u.hp > 0.0 && summon_owners.has(u.id)) {
			int64_t owner = int64_t(summon_owners[u.id]);
			live_skeletons[owner] += 1;
		}
	}
	for (int i = 0; i < int(U().size()); i++) {
		Unit &u = U()[i];
		if (u.has_frozen) continue;
		u.cooldown = gd_max(0.0, u.cooldown - delta * support_attack_speed(u));
		if (u.hp <= 0.0) continue;
		if (u.kind == necromancer) {
			double timer = double(summon_timers.get(u.id, SUMMON_INTERVAL)) - delta;
			summon_timers[u.id] = timer;
			if (timer <= EPS) {
				auto found = live_skeletons.find(u.id);
				int64_t live = found == live_skeletons.end() ? 0 : found->second;
				if (live < MAX_SKELETONS_PER_NECROMANCER + int64_t(modifier(u.side, "skeleton_cap", int64_t(0)))) pending_summons.push_back(u.id);
				summon_timers[u.id] = SUMMON_INTERVAL;
				timer = SUMMON_INTERVAL;
			}
			u.has_summon = true;
			u.summon_remaining = gd_maxf(0.0, timer);
		}
		if (u.has_skill) u.skill_remaining = gd_maxf(0.0, u.skill_remaining - delta);
		if (u.has_blink) u.blink_remaining = gd_maxf(0.0, u.blink_remaining - delta);
		if (u.kind == healer) {
			tick_support(i);
			continue;
		}
	}
	if (supports_moved) index_lanes();
	supports_moved = false;
	std::vector<std::pair<int, double>> pending_skills;
	std::vector<std::pair<int, double>> pending_blinks;
	std::vector<int> pending_blasts;
	for (int i = 0; i < int(U().size()); i++) {
		Unit &u = U()[i];
		if (u.hp <= 0.0 || u.kind == healer || u.has_frozen || u.has_stall) continue;
		if (u.has_blink && u.blink_remaining <= 0.0 && !sheltered(u)) {
			int mark = blink_mark(u);
			if (mark >= 0) {
				pending_blinks.push_back({i, U()[mark].x});
				u.blink_remaining = K(u.kind).blink_cooldown;
				continue;
			}
		}
		bool blaster = K(u.kind).has_blast;
		Target target;
		if (!sheltered(u)) target = find_target(i);
		if (target.valid()) {
			if (blaster) {
				pending_blasts.push_back(i);
				continue;
			}
			double tx = target.unit >= 0 ? U()[target.unit].x : double(target.structure[N->x]);
			if (u.has_skill && u.skill_remaining <= 0.0) {
				pending_skills.push_back({i, tx});
				const KindInfo &info = K(u.kind);
				u.skill_remaining = info.skill_cooldown * double(modifier(u.side, "skill_cooldown:" + info.name, 1.0));
			}
			if (u.cooldown <= 0.0) {
				PendingAttack attack;
				attack.attacker_unit = i;
				attack.target = target;
				attack.damage = strike_damage(u);
				pending_attacks.push_back(attack);
				u.cooldown = u.interval;
			}
			continue;
		}
		double enemy_base_x = u.side == 0 ? FIELD_RIGHT : FIELD_LEFT;
		Dictionary wall = blocking_wall(u.side, u.x, enemy_base_x);
		if (!wall.is_empty() && std::fabs(double(wall[N->x]) - u.x) <= u.range + 12.0) {
			if (blaster) {
				pending_blasts.push_back(i);
			} else if (u.cooldown <= 0.0) {
				PendingAttack attack;
				attack.attacker_unit = i;
				attack.target.structure = wall;
				attack.damage = strike_damage(u);
				pending_attacks.push_back(attack);
				u.cooldown = u.interval;
			}
			continue;
		}
		if (std::fabs(u.x - enemy_base_x) <= u.range) {
			if (blaster) {
				pending_blasts.push_back(i);
			} else if (u.cooldown <= 0.0) {
				PendingHit hit;
				hit.attacker = i;
				hit.damage = strike_damage(u);
				hit.x = enemy_base_x;
				pending_base_hits.push_back(hit);
				u.cooldown = u.interval;
			}
			continue;
		}
		double direction = u.side == 0 ? 1.0 : -1.0;
		double stride = gd_clamp(u.x + direction * u.speed * swamp_scale(u) * delta, FIELD_LEFT, FIELD_RIGHT);
		stride = held_stride(u, stride, direction);
		pending_moves.push_back({i, stride});
	}

	for (auto &skill : pending_skills) cast_skill(skill.first, skill.second);
	for (PendingAttack &attack : pending_attacks) {
		if (attack.attacker_unit >= 0) {
			damage_target(attack.attacker_unit, 0, String(), 0.0, 0, attack.target, attack.damage, true);
		} else {
			bool target_is_unit = attack.target.unit >= 0;
			double target_hp = target_is_unit ? U()[attack.target.unit].hp : double(attack.target.structure[N->hp]);
			double before = gd_maxf(0.0, target_hp);
			double effective = gd_minf(before, attack.damage);
			record_damage(int64_t(attack.attacker[N->side]), String(attack.attacker[N->kind]), effective, target_is_unit && before > 0.0 && effective >= before);
			double new_hp = gd_maxf(0.0, before - attack.damage);
			Variant target_id;
			Variant target_x;
			if (target_is_unit) {
				U()[attack.target.unit].hp = new_hp;
				target_id = U()[attack.target.unit].id;
				target_x = U()[attack.target.unit].x;
			} else {
				attack.target.structure[N->hp] = new_hp;
				target_id = attack.target.structure[N->id];
				target_x = attack.target.structure[N->x];
			}
			Dictionary e;
			e[N->type] = "ATTACK";
			e["attacker_id"] = attack.attacker[N->id];
			e["target_id"] = target_id;
			e["attack_kind"] = String(attack.attacker[N->kind]);
			e[N->x] = attack.attacker[N->x];
			e["target_x"] = target_x;
			event(e);
			Dictionary d;
			d[N->type] = "DAMAGE";
			d["target_id"] = target_id;
			d["amount"] = attack.damage;
			d[N->x] = target_x;
			event(d);
		}
	}
	for (int bomber : pending_blasts) {
		if (U()[bomber].hp > 0.0) blast(bomber);
	}
	for (PendingHit &hit : pending_base_hits) {
		Unit &attacker = U()[hit.attacker];
		int64_t enemy_side = 1 - attacker.side;
		record_damage(attacker.side, K(attacker.kind).name, gd_minf(hit.damage, double(base_hp[enemy_side])), false);
		if (!bool(invulnerable_bases[enemy_side])) {
			base_hp[enemy_side] = gd_maxf(0.0, double(base_hp[enemy_side]) - hit.damage);
			Dictionary e;
			e[N->type] = "BASE_HIT";
			e[N->side] = enemy_side;
			e["amount"] = hit.damage;
			e[N->x] = hit.x;
			event(e);
		}
		if (attacker.kind == warlock) install_curse(U()[hit.attacker], hit.x);
	}
	for (auto &move : pending_moves) U()[move.first].x = move.second;
	for (auto &jump : pending_blinks) blink(jump.first, jump.second);
	if (double(base_hp[0]) <= 0.0 || double(base_hp[1]) <= 0.0) {
		winner = (double(base_hp[0]) <= 0.0 && double(base_hp[1]) <= 0.0) ? 2 : (double(base_hp[0]) <= 0.0 ? 1 : 0);
	}

	// _down_revivable_units
	for (Unit &u : U()) {
		if (u.hp > 0.0 || u.has_revive || revive_used.has(u.id) || revive_kind(u) < 0) continue;
		revive_used[u.id] = true;
		u.has_revive = true;
		u.revive_remaining = K(revive_kind(u)).revive_delay;
		u.support_stacks = 0;
		u.has_support_stacks = true;
		Dictionary e;
		e[N->type] = "DOWNED";
		e["unit_id"] = u.id;
		e[N->x] = u.x;
		event(e);
	}
	// _emit_death_events; a shaman near a fallen enemy raises it on its own side (after the list is cleaned).
	struct Conversion { int64_t shaman_id; int kind; double x; };
	std::vector<Conversion> pending_conversions;
	for (int i = 0; i < int(U().size()); i++) {
		const Unit &u = U()[i];
		if (u.hp <= 0.0 && !u.has_revive && !announced_deaths.has(u.id)) {
			announced_deaths[u.id] = true;
			Dictionary e;
			e[N->type] = "DEATH";
			e["unit_id"] = u.id;
			e[N->x] = u.x;
			event(e);
			harvest_soul(i);
			remember_fallen(U()[i]);
			const KindInfo &victim = K(U()[i].kind);
			if (!victim.known || victim.summon || victim.field_limit > 0 || U()[i].has_converted) continue;
			for (Unit &shaman : U()) {
				const KindInfo &info = K(shaman.kind);
				if (!info.has_convert || shaman.side == U()[i].side || shaman.hp <= 0.0 || shaman.has_convert_cd) continue;
				if (victim.cost > info.convert_max_cost || std::fabs(shaman.x - U()[i].x) > info.convert_radius) continue;
				int64_t held = 0;
				for (const Unit &other : U()) {
					if (other.has_converted && other.hp > 0.0 && summon_owners.has(other.id) && int64_t(summon_owners[other.id]) == shaman.id) held++;
				}
				for (const Conversion &c : pending_conversions) {
					if (c.shaman_id == shaman.id) held++;
				}
				if (held >= info.convert_limit) continue;
				shaman.has_convert_cd = true;
				shaman.convert_remaining = info.convert_cooldown;
				pending_conversions.push_back({shaman.id, U()[i].kind, U()[i].x});
				break;
			}
		}
	}
	for (int64_t i = 0; i < structures.size(); i++) {
		Dictionary s = structures[i];
		if (double(s[N->hp]) <= 0.0 && !announced_structure_deaths.has(s[N->id])) {
			announced_structure_deaths[s[N->id]] = true;
			Dictionary e;
			e[N->type] = "STRUCTURE_DESTROYED";
			e["structure_id"] = s[N->id];
			e[N->kind] = s[N->kind];
			e[N->x] = s[N->x];
			event(e);
		}
	}
	{
		std::vector<Unit> kept;
		kept.reserve(U().size());
		for (Unit &u : U()) {
			if (u.hp > 0.0 || u.has_revive) kept.push_back(u);
			else if (u.has_handle) core->write_back(u); // a reference GDScript kept sees the unit as it fell
		}
		U().swap(kept);
	}
	{
		Array kept;
		for (int64_t i = 0; i < structures.size(); i++) {
			Dictionary s = structures[i];
			if (double(s[N->hp]) > 0.0) kept.push_back(s);
		}
		structures = kept;
		structures_replaced = true;
	}
	for (const Conversion &c : pending_conversions) {
		int shaman = -1;
		for (int i = 0; i < int(U().size()); i++) {
			if (U()[i].id == c.shaman_id) {
				shaman = i;
				break;
			}
		}
		if (winner != -1 || shaman < 0 || side_full(U()[shaman].side)) continue;
		int64_t side = U()[shaman].side;
		create_unit(side, c.kind, K(U()[shaman].kind).convert_hp, 1.0, c.x);
		Unit &raised = U().back();
		raised.has_converted = true;
		summon_owners[raised.id] = c.shaman_id;
		Dictionary e;
		e[N->type] = "CONVERT";
		e[N->source_id] = c.shaman_id;
		e["unit_id"] = raised.id;
		e[N->kind] = K(c.kind).name;
		e[N->x] = raised.x;
		event(e);
	}
	for (int64_t owner_id : pending_summons) {
		int owner = -1;
		for (int i = 0; i < int(U().size()); i++) {
			if (U()[i].id == owner_id) {
				owner = i;
				break;
			}
		}
		// A summoner that fell this tick is gone from the list (and would have hp <= 0 anyway).
		if (winner != -1 || owner < 0 || U()[owner].hp <= 0.0 || side_full(U()[owner].side)) continue;
		const KindInfo &necro = K(necromancer);
		double hp_scale = U()[owner].max_hp / necro.hp;
		double damage_scale = U()[owner].damage / necro.damage;
		int64_t side = U()[owner].side;
		double owner_x = U()[owner].x;
		Dictionary report = battle_report[side];
		Dictionary rows = report["units"];
		Dictionary row = rows["necromancer"];
		row["summoned"] = int64_t(row["summoned"]) + 1;
		create_unit(side, skeleton, hp_scale, damage_scale, owner_x + (side == 0 ? 22.0 : -22.0));
		const Unit &summoned = U().back();
		summon_owners[summoned.id] = owner_id;
		Dictionary e;
		e[N->type] = "SUMMON";
		e[N->source_id] = owner_id;
		e["unit_id"] = summoned.id;
		e[N->x] = summoned.x;
		event(e);
	}
	{
		Dictionary live_ids;
		for (int i = 0; i < int(U().size()); i++) live_ids[U()[i].id] = i;
		Dictionary *tables[4] = {&summon_timers, &summon_owners, &revive_used, &knocked_back};
		for (Dictionary *table : tables) {
			Array keys = table->keys();
			for (int64_t k = 0; k < keys.size(); k++) {
				if (!live_ids.has(keys[k])) {
					table->erase(keys[k]);
				} else if (table == &summon_owners && !live_ids.has((*table)[keys[k]])) {
					Unit &escort = U()[int(int64_t(live_ids[keys[k]]))];
					if (K(escort.kind).has_leaderless) escort.has_leaderless = true;
				}
			}
		}
		Array keys = structure_expirations.keys();
		for (int64_t k = 0; k < keys.size(); k++) {
			bool present = false;
			for (int64_t i = 0; i < structures.size(); i++) {
				Dictionary s = structures[i];
				if (Variant(s[N->id]) == keys[k]) {
					present = true;
					break;
				}
			}
			if (!present) structure_expirations.erase(keys[k]);
		}
	}
}

} // namespace

int BattleCore::kind_of_public(const String &name) { return kind_of(name); }

void BattleCore::write_back(Unit &u) { write_into(u.handle, u); }

namespace {
void load_tick(Tick &t, BattleCore *core, std::vector<KindInfo> &kinds, std::vector<Unit> &units, const Dictionary &structure_stats, Object *model, double delta) {
	t.core = core;
	t.kinds = &kinds;
	t.units = &units;
	t.model = model;
	t.structure_stats = structure_stats;
	t.delta = delta;
	t.winner = -1;
	t.next_unit_id = int64_t(model->get("next_unit_id"));
#define LOAD(name) t.name = model->get(#name)
	LOAD(cheats); LOAD(curses); LOAD(structures); LOAD(resources); LOAD(spawn_cooldowns); LOAD(spell_cooldowns);
	LOAD(spell_uses); LOAD(base_hp); LOAD(base_max_hp); LOAD(invulnerable_bases); LOAD(castle_cooldowns); LOAD(modifiers);
	LOAD(shelter); LOAD(advance_limit); LOAD(formation); LOAD(combat_events); LOAD(battle_report); LOAD(fallen);
	LOAD(spell_casts); LOAD(structure_expirations); LOAD(structure_cooldowns); LOAD(summon_timers); LOAD(summon_owners);
	LOAD(revive_used); LOAD(knocked_back); LOAD(first_struck); LOAD(cheat_saved); LOAD(announced_deaths);
	LOAD(announced_structure_deaths);
#undef LOAD
	t.healer = core->kind_of_public("healer");
	t.necromancer = core->kind_of_public("necromancer");
	t.skeleton = core->kind_of_public("skeleton");
	t.berserker = core->kind_of_public("berserker");
	t.warlock = core->kind_of_public("warlock");
	t.zombie = core->kind_of_public("zombie");
	t.paladin = core->kind_of_public("paladin");
}

void store_tick(Tick &t, Object *model) {
	if (t.curses_replaced) model->set("curses", t.curses);
	if (t.structures_replaced) model->set("structures", t.structures);
	if (t.casts_replaced) model->set("spell_casts", t.spell_casts);
	model->set("next_unit_id", t.next_unit_id);
	if (t.winner != -1) model->set("winner", t.winner);
}

int index_of_id(std::vector<Unit> &units, int64_t id) {
	for (int i = 0; i < int(units.size()); i++) {
		if (units[i].id == id) return i;
	}
	return -1;
}
} // namespace

void BattleCore::tick(Object *model, double delta) {
	if (model == nullptr) return;
	if (int64_t(model->get("winner")) != -1) return;
	sync_in();
	exposed = Array(); // the tick makes a new units array, as `units = units.filter(...)` does in GDScript
	has_exposed = false;
	Tick t;
	load_tick(t, this, kinds, units, structure_stats, model, delta);
	t.elapsed = double(model->get("elapsed")) + delta;
	model->set("elapsed", t.elapsed);
	t.run();
	store_tick(t, model);
	sync_out();
}

Variant BattleCore::probe(Object *model, const String &what, const Array &args) {
	if (model == nullptr) return Variant();
	sync_in();
	Tick t;
	load_tick(t, this, kinds, units, structure_stats, model, 0.0);
	t.elapsed = double(model->get("elapsed"));
	t.index_curses();
	t.index_lanes();
	t.index_fronts();
	Variant result;
	int unit = args.size() > 0 && args[0].get_type() == Variant::INT ? index_of_id(units, int64_t(args[0])) : -1;
	if (what == "find_target" && unit >= 0) {
		Target target = t.find_target(unit);
		if (target.unit >= 0) result = units[target.unit].id;
		else if (!target.structure.is_empty()) result = target.structure;
	} else if (what == "damage" && unit >= 0 && args.size() >= 4) {
		Target target;
		if (args[1].get_type() == Variant::DICTIONARY) target.structure = args[1];
		else target.unit = index_of_id(units, int64_t(args[1]));
		if (target.valid()) t.damage_target(unit, 0, String(), 0.0, 0, target, double(args[2]), bool(args[3]));
	} else if (what == "swamp_scale" && unit >= 0) {
		result = t.swamp_scale(units[unit]);
	} else if (what == "strike" && unit >= 0) {
		result = t.strike_damage(units[unit]);
	} else if (what == "curse" && unit >= 0 && args.size() >= 2) {
		t.install_curse(units[unit], double(args[1]));
	} else if (what == "record" && args.size() >= 4) {
		t.record_damage(int64_t(args[0]), String(args[1]), double(args[2]), bool(args[3]));
	} else if (what == "support" && unit >= 0) {
		t.tick_support(unit);
	}
	store_tick(t, model);
	sync_out();
	return result;
}
