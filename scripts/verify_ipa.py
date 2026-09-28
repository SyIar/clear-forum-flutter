import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None, 'Corrupt IPA'
    required = {'Payload/Runner.app/Info.plist', 'Payload/Runner.app/Runner', 'Payload/Runner.app/Frameworks/App.framework/App', 'Payload/Runner.app/Frameworks/Flutter.framework/Flutter', 'Payload/Runner.app/MediaProbe.js'}
    assert required.issubset(archive.namelist()), 'Missing app components'
    info = plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
    assert info['CFBundleIdentifier'] == 'dev.sylar.clearforum', 'Unexpected app identity'
    assert info.get('DTPlatformName') == 'iphoneos', 'Not a device build'
    assert info['CFBundleDisplayName'] == 'simp lite', 'Unexpected app name'
    print(f"Verified simp lite {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")
