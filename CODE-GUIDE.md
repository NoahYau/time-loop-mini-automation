# 程式碼導覽（Code Guide）

> 對象：想自己改數值／規則／UI 嘅開發者。
> 只講 **`game/`** 入面嘅遊戲程式；`game/autoload/mcp_interaction_server.gd` 係開發工具（見 §8），唔關玩法事。
> 改完記得跑測試：`res://tests/test_determinism.gd`（T1–T16 要全綠）。

---

## 0. 先理解呢三件事

### 0.1 一個 tick 發生咩事

```
玩家輸入（_unhandled_input）
   └─ LoopManager.submit_build / submit_rotate / submit_demolish
         └─ 產生一條命令 {t: 下一個 tick, k: 種類, x, y, type, dir}，放入 current_log

每個 tick（_process 累積 1/30 秒 → LoopManager.step()）
   ├─ 到 300 tick 就為每個 AP key +1（上限 AP_MAX）
   ├─ 每個出動嘅幽靈：_apply_until() → 逐條 _apply()（照佢當年嘅 log）
   ├─ 玩家：_apply_until() → 逐條 _apply()（今個 loop 嘅 log）
   └─ SimWorld.step()：_produce()（機器生產）→ _transport()（貨物移動）

畫面上每一 frame：_draw() 讀住世界現狀重畫（唔會改世界）
```

### 0.2 五個一定要知嘅概念

| 概念 | 意思 | 喺邊 |
|---|---|---|
| **tick** | 模擬時間單位，30 tick = 1 秒；一個 loop = 1800 tick | `constants.gd` `SIM_HZ` / `LOOP_TICKS` |
| **命令（command）** | 改世界嘅**唯一**方法：`{t, k, x, y, type, dir}`。冇「直接改格」呢回事 | `loop_manager.submit_*` / `_apply` |
| **origin** | 呢格建築由第幾個 loop 建成。`origin < loop_index` = 幽靈舊建築；`origin == loop_index` = 你今個 loop 起 | `building.gd` |
| **AP** | 行動點，只係 `LoopManager` 嘅記帳，**唔屬於世界**；幽靈重播時都會扣佢自己嗰份 AP | `loop_manager.ap_left()` |
| **確定性** | 冇隨機、冇浮點累加、冇物理、遍歷次序固定 → 同一 log 重播逐 tick 一樣 | `sim_world.digest()` 驗證 |

### 0.3 資料流（一句）

```
輸入 → LoopManager（排命令）→ _apply（唯一入口，檢查 AP/佔格）→ SimWorld（建築＋貨物）
     → UI（_draw 讀世界；結算讀 ghost_report）
```

---

## 1. 檔案地圖

| 檔案 | 角色 | 有冇 Node？ |
|---|---|---|
| `game/sim/constants.gd` | 全部平衡數字、枚舉、type id | 冇 |
| `game/sim/building.gd` | 一格建築嘅資料（20 行） | 冇 |
| `game/sim/sim_world.gd` | 世界：建築、生產、運輸、存檔、指紋 | 冇 |
| `game/sim/loop_manager.gd` | 時間循環、幽靈 log、AP、預演、結算統計 | 冇 |
| `game/scenes/sandbox.gd` | 可玩切片：輸入、繪製、UI、流程 | Node2D（主場景） |
| `game/scenes/sandbox.tscn` | 只有一個 Node，掛住 sandbox.gd | — |
| `game/tests/test_determinism.gd` | T1–T16 驗收（SceneTree script） | 冇 |
| `game/tests/bench_step.gd` / `bench_regen.gd` | 產能／回復速度基準 | 冇 |
| `game/autoload/mcp_interaction_server.gd` | godot-bridge 開發工具 | Autoload |

---

## 2. `game/sim/constants.gd` — 所有平衡數字

改難度／節奏，九成只改呢個檔。**改完要重跑測試**（T9 曲線、T3/T15 AP 測試會受影響）。

### 2.1 模擬核心

| 常數 | 值 | 意思／改動影響 |
|---|---|---|
| `GRID_W` / `GRID_H` | 16 | 棋盤闊高（格）。改咗要改 UI 版面（`CELL`、`ORIGIN`、視窗） |
| `SIM_HZ` | 30 | 每秒幾個 sim tick |
| `LOOP_TICKS` | 1800 | 一個 loop 幾多 tick（60 秒）。改咗時間軸、快進、AI 都會自動跟 |

### 2.2 配方（三層）

| 常數 | 值 | 意思 |
|---|---|---|
| `MINER_TICKS` | 15 | 礦機每 15 tick 出 1 礦 |
| `SMELT_TICKS` / `SMELT_IN` / `SMELT_CAP` | 30 / 2 / 4 | 爐：2 礦 → 1 錠，每 30 tick；入料上限 4 |
| `GEAR_TICKS` / `GEAR_IN` / `GEAR_CAP` | 20 / 1 / 4 | 齒輪機：1 錠 → 1 齒輪 |
| `ASSEMBLE_TICKS` / `ASSEMBLE_IN` / `ASSEMBLE_CAP` | 80 / 4 / 8 | 組裝台：4 齒輪 → 1 零件 |

> 呢啲數字只係「原料」；真正點用係 `sim_world.recipe_*()` 同 `_produce()`。

### 2.3 建築 type / 方向 / 物品

| 常數 | 值 | 意思 |
|---|---|---|
| `T_NONE` … `T_SINK` | 0–6 | 空地 / 礦機 / 帶 / 爐 / 齒輪機 / 組裝台 / 出口 |
| `D_N` / `D_E` / `D_S` / `D_W` | 0–3 | 方向；`DIR_VEC` 係對應 `Vector2i` |
| `ITEM_ORE` / `ITEM_INGOT` / `ITEM_GEAR` / `ITEM_PART` | 0–3 | 貨物種類 |

### 2.4 礦脈（B 規則）

| 常數 | 值 | 意思 |
|---|---|---|
| `ORE_X` | 3 | 礦脈喺邊一欄 |
| `ORE_LANES` | `[2, 5, 8, 11, 14]` | 5 條礦脈嘅 y 座標；礦機只可以擺喺 `(3, lane)` |

### 2.5 幽靈

| 常數 | 值 | 意思 |
|---|---|---|
| `GHOST_CAP` | 0 | 0 = 唔封頂；> 0 = 關卡自訂上限 |
| `GHOST_SLACK` | 2 | ⚠️ **目前冇用**（`loop_manager.gd` 自己有一份同名常數）。可以刪 |

### 2.6 循環 / AP / 建造

| 常數 | 值 | 意思 |
|---|---|---|
| `LOOP_LIMIT` | 8 | 最多幾個 loop（`start_level()` 可以覆寫） |
| `AP_MAX` | 12 | AP 上限 |
| `AP_COST_BUILD` | 1 | 起一件建築 |
| `AP_COST_DEMOLISH_OWN` | 1 | 拆自己嘅（但會退 1，淨 0） |
| `AP_COST_DEMOLISH_GHOST` | 2 | 拆幽靈嘅（冇退） |
| `AP_COST_ROTATE_GHOST` | 1 | 轉幽靈建築方向（**今次由 2 改 1**） |
| `AP_REFUND_DEMOLISH_OWN` | 1 | 拆自己退幾多 |
| `BUILD_TICKS` | 15 | 一次建造／旋轉佔用 0.5 秒 |
| `AP_REGEN_TICKS` | 300 | 每 10 秒回 1 AP |
| `AP_REGEN_AMOUNT` | 1 | 每次回幾多 |
| `WIN_TARGET` | 48 | 達標交貨數 |

### 2.7 命令種類

`C_BUILD` = 0（起）、`C_DEMOLISH` = 1（拆）、`C_ROTATE` = 2（轉）。

---

## 3. `game/sim/building.gd` — 一格建築

只有資料，冇 Node、冇 signal。**重播零漂移嘅前提**。

| 欄位 | 意思 |
|---|---|
| `type` | `T_*` |
| `dir` | `D_*`（帶／機／出口嘅輸出方向） |
| `progress` | 生產進度（tick 數） |
| `in_count` | 機器已入料數量 |
| `has_out` | 有冇一件貨等住送出 |
| `item` | 等住送出嘅貨物種類 |
| `origin` | 邊個 loop 起（拆遷退款／轉向收費靠佢） |
| `copy()` | 深拷貝（`save_state` / 預演 checkpoint 用） |

---

## 4. `game/sim/sim_world.gd` — 世界

### 4.1 配方查詢（全部係 `match type` 嘅開關）

| 函數 | 回傳 |
|---|---|
| `recipe_in_type(t)` | 呢部機食邊種貨（礦／錠／齒輪；唔食回 -1） |
| `recipe_in_count(t)` | 一次食幾多 |
| `recipe_ticks(t)` | 生產一件要幾多 tick |
| `recipe_in_cap(t)` | 入料上限 |
| `recipe_out_type(t)` | 出咩貨 |
| `is_machine(t)` | 係咪爐／齒輪機／組裝台 |

> 想加第四層（例如零件 → 引擎），呢六個 function + `_produce()` + `_transport()` 一齊改。

### 4.2 基本操作

| 函數 | 做的事 |
|---|---|
| `clear()` | 清空世界、歸零計數、重新生成礦脈。**每次開 loop 都會叫** |
| `_generate_ore()` | 按 `ORE_X` / `ORE_LANES` 填 `ore` 字典（固定，冇隨機） |
| `is_ore_cell(cell)` | 呢格係咪礦脈 |
| `can_place(cell, type)` | 可唔可以放：喺地圖內、格係空、礦機要喺礦脈 |
| `idx_of(cell)` | 座標 → 一維索引（`y * GRID_W + x`）。**所有內部資料用 idx 做 key** |
| `cell_of(idx)` | 索引 → 座標 |
| `in_bounds(cell)` | 喺地圖內？ |
| `build(idx, type, dir, origin)` | 直接寫一格（只准 `_apply()` 叫） |
| `demolish(idx)` | 直接刪一格 |
| `building_at(cell)` | 攞嗰格嘅 `Building`（冇就 null） |

### 4.3 每個 tick

| 函數 | 做的事 |
|---|---|
| `step()` | `tick += 1` → `_produce()` → `_transport()` |
| `_produce()` | 由細 idx 到大 idx 掃：礦機計時出礦；機器夠料就生產、出貨；`parts_made` 計數 |
| `_transport()` | 兩階段：先收集所有「想移動」→ 用 `claimed` 防止兩件貨撞同一格 → 再統一提交。帶只可以放去帶／空；機器只可以經帶入料（B 規則：機→機要經帶）；出口只收零件 |
| `_neighbor(idx, dir)` | 隔籬格嘅 idx（出界回 -1） |

### 4.4 存檔 / 指紋

| 函數 | 做的事 |
|---|---|
| `save_state()` | 整份世界 → Dictionary（tick、計數、每格 `Building.copy()`）。預演 checkpoint 用 |
| `load_state(d)` | 由 Dictionary 還原世界 |
| `digest()` | 逐格逐欄位計 hash（固定次序）。測試用嚟逐 tick 對比 live／重播／預演 |
| `_mix(h, v)` | hash 混合函數（FNV 風格） |

> **加新狀態（新欄位／新計數）一定要同時改：`clear()`、`save_state()`、`load_state()`、`digest()`**，
> 否則預演拖時間軸會唔一致。

---

## 5. `game/sim/loop_manager.gd` — 循環、幽靈、AP、預演

### 5.1 生命週期

| 函數 | 做的事 |
|---|---|
| `_init()` | 建 `SimWorld` |
| `start_level(limit)` | 全新關卡：清 ghosts／active、`loop_index = 0`、`begin_loop(0)` |
| `begin_loop(n)` | 開第 n 個 loop：清世界／tick／log；重置每個 AP key；清預演 checkpoint；修剪出動名單 |
| `seal_loop()` | 入 loop 結束：把 `current_log` 深拷貝入 `ghosts`；非空 log 且有名額就自動加入出動名單 |

> `_pkey = n`：玩家嘅 AP key 就係 loop 編號，所以幽靈同玩家各自有一份 AP。

### 5.2 幽靈名額 / 換人

| 函數 | 做的事 |
|---|---|
| `ghost_quota_for(li)` | 第 li 個 loop 嘅上限：`ghost_cap == 0` → 無限（99）；否則 `min(ghost_cap, loop_limit - li + GHOST_SLACK)` |
| `is_quota_unlimited()` | 係咪無限 |
| `ghost_quota()` | 今個 loop 嘅上限 |
| `_trim_active()` | 名單只保留有 log 嘅，按 loop 排序，超出上限就踢最舊（`pop_front`） |
| `is_ghost_active(li)` | 呢個幽靈今個 loop 有冇出動 |
| `ghost_has_work(li)` | 呢個幽靈有冇 log（空 loop 唔算） |
| `toggle_ghost(li, quota_override=-1)` | 手動開／關一個幽靈；`quota_override` 用嚟喺結算畫面用「下一個 loop」嘅上限 |
| `add_ghost(log)` | 直接加一段 log（測試同 debug 用） |

### 5.3 AP

| 函數 | 做的事 |
|---|---|
| `ap_left(li=-1)` | 某 AP key 剩幾多（-1 = 玩家） |
| `_pending_ap()` | **已排隊但未執行**嘅命令會用幾多 AP（令連環點擊唔會超支；轉向會即時查嗰格係咪幽靈） |
| `ap_available()` | `ap_left - _pending_ap`，即「而家真係可以再用幾多」 |
| `ticks_to_next_ap()` | 距離下次回復幾多 tick（-1 = 已滿） |

### 5.4 查詢 + 提交

| 函數 | 做的事 |
|---|---|
| `can_build(cell, type)` | 可以放（佔格）＋ AP 夠唔夠 |
| `demolish_net_cost(cell)` | 拆呢格嘅**淨** AP（自己 0、幽靈 2） |
| `can_demolish(cell)` / `demolish_cost(cell)` | 同上嘅查詢版本（`demolish_cost` 係舊版顯示用，而家 UI 用 `demolish_net_cost`；測試 T4 仲有 call） |
| `submit_build(...)` | 排一條 `C_BUILD`（`t = world.tick + 1`） |
| `rotate_cost(cell)` | 轉呢格嘅 AP（自己 0、幽靈 `AP_COST_ROTATE_GHOST`＝**1**） |
| `can_rotate(cell)` | 有建築 ＋ AP 夠 |
| `submit_rotate(cell, dir)` | 排一條 `C_ROTATE` |
| `submit_demolish(cell)` | 排一條 `C_DEMOLISH` |

### 5.5 tick 同命令執行

| 函數 | 做的事 |
|---|---|
| `step()` | 一次 sim tick：① AP 回復（`nt % AP_REGEN_TICKS == 0`）② 每個出動幽靈 `_apply_until` ③ 玩家 `_apply_until` ④ `world.step()` |
| `_apply_until(ap_key, log, upto, ap_slot, origin_loop)` | 由 `_cursor` 開始，逐條執行 `t <= upto` 嘅命令 |
| `_apply(cmd, ap_slot, origin_loop)` | **唯一**改世界嘅入口：檢查佔格／AP → build/rotate/demolish；玩家被拒就寫入 `rejected`（UI 紅閃） |

> `step()` 嘅次序**固定**：舊幽靈 → 新幽靈 → 玩家。同 tick 撞格時幽靈贏，就係靠呢個次序。

### 5.6 預演（時間軸 scrub）

| 函數 | 做的事 |
|---|---|
| `preview_clone()` | 整一個「預演用」manager：把玩家今個 loop 嘅 log 當成最後一個幽靈，由 tick 0 開始重跑 |
| `preview_at(target)` | 推進到第 target tick；往後拖就用最近 checkpoint 還原再跑 |
| `_restore_mark(target)` | 還原最近一個 `tick % PV_MARK_EVERY == 0` 嘅 checkpoint |
| `_reset_cursors_to(t)` | 還原後把每條 log 嘅 cursor 移返去 t 之前 |
| `_active_reset_preview()` | 清 checkpoint（`begin_loop` 用） |

### 5.7 結算 / 其他

| 函數 | 做的事 |
|---|---|
| `is_won()` | 交貨 ≥ `WIN_TARGET` |
| `is_last_loop()` | 係咪最後一個 loop |
| `ghost_quota_str()` | `"3/99"` 之類（HUD 用） |
| `ghost_report()` | 每個幽靈今個 loop 嘅報告 `{loop, active, actions, standing, lost}` |
| `digest()` | 轉發 `world.digest()` |

---

## 6. `game/scenes/sandbox.gd` — 可玩切片

> 呢個檔同時做：流程控制、輸入、繪製、UI 幾何。想改玩法通常改 `LoopManager`；
> 想改**感覺／版面／顏色**先改呢度。

### 6.1 版面常數（檔頭）

| 常數 | 意思 |
|---|---|
| `CELL` / `ORIGIN` | 每格 40px、棋盤左上角 (20, 44) |
| `TL_Y` / `TL_H` | 時間軸 y 位置／高度 |
| `PANEL_X` | 右邊 HUD 左邊界（700） |
| `PALETTE_Y` / `PALETTE_BTN` / `PALETTE_GAP` / `PALETTE_COLS` | 建築選單位置、按鈕大細、行數 |
| `REPORT_Y` / `REPORT_ROWS_Y` / `REPORT_ROW_H` | 結算面板版面 |
| `GHOST_COLORS` / `GHOST_TRAIL_LEN` | 幽靈 8 色、足跡長度 |
| `RESTART_CONFIRM_SEC` | R 鍵確認秒數 |

### 6.2 初始化

| 函數 | 做的事 |
|---|---|
| `_ready()` | `_load_art()` → 建 `LoopManager` → `start_level()` |
| `_load_art()` | 把 `art/**.png` 全部載入 `art` 字典（key 係路徑去掉 `.png`） |
| `_tex(path)` | 攞貼圖：先試 Godot 匯入系統；未 import 就即場解 PNG（headless 都跑到） |
| `_draw_nine(key, r, m, mod)` | 九宮格拉伸繪製（邊距 `m`），用喺面板／按鈕 |
| `_panel_box()` / `_report_x()` / `_report_w()` | HUD 底板矩形／結算文字左邊／可用闊度（**改面板大細改呢三個**） |

### 6.3 主循環

| 函數 | 做的事 |
|---|---|
| `_process(delta)` | 計 toast／R 確認倒數、換鼠標形狀；`RUN` 時用累加器把真實時間換成 sim tick（快進 ×8）；每 tick 叫 `lm.step()`；到贏／時間到就 `_end_loop()` |
| `_drain_rejected()` | 把 `lm.rejected` 變成紅閃（`deny`） |
| `_tick_fx(dt)` | 遞減白閃／紅閃計時 |
| `_end_loop(won)` | 記錄 `report`（交貨、AP、幽靈報告）→ `seal_loop()` → 切 `REPORT`／`WIN`／`LOSE` |
| `_after_report()` | 按「開始下一個 loop」：`begin_loop` + 清 UI 狀態 |
| `_restart()` | 成局由 loop 1 重開 |

### 6.4 輸入

| 函數 | 做的事 |
|---|---|
| `_unhandled_input(e)` | 所有輸入入口：鼠標移動（hover／拖時間軸）、滾輪（切建築）、左鍵（快速鍵／選單／放置）、右鍵（拆除）、SHIFT（預演）、ENTER（快進）、SPACE（暫停／開始）、1–6、Q/E、R×2、D（demo） |
| `_cell_at(p)` | 螢幕座標 → 格座標（越界回 `(-1,-1)`） |
| `_in_timeline(p)` | 滑鼠係咪喺時間軸條上面 |
| `_cycle_selected(step)` | 滾輪喺 6 種建築之間循環 |
| `_begin_preview()` / `_set_preview(t)` | 開預演／拖到某 tick |
| `_rotate_action(step)` | Q/E：指住已放建築 = 轉佢；否則轉「即將放置」方向 |
| `_try_rotate/_try_place/_try_demolish` | 檢查 → `submit_*` → 成功白閃／失敗紅閃；建造佔 `busy = BUILD_TICKS` |
| `debug_demo_build()` | D 鍵：鋪兩條 demo 線（debug 用） |
| `debug_build_line(y)` | 喺賽道 y 鋪一條 10 件完整線，回傳成功幾件 |

### 6.5 繪製（`_draw` 由底到頂）

`_draw()` 次序：海 → 沙灘／島邊 → 地板 → 格線 → 礦脈帶 → 地表裝飾 → 礦脈 → 建築 → 幽靈 → hover → 時間軸 → HUD → 預演標籤 → toast → 結算／勝負。

| 函數 | 做的事 |
|---|---|
| `_draw()` | 主繪製；讀 `lm.world`（預演時讀 `pv.world`） |
| `_draw_palette(font)` | 右邊 6 個建築按鈕（選中／hover 貼圖、名、快捷鍵） |
| `_draw_hover()` | 滑鼠格提示：空格 = 綠／紅框＋放置方向；有建築 = 轉向提示＋拆遷淨 AP |
| `_draw_timeline(font)` | 時間軸：每個幽靈嘅命令刻度（佢自己顏色）＋已過時間條 |
| `_draw_hud(font)` | 右上資訊：LOOP、剩餘時間、交貨、AP、幽靈數；`RUN` 時再畫選單同快進掣 |
| `_draw_end_loop_button(font)` | 「⏩ 快進至 loop 結束」按鈕（AP 用晒會變金色） |
| `_draw_report(font)` | 結算面板：交貨、幽靈列表（顏色 chip、勾選框）、開始掣 |
| `_draw_end(font)` | 勝／負面板 |
| `_draw_arrow(b, r, mod)` | 畫方向箭頭（機器／出口） |

### 6.6 結算／UI 幾何（繪製同點擊共用同一份）

| 函數 | 做的事 |
|---|---|
| `_report_row_rect(i)` | 第 i 行幽靈嘅矩形 |
| `_report_rows_y()` | 幽靈列表下面嗰行嘅 y（開始掣用） |
| `_report_start_rect()` | 「開始下一個 loop」掣矩形 |
| `_report_row_at(pos)` | 滑鼠喺邊一行（-1 = 冇） |
| `_report_click(pos)` | 結算畫面點擊：開始掣 or 切換幽靈 |
| `_end_loop_rect()` | 快進掣矩形 |
| `_toggle_fast_forward()` | 開／關 ×8 快進 |
| `_palette_rect(i)` / `_palette_index_at(pos)` | 選單按鈕矩形／滑鼠喺邊個（**畫同點擊共用**） |
| `_regen_text()` | HUD 嘅 AP 回復倒數文字 |
| `_quota_text()` | 幽靈上限文字（∞ 或數字） |
| `_deco_key(cx, cy)` | 每格裝飾嘅固定 hash（純視覺，唔影響模擬） |

### 6.7 貼圖／顏色對照（`match type` 開關）

| 函數 | 做的事 |
|---|---|
| `_tex_key(b, tick)` | 建築用邊張圖（含帶／爐嘅 2 格動畫） |
| `_slot_tex(t)` | 選單用邊張圖 |
| `_item_tex(item)` | 貨物用邊張圖 |
| `_color_for(t)` | 冇貼圖時嘅代替色 |
| `_item_color(item)` | 冇貼圖時貨物嘅代替色 |
| `_ghost_pos(li, t)` | 第 li 個幽靈喺第 t tick 企喺邊格（最後一條 `t <= t` 嘅命令） |
| `_ghost_color(li)` | 幽靈身份色（`GHOST_COLORS[li % 8]`） |
| `_draw_ghost_trail(li, look_t, gc)` | 最近 6 個建造格嘅足跡色塊 |

> 加新建築：`constants.T_*`、`recipe_*`、`_produce`、`_transport`、`PALETTE_TYPES`、
> `_draw_palette` 嘅 `names`、`_slot_tex`、`_tex_key`、`_color_for`、`gen_art.py`、測試。

### 6.8 已知小問題（可以自行清）

- `_draw()` 入面「礦脈軌道底色」畫咗**兩次**（兩段一模一樣嘅 for loop，alpha 0.05 + 0.10），係早期遺留。
- `speed` 變數（永遠 1.0）同 `report_timer`（冇用到）係預留欄位，可以刪。
- `constants.gd` 嘅 `GHOST_SLACK` 冇被使用（`loop_manager.gd` 自己有一份）。

---

## 7. `game/tests/test_determinism.gd` — T1–T16

| 測試 | 驗咩 |
|---|---|
| T1 | live 同「用同一 log 重播」逐 tick 指紋一致 |
| T2 | 幽靈＋玩家並存，整段重播一致；幽靈建築係真建築 |
| T3 | 連環點擊唔可以超 AP 上限 |
| T4 | 拆幽靈 2 AP／拆自己淨 0 |
| T5 | 8 個 loop × 1800 tick 效能（< 6 秒） |
| T6 | 幽靈上限：預設無限、關卡可自訂、唔會自動踢走你揀咗嘅人 |
| T7 | 預演 `preview_at(t)` 同 live 逐 tick 一致（含前後拖） |
| T8 | 預演唔會污染真實世界 |
| T9 | 5 條礦脈內真係達標；印出交貨曲線（13/26/39/52） |
| T10 | B 規則：機→機一定要經帶 |
| T11 | 礦機只可以擺喺礦脈 |
| T12 | 拆遷退款：退自己、唔退幽靈、唔可以刷 AP |
| T13 | 幽靈換人：手動開關、名額、上限 |
| T14 | 玩家／幽靈搶格四種情況 + 玩家被拒有紀錄 |
| T15 | AP 隨時間回復（1/300 tick）同重播一致 |
| T16 | 就地旋轉：自己免費、幽靈要 `AP_COST_ROTATE_GHOST`、重播一致 |

每個測試用 `_check(name, cond, detail)` 記錄；`_initialize()` 順序叫晒。
加新測試：寫一個 `_test_xxx()`，喺 `_initialize()` 加一行。

---

## 8. `game/autoload/mcp_interaction_server.gd`

godot-bridge 嘅開發工具（~4900 行）：喺遊戲入面開一個 TCP server（port 9090），
畀 AI／工具 send command（`screenshot`、`eval`、`get_scene_tree`…）。

- **唔好**喺呢個檔加遊戲邏輯。
- 遊戲本身唔依賴佢；刪咗佢都玩得（但 AI 就控制唔到遊戲）。
- `eval` 可以喺 runtime 改任何嘢，做 debug／截圖好有用。

---

## 9. 常見改動 checklist

### 9.1 改一件數值（最常見）

```
改 game/sim/constants.gd 一個 const → 跑 test_determinism.gd
```

例：轉幽靈建築 AP：`AP_COST_ROTATE_GHOST`（2 → 1）。UI 文字會自動跟（讀 `rotate_cost()`）。
例外：`DESIGN-SPEC.md` 嘅文字要自己更新。

### 9.2 改配方／加第四層

1. `constants.gd` 加 `T_*`、`ITEM_*`、新 recipe 常數
2. `sim_world.recipe_*()` 六個 function 加 `match` 分支
3. `sim_world._produce()` 完成時加計數（如有）
4. `sim_world._transport()` 如果新貨種／新流向要改
5. `sandbox`：`PALETTE_TYPES`、`names`、`_slot_tex`、`_tex_key`、`_color_for`、`_item_tex`、`_item_color`
6. `tools/gen_art.py` 加圖 → `python tools/gen_art.py`
7. 測試：加 proof，跑 T1–T16

### 9.3 改 loop 長度／AP／目標

- `LOOP_TICKS`：時間軸、快進、AI 自動跟；T5/T7 時間會變，但斷言係相對值
- `AP_MAX` / `AP_REGEN_TICKS` / `AP_REGEN_AMOUNT`：T3/T15 會受影響
- `WIN_TARGET`：T9 會受影響（曲線 13/26/39/52）

### 9.4 改幽靈上限

- `GHOST_CAP = 0`（無限）或 `> 0`；亦可以喺 `start_level()` 之後設 `lm.ghost_cap`
- 如果只想某關卡有上限：`lm.ghost_cap = 3`

### 9.5 改顏色／版面

- 幽靈色：`GHOST_COLORS`（8 色循環）
- 結算面板：`REPORT_Y`、`REPORT_ROWS_Y`、`REPORT_ROW_H`（加行要同步睇 672 底部夠唔夠位）
- 選單：`PALETTE_*`；按鈕畫同點擊都用 `_palette_rect()`，改大細只改一處
- 棋盤：`CELL`、`ORIGIN`；改咗要睇沙灘／時間軸／視窗 1280×720

### 9.6 加新命令種類（例如「升級」）

1. `constants.gd` 加 `C_UPGRADE`
2. `loop_manager._pending_ap()` 加成本
3. `loop_manager._apply()` 加分支（**唯一入口**）
4. `submit_upgrade()` 入隊
5. UI：快捷鍵＋提示
6. 測試：AP 閘、重播一致

---

## 10. 五個唔好踩嘅陷阱

1. **加新狀態唔同步四個地方**：`clear()` / `save_state()` / `load_state()` / `digest()`。
2. **模擬用浮點**：tick、進度、AP 全部要整數；`delta` 只可以喺 `sandbox._process` 用嚟累加時間。
3. **靠 Dictionary 次序**：`digest()` 要用固定 `range()` 次序，唔好 `for key in dict` 直接 hash。
4. **繞過 `_apply()` 直接改世界**：會令幽靈重播／預演對唔上（T1/T7 會捉到）。
5. **UI 幾何分兩份**：畫同點擊一定要共用同一個 rect function（例如 `_palette_rect`），否則會「見到喺度、點落去偏咗」。

---

## 11. 跑測試同遊戲（本機）

```powershell
# 用 Godot 編輯器開
powershell -ExecutionPolicy Bypass -File tools/open-game.ps1

# Headless 測試（普通終端）
& '.\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe' --headless --path game --script res://tests/test_determinism.gd
```

> 喺 **DSH（AI 環境）** 就唔可以用 shell 直接開 Godot（sandbox 會擋 `user://` 寫入 → signal 11），
> 一定要經 `godot_run_project` / `godot_run_headless` / `godot_validate_script` 呢類工具。
