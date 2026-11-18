-------------------------------------------------------------------------------
-- Campfire Games: Solitaire - Free Cell
--
-- Every card is dealt face up into eight piles. Build each suit up from Ace
-- to King on the four foundations (top right). On the table, stack cards
-- down in alternating colors. The four free cells (top left) hold one card
-- each. You can move a run of cards at once when there's room to shuffle
-- it across: (free cells + 1), doubled for each empty pile.
-------------------------------------------------------------------------------

local _, ns = ...

local UI = ns.UI
local K = ns.CardKit
local floor, max = math.floor, math.max
local SuitOf, RankOf, IsRed = K.SuitOf, K.RankOf, K.IsRed

local CW, CH = 38, 52
local COL = 40
local UP_GAP = 17
local TOP_Y, TAB_Y = 18, 80
local AVAIL = 318
local MAX_UNDO = 200
local FINISH_STEP = 0.06
local AUTO_STEP = 0.09

local V = {
  key = "freecell", name = "Free Cell", order = 30,
  help = "Every card starts face up. Build each suit up from Ace to King on the four piles at the top right.\n\n"
    .. "On the table, stack cards down in alternating colors. Any card can go in an empty pile. The four spaces at the top left each hold one card while you work.\n\n"
    .. "You can move a run of cards in one go when there are enough free spaces to do it a card at a time.\n\n"
    .. "Drag cards, or click a card and then the spot. Click a card twice to send it to the best spot, or right-click to send it up to its suit. Almost every deal can be won.",
}
ns.SolitaireVariants = ns.SolitaireVariants or {}
ns.SolitaireVariants.freecell = V

local data, game, hub, page
local cards, slots, where = {}, {}, {}
local sel
local finishing, finishAcc, autoAcc, autoPending = false, 0, 0, false
local finishButton, dragger

local function colx(c) return (c - 1) * COL + 1 end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local function NewState()
  local deck = {}
  for i = 0, 51 do deck[#deck + 1] = i end
  ns.Shuffle(deck)
  local g = {
    cells = { -1, -1, -1, -1 }, found = { {}, {}, {}, {} }, tab = {},
    moves = 0, elapsed = 0, won = false, undo = {},
  }
  for c = 1, 8 do g.tab[c] = {} end
  for i, id in ipairs(deck) do
    local c = (i - 1) % 8 + 1
    g.tab[c][#g.tab[c] + 1] = id
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
  if type(g) ~= "table" or type(g.moves) ~= "number" or type(g.elapsed) ~= "number" then return false end
  if type(g.cells) ~= "table" or type(g.found) ~= "table" or type(g.tab) ~= "table" then return false end
  local seen, count = {}, 0
  for p = 1, 4 do
    local v = g.cells[p]
    if type(v) ~= "number" then return false end
    if v >= 0 then
      if v > 51 or seen[v] then return false end
      seen[v] = true
    end
    if not ValidList(g.found[p], seen) then return false end
  end
  for c = 1, 8 do
    if not ValidList(g.tab[c], seen) then return false end
  end
  for _ in pairs(seen) do count = count + 1 end
  if count ~= 52 then return false end
  if type(g.undo) ~= "table" then g.undo = {} end
  for i = #g.undo, 1, -1 do
    if type(g.undo[i]) ~= "string" then table.remove(g.undo, i) end
  end
  g.won = g.won and true or false
  return true
end

local function Encode()
  local parts = { table.concat(game.cells, ",") }
  for f = 1, 4 do parts[#parts + 1] = table.concat(game.found[f], ",") end
  for c = 1, 8 do parts[#parts + 1] = table.concat(game.tab[c], ",") end
  parts[#parts + 1] = tostring(game.moves)
  return table.concat(parts, ";")
end

local function ToList(s)
  local out = {}
  for n in s:gmatch("%-?%d+") do out[#out + 1] = tonumber(n) end
  return out
end

local function Decode(s)
  local seg = {}
  for part in (s .. ";"):gmatch("([^;]*);") do seg[#seg + 1] = part end
  if #seg ~= 14 then return false end
  game.cells = ToList(seg[1])
  for f = 1, 4 do game.found[f] = ToList(seg[1 + f]) end
  for c = 1, 8 do game.tab[c] = ToList(seg[5 + c]) end
  game.moves = tonumber(seg[14]) or 0
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

-------------------------------------------------------------------------------
-- Rules
-------------------------------------------------------------------------------

local function CanFound(id, f)
  local pile = game.found[f]
  if #pile == 0 then return RankOf(id) == 1 end
  local top = pile[#pile]
  return SuitOf(top) == SuitOf(id) and RankOf(id) == RankOf(top) + 1
end

local function Fits(id, on)
  return IsRed(on) ~= IsRed(id) and RankOf(on) == RankOf(id) + 1
end

local function CanTab(id, c)
  local pile = game.tab[c]
  if #pile == 0 then return true end
  return Fits(id, pile[#pile])
end

local function IsRun(pile, from)
  for i = from + 1, #pile do
    if not Fits(pile[i], pile[i - 1]) then return false end
  end
  return true
end

local function FreeCells()
  local n = 0
  for p = 1, 4 do if game.cells[p] < 0 then n = n + 1 end end
  return n
end

-- The longest run that can move to a pile, a card at a time through the
-- free spaces.
local function MaxMove(toEmpty)
  local empties = 0
  for c = 1, 8 do if #game.tab[c] == 0 then empties = empties + 1 end end
  if toEmpty then empties = empties - 1 end
  return (FreeCells() + 1) * 2 ^ max(0, empties)
end

-- The cards a pick-up would carry: list of ids.
local function Carried(k, p, from)
  if k == "c" then
    local id = game.cells[p]
    return id >= 0 and { id } or nil
  end
  local pile = k == "t" and game.tab[p] or game.found[p]
  if from < 1 or from > #pile then return nil end
  if k == "f" and from ~= #pile then return nil end
  local out = {}
  for i = from, #pile do out[#out + 1] = pile[i] end
  return out
end

local function SafeHome(id)
  local r = RankOf(id)
  if r <= 2 then return true end
  local home = { 0, 0, 0, 0 }
  for f = 1, 4 do
    local top = game.found[f][#game.found[f]]
    if top then home[SuitOf(top)] = RankOf(top) end
  end
  if IsRed(id) then return home[1] >= r - 1 and home[4] >= r - 1 end
  return home[2] >= r - 1 and home[3] >= r - 1
end

local function CanFinish()
  if game.won or FoundCount() == 52 then return false end
  for c = 1, 8 do
    if not IsRun(game.tab[c], 1) then return false end
  end
  return true
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function IsSelected(k, p, pos)
  return sel and sel.k == k and sel.p == p and pos >= sel.from
end

local function Render(dealing)
  if not game then return end
  for p = 1, 4 do
    local id = game.cells[p]
    if id >= 0 then
      where[id] = { k = "c", p = p, pos = 1 }
      cards[id]:SetSelected(IsSelected("c", p, 1))
      cards[id]:MoveTo(colx(p), TOP_Y, 1)
    end
    slots["c" .. p].empty:SetShown(id < 0)
    for i, fid in ipairs(game.found[p]) do
      where[fid] = { k = "f", p = p, pos = i }
      cards[fid]:SetSelected(IsSelected("f", p, i))
      cards[fid]:MoveTo(colx(4 + p), TOP_Y, i)
    end
    slots["f" .. p].empty:SetShown(#game.found[p] == 0)
  end
  for c = 1, 8 do
    local pile = game.tab[c]
    local gap = UP_GAP
    if #pile > 1 and CH + (#pile - 1) * UP_GAP > AVAIL then gap = max(6, (AVAIL - CH) / (#pile - 1)) end
    for i, id in ipairs(pile) do
      where[id] = { k = "t", p = c, pos = i }
      cards[id]:SetSelected(IsSelected("t", c, i))
      cards[id]:MoveTo(colx(c), floor(TAB_Y + (i - 1) * gap + 0.5), i, dealing and ((i - 1) * 8 + c) * 0.02 or nil)
    end
    slots["t" .. c].empty:SetShown(#pile == 0)
  end
  finishButton:SetShown(CanFinish() and not finishing)
  if hub then hub.Refresh() end
end

-------------------------------------------------------------------------------
-- Moving
-------------------------------------------------------------------------------

local function Win()
  game.won = true
  game.undo = {}
  finishing, autoPending, sel = false, false, nil
  Render()
  local order = {}
  for r = 13, 1, -1 do
    for f = 4, 1, -1 do
      local id = game.found[f][r]
      if id then
        cards[id]:StopMoving()
        order[#order + 1] = cards[id]
      end
    end
  end
  local t = floor(game.elapsed)
  hub.Won(V, {
    time = t, lowerIsBetter = true, bestKey = "best_freecell",
    line = format("Won in %s, %d moves", ns.FormatTime(t), game.moves), cards = order,
  })
end

local function CheckWin()
  if not game.won and FoundCount() == 52 then Win() end
end

-- Move without checks or an undo step.
local function DoMove(sk, sp, from, dk, dp)
  local ids = Carried(sk, sp, from)
  if sk == "c" then
    game.cells[sp] = -1
  else
    local src = sk == "t" and game.tab[sp] or game.found[sp]
    for i = #src, from, -1 do src[i] = nil end
  end
  if dk == "c" then
    game.cells[dp] = ids[1]
  else
    local dst = dk == "t" and game.tab[dp] or game.found[dp]
    for _, id in ipairs(ids) do dst[#dst + 1] = id end
  end
  game.moves = game.moves + 1
end

local function Legal(sk, sp, from, dk, dp)
  if game.won or (sk == dk and sp == dp) then return false end
  local ids = Carried(sk, sp, from)
  if not ids then return false end
  local n = #ids
  if dk == "f" then
    return n == 1 and CanFound(ids[1], dp)
  elseif dk == "c" then
    return n == 1 and game.cells[dp] < 0
  elseif dk == "t" then
    if sk == "t" and not IsRun(game.tab[sp], from) then return false end
    if not CanTab(ids[1], dp) then return false end
    return n <= MaxMove(#game.tab[dp] == 0)
  end
  return false
end

local function TryMove(sk, sp, from, dk, dp)
  if not Legal(sk, sp, from, dk, dp) then return false end
  Snapshot()
  DoMove(sk, sp, from, dk, dp)
  sel = nil
  ns.Sound("place")
  autoPending = true
  Render()
  CheckWin()
  return true
end

local function AutoMove(sk, sp, from)
  local ids = Carried(sk, sp, from)
  if not ids then return false end
  if #ids == 1 and sk ~= "f" then
    for f = 1, 4 do
      if TryMove(sk, sp, from, "f", f) then return true end
    end
  end
  for c = 1, 8 do
    if #game.tab[c] > 0 and TryMove(sk, sp, from, "t", c) then return true end
  end
  if #ids == 1 and sk ~= "c" then
    for p = 1, 4 do
      if TryMove(sk, sp, from, "c", p) then return true end
    end
  end
  if not (sk == "t" and from == 1) then
    for c = 1, 8 do
      if #game.tab[c] == 0 and TryMove(sk, sp, from, "t", c) then return true end
    end
  end
  return false
end

local function AutoStep()
  local function Try(k, p, from, id)
    if not id or not SafeHome(id) then return false end
    for f = 1, 4 do
      if CanFound(id, f) then
        DoMove(k, p, from, "f", f)
        ns.Sound("place")
        Render()
        CheckWin()
        return true
      end
    end
    return false
  end
  for p = 1, 4 do
    if game.cells[p] >= 0 and Try("c", p, 1, game.cells[p]) then return true end
  end
  for c = 1, 8 do
    local pile = game.tab[c]
    if Try("t", c, #pile, pile[#pile]) then return true end
  end
  return false
end

local function Bad()
  sel = nil
  ns.Sound("bad")
  Render()
end

local function Select(k, p, from)
  sel = { k = k, p = p, from = from }
  ns.Sound("click")
  Render()
end

local function Drop(k, p)
  if not sel then return end
  if sel.k == k and sel.p == p then sel = nil Render() return end
  if not TryMove(sel.k, sel.p, sel.from, k, p) then Bad() end
end

local function OnCard(id, button)
  if game.won or finishing then return end
  local w = where[id]
  if not w then return end
  if button == "RightButton" then
    sel = nil
    local ids = Carried(w.k, w.p, w.pos)
    if ids and #ids == 1 and w.k ~= "f" then
      for f = 1, 4 do
        if TryMove(w.k, w.p, w.pos, "f", f) then return end
      end
    end
    Bad()
    return
  end
  if sel and sel.k == w.k and sel.p == w.p then
    if sel.from == w.pos then
      if not AutoMove(w.k, w.p, w.pos) then Bad() end
    elseif w.k == "t" and IsRun(game.tab[w.p], w.pos) then
      Select(w.k, w.p, w.pos)
    else
      sel = nil
      Render()
    end
  elseif sel then
    Drop(w.k, w.p)
  elseif w.k == "t" and not IsRun(game.tab[w.p], w.pos) then
    ns.Sound("bad")
  elseif w.k == "f" and w.pos ~= #game.found[w.p] then
    return
  else
    Select(w.k, w.p, w.pos)
  end
end

-------------------------------------------------------------------------------
-- Dragging
-------------------------------------------------------------------------------

local function Lift(card)
  if not game or game.won or finishing then return nil end
  local w = where[card.id]
  if not w then return nil end
  if w.k == "t" and not IsRun(game.tab[w.p], w.pos) then return nil end
  local ids = Carried(w.k, w.p, w.pos)
  if not ids then return nil end
  local list = {}
  for _, id in ipairs(ids) do list[#list + 1] = cards[id] end
  sel = { k = w.k, p = w.p, from = w.pos }
  Render()
  return list, { k = w.k, p = w.p, from = w.pos }
end

local function DropAt(info, x, y)
  local c = floor((x - 1) / COL) + 1
  local k, p
  if c >= 1 and c <= 8 then
    if y < TAB_Y - 6 then
      if c <= 4 then k, p = "c", c else k, p = "f", c - 4 end
    else
      k, p = "t", c
    end
  end
  if k and not (k == info.k and p == info.p) then
    if not TryMove(info.k, info.p, info.from, k, p) then Bad() end
  else
    sel = nil
    Render()
  end
end

-------------------------------------------------------------------------------
-- Hub hooks
-------------------------------------------------------------------------------

local function FinishStep()
  local best, bk, bp, bfrom
  for p = 1, 4 do
    local id = game.cells[p]
    if id >= 0 and (not best or RankOf(id) < RankOf(best)) then best, bk, bp, bfrom = id, "c", p, 1 end
  end
  for c = 1, 8 do
    local pile = game.tab[c]
    local id = pile[#pile]
    if id and (not best or RankOf(id) < RankOf(best)) then best, bk, bp, bfrom = id, "t", c, #pile end
  end
  if not best then finishing = false Render() return end
  for f = 1, 4 do
    if CanFound(best, f) then
      DoMove(bk, bp, bfrom, "f", f)
      ns.Sound("place")
      Render()
      CheckWin()
      return
    end
  end
  finishing = false
  Render()
end

function V.InProgress(d)
  local g = type(d) == "table" and d.game or nil
  return ValidGame(g) and not g.won and g.moves >= 10
end

function V.Tick(dt)
  if not game or game.won then return end
  game.elapsed = game.elapsed + dt
  if finishing then
    finishAcc = finishAcc + dt
    if finishAcc >= FINISH_STEP then
      finishAcc = 0
      FinishStep()
    end
  elseif autoPending and hub.Prefs().autoplay and not dragger:Active() then
    autoAcc = autoAcc + dt
    if autoAcc >= AUTO_STEP then
      autoAcc = 0
      if not AutoStep() then autoPending = false end
    end
  end
end

function V.Title() return "Free Cell" end
function V.Left() return game and ("Moves " .. game.moves) or "" end
function V.Elapsed() return game and game.elapsed or 0 end
function V.CanUndo() return game and #game.undo > 0 and not finishing end
function V.IsWon() return game and game.won end
function V.HasProgress() return game and not game.won and game.moves > 0 end
function V.Option() return nil end
function V.AutoChanged() autoPending = true end

function V.Undo()
  if game.won or finishing or #game.undo == 0 then return end
  sel, autoPending = nil, false
  if Decode(table.remove(game.undo)) then ns.Sound("click") end
  Render()
end

function V.Deal()
  game = NewState()
  data.game = game
  sel, finishing, autoPending = nil, false, false
  for id = 0, 51 do cards[id]:SetPos(140, -CH) end
  Render(true)
end

function V.Show() if game then Render() end end

function V.Hide()
  dragger:Cancel()
  sel, finishing = nil, false
  if game then Render() end
end

function V.Create(parent, saved, theHub)
  page, data, hub = parent, saved, theHub
  if ValidGame(data.game) then game = data.game else data.game = nil end
  for p = 1, 4 do
    slots["c" .. p] = K.NewSlot(parent, colx(p), TOP_Y, CW, CH, nil, function()
      if game and sel then Drop("c", p) end
    end)
    slots["f" .. p] = K.NewSlot(parent, colx(4 + p), TOP_Y, CW, CH, "A", function()
      if game and sel then Drop("f", p) end
    end)
  end
  for c = 1, 8 do
    slots["t" .. c] = K.NewSlot(parent, colx(c), TAB_Y, CW, CH, nil, function()
      if game and sel then Drop("t", c) end
    end)
  end
  dragger = K.NewDragger(parent, UP_GAP, Lift, DropAt)
  V.cards = {}
  for id = 0, 51 do
    local card = K.NewCard(parent, SuitOf(id), RankOf(id), "mid")
    card.id = id
    card:SetScript("OnClick", function(self, button) OnCard(self.id, button) end)
    K.Draggable(card, dragger)
    cards[id] = card
    V.cards[#V.cards + 1] = card
  end
  V.cascade = K.NewCascade(parent)
  finishButton = UI.Button(parent, "Finish", 100, 22)
  finishButton:SetPoint("BOTTOMRIGHT", 0, 28)
  finishButton:SetScript("OnClick", function()
    if not CanFinish() then return end
    Snapshot()
    sel, finishing, finishAcc = nil, true, 0
    Render()
  end)
  finishButton:Hide()

  if not game then
    V.Deal()
  else
    Render()
    if game.won then hub.ShowWon(V, format("Won in %s, %d moves", ns.FormatTime(game.elapsed), game.moves)) end
  end
end
