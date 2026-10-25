-- Seeded random streams for the randomizer.
--
-- A Lehmer generator (x = 48271x mod 2^31-1), never math.random: the engine
-- and the battle system share the global stream, so nothing drawn from it
-- would come back the same after a reload. Every decision draws from its own
-- stream, named after what it decides ("wild:<map>", "trainer:<id>", ...),
-- so the same seed always gives the same world, in any order of play.

local Rng = {}

local M31 = 2147483647
local MUL = 48271
local W32 = 4294967296

local function normalize(n)
  n = math.floor(tonumber(n) or 1) % M31
  if n <= 0 then n = n + M31 - 1 end
  if n <= 0 then n = 1 end
  return n
end

-- djb2 over the arguments, as text.
function Rng.hash(...)
  local h = 5381
  for i = 1, select("#", ...) do
    local s = tostring((select(i, ...)))
    for j = 1, #s do h = (h * 33 + s:byte(j)) % W32 end
    h = (h * 33 + 124) % W32
  end
  return h
end

local Stream = {}
Stream.__index = Stream

function Stream:next()
  self.state = (MUL * self.state) % M31
  return self.state
end

-- 1..n
function Stream:int(n)
  if n <= 1 then return 1 end
  return (self:next() % n) + 1
end

function Stream:pick(list)
  if #list == 0 then return nil end
  return list[self:int(#list)]
end

function Rng.stream(seed, name)
  local s = setmetatable({ state = normalize(Rng.hash(seed, name)) }, Stream)
  s:next() -- the first draw is too close to the hash; skip it
  return s
end

return Rng
