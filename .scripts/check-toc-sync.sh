#!/usr/bin/env bash
# Verifies SparkPoint.toc and SparkPoint_Dev.toc stay in sync.
#
# Compares every header field and the complete file list. The only
# permitted differences are "## Title:" and the validated addon-folder
# prefix in "## IconTexture:". Other metadata is compared literally.
#
# Usage: bash .scripts/check-toc-sync.sh
# Exit:  0 = in sync, 1 = drift (prints a unified diff)

set -euo pipefail

ADDON_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_TOC="$ADDON_DIR/SparkPoint.toc"
DEV_TOC="$ADDON_DIR/SparkPoint_Dev.toc"

for toc in "$RELEASE_TOC" "$DEV_TOC"; do
	if [[ ! -f "$toc" ]]; then
		echo "ERROR: missing $toc"
		exit 1
	fi
done

validate_icon() {
	local toc="$1"
	local folder="$2"
	local icon
	icon="$(sed 's/\r$//' "$toc" | grep '^## IconTexture:' || true)"
	case "$icon" in
		"## IconTexture: Interface\\AddOns\\$folder\\"*)
			# Multiple declarations must not pass the prefix check.
			if [[ "$icon" != *$'\n'* ]]; then
				return 0
			fi
			;;
	esac
	echo "ERROR: $toc must declare one IconTexture in Interface\\AddOns\\$folder\\"
	exit 1
}

validate_icon "$RELEASE_TOC" "SparkPoint"
validate_icon "$DEV_TOC" "SparkPoint_Dev"

normalize() {
	sed 's/\r$//' "$1" \
		| sed 's/^## IconTexture: Interface\\AddOns\\SparkPoint_Dev\\/## IconTexture: Interface\\AddOns\\SparkPoint\\/' \
		| grep -v '^## Title:'
}

if ! diff -u \
		--label "SparkPoint.toc" \
		--label "SparkPoint_Dev.toc" \
		<(normalize "$RELEASE_TOC") \
		<(normalize "$DEV_TOC"); then
	echo
	echo "ERROR: .toc files drifted. Only '## Title:' and the validated IconTexture addon folder may differ."
	exit 1
fi

echo "OK: .toc files in sync"
