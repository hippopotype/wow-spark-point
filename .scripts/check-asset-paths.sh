#!/usr/bin/env bash
# Fails when a .lua file hard-codes the addon folder in an asset path. Paths must be
# built from addon.addonFolder so the dev copy (SparkPoint_Dev) and any install
# folder load their own textures.
#
# Usage: bash .scripts/check-asset-paths.sh [root]
# Exit:  0 = clean, 1 = violations (printed as path:line:text)

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

violations="$(grep -rnF --include='*.lua' \
	--exclude-dir=.clones --exclude-dir=.git --exclude-dir=.tests \
	'AddOns\\SparkPoint' . || true)"

if [[ -n "$violations" ]]; then
	echo "Hard-coded addon folder in asset paths (use addon.addonFolder):"
	echo "$violations"
	exit 1
fi
