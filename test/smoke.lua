dofile("wow.lua")
PLAYER_CLASS = "WARLOCK"
RegisterSpell(6229,  "Shadow Ward")
RegisterSpell(7301,  "Shadow Protection")
RegisterSpell(20911, "Blessing of Sanctuary")
RegisterSpell(17548, "Greater Shadow Protection Potion")
RegisterSpell(7233,  "Fire Protection Potion")

local ok, err = pcall(dofile, os.getenv("HOME") .. "/ShieldBar/ShieldBar.lua")
if not ok then print("❌ LOAD FEJLEDE: " .. tostring(err)) ; os.exit(1) end
print("✅ addon loadet uden fejl")

-- Find event- og update-handlers via de globale frames stubben gemte
local ev = getglobal("ShieldBarEventFrame")
local onEvent, onUpdate = ev:GetScript("OnEvent"), ev:GetScript("OnUpdate")
if not onEvent or not onUpdate then print("❌ handlers ikke registreret") ; os.exit(1) end

-- VARIABLES_LOADED
event = "VARIABLES_LOADED" ; ShieldBarDB = nil
local ok2, err2 = pcall(onEvent)
if not ok2 then print("❌ VARIABLES_LOADED fejlede: " .. tostring(err2)) ; os.exit(1) end
print("✅ VARIABLES_LOADED kørt")

-- PLAYER_ENTERING_WORLD: bygger bjælken (root). Spillet fyrer den foer brugeren
-- kan taste noget, saa dette er den realistiske raekkefoelge.
event = "PLAYER_ENTERING_WORLD"
local okP, errP = pcall(onEvent)
if not okP then print("❌ PLAYER_ENTERING_WORLD fejlede: " .. tostring(errP)) ; os.exit(1) end
print("✅ PLAYER_ENTERING_WORLD kørt (bjælken bygget)")

-- Warlock med: ægte Shadow Ward + Shadow Protection (kollision!) + en fire-potion
BUFFS = { player = {
  {"Interface\\Icons\\Spell_Shadow_AntiShadow", 0, 6229},   -- ægte Shadow Ward
  {"Interface\\Icons\\INV_Potion_23",           0, 7233},   -- Fire Protection Potion
} }
arg1 = 2.0
local ok3, err3 = pcall(onUpdate)
if not ok3 then print("❌ ScanBuffs fejlede: " .. tostring(err3)) ; os.exit(1) end
print("✅ ScanBuffs kørt (Shadow Ward + fire-potion aktive)")

-- Nu med kollisionen: Shadow Protection i stedet for Shadow Ward
BUFFS.player = {
  {"Interface\\Icons\\Spell_Shadow_AntiShadow", 0, 7301},   -- Shadow Protection!
  {"Interface\\Icons\\Spell_Nature_LightningShield", 0, 20911}, -- Blessing of Sanctuary
}
arg1 = 2.0
local ok4, err4 = pcall(onUpdate)
if not ok4 then print("❌ ScanBuffs (kollision) fejlede: " .. tostring(err4)) ; os.exit(1) end
print("✅ ScanBuffs kørt (kun kolliderende buffs)")

-- Kombat-event der ruter skade
event = "UNIT_COMBAT" ; arg1, arg2, arg3, arg4, arg5 = "player", "WOUND", "ABSORB", 0, 16
local ok5, err5 = pcall(onEvent)
if not ok5 then print("❌ UNIT_COMBAT fejlede: " .. tostring(err5)) ; os.exit(1) end
print("✅ UNIT_COMBAT (shadow) kørt")

-- Slash-kommandoer, inkl. debug og GUI-opbygning
BUFFS.player = { {"Interface\\Icons\\Spell_Shadow_AntiShadow", 0, 6229} }
for _, cmd in ipairs({"debug","hide","show","lock","unlock","vertical","horizontal",
                      "curve","straight","curve rotate","size 4","size 9","","reset","vrøvl"}) do
  local ok6, err6 = pcall(SlashCmdList["SHIELDBAR"], cmd)
  if not ok6 then print("❌ /sb " .. cmd .. " fejlede: " .. tostring(err6)) ; os.exit(1) end
end
print("✅ alle slash-kommandoer kørt (inkl. GUI-opbygning og /sb debug)")
print("\n--- uddrag af /sb debug-output ---")
for i = 1, math.min(#OUT, 6) do print("  " .. (OUT[i]:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""))) end
