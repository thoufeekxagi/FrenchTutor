#!/usr/bin/env python3
"""Prepare ParleSprint logo assets from the supplied lossless raster artwork.

The SVG files intentionally embed PNG data. This preserves the source
gradients and pixels instead of tracing them into an approximate vector.
"""

from __future__ import annotations

import base64
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[3]
BRANDING = Path(__file__).resolve().parent
SOURCE = BRANDING / "parlesprint-logo-source-2026-10-13.png"
IMAGES = ROOT / "flutter_app/assets/images"
RES = ROOT / "flutter_app/android/app/src/main/res"
IOS = ROOT / "flutter_app/ios/Runner/Assets.xcassets"
WEB = ROOT / "flutter_app/web"

RESAMPLE = Image.Resampling.LANCZOS


def png_data_uri(image: Image.Image) -> str:
    stream = io.BytesIO()
    image.save(stream, format="PNG", optimize=False)
    return "data:image/png;base64," + base64.b64encode(stream.getvalue()).decode("ascii")


def svg_wrapper(title: str, description: str, image: Image.Image) -> str:
    width, height = image.size
    uri = png_data_uri(image)
    return _svg_with_uri(title, description, width, height, uri)


def svg_from_png(title: str, description: str, path: Path) -> str:
    with Image.open(path) as image:
        width, height = image.size
    uri = "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")
    return _svg_with_uri(title, description, width, height, uri)


def _svg_with_uri(title: str, description: str, width: int, height: int, uri: str) -> str:
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">
  <title id="title">{title}</title>
  <desc id="desc">{description}</desc>
  <image width="{width}" height="{height}" href="{uri}" />
</svg>
'''


def extract_mark(source: Image.Image) -> Image.Image:
    """Remove the white card/background while retaining the colored artwork."""
    rgb = source.convert("RGB")
    pixels = np.asarray(rgb, dtype=np.float32)
    maximum = pixels.max(axis=2)
    minimum = pixels.min(axis=2)
    saturation = np.divide(
        maximum - minimum,
        maximum,
        out=np.zeros_like(maximum),
        where=maximum > 0,
    )

    # The mark's opaque gradient has saturation above 0.2; the card and its
    # shadow are below that threshold. Expand the mark by two source pixels
    # solely to retain antialiased edge pixels.
    core = Image.fromarray((saturation > 0.2).astype(np.uint8) * 255)
    expanded = np.asarray(core.filter(ImageFilter.MaxFilter(5))) > 0
    edge = expanded & (saturation > 0.004)

    alpha = np.zeros_like(maximum, dtype=np.uint8)
    alpha[saturation > 0.2] = 255

    # The source edges were antialiased against white. Unmatting them using
    # the minimum channel preserves their appearance on white while avoiding
    # a white fringe when the transparent mark is shown on another surface.
    edge_only = edge & (saturation <= 0.2)
    edge_alpha = np.clip(255.0 - minimum, 0.0, 255.0)
    alpha[edge_only] = np.rint(edge_alpha[edge_only]).astype(np.uint8)

    out_rgb = pixels.copy()
    non_opaque = (alpha > 0) & (alpha < 255)
    a = alpha[non_opaque].astype(np.float32)[:, None] / 255.0
    out_rgb[non_opaque] = np.clip(
        (pixels[non_opaque] - (1.0 - a) * 255.0) / a,
        0.0,
        255.0,
    )
    out_rgb = np.rint(out_rgb).astype(np.uint8)

    rgba = Image.fromarray(np.dstack([out_rgb, alpha]))
    return rgba.crop(rgba.getchannel("A").getbbox())


def square_mark(mark: Image.Image, size: int = 512, fill: tuple[int, ...] = (0, 0, 0, 0)) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), fill)
    # The old UI logo is a square asset; the mark fills 86% of the canvas
    # height while preserving the supplied logo's original proportions.
    target_height = round(size * 0.86)
    target_width = round(mark.width * target_height / mark.height)
    resized = mark.resize((target_width, target_height), RESAMPLE)
    canvas.alpha_composite(resized, ((size - target_width) // 2, (size - target_height) // 2))
    return canvas


def save_png(image: Image.Image, path: Path, mode: str | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if mode:
        image = image.convert(mode)
    image.save(path, format="PNG", optimize=False)


def resize_icon(icon: Image.Image, size: int, mode: str) -> Image.Image:
    image = icon.resize((size, size), RESAMPLE)
    return image.convert(mode)


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Missing source artwork: {SOURCE}")

    source = Image.open(SOURCE).convert("RGB")
    if source.size != (1254, 1254):
        raise SystemExit(f"Expected the supplied 1254x1254 artwork, got {source.size}")

    mark = extract_mark(source)
    square = square_mark(mark)

    # Keep a lossless transparent mark for UI and splash screens.
    mark_path = IMAGES / "logo_mark.png"
    save_png(mark, mark_path)
    save_png(square, IMAGES / "pulse_sprint_logo.png")
    save_png(square, IMAGES / "parlesprint_logo.png")
    (IMAGES / "pulse_sprint_logo.svg").write_text(
        svg_from_png("ParleSprint logo mark", "The supplied blue, cyan, magenta and coral mark on transparency.", mark_path),
        encoding="utf-8",
    )
    (IMAGES / "parlesprint_logo.svg").write_text(
        svg_from_png("ParleSprint logo mark", "The supplied blue, cyan, magenta and coral mark on transparency.", mark_path),
        encoding="utf-8",
    )

    # This archival SVG embeds the original source PNG bytes unchanged at
    # their original dimensions. It is the pixel-identical SVG conversion.
    (BRANDING / "parlesprint-logo-source-2026-10-13.svg").write_text(
        svg_from_png(
            "ParleSprint supplied logo artwork",
            "Exact embedded copy of the user-supplied 1254 by 1254 PNG.",
            SOURCE,
        ),
        encoding="utf-8",
    )

    # The app icon uses the supplied white rounded tile and shadow, cropped
    # from the surrounding white canvas. Native app icons require a solid,
    # opaque square; platform-specific masks are applied by each OS.
    icon_box = 906
    left = (source.width - icon_box) // 2
    top = (source.height - icon_box) // 2
    app_icon = source.crop((left, top, left + icon_box, top + icon_box))
    save_png(resize_icon(app_icon, 512, "RGBA"), IMAGES / "pulse_sprint_app_icon.png")
    save_png(resize_icon(app_icon, 512, "RGBA"), IMAGES / "parlesprint_app_icon.png")
    (IMAGES / "pulse_sprint_app_icon.svg").write_text(
        svg_wrapper("ParleSprint app icon", "The supplied mark on its white rounded app tile.", app_icon),
        encoding="utf-8",
    )
    (IMAGES / "parlesprint_app_icon.svg").write_text(
        svg_wrapper("ParleSprint app icon", "The supplied mark on its white rounded app tile.", app_icon),
        encoding="utf-8",
    )

    # Native iOS app icons, at every size declared by the existing catalog.
    catalog = json.loads((IOS / "AppIcon.appiconset/Contents.json").read_text())
    for entry in catalog["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        logical_size = float(entry["size"].split("x")[0])
        scale = float(entry["scale"].removesuffix("x"))
        pixels = round(logical_size * scale)
        save_png(resize_icon(app_icon, pixels, "RGB"), IOS / "AppIcon.appiconset" / filename)

    # Android legacy mipmap launcher icons. Keep their opaque white tile.
    for density, pixels in {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }.items():
        save_png(resize_icon(app_icon, pixels, "RGBA"), RES / density / "ic_launcher.png")

    # Android launch drawables and iOS launch images use the transparent mark.
    for name in ("pulse_sprint_logo.png", "parlesprint_logo.png"):
        save_png(square, RES / "drawable-nodpi" / name)
    for size, name in (
        (128, "LaunchImage.png"),
        (256, "LaunchImage@2x.png"),
        (384, "LaunchImage@3x.png"),
    ):
        save_png(resize_icon(square, size, "RGBA"), IOS / "LaunchImage.imageset" / name)

    # Flutter web PWA icons and favicon.
    for size, name in (
        (192, "Icon-192.png"),
        (512, "Icon-512.png"),
        (192, "Icon-maskable-192.png"),
        (512, "Icon-maskable-512.png"),
    ):
        save_png(resize_icon(app_icon, size, "RGB"), WEB / "icons" / name)
    old_favicon = Image.open(WEB / "favicon.png")
    save_png(resize_icon(app_icon, old_favicon.width, "RGB"), WEB / "favicon.png")


if __name__ == "__main__":
    main()
