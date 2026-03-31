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
    return {
        definition = {
            modpack = "test-pack",
            id = id,
            name = id,
            category = category,
            apply = function() end,
            revert = function() end,
        },
        config = {
            Enabled = false,
            DebugMode = false,
        },
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
