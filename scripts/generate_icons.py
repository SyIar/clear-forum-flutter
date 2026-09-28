import json
from pathlib import Path
from PIL import Image, ImageDraw

# A code-drawn reading mark; no external artwork or font files.
image = Image.new('RGB', (1024, 1024), '#087FF5')
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((220, 220, 804, 804), radius=120, fill='white')
for y, width in [(355, 330), (475, 330), (595, 210)]:
    draw.rounded_rectangle((345, y, 345 + width, y + 55), radius=27, fill='#087FF5')
folder = Path('ios/Runner/Assets.xcassets/AppIcon.appiconset')
for entry in json.loads((folder / 'Contents.json').read_text())['images']:
    size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
    image.resize((size, size), Image.Resampling.LANCZOS).save(folder / entry['filename'])
for path in Path('web/icons').glob('*.png'):
    size = 512 if '512' in path.name else 192
    image.resize((size, size), Image.Resampling.LANCZOS).save(path)
image.resize((32, 32), Image.Resampling.LANCZOS).save('web/favicon.png')
