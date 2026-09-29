import hashlib
import json
import os
import plistlib
import struct
import zipfile
from pathlib import Path

app = Path('native/build/Build/Products/Release-iphoneos/ForumLite.app')
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'dev.sylar.clearforum'
assert info['CFBundleDisplayName'] == 'forum lite'
assert info['DTPlatformName'] == 'iphoneos'
assert info.get('NSPhotoLibraryAddUsageDescription'), 'Missing add-only Photos usage description'
assert info.get('UIFileSharingEnabled') is True, 'Missing Documents file sharing'
assert info.get('LSSupportsOpeningDocumentsInPlace') is True, 'Missing Files app document access'
binary = (app / info['CFBundleExecutable']).read_bytes()
assert struct.unpack('<II', binary[:8]) == (0xFEEDFACF, 0x0100000C), 'Expected arm64 Mach-O'
assert not any(p.name in {'Flutter.framework', 'App.framework', 'flutter_assets'} for p in app.rglob('*')), 'Unexpected Flutter runtime'
assert (app / 'MediaProbe.js').is_file(), 'Missing media compatibility script'
assert (app / 'Assets.car').is_file(), 'Missing app assets'
assert (app / 'ThirdPartyNotices.txt').is_file(), 'Missing dependency notice'
assert info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon'), 'Missing primary icon'
output = Path('artifacts/native')
output.mkdir(parents=True, exist_ok=True)
ipa = output / 'ForumLite-unsigned.ipa'
with zipfile.ZipFile(ipa, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        if path.is_file():
            archive.write(path, 'Payload/' + app.name + '/' + str(path.relative_to(app)).replace('\\', '/'))
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
(output / 'SHA256SUMS').write_text(f'{digest}  {ipa.name}\n')
(output / 'build-info.json').write_text(json.dumps({
    'name': info['CFBundleDisplayName'], 'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'], 'bundleId': info['CFBundleIdentifier'],
    'sourceCommit': os.environ.get('GITHUB_SHA'), 'runId': os.environ.get('GITHUB_RUN_ID'),
    'runtime': 'SwiftUI/UIKit', 'sha256': digest, 'bytes': ipa.stat().st_size,
}, indent=2) + '\n')
print(f'Verified native {info["CFBundleDisplayName"]} {info["CFBundleShortVersionString"]} ({info["CFBundleVersion"]}); no Flutter runtime')
