-- layout.lua -- grid arithmetic for the dashboard: how many tile columns fit,
-- and how category sections are cut into pages.
--
-- Pure logic in pixels, no KOReader dependency; main.lua measures the real
-- widgets and passes the heights in.

local Layout = {}

-- Number of tile columns for a grid `width` wide: as many tiles at least
-- `min_tile_w` wide as fit, clamped to [min_cols, max_cols].
function Layout.columns(width, min_tile_w, min_cols, max_cols)
    local n = math.floor(width / math.max(1, min_tile_w))
    return math.max(min_cols or 2, math.min(max_cols or 3, n))
end

-- Cut sections into pages.
--   sections     { { count = <games in section> , ... }, ... }
--   cols         tiles per row
--   first_avail  grid height available on page 1 (it also holds the reading
--                and resume/daily cards in portrait)
--   avail        grid height on every following page
--   header_h     height of a section header (0 when not grouped)
--   row_h        height of one row of tiles, gaps included
-- Returns a list of pages; each page is a list of blocks
--   { section = <index>, first = <first game index>, last = <last index> }.
-- A section is split between rows, never inside a row, and a block that
-- continues on the next page repeats its header there. Page 1 may hold no
-- block at all when the cards leave no room; the result always has at least
-- one page.
function Layout.paginate(sections, cols, first_avail, avail, header_h, row_h)
    local pages = { {} }
    local left = first_avail
    local function new_page()
        pages[#pages + 1] = {}
        left = avail
    end
    for si, s in ipairs(sections) do
        local rows = math.ceil((s.count or 0) / cols)
        local row = 1
        while row <= rows do
            -- Room for the header plus at least one row?
            local fit = math.floor((left - header_h) / row_h)
            if fit < 1 then
                -- Nothing fits here. If this is already an empty fresh page,
                -- force one row so a tiny screen still makes progress.
                if #pages[#pages] == 0 and left == avail then
                    fit = 1
                else
                    new_page()
                    fit = math.max(1, math.floor((left - header_h) / row_h))
                end
            end
            local take = math.min(fit, rows - row + 1)
            local page = pages[#pages]
            page[#page + 1] = {
                section = si,
                first   = (row - 1) * cols + 1,
                last    = math.min(s.count, (row + take - 1) * cols),
            }
            left = left - header_h - take * row_h
            row = row + take
        end
    end
    return pages
end

-- Clamp a page index into [1, n].
function Layout.clampPage(page, n)
    if n < 1 then return 1 end
    return math.max(1, math.min(n, page or 1))
end

return Layout
