local _, ns = ...
if ns.Inactive then return end
local MR = ns.MR

local L = LibStub("AceLocale-3.0"):GetLocale("MidnightRoutine")
local tracking = ns.Tracking
local GetFontSize = ns.GetFontSize
local GetFontFlags = ns.GetFontFlags

local FRAME_NAME = "MidnightRoutineWhatsLeftFrame"
local POS_KEY = "whatsLeftPos"
local TITLE_H = 26
local DEFAULT_W = 340
local DEFAULT_H = 460
local PAD = 8

local frame
local lines = {}
local collapsed = {}
local refreshQueued = false

local function Label(key, fallback)
    local value = L[key]
    if type(value) ~= "string" or value == "" or value == key then
        return fallback
    end
    return value
end

local function HexToRGB(hexColor, r, g, b)
    if type(hexColor) ~= "string" then return r, g, b end
    local hexDigits = hexColor:match("^#?(%x%x%x%x%x%x)$")
    if not hexDigits then return r, g, b end
    return tonumber(hexDigits:sub(1, 2), 16) / 255, tonumber(hexDigits:sub(3, 4), 16) / 255, tonumber(hexDigits:sub(5, 6), 16) / 255
end

local function StripColor(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub(":%s*$", ""))
end

local function ClassColor(classFile)
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then return color.r, color.g, color.b end
    return 0.85, 0.88, 0.92
end

local function AcquireLine(index)
    local line = lines[index]
    if line then return line end
    line = CreateFrame("Button", nil, frame._content)
    line:SetHeight(18)
    line._bg = line:CreateTexture(nil, "BACKGROUND")
    line._bg:SetAllPoints()
    line._left = line:CreateFontString(nil, "OVERLAY")
    line._left:SetPoint("LEFT", line, "LEFT", 0, 0)
    line._left:SetJustifyH("LEFT")
    line._left:SetWordWrap(false)
    line._right = line:CreateFontString(nil, "OVERLAY")
    line._right:SetPoint("RIGHT", line, "RIGHT", -4, 0)
    line._right:SetJustifyH("RIGHT")
    line._right:SetWordWrap(false)
    line._left:SetPoint("RIGHT", line._right, "LEFT", -6, 0)
    line:SetScript("OnClick", function(self)
        if self._charKey then
            collapsed[self._charKey] = not collapsed[self._charKey]
            MR:RefreshWhatsLeft()
        end
    end)
    lines[index] = line
    return line
end

local function SetLine(index, y, indent, height, leftText, lr, lg, lb, rightText, rr, rg, rb, fontSize, header, charKey)
    local line = AcquireLine(index)
    local flags = GetFontFlags()
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", frame._content, "TOPLEFT", PAD + indent, -y)
    line:SetPoint("TOPRIGHT", frame._content, "TOPRIGHT", -PAD, -y)
    line:SetHeight(height)
    line._left:SetFont(header and ns.FONT_HEADERS or ns.FONT_ROWS, fontSize, flags)
    line._right:SetFont(ns.FONT_ROWS, fontSize, flags)
    line._left:SetText(leftText or "")
    line._left:SetTextColor(lr, lg, lb)
    line._right:SetText(rightText or "")
    line._right:SetTextColor(rr or 1, rg or 1, rb or 1)
    if header then
        line._bg:SetColorTexture(1, 1, 1, 0.045)
    else
        line._bg:SetColorTexture(0, 0, 0, 0)
    end
    line._charKey = charKey
    line:EnableMouse(charKey ~= nil)
    line:Show()
end

local function Render()
    if not (frame and frame:IsShown()) then return end
    local hasData = MR.GetWarbandWhatsLeft ~= nil
    local data = hasData and MR:GetWarbandWhatsLeft() or {}
    local baseSize = GetFontSize()
    local headerSize = math.max(9, baseSize)
    local groupSize = math.max(8, baseSize - 1)
    local rowSize = math.max(8, baseSize - 1)
    local headerH = headerSize + 10
    local rowH = rowSize + 7
    local used = 0
    local y = 4
    local totalLeft, charactersWithWork = 0, 0

    for _, entry in ipairs(data) do
        totalLeft = totalLeft + entry.remaining
        if entry.remaining > 0 then
            charactersWithWork = charactersWithWork + 1
        end

        local cr, cg, cb = ClassColor(entry.classFile)
        local nameText = entry.name or "?"
        if entry.isCurrent then
            nameText = nameText .. "  |cff8fa3b5(" .. Label("AltBoard_Current", "Current") .. ")|r"
        end
        if entry.stale then
            nameText = nameText .. "  |cff8a8f99" .. Label("WhatsLeft_Stale", "not logged in this week") .. "|r"
        end
        local rightText, rr, rg, rb
        if entry.remaining == 0 then
            rightText = Label("WhatsLeft_AllDone", "All done")
            rr, rg, rb = 0.30, 0.90, 0.50
        else
            rightText = string.format(Label("WhatsLeft_Count", "%d left"), entry.remaining)
            rr, rg, rb = 1.00, 0.78, 0.30
        end
        local isCollapsed = entry.remaining == 0 or collapsed[entry.key] == true
        local arrow = entry.remaining == 0 and "  " or (isCollapsed and "|cff889095+|r " or "|cff889095-|r ")
        used = used + 1
        SetLine(used, y, 0, headerH, arrow .. nameText, cr, cg, cb, rightText, rr, rg, rb, headerSize, true, entry.remaining > 0 and entry.key or nil)
        y = y + headerH + 2

        if not isCollapsed then
            for _, group in ipairs(entry.groups) do
                local gr, gg, gb = HexToRGB(group.color, 0.55, 0.85, 0.80)
                used = used + 1
                SetLine(used, y, 10, rowH, StripColor(group.label), gr, gg, gb, nil, nil, nil, nil, groupSize, false, nil)
                y = y + rowH
                for _, row in ipairs(group.rows) do
                    local valueText = row.displayValue or string.format("%d / %d", row.value, row.max)
                    local vr, vg, vb = 0.55, 0.60, 0.68
                    if row.value > 0 then
                        vr, vg, vb = 1.00, 0.78, 0.30
                    end
                    used = used + 1
                    SetLine(used, y, 20, rowH, StripColor(row.label), 0.84, 0.88, 0.93, StripColor(valueText), vr, vg, vb, rowSize, false, nil)
                    y = y + rowH
                end
            end
            y = y + 4
        end
    end

    if #data == 0 then
        used = used + 1
        local emptyText = hasData
            and Label("WhatsLeft_Empty", "No tracked characters yet. Log in on your alts to add them.")
            or Label("WhatsLeft_NeedsData", "Update RoutineData to use this window.")
        SetLine(used, y, 0, headerH, emptyText, 0.6, 0.65, 0.72, nil, nil, nil, nil, headerSize, false, nil)
        y = y + headerH
    end

    for index = used + 1, #lines do
        lines[index]._charKey = nil
        lines[index]:Hide()
    end

    frame._content:SetHeight(math.max(y + 4, 1))
    if hasData then
        frame._summary:SetText(string.format(Label("WhatsLeft_Summary", "%d left across %d characters"), totalLeft, charactersWithWork))
    else
        frame._summary:SetText("")
    end
    if frame.UpdateScrollBar then frame.UpdateScrollBar() end
end

local function Build()
    local f = ns.StyledFrame(UIParent, FRAME_NAME, "MEDIUM", 12)
    MR:RegisterPriorityFrame(f)
    f:SetSize(DEFAULT_W, DEFAULT_H)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(260, 220, 700, 900) end
    ns.RestoreManagedFramePos(f, POS_KEY, 0, 40)
    f.topAccent = ns.TopAccent(f, ns.ResolveThemeColor(0.25, 0.78, 0.68))

    local titleBar = ns.TitleBar(f, TITLE_H)
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        ns.SaveManagedFramePos(f, POS_KEY, "top")
    end)

    local close = ns.CloseButton(titleBar, function() f:Hide() end)

    local title = titleBar:CreateFontString(nil, "OVERLAY")
    title:SetFont(ns.FONT_HEADERS, math.max(9, GetFontSize() + 1), GetFontFlags())
    title:SetPoint("LEFT", titleBar, "LEFT", 9, 0)
    title:SetPoint("RIGHT", close, "LEFT", -6, 0)
    title:SetJustifyH("LEFT")
    title:SetText(Label("WhatsLeft_Title", "What's Left This Week"))
    ns.RegisterThemedFontString(title, 0.85, 0.90, 0.89)

    local summary = f:CreateFontString(nil, "OVERLAY")
    summary:SetFont(ns.FONT_ROWS, math.max(8, GetFontSize() - 1), GetFontFlags())
    summary:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", PAD, -5)
    summary:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -PAD, -5)
    summary:SetJustifyH("LEFT")
    summary:SetTextColor(0.62, 0.70, 0.78)
    f._summary = summary

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", -PAD, -5)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(DEFAULT_W - 8, 1)
    f._content = content

    local track = CreateFrame("Frame", nil, f)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 1, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 1, 0)
    track:SetWidth(5)
    f.UpdateScrollBar = ns.AttachScrollList(scroll, content, track, {
        hideTrack = true,
        trackColor = { 0, 0, 0, 0.22 },
        thumbColor = { 0.25, 0.78, 0.68, 0.62 },
    })

    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(math.max(1, width or 1))
        if f.UpdateScrollBar then f.UpdateScrollBar() end
    end)

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        ns.SaveManagedFramePos(f, POS_KEY, "top")
        if MR.SetWindowLayoutValue then
            MR:SetWindowLayoutValue("whatsLeftSize", { width = math.floor(f:GetWidth()), height = math.floor(f:GetHeight()) })
        end
    end)

    local savedSize = MR.GetWindowLayoutValue and MR:GetWindowLayoutValue("whatsLeftSize")
    if type(savedSize) == "table" and savedSize.width and savedSize.height then
        f:SetSize(savedSize.width, savedSize.height)
    end

    f:SetScript("OnShow", function() Render() end)
    f:Hide()
    if UISpecialFrames then
        table.insert(UISpecialFrames, FRAME_NAME)
    end
    return f
end

function MR:RefreshWhatsLeft()
    Render()
end

function MR:ToggleWhatsLeft()
    if not frame then
        frame = Build()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:SetScale((self.db and self.db.profile and self.db.profile.scale) or 1)
        frame:Show()
    end
end

local function QueueRefresh()
    if refreshQueued or not (frame and frame:IsShown()) then return end
    refreshQueued = true
    C_Timer.After(1, function()
        refreshQueued = false
        Render()
    end)
end

if tracking and tracking.RegisterCallback then
    tracking.RegisterCallback({}, "StatsInvalidated", QueueRefresh)
    tracking.RegisterCallback({}, "DataRefreshRequested", QueueRefresh)
end
