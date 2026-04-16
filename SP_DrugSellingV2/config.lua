Config = {}

-- ============================================
-- GENERAL SETTINGS
-- ============================================
Config.PaymentType = "money" -- "money", "bank", "black_money", or item name
Config.Debug = false        -- Toggle verbose debug prints (server/client)
Config.ScamChance = 0.30      -- 30% scam chance (random each time, no pattern)
Config.DeclineChance = 0.25   -- 25% decline chance (random each time, no pattern)
Config.CraftingTime = 60000   -- 1 minute (60000ms) to craft wholesale items
Config.EnableAddiction = false -- Enable/disable addiction system
Config.DriverlessDrivingStyle = 786603 -- Avoid vehicles/peds/objects, stop at lights (better for MLO/custom hoods with trees, medians, fences)
Config.MaxDealerDistFromRoadForBlockWork = 20 -- Max meters dealer can be from a road to call junkie (avoids bad driving/misdirection)

-- ============================================
-- DRUG DEFINITIONS & ECONOMY
-- ============================================

-- Drug Categories:
-- 1. WHOLESALE (crafted by plugs, sold to players only, cannot be used/sold to NPC)
-- 2. RETAIL (bust-down products, can be sold to NPC and used)
-- 3. USABLE (final form, can be consumed for effects)

Config.Drugs = {
    -- ========== WEED SYSTEM ==========
    {
        name = "weed_pound",
        label = "Weed Pound",
        category = "wholesale",
        type = "weed",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = true,
        bustDownItem = "scale",
        bustDownAnim = {
            dict = "anim@amb@business@meth@meth_smash_weight_check@",
            clip = "break_weigh_v3_char02"
        },
        bustDownResult = {
            item = "weed_3_5g",
            count = 128, -- 1 pound = 128 x 3.5g
            preserveMetadata = true -- Preserve strain in metadata
        },
        strains = { -- Different strains plugs can craft
            "og_kush",
            "purple_haze",
            "blue_dream",
            "sour_diesel",
            "white_widow"
        },
        minPrice = 2000,
        maxPrice = 3500
    },
    {
        name = "weed_3_5g",
        label = "3.5g Weed",
        category = "retail",
        type = "weed",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        useRequires = {"backwood", "lighter"}, -- Need both backwood and lighter to smoke
        minPrice = 94,
        maxPrice = 127,
        useEffect = {
            duration = 120000, -- 2 minutes
            animDict = "amb@world_human_smoking@male@male_a@enter",
            animClip = "enter",
            visualEffect = "weed_high",
            useProp = "prop_cigar_01", -- blunt
            usePropOffset = { 0.02, 0.0, 0.0 }, -- just out of mouth a tad
            usePropRot = { -85.0, 180.0, 25.0 }, -- 180 yaw so lit end faces out
        }
    },
    -- ========== LEMON CHERRY GELATO (custom weed – drug only, no job crafting yet) ==========
    {
        name = "weed_pound_gelato",
        label = "Lemon Cherry Gelato Pound",
        category = "wholesale",
        type = "weed",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = true,
        bustDownItem = "scale",
        bustDownAnim = {
            dict = "anim@amb@business@meth@meth_smash_weight_check@",
            clip = "break_weigh_v3_char02"
        },
        bustDownResult = {
            item = "weed_3_5g_gelato",
            count = 128,
        },
        minPrice = 2000,
        maxPrice = 3500
    },
    {
        name = "weed_3_5g_gelato",
        label = "Lemon Cherry Gelato 3.5g",
        category = "retail",
        type = "weed",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        useRequires = {"backwood", "lighter"},
        minPrice = 94,
        maxPrice = 127,
        useEffect = {
            duration = 120000,
            animDict = "amb@world_human_smoking@male@male_a@enter",
            animClip = "enter",
            visualEffect = "weed_high",
            useProp = "prop_cigar_01",
            usePropOffset = { 0.02, 0.0, 0.0 },
            usePropRot = { -85.0, 180.0, 25.0 },
        }
    },
    -- ========== CEREAL MILK (custom weed – nbkpharmacy crafting) ==========
    {
        name = "weed_pound_cm",
        label = "Cereal Milk Pound",
        category = "wholesale",
        type = "weed",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = true,
        bustDownItem = "scale",
        bustDownAnim = {
            dict = "anim@amb@business@meth@meth_smash_weight_check@",
            clip = "break_weigh_v3_char02"
        },
        bustDownResult = {
            item = "weed_3_5g_cm",
            count = 128,
        },
        minPrice = 2000,
        maxPrice = 3500
    },
    {
        name = "weed_3_5g_cm",
        label = "Cereal Milk Exotic 3.5g",
        category = "retail",
        type = "weed",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        useRequires = {"backwood", "lighter"},
        minPrice = 98,
        maxPrice = 130,
        useEffect = {
            duration = 120000,
            animDict = "amb@world_human_smoking@male@male_a@enter",
            animClip = "enter",
            visualEffect = "weed_high",
            useProp = "prop_cigar_01",
            usePropOffset = { 0.02, 0.0, 0.0 },
            usePropRot = { -85.0, 180.0, 25.0 },
        }
    },

    -- ========== COCAINE SYSTEM ==========
    {
        name = "coke_brick",
        label = "Coke Brick",
        category = "wholesale",
        type = "cocaine",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = true,
        bustDownItem = {"gloves", "plasticbaggie"}, -- Need both gloves and plastic baggie
        bustDownAnim = {
            dict = "anim@amb@business@coc@coc_unpack_cut@",
            clip = "fullcut_cycle_v3_cokecutter"
        },
        bustDownResult = {
            item = "coke_gram",
            count = 150, -- 1 brick = 150 grams
            preserveMetadata = true -- Preserve quality in metadata
        },
        qualities = { -- Different qualities plugs can craft
            "pure",
            "fishscale",
            "raw"
        },
        minPrice = 5000,
        maxPrice = 8000
    },
    {
        name = "coke_gram",
        label = "Coke Gram",
        category = "retail",
        type = "cocaine",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        minPrice = 96,
        maxPrice = 122,
        useEffect = {
            duration = 120000, -- 2 minutes for visual effects (quality affects this, but capped at 2 min)
            animDict = "safe@trevor@ig_7",
            animClip = "ig_7_smelllikeasea",
            visualEffect = "coke_high",
            useProp = "prop_meth_bag_01", -- bag of powder
            usePropDelay = 4000, -- spawn prop 4 seconds after anim starts
            usePropOffset = { 0.06, 0.02, -0.08 }, -- in hand, lowered to fit look
            usePropRot = { 0.0, 0.0, 15.0 },
        }
    },
    
    -- ========== PROMETHAZINE SYSTEM ==========
    {
        name = "prometh_box_pai",
        label = "Box of Promethazine PAI (12 Pints)",
        category = "wholesale",
        type = "promethazine",
        subtype = "pai",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = false, -- Box opens directly, no tool needed
        bustDownAnim = {
            dict = "anim@amb@business@meth@meth_smash_weight_check@",
            clip = "break_weigh_v3_char02"
        },
        bustDownResult = {
            item = "prometh_pint_pai",
            count = 12
        },
        minPrice = 1200,
        maxPrice = 1800
    },
    {
        name = "prometh_box_tris",
        label = "Box of Promethazine TRIS (12 Pints)",
        category = "wholesale",
        type = "promethazine",
        subtype = "tris",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = false,
        bustDownAnim = {
            dict = "anim@amb@business@meth@meth_smash_weight_check@",
            clip = "break_weigh_v3_char02"
        },
        bustDownResult = {
            item = "prometh_pint_tris",
            count = 12
        },
        minPrice = 1200,
        maxPrice = 1800
    },
    {
        name = "prometh_box_qua",
        label = "Box of Promethazine QUA (12 Pints)",
        category = "wholesale",
        type = "promethazine",
        subtype = "qua",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = false,
        bustDownAnim = {
            dict = "anim@amb@business@meth@meth_smash_weight_check@",
            clip = "break_weigh_v3_char02"
        },
        bustDownResult = {
            item = "prometh_pint_qua",
            count = 12
        },
        minPrice = 1200,
        maxPrice = 1800
    },
    {
        name = "prometh_pint_pai",
        label = "Pint of Promethazine PAI",
        category = "wholesale",
        type = "promethazine",
        subtype = "pai",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = true,
        bustDownItem = "baby_bottle",
        bustDownAnim = {
            dict = "anim@amb@carmeet@checkout_engine@",
            clip = "male_e_idle_b"
        },
        bustDownResult = {
            item = "prometh_deuce_pai",
            count = 12 -- 1 pint = 12 deuces
        },
        minPrice = 100,
        maxPrice = 150
    },
    {
        name = "prometh_pint_tris",
        label = "Pint of Promethazine TRIS",
        category = "wholesale",
        type = "promethazine",
        subtype = "tris",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = true,
        bustDownItem = "baby_bottle",
        bustDownAnim = {
            dict = "anim@amb@carmeet@checkout_engine@",
            clip = "male_e_idle_b"
        },
        bustDownResult = {
            item = "prometh_deuce_tris",
            count = 12
        },
        minPrice = 100,
        maxPrice = 150
    },
    {
        name = "prometh_pint_qua",
        label = "Pint of Promethazine QUA",
        category = "wholesale",
        type = "promethazine",
        subtype = "qua",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = true,
        bustDownItem = "baby_bottle",
        bustDownAnim = {
            dict = "anim@amb@carmeet@checkout_engine@",
            clip = "male_e_idle_b"
        },
        bustDownResult = {
            item = "prometh_deuce_qua",
            count = 12
        },
        minPrice = 100,
        maxPrice = 150
    },
    {
        name = "prometh_deuce_pai",
        label = "Deuce Promethazine PAI",
        category = "retail",
        type = "promethazine",
        subtype = "pai",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        useRequires = "styrofoam_cup", -- Need cup to use
        useResult = {
            item = "prometh_cup_pai",
            count = 1
        },
        minPrice = 93,
        maxPrice = 124,
        useEffect = {
            duration = 180000, -- 3 minutes
            animDict = "amb@world_human_drinking@beer@male@idle_a",
            animClip = "idle_a",
            visualEffect = "prometh_high",
            useProp = "prop_plastic_cup_02",
            usePropOffset = { 0.02, 0.0, 0.04 }, -- raised a tad
            usePropRot = { 0.0, 0.0, 0.0 },
        }
    },
    {
        name = "prometh_deuce_tris",
        label = "Deuce Promethazine TRIS",
        category = "retail",
        type = "promethazine",
        subtype = "tris",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        useRequires = "styrofoam_cup",
        useResult = {
            item = "prometh_cup_tris",
            count = 1
        },
        minPrice = 95,
        maxPrice = 121,
        useEffect = {
            duration = 180000,
            animDict = "amb@world_human_drinking@beer@male@idle_a",
            animClip = "idle_a",
            visualEffect = "prometh_high",
            useProp = "prop_plastic_cup_02",
            usePropOffset = { 0.02, 0.0, 0.04 }, -- raised a tad
            usePropRot = { 0.0, 0.0, 0.0 },
        }
    },
    {
        name = "prometh_deuce_qua",
        label = "Deuce Promethazine QUA",
        category = "retail",
        type = "promethazine",
        subtype = "qua",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        useRequires = "styrofoam_cup",
        useResult = {
            item = "prometh_cup_qua",
            count = 1
        },
        minPrice = 97,
        maxPrice = 125,
        useEffect = {
            duration = 180000,
            animDict = "amb@world_human_drinking@beer@male@idle_a",
            animClip = "idle_a",
            visualEffect = "prometh_high",
            useProp = "prop_plastic_cup_02",
            usePropOffset = { 0.02, 0.0, 0.04 }, -- raised a tad
            usePropRot = { 0.0, 0.0, 0.0 },
        }
    },
    {
        name = "prometh_cup_pai",
        label = "Cup of Promethazine PAI",
        category = "usable",
        type = "promethazine",
        subtype = "pai",
        canUse = true,
        canSellToNPC = false,
        requiresBustDown = false,
        minPrice = 0,
        maxPrice = 0,
        useEffect = {
            duration = 180000,
            animDict = "amb@world_human_drinking@beer@male@idle_a",
            animClip = "idle_a",
            visualEffect = "prometh_high",
            useProp = "prop_plastic_cup_02",
            usePropOffset = { 0.02, 0.0, 0.04 }, -- raised a tad
            usePropRot = { 0.0, 0.0, 0.0 },
        }
    },
    {
        name = "prometh_cup_tris",
        label = "Cup of Promethazine TRIS",
        category = "usable",
        type = "promethazine",
        subtype = "tris",
        canUse = true,
        canSellToNPC = false,
        requiresBustDown = false,
        minPrice = 0,
        maxPrice = 0,
        useEffect = {
            duration = 180000,
            animDict = "amb@world_human_drinking@beer@male@idle_a",
            animClip = "idle_a",
            visualEffect = "prometh_high",
            useProp = "prop_plastic_cup_02",
            usePropOffset = { 0.02, 0.0, 0.04 }, -- raised a tad
            usePropRot = { 0.0, 0.0, 0.0 },
        }
    },
    {
        name = "prometh_cup_qua",
        label = "Cup of Promethazine QUA",
        category = "usable",
        type = "promethazine",
        subtype = "qua",
        canUse = true,
        canSellToNPC = false,
        requiresBustDown = false,
        minPrice = 0,
        maxPrice = 0,
        useEffect = {
            duration = 180000,
            animDict = "amb@world_human_drinking@beer@male@idle_a",
            animClip = "idle_a",
            visualEffect = "prometh_high",
            useProp = "prop_plastic_cup_02",
            usePropOffset = { 0.02, 0.0, 0.04 }, -- raised a tad
            usePropRot = { 0.0, 0.0, 0.0 },
        }
    },

    -- ========== PILL SYSTEM ==========
    {
        name = "percocet_bottle",
        label = "Percocet Bottle (60ct)",
        category = "wholesale",
        type = "pills",
        subtype = "percocet",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = false, -- Just use the bottle, no tool needed
        bustDownAnim = {
            dict = "amb@world_human_bum_standing@twitchy@base",
            clip = "base"
        },
        bustDownResult = {
            item = "percocet_pill",
            count = 60,
            leavesItem = "empty_percocet_bottle" -- Leaves empty bottle
        },
        minPrice = 800,
        maxPrice = 1200
    },
    {
        name = "percocet_pill",
        label = "Percocet Pill",
        category = "retail",
        type = "pills",
        subtype = "percocet",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        minPrice = 94,
        maxPrice = 126,
        useEffect = {
            duration = 150000,
            animDict = "mp_suicide",
            animClip = "pill",
            animDuration = 3000,
            visualEffect = "percocet_high",
            useProp = "prop_cs_pill_bottle_01",
            usePropOffset = { 0.06, 0.0, 0.02 },
        }
    },
    {
        name = "painkiller_bottle",
        label = "Painkiller Bottle (60ct)",
        category = "wholesale",
        type = "pills",
        subtype = "painkiller",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = false,
        bustDownAnim = {
            dict = "amb@world_human_bum_standing@twitchy@base",
            clip = "base"
        },
        bustDownResult = {
            item = "painkiller_pill",
            count = 60,
            leavesItem = "empty_painkiller_bottle"
        },
        minPrice = 600,
        maxPrice = 1000
    },
    {
        name = "painkiller_pill",
        label = "Painkiller Pill",
        category = "retail",
        type = "pills",
        subtype = "painkiller",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        minPrice = 98,
        maxPrice = 122,
        useEffect = {
            duration = 90000,
            animDict = "mp_suicide",
            animClip = "pill",
            animDuration = 3000,
            visualEffect = "painkiller_high",
            useProp = "prop_cs_pill_bottle_01",
            usePropOffset = { 0.06, 0.0, 0.02 },
        }
    },
    {
        name = "xanax_bottle",
        label = "Xanax Bottle (60ct)",
        category = "wholesale",
        type = "pills",
        subtype = "xanax",
        canUse = false,
        canSellToNPC = false,
        requiresBustDown = false,
        bustDownAnim = {
            dict = "amb@world_human_bum_standing@twitchy@base",
            clip = "base"
        },
        bustDownResult = {
            item = "xanax_pill",
            count = 60,
            leavesItem = "empty_xanax_bottle"
        },
        minPrice = 1000,
        maxPrice = 1500
    },
    {
        name = "xanax_pill",
        label = "Xanax Pill",
        category = "retail",
        type = "pills",
        subtype = "xanax",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        minPrice = 93,
        maxPrice = 128,
        useEffect = {
            duration = 120000,
            animDict = "mp_suicide",
            animClip = "pill",
            animDuration = 3000,
            visualEffect = "xanax_steady",
            useProp = "prop_cs_pill_bottle_01",
            usePropOffset = { 0.06, 0.0, 0.02 },
        }
    },

    -- ========== CUSTOM / STREET ==========
    {
        name = "pinkcocaine",
        label = "Pink Cocaine",
        category = "retail",
        type = "street",
        subtype = "pinkcocaine",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        minPrice = 96,
        maxPrice = 121,
        useEffect = {
            duration = 120000,
            animDict = "safe@trevor@ig_7",
            animClip = "ig_7_smelllikeasea",
            visualEffect = "pinkcocaine_high",
            useProp = "prop_cs_ciggy_01",
            usePropOffset = { 0.02, 0.0, 0.0 },
        }
    },
    {
        name = "escosdrug",
        label = "Fetty Blunts",
        category = "retail",
        type = "street",
        subtype = "fetty",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        minPrice = 95,
        maxPrice = 123,
        useEffect = {
            duration = 120000,
            animDict = "switch@michael@smoking",
            animClip = "michael_smoking_loop",
            visualEffect = "fetty_high",
            useProp = "prop_amb_ciggy_01",
            usePropOffset = { 0.02, 0.0, 0.0 },
        }
    },
    {
        name = "stkgummies",
        label = "STK Gummies",
        category = "retail",
        type = "street",
        subtype = "gummies",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        minPrice = 94,
        maxPrice = 124,
        useEffect = {
            duration = 120000,
            animDict = "mp_player_inteat@pnq",
            animClip = "loop",
            visualEffect = "gummies_high",
            useProp = "prop_cs_pill_bottle_01",
            usePropOffset = { 0.06, 0.0, 0.02 },
        }
    },
    {
        name = "maleekdrug",
        label = "Fentanyl",
        category = "retail",
        type = "street",
        subtype = "fentanyl",
        canUse = true,
        canSellToNPC = true,
        requiresBustDown = false,
        minPrice = 97,
        maxPrice = 126,
        useEffect = {
            duration = 120000,
            animDict = "mp_player_inteat@pnq",
            animClip = "loop",
            visualEffect = "fentanyl_high",
            useProp = "prop_amb_ciggy_01",
            usePropOffset = { 0.02, 0.0, 0.0 },
        }
    },
    -- Craftable pharmacy/street drugs (from job crafting tables)
    { name = "teslapill", label = "Teslapill", category = "retail", type = "street", subtype = "tesla", canUse = true, canSellToNPC = true, requiresBustDown = false, minPrice = 92, maxPrice = 118, useEffect = { duration = 120000, animDict = "mp_suicide", animClip = "pill", animDuration = 3000, visualEffect = "gummies_high", useProp = "prop_cs_pill_bottle_01", usePropOffset = { 0.06, 0.0, 0.02 } } },
    { name = "baggedweed", label = "Bagged Weed Tablets (30mg)", category = "retail", type = "weed", canUse = true, canSellToNPC = true, requiresBustDown = false, minPrice = 90, maxPrice = 115, useEffect = { duration = 120000, animDict = "mp_player_inteat@pnq", animClip = "loop", visualEffect = "weed_high", useProp = "prop_cs_pill_bottle_01", usePropOffset = { 0.06, 0.0, 0.02 } } },
    { name = "lean_hitech", label = "Hi-Tech Tablets (10mg)", category = "retail", type = "street", subtype = "lean", canUse = true, canSellToNPC = true, requiresBustDown = false, minPrice = 88, maxPrice = 112, useEffect = { duration = 120000, animDict = "mp_suicide", animClip = "pill", animDuration = 3000, visualEffect = "fetty_high", useProp = "prop_cs_pill_bottle_01", usePropOffset = { 0.06, 0.0, 0.02 } } },
    { name = "hitech_syrup", label = "Hi-Tech Syrup", category = "retail", type = "street", subtype = "lean", canUse = true, canSellToNPC = true, requiresBustDown = false, minPrice = 95, maxPrice = 120, useEffect = { duration = 120000, animDict = "mp_player_inteat@pnq", animClip = "loop", visualEffect = "fetty_high", useProp = "prop_plastic_cup_02", usePropOffset = { 0.02, 0.0, 0.04 }, usePropRot = { 0.0, 0.0, 0.0 } } }
}

-- ============================================
-- CRAFTING RECIPES (FOR PLUGS)
-- ============================================
Config.CraftingRecipes = {
    -- Weed Pounds (different strains)
    {
        result = { item = "weed_pound", metadata = { strain = "og_kush" } },
        ingredients = {
            { item = "weed_seed_og", count = 50 },
            { item = "fertilizer", count = 10 }
        },
        job = "plug", -- Only plugs can craft
        time = Config.CraftingTime
    },
    {
        result = { item = "weed_pound", metadata = { strain = "purple_haze" } },
        ingredients = {
            { item = "weed_seed_purple", count = 50 },
            { item = "fertilizer", count = 10 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    {
        result = { item = "weed_pound", metadata = { strain = "blue_dream" } },
        ingredients = {
            { item = "weed_seed_blue", count = 50 },
            { item = "fertilizer", count = 10 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    {
        result = { item = "weed_pound", metadata = { strain = "sour_diesel" } },
        ingredients = {
            { item = "weed_seed_sour", count = 50 },
            { item = "fertilizer", count = 10 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    {
        result = { item = "weed_pound", metadata = { strain = "white_widow" } },
        ingredients = {
            { item = "weed_seed_white", count = 50 },
            { item = "fertilizer", count = 10 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    
    -- Cocaine Bricks (different qualities)
    {
        result = { item = "coke_brick", metadata = { quality = "pure" } },
        ingredients = {
            { item = "coca_leaves", count = 100 },
            { item = "chemicals", count = 20 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    {
        result = { item = "coke_brick", metadata = { quality = "fishscale" } },
        ingredients = {
            { item = "coca_leaves", count = 80 },
            { item = "chemicals", count = 15 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    {
        result = { item = "coke_brick", metadata = { quality = "raw" } },
        ingredients = {
            { item = "coca_leaves", count = 60 },
            { item = "chemicals", count = 10 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    
    -- Promethazine Boxes
    {
        result = { item = "prometh_box_pai", count = 1 },
        ingredients = {
            { item = "prometh_raw_pai", count = 12 },
            { item = "bottle_packaging", count = 1 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    {
        result = { item = "prometh_box_tris", count = 1 },
        ingredients = {
            { item = "prometh_raw_tris", count = 12 },
            { item = "bottle_packaging", count = 1 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    {
        result = { item = "prometh_box_qua", count = 1 },
        ingredients = {
            { item = "prometh_raw_qua", count = 12 },
            { item = "bottle_packaging", count = 1 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    
    -- Pill Bottles
    {
        result = { item = "percocet_bottle", count = 1 },
        ingredients = {
            { item = "oxycodone_powder", count = 60 },
            { item = "pill_bottle", count = 1 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    {
        result = { item = "painkiller_bottle", count = 1 },
        ingredients = {
            { item = "opioid_powder", count = 60 },
            { item = "pill_bottle", count = 1 }
        },
        job = "plug",
        time = Config.CraftingTime
    },
    {
        result = { item = "xanax_bottle", count = 1 },
        ingredients = {
            { item = "alprazolam_powder", count = 60 },
            { item = "pill_bottle", count = 1 }
        },
        job = "plug",
        time = Config.CraftingTime
    }
}

-- ============================================
-- JOB-BASED CRAFTING (NUI AT COORDS)
-- All additems (output) must exist in ox_inventory items (e.g. items.lua or ox_inventory data).
-- Job name must match the key in jobs (e.g. job "maleekdrug" for zone maleekdrug).
-- ============================================
Config.Craftings = {
    ["maleekdrug"] = {
        jobs = { ["maleekdrug"] = 0 },
        gang = nil,
        label = "Drug Processing Table",
        icon = "fa-solid fa-vials",
        item = nil,
        coords = { [1] = vector4(1781.2129, 3796.2170, 2001.5398, 292.3899) },
        items = {
            { title = "maleekdrug", description = "Process raw fentanyl into diluted, street-ready product", progressbar = "Diluting, binding, and packaging fentanyl", duration = 12100, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "maleekdrug", amount = 3 } } },
            { title = "Painkiller Bottle (60ct)", description = "Fill and seal a bottle with 60 painkiller tablets from opioid powder.", progressbar = "Filling and sealing painkiller bottle", duration = 15000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "painkiller_bottle", amount = 1 } } },
        },
    },
    ["dosebox"] = {
        jobs = { ["dosebox"] = 0 },
        gang = nil,
        label = "Drug Processing Table",
        icon = "fa-solid fa-vials",
        item = nil,
        coords = { [1] = vector4(1429.1244, 3665.4441, 2001.5927, 265.9874) },
        items = {
            { title = "teslapill", description = "Process teslapill", progressbar = "Cutting and packaging teslapill", duration = 12100, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "teslapill", amount = 3 } } },
            { title = "Percocet Bottle (60ct)", description = "Fill and seal a bottle with 60 Percocet 30mg tablets from oxycodone powder.", progressbar = "Filling and sealing Percocet bottle", duration = 15000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "percocet_bottle", amount = 1 } } },
        },
    },
    ["escospharmacy"] = {
        jobs = { ["escospharmacy"] = 0 },
        gang = nil,
        label = "Drug Processing Table",
        icon = "fa-solid fa-vials",
        item = nil,
        coords = { [1] = vector4(59.6949, 6644.9453, 2001.3248, 264.2988) },
        items = {
            { title = "escosdrug", description = "Process escosdrug", progressbar = "Cutting and packaging escosdrug", duration = 12100, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "escosdrug", amount = 3 } } },
            { title = "Box of Promethazine PAI (12 Pints)", description = "Package 12 pints of promethazine PAI into a sealed box.", progressbar = "Packaging Promethazine PAI box", duration = 15000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "prometh_box_pai", amount = 1 } } },
        },
    },
    ["icebox"] = {
        jobs = { ["icebox"] = 0 },
        gang = nil,
        label = "Craft Chain Ruby & Diamonds",
        icon = "fa-solid fa-vials",
        item = nil,
        coords = { [1] = vector4(-624.3806, -227.5154, 38.0571, 26.2012) },
        items = {
            { title = "diamond", description = "Craft diamonds for chains", progressbar = "Cutting and polishing diamonds", duration = 12100, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "diamond", amount = 3 } } },
            { title = "ruby", description = "Craft rubies for chains", progressbar = "Cutting and polishing rubies", duration = 12100, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "ruby", amount = 3 } } },
        },
    },
    ["nbkpharmacy"] = {
        jobs = { ["nbkpharmacy"] = 0 },
        gang = nil,
        label = "Pharmaceutical Processing Station",
        icon = "fa-solid fa-vials",
        item = nil,
        coords = { [1] = vector4(-229.1760, 6374.6685, 2001.1000, 276.9291) },
        items = {
            { title = "Press Baggie Weeds into Tablets (30mg)", description = "Measures raw material, binds the mixture, and presses into uniform 30mg tablets.", progressbar = "Measuring, pressing, and sealing 30mg tablets", duration = 12100, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "baggedweed", amount = 3 } } },
            { title = "Press Oxy Powder into Percocet 30s", description = "Compresses measured oxycodone powder into Percocet-style 30mg tablets.", progressbar = "Pressing and stamping Percocet 30mg tablets", duration = 12100, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "percocet_pill", amount = 3 } } },
            { title = "Press Hi-Tech Blend into Tablets (10mg)", description = "Measures smaller doses and presses into clean 10mg tablets.", progressbar = "Pressing and coating 10mg tablets", duration = 12100, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "lean_hitech", amount = 3 } } },
            { title = "Weed Pound", description = "Process seeds and fertilizer into a full pound of weed for distribution.", progressbar = "Processing weed pound", duration = 12000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "weed_pound", amount = 1 } } },
            { title = "Cereal Milk Pound", description = "Process into a full pound of Cereal Milk exotic for distribution.", progressbar = "Processing Cereal Milk pound", duration = 12000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "weed_pound_cm", amount = 1 } } },
            { title = "Xanax Bottle (60ct)", description = "Fill and seal a bottle with 60 Xanax tablets from alprazolam powder.", progressbar = "Filling and sealing Xanax bottle", duration = 15000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "xanax_bottle", amount = 1 } } },
            { title = "Box of Promethazine TRIS (12 Pints)", description = "Package 12 pints of promethazine TRIS into a sealed box.", progressbar = "Packaging Promethazine TRIS box", duration = 15000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "prometh_box_tris", amount = 1 } } },
        },
    },
    ["bkbpharmacy"] = {
        jobs = { ["bkbpharmacy"] = 0 },
        gang = nil,
        label = "Secure Pharmaceutical Processing Lab",
        icon = "fa-solid fa-vials",
        item = nil,
        coords = { [1] = vector4(1971.6637, 3808.5217, 2001.3245, 278.6901) },
        items = {
            { title = "Package stkgummies", description = "Measures, seals, and packages gummies for quality and consistency.", progressbar = "Measuring and packaging gummies", duration = 12200, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "stkgummies", amount = 3 } } },
            { title = "Box of Promethazine QUA (12 Pints)", description = "Package 12 pints of promethazine QUA into a sealed box.", progressbar = "Packaging Promethazine QUA box", duration = 15000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "prometh_box_qua", amount = 1 } } },
        },
    },
    ["hitechpharmacy"] = {
        jobs = { ["hitechpharmacy"] = 0 },
        gang = nil,
        label = "Secure Pharmaceutical Processing Lab",
        icon = "fa-solid fa-vials",
        item = nil,
        coords = { [1] = vector4(357.3929, 2617.3491, 2001.3248, 272.1480) },
        items = {
            { title = "Package hitech syrup", description = "Individually measures and packages hitech syrup.", progressbar = "Measuring hitech syrup", duration = 12200, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "hitech_syrup", amount = 3 } } },
            { title = "Coke Brick (raw)", description = "Process coca leaves and chemicals into a raw-quality coke brick.", progressbar = "Processing coke brick", duration = 15000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "coke_brick", amount = 1 } } },
        },
    },
        ["TheSpotTrap"] = {
        jobs = { ["TheSpotTrap"] = 0 },
        gang = nil,
        label = "Drug Processing Table",
        icon = "fa-solid fa-vials",
        item = nil,
        coords = { [1] = vector4(-441.3810, 6331.8740, 2001.8411, 178.3441) },
        items = {
            { title = "Gelato Pound", description = "Process into a full pound of Lemon Cherry Gelato weed for distribution.", progressbar = "Processing Gelato pound", duration = 15000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "weed_pound_gelato", amount = 1 } } },
        },
    },
        ["scattpattdrug"] = {
        jobs = { ["scattpattdrug"] = 0 },
        gang = nil,
        label = "Drug Processing Table",
        icon = "fa-solid fa-vials",
        item = nil,
        coords = { [1] = vector4(32.8418, 3672.0503, 40.2956, 347.7996) },
        items = {
            { title = "Coke Brick", description = "Process coca leaves and chemicals into a coke brick.", progressbar = "Processing coke brick", duration = 13000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "coke_brick", amount = 1 } } },
            { title = "Percocet Bottle (60ct)", description = "Fill and seal a bottle with 60 Percocet 30mg tablets from oxycodone powder.", progressbar = "Filling and sealing Percocet bottle", duration = 15000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "percocet_bottle", amount = 1 } } },
        },
    },
        ["rhysdrug"] = {
        jobs = { ["rhysdrug"] = 0 },
        gang = nil,
        label = "Drug Processing Table",
        icon = "fa-solid fa-vials",
        item = nil,
        coords = { [1] = vector4(90.1033, 3744.8167, 40.6266, 68.2044) },
        items = {
            { title = "weed pound", description = "wrapping murdatown 30 pound.", progressbar = "Processing murdatown 30 pound", duration = 13000, requireditems = { { name = "gloves", amount = 1 } }, additems = { { name = "weed_pound", amount = 1 } } },
        },
    },

}

-- Crafting spot marker (shown to players with job when they have access)
Config.CraftingMarkerDistance = 30.0
Config.CraftingMarkerColor = { r = 0, g = 200, b = 255, a = 120 } -- cyan circle

-- Block work (corner sale): spawn junkie closer first for MLO/custom maps where long pathfinding can glitch
-- Try close range (min–max) first, then fall back to far range if no road found
-- Spawn junkie at CLOSE range first (shorter drive = better pathfinding in custom hoods/MLOs). If many peds wreck or circle, try 50–120 for CloseMin/Max.
-- Optional: ensure resource "chicago_gps_nodes" and fill nodes/connections in its config so block work uses your custom hood road coords for spawn, dest, and pathfinding.
Config.BlockWorkSpawnCloseMin = 80.0
Config.BlockWorkSpawnCloseMax = 220.0
Config.BlockWorkSpawnFarMin = 350.0
Config.BlockWorkSpawnFarMax = 550.0
-- Waypoint is snapped to road only if within this many meters of the ideal route (avoids ped circling the block on addon/MLO maps)
Config.BlockWorkWaypointMaxSnapOffLine = 25.0

-- ============================================
-- VISUAL EFFECTS CONFIG
-- ============================================
Config.VisualEffects = {
    -- ========== WEED EFFECTS ==========
    weed_high = {
        screenEffect = "DrugsMichaelAliensFight",
        colorModifier = true, -- Green tint
        motionBlur = 0.3,
        cameraShake = 0.1,
        armorRestore = 7, -- +7 armor per use (compensates for armor drain)
        healthRestore = 2, -- Extra benefit: minor health restore
        description = "Relaxed, mellow high with slight visual distortion +7 armor, +2 health"
    },
    
    -- ========== COCAINE EFFECTS ==========
    coke_high = {
        screenEffect = "DrugsMichaelAliensFightIn",
        colorModifier = true, -- Strong color flash filter
        motionBlur = 0.2,
        cameraShake = 0.5, -- Strong screen vibration
        staminaRestore = 35, -- Restores 35 stamina per use (usage-based, not time-based)
        -- Cocaine gives alertness and visual effects, +35 stamina per use
        description = "Alertness and visual effects + 35 stamina per use"
    },
    
    -- ========== PROMETHAZINE EFFECTS ==========
    prometh_high = {
        screenEffect = "DrugsDrivingIn",
        colorModifier = "drug_deadman_blend", -- Purple/blue tint filter
        colorModifierStrength = 0.7, -- Strong color filter
        motionBlur = 0.5,
        cameraShake = 0.6, -- Increased for more aggressive screen sway effect
        slowMotion = 0.85, -- 15% slower (feels like slow motion)
        screenSway = true, -- Enable screen sway (visual movement)
        screenSwayStrength = 3.0, -- More aggressive sway to prevent exploiting slow motion
        screenBlackout = 0.5, -- 0.5 second blackout when effect starts
        healthRestore = 2, -- Restores 2 health per use (usage-based)
        -- Promethazine gives slow motion effect and screen sway
        description = "Slow motion effect with screen sway"
    },
    
    -- ========== PILL EFFECTS (Percocet / Painkiller / Xanax) ==========
    percocet_high = {
        screenEffect = "DrugsMichaelAliensFight",
        colorModifier = "drug_deadman_blend",
        colorModifierStrength = 0.35, -- Warm, relaxed opioid tint
        motionBlur = 0.2,
        cameraShake = 0.05, -- Very subtle
        healthRestore = { min = 2, max = 4 }, -- Opioid pain relief
        staminaRestore = { min = 2, max = 4 }, -- Relaxation from pain relief
        description = "Opioid pain relief with minor health and stamina restore (+2-4 each)"
    },
    painkiller_high = {
        screenEffect = "DrugsMichaelAliensFight",
        colorModifier = true,
        colorModifierStrength = 0.2, -- Very mild OTC effect
        motionBlur = 0.1,
        cameraShake = 0.05,
        healthRestore = { min = 2, max = 4 }, -- OTC pain relief
        description = "Mild pain relief with minor health restore (+2-4)"
    },
    xanax_steady = {
        screenEffect = "DrugsMichaelAliensFight",
        colorModifier = "drug_deadman_blend",
        colorModifierStrength = 0.25, -- Subtle calm tint (anxiety relief)
        motionBlur = 0.1,
        cameraShake = 0.05,
        steadyAim = true, -- Steady aim for 1 minute (integrates with sway script)
        duration = 60000, -- 1 minute of steady aim
        staminaRestore = { min = 2, max = 4 }, -- Relaxation reduces tension
        description = "Steady aim and minor stamina restore (+2-4) from reduced anxiety"
    },

    -- ========== CUSTOM / STREET EFFECTS ==========
    pinkcocaine_high = {
        screenEffect = "DrugsMichaelAliensFightIn",
        colorModifier = true,
        motionBlur = 0.2,
        cameraShake = 0.2,
        staminaRestore = { min = 2, max = 4 }, -- Realistic small stamina boost (stimulant)
        description = "Mild euphoria with slight stamina boost (+2-4)"
    },
    fetty_high = {
        screenEffect = "DrugsDrivingIn",
        colorModifier = "drug_deadman_blend",
        colorModifierStrength = 0.4,
        motionBlur = 0.3,
        cameraShake = 0.2,
        healthRestore = { min = 2, max = 4 }, -- Realistic small health boost (sedative pain relief)
        description = "Relaxed sedation with minor health restore (+2-4)"
    },
    gummies_high = {
        screenEffect = "DrugsMichaelAliensFight",
        colorModifier = true,
        motionBlur = 0.25,
        cameraShake = 0.1,
        armorRestore = { min = 2, max = 4 }, -- Realistic small armor boost (edible mellow)
        description = "Mellow edible high with slight armor restore (+2-4)"
    },
    fentanyl_high = {
        screenEffect = "DrugsDrivingIn",
        colorModifier = "drug_deadman_blend",
        colorModifierStrength = 0.5,
        motionBlur = 0.4,
        cameraShake = 0.15,
        healthRestore = { min = 2, max = 4 }, -- Realistic opioid pain relief
        staminaRestore = { min = 2, max = 4 }, -- Slight stamina from pain relief
        description = "Strong pain relief with minor health and stamina restore (+2-4 each)"
    }
}

-- ============================================
-- ADDICTION SYSTEM (IF ENABLED)
-- ============================================
Config.Addiction = {
    enabled = Config.EnableAddiction,
    withdrawalTime = 300000, -- 5 minutes
    withdrawalEffects = {
        screenEffect = "DeathFailOut",
        healthDrain = 1, -- HP per second
        staminaDrain = 10 -- Stamina per second
    }
}

-- ============================================
-- NPC PED & VEHICLE MODELS
-- ============================================
Config.JunkieVehicles = {
    "faggio",
    "blista",
    "dilettante",
    "ingot",
    "stanier",
    "stratum",
    "surge",
    "tailgater",
    "premier",
    "emperor"
}

Config.JunkiePeds = {
    "a_m_m_skidrow_01",
    "a_m_o_tramp_01",
    "a_f_m_tramp_01",
    "a_m_m_tramp_01",
    "a_m_m_tranvest_01",
    "a_f_m_tranvest_01",
    "a_m_m_bevhills_02",
    "a_m_y_roadcyc_01",
    "a_m_y_skater_01",
    "a_m_m_prolhost_01",
    "a_m_o_soucent_01",
    "a_m_o_soucent_02",
    "a_m_m_soucent_01",
    "a_m_m_soucent_02",
    "a_m_m_soucent_03",
    "a_f_m_soucentmc_01",
    "a_m_m_hillbilly_01",
    "a_m_m_hillbilly_02",
    "a_m_o_salton_01",
    "a_m_m_salton_01",
    "a_m_m_salton_02",
    "a_m_m_salton_03",
    "a_m_m_salton_04"
}

Config.DeclinePhrases = {
    "This shit laced!",
    "This shit ass!",
    "Man, I ain't feeling this!",
    "Not my style, bro.",
    "Pass, I'll pass."
}

-- ============================================
-- SELL ZONES (Where /dealer works)
-- ============================================
Config.SellZones = {
    { coords = vector3(-161.7769, -1154.9491, 23.5865), radius = 100.0 },
    { coords = vector3(-119.5655, -1283.9286, 29.2988), radius = 100.0 },
    { coords = vector3(-149.6186, -1305.4797, 29.2918), radius = 100.0 },
    { coords = vector3(-198.8233, -1305.4453, 29.5319), radius = 100.0 },
        { coords = vector3(381.4821, -763.8704, 29.2853), radius = 100.0 },
    { coords = vector3(1055.0809, -2245.5310, 30.3817), radius = 100.0 },
    { coords = vector3(-293.7414, -916.7805, 31.6600), radius = 100.0 },
    { coords = vector3(417.1766, -1530.8622, 29.3035), radius = 100.0 },
    { coords = vector3(936.9994, -1543.4521, 29.2470), radius = 100.0 },
    { coords = vector3(488.2662, -2255.1680, 14.7692), radius = 100.0 },
    { coords = vector3(-1082.1207, -980.3629, 2.1988), radius = 100.0 },
    { coords = vector3(-769.7955, -563.6756, 30.3088), radius = 100.0 },
    { coords = vector3(1088.9519, -607.5974, 61.2532), radius = 100.0 },
    { coords = vector3(1171.2482, -1361.6246, 35.2175), radius = 100.0 },
    { coords = vector3(478.3376, -1382.0044, 29.0429), radius = 100.0 },
    { coords = vector3(-1098.0593, -1546.8419, 4.5497), radius = 100.0 },
    { coords = vector3(706.7853, -1092.8668, 22.4005), radius = 100.0 },
    { coords = vector3(212.9627, -1548.1989, 30.9051), radius = 100.0 },
    { coords = vector3(-972.2261, -954.6251, 2.2540), radius = 100.0 },
    { coords = vector3(-240.1488, -1284.7954, 30.9283), radius = 100.0 },
    { coords = vector3(-202.7268, -1353.7091, 31.3038), radius = 100.0 },
    { coords = vector3(-179.5643, -1382.7080, 30.2254), radius = 100.0 },
    { coords = vector3(-81.9355, -1467.2742, 32.3413), radius = 100.0 },
    { coords = vector3(-52.5056, -1484.1693, 31.4792), radius = 100.0 },
    { coords = vector3(8.5404, -1523.6520, 29.7518), radius = 100.0 },
    { coords = vector3(-24.7371, -1583.1415, 29.2092), radius = 100.0 },
    { coords = vector3(23.4838, -1579.6122, 29.2929), radius = 100.0 },
    { coords = vector3(57.3811, -1601.7478, 29.1596), radius = 100.0 },
    { coords = vector3(86.6677, -1552.7280, 29.3026), radius = 100.0 },
    { coords = vector3(135.9297, -1554.2003, 29.2609), radius = 100.0 },
    { coords = vector3(105.5695, -1491.7347, 29.2971), radius = 100.0 },
    { coords = vector3(170.2240, -1452.7650, 29.2801), radius = 100.0 },
    { coords = vector3(202.9787, -1663.3571, 29.9490), radius = 100.0 },
    { coords = vector3(242.5190, -1696.8715, 29.2024), radius = 100.0 },
    { coords = vector3(24.4668, -1775.9480, 29.0041), radius = 100.0 },
    { coords = vector3(-31.8883, -1753.0719, 29.2192), radius = 100.0 },
    { coords = vector3(-73.1669, -1758.2903, 29.5052), radius = 100.0 },
    { coords = vector3(35.5708, -1873.0703, 22.6426), radius = 100.0 },
    { coords = vector3(439.1410, -1842.3333, 27.8549), radius = 100.0 },
    { coords = vector3(530.1953, -1957.9949, 25.1776), radius = 100.0 },
    { coords = vector3(468.8369, -1995.1016, 23.4392), radius = 100.0 },
    { coords = vector3(516.7228, -2348.0623, 12.9798), radius = 100.0 },
    { coords = vector3(542.3990, -2305.4851, 15.0364), radius = 100.0 },
    { coords = vector3(597.4532, -2271.0059, 19.9454), radius = 100.0 },
    { coords = vector3(852.2733, -2120.9968, 30.8561), radius = 100.0 },
    { coords = vector3(882.6677, -1938.1482, 31.3684), radius = 100.0 },
    { coords = vector3(890.2535, -1831.1409, 30.2274), radius = 100.0 },
    { coords = vector3(767.2567, -1933.2659, 29.2946), radius = 100.0 },
    { coords = vector3(724.1476, -1290.7419, 26.3755), radius = 100.0 },
    { coords = vector3(697.2894, -1104.8391, 22.6015), radius = 100.0 },
    { coords = vector3(-513.8922, -1704.1809, 21.1865), radius = 100.0 },
    { coords = vector3(-1106.3147, -1055.2993, 2.1143), radius = 100.0 },
    { coords = vector3(-292.1111, -416.6799, 30.0767), radius = 100.0 },
    { coords = vector3(-1147.8899, -1540.6362, 4.5337), radius = 100.0 },
}

-- ============================================
-- DROP-OFF LOCATIONS
-- ============================================
Config.DropOffLocations = {
    vector3(-252.6727, -300.8651, 30.3721),
    vector3(-457.6384, -400.9529, 34.0178),
    vector3(-484.1812, -397.7754, 34.5466),
    vector3(-631.4813, -302.3660, 35.3440),
    vector3(-820.9981, -253.6600, 37.0230),
    vector3(-928.8279, -8.5760, 43.5852),
    vector3(-695.4756, -2.5307, 38.2617),
    vector3(-598.7072, 146.3415, 61.3403),
    vector3(-42.2521, -14.9976, 69.5909),
    vector3(321.5264, -197.5694, 54.2264),
    vector3(638.5927, 255.2497, 103.1522),
    vector3(-18.4120, -1452.1897, 30.5906),
    vector3(-185.2045, -1700.5005, 32.7977),
    vector3(365.7918, -1983.3947, 24.1682),
    vector3(1236.3325, -1599.3916, 53.3681),
    vector3(1165.1655, -1287.2773, 35.3943),
    -- Additional city front-door spots
    vector3(-1040.56, -1025.34, 2.1500),   -- Vespucci beach apartments front
    vector3(-833.42, -862.71, 20.6880),    -- City apartment doorway
    vector3(312.45, -218.39, 54.2210),     -- Downtown front steps
    vector3(-10.12, -1441.55, 30.7410),    -- Strawberry front porch
    vector3(129.85, -1929.14, 21.3820),    -- Davis house front door
    vector3(-150.51, -1568.32, 34.2440),   -- Chamberlain front stairs
    -- Hills / Vinewood front-door spots
    vector3(-842.67, 465.21, 87.8180),     -- Vinewood Hills driveway door
    vector3(-884.13, 518.72, 92.4360),     -- Hillside villa entrance
    vector3(-1159.34, 376.85, 71.3180),    -- Rockford hillside home
    vector3(-1348.72, 567.10, 130.5220),   -- High-end hills mansion gate
    vector3(232.41, 672.19, 189.9740),     -- Vinewood Hills cul-de-sac house
    vector3(-595.18, 531.67, 107.7550)     -- Mid-hills front door
}
Config.DropOffMinQty = 1
Config.DropOffMaxQty = 6
