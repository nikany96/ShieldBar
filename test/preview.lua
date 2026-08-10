dofile("wow.lua")
PLAYER_CLASS = "SHAMAN"
RegisterSpell(324,"Lightning Shield")
dofile(os.getenv("HOME") .. "/ShieldBar/ShieldBar.lua")
local ev = getglobal("ShieldBarEventFrame")
local onEvent, onUpdate = ev:GetScript("OnEvent"), ev:GetScript("OnUpdate")
event = "VARIABLES_LOADED" ; onEvent()
event = "PLAYER_ENTERING_WORLD" ; onEvent()
local root = getglobal("ShieldBarFrame")

local function bars()
  local shown, xs = 0, {}
  for _, f in ipairs(ALLFRAMES) do
    if f.__parent == root and f.__point then
      if f.__shown then shown = shown + 1 ; xs[#xs+1] = tostring(f.__point[4]) end
    end
  end
  return shown, table.concat(xs, ",")
end
local fail = 0
local function want(label, got, exp)
  local ok = (got == exp)
  if not ok then fail = fail + 1 end
  print(string.format("%s %-46s %s", ok and "✅" or "❌", label, tostring(got))
        .. (ok and "" or ("   ventede: " .. tostring(exp))))
end

-- Ingen skjolde oppe overhovedet
BUFFS = { player = {} } ; arg1 = 2.0 ; onUpdate()
local n = bars() ; want("uden skjolde: 1 tom bjaelke (traekbar)", n, 1)

-- Aabn options -> eksemplet skal vise 3
SlashCmdList["SHIELDBAR"]("")
n = bars() ; want("options aaben: eksempel med 3 bjaelker", n, 3)

-- Grow-retning skal virke I eksemplet
SlashCmdList["SHIELDBAR"]("grow right") ; local _, xr = bars()
SlashCmdList["SHIELDBAR"]("grow left")  ; local _, xl = bars()
want("grow right i eksempel", xr, "0,108,216")
want("grow left i eksempel (omvendt)", xl, "216,108,0")

-- ScanBuffs maa ikke pille ved eksemplet
arg1 = 2.0 ; onUpdate()
n = bars() ; want("eksempel overlever ScanBuffs", n, 3)

-- "kun i kamp" maa ikke skjule eksemplet
SlashCmdList["SHIELDBAR"]("hide")
want("eksempel synligt trods 'kun i kamp'", root.__shown, true)

-- Skade under eksempel maa ikke crashe (og routes mod de RIGTIGE skjolde)
event = "UNIT_COMBAT" ; arg1,arg2,arg3,arg4,arg5 = "player","WOUND","ABSORB",0,2
local ok = pcall(onEvent) ; want("skade under eksempel crasher ikke", ok, true)

-- Luk med Escape/X -> OnHide skal rydde op
getglobal("ShieldBarConfig"):Hide()
SlashCmdList["SHIELDBAR"]("show")
n = bars() ; want("efter lukning: tilbage til virkeligheden", n, 1)

-- Med et aegte skjold oppe
BUFFS = { player = { {"Interface\\Icons\\Spell_Nature_LightningShield", 3, 324} } }
arg1 = 2.0 ; onUpdate()
n = bars() ; want("aegte skjold vises efter lukning", n, 1)
SlashCmdList["SHIELDBAR"]("")
n = bars() ; want("options aaben igen: eksempel vinder", n, 3)
getglobal("ShieldBarConfig"):Hide()
n = bars() ; want("lukket igen: aegte skjold tilbage", n, 1)

print(fail == 0 and "\n✅ ALT OK" or "\n❌ " .. fail .. " FEJL")
os.exit(fail == 0 and 0 or 1)
