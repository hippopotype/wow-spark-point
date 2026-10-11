#!/usr/bin/env bash
# Exercises .scripts/check-asset-paths.sh against throwaway trees.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/.scripts/check-asset-paths.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Core" "$WORK/.tests"
echo 'local path = addon.addonFolder .. "\\Textures\\icon.png"' >"$WORK/Core/Good.lua"
echo 'local x = "Interface\\AddOns\\SparkPoint\\Textures\\icon.png"' >"$WORK/.tests/fixture.lua"

if ! bash "$SCRIPT" "$WORK" >/dev/null; then
	echo "FAIL: clean tree reported violations"
	exit 1
fi

echo 'icon:SetTexture("Interface\\AddOns\\SparkPoint\\Textures\\icon.png")' >"$WORK/Core/Bad.lua"
if bash "$SCRIPT" "$WORK" >/dev/null; then
	echo "FAIL: hard-coded addon folder not detected"
	exit 1
fi

echo "PASS: asset path script"
