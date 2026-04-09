local lu = require('luaunit')

local function resetMods()
    rom.mods = {
        ['SGG_Modding-ENVY'] = {
            auto = function() return {} end,
        },
        ['SGG_Modding-Chalk'] = {
            auto = function() return { DebugMode = false } end,
        },
        ['adamant-ModpackLib'] = lib,
    }
end

local function attachRegularModule(modName, definition, persisted)
    local exports = {
        definition = definition,
    }
    exports.store = lib.createStore(persisted or {}, definition)
    rom.mods[modName] = exports
    return exports
end

local function attachSpecialModule(modName, definition, persisted)
    local exports = {
        definition = definition,
        DrawTab = function() end,
    }
    exports.store = lib.createStore(persisted or {}, definition)
    rom.mods[modName] = exports
    return exports
end

TestDiscovery = {}

function TestDiscovery:setUp()
    resetMods()
    CaptureWarnings()
end

function TestDiscovery:tearDown()
    RestoreWarnings()
end

function TestDiscovery:testRegularModulesDiscoverStorageUiAndQuickNodes()
    attachRegularModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        category = "Run Director",
        subgroup = "Run Setup",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        ui = {
            { type = "checkbox", binds = { value = "EnabledFlag" }, label = "Enabled", quick = true },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false })

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#discovery.modules, 1)
    lu.assertEquals(#discovery.modulesWithUi, 1)
    lu.assertEquals(#discovery.modulesWithQuickUi, 1)
    lu.assertEquals(#discovery.modulesWithQuickUi[1].quickUi, 1)
    lu.assertEquals(discovery.categories[1].key, "Run Director")
end

function TestDiscovery:testRegularModulesDiscoverQuickNodesFromCustomTypes()
    attachRegularModule("test-GodPoolCustom", {
        modpack = "test-pack",
        id = "GodPoolCustom",
        name = "God Pool Custom",
        category = "Run Director",
        subgroup = "Run Setup",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        customTypes = {
            widgets = {
                fancyToggle = {
                    binds = { value = { storageType = "bool" } },
                    validate = function() end,
                    draw = function() end,
                },
            },
            layouts = {
                fancyGroup = {
                    validate = function() end,
                    render = function() return true end,
                },
            },
        },
        ui = {
            {
                type = "fancyGroup",
                children = {
                    { type = "fancyToggle", binds = { value = "EnabledFlag" }, label = "Enabled", quick = true },
                },
            },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false })

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#discovery.modulesWithQuickUi, 1)
    lu.assertEquals(#discovery.modulesWithQuickUi[1].quickUi, 1)
    lu.assertEquals(discovery.modulesWithQuickUi[1].quickUi[1].type, "fancyToggle")
end

function TestDiscovery:testMissingStorageSkipsRegularModule()
    attachRegularModule("test-MissingStorage", {
        modpack = "test-pack",
        id = "MissingStorage",
        name = "Missing Storage",
        category = "Run Director",
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false })

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#discovery.modules, 0)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "missing definition.storage")
end

function TestDiscovery:testRegularModulesWarnWhenSpecialDrawExportsArePresent()
    local exports = attachRegularModule("test-RegularWithDrawTab", {
        modpack = "test-pack",
        id = "RegularWithDrawTab",
        name = "Regular With DrawTab",
        category = "Run Director",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        ui = {},
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false })
    exports.DrawTab = function() end

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "regular modules ignore DrawTab/DrawQuickContent")
end

function TestDiscovery:testSpecialModulesRequireStorageAndManagedUiState()
    attachSpecialModule("test-Biome", {
        modpack = "test-pack",
        special = true,
        name = "Biome Control",
        shortName = "Biome",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        ui = {
            { type = "checkbox", binds = { value = "EnabledFlag" }, label = "Enabled" },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false })

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#discovery.specials, 1)
    lu.assertNotNil(discovery.specials[1].uiState)
    lu.assertEquals(discovery.specials[1]._tabLabel, "Biome")
end

function TestDiscovery:testSpecialModulesWarnWhenNoTabQuickOrUiFallbackExists()
    rom.mods["test-BareSpecial"] = {
        definition = {
            modpack = "test-pack",
            special = true,
            name = "Bare Special",
            storage = {
                { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
            },
            ui = {},
            apply = function() end,
            revert = function() end,
        },
        store = lib.createStore({ Enabled = false, DebugMode = false, EnabledFlag = false }, {
            modpack = "test-pack",
            special = true,
            name = "Bare Special",
            storage = {
                { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
            },
            ui = {},
            apply = function() end,
            revert = function() end,
        }),
    }

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "exposes neither DrawTab nor DrawQuickContent and has no definition.ui fallback")
end

function TestDiscovery:testUnifiedTabOrderRespectsCategoryOrderAcrossCategoriesAndSpecials()
    attachRegularModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        category = "Run Director",
        subgroup = "Run Setup",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        ui = {},
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false })

    attachSpecialModule("test-Biome", {
        modpack = "test-pack",
        special = true,
        name = "Biome Control",
        shortName = "Biome",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        ui = {},
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false })

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run(nil, nil, { "Biome", "Run Director" })

    lu.assertEquals(#discovery.unifiedTabOrder, 2)
    lu.assertEquals(discovery.unifiedTabOrder[1].kind, "special")
    lu.assertEquals(discovery.unifiedTabOrder[1].entry._tabLabel, "Biome")
    lu.assertEquals(discovery.unifiedTabOrder[2].kind, "category")
    lu.assertEquals(discovery.unifiedTabOrder[2].entry.key, "Run Director")
end
