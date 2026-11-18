-------------------------------------------------------------------------------
-- Campfire Games: Solitaire - Tri Peaks
--
-- Clear three peaks of cards. Play any uncovered card that is one higher or
-- one lower than the card on the waste pile (King and Ace wrap around).
-- It becomes the new waste card. Click the deck for a new waste card when
-- you're stuck. Each card in an unbroken chain scores one more than the
-- last; clearing a peak scores a bonus. Clear all three peaks to win.
-------------------------------------------------------------------------------

local _, ns = ...

local K = ns.CardKit
local floor, abs = math.floor, math.abs
local SuitOf, RankOf = K.SuitOf, K.RankOf

-- Two tables: wide (the window grows, bigger cards) and narrow (fits the
-- normal window). Shared with Spider's setting in the chooser.
-- u is half the pitch of the bottom row.
local LAYOUTS = {
  wide = { w = 424, size = "mid", cw = 38, ch = 52, u = 20.5, rows = { 62, 100, 138, 176 }, low = 262 },
  narrow = { w = 320, size = "small", cw = 30, ch = 42, u = 15.5, rows = { 64, 94, 124, 154 }, low = 250 },
}
local CW, CH, U, X0, ROW_Y, STOCK_X, WASTE_X, LOW_Y, TABLE_W

local function SetLayout(name)
  local L = LAYOUTS[name] or LAYOUTS.wide
  CW, CH, U, ROW_Y, LOW_Y, TABLE_W = L.cw, L.ch, L.u, L.rows, L.low, L.w
  X0 = floor((TABLE_W - (18 * U + CW)) / 2)
  local mid = floor(TABLE_W / 2)
  STOCK_X, WASTE_X = mid - 56, mid + 26
  if name == "narrow" then STOCK_X, WASTE_X = 104, 186 end
  return L
end
SetLayout("wide")
local PEAK_BONUS = 15
local MAX_UNDO = 120

local V = {
  key = "tripeaks", name = "Tri Peaks", order = 50,
  help = "Clear the three peaks.\n\n"
    .. "Click any face-up card that is one higher or one lower than the card on the waste pile, below the peaks. It becomes the new waste card, so you can keep a chain going. King and Ace count as next to each other.\n\n"
    .. "Cards turn face up when nothing covers them. Click the deck for a new waste card when nothing fits.\n\n"
    .. "Each card in a chain scores one more than the card before it, and the deck starts a new chain. Clearing a peak scores 15. Win with cards left in the deck for 5 more each.",
}
ns.SolitaireVariants = ns.SolitaireVariants or {}
ns.SolitaireVariants.tripeaks = V

local data, game, hub, page
local cards, where = {}, {}
local stockSlot, wasteSlot, streakText

-- Cards covering each position (two each above the bottom row).
local COVER = {}
for t = 0, 2 do
  COVER[1 + t] = { 4 + 2 * t, 5 + 2 * t }
end
for j = 0, 5 do
  local t, k = floor(j / 2), j % 2
  COVER[4 + j] = { 10 + 3 * t + k, 11 + 3 * t + k }
end
for j = 0, 8 do
  COVER[10 + j] = { 19 + j, 20 + j }
end

local function PosXY(n)
  local center, row
  if n <= 3 then
    row, center = 1, (6 * (n - 1) + 4) * U
  elseif n <= 9 then
    local j = n - 4
    row, center = 2, (6 * floor(j / 2) + 2 * (j % 2) + 3) * U
  elseif n <= 18 then
    row, center = 3, (2 * (n - 10) + 2) * U
  else
    row, center = 4, (2 * (n - 19) + 1) * U
  end
  return floor(X0 + center - CW / 2 + 0.5), ROW_Y[row]
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local function NewState()
  local deck = {}
  for i = 0, 51 do deck[#deck + 1] = i end
  ns.Shuffle(deck)
  local g = { peaks = {}, stock = {}, waste = {}, moves = 0, elapsed = 0, score = 0, chain = 0, won = false, undo = {} }
  for n = 1, 28 do g.peaks[n] = deck[n] end
  for n = 29, 51 do g.stock[#g.stock + 1] = deck[n] end
  g.waste[1] = deck[52]
  return g
end

local function ValidGame(g)
  if type(g) ~= "table" or type(g.peaks) ~= "table" or type(g.stock) ~= "table" or type(g.waste) ~= "table" then return false end
  if type(g.moves) ~= "number" or type(g.elapsed) ~= "number" or type(g.score) ~= "number" or type(g.chain) ~= "number" then return false end
  local seen, count = {}, 0
  for n = 1, 28 do
    local v = g.peaks[n]
    if type(v) ~= "number" or v > 51 or v ~= floor(v) then return false end
    if v >= 0 then
      if seen[v] then return false end
      seen[v] = true
    end
  end
  for _, list in ipairs({ g.stock, g.waste }) do
    for _, v in ipairs(list) do
      if type(v) ~= "number" or v < 0 or v > 51 or seen[v] then return false end
      seen[v] = true
    end
  end
  for _ in pairs(seen) do count = count + 1 end
  if count ~= 52 or #g.waste < 1 then return false end
  if type(g.undo) ~= "table" then g.undo = {} end
  g.won = g.won and true or false
  return true
end

local function Encode()
  return table.concat({ table.concat(game.peaks, ","), table.concat(game.stock, ","), table.concat(game.waste, ","),
    game.moves, game.score, game.chain }, ";")
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
  game.peaks, game.stock, game.waste = ToList(seg[1]), ToList(seg[2]), ToList(seg[3])
  game.moves = tonumber(seg[4]) or 0
  game.score = tonumber(seg[5]) or 0
  game.chain = tonumber(seg[6]) or 0
  return true
end

local function Snapshot()
  game.undo[#game.undo + 1] = Encode()
  if #game.undo > MAX_UNDO then table.remove(game.undo, 1) end
end

-------------------------------------------------------------------------------
-- Rules
-------------------------------------------------------------------------------

local function Open(n)
  if game.peaks[n] < 0 then return false end
  local cover = COVER[n]
  if not cover then return true end
  return game.peaks[cover[1]] < 0 and game.peaks[cover[2]] < 0
end

local function Fits(id)
  local top = game.waste[#game.waste]
  local d = abs(RankOf(id) - RankOf(top))
  return d == 1 or d == 12
end

local function Left()
  local n = 0
  for i = 1, 28 do if game.peaks[i] >= 0 then n = n + 1 end end
  return n
end

local function CanPlay()
  for n = 1, 28 do
    if Open(n) and Fits(game.peaks[n]) then return true end
  end
  return false
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function Render(dealing)
  if not game then return end
  for n = 1, 28 do
    local id = game.peaks[n]
    if id >= 0 then
      where[id] = { k = "p", p = n }
      local x, y = PosXY(n)
      cards[id]:SetFaceUp(Open(n))
      cards[id]:MoveTo(x, y, n, dealing and n * 0.025 or nil)
    end
  end
  for i, id in ipairs(game.stock) do
    where[id] = { k = "s" }
    cards[id]:SetFaceUp(false)
    cards[id]:MoveTo(STOCK_X - floor((i - 1) / 4) * 2, LOW_Y, i)
  end
  for i, id in ipairs(game.waste) do
    where[id] = { k = "w" }
    cards[id]:SetFaceUp(true)
    cards[id]:MoveTo(WASTE_X, LOW_Y, i)
  end
  if game.chain > 1 then
    streakText:SetText(format("Chain of %d", game.chain))
  else
    streakText:SetText("")
  end
  if hub then hub.Refresh() end
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function CheckEnd()
  if Left() == 0 then
    game.won = true
    game.undo = {}
    game.score = game.score + 5 * #game.stock
    Render()
    local order = {}
    for i = #game.waste, 1, -1 do
      local card = cards[game.waste[i]]
      card:StopMoving()
      order[#order + 1] = card
    end
    local t = floor(game.elapsed)
    hub.Won(V, {
      score = game.score, bestKey = "best_tripeaks",
      line = format("Score %s in %s, %d left in the deck", ns.FormatNumber(game.score), ns.FormatTime(t), #game.stock),
      cards = order,
    })
  elseif #game.stock == 0 and not CanPlay() then
    hub.Stuck(V, format("Cleared %d of 28, score %s", 28 - Left(), ns.FormatNumber(game.score)))
  end
end

local function Play(n)
  local id = game.peaks[n]
  Snapshot()
  game.peaks[n] = -1
  game.waste[#game.waste + 1] = id
  game.moves = game.moves + 1
  game.chain = game.chain + 1
  game.score = game.score + game.chain
  if n <= 3 then
    game.score = game.score + PEAK_BONUS
    if Left() > 0 then hub.Toast("Peak cleared") end
  end
  ns.Sound("place")
  if game.chain >= 3 then ns.PlayTone("bell" .. math.min(4, game.chain - 2)) end
  Render()
  CheckEnd()
end

local function Turn()
  if game.won or #game.stock == 0 then return end
  Snapshot()
  game.waste[#game.waste + 1] = table.remove(game.stock)
  game.moves = game.moves + 1
  game.chain = 0
  ns.Sound("page")
  Render()
  CheckEnd()
end

local function OnCard(id)
  if game.won then return end
  local w = where[id]
  if not w then return end
  if w.k == "s" then Turn() return end
  if w.k ~= "p" then return end
  if Open(w.p) and Fits(id) then
    Play(w.p)
  else
    ns.Sound("bad")
  end
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

function V.Title() return "Tri Peaks" end
function V.Left() return game and ("Score " .. ns.FormatNumber(game.score)) or "" end
function V.Elapsed() return game and game.elapsed or 0 end
function V.CanUndo() return game and #game.undo > 0 end
function V.IsWon() return game and game.won end
function V.HasProgress() return game and not game.won and game.moves > 0 end
function V.Option() return nil end

function V.Undo()
  if game.won or #game.undo == 0 then return end
  if Decode(table.remove(game.undo)) then ns.Sound("click") end
  Render()
end

function V.Deal()
  game = NewState()
  data.game = game
  for id = 0, 51 do cards[id]:SetPos(STOCK_X, LOW_Y) end
  Render(true)
end

function V.Show() if game then Render() end end
function V.Hide() end

local function Size() return hub and hub.TableSize and hub.TableSize() or "wide" end

-- Move the slots and cards for the current table size.
function V.ApplyLayout()
  local L = SetLayout(Size())
  stockSlot:SetSize(CW, CH)
  stockSlot:ClearAllPoints()
  stockSlot:SetPoint("TOPLEFT", page, "TOPLEFT", STOCK_X, -LOW_Y)
  wasteSlot:SetSize(CW, CH)
  wasteSlot:ClearAllPoints()
  wasteSlot:SetPoint("TOPLEFT", page, "TOPLEFT", WASTE_X, -LOW_Y)
  streakText:ClearAllPoints()
  streakText:SetPoint("TOP", page, "TOPLEFT", WASTE_X + CW / 2, -(LOW_Y + CH + 8))
  for id = 0, 51 do
    if cards[id].size ~= L.size then cards[id]:SetLook(L.size) end
  end
  if game then Render() end
end

function V.Width() return TABLE_W end

-- The chooser changed the table size.
function V.LayoutChanged()
  if page then V.ApplyLayout() end
end

function V.Create(parent, saved, theHub)
  page, data, hub = parent, saved, theHub
  if ValidGame(data.game) then game = data.game else data.game = nil end
  local L = SetLayout(Size())
  stockSlot = K.NewSlot(parent, STOCK_X, LOW_Y, CW, CH, nil, function() if game then Turn() end end)
  wasteSlot = K.NewSlot(parent, WASTE_X, LOW_Y, CW, CH)
  streakText = ns.UI.Title(parent, 14)

  V.cards = {}
  for id = 0, 51 do
    local card = K.NewCard(parent, SuitOf(id), RankOf(id), L.size)
    card.id = id
    card:SetScript("OnClick", function(self) OnCard(self.id) end)
    cards[id] = card
    V.cards[#V.cards + 1] = card
  end
  V.cascade = K.NewCascade(parent)
  V.ApplyLayout()

  if not game then
    V.Deal()
  else
    Render()
    if game.won then hub.ShowWon(V, format("Score %s", ns.FormatNumber(game.score))) end
  end
end
