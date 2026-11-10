-------------------------------------------------------------------------------
-- Campfire Games: Sliding Puzzle
--
-- A picture is cut into tiles with one gap. Click a tile next to the gap to
-- slide it in; click a tile further along the same row or column and the
-- whole run slides. Put the picture back together. The small picture in the
-- corner shows the goal, and Peek shows it over the board. Numbers adds a
-- small number to each tile. Every tile moved counts as a move; the clock
-- starts at your first move. New puzzle picks a different picture.
--
-- Puzzles are shuffled by sliding from the solved picture, so each one can
-- be solved. Best moves (and best time) are kept for each size.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, ceil, random, min, max, abs = math.floor, math.ceil, math.random, math.min, math.max, math.abs

local PICS = { "Campfire", "Moonlit Lake", "Mountain Inn", "Lighthouse", "Autumn Road", "Snowy Cabin" }
local SIZES = { { key = 3, label = "3x3" }, { key = 4, label = "4x4" } }

local BOARD = 284                       -- outer square
local INNER = BOARD - 6                 -- room for the tiles
local GAP = 2                           -- space between tiles
local MAX = 16                          -- tile pieces (4x4, including the last one)
local BOARD_X, BOARD_Y = floor((ns.GAME_W - BOARD) / 2), -60
local FILL_T, FULL_T, END_T = 0.35, 0.8, 1.9  -- finish: last tile, whole picture, overlay

local data, game
local panel, board, fullFrame, full, preview
local movesText, timeText, bestText, nameText, peekBtn, sizeRow, overlay
local pieces = {}
local cell, pad
local laidN, laidPic
local peek = false
local finishing                         -- { t = seconds } while the finish plays
local pending                           -- size waiting on the new-puzzle confirm
local shownSecs

-------------------------------------------------------------------------------
-- Puzzle logic
-------------------------------------------------------------------------------

local function IsInt(v, lo, hi)
  return type(v) == "number" and v == floor(v) and v >= lo and v <= hi
end

-------------------------------------------------------------------------------
-- Pictures: the painted scenes we ship, plus WoW's own zone maps. Any zone
-- map the client has works: its art comes as a grid of tiles, which Paint()
-- stitches together and crops to a square.
-------------------------------------------------------------------------------

local sources, sourceList

local function PicPath(i)
  return ns.MEDIA .. "slider\\pic" .. i
end

local function ScanMaps(list)
  if not (C_Map and C_Map.GetMapInfo and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return end
  local zone = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
  local seen = {}
  for id = 1, 3000 do
    local info = C_Map.GetMapInfo(id)
    if info and info.mapType == zone and type(info.name) == "string" and info.name ~= "" and not seen[info.name] then
      local layers = C_Map.GetMapArtLayers(id)
      local L = layers and layers[1]
      if L and (L.layerWidth or 0) >= 900 and (L.layerHeight or 0) >= 600
          and (L.tileWidth or 0) > 0 and (L.tileHeight or 0) > 0 then
        local cols, rows = ceil(L.layerWidth / L.tileWidth), ceil(L.layerHeight / L.tileHeight)
        local files = C_Map.GetMapArtLayerTextures(id, 1)
        if type(files) == "table" and #files >= cols * rows then
          seen[info.name] = true
          list[#list + 1] = {
            key = "m" .. id, name = info.name, w = L.layerWidth, h = L.layerHeight,
            tw = L.tileWidth, th = L.tileHeight, cols = cols, rows = rows, files = files,
          }
        end
      end
    end
  end
end

local function BuildSources()
  sources, sourceList = {}, {}
  ScanMaps(sourceList)
  -- The painted scenes are only a fallback for clients without zone map art.
  if #sourceList == 0 then
    for i, name in ipairs(PICS) do
      sourceList[#sourceList + 1] = { key = "s" .. i, name = name, path = PicPath(i) }
    end
  end
  for _, src in ipairs(sourceList) do sources[src.key] = src end
end

-- Old saves used a number for the picture.
local function PicKey(v)
  if not sources then BuildSources() end
  if type(v) == "number" then v = "s" .. v end
  if type(v) == "string" and sources[v] then return v end
end

-- Fill a frame (w x h) with part of a picture: u and v run 0 to 1 across it.
local function Paint(holder, key, w, h, u0, u1, v0, v1)
  local src = sources[key] or sourceList[1]
  holder.pool = holder.pool or {}
  local pool, used = holder.pool, 0
  local function Tex()
    used = used + 1
    local t = pool[used]
    if not t then
      t = holder:CreateTexture(nil, "ARTWORK")
      pool[used] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
  end
  if src.path then
    local t = Tex()
    t:SetTexture(src.path)
    t:SetTexCoord(u0, u1, v0, v1)
    t:SetAllPoints(holder)
  else
    local side = min(src.w, src.h)
    local ox, oy = (src.w - side) / 2, (src.h - side) / 2
    local x0, x1 = ox + u0 * side, ox + u1 * side
    local y0, y1 = oy + v0 * side, oy + v1 * side
    local sx, sy = w / (x1 - x0), h / (y1 - y0)
    for r = 0, src.rows - 1 do
      for c = 0, src.cols - 1 do
        local tx, ty = c * src.tw, r * src.th
        local ax, bx = max(x0, tx), min(x1, tx + src.tw)
        local ay, by = max(y0, ty), min(y1, ty + src.th)
        if bx > ax and by > ay then
          local t = Tex()
          t:SetTexture(src.files[r * src.cols + c + 1])
          t:SetTexCoord((ax - tx) / src.tw, (bx - tx) / src.tw, (ay - ty) / src.th, (by - ty) / src.th)
          -- a hair of overlap on inside edges so no seams show between tiles
          local ew = (bx < x1) and 0.6 or 0
          local eh = (by < y1) and 0.6 or 0
          t:SetPoint("TOPLEFT", holder, "TOPLEFT", (ax - x0) * sx, -(ay - y0) * sy)
          t:SetSize((bx - ax) * sx + ew, (by - ay) * sy + eh)
        end
      end
    end
  end
  for i = used + 1, #pool do pool[i]:Hide() end
end

local function IsSolved(t, n)
  for i = 1, n * n - 1 do
    if t[i] ~= i then return false end
  end
  return t[n * n] == 0
end

-- Half of all arrangements can never be solved; saved data is checked for it.
local function Solvable(t, n)
  local total, inv, gapRow = n * n, 0, 0
  for i = 1, total do
    local a = t[i]
    if a == 0 then
      gapRow = floor((i - 1) / n)
    else
      for j = i + 1, total do
        local b = t[j]
        if b ~= 0 and a > b then inv = inv + 1 end
      end
    end
  end
  if n % 2 == 1 then return inv % 2 == 0 end
  return (inv + gapRow) % 2 == 1
end

local function ValidGame(g)
  if type(g) ~= "table" then return false end
  local n = g.size
  if n ~= 3 and n ~= 4 then return false end
  g.pic = PicKey(g.pic)
  if not g.pic then return false end
  local total = n * n
  if type(g.tiles) ~= "table" or #g.tiles ~= total then return false end
  local seen = {}
  for i = 1, total do
    local v = g.tiles[i]
    if not IsInt(v, 0, total - 1) or seen[v] then return false end
    seen[v] = true
  end
  if not Solvable(g.tiles, n) then return false end
  if not IsInt(g.moves, 0, 1000000) then return false end
  if type(g.elapsed) ~= "number" or g.elapsed ~= g.elapsed or g.elapsed < 0 or g.elapsed > 10000000 then return false end
  if (g.solved == true) ~= IsSolved(g.tiles, n) then return false end
  return true
end

-- Slides from the solved picture with random legal moves (never straight
-- back), until it is well mixed and not solved.
local function Shuffled(n)
  local total = n * n
  local t = {}
  for i = 1, total - 1 do t[i] = i end
  t[total] = 0
  local gap, prev = total, nil
  local function Step()
    local r, c = floor((gap - 1) / n), (gap - 1) % n
    local opts = {}
    if r > 0 then opts[#opts + 1] = gap - n end
    if r < n - 1 then opts[#opts + 1] = gap + n end
    if c > 0 then opts[#opts + 1] = gap - 1 end
    if c < n - 1 then opts[#opts + 1] = gap + 1 end
    local pool = {}
    for _, o in ipairs(opts) do
      if o ~= prev then pool[#pool + 1] = o end
    end
    local to = pool[random(#pool)]
    t[gap], t[to] = t[to], 0
    prev, gap = gap, to
  end
  for _ = 1, n == 3 and 60 or 120 do Step() end
  for _ = 1, 400 do
    local off = 0
    for i = 1, total - 1 do
      if t[i] ~= i then off = off + 1 end
    end
    if off >= total - 3 and not IsSolved(t, n) then break end
    Step()
  end
  return t
end

local function NewGame(n)
  local pics = {}
  for _, src in ipairs(sourceList) do
    if src.key ~= data.lastPic then pics[#pics + 1] = src.key end
  end
  local pic = pics[random(#pics)]
  data.lastPic = pic
  data.size = n
  game = { size = n, pic = pic, tiles = Shuffled(n), moves = 0, elapsed = 0, solved = false }
  data.game = game
end

local function LoadSaved()
  if type(data.numbers) ~= "boolean" then data.numbers = false end
  data.lastPic = PicKey(data.lastPic)
  for _, s in ipairs(SIZES) do
    local k = "time_" .. s.key
    local v = data[k]
    if type(v) ~= "number" or v ~= v or v < 0 then data[k] = nil end
  end
  if type(data.game) == "table" and data.game.solved == nil then data.game.solved = false end
  if ValidGame(data.game) then
    game = data.game
    data.size = game.size
  else
    NewGame((data.size == 4) and 4 or 3)
  end
end

local function PosOf(v)
  for i = 1, game.size * game.size do
    if game.tiles[i] == v then return i end
  end
end

local function InProgress()
  return game and not game.solved and game.moves > 0
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function CellXY(pos)
  local n = game.size
  local r, c = floor((pos - 1) / n), (pos - 1) % n
  return pad + c * (cell + GAP), pad + r * (cell + GAP)
end

local function Place(pc)
  pc.b:ClearAllPoints()
  pc.b:SetPoint("TOPLEFT", board, "TOPLEFT", pc.x, -pc.y)
end

-- Sizes, picture and tile art for the current size and picture.
local function ApplyPicture()
  local n = game.size
  cell = floor((INNER - (n - 1) * GAP) / n)
  local total = n * cell + (n - 1) * GAP
  pad = floor((BOARD - total) / 2)
  fullFrame:ClearAllPoints()
  fullFrame:SetPoint("TOPLEFT", board, "TOPLEFT", pad, -pad)
  fullFrame:SetSize(total, total)
  Paint(full, game.pic, total, total, 0, 1, 0, 1)
  Paint(preview, game.pic, 52, 52, 0, 1, 0, 1)
  for p = 1, MAX do
    local pc = pieces[p]
    if p <= n * n then
      local r, c = floor((p - 1) / n), (p - 1) % n
      pc.b:SetSize(cell, cell)
      Paint(pc.art, game.pic, cell, cell, c / n, (c + 1) / n, r / n, (r + 1) / n)
      pc.num:SetText(p)
      pc.snap = true
    else
      pc.b:Hide()
      pc.on = false
    end
  end
  laidN, laidPic = n, game.pic
end

local function BestLine(n)
  local s = data.stats or {}
  local mv, tm = s["best_" .. n], data["time_" .. n]
  if type(mv) ~= "number" then return format("Best %dx%d: none yet", n, n) end
  local line = format("Best %dx%d: %d %s", n, n, mv, mv == 1 and "move" or "moves")
  if type(tm) == "number" then line = line .. ", " .. ns.FormatTime(tm) end
  return line
end

local function Render()
  if not game or not board then return end
  if laidN ~= game.size or laidPic ~= game.pic then ApplyPicture() end
  local n = game.size
  local solved = game.solved
  local where = {}
  for i = 1, n * n do
    local v = game.tiles[i]
    if v ~= 0 then where[v] = i end
  end
  local showNum = data.numbers and not solved
  for p = 1, n * n do
    local pc = pieces[p]
    local pos = where[p]
    if p == n * n then pos = n * n end     -- the last tile, only shown once solved
    local visible = pos ~= nil and (p < n * n or solved)
    if visible then
      local x, y = CellXY(pos)
      pc.tx, pc.ty = x, y
      if pc.snap or not pc.on then
        pc.x, pc.y = x, y
        Place(pc)
      end
      pc.snap = false
      pc.on = true
      pc.b:Show()
      if not finishing then pc.b:SetAlpha(1) end
    else
      pc.b:Hide()
      pc.on = false
    end
    pc.num:SetShown(showNum and visible)
    pc.numBg:SetShown(showNum and visible)
  end
  movesText:SetText("Moves " .. game.moves)
  shownSecs = floor(game.elapsed)
  timeText:SetText("Time " .. ns.FormatTime(game.elapsed))
  bestText:SetText(BestLine(n))
  nameText:SetText((sources[game.pic] or sourceList[1]).name)
  sizeRow:Select(n)
  peekBtn:SetText(peek and "Hide" or "Peek")
  if solved then peekBtn:Disable() else peekBtn:Enable() end
  if not finishing then
    fullFrame:SetShown(peek or solved)
    full:SetAlpha(1)
  end
end

local function ShowSolved()
  local n = game.size
  local line = format("%d %s in %s", game.moves, game.moves == 1 and "move" or "moves", ns.FormatTime(game.elapsed))
  line = line .. "\n" .. BestLine(n)
  overlay:Open(game.newBest and "A new best!" or "Picture complete!", line)
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function Win()
  local n = game.size
  game.solved = true
  peek = false
  local better = ns.RecordResult("slider", {
    won = true, score = game.moves, lowerIsBetter = true, bestKey = "best_" .. n,
  })
  local k = "time_" .. n
  local old = data[k]
  if type(old) ~= "number" or game.elapsed < old then
    data[k] = game.elapsed
    if old then better = true end
  end
  game.newBest = better and true or false
  ns.PlayTone("chime")
  finishing = { t = 0 }
  pieces[n * n].b:SetAlpha(0)
  fullFrame:Hide()
  Render()
end

local function Click(pos)
  if not game or game.solved or finishing then return end
  local n = game.size
  local gap
  for i = 1, n * n do
    if game.tiles[i] == 0 then gap = i break end
  end
  if pos == gap then return end
  local gr, gc = floor((gap - 1) / n), (gap - 1) % n
  local r, c = floor((pos - 1) / n), (pos - 1) % n
  local step
  if r == gr then
    step = (c > gc) and 1 or -1
  elseif c == gc then
    step = (r > gr) and n or -n
  else
    return
  end
  if peek then peek = false end
  local count = 0
  local at = gap
  while at ~= pos do
    local nxt = at + step
    game.tiles[at] = game.tiles[nxt]
    at = nxt
    count = count + 1
  end
  game.tiles[pos] = 0
  game.moves = game.moves + count
  ns.Sound("place")
  if IsSolved(game.tiles, n) then
    Win()
    return
  end
  Render()
end

local function NewPuzzle(n)
  NewGame(n)
  peek = false
  finishing = nil
  laidN = nil
  overlay:Close()
  Render()
end

StaticPopupDialogs["DOWNTIME_SLIDER_NEW"] = {
  text = "Start a new puzzle? Your moves on this one will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function() NewPuzzle(pending or (game and game.size) or 3) end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function Ask(n)
  pending = n
  if InProgress() then
    StaticPopup_Show("DOWNTIME_SLIDER_NEW")
  else
    NewPuzzle(n)
  end
end

local function Finish(t)
  local n = game.size
  local a = min(1, t / FILL_T)
  pieces[n * n].b:SetAlpha(a)
  local f = (t - FILL_T) / (FULL_T - FILL_T)
  if f > 0 then
    fullFrame:Show()
    full:SetAlpha(min(1, f))
  end
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function BuildPiece(p)
  local b = CreateFrame("Button", nil, board)
  b:SetSize(68, 68)
  b:RegisterForClicks("LeftButtonUp")
  local pc = { b = b, on = false, snap = true }
  pc.art = CreateFrame("Frame", nil, b)
  pc.art:SetAllPoints()
  UI.Border(b, { 0.04, 0.025, 0.015 }, 1, "OVERLAY", 0.9)
  pc.numBg = b:CreateTexture(nil, "OVERLAY", nil, 1)
  pc.numBg:SetSize(18, 15)
  pc.numBg:SetPoint("TOPLEFT", 3, -3)
  pc.numBg:SetColorTexture(0.03, 0.02, 0.01, 0.7)
  pc.num = UI.Text(b, 11, C.cream, nil, "OVERLAY")
  pc.num:SetPoint("CENTER", pc.numBg, "CENTER", 0, 0)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.85, 0.5, 0.14)
  b:SetScript("OnClick", function()
    local pos = PosOf(p)
    if pos then Click(pos) end
  end)
  b:Hide()
  return pc
end

local function Create(parent, saved)
  panel = parent
  data = saved
  if not sources then BuildSources() end
  LoadSaved()

  -- Goal picture and the numbers beside it.
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(54, 54)
  frame:SetPoint("TOPLEFT", BOARD_X, -2)
  UI.Border(frame, C.line, 1, "OVERLAY")
  preview = CreateFrame("Frame", nil, frame)
  preview:SetPoint("TOPLEFT", 1, -1)
  preview:SetPoint("BOTTOMRIGHT", -1, 1)

  movesText = UI.Text(parent, 13, C.cream)
  movesText:SetPoint("TOPLEFT", BOARD_X + 66, -6)
  timeText = UI.Text(parent, 13, C.cream)
  timeText:SetPoint("TOPLEFT", BOARD_X + 66, -24)
  bestText = UI.Text(parent, 11, C.dim)
  bestText:SetPoint("TOPLEFT", BOARD_X + 66, -42)
  nameText = UI.Title(parent, 14)
  nameText:SetPoint("TOPRIGHT", -BOARD_X, -6)

  board = UI.Inset(parent, BOARD, BOARD)
  board:SetPoint("TOPLEFT", BOARD_X, BOARD_Y)

  for p = 1, MAX do pieces[p] = BuildPiece(p) end

  -- The whole picture, above the tiles, for Peek and the finish.
  fullFrame = CreateFrame("Frame", nil, board)
  fullFrame:SetFrameLevel(board:GetFrameLevel() + 10)
  fullFrame:SetSize(INNER, INNER)
  fullFrame:SetPoint("TOPLEFT", 3, -3)
  full = CreateFrame("Frame", nil, fullFrame)
  full:SetAllPoints()
  UI.Border(fullFrame, { 0.04, 0.025, 0.015 }, 1, "OVERLAY", 0.9)
  fullFrame:Hide()

  local newBtn = UI.Button(parent, "New puzzle", 138, 22)
  newBtn:SetPoint("TOPLEFT", board, "BOTTOMLEFT", 0, -10)
  newBtn:SetScript("OnClick", function() Ask(game.size) end)

  peekBtn = UI.Button(parent, "Peek", 138, 22)
  peekBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)
  peekBtn:SetScript("OnClick", function()
    if game.solved or finishing then return end
    peek = not peek
    Render()
  end)

  sizeRow = UI.Choice(parent, SIZES, 138, function(n)
    if n ~= game.size then Ask(n) end
  end)
  sizeRow:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 0, -10)

  local numbers = UI.Check(parent, "Numbers", function() return data.numbers end, function(v)
    data.numbers = v and true or false
    Render()
  end)
  numbers:SetPoint("LEFT", sizeRow, "RIGHT", 22, 0)

  overlay = UI.Overlay(parent)
  local again = UI.Button(overlay.buttons, "New puzzle", 120, 24)
  again:SetPoint("CENTER", overlay.buttons, "CENTER", 0, 0)
  again:SetScript("OnClick", function() NewPuzzle(game.size) end)

  parent:SetScript("OnUpdate", function(_, dt)
    if not game then return end
    local k = min(1, dt * 22)
    for p = 1, MAX do
      local pc = pieces[p]
      if pc.on and (pc.x ~= pc.tx or pc.y ~= pc.ty) then
        local dx, dy = pc.tx - pc.x, pc.ty - pc.y
        if abs(dx) < 0.6 and abs(dy) < 0.6 then
          pc.x, pc.y = pc.tx, pc.ty
        else
          pc.x, pc.y = pc.x + dx * k, pc.y + dy * k
        end
        Place(pc)
      end
    end
    if finishing then
      finishing.t = finishing.t + dt
      Finish(finishing.t)
      if finishing.t >= END_T then
        finishing = nil
        Render()
        ShowSolved()
      end
    elseif not game.solved and game.moves > 0 then
      game.elapsed = game.elapsed + dt
      local s = floor(game.elapsed)
      if s ~= shownSecs then
        shownSecs = s
        timeText:SetText("Time " .. ns.FormatTime(game.elapsed))
      end
    end
  end)

  Render()
  if game.solved then ShowSolved() end
end

ns.RegisterGame({
  key = "slider",
  name = "Sliding Puzzle",
  blurb = "Slide the tiles back into a picture.",
  icon = ns.MEDIA .. "icons\\slider",
  order = 50,
  hasWins = true,
  Create = Create,
  OnShow = function()
    if game and game.solved and not finishing then ShowSolved() end
  end,
  OnHide = function()
    if peek then peek = false end
    if finishing then
      finishing = nil
      Finish(FULL_T + 1)
    end
    if game and board then Render() end
  end,
  InProgress = function(d)
    if type(d) ~= "table" or type(d.game) ~= "table" then return false end
    local g = d.game
    if g.solved == nil then g.solved = false end
    return ValidGame(g) and g.solved ~= true and g.moves > 0
  end,
  Summary = function(d)
    local s = d.stats or {}
    local parts = {}
    for _, n in ipairs({ 3, 4 }) do
      local v = s["best_" .. n]
      if type(v) == "number" then parts[#parts + 1] = { n = n, v = v } end
    end
    if #parts == 0 then return "" end
    if #parts == 1 then
      return format("Best %dx%d: %d %s", parts[1].n, parts[1].n, parts[1].v, parts[1].v == 1 and "move" or "moves")
    end
    return format("Best 3x3: %d, 4x4: %d", parts[1].v, parts[2].v)
  end,
})
