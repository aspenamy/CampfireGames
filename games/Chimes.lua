-------------------------------------------------------------------------------
-- Campfire Games: Chimes
--
-- Four tavern bells ring in a pattern. Listen, then click the bells back in
-- the same order. Each round adds one more bell. A wrong bell ends the game.
-- The bells play C D E G, and the pattern is often a familiar folk tune.
-- Gentle mode plays slower and forgives one mistake (the pattern replays).
-------------------------------------------------------------------------------

local _, ns = ...

local C, UI = ns.C, ns.UI
local floor, max, min = math.floor, math.max, math.min

local PAD, BOARD = 108, 288
local OFF = 90 -- pad centers sit this far from the middle (a diamond)

local MODES = {
  { key = "classic", label = "Classic" },
  { key = "gentle", label = "Gentle" },
}
local MODE_OK = { classic = true, gentle = true }

-- Clockwise from the top left: low bell to high bell.
local PADS = {
  { color = { 0.66, 0.15, 0.12 }, mark = 7, tone = "bell1", x = 0, y = OFF },
  { color = { 0.88, 0.60, 0.14 }, mark = 2, tone = "bell2", x = OFF, y = 0 },
  { color = { 0.20, 0.54, 0.26 }, mark = 4, tone = "bell3", x = 0, y = -OFF },
  { color = { 0.20, 0.40, 0.76 }, mark = 6, tone = "bell4", x = -OFF, y = 0 },
}

local CLICK_LIT = 0.32   -- how long a player's click keeps a pad lit
local FADE = 0.14        -- soft fade at the end of a light

-- Pads are 1 = C, 2 = D, 3 = E, 4 = G. The pattern is chained from short
-- tunes (folk songs and a few original phrases), never the same one twice in
-- a row, with now and then a single random bell between them.
local PHRASES = {
  { 3, 2, 1, 2, 3, 3, 3 },       -- Mary Had a Little Lamb
  { 2, 2, 2, 3, 4, 4 },          -- Mary Had a Little Lamb, second line
  { 3, 2, 1, 3, 2, 1 },          -- Hot Cross Buns
  { 1, 1, 2, 2, 3, 2, 1 },       -- Hot Cross Buns, second line
  { 1, 1, 1, 2, 3, 2 },          -- Au Clair de la Lune
  { 1, 3, 2, 2, 1 },             -- Au Clair de la Lune, ending
  { 1, 2, 3, 1, 1, 2, 3, 1 },    -- Frere Jacques
  { 3, 4, 4, 3, 4, 4 },          -- Frere Jacques, second line
  { 1, 3, 4, 4 },                -- original: rising fanfare
  { 4, 3, 2, 1 },                -- original: falling bells
  { 1, 3, 1, 3, 4, 3, 2, 1 },    -- original: tavern jig
  { 3, 4, 3, 2, 1, 2, 3 },       -- original: hearth song
  { 4, 4, 3, 4, 1, 3, 4, 4 },    -- original: heroic call
  { 2, 4, 3, 1, 2, 3 },          -- original: lantern walk
}
local MAX_RUN = 3
local queue, lastPhrase = {}, 0

local data
local panel, board, pads, overlay, toast, centerNum, centerText, modeText, bestText, modeRow, modeHint
local seq, mode, phase, clock = {}, "classic", "over", 0
local inputIdx, playIdx, stepT, pauseT, grow, freeLeft = 1, 1, 0, 0, false, 0

-------------------------------------------------------------------------------
-- Building the pattern
-------------------------------------------------------------------------------

local function Refill()
  if lastPhrase > 0 and math.random() < 0.2 then
    queue[#queue + 1] = math.random(4)
  end
  local pick
  repeat pick = math.random(#PHRASES) until pick ~= lastPhrase or #PHRASES < 2
  lastPhrase = pick
  for _, n in ipairs(PHRASES[pick]) do queue[#queue + 1] = n end
end

-- The next bell: from the current tune, but never a 4th in a row.
local function NextNote()
  if #queue == 0 then Refill() end
  local n = table.remove(queue, 1)
  local len = #seq
  if len >= MAX_RUN and seq[len] == n and seq[len - 1] == n and seq[len - 2] == n then
    local alt = math.random(3)
    if alt >= n then alt = alt + 1 end
    n = alt
  end
  return n
end

-------------------------------------------------------------------------------
-- Timing
-------------------------------------------------------------------------------

local function StepTimes()
  local n = #seq
  if mode == "gentle" then
    return max(0.42, 0.70 - 0.012 * n), 0.25
  end
  return max(0.24, 0.45 - 0.010 * n), max(0.08, 0.15 - 0.003 * n)
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------

local function Brightness(p)
  local left = p.litUntil - clock
  if left <= 0 then return 0 end
  return min(1, left / FADE)
end

local function PaintPad(p, b)
  if p.shown == b then return end
  p.shown = b
  local c = p.color
  local k = 0.38 + 0.62 * b
  local w = 0.28 * b
  p.plate:SetVertexColor(min(1, c[1] * k + w), min(1, c[2] * k + w), min(1, c[3] * k + w), 1)
  p.glow:SetVertexColor(c[1], c[2], c[3], 0.9 * b)
  p.markTex:SetAlpha(0.7 + 0.3 * b)
end

local function Light(i, dur)
  pads[i].litUntil = clock + dur
  PaintPad(pads[i], 1)
  ns.PlayTone(PADS[i].tone)
end

local function RefreshPieces()
  if not pads then return end
  local marks = ns.UseRaidMarks()
  for i, p in ipairs(pads) do
    p.markTex:SetShown(marks)
    p.bell:SetShown(not marks)
  end
end

local function RefreshTexts()
  local best = data and data.stats and data.stats["best_" .. mode]
  bestText:SetText(best and best > 0 and ("Best " .. best) or "")
  modeText:SetText(mode == "gentle" and (freeLeft > 0 and "Gentle, one free miss" or "Gentle, no free miss") or "Classic")
  modeRow:Select(mode)
  if modeHint then
    modeHint:SetText(mode == "gentle" and "Gentle forgives one miss." or "Classic ends at the first miss.")
  end

  if phase == "over" then
    centerNum:SetText("")
    centerText:SetText("")
  else
    centerNum:SetText(#seq)
    centerText:SetText(phase == "input" and "Your turn" or phase == "wrong" and "" or "Listen...")
  end
end

-------------------------------------------------------------------------------
-- Game flow
-------------------------------------------------------------------------------

local function Completed()
  -- Rounds fully repeated: the current sequence is still being attempted.
  if phase == "over" then return 0 end
  -- Between rounds the last one is done and the next bell isn't added yet.
  if phase == "pause" and grow then return #seq end
  return max(0, #seq - 1)
end

local function Finish()
  if phase == "over" then return end
  local n = Completed()
  phase = "over"
  local newBest = ns.RecordResult("chimes", { score = n, bestKey = "best_" .. mode })
  local best = data.stats["best_" .. mode] or n
  for _, p in ipairs(pads) do p.litUntil = 0 end
  RefreshTexts()
  overlay:Open("The bells fall quiet",
    format("%s%d %s rung\nBest: %d", newBest and "A new best!\n" or "", n, n == 1 and "bell" or "bells", best))
  if newBest then
    ns.PlayTone("chime")
  end
end

local function BeginPlayback()
  phase = "play"
  playIdx, stepT = 1, 0
  pads[seq[1]].started = false
  RefreshTexts()
end

local function StartPause(addStep, t)
  phase = "pause"
  grow = addStep
  pauseT = t
  RefreshTexts()
end

local function NewGame()
  overlay:Close()
  if phase ~= "over" and Completed() > 0 then Finish() overlay:Close() end
  phase = "pause"
  seq, queue, lastPhrase = {}, {}, 0
  seq[1] = NextNote()
  freeLeft = mode == "gentle" and 1 or 0
  inputIdx = 1
  for _, p in ipairs(pads) do p.litUntil = 0 end
  StartPause(false, 0.7)
end

local function Mistake()
  -- Show the bell that was wanted.
  local want = seq[inputIdx]
  ns.PlayTone("wrong")
  pads[want].litUntil = clock + 0.9
  PaintPad(pads[want], 1)
  if freeLeft > 0 then
    freeLeft = freeLeft - 1
    toast:Say("Try again", C.dim)
    phase = "wrong"
    pauseT = 1.2
    grow = false
    RefreshTexts()
    return
  end
  phase = "wrong"
  pauseT = 1.0
  grow = nil -- nil means the game is over after the pause
  RefreshTexts()
end

local function Press(i)
  if phase ~= "input" then return end
  if seq[inputIdx] ~= i then
    Mistake()
    return
  end
  Light(i, CLICK_LIT)
  inputIdx = inputIdx + 1
  if inputIdx > #seq then
    phase = "pause"
    grow = true
    pauseT = 0.8
    RefreshTexts()
  end
end

local function Tick(dt)
  clock = clock + dt
  for _, p in ipairs(pads) do
    local b = Brightness(p)
    if b > 0 or p.shown ~= 0 then PaintPad(p, b) end
  end

  if phase == "pause" then
    pauseT = pauseT - dt
    if pauseT <= 0 then
      if grow then seq[#seq + 1] = NextNote() end
      grow = false
      BeginPlayback()
    end
  elseif phase == "play" then
    local on, gap = StepTimes()
    local p = pads[seq[playIdx]]
    if not p.started then
      p.started = true
      Light(seq[playIdx], on)
    end
    stepT = stepT + dt
    if stepT >= on + gap then
      p.started = false
      stepT = stepT - (on + gap)
      playIdx = playIdx + 1
      if playIdx > #seq then
        phase = "input"
        inputIdx = 1
        RefreshTexts()
      end
    end
  elseif phase == "wrong" then
    pauseT = pauseT - dt
    if pauseT <= 0 then
      if grow == nil then
        Finish()
      else
        inputIdx = 1
        BeginPlayback()
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------

local function Create(parent, saved)
  panel = parent
  data = saved
  if not MODE_OK[data.mode] then data.mode = "classic" end
  mode = data.mode

  local left = floor((ns.GAME_W - BOARD) / 2)

  modeText = UI.Title(parent, 14)
  modeText:SetPoint("TOPLEFT", left, -2)
  bestText = UI.Text(parent, 12, C.cream)
  bestText:SetPoint("TOPRIGHT", -left, -3)

  board = CreateFrame("Frame", nil, parent)
  board:SetSize(BOARD, BOARD)
  board:SetPoint("TOPLEFT", left, -24)

  pads = {}
  for i, def in ipairs(PADS) do
    local b = CreateFrame("Button", nil, board)
    b:SetSize(PAD, PAD)
    b:SetPoint("CENTER", board, "CENTER", def.x, def.y)
    b:SetHitRectInsets(12, 12, 12, 12)
    b.color = def.color
    b.litUntil = 0

    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(ns.MEDIA .. "dot")
    b.glow:SetBlendMode("ADD")
    b.glow:SetSize(PAD + 34, PAD + 34)
    b.glow:SetPoint("CENTER")

    b.plate = b:CreateTexture(nil, "BORDER")
    b.plate:SetTexture(ns.MEDIA .. "chimes\\plate")
    b.plate:SetAllPoints()
    b.rim = b:CreateTexture(nil, "ARTWORK")
    b.rim:SetTexture(ns.MEDIA .. "chimes\\rim")
    b.rim:SetAllPoints()

    b.markTex = b:CreateTexture(nil, "OVERLAY")
    b.markTex:SetTexture(ns.RAID_MARKS[def.mark])
    b.markTex:SetSize(40, 40)
    b.markTex:SetPoint("CENTER", 0, 0)

    -- A small bell: dome, lip and clapper made of light dots.
    b.bell = CreateFrame("Frame", nil, b)
    b.bell:SetSize(40, 40)
    b.bell:SetPoint("CENTER", 0, 0)
    local dome = b.bell:CreateTexture(nil, "OVERLAY")
    dome:SetTexture(ns.MEDIA .. "dot")
    dome:SetSize(30, 30)
    dome:SetPoint("CENTER", 0, 4)
    dome:SetVertexColor(1, 0.92, 0.7, 0.55)
    local lip = b.bell:CreateTexture(nil, "OVERLAY")
    lip:SetColorTexture(1, 0.92, 0.7, 0.5)
    lip:SetSize(32, 4)
    lip:SetPoint("CENTER", 0, -9)
    local clap = b.bell:CreateTexture(nil, "OVERLAY")
    clap:SetTexture(ns.MEDIA .. "dot")
    clap:SetSize(8, 8)
    clap:SetPoint("CENTER", 0, -14)
    clap:SetVertexColor(1, 0.92, 0.7, 0.7)

    b:SetScript("OnClick", function() Press(i) end)
    pads[i] = b
    PaintPad(b, 0)
  end

  -- Medallion in the middle.
  local med = CreateFrame("Frame", nil, board)
  med:SetSize(78, 78)
  med:SetPoint("CENTER", 0, 0)
  med:SetFrameLevel(board:GetFrameLevel() + 5)
  local disc = med:CreateTexture(nil, "BACKGROUND")
  disc:SetTexture(ns.MEDIA .. "chimes\\medallion")
  disc:SetAllPoints()
  centerNum = UI.Title(med, 26)
  centerNum:SetPoint("CENTER", 0, 0)
  -- "Your turn" / "Listen..." sits under the board so the number stays centered.
  centerText = UI.Text(parent, 12, C.cream)
  centerText:SetPoint("TOP", board, "BOTTOM", 0, -2)

  overlay = UI.Overlay(board)
  local again = UI.Button(overlay.buttons, "Ring again", 110, 24)
  again:SetPoint("CENTER", 0, 0)
  again:SetScript("OnClick", function() NewGame() end)
  toast = UI.Toast(board)

  -- Mode and new game, centered under the board.
  local rowW = 40 + 190
  local modeLabel = UI.Text(parent, 11, C.dim)
  modeLabel:SetPoint("TOPLEFT", board, "BOTTOMLEFT", floor((BOARD - rowW) / 2), -24)
  modeLabel:SetText("Mode:")
  modeRow = UI.Choice(parent, MODES, 190, function(key)
    if key == mode then return end
    if phase ~= "over" then Finish() end
    mode = key
    data.mode = key
    NewGame()
  end)
  modeRow:SetPoint("LEFT", modeLabel, "LEFT", 40, 0)

  local new = UI.Button(parent, "New game", 110, 22)
  new:SetPoint("TOP", board, "BOTTOM", 0, -56)
  new:SetScript("OnClick", function()
    if phase ~= "over" then Finish() end
    NewGame()
  end)
  modeHint = UI.Text(parent, 11, C.dim)
  modeHint:SetPoint("TOP", new, "BOTTOM", 0, -8)
  modeHint:SetJustifyH("CENTER")
  modeHint:SetText("Gentle forgives one miss.")

  ns.OnPiecesChanged(RefreshPieces)
  RefreshPieces()

  parent:SetScript("OnUpdate", function(_, dt)
    if dt > 0.1 then dt = 0.1 end
    Tick(dt)
  end)

  NewGame()
end

ns.RegisterGame({
  key = "chimes",
  name = "Chimes",
  blurb = "Listen to the bells, then ring them back in order.",
  icon = ns.MEDIA .. "icons\\chimes",
  order = 110,
  Create = Create,
  OnHide = function()
    if pads and phase ~= "over" then Finish() end
  end,
  InProgress = function() return false end,
  Summary = function(d)
    local s = d.stats
    local best = max(s.best_classic or 0, s.best_gentle or 0)
    if best <= 0 then return "" end
    return format("Best %d %s", best, best == 1 and "bell" or "bells")
  end,
})
