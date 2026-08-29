from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / "assets" / "units" / "tanker.png").convert("RGBA")
canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
draw = ImageDraw.Draw(canvas)
draw.rounded_rectangle((8, 8, 248, 248), radius=54, fill=(15, 18, 29, 255), outline=(105, 118, 255, 255), width=8)
draw.ellipse((35, 42, 221, 228), fill=(77, 88, 190, 72))
source.thumbnail((166, 202), Image.Resampling.NEAREST)
x = (256 - source.width) // 2
y = 34 + (192 - source.height)
canvas.alpha_composite(source, (x, y))
canvas.save(ROOT / "assets" / "app_icon.png")
canvas.save(ROOT / "assets" / "app_icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("created assets/app_icon.png and assets/app_icon.ico")
