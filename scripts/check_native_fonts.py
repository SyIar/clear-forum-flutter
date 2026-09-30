"""Run the production cascade builder against CoreText without a simulator."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'native/App/MixedScriptFont.swift').read_text(encoding='utf-8')
checks = (root / 'scripts/check_native_fonts.swift').read_text(encoding='utf-8')
with tempfile.TemporaryDirectory(prefix='font-check-') as temporary:
    script = Path(temporary) / 'main.swift'
    script.write_text(source + '\n' + checks, encoding='utf-8')
    subprocess.run(['swift', str(script), str(root / 'native/Resources/Fonts')], cwd=root, check=True)
