--[[ *** DataStore_AscensionRE ***
    Written by: Nihilianth @github.com
    31 March 2021
    Implementation of this addon is based on DataStore_Crafts addon
]]

if not DataStore then return end

local addonName = "DataStore_AscensionRE"

_G[addonName] = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0", "AceTimer-3.0")
local binser = binser or require("binser_wrapper_base64_client")
local TLibCompress = TLibCompress or require("LibCompress")
local addon = _G[addonName]

local THIS_ACCOUNT = "Default"
local commPrefix = "DS_AscRE"

local AscensionInit = false
local AscRESpellIds = {}
local collectionTypeStr = {"Enchant", "Tome"}

local collectionInitMsgName = "ASC_COLLECTION_INIT"
local collectionUpdateMsgName = "ASC_COLLECTION_UPDATE"
local collectionREUnlockedMsgName = "ASC_COLLECTION_RE_UNLOCKED"
local collectionGuildUpdateMsgName = "ASC_GUILD_COLLECTION_UPDATE"
-- local collectionTomeUnlockedMsgName = "ASC_COLLECTION_TOME_UNLOCKED"

local MSG_SEND_LOGIN		= 1
local MSG_LOGIN_REPLY		= 2
local MSG_SEND_ENCHANTS 	= 3
ASCActiveCharacters = {}


local AddonDB_Defaults = {
    global = {
        Options = {
            BroadcastREs = 1,
            AnnounceInit = 1
        },
        Characters = {
            ['*'] = {
                lastUpdate = nil,
                Version = nil,
                NumKnownEnchants = 0,
                KnownEnchants = {},
            }
        },
        Guilds = {
            ['*'] = {
                Members = {
                    ['*'] = {
                        lastUpdate = nil,
                        Version = nil,
                        NumKnownEnchants = 0,
                        KnownEnchants = {},
                    }
                }
            }
        }

    }
}


-- *** Utility functions Generic ***

local function SendOnlineInfo()
    if onlineCnt then
        addon:Print(format("Online guild members with RE sync: %u.", onlineCnt))
    end
end

local function GetOption(option)
	return addon.db.global.Options[option]
end

local function GetCurrentGuild()
	local guild = GetGuildInfo("player")
	if guild then 
		local key = format("%s.%s.%s", THIS_ACCOUNT, GetRealmName(), guild)
		return addon.db.global.Guilds[key]
	end
end

local function SaveAddonVersion(sender, version)
	local thisGuild = GetCurrentGuild()
	if thisGuild and sender and version then
		thisGuild.Members[sender].Version = version
	end
end

local function GetBuildVersion()
	local _, version = GetBuildInfo()
	return tonumber(version)
end

local function GetAddonVersion()
    local version = GetAddOnMetadata(addonName, "Version")
    --addon:Print("curVersion: "..version)
    return version
end

local function SaveVersion(sender, version)
	local thisGuild = GetCurrentGuild()
	if thisGuild and sender and version then
		thisGuild.Members[sender].Version = version
	end
end

local function GuildBroadcast(messageType, ...)
	local serializedData = addon:Serialize(messageType, ...)
	addon:SendCommMessage(commPrefix, serializedData, "GUILD")
end

local function GuildWhisper(player, messageType, ...)
	if DataStore:IsGuildMemberOnline(player) then
		local serializedData = addon:Serialize(messageType, ...)
		addon:SendCommMessage(commPrefix, serializedData, "WHISPER", player)
	end
end

-- *** End Utility Functions Generic ***

-- *** Utility Functions Ascension ***

-- ** Active Char Handling **
function ParseCharGossip(...)
    for i = 1, select("#", ...), 2 do
      line = select(i, ...)
      if line ~= nil and type(line) == "string" then
        name = line:match("%S+") 
        if name ~= nil and type(name) == "string" then
          if string.find(select(i, ...), "Active") ~= nil then
            table.insert(ASCActiveCharacters, name)
          end
        end
      end
    end
end
  
function AscGetActiveCharacters()
  ASCActiveCharacters = {}

  GossipFrame:SetScript("OnUpdate", function()
    GossipFrame:SetScript("OnUpdate", nil)
    ParseCharGossip(GetGossipOptions())
    addon:ScheduleTimer(CloseGossip, 0.1)
    -- GossipFrame:Hide() -- this bugs the esc button
  end)

  SendChatMessage(".char list", "WHISPER", "Common", UnitName("player"));
end

local function CleanupInactiveCharacters()
    if #ASCActiveCharacters == 0 then
        CloseGossip()
        --addon:Print("Inactive Players not synced, retrying")
        AscGetActiveCharacters()
        addon:ScheduleTimer(CleanupInactiveCharacters, 2)
        return
    end
    
	for name, _ in pairs(DataStore:GetCharacters()) do
		--addon:DeleteCharacter(name, realm, account)
        found = false
        for _, charName in pairs(ASCActiveCharacters) do
            if name == charName then
                found = true
                break
            end
        end

        if found == false then
            addon:Print("Removing inactive character: "..name)
            DataStore:DeleteCharacter(name, realm, account)
        end
	end
end

-- ** End Active Char Handling **

local function SaveEnchants(sender, alt, data)
    local thisGuild = GetCurrentGuild()
    if thisGuild and sender then
        local addonVer = thisGuild.Members[sender].Version
        local member_alt = thisGuild.Members[alt]
        --addon:Print("Saving enchant from "..sender)
        member_alt.Version = addonVer
        --addon:Print(format("Got data for %s: %u", alt, #data))
        member_alt.NumKnownEnchants = #data
        member_alt.KnownEnchants = data
        member_alt.lastUpdate = time()
    end
    addon:SendMessage(collectionGuildUpdateMsgName, sender, alt, data)
end

local enchantQueue
local enchantTimer

function GetEnchantQueue()
    return enchantQueue
end

local function SendEnchantQueue()
    if #enchantQueue == 0 then
        --addon:Print("Sent all queued enchants")
        addon:CancelTimer(enchantTimer)
        enchantTimer = nil
        return
    end
    --addon:Print(format("SendEnchantQueue: %d remaining", #enchantQueue))

    local queueEntry = enchantQueue[#enchantQueue]
    local alt = queueEntry[1]
    local recipient = queueEntry[2]
    local knownEnchants = queueEntry[3]

    if recipient then
        --addon:Print(format("Sending %u enchants for alt %s", #knownEnchants, alt))
        GuildWhisper(recipient, MSG_SEND_ENCHANTS, alt, knownEnchants)
    else
        --addon:Print(format("Broadcasting %u enchants for alt %s", #knownEnchants, alt))
        GuildBroadcast(MSG_SEND_ENCHANTS, alt, knownEnchants)
    end

    table.remove(enchantQueue)
end

local function SendEnchantsWithAlts(alts, recipient)
    --if GetOption("BroadcastREs" == 0) then
    --    return
    --end

    enchantQueue = enchantQueue or {}

    --[[
    if recipient then
        addon:Print("sending alt enchants to : "..recipient)
    else
        addon:Print("sending alt enchants")
    end
    ]]--

    if AscensionInit == true then
        local myself = DataStore:GetCharacter()
        local _, _, nameStripped = strsplit(".", myself)
        --addon:Print("sending own enchants: "..#addon.ThisCharacter.KnownEnchants)
        table.insert(enchantQueue, {nameStripped, recipient, addon.ThisCharacter.KnownEnchants})
    else
        --addon:Print("Sending data bafore init")
    end

    if (strlen(alts) > 0) then
        for _, name in pairs({strsplit("|",alts)}) do
            character = DataStore:GetCharacter(name)
            if character then
                --addon:Print("Sending data for alt: "..name.." - "..#addon.db.global.Characters[character].KnownEnchants)
                table.insert(enchantQueue, {name, recipient, addon.db.global.Characters[character].KnownEnchants})
            end
        end
    else
        --addon:Print("sent no alts")
    end

    enchantTimer = enchantTimer or addon:ScheduleRepeatingTimer(SendEnchantQueue, 0.5) -- Send queued enchants every 0.5 seconds
end

-- verify this
local function OnGuildAltsReceived(self, sender, alts)
    if sender == UnitName("player") then				-- if I receive my own list of alts in the same guild, same realm, same account..
        -- addon:Print("Guild alts received from myself")
		--GuildBroadcast(MSG_SEND_LOGIN, GetAddonVersion())
		--addon:ScheduleTimer(SendEnchantsWithAlts, 5, alts)	-- broadcast my crafts to the guild 5 seconds later, to decrease the load at startup
	else
        --addon:Print("Guild alts received from: "..sender)
    end
end

local onlineCnt = 0
local GuildCommCallbacks = {
    [MSG_SEND_LOGIN] = function(sender, version)
        local player = UnitName("player")
        if (sender ~= player) then
            --addon:Print("Got MSG_SEND_LOGIN from "..sender)
            GuildWhisper(sender, MSG_LOGIN_REPLY, GetAddonVersion())
            -- send all data when guildie logs in
            local alts = DataStore:GetGuildMemberAlts(player)
            if alts then
                SendEnchantsWithAlts(alts, sender)
            else
                SendEnchantsWithAlts("", sender)
                --addon:Print("no alts found")
            end
        end
        SaveAddonVersion(sender, version)
    end,
    [MSG_LOGIN_REPLY] = function(sender, version)
        --addon:Print("Got MSG_LOGIN_REPLY from "..sender.." version: "..version)
        onlineCnt = onlineCnt + 1
        SaveAddonVersion(sender, version)
    end,
    [MSG_SEND_ENCHANTS] = function(sender, alt, data)
        local player = UnitName("player")
        if (sender ~= player) then
            --addon:Print("Got MSG_SEND_ENCHANTS from "..sender.."for alt: "..alt.." size: "..#data)
            SaveEnchants(sender, alt, data)
        else
            --addon:Print("Got MSG_SEND_ENCHANTS from self: "..sender.."for alt: "..alt.." size: "..#data)
        end
    end
}

-- *** End Utility Functions Ascension ***

-- *** Public Functions Impl ***
-- FIXME: old
local function _GetKnownEnchants()
    if AscensionInit == false then return nil end

    return addon.ThisCharacter.KnownEnchants
end

local function IsREKnownByPlayer(entry, knownList)
    for _, spellId in pairs(knownList) do
        if entry == spellId  then return true end
    end
    return false
end

local function _GetCharactersWithKnownList()
    local altList = {}
    for name, id in pairs(addon.Characters) do
        table.insert(altList, name)
    end
    return altList
end

local function _GetCharacterREs(name)
    local charKey = format("%s.%s.%s", THIS_ACCOUNT, GetRealmName(), name)
    
    for key, data in pairs(addon.Characters) do
        if key:lower() == charKey:lower() then
            return data.KnownEnchants
        end
    end
    return nil
end

local function _GetGuildieREs(name)
    
    local thisGuild = GetCurrentGuild()
    if not thisGuild then return {} end

    for gname, data in pairs(thisGuild.Members) do
        if gname:lower() == name:lower() then
            --addon:Print(format("Found guildie: %s %s", gname, #data.KnownEnchants))
            return data.KnownEnchants
        end
    end

    return nil
end

-- returns alt names on the same realm that have the RE (cross-faction, cross-guild)
local function _GetCharactersWithRE(entry)
    local altsWithRE = {}
    for characterName, characterKey in pairs(DataStore:GetCharacters()) do
        
        local character = addon.db.global.Characters[characterKey]
        --print(characterName, characterKey, #character.KnownEnchants)
        if #character.KnownEnchants > 0 then
            if IsREKnownByPlayer(entry, character.KnownEnchants) then
                --local _,_,charName = strsplit(".", name)
                table.insert(altsWithRE, characterName)
            end
        end
    end

    return altsWithRE
end

-- returns guild member's character names
local function _GetGuildiesWithRE(entry)
    local guildiesWithRE = {}

    local thisGuild = GetCurrentGuild()
    if not thisGuild then return {} end

    for name, data in pairs(thisGuild.Members) do
        if IsREKnownByPlayer(entry, data.KnownEnchants) then
            table.insert(guildiesWithRE, name)
        end
    end

    return guildiesWithRE;
end

local PublicMethods = {
    GetKnownEnchants = _GetKnownEnchants,
    GetCharactersWithRE = _GetCharactersWithRE,
    GetGuildiesWithRE = _GetGuildiesWithRE,
    GetCharacterREs = _GetCharacterREs,
    GetGuildieREs = _GetGuildieREs,
    GetCharactersWithKnownList = _GetCharactersWithKnownList,
}
-- *** End Public Functions Impl ***

--- *** AddOns\AscensionUI\MysticEnchant\MysticEnchant.lua ***

-- known = false -> unknown only
local function BuildKnownList(known, onlyID)
    local KnownEnchantCount = 0
    local list = {}

    for i , v in pairs(AscensionUI.REList) do
        if not v.known then
            v.known = IsReforgeEnchantmentKnown(i)
        end
        if v.known then
            KnownEnchantCount = KnownEnchantCount + 1
        end
        if (v.known and known) or (not known and not v.known) then
            if onlyID then
                table.insert(list, v.enchantID)
            else
                table.insert(list, v)
            end
        end
    end

    return list, KnownEnchantCount
end

-- Load Data from ascension
local function InitAscensionData()
    local knownList, knownListCnt = BuildKnownList(true, true)
    -- ChatThrottleLib.MAX_CPS = 10000
    --addon:Print("Setting known list for char "..UnitName("player").." size: "..#knownList)
    addon.ThisCharacter.NumKnownEnchants = knownListCnt
    addon.ThisCharacter.KnownEnchants = knownList
    addon.ThisCharacter.lastUpdate = time()
    addon.ThisCharacter.Version = GetAddonVersion()
    -- addon:SendMessage("ASC_COLLECTION_INIT", knownList)
    addon:SendMessage("ASC_COLLECTION_UPDATE", knownList, AscensionInit)
    AscensionInit = true
    GuildBroadcast(MSG_SEND_LOGIN, GetAddonVersion())
    local alts = DataStore:GetGuildMemberAlts(UnitName("player"))
    if alts then
        addon:ScheduleTimer(SendEnchantsWithAlts, 2, alts)
    else
        addon:ScheduleTimer(SendEnchantsWithAlts, 2, "")
        --addon:Print("no alts found")
    end
    addon:ScheduleTimer(SendOnlineInfo, 10)
    --SendEnchantsWithAlts("") -- send own enchants
end

-- Handle Ascension event
-- COMMENTATOR_SKIRMISH_QUEUE_REQUEST
--      ASCENSION_REFORGE_ENCHANTMENT_LEARNED
--          enchantID
function addon:COMMENTATOR_SKIRMISH_QUEUE_REQUEST(event, subevent, data ,...)
    -- addon:Print(string.format("Custom ASC Event %s", subevent))
    if subevent == "ASCENSION_REFORGE_ENCHANTMENT_LEARNED" then
        --MysticEnchant checks for RE validity, prints error

        RE = GetREData(data)
        if RE.enchantID ~= 0 then
            --addon:Print("enchant unlocked")
            table.insert(addon.ThisCharacter.KnownEnchants, RE.enchantID)
            addon.ThisCharacter.NumKnownEnchants = #addon.ThisCharacter.KnownEnchants
            -- Notify other addons
            addon:SendMessage("ASC_COLLECTION_RE_UNLOCKED", RE.enchantID)
            addon:SendMessage("ASC_COLLECTION_UPDATE", addon.ThisCharacter.KnownEnchants, AscensionInit)
            SendEnchantsWithAlts("")
        end
    
    end
end

-- *** WOW Events ***

function addon:OnInitialize()
    addon:Print("OnInitialize")
	addon.db = LibStub("AceDB-3.0"):New(addonName .. "DB", AddonDB_Defaults)
	DataStore:RegisterModule(addonName, addon, PublicMethods)
    DataStore:SetGuildCommCallbacks(commPrefix, GuildCommCallbacks)

    addon:RegisterMessage("DATASTORE_GUILD_ALTS_RECEIVED", OnGuildAltsReceived)
    addon:RegisterComm(commPrefix, DataStore:GetGuildCommHandler())

    AscGetActiveCharacters()
end

function addon:OnEnable()
    addon:Print("OnEnable")
    addon:ScheduleTimer(CleanupInactiveCharacters, 1)
    addon:ScheduleTimer(InitAscensionData, 5)
    addon:RegisterEvent("COMMENTATOR_SKIRMISH_QUEUE_REQUEST")
    -- TODO: addon:SetupOptions()
end

function addon:OnDisable()
    addon:UnregisterEvent("COMMENTATOR_SKIRMISH_QUEUE_REQUEST")
end

