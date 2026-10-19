"""Build an App Store product-page header using the real ParleSprint screen.

The generated background is only decorative. The phone content is cropped
from the approved, genuine v3 course screenshot and is never AI-generated.
"""

from pathlib import Path
import shutil

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


HERE = Path(__file__).resolve().parent
BACKGROUND = HERE / "source" / "aso-header-background-generated.png"
COURSE_SCREEN = HERE / "01-tcf-canada-course.png"
APP_ICON = HERE.parents[1] / "assets" / "images" / "parlesprint_app_icon.png"
OUTPUT = HERE / "product-page-header-tcf-canada-clb7.png"
DOWNLOADS_OUTPUT = Path.home() / "Downloads" / "app-store-v3-submission" / OUTPUT.name

WIDTH, HEIGHT = 3840, 1646  # Apple product-page header: 21:9.
INK = (17, 24, 39)
MUTED = (75, 93, 119)
BLUE = (36, 99, 235)
PALE_BLUE = (212, 227, 249)
WHITE = (255, 255, 255)
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"


def main() -> None:
    for path in (BACKGROUND, COURSE_SCREEN, APP_ICON):
        if not path.exists():
            raise FileNotFoundError(path)

    background = Image.open(BACKGROUND).convert("RGB")
    canvas = ImageOps.fit(
        background,
        (WIDTH, HEIGHT),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )
    canvas = Image.blend(canvas, Image.new("RGB", canvas.size, WHITE), 0.06)

    # Compose a brand row with the production app icon.
    icon = Image.open(APP_ICON).convert("RGBA").resize(
        (128, 128), Image.Resampling.LANCZOS
    )
    canvas.paste(icon, (192, 142), icon)
    draw = ImageDraw.Draw(canvas)
    brand_font = ImageFont.truetype(FONT_BOLD, 48)
    brand_detail_font = ImageFont.truetype(FONT_REGULAR, 44)
    draw.text((352, 156), "PARLESPRINT", font=brand_font, fill=INK)
    brand_end = draw.textbbox((352, 156), "PARLESPRINT", font=brand_font)[2]
    draw.text((brand_end + 25, 158), "·  TCF CANADA", font=brand_detail_font, fill=BLUE)

    # Answer the learner's two questions immediately: who it is for and what
    # they can do. CLB 7+ is expressed as the learner's goal, not a guarantee.
    title_font = ImageFont.truetype(FONT_BOLD, 154)
    draw.text((204, 454), "French for", font=title_font, fill=INK)
    draw.text((204, 642), "TCF Canada", font=title_font, fill=INK)

    goal_font = ImageFont.truetype(FONT_BOLD, 83)
    draw.text((210, 918), "Build toward your CLB 7+ goal.", font=goal_font, fill=BLUE)

    detail_font = ImageFont.truetype(FONT_REGULAR, 51)
    draw.text(
        (212, 1072),
        "A guided A1–B2 path with practice in all four skills.",
        font=detail_font,
        fill=MUTED,
    )
    skills_font = ImageFont.truetype(FONT_BOLD, 37)
    draw.text(
        (214, 1190),
        "LISTENING   ·   SPEAKING   ·   READING   ·   WRITING",
        font=skills_font,
        fill=INK,
    )

    # The screen remains a real capture: remove only the campaign frame and
    # headings from the source image, then place the unretouched UI in a card.
    source = Image.open(COURSE_SCREEN).convert("RGB")
    if source.size != (1320, 2868):
        raise ValueError(f"Unexpected source screenshot size: {source.size}")
    screen = source.crop((142, 512, 1178, 2696))
    target_h = 1430
    target_w = round(screen.width * target_h / screen.height)
    screen = screen.resize((target_w, target_h), Image.Resampling.LANCZOS)
    x, y = 2910, 108
    frame_pad = 16
    frame_box = (x - frame_pad, y - frame_pad, x + target_w + frame_pad, y + target_h + frame_pad)

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (frame_box[0] + 4, frame_box[1] + 26, frame_box[2] + 4, frame_box[3] + 26),
        radius=54,
        fill=(20, 39, 72, 55),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(frame_box, radius=54, fill=WHITE, outline=PALE_BLUE, width=4)
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, screen.width - 1, screen.height - 1), radius=38, fill=255
    )
    canvas.paste(screen, (x, y), mask)

    # Small factual qualifier keeps the creative clear about its relationship
    # to the exam provider and immigration authority.
    footer_font = ImageFont.truetype(FONT_REGULAR, 29)
    footer = "Independent study · not affiliated with FEI or IRCC"
    ImageDraw.Draw(canvas).text((212, 1470), footer, font=footer_font, fill=MUTED)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUTPUT, format="PNG", optimize=True)
    DOWNLOADS_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(OUTPUT, DOWNLOADS_OUTPUT)
    print(f"Saved {OUTPUT} ({WIDTH}×{HEIGHT})")
    print(f"Copied {DOWNLOADS_OUTPUT}")


if __name__ == "__main__":
    main()
