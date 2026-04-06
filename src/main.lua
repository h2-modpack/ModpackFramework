-- =============================================================================
-- ADAMANT-MODPACK-FRAMEWORK
-- =============================================================================
-- Reusable modpack orchestration library: discovery, hash, HUD, and UI.
--
-- Usage (from a coordinator mod's main.lua):
--
--   local Framework = rom.mods['adamant-ModpackFramework']
--   Framework.init({
--       packId      = "speedrun",
--       windowTitle = "Speedrun Modpack",
--       config      = config,    -- coordinator's Chalk config
--       def         = def,       -- { NUM_PROFILES, defaultProfiles }
--       modutil     = modutil,
--   })
--
-- Framework.init can be called on every hot reload; subsequent calls update subsystem
-- instances in place. GUI registration is the coordinator's responsibility:
--   rom.gui.add_imgui(Framework.getRenderer(packId))
--   rom.gui.add_to_menu_bar(Framework.getMenuBar(packId))

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
Framework = {}

import 'ui_theme.lua'
import 'discovery.lua'
import 'hash.lua'
import 'hud.lua'
import 'ui.lua'

-- =============================================================================
-- PACK STATE (module-level; survives hot reloads for late-binding)
-- =============================================================================

local _packs    = {} -- packId -> { ui, hud, _index }
local _packList = {} -- ordered list of packIds for HUD Y-offset stacking

local function ValidateInitParams(params, lib)
    assert(type(params) == "table", "Framework.init: params must be a table")
    assert(type(params.packId) == "string" and params.packId ~= "",
        "Framework.init: packId must be a non-empty string")
    assert(type(params.windowTitle) == "string" and params.windowTitle ~= "",
        "Framework.init: windowTitle must be a non-empty string")
    assert(type(params.config) == "table", "Framework.init: config must be a table")
    assert(type(params.def) == "table", "Framework.init: def must be a table")
    assert(type(params.config.ModEnabled) == "boolean",
        "Framework.init: config.ModEnabled must be a boolean")
    assert(type(params.config.DebugMode) == "boolean",
        "Framework.init: config.DebugMode must be a boolean")
    assert(type(params.config.Profiles) == "table",
        "Framework.init: config.Profiles must be a table")

    local numProfiles = params.def.NUM_PROFILES
    assert(type(numProfiles) == "number" and numProfiles > 0 and math.floor(numProfiles) == numProfiles,
        "Framework.init: def.NUM_PROFILES must be a positive integer")
    assert(type(params.def.defaultProfiles) == "table",
        "Framework.init: def.defaultProfiles must be a table")

    for i = 1, numProfiles do
        local profile = params.config.Profiles[i]
        assert(type(profile) == "table",
            string.format(
                "Framework.init: config.Profiles[%d] is missing; ensure config.lua declares all %d profile entries",
                i, numProfiles))
        profile.Name = profile.Name or ""
        profile.Hash = profile.Hash or ""
        profile.Tooltip = profile.Tooltip or ""
    end

    local groupStyleDefault = params.def.groupStyleDefault
    if groupStyleDefault ~= nil and groupStyleDefault ~= "collapsing" and groupStyleDefault ~= "separator" and
        groupStyleDefault ~= "flat" then
        lib.contractWarn(params.packId,
            "Framework.init: unknown groupStyleDefault '%s'; defaulting to 'collapsing'",
            tostring(groupStyleDefault))
        params.def.groupStyleDefault = "collapsing"
    end
end

-- =============================================================================
-- PROFILE AUDIT
-- =============================================================================

--- Scan saved profiles against the current discovered key surface.
--- Warns when a profile contains a field key for a known module or special that
--- no longer exists, indicating a likely rename. Namespaces absent from discovery
--- are skipped silently because "not installed" and "renamed" are indistinguishable.
--- @param packId string Pack identifier used in warnings.
--- @param profiles table Array of saved profile tables `{ Name, Hash, Tooltip }`.
--- @param discovery table Populated discovery object after `discovery.run(...)`.
--- @param lib table Adamant Modpack Lib export.
local function AuditSavedProfiles(packId, profiles, discovery, lib)
    -- Build known storage surface from discovery.
    -- Regular modules: namespace = definition.id, fields = storage root aliases.
    -- Special modules: namespace = modName, fields = storage root aliases.
    local knownModules  = {}  -- [id]      = { [alias] = true }
    local knownSpecials = {}  -- [modName] = { [alias] = true }

    for _, m in ipairs(discovery.modules) do
        local fields = {}
        if m.storage then
            for _, root in ipairs(m.storage) do
                if root._isRoot and root.alias ~= nil then
                    fields[tostring(root.alias)] = true
                end
            end
        end
        knownModules[m.id] = fields
    end

    for _, special in ipairs(discovery.specials) do
        local fields = {}
        if special.storage then
            for _, root in ipairs(special.storage) do
                if root._isRoot and root.alias ~= nil then
                    fields[tostring(root.alias)] = true
                end
            end
        end
        knownSpecials[special.modName] = fields
    end

    -- Scan each saved profile hash.
    for i, profile in ipairs(profiles) do
        local hash = profile.Hash
        if hash and hash ~= "" then
            local profileLabel = (profile.Name ~= "" and profile.Name) or ("slot " .. i)
            for entry in string.gmatch(hash .. "|", "([^|]*)|") do
                local key = string.match(entry, "^([^=]+)=")
                if key and key ~= "_v" then
                    -- "Namespace.fieldKey" or just "Namespace" (enabled-state key)
                    local namespace, field = string.match(key, "^([^.]+)%.(.+)$")
                    if not namespace then
                        namespace = key
                        field = nil
                    end

                    -- Only warn when the namespace is in discovery — skip silently otherwise.
                    if field then
                        local moduleFields  = knownModules[namespace]
                        local specialFields = knownSpecials[namespace]
                        if moduleFields and not moduleFields[field] then
                            lib.contractWarn(packId,
                                "Profile '%s': unrecognized key '%s.%s' — possible rename or removed option",
                                profileLabel, namespace, field)
                        elseif specialFields and not specialFields[field] then
                            lib.contractWarn(packId,
                                "Profile '%s': unrecognized key '%s.%s' — possible rename or removed field",
                                profileLabel, namespace, field)
                        end
                    end
                end
            end
        end
    end
end

Framework.auditSavedProfiles = AuditSavedProfiles

-- =============================================================================
-- FRAMEWORK.INIT
-- =============================================================================

--- Initialize (or reinitialize) a modpack coordinator.
--- Safe to call on every hot reload. GUI registration is the coordinator's responsibility —
--- use Framework.getRenderer(packId) and Framework.getMenuBar(packId) to get stable callbacks.
---
--- @param params table
---   params.packId      string  — discovery filter + HUD component name scoping
---   params.windowTitle string  — ImGui window title
---   params.config      table   — coordinator's Chalk config (ModEnabled, DebugMode, Profiles)
---   params.def         table   — { NUM_PROFILES, defaultProfiles }
---   params.modutil     table   — ModUtil mod reference (for hud Path.Wrap hook)
---
--- @return table pack  — { discovery, hash, hud, ui, _index }
function Framework.init(params)
    local lib = rom.mods['adamant-ModpackLib']
    ValidateInitParams(params, lib)

    -- Register coordinator with lib so modules can resolve packId → config
    -- without coupling to Thunderstore mod IDs.
    lib.registerCoordinator(params.packId, params.config)

    -- Make game globals available to all subsystem closures (SetupRunData, etc.)
    import_as_fallback(rom.game)

    -- Self-register for HUD stacking; preserve index across hot reloads
    local packIndex = _packs[params.packId] and _packs[params.packId]._index or nil
    if not packIndex then
        table.insert(_packList, params.packId)
        packIndex = #_packList
    end

    -- Create fresh subsystems each call (correct dependency order matters)
    local discovery = Framework.createDiscovery(params.packId, params.config, lib)
    local hash      = Framework.createHash(discovery, params.config, lib, params.packId)
    local theme     = Framework.createTheme()

    -- Discovery must run before createHud so GetConfigHash has modules to read
    discovery.run(
        params.def and params.def.groupStyle,
        params.def and params.def.groupStyleDefault,
        params.def and params.def.categoryOrder
    )

    AuditSavedProfiles(params.packId, params.config.Profiles, discovery, lib)

    local hud             = Framework.createHud(params.packId, packIndex, hash, theme, params.config, params.modutil)
    local ui              = Framework.createUI(discovery, hud, theme, params.def, params.config, lib, params.packId,
        params.windowTitle)

    -- Store instances — overwrites on reload; GUI callbacks use late binding
    _packs[params.packId] = { discovery = discovery, hash = hash, hud = hud, ui = ui, _index = packIndex }

    if params.config.ModEnabled then
        hud.setModMarker(true)
    end

    return _packs[params.packId]
end

public.init = Framework.init

--- Group style constants for use in def.groupStyle / def.groupStyleDefault.
public.GroupStyle = {
    COLLAPSING = "collapsing", -- collapsing header (default)
    SEPARATOR  = "separator",  -- labeled section header + separator line, always visible
    FLAT       = "flat",       -- no header, items rendered directly
}


--- Return a stable imgui render callback for the given pack.
--- Call once at startup; the callback late-binds to the current pack instance.
--- @param packId string Pack identifier passed to `Framework.init(...)`.
--- @return function render Callback suitable for `rom.gui.add_imgui(...)`.
public.getRenderer = function(packId)
    return function()
        local pack = _packs[packId]
        if not pack or not pack.ui or type(pack.ui.renderWindow) ~= "function" then
            return
        end
        pack.ui.renderWindow()
    end
end

--- Return a stable menu-bar callback for the given pack.
--- Call once at startup; the callback late-binds to the current pack instance.
--- @param packId string Pack identifier passed to `Framework.init(...)`.
--- @return function addMenuBar Callback suitable for `rom.gui.add_to_menu_bar(...)`.
public.getMenuBar = function(packId)
    return function()
        local pack = _packs[packId]
        if not pack or not pack.ui or type(pack.ui.addMenuBar) ~= "function" then
            return
        end
        pack.ui.addMenuBar()
    end
end
