-- Relative-time and duration formatting for the dashboard rows.
--
-- Kept out of main.lua so it can be exercised without KOReader: everything
-- here is arithmetic on a timestamp, and the boundaries between "just now",
-- minutes, hours, days and a plain date are exactly where an off-by-one hides.

local _ = require("i18n")
local T = require("ffi/util").template

local Format = {}

-- Human-readable age of a timestamp. `now` is injectable so callers (and
-- tests) can ask about a fixed instant; it defaults to the current time.
function Format.reltime(ts, now)
    if not ts then return "?" end
    local d = (now or os.time()) - ts
    if d < 120        then return _("just now")
    elseif d < 3600   then return T(_("%1 min"), math.floor(d / 60))
    elseif d < 86400  then return T(_("%1 h"),   math.floor(d / 3600))
    elseif d < 604800 then return T(_("%1 d"),   math.floor(d / 86400))
    else                   return os.date(_.lang() == "fr" and "%d/%m/%Y" or "%Y-%m-%d", ts)
    end
end

-- A play time, as "2h05" or "45m". Anything under a minute reads "0m" rather
-- than showing seconds, which would only ever be noise on this screen.
function Format.fmt_seconds(secs)
    secs = math.floor(secs or 0)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return string.format("%dh%02d", h, m) end
    return string.format("%dm", m)
end

return Format
