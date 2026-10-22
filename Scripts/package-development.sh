#!/bin/sh
set -eu
: "${KINDLE_MARGIN_BINARY:?Set the path to the built KindleMargin executable}"
: "${KINDLE_MARGIN_APP_OUTPUT:?Set a new absolute output .app path}"
case "$KINDLE_MARGIN_APP_OUTPUT" in /*.app) ;; *) echo 'Output must be an absolute .app path' >&2; exit 1;; esac
[ ! -e "$KINDLE_MARGIN_APP_OUTPUT" ] || { echo 'Output already exists; choose a new destination' >&2; exit 1; }
mkdir -p "$KINDLE_MARGIN_APP_OUTPUT/Contents/MacOS" "$KINDLE_MARGIN_APP_OUTPUT/Contents/Resources"
cp "$KINDLE_MARGIN_BINARY" "$KINDLE_MARGIN_APP_OUTPUT/Contents/MacOS/KindleMargin"
resource_bundle="$(dirname "$KINDLE_MARGIN_BINARY")/KindleMargin_KindleMargin.bundle"
if [ -d "$resource_bundle" ]; then cp -R "$resource_bundle" "$KINDLE_MARGIN_APP_OUTPUT/"; fi
cat > "$KINDLE_MARGIN_APP_OUTPUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.kindlemargin.development</string>
<key>CFBundleName</key><string>Kindle Margin</string>
<key>CFBundleExecutable</key><string>KindleMargin</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Development only: dynamic libraries retain their explicit local prefix.
# Release packaging must embed dependencies and complete signing/notarization separately.
