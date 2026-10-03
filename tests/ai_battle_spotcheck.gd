extends SceneTree

# A bounded rules-engine spot check, not a human difficulty or win-rate study.
func _initialize() -> void:
	for stage in [1,3,4,7,8]:
		var model := BattleModel.new()
		model.configure_campaign_growth(0,stage-1)
		model.configure_deck(1,ServerAI.stage_unit_deck(stage),ServerAI.stage_structure_deck(stage))
		model.configure_base_health(1,300.0+stage*20.0)
		model.resources[1]=35.0+stage*10.0
		var player := ServerAI.new(0,1)
		var opponent := ServerAI.new(1,stage)
		var counts := {"attacks":0,"curses":0,"summons":0,"structures":0,"generators":0}
		for step in 180:
			player.update(model,0.25)
			opponent.update(model,0.25)
			model.tick(0.25)
			for event in model.drain_combat_events():
				if event.type=="ATTACK": counts.attacks+=1
				elif event.type=="CURSE": counts.curses+=1
				elif event.type=="SUMMON": counts.summons+=1
				elif event.type=="STRUCTURE_PLACED":
					counts.structures+=1
					if event.kind=="generator": counts.generators+=1
			for side in 2:
				if not is_finite(float(model.resources[side])) or model.resources[side]<0.0 or model.base_hp[side]<0.0 or model.base_hp[side]>model.base_max_hp[side]:
					printerr("Invalid battle state at stage ",stage)
					quit(1);return
			if model.winner!=-1:break
		if (stage>=3 and counts.generators==0) or (stage==3 and counts.curses==0) or (stage>=7 and counts.summons==0):
			printerr("AI economy or combined-trait purchases were starved at stage ",stage)
			quit(1);return
		print("BOUNDED_AI_SPOTCHECK ",JSON.stringify({"stage":stage,"elapsed":model.elapsed,"winner":model.winner,"bases":model.base_hp,"live_units":model.units.size(),"events":counts}))
	print("PASS: five bounded 45-second automated battle scenarios")
	quit(0)
