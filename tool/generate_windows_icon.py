"""Generate the Windows icon from the in-app Content Maker brand mark."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ICON_PATH = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
PREVIEW_PATH = ROOT / "windows" / "runner" / "resources" / "app_icon.png"
FONT_PATH = ROOT / "assets" / "fonts" / "BricolageGrotesque-800.ttf"

SIZE = 512
INK = "#16130D"
LIME = "#C9F63C"
CREAM = "#FAF7F1"


def point_on_circle(center: float, radius: float, angle: float) -> tuple[float, float]:
    radians = math.radians(angle)
    return (
        center + radius * math.cos(radians),
        center + radius * math.sin(radians),
    )


image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)

# A dark circular plate keeps the mark readable at 16px and on light taskbars.
draw.ellipse((18, 18, SIZE - 18, SIZE - 18), fill=INK)

center = SIZE / 2
radius = 174
stroke = 58
arc_bounds = (
    center - radius,
    center - radius,
    center + radius,
    center + radius,
)
start_angle = -146
end_angle = 143
draw.arc(arc_bounds, start=start_angle, end=end_angle, fill=LIME, width=stroke)

# Pillow arcs have square caps, so add the round caps used by the Flutter logo.
cap_radius = stroke / 2
for angle in (start_angle, end_angle):
    x, y = point_on_circle(center, radius, angle)
    draw.ellipse(
        (x - cap_radius, y - cap_radius, x + cap_radius, y + cap_radius),
        fill=LIME,
    )

# Keep a little more breathing room between the letter and the lime ring so the
# mark stays crisp when browsers reduce it to a 16 px favicon.
font = ImageFont.truetype(str(FONT_PATH), 224)
draw.text((center, center + 11), "M", font=font, fill=CREAM, anchor="mm")

image.save(PREVIEW_PATH)
image.save(
    ICON_PATH,
    format="ICO",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

print(f"Generated {ICON_PATH}")
