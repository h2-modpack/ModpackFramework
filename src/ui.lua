-- =============================================================================
-- UI: Main window, sidebar, tab rendering
-- =============================================================================
-- All Core.* globals replaced with closed-over factory parameters.
-- Registration (add_imgui / add_to_menu_bar) is handled by Framework.init —
-- this factory only returns { renderWindow, addMenuBar }.

--- Create the main ImGui UI subsystem for one coordinator pack.
--- @param discovery table Discovery object returned by `Framework.createDiscovery(...)`.
--- @param hud table HUD object returned by `Framework.createHud(...)`.
--- @param theme table Theme object returned by `Framework.createTheme(...)`.
--- @param def table Coordinator definition table containing profile and layout metadata.
--- @param config table Coordinator config table.
--- @param lib table Adamant Modpack Lib export.
--- @param packId string Pack identifier used in warnings.
--- @param windowTitle string Window title shown in the mod menu.
--- @return table ui UI object exposing `{ renderWindow, addMenuBar }`.
function Framework.createUI(discovery, hud, theme, def, config, lib, packId, windowTitle)
    local ui                 = rom.ImGui

    -- Unpack theme for convenient access
    local colors             = theme.colors
    local ImGuiTreeNodeFlags = theme.ImGuiTreeNodeFlags
    local SIDEBAR_RATIO      = theme.SIDEBAR_RATIO
    local FIELD_MEDIUM       = theme.FIELD_MEDIUM
    local FIELD_NARROW       = theme.FIELD_NARROW
    local FIELD_WIDE         = theme.FIELD_WIDE
    local PushTheme          = theme.PushTheme
    local PopTheme           = theme.PopTheme

    local function DrawColoredText(color, text)
        ui.TextColored(color[1], color[2], color[3], color[4], text)
    end
    local function PushTextColor(color)
        ui.PushStyleColor(rom.ImGuiCol.Text, color[1], color[2], color[3], color[4])
    end

    -- =============================================================================
    -- STAGING TABLE (performance cache — avoids Chalk reads in render loop)
    -- =============================================================================
    -- Plain Lua tables mirroring each module's Chalk config.
    -- UI reads/writes go through staging. Chalk is only touched in event handlers.

    local _EMPTY_OPTS = {} -- sentinel to avoid `or {}` alloc in DrawCheckboxGroup

    local staging = {
        ModEnabled = config.ModEnabled == true, -- snapshot once
        modules    = {},                        -- [module.id] = bool
        specials   = {},                        -- [special.modName] = bool (enabled state)
        debug      = {},                        -- [module.id or special.modName] = bool (DebugMode per entry)
    }

    -- Profile staging: plain copies of config.Profiles
    local profileStaging = {}

    --- Snapshot all Chalk configs into staging (called at init and after profile load).
    local function SnapshotToStaging()
        staging.ModEnabled = config.ModEnabled == true

        -- Boolean modules
        for _, m in ipairs(discovery.modules) do
            staging.modules[m.id] = discovery.isModuleEnabled(m)
        end

        -- Managed UI state for regular modules
        for _, m in ipairs(discovery.modulesWithUi) do
            local uiState = m.mod.store and m.mod.store.uiState
            if uiState and uiState.reloadFromConfig then
                uiState.reloadFromConfig()
            end
        end

        -- Special modules
        for _, special in ipairs(discovery.specials) do
            staging.specials[special.modName] = discovery.isSpecialEnabled(special)
            staging.debug[special.modName] = discovery.isDebugEnabled(special)
            local uiState = special.uiState
            if uiState and uiState.reloadFromConfig then
                uiState.reloadFromConfig()
            end
        end

        -- Per-module debug states
        for _, m in ipairs(discovery.modules) do
            staging.debug[m.id] = discovery.isDebugEnabled(m)
        end

        -- Profiles
        for i, p in ipairs(config.Profiles) do
            profileStaging[i] = {
                Name    = p.Name or "",
                Hash    = p.Hash or "",
                Tooltip = p.Tooltip or "",
            }
        end
    end

    -- Initialize staging from current configs
    SnapshotToStaging()

    -- =============================================================================
    -- CACHED DISPLAY DATA (rebuilt on dirty flag, never per-frame)
    -- =============================================================================

    local NUM_PROFILES = def.NUM_PROFILES

    local slotLabels = {}
    local slotOccupied = {}
    local slotLabelsDirty = true

    local cachedHash = nil
    local cachedFingerprint = nil

    local selectedProfileSlot = 1
    local selectedProfileCombo = 0
    local importHashBuffer = ""
    local importFeedback = nil
    local importFeedbackColor = nil
    local importFeedbackTime = nil
    local categoryStatusCache = {}
    local categoryStatusDirty = {}

    local FEEDBACK_DURATION = 2.0
    local function SetImportFeedback(text, color)
        importFeedback = text
        importFeedbackColor = color
        importFeedbackTime = os.clock()
    end

    local function InvalidateHash()
        cachedHash = nil
        cachedFingerprint = nil
    end

    local function InvalidateCategoryStatus(category)
        if category then
            categoryStatusDirty[category] = true
            return
        end
        for key in pairs(categoryStatusCache) do
            categoryStatusDirty[key] = true
        end
    end

    local function GetCachedHash()
        if not cachedHash then
            cachedHash, cachedFingerprint = hud.getConfigHash(staging)
        end
        return cachedHash, cachedFingerprint
    end

    local function RebuildSlotLabels()
        for i, p in ipairs(profileStaging) do
            local hasName = p.Name ~= ""
            slotOccupied[i] = hasName
            if hasName then
                slotLabels[i] = i .. ": " .. p.Name
            else
                slotLabels[i] = i .. ": (empty)"
            end
        end
        slotLabelsDirty = false
    end

    -- =============================================================================
    -- TOGGLE HELPERS (event handlers — OK to touch Chalk here)
    -- =============================================================================

    local function FinishUiChange(definition, enabled, category)
        if lib.affectsRunData(definition) and enabled then
            SetupRunData()
        end
        InvalidateHash()
        if category then
            InvalidateCategoryStatus(category)
        end
        hud.updateHash()
    end

    local function ToggleEntry(entry, enabled, stagingBucket, stagingKey, category)
        local setter = entry.definition.special and discovery.setSpecialEnabled or discovery.setModuleEnabled
        local ok = setter(entry, enabled)
        if not ok then
            return
        end
        stagingBucket[stagingKey] = enabled
        FinishUiChange(entry.definition, enabled, category)
    end

    local function OnUiStateFlushed(definition, enabled)
        FinishUiChange(definition, enabled)
    end

    --- Apply enable/disable on the game side only without persisting an entry's Enabled bit.
    --- Used by the coordinator master toggle to suspend/resume already-selected entries.
    local function SetEntryRuntimeState(entry, state)
        local ok, err
        if state then
            ok, err = lib.applyDefinition(entry.definition, entry.mod.store)
        else
            ok, err = lib.revertDefinition(entry.definition, entry.mod.store)
        end
        if not ok then
            lib.contractWarn(packId,
                "%s %s failed: %s", entry.modName or "unknown", state and "apply" or "revert", err)
        end
        return ok, err
    end

    local function RollBackTouchedEntries(touched, previousState)
        local rollbackErrors = {}
        for i = #touched, 1, -1 do
            local rollbackEntry = touched[i]
            local rollbackOk, rollbackErr = SetEntryRuntimeState(rollbackEntry, previousState)
            if not rollbackOk then
                table.insert(rollbackErrors,
                    string.format("%s: %s",
                        tostring(rollbackEntry.modName or rollbackEntry.id or "unknown"),
                        tostring(rollbackErr)))
            end
        end
        if #rollbackErrors > 0 then
            lib.contractWarn(packId,
                "Enable Mod rollback incomplete: %s",
                table.concat(rollbackErrors, "; "))
        end
    end

    --- Apply the coordinator master toggle transactionally across all selected entries.
    --- On failure, already-touched entries are restored to the previous pack runtime state.
    --- @param state boolean
    --- @return boolean, string|nil
    local function SetPackRuntimeState(state)
        local previousState = staging.ModEnabled == true
        local touched = {}

        for _, m in ipairs(discovery.modules) do
            if staging.modules[m.id] then
                local ok, err = SetEntryRuntimeState(m, state)
                if not ok then
                    lib.contractWarn(packId,
                        "Enable Mod toggle failed; restoring previous runtime state")
                    RollBackTouchedEntries(touched, previousState)
                    return false, err
                end
                table.insert(touched, m)
            end
        end

        for _, special in ipairs(discovery.specials) do
            if staging.specials[special.modName] then
                local ok, err = SetEntryRuntimeState(special, state)
                if not ok then
                    lib.contractWarn(packId,
                        "Enable Mod toggle failed; restoring previous runtime state")
                    RollBackTouchedEntries(touched, previousState)
                    return false, err
                end
                table.insert(touched, special)
            end
        end

        staging.ModEnabled = state
        config.ModEnabled = state
        SetupRunData()
        hud.setModMarker(state)
        return true, nil
    end

    --- Load a profile hash: decode, apply to all module configs, re-snapshot.
    local function LoadProfile(profileHash)
        if hud.applyConfigHash(profileHash) then
            SetupRunData()
            SnapshotToStaging()
            InvalidateHash()
            InvalidateCategoryStatus()
            slotLabelsDirty = true
            hud.updateHash()
            return true
        end
        return false
    end

    local function GetCategoryStatus(category)
        if categoryStatusDirty[category] ~= true and categoryStatusCache[category] then
            local cached = categoryStatusCache[category]
            return cached.text, cached.color, cached.hasEntries
        end

        local modules = discovery.byCategory[category] or {}
        if #modules == 0 then
            categoryStatusCache[category] = {
                text = "N/A",
                color = colors.textDisabled,
                hasEntries = false,
            }
            categoryStatusDirty[category] = false
            return "N/A", colors.textDisabled, false
        end

        local hasEnabled = false
        local hasDisabled = false
        for _, m in ipairs(modules) do
            if staging.modules[m.id] then hasEnabled = true else hasDisabled = true end
        end

        if hasEnabled and not hasDisabled then
            categoryStatusCache[category] = {
                text = "All Enabled",
                color = colors.success,
                hasEntries = true,
            }
            categoryStatusDirty[category] = false
            return "All Enabled", colors.success, true
        end
        if hasDisabled and not hasEnabled then
            categoryStatusCache[category] = {
                text = "All Disabled",
                color = colors.error,
                hasEntries = true,
            }
            categoryStatusDirty[category] = false
            return "All Disabled", colors.error, true
        end
        categoryStatusCache[category] = {
            text = "Mixed Configuration",
            color = colors.mixed,
            hasEntries = true,
        }
        categoryStatusDirty[category] = false
        return "Mixed Configuration", colors.mixed, true
    end

    local function SetCategoryEnabled(category, flag)
        local modules = discovery.byCategory[category] or {}
        local touchedRunData = false
        for _, m in ipairs(modules) do
            local ok = discovery.setModuleEnabled(m, flag)
            if ok then
                staging.modules[m.id] = flag
            end
            if ok and lib.affectsRunData(m.definition) then
                touchedRunData = true
            end
        end
        if touchedRunData then
            SetupRunData()
        end
        InvalidateHash()
        InvalidateCategoryStatus(category)
        hud.updateHash()
    end

    local quickSetupContext = {
        ui                = ui,
        colors            = colors,
        theme             = theme,
        drawColoredText   = DrawColoredText,
        getCategoryStatus = GetCategoryStatus,
        setCategoryEnabled = SetCategoryEnabled,
        getCategoryModules = function(category)
            return discovery.byCategory[category] or {}
        end,
    }

    local defaultProfiles = def.defaultProfiles

    -- =============================================================================
    -- GENERIC TAB CONTENT RENDERER
    -- =============================================================================

    local function DrawGroupItems(group, winW)
        for _, itemData in ipairs(group.Items) do
            local m = discovery.modulesById[itemData.Key]
            if m then
                local currentVal = staging.modules[m.id] or false
                local val, chg = ui.Checkbox(itemData.Name, currentVal)
                if chg then
                    ToggleEntry(m, val, staging.modules, m.id, m.category)
                end
                if ui.IsItemHovered() and itemData.Tooltip and itemData.Tooltip ~= "" then
                    ui.SetTooltip(itemData.Tooltip)
                end

                if currentVal and type(m.ui) == "table" and #m.ui > 0 then
                    ui.Indent()
                    local uiState = m.mod.store and m.mod.store.uiState
                    lib.runUiStatePass({
                        name = m.name or m.id,
                        imgui = ui,
                        uiState = uiState,
                        commit = function(state)
                            return lib.commitUiState(m.definition, m.mod.store, state)
                        end,
                        draw = function()
                            lib.drawUiTree(ui, m.ui, uiState, winW * FIELD_MEDIUM, m.definition.customTypes)
                        end,
                        onFlushed = function()
                            OnUiStateFlushed(m.definition, staging.modules[m.id])
                        end,
                    })
                    ui.Unindent()
                end
            end
        end
    end

    local function DrawCheckboxGroup(layoutData)
        local winW = ui.GetWindowWidth()
        for _, group in ipairs(layoutData) do
            local style = group.style
            -- "collapsing" : collapsing header (default)
            -- "separator"  : labeled section header (non-collapsing) + separator line
            -- "flat"       : items rendered directly, no label
            if style == "collapsing" or not (style == "separator" or style == "flat") then
                PushTextColor(colors.info)
                local open = ui.CollapsingHeader(group.Header, ImGuiTreeNodeFlags.DefaultOpen)
                ui.PopStyleColor()
                if open then
                    ui.Indent()
                    DrawGroupItems(group, winW)
                    ui.Unindent()
                end
            elseif style == "separator" then
                DrawColoredText(colors.info, group.Header)
                ui.Separator()
                DrawGroupItems(group, winW)
            else
                -- "flat" or "auto" with single item
                DrawGroupItems(group, winW)
            end
            ui.Spacing()
        end
    end

    -- =============================================================================
    -- SIDE TAB DEFINITIONS
    -- =============================================================================

    local selectedTab = "Quick Setup"

    local cachedTabList = nil
    local cachedQuickList = nil  -- ordered list of { kind="special"|"regular", entry=... }
    local specialQuickPassOpts = {}
    local specialTabPassOpts = {}

    -- Build a lookup from category key -> modules with quick UI nodes in that category.
    local quickModulesByCategory = {}
    for _, m in ipairs(discovery.modulesWithQuickUi) do
        local cat = m.category
        quickModulesByCategory[cat] = quickModulesByCategory[cat] or {}
        table.insert(quickModulesByCategory[cat], m)
    end

    local function BuildTabList()
        if cachedTabList then return cachedTabList end
        cachedTabList = { "Quick Setup" }
        cachedQuickList = {}

        for _, item in ipairs(discovery.unifiedTabOrder or {}) do
            if item.kind == "category" then
                table.insert(cachedTabList, item.entry.label)
                for _, m in ipairs(quickModulesByCategory[item.entry.key] or {}) do
                    table.insert(cachedQuickList, { kind = "regular", entry = m })
                end
            else
                table.insert(cachedTabList, item.entry._tabLabel)
                table.insert(cachedQuickList, { kind = "special", entry = item.entry })
            end
        end

        table.insert(cachedTabList, "Profiles")
        table.insert(cachedTabList, "Dev")
        return cachedTabList
    end

    local function BuildSpecialPassOpts(special)
        return {
            name = special.definition.name or special.modName,
            imgui = ui,
            uiState = special.uiState,
            theme = theme,
            commit = function(state)
                return lib.commitUiState(special.definition, special.mod.store, state)
            end,
            draw = nil,
            onFlushed = function()
                OnUiStateFlushed(special.definition, staging.specials[special.modName])
            end,
        }
    end

    local function AuditAndResyncAllUiState()
        for _, m in ipairs(discovery.modulesWithUi) do
            local uiState = m.mod.store and m.mod.store.uiState
            if uiState then
                lib.auditAndResyncUiState(m.name or m.id or m.modName, uiState)
            end
        end
        for _, special in ipairs(discovery.specials) do
            local uiState = special.uiState
            if uiState then
                lib.auditAndResyncUiState(special.definition.name or special.modName, uiState)
            end
        end
        SnapshotToStaging()
    end

    -- Build lookup: tab label -> special entry
    local specialByTabLabel = {}

    for _, special in ipairs(discovery.specials) do
        specialByTabLabel[special._tabLabel] = special
        specialQuickPassOpts[special.modName] = BuildSpecialPassOpts(special)
        specialTabPassOpts[special.modName] = BuildSpecialPassOpts(special)
    end

    -- =============================================================================
    -- TAB CONTENT DRAWERS
    -- =============================================================================

    local function DrawQuickSetup()
        local winW = ui.GetWindowWidth()

        DrawColoredText(colors.info, "Select a profile to automatically configure the modpack:")
        ui.Spacing()

        if slotLabelsDirty then RebuildSlotLabels() end

        local comboPreview = "Select..."
        if selectedProfileCombo > 0 and selectedProfileCombo <= NUM_PROFILES and slotOccupied[selectedProfileCombo] then
            comboPreview = slotLabels[selectedProfileCombo]
        end

        ui.PushItemWidth(winW * FIELD_MEDIUM)
        if ui.BeginCombo("Profile", comboPreview) then
            for i = 1, NUM_PROFILES do
                if slotOccupied[i] then
                    ui.PushID(i)
                    if ui.Selectable(slotLabels[i], i == selectedProfileCombo) then
                        selectedProfileCombo = i
                    end
                    if ui.IsItemHovered() then
                        local tip = profileStaging[i].Tooltip
                        if tip ~= "" then ui.SetTooltip(tip) end
                    end
                    ui.PopID()
                end
            end
            ui.EndCombo()
        end
        ui.PopItemWidth()

        ui.SameLine()
        local sel = selectedProfileCombo
        if sel > 0 and sel <= NUM_PROFILES then
            local h = profileStaging[sel].Hash
            if h ~= "" then
                if ui.Button("Load") then LoadProfile(h) end
            end
        end

        ui.Separator()
        ui.Spacing()

        if type(def.renderQuickSetup) == "function" then
            def.renderQuickSetup(quickSetupContext)
        end

        local function SelectQuickNodes(module)
            local quickNodes = module.quickUi or {}
            local selector = module.definition and module.definition.selectQuickUi
            if type(selector) ~= "function" then
                return quickNodes
            end

            local selected = selector(module.mod.store, module.mod.store and module.mod.store.uiState, quickNodes)
            if selected == nil then
                return quickNodes
            end

            local selectedSet = {}
            if type(selected) == "string" then
                selectedSet[selected] = true
            elseif type(selected) == "table" then
                for key, value in pairs(selected) do
                    if type(key) == "number" then
                        if type(value) == "string" and value ~= "" then
                            selectedSet[value] = true
                        end
                    elseif value == true then
                        selectedSet[tostring(key)] = true
                    end
                end
            else
                return quickNodes
            end

            local filtered = {}
            for _, node in ipairs(quickNodes) do
                local quickId = lib.getQuickUiNodeId(node)
                if quickId and selectedSet[quickId] then
                    table.insert(filtered, node)
                end
            end
            return filtered
        end

        for _, item in ipairs(cachedQuickList or {}) do
            if item.kind == "special" then
                local special = item.entry
                if staging.specials[special.modName] and special.mod.DrawQuickContent then
                    ui.Separator()
                    ui.Spacing()
                    local passOpts = specialQuickPassOpts[special.modName]
                    passOpts.draw = passOpts.draw or special.mod.DrawQuickContent
                    lib.runUiStatePass(passOpts)
                end
            else
                local m = item.entry
                if staging.modules[m.id] then
                    ui.Separator()
                    ui.Spacing()
                    DrawColoredText(colors.info, m.name or m.id)
                    ui.Spacing()
                    local uiState = m.mod.store and m.mod.store.uiState
                    lib.runUiStatePass({
                        name = m.name or m.id,
                        imgui = ui,
                        uiState = uiState,
                        commit = function(state)
                            return lib.commitUiState(m.definition, m.mod.store, state)
                        end,
                        draw = function()
                            for _, node in ipairs(SelectQuickNodes(m)) do
                                lib.drawUiNode(ui, node, uiState, winW * FIELD_MEDIUM, m.definition.customTypes)
                            end
                        end,
                        onFlushed = function()
                            OnUiStateFlushed(m.definition, staging.modules[m.id])
                        end,
                    })
                end
            end
        end
    end

    local function DrawSpecialTab(special)
        -- Enable checkbox (standardized by Framework)
        local enabled = staging.specials[special.modName] or false
        local val, chg = ui.Checkbox(special._enableLabel, enabled)
        if chg then
            ToggleEntry(special, val, staging.specials, special.modName)
        end
        if ui.IsItemHovered() and special.definition.tooltip then
            ui.SetTooltip(special.definition.tooltip)
        end

        if not enabled then return end

        ui.Spacing()

        -- Delegate tab content to the module or fall back to definition.ui
        if special.mod.DrawTab or (type(special.ui) == "table" and #special.ui > 0) then
            local passOpts = specialTabPassOpts[special.modName]
            passOpts.draw = passOpts.draw or special.mod.DrawTab or function(ui)
                lib.drawUiTree(ui, special.ui, special.uiState, ui.GetWindowWidth() * FIELD_MEDIUM, special.definition.customTypes)
            end
            lib.runUiStatePass(passOpts)
        end
    end

    local function DrawProfiles()
        local winW = ui.GetWindowWidth()

        -- Export / Import
        DrawColoredText(colors.info, "Export / Import")
        ui.Indent()

        -- Read cached hash (computed from staging, not Chalk)
        local canonical, fingerprint = GetCachedHash()
        ui.Text("Config ID:")
        ui.SameLine()
        DrawColoredText(colors.success, fingerprint)
        ui.SameLine()
        if ui.Button("Copy") then
            ui.SetClipboardText(canonical)
            SetImportFeedback("Copied to clipboard!", colors.success)
        end

        ui.Spacing()
        ui.Text("Import Hash:")
        ui.SameLine()
        ui.PushItemWidth(winW * FIELD_MEDIUM)
        local newText, changed = ui.InputText("##ImportHash", importHashBuffer, 2048)
        if changed then importHashBuffer = newText end
        ui.PopItemWidth()
        ui.SameLine()
        if ui.Button("Paste") then
            local clip = ui.GetClipboardText()
            if clip then importHashBuffer = clip end
        end
        ui.SameLine()
        if ui.Button("Import") then
            if LoadProfile(importHashBuffer) then
                SetImportFeedback("Imported successfully!", colors.success)
            else
                SetImportFeedback("Invalid hash.", colors.error)
            end
        end

        ui.Unindent()
        ui.Spacing()
        ui.Separator()
        ui.Spacing()

        -- Profile Slot Selector
        DrawColoredText(colors.info, "Saved Profiles")
        ui.Indent()

        if slotLabelsDirty then RebuildSlotLabels() end

        ui.PushItemWidth(winW * FIELD_NARROW)
        if ui.BeginCombo("Slot", slotLabels[selectedProfileSlot]) then
            for i, label in ipairs(slotLabels) do
                if ui.Selectable(label, i == selectedProfileSlot) then
                    selectedProfileSlot = i
                end
            end
            ui.EndCombo()
        end
        ui.PopItemWidth()

        ui.Spacing()

        -- Read from profileStaging, not Chalk
        local ps = profileStaging[selectedProfileSlot]
        local hasData = ps.Hash ~= ""

        ui.Text("Name:")
        ui.SameLine()
        ui.PushItemWidth(winW * FIELD_NARROW)
        local newName, nameChanged = ui.InputText("##SlotName", ps.Name, 64)
        if nameChanged then
            ps.Name = newName
            config.Profiles[selectedProfileSlot].Name = newName -- write to Chalk
            slotLabelsDirty = true
        end
        ui.PopItemWidth()

        ui.Text("Tooltip:")
        ui.SameLine()
        ui.PushItemWidth(winW * FIELD_WIDE)
        local newTooltip, tooltipChanged = ui.InputText("##SlotTooltip", ps.Tooltip, 256)
        if tooltipChanged then
            ps.Tooltip = newTooltip
            config.Profiles[selectedProfileSlot].Tooltip = newTooltip -- write to Chalk
        end
        ui.PopItemWidth()

        ui.Spacing()

        if ui.Button("Save Current") then
            local h = GetCachedHash()
            ps.Hash = h
            config.Profiles[selectedProfileSlot].Hash = h -- write to Chalk
            if ps.Name == "" then
                ps.Name = "Profile " .. selectedProfileSlot
                config.Profiles[selectedProfileSlot].Name = ps.Name
            end
            slotLabelsDirty = true
            SetImportFeedback("Profile saved.", colors.success)
        end

        if hasData then
            ui.SameLine()
            if ui.Button("Load") then
                if LoadProfile(ps.Hash) then
                    SetImportFeedback("Profile loaded.", colors.success)
                else
                    SetImportFeedback("Failed to load profile.", colors.error)
                end
            end
            ui.SameLine()
            if ui.Button("Copy Hash") then
                ui.SetClipboardText(ps.Hash)
                SetImportFeedback("Copied to clipboard!", colors.success)
            end
            ui.SameLine()
            if ui.Button("Clear") then
                ps.Name = ""
                ps.Hash = ""
                ps.Tooltip = ""
                local cp = config.Profiles[selectedProfileSlot]
                cp.Name = ""
                cp.Hash = ""
                cp.Tooltip = ""
                slotLabelsDirty = true
                SetImportFeedback("Slot cleared.", colors.textDisabled)
            end
            if ui.IsItemHovered() then
                ui.SetTooltip("Permanently clears this profile slot.")
            end
        end

        ui.Unindent()
        ui.Spacing()
        ui.Separator()
        ui.Spacing()

        if ui.Button("Restore Default Profiles") then
            for i = 1, NUM_PROFILES do
                local d = defaultProfiles[i]
                local cp = config.Profiles[i] -- Chalk write
                if d then
                    profileStaging[i] = { Name = d.Name, Hash = d.Hash, Tooltip = d.Tooltip }
                    cp.Name = d.Name
                    cp.Hash = d.Hash
                    cp.Tooltip = d.Tooltip
                else
                    profileStaging[i] = { Name = "", Hash = "", Tooltip = "" }
                    cp.Name = ""
                    cp.Hash = ""
                    cp.Tooltip = ""
                end
            end
            slotLabelsDirty = true
            SetImportFeedback("Default profiles restored.", colors.success)
        end
        if ui.IsItemHovered() then
            ui.SetTooltip("Overwrites ALL profile slots with the shipped defaults. Custom profiles will be lost.")
        end

        -- Status bar: single feedback line for all profile actions
        ui.Spacing()
        if importFeedback then
            if os.clock() - importFeedbackTime > FEEDBACK_DURATION then
                importFeedback = nil
            else
                DrawColoredText(importFeedbackColor, importFeedback)
            end
        end
    end

    local function DrawDev()
        DrawColoredText(colors.info, "Developer options for module authors and debugging.")
        ui.Spacing()

        -- Framework debug gates framework-owned warnings such as discovery, hash import,
        -- and framework-managed apply/revert failures.
        -- Load-time schema validation lives in Lib.
        -- Read/write directly from config — intentional exception to the staging pattern.
        -- These flags have no external writers (no profile load),
        -- so staging would add complexity with no correctness benefit.
        -- lib.config.DebugMode is shared across packs: direct reads reflect changes from
        -- other pack Dev tabs immediately, whereas staging would go stale.
        local fwVal, fwChg = ui.Checkbox("Framework Debug", config.DebugMode == true)
        if fwChg then
            config.DebugMode = fwVal
        end
        if ui.IsItemHovered() then
            ui.SetTooltip(
            "Print framework diagnostics for discovery, hash parsing, and apply/revert failures.")
        end

        local libVal, libChg = ui.Checkbox("Lib Debug", lib.config.DebugMode == true)
        if libChg then
            lib.config.DebugMode = libVal
        end
        if ui.IsItemHovered() then
            ui.SetTooltip(
            "Print lib-internal diagnostic warnings (schema errors, unknown field types). Shared across all packs.")
        end

        if ui.Button("Audit + Resync UI State") then
            AuditAndResyncAllUiState()
        end

        DrawColoredText(colors.info, "Per-Module Debug")
        ui.Spacing()

        -- Regular modules grouped by category (same order as sidebar)
        for _, cat in ipairs(discovery.categories) do
            local modules = discovery.byCategory[cat.key] or {}
            if #modules > 0 then
                PushTextColor(colors.info)
                local open = ui.CollapsingHeader(cat.label, ImGuiTreeNodeFlags.DefaultOpen)
                ui.PopStyleColor()
                if open then
                    ui.Indent()
                    for _, m in ipairs(modules) do
                        local val, chg = ui.Checkbox(m._debugLabel, staging.debug[m.id])
                        if chg then
                            staging.debug[m.id] = val
                            discovery.setDebugEnabled(m, val)
                        end
                    end
                    ui.Unindent()
                    ui.Spacing()
                end
            end
        end

        -- Special modules
        if #discovery.specials > 0 then
            PushTextColor(colors.info)
            local open = ui.CollapsingHeader("Specials", ImGuiTreeNodeFlags.DefaultOpen)
            ui.PopStyleColor()
            if open then
                ui.Indent()
                for _, special in ipairs(discovery.specials) do
                    local val, chg = ui.Checkbox(special._debugLabel, staging.debug[special.modName])
                    if chg then
                        staging.debug[special.modName] = val
                        discovery.setDebugEnabled(special, val)
                    end
                end
                ui.Unindent()
            end
        end
    end

    -- =============================================================================
    -- CATEGORY LABEL LOOKUP
    -- =============================================================================

    local categoryKeyByLabel = {}
    for _, cat in ipairs(discovery.categories) do
        categoryKeyByLabel[cat.label] = cat.key
    end

    -- =============================================================================
    -- MAIN WINDOW
    -- =============================================================================

    local function DrawMainWindow()
        -- Read from staging, not Chalk
        local val, chg = ui.Checkbox("Enable Mod", staging.ModEnabled)
        if chg then
            SetPackRuntimeState(val)
        end
        if ui.IsItemHovered() then ui.SetTooltip("Toggle the entire modpack on or off.") end

        if not staging.ModEnabled then
            ui.Separator()
            DrawColoredText(colors.warning, "Mod is currently disabled. All changes have been reverted.")
            return
        end

        ui.Spacing()
        ui.Separator()
        ui.Spacing()

        local tabs = BuildTabList()
        local totalW = ui.GetWindowWidth()
        local sidebarW = totalW * SIDEBAR_RATIO

        -- Sidebar (proportional width, fill remaining height)
        ui.BeginChild("Sidebar", sidebarW, 0, true)
        for _, tabName in ipairs(tabs) do
            if ui.Selectable(tabName, selectedTab == tabName) then
                selectedTab = tabName
            end
        end
        ui.EndChild()

        ui.SameLine()

        -- Content panel (0 height = fill remaining space)
        ui.BeginChild("TabContent", 0, 0, true)
        ui.Spacing()

        if selectedTab == "Quick Setup" then
            DrawQuickSetup()
        elseif selectedTab == "Profiles" then
            DrawProfiles()
        elseif selectedTab == "Dev" then
            DrawDev()
        elseif specialByTabLabel[selectedTab] then
            -- Special module tab
            DrawSpecialTab(specialByTabLabel[selectedTab])
        else
            -- Dynamic category tab
            local catKey = categoryKeyByLabel[selectedTab]
            if catKey and discovery.categoryLayouts[catKey] then
                DrawCheckboxGroup(discovery.categoryLayouts[catKey])
            end
        end

        ui.EndChild()
    end

    -- =============================================================================
    -- RETURNED API
    -- =============================================================================

    local _showModWindow = false

    local function renderWindow()
        if _showModWindow then
            PushTheme()
            if ui.Begin(windowTitle, true) then
                DrawMainWindow()
                ui.End()
            else
                _showModWindow = false
            end
            PopTheme()
        end
    end

    local function addMenuBar()
        if ui.MenuItem("Show Mod Menu") then
            _showModWindow = not _showModWindow
        end
    end

    return { renderWindow = renderWindow, addMenuBar = addMenuBar }
end
