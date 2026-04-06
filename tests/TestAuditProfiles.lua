local lu = require('luaunit')

TestAuditProfiles = {}

function TestAuditProfiles:setUp()
    CaptureWarnings()
end

function TestAuditProfiles:tearDown()
    RestoreWarnings()
end

function TestAuditProfiles:testKnownStorageKeysProduceNoWarnings()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            storage = {
                { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
            },
        },
    }, {
        {
            modName = "SpecialBiome",
            storage = {
                { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
            },
        },
    })

    Framework.auditSavedProfiles("test-pack", {
        { Name = "Known", Hash = "_v=1|GodPool=1|GodPool.EnabledFlag=1|SpecialBiome=1|SpecialBiome.Mode=Chaos", Tooltip = "" },
    }, discovery, lib)

    lu.assertEquals(#Warnings, 0)
end

function TestAuditProfiles:testUnknownKeyInKnownNamespaceWarns()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            storage = {
                { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
            },
        },
    })

    Framework.auditSavedProfiles("test-pack", {
        { Name = "Broken", Hash = "_v=1|GodPool.MissingField=1", Tooltip = "" },
    }, discovery, lib)

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "Profile 'Broken': unrecognized key 'GodPool.MissingField'")
end

function TestAuditProfiles:testUnknownNamespaceIsIgnored()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            storage = {
                { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
            },
        },
    })

    Framework.auditSavedProfiles("test-pack", {
        { Name = "Foreign", Hash = "_v=1|UnknownModule.Field=1", Tooltip = "" },
    }, discovery, lib)

    lu.assertEquals(#Warnings, 0)
end
