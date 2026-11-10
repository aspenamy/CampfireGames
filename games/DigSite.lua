-------------------------------------------------------------------------------
-- Campfire Games: Dig Site
--
-- Dig up every safe tile without setting off a hidden trap. A number says how
-- many traps touch that tile. Left-click digs, right-click places or removes
-- a survey flag. Click a number whose flags already match it to dig around it.
-- The first dig is always safe.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, random = math.floor, math.random

local DIFFS = {
  { key = "small", label = "Small" },
  { key = "medium", label = "Medium" },
  { key = "large", label = "Large" },
}
local SIZES = {
  small  = { w = 9,  h = 9,  traps = 10, cell = 32, font = 16, name = "Small" },
  medium = { w = 12, h = 12, traps = 22, cell = 24, font = 13, name = "Medium" },
  large  = { w = 14, h = 14, traps = 35, cell = 21, font = 11, name = "Large" },
}
local MAX_CELLS = 196
local BOARD_MIN = 288

local EARTH = { 0.45, 0.30, 0.17 }
local SAND  = { 0.87, 0.80, 0.62 }
local HIT   = { 0.80, 0.25, 0.18 }
local NUMBER = {
  { 0.18, 0.36, 0.78 }, -- 1 blue
  { 0.20, 0.50, 0.20 }, -- 2 green
  { 0.78, 0.18, 0.15 }, -- 3 red
  { 0.45, 0.22, 0.60 }, -- 4 purple
  { 0.50, 0.12, 0.12 }, -- 5 maroon
  { 0.10, 0.50, 0.50 }, -- 6 teal
  { 0.18, 0.14, 0.10 }, -- 7 dark
  { 0.40, 0.40, 0.40 }, -- 8 grey
}

local HIDDEN, DUG, FLAG = 0, 1, 2

local data, game
local panel, board, cells, overlay, toast, sparkFrame
local timerText, trapsText, choiceRow, againButton
local counts = {}
local nbrCache = {}
local sparks = {}

-------------------------------------------------------------------------------
-- Logic
-------------------------------------------------------------------------------

local function Neighbors(i)
  local key = game.w * 1000 + i
  local n = nbrCache[key]
  if n then return n end
  n = {}
  local w, h = game.w, game.h
  local r, c = floor((i - 1) / w), (i - 1) % w
  for dr = -1, 1 do
    for dc = -1, 1 do
      if dr ~= 0 or dc ~= 0 then
        local rr, cc = r + dr, c + dc
        if rr >= 0 and rr < h and cc >= 0 and cc < w then
          n[#n + 1] = rr * w + cc + 1
        end
      end
    end
  end
  nbrCache[key] = n
  return n
end

local function RebuildCounts()
  counts = {}
  for i = 1, game.w * game.h do
    local n = 0
    if game.mines then
      for _, j in ipairs(Neighbors(i)) do
        if game.mines[j] == 1 then n = n + 1 end
      end
    end
    counts[i] = n
  end
end

local function ValidGame(g)
  if type(g) ~= "table" then return false end
  local s = SIZES[g.diff]
  if not s or g.w ~= s.w or g.h ~= s.h or g.traps ~= s.traps then return false end
  local n = s.w * s.h
  if type(g.state) ~= "table" or #g.state ~= n then return false end
  for i = 1, n do
    local v = g.state[i]
    if v ~= HIDDEN and v ~= DUG and v ~= FLAG then return false end
  end
  if type(g.elapsed) ~= "number" then return false end
  if g.status ~= "ready" and g.status ~= "playing" and g.status ~= "won" and g.status ~= "lost" then
    return false
  end
  if g.status ~= "ready" then
    if type(g.mines) ~= "table" or #g.mines ~= n then return false end
    local m = 0
    for i = 1, n do
      if g.mines[i] ~= 0 and g.mines[i] ~= 1 then return false end
      m = m + g.mines[i]
    end
    if m ~= g.traps then return false end
  end
  if g.status == "lost" and (type(g.hit) ~= "number" or g.hit < 1 or g.hit > n) then return false end
  return true
end

local function FlagCount()
  local f = 0
  for i = 1, game.w * game.h do
    if game.state[i] == FLAG then f = f + 1 end
  end
  return f
end

local function PlaceTraps(first)
  local safe = { [first] = true }
  for _, j in ipairs(Neighbors(first)) do safe[j] = true end
  local pool = {}
  for i = 1, game.w * game.h do
    if not safe[i] then pool[#pool + 1] = i end
  end
  ns.Shuffle(pool)
  game.mines = {}
  for i = 1, game.w * game.h do game.mines[i] = 0 end
  for k = 1, game.traps do game.mines[pool[k]] = 1 end
  RebuildCounts()
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function UpdateTimer()
  if not game then return end
  timerText:SetText(ns.FormatTime(game.elapsed))
  trapsText:SetText(tostring(game.traps - FlagCount()))
end

local function Render()
  if not game then return end
  local lost, won = game.status == "lost", game.status == "won"
  for i = 1, game.w * game.h do
    local cell = cells[i]
    local st = game.state[i]
    local mine = game.mines and game.mines[i] == 1
    local bg, icon, num, cross, top = nil, nil, 0, false, false

    if st == DUG then
      bg = SAND
      num = counts[i]
    elseif lost and mine and st ~= FLAG then
      bg = (i == game.hit) and HIT or SAND
      icon = "trap"
    elseif st == FLAG then
      icon = "flag"
      if lost and not mine then
        bg = EARTH
        cross = true
      end
    end
    if not bg then
      bg = EARTH
      top = true
    end

    local shade = 0.9 + ((i * 37) % 11) / 55
    if bg == EARTH then
      cell.bg:SetColorTexture(EARTH[1] * shade, EARTH[2] * shade, EARTH[3] * shade, 1)
    else
      cell.bg:SetColorTexture(bg[1], bg[2], bg[3], 1)
    end
    cell.top:SetShown(top)
    cell.hl:SetShown(not (lost or won))

    if icon then
      cell.icon:SetTexture(ns.MEDIA .. "dig\\" .. icon)
      cell.icon:Show()
    else
      cell.icon:Hide()
    end
    cell.cross:SetShown(cross)
    cell.crossText:SetShown(cross)

    if num > 0 then
      cell.num:SetText(num)
      UI.SetTextColor(cell.num, NUMBER[num])
      cell.num:Show()
    else
      cell.num:Hide()
    end
  end
  choiceRow:Select(game.diff)
  UpdateTimer()
end

local function Layout()
  local s = SIZES[game.diff]
  local size = s.cell
  local bw, bh = s.w * size, s.h * size
  board:SetSize(math.max(bw, BOARD_MIN), math.max(bh, BOARD_MIN))
  for i = 1, MAX_CELLS do
    local cell = cells[i]
    if i <= s.w * s.h then
      local r, c = floor((i - 1) / s.w), (i - 1) % s.w
      cell:SetSize(size, size)
      cell:ClearAllPoints()
      cell:SetPoint("TOPLEFT", board, "TOPLEFT", floor((board:GetWidth() - bw) / 2) + c * size,
        -(floor((board:GetHeight() - bh) / 2) + r * size))
      cell.num:SetFont(ns.FONT, s.font, "")
      cell.icon:SetSize(size - 8, size - 8)
      cell.crossText:SetFont(ns.FONT, s.font, "")
      cell:Show()
    else
      cell:Hide()
    end
  end
end

-------------------------------------------------------------------------------
-- Sparkles
-------------------------------------------------------------------------------

local function StartSparkles()
  for k = 1, #sparks do
    local sp = sparks[k]
    sp.delay = random() * 0.9
    sp.age = 0
    sp.life = 1.3 + random() * 0.9
    sp.x = 20 + random() * (board:GetWidth() - 40)
    sp.y = 30 + random() * (board:GetHeight() * 0.6)
    sp.vy = 25 + random() * 35
    sp.active = true
    sp.tex:SetAlpha(0)
    sp.tex:Show()
  end
  sparkFrame:Show()
end

local function StopSparkles()
  for k = 1, #sparks do
    sparks[k].active = false
    sparks[k].tex:Hide()
  end
  sparkFrame:Hide()
end

local function TickSparkles(dt)
  local any = false
  for k = 1, #sparks do
    local sp = sparks[k]
    if sp.active then
      any = true
      if sp.delay > 0 then
        sp.delay = sp.delay - dt
      else
        sp.age = sp.age + dt
        if sp.age >= sp.life then
          sp.active = false
          sp.tex:Hide()
        else
          local t = sp.age / sp.life
          local a = t < 0.2 and (t / 0.2) or (1 - (t - 0.2) / 0.8)
          sp.tex:SetAlpha(a)
          sp.tex:ClearAllPoints()
          sp.tex:SetPoint("CENTER", board, "BOTTOMLEFT", sp.x, sp.y + sp.vy * sp.age)
        end
      end
    end
  end
  if not any then sparkFrame:Hide() end
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function ShowEnd()
  if game.status == "lost" then
    overlay.title:SetText("The tunnel caved in!")
    overlay.line:SetText("A trap was waiting under that tile.")
    againButton:SetText("Try again")
    overlay:Show()
  elseif game.status == "won" then
    local best = data.stats["best_" .. game.diff]
    overlay.title:SetText("Site cleared!")
    overlay.line:SetText(format("%s dig in %s\nBest: %s", SIZES[game.diff].name,
      ns.FormatTime(game.elapsed), best and ns.FormatTime(best) or "-"))
    againButton:SetText("New dig")
    overlay:Show()
  else
    overlay:Hide()
  end
end

local function Lose(hit)
  game.status = "lost"
  game.hit = hit
  ns.RecordResult("digsite", { won = false })
  ns.Sound("bad")
  Render()
  ShowEnd()
end

local function Win()
  game.status = "won"
  for i = 1, game.w * game.h do
    if game.mines[i] == 1 then game.state[i] = FLAG end
  end
  local newBest = ns.RecordResult("digsite", {
    won = true, time = floor(game.elapsed), lowerIsBetter = true, bestKey = "best_" .. game.diff,
  })
  ns.Sound("win")
  Render()
  ShowEnd()
  if newBest then toast:Say("New best!") end
  StartSparkles()
end

local function CheckWin()
  local dug = 0
  for i = 1, game.w * game.h do
    if game.state[i] == DUG then dug = dug + 1 end
  end
  if dug == game.w * game.h - game.traps then
    Win()
    return true
  end
  return false
end

-- Digs tile i and flood-opens zeros. Returns true when it was a trap.
local function Reveal(i)
  if game.state[i] ~= HIDDEN then return false end
  if game.mines[i] == 1 then return true end
  local stack = { i }
  while #stack > 0 do
    local j = table.remove(stack)
    if game.state[j] == HIDDEN then
      game.state[j] = DUG
      if counts[j] == 0 then
        for _, k in ipairs(Neighbors(j)) do
          if game.state[k] == HIDDEN then stack[#stack + 1] = k end
        end
      end
    end
  end
  return false
end

local function Dig(i)
  if game.status == "won" or game.status == "lost" then return end
  if game.state[i] ~= HIDDEN then return end
  if game.status == "ready" then
    PlaceTraps(i)
    game.status = "playing"
  end
  ns.Sound("place")
  if Reveal(i) then
    Lose(i)
    return
  end
  Render()
  CheckWin()
end

local function Chord(i)
  local flags = 0
  for _, j in ipairs(Neighbors(i)) do
    if game.state[j] == FLAG then flags = flags + 1 end
  end
  if flags ~= counts[i] then return end
  local hit
  for _, j in ipairs(Neighbors(i)) do
    if game.state[j] == HIDDEN and Reveal(j) and not hit then hit = j end
  end
  ns.Sound("place")
  if hit then
    Lose(hit)
    return
  end
  Render()
  CheckWin()
end

local function Flag(i)
  if game.status ~= "playing" and game.status ~= "ready" then return end
  local st = game.state[i]
  if st == DUG then return end
  game.state[i] = (st == FLAG) and HIDDEN or FLAG
  ns.Sound("click")
  Render()
end

local function OnCell(i, button)
  if not game then return end
  if button == "RightButton" then
    Flag(i)
  elseif game.state[i] == DUG then
    if game.status == "playing" and counts[i] > 0 then Chord(i) end
  else
    Dig(i)
  end
end

local function NewGame(diff)
  local s = SIZES[diff] or SIZES.small
  local state = {}
  for i = 1, s.w * s.h do state[i] = HIDDEN end
  game = {
    diff = diff, w = s.w, h = s.h, traps = s.traps,
    state = state, elapsed = 0, status = "ready",
  }
  data.game = game
  RebuildCounts()
  StopSparkles()
  overlay:Hide()
  Layout()
  Render()
end

StaticPopupDialogs["DOWNTIME_NEW_DIGSITE"] = {
  text = "Start a new %s dig? This one will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, d) NewGame(d) end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function AskNewGame(diff)
  if game and game.status == "playing" then
    StaticPopup_Show("DOWNTIME_NEW_DIGSITE", SIZES[diff].name, nil, diff)
  else
    NewGame(diff)
  end
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function Create(parent, saved)
  panel = parent
  data = saved

  choiceRow = UI.Choice(parent, DIFFS, 300, AskNewGame)
  choiceRow:SetPoint("TOP", parent, "TOP", 0, -2)

  local trapIcon = parent:CreateTexture(nil, "ARTWORK")
  trapIcon:SetTexture(ns.MEDIA .. "dig\\trap")
  trapIcon:SetSize(16, 16)
  trapIcon:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -32)
  trapsText = UI.Text(parent, 13, C.cream)
  trapsText:SetPoint("LEFT", trapIcon, "RIGHT", 5, 0)

  timerText = UI.Text(parent, 13, C.cream)
  timerText:SetPoint("TOP", parent, "TOP", 0, -34)

  local newButton = UI.Button(parent, "New dig", 84, 22)
  newButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -30)
  newButton:SetScript("OnClick", function()
    if game then AskNewGame(game.diff) end
  end)

  board = CreateFrame("Frame", nil, parent)
  board:SetSize(BOARD_MIN, BOARD_MIN)
  board:SetPoint("TOP", parent, "TOP", 0, -62)
  local back = board:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  UI.Color(back, C.lineDark)

  cells = {}
  for i = 1, MAX_CELLS do
    local cell = CreateFrame("Button", nil, board)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell.bg = cell:CreateTexture(nil, "BORDER")
    cell.bg:SetPoint("TOPLEFT", 0, 0)
    cell.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    cell.top = cell:CreateTexture(nil, "ARTWORK")
    cell.top:SetPoint("TOPLEFT", 0, 0)
    cell.top:SetPoint("TOPRIGHT", -1, 0)
    cell.top:SetHeight(2)
    cell.top:SetColorTexture(1, 0.9, 0.7, 0.2)
    cell.hl = cell:CreateTexture(nil, "HIGHLIGHT")
    cell.hl:SetPoint("TOPLEFT", 0, 0)
    cell.hl:SetPoint("BOTTOMRIGHT", -1, 1)
    cell.hl:SetColorTexture(1, 0.85, 0.5, 0.14)
    cell.icon = cell:CreateTexture(nil, "ARTWORK", nil, 1)
    cell.icon:SetPoint("CENTER", -0.5, 0.5)
    cell.cross = cell:CreateTexture(nil, "OVERLAY")
    cell.cross:SetPoint("TOPLEFT", 0, 0)
    cell.cross:SetPoint("BOTTOMRIGHT", -1, 1)
    cell.cross:SetColorTexture(0.85, 0.15, 0.1, 0.45)
    cell.crossText = UI.Text(cell, 14, { 1, 0.3, 0.25 })
    cell.crossText:SetPoint("CENTER", -0.5, 0.5)
    cell.crossText:SetText("X")
    cell.num = UI.Text(cell, 14, NUMBER[1])
    cell.num:SetPoint("CENTER", -0.5, 0)
    cell:SetScript("OnClick", function(_, button) OnCell(i, button) end)
    cells[i] = cell
  end

  overlay = UI.Overlay(board)
  overlay.shade:SetColorTexture(0.03, 0.02, 0.01, 0.62)
  againButton = UI.Button(overlay.buttons, "Try again", 96, 24)
  againButton:SetPoint("CENTER", overlay.buttons, "CENTER", -52, 0)
  againButton:SetScript("OnClick", function()
    if game then NewGame(game.diff) end
  end)
  local viewButton = UI.Button(overlay.buttons, "View board", 96, 24)
  viewButton:SetPoint("CENTER", overlay.buttons, "CENTER", 52, 0)
  viewButton:SetScript("OnClick", function() overlay:Hide() end)

  toast = UI.Toast(board)

  sparkFrame = CreateFrame("Frame", nil, board)
  sparkFrame:SetAllPoints()
  sparkFrame:SetFrameLevel(board:GetFrameLevel() + 45)
  for k = 1, 10 do
    local tex = sparkFrame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(ns.MEDIA .. "dig\\relic")
    tex:SetSize(16, 16)
    tex:Hide()
    sparks[k] = { tex = tex, active = false, delay = 0, age = 0, life = 1, x = 0, y = 0, vy = 0 }
  end
  sparkFrame:SetScript("OnUpdate", function(_, dt) TickSparkles(dt) end)
  sparkFrame:Hide()

  -- The clock runs while a dig is under way and the game is open.
  local acc = 0
  parent:SetScript("OnUpdate", function(_, dt)
    if not game or game.status ~= "playing" then return end
    game.elapsed = game.elapsed + dt
    acc = acc + dt
    if acc >= 0.25 then
      acc = 0
      UpdateTimer()
    end
  end)

  if ValidGame(data.game) then
    game = data.game
    RebuildCounts()
    Layout()
    Render()
    ShowEnd()
  else
    data.game = nil
    NewGame("small")
  end
end

ns.RegisterGame({
  key = "digsite",
  name = "Dig Site",
  blurb = "Dig up the site without setting off the old traps.",
  icon = ns.MEDIA .. "icons\\digsite",
  order = 40,
  hasWins = true,
  Create = Create,
  OnHide = function() if sparkFrame then StopSparkles() end end,
  InProgress = function(d)
    local g = type(d) == "table" and d.game or nil
    if not ValidGame(g) then return false end
    return g.status == "playing"
  end,
  Summary = function(d)
    local s = d.stats
    local best = s.best_large and ("Large " .. ns.FormatTime(s.best_large))
      or s.best_medium and ("Medium " .. ns.FormatTime(s.best_medium))
      or s.best_small and ("Small " .. ns.FormatTime(s.best_small))
    return best or ""
  end,
})
