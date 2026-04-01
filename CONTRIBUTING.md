# Contributing to adamant-ModpackFramework

Reusable orchestration library for Hades 2 modpacks. Provides discovery, config hashing, HUD fingerprint, and the shared UI window. Coordinators call `Framework.init(params)` and get the full pack runtime.

See also:

- `HASH_PROFILE_ABI.md` for the dedicated hash/profile ABI policy

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

Coordinators own their Chalk config, `def` (`NUM_PROFILES`, `defaultProfiles`, `groupStyle`, `groupStyleDefault`, `renderQuickSetup`), and `packId`. Framework owns discovery, hash, HUD, and the shared UI.

## Coordinator init contract

`Framework.init(params)` is a validated coordinator contract, not a loose bag of inputs.

Required:

- `params.packId` - non-empty string
- `params.windowTitle` - non-empty string
- `params.config` - table containing:
  - `ModEnabled` boolean
  - `DebugMode` boolean
  - `Profiles` table
- `params.def` - table containing:
  - `NUM_PROFILES` positive integer
  - `defaultProfiles` table

`config.Profiles` must be pre-populated with entries for `1..NUM_PROFILES`. Framework normalizes
missing `Name`, `Hash`, and `Tooltip` values on each existing entry, but missing profile slots are
treated as coordinator contract errors and fail fast.

`sidebarOrder` and `groupStyleDefault` are optional, but unknown values are warned and normalized
to safe defaults.

## Key systems

### Discovery (`discovery.lua` - `createDiscovery`)

Auto-discovers all installed modules that opt in via `definition.modpack = packId`.

- Regular modules: `definition.special` is nil or false
- Special modules: `definition.special = true`
- All metadata (`id`, `name`, `category`, `group`, `tooltip`, `default`) lives in each module's `public.definition`
- Modules are sorted alphabetically by display name; categories and groups are also sorted alphabetically

A new category tab is created automatically the first time a module with a new `definition.category` is discovered.

`Discovery.run(groupStyle, groupStyleDefault)` accepts two optional arguments passed from `params.def` by `Framework.init`:

- `groupStyle` — `table` mapping `category -> group -> style string`. Overrides the default style for specific groups.
- `groupStyleDefault` — `string`. The fallback style for any group not covered by `groupStyle`. Defaults to `"collapsing"` when absent.

Group style is resolved once per group at layout build time and stored on the layout entry as `group.style`.

`opt._hashKey` (`def.id .. "." .. opt.configKey`) is cached on each option descriptor at discovery time, used by both `GetConfigHash` and `ApplyConfigHash` to avoid per-call string concatenation.

For special modules, discovery expects:
- `definition.name`
- `definition.apply`
- `definition.revert`
- `public.store.specialState`
- at least one UI entrypoint:
  - `public.DrawTab`
  - `public.DrawQuickContent`

If a special exposes neither draw entrypoint, discovery warns that the tab will be empty but does
not skip the module automatically.

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

If a field type is unknown or invalid, hashing should warn and degrade safely rather than crash.
Invalid fields should not participate in schema-backed or hash processing as if they were valid.

### Hash ABI policy

Treat the following as frozen compatibility surface after release:

- regular `definition.id`
- regular option `configKey`
- special module `modName`
- special schema `configKey`
- field defaults
- field `toHash(...)` / `fromHash(...)`

Changing any of those is not cosmetic. It is compatibility work for saved profiles and shared
hashes. If a rename or semantic change is required, handle it deliberately in hash migration logic
rather than relying on silent decode-to-default behavior.

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
- Framework passes `public.store.specialState` into `DrawTab(ui, specialState, theme)` and `DrawQuickContent(ui, specialState, theme)`
- after each draw, if `specialState.isDirty()` is true, Framework calls `specialState.flushToConfig()` once
- Framework then invalidates the cached hash and updates the HUD

Special-module flush behavior:
- Framework passes `specialState` into module draw functions
- after draw, if `specialState.isDirty()` is true, Framework flushes once and updates the HUD/hash state

Returns `{ renderWindow, addMenuBar }`. Registration with `rom.gui` is handled by the coordinator via `Framework.init`.

### Dev tab (`ui.lua` - `DrawDev`)

Two independent debug controls:

| Control | What it gates | Config key |
|---|---|---|
| Framework Debug | `lib.warn(packId, enabled, msg)` calls for schema errors, discovery warnings, etc. | `config.DebugMode` |
| Lib Debug | lib-internal diagnostics | `lib.config.DebugMode` |
| Per-module Debug | `lib.log(name, enabled, msg)` inside module code | each module's `config.DebugMode` |

Framework Debug and Lib Debug are written directly rather than through staging.

### Group style system (`ui.lua` - `DrawCheckboxGroup`)

Each group in a category layout carries a `style` field that controls how it is rendered:

| Style | Behavior |
|---|---|
| `"collapsing"` | `CollapsingHeader` — default |
| `"separator"` | Labeled section header + separator line, always visible, never collapsible |
| `"flat"` | No header, items rendered directly |

The coordinator configures styles via `def` fields passed to `Framework.init`:

```lua
local GroupStyle = Framework.GroupStyle  -- COLLAPSING, SEPARATOR, FLAT

Framework.init({
    def = {
        groupStyleDefault = GroupStyle.FLAT,
        groupStyle = {
            ["Bug Fixes"] = { ["Boons & Hammers"] = GroupStyle.COLLAPSING },
        },
        ...
    },
    ...
})
```

`Framework.GroupStyle` is the public constants table on the Framework module. Resolution order per group: `groupStyle[category][group]` → `groupStyleDefault` → `"collapsing"`.

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
- Special-module UI reads from `public.store.specialState.view` and mutates via `public.store.specialState.set/update/toggle`
- `definition.options` config keys must be flat strings; table-path keys are only valid in `definition.stateSchema`
- `lib.createStore(...)` is the only supported store constructor; Framework does not support custom hand-rolled stores
