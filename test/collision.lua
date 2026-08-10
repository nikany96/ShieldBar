dofile("wow.lua")
PLAYER_CLASS = "PALADIN"
RegisterSpell(20911,"Blessing of Sanctuary")
RegisterSpell(324,  "Lightning Shield")
RegisterSpell(7301, "Shadow Protection")
RegisterSpell(6229, "Shadow Ward")
RegisterSpell(17548,"Greater Shadow Protection Potion")
dofile(os.getenv("HOME") .. "/ShieldBar/ShieldBar.lua")
local ev = getglobal("ShieldBarEventFrame")
local onEvent, onUpdate = ev:GetScript("OnEvent"), ev:GetScript("OnUpdate")
event = "VARIABLES_LOADED" ; onEvent()
event = "PLAYER_ENTERING_WORLD" ; onEvent()

local function barsShown(label)
  OUT = {}
  SlashCmdList["SHIELDBAR"]("debug")
  local tracked = {}
  for _, line in ipairs(OUT) do
    local clean = line:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
    if string.find(clean, "tracked", 1, true) then tracked[#tracked+1] = clean end
  end
  print(string.format("%-52s -> %d bjælke(r)", label, #tracked))
  for _, t in ipairs(tracked) do print("        " .. t) end
  return #tracked
end

local fail = 0
local function expect(label, got, want)
  if got ~= want then fail = fail + 1 ; print("   ❌ ventede " .. want) end
end

print("=== PALADIN med Blessing of Sanctuary (vennens bug) ===")
BUFFS = { player = { {"Interface\\Icons\\Spell_Nature_LightningShield", 0, 20911} } }
arg1 = 2.0 ; onUpdate()
expect("paladin/Sanctuary", barsShown("Paladin, Blessing of Sanctuary"), 0)

print("\n=== SHAMAN med Blessing of Sanctuary (class-filter slipper igennem) ===")
PLAYER_CLASS = "SHAMAN"
package.loaded = {} ; OUT = {}
-- ny session med shaman
dofile("wow.lua") ; PLAYER_CLASS = "SHAMAN"
RegisterSpell(20911,"Blessing of Sanctuary") ; RegisterSpell(324,"Lightning Shield")
RegisterSpell(7301,"Shadow Protection") ; RegisterSpell(6229,"Shadow Ward")
dofile(os.getenv("HOME") .. "/ShieldBar/ShieldBar.lua")
ev = getglobal("ShieldBarEventFrame")
onEvent, onUpdate = ev:GetScript("OnEvent"), ev:GetScript("OnUpdate")
event = "VARIABLES_LOADED" ; onEvent() ; event = "PLAYER_ENTERING_WORLD" ; onEvent()
BUFFS = { player = { {"Interface\\Icons\\Spell_Nature_LightningShield", 0, 20911} } }
arg1 = 2.0 ; onUpdate()
expect("shaman/Sanctuary", barsShown("Shaman, Blessing of Sanctuary (kun guard redder)"), 0)

print("\n=== SHAMAN med ægte Lightning Shield ===")
BUFFS = { player = { {"Interface\\Icons\\Spell_Nature_LightningShield", 3, 324} } }
arg1 = 2.0 ; onUpdate()
expect("shaman/ægte", barsShown("Shaman, ægte Lightning Shield"), 1)

print("\n=== WARLOCK: Shadow Protection vs ægte Shadow Ward ===")
dofile("wow.lua") ; PLAYER_CLASS = "WARLOCK"
RegisterSpell(7301,"Shadow Protection") ; RegisterSpell(6229,"Shadow Ward")
dofile(os.getenv("HOME") .. "/ShieldBar/ShieldBar.lua")
ev = getglobal("ShieldBarEventFrame")
onEvent, onUpdate = ev:GetScript("OnEvent"), ev:GetScript("OnUpdate")
event = "VARIABLES_LOADED" ; onEvent() ; event = "PLAYER_ENTERING_WORLD" ; onEvent()
BUFFS = { player = { {"Interface\\Icons\\Spell_Shadow_AntiShadow", 0, 7301} } }
arg1 = 2.0 ; onUpdate()
expect("warlock/ShadowProt", barsShown("Warlock, Shadow Protection (priest-buff)"), 0)
BUFFS = { player = { {"Interface\\Icons\\Spell_Shadow_AntiShadow", 0, 6229} } }
arg1 = 2.0 ; onUpdate()
expect("warlock/ægte", barsShown("Warlock, ægte Shadow Ward"), 1)

print(fail == 0 and "\n✅ ALLE KOLLISIONER HÅNDTERET KORREKT" or "\n❌ " .. fail .. " FEJL")
os.exit(fail == 0 and 0 or 1)
