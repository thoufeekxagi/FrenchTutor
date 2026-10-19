"""Compose genuine iPad captures into the ParleSprint App Store layout.

The UI inside each screenshot is taken directly from the supplied iPad
captures. This script only resizes it proportionally and adds the same white,
pale-blue editorial frame and captions used by the iPhone creative set.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "source" / "ipad-10.5-inch-originals"
BACKGROUND = HERE / "source" / "aso-background.png"
OUT = HERE / "final"
OUT.mkdir(exist_ok=True)

W, H = 2048, 2732  # App Store Connect iPad 13-inch portrait size.
INK = (16, 24, 40)
MUTED = (81, 98, 121)
BLUE = (39, 101, 238)
PALE_BLUE = (210, 226, 249)
WHITE = (255, 255, 255)
FONT_REGULAR = "/System/Library/Fonts/SFNS.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

CAPTURES = [
    {
        "source": "IMG_0015.PNG",
        "output": "01-tcf-canada-course-ipad.png",
        "headline": "Learn French for\nTCF Canada",
        "caption": "A guided A1–B2 path for your exam goal.",
    },
    {
        "source": "IMG_0022.PNG",
        "output": "02-four-tcf-skills-ipad.png",
        "headline": "Practise all four\nTCF skills",
        "caption": "Listening, reading, writing and speaking, in one place.",
    },
    {
        "source": "IMG_0018.PNG",
        "output": "03-daily-tcf-routine-ipad.png",
        "headline": "Build a daily French\nroutine for TCF",
        "caption": "Short challenges, Stories, word review and Marie.",
    },
    {
        "source": "IMG_0019.PNG",
        "output": "04-tcf-bonjour-lesson-ipad.png",
        "headline": "Make every word stick\non your TCF path",
        "caption": "Start with bonjour: hear it, understand it, use it.",
    },
    {
        "source": "IMG_0020.PNG",
        "output": "05-tcf-vocabulary-check-ipad.png",
        "headline": "Make French vocabulary\nstick for TCF",
        "caption": "Quick meaning checks strengthen your French foundation.",
    },
    {
        "source": "IMG_0021.PNG",
        "output": "06-tcf-reading-in-context-ipad.png",
        "headline": "Read French in context",
        "caption": "Short stories build comprehension one page at a time.",
    },
]

def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)

def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return mask

def build(item: dict, index: int) -> Path:
    source_path = SOURCE / item["source"]
    with Image.open(source_path) as source_image:
        source = source_image.convert("RGB")
    if source.size != (1620, 2160):
        raise ValueError(f"{source_path.name}: expected 1620×2160, got {source.size}")

    # App Store iPad canvases are 4:3 portrait. Preserve the complete real
    # screenshot; the rounded frame is part of the surrounding creative only.
    background = Image.open(BACKGROUND).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
    canvas = background.copy()
    draw = ImageDraw.Draw(canvas)

    small_bold = font(FONT_BOLD, 31)
    small_regular = font(FONT_REGULAR, 31)
    headline_font = font(FONT_BOLD, 108)
    caption_font = font(FONT_REGULAR, 42)
    footer_font = font(FONT_REGULAR, 26)

    # Brand line and sequence marker.
    draw.ellipse((132, 72, 155, 95), fill=BLUE)
    draw.text((176, 62), "PARLESPRINT", font=small_bold, fill=INK)
    brand_width = draw.textbbox((0, 0), "PARLESPRINT", font=small_bold)[2]
    draw.text((176 + brand_width + 22, 62), "·  TCF CANADA", font=small_regular, fill=BLUE)
    badge = (1710, 57, 1912, 118)
    draw.rounded_rectangle(badge, radius=30, fill=(255, 255, 255), outline=PALE_BLUE, width=3)
    page = f"{index:02d} / {len(CAPTURES):02d}"
    page_box = draw.textbbox((0, 0), page, font=small_regular)
    draw.text((badge[0] + (badge[2] - badge[0] - page_box[2]) / 2, 70), page, font=small_regular, fill=MUTED)

    # Editorial headline and supporting copy, with the intentional line breaks
    # used by the matching iPhone artwork.
    title_xy = (132, 145)
    draw.multiline_text(title_xy, item["headline"], font=headline_font, fill=INK, spacing=3, stroke_width=1, stroke_fill=INK)
    title_box = draw.multiline_textbbox(title_xy, item["headline"], font=headline_font, spacing=3, stroke_width=1)
    caption_y = title_box[3] + 18
    draw.text((136, caption_y), item["caption"], font=caption_font, fill=MUTED)

    # Screenshot card: near-native resolution, with a quiet outline and soft
    # shadow. No generated or retouched pixels are placed inside the app UI.
    card_w, card_h = 1560, 2067
    card_x, card_y = (W - card_w) // 2, 500
    frame = 20
    inner_size = (card_w - frame * 2, card_h - frame * 2)
    screen = source.resize(inner_size, Image.Resampling.LANCZOS)

    shadow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    shadow_draw.rounded_rectangle(
        (card_x + 4, card_y + 18, card_x + card_w + 4, card_y + card_h + 18),
        radius=62,
        fill=(25, 55, 100, 32),
    )
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(24))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow_layer)
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        (card_x, card_y, card_x + card_w, card_y + card_h),
        radius=62,
        fill=WHITE,
        outline=PALE_BLUE,
        width=4,
    )
    screen_x, screen_y = card_x + frame, card_y + frame
    canvas.paste(screen, (screen_x, screen_y), rounded_mask(inner_size, 48))

    disclaimer = "Independent preparation. Not affiliated with FEI or IRCC."
    disclaimer_box = draw.textbbox((0, 0), disclaimer, font=footer_font)
    draw.text(((W - disclaimer_box[2]) / 2, 2632), disclaimer, font=footer_font, fill=MUTED)

    output_path = OUT / item["output"]
    canvas.convert("RGB").save(output_path, "PNG", optimize=True)
    return output_path

if __name__ == "__main__":
    for index, item in enumerate(CAPTURES, start=1):
        destination = build(item, index)
        print(f"{destination}  {Image.open(destination).size}")
