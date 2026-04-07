local lu = require('luaunit')

local function makeHash(discovery)
    return Framework.createHash(discovery, { DebugMode = false }, lib, "test-pack")
end

local function assertWarningContains(fragment)
    for _, warning in ipairs(Warnings) do
        if string.find(warning, fragment, 1, true) then
            return
        end
    end
    lu.fail("expected warning containing '" .. fragment .. "'")
end

TestHashBase62 = {}

function TestHashBase62:testRoundTrip()
    local hash = makeHash(MockDiscovery.create())
    local encoded = hash.EncodeBase62(3844)
    lu.assertEquals(hash.DecodeBase62(encoded), 3844)
end

TestHashStorage = {}

function TestHashStorage:testAllDefaultsProduceVersionOnlyCanonical()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            default = false,
            enabled = false,
            storage = {
                { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
                { type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 },
            },
            values = {
                EnabledFlag = false,
                Count = 3,
            },
        },
    })

    local canonical = makeHash(discovery).GetConfigHash()

    lu.assertEquals(canonical, "_v=1")
end

function TestHashStorage:testRegularAndSpecialStorageRoundTrip()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            default = false,
            enabled = true,
            storage = {
                { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
                { type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 },
            },
            values = {
                EnabledFlag = true,
                Count = 7,
            },
        },
    }, {
        {
            modName = "BiomeControl",
            enabled = true,
            storage = {
                { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
            },
            values = {
                Mode = "Chaos",
            },
        },
    })
    local hash = makeHash(discovery)
    local canonical = hash.GetConfigHash()

    lu.assertStrContains(canonical, "GodPool=1")
    lu.assertStrContains(canonical, "GodPool.EnabledFlag=1")
    lu.assertStrContains(canonical, "GodPool.Count=7")
    lu.assertStrContains(canonical, "BiomeControl=1")
    lu.assertStrContains(canonical, "BiomeControl.Mode=Chaos")

    local module = discovery.modulesById.GodPool
    local special = discovery.specials[1]
    module.mod.store.write("Enabled", false)
    module.mod.store.write("EnabledFlag", false)
    module.mod.store.write("Count", 3)
    special.mod.store.write("Enabled", false)
    special.mod.store.write("Mode", "Vanilla")

    lu.assertTrue(hash.ApplyConfigHash(canonical))
    lu.assertTrue(module.mod.store.read("Enabled"))
    lu.assertTrue(module.mod.store.read("EnabledFlag"))
    lu.assertEquals(module.mod.store.read("Count"), 7)
    lu.assertTrue(special.mod.store.read("Enabled"))
    lu.assertEquals(special.mod.store.read("Mode"), "Chaos")
end

function TestHashStorage:testFingerprintChangesWithConfig()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            default = false,
            enabled = false,
            storage = {
                { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
            },
            values = { EnabledFlag = false },
        },
    })
    local hash = makeHash(discovery)
    local canonicalA, fingerprintA = hash.GetConfigHash()

    discovery.modulesById.GodPool.mod.store.write("EnabledFlag", true)
    local canonicalB, fingerprintB = hash.GetConfigHash()

    lu.assertNotEquals(canonicalA, canonicalB)
    lu.assertNotEquals(fingerprintA, fingerprintB)
end

function TestHashStorage:testApplyConfigHashRollsBackWhenEnableFails()
    local applyCalls = 0
    local revertCalls = 0
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            default = false,
            enabled = false,
            storage = {
                { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
            },
            values = { EnabledFlag = false },
            apply = function()
                applyCalls = applyCalls + 1
                error("apply boom")
            end,
            revert = function()
                revertCalls = revertCalls + 1
            end,
        },
    })
    local hash = makeHash(discovery)
    local module = discovery.modulesById.GodPool

    local ok = hash.ApplyConfigHash("_v=1|GodPool=1|GodPool.EnabledFlag=1")

    lu.assertFalse(ok)
    lu.assertFalse(module.mod.store.read("Enabled"))
    lu.assertFalse(module.mod.store.read("EnabledFlag"))
    lu.assertEquals(applyCalls, 1)
    lu.assertEquals(revertCalls, 0)
end

function TestHashStorage:testHashGroupsRejectPackedChildAliases()
    CaptureWarnings()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            default = false,
            enabled = false,
            hashGroups = {
                { key = "PackedBits", "EnabledBit" },
            },
            storage = {
                {
                    type = "packedInt",
                    alias = "PackedRoot",
                    configKey = "PackedRoot",
                    bits = {
                        { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = false },
                    },
                },
            },
            values = {
                PackedRoot = 0,
            },
        },
    })

    local canonical = makeHash(discovery).GetConfigHash()

    lu.assertEquals(canonical, "_v=1")
    assertWarningContains("is a packed child alias; only root storage aliases are supported")
    RestoreWarnings()
end

function TestHashStorage:testHashGroupsAllowPackedRootAliases()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            default = false,
            enabled = false,
            hashGroups = {
                { key = "PackedRoots", "PackedA", "PackedB" },
            },
            storage = {
                { type = "packedInt", alias = "PackedA", configKey = "PackedA", width = 12, bits = {
                    { alias = "AFlag", offset = 0, width = 1, type = "bool", default = false },
                }},
                { type = "packedInt", alias = "PackedB", configKey = "PackedB", width = 12, bits = {
                    { alias = "BFlag", offset = 0, width = 1, type = "bool", default = false },
                }},
            },
            values = {
                PackedA = 3,
                PackedB = 5,
            },
        },
    })

    local canonical = makeHash(discovery).GetConfigHash()

    lu.assertStrContains(canonical, "GodPool.PackedRoots=")
end
