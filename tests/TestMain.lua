local lu = require('luaunit')

TestMain = {}

function TestMain:testGetRendererIsSafeBeforeInit()
    local render = public.getRenderer("missing-pack")
    lu.assertTrue(pcall(render))
end

function TestMain:testGetMenuBarIsSafeBeforeInit()
    local addMenuBar = public.getMenuBar("missing-pack")
    lu.assertTrue(pcall(addMenuBar))
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
        TextColored = noop,
        GetCursorPosX = function() return 0 end,
        SetCursorPosX = noop,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemSpacing = { x = 8, y = 4 },
            }
        end,
        CalcTextSize = function(text) return #(tostring(text or "")) * 8 end,
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

    local discovery = MockDiscovery.create({
        {
            modName = "Alpha",
            id = "Alpha",
            name = "Alpha",
            category = "General",
            enabled = true,
            storage = {},
            apply = function()
                firstState.applied = firstState.applied + 1
            end,
            revert = function()
                firstState.reverted = firstState.reverted + 1
            end,
        },
        {
            modName = "Bravo",
            id = "Bravo",
            name = "Bravo",
            category = "General",
            enabled = true,
            storage = {},
            apply = function()
                secondState.applied = secondState.applied + 1
                error("apply boom")
            end,
            revert = function()
                secondState.reverted = secondState.reverted + 1
            end,
        },
    })

    local hudMarkers = {}
    local hud = {
        setModMarker = function(val)
            table.insert(hudMarkers, val)
        end,
        markHashDirty = noop,
        refreshHashIfIdle = noop,
        flushPendingHash = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = Framework.createTheme()
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
    local warnings = Warnings

    rom.ImGui = previousImGui
    SetupRunData = previousSetupRunData
    RestoreWarnings()

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
    lu.assertEquals(#warnings, 2)
    lu.assertStrContains(warnings[1], "[test-pack] Bravo apply failed: ")
    lu.assertStrContains(warnings[2], "[test-pack] Enable Mod toggle failed; restoring previous runtime state")
end

function TestMain:testQuickSetupCanFilterQuickCandidatesByDefinitionSelector()
    local previousImGui = rom.ImGui
    local checkboxLabels = {}

    local function noop() end

    rom.ImGui = {
        Begin = function() return true end,
        End = noop,
        MenuItem = function() return true end,
        Checkbox = function(label, current)
            table.insert(checkboxLabels, label)
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
        TextColored = noop,
        GetCursorPosX = function() return 0 end,
        SetCursorPosX = noop,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemSpacing = { x = 8, y = 4 },
            }
        end,
        CalcTextSize = function(text) return #(tostring(text or "")) * 8 end,
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

    local discovery = MockDiscovery.create({
        {
            modName = "Alpha",
            id = "Alpha",
            name = "Alpha",
            category = "General",
            enabled = true,
            storage = {
                { type = "bool", alias = "FlagA", configKey = "FlagA", default = false },
                { type = "bool", alias = "FlagB", configKey = "FlagB", default = false },
            },
            ui = {
                { type = "checkbox", binds = { value = "FlagA" }, label = "Quick A", quick = true },
                { type = "checkbox", binds = { value = "FlagB" }, label = "Quick B", quick = true },
            },
            selectQuickUi = function()
                return { "value=FlagB" }
            end,
            apply = function() end,
            revert = function() end,
        },
    })
    discovery.unifiedTabOrder = {
        { kind = "category", entry = { key = "General", label = "General" } },
    }

    local hud = {
        setModMarker = noop,
        markHashDirty = noop,
        refreshHashIfIdle = noop,
        flushPendingHash = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = Framework.createTheme()
    local def = {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }

    local builtUi = Framework.createUI(discovery, hud, theme, def, config, lib, "test-pack", "Test Window")
    builtUi.addMenuBar()
    local ok, err = pcall(builtUi.renderWindow)

    rom.ImGui = previousImGui

    lu.assertTrue(ok, tostring(err))
    local joined = table.concat(checkboxLabels, "\n")
    lu.assertStrContains(joined, "Enable Mod")
    lu.assertStrContains(joined, "Quick B")
    lu.assertNotStrContains(joined, "Quick A")
end

function TestMain:testAlwaysDrawRendererFlushesPendingHashWhenHostGuiDisappears()
    local previousGui = rom.gui
    local guiOpen = true
    local flushCalls = 0

    rom.gui = {
        is_open = function()
            return guiOpen
        end,
    }

    local packId = "flush-pack"
    local alwaysDraw = public.getAlwaysDrawRenderer(packId)

    local capturedPacks = nil
    for index = 1, 10 do
        local name, value = debug.getupvalue(alwaysDraw, index)
        if name == "_packs" then
            capturedPacks = value
            break
        end
    end

    local previousPack = capturedPacks and capturedPacks[packId] or nil
    capturedPacks[packId] = {
        hud = {
            flushPendingHash = function()
                flushCalls = flushCalls + 1
            end,
        },
    }

    alwaysDraw()
    guiOpen = false
    alwaysDraw()
    alwaysDraw()

    rom.gui = previousGui
    capturedPacks[packId] = previousPack

    lu.assertEquals(flushCalls, 1)
end
