function Framework.createHash(discovery, config, lib, packId)
    local HASH_VERSION = 1
    local Hash = {}
    local StorageTypes = lib.StorageTypes

    local function ReadPersisted(mod, key)
        return mod.store.read(key)
    end

    local function WritePersisted(mod, key, value)
        mod.store.write(key, value)
    end

    local function ClonePersistedValue(value)
        if type(value) == "table" then
            return rom.game.DeepCopyTable(value)
        end
        return value
    end

    local function GetRootStorage(entry)
        if type(entry.storage) ~= "table" then
            return {}
        end
        return lib.getStorageRoots(entry.storage)
    end

    local function ReloadManagedUiState()
        for _, m in ipairs(discovery.modulesWithUi) do
            local uiState = m.mod.store and m.mod.store.uiState
            if uiState and uiState.reloadFromConfig then
                uiState.reloadFromConfig()
            end
        end
        for _, special in ipairs(discovery.specials) do
            local uiState = special.uiState or (special.mod.store and special.mod.store.uiState)
            if uiState and uiState.reloadFromConfig then
                uiState.reloadFromConfig()
            end
        end
    end

    local function CaptureApplySnapshot()
        local snapshot = {
            moduleEnabled = {},
            moduleStorage = {},
            specialEnabled = {},
            specialStorage = {},
        }

        for _, m in ipairs(discovery.modules) do
            snapshot.moduleEnabled[m] = discovery.isModuleEnabled(m)
            local roots = {}
            for _, root in ipairs(GetRootStorage(m)) do
                table.insert(roots, {
                    alias = root.alias,
                    value = ClonePersistedValue(ReadPersisted(m.mod, root.alias)),
                })
            end
            snapshot.moduleStorage[m] = roots
        end

        for _, special in ipairs(discovery.specials) do
            snapshot.specialEnabled[special] = discovery.isSpecialEnabled(special)
            local roots = {}
            for _, root in ipairs(GetRootStorage(special)) do
                table.insert(roots, {
                    alias = root.alias,
                    value = ClonePersistedValue(ReadPersisted(special.mod, root.alias)),
                })
            end
            snapshot.specialStorage[special] = roots
        end

        return snapshot
    end

    local function RestoreApplySnapshot(snapshot)
        local rollbackErrors = {}

        for _, m in ipairs(discovery.modules) do
            local roots = snapshot.moduleStorage[m] or {}
            for _, entry in ipairs(roots) do
                WritePersisted(m.mod, entry.alias, ClonePersistedValue(entry.value))
            end
        end

        for _, special in ipairs(discovery.specials) do
            local roots = snapshot.specialStorage[special] or {}
            for _, entry in ipairs(roots) do
                WritePersisted(special.mod, entry.alias, ClonePersistedValue(entry.value))
            end
        end

        ReloadManagedUiState()

        for _, m in ipairs(discovery.modules) do
            local previousEnabled = snapshot.moduleEnabled[m]
            if previousEnabled then
                local ok, err = discovery.setModuleEnabled(m, previousEnabled)
                if ok == false then
                    table.insert(rollbackErrors, string.format("%s: %s", tostring(m.modName or m.id), tostring(err)))
                end
            end
        end

        for _, special in ipairs(discovery.specials) do
            local previousEnabled = snapshot.specialEnabled[special]
            if previousEnabled then
                local ok, err = discovery.setSpecialEnabled(special, previousEnabled)
                if ok == false then
                    table.insert(rollbackErrors, string.format("%s: %s", tostring(special.modName), tostring(err)))
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

    local function HashChunk(str, seed, multiplier)
        local h = seed
        for i = 1, #str do
            h = (h * multiplier + string.byte(str, i)) % 1073741824
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

    local function EncodeValue(root, value, entryLabel)
        local storageType = StorageTypes[root.type]
        if not storageType then
            lib.contractWarn(packId,
                "GetConfigHash: skipping %s '%s' with unknown storage type '%s'",
                entryLabel, tostring(root.alias), tostring(root.type))
            return nil
        end
        return storageType.toHash(root, value)
    end

    local function DecodeValue(root, str, entryLabel)
        local storageType = StorageTypes[root.type]
        if not storageType then
            lib.contractWarn(packId,
                "ApplyConfigHash: defaulting %s '%s' with unknown storage type '%s'",
                entryLabel, tostring(root.alias), tostring(root.type))
            return root.default
        end
        return storageType.fromHash(root, str)
    end

    function Hash.GetConfigHash(source)
        local kv = {}

        for _, m in ipairs(discovery.modules) do
            local enabled
            if source then
                enabled = source.modules and source.modules[m.id]
            else
                enabled = discovery.isModuleEnabled(m)
            end
            if enabled == nil then enabled = false end
            local default = m.default == true
            if enabled ~= default then
                kv[m.id] = enabled and "1" or "0"
            end

            for _, root in ipairs(GetRootStorage(m)) do
                local current = ReadPersisted(m.mod, root.alias)
                if not lib.valuesEqual(root, current, root.default) then
                    local encoded = EncodeValue(root, current, "storage root")
                    if encoded ~= nil then
                        kv[m.id .. "." .. root.alias] = encoded
                    end
                end
            end
        end

        for _, special in ipairs(discovery.specials) do
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

            for _, root in ipairs(GetRootStorage(special)) do
                local current = ReadPersisted(special.mod, root.alias)
                if not lib.valuesEqual(root, current, root.default) then
                    local encoded = EncodeValue(root, current, "storage root")
                    if encoded ~= nil then
                        kv[special.modName .. "." .. root.alias] = encoded
                    end
                end
            end
        end

        local payload = Serialize(kv)
        local canonical = "_v=" .. HASH_VERSION .. (payload ~= "" and "|" .. payload or "")
        return canonical, Fingerprint(canonical)
    end

    function Hash.ApplyConfigHash(hash)
        if hash == nil or hash == "" then
            lib.warn(packId, config.DebugMode, "ApplyConfigHash: empty hash")
            return false
        end

        local kv = Deserialize(hash)
        if kv["_v"] == nil then
            lib.warn(packId, config.DebugMode,
                "ApplyConfigHash: unrecognized format (missing version key)")
            return false
        end

        local version = tonumber(kv["_v"]) or 1
        if version > HASH_VERSION then
            lib.contractWarn(packId,
                "ApplyConfigHash: hash version %d is newer than supported (%d)",
                version, HASH_VERSION)
        end

        local snapshot = CaptureApplySnapshot()
        local moduleTargets = {}
        local specialTargets = {}

        for _, m in ipairs(discovery.modules) do
            local stored = kv[m.id]
            if stored ~= nil then
                moduleTargets[m] = stored == "1"
            else
                moduleTargets[m] = m.default == true
            end
        end

        local okWrite, writeErr = xpcall(function()
            for _, m in ipairs(discovery.modules) do
                for _, root in ipairs(GetRootStorage(m)) do
                    local stored = kv[m.id .. "." .. root.alias]
                    if stored ~= nil then
                        WritePersisted(m.mod, root.alias, DecodeValue(root, stored, "storage root"))
                    else
                        WritePersisted(m.mod, root.alias, root.default)
                    end
                end
            end

            for _, special in ipairs(discovery.specials) do
                local storedEnabled = kv[special.modName]
                specialTargets[special] = storedEnabled == "1"

                for _, root in ipairs(GetRootStorage(special)) do
                    local stored = kv[special.modName .. "." .. root.alias]
                    if stored ~= nil then
                        WritePersisted(special.mod, root.alias, DecodeValue(root, stored, "storage root"))
                    else
                        WritePersisted(special.mod, root.alias, root.default)
                    end
                end
            end
        end, debug.traceback)
        if not okWrite then
            return FailApplyHash(snapshot, writeErr)
        end

        ReloadManagedUiState()

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
