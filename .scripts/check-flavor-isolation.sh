#!/usr/bin/env bash
# Fails when flavor-detection tokens appear outside the files allowed to know the game.
# Allowed: Core/Flavor.lua, Data/*_Standard.lua, Data/*_Forever.lua. WOW_PROJECT_* is
# enforced by luacheck instead (only Core/Flavor.lua declares it).
#
# Usage: bash .scripts/check-flavor-isolation.sh [root]
# Exit:  0 = clean, 1 = violations (printed as path:line:text)

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

PATTERN='X-Game|Flavor\.game|IS_FOREVER|IS_RETAIL|Camelot'

violations="$(grep -rnE "$PATTERN" --include='*.lua' \
	--exclude-dir=.clones --exclude-dir=.git --exclude-dir=.tests . \
	| grep -vE '^\./Core/Flavor\.lua:' \
	| grep -vE '^\./Data/[^/]+_(Standard|Forever)\.lua:' || true)"

if [[ -n "$violations" ]]; then
	echo "Flavor isolation violations (use addon.Has(capability) instead):"
	echo "$violations"
	exit 1
fi
