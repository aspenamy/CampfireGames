-------------------------------------------------------------------------------
-- Campfire Games: Pairs
--
-- Click a face-down card to turn it over. Turn over a second card: if the
-- two pictures match they stay up in gold, otherwise both turn back down
-- after a moment. Find every pair in as few turns as you can. Fewer moves
-- is better. Pick 16 or 20 cards at the top, or start over with New game.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, min, max = math.floor, math.min, math.max

local SIZES = { 16, 20 }              -- cards on the table
local PICTURES = 10                   -- media pairs/p1 .. pairs/p10
local CARD_W, CARD_H = 58, 70         -- the size we aim for
local GAP = 6
local PAD = 6                         -- margin around the picture on a face
local FLIP_TIME = 0.1                 -- each half of a flip
local HOLD_TIME = 0.8                 -- a mismatch stays up this long
local AREA_TOP, AREA_H = 60, 360      -- room for the board under the top row
local BACK_TEX = ns.MEDIA .. "cards\\back"
local BACK_W, BACK_H = 64, 128
local PIC_TEX = ns.MEDIA .. "pairs\\p%d"
local PIC_W, PIC_H = 64, 64
local GLOW_TEX = ns.MEDIA .. "dot"

local panel, data, game
local boards = {}                     -- by size: frame, cards, overlay
local active                          -- the board on screen
local moveText, timeText, sizeRow
local open = {}                       -- cards up and not resolved yet (max 2)
local anims = {}                      -- cards in the middle of a flip
local hold                            -- { t = secs } while a mismatch shows
local shownSecs = -1
local Pick                            -- a card was clicked; set below

-------------------------------------------------------------------------------
-- Saved data
-------------------------------------------------------------------------------

local function ValidGame(g)
  if type(g) ~= "table" then return false end
  local size = g.size
  if size ~= 16 and size ~= 20 then return false end
  if type(g.deck) ~= "table" or type(g.matched) ~= "table" then return false end
  if type(g.finished) ~= "boolean" then return false end
  if type(g.moves) ~= "number" or g.moves < 0 or g.moves ~= floor(g.moves) then return false end
  if type(g.elapsed) ~= "number" or g.elapsed < 0 then return false end
  local seen, found = {}, {}
  for i = 1, size do
    local p, m = g.deck[i], g.matched[i]
    if type(p) ~= "number" or p ~= floor(p) or p < 1 or p > PICTURES then return false end
    if type(m) ~= "boolean" then return false end
    seen[p] = (seen[p] or 0) + 1
    if seen[p] > 2 then return false end
    if found[p] == nil then
      found[p] = m
    elseif found[p] ~= m then
      return false -- one card of a pair can't be matched alone
    end
  end
  for _, n in pairs(seen) do
    if n ~= 2 then return false end
  end
  return true
end

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------

-- Card and board sizes for a board of `size` cards (4 across).
local function Dims(size)
  local rows = size / 4
  local cardH = min(CARD_H, floor((AREA_H - GAP * (rows - 1)) / rows))
  local cardW = floor(cardH * CARD_W / CARD_H)
  return {
    cols = 4, rows = rows, cardW = cardW, cardH = cardH,
    boardW = 4 * cardW + 3 * GAP, boardH = rows * cardH + (rows - 1) * GAP,
  }
end

-- Show a texture at its own proportions inside a region, cropping the
-- overflow rather than stretching it.
local function Crop(tex, rw, rh, iw, ih)
  rw, rh = max(rw, 0.5), max(rh, 0.5)
  local ra, ia = rw / rh, iw / ih
  if ra >= ia then
    local t = (1 - ia / ra) / 2
    tex:SetTexCoord(0, 1, t, 1 - t)
  else
    local l = (1 - ra / ia) / 2
    tex:SetTexCoord(l, 1 - l, 0, 1)
  end
end

-- With the raid marks option on, the 16-card game uses the 8 marks as its
-- pictures (picture number p is mark p).
local function UseMarks(size)
  return size == 16 and ns.UseRaidMarks()
end

-- A 16-card deck started with the option off may hold pictures 9 or 10.
-- Swap those for unused numbers 1..8 so every pair still matches.
local function FitDeck(g)
  if not UseMarks(g.size) then return end
  local used, free, map = {}, {}, {}
  for i = 1, g.size do used[g.deck[i]] = true end
  for p = 1, 8 do
    if not used[p] then free[#free + 1] = p end
  end
  for i = 1, g.size do
    local p = g.deck[i]
    if p > 8 then
      if not map[p] then map[p] = table.remove(free) end
      g.deck[i] = map[p]
    end
  end
end

-- Set how wide a card looks: f = 1 is full size, 0 is edge-on.
local function SetFlipWidth(card, f)
  local b, v = card.board, card.visual
  local w = max(b.cardW * f, 0.5)
  v:SetSize(w, b.cardH)
  Crop(v.back, w, b.cardH, BACK_W, BACK_H)
  local pw, ph = max(w - 2 * PAD, 0.5), b.cardH - 2 * PAD
  if card.mark then
    -- Raid marks are square with empty margin: keep them square, a bit larger.
    local side = min(b.cardW - 2 * PAD, ph) * 1.1
    pw, ph = min(pw * 1.1, side), side
  end
  v.pic:SetSize(pw, ph)
  Crop(v.pic, pw, ph, PIC_W, PIC_H)
end

local function Paint(card)
  local v = card.visual
  local face = card.up or card.matched
  v.back:SetShown(not face)
  v.face:SetShown(face)
  v.pic:SetShown(face)
  card.glow:SetShown(card.matched)
  UI.SetBorderColor(v.border, card.matched and C.gold or C.line)
end

local function ResetCard(card, pic, matched)
  card.anim = nil
  card.up = false
  card.matched = matched and true or false
  card.pic = pic
  if pic then
    card.mark = UseMarks(card.board.size)
    card.visual.pic:SetTexture(card.mark and ns.RAID_MARKS[pic] or format(PIC_TEX, pic))
  end
  SetFlipWidth(card, 1)
  Paint(card)
end

local function MakeCard(board, i)
  local card = CreateFrame("Button", nil, board.frame)
  card.board = board
  card.index = i
  card:SetSize(board.cardW, board.cardH)
  local col, row = (i - 1) % board.cols, floor((i - 1) / board.cols)
  card:SetPoint("TOPLEFT", board.frame, "TOPLEFT",
    col * (board.cardW + GAP), -row * (board.cardH + GAP))
  card:RegisterForClicks("LeftButtonUp")

  card.glow = card:CreateTexture(nil, "BACKGROUND")
  card.glow:SetTexture(GLOW_TEX)
  card.glow:SetPoint("TOPLEFT", -8, 8)
  card.glow:SetPoint("BOTTOMRIGHT", 8, -8)
  card.glow:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.55)
  card.glow:SetBlendMode("ADD")
  card.glow:Hide()

  -- The visible card. Its width is what changes during a flip.
  local v = CreateFrame("Frame", nil, card)
  v:SetPoint("CENTER", card, "CENTER")
  v:SetSize(board.cardW, board.cardH)
  card.visual = v
  v.back = v:CreateTexture(nil, "ARTWORK")
  v.back:SetAllPoints(v)
  v.back:SetTexture(BACK_TEX)
  v.face = v:CreateTexture(nil, "ARTWORK")
  v.face:SetAllPoints(v)
  UI.Color(v.face, C.cream)
  v.pic = v:CreateTexture(nil, "OVERLAY")
  v.pic:SetPoint("CENTER", v, "CENTER")
  v.border = UI.Border(v, C.line, 1, "OVERLAY")

  card:SetScript("OnClick", function() Pick(card) end)
  card:SetScript("OnEnter", function()
    if not card.up and not card.matched then UI.SetBorderColor(v.border, C.gold) end
  end)
  card:SetScript("OnLeave", function() Paint(card) end)

  ResetCard(card, nil, false)
  return card
end

local function MakeBoard(parent, size)
  local d = Dims(size)
  d.size = size
  d.frame = CreateFrame("Frame", nil, parent)
  d.frame:SetSize(d.boardW, d.boardH)
  d.frame:SetPoint("TOP", parent, "TOP", 0, -(AREA_TOP + floor((AREA_H - d.boardH) / 2)))
  d.inset = UI.Inset(d.frame, d.boardW + 14, d.boardH + 14)
  d.inset:SetPoint("CENTER", d.frame, "CENTER")
  d.cards = {}
  for i = 1, size do d.cards[i] = MakeCard(d, i) end
  d.overlay = UI.Overlay(d.frame)
  d.frame:Hide()
  return d
end

local function ShowBoard(size)
  for s, b in pairs(boards) do
    b.frame:SetShown(s == size)
    if s ~= size then b.overlay:Close() end
  end
  active = boards[size]
  sizeRow:Select(tostring(size))
end

-------------------------------------------------------------------------------
-- Text
-------------------------------------------------------------------------------

local function ShowMoves()
  moveText:SetText(format("Moves: %d", game.moves))
end

local function ShowTime()
  local secs = floor(game.elapsed)
  if secs ~= shownSecs then
    shownSecs = secs
    timeText:SetText("Time: " .. ns.FormatTime(game.elapsed))
  end
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function Locked()
  return #anims > 0 or hold ~= nil
end

local function Flip(card, toUp, onDone)
  card.anim = { t = 0, phase = 1, toUp = toUp, onDone = onDone }
  anims[#anims + 1] = card
end

local function Win()
  game.finished = true
  local key = "best_" .. game.size
  local newBest = ns.RecordResult("pairs", {
    won = true, score = game.moves, lowerIsBetter = true, bestKey = key,
  })
  ns.Sound("win")
  local best = data.stats[key]
  boards[game.size].overlay:Open(newBest and "A new best!" or "All matched!",
    format("%d moves in %s\nBest: %d moves", game.moves, ns.FormatTime(game.elapsed), best))
end

-- Two cards are face up: a match stays, a miss turns back after a moment.
local function Revealed()
  if #open < 2 then return end
  local a, b = open[1], open[2]
  if a.pic == b.pic then
    a.matched, b.matched = true, true
    game.matched[a.index], game.matched[b.index] = true, true
    open = {}
    Paint(a)
    Paint(b)
    ns.Sound("good")
    local found = 0
    for i = 1, game.size do
      if game.matched[i] then found = found + 1 end
    end
    if found == game.size then Win() end
  else
    hold = { t = 0 }
  end
end

Pick = function(card)
  if not game or game.finished or Locked() then return end
  if card.up or card.matched or #open >= 2 then return end
  ns.Sound("page")
  open[#open + 1] = card
  if #open == 2 then
    game.moves = game.moves + 1
    ShowMoves()
  end
  Flip(card, true, Revealed)
end

-- Runs every frame the panel is shown: the clock, flips and the hold.
local function Tick(_, dt)
  if not game then return end
  if not game.finished then
    game.elapsed = game.elapsed + dt
    ShowTime()
  end

  for k = #anims, 1, -1 do
    local card = anims[k]
    local a = card.anim
    a.t = a.t + dt
    if a.phase == 1 and a.t >= FLIP_TIME then
      -- Edge-on: swap the face while the card is thinnest.
      a.phase, a.t = 2, 0
      card.up = a.toUp
      Paint(card)
    end
    if a.phase == 1 then
      SetFlipWidth(card, 1 - a.t / FLIP_TIME)
    else
      local f = min(a.t / FLIP_TIME, 1)
      SetFlipWidth(card, f)
      if f >= 1 then
        table.remove(anims, k)
        card.anim = nil
        if a.onDone then a.onDone(card) end
      end
    end
  end

  if hold then
    hold.t = hold.t + dt
    if hold.t >= HOLD_TIME then
      hold = nil
      local a, b = open[1], open[2]
      open = {}
      Flip(a, false)
      Flip(b, false)
    end
  end
end

-- Called when the window hides: finish any flip, turn a shown miss back
-- down, so the saved state is a clean one.
local function Settle()
  if not game then return end
  local list = {}
  for k, card in ipairs(anims) do list[k] = card end
  anims = {}
  for _, card in ipairs(list) do
    local a = card.anim
    card.anim = nil
    card.up = a.toUp
    SetFlipWidth(card, 1)
    Paint(card)
    if a.onDone then a.onDone(card) end
  end
  if hold then
    hold = nil
    for _, card in ipairs(open) do
      card.up = false
      Paint(card)
    end
    open = {}
  end
end

local function NewGame(size)
  for _, b in pairs(boards) do b.overlay:Close() end
  anims, open, hold = {}, {}, nil

  local pics = {}
  for p = 1, UseMarks(size) and 8 or PICTURES do pics[p] = p end
  ns.Shuffle(pics)
  local deck = {}
  for i = 1, size / 2 do
    deck[i] = pics[i]
    deck[size / 2 + i] = pics[i]
  end
  ns.Shuffle(deck)

  local matched = {}
  for i = 1, size do matched[i] = false end
  game = {
    size = size, deck = deck, matched = matched,
    moves = 0, elapsed = 0, finished = false,
  }
  data.game = game
  data.size = size

  local b = boards[size]
  for i = 1, size do ResetCard(b.cards[i], deck[i], false) end
  ShowBoard(size)
  shownSecs = -1
  ShowMoves()
  ShowTime()
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function Create(parent, saved)
  panel = parent
  data = saved
  if data.size ~= 16 and data.size ~= 20 then data.size = 16 end

  for _, size in ipairs(SIZES) do boards[size] = MakeBoard(parent, size) end

  moveText = UI.Text(parent, 12, C.cream)
  moveText:SetPoint("TOPLEFT", 14, -36)
  timeText = UI.Text(parent, 12, C.cream)
  timeText:SetPoint("TOPRIGHT", -14, -36)

  sizeRow = UI.Choice(parent, {
    { key = "16", label = "16 cards" },
    { key = "20", label = "20 cards" },
  }, 194, function(key)
    -- Clicking the size you're already playing keeps the game going.
    if game and game.size == tonumber(key) and not game.finished and (game.moves or 0) > 0 then return end
    NewGame(tonumber(key))
  end)
  sizeRow:SetPoint("TOPLEFT", 10, -6)

  local newButton = UI.Button(parent, "New game", 96, 22)
  newButton:SetPoint("TOPRIGHT", -10, -6)
  newButton:SetScript("OnClick", function()
    NewGame(game and game.size or data.size)
  end)

  parent:SetScript("OnUpdate", Tick)

  ns.OnPiecesChanged(function()
    if not game then return end
    FitDeck(game)
    local b = boards[game.size]
    for i = 1, game.size do
      local card = b.cards[i]
      card.pic = game.deck[i]
      card.mark = UseMarks(game.size)
      card.visual.pic:SetTexture(card.mark and ns.RAID_MARKS[card.pic] or format(PIC_TEX, card.pic))
      SetFlipWidth(card, 1)
      Paint(card)
    end
  end)

  if ValidGame(data.game) then
    game = data.game
    FitDeck(game)
    ShowBoard(game.size)
    local b = boards[game.size]
    for i = 1, game.size do
      ResetCard(b.cards[i], game.deck[i], game.matched[i])
    end
    shownSecs = -1
    ShowMoves()
    ShowTime()
    if game.finished then
      b.overlay:Open("All matched!", format("%d moves in %s\nBest: %d moves",
        game.moves, ns.FormatTime(game.elapsed), data.stats["best_" .. game.size] or game.moves))
    end
  else
    data.game = nil
    game = nil
    NewGame(data.size)
  end
end

ns.RegisterGame({
  key = "pairs",
  name = "Pairs",
  blurb = "Turn over two cards at a time and find every match.",
  icon = ns.MEDIA .. "icons\\pairs",
  order = 80,
  hasWins = true,
  Create = Create,
  OnHide = Settle,
  InProgress = function(d)
    local g = type(d) == "table" and d.game or nil
    if not ValidGame(g) then return false end
    return not g.finished and g.moves > 0
  end,
  Summary = function(d)
    local s = d.stats or {}
    local best = s.best_16 or s.best_20
    return best and format("Best %d moves", best) or ""
  end,
})
