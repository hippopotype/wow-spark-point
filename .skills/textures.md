# SparkPoint Texture Workflow

## Intent
Keep ring/cast textures visually smooth in-game and avoid accidental fallback to low-quality formats.

## Current Repo Rules
- Prefer explicit file extensions in code paths (`.png` or `.tga`).
- Do not rely on extensionless `SetTexture` paths.
- `.blp` assets may exist in `Textures/`, but source should not reference them unless intentionally required.

## Rendering Setup (Code)
- Use texture smoothing helper when binding ring/cast textures:
  - Try `SetTexture(path, nil, nil, "TRILINEAR")`.
  - Fallback to `SetTexture(path)` if filter arg is unsupported.
  - Disable pixel snapping when available:
    - `SetSnapToPixelGrid(false)`
    - `SetTexelSnappingBias(0)`
- Apply this consistently to:
  - Donut background/progress/overlay/frame textures
  - Cast frame overlay texture

## Asset Export Guidance
- Source format: SVG is fine; export raster from high resolution.
- Texture dimensions should use powers of two on both axes.
  - Good: `256x256`, `512x512`, `1024x512`, `1024x1024`
  - Avoid: `1024x400`, `512x200`, other non-power-of-two heights or widths
- Even when non-power-of-two PNGs load, they may render worse in WoW UI than equivalent power-of-two exports.
- If a wide HUD element needs a shorter visible shape, keep the art centered inside a power-of-two canvas with transparent padding rather than exporting a non-power-of-two height.
- Recommended texture dimensions:
  - Start at `512x512` for ring layers.
  - Move to `1024x1024` if edges are still rough and perf is acceptable.
- For non-square HUD shells or bars, prefer `512x256` or `1024x512`.
- Keep transparent edge pixels color-bleeded (no black RGB under full alpha transparency).
- Use straight alpha export (avoid premultiplied-alpha dark fringes).

## File Naming Convention
- Ring layers: `name_thickness.png` (example: `cast_fill_20.png`).
- Decorative custom textures: explicit files (example: `AuraSplit.tga`, `AuraHalf.tga`).

## Validation Checklist
1. `/reload` and inspect cast ring while moving and casting.
2. Compare edges at different UI scales.
3. Confirm no missing texture errors after changing filenames/extensions.
4. Verify grep has no unintended `.blp` references:
   - `rg -n "\\.blp" -S Core Modules Widgets Settings`

## When to Use BLP Anyway
- Only if memory/bundle size becomes a real constraint and quality is still acceptable.
- If reintroducing BLP, document why and keep explicit extension usage for clarity.
