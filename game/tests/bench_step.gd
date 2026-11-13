extends SceneTree
const K = preload("res://sim/constants.gd")
const LoopManager = preload("res://sim/loop_manager.gd")

func _line(lm, y: int, compact: bool) -> void:
	if compact:
		# 5 件：礦機 -> 爐 -> 齒輪機 -> 組裝台 -> 出口（機器直接相鄰，唔用帶）
		var q := [[5, K.T_MINER], [6, K.T_FURNACE], [7, K.T_GEAR], [8, K.T_ASSEMBLER], [9, K.T_SINK]]
		for it in q:
			lm.submit_build(Vector2i(it[0], y), it[1], K.D_E)
	else:
		var q2 := [[5, K.T_MINER], [6, K.T_BELT], [7, K.T_BELT], [8, K.T_FURNACE],
			[9, K.T_BELT], [10, K.T_GEAR], [11, K.T_BELT], [12, K.T_ASSEMBLER],
			[13, K.T_BELT], [14, K.T_SINK]]
		for it in q2:
			lm.submit_build(Vector2i(it[0], y), it[1], K.D_E)

func _measure(compact: bool) -> Dictionary:
	var lm = LoopManager.new()
	lm.start_level()
	_line(lm, 5, compact)
	for i in range(K.LOOP_TICKS):
		lm.step()
	return {"delivered": lm.world.delivered, "parts": lm.world.parts_made, "ore": lm.world.ore_mined}

func _initialize() -> void:
	var a := _measure(true)
	print("COMPACT_5  delivered=%d parts=%d ore=%d" % [a["delivered"], a["parts"], a["ore"]])
	var b := _measure(false)
	print("BELT_10    delivered=%d parts=%d ore=%d" % [b["delivered"], b["parts"], b["ore"]])

	# 4 條 compact 線（20 件建築）實際交到幾多
	var lm = LoopManager.new()
	lm.start_level()
	for i in range(4):
		_line(lm, 4 + i * 3, true)
	for i in range(K.LOOP_TICKS):
		lm.step()
	print("FOUR_LINES delivered=%d parts=%d" % [lm.world.delivered, lm.world.parts_made])
	quit(0)
