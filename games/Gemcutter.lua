-------------------------------------------------------------------------------
-- Campfire Games: Gemcutter
--
-- Click a gem, then a neighbor to swap them (or press on a gem and release
-- over a neighbor). Line up three or more of a color to clear them. Four in
-- a line makes an ember gem that clears the 3x3 around it when matched. Five
-- in a line (or an L or T) makes a prism: swap it with any gem to clear every
-- gem of that color. Relaxed is endless; 30 Moves ends after 30 swaps.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, sin, random = math.floor, math.sin, math.random

local N, CELL = 8, 36
local SIZE = N * CELL -- 288
local MOVES = 30
local HINT_AFTER = 10

local MODES = {
  { key = "relaxed", label = "Relaxed" },
  { key = "moves", label = "30 Moves" },
}
local BEST_KEY = { relaxed = "best_relaxed", moves = "best_moves" }
local GEM_TEX = {}
for k = 1, 6 do GEM_TEX[k] = ns.MEDIA .. "gems\\gem" .. k end
local SPARK_TEX = ns.MEDIA .. "gems\\spark"
local MARK_SCALE = 1.1 -- raid mark icons have empty margin, so draw them a bit larger

-- Texture for a cell code. Prism: the skull mark, or the white gem.
local function TexFor(code)
  if ns.UseRaidMarks() then
    if code == 20 then return ns.RAID_MARKS[8] end
    return ns.RAID_MARKS[ns.PIECE_MARKS[code % 10]]
  end
  local k = code % 10
  return GEM_TEX[(k == 0 or code == 20) and 6 or k]
end

local data, b, pc          -- saved table, logic board (64 codes), piece sprites
local panel, field, layer, selRing, overlay, toast, scoreText, bestText, movesText
local modeRow, cells = nil, {}
local phase = "idle"
local now, hintT, cascade = 0, 0, 0
local selected, hint, pending, swapA, swapB
local down, downX, downY
local pool, sparks, floats = {}, {}, {}

-- Cell codes: 1-6 gem, 11-16 ember of that color, 20 prism.
local function Kind(code) return code % 10 end
local function CellXY(i) return ((i - 1) % N + 0.5) * CELL, (floor((i - 1) / N) + 0.5) * CELL end
local function Smooth(t)
  if t >= 1 then return 1 end
  if t <= 0 then return 0 end
  return t * t * (3 - 2 * t)
end

-------------------------------------------------------------------------------
-- Board logic
-------------------------------------------------------------------------------

-- Every run of 3+ same-colored cells: { cells = {...}, dir = "h"|"v" }.
local function FindRuns(board)
  local runs = {}
  for pass = 1, 2 do
    for line = 1, N do
      local s = 1
      while s <= N do
        local function at(p) return pass == 1 and (line - 1) * N + p or (p - 1) * N + line end
        local k, e = Kind(board[at(s)]), s
        if k > 0 then
          while e < N and Kind(board[at(e + 1)]) == k do e = e + 1 end
          if e - s >= 2 then
            local list = {}
            for p = s, e do list[#list + 1] = at(p) end
            runs[#runs + 1] = { cells = list, dir = pass == 1 and "h" or "v" }
          end
        end
        s = e + 1
      end
    end
  end
  return runs
end

local function Swapped(board, a, c)
  board[a], board[c] = board[c], board[a]
end

local function ValidSwap(board, a, c)
  if board[a] == 20 or board[c] == 20 then return true end
  Swapped(board, a, c)
  local ok = #FindRuns(board) > 0
  Swapped(board, a, c)
  return ok
end

local function AllMoves(board)
  local out = {}
  for i = 1, N * N do
    local r, c = floor((i - 1) / N), (i - 1) % N
    if c < N - 1 and ValidSwap(board, i, i + 1) then out[#out + 1] = { i, i + 1 } end
    if r < N - 1 and ValidSwap(board, i, i + N) then out[#out + 1] = { i, i + N } end
  end
  return out
end

local function FreshBoard()
  local nb
  repeat
    nb = {}
    for i = 1, N * N do
      local r, c = floor((i - 1) / N) + 1, (i - 1) % N + 1
      local k
      repeat
        k = random(6)
      until not (c >= 3 and nb[i - 1] == k and nb[i - 2] == k)
        and not (r >= 3 and nb[i - N] == k and nb[i - 2 * N] == k)
      nb[i] = k
    end
  until #AllMoves(nb) > 0
  return nb
end

-- Add the 3x3 around every ember in the set (chaining).
local function ExpandEmbers(set)
  local done, again = {}, true
  while again do
    again = false
    for i in pairs(set) do
      local code = b[i]
      if code and code > 10 and code < 20 and not done[i] then
        done[i] = true
        again = true
        local r, c = floor((i - 1) / N), (i - 1) % N
        for dr = -1, 1 do
          for dc = -1, 1 do
            local rr, cc = r + dr, c + dc
            if rr >= 0 and rr < N and cc >= 0 and cc < N then set[rr * N + cc + 1] = true end
          end
        end
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Sprites
-------------------------------------------------------------------------------

local function NewPiece()
  local p = table.remove(pool)
  if not p then
    p = {}
    p.glow = layer:CreateTexture(nil, "ARTWORK", nil, 0)
    p.glow:SetTexture(ns.MEDIA .. "dot")
    p.glow:SetBlendMode("ADD")
    p.tex = layer:CreateTexture(nil, "ARTWORK", nil, 1)
  end
  p.x, p.y, p.sc, p.al = 0, 0, 1, 1
  p.mv, p.clr, p.pop, p.pulse = nil, nil, nil, nil
  p.tex:SetVertexColor(1, 1, 1)
  p.tex:Show()
  return p
end

local function FreePiece(p)
  p.tex:Hide()
  p.glow:Hide()
  pool[#pool + 1] = p
end

local function Draw(p)
  local s = SIZE / N - 4
  local sc = p.sc
  if ns.UseRaidMarks() then
    sc = sc * MARK_SCALE
  elseif p.code == 20 then
    sc = sc * 1.15
  end
  if p.pulse then sc = sc * (1 + 0.07 * sin(now * 7)) end
  p.tex:SetSize(s * sc, s * sc)
  p.tex:ClearAllPoints()
  p.tex:SetPoint("CENTER", field, "TOPLEFT", p.x, -p.y)
  p.tex:SetAlpha(p.al)
  if p.code > 10 then
    local gs = s * sc * 1.45
    if p.code == 20 then gs = gs * 1.15 end
    p.glow:SetSize(gs, gs)
    p.glow:ClearAllPoints()
    p.glow:SetPoint("CENTER", field, "TOPLEFT", p.x, -p.y)
    local pulse = 0.5 + 0.5 * sin(now * 3.2 + p.x * 0.1)
    if p.code == 20 then
      local r = 0.65 + 0.35 * sin(now * 2)
      local g = 0.65 + 0.35 * sin(now * 2 + 2.1)
      local bl = 0.65 + 0.35 * sin(now * 2 + 4.2)
      if ns.UseRaidMarks() then p.tex:SetVertexColor(1, 1, 1) else p.tex:SetVertexColor(r, g, bl) end
      p.glow:SetVertexColor(r, g, bl, (0.30 + 0.2 * pulse) * p.al)
    else
      p.glow:SetVertexColor(1, 0.55, 0.2, (0.28 + 0.32 * pulse) * p.al)
    end
  end
end

local function SetCode(p, code)
  p.code = code
  p.tex:SetTexture(TexFor(code))
  p.tex:SetVertexColor(1, 1, 1)
  p.glow:SetShown(code > 10)
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

-- Advance one sprite; returns true while it still has work.
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
    local e = p.clr / 0.2
    if e >= 1 then
      p.clr, p.sc, p.al = 1, 0.2, 0
    else
      p.sc, p.al = 1 - 0.8 * e, 1 - e
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
    pc[i].pop = -random() * 0.12
  end
end

-------------------------------------------------------------------------------
-- Effects: sparks and floating score
-------------------------------------------------------------------------------

local function Spark(x, y, big)
  local s
  for _, e in ipairs(sparks) do
    if not e.on then s = e break end
  end
  if not s then return end
  s.on, s.age, s.life = true, 0, 0.35 + random() * 0.2
  s.x, s.y = x, y
  s.vx, s.vy = (random() - 0.5) * 50, -random() * 30 - 5
  s.size = big and 30 or 20
  s.tex:Show()
end

local function Floater(x, y, text)
  local f
  for _, e in ipairs(floats) do
    if not e.on then f = e break end
  end
  if not f then f = floats[1] end
  f.on, f.age, f.x, f.y = true, 0, math.max(30, math.min(SIZE - 30, x)), y
  f.fs:SetText(text)
  f.fs:Show()
end

local function UpdateEffects(dt)
  for _, s in ipairs(sparks) do
    if s.on then
      s.age = s.age + dt
      local e = s.age / s.life
      if e >= 1 then
        s.on = false
        s.tex:Hide()
      else
        s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
        local z = s.size * (0.6 + 0.8 * e)
        s.tex:SetSize(z, z)
        s.tex:ClearAllPoints()
        s.tex:SetPoint("CENTER", field, "TOPLEFT", s.x, -s.y)
        s.tex:SetAlpha(1 - e)
      end
    end
  end
  for _, f in ipairs(floats) do
    if f.on then
      f.age = f.age + dt
      local e = f.age / 0.95
      if e >= 1 then
        f.on = false
        f.fs:Hide()
      else
        f.fs:ClearAllPoints()
        f.fs:SetPoint("CENTER", field, "TOPLEFT", f.x, -(f.y - 26 * Smooth(e)))
        f.fs:SetAlpha(e < 0.5 and 1 or (1 - e) * 2)
      end
    end
  end
end

-------------------------------------------------------------------------------
-- HUD
-------------------------------------------------------------------------------

local function BestShown()
  local v = data.stats[BEST_KEY[data.mode]] or 0
  if data.mode == "relaxed" and data.score > v then v = data.score end
  return v
end

local function UpdateHud()
  scoreText:SetText("Score " .. ns.FormatNumber(data.score))
  bestText:SetText("Best " .. ns.FormatNumber(BestShown()))
  if data.mode == "moves" then
    movesText:SetText("Moves left: " .. data.moves)
  else
    movesText:SetText("")
  end
  modeRow:Select(data.mode)
end

local function SetSelected(i)
  selected = i
  if i then
    local x, y = CellXY(i)
    selRing:ClearAllPoints()
    selRing:SetPoint("CENTER", field, "TOPLEFT", x, -y)
    selRing:Show()
  else
    selRing:Hide()
  end
end

local function ClearHint()
  hintT = 0
  if hint then
    for _, p in ipairs(hint) do
      p.pulse = nil
      Draw(p) -- drop the pulse size right away
    end
    hint = nil
  end
end

-------------------------------------------------------------------------------
-- Turn flow
-------------------------------------------------------------------------------

local Resolve

local function GameOver()
  data.over = true
  phase = "over"
  local newBest = ns.RecordResult("gems", { score = data.score, bestKey = "best_moves" })
  ns.Sound("win")
  UpdateHud()
  overlay:Open(newBest and "A new best!" or "Out of moves",
    format("Score %s\nBest %s", ns.FormatNumber(data.score), ns.FormatNumber(data.stats.best_moves or data.score)))
end

local function Reshuffle()
  toast:Say("No moves left. Reshuffling...")
  local list
  for _ = 1, 60 do
    list = {}
    for i = 1, N * N do list[i] = b[i] end
    ns.Shuffle(list)
    if #FindRuns(list) == 0 and #AllMoves(list) > 0 then break end
    list = nil
  end
  if not list then
    list = FreshBoard()
  end
  for i = 1, N * N do
    b[i] = list[i]
    SetCode(pc[i], b[i])
    Pop(pc[i])
  end
end

local function EndTurn()
  cascade = 0
  phase = "idle"
  if data.mode == "moves" and data.moves <= 0 then
    GameOver()
    return
  end
  if #AllMoves(b) == 0 then Reshuffle() end
  ClearHint()
  UpdateHud()
end

local function StartClear(set, creates, bonus)
  cascade = cascade + 1
  local n, sx, sy, count = 0, 0, 0, 0
  for i in pairs(set) do
    n = n + 1
    local x, y = CellXY(i)
    sx, sy, count = sx + x, sy + y, count + 1
    pc[i].clr = 0
    Spark(x, y, b[i] > 10)
    Spark(x, y, false)
  end
  for i, code in pairs(creates) do
    bonus = bonus + (code == 20 and 100 or 40)
    local x, y = CellXY(i)
    sx, sy, count = sx + x, sy + y, count + 1
  end
  local gain = (n * 10 + bonus) * cascade
  pending = { set = set, creates = creates, gain = gain }
  Floater(sx / math.max(1, count), sy / math.max(1, count),
    "+" .. gain .. (cascade > 1 and (" x" .. cascade) or ""))
  ns.Sound(next(creates) and "coin" or "good")
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
  -- Gravity, then new gems from above.
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
          MoveTo(pc[j], pc[j].x, ty, math.min(0.25, 0.1 + 0.035 * (j - i) / N))
        end
        w = w - 1
      end
    end
    for r = w, 1, -1 do
      local j = (r - 1) * N + c
      local code = random(6)
      b[j] = code
      local _, ty = CellXY(j)
      local p = MakePiece(j, code, -CELL * (w - r + 0.5))
      pc[j] = p
      MoveTo(p, p.x, ty, math.min(0.25, 0.12 + 0.03 * w))
    end
  end
  UpdateHud()
  phase = "fall"
end

-- Look for matches; clear them, or end the turn when there are none.
function Resolve(pref)
  local runs = FindRuns(b)
  if #runs == 0 then EndTurn() return end
  local set, creates, hset = {}, {}, {}
  for _, run in ipairs(runs) do
    for _, i in ipairs(run.cells) do
      set[i] = true
      if run.dir == "h" then hset[i] = true end
    end
  end
  local function Plain(i) return b[i] <= 6 end
  local function Mark(i, code)
    if creates[i] == 20 then return end
    creates[i] = code
  end
  for _, run in ipairs(runs) do
    local list, len = run.cells, #run.cells
    if len >= 4 then
      local pivot
      for _, i in ipairs(list) do
        if pref and pref[i] and Plain(i) then pivot = i break end
      end
      if not pivot then
        local mid = list[floor((len + 1) / 2)]
        if Plain(mid) then pivot = mid end
      end
      if not pivot then
        for _, i in ipairs(list) do
          if Plain(i) then pivot = i break end
        end
      end
      if pivot then Mark(pivot, len >= 5 and 20 or 10 + Kind(b[pivot])) end
    end
    if run.dir == "v" then
      for _, i in ipairs(list) do
        if hset[i] and Plain(i) then Mark(i, 20) end
      end
    end
  end
  local before = {}
  for i in pairs(set) do before[i] = true end
  ExpandEmbers(set)
  for i in pairs(creates) do
    if set[i] and not before[i] then creates[i] = nil end
  end
  for i in pairs(creates) do set[i] = nil end
  StartClear(set, creates, 0)
end

local function CommitSwap()
  local a, c = swapA, swapB
  local ca, cc = b[a], b[c]
  Swapped(b, a, c)
  pc[a], pc[c] = pc[c], pc[a]
  data.swaps = data.swaps + 1
  if data.mode == "moves" then data.moves = math.max(0, data.moves - 1) end
  UpdateHud()
  if ca == 20 or cc == 20 then
    local set = {}
    if ca == 20 and cc == 20 then
      for i = 1, N * N do set[i] = true end
    else
      local k = Kind(ca == 20 and cc or ca)
      for i = 1, N * N do
        if Kind(b[i]) == k then set[i] = true end
      end
      set[a], set[c] = true, true
    end
    ExpandEmbers(set)
    StartClear(set, {}, 50)
  else
    Resolve({ [a] = true, [c] = true })
  end
end

local function Advance()
  if phase == "swap" then
    CommitSwap()
  elseif phase == "swapbad" then
    phase = "swapback"
    local ax, ay = CellXY(swapA)
    local bx, by = CellXY(swapB)
    MoveTo(pc[swapA], ax, ay, 0.14)
    MoveTo(pc[swapB], bx, by, 0.14)
  elseif phase == "swapback" then
    phase = "idle"
    ClearHint()
  elseif phase == "clear" then
    ApplyClear()
  elseif phase == "fall" then
    Resolve(nil)
  end
end

local function TrySwap(a, c)
  if phase ~= "idle" or data.over then return end
  ClearHint()
  SetSelected(nil)
  swapA, swapB = a, c
  local ax, ay = CellXY(a)
  local bx, by = CellXY(c)
  MoveTo(pc[a], bx, by, 0.14)
  MoveTo(pc[c], ax, ay, 0.14)
  if ValidSwap(b, a, c) then
    phase = "swap"
    ns.Sound("place")
  else
    phase = "swapbad"
    ns.Sound("bad")
  end
end

local function Adjacent(a, c)
  local ra, ca = floor((a - 1) / N), (a - 1) % N
  local rc, cc = floor((c - 1) / N), (c - 1) % N
  return math.abs(ra - rc) + math.abs(ca - cc) == 1
end

local function Click(i)
  if phase ~= "idle" or data.over then return end
  ClearHint()
  if selected and Adjacent(selected, i) then
    TrySwap(selected, i)
  elseif selected == i then
    SetSelected(nil)
  else
    SetSelected(i)
    ns.Sound("click")
  end
end

-- Finish every animation at once (used when the window closes).
local function Settle()
  for _ = 1, 200 do
    if phase == "idle" or phase == "over" then break end
    for i = 1, N * N do
      local p = pc[i]
      if p then
        p.mv, p.pop = nil, nil
        if p.clr then p.clr = 1 end
        p.sc, p.al = p.clr and 0.2 or 1, p.clr and 0 or 1
        local x, y = CellXY(i)
        if not p.clr then p.x, p.y = x, y end
      end
    end
    Advance()
  end
  for i = 1, N * N do
    local p = pc[i]
    if p then
      p.x, p.y = CellXY(i)
      p.mv, p.pop, p.clr, p.sc, p.al = nil, nil, nil, 1, 1
      Draw(p)
    end
  end
end

-------------------------------------------------------------------------------
-- New games
-------------------------------------------------------------------------------

local function Started()
  return data.swaps > 0 and not data.over
end

local function NewGame(mode)
  if data.mode == "relaxed" and data.score > 0 and not data.over then
    ns.RecordResult("gems", { score = data.score, bestKey = "best_relaxed" })
  end
  Settle()
  data.mode = mode
  data.score, data.swaps, data.over = 0, 0, false
  data.moves = mode == "moves" and MOVES or 0
  data.board = FreshBoard()
  b = data.board
  phase, cascade, pending = "idle", 0, nil
  ClearHint()
  SetSelected(nil)
  overlay:Close()
  Rebuild()
  UpdateHud()
end

StaticPopupDialogs["DOWNTIME_NEW_GEMS"] = {
  text = "Start a new game? This one will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, d) NewGame(d or "relaxed") end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function AskNew(mode)
  if Started() then
    StaticPopup_Show("DOWNTIME_NEW_GEMS", nil, nil, mode)
  else
    NewGame(mode)
  end
end

local function ValidBoard(t)
  if type(t) ~= "table" or #t ~= N * N then return false end
  for i = 1, N * N do
    local v = t[i]
    if type(v) ~= "number" or v ~= floor(v) then return false end
    if not ((v >= 1 and v <= 6) or (v >= 11 and v <= 16) or v == 20) then return false end
  end
  return true
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function Create(parent, saved)
  panel = parent
  data = saved
  pc = {}

  scoreText = UI.Title(parent, 14)
  scoreText:SetPoint("TOPLEFT", 14, -2)
  bestText = UI.Text(parent, 12, C.dim)
  bestText:SetPoint("TOPRIGHT", -14, -4)

  local inset = UI.Inset(parent, SIZE + 6, SIZE + 6)
  inset:SetPoint("TOP", parent, "TOP", 0, -22)
  field = CreateFrame("Frame", nil, inset)
  field:SetSize(SIZE, SIZE)
  field:SetPoint("CENTER")
  field:SetClipsChildren(true)

  -- Gems live on their own frame so the clip above is sure to cut off gems
  -- that are still falling in from above the board.
  layer = CreateFrame("Frame", nil, field)
  layer:SetAllPoints()
  layer:SetFrameLevel(field:GetFrameLevel() + 1)

  for k = 1, N - 1 do
    local v = field:CreateTexture(nil, "BACKGROUND")
    v:SetColorTexture(0.55, 0.42, 0.22, 0.13)
    v:SetSize(1, SIZE)
    v:SetPoint("TOPLEFT", k * CELL, 0)
    local h = field:CreateTexture(nil, "BACKGROUND")
    h:SetColorTexture(0.55, 0.42, 0.22, 0.13)
    h:SetSize(SIZE, 1)
    h:SetPoint("TOPLEFT", 0, -k * CELL)
  end

  -- Selection ring.
  selRing = CreateFrame("Frame", nil, field)
  selRing:SetSize(CELL - 2, CELL - 2)
  selRing:SetFrameLevel(field:GetFrameLevel() + 3)
  UI.Border(selRing, C.gold, 2, "OVERLAY", 0.95)
  selRing:Hide()

  -- Sparks and floating score sit above the gems.
  local fx = CreateFrame("Frame", nil, field)
  fx:SetAllPoints()
  fx:SetFrameLevel(field:GetFrameLevel() + 6)
  for i = 1, 40 do
    local t = fx:CreateTexture(nil, "OVERLAY")
    t:SetTexture(SPARK_TEX)
    t:SetBlendMode("ADD")
    t:SetVertexColor(1, 0.78, 0.4)
    t:Hide()
    sparks[i] = { tex = t, on = false }
  end
  for i = 1, 6 do
    local fs = UI.Title(fx, 18, C.gold)
    fs:Hide()
    floats[i] = { fs = fs, on = false }
  end

  -- One button per cell: click, or press and release over a neighbor.
  for i = 1, N * N do
    local cell = CreateFrame("Button", nil, field)
    cell:SetSize(CELL, CELL)
    cell:SetFrameLevel(field:GetFrameLevel() + 2)
    local x, y = CellXY(i)
    cell:SetPoint("CENTER", field, "TOPLEFT", x, -y)
    cell:SetScript("OnMouseDown", function(_, button)
      if button == "RightButton" then return end
      if phase ~= "idle" or data.over then down = nil return end
      local cx, cy = GetCursorPosition()
      local s = field:GetEffectiveScale()
      down, downX, downY = i, cx / s, cy / s
    end)
    cell:SetScript("OnMouseUp", function(_, button)
      if button == "RightButton" or down ~= i then down = nil return end
      down = nil
      local cx, cy = GetCursorPosition()
      local s = field:GetEffectiveScale()
      local dx, dy = cx / s - downX, cy / s - downY
      if math.max(math.abs(dx), math.abs(dy)) < 14 then
        Click(i)
        return
      end
      local r, c = floor((i - 1) / N), (i - 1) % N
      if math.abs(dx) > math.abs(dy) then c = c + (dx > 0 and 1 or -1) else r = r + (dy > 0 and -1 or 1) end
      if r >= 0 and r < N and c >= 0 and c < N then TrySwap(i, r * N + c + 1) end
    end)
    cells[i] = cell
  end

  toast = UI.Toast(inset)
  overlay = UI.Overlay(inset)
  local again = UI.Button(overlay.buttons, "Play again", 110, 24)
  again:SetPoint("TOP", 0, 0)
  again:SetScript("OnClick", function() NewGame(data.mode) end)

  modeRow = UI.Choice(parent, MODES, 196, function(key)
    if key ~= data.mode then AskNew(key) end
  end)
  modeRow:SetPoint("TOP", inset, "BOTTOM", 0, -8)
  movesText = UI.Text(parent, 12, C.cream)
  movesText:SetPoint("TOP", modeRow, "BOTTOM", 0, -6)

  local newButton = UI.Button(parent, "New game", 110, 24)
  newButton:SetPoint("TOP", modeRow, "BOTTOM", 0, -24)
  newButton:SetScript("OnClick", function() AskNew(data.mode) end)

  local tip = UI.Text(parent, 10, C.dim)
  tip:SetPoint("TOP", newButton, "BOTTOM", 0, -10)
  tip:SetWidth(SIZE)
  tip:SetJustifyH("CENTER")
  tip:SetSpacing(3)
  tip:SetText("Four in a line makes an ember that clears its neighbors.\nFive makes a prism: swap it to clear one color.")

  -- Load or start.
  if data.mode ~= "relaxed" and data.mode ~= "moves" then data.mode = "relaxed" end
  if type(data.score) ~= "number" or data.score < 0 then data.score = 0 end
  if type(data.swaps) ~= "number" then data.swaps = 0 end
  if type(data.moves) ~= "number" or data.moves < 0 or data.moves > MOVES then
    data.moves = data.mode == "moves" and MOVES or 0
  end
  data.over = data.over == true and data.mode == "moves"
  if ValidBoard(data.board) then
    b = data.board
    if #FindRuns(b) > 0 or #AllMoves(b) == 0 then
      data.board = FreshBoard()
      b = data.board
    end
    Rebuild()
    UpdateHud()
    if data.over then
      phase = "over"
      overlay:Open("Out of moves", format("Score %s\nBest %s", ns.FormatNumber(data.score),
        ns.FormatNumber(data.stats.best_moves or data.score)))
    end
  else
    data.score, data.swaps, data.over = 0, 0, false
    data.moves = data.mode == "moves" and MOVES or 0
    data.board = FreshBoard()
    b = data.board
    Rebuild()
    UpdateHud()
  end

  -- Option changed: swap the art on every live piece.
  ns.OnPiecesChanged(function()
    for i = 1, N * N do
      local p = pc[i]
      if p then
        SetCode(p, p.code)
        Draw(p)
      end
    end
  end)

  -- Logging out does not fire OnHide: finish any cascade so the saved board is whole.
  local saver = CreateFrame("Frame")
  saver:RegisterEvent("PLAYER_LOGOUT")
  saver:SetScript("OnEvent", function()
    if not field then return end
    down = nil
    Settle()
    ClearHint()
    SetSelected(nil)
  end)

  parent:SetScript("OnUpdate", function(_, dt)
    if dt > 0.05 then dt = 0.05 end
    now = now + dt
    local busy = false
    for i = 1, N * N do
      local p = pc[i]
      if p then
        local active = p.mv or p.clr or p.pop
        if Step(p, dt) then busy = true end
        if active or p.code > 10 or p.pulse then Draw(p) end
      end
    end
    -- Sprites that already left the board (clearing) still finish their fade.
    UpdateEffects(dt)
    if selected then
      selRing:SetAlpha(0.65 + 0.35 * sin(now * 6))
    end
    if phase == "idle" then
      hintT = hintT + dt
      if hintT >= HINT_AFTER and not hint and not data.over then
        local moves = AllMoves(b)
        if #moves > 0 then
          local m = moves[random(#moves)]
          hint = { pc[m[1]], pc[m[2]] }
          hint[1].pulse, hint[2].pulse = true, true
        end
        hintT = 0
      end
    elseif not busy and phase ~= "over" then
      Advance()
    end
  end)
end

ns.RegisterGame({
  key = "gems",
  name = "Gemcutter",
  blurb = "Swap gems to line up three or more.",
  icon = ns.MEDIA .. "icons\\gems",
  order = 20,
  Create = Create,
  OnHide = function()
    if not field then return end
    down = nil
    Settle()
    ClearHint()
    SetSelected(nil)
  end,
  InProgress = function(d)
    if type(d) ~= "table" then return false end
    -- Relaxed never ends, so only a 30 Moves game counts as waiting.
    return d.mode == "moves" and type(d.swaps) == "number" and d.swaps > 0 and d.over ~= true
      and ValidBoard(d.board) and true or false
  end,
  Summary = function(d)
    local s = d.stats
    local best = s.best_moves or s.best_relaxed
    return best and ("Best " .. ns.FormatNumber(best)) or ""
  end,
})
