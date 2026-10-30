-- categories.lua -- which shelf each game sits on in the dashboard grid.
--
-- Generated once (2026-10-30) from the fleet-wide categories.json; this file
-- is now the source of truth -- add a new game's id to BY_ID by hand. Category
-- ids are stable; labels are English and go through _() in main.lua, the
-- French lives in i18n_fr.lua. A game missing from this table (a plugin
-- newer than this file) lands in "other", which always sorts last.
--
-- Pure data, no KOReader dependency, so the specs can load it directly.

local Categories = {}

-- Display order of the shelves. "other" is appended for unknown games.
Categories.ORDER = {
    "logic",
    "sudoku",
    "words",
    "board",
    "cards",
    "classic",
    "party",
    "tools",
    "other",
}

-- English labels (translated by the caller).
Categories.LABELS = {
    logic    = "Logic puzzles",
    sudoku   = "Sudoku",
    words    = "Word games",
    board    = "Board games",
    cards    = "Card & dice games",
    classic  = "Classic puzzles",
    party    = "Party & quiz",
    tools    = "Utilities",
    other    = "Other",
}

-- plugin id -> category id
Categories.BY_ID = {
    aquarium = "logic", balance = "logic", binairo = "logic",
    bridges = "logic", cave = "logic", colornonogram = "logic",
    dominosa = "logic", fillomino = "logic", futoshiki = "logic",
    galaxies = "logic", heyawake = "logic", hidato = "logic",
    hitori = "logic", kakuro = "logic", kenken = "logic", lightup = "logic",
    lits = "logic", magnets = "logic", masyu = "logic", mosaic = "logic",
    netwalk = "logic", nonogram = "logic", norinori = "logic",
    numberlink = "logic", numbrix = "logic", nurikabe = "logic",
    rippleeffect = "logic", shikaku = "logic", signpost = "logic",
    skyscraper = "logic", slitherlink = "logic", starbattle = "logic",
    suguru = "logic", tapa = "logic", tatami = "logic", tents = "logic",
    tracks = "logic",
    arrowsudoku = "sudoku", betweenlines = "sudoku",
    sandwichsudoku = "sudoku", sudoku = "sudoku", sudokukiller = "sudoku",
    sudokux = "sudoku", thermosudoku = "sudoku", windoku = "sudoku",
    anagram = "words", arrowwords = "words", boggle = "words",
    cryptogram = "words", hangman = "words", numletters = "words",
    spellingbee = "words", wordladder = "words", wordle = "words",
    wordsearch = "words",
    awale = "board", backgammon = "board", battleship = "board",
    checkers = "board", chess = "board", chesscourse = "board",
    connect4 = "board", dotsandboxes = "board", go = "board",
    gomoku = "board", hex = "board", morris = "board", othello = "board",
    tsumego = "board",
    dice = "cards", farkle = "cards", pickomino = "cards",
    solitaire = "cards", yahtzee = "cards",
    ["2048"] = "classic", fifteen = "classic", hanoi = "classic",
    lightsout = "classic", mastermind = "classic", memory = "classic",
    mentalmath = "classic", minesweeper = "classic", sokoban = "classic",
    boggleparty = "party", doubleornothing = "party", pictionary = "party",
    quiz = "party", taboo = "party",
    dashboard = "tools", opdsdir = "tools", pluginmanager = "tools",
    startmenu = "tools",
}

function Categories.of(id)
    return Categories.BY_ID[id] or "other"
end

-- Position of a category in ORDER (unknown ids sort after "other").
local RANK = {}
for i, c in ipairs(Categories.ORDER) do RANK[c] = i end
function Categories.rank(cat)
    return RANK[cat] or (#Categories.ORDER + 1)
end

return Categories
