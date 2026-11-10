-------------------------------------------------------------------------------
-- Campfire Games: Quill
--
-- Find the hidden five-letter word in six guesses. Type with the on-screen
-- keys, or click the board and use your keyboard (Esc to stop typing, so your
-- movement keys work again). After each guess the tiles show what you got:
--   gold tile with a bar under the letter: right letter, right place
--   blue tile with a dot in the corner:     in the word, wrong place
--   dark tile:                              not in the word
-- "Real words only" asks the scribe's book before accepting a guess.
-- Daily: one shared word per calendar day, with a streak. Free play: random
-- words, as many as you like. Each mode keeps its own game in progress.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, sin, max = math.floor, math.sin, math.max

local TILE, GAP = 38, 4
local COLS, ROWS = 5, 6
local GRID_W = COLS * TILE + (COLS - 1) * GAP -- 206
local GRID_H = ROWS * TILE + (ROWS - 1) * GAP -- 248
local GRID_TOP = 28
local KEY_W, KEY_H, KEY_GAP = 27, 30, 3
local FLIP_STEP, FLIP_TIME = 0.12, 0.16
local SHAKE_TIME = 0.35
local RECENT_MAX = 100

local ABSENT, PRESENT, EXACT = 0, 1, 2

local function Scale(c, k) return { c[1] * k, c[2] * k, c[3] * k } end

local COLOR = {
  tile      = { 0.13, 0.095, 0.065 },
  edge      = { 0.40, 0.30, 0.16 },
  letter    = C.cream,
  exact     = Scale(C.gold, 0.88),
  present   = Scale(C.blue, 0.68),
  absent    = { 0.055, 0.042, 0.032 },
  ink       = { 0.10, 0.07, 0.04 },
  absentTxt = C.dim,
  glow      = C.ember,
}

local KEY_ROWS = { "qwertyuiop", "asdfghjkl", "zxcvbnm" }

local data
local game   -- the game in progress for the current mode (data.daily or data.free)
local panel, grid, tiles, keys, toast, overlay, hint, rowGlow, newButton
local ResetBoard, NewFreeGame
local chart, modeRow, keyFrame, dailyDone, streakText, realCheck
local words, wordSet
local focused = false
local reveal   -- { row, t, upto }
local shake    -- { row, t }

-------------------------------------------------------------------------------
-- Words and scoring
-------------------------------------------------------------------------------

local function LoadWords()
  local w = ns.QuillWords
  if type(w) ~= "table" or type(w.answers) ~= "table" or #w.answers == 0 then
    w = { answers = { "ember", "quill", "spark" }, extra = {} }
  end
  words = w.answers
  wordSet = {}
  for _, x in ipairs(w.answers) do wordSet[x] = true end
  for _, x in ipairs(w.extra or {}) do wordSet[x] = true end
end

-- 2 = right place, 1 = elsewhere in the word, 0 = not in the word.
local function Evaluate(guess, answer)
  local res, left = { 0, 0, 0, 0, 0 }, {}
  for i = 1, 5 do
    local g, a = guess:sub(i, i), answer:sub(i, i)
    if g == a then
      res[i] = EXACT
    else
      left[a] = (left[a] or 0) + 1
    end
  end
  for i = 1, 5 do
    if res[i] == ABSENT then
      local g = guess:sub(i, i)
      if (left[g] or 0) > 0 then
        res[i] = PRESENT
        left[g] = left[g] - 1
      end
    end
  end
  return res
end

local function IsWord5(s)
  return type(s) == "string" and s:match("^%l%l%l%l%l$") ~= nil
end

local function Today()
  return tonumber(date("%Y%m%d")) or 0
end

-- YYYYMMDD -> a running day count, so consecutive days differ by 1.
local function DayIndex(day)
  local y, m, d = floor(day / 10000), floor(day / 100) % 100, day % 100
  if m <= 2 then y = y - 1 end
  local era = floor(y / 400)
  local yoe = y - era * 400
  local doy = floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
  local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
  return era * 146097 + doe
end

-- Same word for everyone on a given day; no random numbers.
local function DailyWord(day)
  local h = day % 2147483647
  for _ = 1, 3 do h = (h * 48271 + 11) % 2147483647 end
  return words[h % #words + 1]
end

-- The daily streak as it stands today (a missed day breaks it).
local function LiveStreak(d)
  local n, last = d.dailyStreak, d.lastDailyDay
  if type(n) ~= "number" or n <= 0 then return 0 end
  if type(last) ~= "number" then return 0 end
  if DayIndex(Today()) - DayIndex(last) > 1 then return 0 end
  return n
end

local function Done()
  local g = game.guesses
  if #g > 0 and g[#g] == game.answer then return true, true end
  return #g >= ROWS, false
end

local function Started()
  return #game.guesses > 0
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function TileOffset(r, c)
  return (c - 1) * (TILE + GAP) + TILE / 2, -((r - 1) * (TILE + GAP) + TILE / 2)
end

local function PlaceRow(r, dx)
  for c = 1, COLS do
    local x, y = TileOffset(r, c)
    tiles[r][c]:SetPoint("CENTER", grid, "TOPLEFT", x + dx, y)
  end
end

local function PaintTile(r, c)
  local t = tiles[r][c]
  local g = game.guesses[r]
  local letter, state = "", nil
  local isCurrent = false
  if g then
    letter = g:sub(c, c)
    state = Evaluate(g, game.answer)[c]
    if reveal and reveal.row == r and c > reveal.upto then state = nil end
  elseif r == #game.guesses + 1 and not Done() then
    isCurrent = true
    letter = game.cur:sub(c, c)
  end

  local bg, txt, edge = COLOR.tile, COLOR.letter, COLOR.edge
  t.bar:Hide()
  t.dot:Hide()
  if state == EXACT then
    bg, txt, edge = COLOR.exact, COLOR.ink, Scale(COLOR.exact, 0.7)
    t.bar:Show()
  elseif state == PRESENT then
    bg, txt, edge = COLOR.present, COLOR.ink, Scale(COLOR.present, 0.7)
    t.dot:Show()
  elseif state == ABSENT then
    bg, txt, edge = COLOR.absent, COLOR.absentTxt, Scale(COLOR.edge, 0.5)
  elseif isCurrent and focused then
    edge = C.gold
  elseif isCurrent and letter ~= "" then
    edge = C.dim
  end
  UI.Color(t.bg, bg)
  UI.SetBorderColor(t.border, edge)
  UI.SetTextColor(t.text, txt)
  t.text:SetText(letter:upper())
end

local function KeyStates()
  local best = {}
  for r, g in ipairs(game.guesses) do
    if not (reveal and reveal.row == r) then
      local res = Evaluate(g, game.answer)
      for i = 1, 5 do
        local ch = g:sub(i, i)
        if (best[ch] or -1) < res[i] then best[ch] = res[i] end
      end
    end
  end
  return best
end

local function PaintKeys()
  local best = KeyStates()
  for ch, k in pairs(keys) do
    local s = best[ch]
    local bg, txt = COLOR.tile, C.gold
    k.dot:Hide()
    if s == EXACT then
      bg, txt = COLOR.exact, COLOR.ink
    elseif s == PRESENT then
      bg, txt = COLOR.present, COLOR.ink
      k.dot:Show()
    elseif s == ABSENT then
      bg, txt = COLOR.absent, C.faint
    end
    UI.Color(k.bg, bg)
    UI.SetTextColor(k.label, txt)
  end
end

local function PaintHint()
  local done = Done()
  if done then
    hint:SetText("")
  elseif focused then
    hint:SetText("Typing... (Esc to stop)")
    UI.SetTextColor(hint, C.gold)
  else
    hint:SetText("Click the board to type")
    UI.SetTextColor(hint, C.faint)
  end
end

local function Render()
  local done = Done()
  for r = 1, ROWS do
    for c = 1, COLS do PaintTile(r, c) end
  end
  PaintKeys()
  PaintHint()
  local daily = data.mode == "daily"
  streakText:SetShown(daily)
  streakText:SetText("Daily streak " .. LiveStreak(data))
  local showDone = daily and done and not reveal
  keyFrame:SetShown(not showDone)
  dailyDone:SetShown(showDone)
  if showDone then
    local _, won = Done()
    local n = #game.guesses
    dailyDone.title:SetText(won and "Well found!" or ("The word was " .. game.answer:upper()))
    dailyDone.result:SetText(won and format("Solved in %d %s.", n, n == 1 and "guess" or "guesses")
      or "Not this time.")
    dailyDone.note:SetText("Today's word is done. Come back tomorrow.")
  end
  local row = #game.guesses + 1
  if not done and row <= ROWS then
    rowGlow:ClearAllPoints()
    rowGlow:SetPoint("CENTER", grid, "TOPLEFT", GRID_W / 2, -((row - 1) * (TILE + GAP) + TILE / 2))
    rowGlow:SetShown(focused)
  else
    rowGlow:Hide()
  end
end

-------------------------------------------------------------------------------
-- End of game
-------------------------------------------------------------------------------

local function UpdateChart(won)
  local top = 1
  for i = 1, ROWS do top = max(top, data.dist[i] or 0) end
  for i = 1, ROWS do
    local n = data.dist[i] or 0
    local row = chart.rows[i]
    local w = n > 0 and max(4, floor(n / top * 140)) or 2
    row.bar:SetWidth(w)
    if won and i == #game.guesses then
      UI.Color(row.bar, C.gold)
    else
      UI.Color(row.bar, n > 0 and C.line or C.lineDark)
    end
    row.count:SetText(n)
  end
end

local function ShowEnd(extra)
  local _, won = Done()
  if data.mode == "daily" then
    overlay:Close()
    return
  end
  if won then
    local n = #game.guesses
    overlay:Open("Well found!", format("Solved in %d %s.%s", n, n == 1 and "guess" or "guesses",
      extra and "\nA new best!" or ""))
  else
    overlay:Open("The word was " .. game.answer:upper(), "Not this time. Try another.")
  end
  UpdateChart(won)
end

local function SetFocus(on)
  on = on and true or false
  if on and Done() then on = false end
  if focused == on then return end
  focused = on
  ns.WantKeys(on)
  Render()
end

local pendingNewBest

local function Finish()
  local _, won = Done()
  SetFocus(false)
  if won then
    local n = #game.guesses
    data.dist[n] = (data.dist[n] or 0) + 1
    pendingNewBest = ns.RecordResult("quill", { won = true, score = n, lowerIsBetter = true })
    ns.Sound("win")
  else
    ns.RecordResult("quill", { won = false })
    ns.Sound("bad")
  end
  game.done = true
  game.won = won and true or false
  game.cur = ""
  if data.mode == "daily" then
    local day = game.day
    if won then
      if type(data.lastDailyDay) == "number" and DayIndex(day) - DayIndex(data.lastDailyDay) == 1
        and (data.dailyStreak or 0) > 0 then
        data.dailyStreak = data.dailyStreak + 1
      else
        data.dailyStreak = 1
      end
      if data.dailyStreak > (data.bestDailyStreak or 0) then data.bestDailyStreak = data.dailyStreak end
    else
      data.dailyStreak = 0
    end
    data.lastDailyDay = day
  end
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function Busy()
  return reveal ~= nil or Done()
end

local function TypeLetter(ch)
  if Busy() or #game.cur >= 5 then return end
  game.cur = game.cur .. ch
  ns.Sound("place")
  Render()
end

local function Backspace()
  if Busy() or #game.cur == 0 then return end
  game.cur = game.cur:sub(1, -2)
  Render()
end

local function Shake(msg)
  shake = { row = #game.guesses + 1, t = 0 }
  toast:Say(msg, C.red)
  ns.Sound("bad")
end

local function Submit()
  if Busy() then return end
  local guess = game.cur
  if #guess < 5 then
    Shake("Five letters, please")
    return
  end
  if data.realWords and not wordSet[guess] then
    Shake("Not in the scribe's book")
    return
  end
  game.guesses[#game.guesses + 1] = guess
  game.cur = ""
  reveal = { row = #game.guesses, t = 0, upto = 0 }
  ns.Sound("page")
  if Done() then Finish() end
  Render()
end

local function FinishReveal()
  if not reveal then return end
  local r = reveal.row
  reveal = nil
  for c = 1, COLS do tiles[r][c]:SetHeight(TILE) end
  Render()
  if Done() then
    ShowEnd(pendingNewBest)
    pendingNewBest = nil
  end
end

local function PickAnswer()
  local used = {}
  for _, w in ipairs(data.recent) do used[w] = true end
  local pick
  for _ = 1, 60 do
    pick = words[math.random(#words)]
    if not used[pick] then break end
  end
  data.recent[#data.recent + 1] = pick
  while #data.recent > RECENT_MAX do table.remove(data.recent, 1) end
  return pick
end

local function NewWord()
  ResetBoard()
  game = NewFreeGame()
  SetFocus(false)
  Render()
end

local function AbandonAndNew()
  if Started() and not Done() then
    ns.RecordResult("quill", { won = false })
  end
  NewWord()
end

StaticPopupDialogs["DOWNTIME_NEW_QUILL"] = {
  text = "Start a new word? This one will count as a loss.",
  button1 = YES,
  button2 = NO,
  OnAccept = function() AbandonAndNew() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function AskNewWord()
  if Started() and not Done() then
    StaticPopup_Show("DOWNTIME_NEW_QUILL")
  else
    AbandonAndNew()
  end
end

local function OnKey(key)
  if not focused then return false end
  if key == "ESCAPE" then
    SetFocus(false)
    return true
  elseif key == "BACKSPACE" then
    Backspace()
    return true
  elseif key == "ENTER" or key == "NUMPADENTER" then
    Submit()
    return true
  elseif type(key) == "string" and #key == 1 and key:match("%a") then
    TypeLetter(key:lower())
    return true
  end
  return false
end

-------------------------------------------------------------------------------
-- Saved data
-------------------------------------------------------------------------------

-- Checks one saved game table; fixes small things, returns false if unusable.
local function ValidGame(g)
  if type(g) ~= "table" or not IsWord5(g.answer) or type(g.guesses) ~= "table"
    or #g.guesses > ROWS then
    return false
  end
  for i, x in ipairs(g.guesses) do
    if not IsWord5(x) then return false end
    -- a guess after the answer was found is junk
    if x == g.answer and i < #g.guesses then return false end
  end
  if type(g.cur) ~= "string" or not g.cur:match("^%l*$") or #g.cur > 5 then g.cur = "" end
  local last = g.guesses[#g.guesses]
  if last == g.answer or #g.guesses >= ROWS then g.cur = "" end
  return true
end

local function NewDaily()
  local day = Today()
  data.daily = { day = day, answer = DailyWord(day), guesses = {}, cur = "" }
  return data.daily
end

function NewFreeGame()
  data.free = { answer = PickAnswer(), guesses = {}, cur = "" }
  return data.free
end

local function Sanitize()
  if type(data.realWords) ~= "boolean" then data.realWords = true end
  if type(data.dist) ~= "table" then data.dist = {} end
  for i = 1, ROWS do
    if type(data.dist[i]) ~= "number" or data.dist[i] < 0 then data.dist[i] = 0 end
  end
  if type(data.recent) ~= "table" then data.recent = {} end
  local recent = {}
  for _, w in ipairs(data.recent) do
    if IsWord5(w) then recent[#recent + 1] = w end
  end
  while #recent > RECENT_MAX do table.remove(recent, 1) end
  data.recent = recent

  -- the single game saved by the first version becomes the free-play game
  if data.free == nil and data.answer ~= nil then
    data.free = { answer = data.answer, guesses = data.guesses, cur = data.cur }
  end
  data.answer, data.guesses, data.cur, data.done, data.won = nil, nil, nil, nil, nil

  for _, k in ipairs({ "dailyStreak", "bestDailyStreak", "lastDailyDay" }) do
    if type(data[k]) ~= "number" then data[k] = k == "lastDailyDay" and nil or 0 end
  end
  if data.mode ~= "daily" and data.mode ~= "free" then data.mode = "daily" end
  if not ValidGame(data.free) then NewFreeGame() end
  if not ValidGame(data.daily) or type(data.daily.day) ~= "number"
    or data.daily.answer ~= DailyWord(data.daily.day) then
    NewDaily()
  end
  -- a missed day ends the streak
  if LiveStreak(data) == 0 then data.dailyStreak = 0 end
end

function ResetBoard()
  reveal, shake = nil, nil
  for r = 1, ROWS do
    PlaceRow(r, 0)
    for c = 1, COLS do tiles[r][c]:SetHeight(TILE) end
  end
  overlay:Close()
  pendingNewBest = nil
end

local function SetMode(mode)
  FinishReveal()
  SetFocus(false)
  data.mode = mode
  if mode == "daily" then
    if data.daily.day ~= Today() then NewDaily() end
    game = data.daily
  else
    game = data.free
  end
  ResetBoard()
  modeRow:Select(mode)
  newButton:SetShown(mode == "free")
  realCheck:ClearAllPoints()
  local cw = 22 + realCheck.text:GetStringWidth()
  if mode == "free" then
    newButton:ClearAllPoints()
    newButton:SetPoint("BOTTOMLEFT", panel, "BOTTOM", -floor((90 + 22 + cw) / 2), 8)
    realCheck:SetPoint("LEFT", newButton, "RIGHT", 22, 0)
  else
    realCheck:SetPoint("BOTTOMLEFT", panel, "BOTTOM", -floor(cw / 2), 12)
  end
  Render()
  if mode == "free" and Done() then ShowEnd(false) end
end

-- A new calendar day gives a fresh daily word.
local function CheckDay()
  if not data or not game then return end
  if data.daily.day ~= Today() then
    if LiveStreak(data) == 0 then data.dailyStreak = 0 end
    if data.mode == "daily" then
      SetMode("daily")
    else
      NewDaily()
    end
  end
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function MakeKey(parent, label, w, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, KEY_H)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  UI.Color(b.bg, COLOR.tile)
  UI.Border(b, C.line)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.85, 0.5, 0.16)
  b.label = UI.Text(b, #label > 1 and 9 or 14, C.gold)
  b.label:SetPoint("CENTER", 0, 0)
  b.label:SetText(#label > 1 and label or label:upper())
  b.dot = b:CreateTexture(nil, "ARTWORK")
  b.dot:SetSize(4, 4)
  b.dot:SetPoint("TOPRIGHT", -2, -2)
  UI.Color(b.dot, COLOR.ink)
  b.dot:Hide()
  b:SetScript("OnClick", onClick)
  return b
end

local function BuildKeys(parent, top)
  keys = {}
  local function RowStart(width)
    return floor((ns.GAME_W - width) / 2)
  end
  -- row 1 and 2: letters only
  for ri = 1, 2 do
    local str = KEY_ROWS[ri]
    local n = #str
    local x = RowStart(n * KEY_W + (n - 1) * KEY_GAP)
    local y = top - (ri - 1) * (KEY_H + KEY_GAP)
    for i = 1, n do
      local ch = str:sub(i, i)
      local k = MakeKey(parent, ch, KEY_W, function() TypeLetter(ch) end)
      k:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (KEY_W + KEY_GAP), y)
      keys[ch] = k
    end
  end
  -- row 3: Enter, letters, Back
  local str = KEY_ROWS[3]
  local n, wide = #str, 40
  local x = RowStart(n * KEY_W + 2 * wide + (n + 1) * KEY_GAP)
  local y = top - 2 * (KEY_H + KEY_GAP)
  local enter = MakeKey(parent, "Enter", wide, Submit)
  enter:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  x = x + wide + KEY_GAP
  for i = 1, n do
    local ch = str:sub(i, i)
    local k = MakeKey(parent, ch, KEY_W, function() TypeLetter(ch) end)
    k:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    keys[ch] = k
    x = x + KEY_W + KEY_GAP
  end
  local back = MakeKey(parent, "Back", wide, Backspace)
  back:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

local function BuildChart(o)
  chart = CreateFrame("Frame", nil, o)
  chart:SetSize(200, ROWS * 14)
  chart:SetPoint("TOP", o.buttons, "BOTTOM", 0, -18)
  chart.rows = {}
  for i = 1, ROWS do
    local row = {}
    local label = UI.Text(chart, 10, C.dim)
    label:SetPoint("TOPLEFT", 0, -(i - 1) * 14)
    label:SetText(i)
    row.bar = chart:CreateTexture(nil, "ARTWORK")
    row.bar:SetHeight(9)
    row.bar:SetPoint("TOPLEFT", 16, -(i - 1) * 14 - 2)
    row.bar:SetWidth(2)
    UI.Color(row.bar, C.line)
    row.count = UI.Text(chart, 10, C.cream)
    row.count:SetPoint("LEFT", row.bar, "RIGHT", 5, 0)
    chart.rows[i] = row
  end
end

local function Create(parent, saved)
  panel = parent
  data = saved
  LoadWords()
  Sanitize()
  game = data.mode == "daily" and data.daily or data.free

  modeRow = UI.Choice(parent, {
    { key = "daily", label = "Daily" },
    { key = "free", label = "Free play" },
  }, 140, function(k) SetMode(k) end)
  modeRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -3)

  hint = UI.Text(parent, 10, C.faint)
  hint:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -9)
  hint:SetJustifyH("RIGHT")

  grid = CreateFrame("Frame", nil, parent)
  grid:SetSize(GRID_W, GRID_H)
  grid:SetPoint("TOP", parent, "TOP", 0, -GRID_TOP)

  rowGlow = grid:CreateTexture(nil, "BACKGROUND")
  rowGlow:SetTexture(ns.MEDIA .. "glow")
  rowGlow:SetSize(GRID_W + 40, TILE + 22)
  rowGlow:SetVertexColor(COLOR.glow[1], COLOR.glow[2], COLOR.glow[3], 0.40)
  rowGlow:SetBlendMode("ADD")
  rowGlow:Hide()

  tiles = {}
  for r = 1, ROWS do
    tiles[r] = {}
    for c = 1, COLS do
      local t = CreateFrame("Frame", nil, grid)
      t:SetSize(TILE, TILE)
      t.bg = t:CreateTexture(nil, "BACKGROUND")
      t.bg:SetAllPoints()
      UI.Color(t.bg, COLOR.tile)
      t.border = UI.Border(t, COLOR.edge)
      t.text = UI.Text(t, 22, COLOR.letter)
      t.text:SetPoint("CENTER", 0, 1)
      t.bar = t:CreateTexture(nil, "ARTWORK")
      t.bar:SetHeight(3)
      t.bar:SetPoint("BOTTOMLEFT", 7, 5)
      t.bar:SetPoint("BOTTOMRIGHT", -7, 5)
      UI.Color(t.bar, COLOR.ink)
      t.bar:Hide()
      t.dot = t:CreateTexture(nil, "ARTWORK")
      t.dot:SetSize(6, 6)
      t.dot:SetPoint("TOPRIGHT", -4, -4)
      UI.Color(t.dot, COLOR.ink)
      t.dot:Hide()
      tiles[r][c] = t
    end
    PlaceRow(r, 0)
  end

  local catcher = CreateFrame("Button", nil, grid)
  catcher:SetAllPoints()
  catcher:SetScript("OnClick", function() SetFocus(true) end)

  streakText = UI.Text(parent, 10, C.dim)
  streakText:SetPoint("TOP", grid, "BOTTOM", 0, -3)

  keyFrame = CreateFrame("Frame", nil, parent)
  keyFrame:SetAllPoints()
  BuildKeys(keyFrame, -(GRID_TOP + GRID_H + 18))

  -- shown instead of the keys once today's word is finished
  dailyDone = CreateFrame("Frame", nil, parent)
  dailyDone:SetSize(ns.GAME_W - 20, 96)
  dailyDone:SetPoint("TOP", grid, "BOTTOM", 0, -22)
  dailyDone.title = UI.Title(dailyDone, 18)
  dailyDone.title:SetPoint("TOP", 0, -6)
  dailyDone.result = UI.Text(dailyDone, 12, C.cream)
  dailyDone.result:SetPoint("TOP", dailyDone.title, "BOTTOM", 0, -8)
  dailyDone.note = UI.Text(dailyDone, 11, C.dim)
  dailyDone.note:SetWidth(ns.GAME_W - 40)
  dailyDone.note:SetPoint("TOP", dailyDone.result, "BOTTOM", 0, -12)
  dailyDone:Hide()

  newButton = UI.Button(parent, "New word", 90, 22)
  newButton:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 12, 8)
  newButton:SetScript("OnClick", AskNewWord)
  realCheck = UI.Check(parent, "Real words only",
    function() return data.realWords end,
    function(v) data.realWords = v end)
  realCheck:SetPoint("LEFT", newButton, "RIGHT", 22, 0)

  overlay = UI.Overlay(parent)
  local again = UI.Button(overlay.buttons, "New word", 100, 24)
  again:SetPoint("TOP", overlay.buttons, "TOP", 0, 0)
  again:SetScript("OnClick", function() NewWord() end)
  BuildChart(overlay)

  toast = UI.Toast(parent)
  toast:ClearAllPoints()
  toast:SetPoint("TOP", parent, "TOP", 0, -118)

  parent:SetScript("OnUpdate", function(_, dt)
    if reveal then
      reveal.t = reveal.t + dt
      local r = reveal.row
      for c = 1, COLS do
        local p = (reveal.t - (c - 1) * FLIP_STEP) / FLIP_TIME
        local tile = tiles[r][c]
        if p <= 0 then
          tile:SetHeight(TILE)
        elseif p < 1 then
          local h = p < 0.5 and (1 - 2 * p) or (2 * p - 1)
          tile:SetHeight(max(2, TILE * h))
          if p >= 0.5 and reveal.upto < c then
            reveal.upto = c
            PaintTile(r, c)
          end
        else
          tile:SetHeight(TILE)
          if reveal.upto < c then
            reveal.upto = c
            PaintTile(r, c)
          end
        end
      end
      if reveal.t >= (COLS - 1) * FLIP_STEP + FLIP_TIME then FinishReveal() end
    end
    if shake then
      shake.t = shake.t + dt
      if shake.t >= SHAKE_TIME then
        PlaceRow(shake.row, 0)
        shake = nil
      else
        PlaceRow(shake.row, sin(shake.t * 70) * 5 * (1 - shake.t / SHAKE_TIME))
      end
    end
  end)

  SetMode(data.mode)
end

ns.RegisterGame({
  key = "quill",
  name = "Quill",
  blurb = "Find the hidden five-letter word in six guesses.",
  icon = ns.MEDIA .. "icons\\quill",
  order = 85,
  hasWins = true,
  Create = Create,
  OnKey = OnKey,
  OnShow = CheckDay,
  OnHide = function()
    FinishReveal()
    SetFocus(false)
  end,
  InProgress = function(d)
    if type(d) ~= "table" then return false end
    local function Live(g)
      if type(g) ~= "table" or not IsWord5(g.answer) or type(g.guesses) ~= "table" then return false end
      local n = #g.guesses
      if n == 0 or n >= ROWS then return false end
      for i = 1, n do
        local x = g.guesses[i]
        if not IsWord5(x) or x == g.answer then return false end
      end
      return true
    end
    local daily = type(d.daily) == "table" and d.daily.day == Today() and d.daily or nil
    return Live(daily) or Live(d.free)
  end,
  Summary = function(d)
    local s = d.stats
    if not s or (s.played or 0) == 0 then return "" end
    local ds = LiveStreak(d)
    if ds > 0 then return format("Daily streak %d, won %d", ds, s.won or 0) end
    return format("Won %d, streak %d", s.won or 0, s.streak or 0)
  end,
})
