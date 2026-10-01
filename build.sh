#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "Building Cat Eye..."
mkdir -p CatEye.app/Contents/MacOS
cp Info.plist CatEye.app/Contents/Info.plist
swiftc -Osize -o CatEye.app/Contents/MacOS/cat-eye *.swift -framework Cocoa -framework UserNotifications -framework Network
# The relay Worker source. Cat Eye copies it to ~/.config/cat-eye/relay at setup.
rm -rf CatEye.app/Contents/Resources/worker
mkdir -p CatEye.app/Contents/Resources/worker
cp -R worker/src worker/wrangler.jsonc CatEye.app/Contents/Resources/worker/
# Only wrangler is needed at runtime. The test tools stay in the repo.
python3 -c "import json; p=json.load(open('worker/package.json')); p.pop('devDependencies', None); print(json.dumps(p, indent=2))" > CatEye.app/Contents/Resources/worker/package.json
strip CatEye.app/Contents/MacOS/cat-eye
# A real identity keeps Keychain "Always Allow" valid across rebuilds. Ad-hoc ("-") is the fallback.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
echo "Signing with: ${IDENTITY:-ad-hoc}"
codesign --force --deep --sign "${IDENTITY:--}" --timestamp=none CatEye.app
codesign --verify --deep --strict CatEye.app
echo "Done. $(ls -lh CatEye.app/Contents/MacOS/cat-eye | awk '{print $5}') binary"
echo "Run with: open CatEye.app"
