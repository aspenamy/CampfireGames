-------------------------------------------------------------------------------
-- Campfire Games: Tapestry
--
-- Weave the hidden pattern. The numbers beside each row and above each column
-- say how long the runs of woven cells are, in order, with at least one gap
-- between runs. Left-click a cell to weave it, right-click to mark it empty.
-- Hold the button and drag to paint a line of cells. Every picture is drawn by
-- hand, has exactly one answer, and can be solved by reasoning alone.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor = math.floor

local MAX_UNDO = 200
local MAX_N = 10
local CLUEW, CLUEH = 64, 64
local GRID = 220 -- pixels for the cells at every size
local TOP = 22

local SIZES = {
  { key = "5", label = "5x5" },
  { key = "8", label = "8x8" },
  { key = "10", label = "10x10" },
}

-- Cozy thread colors: base, highlight.
local PALETTES = {
  { { 0.55, 0.13, 0.19 }, { 0.80, 0.34, 0.36 } }, -- burgundy
  { { 0.17, 0.42, 0.23 }, { 0.42, 0.68, 0.45 } }, -- forest green
  { { 0.15, 0.29, 0.58 }, { 0.40, 0.55, 0.85 } }, -- deep blue
  { { 0.76, 0.48, 0.12 }, { 0.98, 0.76, 0.38 } }, -- amber
}

-- The finished picture is always woven in warm amber.
local WARM = 4

local COLOR = {
  line  = { 0.30, 0.22, 0.12 },
  cell  = { 0.12, 0.09, 0.065 },
  guide = { 0.75, 0.58, 0.28 },
}

local data
local game          -- data.game: n, sol, cells, pal, elapsed, solved
local undo = {}
local drag          -- { mode, changes }
local winAnim, winNewBest
local reveal = 1 -- 0 to 1: how far the solved picture has faded into its colors
local panel, grid, cellFrames, rowFs, colFs, timerText, sizeText, guideText
local overlay, sizeRow, undoButton, rowBg, colBg, guideV, guideH
local rowClue, colClue = {}, {}

-------------------------------------------------------------------------------
-- Clues and the line solver
-------------------------------------------------------------------------------

-- Lengths of the runs of 1s in a list of values.
local function Runs(vals, n)
  local out, run = {}, 0
  for k = 1, n do
    if vals[k] == 1 then
      run = run + 1
    elseif run > 0 then
      out[#out + 1] = run
      run = 0
    end
  end
  if run > 0 then out[#out + 1] = run end
  return out
end

local function SameRuns(a, b)
  if #a ~= #b then return false end
  for k = 1, #a do
    if a[k] ~= b[k] then return false end
  end
  return true
end

local function LineOf(cells, n, isRow, idx)
  local line = {}
  for k = 1, n do
    line[k] = isRow and cells[(idx - 1) * n + k] or cells[(k - 1) * n + idx]
  end
  return line
end

local function ClueSets(sol, n)
  local rows, cols = {}, {}
  for k = 1, n do
    rows[k] = Runs(LineOf(sol, n, true, k), n)
    cols[k] = Runs(LineOf(sol, n, false, k), n)
  end
  return rows, cols
end

-- Hand-drawn pictures. '.' is empty, any letter is a woven square. Each one has been
-- checked (tools/tapestry_check.py) to have exactly one solution from its clues.
-- Letters in the pictures are thread colors, shown when the picture is solved.
-- Any letter other than '.' is a woven square for the clues.
local PIC_COLORS = {
  r = { 0.74, 0.24, 0.22 }, -- red
  o = { 0.90, 0.52, 0.20 }, -- orange
  y = { 0.92, 0.74, 0.30 }, -- gold
  g = { 0.38, 0.62, 0.34 }, -- green
  d = { 0.22, 0.45, 0.28 }, -- dark green
  b = { 0.52, 0.34, 0.20 }, -- brown
  t = { 0.80, 0.64, 0.44 }, -- tan
  w = { 0.93, 0.88, 0.76 }, -- cream
  k = { 0.32, 0.30, 0.31 }, -- dark grey
  s = { 0.56, 0.64, 0.72 }, -- steel blue-grey
  u = { 0.30, 0.46, 0.74 }, -- blue
  p = { 0.88, 0.58, 0.62 }, -- pink
}

local PICS = {
  [5] = {
    { "Heart", "rr.rr", "rrrrr", "rrrrr", ".rrr.", "..r.." },
    { "House", "..r..", ".rrr.", "rrrrr", "tt.tt", "tt.tt" },
    { "Goblet", "yyyyy", "yyyyy", ".yyy.", "..y..", ".yyy." },
    { "Crown", "y.y.y", "yyyyy", "yy.yy", "yyryy", "yyyyy" },
    { "Moon", "..yyy", ".yy..", "yy...", ".yy..", "..yyy" },
    { "Tree", ".ggg.", "ggggg", "ggggg", "..b..", "..b.." },
    { "Bell", "..y..", ".yyy.", "yyyyy", "yyyyy", "..y.." },
    { "Skull", ".www.", "wwwww", "w.w.w", ".www.", ".w.w." },
    { "Cat", "o...o", "ooooo", "o.o.o", "ooooo", ".ooo." },
    { "Ghost", ".www.", "w.w.w", "wwwww", "wwwww", "w.w.w" },
    { "Mushroom", ".rrr.", "r.rrr", "rrrrr", ".www.", ".www." },
    { "Mug", "uuu..", "uuuuu", "uuu.u", "uuuuu", "uuu.." },
  },
  [8] = {
    { "Heart", ".rr..rr.", "rrrrrrrr", "rrrrrrrr", "rrrrrrrr", "rrrrrrrr", ".rrrrrr.", "..rrrr..", "...rr..." },
    { "House", "...rr...", "..rrrr..", ".rrrrrr.", "rrrrrrrr", ".tttttt.", ".tt..tt.", ".tt..tt.", ".tt..tt." },
    { "Key", ".yyyyyy.", "yy....yy", "yy....yy", ".yyyyyy.", "...yy...", "...yyy..", "...yy...", "...yyy.." },
    { "Shield", "uuuuuuuu", "uuu..uuu", "u......u", "uuu..uuu", "uuu..uuu", ".uuuuuu.", "..uuuu..", "...uu..." },
    { "Star", "...yy...", "...yy...", "yyyyyyyy", ".yyyyyy.", "..yyyy..", "..yyyy..", ".yy..yy.", "yy....yy" },
    { "Tree", "...gg...", "..gggg..", ".gggggg.", "..gggg..", ".gggggg.", "gggggggg", "...bb...", "...bb..." },
    { "Boot", ".bbbb...", ".bbbb...", ".bbbb...", ".bbbb...", ".bbbbb..", ".bbbbbb.", "bbbbbbbb", "kkkkkkkk" },
    { "Cat", "o......o", "oo....oo", "oooooooo", "o.oooo.o", "oooooooo", "ooo..ooo", ".oooooo.", "..oooo.." },
    { "Bell", "...yy...", "..yyyy..", "..yyyy..", ".yyyyyy.", ".yyyyyy.", "yyyyyyyy", "yyyyyyyy", "...kk..." },
    { "Candle", "...yy...", "..oooo..", "...kk...", "..wwww..", "..wwww..", "..wwww..", ".wwwwww.", "yyyyyyyy" },
    { "Skull", ".wwwwww.", "wwwwwwww", "ww.ww.ww", "ww.ww.ww", "wwwwwwww", ".wwwwww.", "..wwww..", "..w..w.." },
    { "Lantern", "..kkkk..", "..k..k..", ".kkkkkk.", "kyyyyyyk", "kyyyyyyk", "kyyyyyyk", ".kkkkkk.", "..kkkk.." },
    { "Ghost", "..wwww..", ".wwwwww.", "ww.ww.ww", "ww.ww.ww", "wwwwwwww", "www..www", "wwwwwwww", "ww.ww.ww" },
    { "Tower", "s.s..s.s", "ssssssss", ".ssssss.", ".ss..ss.", ".ss..ss.", ".ssssss.", ".ssssss.", "kkkkkkkk" },
    { "Fish", "...yyy..", "yy.ooooo", "yyoooooo", "yyoooo.o", "yyoooooo", "yy.ooooo", "...yyy..", "....y..." },
    { "Moon", "..yyyyyy", ".yyyy...", "yyyy....", "yyyy....", "yyyy....", "yyyy....", ".yyyy...", "..yyyyyy" },
  },
  [10] = {
    { "Boot", "..bbbbb...", "..bbbbb...", "..bbbbb...", "..bbbbb...", "..bbbbb...", "..bbbbbb..", "..bbbbbbb.", "..bbbbbbbb", "kkkkkkkkkk", "kkkkkkkkkk" },
    { "Heart", ".rrr..rrr.", "rrrrrrrrrr", "rrrrrrrrrr", "rrrrrrrrrr", "rrrrrrrrrr", "rrrrrrrrrr", ".rrrrrrrr.", "..rrrrrr..", "...rrrr...", "....rr...." },
    { "House", "....rr....", "...rrrr...", "..rrrrrr..", ".rrrrrrrr.", "rrrrrrrrrr", ".tttttttt.", ".tt.tt.tt.", ".tttttttt.", ".ttt..ttt.", ".ttt..ttt." },
    { "Castle", "s.s.ss.s.s", "ssssssssss", ".ssssssss.", ".ss.ss.ss.", ".ssssssss.", ".ssssssss.", ".sss..sss.", "ssss..ssss", "ssss..ssss", "ssss..ssss" },
    { "Pine Tree", "....dd....", "...dddd...", "..dddddd..", "...dddd...", "..dddddd..", ".dddddddd.", "..dddddd..", ".dddddddd.", "dddddddddd", "...bbbb..." },
    { "Sword", "....ws....", "...swss...", "...swss...", "...swss...", "...swss...", "...swss...", "yyyyyyyyyy", "....bb....", "....bb....", "...yyyy..." },
    { "Key", "..yyyyyy..", ".yyyyyyyy.", "yyy....yyy", "yyy....yyy", ".yyyyyyyy.", "..yyyyyy..", "....yy....", "....yyyy..", "....yy....", "....yyyy.." },
    { "Lantern", "...kkkk...", "...k..k...", "..kkkkkk..", ".yyyyyyyy.", "kyyyyyyyyk", "kyyyyyyyyk", "kyyyyyyyyk", "kyyyyyyyyk", "..kkkkkk..", "..kk..kk.." },
    { "Potion", "...bbbb...", "....ww....", "....ww....", "....ww....", "...rrrr...", "..rrrrrr..", ".rrrrrrrr.", "rrrrrrrrrr", "rrrrrrrrrr", ".rrrrrrrr." },
    { "Goblet", "yyyyyyyyyy", "yyyyyyyyyy", ".yyyyyyyy.", ".yyyyyyyy.", "..yyyyyy..", "...yyyy...", "....yy....", "....yy....", "...yyyy...", "..yyyyyy.." },
    { "Skull", "..wwwwww..", ".wwwwwwww.", "wwwwwwwwww", "ww..ww..ww", "ww..ww..ww", "wwwwwwwwww", ".www..www.", "..wwwwww..", "..w.ww.w..", "..w.ww.w.." },
    { "Campfire", "....oo....", "....oo....", "...oyyo...", "..ooyyoo..", "..ooyyoo..", ".oooyyooo.", ".oooyyooo.", "b.ooyyoo.b", "bb......bb", "bbbbbbbbbb" },
    { "Cat", "o.o....o.o", "oooooooooo", "oooooooooo", "oo.oooo.oo", "oooooooooo", "oooo..oooo", "oooooooooo", "oooooooooo", ".oooooooo.", "..oooooo.." },
    { "Bell", "....yy....", "...yyyy...", "..yyyyyy..", "..yyyyyy..", "..yyyyyy..", ".yyyyyyyy.", ".yyyyyyyy.", "yyyyyyyyyy", "yyyyyyyyyy", "...yyyy..." },
    { "Moon", "..yyyyyyy.", ".yyyy....y", "yyyy......", "yyyy......", "yyyy......", "yyyy......", "yyyy......", "yyyy......", ".yyyy....y", "..yyyyyyy." },
    { "Shield", "uuuuuuuuuu", "uuuuwwuuuu", "uwwwwwwwwu", "uwwwwwwwwu", "uuuuwwuuuu", ".uuuwwuuu.", ".uuuwwuuu.", "..uuwwuu..", "...uuuu...", "....uu...." },
  },
}

local function FindPic(n, name)
  for _, p in ipairs(PICS[n] or {}) do
    if p[1] == name then return p end
  end
end

local function PicSol(p, n)
  local sol = {}
  for r = 1, n do
    local row = p[r + 1]
    for c = 1, n do
      sol[(r - 1) * n + c] = row:sub(c, c) ~= "." and 1 or 0
    end
  end
  return sol
end

-- A random picture of this size that was not one of the last few played.
local function PickPic(n)
  local key = tostring(n)
  if type(data.recent) ~= "table" then data.recent = {} end
  local recent = data.recent[key]
  if type(recent) ~= "table" then
    recent = {}
    data.recent[key] = recent
  end
  local list = PICS[n]
  local pool = {}
  for _, p in ipairs(list) do
    local seen = false
    for _, name in ipairs(recent) do
      if name == p[1] then seen = true end
    end
    if not seen then pool[#pool + 1] = p end
  end
  if #pool == 0 then pool = list end
  local pick = pool[math.random(#pool)]
  recent[#recent + 1] = pick[1]
  while #recent > 4 do table.remove(recent, 1) end
  return pick
end

local function WithArticle(name)
  return (name:sub(1, 1):match("[AEIOU]") and "an " or "a ") .. name
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local function ValidGame(g)
  if type(g) ~= "table" then return false end
  local n = g.n
  if n ~= 5 and n ~= 8 and n ~= 10 then return false end
  if type(g.pal) ~= "number" or not PALETTES[g.pal] then return false end
  if g.elapsed ~= nil and type(g.elapsed) ~= "number" then return false end
  local pic = type(g.pic) == "string" and FindPic(n, g.pic)
  if not pic then return false end
  if type(g.sol) ~= "table" or #g.sol ~= n * n then return false end
  if type(g.cells) ~= "table" or #g.cells ~= n * n then return false end
  local want = PicSol(pic, n)
  for i = 1, n * n do
    if g.sol[i] ~= want[i] then return false end
    local v = g.cells[i]
    if v ~= 0 and v ~= 1 and v ~= 2 then return false end
  end
  return true
end

local function Started()
  for i = 1, game.n * game.n do
    if game.cells[i] ~= 0 then return true end
  end
  return false
end

local function IsSolved()
  for i = 1, game.n * game.n do
    if (game.cells[i] == 1) ~= (game.sol[i] == 1) then return false end
  end
  return true
end

local function CellSize(n) return floor(GRID / n) end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function UpdateTimer()
  if not game then timerText:SetText("") return end
  timerText:SetText(ns.FormatTime(game.elapsed))
end

local function RenderCell(r, c)
  local n = game.n
  local f = cellFrames[r][c]
  local v = game.cells[(r - 1) * n + c]
  f.thread:SetShown(v == 1)
  f.hi:SetShown(v == 1)
  f.shade:SetShown(v == 1)
  f.stripe:SetShown(v == 1)
  f.mark:SetShown(v == 2)
  f.bad:SetShown(v == 1 and data.showMistakes and game.sol[(r - 1) * n + c] ~= 1)
end

local function RenderClue(isRow, idx)
  local n = game.n
  local fs = isRow and rowFs[idx] or colFs[idx]
  local clue = isRow and rowClue[idx] or colClue[idx]
  local have = Runs(LineOf(game.cells, n, isRow, idx), n)
  if SameRuns(have, clue) then
    UI.SetTextColor(fs, C.green, 0.5)
  else
    UI.SetTextColor(fs, C.gold)
  end
end

-- One short line that says what to do or how it is going.
local function UpdateGuide()
  if not game then guideText:SetText("") return end
  local n = game.n
  if game.solved then
    guideText:SetText("You wove " .. WithArticle(game.pic) .. ". Every line matches.")
    return
  end
  local done = 0
  for k = 1, n do
    if SameRuns(Runs(LineOf(game.cells, n, true, k), n), rowClue[k]) then done = done + 1 end
    if SameRuns(Runs(LineOf(game.cells, n, false, k), n), colClue[k]) then done = done + 1 end
  end
  if done == 0 then
    guideText:SetText("Numbers show runs of woven squares in that line")
  elseif done >= 2 * n - 2 then
    guideText:SetText("Almost there, " .. done .. " of " .. 2 * n .. " lines done")
  else
    guideText:SetText("Nice, " .. done .. " of " .. 2 * n .. " lines done. Faded numbers are done.")
  end
end

-- Woven squares keep their thread color while solving. Once solved they fade to
-- the picture's colors (amber when a picture has no color letters).
local function ColorCells(t)
  local n = game.n
  local pal = PALETTES[game.pal]
  if not game.solved then t = 0 end
  local pic = FindPic(n, game.pic)
  local amber = PALETTES[WARM][1]
  for r = 1, n do
    local row = pic and pic[r + 1]
    for c = 1, n do
      local f = cellFrames[r][c]
      local base, hi = pal[1], pal[2]
      if t > 0 then
        local col = row and PIC_COLORS[row:sub(c, c)] or amber
        local k = 1 - t
        local tr, tg, tb = col[1], col[2], col[3]
        base = { base[1] * k + tr * t, base[2] * k + tg * t, base[3] * k + tb * t }
        local hr, hg, hb = tr * 0.7 + 0.3, tg * 0.7 + 0.3, tb * 0.7 + 0.3
        hi = { hi[1] * k + hr * t, hi[2] * k + hg * t, hi[3] * k + hb * t }
      end
      UI.Color(f.thread, base)
      f.hi:SetColorTexture(hi[1], hi[2], hi[3], 0.75)
    end
  end
end

local function Layout()
  local n = game.n
  local cs = CellSize(n)
  local side = cs * n + 1
  local left = floor((ns.GAME_W - (CLUEW + side)) / 2)
  grid:ClearAllPoints()
  grid:SetPoint("TOPLEFT", panel, "TOPLEFT", left + CLUEW, -(TOP + CLUEH))
  grid:SetSize(side, side)
  rowBg:ClearAllPoints()
  rowBg:SetPoint("TOPLEFT", panel, "TOPLEFT", left, -(TOP + CLUEH))
  rowBg:SetSize(CLUEW - 2, side)
  colBg:ClearAllPoints()
  colBg:SetPoint("TOPLEFT", panel, "TOPLEFT", left + CLUEW, -TOP)
  colBg:SetSize(side, CLUEH - 2)

  local fontSize = n == 10 and 10 or 11
  local dot = math.max(6, floor(cs * 0.3))
  for r = 1, MAX_N do
    for c = 1, MAX_N do
      local f = cellFrames[r][c]
      if r <= n and c <= n then
        f:SetSize(cs, cs)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", grid, "TOPLEFT", (c - 1) * cs, -(r - 1) * cs)
        f.mark:SetSize(dot, dot)
        f:Show()
      else
        f:Hide()
      end
    end
  end
  for k = 1, MAX_N do
    local rf, cf = rowFs[k], colFs[k]
    if k <= n then
      rf:SetFont(ns.FONT, fontSize, "")
      rf:ClearAllPoints()
      rf:SetPoint("RIGHT", grid, "TOPLEFT", -5, -((k - 0.5) * cs))
      rf:SetText(#rowClue[k] > 0 and table.concat(rowClue[k], " ") or "0")
      rf:Show()
      cf:SetFont(ns.FONT, fontSize, "")
      cf:ClearAllPoints()
      cf:SetPoint("BOTTOM", grid, "TOPLEFT", (k - 0.5) * cs, 4)
      cf:SetText(#colClue[k] > 0 and table.concat(colClue[k], "\n") or "0")
      cf:Show()
    else
      rf:Hide()
      cf:Hide()
    end
  end
  ColorCells(reveal)
  -- guide lines every five cells on the big board
  guideV:SetShown(n == 10)
  guideH:SetShown(n == 10)
  if n == 10 then
    guideV:ClearAllPoints()
    guideV:SetPoint("TOPLEFT", grid, "TOPLEFT", 5 * cs, 0)
    guideV:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", 5 * cs, 0)
    guideH:ClearAllPoints()
    guideH:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -5 * cs)
    guideH:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, -5 * cs)
  end
end

local function Render()
  if not game then
    grid:Hide()
    rowBg:Hide(); colBg:Hide()
    sizeText:SetText("")
    return
  end
  local n = game.n
  rowClue, colClue = ClueSets(game.sol, n)
  grid:Show()
  rowBg:Show(); colBg:Show()
  Layout()
  for r = 1, n do
    for c = 1, n do
      RenderCell(r, c)
    end
    RenderClue(true, r)
    RenderClue(false, r)
  end
  sizeText:SetText(string.format("%dx%d", n, n))
  sizeRow:Select(tostring(n))
  UpdateGuide()
  UpdateTimer()
end

local function ClearSheen()
  if not game then return end
  for r = 1, game.n do
    for c = 1, game.n do cellFrames[r][c].sheen:SetAlpha(0) end
  end
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function ShowWon()
  local n = game.n
  local best = data.stats["best_" .. n]
  overlay:Open("Woven!", string.format("You wove %s\n%dx%d in %s%s\nBest: %s", WithArticle(game.pic), n, n,
    ns.FormatTime(game.elapsed), winNewBest and "  (new best)" or "", best and ns.FormatTime(best) or "-"))
end

local function Win()
  game.solved = true
  for i = 1, game.n * game.n do
    if game.cells[i] == 2 then game.cells[i] = 0 end
  end
  winNewBest = ns.RecordResult("tapestry", {
    won = true, time = floor(game.elapsed), lowerIsBetter = true, bestKey = "best_" .. game.n,
  })
  ns.Sound("win")
  reveal = 0
  Render()
  winAnim = 0
end

local function EndDrag()
  if not drag then return end
  local d = drag
  drag = nil
  if #d.changes == 0 then return end
  undo[#undo + 1] = d.changes
  if #undo > MAX_UNDO then table.remove(undo, 1) end
  if game and not game.solved and IsSolved() then Win() end
end

local lastSound = 0

local function Apply(r, c)
  local n = game.n
  local i = (r - 1) * n + c
  local v, mode, new = game.cells[i], drag.mode, nil
  if mode == "fill" and v ~= 1 then
    new = 1
  elseif mode == "clear" and v == 1 then
    new = 0
  elseif mode == "mark" and v == 0 then
    new = 2
  elseif mode == "unmark" and v == 2 then
    new = 0
  end
  if not new then return end
  drag.changes[#drag.changes + 1] = { i, v }
  game.cells[i] = new
  RenderCell(r, c)
  RenderClue(true, r)
  RenderClue(false, c)
  UpdateGuide()
  local now = GetTime()
  if now - lastSound > 0.07 then
    lastSound = now
    ns.Sound("place")
  end
end

local function CanPlay()
  return game and not game.solved and not winAnim
end

local function StartDrag(r, c, button)
  if drag or not CanPlay() then return end
  local v = game.cells[(r - 1) * game.n + c]
  local mode
  if button == "RightButton" then
    mode = v == 2 and "unmark" or "mark"
  elseif button == "LeftButton" then
    mode = v == 1 and "clear" or "fill"
  else
    return
  end
  drag = { mode = mode, changes = {}, r = r, c = c }
  Apply(r, c)
end

-- The press stays with the first cell in WoW, so cells under the moving
-- cursor are found from its position instead of OnEnter. Cells skipped by a
-- quick move are filled along the straight line from the last one.
local function DragTo()
  local gl, gt = grid:GetLeft(), grid:GetTop()
  if not gl or not gt then return end
  local n = game.n
  local cs = CellSize(n)
  local x, y = GetCursorPosition()
  local s = grid:GetEffectiveScale()
  local c = floor((x / s - gl) / cs) + 1
  local r = floor((gt - y / s) / cs) + 1
  if r < 1 or r > n or c < 1 or c > n then return end
  local r0, c0 = drag.r, drag.c
  if r == r0 and c == c0 then return end
  local steps = math.max(math.abs(r - r0), math.abs(c - c0))
  for i = 1, steps do
    Apply(floor(r0 + (r - r0) * i / steps + 0.5), floor(c0 + (c - c0) * i / steps + 0.5))
  end
  drag.r, drag.c = r, c
end

local function Undo()
  if not CanPlay() or drag or #undo == 0 then return end
  local changes = table.remove(undo)
  for k = #changes, 1, -1 do
    game.cells[changes[k][1]] = changes[k][2]
  end
  Render()
end

-------------------------------------------------------------------------------
-- New puzzles
-------------------------------------------------------------------------------

local function NewGame(n)
  if not overlay then return end
  EndDrag()
  winAnim = nil
  ClearSheen()
  local pic = PickPic(n)
  local cells = {}
  for i = 1, n * n do cells[i] = 0 end
  game = {
    n = n, pic = pic[1], sol = PicSol(pic, n), cells = cells,
    pal = math.random(#PALETTES), elapsed = 0, solved = false,
  }
  data.game = game
  wipe(undo)
  overlay:Close()
  Render()
end

StaticPopupDialogs["DOWNTIME_NEW_TAPESTRY"] = {
  text = "Start a new %s tapestry? This one will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, d) NewGame(tonumber(d) or 5) end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function AskNewGame(n)
  if game and not game.solved and Started() then
    StaticPopup_Show("DOWNTIME_NEW_TAPESTRY", string.format("%dx%d", n, n), nil, tostring(n))
  else
    NewGame(n)
  end
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function Create(parent, saved)
  panel = parent
  data = saved
  if data.showMistakes == nil then data.showMistakes = false end
  if ValidGame(data.game) then
    game = data.game
    game.elapsed = game.elapsed or 0
    game.solved = game.solved and true or false
  else
    data.game = nil
  end

  local left = floor((ns.GAME_W - (CLUEW + GRID + 1)) / 2)

  sizeText = UI.Title(parent, 14)
  sizeText:SetPoint("TOPLEFT", left, -2)
  timerText = UI.Text(parent, 12, C.cream)
  timerText:SetPoint("TOPRIGHT", -left, -3)

  rowBg = parent:CreateTexture(nil, "BACKGROUND")
  UI.Color(rowBg, C.inset, 0.7)
  colBg = parent:CreateTexture(nil, "BACKGROUND")
  UI.Color(colBg, C.inset, 0.7)

  grid = CreateFrame("Frame", nil, parent)
  grid:SetSize(GRID + 1, GRID + 1)
  grid:SetPoint("TOPLEFT", left + CLUEW, -(TOP + CLUEH))
  local lines = grid:CreateTexture(nil, "BACKGROUND")
  lines:SetAllPoints()
  UI.Color(lines, COLOR.line)

  cellFrames = {}
  for r = 1, MAX_N do
    cellFrames[r] = {}
    for c = 1, MAX_N do
      local f = CreateFrame("Button", nil, grid)
      f:SetSize(22, 22)
      f.bg = f:CreateTexture(nil, "BACKGROUND")
      f.bg:SetPoint("TOPLEFT", 1, -1)
      f.bg:SetPoint("BOTTOMRIGHT", 0, 0)
      UI.Color(f.bg, COLOR.cell)
      f.thread = f:CreateTexture(nil, "BORDER")
      f.thread:SetPoint("TOPLEFT", 2, -2)
      f.thread:SetPoint("BOTTOMRIGHT", -1, 1)
      f.stripe = f:CreateTexture(nil, "ARTWORK")
      f.stripe:SetPoint("TOP", f.thread, "TOP", 0, 0)
      f.stripe:SetPoint("BOTTOM", f.thread, "BOTTOM", 0, 0)
      f.stripe:SetWidth(1)
      f.stripe:SetColorTexture(1, 1, 1, 0.08)
      f.hi = f:CreateTexture(nil, "ARTWORK")
      f.hi:SetPoint("TOPLEFT", f.thread, "TOPLEFT", 0, 0)
      f.hi:SetPoint("TOPRIGHT", f.thread, "TOPRIGHT", 0, 0)
      f.hi:SetHeight(1)
      f.shade = f:CreateTexture(nil, "ARTWORK")
      f.shade:SetPoint("BOTTOMLEFT", f.thread, "BOTTOMLEFT", 0, 0)
      f.shade:SetPoint("BOTTOMRIGHT", f.thread, "BOTTOMRIGHT", 0, 0)
      f.shade:SetHeight(2)
      f.shade:SetColorTexture(0, 0, 0, 0.3)
      f.mark = f:CreateTexture(nil, "ARTWORK")
      f.mark:SetTexture(ns.MEDIA .. "dot")
      f.mark:SetPoint("CENTER", 0, 0)
      f.mark:SetSize(6, 6)
      f.mark:SetVertexColor(C.dim[1], C.dim[2], C.dim[3], 0.4)
      f.bad = f:CreateTexture(nil, "OVERLAY")
      f.bad:SetPoint("TOPLEFT", f.thread, "TOPLEFT", 0, 0)
      f.bad:SetPoint("BOTTOMRIGHT", f.thread, "BOTTOMRIGHT", 0, 0)
      f.bad:SetColorTexture(1, 0.2, 0.15, 0.5)
      f.sheen = f:CreateTexture(nil, "OVERLAY")
      f.sheen:SetPoint("TOPLEFT", f.thread, "TOPLEFT", 0, 0)
      f.sheen:SetPoint("BOTTOMRIGHT", f.thread, "BOTTOMRIGHT", 0, 0)
      f.sheen:SetColorTexture(1, 0.9, 0.6, 1)
      f.sheen:SetBlendMode("ADD")
      f.sheen:SetAlpha(0)
      local hl = f:CreateTexture(nil, "HIGHLIGHT")
      hl:SetPoint("TOPLEFT", 1, -1)
      hl:SetPoint("BOTTOMRIGHT", 0, 0)
      hl:SetColorTexture(1, 0.85, 0.5, 0.12)
      f:SetScript("OnMouseDown", function(_, button) StartDrag(r, c, button) end)
      f:SetScript("OnMouseUp", function() EndDrag() end)
      cellFrames[r][c] = f
    end
  end

  -- guide lines on top of the cells
  local guides = CreateFrame("Frame", nil, grid)
  guides:SetAllPoints()
  guideV = guides:CreateTexture(nil, "OVERLAY")
  guideV:SetWidth(1)
  guideV:SetColorTexture(COLOR.guide[1], COLOR.guide[2], COLOR.guide[3], 0.55)
  guideH = guides:CreateTexture(nil, "OVERLAY")
  guideH:SetHeight(1)
  guideH:SetColorTexture(COLOR.guide[1], COLOR.guide[2], COLOR.guide[3], 0.55)

  rowFs, colFs = {}, {}
  for k = 1, MAX_N do
    rowFs[k] = UI.Text(parent, 11, C.gold)
    rowFs[k]:SetWidth(CLUEW - 6)
    rowFs[k]:SetJustifyH("RIGHT")
    colFs[k] = UI.Text(parent, 11, C.gold)
    colFs[k]:SetWidth(24)
    colFs[k]:SetJustifyH("CENTER")
  end

  overlay = UI.Overlay(grid)
  local again = UI.Button(overlay.buttons, "New puzzle", 100, 24)
  again:SetPoint("RIGHT", overlay.buttons, "CENTER", -3, 0)
  again:SetScript("OnClick", function() AskNewGame(game and game.n or 5) end)
  local admire = UI.Button(overlay.buttons, "See picture", 100, 24)
  admire:SetPoint("LEFT", overlay.buttons, "CENTER", 3, 0)
  admire:SetScript("OnClick", function() overlay:Close() end)

  -- controls
  guideText = UI.Text(parent, 11, C.cream)
  guideText:SetPoint("TOP", parent, "TOPLEFT", ns.GAME_W / 2, -(TOP + CLUEH + GRID + 8))
  guideText:SetWidth(ns.GAME_W - 16)
  guideText:SetJustifyH("CENTER")
  guideText:SetText("")

  local y = -(TOP + CLUEH + GRID + 30)
  undoButton = UI.Button(parent, "Undo", 96, 22)
  undoButton:SetPoint("TOPLEFT", left, y)
  undoButton:SetScript("OnClick", Undo)
  local newButton = UI.Button(parent, "New puzzle", 96, 22)
  newButton:SetPoint("LEFT", undoButton, "RIGHT", 4, 0)
  newButton:SetScript("OnClick", function()
    AskNewGame(game and game.n or 5)
  end)

  local newLabel = UI.Text(parent, 11, C.dim)
  newLabel:SetPoint("TOPLEFT", undoButton, "BOTTOMLEFT", 0, -10)
  newLabel:SetText("Size:")
  sizeRow = UI.Choice(parent, SIZES, CLUEW + GRID - 40, function(key)
    AskNewGame(tonumber(key))
  end)
  sizeRow:SetPoint("LEFT", newLabel, "LEFT", 40, 0)

  local mistakes = UI.Check(parent, "Show mistakes",
    function() return data.showMistakes end,
    function(v)
      data.showMistakes = v
      if game then
        for r = 1, game.n do
          for c = 1, game.n do RenderCell(r, c) end
        end
      end
    end)
  mistakes:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 0, -12)

  local hint = UI.Text(parent, 10, C.faint)
  hint:SetPoint("TOPLEFT", mistakes, "BOTTOMLEFT", 0, -8)
  hint:SetText("Click to weave, right-click to mark empty. Drag to paint.")

  -- the clock, the win glow, and letting go of a drag
  local acc = 0
  parent:SetScript("OnUpdate", function(_, dt)
    if drag then
      if not (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
        EndDrag()
      elseif game then
        DragTo()
      end
    end
    if winAnim then
      winAnim = winAnim + dt
      local n = game.n
      reveal = math.min(1, winAnim / 1.5)
      ColorCells(reveal)
      for r = 1, n do
        for c = 1, n do
          local s = math.sin((winAnim * 4 - (r + c) * 0.3) * 1.2)
          local a = (winAnim < 2.2 and s > 0 and game.cells[(r - 1) * n + c] == 1) and s * 0.3 or 0
          cellFrames[r][c].sheen:SetAlpha(a)
        end
      end
      if winAnim >= 2.2 then
        winAnim = nil
        reveal = 1
        ClearSheen()
        ShowWon()
      end
      return
    end
    if not game or game.solved then return end
    game.elapsed = game.elapsed + dt
    acc = acc + dt
    if acc >= 0.25 then
      acc = 0
      UpdateTimer()
    end
  end)

  if game then
    Render()
    if game.solved then
      for i = 1, game.n * game.n do
        if game.cells[i] == 2 then game.cells[i] = 0 end
      end
      Render()
      ShowWon()
    end
  else
    NewGame(5)
  end
end

local function OnHide()
  EndDrag()
  if winAnim then
    winAnim = nil
    ClearSheen()
    reveal = 1
    if game then
      ColorCells(1)
      ShowWon()
    end
  end
end

ns.RegisterGame({
  key = "tapestry",
  name = "Tapestry",
  blurb = "Weave the hidden pattern from the number clues.",
  icon = ns.MEDIA .. "icons\\tapestry",
  order = 90,
  hasWins = true,
  Create = Create,
  OnHide = OnHide,
  InProgress = function(d)
    local g = type(d) == "table" and d.game or nil
    if not ValidGame(g) or g.solved == true then return false end
    for i = 1, g.n * g.n do
      if g.cells[i] ~= 0 then return true end
    end
    return false
  end,
  Summary = function(d)
    local s = d.stats
    for _, n in ipairs({ 10, 8, 5 }) do
      if s["best_" .. n] then
        return string.format("%dx%d best %s", n, n, ns.FormatTime(s["best_" .. n]))
      end
    end
    return ""
  end,
})
