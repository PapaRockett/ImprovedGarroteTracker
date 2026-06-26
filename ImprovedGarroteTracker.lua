-- ImprovedGarroteTracker
-- Passive Retail/Midnight tracker for Garrote applications made during the
-- Improved Garrote buff/window. This addon intentionally does not create secure
-- action buttons, call protected action APIs, or modify Blizzard protected UI.

local ADDON_NAME = ...
local IGT = _G[ADDON_NAME] or {}
_G[ADDON_NAME] = IGT

local GARROTE_SPELL_ID = 703
local IMPROVED_GARROTE_SPELL_ID = 392403
local CRIMSON_TEMPEST_SPELL_ID = 1247227

local DEFAULTS = {
    debug = false,
    locked = false,
    x = 0,
    y = 120,
    crimsonWindow = 0.5,
    nameplates = false,
}

local state = {
    playerGUID = nil,
    improvedGarrotes = {},
    crimsonWindowExpires = 0,
    nameplateUnits = {},
    nameplateOverlays = {},
    inCombat = false,
}

IGT.state = state

local eventFrame = CreateFrame("Frame")
IGT.eventFrame = eventFrame

local displayFrame
local displayText

local function CopyDefaults(target, defaults)
    target = target or {}
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = value
        end
    end
    return target
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fff7fIGT:|r " .. tostring(message))
end

local function DebugPrint(message)
    if IGTDB and IGTDB.debug then
        Print(message)
    end
end

local function HasImprovedGarroteBuff()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(IMPROVED_GARROTE_SPELL_ID) ~= nil
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(IMPROVED_GARROTE_SPELL_ID)
        if spellName then
            return C_UnitAuras.GetAuraDataBySpellName("player", spellName, "HELPFUL") ~= nil
        end
    end

    return false
end

local function IsCrimsonWindowActive()
    return GetTime() <= (state.crimsonWindowExpires or 0)
end

local function TargetIsImproved()
    local guid = UnitGUID("target")
    return guid, guid and state.improvedGarrotes[guid] or nil
end

local function UpdateDisplay()
    if not displayFrame then
        return
    end

    local _, info = TargetIsImproved()
    if info then
        displayFrame:Show()
    else
        displayFrame:Hide()
    end
end

local function UpdateOneNameplate(unitToken)
    if not unitToken or not state.nameplateUnits[unitToken] then
        return
    end

    local overlay = state.nameplateOverlays[unitToken]
    if not overlay then
        return
    end

    local guid = UnitGUID(unitToken)
    if guid and state.improvedGarrotes[guid] then
        overlay:Show()
    else
        overlay:Hide()
    end
end

local function UpdateNameplates()
    if not IGTDB or not IGTDB.nameplates then
        return
    end

    for unitToken in pairs(state.nameplateUnits) do
        UpdateOneNameplate(unitToken)
    end
end

local function UpdateAllDisplays()
    UpdateDisplay()
    UpdateNameplates()
end

local function MarkGarrote(destGUID, destName, improved, reason)
    if not destGUID then
        return
    end

    if improved then
        state.improvedGarrotes[destGUID] = {
            name = destName,
            markedAt = GetTime(),
            reason = reason,
        }
        DebugPrint("Garrote marked improved: " .. (destName or destGUID) .. " (" .. reason .. ")")
    else
        state.improvedGarrotes[destGUID] = nil
        DebugPrint("Garrote marked normal: " .. (destName or destGUID))
    end

    UpdateAllDisplays()
end

local function RemoveGarrote(destGUID, destName)
    if not destGUID then
        return
    end

    if state.improvedGarrotes[destGUID] then
        state.improvedGarrotes[destGUID] = nil
        DebugPrint("Garrote removed: " .. (destName or destGUID))
        UpdateAllDisplays()
    end
end

local function HandleCombatLog()
    local timestamp, subevent, _, sourceGUID, _, _, _, destGUID, destName, _, _, spellId = CombatLogGetCurrentEventInfo()
    if not state.playerGUID then
        state.playerGUID = UnitGUID("player")
    end

    if sourceGUID ~= state.playerGUID then
        return
    end

    if spellId == GARROTE_SPELL_ID then
        if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
            local hasBuff = HasImprovedGarroteBuff()
            local crimson = IsCrimsonWindowActive()
            MarkGarrote(destGUID, destName, hasBuff or crimson, hasBuff and "Improved Garrote buff" or "Crimson Tempest window")
        elseif subevent == "SPELL_AURA_REMOVED" then
            RemoveGarrote(destGUID, destName)
        end
    elseif spellId == CRIMSON_TEMPEST_SPELL_ID and subevent == "SPELL_CAST_SUCCESS" then
        local hasTrackedImproved = next(state.improvedGarrotes) ~= nil
        if hasTrackedImproved then
            state.crimsonWindowExpires = GetTime() + (IGTDB.crimsonWindow or DEFAULTS.crimsonWindow)
            DebugPrint("Crimson Tempest spread window active for " .. tostring(IGTDB.crimsonWindow or DEFAULTS.crimsonWindow) .. " seconds")
        end
    end

    -- timestamp is intentionally unpacked above for correct Retail combat-log
    -- payload parsing; GetTime() is used for local display windows.
    local _ = timestamp
end

local function SavePosition()
    if not displayFrame or not IGTDB then
        return
    end

    local point, _, _, xOfs, yOfs = displayFrame:GetPoint(1)
    if point then
        IGTDB.x = xOfs or IGTDB.x
        IGTDB.y = yOfs or IGTDB.y
    end
end

local function SetLocked(locked)
    IGTDB.locked = locked and true or false
    displayFrame:SetMovable(not IGTDB.locked)
    displayFrame:EnableMouse(not IGTDB.locked)
    if IGTDB.locked then
        Print("locked")
    else
        Print("unlocked; drag the label to move it")
    end
end

local function CreateDisplay()
    displayFrame = CreateFrame("Frame", "ImprovedGarroteTrackerFrame", UIParent)
    displayFrame:SetSize(180, 28)
    displayFrame:SetPoint("CENTER", UIParent, "CENTER", IGTDB.x, IGTDB.y)
    displayFrame:SetFrameStrata("LOW")
    displayFrame:SetClampedToScreen(true)
    displayFrame:SetMovable(not IGTDB.locked)
    displayFrame:EnableMouse(not IGTDB.locked)
    displayFrame:RegisterForDrag("LeftButton")
    displayFrame:SetScript("OnDragStart", function(self)
        if not IGTDB.locked then
            self:StartMoving()
        end
    end)
    displayFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    displayText = displayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    displayText:SetPoint("CENTER")
    displayText:SetText("Improved Garrote")
    displayText:SetTextColor(0.7, 1.0, 0.7)

    displayFrame:Hide()
    IGT.displayFrame = displayFrame
end

local function CreateNameplateOverlay(unitToken)
    if not IGTDB.nameplates or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
        return
    end

    local nameplate = C_NamePlate.GetNamePlateForUnit(unitToken)
    if not nameplate or state.nameplateOverlays[unitToken] then
        return
    end

    local overlay = CreateFrame("Frame", nil, nameplate)
    overlay:SetSize(28, 18)
    overlay:SetPoint("TOP", nameplate, "TOP", 0, -8)
    overlay:SetFrameStrata("MEDIUM")

    local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText("IG")
    text:SetTextColor(0.7, 1.0, 0.7)
    overlay.text = text
    overlay:Hide()

    state.nameplateOverlays[unitToken] = overlay
    UpdateOneNameplate(unitToken)
end

local function RemoveNameplateOverlay(unitToken)
    local overlay = state.nameplateOverlays[unitToken]
    if overlay then
        overlay:Hide()
        overlay:SetParent(nil)
        state.nameplateOverlays[unitToken] = nil
    end
    state.nameplateUnits[unitToken] = nil
end

local function PrintStatus()
    local guid, info = TargetIsImproved()
    Print("target GUID: " .. tostring(guid) .. "; improved: " .. tostring(info ~= nil))
    if info then
        Print("marked at: " .. tostring(info.markedAt) .. "; reason: " .. tostring(info.reason))
    end
end

local function ResetState()
    wipe(state.improvedGarrotes)
    state.crimsonWindowExpires = 0
    if displayFrame then
        displayFrame:ClearAllPoints()
        displayFrame:SetPoint("CENTER", UIParent, "CENTER", DEFAULTS.x, DEFAULTS.y)
    end
    IGTDB.x = DEFAULTS.x
    IGTDB.y = DEFAULTS.y
    UpdateAllDisplays()
    Print("reset")
end

local function HandleSlash(input)
    local command = string.lower(strtrim(input or ""))
    if command == "status" or command == "" then
        PrintStatus()
    elseif command == "lock" then
        SetLocked(true)
    elseif command == "unlock" then
        SetLocked(false)
    elseif command == "reset" then
        ResetState()
    elseif command == "debug on" then
        IGTDB.debug = true
        Print("debug on")
    elseif command == "debug off" then
        IGTDB.debug = false
        Print("debug off")
    else
        Print("commands: /igt status, /igt lock, /igt unlock, /igt reset, /igt debug on, /igt debug off")
    end
end

local function OnEvent(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        IGTDB = CopyDefaults(IGTDB, DEFAULTS)
        state.playerGUID = UnitGUID("player")
        CreateDisplay()
        SlashCmdList.IMPROVEDGARROTETRACKER = HandleSlash
        SLASH_IMPROVEDGARROTETRACKER1 = "/igt"
        eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        UpdateAllDisplays()
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateDisplay()
    elseif event == "PLAYER_REGEN_DISABLED" then
        state.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        state.inCombat = false
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        state.nameplateUnits[arg1] = true
        CreateNameplateOverlay(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        RemoveNameplateOverlay(arg1)
    end
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", OnEvent)
