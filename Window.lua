-------------------------------------------------------------------------------
-- Campfire Games: the window
--
-- A standard WoW window (title bar, round portrait, close button) with a
-- wooden board inside: string lights under the title bar, firelight at the
-- bottom. Pages: the game menu, one page per game, scores, options, trophies.
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local C, UI = ns.C, ns.UI

local PAD = 10
local ROW_Y = -32      -- the row under the title bar
local NAV_H = 34       -- breadcrumb bar height (Blizzard's is 34)
local CAP_W = 11       -- arrow tip of a breadcrumb segment
local HEADER = 64      -- top of the window to the top of the game area
local BOTTOM = 12
local WIN_W = ns.GAME_W + PAD * 2
local WIN_H = HEADER + ns.GAME_H + BOTTOM
local MIN_SCALE, MAX_SCALE = 0.5, 1.6
local CAMPFIRE = ns.MEDIA .. "icons\\downtime"

local frame, menuButtons
local SetTitle, SetPortrait
local pages = {}      -- name -> frame
local current         -- current page name
local currentGame     -- game table when a game page is open
local lights = {}
local glow
local menuRows = {}

-------------------------------------------------------------------------------
-- Position and scale
-------------------------------------------------------------------------------

local function SavePosition()
  local s = frame:GetScale()
  ns.db.x, ns.db.y = frame:GetLeft() * s, frame:GetTop() * s
end

local function PlaceFrame()
  local s = ns.db.scale or ns.DEFAULT_SCALE
  frame:SetScale(s)
  frame:ClearAllPoints()
  if ns.db.x and ns.db.y then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.x / s, ns.db.y / s)
  else
    -- Off to the left side, out of the way of the middle of the screen.
    frame:SetPoint("LEFT", UIParent, "LEFT", 40 / s, 40 / s)
  end
end

-------------------------------------------------------------------------------
-- Keyboard: only while a game asks for it, never in combat
-------------------------------------------------------------------------------

function ns.UpdateKeyboard()
  if not frame then return end
  local on = ns.keysWanted and currentGame ~= nil and frame:IsShown() and not InCombatLockdown()
  frame:EnableKeyboard(on and true or false)
end

local function OnKeyDown(self, key)
  if InCombatLockdown() then return end
  local handled = false
  if currentGame and currentGame.OnKey then
    handled = currentGame.OnKey(key) and true or false
  end
  self:SetPropagateKeyboardInput(not handled)
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------

local function RefreshMenu()
  for _, row in ipairs(menuRows) do
    local g = row.game
    local line = ""
    if g.Summary then
      local ok, s = pcall(g.Summary, ns.GameData(g.key))
      if ok and s then line = s end
    end
    row.summary:SetText(line)
    local busy = false
    if g.InProgress then
      local ok, v = pcall(g.InProgress, ns.GameData(g.key))
      busy = ok and v and true or false
    end
    row.ember:SetShown(busy)
  end
end

local function ShowPage(name)
  if current == name then return end
  local old = current
  if currentGame then
    if currentGame.OnHide then currentGame.OnHide() end
    currentGame = nil
    ns.WantKeys(false)
  end
  for n, p in pairs(pages) do p:SetShown(n == name) end
  current = name

  local game = ns.gamesByKey[name]
  if game then
    if not game.built then
      game.built = true
      game.Create(pages[name], ns.GameData(game.key))
    end
    currentGame = game
    ns.db.lastGame = game.key
    SetTitle(game.name)
    if game.OnShow and frame:IsShown() then game.OnShow() end
  elseif name == "menu" then
    ns.db.lastGame = nil
    SetTitle(ns.TITLE)
    RefreshMenu()
  elseif name == "scores" then
    SetTitle("Scores")
    pages.scores:Refresh()
  elseif name == "options" then
    SetTitle("Options")
    pages.options:Refresh()
  elseif name == "trophies" then
    SetTitle("Trophies")
    pages.trophies:Refresh()
  end
  SetPortrait(game and game.icon or CAMPFIRE)
  local labels = { scores = "Scores", options = "Options", trophies = "Trophies" }
  ns.SetNav(game and game.name or labels[name], game ~= nil)
  menuButtons:SetShown(name == "menu")
  ns.helpPanel:Hide()
  ns.helpButton:SetShown(game ~= nil and ns.HELP ~= nil and ns.HELP[name] ~= nil)
  if ns.helpButton.TryClone and ns.helpButton:IsShown() then ns.helpButton:TryClone() end
  if old then ns.Sound("page") end
  ns.UpdateKeyboard()
end
ns.ShowPage = ShowPage

local function NewPage(name)
  local p = CreateFrame("Frame", nil, frame)
  p:SetSize(ns.GAME_W, ns.GAME_H)
  p:SetPoint("TOPLEFT", PAD, -HEADER)
  p:Hide()
  pages[name] = p
  return p
end

-------------------------------------------------------------------------------
-- The game menu: a grid of tiles, like a board of pinned notices. Hovering a
-- tile shows what the game is at the bottom.
-------------------------------------------------------------------------------

local TILE_GAP = 7
local INFO_H = 50

local function BuildMenu()
  local p = NewPage("menu")
  -- Three across, or four once there are more than twelve games.
  local COLS = #ns.games > 12 and 4 or 3
  local TILE_W = math.floor((ns.GAME_W - (COLS - 1) * TILE_GAP) / COLS)
  local rows = math.max(1, math.ceil(#ns.games / COLS))
  local TILE_H = math.min(108, math.floor((ns.GAME_H - INFO_H - 10 - (rows - 1) * TILE_GAP) / rows))
  local ICON = TILE_H >= 100 and 50 or 40

  local info = UI.Inset(p, ns.GAME_W, INFO_H)
  info:SetPoint("BOTTOM", 0, 0)
  local infoName = UI.Title(info, 15)
  infoName:SetPoint("TOPLEFT", 8, -6)
  local infoText = UI.Text(info, 12, C.cream)
  infoText:SetPoint("TOPLEFT", infoName, "BOTTOMLEFT", 0, -2)
  infoText:SetWidth(ns.GAME_W - 16)
  infoText:SetJustifyH("LEFT")
  local function Info(g)
    if g then
      infoName:SetText(g.name)
      infoText:SetText(g.blurb or "")
    else
      infoName:SetText("Pull up a chair")
      infoText:SetText("Pick a game.")
    end
  end
  Info(nil)

  for i, g in ipairs(ns.games) do
    local col, rowN = (i - 1) % COLS, math.floor((i - 1) / COLS)
    local tile = CreateFrame("Button", nil, p)
    tile:SetSize(TILE_W, TILE_H)
    tile:SetPoint("TOPLEFT", col * (TILE_W + TILE_GAP), -rowN * (TILE_H + TILE_GAP))
    tile.game = g

    tile.bg = tile:CreateTexture(nil, "BACKGROUND")
    tile.bg:SetAllPoints()
    UI.Color(tile.bg, C.inset, 0.72)
    tile.border = UI.Border(tile, C.lineDark)

    tile.iconFrame = CreateFrame("Frame", nil, tile)
    tile.iconFrame:SetSize(ICON, ICON)
    tile.iconFrame:SetPoint("TOP", 0, -math.floor((TILE_H - ICON - 34) / 2))
    tile.icon = tile.iconFrame:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", 1, -1)
    tile.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    tile.icon:SetTexture(g.icon)
    tile.iconBorder = UI.Border(tile.iconFrame, C.line)

    tile.name = UI.Title(tile, COLS > 3 and 12 or 14)
    tile.name:SetWidth(TILE_W - 4)
    tile.name:SetPoint("TOP", tile.iconFrame, "BOTTOM", 0, -4)
    tile.name:SetText(g.name)

    tile.summary = UI.Text(tile, 10, C.gold)
    tile.summary:SetPoint("BOTTOM", 0, 5)
    tile.summary:SetWidth(TILE_W - 6)
    tile.summary:SetJustifyH("CENTER")

    tile:SetScript("OnEnter", function(self)
      UI.Color(self.bg, C.insetHi, 0.92)
      UI.SetBorderColor(self.border, C.line)
      UI.SetBorderColor(self.iconBorder, C.gold)
      Info(g)
    end)
    tile:SetScript("OnLeave", function(self)
      UI.Color(self.bg, C.inset, 0.72)
      UI.SetBorderColor(self.border, C.lineDark)
      UI.SetBorderColor(self.iconBorder, C.line)
      Info(nil)
    end)
    tile:SetScript("OnClick", function() ShowPage(g.key) end)
    -- A small ember in the corner when a game is waiting for you.
    tile.ember = tile:CreateTexture(nil, "OVERLAY")
    tile.ember:SetTexture(ns.MEDIA .. "dot")
    tile.ember:SetBlendMode("ADD")
    tile.ember:SetVertexColor(C.ember[1], C.ember[2], C.ember[3], 0.95)
    tile.ember:SetSize(16, 16)
    tile.ember:SetPoint("TOPRIGHT", -3, -3)
    tile.ember:Hide()
    menuRows[i] = tile
  end
end

-------------------------------------------------------------------------------
-- Scores page
-------------------------------------------------------------------------------

local function BuildScores()
  local p = NewPage("scores")
  local rows = {}
  local rowH = 40
  local iconS = rowH - 10

  -- Rows scroll with the mouse wheel when they don't all fit.
  local view = CreateFrame("Frame", nil, p)
  view:SetPoint("TOPLEFT", 0, 0)
  view:SetPoint("BOTTOMRIGHT", 0, 20)
  view:SetClipsChildren(true)
  view:EnableMouseWheel(true)
  local content = CreateFrame("Frame", nil, view)
  content:SetPoint("TOPLEFT")
  content:SetSize(ns.GAME_W, rowH * #ns.games)
  local offset = 0
  local maxOffset = math.max(0, rowH * #ns.games - (ns.GAME_H - 20))
  local more = UI.Text(p, 9, C.faint)
  more:SetPoint("BOTTOMRIGHT", 0, 4)
  more:SetText("Scroll for more")
  local function Scroll(v)
    offset = math.max(0, math.min(maxOffset, v))
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", 0, offset)
    more:SetShown(offset < maxOffset)
  end
  view:SetScript("OnMouseWheel", function(_, delta) Scroll(offset - delta * rowH * 2) end)
  Scroll(0)

  for i, g in ipairs(ns.games) do
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(ns.GAME_W, rowH - 4)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    UI.Color(r.bg, C.inset, (i % 2 == 0) and 0.45 or 0.7)
    local iconFrame = CreateFrame("Frame", nil, r)
    iconFrame:SetSize(iconS, iconS)
    iconFrame:SetPoint("LEFT", 6, 0)
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexture(g.icon)
    UI.Border(iconFrame, C.line)
    r.name = UI.Title(r, 13)
    r.name:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 8, -1)
    r.name:SetText(g.name)
    r.counts = UI.Text(r, 10, C.dim)
    r.counts:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMRIGHT", 8, 1)
    r.best = UI.Text(r, 11, C.gold)
    r.best:SetPoint("RIGHT", -8, 0)
    r.best:SetJustifyH("RIGHT")
    r.game = g
    rows[i] = r
  end
  local fire = UI.Text(p, 11, C.dim)
  fire:SetPoint("BOTTOMLEFT", 2, 4)

  function p:Refresh()
    for _, r in ipairs(rows) do
      local g = r.game
      local d = ns.GameData(g.key)
      local s = d.stats
      local parts = { format("Played %d", s.played or 0) }
      if g.hasWins then
        parts[#parts + 1] = format("Won %d", s.won or 0)
        if (s.bestStreak or 0) > 1 then parts[#parts + 1] = format("Streak %d", s.bestStreak) end
      end
      r.counts:SetText(table.concat(parts, "   "))
      local sum = ""
      if g.Summary then
        local ok, v = pcall(g.Summary, d)
        if ok and v then sum = v end
      end
      r.best:SetText(sum)
    end
    local t = ns.db.timeByFire or 0
    local h, m = math.floor(t / 3600), math.floor(t / 60) % 60
    fire:SetText(format("Time by the fire: %s", h > 0 and format("%dh %dm", h, m) or format("%dm", m)))
  end
end

-------------------------------------------------------------------------------
-- Trophies page: every trophy, earned ones lit. Scroll with the mouse wheel.
-------------------------------------------------------------------------------

local TROPHY_ROW = 34

local function BuildTrophies()
  local p = NewPage("trophies")
  local head = UI.Text(p, 11, C.dim)
  head:SetPoint("TOP", 0, -2)

  local view = CreateFrame("Frame", nil, p)
  view:SetPoint("TOPLEFT", 0, -18)
  view:SetPoint("BOTTOMRIGHT", 0, 0)
  view:SetClipsChildren(true)
  view:EnableMouseWheel(true)
  local content = CreateFrame("Frame", nil, view)
  content:SetPoint("TOPLEFT")
  content:SetSize(ns.GAME_W, 10)

  local hint = UI.Text(p, 9, C.faint)
  hint:SetPoint("BOTTOMRIGHT", 0, -12)
  hint:SetText("Scroll for more")

  local rows = {}
  local offset = 0
  local function MaxOffset()
    return math.max(0, #rows * TROPHY_ROW - (ns.GAME_H - 18))
  end
  local function Scroll(v)
    offset = math.max(0, math.min(MaxOffset(), v))
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", 0, offset)
    hint:SetShown(offset < MaxOffset())
  end
  view:SetScript("OnMouseWheel", function(_, delta) Scroll(offset - delta * TROPHY_ROW * 2) end)

  for i, t in ipairs(ns.TROPHIES) do
    if t[2] == nil or ns.gamesByKey[t[2]] then
      local r = CreateFrame("Frame", nil, content)
      r:SetSize(ns.GAME_W, TROPHY_ROW - 3)
      r:SetPoint("TOPLEFT", 0, -#rows * TROPHY_ROW)
      r.bg = r:CreateTexture(nil, "BACKGROUND")
      r.bg:SetAllPoints()
      local iconFrame = CreateFrame("Frame", nil, r)
      iconFrame:SetSize(TROPHY_ROW - 9, TROPHY_ROW - 9)
      iconFrame:SetPoint("LEFT", 5, 0)
      r.icon = iconFrame:CreateTexture(nil, "ARTWORK")
      r.icon:SetPoint("TOPLEFT", 1, -1)
      r.icon:SetPoint("BOTTOMRIGHT", -1, 1)
      local g = t[2] and ns.gamesByKey[t[2]]
      r.icon:SetTexture(g and g.icon or (ns.MEDIA .. "icons\\downtime"))
      r.iconBorder = UI.Border(iconFrame, C.line)
      r.name = UI.Title(r, 12)
      r.name:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 8, 0)
      r.name:SetText(t[3])
      r.text = UI.Text(r, 9, C.dim)
      r.text:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMRIGHT", 8, 0)
      r.text:SetText(t[4])
      r.when = UI.Text(r, 9, C.faint)
      r.when:SetPoint("RIGHT", -6, 0)
      r.trophy = t
      rows[#rows + 1] = r
    end
  end
  content:SetHeight(#rows * TROPHY_ROW)

  function p:Refresh()
    local earned = ns.db.trophies or {}
    for _, r in ipairs(rows) do
      local when = earned[r.trophy[1]]
      local on = when ~= nil
      UI.Color(r.bg, on and C.insetHi or C.inset, on and 0.85 or 0.55)
      r.icon:SetDesaturated(not on)
      r.icon:SetAlpha(on and 1 or 0.45)
      UI.SetBorderColor(r.iconBorder, on and C.gold or C.lineDark)
      UI.SetTextColor(r.name, on and C.gold or C.faint)
      UI.SetTextColor(r.text, on and C.cream or C.faint)
      r.when:SetText(on and type(when) == "number" and date("%b %d", when) or "")
    end
    local have, total = ns.TrophyCount()
    head:SetText(format("%d of %d trophies earned", have, total))
    Scroll(offset)
  end
end

-------------------------------------------------------------------------------
-- Options page
-------------------------------------------------------------------------------

-- Shared by the Options page and the panel in WoW's AddOns settings.
local OPTIONS = {
  { "Sounds", "sound" },
  { "Flickering firelight", "flicker" },
  { "String lights", "lights", function() ns.UpdateLights() end },
  { "Fireside crackle (ambient sound)", "ambience", function() ns.UpdateAmbience() end },
  { "Hide the window in combat", "hideInCombat" },
  { "Minimap button", "minimap", function() ns.UpdateMinimapButton() end },
  { "See-through when the mouse is away", "seeThrough" },
  { "Use raid marks for game pieces", "raidMarks", function() ns.PiecesChanged() end },
  { "Open when I start fishing", "openFishing" },
  { "Open on flight paths", "openTaxi" },
}

local function SetOption(o, v)
  ns.db[o[2]] = v and true or false
  if o[3] then o[3](v) end
end

local function ResetPlace()
  ns.db.x, ns.db.y, ns.db.scale = nil, nil, ns.DEFAULT_SCALE
  PlaceFrame()
end

local function BuildOptions()
  local p = NewPage("options")
  local y = -8
  local checks = {}
  for _, o in ipairs(OPTIONS) do
    local c = UI.Check(p, o[1],
      function() return ns.db[o[2]] end,
      function(v) SetOption(o, v) end)
    c:SetPoint("TOPLEFT", 8, y)
    y = y - 26
    checks[#checks + 1] = c
  end
  function p:Refresh()
    for _, c in ipairs(checks) do c:Refresh() end
  end

  local reset = UI.Button(p, "Reset size and position", 180, 22)
  reset:SetPoint("TOPLEFT", 8, y - 6)
  reset:SetScript("OnClick", ResetPlace)

  local help = UI.Text(p, 11, C.dim)
  help:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -12)
  help:SetWidth(ns.GAME_W - 16)
  help:SetJustifyH("LEFT")
  help:SetSpacing(2)
  help:SetText("Drag the window by its title bar or any empty spot. Drag the bottom right corner to make it bigger or smaller.\n\n/campfire or /games opens and closes the window. You can also set a key for it under Key Bindings, AddOns.\n\n/campfire reset puts it back where it started.")
end

-------------------------------------------------------------------------------
-- Panel in WoW's own settings (Options > AddOns), with the same options
-------------------------------------------------------------------------------

local function BuildSettingsPanel()
  local panel = CreateFrame("Frame", "DowntimeSettingsPanel")
  panel.name = ns.TITLE

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(ns.TITLE)
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetText("Little games for idle time. Type /campfire or /games to open the window.")

  local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  open:SetSize(160, 22)
  open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
  open:SetText("Open " .. ns.TITLE)
  open:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    frame:Show()
  end)

  local checks = {}
  local y = -96
  for _, o in ipairs(OPTIONS) do
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 14, y)
    if cb.Text then cb.Text:SetText(o[1]) end
    cb:SetScript("OnClick", function(self)
      SetOption(o, self:GetChecked())
      if pages.options then pages.options:Refresh() end
    end)
    cb.option = o
    checks[#checks + 1] = cb
    y = y - 30
  end

  local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  reset:SetSize(200, 22)
  reset:SetPoint("TOPLEFT", 18, y - 8)
  reset:SetText("Reset size and position")
  reset:SetScript("OnClick", ResetPlace)

  panel:SetScript("OnShow", function()
    for _, cb in ipairs(checks) do cb:SetChecked(ns.db[cb.option[2]] and true or false) end
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
    Settings.RegisterAddOnCategory(category)
    ns.settingsCategory = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

function ns.OpenSettings()
  if ns.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(ns.settingsCategory:GetID())
  elseif frame then
    frame:Show()
    ShowPage("options")
  end
end

-------------------------------------------------------------------------------
-- The frame itself
-------------------------------------------------------------------------------

-- Blizzard's standard window: metal edge, title bar, round portrait at the
-- top left and a red close button. Returns nil if the client doesn't have it.
local function MakeBlizzardFrame()
  if not UI.HasTemplate("PortraitFrameTemplate") then return nil end
  local ok, f = pcall(CreateFrame, "Frame", "DowntimeFrame", UIParent, "PortraitFrameTemplate")
  if not ok or not f or not f.CloseButton then return nil end
  return f
end

-- Our own edge, for clients without the template.
local function DrawOwnEdge(f)
  UI.Border(f, { 0, 0, 0 }, 1, "BORDER")
  local gold = CreateFrame("Frame", nil, f)
  gold:SetPoint("TOPLEFT", 1, -1)
  gold:SetPoint("BOTTOMRIGHT", -1, 1)
  UI.Border(gold, C.line, 2, "BORDER")
  local inner = CreateFrame("Frame", nil, f)
  inner:SetPoint("TOPLEFT", 3, -3)
  inner:SetPoint("BOTTOMRIGHT", -3, 3)
  UI.Border(inner, C.lineDark, 1, "BORDER")
  local corners = {
    { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
    { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 },
  }
  for _, c in ipairs(corners) do
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture(ns.MEDIA .. "corner")
    t:SetSize(26, 26)
    t:SetPoint(c[1], c[1]:find("LEFT") and 2 or -2, c[1]:find("TOP") and -2 or 2)
    t:SetTexCoord(c[2], c[3], c[4], c[5])
  end
  -- Title bar: a darker strip with the title centered.
  local bar = f:CreateTexture(nil, "BORDER")
  bar:SetPoint("TOPLEFT", 4, -4)
  bar:SetPoint("TOPRIGHT", -4, -4)
  bar:SetHeight(18)
  bar:SetColorTexture(0, 0, 0, 0.45)
  local title = UI.Title(f, 15)
  title:SetPoint("TOP", 0, -6)
  local icon = f:CreateTexture(nil, "OVERLAY")
  icon:SetSize(44, 44)
  icon:SetPoint("TOPLEFT", 10, -16)
  local iconFrame = CreateFrame("Frame", nil, f)
  iconFrame:SetAllPoints(icon)
  UI.Border(iconFrame, C.line)
  local close = UI.Button(f, "x", 20, 18, 12)
  close:SetPoint("TOPRIGHT", -5, -4)
  close:SetScript("OnClick", function() f:Hide() end)
  return function(text) title:SetText(text) end,
    function(path) icon:SetTexture(path) end
end

local function BuildFrame()
  frame = MakeBlizzardFrame()
  local blizzard = frame ~= nil
  if not blizzard then frame = CreateFrame("Frame", "DowntimeFrame", UIParent) end
  frame:SetSize(WIN_W, WIN_H)
  frame:SetFrameStrata("MEDIUM")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
  frame:Hide()
  ns.frame = frame

  -- Where the wood goes: inside Blizzard's edge, or the whole frame.
  local inside = frame
  if blizzard and frame.Bg then
    inside = frame.Bg
    frame.Bg:SetAlpha(0)
  end

  -- Wood planks, darkened.
  local wood = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
  wood:SetAllPoints(inside)
  wood:SetTexture(ns.MEDIA .. "wood", "REPEAT", "REPEAT")
  wood:SetHorizTile(true)
  wood:SetVertTile(true)
  wood:SetVertexColor(0.62, 0.55, 0.50)

  glow = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
  glow:SetTexture(ns.MEDIA .. "glow")
  glow:SetPoint("BOTTOMLEFT", inside, "BOTTOMLEFT", 0, 0)
  glow:SetPoint("BOTTOMRIGHT", inside, "BOTTOMRIGHT", 0, 0)
  glow:SetHeight(WIN_H * 0.55)
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(C.ember[1], C.ember[2], C.ember[3], 0.32)

  local vignette = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
  vignette:SetAllPoints(inside)
  vignette:SetTexture(ns.MEDIA .. "vignette")
  vignette:SetAlpha(0.85)

  if blizzard then
    SetTitle = function(text)
      if frame.SetTitle then
        frame:SetTitle(text)
      else
        local fs = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
        if fs then fs:SetText(text) end
      end
    end
    SetPortrait = function(path)
      if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(path)
      else
        local p = frame.portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
        if p then
          if SetPortraitToTexture then SetPortraitToTexture(p, path) else p:SetTexture(path) end
        end
      end
    end
    if frame.CloseButton then
      UI.Tooltip(frame.CloseButton, "Close", "Your game is kept. /campfire opens it again.")
    end
  else
    SetTitle, SetPortrait = DrawOwnEdge(frame)
  end
  SetTitle(ns.TITLE)
  SetPortrait(CAMPFIRE)

  -- String lights hanging just under the title bar, clear of the buttons.
  local n = 9
  local x0, x1 = 70, WIN_W - 14
  for i = 1, n do
    local d = frame:CreateTexture(nil, "ARTWORK")
    d:SetTexture(ns.MEDIA .. "dot")
    d:SetBlendMode("ADD")
    local x = x0 + (i - 1) * ((x1 - x0) / (n - 1))
    local sag = math.sin((i - 1) / (n - 1) * math.pi) * 2
    d:SetSize(10, 10)
    d:SetPoint("CENTER", frame, "TOPLEFT", x, -24 - sag)
    d:SetVertexColor(C.blue[1], C.blue[2], C.blue[3], 0.6)
    lights[i] = { tex = d, phase = math.random() * 6.28, speed = 0.6 + math.random() * 0.8 }
  end
  function ns.UpdateLights()
    for _, l in ipairs(lights) do l.tex:SetShown(ns.db.lights) end
  end
  ns.UpdateLights()

  -- The row under the title bar, right of the portrait: a breadcrumb bar
  -- like the world map's (Games > Ricochet, with a list of the other games),
  -- and round buttons at its right end. The bar has a fixed width: it only
  -- ever holds two steps, so nothing needs to fold away.
  local nav = CreateFrame("Frame", nil, frame)
  -- Explicit sizes: a hidden window may not have worked out anchored widths
  -- yet, and the bar measures itself when buttons are added.
  local NAV_W = WIN_W - 62 - PAD
  nav:SetPoint("TOPLEFT", 62, ROW_Y + 4)
  nav:SetSize(NAV_W, NAV_H)
  local navLabel = false   -- current page name on the bar (false = not set yet)
  local navBlizzard = false

  local function HomeClick()
    if current ~= "menu" then ShowPage("menu") end
  end

  -- The other games, for the dropdown on the second step.
  local function GameList()
    local list = {}
    for i, g in ipairs(ns.games) do
      list[#list + 1] = {
        text = g.name, id = i,
        func = function(_, id) ShowPage(ns.games[id].key) end,
      }
    end
    return list
  end

  -- Blizzard's navigation bar (world map, Encounter Journal), if the client has it.
  if UI.HasTemplate("NavBarTemplate") and NavBar_Initialize and NavBar_AddButton and NavBar_Reset then
    local ok = pcall(function()
      local bar = CreateFrame("Frame", "DowntimeNavBar", nav, "NavBarTemplate")
      bar:SetPoint("TOPLEFT")
      bar:SetSize(NAV_W, NAV_H)
      NavBar_Initialize(bar, "NavButtonTemplate", { name = "Games", OnClick = HomeClick }, bar.home, bar.overflow)
      -- Blizzard sized the home button for "Home"; fit it to "Games".
      local fs = bar.home and bar.home:GetFontString()
      if fs then bar.home:SetWidth(math.min(128, fs:GetStringWidth() + 50)) end
      nav.bar = bar
    end)
    navBlizzard = ok and nav.bar ~= nil
  end

  -- Our own breadcrumb otherwise: arrow-ended segments.
  local homeSeg, hereSeg
  if not navBlizzard then
    local bg = nav:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    UI.Border(nav, C.lineDark)
    local SEG_H = NAV_H - 8
    local function Segment(level, color)
      local b = CreateFrame("Button", nil, nav)
      b:SetHeight(SEG_H)
      b:SetFrameLevel(nav:GetFrameLevel() + level)
      b.body = b:CreateTexture(nil, "ARTWORK")
      b.body:SetTexture(ns.MEDIA .. "nav_body")
      b.body:SetPoint("TOPLEFT")
      b.body:SetPoint("BOTTOMRIGHT", -CAP_W, 0)
      b.cap = b:CreateTexture(nil, "ARTWORK")
      b.cap:SetTexture(ns.MEDIA .. "nav_cap")
      b.cap:SetSize(CAP_W, SEG_H)
      b.cap:SetPoint("LEFT", b.body, "RIGHT")
      b.text = UI.Text(b, 12, C.gold)
      b.text:SetPoint("LEFT", 8, 1)
      function b:Tint(k)
        k = k or 1
        self.body:SetVertexColor(color[1] * k, color[2] * k, color[3] * k)
        self.cap:SetVertexColor(color[1] * k, color[2] * k, color[3] * k)
      end
      function b:Label(t, extra)
        self.text:SetText(t)
        self:SetWidth(math.ceil(self.text:GetStringWidth()) + 18 + CAP_W + (extra or 0))
      end
      b:Tint()
      return b
    end
    homeSeg = Segment(3, { 0.62, 0.13, 0.08 })
    homeSeg:SetPoint("LEFT", nav, "LEFT", 4, 0)
    homeSeg:Label("Games")
    homeSeg:SetScript("OnEnter", function(self) self:Tint(1.3) end)
    homeSeg:SetScript("OnLeave", function(self) self:Tint() end)
    homeSeg:SetScript("OnClick", function() ns.Sound("click"); HomeClick() end)
    hereSeg = Segment(2, { 0.36, 0.22, 0.10 })
    hereSeg:SetPoint("LEFT", homeSeg, "RIGHT", -CAP_W, 0)   -- tucks under the home tip
    hereSeg.text:SetPoint("LEFT", CAP_W + 6, 1)
    hereSeg:EnableMouse(false)
    hereSeg:Hide()
  end

  -- Show "Games" alone on the menu, "Games > Page" elsewhere.
  function ns.SetNav(label, isGame)
    if navLabel == label then return end
    navLabel = label
    if navBlizzard then
      local ok, err = pcall(function()
        NavBar_Reset(nav.bar)
        if label then
          NavBar_AddButton(nav.bar, {
            name = label, id = label,
            OnClick = function() end,
            listFunc = isGame and GameList or nil,
          })
        end
      end)
      if not ok and not ns.navWarned then
        ns.navWarned = true
        print("|cffffd173" .. ns.TITLE .. "|r: nav bar error: " .. tostring(err))
      end
    else
      hereSeg:SetShown(label ~= nil)
      if label then hereSeg:Label(label, CAP_W) end
    end
  end

  -- Round buttons sit over the right end of the bar.
  local top = nav:GetFrameLevel() + 80

  -- Menu page: scores, options, trophies.
  menuButtons = CreateFrame("Frame", nil, frame)
  menuButtons:SetFrameLevel(top)
  menuButtons:SetSize(3 * 31 + 2 * 2, 31)
  menuButtons:SetPoint("RIGHT", nav, "RIGHT", -2, 0)
  local scores = UI.RoundButton(menuButtons, "Interface\\Icons\\INV_Misc_Note_01", "Scores", "Plays, wins and best scores for every game.")
  scores:SetPoint("LEFT")
  scores:SetScript("OnClick", function() ShowPage("scores") end)
  local options = UI.RoundButton(menuButtons, "Interface\\Icons\\INV_Misc_Gear_01", "Options")
  options:SetPoint("LEFT", scores, "RIGHT", 2, 0)
  options:SetScript("OnClick", function() ShowPage("options") end)
  local trophiesButton = UI.RoundButton(menuButtons, "Interface\\Icons\\Achievement_General", "Trophies")
  trophiesButton:SetPoint("LEFT", options, "RIGHT", 2, 0)
  trophiesButton:SetScript("OnClick", function() ShowPage("trophies") end)

  -- How to play: hover the magnifier for the rules, click for a bigger panel.
  local helpPanel = CreateFrame("Frame", nil, frame)
  helpPanel:SetSize(ns.GAME_W, ns.GAME_H)
  helpPanel:SetPoint("TOPLEFT", PAD, -HEADER)
  helpPanel:SetFrameLevel(frame:GetFrameLevel() + 300)
  helpPanel:EnableMouse(true)
  local hbg = helpPanel:CreateTexture(nil, "BACKGROUND")
  hbg:SetAllPoints()
  hbg:SetColorTexture(0.05, 0.035, 0.02, 0.985)
  UI.Border(helpPanel, C.line)
  local hTitle = UI.Title(helpPanel, 18)
  hTitle:SetPoint("TOP", 0, -14)
  hTitle:SetText("How to play")
  local hText = UI.Text(helpPanel, 13, C.cream)
  hText:SetPoint("TOPLEFT", 16, -46)
  hText:SetWidth(ns.GAME_W - 32)
  hText:SetJustifyH("LEFT")
  hText:SetSpacing(3)
  local hOk = UI.Button(helpPanel, "Got it", 100, 22)
  hOk:SetPoint("BOTTOM", 0, 14)
  hOk:SetScript("OnClick", function() helpPanel:Hide() end)
  helpPanel:Hide()
  ns.helpPanel = helpPanel

  local helpButton = UI.SearchButton(frame, function()
    local g = currentGame
    if not (g and ns.HELP and ns.HELP[g.key]) then return end
    GameTooltip:SetText("How to play " .. g.name)
    GameTooltip:AddLine(ns.HELP[g.key], 1, 1, 1, true)
    GameTooltip:AddLine("Click to keep it open.", 0.6, 0.6, 0.6)
  end)
  helpButton:SetFrameLevel(top)
  helpButton:SetPoint("RIGHT", nav, "RIGHT", -6, 0)
  helpButton:SetScript("OnClick", function()
    GameTooltip:Hide()
    if helpPanel:IsShown() then
      helpPanel:Hide()
    elseif currentGame and ns.HELP and ns.HELP[currentGame.key] then
      hText:SetText(ns.HELP[currentGame.key])
      helpPanel:Show()
    end
  end)
  ns.helpButton = helpButton

  -- Drag to move
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
    PlaceFrame()
  end)

  -- Corner grip scales the whole window.
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetFrameLevel(frame:GetFrameLevel() + 20)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function(self)
    local s = frame:GetScale()
    local ui = UIParent:GetEffectiveScale()
    self.startX = GetCursorPosition() / ui
    self.startScale = s
    self.width = frame:GetWidth() * s
    self.left, self.top = frame:GetLeft() * s, frame:GetTop() * s
    self:SetScript("OnUpdate", function()
      local dx = GetCursorPosition() / ui - self.startX
      local new = self.startScale * (self.width + dx) / self.width
      new = math.max(MIN_SCALE, math.min(MAX_SCALE, new))
      frame:SetScale(new)
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.left / new, self.top / new)
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    ns.db.scale = frame:GetScale()
    SavePosition()
  end)

  -- Firelight and twinkling lights.
  local t = 0
  local fade = 1
  local trophyClock = 0
  frame:SetScript("OnUpdate", function(_, dt)
    ns.db.timeByFire = (ns.db.timeByFire or 0) + dt
    ns.TickAmbience(dt)
    trophyClock = trophyClock + dt
    if trophyClock > 60 then
      trophyClock = 0
      ns.CheckTrophies()
    end
    -- See-through while the mouse is away (if turned on).
    local want = 1
    if ns.db.seeThrough and not frame:IsMouseOver() then
      want = ns.db.seeThroughAlpha or 0.45
    end
    if math.abs(fade - want) < 0.01 then
      if fade ~= want then fade = want; frame:SetAlpha(fade) end
    else
      fade = fade + (want - fade) * math.min(1, dt * 6)
      frame:SetAlpha(fade)
    end
    if not ns.db.flicker then return end
    t = t + dt
    local f = 0.30 + math.sin(t * 2.1) * 0.025 + math.sin(t * 5.3 + 1) * 0.015 + math.sin(t * 11.7) * 0.01
    glow:SetAlpha(f / 0.32)
    for _, l in ipairs(lights) do
      l.tex:SetAlpha(0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * l.speed + l.phase)))
    end
  end)

  frame:SetScript("OnKeyDown", OnKeyDown)
  frame:SetScript("OnShow", function()
    ns.Sound("open")
    ns.UpdateAmbience()
    if currentGame and currentGame.OnShow then currentGame.OnShow() end
    if current == "menu" then RefreshMenu() end
    ns.UpdateKeyboard()
  end)
  frame:SetScript("OnHide", function()
    ns.Sound("close")
    ns.UpdateAmbience()
    -- Hidden mid-drag or mid-resize (combat, Esc): let go cleanly.
    frame:StopMovingOrSizing()
    if grip:GetScript("OnUpdate") then
      grip:SetScript("OnUpdate", nil)
      ns.db.scale = frame:GetScale()
      SavePosition()
    end
    if currentGame and currentGame.OnHide then currentGame.OnHide() end
    ns.UpdateKeyboard()
  end)

  -- "Trophy earned" banner across the top of the window.
  local banner = CreateFrame("Frame", nil, frame)
  banner:SetSize(WIN_W - 40, 46)
  banner:SetPoint("TOP", 0, -30)
  banner:SetFrameLevel(frame:GetFrameLevel() + 320)
  local bbg = banner:CreateTexture(nil, "BACKGROUND")
  bbg:SetAllPoints()
  bbg:SetColorTexture(0.06, 0.04, 0.02, 0.94)
  UI.Border(banner, C.gold)
  local bglow = banner:CreateTexture(nil, "BORDER")
  bglow:SetTexture(ns.MEDIA .. "glow")
  bglow:SetAllPoints()
  bglow:SetBlendMode("ADD")
  bglow:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.25)
  local bIconFrame = CreateFrame("Frame", nil, banner)
  bIconFrame:SetSize(34, 34)
  bIconFrame:SetPoint("LEFT", 6, 0)
  local bIcon = bIconFrame:CreateTexture(nil, "ARTWORK")
  bIcon:SetPoint("TOPLEFT", 1, -1)
  bIcon:SetPoint("BOTTOMRIGHT", -1, 1)
  UI.Border(bIconFrame, C.gold)
  local bTop = UI.Text(banner, 10, C.dim)
  bTop:SetPoint("TOPLEFT", bIconFrame, "TOPRIGHT", 8, -2)
  bTop:SetText("Trophy earned")
  local bName = UI.Title(banner, 15)
  bName:SetPoint("BOTTOMLEFT", bIconFrame, "BOTTOMRIGHT", 8, 1)
  banner:Hide()
  local queue = {}
  banner:SetScript("OnUpdate", function(self, dt)
    self.age = self.age + dt
    local a
    if self.age < 0.3 then a = self.age / 0.3
    elseif self.age < 3.5 then a = 1
    else a = 1 - (self.age - 3.5) / 0.6 end
    if a <= 0 then
      table.remove(queue, 1)
      if queue[1] then self:Play(queue[1]) else self:Hide() end
      return
    end
    self:SetAlpha(a)
  end)
  function banner:Play(t)
    -- Float just outside the window so it doesn't cover the game: above it,
    -- or below it when the window sits near the top of the screen.
    self:ClearAllPoints()
    local top = (frame:GetTop() or 0) * frame:GetEffectiveScale()
    local screenTop = UIParent:GetTop() * UIParent:GetEffectiveScale()
    if top + 60 * frame:GetEffectiveScale() < screenTop then
      self:SetPoint("BOTTOM", frame, "TOP", 0, 6)
    else
      self:SetPoint("TOP", frame, "BOTTOM", 0, -6)
    end
    local g = t[2] and ns.gamesByKey[t[2]]
    bIcon:SetTexture(g and g.icon or (ns.MEDIA .. "icons\\downtime"))
    bName:SetText(t[3])
    self.age = 0
    self:SetAlpha(0)
    self:Show()
    ns.PlayTone("chime")
  end
  function ns.ShowTrophyBanner(t)
    if not frame:IsShown() then return end
    queue[#queue + 1] = t
    if #queue == 1 then banner:Play(t) end
  end

  tinsert(UISpecialFrames, "DowntimeFrame")
  PlaceFrame()
end

-------------------------------------------------------------------------------
-- Minimap button: click to open, drag around the minimap edge
-------------------------------------------------------------------------------

local minimapButton

local function PlaceMinimapButton()
  local a = math.rad(ns.db.minimapAngle or 210)
  local r = (Minimap:GetWidth() / 2) + 10
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function ns.UpdateMinimapButton()
  if minimapButton then minimapButton:SetShown(ns.db.minimap) end
end

local function BuildMinimapButton()
  if not Minimap then return end
  local b = CreateFrame("Button", "DowntimeMinimapButton", Minimap)
  minimapButton = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ns.MEDIA .. "icons\\downtime")
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      frame:Show()
      ShowPage("options")
    else
      ns.Toggle()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local sc = Minimap:GetEffectiveScale()
      ns.db.minimapAngle = math.deg(math.atan2(py / sc - my, px / sc - mx))
      PlaceMinimapButton()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(ns.TITLE, C.gold[1], C.gold[2], C.gold[3])
    GameTooltip:AddLine("Click to open or close.", C.cream[1], C.cream[2], C.cream[3])
    GameTooltip:AddLine("Right-click for options. Drag to move.", C.dim[1], C.dim[2], C.dim[3])
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  PlaceMinimapButton()
  ns.UpdateMinimapButton()
end

-------------------------------------------------------------------------------
-- Fireside crackle: a quiet campfire loop on the Ambience channel while the
-- window is open (if turned on).
-------------------------------------------------------------------------------

local FIRE_FILE = ns.MEDIA .. "sounds\\fire.ogg"
local FIRE_LEN = 22.9
local fireHandle, fireTimer = nil, 0

local function StopFire()
  if fireHandle then
    StopSound(fireHandle, 800)
    fireHandle = nil
  end
end

local function StartFire()
  StopFire()
  local ok, handle = PlaySoundFile(FIRE_FILE, "Ambience")
  if ok then fireHandle = handle end
  fireTimer = 0
end

function ns.UpdateAmbience()
  if ns.db.ambience and frame and frame:IsShown() then
    if not fireHandle then StartFire() end
  else
    StopFire()
  end
end

-- Called from the window's OnUpdate to restart the loop when it runs out.
function ns.TickAmbience(dt)
  if not fireHandle then return end
  fireTimer = fireTimer + dt
  if fireTimer >= FIRE_LEN then
    local old = fireHandle
    local ok, handle = PlaySoundFile(FIRE_FILE, "Ambience")
    fireHandle = ok and handle or nil
    fireTimer = 0
    if old then StopSound(old, 600) end
  end
end

-------------------------------------------------------------------------------
-- Opening, closing, combat
-------------------------------------------------------------------------------

function ns.Toggle()
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

function Downtime_OnAddonCompartmentClick()
  ns.Toggle()
end

-- Key binding (Bindings.xml loads on its own; it isn't listed in the TOC).
BINDING_HEADER_DOWNTIME = ns.TITLE
BINDING_NAME_DOWNTIME_TOGGLE = "Open or close the window"
function Downtime_Toggle()
  if frame then ns.Toggle() end
end

local reopenAfterCombat = false

-- Fishing: known Fishing spell IDs, plus whatever the client calls Fishing
-- (so other languages and other ranks match too).
local FISHING_IDS = {
  [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true,
  [51294] = true, [88868] = true, [110410] = true, [131474] = true, [131476] = true,
  [131490] = true, [158743] = true, [271990] = true, [271991] = true,
}
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function IsFishing(id)
  if not id then return false end
  if FISHING_IDS[id] then return true end
  local name = SpellName(id)
  return name ~= nil and (name == SpellName(7620) or name == SpellName(131474))
end

local function OpenQuietly()
  if frame and not frame:IsShown() and not InCombatLockdown() then frame:Show() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterEvent("PLAYER_CONTROL_LOST")
events:SetScript("OnEvent", function(self, event, arg, arg2, arg3)
  if event == "UNIT_SPELLCAST_CHANNEL_START" then
    if ns.db and ns.db.openFishing and IsFishing(arg3) then OpenQuietly() end
    return
  elseif event == "PLAYER_CONTROL_LOST" then
    -- Flight paths take control away; check a moment later that it's a taxi.
    if ns.db and ns.db.openTaxi then
      C_Timer.After(0.5, function()
        if UnitOnTaxi and UnitOnTaxi("player") then OpenQuietly() end
      end)
    end
    return
  end
  if event == "ADDON_LOADED" then
    if arg ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    ns.LoadDB()
    BuildFrame()
    BuildMenu()
    BuildScores()
    BuildOptions()
    BuildSettingsPanel()
    BuildTrophies()
    BuildMinimapButton()
    ns.CheckTrophies(true)
    for _, g in ipairs(ns.games) do NewPage(g.key) end
    if not ns.db.welcomed then
      ns.db.welcomed = true
      print("|cffffd173" .. ns.TITLE .. "|r: pull up a chair. Type /campfire or click the minimap button to play.")
    end
    local last = ns.db.lastGame
    ShowPage((last and ns.gamesByKey[last]) and last or "menu")
  elseif event == "PLAYER_REGEN_DISABLED" then
    if frame then frame:EnableKeyboard(false) end
    if ns.db and ns.db.hideInCombat and frame and frame:IsShown() then
      reopenAfterCombat = true
      frame:Hide()
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    ns.UpdateKeyboard()
    if reopenAfterCombat and frame then
      reopenAfterCombat = false
      frame:Show()
    end
  end
end)

SLASH_DOWNTIME1 = "/campfire"
SLASH_DOWNTIME2 = "/games"
SlashCmdList.DOWNTIME = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "options" or msg == "settings" then
    ns.OpenSettings()
  elseif msg == "reset" then
    ns.db.x, ns.db.y, ns.db.scale = nil, nil, ns.DEFAULT_SCALE
    PlaceFrame()
    frame:Show()
    print("|cffffd173" .. ns.TITLE .. "|r: window size and place reset.")
  elseif ns.gamesByKey[msg] then
    frame:Show()
    ShowPage(msg)
  else
    ns.Toggle()
  end
end
