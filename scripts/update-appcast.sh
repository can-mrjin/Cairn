#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/update-appcast.sh [--channel beta] <version> <dmg-path>
# Example: ./scripts/update-appcast.sh 1.2.0 .build/Cairn.dmg
# Example: ./scripts/update-appcast.sh 1.3.0-beta.1 .build/Cairn.dmg
#
# Produces / updates appcast.xml at the repo root. Signs the DMG with the
# private EdDSA key that lives in the macOS Keychain (added by Sparkle's
# generate_keys tool during initial setup) and records the signature + size
# + pubDate on a new <item> entry. Prerelease versions (containing `-`) or
# `--channel beta` are tagged with `<sparkle:channel>beta</sparkle:channel>`.
#
# Assumptions:
#   - A prior `swift build -c release` has populated .build/artifacts so
#     Sparkle's sign_update binary is on disk.
#   - The DMG is uploaded to
#       https://github.com/can-mrjin/Cairn/releases/download/v<version>/Cairn.dmg
#     (the default asset URL from build-dmg.sh + `gh release create`).

CHANNEL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel)
            CHANNEL="${2:-}"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

VERSION="${1:-}"
DMG_PATH="${2:-}"
if [[ -z "$VERSION" || -z "$DMG_PATH" ]]; then
    echo "Usage: $0 [--channel beta] <version> <dmg-path>" >&2
    exit 1
fi
if [[ -z "$CHANNEL" && "$VERSION" == *-* ]]; then
    CHANNEL="beta"
fi
if [[ ! -f "$DMG_PATH" ]]; then
    echo "ERROR: DMG not found at $DMG_PATH" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build"
APPCAST="$REPO_ROOT/appcast.xml"
SIGN_UPDATE="$BUILD_DIR/artifacts/sparkle/Sparkle/bin/sign_update"

if [[ ! -x "$SIGN_UPDATE" ]]; then
    echo "ERROR: sign_update not at $SIGN_UPDATE — run 'swift build -c release' first." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Collect fields for the <enclosure> tag
# ---------------------------------------------------------------------------
DOWNLOAD_URL="https://github.com/can-mrjin/Cairn/releases/download/v${VERSION}/Cairn.dmg"
PUB_DATE="$(LC_TIME=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")"
LENGTH="$(stat -f%z "$DMG_PATH")"
MIN_OS="14.0"

echo "==> Signing $DMG_PATH with Sparkle EdDSA key from Keychain"
SIGN_OUTPUT="$("$SIGN_UPDATE" "$DMG_PATH")"
# sign_update emits `sparkle:edSignature="..." length="..."` on success.
ED_SIG="$(printf '%s' "$SIGN_OUTPUT" | /usr/bin/perl -ne 'print $1 if /sparkle:edSignature="([^"]+)"/')"
if [[ -z "$ED_SIG" ]]; then
    echo "ERROR: could not parse EdDSA signature from sign_update output:" >&2
    echo "$SIGN_OUTPUT" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Build the new <item> block
# ---------------------------------------------------------------------------
CHANNEL_XML=""
if [[ -n "$CHANNEL" ]]; then
    CHANNEL_XML="
      <sparkle:channel>${CHANNEL}</sparkle:channel>"
fi

NEW_ITEM="    <item>
      <title>Version ${VERSION}</title>
      <link>https://github.com/can-mrjin/Cairn/releases/tag/v${VERSION}</link>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>${CHANNEL_XML}
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url=\"${DOWNLOAD_URL}\"
        sparkle:edSignature=\"${ED_SIG}\"
        length=\"${LENGTH}\"
        type=\"application/octet-stream\" />
    </item>"

# ---------------------------------------------------------------------------
# Fresh appcast vs existing — insert the new item at the top of <channel>
# ---------------------------------------------------------------------------
if [[ ! -f "$APPCAST" ]]; then
    echo "==> Creating new $APPCAST"
    cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/"
     version="2.0">
  <channel>
    <title>Cairn</title>
    <link>https://raw.githubusercontent.com/can-mrjin/Cairn/main/appcast.xml</link>
    <description>Most recent Cairn updates</description>
    <language>en</language>
${NEW_ITEM}
  </channel>
</rss>
EOF
else
    echo "==> Prepending version ${VERSION} to $APPCAST"
    # Reject if the same version is already in the feed.
    if /usr/bin/grep -q "<sparkle:version>${VERSION}</sparkle:version>" "$APPCAST"; then
        echo "ERROR: ${VERSION} is already in appcast.xml. Bump the version or edit by hand." >&2
        exit 1
    fi
    # Use perl for portable insertion before the first <item> (or before </channel>
    # if no items yet).
    /usr/bin/perl -i -pe '
        BEGIN { $done = 0; $item = shift @ARGV; }
        if (!$done && (/<item>/ || /<\/channel>/)) {
            print $item . "\n";
            $done = 1;
        }
    ' "$NEW_ITEM" "$APPCAST"
fi

echo "==> appcast.xml updated:"
echo "    version=${VERSION}"
echo "    length=${LENGTH}"
echo "    pubDate=${PUB_DATE}"
echo "    url=${DOWNLOAD_URL}"
