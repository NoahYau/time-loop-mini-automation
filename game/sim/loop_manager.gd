extends RefCounted
## 時間循環 + 幽靈管線 + 預演（時間軸 scrub）。
##
## 已鎖定規則（v1.1）：
##   * 幽靈建嘅係「真建築」：存在、佔格、會生產。
##   * 可以重做幽靈做嘅事，但拆幽靈建築 = 2 AP，拆自己嘅 = 1 AP。
##   * LOOP_LIMIT 個 loop 內要達標。
##   * 幽靈上限 = 剩餘 loop 數 + GHOST_SLACK（寬鬆 B，防後期斷崖）。
##   * 空 loop 唔佔幽靈名額。
##
## 確定性規則（S1/S2 地基）：
##   所有命令（幽靈 + 玩家）都喺 tick 邊界依序執行：
##   舊 loop 幽靈（loop 0 -> N）先，本 loop 玩家最後。
##   live 同 replay 走同一條 _apply()，所以預演可以逐 tick 對得上。

const K = preload("res://sim/constants.gd")
const SimWorld = preload("res://sim/sim_world.gd")

## GHOST_CAP = 0 -> 唔封頂（預設）；> 0 -> 同時受「剩餘 loop + slack」限制。
## 呢個係關卡參數：想加難度才開。
const GHOST_SLACK: int = 2
const UNLIMITED_QUOTA: int = 99
## 預演每幾多 tick 存一個 checkpoint（拖 timeline 唔會卡）。
const PV_MARK_EVERY: int = 120

var world: SimWorld
var ghosts: Array = []        # Array[Array[Dictionary]]，index = loop 編號
var current_log: Array = []   # 本 loop 玩家提交嘅命令
var active: Array = []        # 今個 loop 參與重播嘅幽靈
var loop_index: int = 0
var tick: int = 0
var loop_limit: int = K.LOOP_LIMIT
var ghost_cap: int = K.GHOST_CAP      # 0 = 唔封頂

var _ap: Dictionary = {}      # AP key -> 剩餘 AP
var _cursor: Dictionary = {}  # AP key -> log 讀到邊
var _pkey: int = 0            # 玩家喺 _ap / _cursor 用嘅 key（預演時係 pseudo）
var _preview: bool = false
var _marks: Array = []
## 玩家命令被拒嘅紀錄（tick, x, y, 原因）。畀 UI 做紅閃回饋，逐個 frame 清空。
var rejected: Array = []

func _init() -> void:
	world = SimWorld.new()

func start_level(limit: int = K.LOOP_LIMIT) -> void:
	loop_limit = limit
	ghosts = []
	current_log = []
	active = []
	loop_index = 0
	begin_loop(0)

func begin_loop(n: int) -> void:
	loop_index = n
	world.clear()
	tick = 0
	current_log = []
	_pkey = n
	_ap.clear()
	_cursor.clear()
	rejected.clear()
	for i in range(ghosts.size() + 1):
		_ap[i] = K.AP_MAX
		_cursor[i] = 0
	# 玩家 key 一定要存在（唔好假設 ghosts 數 == loop 數）
	_ap[_pkey] = K.AP_MAX
	_cursor[_pkey] = 0
	_active_reset_preview()
	_trim_active()

func seal_loop() -> void:
	ghosts.append(current_log.duplicate(true))
	# 乜都冇做嘅 loop 唔佔幽靈位；有名額才自動出動。
	# 冇名額就排隊等玩家喺結算畫面揀 —— 唔會靜靜雞踢走你揀咗嘅幽靈。
	if not current_log.is_empty():
		var li: int = ghosts.size() - 1
		if active.size() < ghost_quota():
			active.append(li)
		_ap[li] = K.AP_MAX
		_cursor[li] = 0
	_trim_active()

# ---------------------------------------------------------------- 幽靈名額

## 第 li 個 loop 嘅幽靈上限。ghost_cap = 0 時回傳 UNLIMITED_QUOTA。
func ghost_quota_for(li: int) -> int:
	if ghost_cap <= 0:
		return UNLIMITED_QUOTA
	var by_loops: int = maxi(0, loop_limit - li + GHOST_SLACK)
	return mini(ghost_cap, by_loops)

func is_quota_unlimited() -> bool:
	return ghost_cap <= 0

func ghost_quota() -> int:
	return ghost_quota_for(loop_index)

func _trim_active() -> void:
	var keep: Array = []
	for li in active:
		if int(li) < ghosts.size() and not (ghosts[int(li)] as Array).is_empty():
			keep.append(int(li))
	keep.sort()
	var q := ghost_quota()
	while keep.size() > q:
		keep.pop_front()
	active = keep

func is_ghost_active(li: int) -> bool:
	return active.has(li)

func ghost_has_work(li: int) -> bool:
	return li >= 0 and li < ghosts.size() and not (ghosts[li] as Array).is_empty()

## 手動換人（受上限約束）。停用一個舊幽靈 = 佢今個 loop 唔會幫你起嘢。
## quota_override >= 0 時用指定上限（結算畫面用「下一個 loop」嘅上限）。
func toggle_ghost(li: int, quota_override: int = -1) -> bool:
	if not ghost_has_work(li):
		return false
	if active.has(li):
		active.erase(li)
		return true
	var q: int = ghost_quota() if quota_override < 0 else quota_override
	if active.size() >= q:
		return false
	active.append(li)
	active.sort()
	return true

func add_ghost(log: Array) -> void:
	ghosts.append(log.duplicate(true))
	var li: int = ghosts.size() - 1
	if not _ap.has(li):
		_ap[li] = K.AP_MAX
	if not _cursor.has(li):
		_cursor[li] = 0
	if not log.is_empty():
		active.append(li)
	_trim_active()

# ---------------------------------------------------------------- 玩家操作

func ap_left(li: int = -1) -> int:
	if li < 0:
		li = _pkey
	return _ap.get(li, 0)

## 已排隊但未執行嘅命令預留嘅 AP（令連環點擊唔會超支）。
func _pending_ap() -> int:
	var total := 0
	var i: int = _cursor.get(_pkey, 0)
	while i < current_log.size():
		var cmd: Dictionary = current_log[i]
		if int(cmd["k"]) == K.C_BUILD:
			total += K.AP_COST_BUILD
		elif int(cmd["k"]) == K.C_ROTATE:
			var cb = world.building_at(Vector2i(int(cmd["x"]), int(cmd["y"])))
			if cb != null and cb.origin != loop_index:
				total += K.AP_COST_ROTATE_GHOST
		else:
			total += demolish_net_cost(Vector2i(int(cmd["x"]), int(cmd["y"])))
		i += 1
	return total

## 即時可用 AP（扣走排隊中嘅）。
## 距離下一次 AP 回復仲有幾多 tick（0 = 即時）。
func ticks_to_next_ap() -> int:
	if K.AP_REGEN_TICKS <= 0:
		return 0
	if ap_left() >= K.AP_MAX:
		return -1
	return K.AP_REGEN_TICKS - (world.tick % K.AP_REGEN_TICKS)

func ap_available() -> int:
	return maxi(0, ap_left() - _pending_ap())

func can_build(cell: Vector2i, type: int = -1) -> bool:
	if type < 0:
		type = K.T_BELT
	if not world.can_place(cell, type):
		return false
	return ap_available() >= K.AP_COST_BUILD

## 拆呢格嘅淨 AP 開支：拆自己 = 0（退晒），拆幽靈 = 2。
func demolish_net_cost(cell: Vector2i) -> int:
	var b = world.building_at(cell)
	if b == null:
		return 0
	return 0 if b.origin == loop_index else K.AP_COST_DEMOLISH_GHOST

func can_demolish(cell: Vector2i) -> bool:
	if not world.in_bounds(cell):
		return false
	var idx := world.idx_of(cell)
	if not world.buildings.has(idx):
		return false
	return ap_available() >= demolish_net_cost(cell)

func demolish_cost(cell: Vector2i) -> int:
	var b = world.building_at(cell)
	if b == null:
		return 0
	return K.AP_COST_DEMOLISH_OWN if b.origin == loop_index else K.AP_COST_DEMOLISH_GHOST

## 命令排隊，喺下一個 tick 邊界同幽靈一齊執行（保證預演 = 實際）。
func submit_build(cell: Vector2i, type: int, dir: int) -> bool:
	if not can_build(cell, type):
		return false
	current_log.append({"t": world.tick + 1, "k": K.C_BUILD, "x": cell.x, "y": cell.y, "type": type, "dir": dir})
	return true

func rotate_cost(cell: Vector2i) -> int:
	var b = world.building_at(cell)
	if b == null:
		return 0
	return 0 if b.origin == loop_index else K.AP_COST_ROTATE_GHOST

func can_rotate(cell: Vector2i) -> bool:
	if world.building_at(cell) == null:
		return false
	return ap_available() >= rotate_cost(cell)

## 就地改方向（唔使拆）。自己嘅免費，幽靈嘅 2 AP。
func submit_rotate(cell: Vector2i, dir: int) -> bool:
	if not can_rotate(cell):
		return false
	current_log.append({"t": world.tick + 1, "k": K.C_ROTATE, "x": cell.x, "y": cell.y, "dir": dir})
	return true

func submit_demolish(cell: Vector2i) -> bool:
	if not can_demolish(cell):
		return false
	current_log.append({"t": world.tick + 1, "k": K.C_DEMOLISH, "x": cell.x, "y": cell.y})
	return true

# ---------------------------------------------------------------- tick

func step() -> void:
	var nt := world.tick + 1
	# AP 隨時間回復：純 tick 驅動，所以 live / 預演 / 重播完全一致
	if K.AP_REGEN_TICKS > 0 and nt % K.AP_REGEN_TICKS == 0:
		for key in _ap.keys():
			_ap[key] = mini(K.AP_MAX, int(_ap[key]) + K.AP_REGEN_AMOUNT)
	for li in active:
		_apply_until(li, ghosts[li], nt, li, li)
	_apply_until(_pkey, current_log, nt, _pkey, loop_index)
	world.step()
	tick = world.tick

func _apply_until(ap_key: int, log: Array, upto: int, ap_slot: int, origin_loop: int) -> void:
	var i: int = _cursor.get(ap_key, 0)
	while i < log.size() and int(log[i]["t"]) <= upto:
		_apply(log[i], ap_slot, origin_loop)
		i += 1
	_cursor[ap_key] = i

## 唯一嘅命令入口：live 同 replay 完全同一條路徑、同一套規則。
func _apply(cmd: Dictionary, ap_slot: int, origin_loop: int) -> bool:
	var cell := Vector2i(int(cmd["x"]), int(cmd["y"]))
	if not world.in_bounds(cell):
		return false
	var idx := world.idx_of(cell)
	var ap: int = _ap.get(ap_slot, 0)
	var is_player: bool = ap_slot == _pkey
	if int(cmd["k"]) == K.C_BUILD:
		if not world.can_place(cell, int(cmd["type"])):
			if is_player:
				rejected.append({"x": cell.x, "y": cell.y, "t": world.tick + 1, "why": "格已被佔用"})
			return false
		if ap < K.AP_COST_BUILD:
			if is_player:
				rejected.append({"x": cell.x, "y": cell.y, "t": world.tick + 1, "why": "AP不足"})
			return false
		world.build(idx, int(cmd["type"]), int(cmd["dir"]), origin_loop)
		_ap[ap_slot] = ap - K.AP_COST_BUILD
		return true
	if int(cmd["k"]) == K.C_ROTATE:
		var rb = world.buildings.get(idx, null)
		if rb == null:
			if is_player:
				rejected.append({"x": cell.x, "y": cell.y, "t": world.tick + 1, "why": "格已空"})
			return false
		var rcost: int = 0 if rb.origin == origin_loop else K.AP_COST_ROTATE_GHOST
		if ap < rcost:
			if is_player:
				rejected.append({"x": cell.x, "y": cell.y, "t": world.tick + 1, "why": "AP不足"})
			return false
		rb.dir = int(cmd["dir"])
		_ap[ap_slot] = ap - rcost
		return true
	if not world.buildings.has(idx):
		if is_player:
			rejected.append({"x": cell.x, "y": cell.y, "t": world.tick + 1, "why": "格已空"})
		return false
	var b = world.buildings[idx]
	var mine: bool = b.origin == origin_loop
	# 拆自己：退返當初建造用嘅 AP（淨 +1）。拆幽靈：扣 2、冇退款。
	var net: int = 0 if mine else K.AP_COST_DEMOLISH_GHOST
	var refund: int = K.AP_REFUND_DEMOLISH_OWN if mine else 0
	if ap < net:
		if is_player:
			rejected.append({"x": cell.x, "y": cell.y, "t": world.tick + 1, "why": "AP不足"})
		return false
	world.demolish(idx)
	# 退款唔可以令 AP 超過上限（防止「起-拆-起」刷 AP）
	_ap[ap_slot] = mini(K.AP_MAX, ap - net + refund)
	return true

# ---------------------------------------------------------------- 預演（時間軸 scrub）

## 由而家嘅狀態整一份「乾淨嘅」預演用 manager：
## 由 tick 0 開始、世界清空、本 loop 玩家命令當成最後一個幽靈重播。
func preview_clone():
	var m = load("res://sim/loop_manager.gd").new()
	m.loop_limit = loop_limit
	m.loop_index = loop_index
	m._preview = true
	m.ghosts = ghosts.duplicate()
	m.ghosts.append(current_log.duplicate(true))
	m.active = active.duplicate()
	m.active.append(m.ghosts.size() - 1)
	m._pkey = m.ghosts.size() - 1
	m.current_log = []
	m.world.clear()
	m.tick = 0
	m._marks = [{"tick": 0, "state": m.world.save_state(), "ap": {}}]
	for i in range(m.ghosts.size() + 1):
		m._ap[i] = K.AP_MAX
		m._cursor[i] = 0
	return m

## 將預演推進到 target tick（可以前後拖）。
func preview_at(target: int) -> void:
	target = clampi(target, 0, K.LOOP_TICKS)
	if target < world.tick:
		_restore_mark(target)
	var guard := 0
	while world.tick < target and guard <= K.LOOP_TICKS:
		guard += 1
		step()
		if world.tick % PV_MARK_EVERY == 0:
			_marks.append({"tick": world.tick, "state": world.save_state(), "ap": _ap.duplicate()})
	if world.tick % PV_MARK_EVERY == 0 and world.tick > 0:
		var exists := false
		for mk in _marks:
			if int(mk["tick"]) == world.tick:
				exists = true
				break
		if not exists:
			_marks.append({"tick": world.tick, "state": world.save_state(), "ap": _ap.duplicate()})

func _restore_mark(target: int) -> void:
	var best: Dictionary = {}
	for mk in _marks:
		if int(mk["tick"]) <= target:
			best = mk
	if best.is_empty():
		return
	world.load_state(best["state"])
	_ap = (best["ap"] as Dictionary).duplicate()
	_reset_cursors_to(world.tick)
	var keep: Array = []
	for mk in _marks:
		if int(mk["tick"]) <= int(best["tick"]):
			keep.append(mk)
	_marks = keep

func _reset_cursors_to(t: int) -> void:
	for key in _cursor.keys():
		var li := int(key)
		var log: Array = ghosts[li] if li < ghosts.size() else []
		var i := 0
		while i < log.size() and int(log[i]["t"]) <= t:
			i += 1
		_cursor[key] = i

func _active_reset_preview() -> void:
	_marks = []

# ---------------------------------------------------------------- 查詢

func is_won() -> bool:
	return world.delivered >= K.WIN_TARGET

func is_last_loop() -> bool:
	return loop_index >= loop_limit - 1

func ghost_quota_str() -> String:
	return "%d/%d" % [active.size(), ghost_quota()]

## 每個幽靈喺今個 loop 嘅工作報告（用嚟做結算畫面）。
func ghost_report() -> Array:
	var out: Array = []
	for li in range(ghosts.size()):
		var standing := 0
		var overwritten := 0
		for idx in world.buildings:
			var b = world.buildings[idx]
			if b.origin == li:
				standing += 1
		overwritten = maxi(0, (ghosts[li] as Array).size() - standing)
		out.append({
			"loop": li,
			"active": active.has(li),
			"actions": (ghosts[li] as Array).size(),
			"standing": standing,
			"lost": overwritten,
		})
	return out

func digest() -> int:
	return world.digest()
