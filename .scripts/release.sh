#!/usr/bin/env bash
# SparkPoint release packager
# Creates a distributable .zip ready for CurseForge, Wago.io, and GitHub Releases.
#
# Usage:
#   bash .scripts/release.sh          # package current version from .toc
#   bash .scripts/release.sh 1.2.0    # override version string
#
# Output: .releases/SparkPoint-v{VERSION}.zip

set -euo pipefail

ADDON_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ADDON_NAME="SparkPoint"
TOC_FILE="$ADDON_DIR/${ADDON_NAME}.toc"

# ── Version ──────────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    VERSION="$1"
else
    VERSION="$(grep -m1 "^## Version:" "$TOC_FILE" | sed 's/## Version:[[:space:]]*//' | tr -d '\r')"
fi

if [[ -z "$VERSION" ]]; then
    echo "ERROR: Could not determine version. Check ${ADDON_NAME}.toc or pass a version argument."
    exit 1
fi

# ── Output ────────────────────────────────────────────────────────────────────
RELEASES_DIR="$ADDON_DIR/.releases"
OUTPUT="$RELEASES_DIR/${ADDON_NAME}-v${VERSION}.zip"
mkdir -p "$RELEASES_DIR"
rm -f "$OUTPUT"

# ── Staging ───────────────────────────────────────────────────────────────────
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

DEST="$STAGING/$ADDON_NAME"

rsync -r \
    --exclude='.git' \
    --exclude='.gitignore' \
    --exclude='.clones' \
    --exclude='.skills' \
    --exclude='.agents' \
    --exclude='.claude/' \
    --exclude='.sessions' \
    --exclude='.resources' \
    --exclude='.releases' \
    --exclude='.github' \
    --exclude='.scripts' \
    --exclude='SparkPoint_Dev.toc' \
    --exclude='CLAUDE.md' \
    --exclude='AGENTS.md' \
    --exclude='.luacheckrc' \
    --exclude='.luarc.json' \
    --exclude='.stylua.toml' \
    --exclude='.styluaignore' \
    --exclude='.DS_Store' \
    --exclude='Thumbs.db' \
    --exclude='*.bak' \
    --exclude='*.tmp' \
    --exclude='*.log' \
    "$ADDON_DIR/" "$DEST/"

# ── Zip ───────────────────────────────────────────────────────────────────────
cd "$STAGING"
zip -r "$OUTPUT" "$ADDON_NAME/" -q

echo ""
echo "  Release packaged:"
echo "  $OUTPUT"
echo ""
echo "  Contents:"
unzip -l "$OUTPUT" | awk 'NR>3 && /SparkPoint\// {print "  " $NF}' | head -30
TOTAL=$(unzip -l "$OUTPUT" | grep -c "SparkPoint/" || true)
echo "  ... ($TOTAL files total)"
echo ""
