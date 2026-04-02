-- =============================================================================
-- UI THEME & LAYOUT CONSTANTS
-- =============================================================================
-- Purely declarative — no runtime dependencies.
-- Exposes Framework.createTheme() — called once per coordinator.

--- Create the shared theme/layout constants used by the Framework UI and HUD.
--- @return table theme Theme object exposing colors, ImGui flags, layout ratios, and push/pop helpers.
function Framework.createTheme()
    local ui                 = rom.ImGui
    local uiCol              = rom.ImGuiCol

    -- -------------------------------------------------------------------------
    -- COLORS
    -- -------------------------------------------------------------------------

    local colors             = {
        text          = { 0.92, 0.90, 0.95, 1.0 },
        textDisabled  = { 0.45, 0.40, 0.55, 1.0 },
        info          = { 0.90, 0.75, 0.20, 1.0 },
        warning       = { 0.85, 0.20, 0.25, 1.0 },
        success       = { 0.30, 0.85, 0.55, 1.0 },
        error         = { 0.90, 0.35, 0.50, 1.0 },
        mixed         = { 0.30, 0.70, 0.90, 1.0 },

        windowBg      = { 0.08, 0.06, 0.12, 0.95 },
        childBg       = { 0.10, 0.08, 0.15, 0.90 },
        header        = { 0.28, 0.18, 0.45, 1.0 },
        headerHover   = { 0.38, 0.25, 0.58, 1.0 },
        headerActive  = { 0.45, 0.30, 0.65, 1.0 },
        button        = { 0.30, 0.20, 0.48, 1.0 },
        buttonHover   = { 0.40, 0.28, 0.60, 1.0 },
        buttonActive  = { 0.50, 0.35, 0.70, 1.0 },
        frameBg       = { 0.14, 0.10, 0.22, 1.0 },
        frameBgHover  = { 0.20, 0.15, 0.30, 1.0 },
        frameBgActive = { 0.25, 0.18, 0.38, 1.0 },
        checkMark     = { 0.75, 0.55, 1.00, 1.0 },
        tab           = { 0.18, 0.12, 0.28, 1.0 },
        tabHover      = { 0.35, 0.22, 0.52, 1.0 },
        tabActive     = { 0.40, 0.28, 0.60, 1.0 },
        separator     = { 0.30, 0.20, 0.45, 0.6 },
        border        = { 0.25, 0.18, 0.38, 0.5 },
    }

    -- -------------------------------------------------------------------------
    -- IMGUI FLAG CONSTANTS
    -- -------------------------------------------------------------------------

    local ImGuiTreeNodeFlags = {
        None                 = 0,
        Selected             = 1,
        Framed               = 2,
        AllowOverlap         = 4,
        NoTreePushOnOpen     = 8,
        NoAutoOpenOnLog      = 16,
        DefaultOpen          = 32,
        OpenOnDoubleClick    = 64,
        OpenOnArrow          = 128,
        Leaf                 = 256,
        Bullet               = 512,
        FramePadding         = 1024,
        SpanAvailWidth       = 2048,
        SpanFullWidth        = 4096,
        NavLeftJumpsBackHere = 8192,
        CollapsingHeader     = 26, -- Framed | NoTreePushOnOpen | NoAutoOpenOnLog
    }

    -- -------------------------------------------------------------------------
    -- LAYOUT PROPORTIONS
    -- -------------------------------------------------------------------------

    local SIDEBAR_RATIO      = 0.2 -- sidebar takes 20% of window
    local FIELD_MEDIUM       = 0.5 -- combos, hash inputs
    local FIELD_NARROW       = 0.3 -- short inputs (name, slot selector)
    local FIELD_WIDE         = 0.85 -- long text (tooltip)

    local themeColors        = {
        { uiCol.Text,           colors.text },
        { uiCol.TextDisabled,   colors.textDisabled },
        { uiCol.WindowBg,       colors.windowBg },
        { uiCol.ChildBg,        colors.childBg },
        { uiCol.Header,         colors.header },
        { uiCol.HeaderHovered,  colors.headerHover },
        { uiCol.HeaderActive,   colors.headerActive },
        { uiCol.Button,         colors.button },
        { uiCol.ButtonHovered,  colors.buttonHover },
        { uiCol.ButtonActive,   colors.buttonActive },
        { uiCol.FrameBg,        colors.frameBg },
        { uiCol.FrameBgHovered, colors.frameBgHover },
        { uiCol.FrameBgActive,  colors.frameBgActive },
        { uiCol.CheckMark,      colors.checkMark },
        { uiCol.Tab,            colors.tab },
        { uiCol.TabHovered,     colors.tabHover },
        { uiCol.TabActive,      colors.tabActive },
        { uiCol.Separator,      colors.separator },
        { uiCol.Border,         colors.border },
        { uiCol.TitleBgActive,  colors.header },
    }

    local function PushTheme()
        for _, entry in ipairs(themeColors) do
            ui.PushStyleColor(entry[1], table.unpack(entry[2]))
        end
    end

    local function PopTheme()
        ui.PopStyleColor(#themeColors)
    end

    return {
        colors             = colors,
        ImGuiTreeNodeFlags = ImGuiTreeNodeFlags,
        SIDEBAR_RATIO      = SIDEBAR_RATIO,
        FIELD_MEDIUM       = FIELD_MEDIUM,
        FIELD_NARROW       = FIELD_NARROW,
        FIELD_WIDE         = FIELD_WIDE,
        PushTheme          = PushTheme,
        PopTheme           = PopTheme,
    }
end
