-- =============================================================================
-- ADAMANT-MODPACK-FRAMEWORK
-- =============================================================================
-- Reusable modpack orchestration library: discovery, hash, HUD, and UI.
--
-- Usage (from a coordinator mod's main.lua):
--
--   local Framework = rom.mods['adamant-ModpackFramework']
--   Framework.init({
--       packId      = "h2-modpack",
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
    discovery.run()

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

--- Returns a stable imgui render callback for the given packId.
--- Call once at startup; the callback late-binds to the current pack instance.
public.getRenderer = function(packId)
    return function() _packs[packId].ui.renderWindow() end
end

--- Returns a stable menu bar callback for the given packId.
--- Call once at startup; the callback late-binds to the current pack instance.
public.getMenuBar = function(packId)
    return function() _packs[packId].ui.addMenuBar() end
end
