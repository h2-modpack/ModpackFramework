local lu = require('luaunit')

-- =============================================================================
-- Hash tests using Framework.createHash factory
-- =============================================================================
-- TestUtils.lua has already loaded Framework and set up lib and rom mocks.
-- Each test creates a mock discovery and passes it directly to createHash —
-- no global patching needed.

local function withDiscovery(discovery)
    local Hash = Framework.createHash(discovery, config, lib, "test-pack")
    return Hash.GetConfigHash, Hash.ApplyConfigHash, Hash
end

-- =============================================================================
-- BASE62 TESTS (EncodeBase62/DecodeBase62 still used for fingerprint)
-- =============================================================================

TestBase62 = {}

function TestBase62:testEncodeZero()
    local Hash = Framework.createHash(MockDiscovery.create({}), config, lib, "test-pack")
    lu.assertEquals(Hash.EncodeBase62(0), "0")
end

function TestBase62:testEncodeSingleDigit()
    local Hash = Framework.createHash(MockDiscovery.create({}), config, lib, "test-pack")
    lu.assertEquals(Hash.EncodeBase62(9), "9")
    lu.assertEquals(Hash.EncodeBase62(10), "A")
    lu.assertEquals(Hash.EncodeBase62(61), "z")
end

function TestBase62:testEncodeMultiDigit()
    local Hash = Framework.createHash(MockDiscovery.create({}), config, lib, "test-pack")
    lu.assertEquals(Hash.EncodeBase62(62), "10")
    lu.assertEquals(Hash.EncodeBase62(124), "20")
end

function TestBase62:testRoundTrip()
    local Hash = Framework.createHash(MockDiscovery.create({}), config, lib, "test-pack")
    for _, n in ipairs({0, 1, 42, 61, 62, 100, 999, 123456, 1073741823}) do
        lu.assertEquals(Hash.DecodeBase62(Hash.EncodeBase62(n)), n)
    end
end

function TestBase62:testDecodeInvalidChar()
    local Hash = Framework.createHash(MockDiscovery.create({}), config, lib, "test-pack")
    lu.assertIsNil(Hash.DecodeBase62("!invalid"))
end

-- =============================================================================
-- KEY-VALUE ROUND-TRIPS
-- =============================================================================

TestHashKeyValue = {}

function TestHashKeyValue:testBoolOnlyAllEnabled()
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true,  default = false },
        { id = "B", category = "Cat1", enabled = true,  default = false },
        { id = "C", category = "Cat1", enabled = true,  default = false },
    })
    local GetHash, ApplyHash = withDiscovery(discovery)
    local hash = GetHash()

    for _, m in ipairs(discovery.modules) do m.mod.config.Enabled = false end
    ApplyHash(hash)

    for _, m in ipairs(discovery.modules) do
        lu.assertTrue(m.mod.config.Enabled)
    end
end

function TestHashKeyValue:testBoolOnlyMixedStates()
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true,  default = false },
        { id = "B", category = "Cat1", enabled = false, default = false },
        { id = "C", category = "Cat2", enabled = true,  default = false },
        { id = "D", category = "Cat2", enabled = false, default = false },
    })
    local GetHash, ApplyHash = withDiscovery(discovery)
    local hash = GetHash()

    for _, m in ipairs(discovery.modules) do
        m.mod.config.Enabled = not m.mod.config.Enabled
    end
    ApplyHash(hash)

    lu.assertTrue(discovery.modulesById["A"].mod.config.Enabled)
    lu.assertFalse(discovery.modulesById["B"].mod.config.Enabled)
    lu.assertTrue(discovery.modulesById["C"].mod.config.Enabled)
    lu.assertFalse(discovery.modulesById["D"].mod.config.Enabled)
end

function TestHashKeyValue:testDropdownOptionRoundTrip()
    local opts = {
        { type = "dropdown", configKey = "Mode", values = {"Vanilla", "Always", "Never"}, default = "Vanilla" },
    }
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true, default = false, options = opts },
    })
    discovery.modules[1].mod.config.Mode = "Always"

    local GetHash, ApplyHash = withDiscovery(discovery)
    local hash = GetHash()

    discovery.modules[1].mod.config.Enabled = false
    discovery.modules[1].mod.config.Mode = "Vanilla"
    ApplyHash(hash)

    lu.assertTrue(discovery.modules[1].mod.config.Enabled)
    lu.assertEquals(discovery.modules[1].mod.config.Mode, "Always")
end

function TestHashKeyValue:testCheckboxOptionRoundTrip()
    local opts = {
        { type = "checkbox", configKey = "Strict", default = false },
    }
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true, default = false, options = opts },
    })
    discovery.modules[1].mod.config.Strict = true

    local GetHash, ApplyHash = withDiscovery(discovery)
    local hash = GetHash()

    discovery.modules[1].mod.config.Strict = false
    ApplyHash(hash)

    lu.assertTrue(discovery.modules[1].mod.config.Strict)
end

function TestHashKeyValue:testSpecialSchemaRoundTrip()
    local discovery = MockDiscovery.create(
        { { id = "A", category = "Cat1", enabled = true, default = false } },
        {},
        {
            {
                modName = "adamant-Special",
                config = { Weapon = "Axe", Aspect = "Default" },
                stateSchema = {
                    { type = "dropdown", configKey = "Weapon", values = {"Axe", "Staff", "Daggers"}, default = "Axe" },
                    { type = "dropdown", configKey = "Aspect", values = {"Default", "Alpha", "Beta"}, default = "Default" },
                },
            },
        }
    )
    -- Set non-default values
    discovery.specials[1].mod.config.Weapon = "Staff"
    discovery.specials[1].mod.config.Aspect = "Beta"

    local GetHash, ApplyHash = withDiscovery(discovery)
    local hash = GetHash()

    discovery.specials[1].mod.config.Weapon = "Axe"
    discovery.specials[1].mod.config.Aspect = "Default"
    ApplyHash(hash)

    lu.assertEquals(discovery.specials[1].mod.config.Weapon, "Staff")
    lu.assertEquals(discovery.specials[1].mod.config.Aspect, "Beta")
end

-- =============================================================================
-- OMIT DEFAULTS
-- =============================================================================

TestHashOmitDefaults = {}

function TestHashOmitDefaults:testAllDefaultsProduceVersionOnlyCanonical()
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false },
        { id = "B", category = "Cat1", enabled = true,  default = true  },
    })
    local GetHash = withDiscovery(discovery)
    local canonical = GetHash()

    lu.assertEquals(canonical, "_v=1")
end

function TestHashOmitDefaults:testNonDefaultAppearsInCanonical()
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true, default = false },
    })
    local GetHash = withDiscovery(discovery)
    local canonical = GetHash()

    lu.assertStrContains(canonical, "A=1")
end

function TestHashOmitDefaults:testOptionAtDefaultOmitted()
    local opts = {
        { type = "dropdown", configKey = "Mode", values = {"Vanilla", "Always"}, default = "Vanilla" },
    }
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false, options = opts },
    })
    discovery.modules[1].mod.config.Mode = "Vanilla"  -- at default

    local GetHash = withDiscovery(discovery)
    local canonical = GetHash()

    lu.assertEquals(canonical, "_v=1")
end

function TestHashOmitDefaults:testTableValuedOptionAtDefaultOmitted()
    local previousFieldType = lib.FieldTypes.tableblob
    lib.FieldTypes.tableblob = {
        validate = function() end,
        toHash = function(_, value)
            return tostring(value and value.value or "")
        end,
        fromHash = function(_, str)
            return { value = str }
        end,
        toStaging = function(value)
            return rom.game.DeepCopyTable(value or {})
        end,
        draw = function(_, _, value)
            return value, false
        end,
    }

    local opts = {
        { type = "tableblob", configKey = "Blob", default = { value = "A" } },
    }
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false, options = opts },
    })
    discovery.modules[1].mod.config.Blob = { value = "A" }

    local GetHash = withDiscovery(discovery)
    local canonical = GetHash()

    lib.FieldTypes.tableblob = previousFieldType
    lu.assertEquals(canonical, "_v=1")
end

function TestHashOmitDefaults:testTableValuedSpecialFieldAtDefaultOmitted()
    local previousFieldType = lib.FieldTypes.tableblob
    lib.FieldTypes.tableblob = {
        validate = function() end,
        toHash = function(_, value)
            return tostring(value and value.value or "")
        end,
        fromHash = function(_, str)
            return { value = str }
        end,
        toStaging = function(value)
            return rom.game.DeepCopyTable(value or {})
        end,
        draw = function(_, _, value)
            return value, false
        end,
    }

    local discovery = MockDiscovery.create(
        {},
        {},
        {
            {
                modName = "adamant-Special",
                config = { Blob = { value = "A" } },
                stateSchema = {
                    { type = "tableblob", configKey = "Blob", default = { value = "A" } },
                },
            },
        }
    )

    local GetHash = withDiscovery(discovery)
    local canonical = GetHash()

    lib.FieldTypes.tableblob = previousFieldType
    lu.assertEquals(canonical, "_v=1")
end

function TestHashOmitDefaults:testOptionNonDefaultIncluded()
    local opts = {
        { type = "dropdown", configKey = "Mode", values = {"Vanilla", "Always"}, default = "Vanilla" },
    }
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false, options = opts },
    })
    discovery.modules[1].mod.config.Mode = "Always"  -- non-default

    local GetHash = withDiscovery(discovery)
    local canonical = GetHash()

    lu.assertStrContains(canonical, "A.Mode=Always")
end

-- =============================================================================
-- ROBUSTNESS
-- =============================================================================

TestHashRobustness = {}

function TestHashRobustness:testHashFromFewerModulesAppliesCleanly()
    -- Hash produced with 2 modules, applied to setup with 3 modules
    -- New module should reset to its default
    local discovery2 = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true,  default = false },
        { id = "B", category = "Cat1", enabled = false, default = false },
    })
    local GetHash = withDiscovery(discovery2)
    local hash = GetHash()

    -- Now apply to a 3-module discovery
    local discovery3 = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false },
        { id = "B", category = "Cat1", enabled = true,  default = false },
        { id = "C", category = "Cat1", enabled = true,  default = false },  -- new module
    })
    local _, ApplyHash = withDiscovery(discovery3)
    ApplyHash(hash)

    lu.assertTrue(discovery3.modulesById["A"].mod.config.Enabled)   -- restored from hash
    lu.assertFalse(discovery3.modulesById["B"].mod.config.Enabled)  -- restored from hash
    lu.assertFalse(discovery3.modulesById["C"].mod.config.Enabled)  -- reset to default (false)
end

function TestHashRobustness:testHashWithDefaultTrueModule()
    -- Module with default=true: absent from hash means enabled
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true, default = true },
    })
    local GetHash, ApplyHash = withDiscovery(discovery)
    local hash = GetHash()

    -- Hash should be version-only (value matches default, no payload)
    lu.assertEquals(hash, "_v=1")

    -- Disable the module, then apply empty hash — should restore to default (true)
    discovery.modules[1].mod.config.Enabled = false
    ApplyHash(hash)
    lu.assertTrue(discovery.modules[1].mod.config.Enabled)
end

-- =============================================================================
-- APPLY ORDER
-- =============================================================================

TestHashApplyOrder = {}

function TestHashApplyOrder:testRegularModuleApplySeesDecodedOptions()
    local appliedMode = nil
    local modConfig = {
        Enabled = false,
        Mode = "Vanilla",
    }

    local module = {
        modName = "adamant-A",
        mod = {
            config = modConfig,
            store = lib.createStore(modConfig, {
                options = {
                    {
                        type = "dropdown",
                        configKey = "Mode",
                        values = { "Vanilla", "Always" },
                        default = "Vanilla",
                    },
                },
            }),
        },
        definition = {
            apply = function()
                appliedMode = modConfig.Mode
            end,
            revert = function() end,
        },
        id = "A",
        name = "A",
        category = "Cat1",
        default = false,
        options = {
            {
                type = "dropdown",
                configKey = "Mode",
                values = { "Vanilla", "Always" },
                default = "Vanilla",
                _hashKey = "A.Mode",
            },
        },
    }

    local discovery = {
        modules = { module },
        modulesById = { A = module },
        modulesWithOptions = { module },
        specials = {},
    }

    function discovery.isModuleEnabled(m)
        return m.mod.store.read("Enabled") == true
    end

    function discovery.setModuleEnabled(m, enabled)
        m.mod.store.write("Enabled", enabled)
        local fn = enabled and m.definition.apply or m.definition.revert
        fn()
    end

    function discovery.getOptionValue(m, configKey)
        return m.mod.store.read(configKey)
    end

    function discovery.setOptionValue(m, configKey, value)
        m.mod.store.write(configKey, value)
    end

    module.mod.store.uiState.set("Mode", "Vanilla")
    local _, ApplyHash = withDiscovery(discovery)
    lu.assertTrue(ApplyHash("_v=1|A=1|A.Mode=Always"))
    lu.assertTrue(modConfig.Enabled)
    lu.assertEquals(modConfig.Mode, "Always")
    lu.assertEquals(appliedMode, "Always")
    lu.assertEquals(module.mod.store.uiState.view.Mode, "Always")
end

function TestHashApplyOrder:testApplyHashReappliesAlreadyEnabledModuleWhenOptionsChange()
    local appliedModes = {}
    local modConfig = {
        Enabled = true,
        Mode = "Vanilla",
    }

    local module = {
        modName = "adamant-A",
        mod = {
            config = modConfig,
            store = lib.createStore(modConfig, {
                options = {
                    {
                        type = "dropdown",
                        configKey = "Mode",
                        values = { "Vanilla", "Always" },
                        default = "Vanilla",
                    },
                },
            }),
        },
        definition = {
            apply = function()
                table.insert(appliedModes, modConfig.Mode)
            end,
            revert = function() end,
        },
        id = "A",
        name = "A",
        category = "Cat1",
        default = false,
        options = {
            {
                type = "dropdown",
                configKey = "Mode",
                values = { "Vanilla", "Always" },
                default = "Vanilla",
                _hashKey = "A.Mode",
            },
        },
    }

    local discovery = {
        modules = { module },
        modulesById = { A = module },
        modulesWithOptions = { module },
        specials = {},
    }

    function discovery.isModuleEnabled(m)
        return m.mod.store.read("Enabled") == true
    end

    function discovery.setModuleEnabled(m, enabled)
        return lib.setDefinitionEnabled(m.definition, m.mod.store, enabled)
    end

    function discovery.getOptionValue(m, configKey)
        return m.mod.store.read(configKey)
    end

    function discovery.setOptionValue(m, configKey, value)
        m.mod.store.write(configKey, value)
    end

    local _, ApplyHash = withDiscovery(discovery)
    lu.assertTrue(ApplyHash("_v=1|A=1|A.Mode=Always"))
    lu.assertTrue(modConfig.Enabled)
    lu.assertEquals(modConfig.Mode, "Always")
    lu.assertEquals(appliedModes, { "Always" })
end

function TestHashApplyOrder:testSpecialModuleApplySeesDecodedSchemaValues()
    local appliedWeapon = nil
    local reloadedWeapon = nil
    local specialConfig = {
        Enabled = false,
        Weapon = "Axe",
    }

    local special = {
        modName = "adamant-Special",
        mod = {},
        definition = {
            apply = function()
                appliedWeapon = specialConfig.Weapon
            end,
            revert = function() end,
        },
        stateSchema = {
            {
                type = "dropdown",
                configKey = "Weapon",
                values = { "Axe", "Staff" },
                default = "Axe",
            },
        },
    }
    special.mod.config = specialConfig
    special.mod.store = lib.createStore(specialConfig, {
        stateSchema = special.stateSchema,
    })
    special.mod.store.uiState.reloadFromConfig = function()
        reloadedWeapon = specialConfig.Weapon
    end

    local discovery = {
        modules = {},
        modulesById = {},
        modulesWithOptions = {},
        specials = { special },
    }

    function discovery.isSpecialEnabled(entry)
        return entry.mod.store.read("Enabled") == true
    end

    function discovery.setSpecialEnabled(entry, enabled)
        entry.mod.store.write("Enabled", enabled)
        local fn = enabled and entry.definition.apply or entry.definition.revert
        fn()
    end

    local _, ApplyHash = withDiscovery(discovery)
    lu.assertTrue(ApplyHash("_v=1|adamant-Special=1|adamant-Special.Weapon=Staff"))
    lu.assertTrue(specialConfig.Enabled)
    lu.assertEquals(specialConfig.Weapon, "Staff")
    lu.assertEquals(reloadedWeapon, "Staff")
    lu.assertEquals(appliedWeapon, "Staff")
end

function TestHashApplyOrder:testApplyHashReturnsFalseWhenEnableFails()
    CaptureWarnings()

    local module = {
        modName = "adamant-Broken",
        mod = {
            config = { Enabled = false },
            store = lib.createStore({ Enabled = false }),
        },
        definition = {
            apply = function() end,
            revert = function() end,
        },
        id = "Broken",
        name = "Broken",
        category = "General",
        default = false,
    }

    local discovery = {
        modules = { module },
        modulesById = { Broken = module },
        modulesWithOptions = {},
        specials = {},
    }

    function discovery.isModuleEnabled(m)
        return m.mod.store.read("Enabled") == true
    end

    function discovery.setModuleEnabled()
        return false, "enable boom"
    end

    local _, ApplyHash = withDiscovery(discovery)
    lu.assertFalse(ApplyHash("_v=1|Broken=1"))
    lu.assertFalse(module.mod.store.read("Enabled"))
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "[test-pack] ApplyConfigHash failed; restoring previous state: enable boom")

    RestoreWarnings()
end

function TestHashApplyOrder:testApplyHashRestoresPreviousConfigWhenLaterEnableFails()
    CaptureWarnings()

    local appliedModes = {}
    local alphaConfig = {
        Enabled = true,
        Mode = "Vanilla",
    }
    local brokenConfig = {
        Enabled = false,
    }

    local alpha = {
        modName = "adamant-Alpha",
        mod = {
            config = alphaConfig,
            store = lib.createStore(alphaConfig, {
                options = {
                    {
                        type = "dropdown",
                        configKey = "Mode",
                        values = { "Vanilla", "Always" },
                        default = "Vanilla",
                    },
                },
            }),
        },
        definition = {
            apply = function()
                table.insert(appliedModes, alphaConfig.Mode)
            end,
            revert = function() end,
        },
        id = "Alpha",
        name = "Alpha",
        category = "Cat1",
        default = false,
        options = {
            {
                type = "dropdown",
                configKey = "Mode",
                values = { "Vanilla", "Always" },
                default = "Vanilla",
                _hashKey = "Alpha.Mode",
            },
        },
    }

    local broken = {
        modName = "adamant-Broken",
        mod = {
            config = brokenConfig,
            store = lib.createStore(brokenConfig),
        },
        definition = {
            apply = function()
                error("enable boom")
            end,
            revert = function() end,
        },
        id = "Broken",
        name = "Broken",
        category = "Cat1",
        default = false,
    }

    local discovery = {
        modules = { alpha, broken },
        modulesById = { Alpha = alpha, Broken = broken },
        modulesWithOptions = { alpha },
        specials = {},
    }

    function discovery.isModuleEnabled(m)
        return m.mod.store.read("Enabled") == true
    end

    function discovery.setModuleEnabled(m, enabled)
        return lib.setDefinitionEnabled(m.definition, m.mod.store, enabled)
    end

    function discovery.getOptionValue(m, configKey)
        return m.mod.store.read(configKey)
    end

    function discovery.setOptionValue(m, configKey, value)
        m.mod.store.write(configKey, value)
    end

    local _, ApplyHash = withDiscovery(discovery)
    lu.assertFalse(ApplyHash("_v=1|Alpha=1|Alpha.Mode=Always|Broken=1"))
    lu.assertTrue(alpha.mod.store.read("Enabled"))
    lu.assertEquals(alphaConfig.Mode, "Vanilla")
    lu.assertFalse(broken.mod.store.read("Enabled"))
    lu.assertEquals(appliedModes, { "Always", "Vanilla" })
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "[test-pack] ApplyConfigHash failed; restoring previous state: ")

    RestoreWarnings()
end

-- =============================================================================
-- SPECIAL STATE SAFETY
-- =============================================================================

TestUiStateSafety = {}

function TestUiStateSafety:testSeparatorFieldsAreIgnoredByManagedUiState()
    local modConfig = {
        Flag = true,
    }

    local uiState = lib.createStore(modConfig, {
        stateSchema = {
            { type = "separator", label = "Section" },
            { type = "checkbox", configKey = "Flag", default = false },
        },
    }).uiState

    lu.assertTrue(uiState.view.Flag)
    uiState.set("Flag", false)
    lu.assertTrue(uiState.isDirty())
    uiState.flushToConfig()
    lu.assertFalse(modConfig.Flag)
end

-- =============================================================================
-- FINGERPRINT
-- =============================================================================

TestHashFingerprint = {}

function TestHashFingerprint:testSameConfigSameFingerprint()
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true,  default = false },
        { id = "B", category = "Cat1", enabled = false, default = false },
    })
    local GetHash = withDiscovery(discovery)
    local _, fp1 = GetHash()
    local _, fp2 = GetHash()
    lu.assertEquals(fp1, fp2)
end

function TestHashFingerprint:testDifferentConfigDifferentFingerprint()
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true,  default = false },
        { id = "B", category = "Cat1", enabled = false, default = false },
    })
    local GetHash = withDiscovery(discovery)
    local _, fp1 = GetHash()

    discovery.modules[2].mod.config.Enabled = true
    local _, fp2 = GetHash()

    lu.assertNotEquals(fp1, fp2)
end

function TestHashFingerprint:testFingerprintIsNonEmptyString()
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true, default = false },
    })
    local GetHash = withDiscovery(discovery)
    local _, fp = GetHash()
    lu.assertIsString(fp)
    lu.assertTrue(#fp > 0)
end

function TestHashFingerprint:testAllDefaultsHasStableFingerprint()
    -- Even with empty canonical, fingerprint should be stable
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = false, default = false },
    })
    local GetHash = withDiscovery(discovery)
    local _, fp1 = GetHash()
    local _, fp2 = GetHash()
    lu.assertEquals(fp1, fp2)
end

-- =============================================================================
-- ERROR HANDLING
-- =============================================================================

TestHashErrors = {}

function TestHashErrors:testNilHashRejected()
    local discovery = MockDiscovery.create({})
    local _, ApplyHash = withDiscovery(discovery)
    ---@diagnostic disable-next-line: param-type-mismatch
    lu.assertFalse(ApplyHash(nil))
end

function TestHashErrors:testEmptyHashRejected()
    -- Empty string is invalid — valid all-defaults canonical is "_v=1"
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true, default = false },
    })
    local _, ApplyHash = withDiscovery(discovery)
    lu.assertFalse(ApplyHash(""))
end

function TestHashErrors:testMalformedHashRejected()
    -- Input with no parseable key=value pairs (missing version key) is rejected
    local discovery = MockDiscovery.create({
        { id = "A", category = "Cat1", enabled = true, default = false },
    })
    local _, ApplyHash = withDiscovery(discovery)
    lu.assertFalse(ApplyHash("notavalidentry"))
end

function TestHashErrors:testUnknownOptionTypeDoesNotCrashHashEncodeOrDecode()
    local previousDebugMode = config.DebugMode
    config.DebugMode = true
    CaptureWarnings()

    local discovery = MockDiscovery.create({
        {
            id = "A",
            category = "Cat1",
            enabled = true,
            default = false,
            options = {
                { type = "mystery", configKey = "Mode", default = "Vanilla", _hashKey = "A.Mode" },
            },
        },
    })
    discovery.modules[1].mod.config.Mode = "Always"

    local GetHash, ApplyHash = withDiscovery(discovery)
    local canonical = GetHash()
    lu.assertEquals(canonical, "_v=1|A=1")

    discovery.modules[1].mod.config.Mode = "Always"
    lu.assertTrue(ApplyHash("_v=1|A.Mode=Broken"))
    lu.assertEquals(discovery.modules[1].mod.config.Mode, "Vanilla")

    local warnings = Warnings
    RestoreWarnings()
    config.DebugMode = previousDebugMode

    lu.assertTrue(#warnings >= 2)
    lu.assertStrContains(table.concat(warnings, "\n"), "unknown field type")
end
