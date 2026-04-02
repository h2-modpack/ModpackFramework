-- =============================================================================
-- CONFIG HASH: Key-Value Encoding / Decoding
-- =============================================================================
-- Pure hash logic — no engine dependencies. Testable in standalone Lua.
-- Depends on: discovery (module list), lib (readPath/writePath/FieldTypes)
--
-- Two-layer design:
--   canonical  — key-value string encoding all non-default values (for export/import)
--   fingerprint — short base62 checksum of canonical string (for HUD display)
--
-- Format: "ModId=1|ModId.configKey=value|adamant-SpecialName.configKey=value"
-- Keys are sorted alphabetically for stable output.
-- Only non-default values are encoded — adding new fields with defaults is non-breaking.

--- Create the hash/profile subsystem for one coordinator pack.
--- @param discovery table Discovery object returned by `Framework.createDiscovery(...)`.
--- @param config table Coordinator config table used for debug-gated warnings.
--- @param lib table Adamant Modpack Lib export.
--- @param packId string Pack identifier used in warnings.
--- @return table hash Hash object exposing encode/decode, export, and import helpers.
function Framework.createHash(discovery, config, lib, packId)
    local HASH_VERSION = 1

    local Hash = {}
    local GetSchemaConfigFields = lib.getSchemaConfigFields

    local function ReadPersisted(mod, key)
        return mod.store.read(key)
    end

    local function WritePersisted(mod, key, value)
        mod.store.write(key, value)
    end

    local function GetUiState(mod)
        return mod.store.uiState
    end

    local function ClonePersistedValue(value)
        if type(value) == "table" then
            return rom.game.DeepCopyTable(value)
        end
        return value
    end

    local function ReloadManagedUiState()
        for _, m in ipairs(discovery.modulesWithOptions) do
            local uiState = GetUiState(m.mod)
            if uiState and uiState.reloadFromConfig then
                uiState.reloadFromConfig()
            end
        end
        for _, special in ipairs(discovery.specials) do
            local uiState = GetUiState(special.mod)
            if uiState and uiState.reloadFromConfig then
                uiState.reloadFromConfig()
            end
        end
    end

    local function CaptureApplySnapshot()
        local snapshot = {
            moduleEnabled = {},
            moduleOptions = {},
            specialEnabled = {},
            specialFields = {},
        }

        for _, m in ipairs(discovery.modules) do
            snapshot.moduleEnabled[m] = discovery.isModuleEnabled(m)
        end

        for _, m in ipairs(discovery.modulesWithOptions) do
            local fields = {}
            for _, opt in ipairs(m.options) do
                if opt.type ~= "separator" and opt.configKey ~= nil then
                    table.insert(fields, {
                        key = opt.configKey,
                        value = ClonePersistedValue(discovery.getOptionValue(m, opt.configKey)),
                    })
                end
            end
            snapshot.moduleOptions[m] = fields
        end

        for _, special in ipairs(discovery.specials) do
            snapshot.specialEnabled[special] = discovery.isSpecialEnabled(special)
            local fields = {}
            local schema = special.stateSchema
            if schema then
                for _, field in ipairs(GetSchemaConfigFields(schema)) do
                    table.insert(fields, {
                        key = field.configKey,
                        value = ClonePersistedValue(ReadPersisted(special.mod, field.configKey)),
                    })
                end
            end
            snapshot.specialFields[special] = fields
        end

        return snapshot
    end

    local function RestoreApplySnapshot(snapshot)
        local rollbackErrors = {}

        for _, m in ipairs(discovery.modulesWithOptions) do
            local fields = snapshot.moduleOptions[m] or {}
            for _, entry in ipairs(fields) do
                discovery.setOptionValue(m, entry.key, ClonePersistedValue(entry.value))
            end
        end

        for _, special in ipairs(discovery.specials) do
            local fields = snapshot.specialFields[special] or {}
            for _, entry in ipairs(fields) do
                WritePersisted(special.mod, entry.key, ClonePersistedValue(entry.value))
            end
        end

        ReloadManagedUiState()

        for _, m in ipairs(discovery.modules) do
            local previousEnabled = snapshot.moduleEnabled[m]
            local currentEnabled = discovery.isModuleEnabled(m)
            if previousEnabled or currentEnabled ~= previousEnabled then
                local ok, err = discovery.setModuleEnabled(m, previousEnabled)
                if ok == false then
                    table.insert(rollbackErrors, string.format("%s: %s", tostring(m.modName or m.id), tostring(err)))
                end
            end
        end

        for _, special in ipairs(discovery.specials) do
            local previousEnabled = snapshot.specialEnabled[special]
            local currentEnabled = discovery.isSpecialEnabled(special)
            if previousEnabled or currentEnabled ~= previousEnabled then
                local ok, err = discovery.setSpecialEnabled(special, previousEnabled)
                if ok == false then
                    table.insert(rollbackErrors,
                        string.format("%s: %s", tostring(special.modName), tostring(err)))
                end
            end
        end

        if #rollbackErrors > 0 then
            return false, table.concat(rollbackErrors, "; ")
        end
        return true, nil
    end

    local function FailApplyHash(snapshot, err)
        lib.contractWarn(packId,
            "ApplyConfigHash failed; restoring previous state: %s",
            tostring(err))
        local rollbackOk, rollbackErr = RestoreApplySnapshot(snapshot)
        if not rollbackOk then
            lib.contractWarn(packId,
                "ApplyConfigHash rollback incomplete: %s",
                tostring(rollbackErr))
        end
        return false
    end

    local BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

    -- =============================================================================
    -- BASE62 (used for fingerprint generation)
    -- =============================================================================

    --- Encode a non-negative integer as a base62 string.
    --- @param n number Integer value in the supported hash range.
    --- @return string encoded
    function Hash.EncodeBase62(n)
        if n == 0 then return "0" end
        local result = ""
        while n > 0 do
            local idx = (n % 62) + 1
            result = string.sub(BASE62, idx, idx) .. result
            n = math.floor(n / 62)
        end
        return result
    end

    --- Decode a base62 string produced by `Hash.EncodeBase62(...)`.
    --- @param str string Base62-encoded string.
    --- @return number|nil decoded Decoded integer, or nil when the string is invalid.
    function Hash.DecodeBase62(str)
        local n = 0
        for i = 1, #str do
            local c = string.sub(str, i, i)
            local idx = string.find(BASE62, c, 1, true)
            if not idx then return nil end
            n = n * 62 + (idx - 1)
        end
        return n
    end

    -- =============================================================================
    -- SERIALIZATION
    -- =============================================================================

    -- Sort keys for stable output, then join as "key=value|key=value"
    local function Serialize(kv)
        local keys = {}
        for k in pairs(kv) do
            table.insert(keys, k)
        end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            table.insert(parts, k .. "=" .. kv[k])
        end
        return table.concat(parts, "|")
    end

    -- Parse "key=value|key=value" into a table. Returns {} on empty input.
    local function Deserialize(str)
        local kv = {}
        if not str or str == "" then return kv end
        for entry in string.gmatch(str .. "|", "([^|]*)|") do
            local k, v = string.match(entry, "^([^=]+)=(.*)$")
            if k and v then
                kv[k] = v
            end
        end
        return kv
    end

    -- Two independent djb2 passes with different seeds, concatenated.
    -- Each pass produces up to 6 base62 chars (30-bit range), padded to fixed width.
    -- Combined: always exactly 12 chars, ~60 bits of collision resistance.
    local function HashChunk(str, seed, multiplier)
        local h = seed
        for i = 1, #str do
            h = (h * multiplier + string.byte(str, i)) % 1073741824 -- 2^30
        end
        return h
    end

    local function EncodeBase62Fixed(n, width)
        local s = Hash.EncodeBase62(n)
        while #s < width do s = "0" .. s end
        return s
    end

    local function Fingerprint(str)
        local h1 = HashChunk(str, 5381, 33)
        local h2 = HashChunk(str, 52711, 37)
        return EncodeBase62Fixed(h1, 6) .. EncodeBase62Fixed(h2, 6)
    end

    -- Stable string key for a configKey that may be a string or table path.
    -- {"Parent", "Child"} -> "Parent.Child",  "SimpleKey" -> "SimpleKey"
    local function KeyStr(configKey)
        if type(configKey) == "table" then
            return table.concat(configKey, ".")
        end
        return tostring(configKey)
    end

    -- Encode/decode delegates to the field type defined in lib.FieldTypes
    local function EncodeValue(field, value, entryLabel)
        local fieldType = lib.FieldTypes[field.type]
        if not fieldType then
            lib.contractWarn(packId,
                "GetConfigHash: skipping %s '%s' with unknown field type '%s'",
                entryLabel, tostring(field._schemaKey or KeyStr(field.configKey)), tostring(field.type))
            return nil
        end
        return fieldType.toHash(field, value)
    end

    local function DecodeValue(field, str, entryLabel)
        local fieldType = lib.FieldTypes[field.type]
        if not fieldType then
            lib.contractWarn(packId,
                "ApplyConfigHash: defaulting %s '%s' with unknown field type '%s'",
                entryLabel, tostring(field._schemaKey or KeyStr(field.configKey)), tostring(field.type))
            return field.default
        end
        return fieldType.fromHash(field, str)
    end

    -- =============================================================================
    -- CONFIG HASH
    -- =============================================================================

    --- Compute the canonical config hash and short fingerprint for the current pack state.
    --- @param source table|nil Optional staging snapshot with `modules[id]` and `specials[modName]` enabled states.
    --- @return string canonical Stable canonical hash payload for export/profile save.
    --- @return string fingerprint Short base62 fingerprint for HUD display.
    function Hash.GetConfigHash(source)
        local kv = {}

        -- Boolean module enabled states (omit if matches module default)
        for _, m in ipairs(discovery.modules) do
            local enabled
            if source then
                enabled = source.modules and source.modules[m.id]
            else
                enabled = discovery.isModuleEnabled(m)
            end
            if enabled == nil then enabled = false end
            local default = m.default == true -- treat nil default as false
            if enabled ~= default then
                kv[m.id] = enabled and "1" or "0"
            end
        end

        -- Inline option values (omit if matches field default)
        for _, m in ipairs(discovery.modulesWithOptions) do
            for _, opt in ipairs(m.options) do
                if opt.type ~= "separator" and opt.configKey ~= nil then
                    local current = discovery.getOptionValue(m, opt.configKey)
                    if not lib.valuesEqual(opt, current, opt.default) then
                        local encoded = EncodeValue(opt, current, "option")
                        if encoded ~= nil then
                            kv[opt._hashKey or (m.id .. "." .. opt.configKey)] = encoded
                        end
                    end
                end
            end
        end

        -- Special module enabled states and state schema values
        for _, special in ipairs(discovery.specials) do
            -- Enabled state (default is false; only encode if true)
            local enabled
            if source then
                enabled = source.specials and source.specials[special.modName]
            else
                enabled = discovery.isSpecialEnabled(special)
            end
            if enabled == nil then enabled = false end
            if enabled then
                kv[special.modName] = "1"
            end

            -- State schema values (omit if matches field default)
            local schema = special.stateSchema
            if schema then
                for _, field in ipairs(GetSchemaConfigFields(schema)) do
                    local current = ReadPersisted(special.mod, field.configKey)
                    if not lib.valuesEqual(field, current, field.default) then
                        local encoded = EncodeValue(field, current, "schema field")
                        if encoded ~= nil then
                            kv[special.modName .. "." .. (field._schemaKey or KeyStr(field.configKey))] = encoded
                        end
                    end
                end
            end
        end

        local payload = Serialize(kv)
        local canonical = "_v=" .. HASH_VERSION
            .. (payload ~= "" and "|" .. payload or "")
        return canonical, Fingerprint(canonical)
    end

    --- Apply a canonical config hash to the pack, with rollback on later failure.
    --- @param hash string Canonical hash payload to decode and apply.
    --- @return boolean success True when the full import completed successfully.
    function Hash.ApplyConfigHash(hash)
        if hash == nil or hash == "" then
            lib.warn(packId, config.DebugMode, "ApplyConfigHash: empty hash")
            return false
        end

        local kv = Deserialize(hash)

        if kv["_v"] == nil then
            lib.warn(packId, config.DebugMode,
                "ApplyConfigHash: unrecognized format (missing version key) — hash may be from an older format")
            return false
        end

        local version = tonumber(kv["_v"]) or 1
        if version > HASH_VERSION then
            lib.contractWarn(packId,
                "ApplyConfigHash: hash version %d is newer than supported (%d) — some settings may not apply",
                version, HASH_VERSION)
        end

        local snapshot = CaptureApplySnapshot()
        local moduleTargets = {}
        local specialTargets = {}

        -- Capture enabled-state targets first, then write all option/schema values
        -- before any apply() calls run. This ensures data-mutation modules see the
        -- final decoded config when profile/hash application enables them.
        for _, m in ipairs(discovery.modules) do
            local stored = kv[m.id]
            if stored ~= nil then
                moduleTargets[m] = stored == "1"
            else
                moduleTargets[m] = m.default == true
            end
        end

        local okWrite, writeErr = xpcall(function()
            -- Inline option values
            for _, m in ipairs(discovery.modulesWithOptions) do
                for _, opt in ipairs(m.options) do
                    if opt.type ~= "separator" and opt.configKey ~= nil then
                        local stored = kv[opt._hashKey or (m.id .. "." .. opt.configKey)]
                        if stored ~= nil then
                            discovery.setOptionValue(m, opt.configKey, DecodeValue(opt, stored, "option"))
                        else
                            discovery.setOptionValue(m, opt.configKey, opt.default)
                        end
                    end
                end
            end

            -- Special module enabled states and state schema values
            for _, special in ipairs(discovery.specials) do
                local storedEnabled = kv[special.modName]
                specialTargets[special] = storedEnabled == "1"

                local schema = special.stateSchema
                if schema then
                    for _, field in ipairs(GetSchemaConfigFields(schema)) do
                        local storedField = kv[special.modName .. "." .. (field._schemaKey or KeyStr(field.configKey))]
                        if storedField ~= nil then
                            WritePersisted(special.mod, field.configKey, DecodeValue(field, storedField, "schema field"))
                        else
                            WritePersisted(special.mod, field.configKey, field.default)
                        end
                    end
                end
            end
        end, debug.traceback)
        if not okWrite then
            return FailApplyHash(snapshot, writeErr)
        end

        ReloadManagedUiState()

        -- Apply enabled states after all decoded values are in place.
        for _, m in ipairs(discovery.modules) do
            local ok, err = discovery.setModuleEnabled(m, moduleTargets[m])
            if ok == false then
                return FailApplyHash(snapshot, err)
            end
        end

        for _, special in ipairs(discovery.specials) do
            local ok, err = discovery.setSpecialEnabled(special, specialTargets[special])
            if ok == false then
                return FailApplyHash(snapshot, err)
            end
        end

        return true
    end

    return Hash
end
