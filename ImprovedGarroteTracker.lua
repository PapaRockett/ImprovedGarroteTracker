-- ImprovedGarroteTracker
-- Retail/Midnight passive-only tracker.
--
-- Safety model:
-- * This addon never performs restricted gameplay actions.
-- * It does not create buttons, secure templates, macros, bindings, or nameplate UI.
-- * It does not modify, hook, or anchor to Blizzard frames, nameplates, aura buttons,
--   unit frames, raid frames, or action bars.
-- * It uses one invisible event frame plus one independent small movable icon display parented
--   directly to UIParent.
-- * Tracking is based on the player's successful Garrote casts plus an estimated
--   Improved Garrote window. Combat-log tracking is intentionally not used for
--   Midnight compatibility; no combat-log events are registered or read.

local ADDON_NAME = ...

local GARROTE_SPELL_ID = 703
local IMPROVED_GARROTE_SPELL_ID = 392403
local STEALTH_SPELL_ID = 1784
local VANISH_SPELL_ID = 1856

local GARROTE_BASE_DURATION = 18
local GARROTE_PANDEMIC_EXTENSION = 5.4
local GARROTE_MAX_DURATION = GARROTE_BASE_DURATION + GARROTE_PANDEMIC_EXTENSION
local POST_STEALTH_IMPROVED_WINDOW = 6
local TEST_DISPLAY_DURATION = 3

local DEFAULT_SAVED_VARIABLES = {
    debug = false,
    locked = true,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 120,
}

local state = {
    playerGUID = nil,
    improvedGarrotes = {},
    warnedMissingAuraAPI = false,
    improvedWindowUntil = 0,
    hadStealthLikeAura = false,
}

local eventFrame = CreateFrame("Frame")
local displayFrame
local displayTexture
local updateElapsed = 0
local testDisplayUntil = 0

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff77ff77IGT:|r " .. tostring(message))
end

local function DebugPrint(message)
    if ImprovedGarroteTrackerDB and ImprovedGarroteTrackerDB.debug then
        Print(message)
    end
end

local function EnsureSavedVariables()
    if type(ImprovedGarroteTrackerDB) ~= "table" then
        ImprovedGarroteTrackerDB = {}
    end

    for key, value in pairs(DEFAULT_SAVED_VARIABLES) do
        if ImprovedGarroteTrackerDB[key] == nil then
            ImprovedGarroteTrackerDB[key] = value
        end
    end
end

local function CountTrackedImprovedGarrotes()
    local count = 0
    local now = GetTime()

    for targetGUID, expires in pairs(state.improvedGarrotes) do
        if expires and expires > now then
            count = count + 1
        else
            state.improvedGarrotes[targetGUID] = nil
        end
    end

    return count
end

local function PrintBlockedAction(event, addonName, blockedFunction)
    Print("blocked action: event=" .. tostring(event) .. " addon=" .. tostring(addonName) .. " function=" .. tostring(blockedFunction))

    if debugstack then
        Print("Stack: " .. tostring(debugstack()))
    end
end

local function GetSpellNameSafe(spellID, fallbackName)
    if C_Spell and C_Spell.GetSpellName then
        local spellName = C_Spell.GetSpellName(spellID)

        if spellName then
            return spellName
        end
    end

    return fallbackName
end

local function PlayerHasAuraByName(unit, spellID, fallbackName, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local spellName = GetSpellNameSafe(spellID, fallbackName)
        return C_UnitAuras.GetAuraDataBySpellName(unit, spellName, filter) ~= nil
    end

    if not state.warnedMissingAuraAPI then
        state.warnedMissingAuraAPI = true
        Print("warning: no supported aura-name API is available; assuming aura absent.")
    end

    return false
end

local function PlayerHasImprovedGarroteAura()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(IMPROVED_GARROTE_SPELL_ID) ~= nil
    end

    return PlayerHasAuraByName("player", IMPROVED_GARROTE_SPELL_ID, "Improved Garrote", "HELPFUL|PLAYER")
end

local function PlayerHasStealthLikeAura()
    return PlayerHasAuraByName("player", STEALTH_SPELL_ID, "Stealth", "HELPFUL|PLAYER")
        or PlayerHasAuraByName("player", VANISH_SPELL_ID, "Vanish", "HELPFUL|PLAYER")
end

local function PlayerInImprovedGarroteWindow()
    return PlayerHasImprovedGarroteAura()
        or PlayerHasStealthLikeAura()
        or GetTime() <= state.improvedWindowUntil
end

local function TargetIsMarkedImproved()
    local targetGUID = UnitGUID("target")

    if not targetGUID then
        return false
    end

    local expires = state.improvedGarrotes[targetGUID]

    if expires and expires > GetTime() then
        return true
    end

    if expires then
        state.improvedGarrotes[targetGUID] = nil
    end

    return false
end

local function GetTargetMarkRemaining(targetGUID)
    if not targetGUID then
        return 0
    end

    local expires = state.improvedGarrotes[targetGUID]

    if not expires then
        return 0
    end

    local remaining = expires - GetTime()

    if remaining <= 0 then
        state.improvedGarrotes[targetGUID] = nil
        return 0
    end

    return remaining
end

local function UpdateDisplay()
    if not displayFrame then
        return
    end

    if testDisplayUntil > GetTime() or not ImprovedGarroteTrackerDB.locked or TargetIsMarkedImproved() then
        displayFrame:Show()
    else
        displayFrame:Hide()
    end
end

local function MarkCurrentTargetFromGarroteCast()
    local targetGUID = UnitGUID("target")

    if not targetGUID then
        DebugPrint("Garrote cast succeeded with no target GUID; no mark changed.")
        UpdateDisplay()
        return
    end

    if PlayerInImprovedGarroteWindow() then
        local now = GetTime()
        local existingExpires = state.improvedGarrotes[targetGUID]
        local remaining = 0

        if existingExpires and existingExpires > now then
            remaining = existingExpires - now
        end

        local pandemicExtension = math.min(remaining, GARROTE_PANDEMIC_EXTENSION)
        state.improvedGarrotes[targetGUID] = math.min(now + GARROTE_BASE_DURATION + pandemicExtension, now + GARROTE_MAX_DURATION)
        DebugPrint("Garrote cast succeeded during Improved Garrote window; marked " .. tostring(targetGUID))
    else
        state.improvedGarrotes[targetGUID] = nil
        DebugPrint("Normal Garrote cast succeeded; cleared " .. tostring(targetGUID))
    end

    UpdateDisplay()
end

local function RefreshPlayerStealthWindow()
    local hasStealthLikeAura = PlayerHasStealthLikeAura()

    if hasStealthLikeAura then
        state.hadStealthLikeAura = true
        state.improvedWindowUntil = GetTime() + POST_STEALTH_IMPROVED_WINDOW
        DebugPrint("Stealth/Vanish aura active; refreshed Improved Garrote window.")
    elseif state.hadStealthLikeAura then
        state.hadStealthLikeAura = false
        state.improvedWindowUntil = GetTime() + POST_STEALTH_IMPROVED_WINDOW
        DebugPrint("Stealth/Vanish aura ended; started post-stealth Improved Garrote window.")
    end
end

local function SaveDisplayPosition()
    local point, _, relativePoint, x, y = displayFrame:GetPoint(1)

    ImprovedGarroteTrackerDB.point = point or "CENTER"
    ImprovedGarroteTrackerDB.relativePoint = relativePoint or "CENTER"
    ImprovedGarroteTrackerDB.x = x or 0
    ImprovedGarroteTrackerDB.y = y or 120
end

local function ApplyDisplayLockState()
    if not displayFrame then
        return
    end

    displayFrame:SetMovable(not ImprovedGarroteTrackerDB.locked)
    displayFrame:EnableMouse(not ImprovedGarroteTrackerDB.locked)
    displayFrame:RegisterForDrag("LeftButton")
    UpdateDisplay()
end

local function CreateDisplay()
    displayFrame = CreateFrame("Frame", nil, UIParent)
    displayFrame:SetSize(10, 10)
    displayFrame:SetPoint(ImprovedGarroteTrackerDB.point, UIParent, ImprovedGarroteTrackerDB.relativePoint, ImprovedGarroteTrackerDB.x, ImprovedGarroteTrackerDB.y)

    displayTexture = displayFrame:CreateTexture(nil, "OVERLAY")
    displayTexture:SetAllPoints(displayFrame)
    displayTexture:SetColorTexture(1, 0.2, 0.7, 1)

    displayFrame:SetClampedToScreen(true)
    displayFrame:SetScript("OnDragStart", function(frame)
        if not ImprovedGarroteTrackerDB.locked then
            frame:StartMoving()
        end
    end)
    displayFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        SaveDisplayPosition()
    end)
    ApplyDisplayLockState()
end

local function PrintStatus()
    local targetGUID = UnitGUID("target")
    local improvedWindowRemaining = math.max(0, state.improvedWindowUntil - GetTime())

    Print("playerGUID=" .. tostring(state.playerGUID))
    Print("targetGUID=" .. tostring(targetGUID))
    Print("playerHasImprovedGarroteAura=" .. tostring(PlayerHasImprovedGarroteAura()))
    Print("playerHasStealthLikeAura=" .. tostring(PlayerHasStealthLikeAura()))
    Print("playerInImprovedGarroteWindow=" .. tostring(PlayerInImprovedGarroteWindow()))
    Print("improvedWindowRemaining=" .. string.format("%.1f", improvedWindowRemaining))
    Print("targetMarkedImproved=" .. tostring(TargetIsMarkedImproved()))
    Print("targetMarkRemaining=" .. string.format("%.1f", GetTargetMarkRemaining(targetGUID)))
    Print("locked=" .. tostring(ImprovedGarroteTrackerDB.locked))
    Print("displayPosition=" .. tostring(ImprovedGarroteTrackerDB.point) .. "," .. tostring(ImprovedGarroteTrackerDB.relativePoint) .. "," .. string.format("%.1f", ImprovedGarroteTrackerDB.x or 0) .. "," .. string.format("%.1f", ImprovedGarroteTrackerDB.y or 0))
    Print("trackedImprovedGarrotes=" .. tostring(CountTrackedImprovedGarrotes()))
    Print("trackingMode=UNIT_SPELLCAST_SUCCEEDED + estimated timer; no combat log; no secret aura field comparisons")
end

local function PrintHelp()
    Print("commands: /igt status, /igt test, /igt lock, /igt unlock, /igt reset, /igt debug on, /igt debug off")
end

local function RunDisplayTest()
    if not displayFrame then
        Print("display is not ready yet.")
        return
    end

    testDisplayUntil = GetTime() + TEST_DISPLAY_DURATION
    UpdateDisplay()
    Print("showing test square for " .. tostring(TEST_DISPLAY_DURATION) .. " seconds.")

    if C_Timer and C_Timer.After then
        C_Timer.After(TEST_DISPLAY_DURATION, UpdateDisplay)
    end
end

local function HandleSlashCommand(input)
    local command, argument = string.match(string.lower(input or ""), "^(%S*)%s*(.-)$")

    if command == "status" then
        PrintStatus()
    elseif command == "test" then
        RunDisplayTest()
    elseif command == "lock" then
        ImprovedGarroteTrackerDB.locked = true
        ApplyDisplayLockState()
        Print("display locked.")
    elseif command == "unlock" then
        ImprovedGarroteTrackerDB.locked = false
        ApplyDisplayLockState()
        Print("display unlocked; drag the pink square with the left mouse button.")
    elseif command == "reset" then
        ImprovedGarroteTrackerDB.point = "CENTER"
        ImprovedGarroteTrackerDB.relativePoint = "CENTER"
        ImprovedGarroteTrackerDB.x = 0
        ImprovedGarroteTrackerDB.y = 120
        if displayFrame then
            displayFrame:ClearAllPoints()
            displayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        end
        UpdateDisplay()
        Print("display position reset.")
    elseif command == "debug" and argument == "on" then
        ImprovedGarroteTrackerDB.debug = true
        Print("debug enabled.")
    elseif command == "debug" and argument == "off" then
        ImprovedGarroteTrackerDB.debug = false
        Print("debug disabled.")
    else
        PrintHelp()
    end
end

local function OnEvent(_, event, arg1, arg2, arg3)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        PrintBlockedAction(event, arg1, arg2)
        return
    end

    if event == "PLAYER_LOGIN" then
        EnsureSavedVariables()
        state.playerGUID = UnitGUID("player")
        CreateDisplay()
        RefreshPlayerStealthWindow()
        UpdateDisplay()
        Print("loaded safely. Type /igt status for current tracking state.")
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateDisplay()
    elseif event == "UNIT_AURA" and arg1 == "player" then
        RefreshPlayerStealthWindow()
        UpdateDisplay()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        if arg3 == GARROTE_SPELL_ID then
            MarkCurrentTargetFromGarroteCast()
        end
    end
end

SLASH_IMPROVEDGARROTETRACKER1 = "/igt"
SlashCmdList.IMPROVEDGARROTETRACKER = HandleSlashCommand

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:SetScript("OnUpdate", function(_, elapsed)
    updateElapsed = updateElapsed + elapsed

    if updateElapsed >= 0.2 then
        updateElapsed = 0
        UpdateDisplay()
    end
end)
