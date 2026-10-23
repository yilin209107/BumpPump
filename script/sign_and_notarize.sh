#!/usr/bin/env bash
# Optional release operation. Requires the publisher's Developer ID and Keychain profile.
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo 'Usage: FITNESS_SIGN_IDENTITY="Developer ID Application: ..." FITNESS_NOTARY_PROFILE="profile" script/sign_and_notarize.sh /path/to/App.app'
  exit 0
fi
: "${FITNESS_SIGN_IDENTITY:?Set your Developer ID Application signing identity}"
: "${FITNESS_NOTARY_PROFILE:?Set an existing notarytool Keychain profile}"
APP="${1:?Provide the built .app path}"
[[ -d "$APP/Contents/MacOS" ]] || { echo 'Invalid app bundle' >&2; exit 2; }
APP="$(cd "$APP" && pwd)"
TEMP_RELEASE="$(mktemp -d)"
trap 'rm -rf "$TEMP_RELEASE"' EXIT
# Sign physical Mach-O files first. Ignore symlink aliases; include Python extensions.
python3 - "$APP" "$FITNESS_SIGN_IDENTITY" <<'PY'
from pathlib import Path
import subprocess,sys
app=Path(sys.argv[1]);identity=sys.argv[2]
magics={bytes.fromhex(v) for v in ['cffaedfe','feedfacf','cefaedfe','feedface','cafebabe','bebafeca','cafebabf','bfbafeca']}
for p in sorted(app.rglob('*'),key=lambda p:len(p.parts),reverse=True):
    if p.is_symlink() or not p.is_file():continue
    with p.open('rb') as f:magic=f.read(4)
    if magic in magics:
        subprocess.run(['codesign','--force','--timestamp','--options','runtime','--sign',identity,str(p)],check=True)
PY
codesign --force --timestamp --options runtime --sign "$FITNESS_SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$TEMP_RELEASE/Notarization.zip"
xcrun notarytool submit "$TEMP_RELEASE/Notarization.zip" --keychain-profile "$FITNESS_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
echo 'Signed, notarized and stapled. Repackage this exact app for release.'
