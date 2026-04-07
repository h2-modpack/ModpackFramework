# adamant-ModpackFramework

Reusable coordinator framework for adamant modpacks.

Start here for Framework documentation.
This page links to the current coordinator and compatibility references.
External repos and templates should link here rather than to individual Framework docs.

It owns:
- discovery
- config hashing and profile load
- HUD fingerprint rendering
- the shared coordinator UI

## Docs

- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
  Bootstrap, discovery, and coordinator-facing Framework contract.
- [QUICK_SETUP.md](QUICK_SETUP.md)
  Quick Setup model, coordinator quick content, module quick nodes, and runtime quick filtering.
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
  Compatibility rules for hashes, profiles, aliases, defaults, and hash groups.
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for changing Framework behavior or public contract.

## Public Contract Freeze

The public Framework contract is intended to be stable:
- coordinator init shape and discovery expectations
- shared UI, HUD, and profile/hash behavior
- rollback behavior for major framework-owned operations

Hash/profile ABI is compatibility-sensitive. Changes to ids, keys, defaults, or field serialization should be treated as compatibility work, not refactoring.

## Validation

```bash
cd adamant-ModpackFramework
lua5.2 tests/all.lua
```
