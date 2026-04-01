local lu = require('luaunit')

TestDiscovery = {}

local function withMockModules(entries, fn)
    local previous = {}
    for modName, mod in pairs(entries) do
        previous[modName] = rom.mods[modName]
        rom.mods[modName] = mod
    end

    local ok, err = pcall(fn)

    for modName, _ in pairs(entries) do
        rom.mods[modName] = previous[modName]
    end

    if not ok then
        error(err, 0)
    end
end

local function makeModule(id, category)
    local persisted = {
        Enabled = false,
        DebugMode = false,
    }
    return {
        definition = {
            modpack = "test-pack",
            id = id,
            name = id,
            category = category,
            apply = function() end,
            revert = function() end,
        },
        store = lib.createStore(persisted),
    }
end

function TestDiscovery:testCategoriesAlphabeticalByDefault()
    withMockModules({
        ["test-A"] = makeModule("A", "Zeta"),
        ["test-B"] = makeModule("B", "Alpha"),
        ["test-C"] = makeModule("C", "Beta"),
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()

        lu.assertEquals(#discovery.categories, 3)
        lu.assertEquals(discovery.categories[1].key, "Alpha")
        lu.assertEquals(discovery.categories[2].key, "Beta")
        lu.assertEquals(discovery.categories[3].key, "Zeta")
    end)
end

function TestDiscovery:testCategoryOrderCanOverrideDefaultSort()
    withMockModules({
        ["test-A"] = makeModule("A", "Zeta"),
        ["test-B"] = makeModule("B", "Alpha"),
        ["test-C"] = makeModule("C", "Beta"),
        ["test-D"] = makeModule("D", "Gamma"),
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run(nil, nil, { "Gamma", "Alpha" })

        lu.assertEquals(#discovery.categories, 4)
        lu.assertEquals(discovery.categories[1].key, "Gamma")
        lu.assertEquals(discovery.categories[2].key, "Alpha")
        lu.assertEquals(discovery.categories[3].key, "Beta")
        lu.assertEquals(discovery.categories[4].key, "Zeta")
    end)
end

function TestDiscovery:testDuplicateRegularIdsWarnAndSkipAllColliders()
    CaptureWarnings()

    withMockModules({
        ["test-A"] = makeModule("Shared", "Alpha"),
        ["test-B"] = makeModule("Shared", "Beta"),
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()

        lu.assertEquals(#discovery.modules, 0)
        lu.assertEquals(#discovery.modulesWithOptions, 0)
        lu.assertEquals(discovery.modulesById["Shared"], nil)
    end)

    local warnings = Warnings
    RestoreWarnings()

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "duplicate hash namespace 'Shared'")
    lu.assertStrContains(warnings[1], "skipping all conflicting entries")
end

function TestDiscovery:testRegularIdCollidingWithSpecialModNameWarnsAndSkipsBoth()
    CaptureWarnings()

    withMockModules({
        ["test-regular"] = {
            definition = {
                modpack = "test-pack",
                id = "test-special",
                name = "Regular",
                category = "Alpha",
                apply = function() end,
                revert = function() end,
            },
            store = lib.createStore({
                Enabled = false,
                DebugMode = false,
            }),
        },
        ["test-special"] = {
            definition = {
                modpack = "test-pack",
                special = true,
                name = "Special",
                apply = function() end,
                revert = function() end,
                stateSchema = {
                    { type = "checkbox", configKey = "Flag", default = false },
                },
            },
            store = lib.createStore({
                Enabled = false,
                DebugMode = false,
                Flag = false,
            }, {
                stateSchema = {
                    { type = "checkbox", configKey = "Flag", default = false },
                },
            }),
            DrawTab = function() end,
        },
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()

        lu.assertEquals(#discovery.modules, 0)
        lu.assertEquals(#discovery.specials, 0)
        lu.assertEquals(discovery.modulesById["test-special"], nil)
    end)

    local warnings = Warnings
    RestoreWarnings()

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "duplicate hash namespace 'test-special'")
    lu.assertStrContains(warnings[1], "skipping all conflicting entries")
end

function TestDiscovery:testReservedHashNamespaceWarnsAndSkipsEntry()
    CaptureWarnings()

    withMockModules({
        ["test-A"] = makeModule("_v", "Alpha"),
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()

        lu.assertEquals(#discovery.modules, 0)
        lu.assertEquals(discovery.modulesById["_v"], nil)
    end)

    local warnings = Warnings
    RestoreWarnings()

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "reserved hash namespace '_v'")
    lu.assertStrContains(warnings[1], "skipping all conflicting entries")
end

function TestDiscovery:testUnknownCategoryOrderEntryWarnsInDebugMode()
    local previousDebugMode = config.DebugMode
    config.DebugMode = true
    CaptureWarnings()

    withMockModules({
        ["test-A"] = makeModule("A", "Alpha"),
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run(nil, nil, { "MissingCategory", "Alpha" })

        lu.assertEquals(#discovery.categories, 1)
        lu.assertEquals(discovery.categories[1].key, "Alpha")
    end)

    local warnings = Warnings
    RestoreWarnings()
    config.DebugMode = previousDebugMode

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "categoryOrder contains unknown category 'MissingCategory'")
end

function TestDiscovery:testSpecialMissingUiStateIsSkipped()
    local previousDebugMode = config.DebugMode
    config.DebugMode = true
    CaptureWarnings()

    withMockModules({
        ["test-special"] = {
            definition = {
                modpack = "test-pack",
                special = true,
                name = "My Special",
                apply = function() end,
                revert = function() end,
                stateSchema = {
                    { type = "checkbox", configKey = "Flag", default = false },
                },
            },
            config = {
                Enabled = false,
                DebugMode = false,
                Flag = false,
            },
        },
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()
        lu.assertEquals(#discovery.specials, 0)
    end)

    local warnings = Warnings
    RestoreWarnings()
    config.DebugMode = previousDebugMode

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "missing public.store")
end

function TestDiscovery:testSpecialMissingStateSchemaIsSkipped()
    local previousDebugMode = config.DebugMode
    config.DebugMode = true
    CaptureWarnings()

    withMockModules({
        ["test-special"] = {
            definition = {
                modpack = "test-pack",
                special = true,
                name = "My Special",
                apply = function() end,
                revert = function() end,
            },
            store = lib.createStore({
                Enabled = false,
                DebugMode = false,
            }),
            DrawTab = function() end,
        },
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()
        lu.assertEquals(#discovery.specials, 0)
    end)

    local warnings = Warnings
    RestoreWarnings()
    config.DebugMode = previousDebugMode

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "missing definition.stateSchema")
end

function TestDiscovery:testSpecialMissingDrawEntrypointsWarnsButStillDiscovers()
    local previousDebugMode = config.DebugMode
    config.DebugMode = true
    CaptureWarnings()

    withMockModules({
        ["test-special"] = {
            definition = {
                modpack = "test-pack",
                special = true,
                name = "My Special",
                apply = function() end,
                revert = function() end,
                stateSchema = {
                    { type = "checkbox", configKey = "Flag", default = false },
                },
            },
            store = lib.createStore({
                Enabled = false,
                DebugMode = false,
                Flag = false,
            }, {
                stateSchema = {
                    { type = "checkbox", configKey = "Flag", default = false },
                },
            }),
        },
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()
        lu.assertEquals(#discovery.specials, 1)
    end)

    local warnings = Warnings
    RestoreWarnings()
    config.DebugMode = previousDebugMode

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "exposes neither DrawTab nor DrawQuickContent")
end

function TestDiscovery:testPatchOnlyModuleIsDiscovered()
    withMockModules({
        ["test-patch"] = {
            definition = {
                modpack = "test-pack",
                id = "PatchOnly",
                name = "PatchOnly",
                category = "General",
                dataMutation = true,
                patchPlan = function() end,
            },
            store = lib.createStore({
                Enabled = false,
                DebugMode = false,
            }),
        },
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()
        lu.assertEquals(#discovery.modules, 1)
        lu.assertEquals(discovery.modules[1].id, "PatchOnly")
    end)
end

function TestDiscovery:testMutationModeMismatchWarns()
    local previousDebugMode = config.DebugMode
    config.DebugMode = true
    CaptureWarnings()

    withMockModules({
        ["test-mismatch"] = {
            definition = {
                modpack = "test-pack",
                id = "Mismatch",
                name = "Mismatch",
                category = "General",
                dataMutation = true,
                mutationMode = lib.MutationMode.Manual,
                patchPlan = function() end,
            },
            store = lib.createStore({
                Enabled = false,
                DebugMode = false,
            }),
        },
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()
        lu.assertEquals(#discovery.modules, 1)
    end)

    local warnings = Warnings
    RestoreWarnings()
    config.DebugMode = previousDebugMode

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "does not match inferred mutation shape")
end

function TestDiscovery:testDataMutationWithoutPatchOrManualWarnsAndSkips()
    local previousDebugMode = config.DebugMode
    config.DebugMode = true
    CaptureWarnings()

    withMockModules({
        ["test-invalid"] = {
            definition = {
                modpack = "test-pack",
                id = "Invalid",
                name = "Invalid",
                category = "General",
                dataMutation = true,
            },
            store = lib.createStore({
                Enabled = false,
                DebugMode = false,
            }),
        },
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()
        lu.assertEquals(#discovery.modules, 0)
    end)

    local warnings = Warnings
    RestoreWarnings()
    config.DebugMode = previousDebugMode

    lu.assertEquals(#warnings, 2)
    lu.assertStrContains(warnings[1], "dataMutation=true but module exposes neither patchPlan nor apply/revert")
    lu.assertStrContains(warnings[2], "missing id, apply/revert, or patchPlan")
end

function TestDiscovery:testRegularOptionsMissingUiStateWarnsAndSkipsOptionRendering()
    local previousDebugMode = config.DebugMode
    config.DebugMode = true
    CaptureWarnings()

    withMockModules({
        ["test-options"] = {
            definition = {
                modpack = "test-pack",
                id = "OptionsOnly",
                name = "OptionsOnly",
                category = "General",
                apply = function() end,
                revert = function() end,
                options = {
                    { type = "checkbox", configKey = "Flag", default = false },
                },
            },
            store = lib.createStore({
                Enabled = false,
                DebugMode = false,
                Flag = false,
            }),
        },
    }, function()
        local discovery = Framework.createDiscovery("test-pack", config, lib)
        discovery.run()
        lu.assertEquals(#discovery.modules, 1)
        lu.assertEquals(#discovery.modulesWithOptions, 0)
    end)

    local warnings = Warnings
    RestoreWarnings()
    config.DebugMode = previousDebugMode

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "missing public.store.uiState")
end
