-- ShieldBar.lua – Vanilla WoW 1.12.1 (Lua 5.0 compatible)
-- Displays remaining absorb shield HP as a segmented bar.
-- Supports: Power Word: Shield, Sacrifice, Ice Barrier, Frost/Fire Ward,
--           protection potions, and other absorb buffs.
--
-- Commands: /shieldbar  or  /sb
--   show       – always show bar (default)
--   hide       – only show bar when in combat AND a shield is active
--   vertical   – vertical bar layout
--   horizontal – horizontal bar layout
--   curve      – curved/bent bar shape
--   straight   – straight bar shape (default)
--   size <1-5> – bar size (3 = default)
--   lock       – lock bar position
--   unlock     – unlock bar position (drag with left mouse button)
--   reset      – reset ALL settings to default

-- ============================================================
-- Config
-- ============================================================
local CFG = {
    segments       = 20,
    defaultAnchorX = -60,
    defaultAnchorY = 0,
    colBot         = {1.0, 0.35, 0.0},
    colTop         = {1.0, 0.88, 0.0},
    colEmpty       = {0.15, 0.09, 0.02},
    colAlpha       = 1.0,
    colEmptyAlpha  = 0.70,
}

-- segW = long side of each segment, segH = short side, segGap = gap between segments
local SIZE_PRESETS = {
    {segW=20, segH=5,  segGap=2},
    {segW=27, segH=7,  segGap=2},
    {segW=34, segH=9,  segGap=3},
    {segW=44, segH=11, segGap=3},
    {segW=54, segH=14, segGap=4},
}

-- ============================================================
-- Absorb database: TEXTURE PATH -> fallback max absorb
-- UnitBuff() in 1.12.1 returns texture path as first value, not spell name.
-- ============================================================
local ABSORB_DB = {
    ["Interface\\Icons\\Spell_Holy_PowerWordShield"]      = 1265,
    ["Interface\\Icons\\Spell_Shadow_SacrificialShield"]  = 1470,
    ["Interface\\Icons\\Spell_Frost_IceBarrier"]          = 1100,
    ["Interface\\Icons\\Spell_Frost_FrostWard"]           = 714,
    ["Interface\\Icons\\Spell_Fire_FireWard"]             = 714,
    ["Interface\\Icons\\INV_Potion_96"]                   = 1400,
    ["Interface\\Icons\\INV_Potion_74"]                   = 900,
    ["Interface\\Icons\\INV_Potion_75"]                   = 1400,
    ["Interface\\Icons\\INV_Potion_80"]                   = 900,
    ["Interface\\Icons\\INV_Potion_56"]                   = 1400,
    ["Interface\\Icons\\INV_Potion_57"]                   = 900,
    ["Interface\\Icons\\INV_Potion_23"]                   = 1400,
    ["Interface\\Icons\\INV_Potion_24"]                   = 900,
    ["Interface\\Icons\\INV_Potion_97"]                   = 1400,
    ["Interface\\Icons\\INV_Potion_83"]                   = 1400,
    ["Interface\\Icons\\INV_Belt_13"]                     = 500,
}

-- ============================================================
-- State
-- ============================================================
local state = {
    current = 0,
    max     = 0,
    active  = false,
    tracked = {},
}

-- ============================================================
-- Settings  (loaded from ShieldBarDB in VARIABLES_LOADED)
-- ============================================================
local orientation = "vertical"
local hiddenMode  = false
local locked      = false
local inCombat    = false
local curved      = false
local curveFlip   = false
local barSize     = 3

local function LoadSettings()
    if not ShieldBarDB then return end
    if ShieldBarDB.orientation ~= nil then orientation = ShieldBarDB.orientation end
    if ShieldBarDB.hidden      ~= nil then hiddenMode  = ShieldBarDB.hidden      end
    if ShieldBarDB.locked      ~= nil then locked      = ShieldBarDB.locked      end
    if ShieldBarDB.curved      ~= nil then curved      = ShieldBarDB.curved      end
    if ShieldBarDB.curveFlip   ~= nil then curveFlip   = ShieldBarDB.curveFlip   end
    if ShieldBarDB.barSize     ~= nil then barSize     = ShieldBarDB.barSize     end
end

local function SaveSetting(key, value)
    if not ShieldBarDB then ShieldBarDB = {} end
    ShieldBarDB[key] = value
end

-- ============================================================
-- UI
-- ============================================================
local barFrame, numText
local segs     = {}
local barReady = false

local function UpdateVisibility()
    if not barReady then return end
    if hiddenMode then
        if inCombat and state.active then
            barFrame:Show()
        else
            barFrame:Hide()
        end
    else
        barFrame:Show()
    end
end

local function SavePosition()
    if not barFrame then return end
    local point, _, relPoint, x, y = barFrame:GetPoint(1)
    if not point then return end
    SaveSetting("posPoint",    point)
    SaveSetting("posRelPoint", relPoint)
    SaveSetting("posX",        x)
    SaveSetting("posY",        y)
end

local function ApplyPosition()
    barFrame:ClearAllPoints()
    if ShieldBarDB and ShieldBarDB.posX and ShieldBarDB.posY and ShieldBarDB.posPoint then
        barFrame:SetPoint(ShieldBarDB.posPoint, UIParent, ShieldBarDB.posRelPoint,
                          ShieldBarDB.posX, ShieldBarDB.posY)
    else
        barFrame:SetPoint("RIGHT", UIParent, "RIGHT", CFG.defaultAnchorX, CFG.defaultAnchorY)
    end
end

local function LayoutBar()
    if not barReady then return end
    local cfg  = CFG
    local sz   = SIZE_PRESETS[barSize]
    local segW, segH, segGap = sz.segW, sz.segH, sz.segGap
    local vert = (orientation == "vertical")

    -- maxIndent: how many pixels narrower the middle segments become (crescent shape).
    local maxIndent = curved and math.floor(segW * 0.55) or 0

    if vert then
        local totalSpan = cfg.segments * (segH + segGap) - segGap
        barFrame:SetWidth(segW + 14)
        barFrame:SetHeight(totalSpan + 26)
    else
        local totalSpan = cfg.segments * (segH + segGap) - segGap
        barFrame:SetWidth(totalSpan + 14)
        barFrame:SetHeight(segW + 14)
    end

    for i = 1, cfg.segments do
        local seg = segs[i]
        seg:ClearAllPoints()

        local t      = (i - 1) / math.max(cfg.segments - 1, 1)
        local indent = math.floor(math.sin(t * math.pi) * maxIndent)
        local w      = math.max(4, segW - indent)

        if vert then
            local yOff = (i-1) * (segH + segGap)
            seg:SetWidth(w)
            seg:SetHeight(segH)
            if curveFlip then
                seg:SetPoint("BOTTOMLEFT",  barFrame, "BOTTOMLEFT",  7,  yOff + 18)
            else
                seg:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -7, yOff + 18)
            end

            seg.topEdge:ClearAllPoints()
            seg.topEdge:SetPoint("TOPLEFT",  seg, "TOPLEFT",  0, 0)
            seg.topEdge:SetPoint("TOPRIGHT", seg, "TOPRIGHT", 0, 0)
            seg.topEdge:SetHeight(2)

            seg.shine:ClearAllPoints()
            seg.shine:SetPoint("TOPLEFT",  seg, "TOPLEFT",  0, -2)
            seg.shine:SetPoint("TOPRIGHT", seg, "TOPRIGHT", 0, -2)
            seg.shine:SetHeight(2)
        else
            local xOff = (i-1) * (segH + segGap)
            local h    = math.max(4, segW - indent)
            seg:SetWidth(segH)
            seg:SetHeight(h)
            if curveFlip then
                seg:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", xOff + 7, 18)
            else
                seg:SetPoint("TOPLEFT",    barFrame, "TOPLEFT",    xOff + 7, -18)
            end

            seg.topEdge:ClearAllPoints()
            seg.topEdge:SetPoint("TOPRIGHT",    seg, "TOPRIGHT",    0, 0)
            seg.topEdge:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", 0, 0)
            seg.topEdge:SetWidth(2)

            seg.shine:ClearAllPoints()
            seg.shine:SetPoint("TOPRIGHT",    seg, "TOPRIGHT",    -2, 0)
            seg.shine:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", -2, 0)
            seg.shine:SetWidth(2)
        end
    end

    numText:ClearAllPoints()
    numText:SetPoint("BOTTOM", barFrame, "BOTTOM", 0, 0)
end

local function CreateBar()
    if barReady then return end
    barReady = true

    barFrame = CreateFrame("Frame", "ShieldBarFrame", UIParent)
    barFrame:SetFrameStrata("HIGH")
    barFrame:SetMovable(true)
    barFrame:EnableMouse(true)
    barFrame:RegisterForDrag("LeftButton")
    barFrame:SetScript("OnDragStart", function()
        if not locked then barFrame:StartMoving() end
    end)
    barFrame:SetScript("OnDragStop", function()
        barFrame:StopMovingOrSizing()
        SavePosition()
    end)

    for i = 1, CFG.segments do
        local seg = CreateFrame("Frame", nil, barFrame)

        local fill = seg:CreateTexture(nil, "ARTWORK")
        fill:SetTexture("Interface\\Buttons\\WHITE8X8")
        fill:SetAllPoints(seg)
        fill:SetVertexColor(CFG.colEmpty[1], CFG.colEmpty[2], CFG.colEmpty[3], CFG.colEmptyAlpha)

        local topEdge = seg:CreateTexture(nil, "OVERLAY")
        topEdge:SetTexture("Interface\\Buttons\\WHITE8X8")
        topEdge:SetVertexColor(0, 0, 0, 0)

        local shine = seg:CreateTexture(nil, "OVERLAY")
        shine:SetTexture("Interface\\Buttons\\WHITE8X8")
        shine:SetVertexColor(1, 1, 1, 0)

        seg.fill    = fill
        seg.topEdge = topEdge
        seg.shine   = shine
        segs[i]     = seg
    end

    numText = barFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    numText:SetTextColor(1.0, 0.85, 0.1, 1.0)
    numText:SetText("")

    LayoutBar()
    ApplyPosition()
    UpdateVisibility()
end

local function UpdateBar()
    if not barReady then return end
    local cfg = CFG

    if not state.active or state.max == 0 then
        for i = 1, cfg.segments do
            segs[i].fill:SetVertexColor(cfg.colEmpty[1], cfg.colEmpty[2], cfg.colEmpty[3], cfg.colEmptyAlpha)
            segs[i].topEdge:SetVertexColor(0, 0, 0, 0)
            segs[i].shine:SetVertexColor(1, 1, 1, 0)
        end
        numText:SetText("")
        UpdateVisibility()
        return
    end

    local ratio  = math.max(0, state.current / state.max)
    local filled = math.ceil(ratio * cfg.segments)

    for i = 1, cfg.segments do
        if i <= filled then
            local t = (i-1) / math.max(cfg.segments - 1, 1)
            local r = cfg.colBot[1] + (cfg.colTop[1] - cfg.colBot[1]) * t
            local g = cfg.colBot[2] + (cfg.colTop[2] - cfg.colBot[2]) * t
            local b = cfg.colBot[3] + (cfg.colTop[3] - cfg.colBot[3]) * t
            segs[i].fill:SetVertexColor(r, g, b, cfg.colAlpha)
            segs[i].topEdge:SetVertexColor(0, 0, 0, 0.65)
            if i == filled then
                segs[i].shine:SetVertexColor(1, 1, 1, 0.30)
            else
                segs[i].shine:SetVertexColor(1, 1, 1, 0.10)
            end
        else
            segs[i].fill:SetVertexColor(cfg.colEmpty[1], cfg.colEmpty[2], cfg.colEmpty[3], cfg.colEmptyAlpha)
            segs[i].topEdge:SetVertexColor(0, 0, 0, 0)
            segs[i].shine:SetVertexColor(1, 1, 1, 0)
        end
    end

    numText:SetText(tostring(math.max(0, state.current)))
    UpdateVisibility()
end

-- ============================================================
-- Tooltip scanning
-- ============================================================
local ScanTip = CreateFrame("GameTooltip", "ShieldBarScanTip", UIParent, "GameTooltipTemplate")

local function GetAbsorbFromTooltip(unit, buffIdx)
    local ok = pcall(function()
        ScanTip:SetOwner(UIParent, "ANCHOR_NONE")
        ScanTip:ClearLines()
        ScanTip:SetUnitBuff(unit, buffIdx)
    end)
    if not ok then return nil end
    for i = 1, ScanTip:NumLines() do
        local line = getglobal("ShieldBarScanTipTextLeft" .. i)
        if line then
            local txt = line:GetText()
            if txt then
                local _, _, v = string.find(txt, "[Aa]bsorbing (%d+)")
                if not v then _, _, v = string.find(txt, "[Aa]bsorbs? up to (%d+)") end
                if not v then _, _, v = string.find(txt, "[Aa]bsorbs? (%d+)") end
                v = tonumber(v)
                if v and v > 0 then ScanTip:Hide() ; return v end
            end
        end
    end
    ScanTip:Hide()
    return nil
end

-- ============================================================
-- Buff scanning
-- ============================================================
local function ScanBuffs()
    local newTracked = {}
    local newMax     = 0

    for i = 1, 32 do
        local texture = UnitBuff("player", i)
        if not texture then break end
        if ABSORB_DB[texture] then
            local maxAbs = GetAbsorbFromTooltip("player", i)
            if not maxAbs or maxAbs == 0 then maxAbs = ABSORB_DB[texture] end
            if maxAbs and maxAbs > 0 then
                newTracked[texture] = maxAbs
                newMax = newMax + maxAbs
            end
        end
    end

    local addedAbs = 0
    for name, maxAbs in pairs(newTracked) do
        if not state.tracked[name] then addedAbs = addedAbs + maxAbs end
    end

    local removedMax = 0
    for name, maxAbs in pairs(state.tracked) do
        if not newTracked[name] then removedMax = removedMax + maxAbs end
    end

    if newMax == 0 then
        state.current = 0 ; state.max = 0 ; state.active = false
    else
        if state.max == 0 then
            state.current = newMax
        else
            state.current = state.current + addedAbs
            if removedMax > 0 and state.max > 0 then
                state.current = math.floor(state.current * (newMax / state.max))
            end
        end
        state.current = math.min(state.current, newMax)
        state.current = math.max(state.current, 0)
        state.max     = newMax
        state.active  = true
    end

    state.tracked = newTracked
    UpdateBar()
end

-- ============================================================
-- Absorb tracking (rolling average estimation)
-- UNIT_COMBAT fires with arg3="ABSORB" but arg4=0 – amount unavailable in 1.12.1.
-- ============================================================
local recentHits = {}
local estAvgHit  = 30

local function UpdateHitAverage(amount)
    if amount <= 0 then return end
    table.insert(recentHits, amount)
    if table.getn(recentHits) > 8 then table.remove(recentHits, 1) end
    local s = 0
    for _, v in pairs(recentHits) do s = s + v end
    estAvgHit = math.max(1, math.floor(s / table.getn(recentHits)))
end

local function TryGetTotalAbsorbs()
    local ok, v = pcall(UnitGetTotalAbsorbs, "player")
    if ok and type(v) == "number" then return v end
    return nil
end

local function OnAbsorbedDamage(estimatedAmount)
    if not state.active then return end
    local exact = TryGetTotalAbsorbs()
    if exact ~= nil then
        state.current = exact ; state.active = (exact > 0)
    else
        state.current = math.max(0, state.current - estimatedAmount)
        if state.current == 0 then state.active = false end
    end
    UpdateBar()
end

local function ExtractAbsorbed(msg)
    local low = string.lower(msg)
    local _, _, v = string.find(low, "%((%d+) absorbed")
    if v then return tonumber(v) end
    _, _, v = string.find(low, "absorbed (%d+)")
    return tonumber(v)
end

-- ============================================================
-- Slash commands  (/shieldbar  or  /sb)
-- ============================================================
local function HandleCommand(msg)
    if msg == "show" then
        hiddenMode = false
        SaveSetting("hidden", false)
        UpdateVisibility()
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Bar will |cff00FF00always|r be visible.")

    elseif msg == "hide" then
        hiddenMode = true
        SaveSetting("hidden", true)
        UpdateVisibility()
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Bar will |cffFF8800only show when in combat with an active shield|r.")

    elseif msg == "lock" then
        locked = true
        SaveSetting("locked", true)
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Bar locked.")

    elseif msg == "unlock" then
        locked = false
        SaveSetting("locked", false)
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Bar unlocked. Drag with left mouse button.")

    elseif msg == "vertical" then
        orientation = "vertical"
        SaveSetting("orientation", "vertical")
        LayoutBar()
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Layout set to |cffFFFF00vertical|r.")

    elseif msg == "horizontal" then
        orientation = "horizontal"
        SaveSetting("orientation", "horizontal")
        LayoutBar()
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Layout set to |cffFFFF00horizontal|r.")

    elseif msg == "curve" then
        curved = true
        SaveSetting("curved", true)
        LayoutBar()
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Bar shape set to |cffFFFF00curved|r.")

    elseif msg == "straight" then
        curved = false
        SaveSetting("curved", false)
        LayoutBar()
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Bar shape set to |cffFFFF00straight|r.")

    elseif msg == "curve rotate" then
        curveFlip = not curveFlip
        SaveSetting("curveFlip", curveFlip)
        LayoutBar()
        local dir = curveFlip and "flipped" or "normal"
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Curve direction: |cffFFFF00" .. dir .. "|r.")

    elseif msg == "reset" then
        ShieldBarDB  = {}
        orientation  = "vertical"
        hiddenMode   = false
        locked       = false
        curved       = false
        curveFlip    = false
        barSize      = 3
        LayoutBar()
        ApplyPosition()
        UpdateVisibility()
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r All settings reset to default.")

    else
        local _, _, sizeStr = string.find(msg, "^size (%d)$")
        if sizeStr then
            local s = tonumber(sizeStr)
            if s and s >= 1 and s <= 5 then
                barSize = s
                SaveSetting("barSize", s)
                LayoutBar()
                DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Size set to |cffFFFF00" .. s .. "|r.")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Size must be between 1 and 5.")
            end
        else
            local modeStr  = hiddenMode and "|cffFF8800hide|r" or "|cff00FF00show|r"
            local shapeStr = curved     and "|cffFFFF00curved|r" or "|cffFFFF00straight|r"
            DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar|r v1.5  –  mode: " .. modeStr .. "  shape: " .. shapeStr .. "  size: |cffFFFF00" .. barSize .. "|r")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb show|r        – always show bar")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb hide|r        – only show when in combat + shield active")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb vertical|r    – vertical layout")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb horizontal|r  – horizontal layout")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb curve|r          – curved bar shape")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb curve rotate|r  – flip curve direction")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb straight|r      – straight bar shape")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb size 1-5|r    – bar size (3 = default)")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb lock|r        – lock position")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb unlock|r      – unlock position")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffFFFF00/sb reset|r       – reset ALL settings to default")
        end
    end
end

SLASH_SHIELDBAR1 = "/shieldbar"
SLASH_SHIELDBAR2 = "/sb"
SlashCmdList["SHIELDBAR"] = function(msg) HandleCommand(msg) end

-- ============================================================
-- Events
-- ============================================================
local evFrame = CreateFrame("Frame", "ShieldBarEventFrame", UIParent)
evFrame:RegisterEvent("VARIABLES_LOADED")
evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
evFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
evFrame:RegisterEvent("UNIT_AURA")
evFrame:RegisterEvent("UNIT_COMBAT")
evFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
evFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")
evFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
evFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
evFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
evFrame:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")

local pollTimer = 0
evFrame:SetScript("OnUpdate", function()
    pollTimer = pollTimer + arg1
    if pollTimer >= 1.0 then
        pollTimer = 0
        ScanBuffs()
    end
end)

evFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        LoadSettings()

    elseif event == "PLAYER_ENTERING_WORLD" then
        CreateBar()
        ScanBuffs()

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        UpdateVisibility()

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UpdateVisibility()

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then ScanBuffs() end

    elseif event == "UNIT_COMBAT" then
        if arg1 == "player" and arg2 == "WOUND" then
            local amt = tonumber(arg4) or 0
            if arg3 == "ABSORB" then
                OnAbsorbedDamage(estAvgHit)
            elseif amt > 0 then
                UpdateHitAverage(amt)
            end
        end

    elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"
        or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"
        or event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"
        or event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE"
        or event == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE"
        or event == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF"
    then
        local absorbed = ExtractAbsorbed(arg1)
        if absorbed then OnAbsorbedDamage(absorbed) end
    end
end)

DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar|r v1.5 loaded.  |cffFFFF00/sb|r for commands.")
