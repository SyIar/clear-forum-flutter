"""Check that application UI uses public Apple APIs without retired UI dependencies."""
from pathlib import Path
import json
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
folders = ['native/App', 'native/Tieba/App', 'native/NativeUI']
for folder in folders:
    for path in (root / folder).glob('*.swift'):
        source = path.read_text(encoding='utf-8')
        for retired in ['import ChunUI', 'import Pow', 'forumSymbol:', 'ForumIcons',
                        'ForumToolbarGroup', 'ForumDesignSystem', 'ForumRefreshFeedback',
                        'CCShaders', 'CAFilter', 'VariableBlur', 'ForumPresentationHost',
                        'forumDismiss', '.forumSheet(']:
            assert retired not in source, f'{path.name}: retired UI API {retired}'
project = (root / 'native/project.yml').read_text(encoding='utf-8')
assert 'ChunUI' not in project and 'Pow:' not in project
assert '- NativeUI' in project
assert project.count('- target: ForumUI') == 2
assert not any(path.is_file() for path in (root / 'native/DesignSystem').rglob('*')), 'Retired UI resources remain'
print('Native UI dependency, public API, and framework checks passed')

# Verify real catalog availability on the macOS build host. This catches silent
# missing images, including legacy semantic aliases that are not SF Symbols.
symbols = set()
for folder in folders + ['native/Core']:
    for path in (root / folder).glob('*.swift'):
        source = path.read_text(encoding='utf-8')
        for match in re.finditer(r'\b(?:systemName|systemImage|symbol):\s*|\bvar symbol:\s*String\s*\{', source):
            start = match.end()
            block = match.group().endswith('{')
            depth = 0
            quoted = False
            escaped = False
            end = start
            for end in range(start, len(source)):
                char = source[end]
                if quoted:
                    if escaped:
                        escaped = False
                    elif char == '\\':
                        escaped = True
                    elif char == '"':
                        quoted = False
                elif char == '"':
                    quoted = True
                elif char in '({[':
                    depth += 1
                elif char in ')}]':
                    if depth == 0:
                        break
                    depth -= 1
                elif char == ',' and depth == 0 and not block:
                    break
                elif char == '\n' and depth == 0 and not block:
                    break
            symbols.update(re.findall(r'"([a-z][a-z0-9.]*)"', source[start:end]))
if sys.platform == 'darwin':
    with tempfile.TemporaryDirectory(prefix='forum-native-symbols-') as directory:
        script = Path(directory) / 'symbols.swift'
        script.write_text('import AppKit\nlet symbols = ' + json.dumps(sorted(symbols)) + '\n'
            'let missing = symbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }\n'
            'precondition(missing.isEmpty, "Missing system symbols: \\(missing)")\n'
            'print("Validated \\(symbols.count) system symbols against the Apple catalog")\n', encoding='utf-8')
        subprocess.run(['swift', str(script)], check=True)
else:
    print(f'Apple catalog validation for {len(symbols)} symbols runs on macOS CI')
