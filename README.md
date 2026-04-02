# adamant-ModpackFramework

Reusable coordinator framework for adamant modpacks.

It owns:
- discovery
- config hashing and profile load
- HUD fingerprint rendering
- the shared coordinator UI

## Docs

- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)

## Public Contract Freeze

The public Framework contract is intended to be stable:
- coordinator init shape and discovery expectations
- shared UI, HUD, and profile/hash behavior
- rollback behavior for major framework-owned operations

Hash/profile ABI is compatibility-sensitive. Changes to ids, keys, defaults, or field serialization should be treated as compatibility work, not refactoring.

## Validation

```bash
cd adamant-ModpackFramework
lua5.1 tests/all.lua
```
