extends RefCounted
## Card statistics from ranked games, one file per season and ruleset (ranked_cards_<season>_<ruleset>.json).
## For every card: how many ranked decks brought it (picks), how often the opponent banned it, and the
## wins and draws of the decks that brought it. Players see the summary in the ranking dialog; the files
## feed balance work (tools/ranked_report.py).

const ServerStats = preload("res://scripts/ServerStats.gd")

const FIELDS := ["picks", "bans", "wins", "draws"]

var directory := ""
var season := ""
var ruleset := ""
var path := ""
var data: Dictionary = {"matches": 0, "cards": {}}
var dirty := false

func configure(state_directory: String, season_id: String, rule: String = "") -> void:
	directory = state_directory
	season = season_id
	ruleset = rule if not rule.is_empty() else ServerStats.ruleset_id()
	path = "" if directory.is_empty() else directory.path_join("ranked_cards_%s_%s.json" % [season, ruleset])
	data = _sanitize(ServerStats.read_json(path))
	dirty = false

static func _sanitize(raw: Variant) -> Dictionary:
	var clean := {"matches": 0, "cards": {}}
	if not raw is Dictionary:
		return clean
	clean.matches = int(raw.matches) if ServerStats.valid_count(raw.get("matches")) else 0
	if raw.get("cards") is Dictionary:
		for kind in raw.cards:
			var entry = raw.cards[kind]
			if valid_kind(kind) and entry is Dictionary and FIELDS.all(func(field): return ServerStats.valid_count(entry.get(field))):
				clean.cards[String(kind)] = {"picks": int(entry.picks), "bans": int(entry.bans), "wins": int(entry.wins), "draws": int(entry.draws)}
	return clean

static func valid_kind(kind: Variant) -> bool:
	return kind is String and (BattleModel.UNIT_STATS.has(kind) or BattleModel.STRUCTURE_STATS.has(kind))

## Counts one finished ranked battle. `winner` is the winning side, or 2 for a draw. A new season starts a new file.
func record(model: BattleModel, winner: int, season_id: String) -> void:
	if season_id != season:
		flush()
		configure(directory, season_id, ruleset)
	data.matches = int(data.matches) + 1
	for side in 2:
		for kind in Array(model.unit_decks[side]) + Array(model.structure_decks[side]):
			var entry := _entry(String(kind))
			entry.picks += 1
			if winner == side: entry.wins += 1
			elif winner == 2: entry.draws += 1
		for kind in model.banned[side]:
			_entry(String(kind)).bans += 1
	dirty = true

func _entry(kind: String) -> Dictionary:
	if not data.cards.has(kind):
		data.cards[kind] = {"picks": 0, "bans": 0, "wins": 0, "draws": 0}
	return data.cards[kind]

## Rows for the ranking dialog: every card seen this season, most picked first.
func summary() -> Array:
	var rows: Array = []
	for kind in data.cards:
		var entry: Dictionary = data.cards[kind]
		rows.append({"kind": String(kind), "picks": int(entry.picks), "bans": int(entry.bans), "wins": int(entry.wins), "draws": int(entry.draws)})
	rows.sort_custom(func(a, b): return int(a.picks) > int(b.picks) or (int(a.picks) == int(b.picks) and String(a.kind) < String(b.kind)))
	return rows

func flush() -> bool:
	if path.is_empty() or not dirty:
		return true
	if ServerStats.write_json(path, data):
		dirty = false
	return not dirty
