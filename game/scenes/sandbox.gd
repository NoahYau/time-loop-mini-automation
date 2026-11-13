extends Node2D
## S2 可玩切片：滑鼠建造 + 時間軸預演 + 幽靈工作報告。
##
## 操作：點建築選單 / 按 1–6 / 滾輪 選建築，Q/E 轉向，左鍵放、右鍵拆。
##       按住 SHIFT = 時間停止 + 拖時間軸預演（呢個係可讀性生死線）。
##       SPACE 暫停，D = 自動示範一條線（debug），R 重來（完場後）。

const K = preload("res://sim/constants.gd")
const LoopManager = preload("res://sim/loop_manager.gd")

const CELL := 40.0
const ORIGIN := Vector2(20, 44)
const BUILD_TICKS: int = K.BUILD_TICKS
const TL_Y := 692.0                # 時間軸
const TL_H := 16.0
const PANEL_X := 700.0
const PALETTE_Y := 392.0           # 建築選單頂部
const PALETTE_BTN := Vector2(104, 58)
const PALETTE_GAP := 6.0
const PALETTE_COLS := 3            # 1/2/3 一行，4/5/6 下一行

# 結算／規劃面板
const REPORT_X := 700.0
const REPORT_Y := 268.0
const REPORT_W := 552.0
const REPORT_ROWS_Y := 78.0
const REPORT_ROW_H := 21.0
const PALETTE_TYPES: Array = [1, 2, 3, 4, 5, 6]   # 同 constants.gd 嘅 T_* 一致

enum P { RUN, REPORT, WIN, LOSE }

var lm
var phase: int = P.RUN
var acc: float = 0.0
var speed: float = 1.0
var paused: bool = false
var started: bool = false

var busy: int = 0                   # 建造佔用剩餘 tick
var selected: int = K.T_BELT
var place_dir: int = K.D_E
var hover: Vector2i = Vector2i(-1, -1)
var flash: Dictionary = {}          # idx -> 秒（白）
var deny: Dictionary = {}           # idx -> 秒（紅）

var report_timer: float = 0.0
var report: Dictionary = {}
var total_delivered: int = 0
var last_loop_delivered: int = 0
var loops_used: int = 0

var mouse_pos: Vector2 = Vector2(-1, -1)   # 由事件追蹤嘅鼠標位置（同點擊同一座標系）
var debug_clicks: Array = []      # 最近收到嘅點擊（除錯用）
var restart_armed: bool = false
var restart_arm_timer: float = 0.0
const RESTART_CONFIRM_SEC := 2.0
var toast: String = ""
var toast_timer: float = 0.0
var fast_forward: bool = false
var ff_mult: float = 8.0
var previewing: bool = false
var pv = null
var pv_tick: int = 0

const ART := "res://art/"
var art: Dictionary = {}

## 攞貼圖：優先經 Godot 匯入系統；未匯入（例如未開過編輯器）就即場解 PNG。
## 咁樣 headless 測試同未 import 嘅環境都照跑得到。
func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() > 0:
			var img := Image.new()
			if img.load_png_from_buffer(bytes) == OK:
				return ImageTexture.create_from_image(img)
	return null

func _load_art() -> void:
	var singles := [
		"tiles/ground", "tiles/ore", "buildings/miner", "buildings/gear",
		"buildings/assembler", "buildings/sink",
		"buildings/furnace_a", "buildings/furnace_b",
		"items/ore", "items/ingot", "items/gear", "items/part",
	]
	for n in singles:
		var t := _tex(ART + n + ".png")
		if t != null:
			art[n] = t
	for d in ["e", "n", "s", "w"]:
		for f in ["a", "b"]:
			var t2 := _tex(ART + "buildings/belt_%s_%s.png" % [d, f])
			if t2 != null:
				art["buildings/belt_%s_%s" % [d, f]] = t2

func _ready() -> void:
	_load_art()
	lm = LoopManager.new()
	lm.start_level()
	started = true

# ---------------------------------------------------------------- 主循環

func _process(delta: float) -> void:
	if toast_timer > 0.0:
		toast_timer -= delta
	if restart_arm_timer > 0.0:
		restart_arm_timer -= delta
		if restart_arm_timer <= 0.0:
			restart_armed = false
	# 鼠標喺建築選單上面 -> 手指（提示可以點）
	var over_ui: bool = _palette_index_at(mouse_pos) >= 0
	if phase == P.RUN and _end_loop_rect().has_point(mouse_pos):
		over_ui = true
	if phase == P.REPORT:
		over_ui = _report_start_rect().has_point(mouse_pos) or _report_row_at(mouse_pos) >= 0
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over_ui else Input.CURSOR_ARROW)
	if not started or paused or previewing:
		queue_redraw()
		return
	if phase == P.REPORT:
		queue_redraw()   # 時間停住，等玩家揀幽靈／按開始
		return
	if phase == P.WIN or phase == P.LOSE:
		queue_redraw()
		return

	var step_dt := 1.0 / float(K.SIM_HZ)
	acc += delta * (ff_mult if fast_forward else speed)
	var guard := 0
	while acc >= step_dt and guard < 600:
		guard += 1
		acc -= step_dt
		lm.step()
		_drain_rejected()
		if busy > 0:
			busy -= 1
		_tick_fx(step_dt)
		if lm.world.delivered >= K.WIN_TARGET:
			_end_loop(true)
			break
		if lm.world.tick >= K.LOOP_TICKS:
			_end_loop(false)
			break
	queue_redraw()

## 玩家命令喺執行時被拒（例如同一 tick 撞到幽靈）-> 紅閃，唔好靜靜雞食咗
func _drain_rejected() -> void:
	if lm.rejected.is_empty():
		return
	for r in lm.rejected:
		var idx: int = lm.world.idx_of(Vector2i(int(r["x"]), int(r["y"])))
		deny[idx] = 0.5
	lm.rejected.clear()

func _tick_fx(dt: float) -> void:
	for k in flash.keys():
		flash[k] -= dt
		if flash[k] <= 0.0:
			flash.erase(k)
	for k in deny.keys():
		deny[k] -= dt
		if deny[k] <= 0.0:
			deny.erase(k)

func _end_loop(won: bool) -> void:
	last_loop_delivered = lm.world.delivered
	total_delivered += last_loop_delivered
	loops_used = lm.loop_index + 1
	report = {
		"delivered": last_loop_delivered,
		"ap_left": lm.ap_left(),
		"ghosts": lm.ghost_report(),
		"active": lm.active.duplicate(),
	}
	if won:
		lm.seal_loop()
		phase = P.WIN
		return
	lm.seal_loop()
	if lm.is_last_loop():
		phase = P.LOSE
	else:
		phase = P.REPORT

func _after_report() -> void:
	lm.begin_loop(lm.loop_index + 1)
	fast_forward = false
	busy = 0
	pv = null
	previewing = false
	phase = P.RUN
	acc = 0.0

func _restart() -> void:
	lm.start_level()
	phase = P.RUN
	total_delivered = 0
	loops_used = 0
	busy = 0
	acc = 0.0
	pv = null
	previewing = false
	flash.clear()
	deny.clear()
	report = {}
	fast_forward = false
	paused = false
	started = true
	restart_armed = false
	restart_arm_timer = 0.0
	toast = "已重來 — 由 LOOP 1 開始"
	toast_timer = 1.6

# ---------------------------------------------------------------- 輸入

func _cell_at(p: Vector2) -> Vector2i:
	var local := (p - ORIGIN) / CELL
	var c := Vector2i(floori(local.x), floori(local.y))
	if c.x < 0 or c.y < 0 or c.x >= K.GRID_W or c.y >= K.GRID_H:
		return Vector2i(-1, -1)
	return c

func _in_timeline(p: Vector2) -> bool:
	return p.y >= TL_Y - 6.0 and p.y <= TL_Y + TL_H + 6.0 and p.x >= ORIGIN.x and p.x <= ORIGIN.x + K.GRID_W * CELL

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		mouse_pos = e.position
		hover = _cell_at(e.position)
		if previewing:
			if _in_timeline(e.position):
				var frac: float = clampf((e.position.x - ORIGIN.x) / (K.GRID_W * CELL), 0.0, 1.0)
				_set_preview(int(round(frac * K.LOOP_TICKS)))
		return

	if e is InputEventMouseButton:
		mouse_pos = e.position
		debug_clicks.append([e.position.x, e.position.y, e.button_index, e.pressed])
		if debug_clicks.size() > 8:
			debug_clicks.pop_front()
		if phase == P.REPORT and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if _report_click(e.position):
				return
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_selected(-1)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_selected(1)
		elif e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if phase == P.RUN and _end_loop_rect().has_point(e.position):
				_toggle_fast_forward()
				return
			var pi: int = _palette_index_at(e.position)
			if pi >= 0:
				selected = int(PALETTE_TYPES[pi])
				return
			if not previewing:
				_try_place(_cell_at(e.position))
		elif e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and not previewing:
			_try_demolish(_cell_at(e.position))
		return

	if e is InputEventKey:
		if e.keycode == KEY_SHIFT:
			if e.pressed:
				_begin_preview()
			else:
				previewing = false
				pv = null
			return
		if not e.pressed or e.echo:
			return
		if e.keycode == KEY_ENTER and phase == P.RUN:
			_toggle_fast_forward()
			return
		if e.keycode == KEY_SPACE and phase == P.REPORT:
			_after_report()
			return
		match e.keycode:
			KEY_1: selected = K.T_MINER
			KEY_2: selected = K.T_BELT
			KEY_3: selected = K.T_FURNACE
			KEY_4: selected = K.T_GEAR
			KEY_5: selected = K.T_ASSEMBLER
			KEY_6: selected = K.T_SINK
			KEY_Q: place_dir = (place_dir + 3) % 4
			KEY_E: place_dir = (place_dir + 1) % 4
			KEY_SPACE:
				if phase == P.RUN:
					paused = not paused
			KEY_R:
				if phase == P.WIN or phase == P.LOSE:
					_restart()
				elif restart_armed and restart_arm_timer > 0.0:
					_restart()
				else:
					restart_armed = true
					restart_arm_timer = RESTART_CONFIRM_SEC
					toast = "再按一次 R 確認重來（2 秒內）"
					toast_timer = RESTART_CONFIRM_SEC
			KEY_D:
				debug_demo_build()

## 滾輪喺 6 種建築之間循環（唔再轉向）。
func _cycle_selected(step: int) -> void:
	var i: int = PALETTE_TYPES.find(selected)
	if i < 0:
		i = 0
	i = (i + step + PALETTE_TYPES.size()) % PALETTE_TYPES.size()
	selected = int(PALETTE_TYPES[i])

func _begin_preview() -> void:
	if phase != P.RUN:
		return
	previewing = true
	pv = lm.preview_clone()
	_set_preview(lm.world.tick)

func _set_preview(t: int) -> void:
	pv_tick = clampi(t, 0, K.LOOP_TICKS)
	if pv != null:
		pv.preview_at(pv_tick)

# ---------------------------------------------------------------- 建造

func _try_place(cell: Vector2i) -> void:
	if cell == Vector2i(-1, -1) or phase != P.RUN:
		return
	if busy > 0:
		deny[lm.world.idx_of(cell)] = 0.2
		return
	if not lm.can_build(cell, selected):
		deny[lm.world.idx_of(cell)] = 0.3
		return
	if lm.submit_build(cell, selected, place_dir):
		flash[lm.world.idx_of(cell)] = 0.35
		busy = BUILD_TICKS

func _try_demolish(cell: Vector2i) -> void:
	if cell == Vector2i(-1, -1) or phase != P.RUN:
		return
	if busy > 0 or not lm.can_demolish(cell):
		deny[lm.world.idx_of(cell)] = 0.3
		return
	if lm.submit_demolish(cell):
		flash[lm.world.idx_of(cell)] = 0.35
		busy = BUILD_TICKS

func debug_demo_build() -> void:
	debug_build_line(K.ORE_LANES[0])
	debug_build_line(K.ORE_LANES[1])

## 一條完整三層產線：礦機 -> 帶帶 -> 爐 -> 帶 -> 齒輪機 -> 帶 -> 組裝台 -> 帶 -> 出口
## 共 10 件建築，60 秒約 15 件零件。
func debug_build_line(y: int) -> int:
	var line := [
		[3, K.T_MINER], [4, K.T_BELT], [5, K.T_BELT], [6, K.T_FURNACE],
		[7, K.T_BELT], [8, K.T_GEAR], [9, K.T_BELT], [10, K.T_ASSEMBLER],
		[11, K.T_BELT], [12, K.T_SINK],
	]
	var ok := 0
	for item in line:
		if lm.submit_build(Vector2i(item[0], y), item[1], K.D_E):
			ok += 1
	return ok

# ---------------------------------------------------------------- 繪圖

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w = pv.world if (previewing and pv != null) else lm.world

	draw_rect(Rect2(ORIGIN - Vector2(6, 6), Vector2(K.GRID_W * CELL + 12, K.GRID_H * CELL + 12)), Color(0.05, 0.07, 0.09))
	if art.has("tiles/ground"):
		draw_texture_rect(art["tiles/ground"], Rect2(ORIGIN, Vector2(K.GRID_W * CELL, K.GRID_H * CELL)), true, Color(1, 1, 1, 0.9))
	draw_rect(Rect2(ORIGIN - Vector2(3, 3), Vector2(K.GRID_W * CELL + 6, K.GRID_H * CELL + 6)), Color(0.22, 0.30, 0.40, 0.9), false, 2.0)
	for i in range(0, K.GRID_W + 1, 3):
		var x := ORIGIN.x + i * CELL
		var y := ORIGIN.y + i * CELL
		draw_line(Vector2(x, ORIGIN.y), Vector2(x, ORIGIN.y + K.GRID_H * CELL), Color(1, 1, 1, 0.04))
		draw_line(Vector2(ORIGIN.x, y), Vector2(ORIGIN.x + K.GRID_W * CELL, y), Color(1, 1, 1, 0.04))

	# 礦脈軌道底色（每條賽道一行）
	for lane in K.ORE_LANES:
		draw_rect(Rect2(Vector2(ORIGIN.x, ORIGIN.y + float(lane) * CELL),
			Vector2(K.GRID_W * CELL, CELL)), Color(0.42, 0.30, 0.16, 0.05))

	# 礦脈
	for idx in w.ore:
		var oc: Vector2i = w.cell_of(idx)
		if art.has("tiles/ore"):
			draw_texture_rect(art["tiles/ore"], Rect2(ORIGIN + Vector2(oc) * CELL, Vector2(CELL, CELL)), false)
		else:
			draw_rect(Rect2(ORIGIN + Vector2(oc) * CELL, Vector2(CELL, CELL)).grow(-1.0), Color(0.42, 0.30, 0.16, 0.85))

	for idx in w.buildings:
		var b = w.buildings[idx]
		var cell: Vector2i = w.cell_of(idx)
		var r := Rect2(ORIGIN + Vector2(cell) * CELL, Vector2(CELL, CELL))
		var key := _tex_key(b, w.tick)
		var ghost: bool = b.origin < lm.loop_index
		var mod := Color(1, 1, 1, 0.55) if ghost else Color(1, 1, 1, 1)
		# 落地陰影，令建築唔會「浮」喺地面
		draw_rect(Rect2(r.position + Vector2(1.5, 2.0), r.size), Color(0, 0, 0, 0.22))
		if art.has(key):
			draw_texture_rect(art[key], r, false, mod)
		else:
			var col := _color_for(b.type)
			col.a = mod.a
			draw_rect(r, col)
		if flash.has(idx) and not previewing:
			draw_rect(r.grow(1.0), Color(1, 1, 1, float(flash[idx])))
		if deny.has(idx) and not previewing:
			draw_rect(r.grow(1.0), Color(1, 0.3, 0.3, float(deny[idx])))
		if b.has_out:
			var ikey := _item_tex(b.item)
			if art.has(ikey):
				draw_texture_rect(art[ikey], Rect2(r.get_center() - Vector2(8, 8), Vector2(16, 16)), false, mod)
			else:
				draw_circle(r.get_center(), 4.6, _item_color(b.item))
		if b.type == K.T_FURNACE:
			var frac := clampf(float(b.progress) / float(K.SMELT_TICKS), 0.0, 1.0)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x * frac, 3)), Color(1, 1, 1, 0.35))
		if b.type != K.T_BELT:
			_draw_arrow(b, r, mod)

	# 幽靈位置（佢而家做緊邊一步）
	var look_t: int = pv_tick if previewing else lm.world.tick
	for li in lm.active:
		var gp := _ghost_pos(li, look_t)
		if gp == Vector2i(-1, -1):
			continue
		var p := ORIGIN + Vector2(gp) * CELL + Vector2(CELL, CELL) * 0.5
		draw_circle(p, 8.0, Color(0.55, 0.75, 1.0, 0.22))
		draw_circle(p, 3.4, Color(0.78, 0.92, 1.0, 0.9))

	if not previewing:
		_draw_hover()
	_draw_timeline(font)
	_draw_hud(font)

	if previewing:
		draw_rect(Rect2(ORIGIN - Vector2(6, 6), Vector2(K.GRID_W * CELL + 12, K.GRID_H * CELL + 12)), Color(0.35, 0.6, 1.0, 0.06))
		draw_string(font, Vector2(ORIGIN.x, ORIGIN.y - 12), "預演 PREVIEW  t = %.1fs / %.0fs" % [float(pv_tick) / K.SIM_HZ, float(K.LOOP_TICKS) / K.SIM_HZ], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.85, 1.0))
	if toast_timer > 0.0 and toast != "":
		var a: float = clampf(toast_timer / 0.6, 0.0, 1.0)
		var tw: float = font.get_string_size(toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var tp := Vector2(ORIGIN.x + (K.GRID_W * CELL - tw) * 0.5, ORIGIN.y + 46.0)
		draw_rect(Rect2(tp + Vector2(-10, -16), Vector2(tw + 20, 24)), Color(0.05, 0.08, 0.12, 0.85 * a))
		draw_string(font, tp, toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.95, 0.75, a))
	if phase == P.REPORT:
		_draw_report(font)
	if phase == P.WIN or phase == P.LOSE:
		_draw_end(font)

func _ghost_pos(li: int, t: int) -> Vector2i:
	if li >= lm.ghosts.size():
		return Vector2i(-1, -1)
	var log: Array = lm.ghosts[li]
	var found := Vector2i(-1, -1)
	for cmd in log:
		if int(cmd["t"]) > t:
			break
		found = Vector2i(int(cmd["x"]), int(cmd["y"]))
	return found

func _draw_palette(font: Font) -> void:
	var names := {
		K.T_MINER: "礦機", K.T_BELT: "傳送帶", K.T_FURNACE: "合成爐",
		K.T_GEAR: "齒輪機", K.T_ASSEMBLER: "組裝台", K.T_SINK: "出口",
	}
	var hi: int = _palette_index_at(mouse_pos)
	for i in range(PALETTE_TYPES.size()):
		var t: int = int(PALETTE_TYPES[i])
		var r := _palette_rect(i)
		var is_sel: bool = (t == selected)
		var is_hi: bool = (i == hi)
		var bg := Color(0.18, 0.24, 0.30)
		if is_sel:
			bg = Color(0.28, 0.45, 0.62)
		elif is_hi:
			bg = Color(0.23, 0.31, 0.40)
		draw_rect(r, bg)
		var border := Color(1, 1, 1, 0.2)
		if is_sel:
			border = Color(0.6, 0.85, 1.0)
		elif is_hi:
			border = Color(0.75, 0.9, 1.0, 0.65)
		draw_rect(r, border, false, 1.0)
		var skey := _slot_tex(t)
		if art.has(skey):
			draw_texture_rect(art[skey], Rect2(r.position + Vector2(4, 6), Vector2(20, 20)), false)
		else:
			draw_rect(Rect2(r.position + Vector2(5, 7), Vector2(14, 14)), _color_for(t))
		draw_string(font, Vector2(r.position.x + 26, r.position.y + 22), names[t], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.92))
		draw_string(font, Vector2(r.position.x + 6, r.position.y + 46), "[%d]" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.45))

func _draw_hover() -> void:
	if hover == Vector2i(-1, -1) or phase != P.RUN:
		return
	var r := Rect2(ORIGIN + Vector2(hover) * CELL, Vector2(CELL, CELL)).grow(-1.2)
	var ok: bool = lm.can_build(hover, selected) and busy <= 0
	draw_rect(r, Color(0.4, 1.0, 0.5, 0.22) if ok else Color(1, 0.35, 0.35, 0.22))
	draw_rect(r, Color(0.5, 1.0, 0.6, 0.8) if ok else Color(1, 0.4, 0.4, 0.8), false, 1.0)
	# 放落去嘅方向提示
	var c := r.get_center()
	var d: Vector2 = K.DIR_VEC[place_dir]
	draw_line(c, c + d * (CELL * 0.42), Color(1, 1, 1, 0.55), 1.2)

	# 呢格有嘢 -> 講清楚右鍵拆嘅淨成本
	if lm.world.building_at(hover) != null:
		var net: int = lm.demolish_net_cost(hover)
		var txt := "拆：退 1 AP" if net == 0 else "拆：−%d AP" % net
		var col2 := Color(0.6, 1.0, 0.7) if net == 0 else Color(1, 0.65, 0.55)
		draw_string(ThemeDB.fallback_font, Vector2(r.position.x - 6, r.position.y - 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col2)

func _report_row_rect(i: int) -> Rect2:
	return Rect2(Vector2(REPORT_X + 10.0, REPORT_Y + REPORT_ROWS_Y + float(i) * REPORT_ROW_H),
		Vector2(REPORT_W - 20.0, REPORT_ROW_H))

func _report_rows_y() -> float:
	return REPORT_Y + REPORT_ROWS_Y + float(maxi(lm.ghosts.size(), 1)) * REPORT_ROW_H + 12.0

func _report_start_rect() -> Rect2:
	return Rect2(Vector2(REPORT_X + 10.0, _report_rows_y()), Vector2(REPORT_W - 20.0, 34.0))

func _report_row_at(pos: Vector2) -> int:
	for li in range(lm.ghosts.size()):
		if _report_row_rect(li).has_point(pos):
			return li
	return -1

## 結算畫面嘅滑鼠處理；有消費到事件就 return true
func _report_click(pos: Vector2) -> bool:
	if _report_start_rect().has_point(pos):
		_after_report()
		return true
	var li: int = _report_row_at(pos)
	if li >= 0:
		# 用「下一個 loop」嘅上限，避免報告時揀多咗、開始時又被剪
		lm.toggle_ghost(li, lm.ghost_quota_for(lm.loop_index + 1))
		return true
	return false

## 「提早結束」按鈕（HUD 左下角，選單下面）
func _end_loop_rect() -> Rect2:
	var w: float = float(PALETTE_COLS) * PALETTE_BTN.x + float(PALETTE_COLS - 1) * PALETTE_GAP
	var y: float = PALETTE_Y + 2.0 * (PALETTE_BTN.y + PALETTE_GAP) + 10.0
	return Rect2(Vector2(PANEL_X, y), Vector2(w, 36))

## 快進到 loop 結束：同樣嘅模擬、同樣嘅產量，只係唔使眼白白等。
## （真·提早結束會丟掉九成產量，所以唔做預設；見 DESIGN-SPEC 6.7）
func _toggle_fast_forward() -> void:
	if phase != P.RUN:
		return
	fast_forward = not fast_forward
	paused = false

## AP 回復倒數（滿咗或者冇開回復就空字串）
func _regen_text() -> String:
	var t: int = lm.ticks_to_next_ap()
	if t < 0:
		return ""
	if t == 0:
		return "  +1"
	return "  +1 於 %.1fs" % (float(t) / float(K.SIM_HZ))

func _quota_text() -> String:
	var q: int = lm.ghost_quota()
	return "∞" if q >= lm.UNLIMITED_QUOTA else str(q)

func _palette_rect(i: int) -> Rect2:
	@warning_ignore("integer_division")
	var row: int = i / PALETTE_COLS
	var col: int = i % PALETTE_COLS
	return Rect2(
		Vector2(PANEL_X + float(col) * (PALETTE_BTN.x + PALETTE_GAP),
			PALETTE_Y + float(row) * (PALETTE_BTN.y + PALETTE_GAP)),
		PALETTE_BTN)

## 滑鼠喺邊個建築按鈕上面（-1 = 唔係）
func _palette_index_at(pos: Vector2) -> int:
	for i in range(PALETTE_TYPES.size()):
		if _palette_rect(i).has_point(pos):
			return i
	return -1

func _draw_timeline(font: Font) -> void:
	var x0 := ORIGIN.x
	var wpx := K.GRID_W * CELL
	draw_rect(Rect2(Vector2(x0, TL_Y), Vector2(wpx, TL_H)), Color(1, 1, 1, 0.06))
	# 幽靈命令位置（睇得到邊個幽靈幾時落手）
	for li in lm.active:
		var log: Array = lm.ghosts[li]
		for cmd in log:
			var fx: float = float(int(cmd["t"])) / float(K.LOOP_TICKS) * wpx
			var c := Color(0.55, 0.75, 1.0, 0.45) if li % 2 == 0 else Color(0.75, 0.85, 1.0, 0.45)
			draw_line(Vector2(x0 + fx, TL_Y + 2), Vector2(x0 + fx, TL_Y + TL_H - 2), c, 1.0)
	# 已過時間
	var cur: int = pv_tick if previewing else lm.world.tick
	var frac := float(cur) / float(K.LOOP_TICKS)
	draw_rect(Rect2(Vector2(x0, TL_Y), Vector2(wpx * frac, TL_H)), Color(0.35, 0.65, 0.95, 0.25))
	draw_line(Vector2(x0 + wpx * frac, TL_Y - 3), Vector2(x0 + wpx * frac, TL_Y + TL_H + 3), Color(0.7, 0.9, 1.0), 2.0)
	draw_string(font, Vector2(x0 + wpx - 4, TL_Y + 14), "%.0fs" % (float(K.LOOP_TICKS) / K.SIM_HZ), HORIZONTAL_ALIGNMENT_RIGHT, -1, 11, Color(1, 1, 1, 0.35))

func _draw_hud(font: Font) -> void:
	var x := PANEL_X
	var y := 44.0
	var left := int(lm.world.tick if not previewing else pv_tick)
	var remain := (K.LOOP_TICKS - left) / float(K.SIM_HZ)
	# 預演時 HUD 必須顯示「預演世界」嘅數字，唔係真實世界（否則預覽係假嘅）
	var shown = pv.world if (previewing and pv != null) else lm.world
	var lines: Array = [
		["TIME LOOP AUTOMATION", 20, Color(0.85, 0.9, 1.0)],
		["", 10, Color.WHITE],
		["LOOP %d / %d%s%s" % [lm.loop_index + 1, K.LOOP_LIMIT, "  (預演)" if previewing else "", "   ⏩%dx" % int(ff_mult) if fast_forward else ""], 21, Color(1, 1, 1)],
		["剩餘 %.1fs" % remain, 18, Color(0.8, 0.85, 0.95)],
		["交貨 %d / %d" % [shown.delivered, K.WIN_TARGET], 18, Color(1, 0.9, 0.6) if shown.delivered < K.WIN_TARGET else Color(0.5, 1, 0.6)],
		["AP %d / %d%s%s" % [lm.ap_available(), K.AP_MAX, _regen_text(), "  (建造中)" if busy > 0 else ""], 18, Color(0.8, 0.85, 0.95)],
		["幽靈 %d / 上限 %s" % [lm.active.size(), _quota_text()], 18, Color(0.6, 0.8, 1.0)],
		["", 10, Color.WHITE],
		["[1]礦 [2]帶 [3]爐 [4]齒 [5]組 [6]出口", 14, Color(1, 1, 1, 0.55)],
		["點選單或用 1–6 選建築", 15, Color(1, 1, 1, 0.55)],
		["滾輪切換建築   [Q/E] 轉向", 15, Color(1, 1, 1, 0.55)],
		["左鍵放  右鍵拆", 15, Color(1, 1, 1, 0.55)],
		["[SHIFT] 預演  [SPACE] 暫停  [ENTER] 快進  [R] 重來×2", 13, Color(1, 1, 1, 0.55)],
		["拆自己會退 AP；拆幽靈要 2 AP", 13, Color(1, 1, 1, 0.4)],
		["按住 SHIFT 拖下面時間軸 = 預演", 13, Color(1, 1, 1, 0.4)],
	]
	for line in lines:
		var txt: String = line[0]
		if txt == "":
			y += 8
			continue
		draw_string(font, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(line[1]), line[2])
		y += int(line[1]) + 8

	if phase != P.RUN:
		return
	_draw_end_loop_button(font)
	_draw_palette(font)

func _draw_end_loop_button(font: Font) -> void:
	var eb := _end_loop_rect()
	var e_hover: bool = eb.has_point(mouse_pos)
	var ap_zero: bool = lm.ap_available() <= 0
	var bg := Color(0.16, 0.22, 0.28)
	if e_hover:
		bg = Color(0.24, 0.33, 0.40)
	if ap_zero:
		bg = Color(0.30, 0.26, 0.16) if not e_hover else Color(0.42, 0.36, 0.20)
	if fast_forward:
		bg = Color(0.18, 0.34, 0.24)
	draw_rect(eb, bg)
	var border := Color(1, 1, 1, 0.28)
	if ap_zero and not fast_forward:
		border = Color(0.85, 0.72, 0.35, 0.9)
	draw_rect(eb, border, false, 1.0)
	var label := "⏩ 快進至 loop 結束"
	if fast_forward:
		label = "⏩ 快進中 %dx（再按取消）" % int(ff_mult)
	elif ap_zero:
		label = "⏩ AP 用晒 — 快進至結束"
	draw_string(font, eb.position + Vector2(14, 26), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.95, 0.8) if (ap_zero or fast_forward) else Color(1, 1, 1, 0.85))
	draw_string(font, eb.position + Vector2(eb.size.x - 60.0, 23), "[ENTER]",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))

func _draw_report(font: Font) -> void:
	var start_btn := _report_start_rect()
	var panel := Rect2(Vector2(REPORT_X - 8.0, REPORT_Y - 10.0),
		Vector2(REPORT_W + 16.0, start_btn.end.y - REPORT_Y + 26.0))
	draw_rect(panel, Color(0.04, 0.06, 0.09, 0.96))
	draw_rect(panel, Color(0.45, 0.65, 0.9, 0.6), false, 1.0)

	var next_quota: int = lm.ghost_quota_for(lm.loop_index + 1)
	draw_string(font, Vector2(REPORT_X, REPORT_Y + 18.0),
		"LOOP %d 結算 — 交貨 %d / %d" % [lm.loop_index + 1, int(report.get("delivered", 0)), K.WIN_TARGET],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.95, 0.7))
	draw_string(font, Vector2(REPORT_X, REPORT_Y + 42.0),
		"幽靈 %d / 上限 %s（下個 loop）・AP 剩 %d" % [lm.active.size(), ("∞" if lm.ghost_cap <= 0 else str(next_quota)), lm.ap_left()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 1.0))
	draw_string(font, Vector2(REPORT_X, REPORT_Y + 62.0),
		"點擊幽靈切換出動 — 下個 loop 生效", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))

	# 用即時狀態（seal_loop 喺結算之後才加新幽靈，所以要即時計）
	var gs: Array = lm.ghost_report()
	if gs.is_empty():
		draw_string(font, Vector2(REPORT_X + 10.0, REPORT_Y + REPORT_ROWS_Y + 14.0),
			"未有幽靈（呢個 loop 你一個人做）", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
	for li in range(gs.size()):
		var info: Dictionary = gs[li]
		var r := _report_row_rect(li)
		var on: bool = lm.active.has(li)
		var hovered: bool = r.has_point(mouse_pos) and not _report_start_rect().has_point(mouse_pos)
		if on:
			draw_rect(r, Color(0.16, 0.30, 0.40) if not hovered else Color(0.20, 0.38, 0.50))
		elif hovered:
			draw_rect(r, Color(1, 1, 1, 0.06))
		var box := Rect2(r.position + Vector2(6, 4), Vector2(13, 13))
		draw_rect(box, Color(0.35, 0.75, 0.50) if on else Color(1, 1, 1, 0.10))
		if on:
			draw_line(box.position + Vector2(3, 7), box.position + Vector2(6, 10), Color(1, 1, 1, 0.9), 1.6)
			draw_line(box.position + Vector2(6, 10), box.position + Vector2(10, 4), Color(1, 1, 1, 0.9), 1.6)
		var state := "出動" if on else "待命"
		var col := Color(0.8, 0.95, 1.0) if on else Color(1, 1, 1, 0.4)
		draw_string(font, r.position + Vector2(28, 15),
			"#%d  %d 次操作  剩 %d 件  %s" % [li + 1, int(info["actions"]), int(info["standing"]), state],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

	var sb := _report_start_rect()
	var s_hover: bool = sb.has_point(mouse_pos)
	draw_rect(sb, Color(0.20, 0.42, 0.32) if not s_hover else Color(0.26, 0.52, 0.40))
	draw_rect(sb, Color(0.5, 1.0, 0.7, 0.8), false, 1.0)
	draw_string(font, sb.position + Vector2(12, 22),
		"▶ 開始 LOOP %d（%d 個幽靈出動）" % [lm.loop_index + 2, lm.active.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 1.0, 0.9))
	draw_string(font, sb.position + Vector2(sb.size.x - 96.0, 22),
		"[SPACE]", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 1.0, 0.9, 0.6))

func _draw_end(font: Font) -> void:
	var r := Rect2(Vector2(ORIGIN.x + 60, 190), Vector2(400, 150))
	draw_rect(r, Color(0.03, 0.05, 0.08, 0.96))
	draw_rect(r, Color(0.5, 0.7, 0.9, 0.7), false, 1.0)
	if phase == P.WIN:
		draw_string(font, r.position + Vector2(16, 42), "達標！", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.55, 1.0, 0.65))
		draw_string(font, r.position + Vector2(16, 76), "用咗 %d / %d 個 loop，合共交貨 %d" % [loops_used, K.LOOP_LIMIT, total_delivered], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))
	else:
		draw_string(font, r.position + Vector2(16, 42), "時間用完", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.6, 0.55))
		draw_string(font, r.position + Vector2(16, 76), "%d 個 loop 內差 %d 件（最後一輪交貨 %d）" % [K.LOOP_LIMIT, K.WIN_TARGET - lm.world.delivered, last_loop_delivered], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))
	draw_string(font, r.position + Vector2(16, 112), "[R] 重來", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.9, 1.0))

## 用邊張貼圖（含動畫格）
func _tex_key(b, tick: int) -> String:
	match b.type:
		K.T_MINER: return "buildings/miner"
		K.T_FURNACE: return "buildings/furnace_" + ("a" if (tick / 8) % 2 == 0 else "b")
		K.T_GEAR: return "buildings/gear"
		K.T_ASSEMBLER: return "buildings/assembler"
		K.T_SINK: return "buildings/sink"
		K.T_BELT:
			var dirs := ["n", "e", "s", "w"]
			var frame := "a" if (tick / 6) % 2 == 0 else "b"
			return "buildings/belt_%s_%s" % [dirs[b.dir], frame]
	return ""

## 選單用嘅貼圖（傳送帶用向東嘅第一格）
func _slot_tex(t: int) -> String:
	match t:
		K.T_MINER: return "buildings/miner"
		K.T_BELT: return "buildings/belt_e_a"
		K.T_FURNACE: return "buildings/furnace_a"
		K.T_GEAR: return "buildings/gear"
		K.T_ASSEMBLER: return "buildings/assembler"
		K.T_SINK: return "buildings/sink"
	return ""

func _item_tex(item: int) -> String:
	match item:
		K.ITEM_ORE: return "items/ore"
		K.ITEM_INGOT: return "items/ingot"
		K.ITEM_GEAR: return "items/gear"
		K.ITEM_PART: return "items/part"
	return ""

func _color_for(t: int) -> Color:
	match t:
		K.T_MINER:     return Color(0.85, 0.55, 0.25)
		K.T_BELT:      return Color(0.35, 0.42, 0.52)
		K.T_FURNACE:   return Color(0.75, 0.30, 0.30)
		K.T_GEAR:      return Color(0.80, 0.72, 0.25)
		K.T_ASSEMBLER: return Color(0.55, 0.38, 0.72)
		K.T_SINK:      return Color(0.30, 0.75, 0.45)
	return Color(0.5, 0.5, 0.5)

func _item_color(item: int) -> Color:
	match item:
		K.ITEM_ORE:   return Color(1.0, 0.62, 0.25)
		K.ITEM_INGOT: return Color(0.45, 0.9, 1.0)
		K.ITEM_GEAR:  return Color(0.95, 0.88, 0.35)
		K.ITEM_PART:  return Color(0.55, 1.0, 0.65)
	return Color.WHITE

func _draw_arrow(b, r: Rect2, mod: Color = Color.WHITE) -> void:
	var c := r.get_center()
	var d: Vector2 = K.DIR_VEC[b.dir]
	var tip := c + d * (CELL * 0.26)
	var l := Vector2(-d.y, d.x) * (CELL * 0.12)
	var ac := Color(1, 1, 1, 0.45 * mod.a)
	draw_line(c - d * 2.0, tip, ac, 1.2)
	draw_line(tip, tip - d * 3.5 + l, ac, 1.2)
	draw_line(tip, tip - d * 3.5 - l, ac, 1.2)