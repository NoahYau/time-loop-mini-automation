extends SceneTree
## S1 + S2 驗收。
##   T1 live vs 重播（逐 tick 指紋）
##   T2 幽靈 + 玩家並存後整段重播
##   T3 AP 上限（連環點擊唔可以超支）
##   T4 拆幽靈 2 AP / 拆自己 1 AP
##   T5 8 loop 規模效能
##   T6 幽靈上限（寬鬆 B）+ 淘汰最舊
##   T7 預演可信：preview_at(t) 同當時 live 逐 tick 指紋一致（含前後拖）
##   T8 預演唔會污染真實世界
## 執行：godot --headless --path . --script res://tests/test_determinism.gd

const K = preload("res://sim/constants.gd")
const LoopManager = preload("res://sim/loop_manager.gd")

var failures: int = 0

var SCRIPT_A: Array = [
	{"t": 0, "k": K.C_BUILD, "x": 3, "y": 2, "type": K.T_MINER, "dir": K.D_E},
	{"t": 2, "k": K.C_BUILD, "x": 4, "y": 2, "type": K.T_BELT, "dir": K.D_E},
	{"t": 4, "k": K.C_BUILD, "x": 5, "y": 2, "type": K.T_BELT, "dir": K.D_E},
	{"t": 6, "k": K.C_BUILD, "x": 6, "y": 2, "type": K.T_FURNACE, "dir": K.D_E},
	{"t": 8, "k": K.C_BUILD, "x": 7, "y": 2, "type": K.T_BELT, "dir": K.D_E},
	{"t": 10, "k": K.C_BUILD, "x": 8, "y": 2, "type": K.T_GEAR, "dir": K.D_E},
	{"t": 12, "k": K.C_BUILD, "x": 9, "y": 2, "type": K.T_BELT, "dir": K.D_E},
	{"t": 14, "k": K.C_BUILD, "x": 10, "y": 2, "type": K.T_ASSEMBLER, "dir": K.D_E},
	{"t": 16, "k": K.C_BUILD, "x": 11, "y": 2, "type": K.T_BELT, "dir": K.D_E},
	{"t": 18, "k": K.C_BUILD, "x": 12, "y": 2, "type": K.T_SINK, "dir": K.D_E},
]

var SCRIPT_B: Array = [
	{"t": 0, "k": K.C_BUILD, "x": 3, "y": 8, "type": K.T_MINER, "dir": K.D_E},
	{"t": 2, "k": K.C_BUILD, "x": 4, "y": 8, "type": K.T_BELT, "dir": K.D_E},
	{"t": 4, "k": K.C_BUILD, "x": 5, "y": 8, "type": K.T_BELT, "dir": K.D_E},
	{"t": 6, "k": K.C_BUILD, "x": 6, "y": 8, "type": K.T_FURNACE, "dir": K.D_E},
	{"t": 8, "k": K.C_BUILD, "x": 7, "y": 8, "type": K.T_BELT, "dir": K.D_E},
	{"t": 10, "k": K.C_BUILD, "x": 8, "y": 8, "type": K.T_GEAR, "dir": K.D_E},
	{"t": 12, "k": K.C_BUILD, "x": 9, "y": 8, "type": K.T_BELT, "dir": K.D_E},
	{"t": 14, "k": K.C_BUILD, "x": 10, "y": 8, "type": K.T_ASSEMBLER, "dir": K.D_E},
	{"t": 16, "k": K.C_BUILD, "x": 11, "y": 8, "type": K.T_BELT, "dir": K.D_E},
	{"t": 18, "k": K.C_BUILD, "x": 12, "y": 8, "type": K.T_SINK, "dir": K.D_E},
]

func _initialize() -> void:
	print("=== S1+S2 驗收 (Godot %s) ===" % Engine.get_version_info()["string"])
	_test_replay_matches_live()
	_test_ghost_and_player()
	_test_ap_gate()
	_test_demolish_cost()
	_test_scale()
	_test_ghost_quota()
	_test_preview_matches_live()
	_test_preview_isolation()
	_test_win_reachable()
	_test_b_rule()
	_test_ore_rule()
	_test_ap_refund()
	_test_ghost_selection()
	_test_cell_conflict()
	_test_ap_regen()
	_test_rotate()
	print("----------------------------------")
	print("RESULT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

# ---------------------------------------------------------------- helpers

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] %s" % name)
	else:
		failures += 1
		print("  [FAIL] %s %s" % [name, detail])

func _new_manager():
	return LoopManager.new()

func _run(lm, script: Array, ticks: int) -> Array:
	var digests: Array = []
	var i: int = 0
	for _t in range(ticks):
		while i < script.size() and int(script[i]["t"]) <= lm.world.tick:
			var s: Dictionary = script[i]
			if int(s["k"]) == K.C_BUILD:
				lm.submit_build(Vector2i(s["x"], s["y"]), s["type"], s["dir"])
			else:
				lm.submit_demolish(Vector2i(s["x"], s["y"]))
			i += 1
		lm.step()
		digests.append(lm.world.digest())
	return digests

# ---------------------------------------------------------------- T1

func _test_replay_matches_live() -> void:
	print("[T1] 同一 loop：live vs 重播")
	var live = _new_manager()
	live.start_level()
	var d_live: Array = _run(live, SCRIPT_A, K.LOOP_TICKS)
	var log_a: Array = live.current_log.duplicate(true)

	var replay = _new_manager()
	replay.start_level()
	replay.add_ghost(log_a)
	replay.begin_loop(1)
	var d_replay: Array = _run(replay, [], K.LOOP_TICKS)

	_check("逐 tick 指紋一致 (%d ticks)" % d_live.size(), d_live == d_replay)
	_check("最終產出一致", int(live.world.delivered) == int(replay.world.delivered),
		"live=%d replay=%d" % [live.world.delivered, replay.world.delivered])
	_check("有交貨", int(live.world.delivered) > 0, "delivered=%d" % live.world.delivered)
	print("  delivered=%d ore=%d FINAL_DIGEST=%d" % [live.world.delivered, live.world.ore_mined, live.world.digest()])

# ---------------------------------------------------------------- T2

func _test_ghost_and_player() -> void:
	print("[T2] 幽靈同玩家並存嘅 loop，再整段重播")
	var lm = _new_manager()
	lm.start_level()
	_run(lm, SCRIPT_A, K.LOOP_TICKS)
	lm.seal_loop()
	lm.begin_loop(1)
	var d_live: Array = _run(lm, SCRIPT_B, K.LOOP_TICKS)

	var ghost_made := 0
	for idx in lm.world.buildings:
		if lm.world.buildings[idx].origin == 0:
			ghost_made += 1
	lm.seal_loop()
	lm.begin_loop(2)
	var d_replay: Array = _run(lm, [], K.LOOP_TICKS)

	_check("幽靈建築係真建築（%d 格）" % ghost_made, ghost_made > 0)
	_check("並存後重播逐 tick 一致", d_live == d_replay)
	print("  loop2 replay delivered=%d FINAL_DIGEST=%d" % [lm.world.delivered, lm.world.digest()])

# ---------------------------------------------------------------- T3

func _test_ap_gate() -> void:
	print("[T3] AP 上限：連環點擊唔可以超支")
	var lm = _new_manager()
	lm.start_level()
	var accepted := 0
	for i in range(K.AP_MAX + 5):
		if lm.submit_build(Vector2i(i, 8), K.T_BELT, K.D_E):
			accepted += 1
	_check("AP_MAX 之內全收 (%d/%d)" % [accepted, K.AP_MAX], accepted == K.AP_MAX)
	_check("可用 AP 用晒", lm.ap_available() == 0, "available=%d" % lm.ap_available())
	lm.step()
	_check("所有已排隊命令落地", int(lm.world.buildings.size()) == K.AP_MAX,
		"buildings=%d" % lm.world.buildings.size())
	_check("AP 剩 0", lm.ap_left() == 0, "ap=%d" % lm.ap_left())

	var log_ap: Array = lm.current_log.duplicate(true)
	var replay = _new_manager()
	replay.start_level()
	replay.add_ghost(log_ap)
	replay.begin_loop(1)
	_run(replay, [], 60)
	_check("重播後建築數一致", int(replay.world.buildings.size()) == K.AP_MAX)

# ---------------------------------------------------------------- T4

func _test_demolish_cost() -> void:
	print("[T4] 拆幽靈 = 2 AP，拆自己 = 淨 0（退返建造費）")
	var lm = _new_manager()
	lm.start_level()
	lm.submit_build(Vector2i(3, 3), K.T_BELT, K.D_E)
	lm.step()
	var log_a: Array = lm.current_log.duplicate(true)
	lm.add_ghost(log_a)
	lm.begin_loop(1)
	lm.step()
	var cell := Vector2i(3, 3)
	_check("幽靈建築存在", lm.world.building_at(cell) != null)
	_check("拆幽靈價錢 = 2", lm.demolish_cost(cell) == K.AP_COST_DEMOLISH_GHOST)
	var ok: bool = lm.submit_demolish(cell)
	lm.step()
	_check("拆成功且扣 2 AP", ok and lm.ap_left() == K.AP_MAX - K.AP_COST_DEMOLISH_GHOST,
		"ap=%d" % lm.ap_left())
	lm.submit_build(Vector2i(4, 3), K.T_BELT, K.D_E)
	lm.step()
	_check("拆自己嘅建築淨成本 = 0", lm.demolish_net_cost(Vector2i(4, 3)) == 0,
		"net=%d" % lm.demolish_net_cost(Vector2i(4, 3)))

# ---------------------------------------------------------------- T5

func _test_scale() -> void:
	print("[T5] 規模：8 loop × 1800 tick")
	var lm = _new_manager()
	lm.start_level()
	var t0 := Time.get_ticks_usec()
	for loop in range(K.LOOP_LIMIT):
		lm.begin_loop(loop)
		_run(lm, SCRIPT_A if loop == 0 else [], K.LOOP_TICKS)
		if loop < K.LOOP_LIMIT - 1:
			lm.seal_loop()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("  %.1f ms" % ms)
	_check("總耗時 < 6000ms", ms < 6000.0, "%.1f ms" % ms)

# ---------------------------------------------------------------- T6

func _test_ghost_quota() -> void:
	print("[T6] 幽靈上限：預設唔封頂；關卡可以自訂（有上限就要自己揀）")
	var lm = _new_manager()
	lm.start_level()
	_check("預設唔封頂", lm.is_quota_unlimited() and lm.ghost_quota() >= lm.UNLIMITED_QUOTA,
		"quota=%d" % lm.ghost_quota())
	for i in range(K.LOOP_LIMIT - 1):
		lm.submit_build(Vector2i(i, 1), K.T_BELT, K.D_E)
		lm.step()
		lm.seal_loop()
		lm.begin_loop(i + 1)
	_check("7 個幽靈全部出動（唔會逼你棄人）", lm.active.size() == K.LOOP_LIMIT - 1,
		"active=%s" % str(lm.active))

	# 關卡自訂上限
	var lm2 = _new_manager()
	lm2.start_level()
	lm2.ghost_cap = 3
	for i in range(K.LOOP_LIMIT - 1):
		lm2.submit_build(Vector2i(i, 1), K.T_BELT, K.D_E)
		lm2.step()
		lm2.seal_loop()
		lm2.begin_loop(i + 1)
	_check("自訂上限 3 -> 只出 3 個", lm2.active.size() == 3, "active=%s" % str(lm2.active))
	_check("上限唔會自動踢走你揀咗嘅人", lm2.active == [0, 1, 2], "active=%s" % str(lm2.active))
	lm2.step()
	var alive: int = 0
	for i in range(7):
		if lm2.world.building_at(Vector2i(i, 1)) != null:
			alive += 1
	_check("冇出動嘅幽靈唔會起嘢", alive == 3, "alive=%d" % alive)

	# 有上限時：手動換人
	lm2.toggle_ghost(0)
	_check("可以手動停用", not lm2.active.has(0), "active=%s" % str(lm2.active))
	_check("可以有上限咁加入", lm2.toggle_ghost(4, 3) and lm2.active.has(4), "active=%s" % str(lm2.active))
	_check("滿咗唔可以再加", not lm2.toggle_ghost(5, 3))

func _test_preview_matches_live() -> void:
	print("[T7] 預演可信：preview_at(t) 同當時 live 逐 tick 指紋一致")
	var lm = _new_manager()
	lm.start_level()
	var digests: Array = _run(lm, SCRIPT_A, K.LOOP_TICKS)

	var pv = lm.preview_clone()
	var targets: Array = [0, 1, 57, 300, 900, K.LOOP_TICKS]
	var all_ok := true
	var detail := ""
	for t in targets:
		pv.preview_at(int(t))
		var expected: int
		if int(t) == 0:
			var empty_world = load("res://sim/sim_world.gd").new()
			expected = empty_world.digest()
		else:
			expected = int(digests[int(t) - 1])
		if pv.world.digest() != expected:
			all_ok = false
			detail += " t=%d got=%d want=%d;" % [t, pv.world.digest(), expected]
	_check("前進對得上", all_ok, detail)

	# 前後拖（checkpoint 還原）
	pv.preview_at(K.LOOP_TICKS)
	pv.preview_at(300)
	_check("往回拖對得上 t=300", pv.world.digest() == int(digests[299]),
		"got=%d want=%d" % [pv.world.digest(), digests[299]])
	pv.preview_at(K.LOOP_TICKS)
	_check("再拖到尾對得上", pv.world.digest() == int(digests[K.LOOP_TICKS - 1]))
	_check("預演見到交貨", int(pv.world.delivered) > 0, "delivered=%d" % pv.world.delivered)

# ---------------------------------------------------------------- T8

func _test_preview_isolation() -> void:
	print("[T8] 預演唔會污染真實世界")
	var lm = _new_manager()
	lm.start_level()
	_run(lm, SCRIPT_A, 200)
	var before: int = lm.world.digest()
	var tick_before: int = lm.world.tick
	var log_before: int = lm.current_log.size()
	var ap_before: int = lm.ap_left()

	var pv = lm.preview_clone()
	pv.preview_at(K.LOOP_TICKS)
	pv.preview_at(10)
	pv.preview_at(K.LOOP_TICKS)

	_check("真實世界指紋不變", lm.world.digest() == before)
	_check("真實 tick 不變", lm.world.tick == tick_before)
	_check("命令 log 不變", lm.current_log.size() == log_before)
	_check("AP 不變", lm.ap_left() == ap_before)
	lm.step()
	_check("預演後仍然跑得正常", lm.world.tick == tick_before + 1)
# ---------------------------------------------------------------- T9

## B 規則下一條線最少 10 件（礦機 -> 帶帶 -> 爐 -> 帶 -> 齒輪 -> 帶 -> 組裝 -> 帶 -> 出口）
## 12 AP 只夠鋪 1 條線，所以每個 loop 增長 1 條。
func _lane_line(y: int) -> Array:
	var q := [
		[3, K.T_MINER], [4, K.T_BELT], [5, K.T_BELT], [6, K.T_FURNACE],
		[7, K.T_BELT], [8, K.T_GEAR], [9, K.T_BELT], [10, K.T_ASSEMBLER],
		[11, K.T_BELT], [12, K.T_SINK],
	]
	var out: Array = []
	for i in range(q.size()):
		out.append({"t": i * K.BUILD_TICKS, "k": K.C_BUILD, "x": q[i][0], "y": y, "type": q[i][1], "dir": K.D_E})
	return out

func _test_win_reachable() -> void:
	print("[T9] 勝利條件（%d 件）喺 %d 條礦脈內真係做得到" % [K.WIN_TARGET, K.ORE_LANES.size()])
	var lm = _new_manager()
	lm.start_level()
	var curve: Array = []
	var won_at := 0
	for loop in range(mini(K.LOOP_LIMIT, K.ORE_LANES.size())):
		lm.begin_loop(loop)
		_run(lm, _lane_line(int(K.ORE_LANES[loop])), K.LOOP_TICKS)
		curve.append(lm.world.delivered)
		if int(lm.world.delivered) >= K.WIN_TARGET:
			won_at = loop + 1
			break
		lm.seal_loop()
	print("  交貨曲線：%s（目標 %d）" % [str(curve), K.WIN_TARGET])
	_check("喺 %d 條礦脈內達標" % K.ORE_LANES.size(), won_at > 0, "curve=%s" % str(curve))
	_check("唔會第 1 個 loop 就贏", won_at >= 2, "won_at=%d" % won_at)
	print("  達標於第 %d 個 loop" % won_at)

func _test_b_rule() -> void:
	print("[T10] B 規則：機器唔可以直接餵機器，一定要經傳送帶")
	var lm = _new_manager()
	lm.start_level()
	# 礦機 -> 爐 直接相鄰（中間冇帶）-> 應該卡住
	var ly: int = int(K.ORE_LANES[0])
	lm.submit_build(Vector2i(K.ORE_X, ly), K.T_MINER, K.D_E)
	lm.submit_build(Vector2i(K.ORE_X + 1, ly), K.T_FURNACE, K.D_E)
	for i in range(400):
		lm.step()
	_check("冇帶連接 -> 冇交貨", int(lm.world.delivered) == 0, "delivered=%d" % lm.world.delivered)
	_check("爐冇收到礦", int(lm.world.building_at(Vector2i(K.ORE_X + 1, ly)).in_count) == 0,
		"in=%d" % lm.world.building_at(Vector2i(K.ORE_X + 1, ly)).in_count)

	var lm2 = _new_manager()
	lm2.start_level()
	# 加一條帶喺中間 -> 通
	for it in [[K.ORE_X, K.T_MINER], [K.ORE_X + 1, K.T_BELT], [K.ORE_X + 2, K.T_FURNACE]]:
		lm2.submit_build(Vector2i(it[0], ly), it[1], K.D_E)
	for i in range(400):
		lm2.step()
	_check("有帶連接 -> 爐收到礦", int(lm2.world.building_at(Vector2i(K.ORE_X + 2, ly)).in_count) > 0,
		"in=%d" % lm2.world.building_at(Vector2i(K.ORE_X + 2, ly)).in_count)

func _test_ore_rule() -> void:
	print("[T11] 礦機只可以擺喺礦脈上")
	var lm = _new_manager()
	lm.start_level()
	_check("礦脈上可以放", lm.can_build(Vector2i(K.ORE_X, int(K.ORE_LANES[0])), K.T_MINER))
	_check("非礦脈唔可以放", not lm.can_build(Vector2i(K.ORE_X + 1, int(K.ORE_LANES[0])), K.T_MINER))
	_check("傳送帶唔受限制", lm.can_build(Vector2i(K.ORE_X + 1, int(K.ORE_LANES[0])), K.T_BELT))
	var ok: bool = lm.submit_build(Vector2i(K.ORE_X + 1, int(K.ORE_LANES[0])), K.T_MINER, K.D_E)
	_check("submit 都會擋", not ok)
# ---------------------------------------------------------------- T12

func _test_ap_refund() -> void:
	print("[T12] 拆自己退 AP（搬位免費），拆幽靈冇退款，退款唔可以刷爆上限")
	var lm = _new_manager()
	lm.start_level()
	var start_ap: int = lm.ap_left()
	lm.submit_build(Vector2i(K.ORE_X, int(K.ORE_LANES[0])), K.T_MINER, K.D_E)
	lm.step()
	_check("建造扣 1 AP", lm.ap_left() == start_ap - K.AP_COST_BUILD, "ap=%d" % lm.ap_left())
	lm.submit_demolish(Vector2i(K.ORE_X, int(K.ORE_LANES[0])))
	lm.step()
	_check("拆自己退返，AP 回復原狀", lm.ap_left() == start_ap, "ap=%d" % lm.ap_left())

	# 搬位：同一格再起，總數唔會少
	lm.submit_build(Vector2i(K.ORE_X, int(K.ORE_LANES[0])), K.T_MINER, K.D_E)
	lm.step()
	_check("搬位後 AP = 上限 -1", lm.ap_left() == start_ap - 1, "ap=%d" % lm.ap_left())

	# 幽靈嘅建築：冇退款（用乾淨嘅 log，避免重播到本 loop 嘅拆遷命令）
	var lm_g = _new_manager()
	lm_g.start_level()
	lm_g.submit_build(Vector2i(K.ORE_X, int(K.ORE_LANES[0])), K.T_MINER, K.D_E)
	lm_g.step()
	var clean_log: Array = lm_g.current_log.duplicate(true)

	lm.begin_loop(1)
	lm.add_ghost(clean_log)
	lm.step()
	var gc := Vector2i(K.ORE_X, int(K.ORE_LANES[0]))
	_check("幽靈建築淨成本 = 2", lm.demolish_net_cost(gc) == K.AP_COST_DEMOLISH_GHOST)
	lm.submit_demolish(gc)
	lm.step()
	_check("拆幽靈扣足 2 AP、冇退款", lm.ap_left() == K.AP_MAX - K.AP_COST_DEMOLISH_GHOST,
		"ap=%d" % lm.ap_left())

	# 唔可以靠「起-拆」刷返超過上限
	var lm2 = _new_manager()
	lm2.start_level()
	for i in range(3):
		lm2.submit_build(Vector2i(K.ORE_X, int(K.ORE_LANES[0])), K.T_MINER, K.D_E)
		lm2.step()
		lm2.submit_demolish(Vector2i(K.ORE_X, int(K.ORE_LANES[0])))
		lm2.step()
	_check("反覆起拆唔會增加 AP", lm2.ap_left() == K.AP_MAX, "ap=%d" % lm2.ap_left())
	_check("反覆起拆唔會增加建築", lm2.world.buildings.is_empty())
# ---------------------------------------------------------------- T13

func _test_ghost_selection() -> void:
	print("[T13] 幽靈換人：手動揀人、有名額才自動出動、關掉即刻唔出動")
	var lm = _new_manager()
	lm.start_level()
	# loop 0：鋪一條線
	lm.submit_build(Vector2i(K.ORE_X, int(K.ORE_LANES[0])), K.T_MINER, K.D_E)
	lm.step()
	lm.seal_loop()
	_check("第一個幽靈自動出動", lm.active == [0], "active=%s" % str(lm.active))

	lm.begin_loop(1)
	lm.submit_build(Vector2i(K.ORE_X, int(K.ORE_LANES[1])), K.T_MINER, K.D_E)
	lm.step()
	lm.seal_loop()
	_check("有名額 -> 第二個都自動出動", lm.active == [0, 1], "active=%s" % str(lm.active))

	lm.begin_loop(2)
	lm.step()
	var stood := 0
	for lane in [0, 1]:
		if lm.world.building_at(Vector2i(K.ORE_X, int(K.ORE_LANES[lane]))) != null:
			stood += 1
	_check("兩個幽靈都幫手起嘢", stood == 2, "stood=%d" % stood)

	# 手動關掉第一個 -> 即刻唔再出動
	_check("手動關閉", lm.toggle_ghost(0) and lm.active == [1], "active=%s" % str(lm.active))
	lm.begin_loop(3)
	lm.step()
	_check("關掉嘅幽靈唔會起嘢", lm.world.building_at(Vector2i(K.ORE_X, int(K.ORE_LANES[0]))) == null)
	_check("冇關掉嘅照樣起嘢", lm.world.building_at(Vector2i(K.ORE_X, int(K.ORE_LANES[1]))) != null)

	# 用下一個 loop 嘅上限開返（報告畫面用嘅 API）
	var next_quota: int = lm.ghost_quota_for(lm.loop_index + 1)
	_check("可以再開返", lm.toggle_ghost(0, next_quota) and lm.active.has(0), "active=%s" % str(lm.active))

	# 有上限時要擋
	var lm_c = _new_manager()
	lm_c.start_level()
	lm_c.ghost_cap = 1
	lm_c.submit_build(Vector2i(K.ORE_X, int(K.ORE_LANES[0])), K.T_MINER, K.D_E)
	lm_c.step()
	lm_c.seal_loop()
	lm_c.submit_build(Vector2i(K.ORE_X, int(K.ORE_LANES[1])), K.T_MINER, K.D_E)
	lm_c.step()
	lm_c.seal_loop()
	lm_c.active = [0]
	_check("上限 1 時唔可以再加人", not lm_c.toggle_ghost(1, 1) and lm_c.active == [0],
		"active=%s" % str(lm_c.active))
# ---------------------------------------------------------------- T14

## 玩家同幽靈搶同一格：4 種情況
func _test_cell_conflict() -> void:
	print("[T14] 玩家同幽靈搶同一格")
	var cell := Vector2i(10, 3)
	var ghost_log: Array = [{"t": 5, "k": K.C_BUILD, "x": cell.x, "y": cell.y, "type": K.T_BELT, "dir": K.D_E}]

	# A) 幽靈已經建好
	var a = _new_manager()
	a.start_level()
	a.add_ghost(ghost_log)
	a.begin_loop(1)
	while a.world.tick < 10:
		a.step()
	var ap_a0: int = a.ap_left()
	var ok_a: bool = a.submit_build(cell, K.T_GEAR, K.D_E)
	a.step()
	_check("A 幽靈已佔住 -> 玩家被拒、唔扣 AP",
		(not ok_a) and a.ap_left() == ap_a0 and int(a.world.building_at(cell).type) == K.T_BELT,
		"ok=%s ap=%d type=%d" % [ok_a, a.ap_left(), int(a.world.building_at(cell).type)])

	# B) 玩家先建，幽靈遲啲嚟
	var b = _new_manager()
	b.start_level()
	b.add_ghost(ghost_log)
	b.begin_loop(1)
	var ok_b: bool = b.submit_build(cell, K.T_GEAR, K.D_E)
	while b.world.tick < 10:
		b.step()
	_check("B 玩家先 -> 玩家嘅建築留低，幽靈靜靜雞失敗",
		ok_b and int(b.world.building_at(cell).type) == K.T_GEAR,
		"type=%d" % int(b.world.building_at(cell).type))

	# C) 同一個 tick：幽靈先套用 -> 玩家失敗（但要有 rejected 紀錄畀 UI 閃紅）
	var c = _new_manager()
	c.start_level()
	c.add_ghost(ghost_log)
	c.begin_loop(1)
	while c.world.tick < 4:
		c.step()
	var ap_c0: int = c.ap_left()
	var ok_c: bool = c.submit_build(cell, K.T_GEAR, K.D_E)
	var rej := 0
	for i in range(4):
		c.step()
		rej += c.rejected.size()
	_check("C 同 tick -> 幽靈贏、玩家唔扣 AP", int(c.world.building_at(cell).type) == K.T_BELT and c.ap_left() == ap_c0,
		"type=%d ap=%d" % [int(c.world.building_at(cell).type), c.ap_left()])
	_check("C 玩家失敗有記錄（畀 UI 閃紅）", rej > 0, "rejected=%d" % rej)

	# D) 拆幽靈建築再重建
	var d = _new_manager()
	d.start_level()
	d.add_ghost(ghost_log)
	d.begin_loop(1)
	while d.world.tick < 10:
		d.step()
	var ap_d0: int = d.ap_left()
	d.submit_demolish(cell)
	d.step()
	var ok_dr: bool = d.submit_build(cell, K.T_GEAR, K.D_E)
	d.step()
	_check("D 拆幽靈 -2 AP，之後可以重建",
		ok_dr and d.ap_left() == ap_d0 - K.AP_COST_DEMOLISH_GHOST - K.AP_COST_BUILD
			and int(d.world.building_at(cell).type) == K.T_GEAR,
		"ap=%d type=%d" % [d.ap_left(), int(d.world.building_at(cell).type)])
# ---------------------------------------------------------------- T15

func _test_ap_regen() -> void:
	print("[T15] AP 隨時間回復（%d 點 / %d tick，上限 %d）" % [K.AP_REGEN_AMOUNT, K.AP_REGEN_TICKS, K.AP_MAX])
	# 1) 花光之後，到時間會回
	var lm = _new_manager()
	lm.start_level()
	for i in range(K.AP_MAX):
		lm.submit_build(Vector2i(i, 1), K.T_BELT, K.D_E)
	lm.step()
	_check("先花光 12 點", lm.ap_left() == 0, "ap=%d" % lm.ap_left())
	while lm.world.tick < K.AP_REGEN_TICKS - 1:
		lm.step()
	_check("未到時間唔回", lm.ap_left() == 0, "ap=%d" % lm.ap_left())
	lm.step()
	_check("到 %d tick 回 %d 點" % [K.AP_REGEN_TICKS, K.AP_REGEN_AMOUNT],
		lm.ap_left() == K.AP_REGEN_AMOUNT, "ap=%d" % lm.ap_left())
	_check("倒數查詢正常", lm.ticks_to_next_ap() > 0 and lm.ticks_to_next_ap() <= K.AP_REGEN_TICKS)

	# 2) 唔可以超過上限
	var lm2 = _new_manager()
	lm2.start_level()
	while lm2.world.tick < K.LOOP_TICKS:
		lm2.step()
	_check("冇花 AP 都唔會爆上限", lm2.ap_left() == K.AP_MAX, "ap=%d" % lm2.ap_left())
	_check("滿 AP 時回報 -1", lm2.ticks_to_next_ap() == -1, "t=%d" % lm2.ticks_to_next_ap())

	# 3) 有回復都保持確定性（live vs 幽靈重播）
	var live = _new_manager()
	live.start_level()
	var d_live: Array = []
	var i := 0
	var script: Array = []
	for x in range(10):
		script.append({"t": x * 15, "k": K.C_BUILD, "x": 4 + x, "y": 3, "type": K.T_BELT, "dir": K.D_E})
	# 遲啲（回咗 AP 之後）再建一個
	script.append({"t": 700, "k": K.C_BUILD, "x": 19, "y": 2, "type": K.T_BELT, "dir": K.D_E})
	for tick in range(K.LOOP_TICKS):
		while i < script.size() and int(script[i]["t"]) <= live.world.tick:
			var s: Dictionary = script[i]
			live.submit_build(Vector2i(s["x"], s["y"]), s["type"], K.D_E)
			i += 1
		live.step()
		d_live.append(live.world.digest())
	var log_a: Array = live.current_log.duplicate(true)

	var replay = _new_manager()
	replay.start_level()
	replay.add_ghost(log_a)
	replay.begin_loop(1)
	var d_replay: Array = []
	for tick in range(K.LOOP_TICKS):
		replay.step()
		d_replay.append(replay.world.digest())
	_check("有 AP 回復之下，重播逐 tick 一致", d_live == d_replay)
	_check("回復後真係建到額外建築", int(live.world.buildings.size()) >= 10,
		"buildings=%d" % live.world.buildings.size())
# ---------------------------------------------------------------- T16

func _test_rotate() -> void:
	print("[T16] 就地方向旋轉（唔使拆）")
	var cell := Vector2i(K.ORE_X, int(K.ORE_LANES[0]))

	# 1) 自己嘅建築：免費
	var a = _new_manager()
	a.start_level()
	a.submit_build(cell, K.T_MINER, K.D_E)
	a.step()
	var ap0: int = a.ap_left()
	var ok_a: bool = a.submit_rotate(cell, K.D_S)
	a.step()
	_check("自己嘅可免費轉向", ok_a and int(a.world.building_at(cell).dir) == K.D_S and a.ap_left() == ap0,
		"ok=%s dir=%d ap=%d" % [ok_a, int(a.world.building_at(cell).dir), a.ap_left()])
	_check("空格唔可以轉", not a.can_rotate(Vector2i(9, 9)))

	# 2) 幽靈嘅建築：2 AP
	var b = _new_manager()
	b.start_level()
	b.submit_build(cell, K.T_MINER, K.D_E)
	b.step()
	var log_a: Array = b.current_log.duplicate(true)
	b.add_ghost(log_a)
	b.begin_loop(1)
	b.step()
	var ap_b0: int = b.ap_left()
	var ok_b: bool = b.submit_rotate(cell, K.D_S)
	b.step()
	_check("轉幽靈嘅建築要 2 AP",
		ok_b and int(b.world.building_at(cell).dir) == K.D_S
			and b.ap_left() == ap_b0 - K.AP_COST_ROTATE_GHOST,
		"ok=%s ap=%d dir=%d" % [ok_b, b.ap_left(), int(b.world.building_at(cell).dir)])

	# 3) 有 rotate 嘅 log 一樣重播得一致
	var live = _new_manager()
	live.start_level()
	var d_live: Array = []
	var i := 0
	var script: Array = [
		{"t": 0, "k": K.C_BUILD, "x": K.ORE_X, "y": int(K.ORE_LANES[0]), "type": K.T_MINER, "dir": K.D_E},
		{"t": 20, "k": K.C_ROTATE, "x": K.ORE_X, "y": int(K.ORE_LANES[0]), "dir": K.D_S},
		{"t": 40, "k": K.C_BUILD, "x": K.ORE_X + 1, "y": int(K.ORE_LANES[0]), "type": K.T_BELT, "dir": K.D_N},
		{"t": 60, "k": K.C_ROTATE, "x": K.ORE_X + 1, "y": int(K.ORE_LANES[0]), "dir": K.D_E},
	]
	for tick in range(K.LOOP_TICKS):
		while i < script.size() and int(script[i]["t"]) <= live.world.tick:
			var s: Dictionary = script[i]
			var c := Vector2i(s["x"], s["y"])
			if int(s["k"]) == K.C_BUILD:
				live.submit_build(c, s["type"], s["dir"])
			else:
				live.submit_rotate(c, s["dir"])
			i += 1
		live.step()
		d_live.append(live.world.digest())

	var replay = _new_manager()
	replay.start_level()
	replay.add_ghost(live.current_log.duplicate(true))
	replay.begin_loop(1)
	var d_replay: Array = []
	for tick in range(K.LOOP_TICKS):
		replay.step()
		d_replay.append(replay.world.digest())
	_check("有旋轉命令都重播一致", d_live == d_replay)
