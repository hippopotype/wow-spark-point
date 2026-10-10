#!/usr/bin/env bash
# Exercises .scripts/check-flavor-isolation.sh against throwaway trees.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/.scripts/check-flavor-isolation.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Core" "$WORK/Data" "$WORK/Modules" "$WORK/.tests"
echo 'local game = "Camelot" -- X-Game' >"$WORK/Core/Flavor.lua"
echo 'local models = {} -- Camelot data' >"$WORK/Data/ResourceModels_Forever.lua"
echo 'local x = "Camelot"' >"$WORK/.tests/test_flavor.lua"
echo 'local ok = addon.Has("specs")' >"$WORK/Modules/Clean.lua"

if ! bash "$SCRIPT" "$WORK" >/dev/null; then
	echo "FAIL: clean tree reported violations"
	exit 1
fi

echo 'if addon.Flavor.game == "Forever" then end' >"$WORK/Modules/Leaky.lua"
if bash "$SCRIPT" "$WORK" >/dev/null; then
	echo "FAIL: leaky module not detected"
	exit 1
fi

echo "PASS: isolation script"
