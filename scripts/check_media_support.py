import subprocess
import tempfile
from pathlib import Path

support = Path('ios/Runner/MediaSupport.swift').read_text(encoding='utf-8')
checks = Path('scripts/media_support_checks.swift').read_text(encoding='utf-8')
with tempfile.TemporaryDirectory(prefix='media-support-') as directory:
    source = Path(directory) / 'main.swift'
    binary = Path(directory) / 'checks'
    source.write_text(support + '\n' + checks, encoding='utf-8')
    subprocess.run(['swiftc', '-swift-version', '5', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
