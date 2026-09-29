import json
from pathlib import Path
from PIL import Image, ImageDraw

# Original geometric monogram. No downloaded artwork or font dependency.
icons = Path('ios/Runner/Assets.xcassets/AppIcon.appiconset')
scale = 2
image = Image.new('RGB', (1024 * scale, 1024 * scale))
draw = ImageDraw.Draw(image)
for y in range(1024 * scale):
    t = y / (1024 * scale - 1)
    color = tuple(round(a + (b - a) * t) for a, b in zip((15, 154, 202), (24, 80, 185)))
    draw.line((0, y, 1024 * scale, y), fill=color)

def rounded(box, radius):
    draw.rounded_rectangle(tuple(v * scale for v in box), radius=radius * scale, fill='white')

rounded((282, 225, 402, 801), 52)
rounded((282, 225, 753, 345), 52)
rounded((282, 466, 676, 582), 50)
manifest = json.loads((icons / 'Contents.json').read_text())
for entry in manifest['images']:
    size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
    image.resize((size, size), Image.Resampling.LANCZOS).save(icons / entry['filename'])
print('Rendered opaque Forum Lite icons at every catalog size.')
