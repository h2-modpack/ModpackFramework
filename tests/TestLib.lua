local lu = require('luaunit')

TestLibUiStatePass = {}

function TestLibUiStatePass:testFlushesManagedAliasStateAndCallsCallback()
    local config = { Flag = false }
    local definition = {
        storage = {
            { type = "bool", alias = "Flag", configKey = "Flag", default = false },
        },
        ui = {
            { type = "checkbox", binds = { value = "Flag" }, label = "Flag" },
        },
    }
    local uiState = lib.createStore(config, definition).uiState

    local flushed = false
    local didFlush = lib.runUiStatePass({
        name = "ManagedState",
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
    lu.assertTrue(config.Flag)
end

function TestLibUiStatePass:testMissingUiStateSkipsSafely()
    local didFlush = lib.runUiStatePass({
        name = "MissingState",
        draw = function()
            error("draw should not run")
        end,
    })

    lu.assertFalse(didFlush)
end

TestLibValidation = {}

function TestLibValidation:testDuplicateStorageAliasesWarn()
    CaptureWarnings()
    lib.validateStorage({
        { type = "bool", alias = "Flag", configKey = "FlagA", default = false },
        { type = "bool", alias = "Flag", configKey = "FlagB", default = false },
    }, "DuplicateStorage")
    local warnings = Warnings
    RestoreWarnings()

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "duplicate alias 'Flag'")
end
