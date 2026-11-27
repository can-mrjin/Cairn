#!/usr/bin/env bash
set -euo pipefail

# Increments the beta prerelease suffix in Resources/Info.plist:
#   1.2.1-beta.1 -> 1.2.1-beta.2
#   1.2.0        -> 1.2.1-beta.1
#
# Usage: ./scripts/bump-beta-version.sh [explicit-version]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$REPO_ROOT/Resources/Info.plist"

CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
NEXT="${1:-}"

if [[ -z "$NEXT" ]]; then
    if [[ "$CURRENT" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-beta\.([0-9]+)$ ]]; then
        BASE="${BASH_REMATCH[1]}"
        NUM="${BASH_REMATCH[2]}"
        NEXT="${BASE}-beta.$((NUM + 1))"
    elif [[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        NEXT="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))-beta.1"
    else
        echo "ERROR: Cannot auto-increment unrecognized version '$CURRENT'. Pass an explicit version." >&2
        exit 1
    fi
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEXT" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT" "$PLIST"

echo "Bumped version: $CURRENT -> $NEXT"
