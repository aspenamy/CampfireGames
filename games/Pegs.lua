-------------------------------------------------------------------------------
-- Campfire Games: Pegs
--
-- Peg solitaire on a wooden board. Click a peg to pick it up, then click a
-- glowing hole to jump over a neighbor into it; the peg you jumped is removed.
-- Click another peg to switch, or empty space to let go. The game ends when
-- no jumps are left: one peg is a perfect game. Undo has no limit.
--
-- Cross: the 33 hole board, center empty. Triangle: 15 holes, top empty.
-- Each board keeps its own game in progress.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local sin = math.sin

local BOARD = 288
local MAX_UNDO = 100
local POOL = 33
local DOT = ns.MEDIA .. "dot"
local DISC = ns.MEDIA .. "chimes\\plate" -- a crisp round disc, tinted here

local KINDS = {
  { key = "cross", label = "Cross" },
  { key = "triangle", label = "Triangle" },
}
local NAMES = { cross = "Cross", triangle = "Triangle" }

-- Triangle board shape.
local TRI_TOP, TRI_H, TRI_ROW, TRI_SX = 21, 246, 46, 52

-------------------------------------------------------------------------------
-- Board layouts and jumps
-------------------------------------------------------------------------------

local LAYOUT = {}

local function MakeLayout(kind)
  local L = { pos = {}, at = {}, rc = {}, moves = {} }
  local dirs = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }
  if kind == "cross" then
    for r = 1, 7 do
      for c = 1, 7 do
        if (r >= 3 and r <= 5) or (c >= 3 and c <= 5) then
          local i = #L.pos + 1
          L.pos[i] = { x = (c - 4) * 40, y = 144 + (r - 4) * 40 }
          L.at[r * 10 + c] = i
          L.rc[i] = { r, c }
        end
      end
    end
    L.empty = L.at[44]
    L.center = L.empty
  else
    dirs[5], dirs[6] = { 1, 1 }, { -1, -1 }
    for r = 1, 5 do
      for c = 1, r do
        local i = #L.pos + 1
        L.pos[i] = { x = (c - (r + 1) / 2) * TRI_SX, y = TRI_TOP + 32 + (r - 1) * TRI_ROW }
        L.at[r * 10 + c] = i
        L.rc[i] = { r, c }
      end
    end
    L.empty = 1
  end
  L.n = #L.pos
  for i = 1, L.n do
    local r, c = L.rc[i][1], L.rc[i][2]
    local list = {}
    for _, d in ipairs(dirs) do
      local o = L.at[(r + d[1]) * 10 + c + d[2]]
      local t = L.at[(r + 2 * d[1]) * 10 + c + 2 * d[2]]
      if o and t then list[#list + 1] = { o = o, t = t } end
    end
    L.moves[i] = list
  end
  return L
end

LAYOUT.cross = MakeLayout("cross")
LAYOUT.triangle = MakeLayout("triangle")

-------------------------------------------------------------------------------
-- State
--
-- saved: data.board, data.saves[kind] = { pegs = {0/1...}, undo = { {f,o,t}... },
-- over = bool }, data.best[kind] = fewest pegs left
-------------------------------------------------------------------------------

local data
local kind, L, cur
local selected
local fade = {}
local fading = false
local pulse = 0
local panel, board, holes, overlay, toast, countText, nameText, undoButton, kindRow
local backdrop = { cross = {}, triangle = {} }

local function IsInt(v, lo, hi)
  return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

local function Fresh(k)
  local lay = LAYOUT[k]
  local pegs = {}
  for i = 1, lay.n do pegs[i] = (i == lay.empty) and 0 or 1 end
  return { pegs = pegs, undo = {}, over = false }
end

local function Count()
  local n = 0
  for i = 1, L.n do n = n + cur.pegs[i] end
  return n
end

local function HasMoves()
  local pegs = cur.pegs
  for i = 1, L.n do
    if pegs[i] == 1 then
      for _, m in ipairs(L.moves[i]) do
        if pegs[m.o] == 1 and pegs[m.t] == 0 then return true end
      end
    end
  end
  return false
end

local function ValidSave(s, k)
  local n = LAYOUT[k].n
  if type(s) ~= "table" or type(s.pegs) ~= "table" or #s.pegs ~= n then return false end
  local sum = 0
  for i = 1, n do
    local v = s.pegs[i]
    if v ~= 0 and v ~= 1 then return false end
    sum = sum + v
  end
  if sum < 1 then return false end
  if type(s.over) ~= "boolean" then s.over = false end
  local undo = {}
  if type(s.undo) == "table" then
    for _, u in ipairs(s.undo) do
      if type(u) == "table" and IsInt(u.f, 1, n) and IsInt(u.o, 1, n) and IsInt(u.t, 1, n) then
        undo[#undo + 1] = { f = u.f, o = u.o, t = u.t }
      else
        undo = {}
        break
      end
    end
  end
  while #undo > MAX_UNDO do table.remove(undo, 1) end
  s.undo = undo
  return true
end

local function LoadKind(k)
  kind, L = k, LAYOUT[k]
  data.board = k
  if not ValidSave(data.saves[k], k) then data.saves[k] = Fresh(k) end
  cur = data.saves[k]
  selected = nil
  for i = 1, POOL do fade[i] = 0 end
  fading = false
  if not cur.over and not HasMoves() then cur.over = true end
end

local function Plural(n)
  return n == 1 and "1 peg" or (n .. " pegs")
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function PegAlpha(b, a)
  b.shadow:SetAlpha(0.55 * a)
  b.base:SetAlpha(a)
  b.body:SetAlpha(a)
  b.shine:SetAlpha(0.85 * a)
end

local function Render()
  if not holes then return end
  local legal = {}
  if selected and not cur.over then
    for _, m in ipairs(L.moves[selected]) do
      if cur.pegs[m.o] == 1 and cur.pegs[m.t] == 0 then legal[m.t] = m.o end
    end
  end
  for i = 1, POOL do
    local b = holes[i]
    if i > L.n then
      b:Hide()
    else
      b:Show()
      local has = cur.pegs[i] == 1
      local show = has or fade[i] > 0
      b.shadow:SetShown(show)
      b.base:SetShown(show)
      b.body:SetShown(show)
      b.shine:SetShown(show)
      if show then PegAlpha(b, has and 1 or fade[i]) end
      b.ring:SetShown(has and selected == i)
      b.glow:SetShown(legal[i] ~= nil)
    end
  end
  local n = Count()
  countText:SetText(Plural(n))
  nameText:SetText(NAMES[kind])
  kindRow:Select(kind)
  if cur.over or #cur.undo == 0 then undoButton:Disable() else undoButton:Enable() end
  for k, group in pairs(backdrop) do
    for _, t in ipairs(group) do t:SetShown(k == kind) end
  end
end

local function Layout()
  for i = 1, POOL do
    local b = holes[i]
    local p = L.pos[i]
    if p then
      b:ClearAllPoints()
      b:SetPoint("CENTER", board, "TOPLEFT", BOARD / 2 + p.x, -p.y)
    end
  end
end

local function ShowEnd(improved)
  local left = Count()
  local name = NAMES[kind]
  local title, line
  if left == 1 then
    if kind == "cross" and cur.pegs[L.center] == 1 then
      title, line = "Dead center!", "The last peg sits in the middle."
    else
      title, line = "One peg left!", "A clean sweep of the " .. name .. " board."
    end
  else
    title = Plural(left) .. " left"
    local best = data.best[kind]
    line = "Best on the " .. name .. " board: " .. Plural(best or left)
  end
  if improved then line = line .. "\nA new best!" end
  overlay:Open(title, line)
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function End()
  cur.over = true
  local left = Count()
  local prev = data.best[kind]
  local improved = prev ~= nil and left < prev
  if prev == nil or left < prev then data.best[kind] = left end
  ns.RecordResult("pegs", {
    won = (left == 1), score = left, lowerIsBetter = true, bestKey = "best_" .. kind,
  })
  if left == 1 then ns.PlayTone("chime") else ns.PlayTone("bell1") end
  ShowEnd(improved)
end

local function Jump(f, o, t)
  local u = cur.undo
  u[#u + 1] = { f = f, o = o, t = t }
  if #u > MAX_UNDO then table.remove(u, 1) end
  cur.pegs[f], cur.pegs[o], cur.pegs[t] = 0, 0, 1
  fade[o] = 1
  fading = true
  selected = nil
  ns.Sound("place")
  if not HasMoves() then End() end
  Render()
end

local function Click(i)
  if cur.over then return end
  if selected and selected ~= i and cur.pegs[i] == 0 then
    for _, m in ipairs(L.moves[selected]) do
      if m.t == i and cur.pegs[m.o] == 1 then
        Jump(selected, m.o, i)
        return
      end
    end
  end
  if cur.pegs[i] == 1 and selected ~= i then
    selected = i
    ns.Sound("click")
  else
    selected = nil
  end
  Render()
end

local function Undo()
  if cur.over or #cur.undo == 0 then return end
  local u = table.remove(cur.undo)
  cur.pegs[u.f], cur.pegs[u.o], cur.pegs[u.t] = 1, 1, 0
  fade[u.o] = 0
  selected = nil
  ns.Sound("click")
  Render()
end

local function Restart()
  data.saves[kind] = Fresh(kind)
  cur = data.saves[kind]
  selected = nil
  for i = 1, POOL do fade[i] = 0 end
  overlay:Close()
  Render()
end

local function SwitchTo(k)
  if k == kind then return end
  LoadKind(k)
  Layout()
  overlay:Close()
  if cur.over then ShowEnd(false) end
  Render()
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local WOOD = { 0.36, 0.22, 0.10 }
local EDGE = { 0.15, 0.09, 0.04 }

local function Backdrop(group, x, y, w, h, color)
  local t = board:CreateTexture(nil, "BACKGROUND")
  t:SetPoint("TOPLEFT", board, "TOPLEFT", x, -y)
  t:SetSize(w, h)
  UI.Color(t, color)
  group[#group + 1] = t
end

local function BuildBackdrops()
  -- Cross: two overlapping bars, edged by slightly larger dark ones.
  local g = backdrop.cross
  Backdrop(g, 1, 84 - 3, 286, 126, EDGE)
  Backdrop(g, 84 - 3 + 0, 1, 126, 286, EDGE)
  Backdrop(g, 4, 84, 280, 120, WOOD)
  Backdrop(g, 84, 4, 120, 280, WOOD)
  -- Triangle: thin strips that widen toward the base.
  local t = backdrop.triangle
  local top = TRI_TOP
  for yy = -3, TRI_H + 3, 2 do
    local hw = 14 + math.max(yy, 0) * 0.49
    Backdrop(t, BOARD / 2 - hw - 3, top + yy, 2 * hw + 6, 3, EDGE)
  end
  for yy = 0, TRI_H, 2 do
    local hw = 14 + yy * 0.49
    Backdrop(t, BOARD / 2 - hw, top + yy, 2 * hw, 3, WOOD)
  end
end

local function Tex(b, layer, sub, size, color, alpha, dx, dy, soft)
  local t = b:CreateTexture(nil, layer, nil, sub)
  t:SetTexture(soft and DOT or DISC)
  t:SetSize(size, size)
  t:SetPoint("CENTER", dx or 0, dy or 0)
  t:SetVertexColor(color[1], color[2], color[3], alpha or 1)
  return t
end

local function BuildHole(i)
  local b = CreateFrame("Button", nil, board)
  b:SetSize(40, 40)
  -- Above the "bare" board button, or it swallows every click.
  b:SetFrameLevel(board:GetFrameLevel() + 3)
  b:RegisterForClicks("LeftButtonUp")
  Tex(b, "BORDER", 0, 29, { 0.14, 0.085, 0.04 }, 1)
  Tex(b, "BORDER", 1, 23, { 0.02, 0.012, 0.006 }, 1, 0, -1)
  b.glow = Tex(b, "ARTWORK", 0, 46, { 0.50, 0.75, 1.00 }, 0.55, 0, 0, true)
  b.glow:SetBlendMode("ADD")
  b.glow:Hide()
  b.ring = Tex(b, "ARTWORK", 1, 38, { 1.00, 0.84, 0.38 }, 1)
  b.ring:Hide()
  b.shadow = Tex(b, "ARTWORK", 2, 44, { 0, 0, 0 }, 0.55, 1, -3, true)
  b.base = Tex(b, "ARTWORK", 3, 31, { 0.50, 0.30, 0.10 }, 1)
  b.body = Tex(b, "ARTWORK", 4, 27, { 0.95, 0.70, 0.28 }, 1)
  b.shine = Tex(b, "OVERLAY", 0, 14, { 1.00, 0.94, 0.75 }, 0.85, -4, 4, true)
  local hl = Tex(b, "HIGHLIGHT", 0, 38, { 1, 0.9, 0.6 }, 0.14, 0, 0, true)
  hl:SetBlendMode("ADD")
  b:SetScript("OnClick", function() Click(i) end)
  return b
end

local function Create(parent, saved)
  panel = parent
  data = saved
  if type(data.saves) ~= "table" then data.saves = {} end
  if type(data.best) ~= "table" then data.best = {} end
  for _, k in ipairs(KINDS) do
    local v = data.best[k.key]
    if not IsInt(v, 1, LAYOUT[k.key].n) then data.best[k.key] = nil end
  end
  LoadKind(LAYOUT[data.board] and data.board or "cross")

  local left = (ns.GAME_W - BOARD) / 2
  nameText = UI.Title(parent, 14)
  nameText:SetPoint("TOPLEFT", left, -2)
  countText = UI.Text(parent, 12, C.cream)
  countText:SetPoint("TOPRIGHT", -left, -3)

  board = CreateFrame("Frame", nil, parent)
  board:SetSize(BOARD, BOARD)
  board:SetPoint("TOPLEFT", left, -24)
  local floor = board:CreateTexture(nil, "BACKGROUND")
  floor:SetAllPoints()
  UI.Color(floor, C.inset, 0.85)
  UI.Border(board, C.lineDark)
  BuildBackdrops()

  -- Clicking empty board lets go of the peg.
  local bare = CreateFrame("Button", nil, board)
  bare:SetAllPoints()
  bare:SetFrameLevel(board:GetFrameLevel() + 1)
  bare:SetScript("OnClick", function()
    if selected then
      selected = nil
      Render()
    end
  end)

  holes = {}
  for i = 1, POOL do holes[i] = BuildHole(i) end
  Layout()

  overlay = UI.Overlay(board)
  toast = UI.Toast(board)
  local again = UI.Button(overlay.buttons, "Play again", 110, 24)
  again:SetPoint("TOP", 0, 0)
  again:SetScript("OnClick", Restart)

  undoButton = UI.Button(parent, "Undo", 140, 22)
  undoButton:SetPoint("TOPLEFT", board, "BOTTOMLEFT", 0, -8)
  undoButton:SetScript("OnClick", Undo)
  local restart = UI.Button(parent, "Restart", 140, 22)
  restart:SetPoint("LEFT", undoButton, "RIGHT", 8, 0)
  restart:SetScript("OnClick", Restart)

  kindRow = UI.Choice(parent, KINDS, BOARD, SwitchTo)
  kindRow:SetPoint("TOPLEFT", undoButton, "BOTTOMLEFT", 0, -8)

  local hint = UI.Text(parent, 10, C.dim)
  hint:SetPoint("TOPLEFT", kindRow, "BOTTOMLEFT", 0, -10)
  hint:SetWidth(BOARD)
  hint:SetJustifyH("CENTER")
  hint:SetText("Jump over a peg into an empty hole to remove it.")

  parent:SetScript("OnUpdate", function(_, dt)
    pulse = pulse + dt
    if selected then
      local a = 0.6
      if ns.db and ns.db.flicker then a = 0.5 + 0.2 * sin(pulse * 4) end
      for i = 1, L.n do
        if holes[i].glow:IsShown() then holes[i].glow:SetAlpha(a) end
      end
    end
    if fading then
      local any = false
      for i = 1, L.n do
        if fade[i] > 0 then
          fade[i] = fade[i] - dt / 0.25
          if fade[i] <= 0 then
            fade[i] = 0
            if cur.pegs[i] == 0 then
              local b = holes[i]
              b.shadow:Hide(); b.base:Hide(); b.body:Hide(); b.shine:Hide()
            end
          else
            any = true
            if cur.pegs[i] == 0 then PegAlpha(holes[i], fade[i]) end
          end
        end
      end
      fading = any
    end
  end)

  if cur.over then ShowEnd(false) end
  Render()
end

ns.RegisterGame({
  key = "pegs",
  name = "Pegs",
  blurb = "Jump pegs over each other until only one is left.",
  icon = ns.MEDIA .. "icons\\pegs",
  order = 120,
  hasWins = true,
  Create = Create,
  OnHide = function()
    if selected then
      selected = nil
      Render()
    end
  end,
  InProgress = function(d)
    if type(d) ~= "table" or type(d.saves) ~= "table" then return false end
    for _, k in ipairs({ "cross", "triangle" }) do
      local s = d.saves[k]
      if type(s) == "table" and ValidSave(s, k) and s.over ~= true and #s.undo > 0 then
        return true
      end
    end
    return false
  end,
  Summary = function(d)
    local best
    if type(d.best) == "table" then
      for _, v in pairs(d.best) do
        if type(v) == "number" and (not best or v < best) then best = v end
      end
    end
    return best and ("Best: " .. Plural(best)) or ""
  end,
})
