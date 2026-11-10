-------------------------------------------------------------------------------
-- Campfire Games: Sudoku puzzle maker and solver
--
-- Cells are numbered 1-81, left to right, top to bottom. A grid is a table of
-- 81 digits where 0 is an empty cell. Digits used in each row, column and box
-- are kept as 9-bit masks so finding a cell's candidates is a few bit ops.
--
-- The search checks in with coroutine.yield() every so often, so a puzzle can
-- be made a little at a time across frames without freezing the game.
-------------------------------------------------------------------------------

local _, ns = ...

local band, bor, lshift = bit.band, bit.bor, bit.lshift
local floor, random = math.floor, math.random

local L = {}
ns.SudokuLogic = L

local ALL = 511 -- all nine digits

-- How many clues each difficulty aims for. Clues are only taken away while
-- the puzzle keeps a single solution, so Hard stops wherever that runs out.
L.CLUES = { easy = 38, medium = 30, hard = 22 }

-- Bit count and digit list for every mask.
local POP, DIGITS = {}, {}
for m = 0, ALL do
  local n, list = 0, {}
  for d = 1, 9 do
    if band(m, lshift(1, d - 1)) ~= 0 then
      n = n + 1
      list[n] = d
    end
  end
  POP[m], DIGITS[m] = n, list
end

-- Row, column and box (all 1-9) for each cell, and each cell's 20 peers.
local ROW, COL, BOX, PEERS = {}, {}, {}, {}
for i = 1, 81 do
  local r, c = floor((i - 1) / 9), (i - 1) % 9
  ROW[i], COL[i], BOX[i] = r + 1, c + 1, floor(r / 3) * 3 + floor(c / 3) + 1
end
for i = 1, 81 do
  local p = {}
  for j = 1, 81 do
    if j ~= i and (ROW[i] == ROW[j] or COL[i] == COL[j] or BOX[i] == BOX[j]) then
      p[#p + 1] = j
    end
  end
  PEERS[i] = p
end
L.ROW, L.COL, L.BOX, L.PEERS = ROW, COL, BOX, PEERS

local YIELD_EVERY = 250
local steps = 0
local function Tick()
  steps = steps + 1
  if steps >= YIELD_EVERY then
    steps = 0
    if coroutine.running() then coroutine.yield() end
  end
end

-- Small seeded generator (Park-Miller). The state stays under 2^31 and every
-- product under 2^53, so the numbers are exact and the same on every machine.
-- Returns a function rnd(n) giving an integer from 1 to n.
local function SeededRandom(seed)
  local state = (floor(seed) * 40503 + 12345) % 2147483647
  if state == 0 then state = 1 end
  local function step()
    state = (state * 48271) % 2147483647
    return state
  end
  for _ = 1, 8 do step() end -- let nearby seeds drift apart
  return function(n)
    return floor(step() / 2147483647 * n) + 1
  end
end

local function Shuffle(t, rnd)
  for i = #t, 2, -1 do
    local j = rnd(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

local function Masks(g)
  local rows, cols, boxes = {}, {}, {}
  for k = 1, 9 do rows[k], cols[k], boxes[k] = 0, 0, 0 end
  for i = 1, 81 do
    local d = g[i]
    if d > 0 then
      local b = lshift(1, d - 1)
      rows[ROW[i]] = bor(rows[ROW[i]], b)
      cols[COL[i]] = bor(cols[COL[i]], b)
      boxes[BOX[i]] = bor(boxes[BOX[i]], b)
    end
  end
  return rows, cols, boxes
end

-- Fills empty cells by backtracking, always trying the cell with the fewest
-- candidates first. Stops once `limit` solutions are found. The first
-- solution found is copied into `out` when given.
-- `randomize` is nil for plain counting, or a function rnd(n) to shuffle with.
local function Search(g, rows, cols, boxes, limit, randomize, out, found)
  Tick()
  local best, bestMask, bestN = nil, 0, 10
  for i = 1, 81 do
    if g[i] == 0 then
      local m = ALL - bor(bor(rows[ROW[i]], cols[COL[i]]), boxes[BOX[i]])
      local n = POP[m]
      if n == 0 then return found end
      if n < bestN then
        best, bestMask, bestN = i, m, n
        if n == 1 then break end
      end
    end
  end

  if not best then
    if out and found == 0 then
      for i = 1, 81 do out[i] = g[i] end
    end
    return found + 1
  end

  local list = DIGITS[bestMask]
  if randomize then
    local copy = {}
    for k = 1, #list do copy[k] = list[k] end
    list = Shuffle(copy, randomize)
  end

  local r, c, b = ROW[best], COL[best], BOX[best]
  for k = 1, #list do
    local d = list[k]
    local v = lshift(1, d - 1)
    g[best] = d
    rows[r], cols[c], boxes[b] = rows[r] + v, cols[c] + v, boxes[b] + v
    found = Search(g, rows, cols, boxes, limit, randomize, out, found)
    rows[r], cols[c], boxes[b] = rows[r] - v, cols[c] - v, boxes[b] - v
    g[best] = 0
    if found >= limit then return found end
  end
  return found
end

-- Number of solutions, counting no higher than `limit` (default 2).
function L.CountSolutions(g, limit)
  local copy = {}
  for i = 1, 81 do copy[i] = g[i] end
  local rows, cols, boxes = Masks(copy)
  return Search(copy, rows, cols, boxes, limit or 2, false, nil, 0)
end

-- Makes a puzzle with a single solution. Returns puzzle, solution.
-- Best run inside a coroutine; it yields while it works.
-- With a seed, every random choice comes from a local seeded generator, so
-- the same seed always gives the same puzzle. Without one, math.random is used.
function L.Generate(difficulty, seed)
  local rnd = seed and SeededRandom(seed) or random
  local target = L.CLUES[difficulty] or L.CLUES.medium

  local solution, empty = {}, {}
  for i = 1, 81 do empty[i] = 0 end
  local rows, cols, boxes = Masks(empty)
  Search(empty, rows, cols, boxes, 1, rnd, solution, 0)

  local puzzle, order = {}, {}
  for i = 1, 81 do
    puzzle[i] = solution[i]
    order[i] = i
  end
  Shuffle(order, rnd)

  local clues = 81
  for _, i in ipairs(order) do
    if clues <= target then break end
    local keep = puzzle[i]
    puzzle[i] = 0
    if L.CountSolutions(puzzle, 2) == 1 then
      clues = clues - 1
    else
      puzzle[i] = keep
    end
  end
  return puzzle, solution
end
