-- Gen 1 evolution families for the dupes clause.
--
-- FireRed's internal species ids 1..251 equal the National Dex, so these
-- numbers are used as-is. Gen 2 relatives (babies, Crobat, Steelix, ...)
-- are folded into their Gen 1 family so a later evolution never looks new.
-- Any species not listed is its own family.

local Families = {}

local GROUPS = {
  { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 10, 11, 12 }, { 13, 14, 15 },
  { 16, 17, 18 }, { 19, 20 }, { 21, 22 }, { 23, 24 }, { 25, 26, 172 },
  { 27, 28 }, { 29, 30, 31 }, { 32, 33, 34 }, { 35, 36, 173 }, { 37, 38 },
  { 39, 40, 174 }, { 41, 42, 169 }, { 43, 44, 45, 182 }, { 46, 47 },
  { 48, 49 }, { 50, 51 }, { 52, 53 }, { 54, 55 }, { 56, 57 }, { 58, 59 },
  { 60, 61, 62, 186 }, { 63, 64, 65 }, { 66, 67, 68 }, { 69, 70, 71 },
  { 72, 73 }, { 74, 75, 76 }, { 77, 78 }, { 79, 80, 199 }, { 81, 82 },
  { 84, 85 }, { 86, 87 }, { 88, 89 }, { 90, 91 }, { 92, 93, 94 },
  { 95, 208 }, { 96, 97 }, { 98, 99 }, { 100, 101 }, { 102, 103 },
  { 104, 105 }, { 106, 107, 236, 237 }, { 109, 110 }, { 111, 112 },
  { 113, 242 }, { 116, 117, 230 }, { 118, 119 }, { 120, 121 }, { 123, 212 },
  { 124, 238 }, { 125, 239 }, { 126, 240 }, { 129, 130 },
  { 133, 134, 135, 136, 196, 197 }, { 137, 233 }, { 138, 139 }, { 140, 141 },
  { 147, 148, 149 },
}

local ROOT = {}
for _, group in ipairs(GROUPS) do
  for _, species in ipairs(group) do ROOT[species] = group[1] end
end

-- The family id (the first member's species number) for a species id.
function Families.of(species)
  species = tonumber(species)
  if not species then return nil end
  return ROOT[species] or species
end

return Families
