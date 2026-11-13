extends RefCounted
## 全域平衡常數：改呢個檔就等於改難度曲線。

# --- 模擬核心 ---
const GRID_W: int = 16
const GRID_H: int = 16
const SIM_HZ: int = 30
const LOOP_TICKS: int = 1800          # 60 秒 × 30 Hz

# --- 三層配方（v1.2）---
# 礦 ->(爐) 錠 ->(齒輪機) 齒輪 ->(組裝台) 零件
# 每條線 60 秒實測 ~15 件零件；4 條線 = 60 = 勝利目標
const MINER_TICKS: int = 15           # 0.5s 產 1 礦 -> 120 礦 / 60s

const SMELT_TICKS: int = 30           # 2 礦 -> 1 錠，1s
const SMELT_IN: int = 2
const SMELT_CAP: int = 4

const GEAR_TICKS: int = 20            # 1 錠 -> 1 齒輪，0.67s
const GEAR_IN: int = 1
const GEAR_CAP: int = 4

const ASSEMBLE_TICKS: int = 80        # 4 齒輪 -> 1 零件，2.67s
const ASSEMBLE_IN: int = 4
const ASSEMBLE_CAP: int = 8

# --- 建築類型 ---
const T_NONE: int = 0
const T_MINER: int = 1
const T_BELT: int = 2
const T_FURNACE: int = 3
const T_GEAR: int = 4
const T_ASSEMBLER: int = 5
const T_SINK: int = 6

# --- 方向 ---
const D_N: int = 0
const D_E: int = 1
const D_S: int = 2
const D_W: int = 3
const DIR_VEC: Array = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

# --- 物品 ---
const ITEM_ORE: int = 0
const ITEM_INGOT: int = 1
const ITEM_GEAR: int = 2
const ITEM_PART: int = 3

# --- 礦脈（B 規則）：礦機只可以擺喺礦脈上，每條礦脈一行 ---
const ORE_X: int = 3
# 5 條礦脈，間距 3 格（16 行棋盤）
const ORE_LANES: Array = [2, 5, 8, 11, 14]

# --- 幽靈上限 ---
# 0 = 唔封頂。本作真正嘅上限係地圖：7 條礦脈 = 最多 7 條產線。
# 舊設定（剩餘 loop + 2）會喺 loop 7–8 逼你棄人 —— 即係落後嗰陣再踩你一腳。
# 將來某啲關卡想加難度，可以喺關卡參數設 GHOST_CAP > 0。
const GHOST_CAP: int = 0
const GHOST_SLACK: int = 2

# --- 循環 / 幽靈 / 行動點 ---
const LOOP_LIMIT: int = 8
const AP_MAX: int = 12
const AP_COST_BUILD: int = 1
const AP_COST_DEMOLISH_OWN: int = 1
const AP_COST_DEMOLISH_GHOST: int = 2
# 拆自己今個 loop 起嘅建築：退返 1 AP（即係搬位/改位淨成本 0）。
# 拆幽靈嘅建築冇退款 —— 果 2 AP 代表「你要重做佢做過嘅嘢」，唔係消費。
const AP_REFUND_DEMOLISH_OWN: int = 1
const BUILD_TICKS: int = 15            # 落一件建築佔用你 0.5 秒

# --- AP 隨時間回復 ---
# 每 AP_REGEN_TICKS 個 tick 回 AP_REGEN_AMOUNT 點，上限仍然係 AP_MAX。
# 300 tick = 10 秒 -> 一個 60 秒 loop 最多回 6 點（總開支 12 -> 18）。
const AP_REGEN_TICKS: int = 300
const AP_REGEN_AMOUNT: int = 1
# 16x16 棋盤有 5 條礦脈；一條線 60 秒約 13 件。
# 目標 48 = 一定要 4 條線（3 條 39 唔夠），仲有 1 條備用賽道。
const WIN_TARGET: int = 48

# --- 命令種類 ---
const C_BUILD: int = 0
const C_DEMOLISH: int = 1