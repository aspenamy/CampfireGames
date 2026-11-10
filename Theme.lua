-------------------------------------------------------------------------------
-- Campfire Games: look and shared widgets
--
-- Warm tavern colors: dark wood, candle gold, firelight orange, with a few
-- small blue lights. Games should build with these helpers so everything
-- matches.
-------------------------------------------------------------------------------

local _, ns = ...

ns.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
ns.FONT_TITLE = "Fonts\\MORPHEUS.TTF"

ns.C = {
  gold      = { 1.00, 0.82, 0.45 },
  cream     = { 0.96, 0.90, 0.78 },
  dim       = { 0.68, 0.60, 0.48 },
  faint     = { 0.45, 0.39, 0.31 },
  ember     = { 1.00, 0.55, 0.20 },
  blue      = { 0.50, 0.75, 1.00 },
  red       = { 1.00, 0.42, 0.34 },
  green     = { 0.60, 0.90, 0.50 },
  line      = { 0.55, 0.42, 0.22 },
  lineDark  = { 0.20, 0.13, 0.07 },
  wood      = { 0.24, 0.15, 0.08 },
  woodHover = { 0.33, 0.21, 0.11 },
  woodDown  = { 0.17, 0.10, 0.05 },
  inset     = { 0.07, 0.05, 0.035 },
  insetHi   = { 0.12, 0.09, 0.06 },
  selected  = { 0.45, 0.32, 0.12 },
}
local C = ns.C

local UI = {}
ns.UI = UI

function UI.Color(tex, c, a)
  tex:SetColorTexture(c[1], c[2], c[3], a or 1)
end

function UI.SetTextColor(fs, c, a)
  fs:SetTextColor(c[1], c[2], c[3], a or 1)
end

-- A font string with a soft shadow.
function UI.Text(parent, size, color, font, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(font or ns.FONT, size or 12, "")
  fs:SetShadowColor(0, 0, 0, 0.9)
  fs:SetShadowOffset(1, -1)
  UI.SetTextColor(fs, color or C.cream)
  return fs
end

function UI.Title(parent, size, color)
  return UI.Text(parent, size or 16, color or C.gold, ns.FONT_TITLE)
end

-- Thin lines around a frame. Returns the four textures.
function UI.Border(frame, color, size, layer, alpha)
  size = size or 1
  local t = {}
  for i = 1, 4 do
    local tex = frame:CreateTexture(nil, layer or "BORDER")
    UI.Color(tex, color or C.line, alpha)
    t[i] = tex
  end
  t[1]:SetPoint("TOPLEFT"); t[1]:SetPoint("TOPRIGHT"); t[1]:SetHeight(size)
  t[2]:SetPoint("BOTTOMLEFT"); t[2]:SetPoint("BOTTOMRIGHT"); t[2]:SetHeight(size)
  t[3]:SetPoint("TOPLEFT"); t[3]:SetPoint("BOTTOMLEFT"); t[3]:SetWidth(size)
  t[4]:SetPoint("TOPRIGHT"); t[4]:SetPoint("BOTTOMRIGHT"); t[4]:SetWidth(size)
  return t
end

function UI.SetBorderColor(border, c, a)
  for i = 1, 4 do UI.Color(border[i], c, a) end
end

-- A dark sunken panel with a thin warm edge.
function UI.Inset(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  if w then f:SetSize(w, h) end
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  UI.Color(f.bg, C.inset, 0.85)
  f.border = UI.Border(f, C.lineDark)
  return f
end

local function HasTemplate(name)
  if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
    return C_XMLUtil.GetTemplateInfo(name) ~= nil
  end
  return true
end
UI.HasTemplate = HasTemplate

local WoodButton

-- WoW's standard red button with gold text, like the Game Menu's.
-- b:SetSelected(true) for toggles: it stays lit with white text.
-- Falls back to a wooden button on clients without the template.
function UI.Button(parent, text, w, h, size)
  local b
  if HasTemplate("UIPanelButtonTemplate") then
    local ok, made = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
    if ok then b = made end
  end
  if not b then return WoodButton(parent, text, w, h, size) end
  b:SetSize(w or 90, h or 22)
  if size and size <= 10 and GameFontNormalSmall then
    b:SetNormalFontObject(GameFontNormalSmall)
    b:SetHighlightFontObject(GameFontHighlightSmall)
    if GameFontDisableSmall then b:SetDisabledFontObject(GameFontDisableSmall) end
  end
  b:SetText(text or "")
  b.label = b:GetFontString()
  function b:SetSelected(on)
    self.selected = on and true or false
    if self.selected then self:LockHighlight() else self:UnlockHighlight() end
  end
  b.Paint = function(self) self:SetSelected(self.selected) end
  b:SetScript("PreClick", function(self) if not self.quiet then ns.Sound("click") end end)
  return b
end

-- A wooden button with gold text, for clients without WoW's button template.
function WoodButton(parent, text, w, h, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 90, h or 22)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  UI.Color(b.bg, C.wood)
  b.shine = b:CreateTexture(nil, "BORDER")
  b.shine:SetPoint("TOPLEFT", 1, -1)
  b.shine:SetPoint("TOPRIGHT", -1, -1)
  b.shine:SetHeight(1)
  b.shine:SetColorTexture(1, 0.85, 0.55, 0.18)
  b.border = UI.Border(b, C.line)
  local fs = UI.Text(b, size or 12, C.gold)
  -- WoW fonts leave room below for descenders; lift a pixel so caps look centered.
  fs:SetPoint("CENTER", 0, 1)
  -- A plain child, not the button's own font string: WoW moves a button's
  -- font string around when it's pressed, which left some labels off center.
  b.label = fs
  function b:SetText(t) self.label:SetText(t) end
  function b:GetText() return self.label:GetText() end
  function b:GetFontString() return self.label end
  b:SetText(text or "")

  local function Paint(self)
    local c
    if not self:IsEnabled() then
      c = C.woodDown
    elseif self.down then
      c = C.woodDown
    elseif self.selected then
      c = C.selected
    elseif self.hover then
      c = C.woodHover
    else
      c = C.wood
    end
    UI.Color(self.bg, c)
    UI.SetTextColor(self.label, self:IsEnabled() and (self.selected and C.cream or C.gold) or C.faint)
    UI.SetBorderColor(self.border, (self.hover and self:IsEnabled()) and C.gold or C.line, (self.hover and self:IsEnabled()) and 0.9 or 1)
  end
  b.Paint = Paint
  b:SetScript("OnEnter", function(self) self.hover = true; Paint(self) end)
  b:SetScript("OnLeave", function(self) self.hover = false; self.down = false; Paint(self) end)
  b:SetScript("OnMouseDown", function(self)
    if not self:IsEnabled() then return end
    self.down = true
    Paint(self)
  end)
  b:SetScript("OnMouseUp", function(self)
    self.down = false
    Paint(self)
  end)
  b:SetScript("OnEnable", Paint)
  b:SetScript("OnDisable", Paint)
  function b:SetSelected(on)
    self.selected = on and true or false
    Paint(self)
  end
  -- PreClick so games can SetScript("OnClick") freely.
  b:SetScript("PreClick", function(self) if not self.quiet then ns.Sound("click") end end)
  Paint(b)
  return b
end

-- A round button like the minimap's (tracking, calendar): dark disc, icon,
-- gold ring, standard round highlight. Hovering shows a tooltip: tip is a
-- title, or a function(self) that fills GameTooltip.
function UI.RoundButton(parent, icon, tip, text)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(31, 31)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg = bg
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(icon)
  b.icon:SetSize(19, 19)
  b.icon:SetPoint("CENTER", bg, "CENTER", 0, 0)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  if b.icon.SetMask then b.icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end
  local ring = b:CreateTexture(nil, "OVERLAY")
  b.ring = ring
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(53, 53)
  ring:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if type(tip) == "function" then
      tip(self)
    else
      GameTooltip:SetText(tip or "")
      if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("PreClick", function() ns.Sound("click") end)
  b:SetScript("OnMouseDown", function() b.icon:SetVertexColor(0.7, 0.7, 0.7) end)
  b:SetScript("OnMouseUp", function() b.icon:SetVertexColor(1, 1, 1) end)
  return b
end

-- The help button copies the minimap's tracking button (the little gold
-- magnifying glass). Every texture on that button is cloned at the same
-- size and spot, so it matches whatever this client draws there. Until the
-- minimap is found it shows the classic tracking glass in a round frame.
local function DebugName(f)
  local n = (f.GetDebugName and f:GetDebugName()) or (f.GetName and f:GetName())
  return type(n) == "string" and n or ""
end

local function FindTracking()
  local mc = _G.MinimapCluster
  local direct = {
    mc and rawget(mc, "Tracking"), mc and rawget(mc, "TrackingFrame"),
    _G.MiniMapTracking, _G.MiniMapTrackingFrame, _G.MiniMapTrackingButton,
  }
  for i = 1, 5 do
    local f = direct[i]
    if type(f) == "table" and f.GetRegions and f.IsShown and f:IsShown() then return f end
  end
  -- Otherwise look under the minimap for anything named like it.
  local found
  local function Walk(f, depth)
    if found or depth > 4 or type(f) ~= "table" or not f.GetChildren then return end
    for _, c in ipairs({ f:GetChildren() }) do
      if c:IsShown() and DebugName(c):lower():find("tracking") then found = c; return end
      Walk(c, depth + 1)
    end
  end
  Walk(mc, 1)
  Walk(_G.Minimap, 1)
  return found
end

-- Copy every visible texture of root (and its children) onto b.
local function CloneLook(root, b)
  local rw, rh = root:GetSize()
  local rx, ry = root:GetCenter()
  if not (rx and rw and rw > 0 and rh > 0) then return false end
  local size = math.max(20, math.min(30, math.max(rw, rh)))
  local k = size / math.max(rw, rh)
  local skip, hl = {}, nil
  local copies = {}
  local function Visit(f, depth)
    if depth > 3 then return end
    if f:IsObjectType("Button") then
      local h = f:GetHighlightTexture()
      if h then skip[h] = true; hl = hl or h end
      for _, g in ipairs({ "GetPushedTexture", "GetDisabledTexture" }) do
        local t = f[g] and f[g](f)
        if t then skip[t] = true end
      end
    end
    for _, r in ipairs({ f:GetRegions() }) do
      if not skip[r] and r.IsObjectType and r:IsObjectType("Texture") and r:IsShown() then
        local x, y = r:GetCenter()
        local w, h = r:GetSize()
        local atlas = r.GetAtlas and r:GetAtlas()
        local file = not atlas and r:GetTexture()
        if x and w and w > 0 and (atlas or file) then
          copies[#copies + 1] = { r = r, x = x - rx, y = y - ry, w = w, h = h, atlas = atlas, file = file }
        end
      end
    end
    for _, c in ipairs({ f:GetChildren() }) do
      if c:IsShown() then Visit(c, depth + 1) end
    end
  end
  Visit(root, 1)
  if #copies == 0 then return false end
  b:SetSize(size, size)
  for _, c in ipairs(copies) do
    local layer, sub = c.r:GetDrawLayer()
    local t = b:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    if c.atlas then t:SetAtlas(c.atlas) else t:SetTexture(c.file); t:SetTexCoord(c.r:GetTexCoord()) end
    t:SetVertexColor(c.r:GetVertexColor())
    if c.r.GetBlendMode then t:SetBlendMode(c.r:GetBlendMode()) end
    t:SetSize(c.w * k, c.h * k)
    t:SetPoint("CENTER", b, "CENTER", c.x * k, c.y * k)
  end
  if hl then
    local a = hl.GetAtlas and hl:GetAtlas()
    if a then b:SetHighlightAtlas(a, "ADD") else b:SetHighlightTexture(hl:GetTexture(), "ADD") end
  end
  return true
end

function UI.SearchButton(parent, tip, text)
  local b = UI.RoundButton(parent, "Interface\\Minimap\\Tracking\\None", tip, text)
  -- Called each time the button is shown: a few tries, in case the minimap
  -- isn't laid out yet.
  function b.TryClone(self)
    if self.cloned or (self.tries or 0) >= 5 then return end
    self.tries = (self.tries or 0) + 1
    local ok, root = pcall(FindTracking)
    if not (ok and root) then return end
    local done, res = pcall(CloneLook, root, self)
    if done and res then
      self.cloned = true
      self.bg:Hide(); self.icon:Hide(); self.ring:Hide()
    end
  end
  b:HookScript("OnShow", b.TryClone)
  return b
end

-- WoW's standard checkbox with a label. get() returns the value, set(v)
-- saves it. The box plus its gap is 22 wide, as games lay them out.
function UI.Check(parent, label, get, set)
  if HasTemplate("UICheckButtonTemplate") then
    local ok, c = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
    if ok and c then
      c:SetSize(24, 24)
      c.text = c.Text or c.text
      if not c.text then
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      end
      c.text:ClearAllPoints()
      c.text:SetPoint("LEFT", c, "RIGHT", -2, 1)
      c.text:SetText(label)
      c:SetHitRectInsets(0, -(c.text:GetStringWidth() + 4), 0, 0)
      function c:Refresh()
        self:SetChecked(get() and true or false)
      end
      c:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns.Sound("click")
      end)
      c:Refresh()
      return c
    end
  end
  local c = CreateFrame("Button", nil, parent)
  c:SetSize(16, 16)
  c.bg = c:CreateTexture(nil, "BACKGROUND")
  c.bg:SetAllPoints()
  UI.Color(c.bg, C.inset)
  c.border = UI.Border(c, C.line)
  c.mark = c:CreateTexture(nil, "ARTWORK")
  c.mark:SetPoint("TOPLEFT", 4, -4)
  c.mark:SetPoint("BOTTOMRIGHT", -4, 4)
  UI.Color(c.mark, C.gold)
  c.text = UI.Text(c, 12, C.cream)
  c.text:SetPoint("LEFT", c, "RIGHT", 6, 0)
  c.text:SetText(label)
  c:SetHitRectInsets(0, -(c.text:GetStringWidth() + 8), -2, -2)
  function c:Refresh()
    self.mark:SetShown(get() and true or false)
  end
  c:SetScript("OnClick", function(self)
    set(not get())
    ns.Sound("click")
    self:Refresh()
  end)
  c:SetScript("OnEnter", function(self) UI.SetBorderColor(self.border, C.gold) end)
  c:SetScript("OnLeave", function(self) UI.SetBorderColor(self.border, C.line) end)
  c:Refresh()
  return c
end

-- Hover text for any frame.
function UI.Tooltip(frame, title, text)
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, C.gold[1], C.gold[2], C.gold[3])
    if text then GameTooltip:AddLine(text, C.cream[1], C.cream[2], C.cream[3], true) end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A cover over a game area for "You win" moments. o:Open(title, line) /
-- o:Close(). Add buttons to o.buttons (a frame under the text).
function UI.Overlay(parent)
  local o = CreateFrame("Frame", nil, parent)
  o:SetAllPoints()
  o:SetFrameLevel(parent:GetFrameLevel() + 30)
  o:EnableMouse(true)
  o.shade = o:CreateTexture(nil, "BACKGROUND")
  o.shade:SetAllPoints()
  o.shade:SetColorTexture(0.03, 0.02, 0.01, 0.82)
  o.glow = o:CreateTexture(nil, "BORDER")
  o.glow:SetTexture(ns.MEDIA .. "glow")
  o.glow:SetPoint("BOTTOMLEFT", o, "LEFT", 0, -20)
  o.glow:SetPoint("BOTTOMRIGHT", o, "RIGHT", 0, -20)
  o.glow:SetHeight(120)
  o.glow:SetVertexColor(C.ember[1], C.ember[2], C.ember[3], 0.35)
  o.glow:SetBlendMode("ADD")
  o.title = UI.Title(o, 22)
  o.title:SetWidth(parent:GetWidth() - 16)
  o.title:SetPoint("BOTTOM", o, "CENTER", 0, 26)
  o.line = UI.Text(o, 12, C.cream)
  o.line:SetPoint("TOP", o.title, "BOTTOM", 0, -8)
  o.line:SetWidth(parent:GetWidth() - 30)
  o.line:SetJustifyH("CENTER")
  o.line:SetSpacing(3)
  o.buttons = CreateFrame("Frame", nil, o)
  o.buttons:SetSize(parent:GetWidth(), 26)
  o.buttons:SetPoint("TOP", o.line, "BOTTOM", 0, -16)
  function o:Open(title, line)
    self.title:SetText(title or "")
    self.line:SetText(line or "")
    self:Show()
  end
  function o:Close() self:Hide() end
  o:Hide()
  return o
end

-- A short message that fades out over a game ("New best!").
function UI.Toast(parent)
  local t = CreateFrame("Frame", nil, parent)
  t:SetSize(parent:GetWidth(), 30)
  t:SetPoint("CENTER")
  t:SetFrameLevel(parent:GetFrameLevel() + 40)
  t.text = UI.Title(t, 20)
  t.text:SetPoint("CENTER")
  t:Hide()
  t:SetScript("OnUpdate", function(self, dt)
    self.age = self.age + dt
    local a = 1
    if self.age > 1.2 then a = 1 - (self.age - 1.2) / 0.6 end
    if a <= 0 then self:Hide() return end
    self:SetAlpha(a)
  end)
  function t:Say(msg, color)
    self.text:SetText(msg)
    UI.SetTextColor(self.text, color or C.gold)
    self.age = 0
    self:SetAlpha(1)
    self:Show()
  end
  return t
end

-- A row of difficulty / mode buttons that act like radio buttons.
-- options = { {key=, label=}, ... }; onPick(key) is called on click.
function UI.Choice(parent, options, w, onPick)
  local row = CreateFrame("Frame", nil, parent)
  local bw = math.floor((w - (#options - 1) * 4) / #options)
  row:SetSize(w, 22)
  row.buttons = {}
  for i, o in ipairs(options) do
    local b = UI.Button(row, o.label, bw, 22, 11)
    b:SetPoint("LEFT", (i - 1) * (bw + 4), 0)
    b:SetScript("OnClick", function() onPick(o.key) end)
    row.buttons[o.key] = b
  end
  function row:Select(key)
    for k, b in pairs(self.buttons) do b:SetSelected(k == key) end
  end
  return row
end
