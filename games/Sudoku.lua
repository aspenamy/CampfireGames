-------------------------------------------------------------------------------
-- Campfire Games: Sudoku
--
-- Click a cell, then a number. While a cell is selected the keyboard works
-- too: 1-9 to fill, Shift+1-9 for a note, Backspace/Delete to clear, arrow
-- keys to move, Esc to let go. Right-click a cell to clear it.
--
-- "Daily" is one Medium puzzle per calendar day, the same for everyone. It is
-- saved apart from the regular game, and solving it on consecutive days builds
-- a daily streak.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local L = ns.SudokuLogic
local band, bxor, lshift = bit.band, bit.bxor, bit.lshift
local floor = math.floor

local CELL, THIN, THICK = 30, 1, 3
local BOARD = CELL * 9 + THIN * 6 + THICK * 4 -- 288
local MAX_UNDO = 200

local DIFFS = {
  { key = "easy", label = "Easy" },
  { key = "medium", label = "Medium" },
  { key = "hard", label = "Hard" },
  { key = "daily", label = "Daily" },
}
local DIFF_LABEL = { easy = "Easy", medium = "Medium", hard = "Hard" }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local COLOR = {
  line     = { 0.50, 0.38, 0.20 },
  cell     = { 0.13, 0.095, 0.065 },
  peer     = { 0.20, 0.15, 0.10 },
  same     = { 0.33, 0.24, 0.11 },
  selected = { 0.52, 0.37, 0.13 },
  given    = { 0.96, 0.90, 0.78 },
  entered  = { 0.55, 0.78, 1.00 },
  wrong    = { 1.00, 0.42, 0.34 },
  note     = { 0.70, 0.64, 0.54 },
  noteHit  = { 1.00, 0.82, 0.30 },
}

-- saved: data.game (regular), data.daily, data.mode ("daily" or nil),
-- data.dailyStreak, data.bestDailyStreak, data.lastDailyDay,
-- data.showMistakes, data.showTimer
local data
local game          -- the board on show: data.game or data.daily
local mode = "regular"
local undo = {}
local selected
local notesMode = false
local generating
local panel, cells, pad, overlay, toast, timerText, diffText, notesButton, statusText
local newRow

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local function Ints(t, lo, hi)
  if type(t) ~= "table" or #t ~= 81 then return false end
  for i = 1, 81 do
    local v = t[i]
    if type(v) ~= "number" or v < lo or v > hi or v ~= floor(v) then return false end
  end
  return true
end

local function ValidGame(g)
  return type(g) == "table" and DIFF_LABEL[g.difficulty] ~= nil
    and (g.elapsed == nil or type(g.elapsed) == "number")
    and Ints(g.puzzle, 0, 9) and Ints(g.solution, 1, 9)
    and Ints(g.values, 0, 9) and Ints(g.notes, 0, 511)
end

-- Dates. A daily's seed is the date as YYYYMMDD.
local function Today()
  return tonumber(date("%Y%m%d"))
end

local function SeedParts(seed)
  return floor(seed / 10000), floor(seed / 100) % 100, seed % 100
end

-- Days since 1970-01-01 for a civil date (proleptic Gregorian).
local function DaysFromCivil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = floor(y / 400)
  local yoe = y - era * 400
  local doy = floor((153 * (m > 2 and m - 3 or m + 9) + 2) / 5) + d - 1
  local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

local function SeedDay(seed)
  return DaysFromCivil(SeedParts(seed))
end

local function ValidDaily(g)
  if not ValidGame(g) or type(g.seed) ~= "number" or g.seed ~= floor(g.seed) then return false end
  local y, m, d = SeedParts(g.seed)
  return y >= 2000 and y <= 9999 and m >= 1 and m <= 12 and d >= 1 and d <= 31
end

local function DailyLabel(seed)
  local _, m, d = SeedParts(seed)
  return format("Daily, %s %d", MONTHS[m], d)
end

local function Snapshot()
  local v, n = {}, {}
  for i = 1, 81 do v[i], n[i] = game.values[i], game.notes[i] end
  undo[#undo + 1] = { values = v, notes = n }
  if #undo > MAX_UNDO then table.remove(undo, 1) end
end

local function IsSolved()
  for i = 1, 81 do
    if game.values[i] ~= game.solution[i] then return false end
  end
  return true
end

local function Started(g)
  for i = 1, 81 do
    if g.puzzle[i] == 0 and (g.values[i] ~= 0 or g.notes[i] ~= 0) then return true end
  end
  return false
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function IsPeer(a, b)
  return L.ROW[a] == L.ROW[b] or L.COL[a] == L.COL[b] or L.BOX[a] == L.BOX[b]
end

local function UpdateTimer()
  if not game then timerText:SetText("") return end
  timerText:SetShown(data.showTimer)
  timerText:SetText(ns.FormatTime(game.elapsed))
end

local function Render()
  if generating then
    statusText:SetText("Shuffling the numbers...")
    statusText:Show()
  else
    statusText:Hide()
  end
  if not game then return end
  local selDigit = selected and game.values[selected] or 0
  local counts = {}
  for d = 1, 9 do counts[d] = 0 end

  for i = 1, 81 do
    local cell, v = cells[i], game.values[i]
    if v > 0 then counts[v] = counts[v] + 1 end
    local bg
    if i == selected then
      bg = COLOR.selected
    elseif selDigit > 0 and v == selDigit then
      bg = COLOR.same
    elseif selected and IsPeer(i, selected) then
      bg = COLOR.peer
    else
      bg = COLOR.cell
    end
    UI.Color(cell.bg, bg)

    if v > 0 then
      cell.digit:SetText(v)
      local c
      if game.puzzle[i] > 0 then
        c = COLOR.given
      elseif data.showMistakes and v ~= game.solution[i] then
        c = COLOR.wrong
      else
        c = COLOR.entered
      end
      UI.SetTextColor(cell.digit, c)
      for d = 1, 9 do cell.notes[d]:Hide() end
    else
      cell.digit:SetText("")
      local mask = game.notes[i]
      for d = 1, 9 do
        local fs = cell.notes[d]
        if band(mask, lshift(1, d - 1)) ~= 0 then
          UI.SetTextColor(fs, d == selDigit and COLOR.noteHit or COLOR.note)
          fs:Show()
        else
          fs:Hide()
        end
      end
    end
  end

  for d = 1, 9 do
    local b = pad[d]
    local left = 9 - counts[d]
    b.count:SetText(left > 0 and left or "")
    b:SetAlpha(left > 0 and 1 or 0.35)
  end

  diffText:SetText(mode == "daily" and DailyLabel(game.seed) or DIFF_LABEL[game.difficulty] or "")
  notesButton:SetSelected(notesMode)
  notesButton:SetText(notesMode and "Notes: On" or "Notes: Off")
  newRow:Select(mode == "daily" and "daily" or game.difficulty)
  UpdateTimer()
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function Select(i)
  if not game or game.solved or generating then i = nil end
  selected = i
  ns.WantKeys(i ~= nil)
  Render()
end

local function DailyOverlay(title)
  overlay:Open(title, format("%s in %s\nDaily streak: %d\nCome back tomorrow for a new one.",
    DailyLabel(game.seed), ns.FormatTime(game.elapsed), data.dailyStreak or 0))
end

-- Counts consecutive calendar days, by day number rather than by date digits.
local function BumpStreak()
  local day = SeedDay(game.seed)
  local last = data.lastDailyDay
  if last and day <= last then return end
  if last and day - last == 1 then
    data.dailyStreak = (data.dailyStreak or 0) + 1
  else
    data.dailyStreak = 1
  end
  data.lastDailyDay = day
  if data.dailyStreak > (data.bestDailyStreak or 0) then data.bestDailyStreak = data.dailyStreak end
end

local function Win()
  game.solved = true
  local daily = mode == "daily"
  local bestKey = daily and "best_daily" or ("best_" .. game.difficulty)
  local newBest = ns.RecordResult("sudoku", {
    won = true, time = floor(game.elapsed), lowerIsBetter = true, bestKey = bestKey,
  })
  if daily then BumpStreak() end
  ns.Sound("win")
  selected = nil
  ns.WantKeys(false)
  Render()
  local title = newBest and "A new best!" or "Solved!"
  if daily then
    DailyOverlay(title)
  else
    overlay:Open(title, format("%s puzzle in %s\nBest: %s",
      DIFF_LABEL[game.difficulty], ns.FormatTime(game.elapsed), ns.FormatTime(data.stats[bestKey])))
  end
end

local function Enter(d, asNote)
  local i = selected
  if not i or not game or game.solved or generating then return end
  if game.puzzle[i] > 0 then return end

  if asNote or notesMode then
    if game.values[i] ~= 0 then return end
    Snapshot()
    game.notes[i] = bxor(game.notes[i], lshift(1, d - 1))
  else
    Snapshot()
    if game.values[i] == d then
      game.values[i] = 0
    else
      game.values[i] = d
      game.notes[i] = 0
      local bitv = lshift(1, d - 1)
      for _, p in ipairs(L.PEERS[i]) do
        if band(game.notes[p], bitv) ~= 0 then game.notes[p] = game.notes[p] - bitv end
      end
      if data.showMistakes and d ~= game.solution[i] then
        game.mistakes = (game.mistakes or 0) + 1
      end
    end
  end
  ns.Sound("place")
  if IsSolved() then Win() return end
  Render()
end

local function Erase()
  local i = selected
  if not i or not game or game.solved or game.puzzle[i] > 0 then return end
  if game.values[i] == 0 and game.notes[i] == 0 then return end
  Snapshot()
  game.values[i], game.notes[i] = 0, 0
  Render()
end

local function Undo()
  if not game or game.solved or #undo == 0 then return end
  local u = table.remove(undo)
  game.values, game.notes = u.values, u.notes
  Render()
end

local function Move(dr, dc)
  local i = selected or 41
  local r, c = L.ROW[i] - 1, L.COL[i] - 1
  r, c = (r + dr) % 9, (c + dc) % 9
  Select(r * 9 + c + 1)
end

local KEY_DIGIT = {}
for d = 1, 9 do
  KEY_DIGIT[tostring(d)] = d
  KEY_DIGIT["NUMPAD" .. d] = d
end
local KEY_ERASE = { BACKSPACE = true, DELETE = true, ["0"] = true, NUMPAD0 = true }
local KEY_MOVE = { UP = { -1, 0 }, DOWN = { 1, 0 }, LEFT = { 0, -1 }, RIGHT = { 0, 1 } }

local function OnKey(key)
  if not selected then return false end
  if KEY_DIGIT[key] then
    Enter(KEY_DIGIT[key], IsShiftKeyDown())
  elseif KEY_ERASE[key] then
    Erase()
  elseif KEY_MOVE[key] then
    Move(KEY_MOVE[key][1], KEY_MOVE[key][2])
  elseif key == "ESCAPE" then
    Select(nil)
  else
    return false
  end
  return true
end

-------------------------------------------------------------------------------
-- New puzzles, made a little each frame
-------------------------------------------------------------------------------

-- Puts a saved board on show (regular or daily).
local function ShowBoard(g, newMode)
  game, mode = g, newMode
  data.mode = newMode == "daily" and "daily" or nil
  wipe(undo)
  overlay:Close()
  Select(nil)
  if g.solved then
    if newMode == "daily" then
      DailyOverlay("Solved!")
    else
      overlay:Open("Solved!", format("%s puzzle in %s\nPick a new one below.",
        DIFF_LABEL[g.difficulty] or "", ns.FormatTime(g.elapsed)))
    end
  end
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
  if not generating then self:Hide() return end
  local stopAt = debugprofilestop() + 8
  repeat
    local ok, puzzle, solution = coroutine.resume(generating.co)
    if not ok then
      generating = nil
      self:Hide()
      Render()
      error(puzzle)
    end
    if coroutine.status(generating.co) == "dead" then
      local values, notes = {}, {}
      for i = 1, 81 do values[i], notes[i] = puzzle[i], 0 end
      local g = {
        difficulty = generating.difficulty,
        puzzle = puzzle, solution = solution,
        values = values, notes = notes,
        elapsed = 0, solved = false, mistakes = 0,
      }
      local daily = generating.seed ~= nil
      if daily then
        g.seed = generating.seed
        data.daily = g
      else
        data.game = g
      end
      generating = nil
      self:Hide()
      ShowBoard(g, daily and "daily" or "regular")
      Render()
      return
    end
  until debugprofilestop() > stopAt
end)

local function NewGame(difficulty)
  if generating then return end
  generating = {
    difficulty = difficulty,
    co = coroutine.create(function() return L.Generate(difficulty) end),
  }
  overlay:Close()
  Select(nil)
  driver:Show()
end

-- Today's puzzle: the same seed gives everyone the same board.
local function NewDaily()
  if generating then return end
  local seed = Today()
  generating = {
    difficulty = "medium", seed = seed,
    co = coroutine.create(function() return L.Generate("medium", seed) end),
  }
  overlay:Close()
  Select(nil)
  driver:Show()
end

-- Opens the daily: keeps today's board, or starts a fresh one for a new day.
local function OpenDaily()
  if generating then return end
  local seed = Today()
  if data.dailyStreak and data.dailyStreak > 0
    and not (data.lastDailyDay and SeedDay(seed) - data.lastDailyDay <= 1) then
    data.dailyStreak = 0 -- a day was missed
  end
  if ValidDaily(data.daily) and data.daily.seed == seed then
    if mode ~= "daily" or game ~= data.daily then
      ShowBoard(data.daily, "daily")
      Render()
    end
  else
    NewDaily()
  end
end

StaticPopupDialogs["DOWNTIME_NEW_SUDOKU"] = {
  text = "Start a new %s puzzle? This one will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, d) NewGame(d) end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function AskNewGame(difficulty)
  if generating then return end
  if difficulty == "daily" then OpenDaily() return end
  local g = data.game
  if mode == "daily" and g and not g.solved and g.difficulty == difficulty then
    ShowBoard(g, "regular") -- back to the puzzle in progress
    Render()
  elseif g and not g.solved and Started(g) then
    StaticPopup_Show("DOWNTIME_NEW_SUDOKU", DIFF_LABEL[difficulty], nil, difficulty)
  else
    NewGame(difficulty)
  end
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function CellOffset(k)
  return THICK + k * (CELL + THIN) + floor(k / 3) * (THICK - THIN)
end

local function Create(parent, saved)
  panel = parent
  data = saved
  if data.showMistakes == nil then data.showMistakes = true end
  if data.showTimer == nil then data.showTimer = true end
  if ValidGame(data.game) then
    data.game.elapsed = data.game.elapsed or 0
  else
    data.game = nil
  end
  if ValidDaily(data.daily) then
    data.daily.elapsed = data.daily.elapsed or 0
  else
    data.daily = nil
  end
  if type(data.dailyStreak) ~= "number" then data.dailyStreak = nil end
  if type(data.bestDailyStreak) ~= "number" then data.bestDailyStreak = nil end
  if type(data.lastDailyDay) ~= "number" then data.lastDailyDay = nil end

  local left = floor((ns.GAME_W - BOARD) / 2)

  diffText = UI.Title(parent, 14)
  diffText:SetPoint("TOPLEFT", left, -2)
  timerText = UI.Text(parent, 12, C.cream)
  timerText:SetPoint("TOPRIGHT", -left, -3)

  local board = CreateFrame("Frame", nil, parent)
  board:SetSize(BOARD, BOARD)
  board:SetPoint("TOPLEFT", left, -22)
  local lines = board:CreateTexture(nil, "BACKGROUND")
  lines:SetAllPoints()
  UI.Color(lines, COLOR.line)

  cells = {}
  for i = 1, 81 do
    local cell = CreateFrame("Button", nil, board)
    cell:SetSize(CELL, CELL)
    cell:SetPoint("TOPLEFT", CellOffset(L.COL[i] - 1), -CellOffset(L.ROW[i] - 1))
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell.bg = cell:CreateTexture(nil, "BORDER")
    cell.bg:SetAllPoints()
    local hl = cell:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.85, 0.5, 0.10)
    cell.digit = UI.Text(cell, 18, COLOR.given)
    cell.digit:SetPoint("CENTER", 0, 0)
    cell.notes = {}
    for d = 1, 9 do
      local fs = cell:CreateFontString(nil, "OVERLAY")
      fs:SetFont(ns.FONT, 8, "")
      local nr, nc = floor((d - 1) / 3), (d - 1) % 3
      fs:SetPoint("CENTER", cell, "TOPLEFT", 5 + nc * 10, -5 - nr * 10)
      fs:SetText(d)
      fs:Hide()
      cell.notes[d] = fs
    end
    cell:SetScript("OnClick", function(_, button)
      if button == "RightButton" then
        Select(i)
        Erase()
      elseif selected == i then
        Select(nil)
      else
        Select(i)
      end
    end)
    cells[i] = cell
  end

  statusText = UI.Title(board, 16)
  statusText:SetPoint("CENTER")
  statusText:Hide()

  overlay = UI.Overlay(board)
  toast = UI.Toast(board)

  -- Number pad with how many of each are left.
  pad = {}
  local padGap = floor((BOARD - CELL * 9) / 8)
  for d = 1, 9 do
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(CELL, CELL)
    b:SetPoint("TOPLEFT", board, "BOTTOMLEFT", (d - 1) * (CELL + padGap), -6)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    UI.Color(bg, C.wood)
    UI.Border(b, C.line)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0.3, 0.18)
    local fs = UI.Text(b, 16, C.gold)
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText(d)
    b.count = UI.Text(b, 8, C.dim)
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnClick", function() Enter(d, IsShiftKeyDown()) end)
    pad[d] = b
  end

  notesButton = UI.Button(parent, "Notes: Off", 96, 22)
  notesButton:SetPoint("TOPLEFT", board, "BOTTOMLEFT", 0, -42)
  notesButton:SetScript("OnClick", function()
    notesMode = not notesMode
    Render()
  end)
  UI.Tooltip(notesButton, "Notes", "Pencil in small numbers. Shift+number does the same.")
  local erase = UI.Button(parent, "Erase", 92, 22)
  erase:SetPoint("LEFT", notesButton, "RIGHT", 4, 0)
  erase:SetScript("OnClick", Erase)
  local undoButton = UI.Button(parent, "Undo", 92, 22)
  undoButton:SetPoint("LEFT", erase, "RIGHT", 4, 0)
  undoButton:SetScript("OnClick", Undo)

  local newLabel = UI.Text(parent, 11, C.dim)
  newLabel:SetPoint("TOPLEFT", notesButton, "BOTTOMLEFT", 0, -11)
  newLabel:SetText("New:")
  newRow = UI.Choice(parent, DIFFS, BOARD - 32, AskNewGame)
  newRow:SetPoint("LEFT", newLabel, "LEFT", 32, 0)

  local mistakes = UI.Check(parent, "Show mistakes",
    function() return data.showMistakes end,
    function(v) data.showMistakes = v; Render() end)
  local timer = UI.Check(parent, "Show timer",
    function() return data.showTimer end,
    function(v) data.showTimer = v; Render() end)
  -- Center the two checkboxes as a pair under the board.
  local w1 = 22 + mistakes.text:GetStringWidth()
  local w2 = 22 + timer.text:GetStringWidth()
  local gap = 24
  local x0 = floor((BOARD - (w1 + gap + w2)) / 2)
  if x0 < 0 then x0 = 0 end
  mistakes:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", x0, -14)
  timer:SetPoint("LEFT", mistakes, "LEFT", w1 + gap, 0)

  -- The clock runs while the game is open.
  local acc = 0
  parent:SetScript("OnUpdate", function(_, dt)
    if not game or game.solved or generating then return end
    game.elapsed = game.elapsed + dt
    acc = acc + dt
    if acc >= 0.25 then
      acc = 0
      UpdateTimer()
    end
  end)

  if data.mode == "daily" then
    OpenDaily()
  elseif data.game then
    ShowBoard(data.game, "regular")
    Render()
  else
    NewGame("easy")
  end
end

ns.RegisterGame({
  key = "sudoku",
  name = "Sudoku",
  blurb = "Fill the grid so every row, column and box has 1 to 9.",
  icon = ns.MEDIA .. "icons\\sudoku",
  order = 10,
  hasWins = true,
  Create = Create,
  OnKey = OnKey,
  OnHide = function() if selected then Select(nil) end end,
  OnShow = function()
    -- A new day while the window was closed: the daily starts fresh.
    if data and mode == "daily" and game and game.seed ~= Today() then OpenDaily() end
  end,
  InProgress = function(d)
    if type(d) ~= "table" then return false end
    local g = d.game
    if ValidGame(g) and not g.solved and Started(g) then return true end
    local daily = d.daily
    if ValidDaily(daily) and daily.seed == Today() and not daily.solved and Started(daily) then return true end
    return false
  end,
  Summary = function(d)
    local s = d.stats
    local best = s.best_hard and ("Hard " .. ns.FormatTime(s.best_hard))
      or s.best_medium and ("Medium " .. ns.FormatTime(s.best_medium))
      or s.best_easy and ("Easy " .. ns.FormatTime(s.best_easy))
    local line = best and ("Best: " .. best) or ""
    if (d.dailyStreak or 0) > 0 then
      line = ("Daily streak " .. d.dailyStreak .. ". " .. line):gsub("%s+$", "")
    end
    return line
  end,
})
