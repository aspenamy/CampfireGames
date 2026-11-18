-------------------------------------------------------------------------------
-- Campfire Games: Solitaire - Pyramid
--
-- Take the pyramid apart by pairing cards that add up to 13: Queen and Ace,
-- Jack and 2, 10 and 3, and so on. Kings count 13 and go on their own.
-- A card is free when no card overlaps it from below. The top card of the
-- waste is free too. Click the deck to turn a card; you can go through the
-- deck three times. Clear all 28 pyramid cards to win.
-------------------------------------------------------------------------------

local _, ns = ...

local K = ns.CardKit
local floor = math.floor
local SuitOf, RankOf = K.SuitOf, K.RankOf

local CW, CH = 38, 52
local PITCH, ROW = 40, 27
local PY = 24
local STOCK_X, WASTE_X, GONE_X, LOW_Y = 50, 104, 232, 266
local PASSES = 3
local MAX_UNDO = 120

local V = {
  key = "pyramid", name = "Pyramid", order = 40,
  help = "Take the pyramid apart by pairing two free cards that add up to 13. Aces count 1, Jacks 11, Queens 12 and Kings 13, so a King goes on its own.\n\n"
    .. "A card is free when no card overlaps its bottom edge. Cards that aren't free yet are shaded. The top card of the waste pile (next to the deck) is free too.\n\n"
    .. "Click one card and then its partner. Click the deck to turn over a card. You can go through the deck three times.\n\n"
    .. "Clear all 28 pyramid cards to win.",
}
ns.SolitaireVariants = ns.SolitaireVariants or {}
ns.SolitaireVariants.pyramid = V

local data, game, hub, page
local cards, where = {}, {}
local sel
local stockSlot, wasteSlot, goneSlot, passText

local function RowOf(k)
  local r = 1
  while k > r * (r + 1) / 2 do r = r + 1 end
  return r, k - r * (r - 1) / 2
end

local function Index(r, i) return r * (r - 1) / 2 + i end

local function PyrXY(k)
  local r, i = RowOf(k)
  local x = floor((ns.GAME_W - (r * PITCH - 2)) / 2) + (i - 1) * PITCH
  return x, PY + (r - 1) * ROW
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local function NewState()
  local deck = {}
  for i = 0, 51 do deck[#deck + 1] = i end
  ns.Shuffle(deck)
  local g = { pyr = {}, stock = {}, waste = {}, gone = {}, passes = 1, moves = 0, elapsed = 0, won = false, undo = {} }
  for k = 1, 28 do g.pyr[k] = deck[k] end
  for n = 29, 52 do g.stock[#g.stock + 1] = deck[n] end
  return g
end

local function ValidGame(g)
  if type(g) ~= "table" or type(g.pyr) ~= "table" or type(g.moves) ~= "number" or type(g.elapsed) ~= "number" then return false end
  if type(g.passes) ~= "number" then return false end
  local seen, count = {}, 0
  for k = 1, 28 do
    local v = g.pyr[k]
    if type(v) ~= "number" or v > 51 or v ~= floor(v) then return false end
    if v >= 0 then
      if seen[v] then return false end
      seen[v] = true
    end
  end
  for _, list in ipairs({ g.stock, g.waste, g.gone }) do
    if type(list) ~= "table" then return false end
    for _, v in ipairs(list) do
      if type(v) ~= "number" or v < 0 or v > 51 or seen[v] then return false end
      seen[v] = true
    end
  end
  for _ in pairs(seen) do count = count + 1 end
  if count ~= 52 then return false end
  if type(g.undo) ~= "table" then g.undo = {} end
  g.won = g.won and true or false
  return true
end

local function Encode()
  return table.concat({ table.concat(game.pyr, ","), table.concat(game.stock, ","), table.concat(game.waste, ","),
    table.concat(game.gone, ","), game.passes, game.moves }, ";")
end

local function ToList(s)
  local out = {}
  for n in s:gmatch("%-?%d+") do out[#out + 1] = tonumber(n) end
  return out
end

local function Decode(s)
  local seg = {}
  for part in (s .. ";"):gmatch("([^;]*);") do seg[#seg + 1] = part end
  if #seg ~= 6 then return false end
  game.pyr, game.stock, game.waste, game.gone = ToList(seg[1]), ToList(seg[2]), ToList(seg[3]), ToList(seg[4])
  game.passes = tonumber(seg[5]) or 1
  game.moves = tonumber(seg[6]) or 0
  return true
end

local function Snapshot()
  game.undo[#game.undo + 1] = Encode()
  if #game.undo > MAX_UNDO then table.remove(game.undo, 1) end
end

-------------------------------------------------------------------------------
-- Rules
-------------------------------------------------------------------------------

local function Free(k)
  if game.pyr[k] < 0 then return false end
  local r, i = RowOf(k)
  if r == 7 then return true end
  return game.pyr[Index(r + 1, i)] < 0 and game.pyr[Index(r + 1, i + 1)] < 0
end

local function Cleared()
  local n = 0
  for k = 1, 28 do if game.pyr[k] < 0 then n = n + 1 end end
  return n
end

-- Every free card: { k = "p"/"w", p = index, id }.
local function FreeCards()
  local out = {}
  for k = 1, 28 do
    if Free(k) then out[#out + 1] = { k = "p", p = k, id = game.pyr[k] } end
  end
  local w = game.waste[#game.waste]
  if w then out[#out + 1] = { k = "w", p = 1, id = w } end
  return out
end

local function AnyPair()
  local list = FreeCards()
  for a = 1, #list do
    if RankOf(list[a].id) == 13 then return true end
    for b = a + 1, #list do
      if RankOf(list[a].id) + RankOf(list[b].id) == 13 then return true end
    end
  end
  return false
end

local function Stuck()
  if #game.stock > 0 or (#game.waste > 0 and game.passes < PASSES) then return false end
  return not AnyPair()
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function Render(dealing)
  if not game then return end
  for k = 1, 28 do
    local id = game.pyr[k]
    if id >= 0 then
      where[id] = { k = "p", p = k }
      local x, y = PyrXY(k)
      local card = cards[id]
      card:SetFaceUp(true)
      card:SetDim(not Free(k) and not game.won)
      card:SetSelected(sel and sel.k == "p" and sel.p == k)
      card:MoveTo(x, y, k, dealing and k * 0.03 or nil)
    end
  end
  for i, id in ipairs(game.stock) do
    where[id] = { k = "s" }
    cards[id]:SetFaceUp(false)
    cards[id]:SetDim(false)
    cards[id]:SetSelected(false)
    cards[id]:MoveTo(STOCK_X, LOW_Y, i)
  end
  for i, id in ipairs(game.waste) do
    where[id] = { k = "w", pos = i }
    cards[id]:SetFaceUp(true)
    cards[id]:SetDim(false)
    cards[id]:SetSelected(sel and sel.k == "w" and i == #game.waste)
    cards[id]:MoveTo(WASTE_X, LOW_Y, i)
  end
  for i, id in ipairs(game.gone) do
    where[id] = { k = "g" }
    cards[id]:SetFaceUp(true)
    cards[id]:SetDim(false)
    cards[id]:SetSelected(false)
    cards[id]:MoveTo(GONE_X, LOW_Y, i)
  end
  stockSlot.again:SetShown(#game.stock == 0 and #game.waste > 0 and game.passes < PASSES)
  passText:SetText(format("Pass %d of %d", game.passes, PASSES))
  if hub then hub.Refresh() end
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function CheckEnd()
  if Cleared() == 28 then
    game.won = true
    game.undo = {}
    sel = nil
    Render()
    local order = {}
    for i = #game.gone, 1, -1 do
      local card = cards[game.gone[i]]
      card:StopMoving()
      order[#order + 1] = card
    end
    local t = floor(game.elapsed)
    hub.Won(V, {
      time = t, lowerIsBetter = true, bestKey = "best_pyramid",
      line = format("Cleared in %s, pass %d of %d", ns.FormatTime(t), game.passes, PASSES), cards = order,
    })
  elseif Stuck() then
    hub.Stuck(V, format("Cleared %d of 28 pyramid cards", Cleared()))
  end
end

local function Take(ref)
  if ref.k == "p" then
    game.gone[#game.gone + 1] = game.pyr[ref.p]
    game.pyr[ref.p] = -1
  else
    game.gone[#game.gone + 1] = table.remove(game.waste)
  end
end

local function Remove(a, b)
  Snapshot()
  Take(a)
  if b then Take(b) end
  game.moves = game.moves + 1
  sel = nil
  ns.Sound("place")
  Render()
  CheckEnd()
end

local function DrawCard()
  if game.won then return end
  sel = nil
  if #game.stock > 0 then
    Snapshot()
    game.waste[#game.waste + 1] = table.remove(game.stock)
  elseif #game.waste > 0 and game.passes < PASSES then
    Snapshot()
    for i = #game.waste, 1, -1 do game.stock[#game.stock + 1] = game.waste[i] end
    game.waste = {}
    game.passes = game.passes + 1
  else
    return
  end
  game.moves = game.moves + 1
  ns.Sound("page")
  Render()
  CheckEnd()
end

local function RefOf(id)
  local w = where[id]
  if not w then return nil end
  if w.k == "p" and Free(w.p) then return { k = "p", p = w.p, id = id } end
  if w.k == "w" and w.pos == #game.waste then return { k = "w", p = 1, id = id } end
  return nil
end

local function OnCard(id)
  if game.won then return end
  local w = where[id]
  if not w then return end
  if w.k == "s" then DrawCard() return end
  local ref = RefOf(id)
  if not ref then
    ns.Sound("bad")
    return
  end
  if RankOf(id) == 13 then Remove(ref) return end
  if sel and sel.k == ref.k and sel.p == ref.p then
    sel = nil
    Render()
    return
  end
  if sel then
    local other = sel.k == "p" and game.pyr[sel.p] or game.waste[#game.waste]
    if other and RankOf(other) + RankOf(id) == 13 then
      Remove({ k = sel.k, p = sel.p }, ref)
      return
    end
    ns.Sound("bad")
  else
    ns.Sound("click")
  end
  sel = { k = ref.k, p = ref.p }
  Render()
end

-------------------------------------------------------------------------------
-- Hub hooks
-------------------------------------------------------------------------------

function V.InProgress(d)
  local g = type(d) == "table" and d.game or nil
  return ValidGame(g) and not g.won and g.moves >= 5
end

function V.Tick(dt)
  if game and not game.won then game.elapsed = game.elapsed + dt end
end

function V.Title() return "Pyramid" end
function V.Left() return game and format("Cleared %d of 28", Cleared()) or "" end
function V.Elapsed() return game and game.elapsed or 0 end
function V.CanUndo() return game and #game.undo > 0 end
function V.IsWon() return game and game.won end
function V.HasProgress() return game and not game.won and game.moves > 0 end
function V.Option() return nil end

function V.Undo()
  if game.won or #game.undo == 0 then return end
  sel = nil
  if Decode(table.remove(game.undo)) then ns.Sound("click") end
  Render()
end

function V.Deal()
  game = NewState()
  data.game = game
  sel = nil
  for id = 0, 51 do cards[id]:SetPos(STOCK_X, LOW_Y) end
  Render(true)
end

function V.Show() if game then Render() end end
function V.Hide() sel = nil if game then Render() end end

function V.Create(parent, saved, theHub)
  page, data, hub = parent, saved, theHub
  if ValidGame(data.game) then game = data.game else data.game = nil end
  stockSlot = K.NewSlot(parent, STOCK_X, LOW_Y, CW, CH, nil, function() if game then DrawCard() end end)
  stockSlot.again = stockSlot:CreateTexture(nil, "ARTWORK")
  stockSlot.again:SetTexture(ns.MEDIA .. "dot")
  stockSlot.again:SetSize(22, 22)
  stockSlot.again:SetPoint("CENTER")
  stockSlot.again:SetVertexColor(ns.C.dim[1], ns.C.dim[2], ns.C.dim[3], 0.6)
  wasteSlot = K.NewSlot(parent, WASTE_X, LOW_Y, CW, CH)
  goneSlot = K.NewSlot(parent, GONE_X, LOW_Y, CW, CH)
  passText = ns.UI.Text(parent, 11, ns.C.dim)
  passText:SetPoint("TOP", stockSlot, "BOTTOM", 0, -6)
  local goneText = ns.UI.Text(parent, 11, ns.C.dim)
  goneText:SetPoint("TOP", goneSlot, "BOTTOM", 0, -6)
  goneText:SetText("Cleared")

  V.cards = {}
  for id = 0, 51 do
    local card = K.NewCard(parent, SuitOf(id), RankOf(id), "mid")
    card.id = id
    card:SetScript("OnClick", function(self) OnCard(self.id) end)
    cards[id] = card
    V.cards[#V.cards + 1] = card
  end
  V.cascade = K.NewCascade(parent)

  if not game then
    V.Deal()
  else
    Render()
    if game.won then hub.ShowWon(V, format("Cleared in %s", ns.FormatTime(game.elapsed))) end
  end
end
