-- ImprovedGarroteTracker
-- Retail/Midnight passive-only tracker.
--
-- Safety model:
-- * This addon never performs restricted gameplay actions.
-- * It does not create buttons, secure templates, macros, bindings, or nameplate UI.
-- * It does not modify, hook, or anchor to Blizzard frames, nameplates, aura buttons,
--   unit frames, raid frames, or action bars.
-- * It uses one invisible event frame plus one independent text-only display parented
--   directly to UIParent.
-- * Tracking is target-aura based only. Combat-log tracking was intentionally removed
--   for Midnight compatibility; no combat-log events are registered or read.

local ADDON_NAME = ...

local GARROTE_SPELL_ID = 703
local IMPROVED_GARROTE_SPELL_ID = 392403

local DEFAULT_SAVED_VARIABLES = {
    debug = false,
}

local state = {
    playerGUID = nil,
    improvedGarrotes = {},
    warnedMissingAuraAPI = false,
}

local eventFrame = CreateFrame("Frame")
local displayFrame
local displayText

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

local function TargetHasPlayerGarrote()
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local garroteName = GetSpellNameSafe(GARROTE_SPELL_ID, "Garrote")
        return C_UnitAuras.GetAuraDataBySpellName("target", garroteName, "HARMFUL|PLAYER") ~= nil
    end

    if not state.warnedMissingAuraAPI then
        state.warnedMissingAuraAPI = true
        Print("warning: no supported aura API is available for target Garrote detection; assuming absent.")
    end

    return false
end

local function PlayerHasImprovedGarrote()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(IMPROVED_GARROTE_SPELL_ID) ~= nil
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local improvedGarroteName = GetSpellNameSafe(IMPROVED_GARROTE_SPELL_ID, "Improved Garrote")
        return C_UnitAuras.GetAuraDataBySpellName("player", improvedGarroteName, "HELPFUL|PLAYER") ~= nil
    end

    if not state.warnedMissingAuraAPI then
        state.warnedMissingAuraAPI = true
        Print("warning: no supported aura API is available for Improved Garrote detection; assuming inactive.")
    end

    return false
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

local function UpdateDisplay()
    if not displayText then
        return
    end

    -- The display frame remains created and parented only to UIParent. To keep the
    -- implementation maximally passive, updates only change this addon's text.
    if TargetIsMarkedImproved() then
        displayText:SetText("Improved Garrote")
    else
        displayText:SetText("")
    end
end

local function RefreshTargetGarroteState(reason)
    local targetGUID = UnitGUID("target")

    if not targetGUID then
        UpdateDisplay()
        return
    end

    if not TargetHasPlayerGarrote() then
        state.improvedGarrotes[targetGUID] = nil
        DebugPrint("Target player Garrote missing; cleared " .. tostring(targetGUID) .. " (" .. tostring(reason) .. ")")
        UpdateDisplay()
        return
    end

    if PlayerHasImprovedGarrote() then
        state.improvedGarrotes[targetGUID] = GetTime() + 23.4
        DebugPrint("Target player Garrote marked improved on " .. tostring(targetGUID) .. " (" .. tostring(reason) .. ")")
        UpdateDisplay()
        return
    end

    DebugPrint("Target player Garrote present without current Improved Garrote; preserved existing mark for " .. tostring(targetGUID) .. " (" .. tostring(reason) .. ")")
    UpdateDisplay()
end

local function CreateDisplay()
    displayFrame = CreateFrame("Frame", nil, UIParent)
    displayFrame:SetSize(220, 32)
    displayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)

    displayText = displayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    displayText:SetPoint("CENTER", displayFrame, "CENTER")
    displayText:SetTextColor(0.7, 1.0, 0.7)
    displayText:SetText("")
end

local function PrintStatus()
    local targetGUID = UnitGUID("target")

    Print("playerGUID=" .. tostring(state.playerGUID))
    Print("targetGUID=" .. tostring(targetGUID))
    Print("targetHasPlayerGarrote=" .. tostring(TargetHasPlayerGarrote()))
    Print("playerHasImprovedGarrote=" .. tostring(PlayerHasImprovedGarrote()))
    Print("targetMarkedImproved=" .. tostring(TargetIsMarkedImproved()))
    Print("trackedImprovedGarrotes=" .. tostring(CountTrackedImprovedGarrotes()))
    Print("trackingMode=target aura presence only; secret aura fields are not read")
end

local function PrintHelp()
    Print("commands: /igt status, /igt debug on, /igt debug off")
end

local function HandleSlashCommand(input)
    local command, argument = string.match(string.lower(input or ""), "^(%S*)%s*(.-)$")

    if command == "status" then
        PrintStatus()
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

local function OnEvent(_, event, arg1, arg2)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        PrintBlockedAction(event, arg1, arg2)
        return
    end

    if event == "PLAYER_LOGIN" then
        EnsureSavedVariables()
        state.playerGUID = UnitGUID("player")
        CreateDisplay()
        RefreshTargetGarroteState(event)
        Print("loaded safely. Type /igt status for current tracking state.")
    elseif event == "PLAYER_TARGET_CHANGED" then
        RefreshTargetGarroteState(event)
    elseif event == "UNIT_AURA" and arg1 == "target" then
        RefreshTargetGarroteState(event)
    end
end

SLASH_IMPROVEDGARROTETRACKER1 = "/igt"
SlashCmdList.IMPROVEDGARROTETRACKER = HandleSlashCommand

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:SetScript("OnEvent", OnEvent)
