-- startup.lua -- when the dashboard shows itself, and where that setting
-- comes from on a device that already had dashboard or startmenu settings.
--
-- Pure logic, no KOReader dependency.
--
-- KOReader builds a new plugin instance for every FileManager and every
-- ReaderUI -- and FileManager is torn down and rebuilt each time a book
-- closes. So "at launch only" cannot be an instance field: main.lua keeps a
-- module-level flag, which survives because PluginLoader:loadPlugins() caches
-- the loaded modules and dofile()s main.lua once per process.

local Startup = {}

Startup.LAUNCH      = "launch"       -- first file browser of this KOReader run
Startup.FILEMANAGER = "filemanager"  -- every time the file browser opens
Startup.NEVER       = "never"

Startup.DEFAULT = Startup.LAUNCH

local VALID = { launch = true, filemanager = true, never = true }

function Startup.isValid(mode)
    return VALID[mode] == true
end

-- Should this plugin instance show the dashboard on its own?
--   mode          the startup_mode setting
--   has_document  true for a ReaderUI instance (a book is open)
--   first_in_run  true for the first dashboard instance of this KOReader
--                 process, whatever its kind. KOReader started straight into
--                 a book ("start with last file") has used up its launch:
--                 closing that book later is not a launch.
function Startup.shouldShow(mode, has_document, first_in_run)
    if has_document then return false end
    if mode == Startup.FILEMANAGER then return true end
    if mode == Startup.NEVER then return false end
    -- LAUNCH, and anything unrecognised falls back to the default.
    return first_in_run == true
end

-- The startup mode to use, resolved once and then saved as startup_mode.
--   dash_mode       dashboard's startup_mode, if already set
--   dash_legacy     dashboard's former boolean show_on_startup (nil = never
--                   touched; it was only ever written by its toggle)
--   startmenu       startmenu's settings table ({ enabled = ... }), or nil
--                   when startmenu was never installed/run
-- Rules:
--   1. an existing startup_mode wins;
--   2. a startmenu user had a startup screen unless they switched it off
--      (its `enabled` defaulted to true); dashboard replaces it, so they keep
--      one -- at launch, the default, rather than after every book. If they
--      had switched startmenu off and never turned dashboard's on: never;
--   3. otherwise an explicit "Show at startup" off means never;
--   4. otherwise the default (at launch).
function Startup.resolveMode(dash_mode, dash_legacy, startmenu)
    if Startup.isValid(dash_mode) then return dash_mode end
    if type(startmenu) == "table" then
        if startmenu.enabled == false and dash_legacy ~= true then
            return Startup.NEVER
        end
        return Startup.DEFAULT
    end
    if dash_legacy == false then return Startup.NEVER end
    return Startup.DEFAULT
end

return Startup
