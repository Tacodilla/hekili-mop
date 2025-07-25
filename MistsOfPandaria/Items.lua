-- MistsOfPandaria/Items.lua
-- Items and trinkets specific to Mists of Pandaria expansion

local addon, ns = ...
local Hekili = _G[ addon ]

if not Hekili.IsMoP() then return end

-- Safety check: ensure Hekili.Class is a table, not a string
if type(Hekili.Class) ~= "table" then
    return -- Exit if Class isn't properly initialized yet
end

local class = Hekili.Class
local state = Hekili.State

-- Ensure class is properly initialized
if not class then return end

-- MoP Trinkets and Items
local items = {
    -- Legendary Items
    rune_of_reorigination = 94535,
    wrists_of_the_gods = 95992,
    cloak_of_the_celestials = 95993,
    
    -- Raid Trinkets from Siege of Orgrimmar
    purified_bindings_of_immerseus = 104426,
    thoks_tail_tip = 104427,
    sigil_of_rampage = 104428,
    ticking_ebon_detonator = 104429,
    black_blood_of_gorrosh = 104430,
    
    -- Raid Trinkets from Throne of Thunder
    renatakis_soul_charm = 94508,
    bad_juju = 94511,
    unerring_vision_of_leishen = 94512,
    spark_of_zandalar = 94513,
    
    -- Heroic Dungeon Trinkets
    flashing_steel_talisman = 81265,
    bottle_of_infinite_stars = 81267,
    terror_in_the_mists = 81268,
    
    -- PvP Trinkets
    malevolent_gladiators_medallion_of_tenacity = 91370,
    tyrannical_gladiators_medallion_of_tenacity = 94227,
    grievous_gladiators_medallion_of_tenacity = 103686,
    
    -- Engineering Items
    ghost_iron_dragonling = 82200,
    mechanical_pandaren_dragonling = 82201,
    pierre = 87213,
    
    -- Potions
    potion_of_the_jade_serpent = 76085,
    potion_of_mogu_power = 76086,
    virmen_nut = 76097,
    master_mana_potion = 76098,
    
    -- Flasks
    flask_of_winter_bite = 76374,
    flask_of_the_earth = 76375,
    flask_of_flowing_water = 76376,
    flask_of_spring_blossoms = 76377,
    flask_of_warm_sun = 76378,
    
    -- Food
    mogu_fish_stew = 74919,
    shrimp_dumplings = 74636,
    fish_cake = 74641,
    rice_pudding = 74919,
}

-- Register all items
if class and type(class) == "table" then
    -- Ensure itemList and itemMap are initialized
    class.itemList = class.itemList or {}
    class.itemMap = class.itemMap or {}
    
    for name, id in pairs( items ) do
        class.itemList[ name ] = id
        class.itemMap[ id ] = name
    end
end

-- Item Effects and Handlers
class.items = class.items or {}

-- Example trinket handler - Purified Bindings of Immerseus
class.items.purified_bindings_of_immerseus = {
    id = 104426,
    cast = 0,
    cooldown = 120,
    gcd = "off",
    
    item = 104426,
    toggle = "cooldowns",
    
    handler = function()
        -- Grants Purified Resolve, increasing stats
        applyBuff( "purified_resolve" )
    end,
}

-- Flask effects
class.items.flask_of_winter_bite = {
    id = 76374,
    cast = 3,
    cooldown = 0,
    gcd = "spell",
    
    item = 76374,
    
    handler = function()
        applyBuff( "flask_of_winter_bite" )
    end,
}

-- Add more item handlers as needed for specific trinkets and consumables

Hekili:Debug( "MoP Items module loaded." )
