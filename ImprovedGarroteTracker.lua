-- ImprovedGarroteTracker
-- Retail WoW API review notes:
-- * Retail aura queries should prefer C_UnitAuras aura-data tables over legacy
--   positional UnitAura/UnitDebuff return values. Positional aura returns have
--   changed across client generations and are easy to parse incorrectly.
-- * COMBAT_LOG_EVENT_UNFILTERED no longer passes its payload as event handler
--   varargs; call CombatLogGetCurrentEventInfo() inside the handler and unpack
--   the documented prefix before reading spell fields.
-- * If Blizzard changes aura helper availability again, this addon fails soft:
--   combat-log tracking remains available, and aura scanning simply returns nil.

local ADDON_NAME = ...
local IGT = _G[ADDON_NAME] or {}
_G[ADDON_NAME] = IGT

local GARROTE_SPELL_ID = 703
local PLAYER_FILTER = "HARMFUL|PLAYER"

local frame = CreateFrame("Frame")
IGT.frame = frame
IGT.active = IGT.active or {}

local function IsPlayerGarroteAura(aura)
    if not aura or aura.spellId ~= GARROTE_SPELL_ID then
        return false
    end

    -- Retail auraData includes isFromPlayerOrPlayerPet for this exact use case.
    -- Keep sourceUnit as a conservative fallback because some PTR/build-specific
    -- aura tables have differed while the C_UnitAuras namespace was settling.
    return aura.isFromPlayerOrPlayerPet or aura.sourceUnit == "player" or aura.sourceUnit == "pet"
end

local function FindPlayerGarrote(unit)
    if not unit or not UnitExists(unit) or not C_UnitAuras then
        return nil
    end

    if C_UnitAuras.GetAuraDataBySpellName then
        local aura = C_UnitAuras.GetAuraDataBySpellName(unit, (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(GARROTE_SPELL_ID)) or "Garrote", PLAYER_FILTER)
        if IsPlayerGarroteAura(aura) then
            return aura
        end
    end

    if C_UnitAuras.GetAuraDataByIndex then
        local index = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, PLAYER_FILTER)
            if not aura then
                break
            end
            if IsPlayerGarroteAura(aura) then
                return aura
            end
            index = index + 1
        end
    end

    return nil
end

local function UpsertAuraFromAuraData(unit)
    local guid = UnitGUID(unit)
    if not guid then
        return
    end

    local aura = FindPlayerGarrote(unit)
    if aura then
        IGT.active[guid] = {
            applications = aura.applications or 0,
            duration = aura.duration or 0,
            expirationTime = aura.expirationTime or 0,
            name = aura.name,
            source = "aura",
            updated = GetTime(),
        }
    else
        IGT.active[guid] = nil
    end
end

local function HandleCombatLog()
    local timestamp, subevent, _, sourceGUID, _, _, _, destGUID, destName, _, _, spellId = CombatLogGetCurrentEventInfo()
    if sourceGUID ~= UnitGUID("player") or spellId ~= GARROTE_SPELL_ID or not destGUID then
        return
    end

    if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
        -- The combat log is authoritative that our Garrote exists, but it does
        -- not include expiration time. Refresh visible units through C_UnitAuras;
        -- otherwise keep a conservative record with timestamp-only data.
        IGT.active[destGUID] = IGT.active[destGUID] or {}
        IGT.active[destGUID].name = destName
        IGT.active[destGUID].source = "combatlog"
        IGT.active[destGUID].updated = timestamp

        if UnitGUID("target") == destGUID then
            UpsertAuraFromAuraData("target")
        end
    elseif subevent == "SPELL_AURA_REMOVED" then
        IGT.active[destGUID] = nil
    end
end

local function OnEvent(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
        frame:RegisterEvent("UNIT_AURA")
        frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        UpsertAuraFromAuraData("target")
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpsertAuraFromAuraData("target")
    elseif event == "UNIT_AURA" then
        if arg1 == "target" then
            UpsertAuraFromAuraData("target")
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog()
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", OnEvent)

function IGT.GetTargetGarrote()
    UpsertAuraFromAuraData("target")
    local guid = UnitGUID("target")
    return guid and IGT.active[guid] or nil
end
