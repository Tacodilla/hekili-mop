-- RogueAssassination.lua July 2025
-- by Smufrik

-- MoP: Use UnitClass instead of UnitClassBase
local addon, ns = ...
local _, playerClass = UnitClass('player')
if playerClass ~= 'ROGUE' then return end

local Hekili = _G[ "Hekili" ]
local class, state = Hekili.Class, Hekili.State

local floor = math.floor
local strformat = string.format

-- Create the Assassination spec (259 is Assassination in retail, using appropriate ID)
local spec = Hekili:NewSpecialization(259, true)

spec.name = "Assassination"
spec.role = "DAMAGER"
spec.primaryStat = 2 -- Agility

-- Ensure state is properly initialized
if not state then 
    state = Hekili.State 
end

-- MoP-compatible power type registration with enhanced energy mechanics
-- Use MoP power type numbers instead of Enum
-- Energy = 3, ComboPoints = 4 in MoP Classic
spec:RegisterResource( 3, { -- Energy with enhanced regeneration mechanics
    -- Adrenaline Rush energy bonus (if talented from Combat spec via Preparation)
    adrenaline_rush = {
        aura = "adrenaline_rush",
        last = function ()
            local app = state.buff.adrenaline_rush.applied
            local t = state.query_time
            return app + floor( ( t - app ) / 1 ) * 1
        end,
        interval = 1,
        value = function()
            -- Adrenaline Rush doubles energy regeneration
            return state.buff.adrenaline_rush.up and 10 or 0 -- Additional 10 energy per second
        end,
    },
    
    -- Shadow Focus talent energy reduction mechanics
    shadow_focus = {
        aura = "stealth",
        last = function ()
            return state.buff.stealth.applied or state.buff.vanish.applied or 0
        end,
        interval = 1,
        value = function()
            -- Shadow Focus reduces energy costs while stealthed
            return (state.buff.stealth.up or state.buff.vanish.up) and 3 or 0 -- +3 energy per second while stealthed
        end,
    },
    
    -- Vendetta energy efficiency (Assassination signature)
    vendetta = {
        aura = "vendetta",
        last = function ()
            local app = state.buff.vendetta.applied
            local t = state.query_time
            return app + floor( ( t - app ) / 1 ) * 1
        end,
        interval = 1,
        value = function()
            -- Enhanced energy efficiency during Vendetta
            return state.buff.vendetta.up and 2 or 0 -- +2 energy per second during Vendetta
        end,
    },
    
    -- Relentless Strikes energy return (Assassination signature talent)
    relentless_strikes_energy = {
        last = function ()
            return state.query_time
        end,
        interval = 1,
        value = function()
            -- Relentless Strikes: 20% chance per combo point spent to generate 25 energy
            if state.talent.relentless_strikes.enabled and state.last_finisher_cp then
                local energy_chance = state.last_finisher_cp * 0.04 -- 4% chance per combo point for energy return
                return math.random() < energy_chance and 25 or 0
            end
            return 0
        end,
    },
    
    -- Overkill energy bonus (from stealth/vanish)
    overkill_energy = {
        aura = "overkill",
        last = function ()
            return state.buff.overkill.applied or 0
        end,
        interval = 1,
        value = function()
            -- Overkill: Stealth abilities grant enhanced energy regeneration
            return state.buff.overkill.up and 5 or 0 -- +5 energy per second for 20 seconds
        end,
    },
}, {
    -- Enhanced base energy regeneration for Assassination with MoP mechanics
    base_regen = function ()
        local base = 10 -- Base energy regeneration in MoP (10 energy per second)
        
        -- Haste scaling for energy regeneration (minor in MoP)
        local haste_bonus = 1.0 + ((state.stat.haste_rating or 0) / 42500) -- Approximate haste scaling
        
        -- Assassination gets enhanced energy efficiency from poisons
        local poison_bonus = 1.0
        if state.buff.deadly_poison.up then poison_bonus = poison_bonus + 0.02 end -- 2% bonus
        if state.buff.instant_poison.up then poison_bonus = poison_bonus + 0.02 end -- 2% bonus
        
        return base * haste_bonus * poison_bonus
    end,
    
    -- Improved energy regeneration during Vendetta
    vendetta_energy_efficiency = function ()
        return state.debuff.vendetta.up and 1.15 or 1.0 -- 15% energy efficiency during Vendetta
    end,
    
    -- Lethality talent affects energy efficiency
    lethality_efficiency = function ()
        return state.talent.lethality.enabled and 1.03 or 1.0 -- 3% energy efficiency from Lethality
    end,
} )

-- Enhanced combo point mechanics for Assassination
spec:RegisterResource( 4, { -- Combo Points = 4 in MoP
    -- Seal Fate combo point generation (Assassination mastery)
    seal_fate = {
        last = function ()
            return state.query_time -- Continuous tracking
        end,
        interval = 1,
        value = function()
            -- Seal Fate: Critical strikes with abilities that generate combo points have a 50% chance to generate an extra combo point
            -- Completely rewritten to avoid state variable issues - use a simple random proc system
            -- This simulates the Seal Fate proc without relying on problematic state variables
            return math.random() <= 0.05 and 1 or 0 -- 5% chance per second (simplified proc system)
        end,
    },
    
    -- Anticipation combo point storage (Level 90 talent)
    anticipation_storage = {
        aura = "anticipation",
        last = function ()
            return state.query_time
        end,
        interval = 1,
        value = function()
            -- Anticipation allows storing combo points beyond the 5-point limit
            if state.talent.anticipation.enabled and (state.combo_points.current or 0) >= 5 then
                return 1 -- Store excess combo points as Anticipation stacks
            end
            return 0
        end,
    },
    
    -- Honor Among Thieves combo point generation (raid setting)
    honor_among_thieves = {
        last = function ()
            return state.query_time
        end,
        interval = 1, -- HAT proc chance roughly every second in raid with many crits
        value = function()
            if state.talent.honor_among_thieves.enabled and state.group_members > 1 then
                -- HAT generates 1 combo point when party/raid members crit (1% chance per member's crit)
                local proc_chance = state.group_members >= 5 and 0.15 or 0.05 -- Higher chance in full groups
                return math.random() <= proc_chance and 1 or 0
            end
            return 0
        end,
    },
    
    -- Relentless Strikes combo point efficiency 
    relentless_strikes_retention = {
        last = function ()
            return state.query_time
        end,
        interval = 1,
        value = function()
            -- Relentless Strikes: 20% chance per combo point to generate 25 energy and not consume the combo point
            if state.talent.relentless_strikes.enabled and state.last_finisher_cp then
                local retention_chance = state.last_finisher_cp * 0.04 -- 4% chance per combo point to retain 1 CP
                return math.random() < retention_chance and 1 or 0
            end
            return 0
        end,
    },
}, {
    -- Base combo point mechanics for Assassination
    max_combo_points = function ()
        return 5 -- Maximum 5 combo points in MoP
    end,
    
    -- Enhanced combo point generation for Assassination
    assassination_efficiency = function ()
        -- Assassination gets enhanced combo point generation from poisons and crits
        local efficiency = 1.0
        
        -- Seal Fate mastery increases crit-based combo point generation
        if state.mastery_rating > 0 then
            efficiency = efficiency + (state.mastery_rating * 0.01) -- Roughly 1% per mastery rating
        end
        
        return efficiency
    end,
    
    -- Vendetta damage bonus affects effective combo point value
    vendetta_bonus = function ()
        return state.debuff.vendetta.up and 1.3 or 1.0 -- 30% damage bonus affects CP efficiency
    end,
} )

-- Talents for MoP Assassination Rogue
spec:RegisterTalents({
    -- Tier 1 (Level 15)
    shadow_focus =        { 1, 1, 108209 }, -- Abilities cost 30% less Energy while Stealth or Shadow Clone is active
    improved_recuperate = { 1, 2, 108210 }, -- Recuperate restores 5% additional health and 30% more healing per stack of Recuperate
    lethality =           { 1, 3, 108211 }, -- Critical strike damage bonus increased by 10%
    
    -- Tier 2 (Level 30)
    deadly_throw =       { 2, 1, 26679 }, -- Throw a dagger that slows the target
    nerve_strike =       { 2, 2, 108215 }, -- Your successful melee attacks reduce the target's damage by 50% for 6 sec
    combat_readiness =   { 2, 3, 74001 }, -- Each melee or ranged attack against you increases your dodge by 2%
    
    -- Tier 3 (Level 45)
    cheat_death = { 3, 1, 31230 }, -- Fatal damage instead reduces you to 7% of maximum health
    leeching_poison = { 3, 2, 108211 }, -- Your poisons also heal you for 10% of damage dealt
    elusiveness = { 3, 3, 79008 }, -- Reduces cooldown of Cloak of Shadows, Combat Readiness, and Dismantle
    
    -- Tier 4 (Level 60) 
    cloak_and_dagger = { 4, 1, 138106 }, -- Ambush, Garrote, and Cheap Shot have 40 yard range and will cause you to teleport behind your target
    shadowstep = { 4, 2, 36554 }, -- Step through shadows to appear behind your target and increase movement speed
    burst_of_speed = { 4, 3, 108212 }, -- Increases movement speed by 70% for 4 sec. Each enemy strike removes 1 sec
    
    -- Tier 5 (Level 75)
    internal_bleeding = { 5, 1, 154953 }, -- Kidney Shot also causes the target to bleed
    dirty_deeds = { 5, 2, 108216 }, -- Cheap Shot and Kidney Shot have 20% increased critical strike chance
    paralytic_poison = { 5, 3, 108215 }, -- Coats weapons with poison that reduces target's movement speed
    
    -- Tier 6 (Level 90)
    vendetta = { 6, 1, 79140 }, -- Marks an enemy for death, increasing all damage you deal to the target
    -- shadow_clone = { 6, 2, 159621 }, -- Not available in MoP Classic
    venom_rush = { 6, 3, 152152 }, -- Vendetta also increases your Energy regeneration
})

-- Auras for Assassination Rogue
spec:RegisterAuras({
    -- Weapon Poison Buffs (applied to weapons)
    deadly_poison = {
        id = 2823,
        duration = 3600, -- 1 hour duration
        max_stack = 1
    },
    instant_poison = {
        id = 8680,
        duration = 3600, -- 1 hour duration
        max_stack = 1
    },
    wound_poison = {
        id = 8679,
        duration = 3600, -- 1 hour duration  
        max_stack = 1
    },
    leeching_poison = {
        id = 108211,
        duration = 3600, -- 1 hour duration
        max_stack = 1
    },
    paralytic_poison = {
        id = 108215,
        duration = 3600, -- 1 hour duration
        max_stack = 1
    },
    crippling_poison = {
        id = 3408,
        duration = 3600, -- 1 hour duration
        max_stack = 1
    },
    mind_numbing_poison = {
        id = 5761,
        duration = 3600, -- 1 hour duration
        max_stack = 1
    },
    
    -- Poison Debuffs on targets (MoP mechanics)
    deadly_poison_dot = {
        id = 2818,
        duration = 12, -- MoP: 12 second duration
        tick_time = 3, -- Ticks every 3 seconds
        max_stack = 5, -- Can stack up to 5 times
        copy = "deadly_poison_debuff"
    },
    instant_poison_debuff = {
        id = 8681, -- Instant poison application effect
        duration = 8, -- Brief duration for tracking
        max_stack = 1
    },
    wound_poison_debuff = {
        id = 13218,
        duration = 15, -- 15 second duration
        max_stack = 5, -- Stacks up to 5 times, reduces healing by 10% per stack
        copy = "mortal_wounds"
    },
    crippling_poison_debuff = {
        id = 3409,
        duration = 12, -- 12 second duration
        max_stack = 1, -- Reduces movement speed by 70%
        copy = "crippling_poison_slow"
    },
    mind_numbing_poison_debuff = {
        id = 5760,
        duration = 16, -- 16 second duration
        max_stack = 5, -- Stacks up to 5 times, increases casting time
        copy = "mind_numbing_poison_slow"
    },
    paralytic_poison_debuff = {
        id = 113952, -- MoP paralytic poison debuff
        duration = 4, -- 4 second stun duration
        max_stack = 1
    },
    leeching_poison_debuff = {
        id = 112961, -- MoP leeching poison effect
        duration = 8, -- Duration for tracking
        max_stack = 1
    },
    
    -- Bleed effects
    rupture = {
        id = 1943,
        duration = function() return 8 + (4 * (combo_points.current or 0)) end, -- MoP Classic: 8s base + 4s per combo point
        tick_time = 2, -- Ticks every 2 seconds
        max_stack = 1
    },
    garrote = {
        id = 703,
        duration = 18, -- 18 second duration
        tick_time = 3, -- Ticks every 3 seconds
        max_stack = 1
    },
    
    -- Buffs
    slice_and_dice = {
        id = 5171,
        duration = function() return 6 + (6 * (combo_points.current or 0)) end, -- MoP Classic: 6s base + 6s per combo point
        max_stack = 1
    },
    stealth = {
        id = 1784,
        duration = 10,
        max_stack = 1
    },
    vanish = {
        id = 1856,
        duration = 3,
        max_stack = 1
    },
    cold_blood = {
        id = 14177,
        duration = 60,
        max_stack = 1
    },
    vendetta = {
        id = 79140,
        duration = 30,
        max_stack = 1
    },
    
    -- Missing debuff tracking for Vendetta on target
    vendetta_debuff = {
        id = 79140,
        duration = 30,
        max_stack = 1,
        copy = "vendetta" -- Allows both buff and debuff tracking
    },
    
    -- Revealing Strike (Combat spec ability, but referenced in imported rotations)
    revealing_strike = {
        id = 84617,
        duration = 15,
        max_stack = 1
    },
    
    -- Deep Insight (Combat spec buff, but referenced in imported rotations)
    deep_insight = {
        id = 84747,
        duration = 15,
        max_stack = 1
    },
    
    -- Venom Rush talent buff
    venom_rush = {
        id = 152152,
        duration = 30,
        max_stack = 1
    },
    -- shadow_clone removed - not available in MoP Classic
    envenom = {
        id = 32645,
        duration = function() return combo_points.current or 0 end,
        max_stack = 1
    },
    
    -- Stun effects
    kidney_shot = {
        id = 408,
        duration = function() return 1 + (combo_points.current or 0) end, -- MoP Classic: 1s base + 1s per combo point
        max_stack = 1
    },
    cheap_shot = {
        id = 1833,
        duration = 4,
        max_stack = 1
    },
    
    -- Talent effects
    nerve_strike = {
        id = 108210,
        duration = 6,
        max_stack = 1
    },
    internal_bleeding = {
        id = 154953,
        duration = 6,
        tick_time = 2,
        max_stack = 1
    },
    
    -- Utility
    evasion = {
        id = 5277,
        duration = 15,
        max_stack = 1
    },
    feint = {
        id = 1966,
        duration = 10,
        max_stack = 1
    },
    sprint = {
        id = 2983,
        duration = 15,
        max_stack = 1
    },
    shadowstep = {
        id = 36554,
        duration = 0,
        max_stack = 1
    },
    burst_of_speed = {
        id = 108212,
        duration = 4,
        max_stack = 1
    },
    
    -- Stealth and related buffs
    subterfuge = {
        id = 115192,
        duration = 3,
        max_stack = 1
    },
    master_of_subtlety = {
        id = 31665,
        duration = 6,
        max_stack = 1
    },
    overkill = {
        id = 58426,
        duration = 20,
        max_stack = 1
    },
    nightstalker = {
        id = 14062,
        duration = 3,
        max_stack = 1
    },
    dirty_deeds = {
        id = 108216,
        duration = 6,
        max_stack = 1
    },
    
    -- MoP Trinket auras
    vial_of_shadows = {
        id = 79734, -- Vial of Shadows proc aura
        duration = 15,
        max_stack = 1
    },
    
    -- Shadow Dance (for compatibility with imported rotations)
    shadow_dance = {
        id = 185313, -- Shadow Dance spell ID
        duration = 8,
        max_stack = 1
    },
    
    -- Anticipation (Level 90 talent)
    anticipation = {
        id = 114015,
        duration = 3600,
        max_stack = 5
    },
    
    -- Jade Serpent Potion
    jade_serpent_potion = {
        id = 76089,
        duration = 25,
        max_stack = 1
    },
    
    -- Tricks of the Trade
    tricks_of_the_trade = {
        id = 57934,
        duration = 6,
        max_stack = 1
    },
    
    -- Blindside - Proc buff that allows Dispatch usage
    blindside = {
        id = 121153, -- MoP Blindside proc ID
        duration = 10,
        max_stack = 1
    },
    
    -- Shadow Blades - Major DPS cooldown buff
    shadow_blades = {
        id = 121471,
        duration = 12,
        max_stack = 1
    },
    
    -- Cloak of Shadows - Defensive buff
    cloak_of_shadows = {
        id = 31224,
        duration = 5,
        max_stack = 1
    },
    
    -- Crimson Tempest debuff
    crimson_tempest = {
        id = 121411,
        duration = function() return 2 + (2 * (combo_points.current or 0)) end, -- 2s base + 2s per combo point
        max_stack = 1,
        tick_time = 2 -- Ticks every 2 seconds
    },
})

-- State Expressions for MoP Assassination Rogue
spec:RegisterStateExpr("stealthed", function()
    return {
        all = buff.stealth.up or buff.vanish.up or buff.subterfuge.up,
        normal = buff.stealth.up,
        vanish = buff.vanish.up,
        subterfuge = buff.subterfuge.up
    }
end)

spec:RegisterStateExpr("effective_combo_points", function()
    local cp = combo_points.current or 0
    -- Account for Anticipation talent
    if talent.anticipation.enabled and buff.anticipation.up then
        return cp + buff.anticipation.stack
    end
    return cp
end)

spec:RegisterStateExpr("behind_target", function()
    -- Simplified positional check - in real game this would check actual positioning
    return true -- Assume behind target for simulation purposes
end)

-- Stealth-breaking hook for proper MoP mechanics
spec:RegisterHook("runHandler", function(action, pool)
    -- Handle stealth-breaking for non-stealth abilities
    local stealth_abilities = {
        "stealth", "vanish", "garrote", "ambush", "cheap_shot", "sap", "pick_pocket", "distract"
    }
    
    local breaks_stealth = true
    for _, ability in ipairs(stealth_abilities) do
        if action == ability then
            breaks_stealth = false
            break
        end
    end
    
    if breaks_stealth then
        if buff.stealth.up and not talent.subterfuge.enabled then
            removeBuff("stealth")
        elseif buff.stealth.up and talent.subterfuge.enabled then
            -- Subterfuge extends stealth abilities for 3 seconds
            removeBuff("stealth")
            applyBuff("subterfuge", 3)
        end
        
        if buff.vanish.up and not talent.subterfuge.enabled then
            removeBuff("vanish")
        elseif buff.vanish.up and talent.subterfuge.enabled then
            removeBuff("vanish")
            applyBuff("subterfuge", 3)
        end
    end
    
    -- Handle Overkill buff from stealth abilities
    if action == "ambush" or action == "garrote" or action == "cheap_shot" then
        if stealthed_all then
            applyBuff("overkill", 20) -- 20-second energy regeneration bonus
        end
    end
end)

-- Hook for Master of Subtlety and other stealth-related mechanics
spec:RegisterHook("reset_precast", function()
    -- Ensure proper stealth state tracking
    if buff.stealth.up or buff.vanish.up or buff.subterfuge.up then
        -- Master of Subtlety damage bonus (if it applies to other specs via talent)
        if talent.master_of_subtlety and talent.master_of_subtlety.enabled then
            applyBuff("master_of_subtlety", 6)
        end
    end
end)

-- Abilities for Assassination Rogue
spec:RegisterAbilities({
    -- Basic attacks
    mutilate = {
        id = 1329,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        school = "physical",
        
        spend = function() 
            -- MoP: Mutilate costs 55 energy base
            local cost = 55
            
            -- Shadow Focus reduces cost while stealthed
            if talent.shadow_focus.enabled and (buff.stealth.up or buff.vanish.up) then
                cost = cost * 0.25 -- 75% cost reduction in stealth
            end
            
            return cost
        end,
        spendType = "energy",
        
        startsCombat = true,
        
        usable = function() return target.distance <= 5, "target too far away" end,
        
        handler = function()
            -- Mutilate always generates 2 combo points
            gain(2, "combo_points")
            
            -- Seal Fate proc chance on crit (50% chance for extra combo point)
            if (state.crit_chance or 0) > math.random() then
                state.last_ability_crit = true
                if math.random() <= 0.5 then
                    gain(1, "combo_points")
                end
            else
                state.last_ability_crit = false
            end
            
            -- Apply/refresh poisons
            if buff.deadly_poison.up then
                applyDebuff("target", "deadly_poison_dot", 12, min(5, debuff.deadly_poison_dot.stack + 1))
            end
            if buff.instant_poison.up then
                -- Instant poison does immediate damage
                applyDebuff("target", "instant_poison_dot", 8)
            end
            
            -- Blindside proc chance (MoP: 30% chance on poison application)
            if (buff.deadly_poison.up or buff.instant_poison.up) and math.random() <= 0.30 then
                applyBuff("blindside", 10) -- 10 second duration
            end
            
            -- Track last ability for Seal Fate
            state.last_ability = "mutilate"
        end,
    },
    
    sinister_strike = {
        id = 1752,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 45,
        spendType = "energy",
        
        startsCombat = true,
        
        handler = function()
            gain(1, "combo_points")
        end,
    },
    
    backstab = {
        id = 53,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        school = "physical",
        
        spend = function() 
            local cost = 60 -- MoP: Backstab costs 60 energy
            
            -- Shadow Focus reduces cost while stealthed
            if talent.shadow_focus.enabled and (buff.stealth.up or buff.vanish.up) then
                cost = cost * 0.25 -- 75% cost reduction in stealth
            end
            
            return cost
        end,
        spendType = "energy",
        
        startsCombat = true,
        
        usable = function() return behind_target, "must be behind target" end,
        
        handler = function()
            -- Backstab generates 1 combo point
            gain(1, "combo_points")
            
            -- Seal Fate proc chance on crit (50% chance for extra combo point)
            if (state.crit_chance or 0) > math.random() then
                state.last_ability_crit = true
                if math.random() <= 0.5 then
                    gain(1, "combo_points")
                end
            else
                state.last_ability_crit = false
            end
            
            -- Apply poisons
            if buff.deadly_poison.up then
                applyDebuff("target", "deadly_poison_dot", 12, min(5, debuff.deadly_poison_dot.stack + 1))
            end
            
            -- Track last ability for Seal Fate
            state.last_ability = "backstab"
        end,
    },
    
    -- Dispatch - Assassination finisher that can be used with 1+ combo points or on low health targets
    dispatch = {
        id = 111240, -- MoP Dispatch spell ID
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        school = "physical",
        
        spend = function() 
            local cost = 30 -- MoP: Dispatch costs 30 energy
            
            -- Shadow Focus reduces cost while stealthed
            if talent.shadow_focus.enabled and (buff.stealth.up or buff.vanish.up) then
                cost = cost * 0.25
            end
            
            return cost
        end,
        spendType = "energy",
        
        startsCombat = true,
        
                usable = function()
            return (combo_points.current or 0) > 0 or target.health.pct < 35, "requires combo points or target below 35% health"
        end,
        
        handler = function()
            local cp = combo_points.current or 0
            
            -- Dispatch can be used as a combo point generator when target is below 35% health
            if target.health.pct < 35 and cp == 0 then
                gain(1, "combo_points")
                
                -- Seal Fate proc chance on crit
                if (state.crit_chance or 0) > math.random() then
                    state.last_ability_crit = true
                    if math.random() <= 0.5 then
                        gain(1, "combo_points")
                    end
                else
                    state.last_ability_crit = false
                end
                
                state.last_ability = "dispatch"
            else
                -- Used as finisher - consume combo points
                spend(cp, "combo_points")
                
                -- Apply poisons on finisher
                if buff.deadly_poison.up then
                    applyDebuff("target", "deadly_poison_dot", 12, min(5, debuff.deadly_poison_dot.stack + 1))
                end
            end
        end,
    },
    
    -- Fan of Knives - AoE combo point generator
    fan_of_knives = {
        id = 51723,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        school = "physical",
        
        spend = function() 
            local cost = 35 -- MoP: Fan of Knives costs 35 energy
            
            -- Shadow Focus reduces cost while stealthed
            if talent.shadow_focus.enabled and (buff.stealth.up or buff.vanish.up) then
                cost = cost * 0.25
            end
            
            return cost
        end,
        spendType = "energy",
        
        startsCombat = true,
        
        handler = function()
            -- Fan of Knives generates 1 combo point per target hit (up to 1 in single target)
            local targets_hit = active_enemies > 0 and math.min(active_enemies, 1) or 1
            gain(targets_hit, "combo_points")
            
            -- Apply poisons to all targets hit
            if buff.deadly_poison.up then
                applyDebuff("target", "deadly_poison_dot", 12, min(5, debuff.deadly_poison_dot.stack + 1))
            end
            
            -- Track for Seal Fate (though FoK doesn't typically crit for extra CPs in MoP)
            state.last_ability = "fan_of_knives"
        end,
    },
    
    -- Finishers
    envenom = {
        id = 32645,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 35,
        spendType = "energy",
        
        startsCombat = true,
        
        usable = function() return (combo_points.current or 0) > 0 end,
        
        handler = function()
            local cp = combo_points.current or 0
            -- Envenom duration = combo points spent
            applyBuff("envenom", cp)
            spend(cp, "combo_points")
            
            -- Track for Relentless Strikes
            state.last_finisher_cp = cp
        end,
    },
    
    rupture = {
        id = 1943,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 25,
        spendType = "energy",
        
        startsCombat = true,
        
        usable = function() return (combo_points.current or 0) > 0 end,
        
        handler = function()
            local cp = combo_points.current or 0
            -- MoP Classic: 8 seconds base + 4 seconds per combo point
            applyDebuff("target", "rupture", 8 + (4 * cp))
            spend(cp, "combo_points")
            
            -- Track for Relentless Strikes
            state.last_finisher_cp = cp
        end,
    },
    
    slice_and_dice = {
        id = 5171,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 25,
        spendType = "energy",
        
        startsCombat = false,
        
        usable = function() return (combo_points.current or 0) > 0 end,
        
        handler = function()
            local cp = combo_points.current or 0
            -- MoP Classic: 6 seconds base + 6 seconds per combo point
            applyBuff("slice_and_dice", 6 + (6 * cp))
            spend(cp, "combo_points")
            
            -- Track for Relentless Strikes
            state.last_finisher_cp = cp
        end,
    },

-- Add missing finishing moves for Assassination
eviscerate = {
    id = 2098,
    cast = 0,
    cooldown = 0,
    gcd = "spell",
    
    spend = 35,
    spendType = "energy",
    
    startsCombat = true,
    
    usable = function() return (combo_points.current or 0) > 0 end,
    
    handler = function()
        local cp = combo_points.current or 0
        -- Eviscerate: Damage scales with combo points
        spend(cp, "combo_points")
        
        -- Track for Relentless Strikes
        state.last_finisher_cp = cp
    end,
},

kidney_shot = {
    id = 408,
    cast = 0,
    cooldown = 20,
    gcd = "spell",
    
    spend = 25,
    spendType = "energy",
    
    startsCombat = true,
    
    usable = function() return (combo_points.current or 0) > 0 end,
    
    handler = function()
        local cp = combo_points.current or 0
        -- MoP Classic: 1 second base + 1 second per combo point (max 6 seconds)
        applyDebuff("target", "kidney_shot", 1 + cp)
        spend(cp, "combo_points")
        
        -- Track for Relentless Strikes
        state.last_finisher_cp = cp
        
        -- Apply talent effects
        if talent.nerve_strike.enabled then
            applyDebuff("target", "nerve_strike", 6)
        end
        if talent.internal_bleeding.enabled then
            applyDebuff("target", "internal_bleeding", 6)
        end
    end,
},

-- Stealth abilities
    stealth = {
        id = 1784,
        cast = 0,
        cooldown = 10,
        gcd = "off",
        school = "physical",
        
        startsCombat = false,
        
        usable = function() return not combat, "cannot stealth in combat" end,
        
        handler = function()
            applyBuff("stealth", 3600) -- Long duration until broken
            
            -- Master of Subtlety (if talented)
            if talent.master_of_subtlety and talent.master_of_subtlety.enabled then
                applyBuff("master_of_subtlety", 6)
            end
        end,
    },
    
    vanish = {
        id = 1856,
        cast = 0,
        cooldown = 90,
        gcd = "off",
        school = "physical",
        
        toggle = "cooldowns",
        startsCombat = false,
        
        handler = function()
            applyBuff("vanish", 3) -- MoP: Vanish lasts 3 seconds
            
            -- Vanish breaks target lock and resets threat
            if target.exists then
                setCooldown("vanish", 90)
            end
            
            -- Master of Subtlety (if talented)
            if talent.master_of_subtlety and talent.master_of_subtlety.enabled then
                applyBuff("master_of_subtlety", 6)
            end
            
            -- Nightstalker talent bonus damage
            if talent.nightstalker.enabled then
                applyBuff("nightstalker", 3)
            end
        end,
    },
    
    -- Cheap Shot - stealth opener that stuns
    cheap_shot = {
        id = 1833,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        school = "physical",
        
        spend = function() 
            local cost = 40 -- MoP: Cheap Shot costs 40 energy
            
            -- Shadow Focus reduces cost while stealthed
            if talent.shadow_focus.enabled then
                cost = cost * 0.25 -- 75% cost reduction in stealth
            end
            
            -- Dirty Tricks reduces cost to 0
            if talent.dirty_tricks.enabled then
                cost = 0
            end
            
            return cost
        end,
        spendType = "energy",
        
        startsCombat = true,
        
        usable = function() return stealthed_all, "requires stealth" end,
        
        handler = function()
            -- Cheap Shot generates 2 combo points and stuns for 4 seconds
            gain(2, "combo_points")
            applyDebuff("target", "cheap_shot", 4)
            
            -- Apply poisons
            if buff.deadly_poison.up then
                applyDebuff("target", "deadly_poison_dot", 12, min(5, debuff.deadly_poison_dot.stack + 1))
            end
            
            -- Nerve Strike talent
            if talent.nerve_strike.enabled then
                applyDebuff("target", "nerve_strike", 6)
            end
            
            -- Dirty Deeds talent (increased crit chance)
            if talent.dirty_deeds.enabled then
                applyBuff("dirty_deeds", 6)
            end
            
            -- Remove stealth (unless Subterfuge)
            if not talent.subterfuge.enabled then
                removeBuff("stealth")
                removeBuff("vanish")
            else
                -- Subterfuge extends stealth abilities for 3 seconds
                removeBuff("stealth")
                removeBuff("vanish")
                applyBuff("subterfuge", 3)
            end
            
            -- Overkill energy bonus
            applyBuff("overkill", 20)
        end,
    },
    
    -- Opening abilities
    garrote = {
        id = 703,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 45,
        spendType = "energy",
        
        startsCombat = true,
        
        usable = function() return stealthed_all and behind_target end,
        
        handler = function()
            applyDebuff("target", "garrote")
            removeBuff("stealth")
            removeBuff("vanish")
        end,
    },
    
    ambush = {
        id = 8676,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        school = "physical",
        
        spend = function() 
            local cost = 60 -- MoP: Ambush costs 60 energy
            
            -- Shadow Focus reduces cost while stealthed (but Ambush requires stealth)
            if talent.shadow_focus.enabled then
                cost = cost * 0.25 -- 75% cost reduction in stealth
            end
            
            return cost
        end,
        spendType = "energy",
        
        startsCombat = true,
        
        usable = function() return stealthed_all, "requires stealth" end,
        
        handler = function()
            -- Ambush generates 2 combo points
            gain(2, "combo_points")
            
            -- Seal Fate proc chance on crit (50% chance for extra combo point)
            if (state.crit_chance or 0) > math.random() then
                state.last_ability_crit = true
                if math.random() <= 0.5 then
                    gain(1, "combo_points")
                end
            else
                state.last_ability_crit = false
            end
            
            -- Apply poisons from stealth
            if buff.deadly_poison.up then
                applyDebuff("target", "deadly_poison_dot", 12, min(5, debuff.deadly_poison_dot.stack + 1))
            end
            
            -- Track last ability for Seal Fate
            state.last_ability = "ambush"
            
            -- Remove stealth (unless Subterfuge talent extends it)
            if not talent.subterfuge.enabled then
                removeBuff("stealth")
                removeBuff("vanish")
            else
                -- Subterfuge extends stealth abilities for 3 seconds
                applyBuff("subterfuge", 3)
            end
        end,
    },
    
    -- Utility
    kick = {
        id = 1766,
        cast = 0,
        cooldown = 24,
        gcd = "off",
        
        startsCombat = true,
        interrupt = true,
        
        handler = function()
            interrupt()
        end,
    },
    
    evasion = {
        id = 5277,
        cast = 0,
        cooldown = 90,
        gcd = "off",
        
        startsCombat = false,
        toggle = "defensives",
        
        handler = function()
            applyBuff("evasion")
        end,
    },
    
    feint = {
        id = 1966,
        cast = 0,
        cooldown = 10,
        gcd = "spell",
        
        spend = 20,
        spendType = "energy",
        
        startsCombat = false,
        
        handler = function()
            applyBuff("feint")
        end,
    },
    
    sprint = {
        id = 2983,
        cast = 0,
        cooldown = 60,
        gcd = "off",
        
        startsCombat = false,
        
        handler = function()
            applyBuff("sprint")
        end,
    },
    
    -- Talents
    vendetta = {
        id = 79140,
        cast = 0,
        cooldown = 120,
        gcd = "off",
        
        talent = "vendetta",
        toggle = "cooldowns",
        
        startsCombat = true,
        
        handler = function()
            -- Vendetta: Marks target for death with significant damage bonus
            applyDebuff("target", "vendetta", 30) -- 30 second duration
            
            -- Vendetta also provides energy efficiency buff to the player
            applyBuff("vendetta", 30) -- Player buff for enhanced energy regeneration
            
            -- Venom Rush talent extends Vendetta's energy benefits
            if talent.venom_rush.enabled then
                applyBuff("venom_rush", 30) -- Additional energy regeneration
            end
        end,
    },
    
    shadowstep = {
        id = 36554,
        cast = 0,
        cooldown = 24,
        gcd = "off",
        
        talent = "shadowstep",
        
        startsCombat = false,
        
        handler = function()
            setDistance(5)
        end,
    },
    
    -- Poison Application Abilities
    deadly_poison = {
        id = 2823,
        cast = 3,
        cooldown = 0,
        gcd = "spell",
        school = "nature",
        
        startsCombat = false,
        
        usable = function() return not buff.deadly_poison.up, "deadly poison already applied" end,
        
        handler = function()
            applyBuff("deadly_poison", 3600) -- Apply to weapon for 1 hour
        end,
    },
    
    instant_poison = {
        id = 8680,
        cast = 3,
        cooldown = 0,
        gcd = "spell",
        school = "nature",
        
        startsCombat = false,
        
        usable = function() return not buff.instant_poison.up, "instant poison already applied" end,
        
        handler = function()
            applyBuff("instant_poison", 3600) -- Apply to weapon for 1 hour
        end,
    },
    
    wound_poison = {
        id = 8679,
        cast = 3,
        cooldown = 0,
        gcd = "spell",
        school = "nature",
        
        startsCombat = false,
        
        usable = function() return not buff.wound_poison.up, "wound poison already applied" end,
        
        handler = function()
            applyBuff("wound_poison", 3600) -- Apply to weapon for 1 hour
        end,
    },
    
    crippling_poison = {
        id = 3408,
        cast = 3,
        cooldown = 0,
        gcd = "spell",
        school = "nature",
        
        startsCombat = false,
        
        usable = function() return not buff.crippling_poison.up, "crippling poison already applied" end,
        
        handler = function()
            applyBuff("crippling_poison", 3600) -- Apply to weapon for 1 hour
        end,
    },
    
    mind_numbing_poison = {
        id = 5761,
        cast = 3,
        cooldown = 0,
        gcd = "spell",
        school = "nature",
        
        startsCombat = false,
        
        usable = function() return not buff.mind_numbing_poison.up, "mind numbing poison already applied" end,
        
        handler = function()
            applyBuff("mind_numbing_poison", 3600) -- Apply to weapon for 1 hour
        end,
    },
    
    leeching_poison = {
        id = 108211,
        cast = 3,
        cooldown = 0,
        gcd = "spell",
        school = "nature",
        
        talent = "leeching_poison",
        startsCombat = false,
        
        usable = function() return not buff.leeching_poison.up, "leeching poison already applied" end,
        
        handler = function()
            applyBuff("leeching_poison", 3600) -- Apply to weapon for 1 hour
        end,
    },
    
    paralytic_poison = {
        id = 108215,
        cast = 3,
        cooldown = 0,
        gcd = "spell",
        school = "nature",
        
        talent = "paralytic_poison",
        startsCombat = false,
        
        usable = function() return not buff.paralytic_poison.up, "paralytic poison already applied" end,
        
        handler = function()
            applyBuff("paralytic_poison", 3600) -- Apply to weapon for 1 hour
        end,
    },
    
    -- Jade Serpent Potion
    jade_serpent_potion = {
        id = 76089,
        cast = 0,
        cooldown = 0,
        gcd = "off",
        
        startsCombat = false,
        
        usable = function() return not combat and not buff.jade_serpent_potion.up end,
        
        handler = function()
            applyBuff("jade_serpent_potion", 25)
        end,
    },
    
    -- Tricks of the Trade
    tricks_of_the_trade = {
        id = 57934,
        cast = 0,
        cooldown = 30,
        gcd = "off",
        
        startsCombat = false,
        
        handler = function()
            applyBuff("tricks_of_the_trade")
        end,
    },
    
    -- Apply Poison (generic poison application)
    apply_poison = {
        id = 2823, -- Deadly Poison spell ID (updated for MoP)
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        startsCombat = false,
        
        usable = function()
            -- Check if deadly poison is missing (for SimC lethal=deadly,nonlethal=crippling)
            return not buff.deadly_poison.up, "deadly poison already applied"
        end,
        
        handler = function()
            -- Apply deadly poison as lethal and crippling poison as nonlethal
            -- This matches the SimC priority: apply_poison,lethal=deadly,nonlethal=crippling
            applyBuff("deadly_poison", 3600)
            applyBuff("crippling_poison", 3600)
        end,
    },
    
    -- Shiv - applies poison and removes buff
    shiv = {
        id = 5938,
        cast = 0,
        cooldown = 9, -- MoP: 9 second cooldown
        gcd = "spell",
        school = "physical",
        
        spend = 40, -- 40 energy cost
        spendType = "energy",
        
        startsCombat = true,
        
        handler = function()
            -- Shiv automatically applies your active poison
            local poison_applied = false
            
            if buff.deadly_poison.up then
                applyDebuff("target", "deadly_poison_dot", 12, min(5, (debuff.deadly_poison_dot.stack or 0) + 1))
                poison_applied = true
            end
            
            if buff.instant_poison.up then
                applyDebuff("target", "instant_poison_debuff", 8)
                poison_applied = true
            end
            
            if buff.wound_poison.up then
                applyDebuff("target", "wound_poison_debuff", 15, min(5, (debuff.wound_poison_debuff.stack or 0) + 1))
                poison_applied = true
            end
            
            if buff.crippling_poison.up then
                applyDebuff("target", "crippling_poison_debuff", 12)
                poison_applied = true
            end
            
            if buff.mind_numbing_poison.up then
                applyDebuff("target", "mind_numbing_poison_debuff", 16, min(5, (debuff.mind_numbing_poison_debuff.stack or 0) + 1))
                poison_applied = true
            end
            
            if buff.leeching_poison.up then
                applyDebuff("target", "leeching_poison_debuff", 8)
                poison_applied = true
            end
            
            if buff.paralytic_poison.up then
                -- Paralytic poison has a chance to stun
                if math.random() <= 0.25 then -- 25% chance to stun
                    applyDebuff("target", "paralytic_poison_debuff", 4)
                end
            end
            
            -- Shiv removes one magic effect from the target
            removeDebuff("target", "magic")
        end,
    },
    
    -- Crimson Tempest - AoE finisher
    crimson_tempest = {
        id = 121411, -- MoP Crimson Tempest spell ID
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        school = "physical",
        
        spend = function() 
            local cost = 35 -- Base energy cost
            
            -- Shadow Focus reduces cost while stealthed
            if talent.shadow_focus.enabled and (buff.stealth.up or buff.vanish.up) then
                cost = cost * 0.25
            end
            
            return cost
        end,
        spendType = "energy",
        
        startsCombat = true,
        
        usable = function() return combo_points.current and combo_points.current > 0, "requires combo points" end,
        
        handler = function()
            local cp = combo_points.current or 0
            -- Crimson Tempest duration: 2s base + 2s per combo point
            applyDebuff("target", "crimson_tempest", 2 + (2 * cp))
            spend(cp, "combo_points")
        end,
    },
    
    -- Shadow Blades - Major DPS cooldown
    shadow_blades = {
        id = 121471, -- MoP Shadow Blades spell ID
        cast = 0,
        cooldown = 180, -- 3 minute cooldown
        gcd = "off",
        school = "shadow",
        
        startsCombat = false,
        
        handler = function()
            applyBuff("shadow_blades", 12) -- 12 second duration
        end,
    },
    
    -- Cloak of Shadows - Defensive cooldown
    cloak_of_shadows = {
        id = 31224,
        cast = 0,
        cooldown = 120, -- 2 minute cooldown in MoP
        gcd = "off",
        school = "physical",
        
        startsCombat = false,
        
        handler = function()
            applyBuff("cloak_of_shadows", 5) -- 5 second duration
            -- Removes all magical debuffs
            removeDebuff("player", "magic")
        end,
    },
    
    -- Marked for Death - Combo point generator
    marked_for_death = {
        id = 137619, -- MoP Marked for Death spell ID
        cast = 0,
        cooldown = 60, -- 1 minute cooldown
        gcd = "off",
        school = "physical",
        
        startsCombat = false,
        
        usable = function() return combo_points.current == 0, "only usable at 0 combo points" end,
        
        handler = function()
            gain(5, "combo_points") -- Instantly grants 5 combo points
        end,
    },
    
    -- Preparation - Resets cooldowns
    preparation = {
        id = 14185,
        cast = 0,
        cooldown = 300, -- 5 minute cooldown in MoP
        gcd = "off",
        school = "physical",
        
        startsCombat = false,
        
        handler = function()
            -- Reset specific cooldowns
            setCooldown("vanish", 0)
            setCooldown("sprint", 0)
            setCooldown("evasion", 0)
            setCooldown("kidney_shot", 0)
            setCooldown("blind", 0)
            setCooldown("dismantle", 0)
        end,
    },
})

-- State expressions
spec:RegisterStateExpr("behind_target", function()
    return true -- Assume we can get behind target
end)

spec:RegisterStateExpr("poisoned", function()
    return debuff.deadly_poison_dot.up or debuff.wound_poison.up
end)

-- Proper stealthed state expressions for MoP compatibility
spec:RegisterStateExpr("stealthed_rogue", function() return buff.stealth.up end)
spec:RegisterStateExpr("stealthed_mantle", function() return false end) -- Not available in MoP
spec:RegisterStateExpr("stealthed_all", function() return buff.stealth.up or buff.vanish.up or buff.shadow_dance.up end)

-- Add anticipation_charges for compatibility (not used in MoP but referenced in imported rotations)
spec:RegisterStateExpr("anticipation_charges", function()
    return 0 -- Always 0 in MoP since Anticipation works differently
end)

-- Hooks
spec:RegisterHook("reset_precast", function()
    -- Reset any necessary state
end)

-- Options
spec:RegisterOptions({
    enabled = true,
    aoe = 2,
    cycle = false,
    nameplates = true,
    nameplateRange = 8,
    damage = true,
    damageExpiration = 8,
    potion = "virmen_bite_potion",
    package = "Assassination"
})
spec:RegisterSetting( "use_vendetta", true, {
    name = strformat( "Use %s", Hekili:GetSpellLinkWithTexture( 79140 ) ), -- Vendetta
    desc = "If checked, Vendetta will be recommended based on the Assassination Rogue priority. If unchecked, it will not be recommended.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "envenom_stack_threshold", 4, {
    name = strformat( "Envenom Stack Threshold" ),
    desc = "Minimum deadly poison stacks on target before recommending Envenom over Rupture (1-5)",
    type = "range",
    min = 1,
    max = 5,
    step = 1,
    width = 1.5
} )

-- Shadow Clone setting removed - not available in MoP Classic

spec:RegisterSetting( "mutilate_poison_management", true, {
    name = strformat( "Optimize %s Poison Application", Hekili:GetSpellLinkWithTexture( 1329 ) ), -- Mutilate
    desc = "If checked, the addon will optimize Mutilate usage to maintain deadly poison stacks efficiently.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "allow_shadowstep", true, {
    name = strformat( "Allow %s", Hekili:GetSpellLinkWithTexture( 36554 ) ), -- Shadowstep
    desc = "If checked, Shadowstep may be recommended for mobility and positioning. If unchecked, it will only be recommended for damage bonuses.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "use_tricks_of_the_trade", true, {
    name = strformat( "Use %s", Hekili:GetSpellLinkWithTexture( 57934 ) ), -- Tricks of the Trade
    desc = "If checked, Tricks of the Trade will be recommended based on the Assassination Rogue priority. If unchecked, it will not be recommended automatically.",
    type = "toggle",
    width = "full"
} )
-- Pack (rotation logic would go here)
spec:RegisterPack("Assassination", 20250802, [[Hekili:nJX6UTTn3NLGcy00fOzBfNMoyBG21n81aSIH5(BjrlrhZzDdsuUlag6zFNdj1fsDljO4ddfnqM8WZ97olC(MZUacN681LZxUA(9ZxAnFU99lU3zh)PuQZUuI)jYJWhXKi4VFmpNKNZIjCwsmE7tHjKael5jfz(aeo72xWc5Fj2zFpOEX92FaGnL6dhVc(8iliGkHLM77S7Bhz5LE4)jLEkIx6LCa(TpsZsVqwohU(qswP3)JEIfYSC2joezdK4i)8vHOrJj7dPboFYzN85o7IizNObUWZDdOe(rjHZyPYR)e((sVSeUseHR40mgb(kjAFIBAclgP)MsV5oCqkmOtd8Cs2JuU1rkjKF0k1Nx6TU0ZEvP3LlLEVT0BFXHdw7dzXb5SaQvrAP3SspDYaV42sVRB4)awEkH7FePT9G0oiHBfqPPUS4C2Jh5wz0ic8DP3wGVf0bbjJEg4ow8JU58m2jQoy9t0BhKO9X5krLtcPXClsmN5ZsfQwlfo6xOxjoUn8U(hrfQ8ABnDsubNfIUAa7T6)ESxBT3DdYExPCiotIz5hB8gscds(EC1XTnq31YcLMrtjzsFwo8pWR(aPiKpwOajAFrUzaWFaOVF))CUWtMgyrcdh31pGkefuWPHHiaU04miugeRg6NFKDEC3yviKcD(KCo4RQHJtm)tJ7vMt54RYTkYPUGxU)PC3KdUGGa)IeqfQzolIk0P2T0P9aCFEyvG7dQfx5pCX8rYSsUYeN(b5JB(7KDz1R07C7gHN9GUN496(NzfXdY3hyOBhY6VFynmAKDL2QCRdKyuLDkMDUIClFE0IKi0V3)A0VY8(WR)WR51qWcfsucmSm4bIMqLkP3WNwHSc3YVNuehGQ)CWUG(MHu(rsiIvsq4tTI3stdFsbOru3FL8yb9xk90QVw69Nv8rv5VCOqCsCfbW3NIPVhpACQiGj94fbOvW83WHU50SuWNeeg5Hn0D0yrihNEwKMCbYJhpdUqDNhY8PUeqLhaFyHjhBHgTlLgt0TAKSGa6JadIlNgLsZ5ggMpM8BpNUbAc6MmyWwa2vYcWge3ccypnP9Sp1qDDH6ItDzWLJONgjjC3IFn4rt(EjDh8Ivy9PTAl0lh2Ik8cWeWJ4fCMghaHjedZ)VQk)MRvvQQyXI5v2sPjr6dJ5aM2(TpmjjiSqifeS3qmzVQEhsaxEcyBOYgvMlVwsLJeGJC3hcXH5c3Fbtu1pzLGiAGaFuthev30Uhc75ALc0q(4Uf9tTbKG2LvXSqasIMWFzATS(XsopGe7x3knnMM94tQEL6Vro7wUaKQsDtKbQLq38AH909qr2tJxNFemqZG0QvH)dxUTsQwR3bijZNeJk9SmiZCFfs72xfube1xY4mLEw1THuFck70QEnm9sW7Q71SQ85yjAHrfpHb3QNBeQ95gK0It1MEcZHP7myIZjJ9mXN9kn8rptYzQY4v8T6SXJgyXGRfoivajc6Z1DLm8srUiY)u69oyKkRwPPoqzs70WXaMZoQzHcPu)JijvTE0XmzaG0wPAOBe7KrTbDR0VlEE)LeNQU0YbRlnQj7kS9CrzrL03nddgGpaYx0U3ZuEr2ev76YW)qi4lPUytN)dvZSNvlSv6l3kxongsZKenEcTHOWO2YAPxSdbPqQD7IE5IN7WpcFIP5c9I(n0r4MFgsMINlx(07xajk)ojlgBd2z3xIstY440tV3yVswLpGD)NCGfcE(VP0R)gZF4n91BE5dQpSQNF4N28ZT76)gzN7BKtgCtDR8B8R6KVFC0tF53WoSzQg77hz90aF)aQQ0Iu6kT22haCn7e(QH6xV8bHguFvd1if1zIntieXEPlsTJSZiaJTQH2WJlkaHFOvk0g2xP6EgMIylKKUfQmh78gCGZnqZOTbYyOyjmYe1iDBhDSz1LlVDKfcmRnWB3C7S(wcW2n2xpj9HXMec9WTNVDZYPfvXG5tdwtlekNdTbVAC4aUcXHEh(MkjuUhLVTND1itFzsTNNJTkV06vgMGLMOtJxmz91R(XlRJm606Lk1TXEVBycH9dydZ9M3XXCE33uT4ZwXDnLSwBJUYD2bUM2B9TxpowhAp3BNpBS9BVThMTAjYDSi3(cI4aRFFbCRTNqo()cbBTJyroD91npBGvnVfgDs6Jy27xdfK5QEXHklhouPgJQ2lemSk(Cw3oY2ENbQwmoQA4GxjUuTB0nAeDQnJp747V1E11VeKE7SruJa)2tFyBFrC9YXiqDsI6TH0GAOsgG3Q5zfb6yrWfZNDL506gVrBvd1EkgRf5YLU2N13o)YLbwfYS3AoF9LldUaeOu91MCv9YjQ5inC1d30QEFL2Guv5EiDr1b67SyMCYEiGtpe32Kan7AOpUSd017v45aT(AeWxi5Q131roBwdq7gRu7uacBMpBWDjOCO(CRQ(v4UPtaS4NX89iHAvczZYkDBplcyauQgN3et2RuyQzfadGaXC74Z7oZ)2M59FhmR)aiWyUCdoXUwTn8a(f8Jjzo72fvCakRjM4X5Fp]])
