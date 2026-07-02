#!/usr/bin/env python3
"""Generate cmux logo and app icon assets from a single source image."""

import argparse
import base64
import json
import os
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


REPO = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = REPO / "design" / "cmux-logo-source.png"

MAC_SIZES = [
    ("16.png", 16),
    ("16@2x.png", 32),
    ("32.png", 32),
    ("32@2x.png", 64),
    ("128.png", 128),
    ("128@2x.png", 256),
    ("256.png", 256),
    ("256@2x.png", 512),
    ("512.png", 512),
    ("512@2x.png", 1024),
]

BANNER_COLORS = {
    "DEV": (255, 107, 0, 255),
    "NIGHTLY": (140, 60, 220, 255),
}


def load_source(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def fit_square(image: Image.Image, size: int, padding_fraction: float = 0.0) -> Image.Image:
    """Fit the full artwork on a transparent square canvas."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    target = int(size * (1.0 - padding_fraction * 2.0))
    target = max(1, target)
    fitted = ImageOps.contain(image, (target, target), Image.Resampling.LANCZOS)
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2
    canvas.alpha_composite(fitted, (x, y))
    return canvas


def font_for_size(size: int, label: str) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    font_size = max(6, int(size * (0.105 if len(label) > 3 else 0.13)))
    for font_path in [
        "/System/Library/Fonts/SFCompact-Bold.otf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]:
        if os.path.exists(font_path):
            try:
                return ImageFont.truetype(font_path, font_size)
            except Exception:
                continue
    return ImageFont.load_default()


def add_banner(image: Image.Image, label: str) -> Image.Image:
    result = image.copy()
    draw = ImageDraw.Draw(result)
    width, height = result.size
    banner_height = max(3, int(height * 0.18))
    y0 = height - banner_height
    draw.rectangle([0, y0, width, height], fill=BANNER_COLORS[label])

    font = font_for_size(height, label)
    bbox = draw.textbbox((0, 0), label, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (width - text_width) / 2 - bbox[0]
    y = y0 + (banner_height - text_height) / 2 - bbox[1]
    draw.text((x, y), label, fill=(255, 255, 255, 255), font=font)
    return result


def write_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")


def write_mac_icon_set(icon_set: str, source: Image.Image, label: str | None = None) -> None:
    icon_dir = REPO / "Assets.xcassets" / f"{icon_set}.appiconset"
    for filename, size in MAC_SIZES:
        image = fit_square(source, size)
        if label is not None:
            image = add_banner(image, label)
        write_png(icon_dir / filename, image)


def write_release_dark_variants(source: Image.Image) -> None:
    icon_dir = REPO / "Assets.xcassets" / "AppIcon.appiconset"
    for filename, size in MAC_SIZES:
        base, ext = os.path.splitext(filename)
        write_png(icon_dir / f"{base}_dark{ext}", fit_square(source, size))


def write_app_images(source: Image.Image) -> None:
    light = fit_square(source, 1024)
    write_png(REPO / "Assets.xcassets" / "AppIconLight.imageset" / "AppIconLight.png", light)
    write_png(REPO / "Assets.xcassets" / "AppIconDark.imageset" / "AppIconDark.png", light)

    write_png(REPO / "ios" / "cmux" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png", light)
    write_png(REPO / "ios" / "cmux" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIconDark.png", light)
    write_png(REPO / "ios" / "cmux" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIconTinted.png", light)
    write_png(REPO / "ios" / "cmux" / "Assets.xcassets" / "CmuxLogo.imageset" / "cmux-logo.png", light)


def update_ios_logo_contents() -> None:
    contents_path = REPO / "ios" / "cmux" / "Assets.xcassets" / "CmuxLogo.imageset" / "Contents.json"
    contents = {
        "images": [
            {
                "filename": "cmux-logo.png",
                "idiom": "universal",
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }
    contents_path.write_text(json.dumps(contents, indent=2) + "\n")


def write_web_assets(source: Image.Image) -> None:
    base = fit_square(source, 1024)
    nightly = add_banner(base, "NIGHTLY")
    write_png(REPO / "web" / "public" / "logo.png", base)
    write_png(REPO / "web" / "public" / "logo-nightly.png", nightly)
    write_png(REPO / "web" / "public" / "brand" / "app-icon-light.png", base)
    write_png(REPO / "web" / "public" / "brand" / "app-icon-dark.png", base)

    buffer_path = REPO / "web" / "public" / "logo.png"
    encoded = base64.b64encode(buffer_path.read_bytes()).decode("ascii")
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
        'role="img" aria-labelledby="title">\n'
        '  <title id="title">cmux icon</title>\n'
        f'  <image href="data:image/png;base64,{encoded}" width="1024" height="1024" />\n'
        '</svg>\n'
    )
    (REPO / "web" / "public" / "cmux-icon.svg").write_text(svg)


def update_icon_composer_json() -> None:
    for icon_json in [
        REPO / "AppIcon.icon" / "icon.json",
        REPO / "design" / "cmux.icon" / "icon.json",
    ]:
        if not icon_json.exists():
            continue
        contents = json.loads(icon_json.read_text())
        for group in contents.get("groups", []):
            for layer in group.get("layers", []):
                layer["image-name"] = "cmux-logo-source.png"
                layer["name"] = "cmux logo"
                layer["position"] = {
                    "scale": 1,
                    "translation-in-points": [0, 0],
                }
        icon_json.write_text(json.dumps(contents, indent=2) + "\n")


def write_icon_composer_assets() -> None:
    for assets_dir in [
        REPO / "AppIcon.icon" / "Assets",
        REPO / "design" / "cmux.icon" / "Assets",
    ]:
        if assets_dir.exists():
            shutil.copyfile(DEFAULT_SOURCE, assets_dir / "cmux-logo-source.png")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE,
        help="Path to the source logo image.",
    )
    args = parser.parse_args()

    source_path = args.source.expanduser().resolve()
    if source_path != DEFAULT_SOURCE.resolve():
        DEFAULT_SOURCE.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_path, DEFAULT_SOURCE)
        source_path = DEFAULT_SOURCE

    source = load_source(source_path)
    write_mac_icon_set("AppIcon", source)
    write_release_dark_variants(source)
    write_mac_icon_set("AppIcon-Debug", source, label="DEV")
    write_mac_icon_set("AppIcon-Nightly", source, label="NIGHTLY")
    write_app_images(source)
    update_ios_logo_contents()
    write_web_assets(source)
    write_icon_composer_assets()
    update_icon_composer_json()


if __name__ == "__main__":
    main()
