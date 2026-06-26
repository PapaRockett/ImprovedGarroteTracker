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
-- * Tracking is inferred only from combat-log events and the player's own aura state.

local ADDON_NAME = ...

local GARROTE_SPELL_ID = 703
local IMPROVED_GARROTE_SPELL_ID = 392403
local CRIMSON_TEMPEST_SPELL_ID = 1247227
local CRIMSON_TEMPEST_SPREAD_WINDOW_SECONDS = 0.5

local DEFAULT_SAVED_VARIABLES = {
    debug = false,
}

local state = {
    playerGUID = nil,
    improvedGarrotes = {},
    crimsonSpreadUntil = 0,
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

    for _ in pairs(state.improvedGarrotes) do
        count = count + 1
    end

    return count
end

local function AnyTrackedImprovedGarroteExists()
    return next(state.improvedGarrotes) ~= nil
end

local function PrintBlockedAction(event, addonName, blockedFunction)
    Print("blocked action: event=" .. tostring(event) .. " addon=" .. tostring(addonName) .. " function=" .. tostring(blockedFunction))

    if debugstack then
        Print("Stack: " .. tostring(debugstack()))
    end
end

local function PlayerHasImprovedGarrote()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(IMPROVED_GARROTE_SPELL_ID) ~= nil
    end

    if AuraUtil and AuraUtil.FindAuraBySpellID then
        return AuraUtil.FindAuraBySpellID(IMPROVED_GARROTE_SPELL_ID, "player", "HELPFUL") ~= nil
    end

    if not state.warnedMissingAuraAPI then
        state.warnedMissingAuraAPI = true
        Print("warning: no supported aura API is available for Improved Garrote detection; assuming inactive.")
    end

    return false
end

local function CrimsonSpreadWindowIsActive()
    return GetTime() <= state.crimsonSpreadUntil
end

local function TargetIsMarkedImproved()
    local targetGUID = UnitGUID("target")
    return targetGUID and state.improvedGarrotes[targetGUID] ~= nil
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

local function MarkGarrote(destGUID, destName, improved, reason)
    if not destGUID then
        return
    end

    if improved then
        state.improvedGarrotes[destGUID] = true
        DebugPrint("Garrote marked improved on " .. tostring(destName or destGUID) .. " (" .. tostring(reason) .. ")")
    else
        state.improvedGarrotes[destGUID] = nil
        DebugPrint("Garrote marked normal on " .. tostring(destName or destGUID))
    end

    UpdateDisplay()
end

local function RemoveGarrote(destGUID, destName)
    if not destGUID then
        return
    end

    state.improvedGarrotes[destGUID] = nil
    DebugPrint("Garrote removed from " .. tostring(destName or destGUID))
    UpdateDisplay()
end

local function HandleCombatLogEvent()
    local _, subevent, _, sourceGUID, _, _, _, destGUID, destName, _, _, spellID = CombatLogGetCurrentEventInfo()

    if not state.playerGUID then
        state.playerGUID = UnitGUID("player")
    end

    if sourceGUID ~= state.playerGUID then
        return
    end

    if spellID == GARROTE_SPELL_ID then
        if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
            local hasImprovedGarrote = PlayerHasImprovedGarrote()
            local inCrimsonSpreadWindow = CrimsonSpreadWindowIsActive()

            -- Crimson Tempest spreading is inferential/best-effort: the combat log
            -- does not explicitly say a spread Garrote inherited Improved Garrote.
            -- During the short post-cast window, Garrote applications/refreshed by
            -- the player are treated as improved when any improved Garrote was
            -- already tracked at the time Crimson Tempest was cast.
            MarkGarrote(
                destGUID,
                destName,
                hasImprovedGarrote or inCrimsonSpreadWindow,
                hasImprovedGarrote and "Improved Garrote aura" or "Crimson Tempest spread inference"
            )
        elseif subevent == "SPELL_AURA_REMOVED" then
            RemoveGarrote(destGUID, destName)
        end
    elseif spellID == CRIMSON_TEMPEST_SPELL_ID and subevent == "SPELL_CAST_SUCCESS" then
        if AnyTrackedImprovedGarroteExists() then
            state.crimsonSpreadUntil = GetTime() + CRIMSON_TEMPEST_SPREAD_WINDOW_SECONDS
            DebugPrint("Crimson Tempest spread window active for " .. tostring(CRIMSON_TEMPEST_SPREAD_WINDOW_SECONDS) .. " seconds")
        end
    end
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
    Print("targetMarkedImproved=" .. tostring(TargetIsMarkedImproved()))
    Print("playerHasImprovedGarrote=" .. tostring(PlayerHasImprovedGarrote()))
    Print("trackedImprovedGarrotes=" .. tostring(CountTrackedImprovedGarrotes()))
    Print("crimsonTempestSpreadWindowActive=" .. tostring(CrimsonSpreadWindowIsActive()))
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
        UpdateDisplay()
        Print("loaded safely. Type /igt status for current tracking state.")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLogEvent()
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateDisplay()
    end
end

SLASH_IMPROVEDGARROTETRACKER1 = "/igt"
SlashCmdList.IMPROVEDGARROTETRACKER = HandleSlashCommand

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:SetScript("OnEvent", OnEvent)
