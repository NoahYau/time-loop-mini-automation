"""產生遊戲用嘅像素素材（可重跑）。

風格：10×10 像素、深色工業風、每個建築有 1px 深色外框 + 上方高光。
所有圖喺 game/art/ 之下，遊戲用 nearest filter 放大到 20px 顯示。

改美術：改下面嘅 ASCII 圖同 PALETTE，再跑：
    python tools/gen_art.py
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "game" / "art"

PALETTE = {
    ".": (0, 0, 0, 0),
    "k": (18, 23, 31, 255),      # 外框
    "r": (92, 80, 66, 255),      # 岩石暗
    "R": (146, 128, 102, 255),   # 岩石亮
    "o": (176, 104, 44, 255),    # 礦機暗
    "O": (246, 168, 82, 255),    # 礦機亮
    "b": (62, 76, 96, 255),      # 帶暗
    "B": (168, 196, 226, 255),   # 帶亮
    "f": (154, 54, 48, 255),     # 爐暗
    "F": (226, 96, 80, 255),     # 爐亮
    "y": (255, 150, 50, 255),    # 火暗
    "Y": (255, 214, 120, 255),   # 火亮
    "g": (176, 156, 58, 255),    # 齒輪機暗
    "G": (246, 226, 118, 255),   # 齒輪機亮
    "p": (120, 92, 172, 255),    # 組裝台暗
    "P": (192, 164, 236, 255),   # 組裝台亮
    "s": (52, 138, 94, 255),     # 出口暗
    "S": (108, 226, 166, 255),   # 出口亮
    "w": (30, 37, 47, 255),      # 地面暗
    "W": (39, 48, 61, 255),      # 地面亮
    "c": (200, 168, 96, 255),    # 礦石暗
    "C": (246, 214, 140, 255),   # 礦石亮
}

def img(rows):
    assert len(rows) == 10 and all(len(r) == 10 for r in rows), "每張圖要 10x10"
    im = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    px = im.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            px[x, y] = PALETTE[ch]
    return im

MINER = [
"kkkkkkkkkk",
"kOooooooOk",
"kOoOOOooOk",
"kOooooooOk",
"kkkkkkkkkk",
"kRrrrrrrRk",
"kRrrkrrrRk",
"kRrrrkrrRk",
"kRRRRRRRRk",
"kkkkkkkkkk",
]

BELT_E_A = [
"kkkkkkkkkk",
"kBBBBBBBBk",
"kbbbbbbBbk",
"kbbbbbBBbk",
"kbbbbBBBbk",
"kbbbbBBBbk",
"kbbbbbBBbk",
"kbbbbbbBbk",
"kBBBBBBBBk",
"kkkkkkkkkk",
]

BELT_E_B = [
"kkkkkkkkkk",
"kBBBBBBBBk",
"kbbBbbbbbk",
"kBbbBbbbbk",
"kBBbbBbbbk",
"kBBbbBbbbk",
"kBbbBbbbbk",
"kbbBbbbbbk",
"kBBBBBBBBk",
"kkkkkkkkkk",
]

FURNACE_A = [
"kkkkkkkkkk",
"kffffffffk",
"kfkkkkkkfk",
"kkkkkkkkkk",
"kFffffffFk",
"kffyyyyffk",
"kfyYYYYyfk",
"kffyyyyffk",
"kFffffffFk",
"kkkkkkkkkk",
]

FURNACE_B = [
"kkkkkkkkkk",
"kffffffffk",
"kfkkkkkkfk",
"kkkkkkkkkk",
"kFffffffFk",
"kffyYyyffk",
"kfyYYYyffk",
"kffyYyyffk",
"kFffffffFk",
"kkkkkkkkkk",
]

GEAR = [
"kkkkkkkkkk",
"kGgGgGgGgk",
"kGGGGGGGGk",
"kGgkkkkgGk",
"kGgkGGkgGk",
"kGgkGGkgGk",
"kGgkkkkgGk",
"kGGGGGGGGk",
"kGgGgGgGgk",
"kkkkkkkkkk",
]

ASSEMBLER = [
"kkkkkkkkkk",
"kPPPPPPPPk",
"kPppppppPk",
"kPpkkkkpPk",
"kPpkPPkpPk",
"kPpkkkkpPk",
"kPppppppPk",
"kPPPPPPPPk",
"kPppppppPk",
"kkkkkkkkkk",
]

SINK = [
"kkkkkkkkkk",
"kSSSSSSSSk",
"kSssssssSk",
"kSsSSSSsSk",
"kSsSssSsSk",
"kSsSssSsSk",
"kSsSSSSsSk",
"kSssssssSk",
"kSSSSSSSSk",
"kkkkkkkkkk",
]

GROUND = [
"wwwwwwwwww",
"wwWwwwwwww",
"wwwwwwwwww",
"wwwwwwwwww",
"wwwwwWwwww",
"wwwwwwwwww",
"wwwwwwwwww",
"wwWwwwwwww",
"wwwwwwwwww",
"wwwwwwwwww",
]

ORE = [
"..........",
"..........",
"...cc.....",
"..cCCc....",
"...cc.....",
".....cc...",
"....cCCc..",
".....cc...",
"..........",
"..........",
]

def gen():
    (ART / "tiles").mkdir(parents=True, exist_ok=True)
    (ART / "buildings").mkdir(parents=True, exist_ok=True)
    (ART / "items").mkdir(parents=True, exist_ok=True)

    img(GROUND).save(ART / "tiles" / "ground.png")
    img(ORE).save(ART / "tiles" / "ore.png")
    img(MINER).save(ART / "buildings" / "miner.png")
    img(GEAR).save(ART / "buildings" / "gear.png")
    img(ASSEMBLER).save(ART / "buildings" / "assembler.png")
    img(SINK).save(ART / "buildings" / "sink.png")
    img(FURNACE_A).save(ART / "buildings" / "furnace_a.png")
    img(FURNACE_B).save(ART / "buildings" / "furnace_b.png")

    # 傳送帶：先畫向東，再旋轉出四個方向（每方向兩格動畫）
    for tag, rows in (("a", BELT_E_A), ("b", BELT_E_B)):
        base = img(rows)
        for name, angle in (("e", 0), ("n", 90), ("w", 180), ("s", 270)):
            rot = base.rotate(angle, expand=False) if angle else base
            rot.save(ART / f"buildings" / f"belt_{name}_{tag}.png")

    def item(rows4, colors, fname):
        im = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
        px = im.load()
        for y, row in enumerate(rows4):
            for x, ch in enumerate(row):
                px[x, y] = colors.get(ch, (0, 0, 0, 0))
        im.save(ART / "items" / fname)

    OUTLINE = PALETTE["k"]
    item([
        ".kk.",
        "kOOk",
        "kook",
        ".kk.",
    ], {"O": (255, 154, 74, 255), "o": (198, 108, 46, 255), "k": OUTLINE}, "ore.png")
    item([
        ".kk.",
        "kIIk",
        "kiik",
        ".kk.",
    ], {"I": (122, 212, 255, 255), "i": (58, 130, 170, 255), "k": OUTLINE}, "ingot.png")
    item([
        ".kk.",
        "kGGk",
        "kggk",
        ".kk.",
    ], {"G": (255, 215, 90, 255), "g": (176, 140, 40, 255), "k": OUTLINE}, "gear.png")
    item([
        ".kk.",
        "kPPk",
        "kppk",
        ".kk.",
    ], {"P": (109, 255, 160, 255), "p": (44, 150, 96, 255), "k": OUTLINE}, "part.png")

    files = sorted(p.relative_to(ART).as_posix() for p in ART.rglob("*.png"))
    print(f"generated {len(files)} files:")
    for f in files:
        print("  ", f)

if __name__ == "__main__":
    gen()