# Coordinator Guide

This guide covers the supported `adamant-ModpackFramework` contract for coordinator mods.

## What the Coordinator Owns

The coordinator owns:
- `packId`
- Chalk config
- default profiles
- GUI registration
- any coordinator-specific quick-setup content

Framework owns:
- discovery
- config hashing / profile load
- HUD fingerprint
- main pack window

## Bootstrap Pattern

Recommended coordinator shape:

```lua
local config = chalk.auto("config.lua")
local loader = reload.auto_single()

local function init()
    Framework.init({
        packId = PACK_ID,
        windowTitle = "My Modpack",
        config = config,
        def = def,
        modutil = modutil,
    })
end

modutil.once_loaded.game(function()
    rom.gui.add_imgui(Framework.getRenderer(PACK_ID))
    rom.gui.add_to_menu_bar(Framework.getMenuBar(PACK_ID))
    loader.load(init, init)
end)
```

Use `loader.load(init, init)` unless you have a specific one-time-only registration reason to split `on_ready` and `on_reload`.

## `Framework.init(params)`

Required:
- `packId`
- `windowTitle`
- `config`
- `def`
- `modutil`

`config` must contain:
- `ModEnabled`
- `DebugMode`
- `Profiles`

`def` must contain:
- `NUM_PROFILES`
- `defaultProfiles`

Optional `def` fields:
- `groupStyle`
- `groupStyleDefault`
- `categoryOrder` — ordered list of category and/or special names to pin first in the sidebar. Any mix of categories and specials is supported. Entries not in the list are appended alphabetically after the pinned ones. Unknown entries are warned and ignored.
- `renderQuickSetup(ctx)` — coordinator-owned Quick Setup content. See [QUICK_SETUP.md](QUICK_SETUP.md).

## Discovery

Framework discovers modules by:

```lua
public.definition.modpack = PACK_ID
```

Regular modules:
- `definition.special` absent or false
- discovered into category/subgroup tabs
- use `definition.id` as the Framework hash namespace
- hosted Quick Setup comes from `definition.ui` nodes marked `quick = true`
- `definition.selectQuickUi(...)` may filter those quick candidates at render time

Special modules:
- `definition.special = true`
- discovered into dedicated sidebar tabs
- use `modName` as the Framework hash namespace
- ignore `definition.category`, `definition.subgroup`, and `definition.selectQuickUi`
- Quick Setup comes from `DrawQuickContent`, not quick widget collection
- tab rendering comes from `DrawTab`, or falls back to `definition.ui` when present

Lifecycle shape is inferred from:
- `patchPlan`
- `apply/revert`
- or both

## Hash and Profiles

Hash format is canonical key-value encoding.

Properties:
- only non-default values are encoded
- keys are sorted for stable output
- field serialization is delegated to storage types
- optional module `definition.hashGroups` can compress multiple small root storage values into one base62 token per group

Profile load behavior:
- writes decoded config values
- reloads managed `uiState`
- applies enabled/runtime state
- rolls the whole operation back on later failure

Compatibility-sensitive surface is documented in [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md).

## Runtime Transactions

Framework now owns transaction boundaries for the major public operations:

- per-entry enable/disable
- managed `uiState` commit
- coordinator master `ModEnabled` toggle
- profile/hash load

These paths either:
- commit the new state
- or restore the previous persisted/runtime state and warn

Smaller bespoke batch operations may still be best-effort unless explicitly hardened.

## UI Model

Framework keeps its own staging only for Framework-owned state:
- pack `ModEnabled`
- module enabled states
- special enabled states
- debug toggles
- profile editing state

Module-owned managed values live in `public.store.uiState`.

Framework renders module-managed state through:
- `lib.runUiStatePass(...)`
- `lib.commitUiState(...)`

Quick Setup has its own surface and behavior contract. See [QUICK_SETUP.md](QUICK_SETUP.md).

## Debug and Warnings

Warning split:
- `lib.warn(...)`: debug-gated framework hygiene diagnostics
- `lib.contractWarn(...)`: always-on contract or compatibility warnings

Framework debug:
- `config.DebugMode`

Lib debug:
- `lib.config.DebugMode`

## Related Docs

- [ModpackLib README.md](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/README.md)
- [QUICK_SETUP.md](QUICK_SETUP.md)
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
