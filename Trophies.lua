-------------------------------------------------------------------------------
-- Campfire Games: trophies
--
-- Small milestones across the games. They're checked after every result
-- (ns.RecordResult) and once a minute for time-by-the-fire ones. Earned
-- trophies are kept in DowntimeDB.trophies[id] = time earned.
-------------------------------------------------------------------------------

local _, ns = ...

local function S(key)
  local g = ns.db.games[key]
  return (g and g.stats) or {}
end

local function G(key)
  return ns.db.games[key] or {}
end

local function TotalPlayed()
  local n = 0
  for _, g in pairs(ns.db.games) do
    if type(g) == "table" and type(g.stats) == "table" then n = n + (g.stats.played or 0) end
  end
  return n
end

local function Low(...)  -- smallest of the given values that exist
  local best
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "number" and (not best or v < best) then best = v end
  end
  return best
end

local function High(...)
  local best
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "number" and (not best or v > best) then best = v end
  end
  return best
end

-- { id, game key (for the icon) or nil, name, how to earn it, check }
ns.TROPHIES = {
  { "chair", nil, "Pull Up a Chair", "Play any game.", function() return TotalPlayed() >= 1 end },
  { "regular", nil, "A Regular", "Play 50 games.", function() return TotalPlayed() >= 50 end },
  { "furniture", nil, "Part of the Furniture", "Play 250 games.", function() return TotalPlayed() >= 250 end },
  { "warm", nil, "Warm Hands", "Spend an hour by the fire.", function() return (ns.db.timeByFire or 0) >= 3600 end },
  { "longnight", nil, "The Long Night", "Spend ten hours by the fire.", function() return (ns.db.timeByFire or 0) >= 36000 end },
  { "flight", nil, "Tasting Flight", "Play every game at least once.", function()
      for _, g in ipairs(ns.games) do
        if (S(g.key).played or 0) < 1 then return false end
      end
      return true
    end },
  { "allwins", nil, "Jack of All Games", "Win at least once in every game that can be won.", function()
      for _, g in ipairs(ns.games) do
        if g.hasWins and (S(g.key).won or 0) < 1 then return false end
      end
      return true
    end },

  { "sudoku1", "sudoku", "Pencil Pusher", "Solve a Sudoku.", function() return (S("sudoku").won or 0) >= 1 end },
  { "sudoku10", "sudoku", "Ten Minutes Flat", "Solve a Medium Sudoku in under ten minutes.", function() return (S("sudoku").best_medium or 9e9) < 600 end },
  { "sudokuhard", "sudoku", "Hard Graft", "Solve a Hard Sudoku.", function() return S("sudoku").best_hard ~= nil end },
  { "sudokudaily", "sudoku", "Morning Ritual", "Solve the Daily Sudoku seven days in a row.", function() return (G("sudoku").bestDailyStreak or 0) >= 7 end },
  { "sudoku25", "sudoku", "Number Sage", "Solve 25 Sudoku.", function() return (S("sudoku").won or 0) >= 25 end },

  { "gems1", "gems", "First Facet", "Score 1,000 in Gemcutter.", function() return (High(S("gems").best_moves, S("gems").best_relaxed) or 0) >= 1000 end },
  { "gems5", "gems", "Master Jeweler", "Score 5,000 in a 30 Moves game.", function() return (S("gems").best_moves or 0) >= 5000 end },

  { "sol1", "solitaire", "Patience Rewarded", "Win a game of Solitaire.", function() return (S("solitaire").won or 0) >= 1 end },
  { "sol10", "solitaire", "Card Sharp", "Win 10 games of Solitaire.", function() return (S("solitaire").won or 0) >= 10 end },
  { "solfast", "solitaire", "Quick Shuffle", "Win Solitaire in under five minutes.", function() return (Low(S("solitaire").best_draw1, S("solitaire").best_draw3) or 9e9) < 300 end },

  { "dig1", "digsite", "Amateur Archaeologist", "Clear a dig site.", function() return (S("digsite").won or 0) >= 1 end },
  { "diglarge", "digsite", "Grand Excavation", "Clear a Large dig site.", function() return S("digsite").best_large ~= nil end },
  { "dig10", "digsite", "Steady Hands", "Clear 10 dig sites.", function() return (S("digsite").won or 0) >= 10 end },

  { "fly1", "fireflies", "Ring of Light", "Close a loop in Fireflies.", function() return (S("fireflies").loops or 0) >= 1 end },
  { "flydew", "fireflies", "Morning Dew", "Make a dewdrop by linking 8 lights in Fireflies.", function() return (S("fireflies").dews or 0) >= 1 end },
  { "flyseed", "fireflies", "Planting Season", "Collect 10 seeds in Fireflies.", function() return (S("fireflies").seeds or 0) >= 10 end },
  { "fly15", "fireflies", "Keeper of the Lights", "Pass level 15 of Fireflies.", function() return (S("fireflies").best_level or 0) >= 15 end },
  { "fly3k", "fireflies", "Summer Night", "Score 3,000 in a 30 Moves game of Fireflies.", function() return (S("fireflies").best_moves or 0) >= 3000 end },
  { "slider4", "slider", "Picture Perfect", "Solve a 4x4 Sliding Puzzle.", function() return S("slider").best_4 ~= nil end },
  { "slider40", "slider", "Nimble Fingers", "Solve a 3x3 Sliding Puzzle in 40 moves or fewer.", function() return (S("slider").best_3 or 999) <= 40 end },

  { "lan5", "lanterns", "Light in the Dark", "Light Lanterns level 5.", function() return (S("lanterns").best or 0) >= 5 end },
  { "lan15", "lanterns", "Lamplighter", "Light Lanterns level 15.", function() return (S("lanterns").best or 0) >= 15 end },

  { "rune1", "runes", "Lockpick", "Open a rune lock.", function() return (S("runes").won or 0) >= 1 end },
  { "runemaster", "runes", "Master Locksmith", "Open a Master lock.", function() return S("runes").best_master ~= nil end },
  { "rune4", "runes", "Sharp Mind", "Open a lock in four tries or fewer.", function() return (Low(S("runes").best_apprentice, S("runes").best_master) or 99) <= 4 end },

  { "pairs12", "pairs", "Good Memory", "Clear 16 cards in 12 moves or fewer.", function() return (S("pairs").best_16 or 99) <= 12 end },
  { "pairs16", "pairs", "Long Memory", "Clear 20 cards in 16 moves or fewer.", function() return (S("pairs").best_20 or 99) <= 16 end },

  { "quill1", "quill", "Wordsmith", "Find a Quill word.", function() return (S("quill").won or 0) >= 1 end },
  { "quill2", "quill", "Inspired", "Find a Quill word in two guesses.", function() return (S("quill").best or 99) <= 2 end },
  { "quilldaily", "quill", "Word of the Day", "Find the Daily word seven days in a row.", function() return (G("quill").bestDailyStreak or 0) >= 7 end },
  { "quill25", "quill", "Scribe", "Find 25 Quill words.", function() return (S("quill").won or 0) >= 25 end },

  { "tap1", "tapestry", "First Stitch", "Weave a tapestry.", function() return (S("tapestry").won or 0) >= 1 end },
  { "tap10", "tapestry", "Master Weaver", "Weave a 10x10 tapestry.", function() return S("tapestry").best_10 ~= nil end },

  { "ric3", "ricochet", "Brick by Brick", "Reach Ricochet level 3.", function() return (G("ricochet").bestLevel or 0) >= 3 end },
  { "ric10k", "ricochet", "Wall Breaker", "Score 10,000 in Ricochet.", function() return (S("ricochet").best or 0) >= 10000 end },

  { "chime10", "chimes", "Good Ear", "Ring back 10 bells in Chimes.", function() return (High(S("chimes").best_classic, S("chimes").best_gentle) or 0) >= 10 end },
  { "chime20", "chimes", "Bell Ringer", "Ring back 20 bells in Chimes.", function() return (High(S("chimes").best_classic, S("chimes").best_gentle) or 0) >= 20 end },

  { "pegs1", "pegs", "One Peg Left", "Finish Pegs with a single peg.", function() return (S("pegs").won or 0) >= 1 end },
  { "pegscross", "pegs", "Cross Master", "Leave one peg on the Cross board.", function() return (S("pegs").best_cross or 99) <= 1 end },

  { "tea1", "teahouse", "Clear Table", "Clear a table of Teahouse Tiles.", function() return (S("teahouse").won or 0) >= 1 end },
  { "teabig", "teahouse", "Full House", "Clear the big Teahouse layout.", function() return S("teahouse").best_teahouse ~= nil end },
}

local function Earned()
  if type(ns.db.trophies) ~= "table" then ns.db.trophies = {} end
  return ns.db.trophies
end

function ns.TrophyCount()
  local have, total = 0, 0
  local earned = Earned()
  for _, t in ipairs(ns.TROPHIES) do
    if t[2] == nil or ns.gamesByKey[t[2]] then
      total = total + 1
      if earned[t[1]] then have = have + 1 end
    end
  end
  return have, total
end

-- Checks every trophy; announces new ones. `quiet` skips the banner (used at
-- login so old progress is counted without a pile of banners).
function ns.CheckTrophies(quiet)
  if not ns.db then return end
  local earned = Earned()
  for _, t in ipairs(ns.TROPHIES) do
    local id, game = t[1], t[2]
    if not earned[id] and (game == nil or ns.gamesByKey[game]) then
      local ok, got = pcall(t[5])
      if ok and got then
        earned[id] = time()
        if not quiet then
          if ns.ShowTrophyBanner then pcall(ns.ShowTrophyBanner, t) end
          print(format("|cffffd173%s|r: Trophy earned: |cffffffff%s|r", ns.TITLE, t[3]))
        end
      end
    end
  end
end

-- Check right after any result is recorded.
local record = ns.RecordResult
function ns.RecordResult(key, r)
  local newBest = record(key, r)
  ns.CheckTrophies()
  return newBest
end
