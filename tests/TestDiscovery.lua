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

function TestDiscovery:testSpecialMissingSpecialStateIsSkipped()
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
            config = {
                Enabled = false,
                DebugMode = false,
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
            },
            store = lib.createStore({
                Enabled = false,
                DebugMode = false,
            }, {}),
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
