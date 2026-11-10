-------------------------------------------------------------------------------
-- Campfire Games: Rune Lock
--
-- A hidden code of four runes from six kinds. Click a rune below to fill the
-- next slot of the current row, then press Unlock. Click a filled slot in the
-- current row to clear it. The pips on the right show how close the guess
-- was: a gold pip is a right rune in the right place, a silver pip is a right
-- rune in the wrong place. You have ten tries.
--
-- Apprentice: no rune repeats in the code. Master: repeats allowed.
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, min = math.floor, math.min

local RUNES = 6
local SLOTS = 4
local TRIES = 10
local MODES = {
  { key = "apprentice", label = "Apprentice" },
  { key = "master", label = "Master" },
}
local MODE_LABEL = { apprentice = "Apprentice", master = "Master" }

local ROW_H = 29
local ROW_INSET = 40          -- row background runs from x 40 to x 280
local BOARD_TOP = -30
local NUM_RIGHT = 78          -- row numbers end here
local SLOT, SLOT_GAP, SLOT_X = 26, 8, 90
local CLUE_X, PIP, PIP_GAP = 240, 10, 3

local GOLD = { 1.00, 0.82, 0.30 }
local SILVER = { 0.86, 0.88, 0.93 }
local PIP_EMPTY = { 0.50, 0.42, 0.30 }

local data                      -- saved: mode, code, rows, input
local rowsUI, palette, codeRunes = {}, {}, {}
local overlay, modeRow, triesText, unlockButton, clearButton

-------------------------------------------------------------------------------
-- Rules
-------------------------------------------------------------------------------

local function NewCode(mode)
  local code = {}
  if mode == "master" then
    for i = 1, SLOTS do code[i] = math.random(RUNES) end
  else
    local pool = {}
    for r = 1, RUNES do pool[r] = r end
    ns.Shuffle(pool)
    for i = 1, SLOTS do code[i] = pool[i] end
  end
  return code
end

-- Standard Mastermind scoring. exact = right rune in the right place. near =
-- right rune in the wrong place, counted only on the positions that are not
-- exact, so no rune is counted twice.
local function Score(guess, code)
  local left, right = {}, {}
  for r = 1, RUNES do left[r], right[r] = 0, 0 end
  local exact = 0
  for i = 1, SLOTS do
    if guess[i] == code[i] then
      exact = exact + 1
    else
      left[code[i]] = left[code[i]] + 1
      right[guess[i]] = right[guess[i]] + 1
    end
  end
  local near = 0
  for r = 1, RUNES do near = near + min(left[r], right[r]) end
  return exact, near
end

local function IsRune(v)
  return type(v) == "number" and v >= 1 and v <= RUNES and v == floor(v)
end

-- Saved data may be old or broken. Every row is scored again so a bad save
-- starts a fresh lock instead of showing wrong clues.
local function ValidGame(d)
  if d.mode ~= "apprentice" and d.mode ~= "master" then return false end
  if type(d.code) ~= "table" or #d.code ~= SLOTS then return false end
  for i = 1, SLOTS do
    if not IsRune(d.code[i]) then return false end
  end
  if d.mode == "apprentice" then
    for i = 1, SLOTS do
      for j = i + 1, SLOTS do
        if d.code[i] == d.code[j] then return false end
      end
    end
  end

  local rows = d.rows
  if type(rows) ~= "table" then return false end
  local count = 0
  for _ in pairs(rows) do count = count + 1 end
  if count ~= #rows or #rows > TRIES then return false end
  local won = false
  for r = 1, #rows do
    local row = rows[r]
    if won or type(row) ~= "table" or type(row.g) ~= "table" or #row.g ~= SLOTS then
      return false
    end
    for i = 1, SLOTS do
      if not IsRune(row.g[i]) then return false end
    end
    local e, n = Score(row.g, d.code)
    if e ~= row.e or n ~= row.n then return false end
    if e == SLOTS then won = true end
  end

  if type(d.input) ~= "table" or #d.input ~= SLOTS then return false end
  for i = 1, SLOTS do
    local v = d.input[i]
    if v ~= 0 and not IsRune(v) then return false end
  end
  return true
end

local function IsWon()
  local n = #data.rows
  return n > 0 and data.rows[n].e == SLOTS
end

local function IsOver()
  return IsWon() or #data.rows >= TRIES
end

local function InputFull()
  for i = 1, SLOTS do
    if data.input[i] == 0 then return false end
  end
  return true
end

local function InputEmpty()
  for i = 1, SLOTS do
    if data.input[i] ~= 0 then return false end
  end
  return true
end

local function StartGame(mode)
  data.mode = mode
  data.code = NewCode(mode)
  data.rows = {}
  data.input = { 0, 0, 0, 0 }
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

-- Raid mark icons have empty margin, so they are drawn a bit larger.
local function RuneTexture(tex, rune, size)
  if ns.UseRaidMarks() then
    tex:SetTexture(ns.RAID_MARKS[ns.PIECE_MARKS[rune]])
    tex:SetSize(size * 1.1, size * 1.1)
  else
    tex:SetTexture(ns.MEDIA .. "runes\\rune" .. rune)
    tex:SetSize(size, size)
  end
end

local function Render()
  local over = IsOver()
  local n = #data.rows
  modeRow:Select(data.mode)
  if over then
    triesText:SetText(IsWon() and format("Solved in %d", n) or "No tries left")
  else
    triesText:SetText(format("Tries left: %d", TRIES - n))
  end

  for r = 1, TRIES do
    local ui = rowsUI[r]
    local current = (not over) and r == n + 1
    UI.Color(ui.bg, current and C.selected or C.inset, current and 0.55 or 0.45)
    UI.SetTextColor(ui.num, current and C.gold or C.faint)

    local guess, e, nn
    if r <= n then
      guess, e, nn = data.rows[r].g, data.rows[r].e, data.rows[r].n
    elseif current then
      guess = data.input
    end

    for i = 1, SLOTS do
      local slot = ui.slots[i]
      local v = guess and guess[i] or 0
      if v ~= 0 then
        RuneTexture(slot.rune, v, 20)
        slot.rune:Show()
      else
        slot.rune:Hide()
      end
      UI.SetBorderColor(slot.border, current and C.line or C.lineDark)
      slot.hl:SetShown(current)
    end

    -- Gold pips first, then silver, then faint empty pips.
    local gold, silver = e or 0, nn or 0
    for k = 1, SLOTS do
      local pip = ui.pips[k]
      if k <= gold then
        pip:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
      elseif k <= gold + silver then
        pip:SetVertexColor(SILVER[1], SILVER[2], SILVER[3], 1)
      else
        pip:SetVertexColor(PIP_EMPTY[1], PIP_EMPTY[2], PIP_EMPTY[3], 0.35)
      end
    end
  end

  for k = 1, RUNES do
    palette[k]:SetAlpha(over and 0.4 or 1)
  end
  unlockButton:SetEnabled((not over) and InputFull())
  clearButton:SetEnabled((not over) and not InputEmpty())
end

-- The cover over the board when the game ends.
local function ShowEnd(newBest)
  local count = #data.rows
  local label = MODE_LABEL[data.mode] or ""
  for i = 1, SLOTS do
    RuneTexture(codeRunes[i], data.code[i], 26)
  end
  if IsWon() then
    local line = format("%s lock, solved in %d %s.", label, count, count == 1 and "try" or "tries")
    local best = data.stats and data.stats["best_" .. data.mode]
    if newBest then
      line = line .. "\nA new best!"
    elseif best then
      line = line .. format("\nBest: %d %s", best, best == 1 and "try" or "tries")
    end
    overlay:Open("The lock opens!", line)
  else
    overlay:Open("The lock holds", format("%s lock, no match in %d tries.", label, count))
  end
end

-------------------------------------------------------------------------------
-- Playing
-------------------------------------------------------------------------------

local function Place(rune)
  if IsOver() then return end
  for i = 1, SLOTS do
    if data.input[i] == 0 then
      data.input[i] = rune
      ns.Sound("place")
      Render()
      return
    end
  end
end

local function ClickSlot(row, i)
  if IsOver() or row ~= #data.rows + 1 or data.input[i] == 0 then return end
  data.input[i] = 0
  ns.Sound("click")
  Render()
end

local function Unlock()
  if IsOver() or not InputFull() then return end
  local guess = { data.input[1], data.input[2], data.input[3], data.input[4] }
  local e, n = Score(guess, data.code)
  data.rows[#data.rows + 1] = { g = guess, e = e, n = n }
  data.input = { 0, 0, 0, 0 }

  local count = #data.rows
  local newBest = false
  if e == SLOTS then
    newBest = ns.RecordResult("runes", {
      won = true, score = count, lowerIsBetter = true, bestKey = "best_" .. data.mode,
    })
    ns.Sound("win")
  elseif count >= TRIES then
    ns.RecordResult("runes", { won = false, score = count, bestKey = "best_" .. data.mode })
    ns.Sound("bad")
  else
    ns.Sound("good")
  end
  Render()
  if IsOver() then ShowEnd(newBest) end
end

local function Clear()
  if IsOver() then return end
  data.input = { 0, 0, 0, 0 }
  Render()
end

local function NewGame(mode)
  StartGame(mode)
  overlay:Close()
  Render()
end

StaticPopupDialogs["DOWNTIME_NEW_RUNES"] = {
  text = "Start a new %s lock? The current one will be lost.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(_, m) NewGame(m) end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- Asks first only when at least one try has been made on a lock still in play.
local function AskNewGame(mode)
  if #data.rows > 0 and not IsOver() then
    StaticPopup_Show("DOWNTIME_NEW_RUNES", MODE_LABEL[mode] or "", nil, mode)
  else
    NewGame(mode)
  end
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function BuildRow(parent, r)
  local ui = { slots = {}, pips = {} }
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(ns.GAME_W, ROW_H - 3)
  row:SetPoint("TOPLEFT", 0, BOARD_TOP - (r - 1) * ROW_H)

  ui.bg = row:CreateTexture(nil, "BACKGROUND")
  ui.bg:SetPoint("TOPLEFT", ROW_INSET, 0)
  ui.bg:SetPoint("BOTTOMRIGHT", -ROW_INSET, 0)

  ui.num = UI.Text(row, 11, C.faint)
  ui.num:SetPoint("TOPRIGHT", row, "TOPLEFT", NUM_RIGHT, -6)
  ui.num:SetText(r)

  for i = 1, SLOTS do
    local slot = CreateFrame("Button", nil, row)
    slot:SetSize(SLOT, SLOT)
    slot:SetPoint("TOPLEFT", SLOT_X + (i - 1) * (SLOT + SLOT_GAP), 0)
    slot.bg = slot:CreateTexture(nil, "BACKGROUND")
    slot.bg:SetAllPoints()
    UI.Color(slot.bg, C.inset, 0.9)
    slot.border = UI.Border(slot, C.lineDark)
    slot.rune = slot:CreateTexture(nil, "ARTWORK")
    slot.rune:SetSize(20, 20)
    slot.rune:SetPoint("CENTER")
    slot.hl = slot:CreateTexture(nil, "HIGHLIGHT")
    slot.hl:SetAllPoints()
    slot.hl:SetColorTexture(1, 0.85, 0.5, 0.14)
    local rr, ii = r, i
    slot:SetScript("OnClick", function() ClickSlot(rr, ii) end)
    ui.slots[i] = slot
  end

  local clueBG = row:CreateTexture(nil, "BORDER")
  clueBG:SetPoint("TOPLEFT", CLUE_X - 4, -1)
  clueBG:SetSize(PIP * 2 + PIP_GAP + 8, SLOT - 2)
  UI.Color(clueBG, C.inset, 0.6)

  for k = 1, SLOTS do
    local col, rowIdx = (k - 1) % 2, floor((k - 1) / 2)
    local pip = row:CreateTexture(nil, "ARTWORK")
    pip:SetTexture(ns.MEDIA .. "dot")
    pip:SetSize(PIP, PIP)
    pip:SetPoint("TOPLEFT", CLUE_X + col * (PIP + PIP_GAP), -(2 + rowIdx * (PIP + PIP_GAP)))
    ui.pips[k] = pip
  end

  rowsUI[r] = ui
end

local function Create(parent, saved)
  data = saved
  if not ValidGame(data) then StartGame("apprentice") end

  modeRow = UI.Choice(parent, MODES, 180, AskNewGame)
  modeRow:SetPoint("TOPLEFT", 12, -4)
  triesText = UI.Text(parent, 12, C.cream)
  triesText:SetPoint("TOPRIGHT", -12, -9)

  for r = 1, TRIES do BuildRow(parent, r) end

  local legend = UI.Text(parent, 10, C.dim)
  legend:SetPoint("TOP", parent, "TOP", 0, -402)
  legend:SetJustifyH("CENTER")
  legend:SetText("Gold: right rune, right place.\nSilver: right rune, wrong place.")

  -- Rune palette: fills the next empty slot of the current row.
  local PAL, PAL_GAP = 36, 8
  local palX = floor((ns.GAME_W - (RUNES * PAL + (RUNES - 1) * PAL_GAP)) / 2)
  for k = 1, RUNES do
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(PAL, PAL)
    b:SetPoint("TOPLEFT", palX + (k - 1) * (PAL + PAL_GAP), -328)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    UI.Color(b.bg, C.wood)
    UI.Border(b, C.line)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 0.82, 0.3, 0.18)
    b.rune = b:CreateTexture(nil, "ARTWORK")
    b.rune:SetSize(24, 24)
    b.rune:SetPoint("CENTER")
    RuneTexture(b.rune, k, 24)
    local kk = k
    b:SetScript("OnEnter", function(self)
      if not ns.UseRaidMarks() then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(ns.RAID_MARK_NAMES[ns.PIECE_MARKS[kk]], C.gold[1], C.gold[2], C.gold[3])
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() Place(kk) end)
    palette[k] = b
  end

  unlockButton = UI.Button(parent, "Unlock", 100, 24)
  unlockButton:SetPoint("TOPLEFT", 22, -372)
  unlockButton:SetScript("OnClick", Unlock)
  clearButton = UI.Button(parent, "Clear", 84, 24)
  clearButton:SetPoint("LEFT", unlockButton, "RIGHT", 4, 0)
  clearButton:SetScript("OnClick", Clear)
  local newButton = UI.Button(parent, "New lock", 84, 24)
  newButton:SetPoint("LEFT", clearButton, "RIGHT", 4, 0)
  newButton:SetScript("OnClick", function() AskNewGame(data.mode) end)

  overlay = UI.Overlay(parent)
  for i = 1, SLOTS do
    local t = overlay.buttons:CreateTexture(nil, "ARTWORK")
    t:SetSize(26, 26)
    t:SetPoint("TOP", overlay.buttons, "TOP", (i - 2.5) * 32, 0)
    codeRunes[i] = t
  end
  local again = UI.Button(overlay.buttons, "New lock", 100, 24)
  again:SetPoint("TOP", overlay.buttons, "TOP", 0, -36)
  again:SetScript("OnClick", function() AskNewGame(data.mode) end)

  Render()
  if IsOver() then ShowEnd(false) end

  ns.OnPiecesChanged(function()
    for k = 1, RUNES do RuneTexture(palette[k].rune, k, 24) end
    Render()
    if IsOver() then
      for i = 1, SLOTS do RuneTexture(codeRunes[i], data.code[i], 26) end
    end
  end)
end

ns.RegisterGame({
  key = "runes",
  name = "Rune Lock",
  blurb = "Work out the hidden rune code in ten tries.",
  icon = ns.MEDIA .. "icons\\runes",
  order = 70,
  hasWins = true,
  Create = Create,
  InProgress = function(d)
    if type(d) ~= "table" or not ValidGame(d) then return false end
    local n = #d.rows
    if n == 0 or n >= TRIES then return false end
    return d.rows[n].e ~= SLOTS
  end,
  Summary = function(d)
    local s = d.stats or {}
    local best
    for _, k in ipairs({ "best_apprentice", "best_master" }) do
      local v = s[k]
      if v and (not best or v < best) then best = v end
    end
    return best and format("Best %d tries", best) or ""
  end,
})
