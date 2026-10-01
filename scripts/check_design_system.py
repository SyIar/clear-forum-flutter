"""Check icon resource coverage and shared framework wiring before packaging."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
design = root / 'native/DesignSystem'
names = json.loads((design / 'PikaSymbolMap.json').read_text())
for name in names.values():
    folder = design / 'PikaIcons.xcassets' / (name + '.imageset')
    contents = json.loads((folder / 'Contents.json').read_text())
    assert contents['properties']['template-rendering-intent'] == 'template'
    for image in contents['images']:
        assert (folder / image['filename']).is_file(), f'Missing Pika SVG: {name}'
for folder in ['native/App', 'native/Tieba/App']:
    for path in (root / folder).glob('*.swift'):
        text = path.read_text(encoding='utf-8')
        assert 'systemName:' not in text and 'systemImage:' not in text, f'SF icon left in {path.name}'
        for name in re.findall(r'(?:forumSymbol:|ForumIcons.image\()\s*"([^"]+)"', text):
            assert name in names, f'Unmapped icon in {path.name}: {name}'
project = (root / 'native/project.yml').read_text()
assert project.count('- package: ChunUI') == 1, 'Link ChunUI once in the shared UI framework'
assert project.count('- target: ForumUI') == 2, 'Host and Tieba must use the same shared UI framework'
print(f'Design system: {len(names)} semantic icons, {len(set(names.values()))} SVG assets, shared framework wiring validated')
