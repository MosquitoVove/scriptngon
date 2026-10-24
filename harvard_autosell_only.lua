--[[
  Harvard Labs - Auto Sell only
  Trích từ script gốc: giao diện (UIKit + khung cửa sổ), logic auto sell và trang "Auto Sell".
  Mọi tính năng khác (farm, party, webhook, visuals...) đã được bỏ.
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end
if type(_G.HarvardAutoSellDestroy) == "function" then
    pcall(_G.HarvardAutoSellDestroy)
    task.wait(0.1)
end

local argumentHelpers = { [127] = table.pack, [1] = unpack, [32] = table.move }
argumentHelpers.jB = function(helpers, values)
    return helpers[1](values, 1, values.n)
end
argumentHelpers.YB = function(helpers, destination, offset, ...)
    local values = helpers[127](...)
    helpers[32](values, 1, values.n, offset + 1, destination)
end
local vmHelpers = argumentHelpers
local components = {}
local context = {}

local players = game:GetService("Players")
local localPlayer = players.LocalPlayer
while not localPlayer do
    task.wait(0.1)
    localPlayer = players.LocalPlayer
end
local contextWorkspace = game:GetService("Workspace")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local httpService = game:GetService("HttpService")

----------------------------------------------------------------------
-- Config + runtime state (rút gọn từ coreSettings)
----------------------------------------------------------------------
local config = {
    autoSell = false,
    sellInterval = 60,
    sellAfterGames = 10,
    sellKeepLevel = 186,
    sellLobbyOnly = true,
    sellListMax = 40,
    sellCommon = true,
    sellUncommon = true,
    sellRare = true,
    sellEpic = true,
    sellLegendary = false,
    sellUltimate = false,
    sellKeep = {},
    menuKey = "RightShift",
    menuZ = 20,
    notifications = true,
    mobileButton = true,
}
local runtimeState = {
    farmEnabled = false,
    destroyed = false,
}

local paths = {
    root = "HarvardLabs",
    configs = "HarvardLabs/configs",
    data = "HarvardLabs/data",
    logs = "HarvardLabs/logs",
}
local function contextEnsureFolders()
    if type(makefolder) ~= "function" then
        return
    end
    for _, p in ipairs({ paths.root, paths.configs, paths.data, paths.logs }) do
        pcall(function()
            if not (type(isfolder) == "function" and isfolder(p)) then
                makefolder(p)
            end
        end)
    end
end
contextEnsureFolders()

local configFile = paths.configs .. "/autosell_" .. tostring(localPlayer.UserId) .. ".json"
local persist = {
    "autoSell", "sellInterval", "sellAfterGames", "sellKeepLevel", "sellLobbyOnly",
    "sellCommon", "sellUncommon", "sellRare", "sellEpic", "sellLegendary", "sellUltimate",
    "sellKeep", "menuKey",
}
local function contextSaveConfig()
    if type(writefile) ~= "function" then
        return
    end
    local out = {}
    for _, key in ipairs(persist) do
        out[key] = config[key]
    end
    pcall(function()
        writefile(configFile, httpService:JSONEncode(out))
    end)
end
local function contextLoadConfig()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then
        return
    end
    pcall(function()
        if not isfile(configFile) then
            return
        end
        local saved = httpService:JSONDecode(readfile(configFile))
        if type(saved) ~= "table" then
            return
        end
        for _, key in ipairs(persist) do
            if saved[key] ~= nil and type(saved[key]) == type(config[key]) then
                config[key] = saved[key]
            end
        end
    end)
    -- bán là không hoàn lại được: luôn bắt bật lại bằng tay sau mỗi lần chạy
    config.autoSell = false
end

context.CFG = config
context.RT = runtimeState
context.LocalPlayer = localPlayer
context.Workspace = contextWorkspace
context.RunService = runService
context.UserInputService = userInputService
context.ReplicatedStorage = game:GetService("ReplicatedStorage")
context.HttpService = httpService
context.PATH = paths
context.ensureFolders = contextEnsureFolders
context.saveConfig = contextSaveConfig
context.loadConfig = contextLoadConfig
context.SCRIPT_VERSION = "Auto Sell"
context.UI = {}
context.sliderConnections = {}
-- Gear, Spells & Stats không có trong bản này: không có món nào được tự bảo vệ ngoài luật của trang Auto Sell.
context.BG = {
    keepers = function()
        return {}
    end,
    beforeSale = function() end,
}
contextLoadConfig()

----------------------------------------------------------------------
-- Auto sell (nguyên bản)
----------------------------------------------------------------------
    components.inventoryAutomation = function(context)
        local config = context.CFG
        local L, inventoryAutomation =
            context.ReplicatedStorage or game:GetService("ReplicatedStorage"), {
                lastSold = 0,
                totalSold = 0,
                note = "no sale yet",
                at = 0,
            }
        context.AS = inventoryAutomation
        local dungeons, D, P, _, l =
            {
                "Abyssal Void",
                "Aquatic Temple",
                "Boss Raids (Legacy)",
                "Desert Temple",
                "Desert Temple (Legacy)",
                "Egg Island",
                "Enchanted Forest",
                "Ghastly Harbor",
                "Gilded Skies",
                "King's Castle",
                "Northern Lands",
                "Orbital Outpost",
                "Pirate Island",
                "Ready Player Two",
                "Samurai Palace",
                "Steampunk Sewers",
                "The Canals",
                "The Underworld",
                "Volcanic Chambers",
                "Winter Outpost",
                "Winter Outpost (Legacy)",
                "Yokai Peak",
            }, {
                w = "weapon",
                a = "ability",
                h = "helmet",
                c = "chest",
            }, {
                n = "",
                c = "common",
                u = "uncommon",
                r = "rare",
                e = "epic",
                l = "legendary",
                x = "ultimate",
            }, {
                p = "physical",
                s = "spell",
                m = "mage",
                w = "warrior",
                g = "guardian",
                d = "damaging",
                v = "speed",
                h = "healing",
                b = "boosting",
                f = "buffing",
            }, {
                "Abyssal Skewers|w|n|1|s",
                "Abyssal Spellscythe|w|n|1|s",
                "Abyssal Talons|w|n|1|p",
                "Abyssal Warhammers|w|n|1|p",
                "Adventurer's Staff|w|n|0|s",
                "Adventurer's Sword|w|n|0|p",
                "Agony Orbs|a|e|7|d",
                "Akuma Guardian Armor|c|n|22|g",
                "Akuma Guardian Helmet|h|n|22|g",
                "Akuma Mage Cloak|h|n|22|m",
                "Akuma Mage Robes|c|n|22|m",
                "Akuma Warrior Armor|c|n|22|w",
                "Akuma Warrior Helmet|h|n|22|w",
                "Akuma's Soulreaver|w|l|22|s",
                "Akuma's Wraithbringer|w|l|22|p",
                "Alien Guardian Armor|c|n|12|g",
                "Alien Guardian Helmet|h|n|12|g",
                "Alien Mage Armor|c|n|12|m",
                "Alien Mage Helmet|h|n|12|m",
                "Alien Warrior Armor|c|n|12|w",
                "Alien Warrior Helmet|h|n|12|w",
                "Amethyst Beams|a|e|9|d",
                "Amethyst Blast|a|e|19|d",
                "Amethyst Crescent Spellblade|w|n|15|s",
                "Amethyst Spelldagger|w|n|15|s",
                "Amethyst Spellscythe|w|n|17|s",
                "Ancestral Guardian Armor|c|n|15|g",
                "Ancestral Guardian Helmet|h|n|15|g",
                "Ancestral Mage Armor|c|n|15|m",
                "Ancestral Mage Hood|h|n|15|m",
                "Ancestral Warrior Armor|c|n|15|w",
                "Ancestral Warrior Helmet|h|n|15|w",
                "Ancient Elder Staff|w|n|18|s",
                "Ancient Lava Axe|w|n|19|s",
                "Ancient Plate Armor|c|n|21|g",
                "Ancient Plate Helmet|h|n|21|g",
                "Ancient Ruins Greatsword|w|n|3|p",
                "Angelic Plate Armor|c|n|13|m",
                "Angelic Plate Helmet|h|n|13|m",
                "Angelic Staff|w|n|13|s",
                "Apothecary Staff|w|n|10|s",
                "Apprentice Staff|w|n|5|s",
                "Aquatic Defender|w|n|2|s",
                "Aquatic Executioner|w|n|2|p",
                "Aquatic Guardian Armor|c|n|2|g",
                "Aquatic Guardian Helmet|h|n|2|g",
                "Aquatic Mage Armor|c|n|2|m",
                "Aquatic Mage Helmet|h|n|2|m",
                "Aquatic Scimitars|w|n|2|p",
                "Aquatic Smite|a|e|2|d",
                "Aquatic Spear|w|n|2|p",
                "Aquatic Warrior Armor|c|n|2|w",
                "Aquatic Warrior Helmet|h|n|2|w",
                "Arc Blast|a|e|0|d",
                "Arc Wave|a|e|0|d",
                "Arcane Amplifier|a|e|1|f",
                "Arcane Barrage|a|u|20|d",
                "Arcane Greatstaff|w|n|20|s",
                "Arcane Orb Staff|w|n|13|s",
                "Arcane Spray|a|u|4|d",
                "Arch-Mage_Crown|h|n|10|m",
                "Arch-Mage_Robes|c|n|10|m",
                "Arclight Battlestaff|w|n|10|s",
                "Arrow Barrage|a|e|16|d",
                "Arrow Rain|a|r|16|d",
                "Aura of Life|a|u|20|h",
                "Azerite Greatstaff|w|n|20|s",
                "Banished Greatsword|w|n|3|p",
                "Barbaric_Guardian_Armor|c|n|10|g",
                "Barbaric_Guardian_Helmet|h|n|10|g",
                "Barbaric_Mage_Crown|h|n|10|m",
                "Barbaric_Mage_Robes|c|n|10|m",
                "Barbaric_Warrior_Armor|c|n|10|w",
                "Barbaric_Warrior_Helmet|h|n|10|w",
                "Battle Shout|a|u|4|b",
                "Beast Cleaver|w|n|10|p",
                "Beastly_Guardian_Armor|c|n|10|g",
                "Beastly_Guardian_Helmet|h|n|10|g",
                "Beastly_Warrior_Armor|c|n|10|w",
                "Beastly_Warrior_Helmet|h|n|10|w",
                "Beastmaster Spell Scythe|w|l|10|s",
                "Beastmaster War Scythe|w|l|10|p",
                "Berserk|a|e|15|d",
                "Bioforged Cog Spellblade|w|n|3|s",
                "Bioforged Greataxe|w|n|16|p",
                "Bioforged Greatsword|w|n|16|p",
                "Bioforged Quickblade|w|n|3|p",
                "Bioforged Reinforced Slicer|w|n|16|p",
                "Blacksteel Greatsword|w|n|18|p",
                "Blade Barrage|a|e|9|d",
                "Blade Fall|a|e|19|d",
                "Blade Revolver|a|e|17|d",
                "Blade Storm|a|e|17|d",
                "Blade Throw|a|e|10|d",
                "Blazing Star|w|n|12|p",
                "Blessed Lightpost|w|n|3|s",
                "Blood Pact|a|e|1|g",
                "Bloodthirster|w|n|17|p",
                "Blue Fireball|a|c|4|d",
                "Blue Wizard Hat|h|n|5|m",
                "Blue Wizard Robes|c|n|5|m",
                "Bluefire Staff|w|n|20|s",
                "Bone Scythe|w|n|15|p",
                "Bronze Dagger|w|n|5|p",
                "Bronze Longsword|w|n|5|p",
                "Burned Guardian Armor|c|n|19|g",
                "Burned Guardian Helmet|h|n|19|g",
                "Burned Mage Armor|c|n|19|m",
                "Burned Mage Helmet|h|n|19|m",
                "Burned Warrior Armor|c|n|19|w",
                "Burned Warrior Helmet|h|n|19|w",
                "Captain's Anchor|w|n|8|p",
                "Carrot Barrage|a|r|6|d",
                "Celestial Fire Staff|w|n|10|s",
                "Chain Heal|a|r|10|h",
                "Chain Lightning|a|e|16|d",
                "Chain Phase Shock|a|n|14|d",
                "Chain Storm|a|e|22|d",
                "Chained Energy Blasts|a|r|16|d",
                "Champion's Destiny|w|l|0|p",
                "Champion's Fury|w|l|0|p",
                "Champion's Judgement|w|l|0|p",
                "Champion's Oath|w|l|0|p",
                "Chromatic Rain|a|e|16|d",
                "Cleansing Beam|a|e|1|",
                "Coldstone Axes|w|n|20|p",
                "Coldstone Blades|w|n|20|s",
                "Coldstone Cleaver|w|n|20|p",
                "Coldstone Glaive|w|n|20|p",
                "Coldstone Greatstaff|w|n|20|s",
                "Coldstone Spellscythe|w|n|20|s",
                "Coldstone Sword|w|n|20|p",
                "Commander's Guardian Armor|c|n|12|g",
                "Commander's Guardian Helmet|h|n|12|g",
                "Commander's Mage Armor|c|n|12|m",
                "Commander's Mage Helmet|h|n|12|m",
                "Commander's Warrior Armor|c|n|12|w",
                "Commander's Warrior Helmet|h|n|12|w",
                "Cracked Tooth Cleaver|w|n|8|p",
                "Crimson Kris|w|n|15|p",
                "Crimson Spellblade|w|n|20|s",
                "Crusader Armor|c|n|5|g",
                "Crusader Helmet|h|n|5|g",
                "Crystalized Greatsword|w|l|20|p",
                "Crystalline Cannon|a|e|7|d",
                "Crystalline Guardian Armor|c|n|7|g",
                "Crystalline Guardian Helmet|h|n|7|g",
                "Crystalline Mage Armor|c|n|7|m",
                "Crystalline Mage Helmet|h|n|7|m",
                "Crystalline Shard Staff|w|n|7|s",
                "Crystalline Warrior Armor|c|n|7|w",
                "Crystalline Warrior Helmet|h|n|7|w",
                "Cultist Blade|w|n|13|p",
                "Dark Ice Blades|w|n|17|p",
                "Dark Priest Staff|w|n|13|s",
                "Darkstone Greatsword|w|n|19|p",
                "Daybreak And Gildensong|w|l|9|s",
                "Demon Lord's Greatstaff|w|n|18|s",
                "Demonic Curse|a|e|12|d",
                "Demonic Greatsword|w|n|20|p",
                "Demonic Spellblade|w|n|20|s",
                "Demonic Spikes|a|r|18|d",
                "Demonic Strike|a|r|13|d",
                "Desert Fury|w|l|5|p",
                "Desert Mirage|w|l|4|s",
                "Desert Wrath|w|l|4|p",
                "Devilish Greataxe|w|n|13|p",
                "Diamond Encrusted Blade|w|n|20|p",
                "Dracani Flanged Mace|w|n|9|p",
                "Dracani Gilded Lance|w|n|9|s",
                "Dracani Gilded Staff|w|n|9|s",
                "Dracani Gilded Sword|w|n|9|p",
                "Dracani Guardian Armor|c|n|9|g",
                "Dracani Guardian Helmet|h|n|9|g",
                "Dracani Mage Armor|c|n|9|m",
                "Dracani Mage Helmet|h|n|9|m",
                "Dracani Royal Glaive|w|n|9|p",
                "Dracani Spellclaws|w|n|9|s",
                "Dracani Warrior Armor|c|n|9|w",
                "Dracani Warrior Helmet|h|n|9|w",
                "Dragon Slayer Blade|w|n|20|p",
                "Dragon's Claw Scythe|w|n|18|s",
                "Dual Ancient Daggers|w|n|18|p",
                "Dual Arcane Slicers|w|n|17|s",
                "Dual Arcane Spelldaggers|w|n|18|s",
                "Dual Bioforged Drills|w|l|3|p",
                "Dual Bioforged Spelldaggers|w|n|16|s",
                "Dual Bladed Mage Daggers|w|n|8|s",
                "Dual Crimson Daggers|w|n|17|p",
                "Dual Crystalized Knives|w|n|12|p",
                "Dual Cutlasses|w|n|10|p",
                "Dual Elegant Mage Fans|w|n|15|s",
                "Dual Fist Blades|w|n|19|p",
                "Dual Flatblade Slicers|w|n|18|p",
                "Dual Frozen Blades|w|n|10|p",
                "Dual Fusion Blades|w|n|16|p",
                "Dual Godforged Blades|w|l|3|p",
                "Dual Hellfire Blades|w|n|19|s",
                "Dual Hextech Spelldaggers|w|n|16|s",
                "Dual Infernal Daggers|w|n|15|p",
                "Dual Infernal Scimitars|w|n|17|p",
                "Dual Inferno Slicers|w|n|10|p",
                "Dual Jade Daggers|w|n|10|p",
                "Dual Magma Fangs|w|n|17|p",
                "Dual Magma Shields|w|n|19|s",
                "Dual Nature Vines|w|n|3|s",
                "Dual Ocean Fists|w|n|8|s",
                "Dual Phantom Axes|w|n|8|p",
                "Dual Phantom Daggers|w|n|8|p",
                "Dual Phantom Defenders|w|n|8|s",
                "Dual Phoenix Daggers|w|l|18|p",
                "Dual Pirate Cutlasses|w|n|8|p",
                "Dual Razor Slicers|w|n|17|p",
                "Dual Royal Axes|w|n|10|p",
                "Dual Samurai Sickles|w|n|15|p",
                "Dual Samurai Stars|w|n|15|p",
                "Dual Sapphire Slicers|w|n|18|p",
                "Dual Serrated Knives|w|n|8|p",
                "Dual Sinister Blades|w|n|3|p",
                "Dual Solar Blades|w|n|12|p",
                "Dual Toxic Daggers|w|n|8|s",
                "Eagle Staff|w|n|10|s",
                "Earth Clap|a|r|15|d",
                "Earth Kick|a|u|17|d",
                "Earth Maul|w|n|3|p",
                "Earth Spikes|a|u|8|d",
                "Earth Staff|w|n|3|s",
                "Earth Wand|w|n|13|s",
                "Easter Guardian Armor|c|e|6|g",
                "Easter Guardian Helmet|h|e|6|g",
                "Easter Mage Armor|c|e|6|m",
                "Easter Mage Helmet|h|e|6|m",
                "Easter Warrior Armor|c|e|6|w",
                "Easter Warrior Helmet|h|e|6|w",
                "Egg Bomb|a|r|6|d",
                "Egg Maul|w|e|6|p",
                "Egg Staff|w|e|6|s",
                "Eldenbark Greatstaff|w|l|7|s",
                "Eldenbark Greatsword|w|l|7|p",
                "Eldenbark Guardian Armor|c|n|7|g",
                "Eldenbark Guardian Helmet|h|n|7|g",
                "Eldenbark Mage Armor|c|n|7|m",
                "Eldenbark Mage Helmet|h|n|7|m",
                "Eldenbark Warrior Armor|c|n|7|w",
                "Eldenbark Warrior Helmet|h|n|7|w",
                "Elder Void Wand|w|n|20|s",
                "Eldritch Cleavers|w|n|1|p",
                "Eldritch Guardian Armor|c|n|1|g",
                "Eldritch Guardian Helmet|h|n|1|g",
                "Eldritch Mace|w|n|1|s",
                "Eldritch Mage Armor|c|n|1|m",
                "Eldritch Mage Helmet|h|n|1|m",
                "Eldritch Trident|w|n|1|s",
                "Eldritch War Lance|w|n|1|p",
                "Eldritch Warrior Armor|c|n|1|w",
                "Eldritch Warrior Helmet|h|n|1|w",
                "Electric Boom|a|e|10|d",
                "Electric Field|a|e|12|d",
                "Electric Grinder|a|e|12|d",
                "Electric Slash|a|r|17|d",
                "Electron Spell Dagger|w|n|12|s",
                "Elementalist Hood|h|n|5|m",
                "Elementalist Robes|c|n|5|m",
                "Elementalist Staff|w|n|17|s",
                "Elite Ancient Plate Armor|c|n|21|g",
                "Elite Ancient Plate Helmet|h|n|21|g",
                "Elite Mage Plate Armor|c|n|21|m",
                "Elite Mage Plate Helmet|h|n|21|m",
                "Elite Warlord Plate Armor|c|n|21|w",
                "Elite Warlord Plate Helmet|h|n|21|w",
                "Elven Staff|w|n|10|s",
                "Empowered Crystal Blade|w|n|13|p",
                "Enchanted Demonic Greataxe|w|n|18|p",
                "Enchanted Sea Axes|w|n|2|s",
                "Enchanted Sea Daggers|w|n|2|s",
                "Enchanted Serpent Daggers|w|n|2|s",
                "Enchanted Shard Dual Blade|w|n|7|p",
                "Enchanted Shard Spelldagger|w|n|7|s",
                "Enchanted Shard Staff|w|n|7|s",
                "Enchanted Shard War Axe|w|n|7|p",
                "Enchanted Shuriken|a|e|15|d",
                "Enchanted Spinning Blades|a|e|13|d",
                "Enchanted Sword|w|n|5|p",
                "Energized Spell Dagger|w|n|12|s",
                "Energy Orb|a|e|12|d",
                "Enhanced Inner Focus|a|l|2|b",
                "Enhanced Inner Rage|a|l|2|b",
                "Ethereal Greataxe|w|n|10|p",
                "Explosive Mine|a|e|12|d",
                "Explosive Punch|a|e|16|d",
                "Fallen Guardian Armor|c|n|1|g",
                "Fallen Guardian Helmet|h|n|1|g",
                "Fallen Mage Armor|c|n|1|m",
                "Fallen Mage Helmet|h|n|1|m",
                "Fallen Warrior Armor|c|n|1|w",
                "Fallen Warrior Helmet|h|n|1|w",
                "Fallen's Battlestaff|w|n|1|s",
                "Fallen's Blade|w|n|1|p",
                "Fallen's Halberd|w|n|1|p",
                "Fallen's Spellblades|w|n|1|s",
                "File:Fungal Guardian Armor|c|n|7|g",
                "Fire and Ice Staff|w|n|10|s",
                "Fire Bomb|a|u|20|d",
                "Fireball|a|c|4|d",
                "Flame Cyclone|a|e|15|d",
                "Flame Shuriken|a|e|11|d",
                "Flame Staff|w|n|5|s",
                "Flame Step|a|c|0|d",
                "Flame Strike|a|r|11|d",
                "Focus Beam|a|e|12|d",
                "Forest Vine Hatchet|w|n|7|p",
                "Forest Vine Spellblade|w|n|7|s",
                "Forgotten Army|a|e|17|d",
                "Forgotten Guardian Armor|c|n|21|g",
                "Forgotten Guardian Helmet|h|n|21|g",
                "Forgotten Mage Hood|h|n|21|m",
                "Forgotten Mage Robes|c|n|21|m",
                "Forgotten Warrior Armor|c|n|21|w",
                "Forgotten Warrior Helmet|h|n|21|w",
                "Frost Cone|a|r|11|d",
                "Frost Giant Greataxe|w|n|11|p",
                "Frost Maul|w|n|20|p",
                "Frostbound Guardian Armor|c|n|20|g",
                "Frostbound Guardian Helmet|h|n|20|g",
                "Frostbound Mage Cloak|h|n|20|m",
                "Frostbound Mage Robes|c|n|20|m",
                "Frostbound Warrior Armor|c|n|20|w",
                "Frostbound Warrior Helmet|h|n|20|w",
                "Frostshard Battle Axe|w|n|20|p",
                "Frostshard Greatstaff|w|n|20|s",
                "Frostshard Hammer|w|n|20|p",
                "Frostshard Lance|w|n|20|s",
                "Frostshard Trident|w|n|20|s",
                "Frostshard Twinblades|w|n|20|p",
                "Frostwarden|w|l|20|s",
                "Frosty Staff|w|n|20|s",
                "Frozen Greatsword|w|n|20|p",
                "Frozen Lord's Greatsword|w|n|20|p",
                "Frozen Spelldaggers|w|n|20|s",
                "Fungal Guardian Helmet|h|n|7|g",
                "Fungal Lance|w|n|7|p",
                "Fungal Mage Armor|c|n|7|m",
                "Fungal Mage Helmet|h|n|7|m",
                "Fungal Pike|w|n|7|s",
                "Fungal Poison|a|r|7|d",
                "Fungal Staff|w|n|7|s",
                "Fungal Warhammer|w|n|7|p",
                "Fungal Warrior Armor|c|n|7|w",
                "Fungal Warrior Helmet|h|n|7|w",
                "Fusion Greatsword|w|n|16|p",
                "Fusion Magic Keyblade|w|n|3|s",
                "Galactic Dual Blades|w|l|12|p",
                "Galactic Pike|w|l|12|s",
                "Gale Barrage|a|e|11|d",
                "Gale Slice|a|u|20|d",
                "Geyser|a|e|11|d",
                "Ghostly Cannon Barrage|a|u|13|d",
                "Ghostly Greataxe|w|n|5|p",
                "Ghostly Rampage|a|r|15|d",
                "Ghoul Slayer|w|n|5|p",
                "Giant Royal Axe|w|n|17|p",
                "Gildenscale Guardian Armor|c|n|9|g",
                "Gildenscale Guardian Helmet|h|n|9|g",
                "Gildenscale Mage Armor|c|n|9|m",
                "Gildenscale Mage Helmet|h|n|9|m",
                "Gildenscale Oath And Aegis|w|l|9|p",
                "Gildenscale Warrior Armor|c|n|9|w",
                "Gildenscale Warrior Helmet|h|n|9|w",
                "Glacial Blows|a|r|10|d",
                "Glacial Greatsword|w|n|20|p",
                "Glorious Guardian Armor|c|n|18|g",
                "Glorious Guardian Helmet|h|n|18|g",
                "Glorious Mage Armor|c|n|18|m",
                "Glorious Mage Helmet|h|n|18|m",
                "Glorious Warrior Armor|c|n|18|w",
                "Glorious Warrior Helmet|h|n|18|w",
                "Goblin Cleaver|w|n|10|p",
                "God Spear|a|e|9|d",
                "Godforged Greatstaff|w|l|3|s",
                "Godly Guardian Armor|c|n|13|g",
                "Godly Guardian Helmet|h|n|13|g",
                "Godly Mage Helmet|h|n|13|m",
                "Godly Mage Robes|c|n|13|m",
                "Godly Warrior Armor|c|n|13|w",
                "Godly Warrior Helmet|h|n|13|w",
                "Godsword|w|n|20|p",
                "Golden Kopesh|w|n|4|p",
                "Grand Claymore|w|n|5|p",
                "Granite Maul|w|n|5|p",
                "Gravity Leap|a|l|1|",
                "Greater Dark Scythe|w|n|13|s",
                "Greater Prophet Staff|w|n|13|s",
                "Ground Slam|a|u|20|d",
                "Ground Stomp|a|e|16|d",
                "Guardian Armor|c|n|5|g",
                "Guardian Call|a|e|13|g",
                "Guardian Helmet|h|n|5|g",
                "Guardian Roar|a|r|6|g",
                "Guardian's Blessing|a|r|10|g",
                "Gungnir|w|l|11|s",
                "Hand Cannon|a|u|15|d",
                "Hands Of Death|a|e|22|d",
                "Hardened Ice Sword|w|n|20|p",
                "Heavenly Greatsword|w|n|10|p",
                "Heavenly Guardian Armor|c|n|3|g",
                "Heavenly Guardian Helmet|h|n|3|g",
                "Heavenly Mage Armor|c|n|3|m",
                "Heavenly Mage Helmet|h|n|3|m",
                "Heavenly Warrior Armor|c|n|3|w",
                "Heavenly Warrior Helmet|h|n|3|w",
                "Hellstone Greataxe|w|n|19|p",
                "Hextech Greataxe|w|n|16|p",
                "Hextech Katana|w|n|16|p",
                "Hextech Overloaded Staff|w|l|3|s",
                "Hextech Polearm|w|n|16|s",
                "Hextech Wired Spellblade|w|n|16|s",
                "High Priest Battleaxe|w|n|10|p",
                "Hofund|w|x|11|p",
                "Holy Barrier|a|r|4|g",
                "Holy Circle|a|e|4|h",
                "Holy Grail|w|n|20|s",
                "Holy Staff|w|n|5|s",
                "Holy Sun Staff|w|n|4|s",
                "Holy Wand|w|n|13|s",
                "Honorable Greatsword|w|n|15|p",
                "Hope's Triumph|w|n|18|s",
                "Hunter's Guardian Armor|c|n|8|g",
                "Hunter's Guardian Helmet|h|n|8|g",
                "Hunter's Mage Armor|c|n|8|m",
                "Hunter's Mage Helmet|h|n|8|m",
                "Hunter's Warrior Armor|c|n|8|w",
                "Hunter's Warrior Helmet|h|n|8|w",
                "Ice Barrage|a|e|2|d",
                "Ice Crash|a|e|2|d",
                "Ice Enhanced Sword|w|n|20|p",
                "Ice Greatspear|w|n|11|p",
                "Ice Guardian Armor|c|n|21|g",
                "Ice Guardian Helmet|h|n|21|g",
                "Ice Infused Slicer|w|n|20|p",
                "Ice King's Guardian Armor|c|n|21|g",
                "Ice King's Guardian Helmet|h|n|21|g",
                "Ice King's Mage Hood|h|n|21|m",
                "Ice King's Mage Robes|c|n|21|m",
                "Ice King's Warrior Armor|c|n|21|w",
                "Ice King's Warrior Helmet|h|n|21|w",
                "Ice Mage Hood|h|n|21|m",
                "Ice Mage Robes|c|n|21|m",
                "Ice Needles|a|u|20|d",
                "Ice Nova|a|r|18|d",
                "Ice Queen's Wand|w|n|20|s",
                "Ice Reaver|w|n|20|s",
                "Ice Sickles|w|n|20|p",
                "Ice Spellblade|w|n|11|s",
                "Ice Spikes|a|e|2|d",
                "Ice Totem|a|e|18|d",
                "Ice Wand|w|n|20|s",
                "Ice Warrior Armor|c|n|21|w",
                "Ice Warrior Helmet|h|n|21|w",
                "Iceblade|w|n|20|p",
                "Icicle Barrage|a|r|17|d",
                "Illusion Blast|a|e|15|d",
                "Industrial Guardian Armor|c|n|16|g",
                "Industrial Guardian Helmet|h|n|16|g",
                "Industrial Mage Armor|c|n|16|m",
                "Industrial Mage Helmet|h|n|16|m",
                "Industrial Spellscythe|w|n|15|s",
                "Industrial Warrior Armor|c|n|16|w",
                "Industrial Warrior Helmet|h|n|16|w",
                "Infernal Blast|a|e|16|d",
                "Infernal Elemental Sword|w|n|20|p",
                "Infernal Guardian Armor|c|n|15|g",
                "Infernal Guardian Helmet|h|n|15|g",
                "Infernal Mage Hood|h|n|15|m",
                "Infernal Mage Robes|c|n|15|m",
                "Infernal Orbs|a|u|18|d",
                "Infernal Strike|a|e|18|d",
                "Infernal Sun Staff|w|n|10|s",
                "Infernal Warrior Armor|c|n|15|w",
                "Infernal Warrior Helmet|h|n|15|w",
                "Inferno Plate Armor|c|n|13|w",
                "Inferno Plate Helmet|h|n|13|w",
                "Inner Focus|a|e|19|b",
                "Inner Rage|a|e|19|b",
                "Innervate|a|e|4|b",
                "Inventor's Greatsword|w|l|16|p",
                "Inventor's Guardian Armor|c|n|3|g",
                "Inventor's Guardian Helmet|h|n|3|g",
                "Inventor's Mage Armor|c|n|3|m",
                "Inventor's Mage Helmet|h|n|3|m",
                "Inventor's Spellblade|w|l|16|s",
                "Inventor's Warrior Armor|c|n|3|w",
                "Inventor's Warrior Helmet|h|n|3|w",
                "Iron Armor|c|n|5|g",
                "Iron Helmet|h|n|5|g",
                "Iron Longsword|w|n|5|p",
                "Jade Rain|a|e|9|d",
                "Jade Roller|a|e|9|d",
                "Jade Spelldagger|w|n|15|s",
                "Jigoku Club And Shield|w|n|22|p",
                "Jigoku Shuriblade|w|n|22|s",
                "Jigoku Twin Katanas|w|n|22|p",
                "Jigoku Twin Warfans|w|n|22|s",
                "Jotunn Guardian Armor|c|n|11|g",
                "Jotunn Guardian Helmet|h|n|11|g",
                "Jotunn Mage Armor|c|n|11|m",
                "Jotunn Mage Helmet|h|n|11|m",
                "Jotunn Warrior Armor|c|n|11|w",
                "Jotunn Warrior Helmet|h|n|11|w",
                "King's Greatsword|w|n|20|p",
                "King's Spellblade|w|n|20|s",
                "Kraken Slayer|w|l|8|p",
                "Kunai Knives|a|e|22|d",
                "Laevateinn|w|x|11|s",
                "Lava Barrage|a|e|19|d",
                "Lava Beam Orb|a|e|19|d",
                "Lava Cage|a|e|19|d",
                "Lava King's Guardian Armor|c|n|19|g",
                "Lava King's Guardian Helmet|h|n|19|g",
                "Lava King's Mage Armor|c|n|19|m",
                "Lava King's Mage Helmet|h|n|19|m",
                "Lava King's Spell Daggers|w|l|19|s",
                "Lava King's Warrior Armor|c|n|19|w",
                "Lava King's Warrior Helmet|h|n|19|w",
                "Lava King's Warscythe|w|l|19|p",
                "Lava Lash|a|e|15|d",
                "Lava Shard Staff|w|n|19|s",
                "Lava Spellblade|w|n|19|s",
                "Lava Tendril Pike|w|n|19|s",
                "Leaping Strike|a|c|0|d",
                "Life Dash|a|r|16|h",
                "Life Pulse|a|r|6|h",
                "Lightning Beam|a|u|20|d",
                "Lightning Burst|a|e|7|d",
                "Lightning Strikes|a|r|4|d",
                "Luminous Greatstaff|w|n|18|s",
                "Mage Plate Armor|c|n|21|m",
                "Mage Plate Helmet|h|n|21|m",
                "Mage's Spellbook|w|n|5|s",
                "Magic Mallet|w|n|5|s",
                "Magic Trident|w|n|8|s",
                "Magma Infused Staff|w|n|20|s",
                "Magma Infused Waraxe|w|n|19|p",
                "Mana Infused Spellblade|w|n|17|s",
                "Mercenary Armor|c|n|5|w",
                "Mercenary Helmet|h|n|5|w",
                "Midgardian Guardian Armor|c|n|11|g",
                "Midgardian Guardian Helmet|h|n|11|g",
                "Midgardian Mage Armor|c|n|11|m",
                "Midgardian Mage Helmet|h|n|11|m",
                "Midgardian Warrior Armor|c|n|11|w",
                "Midgardian Warrior Helmet|h|n|11|w",
                "Mighty Cleave|a|e|1|",
                "Mighty Flatblade|w|n|13|p",
                "Mighty Frozen Greatsword|w|n|20|p",
                "Mighty Fusion Maul|w|n|16|p",
                "Mighty Fusion Spellblade|w|n|16|s",
                "Mighty Leap|a|r|8|d",
                "Mjolnir|w|l|11|p",
                "Molten Ball|a|e|12|d",
                "Molten Blade|w|n|13|p",
                "Molten Forged Guardian Armor|c|n|19|g",
                "Molten Forged Guardian Helmet|h|n|19|g",
                "Molten Forged Mage Armor|c|n|19|m",
                "Molten Forged Mage Helmet|h|n|19|m",
                "Molten Forged Warrior Armor|c|n|19|w",
                "Molten Forged Warrior Helmet|h|n|19|w",
                "Molten Greataxe|w|n|13|p",
                "Molten Maul|w|n|0|p",
                "Molten Shards|a|e|19|d",
                "Moon Crystal Spell Blade|w|n|12|s",
                "Moonlight Staff|w|n|10|s",
                "Mossy Greatsword|w|n|20|p",
                "Mystery Matter|a|e|12|d",
                "Mythical Guardian Armor|c|n|8|g",
                "Mythical Guardian Helmet|h|n|8|g",
                "Mythical Mage Armor|c|n|8|m",
                "Mythical Mage Helmet|h|n|8|m",
                "Mythical Warrior Armor|c|n|8|w",
                "Mythical Warrior Helmet|h|n|8|w",
                "Nature Guardian Armor|c|n|3|g",
                "Nature Guardian Helmet|h|n|3|g",
                "Nature Mage Armor|c|n|3|m",
                "Nature Mage Helmet|h|n|3|m",
                "Nature Scythe|w|n|18|p",
                "Nature Spellblade|w|n|3|s",
                "Nature Warrior Armor|c|n|3|w",
                "Nature Warrior Helmet|h|n|3|w",
                "Norse Blade|w|n|11|p",
                "Norse Greataxe|w|n|11|p",
                "Northern Runic Blade|w|n|11|p",
                "Northern Spellstaff|w|n|11|s",
                "Novice Armor|c|n|5|w",
                "Novice Helmet|h|n|5|w",
                "Novice Wand|w|n|5|s",
                "Oathsworn Guardian Armor|c|n|9|g",
                "Oathsworn Guardian Helmet|h|n|9|g",
                "Oathsworn Halberd|w|n|9|p",
                "Oathsworn Hammer|w|n|9|p",
                "Oathsworn Mage Armor|c|n|9|m",
                "Oathsworn Mage Helmet|h|n|9|m",
                "Oathsworn Spellblade|w|n|9|s",
                "Oathsworn Spellscythe|w|n|9|s",
                "Oathsworn Staff And Tome|w|n|9|s",
                "Oathsworn Sword And Shield|w|n|9|p",
                "Oathsworn Warrior Armor|c|n|9|w",
                "Oathsworn Warrior Helmet|h|n|9|w",
                "Ocean Dweller's Mageblade|w|n|8|s",
                "Ocean Pearl Staff|w|n|2|s",
                "Ocean Splitter|w|n|13|p",
                "Oceanic Greatsword|w|n|2|p",
                "Oni Guardian Armor|c|n|22|g",
                "Oni Guardian Helmet|h|n|22|g",
                "Oni Mage Cloak|h|n|22|m",
                "Oni Mage Robes|c|n|22|m",
                "Oni Warrior Armor|c|n|22|w",
                "Oni Warrior Helmet|h|n|22|w",
                "Oni's Bell Staff|w|n|22|s",
                "Oni's Dadao|w|n|22|p",
                "Oni's Kanabo|w|n|22|p",
                "Oni's Naginata|w|n|22|s",
                "Onyx Empowered Greatsword|w|n|13|p",
                "Onyx Hammer|w|n|20|p",
                "Onyx Spell Scythe|w|n|20|s",
                "Onyx Staff|w|n|5|s",
                "Oracle's Ascendance|w|l|0|s",
                "Oracle's Gaze|w|l|0|s",
                "Oracle's Revelation|w|l|0|s",
                "Oracle's Wisdom|w|l|0|s",
                "Orb Of Destruction|a|e|16|d",
                "Overcharge|a|r|16|d",
                "Overgrown War Scythe|w|n|7|p",
                "Overlord's Guardian Armor|c|n|17|g",
                "Overlord's Guardian Hat|h|n|17|g",
                "Overlord's Mage Hat|h|n|17|m",
                "Overlord's Mage Robes|c|n|17|m",
                "Overlord's Manablade|w|l|17|s",
                "Overlord's Rageblade|w|l|17|p",
                "Overlord's Warrior Armor|c|n|17|w",
                "Overlord's Warrior Hat|h|n|17|w",
                "Phantom Blades|a|e|8|d",
                "Phantom Flames|a|e|13|d",
                "Phantom Striker|a|e|8|d",
                "Phase Barrage|a|n|14|d",
                "Phoenix Greatstaff|w|l|18|s",
                "Piercing Rain|a|u|20|d",
                "Piercing Roots|a|r|7|d",
                "Pink Pearl Spellscythe|w|n|15|s",
                "Pirate King's Guardian Armor|c|n|13|g",
                "Pirate King's Guardian Helmet|h|n|13|g",
                "Pirate King's Mage Halo|h|n|13|m",
                "Pirate King's Mage Robes|c|n|13|m",
                "Pirate King's Warrior Armor|c|n|13|w",
                "Pirate King's Warrior Helmet|h|n|13|w",
                "Plasma Infused Cutlass|w|n|16|s",
                "Plasma Spellblade|w|n|16|s",
                "Plasma Twin Spellblade|w|n|16|s",
                "Poison Cloud|a|r|4|d",
                "Poison Spear|w|n|8|s",
                "Pulse Beam|a|r|8|d",
                "Pulse Waves|a|r|16|d",
                "Pulsefire|a|r|13|d",
                "Pulverizer|w|n|5|p",
                "Raider's Guardian Armor|c|n|8|g",
                "Raider's Guardian Helmet|h|n|8|g",
                "Raider's Mage Armor|c|n|8|m",
                "Raider's Mage Helmet|h|n|8|m",
                "Raider's Warrior Armor|c|n|8|w",
                "Raider's Warrior Helmet|h|n|8|w",
                "Red Knight Armor|c|n|5|w",
                "Red Knight Helmet|h|n|5|w",
                "Redemption|a|u|4|h",
                "Reinforced Guardian Armor|c|n|18|g",
                "Reinforced Guardian Helmet|h|n|18|g",
                "Reinforced Ice Blade|w|n|20|p",
                "Reinforced Steel Sword|w|n|20|p",
                "Rejuvenating Spray|a|u|20|h",
                "Rending Slice|a|r|18|d",
                "Revitalize|a|e|7|h",
                "Rift Beam|a|e|22|d",
                "Riptide Guardian Armor|c|n|2|g",
                "Riptide Guardian Helmet|h|n|2|g",
                "Riptide Mage Armor|c|n|2|m",
                "Riptide Mage Helmet|h|n|2|m",
                "Riptide Warrior Armor|c|n|2|w",
                "Riptide Warrior Helmet|h|n|2|w",
                "Rogue Guardian Armor|c|n|17|g",
                "Rogue Guardian Hood|h|n|17|g",
                "Rogue Mage Hood|h|n|17|m",
                "Rogue Mage Robes|c|n|17|m",
                "Rogue Warrior Armor|c|n|17|w",
                "Rogue Warrior Hood|h|n|17|w",
                "Rogue's Rapier|w|n|5|p",
                "Royal Crimson Greatsword|w|n|18|p",
                "Royal Katana|w|n|15|p",
                "Royal Slicer|w|n|20|p",
                "Ruby Greatsword|w|n|15|p",
                "Ruby Staff|w|n|13|s",
                "Runic Hammer|w|n|20|p",
                "Runic Mace|w|n|11|s",
                "Runic Pike|w|n|17|s",
                "Runic Spellscythe|w|n|17|s",
                "Runic Strike|a|u|17|d",
                "Sacrificial Orbs|a|e|1|",
                "Sakura Greatstaff|w|l|15|s",
                "Sakura Katana|w|l|15|p",
                "Salvaged Guardian Armor|c|n|17|g",
                "Salvaged Guardian Helmet|h|n|17|g",
                "Salvaged Mage Hat|h|n|17|m",
                "Salvaged Mage Robes|c|n|17|m",
                "Salvaged Warrior Armor|c|n|17|w",
                "Salvaged Warrior Helmet|h|n|17|w",
                "Samurai Guardian Armor|c|n|15|g",
                "Samurai Guardian Helmet|h|n|15|g",
                "Samurai Mage Helmet|h|n|15|m",
                "Samurai Mage Robes|c|n|15|m",
                "Samurai Warrior Armor|c|n|15|w",
                "Samurai Warrior Hairband|h|n|15|w",
                "Sandstone Guardian Armor|c|n|4|g",
                "Sandstone Guardian Helmet|h|n|4|g",
                "Sandstone Mage Cloak|h|n|4|m",
                "Sandstone Mage Robes|c|n|4|m",
                "Sandstone Warrior Armor|c|n|4|w",
                "Sandstone Warrior Helmet|h|n|4|w",
                "Sapphire Greatstaff|w|n|18|s",
                "Sapphire Spell Dagger|w|n|20|s",
                "Sapphire Spellspear|w|n|15|s",
                "Sapphire Stone Wand|w|n|17|s",
                "Sea King's Greatstaff|w|l|2|s",
                "Sea King's Trident|w|l|2|p",
                "Sea Serpent's Wings|w|l|8|s",
                "Sea Staff|w|n|2|s",
                "Seafarer's Lost Blade|w|n|8|p",
                "Seafarer's Magic Device|w|n|8|s",
                "Searing Beam|a|u|20|d",
                "Seishin Cleaver|w|n|22|p",
                "Seishin Club|w|n|22|s",
                "Seishin Crescent|w|n|22|p",
                "Seishin Guardian Armor|c|n|22|g",
                "Seishin Guardian Helmet|h|n|22|g",
                "Seishin Mage Cloak|h|n|22|m",
                "Seishin Mage Robes|c|n|22|m",
                "Seishin Staff|w|n|22|s",
                "Seishin Warrior Armor|c|n|22|w",
                "Seishin Warrior Helmet|h|n|22|w",
                "Serpent Pike|w|n|2|p",
                "Serpent Scimitars|w|n|2|p",
                "Sharktooth Blade|w|n|8|p",
                "Shattered Magma Blade|w|n|19|p",
                "Shatterstrike|a|e|1|",
                "Shock Blast|a|r|0|d",
                "Shock Wave|a|r|0|d",
                "Skull Flames|a|e|13|d",
                "Slam|a|u|4|d",
                "Smite|a|r|8|d",
                "Snow Elemental Staff|w|n|20|s",
                "Snowy Greatstaff|w|n|20|s",
                "Solar Beam|a|e|9|d",
                "Solar Essence Staff|w|n|12|s",
                "Solar Greatsword|w|n|12|p",
                "Solar Katana|w|n|12|p",
                "Solar Staff|w|n|13|s",
                "Soul Drain|a|e|11|d",
                "Soulstealer Greatsword|w|l|13|p",
                "Space Guardian Armor|c|n|12|g",
                "Space Guardian Helmet|h|n|12|g",
                "Space Mage Armor|c|n|12|m",
                "Space Mage Helmet|h|n|12|m",
                "Space Warrior Armor|c|n|12|w",
                "Space Warrior Helmet|h|n|12|w",
                "Spear Strike|a|r|2|d",
                "Spiked Club|w|n|5|p",
                "Spinning Blade Smash|a|e|22|d",
                "Spirit Bomb|a|u|8|d",
                "Spirit Link|a|e|22|h",
                "Staff of Heat|w|n|15|s",
                "Staff of the Gods|w|l|13|s",
                "Staff of the North|w|n|11|s",
                "Star Barrage|a|r|16|d",
                "Starfall|a|r|16|d",
                "Starter Wand|w|c|0|s",
                "Steel Serrated Sword|w|n|5|p",
                "Steel Strongsword|w|n|20|p",
                "Stone Scythe|w|n|17|p",
                "Stone Strongsword|w|n|13|p",
                "Storm Blast|a|e|0|d",
                "Storm Wave|a|e|0|d",
                "Sunken Blade|w|n|3|p",
                "Sunlight Staff|w|n|10|s",
                "Taunt|a|c|5|g",
                "Taunting Aura|a|u|20|g",
                "Templar Blade|w|n|13|p",
                "Templar Hood|h|n|5|m",
                "Templar Robes|c|n|5|m",
                "Thunderous Blast|a|u|10|d",
                "Timelost Greatsword|w|n|18|p",
                "Timelost Guardian Armor|c|n|18|g",
                "Timelost Guardian Helmet|h|n|18|g",
                "Timelost Mage Armor|c|n|18|m",
                "Timelost Mage Helmet|h|n|18|m",
                "Timelost Spellbook|w|n|18|s",
                "Timelost Warhammer|w|n|18|p",
                "Timelost Warrior Armor|c|n|18|w",
                "Timelost Warrior Helmet|h|n|18|w",
                "Titan's Greataxe|w|n|13|p",
                "Titan-forged_Guardian_Armor|c|n|10|g",
                "Titan-forged_Guardian_Helmet|h|n|10|g",
                "Titan-forged_Mage_Armor|c|n|10|m",
                "Titan-forged_Mage_Helmet|h|n|10|m",
                "Titan-forged_Warrior_Armor|c|n|10|w",
                "Titan-forged_Warrior_Helmet|h|n|10|w",
                "Titanium Guardian Armor|c|n|16|g",
                "Titanium Guardian Helmet|h|n|16|g",
                "Titanium Mage Armor|c|n|16|m",
                "Titanium Mage Helmet|h|n|16|m",
                "Titanium Warrior Armor|c|n|16|w",
                "Titanium Warrior Helmet|h|n|16|w",
                "Toxic Spellscythe|w|n|17|s",
                "Toxic Warspear|w|n|15|p",
                "Tribal Mage Armor|c|n|18|m",
                "Tribal Mage Hood|h|n|18|m",
                "Tribal Staff|w|n|10|s",
                "Tribal Warrior Helmet|h|n|18|w",
                "Tribal_Warrior_Armor|c|n|18|w",
                "Triple Blade Throw|a|e|16|d",
                "Triple Quake|a|e|22|d",
                "Triton Guardian Armor|c|n|2|g",
                "Triton Guardian Helmet|h|n|2|g",
                "Triton Mage Armor|c|n|2|m",
                "Triton Mage Helmet|h|n|2|m",
                "Triton Warrior Armor|c|n|2|w",
                "Triton Warrior Helmet|h|n|2|w",
                "Tsunami|a|u|17|d",
                "Tundra Guardian Armor|c|n|20|g",
                "Tundra Guardian Helmet|h|n|20|g",
                "Tundra Mage Cloak|h|n|20|m",
                "Tundra Mage Robes|c|n|20|m",
                "Tundra Warrior Armor|c|n|20|w",
                "Tundra Warrior Helmet|h|n|20|w",
                "Twin Bladed Slicer|w|n|20|p",
                "Twin Slash|a|e|12|d",
                "Twisted Wood Greatstaff|w|l|3|s",
                "Twisted Wood Greatsword|w|l|3|p",
                "Universal Heal|a|e|13|h",
                "Unstable Warp|a|l|1|",
                "Valhalla Guardian Armor|c|n|11|g",
                "Valhalla Guardian Helmet|h|n|11|g",
                "Valhalla Mage Armor|c|n|11|m",
                "Valhalla Mage Helmet|h|n|11|m",
                "Valhalla Warrior Armor|c|n|11|w",
                "Valhalla Warrior Helmet|h|n|11|w",
                "Vampiric Greatstaff|w|n|18|s",
                "Vengeful Taunt|a|e|1|",
                "Viking Hatchets|w|n|11|p",
                "Viking Sceptre|w|n|11|s",
                "Viking Shield|w|n|11|s",
                "Violet Spellblade|w|n|15|s",
                "Void Beam|a|r|10|d",
                "Void Dragon|a|e|22|d",
                "Void Greatsword|w|n|12|p",
                "Void Plate Armor|c|n|13|g",
                "Void Plate Helmet|h|n|13|g",
                "Void Spell Blade|w|n|12|s",
                "Void Spell Dagger|w|n|12|s",
                "Void Spheres|a|r|8|d",
                "Voidborn Guardian Armor|c|n|1|g",
                "Voidborn Guardian Helmet|h|n|1|g",
                "Voidborn Mage Armor|c|n|1|m",
                "Voidborn Mage Helmet|h|n|1|m",
                "Voidborn Warrior Armor|c|n|1|w",
                "Voidborn Warrior Helmet|h|n|1|w",
                "Voidborn's Embrace|w|l|1|s",
                "Voidborn's Malice|w|l|1|p",
                "Voidfallen's Effigy & Edict|w|x|1|s",
                "Voidflames|a|e|1|",
                "Voidspire & Abyssal Veil|w|x|1|p",
                "Volcanic Greatsword|w|n|19|p",
                "Vortex|a|e|17|d",
                "Vortex Grenade|a|e|12|d",
                "War-forged Guardian Armor|c|n|16|g",
                "War-forged Guardian Helmet|h|n|16|g",
                "War-forged Mage Armor|c|n|16|m",
                "War-forged Mage Helmet|h|n|16|m",
                "War-forged Warrior Armor|c|n|16|w",
                "War-forged Warrior Helmet|h|n|16|w",
                "Warlord Plate Armor|c|n|21|w",
                "Warlord Plate Helmet|h|n|21|w",
                "Water Elemental Spellblade|w|n|20|s",
                "Water Orb|a|r|2|d",
                "Whirlwind|a|u|4|d",
                "Wind Blast|a|e|7|d",
                "Winter Lord's Guardian Armor|c|n|20|g",
                "Winter Lord's Guardian Helmet|h|n|20|g",
                "Winter Lord's Mage Cloak|h|n|20|m",
                "Winter Lord's Mage Robes|c|n|20|m",
                "Winter Lord's Warrior Armor|c|n|20|w",
                "Winter Lord's Warrior Helmet|h|n|20|w",
                "Winterborne|w|l|20|p",
                "Yokai Transformation|a|e|22|d",
            }
        local function nameKey(u)
            local h = string.lower(tostring(u or ""))
            h = string.gsub(h, "[^a-z0-9]", "")
            return (string.gsub(h, "armour", "armor"))
        end
        inventoryAutomation.nameKey = nameKey
        inventoryAutomation.items = {}
        inventoryAutomation.dungeons = dungeons
        for index = 1, #l, 1 do
            local name, m, R, y, q = string.match(l[index], "^(.-)|(%a)|(%a)|(%d+)|(%a*)$")
            if name then
                index = #inventoryAutomation.items + 1
                inventoryAutomation.items[index] = {
                    name = name,
                    key = nameKey(name),
                    kind = D[m] or "weapon",
                    tier = P[R] or "",
                    dung = dungeons[tonumber(y)] or "",
                    sub = _[q] or "",
                }
            end
        end
        local cfg = {
            common = "sellCommon",
            uncommon = "sellUncommon",
            rare = "sellRare",
            epic = "sellEpic",
            legendary = "sellLegendary",
            ultimate = "sellUltimate",
        }
        inventoryAutomation.TIER_CFG = cfg
        local order = { "common", "uncommon", "rare", "epic", "legendary", "ultimate" }
        inventoryAutomation.TIER_ORDER = order
        local long, _ =
            {
                common = "Common",
                uncommon = "Uncommon",
                rare = "Rare",
                epic = "Epic",
                legendary = "Legendary",
                ultimate = "Ultimate",
            }, {
                common = "Com",
                uncommon = "Unc",
                rare = "Rare",
                epic = "Epic",
                legendary = "Leg",
                ultimate = "Ult",
            }
        inventoryAutomation.TIER_LONG = long
        local function l(u)
            if u == true then
                return true
            end
            if type(u) == "table" then
                for index2, entry in ipairs(order) do
                    if u[entry] == true then
                        return u
                    end
                end
            end
            return nil
        end
        inventoryAutomation.keptRule = function(u)
            local sellKeep = config.sellKeep
            if type(sellKeep) ~= "table" then
                return nil
            end
            return l(sellKeep[nameKey(u)])
        end
        inventoryAutomation.isKept = function(u, h)
            local m = inventoryAutomation.keptRule(u)
            if m == nil then
                return false
            end
            if m == true or h == nil then
                return true
            end
            return m[string.lower(tostring(h))] == true
        end
        inventoryAutomation.setKept = function(u, h)
            if type(config.sellKeep) ~= "table" then
                config.sellKeep = {}
            end
            local m = nameKey(u)
            if type(h) ~= "table" then
                config.sellKeep[m] = h and true or nil
                return
            end
            local c, u = {}, 0
            for index2, entry in ipairs(order) do
                if h[entry] == true then
                    u += 1
                    c[entry] = true
                else
                end
            end
            if u == #order then
                config.sellKeep[m] = true
            elseif u > 0 then
                config.sellKeep[m] = c
            else
                config.sellKeep[m] = nil
            end
        end
        inventoryAutomation.ruleText = function(c, u)
            if type(c) ~= "table" then
                return ""
            end
            local h = {}
            for index2, entry in ipairs(order) do
                if c[entry] == true then
                    h[#h + 1] = (u and _ or long)[entry]
                end
            end
            return table.concat(h, ", ")
        end
        inventoryAutomation.keptCount = function()
            local D = 0
            if type(config.sellKeep) == "table" then
                for key, entry in pairs(config.sellKeep) do
                    D = if l(entry) ~= nil then D + 1 else D
                end
            else
            end
            return D
        end
        inventoryAutomation.worn = nil
        inventoryAutomation.wornKey = function(D)
            local uniqueItemId = D.UniqueItemID
            if type(uniqueItemId) == "string" and uniqueItemId ~= "" and uniqueItemId ~= "none" then
                return "uid:" .. uniqueItemId
            end
            return "name:" .. string.lower(tostring(D.name))
        end
        inventoryAutomation.wornFile = function()
            local localPlayer = game:GetService("Players").LocalPlayer
            return "HarvardLabs/data/worn_"
                .. string.lower(localPlayer and localPlayer.Name or "unknown")
                .. ".json"
        end
        inventoryAutomation.wornLoad = function()
            if inventoryAutomation.worn then
                return inventoryAutomation.worn
            end
            inventoryAutomation.worn = {}
            pcall(function()
                if isfile and isfile(inventoryAutomation.wornFile()) then
                    local D = game:GetService("HttpService"):JSONDecode(readfile(inventoryAutomation.wornFile()))
                    if type(D) == "table" then
                        for key, entry in pairs(D) do
                            if type(key) == "string" and tonumber(entry) then
                                inventoryAutomation.worn[key] = tonumber(entry)
                            end
                        end
                    end
                end
            end)
            return inventoryAutomation.worn
        end
        inventoryAutomation.noteWorn = function(D)
            if type(D) ~= "table" then
                return
            end
            local P = inventoryAutomation.wornLoad()
            local timestamp, l = os.time(), false
            for key, entry in pairs(D.abilities or {}) do
                if
                    type(entry) == "table"
                    and type(entry.equipped) == "table"
                    and type(entry.name) == "string"
                then
                    key = false
                    for key2, entry2 in pairs(entry.equipped) do
                        key = if entry2 == true then true else key
                    end
                    local h = inventoryAutomation.wornKey(entry)
                    if key and (P[h] == nil or timestamp - P[h] > 600) then
                        P[h] = timestamp
                        l = true
                    else
                    end
                else
                end
            end
            if l then
                D = 2 * (tonumber(config.sellWornHours) or 24) * 3600
                for key3, entry3 in pairs(P) do
                    if timestamp - entry3 > D then
                        P[key3] = nil
                    end
                end
                pcall(function()
                    writefile(inventoryAutomation.wornFile(), game:GetService("HttpService"):JSONEncode(P))
                end)
            end
        end
        inventoryAutomation.wasWorn = function(D)
            local P = inventoryAutomation.wornLoad()[inventoryAutomation.wornKey(D)]
            return P ~= nil and os.time() - P <= (tonumber(config.sellWornHours) or 24) * 3600
        end
        inventoryAutomation.abilityFree = function(D)
            if
                type(D) ~= "table"
                or type(D.equipped) ~= "table"
                or type(D.name) ~= "string"
                or tonumber(D.levelReq) == nil
            then
                return false
            end
            for key, entry in pairs(D.equipped) do
                if entry == true then
                    return false
                end
            end
            return not inventoryAutomation.wasWorn(D)
        end
        inventoryAutomation.shouldSell = function(D)
            if type(D) ~= "table" then
                return false
            end
            local P = cfg[string.lower(tostring(D.rarity or ""))]
            if not P or config[P] ~= true then
                return false
            end
            if inventoryAutomation.isKept(D.name, D.rarity) then
                return false
            end
            local S, P = tonumber(D.levelReq), tonumber(config.sellKeepLevel) or 0
            if P > 0 and S and S >= P then
                return false
            end
            return true
        end
        local S = {
            {
                inv = "weapons",
                out = "weapon",
                pre = 8,
            },
            {
                inv = "helmets",
                out = "helmet",
                pre = 8,
            },
            {
                inv = "chests",
                out = "chest",
                pre = 7,
            },
            {
                inv = "abilities",
                out = "ability",
                pre = 9,
            },
        }
        inventoryAutomation.plan = function(D, P)
            local _, l, c, u =
                {
                    helmet = {},
                    ability = {},
                    chest = {},
                    weapon = {},
                }, {}, {}, {}
            pcall(function()
                local h = context.BG and context.BG.keepers
                if h then
                    u = context.BG.keepers(D) or {}
                end
            end)
            pcall(inventoryAutomation.noteWorn, D)
            local h = 0
            for index2, entry in ipairs(S) do
                local iteratePairs, q = pairs, D[entry.inv] or {}
                for key, entry2 in iteratePairs(q) do
                    index2 = entry.out == "ability" and inventoryAutomation.abilityFree(entry2)
                        or entry.out ~= "ability"
                            and type(entry2) == "table"
                            and entry2.equipped == false
                    local y = index2
                        and inventoryAutomation.shouldSell(entry2)
                        and not u[entry.inv .. ":" .. tostring(key)]
                    if y then
                        local u = tonumber(string.sub(tostring(key), entry.pre))
                            or tonumber(string.match(tostring(key), "(%d+)$"))
                        if u then
                            local m = _[entry.out]
                            if P then
                                m[#m + 1] = u
                            else
                                local P = type(entry2.UniqueItemID) == "string"
                                        and entry2.UniqueItemID ~= ""
                                        and entry2.UniqueItemID
                                    or "none"
                                m[#m + 1] = tostring(u) .. ":" .. P
                            end
                            h += 1
                            if type(entry2.UniqueItemID) == "string" and entry2.UniqueItemID ~= "" then
                                l[entry2.UniqueItemID] = true
                            end
                            c[#c + 1] = {
                                cat = entry.inv,
                                key = tostring(key),
                                id = u,
                                name = tostring(entry2.name),
                                rarity = tostring(entry2.rarity),
                                req = tonumber(entry2.levelReq),
                                price = tonumber(entry2.sellPrice),
                                uid = entry2.UniqueItemID,
                            }
                        else
                        end
                    else
                    end
                end
            end
            return _, h, l, c
        end
        inventoryAutomation.planList = function(D)
            local P, _ = {}, {}
            pcall(function()
                local l = context.BG and context.BG.keepers
                if l then
                    _ = context.BG.keepers(D) or {}
                end
            end)
            for index2, entry in ipairs(S) do
                local iteratePairs, u = pairs, D[entry.inv] or {}
                for key, entry2 in iteratePairs(u) do
                    index2 = entry.out == "ability" and inventoryAutomation.abilityFree(entry2)
                        or entry.out ~= "ability"
                            and type(entry2) == "table"
                            and entry2.equipped == false
                    local S = index2
                        and inventoryAutomation.shouldSell(entry2)
                        and not _[entry.inv .. ":" .. tostring(key)]
                    if S then
                        local S = tonumber(string.match(tostring(key), "%d+"))
                        if S then
                            P[#P + 1] = {
                                inv = entry.inv,
                                out = entry.out,
                                key = key,
                                id = S,
                                name = tostring(entry2.name or "?"),
                                uid = type(entry2.UniqueItemID) == "string"
                                        and entry2.UniqueItemID ~= ""
                                        and entry2.UniqueItemID
                                    or nil,
                            }
                        end
                    end
                end
            end
            return P
        end
        inventoryAutomation.logSale = function(S)
            local localPlayer = game:GetService("Players").LocalPlayer
            S.t, S.time, S.job, S.place = os.time(), os.date("%m/%d %I:%M:%S %p"), game.JobId, game.PlaceId
            local P, _ =
                game:GetService("HttpService"):JSONEncode(S) .. "\10",
                "HarvardLabs/logs/sales_"
                    .. string.lower(localPlayer and localPlayer.Name or "unknown")
                    .. ".jsonl"
            if appendfile and isfile and isfile(_) then
                appendfile(_, P)
            else
                writefile(_, P)
            end
        end
        local function S()
            local remotes = L:FindFirstChild("remotes")
            if not remotes then
                return nil, nil
            end
            return remotes:FindFirstChild("sellItemEvent"), remotes:FindFirstChild("reloadInvy")
        end
        inventoryAutomation.inLobby = function()
            return game.PlaceId == 77649408247578
        end
        inventoryAutomation.sellNow = function()
            if context.isEvent and context.isEvent() then
                inventoryAutomation.note = "not in an event run - its bag is the event's class kits"
                return 0, false
            end
            local now = os.clock()
            while not (context.BG and context.BG.keepers) and os.clock() - now < 20 do
                task.wait(0.25)
            end
            if not (context.BG and context.BG.keepers) then
                inventoryAutomation.note = "waiting for Gear, Spells & Stats (the menu is still loading)"
                return 0, false
            end
            pcall(function()
                if context.BG and context.BG.beforeSale then
                    context.BG.beforeSale()
                end
            end)
            local D, P = S()
            if not D or not P then
                inventoryAutomation.note = "sell remotes are missing"
                return 0, false
            end
            local success, _ = pcall(function()
                return P:InvokeServer()
            end)
            if not success or type(_) ~= "table" then
                inventoryAutomation.note = "the inventory would not open"
                return 0, false
            end
            success = not inventoryAutomation.inLobby()
            local l, asked, u, items = inventoryAutomation.plan(_, success)
            inventoryAutomation.at = os.clock()
            if asked == 0 then
                inventoryAutomation.note = "nothing matched the rules"
                return 0, true
            end
            local success2, m, R =
                pcall, inventoryAutomation.logSale, {
                    phase = "selling",
                    where = success and "dungeon" or "lobby",
                    asked = asked,
                    items = items,
                }
            R.bestGear = context.BG
                    and context.BG.lastMoves
                    and os.time() - (context.BG.lastMoves.at or 0) < 120
                    and context.BG.lastMoves.list
                or nil
            success2(m, R)
            if success then
                inventoryAutomation.note = ("selling %d item%s in the dungeon"):format(
                    asked,
                    asked == 1 and "" or "s"
                )
                for key, entry in pairs(l) do
                    if context.RT and context.RT.destroyed then
                        break
                    end
                    for index2, entry2 in ipairs(entry) do
                        if context.RT and context.RT.destroyed then
                            break
                        end
                        local q = {
                            helmet = {},
                            ability = {},
                            chest = {},
                            weapon = {},
                            [key] = {
                                entry2,
                            },
                        }
                        pcall(function()
                            D:FireServer(q)
                        end)
                        task.wait(tonumber(config.sellDelay) or 1)
                    end
                end
            elseif not pcall(function()
                D:FireServer(l)
            end) then
                inventoryAutomation.note = "the sell remote refused"
                return 0, false
            end
            task.wait(tonumber(config.sellCheckAfter) or 2)
            R = nil
            success2, now = pcall(function()
                return P:InvokeServer()
            end)
            if success2 and type(now) == "table" then
                items = 0
                for entry3 in pairs(u) do
                    items += 1
                end
                if items == asked then
                    m, success = { "weapons", "helmets", "chests", "abilities" }, 0
                    for index3, entry4 in ipairs(m) do
                        for key2, entry5 in pairs(now[entry4] or {}) do
                            success = if type(entry5) == "table" and u[entry5.UniqueItemID]
                                then success + 1
                                else success
                        end
                    end
                    R = asked - success
                else
                    local S, S = inventoryAutomation.plan(now)
                    R = math.max(0, asked - S)
                end
            else
            end
            if R == nil then
                inventoryAutomation.note = ("asked to sell %d; the bag would not open to check"):format(asked)
                return 0, true
            end
            inventoryAutomation.lastSold, inventoryAutomation.totalSold = R, inventoryAutomation.totalSold + R
            pcall(inventoryAutomation.logSale, {
                phase = "sold",
                gone = R,
                asked = asked,
            })
            if R == 0 then
                inventoryAutomation.note = ("the game sold nothing (%d asked)"):format(asked)
                if context.log then
                    context.log("AutoSell", inventoryAutomation.note)
                end
                if context.notify then
                    context.notify("warning", "Auto sell", ("The game sold nothing (%d asked)."):format(asked))
                end
                return 0, true
            end
            inventoryAutomation.note = ("sold %d item%s"):format(R, R == 1 and "" or "s")
                .. (R < asked and (" of %d asked"):format(asked) or "")
                .. (inventoryAutomation.inLobby() and " in the lobby" or " in the dungeon")
            if context.log then
                context.log("AutoSell", inventoryAutomation.note)
            end
            if context.notify then
                context.notify("sell", "Auto sell", ("Sold %d item%s."):format(R, R == 1 and "" or "s"))
            end
            return R, true
        end
        local httpService = game:GetService("HttpService")
        local function S()
            local localPlayer = game:GetService("Players").LocalPlayer
            return "HarvardLabs/data/sellgames_" .. (localPlayer and localPlayer.Name or "unknown") .. ".json"
        end
        local D
        local function P()
            local _ = D
            if _ then
                local l = D
                return l
            end
            D = {
                games = 0,
                job = "",
            }
            pcall(function()
                local l = isfile and isfile(S())
                if l then
                    local l = httpService:JSONDecode(readfile(S()))
                    local c = type(l) == "table"
                    if c then
                        local c, u, games, job = D, D, tonumber(l.games) or 0, tostring(l.job or "")
                        c.games = games
                        u.job = job
                    end
                end
            end)
            _ = D
            return _
        end
        local function D()
            pcall(function()
                writefile(S(), httpService:JSONEncode(P()))
            end)
        end
        inventoryAutomation.games = function()
            return P().games
        end
        inventoryAutomation.sellAfter = function()
            return math.clamp(math.floor(tonumber(config.sellAfterGames) or 10), 1, 50)
        end
        inventoryAutomation.sellDue = function()
            return config.autoSell == true and P().games >= inventoryAutomation.sellAfter()
        end
        inventoryAutomation.lobbyJob = nil
        inventoryAutomation.busy = false
        inventoryAutomation.holdStart = function()
            if
                config.autoSell ~= true
                or not inventoryAutomation.inLobby()
                or context.RT and context.RT.modHalt
            then
                return false
            end
            if not (inventoryAutomation.busy or inventoryAutomation.lobbyJob ~= game.JobId) then
                return false
            end
            if inventoryAutomation.holdJob ~= game.JobId then
                inventoryAutomation.holdJob, inventoryAutomation.holdSince = game.JobId, os.clock()
            end
            if os.clock() - inventoryAutomation.holdSince > (tonumber(config.sellHoldMax) or 45) then
                inventoryAutomation.note = "the sale took too long - the run starts anyway"
                return false
            end
            return true
        end
        task.spawn(function()
            local L
            while not (context.RT and context.RT.destroyed) do
                task.wait(1)
                pcall(function()
                    local S = inventoryAutomation.inLobby()
                    if S then
                        if inventoryAutomation.lobbyJob == game.JobId then
                            return
                        end
                        if config.autoSell ~= true then
                            inventoryAutomation.note = "off"
                            inventoryAutomation.lobbyJob = game.JobId
                            return
                        end
                        if context.RT and context.RT.modHalt then
                            inventoryAutomation.note = "held by mod detection"
                            return
                        end
                        L = L or os.clock()
                        local success = os.clock() - L
                        if success < (tonumber(config.sellLobbySettle) or 2) then
                            return
                        end
                        local localPlayer, l = game:GetService("Players").LocalPlayer, os.clock() - L
                        if l < (tonumber(config.sellLobbyMin) or 10) then
                            return
                        end
                        l = localPlayer and (localPlayer:FindFirstChild("leaderstats"))
                        success = l and (l:FindFirstChild("Level"))
                        l = not (success and (tonumber(success.Value) or 0) > 1)
                        if l then
                            success = os.clock() - L
                            if success < (tonumber(config.sellLoadWait) or 30) then
                                return
                            end
                            inventoryAutomation.note =
                                "this lobby never showed the account's level - no sale here"
                            inventoryAutomation.lobbyJob = game.JobId
                            return
                        end
                        if inventoryAutomation.busy then
                            return
                        end
                        inventoryAutomation.busy = true
                        success, localPlayer, l = pcall(inventoryAutomation.sellNow)
                        inventoryAutomation.busy = false
                        inventoryAutomation.lobbyJob = game.JobId
                        if success and l then
                            P().games = 0
                            D()
                        end
                    else
                        L = nil
                        if context.isEvent and context.isEvent() then
                            if config.autoSell == true then
                                inventoryAutomation.note =
                                    "not in an event run - its bag is the event's class kits"
                            end
                            return
                        end
                        local dungeonName, dungeonStarted =
                            workspace:FindFirstChild("dungeonName"), workspace:FindFirstChild("dungeonStarted")
                        if
                            dungeonName
                            and tostring(dungeonName.Value) ~= ""
                            and dungeonStarted
                            and dungeonStarted.Value == true
                            and P().job ~= game.JobId
                        then
                            P().job = game.JobId
                            P().games = P().games + 1
                            D()
                            if config.autoSell == true then
                                inventoryAutomation.note = ("%d of %d games played"):format(
                                    P().games,
                                    inventoryAutomation.sellAfter()
                                )
                            end
                        end
                        if
                            config.autoSell == true
                            and dungeonName
                            and tostring(dungeonName.Value) ~= ""
                            and dungeonStarted
                            and dungeonStarted.Value == true
                            and P().games >= inventoryAutomation.sellAfter()
                            and inventoryAutomation.soldJob ~= game.JobId
                            and not inventoryAutomation.busy
                            and not (context.RT and context.RT.modHalt)
                        then
                            inventoryAutomation.soldJob = game.JobId
                            inventoryAutomation.busy = true
                            local success2, Q, Q = pcall(inventoryAutomation.sellNow)
                            inventoryAutomation.busy = false
                            if success2 and Q then
                                P().games = 0
                                D()
                            end
                        end
                    end
                end)
            end
        end)
    end

components.inventoryAutomation(context)

----------------------------------------------------------------------
-- UIKit (nguyên bản)
----------------------------------------------------------------------
    components.uiLibrary = function(context)
        local runtimeState, config, localPlayer, userInputService =
            context.RT, context.CFG, context.LocalPlayer, context.UserInputService
        local runService = context.RunService
        local theme, fontFamilies =
            {
                TextPrimary = Color3.fromHex("f0f0f4"),
                TextSub = Color3.fromHex("9898a2"),
                TextMuted = Color3.fromHex("686872"),
                TextOnAccent = Color3.fromHex("000000"),
                StatusBad = Color3.fromHex("D50000"),
                StatusGood = Color3.fromHex("2FBF71"),
                SurfaceHeader = Color3.fromHex("18181c"),
                SurfaceElement = Color3.fromHex("26262c"),
                SurfaceHover = Color3.fromHex("303038"),
                SurfaceField = Color3.fromHex("1c1c21"),
                SurfaceSection = Color3.fromHex("1e1e24"),
                SurfaceWell = Color3.fromHex("121216"),
                SurfaceChip = Color3.fromHex("0c0c0f"),
                Hairline = Color3.fromHex("323338"),
                BodyTop = Color3.fromHex("2a2a2f"),
                BodyMid = Color3.fromHex("1a1a1e"),
                BodyBot = Color3.fromHex("101013"),
                BodyTopA = 0.05,
                BodyMidA = 0.13,
                BodyBotA = 0.42,
                SweepSpeed = 0.22,
                AccentA = Color3.fromHex("A30000"),
                AccentMid = Color3.fromHex("F43120"),
                AccentB = Color3.fromHex("D50000"),
                AccentDark = Color3.fromHex("7A0000"),
                RadiusSm = 5,
                RadiusMd = 6,
                RadiusLg = 8,
                GapSm = 6,
                GapMd = 8,
                GapLg = 12,
                GapXl = 14,
                RowH = 34,
                HeaderH = 40,
            }, {
                sans = "rbxasset://fonts/families/Montserrat.json",
                mono = "rbxasset://fonts/families/RobotoMono.json",
            }
        local P = {
            [Enum.FontWeight.Regular] = Enum.Font.Gotham,
            [Enum.FontWeight.Medium] = Enum.Font.GothamMedium,
            [Enum.FontWeight.SemiBold] = Enum.Font.GothamBold,
            [Enum.FontWeight.Bold] = Enum.Font.GothamBold,
        }
        local function setFont(l, c, u)
            if not pcall(function()
                l.FontFace = Font.new(fontFamilies[c], u)
            end) then
                l.Font = P[u] or Enum.Font.Gotham
            end
        end
        local D = {
            windowTitle = {
                family = "sans",
                weight = Enum.FontWeight.SemiBold,
                size = 15,
                color = "TextPrimary",
            },
            windowChip = {
                family = "sans",
                weight = Enum.FontWeight.Bold,
                size = 15,
                color = "TextPrimary",
            },
            rowLabel = {
                family = "sans",
                weight = Enum.FontWeight.Medium,
                size = 13,
                color = "TextPrimary",
            },
            rowButton = {
                family = "sans",
                weight = Enum.FontWeight.SemiBold,
                size = 13,
                color = "TextOnAccent",
            },
            rowEntry = {
                family = "sans",
                weight = Enum.FontWeight.SemiBold,
                size = 13,
                color = "TextPrimary",
            },
            rowStat = {
                family = "sans",
                weight = Enum.FontWeight.Medium,
                size = 14,
                color = "TextPrimary",
            },
            captionKey = {
                family = "sans",
                weight = Enum.FontWeight.Medium,
                size = 12,
                color = "TextSub",
            },
            captionSub = {
                family = "sans",
                weight = Enum.FontWeight.Regular,
                size = 10,
                color = "TextMuted",
            },
            captionStat = {
                family = "sans",
                weight = Enum.FontWeight.Bold,
                size = 12,
                color = "TextSub",
            },
            monoValue = {
                family = "mono",
                weight = Enum.FontWeight.Medium,
                size = 11,
                color = "TextOnAccent",
            },
            monoMeta = {
                family = "mono",
                weight = Enum.FontWeight.Medium,
                size = 10,
                color = "TextMuted",
            },
            monoStat = {
                family = "mono",
                weight = Enum.FontWeight.Medium,
                size = 13,
                color = "TextSub",
            },
        }
        local function corner(parent, c)
            local corner2 = Instance.new("UICorner")
            corner2.CornerRadius = UDim.new(0, c)
            corner2.Parent = parent
            return corner2
        end
        local function stroke(parent, u, h)
            local stroke2 = Instance.new("UIStroke")
            stroke2.Color = u or theme.Hairline
            stroke2.Thickness = h or 1
            stroke2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke2.Parent = parent
            return stroke2
        end
        local function pad(parent, h, m, R, y)
            local padding = Instance.new("UIPadding")
            padding.PaddingTop = UDim.new(0, h)
            padding.PaddingRight = UDim.new(0, m)
            padding.PaddingBottom = UDim.new(0, R)
            padding.PaddingLeft = UDim.new(0, y)
            padding.Parent = parent
            return padding
        end
        local function vlist(parent, m, R)
            local listLayout = Instance.new("UIListLayout")
            listLayout.FillDirection = Enum.FillDirection.Vertical
            listLayout.Padding = UDim.new(0, m or theme.GapSm)
            listLayout.SortOrder = R or Enum.SortOrder.LayoutOrder
            listLayout.Parent = parent
            return listLayout
        end
        local function flexFill(m, R, y, q)
            if not R then
                return false
            end
            m.Size = UDim2.new(1, -R, y or 1, q or 0)
            return true
        end
        local function hlist(parent, y)
            local listLayout = Instance.new("UIListLayout")
            listLayout.FillDirection = Enum.FillDirection.Horizontal
            listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
            listLayout.Padding = UDim.new(0, y or theme.GapMd)
            listLayout.SortOrder = Enum.SortOrder.LayoutOrder
            listLayout.Parent = parent
            return listLayout
        end
        local function label(parent, q, V, E)
            local p, label2 = D[V] or D.rowLabel, Instance.new("TextLabel")
            label2.BackgroundTransparency = 1
            label2.Text = q or ""
            label2.TextColor3 = theme[p.color]
            label2.TextSize = p.size
            label2.TextXAlignment = Enum.TextXAlignment.Left
            label2.TextYAlignment = Enum.TextYAlignment.Center
            label2.LayoutOrder = E or 1
            label2.Size = UDim2.new(1, 0, 1, 0)
            setFont(label2, p.family, p.weight)
            label2.Parent = parent
            return label2
        end
        local function accentGradient(parent, q)
            local gradient = Instance.new("UIGradient")
            gradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, theme.AccentA),
                ColorSequenceKeypoint.new(0.53, theme.AccentMid),
                ColorSequenceKeypoint.new(1, theme.AccentB),
            })
            gradient.Rotation = q or 0
            gradient.Parent = parent
            return gradient
        end
        local y, connection = {}
        local function accentSweep(parent)
            parent.ClipsDescendants = true
            local sweep = Instance.new("Frame")
            sweep.Name = "Sweep"
            sweep.BackgroundColor3 = Color3.new(1, 1, 1)
            sweep.BorderSizePixel = 0
            sweep.Size = UDim2.new(2, 0, 1, 0)
            sweep.Position = UDim2.new(-1, 0, 0, 0)
            sweep.ZIndex = parent.ZIndex
            sweep.Parent = parent
            parent = Instance.new("UIGradient")
            parent.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, theme.AccentA),
                ColorSequenceKeypoint.new(0.125, theme.AccentMid),
                ColorSequenceKeypoint.new(0.25, theme.AccentB),
                ColorSequenceKeypoint.new(0.375, theme.AccentMid),
                ColorSequenceKeypoint.new(0.5, theme.AccentA),
                ColorSequenceKeypoint.new(0.625, theme.AccentMid),
                ColorSequenceKeypoint.new(0.75, theme.AccentB),
                ColorSequenceKeypoint.new(0.875, theme.AccentMid),
                ColorSequenceKeypoint.new(1, theme.AccentA),
            })
            parent.Parent = sweep
            y[#y + 1] = sweep
            parent = not connection
            if parent then
                connection = runService.RenderStepped:Connect(function()
                    local E = os.clock() * (theme.SweepSpeed or 0.22) % 1
                    local position = UDim2.new(E - 1, 0, 0, 0)
                    for index = #y, 1, -1 do
                        E = y[index]
                        if E.Parent then
                            E.Position = position
                        else
                            table.remove(y, index)
                        end
                    end
                end)
            end
            return sweep
        end
        local function stopSweeps()
            local connection2 = connection
            if connection2 then
                pcall(function()
                    connection:Disconnect()
                end)
                connection = nil
            end
            for index = #y, 1, -1 do
                y[index] = nil
            end
        end
        local function bodyGradient(parent)
            local gradient = Instance.new("UIGradient")
            gradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, theme.BodyTop),
                ColorSequenceKeypoint.new(0.45, theme.BodyMid),
                ColorSequenceKeypoint.new(1, theme.BodyBot),
            })
            gradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, theme.BodyTopA),
                NumberSequenceKeypoint.new(0.45, theme.BodyMidA),
                NumberSequenceKeypoint.new(1, theme.BodyBotA),
            })
            gradient.Rotation = 90
            gradient.Parent = parent
            return gradient
        end
        local function shadow(p, j, U, J, w, Y)
            j, U, J, w, Y = j or 8, U or 1.5, J or 10, w or 0.04, Y or theme.RadiusLg
            local parent = Instance.new("Frame")
            parent.Name = (p.Name or "Window") .. "Shadow"
            parent.BackgroundTransparency = 1
            parent.ZIndex = math.max(p.ZIndex - 1, 0)
            local function frame()
                parent.Position, parent.Size, parent.AnchorPoint, parent.Visible =
                    p.Position, p.Size, p.AnchorPoint, p.Visible
            end
            frame()
            parent.Parent = p.Parent
            local Z = { "Position", "Size", "AnchorPoint", "Visible" }
            for index, entry in ipairs(Z) do
                p:GetPropertyChangedSignal(entry):Connect(frame)
            end
            local function n()
                if not p.Parent then
                    parent:Destroy()
                elseif parent.Parent ~= p.Parent then
                    parent.Parent = p.Parent
                end
            end
            p.AncestryChanged:Connect(n)
            for index2 = 1, j, 1 do
                Z, n, frame = index2 * U, J * (index2 / j), Instance.new("Frame")
                frame.Name = "L" .. index2
                frame.BackgroundColor3 = Color3.new(0, 0, 0)
                frame.BackgroundTransparency = 1 - w
                frame.BorderSizePixel = 0
                frame.ZIndex = p.ZIndex - 1
                frame.Position = UDim2.fromOffset(-Z, -Z + n)
                frame.Size = UDim2.new(1, Z * 2, 1, Z * 2)
                corner(frame, Y + Z)
                frame.Parent = parent
            end
            return parent
        end
        local p = {
            frame = nil,
            label = nil,
            target = nil,
            showAt = nil,
            conn = nil,
        }
        local function ensureTip(U)
            if p.frame and p.frame.Parent then
                return
            end
            local tooltip = Instance.new("Frame")
            tooltip.Name = "Tooltip"
            tooltip.BackgroundColor3 = Color3.fromHex("3a3a42")
            tooltip.BorderSizePixel = 0
            tooltip.Visible = false
            tooltip.ZIndex = 500
            tooltip.AutomaticSize = Enum.AutomaticSize.XY
            tooltip.Size = UDim2.fromOffset(0, 0)
            tooltip.Parent = U
            corner(tooltip, theme.RadiusSm)
            stroke(tooltip, Color3.fromHex("4a4a55"), 1)
            pad(tooltip, 6, 8, 6, 8)
            U = Instance.new("TextLabel")
            U.BackgroundTransparency = 1
            U.AutomaticSize = Enum.AutomaticSize.XY
            U.Size = UDim2.fromOffset(0, 0)
            U.TextWrapped = true
            U.TextXAlignment = Enum.TextXAlignment.Left
            U.TextYAlignment = Enum.TextYAlignment.Top
            U.TextColor3 = Color3.fromHex("e8e8ee")
            U.TextSize = 11
            U.ZIndex = 501
            setFont(U, "sans", Enum.FontWeight.Medium)
            U.Parent = tooltip
            local w = Instance.new("UISizeConstraint")
            w.MaxSize = Vector2.new(240, math.huge)
            w.Parent = U
            p.frame = tooltip
            p.label = U
            if p.conn then
                p.conn:Disconnect()
            end
            p.conn = runService.RenderStepped:Connect(function()
                if not p.target then
                    return
                end
                local O = os.clock()
                if not p.frame.Visible then
                    if O < p.showAt then
                        return
                    end
                    p.frame.Visible = true
                    local tweenService, stroke2 =
                        game:GetService("TweenService"), p.frame:FindFirstChildOfClass("UIStroke")
                    p.frame.BackgroundTransparency, p.label.TextTransparency = 1, 1
                    if stroke2 then
                        stroke2.Transparency = 1
                        tweenService
                            :Create(stroke2, TweenInfo.new(0.16), {
                                Transparency = 0,
                            })
                            :Play()
                    end
                    tweenService
                        :Create(p.frame, TweenInfo.new(0.16), {
                            BackgroundTransparency = 0,
                        })
                        :Play()
                    tweenService
                        :Create(p.label, TweenInfo.new(0.16), {
                            TextTransparency = 0,
                        })
                        :Play()
                end
                local vector, J = userInputService:GetMouseLocation(), workspace.CurrentCamera
                local vector2, Y, v =
                    J and J.ViewportSize or Vector2.new(1920, 1080),
                    p.frame.AbsoluteSize.X,
                    p.frame.AbsoluteSize.Y
                O, J =
                    vector.X + 16 + Y > vector2.X and vector.X - 16 - Y or vector.X + 16,
                    vector.Y + 18 + v > vector2.Y and vector.Y - 12 - v or vector.Y + 18
                p.frame.Position = UDim2.fromOffset(O, J)
            end)
        end
        local function hideTip()
            p.target = nil
            if p.frame then
                p.frame.Visible = false
            end
        end
        local U = {}
        context.tipTextOf = function(J)
            return U[J]
        end
        local function tip(target, text)
            if not text or text == "" then
                return target
            end
            U[target] = text
            local function v()
                U[target] = nil
            end
            target.Destroying:Connect(v)
            local function U()
                if not p.frame then
                    return
                end
                p.target = target
                p.showAt = os.clock() + 0.45
                p.frame.Visible = false
                p.label.Text = text
            end
            target.MouseEnter:Connect(U)
            local function U()
                if p.target == target then
                    hideTip()
                end
            end
            target.MouseLeave:Connect(U)
            local function U()
                if not target:IsDescendantOf(game) and p.target == target then
                    hideTip()
                end
            end
            target.AncestryChanged:Connect(U)
            return target
        end
        local p = {
            plus = 10734924532,
            x = 10747384394,
            pin = 10734922324,
            info = 10723415903,
            check = 10709790644,
            ["chevron-down"] = 10709790948,
            ["chevron-up"] = 10709791523,
            ["chevron-left"] = 10709791281,
            ["chevron-right"] = 10709791437,
            crown = 10709818626,
            ["trash-2"] = 10747362241,
            swords = 10734975692,
            eye = 10723346959,
            bell = 10709775704,
            coins = 10709811110,
            users = 10747373426,
            palette = 10734910430,
            map = 10734886202,
            camera = 10709789686,
            bug = 10709782845,
            search = 10734943674,
            ["alert-triangle"] = 10709753149,
            shield = 10734951847,
        }
        local function icon(parent, Y, v, M, zIndex)
            local image = Instance.new("ImageLabel")
            image.Name = "Icon_" .. tostring(Y)
            image.BackgroundTransparency = 1
            image.BorderSizePixel = 0
            image.Image = "rbxassetid://" .. tostring(p[Y] or p.info)
            image.ImageColor3 = M or theme.TextSub
            image.ScaleType = Enum.ScaleType.Fit
            image.Size = UDim2.fromOffset(v or 16, v or 16)
            if zIndex then
                image.ZIndex = zIndex
            end
            image.Parent = parent
            return image
        end
        local function chevron(parent)
            local chevron2 = Instance.new("Frame")
            chevron2.Name = "Chevron"
            chevron2.BackgroundTransparency = 1
            chevron2.Size = UDim2.fromOffset(16, 16)
            chevron2.LayoutOrder = 99
            chevron2.Parent = parent
            local Y = icon(chevron2, "chevron-down", 16, theme.TextSub)
            Y.AnchorPoint, Y.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
            return {
                frame = chevron2,
                setOpen = function(v)
                    Y.Rotation = v and 180 or 0
                    Y.ImageColor3 = v and theme.AccentMid or theme.TextSub
                end,
            }
        end
        local guiService = game:GetService("GuiService")
        local function v(M)
            local Z = M
            while Z and not (Z.GetAttribute and Z:GetAttribute("hlWin")) do
                Z = Z.Parent
            end
            return Z
        end
        local function M(Z)
            local parent = Z.Parent
            return Z.ZIndex * 100000 + (parent and table.find(parent:GetChildren(), Z) or 0)
        end
        local function Z(n)
            if n and n.UserInputType == Enum.UserInputType.Touch then
                local vector = guiService:GetGuiInset()
                return n.Position.X + vector.X, n.Position.Y + vector.Y
            end
            n = userInputService:GetMouseLocation()
            return n.X, n.Y
        end
        local function Y(n, f, r)
            local o, A
            for index, child in ipairs(r:GetChildren()) do
                if child:IsA("GuiObject") and child.Visible and child:GetAttribute("hlWin") then
                    local absolutePosition, absoluteSize = child.AbsolutePosition, child.AbsoluteSize
                    if
                        n >= absolutePosition.X
                        and f >= absolutePosition.Y
                        and n <= absolutePosition.X + absoluteSize.X
                        and f <= absolutePosition.Y + absoluteSize.Y
                    then
                        index = M(child)
                        if not o or index > o then
                            o, A = index, child
                        else
                        end
                    else
                    end
                else
                end
            end
            return A
        end
        local function contextPressOnTop(f, r)
            local o = v(f)
            if not (o and o.Parent) then
                return true
            end
            local v, A = Z(r)
            f = Y(v, A, o.Parent)
            return f == nil or f == o
        end
        context.pressOnTop = contextPressOnTop
        local function row(parent, f, r, o, A)
            local row2 = Instance.new("Frame")
            row2.Name = "Row"
            row2.BackgroundColor3 = theme.SurfaceElement
            row2.BorderSizePixel = 0
            row2.Size = UDim2.new(1, 0, 0, o or theme.RowH)
            row2.LayoutOrder = r or 1
            row2.Parent = parent
            corner(row2, theme.RadiusMd)
            stroke(row2, theme.Hairline, 1)
            pad(row2, 0, theme.GapLg, 0, theme.GapLg)
            parent, r = hlist(row2, theme.GapMd), label(row2, f, "rowLabel", 1)
            r.Size = UDim2.new(1, 0, 1, 0)
            r.TextTruncate = Enum.TextTruncate.AtEnd
            flexFill(r, A or 24)
            return row2, r, parent
        end
        local function hoverable(f, r)
            local backgroundColor3 = f.BackgroundColor3
            local tweenService = game:GetService("TweenService")
            local function k()
                if contextPressOnTop(f) then
                    tweenService
                        :Create(f, TweenInfo.new(0.14, Enum.EasingStyle.Quint), {
                            BackgroundColor3 = theme.SurfaceHover,
                        })
                        :Play()
                end
            end
            f.MouseEnter:Connect(k)
            local function k()
                tweenService
                    :Create(f, TweenInfo.new(0.2, Enum.EasingStyle.Quint), {
                        BackgroundColor3 = backgroundColor3,
                    })
                    :Play()
            end
            f.MouseLeave:Connect(k)
            if not r then
                return nil
            end
            f.Active = true
            return {
                onClick = function(r)
                    local function o(input)
                        if
                            (
                                input.UserInputType == Enum.UserInputType.MouseButton1
                                or input.UserInputType == Enum.UserInputType.Touch
                            ) and contextPressOnTop(f, input)
                        then
                            r()
                        end
                    end
                    f.InputBegan:Connect(o)
                end,
            }
        end
        local function toggle(r, o, A, k, x, a)
            local e = row(r, o, x, nil, 46)
            local r, track = hoverable(e, true), Instance.new("Frame")
            track.Name = "Track"
            track.BackgroundColor3 = theme.SurfaceField
            track.BorderSizePixel = 0
            track.Size = UDim2.fromOffset(38, 20)
            track.LayoutOrder = 2
            track.Parent = e
            corner(track, 10)
            local x = stroke(track, theme.Hairline, 1)
            local N = accentGradient(track, 0)
            N.Enabled = false
            local knob = Instance.new("Frame")
            knob.Name = "Knob"
            knob.BackgroundColor3 = theme.TextMuted
            knob.BorderSizePixel = 0
            knob.Size = UDim2.fromOffset(14, 14)
            knob.Position = UDim2.fromOffset(2, 3)
            knob.ZIndex = 2
            corner(knob, 7)
            knob.Parent = track
            local F = false
            local function render()
                local enabled = A() and true or false
                N.Enabled = enabled
                track.BackgroundColor3 = enabled and Color3.new(1, 1, 1) or theme.SurfaceField
                x.Transparency = enabled and 1 or 0
                knob.BackgroundColor3 = enabled and theme.TextOnAccent or theme.TextMuted
                local position = UDim2.fromOffset(enabled and 22 or 2, 3)
                enabled = F and knob.Position ~= position and knob:IsDescendantOf(game)
                if enabled then
                    game:GetService("TweenService")
                        :Create(knob, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                            Position = position,
                        })
                        :Play()
                else
                    knob.Position = position
                end
                F = true
            end
            render()
            r.onClick(function()
                k(not A())
                render()
            end)
            tip(e, a)
            return {
                row = e,
                render = render,
            }
        end
        local function r(o, A, k, x)
            if context.COMPACT ~= true then
                return false
            end
            local a, e = A - o, k or (x and 0.1 or 1)
            return a / e > 60
        end
        local function o(A, k, x, a, e)
            A = math.clamp(A, k, x)
            A = if e
                then math.floor(A / e + 0.5) * e
                else if a then math.floor(A * 10 + 0.5) / 10 else math.floor(A + 0.5)
            return math.clamp(A, k, x)
        end
        local function A(k, x)
            if x then
                return string.format("%.1f", k)
            end
            return tostring(math.floor(k + 0.5))
        end
        local function k(textControl)
            return tonumber((string.gsub(textControl.Text, "[^%d%.%-]", "")))
        end
        local function x(parent, e, layoutOrder)
            local number = Instance.new("TextBox")
            number.Name = "Number"
            number.BackgroundColor3 = theme.SurfaceField
            number.BorderSizePixel = 0
            number.Size = UDim2.fromOffset(e, 24)
            number.LayoutOrder = layoutOrder
            number.TextColor3 = theme.TextPrimary
            number.TextSize = 12
            number.ClearTextOnFocus = false
            number.TextXAlignment = Enum.TextXAlignment.Center
            setFont(number, "sans", Enum.FontWeight.SemiBold)
            number.Parent = parent
            corner(number, theme.RadiusSm)
            stroke(number, theme.Hairline, 1)
            return number
        end
        local function a(e, N, I, F)
            local C = label(e, tostring(N or ""):gsub("^%s+", ""), "captionSub", F)
            C.Size = UDim2.fromOffset(I, 24)
            C.TextXAlignment = Enum.TextXAlignment.Left
            return C
        end
        local function e(N, I, F, C, g, i, b, B, G, z, s)
            local holder = row(N, I, G, nil, 136)
            local textControl = x(holder, 80, 2)
            a(holder, F, 40, 3)
            local function render()
                textControl.Text = A(tonumber(b()) or C, i)
            end
            local function F()
                local b = k(textControl)
                if b then
                    B(o(b, C, g, i, s))
                end
                render()
            end
            textControl.FocusLost:Connect(F)
            render()
            tip(holder, z)
            return {
                holder = holder,
                render = render,
            }
        end
        local function N(I, F, C, g, i, b, B, G, z)
            local holder = row(I, F, G, nil, 200)
            local textControl = x(holder, 58, 2)
            I = label(holder, "to", "captionSub", 3)
            I.Size, I.TextXAlignment = UDim2.fromOffset(16, 24), Enum.TextXAlignment.Center
            local textControl2 = x(holder, 58, 4)
            a(holder, C, 36, 5)
            local function render()
                local a, C = b()
                textControl.Text, textControl2.Text = A(tonumber(a) or g), A(tonumber(C) or i)
            end
            local function A()
                local a, C = b()
                local b, G =
                    o(k(textControl) or tonumber(a) or g, g, i), o(k(textControl2) or tonumber(C) or i, g, i)
                if b > G then
                    b, G = G, b
                else
                end
                B(b, G)
                render()
            end
            textControl.FocusLost:Connect(A)
            textControl2.FocusLost:Connect(A)
            render()
            tip(holder, z)
            return {
                holder = holder,
                render = render,
            }
        end
        local function slider(head, k, x, a, I, F, C, g, i, b, B)
            if r(a, I, B, F) then
                return e(head, k, x, a, I, F, C, g, i, b, B)
            end
            local slider2 = Instance.new("Frame")
            slider2.Name = "Slider"
            slider2.BackgroundTransparency = 0
            slider2.BackgroundColor3 = theme.SurfaceElement
            slider2.BorderSizePixel = 0
            slider2.AutomaticSize = Enum.AutomaticSize.Y
            slider2.Size = UDim2.new(1, 0, 0, 0)
            slider2.LayoutOrder = i or 1
            slider2.Parent = head
            corner(slider2, theme.RadiusMd)
            stroke(slider2, theme.Hairline, 1)
            pad(slider2, 7, 12, 9, 12)
            vlist(slider2, theme.GapSm)
            head = Instance.new("Frame")
            head.Name = "Head"
            head.BackgroundTransparency = 1
            head.AutomaticSize = Enum.AutomaticSize.Y
            head.Size = UDim2.new(1, 0, 0, 0)
            head.LayoutOrder = 1
            head.Parent = slider2
            vlist(head, 1)
            label(head, k, "rowLabel", 1).Size = UDim2.new(1, 0, 0, 18)
            if x and x ~= "" then
                label(head, x, "captionSub", 2).Size = UDim2.new(1, 0, 0, 12)
            end
            local track = Instance.new("Frame")
            track.Name = "Track"
            track.BackgroundColor3 = theme.SurfaceField
            track.BorderSizePixel = 0
            track.Size = UDim2.new(1, 0, 0, 18)
            track.ClipsDescendants = true
            track.LayoutOrder = 2
            track.Active = true
            track.Parent = slider2
            corner(track, theme.RadiusSm)
            stroke(track, theme.Hairline, 1)
            local fill = Instance.new("Frame")
            fill.Name = "Fill"
            fill.BackgroundColor3 = Color3.new(1, 1, 1)
            fill.BorderSizePixel = 0
            fill.Size = UDim2.fromScale(0, 1)
            fill.Parent = track
            corner(fill, theme.RadiusSm)
            accentGradient(fill, 0)
            local value = Instance.new("TextLabel")
            value.Name = "Value"
            value.BackgroundTransparency = 1
            value.Size = UDim2.new(1, -8, 1, 0)
            value.Position = UDim2.fromOffset(0, 0)
            value.TextXAlignment = Enum.TextXAlignment.Right
            value.TextColor3 = theme.TextOnAccent
            value.TextSize = 11
            value.ZIndex = 3
            setFont(value, "mono", Enum.FontWeight.Medium)
            value.Parent = fill
            local function i(G)
                if B then
                    return (string.format("%.3f", G):gsub("0+$", ""):gsub("%.$", ""))
                end
                if F then
                    return string.format("%.1f", G)
                end
                return tostring(math.floor(G + 0.5))
            end
            local function render()
                local z = C()
                local C = math.clamp((z - a) / (I - a), 0, 1)
                fill.Size = UDim2.fromScale(C, 1)
                value.Text = i(z)
                if C < 0.22 then
                    value.Parent = track
                    value.Size = UDim2.new(1, -8, 1, 0)
                    value.TextColor3 = theme.TextPrimary
                else
                    value.Parent = fill
                    value.Size = UDim2.new(1, -8, 1, 0)
                    value.TextColor3 = theme.TextOnAccent
                end
            end
            render()
            local k = false
            local function x(C)
                if track.AbsoluteSize.X <= 0 then
                    return
                end
                local i = math.clamp((C - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                C = a + (I - a) * i
                g(
                    if B
                        then math.floor(C / B + 0.5) * B
                        else if F then math.floor(C * 10 + 0.5) / 10 else math.floor(C + 0.5)
                )
                render()
            end
            track.InputBegan:Connect(function(input)
                if not contextPressOnTop(track, input) then
                    return
                end
                local A = input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch
                if A then
                    k = true
                    x(input.Position.X)
                end
            end)
            table.insert(
                context.sliderConnections,
                userInputService.InputChanged:Connect(function(input)
                    local a = k
                        and (
                            input.UserInputType == Enum.UserInputType.MouseMovement
                            or input.UserInputType == Enum.UserInputType.Touch
                        )
                    if a then
                        x(input.Position.X)
                    end
                end)
            )
            table.insert(
                context.sliderConnections,
                userInputService.InputEnded:Connect(function(input)
                    local x = input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch
                    if x then
                        k = false
                    end
                end)
            )
            tip(slider2, b)
            return {
                holder = slider2,
                render = render,
            }
        end
        local function rangeSlider(head, x, a, e, I, F, C, top, i, b)
            if r(e, I, nil, false) then
                return N(head, x, b, e, I, F, C, top, i)
            end
            local rangeSlider2 = Instance.new("Frame")
            rangeSlider2.Name = "RangeSlider"
            rangeSlider2.BackgroundTransparency = 0
            rangeSlider2.BackgroundColor3 = theme.SurfaceElement
            rangeSlider2.BorderSizePixel = 0
            rangeSlider2.AutomaticSize = Enum.AutomaticSize.Y
            rangeSlider2.Size = UDim2.new(1, 0, 0, 0)
            rangeSlider2.LayoutOrder = top or 1
            rangeSlider2.Parent = head
            corner(rangeSlider2, theme.RadiusMd)
            stroke(rangeSlider2, theme.Hairline, 1)
            pad(rangeSlider2, 7, 12, 9, 12)
            vlist(rangeSlider2, theme.GapSm)
            head = Instance.new("Frame")
            head.Name = "Head"
            head.BackgroundTransparency = 1
            head.AutomaticSize = Enum.AutomaticSize.Y
            head.Size = UDim2.new(1, 0, 0, 0)
            head.LayoutOrder = 1
            head.Parent = rangeSlider2
            vlist(head, 1)
            top = Instance.new("Frame")
            top.Name = "Top"
            top.BackgroundTransparency = 1
            top.Size = UDim2.new(1, 0, 0, 18)
            top.LayoutOrder = 1
            top.Parent = head
            label(top, x, "rowLabel", 1).Size = UDim2.new(1, -96, 1, 0)
            local textControl = label(top, "", "captionKey", 2)
            textControl.Size = UDim2.new(0, 96, 1, 0)
            textControl.Position = UDim2.new(1, -96, 0, 0)
            textControl.TextXAlignment = Enum.TextXAlignment.Right
            if a and a ~= "" then
                label(head, a, "captionSub", 2).Size = UDim2.new(1, 0, 0, 12)
            end
            local track = Instance.new("Frame")
            track.Name = "Track"
            track.BackgroundColor3 = theme.SurfaceField
            track.BorderSizePixel = 0
            track.Size = UDim2.new(1, 0, 0, 18)
            track.ClipsDescendants = false
            track.LayoutOrder = 2
            track.Active = true
            track.Parent = rangeSlider2
            corner(track, theme.RadiusSm)
            stroke(track, theme.Hairline, 1)
            local fill = Instance.new("Frame")
            fill.Name = "Fill"
            fill.BackgroundColor3 = Color3.new(1, 1, 1)
            fill.BorderSizePixel = 0
            fill.Size = UDim2.fromScale(0, 1)
            fill.Parent = track
            corner(fill, theme.RadiusSm)
            accentGradient(fill, 0)
            local function N(name)
                local frame = Instance.new("Frame")
                frame.Name = name
                frame.AnchorPoint = Vector2.new(0.5, 0.5)
                frame.BackgroundColor3 = theme.TextPrimary
                frame.BorderSizePixel = 0
                frame.Size = UDim2.fromOffset(8, 22)
                frame.ZIndex = 3
                frame.Parent = track
                corner(frame, 3)
                stroke(frame, theme.Hairline, 1)
                return frame
            end
            local g = N("Low")
            local B = N("High")
            local N = math.max(I - e, 1)
            local G = b and b ~= "" and " " .. b or ""
            local function b()
                local z, s = F()
                z, s =
                    math.clamp(math.floor((tonumber(z) or e) + 0.5), e, I),
                    math.clamp(math.floor((tonumber(s) or I) + 0.5), e, I)
                if s < z then
                    z, s = s, z
                else
                end
                return z, s
            end
            local function render()
                local z, s = b()
                local T, W = (z - e) / N, (s - e) / N
                fill.Position = UDim2.fromScale(T, 0)
                fill.Size = UDim2.fromScale(W - T, 1)
                g.Position = UDim2.fromScale(T, 0.5)
                B.Position = UDim2.fromScale(W, 0.5)
                textControl.Text = z == s and tostring(z) .. G or ("%d - %d"):format(z, s) .. G
            end
            render()
            local x
            local function a(N)
                local g = math.clamp((N - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                return math.floor(e + (I - e) * g + 0.5)
            end
            local function e(N)
                local I = not x or track.AbsoluteSize.X <= 0
                if I then
                    return
                end
                local g, B, G = a(N), b()
                N = x == "both"
                if N then
                    I = g > G
                    if I then
                        x = "hi"
                    else
                        local N = g < B
                        if N then
                            x = "lo"
                        else
                            return
                        end
                    end
                end
                I = x
                if I == "lo" then
                    B = math.min(g, G)
                else
                    G = math.max(g, B)
                end
                C(B, G)
                render()
            end
            track.InputBegan:Connect(function(input)
                if not contextPressOnTop(track, input) then
                    return
                end
                local I = input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch
                if I then
                    if track.AbsoluteSize.X <= 0 then
                        return
                    end
                    local k, I, C = a(input.Position.X), b()
                    x = if I == C and k == I
                        then "both"
                        else if k <= I
                            then "lo"
                            else if k >= C then "hi" else k - I <= C - k and "lo" or "hi"
                    e(input.Position.X)
                end
            end)
            table.insert(
                context.sliderConnections,
                userInputService.InputChanged:Connect(function(input)
                    local a = x
                        and (
                            input.UserInputType == Enum.UserInputType.MouseMovement
                            or input.UserInputType == Enum.UserInputType.Touch
                        )
                    if a then
                        e(input.Position.X)
                    end
                end)
            )
            table.insert(
                context.sliderConnections,
                userInputService.InputEnded:Connect(function(input)
                    local a = input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch
                    if a then
                        x = nil
                    end
                end)
            )
            tip(rangeSlider2, i)
            return {
                holder = rangeSlider2,
                render = render,
            }
        end
        local function listInput(head, x, a, e, N, I, F, C, g)
            local i, b, B = 26, 4, 4
            g = g or 5
            local listInput2 = Instance.new("Frame")
            listInput2.Name = "ListInput"
            listInput2.BackgroundTransparency = 1
            listInput2.AutomaticSize = Enum.AutomaticSize.Y
            listInput2.Size = UDim2.new(1, 0, 0, 0)
            listInput2.LayoutOrder = I or 1
            listInput2.Parent = head
            vlist(listInput2, theme.GapSm)
            head = Instance.new("Frame")
            head.Name = "Head"
            head.BackgroundTransparency = 1
            head.AutomaticSize = Enum.AutomaticSize.Y
            head.Size = UDim2.new(1, 0, 0, 0)
            head.LayoutOrder = 1
            head.Parent = listInput2
            vlist(head, 1)
            label(head, x, "rowLabel", 1).Size = UDim2.new(1, 0, 0, 18)
            if a and a ~= "" then
                label(head, a, "captionSub", 2).Size = UDim2.new(1, 0, 0, 12)
            end
            local list = Instance.new("ScrollingFrame")
            list.Name = "List"
            list.BackgroundColor3 = theme.SurfaceField
            list.BorderSizePixel = 0
            list.LayoutOrder = 2
            list.Size = UDim2.new(1, 0, 0, B * 2 + i)
            list.CanvasSize = UDim2.new()
            list.AutomaticCanvasSize = Enum.AutomaticSize.Y
            list.ScrollingDirection = Enum.ScrollingDirection.Y
            list.ScrollBarThickness = 4
            list.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 95)
            list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
            list.Parent = listInput2
            corner(list, theme.RadiusMd)
            stroke(list, theme.Hairline, 1)
            pad(list, B, B, B, B)
            vlist(list, b)
            local x, a = {}, false
            local function I(z)
                return (tostring(z or ""):gsub("^%s+", ""):gsub("%s+$", ""))
            end
            local function z()
                local s = math.clamp(#x, 1, g)
                list.Size = UDim2.new(1, 0, 0, B * 2 + s * i + (s - 1) * b)
            end
            local function g()
                local b = a
                if b then
                    return
                end
                b = {}
                for index, entry in ipairs(x) do
                    index = I(entry.Text)
                    if index ~= "" then
                        b[#b + 1] = index
                    end
                end
                N(b)
            end
            local function toBottom()
                task.defer(function()
                    if list.Parent then
                        list.CanvasPosition =
                            Vector2.new(0, math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y))
                    end
                end)
            end
            local b
            local function B()
                for index = #x - 1, 1, -1 do
                    local textControl = x[index]
                    if I(textControl.Text) == "" then
                        table.remove(x, index)
                        textControl:Destroy()
                    end
                end
                if #x == 0 or I(x[#x].Text) ~= "" then
                    b("")
                end
                for index2, entry in ipairs(x) do
                    entry.LayoutOrder = index2
                end
                z()
            end
            b = function(s)
                local entry = Instance.new("TextBox")
                entry.Name = "Entry"
                entry.BackgroundColor3 = theme.SurfaceElement
                entry.BorderSizePixel = 0
                entry.Size = UDim2.new(1, 0, 0, i)
                entry.LayoutOrder = #x + 1
                entry.Text = s or ""
                entry.PlaceholderText = C or "Add a name"
                entry.PlaceholderColor3 = theme.TextMuted
                entry.TextColor3 = theme.TextPrimary
                entry.TextSize = 12
                entry.ClearTextOnFocus = false
                entry.TextXAlignment = Enum.TextXAlignment.Left
                entry.TextTruncate = Enum.TextTruncate.AtEnd
                setFont(entry, "sans", Enum.FontWeight.Medium)
                entry.Parent = list
                corner(entry, theme.RadiusSm)
                stroke(entry, theme.Hairline, 1)
                pad(entry, 0, 8, 0, 8)
                x[#x + 1] = entry
                entry:GetPropertyChangedSignal("Text"):Connect(function()
                    local k = a
                    if k then
                        return
                    end
                    if x[#x] == entry and I(entry.Text) ~= "" then
                        b("")
                        z()
                        toBottom()
                    end
                    g()
                end)
                entry.FocusLost:Connect(function()
                    local k = a
                    if k then
                        return
                    end
                    B()
                    g()
                end)
                return entry
            end
            local function render()
                a = true
                for index, entry in ipairs(x) do
                    entry:Destroy()
                end
                table.clear(x)
                local x = e()
                if type(x) == "table" then
                    for index2, entry2 in ipairs(x) do
                        index2 = I(entry2)
                        if index2 ~= "" then
                            b(index2)
                        end
                    end
                end
                b("")
                a = false
                z()
            end
            render()
            tip(listInput2, F)
            return {
                holder = listInput2,
                render = render,
                toBottom = toBottom,
            }
        end
        local function dropdown(x, button, e, N, I, F, C)
            local dropdown2 = Instance.new("Frame")
            dropdown2.Name = "Dropdown"
            dropdown2.BackgroundTransparency = 1
            dropdown2.AutomaticSize = Enum.AutomaticSize.Y
            dropdown2.Size = UDim2.new(1, 0, 0, 0)
            dropdown2.LayoutOrder = F or 1
            dropdown2.Parent = x
            vlist(dropdown2, 4)
            F = row(dropdown2, button, 1, nil, 150)
            local i, textControl = hoverable(F, true), label(F, "", "captionKey", 2)
            textControl.Size = UDim2.fromOffset(118, 18)
            textControl.AutomaticSize = Enum.AutomaticSize.None
            textControl.TextTruncate = Enum.TextTruncate.AtEnd
            textControl.TextXAlignment = Enum.TextXAlignment.Right
            local B = chevron(F)
            local menu = Instance.new("Frame")
            menu.Name = "Menu"
            menu.BackgroundColor3 = theme.SurfaceField
            menu.BorderSizePixel = 0
            menu.AutomaticSize = Enum.AutomaticSize.Y
            menu.Size = UDim2.new(1, 0, 0, 0)
            menu.Visible = false
            menu.LayoutOrder = 2
            menu.Parent = dropdown2
            corner(menu, theme.RadiusMd)
            stroke(menu, theme.Hairline, 1)
            pad(menu, 4, 4, 4, 4)
            local z
            if #e > 6 then
                x = #e > 10 and 3 or 2
                z = Instance.new("UIGridLayout")
                z.CellSize = UDim2.new(1 / x, -math.ceil(2 * (x - 1) / x) - 1, 0, 26)
                z.CellPadding, z.FillDirectionMaxCells, z.SortOrder =
                    UDim2.fromOffset(2, 2), x, Enum.SortOrder.LayoutOrder
                z.Parent = menu
            else
                z = vlist(menu, 2)
            end
            local x = false
            local function s(visible)
                x = visible
                B.setOpen(visible)
                if
                    context.Shell
                    and context.Shell.slideTo
                    and context.Shell.isShown
                    and context.Shell.isShown()
                then
                    context.Shell.slideTo(menu, z, 8, visible)
                else
                    menu.Visible = visible
                end
            end
            local B = {}
            local function render()
                local T = N()
                textControl.Text = tostring(T)
                for key, entry in pairs(B) do
                    local W = key == T
                    entry.BackgroundColor3 = W and theme.SurfaceHover or theme.SurfaceElement
                    entry.TextColor3 = W and theme.AccentMid or theme.TextSub
                end
            end
            for index, entry2 in ipairs(e) do
                button = Instance.new("TextButton")
                button.Name = tostring(entry2.value)
                button.BackgroundColor3 = theme.SurfaceElement
                button.BorderSizePixel = 0
                button.Size = UDim2.new(1, 0, 0, 26)
                button.Text = entry2.label or tostring(entry2.value)
                button.TextColor3 = theme.TextSub
                button.TextSize = 12
                button.LayoutOrder = index
                setFont(button, "sans", Enum.FontWeight.Medium)
                button.Parent = menu
                corner(button, 4)
                local function e()
                    I(entry2.value)
                    s(false)
                    render()
                end
                button.MouseButton1Click:Connect(e)
                B[entry2.value] = button
            end
            render()
            i.onClick(function()
                s(not x)
            end)
            render()
            tip(F, C)
            return {
                holder = dropdown2,
                render = render,
            }
        end
        local function colorRow(parent, shade, N, I, gradient, C)
            local color = Instance.new("Frame")
            color.Name = "Color"
            color.BackgroundTransparency = 1
            color.AutomaticSize = Enum.AutomaticSize.Y
            color.Size = UDim2.new(1, 0, 0, 0)
            color.LayoutOrder = gradient or 1
            color.Parent = parent
            vlist(color, theme.GapSm)
            parent = row(color, shade, 1, nil, 54)
            local i, swatch = hoverable(parent, true), Instance.new("Frame")
            swatch.Name = "Swatch"
            swatch:SetAttribute("HLThemeSkipTree", true)
            swatch.BackgroundColor3 = N()
            swatch.BorderSizePixel = 0
            swatch.Size = UDim2.fromOffset(46, 20)
            swatch.LayoutOrder = 2
            swatch.Parent = parent
            corner(swatch, theme.RadiusSm)
            stroke(swatch, theme.Hairline, 1)
            local picker = Instance.new("Frame")
            picker.Name = "Picker"
            picker:SetAttribute("HLThemeSkipTree", true)
            picker.BackgroundTransparency = 1
            picker.Size = UDim2.new(1, 0, 0, 140)
            picker.Visible = false
            picker.LayoutOrder = 2
            picker.Parent = color
            hlist(picker, theme.GapMd)
            local parent2 = Instance.new("Frame")
            parent2.Name = "SV"
            parent2.BackgroundColor3 = Color3.new(1, 1, 1)
            parent2.BorderSizePixel = 0
            parent2.Size = UDim2.new(1, -22, 1, 0)
            parent2.Active = true
            parent2.LayoutOrder = 1
            parent2.Parent = picker
            corner(parent2, theme.RadiusMd)
            flexFill(parent2, 22)
            local gradient2 = Instance.new("UIGradient")
            gradient2.Rotation = 0
            gradient2.Parent = parent2
            shade = Instance.new("Frame")
            shade.Name = "Shade"
            shade.BackgroundColor3 = Color3.new(0, 0, 0)
            shade.BorderSizePixel = 0
            shade.Size = UDim2.fromScale(1, 1)
            shade.Parent = parent2
            corner(shade, theme.RadiusMd)
            gradient = Instance.new("UIGradient")
            gradient.Rotation = 90
            gradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0),
            })
            gradient.Parent = shade
            local cursor = Instance.new("Frame")
            cursor.Name = "Cursor"
            cursor.BackgroundTransparency = 1
            cursor.AnchorPoint = Vector2.new(0.5, 0.5)
            cursor.Size = UDim2.fromOffset(12, 12)
            cursor.ZIndex = 4
            cursor.Parent = parent2
            corner(cursor, 6)
            stroke(cursor, Color3.new(1, 1, 1), 2)
            local hue = Instance.new("Frame")
            hue.Name = "Hue"
            hue.BackgroundColor3 = Color3.new(1, 1, 1)
            hue.BorderSizePixel = 0
            hue.Size = UDim2.new(0, 14, 1, 0)
            hue.Active = true
            hue.LayoutOrder = 2
            hue.Parent = picker
            corner(hue, theme.RadiusSm)
            shade = Instance.new("UIGradient")
            shade.Rotation = 90
            shade.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
                ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
                ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
                ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
                ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
            })
            shade.Parent = hue
            local marker = Instance.new("Frame")
            marker.Name = "Marker"
            marker.BackgroundColor3 = Color3.new(1, 1, 1)
            marker.BorderSizePixel = 0
            marker.AnchorPoint = Vector2.new(0.5, 0.5)
            marker.Size = UDim2.fromOffset(20, 3)
            marker.Position = UDim2.new(0.5, 0, 0, 0)
            marker.ZIndex = 4
            corner(marker, 2)
            marker.Parent = hue
            local T, W, K = N():ToHSV()
            local function render()
                local backgroundColor3 = Color3.fromHSV(T, W, K)
                swatch.BackgroundColor3 = backgroundColor3
                gradient2.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(T, 1, 1))
                cursor.Position = UDim2.fromScale(W, 1 - K)
                marker.Position = UDim2.new(0.5, 0, T, 0)
                I(backgroundColor3)
            end
            render()
            local e, I = false, false
            local function F(b, z)
                if parent2.AbsoluteSize.X <= 0 then
                    return
                end
                W = math.clamp((b - parent2.AbsolutePosition.X) / parent2.AbsoluteSize.X, 0, 1)
                K = 1 - math.clamp((z - parent2.AbsolutePosition.Y) / parent2.AbsoluteSize.Y, 0, 1)
                render()
            end
            local function b(z)
                if hue.AbsoluteSize.Y <= 0 then
                    return
                end
                T = math.clamp((z - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y, 0, 1)
                render()
            end
            parent2.InputBegan:Connect(function(input)
                if not contextPressOnTop(parent2, input) then
                    return
                end
                local G = input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch
                if G then
                    e = true
                    F(input.Position.X, input.Position.Y)
                end
            end)
            hue.InputBegan:Connect(function(input)
                if not contextPressOnTop(hue, input) then
                    return
                end
                local z = input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch
                if z then
                    I = true
                    b(input.Position.Y)
                end
            end)
            table.insert(
                context.sliderConnections,
                userInputService.InputChanged:Connect(function(input)
                    if
                        input.UserInputType ~= Enum.UserInputType.MouseMovement
                        and input.UserInputType ~= Enum.UserInputType.Touch
                    then
                        return
                    end
                    local z = e
                    if z then
                        F(input.Position.X, input.Position.Y)
                    end
                    z = I
                    if z then
                        b(input.Position.Y)
                    end
                end)
            )
            table.insert(
                context.sliderConnections,
                userInputService.InputEnded:Connect(function(input)
                    local b = input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch
                    if b then
                        e, I = false, false
                    end
                end)
            )
            i.onClick(function()
                picker.Visible = not picker.Visible
            end)
            tip(parent, C)
            return {
                holder = color,
                render = render,
            }
        end
        local function colorWheel(parent, rim, I, F, spoke, g)
            local colorWheel2 = Instance.new("Frame")
            colorWheel2.Name = "ColorWheel"
            colorWheel2.BackgroundTransparency = 1
            colorWheel2.AutomaticSize = Enum.AutomaticSize.Y
            colorWheel2.Size = UDim2.new(1, 0, 0, 0)
            colorWheel2.LayoutOrder = spoke or 1
            colorWheel2.Parent = parent
            vlist(colorWheel2, theme.GapSm)
            parent = row(colorWheel2, rim, 1, nil, 54)
            local b, swatch = hoverable(parent, true), Instance.new("Frame")
            swatch.Name = "Swatch"
            swatch:SetAttribute("HLThemeSkipTree", true)
            swatch.BorderSizePixel = 0
            swatch.Size = UDim2.fromOffset(46, 20)
            swatch.LayoutOrder = 2
            swatch.Parent = parent
            corner(swatch, theme.RadiusSm)
            stroke(swatch, theme.Hairline, 1)
            local picker = Instance.new("Frame")
            picker.Name = "Picker"
            picker:SetAttribute("HLThemeSkipTree", true)
            picker.BackgroundTransparency = 1
            picker.Size = UDim2.new(1, 0, 0, 180)
            picker.Visible = false
            picker.LayoutOrder = 2
            picker.Parent = colorWheel2
            local wheel = Instance.new("Frame")
            wheel.Name = "Wheel"
            wheel.BackgroundTransparency = 1
            wheel.AnchorPoint = Vector2.new(0.5, 0)
            wheel.Position = UDim2.new(0.5, 0, 0, 0)
            wheel.Size = UDim2.fromOffset(150, 150)
            wheel.Active = true
            wheel.Parent = picker
            for index = 0, 35, 1 do
                spoke = Instance.new("Frame")
                spoke.Name = "Spoke"
                spoke.BorderSizePixel = 0
                spoke.BackgroundColor3 = Color3.new(1, 1, 1)
                spoke.AnchorPoint = Vector2.new(0.5, 0.5)
                spoke.Position = UDim2.fromScale(0.5, 0.5)
                spoke.Size = UDim2.fromOffset(150, 10)
                spoke.Rotation = index * 360 / 72
                rim = Instance.new("UIGradient")
                rim.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV((index + 36) % 72 / 72, 1, 1)),
                    ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(index / 72, 1, 1)),
                })
                rim.Parent = spoke
                spoke.Parent = wheel
            end
            local shade = Instance.new("Frame")
            shade.Name = "Shade"
            shade.BorderSizePixel = 0
            shade.BackgroundColor3 = Color3.new(0, 0, 0)
            shade.Size = UDim2.fromScale(1, 1)
            shade.ZIndex = 3
            shade.Parent = wheel
            corner(shade, 150)
            rim = Instance.new("Frame")
            rim.Name = "Rim"
            rim.BackgroundTransparency = 1
            rim.Size = UDim2.fromScale(1, 1)
            rim.ZIndex = 4
            rim.Parent = wheel
            corner(rim, 150)
            stroke(rim, theme.Hairline, 2)
            local cursor = Instance.new("Frame")
            cursor.Name = "Cursor"
            cursor.BackgroundTransparency = 1
            cursor.AnchorPoint = Vector2.new(0.5, 0.5)
            cursor.Size = UDim2.fromOffset(12, 12)
            cursor.ZIndex = 5
            cursor.Parent = wheel
            corner(cursor, 6)
            stroke(cursor, Color3.new(1, 1, 1), 2)
            local brightness = Instance.new("Frame")
            brightness.Name = "Brightness"
            brightness.BorderSizePixel = 0
            brightness.BackgroundColor3 = Color3.new(1, 1, 1)
            brightness.AnchorPoint = Vector2.new(0.5, 0)
            brightness.Position = UDim2.new(0.5, 0, 0, 162)
            brightness.Size = UDim2.fromOffset(150, 12)
            brightness.Active = true
            brightness.Parent = picker
            corner(brightness, theme.RadiusSm)
            stroke(brightness, theme.Hairline, 1)
            local gradient = Instance.new("UIGradient")
            gradient.Parent = brightness
            local marker = Instance.new("Frame")
            marker.Name = "Marker"
            marker.BackgroundColor3 = Color3.new(1, 1, 1)
            marker.BorderSizePixel = 0
            marker.AnchorPoint = Vector2.new(0.5, 0.5)
            marker.Size = UDim2.fromOffset(4, 18)
            marker.ZIndex = 4
            marker.Parent = brightness
            corner(marker, 2)
            local K, t, backgroundTransparency = I():ToHSV()
            local function X()
                local backgroundColor3 = Color3.fromHSV(K, t, backgroundTransparency)
                swatch.BackgroundColor3 = backgroundColor3
                shade.BackgroundTransparency = backgroundTransparency
                local C = K * 2 * 3.141592653589793
                cursor.Position = UDim2.fromScale(0.5 + math.cos(C) * t * 0.5, 0.5 + math.sin(C) * t * 0.5)
                gradient.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(K, t, 1))
                marker.Position = UDim2.new(backgroundTransparency, 0, 0.5, 0)
                return backgroundColor3
            end
            local function N()
                F(X())
            end
            local function render()
                K, t, backgroundTransparency = I():ToHSV()
                X()
            end
            render()
            local I, C = false, false
            local function B(T, W)
                local absoluteSize = wheel.AbsoluteSize
                if absoluteSize.X <= 0 then
                    return
                end
                local vector = wheel.AbsolutePosition + absoluteSize * 0.5
                local QF, LF = T - vector.X, W - vector.Y
                K = math.atan2(LF, QF) / 6.283185307179586 % 1
                t = math.clamp(math.sqrt(QF * QF + LF * LF) / (absoluteSize.X * 0.5), 0, 1)
                N()
            end
            local function T(W)
                if brightness.AbsoluteSize.X <= 0 then
                    return
                end
                backgroundTransparency =
                    math.clamp((W - brightness.AbsolutePosition.X) / brightness.AbsoluteSize.X, 0, 1)
                N()
            end
            wheel.InputBegan:Connect(function(input)
                if not contextPressOnTop(wheel, input) then
                    return
                end
                local z = input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch
                if z then
                    I = true
                    B(input.Position.X, input.Position.Y)
                end
            end)
            brightness.InputBegan:Connect(function(input)
                if not contextPressOnTop(brightness, input) then
                    return
                end
                local z = input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch
                if z then
                    C = true
                    T(input.Position.X)
                end
            end)
            table.insert(
                context.sliderConnections,
                userInputService.InputChanged:Connect(function(input)
                    if
                        input.UserInputType ~= Enum.UserInputType.MouseMovement
                        and input.UserInputType ~= Enum.UserInputType.Touch
                    then
                        return
                    end
                    local z = I
                    if z then
                        B(input.Position.X, input.Position.Y)
                    end
                    z = C
                    if z then
                        T(input.Position.X)
                    end
                end)
            )
            table.insert(
                context.sliderConnections,
                userInputService.InputEnded:Connect(function(input)
                    local B = input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch
                    if B then
                        I, C = false, false
                    end
                end)
            )
            b.onClick(function()
                picker.Visible = not picker.Visible
            end)
            tip(parent, g)
            return {
                holder = colorWheel2,
                render = render,
            }
        end
        local function button2(parent, text, F, C, success, i)
            local button = Instance.new("TextButton")
            button.Name = "Button"
            button.BorderSizePixel = 0
            button.Size = UDim2.new(1, 0, 0, 32)
            button.Text = text
            button.TextSize = 13
            button.AutoButtonColor = false
            button.LayoutOrder = success or 1
            setFont(button, "sans", Enum.FontWeight.SemiBold)
            button.Parent = parent
            corner(button, theme.RadiusMd)
            success, parent = pcall(function()
                local textService, G, gothamBold, s =
                    game:GetService("TextService"),
                    tostring(text),
                    Enum.Font.GothamBold,
                    vmHelpers[127](Vector2.new(2000, 40))
                return textService:GetTextSize(G, 13, gothamBold, vmHelpers:jB(s))
            end)
            local d = Instance.new("UISizeConstraint")
            d.MaxSize = Vector2.new(math.max(220, (success and parent.X or 180) + 44), math.huge)
            d.Parent = button
            if context.Shell and context.Shell.pressable then
                context.Shell.pressable(button)
            end
            if F == "accent" or F == "danger" then
                button.BackgroundTransparency = 1
                button.TextTransparency = 1
                local fill = Instance.new("Frame")
                fill.Name, fill.BackgroundColor3, fill.BorderSizePixel, fill.Size, fill.ZIndex =
                    "Fill", Color3.new(1, 1, 1), 0, UDim2.fromScale(1, 1), button.ZIndex
                fill.Parent = button
                corner(fill, theme.RadiusMd)
                parent = Instance.new("UIGradient")
                parent.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, theme.AccentB),
                    ColorSequenceKeypoint.new(0.5, theme.AccentDark),
                    ColorSequenceKeypoint.new(1, theme.AccentB),
                })
                parent.Parent = fill
                local label2 = Instance.new("TextLabel")
                label2.Name, label2.BackgroundTransparency, label2.Size, label2.ZIndex, label2.Text, label2.TextColor3, label2.TextSize =
                    "Label",
                    1,
                    UDim2.fromScale(1, 1),
                    button.ZIndex + 1,
                    button.Text,
                    theme.TextOnAccent,
                    button.TextSize
                setFont(label2, "sans", Enum.FontWeight.SemiBold)
                label2.Parent = button
                local function I()
                    label2.Text = button.Text
                end
                button:GetPropertyChangedSignal("Text"):Connect(I)
                local function N()
                    fill.BackgroundColor3 = Color3.new(0.68, 0.68, 0.68)
                end
                button.MouseEnter:Connect(N)
                local function N()
                    fill.BackgroundColor3 = Color3.new(1, 1, 1)
                end
                button.MouseLeave:Connect(N)
            else
                button.BackgroundColor3 = theme.SurfaceElement
                button.TextColor3 = theme.TextPrimary
                stroke(button, theme.Hairline, 1)
                local function d()
                    button.BackgroundColor3 = theme.SurfaceHover
                end
                button.MouseEnter:Connect(d)
                local function d()
                    button.BackgroundColor3 = theme.SurfaceElement
                end
                button.MouseLeave:Connect(d)
            end
            if C then
                button.MouseButton1Click:Connect(C)
            end
            tip(button, i)
            return button
        end
        local function textInput(N, I, F, C, g, i, b)
            local B, input = row(N, I, g, nil, 196), Instance.new("TextBox")
            input.Name = "Input"
            input.BackgroundColor3 = theme.SurfaceField
            input.BorderSizePixel = 0
            input.Size = UDim2.fromOffset(180, 24)
            input.LayoutOrder = 2
            input.Text = tostring(F() or "")
            input.PlaceholderText = b or "empty = hidden"
            input.PlaceholderColor3 = theme.TextMuted
            input.TextColor3 = theme.TextPrimary
            input.TextSize = 12
            input.ClearTextOnFocus = false
            input.TextXAlignment = Enum.TextXAlignment.Left
            input.TextTruncate = Enum.TextTruncate.AtEnd
            setFont(input, "sans", Enum.FontWeight.Medium)
            input.Parent = B
            corner(input, theme.RadiusSm)
            stroke(input, theme.Hairline, 1)
            pad(input, 0, 8, 0, 8)
            local function render()
                input.Text = tostring(F() or "")
            end
            local function I()
                C(input.Text)
            end
            input.FocusLost:Connect(I)
            tip(B, i)
            return {
                row = B,
                render = render,
                box = input,
            }
        end
        local function buttonRow(parent, F)
            local buttons = Instance.new("Frame")
            buttons.Name = "Buttons"
            buttons.BackgroundTransparency = 1
            buttons.Size = UDim2.new(1, 0, 0, 32)
            buttons.LayoutOrder = F or 1
            buttons.Parent = parent
            hlist(buttons, theme.GapMd)
            local F, g = 0, {}
            parent = {
                frame = buttons,
                add = function(i, b, B, G)
                    F += 1
                    local z = button2(buttons, i, b, B, F, G)
                    z.Size = UDim2.new(0, 0, 1, 0)
                    g[F] = z
                    for index, entry in ipairs(g) do
                        entry.Size = UDim2.new(1 / F, -(theme.GapMd * (F - 1)) / F, 1, 0)
                    end
                    return z
                end,
            }
            return parent
        end
        local I
        local F = 0
        local function contextRaiseWindow(g)
            F += 1
            g:SetAttribute("hlTop", F)
            g.ZIndex = (tonumber(context.CFG and context.CFG.menuZ) or 20) + 1 + F
            local parent = g.Parent
            if parent then
                g.Parent = nil
                g.Parent = parent
            end
        end
        context.raiseWindow = contextRaiseWindow
        local function makeDraggable(i, b)
            local B, position, parent = false
            i.InputBegan:Connect(function(input)
                local T = (
                    input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch
                ) and contextPressOnTop(b, input)
                if T then
                    local rank = b:GetAttribute("hlTop")
                        or (b.Parent and table.find(b.Parent:GetChildren(), b) or 0) / 1000
                    local W, K =
                        {
                            rank = rank,
                            go = function()
                                local position2, parent2
                                position2, parent2, B = input.Position, b.Position, true
                                position, parent = position2, parent2
                                F += 1
                                b:SetAttribute("hlTop", F)
                                b.ZIndex = (tonumber(context.CFG and context.CFG.menuZ) or 20) + 1 + F
                                parent2 = b.Parent
                                if parent2 then
                                    b.Parent = nil
                                    b.Parent = parent2
                                end
                            end,
                        }, I
                    if K then
                        rank = I
                        rank[#rank + 1] = W
                        return
                    end
                    I = {
                        W,
                    }
                    task.defer(function()
                        local F, s = I[1], I
                        for index, entry in ipairs(s) do
                            F = if entry.rank > F.rank then entry else F
                        end
                        I = nil
                        F.go()
                    end)
                end
            end)
            i.InputEnded:Connect(function(input)
                local F = input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch
                if F then
                    B = false
                end
            end)
            table.insert(
                context.sliderConnections,
                userInputService.InputChanged:Connect(function(input)
                    local I = B
                    if not I then
                        return
                    end
                    if
                        input.UserInputType ~= Enum.UserInputType.MouseMovement
                        and input.UserInputType ~= Enum.UserInputType.Touch
                    then
                        return
                    end
                    I = input.Position - position
                    b.Position =
                        UDim2.new(parent.X.Scale, parent.X.Offset + I.X, parent.Y.Scale, parent.Y.Offset + I.Y)
                end)
            )
        end
        local function window(I, F)
            local i = Instance.new("Frame")
            i.Name = F.name or "Window"
            i.BackgroundColor3 = Color3.new(1, 1, 1)
            i.BorderSizePixel = 0
            i.Size = UDim2.fromOffset(F.width or 310, F.height or 460)
            i.Position = F.position or UDim2.fromOffset(40, 40)
            i.Visible = F.visible ~= false
            i.Active = true
            i.ClipsDescendants = true
            i.ZIndex = 2
            i:SetAttribute("hlWin", true)
            i.Parent = I
            local function header(input)
                if
                    (
                        input.UserInputType == Enum.UserInputType.MouseButton1
                        or input.UserInputType == Enum.UserInputType.Touch
                    )
                    and contextPressOnTop(i, input)
                    and i.Parent
                then
                    Z(input)
                    local Z, n
                    for index, child in ipairs(i.Parent:GetChildren()) do
                        if child:IsA("GuiObject") and child.Visible and child:GetAttribute("hlWin") then
                            index = M(child)
                            if not Z or index > Z then
                                Z, n = index, child
                            else
                            end
                        else
                        end
                    end
                    if n ~= i then
                        task.defer(contextRaiseWindow, i)
                    end
                end
            end
            i.InputBegan:Connect(header)
            corner(i, theme.RadiusLg)
            stroke(i, theme.Hairline, 1)
            bodyGradient(i)
            shadow(i)
            header = Instance.new("Frame")
            header.Name = "Header"
            header.BackgroundColor3 = theme.SurfaceHeader
            header.BorderSizePixel = 0
            header.Size = UDim2.new(1, 0, 0, theme.HeaderH)
            header.Position = UDim2.fromOffset(0, 3)
            header.Active = true
            header.ZIndex = 3
            header.Parent = i
            corner(header, theme.RadiusLg)
            pad(header, 0, 12, 0, 14)
            I = Instance.new("Frame")
            I.Name = "HeaderFill"
            I.BackgroundColor3 = theme.SurfaceHeader
            I.BorderSizePixel = 0
            I.Position = UDim2.fromOffset(0, theme.HeaderH + 3 - theme.RadiusLg)
            I.Size = UDim2.new(1, 0, 0, theme.RadiusLg)
            I.ZIndex = 3
            I.Parent = i
            I = Instance.new("CanvasGroup")
            I.Name = "AccentBar"
            I.BackgroundTransparency = 1
            I.BorderSizePixel = 0
            I.Position = UDim2.fromOffset(0, 0)
            I.Size = UDim2.new(1, 0, 0, theme.RadiusLg + 3)
            I.ZIndex = 4
            I.Parent = i
            corner(I, theme.RadiusLg)
            local M = Instance.new("Frame")
            M.Name = "Band"
            M.BackgroundColor3 = Color3.new(1, 1, 1)
            M.BorderSizePixel = 0
            M.Size = UDim2.new(1, 0, 0, 3)
            M.ZIndex = 4
            M.Parent = I
            accentSweep(M)
            hlist(header, theme.GapLg)
            makeDraggable(header, i)
            M = nil
            if F.icon and p[F.icon] then
                M = icon(header, F.icon, 16, Color3.new(1, 1, 1), 4)
                M.Name = "Icon"
                M.LayoutOrder = 1
            else
                M = Instance.new("Frame")
                M.Name = "Icon"
                M.BackgroundColor3 = Color3.new(1, 1, 1)
                M.BorderSizePixel = 0
                M.Size = UDim2.fromOffset(14, 14)
                M.LayoutOrder = 1
                M.ZIndex = 4
                M.Parent = header
                corner(M, 4)
            end
            accentGradient(M, 45)
            I = label(header, F.title or "Window", "windowTitle", 2)
            I.ZIndex = 4
            flexFill(I, 58 + (F.info and 32 or 0))
            local p = false
            local pin = Instance.new("TextButton")
            pin.Name = "Pin"
            pin.BackgroundColor3 = theme.SurfaceElement
            pin.BorderSizePixel = 0
            pin.Size = UDim2.fromOffset(20, 20)
            pin.Text = ""
            pin.AutoButtonColor = false
            pin.LayoutOrder = 3
            pin.ZIndex = 4
            pin.Parent = header
            corner(pin, 6)
            local n = stroke(pin, theme.Hairline, 1)
            local C = icon(pin, "pin", 13, theme.TextMuted, 5)
            C.AnchorPoint, C.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
            local function B()
                local imageColor3 = p and theme.AccentMid or theme.TextMuted
                C.ImageColor3 = imageColor3
                n.Color = p and theme.AccentMid or theme.Hairline
                pin.BackgroundColor3 = p and theme.SurfaceHover or theme.SurfaceElement
            end
            B()
            tip(
                pin,
                "Pin this window so it stays on screen after you close the interface. You can still drag it. Click again to let it hide with the rest."
            )
            if F.info then
                M = Instance.new("TextLabel")
                M.Name = "Info"
                M.BackgroundColor3 = theme.SurfaceElement
                M.BorderSizePixel = 0
                M.Size = UDim2.fromOffset(20, 20)
                M.Text = ""
                M.TextColor3 = theme.TextSub
                M.TextSize = 12
                M.LayoutOrder = 3
                M.ZIndex = 4
                setFont(M, "sans", Enum.FontWeight.Bold)
                M.Parent = header
                corner(M, 10)
                stroke(M, theme.Hairline, 1)
                local n = icon(M, "info", 13, theme.TextSub, 5)
                n.AnchorPoint, n.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
                tip(M, F.info)
            end
            M = Instance.new("Frame")
            M.Name = "Divider"
            M.BackgroundColor3 = theme.Hairline
            M.BorderSizePixel = 0
            M.Size = UDim2.new(1, 0, 0, 1)
            M.Position = UDim2.fromOffset(0, 3 + theme.HeaderH)
            M.ZIndex = 3
            M.Parent = i
            M = Instance.new("ScrollingFrame")
            M.Name = "Body"
            M.BackgroundTransparency = 1
            M.BorderSizePixel = 0
            M.Position = UDim2.fromOffset(0, 4 + theme.HeaderH)
            M.Size = UDim2.new(1, 0, 1, -(4 + theme.HeaderH + theme.RadiusLg))
            M.CanvasSize = UDim2.new()
            M.AutomaticCanvasSize = Enum.AutomaticSize.Y
            M.ScrollBarThickness = 4
            M.ScrollBarImageColor3 = Color3.fromHex("50505f")
            M.ZIndex = 3
            M.Parent = i
            pad(M, 10, theme.GapLg, theme.GapXl, theme.GapLg)
            local n = vlist(M, theme.GapSm)
            local C = F.maxHeight or F.height or 460
            local function fit()
                local z = 4 + theme.HeaderH + 10 + n.AbsoluteContentSize.Y + theme.GapXl + theme.RadiusLg
                local s = math.clamp(z, theme.HeaderH + 48, C)
                i.Size = UDim2.fromOffset(F.width or 310, s)
            end
            if F.autoHeight ~= false then
                n:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
                task.defer(fit)
            end
            local n
            n = {
                frame = i,
                header = header,
                body = M,
                title = I,
                fit = fit,
                isPinned = function()
                    local M = p
                    return M
                end,
                setPinned = function(M)
                    p = M and true or false
                    B()
                    if F.onPinChanged then
                        F.onPinChanged(n)
                    end
                end,
            }
            pin.MouseButton1Click:Connect(function()
                n.setPinned(not p)
            end)
            return n
        end
        local function section(parent, Z, n, I)
            local section2 = Instance.new("Frame")
            section2.Name = "Section"
            section2.BackgroundTransparency = 1
            section2.AutomaticSize = Enum.AutomaticSize.Y
            section2.Size = UDim2.new(1, 0, 0, 0)
            section2.LayoutOrder = n or 1
            section2.Parent = parent
            vlist(section2, theme.GapSm)
            local head, textControl = row(section2, Z, 1, nil, 24)
            head.BackgroundColor3 = theme.SurfaceSection
            setFont(textControl, "sans", Enum.FontWeight.SemiBold)
            local i, b = hoverable(head, true), chevron(head)
            local content = Instance.new("Frame")
            content.Name = "Content"
            content.BackgroundColor3 = theme.SurfaceWell
            content.BorderSizePixel = 0
            content.AutomaticSize = Enum.AutomaticSize.Y
            content.Size = UDim2.new(1, 0, 0, 0)
            content.Visible = false
            content.LayoutOrder = 2
            content.Parent = section2
            corner(content, theme.RadiusMd)
            local G = vlist(content, theme.GapSm)
            pad(content, 6, 6, 6, 6)
            local visible = false
            local function setOpen(T, W)
                T = T and true or false
                local K = T ~= visible
                visible = T
                b.setOpen(visible)
                textControl.TextColor3 = visible and theme.AccentMid or theme.TextPrimary
                local C = K
                    and not W
                    and context.Shell
                    and context.Shell.slideTo
                    and context.Shell.isShown
                    and context.Shell.isShown()
                    and section2:IsDescendantOf(game)
                if C then
                    context.Shell.slideTo(content, G, 12, visible)
                else
                    content.Visible = visible
                end
            end
            setOpen(false, true)
            i.onClick(function()
                setOpen(not visible)
            end)
            tip(head, I)
            if I and I ~= "" then
                n = label(content, I, "captionSub", -1000)
                n.Name = "Description"
                n.TextSize = 11
                n.AutomaticSize = Enum.AutomaticSize.Y
                n.Size = UDim2.new(1, 0, 0, 0)
                n.TextWrapped = true
                n.TextYAlignment = Enum.TextYAlignment.Top
                pad(n, 2, 4, 2, 4)
            end
            context.sectionReg = context.sectionReg or {}
            context.sectionReg[section2] = {
                head = head,
                content = content,
                setOpen = setOpen,
                isOpen = function()
                    local visible2 = visible
                    return visible2
                end,
            }
            Z = {
                holder = section2,
                content = content,
                setOpen = function(M, n)
                    if not M then
                        setOpen(false, n)
                    end
                end,
                isOpen = function()
                    local visible2 = visible
                    return visible2
                end,
            }
            return Z
        end
        context.UIKit = {
            Theme = theme,
            setFont = setFont,
            corner = corner,
            stroke = stroke,
            pad = pad,
            vlist = vlist,
            hlist = hlist,
            label = label,
            caption = function(Q, S, P)
                local _ = label(Q, S, "captionSub", P)
                _.AutomaticSize = Enum.AutomaticSize.Y
                _.Size = UDim2.new(1, 0, 0, 0)
                _.TextWrapped = true
                _.TextYAlignment = Enum.TextYAlignment.Top
                return _
            end,
            flexFill = flexFill,
            accentGradient = accentGradient,
            accentSweep = accentSweep,
            stopSweeps = stopSweeps,
            bodyGradient = bodyGradient,
            shadow = shadow,
            ensureTip = ensureTip,
            tip = tip,
            hideTip = hideTip,
            chevron = chevron,
            row = row,
            hoverable = hoverable,
            icon = icon,
            toggle = toggle,
            slider = slider,
            dropdown = dropdown,
            textInput = textInput,
            rangeSlider = rangeSlider,
            listInput = listInput,
            colorRow = colorRow,
            colorWheel = colorWheel,
            button = button2,
            buttonRow = buttonRow,
            window = window,
            section = section,
            makeDraggable = makeDraggable,
        }
    end

components.uiLibrary(context)

----------------------------------------------------------------------
-- Cửa sổ + trang Auto Sell
----------------------------------------------------------------------
local uiKit = context.UIKit
local theme = context.UIKit.Theme
local uiSettings = context.UI
local contextSliderConnections = context.sliderConnections
local ver, U, J, w = context.SCRIPT_VERSION, {}, {}, true
local function Y(v)
    U[#U + 1] = v
    return v
end
local function contextRefreshAll()
    for index, entry in ipairs(U) do
        if type(entry) == "table" and entry.render then
            pcall(entry.render)
        end
    end
end
context.refreshAll = contextRefreshAll

local function contextDestructScript()
    runtimeState.destroyed = true
    for _, connection in ipairs(contextSliderConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    pcall(contextSaveConfig)
    pcall(function()
        if runtimeState.mobileMenuButton then
            runtimeState.mobileMenuButton:Destroy()
        end
    end)
    pcall(function()
        if runtimeState.scriptGui then
            runtimeState.scriptGui:Destroy()
        end
    end)
    if _G.HarvardAutoSellDestroy == contextDestructScript then
        _G.HarvardAutoSellDestroy = nil
    end
end
_G.HarvardAutoSellDestroy = contextDestructScript

-- Khung cửa sổ (nguyên bản, chỉ còn một tab)
        context.buildShell = function(f)
            local tweenService = game:GetService("TweenService")
            game:GetService("TextService")
            local k, x = {
                pages = {},
                order = {},
            }, {}
            local function a(e, N)
                local connection = e:Connect(N)
                x[#x + 1] = connection
                contextSliderConnections[#contextSliderConnections + 1] = connection
                return connection
            end
            local function x(e, N, parent)
                local F = Instance.new(e)
                for key, entry in pairs(N or {}) do
                    F[key] = entry
                end
                if parent then
                    F.Parent = parent
                end
                return F
            end
            local radiusSm, radiusMd = theme.RadiusSm, theme.RadiusMd
            local radiusLg = theme.RadiusLg
            local iconGrad, fontWeight = theme.RowH, Enum.FontWeight
            local function C(g, i)
                return uiKit.corner(g, i or radiusMd)
            end
            local function g(i, b, B)
                return uiKit.stroke(i, b or theme.Hairline, B or 1)
            end
            local function i(b, B, G, z, s)
                return uiKit.pad(b, B, G or B, z or B, s or G or B)
            end
            local function b(B, G)
                return uiKit.vlist(B, G or 0)
            end
            local function B(G, z, s)
                local T = uiKit.hlist(G, z or 0)
                if s then
                    T.HorizontalAlignment = Enum.HorizontalAlignment.Right
                end
                return T
            end
            local function G(z, text, textSize, textColor3, K, t)
                local H = x("TextLabel", {
                    BackgroundTransparency = 1,
                    Text = text,
                    TextSize = textSize,
                    TextColor3 = textColor3,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextYAlignment = Enum.TextYAlignment.Center,
                    Size = UDim2.new(1, 0, 0, textSize + 6),
                }, z)
                uiKit.setFont(H, "sans", K or fontWeight.Regular)
                for key, entry in pairs(t or {}) do
                    H[key] = entry
                end
                return H
            end
            local function z(s, T, W, K, t)
                local H = uiKit.icon(s, T, W, K)
                for key, entry in pairs(t or {}) do
                    H[key] = entry
                end
                return H
            end
            local function s(T, W)
                local K = x("TextButton", {
                    AutoButtonColor = false,
                    Text = "",
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                }, T)
                for key, entry in pairs(W or {}) do
                    K[key] = entry
                end
                return K
            end
            local function T(W)
                W.AnchorPoint, W.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
                return W
            end
            local W = context.COMPACT == true
            local function K(input)
                return input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch
            end
            local function t(input)
                return input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch
            end
            local function H(X, dF, QF)
                local LF = tweenService:Create(
                    X,
                    TweenInfo.new(dF, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                    QF
                )
                LF:Play()
                return LF
            end
            local function twd(dF, QF, LF, OF, SF, DF)
                local PF = tweenService:Create(
                    dF,
                    TweenInfo.new(
                        QF,
                        SF or Enum.EasingStyle.Quint,
                        DF or Enum.EasingDirection.Out,
                        0,
                        false,
                        OF or 0
                    ),
                    LF
                )
                PF:Play()
                return PF
            end
            k.tw = H
            k.twd = twd
            local dF, QF, LF, OF, SF, DF, PF = 780, 600, 184, 58, 3, 620, 400
            local function _F()
                local camera = workspace.CurrentCamera
                return camera and camera.ViewportSize or Vector2.new(1920, 1080)
            end
            local function lF()
                local absoluteSize = f.AbsoluteSize
                if absoluteSize.X > 0 and absoluteSize.Y > 0 then
                    return absoluteSize
                end
                return _F()
            end
            if W then
                local vector = lF()
                OF, DF, PF = 44, 460, 260
                dF = math.floor(math.clamp(vector.X - 48, DF, 720))
                QF = math.floor(math.clamp(vector.Y - 20, PF, 440))
                LF = 56
            else
            end
            local cF, uF, hF = dF, QF, "HarvardLabs/configs/menu_window.json"
            local mF = W and "phone" or "pc"
            local function RF()
                local success, qF = pcall(function()
                    local httpService, EF = game:GetService("HttpService"), vmHelpers[127](readfile(hF))
                    return httpService:JSONDecode(vmHelpers:jB(EF))
                end)
                return success and type(qF) == "table" and qF or {}
            end
            local yF = RF()[mF]
            local accentBar, frame =
                type(yF) == "table" and tonumber(yF.w) or nil, type(yF) == "table" and tonumber(yF.h) or nil
            yF = accentBar and frame
            if yF then
                local vector2 = W and lF() or _F()
                cF = math.floor(math.clamp(accentBar, DF, math.max(DF, vector2.X - 20)))
                uF = math.floor(math.clamp(frame, PF, math.max(PF, vector2.Y - 20)))
            else
            end
            local function EF()
                local pF = RF()
                pF[mF] = {
                    w = cF,
                    h = uF,
                }
                pcall(function()
                    writefile(hF, game:GetService("HttpService"):JSONEncode(pF))
                end)
            end
            local hF = x("Frame", {
                Name = "HLMenu",
                Size = UDim2.fromOffset(cF, uF),
                BackgroundTransparency = 1,
                Visible = false,
                ZIndex = tonumber(config.menuZ) or 20,
            }, f)
            hF:SetAttribute("hlWin", true)
            hF:SetAttribute("HLUIMotionOwned", true)
            local mF = x("UIScale", {}, hF)
            local RF = x("Frame", {
                Name = "Shadow",
                BackgroundTransparency = 1,
                Size = UDim2.fromScale(1, 1),
            }, hF)
            for index = 1, 8, 1 do
                yF, accentBar = index * 1.5, 10 * index / 8
                C(
                    x("Frame", {
                        BackgroundColor3 = Color3.new(0, 0, 0),
                        BackgroundTransparency = 0.96,
                        BorderSizePixel = 0,
                        Position = UDim2.fromOffset(-yF, -yF + accentBar),
                        Size = UDim2.new(1, yF * 2, 1, yF * 2),
                    }, RF),
                    radiusLg + yF
                )
            end
            local root = x("Frame", {
                Name = "Window",
                Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                ClipsDescendants = true,
                Active = true,
            }, hF)
            x("TextButton", {
                Name = "FreeMouse",
                Modal = true,
                Text = "",
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(0, 0),
            }, root)
            C(root, radiusLg)
            g(root, theme.Hairline, 1)
            x("UIGradient", {
                Rotation = 90,
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, theme.BodyTop),
                    ColorSequenceKeypoint.new(0.45, theme.BodyMid),
                    ColorSequenceKeypoint.new(1, theme.BodyBot),
                }),
            }, root)
            k.holder = hF
            k.root = root
            local jF, UF = 1, false
            local JF = Vector2.zero
            local wF, YF = Vector2.zero, 1
            local function vF()
                local scale = jF * YF
                mF.Scale = scale
                local ZF = Vector2.new(hF.Size.X.Offset, hF.Size.Y.Offset)
                local vector3 = ZF * (jF - scale) / 2
                hF.Position =
                    UDim2.fromOffset(math.floor(wF.X + vector3.X + 0.5), math.floor(wF.Y + vector3.Y + 0.5))
            end
            local MF
            local function ZF()
                local vector3 = W and lF() or _F()
                return math.clamp(math.min((vector3.X - 24) / 312, (vector3.Y - 24) / 520), 0.5, 1)
            end
            local function stroke()
                local vector3 = W and lF() or _F()
                jF = if W
                    then math.clamp(math.min((vector3.X - 8) / dF, (vector3.Y - 8) / QF), 0.6, 1)
                    else math.clamp(math.min((vector3.X - 24) / dF, (vector3.Y - 24) / QF), 0.5, 1)
                if MF then
                    MF.Scale = ZF()
                end
                local rF = not UF
                if rF then
                    UF = true
                    JF = Vector2.new(math.floor((vector3.X - cF * jF) / 2), math.floor((vector3.Y - uF * jF) / 2))
                    wF = JF
                end
                vF()
            end
            stroke()
            if workspace.CurrentCamera then
                a(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), stroke)
            end
            local function UF(fF)
                local rF, oF = fF - root.AbsolutePosition, jF
                return rF / oF
            end
            accentBar = x("CanvasGroup", {
                Name = "AccentBar",
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, radiusLg + SF),
                ZIndex = 6,
            }, root)
            C(accentBar, radiusLg)
            yF = x("Frame", {
                Name = "Band",
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, SF),
                ZIndex = 6,
            }, accentBar)
            uiKit.accentSweep(yF)
            k.accentBar = accentBar
            local header = x("Frame", {
                Name = "Header",
                BackgroundColor3 = theme.SurfaceHeader,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, SF),
                Size = UDim2.new(1, 0, 0, OF),
                ZIndex = 3,
            }, root)
            x("Frame", {
                Name = "Divider",
                BackgroundColor3 = theme.Hairline,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, SF + OF),
                Size = UDim2.new(1, 0, 0, 1),
                ZIndex = 3,
            }, root)
            local rF, oF =
                {}, {
                    "...#....",
                    "..#.....",
                    ".##.....",
                    ".##..#..",
                    ".##.###.",
                    ".###.###",
                    ".##..##.",
                    ".##..##.",
                    ".##..##.",
                    "###..##.",
                    ".###.##.",
                    "..#..##.",
                    ".....##.",
                    ".....#..",
                    "....#...",
                    "...#....",
                }
            do
                local AF = x("Frame", {
                    Name = "Logo",
                    Position = W and UDim2.fromOffset(12, 7) or UDim2.fromOffset(16, 10),
                    Size = W and UDim2.fromOffset(28, 30) or UDim2.fromOffset(36, 38),
                    BackgroundTransparency = 1,
                    ZIndex = 4,
                }, header)
                AF:SetAttribute("HLThemeSkipTree", true)
                local function bold()
                    local parent, camera =
                        x("ViewportFrame", {
                            Size = UDim2.fromScale(1, 1),
                            BackgroundTransparency = 1,
                            Ambient = Color3.new(1, 1, 1),
                            LightColor = Color3.new(0, 0, 0),
                            ZIndex = 4,
                        }, AF), Instance.new("Camera")
                    camera.FieldOfView = 22
                    camera.CFrame = CFrame.new(Vector3.new(0, 0, 11.6), Vector3.new(0, 0, 0))
                    camera.Parent = parent
                    parent.CurrentCamera = camera
                    local parent2 = Instance.new("Model")
                    local NF, IF, FF, CF = #oF, #oF[1], 0.25, 0.5
                    local gF, iF = IF * FF / 2, NF * FF / 2
                    for index2 = 1, NF, 1 do
                        for index3 = 1, IF, 1 do
                            if oF[index2]:sub(index3, index3) == "#" then
                                camera = Instance.new("Part")
                                camera.Anchored, camera.CanCollide, camera.CastShadow, camera.Material =
                                    true, false, false, Enum.Material.SmoothPlastic
                                camera.Size = Vector3.new(0.252, 0.252, CF)
                                camera.CFrame =
                                    CFrame.new((index3 - 1) * FF + 0.125 - gF, iF - (index2 - 1) * FF - 0.125, 0)
                                camera.Color = theme.AccentB
                                camera.Parent = parent2
                                rF[#rF + 1] = {
                                    p = camera,
                                    u = ((index3 - 1) / (IF - 1) + (index2 - 1) / (NF - 1)) * 0.5,
                                    ax = (index3 - 0.5) / IF,
                                    ay = (index2 - 0.5) / NF,
                                }
                            end
                        end
                    end
                    parent2.Parent = parent
                    parent2.WorldPivot = CFrame.new()
                    local function xF(aF)
                        return aF < 0.5 and 4 * aF * aF * aF or 1 - (-2 * aF + 2) ^ 3 / 2
                    end
                    local aF
                    local NF = 0
                    parent2:PivotTo(CFrame.Angles(0, -0.17453292519943295, 0))
                    a(runService.RenderStepped, function()
                        if not hF.Visible then
                            return
                        end
                        local now = os.clock()
                        local FF = now % 3
                        local CF = FF < 1 and -10 + 360 * xF(FF) or -10
                        FF = CF ~= aF
                        if FF then
                            aF = CF
                            parent2:PivotTo(CFrame.Angles(0, math.rad(CF), 0))
                        end
                        CF = now - NF
                        if CF < 0.03333333333333333 then
                            return
                        end
                        NF = now
                        CF, FF = theme.AccentB
                        if context.themeLive then
                            local xF, aF = context.themeLive(now)
                            CF, FF = xF or theme.AccentB, aF
                        else
                        end
                        if FF then
                            local vector3, absoluteSize =
                                AF.AbsolutePosition - hF.AbsolutePosition, AF.AbsoluteSize
                            for index4, entry in ipairs(rF) do
                                entry.p.Color = FF(
                                    now,
                                    vector3.X + entry.ax * absoluteSize.X,
                                    vector3.Y + entry.ay * absoluteSize.Y
                                )
                            end
                        else
                            local xF, aF, eF = CF:ToHSV()
                            local NF, FF =
                                Color3.fromHSV(xF, aF, eF * 0.55),
                                Color3.fromHSV(xF, aF * 0.88, math.min(1, eF * 1.12))
                            for index5, entry2 in ipairs(rF) do
                                entry2.p.Color = NF:Lerp(
                                    FF,
                                    0.5 + 0.5 * math.cos((entry2.u * 0.8 - now * 0.25) * 3.141592653589793 * 2)
                                )
                            end
                        end
                    end)
                end
                if not pcall(bold) then
                    frame = C(
                        x("Frame", {
                            Size = UDim2.fromOffset(32, 32),
                            Position = UDim2.fromOffset(2, 3),
                            BackgroundColor3 = Color3.new(1, 1, 1),
                            ZIndex = 4,
                        }, AF),
                        radiusMd
                    )
                    uiKit.accentGradient(frame, 45)
                    G(frame, "h", 22, theme.TextOnAccent, fontWeight.Bold, {
                        Size = UDim2.fromScale(1, 1),
                        TextXAlignment = Enum.TextXAlignment.Center,
                        ZIndex = 5,
                    })
                end
                accentBar, yF, bold, stroke =
                    W and 15 or 17, theme.TextPrimary, fontWeight.Bold, {
                        Position = W and UDim2.fromOffset(48, 5) or UDim2.fromOffset(60, 10),
                    }
                stroke.Size, stroke.ZIndex = UDim2.fromOffset(W and 220 or 320, W and 19 or 22), 4
                G(header, "Harvard Labs", accentBar, yF, bold, stroke)
                local rF, AF, textMuted, medium, aF =
                    tostring(ver), W and 11 or 12, theme.TextMuted, fontWeight.Medium, {
                        Position = W and UDim2.fromOffset(48, 23) or UDim2.fromOffset(60, 31),
                    }
                aF.Size, aF.ZIndex = UDim2.fromOffset(W and 220 or 320, W and 14 or 16), 4
                G(header, rF, AF, textMuted, medium, aF)
            end
            local rF = x("Frame", {
                Name = "Overlay",
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                ZIndex = 50,
                Visible = false,
            }, root)
            local AF = s(rF, {
                Size = UDim2.fromScale(1, 1),
                ZIndex = 50,
            })
            local function kF()
                for index2, child in ipairs(rF:GetChildren()) do
                    if child ~= AF then
                        child:Destroy()
                    end
                end
                rF.Visible = false
            end
            a(AF.Activated, kF)
            local function pressable(aF)
                local eF = x("UIScale", {}, aF)
                a(aF.MouseButton1Down, function()
                    twd(eF, 0.08, {
                        Scale = 0.96,
                    }, 0, Enum.EasingStyle.Quad)
                end)
                local function NF()
                    twd(eF, 0.28, {
                        Scale = 1,
                    }, 0, Enum.EasingStyle.Back)
                end
                a(aF.MouseButton1Up, NF)
                a(aF.MouseLeave, NF)
            end
            k.pressable = pressable
            local aF = {}
            local function slideTo(NF, IF, FF, CF, gF)
                local iF = (aF[NF] or 0) + 1
                aF[NF] = iF
                local bF = NF.Size.X
                local BF = NF.Visible and NF.AbsoluteSize.Y / math.max(jF, 0.01) or 0
                BF = if NF:FindFirstAncestorOfClass("ScreenGui") ~= f or not hF:IsAncestorOf(NF)
                    then NF.Visible and NF.AbsoluteSize.Y or 0
                    else BF
                NF.ClipsDescendants = true
                NF.AutomaticSize = Enum.AutomaticSize.None
                NF.Size = UDim2.new(bF.Scale, bF.Offset, 0, BF)
                NF.Visible = true
                task.defer(function()
                    if aF[NF] ~= iF then
                        return
                    end
                    local BF = hF:IsAncestorOf(NF) and jF or 1
                    local GF = CF and IF.AbsoluteContentSize.Y / BF + FF or 0
                    BF = tweenService:Create(
                        NF,
                        TweenInfo.new(CF and 0.34 or 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {
                            Size = UDim2.new(bF.Scale, bF.Offset, 0, GF),
                        }
                    )
                    BF:Play()
                    local function IF()
                        if aF[NF] ~= iF then
                            return
                        end
                        aF[NF] = nil
                        if not CF then
                            NF.Visible = false
                        end
                        NF.AutomaticSize = Enum.AutomaticSize.Y
                        NF.Size = UDim2.new(bF.Scale, bF.Offset, 0, 0)
                        NF.ClipsDescendants = false
                        if gF then
                            gF()
                        end
                    end
                    BF.Completed:Once(IF)
                end)
            end
            k.slideTo = slideTo
            local aF, NF = {}, {}
            local function IF(FF, prop, gF, dur)
                local bF, BF = NF[FF]
                if bF and bF[prop] then
                    BF = bF[prop].to
                    bF[prop].dead = true
                else
                    BF = FF[prop]
                end
                if BF >= 0.999 then
                    return
                end
                local GF = {
                    o = FF,
                    prop = prop,
                    to = BF,
                    t0 = gF,
                    dur = dur,
                }
                bF = bF or {}
                bF[prop] = GF
                NF[FF] = bF
                FF[prop] = 1
                aF[#aF + 1] = GF
            end
            local function FF(CF, gF, iF, bF)
                local BF = os.clock() + (gF or 0)
                iF = iF or 0.42
                gF = bF and {
                    CF,
                } or CF:GetDescendants()
                if not bF then
                    table.insert(gF, 1, CF)
                end
                for index2, entry in ipairs(gF) do
                    if entry:IsA("GuiObject") then
                        if entry.Visible then
                            IF(entry, "BackgroundTransparency", BF, iF)
                            if entry:IsA("TextLabel") or entry:IsA("TextButton") or entry:IsA("TextBox") then
                                IF(entry, "TextTransparency", BF, iF)
                            end
                            if entry:IsA("ImageLabel") or entry:IsA("ImageButton") then
                                IF(entry, "ImageTransparency", BF, iF)
                            end
                        end
                    elseif entry:IsA("UIStroke") and not bF then
                        IF(entry, "Transparency", BF, iF)
                    end
                end
            end
            a(runService.RenderStepped, function()
                if #aF == 0 then
                    return
                end
                local now = os.clock()
                for index2 = #aF, 1, -1 do
                    local gF = aF[index2]
                    if gF.dead or not gF.o.Parent then
                        table.remove(aF, index2)
                        if not gF.dead and NF[gF.o] then
                            NF[gF.o] = nil
                        end
                    else
                        local iF = (now - gF.t0) / gF.dur
                        if iF >= 1 then
                            gF.o[gF.prop] = gF.to
                            local IF = NF[gF.o]
                            if IF and IF[gF.prop] == gF then
                                IF[gF.prop] = nil
                                if next(IF) == nil then
                                    NF[gF.o] = nil
                                end
                            end
                            table.remove(aF, index2)
                        elseif iF > 0 then
                            gF.o[gF.prop] = 1 + (gF.to - 1) * (1 - (1 - iF) ^ 3)
                        end
                    end
                end
            end)
            local function aF(NF, IF)
                if NF.AutomaticSize ~= Enum.AutomaticSize.None then
                    return
                end
                local CF = NF:FindFirstChildOfClass("UIPadding") or x("UIPadding", {}, NF)
                if CF:GetAttribute("hlT") == nil then
                    CF:SetAttribute("hlT", CF.PaddingTop.Offset)
                end
                NF = CF:GetAttribute("hlT")
                CF.PaddingTop = UDim.new(0, NF + 8)
                twd(CF, 0.45, {
                    PaddingTop = UDim.new(0, NF),
                }, IF)
            end
            local function NF(visible)
                local CF, gF, iF = 0.045, 18, 0
                local function bF()
                    local BF = math.min(iF, gF) * CF
                    iF += 1
                    return BF
                end
                local function gF(BF)
                    local GF, zF = {}, {}
                    for index2, child in ipairs(BF:GetChildren()) do
                        if child:IsA("GuiObject") and child.Visible then
                            GF[#GF + 1] = child
                            zF[child] = index2
                        end
                    end
                    table.sort(GF, function(BF, sF)
                        if BF.LayoutOrder ~= sF.LayoutOrder then
                            return BF.LayoutOrder < sF.LayoutOrder
                        end
                        return zF[BF] < zF[sF]
                    end)
                    return GF
                end
                local BF = gF(visible)
                for index3, entry in ipairs(BF) do
                    index3 = k.sections[entry]
                    if index3 then
                        FF(index3.head, (bF()))
                        visible = index3.content.Visible
                        if visible then
                            FF(index3.content, math.max(0, iF - 1) * CF + 0.04, 0.34, true)
                            for index4, entry2 in ipairs((gF(index3.content))) do
                                index4 = bF()
                                FF(entry2, index4)
                                aF(entry2, index4)
                            end
                        end
                    else
                        local IF = bF()
                        FF(entry, IF)
                        aF(entry, IF)
                    end
                end
            end
            k.sections = context.sectionReg or {}
            context.sectionReg = k.sections
            do
                local textControl = x("TextLabel", {
                    AnchorPoint = Vector2.new(0.5, 1),
                    Position = UDim2.new(0.5, 0, 1, -16),
                    Size = UDim2.fromOffset(0, 32),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Color3.fromHex("3a3a42"),
                    TextColor3 = theme.TextPrimary,
                    TextSize = 12,
                    Text = "",
                    ZIndex = 70,
                    Visible = false,
                }, root)
                uiKit.setFont(textControl, "sans", fontWeight.Medium)
                C(textControl, radiusMd)
                g(textControl, theme.Hairline, 1)
                i(textControl, 0, 14, 0, 14)
                local IF = 0
                k.toast = function(text)
                    IF += 1
                    local CF = IF
                    textControl.Text = text
                    textControl.Visible = true
                    textControl.TextTransparency = 1
                    textControl.BackgroundTransparency = 1
                    textControl.Position = UDim2.new(0.5, 0, 1, -6)
                    H(textControl, 0.3, {
                        TextTransparency = 0,
                        BackgroundTransparency = 0,
                        Position = UDim2.new(0.5, 0, 1, -16),
                    })
                    task.delay(2.4, function()
                        local FF = IF ~= CF or not textControl.Parent
                        if FF then
                            return
                        end
                        H(textControl, 0.3, {
                            TextTransparency = 1,
                            BackgroundTransparency = 1,
                        })
                        task.delay(0.3, function()
                            local FF = IF == CF and textControl.Parent
                            if FF then
                                textControl.Visible = false
                            end
                        end)
                    end)
                end
            end
            local aF = W and 30 or 28
            local IF = x("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, W and -10 or -14, 0.5, 0),
                Size = UDim2.fromOffset(aF * 3 + 12, aF),
                BackgroundTransparency = 1,
                ZIndex = 4,
            }, header)
            B(IF, 6, true)
            local function label(layoutOrder, gF, iF, bF)
                local BF = s(IF, {
                    Size = UDim2.fromOffset(aF, aF),
                    LayoutOrder = layoutOrder,
                    BackgroundColor3 = theme.SurfaceElement,
                    BackgroundTransparency = 0,
                    ZIndex = 4,
                })
                C(BF, radiusMd)
                g(BF, theme.Hairline, 1)
                gF(BF)
                a(BF.MouseEnter, function()
                    H(BF, 0.14, {
                        BackgroundColor3 = theme.SurfaceHover,
                    })
                end)
                a(BF.MouseLeave, function()
                    H(BF, 0.2, {
                        BackgroundColor3 = theme.SurfaceElement,
                    })
                end)
                pressable(BF)
                a(BF.Activated, bF)
                uiKit.tip(BF, iF)
                return BF
            end
            local aF, IF, CF, gF, iF = false, false, dF, QF
            local function dF()
                H(hF, 0.25, {
                    Size = UDim2.fromOffset(cF, aF and SF + OF + 1 or uF),
                })
            end
            label(
                1,
                function(QF)
                    T(x("Frame", {
                        Size = UDim2.fromOffset(11, 2),
                        BackgroundColor3 = theme.TextMuted,
                        BorderSizePixel = 0,
                        ZIndex = 5,
                    }, QF))
                end,
                "Fold the window up to its header.",
                function()
                    aF = not aF
                    dF()
                end
            )
            label(
                2,
                function(QF)
                    local bF = T(x("Frame", {
                        Size = UDim2.fromOffset(10, 10),
                        BackgroundTransparency = 1,
                        ZIndex = 5,
                    }, QF))
                    C(bF, 2)
                    g(bF, theme.TextMuted, 1.5)
                end,
                "Make the window as big as the screen allows, or back to the size it was.",
                function()
                    IF, aF = not IF, false
                    local QF = IF
                    if QF then
                        CF, gF, iF = cF, uF, JF
                        local QF, vector3 = W and 6 or 40, (W and lF() or _F()) / jF
                        local BF, GF =
                            math.max(DF, math.floor(vector3.X - 2 * QF)),
                            math.max(PF, math.floor(vector3.Y - 2 * QF))
                        cF, uF = BF, GF
                        JF = Vector2.new(QF * jF, QF * jF)
                    else
                        cF, uF = CF, gF
                        local QF = iF
                        if QF then
                            JF = iF
                        end
                    end
                    dF()
                end
            )
            label(
                3,
                function(dF)
                    T(z(dF, "x", 14, theme.TextMuted, {
                        ZIndex = 5,
                    }))
                end,
                "Close the menu. The menu key opens it again.",
                function()
                    if k.onClose then
                        k.onClose()
                    end
                end
            )
            do
                local dF, QF
                a(header.InputBegan, function(CF)
                    local gF = K(CF) and context.pressOnTop(hF, CF)
                    if gF then
                        local gF
                        gF, dF = Vector2.new(CF.Position.X, CF.Position.Y) - JF, true
                        QF = gF
                    end
                end)
                a(userInputService.InputChanged, function(CF)
                    local gF = dF and t(CF)
                    if gF then
                        JF = Vector2.new(CF.Position.X, CF.Position.Y) - QF
                    end
                end)
                a(userInputService.InputEnded, function(QF)
                    local CF = K(QF)
                    if CF then
                        dF = false
                    end
                end)
                a(runService.RenderStepped, function(dF)
                    local vector3 = JF - wF
                    local CF = vector3.Magnitude > 0.35
                    if CF then
                        local CF = wF
                        wF = CF + vector3 * (1 - math.exp(-dF * 13))
                        vF()
                    else
                        local dF = vector3.Magnitude > 0
                        if dF then
                            wF = JF
                            vF()
                        end
                    end
                end)
            end
            do
                yF = W and 30 or 16
                local dF, QF =
                    s(root, {
                        Name = "Resize",
                        AnchorPoint = Vector2.new(1, 1),
                        Position = UDim2.new(1, -4, 1, -4),
                        Size = UDim2.fromOffset(yF, yF),
                        ZIndex = 65,
                    }), {}
                for index6 = 0, 2, 1 do
                    for index7 = 0, 2 - index6, 1 do
                        QF[#QF + 1] = x("Frame", {
                            Position = UDim2.fromOffset(yF - 4 - 4 * index6, yF - 4 - 4 * index7),
                            Size = UDim2.fromOffset(2, 2),
                            BackgroundColor3 = theme.TextMuted,
                            BorderSizePixel = 0,
                            ZIndex = 66,
                        }, dF)
                    end
                end
                a(dF.MouseEnter, function()
                    for index2, entry in ipairs(QF) do
                        entry.BackgroundColor3 = theme.TextPrimary
                    end
                end)
                a(dF.MouseLeave, function()
                    for index2, entry in ipairs(QF) do
                        entry.BackgroundColor3 = theme.TextMuted
                    end
                end)
                uiKit.tip(dF, "Drag to resize the window.")
                local QF, position, wF, CF
                a(dF.InputBegan, function(dF)
                    local gF = K(dF)
                    if gF then
                        local position2
                        position2, QF = dF.Position, true
                        position, wF, CF, aF, IF = position2, cF, uF, false, false
                    end
                end)
                a(userInputService.InputChanged, function(dF)
                    local aF = QF and t(dF)
                    if aF then
                        local vector3, vector4, IF, gF, iF =
                            Vector2.new(dF.Position.X - position.X, dF.Position.Y - position.Y) / jF,
                            (W and lF() or _F()) / jF,
                            math.clamp,
                            math.floor,
                            wF
                        cF = IF(gF(iF + vector3.X), DF, math.max(DF, math.floor(vector4.X - 20)))
                        gF, iF, IF = math.clamp, math.floor, CF
                        uF = gF(iF(IF + vector3.Y), PF, math.max(PF, math.floor(vector4.Y - 20)))
                        hF.Size = UDim2.fromOffset(cF, uF)
                    end
                end)
                a(userInputService.InputEnded, function(t)
                    local dF = K(t) and QF
                    if dF then
                        QF = false
                        EF()
                    end
                end)
            end
            frame = SF + OF + 1
            yF = x("Frame", {
                Name = "Sidebar",
                Position = UDim2.fromOffset(0, frame),
                Size = UDim2.new(0, LF, 1, -frame),
                BackgroundColor3 = Color3.fromHex("141418"),
                BorderSizePixel = 0,
            }, root)
            x("Frame", {
                Name = "Rule",
                Position = UDim2.new(1, -1, 0, 0),
                Size = UDim2.new(0, 1, 1, 0),
                BackgroundColor3 = theme.Hairline,
                BorderSizePixel = 0,
            }, yF)
            local K = W and 8 or 10
            local t, dF = W and 40 or iconGrad + 4, 4
            accentBar = x("Frame", {
                Position = UDim2.fromOffset(K, K),
                Size = UDim2.new(1, -2 * K, 1, W and -16 or -86),
                BackgroundTransparency = 1,
            }, yF)
            b(accentBar, dF)
            local QF = x("Frame", {
                Name = "NavMark",
                Position = UDim2.fromOffset(W and 3 or 10, 19),
                Size = UDim2.fromOffset(3, 20),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                ZIndex = 3,
            }, yF)
            C(QF, 2)
            uiKit.accentGradient(QF, 90)
            local body, DF =
                x("Frame", {
                    Name = "Content",
                    Position = UDim2.fromOffset(LF, frame),
                    Size = UDim2.new(1, -LF, 1, -frame),
                    BackgroundTransparency = 1,
                }, root), W and 44 or 60
            local LF = W and 11 or 6
            local PF = x("Frame", {
                Size = UDim2.new(1, -32, 0, DF),
                Position = UDim2.fromOffset(18, 0),
                BackgroundTransparency = 1,
            }, body)
            local _F = z(PF, "swords", 18, Color3.new(1, 1, 1), {
                Position = UDim2.fromOffset(0, W and 13 or 10),
            })
            uiKit.accentGradient(_F, 45)
            local title = G(PF, "", 16, theme.TextPrimary, fontWeight.Bold, {
                Position = UDim2.fromOffset(28, LF),
                Size = UDim2.new(0.58, -36, 0, 22),
            })
            local textControl2 = G(PF, "", 11, theme.TextMuted, fontWeight.Regular, {
                Position = UDim2.fromOffset(28, 28),
                Size = UDim2.new(0.58, -36, 0, 28),
                TextWrapped = true,
                TextYAlignment = Enum.TextYAlignment.Top,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Visible = not W,
            })
            x("Frame", {
                Position = UDim2.new(0, 18, 0, DF),
                Size = UDim2.new(1, -36, 0, 1),
                BackgroundColor3 = theme.Hairline,
                BorderSizePixel = 0,
            }, body)
            local uF = x("Frame", {
                Name = "Pages",
                Position = UDim2.fromOffset(0, DF + 1),
                Size = UDim2.new(1, 0, 1, -(DF + 1)),
                BackgroundTransparency = 1,
            }, body)
            iconGrad = W and 30 or 32
            local EF = x("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.new(0.42, 0, 0, iconGrad),
                BackgroundColor3 = theme.SurfaceField,
                BorderSizePixel = 0,
            }, PF)
            x("UISizeConstraint", {
                MinSize = Vector2.new(W and 150 or 170, iconGrad),
                MaxSize = Vector2.new(W and 260 or 300, iconGrad),
            }, EF)
            C(EF, radiusMd)
            local JF = g(EF, theme.Hairline, 1)
            local wF = z(EF, "search", 15, theme.TextMuted, {
                Position = UDim2.fromOffset(10, (iconGrad - 15) / 2),
            })
            local textControl3 = x("TextBox", {
                Position = UDim2.fromOffset(32, 0),
                Size = UDim2.new(1, -40, 1, 0),
                BackgroundTransparency = 1,
                Text = "",
                PlaceholderText = "Search every option...",
                PlaceholderColor3 = theme.TextMuted,
                TextColor3 = theme.TextPrimary,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                ClearTextOnFocus = false,
            }, EF)
            uiKit.setFont(textControl3, "sans", fontWeight.Medium)
            local textService, CF, gF, iF = game:GetService("TextService"), 0, 0, {}
            local bF = W and 2 or 4
            local function BF(GF)
                if W then
                    return LF
                end
                local zF = iF[GF or textControl2.Text]
                GF = zF and zF.w == gF and zF.lines <= 1
                if GF then
                    return math.floor((DF - 33) / 2)
                end
                return LF
            end
            local function LF(DF)
                local GF, zF = BF(), iF[textControl2.Text]
                textControl2.TextSize = zF and zF.w == gF and zF.size or 11
                if DF == "now" then
                    title.Position, textControl2.Position, _F.Position =
                        UDim2.fromOffset(28, GF), UDim2.fromOffset(28, GF + 22), UDim2.fromOffset(0, GF + bF)
                    return
                end
                if DF then
                    title.Position, textControl2.Position =
                        UDim2.fromOffset(28, GF + DF), UDim2.fromOffset(28, GF + 22 + DF)
                end
                twd(title, 0.4, {
                    Position = UDim2.fromOffset(28, GF),
                })
                twd(textControl2, 0.4, {
                    Position = UDim2.fromOffset(28, GF + 22),
                }, DF and 0.05 or 0)
                H(_F, 0.3, {
                    Position = UDim2.fromOffset(0, GF + bF),
                })
            end
            local function DF(text, width)
                local function GF(size)
                    local success, TF = pcall(function()
                        local textControl4 = Instance.new("GetTextBoundsParams")
                        textControl4.Text, textControl4.Font = text, textControl2.FontFace
                        textControl4.Size = size
                        textControl4.Width = width
                        return textService:GetTextBoundsAsync(textControl4).Y
                    end)
                    return success and TF or nil
                end
                local IF = GF(11)
                if not IF then
                    return nil
                end
                if IF <= 28 then
                    return {
                        w = width,
                        size = 11,
                        lines = math.max(1, math.floor(IF / 11 + 0.5)),
                    }
                end
                IF = GF(10) or 20
                return {
                    w = width,
                    size = 10,
                    lines = math.max(1, math.floor(IF / 10 + 0.5)),
                }
            end
            local IF = {}
            local function bF()
                local BF = math.max(120, math.floor(PF.AbsoluteSize.X - EF.AbsoluteSize.X - 28 - 14))
                title.Size = UDim2.new(0, BF, 0, 22)
                textControl2.Size = UDim2.new(0, BF, 0, 28)
                gF = BF
                CF += 1
                local gF = CF
                local GF = {
                    textControl2.Text,
                }
                for entry in pairs(IF) do
                    if entry ~= textControl2.Text then
                        GF[#GF + 1] = entry
                    end
                end
                task.spawn(function()
                    for index2, entry2 in ipairs(GF) do
                        index2 = CF
                        if gF ~= index2 then
                            return
                        end
                        index2 = iF[entry2]
                        if entry2 ~= "" and not (index2 and index2.w == BF) then
                            iF[entry2] = DF(entry2, BF)
                        end
                    end
                    local DF = CF
                    if gF == DF then
                        LF(nil)
                    end
                end)
            end
            PF:GetPropertyChangedSignal("AbsoluteSize"):Connect(bF)
            EF:GetPropertyChangedSignal("AbsoluteSize"):Connect(bF)
            local function icon()
                IF[textControl2.Text] = true
                bF()
            end
            textControl2:GetPropertyChangedSignal("Text"):Connect(icon)
            task.defer(bF)
            local PF, CF, gF =
                {
                    {
                        id = "AutoSell",
                        name = "Auto Sell",
                        icon = "coins",
                        desc = "Sell what drops, keep what matters.",
                    },
                }, {}
            local iF, BF, GF, selectTab = false, false, false
            for index8, entry3 in ipairs(PF) do
                local frame2 = s(accentBar, {
                    LayoutOrder = index8,
                    Size = UDim2.new(1, 0, 0, t),
                    BackgroundColor3 = theme.SurfaceElement,
                    BackgroundTransparency = 1,
                })
                C(frame2, radiusMd)
                stroke = g(frame2, theme.Hairline, 1)
                stroke.Enabled = false
                icon = z(frame2, entry3.icon, W and 18 or 16, theme.TextSub, {
                    Position = UDim2.fromOffset(13, 11),
                })
                if W then
                    T(icon)
                end
                iconGrad = uiKit.accentGradient(icon, 45)
                iconGrad.Enabled = false
                label = G(frame2, entry3.name, 13, theme.TextSub, fontWeight.Medium, {
                    Position = UDim2.fromOffset(40, 0),
                    Size = UDim2.new(1, -44, 1, 0),
                    TextTruncate = Enum.TextTruncate.AtEnd,
                })
                if W then
                    label.Visible = false
                    uiKit.tip(frame2, entry3.name)
                end
                CF[entry3.id] = {
                    frame = frame2,
                    stroke = stroke,
                    icon = icon,
                    iconGrad = iconGrad,
                    label = label,
                    index = index8,
                }
                a(frame2.MouseEnter, function()
                    local KF = gF
                    if KF ~= entry3.id then
                        H(frame2, 0.14, {
                            BackgroundTransparency = 0.4,
                        })
                    end
                end)
                a(frame2.MouseLeave, function()
                    local KF = gF
                    if KF ~= entry3.id then
                        H(frame2, 0.2, {
                            BackgroundTransparency = 1,
                        })
                    end
                end)
                a(frame2.Activated, function()
                    selectTab(entry3.id)
                end)
                frame = x("Frame", {
                    Name = entry3.id,
                    Size = UDim2.fromScale(1, 1),
                    BackgroundTransparency = 1,
                    Visible = false,
                }, uF)
                body = x("ScrollingFrame", {
                    Name = "Body",
                    Size = UDim2.fromScale(1, 1),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    ScrollBarThickness = 4,
                    ScrollBarImageColor3 = Color3.fromHex("50505f"),
                    CanvasSize = UDim2.new(),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollingDirection = Enum.ScrollingDirection.Y,
                }, frame)
                if W then
                    i(body, 8, 10, 16, 10)
                else
                    i(body, 12, 18, 24, 18)
                end
                b(body, 10)
                k.pages[entry3.id] = {
                    frame = frame,
                    body = body,
                    tab = entry3,
                }
                k.order[index8] = entry3.id
            end
            local function sF(TF, WF)
                local KF = CF[TF]
                if not KF then
                    return
                end
                local TF, tF = K + (KF.index - 1) * (t + dF) + (t - 20) / 2, W and 3 or 10
                if WF then
                    twd(QF, 0.38, {
                        Position = UDim2.fromOffset(tF, TF),
                    }, 0, Enum.EasingStyle.Back)
                else
                    QF.Position = UDim2.fromOffset(tF, TF)
                end
            end
            selectTab = function(K, t)
                local dF = gF
                if dF == K then
                    return
                end
                gF = K
                dF = nil
                for key, page in pairs(k.pages) do
                    page.frame.Visible = key == K
                    if key == K then
                        if not t then
                            page.frame.Position = UDim2.fromOffset(18, 0)
                            local frame3, WF = page.frame, {}
                            WF.Position = UDim2.fromOffset(0, 0)
                            twd(frame3, 0.4, WF)
                        end
                        dF = page
                    else
                    end
                end
                for key2, entry in pairs(CF) do
                    local enabled, WF, KF = key2 == K, entry.frame, {}
                    KF.BackgroundTransparency = enabled and 0 or 1
                    H(WF, 0.2, KF)
                    entry.stroke.Enabled = enabled
                    key2, WF = entry.label, {}
                    WF.TextColor3 = enabled and theme.TextPrimary or theme.TextSub
                    H(key2, 0.2, WF)
                    uiKit.setFont(entry.label, "sans", enabled and fontWeight.SemiBold or fontWeight.Medium)
                    entry.iconGrad.Enabled = enabled
                    entry.icon.ImageColor3 = enabled and Color3.new(1, 1, 1) or theme.TextSub
                end
                sF(K, iF)
                iF = true
                K = dF and dF.tab
                if K then
                    title.Text, textControl2.Text = K.name, K.desc
                    _F.Image = "rbxassetid://"
                        .. tostring(({
                            swords = 10734975692,
                            users = 10747373426,
                            shield = 10734951847,
                            coins = 10709811110,
                            bell = 10709775704,
                            eye = 10723346959,
                        })[K.icon] or 10723415903)
                end
                if t then
                    LF("now")
                end
                K = not t
                if K then
                    title.TextTransparency = 1
                    textControl2.TextTransparency = 1
                    _F.ImageTransparency = 1
                    LF(6)
                    twd(title, 0.4, {
                        TextTransparency = 0,
                    })
                    twd(textControl2, 0.4, {
                        TextTransparency = 0,
                    }, 0.05)
                    twd(_F, 0.35, {
                        ImageTransparency = 0,
                    })
                    t = dF and GF and dF.body.CanvasPosition.Y < 2
                    if t then
                        NF(dF.body)
                    end
                end
            end
            k.selectTab = selectTab
            k.page = function(name, t, desc)
                local dF = k.pages[name]
                if not dF then
                    local QF, tab =
                        #k.order + 1, {
                            id = name,
                            name = t or name,
                            icon = "info",
                            desc = desc or "",
                        }
                    PF[#PF + 1] = tab
                    local frame3 = x("Frame", {
                        Name = name,
                        Size = UDim2.fromScale(1, 1),
                        BackgroundTransparency = 1,
                        Visible = false,
                    }, uF)
                    local body2 = x("ScrollingFrame", {
                        Name = "Body",
                        Size = UDim2.fromScale(1, 1),
                        BackgroundTransparency = 1,
                        BorderSizePixel = 0,
                        ScrollBarThickness = 4,
                        ScrollBarImageColor3 = Color3.fromHex("50505f"),
                        CanvasSize = UDim2.new(),
                        AutomaticCanvasSize = Enum.AutomaticSize.Y,
                        ScrollingDirection = Enum.ScrollingDirection.Y,
                    }, frame3)
                    if W then
                        i(body2, 8, 10, 16, 10)
                    else
                        i(body2, 12, 18, 24, 18)
                    end
                    b(body2, 10)
                    dF = {
                        frame = frame3,
                        body = body2,
                        tab = tab,
                    }
                    k.pages[name] = dF
                    k.order[QF] = name
                else
                end
                if desc and desc ~= "" and not dF.tab.descFixed then
                    dF.tab.desc = desc
                end
                return {
                    frame = dF.frame,
                    body = dF.body,
                    title = title,
                    header = header,
                    fit = function() end,
                    isPinned = function()
                        return false
                    end,
                    setPinned = function() end,
                }
            end
            k.menuPage = function(K)
                local t = k.pages[K]
                return t and t.frame or nil
            end
            k.menuButton = function(K)
                local t = s(f, {
                    Name = "MobileMenuButton",
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 14, 0.35, 0),
                    Size = UDim2.fromOffset(52, 52),
                    BackgroundColor3 = theme.SurfaceHeader,
                    BackgroundTransparency = 0,
                    ZIndex = 60,
                })
                C(t, radiusLg)
                g(t, theme.Hairline, 1)
                local X = x("CanvasGroup", {
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, radiusLg + SF),
                    ZIndex = 61,
                }, t)
                C(X, radiusLg)
                uiKit.accentGradient(
                    x("Frame", {
                        BackgroundColor3 = Color3.new(1, 1, 1),
                        BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, SF),
                        ZIndex = 61,
                    }, X),
                    0
                )
                local N, dF = #oF[1] * 2, #oF * 2
                X = x("Frame", {
                    BackgroundTransparency = 1,
                    Position = UDim2.fromOffset(math.floor((52 - N) / 2), math.floor((52 - dF) / 2) + 1),
                    Size = UDim2.fromOffset(N, dF),
                    ZIndex = 61,
                }, t)
                for index2 = 1, #oF, 1 do
                    for index3 = 1, #oF[1], 1 do
                        if oF[index2]:sub(index3, index3) == "#" then
                            x("Frame", {
                                BackgroundColor3 = theme.AccentB,
                                BorderSizePixel = 0,
                                Position = UDim2.fromOffset((index3 - 1) * 2, (index2 - 1) * 2),
                                Size = UDim2.fromOffset(2, 2),
                                ZIndex = 61,
                            }, X)
                        end
                    end
                end
                a(t.MouseEnter, function()
                    H(t, 0.14, {
                        BackgroundColor3 = theme.SurfaceHover,
                    })
                end)
                a(t.MouseLeave, function()
                    H(t, 0.2, {
                        BackgroundColor3 = theme.SurfaceHeader,
                    })
                end)
                pressable(t)
                a(t.Activated, K)
                return t
            end
            for index9, entry4 in ipairs(PF) do
                entry4.descFixed = true
            end
            do
                accentBar = k.pages.Farm.body
                local N = x("Frame", {
                    Name = "Welcome",
                    LayoutOrder = -100,
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                }, accentBar)
                local K = x("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = theme.SurfaceElement,
                    BorderSizePixel = 0,
                }, N)
                C(K, radiusMd)
                g(K, theme.Hairline, 1)
                i(K, 12, 14, 14, 14)
                b(K, 8)
                local function t(layoutOrder, dF)
                    local QF = x("Frame", {
                        LayoutOrder = layoutOrder,
                        Size = UDim2.new(1, 0, 0, dF),
                        BackgroundTransparency = 1,
                    }, K)
                    B(QF, 0)
                    return QF
                end
                local function X(dF, layoutOrder, LF, SF, _F, lF)
                    return G(dF, LF, SF, _F, lF, {
                        LayoutOrder = layoutOrder,
                        Size = UDim2.fromOffset(0, SF + 8),
                        AutomaticSize = Enum.AutomaticSize.X,
                    })
                end
                stroke, body, label = W and 18 or 24, W and 12 or 14, W and 52 or 72
                icon = t(1, stroke + 8)
                X(icon, 1, "Welcome, ", stroke, theme.TextPrimary, fontWeight.Medium)
                local textControl5 = X(icon, 2, "", stroke, theme.AccentMid, fontWeight.Medium)
                local QF = X(icon, 3, ".", stroke, theme.TextPrimary, fontWeight.Medium)
                frame = t(2, body + 6)
                X(frame, 1, "Version: ", body, theme.TextPrimary, fontWeight.Medium)
                X(frame, 2, tostring(ver), body, theme.AccentMid, fontWeight.Medium)
                X(frame, 3, "      Level: ", body, theme.TextPrimary, fontWeight.Medium)
                local textControl6 = X(frame, 4, "-", body, theme.AccentMid, fontWeight.Medium)
                x("Frame", {
                    LayoutOrder = 3,
                    Size = UDim2.new(1, 0, 0, 1),
                    BackgroundColor3 = theme.Hairline,
                    BorderSizePixel = 0,
                }, K)
                iconGrad = x("Frame", {
                    LayoutOrder = 4,
                    Size = UDim2.new(1, 0, 0, label),
                    BackgroundTransparency = 1,
                }, K)
                local K = x("ImageLabel", {
                    Size = UDim2.fromOffset(label, label),
                    BackgroundColor3 = theme.SurfaceField,
                    Image = "",
                }, iconGrad)
                C(K, radiusMd)
                g(K, theme.Hairline, 1)
                task.spawn(function()
                    local success, image = pcall(function()
                        local userId, headShot, size150X150 =
                            localPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150
                        return players:GetUserThumbnailAsync(userId, headShot, size150X150)
                    end)
                    if success and K.Parent then
                        K.Image = image
                    end
                end)
                t = x("Frame", {
                    Position = UDim2.fromOffset(label + 16, W and 0 or 6),
                    Size = UDim2.new(1, -(label + 16), 1, W and 0 or -6),
                    BackgroundTransparency = 1,
                }, iconGrad)
                b(t, W and 0 or 2)
                local textControl7 = G(t, "", W and 13 or 15, theme.AccentMid, fontWeight.SemiBold, {
                    LayoutOrder = 1,
                })
                local textControl8 = G(t, "", W and 11 or 13, theme.TextPrimary, fontWeight.Medium, {
                    LayoutOrder = 2,
                })
                local textControl9 = G(t, "", W and 11 or 13, theme.TextSub, fontWeight.Medium, {
                    LayoutOrder = 3,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                })
                local function t(SF)
                    local value
                    pcall(function()
                        value = localPlayer.leaderstats[SF].Value
                    end)
                    return value
                end
                local function SF(DF)
                    local _F, lF = 1, tostring(math.floor((tonumber(DF) or 0) + 0.5))
                    while _F > 0 do
                        lF, _F = lF:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
                    end
                    return lF
                end
                local function refreshWelcome()
                    local _F, text =
                        config.streamer == true,
                        localPlayer.DisplayName ~= "" and localPlayer.DisplayName or localPlayer.Name
                    text = _F and tostring(config.streamerNameText or "") or text
                    textControl5.Text, textControl5.Visible, QF.Visible = text, text ~= "", text ~= ""
                    textControl6.Text = _F and "XXX" or tostring(t("Level") or "-")
                    textControl7.Text = _F and (text ~= "" and "@" .. text or "") or "@" .. localPlayer.Name
                    textControl7.Visible = textControl7.Text ~= ""
                    local I = t("Gold")
                    textControl8.Text = "Gold: "
                        .. (
                            _F
                                and config.streamerGoldText
                                and config.streamerGoldText ~= ""
                                and tostring(config.streamerGoldText)
                            or (I and SF(I) or "-")
                        )
                    local I = "idle"
                    pcall(function()
                        local toString, X =
                            tostring,
                            context.LB and context.LB.status or (runtimeState.farmEnabled and "running" or "idle")
                        I = toString(X)
                    end)
                    textControl9.Text = "Status: " .. I
                    K.ImageTransparency = _F and 1 or 0
                end
                refreshWelcome()
                task.spawn(function()
                    while not runtimeState.destroyed and N.Parent do
                        task.wait(1)
                        pcall(refreshWelcome)
                    end
                end)
                k.refreshWelcome = refreshWelcome
            end
            do
                local N = x("Frame", {
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.new(0, 10, 1, -10),
                    Size = UDim2.new(1, -20, 0, 50),
                    BackgroundColor3 = theme.SurfaceElement,
                    BorderSizePixel = 0,
                    Visible = not W,
                }, yF)
                C(N, radiusMd)
                g(N, theme.Hairline, 1)
                local I = x("ImageLabel", {
                    Position = UDim2.fromOffset(9, 9),
                    Size = UDim2.fromOffset(32, 32),
                    BackgroundColor3 = theme.SurfaceField,
                    Image = "",
                }, N)
                C(I, 16)
                task.spawn(function()
                    local success, image = pcall(function()
                        local userId, headShot, size48X48 =
                            localPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48
                        return players:GetUserThumbnailAsync(userId, headShot, size48X48)
                    end)
                    if success and I.Parent then
                        I.Image = image
                    end
                end)
                local textControl10 = G(N, "", 12, theme.TextPrimary, fontWeight.SemiBold, {
                    Position = UDim2.fromOffset(50, 8),
                    Size = UDim2.new(1, -56, 0, 18),
                    TextTruncate = Enum.TextTruncate.AtEnd,
                })
                G(N, tostring(ver), 11, theme.TextMuted, fontWeight.Medium, {
                    Position = UDim2.fromOffset(50, 26),
                    Size = UDim2.new(1, -56, 0, 16),
                })
                local function t()
                    local X = config.streamer == true
                    textControl10.Text = X and tostring(config.streamerNameText or "")
                        or (localPlayer.DisplayName ~= "" and localPlayer.DisplayName or localPlayer.Name)
                    I.ImageTransparency = X and 1 or 0
                end
                t()
                task.spawn(function()
                    while not runtimeState.destroyed and N.Parent do
                        task.wait(1)
                        pcall(t)
                    end
                end)
            end
            local N = {}
            local I = x("Frame", {
                Name = "FlashLayer",
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                ClipsDescendants = true,
                ZIndex = 19,
            }, uF)
            local function K(t)
                local X = x("Frame", {
                    BackgroundColor3 = theme.AccentB,
                    BackgroundTransparency = 0.8,
                    BorderSizePixel = 0,
                    ZIndex = 20,
                }, I)
                C(X, radiusMd)
                local dF = g(X, theme.AccentMid, 1.5)
                local function QF()
                    if not t.Parent then
                        return
                    end
                    local LF = mF.Scale > 0 and mF.Scale or 1
                    local vector3 = (t.AbsolutePosition - I.AbsolutePosition) / LF
                    X.Position = UDim2.fromOffset(vector3.X, vector3.Y)
                    X.Size = UDim2.fromOffset(t.AbsoluteSize.X / LF, t.AbsoluteSize.Y / LF)
                end
                QF()
                local connection = runService.RenderStepped:Connect(QF)
                H(X, 1.2, {
                    BackgroundTransparency = 1,
                })
                H(dF, 1.2, {
                    Transparency = 1,
                })
                task.delay(1.3, function()
                    connection:Disconnect()
                    X:Destroy()
                end)
            end
            local function I()
                local t, X = {}, {}
                for index2, entry in ipairs(k.order) do
                    index2 = k.pages[entry]
                    for index3, descendant in ipairs(index2.body:GetDescendants()) do
                        local label2, frame3
                        if
                            descendant:IsA("Frame")
                            and (
                                descendant.Name == "Row"
                                or descendant.Name == "Slider"
                                or descendant.Name == "RangeSlider"
                                or descendant.Name == "ListInput"
                            )
                        then
                            index3 = descendant:FindFirstChildWhichIsA("TextLabel")
                                or descendant:FindFirstChild("Head")
                                    and descendant.Head:FindFirstChildWhichIsA("TextLabel", true)
                            if index3 and index3.Text ~= "" then
                                label2, frame3 = index3.Text, descendant
                            else
                            end
                        else
                            if
                                descendant:IsA("TextButton")
                                and descendant.Name == "Button"
                                and descendant.Text ~= ""
                            then
                                label2, frame3 = descendant.Text, descendant
                            else
                            end
                        end
                        if label2 and frame3 then
                            descendant = entry .. "|" .. label2
                            if not X[descendant] then
                                X[descendant] = true
                                local X, LF =
                                    #t + 1, {
                                        label = label2,
                                        frame = frame3,
                                        page = entry,
                                        tab = index2.tab,
                                    }
                                LF.hint, t[X] = context.tipTextOf and context.tipTextOf(frame3) or "", LF
                            end
                        end
                    end
                end
                return t
            end
            local function t(X)
                kF()
                textControl3:ReleaseFocus()
                selectTab(X.page, true)
                task.defer(function()
                    local parent = X.frame.Parent
                    while parent and parent ~= k.pages[X.page].body do
                        local QF = k.sections[parent]
                        if QF and not QF.isOpen() then
                            QF.setOpen(true)
                        end
                        parent = parent.Parent
                    end
                    task.wait(0.4)
                    local body2, parent2 = k.pages[X.page].body, X.frame.Parent
                    if parent2 then
                        local QF = (X.frame.AbsolutePosition.Y - body2.AbsolutePosition.Y) / jF
                            + body2.CanvasPosition.Y
                            - 18
                        H(body2, 0.35, {
                            CanvasPosition = Vector2.new(0, math.max(0, QF)),
                        })
                        task.delay(0.3, function()
                            if X.frame.Parent then
                                K(X.frame)
                            end
                        end)
                    end
                end)
            end
            local function K(textMuted2)
                for index2, child in ipairs(rF:GetChildren()) do
                    if child ~= AF then
                        child:Destroy()
                    end
                end
                local dF, QF, LF = string.lower(textControl3.Text):gsub("^%s+", ""):gsub("%s+$", ""), I(), {}
                if dF == "" then
                    local I = {
                        ["Enable Autofarm"] = 1,
                        ["Run this party"] = 2,
                        ["Send to Discord"] = 3,
                        Enabled = 4,
                    }
                    for index3, entry in ipairs(QF) do
                        if I[entry.label] and not (entry.label == "Enabled" and entry.page ~= "AutoSell") then
                            LF[#LF + 1] = entry
                        end
                    end
                    table.sort(LF, function(OF, SF)
                        return I[OF.label] < I[SF.label]
                    end)
                else
                    for index4, entry2 in ipairs(QF) do
                        index4 = string.lower(entry2.label)
                        local SF = index4:sub(1, #dF) == dF and 3
                            or index4:find(dF, 1, true) and 2
                            or string.lower(entry2.hint or ""):find(dF, 1, true) and 1
                            or 0
                        if SF > 0 then
                            LF[#LF + 1] = {
                                e = entry2,
                                s = SF,
                            }
                        end
                    end
                    table.sort(LF, function(I, OF)
                        if I.s ~= OF.s then
                            return I.s > OF.s
                        end
                        return I.e.label < OF.e.label
                    end)
                    for index5, entry5 in ipairs(LF) do
                        LF[index5] = entry5.e
                    end
                end
                N = LF
                rF.Visible = true
                local I, OF = UF(EF.AbsolutePosition), EF.AbsoluteSize.X / jF
                local SF = x("Frame", {
                    Position = UDim2.fromOffset(I.X, I.Y + 36),
                    Size = UDim2.fromOffset(OF, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = theme.SurfaceField,
                    BorderSizePixel = 0,
                    ZIndex = 51,
                }, rF)
                C(SF, radiusMd)
                g(SF, theme.Hairline, 1)
                i(SF, 4)
                local i = b(SF, 2)
                if textMuted2 then
                    task.defer(function()
                        if SF.Parent then
                            SF.Visible = false
                            slideTo(SF, i, 8, true)
                        end
                    end)
                end
                QF, textMuted2, OF, I =
                    dF == "" and "Most used"
                        or (#LF == 0 and "Nothing called that." or #LF .. (#LF == 1 and " option" or " options")),
                    theme.TextMuted,
                    fontWeight.SemiBold,
                    {
                        LayoutOrder = 0,
                    }
                I.Size, I.ZIndex = UDim2.new(1, 0, 0, 20), 52
                G(SF, QF, 10, textMuted2, OF, I)
                for index10 = 1, math.min(#LF, W and 6 or 8), 1 do
                    local i = LF[index10]
                    local X = s(SF, {
                        LayoutOrder = index10,
                        Size = UDim2.new(1, 0, 0, 30),
                        BackgroundColor3 = index10 == 1 and theme.SurfaceHover or theme.SurfaceElement,
                        BackgroundTransparency = 0,
                        ZIndex = 52,
                    })
                    C(X, 4)
                    local textControl4 =
                        G(X, i.label, 12, index10 == 1 and theme.AccentMid or theme.TextSub, fontWeight.Medium, {
                            Position = UDim2.fromOffset(10, 0),
                            Size = UDim2.new(1, -120, 1, 0),
                            TextTruncate = Enum.TextTruncate.AtEnd,
                            ZIndex = 53,
                        })
                    QF = x("Frame", {
                        AnchorPoint = Vector2.new(1, 0.5),
                        Position = UDim2.new(1, -8, 0.5, 0),
                        Size = UDim2.fromOffset(106, 18),
                        BackgroundTransparency = 1,
                        ZIndex = 53,
                    }, X)
                    B(QF, 4, true)
                    z(QF, i.tab.icon, 12, theme.TextMuted, {
                        LayoutOrder = 1,
                        ZIndex = 53,
                    })
                    G(QF, i.tab.name, 11, theme.TextMuted, fontWeight.Medium, {
                        LayoutOrder = 2,
                        Size = UDim2.fromOffset(0, 18),
                        AutomaticSize = Enum.AutomaticSize.X,
                        ZIndex = 53,
                    })
                    a(X.MouseEnter, function()
                        X.BackgroundColor3 = theme.SurfaceHover
                        textControl4.TextColor3 = theme.AccentMid
                    end)
                    a(X.MouseLeave, function()
                        X.BackgroundColor3 = index10 == 1 and theme.SurfaceHover or theme.SurfaceElement
                        textControl4.TextColor3 = index10 == 1 and theme.AccentMid or theme.TextSub
                    end)
                    a(X.Activated, function()
                        t(i)
                    end)
                end
            end
            a(textControl3.Focused, function()
                local I = BF
                if not I then
                    task.defer(function()
                        pcall(function()
                            textControl3:ReleaseFocus()
                        end)
                    end)
                    return
                end
                JF.Color = theme.AccentMid
                wF.ImageColor3 = theme.AccentMid
                K(true)
            end)
            a(textControl3.FocusLost, function(I)
                JF.Color = theme.Hairline
                wF.ImageColor3 = theme.TextMuted
                local i = I and N[1]
                if i then
                    t(N[1])
                    return
                end
                task.delay(0.35, function()
                    if not textControl3:IsFocused() then
                        kF()
                    end
                end)
            end)
            a(textControl3:GetPropertyChangedSignal("Text"), function()
                if textControl3:IsFocused() then
                    K(false)
                end
            end)
            local a = x("Frame", {
                Name = "HLNotifications",
                AnchorPoint = W and Vector2.new(1, 0) or Vector2.new(1, 1),
                Position = W and UDim2.new(1, -12, 0, 12) or UDim2.new(1, -16, 1, -16),
                Size = UDim2.fromOffset(312, 520),
                BackgroundTransparency = 1,
                ZIndex = 80,
            }, f)
            a:SetAttribute("HLUIMotionOwned", true)
            MF = x("UIScale", {
                Scale = ZF(),
            }, a)
            yF = b(a, 8)
            yF.VerticalAlignment, yF.HorizontalAlignment =
                W and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom, Enum.HorizontalAlignment.Right
            local f, N, I =
                {
                    info = {
                        icon = "bell",
                    },
                    party = {
                        icon = "users",
                    },
                    run = {
                        icon = "swords",
                    },
                    sell = {
                        icon = "coins",
                    },
                    success = {
                        icon = "check",
                        color = Color3.fromHex("2FBF71"),
                    },
                    warning = {
                        icon = "alert-triangle",
                        color = Color3.fromHex("FFB020"),
                    },
                    error = {
                        icon = "x",
                        color = Color3.fromHex("FF4D4F"),
                    },
                    drop = {
                        icon = "crown",
                        color = Color3.fromHex("FFA028"),
                    },
                    dropUltimate = {
                        icon = "crown",
                        color = Color3.fromHex("FF3B3B"),
                    },
                }, {}, {}
            local function i(b)
                if b.gone then
                    return
                end
                b.gone = true
                local card, K = b.card, {}
                K.Position, K.GroupTransparency = UDim2.fromOffset(330, 0), 1
                H(card, 0.28, K)
                task.delay(0.22, function()
                    if b.slot.Parent then
                        local slot, K = b.slot, {}
                        K.Size = UDim2.fromOffset(300, 0)
                        H(slot, 0.2, K)
                    end
                end)
                task.delay(0.5, function()
                    b.slot:Destroy()
                end)
                for index2, entry in ipairs(N) do
                    if entry == b then
                        table.remove(N, index2)
                        break
                    end
                end
            end
            local function notify(slot, K, t, X, dF)
                if config.notifications == false or runtimeState.destroyed then
                    return
                end
                K, t, dF = tostring(K or ""), tostring(t or ""), type(dF) == "table" and dF or {}
                local card = K .. "|" .. t
                if not dF.sticky and I[card] and os.clock() - I[card] < 4 then
                    return
                end
                I[card] = os.clock()
                X = X or 5
                local button, LF, OF =
                    f[slot] or f.info, dF.button and 100 or 66, math.floor(os.clock() * 1000) % 2000000000
                slot = x("Frame", {
                    Name = "Notification",
                    Size = UDim2.fromOffset(300, 0),
                    BackgroundTransparency = 1,
                    LayoutOrder = W and -OF or OF,
                }, a)
                card = x("CanvasGroup", {
                    Size = UDim2.fromOffset(300, LF),
                    Position = UDim2.fromOffset(330, 0),
                    BackgroundColor3 = theme.SurfaceHeader,
                    BorderSizePixel = 0,
                    GroupTransparency = 1,
                }, slot)
                C(card, radiusMd)
                g(card, theme.Hairline, 1)
                local textControl4 = G(card, K, 13, theme.TextPrimary, fontWeight.SemiBold, {
                    Position = UDim2.fromOffset(14, 11),
                    Size = UDim2.new(1, -72, 0, 18),
                    TextTruncate = Enum.TextTruncate.AtEnd,
                })
                local textControl11 = G(card, t, 11, theme.TextSub, fontWeight.Regular, {
                    Position = UDim2.fromOffset(14, 30),
                    Size = UDim2.new(1, -72, 0, 28),
                    TextWrapped = true,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                })
                OF = x("Frame", {
                    AnchorPoint = dF.button and Vector2.new(1, 0) or Vector2.new(1, 0.5),
                    Position = dF.button and UDim2.new(1, -12, 0, 12) or UDim2.new(1, -12, 0.5, 1),
                    Size = UDim2.fromOffset(34, 34),
                    BackgroundColor3 = theme.SurfaceElement,
                    BorderSizePixel = 0,
                }, card)
                C(OF, radiusMd)
                g(OF, theme.Hairline, 1)
                local e, F =
                    T(z(OF, button.icon, 17, button.color or theme.AccentMid)), x("Frame", {
                        AnchorPoint = Vector2.new(0, 1),
                        Position = UDim2.new(0, 0, 1, 0),
                        Size = UDim2.new(1, 0, 0, 2),
                        BackgroundColor3 = button.color or Color3.new(1, 1, 1),
                        BorderSizePixel = 0,
                    }, card)
                if button.color then
                    e:SetAttribute("HLThemeSkip", true)
                    F:SetAttribute("HLThemeSkip", true)
                else
                    uiKit.accentGradient(F, 0)
                end
                local C, g =
                    s(card, {
                        Size = UDim2.fromScale(1, 1),
                        ZIndex = 5,
                    }), {
                        slot = slot,
                        card = card,
                        sticky = dF.sticky == true,
                    }
                N[#N + 1] = g
                while #N > 5 do
                    button = N[1]
                    for index2, entry in ipairs(N) do
                        if not entry.sticky then
                            button = entry
                            break
                        end
                    end
                    i(button)
                end
                local function N()
                    i(g)
                end
                C.Activated:Connect(N)
                g.set = function(N, G)
                    if N ~= nil then
                        textControl4.Text = tostring(N)
                    end
                    if G ~= nil then
                        textControl11.Text = tostring(G)
                    end
                end
                g.close = function()
                    i(g)
                end
                if dF.button then
                    local button2 = dF.button
                    button = uiKit.button(card, tostring(button2.text or "OK"), "accent")
                    button.Size, button.Position = UDim2.fromOffset(104, 26), UDim2.fromOffset(14, 62)
                    button.ZIndex = 6
                    OF, e = button:FindFirstChild("Fill"), button:FindFirstChild("Label")
                    if OF then
                        OF.ZIndex = 6
                    end
                    if e then
                        e.ZIndex = 7
                        e.TextSize = 12
                    end
                    g.button = button
                    local function a()
                        if g.gone or g.busy then
                            return
                        end
                        g.busy = true
                        if type(button2.onClick) == "function" then
                            pcall(button2.onClick, g)
                        end
                    end
                    button.MouseButton1Click:Connect(a)
                end
                H(slot, 0.22, {
                    Size = UDim2.fromOffset(300, LF),
                })
                H(card, 0.38, {
                    Position = UDim2.fromOffset(0, 0),
                    GroupTransparency = 0,
                })
                if g.sticky then
                    F.Visible = false
                else
                    C, OF = TweenInfo.new, Enum.EasingStyle
                    LF, card = C(X, OF.Linear), {}
                    card.Size = UDim2.new(0, 0, 0, 2)
                    tweenService:Create(F, LF, card):Play()
                    task.delay(X, function()
                        i(g)
                    end)
                end
                return g
            end
            function context.notify(...)
                return (pcall(notify, ...))
            end
            function context.notifyCard(...)
                local success, a = pcall(notify, ...)
                if success then
                    return a
                end
                return nil
            end
            k.notify = notify
            k.notifyExamples = function()
                local f = {
                    { "party", "Queued", "Northern Lands, Insane." },
                    { "run", "Run started", "Northern Lands, Insane." },
                    {
                        "warning",
                        "Mod in the run",
                        "Every account stands still until the run ends, then back to the lobby.",
                    },
                    { "success", "Run won", "4:12. Replaying with the party." },
                    { "drop", "Legendary drop", "Mjolnir" },
                    { "sell", "Auto sell", "Sold 23 items." },
                    { "info", "Autofarm off", "In the lobby - it switches back on in the next dungeon." },
                    { "error", "Run lost", "Back to the lobby to make the party again." },
                }
                for index2, entry in ipairs(f) do
                    task.delay((index2 - 1) * 0.9, function()
                        notify(entry[1], entry[2], entry[3])
                    end)
                end
            end
            do
                local webhooks = context.WH
                local function a(e, N)
                    if not (webhooks and type(webhooks[e]) == "function") then
                        return
                    end
                    local I = webhooks[e]
                    webhooks[e] = function(...)
                        pcall(N, ...)
                        return I(...)
                    end
                end
                local e = {
                    legendary = true,
                    ultimate = true,
                    epic = true,
                }
                a("start", function(N, I)
                    notify("run", "Run started", ("%s, %s."):format(tostring(N or "Dungeon"), tostring(I or "")))
                end)
                a("finish", function(N)
                    local run = webhooks.run
                    local F = run and run.at and webhooks.runSecs(run) or nil
                    local f = F and ("%d:%02d"):format(math.floor(F / 60), F % 60) or ""
                    if N == false then
                        notify("error", "Run lost", (f ~= "" and f .. ". " or "") .. "Back to the party.")
                    else
                        notify(
                            "success",
                            "Run won",
                            (f ~= "" and f .. ". " or "") .. tostring(run and run.dungeon or "")
                        )
                    end
                end)
                a("item", function(f, N)
                    if N and e[string.lower(tostring(N))] then
                        notify(
                            string.lower(tostring(N)) == "ultimate" and "dropUltimate" or "drop",
                            tostring(N) .. " drop",
                            tostring(f)
                        )
                    end
                end)
                a("rodinClear", function()
                    notify("success", "Rodin cleared", "The bonus boss is down.")
                end)
                a("rodinFail", function()
                    notify("error", "Rodin failed", "The bonus boss got away.")
                end)
            end
            local parent3
            local a = 0
            local function e(N, I)
                a += 1
                local F = a
                local C = not parent3
                if C then
                    parent3 = x("CanvasGroup", {
                        Name = "Fader",
                        Size = UDim2.fromScale(1, 1),
                        BackgroundTransparency = 1,
                        GroupTransparency = N and 1 or 0,
                    }, hF)
                    root.Parent = parent3
                end
                hF.Visible = true
                local x = Instance.new("NumberValue")
                C = N and (YF < 0.999 and YF or 0.9)
                x.Value = C or YF
                YF = x.Value
                vF()
                local connection = x.Changed:Connect(function(i)
                    YF = i
                    vF()
                end)
                local i, b = TweenInfo.new, N and 0.5
                local B, G = b or 0.2, N and Enum.EasingStyle.Back
                b, C = G or Enum.EasingStyle.Quad, N and Enum.EasingDirection.Out
                local z, s = i(B, b, C or Enum.EasingDirection.In), {}
                s.Value = N and 1 or 0.93
                tweenService:Create(x, z, s):Play()
                z, G, s = parent3, TweenInfo.new, N and 0.28
                b, B = s or 0.18, Enum.EasingStyle
                C, i = G(b, B.Quad), {}
                i.GroupTransparency = N and 0 or 1
                tweenService:Create(z, C, i):Play()
                for index2, child in ipairs(RF:GetChildren()) do
                    s, z = N and 0.4 or 0.2, {}
                    z.BackgroundTransparency = N and 0.96 or 1
                    H(child, s, z)
                end
                task.delay(N and 0.52 or 0.22, function()
                    connection:Disconnect()
                    x:Destroy()
                    local o = a
                    if F ~= o then
                        return
                    end
                    if N then
                        YF = 1
                        vF()
                        root.Parent = hF
                        o = parent3
                        if o then
                            parent3:Destroy()
                            parent3 = nil
                        end
                    else
                        hF.Visible = false
                        pcall(function()
                            local f = userInputService:GetFocusedTextBox()
                            if f and (hF:IsAncestorOf(f)) then
                                f:ReleaseFocus()
                            end
                        end)
                    end
                    if I then
                        I()
                    end
                end)
            end
            k.isShown = function()
                local f = BF
                return f
            end
            k.setShown = function(f)
                f = f == true
                local o = BF
                if f == o then
                    return
                end
                BF = f
                if not f then
                    kF()
                    pcall(uiKit.hideTip)
                    pcall(function()
                        local x = userInputService:GetFocusedTextBox()
                        if x and (hF:IsAncestorOf(x)) then
                            x:ReleaseFocus()
                        end
                    end)
                end
                e(f)
                if f then
                    o = gF
                    if not o then
                        selectTab(k.order[1], true)
                    end
                    local f = gF and k.pages[gF]
                    local o = f and GF and f.body.CanvasPosition.Y < 2
                    if o then
                        task.defer(function()
                            NF(f.body)
                        end)
                    end
                end
            end
            k.finish = function()
                for index2, entry in ipairs(PF) do
                    if entry.desc and entry.desc ~= "" then
                        IF[entry.desc] = true
                    end
                end
                bF()
                GF = true
                local f = gF
                if not f then
                    selectTab(k.order[1], true)
                end
            end
            return k
        end

local statusChip, g

do
    local parent = localPlayer:WaitForChild("PlayerGui")
    local old = parent:FindFirstChild("DungeonAutofarmUI")
    if old then
        old:Destroy()
    end
    local dungeonAutofarmUi = Instance.new("ScreenGui")
    dungeonAutofarmUi.Name, dungeonAutofarmUi.ResetOnSpawn, dungeonAutofarmUi.IgnoreGuiInset, dungeonAutofarmUi.DisplayOrder, dungeonAutofarmUi.ZIndexBehavior =
        "DungeonAutofarmUI", false, true, 100, Enum.ZIndexBehavior.Sibling
    dungeonAutofarmUi.Parent = parent
    runtimeState.scriptGui = dungeonAutofarmUi
    uiKit.ensureTip(dungeonAutofarmUi)
    local shell = context.buildShell(dungeonAutofarmUi)
    context.Shell = shell
    function context.menuPage(e)
        return shell.menuPage(e)
    end
    local camera = contextWorkspace.CurrentCamera
    local e = camera and camera.ViewportSize.X or 1600
    local N = camera and camera.ViewportSize.Y or 900
    parent = math.clamp(N - 140, 320, 640)
    local function F(C, g, i, i, i, i, b, B)
        i = shell.page(C, g, b)
        J[C] = i
        return i
    end
    local dim = Instance.new("Frame")
    dim.Name, dim.BackgroundColor3, dim.BackgroundTransparency, dim.BorderSizePixel, dim.Size =
        "Dim", Color3.new(0, 0, 0), 0.5, 0, UDim2.fromScale(1, 1)
    dim.Visible = false
    dim.ZIndex = 1
    dim.Parent = dungeonAutofarmUi
            local function y(q, Z, n, f, o, A)
                return Y(uiKit.toggle(q, Z, function()
                    return config[n]
                end, function(q)
                    config[n] = q
                    if A then
                        A(q)
                    end
                    contextSaveConfig()
                end, f, o))
            end
            local q = false
            local function Z()
                local n = q
                if n then
                    return
                end
                q = true
                task.delay(0.5, function()
                    q = false
                    pcall(contextSaveConfig)
                end)
            end
            local function q(n, f, o, A, k, x, a, e, N, I)
                return Y(uiKit.slider(n, f, o, A, k, x, function()
                    return config[a]
                end, function(n)
                    config[a] = n
                    Z()
                end, e, N, I))
            end
                function context.confirmPop(b)
                    if context.confirmOpen then
                        pcall(function()
                            context.confirmOpen:Destroy()
                        end)
                        context.confirmOpen = nil
                    end
                    local B = uiKit.window(dungeonAutofarmUi, {
                        name = "HLConfirm",
                        title = b.title,
                        icon = b.icon or "info",
                        width = 380,
                        height = 190,
                        visible = true,
                        autoHeight = true,
                        maxHeight = 460,
                        position = UDim2.fromOffset(math.max(8, (e - 380) / 2), math.max(8, N / 2 - 120)),
                    })
                    B.frame.ZIndex = 61
                    context.confirmOpen = B.frame
                    uiKit.caption(B.body, b.text, 1)
                    local G = uiKit.buttonRow(B.body, 2)
                    local function z()
                        if context.confirmOpen == B.frame then
                            context.confirmOpen = nil
                        end
                        pcall(function()
                            B.frame:Destroy()
                        end)
                    end
                    G.add(b.yes, "danger", function()
                        z()
                        pcall(b.onYes)
                    end, b.yesTip or "")
                    G.add(b.no or "Cancel", "accent", function()
                        z()
                        if b.onNo then
                            pcall(b.onNo)
                        end
                    end, b.noTip or "")
                end
                do
                    local inventoryAutomation = context.AS
                    local body, b, B =
                        F("AutoSell", "Auto Sell", 716, 24, 330, parent, "Sell what drops, keep what matters.").body
                    local G = {
                        {
                            cfg = "sellCommon",
                            label = "Common",
                            hint = "The gray drops.",
                        },
                        {
                            cfg = "sellUncommon",
                            label = "Uncommon",
                            hint = "The green drops.",
                        },
                        {
                            cfg = "sellRare",
                            label = "Rare",
                            hint = "The blue drops.",
                        },
                        {
                            cfg = "sellEpic",
                            label = "Epic",
                            hint = "The purple drops.",
                        },
                        {
                            cfg = "sellLegendary",
                            label = "Legendary",
                            hint = "The orange drops. Off to begin with.",
                        },
                        {
                            cfg = "sellUltimate",
                            label = "Ultimate",
                            hint = "The red drops - the very best. Off to begin with.",
                        },
                    }
                    local function z()
                        local s = {}
                        for index, entry in ipairs(G) do
                            if config[entry.cfg] == true then
                                s[#s + 1] = string.lower(entry.label)
                            end
                        end
                        return s
                    end
                    local function s()
                        local T = z()
                        if config.autoSell ~= true then
                            if #T == 0 then
                                return "Switched off. No rarities are ticked either, so it would sell nothing."
                            end
                            local W, K, t, H =
                                table.concat(T, ", "),
                                tonumber(config.sellKeepLevel) or 0,
                                inventoryAutomation.keptCount(),
                                inventoryAutomation.keptCount() == 1 and "" or "s"
                            return ("Switched off. It would sell %s, keeping level %d and up and %d protected item%s."):format(
                                W,
                                K,
                                t,
                                H
                            )
                        end
                        local W, K, t, totalSold, note =
                            inventoryAutomation.sellAfter(),
                            inventoryAutomation.games(),
                            #T == 0 and "No rarities ticked" or "Selling " .. table.concat(T, ", "),
                            inventoryAutomation.totalSold,
                            inventoryAutomation.note
                        return ("On: sells every %d games right in the dungeon, and on every arrival in the lobby (%d played since the last sale). %s. Sold %d so far. Last: %s."):format(
                            W,
                            K,
                            t,
                            totalSold,
                            note
                        )
                    end
                    statusChip = uiKit.section(
                        body,
                        "Auto sell",
                        0.5,
                        "Sells unequipped items out of your bag every few games right in the dungeon - no trip to the lobby - and whenever it arrives in the lobby."
                    )
                    B = uiKit.caption(statusChip.content, s(), 2)
                    local textControl8 = uiKit.caption(statusChip.content, "", 3)
                    textControl8.Visible = false
                    local W = uiKit.buttonRow(statusChip.content, 4)
                    W.frame.Visible = false
                    local function K()
                        W.frame.Visible = false
                        textControl8.Visible = false
                    end
                    Y(uiKit.toggle(statusChip.content, "Enabled", function()
                        return config.autoSell == true
                    end, function(t)
                        if t ~= true then
                            config.autoSell = false
                            K()
                            contextSaveConfig()
                            B.Text = s()
                            contextRefreshAll()
                            return
                        end
                        t = z()
                        textControl8.Visible = true
                        textControl8.Text = #t == 0
                                and "No rarities are ticked, so this would sell nothing. Tick the ones you want sold first."
                            or ("THIS SELLS ITEMS AND CANNOT BE UNDONE.\10Every unequipped %s item in your bag will be sold, every %d games and on every arrival in the lobby, except items at level %d or above and the %d you have protected. Are you sure?"):format(
                                table.concat(t, ", "),
                                inventoryAutomation.sellAfter(),
                                tonumber(config.sellKeepLevel) or 0,
                                inventoryAutomation.keptCount()
                            )
                        W.frame.Visible = #t > 0
                        contextRefreshAll()
                    end, 1, "Nothing is sold until you confirm it."))
                    q(
                        statusChip.content,
                        "Sell after",
                        " games",
                        1,
                        50,
                        false,
                        "sellAfterGames",
                        1,
                        "How many games between sales. The sale happens in the dungeon as that game starts, one item a second. It also sells on every arrival in the lobby.",
                        1
                    )
                    W.add("Yes, sell them", "danger", function()
                        config.autoSell = true
                        K()
                        contextSaveConfig()
                        B.Text = s()
                        contextRefreshAll()
                    end, "Start selling: every few games in the dungeon, and on arrival in the lobby.")
                    W.add("Cancel", "accent", function()
                        K()
                        contextRefreshAll()
                    end, "Leave it switched off.")
                    uiKit.buttonRow(statusChip.content, 5).add("Sell once now", "accent", function()
                        if inventoryAutomation.busy then
                            return
                        end
                        inventoryAutomation.busy = true
                        pcall(inventoryAutomation.sellNow)
                        inventoryAutomation.busy = false
                        B.Text = s()
                    end, "Sell now - in a dungeon or in the lobby.")
                    statusChip.setOpen(true)
                    g = uiKit.section(
                        body,
                        "Rarities to sell",
                        1,
                        "Rarity belongs to the drop, so this is read off each item as it is found."
                    )
                    for index16, entry20 in ipairs(G) do
                        if entry20.cfg == "sellLegendary" or entry20.cfg == "sellUltimate" then
                            Y(uiKit.toggle(g.content, entry20.label, function()
                                return config[entry20.cfg]
                            end, function(G)
                                local function W(t)
                                    config[entry20.cfg] = t
                                    contextSaveConfig()
                                    if config.autoSell == true then
                                        K()
                                    end
                                    B.Text = s()
                                    contextRefreshAll()
                                end
                                if G ~= true then
                                    W(false)
                                    return
                                end
                                local confirmPop, t, label, X, dF, QF =
                                    context.confirmPop, {
                                        title = "Sell " .. entry20.label .. " items?",
                                        icon = "coins",
                                    }, entry20.label, entry20.label:lower(), config.autoSell == true and ", starting with the next check" or " once auto sell is switched on", tonumber(config.sellKeepLevel)
                                t.text = ("Ticking %s makes auto sell SELL every unequipped %s item in your bag%s (only items at level %d or above and the ones you protected are kept). A sold item cannot be brought back. Are you sure?"):format(
                                    label,
                                    X,
                                    dF,
                                    QF or 0
                                )
                                t.yes = "Yes, sell " .. entry20.label
                                t.no = "Cancel"
                                t.onYes = function()
                                    W(true)
                                end
                                confirmPop(t)
                            end, index16, entry20.hint))
                        else
                            y(g.content, entry20.label, entry20.cfg, index16, entry20.hint, function()
                                if config.autoSell == true then
                                    K()
                                end
                                B.Text = s()
                            end)
                        end
                    end
                    g.setOpen(true)
                    q(
                        uiKit.section(body, "Limits", 2, "The guards that apply on top of the rarities.").content,
                        "Keep level and above",
                        "",
                        0,
                        200,
                        false,
                        "sellKeepLevel",
                        1,
                        "Anything needing this level or higher is never sold. 0 turns the guard off.",
                        1
                    )
                    local q, G, z, T =
                        uiKit.section(
                            body,
                            "Protected items",
                            3,
                            "Switch an item on to keep it in every rarity, or light only the rarities to keep under it - it is never sold as a lit one. 898 items, straight off the wiki."
                        ),
                        {
                            text = "",
                            kind = "any",
                            dung = "any",
                            tier = "any",
                        },
                        {
                            {
                                value = "any",
                                label = "Every dungeon",
                            },
                        },
                        {}
                    for index17, dungeon in ipairs(inventoryAutomation.dungeons) do
                        T[dungeon] = true
                    end
                    for index18, entry21 in ipairs(context.QUEUE_MAPS or inventoryAutomation.dungeons) do
                        if T[entry21] then
                            z[#z + 1] = {
                                value = entry21,
                                label = entry21,
                            }
                        end
                    end
                    Y(uiKit.textInput(q.content, "Search", function()
                        return G.text
                    end, function(N)
                        G.text = tostring(N or "")
                        b()
                    end, 1, "Part of an item name.", "mjolnir"))
                    Y(uiKit.dropdown(q.content, "Type", {
                        {
                            value = "any",
                            label = "Everything",
                        },
                        {
                            value = "weapon",
                            label = "Weapons",
                        },
                        {
                            value = "ability",
                            label = "Spells",
                        },
                        {
                            value = "helmet",
                            label = "Helmets",
                        },
                        {
                            value = "chest",
                            label = "Armor",
                        },
                    }, function()
                        return G.kind
                    end, function(kind)
                        G.kind = kind
                        b()
                    end, 2, "Weapons, spells, helmets or armor."))
                    Y(uiKit.dropdown(q.content, "Dungeon", z, function()
                        return G.dung
                    end, function(dung)
                        G.dung = dung
                        b()
                    end, 3, "Where the item comes from."))
                    Y(
                        uiKit.dropdown(
                            q.content,
                            "Rarity",
                            {
                                {
                                    value = "any",
                                    label = "Any rarity",
                                },
                                {
                                    value = "legendary",
                                    label = "Legendary",
                                },
                                {
                                    value = "ultimate",
                                    label = "Ultimate",
                                },
                                {
                                    value = "epic",
                                    label = "Epic",
                                },
                                {
                                    value = "rare",
                                    label = "Rare",
                                },
                                {
                                    value = "uncommon",
                                    label = "Uncommon",
                                },
                                {
                                    value = "common",
                                    label = "Common",
                                },
                                {
                                    value = "",
                                    label = "Untagged",
                                },
                            },
                            function()
                                return G.tier
                            end,
                            function(tier)
                                G.tier = tier
                                b()
                            end,
                            4,
                            "The wiki's base tier. Most of the game is untagged, which is why the sell rules do not use it."
                        )
                    )
                    local N, z =
                        {
                            common = Color3.fromHex("94a5b8"),
                            uncommon = Color3.fromHex("22c55e"),
                            rare = Color3.fromHex("3b80f6"),
                            epic = Color3.fromHex("a855f6"),
                            legendary = Color3.fromHex("ff9900"),
                            ultimate = Color3.fromHex("ff3b3b"),
                        }, {
                            common = "Com",
                            uncommon = "Unc",
                            rare = "Rare",
                            epic = "Epic",
                            legendary = "Leg",
                            ultimate = "Ult",
                        }
                    local textControl9 = uiKit.caption(q.content, "", 5)
                    local W, items = uiKit.buttonRow(q.content, 6), Instance.new("Frame")
                    items.Name = "Items"
                    items.BackgroundTransparency = 1
                    items.AutomaticSize = Enum.AutomaticSize.Y
                    items.Size = UDim2.new(1, 0, 0, 0)
                    items.LayoutOrder = 7
                    items.Parent = q.content
                    uiKit.vlist(items, 8)
                    local function q(t)
                        if G.kind ~= "any" and t.kind ~= G.kind then
                            return false
                        end
                        if G.dung ~= "any" and t.dung ~= G.dung then
                            return false
                        end
                        if G.tier ~= "any" and t.tier ~= G.tier then
                            return false
                        end
                        if G.text ~= "" and not string.find(t.key, inventoryAutomation.nameKey(G.text), 1, true) then
                            return false
                        end
                        return true
                    end
                    local function G()
                        local t = {}
                        for index = 1, #inventoryAutomation.items, 1 do
                            local X = inventoryAutomation.items[index]
                            if q(X) then
                                t[#t + 1] = X
                            end
                        end
                        return t
                    end
                    b = function()
                        for index, child in ipairs(items:GetChildren()) do
                            if not child:IsA("UIListLayout") then
                                child:Destroy()
                            end
                        end
                        local q, t = G(), math.max(tonumber(config.sellListMax) or 40, 5)
                        local H = math.min(#q, t)
                        for index2 = 1, H, 1 do
                            local X = q[index2]
                            local dF, item = X.tier ~= "" and " - " .. X.tier or "", Instance.new("Frame")
                            item.Name, item.BackgroundTransparency, item.AutomaticSize =
                                "Item", 1, Enum.AutomaticSize.Y
                            item.Size = UDim2.new(1, 0, 0, 0)
                            item.LayoutOrder = index2
                            item.Parent = items
                            uiKit.vlist(item, 3)
                            local K, LF = {}
                            local OF = X.tier ~= ""
                            local SF = uiKit.toggle(
                                item,
                                X.name,
                                function()
                                    return inventoryAutomation.isKept(X.name, OF and X.tier or nil)
                                end,
                                function(DF)
                                    inventoryAutomation.setKept(X.name, DF)
                                    contextSaveConfig()
                                    B.Text = s()
                                    LF()
                                end,
                                1,
                                OF
                                        and ("%s%s%s. Always drops as %s. On: never sold."):format(
                                            X.kind,
                                            dF,
                                            X.dung ~= "" and " - " .. X.dung or "",
                                            X.tier
                                        )
                                    or ("%s%s%s. On: kept in every rarity. Light only some rarities below to keep just those."):format(
                                        X.kind,
                                        dF,
                                        X.dung ~= "" and " - " .. X.dung or ""
                                    )
                            )
                            index2 = Instance.new("Frame")
                            index2.Name, index2.BackgroundTransparency, index2.Size =
                                "Rarities", 1, UDim2.new(1, 0, 0, 22)
                            index2.LayoutOrder = 2
                            index2.Visible = not OF
                            index2.Parent = item
                            uiKit.hlist(index2, 4)
                            LF = function()
                                for index3, entry in ipairs(K) do
                                    local DF, PF = inventoryAutomation.isKept(X.name, entry.t), N[entry.t]
                                    index3 = 0.299 * PF.R + 0.587 * PF.G + 0.114 * PF.B > 0.5
                                    entry.b.BackgroundColor3 = DF and PF or uiKit.Theme.SurfaceField
                                    local textControl7, _F =
                                        entry.b, DF and (index3 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1))
                                    textControl7.TextColor3 = _F or uiKit.Theme.TextMuted
                                    entry.s.Color = DF and PF or uiKit.Theme.Hairline
                                end
                            end
                            for index4, entry2 in ipairs(inventoryAutomation.TIER_ORDER) do
                                item = Instance.new("TextButton")
                                item.Name, item.AutoButtonColor, item.BorderSizePixel, item.Text =
                                    inventoryAutomation.TIER_LONG[entry2], false, 0, z[entry2]
                                item.TextSize = 11
                                item.Size = UDim2.new(0.16666666666666666, -4, 1, 0)
                                item.LayoutOrder = index4
                                uiKit.setFont(item, "sans", Enum.FontWeight.SemiBold)
                                uiKit.corner(item, uiKit.Theme.RadiusSm)
                                K[index4] = {
                                    t = entry2,
                                    b = item,
                                    s = uiKit.stroke(item, uiKit.Theme.Hairline, 1),
                                }
                                item.Parent = index2
                                local function N()
                                    local z, K = inventoryAutomation.keptRule(X.name), {}
                                    for index3, entry in ipairs(inventoryAutomation.TIER_ORDER) do
                                        K[entry] = z == true or type(z) == "table" and z[entry] == true
                                    end
                                    K[entry2] = not K[entry2]
                                    inventoryAutomation.setKept(X.name, K)
                                    contextSaveConfig()
                                    B.Text = s()
                                    LF()
                                    SF.render()
                                end
                                item.MouseButton1Click:Connect(N)
                                uiKit.tip(
                                    item,
                                    ("%s %s: lit = kept, never sold when it drops as %s."):format(
                                        inventoryAutomation.TIER_LONG[entry2],
                                        X.name,
                                        inventoryAutomation.TIER_LONG[entry2]
                                    )
                                )
                            end
                            LF()
                        end
                        textControl9.Text = #q == 0 and "Nothing matches that."
                            or ("Showing %d of %d. %d protected in total."):format(
                                H,
                                #q,
                                inventoryAutomation.keptCount()
                            )
                    end
                    W.add(
                        "Protect these",
                        "accent",
                        function()
                            for index, entry in ipairs(G()) do
                                inventoryAutomation.setKept(entry.name, true)
                            end
                            contextSaveConfig()
                            b()
                            B.Text = s()
                            contextRefreshAll()
                        end,
                        "Protect every item the filters above are showing, not only the ones on screen, in every rarity."
                    )
                    W.add("Unprotect these", "accent", function()
                        for index, entry in ipairs(G()) do
                            inventoryAutomation.setKept(entry.name, false)
                        end
                        contextSaveConfig()
                        b()
                        B.Text = s()
                        contextRefreshAll()
                    end, "Drop the protection from every item the filters are showing.")
                    b()

                do
                    local scriptSection = uiKit.section(body, "Script", 4, "The key that opens this window, and the off switch.")
                    uiSettings.menuKeyButton = uiKit.button(
                        scriptSection.content,
                        "Menu key: " .. tostring(config.menuKey) .. " (click, then press a key)",
                        "accent",
                        function()
                            runtimeState.menuKeyCapture = true
                            if uiSettings.menuKeyButton then
                                uiSettings.menuKeyButton.Text = "Press the new key... (Escape cancels)"
                            end
                        end,
                        1,
                        "Rebind the key that opens and closes this window: click, then press the new key. Escape keeps the old one."
                    )
                    uiKit.button(
                        scriptSection.content,
                        "Close the script",
                        "danger",
                        contextDestructScript,
                        2,
                        "Remove everything this script made and stop."
                    )
                    scriptSection.setOpen(true)
                end
                end

    local I
    I = function()
        shell.setShown(w)
        dim.Visible = false
        local y = w
        if not y then
            uiKit.hideTip()
        end
    end
    shell.onClose = function()
        w = false
        I()
    end
    shell.finish()
    contextSliderConnections[#contextSliderConnections + 1] = userInputService.InputBegan:Connect(
        function(input, q)
            if
                runtimeState.menuKeyCapture
                and not q
                and input.UserInputType == Enum.UserInputType.Keyboard
            then
                runtimeState.menuKeyCapture = false
                local keyCode = input.KeyCode
                if keyCode ~= Enum.KeyCode.Escape and keyCode ~= Enum.KeyCode.Unknown then
                    config.menuKey = keyCode.Name
                    contextSaveConfig()
                end
                if uiSettings.menuKeyButton then
                    uiSettings.menuKeyButton.Text = "Menu key: "
                        .. tostring(config.menuKey)
                        .. " (click, then press a key)"
                end
                return
            end
            local Y = not q
            q = Y and input.KeyCode.Name == config.menuKey
            if q then
                w = not w
                I()
            end
        end
    )
    I()
    statusChip = config.menuButtonAnyTouch ~= false
    local F = userInputService.TouchEnabled and (statusChip or not userInputService.KeyboardEnabled)
    F = if statusChip and context.COMPACT == true then true else F
    local function y()
        if runtimeState.mobileMenuButton and runtimeState.mobileMenuButton.Parent then
            return
        end
        runtimeState.mobileMenuButton = shell.menuButton(function()
            w = not w
            I()
        end)
    end
    F = config.mobileButton ~= false and (config.mobileButtonAlways == true or F)
    if F then
        y()
    else
        local contextRunsThisAccount = config.mobileButton ~= false and statusChip
        if contextRunsThisAccount then
            local connection3
            connection3 = userInputService.InputBegan:Connect(function(connection2)
                if connection2.UserInputType ~= Enum.UserInputType.Touch then
                    return
                end
                connection2 = connection3
                if connection2 then
                    connection3:Disconnect()
                    connection3 = nil
                end
                if not runtimeState.destroyed then
                    pcall(y)
                end
            end)
            contextSliderConnections[#contextSliderConnections + 1] = connection3
        end
    end
end
