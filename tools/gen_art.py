"""產生遊戲用嘅像素素材（20×20 版）。

建築：20×20 像素，1:1 對應遊戲格（20px），所以輪廓可以畫得清楚。
貨物：8×8，遊戲內放大 2 倍顯示。
地板：20×20，可平鋪。

全部用幾何繪製（Pillow），改外觀改下面每個 _draw_xxx() 就得。
    python tools/gen_art.py
    python tools/preview_art.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "game" / "art"
S = 20  # 建築畫格

K = (16, 20, 27, 255)        # 外框
SHADOW = (10, 13, 18, 255)

PAL = {
    "rock_d": (92, 80, 66, 255), "rock_l": (146, 128, 102, 255),
    "mine_d": (176, 104, 44, 255), "mine_l": (246, 168, 82, 255),
    "belt_d": (62, 76, 96, 255), "belt_l": (168, 196, 226, 255),
    "furn_d": (154, 54, 48, 255), "furn_l": (226, 96, 80, 255),
    "fire_d": (255, 150, 50, 255), "fire_l": (255, 226, 140, 255),
    "gear_d": (176, 156, 58, 255), "gear_l": (246, 226, 118, 255),
    "asm_d": (120, 92, 172, 255), "asm_l": (192, 164, 236, 255),
    "sink_d": (52, 138, 94, 255), "sink_l": (108, 226, 166, 255),
    "gnd_d": (30, 37, 47, 255), "gnd_l": (40, 49, 63, 255),
    "ore_d": (198, 168, 96, 255), "ore_l": (246, 214, 140, 255),
}


def canvas(size, bg=(0, 0, 0, 0)):
    im = Image.new("RGBA", (size, size), bg)
    return im, ImageDraw.Draw(im)


def rct(d, x0, y0, x1, y1, col, outline=K):
    """有 1px 外框嘅矩形（x1/y1 含）"""
    d.rectangle([x0 - 1, y0 - 1, x1 + 1, y1 + 1], fill=outline)
    d.rectangle([x0, y0, x1, y1], fill=col)


def ell(d, cx, cy, r, col, outline=K):
    d.ellipse([cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1], fill=outline)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)


def _draw_belt(frame):
    im, d = canvas(S)
    d.rectangle([0, 0, 19, 19], fill=K)
    d.rectangle([1, 1, 18, 18], fill=PAL["belt_d"])
    # 上下路軌
    d.rectangle([1, 2, 18, 4], fill=PAL["belt_l"])
    d.rectangle([1, 15, 18, 17], fill=PAL["belt_l"])
    # 中間暗坑
    d.rectangle([1, 5, 18, 14], fill=(48, 58, 74, 255))
    # 箭頭（每格移動 2px）
    off = 0 if frame == 0 else 2
    for i in range(3):
        x = 2 + i * 6 + off
        d.polygon([(x, 5), (x + 5, 9), (x + 5, 10), (x, 14)], fill=PAL["belt_l"])
        d.polygon([(x + 1, 6), (x + 5, 9), (x + 5, 10), (x + 1, 13)], fill=PAL["belt_l"])
    return im


def _draw_furnace(frame):
    im, d = canvas(S)
    # 機身
    rct(d, 2, 7, 17, 18, PAL["furn_d"])
    # 煙囪
    rct(d, 12, 1, 17, 7, PAL["furn_d"])
    d.rectangle([13, 1, 16, 2], fill=(60, 26, 24, 255))
    # 頂邊高光
    d.rectangle([3, 8, 16, 9], fill=PAL["furn_l"])
    # 爐窗
    d.rectangle([5, 11, 14, 17], fill=(46, 20, 18, 255))
    fire_l = PAL["fire_l"]
    fire_d = PAL["fire_d"]
    if frame == 0:
        d.polygon([(6, 17), (6, 14), (8, 12), (11, 12), (13, 14), (13, 17)], fill=fire_d)
        d.polygon([(8, 17), (8, 14), (10, 13), (11, 15), (11, 17)], fill=fire_l)
    else:
        d.polygon([(6, 17), (6, 13), (9, 12), (12, 14), (13, 17)], fill=fire_d)
        d.polygon([(9, 17), (9, 14), (11, 13), (12, 16), (12, 17)], fill=fire_l)
    # 鉚釘
    for x in (3, 16):
        d.point((x, 17), K)
    return im


def _draw_miner():
    im, d = canvas(S)
    # 底座岩石
    d.polygon([(0, 19), (0, 14), (4, 12), (15, 12), (19, 14), (19, 19)], fill=K)
    d.polygon([(1, 18), (1, 14), (4, 13), (15, 13), (18, 14), (18, 18)],
              fill=PAL["rock_d"])
    d.rectangle([3, 14, 16, 15], fill=PAL["rock_l"])
    # 礦石
    for (x, y) in ((3, 16), (15, 17), (6, 17)):
        d.point((x, y), PAL["ore_l"])
        d.point((x + 1, y), PAL["ore_d"])
    # 機身
    rct(d, 4, 4, 15, 12, PAL["mine_d"])
    d.rectangle([5, 5, 14, 6], fill=PAL["mine_l"])
    d.rectangle([6, 8, 13, 9], fill=(120, 66, 28, 255))
    # 鑽頭
    d.polygon([(8, 12), (11, 12), (10, 16), (9, 16)], fill=PAL["mine_l"], outline=K)
    # 側腳
    d.rectangle([1, 9, 3, 12], fill=K)
    d.rectangle([16, 9, 18, 12], fill=K)
    return im


def _draw_gear():
    im, d = canvas(S)
    cx = cy = 10
    import math
    # 齒：由中心伸出嘅粗條（同本體連住）
    for i in range(8):
        a = math.radians(i * 45)
        for t in range(3, 9):
            x = int(round(cx + math.cos(a) * t))
            y = int(round(cy + math.sin(a) * t))
            d.rectangle([x - 1, y - 1, x + 1, y + 1], fill=K)
    for i in range(8):
        a = math.radians(i * 45)
        for t in range(3, 8):
            x = int(round(cx + math.cos(a) * t))
            y = int(round(cy + math.sin(a) * t))
            d.point((x, y), PAL["gear_l"])
    # 本體
    ell(d, cx, cy, 7, PAL["gear_d"])
    ell(d, cx, cy, 6, PAL["gear_l"])
    # 中心孔
    ell(d, cx, cy, 2, (60, 52, 26, 255), outline=K)
    # 高光
    d.point((7, 6), PAL["gear_l"])
    return im


def _draw_assembler():
    im, d = canvas(S)
    # 底座
    rct(d, 2, 11, 17, 18, PAL["asm_d"])
    d.rectangle([3, 12, 16, 13], fill=PAL["asm_l"])
    # 機械臂
    rct(d, 12, 4, 15, 12, PAL["asm_d"])
    ell(d, 13, 4, 3, PAL["asm_l"])
    # 爪
    d.rectangle([8, 5, 12, 6], fill=K)
    d.rectangle([7, 6, 8, 8], fill=PAL["asm_l"])
    d.rectangle([11, 6, 12, 8], fill=PAL["asm_l"])
    # 面板
    d.rectangle([4, 15, 9, 17], fill=(46, 34, 66, 255))
    d.point((5, 16), PAL["sink_l"])
    d.point((7, 16), PAL["gear_l"])
    return im


def _draw_sink():
    im, d = canvas(S)
    # 箱體
    rct(d, 2, 4, 17, 18, PAL["sink_d"])
    # 內凹
    d.rectangle([5, 7, 14, 16], fill=(28, 62, 46, 255))
    # 發光入口
    d.rectangle([7, 9, 12, 14], fill=PAL["sink_l"])
    d.rectangle([8, 10, 11, 13], fill=(230, 255, 240, 255))
    # 上下輸送唇
    d.rectangle([3, 5, 16, 6], fill=PAL["sink_l"])
    d.rectangle([3, 16, 16, 17], fill=PAL["sink_l"])
    return im


def _draw_ground():
    im, d = canvas(S, PAL["gnd_d"])
    for (x, y) in ((3, 4), (11, 2), (16, 9), (6, 13), (14, 16), (2, 17), (9, 8)):
        d.point((x, y), PAL["gnd_l"])
    for (x, y) in ((7, 2), (17, 5), (4, 11)):
        d.point((x, y), (24, 30, 39, 255))
    return im


def _draw_ore():
    im, d = canvas(S)
    for (x, y, r) in ((6, 7, 2), (13, 12, 2), (8, 15, 1)):
        d.ellipse([x - r, y - r, x + r, y + r], fill=K)
        d.ellipse([x - r + 1, y - r + 1, x + r - 1, y + r - 1], fill=PAL["ore_d"])
        d.point((x, y - 1), PAL["ore_l"])
    return im


def _draw_item(kind):
    """8×8 貨物"""
    im, d = canvas(8)
    if kind == "ore":
        d.polygon([(1, 6), (3, 2), (6, 3), (7, 6)], fill=K)
        d.polygon([(2, 5), (3, 3), (5, 4), (6, 5)], fill=(255, 154, 74, 255))
        d.point((4, 4), (255, 210, 150, 255))
    elif kind == "ingot":
        d.rectangle([1, 3, 6, 6], fill=K)
        d.rectangle([2, 4, 5, 5], fill=(122, 212, 255, 255))
        d.point((3, 4), (220, 245, 255, 255))
    elif kind == "gear":
        d.ellipse([0, 0, 7, 7], fill=K)
        d.ellipse([1, 1, 6, 6], fill=(246, 226, 118, 255))
        d.ellipse([3, 3, 4, 4], fill=K)
    elif kind == "part":
        d.rectangle([1, 2, 6, 6], fill=K)
        d.rectangle([2, 3, 5, 5], fill=(109, 255, 160, 255))
        d.point((3, 4), (230, 255, 240, 255))
    return im


def gen():
    for sub in ("tiles", "buildings", "items"):
        (ART / sub).mkdir(parents=True, exist_ok=True)

    _draw_ground().save(ART / "tiles" / "ground.png")
    _draw_ore().save(ART / "tiles" / "ore.png")
    _draw_miner().save(ART / "buildings" / "miner.png")
    _draw_gear().save(ART / "buildings" / "gear.png")
    _draw_assembler().save(ART / "buildings" / "assembler.png")
    _draw_sink().save(ART / "buildings" / "sink.png")
    _draw_furnace(0).save(ART / "buildings" / "furnace_a.png")
    _draw_furnace(1).save(ART / "buildings" / "furnace_b.png")

    for tag, frame in (("a", 0), ("b", 1)):
        base = _draw_belt(frame)
        for name, angle in (("e", 0), ("n", 90), ("w", 180), ("s", 270)):
            rot = base.rotate(angle, expand=False) if angle else base
            rot.save(ART / "buildings" / f"belt_{name}_{tag}.png")

    for kind in ("ore", "ingot", "gear", "part"):
        _draw_item(kind).save(ART / "items" / f"{kind}.png")

    files = sorted(p.relative_to(ART).as_posix() for p in ART.rglob("*.png"))
    print(f"generated {len(files)} files (buildings/tiles {S}x{S}, items 8x8)")
    for f in files:
        print("  ", f)


if __name__ == "__main__":
    gen()