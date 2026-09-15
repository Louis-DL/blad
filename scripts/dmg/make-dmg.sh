#!/bin/zsh
# Builds Blad (Release) and packages it as dist/Blad-<version>.dmg with a designed install window.
# Usage: scripts/dmg/make-dmg.sh
# The first run asks for permission to control Finder, which lays out the window.
set -euo pipefail

ROOT=${0:A:h:h:h}
WORK=$(mktemp -d)
VOLUME="Blad"
trap 'hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

VERSION=$(xcodebuild -project "$ROOT/Blad.xcodeproj" -scheme Blad -configuration Release -showBuildSettings 2>/dev/null \
  | awk '/ MARKETING_VERSION / { print $3; exit }')
OUTPUT="$ROOT/dist/Blad-$VERSION.dmg"

echo "› Building Blad $VERSION"
xcodebuild -project "$ROOT/Blad.xcodeproj" -scheme Blad -configuration Release \
  -derivedDataPath "$WORK/build" build -quiet
APP="$WORK/build/Build/Products/Release/Blad.app"

echo "› Drawing the background"
xcrun swiftc -swift-version 5 -default-isolation MainActor -parse-as-library -O \
  "$ROOT/Blad/Design/Theme.swift" "$ROOT/Blad/Design/EditorFont.swift" "$ROOT/scripts/dmg/background.swift" \
  -o "$WORK/background"
mkdir -p "$WORK/art"
"$WORK/background" "$WORK/art"

echo "› Staging"
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Blad.app"
# Show "Blad" rather than "Blad.app" (unless someone's Finder shows all extensions).
xcrun SetFile -a E "$STAGE/Blad.app"
ln -s /Applications "$STAGE/Programma's"
# One TIFF holding both resolutions, so the window stays sharp on Retina screens.
tiffutil -cathidpicheck "$WORK/art/background.png" "$WORK/art/background@2x.png" -out "$STAGE/.background/background.tiff" 2>/dev/null

echo "› Laying out the window"
hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ -format UDRW -size 200m "$WORK/blad-rw.dmg" -quiet
hdiutil attach "$WORK/blad-rw.dmg" -readwrite -noverify -noautoopen -quiet

# Icon positions match DMGBackground.appIconCenter and applicationsIconCenter.
osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "Blad"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- 660 × 420 of content, plus the 32 pt title bar Finder counts in the bounds.
        set bounds of container window to {200, 120, 860, 572}
        set options to icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 112
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set extension hidden of item "Blad.app" to true
        set position of item "Blad.app" of container window to {180, 230}
        set position of item "Programma's" of container window to {480, 230}
        update without registering applications
        delay 1
        close
        open
        delay 1
        close
    end tell
end tell
APPLESCRIPT

chmod -Rf go-w "/Volumes/$VOLUME" 2>/dev/null || true
sync
hdiutil detach "/Volumes/$VOLUME" -quiet

echo "› Compressing"
mkdir -p "$ROOT/dist"
rm -f "$OUTPUT"
hdiutil convert "$WORK/blad-rw.dmg" -format ULFO -o "$OUTPUT" -quiet

echo "✓ $OUTPUT"
