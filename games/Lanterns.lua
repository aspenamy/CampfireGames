-------------------------------------------------------------------------------
-- Campfire Games: Lanterns
--
-- Every lantern starts lit. Click one to flip it and the four lanterns
-- next to it (up, down, left, right). Light them all. Levels 1 to 10 are
-- 5x5, then 6x6. Stars: 3 if you use par moves or fewer, 2 if within 3
-- of par, otherwise 1. Undo takes back the last click.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor = math.floor

local BOARD = 252                 -- square area the grid is centered in
local BOARD_X, BOARD_Y = floor((ns.GAME_W - BOARD) / 2), -30
local MAX_CELLS = 36              -- 6x6
local CELEBRATE = 0.6             -- seconds the lanterns pulse on a solve
local BIG_FROM = 11               -- first level on the 6x6 grid

local LIT = ns.MEDIA .. "lanterns\\lit"
local UNLIT = ns.MEDIA .. "lanterns\\unlit"
-- The lit art has a square halo painted into it, so a lit lantern is drawn as
-- the clean unlit silhouette (tinted dark) with only the lit window on top.
local WIN_L, WIN_R, WIN_T, WIN_B = 22, 42, 24, 47   -- window, in 64px art
local GLOW = ns.MEDIA .. "dot"
local SPARK = ns.MEDIA .. "gems\\spark"

local data                        -- saved: data.level, start, state, presses, par, solved, stars
local panel, board, levelText, statsText, restartBtn, undoBtn
local cells, glows = {}, {}
local overlay, starRow, starPips, nextBtn
local laidOut                     -- grid size the cells are placed for
local celebrating = false
local celebrateT = 0

-------------------------------------------------------------------------------
-- Levels
-------------------------------------------------------------------------------

local function SizeOf(level)
  if level >= BIG_FROM then return 6 end
  return 5
end

-- Level 1 has 3 presses, one more per level, capped by the grid.
local function PressesFor(level)
  local cap = SizeOf(level) == 6 and 15 or 12
  return math.min(cap, level + 2)
end

local function Flip(state, n, r, c)
  if r >= 0 and r < n and c >= 0 and c < n then
    local k = r * n + c + 1
    state[k] = 1 - state[k]
  end
end

-- Flips lantern i and its four orthogonal neighbors.
local function Toggle(state, n, i)
  local r, c = floor((i - 1) / n), (i - 1) % n
  Flip(state, n, r, c)
  Flip(state, n, r - 1, c)
  Flip(state, n, r + 1, c)
  Flip(state, n, r, c - 1)
  Flip(state, n, r, c + 1)
end

local function AllLit(state)
  for i = 1, #state do
    if state[i] ~= 1 then return false end
  end
  return true
end

local function Copy(t)
  local out = {}
  for i = 1, #t do out[i] = t[i] end
  return out
end

-- Starts all lit, then presses a set of distinct random lanterns. The
-- returned state is the level's start; the same presses solve it.
local function NewBoard(level)
  local n = SizeOf(level)
  local total = n * n
  local k = PressesFor(level)
  local state
  for _ = 1, 100 do
    local order = {}
    for i = 1, total do order[i] = i end
    ns.Shuffle(order)
    state = {}
    for i = 1, total do state[i] = 1 end
    for j = 1, k do Toggle(state, n, order[j]) end
    if not AllLit(state) then break end
  end
  return state, k
end

local function StarsFor(moves, par)
  if moves <= par then return 3 end
  if moves <= par + 3 then return 2 end
  return 1
end

local function Fresh()
  local start, par = NewBoard(data.level)
  data.start = start
  data.state = Copy(start)
  data.presses = {}
  data.par = par
  data.solved = false
end

-- Saved board must match its level and replay cleanly from its start.
local function ValidBoard(d)
  local n = SizeOf(d.level)
  local total = n * n
  if type(d.start) ~= "table" or #d.start ~= total then return false end
  if type(d.state) ~= "table" or #d.state ~= total then return false end
  if type(d.presses) ~= "table" or type(d.par) ~= "number" then return false end
  for i = 1, total do
    local a, b = d.start[i], d.state[i]
    if (a ~= 0 and a ~= 1) or (b ~= 0 and b ~= 1) then return false end
  end
  local replay = Copy(d.start)
  for _, p in ipairs(d.presses) do
    if type(p) ~= "number" or p < 1 or p > total or p ~= floor(p) then return false end
    Toggle(replay, n, p)
  end
  for i = 1, total do
    if replay[i] ~= d.state[i] then return false end
  end
  if d.solved and not AllLit(d.state) then return false end
  return true
end

local function LoadSaved()
  if type(data.stars) ~= "number" or data.stars < 0 then data.stars = 0 end
  data.stars = floor(data.stars)
  if type(data.level) ~= "number" or data.level < 1 or data.level ~= floor(data.level) then
    data.level = 1
    Fresh()
    return
  end
  data.solved = data.solved == true
  if not ValidBoard(data) then
    Fresh()
  end
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function Layout(n)
  if laidOut == n then return end
  laidOut = n
  local cell = n == 5 and 48 or 42
  local off = floor((BOARD - n * cell) / 2)
  for i = 1, MAX_CELLS do
    local b, glow = cells[i], glows[i]
    if i <= n * n then
      local r, c = floor((i - 1) / n), (i - 1) % n
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", board, "TOPLEFT", off + c * cell, -(off + r * cell))
      b:SetSize(cell, cell)
      b:Show()
      glow:ClearAllPoints()
      glow:SetPoint("CENTER", b, "CENTER", 0, 0)
      -- Soft light about 1.6x the cell, kept from spilling past the board.
      local reach = off + cell / 2
      local size = math.min(cell * 1.6, reach * 2 - 2)
      glow:SetSize(size, size)
      local k = (cell - 6) / 64
      b.win:ClearAllPoints()
      b.win:SetPoint("TOPLEFT", b.art, "TOPLEFT", WIN_L * k, -WIN_T * k)
      b.win:SetSize((WIN_R - WIN_L) * k, (WIN_B - WIN_T) * k)
    else
      b:Hide()
      glow:Hide()
    end
  end
end

local function Render()
  if not data then return end
  local n = SizeOf(data.level)
  Layout(n)
  levelText:SetText(format("Level %d", data.level))
  statsText:SetText(format("Moves %d   Par %d", #data.presses, data.par))
  for i = 1, n * n do
    local lit = data.state[i] == 1
    if lit then
      cells[i].art:SetVertexColor(0.5, 0.4, 0.33, 1)
    else
      cells[i].art:SetVertexColor(1, 1, 1, 1)
    end
    cells[i].win:SetShown(lit)
    glows[i]:SetShown(lit)
  end
end

local function SetFlash(a)
  for i = 1, MAX_CELLS do cells[i].flash:SetAlpha(a) end
end

local function ShowSolved()
  local moves, par = #data.presses, data.par
  local earned = StarsFor(moves, par)
  for k = 1, 3 do
    local pip = starPips[k]
    if k <= earned then
      pip:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
    else
      pip:SetVertexColor(C.faint[1], C.faint[2], C.faint[3], 0.6)
    end
  end
  overlay:Open(format("Level %d lit", data.level),
    format("%d %s, par %d", moves, moves == 1 and "move" or "moves", par))
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function Win()
  local moves, par = #data.presses, data.par
  data.solved = true
  data.stars = data.stars + StarsFor(moves, par)
  ns.RecordResult("lanterns", { won = true, score = data.level })
  ns.Sound("win")
  celebrating = true
  celebrateT = 0
  Render()
end

local function PressCell(i)
  if not data or celebrating or data.solved then return end
  Toggle(data.state, SizeOf(data.level), i)
  data.presses[#data.presses + 1] = i
  ns.Sound("place")
  if AllLit(data.state) then
    Win()
    return
  end
  Render()
end

local function Undo()
  if not data or celebrating or data.solved or #data.presses == 0 then return end
  local i = table.remove(data.presses)
  Toggle(data.state, SizeOf(data.level), i)
  Render()
end

local function Restart()
  if not data or celebrating or data.solved then return end
  data.state = Copy(data.start)
  data.presses = {}
  Render()
end

local function NextLevel()
  if not data or not data.solved then return end
  data.level = data.level + 1
  Fresh()
  overlay:Close()
  Render()
end

StaticPopupDialogs["DOWNTIME_LANTERNS_RESTART"] = {
  text = "Start this level over? Your moves will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function() Restart() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function Create(parent, saved)
  data = saved
  panel = parent
  LoadSaved()

  board = UI.Inset(parent, BOARD, BOARD)
  board:SetPoint("TOPLEFT", BOARD_X, BOARD_Y)

  -- A darker well sunk into the board.
  local well = board:CreateTexture(nil, "BACKGROUND", nil, 1)
  well:SetPoint("TOPLEFT", 3, -3)
  well:SetPoint("BOTTOMRIGHT", -3, 3)
  well:SetColorTexture(0.02, 0.012, 0.008, 0.7)
  local shadeT = board:CreateTexture(nil, "BACKGROUND", nil, 2)
  shadeT:SetPoint("TOPLEFT", 3, -3)
  shadeT:SetPoint("TOPRIGHT", -3, -3)
  shadeT:SetHeight(2)
  shadeT:SetColorTexture(0, 0, 0, 0.5)
  local shadeL = board:CreateTexture(nil, "BACKGROUND", nil, 2)
  shadeL:SetPoint("TOPLEFT", 3, -3)
  shadeL:SetPoint("BOTTOMLEFT", 3, 3)
  shadeL:SetWidth(2)
  shadeL:SetColorTexture(0, 0, 0, 0.4)

  -- Glows go under the lanterns (created first so buttons draw above them).
  for i = 1, MAX_CELLS do
    local glow = board:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(GLOW)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(C.ember[1], C.ember[2], C.ember[3], 0.55)
    glows[i] = glow
  end

  for i = 1, MAX_CELLS do
    local b = CreateFrame("Button", nil, board)
    b:SetSize(48, 48)
    b:RegisterForClicks("LeftButtonUp")
    b.art = b:CreateTexture(nil, "ARTWORK")
    b.art:SetPoint("TOPLEFT", 3, -3)
    b.art:SetPoint("BOTTOMRIGHT", -3, 3)
    b.art:SetTexture(UNLIT)
    b.win = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.win:SetTexture(LIT)
    b.win:SetTexCoord(WIN_L / 64, WIN_R / 64, WIN_T / 64, WIN_B / 64)
    b.flash = b:CreateTexture(nil, "OVERLAY")
    b.flash:SetAllPoints(b.art)
    b.flash:SetTexture(GLOW)
    b.flash:SetBlendMode("ADD")
    b.flash:SetVertexColor(1, 0.9, 0.65, 1)
    b.flash:SetAlpha(0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.85, 0.5, 0.12)
    b:SetScript("OnClick", function() PressCell(i) end)
    cells[i] = b
  end

  -- The pulse runs only while the board is shown.
  board:SetScript("OnUpdate", function(_, dt)
    if not celebrating then return end
    celebrateT = celebrateT + dt
    local p = celebrateT / CELEBRATE
    if p >= 1 then
      celebrating = false
      SetFlash(0)
      ShowSolved()
    else
      SetFlash(math.sin(p * math.pi) * 0.6)
    end
  end)

  levelText = UI.Title(parent, 15)
  levelText:SetPoint("TOPLEFT", BOARD_X, -6)
  statsText = UI.Text(parent, 12, C.cream)
  statsText:SetPoint("TOPRIGHT", -BOARD_X, -9)

  restartBtn = UI.Button(parent, "Restart level", 116, 22)
  restartBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 51, -296)
  restartBtn:SetScript("OnClick", function()
    if not data or celebrating or data.solved then return end
    if #data.presses > 0 then
      StaticPopup_Show("DOWNTIME_LANTERNS_RESTART")
    else
      Restart()
    end
  end)

  undoBtn = UI.Button(parent, "Undo", 96, 22)
  undoBtn:SetPoint("LEFT", restartBtn, "RIGHT", 6, 0)
  undoBtn:SetScript("OnClick", Undo)

  overlay = UI.Overlay(parent)
  starRow = CreateFrame("Frame", nil, overlay)
  starRow:SetSize(82, 22)
  starRow:SetPoint("TOP", overlay.line, "BOTTOM", 0, -12)
  starPips = {}
  for k = 1, 3 do
    local pip = starRow:CreateTexture(nil, "ARTWORK")
    pip:SetSize(22, 22)
    pip:SetPoint("LEFT", starRow, "LEFT", (k - 1) * 30, 0)
    pip:SetTexture(SPARK)
    starPips[k] = pip
  end
  overlay.buttons:ClearAllPoints()
  overlay.buttons:SetPoint("TOP", starRow, "BOTTOM", 0, -12)
  nextBtn = UI.Button(overlay.buttons, "Next level", 120, 24)
  nextBtn:SetPoint("CENTER", overlay.buttons, "CENTER", 0, 0)
  nextBtn:SetScript("OnClick", NextLevel)

  Render()
  if data.solved then ShowSolved() end
end

ns.RegisterGame({
  key = "lanterns",
  name = "Lanterns",
  blurb = "Light every lantern. Each one you touch flips its neighbors.",
  icon = ns.MEDIA .. "icons\\lanterns",
  order = 60,
  hasWins = true,
  Create = Create,
  OnShow = function()
    if data and data.solved and not celebrating then ShowSolved() end
  end,
  OnHide = function()
    if celebrating then
      celebrating = false
      SetFlash(0)
    end
  end,
  InProgress = function(d)
    if type(d) ~= "table" or type(d.level) ~= "number" then return false end
    if d.level < 1 or d.level ~= floor(d.level) then return false end
    if d.solved == true or type(d.presses) ~= "table" or #d.presses == 0 then return false end
    return ValidBoard(d) and true or false
  end,
  Summary = function(d)
    if (d.stats and d.stats.played or 0) == 0 and (d.level or 1) <= 1 then return "" end
    local stars = d.stars or 0
    return format("Level %d, %d %s", d.level or 1, stars, stars == 1 and "star" or "stars")
  end,
})
