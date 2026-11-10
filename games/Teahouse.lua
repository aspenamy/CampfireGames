-------------------------------------------------------------------------------
-- Campfire Games: Teahouse Tiles
--
-- Tiles are stacked in a heap. A tile is free when nothing lies on top of it
-- and its left or right side is open. Click a free tile, then a free tile with
-- the same picture, and both leave the table. Clear every tile to win.
-- Hint shows a pair that keeps the table solvable, Undo puts a pair back, and
-- Shuffle appears when no free pairs are left. Every deal can be cleared.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, sin = math.floor, math.sin

local TW, TH = 30, 38        -- tile size
local HX, HY = 15, 19        -- half a tile, the grid step
local LIFT = 3               -- each layer sits this far up and left
local AREA_H = 270
local MAX_UNDO = 100
local FADE = 0.25
local HINT_TIME = 2.5

-- layer, row, first column, last column (in tiles)
local LAYOUT_ROWS = {
  teahouse = {
    { 0, 0, 3, 6 }, { 0, 1, 1, 8 }, { 0, 2, 1, 8 }, { 0, 3, 1, 8 }, { 0, 4, 1, 8 }, { 0, 5, 3, 6 },
    { 1, 1, 3, 6 }, { 1, 2, 2, 7 }, { 1, 3, 2, 7 }, { 1, 4, 3, 6 },
    { 2, 2, 3, 6 }, { 2, 3, 3, 6 },
    { 3, 2, 4, 5 }, { 3, 3, 4, 5 },
  },
  quick = {
    { 0, 0, 2, 5 }, { 0, 1, 1, 6 }, { 0, 2, 1, 6 }, { 0, 3, 2, 5 },
    { 1, 0, 3, 4 }, { 1, 1, 2, 5 }, { 1, 2, 2, 5 }, { 1, 3, 3, 4 },
    { 2, 1, 3, 4 }, { 2, 2, 3, 4 },
  },
}
local LAYOUT_LABEL = { teahouse = "Teahouse", quick = "Quick" }
local CHOICES = {
  { key = "teahouse", label = "Teahouse" },
  { key = "quick", label = "Quick" },
}

local COLOR = {
  face     = { 0.95, 0.91, 0.78 },
  faceDim  = { 0.68, 0.64, 0.53 },
  side     = { 0.50, 0.40, 0.26 },
  edge     = { 0.14, 0.09, 0.05 },
  shine    = { 1.00, 0.98, 0.90 },
}

local data, g
local panel, board, buttons, overlay, toast, leftText, timeText, statusText
local hintButton, undoButton, shuffleButton, choiceRow
local selected
local hintLeft = 0
local freePairs = true
local SYMS = {}
local LAY = {}

-------------------------------------------------------------------------------
-- Layouts
-------------------------------------------------------------------------------

-- Builds positions (sorted by layer, row, column) and what blocks what.
local function BuildLayout(rows)
  local P = { l = {}, x = {}, y = {}, above = {}, left = {}, right = {} }
  local list = {}
  for _, r in ipairs(rows) do
    for c = r[3], r[4] do list[#list + 1] = { l = r[1], y = r[2] * 2, x = c * 2 } end
  end
  table.sort(list, function(a, b)
    if a.l ~= b.l then return a.l < b.l end
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
  end)
  local n = #list
  P.n = n
  for i, p in ipairs(list) do
    P.l[i], P.x[i], P.y[i] = p.l, p.x, p.y
    P.above[i], P.left[i], P.right[i] = {}, {}, {}
  end
  for i = 1, n do
    for j = 1, n do
      if j ~= i then
        local dx, dy = P.x[j] - P.x[i], P.y[j] - P.y[i]
        if math.abs(dy) < 2 then
          if P.l[j] > P.l[i] and math.abs(dx) < 2 then
            table.insert(P.above[i], j)
          elseif P.l[j] == P.l[i] and dx == -2 then
            table.insert(P.left[i], j)
          elseif P.l[j] == P.l[i] and dx == 2 then
            table.insert(P.right[i], j)
          end
        end
      end
    end
  end
  -- Pixel box of every tile, and the box around all of them.
  local minx, miny, maxx, maxy = 9999, 9999, -9999, -9999
  P.px, P.py = {}, {}
  for i = 1, n do
    local px, py = P.x[i] * HX - P.l[i] * LIFT, P.y[i] * HY - P.l[i] * LIFT
    P.px[i], P.py[i] = px, py
    minx, miny = math.min(minx, px), math.min(miny, py)
    maxx, maxy = math.max(maxx, px + TW + 4), math.max(maxy, py + TH + 4)
  end
  P.ox = floor((ns.GAME_W - (maxx - minx)) / 2 - minx)
  P.oy = floor((AREA_H - (maxy - miny)) / 2 - miny)
  return P
end

-------------------------------------------------------------------------------
-- Rules and dealing (t is a list of symbols by position, 0 once removed)
-------------------------------------------------------------------------------

local function IsFree(P, t, i)
  if t[i] == 0 then return false end
  local a = P.above[i]
  for k = 1, #a do
    if t[a[k]] ~= 0 then return false end
  end
  local l, r = false, false
  a = P.left[i]
  for k = 1, #a do
    if t[a[k]] ~= 0 then l = true break end
  end
  if not l then return true end
  a = P.right[i]
  for k = 1, #a do
    if t[a[k]] ~= 0 then r = true break end
  end
  return not r
end

-- Every pair of free tiles with the same picture, as { a, b }.
local function FreePairs(P, t)
  local by, out = {}, {}
  for i = 1, P.n do
    if IsFree(P, t, i) then
      local s = t[i]
      local lst = by[s]
      if not lst then
        by[s] = { i }
      else
        for k = 1, #lst do out[#out + 1] = { lst[k], i } end
        lst[#lst + 1] = i
      end
    end
  end
  return out
end

local function Copy(t)
  local o = {}
  for i = 1, #t do o[i] = t[i] end
  return o
end

local function CountLeft(t)
  local n = 0
  for i = 1, #t do
    if t[i] ~= 0 then n = n + 1 end
  end
  return n
end

-- Takes pairs of free tiles off the full heap, in order. Played in that
-- order, any pictures put on the pairs can be cleared.
local function PlanPairs(P, inc)
  local t, left = {}, 0
  for i = 1, P.n do
    t[i] = inc[i] and 1 or 0
    left = left + t[i]
  end
  local plan = {}
  while left > 0 do
    local free = {}
    for i = 1, P.n do
      if IsFree(P, t, i) then free[#free + 1] = i end
    end
    if #free < 2 then return nil end
    local a = table.remove(free, math.random(#free))
    local b = table.remove(free, math.random(#free))
    plan[#plan + 1] = { a, b }
    t[a], t[b] = 0, 0
    left = left - 2
  end
  return plan
end

-- Plays the plan on the dealt tiles to be sure it clears.
local function Replay(P, t, plan)
  t = Copy(t)
  for _, p in ipairs(plan) do
    local a, b = p[1], p[2]
    if t[a] ~= t[b] or not IsFree(P, t, a) or not IsFree(P, t, b) then return false end
    t[a], t[b] = 0, 0
  end
  return CountLeft(t) == 0
end

-- pairSyms: one entry per pair to place. Returns the tiles, or nil.
local function Deal(P, inc, pairSyms)
  for _ = 1, 60 do
    local plan = PlanPairs(P, inc)
    if plan then
      ns.Shuffle(pairSyms)
      local t = {}
      for i = 1, P.n do t[i] = 0 end
      for k, p in ipairs(plan) do
        t[p[1]], t[p[2]] = pairSyms[k], pairSyms[k]
      end
      if Replay(P, t, plan) then return t end
    end
  end
end

-- One quick greedy game from here; true when it clears the table.
local function Rollout(P, t)
  local left = CountLeft(t)
  while left > 0 do
    local pairs_ = FreePairs(P, t)
    if #pairs_ == 0 then return false end
    local pick
    if math.random() < 0.7 then
      local best = -1
      for _, p in ipairs(pairs_) do
        local score = P.l[p[1]] + P.l[p[2]] + math.random() * 0.9
        if score > best then best, pick = score, p end
      end
    else
      pick = pairs_[math.random(#pairs_)]
    end
    t[pick[1]], t[pick[2]] = 0, 0
    left = left - 2
  end
  return true
end

-- A free pair after which the table still seems clearable (or any free pair).
local function SafePair(P, t)
  local list = ns.Shuffle(FreePairs(P, t))
  if #list == 0 then return nil end
  for k = 1, math.min(#list, 6) do
    local p = list[k]
    for _ = 1, 5 do
      local c = Copy(t)
      c[p[1]], c[p[2]] = 0, 0
      if Rollout(P, c) then return p end
    end
  end
  return list[1]
end

-------------------------------------------------------------------------------
-- Saved game
-------------------------------------------------------------------------------

local function ValidGame(s)
  if type(s) ~= "table" or not LAYOUT_ROWS[s.layout] then return false end
  local P = LAY[s.layout]
  if type(s.tiles) ~= "table" or #s.tiles ~= P.n then return false end
  local counts = {}
  for i = 1, P.n do
    local v = s.tiles[i]
    if type(v) ~= "number" or v < 0 or v > #SYMS or v ~= floor(v) then return false end
    if v > 0 then counts[v] = (counts[v] or 0) + 1 end
  end
  for _, c in pairs(counts) do
    if c % 2 ~= 0 then return false end
  end
  if type(s.elapsed) ~= "number" or s.elapsed < 0 then s.elapsed = 0 end
  if type(s.hints) ~= "number" then s.hints = 0 end
  if CountLeft(s.tiles) == 0 then s.won = true end
  s.won = s.won and true or false
  s.hintA, s.hintB = nil, nil
  local u, ok = s.undo, true
  if type(u) ~= "table" or #u % 3 ~= 0 then
    ok = false
  else
    for k = 1, #u, 3 do
      local a, b, v = u[k], u[k + 1], u[k + 2]
      if type(a) ~= "number" or type(b) ~= "number" or type(v) ~= "number"
        or a < 1 or a > P.n or b < 1 or b > P.n or a == b or v < 1 or v > #SYMS then
        ok = false
        break
      end
    end
  end
  if not ok then s.undo = {} end
  while #s.undo > MAX_UNDO * 3 do
    table.remove(s.undo, 1); table.remove(s.undo, 1); table.remove(s.undo, 1)
  end
  return true
end

local function Progress()
  return g ~= nil and not g.won and CountLeft(g.tiles) < #g.tiles
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function UpdateTime()
  if not g then return end
  timeText:SetText(ns.FormatTime(g.elapsed))
end

local function SetSelBorder(t, on)
  for i = 1, 4 do t.sel[i]:SetShown(on) end
end

local function Render()
  if not g then return end
  local P = LAY[g.layout]
  local t = g.tiles
  local by = {}
  freePairs = false
  for i = 1, P.n do
    local b = buttons[i]
    local sym = t[i]
    if sym == 0 then
      b:EnableMouse(false)
      SetSelBorder(b, false)
      if not b.fade then b:Hide() end
    else
      b.fade = nil
      b:SetAlpha(1)
      if hintLeft <= 0 then b.glow:SetAlpha(0) end
      b:EnableMouse(true)
      b:Show()
      local free = IsFree(P, t, i)
      b.free = free
      b.symTex:SetTexture(SYMS[sym])
      b.symTex:SetAlpha(free and 1 or 0.75)
      local fc = free and COLOR.face or COLOR.faceDim
      b.face:SetColorTexture(fc[1], fc[2], fc[3], 1)
      b.symTex:SetVertexColor(1, 1, 1)
      if not free then b.symTex:SetVertexColor(0.8, 0.8, 0.8) end
      SetSelBorder(b, i == selected)
      if free then
        by[sym] = (by[sym] or 0) + 1
        if by[sym] >= 2 then freePairs = true end
      end
    end
  end
  leftText:SetText("Tiles left: " .. CountLeft(t))
  UpdateTime()
  choiceRow:Select(g.layout)
  undoButton[#g.undo > 0 and not g.won and "Enable" or "Disable"](undoButton)
  undoButton:Paint()
  local canShuffle = not g.won and not freePairs
  shuffleButton[canShuffle and "Enable" or "Disable"](shuffleButton)
  shuffleButton:Paint()
  hintButton[(not g.won and freePairs) and "Enable" or "Disable"](hintButton)
  hintButton:Paint()
  if canShuffle then
    statusText:SetText("No free pairs left. Shuffle the tiles or undo.")
  else
    statusText:SetText("")
  end
end

-- Puts the buttons where the current layout wants them.
local function ApplyLayout()
  local P = LAY[g.layout]
  local base = board:GetFrameLevel() + 2
  for i = 1, #buttons do
    local b = buttons[i]
    b.fade = nil
    if i <= P.n then
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", board, "TOPLEFT", P.ox + P.px[i], -(P.oy + P.py[i]))
      b:SetFrameLevel(base + i)
    else
      b:Hide()
      b:EnableMouse(false)
    end
  end
end

local function ShowGame()
  selected = nil
  hintLeft = 0
  overlay:Close()
  ApplyLayout()
  Render()
  if g.won then
    local best = data.stats["best_" .. g.layout]
    overlay:Open("The table is clear!", format("%s in %s\nBest: %s",
      LAYOUT_LABEL[g.layout], ns.FormatTime(g.elapsed), best and ns.FormatTime(best) or "-"))
  end
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function Win()
  g.won = true
  local newBest = ns.RecordResult("teahouse", {
    won = true, time = floor(g.elapsed), lowerIsBetter = true, bestKey = "best_" .. g.layout,
  })
  ns.PlayTone("chime")
  selected = nil
  hintLeft = 0
  g.hintA, g.hintB = nil, nil
  Render()
  local best = data.stats["best_" .. g.layout]
  local line = format("%s in %s\nBest: %s", LAYOUT_LABEL[g.layout], ns.FormatTime(g.elapsed),
    best and ns.FormatTime(best) or "-")
  if g.hints > 0 then line = line .. format("\nHints used: %d", g.hints) end
  overlay:Open(newBest and "A new best!" or "The table is clear!", line)
end

local function Remove(a, b)
  local t = g.tiles
  local u = g.undo
  u[#u + 1] = a
  u[#u + 1] = b
  u[#u + 1] = t[a]
  while #u > MAX_UNDO * 3 do
    table.remove(u, 1); table.remove(u, 1); table.remove(u, 1)
  end
  for _, i in ipairs({ a, b }) do
    buttons[i].fade = FADE
    t[i] = 0
  end
  selected = nil
  hintLeft = 0
  g.hintA, g.hintB = nil, nil
  ns.Sound("place")
  if CountLeft(t) == 0 then
    Win()
  else
    Render()
  end
end

local function Click(i)
  if not g or g.won or g.tiles[i] == 0 then return end
  local P = LAY[g.layout]
  if not IsFree(P, g.tiles, i) then
    ns.Sound("bad")
    return
  end
  if selected == i then
    selected = nil
    ns.Sound("click")
  elseif selected and g.tiles[selected] == g.tiles[i] then
    Remove(selected, i)
    return
  else
    selected = i
    ns.Sound("click")
  end
  hintLeft = 0
  g.hintA, g.hintB = nil, nil
  Render()
end

local function Undo()
  if not g or g.won or #g.undo == 0 then return end
  local u = g.undo
  local v = table.remove(u)
  local b = table.remove(u)
  local a = table.remove(u)
  g.tiles[a], g.tiles[b] = v, v
  selected = nil
  hintLeft = 0
  g.hintA, g.hintB = nil, nil
  ns.Sound("page")
  Render()
end

local function Hint()
  if not g or g.won then return end
  local p = SafePair(LAY[g.layout], g.tiles)
  if not p then return end
  g.hints = g.hints + 1
  g.hintA, g.hintB = p[1], p[2]
  hintLeft = HINT_TIME
  ns.Sound("good")
end

local function Reshuffle()
  if not g or g.won or freePairs then return end
  local P = LAY[g.layout]
  local t = g.tiles
  local inc, counts, order = {}, {}, {}
  for i = 1, P.n do
    if t[i] ~= 0 then
      inc[i] = true
      counts[t[i]] = (counts[t[i]] or 0) + 1
      order[#order + 1] = i
    end
  end
  local pairSyms = {}
  for s, c in pairs(counts) do
    for _ = 1, c / 2 do pairSyms[#pairSyms + 1] = s end
  end
  local new = Deal(P, inc, pairSyms)
  if not new then
    -- Could not keep it clearable; just mix the pictures.
    local syms = {}
    for _, i in ipairs(order) do syms[#syms + 1] = t[i] end
    ns.Shuffle(syms)
    new = {}
    for i = 1, P.n do new[i] = 0 end
    for k, i in ipairs(order) do new[i] = syms[k] end
  end
  g.tiles = new
  g.undo = {}
  selected = nil
  hintLeft = 0
  g.hintA, g.hintB = nil, nil
  ns.Sound("page")
  Render()
end

local function Start(layout)
  if g and Progress() then
    ns.RecordResult("teahouse", { won = false })
  end
  local P = LAY[layout]
  local pool = {}
  for i = 1, #SYMS do pool[i] = i end
  ns.Shuffle(pool)
  local pairSyms, inc = {}, {}
  for k = 1, P.n / 4 do
    pairSyms[#pairSyms + 1] = pool[k]
    pairSyms[#pairSyms + 1] = pool[k]
  end
  for i = 1, P.n do inc[i] = true end
  -- Four of each picture: two pairs apiece.
  local t = Deal(P, inc, ns.CopyList(pairSyms))
  if not t then
    t = {}
    local flat = {}
    for _, s in ipairs(pairSyms) do flat[#flat + 1] = s; flat[#flat + 1] = s end
    ns.Shuffle(flat)
    for i = 1, P.n do t[i] = flat[i] end
  end
  g = { layout = layout, tiles = t, elapsed = 0, hints = 0, undo = {}, won = false }
  data.game = g
  ShowGame()
end

StaticPopupDialogs["DOWNTIME_NEW_TEAHOUSE"] = {
  text = "Start a new game? This one will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, d) Start(d or (g and g.layout) or "teahouse") end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function AskNew(layout)
  if Progress() then
    StaticPopup_Show("DOWNTIME_NEW_TEAHOUSE", nil, nil, layout)
  else
    Start(layout)
  end
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function MakeTile(parent, i)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(TW, TH)
  local edge = b:CreateTexture(nil, "BACKGROUND", nil, 0)
  edge:SetPoint("TOPLEFT", 0, 0)
  edge:SetPoint("BOTTOMRIGHT", 4, -4)
  UI.Color(edge, COLOR.edge)
  local side = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  side:SetPoint("TOPLEFT", 1, -1)
  side:SetPoint("BOTTOMRIGHT", 3, -3)
  UI.Color(side, COLOR.side)
  b.face = b:CreateTexture(nil, "ARTWORK", nil, 0)
  b.face:SetAllPoints()
  UI.Color(b.face, COLOR.face)
  b.symTex = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.symTex:SetSize(22, 22)
  b.symTex:SetPoint("CENTER", 0, 0)
  local shine = b:CreateTexture(nil, "ARTWORK", nil, 2)
  shine:SetPoint("TOPLEFT", 1, -1)
  shine:SetPoint("TOPRIGHT", -1, -1)
  shine:SetHeight(1)
  shine:SetColorTexture(COLOR.shine[1], COLOR.shine[2], COLOR.shine[3], 0.6)
  UI.Border(b, COLOR.edge, 1, "OVERLAY")
  b.sel = UI.Border(b, C.gold, 2, "OVERLAY")
  SetSelBorder(b, false)
  b.glow = b:CreateTexture(nil, "OVERLAY", nil, 2)
  b.glow:SetAllPoints()
  b.glow:SetColorTexture(1, 0.8, 0.3, 1)
  b.glow:SetAlpha(0)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.9, 0.6, 0.15)
  b:SetScript("OnClick", function() Click(i) end)
  return b
end

local function Create(parent, saved)
  panel = parent
  data = saved

  SYMS = {}
  for i = 1, 6 do SYMS[#SYMS + 1] = ns.MEDIA .. "gems\\gem" .. i end
  for i = 1, 6 do SYMS[#SYMS + 1] = ns.MEDIA .. "runes\\rune" .. i end
  -- Skip the moon (p5) and star (p6): the raid marks below have their own.
  for i = 1, 10 do
    if i ~= 5 and i ~= 6 then SYMS[#SYMS + 1] = ns.MEDIA .. "pairs\\p" .. i end
  end
  for _, s in ipairs({ "spade", "heart", "diamond", "club" }) do
    SYMS[#SYMS + 1] = ns.MEDIA .. "cards\\" .. s
  end
  for i = 1, 8 do SYMS[#SYMS + 1] = ns.RAID_MARKS[i] end
  for k, rows in pairs(LAYOUT_ROWS) do LAY[k] = BuildLayout(rows) end

  leftText = UI.Title(parent, 14)
  leftText:SetPoint("TOPLEFT", 8, -2)
  timeText = UI.Text(parent, 12, C.cream)
  timeText:SetPoint("TOPRIGHT", -8, -3)

  board = CreateFrame("Frame", nil, parent)
  board:SetSize(ns.GAME_W, AREA_H)
  board:SetPoint("TOPLEFT", 0, -24)

  buttons = {}
  local maxN = 0
  for _, P in pairs(LAY) do maxN = math.max(maxN, P.n) end
  for i = 1, maxN do
    buttons[i] = MakeTile(board, i)
    buttons[i]:Hide()
  end

  -- The win cover sits above every tile.
  local top = CreateFrame("Frame", nil, board)
  top:SetSize(ns.GAME_W, AREA_H)
  top:SetPoint("TOPLEFT", 0, 0)
  top:SetFrameLevel(board:GetFrameLevel() + maxN + 20)
  overlay = UI.Overlay(top)
  toast = UI.Toast(top)
  local again = UI.Button(overlay.buttons, "Play again", 110, 24)
  again:SetPoint("TOP", 0, 0)
  again:SetScript("OnClick", function() Start(g and g.layout or "teahouse") end)

  choiceRow = UI.Choice(parent, CHOICES, 308, function(key) AskNew(key) end)
  choiceRow:SetPoint("TOPLEFT", board, "BOTTOMLEFT", 6, -8)

  hintButton = UI.Button(parent, "Hint", 74, 22)
  hintButton:SetPoint("TOPLEFT", choiceRow, "BOTTOMLEFT", 0, -8)
  hintButton:SetScript("OnClick", function() Hint(); Render() end)
  UI.Tooltip(hintButton, "Hint", "Shows a pair you can remove safely.")
  undoButton = UI.Button(parent, "Undo", 74, 22)
  undoButton:SetPoint("LEFT", hintButton, "RIGHT", 4, 0)
  undoButton:SetScript("OnClick", Undo)
  shuffleButton = UI.Button(parent, "Shuffle", 74, 22)
  shuffleButton:SetPoint("LEFT", undoButton, "RIGHT", 4, 0)
  shuffleButton:SetScript("OnClick", Reshuffle)
  UI.Tooltip(shuffleButton, "Shuffle", "Mixes the pictures when no free pairs are left.")
  local newButton = UI.Button(parent, "New game", 74, 22)
  newButton:SetPoint("LEFT", shuffleButton, "RIGHT", 4, 0)
  newButton:SetScript("OnClick", function() AskNew(g and g.layout or "teahouse") end)

  statusText = UI.Text(parent, 11, C.dim)
  statusText:SetPoint("TOP", hintButton, "BOTTOM", 120, -12)
  statusText:SetWidth(300)
  statusText:SetJustifyH("CENTER")

  local acc = 0
  parent:SetScript("OnUpdate", function(_, dt)
    if not g then return end
    local P = LAY[g.layout]
    if not g.won then
      g.elapsed = g.elapsed + dt
      acc = acc + dt
      if acc >= 0.25 then
        acc = 0
        UpdateTime()
      end
    end
    for i = 1, P.n do
      local b = buttons[i]
      if b.fade then
        b.fade = b.fade - dt
        if b.fade <= 0 then
          b.fade = nil
          b:Hide()
        else
          b:SetAlpha(b.fade / FADE)
        end
      end
    end
    if hintLeft > 0 then
      hintLeft = hintLeft - dt
      local a = hintLeft > 0 and (0.22 + 0.18 * sin(hintLeft * 7)) or 0
      for _, i in ipairs({ g.hintA or 0, g.hintB or 0 }) do
        if buttons[i] then buttons[i].glow:SetAlpha(a) end
      end
      if hintLeft <= 0 then g.hintA, g.hintB = nil, nil end
    end
  end)

  if ValidGame(data.game) then
    g = data.game
    ShowGame()
  else
    data.game = nil
    Start("teahouse")
  end
end

ns.RegisterGame({
  key = "teahouse",
  name = "Teahouse Tiles",
  blurb = "Match free pairs of tiles until the table is clear.",
  icon = ns.MEDIA .. "icons\\teahouse",
  order = 130,
  hasWins = true,
  Create = Create,
  OnHide = function()
    selected = nil
    hintLeft = 0
    if g then
      g.hintA, g.hintB = nil, nil
      for i = 1, #buttons do buttons[i].glow:SetAlpha(0) end
      Render()
    end
  end,
  InProgress = function(d)
    local s = type(d) == "table" and d.game or nil
    if type(s) ~= "table" or not LAYOUT_ROWS[s.layout] or type(s.tiles) ~= "table" then return false end
    if s.won == true then return false end
    local n, removed = #s.tiles, 0
    for i = 1, n do
      local v = s.tiles[i]
      if type(v) ~= "number" or v < 0 or v ~= floor(v) then return false end
      if v == 0 then removed = removed + 1 end
    end
    return removed >= 2 and removed < n
  end,
  Summary = function(d)
    local s = d.stats
    local best = s.best_teahouse or s.best_quick
    return best and ("Best " .. ns.FormatTime(best)) or ""
  end,
})
