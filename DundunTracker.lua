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
--  Saved Variables  (per-account, shared across all chars)
-- ============================================================
-- DundunTrackerDB["CharName-Realm"] = {
--     name         = "CharName",
--     realm        = "Realm",
--     class        = "WARRIOR",
--     quantity     = 3,
--     weeklyEarned = 5,
--     weeklyCap    = 8,
--     totalCap     = 8,
--     lastSaved    = <unix timestamp>,   -- set every time SaveCurrentChar runs
-- }
-- DundunTrackerDB._lastResetTime = <unix timestamp>
--     Set whenever the current character's weeklyEarned drops, indicating a
--     weekly reset occurred. Used to zero out stale alt data in the UI.

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

local function SaveCurrentChar()
    if not DundunTrackerDB then return end
    local info = C_CurrencyInfo.GetCurrencyInfo(CURRENCY_ID)
    if not info then return end

    local weeklyCap = (info.maxWeeklyQuantity and info.maxWeeklyQuantity > 0)
                      and info.maxWeeklyQuantity or WEEKLY_CAP
    local totalCap  = (info.maxQuantity and info.maxQuantity > 0)
                      and info.maxQuantity or TOTAL_CAP

    local key            = GetCharKey()
    local newWeeklyEarned = info.quantityEarnedThisWeek or 0

    -- If weekly earned dropped from last save, a reset occurred — record it.
    local prev = DundunTrackerDB[key]
    if prev and (prev.weeklyEarned or 0) > newWeeklyEarned then
        DundunTrackerDB._lastResetTime = GetServerTime()
    end

    DundunTrackerDB[key] = {
        name         = UnitName("player"),
        realm        = GetRealmName(),
        class        = select(2, UnitClass("player")),
        quantity     = info.quantity or 0,
        weeklyEarned = newWeeklyEarned,
        weeklyCap    = weeklyCap,
        totalCap     = totalCap,
        lastSaved    = GetServerTime(),
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

local COL_NAME    = 210
local COL_WEEKLY  = 115
local COL_TOTAL   = 115
local WIN_WIDTH   = COL_NAME + COL_WEEKLY + COL_TOTAL + 32
local ROW_HEIGHT  = 22
local HEADER_H    = 22
local TITLE_BAR_H = 26
local QUOTE_H     = 24
local FOOTER_H    = 48
local MIN_WIN_H   = 160

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

    row.nameText   = nameText
    row.weeklyText = weeklyText
    row.totalText  = totalText
    return row
end

local function CreateWindow()
    local f = CreateFrame("Frame", "DundunTrackerWindow", UIParent, "BackdropTemplate")
    f:SetSize(WIN_WIDTH, 280)
    f:SetPoint("CENTER")
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetResizable(true)
    f:SetResizeBounds(WIN_WIDTH, MIN_WIN_H)

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

    local function HeaderCell(text, x, w)
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", headerRow, "TOPLEFT", x, 0)
        fs:SetSize(w, HEADER_H)
        fs:SetJustifyH("CENTER")
        fs:SetText(text)
        fs:SetTextColor(0.9, 0.8, 0.5)
    end
    HeaderCell("Character",       0,                     COL_NAME)
    HeaderCell("Weekly (picked)", COL_NAME,              COL_WEEKLY)
    HeaderCell("Total (held)",    COL_NAME + COL_WEEKLY, COL_TOTAL)

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
    content:SetSize(WIN_WIDTH - 36, 1)
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

    -- Credit text
    local creditText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    creditText:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  12, 12)
    creditText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    creditText:SetJustifyH("LEFT")
    creditText:SetTextColor(0.4, 0.35, 0.5)
    creditText:SetText("Addon by Parmenides-Khaz'goroth; vibecoded using Claude Sonnet 4.6")

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

    -- Compute the start of the current reset week using the game's own API.
    -- Any alt whose lastSaved predates this is carrying last-week's data.
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

        -- Alt data saved before this week's reset boundary is stale; show 0.
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

    -- Highlight the active mode button
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

    -- Rebuild checkboxes
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
    titleBar:SetBackdropBorderColor(0.55, 0.30, 0.75, 1)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("CENTER")
    titleText:SetText("|cffcc88ffDunDun Tracker - Settings|r")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 4, 4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Info text
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

    -- Mode label + buttons
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

    -- Divider
    local DIVIDER_TOP = MODE_TOP + 18 + 22 + 8
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.4, 0.25, 0.6, 0.45)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  f, "TOPLEFT",   8, -DIVIDER_TOP)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -8, -DIVIDER_TOP)

    -- "No mode selected" placeholder
    local LIST_TOP = DIVIDER_TOP + 8
    local noModeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noModeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -LIST_TOP)
    noModeLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -LIST_TOP)
    noModeLabel:SetJustifyH("LEFT")
    noModeLabel:SetTextColor(0.40, 0.38, 0.48)
    noModeLabel:SetText("Select Whitelist or Blacklist above to manage the character list.")
    f.noModeLabel = noModeLabel

    -- Character list scroll frame
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

local function AutoSizeWindow()
    if not DundunTrackerDB then return end
    local count = 0
    for k, v in pairs(DundunTrackerDB) do
        if type(v) == "table" and k:sub(1,1) ~= "_" and IsCharVisible(k) then count = count + 1 end
    end
    if count == 0 then return end
    -- Fixed vertical overhead: top inset + title bar + gap + quote bar + gap + header + gap
    local scrollTop = (6 + TITLE_BAR_H + 4) + QUOTE_H + 3 + HEADER_H + 2
    local idealH = scrollTop + FOOTER_H + (count * ROW_HEIGHT) + 8
    window:SetHeight(math.max(idealH, MIN_WIN_H))
end

local function ShowWindow()
    if not window then
        window = CreateWindow()
    end
    AutoSizeWindow()
    window.quoteText:SetText(GetNextQuote())
    SaveCurrentChar()
    window:Show()
    DundunTracker_RefreshWindow()
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

        -- DB migration: safely initialise any missing top-level fields
        if not DundunTrackerDB._minimapIcon then
            DundunTrackerDB._minimapIcon = { hide = false }
        end
        local s = DundunTrackerDB._settings
        if s then
            if s.expandPrimaryGear   == nil then s.expandPrimaryGear   = false end
            if s.expandSecondaryGear == nil then s.expandSecondaryGear = false end
            if s.expandFusedVitality == nil then s.expandFusedVitality = false end
            if s.expandUnalloyed     == nil then s.expandUnalloyed     = false end
        end

        RegisterMinimapButton()

        -- Startup diagnostic: tells us how many chars were loaded from disk
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
