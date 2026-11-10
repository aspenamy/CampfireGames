-------------------------------------------------------------------------------
-- Campfire Games: Fireflies
--
-- A firefly flies through little glowing lights. Press on a light and drag
-- through its neighbors of the same color (up, down, left, right); the
-- firefly follows your line, leaving a trail of light. Drag back to undo a
-- link, let go to catch them. Rewards:
--   5+ linked   the last light stays as a beacon: when caught it clears its
--               whole row and column
--   8+ linked   the last light becomes a dewdrop, which counts as any color
--   a loop      (end on a light already in your line) catches every light
--               of that color, and lights inside the loop burst like
--               lanterns, clearing the space around them
--   10+ linked  a swarm: catches every light of that color too
-- Catching 6 or more in a move, twice in a row, starts a glow streak that
-- multiplies score.
--
-- Levels (saved as mode "jars"): reach the target score by the last move to
-- pass. Each level has bonus goals (lights of a color, broken webs,
-- collected seeds); meeting one adds a score bonus. New pieces arrive as levels
-- go on: dewdrops (any color), twin lights (either of two colors), cobwebs
-- (break them by catching a light next to them) and seeds (drop them to the
-- bottom to collect them). 30 Moves: best score. Relaxed: no limit.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, sin, cos, abs, random = math.floor, math.sin, math.cos, math.abs, math.random
local band = bit.band

local N, CELL = 7, 40
local SIZE = N * CELL -- 280
local KINDS = 5
local MOVES = 30
local BEACON_AT, DEW_AT, SWARM_AT = 5, 8, 10

-- Piece codes. Add WEB for a cobweb over the piece.
local DEW, SEED, WEB = 20, 50, 1000
-- 1-5 light, 11-15 beacon of that color, 100 + 10a + b twin of colors a < b.
local BIT = { 1, 2, 4, 8, 16 }
local ALL = 31

local MODES = {
  { key = "jars", label = "Levels" },
  { key = "moves", label = "30 Moves" },
  { key = "relaxed", label = "Relaxed" },
}

local COLORS = {
  { 1.00, 0.84, 0.35 },  -- gold
  { 0.52, 0.94, 0.46 },  -- green
  { 0.45, 0.76, 1.00 },  -- blue
  { 1.00, 0.48, 0.40 },  -- coral
  { 0.76, 0.56, 1.00 },  -- violet
}
local WHITE = { 0.88, 0.94, 1 }
local COLOR_NAMES = { "gold", "green", "blue", "coral", "violet" }
local RAID = { 1, 4, 6, 7, 3 }   -- star, triangle, square, cross, diamond
local FLY_COLOR = { 0.86, 1, 0.55 }

local ART = ns.MEDIA .. "fireflies\\"
local ORB_TEX, DEW_TEX, SEED_TEX = ART .. "orb", ART .. "dew", ART .. "seed"
local RING_TEX, WEB_TEX, BEAM_TEX, FLY_TEX = ART .. "ring", ART .. "web", ART .. "beam", ART .. "fly"
local GLOW_TEX = ns.MEDIA .. "dot"
local LANTERN_TEX = ns.MEDIA .. "lanterns\\lit"
local SPARK_TEX = ns.MEDIA .. "gems\\spark"

-- New pieces get a card the first time a level brings them in.
local INTRO = {
  dew = { "Dewdrops", "A clear dewdrop counts as any color. Link it into any line." },
  twin = { "Twin lights", "A twin light is two colors at once. It links with either one." },
  web = { "Cobwebs", "A light under a cobweb can't be linked. Catch a light next to it to break the web. Broken webs count toward the web bonus." },
  seed = { "Seeds", "Seeds can't be linked. Catch the lights under them so they drop to the bottom row, where they're collected. Beacon beams and lantern bursts collect them too." },
}

local data, b, pc, cfg
local panel, field, layer, overlay, toast
local scoreText, rightText, infoText, goalRow, modeRow, nextButton, againButton, playButton
local cells = {}
local phase = "idle"
local now = 0
local chain, chainMask, closed = {}, ALL, nil
local born, closedBorn = {}, 0      -- when each link was made, for the fade-in
local ghost, ghostAt                -- the line just released, fading out
local pending
local pool, segs, sparks, motes, floats, flashes, beams = {}, {}, {}, {}, {}, {}, {}
local fly = { x = SIZE / 2, y = SIZE / 2, tx = SIZE / 2, ty = SIZE / 2, ang = 0, wander = 0, moteT = 0 }
local lastToneAt = 0

-------------------------------------------------------------------------------
-- Pieces
-------------------------------------------------------------------------------

local function Base(code) return code % WEB end
local function Webbed(code) return code >= WEB end
local function IsTwin(c) return c > 100 and c < 150 end
local function TwinColors(c) return floor((c - 100) / 10), (c - 100) % 10 end
local function Has(mask, k) return band(mask, BIT[k]) ~= 0 end

-- Colors a piece counts as (ignores webs).
local function Colors(code)
  local c = Base(code)
  if c == DEW then return ALL end
  if c == SEED or c == 0 then return 0 end
  if IsTwin(c) then
    local a, d = TwinColors(c)
    return BIT[a] + BIT[d]
  end
  return BIT[c % 10]
end

-- Colors it can be linked as right now (webbed pieces can't be linked).
local function Mask(code)
  if Webbed(code) then return 0 end
  return Colors(code)
end

local function OnlyColor(mask)
  for k = 1, KINDS do
    if mask == BIT[k] then return k end
  end
end

local function FirstColor(mask)
  for k = 1, KINDS do
    if Has(mask, k) then return k end
  end
end

local function CellXY(i) return ((i - 1) % N + 0.5) * CELL, (floor((i - 1) / N) + 0.5) * CELL end
local function RC(i) return floor((i - 1) / N), (i - 1) % N end
local function Smooth(t)
  if t >= 1 then return 1 end
  if t <= 0 then return 0 end
  return t * t * (3 - 2 * t)
end

local function Adjacent(a, c)
  local ra, ca = RC(a)
  local rc, cc = RC(c)
  return abs(ra - rc) + abs(ca - cc) == 1
end

-------------------------------------------------------------------------------
-- Levels
-------------------------------------------------------------------------------

-- A small fixed random sequence, so a level is the same every time.
local function Seq(n)
  local s = (n * 7919 + 17) % 65536
  return function(m)
    s = (s * 25173 + 13849) % 65536
    return s % m
  end
end

local function Cfg(mode, n)
  local c = { dew = 0, twin = 0, webs = 0, seeds = 0, colors = 0 }
  if mode ~= "jars" then
    c.dew, c.twin = 0.025, 0.06
    return c
  end
  local T = {
    { 1 }, { 1 }, { 2 }, { 2 },
    { 2, dew = true, intro = "dew" }, { 3, dew = true },
    { 2, dew = true, twin = true, intro = "twin" }, { 2, dew = true, twin = true }, { 3, dew = true, twin = true },
    { 1, dew = true, webs = 8, intro = "web" }, { 2, dew = true, twin = true, webs = 10 }, { 2, dew = true, twin = true, webs = 12 },
    { 1, dew = true, seeds = 3, intro = "seed" }, { 2, dew = true, twin = true, seeds = 4 },
    { 1, dew = true, twin = true, webs = 10, seeds = 4 },
  }
  local t = T[n]
  if not t then
    local r = Seq(n)
    t = { 1 + r(3), dew = true, twin = true }
    local pick = r(3)
    if pick ~= 1 then t.webs = 8 + r(6) end
    if pick ~= 0 then t.seeds = 3 + r(3) end
    if t.webs and t.seeds and t[1] > 2 then t[1] = 2 end
  end
  c.colors = t[1]
  c.dew = t.dew and 0.03 or 0
  c.twin = t.twin and 0.09 or 0
  c.webs, c.seeds, c.intro = t.webs or 0, t.seeds or 0, t.intro
  if c.seeds > 0 then
    c.amount = math.min(14, 2 + n)
  elseif c.webs > 0 then
    c.amount = math.min(22, 8 + n)
  else
    c.amount = math.min(26, 8 + 2 * n)
  end
  c.moves = 14 + 4 * c.colors + floor(c.webs / 4) + 3 * c.seeds + math.min(4, floor(n / 5))
  -- Score to pass: checked against a simple simulated player, which reaches
  -- it about 4 times in 5 early on and about half the time later.
  c.target = floor(c.moves * math.min(110, 40 + 3 * n) / 50 + 0.5) * 50
  return c
end

-------------------------------------------------------------------------------
-- Board
-------------------------------------------------------------------------------

local MIN_LINK = 2

-- Is there a pair that could be linked?
local function HasMove(board)
  for i = 1, N * N do
    local r, c = RC(i)
    local m = Mask(board[i])
    if m ~= 0 then
      if c < N - 1 and band(m, Mask(board[i + 1])) ~= 0 then return true end
      if r < N - 1 and band(m, Mask(board[i + N])) ~= 0 then return true end
    end
  end
  return false
end

local function NewCode()
  local r = random()
  if r < cfg.dew then return DEW end
  if r < cfg.dew + cfg.twin then
    local a, d = random(KINDS), random(KINDS - 1)
    if d >= a then d = d + 1 end
    if a > d then a, d = d, a end
    return 100 + 10 * a + d
  end
  return random(KINDS)
end

local function FreshBoard()
  local nb
  repeat
    nb = {}
    for i = 1, N * N do nb[i] = NewCode() end
    -- Cobwebs over plain lights in the lower rows.
    local spots = {}
    for i = 2 * N + 1, N * N do
      if nb[i] <= KINDS then spots[#spots + 1] = i end
    end
    ns.Shuffle(spots)
    local webs = cfg.webs > 0 and math.min(#spots, cfg.webs + 2) or 0
    for k = 1, webs do nb[spots[k]] = nb[spots[k]] + WEB end
    -- Seeds start partway down.
    if cfg.seeds > 0 then
      local cols = ns.Shuffle({ 1, 2, 3, 4, 5, 6, 7 })
      for k = 1, math.min(2, cfg.seeds) do nb[4 * N + cols[k]] = SEED end
    end
  until HasMove(nb)
  return nb
end

-------------------------------------------------------------------------------
-- Sprites
-------------------------------------------------------------------------------

local function NewPiece()
  local p = table.remove(pool)
  if not p then
    p = {}
    p.glow = layer:CreateTexture(nil, "ARTWORK", nil, 0)
    p.glow:SetTexture(GLOW_TEX)
    p.glow:SetBlendMode("ADD")
    p.tex = layer:CreateTexture(nil, "ARTWORK", nil, 2)
    p.tex2 = layer:CreateTexture(nil, "ARTWORK", nil, 2)
    p.deco = layer:CreateTexture(nil, "ARTWORK", nil, 4)
  end
  p.x, p.y, p.sc, p.al = 0, 0, 1, 1
  p.mv, p.clr, p.pop, p.hot, p.lit = nil, nil, nil, nil, nil
  p.ph = random() * 6.28
  p.tex:Show()
  p.glow:Show()
  return p
end

local function FreePiece(p)
  p.tex:Hide()
  p.tex2:Hide()
  p.deco:Hide()
  p.glow:Hide()
  pool[#pool + 1] = p
end

local function LightTex(t, k)
  if ns.UseRaidMarks() then
    t:SetTexture(ns.RAID_MARKS[RAID[k]])
    t:SetVertexColor(1, 1, 1)
  else
    t:SetTexture(ORB_TEX)
    t:SetVertexColor(COLORS[k][1], COLORS[k][2], COLORS[k][3])
  end
end

local function SetCode(p, code)
  p.code = code
  local c = Base(code)
  p.tex:SetTexCoord(0, 1, 0, 1)
  p.tex2:Hide()
  p.deco:Hide()
  p.twin, p.beacon = false, false
  local gc
  if c == DEW then
    p.tex:SetTexture(DEW_TEX)
    p.tex:SetVertexColor(1, 1, 1)
    gc = WHITE
  elseif c == SEED then
    p.tex:SetTexture(SEED_TEX)
    p.tex:SetVertexColor(1, 1, 1)
    gc = { 1, 0.75, 0.4 }
  elseif IsTwin(c) then
    local a, d = TwinColors(c)
    LightTex(p.tex, a)
    LightTex(p.tex2, d)
    p.tex:SetTexCoord(0, 0.5, 0, 1)
    p.tex2:SetTexCoord(0.5, 1, 0, 1)
    p.tex2:Show()
    p.twin = true
    gc = { (COLORS[a][1] + COLORS[d][1]) / 2, (COLORS[a][2] + COLORS[d][2]) / 2, (COLORS[a][3] + COLORS[d][3]) / 2 }
  else
    local k = c % 10
    LightTex(p.tex, k)
    gc = COLORS[k]
    if c > 10 then
      p.beacon = true
      p.deco:SetTexture(RING_TEX)
      p.deco:SetVertexColor(gc[1], gc[2], gc[3])
      p.deco:SetBlendMode("ADD")
      p.deco:Show()
    end
  end
  if Webbed(code) then
    p.deco:SetTexture(WEB_TEX)
    p.deco:SetVertexColor(1, 1, 1)
    p.deco:SetBlendMode("BLEND")
    p.deco:SetRotation(0)
    p.deco:Show()
  end
  p.glow:SetVertexColor(gc[1], gc[2], gc[3])
end

local function Place(t, w, h, x, y, point)
  t:SetSize(w, h)
  t:ClearAllPoints()
  t:SetPoint(point or "CENTER", field, "TOPLEFT", x, -y)
end

local function Draw(p)
  local c = Base(p.code)
  local sc = p.sc * (p.hot and 1.2 or 1)
  local s = (ns.UseRaidMarks() and c ~= DEW and c ~= SEED and 24 or 26) * sc
  local webbed = Webbed(p.code)
  local bob = webbed and 0 or 1.1 * sin(now * 1.4 + p.ph)
  local x, y = p.x, p.y + bob
  if p.twin then
    Place(p.tex, s / 2, s, x, y, "RIGHT")
    Place(p.tex2, s / 2, s, x, y, "LEFT")
    p.tex2:SetAlpha(p.al)
  else
    Place(p.tex, s, s, x, y)
  end
  p.tex:SetAlpha(p.al)
  local tw = 0.5 + 0.5 * sin(now * 1.8 + p.ph)
  local gs, ga = 40, 0.35 + 0.25 * tw
  if p.beacon then
    local pulse = 0.5 + 0.5 * sin(now * 5 + p.ph)
    gs, ga = 52 + 8 * pulse, 0.55 + 0.35 * pulse
    Place(p.deco, s * 1.5, s * 1.5, x, y)
    p.deco:SetRotation(now * 0.8 + p.ph)
    p.deco:SetAlpha((0.6 + 0.4 * pulse) * p.al)
  elseif webbed then
    Place(p.deco, CELL - 2, CELL - 2, p.x, p.y)
    p.deco:SetAlpha(0.85 * p.al)
    gs, ga = 30, 0.15
  elseif c == DEW then
    gs, ga = 46, 0.45 + 0.25 * tw
  end
  if p.hot or p.lit then gs, ga = gs * 1.25, math.min(1, ga + 0.45) end
  Place(p.glow, gs * p.sc, gs * p.sc, x, y)
  p.glow:SetAlpha(ga * p.al)
end

local function MakePiece(i, code, fromY)
  local p = NewPiece()
  SetCode(p, code)
  p.x, p.y = CellXY(i)
  if fromY then p.y = fromY end
  Draw(p)
  return p
end

local function Pop(p) p.pop = 0; p.sc = 0.4 end

local function MoveTo(p, x, y, dur)
  p.mv = { x0 = p.x, y0 = p.y, x1 = x, y1 = y, t = 0, d = dur }
end

local function Step(p, dt)
  local busy = false
  if p.mv then
    local m = p.mv
    m.t = m.t + dt
    local e = Smooth(m.t / m.d)
    p.x, p.y = m.x0 + (m.x1 - m.x0) * e, m.y0 + (m.y1 - m.y0) * e
    if m.t >= m.d then p.mv = nil else busy = true end
  end
  if p.clr then
    p.clr = p.clr + dt
    local e = p.clr / 0.28
    if e >= 1 then
      p.clr, p.sc, p.al = 1, 1.7, 0
    else
      p.sc, p.al = 1 + 0.7 * e, 1 - e   -- swell and fade
      busy = true
    end
  end
  if p.pop then
    busy = true
    p.pop = p.pop + dt
    local e = p.pop / 0.22
    if e >= 1 then
      p.pop, p.sc = nil, 1
    else
      p.sc = 0.4 + 0.6 * Smooth(e) + 0.12 * sin(math.max(0, e) * 3.14159)
    end
  end
  return busy
end

local function Rebuild()
  for i = 1, N * N do
    if pc[i] then FreePiece(pc[i]); pc[i] = nil end
  end
  for i = 1, N * N do
    pc[i] = MakePiece(i, b[i])
    Pop(pc[i])
    pc[i].pop = -random() * 0.15
  end
end

-------------------------------------------------------------------------------
-- Effects
-------------------------------------------------------------------------------

local function Grab(list)
  for _, e in ipairs(list) do
    if not e.on then return e end
  end
end

local function Spark(x, y, color)
  local s = Grab(sparks)
  if not s then return end
  s.on, s.age, s.life = true, 0, 0.4 + random() * 0.3
  s.x, s.y = x, y
  s.vx, s.vy = (random() - 0.5) * 70, -random() * 50 - 10
  s.size = 16
  s.tex:SetVertexColor(color[1], color[2], color[3])
  s.tex:Show()
end

-- A small mote of light shed by the firefly: drifts up a little and fades.
local function Mote(x, y, color)
  local s = Grab(motes)
  if not s then return end
  s.on, s.age, s.life = true, 0, 0.7 + random() * 0.5
  s.x, s.y = x + (random() - 0.5) * 6, y + (random() - 0.5) * 6
  s.vx, s.vy = (random() - 0.5) * 10, -6 - random() * 10
  s.size = 6 + random() * 5
  s.tex:SetVertexColor(color[1], color[2], color[3])
  s.tex:Show()
end

local function Floater(x, y, text, color)
  local f = Grab(floats) or floats[1]
  f.on, f.age, f.x, f.y = true, 0, math.max(40, math.min(SIZE - 40, x)), y
  f.fs:SetText(text)
  UI.SetTextColor(f.fs, color or C.gold)
  f.fs:Show()
end

local function Flash(x, y)
  local f = Grab(flashes)
  if not f then return end
  f.on, f.age, f.x, f.y = true, 0, x, y
  f.tex:Show()
  f.glow:Show()
end

local function Beam(i, color)
  local x, y = CellXY(i)
  for horiz = 0, 1 do
    local bm = Grab(beams)
    if bm then
      bm.on, bm.age = true, 0
      if horiz == 1 then
        bm.tex:SetTexCoord(0, 1, 0, 1)
        Place(bm.tex, SIZE + 20, 22, SIZE / 2, y)
      else
        bm.tex:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)   -- turned upright
        Place(bm.tex, 22, SIZE + 20, x, SIZE / 2)
      end
      bm.tex:SetVertexColor(color[1], color[2], color[3])
      bm.tex:Show()
    end
  end
end

local function StepParticles(list, dt, fade)
  for _, s in ipairs(list) do
    if s.on then
      s.age = s.age + dt
      local e = s.age / s.life
      if e >= 1 then
        s.on = false
        s.tex:Hide()
      else
        s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
        local z = s.size * (fade and (1 - 0.5 * e) or (0.6 + 0.8 * e))
        Place(s.tex, z, z, s.x, s.y)
        s.tex:SetAlpha(fade and (1 - e) * (0.6 + 0.4 * sin(s.age * 12)) or (1 - e))
      end
    end
  end
end

local function UpdateEffects(dt)
  StepParticles(sparks, dt, false)
  StepParticles(motes, dt, true)
  for _, f in ipairs(floats) do
    if f.on then
      f.age = f.age + dt
      local e = f.age / 1.1
      if e >= 1 then
        f.on = false
        f.fs:Hide()
      else
        f.fs:ClearAllPoints()
        f.fs:SetPoint("CENTER", field, "TOPLEFT", f.x, -(f.y - 28 * Smooth(e)))
        f.fs:SetAlpha(e < 0.5 and 1 or (1 - e) * 2)
      end
    end
  end
  for _, f in ipairs(flashes) do
    if f.on then
      f.age = f.age + dt
      local e = f.age / 0.5
      if e >= 1 then
        f.on = false
        f.tex:Hide()
        f.glow:Hide()
      else
        local z = 30 + 30 * Smooth(e)
        Place(f.tex, z, z, f.x, f.y)
        f.tex:SetAlpha(1 - e)
        Place(f.glow, z * 3, z * 3, f.x, f.y)
        f.glow:SetAlpha(0.8 * (1 - e))
      end
    end
  end
  for _, bm in ipairs(beams) do
    if bm.on then
      bm.age = bm.age + dt
      local e = bm.age / 0.5
      if e >= 1 then
        bm.on = false
        bm.tex:Hide()
      else
        bm.tex:SetAlpha(1 - e)
      end
    end
  end
end

-------------------------------------------------------------------------------
-- The trail of light
-------------------------------------------------------------------------------

local function LineColor(mask)
  local k = OnlyColor(mask or chainMask)
  return k and COLORS[k] or WHITE
end

-- Each link is a soft wide glow with a bright core. New links fade in;
-- a released line fades out.
local function DrawSeg(n, a, c, alpha, col)
  local s = segs[n]
  if not s then return end
  local ax, ay = CellXY(a)
  local cx, cy = CellXY(c)
  local mx, my = (ax + cx) / 2, (ay + cy) / 2
  local len = abs(cx - ax) + abs(cy - ay) + 14
  local shimmer = 0.85 + 0.15 * sin(now * 6 + n)
  for _, part in ipairs(s) do
    local w = part.wide and 20 or 7
    if ay == cy then
      part.tex:SetTexCoord(0, 1, 0, 1)
      Place(part.tex, len, w, mx, my)
    else
      part.tex:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
      Place(part.tex, w, len, mx, my)
    end
    if part.wide then
      part.tex:SetVertexColor(col[1], col[2], col[3])
      part.tex:SetAlpha(0.55 * alpha * shimmer)
    else
      part.tex:SetVertexColor(0.6 + 0.4 * col[1], 0.6 + 0.4 * col[2], 0.6 + 0.4 * col[3])
      part.tex:SetAlpha(alpha * shimmer)
    end
    part.tex:Show()
  end
end

local function DrawLine()
  local n = 0
  if phase == "chain" then
    local col = LineColor()
    for k = 2, #chain do
      n = n + 1
      DrawSeg(n, chain[k - 1], chain[k], math.min(1, (now - (born[k] or 0)) / 0.25), col)
    end
    if closed then
      n = n + 1
      DrawSeg(n, chain[#chain], closed, math.min(1, (now - closedBorn) / 0.25), col)
    end
  elseif ghost then
    local e = (now - ghostAt) / 0.45
    if e >= 1 then
      ghost = nil
    else
      for k = 2, #ghost.list do
        n = n + 1
        DrawSeg(n, ghost.list[k - 1], ghost.list[k], 1 - e, ghost.col)
      end
      if ghost.closed then
        n = n + 1
        DrawSeg(n, ghost.list[#ghost.list], ghost.closed, 1 - e, ghost.col)
      end
    end
  end
  for k = n + 1, #segs do
    for _, part in ipairs(segs[k]) do part.tex:Hide() end
  end
end

-------------------------------------------------------------------------------
-- The firefly
-------------------------------------------------------------------------------

local function UpdateFly(dt)
  local busyLine = phase == "chain" and #chain > 0
  if busyLine then
    fly.tx, fly.ty = CellXY(closed or chain[#chain])
  else
    fly.wander = fly.wander - dt
    if fly.wander <= 0 then
      fly.wander = 2 + random() * 3
      fly.tx, fly.ty = 30 + random() * (SIZE - 60), 30 + random() * (SIZE - 60)
    end
  end
  local k = math.min(1, dt * (busyLine and 14 or 1.6))
  local ox, oy = fly.x, fly.y
  fly.x = fly.x + (fly.tx - fly.x) * k
  fly.y = fly.y + (fly.ty - fly.y) * k
  local vx, vy = (fly.x - ox) / math.max(dt, 0.001), (fly.y - oy) / math.max(dt, 0.001)
  local speed = abs(vx) + abs(vy)
  if speed > 8 then
    local want = math.atan2(-vx, -vy)
    local d = (want - fly.ang + math.pi) % (2 * math.pi) - math.pi
    fly.ang = fly.ang + d * math.min(1, dt * 10)
  end
  -- A gentle hover.
  local hx, hy = fly.x + 1.5 * sin(now * 2.3), fly.y + 1.5 * cos(now * 1.7)
  Place(fly.tex, 26, 26, hx, hy)
  fly.tex:SetRotation(fly.ang)
  local tail = 0.5 + 0.5 * sin(now * 3.1)
  -- The glow sits a little behind the head, on the tail.
  local gx, gy = hx + 6 * sin(fly.ang), hy + 6 * cos(fly.ang)
  Place(fly.glow, 40 + 10 * tail, 40 + 10 * tail, gx, gy)
  fly.glow:SetAlpha(0.55 + 0.35 * tail)
  -- Shed motes of light: steadily while drawing, now and then while wandering.
  fly.moteT = fly.moteT - dt
  if fly.moteT <= 0 then
    if busyLine or speed > 30 then
      Mote(gx, gy, busyLine and LineColor() or FLY_COLOR)
      fly.moteT = busyLine and 0.03 or 0.08
    else
      fly.moteT = 0.4
      if random() < 0.5 then Mote(gx, gy, FLY_COLOR) end
    end
  end
end

-------------------------------------------------------------------------------
-- Drawing a line
-------------------------------------------------------------------------------

local Enclosed

local function ChainInfo()
  if phase ~= "chain" or #chain < 2 then
    infoText:SetText("")
    goalRow:Show()
    return
  end
  goalRow:Hide()
  local k = OnlyColor(chainMask)
  local name = k and (COLOR_NAMES[k] .. " lights") or "lights that match"
  local msg
  if closed then
    msg = "Loop! Catches all the " .. name
  elseif #chain >= SWARM_AT then
    msg = #chain .. " linked: a swarm catches all the " .. name
  elseif #chain >= DEW_AT then
    msg = #chain .. " linked: leaves a dewdrop"
  elseif #chain >= BEACON_AT then
    msg = #chain .. " linked: leaves a beacon"
  elseif #chain < MIN_LINK then
    msg = "Link at least " .. MIN_LINK
  else
    msg = #chain .. " linked"
  end
  infoText:SetText(msg)
end

-- Light up everything the line would catch, and what a loop would burst.
local function MarkPreview()
  local all = closed or #chain >= SWARM_AT
  local inChain = {}
  for _, i in ipairs(chain) do inChain[i] = true end
  local inside = {}
  if closed then
    for _, i in ipairs(Enclosed(inChain)) do inside[i] = true end
  end
  for i = 1, N * N do
    local p = pc[i]
    if p then
      p.hot = inChain[i] or nil
      p.lit = (all and band(Colors(b[i]), chainMask) ~= 0) or inside[i] or nil
    end
  end
end

local function RefreshChain()
  chainMask = ALL
  for _, i in ipairs(chain) do chainMask = band(chainMask, Mask(b[i])) end
  MarkPreview()
  ChainInfo()
end

local function Tone(n)
  if now - lastToneAt < 0.04 then return end
  lastToneAt = now
  ns.PlayTone("glow" .. math.min(4, n))   -- a soft hush, a touch brighter each link
end

-- The cursor reached cell j while drawing.
local function Visit(j)
  local last = chain[#chain]
  if closed then
    -- Moving back off the closing light opens the loop again.
    if j == last then closed = nil; RefreshChain() end
    return
  end
  if j == last then return end
  if #chain >= 2 and j == chain[#chain - 1] then
    born[#chain] = nil
    table.remove(chain)
    RefreshChain()
    return
  end
  if not Adjacent(last, j) or band(chainMask, Mask(b[j])) == 0 then return end
  for _, i in ipairs(chain) do
    if i == j then
      closed, closedBorn = j, now
      ns.PlayTone("shimmer")
      RefreshChain()
      return
    end
  end
  chain[#chain + 1] = j
  born[#chain] = now
  Tone(#chain)
  RefreshChain()
end

-------------------------------------------------------------------------------
-- HUD and goals
-------------------------------------------------------------------------------

local function BestShown()
  if data.mode == "moves" then return data.stats.best_moves or 0 end
  local v = data.stats.best_relaxed or 0
  if data.score > v then v = data.score end
  return v
end

local GOAL_ORDER = { 1, 2, 3, 4, 5, "web", "seed" }
local GOAL_ICON = 22

local function UpdateGoals()
  for _, e in ipairs(goalRow.entries) do e:Hide() end
  if data.mode ~= "jars" then
    goalRow.label:SetText("Best " .. ns.FormatNumber(BestShown()))
    goalRow.label:ClearAllPoints()
    goalRow.label:SetPoint("CENTER")
    return
  end
  goalRow.label:SetText("Level " .. data.level)
  local shown = {}
  for _, k in ipairs(GOAL_ORDER) do
    if data.goal[k] then shown[#shown + 1] = k end
  end
  local EW = 60
  local w = 66 + #shown * EW
  goalRow.label:ClearAllPoints()
  goalRow.label:SetPoint("LEFT", goalRow, "CENTER", -w / 2, 0)
  for n, k in ipairs(shown) do
    local e = goalRow.entries[n]
    local got, need = math.min(data.got[k] or 0, data.goal[k]), data.goal[k]
    local col
    for _, t in ipairs({ e.dim, e.icon }) do
      if k == "web" then
        t:SetTexture(WEB_TEX)
        t:SetVertexColor(1, 1, 1)
      elseif k == "seed" then
        t:SetTexture(SEED_TEX)
        t:SetVertexColor(1, 1, 1)
      else
        LightTex(t, k)
      end
    end
    if k == "web" then col = WHITE elseif k == "seed" then col = { 1, 0.75, 0.4 } else col = COLORS[k] end
    e.dim:SetDesaturated(true)
    e.dim:SetAlpha(0.3)
    local frac = need > 0 and got / need or 0
    if frac > 0 then
      e.icon:SetHeight(GOAL_ICON * frac)
      e.icon:SetTexCoord(0, 1, 1 - frac, 1)
      e.icon:Show()
    else
      e.icon:Hide()
    end
    local full = got >= need
    e.glow:SetVertexColor(col[1], col[2], col[3])
    e.glow:SetAlpha(full and 0.8 or 0.15 + 0.35 * frac)
    e.text:SetText(got .. "/" .. need)
    UI.SetTextColor(e.text, full and C.green or C.cream)
    e:ClearAllPoints()
    e:SetPoint("LEFT", goalRow, "CENTER", -w / 2 + 66 + (n - 1) * EW, 0)
    e:Show()
  end
end

local function UpdateHud()
  if data.mode == "jars" then
    scoreText:SetText("Score " .. ns.FormatNumber(data.score) .. " / " .. ns.FormatNumber(data.target))
  else
    scoreText:SetText("Score " .. ns.FormatNumber(data.score))
  end
  if data.mode == "relaxed" then
    rightText:SetText(data.streak >= 2 and ("Glow x" .. math.min(data.streak, 5)) or "")
  else
    rightText:SetText("Moves " .. data.moves)
  end
  modeRow:Select(data.mode)
  UpdateGoals()
end

local function SetupLevel(n)
  data.level = n
  cfg = Cfg("jars", n)
  data.goal, data.got = {}, {}
  local pick = ns.Shuffle({ 1, 2, 3, 4, 5 })
  for k = 1, cfg.colors do data.goal[pick[k]] = cfg.amount end
  if cfg.webs > 0 then data.goal.web = cfg.webs end
  if cfg.seeds > 0 then data.goal.seed = cfg.seeds end
  data.filled = {}
  data.moves = cfg.moves
  data.target = cfg.target
end

-- Bonus goals just met: each one adds to the score. Returns the bonus.
local function FillBonuses()
  if data.mode ~= "jars" then return 0 end
  local n = 0
  for k, need in pairs(data.goal) do
    if (data.got[k] or 0) >= need and not data.filled[k] then
      data.filled[k] = true
      n = n + 1
    end
  end
  if n == 0 then return 0 end
  local bonus = n * (150 + 25 * data.level)
  data.stats.jars = (data.stats.jars or 0) + n
  ns.PlayTone("shimmer")
  return bonus
end

-------------------------------------------------------------------------------
-- Turn flow
-------------------------------------------------------------------------------

local function ShowOver(title, line, which)
  overlay:Open(title, line)
  nextButton:SetShown(which == "next")
  againButton:SetShown(which == "again")
  playButton:SetShown(which == "play")
end

local function BonusLine()
  local n, full = 0, 0
  for k in pairs(data.goal) do
    n = n + 1
    if data.filled[k] then full = full + 1 end
  end
  return format("%d of %d %s earned", full, n, n == 1 and "bonus" or "bonuses")
end

local function LevelResult()
  local passed = data.score >= data.target
  local line = format("Score %s of %s\n%s", ns.FormatNumber(data.score), ns.FormatNumber(data.target), BonusLine())
  if passed then
    ShowOver("Level " .. data.level .. " passed!", line, "next")
  else
    ShowOver("Not quite", line .. "\nTry level " .. data.level .. " again.", "again")
  end
end

local function CheckEnd()
  if data.mode == "jars" then
    if data.moves <= 0 then
      local passed = data.score >= data.target
      data.over, data.won = true, passed
      phase = "over"
      if passed then
        ns.RecordResult("fireflies", { won = true, score = data.level, bestKey = "best_level" })
        ns.Sound("win")
      else
        ns.RecordResult("fireflies", { won = false })
      end
      LevelResult()
      return true
    end
  elseif data.mode == "moves" and data.moves <= 0 then
    data.over = true
    phase = "over"
    local newBest = ns.RecordResult("fireflies", { score = data.score, bestKey = "best_moves" })
    ns.Sound("win")
    ShowOver(newBest and "A new best!" or "Out of moves",
      format("Score %s\nBest %s", ns.FormatNumber(data.score), ns.FormatNumber(data.stats.best_moves or data.score)), "again")
    return true
  end
  return false
end

local function Reshuffle()
  toast:Say("The lights drift about...")
  local list
  for _ = 1, 60 do
    list = {}
    for i = 1, N * N do list[i] = b[i] end
    ns.Shuffle(list)
    if HasMove(list) then break end
    list = nil
  end
  if not list then
    list = {}
    for i = 1, N * N do list[i] = (b[i] == SEED) and SEED or NewCode() end
  end
  for i = 1, N * N do
    b[i] = list[i]
    SetCode(pc[i], b[i])
    Pop(pc[i])
  end
end

-- Seeds that reached the bottom row are collected (then everything falls again).
local function CollectSeeds()
  local set = {}
  for c = 1, N do
    local i = (N - 1) * N + c
    if b[i] == SEED then set[i] = true end
  end
  if not next(set) then return false end
  local n = 0
  for i in pairs(set) do
    n = n + 1
    local x, y = CellXY(i)
    Spark(x, y, { 1, 0.8, 0.45 })
    Spark(x, y, { 0.6, 1, 0.5 })
    pc[i].clr = 0
  end
  data.got.seed = (data.got.seed or 0) + n
  data.stats.seeds = (data.stats.seeds or 0) + n
  local extra = FillBonuses()
  pending = { set = set, creates = {}, gain = 50 * n + extra }
  toast:Say((n > 1 and "Seeds collected!" or "Seed collected!") .. (extra > 0 and (" Bonus! +" .. extra) or ""), { 1, 0.85, 0.5 })
  ns.PlayTone("shimmer")
  phase = "clear"
  return true
end

local function EndTurn()
  if CollectSeeds() then return end
  phase = "idle"
  UpdateHud()
  if CheckEnd() then return end
  if not HasMove(b) then Reshuffle() end
end

-- Cells enclosed by the loop: not reachable from the edge without crossing it.
function Enclosed(wall)
  local seen, stack = {}, {}
  for i = 1, N * N do
    local r, c = RC(i)
    if (r == 0 or c == 0 or r == N - 1 or c == N - 1) and not wall[i] then
      seen[i] = true
      stack[#stack + 1] = i
    end
  end
  while #stack > 0 do
    local i = table.remove(stack)
    local r, c = RC(i)
    local nbr = {}
    if r > 0 then nbr[#nbr + 1] = i - N end
    if r < N - 1 then nbr[#nbr + 1] = i + N end
    if c > 0 then nbr[#nbr + 1] = i - 1 end
    if c < N - 1 then nbr[#nbr + 1] = i + 1 end
    for _, j in ipairs(nbr) do
      if not seen[j] and not wall[j] then
        seen[j] = true
        stack[#stack + 1] = j
      end
    end
  end
  local out = {}
  for i = 1, N * N do
    if not seen[i] and not wall[i] then out[#out + 1] = i end
  end
  return out
end

-- Which bonus goal a caught piece counts toward.
local function GoalFor(code, color)
  local m = Colors(code)
  if m == 0 then return nil end
  if color and Has(m, color) then return color end
  if data.mode == "jars" then
    for k = 1, KINDS do
      if Has(m, k) and data.goal[k] and (data.got[k] or 0) < data.goal[k] then return k end
    end
  end
  if Base(code) == DEW then return nil end
  return FirstColor(m)
end

local function Release()
  local loop = closed ~= nil
  local list, mask = chain, chainMask
  ghost = #list >= MIN_LINK and { list = list, closed = closed, col = LineColor(mask) } or nil
  ghostAt = now
  chain, closed, born = {}, nil, {}
  for i = 1, N * N do
    if pc[i] then pc[i].hot, pc[i].lit = nil, nil end
  end
  phase = "idle"
  ChainInfo()
  if #list < MIN_LINK then return end

  data.moved = (data.moved or 0) + 1
  if data.mode ~= "relaxed" then data.moves = math.max(0, data.moves - 1) end

  local color = OnlyColor(mask)
  local set, bonus, words = {}, 0, {}
  for _, i in ipairs(list) do set[i] = true end
  local creates = {}
  local last = list[#list]
  local lx, ly = CellXY(last)

  if loop or #list >= SWARM_AT then
    for i = 1, N * N do
      if band(Colors(b[i]), mask) ~= 0 then set[i] = true end
    end
    bonus = bonus + 50
    words[#words + 1] = loop and "Loop!" or "Swarm!"
    if loop then
      data.stats.loops = (data.stats.loops or 0) + 1
      local wall = {}
      for _, i in ipairs(list) do wall[i] = true end
      local inside = Enclosed(wall)
      for _, i in ipairs(inside) do
        local r, c = RC(i)
        for dr = -1, 1 do
          for dc = -1, 1 do
            local rr, cc = r + dr, c + dc
            if rr >= 0 and rr < N and cc >= 0 and cc < N then set[rr * N + cc + 1] = true end
          end
        end
        local x, y = CellXY(i)
        Flash(x, y)
        bonus = bonus + 30
      end
      if #inside > 0 then words[#words + 1] = "Lanterns!" end
    end
  end

  -- Rewards left behind on the last light.
  if #list >= DEW_AT then
    creates[last] = DEW
    data.stats.dews = (data.stats.dews or 0) + 1
    words[#words + 1] = "Dewdrop!"
  elseif #list >= BEACON_AT and not loop then
    local k = color or GoalFor(b[last], nil) or FirstColor(mask)
    if k then
      creates[last] = 10 + k
      words[#words + 1] = "Beacon!"
    end
  end

  -- Beacons caught clear their row and column (and set off others).
  local fired, again = {}, true
  while again do
    again = false
    for i in pairs(set) do
      local c = Base(b[i])
      if c > 10 and c <= 10 + KINDS and not Webbed(b[i]) and not fired[i] and not creates[i] then
        fired[i], again = true, true
        local r, cc = RC(i)
        for k = 0, N - 1 do
          set[r * N + k + 1] = true
          set[k * N + cc + 1] = true
        end
        Beam(i, COLORS[c % 10])
        bonus = bonus + 40
      end
    end
  end
  if next(fired) then words[#words + 1] = "Beacon burst!" end

  -- Webs in the catch break instead (the light stays). Seeds can't be
  -- linked, but a beacon or lantern burst that reaches one collects it.
  local unweb = {}
  for i in pairs(set) do
    if Webbed(b[i]) then unweb[i] = true end
  end
  for i in pairs(unweb) do set[i] = nil end
  local seeds = 0
  for i in pairs(set) do
    if b[i] == SEED then seeds = seeds + 1 end
  end
  if seeds > 0 then
    data.got.seed = (data.got.seed or 0) + seeds
    data.stats.seeds = (data.stats.seeds or 0) + seeds
    bonus = bonus + 50 * seeds
    words[#words + 1] = seeds > 1 and "Seeds collected!" or "Seed collected!"
  end
  -- Catching a light next to a web breaks it too.
  for i in pairs(set) do
    local r, c = RC(i)
    local nbr = {}
    if r > 0 then nbr[#nbr + 1] = i - N end
    if r < N - 1 then nbr[#nbr + 1] = i + N end
    if c > 0 then nbr[#nbr + 1] = i - 1 end
    if c < N - 1 then nbr[#nbr + 1] = i + 1 end
    for _, j in ipairs(nbr) do
      if Webbed(b[j]) and not set[j] then unweb[j] = true end
    end
  end
  local webs = 0
  for i in pairs(unweb) do
    webs = webs + 1
    b[i] = b[i] - WEB
    local x, y = CellXY(i)
    Spark(x, y, WHITE)
    SetCode(pc[i], b[i])
    Pop(pc[i])
  end
  if webs > 0 then
    data.got.web = (data.got.web or 0) + webs
    bonus = bonus + 20 * webs
    words[#words + 1] = webs > 1 and "Webs broken!" or "Web broken!"
  end

  -- Count the catch (the one that turns into a reward counts too).
  local n = 0
  for i in pairs(set) do
    n = n + 1
    local k = GoalFor(b[i], color)
    if k then data.got[k] = (data.got[k] or 0) + 1 end
    local x, y = CellXY(i)
    local col = k and COLORS[k] or WHITE
    Spark(x, y, col)
    if n % 2 == 0 then Spark(x, y, col) end
    if not creates[i] then pc[i].clr = 0 end
  end
  for i in pairs(creates) do set[i] = nil end
  data.caught = (data.caught or 0) + n

  if n >= 6 then data.streak = data.streak + 1 else data.streak = 0 end
  local mult = data.streak >= 2 and math.min(data.streak, 5) or 1
  local gain = (n * 10 + bonus) * mult
  local extra = FillBonuses()
  if extra > 0 then words[#words + 1] = "Bonus! +" .. extra end
  pending = { set = set, creates = creates, gain = gain + extra }

  Floater(lx, ly, "+" .. gain .. (mult > 1 and (" x" .. mult) or ""), color and COLORS[color] or C.gold)
  if #words > 0 then
    toast:Say(table.concat(words, " "), color and COLORS[color] or C.gold)
  elseif mult > 1 then
    toast:Say("Glow streak x" .. mult)
  end
  if loop or next(fired) or next(creates) or webs > 0 or seeds > 0 then
    ns.PlayTone("shimmer")
  else
    ns.Sound("good")
  end
  if ns.CheckTrophies then ns.CheckTrophies() end
  phase = "clear"
end

local function ApplyClear()
  local set, creates = pending.set, pending.creates
  data.score = data.score + pending.gain
  pending = nil
  for i in pairs(set) do
    FreePiece(pc[i])
    pc[i], b[i] = nil, 0
  end
  for i, code in pairs(creates) do
    b[i] = code
    SetCode(pc[i], code)
    Pop(pc[i])
  end
  -- Another seed may drop in from the top while more are needed.
  local seedOK = false
  if data.mode == "jars" and data.goal.seed then
    local onBoard = 0
    for i = 1, N * N do
      if b[i] == SEED then onBoard = onBoard + 1 end
    end
    seedOK = onBoard < 2 and (data.got.seed or 0) + onBoard < data.goal.seed and random() < 0.8
  end
  local fresh = {}
  for c = 1, N do
    local w = N
    for r = N, 1, -1 do
      local i = (r - 1) * N + c
      if b[i] ~= 0 then
        local j = (w - 1) * N + c
        if i ~= j then
          b[j], pc[j] = b[i], pc[i]
          b[i], pc[i] = 0, nil
          local _, ty = CellXY(j)
          MoveTo(pc[j], pc[j].x, ty, math.min(0.28, 0.12 + 0.04 * (j - i) / N))
        end
        w = w - 1
      end
    end
    for r = w, 1, -1 do
      local j = (r - 1) * N + c
      b[j] = NewCode()
      fresh[#fresh + 1] = j
      local _, ty = CellXY(j)
      local p = MakePiece(j, b[j], -CELL * (w - r + 0.5))
      pc[j] = p
      MoveTo(p, p.x, ty, math.min(0.3, 0.14 + 0.03 * w))
    end
  end
  if seedOK and #fresh > 0 then
    local j = fresh[random(#fresh)]
    b[j] = SEED
    SetCode(pc[j], SEED)
  end
  UpdateHud()
  phase = "fall"
end

local function Advance()
  if phase == "clear" then
    ApplyClear()
  elseif phase == "fall" then
    EndTurn()
  end
end

-- Finish every animation at once (window closed, or logging out).
local function Settle()
  if phase == "chain" then
    chain, closed, born = {}, nil, {}
    phase = "idle"
    ChainInfo()
  end
  for _ = 1, 40 do
    if phase ~= "clear" and phase ~= "fall" then break end
    Advance()
  end
  ghost = nil
  for i = 1, N * N do
    local p = pc[i]
    if p then
      p.x, p.y = CellXY(i)
      p.mv, p.pop, p.clr, p.sc, p.al, p.hot, p.lit = nil, nil, nil, 1, 1, nil, nil
      Draw(p)
    end
  end
end

-------------------------------------------------------------------------------
-- Input: press on a light, drag, let go
-------------------------------------------------------------------------------

local function CursorCell()
  local x, y = GetCursorPosition()
  local s = field:GetEffectiveScale()
  local left, top = field:GetLeft(), field:GetTop()
  if not left or not top then return nil end
  x, y = x / s - left, top - y / s
  local c, r = floor(x / CELL), floor(y / CELL)
  if c < 0 or c >= N or r < 0 or r >= N then return nil end
  -- Near the middle of the cell, so cutting a corner doesn't jump diagonally.
  local cx, cy = (c + 0.5) * CELL, (r + 0.5) * CELL
  if abs(x - cx) > CELL * 0.42 or abs(y - cy) > CELL * 0.42 then return nil end
  return r * N + c + 1
end

local function Press(i)
  if phase ~= "idle" or data.over then return end
  if Mask(b[i]) == 0 then return end
  phase = "chain"
  ghost = nil
  chain, closed, born = { i }, nil, { now }
  Tone(1)
  RefreshChain()
end

local function Track()
  local j = CursorCell()
  if not j then return end
  -- Step one cell at a time toward the cursor when it moved fast along a line.
  for _ = 1, N do
    local last = closed or chain[#chain]
    if j == last then return end
    local lr, lc = RC(last)
    local jr, jc = RC(j)
    local step
    if lr == jr then
      step = last + (jc > lc and 1 or -1)
    elseif lc == jc then
      step = last + (jr > lr and N or -N)
    else
      return
    end
    local before = #chain .. tostring(closed)
    Visit(step)
    if #chain .. tostring(closed) == before then return end
  end
end

-------------------------------------------------------------------------------
-- New games
-------------------------------------------------------------------------------

local function Started()
  return (data.moved or 0) > 0 and not data.over
end

local function NewGame(mode, level)
  if data.mode == "relaxed" and data.score > 0 and not data.over then
    ns.RecordResult("fireflies", { score = data.score, bestKey = "best_relaxed" })
  end
  Settle()
  data.mode = mode
  data.score, data.moved, data.over, data.won, data.streak = 0, 0, false, false, 0
  if mode == "jars" then
    SetupLevel(level or data.level or 1)
  else
    cfg = Cfg(mode, 1)
    data.goal, data.got = {}, {}
    data.moves = mode == "moves" and MOVES or 0
  end
  data.board = FreshBoard()
  b = data.board
  phase, pending, ghost = "idle", nil, nil
  overlay:Close()
  Rebuild()
  UpdateHud()
  -- A card for pieces this level brings in for the first time.
  if mode == "jars" and cfg.intro and not data.seen[cfg.intro] then
    local t = INTRO[cfg.intro]
    phase = "intro"
    ShowOver("New: " .. t[1], t[2], "play")
  end
end

StaticPopupDialogs["DOWNTIME_NEW_FIREFLIES"] = {
  text = "Start a new game? This one will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, d) NewGame(d or "jars") end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function AskNew(mode)
  if Started() then
    StaticPopup_Show("DOWNTIME_NEW_FIREFLIES", nil, nil, mode)
  else
    NewGame(mode)
  end
end

local function ValidCode(v)
  if type(v) ~= "number" or v ~= floor(v) or v < 1 then return false end
  local c = v % WEB
  if v >= 2 * WEB then return false end
  if c >= 1 and c <= KINDS then return true end
  if c >= 11 and c <= 10 + KINDS then return true end
  if c == DEW or c == SEED then return v < WEB end
  if IsTwin(c) then
    local a, d = TwinColors(c)
    return a >= 1 and d <= KINDS and a < d
  end
  return false
end

local function ValidBoard(t)
  if type(t) ~= "table" or #t ~= N * N then return false end
  for i = 1, N * N do
    if not ValidCode(t[i]) then return false end
  end
  return true
end

local function ValidGoal(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for k, v in pairs(t) do
    local okKey = k == "web" or k == "seed" or (type(k) == "number" and k >= 1 and k <= KINDS)
    if not okKey or type(v) ~= "number" or v < 1 then return false end
    n = n + 1
  end
  return n > 0
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

-- Building is split into parts: Lua 5.1 allows a function at most 60 outer
-- locals, and one big Create went over.
local function BuildBoard(parent)
  scoreText = UI.Title(parent, 14)
  scoreText:SetPoint("TOPLEFT", 14, -2)
  rightText = UI.Text(parent, 12, C.cream)
  rightText:SetPoint("TOPRIGHT", -14, -4)

  local inset = UI.Inset(parent, SIZE + 6, SIZE + 6)
  inset:SetPoint("TOP", parent, "TOP", 0, -22)
  field = CreateFrame("Frame", nil, inset)
  field:SetSize(SIZE, SIZE)
  field:SetPoint("CENTER")
  field:SetClipsChildren(true)

  -- A summer night: dark sky, a faint glow along the grass, a hazy moon.
  local sky = field:CreateTexture(nil, "BACKGROUND", nil, 0)
  sky:SetAllPoints()
  sky:SetColorTexture(0.025, 0.04, 0.08, 0.94)
  local grass = field:CreateTexture(nil, "BACKGROUND", nil, 1)
  grass:SetTexture(ns.MEDIA .. "glow")
  grass:SetPoint("BOTTOMLEFT", 0, -30)
  grass:SetPoint("BOTTOMRIGHT", 0, -30)
  grass:SetHeight(140)
  grass:SetVertexColor(0.25, 0.55, 0.3, 0.35)
  grass:SetBlendMode("ADD")
  local moon = field:CreateTexture(nil, "BACKGROUND", nil, 2)
  moon:SetTexture(GLOW_TEX)
  moon:SetSize(120, 120)
  moon:SetPoint("CENTER", field, "TOPRIGHT", -30, -26)
  moon:SetVertexColor(0.7, 0.8, 1, 0.18)
  moon:SetBlendMode("ADD")

  -- The trail of light sits under the lights.
  local lineLayer = CreateFrame("Frame", nil, field)
  lineLayer:SetAllPoints()
  lineLayer:SetFrameLevel(field:GetFrameLevel() + 1)
  for k = 1, N * N do
    local wide = lineLayer:CreateTexture(nil, "ARTWORK", nil, 0)
    wide:SetTexture(BEAM_TEX)
    wide:SetBlendMode("ADD")
    wide:Hide()
    local core = lineLayer:CreateTexture(nil, "ARTWORK", nil, 1)
    core:SetTexture(BEAM_TEX)
    core:SetBlendMode("ADD")
    core:Hide()
    segs[k] = { { tex = wide, wide = true }, { tex = core } }
  end

  layer = CreateFrame("Frame", nil, field)
  layer:SetAllPoints()
  layer:SetFrameLevel(field:GetFrameLevel() + 2)
  return inset
end

local function BuildEffects()
  local fx = CreateFrame("Frame", nil, field)
  fx:SetAllPoints()
  fx:SetFrameLevel(field:GetFrameLevel() + 6)
  for i = 1, 60 do
    local t = fx:CreateTexture(nil, "OVERLAY")
    t:SetTexture(SPARK_TEX)
    t:SetBlendMode("ADD")
    t:Hide()
    sparks[i] = { tex = t, on = false }
  end
  for i = 1, 50 do
    local t = fx:CreateTexture(nil, "ARTWORK")
    t:SetTexture(GLOW_TEX)
    t:SetBlendMode("ADD")
    t:Hide()
    motes[i] = { tex = t, on = false }
  end
  for i = 1, 6 do
    local fs = UI.Title(fx, 18, C.gold)
    fs:Hide()
    floats[i] = { fs = fs, on = false }
  end
  for i = 1, 12 do
    local g = fx:CreateTexture(nil, "ARTWORK")
    g:SetTexture(GLOW_TEX)
    g:SetBlendMode("ADD")
    g:SetVertexColor(1, 0.7, 0.3)
    g:Hide()
    local t = fx:CreateTexture(nil, "OVERLAY")
    t:SetTexture(LANTERN_TEX)
    t:Hide()
    flashes[i] = { tex = t, glow = g, on = false }
  end
  for i = 1, 16 do
    local t = fx:CreateTexture(nil, "ARTWORK")
    t:SetTexture(BEAM_TEX)
    t:SetBlendMode("ADD")
    t:Hide()
    beams[i] = { tex = t, on = false }
  end

  -- The firefly flies above everything on the board.
  fly.glow = fx:CreateTexture(nil, "ARTWORK")
  fly.glow:SetTexture(GLOW_TEX)
  fly.glow:SetBlendMode("ADD")
  fly.glow:SetVertexColor(FLY_COLOR[1], FLY_COLOR[2], FLY_COLOR[3])
  fly.tex = fx:CreateTexture(nil, "OVERLAY")
  fly.tex:SetTexture(FLY_TEX)
  fly.tex:SetVertexColor(FLY_COLOR[1], FLY_COLOR[2], FLY_COLOR[3])
end

local function BuildCells()
  -- One button per cell: press starts a line; letting go anywhere ends it.
  for i = 1, N * N do
    local cell = CreateFrame("Button", nil, field)
    cell:SetSize(CELL, CELL)
    cell:SetFrameLevel(field:GetFrameLevel() + 3)
    local x, y = CellXY(i)
    cell:SetPoint("CENTER", field, "TOPLEFT", x, -y)
    cell:SetScript("OnMouseDown", function(_, button)
      if button ~= "LeftButton" then return end
      Press(i)
    end)
    cell:SetScript("OnMouseUp", function(_, button)
      if button ~= "LeftButton" then return end
      if phase == "chain" then
        Track()
        Release()
      end
    end)
    cells[i] = cell
  end
end

local function BuildControls(parent, inset)
  toast = UI.Toast(inset)
  overlay = UI.Overlay(inset)
  nextButton = UI.Button(overlay.buttons, "Next level", 110, 24)
  nextButton:SetPoint("TOP", 0, 0)
  nextButton:SetScript("OnClick", function() NewGame("jars", data.level + 1) end)
  againButton = UI.Button(overlay.buttons, "Play again", 110, 24)
  againButton:SetPoint("TOP", 0, 0)
  againButton:SetScript("OnClick", function() NewGame(data.mode) end)
  playButton = UI.Button(overlay.buttons, "Play", 110, 24)
  playButton:SetPoint("TOP", 0, 0)
  playButton:SetScript("OnClick", function()
    if cfg.intro then data.seen[cfg.intro] = true end
    overlay:Close()
    phase = "idle"
  end)

  goalRow = CreateFrame("Frame", nil, parent)
  goalRow:SetSize(SIZE, 22)
  goalRow:SetPoint("TOP", inset, "BOTTOM", 0, -4)
  goalRow.label = UI.Title(goalRow, 13)
  goalRow.entries = {}
  -- Each bonus goal is its light (or web, or seed) drawn faint, filling up
  -- with full color from the bottom as you collect, and glowing once full.
  for k = 1, 4 do
    local e = CreateFrame("Frame", nil, goalRow)
    e:SetSize(58, 24)
    e.slot = CreateFrame("Frame", nil, e)
    e.slot:SetSize(GOAL_ICON, GOAL_ICON)
    e.slot:SetPoint("LEFT")
    e.glow = e.slot:CreateTexture(nil, "BACKGROUND")
    e.glow:SetTexture(GLOW_TEX)
    e.glow:SetBlendMode("ADD")
    e.glow:SetSize(GOAL_ICON * 2, GOAL_ICON * 2)
    e.glow:SetPoint("CENTER")
    e.dim = e.slot:CreateTexture(nil, "ARTWORK", nil, 0)
    e.dim:SetAllPoints()
    e.icon = e.slot:CreateTexture(nil, "ARTWORK", nil, 1)
    e.icon:SetPoint("BOTTOMLEFT")
    e.icon:SetPoint("BOTTOMRIGHT")
    e.text = UI.Text(e, 12, C.cream)
    e.text:SetPoint("LEFT", e.slot, "RIGHT", 3, 0)
    e:Hide()
    goalRow.entries[k] = e
  end

  infoText = UI.Text(parent, 12, C.gold)
  infoText:SetPoint("CENTER", goalRow, "CENTER", 0, 0)

  modeRow = UI.Choice(parent, MODES, 240, function(key)
    if key ~= data.mode then AskNew(key) end
  end)
  modeRow:SetPoint("TOP", goalRow, "BOTTOM", 0, -6)

  local newButton = UI.Button(parent, "New game", 110, 24)
  newButton:SetPoint("TOP", modeRow, "BOTTOM", 0, -8)
  newButton:SetScript("OnClick", function() AskNew(data.mode) end)

  local tip = UI.Text(parent, 10, C.dim)
  tip:SetPoint("TOP", newButton, "BOTTOM", 0, -8)
  tip:SetWidth(SIZE)
  tip:SetJustifyH("CENTER")
  tip:SetText("Drag a line through lights of one color. End on a light\nalready in your line to make a loop and catch them all.")
  tip:SetSpacing(2)
end

-- Load the saved game, or start one.
local function LoadState()
  if data.mode ~= "jars" and data.mode ~= "moves" and data.mode ~= "relaxed" then data.mode = "jars" end
  if type(data.score) ~= "number" or data.score < 0 then data.score = 0 end
  if type(data.moved) ~= "number" then data.moved = 0 end
  if type(data.streak) ~= "number" then data.streak = 0 end
  if type(data.level) ~= "number" or data.level < 1 then data.level = 1 end
  data.level = floor(data.level)
  if type(data.seen) ~= "table" then data.seen = {} end
  if type(data.got) ~= "table" then data.got = {} end
  if type(data.filled) ~= "table" then data.filled = {} end
  if type(data.moves) ~= "number" or data.moves < 0 or data.moves > 80 then data.moves = 0 end
  cfg = Cfg(data.mode, data.level)
  if type(data.target) ~= "number" or data.target < 1 then data.target = cfg.target end
  local good = ValidBoard(data.board)
  if data.mode == "jars" and not ValidGoal(data.goal) then good = false end
  if good then
    b = data.board
    if not HasMove(b) then
      data.board = FreshBoard()
      b = data.board
    end
    Rebuild()
    UpdateHud()
    if data.over then
      phase = "over"
      if data.mode == "jars" then
        LevelResult()
      else
        ShowOver("Out of moves", format("Score %s\nBest %s", ns.FormatNumber(data.score),
          ns.FormatNumber(data.stats.best_moves or data.score)), "again")
      end
    end
  else
    data.over = false
    NewGame(data.mode, data.level)
  end
end

local function Tick(_, dt)
  if dt > 0.05 then dt = 0.05 end
  now = now + dt
  if phase == "chain" then
    if not IsMouseButtonDown("LeftButton") then
      Release()
    else
      Track()
    end
  end
  local busy = false
  for i = 1, N * N do
    local p = pc[i]
    if p then
      if Step(p, dt) then busy = true end
      Draw(p)
    end
  end
  -- Lights already caught finish their fade while they leave.
  if pending then
    for i in pairs(pending.set) do
      local p = pc[i]
      if p and p.clr and p.clr < 1 then busy = true end
    end
  end
  DrawLine()
  UpdateFly(dt)
  UpdateEffects(dt)
  if not busy and (phase == "clear" or phase == "fall") then Advance() end
end

local function Create(parent, saved)
  panel = parent
  data = saved
  pc = {}
  local inset = BuildBoard(parent)
  BuildEffects()
  BuildCells()
  BuildControls(parent, inset)
  LoadState()

  ns.OnPiecesChanged(function()
    for i = 1, N * N do
      local p = pc[i]
      if p then SetCode(p, p.code); Draw(p) end
    end
    UpdateGoals()
  end)

  local saver = CreateFrame("Frame")
  saver:RegisterEvent("PLAYER_LOGOUT")
  saver:SetScript("OnEvent", function()
    if field then Settle() end
  end)

  parent:SetScript("OnUpdate", Tick)
end

ns.RegisterGame({
  key = "fireflies",
  name = "Fireflies",
  blurb = "Fly a firefly through glowing lights. Loops catch them all.",
  icon = ns.MEDIA .. "icons\\fireflies",
  order = 25,
  hasWins = true,
  Create = Create,
  OnHide = function()
    if field then Settle() end
  end,
  InProgress = function(d)
    if type(d) ~= "table" then return false end
    return d.mode ~= "relaxed" and type(d.moved) == "number" and d.moved > 0 and d.over ~= true
      and ValidBoard(d.board) and true or false
  end,
  Summary = function(d)
    local s = d.stats
    if s.best_level then return "Level " .. s.best_level end
    local best = s.best_moves or s.best_relaxed
    return best and ("Best " .. ns.FormatNumber(best)) or ""
  end,
})
