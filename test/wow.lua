-- Minimal WoW 1.12 API-stub: nok til at LOADE ShieldBar og koere scanneren.
string.gfind = string.gfind or string.gmatch
table.getn   = table.getn or function(t) return #t end
local unpackf = unpack or table.unpack

local G = {}
local function mock(name)
  local t = { __name = name, __scripts = {} }
  setmetatable(t, { __index = function(tbl, k)
    -- interne felter maa IKKE fanges af fallbacken nedenfor, ellers bliver
    -- tbl.__text til en funktion i stedet for nil
    if type(k) == "string" and string.sub(k, 1, 2) == "__" then return nil end
    if k == "GetText"   then return function() return tbl.__text end end
    if k == "GetValue"  then return function() return tbl.__value or 1 end end
    if k == "NumLines"  then return function() return 0 end end
    if k == "IsShown"   then return function() return tbl.__shown end end
    if k == "GetWidth"  then return function() return 100 end end
    if k == "GetHeight" then return function() return 100 end end
    if k == "SetScript" then return function(_, ev, fn) tbl.__scripts[ev] = fn end end
    if k == "SetPoint"  then return function(_, ...) tbl.__point = {...} ; return tbl end end
    if k == "ClearAllPoints" then return function() tbl.__point = nil ; return tbl end end
    if k == "GetScript" then return function(_, ev) return tbl.__scripts[ev] end end
    if k == "SetText"   then return function(_, v) tbl.__text = v end end
    if k == "SetValue"  then return function(_, v) tbl.__value = v end end
    -- WoW fyrer OnShow/OnHide naar synligheden faktisk skifter. Uden det
    -- ville stubben skjule fejl i kode der haenger paa de to scripts.
    if k == "Show" then return function()
      local was = tbl.__shown
      tbl.__shown = true
      if not was and tbl.__scripts.OnShow then
        local prev = this ; this = tbl ; tbl.__scripts.OnShow() ; this = prev
      end
    end end
    if k == "Hide" then return function()
      local was = tbl.__shown
      tbl.__shown = false
      if was and tbl.__scripts.OnHide then
        local prev = this ; this = tbl ; tbl.__scripts.OnHide() ; this = prev
      end
    end end
    if k == "CreateFontString" or k == "CreateTexture" then
      return function() return mock(name .. ".child") end
    end
    return function() return tbl end   -- alt andet: no-op, returnerer sig selv
  end })
  return t
end

ALLFRAMES = {}
function CreateFrame(ftype, name, parent, template)
  local f = mock(name or ("anon:" .. tostring(ftype)))
  f.__parent = parent
  ALLFRAMES[#ALLFRAMES+1] = f
  if name then
    G[name] = f
    for _, sfx in ipairs({"Text","Low","High","Middle","Left","Right","Thumb"}) do
      G[name .. sfx] = mock(name .. sfx)
    end
  end
  return f
end
function getglobal(n) if G[n] == nil then G[n] = mock(n) end return G[n] end
function setglobal(n, v) G[n] = v end
UIParent          = mock("UIParent")
DEFAULT_CHAT_FRAME= { AddMessage = function(_, m) OUT[#OUT+1] = tostring(m) end }
OUT               = {}
UISpecialFrames   = {}
GameTooltip       = mock("GameTooltip")
function GetTime() return 1000 end
function UnitClass() return "Warlock", PLAYER_CLASS or "MAGE" end
function UnitName(u) return u end
function UnitExists(u) return u == "player" or u == "target" end
function UnitLevel() return 60 end
function UnitAffectingCombat() return false end
function GetRealmName() return "OctoWow" end
function IsAddOnLoaded() return true end
function UnitGetTotalAbsorbs() error("not present in 1.12") end
-- SuperWoW:
SUPERWOW_VERSION = "1.5"
local SPELLNAMES = {}
function SpellInfo(id) return SPELLNAMES[id] or error("unknown spell " .. tostring(id)) end
-- styres af testen:
BUFFS = {}   -- liste af {texture, count, id}
function UnitBuff(unit, i)
  local list = BUFFS[unit]
  if not list or not list[i] then return nil end
  return unpackf(list[i])
end
function UnitDebuff() return nil end
function RegisterSpell(id, name) SPELLNAMES[id] = name end
SlashCmdList = {}
