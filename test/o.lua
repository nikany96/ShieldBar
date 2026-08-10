table.getn = function(t) return #t end  -- Lua 5.0-alias
local SHIELDS = {
  PWS      = { fallback = 1265 },                       -- generisk
  FIREWARD = { fallback = 890, school = "fire" },       -- fast school
  POTION   = { fallback = 1400, schoolFromName = true },-- dynamisk school
  LSHIELD  = { charges = true },                        -- absorberer aldrig
}
local ORDER = { "LSHIELD", "PWS", "FIREWARD", "POTION" }
local active = {}
local function ActiveList()
  local l = {}
  for _, t in ipairs(ORDER) do if active[t] then table.insert(l, t) end end
  return l
end
local function ShieldSchool(texture)
  local a = active[texture]
  if a and a.school then return a.school end
  return SHIELDS[texture].school
end
local function AbsorbOrder(school)
  local order, list = {}, ActiveList()
  if school then
    for i = 1, table.getn(list) do
      local info = SHIELDS[list[i]]
      if not info.charges and ShieldSchool(list[i]) == school then table.insert(order, list[i]) end
    end
  end
  for i = 1, table.getn(list) do
    local info = SHIELDS[list[i]]
    if not info.charges and not ShieldSchool(list[i]) then table.insert(order, list[i]) end
  end
  if not school then
    for i = 1, table.getn(list) do
      local info = SHIELDS[list[i]]
      if not info.charges and ShieldSchool(list[i]) then table.insert(order, list[i]) end
    end
  end
  return order
end
local function j(t) return table.concat(t, ",") end
local pass, fail = 0, 0
local function check(label, got, want)
  if got == want then pass = pass + 1
  else fail = fail + 1 ; print(string.format("FEJL %-46s -> [%s] ventede [%s]", label, got, want)) end
end

-- alt aktivt; potionen er en FROST protection potion
active = { LSHIELD={}, PWS={}, FIREWARD={}, POTION={school="frost"} }
check("frost-skade: frost-potion foerst, saa generisk",  j(AbsorbOrder("frost")), "POTION,PWS")
check("fire-skade: Fire Ward foerst, saa generisk",      j(AbsorbOrder("fire")),  "FIREWARD,PWS")
check("shadow-skade: kun generisk",                      j(AbsorbOrder("shadow")),"PWS")
check("ukendt school: generisk foerst, school'ede sidst",j(AbsorbOrder(nil)),     "PWS,FIREWARD,POTION")

-- samme potion, men navnet kunne ikke laeses -> school nil -> generisk som foer
active.POTION = {}
check("potion uden navn: opfoerer sig generisk",         j(AbsorbOrder("frost")), "PWS,POTION")
check("potion uden navn, ukendt school",                 j(AbsorbOrder(nil)),     "PWS,POTION,FIREWARD")

-- charge-skjold maa aldrig med
active = { LSHIELD={} }
check("kun charge-skjold aktivt -> intet absorberer",    j(AbsorbOrder("fire")),  "")
print(string.format("\n%d bestaaet, %d fejlet", pass, fail))
