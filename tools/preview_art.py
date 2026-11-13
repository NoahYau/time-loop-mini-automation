from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "game" / "art"
files = sorted(ART.rglob("*.png"))
SCALE, PAD, COLS = 8, 6, 5
cell = 20 * SCALE
rows = (len(files) + COLS - 1) // COLS
sheet = Image.new("RGBA", (COLS * (cell + PAD) + PAD, rows * (cell + PAD) + PAD), (26, 32, 42, 255))
for i, f in enumerate(files):
    im = Image.open(f).convert("RGBA")
    im = im.resize((cell, cell), Image.NEAREST)
    x = PAD + (i % COLS) * (cell + PAD)
    y = PAD + (i // COLS) * (cell + PAD)
    sheet.alpha_composite(im, (x, y))
sheet.save(ROOT / "art_preview.png")
print("saved", sheet.size)