# Time Loop Mini Automation

一個 2D 像素風的時間循環自動化小品（Godot 4.7 / GDScript）。
60 秒內鋪好產線、交出足夠零件；每次循環地圖重置，但你「過去嘅自己」會重播當年嘅建造動作。

## 玩法

- 每 loop 60 秒、12 AP（行動點，上限 12），每 10 秒回 1 點；最多 8 個 loop
- 棋盤 16×16 格（每格 40px）、5 條礦脈賽道；目標 48 件零件
- 三層配方：礦 → 錠 → 齒輪 → 零件，目標 56 件
- 幽靈（Ghost）會重播你過去每個 loop 嘅建造時序 —— 佢哋唔係裝飾，係真建築
- 拆自己嘅建築退 AP；拆幽靈嘅建築要 2 AP
- 地圖有 7 條礦脈，礦機只能擺喺礦脈上

## 操作

| 操作 | 效果 |
|---|---|
| 點選單 / `1–6` / 滾輪 | 選建築 |
| `Q/E` | 轉向 |
| 左鍵 / 右鍵 | 放置 / 拆除 |
| `SHIFT`（按住） | 時間停止 + 拖時間軸預演 |
| `ENTER` | 快進 8x 到 loop 結束 |
| `SPACE` | 暫停（結算畫面 = 開始下一個 loop） |
| `R` ×2 | 隨時重來；遊戲中要**按兩次**（2 秒內）確認，避免手滑清局 |

## 用 Godot 編輯器打開

專案喺 **`game/`** 呢個資料夾（`game/project.godot`），主場景係 `res://scenes/sandbox.tscn`。

```powershell
# 一鍵打開（會用 repo 根目錄嘅 Godot 引擎）
powershell -ExecutionPolicy Bypass -File tools/open-game.ps1
```

或者手動：Godot Project Manager → **Import** → 揀 `game\project.godot` → Import & Edit。

打開之後，左邊 FileSystem 會見到：

```
res://
  sim/      constants.gd  building.gd  sim_world.gd  loop_manager.gd
  scenes/   sandbox.tscn  sandbox.gd
  tests/    test_determinism.gd  bench_*.gd
  autoload/ mcp_interaction_server.gd   ← 開發工具，唔係遊戲邏輯
```

> 注意：根目錄仲有個 `demo/`，係早期 godot-bridge 嘅 hello-world，唔係遊戲本體。

## 執行

```powershell
# 需要 Godot 4.7（本 repo 唔包含引擎，請自行下載並放到 repo 根目錄，或改下面路徑）
& '.\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe' --path game
```

## 測試

```powershell
& '.\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe' --headless --path game --script res://tests/test_determinism.gd
```

T1–T13 覆蓋：確定性重播、AP、拆除退款、預演可信度、B 規則、礦脈、幽靈換人。

## 架構

```
game/
  sim/     純資料、確定性模擬（無 Node、無 delta、無物理）
  scenes/  可玩切片（繪製 + 輸入 + UI）
  tests/   無頭測試與效能基準
```

確定性係整個設計嘅地基：所有命令（幽靈 + 玩家）都喺 tick 邊界依序執行，
所以「預演」同「重播」可以同實際逐 tick 完全一致（T7 有驗證）。

## 美術

所有素材都係程式生成，冇手繪檔案：

```
tools/gen_art.py       ASCII 像素圖 + 調色板 -> game/art/**/*.png
tools/preview_art.py   出一張 A4 聯絡表（art_preview.png）方便一次過睇
```

- 建築／地板：**20×20 像素**，遊戲格 40px（整數 2 倍，輪廓清晰）
- 貨物：8×8，遊戲內 2 倍顯示
- 建築：礦機（鑽頭＋礦石底座）／傳送帶（路軌＋箭頭，4 方向 × 2 動畫格）／合成爐（煙囪＋火焰 2 格）／齒輪機（圓形齒輪）／組裝台（機械臂）／出口（發光箱）
- 貨物：礦、錠、齒輪、零件（4×4）
- 地板與礦脈各一張

改美術：改 `gen_art.py` 入面嘅 ASCII 圖（`.` 透明、`k` 外框、其餘見 PALETTE），再跑：

```powershell
python tools/gen_art.py
python tools/preview_art.py
```

> 遊戲載入貼圖時會先試 Godot 匯入系統，未匯入（例如未開過編輯器）就即場解 PNG，
> 所以 headless 測試同 CI 都跑得到。開過一次編輯器之後就會用 `.import` 嘅正路。

## 分支策略

| 分支 | 用途 |
|---|---|
| `main` | 穩定版本，只收「測試全綠 + 實機驗證過」嘅改動 |
| `dev` | 開發／實驗，日常改動都喺呢度 |

穩定版本用 tag 標記（現時：`v0.1-slice`），想回到某個狀態就 `git checkout <tag>`。

### 防止手滑推上 main

repo 有一個 `pre-push` hook：推上 `main` 的 commit 必須已經存在於 `dev`（即係「合併 dev → main」之後才推）。
在 main 上直接改東西、刪除 main、force-push 分歧的 main 都會被擋。

```powershell
# 新機安裝 hook
powershell -ExecutionPolicy Bypass -File tools/install-hooks.ps1

# 真係要硬推（會跳過檢查）
$env:ALLOW_MAIN_PUSH=1; git push

# 如果 hook 壞咗，暫時停用
Remove-Item .git/hooks/pre-push
```

## 文件

- [DESIGN-SPEC.md](DESIGN-SPEC.md) — 鎖定規則、平衡數字、每次改動嘅原因
- [analysis-time-loop-automation.md](analysis-time-loop-automation.md) — 最初的方案分析