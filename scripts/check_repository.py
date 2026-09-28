import re
import subprocess
from pathlib import Path

paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard'], text=True).splitlines()
failures = []
for name in set(paths):
    path = Path(name)
    if not path.is_file() or path.suffix.lower() in {'.md', '.sql', '.png', '.ico'}:
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    if re.search(r'[\u3400-\u4dbf\u4e00-\u9fff]', text):
        failures.append(f'{name}: unexpected Chinese text')
    if re.search(r'(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)', text):
        failures.append(f'{name}: potential credential')
    if path.suffix.lower() in {'.ipa', '.p12', '.mobileprovision'}:
        failures.append(f'{name}: private or generated artifact')
if failures:
    raise SystemExit('\n'.join(failures))
print(f'Repository policy checked: {len(set(paths))} files')
