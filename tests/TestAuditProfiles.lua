local lu = require('luaunit')

-- =============================================================================
-- AuditSavedProfiles tests
-- =============================================================================
-- Tests Framework.auditSavedProfiles(packId, profiles, discovery, lib).
-- Each test constructs a discovery surface and a set of saved profile hashes,
-- then asserts whether warnings are (or are not) emitted.

TestAuditProfiles = {}

local function makeProfiles(hashes)
    local profiles = {}
    for i, hash in ipairs(hashes) do
        profiles[i] = { Name = "Slot " .. i, Hash = hash, Tooltip = "" }
    end
    return profiles
end

function TestAuditProfiles:setUp()
    CaptureWarnings()
end

function TestAuditProfiles:tearDown()
    RestoreWarnings()
end

-- =============================================================================
-- NO WARNINGS (clean surface)
-- =============================================================================

function TestAuditProfiles:testAllDefaultsProfileProducesNoWarnings()
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false },
    })
    Framework.auditSavedProfiles("test-pack", makeProfiles({ "_v=1" }), discovery, lib)
    lu.assertEquals(#Warnings, 0)
end

function TestAuditProfiles:testEmptyProfileHashProducesNoWarnings()
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false },
    })
    Framework.auditSavedProfiles("test-pack", makeProfiles({ "" }), discovery, lib)
    lu.assertEquals(#Warnings, 0)
end

function TestAuditProfiles:testKnownModuleEnabledStateKeyProducesNoWarning()
    -- "A=1" is the enabled-state key for module A — no field, always valid if A is known
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false },
    })
    Framework.auditSavedProfiles("test-pack", makeProfiles({ "_v=1|A=1" }), discovery, lib)
    lu.assertEquals(#Warnings, 0)
end

function TestAuditProfiles:testKnownSpecialEnabledStateKeyProducesNoWarning()
    -- "adamant-Special=1" is the enabled-state key — no field, always valid if special is known
    local discovery = MockDiscovery.create({}, {}, {
        {
            modName = "adamant-Special",
            config = { Weapon = "Axe" },
            stateSchema = {
                { type = "dropdown", configKey = "Weapon", values = { "Axe", "Staff" }, default = "Axe" },
            },
        },
    })
    Framework.auditSavedProfiles("test-pack", makeProfiles({ "_v=1|adamant-Special=1" }), discovery, lib)
    lu.assertEquals(#Warnings, 0)
end

function TestAuditProfiles:testKnownModuleOptionKeyProducesNoWarning()
    local discovery = MockDiscovery.create({
        {
            id = "A", category = "Cat1", enabled = false, default = false,
            options = {
                { type = "checkbox", configKey = "Strict", default = false },
            },
        },
    })
    Framework.auditSavedProfiles("test-pack", makeProfiles({ "_v=1|A=1|A.Strict=1" }), discovery, lib)
    lu.assertEquals(#Warnings, 0)
end

function TestAuditProfiles:testKnownSpecialSchemaKeyProducesNoWarning()
    local discovery = MockDiscovery.create({}, {}, {
        {
            modName = "adamant-Special",
            config = { Weapon = "Axe" },
            stateSchema = {
                { type = "dropdown", configKey = "Weapon", values = { "Axe", "Staff" }, default = "Axe" },
            },
        },
    })
    Framework.auditSavedProfiles("test-pack",
        makeProfiles({ "_v=1|adamant-Special=1|adamant-Special.Weapon=Staff" }), discovery, lib)
    lu.assertEquals(#Warnings, 0)
end

function TestAuditProfiles:testUnknownNamespaceProducesNoWarning()
    -- Namespace not in discovery = module not installed; skip silently
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false },
    })
    Framework.auditSavedProfiles("test-pack",
        makeProfiles({ "_v=1|UninstalledMod=1|UninstalledMod.SomeField=value" }), discovery, lib)
    lu.assertEquals(#Warnings, 0)
end

-- =============================================================================
-- WARNINGS (unrecognized keys in known namespaces)
-- =============================================================================

function TestAuditProfiles:testUnrecognizedOptionInKnownModuleWarns()
    local discovery = MockDiscovery.create({
        {
            id = "A", category = "Cat1", enabled = false, default = false,
            options = {
                { type = "checkbox", configKey = "Strict", default = false },
            },
        },
    })
    -- A.OldKey no longer exists in the option surface
    Framework.auditSavedProfiles("test-pack", makeProfiles({ "_v=1|A=1|A.OldKey=1" }), discovery, lib)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "A.OldKey")
end

function TestAuditProfiles:testUnrecognizedFieldInKnownSpecialWarns()
    local discovery = MockDiscovery.create({}, {}, {
        {
            modName = "adamant-Special",
            config = { Weapon = "Axe" },
            stateSchema = {
                { type = "dropdown", configKey = "Weapon", values = { "Axe", "Staff" }, default = "Axe" },
            },
        },
    })
    -- adamant-Special.OldField no longer exists in the schema
    Framework.auditSavedProfiles("test-pack",
        makeProfiles({ "_v=1|adamant-Special=1|adamant-Special.OldField=Axe" }), discovery, lib)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "adamant-Special.OldField")
end

function TestAuditProfiles:testMultipleUnrecognizedKeysInOneProfileWarnForEach()
    local discovery = MockDiscovery.create({
        {
            id = "A", category = "Cat1", enabled = false, default = false,
            options = {
                { type = "checkbox", configKey = "Strict", default = false },
            },
        },
    })
    Framework.auditSavedProfiles("test-pack",
        makeProfiles({ "_v=1|A.Gone1=1|A.Gone2=value" }), discovery, lib)
    lu.assertEquals(#Warnings, 2)
end

function TestAuditProfiles:testMultipleProfilesEachScannedIndependently()
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false },
    })
    -- Two profiles each with one unrecognized key
    Framework.auditSavedProfiles("test-pack",
        makeProfiles({ "_v=1|A.Gone=1", "_v=1|A.AlsoGone=1" }), discovery, lib)
    lu.assertEquals(#Warnings, 2)
end

function TestAuditProfiles:testWarningIncludesProfileName()
    local profiles = { { Name = "MyProfile", Hash = "_v=1|A.Gone=1", Tooltip = "" } }
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false },
    })
    Framework.auditSavedProfiles("test-pack", profiles, discovery, lib)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "MyProfile")
end

function TestAuditProfiles:testUnnamedProfileFallsBackToSlotNumber()
    local profiles = { { Name = "", Hash = "_v=1|A.Gone=1", Tooltip = "" } }
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false },
    })
    Framework.auditSavedProfiles("test-pack", profiles, discovery, lib)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "slot 1")
end
