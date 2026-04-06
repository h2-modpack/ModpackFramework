# Contributing to adamant-ModpackFramework

`adamant-ModpackFramework` owns coordinator orchestration: discovery, hashing, HUD, and the shared UI. Treat its runtime behavior and warnings as public coordinator contract.

## Read This First

- [README.md](README.md) for package overview
- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md) for the coordinator/runtime contract
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md) for hash/profile compatibility policy
- [https://github.com/h2-modpack/ModpackLib/blob/main/MODULE_AUTHORING.md](https://github.com/h2-modpack/ModpackLib/blob/main/MODULE_AUTHORING.md) for module-side lifecycle expectations

## Contribution Rules

- Keep Framework docs aligned with the live coordinator contract and the template repo.
- Prefer explicit contract warnings over silent skips for skip-causing failures.
- Batch operations may be best-effort, but major framework-owned operations should rollback when practical.
- Treat hash/profile ABI changes as compatibility work, not refactoring.

## Validation

```bash
cd adamant-ModpackFramework
lua5.2 tests/all.lua
```
