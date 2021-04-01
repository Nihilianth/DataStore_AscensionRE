--[[ *** DataStore_AscensionRE ***
    Written by: Nihilianth @github.com
    31 March 2021
    Implementation of this addon is based on DataStore_Crafts addon
]]

if not DataStore then return end

local addonName = "DataStore_AscensionRE"

_G[addonName] = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")

local addon = _G[addonName]

local THIS_ACCOUNT = "Default"
local CommPrefix = "DS_AscRE"

local AscensionInit = false
AscRESpellIds = {}
local collectionTypeStr = {"Enchant", "Tome"}

local collectionUpdateMsgName = "ASC_COLLECTION_UPDATE"
local collectionREUnlockedMsgName = "ASC_COLLECTION_RE_UNLOCKED"
local collectionTomeUnlockedMsgName = "ASC_COLLECTION_TOME_UNLOCKED"

local AddonDB_Defaults = {
    global = {
        Options = {
            BroadcastREs = 1
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

local PublicMethods = {

}

-- *** Utility functions Generic ***

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

local function GetBuildVersion()
	local _, version = GetBuildInfo()
	return tonumber(version)
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

--[[ * True Spell IDs *
    The CollectionStore contains some variant of skill IDs
    most of which match with spell IDs. For others true spell IDs
    has to be retrieved to ensure proper use for (tooltip and other) addon functionality
-- ]]
local function GetRealRESpellIds()
    local reList = CollectionsFrame.EnchantList
    local spellIds = {}

    for reId, misc in pairs(reList) do
        local spellId = reList[reId][1][2]

        table.insert(spellIds, spellId)
    end

    return spellIds
end

-- Parse Server Message containing known Enchants using Smallfolk (used by Ascension addons)
local function ParseKnownEnchantsList(message)
    -- TODO: Large server messages are split. 
    -- Ingame tests showed no issues for players with large enchant collections
    -- Further tests are needed to determine if additional processing is required
    -- TODO: Additional error handling if required

    local reList = CollectionsFrame.EnchantList
    local knownList = {}

    local recvTable = Smallfolk.loads(string.sub(message, 3))
    if not recvTable or type(recvTable) ~= 'table' then
        addon:Print("Error: received invalid enchant data with size: "..#msg)
        return
    end

    for id, enchant_id in pairs(recvTable[1][4]) do
        local spellId = reList[enchant_id][1][2]
        if not spellId then
            addon:Print("Unknown enchant with id: "..enchant_id.." skipped.")
        else
            table.insert(knownList, spellId)
        end
    end

    charEnchants = knownList
    addon:SendMessage(collectionUpdatedMsgName, knownList, AscensionInit)
end

-- Parse server message received after unlocking a new RE
local function ParseNewEnchant(message)
    addon:Print("RE Toolkit: Got FillCollectionByEnchant")
    local reList = CollectionsFrame.EnchantList

    local recvTable = Smallfolk.loads(string.sub(message, 3))
    if not recvTable or type(recvTable) ~= 'table' then
        addon:Print("Received invalid new enchant message. Size: "..#message)
        addon:Print(message)
    end
    
    local entry = reList[recvTable[1][4]][1][2]
    if entry then 
        addon:SendMessage(collectionREUnlockedMsgName, entry)
    else
        addon:Print("Received unknown New Enchant!")
    end
end

-- *** End Utility Functions Ascension ***

-- *** WOW Events ***

function addon:OnInitialize()
	addon.db = LibStub("AceDB-3.0"):New(addonName .. "DB", AddonDB_Defaults)
	DataStore:RegisterModule(addonName, addon, PublicMethods)
	-- DataStore:SetGuildCommCallbacks(commPrefix, GuildCommCallbacks)
end

function addon:OnEnable()
    local charEnchants = addon.ThisCharacter.KnownEnchants

    addon:RegisterEvent("CHAT_MSG_ADDON")
end

function addon:OnDisable()
    addon:UnregisterEvent("CHAT_MSG_ADDON")
end

function addon:CHAT_MSG_ADDON(event, prefix, message, channel, sender)
    if not prefix or not prefix:find("SAIO") then return end
    if not message then return end

    -- Provided after login as a responce to requests from client addons
    -- Data is not present on PLAYER_ALIVE
    if message:find("GetKnownEnchantsList") then
        addon:Print("Received GetKnownEnchantsList")
        charEnchants = {}

        if AscensionInit == false then
            AscRESpellIds = GetRealRESpellIds()
            ParseKnownEnchantsList(message)
            AscensionInit = true
        end

        ParseKnownEnchantsList(message)
        
        addon:Print("Parsed GetKnownEnchantsList")
    elseif message:find("FillCollectionByEnchant") then
        addon:Print("Unlocked Enchant")
    end
end