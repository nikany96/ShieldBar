-- stub: SuperWoW-agtig SpellInfo + en tooltip vi kan slukke for
local SPELLS = { [7301]="Shadow Protection", [6229]="Shadow Ward", [974]="Earth Shield",
                 [20911]="Blessing of Sanctuary", [324]="Lightning Shield" }
local spellInfoCalls = 0
SpellInfo = function(id)
  spellInfoCalls = spellInfoCalls + 1
  if not SPELLS[id] then error("no such spell") end
  return SPELLS[id]
end
local SHIELDS = {
  SHADOWWARD = { guard = "shadow ward" },
  LIGHTNING  = { guard = "lightning shield" },
  PWS        = { },
}
local tooltipName, tooltipReadable = nil, true
local function GetBuffName() if not tooltipReadable then return nil end return tooltipName end

local spellNameCache = {}
local function SpellNameByID(id)
  if not id or not SpellInfo then return nil end
  local cached = spellNameCache[id]
  if cached ~= nil then if cached == false then return nil end return cached end
  local ok, name = pcall(SpellInfo, id)
  if not ok or not name or name == "" then spellNameCache[id] = false ; return nil end
  spellNameCache[id] = name
  return name
end
local function NameGuardOK(unit, idx, texture, id)
  local info = SHIELDS[texture]
  if not info or not info.guard then return true, true end
  local name = SpellNameByID(id)
  if name then return string.find(string.lower(name), info.guard, 1, true) ~= nil, true end
  name = GetBuffName(unit, idx)
  if not name then return true, false end
  return string.find(string.lower(name), info.guard, 1, true) ~= nil, false
end

local pass, fail = 0, 0
local function check(label, gotOK, gotExact, wantOK, wantExact)
  if gotOK == wantOK and gotExact == wantExact then pass = pass + 1
  else fail = fail + 1
    print(string.format("FEJL %s: fik ok=%s exact=%s, ventede ok=%s exact=%s",
      label, tostring(gotOK), tostring(gotExact), tostring(wantOK), tostring(wantExact))) end
end

-- 1. Shadow Protection på warlock, spell id kendt -> skal AFVISES entydigt
do local a,b = NameGuardOK("player",1,"SHADOWWARD",7301) ; check("Shadow Protection vs Shadow Ward", a, b, false, true) end
local ok, ex = NameGuardOK("player",1,"SHADOWWARD",7301) ; check("(samme igen)", ok, ex, false, true)
-- 2. Ægte Shadow Ward -> accepteres
do local a,b = NameGuardOK("player",1,"SHADOWWARD",6229) ; check("ægte Shadow Ward", a, b, true, true) end
-- 3. Blessing of Sanctuary vs Lightning Shield -> afvises
do local a,b = NameGuardOK("player",1,"LIGHTNING",20911) ; check("Sanctuary vs Lightning", a, b, false, true) end
-- 4. Ægte Lightning Shield -> accepteres
do local a,b = NameGuardOK("player",1,"LIGHTNING",324) ; check("ægte Lightning Shield", a, b, true, true) end
-- 5. INTET spell id (ingen SuperWoW), tooltip læsbar og forkert -> afvist via tooltip
tooltipName, tooltipReadable = "Shadow Protection", true
do local a,b = NameGuardOK("player",1,"SHADOWWARD",nil) ; check("uden id, tooltip forkert", a, b, false, false) end
-- 6. Intet id, tooltip ULÆSELIG -> fail-open (accepteres)
tooltipReadable = false
do local a,b = NameGuardOK("player",1,"SHADOWWARD",nil) ; check("uden id, tooltip død -> fail-open", a, b, true, false) end
-- 7. Ukendt id (Turtle "mistede" id'et) -> falder til tooltip, som er død -> fail-open
do local a,b = NameGuardOK("player",1,"SHADOWWARD",99999) ; check("ukendt id -> fallback", a, b, true, false) end
-- 8. samme ukendte id igen: må IKKE kalde SpellInfo på ny (negativ cache)
local before = spellInfoCalls
NameGuardOK("player",1,"SHADOWWARD",99999)
if spellInfoCalls ~= before then fail=fail+1 ; print("FEJL: negativ cache virker ikke") else pass=pass+1 end
-- 9. skjold uden guard -> altid ok
do local a,b = NameGuardOK("player",1,"PWS",nil) ; check("uden guard", a, b, true, true) end

print(string.format("\n%d bestået, %d fejlet   (SpellInfo kaldt %d gange i alt)", pass, fail, spellInfoCalls))
