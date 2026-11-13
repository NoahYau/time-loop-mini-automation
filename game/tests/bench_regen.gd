extends SceneTree
const K = preload("res://sim/constants.gd")
const LoopManager = preload("res://sim/loop_manager.gd")

func _line_cells() -> Array:
	return [
		[3, K.T_MINER], [4, K.T_BELT], [5, K.T_FURNACE], [6, K.T_BELT],
		[7, K.T_GEAR], [8, K.T_BELT], [9, K.T_ASSEMBLER], [10, K.T_BELT], [11, K.T_SINK],
	]

func _initialize() -> void:
	var lm = LoopManager.new()
	lm.start_level()
	var next_lane := 0
	for loop in range(4):
		lm.begin_loop(loop)
		var queue: Array = []
		for k in range(2):
			if next_lane + k < K.ORE_LANES.size():
				var y: int = int(K.ORE_LANES[next_lane + k])
				for it in _line_cells():
					queue.append([Vector2i(it[0], y), it[1]])
		var qi := 0
		for t in range(K.LOOP_TICKS):
			if t % K.BUILD_TICKS == 0 and qi < queue.size():
				if lm.can_build(queue[qi][0], queue[qi][1]):
					lm.submit_build(queue[qi][0], queue[qi][1], K.D_E)
					qi += 1
			lm.step()
		var by_origin := {}
		for idx in lm.world.buildings:
			var o: int = lm.world.buildings[idx].origin
			by_origin[o] = by_origin.get(o, 0) + 1
		print("loop %d: 提交/排隊 %d/%d  buildings=%d by_origin=%s delivered=%d ap_left=%d" % [
			loop, qi, queue.size(), lm.world.buildings.size(), str(by_origin), lm.world.delivered, lm.ap_left()])
		next_lane += 2
		lm.seal_loop()
	quit(0)