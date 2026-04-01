local lu = require('luaunit')

TestLibSpecialUiPass = {}

function TestLibSpecialUiPass:testFlushesManagedStateAndCallsCallback()
    local modConfig = {
        Flag = false,
    }
    local schema = {
        { type = "checkbox", configKey = "Flag", default = false },
    }
    local specialState = lib.createStore(modConfig, schema).specialState

    local flushed = false
    local didFlush = lib.runSpecialUiPass({
        name = "MySpecial",
        specialState = specialState,
        draw = function(_, state)
            state.set("Flag", true)
        end,
        onFlushed = function()
            flushed = true
        end,
    })

    lu.assertTrue(didFlush)
    lu.assertTrue(flushed)
    lu.assertTrue(modConfig.Flag)
end

function TestLibSpecialUiPass:testMissingSpecialStateSkipsSafely()
    local didFlush = lib.runSpecialUiPass({
        name = "MySpecial",
        draw = function()
            error("draw should not run when specialState is malformed")
        end,
    })

    lu.assertFalse(didFlush)
end

TestLibSchemaValidation = {}

function TestLibSchemaValidation:testDuplicateConfigKeysWarn()
    local previousDebugMode = lib.config.DebugMode
    lib.config.DebugMode = true
    CaptureWarnings()

    lib.validateSchema({
        { type = "checkbox", configKey = "Flag", default = false },
        { type = "checkbox", configKey = "Flag", default = false },
    }, "DuplicateSchema")

    local warnings = Warnings
    RestoreWarnings()
    lib.config.DebugMode = previousDebugMode

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "duplicate configKey 'Flag'")
end
