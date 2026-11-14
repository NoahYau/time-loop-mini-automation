# 新功能計劃（第一批）：生產診斷 × 藍圖複製 × 幽靈分色

> 狀態：**計劃稿，未實作**。對應 `dev` 分支可玩切片，Godot 4.7.2。
> 想法背景見 [FEATURE-IDEAS.md](FEATURE-IDEAS.md) 第 1–3 項；規則與平衡見 [DESIGN-SPEC.md](DESIGN-SPEC.md)。

---

## 0. 定位

第一批嘅目標**唔係**加深玩法，而係令現有玩法「講得清楚、鋪得快、睇得明」：

| 功能 | 解決咩痛點 |
|---|---|
| 生產診斷 | 結算只講「交貨幾多」，玩家唔知點解輸 |
| 藍圖複製 | 5 條線一模一樣，要逐格點 50 次 |
| 幽靈分色 | 6–7 個幽靈全部白色，分唔清邊個做咗咩 |

**關鍵約束**：三個功能都**唔改** `constants.gd` 嘅平衡數字、**唔改**命令 schema、**唔加**新命令種類。
所以 T1–T16 應該原封不動保持綠燈，T9 曲線 `13 / 26 / 39 / 52`、第 4 個 loop 達標必須不變。

---

## 1. 目標與成功標準

**目標**：令一個新玩家喺第 2 個 loop 就明白「點解今個 loop 交得少」，並且用 5 秒而唔係 50 秒鋪完下一條線；同時一眼分得出邊個幽靈做咗咩。

**成功標準**
1. `res://tests/test_determinism.gd` 全綠（T1–T20），T9 曲線不變。
2. 結算畫面同時顯示：流量數字（礦→錠→齒→零件→出口）、你 vs 幽靈反事實貢獻、一個樽頸診斷、你嘅操作統計。
3. ALT＋左鍵拖框可複製一段建築；左鍵連續貼落其餘 4 條賽道；每次貼上 AP 與建造時間同逐格起完全一致；貼上後下一 loop 幽靈重播一致。
4. 3 個以上幽靈在棋盤、時間軸、結算列表各有固定顏色。
5. 實機截圖 `s25_diag.png`、`s26_blueprint.png`、`s27_ghostcolor.png`。

---

## 2. 現況基準（已實測）

- 分支 `dev`，實作前 working tree 只有未追蹤嘅 `FEATURE-IDEAS.md`。
- `godot_run_headless --script res://tests/test_determinism.gd` → **RESULT: PASS (0 failures)**；T5 8 loop 共 **719.4 ms**；T9 曲線 `[13, 26, 39, 52]`、第 4 loop 達標。
- 引擎：`Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe`。
  **只准經 `godot_*` 工具啟動，唔可以用 pwsh／shell**（會被 sandbox 擋 user:// 寫入而 signal 11）。
- 架構約束：
  - 命令 schema 固定 `{t, k, x, y, type, dir}`，`LoopManager._apply()` 係 live／重播／預演唯一入口。
  - sim 內零 Node、零 delta、零浮點累加；遍歷次序固定（`range(GRID_W*GRID_H)`）。
  - 加新狀態＝同時處理 `clear() / save_state() / load_state() / digest()`，否則預演 checkpoint 同重播會唔一致。

---

## 3. 功能 A：生產診斷

### A1 `game/sim/sim_world.gd`（純資料）

新欄位：

```gdscript
var ingots_made: int = 0
var gears_made: int = 0
var stat_alive: Dictionary = {}     # type -> 該類建築存在嘅 tick 數
var stat_starve: Dictionary = {}    # type -> 缺料 tick 數
var stat_blocked: Dictionary = {}   # type -> 有貨但送唔出嘅 tick 數
```

- `clear()` 全部歸零。
- `_produce()`：每格先 `stat_alive[type] += 1`；機器 `in_count < need` 時 `stat_starve[type] += 1`；
  完成時 `T_FURNACE → ingots_made += 1`、`T_GEAR → gears_made += 1`、`T_ASSEMBLER → parts_made += 1`（現有）。
- `_transport()`：收集 moves 時記 `moved[idx] = true`；提交後遍歷全部建築，`has_out` 但冇移動 → `stat_blocked[type] += 1`。
  呢個定義同時捉到「冇下游」「下游塞住」「機器貼機器（B 規則）」。
- `save_state()/load_state()` 加 `"stat"` 子字典；`digest()` 加入新數值，
  **固定用 `for t in range(1, K.T_SINK + 1)` 迭代**（唔可以靠 Dictionary 次序）。
- 新 API `func stats() -> Dictionary`：
  `{tick, ore, ingot, gear, part, delivered, alive{}, starve{}, blocked{}}`（dict 用 `duplicate()`，畀 UI 唯讀快照）。
- 效能預算：T5 上限 6000 ms，現時 719 ms，容許 +20%。

### A2 `game/sim/diagnose.gd`（新檔，RefCounted，純函數，方便 headless 測）

```gdscript
static func hints(stats: Dictionary) -> PackedStringArray   # 回傳 id，最多 2 個
static func text_for(id: String) -> String                  # 廣東話文案
```

規則（閾值做 const，方便調）：

| id | 條件 |
|---|---|
| `no_buildings` | delivered == 0 且 alive 總和 == 0 |
| `miner_to_furnace_belt` | 爐缺料 ≥30% **且** 礦機送唔出 ≥20% |
| `furnace_starved` | 爐缺料 ≥30% |
| `assembler_starved` | 組裝台缺料 ≥30% |
| `gear_starved` | 齒輪機缺料 ≥30% |
| `belt_jammed` | 傳送帶送唔出 ≥40% |
| `none` | 其他 |

`miner_to_furnace_belt` 額外附 `b_rule_tip`。百分比 = `stat / max(1, alive)`。
文案例：`"礦機貼住爐但中間冇帶：機器唔可以直接餵機器（B 規則）"`。

### A3 `game/sim/loop_manager.gd`（只加統計，唔改規則）

- `var player_actions := {"build":0,"demolish":0,"rotate":0}`、`var player_ap_spent: int = 0`；
  `begin_loop()` 重置；`_apply()` 內 `is_player` 時累加（拆除計 `maxi(0, net)`，退款後淨 0 就唔算）。
- `func baseline_delivered() -> int`：反事實——複製 `ghosts/active/ghost_cap/loop_limit`，
  `begin_loop(loop_index)` 後**完全冇玩家命令**跑到 `LOOP_TICKS`／達標，回傳 delivered。
  用 `(load("res://sim/loop_manager.gd") as GDScript).new()`，唔郁本體狀態。成本 ≈ 一個 loop ≈ 90 ms，結算時算一次。

### A4 `game/scenes/sandbox.gd`（結算面板）

- `_end_loop()`：喺 `seal_loop()` **之前** snapshot `report["stats"]`、`report["actions"]`、`report["ap_spent"]`；
  只有「唔係贏、唔係最後一個 loop」才計 `report["baseline"]`。
- 版面：`REPORT_Y 320 → 244`、`REPORT_ROWS_Y 78 → 160`
  （HUD 最後一行 baseline ≈ 213，面板頂 230 有 13 px 緩衝；8 個幽靈時開始掣喺 584–620，面板底 636 < 672）。
- 新增文字行（size 12–13）：
  - `+40` 你 vs 幽靈：`唔靠你 → 19 件；你今個 loop 貢獻 +7`
  - `+60` 流量：`礦 120 → 錠 58 → 齒 52 → 零件 13 → 出口 13`
  - `+80` 你嘅操作：`起 10・拆 0・轉 0・花 11 AP`
  - `+102` 樽頸（暖色）＋ `+122` 提示（暗色）
  - `+146` 原有「點擊幽靈切換出動」
  - 負貢獻文案：`你扣咗 3 件（你嘅建築搶咗幽靈嘅格）`
- WIN／LOSE 面板加一行流量數字（免費，唔用反事實）。

---

## 4. 功能 B：藍圖複製／貼上

### B1 先修一個潛在排序 bug（必須，否則藍圖會令命令卡死）

`_apply_until()` 假設 `current_log` 按 `t` 升序。而家全部命令都係 `t = world.tick + 1` 所以冇事，
但藍圖會一次過排 `t = now+1, +16, +31…`，之後再單獨點一下（`t = now+1`）就會排到隊尾 → `while` 提早停，命令永遠唔執行。

- 新 `func _queue(cmd: Dictionary) -> void`：由尾向前掃，插在最後一個 `t <= cmd.t` 之後。
  `submit_build / submit_rotate / submit_demolish` 全部改用它。
- `submit_*` 加 `if world.tick + 1 > K.LOOP_TICKS: return false`（避免永遠唔會執行嘅墳墓命令）。

### B2 `loop_manager.submit_blueprint(anchor: Vector2i, cells: Array) -> Dictionary`

- `cells` 每項 `{dx, dy, type, dir}`；內部**先按 `(dy, dx)` 排序**（重播次序同 UI 無關）。
- 逐格：`cell = anchor + offset`；`can_place()` 失敗 → `skipped_invalid`。
- 三重上限：
  - `ap_available()` 本地預算（每件扣 1，唔好逐次重算 `_pending_ap`）→ `skipped_ap`
  - `t = world.tick + 1 + i * K.BUILD_TICKS` 超過 `K.LOOP_TICKS` → 停 → `skipped_time`
- 回傳 `{queued, skipped_invalid, skipped_ap, skipped_time}`。
- AP 係「執行時才扣」，`_apply()` 照舊做最後防線（撞幽靈 → 紅閃、唔扣 AP）。
- 藍圖只係一次過排多條 `C_BUILD` → 命令 schema 不變、幽靈 log 格式不變、盤面平衡不變。

### B3 `sandbox.gd` 輸入與繪製

- 新狀態：`bp_cells: Array`、`copying: bool`、`copy_a/copy_b: Vector2i`。
- 操作：
  - **ALT + 左鍵拖**（棋盤內）→ 青色選框；放開 → 按 (y, x) 捕捉建築，跳過空格。
    `toast = "已複製 N 件 — 左鍵貼上、ESC 取消"`，進入貼上模式。
  - 貼上模式：跟住鼠標畫半透明藍圖（綠 = 可放、紅 = 被佔／出界／AP 唔夠），旁邊顯示 `N 件 = N AP（可用 M）`。
  - 左鍵 → 貼；**貼完保留藍圖**，可以即刻貼下一條賽道。
  - `ESC` 或右鍵 → 取消（右鍵有藍圖時**唔會**拆嘢，避免手滑）。
  - 選單／滾輪／1–6 照常；`SHIFT` 預演時唔准複製／貼上。
- `_capture_blueprint()` 要 clamp 去棋盤範圍；0 件 → toast 提示、唔進入貼上模式。
- HUD 加 `ALT+拖 = 複製藍圖　左鍵貼上、ESC 取消`；貼上中顯示藍圖狀態。
- 貼上用回傳值砌 toast：`已貼 8／10 件（2 格被佔；AP 用晒）`。
- 複製係純讀盤面，**唔扣 AP**；貼上每件照收 1 AP、照佔 0.5 秒（staggered t）。
- v1 唔做旋轉／鏡像藍圖（5 條賽道同向，用唔著）。

---

## 5. 功能 C：幽靈分色 + 足跡（純繪製，零 sim 改動）

- 8 色循環（藍／薄荷／琥珀／珊瑚／紫／粉／青檸／白），`_ghost_color(li)` 取 `li % 8`。
- 建築：幽靈建築貼圖保持白色 α0.62，另在格底畫 4 px 該幽靈色橫條（唔會令像素圖變濁）；玩家自己嘅唔畫。
- 幽靈本體：光環＋核心用該幽靈色，旁邊 `#n`；足跡＝`look_t` 之前最近 ≤6 個建造格，由舊到新 α 0.10→0.22。
- 時間軸刻度改用該幽靈顏色（而家只有兩種白）；結算列表每行加 3 px 顏色 chip。
- 唔需要新美術、唔改 `tools/gen_art.py`。

---

## 6. 改動檔案（按子系統）

| 檔案 | 改動 |
|---|---|
| `game/sim/sim_world.gd` | 統計欄位、`stats()`、save/load/digest 同步 |
| `game/sim/diagnose.gd` | **新檔**：純函數診斷 + 文案 |
| `game/sim/loop_manager.gd` | `_queue()` 排序插入、`submit_blueprint()`、`baseline_delivered()`、玩家操作統計 |
| `game/scenes/sandbox.gd` | 結算版面同診斷文字、藍圖輸入／預覽／toast、幽靈分色／足跡 |
| `game/tests/test_determinism.gd` | T17–T20（見 §8），`_initialize()` 加呼叫 |
| `README.md` | 操作表（ALT 複製／ESC）、測試 T1–T20、架構加 `sim/diagnose.gd` |
| `DESIGN-SPEC.md` | v1.5：6.96 診斷報告／6.97 藍圖／6.98 幽靈分色；驗收加 T17–T20；規則總表不變 |
| `FEATURE-IDEAS.md` | 第 1–3 項標記「已規劃（見本檔）」 |

**唔會改**：`constants.gd` 平衡數字、命令 schema、美術／`gen_art.py`、`project.godot`、`main` 分支。

---

## 7. 資料流 / API / schema

```
輸入(ALT拖/點擊) → LoopManager._queue(t 排序插入) → step() tick 邊界
   → _apply()（唯一入口，AP/佔格檢查）→ SimWorld（建築 + 統計）
   → 結算：world.stats() + baseline_delivered() + player_actions → report dict → UI 繪製
```

- **命令 schema 不變**（藍圖重用 `C_BUILD`）。
- **`save_state()` schema v2**：加 `"stat"`（只在預演 checkpoint 用，未有存檔系統，無遷移問題）。
- **`digest()`**：加入統計值；現有測試全部係同 run 內比對，數值改變唔影響斷言。
- **新公開 API**：`SimWorld.stats()`、`LoopManager.submit_blueprint()`、`LoopManager.baseline_delivered()`、
  `LoopManager.player_actions/player_ap_spent`、`Diagnose.hints()/text_for()`。

---

## 8. 測試（headless，加入現有 `_initialize()`）

| 編號 | 內容 | 關鍵斷言 |
|---|---|---|
| **T17** 生產診斷 | 一條完整線跑 600 tick；再跑「礦機貼爐冇帶」 | 錠/齒/零件/交貨 > 0；`stat_alive[furnace] > 0`；壞線 delivered == 0、礦機 blocked > 100、爐 starve > 100；`Diagnose.hints()` 含 `miner_to_furnace_belt`；好線唔含；兩次同 script 跑 `stats()` 相等 |
| **T18** 你 vs 幽靈 | loop0 鋪 A；loop1 冇玩家輸入 → baseline == delivered；loop1 加 B 線 → baseline < delivered；全新 manager → baseline == 0 | 反事實單調、唔污染本體（跑完後本體 digest／AP／log 不變） |
| **T19** 藍圖 | 藍圖貼一整條 10 件線 | `queued == 10`、`skipped_* == 0`、`ap_available()` 12→2、`current_log` t 非遞減、每條 t ≤ LOOP_TICKS、10 格都有建築；同「逐格起」控制組逐 tick digest 一致；seal 後下一個 loop 重播一致。另加：AP 只剩 3 貼 10 件 → `queued 3 / skipped_ap 7`；loop 尾貼 → `skipped_time > 0` 且冇命令 t > LOOP_TICKS |
| **T20** 隊列排序 | 先貼藍圖（t=1,16…136），即刻再單獨 submit 一件（t=1） | `current_log` t 非遞減；step 2 次後兩件都落地 |

**回歸要求**：T1–T16 一行都唔改，`RESULT: PASS`；T9 仍 `13/26/39/52`、第 4 loop 達標；T5 < 6000 ms。

**實機驗收**（`godot_run_project` + `godot_command` / `godot_screenshot`，唔可以用 shell 開 Godot）：
1. `D` 快速鋪兩條線 → 過一個 loop 出現 2 個幽靈，顏色唔同；截 `s27_ghostcolor.png`。
2. ALT 拖第一條線、貼落其餘 3 條賽道 → 每次 AP 準確 −10、有 stagger、console 無 error；截 `s26_blueprint.png`。
3. `godot_command eval` 臨時塞 7 個幽靈再 `_end_loop(false)`，確認結算面板 8 行齊、開始掣可點；截 `s25_diag.png`。

---

## 9. 邊界情況 / 失敗模式

| 情況 | 行為 |
|---|---|
| 藍圖貼上撞到幽靈（已存在或同 tick） | 交由 `_apply()` 拒絕 → 紅閃、唔扣 AP（T14/C 已覆蓋） |
| 藍圖超出地圖邊界 | `skipped_invalid`，其餘照貼 |
| AP 唔夠／loop 剩餘時間唔夠 | 貼到幾多得幾多，toast 明確講漏幾多件（唔可以靜靜雞吞） |
| 藍圖同手動點擊交錯 | `_queue()` 排序插入保證兩者都喺自己嘅 tick 執行（T20） |
| 貼上時 loop 快完 | 時間上限截斷，避免墳墓命令入 ghost log |
| 反事實貢獻係負數 | 文案「你扣咗 N 件」，唔好當 bug |
| 冇幽靈（第一個 loop） | baseline = 0，文案「全部係你」 |
| 8 個幽靈面板太高 | 已預留 8 行；再加行就先減 `REPORT_ROWS_Y` |
| `digest` 加欄位令數值變 | 現有測試同 run 內比對，唔受影響；但唔可以改成靠 Dictionary 次序迭代 |
| 反事實重算造成卡頓 | 實測 ~90 ms，只喺結算一次；真係卡就快取／背景計，API 唔變 |

---

## 10. 實作次序

1. `sim_world.gd` 統計 + save/load/digest（先令 T1–T16 重跑綠）。
2. `diagnose.gd` + T17。
3. `loop_manager.gd`：`_queue()`、`submit_blueprint()`、`baseline_delivered()`、玩家統計 + T18–T20。
4. `sandbox.gd`：結算版面／診斷文字（A4）→ 藍圖（B3）→ 幽靈分色（C）。**順序做**，因為三個功能都改同一個檔。
5. 文件（README／DESIGN-SPEC／FEATURE-IDEAS）＋ 三張截圖＋ `git diff` 覆核。
6. 全部 commit 落 `dev`（唔 push、唔掂 `main`）。

---

## 11. 假設

- 今批**唔改任何規則／平衡**；T9 曲線同通關 loop 數必須不變。
- UI 文字維持廣東話；唔做 i18n。
- 藍圖 v1 只做平移貼上，唔做旋轉／鏡像。
- 複製**包括**幽靈起嘅建築（「複製幽靈嗰條線」係刻意支援嘅用法）。
- ALT＋拖係暫定；如果實機發現 Windows 食咗 Alt，改用 `C` 鍵切換複製模式（只需改一個判斷）。
- 未有存檔系統，所以 `save_state` schema 改動無兼容包袱。
- 音效、升級、倒帶、分流器、關卡、分享碼：本批唔做（見 FEATURE-IDEAS 第二／三批）。

---

## 12. 之後（未批准，唔會做）

- **第二批**：機器超頻（`Building.level` + `C_UPGRADE`）、倒帶 10 秒（重用 checkpoint）、程序生成音效＋打擊感。
- **第三批**：關卡參數化＋星級、存檔、幽靈碼分享／觀戰、每日種子、首關引導。
