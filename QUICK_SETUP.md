# Quick Setup

This document covers the Framework Quick Setup surface:

- coordinator-owned quick content
- module quick UI nodes
- special-module quick content
- runtime quick selection

Use [README.md](README.md) as the entrypoint for Framework docs.

## What Quick Setup Is

Quick Setup is the context-oriented panel in the Framework window.

It is meant for:

- high-frequency controls
- small slices of module UI that matter immediately
- run- or state-dependent quick access

It is not meant to replace full module tabs.

## Render Order

Quick Setup renders in this order:

1. coordinator-owned quick content from `def.renderQuickSetup(ctx)`
2. special-module quick content from `DrawQuickContent`
3. regular-module quick nodes collected from `definition.ui`

This all happens inside the Framework UI pass in
[`src/ui.lua`](src/ui.lua).

## Coordinator Quick Content

Coordinators may inject their own quick content through:

```lua
def.renderQuickSetup = function(ctx)
    ...
end
```

`ctx` is the Quick Setup context provided by Framework.

Current fields:

- `imgui`
  - the active ImGui binding
- `theme`
  - the current Framework theme object
- `config`
  - the coordinator Chalk config
- `staging`
  - Framework-owned staged values for pack/module/special enable state and profile UI state
- `discovery`
  - the current discovery object
- `lib`
  - the ModpackLib export
- `packId`
  - the current coordinator pack id

Coordinator quick content should stay coordinator-scoped.
If a control belongs to a module, prefer putting it in the module's quick surface instead.

## Regular Module Quick UI

Regular modules participate in Quick Setup through declarative UI nodes.

Mark a node with:

```lua
quick = true
```

Framework collects these candidates from `definition.ui` during discovery and stores them as the
module's quick-node set.

At render time, Framework draws the selected quick nodes through:

- `lib.runUiStatePass(...)`
- `lib.drawUiNode(...)`
- `lib.commitUiState(...)`

So Quick Setup uses the same managed UI state path as full module UI.

## Quick IDs

Quick candidates need stable identities when runtime filtering is used.

Framework resolves a quick node id through:

- explicit `quickId`, if present
- otherwise a derived id from the node's `binds`

If a module uses runtime quick selection, explicit `quickId` is recommended.

Use explicit ids when:

- multiple quick nodes could bind the same storage
- a node's identity should stay stable even if binds change later
- runtime filtering depends on names that should be obvious in code

## Runtime Quick Selection

Modules may narrow their quick surface at render time through:

```lua
definition.selectQuickUi = function(store, uiState, quickNodes)
    ...
end
```

This callback receives:

- `store`
  - the module store
- `uiState`
  - the module managed UI state
- `quickNodes`
  - the full discovered quick candidate list for that module

Return values:

- `nil`
  - render all quick candidates
- a string
  - render the node whose `quickId` matches that string
- a table of strings
  - render nodes whose `quickId` values are in that list
- a set-like table
  - render nodes whose `quickId` keys map to `true`

This is selection, not discovery.

Framework does not discover new quick nodes at runtime.
It filters among the already-declared quick candidates.

## Special Modules

Special modules participate in Quick Setup through:

- `DrawQuickContent`

Framework runs special quick content through `lib.runUiStatePass(...)` when the special is enabled.

Special-module quick content is appropriate when:

- the module already has a custom special UI surface
- the quick surface is not naturally expressible as declarative nodes

If a regular module can express its quick content declaratively, prefer the declarative path.

## What Belongs In Quick Setup

Good Quick Setup content:

- one or two controls the user reaches for often
- context-dependent selectors
- enable/disable or hot-path tuning controls

Bad Quick Setup content:

- the full module UI copied into Quick Setup
- large audit surfaces
- controls that are only meaningful during deep configuration

Quick Setup should stay narrow and fast.

## Design Boundary

Use Quick Setup for:

- contextual access
- narrowed access
- repeated actions

Use full module tabs for:

- complete configuration
- explanation-heavy UI
- large or exploratory editing surfaces

## Related Docs

- [README.md](README.md)
- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
- [ModpackLib README.md](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/README.md)
