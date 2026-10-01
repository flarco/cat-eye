#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "Building Cat Eye..."
# Remember where the running or installed copy lives, so the restart opens it.
RUNNING_APP="$(ps -axo comm= | sed -n 's#^\(.*\.app\)/Contents/MacOS/cat-eye$#\1#p' | head -1)"
if [ -z "$RUNNING_APP" ]; then
  for a in /Applications/CatEye.app "$HOME/Applications/CatEye.app"; do [ -d "$a" ] && RUNNING_APP="$a" && break; done
fi
mkdir -p CatEye.app/Contents/MacOS
cp Info.plist CatEye.app/Contents/Info.plist
# VERSION overrides the version in Info.plist (CI sets it from the release tag).
# Local builds get a "-dev" suffix, so the auto-updater never replaces them.
if [ -n "$VERSION" ]; then
  plutil -replace CFBundleVersion -string "$VERSION" CatEye.app/Contents/Info.plist
  plutil -replace CFBundleShortVersionString -string "$VERSION" CatEye.app/Contents/Info.plist
else
  plutil -replace CFBundleShortVersionString -string "$(plutil -extract CFBundleShortVersionString raw Info.plist)-dev" CatEye.app/Contents/Info.plist
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
# AppIcon.icns comes from AppIcon.svg. See CONTRIBUTING.md to make it again.
mkdir -p CatEye.app/Contents/Resources
cp AppIcon.icns CatEye.app/Contents/Resources/AppIcon.icns
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
# CI and release builds only package the app. NO_RESTART=1 does the same locally.
if [ -n "$CI" ] || [ "$RELEASE" = 1 ] || [ "$NO_RESTART" = 1 ]; then exit 0; fi
pkill -x cat-eye 2>/dev/null && sleep 0.5 || true
DEST="$PWD/CatEye.app"
# Refresh an installed copy only if it is a real directory with our bundle id.
# rsync --delete on the wrong target removes an unrelated app.
if [ -n "$RUNNING_APP" ] && [ "$RUNNING_APP" != "$DEST" ] && [ -d "$RUNNING_APP" ] && [ ! -L "$RUNNING_APP" ] &&
   [[ "$(defaults read "$RUNNING_APP/Contents/Info" CFBundleIdentifier 2>/dev/null)" =~ ^com\.(flarco|clintoncodewell)\.cateye$ ]]; then
  rsync -a --delete CatEye.app/ "$RUNNING_APP/"
  DEST="$RUNNING_APP"
fi
open "$DEST"
echo "Restarted: $DEST"
