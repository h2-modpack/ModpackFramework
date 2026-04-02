-- =============================================================================
-- MODULE DISCOVERY
-- =============================================================================
-- Auto-discovers all installed modules that opt in via definition.modpack = packId.
-- Regular modules: definition.special is nil/false.
-- Special modules: definition.special = true.
-- Modules are sorted alphabetically by display name within each category.

--- Create the discovery subsystem for one coordinator pack.
--- @param packId string Pack identifier used to filter opted-in modules.
--- @param config table Coordinator config table containing at least `DebugMode`.
--- @param lib table Adamant Modpack Lib export.
--- @return table discovery Discovery object with `run`, state accessors, and discovered entry lists.
function Framework.createDiscovery(packId, config, lib)
    local Discovery = {}

    local function GetStore(mod)
        return type(mod.store) == "table" and mod.store or nil
    end

    local function ReadPersisted(mod, key)
        return GetStore(mod).read(key)
    end

    local function WritePersisted(mod, key, value)
        GetStore(mod).write(key, value)
    end

    local function GetUiState(mod)
        local store = GetStore(mod)
        return store and store.uiState or nil
    end

    -- -------------------------------------------------------------------------
    -- DISCOVERY STATE
    -- -------------------------------------------------------------------------

    -- Populated by Discovery.run()
    Discovery.modules = {}            -- ordered list of discovered boolean modules
    Discovery.modulesById = {}        -- id -> module entry
    Discovery.modulesWithOptions = {} -- ordered list of modules that have definition.options
    Discovery.specials = {}           -- ordered list of discovered special modules

    Discovery.categories = {}         -- ordered list of { key, label }
    Discovery.byCategory = {}         -- category key -> ordered list of modules
    Discovery.categoryLayouts = {}    -- category key -> UI layout (groups)

    -- -------------------------------------------------------------------------
    -- DISCOVERY
    -- -------------------------------------------------------------------------

    --- Discover all modules/specials for this pack and build category layouts.
    --- @param groupStyle table|nil Optional per-category/per-group style overrides.
    --- @param groupStyleDefault string|nil Default group style when not overridden.
    --- @param categoryOrder table|nil Optional ordered list of category names to pin first.
    function Discovery.run(groupStyle, groupStyleDefault, categoryOrder)
        local mods = rom.mods

        -- Collect all opted-in modules
        local found = {}
        for modName, mod in pairs(mods) do
            if type(mod) == "table" and mod.definition and
                mod.definition.modpack and mod.definition.modpack == packId then
                table.insert(found, { modName = modName, mod = mod, def = mod.definition })
            end
        end

        -- Sort alphabetically by display name for stable UI ordering
        table.sort(found, function(a, b)
            return (a.def.name or a.def.id or a.modName) < (b.def.name or b.def.id or b.modName)
        end)

        local categorySet = {}
        local duplicateNamespaces = {}
        local namespaceEntries = {}

        for _, entry in ipairs(found) do
            local def = entry.def
            local namespace = def.special and entry.modName or def.id
            if namespace ~= nil then
                namespaceEntries[namespace] = namespaceEntries[namespace] or {}
                table.insert(namespaceEntries[namespace], {
                    modName = entry.modName,
                    kind = def.special and "special" or "module",
                })
            end
        end

        for namespace, entries in pairs(namespaceEntries) do
            if namespace == "_v" then
                duplicateNamespaces[namespace] = true
                table.sort(entries, function(a, b) return a.modName < b.modName end)
                local labels = {}
                for _, item in ipairs(entries) do
                    table.insert(labels, item.modName .. " (" .. item.kind .. ")")
                end
                lib.contractWarn(packId,
                    "reserved hash namespace '%s' is used by: %s; skipping all conflicting entries",
                    tostring(namespace), table.concat(labels, ", "))
            elseif #entries > 1 then
                duplicateNamespaces[namespace] = true
                table.sort(entries, function(a, b) return a.modName < b.modName end)
                local labels = {}
                for _, item in ipairs(entries) do
                    table.insert(labels, item.modName .. " (" .. item.kind .. ")")
                end
                lib.contractWarn(packId,
                    "duplicate hash namespace '%s' across entries: %s; skipping all conflicting entries",
                    tostring(namespace), table.concat(labels, ", "))
            end
        end

        for _, entry in ipairs(found) do
            local modName = entry.modName
            local mod     = entry.mod
            local def     = entry.def
            local inferredMutationShape, mutationInfo = lib.inferMutationShape(def)

            if lib.affectsRunData(def) and not inferredMutationShape then
                lib.contractWarn(packId,
                    "%s: affectsRunData=true but module exposes neither patchPlan nor apply/revert",
                    modName)
            end

            if def.special then
                local hasLifecycle = mutationInfo.hasManual or mutationInfo.hasPatch
                local lifecycleRequired = lib.affectsRunData(def)
                if duplicateNamespaces[modName] then
                    -- Already warned once for the full collision set above.
                elseif not def.name or (lifecycleRequired and not hasLifecycle) then
                    lib.contractWarn(packId,
                        "Skipping special %s: missing name or lifecycle (patchPlan/apply/revert)", modName)
                elseif type(def.stateSchema) ~= "table" then
                    lib.contractWarn(packId,
                        "Skipping special %s: missing definition.stateSchema", modName)
                else
                    local store = GetStore(mod)
                    if not store or type(store.read) ~= "function" or type(store.write) ~= "function" then
                        lib.contractWarn(packId,
                            "%s: special module is missing public.store", modName)
                    elseif not GetUiState(mod) then
                        lib.contractWarn(packId,
                            "%s: special module is missing public.store.uiState (managed UI state)", modName)
                    else
                        if def.stateSchema then
                            lib.validateSchema(def.stateSchema, modName)
                        end
                        if not mod.DrawTab and not mod.DrawQuickContent then
                            lib.warn(packId, config.DebugMode,
                                "%s: special module exposes neither DrawTab nor DrawQuickContent; tab will be empty",
                                modName)
                        end
                        table.insert(Discovery.specials, {
                            modName      = modName,
                            mod          = mod,
                            definition   = def,
                            stateSchema  = def.stateSchema,
                            uiState      = GetUiState(mod),
                            _enableLabel = "Enable " .. tostring(def.name),
                            _debugLabel  = tostring(def.name) .. "##" .. modName,
                        })
                    end
                end
            else
                local hasLifecycle = mutationInfo.hasManual or mutationInfo.hasPatch
                local lifecycleRequired = lib.affectsRunData(def)
                if duplicateNamespaces[def.id] then
                    -- Already warned once for the full collision set above.
                elseif not def.id or (lifecycleRequired and not hasLifecycle) then
                    lib.contractWarn(packId, "Skipping %s: missing id or lifecycle (patchPlan/apply/revert)", modName)
                elseif not GetStore(mod) or type(GetStore(mod).read) ~= "function" or type(GetStore(mod).write) ~= "function" then
                    lib.contractWarn(packId, "%s: module is missing public.store", modName)
                else
                    local cat = def.category or "General"
                    local module = {
                        modName     = modName,
                        mod         = mod,
                        definition  = def,
                        id          = def.id,
                        name        = def.name,
                        category    = cat,
                        group       = def.group or "General",
                        tooltip     = def.tooltip or "",
                        default     = def.default,
                        options     = def.options,
                        _debugLabel = (def.name or def.id) .. "##" .. def.id,
                    }

                    table.insert(Discovery.modules, module)
                    Discovery.modulesById[def.id] = module
                    if def.options and #def.options > 0 then
                        lib.validateSchema(def.options, modName)
                        local validOptions = {}
                        for index, opt in ipairs(def.options) do
                            opt._pushId = def.id .. "_" .. tostring(opt.configKey or opt.label or opt.type or index)
                            if opt.type == "separator" then
                                table.insert(validOptions, opt)
                            elseif type(opt.configKey) == "table" then
                                lib.contractWarn(packId,
                                    "%s: option configKey is a table -- table-path keys are only valid in stateSchema" ..
                                    " (special modules). Use a flat string key in def.options. Option skipped.", modName)
                            else
                                opt._hashKey = def.id .. "." .. opt.configKey
                                table.insert(validOptions, opt)
                            end
                        end
                        module.options = validOptions
                        if #validOptions > 0 then
                            if not GetUiState(mod) then
                                lib.contractWarn(packId,
                                    "%s: module options are missing public.store.uiState (managed UI state)",
                                    modName)
                            else
                                table.insert(Discovery.modulesWithOptions, module)
                            end
                        end
                    end

                    if not categorySet[cat] then
                        categorySet[cat] = true
                        table.insert(Discovery.categories, { key = cat, label = cat })
                    end

                    Discovery.byCategory[cat] = Discovery.byCategory[cat] or {}
                    table.insert(Discovery.byCategory[cat], module)
                end
            end
        end

        -- Resolve tab labels for all specials; suffix duplicates as (1), (2), ... and warn
        local labelCount = {}
        for _, special in ipairs(Discovery.specials) do
            local label = special.definition.tabLabel or special.definition.name
            labelCount[label] = (labelCount[label] or 0) + 1
        end
        local labelIndex = {}
        for _, special in ipairs(Discovery.specials) do
            local label = special.definition.tabLabel or special.definition.name
            if labelCount[label] > 1 then
                labelIndex[label] = (labelIndex[label] or 0) + 1
                special._tabLabel = label .. " (" .. labelIndex[label] .. ")"
                lib.warn(packId, config.DebugMode,
                    "%s: tabLabel '%s' is shared by multiple specials." ..
                    " Rename tabLabel or definition.name to resolve. Rendering as '%s'.",
                    special.modName, label, special._tabLabel)
            else
                special._tabLabel = label
            end
        end

        -- Sort categories alphabetically by default; coordinators can optionally
        -- force specific categories to the front via def.categoryOrder.
        local categoryRank = {}
        if type(categoryOrder) == "table" then
            local warnedUnknownCategories = {}
            for index, category in ipairs(categoryOrder) do
                if type(category) == "string" then
                    categoryRank[category] = index
                    if not categorySet[category] and not warnedUnknownCategories[category] then
                        warnedUnknownCategories[category] = true
                        lib.warn(packId, config.DebugMode,
                            "categoryOrder contains unknown category '%s'; entry ignored",
                            category)
                    end
                end
            end
        end

        table.sort(Discovery.categories, function(a, b)
            local aRank = categoryRank[a.key]
            local bRank = categoryRank[b.key]
            if aRank and bRank then
                return aRank < bRank
            end
            if aRank then
                return true
            end
            if bRank then
                return false
            end
            return a.label < b.label
        end)

        -- Build UI layouts
        for _, cat in ipairs(Discovery.categories) do
            Discovery.categoryLayouts[cat.key] = Discovery.buildLayout(cat.key, groupStyle, groupStyleDefault)
        end
    end

    -- -------------------------------------------------------------------------
    -- LAYOUT BUILDER
    -- -------------------------------------------------------------------------

    --- Build a grouped checkbox layout for one discovered category.
    --- @param category string Category key.
    --- @param groupStyle table|nil Optional per-category/per-group style overrides.
    --- @param groupStyleDefault string|nil Default group style when not overridden.
    --- @return table layout Array of grouped layout blocks for the UI.
    function Discovery.buildLayout(category, groupStyle, groupStyleDefault)
        local mods = Discovery.byCategory[category] or {}
        local groupOrder = {}
        local groups = {}
        local catStyle = groupStyle and groupStyle[category]

        for _, m in ipairs(mods) do
            local g = m.group
            if not groups[g] then
                local style = (catStyle and catStyle[g]) or groupStyleDefault or "collapsing"
                groups[g] = { Header = g, Items = {}, style = style }
                table.insert(groupOrder, g)
            end
            table.insert(groups[g].Items, {
                Key     = m.id,
                ModName = m.modName,
                Name    = m.name,
                Tooltip = m.tooltip,
            })
        end

        table.sort(groupOrder)

        local layout = {}
        for _, g in ipairs(groupOrder) do
            table.insert(layout, groups[g])
        end
        return layout
    end

    -- -------------------------------------------------------------------------
    -- MODULE STATE ACCESS
    -- -------------------------------------------------------------------------

    --- Read a regular module's persisted Enabled state.
    --- @param module table Discovered regular module entry.
    --- @return boolean enabled
    function Discovery.isModuleEnabled(module)
        return ReadPersisted(module.mod, "Enabled") == true
    end

    --- Commit a regular module's Enabled state only after lifecycle succeeds.
    --- @param module table Discovered regular module entry.
    --- @param enabled boolean Desired enabled state.
    --- @return boolean ok
    --- @return string|nil err
    function Discovery.setModuleEnabled(module, enabled)
        local ok, err = lib.setDefinitionEnabled(module.definition, GetStore(module.mod), enabled)
        if not ok then
            lib.contractWarn(packId,
                "%s %s failed: %s", module.modName, enabled and "enable" or "disable", err)
        end
        return ok, err
    end

    --- Read a regular module option value from persisted config.
    --- @param module table Discovered regular module entry.
    --- @param configKey string|table Option key/path.
    --- @return any value
    function Discovery.getOptionValue(module, configKey)
        return ReadPersisted(module.mod, configKey)
    end

    --- Write a regular module option value to persisted config.
    --- @param module table Discovered regular module entry.
    --- @param configKey string|table Option key/path.
    --- @param value any Value to persist.
    function Discovery.setOptionValue(module, configKey, value)
        WritePersisted(module.mod, configKey, value)
    end

    --- Read a special module's persisted Enabled state.
    --- @param special table Discovered special entry.
    --- @return boolean enabled
    function Discovery.isSpecialEnabled(special)
        return ReadPersisted(special.mod, "Enabled") == true
    end

    --- Commit a special module's Enabled state only after lifecycle succeeds.
    --- @param special table Discovered special entry.
    --- @param enabled boolean Desired enabled state.
    --- @return boolean ok
    --- @return string|nil err
    function Discovery.setSpecialEnabled(special, enabled)
        local ok, err = lib.setDefinitionEnabled(special.definition, GetStore(special.mod), enabled)
        if not ok then
            lib.contractWarn(packId,
                "%s %s failed: %s", special.modName, enabled and "enable" or "disable", err)
        end
        return ok, err
    end

    --- Read a module or special's persisted DebugMode state.
    --- @param entry table Discovered regular or special entry.
    --- @return boolean enabled
    function Discovery.isDebugEnabled(entry)
        return ReadPersisted(entry.mod, "DebugMode") == true
    end

    --- Write a module or special's DebugMode state to persisted config.
    --- @param entry table Discovered regular or special entry.
    --- @param val boolean Desired DebugMode state.
    function Discovery.setDebugEnabled(entry, val)
        WritePersisted(entry.mod, "DebugMode", val)
    end

    return Discovery
end
