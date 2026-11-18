-------------------------------------------------------------------------------
-- Campfire Games: Solitaire (the card table)
--
-- One menu tile holding several patience games: Klondike, Spider, Free Cell,
-- Pyramid and Tri Peaks. This file is the table they share: the header,
-- the Undo / Choose game / New deal buttons, the game picker with its
-- options (Klondike scoring, card backs, auto-play), the win screen and the
-- records. Each game lives in its own Solitaire<Name>.lua and registers with
-- ns.SolitaireVariants.
--
-- A variant looks like:
--   { key, name, order, options = { {key, label}, ... }, optionField = "draw",
--     help = "...", Create(page, vdata, hub), Tick(dt), Title(), Left(),
--     Elapsed(), CanUndo(), Undo(), HasProgress(), Deal(), Option(),
--     IsWon(), Show(), Hide(), InProgress(vdata), Data(root) }
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local K = ns.CardKit
local floor, max, min = math.floor, math.max, math.min

ns.SolitaireVariants = ns.SolitaireVariants or {}
local VARIANTS = ns.SolitaireVariants

local NUM_SPARKS = 22

local data, panel
local current
local hub = {}
local header = {}
local undoButton, pickButton, newButton
local overlay, overlayUndo, toast, picker, sparks
local stuckMode = false

local function Sorted()
  local list = {}
  for _, v in pairs(VARIANTS) do list[#list + 1] = v end
  table.sort(list, function(a, b) return a.order < b.order end)
  return list
end

-- The saved table for one variant. Klondike keeps using the top level so
-- games saved before the other variants existed carry on.
local function VData(v)
  if v.Data then return v.Data(data) end
  if type(data[v.key]) ~= "table" then data[v.key] = {} end
  return data[v.key]
end

local function Record(key)
  if type(data.record) ~= "table" then data.record = {} end
  local r = data.record[key]
  if type(r) ~= "table" then
    r = { played = 0, won = 0 }
    data.record[key] = r
  end
  return r
end

local function RecordLine(key)
  local r = Record(key)
  if (r.played or 0) == 0 then return "Not played yet" end
  return format("Won %d of %d", r.won or 0, r.played or 0)
end

-------------------------------------------------------------------------------
-- Header and buttons
-------------------------------------------------------------------------------

function hub.Refresh()
  if not current then return end
  header.left:SetText(current.Left() or "")
  header.title:SetText(current.Title() or current.name)
  header.time:SetText(ns.FormatTime(current.Elapsed() or 0))
  undoButton:SetEnabled(current.CanUndo() and not current.IsWon())
end

function hub.Toast(msg)
  toast:Say(msg)
end

function hub.Prefs() return data end

-------------------------------------------------------------------------------
-- Win screen
-------------------------------------------------------------------------------

local sparkList = {}

local function ResetSpark(s, anywhere)
  s.x = math.random(10, floor(panel:GetWidth()) - 10)
  s.y = anywhere and math.random(0, ns.GAME_H) or -6
  s.vy = 18 + math.random() * 34
  s.ph = math.random() * 6.28
  s.size = 7 + math.random() * 9
  s.tex:SetSize(s.size, s.size)
end

local function OpenWin(title, line)
  stuckMode = false
  overlayUndo:Hide()
  overlay:Open(title, line)
  for _, s in ipairs(sparkList) do ResetSpark(s, true) end
  sparks:Show()
end

-- info = { time, bestKey, lowerIsBetter, score, line, cards }
function hub.Won(v, info)
  local r = Record(v.key)
  r.played = (r.played or 0) + 1
  r.won = (r.won or 0) + 1
  local newBest = ns.RecordResult("solitaire", {
    won = true, time = info.score == nil and info.time or nil, score = info.score,
    lowerIsBetter = info.lowerIsBetter, bestKey = info.bestKey,
  })
  ns.Sound("win")
  hub.Refresh()
  local title = newBest and "A new best!" or "You win!"
  local line = (info.line or "") .. "\n" .. RecordLine(v.key)
  if info.cards and #info.cards > 0 and v.cascade then
    v.cascade:Play(info.cards, function()
      if current == v and v.IsWon() then OpenWin(title, line) end
    end)
  else
    OpenWin(title, line)
  end
end

-- The game can't go on: offer Undo or a new deal.
function hub.Stuck(v, line)
  ns.Sound("bad")
  stuckMode = true
  sparks:Hide()
  overlayUndo:Show()
  overlay:Open("No more moves", line)
end

-- When a saved, finished game is opened again.
function hub.ShowWon(v, line)
  OpenWin("You win!", (line or "") .. "\n" .. RecordLine(v.key))
end

local function CloseOverlay()
  overlay:Close()
  sparks:Hide()
  stuckMode = false
end

-------------------------------------------------------------------------------
-- Dealing and switching games
-------------------------------------------------------------------------------

local function Deal()
  if not current then return end
  if current.HasProgress() then
    local r = Record(current.key)
    r.played = (r.played or 0) + 1
    ns.RecordResult("solitaire", { won = false })
  end
  CloseOverlay()
  if current.cascade then current.cascade:Clear(current.cards) end
  current.Deal()
  hub.Refresh()
end

StaticPopupDialogs["DOWNTIME_NEW_SOLITAIRE"] = {
  text = "Start a new deal? This game will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function() Deal() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function AskDeal()
  if current and current.HasProgress() then
    StaticPopup_Show("DOWNTIME_NEW_SOLITAIRE")
  else
    Deal()
  end
end

local function Undo()
  if not current or not current.CanUndo() then return end
  if stuckMode then CloseOverlay() end
  current.Undo()
  hub.Refresh()
end

local function Switch(v)
  if current == v then return end
  if current then
    current.Hide()
    current.page:Hide()
  end
  CloseOverlay()
  current = v
  data.variant = v.key
  ns.HELP.solitaire = v.help
  if not v.page then
    v.page = CreateFrame("Frame", nil, panel)
    v.page:SetAllPoints()
    v.page:SetFrameLevel(panel:GetFrameLevel() + 1)
    v.Create(v.page, VData(v), hub)
  end
  v.page:Show()
  v.Show()
  hub.Refresh()
  hub.FitWidth()
end

-- The table size from the chooser (kept with Spider's data): "wide" or "narrow".
function hub.TableSize()
  local sv = VARIANTS.spider
  local l = sv and VData(sv).layout
  return l == "narrow" and "narrow" or "wide"
end

-- Spider and Tri Peaks can make the window wider; the others use the normal width.
function hub.Width()
  return current and current.Width and current.Width() or ns.GAME_W
end

function hub.FitWidth()
  if ns.SetGameWidth and panel:IsVisible() then ns.SetGameWidth(hub.Width()) end
end

local pendingPick

StaticPopupDialogs["DOWNTIME_SOLITAIRE_SWITCH"] = {
  text = "Start a new game of %s? The game in progress will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    pendingPick = nil
    Deal()
  end,
  OnCancel = function()
    -- Keep playing the game in progress with its own option.
    local p = pendingPick
    pendingPick = nil
    if p and p.v.optionField then VData(p.v)[p.v.optionField] = p.v.Option() end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function OptionLabel(v, opt)
  for _, o in ipairs(v.options or {}) do
    if o.key == opt then return v.name .. " (" .. o.label .. ")" end
  end
  return v.name
end

-- A game and option picked in the chooser. A different option than the
-- game in progress starts a new deal with it, after asking.
local function Pick(v, opt)
  Switch(v)
  local vd = VData(v)
  if v.optionField and opt ~= nil then vd[v.optionField] = opt end
  if v.optionField and opt ~= nil and v.Option() ~= opt then
    if v.HasProgress() then
      pendingPick = { v = v }
      StaticPopup_Show("DOWNTIME_SOLITAIRE_SWITCH", OptionLabel(v, opt))
    else
      Deal()
    end
  end
  hub.Refresh()
end

-------------------------------------------------------------------------------
-- The chooser: every game with its options, and the shared settings.
-------------------------------------------------------------------------------

local function BuildPicker(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  p:SetFrameLevel(parent:GetFrameLevel() + 2100)
  p:EnableMouse(true)
  local shade = p:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints()
  shade:SetColorTexture(0.04, 0.025, 0.015, 0.96)
  local title = UI.Title(p, 18)
  title:SetPoint("TOP", 0, -4)
  title:SetText("Choose a game")

  p.rows = {}
  local y = 32
  for _, v in ipairs(Sorted()) do
    local row = CreateFrame("Frame", nil, p)
    row:SetHeight(36)
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", 0, -y)
    row.name = UI.Title(row, 14)
    row.name:SetPoint("TOPLEFT", 4, -2)
    row.name:SetText(v.name)
    row.rec = UI.Text(row, 10, C.dim)
    row.rec:SetPoint("TOPLEFT", 4, -19)
    local opts = v.options or { { key = false, label = "Play" } }
    local bw = (#opts >= 3) and 56 or 66
    for i = #opts, 1, -1 do
      local o = opts[i]
      local b = UI.Button(row, o.label, bw, 22, 11)
      b:SetPoint("RIGHT", row, "RIGHT", -((#opts - i) * (bw + 3)), 0)
      b:SetScript("OnClick", function()
        p:Hide()
        Pick(v, o.key ~= false and o.key or nil)
      end)
    end
    row.v = v
    p.rows[#p.rows + 1] = row
    y = y + 38
  end

  local line = p:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", 6, -(y + 2))
  line:SetPoint("TOPRIGHT", -6, -(y + 2))
  line:SetHeight(1)
  UI.Color(line, C.line, 0.6)
  y = y + 10

  local sl = UI.Text(p, 11, C.cream)
  sl:SetPoint("TOPLEFT", 4, -(y + 5))
  sl:SetText("Klondike score")
  p.scoring = UI.Choice(p, {
    { key = "standard", label = "Standard" }, { key = "vegas", label = "Vegas" }, { key = "none", label = "None" },
  }, 204, function(k)
    data.scoring = k
    p.scoring:Select(k)
    local kv = VARIANTS.klondike
    if kv and kv.ScoringChanged then kv.ScoringChanged() end
    hub.Refresh()
  end)
  p.scoring:SetPoint("TOPRIGHT", 0, -y)
  y = y + 30

  local tl = UI.Text(p, 11, C.cream)
  tl:SetPoint("TOPLEFT", 4, -(y + 5))
  tl:SetText("Spider and Tri Peaks table")
  p.layout = UI.Choice(p, { { key = "wide", label = "Wide" }, { key = "narrow", label = "Narrow" } }, 136, function(k)
    local sd = VData(VARIANTS.spider)
    sd.layout = k
    p.layout:Select(k)
    for _, v in pairs(VARIANTS) do
      if v.LayoutChanged then v.LayoutChanged() end
    end
    hub.FitWidth()
  end)
  p.layout:SetPoint("TOPRIGHT", 0, -y)
  y = y + 30

  local bl = UI.Text(p, 11, C.cream)
  bl:SetPoint("TOPLEFT", 4, -(y + 14))
  bl:SetText("Card back")
  p.backs = {}
  for i = #K.BACKS, 1, -1 do
    local b = CreateFrame("Button", nil, p)
    b:SetSize(28, 40)
    b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -((#K.BACKS - i) * 34) - 2, -y)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(ns.MEDIA .. "cards\\" .. K.BACKS[i].tex)
    t:SetTexCoord(0, 1, 0.156, 0.844)
    b.ring = UI.Border(b, C.gold, 2, "OVERLAY")
    UI.Tooltip(b, K.BACKS[i].name)
    b:SetScript("OnClick", function()
      data.back = i
      K.prefs.back = i
      K.RefreshBacks()
      ns.Sound("click")
      p:Refresh()
    end)
    p.backs[i] = b
  end
  y = y + 48

  p.auto = UI.Check(p, "Play safe cards up to the foundations",
    function() return data.autoplay end,
    function(on)
      data.autoplay = on
      if current and current.AutoChanged then current.AutoChanged() end
    end)
  p.auto:SetPoint("TOPLEFT", 0, -y)

  local close = UI.Button(p, "Back to the table", 150, 22)
  close:SetPoint("BOTTOM", 0, 0)
  close:SetScript("OnClick", function() p:Hide() end)

  function p:Refresh()
    for _, row in ipairs(self.rows) do
      row.rec:SetText(RecordLine(row.v.key))
      UI.SetTextColor(row.name, row.v == current and C.gold or C.cream)
    end
    self.scoring:Select(data.scoring)
    self.layout:Select(VARIANTS.spider and VData(VARIANTS.spider).layout or "wide")
    for i, b in ipairs(self.backs) do
      for j = 1, 4 do b.ring[j]:SetShown(i == data.back) end
    end
    self.auto:Refresh()
  end
  p:SetScript("OnShow", function(self) self:Refresh() end)
  p:Hide()
  return p
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function BuildOverlay(parent)
  overlay = UI.Overlay(parent)
  overlay:SetFrameLevel(parent:GetFrameLevel() + 2000)
  overlay.shade:SetColorTexture(0.03, 0.02, 0.01, 0.74)
  local again = UI.Button(overlay.buttons, "New deal", 110, 24)
  again:SetPoint("TOP", 0, 0)
  again:SetScript("OnClick", Deal)
  overlayUndo = UI.Button(overlay.buttons, "Undo", 80, 24)
  overlayUndo:SetPoint("TOP", 0, -30)
  overlayUndo:SetScript("OnClick", Undo)
  overlayUndo:Hide()
  toast = UI.Toast(parent)
  toast:SetFrameLevel(parent:GetFrameLevel() + 2200)

  -- Warm lights drifting up over the win screen.
  sparks = CreateFrame("Frame", nil, parent)
  sparks:SetAllPoints()
  sparks:SetFrameLevel(parent:GetFrameLevel() + 2010)
  for i = 1, NUM_SPARKS do
    local s = { tex = sparks:CreateTexture(nil, "OVERLAY") }
    s.tex:SetTexture(ns.MEDIA .. "dot")
    s.tex:SetBlendMode("ADD")
    s.tex:SetVertexColor(1.0, 0.72, 0.38, 0.55)
    ResetSpark(s, true)
    sparkList[i] = s
  end
  local clock = 0
  sparks:SetScript("OnUpdate", function(_, dt)
    clock = clock + dt
    for _, s in ipairs(sparkList) do
      s.y = s.y + s.vy * dt
      if s.y > ns.GAME_H + 10 then ResetSpark(s, false) end
      local x = s.x + math.sin(clock * 0.8 + s.ph) * 9
      s.tex:ClearAllPoints()
      s.tex:SetPoint("CENTER", parent, "BOTTOMLEFT", x, s.y)
      s.tex:SetAlpha(max(0.05, min(1, (1 - s.y / ns.GAME_H) * 1.4)))
    end
  end)
  sparks:Hide()
end

local function BuildChrome(parent)
  header.left = UI.Text(parent, 12, C.cream)
  header.left:SetPoint("TOPLEFT", 2, -1)
  header.time = UI.Text(parent, 12, C.cream)
  header.time:SetPoint("TOPRIGHT", -2, -1)
  header.title = UI.Title(parent, 13)
  header.title:SetPoint("TOP", 0, -1)

  undoButton = UI.Button(parent, "Undo", 98, 22)
  undoButton:SetPoint("BOTTOMLEFT", 0, 0)
  undoButton:SetScript("OnClick", Undo)
  pickButton = UI.Button(parent, "Choose game", 116, 22)
  pickButton:SetPoint("BOTTOM", 0, 0)
  pickButton:SetScript("OnClick", function()
    if picker:IsShown() then picker:Hide() else picker:Show() end
  end)
  newButton = UI.Button(parent, "New deal", 98, 22)
  newButton:SetPoint("BOTTOMRIGHT", 0, 0)
  newButton:SetScript("OnClick", AskDeal)
end

local function Create(parent, saved)
  panel = parent
  data = saved
  if data.draw ~= 1 and data.draw ~= 3 then data.draw = 1 end
  if data.scoring ~= "standard" and data.scoring ~= "vegas" and data.scoring ~= "none" then data.scoring = "standard" end
  if type(data.back) ~= "number" or not K.BACKS[data.back] then data.back = 1 end
  data.autoplay = data.autoplay and true or false
  if type(data.vegasBank) ~= "number" then data.vegasBank = 0 end
  K.prefs = data

  BuildChrome(parent)
  BuildOverlay(parent)
  picker = BuildPicker(parent)

  local acc = 0
  parent:SetScript("OnUpdate", function(_, dt)
    if not current then return end
    current.Tick(dt)
    acc = acc + dt
    if acc >= 0.25 then
      acc = 0
      hub.Refresh()
    end
  end)

  Switch(VARIANTS[data.variant] or VARIANTS.klondike or Sorted()[1])
end

ns.RegisterGame({
  key = "solitaire",
  name = "Solitaire",
  blurb = "Klondike, Spider, Free Cell, Pyramid and Tri Peaks.",
  icon = ns.MEDIA .. "icons\\solitaire",
  order = 30,
  hasWins = true,
  Create = Create,
  Width = function() return hub.Width() end,
  OnShow = function()
    if current then
      current.Show()
      hub.Refresh()
    end
  end,
  OnHide = function()
    if current then current.Hide() end
    if picker then picker:Hide() end
  end,
  InProgress = function(d)
    if type(d) ~= "table" then return false end
    local v = VARIANTS[d.variant] or VARIANTS.klondike
    if not v or not v.InProgress then return false end
    local vd = v.Data and v.Data(d) or d[v.key]
    return v.InProgress(vd) and true or false
  end,
  Summary = function(d)
    local s = d.stats
    if (s.won or 0) == 0 then return "" end
    return format("Won %d", s.won)
  end,
})
