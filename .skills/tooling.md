# Dev Tooling Guide

Installed via Homebrew. No build step — all tools run directly against source files.

---

## luacheck — Linter / Static Analysis

### Run it

```bash
# Lint the entire addon
luacheck .

# Lint a single file
luacheck Modules/Cast.lua

# Show warning codes (useful for adding new ignores)
luacheck . --codes

# Fail with exit code 1 if any warnings exist (useful in CI / git hooks)
luacheck . --no-max-line-length
```

### Reading output

```
Core/API.lua:35:8: accessing undefined variable CUSTOM_CLASS_COLORS
         ^file  ^line ^col   ^message
```

Exit codes: `0` = clean, `1` = warnings, `2` = errors, `3` = I/O error.

### Config: `.luacheckrc`

- `std = "lua51"` — tells luacheck the code targets Lua 5.1 (WoW's runtime)
- `globals` — all WoW API globals and addon-specific globals (`SparkPointDB`, etc.)
- `ignore` — suppressed warning codes:
  - `11./SLASH_.*` — slash handler globals are expected
  - `211/212/213` — unused locals/args/loop vars (common in event handlers)
  - `42./43.` — upvalue shadowing (acceptable in WoW module pattern)
  - `512` — "loop executed at most once" (intentional early-break idiom in AnchorFrame)
- `exclude_files` — skips `.clones/` and `.git/`

### Adding a new global

If luacheck complains about a new WoW API you've used, add it to both:
1. `.luacheckrc` under `globals`
2. `.luarc.json` under `Lua.diagnostics.globals`

---

## stylua — Formatter

### Run it

```bash
# Format all Lua files in place
stylua .

# Check only — print diff without writing (use before committing)
stylua --check .

# Format a single file
stylua Modules/Cast.lua

# Format a specific directory
stylua Modules/
```

### Config: `.stylua.toml`

```toml
indent_type = "Tabs"    # Matches project style
indent_width = 4        # Visual width per tab stop
column_width = 120      # Soft wrap hint for long lines
```

**Important:** stylua reformats aggressively. Run `stylua --check .` first to preview
what would change. The project uses tabs — do not let any editor convert to spaces.

### When to use

- Before committing new files
- After large refactors

---

## lua-language-server — LSP (Editor Intellisense)

### What it provides

- Inline diagnostics (undefined globals, type mismatches, unreachable code)
- Hover documentation
- Go-to-definition within the addon
- Auto-complete for `addon.*`, module methods, local variables

### Config: `.luarc.json`

Key settings:

```json
{
  "Lua.runtime.version": "Lua 5.1",
  "Lua.diagnostics.globals": [ ... ],
  "Lua.workspace.ignoreDir": [".clones", ".git"]
}
```

- `runtime.version` — ensures the LSP doesn't flag Lua 5.1 patterns as errors
- `diagnostics.globals` — suppresses "undefined global" for all WoW API symbols
- `workspace.ignoreDir` — prevents the LSP from indexing clone reference files

### Editor setup

**VS Code:** Install the `sumneko.lua` (Lua) extension. It auto-discovers
`lua-language-server` installed via Homebrew and reads `.luarc.json` automatically.

**Neovim:** Add to your LSP config:
```lua
require('lspconfig').lua_ls.setup({})
```
The server reads `.luarc.json` from the workspace root.

---

## Recommended Workflow

```bash
# Before committing any Lua changes:
luacheck .          # Must be 0 warnings / 0 errors
stylua --check .    # Review formatting diff
stylua .            # Apply if happy with diff
```
