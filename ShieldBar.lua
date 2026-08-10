-- ShieldBar.lua – Vanilla WoW 1.12.1 (Lua 5.0 compatible)
-- One segmented bar per active shield.
--   Absorb shields – bar shows remaining absorb HP:
--       Power Word: Shield, Sacrifice, Ice Barrier, Frost/Fire/Shadow Ward,
--       Mana Shield, protection potions
--   Charge shields – bar shows remaining charges:
--       Water Shield, Lightning Shield, Earth Shield (also tracked on target/party)
--
-- /shieldbar  or  /sb  opens the options window.
-- Right-clicking a bar opens it too.
--
-- The old text commands still work for macros:
--   show / hide, vertical / horizontal, curve / straight, curve rotate,
--   grow right|left|down|up, size <1-5>, lock / unlock, debug, reset

-- ============================================================
-- Config
-- ============================================================
local CFG = {
    segments      = 20,
    maxBars       = 6,
    barGap        = 8,
    defaultAnchorX = -60,
    defaultAnchorY = 0,
    colBot        = {1.0, 0.35, 0.0},   -- default gradient (bottom / start)
    colTop        = {1.0, 0.88, 0.0},   -- default gradient (top / end)
    colEmpty      = {0.15, 0.09, 0.02},
    colAlpha      = 1.0,
    colEmptyAlpha = 0.70,
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
-- Shield database, keyed by TEXTURE PATH
-- UnitBuff() in 1.12.1 returns the texture path as first value, not the spell name,
-- which is why shields are keyed by icon. SuperWoW adds the spell id as a third
-- return; when present it is used to resolve shared icons exactly (see `guard`).
--
--   fallback – absorb assumed when the tooltip carries no number (max rank)
--   ranks    – {minLevel, absorb} pairs; beats `fallback` while levelling
--   school   – ward only absorbs this damage school; nil = absorbs everything
--   guard    – required buff name, for icons shared with non-absorb buffs.
--              Under SuperWoW the name comes from the aura's spell id and is
--              exact; without it we read the tooltip and, if that is unreadable,
--              accept the buff rather than dropping a real shield.
--   class    – only ever trust this icon on this class (self-cast shields only).
--              Cheap first filter that works even when the tooltip is unreadable.
--              Never set it on shields that land on OTHER players (PW:S, Earth
--              Shield), or they would vanish for everyone but the caster's class.
--   colBot/colTop – per-shield gradient so bars are told apart at a glance
--   charges  – charge-based shield: the bar tracks UnitBuff stacks, not absorb HP
--   scanRaid – also look for this buff on target/party (Earth Shield sits on others)
-- ============================================================
local DEFAULT_POTION_COL = { bot = {0.10, 0.45, 0.15}, top = {0.60, 1.00, 0.45} }

local SHIELDS = {
    ["Interface\\Icons\\Spell_Holy_PowerWordShield"] = {
        fallback = 1265,
        colBot = {0.35, 0.35, 0.80}, colTop = {0.95, 0.95, 1.00},
    },
    ["Interface\\Icons\\Spell_Shadow_SacrificialShield"] = {
        fallback = 1470, class = "WARLOCK",
        colBot = {0.40, 0.10, 0.50}, colTop = {0.95, 0.55, 1.00},
    },
    -- Shares its icon with the rogue cooldown Cold Blood.
    ["Interface\\Icons\\Spell_Ice_Lament"] = {                       -- Ice Barrier
        fallback = 1100, class = "MAGE", guard = "ice barrier",
        colBot = {0.10, 0.45, 0.70}, colTop = {0.75, 0.98, 1.00},
    },
    -- Shares its icon with the Frost Resistance totem/aura buff.
    ["Interface\\Icons\\Spell_Frost_FrostWard"] = {                  -- Frost Ward
        fallback = 890, school = "frost", class = "MAGE", guard = "frost ward",
        ranks = {{22,165}, {32,290}, {42,470}, {52,675}, {60,890}},
        colBot = {0.05, 0.35, 0.85}, colTop = {0.55, 0.90, 1.00},
    },
    -- Shares its icon with Fire Resistance and Fire Shield.
    ["Interface\\Icons\\Spell_Fire_FireArmor"] = {                   -- Fire Ward
        fallback = 890, school = "fire", class = "MAGE", guard = "fire ward",
        ranks = {{20,165}, {28,290}, {38,470}, {48,675}, {58,890}},
        colBot = {0.85, 0.12, 0.00}, colTop = {1.00, 0.80, 0.25},
    },
    -- Heavy icon sharing: Shadow Protection (priest raid buff, lands on everyone),
    -- Shadow Resistance, Consume Shadows, Fel Stamina. The class filter alone is
    -- not enough here – a warlock carrying Shadow Protection passes it – so the
    -- name guard is what actually keeps this bar honest.
    ["Interface\\Icons\\Spell_Shadow_AntiShadow"] = {                -- Shadow Ward
        fallback = 875, school = "shadow", class = "WARLOCK", guard = "shadow ward",
        ranks = {{32,290}, {42,470}, {52,675}, {60,875}},
        colBot = {0.20, 0.05, 0.30}, colTop = {0.65, 0.35, 0.95},
    },
    ["Interface\\Icons\\Spell_Shadow_DetectLesserInvisibility"] = {  -- Mana Shield
        fallback = 570, class = "MAGE", guard = "mana shield",
        ranks = {{17,120}, {24,210}, {32,300}, {40,390}, {48,480}, {56,570}},
        colBot = {0.20, 0.20, 0.85}, colTop = {0.75, 0.55, 1.00},
    },
    -- Shaman charge shields: the bar shows remaining charges, not absorb HP.
    ["Interface\\Icons\\Ability_Shaman_WaterShield"] = {           -- Water Shield
        charges = true, class = "SHAMAN",
        colBot = {0.05, 0.30, 0.70}, colTop = {0.45, 0.85, 1.00},
    },
    -- This icon is ALSO the paladin's Blessing of Sanctuary and the priest's
    -- Shadowguard, so without both filters every buffed player grew a bar.
    ["Interface\\Icons\\Spell_Nature_LightningShield"] = {         -- Lightning Shield
        charges = true, class = "SHAMAN", guard = "lightning shield",
        colBot = {0.30, 0.25, 0.70}, colTop = {1.00, 0.95, 0.45},
    },
    -- No class filter: Earth Shield is cast on other people, any class can carry it.
    ["Interface\\Icons\\Spell_Nature_SkinofEarth"] = {             -- Earth Shield
        charges = true, scanRaid = true, guard = "earth shield",
        colBot = {0.08, 0.40, 0.12}, colTop = {0.50, 1.00, 0.45},
    },
    -- Alias: kept in case this build ships Earth Shield under its own icon name.
    -- Only one of the two can ever be active, so this cannot double up.
    ["Interface\\Icons\\Spell_Nature_EarthShield"] = {
        charges = true, scanRaid = true, guard = "earth shield",
        colBot = {0.08, 0.40, 0.12}, colTop = {0.50, 1.00, 0.45},
    },

    -- Protection potions. Which icon belongs to which potion was never recorded
    -- and cannot be looked up locally, so instead of a hardcoded school each of
    -- these resolves its own from the buff name at runtime (schoolFromName).
    -- A potion whose name carries no school stays generic and absorbs anything.
    ["Interface\\Icons\\INV_Potion_96"] = { fallback = 1400, schoolFromName = true },
    ["Interface\\Icons\\INV_Potion_74"] = { fallback = 900 , schoolFromName = true },
    ["Interface\\Icons\\INV_Potion_75"] = { fallback = 1400, schoolFromName = true },
    ["Interface\\Icons\\INV_Potion_80"] = { fallback = 900 , schoolFromName = true },
    ["Interface\\Icons\\INV_Potion_56"] = { fallback = 1400, schoolFromName = true },
    ["Interface\\Icons\\INV_Potion_57"] = { fallback = 900 , schoolFromName = true },
    ["Interface\\Icons\\INV_Potion_23"] = { fallback = 1400, schoolFromName = true },
    ["Interface\\Icons\\INV_Potion_24"] = { fallback = 900 , schoolFromName = true },
    ["Interface\\Icons\\INV_Potion_97"] = { fallback = 1400, schoolFromName = true },
    ["Interface\\Icons\\INV_Potion_83"] = { fallback = 1400, schoolFromName = true },
    ["Interface\\Icons\\INV_Belt_13"]   = { fallback = 500 , schoolFromName = true },
}

-- Fixed display order, so bars never jump around when one expires.
local ORDER = {
    "Interface\\Icons\\Ability_Shaman_WaterShield",
    "Interface\\Icons\\Spell_Nature_LightningShield",
    "Interface\\Icons\\Spell_Nature_SkinofEarth",
    "Interface\\Icons\\Spell_Nature_EarthShield",
    "Interface\\Icons\\Spell_Holy_PowerWordShield",
    "Interface\\Icons\\Spell_Shadow_SacrificialShield",
    "Interface\\Icons\\Spell_Ice_Lament",
    "Interface\\Icons\\Spell_Shadow_DetectLesserInvisibility",
    "Interface\\Icons\\Spell_Fire_FireArmor",
    "Interface\\Icons\\Spell_Frost_FrostWard",
    "Interface\\Icons\\Spell_Shadow_AntiShadow",
    "Interface\\Icons\\INV_Potion_96",
    "Interface\\Icons\\INV_Potion_74",
    "Interface\\Icons\\INV_Potion_75",
    "Interface\\Icons\\INV_Potion_80",
    "Interface\\Icons\\INV_Potion_56",
    "Interface\\Icons\\INV_Potion_57",
    "Interface\\Icons\\INV_Potion_23",
    "Interface\\Icons\\INV_Potion_24",
    "Interface\\Icons\\INV_Potion_97",
    "Interface\\Icons\\INV_Potion_83",
    "Interface\\Icons\\INV_Belt_13",
}

local SCHOOL_WORDS = {
    fire = true, frost = true, nature = true,
    shadow = true, arcane = true, holy = true,
}

-- Protection potions only absorb their own school, but which icon is which item
-- is not something we can look up – so read the school straight out of the buff
-- name instead ("Greater Fire Protection Potion" -> fire). Matched as a whole
-- word so a stray substring cannot invent a school. Returns nil for anything
-- that names no school, which leaves the shield generic exactly as before.
local function SchoolFromSpellName(name)
    if not name then return nil end
    for word in string.gfind(string.lower(name), "%a+") do
        if SCHOOL_WORDS[word] then return word end
    end
    return nil
end

local function ShieldColors(texture)
    local info = SHIELDS[texture]
    if info and info.colBot then return info.colBot, info.colTop end
    if info and info.fallback and string.find(texture, "Potion") then
        return DEFAULT_POTION_COL.bot, DEFAULT_POTION_COL.top
    end
    return CFG.colBot, CFG.colTop
end

local function FallbackAbsorb(texture)
    local info = SHIELDS[texture]
    if not info then return 0 end
    if info.ranks then
        local lvl  = UnitLevel("player") or 60
        local best = nil
        for i = 1, table.getn(info.ranks) do
            if lvl >= info.ranks[i][1] then best = info.ranks[i][2] end
        end
        if best then return best end
    end
    return info.fallback or 0
end

-- ============================================================
-- State: one entry per active shield
--   active[texture] = { cur = , max = , live = }
-- `live` means the tooltip reports remaining absorb, so no estimation is needed.
-- ============================================================
local active       = {}
local anyShield    = false
local lastBarCount = -1

local function AnyActive()
    return anyShield
end

-- Active shields in ORDER sequence
local function ActiveList()
    local list = {}
    for i = 1, table.getn(ORDER) do
        local tex = ORDER[i]
        if active[tex] then
            table.insert(list, tex)
            if table.getn(list) >= CFG.maxBars then break end
        end
    end
    return list
end

-- ============================================================
-- Preview: while the options window is open the real bars stand in as the
-- example, so what you see is the actual layout rather than a mock-up that
-- could drift from it. Three shields, so the growth direction is visible.
-- Deliberately kept out of `active`: ScanBuffs would wipe it a second later,
-- and absorbed damage must never be routed into a shield that isn't real.
-- ============================================================
local previewOn = false

local PREVIEW_ORDER = {
    "Interface\\Icons\\Ability_Shaman_WaterShield",
    "Interface\\Icons\\Spell_Holy_PowerWordShield",
    "Interface\\Icons\\Spell_Fire_FireArmor",
}
local PREVIEW = {
    ["Interface\\Icons\\Ability_Shaman_WaterShield"] = { cur = 3,   max = 3    },
    ["Interface\\Icons\\Spell_Holy_PowerWordShield"] = { cur = 820, max = 1265 },
    ["Interface\\Icons\\Spell_Fire_FireArmor"]       = { cur = 355, max = 890  },
}

-- What the bars should draw: the example while previewing, otherwise reality.
local function DisplayList()
    if previewOn then return PREVIEW_ORDER end
    return ActiveList()
end

local function DisplayData(texture)
    if previewOn then return PREVIEW[texture] end
    return active[texture]
end

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
-- false: extra bars stack right (vertical) / down (horizontal). true: the other way.
local growReverse = false

local function LoadSettings()
    if not ShieldBarDB then return end
    if ShieldBarDB.orientation ~= nil then orientation = ShieldBarDB.orientation end
    if ShieldBarDB.hidden      ~= nil then hiddenMode  = ShieldBarDB.hidden      end
    if ShieldBarDB.locked      ~= nil then locked      = ShieldBarDB.locked      end
    if ShieldBarDB.curved      ~= nil then curved      = ShieldBarDB.curved      end
    if ShieldBarDB.curveFlip   ~= nil then curveFlip   = ShieldBarDB.curveFlip   end
    if ShieldBarDB.barSize     ~= nil then barSize     = ShieldBarDB.barSize     end
    if ShieldBarDB.growReverse ~= nil then growReverse = ShieldBarDB.growReverse end
end

local function SaveSetting(key, value)
    if not ShieldBarDB then ShieldBarDB = {} end
    ShieldBarDB[key] = value
end

-- ============================================================
-- UI
-- ============================================================
local root                  -- movable parent frame
local bars     = {}         -- CFG.maxBars bar widgets, shown/hidden as needed
local barReady = false

local ToggleConfigUI        -- forward declaration; defined with the config GUI below

local ICON_SPACE = 20       -- room reserved for the shield icon
local TEXT_SPACE = 22       -- room reserved for the number

local function UpdateVisibility()
    if not barReady then return end
    -- The example is useless if "only show in combat" hides it while you are
    -- standing in the options window deciding whether to tick that very box.
    if previewOn then root:Show() return end
    if hiddenMode then
        if inCombat and AnyActive() then root:Show() else root:Hide() end
    else
        root:Show()
    end
end

local function SavePosition()
    if not root then return end
    local point, _, relPoint, x, y = root:GetPoint(1)
    if not point then return end
    SaveSetting("posPoint",    point)
    SaveSetting("posRelPoint", relPoint)
    SaveSetting("posX",        x)
    SaveSetting("posY",        y)
end

local function ApplyPosition()
    -- root only exists after PLAYER_ENTERING_WORLD built the bar; SavePosition
    -- and LayoutBar both guard for that, this one used to not.
    if not root then return end
    root:ClearAllPoints()
    if ShieldBarDB and ShieldBarDB.posX and ShieldBarDB.posY and ShieldBarDB.posPoint then
        root:SetPoint(ShieldBarDB.posPoint, UIParent, ShieldBarDB.posRelPoint,
                      ShieldBarDB.posX, ShieldBarDB.posY)
    else
        root:SetPoint("RIGHT", UIParent, "RIGHT", CFG.defaultAnchorX, CFG.defaultAnchorY)
    end
end

-- Lay out the segments inside a single bar widget
local function LayoutOneBar(bar)
    local sz   = SIZE_PRESETS[barSize]
    local segW, segH, segGap = sz.segW, sz.segH, sz.segGap
    local vert = (orientation == "vertical")
    local span = CFG.segments * (segH + segGap) - segGap

    -- maxIndent: how many pixels narrower the middle segments become (crescent shape).
    local maxIndent = curved and math.floor(segW * 0.55) or 0

    if vert then
        bar:SetWidth(segW + 14)
        bar:SetHeight(span + ICON_SPACE + TEXT_SPACE)
    else
        bar:SetWidth(span + ICON_SPACE + 8)
        bar:SetHeight(segW + TEXT_SPACE)
    end

    for i = 1, CFG.segments do
        local seg = bar.segs[i]
        seg:ClearAllPoints()

        local t      = (i - 1) / math.max(CFG.segments - 1, 1)
        local indent = math.floor(math.sin(t * math.pi) * maxIndent)

        if vert then
            local yOff = (i-1) * (segH + segGap)
            seg:SetWidth(math.max(4, segW - indent))
            seg:SetHeight(segH)
            if curveFlip then
                seg:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  7,  yOff + TEXT_SPACE)
            else
                seg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -7, yOff + TEXT_SPACE)
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
            seg:SetWidth(segH)
            seg:SetHeight(math.max(4, segW - indent))
            if curveFlip then
                seg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", xOff + ICON_SPACE, TEXT_SPACE)
            else
                seg:SetPoint("TOPLEFT",    bar, "TOPLEFT",    xOff + ICON_SPACE, 0)
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

    bar.icon:ClearAllPoints()
    bar.numText:ClearAllPoints()
    if vert then
        bar.icon:SetPoint("TOP", bar, "TOP", 0, -2)
        bar.numText:SetPoint("BOTTOM", bar, "BOTTOM", 0, 2)
    else
        bar.icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -1)
        bar.numText:SetPoint("BOTTOM", bar, "BOTTOM", ICON_SPACE / 2, 2)
    end

    local fontObj = (barSize >= 3) and "GameFontNormalLarge" or "GameFontNormal"
    bar.numText:SetFontObject(getglobal(fontObj))
end

-- Position the visible bars next to each other and resize the parent frame
local function LayoutBar()
    if not barReady then return end

    for i = 1, CFG.maxBars do LayoutOneBar(bars[i]) end

    local shown = DisplayList()
    local n     = table.getn(shown)
    if n == 0 then n = 1 end   -- keep one empty bar visible so the frame stays draggable

    local bw, bh = bars[1]:GetWidth(), bars[1]:GetHeight()
    local vert   = (orientation == "vertical")

    if vert then
        root:SetWidth(n * bw + (n - 1) * CFG.barGap)
        root:SetHeight(bh)
    else
        root:SetWidth(bw)
        root:SetHeight(n * bh + (n - 1) * CFG.barGap)
    end

    for i = 1, CFG.maxBars do
        local bar = bars[i]
        bar:ClearAllPoints()
        if i <= n then
            -- Which end of the frame bar 1 sits at. Reversing matters because the
            -- frame grows away from whichever edge it is anchored by, so this
            -- decides whether an extra shield pushes the existing bar aside or
            -- appears beside it.
            local slot = growReverse and (n - i) or (i - 1)
            if vert then
                bar:SetPoint("TOPLEFT", root, "TOPLEFT", slot * (bw + CFG.barGap), 0)
            else
                bar:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -slot * (bh + CFG.barGap))
            end
            bar:Show()
        else
            bar:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
            bar:Hide()
        end
    end
end

local function CreateBar()
    if barReady then return end
    barReady = true

    root = CreateFrame("Frame", "ShieldBarFrame", UIParent)
    root:SetFrameStrata("HIGH")
    root:SetMovable(true)
    root:EnableMouse(true)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", function()
        if not locked then root:StartMoving() end
    end)
    root:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        SavePosition()
    end)
    root:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" and ToggleConfigUI then ToggleConfigUI() end
    end)

    for b = 1, CFG.maxBars do
        local bar = CreateFrame("Frame", nil, root)
        bar.segs = {}

        for i = 1, CFG.segments do
            local seg = CreateFrame("Frame", nil, bar)

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
            bar.segs[i] = seg
        end

        bar.icon = bar:CreateTexture(nil, "OVERLAY")
        bar.icon:SetWidth(16)
        bar.icon:SetHeight(16)
        bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        bar.icon:Hide()

        bar.numText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        bar.numText:SetTextColor(1.0, 0.85, 0.1, 1.0)
        bar.numText:SetText("")

        bars[b] = bar
    end

    LayoutBar()
    ApplyPosition()
    UpdateVisibility()
end

local function ClearBar(bar)
    for i = 1, CFG.segments do
        bar.segs[i].fill:SetVertexColor(CFG.colEmpty[1], CFG.colEmpty[2], CFG.colEmpty[3], CFG.colEmptyAlpha)
        bar.segs[i].topEdge:SetVertexColor(0, 0, 0, 0)
        bar.segs[i].shine:SetVertexColor(1, 1, 1, 0)
    end
    bar.numText:SetText("")
    bar.icon:Hide()
end

local function DrawBar(bar, texture, shield)
    local colBot, colTop = ShieldColors(texture)
    local ratio  = math.max(0, shield.cur / math.max(shield.max, 1))
    local filled = math.ceil(ratio * CFG.segments)

    for i = 1, CFG.segments do
        if i <= filled then
            local t = (i-1) / math.max(CFG.segments - 1, 1)
            local r = colBot[1] + (colTop[1] - colBot[1]) * t
            local g = colBot[2] + (colTop[2] - colBot[2]) * t
            local b = colBot[3] + (colTop[3] - colBot[3]) * t
            bar.segs[i].fill:SetVertexColor(r, g, b, CFG.colAlpha)
            bar.segs[i].topEdge:SetVertexColor(0, 0, 0, 0.65)
            if i == filled then
                bar.segs[i].shine:SetVertexColor(1, 1, 1, 0.30)
            else
                bar.segs[i].shine:SetVertexColor(1, 1, 1, 0.10)
            end
        else
            bar.segs[i].fill:SetVertexColor(CFG.colEmpty[1], CFG.colEmpty[2], CFG.colEmpty[3], CFG.colEmptyAlpha)
            bar.segs[i].topEdge:SetVertexColor(0, 0, 0, 0)
            bar.segs[i].shine:SetVertexColor(1, 1, 1, 0)
        end
    end

    bar.numText:SetTextColor(colTop[1], colTop[2], colTop[3], 1.0)
    bar.numText:SetText(tostring(math.max(0, math.floor(shield.cur))))
    bar.icon:SetTexture(texture)
    bar.icon:Show()
end

local function UpdateBar()
    if not barReady then return end

    local shown = DisplayList()
    for i = 1, CFG.maxBars do
        local tex = shown[i]
        if tex then
            DrawBar(bars[i], tex, DisplayData(tex))
        else
            ClearBar(bars[i])
        end
    end

    UpdateVisibility()
end

-- ============================================================
-- Tooltip scanning
-- ============================================================
local ScanTip = CreateFrame("GameTooltip", "ShieldBarScanTip", UIParent, "GameTooltipTemplate")

local function OpenBuffTip(unit, buffIdx)
    return pcall(function()
        ScanTip:SetOwner(UIParent, "ANCHOR_NONE")
        ScanTip:ClearLines()
        ScanTip:SetUnitBuff(unit, buffIdx)
    end)
end

-- Buff name = tooltip line 1. Returns nil if the tooltip cannot be read.
local function GetBuffName(unit, buffIdx)
    if not OpenBuffTip(unit, buffIdx) then return nil end
    local line = getglobal("ShieldBarScanTipTextLeft1")
    local txt  = line and line:GetText()
    ScanTip:Hide()
    if not txt or txt == "" then return nil end
    return txt
end

-- Self-cast shields can only ever belong to one class. Checking that first is
-- free and – unlike the tooltip guard – cannot fail open, so a paladin's
-- Blessing of Sanctuary never reaches the Lightning Shield entry at all.
local playerClass
local function ClassOK(texture)
    local info = SHIELDS[texture]
    if not info or not info.class then return true end
    if not playerClass then
        local _, c = UnitClass("player")
        playerClass = c or "UNKNOWN"
    end
    return playerClass == info.class
end

-- SuperWoW hands the aura's spell id back as UnitBuff's third return, and
-- SpellInfo() turns that id into the real spell name. That is an exact answer
-- rather than a texture guess, so where it is available the guard can reject a
-- mismatch outright instead of having to give the buff the benefit of the doubt.
-- Names are cached per id – ScanBuffs runs every second and ids never change.
local spellNameCache = {}
local function SpellNameByID(id)
    if not id or not SpellInfo then return nil end
    local cached = spellNameCache[id]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local ok, name = pcall(SpellInfo, id)
    if not ok or not name or name == "" then
        spellNameCache[id] = false
        return nil
    end
    spellNameCache[id] = name
    return name
end

-- Texture is shared between spells – confirm this really is the spell we want.
-- Returns ok, exact.  `exact` is true when the verdict came from a spell id.
-- Without an id we fall back to reading the tooltip, and if even that is
-- unreadable we accept the match rather than dropping the shield.
local function NameGuardOK(unit, buffIdx, texture, id)
    local info = SHIELDS[texture]
    if not info or not info.guard then return true, true end

    local name = SpellNameByID(id)
    if name then
        return string.find(string.lower(name), info.guard, 1, true) ~= nil, true
    end

    name = GetBuffName(unit, buffIdx)
    if not name then return true, false end
    return string.find(string.lower(name), info.guard, 1, true) ~= nil, false
end

-- Returns absorb, isLive.  isLive = the tooltip reports REMAINING absorb
-- ("Absorbing 240"), so it can be used directly instead of estimating.
local function GetAbsorbFromTooltip(unit, buffIdx)
    if not OpenBuffTip(unit, buffIdx) then return nil end
    for i = 1, ScanTip:NumLines() do
        local line = getglobal("ShieldBarScanTipTextLeft" .. i)
        if line then
            local txt = line:GetText()
            if txt then
                local live = true
                local _, _, v = string.find(txt, "[Aa]bsorbing (%d+)")
                if not v then live = false ; _, _, v = string.find(txt, "[Aa]bsorbs? up to (%d+)") end
                if not v then live = false ; _, _, v = string.find(txt, "[Aa]bsorbs? (%d+)") end
                v = tonumber(v)
                if v and v > 0 then ScanTip:Hide() ; return v, live end
            end
        end
    end
    ScanTip:Hide()
    return nil, false
end

-- ============================================================
-- Buff scanning – each shield keeps its own current/max
-- ============================================================
local RAID_UNITS = { "target", "party1", "party2", "party3", "party4" }

local function ScanBuffs()
    local seen = {}

    for i = 1, 32 do
        -- Third return is SuperWoW's spell id; plain 1.12 simply leaves it nil.
        local texture, count, id = UnitBuff("player", i)
        if not texture then break end
        local info = SHIELDS[texture]
        if info and not seen[texture] and ClassOK(texture)
           and NameGuardOK("player", i, texture, id) then
            if info.charges then
                -- Charge shields report their stack count directly. Some servers
                -- return 0 for a single-stack buff, so never fall below 1.
                local n = tonumber(count) or 1
                if n < 1 then n = 1 end
                seen[texture] = { val = n, live = true }
            else
                local val, live = GetAbsorbFromTooltip("player", i)
                if not val or val == 0 then
                    val  = FallbackAbsorb(texture)
                    live = false
                end
                if val and val > 0 then
                    -- Potions carry no fixed school; derive it from the name once.
                    local school
                    if info.schoolFromName then
                        school = SchoolFromSpellName(
                            SpellNameByID(id) or GetBuffName("player", i))
                    end
                    seen[texture] = { val = val, live = live, school = school }
                end
            end
        end
    end

    -- Earth Shield usually sits on someone else – look at target and party too.
    for u = 1, table.getn(RAID_UNITS) do
        local unit = RAID_UNITS[u]
        if UnitExists(unit) then
            for i = 1, 32 do
                local texture, count, id = UnitBuff(unit, i)
                if not texture then break end
                local info = SHIELDS[texture]
                -- ClassOK is deliberately not applied here: these bars come off
                -- someone else's buff bar, so the player's own class says nothing.
                if info and info.scanRaid and not seen[texture]
                   and NameGuardOK(unit, i, texture, id) then
                    local n = tonumber(count) or 1
                    if n < 1 then n = 1 end
                    seen[texture] = { val = n, live = true }
                end
            end
        end
    end

    -- add / refresh
    for texture, info in pairs(seen) do
        local s = active[texture]
        if not s then
            active[texture] = { cur = info.val, max = info.val, live = info.live }
        elseif info.live then
            -- tooltip knows the exact remaining amount
            s.cur  = info.val
            s.max  = math.max(s.max, info.val)
            s.live = true
        elseif info.val > s.max then
            -- recast at a higher rank, or refreshed – treat as a new shield
            s.cur = info.val
            s.max = info.val
        end
        -- School resolved from the buff name (potions); nil for everything else.
        active[texture].school = info.school
    end

    -- remove expired
    for texture in pairs(active) do
        if not seen[texture] then active[texture] = nil end
    end

    anyShield = false
    for _ in pairs(active) do anyShield = true ; break end

    -- Re-laying out 6 bars x 20 segments every poll is wasteful; only do it
    -- when the number of visible bars actually changed.
    local n = table.getn(DisplayList())
    if n ~= lastBarCount then
        lastBarCount = n
        LayoutBar()
    end
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

local SCHOOL_BY_ID = {
    [0] = "physical", [1] = "holy", [2] = "fire",
    [4] = "nature",   [8] = "frost", [16] = "shadow", [32] = "arcane",
}

local function ExtractSchool(msg)
    local low = string.lower(msg or "")
    local _, _, w = string.find(low, "(%a+) damage")
    if w and SCHOOL_WORDS[w] then return w end
    return nil
end

local function ExtractAbsorbed(msg)
    local low = string.lower(msg)
    local _, _, v = string.find(low, "%((%d+) absorbed")
    if v then return tonumber(v) end
    _, _, v = string.find(low, "absorbed (%d+)")
    return tonumber(v)
end

-- Which shields can eat this damage, in the order they are consumed.
-- A ward only absorbs its own school; generic shields absorb anything.
-- When the school is unknown, generic shields go first and wards last.
-- A shield's school is normally fixed in SHIELDS, but potions resolve theirs
-- from the buff name at scan time and stash it on the active entry.
local function ShieldSchool(texture)
    local a = active[texture]
    if a and a.school then return a.school end
    return SHIELDS[texture].school
end

local function AbsorbOrder(school)
    local order = {}
    local list  = ActiveList()

    -- Charge shields (Water/Lightning/Earth Shield) do not absorb damage at all.
    if school then
        for i = 1, table.getn(list) do
            local info = SHIELDS[list[i]]
            if not info.charges and ShieldSchool(list[i]) == school then
                table.insert(order, list[i])
            end
        end
    end
    for i = 1, table.getn(list) do
        local info = SHIELDS[list[i]]
        if not info.charges and not ShieldSchool(list[i]) then
            table.insert(order, list[i])
        end
    end
    if not school then
        for i = 1, table.getn(list) do
            local info = SHIELDS[list[i]]
            if not info.charges and ShieldSchool(list[i]) then
                table.insert(order, list[i])
            end
        end
    end
    return order
end

local function TryGetTotalAbsorbs()
    local ok, v = pcall(UnitGetTotalAbsorbs, "player")
    if ok and type(v) == "number" then return v end
    return nil
end

local function OnAbsorbedDamage(amount, school)
    if not AnyActive() then return end

    -- If the server exposes the real total, a 0 means every shield is gone.
    local exact = TryGetTotalAbsorbs()
    if exact ~= nil and exact <= 0 then
        for _, s in pairs(active) do s.cur = 0 end
        UpdateBar()
        return
    end

    local left = amount
    local order = AbsorbOrder(school)
    for i = 1, table.getn(order) do
        if left <= 0 then break end
        local s = active[order[i]]
        if s and not s.live and s.cur > 0 then
            local taken = math.min(s.cur, left)
            s.cur = s.cur - taken
            left  = left - taken
        end
    end

    UpdateBar()
end

-- ============================================================
-- Shared actions (used by both the GUI and the slash fallbacks)
-- ============================================================
local function SetHiddenMode(v)
    hiddenMode = v
    SaveSetting("hidden", v)
    UpdateVisibility()
end

local function SetLocked(v)
    locked = v
    SaveSetting("locked", v)
end

local function SetOrientation(v)
    orientation = v
    SaveSetting("orientation", v)
    LayoutBar()
end

local function SetCurved(v)
    curved = v
    SaveSetting("curved", v)
    LayoutBar()
end

local function SetCurveFlip(v)
    curveFlip = v
    SaveSetting("curveFlip", v)
    LayoutBar()
end

local function SetGrowReverse(v)
    growReverse = v
    SaveSetting("growReverse", v)
    LayoutBar()
end

local function SetBarSize(v)
    if v < 1 or v > 5 then return end
    barSize = v
    SaveSetting("barSize", v)
    LayoutBar()
end

local function ResetAll()
    ShieldBarDB = {}
    orientation = "vertical"
    hiddenMode  = false
    locked      = false
    curved      = false
    curveFlip   = false
    barSize     = 3
    growReverse = false
    LayoutBar()
    ApplyPosition()
    UpdateVisibility()
end

local function DumpUnitBuffs(unit)
    if not UnitExists(unit) then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r buffs on |cffFFFFFF" ..
        (UnitName(unit) or unit) .. "|r (" .. unit .. "):")
    for i = 1, 32 do
        local texture, count, id = UnitBuff(unit, i)
        if not texture then break end
        local name   = SpellNameByID(id) or GetBuffName(unit, i) or "?"
        local info   = SHIELDS[texture]
        local status = "|cff888888ignored|r"
        local detail = ""
        if info then
            -- The player's own class only decides their own buffs; a shield
            -- read off someone else's bar is judged by the name guard alone.
            local classOK = (unit ~= "player") or ClassOK(texture)
            local guardOK, exact = NameGuardOK(unit, i, texture, id)
            if info.guard then
                detail = ", guard via " ..
                    (exact and "|cff00FF00spell id " .. tostring(id) .. "|r"
                           or "|cffFFAA00tooltip (fail-open)|r")
            end
            if not classOK then
                status = "|cffFF5555wrong class (" .. tostring(info.class) .. ")|r"
            elseif guardOK then
                status = "|cff00FF00tracked|r"
                if info.charges then
                    detail = detail .. ", charges: " .. tostring(tonumber(count) or 1)
                else
                    local abs, live = GetAbsorbFromTooltip(unit, i)
                    detail = detail .. ", tooltip absorb: " .. (abs or "none") ..
                             (live and " (live)" or "") ..
                             ", fallback " .. tostring(FallbackAbsorb(texture))
                end
            else
                status = "|cffFF5555name guard rejected|r"
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage("  " .. i .. ": |cffFFFF00" .. name .. "|r  " .. texture)
        DEFAULT_CHAT_FRAME:AddMessage("      " .. status .. detail)
    end
end

local function DumpBuffs()
    if SpellInfo then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r SuperWoW detected (" ..
            tostring(SUPERWOW_VERSION or "version unknown") ..
            ") - shields identified by |cff00FF00spell id|r.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r no SuperWoW - falling back to " ..
            "|cffFFAA00texture + tooltip|r. Shared icons rely on the tooltip being readable.")
    end
    DumpUnitBuffs("player")
    DumpUnitBuffs("target")
end

-- ============================================================
-- Config GUI
-- ============================================================
local cfgFrame
local ui          = {}
local refreshing  = false   -- guards SetChecked/SetValue from firing handlers

local function RefreshConfigUI()
    if not cfgFrame then return end
    refreshing = true

    ui.combat:SetChecked(hiddenMode)
    ui.lock:SetChecked(locked)
    ui.vertical:SetChecked(orientation == "vertical")
    ui.horizontal:SetChecked(orientation ~= "vertical")
    ui.growNormal:SetChecked(not growReverse)
    ui.growReverse:SetChecked(growReverse)
    -- Vertical bars sit side by side, horizontal ones stack – so the same
    -- setting reads as right/left in one mode and down/up in the other.
    local fwd, back = "Grow right", "Grow left"
    if orientation ~= "vertical" then fwd, back = "Grow down", "Grow up" end
    getglobal("ShieldBarCheckGrowNormalText"):SetText(fwd)
    getglobal("ShieldBarCheckGrowReverseText"):SetText(back)

    ui.curved:SetChecked(curved)
    ui.flip:SetChecked(curveFlip)

    if curved then ui.flip:Enable() else ui.flip:Disable() end

    ui.size:SetValue(barSize)
    getglobal("ShieldBarSizeSliderText"):SetText("Bar size: " .. barSize)

    refreshing = false
end

local function MakeCheck(name, label, x, y, onToggle)
    local c = CreateFrame("CheckButton", name, cfgFrame, "UICheckButtonTemplate")
    c:SetWidth(24)
    c:SetHeight(24)
    c:SetPoint("TOPLEFT", cfgFrame, "TOPLEFT", x, y)
    getglobal(name .. "Text"):SetText(label)
    c:SetScript("OnClick", function()
        if refreshing then return end
        onToggle(this:GetChecked() and true or false)
        RefreshConfigUI()
    end)
    return c
end

local function MakeButton(name, label, x, y, w, onClick)
    local b = CreateFrame("Button", name, cfgFrame, "UIPanelButtonTemplate")
    b:SetWidth(w)
    b:SetHeight(22)
    b:SetPoint("TOPLEFT", cfgFrame, "TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function MakeHeader(label, x, y)
    local fs = cfgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", cfgFrame, "TOPLEFT", x, y)
    fs:SetTextColor(1.0, 0.82, 0.0)
    fs:SetText(label)
    return fs
end

local function CreateConfigUI()
    if cfgFrame then return end

    cfgFrame = CreateFrame("Frame", "ShieldBarConfig", UIParent)
    cfgFrame:SetWidth(290)
    cfgFrame:SetHeight(398)
    cfgFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    cfgFrame:SetFrameStrata("DIALOG")
    cfgFrame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = {left = 11, right = 12, top = 12, bottom = 11},
    })
    -- UI replacement addons (ShaguPlates, DragonflightUI) retexture the dialog
    -- background to something semi-transparent, which left the world visible
    -- through the window and the labels unreadable. Tint it opaque ourselves.
    cfgFrame:SetBackdropColor(0, 0, 0, 1)
    cfgFrame:SetBackdropBorderColor(1, 1, 1, 1)
    cfgFrame:SetMovable(true)
    cfgFrame:EnableMouse(true)
    cfgFrame:RegisterForDrag("LeftButton")
    cfgFrame:SetScript("OnDragStart", function() cfgFrame:StartMoving() end)
    cfgFrame:SetScript("OnDragStop",  function() cfgFrame:StopMovingOrSizing() end)

    -- OnShow/OnHide rather than ToggleConfigUI, so the example is also torn down
    -- when the window closes by Escape or the X button, which never route
    -- through the toggle.
    cfgFrame:SetScript("OnShow", function()
        previewOn = true
        LayoutBar()
        UpdateBar()
    end)
    cfgFrame:SetScript("OnHide", function()
        previewOn = false
        LayoutBar()
        UpdateBar()
    end)

    cfgFrame:Hide()

    -- Escape closes the window
    table.insert(UISpecialFrames, "ShieldBarConfig")

    local title = cfgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", cfgFrame, "TOP", 0, -16)
    title:SetText("ShieldBar")

    local close = CreateFrame("Button", "ShieldBarConfigClose", cfgFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", cfgFrame, "TOPRIGHT", -6, -6)

    MakeHeader("Visibility", 22, -46)
    ui.combat = MakeCheck("ShieldBarCheckCombat",
        "Only show in combat", 20, -62, SetHiddenMode)
    ui.lock = MakeCheck("ShieldBarCheckLock",
        "Lock position", 20, -88, SetLocked)

    MakeHeader("Layout", 22, -120)
    ui.vertical = MakeCheck("ShieldBarCheckVertical", "Vertical", 20, -136, function(v)
        SetOrientation(v and "vertical" or "horizontal")
    end)
    ui.horizontal = MakeCheck("ShieldBarCheckHorizontal", "Horizontal", 150, -136, function(v)
        SetOrientation(v and "horizontal" or "vertical")
    end)

    -- Where a second shield's bar appears. The labels are rewritten in
    -- RefreshConfigUI, because "right/left" only makes sense while the bars are
    -- vertical – laid out horizontally the same setting means down/up.
    ui.growNormal = MakeCheck("ShieldBarCheckGrowNormal", "Grow right", 20, -162, function(v)
        SetGrowReverse(not v)
    end)
    ui.growReverse = MakeCheck("ShieldBarCheckGrowReverse", "Grow left", 150, -162, function(v)
        SetGrowReverse(v)
    end)

    MakeHeader("Shape", 22, -194)
    ui.curved = MakeCheck("ShieldBarCheckCurved", "Curved bars", 20, -210, SetCurved)
    ui.flip = MakeCheck("ShieldBarCheckFlip", "Flip curve direction", 20, -236, SetCurveFlip)

    ui.size = CreateFrame("Slider", "ShieldBarSizeSlider", cfgFrame, "OptionsSliderTemplate")
    ui.size:SetWidth(230)
    ui.size:SetHeight(16)
    ui.size:SetPoint("TOPLEFT", cfgFrame, "TOPLEFT", 28, -278)
    ui.size:SetMinMaxValues(1, 5)
    ui.size:SetValueStep(1)
    getglobal("ShieldBarSizeSliderLow"):SetText("1")
    getglobal("ShieldBarSizeSliderHigh"):SetText("5")
    ui.size:SetScript("OnValueChanged", function()
        if refreshing then return end
        local v = math.floor(this:GetValue() + 0.5)
        if v ~= barSize then
            SetBarSize(v)
            getglobal("ShieldBarSizeSliderText"):SetText("Bar size: " .. v)
        end
    end)

    MakeButton("ShieldBarBtnDebug", "List buffs", 20, -316, 120, DumpBuffs)
    MakeButton("ShieldBarBtnReset", "Reset all", 150, -316, 120, function()
        ResetAll()
        RefreshConfigUI()
    end)

    -- One line of this ran wider than the 267px of usable space inside the
    -- border and spilled out both sides of the frame. Two lines, width-capped
    -- so it wraps instead of overflowing if a locale makes it longer.
    local hint = cfgFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", cfgFrame, "BOTTOM", 0, 16)
    hint:SetWidth(250)
    hint:SetJustifyH("CENTER")
    hint:SetText("The bars show an example while this window is open.\n" ..
                 "Drag them to move. Right-click a bar to reopen.")
end

function ToggleConfigUI()
    CreateConfigUI()
    if cfgFrame:IsShown() then
        cfgFrame:Hide()
    else
        RefreshConfigUI()
        cfgFrame:Show()
    end
end

-- ============================================================
-- Slash commands  (/shieldbar  or  /sb  opens the GUI)
-- The old text commands still work, for macros.
-- ============================================================
local function HandleCommand(msg)
    msg = string.lower(msg or "")

    if msg == "" then
        ToggleConfigUI()

    elseif msg == "show" then
        SetHiddenMode(false)
        RefreshConfigUI()
    elseif msg == "hide" then
        SetHiddenMode(true)
        RefreshConfigUI()
    elseif msg == "lock" then
        SetLocked(true)
        RefreshConfigUI()
    elseif msg == "unlock" then
        SetLocked(false)
        RefreshConfigUI()
    elseif msg == "vertical" or msg == "horizontal" then
        SetOrientation(msg)
        RefreshConfigUI()
    elseif msg == "curve" then
        SetCurved(true)
        RefreshConfigUI()
    elseif msg == "straight" then
        SetCurved(false)
        RefreshConfigUI()
    elseif msg == "curve rotate" then
        SetCurveFlip(not curveFlip)
        RefreshConfigUI()
    -- right/down and left/up are the same axis seen in the two orientations,
    -- so both spellings are accepted rather than making the user translate.
    elseif msg == "grow right" or msg == "grow down" then
        SetGrowReverse(false)
        RefreshConfigUI()
    elseif msg == "grow left" or msg == "grow up" then
        SetGrowReverse(true)
        RefreshConfigUI()
    elseif msg == "debug" then
        DumpBuffs()
    elseif msg == "reset" then
        ResetAll()
        RefreshConfigUI()
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r All settings reset to default.")
    else
        local _, _, sizeStr = string.find(msg, "^size (%d)$")
        local s = tonumber(sizeStr)
        if s and s >= 1 and s <= 5 then
            SetBarSize(s)
            RefreshConfigUI()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar:|r Unknown command '" .. msg ..
                "'. Type |cffFFFF00/sb|r to open the options window.")
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
evFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
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
        -- target/party matter too: Earth Shield is normally on someone else
        local u = tostring(arg1 or "")
        if u == "player" or u == "target" or string.find(u, "^party") then
            ScanBuffs()
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        ScanBuffs()

    elseif event == "UNIT_COMBAT" then
        if arg1 == "player" and arg2 == "WOUND" then
            local amt = tonumber(arg4) or 0
            if arg3 == "ABSORB" then
                OnAbsorbedDamage(estAvgHit, SCHOOL_BY_ID[tonumber(arg5) or 0])
            elseif amt > 0 then
                UpdateHitAverage(amt)
            end
        end

    elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"
        or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"
    then
        local absorbed = ExtractAbsorbed(arg1)
        if absorbed then OnAbsorbedDamage(absorbed, "physical") end

    elseif event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"
        or event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE"
        or event == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE"
        or event == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF"
    then
        local absorbed = ExtractAbsorbed(arg1)
        if absorbed then OnAbsorbedDamage(absorbed, ExtractSchool(arg1)) end
    end
end)

DEFAULT_CHAT_FRAME:AddMessage("|cffFFAA00ShieldBar|r v2.3 loaded.  |cffFFFF00/sb|r for options.")
