from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps
import shutil

ROOT = Path('/Users/thoufeekx/Desktop/Millionaire/FrenchTutor')
PACKAGE = ROOT / 'flutter_app/app_store_screenshots/v3-submission'
DOWNLOADS_PACKAGE = Path.home() / 'Downloads/app-store-v3-submission'
CAPTURES = Path.home() / 'Downloads/app-view-v3'
BACKGROUND = PACKAGE / 'source/generated-white-background.png'
FONT_BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
FONT_REGULAR = '/System/Library/Fonts/Supplemental/Arial.ttf'

SHOTS = [
    ('01-tcf-canada-course.png', 'shot_05_course_path.png',
     ('Learn French for', 'TCF Canada'),
     'A guided A1–B2 path for your exam goal.'),
    ('02-four-tcf-skills.png', 'shot_14_tests.png',
     ('Practise all four', 'TCF skills'),
     'Listening, reading, writing and speaking, in one place.'),
    ('03-daily-tcf-routine.png', 'shot_06_practice.png',
     ('Build a daily French', 'routine for TCF'),
     'Short challenges, Stories, word review and Marie.'),
    ('04-tcf-bonjour-lesson.png', 'shot_02_lesson_word.png',
     ('Make every word stick', 'on your TCF path'),
     'Start with bonjour: hear it, understand it, use it.'),
    ('05-tcf-listening.png', 'shot_15_exam_listening.png',
     ('Train your TCF', 'listening skills'),
     'Hear a French prompt and choose the best answer.'),
    ('06-tcf-reading.png', 'shot_16_exam_reading.png',
     ('Build confidence with', 'TCF reading'),
     'Read a passage, find the detail, then answer.'),
    ('07-tcf-writing-model.png', 'shot_17_exam_writing_model.png',
     ('See a TCF writing', 'model response'),
     'Learn how a clear B1 answer is put together.'),
]

INK = '#111827'
MUTED = '#52627A'
BLUE = '#2463EB'
PALE = '#D9E4F4'


def font_that_fits(lines, max_width=1130):
    probe = ImageDraw.Draw(Image.new('RGB', (1, 1)))
    for size in range(80, 63, -1):
        font = ImageFont.truetype(FONT_BOLD, size)
        if all(probe.textbbox((0, 0), line, font=font)[2] <= max_width for line in lines):
            return font
    return ImageFont.truetype(FONT_BOLD, 64)


def rounded_image(image, size, radius):
    image = ImageOps.fit(image, size, method=Image.Resampling.LANCZOS)
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return image, mask


def compose(index, filename, capture_name, title_lines, subtitle, background):
    source = CAPTURES / capture_name
    if not source.exists():
        raise FileNotFoundError(f'Missing iPhone capture: {source}')
    screenshot = Image.open(source).convert('RGB')
    if screenshot.size != (1284, 2778):
        raise ValueError(f'Unexpected capture dimensions for {source.name}: {screenshot.size}')

    canvas = background.copy()

    # Soft shadow and a clean, restrained device frame around the unaltered app capture.
    outer = (142, 512, 1178, 2696)
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((outer[0] + 2, outer[1] + 24, outer[2] + 2, outer[3] + 24), radius=48, fill=(23, 47, 83, 42))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    canvas = Image.alpha_composite(canvas.convert('RGBA'), shadow).convert('RGB')
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(outer, radius=48, fill='#FFFFFF', outline=PALE, width=3)

    inset = 22
    inner_x, inner_y = outer[0] + inset, outer[1] + inset
    inner_w = outer[2] - outer[0] - 2 * inset
    inner_h = round(inner_w * 2778 / 1284)
    image, mask = rounded_image(screenshot, (inner_w, inner_h), radius=32)
    canvas.paste(image, (inner_x, inner_y), mask)
    draw = ImageDraw.Draw(canvas)

    # Brand row and screenshot position.
    draw.ellipse((90, 72, 112, 94), fill=BLUE)
    brand = ImageFont.truetype(FONT_BOLD, 25)
    regular = ImageFont.truetype(FONT_REGULAR, 25)
    draw.text((130, 62), 'PARLESPRINT', font=brand, fill=INK)
    brand_right = draw.textbbox((130, 62), 'PARLESPRINT', font=brand)[2]
    draw.text((brand_right + 18, 62), '·', font=brand, fill=BLUE)
    draw.text((brand_right + 43, 62), 'TCF CANADA', font=regular, fill=BLUE)

    draw.rounded_rectangle((1118, 57, 1230, 105), radius=24, fill='#FFFFFF', outline=PALE, width=2)
    badge_font = ImageFont.truetype(FONT_REGULAR, 22)
    draw.text((1174, 81), f'{index:02d} / 07', font=badge_font, fill=MUTED, anchor='mm')

    title_font = font_that_fits(title_lines)
    y = 145
    for line in title_lines:
        draw.text((92, y), line, font=title_font, fill=INK)
        y = draw.textbbox((92, y), line, font=title_font)[3] + 7

    subtitle_font = ImageFont.truetype(FONT_REGULAR, 31)
    if draw.textbbox((0, 0), subtitle, font=subtitle_font)[2] > 1130:
        subtitle_font = ImageFont.truetype(FONT_REGULAR, 28)
    draw.text((92, 360), subtitle, font=subtitle_font, fill=MUTED)

    # Independent-preparation note, kept small and secondary to the app experience.
    footer_font = ImageFont.truetype(FONT_REGULAR, 20)
    footer = 'Independent preparation. Not affiliated with FEI or IRCC.'
    draw.text((660, 2773), footer, font=footer_font, fill=MUTED, anchor='mm')

    path = PACKAGE / filename
    canvas.save(path, format='PNG', optimize=True)
    shutil.copy2(path, DOWNLOADS_PACKAGE / filename)
    return path


PACKAGE.mkdir(parents=True, exist_ok=True)
DOWNLOADS_PACKAGE.mkdir(parents=True, exist_ok=True)
background = Image.open(BACKGROUND).convert('RGB')
if background.size != (1320, 2868):
    background = ImageOps.fit(background, (1320, 2868), method=Image.Resampling.LANCZOS)

outputs = [compose(i, *item, background) for i, item in enumerate(SHOTS, start=1)]

thumb_w = 400
thumb_h = round(2868 * thumb_w / 1320)
label_h = 44
cols = 3
rows = (len(outputs) + cols - 1) // cols
margin = 24
sheet = Image.new('RGB', (margin + cols * (thumb_w + margin), margin + rows * (thumb_h + label_h + margin)), '#EDF1F7')
label_font = ImageFont.truetype(FONT_REGULAR, 19)
for i, path in enumerate(outputs):
    x = margin + (i % cols) * (thumb_w + margin)
    y = margin + (i // cols) * (thumb_h + label_h + margin)
    image = Image.open(path).convert('RGB').resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
    sheet.paste(image, (x, y))
    ImageDraw.Draw(sheet).text((x, y + thumb_h + 10), f'{i + 1:02d} · {path.stem}', font=label_font, fill=INK)
(PACKAGE / 'preview').mkdir(exist_ok=True)
sheet.save(PACKAGE / 'preview/contact-sheet.png', format='PNG', optimize=True)
shutil.copy2(PACKAGE / 'preview/contact-sheet.png', DOWNLOADS_PACKAGE / 'preview/contact-sheet.png')

for path in outputs:
    print(path.name, Image.open(path).size)
