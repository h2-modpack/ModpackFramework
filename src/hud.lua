-- =============================================================================
-- HUD SYSTEM: Mod Mark Display
-- =============================================================================
-- Manages the modpack fingerprint display on the HUD.
-- Hash logic lives in hash.lua (via the hash parameter).
-- Displays the short fingerprint (base62 checksum) of the canonical config string.
--
-- Multiple packs stack vertically: each pack's component is named
-- "ModpackMark_<packId>" and offset by packIndex * 24px.

--- Create the HUD subsystem for one coordinator pack.
--- @param packId string Pack identifier used for component naming.
--- @param packIndex number Stable vertical stacking index for this pack.
--- @param hash table Hash subsystem returned by `Framework.createHash(...)`.
--- @param theme table Theme object returned by `Framework.createTheme(...)`.
--- @param config table Coordinator config table containing `ModEnabled`.
--- @param modutil table ModUtil mod reference used for the HUD hook registration.
--- @return table hud HUD object exposing marker/hash update helpers.
function Framework.createHud(packId, packIndex, hash, theme, config, modutil)
    assert(ScreenData and ScreenData.HUD and ScreenData.HUD.ComponentData,
        "Framework.createHud: game HUD globals are not ready; call Framework.init after game load")

    local HUD_LINE_HEIGHT = 24
    local componentName = "ModpackMark_" .. packId

    -- =============================================================================
    -- HUD MARK
    -- =============================================================================

    local _, initFingerprint = hash.GetConfigHash()
    local currentHash = config.ModEnabled and initFingerprint or ""
    local displayedHash = nil

    ScreenData.HUD.ComponentData[componentName] = {
        RightOffset = 20,
        Y = 250 + (packIndex - 1) * HUD_LINE_HEIGHT,
        TextArgs = {
            Text = "",
            Font = "MonospaceTypewriterBold",
            FontSize = 18,
            Color = theme.colors.text,
            ShadowRed = 0.1,
            ShadowBlue = 0.1,
            ShadowGreen = 0.1,
            OutlineColor = { 0.113, 0.113, 0.113, 1 },
            OutlineThickness = 2,
            ShadowAlpha = 1.0,
            ShadowBlur = 1,
            ShadowOffset = { 0, 4 },
            Justification = "Right",
            VerticalJustification = "Top",
            DataProperties = { OpacityWithOwner = true },
        },
    }

    local function UpdateModMark()
        if not HUDScreen or not HUDScreen.Components[componentName] then return end
        if currentHash == displayedHash then return end

        if currentHash == "" then
            ModifyTextBox({ Id = HUDScreen.Components[componentName].Id, ClearText = true })
        else
            ModifyTextBox({ Id = HUDScreen.Components[componentName].Id, Text = currentHash })
        end
        displayedHash = currentHash
    end

    modutil.mod.Path.Wrap("ShowHealthUI", function(base, args)
        base(args)
        if config.ModEnabled then
            displayedHash = nil
            UpdateModMark()
        end
    end)

    -- =============================================================================
    -- PUBLIC API
    -- =============================================================================

    local function updateHash()
        local _, fingerprint = hash.GetConfigHash()
        currentHash = fingerprint
        UpdateModMark()
    end

    local function setModMarker(enabled)
        if enabled then
            local _, fingerprint = hash.GetConfigHash()
            currentHash = fingerprint
        else
            currentHash = ""
        end
        displayedHash = nil
        UpdateModMark()
    end

    return {
        setModMarker    = setModMarker,
        updateHash      = updateHash,
        getConfigHash   = hash.GetConfigHash,
        applyConfigHash = hash.ApplyConfigHash,
    }
end
