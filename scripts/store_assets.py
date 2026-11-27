"""Makes the App Store's screenshots from the app's screenshots.

The App Store wants screenshots for the 6.9" iPhone display (1320 x 2868). Each of the
app's screenshots is placed on a card that size, in the app's colours, with a caption
above it in Greek or English: the usual look of a store listing.

    python scripts/store_assets.py --shots <folder of full-size screenshots>

The screenshots come from the Screenshots workflow (Artifacts, "screenshots"), full
size; docs/screenshots has them shrunk for the README. The cards go into
fastlane/screenshots/<locale>, where fastlane's `deliver` uploads them from; it tells
the display from the size.
"""

import argparse
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "App" / "Resources" / "Fonts"
OUT = ROOT / "fastlane" / "screenshots"

LAKE = (14, 76, 109)
LAKE_MID = (22, 98, 127)
LAKE_LIGHT = (27, 115, 148)
OFF_WHITE = (247, 243, 234)
YELLOW = (242, 179, 61)
SOFT = (191, 214, 225)

# Which screenshots, in order, and what each says
SHOTS = [
    ("el-home.png", "Τα αστικά της Καστοριάς, στο κινητό σου", "Kastoria's city buses, on your phone"),
    ("el-stop.png", "Πότε έρχεται το επόμενο, σε κάθε στάση", "When the next bus comes, at every stop"),
    ("el-map-line.png", "Κάθε γραμμή στον χάρτη, με τα λεωφορεία της", "Every line on the map, with its buses"),
    ("el-line.png", "Όλο το ωράριο κάθε γραμμής", "Every line's full timetable"),
    ("el-route.png", "Πότε φτάνει το λεωφορείο σε κάθε στάση", "When the bus gets to each stop"),
    ("el-home-dark.png", "Και σε σκούρο θέμα", "In dark mode too"),
]
LOCALES = {"el": 1, "en-US": 2}
SIZE = (1320, 2868)


def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"commissioner_{weight}.ttf"), size)


def waves(img: Image.Image) -> None:
    """The lake's two waves along the bottom, like the app's splash"""
    w, h = img.size
    d = ImageDraw.Draw(img)
    for color, base, amp, phase in ((LAKE_MID, 0.80, 0.035, 0.0), (LAKE_LIGHT, 0.88, 0.03, 1.7)):
        pts = [(x, h * base + h * amp * math.sin(x / w * 2 * math.pi * 0.9 + phase)) for x in range(0, w + 1, 8)]
        d.polygon(pts + [(w, h), (0, h)], fill=color)


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def wrap(text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines, line = [], ""
    for word in text.split():
        test = f"{line} {word}".strip()
        if f.getlength(test) <= width or not line:
            line = test
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines


def card(shot: Path, caption: str, size: tuple[int, int]) -> Image.Image:
    w, h = size
    img = Image.new("RGB", size, LAKE)
    waves(img)
    d = ImageDraw.Draw(img)
    # The caption, centred, in the top part
    f = font("bold", int(w * 0.062))
    lines = wrap(caption, f, int(w * 0.84))
    line_h = int(f.size * 1.18)
    top = int(h * 0.06)
    for i, line in enumerate(lines):
        d.text(((w - f.getlength(line)) / 2, top + i * line_h), line, font=f, fill=OFF_WHITE)
    d.rounded_rectangle(((w - 90) / 2, top + len(lines) * line_h + 22, (w + 90) / 2, top + len(lines) * line_h + 32), 5, fill=YELLOW)
    # The screenshot below it, rounded, with a soft shadow
    screen = Image.open(shot).convert("RGB")
    sh = int(h * 0.70)
    sw = int(screen.width * sh / screen.height)
    screen = rounded(screen.resize((sw, sh), Image.LANCZOS), int(sw * 0.07))
    x = (w - sw) // 2
    y = h - sh - int(h * 0.05)
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 18, x + sw, y + sh + 18), int(sw * 0.07), fill=(0, 0, 0, 110))
    img.paste(shadow.filter(ImageFilter.GaussianBlur(28)), (0, 0), shadow.filter(ImageFilter.GaussianBlur(28)))
    img.paste(screen, (x, y), screen)
    return img


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--shots", type=Path, required=True, help="the full-size screenshots")
    args = parser.parse_args()
    for locale, index in LOCALES.items():
        folder = OUT / locale
        folder.mkdir(parents=True, exist_ok=True)
        for old in folder.glob("*.png"):
            old.unlink()
        n = 0
        for name, *captions in SHOTS:
            shot = args.shots / name
            if not shot.exists():
                print(f"  missing {name}, left out", file=sys.stderr)
                continue
            n += 1
            card(shot, captions[index - 1], SIZE).save(folder / f"{n}_iphone69.png", optimize=True)
        print(f"{locale}: {n} screenshots")
    return 0


if __name__ == "__main__":
    sys.exit(main())
