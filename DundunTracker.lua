-- DundunTracker.lua
-- Tracks Shard of Dundun (currency ID 3376) across all characters on account.
-- Caps: 8 weekly maximum (earnedThisWeek), 8 total maximum (quantity held).

local ADDON_NAME  = "DundunTracker"
local CURRENCY_ID = 3376
local WEEKLY_CAP  = 8
local TOTAL_CAP   = 8

-- ============================================================
--  Dundun Quotes
-- ============================================================

local DUNDUN_QUOTES = {
    [1] = '"Revel in this divinely abundant boon!"',
    [2] = '"Hurry! Abundance will soon overwhelm your fragile form!"',
    [3] = '"Magnificent contributions, my acolytes!"',
    [4] = '"Glory be to a bounty so richly abundant!"',
    [5] = '"You shall be benevolently rewarded in abundant kind!"',
    [6] = '"Alas, alack, alacrity! Your abundant limit nears!"',
}
local lastQuoteIndex = 0

local function GetNextQuote()
    local idx = lastQuoteIndex
    while idx == lastQuoteIndex do
        idx = math.random(1, #DUNDUN_QUOTES)
    end
    lastQuoteIndex = idx
    return DUNDUN_QUOTES[idx]
end

-- ============================================================
--  Profession gear data tables
-- ============================================================

local SECONDARY_PROFS = { [184] = true, [356] = true }

local PROF_LABELS = {
    [171] = "Alch",  [164] = "BS",   [333] = "Ench", [202] = "Eng",
    [182] = "Herb",  [773] = "Insc", [755] = "JC",   [165] = "LW",
    [186] = "Mine",  [393] = "Skin", [197] = "Tail", [184] = "Cook",
    [356] = "Fish",
}

local PROF_FULL_NAMES = {
    [171] = "Alchemy",        [164] = "Blacksmithing", [333] = "Enchanting",
    [202] = "Engineering",    [182] = "Herbalism",     [773] = "Inscription",
    [755] = "Jewelcrafting",  [165] = "Leatherworking",[186] = "Mining",
    [393] = "Skinning",       [197] = "Tailoring",     [184] = "Cooking",
    [356] = "Fishing",
}

local EPIC_PROF_GEAR = {
    [186] = { 246534, 259175, 259173 },   -- Mining
    [182] = { 246533, 267060, 244807 },   -- Herbalism
    [393] = { 246535, 244808, 244809 },   -- Skinning
    [333] = { 244177, 246523, 246527 },   -- Enchanting
    [197] = { 259177, 259234, 246514 },   -- Tailoring
    [165] = { 246536, 259232, 244811 },   -- Leatherworking
    [164] = { 246537, 259230, 244813 },   -- Blacksmithing
    [755] = { 259181, 246526, 244814 },   -- Jewelcrafting
    [773] = { 259209, 246524, 246525 },   -- Inscription
    [202] = { 259183, 259171, 244810 },   -- Engineering
    [171] = { 259205, 244812, 267052 },   -- Alchemy
    [184] = { 259207, 267054 },           -- Cooking (2 items only)
    [356] = { 259179 },                   -- Fishing (1 item only)
}

local EPIC_PROF_GEAR_NAMES = {
    [246534] = "Sunforged Pickaxe",
    [259175] = "Heavy-Duty Rock Assister",
    [259173] = "Rock Bonkin' Hardhat",
    [246533] = "Sunforged Sickle",
    [267060] = "Thalassian Herbalist's Cowl",
    [244807] = "Thalassian Herbtender's Cradle",
    [246535] = "Sunforged Skinning Knife",
    [244808] = "Thalassian Wildseeker's Workbag",
    [244809] = "Thalassian Wildseeker's Stridercap",
    [244177] = "Runed Dazzling Thorium Rod",
    [246523] = "Super Elegant Artisan's Enchanting Hat",
    [246527] = "Attuned Thalassian Rune-Prism",
    [259177] = "Self-Sharpening Sin'dorei Snippers",
    [259234] = "Sunforged Needle Set",
    [246514] = "Super Elegant Artisan's Tailoring Robe",
    [246536] = "Sunforged Leatherworker's Knife",
    [259232] = "Sunforged Leatherworker's Toolset",
    [244811] = "Thalassian Hideshaper's Regalia",
    [246537] = "Sunforged Blacksmith's Hammer",
    [259230] = "Sunforged Blacksmith's Toolbox",
    [244813] = "Thalassian Ironbender's Regalia",
    [259181] = "Giga-Gem Grippers",
    [246526] = "Mage-Eye Precision Loupes",
    [244814] = "Thalassian Gemshaper's Grand Cover",
    [259209] = "Gilded Sin'dorei Quill",
    [246524] = "Flawless Text Scrutinizers",
    [246525] = "Thalassian Scribe's Crystalline Lens",
    [259183] = "Turbo-Junker's Multitool v9",
    [259171] = "Head-Mounted Beam Bummer",
    [244810] = "Thalassian Scrapmaster's Gauntlets",
    [259205] = "Gilded Alchemist's Mixing Rod",
    [244812] = "Thalassian Alchemist's Mixcap",
    [267052] = "Thalassian Alchemy Coveralls",
    [259207] = "Gilded Sin'dorei Rolling Pin",
    [267054] = "Thalassian Chef's Chapeau",
    [259179] = "Sin'dorei Reeler's Rod",
}

-- ============================================================
--  Saved Variables  (per-account, shared across all chars)
-- ============================================================
-- DundunTrackerDB["CharName-Realm"] = {
--     name               = "CharName",
--     realm              = "Realm",
--     class              = "WARRIOR",
--     quantity           = 3,
--     weeklyEarned       = 5,
--     weeklyCap          = 8,
--     totalCap           = 8,
--     lastSaved          = <unix timestamp>,
--     professions        = { [skillLine] = true, ... },
--     profGear           = { [skillLine] = { itemID, ... } },
--     fusedVitality      = N,
--     unalloyedAbundance = N,
-- }
-- DundunTrackerDB._lastResetTime = <unix timestamp>

-- ============================================================
--  Helpers
-- ============================================================

local function GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

local function ClassColor(classToken)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if c then
        return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    return "|cffffffff"
end

local function FractionColor(val, cap)
    if cap == 0 then return 0.6, 0.6, 0.6 end
    local f = math.min(val / cap, 1)
    if     f >= 1   then return 0.2, 1.0, 0.3
    elseif f >= 0.5 then return 1.0, 0.85, 0.1
    elseif f >  0   then return 1.0, 0.45, 0.1
    else                 return 0.6, 0.6, 0.6
    end
end

-- ============================================================
--  Data write
-- ============================================================

local function ScanProfessionGear()
    -- Build item -> skillLine lookup
    local itemToSkillLine = {}
    for skillLine, items in pairs(EPIC_PROF_GEAR) do
        for _, itemID in ipairs(items) do
            itemToSkillLine[itemID] = skillLine
        end
    end

    -- Determine which Midnight-tier professions this character has.
    -- GetProfessions() returns up to 5 positional values (primary, primary,
    -- archaeology, fishing, cooking); any can be nil. We unpack all five
    -- explicitly to avoid ipairs/table.pack nil-hole issues.
    -- skillLevel is the current expansion's tier skill; 0 means the character
    -- hasn't started the Midnight tier for that profession yet.
    local charProfs = {}
    local function tryProf(profIndex)
        if not profIndex then return end
        local _, _, skillLevel, _, _, _, skillLine = GetProfessionInfo(profIndex)
        if skillLine and EPIC_PROF_GEAR[skillLine] and skillLevel and skillLevel > 0 then
            charProfs[skillLine] = true
        end
    end
    local p1, p2, p3, p4, p5 = GetProfessions()
    tryProf(p1); tryProf(p2); tryProf(p3); tryProf(p4); tryProf(p5)

    -- Check profession equipment slots (Dragonflight+: tool and accessory
    -- slots live in the profession window UI, NOT in the standard character
    -- sheet slots 1-19). IsEquippedItem(itemID) scans every equipped slot
    -- on the player, including the new profession equipment slots, so we
    -- iterate the items we care about and ask WoW directly.
    local foundSets = {}
    for sl in pairs(charProfs) do
        for _, itemID in ipairs(EPIC_PROF_GEAR[sl]) do
            if IsEquippedItem(itemID) then
                if not foundSets[sl] then foundSets[sl] = {} end
                foundSets[sl][itemID] = true
            end
        end
    end

    -- Scan bags 0-5 (5 = reagent bag, added in Dragonflight).
    -- Guard numSlots against nil: GetContainerNumSlots returns nil for
    -- bag slots that don't exist, and "for i=1,nil" is a Lua error.
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, (numSlots or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and itemToSkillLine[info.itemID] then
                local sl = itemToSkillLine[info.itemID]
                if charProfs[sl] then
                    if not foundSets[sl] then foundSets[sl] = {} end
                    foundSets[sl][info.itemID] = true
                end
            end
        end
    end

    -- Convert sets to arrays
    local profGear = {}
    for sl, itemSet in pairs(foundSets) do
        profGear[sl] = {}
        for itemID in pairs(itemSet) do
            table.insert(profGear[sl], itemID)
        end
    end

    return charProfs, profGear
end

local function SaveCurrentChar()
    if not DundunTrackerDB then return end
    local info = C_CurrencyInfo.GetCurrencyInfo(CURRENCY_ID)
    if not info then return end

    local weeklyCap = (info.maxWeeklyQuantity and info.maxWeeklyQuantity > 0)
                      and info.maxWeeklyQuantity or WEEKLY_CAP
    local totalCap  = (info.maxQuantity and info.maxQuantity > 0)
                      and info.maxQuantity or TOTAL_CAP

    local key             = GetCharKey()
    local newWeeklyEarned = info.quantityEarnedThisWeek or 0

    -- If weekly earned dropped from last save, a reset occurred — record it.
    local prev = DundunTrackerDB[key]
    if prev and (prev.weeklyEarned or 0) > newWeeklyEarned then
        DundunTrackerDB._lastResetTime = GetServerTime()
    end

    -- Scan profession gear.
    -- At PLAYER_LEAVING_WORLD / PLAYER_LOGOUT, WoW tears down skill data
    -- before firing the event, so GetProfessionInfo returns skillLevel = 0
    -- and our Midnight filter rejects everything — charProfs comes back
    -- empty. Guard against this: if the new scan found nothing but the
    -- previous DB entry had profession data, keep the old snapshot.
    local charProfs, profGear = ScanProfessionGear()
    if next(charProfs) == nil and prev and prev.professions
            and next(prev.professions) ~= nil then
        charProfs = prev.professions
        profGear  = prev.profGear or {}
    end

    -- Scan bags for Fused Vitality (item ID 245345).
    -- The backpack (bag 0) always has slots in a normal game state; if it
    -- reports 0 or nil slots, WoW is tearing down container data and the
    -- scan result is unreliable. In that case preserve the previous value
    -- so a legitimate spend-to-zero is not confused with a failed scan.
    local bagScanValid = (C_Container.GetContainerNumSlots(0) or 0) > 0
    local fusedVitality = 0
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, (numSlots or 0) do
            local slotInfo = C_Container.GetContainerItemInfo(bag, slot)
            if slotInfo and slotInfo.itemID == 245345 then
                fusedVitality = fusedVitality + (slotInfo.stackCount or 1)
            end
        end
    end
    if not bagScanValid and prev then
        fusedVitality = prev.fusedVitality or 0
    end

    -- Unalloyed Abundance currency (ID 3377)
    local uaInfo = C_CurrencyInfo.GetCurrencyInfo(3377)
    local unalloyedAbundance = uaInfo and uaInfo.quantity or 0

    DundunTrackerDB[key] = {
        name               = UnitName("player"),
        realm              = GetRealmName(),
        class              = select(2, UnitClass("player")),
        quantity           = info.quantity or 0,
        weeklyEarned       = newWeeklyEarned,
        weeklyCap          = weeklyCap,
        totalCap           = totalCap,
        lastSaved          = GetServerTime(),
        professions        = charProfs,
        profGear           = profGear,
        fusedVitality      = fusedVitality,
        unalloyedAbundance = unalloyedAbundance,
    }
end

-- ============================================================
--  Settings helpers
-- ============================================================

local function GetSettings()
    if not DundunTrackerDB then return { listMode = "none", list = {} } end
    if not DundunTrackerDB._settings then
        DundunTrackerDB._settings = { listMode = "none", list = {} }
    end
    return DundunTrackerDB._settings
end

local function IsCharVisible(key)
    local s = GetSettings()
    if s.listMode == "whitelist" then
        return s.list[key] == true
    elseif s.listMode == "blacklist" then
        return not s.list[key]
    end
    return true
end

-- ============================================================
--  Layout constants
-- ============================================================

local COL_NAME       = 210
local COL_WEEKLY     = 115
local COL_TOTAL      = 115
local COL_PRIMGEAR   = 80
local COL_SECGEAR    = 80
local COL_FUSED      = 80
local COL_UNALLOYED  = 100
local ROW_HEIGHT     = 22
local HEADER_H       = 22
local TITLE_BAR_H    = 26
local QUOTE_H        = 24
local FOOTER_H       = 60
local MIN_WIN_H      = 160
local BASE_WIN_W     = COL_NAME + COL_WEEKLY + COL_TOTAL + 32

local function GetWindowWidth()
    local s = (DundunTrackerDB and DundunTrackerDB._settings) or {}
    local w = BASE_WIN_W
    if s.expandPrimaryGear   then w = w + COL_PRIMGEAR   end
    if s.expandSecondaryGear then w = w + COL_SECGEAR    end
    if s.expandFusedVitality then w = w + COL_FUSED      end
    if s.expandUnalloyed     then w = w + COL_UNALLOYED  end
    return w
end

local function GetExtraColumnOffsets()
    local s = (DundunTrackerDB and DundunTrackerDB._settings) or {}
    local x = COL_NAME + COL_WEEKLY + COL_TOTAL
    local offsets = {}
    if s.expandPrimaryGear   then offsets.primary   = x; x = x + COL_PRIMGEAR   end
    if s.expandSecondaryGear then offsets.secondary = x; x = x + COL_SECGEAR    end
    if s.expandFusedVitality then offsets.fused     = x; x = x + COL_FUSED      end
    if s.expandUnalloyed     then offsets.unalloyed = x; x = x + COL_UNALLOYED  end
    return offsets
end

-- ============================================================
--  Gear fraction helper
-- ============================================================

local function GetGearFraction(d, isPrimary)
    if not d.professions or not d.profGear then return nil end
    local owned = 0
    local total = 0
    for skillLine in pairs(d.professions) do
        local isSecondary = SECONDARY_PROFS[skillLine]
        if (isPrimary and not isSecondary) or (not isPrimary and isSecondary) then
            local items = EPIC_PROF_GEAR[skillLine] or {}
            total = total + #items
            local found = d.profGear[skillLine] or {}
            owned = owned + #found
        end
    end
    if total == 0 then return nil end
    return owned, total
end

-- ============================================================
--  Window
-- ============================================================

local window
local ToggleSettingsWindow  -- forward declaration; defined after CreateWindow

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.05 or 0)

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
    nameText:SetWidth(COL_NAME - 6)
    nameText:SetWordWrap(false)
    nameText:SetJustifyH("LEFT")

    local weeklyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    weeklyText:SetPoint("LEFT", row, "LEFT", COL_NAME, 0)
    weeklyText:SetWidth(COL_WEEKLY)
    weeklyText:SetJustifyH("CENTER")

    local totalText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalText:SetPoint("LEFT", row, "LEFT", COL_NAME + COL_WEEKLY, 0)
    totalText:SetWidth(COL_TOTAL)
    totalText:SetJustifyH("CENTER")

    -- Extra columns — repositioned dynamically in RefreshWindow
    local primGearText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    primGearText:SetWidth(COL_PRIMGEAR)
    primGearText:SetJustifyH("CENTER")
    primGearText:Hide()

    local secGearText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secGearText:SetWidth(COL_SECGEAR)
    secGearText:SetJustifyH("CENTER")
    secGearText:Hide()

    local fusedText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fusedText:SetWidth(COL_FUSED)
    fusedText:SetJustifyH("CENTER")
    fusedText:Hide()

    local unalloyedText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    unalloyedText:SetWidth(COL_UNALLOYED)
    unalloyedText:SetJustifyH("CENTER")
    unalloyedText:Hide()

    -- Invisible hit frames for gear tooltips
    local primGearHit = CreateFrame("Frame", nil, row)
    primGearHit:SetSize(COL_PRIMGEAR, ROW_HEIGHT)
    primGearHit:EnableMouse(true)
    primGearHit:Hide()
    primGearHit:SetScript("OnEnter", function(self)
        local d = self.charData
        if not d or not d.professions or not d.profGear then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        for skillLine in pairs(d.professions) do
            if not SECONDARY_PROFS[skillLine] then
                GameTooltip:AddLine(PROF_FULL_NAMES[skillLine] or tostring(skillLine), 1, 0.82, 0)
                local items = EPIC_PROF_GEAR[skillLine] or {}
                local gearFound = d.profGear[skillLine] or {}
                local foundSet = {}
                for _, id in ipairs(gearFound) do foundSet[id] = true end
                for _, itemID in ipairs(items) do
                    local name = EPIC_PROF_GEAR_NAMES[itemID] or ("Item " .. itemID)
                    if foundSet[itemID] then
                        GameTooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t " .. name, 0.2, 1.0, 0.3)
                    else
                        GameTooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t " .. name, 1.0, 0.3, 0.3)
                    end
                end
            end
        end
        GameTooltip:Show()
    end)
    primGearHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local secGearHit = CreateFrame("Frame", nil, row)
    secGearHit:SetSize(COL_SECGEAR, ROW_HEIGHT)
    secGearHit:EnableMouse(true)
    secGearHit:Hide()
    secGearHit:SetScript("OnEnter", function(self)
        local d = self.charData
        if not d or not d.professions or not d.profGear then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        for skillLine in pairs(d.professions) do
            if SECONDARY_PROFS[skillLine] then
                GameTooltip:AddLine(PROF_FULL_NAMES[skillLine] or tostring(skillLine), 1, 0.82, 0)
                local items = EPIC_PROF_GEAR[skillLine] or {}
                local gearFound = d.profGear[skillLine] or {}
                local foundSet = {}
                for _, id in ipairs(gearFound) do foundSet[id] = true end
                for _, itemID in ipairs(items) do
                    local name = EPIC_PROF_GEAR_NAMES[itemID] or ("Item " .. itemID)
                    if foundSet[itemID] then
                        GameTooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t " .. name, 0.2, 1.0, 0.3)
                    else
                        GameTooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t " .. name, 1.0, 0.3, 0.3)
                    end
                end
            end
        end
        GameTooltip:Show()
    end)
    secGearHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.nameText      = nameText
    row.weeklyText    = weeklyText
    row.totalText     = totalText
    row.primGearText  = primGearText
    row.secGearText   = secGearText
    row.fusedText     = fusedText
    row.unalloyedText = unalloyedText
    row.primGearHit   = primGearHit
    row.secGearHit    = secGearHit
    return row
end

local function CreateWindow()
    local f = CreateFrame("Frame", "DundunTrackerWindow", UIParent, "BackdropTemplate")
    f:SetSize(GetWindowWidth(), 280)
    f:SetPoint("CENTER")
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetResizable(true)
    f:SetResizeBounds(BASE_WIN_W, MIN_WIN_H)

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    f:SetBackdropBorderColor(0.4, 0.35, 0.55, 1)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",   8, -6)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -8, -6)
    titleBar:SetHeight(TITLE_BAR_H)
    titleBar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    titleBar:SetBackdropColor(0.18, 0.10, 0.30, 0.95)
    titleBar:SetBackdropBorderColor(0.55, 0.3, 0.75, 1)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("CENTER")
    titleText:SetText("|cffcc88ffShard of Dundun|r")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 4, 4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Settings button
    local gearBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    gearBtn:SetSize(58, 20)
    gearBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 2)
    gearBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 6,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    gearBtn:SetBackdropColor(0.12, 0.06, 0.20, 0.85)
    gearBtn:SetBackdropBorderColor(0.45, 0.25, 0.65, 0.8)
    local gearLabel = gearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gearLabel:SetPoint("CENTER")
    gearLabel:SetText("|cffaa88ccSettings|r")
    gearBtn:SetScript("OnClick", function() ToggleSettingsWindow() end)

    -- Quote bar
    local TOP_OFFSET = 6 + TITLE_BAR_H + 4
    local quoteBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    quoteBar:SetPoint("TOPLEFT",  f, "TOPLEFT",   8, -TOP_OFFSET)
    quoteBar:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -8, -TOP_OFFSET)
    quoteBar:SetHeight(QUOTE_H)
    quoteBar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    quoteBar:SetBackdropColor(0.08, 0.04, 0.14, 0.85)
    quoteBar:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.7)

    local quoteText = quoteBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    quoteText:SetPoint("LEFT",  quoteBar, "LEFT",   6, 0)
    quoteText:SetPoint("RIGHT", quoteBar, "RIGHT", -6, 0)
    quoteText:SetJustifyH("CENTER")
    quoteText:SetTextColor(0.85, 0.65, 1.0)
    f.quoteText = quoteText

    local quoteDivider = f:CreateTexture(nil, "ARTWORK")
    quoteDivider:SetColorTexture(0.4, 0.25, 0.6, 0.45)
    quoteDivider:SetHeight(1)
    quoteDivider:SetPoint("TOPLEFT",  quoteBar, "BOTTOMLEFT",  0, 0)
    quoteDivider:SetPoint("TOPRIGHT", quoteBar, "BOTTOMRIGHT", 0, 0)

    -- Column headers
    local HEADER_TOP = TOP_OFFSET + QUOTE_H + 3
    local headerRow = CreateFrame("Frame", nil, f)
    headerRow:SetPoint("TOPLEFT",  f, "TOPLEFT",  8,  -HEADER_TOP)
    headerRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -HEADER_TOP)
    headerRow:SetHeight(HEADER_H)
    f.headerRow = headerRow

    local function FixedHeaderCell(text, x, w)
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", headerRow, "TOPLEFT", x, 0)
        fs:SetSize(w, HEADER_H)
        fs:SetJustifyH("CENTER")
        fs:SetText(text)
        fs:SetTextColor(0.9, 0.8, 0.5)
    end
    FixedHeaderCell("Character",       0,                     COL_NAME)
    FixedHeaderCell("Weekly (picked)", COL_NAME,              COL_WEEKLY)
    FixedHeaderCell("Total (held)",    COL_NAME + COL_WEEKLY, COL_TOTAL)

    local function ExtraHeaderCell(text, w)
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetSize(w, HEADER_H)
        fs:SetJustifyH("CENTER")
        fs:SetText(text)
        fs:SetTextColor(0.9, 0.8, 0.5)
        fs:Hide()
        return fs
    end
    f.hdrPrimGear  = ExtraHeaderCell("Prim Gear",  COL_PRIMGEAR)
    f.hdrSecGear   = ExtraHeaderCell("Sec Gear",   COL_SECGEAR)
    f.hdrFused     = ExtraHeaderCell("Fused Vit",  COL_FUSED)
    f.hdrUnalloyed = ExtraHeaderCell("Unalloyed",  COL_UNALLOYED)

    local headerDivider = f:CreateTexture(nil, "ARTWORK")
    headerDivider:SetColorTexture(0.5, 0.4, 0.7, 0.5)
    headerDivider:SetHeight(1)
    headerDivider:SetPoint("TOPLEFT",  headerRow, "BOTTOMLEFT",  0, 0)
    headerDivider:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, 0)

    -- Scroll frame
    local SCROLL_TOP = HEADER_TOP + HEADER_H + 2
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",      8,   -SCROLL_TOP)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28,   FOOTER_H)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(GetWindowWidth() - 36, 1)
    content.rows = {}
    scrollFrame:SetScrollChild(content)

    f.scrollFrame = scrollFrame
    f.content     = content

    -- Footer divider
    local footerDivider = f:CreateTexture(nil, "ARTWORK")
    footerDivider:SetColorTexture(0.4, 0.25, 0.6, 0.35)
    footerDivider:SetHeight(1)
    footerDivider:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",   8, FOOTER_H - 1)
    footerDivider:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, FOOTER_H - 1)

    -- Footer checkboxes — Row 1: Primary Gear | Secondary Gear
    local function MakeCheckbox(labelText, xOff, yOff, settingKey)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", xOff, yOff)
        cb:EnableKeyboard(false)  -- prevent checkbox from swallowing keyboard input
        cb.text:SetText(labelText)
        cb.text:SetTextColor(0.75, 0.70, 0.85)
        -- Initialise from saved settings (CreateWindow is always called after ADDON_LOADED)
        cb:SetChecked(GetSettings()[settingKey] and true or false)
        cb:SetScript("OnClick", function(self)
            GetSettings()[settingKey] = self:GetChecked() and true or false
            AutoSizeWindow()
            DundunTracker_RefreshWindow()
        end)
        return cb
    end

    f.cb_primGear  = MakeCheckbox("Primary Gear",        8,   36, "expandPrimaryGear")
    f.cb_secGear   = MakeCheckbox("Secondary Gear",      150, 36, "expandSecondaryGear")
    f.cb_fused     = MakeCheckbox("Fused Vitality",      8,   14, "expandFusedVitality")
    f.cb_unalloyed = MakeCheckbox("Unalloyed Abundance", 150, 14, "expandUnalloyed")

    -- Resize grip dots (bottom-right corner)
    local function GripDot(xOff, yOff)
        local d = f:CreateTexture(nil, "OVERLAY")
        d:SetSize(2, 2)
        d:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", xOff, yOff)
        d:SetColorTexture(0.7, 0.5, 0.9, 0.8)
    end
    GripDot(-11, 3); GripDot(-7, 3);  GripDot(-3, 3)
                     GripDot(-7, 7);  GripDot(-3, 7)
                                      GripDot(-3, 11)

    local gripFrame = CreateFrame("Frame", nil, f)
    gripFrame:SetSize(18, 18)
    gripFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    gripFrame:EnableMouse(true)
    gripFrame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    gripFrame:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
    end)

    -- ESC closes the window
    tinsert(UISpecialFrames, "DundunTrackerWindow")

    return f
end

-- ============================================================
--  Populate rows
-- ============================================================

function DundunTracker_RefreshWindow()
    if not window or not window:IsShown() then return end
    if not DundunTrackerDB then return end

    local currentKey = GetCharKey()

    local nextReset = GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()
    local weekStart = nextReset - (7 * 24 * 3600)

    local sorted = {}
    for k, v in pairs(DundunTrackerDB) do
        if type(v) == "table" and k:sub(1,1) ~= "_" and IsCharVisible(k) then
            table.insert(sorted, { key = k, data = v })
        end
    end
    table.sort(sorted, function(a, b)
        if a.key == currentKey then return true  end
        if b.key == currentKey then return false end
        return (a.data.name or "") < (b.data.name or "")
    end)

    local content = window.content
    local offsets = GetExtraColumnOffsets()

    -- Update extra column headers
    local function RefreshHeader(hdr, offset)
        if offset then
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", window.headerRow, "TOPLEFT", offset, 0)
            hdr:Show()
        else
            hdr:Hide()
        end
    end
    RefreshHeader(window.hdrPrimGear,  offsets.primary)
    RefreshHeader(window.hdrSecGear,   offsets.secondary)
    RefreshHeader(window.hdrFused,     offsets.fused)
    RefreshHeader(window.hdrUnalloyed, offsets.unalloyed)

    for i = #sorted + 1, #content.rows do
        content.rows[i]:Hide()
    end

    for i, entry in ipairs(sorted) do
        if not content.rows[i] then
            content.rows[i] = CreateRow(content, i)
        end
        local row = content.rows[i]
        row:Show()

        local d = entry.data
        local isCurrent = (entry.key == currentKey)
        local prefix = isCurrent and "|cffFFFFFF>|r " or "  "
        local nameLabel = (d.name or "?") .. (d.realm and ("-" .. d.realm) or "")
        row.nameText:SetText(prefix .. ClassColor(d.class or "") .. nameLabel .. "|r")

        local stale = not isCurrent
                      and d.lastSaved
                      and d.lastSaved < weekStart
        local we = stale and 0 or (d.weeklyEarned or 0)
        local wc = d.weeklyCap or WEEKLY_CAP
        local wr, wg, wb = FractionColor(we, wc)
        row.weeklyText:SetText(string.format("|cff%02x%02x%02x%d / %d|r",
            wr*255, wg*255, wb*255, we, wc))

        local qty = d.quantity or 0
        local tc  = d.totalCap or TOTAL_CAP
        local tr, tg, tb = FractionColor(qty, tc)
        row.totalText:SetText(string.format("|cff%02x%02x%02x%d / %d|r",
            tr*255, tg*255, tb*255, qty, tc))

        -- Primary Gear column
        if offsets.primary then
            row.primGearText:ClearAllPoints()
            row.primGearText:SetPoint("LEFT", row, "LEFT", offsets.primary, 0)
            row.primGearHit:ClearAllPoints()
            row.primGearHit:SetPoint("TOPLEFT", row, "TOPLEFT", offsets.primary, 0)
            row.primGearHit.charData = d
            local owned, total = GetGearFraction(d, true)
            if owned then
                local r, g, b = FractionColor(owned, total)
                row.primGearText:SetText(string.format("|cff%02x%02x%02x%d/%d|r",
                    r*255, g*255, b*255, owned, total))
            else
                row.primGearText:SetText("|cff999999--|r")
            end
            row.primGearText:Show()
            row.primGearHit:Show()
        else
            row.primGearText:Hide()
            row.primGearHit:Hide()
        end

        -- Secondary Gear column
        if offsets.secondary then
            row.secGearText:ClearAllPoints()
            row.secGearText:SetPoint("LEFT", row, "LEFT", offsets.secondary, 0)
            row.secGearHit:ClearAllPoints()
            row.secGearHit:SetPoint("TOPLEFT", row, "TOPLEFT", offsets.secondary, 0)
            row.secGearHit.charData = d
            local owned, total = GetGearFraction(d, false)
            if owned then
                local r, g, b = FractionColor(owned, total)
                row.secGearText:SetText(string.format("|cff%02x%02x%02x%d/%d|r",
                    r*255, g*255, b*255, owned, total))
            else
                row.secGearText:SetText("|cff999999--|r")
            end
            row.secGearText:Show()
            row.secGearHit:Show()
        else
            row.secGearText:Hide()
            row.secGearHit:Hide()
        end

        -- Fused Vitality column
        if offsets.fused then
            row.fusedText:ClearAllPoints()
            row.fusedText:SetPoint("LEFT", row, "LEFT", offsets.fused, 0)
            if d.fusedVitality ~= nil then
                row.fusedText:SetText(tostring(d.fusedVitality))
            else
                row.fusedText:SetText("|cff999999--|r")
            end
            row.fusedText:Show()
        else
            row.fusedText:Hide()
        end

        -- Unalloyed Abundance column
        if offsets.unalloyed then
            row.unalloyedText:ClearAllPoints()
            row.unalloyedText:SetPoint("LEFT", row, "LEFT", offsets.unalloyed, 0)
            if d.unalloyedAbundance ~= nil then
                row.unalloyedText:SetText(tostring(d.unalloyedAbundance))
            else
                row.unalloyedText:SetText("|cff999999--|r")
            end
            row.unalloyedText:Show()
        else
            row.unalloyedText:Hide()
        end
    end

    content:SetHeight(math.max(#sorted * ROW_HEIGHT, ROW_HEIGHT))
end

-- ============================================================
--  Settings window
-- ============================================================

local settingsWindow

local function RefreshSettingsWindow()
    if not settingsWindow then return end
    local s = GetSettings()

    for _, btn in ipairs(settingsWindow.modeBtns) do
        local active = (btn.mode == s.listMode)
        if active then
            btn:SetBackdropColor(0.25, 0.12, 0.40, 0.95)
            btn:SetBackdropBorderColor(0.7, 0.4, 1.0, 1)
            btn.label:SetTextColor(0.95, 0.80, 1.0)
        else
            btn:SetBackdropColor(0.08, 0.04, 0.14, 0.85)
            btn:SetBackdropBorderColor(0.35, 0.20, 0.50, 0.7)
            btn.label:SetTextColor(0.55, 0.50, 0.65)
        end
    end

    local hasMode = s.listMode ~= "none"
    settingsWindow.noModeLabel:SetShown(not hasMode)
    settingsWindow.listScroll:SetShown(hasMode)
    if not hasMode then return end

    local listContent = settingsWindow.listContent
    for _, cb in ipairs(listContent.checkboxes) do cb:Hide() end

    local sorted = {}
    if DundunTrackerDB then
        for k, v in pairs(DundunTrackerDB) do
            if type(v) == "table" and k:sub(1,1) ~= "_" then
                table.insert(sorted, { key = k, data = v })
            end
        end
    end
    table.sort(sorted, function(a, b)
        return (a.data.name or "") < (b.data.name or "")
    end)

    local CBH = 22
    for i, entry in ipairs(sorted) do
        local cb = listContent.checkboxes[i]
        if not cb then
            cb = CreateFrame("CheckButton", nil, listContent, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", listContent, "TOPLEFT", 4, -(i - 1) * CBH - 2)
            local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            cb.lbl = lbl
            cb:SetScript("OnClick", function(self)
                local settings = GetSettings()
                if self:GetChecked() then
                    settings.list[self.charKey] = true
                else
                    settings.list[self.charKey] = nil
                end
                DundunTracker_RefreshWindow()
            end)
            listContent.checkboxes[i] = cb
        end
        local d = entry.data
        cb.charKey = entry.key
        local charLabel = (d.name or "?") .. (d.realm and ("-" .. d.realm) or "")
        cb.lbl:SetText(ClassColor(d.class or "") .. charLabel .. "|r")
        cb:SetChecked(s.list[entry.key] == true)
        cb:Show()
    end
    listContent:SetHeight(math.max(#sorted * CBH + 4, CBH))
end

local function CreateSettingsWindow()
    local SW = 300
    local f = CreateFrame("Frame", "DundunTrackerSettingsWindow", UIParent, "BackdropTemplate")
    f:SetSize(SW, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    f:SetBackdropBorderColor(0.4, 0.35, 0.55, 1)

    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",   8, -6)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -8, -6)
    titleBar:SetHeight(TITLE_BAR_H)
    titleBar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    titleBar:SetBackdropColor(0.18, 0.10, 0.30, 0.95)
    titleBar:SetBackdropBorderColor(0.55, 0.30, 0.75, 1)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("CENTER")
    titleText:SetText("|cffcc88ffDunDun Tracker - Settings|r")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 4, 4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local INFO_TOP = 6 + TITLE_BAR_H + 10
    local infoText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT",  f, "TOPLEFT",  14, -INFO_TOP)
    infoText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -INFO_TOP)
    infoText:SetJustifyH("LEFT")
    infoText:SetTextColor(0.65, 0.60, 0.75)
    infoText:SetText(
        "|cffcc88ffWhitelist|r: only listed characters appear in the tracker.\n" ..
        "|cffcc88ffBlacklist|r: listed characters are hidden from the tracker."
    )

    local MODE_TOP = INFO_TOP + 72
    local modeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -MODE_TOP)
    modeLabel:SetText("List Mode:")
    modeLabel:SetTextColor(0.80, 0.75, 0.90)

    local modeRow = CreateFrame("Frame", nil, f)
    modeRow:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(MODE_TOP + 18))
    modeRow:SetSize(SW - 28, 22)

    local modeBtns = {}
    local modes = {
        { "None",      "none"      },
        { "Whitelist", "whitelist" },
        { "Blacklist", "blacklist" },
    }
    local btnW = math.floor((SW - 28) / 3)
    for i, m in ipairs(modes) do
        local btn = CreateFrame("Button", nil, modeRow, "BackdropTemplate")
        btn:SetSize(btnW - 2, 22)
        btn:SetPoint("TOPLEFT", modeRow, "TOPLEFT", (i - 1) * btnW, 0)
        btn:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText(m[1])
        btn.mode  = m[2]
        btn.label = lbl
        btn:SetScript("OnClick", function()
            GetSettings().listMode = m[2]
            RefreshSettingsWindow()
            DundunTracker_RefreshWindow()
        end)
        modeBtns[i] = btn
    end
    f.modeBtns = modeBtns

    local DIVIDER_TOP = MODE_TOP + 18 + 22 + 8
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.4, 0.25, 0.6, 0.45)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  f, "TOPLEFT",   8, -DIVIDER_TOP)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -8, -DIVIDER_TOP)

    local LIST_TOP = DIVIDER_TOP + 8
    local noModeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noModeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -LIST_TOP)
    noModeLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -LIST_TOP)
    noModeLabel:SetJustifyH("LEFT")
    noModeLabel:SetTextColor(0.40, 0.38, 0.48)
    noModeLabel:SetText("Select Whitelist or Blacklist above to manage the character list.")
    f.noModeLabel = noModeLabel

    local listScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT",     f, "TOPLEFT",      10, -LIST_TOP)
    listScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  -26, 10)

    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(SW - 36, 1)
    listContent.checkboxes = {}
    listScroll:SetScrollChild(listContent)

    f.listScroll   = listScroll
    f.listContent  = listContent

    tinsert(UISpecialFrames, "DundunTrackerSettingsWindow")
    f:Hide()
    return f
end

ToggleSettingsWindow = function()
    if not settingsWindow then
        settingsWindow = CreateSettingsWindow()
    end
    if settingsWindow:IsShown() then
        settingsWindow:Hide()
    else
        RefreshSettingsWindow()
        settingsWindow:Show()
    end
end

-- ============================================================
--  Show / Toggle
-- ============================================================

function AutoSizeWindow()
    if not DundunTrackerDB or not window then return end
    local count = 0
    for k, v in pairs(DundunTrackerDB) do
        if type(v) == "table" and k:sub(1,1) ~= "_" and IsCharVisible(k) then count = count + 1 end
    end
    if count == 0 then return end
    local scrollTop = (6 + TITLE_BAR_H + 4) + QUOTE_H + 3 + HEADER_H + 2
    local idealH = scrollTop + FOOTER_H + (count * ROW_HEIGHT) + 8
    local w = GetWindowWidth()
    window:SetSize(w, math.max(idealH, MIN_WIN_H))
    window.content:SetSize(w - 36, 1)
end

local function ShowWindow()
    if not window then
        window = CreateWindow()
    end
    AutoSizeWindow()
    window.quoteText:SetText(GetNextQuote())
    SaveCurrentChar()
    window:Show()
    -- Defer one frame so WoW's layout pass completes before we build rows.
    C_Timer.After(0, DundunTracker_RefreshWindow)
end

local function ToggleWindow()
    if window and window:IsShown() then
        window:Hide()
    else
        ShowWindow()
    end
end

-- ============================================================
--  Minimap button (LibDBIcon)
-- ============================================================

local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("DundunTracker", {
    type  = "data source",
    icon  = "Interface\\AddOns\\DundunTracker\\Media\\dundun-small",
    label = "DunDun Tracker",
    OnClick = function(_, btn)
        if btn == "RightButton" then
            ToggleSettingsWindow()
        else
            ToggleWindow()
        end
    end,
    OnTooltipShow = function(tt)
        tt:AddLine("|cffcc88ffDunDun Tracker|r")
        tt:AddLine("|cffaaaaaaLeft-click|r to toggle window")
        tt:AddLine("|cffaaaaaaRight-click|r to toggle settings")
    end,
})

local icon = LibStub("LibDBIcon-1.0")

local function RegisterMinimapButton()
    DundunTrackerDB._minimapIcon = DundunTrackerDB._minimapIcon or { hide = false }
    icon:Register("DundunTracker", ldb, DundunTrackerDB._minimapIcon)
end

-- ============================================================
--  Events
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        DundunTrackerDB = DundunTrackerDB or {}

        if not DundunTrackerDB._minimapIcon then
            DundunTrackerDB._minimapIcon = { hide = false }
        end
        if not DundunTrackerDB._settings then
            DundunTrackerDB._settings = { listMode = "none", list = {} }
        end
        local s = DundunTrackerDB._settings
        if s.expandPrimaryGear   == nil then s.expandPrimaryGear   = false end
        if s.expandSecondaryGear == nil then s.expandSecondaryGear = false end
        if s.expandFusedVitality == nil then s.expandFusedVitality = false end
        if s.expandUnalloyed     == nil then s.expandUnalloyed     = false end

        RegisterMinimapButton()

        local count = 0
        for k, v in pairs(DundunTrackerDB) do
            if type(v) == "table" and k:sub(1,1) ~= "_" then count = count + 1 end
        end
        if count > 0 then
            print(string.format(
                "|cffcc88ffDunDun Tracker|r loaded — found |cffFFFF00%d|r saved character(s) from disk.",
                count))
        else
            print("|cffcc88ffDunDun Tracker|r loaded — no saved data found yet. Type |cffFFFF00/dundun|r to open.")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        SaveCurrentChar()
        C_Timer.After(2, function()
            SaveCurrentChar()
            DundunTracker_RefreshWindow()
        end)
        if not DundunTrackerTicker then
            DundunTrackerTicker = C_Timer.NewTicker(30, SaveCurrentChar)
        end

    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        SaveCurrentChar()
        DundunTracker_RefreshWindow()

    elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
        SaveCurrentChar()
    end
end)

-- ============================================================
--  Slash commands
-- ============================================================

SLASH_DUNDUN1 = "/dundun"
SLASH_DUNDUN2 = "/ddt"
SlashCmdList["DUNDUN"] = function(msg)
    local cmd = strtrim(msg):lower()

    if cmd == "debug" then
        local info = C_CurrencyInfo.GetCurrencyInfo(CURRENCY_ID)
        print("|cffcc88ffDunDun Tracker:|r Raw CurrencyInfo fields:")
        if info then
            for k, v in pairs(info) do
                print(string.format("  |cffFFFF00%s|r = %s", tostring(k), tostring(v)))
            end
        else
            print("  nil — currency not found for ID " .. CURRENCY_ID)
        end
        local dbgNextReset = GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()
        local dbgWeekStart = dbgNextReset - (7 * 24 * 3600)
        local dbgNow       = GetServerTime()
        print(string.format(
            "|cffcc88ffDunDun Tracker:|r now=|cffFFFF00%d|r  weekStart=|cffFFFF00%d|r  nextReset=|cffFFFF00%d|r  secsUntilReset=|cffFFFF00%d|r",
            dbgNow, dbgWeekStart, dbgNextReset, dbgNextReset - dbgNow))
        print("|cffcc88ffDunDun Tracker:|r DB state:")
        local count = 0
        if DundunTrackerDB then
            for k, v in pairs(DundunTrackerDB) do
                if type(v) == "table" and k:sub(1,1) ~= "_" then
                    count = count + 1
                    local staleFlag = (v.lastSaved and v.lastSaved < dbgWeekStart) and "|cffFF4444STALE|r" or "|cff44FF44fresh|r"
                    print(string.format("  |cffFFFF00%s|r => qty=%s weekly=%s lastSaved=%s [%s]",
                        tostring(k), tostring(v.quantity), tostring(v.weeklyEarned),
                        tostring(v.lastSaved), staleFlag))
                end
            end
        end
        if count == 0 then print("  (empty)") end

    else
        ToggleWindow()
    end
end
