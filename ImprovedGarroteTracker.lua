-- ImprovedGarroteTracker
-- Retail/Midnight passive-only tracker.
--
-- Safety model:
-- * This addon never performs restricted gameplay actions.
-- * It does not create buttons, secure templates, macros, bindings, or nameplate UI.
-- * It uses one invisible event frame plus one independent text-only display parented
--   directly to UIParent.
-- * Tracking is inferred only from combat-log events and the player's own aura state.

local ADDON_NAME = ...

local GARROTE_SPELL_ID = 703
local IMPROVED_GARROTE_SPELL_ID = 392403
local CRIMSON_TEMPEST_SPELL_ID = 1247227
local CRIMSON_TEMPEST_SPREAD_WINDOW_SECONDS = 0.5

local state = {
    playerGUID = nil,
    improvedGarrotes = {},
    crimsonTempestWindowExpires = 0,
}

local f = CreateFrame("Frame")
local displayFrame
local displayText

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(tostring(message))
end

local function PrintBlockedAction(event, addonName, blockedFunction)
    Print("IGT blocked action: " .. tostring(event) .. " addon=" .. tostring(addonName) .. " function=" .. tostring(blockedFunction))

    if debugstack then
        Print("Stack: " .. tostring(debugstack()))
    end
end

local function HasImprovedGarroteBuff()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(IMPROVED_GARROTE_SPELL_ID) ~= nil
    end

    -- Conservative fallback for clients where GetPlayerAuraBySpellID is absent.
    -- This reads the player's own helpful aura data only.
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName and C_Spell and C_Spell.GetSpellName then
        local spellName = C_Spell.GetSpellName(IMPROVED_GARROTE_SPELL_ID)
        if spellName then
            return C_UnitAuras.GetAuraDataBySpellName("player", spellName, "HELPFUL") ~= nil
        end
    end

    return false
end

local function CrimsonTempestWindowIsActive()
    return GetTime() <= state.crimsonTempestWindowExpires
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
        Print("IGT: Garrote marked improved on " .. tostring(destName or destGUID) .. " (" .. tostring(reason) .. ")")
    else
        state.improvedGarrotes[destGUID] = nil
        Print("IGT: Garrote marked normal on " .. tostring(destName or destGUID))
    end

    UpdateDisplay()
end

local function RemoveGarrote(destGUID, destName)
    if not destGUID then
        return
    end

    state.improvedGarrotes[destGUID] = nil
    Print("IGT: Garrote removed from " .. tostring(destName or destGUID))
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
            local hasImprovedGarrote = HasImprovedGarroteBuff()
            local inCrimsonTempestWindow = CrimsonTempestWindowIsActive()

            -- Crimson Tempest spreading is inferential: the combat log does not
            -- explicitly say a spread Garrote inherited Improved Garrote. During
            -- the short post-cast window, applications by the player are treated
            -- as improved only if an improved Garrote was already tracked.
            MarkGarrote(
                destGUID,
                destName,
                hasImprovedGarrote or inCrimsonTempestWindow,
                hasImprovedGarrote and "Improved Garrote aura" or "Crimson Tempest spread inference"
            )
        elseif subevent == "SPELL_AURA_REMOVED" then
            RemoveGarrote(destGUID, destName)
        end
    elseif spellID == CRIMSON_TEMPEST_SPELL_ID and subevent == "SPELL_CAST_SUCCESS" then
        if next(state.improvedGarrotes) ~= nil then
            state.crimsonTempestWindowExpires = GetTime() + CRIMSON_TEMPEST_SPREAD_WINDOW_SECONDS
            Print("IGT: Crimson Tempest spread window active")
        end
    end
end

local function CreateDisplay()
    displayFrame = CreateFrame("Frame", "ImprovedGarroteTrackerDisplay", UIParent)
    displayFrame:SetSize(220, 32)
    displayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)

    displayText = displayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    displayText:SetPoint("CENTER", displayFrame, "CENTER")
    displayText:SetTextColor(0.7, 1.0, 0.7)
    displayText:SetText("")
end

local function OnEvent(_, event, arg1, arg2)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        PrintBlockedAction(event, arg1, arg2)
        return
    end

    if event == "PLAYER_LOGIN" then
        state.playerGUID = UnitGUID("player")
        CreateDisplay()
        Print("ImprovedGarroteTracker loaded safely.")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLogEvent()
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateDisplay()
    end
end

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
f:RegisterEvent("ADDON_ACTION_BLOCKED")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:SetScript("OnEvent", OnEvent)
