local _, ns = ...
if ns.Inactive then return end
local MR = ns.MR

local L = LibStub("AceLocale-3.0"):GetLocale("MidnightRoutine")
local Warband = assert(ns.WarbandBoardInternal, "UI/Warband/Shared.lua must load first")
local FormatDuration = Warband.WBFormatDurationShort

local HOUR = 3600
local DEFAULT_HOURS = 24
local FINAL_CALL_SECONDS = HOUR
local LOGIN_DELAY = 8
local MAX_TASKS_SHOWN = 3
local SEPARATOR = "|cff687582, |r"

local BUSY_INSTANCE_TYPES = {
    party = true,
    raid = true,
    pvp = true,
    arena = true,
    scenario = true,
}

local pendingTimer
local waitingForSafeMoment

local function IsEnabled()
    return MR.db and MR.db.profile and MR.db.profile.resetReminder == true
end

local function GetWarningSeconds()
    return (tonumber(MR.db.profile.resetReminderHours) or DEFAULT_HOURS) * HOUR
end

local function GetSecondsUntilReset()
    local seconds = tonumber(C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset())
    return seconds and seconds > 0 and seconds or nil
end

local function GetResetTimestamp(seconds)
    return math.floor((GetServerTime() + seconds + 30) / 60) * 60
end

local function GetStage(seconds)
    if seconds <= FINAL_CALL_SECONDS then return 2 end
    if seconds <= GetWarningSeconds() then return 1 end
    return 0
end

local function IsSafeMoment()
    if InCombatLockdown() or UnitAffectingCombat("player") then return false end
    local inInstance, instanceType = IsInInstance()
    return not (inInstance and BUSY_INSTANCE_TYPES[instanceType])
end

local function CollectRows(entry)
    local rows = {}
    for _, group in ipairs(entry.groups or {}) do
        for _, row in ipairs(group.rows or {}) do
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function BuildSummary()
    local summary = { total = 0, characters = 0 }
    if not MR.GetWarbandMainOverview then return summary end
    for _, entry in ipairs(MR:GetWarbandMainOverview()) do
        local remaining = tonumber(entry.remaining) or 0
        if remaining > 0 then
            summary.total = summary.total + remaining
            summary.characters = summary.characters + 1
            if entry.isCurrent then
                summary.current = { entry = entry, rows = CollectRows(entry), remaining = remaining }
            end
        end
    end
    return summary
end

local function ColoredName(entry)
    local color = entry.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile]
    local name = entry.name or "?"
    return color and color:WrapTextInColorCode(name) or name
end

local function TaskText(row)
    local label = ns.StripColorCodes(row.label or "")
    if row.displayValue then
        return label .. " |cffffc94d" .. row.displayValue .. "|r"
    end
    return label
end

local function MoreText(count)
    return count > 0 and (SEPARATOR .. string.format(L["ResetReminder_More"], count)) or ""
end

local function PrintSummary(summary, seconds)
    local across = summary.characters > 1 and string.format(L["ResetReminder_AcrossCharacters"], summary.characters) or ""
    print(string.format(L["ResetReminder_Header"], FormatDuration(seconds), summary.total, across))

    local current = summary.current
    if current then
        local tasks = {}
        for index = 1, math.min(#current.rows, MAX_TASKS_SHOWN) do
            tasks[#tasks + 1] = TaskText(current.rows[index])
        end
        print("  " .. string.format(L["ResetReminder_Current"], ColoredName(current.entry), current.remaining)
            .. table.concat(tasks, SEPARATOR) .. MoreText(current.remaining - #tasks))
    end

    print("  |cff8a8f99" .. L["ResetReminder_Hint"] .. "|r")
end

function MR:ShowResetReminder(manual)
    local seconds = GetSecondsUntilReset()
    if not seconds then
        if manual then print(L["ResetReminder_Unavailable"]) end
        return false
    end
    local summary = BuildSummary()
    if summary.total == 0 then
        if manual then print(string.format(L["ResetReminder_AllDone"], FormatDuration(seconds))) end
        return false
    end
    PrintSummary(summary, seconds)
    return true
end

local Check

local function ScheduleNext(seconds)
    if pendingTimer then
        pendingTimer:Cancel()
        pendingTimer = nil
    end
    local warning = GetWarningSeconds()
    local delay
    if seconds > warning then
        delay = seconds - warning
    elseif seconds > FINAL_CALL_SECONDS then
        delay = seconds - FINAL_CALL_SECONDS
    end
    if delay then
        pendingTimer = C_Timer.NewTimer(delay + 5, Check)
    end
end

Check = function()
    pendingTimer = nil
    waitingForSafeMoment = nil
    if not IsEnabled() then return end
    local seconds = GetSecondsUntilReset()
    if not seconds then return end
    ScheduleNext(seconds)

    local stage = GetStage(seconds)
    if stage == 0 then return end
    local resetAt = GetResetTimestamp(seconds)
    local state = MR.db.char.resetReminder
    if type(state) == "table" and state.resetAt == resetAt and (tonumber(state.stage) or 0) >= stage then return end
    if not IsSafeMoment() then
        waitingForSafeMoment = true
        return
    end

    MR:ShowResetReminder(false)
    MR.db.char.resetReminder = { resetAt = resetAt, stage = stage }
end

function MR:RefreshResetReminder()
    if pendingTimer then
        pendingTimer:Cancel()
        pendingTimer = nil
    end
    waitingForSafeMoment = nil
    if IsEnabled() then Check() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(LOGIN_DELAY, Check)
    elseif waitingForSafeMoment then
        C_Timer.After(2, Check)
    end
end)
