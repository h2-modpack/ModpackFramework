local lu = require('luaunit')

TestLibUiStatePass = {}

function TestLibUiStatePass:testFlushesManagedStateAndCallsCallback()
    local modConfig = {
        Flag = false,
    }
    local definition = {
        stateSchema = {
            { type = "checkbox", configKey = "Flag", default = false },
        },
    }
    local uiState = lib.createStore(modConfig, definition).uiState

    local flushed = false
    local didFlush = lib.runUiStatePass({
        name = "MyState",
        uiState = uiState,
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

function TestLibUiStatePass:testMissingUiStateSkipsSafely()
    local didFlush = lib.runUiStatePass({
        name = "MyState",
        draw = function()
            error("draw should not run when uiState is malformed")
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
