-------------------------------------------------------------------------------
-- Campfire Games: Solitaire - Klondike
--
-- Build each suit on a foundation from Ace to King. On the tableau, stack
-- cards downward in alternating colors (red on black, black on red).
-- Click the stock to draw (click the empty stock to turn the waste over).
-- Drag a face-up card (with the cards on top of it) to where it goes, or
-- click it and then click where it goes. Click the same card again to send
-- it to the best spot, or right-click a card to send it to a foundation.
-- Kings fill empty piles. When everything is face up, Finish plays the rest.
--
-- Scoring (picked in the chooser): Standard counts points for good moves
-- and loses a little over time; Vegas pays $5 a card against $52 a deal and
-- keeps a running total; None just counts moves.
-------------------------------------------------------------------------------

local _, ns = ...

local UI = ns.UI
local K = ns.CardKit
local floor, max, min = math.floor, math.max, math.min
local SuitOf, RankOf, IsRed = K.SuitOf, K.RankOf, K.IsRed

local CW, CH = 42, 58
local COL = 46
local DOWN_GAP, UP_GAP = 6, 15
local TOP_Y, TAB_Y = 18, 86
local AVAIL = 286
local FAN = 12
local MAX_UNDO = 200
local FINISH_STEP = 0.06
local AUTO_STEP = 0.09

local V = {
  key = "klondike", name = "Klondike", order = 10,
  options = { { key = 1, label = "Draw 1" }, { key = 3, label = "Draw 3" } },
  optionField = "draw",
  help = "Build each suit up from Ace to King on the four piles at the top right.\n\n"
    .. "On the table, stack cards down in alternating colors. Only a King can go in an empty space.\n\n"
    .. "Drag a card to where it goes, or click it and then click the spot. Click a card twice to send it to the best spot, or right-click to send it up to its suit. Click the deck to draw.\n\n"
    .. "Standard scoring gives points for good moves and takes 2 every 10 seconds, with a bonus for a quick win. Vegas costs $52 a deal and pays $5 a card, with one pass through the deck (three when drawing 3).",
}
ns.SolitaireVariants = ns.SolitaireVariants or {}
ns.SolitaireVariants.klondike = V

local data, game, hub, page
local cards, slots = {}, {}
local where = {}
local sel
local finishing, finishAcc, autoAcc, autoPending = false, 0, 0, false
local finishButton, dragger

local function colx(c) return (c - 1) * COL + 1 end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local function NewState(draw, scoring)
  local deck = {}
  for i = 0, 51 do deck[#deck + 1] = i end
  ns.Shuffle(deck)
  local g = {
    draw = draw, stock = {}, waste = {}, found = { {}, {}, {}, {} },
    tab = {}, fu = {}, moves = 0, elapsed = 0, won = false, undo = {},
    scoring = scoring, score = 0, vegas = scoring == "vegas" and -52 or 0, passes = 0,
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
  -- Games saved before scoring existed play on without a score.
  if g.scoring ~= "standard" and g.scoring ~= "vegas" and g.scoring ~= "none" then g.scoring = "none" end
  if type(g.score) ~= "number" then g.score = 0 end
  if type(g.vegas) ~= "number" then g.vegas = 0 end
  if type(g.passes) ~= "number" then g.passes = 0 end
  return true
end

-- A whole position as one short string, for the undo list.
local function Encode()
  local parts = { table.concat(game.stock, ","), table.concat(game.waste, ",") }
  for f = 1, 4 do parts[#parts + 1] = table.concat(game.found[f], ",") end
  for c = 1, 7 do parts[#parts + 1] = table.concat(game.tab[c], ",") end
  parts[#parts + 1] = table.concat(game.fu, ",")
  parts[#parts + 1] = tostring(game.moves)
  parts[#parts + 1] = tostring(game.score)
  parts[#parts + 1] = tostring(game.vegas)
  parts[#parts + 1] = tostring(game.passes)
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
  if #seg ~= 15 and #seg ~= 18 then return false end
  game.stock, game.waste = ToList(seg[1]), ToList(seg[2])
  for f = 1, 4 do game.found[f] = ToList(seg[2 + f]) end
  for c = 1, 7 do game.tab[c] = ToList(seg[6 + c]) end
  game.fu = ToList(seg[14])
  game.moves = tonumber(seg[15]) or 0
  if #seg == 18 then
    game.score = tonumber(seg[16]) or game.score
    game.vegas = tonumber(seg[17]) or game.vegas
    game.passes = tonumber(seg[18]) or game.passes
  end
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
-- Scoring
-------------------------------------------------------------------------------

local function StandardScore()
  return max(0, game.score - 2 * floor(game.elapsed / 10))
end

local function Points(n)
  if game.scoring == "standard" then game.score = max(0, game.score + n) end
end

local function Dollars(n)
  if game.scoring == "vegas" then game.vegas = game.vegas + n end
end

-- How many times the waste may be turned over.
local function RecyclesLeft()
  if game.scoring ~= "vegas" then return 99 end
  return (game.draw == 3 and 2 or 0) - game.passes
end

local function MoneyText(n)
  if n < 0 then return "-$" .. ns.FormatNumber(-n) end
  return "$" .. ns.FormatNumber(n)
end

-- Put this deal's Vegas money in the running total, once.
local function Bank()
  if game and game.scoring == "vegas" and not game.banked and game.moves > 0 then
    game.banked = true
    data.vegasBank = (data.vegasBank or 0) + game.vegas
  end
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

-- A card is safe to send home when nothing could still need to sit on it.
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

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function IsSelected(k, p, pos)
  return sel and sel.k == k and sel.p == p and pos >= sel.from
end

local function Place(id, x, y, z, faceUp, selected, delay)
  local card = cards[id]
  card:SetFaceUp(faceUp)
  card:SetSelected(selected)
  card:MoveTo(x, y, z, delay)
end

local function Render(dealing)
  if not game then return end
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
      local delay = dealing and ((i - 1) * 7 + c) * 0.025 or nil
      Place(id, colx(c), floor(y + 0.5), i, i > downs, IsSelected("t", c, i), delay)
      y = y + (i <= downs and DOWN_GAP or up)
    end
  end

  for f = 1, 4 do slots["f" .. f].empty:SetShown(#game.found[f] == 0) end
  for c = 1, 7 do slots["t" .. c].empty:SetShown(#game.tab[c] == 0) end
  slots.s.again:SetShown(#game.stock == 0 and #game.waste > 0 and RecyclesLeft() > 0)
  finishButton:SetShown(CanFinish() and not finishing)
  if hub then hub.Refresh() end
end

-------------------------------------------------------------------------------
-- Winning
-------------------------------------------------------------------------------

local function Win()
  game.won = true
  game.undo = {}
  finishing, autoPending = false, false
  sel = nil
  local t = floor(game.elapsed)
  local lines = { format("Draw %d in %s, %d moves", game.draw, ns.FormatTime(t), game.moves) }
  if game.scoring == "standard" then
    local bonus = t >= 30 and floor(700000 / t) or 0
    game.final = StandardScore() + bonus
    lines[#lines + 1] = format("Score %s (time bonus %s)", ns.FormatNumber(game.final), ns.FormatNumber(bonus))
  elseif game.scoring == "vegas" then
    Bank()
    lines[#lines + 1] = format("This deal %s, overall %s", MoneyText(game.vegas), MoneyText(data.vegasBank))
  end
  Render()
  -- Kings leave first, one from each pile in turn, like the old days.
  local order = {}
  for r = 13, 1, -1 do
    for f = 4, 1, -1 do
      local id = game.found[f][r]
      if id then order[#order + 1] = cards[id] end
    end
  end
  for _, card in ipairs(order) do card:StopMoving() end
  hub.Won(V, {
    time = t, lowerIsBetter = true, bestKey = game.draw == 3 and "best_draw3" or "best_draw1",
    line = table.concat(lines, "\n"), cards = order,
  })
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

-- Move cards from[pos..] of a pile without asking: no undo step.
local function DoMove(sk, sp, from, dk, dp)
  local src, dst = PileOf(sk, sp), PileOf(dk, dp)
  local n = #src - from + 1
  for i = from, #src do dst[#dst + 1] = src[i] end
  for i = #src, from, -1 do src[i] = nil end
  if dk == "t" then game.fu[dp] = game.fu[dp] + n end
  if sk == "t" then
    game.fu[sp] = game.fu[sp] - n
    if game.fu[sp] < 1 and #src > 0 then
      game.fu[sp] = 1
      Points(5)
    end
  end
  if dk == "f" then
    Points(10)
    Dollars(5)
  elseif sk == "w" then
    Points(5)
  elseif sk == "f" then
    Points(-15)
    Dollars(-5)
  end
  game.moves = game.moves + 1
end

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
  DoMove(sk, sp, from, dk, dp)
  sel = nil
  ns.Sound("place")
  autoPending = true
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

-- One safe card goes home on its own (the auto-play option).
local function AutoStep()
  local function Try(k, p)
    local pile = PileOf(k, p)
    local id = pile[#pile]
    if not id or not SafeHome(id) then return false end
    for f = 1, 4 do
      if CanFound(id, f) then
        DoMove(k, p, #pile, "f", f)
        ns.Sound("place")
        Render()
        CheckWin()
        return true
      end
    end
    return false
  end
  if Try("w", 1) then return true end
  for c = 1, 7 do
    if Try("t", c) then return true end
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
    if RecyclesLeft() <= 0 then
      hub.Toast("No more passes")
      ns.Sound("bad")
      return
    end
    Snapshot()
    for i = #game.waste, 1, -1 do game.stock[#game.stock + 1] = game.waste[i] end
    game.waste = {}
    game.moves = game.moves + 1
    game.passes = game.passes + 1
    Points(game.draw == 1 and -100 or -20)
    ns.Sound("page")
  else
    return
  end
  autoPending = true
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
-- Dragging
-------------------------------------------------------------------------------

local function Lift(card)
  if not game or game.won or finishing then return nil end
  local w = where[card.id]
  if not w or w.k == "s" then return nil end
  local pile = PileOf(w.k, w.p)
  if (w.k == "w" or w.k == "f") and w.pos ~= #pile then return nil end
  if w.k == "t" and w.pos <= #pile - game.fu[w.p] then return nil end
  local list = {}
  for i = w.pos, #pile do list[#list + 1] = cards[pile[i]] end
  sel = { k = w.k, p = w.p, from = w.pos }
  Render()
  return list, { k = w.k, p = w.p, from = w.pos }
end

local function PileAt(x, y)
  local c = floor((x - 1) / COL) + 1
  if c < 1 or c > 7 then return nil end
  if y < TAB_Y - 6 then
    if c >= 4 then return "f", c - 3 end
    return nil
  end
  return "t", c
end

local function DropAt(info, x, y)
  local k, p = PileAt(x, y)
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
  DoMove("t", bestC, #game.tab[bestC], "f", bestF)
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

function V.Data(root) return root end

function V.InProgress(d)
  local g = type(d) == "table" and d.game or nil
  if not ValidGame(g) then return false end
  return not g.won and g.moves >= 10
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
  elseif autoPending and data.autoplay and not dragger:Active() then
    autoAcc = autoAcc + dt
    if autoAcc >= AUTO_STEP then
      autoAcc = 0
      if not AutoStep() then autoPending = false end
    end
  end
end

function V.Title() return game and format("Klondike  Draw %d", game.draw) or "Klondike" end

function V.Left()
  if not game then return "" end
  if game.scoring == "standard" then
    return "Score " .. ns.FormatNumber(game.won and (game.final or StandardScore()) or StandardScore())
  elseif game.scoring == "vegas" then
    local total = (data.vegasBank or 0) + (game.banked and 0 or game.vegas)
    return "Vegas " .. MoneyText(total)
  end
  return "Moves " .. game.moves
end

function V.Elapsed() return game and game.elapsed or 0 end
function V.CanUndo() return game and #game.undo > 0 and not finishing end
function V.IsWon() return game and game.won end
function V.HasProgress() return game and not game.won and game.moves > 0 end
function V.Option() return game and game.draw end

function V.Undo()
  if game.won or finishing or #game.undo == 0 then return end
  local s = table.remove(game.undo)
  sel = nil
  autoPending = false
  if Decode(s) then ns.Sound("click") end
  Render()
end

function V.Deal()
  Bank()
  game = NewState(data.draw, data.scoring)
  data.game = game
  sel, finishing, autoPending = nil, false, false
  for id = 0, 51 do cards[id]:SetPos(colx(1), TOP_Y) end
  Render(true)
end

function V.ScoringChanged()
  if not game then return end
  if not game.won and game.moves == 0 and game.scoring ~= data.scoring then
    game = NewState(game.draw, data.scoring)
    data.game = game
    Render()
  elseif game.scoring ~= data.scoring then
    hub.Toast("Used for the next deal")
  end
end

function V.AutoChanged()
  autoPending = true
end

function V.Show()
  if game then Render() end
end

function V.Hide()
  dragger:Cancel()
  sel, finishing = nil, false
  if game then Render() end
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function BuildTable(parent)
  slots.s = K.NewSlot(parent, colx(1), TOP_Y, CW, CH, nil, function() if game then Draw() end end)
  slots.s.again = slots.s:CreateTexture(nil, "ARTWORK")
  slots.s.again:SetTexture(ns.MEDIA .. "dot")
  slots.s.again:SetSize(22, 22)
  slots.s.again:SetPoint("CENTER")
  slots.s.again:SetVertexColor(ns.C.dim[1], ns.C.dim[2], ns.C.dim[3], 0.6)
  slots.w = K.NewSlot(parent, colx(2), TOP_Y, CW, CH)
  for f = 1, 4 do
    slots["f" .. f] = K.NewSlot(parent, colx(3 + f), TOP_Y, CW, CH, "A", function()
      if game and sel then Drop("f", f) end
    end)
  end
  for c = 1, 7 do
    slots["t" .. c] = K.NewSlot(parent, colx(c), TAB_Y, CW, CH, nil, function()
      if game and sel then Drop("t", c) end
    end)
  end
end

function V.Create(parent, saved, theHub)
  page, data, hub = parent, saved, theHub
  if ValidGame(data.game) then
    game = data.game
  else
    data.game = nil
  end
  BuildTable(parent)
  dragger = K.NewDragger(parent, UP_GAP, Lift, DropAt)
  for id = 0, 51 do
    local card = K.NewCard(parent, SuitOf(id), RankOf(id), "big")
    card.id = id
    card:SetScript("OnClick", function(self, button) OnCard(self.id, button) end)
    K.Draggable(card, dragger)
    cards[id] = card
  end
  V.cards = {}
  for id = 0, 51 do V.cards[#V.cards + 1] = cards[id] end
  V.cascade = K.NewCascade(parent)

  finishButton = UI.Button(parent, "Finish", 100, 22)
  finishButton:SetPoint("BOTTOMRIGHT", 0, 28)
  finishButton:SetScript("OnClick", StartFinish)
  finishButton:Hide()

  if not game then
    game = NewState(data.draw, data.scoring)
    data.game = game
    for id = 0, 51 do cards[id]:SetPos(colx(1), TOP_Y) end
    Render(true)
  else
    Render()
  end
  if game.won then
    hub.ShowWon(V, format("Draw %d in %s, %d moves", game.draw, ns.FormatTime(game.elapsed), game.moves))
  end
end
