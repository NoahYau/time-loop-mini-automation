# BRIEF：UI 重構做 Control scene（可喺編輯器拖拽）

> 呢份係「開新對話」用嘅開場 brief。新對話嘅 Lead 讀完之後，
> 先開共享 task、再組隊，然後照里程碑落手。

---

## 0. 一句總結

把 `game/scenes/sandbox.gd` 入面用 `_draw()` 即時繪製嘅 **UI 部件**，
拆成真正嘅 `Control` scene（HUD、建築選單、結算面板、勝敗面板 + 一個 Theme），
令編輯器入面可以**揀中、拖拽、改屬性**；runtime 只係「餵數值」。
**外觀、文字、操作手感、模擬行為必須完全唔變。**

---

## 1. 專案背景（唔使再查）

- 專案路徑：`C:\Users\Noah Yau\Documents\deepseek-harness\godot\game`（`project.godot`，Godot **4.7.2 mono**）
- 主場景：`res://scenes/sandbox.tscn` → 單一節點 `Sandbox (Node2D)`，掛 `@tool` script `sandbox.gd`（約 1,050 行）
- 視窗 1280×720（`display/window/stretch/mode="canvas_items"`）
- 模擬層 `game/sim/**` 係純資料、確定性、零 Node（**唔准改**）
- 測試：`game/tests/test_determinism.gd`（T1–T16，現時全 PASS）、`bench_step.gd`、`bench_regen.gd`
- 文件：`CODE-GUIDE.md`（逐 function 講解 + 陷阱）、`DESIGN-SPEC.md`
- 現時分支 `dev`，最新 commit `ad897aa`（就係加咗編輯器預覽嗰個）
- 引擎路徑已經寫入 DSH profile（`godot_set_engine_path`），`godot_*` 工具直接用得

### 現況：UI 全部係 immediate mode

`sandbox.gd` 嘅 `_draw()` 每一 frame 用 `draw_rect / draw_texture_rect / draw_string` 畫：

| 部件 | 繪製函式 | 命中測試 |
| --- | --- | --- |
| 海／沙灘／地板／格線／裝飾／礦脈 | `_draw()` 本體 | `_cell_at(p)` |
| 建築、貨物、幽靈色條、進度條、箭頭 | `_draw()` 本體 | — |
| 幽靈本體 + 足跡 + `#n` 標籤 | `_draw_ghost_trail()` | — |
| hover 高亮 / Q-E 提示 | `_draw_hover()` | — |
| 時間軸 | `_draw_timeline()` | `_in_timeline(p)` |
| **右邊 HUD 文字** | `_draw_hud()` | — |
| **建築選單 6 個按鈕** | `_draw_palette()` | `_palette_rect(i)` / `_palette_index_at(p)` |
| **快進按鈕** | `_draw_end_loop_button()` | `_end_loop_rect()` |
| **結算面板（含幽靈列表 + 開始按鈕）** | `_draw_report()` | `_report_row_rect(i)` / `_report_start_rect()` / `_report_row_at(p)` |
| **勝敗面板** | `_draw_end()` | — |

9-slice 貼圖：`art/ui/{panel,panel_light,btn_normal,btn_hover,btn_sel,row}.png`，
現時由 `_draw_nine(key, rect, margin, mod)` 處理，邊距：`panel`/`panel_light` = 8、`btn_*` = 6、`row` = 4。
選單圖示：`art/buildings/{miner,belt_e_a,furnace_a,gear,assembler,sink}.png`。

### 版面常數（**新 UI 必須對得上，唔准郁**）

```
CELL=40  ORIGIN=(20,44)  棋盤 16×16           # 棋盤範圍 x:20–660, y:44–684
_panel_box() = Rect2(684, 16, 572, 656)       # 右邊 HUD 底板
PANEL_X=700  PALETTE_Y=392                    # 選單 x 起點 / y 起點
PALETTE_BTN=(104,58)  PALETTE_GAP=6  PALETTE_COLS=3   # 2 行 × 3 欄
_end_loop_rect() = (700, 530, 324, 36)        # 選單下面嗰粒「快進至 loop 結束」
TL_Y=692  TL_H=16                             # 時間軸：x 20–660
REPORT_Y=320  REPORT_ROWS_Y=78  REPORT_ROW_H=21
_report_row_rect(i) = (708, 320+78+21i, 524, 21)
_report_start_rect()  = (708, 320+78+21·max(ghosts,1)+12, 524, 36)
結算面板底 = Rect2(684, 306, 572, start_btn.end.y - 320 + 30)
```

字級現用：20（標題）/21（LOOP）/18（數值）/15 /13 /12 /11。中文字用 `ThemeDB.fallback_font`。
`phase` enum：`P.RUN / P.REPORT / P.WIN / P.LOSE`；UI 只喺 `RUN` 顯示選單+快進鍵。

### 已經有嘅編輯器預覽（**唔准拆爛**）

`@tool` + Inspector ▸ Editor Preview（`editor_preview` / `editor_phase` / `editor_fill_demo` / `editor_seconds`），
`_editor_refresh()` / `_rebuild_preview()` / `_preview_run_loop()` / `_draw_editor_badge()`。
重構之後，喺編輯器打開 `scenes/sandbox.tscn` 仍然要見到成個畫面（棋盤 + 新 UI 一齊）。

---

## 2. 目標架構（可以調整，但要寫低理由）

```
Sandbox (Node2D, sandbox.gd)        ← 保留：模擬驅動、棋盤 _draw()、輸入、@tool 預覽
└─ UI (CanvasLayer)                 ← 新增，UI 同 2D 鏡頭解耦
   └─ HUD (Control, full rect, mouse_filter = IGNORE)
      ├─ StatsPanel (PanelContainer/自訂)   ← 右邊 HUD 文字
      ├─ PaletteGrid (GridContainer)        ← 6 粒 Button
      ├─ FastForwardButton (Button)
      ├─ ReportPanel (Control)              ← 結算：3 行文字 + 幽靈列容器 + 開始鍵
      └─ EndPanel (Control)                 ← 勝／敗
```

規則：

1. **棋盤仍然用 `_draw()`**（每格像素貼圖、幽靈色條、足跡、hover、時間軸）。
   Control node 逐格做會又慢又走樣，唔值得。
2. **單一寫手**：`sandbox.gd` / `sandbox.tscn` 永遠只有 Lead 改。
3. **單向資料流**：sandbox 每 frame 砌一個 `Dictionary`（或小型 RefCounted `HudView`），
   呼叫 `hud.update_view(view)`；UI **唔准**直接讀 `lm` / `world`。
4. **事件反向用 signal**：`palette_selected(type)`、`fast_forward_pressed`、
   `report_row_toggled(li)`、`report_start_pressed`。
5. **命中一致性**：部件嘅位置只有一個來源（Control 自己）。
   舊嘅 `_palette_rect / _end_loop_rect / _report_*` 一律刪走，`mouse_pos` 手動 cursor 邏輯由 Control
   `mouse_default_cursor_shape` 取代；棋盤區域要**確保冇 Control 蓋住**（HUD 用 `mouse_filter = IGNORE`，
   只有按鈕/面板設 `STOP`）。
6. **Theme**：`game/ui/theme.tres` + `StyleBoxTexture`（9-slice margin 6/8）重用 `art/ui/*.png`；
   `default_font = ThemeDB.fallback_font`（否則中文變豆腐）、`default_font_size` 設基準。
7. 文字、顏色、數值格式**逐字照抄**現有 `draw_string` 嘅內容（包括 `⏩`、`#n`、全形括號）。

---

## 3. 里程碑（每個 milestone 一個 commit）

| M | 內容 | 完成條件 |
| --- | --- | --- |
| **M0** | Lead：`UI(CanvasLayer)` + `HUD.tscn` 骨架入 `sandbox.tscn`、`update_view()` 介面、`theme.tres`（9-slice） | 遊戲畫面 0 變化（UI 全隱藏）；T1–T16 綠 |
| **M1** | 右邊 HUD 文字 Control 化，`_draw_hud()` 只留空殼 | 截圖同 `test_screenshot/editor_preview_run.png` 一致 |
| **M2** | 選單 6 鍵 + 快進鍵 Control 化；signal 接返 `selected` / `_toggle_fast_forward()`；選中/hover/AP=0 狀態用 theme override 表達 | 點擊、滾輪、1–6 快捷鍵全部照舊；滑鼠手感一致 |
| **M3** | 結算面板 + 勝敗面板 Control 化（幽靈列用容器動態生成） | 對齊 `test_screenshot/editor_preview_report.png`；toggle/開始鍵行為不變 |
| **M4** | 清死碼（`_draw_nine`、舊 rect function、無用常數）、更新 `CODE-GUIDE.md`、補截圖 | 無 warning、無孤兒 code、文件講清楚新結構 |

---

## 4. 團隊分工（建議）

| 角色 | 寫入範圍（互不重疊） | 負責 |
| --- | --- | --- |
| **Lead（你）** | `game/scenes/sandbox.gd`、`game/scenes/sandbox.tscn`、`CODE-GUIDE.md` | M0、整合、`update_view()`、刪死碼、最後 review |
| `ui-hud` | `game/ui/hud.tscn`、`game/ui/hud.gd` | M1（數值文字）+ M2（選單/快進鍵） |
| `ui-panels` | `game/ui/report_panel.*`、`game/ui/end_panel.*` | M3 |
| `ui-theme` | `game/ui/theme.tres`、`game/ui/sb_*.tres`、`game/ui/font.tres` | Theme / 9-slice StyleBox（可以同 M0 並行） |

流程要求：`team_task_create` 開 task（寫明寫入範圍同驗收）→ 隊友 `claim` →
每個 milestone 完 Lead 親自跑測試 + 截圖 + review diff，先至 `complete`。

---

## 5. 驗收門檻（缺一不可）

1. `godot_run_headless --script res://tests/test_determinism.gd` → **T1–T16 全 PASS**
2. `bench_step.gd` / `bench_regen.gd` 數字同改動前一致（改之前先量一次做 baseline）
3. 遊戲實機截圖（`godot_run_project` + `screenshot`）同 `test_screenshot/editor_preview_run.png`、
   `editor_preview_report.png`（或 `s24_aligned.png`、`s28_ghostreport.png`）對得上；
   有像素差異要逐項解釋（例如字體 hinting 已可接受）
4. 編輯器：打開 `game/ui/hud.tscn`／`report_panel.tscn` → 揀得中、拖得動、改得屬性；
   打開 `scenes/sandbox.tscn` → `@tool` 預覽仍然畫出棋盤 + 新 UI
5. 60 秒實機 run 冇 script error、冇新 warning
6. 唔准改 `game/sim/**`、`game/tests/**`（除咗新增測試）、`game/art/**`、`game/sim/constants.gd`

---

## 6. 已知陷阱

- **DSH sandbox**：絕對唔可以用 `pwsh`/`bash` 直接開 Godot（會 signal 11）。一律用
  `godot_run_project` / `godot_run_headless` / `godot_validate_script` / `godot_headless_op`。
- **`@tool` 預覽**：`sandbox.gd` 係 `@tool`；改動 `_draw()` 時記住編輯器都會行，任何新 code（例如
  `hud.update_view()`）都要有 `lm == null` / `Engine.is_editor_hint()` 保護，否則編輯器會爆錯。
- **字體**：Control 冇設 `default_font` 會用內建字型 → 中文變豆腐。用 `ThemeDB.fallback_font`。
- **9-slice**：`StyleBoxTexture` 嘅 `texture_margin_*` 要對應舊 `_draw_nine` 嘅邊距（panel 8、btn 6、row 4），
  否則邊框拉伸比例會唔同。
- **滑鼠吞事件**：Control 全螢幕 + `STOP` 會令棋盤點唔到。全 rect HUD 一定要 `mouse_filter = IGNORE`。
- **時間軸拖拽**（`TL_Y=692` 嗰條）要留喺 `_draw()` + `_in_timeline()`，唔好被 Control 蓋住。
- **`_process` 係確定性驅動**：UI 更新只可以讀狀態，唔可以喺 UI 入面改 `lm`。
- 每個 milestone 前 `git status` 要乾淨；commit 用 `feat(ui): …` / `refactor(ui): …`，**只推 `dev`**。
- **故意 untracked 嘅兩樣嘢**：`Godot_v4.7.2-stable_win64.exe/`（引擎）同 `game/export_presets.cfg`。
  `git status` 見到佢哋係正常，**唔好 `git add` 佢哋**。

---

## 7. 建議第一步（新對話照抄）

1. `git log --oneline -1`、`git status`，讀 `CODE-GUIDE.md`、`DESIGN-SPEC.md`、`game/scenes/sandbox.gd`
2. 跑一次 baseline：`godot_run_headless --script res://tests/test_determinism.gd` + `godot_run_project` 截圖，記低數字
3. `team_task_create` 開 M0–M4 + 各人 scope，`spawn_teammate` 開 `ui-hud` / `ui-panels` / `ui-theme`
4. 做 M0（Lead），綠燈之後放隊友並行；每個 milestone 完返嚟 review
