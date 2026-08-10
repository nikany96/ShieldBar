dofile("wow.lua")
PLAYER_CLASS = "SHAMAN"
RegisterSpell(324,"Lightning Shield") ; RegisterSpell(52127,"Water Shield")
dofile(os.getenv("HOME") .. "/ShieldBar/ShieldBar.lua")
local ev = getglobal("ShieldBarEventFrame")
local onEvent, onUpdate = ev:GetScript("OnEvent"), ev:GetScript("OnUpdate")
event = "VARIABLES_LOADED" ; onEvent()
event = "PLAYER_ENTERING_WORLD" ; onEvent()
local root = getglobal("ShieldBarFrame")

-- to forskellige skjolde oppe samtidig
BUFFS = { player = {
  {"Interface\\Icons\\Ability_Shaman_WaterShield",     3, 52127},
  {"Interface\\Icons\\Spell_Nature_LightningShield",   3, 324},
} }
arg1 = 2.0 ; onUpdate()

local function barXs()
  local xs = {}
  for _, f in ipairs(ALLFRAMES) do
    if f.__parent == root and f.__point then
      xs[#xs+1] = string.format("%s(x=%s,y=%s)", f.__shown and "vist" or "skjult",
                                tostring(f.__point[4]), tostring(f.__point[5]))
    end
  end
  return table.concat(xs, "  ")
end
local fail = 0
local function want(label, got, exp)
  local mark = "✅" ; if got ~= exp then mark = "❌" ; fail = fail + 1 end
  print(string.format("%s %-34s %s", mark, label, got))
  if got ~= exp then print(string.format("   ventede: %s", exp)) end
end

SlashCmdList["SHIELDBAR"]("grow right")
want("vertical, grow right", barXs(),
     "vist(x=0,y=0)  vist(x=108,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)")
SlashCmdList["SHIELDBAR"]("grow left")
want("vertical, grow left  (byttet om)", barXs(),
     "vist(x=108,y=0)  vist(x=0,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)")
SlashCmdList["SHIELDBAR"]("horizontal")
SlashCmdList["SHIELDBAR"]("grow down")
want("horizontal, grow down", barXs(),
     "vist(x=0,y=0)  vist(x=0,y=-108)  skjult(x=0,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)")
SlashCmdList["SHIELDBAR"]("grow up")
want("horizontal, grow up   (byttet om)", barXs(),
     "vist(x=0,y=-108)  vist(x=0,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)  skjult(x=0,y=0)")

-- indstillingen skal overleve i DB
SlashCmdList["SHIELDBAR"]("grow up")
if ShieldBarDB.growReverse ~= true then fail = fail + 1 ; print("❌ ikke gemt i DB") 
else print("✅ gemt i ShieldBarDB.growReverse") end
SlashCmdList["SHIELDBAR"]("reset")
if ShieldBarDB.growReverse ~= nil and ShieldBarDB.growReverse ~= false then
  fail = fail + 1 ; print("❌ reset nulstillede ikke")
else print("✅ reset nulstiller growReverse") end
-- GUI-labels skal foelge orientering
SlashCmdList["SHIELDBAR"]("")            -- byg GUI
SlashCmdList["SHIELDBAR"]("vertical")
want("GUI-label (vertical)", getglobal("ShieldBarCheckGrowNormalText").__text, "Grow right")
SlashCmdList["SHIELDBAR"]("horizontal")
want("GUI-label (horizontal)", getglobal("ShieldBarCheckGrowNormalText").__text, "Grow down")
print(fail == 0 and "\n✅ ALT OK" or "\n❌ " .. fail .. " FEJL")
os.exit(fail == 0 and 0 or 1)
