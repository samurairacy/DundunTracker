-- LibDBIcon-1.0
-- Creates and manages minimap data-broker icon buttons.
-- Public Domain.

assert(LibStub, "LibDBIcon-1.0 requires LibStub")

local lib, oldminor = LibStub:NewLibrary("LibDBIcon-1.0", 26)
if not lib then return end

lib.objects = lib.objects or {}

-- ============================================================
--  Internal helpers
-- ============================================================

local function GetCursorAngle()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale  = UIParent:GetEffectiveScale()
    return math.deg(math.atan2((cy / scale) - my, (cx / scale) - mx)) % 360
end

local function ApplyPosition(button)
    local angle  = math.rad(button.db.minimapPos or 220)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius,
        math.sin(angle) * radius)
end

local function OnDragStart(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", function(s)
        s.db.minimapPos = GetCursorAngle()
        ApplyPosition(s)
    end)
end

local function OnDragStop(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
    self.db.minimapPos = GetCursorAngle()
    ApplyPosition(self)
end

-- ============================================================
--  Button factory
-- ============================================================

local function CreateButton(name, object, db)
    local button = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
    button:SetFrameLevel(8)
    button:SetFrameStrata("MEDIUM")
    button:SetSize(31, 31)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetClampedToScreen(false)

    -- Background circle
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Background")

    -- Icon
    local icon = button:CreateTexture(nil, "BORDER")
    icon:SetSize(17, 17)
    icon:SetPoint("CENTER")
    icon:SetTexture(object.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    button.icon = icon

    -- Ring border
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("CENTER")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Highlight
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(26, 26)
    hl:SetPoint("CENTER")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")

    button:SetScript("OnDragStart", OnDragStart)
    button:SetScript("OnDragStop",  OnDragStop)

    button:SetScript("OnEnter", function(self)
        if object.OnTooltipShow then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            object.OnTooltipShow(GameTooltip)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    button:SetScript("OnClick", function(self, btn)
        if object.OnClick then
            object.OnClick(self, btn)
        end
    end)

    button.db = db
    db.minimapPos = db.minimapPos or 220

    ApplyPosition(button)

    if db.hide then button:Hide() else button:Show() end

    lib.objects[name] = button
    return button
end

-- ============================================================
--  Public API
-- ============================================================

function lib:Register(name, object, db)
    if not db then error("LibDBIcon: 'db' argument cannot be nil.") end
    if lib.objects[name] then return end
    db.minimapPos = db.minimapPos or 220
    if db.hide == nil then db.hide = false end
    CreateButton(name, object, db)
end

function lib:Show(name)
    local b = lib.objects[name]
    if b then b.db.hide = false ; b:Show() end
end

function lib:Hide(name)
    local b = lib.objects[name]
    if b then b.db.hide = true ; b:Hide() end
end

function lib:Toggle(name)
    local b = lib.objects[name]
    if not b then return end
    if b.db.hide then
        b.db.hide = false ; b:Show()
    else
        b.db.hide = true  ; b:Hide()
    end
end

function lib:IsRegistered(name)
    return lib.objects[name] ~= nil
end

function lib:Refresh(name, db)
    local b = lib.objects[name]
    if not b then return end
    if db then b.db = db end
    ApplyPosition(b)
    if b.db.hide then b:Hide() else b:Show() end
end

function lib:GetMinimapButton(name)
    return lib.objects[name]
end
