-- =============================================================================
-- Test utilities: mock engine globals and load Framework for testing
-- =============================================================================

public = {}
_PLUGIN = { guid = "test-framework" }

local function deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deepCopy(v)
    end
    return copy
end

rom = {
    mods = {},
    game = {
        DeepCopyTable = deepCopy,
        SetupRunData = function() end,
    },
    ImGui = {},
    ImGuiCol = {
        Text = 1,
        TextDisabled = 2,
        WindowBg = 3,
        ChildBg = 4,
        Header = 5,
        HeaderHovered = 6,
        HeaderActive = 7,
        Button = 8,
        ButtonHovered = 9,
        ButtonActive = 10,
        FrameBg = 11,
        FrameBgHovered = 12,
        FrameBgActive = 13,
        CheckMark = 14,
        Tab = 15,
        TabHovered = 16,
        TabActive = 17,
        Separator = 18,
        Border = 19,
        TitleBgActive = 20,
    },
    gui = {
        add_to_menu_bar = function() end,
        add_imgui = function() end,
        add_always_draw_imgui = function() end,
        is_open = function() return true end,
    },
}

rom.mods['SGG_Modding-ENVY'] = {
    auto = function() return {} end,
}

rom.mods['SGG_Modding-Chalk'] = {
    auto = function() return { DebugMode = false } end,
}

import = function(path)
    dofile("../adamant-ModpackLib/src/" .. path)
end

Warnings = {}

function CaptureWarnings()
    Warnings = {}
    lib.config.DebugMode = true
    _originalPrint = print
    print = function(msg)
        table.insert(Warnings, msg)
    end
end

function RestoreWarnings()
    lib.config.DebugMode = false
    print = _originalPrint or print
    Warnings = {}
end

dofile("../adamant-ModpackLib/src/main.lua")
lib = public
rom.mods['adamant-ModpackLib'] = lib

import = function() end
import_as_fallback = function() end

dofile("src/main.lua")
dofile("src/ui_theme.lua")
dofile("src/discovery.lua")
dofile("src/hash.lua")
dofile("src/ui.lua")

config = { ModEnabled = true, DebugMode = false }

MockDiscovery = {}

local function makePersistedConfig(storage, overrides)
    local persisted = {
        Enabled = false,
        DebugMode = false,
    }
    for _, root in ipairs(storage or {}) do
        persisted[root.configKey] = overrides and overrides[root.alias] or root.default
    end
    if overrides then
        for key, value in pairs(overrides) do
            if persisted[key] == nil then
                persisted[key] = value
            end
        end
    end
    return persisted
end

function MockDiscovery.create(moduleDefs, specialDefs)
    moduleDefs = moduleDefs or {}
    specialDefs = specialDefs or {}

    local discovery = {
        modules = {},
        modulesById = {},
        modulesWithUi = {},
        modulesWithQuickUi = {},
        specials = {},
        categories = {},
        byCategory = {},
        categoryLayouts = {},
        unifiedTabOrder = {},
    }

    local seenCategories = {}

    local function addModule(def)
        local persisted = makePersistedConfig(def.storage, def.values)
        persisted.Enabled = def.enabled == true
        persisted.DebugMode = def.debug == true

        local definition = {
            id = def.id,
            name = def.name or def.id,
            category = def.category or "General",
            default = def.default == true,
            storage = def.storage or {},
            ui = def.ui or {},
            hashGroups = def.hashGroups,
            selectQuickUi = def.selectQuickUi,
            affectsRunData = def.affectsRunData == true,
            apply = def.apply,
            revert = def.revert,
            patchPlan = def.patchPlan,
        }
        local store = lib.createStore(persisted, definition)
        local module = {
            modName = def.modName or ("adamant-" .. def.id),
            mod = { store = store, definition = definition },
            definition = definition,
            id = definition.id,
            name = definition.name,
            category = definition.category,
            subgroup = def.subgroup or "General",
            default = definition.default,
            storage = definition.storage,
            ui = definition.ui,
        }

        table.insert(discovery.modules, module)
        discovery.modulesById[module.id] = module

        if type(module.ui) == "table" and #module.ui > 0 then
            table.insert(discovery.modulesWithUi, module)
            local quickUi = lib.collectQuickUiNodes(module.ui)
            if #quickUi > 0 then
                module.quickUi = quickUi
                table.insert(discovery.modulesWithQuickUi, module)
            end
        end

        local category = module.category
        if not seenCategories[category] then
            seenCategories[category] = true
            table.insert(discovery.categories, { key = category, label = category })
        end
        discovery.byCategory[category] = discovery.byCategory[category] or {}
        table.insert(discovery.byCategory[category], module)
    end

    local function addSpecial(def)
        local persisted = makePersistedConfig(def.storage, def.values)
        persisted.Enabled = def.enabled == true
        persisted.DebugMode = def.debug == true

        local definition = {
            special = true,
            name = def.name or def.modName,
            shortName = def.shortName,
            storage = def.storage or {},
            ui = def.ui or {},
            hashGroups = def.hashGroups,
            affectsRunData = def.affectsRunData == true,
            apply = def.apply,
            revert = def.revert,
            patchPlan = def.patchPlan,
        }
        local store = lib.createStore(persisted, definition)
        local special = {
            modName = def.modName,
            mod = {
                store = store,
                definition = definition,
                DrawTab = def.DrawTab,
                DrawQuickContent = def.DrawQuickContent,
            },
            definition = definition,
            storage = definition.storage,
            ui = definition.ui,
            uiState = store.uiState,
            _tabLabel = definition.shortName or definition.name,
        }
        table.insert(discovery.specials, special)
    end

    for _, def in ipairs(moduleDefs) do
        addModule(def)
    end
    for _, def in ipairs(specialDefs) do
        addSpecial(def)
    end

    function discovery.isModuleEnabled(module)
        return module.mod.store.read("Enabled") == true
    end

    function discovery.setModuleEnabled(module, enabled)
        return lib.setDefinitionEnabled(module.definition, module.mod.store, enabled)
    end

    function discovery.getStorageValue(module, aliasOrKey)
        return module.mod.store.read(aliasOrKey)
    end

    function discovery.setStorageValue(module, aliasOrKey, value)
        module.mod.store.write(aliasOrKey, value)
    end

    function discovery.isSpecialEnabled(special)
        return special.mod.store.read("Enabled") == true
    end

    function discovery.setSpecialEnabled(special, enabled)
        return lib.setDefinitionEnabled(special.definition, special.mod.store, enabled)
    end

    function discovery.isDebugEnabled(entry)
        return entry.mod.store.read("DebugMode") == true
    end

    function discovery.setDebugEnabled(entry, value)
        entry.mod.store.write("DebugMode", value)
    end

    return discovery
end
