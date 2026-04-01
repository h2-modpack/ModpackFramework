-- =============================================================================
-- Test utilities: mock engine globals and load Framework for testing
-- =============================================================================

-- Mock public/ENVY
public = {}
_PLUGIN = { guid = "test-framework" }

-- Deep copy
local function deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deepCopy(v)
    end
    return copy
end

-- Mock rom
rom = {
    mods = {},
    game = {
        DeepCopyTable = deepCopy,
        SetupRunData = function() end,
    },
    ImGui = {},
    gui = {
        add_to_menu_bar = function() end,
        add_imgui = function() end,
    },
}

rom.mods['SGG_Modding-ENVY'] = {
    auto = function() return {} end,
}

-- Minimal Chalk mock: auto() returns a plain table (the "config")
rom.mods['SGG_Modding-Chalk'] = {
    auto = function() return { DebugMode = false } end,
}

import = function(path)
    dofile("../adamant-ModpackLib/src/" .. path)
end

-- Warning capture
Warnings = {}

function CaptureWarnings()
    Warnings = {}
    _originalPrint = print
    print = function(msg)
        table.insert(Warnings, msg)
    end
end

function RestoreWarnings()
    print = _originalPrint or print
    Warnings = {}
end

-- Load Lib first (Framework depends on it)
dofile("../adamant-ModpackLib/src/main.lua")
lib = public

-- Set up lib as a rom mod so Framework can find it
rom.mods['adamant-ModpackLib'] = lib

-- Load Framework factory functions directly.
-- Framework.init is NOT called — only individual factory functions are used in tests.
-- We stub import/import_as_fallback so the sub-files load cleanly without the engine.
import = function() end
import_as_fallback = function() end

dofile("src/main.lua")
dofile("src/ui_theme.lua")
dofile("src/discovery.lua")
dofile("src/hash.lua")

-- Test-level config: gates lib.warn in hash/discovery during tests
config = { ModEnabled = true, DebugMode = false }

-- =============================================================================
-- Mock Discovery: simulates discovered modules for hash testing
-- =============================================================================

MockDiscovery = {}

function MockDiscovery.create(moduleConfigs, optionConfigs, specialConfigs)
    -- moduleConfigs: ordered list of { id, category, enabled, default, options? }
    -- optionConfigs: { [id] = { [configKey] = value } }  (unused; options are on moduleConfigs)
    -- specialConfigs: { { modName, config, stateSchema } }

    moduleConfigs = moduleConfigs or {}
    optionConfigs = optionConfigs or {}
    specialConfigs = specialConfigs or {}

    local discovery = {
        modules = {},
        modulesById = {},
        modulesWithOptions = {},
        specials = {},
        categories = {},
        byCategory = {},
    }

    local categorySet = {}

    for _, mc in ipairs(moduleConfigs) do
        local persisted = { Enabled = mc.enabled }
        if mc.options then
            for _, opt in ipairs(mc.options) do
                if opt.configKey ~= nil and persisted[opt.configKey] == nil then
                    persisted[opt.configKey] = opt.default
                end
            end
        end
        local mod = {
            modName = "adamant-" .. mc.id,
            mod = {
                config = persisted,
                store = lib.createStore(persisted, {
                    options = mc.options,
                }),
            },
            definition = {
                apply = function() end,
                revert = function() end,
            },
            id = mc.id,
            name = mc.id,
            category = mc.category or "General",
            options = mc.options,
            default = mc.default ~= nil and mc.default or false,
        }

        table.insert(discovery.modules, mod)
        discovery.modulesById[mc.id] = mod

        if mc.options and #mc.options > 0 then
            table.insert(discovery.modulesWithOptions, mod)
        end

        local cat = mc.category or "General"
        if not categorySet[cat] then
            categorySet[cat] = true
            table.insert(discovery.categories, { key = cat, label = cat })
        end
        discovery.byCategory[cat] = discovery.byCategory[cat] or {}
        table.insert(discovery.byCategory[cat], mod)
    end

    for _, sc in ipairs(specialConfigs) do
        local store = lib.createStore(sc.config, {
            stateSchema = sc.stateSchema,
        })
        table.insert(discovery.specials, {
            modName = sc.modName,
            mod = {
                config = sc.config,
                store = store,
            },
            definition = {},
            stateSchema = sc.stateSchema,
            uiState = store.uiState,
        })
    end

    -- State accessors
    function discovery.isModuleEnabled(m)
        return m.mod.store.read("Enabled") == true
    end

    function discovery.setModuleEnabled(m, enabled)
        m.mod.store.write("Enabled", enabled)
    end

    function discovery.getOptionValue(m, configKey)
        return m.mod.store.read(configKey)
    end

    function discovery.setOptionValue(m, configKey, value)
        m.mod.store.write(configKey, value)
    end

    function discovery.isSpecialEnabled(special)
        return special.mod.store.read("Enabled") == true
    end

    function discovery.setSpecialEnabled(special, enabled)
        special.mod.store.write("Enabled", enabled)
    end

    return discovery
end
