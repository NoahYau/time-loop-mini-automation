# Time Loop Mini Automation

一個 2D 像素風的時間循環自動化小品（Godot 4.7 / GDScript）。
60 秒內鋪好產線、交出足夠零件；每次循環地圖重置，但你「過去嘅自己」會重播當年嘅建造動作。

## 玩法

- 每 loop 60 秒、12 AP（行動點），最多 8 個 loop
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