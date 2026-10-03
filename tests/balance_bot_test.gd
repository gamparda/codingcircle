extends SceneTree

const Bot = preload("res://tools/BalanceBot.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	var model := BattleModel.new()
	model.configure_deck(0,["shield","archer","necromancer"],BattleModel.DEFAULT_STRUCTURE_DECK)
	var bot := Bot.new(0,"cycle",123,model.unit_decks[0])
	bot.order=["necromancer","shield","archer"]
	bot.timer=0.0
	bot.update(model,0.1)
	check(model.units.is_empty() and model.resources[0]==70.0,"cycle saves for its selected expensive card without cheap fallback spam")
	model.resources[0]=110.0;bot.timer=0.0
	bot.update(model,0.1)
	check(model.units.size()==1 and model.units[0].kind=="necromancer" and bot.cursor==1,"saved card is bought and rotation advances once")
	check(model.units[0].max_hp==50.0 and model.units[0].damage==2.0,"benchmark player receives no AI stat bonus")
	var mirrored := BattleModel.new()
	mirrored.configure_deck(1,model.unit_decks[0],BattleModel.DEFAULT_STRUCTURE_DECK)
	var left := Bot.new(0,"weighted",567,model.unit_decks[0])
	var right := Bot.new(1,"weighted",567,model.unit_decks[0])
	check(left.order==right.order and left.weights==right.weights and left.timer==right.timer,"side swaps retain exact seeded preference and timing")
	print("%s: benchmark purchase-policy checks" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
