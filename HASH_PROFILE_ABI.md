# Hash and Profile ABI

This document defines the compatibility contract for Framework hashing and profile storage.

If a change can alter how a module is identified, how a field is keyed, how a default is
interpreted, or how a value is serialized, treat it as ABI work, not cleanup.

## Scope

This applies to:

- shared hashes created by Framework
- coordinator profile slots stored in Chalk config
- regular modules
- special modules

It does not describe the full UI contract. It only covers the serialized identity and value
encoding surface that must stay stable after release.

## Canonical Format

Framework encodes config state into a canonical key-value string:

```text
_v=1|ModId=1|ModId.configKey=value|adamant-SpecialName.configKey=value
```

Properties of the format:

- `_v` is the hash format version and must be present
- keys are sorted alphabetically before the final string is produced
- only non-default values are encoded
- unknown keys are ignored on decode
- missing keys decode to their current defaults

The hash string is used both for:

- portable sharing between users
- local coordinator profile slots

That means compatibility mistakes affect both imports and saved local presets.

## Frozen ABI Surface

Treat the following as frozen after release unless you are doing deliberate compatibility work:

- regular `definition.id`
- storage root `alias` (for both regular and special modules)
- special module `modName`
- storage `default`
- storage type `toHash(...)`
- storage type `fromHash(...)`

These are not cosmetic details. They are the wire format.

`alias` is the hash key. `configKey` is the Chalk persistence path. If you declare an explicit `alias`, `configKey` can change freely without affecting hashes or saved profiles. If `alias` is omitted, it defaults to the stringified `configKey`, which means `configKey` is implicitly frozen for that root.

## Why Each One Matters

### `definition.id`

Regular module enable state is encoded under the module id.

If you rename:

```lua
definition.id = "OldName"
```

to:

```lua
definition.id = "NewName"
```

then old hashes and old profile entries no longer target the same module key space.

### Storage root `alias`

Storage root values are encoded under:

```text
ModId.alias=value
```

`alias` is the hash key. If a root omits `alias`, it defaults to the stringified `configKey`, so `configKey` is effectively the hash key in that case.

If you declare an explicit `alias`, you can rename `configKey` freely — the hash key is unchanged. If you did not declare an explicit `alias`, renaming `configKey` breaks old hashes and saved profile entries for that root unless you add compatibility handling.

### Special `modName`

Special-module state is encoded under the special module name:

```text
adamant-SpecialName.configKey=value
```

Changing `modName` is equivalent to changing a namespace prefix for every special field.

### Special storage root `alias`

Special module storage values are encoded under:

```text
adamant-SpecialName.alias=value
```

The same alias/configKey rules apply: explicit `alias` decouples the hash key from the Chalk path; omitted `alias` means `configKey` is the hash key and is implicitly frozen.

### `default`

Framework only encodes non-default values.

That means changing a default is a compatibility change even if the field name stays the same.

Example:

- old default: `false`
- new default: `true`
- old hash omitted the field because it matched `false`

After the default changes, decoding that old hash will now produce `true` unless the old value was
explicitly encoded. This is not a neutral cleanup.

### `toHash(...)` / `fromHash(...)`

Field type serialization is part of the wire format.

Changing:

- accepted strings
- normalization rules
- delimiter behavior
- numeric formatting
- fallback behavior

can change how old hashes decode or what new hashes look like.

## Compatibility Classes

### Safe internal changes

These are usually fine:

- refactoring UI code
- renaming local Lua variables
- moving functions between files
- changing how store access is implemented internally
- caching or performance optimizations that do not change encoded identity or value semantics

### Public interface changes

These are contract changes, but not necessarily hash ABI changes:

- renaming `DrawTab`
- renaming `DrawQuickContent`
- changing standalone helper signatures
- changing `public.store` shape

These can break Framework or module integration, but they are not the same as serialized ABI.

### ABI changes

These require compatibility planning:

- renaming module ids or schema keys
- changing defaults
- changing value encoding
- changing special `modName`

## Current Compatibility Behavior

Framework currently provides only limited compatibility behavior:

- hash format version check on decode
- unknown keys are ignored
- missing keys fall back to defaults
- invalid dropdown/radio values fall back to defaults
- invalid/unknown field types warn and degrade safely rather than crashing
- saved coordinator profiles are audited at `Framework.init(...)` and warn on unknown field keys
  inside known module/special namespaces, which helps catch likely renames

Framework does not automatically preserve compatibility for:

- renamed module ids
- renamed `configKey` values
- renamed `modName`
- changed defaults
- changed encoding semantics

Those are author-owned compatibility tasks.

## `_hashKey` and Rename Safety

Do not overstate `_hashKey`.

`_hashKey` is a cached runtime key used by Framework for regular-module hashing. It can support
intentional compatibility handling in narrowly controlled cases, but it is not a general rename
system and it does not solve every rename problem across regular modules, special schemas, module
ids, and special `modName`.

Policy:

- do not treat renames as free
- do not assume the current system already has a universal rename layer

## Recommended Rules

### 1. Freeze ids and keys after first release

Once a module is shipped publicly:

- do not rename `definition.id`
- do not rename option `configKey`
- do not rename special `modName`
- do not rename special schema `configKey`

unless you are intentionally doing compatibility work.

### 2. Treat default changes as migrations

If you change a field default:

- assume old hashes may decode differently
- note it in changelog/release notes
- verify impact on shared hashes and saved profiles

### 3. Treat field type serialization as versioned behavior

If you change `toHash(...)` or `fromHash(...)`:

- assume the wire format changed
- test old hashes explicitly
- consider whether a format version bump is required

### 4. Add compatibility deliberately, not implicitly

If you need to preserve old data:

- add explicit decode compatibility handling
- document it
- add tests for old and new forms

Do not rely on accidental fallback behavior.

## When to Bump `_v`

Consider a hash format version bump when the global decode rules change in a way that old hashes
cannot be interpreted safely under the new parser.

Examples:

- changing the top-level delimiter format
- changing how module key namespaces are parsed
- changing the meaning of the overall hash envelope

Do not use `_v` as a substitute for every module-level compatibility decision. Many compatibility
changes are module- or field-level and should be handled there.

## Testing Expectations for ABI Changes

If you intentionally make an ABI-affecting change, test all of:

1. old hash -> new code
2. old saved profile -> new code
3. new hash -> new code
4. unknown-key tolerance still works

At minimum, confirm:

- unchanged modules still round-trip identically
- intended compatibility paths decode to the expected current values
- no unrelated module keys are affected

## Practical Author Checklist

Before changing a released module, ask:

1. Am I changing `definition.id`, `modName`, a storage root `alias`, `default`, `toHash`, or `fromHash`?
2. If I'm changing `configKey` only — did I declare an explicit `alias`? If yes, the hash is unaffected. If no, this is an ABI change.
3. If yes to 1, what happens to old hashes and old saved profiles?
4. Is this a harmless internal refactor, or am I actually changing the wire format?
5. Do I need explicit compatibility handling and tests?

If you cannot answer those clearly, do not merge the change as "cleanup."
