-- books.lua -- which books the "Continue reading" cards show.
--
-- Pure: the caller passes the files and a function reading each book's
-- state, so the choice can be tested without KOReader.
--
-- The first card is the last book opened, whatever its state (as KOReader's
-- "Open last document"). The others are the next books of the reading
-- history still being read: started, not finished, not set aside ("on
-- hold" or "finished" in the book's status).

local Books = {}

Books.CHOICES = { 1, 2, 3 }
Books.DEFAULT = 1

-- History entries looked at, at most: each one costs a read of the book's
-- settings file, which is slow on the device.
Books.MAX_LOOKED = 10

function Books.count(setting)
    for _i, n in ipairs(Books.CHOICES) do
        if setting == n then return n end
    end
    return Books.DEFAULT
end

-- A book being read: started, not done, not set aside.
function Books.inProgress(b)
    if b.status == "complete" or b.status == "abandoned" then return false end
    return b.percent ~= nil and b.percent > 0 and b.percent < 1
end

-- last: the last file opened, or nil. history: files, most recent first.
-- info(file): the book's { file, title, authors, percent, status }, or nil
-- when the file is gone. n: how many books at most.
function Books.pick(last, history, n, info)
    local books, seen = {}, {}
    if last then
        seen[last] = true
        local b = info(last)
        if b then books[1] = b end
    end
    local looked = 0
    for _i, file in ipairs(history) do
        if #books >= n or looked >= Books.MAX_LOOKED then break end
        if not seen[file] then
            seen[file] = true
            looked = looked + 1
            local b = info(file)
            if b and Books.inProgress(b) then books[#books + 1] = b end
        end
    end
    return books
end

return Books
