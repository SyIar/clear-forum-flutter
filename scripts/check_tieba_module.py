"""Validate resources and credential isolation at the native feature boundary."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
module = root / 'native/Tieba'
resources = module / 'Resources'
english = json.loads((resources / 'app_en.arb').read_text(encoding='utf-8'))
chinese = json.loads((resources / 'app_zh.arb').read_text(encoding='utf-8'))
assert {k for k in english if not k.startswith('@')} == {k for k in chinese if not k.startswith('@')}
references = set()
for path in (module / 'App').glob('*.swift'):
    text = path.read_text(encoding='utf-8')
    assert '@main' not in text, f'Unexpected second application entry point: {path.name}'
    references.update(re.findall(r'\btr\("([^"]+)"\)', text))
assert references <= chinese.keys(), f'Missing Tieba translations: {sorted(references - chinese.keys())}'
emoticons = json.loads((resources / 'emoticons_zh.arb').read_text(encoding='utf-8'))
assert emoticons and list((resources / 'emoticons').glob('*.webp'))
state = (module / 'App/AppState.swift').read_text(encoding='utf-8')
assert 'dev.sylar.forumlite.tieba.accounts' in state
assert 'flutter.tieba_lite.settings.' in state
assert '.nonPersistent()' in (module / 'App/BaiduBrowser.swift').read_text(encoding='utf-8')
assert 'TiebaResources.bundle.url' in state
assert not list(module.rglob('*.otf')), 'Do not duplicate the host font files'
print(f'Tieba module: {len(references)} text keys and isolated resource/session boundaries validated')
