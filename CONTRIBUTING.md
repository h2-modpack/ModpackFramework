# Contributing to adamant-ModpackFramework

Reusable orchestration library for Hades 2 modpacks. Provides discovery, config hashing, HUD fingerprint, and the shared UI window. Coordinators call `Framework.init(params)` and get the full pack runtime.

## Architecture

```text
src/
  main.lua        -- Framework table, ENVY wiring, Framework.init, imports sub-files
  discovery.lua   -- createDiscovery(packId, config, lib)
  hash.lua        -- createHash(discovery, config, lib, packId)
  ui_theme.lua    -- createTheme()
  hud.lua         -- createHud(packId, packIndex, hash, theme, config, modutil)
  ui.lua          -- createUI(discovery, hud, theme, def, config, lib, packId, windowTitle)
```

Each sub-file exposes one factory function on the `Framework` table. `Framework.init` wires them together, handles coordinator registration through Lib, and returns the pack table. Factory params replace the old global `Core.*` style; state is closed over, not shared.

Coordinators own their Chalk config, `def` (`NUM_PROFILES`, `defaultProfiles`), and `packId`. Framework owns discovery, hash, HUD, and the shared UI.

## Key systems

### Discovery (`discovery.lua` - `createDiscovery`)

Auto-discovers all installed modules that opt in via `definition.modpack = packId`.

- Regular modules: `definition.special` is nil or false
- Special modules: `definition.special = true`
- All metadata (`id`, `name`, `category`, `group`, `tooltip`, `default`) lives in each module's `public.definition`
- Modules are sorted alphabetically by display name; categories and groups are also sorted alphabetically

A new category tab is created automatically the first time a module with a new `definition.category` is discovered.

For special modules, discovery expects:
- `definition.name`
- `definition.apply`
- `definition.revert`
- `public.specialState`

### Config hash (`hash.lua` - `createHash`)

Pure encoding logic with no engine dependencies. Uses a key-value canonical string:

```text
_v=1|ModId=1|ModId.configKey=value|adamant-SpecialName.configKey=value
```

- Only non-default values are encoded
- Keys are sorted alphabetically for stable output
- Value encoding is delegated to `lib.FieldTypes[field.type].toHash/fromHash`
- `_v` must be present or the hash is rejected

`GetConfigHash(source)` returns `canonical, fingerprint`.
`ApplyConfigHash(hash)` decodes and applies the canonical string; unknown keys are ignored and missing keys reset to defaults.

For special modules, hash application writes config directly and then calls `specialState.reloadFromConfig()`.

### HUD (`hud.lua` - `createHud`)

Manages the fingerprint overlay. Each pack registers its own component named `ModpackMark_<packId>`, positioned at `Y = 250 + (packIndex - 1) * 24` so multiple packs stack vertically. Returns `{ setModMarker, updateHash, getConfigHash, applyConfigHash }`.

### UI (`ui.lua` - `createUI`)

Framework uses its own staging table for regular module state and profiles.

Key handlers:

| Function | Purpose |
|---|---|
| `ToggleModule(module, val)` | Enable or disable a regular module |
| `ChangeOption(module, key, val)` | Change an inline option |
| `ToggleSpecial(special, val)` | Enable or disable a special module |
| `SetModuleState(module, state)` | Game-side only apply or revert |
| `LoadProfile(hash)` | Apply a hash string to all modules and refresh staging |
| `setCategoryEnabled(category, val)` | Bulk toggle all regular modules in a category |
| `getCategoryStatus(category)` | Return category status text/color/exists for coordinator quick-setup UI |

Special-module rendering contract:
- Framework passes `public.specialState` into `DrawTab(ui, specialState, theme)` and `DrawQuickContent(ui, specialState, theme)`
- after each draw, if `specialState.isDirty()` is true, Framework calls `specialState.flushToConfig()` once
- Framework then invalidates the cached hash and updates the HUD

Debug guard for special modules:
- Framework can snapshot schema-backed config values before special draw
- after draw, if config changed but `specialState.isDirty()` stayed false, Framework calls `lib.warnIfSpecialConfigBypassedState(...)`
- this warns when a special writes schema-backed `config` directly during draw instead of using `public.specialState`

Returns `{ renderWindow, addMenuBar }`. Registration with `rom.gui` is handled by the coordinator via `Framework.init`.

### Dev tab (`ui.lua` - `DrawDev`)

Two independent debug controls:

| Control | What it gates | Config key |
|---|---|---|
| Framework Debug | `lib.warn(packId, enabled, msg)` calls for schema errors, discovery warnings, etc. | `config.DebugMode` |
| Lib Debug | lib-internal diagnostics | `lib.config.DebugMode` |
| Per-module Debug | `lib.log(name, enabled, msg)` inside module code | each module's `config.DebugMode` |

Framework Debug and Lib Debug are written directly rather than through staging.

### Theme (`ui_theme.lua` - `createTheme`)

Declarative colors and layout constants. No parameters today; returns the same palette each time.

## Hot reload

`Framework.init` is safe to call on every reload. Subsystem instances are recreated fresh each call, while GUI callbacks remain stable through late binding.

## Tests

```text
cd adamant-ModpackFramework
lua5.1 tests/all.lua
```

Tests use the individual factory functions directly with mocks rather than requiring the engine.

## Guidelines

- Never rename `definition.id` or `field.configKey` after release; these are hash keys
- Coordinator-specific Quick Setup UI belongs in `def.renderQuickSetup(ctx)`, not in Framework
- All module apply/revert calls go through `pcall`; use `lib.warn(...)` for framework errors, never crash
- Regular-module UI reads from Framework staging, not Chalk
- Special-module UI reads from `public.specialState.view` and mutates via `public.specialState.set/update/toggle`
- `definition.options` config keys must be flat strings; table-path keys are only valid in `definition.stateSchema`
