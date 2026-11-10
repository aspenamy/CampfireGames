-------------------------------------------------------------------------------
-- Campfire Games: core
--
-- Saved data, sounds, scores and the list of games. Each game file calls
-- ns.RegisterGame{...}; Window.lua builds the window and the game menu.
--
-- A game looks like:
--   ns.RegisterGame({
--     key    = "sudoku",            -- saved data key, never change it
--     name   = "Sudoku",
--     blurb  = "Fill the grid with 1 to 9.",
--     icon   = ns.MEDIA .. "icons\\sudoku",
--     order  = 10,                  -- place in the menu
--     Create = function(panel, data) end, -- build once; panel is ns.GAME_W x ns.GAME_H
--     OnShow = function() end,      -- optional, game opened
--     OnHide = function() end,      -- optional, game closed or window hidden
--     OnKey  = function(key) return handled end, -- optional, see ns.WantKeys
--     Summary = function(data) return "Best 3:12" end, -- optional, menu line
--   })
-- `data` is the game's own saved table (plain values and tables only).
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

ns.TITLE = "Campfire Games"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"

-- Size of the area each game draws into.
ns.GAME_W, ns.GAME_H = 320, 430
ns.DEFAULT_SCALE = 1

ns.games = {}       -- in menu order
ns.gamesByKey = {}

function ns.RegisterGame(game)
  assert(type(game.key) == "string" and game.Create, "game needs key and Create")
  game.order = game.order or 100
  ns.gamesByKey[game.key] = game
  table.insert(ns.games, game)
  table.sort(ns.games, function(a, b) return a.order < b.order end)
end

-------------------------------------------------------------------------------
-- Saved data
-------------------------------------------------------------------------------

local DEFAULTS = {
  scale = 1,          -- drag the corner to change
  sound = true,
  flicker = true,     -- firelight and string lights move a little
  lights = true,      -- string lights under the title bar
  hideInCombat = true,
  minimap = true,     -- show the minimap button
  ambience = false,   -- soft campfire crackle while the window is open
  raidMarks = true,   -- use WoW's raid target marks for colored game pieces
  openFishing = false, -- open the window when you start fishing
  openTaxi = false,    -- open the window on flight paths
  seeThrough = false, -- fade the window while the mouse is elsewhere
  seeThroughAlpha = 0.45,
  minimapAngle = 210,
  lastGame = nil,     -- reopened next time
  games = {},
}

local function FillDefaults(t, d)
  for k, v in pairs(d) do
    if type(v) == "table" then
      if type(t[k]) ~= "table" then t[k] = {} end
      FillDefaults(t[k], v)
    elseif t[k] == nil then
      t[k] = v
    end
  end
end

function ns.LoadDB()
  if type(DowntimeDB) ~= "table" then DowntimeDB = {} end
  FillDefaults(DowntimeDB, DEFAULTS)
  ns.db = DowntimeDB
end

-- The saved table for one game, created on first use.
function ns.GameData(key)
  local g = ns.db.games[key]
  if type(g) ~= "table" then
    g = {}
    ns.db.games[key] = g
  end
  if type(g.stats) ~= "table" then
    g.stats = { played = 0, won = 0, streak = 0, bestStreak = 0 }
  end
  return g
end

-------------------------------------------------------------------------------
-- Scores
--
-- ns.RecordResult(key, { won = true/false/nil, score = n, time = seconds,
--   lowerIsBetter = true (for times/moves), bestKey = "best_hard" })
-- Counts the game as played, keeps win streaks, and saves a best. Returns
-- true when this result is a new best.
-------------------------------------------------------------------------------

function ns.RecordResult(key, r)
  local s = ns.GameData(key).stats
  s.played = (s.played or 0) + 1
  if r.won ~= nil then
    if r.won then
      s.won = (s.won or 0) + 1
      s.streak = (s.streak or 0) + 1
      if s.streak > (s.bestStreak or 0) then s.bestStreak = s.streak end
    else
      s.streak = 0
    end
  end
  local value = r.score or r.time
  if value == nil or r.won == false then return false end
  local bk = r.bestKey or "best"
  local old = s[bk]
  local better
  if old == nil then
    better = true
  elseif r.lowerIsBetter then
    better = value < old
  else
    better = value > old
  end
  if better then s[bk] = value end
  return better and old ~= nil
end

function ns.FormatTime(sec)
  sec = math.floor(sec or 0)
  local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
  if h > 0 then return format("%d:%02d:%02d", h, m, s) end
  return format("%d:%02d", m, s)
end

-- 12345 -> "12,345"
function ns.FormatNumber(n)
  local s = tostring(math.floor(n or 0))
  local neg = s:sub(1, 1) == "-"
  if neg then s = s:sub(2) end
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return (neg and "-" or "") .. out
end

-------------------------------------------------------------------------------
-- Sounds (quiet, built-in UI sounds only)
-------------------------------------------------------------------------------

local SOUNDS = {
  click  = "IG_MAINMENU_OPTION_CHECKBOX_ON",
  place  = "U_CHAT_SCROLL_BUTTON",
  open   = "IG_MAINMENU_OPEN",
  close  = "IG_MAINMENU_CLOSE",
  win    = "UI_QUEST_COMPLETE",   -- falls back below if missing
  good   = "IG_QUEST_LIST_SELECT",
  bad    = "IG_PLAYER_INVITE_DECLINE",
  page   = "IG_ABILITY_PAGE_TURN",
  coin   = "LOOTWINDOWCOINSOUND",
}
local FALLBACK = { win = "IG_QUEST_LIST_COMPLETE", coin = "IG_BACKPACK_COIN_SELECT" }

function ns.Sound(name)
  if not ns.db or not ns.db.sound or not SOUNDKIT then return end
  local id = SOUNDKIT[SOUNDS[name] or ""] or SOUNDKIT[FALLBACK[name] or ""]
  if id then PlaySound(id, "SFX") end
end

-- Our own soft tones in media/sounds (bell1-bell4, wrong, chime, and the
-- Fireflies glow1-glow4 and shimmer).
function ns.PlayTone(name)
  if not ns.db or not ns.db.sound then return end
  PlaySoundFile(ns.MEDIA .. "sounds" .. "\\" .. name .. ".ogg", "SFX")
end

-------------------------------------------------------------------------------
-- Keyboard
--
-- A game calls ns.WantKeys(true) while it wants key presses (e.g. a Sudoku
-- cell is selected) and gets them in game.OnKey(key), returning true for
-- keys it used. Unused keys go on to the game as normal. Keys are never
-- caught in combat.
-------------------------------------------------------------------------------

ns.keysWanted = false

function ns.WantKeys(on)
  ns.keysWanted = on and true or false
  if ns.UpdateKeyboard then ns.UpdateKeyboard() end
end

-------------------------------------------------------------------------------
-- Raid target marks as game pieces
--
-- ns.RAID_MARKS[i] = texture for mark i (1 star, 2 circle, 3 diamond,
-- 4 triangle, 5 moon, 6 square, 7 cross, 8 skull). ns.PIECE_MARKS lists six
-- marks with clearly different colors and shapes, for games with six
-- kinds of pieces. ns.UseRaidMarks() says whether the option is on.
-------------------------------------------------------------------------------

ns.RAID_MARKS = {}
for i = 1, 8 do
  ns.RAID_MARKS[i] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i
end
ns.RAID_MARK_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
ns.PIECE_MARKS = { 7, 6, 4, 1, 3, 2 }  -- red, blue, green, yellow, purple, orange

function ns.UseRaidMarks()
  return ns.db and ns.db.raidMarks and true or false
end

-- Games that swap art when the option changes register a refresh here.
ns.pieceListeners = {}
function ns.OnPiecesChanged(fn)
  table.insert(ns.pieceListeners, fn)
end
function ns.PiecesChanged()
  for _, fn in ipairs(ns.pieceListeners) do pcall(fn) end
end

-------------------------------------------------------------------------------
-- Little helpers games share
-------------------------------------------------------------------------------

function ns.Shuffle(t)
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

function ns.CopyList(t)
  local out = {}
  for i = 1, #t do out[i] = t[i] end
  return out
end
