-------------------------------------------------------------------------------
-- Campfire Games: Ricochet
--
-- Move the mouse over the playfield to slide the paddle (Left/Right arrow keys
-- work too, but only while the ember is in play). Click to launch the ember, then bounce it into the wall to break
-- the stones. Where the ball meets the paddle sets its angle. Falling tokens:
-- a plank with arrows widens the paddle, an hourglass slows the ember, three
-- embers add more embers, a heart gives an extra life. Three lives;
-- clear every brick to move to the next wall, which gets a little faster.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, ceil, sin, cos, abs, min, max = math.floor, math.ceil, math.sin, math.cos, math.abs, math.min, math.max
local random = math.random

-- Playfield and brick grid (y grows downward in all game math).
local W, H = 302, 350
local COLS, ROWS = 10, 10
local BW, BH, PX, PY, OX, OY = 28, 12, 30, 14, 1, 26
local BALL_R = 4
local PAD_H, PAD_Y = 8, H - 26
local PAD_W, PAD_WIDE = 56, 86
local MAX_BALLS, MAX_LIVES = 3, 5
local TRAIL = 6
local N_PART, N_PUP = 28, 5
local STEP = 3.5

-- 1-6 stone and glass colors, 7 gold.
local COLORS = {
  { 0.72, 0.22, 0.20 },  -- ruby
  { 0.88, 0.56, 0.18 },  -- amber
  { 0.24, 0.58, 0.38 },  -- emerald
  { 0.24, 0.42, 0.74 },  -- sapphire
  { 0.54, 0.32, 0.68 },  -- amethyst
  { 0.56, 0.51, 0.46 },  -- slate
  { 0.96, 0.78, 0.28 },  -- gold
}

-- 1-6 colors, A-F the same colors with two hits, G gold, . empty.
local LEVELS = {
  { name = "Arch", rows = {
    "...GGGG...",
    "..444444..",
    ".44....44.",
    "44......44",
    "55......55",
    "55......55",
    "A6......6A",
    "66......66" } },
  { name = "Hearth", rows = {
    "6666666666",
    "6AAAAAAAA6",
    "6A......A6",
    "6A..22..A6",
    "6A.2GG2.A6",
    "6A.2112.A6",
    "6AA1111AA6" } },
  { name = "Lantern", rows = {
    "....66....",
    "...2222...",
    "..222222..",
    "..2GGGG2..",
    "..2GGGG2..",
    "..2GGGG2..",
    "..222222..",
    "...2222...",
    "....66...." } },
  { name = "Checker", rows = {
    "1.2.3.4.5.",
    ".2.3.4.5.6",
    "3.4.5.6.1.",
    ".4.5.6.1.2",
    "A.B.C.D.E.",
    ".B.C.D.E.F" } },
  { name = "Diamond", rows = {
    "....11....",
    "...2222...",
    "..333333..",
    ".44GGGG44.",
    "..555555..",
    "...6666...",
    "....11...." } },
  { name = "Fortress", rows = {
    "6.6.66.6.6",
    "6666666666",
    "6AAAAAAAA6",
    "6A.6666.A6",
    "6A.6GG6.A6",
    "6A.6666.A6",
    "6AAAAAAAA6",
    "6666666666" } },
  { name = "Twin Towers", rows = {
    "G........G",
    "22......22",
    "33......33",
    "A4..GG..4A",
    "B5..55..5B",
    "C6.1111.6C",
    "D6.1111.6D",
    "EEEEEEEEEE" } },
  { name = "Rose Window", rows = {
    "A11111111A",
    "B22222222B",
    "C33G33G33C",
    "D44444444D",
    "E55555555E",
    "F66666666F" } },
}

local POWER = {
  wide  = { icon = "widen", color = { 0.95, 0.75, 0.30 } },
  slow  = { icon = "slow", color = { 0.45, 0.72, 1.00 } },
  multi = { icon = "multi", color = { 1.00, 0.52, 0.22 } },
  life  = { icon = "life", color = { 0.60, 0.90, 0.50 } },
}

local data
local panel, field, paddle, pauseButton
local scoreText, levelText, hintText, statusText, toast
local pauseOver, overOver
local bricks, balls, particles, pups, pips = {}, {}, {}, {}, {}
local state = "ready"          -- ready, play, paused, over
local padX, padW, padTarget = W / 2, PAD_W, PAD_W
local wideT, slowT = 0, 0
local lastCursor
local Pause
local remaining = 0
local partNext = 1
local statusAcc, trailAcc = 0, 0
local lastSnd = {}

-------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------

local function Snd(kind, tone)
  local now = GetTime()
  if now - (lastSnd[kind] or -1) < 0.07 then return end
  lastSnd[kind] = now
  if tone then ns.PlayTone(kind) else ns.Sound(kind) end
end

local function Speed()
  return min(340, 180 + ((data.level or 1) - 1) * 14)
end

local function Decode(code)
  return floor(code / 100), floor(code / 10) % 10, code % 10 -- maxhp, hp, color
end

local function SyncKeys()
  ns.WantKeys(state == "play")
end

-------------------------------------------------------------------------------
-- Bricks
-------------------------------------------------------------------------------

local function PaintBrick(i)
  local b = bricks[i]
  local code = data.cells[i]
  if code == 0 then
    b.body:Hide(); b.hi:Hide(); b.lo:Hide(); b.band:Hide(); b.crack1:Hide(); b.crack2:Hide()
    return
  end
  local maxhp, hp, color = Decode(code)
  local c = COLORS[color]
  local dim = (hp < maxhp) and 0.62 or 1
  b.body:SetColorTexture(c[1] * dim, c[2] * dim, c[3] * dim, 1)
  b.hi:SetColorTexture(min(1, c[1] * dim + 0.35), min(1, c[2] * dim + 0.35), min(1, c[3] * dim + 0.35), 0.8)
  b.lo:SetColorTexture(c[1] * dim * 0.45, c[2] * dim * 0.45, c[3] * dim * 0.45, 1)
  b.body:Show(); b.hi:Show(); b.lo:Show()
  b.band:SetShown(maxhp == 2 and hp == 2)
  b.crack1:SetShown(hp < maxhp)
  b.crack2:SetShown(hp < maxhp)
end

local function CountBricks()
  local n = 0
  for i = 1, COLS * ROWS do
    if data.cells[i] ~= 0 then n = n + 1 end
  end
  remaining = n
end

local function PaintAll()
  for i = 1, COLS * ROWS do PaintBrick(i) end
end

local function LoadLevel(n)
  local layout = LEVELS[(n - 1) % #LEVELS + 1]
  local cells = {}
  for i = 1, COLS * ROWS do cells[i] = 0 end
  for r, line in ipairs(layout.rows) do
    for c = 1, COLS do
      local ch = line:sub(c, c)
      local code = 0
      if ch:match("[1-6]") then
        code = 100 + 10 + tonumber(ch)
      elseif ch:match("[A-F]") then
        code = 200 + 20 + (ch:byte() - 64)
      elseif ch == "G" then
        code = 100 + 10 + 7
      end
      cells[(r - 1) * COLS + c] = code
    end
  end
  data.cells = cells
  CountBricks()
  PaintAll()
end

local function ValidCells(t)
  if type(t) ~= "table" or #t ~= COLS * ROWS then return false end
  local any = false
  for i = 1, COLS * ROWS do
    local v = t[i]
    if type(v) ~= "number" or v ~= floor(v) then return false end
    if v ~= 0 then
      local maxhp, hp, color = Decode(v)
      if maxhp < 1 or maxhp > 2 or hp < 1 or hp > maxhp or color < 1 or color > 7 or v > 299 then return false end
      any = true
    end
  end
  return any
end

local function BrickAt(x, y)
  -- First live brick overlapping a ball-sized box centred on x, y.
  local c0 = max(0, floor((x - BALL_R - OX) / PX))
  local c1 = min(COLS - 1, floor((x + BALL_R - OX) / PX))
  local r0 = max(0, floor((y - BALL_R - OY) / PY))
  local r1 = min(ROWS - 1, floor((y + BALL_R - OY) / PY))
  for r = r0, r1 do
    for c = c0, c1 do
      local i = r * COLS + c + 1
      if data.cells[i] ~= 0 then
        local bx, by = OX + c * PX + 1, OY + r * PY + 1
        if x + BALL_R > bx and x - BALL_R < bx + BW and y + BALL_R > by and y - BALL_R < by + BH then
          return i
        end
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Particles, power-ups, status
-------------------------------------------------------------------------------

local function Burst(x, y, color, n)
  for _ = 1, n do
    local p = particles[partNext]
    partNext = partNext % N_PART + 1
    local a = random() * 6.2832
    local s = 30 + random() * 70
    p.x, p.y, p.vx, p.vy, p.life = x, y, cos(a) * s, sin(a) * s - 40, 0.35 + random() * 0.25
    p.tex:SetVertexColor(color[1], color[2], color[3], 1)
    p.tex:SetPoint("CENTER", field, "TOPLEFT", x, -y)
    p.tex:Show()
  end
end

local function SpawnPower(x, y, gold)
  local chance = gold and 0.45 or 0.11
  if random() > chance then return end
  local r = random(100)
  local kind
  if r <= 34 then kind = "wide"
  elseif r <= 64 then kind = "slow"
  elseif r <= 94 then kind = "multi"
  else kind = "life" end
  for _, p in ipairs(pups) do
    if not p.active then
      p.active, p.kind, p.x, p.y = true, kind, x, y
      local pc = POWER[kind].color
      p.icon:SetTexture(ns.MEDIA .. "ricochet\\" .. POWER[kind].icon)
      p.glow:SetVertexColor(pc[1], pc[2], pc[3], 0.6)
      p:ClearAllPoints()
      p:SetPoint("CENTER", field, "TOPLEFT", x, -y)
      p:Show()
      return
    end
  end
end

local function UpdateHeader()
  scoreText:SetText("Score " .. ns.FormatNumber(data.score))
  levelText:SetText("Level " .. data.level)
  for i = 1, MAX_LIVES do
    pips[i]:SetAlpha(i <= data.lives and 1 or 0.18)
  end
end

local function UpdateStatus()
  local s = ""
  if wideT > 0 then s = s .. "Wide " .. ceil(wideT) .. "s   " end
  if slowT > 0 then s = s .. "Slow " .. ceil(slowT) .. "s" end
  statusText:SetText(s)
end

local function PutPaddle()
  paddle:SetWidth(padW)
  paddle:ClearAllPoints()
  paddle:SetPoint("CENTER", field, "TOPLEFT", padX, -(PAD_Y + PAD_H / 2))
end

-------------------------------------------------------------------------------
-- Balls
-------------------------------------------------------------------------------

local function HideBall(b)
  b.active = false
  b.glow:Hide(); b.mid:Hide(); b.core:Hide()
  for k = 1, TRAIL do b.trail[k]:Hide() end
end

local function PlaceBall(b)
  b.glow:ClearAllPoints(); b.mid:ClearAllPoints(); b.core:ClearAllPoints()
  b.glow:SetPoint("CENTER", field, "TOPLEFT", b.x, -b.y)
  b.mid:SetPoint("CENTER", field, "TOPLEFT", b.x, -b.y)
  b.core:SetPoint("CENTER", field, "TOPLEFT", b.x, -b.y)
end

local function ShowBall(b)
  b.active = true
  b.glow:Show(); b.mid:Show(); b.core:Show()
  for k = 1, TRAIL do
    b.tx[k], b.ty[k] = b.x, b.y
    b.trail[k]:Hide()
  end
  PlaceBall(b)
end

local function ClearPowers()
  wideT, slowT = 0, 0
  padTarget = PAD_W
  for _, p in ipairs(pups) do
    p.active = false
    p:Hide()
  end
  UpdateStatus()
end

local function StickBall()
  for i = 2, MAX_BALLS do HideBall(balls[i]) end
  local b = balls[1]
  b.stuck = true
  b.vx, b.vy = 0, 0
  b.x, b.y = padX, PAD_Y - BALL_R
  ShowBall(b)
  for i = 1, TRAIL do b.trail[i]:Hide() end
end

local function SetState(s)
  state = s
  hintText:SetShown(s == "ready")
  pauseButton:SetText(s == "paused" and "Resume" or "Pause")
  if s == "ready" or s == "play" or s == "paused" then pauseButton:Enable() else pauseButton:Disable() end
  SyncKeys()
end

local function Launch()
  if state ~= "ready" then return end
  local b = balls[1]
  local a = (random() - 0.5) * 0.7
  local sp = Speed()
  b.stuck = false
  b.vx, b.vy = sin(a) * sp, -cos(a) * sp
  SetState("play")
end

local function StartLevelMessage()
  toast:Say("Level " .. data.level .. "  " .. LEVELS[(data.level - 1) % #LEVELS + 1].name)
end

local function GameOver()
  data.lives = 0
  data.bestLevel = max(data.bestLevel or 0, data.level)
  local newBest = ns.RecordResult("ricochet", { score = data.score })
  local best = data.stats.best or data.score
  SetState("over")
  UpdateHeader()
  overOver:Open(newBest and "A new best!" or "The ember goes out",
    format("Score %s\nLevel reached %d\nBest %s", ns.FormatNumber(data.score), data.level, ns.FormatNumber(best)))
end

local function NewRun()
  overOver:Close()
  pauseOver:Close()
  data.level, data.score, data.lives = 1, 0, 3
  LoadLevel(1)
  ClearPowers()
  padX = W / 2
  PutPaddle()
  StickBall()
  UpdateHeader()
  SetState("ready")
  StartLevelMessage()
end

local function LoseLife()
  Snd("wrong", true)
  ClearPowers()
  data.lives = data.lives - 1
  UpdateHeader()
  if data.lives <= 0 then
    GameOver()
  else
    StickBall()
    SetState("ready")
  end
end

local function ClearLevel()
  Snd("chime", true)
  data.score = data.score + 100
  data.level = data.level + 1
  data.bestLevel = max(data.bestLevel or 0, data.level)
  ClearPowers()
  LoadLevel(data.level)
  StickBall()
  UpdateHeader()
  SetState("ready")
  StartLevelMessage()
end

local function Damage(i)
  local code = data.cells[i]
  local maxhp, hp, color = Decode(code)
  local c, r = (i - 1) % COLS, floor((i - 1) / COLS)
  local cx, cy = OX + c * PX + 1 + BW / 2, OY + r * PY + 1 + BH / 2
  Snd("place")
  if hp > 1 then
    data.cells[i] = maxhp * 100 + (hp - 1) * 10 + color
    data.score = data.score + 5
    PaintBrick(i)
    Burst(cx, cy, COLORS[color], 2)
  else
    data.cells[i] = 0
    remaining = remaining - 1
    data.score = data.score + (color == 7 and 50 or (maxhp == 2 and 25 or 10))
    PaintBrick(i)
    Burst(cx, cy, COLORS[color], 5)
    SpawnPower(cx, cy, color == 7)
  end
  scoreText:SetText("Score " .. ns.FormatNumber(data.score))
end

local function Collect(kind)
  Snd("good")
  if kind == "wide" then
    wideT = 10
    padTarget = PAD_WIDE
  elseif kind == "slow" then
    slowT = 10
  elseif kind == "multi" then
    local src
    local free = {}
    for i = 1, MAX_BALLS do
      local b = balls[i]
      if b.active and not b.stuck then src = src or b end
      if not b.active then free[#free + 1] = b end
    end
    if src then
      local sp = Speed()
      local base = math.atan2(src.vx, -src.vy)
      for n, b in ipairs(free) do
        local a = base + (n == 1 and 0.45 or -0.45)
        b.x, b.y, b.stuck = src.x, src.y, false
        b.vx, b.vy = sin(a) * sp, -cos(a) * sp
        ShowBall(b)
      end
    end
  elseif kind == "life" then
    data.lives = min(MAX_LIVES, data.lives + 1)
    UpdateHeader()
  end
  UpdateStatus()
end

-------------------------------------------------------------------------------
-- Movement
-------------------------------------------------------------------------------

local function StepBall(b, h)
  local mul = slowT > 0 and 0.7 or 1

  -- sideways
  local nx = b.x + b.vx * mul * h
  if nx < BALL_R then
    nx = BALL_R; b.vx = abs(b.vx)
  elseif nx > W - BALL_R then
    nx = W - BALL_R; b.vx = -abs(b.vx)
  end
  local hit = BrickAt(nx, b.y)
  if hit then
    b.vx = -b.vx
    Damage(hit)
  else
    b.x = nx
  end

  -- up and down
  local oldBottom = b.y + BALL_R
  local ny = b.y + b.vy * mul * h
  if ny < BALL_R then
    ny = BALL_R; b.vy = abs(b.vy)
  end
  hit = BrickAt(b.x, ny)
  if hit then
    b.vy = -b.vy
    Damage(hit)
  else
    b.y = ny
  end

  -- paddle
  if b.vy > 0 and b.y + BALL_R >= PAD_Y and oldBottom <= PAD_Y + 4 then
    local hw = padW / 2
    if b.x >= padX - hw - 3 and b.x <= padX + hw + 3 then
      local rel = (b.x - padX) / (hw + 3)
      if rel < -1 then rel = -1 elseif rel > 1 then rel = 1 end
      local a = rel * 1.0
      local sp = Speed()
      b.vx, b.vy = sin(a) * sp, -cos(a) * sp
      b.y = PAD_Y - BALL_R
    end
  end
end

local function MoveBalls(dt)
  local sp = Speed() * (slowT > 0 and 0.7 or 1)
  local steps = max(1, ceil(sp * dt / STEP))
  local h = dt / steps
  for s = 1, steps do
    for i = 1, MAX_BALLS do
      local b = balls[i]
      if b.active and not b.stuck then
        StepBall(b, h)
        if b.y - BALL_R > H then HideBall(b) end
      end
    end
    if remaining <= 0 then return end
  end
end

local function CountBalls()
  local n = 0
  for i = 1, MAX_BALLS do
    if balls[i].active then n = n + 1 end
  end
  return n
end

local function UpdateTrail(b)
  for k = TRAIL, 2, -1 do b.tx[k], b.ty[k] = b.tx[k - 1], b.ty[k - 1] end
  b.tx[1], b.ty[1] = b.x, b.y
  for k = 1, TRAIL do
    local t = b.trail[k]
    t:ClearAllPoints()
    t:SetPoint("CENTER", field, "TOPLEFT", b.tx[k], -b.ty[k])
    t:Show()
  end
end

local function OnUpdate(_, dt)
  if state ~= "play" and state ~= "ready" then return end
  if dt > 0.05 then dt = 0.05 end

  -- Paddle follows the mouse anywhere over the window (it stops at the
  -- board edges), so pushing it to a side doesn't pause the game.
  local cx
  local over = (ns.frame and ns.frame:IsMouseOver()) or field:IsMouseOver()
  if over then
    cx = GetCursorPosition() / field:GetEffectiveScale() - field:GetLeft()
    if lastCursor and abs(cx - lastCursor) > 0.5 then padX = cx end
    lastCursor = cx
  else
    -- cursor left the window mid-play: pause (resume by clicking)
    if lastCursor and state == "play" then
      lastCursor = nil
      Pause()
      return
    end
    lastCursor = nil
  end
  if abs(padW - padTarget) > 0.5 then
    padW = padW + (padTarget - padW) * min(1, dt * 12)
  else
    padW = padTarget
  end
  local hw = padW / 2
  if padX < hw + 1 then padX = hw + 1 elseif padX > W - hw - 1 then padX = W - hw - 1 end
  PutPaddle()

  -- ember pulse
  local pulse = 0.85 + 0.15 * sin(GetTime() * 11)
  if not (ns.db and ns.db.flicker) then pulse = 1 end

  if state == "ready" then
    local b = balls[1]
    b.x, b.y = padX, PAD_Y - BALL_R
    PlaceBall(b)
    b.glow:SetAlpha(pulse)
  else
    if wideT > 0 then
      wideT = wideT - dt
      if wideT <= 0 then wideT = 0; padTarget = PAD_W end
    end
    if slowT > 0 then
      slowT = slowT - dt
      if slowT < 0 then slowT = 0 end
    end
    statusAcc = statusAcc + dt
    if statusAcc > 0.2 then statusAcc = 0; UpdateStatus() end

    MoveBalls(dt)

    trailAcc = trailAcc + dt
    local doTrail = trailAcc >= 0.02
    if doTrail then trailAcc = 0 end
    for i = 1, MAX_BALLS do
      local b = balls[i]
      if b.active then
        PlaceBall(b)
        b.glow:SetAlpha(pulse)
        if doTrail then UpdateTrail(b) end
      end
    end

    -- falling tokens
    for _, p in ipairs(pups) do
      if p.active then
        p.y = p.y + 85 * dt
        if p.y > H + 10 then
          p.active = false
          p:Hide()
        elseif p.y + 8 >= PAD_Y and p.y - 8 <= PAD_Y + PAD_H and abs(p.x - padX) <= hw + 7 then
          p.active = false
          p:Hide()
          Collect(p.kind)
        else
          p:ClearAllPoints()
          p:SetPoint("CENTER", field, "TOPLEFT", p.x, -p.y)
        end
      end
    end

    if remaining <= 0 then
      ClearLevel()
    elseif CountBalls() == 0 then
      LoseLife()
    end
  end

  -- sparks
  for i = 1, N_PART do
    local p = particles[i]
    if p.life > 0 then
      p.life = p.life - dt
      if p.life <= 0 then
        p.tex:Hide()
      else
        p.vy = p.vy + 260 * dt
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        p.tex:ClearAllPoints()
        p.tex:SetPoint("CENTER", field, "TOPLEFT", p.x, -p.y)
        p.tex:SetAlpha(min(1, p.life * 3))
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Pause and keys
-------------------------------------------------------------------------------

function Pause()
  if state ~= "play" then return end
  SetState("paused")
  pauseOver:Open("Paused", "Click to continue")
end

local function Resume()
  if state ~= "paused" then return end
  pauseOver:Close()
  lastCursor = nil
  SetState("play")
end

local function OnKey(key)
  if state ~= "play" then return false end
  if key == "LEFT" or key == "RIGHT" then
    padX = padX + (key == "LEFT" and -22 or 22)
    return true
  end
  return false
end

StaticPopupDialogs["DOWNTIME_NEW_RICOCHET"] = {
  text = "Start a new Ricochet run? This one will end.",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    if data.score > 0 and state ~= "over" then
      ns.RecordResult("ricochet", { score = data.score })
    end
    NewRun()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function BuildPaddle()
  paddle = CreateFrame("Frame", nil, field)
  paddle:SetSize(PAD_W, PAD_H)
  local body = paddle:CreateTexture(nil, "ARTWORK")
  body:SetAllPoints()
  body:SetColorTexture(0.45, 0.27, 0.12, 1)
  local top = paddle:CreateTexture(nil, "OVERLAY")
  top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
  top:SetColorTexture(0.98, 0.80, 0.38, 1)
  local lit = paddle:CreateTexture(nil, "ARTWORK")
  lit:SetPoint("TOPLEFT", 3, -1); lit:SetPoint("TOPRIGHT", -3, -1); lit:SetHeight(2)
  lit:SetColorTexture(0.64, 0.42, 0.20, 1)
  local low = paddle:CreateTexture(nil, "OVERLAY")
  low:SetPoint("BOTTOMLEFT"); low:SetPoint("BOTTOMRIGHT"); low:SetHeight(2)
  low:SetColorTexture(0.20, 0.10, 0.04, 1)
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local cap = paddle:CreateTexture(nil, "OVERLAY")
    cap:SetPoint("TOP" .. side); cap:SetPoint("BOTTOM" .. side); cap:SetWidth(4)
    cap:SetColorTexture(0.92, 0.72, 0.28, 1)
    local capLo = paddle:CreateTexture(nil, "OVERLAY")
    capLo:SetPoint("BOTTOM" .. side); capLo:SetSize(4, 2)
    capLo:SetColorTexture(0.58, 0.40, 0.14, 1)
    local grain = paddle:CreateTexture(nil, "OVERLAY")
    grain:SetPoint(side, side == "LEFT" and 14 or -14, -1)
    grain:SetSize(10, 1)
    grain:SetColorTexture(0.30, 0.17, 0.07, 0.8)
  end
  local glow = paddle:CreateTexture(nil, "BACKGROUND")
  glow:SetTexture(ns.MEDIA .. "glow")
  glow:SetPoint("TOPLEFT", -6, 6); glow:SetPoint("BOTTOMRIGHT", 6, -2)
  glow:SetVertexColor(C.ember[1], C.ember[2], C.ember[3], 0.18)
  glow:SetBlendMode("ADD")
end

local function BuildBricks()
  for i = 1, COLS * ROWS do
    local c, r = (i - 1) % COLS, floor((i - 1) / COLS)
    local x, y = OX + c * PX + 1, -(OY + r * PY + 1)
    local b = {}
    b.body = field:CreateTexture(nil, "ARTWORK")
    b.body:SetSize(BW, BH)
    b.body:SetPoint("TOPLEFT", x, y)
    b.hi = field:CreateTexture(nil, "ARTWORK")
    b.hi:SetSize(BW - 2, 1)
    b.hi:SetPoint("TOPLEFT", x + 1, y - 1)
    b.lo = field:CreateTexture(nil, "ARTWORK")
    b.lo:SetSize(BW, 2)
    b.lo:SetPoint("TOPLEFT", x, y - BH + 2)
    b.band = field:CreateTexture(nil, "ARTWORK")
    b.band:SetSize(BW, 2)
    b.band:SetPoint("TOPLEFT", x, y - 5)
    b.band:SetColorTexture(0.12, 0.09, 0.07, 0.85)
    b.crack1 = field:CreateTexture(nil, "ARTWORK")
    b.crack1:SetSize(1, 8)
    b.crack1:SetPoint("TOPLEFT", x + 12, y - 2)
    b.crack1:SetColorTexture(0.05, 0.03, 0.02, 0.9)
    b.crack2 = field:CreateTexture(nil, "ARTWORK")
    b.crack2:SetSize(7, 1)
    b.crack2:SetPoint("TOPLEFT", x + 12, y - 6)
    b.crack2:SetColorTexture(0.05, 0.03, 0.02, 0.9)
    b.body:Hide(); b.hi:Hide(); b.lo:Hide(); b.band:Hide(); b.crack1:Hide(); b.crack2:Hide()
    bricks[i] = b
  end
end

local function DotTexture(parent, size, r, g, b, a)
  local t = parent:CreateTexture(nil, "OVERLAY")
  t:SetTexture(ns.MEDIA .. "dot")
  t:SetSize(size, size)
  t:SetVertexColor(r, g, b, a)
  t:SetBlendMode("ADD")
  t:Hide()
  return t
end

local function BuildActors()
  for i = 1, N_PART do
    particles[i] = { life = 0, x = 0, y = 0, vx = 0, vy = 0, tex = DotTexture(field, 6, 1, 0.7, 0.3, 1) }
  end
  for i = 1, MAX_BALLS do
    local b = { active = false, x = 0, y = 0, vx = 0, vy = 0, tx = {}, ty = {}, trail = {} }
    for k = 1, TRAIL do
      local s = 13 - k * 1.6
      b.trail[k] = DotTexture(field, s, 1, 0.5, 0.18, 0.5 * (1 - (k - 1) / TRAIL))
    end
    b.glow = DotTexture(field, 28, 1, 0.48, 0.14, 0.7)
    b.mid = DotTexture(field, 13, 1, 0.72, 0.30, 0.95)
    b.core = DotTexture(field, 6, 1, 0.96, 0.82, 1)
    balls[i] = b
  end
  for i = 1, N_PUP do
    local p = CreateFrame("Frame", nil, field)
    p:SetSize(16, 16)
    p.glow = p:CreateTexture(nil, "BACKGROUND")
    p.glow:SetTexture(ns.MEDIA .. "dot")
    p.glow:SetSize(32, 32)
    p.glow:SetPoint("CENTER")
    p.glow:SetBlendMode("ADD")
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetSize(22, 22)
    p.icon:SetPoint("CENTER")
    p.active = false
    p:Hide()
    pups[i] = p
  end
end

local function Create(parent, saved)
  panel = parent
  data = saved

  if type(data.level) ~= "number" or data.level < 1 or data.level ~= floor(data.level)
    or type(data.score) ~= "number" or data.score < 0
    or type(data.lives) ~= "number" or data.lives < 1 or data.lives > MAX_LIVES or data.lives ~= floor(data.lives)
    or not ValidCells(data.cells) then
    data.level, data.score, data.lives, data.cells = nil, nil, nil, nil
  end
  if type(data.bestLevel) ~= "number" then data.bestLevel = nil end

  local left = floor((ns.GAME_W - W) / 2)

  field = CreateFrame("Button", nil, parent)
  field:SetSize(W, H)
  field:SetPoint("TOPLEFT", left, -24)
  field:RegisterForClicks("LeftButtonUp")
  local bg = field:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  UI.Color(bg, C.inset, 1)
  local hearth = field:CreateTexture(nil, "BACKGROUND")
  hearth:SetTexture(ns.MEDIA .. "glow")
  hearth:SetPoint("BOTTOMLEFT"); hearth:SetPoint("BOTTOMRIGHT"); hearth:SetHeight(120)
  hearth:SetVertexColor(C.ember[1], C.ember[2], C.ember[3], 0.16)
  hearth:SetBlendMode("ADD")
  local vig = field:CreateTexture(nil, "BORDER")
  vig:SetTexture(ns.MEDIA .. "vignette")
  vig:SetAllPoints()
  vig:SetVertexColor(1, 1, 1, 0.6)
  UI.Border(field, C.line, 1, "OVERLAY", 0.8)

  BuildBricks()
  BuildActors()
  BuildPaddle()

  hintText = UI.Text(field, 12, C.dim)
  hintText:SetPoint("CENTER", field, "TOP", 0, -(PAD_Y - 54))
  hintText:SetText("Click to launch")
  statusText = UI.Text(field, 10, C.dim)
  statusText:SetPoint("BOTTOMLEFT", 6, 4)
  statusText:SetJustifyH("LEFT")

  -- header: score, level, lives
  scoreText = UI.Text(parent, 12, C.cream)
  scoreText:SetPoint("TOPLEFT", left + 2, -4)
  levelText = UI.Title(parent, 14)
  levelText:SetPoint("TOP", 0, -3)
  for i = 1, MAX_LIVES do
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(ns.MEDIA .. "dot")
    t:SetSize(16, 16)
    t:SetPoint("TOPRIGHT", -(left + 2) - (MAX_LIVES - i) * 13, -3)
    t:SetVertexColor(C.ember[1], C.ember[2], C.ember[3], 1)
    t:SetBlendMode("ADD")
    pips[i] = t
  end

  toast = UI.Toast(field)
  toast:ClearAllPoints()
  toast:SetPoint("CENTER", field, "TOP", 0, -(OY + ROWS * PY + 30))

  pauseOver = UI.Overlay(field)
  pauseOver:SetScript("OnMouseUp", Resume)
  overOver = UI.Overlay(field)
  local again = UI.Button(overOver.buttons, "New game", 100, 24)
  again:SetPoint("TOP", 0, 0)
  again:SetScript("OnClick", NewRun)

  pauseButton = UI.Button(parent, "Pause", 90, 22)
  pauseButton:SetPoint("TOPLEFT", field, "BOTTOM", -97, -8)
  pauseButton:SetScript("OnClick", function()
    if state == "play" then Pause() elseif state == "paused" then Resume() end
  end)
  local newButton = UI.Button(parent, "New game", 100, 22)
  newButton:SetPoint("LEFT", pauseButton, "RIGHT", 4, 0)
  newButton:SetScript("OnClick", function()
    if state == "over" or data.score == 0 then
      NewRun()
    else
      Pause()
      StaticPopup_Show("DOWNTIME_NEW_RICOCHET")
    end
  end)

  field:SetScript("OnClick", function()
    if state == "ready" then Launch() end
  end)

  -- resume a saved run (ball back on the paddle) or start fresh
  if data.cells and data.level then
    CountBricks()
    PaintAll()
    ClearPowers()
    PutPaddle()
    StickBall()
    UpdateHeader()
    SetState("ready")
  else
    NewRun()
  end

  field:SetScript("OnUpdate", OnUpdate)
end

ns.RegisterGame({
  key = "ricochet",
  name = "Ricochet",
  blurb = "Bounce the ember and knock down the wall.",
  icon = ns.MEDIA .. "icons\\ricochet",
  order = 100,
  Create = Create,
  OnKey = OnKey,
  OnShow = SyncKeys,
  OnHide = function()
    ns.WantKeys(false)
    if state == "play" then Pause() end
  end,
  InProgress = function(d)
    if type(d) ~= "table" then return false end
    if type(d.level) ~= "number" or d.level < 1 or d.level ~= floor(d.level) then return false end
    if type(d.score) ~= "number" or d.score < 0 then return false end
    if type(d.lives) ~= "number" or d.lives < 1 or d.lives > MAX_LIVES then return false end
    if not ValidCells(d.cells) then return false end
    return d.score > 0 or d.level > 1
  end,
  Summary = function(d)
    local best = d.stats and d.stats.best
    return best and ("Best " .. ns.FormatNumber(best)) or ""
  end,
})
