-------------------------------------------------------------------------------
-- Campfire Games: Solitaire card kit
--
-- Shared by every Solitaire game: card faces in three sizes, card backs,
-- cards that glide to where they go, dragging, and the bouncing cards that
-- play out a win.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt

local K = {}
ns.CardKit = K

K.RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
K.SUIT_TEX = { "spade", "heart", "diamond", "club" }
K.RED_INK = { 0.70, 0.12, 0.10 }
K.BLACK_INK = { 0.10, 0.08, 0.07 }
K.PARCHMENT = { 0.94, 0.88, 0.74 }

K.BACKS = {
  { tex = "back", name = "Wine" },
  { tex = "back2", name = "Forest" },
  { tex = "back3", name = "Midnight" },
  { tex = "back4", name = "Ember" },
}

-- Card sizes: width, height, rank font, small suit, big suit, big suit offset.
K.SIZES = {
  big = { 42, 58, 11, 10, 24, -6 },
  mid = { 38, 52, 11, 9, 22, -5 },
  small = { 30, 42, 9, 8, 15, -5 },
}

-- Ids 0..51 (and 52..103 for a second deck): suit = floor(id / 13) % 4 + 1
-- (1 spade, 2 heart, 3 diamond, 4 club), rank = id % 13 + 1.
function K.SuitOf(id) return floor(id / 13) % 4 + 1 end
function K.RankOf(id) return id % 13 + 1 end
function K.IsRedSuit(s) return s == 2 or s == 3 end
function K.IsRed(id) return K.IsRedSuit(K.SuitOf(id)) end

K.prefs = { back = 1 }
local allCards = {}

function K.BackPath()
  local b = K.BACKS[K.prefs.back] or K.BACKS[1]
  return ns.MEDIA .. "cards\\" .. b.tex
end

function K.RefreshBacks()
  local path = K.BackPath()
  for _, card in ipairs(allCards) do card.back:SetTexture(path) end
end

-------------------------------------------------------------------------------
-- Cards
-------------------------------------------------------------------------------

local CardMethods = {}

function CardMethods:SetCard(suit, rank)
  self.suit, self.rankN = suit, rank
  local ink = K.IsRedSuit(suit) and K.RED_INK or K.BLACK_INK
  self.rank:SetTextColor(ink[1], ink[2], ink[3], 1)
  self.rank:SetText(K.RANKS[rank])
  self.small:SetTexture(ns.MEDIA .. "cards\\" .. K.SUIT_TEX[suit])
  self.big:SetTexture(ns.MEDIA .. "cards\\" .. K.SUIT_TEX[suit])
end

-- Card size: "big", "mid" or "small" (see K.SIZES).
function CardMethods:SetLook(size)
  local sz = K.SIZES[size] or K.SIZES.big
  self.size, self.w, self.h = size, sz[1], sz[2]
  self:SetSize(sz[1], sz[2])
  self.rank:SetFont(ns.FONT, sz[3], "")
  self.rank:ClearAllPoints()
  self.rank:SetPoint("TOPLEFT", size == "small" and 2 or 3, size == "small" and -2 or -3)
  self.small:SetSize(sz[4], sz[4])
  self.big:SetSize(sz[5], sz[5])
  self.big:ClearAllPoints()
  self.big:SetPoint("CENTER", 0, sz[6])
end

function CardMethods:SetFaceUp(up)
  up = up and true or false
  if self.up == up then return end
  self.up = up
  self.rank:SetShown(up)
  self.small:SetShown(up)
  self.big:SetShown(up)
  self.back:SetShown(not up)
end

function CardMethods:SetSelected(on)
  on = on and true or false
  if self.selected == on then return end
  self.selected = on
  for i = 1, 4 do self.gold[i]:SetShown(on) end
end

function CardMethods:SetDim(on)
  self.shade:SetShown(on and true or false)
end

local function StepMove(self, dt)
  self.t = self.t + dt
  if self.t < 0 then return end
  local p = min(1, self.t / self.dur)
  local e = 1 - (1 - p) * (1 - p) * (1 - p)
  self:SetPos(self.fx + (self.tx - self.fx) * e, self.fy + (self.ty - self.fy) * e)
  if p >= 1 then
    self.moving = false
    self:SetScript("OnUpdate", nil)
    self:SetFrameLevel(self.home:GetFrameLevel() + 2 + self.z)
  end
end

-- Put the card at x, y (from the top left of its parent, y down) right now.
function CardMethods:SetPos(x, y)
  self.cx, self.cy = x, y
  self:ClearAllPoints()
  self:SetPoint("TOPLEFT", self.home, "TOPLEFT", floor(x + 0.5), -floor(y + 0.5))
end

-- Glide the card to x, y. z orders cards on the table (higher is on top).
-- delay holds it in place first, for dealing one card after another.
function CardMethods:MoveTo(x, y, z, delay)
  self.z = z
  self:Show()
  if self.moving and self.tx == x and self.ty == y then return end
  if not self.cx or K.instant or (self.cx == x and self.cy == y) then
    self.moving = false
    self:SetScript("OnUpdate", nil)
    self:SetPos(x, y)
    self:SetFrameLevel(self.home:GetFrameLevel() + 2 + z)
    return
  end
  local dx, dy = x - self.cx, y - self.cy
  self.fx, self.fy, self.tx, self.ty = self.cx, self.cy, x, y
  self.dur = max(0.09, min(0.24, sqrt(dx * dx + dy * dy) / 1300))
  self.t = -(delay or 0)
  self.moving = true
  self:SetFrameLevel(self.home:GetFrameLevel() + 150 + min(z, 90))
  self:SetScript("OnUpdate", StepMove)
end

function CardMethods:StopMoving()
  if self.moving then
    self.moving = false
    self:SetScript("OnUpdate", nil)
    self:SetPos(self.tx, self.ty)
  end
end

-- A card button on parent. size is "big", "mid" or "small".
function K.NewCard(parent, suit, rank, size)
  local b = CreateFrame("Button", nil, parent)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.home, b.z = parent, 0
  for k, fn in pairs(CardMethods) do b[k] = fn end

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  UI.Color(bg, K.PARCHMENT)
  UI.Border(b, C.lineDark, 1, "BORDER")
  b.gold = UI.Border(b, C.gold, 2, "OVERLAY")
  for i = 1, 4 do b.gold[i]:Hide() end

  b.rank = b:CreateFontString(nil, "OVERLAY")
  b.small = b:CreateTexture(nil, "ARTWORK")
  b.small:SetPoint("LEFT", b.rank, "RIGHT", 1, 0)
  b.big = b:CreateTexture(nil, "ARTWORK")
  b:SetLook(size)

  b.back = b:CreateTexture(nil, "ARTWORK")
  b.back:SetTexture(K.BackPath())
  b.back:SetPoint("TOPLEFT", 1, -1)
  b.back:SetPoint("BOTTOMRIGHT", -1, 1)
  b.back:SetTexCoord(0, 1, 0.156, 0.844)
  b.back:Hide()

  b.shade = b:CreateTexture(nil, "OVERLAY")
  b.shade:SetAllPoints()
  b.shade:SetColorTexture(0.05, 0.03, 0.02, 0.38)
  b.shade:Hide()

  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 0.85, 0.5, 0.18)

  b.up = true
  b:SetCard(suit, rank)
  b:Hide()
  allCards[#allCards + 1] = b
  return b
end

-- An empty spot on the table: a faint outline, with an optional letter.
function K.NewSlot(parent, x, y, w, h, letter, onClick)
  local s = CreateFrame("Button", nil, parent)
  s:SetSize(w, h)
  s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  s:SetFrameLevel(parent:GetFrameLevel() + 1)
  s.empty = CreateFrame("Frame", nil, s)
  s.empty:SetAllPoints()
  UI.Border(s.empty, C.faint, 1, "ARTWORK", 0.55)
  if letter then
    local a = UI.Text(s.empty, h >= 50 and 18 or 14, C.faint, ns.FONT_TITLE)
    a:SetPoint("CENTER")
    a:SetText(letter)
    a:SetAlpha(0.6)
    s.letter = a
  end
  if onClick then s:SetScript("OnClick", onClick) end
  return s
end

-------------------------------------------------------------------------------
-- Dragging
--
-- K.NewDragger(page, lift, drop): lift(card) returns a list of card frames
-- to carry (the pressed card first) and any info, or nil. drop(info, x, y)
-- gets the middle of the carried card in page coordinates, y down.
-------------------------------------------------------------------------------

function K.CursorXY(frame)
  local x, y = GetCursorPosition()
  local s = frame:GetEffectiveScale()
  return x / s - frame:GetLeft(), frame:GetTop() - y / s
end

function K.NewDragger(page, gap, lift, drop)
  local d = CreateFrame("Frame", nil, page)
  d:Hide()
  local carry
  local function Update()
    if not carry then return end
    local x, y = K.CursorXY(page)
    local step = type(gap) == "function" and gap() or gap
    for j, card in ipairs(carry.cards) do
      card:StopMoving()
      card:SetPos(x - carry.ox, y - carry.oy + (j - 1) * step)
      card:SetFrameLevel(page:GetFrameLevel() + 260 + j)
    end
  end
  d:SetScript("OnUpdate", Update)
  function d:Start(card)
    local list, info = lift(card)
    if not list or #list == 0 then return end
    card:StopMoving()
    local x, y = K.CursorXY(page)
    carry = { cards = list, info = info, ox = x - (card.cx or 0), oy = y - (card.cy or 0), w = card.w, h = card.h }
    self:Show()
    Update()
  end
  function d:Stop()
    if not carry then return end
    local c = carry
    carry = nil
    self:Hide()
    local x, y = K.CursorXY(page)
    drop(c.info, x - c.ox + c.w / 2, y - c.oy + c.h / 2)
  end
  function d:Cancel()
    carry = nil
    self:Hide()
  end
  function d:Active() return carry ~= nil end
  return d
end

-- Hook a card's drag scripts to a dragger.
function K.Draggable(card, dragger)
  card:RegisterForDrag("LeftButton")
  card:SetScript("OnDragStart", function(self) dragger:Start(self) end)
  card:SetScript("OnDragStop", function() dragger:Stop() end)
end

-------------------------------------------------------------------------------
-- Bouncing cards: on a win the cards leap off the table one at a time and
-- bounce along the bottom, leaving a trail of themselves behind.
-------------------------------------------------------------------------------

local GHOSTS = 520
local GHOST_STEP = 5
local GRAVITY = 820
local LAUNCH_GAP = 0.22

function K.NewCascade(page)
  local fx = CreateFrame("Frame", nil, page)
  fx:SetAllPoints()
  fx:SetFrameLevel(page:GetFrameLevel() + 400)
  fx:SetClipsChildren(true)
  fx:Hide()
  -- Catches a click while the cards fly; the trails stay after it hides.
  local catcher = CreateFrame("Button", nil, fx)
  catcher:SetAllPoints()
  catcher:SetFrameLevel(fx:GetFrameLevel() + 1700)
  catcher:Hide()
  local playing = false
  local ghosts, nextGhost, levelN = {}, 1, 0
  local queue, flying, clock, onDone, gap = {}, {}, 0, nil, LAUNCH_GAP

  local function Ghost(card)
    local g = ghosts[nextGhost]
    if not g then
      g = CreateFrame("Frame", nil, fx)
      local bg = g:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      UI.Color(bg, K.PARCHMENT)
      UI.Border(g, C.lineDark, 1, "BORDER")
      g.rank = g:CreateFontString(nil, "OVERLAY")
      g.small = g:CreateTexture(nil, "ARTWORK")
      g.big = g:CreateTexture(nil, "ARTWORK")
      ghosts[nextGhost] = g
    end
    nextGhost = nextGhost % GHOSTS + 1
    if g.card ~= card then
      g.card = card
      g:SetSize(card.w, card.h)
      local font, size = card.rank:GetFont()
      g.rank:SetFont(font or ns.FONT, size or 11, "")
      g.rank:ClearAllPoints()
      g.rank:SetPoint("TOPLEFT", card.w < 34 and 2 or 3, card.w < 34 and -2 or -3)
      local ink = K.IsRedSuit(card.suit) and K.RED_INK or K.BLACK_INK
      g.rank:SetTextColor(ink[1], ink[2], ink[3], 1)
      g.rank:SetText(K.RANKS[card.rankN])
      local tex = ns.MEDIA .. "cards\\" .. K.SUIT_TEX[card.suit]
      local sw = card.small:GetWidth()
      g.small:SetTexture(tex)
      g.small:SetSize(sw, sw)
      g.small:ClearAllPoints()
      g.small:SetPoint("LEFT", g.rank, "RIGHT", 1, 0)
      local bw = card.big:GetWidth()
      g.big:SetTexture(tex)
      g.big:SetSize(bw, bw)
      g.big:ClearAllPoints()
      g.big:SetPoint("CENTER", 0, card.h >= 50 and -6 or -5)
    end
    levelN = levelN + 1
    if levelN > 1500 then levelN = 1 end
    g:SetFrameLevel(fx:GetFrameLevel() + levelN)
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", fx, "TOPLEFT", floor(card.cx + 0.5), -floor(card.cy + 0.5))
    g:Show()
  end

  local function Land(f)
    f.card:SetPos(f.x, f.y)
    f.card:SetFrameLevel(fx:GetFrameLevel() + 1600)
  end

  local function Done()
    playing = false
    catcher:Hide()
    local fn = onDone
    onDone = nil
    for _, f in ipairs(flying) do f.card:Hide() end
    for _, card in ipairs(queue) do card:Hide() end
    flying, queue = {}, {}
    if fn then fn() end
  end

  fx:SetScript("OnUpdate", function(_, dt)
    if not playing then return end
    dt = min(dt, 0.05)
    clock = clock + dt
    if #queue > 0 and clock >= gap then
      clock = 0
      local card = table.remove(queue, 1)
      card:StopMoving()
      card:SetParent(fx)
      card:Show()
      local dir = math.random() < 0.5 and -1 or 1
      flying[#flying + 1] = {
        card = card, x = card.cx or 0, y = card.cy or 0,
        vx = dir * (70 + math.random() * 110), vy = -(math.random() * 260),
        gx = card.cx or 0, gy = card.cy or 0,
      }
    end
    local floorY = ns.GAME_H - 2
    for i = #flying, 1, -1 do
      local f = flying[i]
      f.vy = f.vy + GRAVITY * dt
      f.x = f.x + f.vx * dt
      f.y = f.y + f.vy * dt
      if f.y + f.card.h > floorY then
        f.y = floorY - f.card.h
        f.vy = -abs(f.vy) * 0.78
      end
      Land(f)
      local dx, dy = f.x - f.gx, f.y - f.gy
      if dx * dx + dy * dy >= GHOST_STEP * GHOST_STEP then
        f.gx, f.gy = f.x, f.y
        Ghost(f.card)
      end
      if f.x < -f.card.w - 2 or f.x > page:GetWidth() + 2 then
        f.card:Hide()
        table.remove(flying, i)
      end
    end
    if #queue == 0 and #flying == 0 then Done() end
  end)
  -- A click lets the rest go.
  catcher:SetScript("OnClick", function() Done() end)

  local cascade = {}
  -- cards: card frames in launch order, each where it sits now.
  function cascade:Play(cards, done)
    for _, g in ipairs(ghosts) do g:Hide(); g.card = nil end
    gap = min(LAUNCH_GAP, 12 / max(1, #cards))
    nextGhost, levelN, clock = 1, 0, gap
    queue, flying, onDone = {}, {}, done
    for i, card in ipairs(cards) do queue[i] = card end
    playing = true
    fx:Show()
    catcher:Show()
  end
  function cascade:Stop()
    if playing then Done() end
  end
  -- Clear the trails and give the cards back to their table.
  function cascade:Clear(home)
    if playing then Done() end
    for _, g in ipairs(ghosts) do g:Hide() end
    fx:Hide()
    if home then
      for _, card in ipairs(home) do
        if card:GetParent() ~= card.home then card:SetParent(card.home) end
      end
    end
  end
  function cascade:Busy() return playing end
  return cascade
end

-------------------------------------------------------------------------------
-- Sparkle bursts: a shower of warm sparks and a soft ring of light, plus a
-- little scheduler for timing sounds to go with them.
-------------------------------------------------------------------------------

local SPARKS = 26
local BURST_TIME = 0.9

function K.NewBurst(page)
  local fx = CreateFrame("Frame", nil, page)
  fx:SetAllPoints()
  fx:SetFrameLevel(page:GetFrameLevel() + 380)
  local pool, live, later = {}, {}, {}

  local function Spark()
    local s = table.remove(pool)
    if not s then
      s = { tex = fx:CreateTexture(nil, "OVERLAY") }
      s.tex:SetTexture(ns.MEDIA .. "dot")
      s.tex:SetBlendMode("ADD")
    end
    return s
  end

  local function Ring()
    local r = Spark()
    r.ring = true
    r.tex:SetTexture(ns.MEDIA .. "glow")
    return r
  end

  local function Start(x, y)
    local r = Ring()
    r.x, r.y, r.age, r.vx, r.vy = x, y, 0, 0, 0
    live[#live + 1] = r
    for _ = 1, SPARKS do
      local s = Spark()
      local a = math.random() * 6.283
      local v = 55 + math.random() * 95
      s.x, s.y, s.age = x, y, -math.random() * 0.08
      s.vx, s.vy = math.cos(a) * v, math.sin(a) * v - 40
      s.size = 7 + math.random() * 9
      local warm = math.random()
      s.tex:SetVertexColor(1, 0.62 + warm * 0.3, 0.25 + warm * 0.35, 1)
      live[#live + 1] = s
    end
    fx:Show()
  end

  fx:SetScript("OnUpdate", function(_, dt)
    dt = min(dt, 0.05)
    for i = #later, 1, -1 do
      local l = later[i]
      l.t = l.t - dt
      if l.t <= 0 then
        table.remove(later, i)
        l.fn()
      end
    end
    for i = #live, 1, -1 do
      local s = live[i]
      s.age = s.age + dt
      local p = s.age / BURST_TIME
      if p >= 1 then
        s.tex:Hide()
        if s.ring then
          s.ring = nil
          s.tex:SetTexture(ns.MEDIA .. "dot")
        end
        table.remove(live, i)
        pool[#pool + 1] = s
      elseif s.age >= 0 then
        s.tex:ClearAllPoints()
        if s.ring then
          local size = 40 + p * 120
          s.tex:SetSize(size, size)
          s.tex:SetVertexColor(1, 0.78, 0.4, 0.55 * (1 - p))
          s.tex:SetPoint("CENTER", fx, "TOPLEFT", s.x, -s.y)
        else
          s.vy = s.vy + 160 * dt
          s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
          s.tex:SetSize(s.size * (1 - p * 0.5), s.size * (1 - p * 0.5))
          s.tex:SetAlpha(1 - p * p)
          s.tex:SetPoint("CENTER", fx, "TOPLEFT", s.x, -s.y)
        end
        s.tex:Show()
      end
    end
    if #live == 0 and #later == 0 then fx:Hide() end
  end)
  fx:Hide()

  local burst = {}
  -- A burst at x, y (page coordinates, y down) after delay seconds.
  function burst:Play(x, y, delay)
    self:Later(delay or 0, function() Start(x, y) end)
  end
  function burst:Later(delay, fn)
    later[#later + 1] = { t = delay, fn = fn }
    fx:Show()
  end
  function burst:Stop()
    later = {}
    for _, s in ipairs(live) do
      s.tex:Hide()
      if s.ring then s.ring = nil; s.tex:SetTexture(ns.MEDIA .. "dot") end
      pool[#pool + 1] = s
    end
    live = {}
    fx:Hide()
  end
  return burst
end
