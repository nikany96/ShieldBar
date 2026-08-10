string.gfind = string.gmatch  -- Lua 5.0 hed det gfind; alias så testen kan køre på 5.4
local SCHOOL_WORDS = { fire=true, frost=true, nature=true, shadow=true, arcane=true, holy=true }
local function SchoolFromSpellName(name)
    if not name then return nil end
    for word in string.gfind(string.lower(name), "%a+") do
        if SCHOOL_WORDS[word] then return word end
    end
    return nil
end
local cases = {
  {"Greater Fire Protection Potion",   "fire"},
  {"Fire Protection Potion",           "fire"},
  {"Greater Frost Protection Potion",  "frost"},
  {"Greater Shadow Protection Potion", "shadow"},
  {"Greater Arcane Protection Potion", "arcane"},
  {"Greater Nature Protection Potion", "nature"},
  {"Greater Holy Protection Potion",   "holy"},
  {"Frost Reflector",                  "frost"},
  {"Shadow Reflector",                 "shadow"},
  -- må IKKE finde en school:
  {"Free Action Potion",               nil},
  {"Elixir of the Mongoose",           nil},
  {"Greater Stoneshield Potion",       nil},
  {"Fireball",                         nil},   -- delstreng "fire" må ikke tælle
  {"Shadowguard",                      nil},   -- delstreng "shadow" må ikke tælle
  {"Firewater",                        nil},
  {nil,                                nil},
}
local pass, fail = 0, 0
for _, c in ipairs(cases) do
  local got = SchoolFromSpellName(c[1])
  if got == c[2] then pass = pass + 1
  else fail = fail + 1
    print(string.format("FEJL %-34s -> %s (ventede %s)", tostring(c[1]), tostring(got), tostring(c[2]))) end
end
print(string.format("\n%d bestået, %d fejlet", pass, fail))
