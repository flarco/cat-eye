#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "Building Cat Eye..."
mkdir -p CatEye.app/Contents/MacOS
cp Info.plist CatEye.app/Contents/Info.plist
# VERSION overrides the version in Info.plist (CI sets it from the release tag).
if [ -n "$VERSION" ]; then
  plutil -replace CFBundleVersion -string "$VERSION" CatEye.app/Contents/Info.plist
  plutil -replace CFBundleShortVersionString -string "$VERSION" CatEye.app/Contents/Info.plist
fi
# ARCHS="arm64 x86_64" builds a universal binary. The default is this Mac's arch.
BINS=()
for arch in ${ARCHS:-$(uname -m)}; do
  swiftc -Osize -target "$arch-apple-macos13.0" -o "CatEye.app/Contents/MacOS/cat-eye-$arch" *.swift \
    -framework Cocoa -framework UserNotifications -framework Network
  BINS+=("CatEye.app/Contents/MacOS/cat-eye-$arch")
done
lipo -create "${BINS[@]}" -output CatEye.app/Contents/MacOS/cat-eye
rm "${BINS[@]}"
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
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
  codesign --force --deep --sign - --timestamp=none CatEye.app
else
  # Notarization needs the hardened runtime and a secure timestamp. RELEASE=1 adds the timestamp.
  TS=--timestamp=none; [ "$RELEASE" = 1 ] && TS=--timestamp
  codesign --force --deep --options runtime $TS --sign "$IDENTITY" CatEye.app
fi
codesign --verify --deep --strict CatEye.app
echo "Done. $(ls -lh CatEye.app/Contents/MacOS/cat-eye | awk '{print $5}') binary"
echo "Run with: open CatEye.app"
