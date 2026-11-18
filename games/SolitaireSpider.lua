-------------------------------------------------------------------------------
-- Campfire Games: Solitaire - Spider
--
-- Two decks in ten piles. Build down on any card one rank higher, but only
-- runs of one suit move together. A full run from King down to Ace of one
-- suit leaves the table on its own. Clear all eight runs to win.
-- Click the deck (top right) to deal a card onto every pile; every pile
-- needs a card first. 1, 2 or 4 suits set how hard it is.
-- Score starts at 500, loses 1 a move and gains 100 a finished run.
-------------------------------------------------------------------------------

local _, ns = ...

local UI = ns.UI
local K = ns.CardKit
local floor, max = math.floor, math.max
local RankOf = K.RankOf

local TOP_Y = 18
-- Two tables: wide (the window grows, bigger cards) and narrow (fits the
-- normal window). Set in the chooser.
local LAYOUTS = {
  wide = { w = 424, size = "mid", cw = 38, ch = 52, col = 42, down = 6, up = 16 },
  narrow = { w = 320, size = "small", cw = 30, ch = 42, col = 32, down = 5, up = 14 },
}
local CW, CH, COL, DOWN_GAP, UP_GAP, TAB_Y, AVAIL, TABLE_W
local MAX_UNDO = 150
local HINT_TIME = 1.6

local V = {
  key = "spider", name = "Spider", order = 20,
  options = { { key = 1, label = "1 suit" }, { key = 2, label = "2 suits" }, { key = 4, label = "4 suits" } },
  optionField = "suits",
  help = "Clear the table by building runs from King down to Ace in one suit. A finished run leaves the table on its own.\n\n"
    .. "Any card can go on a card one rank higher, whatever its suit, but only runs of a single suit move together. Any card or run can go in an empty pile.\n\n"
    .. "Click the deck at the top right to deal one more card onto every pile. Every pile needs at least one card before you can deal.\n\n"
    .. "Hint shows a move you could make. One suit is gentle, four suits is a real challenge.",
}
ns.SolitaireVariants = ns.SolitaireVariants or {}
ns.SolitaireVariants.spider = V

local data, game, hub, page
local cards, slots, where = {}, {}, {}
local sel, hint
local fresh = {}              -- cards of runs finished this move: id -> delay
local freshRuns = 0
local burst
local PEEL = 0.045            -- seconds between cards of a finished run
local stockSlot, hintButton, dragger

local function colx(c) return (c - 1) * COL + 1 + floor((TABLE_W - 10 * COL) / 2) end

local function StockX() return TABLE_W - CW - 1 end

local function SetLayout(name)
  if not LAYOUTS[name] then name = "wide" end
  local L = LAYOUTS[name]
  CW, CH, COL, DOWN_GAP, UP_GAP = L.cw, L.ch, L.col, L.down, L.up
  TABLE_W = L.w
  TAB_Y = TOP_Y + CH + 8
  AVAIL = 400 - TAB_Y
  V.layout = name
  return L
end
SetLayout("wide")

local function SuitOf(id)
  local s = game and game.suits or 4
  if s == 1 then return 1 end
  if s == 2 then return (floor(id / 13) % 2 == 0) and 1 or 2 end
  return floor(id / 13) % 4 + 1
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local function NewState(suits)
  local deck = {}
  for i = 0, 103 do deck[#deck + 1] = i end
  ns.Shuffle(deck)
  local g = {
    suits = suits, stock = {}, tab = {}, fu = {}, done = {},
    moves = 0, score = 500, elapsed = 0, won = false, undo = {},
  }
  local n = 0
  for c = 1, 10 do
    g.tab[c] = {}
    for _ = 1, (c <= 4 and 6 or 5) do
      n = n + 1
      g.tab[c][#g.tab[c] + 1] = deck[n]
    end
    g.fu[c] = 1
  end
  while n < 104 do
    n = n + 1
    g.stock[#g.stock + 1] = deck[n]
  end
  return g
end

local function ValidList(t, seen)
  if type(t) ~= "table" then return false end
  for i = 1, #t do
    local v = t[i]
    if type(v) ~= "number" or v < 0 or v > 103 or v ~= floor(v) or seen[v] then return false end
    seen[v] = true
  end
  return true
end

local function ValidGame(g)
  if type(g) ~= "table" or (g.suits ~= 1 and g.suits ~= 2 and g.suits ~= 4) then return false end
  if type(g.moves) ~= "number" or type(g.elapsed) ~= "number" or type(g.score) ~= "number" then return false end
  if type(g.tab) ~= "table" or type(g.fu) ~= "table" then return false end
  local seen, count = {}, 0
  if not ValidList(g.stock, seen) or not ValidList(g.done, seen) then return false end
  if #g.done % 13 ~= 0 then return false end
  for c = 1, 10 do
    if not ValidList(g.tab[c], seen) then return false end
    local fu = g.fu[c]
    if type(fu) ~= "number" or fu < 0 or fu > #g.tab[c] or (#g.tab[c] > 0 and fu < 1) then return false end
  end
  for _ in pairs(seen) do count = count + 1 end
  if count ~= 104 then return false end
  if type(g.undo) ~= "table" then g.undo = {} end
  for i = #g.undo, 1, -1 do
    if type(g.undo[i]) ~= "string" then table.remove(g.undo, i) end
  end
  g.won = g.won and true or false
  return true
end

local function Encode()
  local parts = { table.concat(game.stock, ","), table.concat(game.done, ",") }
  for c = 1, 10 do parts[#parts + 1] = table.concat(game.tab[c], ",") end
  parts[#parts + 1] = table.concat(game.fu, ",")
  parts[#parts + 1] = tostring(game.moves)
  parts[#parts + 1] = tostring(game.score)
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
  game.stock, game.done = ToList(seg[1]), ToList(seg[2])
  for c = 1, 10 do game.tab[c] = ToList(seg[2 + c]) end
  game.fu = ToList(seg[13])
  game.moves = tonumber(seg[14]) or 0
  game.score = tonumber(seg[15]) or 0
  return true
end

local function Snapshot()
  game.undo[#game.undo + 1] = Encode()
  if #game.undo > MAX_UNDO then table.remove(game.undo, 1) end
end

-------------------------------------------------------------------------------
-- Rules
-------------------------------------------------------------------------------

-- Cards from[pos..] form a run of one suit going down.
local function IsRun(c, from)
  local pile = game.tab[c]
  if from < 1 or from > #pile or from <= #pile - game.fu[c] then return false end
  for i = from + 1, #pile do
    local a, b = pile[i - 1], pile[i]
    if SuitOf(a) ~= SuitOf(b) or RankOf(a) ~= RankOf(b) + 1 then return false end
  end
  return true
end

local function CanPlace(id, c)
  local pile = game.tab[c]
  if #pile == 0 then return true end
  return RankOf(pile[#pile]) == RankOf(id) + 1
end

local function FlipTop(c)
  if game.fu[c] < 1 and #game.tab[c] > 0 then game.fu[c] = 1 end
end

-- Take a finished King-to-Ace run off a pile.
local function Collect(c)
  local pile = game.tab[c]
  if #pile < 13 then return false end
  local from = #pile - 12
  if RankOf(pile[from]) ~= 13 or not IsRun(c, from) then return false end
  -- The run peels off from the Ace up, then lands with a chime and sparks.
  -- A second run finished by the same move waits for the first.
  local wait = freshRuns * 0.8
  freshRuns = freshRuns + 1
  for i = from, #pile do
    game.done[#game.done + 1] = pile[i]
    fresh[pile[i]] = wait + (#pile - i) * PEEL
  end
  for i = #pile, from, -1 do pile[i] = nil end
  game.fu[c] = game.fu[c] - 13
  if game.fu[c] < 0 then game.fu[c] = 0 end
  FlipTop(c)
  game.score = game.score + 100
  local run = #game.done / 13 - 1
  local land = wait + 12 * PEEL + 0.2
  for k = 1, 4 do
    burst:Later(wait + (k - 1) * 0.11, function() ns.PlayTone("bell" .. k) end)
  end
  burst:Later(land, function() ns.PlayTone("chime") end)
  burst:Play(colx(1) + run * 11 + CW / 2, TOP_Y + CH / 2, land)
  burst:Later(land, function() if not game.won then hub.Toast("Run complete") end end)
  return true
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function Render(dealing)
  if not game then return end
  for i, id in ipairs(game.stock) do
    where[id] = { k = "s" }
    local group = floor((i - 1) / 10)
    cards[id]:SetFaceUp(false)
    cards[id]:SetSelected(false)
    cards[id]:MoveTo(StockX() - group * 7, TOP_Y, i)
  end
  stockSlot.empty:SetShown(#game.stock == 0)
  for i, id in ipairs(game.done) do
    where[id] = { k = "d" }
    local run = floor((i - 1) / 13)
    cards[id]:SetFaceUp(true)
    cards[id]:SetSelected(false)
    -- The King of each run sits on top.
    cards[id]:MoveTo(colx(1) + run * 11, TOP_Y, run * 13 + (13 - (i - 1) % 13), fresh[id])
  end
  for c = 1, 10 do
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
      local card = cards[id]
      card:SetFaceUp(i > downs)
      local lit = (sel and sel.p == c and i >= sel.from)
        or (hint and ((hint.p == c and i >= hint.from) or (hint.to == c and i == #pile)))
      card:SetSelected(lit)
      local delay = dealing and dealing[id]
      card:MoveTo(colx(c), floor(y + 0.5), i, delay)
      y = y + (i <= downs and DOWN_GAP or up)
    end
    slots[c].empty:SetShown(#pile == 0)
    slots[c]:SetSelected(hint and hint.to == c and #pile == 0)
  end
  fresh, freshRuns = {}, 0
  hintButton:SetEnabled(not game.won)
  if hub then hub.Refresh() end
end

-------------------------------------------------------------------------------
-- Moving
-------------------------------------------------------------------------------

local function Win()
  game.won = true
  game.undo = {}
  sel, hint = nil, nil
  Render()
  local order = {}
  for run = #game.done / 13 - 1, 0, -1 do
    for r = 1, 13 do order[#order + 1] = cards[game.done[run * 13 + r]] end
  end
  for _, card in ipairs(order) do card:StopMoving() end
  local t = floor(game.elapsed)
  hub.Won(V, {
    time = t, lowerIsBetter = true, bestKey = "best_spider" .. game.suits,
    line = format("%d %s in %s, %d moves\nScore %s", game.suits, game.suits == 1 and "suit" or "suits",
      ns.FormatTime(t), game.moves, ns.FormatNumber(game.score)),
    cards = order,
  })
end

local function AfterMove()
  for c = 1, 10 do Collect(c) end
  Render()
  if #game.done == 104 then Win() end
end

local function TryMove(sc, from, dc)
  if game.won or sc == dc or not IsRun(sc, from) then return false end
  local src = game.tab[sc]
  if not CanPlace(src[from], dc) then return false end
  Snapshot()
  local dst = game.tab[dc]
  local n = #src - from + 1
  for i = from, #src do dst[#dst + 1] = src[i] end
  for i = #src, from, -1 do src[i] = nil end
  game.fu[dc] = game.fu[dc] + n
  game.fu[sc] = game.fu[sc] - n
  FlipTop(sc)
  game.moves = game.moves + 1
  game.score = game.score - 1
  sel, hint = nil, nil
  ns.Sound("place")
  AfterMove()
  return true
end

-- Best home for a run: on its own suit, then any card, then an empty pile.
local function BestTarget(sc, from)
  local lead = game.tab[sc][from]
  local any, empty
  for c = 1, 10 do
    if c ~= sc then
      local pile = game.tab[c]
      local top = pile[#pile]
      if top and RankOf(top) == RankOf(lead) + 1 then
        if SuitOf(top) == SuitOf(lead) then return c end
        any = any or c
      elseif not top and from > 1 then
        empty = empty or c
      end
    end
  end
  return any or empty
end

local function DealRow()
  if game.won then return end
  sel, hint = nil, nil
  if #game.stock == 0 then return end
  for c = 1, 10 do
    if #game.tab[c] == 0 then
      hub.Toast("Fill every pile first")
      ns.Sound("bad")
      Render()
      return
    end
  end
  Snapshot()
  local delays = {}
  for c = 1, 10 do
    local id = table.remove(game.stock)
    game.tab[c][#game.tab[c] + 1] = id
    game.fu[c] = game.fu[c] + 1
    delays[id] = (c - 1) * 0.04
  end
  game.moves = game.moves + 1
  game.score = game.score - 1
  ns.Sound("page")
  for c = 1, 10 do Collect(c) end
  Render(delays)
  if #game.done == 104 then Win() end
end

local function FindHint()
  -- A run that lands on its own suit (and isn't already sitting on it) first.
  local fallback
  for sc = 1, 10 do
    local pile = game.tab[sc]
    local from = #pile
    while from > 1 and IsRun(sc, from - 1) do from = from - 1 end
    if from >= 1 and IsRun(sc, from) then
      for i = from, #pile do
        local lead = pile[i]
        local under = pile[i - 1]
        local alreadyHome = under and i - 1 > #pile - game.fu[sc] and RankOf(under) == RankOf(lead) + 1
        for dc = 1, 10 do
          local dst = game.tab[dc]
          local top = dst[#dst]
          if dc ~= sc and top and RankOf(top) == RankOf(lead) + 1 then
            if SuitOf(top) == SuitOf(lead) and not (alreadyHome and SuitOf(under) == SuitOf(lead)) then
              return { p = sc, from = i, to = dc }
            end
            if not alreadyHome and i == from then fallback = fallback or { p = sc, from = i, to = dc } end
          end
        end
      end
    end
  end
  if fallback then return fallback end
  for dc = 1, 10 do
    if #game.tab[dc] == 0 then
      for sc = 1, 10 do
        local n = #game.tab[sc]
        if n > 1 and IsRun(sc, n) then return { p = sc, from = n, to = dc } end
      end
    end
  end
  return nil
end

local function ShowHint()
  if not game or game.won then return end
  sel = nil
  hint = FindHint()
  if hint then
    hint.t = HINT_TIME
    ns.Sound("click")
  elseif #game.stock > 0 then
    hub.Toast("Deal more cards")
  else
    hub.Toast("No moves left")
  end
  Render()
end

local function Bad()
  sel = nil
  ns.Sound("bad")
  Render()
end

local function OnCard(id, button)
  if game.won then return end
  local w = where[id]
  if not w then return end
  hint = nil
  if w.k == "s" then DealRow() return end
  if w.k ~= "t" then return end
  local c = w.p
  if button == "RightButton" then
    sel = nil
    local dc = IsRun(c, w.pos) and BestTarget(c, w.pos)
    if not dc or not TryMove(c, w.pos, dc) then Bad() end
    return
  end
  if sel and sel.p == c then
    if sel.from == w.pos then
      local dc = BestTarget(c, w.pos)
      if not dc or not TryMove(c, w.pos, dc) then Bad() end
    elseif IsRun(c, w.pos) then
      sel = { p = c, from = w.pos }
      Render()
    else
      sel = nil
      Render()
    end
  elseif sel then
    if not TryMove(sel.p, sel.from, c) then Bad() end
  elseif IsRun(c, w.pos) then
    sel = { p = c, from = w.pos }
    ns.Sound("click")
    Render()
  elseif w.pos > #game.tab[c] - game.fu[c] then
    ns.Sound("bad")
  end
end

local function Lift(card)
  if not game or game.won then return nil end
  local w = where[card.id]
  if not w or w.k ~= "t" or not IsRun(w.p, w.pos) then return nil end
  local list = {}
  local pile = game.tab[w.p]
  for i = w.pos, #pile do list[#list + 1] = cards[pile[i]] end
  sel, hint = { p = w.p, from = w.pos }, nil
  Render()
  return list, { p = w.p, from = w.pos }
end

local function DropAt(info, x, y)
  local c = floor((x - colx(1)) / COL) + 1
  if c >= 1 and c <= 10 and c ~= info.p and y > TAB_Y - 10 then
    if not TryMove(info.p, info.from, c) then Bad() end
  else
    sel = nil
    Render()
  end
end

-------------------------------------------------------------------------------
-- Hub hooks
-------------------------------------------------------------------------------

function V.InProgress(d)
  local g = type(d) == "table" and d.game or nil
  return ValidGame(g) and not g.won and g.moves >= 10
end

function V.Tick(dt)
  if not game or game.won then return end
  game.elapsed = game.elapsed + dt
  if hint then
    hint.t = hint.t - dt
    if hint.t <= 0 then
      hint = nil
      Render()
    end
  end
end

function V.Title()
  if not game then return "Spider" end
  return format("Spider  %d %s", game.suits, game.suits == 1 and "suit" or "suits")
end
function V.Left() return game and ("Score " .. ns.FormatNumber(game.score)) or "" end
function V.Elapsed() return game and game.elapsed or 0 end
function V.CanUndo() return game and #game.undo > 0 end
function V.IsWon() return game and game.won end
function V.HasProgress() return game and not game.won and game.moves > 0 end
function V.Option() return game and game.suits end

local function ApplyFaces()
  for id = 0, 103 do cards[id]:SetCard(SuitOf(id), RankOf(id)) end
end

function V.Undo()
  if burst then burst:Stop() end
  if game.won or #game.undo == 0 then return end
  sel, hint = nil, nil
  if Decode(table.remove(game.undo)) then ns.Sound("click") end
  Render()
end

function V.Deal()
  if burst then burst:Stop() end
  game = NewState(data.suits)
  data.game = game
  sel, hint = nil, nil
  ApplyFaces()
  local delays = {}
  for c = 1, 10 do
    for i, id in ipairs(game.tab[c]) do delays[id] = ((i - 1) * 10 + c) * 0.012 end
  end
  for id = 0, 103 do cards[id]:SetPos(StockX(), TOP_Y) end
  Render(delays)
end

function V.Show() if game then Render() end end

function V.Hide()
  if burst then burst:Stop() end
  dragger:Cancel()
  sel, hint = nil, nil
  if game then Render() end
end

-- Move the slots, buttons and cards for the current table size.
function V.ApplyLayout()
  local L = SetLayout(data.layout)
  for c = 1, 10 do
    slots[c]:SetSize(CW, CH)
    slots[c]:ClearAllPoints()
    slots[c]:SetPoint("TOPLEFT", page, "TOPLEFT", colx(c), -TAB_Y)
  end
  stockSlot:SetSize(CW, CH)
  stockSlot:ClearAllPoints()
  stockSlot:SetPoint("TOPLEFT", page, "TOPLEFT", StockX(), -TOP_Y)
  hintButton:ClearAllPoints()
  hintButton:SetPoint("TOP", page, "TOPLEFT", floor(TABLE_W / 2) + 10, -(TOP_Y + floor(CH / 2) - 11))
  for id = 0, 103 do
    if cards[id].size ~= L.size then cards[id]:SetLook(L.size) end
  end
  if game then Render() end
end

function V.Width()
  return TABLE_W
end

-- The chooser changed the table size.
function V.LayoutChanged()
  if not page then return end
  dragger:Cancel()
  V.ApplyLayout()
end

function V.Create(parent, saved, theHub)
  page, data, hub = parent, saved, theHub
  if data.suits ~= 1 and data.suits ~= 2 and data.suits ~= 4 then data.suits = 1 end
  if ValidGame(data.game) then game = data.game else data.game = nil end

  if not LAYOUTS[data.layout] then data.layout = "wide" end
  SetLayout(data.layout)
  for c = 1, 10 do
    local s = K.NewSlot(parent, colx(c), TAB_Y, CW, CH, nil, function()
      if game and sel then
        if not TryMove(sel.p, sel.from, c) then Bad() end
      end
    end)
    s.gold = UI.Border(s, ns.C.gold, 2, "OVERLAY")
    function s:SetSelected(on) for i = 1, 4 do self.gold[i]:SetShown(on and true or false) end end
    s:SetSelected(false)
    slots[c] = s
  end
  stockSlot = K.NewSlot(parent, StockX(), TOP_Y, CW, CH, nil, function() if game then DealRow() end end)

  dragger = K.NewDragger(parent, function() return UP_GAP end, Lift, DropAt)
  V.cards = {}
  for id = 0, 103 do
    local card = K.NewCard(parent, 1, RankOf(id), LAYOUTS[V.layout].size)
    card.id = id
    card:SetScript("OnClick", function(self, button) OnCard(self.id, button) end)
    K.Draggable(card, dragger)
    cards[id] = card
    V.cards[#V.cards + 1] = card
  end
  V.cascade = K.NewCascade(parent)
  burst = K.NewBurst(parent)

  -- Between the finished runs and the deck.
  hintButton = UI.Button(parent, "Hint", 70, 22)
  hintButton:SetScript("OnClick", ShowHint)

  V.ApplyLayout()
  if not game then
    V.Deal()
  else
    ApplyFaces()
    Render()
    if game.won then
      hub.ShowWon(V, format("%d %s in %s", game.suits, game.suits == 1 and "suit" or "suits", ns.FormatTime(game.elapsed)))
    end
  end
end
