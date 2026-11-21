#!/bin/bash
# Builds a universal (Apple Silicon + Intel), signed MiniDict.app, zips it into
# dist/ and publishes it as a GitHub Release tagged v<version from build.sh>.
#   tools/release.sh --dry                       build + zip only
#   NOTES=notes.md tools/release.sh              build, zip, push, create the release
# Sign with the same "MiniDict Local Signing" identity every time: users'
# Accessibility permission is tied to it and survives updates only if it stays.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's|.*<key>CFBundleShortVersionString</key> *<string>\([^<]*\)</string>.*|\1|p' build.sh)
TAG="v$VERSION"
ZIP="dist/MiniDict-$VERSION.zip"
DRY="${1:-}"

if [ "$DRY" != "--dry" ]; then
    [ -n "${NOTES:-}" ] && [ -f "$NOTES" ] || { echo "Set NOTES=path/to/release-notes.md"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
    ! gh release view "$TAG" >/dev/null 2>&1 || { echo "$TAG already exists: bump the version in build.sh."; exit 1; }
fi

UNIVERSAL=1 ./build.sh --no-install
echo "==> check"
lipo -archs MiniDict.app/Contents/MacOS/MiniDict
codesign --verify --deep --strict MiniDict.app
codesign -dv MiniDict.app 2>&1 | grep -E '^(Authority|Identifier)='

echo "==> zip"
mkdir -p dist
rm -f "$ZIP"
# ditto keeps the bundle's signature and extended attributes intact (plain zip can break it).
ditto -c -k --sequesterRsrc --keepParent MiniDict.app "$ZIP"
ls -lh "$ZIP" | awk '{print $5, $9}'
shasum -a 256 "$ZIP"

[ "$DRY" = "--dry" ] && exit 0

echo "==> publish $TAG"
git push origin HEAD
gh release create "$TAG" "$ZIP" --title "MiniDict $VERSION" --notes-file "$NOTES" --target "$(git rev-parse HEAD)"
