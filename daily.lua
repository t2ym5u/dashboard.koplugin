-- daily.lua -- which game is today's Daily Challenge, and whether it is done.
--
-- Pure logic, no KOReader dependency. The puzzle itself comes from the game
-- (game-common's DailySeed seeds its generator); this only picks the game.

local Daily = {}

Daily.AUTO = "auto"

-- A day number that goes up by exactly one every local calendar day, so the
-- rotation below never skips or repeats a game at a month or year boundary
-- (year * 1000 + yday, DailySeed.today()'s value, jumps by ~635 on 1 January).
-- `t` is an os.date("*t") table; noon keeps DST shifts away from midnight.
function Daily.dayNumber(t)
    local noon = os.time{ year = t.year, month = t.month, day = t.day, hour = 12 }
    -- Days since 1970-01-01 local noon, independent of the timezone offset.
    local epoch = os.time{ year = 1970, month = 1, day = 2, hour = 12 } - 86400
    return math.floor((noon - epoch) / 86400 + 0.5)
end

-- The pool to pick from: the daily-capable games the player shows on the
-- dashboard, or, when none of those has a daily mode, every daily-capable
-- installed game -- so the tile is never empty just because the player's
-- favourites are all board games. Sorted by id, so the pick does not depend
-- on the filesystem's listing order.
function Daily.candidates(games, shown)
    local fav, all = {}, {}
    for _, g in ipairs(games) do
        if g.daily then
            all[#all + 1] = g
            if shown and shown(g.id) then fav[#fav + 1] = g end
        end
    end
    local pool = #fav > 0 and fav or all
    table.sort(pool, function(a, b) return a.id < b.id end)
    return pool
end

-- Today's game. `chosen` is the daily_game setting: AUTO (or nil) rotates
-- through the pool, one game a day, every game once before any repeats
-- (7919 is a prime larger than any pool, so stepping by it modulo n visits
-- every slot); a game id pins that game while it is installed and daily-
-- capable, and falls back to the rotation otherwise.
function Daily.pick(pool, day, chosen, all_games)
    if chosen and chosen ~= Daily.AUTO then
        for _, g in ipairs(all_games or pool) do
            if g.id == chosen and g.daily then return g end
        end
    end
    local n = #pool
    if n == 0 then return nil end
    return pool[(day * 7919) % n + 1]
end

-- Was today's challenge already launched? `record` is the saved
-- { day = <dayNumber>, id = <game id> }. Tied to the game too: if the player
-- pins another game after launching today's, the new one is not done.
function Daily.isDone(record, day, id)
    return type(record) == "table" and record.day == day and record.id == id
end

return Daily
