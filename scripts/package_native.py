import hashlib
import json
import os
import plistlib
import struct
import subprocess
import zipfile
from pathlib import Path

app = Path('native/build/Build/Products/Release-iphoneos/ForumLite.app')
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'dev.sylar.clearforum'
assert info['CFBundleDisplayName'] == 'Forum Lite'
assert info['DTPlatformName'] == 'iphoneos'
assert info.get('NSPhotoLibraryAddUsageDescription'), 'Missing add-only Photos usage description'
assert info.get('UIFileSharingEnabled') is True, 'Missing Documents file sharing'
assert info.get('LSSupportsOpeningDocumentsInPlace') is True, 'Missing Files app document access'
binary = (app / info['CFBundleExecutable']).read_bytes()
assert struct.unpack('<II', binary[:8]) == (0xFEEDFACF, 0x0100000C), 'Expected arm64 Mach-O'
assert not any(p.name in {'Flutter.framework', 'App.framework', 'flutter_assets'} for p in app.rglob('*')), 'Unexpected Flutter runtime'
assert (app / 'MediaProbe.js').is_file(), 'Missing media compatibility script'
assert (app / 'Assets.car').is_file(), 'Missing app assets'
tieba = app / 'Frameworks/TiebaFeature.framework'
assert (tieba / 'TiebaFeature').is_file(), 'Missing native Tieba feature binary'
assert struct.unpack('<II', (tieba / 'TiebaFeature').read_bytes()[:8]) == (0xFEEDFACF, 0x0100000C), 'Expected arm64 Tieba framework'
for name in ['app_zh.arb', 'app_en.arb', 'emoticons_zh.arb', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'SwiftProtobuf-LICENSE.txt']:
    assert (tieba / name).is_file(), f'Missing Tieba resource: {name}'
    assert (tieba / name).read_bytes() == (Path('native/Tieba/Resources') / name).read_bytes(), f'Tieba resource differs: {name}'
for source in Path('native/Tieba/Resources/emoticons').iterdir():
    assert (tieba / 'emoticons' / source.name).read_bytes() == source.read_bytes(), f'Missing Tieba emoticon: {source.name}'
assert not list(tieba.rglob('*.otf')), 'Tieba should reuse the host fonts'
assert (app / 'ThirdPartyNotices.txt').is_file(), 'Missing dependency notice'
fonts = ['SourceHanSerifSC-Regular.otf', 'SourceHanSerifSC-Bold.otf']
assert sorted(info.get('UIAppFonts', [])) == sorted(fonts), 'Missing bundled font registration'
for name in fonts:
    source = Path('native/Resources/Fonts') / name
    bundled = app / name
    assert source.read_bytes()[:4] == b'OTTO', f'Expected an OTF font: {name}'
    assert bundled.is_file(), f'Missing bundled font: {name}'
    assert hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(bundled.read_bytes()).digest(), f'Font changed during packaging: {name}'
assert (app / 'SourceHanSerif-LICENSE.txt').is_file(), 'Missing bundled font license'
assert info.get('CFBundleDevelopmentRegion') == 'zh-Hans', f'Unexpected default app language: {info.get("CFBundleDevelopmentRegion")}'
for table in ['Localizable', 'InfoPlist']:
    localized = app / 'zh-Hans.lproj' / (table + '.strings')
    assert localized.is_file(), f'Missing Chinese resource: {table}'
    values = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(localized)]))
    assert values, f'Empty Chinese resource: {table}'
    if table == 'Localizable':
        from check_localization import read_strings
        assert values == read_strings(Path('native/Resources/zh-Hans.lproj/Localizable.strings')), 'Packaged translations differ from source'
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
