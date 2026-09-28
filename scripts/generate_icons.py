import json
from pathlib import Path
from PIL import Image

# Resize the checked-in opaque master; see docs/BRANDING.md for provenance.
image = Image.open('assets/branding/app-icon.png').convert('RGB')
assert image.width == image.height, 'The icon master must be square'
folder = Path('ios/Runner/Assets.xcassets/AppIcon.appiconset')
for entry in json.loads((folder / 'Contents.json').read_text())['images']:
    size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
    image.resize((size, size), Image.Resampling.LANCZOS).save(folder / entry['filename'])
for path in Path('web/icons').glob('*.png'):
    size = 512 if '512' in path.name else 192
    image.resize((size, size), Image.Resampling.LANCZOS).save(path)
image.resize((32, 32), Image.Resampling.LANCZOS).save('web/favicon.png')
