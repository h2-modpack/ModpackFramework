local lu = require('luaunit')

TestMain = {}

function TestMain:testGetRendererIsSafeBeforeInit()
    local render = public.getRenderer("missing-pack")
    local ok = pcall(render)
    lu.assertTrue(ok)
end

function TestMain:testGetMenuBarIsSafeBeforeInit()
    local addMenuBar = public.getMenuBar("missing-pack")
    local ok = pcall(addMenuBar)
    lu.assertTrue(ok)
end

function TestMain:testMasterToggleRollsBackTouchedRuntimeStateOnFailure()
    CaptureWarnings()

    local previousSetupRunData = SetupRunData
    local setupRunDataCalls = 0
    SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local previousImGui = rom.ImGui
    local masterCheckboxPass = 1
    local secondPassCurrent = nil

    local function noop() end

    rom.ImGui = {
        Begin = function() return true end,
        End = noop,
        MenuItem = function() return true end,
        Checkbox = function(label, current)
            if label == "Enable Mod" then
                if masterCheckboxPass == 1 then
                    masterCheckboxPass = 2
                    return true, true
                end
                secondPassCurrent = current
                return current, false
            end
            return current, false
        end,
        IsItemHovered = function() return false end,
        SetTooltip = noop,
        Separator = noop,
        SameLine = noop,
        Spacing = noop,
        TextColored = noop,
        GetWindowWidth = function() return 1000 end,
        BeginChild = function() return true end,
        EndChild = noop,
        Selectable = function() return false end,
        BeginCombo = function() return false end,
        EndCombo = noop,
        PushItemWidth = noop,
        PopItemWidth = noop,
        Text = noop,
        Button = function() return false end,
        InputText = function(_, value) return value, false end,
        GetClipboardText = function() return nil end,
        SetClipboardText = noop,
        CollapsingHeader = function() return false end,
        Indent = noop,
        Unindent = noop,
        PushID = noop,
        PopID = noop,
        PushStyleColor = noop,
        PopStyleColor = noop,
    }

    local firstState = { applied = 0, reverted = 0 }
    local secondState = { applied = 0, reverted = 0 }

    local firstStore = lib.createStore({ Enabled = true })
    local secondStore = lib.createStore({ Enabled = true })

    local discovery = {
        modules = {
            {
                id = "Alpha",
                name = "Alpha",
                modName = "AlphaMod",
                category = "General",
                mod = { store = firstStore },
                definition = {
                    apply = function() firstState.applied = firstState.applied + 1 end,
                    revert = function() firstState.reverted = firstState.reverted + 1 end,
                },
            },
            {
                id = "Bravo",
                name = "Bravo",
                modName = "BravoMod",
                category = "General",
                mod = { store = secondStore },
                definition = {
                    apply = function()
                        secondState.applied = secondState.applied + 1
                        error("apply boom")
                    end,
                    revert = function() secondState.reverted = secondState.reverted + 1 end,
                },
            },
        },
        modulesWithOptions = {},
        specials = {},
        categories = {},
        byCategory = {},
        categoryLayouts = {},
        isModuleEnabled = function(m)
            return m.mod.store.read("Enabled") == true
        end,
        isSpecialEnabled = function(special)
            return special.mod.store.read("Enabled") == true
        end,
        isDebugEnabled = function()
            return false
        end,
    }

    local hudMarkers = {}
    local hud = {
        setModMarker = function(val)
            table.insert(hudMarkers, val)
        end,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = {
        colors = {
            warning = { 1, 1, 1, 1 },
            info = { 1, 1, 1, 1 },
            success = { 1, 1, 1, 1 },
            error = { 1, 1, 1, 1 },
            mixed = { 1, 1, 1, 1 },
            textDisabled = { 1, 1, 1, 1 },
        },
        ImGuiTreeNodeFlags = { DefaultOpen = 0 },
        SIDEBAR_RATIO = 0.2,
        FIELD_MEDIUM = 0.5,
        FIELD_NARROW = 0.3,
        FIELD_WIDE = 0.85,
        PushTheme = noop,
        PopTheme = noop,
    }

    local def = {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local config = {
        ModEnabled = false,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }

    local builtUi = Framework.createUI(discovery, hud, theme, def, config, lib, "test-pack", "Test Window")
    builtUi.addMenuBar()

    local okFirst, errFirst = pcall(builtUi.renderWindow)
    local okSecond, errSecond = pcall(builtUi.renderWindow)

    rom.ImGui = previousImGui
    SetupRunData = previousSetupRunData

    lu.assertTrue(okFirst, tostring(errFirst))
    lu.assertTrue(okSecond, tostring(errSecond))
    lu.assertFalse(config.ModEnabled)
    lu.assertEquals(secondPassCurrent, false)
    lu.assertEquals(setupRunDataCalls, 0)
    lu.assertEquals(#hudMarkers, 0)
    lu.assertEquals(firstState.applied, 1)
    lu.assertEquals(firstState.reverted, 1)
    lu.assertEquals(secondState.applied, 1)
    lu.assertEquals(secondState.reverted, 0)
    lu.assertEquals(#Warnings, 2)
    lu.assertStrContains(Warnings[1], "[test-pack] BravoMod apply failed: ")
    lu.assertStrContains(Warnings[2], "[test-pack] Enable Mod toggle failed; restoring previous runtime state")

    RestoreWarnings()
end
