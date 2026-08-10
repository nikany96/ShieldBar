dofile("wow.lua")
-- Simulér en klient UDEN SuperWoW: ingen SpellInfo, intet id fra UnitBuff
SpellInfo = nil
SUPERWOW_VERSION = nil
BUFFS = {}
function UnitBuff(unit, i)
  local list = BUFFS[unit]
  if not list or not list[i] then return nil end
  return list[i][1], list[i][2]      -- KUN to returværdier, som i ægte 1.12
end
PLAYER_CLASS = "SHAMAN"
local ok, err = pcall(dofile, os.getenv("HOME") .. "/ShieldBar/ShieldBar.lua")
if not ok then print("❌ LOAD FEJLEDE uden SuperWoW: " .. tostring(err)) ; os.exit(1) end
print("✅ addon loadet uden SuperWoW")
local ev = getglobal("ShieldBarEventFrame")
local onEvent, onUpdate = ev:GetScript("OnEvent"), ev:GetScript("OnUpdate")
event = "VARIABLES_LOADED" ; onEvent()
event = "PLAYER_ENTERING_WORLD" ; onEvent()
BUFFS = { player = {
  {"Interface\\Icons\\Spell_Nature_LightningShield", 3},
  {"Interface\\Icons\\INV_Potion_23", 0},
} }
arg1 = 2.0
local ok2, err2 = pcall(onUpdate)
if not ok2 then print("❌ ScanBuffs fejlede uden SuperWoW: " .. tostring(err2)) ; os.exit(1) end
print("✅ ScanBuffs kørt uden SuperWoW (tooltip-fallback)")
OUT = {}
local ok3, err3 = pcall(SlashCmdList["SHIELDBAR"], "debug")
if not ok3 then print("❌ /sb debug fejlede: " .. tostring(err3)) ; os.exit(1) end
for i = 1, math.min(#OUT, 5) do
  print("  " .. (OUT[i]:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")))
end
-- skade-routing uden school-info
event = "UNIT_COMBAT" ; arg1, arg2, arg3, arg4, arg5 = "player","WOUND","ABSORB",0,8
local ok4, err4 = pcall(onEvent)
if not ok4 then print("❌ UNIT_COMBAT fejlede: " .. tostring(err4)) ; os.exit(1) end
print("✅ skade-routing kørt uden SuperWoW")
