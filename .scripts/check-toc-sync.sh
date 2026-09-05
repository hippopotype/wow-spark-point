#!/usr/bin/env bash
# Verifies SparkPoint.toc and SparkPoint_Dev.toc stay in sync.
#
# Compares every header field and the complete file list. The only
# permitted difference is "## Title:". Addon-name occurrences are
# normalized so SparkPoint_Dev paths compare equal to SparkPoint paths.
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

normalize() {
	sed 's/\r$//' "$1" \
		| sed 's/SparkPoint_Dev/SparkPoint/g' \
		| grep -v '^## Title:'
}

if ! diff -u \
		--label "SparkPoint.toc" \
		--label "SparkPoint_Dev.toc" \
		<(normalize "$RELEASE_TOC") \
		<(normalize "$DEV_TOC"); then
	echo
	echo "ERROR: .toc files drifted. Only '## Title:' may differ."
	exit 1
fi

echo "OK: .toc files in sync"
