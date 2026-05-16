#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <version> <notes-file>" >&2
  echo "  example: $0 0.5 /tmp/release-notes.md" >&2
  exit 1
fi

VERSION="$1"
NOTES_FILE="$2"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is dirty — commit or stash first" >&2
  exit 1
fi

if [[ ! -f "$NOTES_FILE" ]]; then
  echo "notes file not found: $NOTES_FILE" >&2
  exit 1
fi

if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
  echo "tag v${VERSION} already exists" >&2
  exit 1
fi

INFO_PLIST="MarsEdit/Info.plist"
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
NEW_BUILD=$((CURRENT_BUILD + 1))

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_BUILD}" "$INFO_PLIST"

echo "==> Running tests"
xcodebuild -scheme MarsEdit -destination 'platform=macOS' test >/dev/null

echo "==> Building DMG"
./scripts/make-dmg.sh

DMG_PATH="dist/Yanmo-${VERSION}.dmg"
if [[ ! -f "$DMG_PATH" ]]; then
  echo "expected DMG not found: $DMG_PATH" >&2
  exit 1
fi

echo "==> Committing version bump"
git add "$INFO_PLIST"
git commit -m "Release v${VERSION}"

echo "==> Tagging and pushing"
git tag "v${VERSION}"
git push origin main
git push origin "v${VERSION}"

echo "==> Creating GitHub release"
gh release create "v${VERSION}" "$DMG_PATH" \
  --title "Yanmo ${VERSION}" \
  --notes-file "$NOTES_FILE"

echo
echo "Released v${VERSION}: https://github.com/lvterry/Yanmo/releases/tag/v${VERSION}"
