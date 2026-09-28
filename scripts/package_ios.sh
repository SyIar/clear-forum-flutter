#!/usr/bin/env bash
set -euo pipefail
app_path="build/ios/iphoneos/Runner.app"
test -f "$app_path/Runner"
test -f "$app_path/Frameworks/App.framework/App"
test "$(/usr/libexec/PlistBuddy -c 'Print :DTPlatformName' "$app_path/Info.plist")" = iphoneos
xcrun lipo -archs "$app_path/Runner" | tr ' ' '\n' | grep -qx arm64
stage_path="$(mktemp -d "$RUNNER_TEMP/clear-forum.XXXXXX")"
mkdir -p "$stage_path/Payload" artifacts
ditto "$app_path" "$stage_path/Payload/Runner.app"
(cd "$stage_path" && /usr/bin/zip -qry "$OLDPWD/artifacts/ClearForum-unsigned.ipa" Payload)
python3 scripts/verify_ipa.py artifacts/ClearForum-unsigned.ipa
(cd artifacts && shasum -a 256 ClearForum-unsigned.ipa > SHA256SUMS)
python3 - <<'PY'
import json, os, subprocess
from pathlib import Path
info = {
    'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'run_id': os.environ['GITHUB_RUN_ID'],
    'build_number': os.environ['GITHUB_RUN_NUMBER'],
    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'signing': 'Unsigned device build; re-sign locally before installation',
    'acceptance': 'Live iPhone login and reading are not verified by CI',
}
Path('artifacts/build-info.json').write_text(json.dumps(info, indent=2) + '\n')
PY
