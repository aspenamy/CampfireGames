-------------------------------------------------------------------------------
-- Campfire Games: Solitaire (Klondike patience)
--
-- Build each suit on a foundation from Ace to King. On the tableau, stack
-- cards downward in alternating colors (red on black, black on red).
-- Click the stock to draw (click the empty stock to turn the waste over).
-- Drag a face-up card (with the cards on top of it) to where it goes, or
-- click it and then click where it goes. Click the same card again to send it to the best spot, or
-- right-click a card to send it to a foundation. Kings fill empty piles.
-- When everything is face up a Finish button plays the rest home.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, max, min = math.floor, math.max, math.min

local CW, CH = 42, 58          -- card size
local COL = 46                 -- column pitch (42 + 4 gap)
local DOWN_GAP, UP_GAP = 6, 15
local TOP_Y, TAB_Y = 18, 86
local AVAIL = 286              -- tableau height available
local FAN = 12                 -- waste fan offset (draw 3)
local MAX_UNDO = 200
local FINISH_STEP = 0.06
local NUM_SPARKS = 22

local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local SUIT_TEX = { "spade", "heart", "diamond", "club" }
local RED_INK = { 0.70, 0.12, 0.10 }
local BLACK_INK = { 0.10, 0.08, 0.07 }
local PARCHMENT = { 0.94, 0.88, 0.74 }

-- Card ids are 0..51: suit = floor(id / 13) + 1 (1 spade, 2 heart,
-- 3 diamond, 4 club), rank = id % 13 + 1.
local function SuitOf(id) return floor(id / 13) + 1 end
local function RankOf(id) return id % 13 + 1 end
local function IsRed(id) local s = SuitOf(id); return s == 2 or s == 3 end

local data, game
local panel, overlay, toast, fx
local cards, slots = {}, {}
local where = {}               -- where[id] = { k = "s"/"w"/"f"/"t", p = pile, pos = index }
local sel                      -- { k, p, from }
local finishing, finishAcc = false, 0
local movesText, timeText, modeText
local undoButton, newButton, finishButton, drawRow

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local function NewState(draw)
  local deck = {}
  for i = 0, 51 do deck[#deck + 1] = i end
  ns.Shuffle(deck)
  local g = {
    draw = draw, stock = {}, waste = {}, found = { {}, {}, {}, {} },
    tab = {}, fu = {}, moves = 0, elapsed = 0, won = false, undo = {},
  }
  local n = 0
  for c = 1, 7 do
    g.tab[c] = {}
    for _ = 1, c do
      n = n + 1
      g.tab[c][#g.tab[c] + 1] = deck[n]
    end
    g.fu[c] = 1
  end
  while n < 52 do
    n = n + 1
    g.stock[#g.stock + 1] = deck[n]
  end
  return g
end

local function ValidList(t, seen)
  if type(t) ~= "table" then return false end
  for i = 1, #t do
    local v = t[i]
    if type(v) ~= "number" or v < 0 or v > 51 or v ~= floor(v) or seen[v] then return false end
    seen[v] = true
  end
  return true
end

local function ValidGame(g)
  if type(g) ~= "table" then return false end
  if g.draw ~= 1 and g.draw ~= 3 then return false end
  if type(g.moves) ~= "number" or type(g.elapsed) ~= "number" then return false end
  if type(g.found) ~= "table" or type(g.tab) ~= "table" or type(g.fu) ~= "table" then return false end
  local seen = {}
  if not ValidList(g.stock, seen) or not ValidList(g.waste, seen) then return false end
  for f = 1, 4 do
    if not ValidList(g.found[f], seen) then return false end
  end
  for c = 1, 7 do
    if not ValidList(g.tab[c], seen) then return false end
    local fu = g.fu[c]
    if type(fu) ~= "number" or fu < 0 or fu > #g.tab[c] then return false end
    if #g.tab[c] > 0 and fu < 1 then return false end
  end
  local count = 0
  for _ in pairs(seen) do count = count + 1 end
  if count ~= 52 then return false end
  if type(g.undo) ~= "table" then g.undo = {} end
  for i = #g.undo, 1, -1 do
    if type(g.undo[i]) ~= "string" then table.remove(g.undo, i) end
  end
  while #g.undo > MAX_UNDO do table.remove(g.undo, 1) end
  g.won = g.won and true or false
  return true
end

-- A whole position as one short string, for the undo list.
local function Encode()
  local parts = { table.concat(game.stock, ","), table.concat(game.waste, ",") }
  for f = 1, 4 do parts[#parts + 1] = table.concat(game.found[f], ",") end
  for c = 1, 7 do parts[#parts + 1] = table.concat(game.tab[c], ",") end
  parts[#parts + 1] = table.concat(game.fu, ",")
  parts[#parts + 1] = tostring(game.moves)
  return table.concat(parts, ";")
end

local function ToList(s)
  local out = {}
  for n in s:gmatch("%d+") do out[#out + 1] = tonumber(n) end
  return out
end

local function Decode(s)
  local seg = {}
  for part in (s .. ";"):gmatch("([^;]*);") do seg[#seg + 1] = part end
  if #seg ~= 15 then return false end
  game.stock, game.waste = ToList(seg[1]), ToList(seg[2])
  for f = 1, 4 do game.found[f] = ToList(seg[2 + f]) end
  for c = 1, 7 do game.tab[c] = ToList(seg[6 + c]) end
  game.fu = ToList(seg[14])
  game.moves = tonumber(seg[15]) or 0
  return true
end

local function Snapshot()
  game.undo[#game.undo + 1] = Encode()
  if #game.undo > MAX_UNDO then table.remove(game.undo, 1) end
end

local function FoundCount()
  local n = 0
  for f = 1, 4 do n = n + #game.found[f] end
  return n
end

local function CanFinish()
  if game.won or #game.stock > 0 or #game.waste > 0 then return false end
  for c = 1, 7 do
    if game.fu[c] ~= #game.tab[c] then return false end
  end
  return FoundCount() < 52
end

-------------------------------------------------------------------------------
-- Rules
-------------------------------------------------------------------------------

local function CanFound(id, f)
  local pile = game.found[f]
  if #pile == 0 then return RankOf(id) == 1 end
  local top = pile[#pile]
  return SuitOf(top) == SuitOf(id) and RankOf(id) == RankOf(top) + 1
end

local function CanTab(id, c)
  local pile = game.tab[c]
  if #pile == 0 then return RankOf(id) == 13 end
  local top = pile[#pile]
  return IsRed(top) ~= IsRed(id) and RankOf(top) == RankOf(id) + 1
end

local function PileOf(k, p)
  if k == "t" then return game.tab[p] end
  if k == "w" then return game.waste end
  if k == "f" then return game.found[p] end
  return game.stock
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function Place(id, x, y, z, faceUp, selected)
  local card = cards[id]
  card:ClearAllPoints()
  card:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
  card:SetFrameLevel(panel:GetFrameLevel() + 2 + z)
  card.rank:SetShown(faceUp)
  card.small:SetShown(faceUp)
  card.big:SetShown(faceUp)
  card.back:SetShown(not faceUp)
  card.hl:SetShown(faceUp)
  local on = selected and true or false
  for i = 1, 4 do card.gold[i]:SetShown(on) end
  card:Show()
end

local function IsSelected(k, p, pos)
  return sel and sel.k == k and sel.p == p and pos >= sel.from
end

local function UpdateHud()
  movesText:SetText("Moves " .. game.moves)
  timeText:SetText(ns.FormatTime(game.elapsed))
  modeText:SetText("Draw " .. game.draw)
end

local function Render()
  if not game then return end
  local colx = function(c) return (c - 1) * COL + 1 end

  for i, id in ipairs(game.stock) do
    where[id] = { k = "s", p = 1, pos = i }
    Place(id, colx(1), TOP_Y, i, false, false)
  end

  local nw = #game.waste
  local fan = (game.draw == 3) and 3 or 1
  local first = max(1, nw - fan + 1)
  for i, id in ipairs(game.waste) do
    where[id] = { k = "w", p = 1, pos = i }
    local j = max(1, i - first + 1)
    Place(id, colx(2) + (j - 1) * FAN, TOP_Y, i, true, IsSelected("w", 1, i))
  end

  for f = 1, 4 do
    for i, id in ipairs(game.found[f]) do
      where[id] = { k = "f", p = f, pos = i }
      Place(id, colx(3 + f), TOP_Y, i, true, IsSelected("f", f, i))
    end
  end

  for c = 1, 7 do
    local pile, fu = game.tab[c], game.fu[c]
    local downs = #pile - fu
    local up = UP_GAP
    if fu > 1 then
      local need = CH + downs * DOWN_GAP + (fu - 1) * UP_GAP
      if need > AVAIL then up = max(5, (AVAIL - CH - downs * DOWN_GAP) / (fu - 1)) end
    end
    local y = TAB_Y
    for i, id in ipairs(pile) do
      where[id] = { k = "t", p = c, pos = i }
      Place(id, colx(c), floor(y + 0.5), i, i > downs, IsSelected("t", c, i))
      y = y + (i <= downs and DOWN_GAP or up)
    end
  end

  for f = 1, 4 do slots["f" .. f].empty:SetShown(#game.found[f] == 0) end
  for c = 1, 7 do slots["t" .. c].empty:SetShown(#game.tab[c] == 0) end
  slots.s.again:SetShown(#game.stock == 0 and #game.waste > 0)

  UpdateHud()
  undoButton:SetEnabled(#game.undo > 0 and not game.won and not finishing)
  newButton:SetEnabled(not finishing)
  finishButton:SetShown(CanFinish() and not finishing)
  drawRow:Select(data.draw)
end

-------------------------------------------------------------------------------
-- Winning
-------------------------------------------------------------------------------

local sparkList = {}

local function ResetSpark(s, anywhere)
  s.x = math.random(10, ns.GAME_W - 10)
  s.y = anywhere and math.random(0, ns.GAME_H) or -6
  s.vy = 18 + math.random() * 34
  s.ph = math.random() * 6.28
  s.size = 7 + math.random() * 9
  s.tex:SetSize(s.size, s.size)
end

local function Win()
  game.won = true
  game.undo = {} -- no undo after a win; keeps the save small
  finishing = false
  sel = nil
  local t = floor(game.elapsed)
  local newBest = ns.RecordResult("solitaire", {
    won = true, time = t, lowerIsBetter = true,
    bestKey = game.draw == 3 and "best_draw3" or "best_draw1",
  })
  ns.Sound("win")
  Render()
  local best = data.stats[game.draw == 3 and "best_draw3" or "best_draw1"]
  overlay:Open(newBest and "A new best!" or "You win!",
    format("Draw %d in %s, %d moves\nBest: %s", game.draw, ns.FormatTime(t), game.moves, ns.FormatTime(best)))
  for _, s in ipairs(sparkList) do ResetSpark(s, true) end
  fx:Show()
end

local function CheckWin()
  if not game.won and FoundCount() == 52 then Win() return true end
  return false
end

-------------------------------------------------------------------------------
-- Moving
-------------------------------------------------------------------------------

local function Deselect()
  if sel then
    sel = nil
    Render()
  end
end

-- Move cards from[pos..] of a pile to a tableau or foundation. Returns
-- true when it was legal and done.
local function TryMove(sk, sp, from, dk, dp)
  if game.won then return false end
  local src = PileOf(sk, sp)
  local n = #src - from + 1
  if n < 1 or from < 1 then return false end
  if sk == "t" and from <= #src - game.fu[sp] then return false end
  if sk == "w" and n ~= 1 then return false end
  if sk == "f" and n ~= 1 then return false end
  if sk == dk and sp == dp then return false end
  local lead = src[from]
  if dk == "f" then
    if n ~= 1 or not CanFound(lead, dp) then return false end
  elseif dk == "t" then
    if not CanTab(lead, dp) then return false end
  else
    return false
  end

  Snapshot()
  local dst = PileOf(dk, dp)
  for i = from, #src do dst[#dst + 1] = src[i] end
  for i = #src, from, -1 do src[i] = nil end
  if dk == "t" then game.fu[dp] = game.fu[dp] + n end
  if sk == "t" then
    game.fu[sp] = game.fu[sp] - n
    if game.fu[sp] < 1 and #src > 0 then game.fu[sp] = 1 end
  end
  game.moves = game.moves + 1
  sel = nil
  ns.Sound("place")
  Render()
  CheckWin()
  return true
end

-- The best place for a card or run: a foundation first, then a tableau pile.
local function AutoMove(sk, sp, from)
  local src = PileOf(sk, sp)
  local lead = src[from]
  if not lead then return false end
  if sk ~= "f" and from == #src then
    for f = 1, 4 do
      if CanFound(lead, f) and TryMove(sk, sp, from, "f", f) then return true end
    end
  end
  for pass = 1, 2 do
    for c = 1, 7 do
      local isEmpty = #game.tab[c] == 0
      if (pass == 1) ~= isEmpty and not (sk == "t" and sp == c) and CanTab(lead, c) then
        local pointless = isEmpty and sk == "t" and from == 1
        if not pointless and TryMove(sk, sp, from, "t", c) then return true end
      end
    end
  end
  return false
end

local function Draw()
  if game.won or finishing then return end
  sel = nil
  if #game.stock > 0 then
    Snapshot()
    for _ = 1, game.draw do
      if #game.stock == 0 then break end
      game.waste[#game.waste + 1] = table.remove(game.stock)
    end
    game.moves = game.moves + 1
    ns.Sound("page")
  elseif #game.waste > 0 then
    Snapshot()
    for i = #game.waste, 1, -1 do game.stock[#game.stock + 1] = game.waste[i] end
    game.waste = {}
    game.moves = game.moves + 1
    ns.Sound("page")
  else
    return
  end
  Render()
end

local function Select(k, p, from)
  sel = { k = k, p = p, from = from }
  ns.Sound("click")
  Render()
end

local function Bad()
  sel = nil
  ns.Sound("bad")
  Render()
end

local function Drop(k, p)
  if not sel then return end
  if sel.k == k and sel.p == p then Deselect() return end
  if not TryMove(sel.k, sel.p, sel.from, k, p) then Bad() end
end

local function OnCard(id, button)
  if game.won or finishing then return end
  local w = where[id]
  if not w then return end
  local pile = PileOf(w.k, w.p)

  if button == "RightButton" then
    sel = nil
    if w.k == "s" or w.k == "f" or w.pos ~= #pile then Render() return end
    if w.k == "t" and w.pos <= #pile - game.fu[w.p] then Render() return end
    for f = 1, 4 do
      if CanFound(id, f) and TryMove(w.k, w.p, w.pos, "f", f) then return end
    end
    Bad()
    return
  end

  if w.k == "s" then
    Draw()
  elseif w.k == "w" then
    if w.pos ~= #pile then return end
    if sel and sel.k == "w" then
      if not AutoMove("w", 1, w.pos) then Bad() end
    else
      Select("w", 1, w.pos)
    end
  elseif w.k == "f" then
    if sel then
      if sel.k == "f" and sel.p == w.p then
        if not AutoMove("f", w.p, w.pos) then Bad() end
      else
        Drop("f", w.p)
      end
    elseif w.pos == #pile then
      Select("f", w.p, w.pos)
    end
  else
    local faceUp = w.pos > #pile - game.fu[w.p]
    if not faceUp then
      if sel then Drop("t", w.p) end
    elseif sel and sel.k == "t" and sel.p == w.p then
      if sel.from == w.pos then
        if not AutoMove("t", w.p, w.pos) then Bad() end
      else
        Select("t", w.p, w.pos)
      end
    elseif sel then
      Drop("t", w.p)
    else
      Select("t", w.p, w.pos)
    end
  end
end

-------------------------------------------------------------------------------
-- Dragging: press on a face-up card and drag it (with any cards on top of it)
-- to a pile. Clicking still works as before.
-------------------------------------------------------------------------------

local drag, dragFrame

local function CursorXY()
  local x, y = GetCursorPosition()
  local s = panel:GetEffectiveScale()
  return x / s - panel:GetLeft(), panel:GetTop() - y / s
end

local function CanLift(w)
  local pile = PileOf(w.k, w.p)
  if w.k == "s" then return false end
  if w.k == "w" or w.k == "f" then return w.pos == #pile end
  return w.pos > #pile - game.fu[w.p]
end

-- Which pile a point (panel coordinates, y down) is over.
local function PileAt(x, y)
  local c = floor((x - 1) / COL) + 1
  if c < 1 or c > 7 then return nil end
  if y < TAB_Y - 6 then
    if c >= 4 then return "f", c - 3 end
    return nil
  end
  return "t", c
end

local function DragUpdate()
  if not drag then return end
  local x, y = CursorXY()
  for j, id in ipairs(drag.ids) do
    local card = cards[id]
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", panel, "TOPLEFT", x - drag.ox, -(y - drag.oy + (j - 1) * UP_GAP))
    card:SetFrameLevel(panel:GetFrameLevel() + 60 + j)
  end
end

local function StartDrag(id)
  if not game or game.won or finishing then return end
  local w = where[id]
  if not w or not CanLift(w) then return end
  local pile = PileOf(w.k, w.p)
  local ids = {}
  for i = w.pos, #pile do ids[#ids + 1] = pile[i] end
  local x, y = CursorXY()
  local card = cards[id]
  drag = {
    k = w.k, p = w.p, from = w.pos, ids = ids,
    ox = x - (card:GetLeft() - panel:GetLeft()),
    oy = y - (panel:GetTop() - card:GetTop()),
  }
  sel = { k = w.k, p = w.p, from = w.pos }
  Render()
  dragFrame:Show()
  DragUpdate()
end

local function StopDrag()
  if not drag then return end
  local d = drag
  drag = nil
  dragFrame:Hide()
  local x, y = CursorXY()
  -- Dropped by where the middle of the carried card is.
  local k, p = PileAt(x - d.ox + CW / 2, y - d.oy + CH / 2)
  if k and not (k == d.k and p == d.p) then
    if not TryMove(d.k, d.p, d.from, k, p) then Bad() end
  else
    sel = nil
    Render()
  end
end

local function Undo()
  if game.won or finishing or #game.undo == 0 then return end
  local s = table.remove(game.undo)
  sel = nil
  if Decode(s) then ns.Sound("click") end
  Render()
end

-------------------------------------------------------------------------------
-- Finishing and new deals
-------------------------------------------------------------------------------

local function FinishStep()
  -- Lowest card that can go home. With everything face up there always is one.
  local bestId, bestC, bestF
  for c = 1, 7 do
    local pile = game.tab[c]
    local id = pile[#pile]
    if id then
      for f = 1, 4 do
        if CanFound(id, f) then
          if not bestId or RankOf(id) < RankOf(bestId) then bestId, bestC, bestF = id, c, f end
          break
        end
      end
    end
  end
  if not bestId then finishing = false Render() return end
  local pile = game.tab[bestC]
  local dst = game.found[bestF]
  dst[#dst + 1] = table.remove(pile)
  game.fu[bestC] = min(game.fu[bestC], #pile)
  game.moves = game.moves + 1
  ns.Sound("place")
  Render()
  CheckWin()
end

local function StartFinish()
  if not CanFinish() then return end
  Snapshot()
  sel = nil
  finishing = true
  finishAcc = 0
  Render()
end

local function Progress()
  return game and not game.won and game.moves >= 10
end

local function NewDeal()
  if game and not game.won and Progress() then
    ns.RecordResult("solitaire", { won = false })
  end
  game = NewState(data.draw)
  data.game = game
  sel, finishing = nil, false
  overlay:Close()
  fx:Hide()
  Render()
end

StaticPopupDialogs["DOWNTIME_NEW_SOLITAIRE"] = {
  text = "Start a new deal? This game will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function() NewDeal() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function AskNewDeal()
  if game and not game.won and game.moves > 0 then
    StaticPopup_Show("DOWNTIME_NEW_SOLITAIRE")
  else
    NewDeal()
  end
end

local function PickDraw(mode)
  data.draw = mode
  if game and not game.won and game.moves == 0 then
    NewDeal()
  else
    drawRow:Select(mode)
    toast:Say("Used for the next deal")
  end
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function MakeSlot(name, x, y, onClick)
  local s = CreateFrame("Button", nil, panel)
  s:SetSize(CW, CH)
  s:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
  s:SetFrameLevel(panel:GetFrameLevel() + 1)
  s.empty = CreateFrame("Frame", nil, s)
  s.empty:SetAllPoints()
  UI.Border(s.empty, C.faint, 1, "ARTWORK", 0.55)
  if onClick then s:SetScript("OnClick", onClick) end
  slots[name] = s
  return s
end

local function MakeCard(id)
  local suit, rank = SuitOf(id), RankOf(id)
  local ink = IsRed(id) and RED_INK or BLACK_INK
  local b = CreateFrame("Button", nil, panel)
  b:SetSize(CW, CH)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.id = id

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  UI.Color(bg, PARCHMENT)
  UI.Border(b, C.lineDark, 1, "BORDER")
  b.gold = UI.Border(b, C.gold, 2, "OVERLAY")

  b.rank = b:CreateFontString(nil, "OVERLAY")
  b.rank:SetFont(ns.FONT, 11, "")
  b.rank:SetTextColor(ink[1], ink[2], ink[3], 1)
  b.rank:SetPoint("TOPLEFT", 3, -3)
  b.rank:SetText(RANKS[rank])

  b.small = b:CreateTexture(nil, "ARTWORK")
  b.small:SetTexture(ns.MEDIA .. "cards\\" .. SUIT_TEX[suit])
  b.small:SetSize(10, 10)
  b.small:SetPoint("LEFT", b.rank, "RIGHT", 1, 0)

  b.big = b:CreateTexture(nil, "ARTWORK")
  b.big:SetTexture(ns.MEDIA .. "cards\\" .. SUIT_TEX[suit])
  b.big:SetSize(24, 24)
  b.big:SetPoint("CENTER", 0, -6)

  b.back = b:CreateTexture(nil, "ARTWORK")
  b.back:SetTexture(ns.MEDIA .. "cards\\back")
  b.back:SetPoint("TOPLEFT", 1, -1)
  b.back:SetPoint("BOTTOMRIGHT", -1, 1)
  b.back:SetTexCoord(0, 1, 0.156, 0.844)

  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 0.85, 0.5, 0.18)

  b:SetScript("OnClick", function(self, button) OnCard(self.id, button) end)
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self) StartDrag(self.id) end)
  b:SetScript("OnDragStop", function() StopDrag() end)
  cards[id] = b
end

local function Create(parent, saved)
  panel = parent
  data = saved
  if data.draw ~= 1 and data.draw ~= 3 then data.draw = 1 end
  if ValidGame(data.game) then
    game = data.game
  else
    data.game = nil
  end

  movesText = UI.Text(parent, 12, C.cream)
  movesText:SetPoint("TOPLEFT", 2, -1)
  timeText = UI.Text(parent, 12, C.cream)
  timeText:SetPoint("TOPRIGHT", -2, -1)
  modeText = UI.Title(parent, 13)
  modeText:SetPoint("TOP", 0, -1)

  local function colx(c) return (c - 1) * COL + 1 end
  MakeSlot("s", colx(1), TOP_Y, function() if game then Draw() end end)
  slots.s.again = slots.s:CreateTexture(nil, "ARTWORK")
  slots.s.again:SetTexture(ns.MEDIA .. "dot")
  slots.s.again:SetSize(22, 22)
  slots.s.again:SetPoint("CENTER")
  slots.s.again:SetVertexColor(C.dim[1], C.dim[2], C.dim[3], 0.6)
  MakeSlot("w", colx(2), TOP_Y)
  for f = 1, 4 do
    local s = MakeSlot("f" .. f, colx(3 + f), TOP_Y, function()
      if game and sel then Drop("f", f) end
    end)
    local a = UI.Text(s.empty, 18, C.faint, ns.FONT_TITLE)
    a:SetPoint("CENTER")
    a:SetText("A")
    a:SetAlpha(0.6)
  end
  for c = 1, 7 do
    MakeSlot("t" .. c, colx(c), TAB_Y, function()
      if game and sel then Drop("t", c) end
    end)
  end

  for id = 0, 51 do MakeCard(id) end
  dragFrame = CreateFrame("Frame", nil, parent)
  dragFrame:Hide()
  dragFrame:SetScript("OnUpdate", DragUpdate)

  -- Bottom controls.
  undoButton = UI.Button(parent, "Undo", 154, 22)
  undoButton:SetPoint("BOTTOMLEFT", 0, 0)
  undoButton:SetScript("OnClick", Undo)
  newButton = UI.Button(parent, "New deal", 154, 22)
  newButton:SetPoint("BOTTOMRIGHT", 0, 0)
  newButton:SetScript("OnClick", AskNewDeal)

  local label = UI.Text(parent, 11, C.dim)
  label:SetPoint("BOTTOMLEFT", 0, 33)
  label:SetText("Draw:")
  drawRow = UI.Choice(parent, { { key = 1, label = "Draw 1" }, { key = 3, label = "Draw 3" } }, 160, PickDraw)
  drawRow:SetPoint("BOTTOMLEFT", 38, 28)
  finishButton = UI.Button(parent, "Finish", 100, 22)
  finishButton:SetPoint("BOTTOMRIGHT", 0, 28)
  finishButton:SetScript("OnClick", StartFinish)
  finishButton:Hide()

  overlay = UI.Overlay(parent)
  toast = UI.Toast(parent)
  local again = UI.Button(overlay.buttons, "New deal", 110, 24)
  again:SetPoint("TOP", 0, 0)
  again:SetScript("OnClick", NewDeal)

  -- Gentle sparks over the win screen: warm lights drifting up.
  fx = CreateFrame("Frame", nil, parent)
  fx:SetAllPoints()
  fx:SetFrameLevel(parent:GetFrameLevel() + 33)
  for i = 1, NUM_SPARKS do
    local s = { tex = fx:CreateTexture(nil, "OVERLAY") }
    s.tex:SetTexture(ns.MEDIA .. "dot")
    s.tex:SetBlendMode("ADD")
    s.tex:SetVertexColor(1.0, 0.72, 0.38, 0.55)
    ResetSpark(s, true)
    sparkList[i] = s
  end
  local clock = 0
  fx:SetScript("OnUpdate", function(_, dt)
    clock = clock + dt
    for _, s in ipairs(sparkList) do
      s.y = s.y + s.vy * dt
      if s.y > ns.GAME_H + 10 then ResetSpark(s, false) end
      local x = s.x + math.sin(clock * 0.8 + s.ph) * 9
      s.tex:ClearAllPoints()
      s.tex:SetPoint("CENTER", parent, "BOTTOMLEFT", x, s.y)
      local fade = 1 - s.y / ns.GAME_H
      s.tex:SetAlpha(max(0.05, min(1, fade * 1.4)))
    end
  end)
  fx:Hide()

  -- The clock runs while the game is open; Finish plays one card at a time.
  local acc = 0
  parent:SetScript("OnUpdate", function(_, dt)
    if not game or game.won then return end
    game.elapsed = game.elapsed + dt
    acc = acc + dt
    if acc >= 0.25 then
      acc = 0
      timeText:SetText(ns.FormatTime(game.elapsed))
    end
    if finishing then
      finishAcc = finishAcc + dt
      if finishAcc >= FINISH_STEP then
        finishAcc = 0
        FinishStep()
      end
    end
  end)

  if not game then
    game = NewState(data.draw)
    data.game = game
  end
  Render()
  if game.won then
    local t = floor(game.elapsed)
    local best = data.stats[game.draw == 3 and "best_draw3" or "best_draw1"]
    overlay:Open("You win!", format("Draw %d in %s, %d moves\nBest: %s",
      game.draw, ns.FormatTime(t), game.moves, ns.FormatTime(best)))
    fx:Show()
  end
end

ns.RegisterGame({
  key = "solitaire",
  name = "Solitaire",
  blurb = "Classic patience: build each suit from Ace to King.",
  icon = ns.MEDIA .. "icons\\solitaire",
  order = 30,
  hasWins = true,
  Create = Create,
  OnShow = function() if game then Render() end end,
  OnHide = function()
    if drag then
      drag = nil
      if dragFrame then dragFrame:Hide() end
    end
    sel, finishing = nil, false
    if game and panel then Render() end
  end,
  InProgress = function(d)
    local g = type(d) == "table" and d.game or nil
    if not ValidGame(g) then return false end
    return not g.won and g.moves >= 10
  end,
  Summary = function(d)
    local s = d.stats
    if (s.won or 0) == 0 then return "" end
    local best = s.best_draw1
    if s.best_draw3 and (not best or s.best_draw3 < best) then best = s.best_draw3 end
    return best and format("Won %d, best %s", s.won, ns.FormatTime(best)) or format("Won %d", s.won)
  end,
})
