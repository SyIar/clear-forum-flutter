import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
folder = root / 'native/Resources/zh-Hans.lproj'
pair = re.compile(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;')


def read_strings(path):
    source = path.read_text(encoding='utf-8')
    entries = {}
    for match in pair.finditer(source):
        key, value = map(json.loads, match.groups())
        assert key not in entries, f'Duplicate localization: {key}'
        assert value.strip(), f'Empty localization: {key}'
        assert key.count('%@') == value.count('%@'), f'Placeholder mismatch: {key}'
        assert re.search(r'[\u3400-\u9fff]', value), f'Expected Chinese translation: {key}'
        entries[key] = value
    assert not pair.sub('', source).strip(), f'Unparsed localization syntax: {path.name}'
    return entries


if __name__ == '__main__':
    entries = read_strings(folder / 'Localizable.strings')
    read_strings(folder / 'InfoPlist.strings')
    call = re.compile(r'AppText\.(?:text|format)\(("(?:[^"\\]|\\.)*")')
    references = set()
    for directory in ['native/App', 'native/Core']:
        for path in (root / directory).glob('*.swift'):
            source = path.read_text(encoding='utf-8')
            references.update(json.loads(match.group(1)) for match in call.finditer(source))
            if path.name == 'AppText.swift':
                helper_call = re.compile(r'\b(?:text|format)\(("(?:[^"\\]|\\.)*")')
                references.update(json.loads(match.group(1)) for match in helper_call.finditer(source))
    missing = references - entries.keys()
    assert not missing, f'Missing translations: {sorted(missing)}'
    print(f'Checked {len(entries)} Chinese translations and {len(references)} app text keys; placeholders preserved')
