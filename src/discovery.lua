-- =============================================================================
-- MODULE DISCOVERY
-- =============================================================================
-- Auto-discovers all installed modules that opt in via definition.modpack = packId.
-- Regular modules: definition.special is nil/false.
-- Special modules: definition.special = true.
-- Modules are sorted alphabetically by display name within each category.

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
                lib.warn(packId, true,
                    "reserved hash namespace '%s' is used by: %s; skipping all conflicting entries",
                    tostring(namespace), table.concat(labels, ", "))
            elseif #entries > 1 then
                duplicateNamespaces[namespace] = true
                table.sort(entries, function(a, b) return a.modName < b.modName end)
                local labels = {}
                for _, item in ipairs(entries) do
                    table.insert(labels, item.modName .. " (" .. item.kind .. ")")
                end
                lib.warn(packId, true,
                    "duplicate hash namespace '%s' across entries: %s; skipping all conflicting entries",
                    tostring(namespace), table.concat(labels, ", "))
            end
        end

        for _, entry in ipairs(found) do
            local modName = entry.modName
            local mod     = entry.mod
            local def     = entry.def
            local inferredMutationMode, mutationInfo = lib.inferMutationMode(def)

            if def.mutationMode ~= nil then
                local isKnownMode = def.mutationMode == lib.MutationMode.Patch
                    or def.mutationMode == lib.MutationMode.Manual
                    or def.mutationMode == lib.MutationMode.Hybrid
                if not isKnownMode then
                    lib.warn(packId, config.DebugMode,
                        "%s: definition.mutationMode must be lib.MutationMode.Patch, Manual, or Hybrid; got %s",
                        modName, tostring(def.mutationMode))
                elseif inferredMutationMode and def.mutationMode ~= inferredMutationMode then
                    lib.warn(packId, config.DebugMode,
                        "%s: definition.mutationMode=%s does not match inferred mutation shape %s",
                        modName, tostring(def.mutationMode), tostring(inferredMutationMode))
                end
            end

            if def.dataMutation and not inferredMutationMode then
                lib.warn(packId, config.DebugMode,
                    "%s: dataMutation=true but module exposes neither patchPlan nor apply/revert",
                    modName)
            end

            if def.special then
                local hasLifecycle = mutationInfo.hasManual or mutationInfo.hasPatch
                if duplicateNamespaces[modName] then
                    -- Already warned once for the full collision set above.
                elseif not def.name or not hasLifecycle then
                    lib.warn(packId, config.DebugMode,
                        "Skipping special %s: missing name, apply/revert, or patchPlan", modName)
                elseif type(def.stateSchema) ~= "table" then
                    lib.warn(packId, config.DebugMode,
                        "Skipping special %s: missing definition.stateSchema", modName)
                else
                    local store = GetStore(mod)
                    if not store or type(store.read) ~= "function" or type(store.write) ~= "function" then
                        lib.warn(packId, config.DebugMode,
                            "%s: special module is missing public.store", modName)
                    elseif not GetUiState(mod) then
                        lib.warn(packId, config.DebugMode,
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
                if duplicateNamespaces[def.id] then
                    -- Already warned once for the full collision set above.
                elseif not def.id or not hasLifecycle then
                    lib.warn(packId, config.DebugMode, "Skipping %s: missing id, apply/revert, or patchPlan", modName)
                elseif not GetStore(mod) or type(GetStore(mod).read) ~= "function" or type(GetStore(mod).write) ~= "function" then
                    lib.warn(packId, config.DebugMode, "%s: module is missing public.store", modName)
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
                                lib.warn(packId, config.DebugMode,
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
                                lib.warn(packId, config.DebugMode,
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

    --- Read a module's current Enabled state from its own config.
    function Discovery.isModuleEnabled(module)
        return ReadPersisted(module.mod, "Enabled") == true
    end

    --- Write a module's Enabled state and call enable/disable.
    function Discovery.setModuleEnabled(module, enabled)
        WritePersisted(module.mod, "Enabled", enabled)
        local ok, err
        if enabled then
            ok, err = lib.applyDefinition(module.definition, GetStore(module.mod))
        else
            ok, err = lib.revertDefinition(module.definition, GetStore(module.mod))
        end
        if not ok then
            lib.warn(packId, config.DebugMode,
                "%s %s failed: %s", module.modName, enabled and "enable" or "disable", err)
        end
    end

    --- Read a module option's current value from its config.
    function Discovery.getOptionValue(module, configKey)
        return ReadPersisted(module.mod, configKey)
    end

    --- Write a module option's value to its config.
    function Discovery.setOptionValue(module, configKey, value)
        WritePersisted(module.mod, configKey, value)
    end

    --- Read a special module's Enabled state from its config.
    function Discovery.isSpecialEnabled(special)
        return ReadPersisted(special.mod, "Enabled") == true
    end

    --- Write a special module's Enabled state and call enable/disable.
    function Discovery.setSpecialEnabled(special, enabled)
        WritePersisted(special.mod, "Enabled", enabled)
        local ok, err
        if enabled then
            ok, err = lib.applyDefinition(special.definition, GetStore(special.mod))
        else
            ok, err = lib.revertDefinition(special.definition, GetStore(special.mod))
        end
        if not ok then
            lib.warn(packId, config.DebugMode,
                "%s %s failed: %s", special.modName, enabled and "enable" or "disable", err)
        end
    end

    --- Read a module or special's DebugMode state from its config.
    function Discovery.isDebugEnabled(entry)
        return ReadPersisted(entry.mod, "DebugMode") == true
    end

    --- Write a module or special's DebugMode state to its config.
    function Discovery.setDebugEnabled(entry, val)
        WritePersisted(entry.mod, "DebugMode", val)
    end

    return Discovery
end
