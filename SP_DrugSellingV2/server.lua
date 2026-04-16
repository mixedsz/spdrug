-- ============================================
-- DRUG DEALING SYSTEM - SERVER SIDE
-- ============================================

local ESX = nil

-- TriggerEvent asks es_extended to call our callback with the ESX object.
-- Do NOT also use AddEventHandler here — doing so causes the AddEventHandler
-- to receive the callback *function* as obj (funcref), overwriting ESX.
TriggerEvent('esx:getSharedObject', function(obj)
    ESX = obj
    -- Register all drug items as usable via ESX
    for _, drug in ipairs(Config.Drugs) do
        local name = drug.name
        ESX.RegisterUsableItem(name, function(src)
            TriggerClientEvent('nbk_drug_dealer:useItem', src, name)
        end)
    end
end)

local function DebugPrint(...)
    if Config.Debug then print("[nbk_drug_dealer]", ...) end
end

local function GetPlayer(source)
    if not ESX then return nil end
    return ESX.GetPlayerFromId(source)
end

local function GetDrugInfo(itemName)
    for _, drug in ipairs(Config.Drugs) do
        if drug.name == itemName then return drug end
    end
    return nil
end

-- ============================================
-- CALLBACKS (called by client)
-- ============================================

-- Returns all drug items currently in the player's inventory
lib.callback.register('nbk_drug_dealer:getPlayerDrugs', function(source)
    local drugs = {}
    for _, drugInfo in ipairs(Config.Drugs) do
        local count = exports.ox_inventory:Search(source, 'count', drugInfo.name) or 0
        if count > 0 then
            table.insert(drugs, {
                name  = drugInfo.name,
                label = drugInfo.label,
                count = count,
            })
        end
    end
    return drugs
end)

-- Returns whether the player has at least one of the given item
lib.callback.register('nbk_drug_dealer:hasItem', function(source, itemName)
    local count = exports.ox_inventory:Search(source, 'count', itemName) or 0
    return count > 0
end)

-- Returns whether the player's job allows crafting at the given zone
lib.callback.register('nbk_drug_dealer:canCraftAtZone', function(source, zoneName)
    local xPlayer = GetPlayer(source)
    if not xPlayer then return false end

    local craftingData = Config.Craftings and Config.Craftings[zoneName]
    if not craftingData or not craftingData.jobs then return false end

    local job   = xPlayer.job.name
    local grade = xPlayer.job.grade

    if craftingData.jobs[job] ~= nil then
        return grade >= craftingData.jobs[job]
    end
    return false
end)

-- ============================================
-- DROP-OFF SYSTEM
-- ============================================

RegisterNetEvent('nbk_drug_dealer:completeDropOff', function(itemName, qty)
    local src     = source
    local xPlayer = GetPlayer(src)
    if not xPlayer then return end

    local drugInfo = GetDrugInfo(itemName)
    if not drugInfo then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Drop-Off', description = 'Unknown item.', type = 'error' })
        return
    end

    local have = exports.ox_inventory:Search(src, 'count', itemName) or 0
    if have < qty then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Drop-Off', description = 'Not enough ' .. drugInfo.label .. '.', type = 'error' })
        return
    end

    local removed = exports.ox_inventory:RemoveItem(src, itemName, qty)
    if not removed then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Drop-Off', description = 'Could not remove item.', type = 'error' })
        return
    end

    local priceEach = math.random(drugInfo.minPrice, drugInfo.maxPrice)
    local total     = priceEach * qty

    if Config.PaymentType == 'money' then
        xPlayer.addMoney(total)
    elseif Config.PaymentType == 'bank' then
        xPlayer.addAccountMoney('bank', total)
    elseif Config.PaymentType == 'black_money' then
        xPlayer.addAccountMoney('black_money', total)
    else
        -- PaymentType is an item name
        exports.ox_inventory:AddItem(src, Config.PaymentType, total)
    end

    DebugPrint(("DropOff: src=%d item=%s qty=%d pay=$%d"):format(src, itemName, qty, total))

    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Drop-Off',
        description = ('Dropped off %dx %s — received $%d.'):format(qty, drugInfo.label, total),
        type        = 'success',
    })

    TriggerClientEvent('nbk_drug_dealer:dropOffResult', src, true, 0)
end)

-- ============================================
-- BUST-DOWN SYSTEM
-- ============================================

RegisterNetEvent('nbk_drug_dealer:processBustDown', function(itemName, slot)
    local src     = source
    local xPlayer = GetPlayer(src)
    if not xPlayer then return end

    local drugInfo = GetDrugInfo(itemName)
    if not drugInfo or not drugInfo.bustDownResult then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Bust Down', description = 'Invalid item.', type = 'error' })
        return
    end

    local have = exports.ox_inventory:Search(src, 'count', itemName) or 0
    if have < 1 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Bust Down', description = 'You do not have that item.', type = 'error' })
        return
    end

    -- Grab metadata from the specific slot (preserves strain/quality)
    local slotData = slot and exports.ox_inventory:GetSlot(src, slot)
    local metadata = (slotData and slotData.metadata) or {}

    -- Remove the wholesale item
    exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slot)

    -- Remove required tool(s) when bust-down requires one
    if drugInfo.bustDownItem and drugInfo.requiresBustDown then
        local tools = type(drugInfo.bustDownItem) == 'table' and drugInfo.bustDownItem or { drugInfo.bustDownItem }
        for _, tool in ipairs(tools) do
            exports.ox_inventory:RemoveItem(src, tool, 1)
        end
    end

    -- Give bust-down result items
    local result     = drugInfo.bustDownResult
    local resultMeta = result.preserveMetadata and metadata or {}

    exports.ox_inventory:AddItem(src, result.item, result.count, resultMeta)

    -- Leave empty container if defined (e.g. empty pill bottle)
    if result.leavesItem then
        exports.ox_inventory:AddItem(src, result.leavesItem, 1)
    end

    DebugPrint(("BustDown: src=%d %s -> %dx %s"):format(src, itemName, result.count, result.item))

    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Bust Down',
        description = ('Got %dx %s.'):format(result.count, result.item),
        type        = 'success',
    })
end)

-- ============================================
-- DRUG USE / CONSUMPTION
-- ============================================

-- Called after the player finishes the use animation; removes item and applies effect.
RegisterNetEvent('nbk_drug_dealer:consumeDrug', function(itemName, slot, metadata, effect)
    local src     = source
    local xPlayer = GetPlayer(src)
    if not xPlayer then return end

    local drugInfo = GetDrugInfo(itemName)
    if not drugInfo then return end

    local have = exports.ox_inventory:Search(src, 'count', itemName) or 0
    if have < 1 then return end

    -- Remove the drug
    exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slot)

    -- Remove consumables that the drug requires (backwood + lighter, etc.)
    if drugInfo.useRequires then
        local required = type(drugInfo.useRequires) == 'table' and drugInfo.useRequires or { drugInfo.useRequires }
        for _, reqItem in ipairs(required) do
            exports.ox_inventory:RemoveItem(src, reqItem, 1)
        end
    end

    -- Fire the visual effect on the client
    if effect and effect.visualEffect then
        local duration = (type(effect.duration) == 'number') and effect.duration or 120000
        TriggerClientEvent('nbk_drug_dealer:applyEffect', src, effect.visualEffect, duration, metadata)
    end

    DebugPrint(("ConsumeDrug: src=%d item=%s"):format(src, itemName))
end)

-- Called when a drug needs a secondary item to prepare (e.g. prometh pint + styrofoam cup).
-- Removes both, gives the prepared result item, and does NOT apply a visual effect
-- (the result item e.g. prometh_cup triggers its own effect when consumed).
RegisterNetEvent('nbk_drug_dealer:processUse', function(itemName, slot, metadata, requiredItems)
    local src     = source
    local xPlayer = GetPlayer(src)
    if not xPlayer then return end

    local drugInfo = GetDrugInfo(itemName)
    if not drugInfo then return end

    local have = exports.ox_inventory:Search(src, 'count', itemName) or 0
    if have < 1 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Use Drug', description = 'You do not have that item.', type = 'error' })
        return
    end

    -- Remove required secondary items
    if requiredItems then
        for _, reqItem in ipairs(requiredItems) do
            exports.ox_inventory:RemoveItem(src, reqItem, 1)
        end
    end

    -- Remove the drug itself
    exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slot)

    -- Give the result item (e.g. poured cup)
    if drugInfo.useResult then
        local resultMeta = {}
        if drugInfo.subtype then resultMeta.subtype = drugInfo.subtype end
        exports.ox_inventory:AddItem(src, drugInfo.useResult.item, drugInfo.useResult.count or 1, resultMeta)
        TriggerClientEvent('ox_lib:notify', src, {
            title       = drugInfo.label,
            description = 'Ready.',
            type        = 'success',
        })
    end

    DebugPrint(("ProcessUse: src=%d item=%s"):format(src, itemName))
end)

-- ============================================
-- DISPATCH
-- ============================================

RegisterNetEvent('nbk_drug_dealer:sendDispatch', function(coords, code, message, blipLabel)
    -- Generic dispatch bridge — wire to your server's dispatch resource here.
    TriggerEvent('dispatch:server:createDispatchCall', {
        coords    = coords,
        type      = code,
        message   = message,
        blipSprite = 51,
        blipColor  = 1,
        blipScale  = 1.2,
        blipLength = 5,
        blipLabel  = blipLabel or code,
        jobs       = { 'police', 'sheriff' },
    })
end)

-- ============================================
-- JOB-BASED CRAFTING (NUI TABLE)
-- ============================================

RegisterNetEvent('nbk_drug_dealer:craftingGiveItems', function(zoneName, itemIndexOrData)
    local src     = source
    local xPlayer = GetPlayer(src)
    if not xPlayer then return end

    local craftingData = Config.Craftings and Config.Craftings[zoneName]
    if not craftingData then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Crafting', description = 'Invalid crafting zone.', type = 'error' })
        return
    end

    -- Job / access check
    local canCraft  = false
    local job       = xPlayer.job.name
    local grade     = xPlayer.job.grade
    if craftingData.jobs and craftingData.jobs[job] ~= nil then
        canCraft = grade >= craftingData.jobs[job]
    end
    if not canCraft then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Crafting', description = 'You do not have the required job.', type = 'error' })
        return
    end

    -- Resolve which recipe to use
    local recipe = nil
    if type(itemIndexOrData) == 'number' then
        recipe = craftingData.items[itemIndexOrData]
    elseif type(itemIndexOrData) == 'table' then
        for _, it in ipairs(craftingData.items) do
            if it.title == (itemIndexOrData.title or '') then
                recipe = it
                break
            end
        end
    end

    if not recipe then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Crafting', description = 'Recipe not found.', type = 'error' })
        return
    end

    -- Verify required items
    if recipe.requireditems then
        for _, req in ipairs(recipe.requireditems) do
            local have = exports.ox_inventory:Search(src, 'count', req.name) or 0
            if have < req.amount then
                TriggerClientEvent('ox_lib:notify', src, {
                    title       = 'Crafting',
                    description = ('Missing: %dx %s.'):format(req.amount, req.name),
                    type        = 'error',
                })
                return
            end
        end
    end

    -- Deduct required items
    if recipe.requireditems then
        for _, req in ipairs(recipe.requireditems) do
            exports.ox_inventory:RemoveItem(src, req.name, req.amount)
        end
    end

    -- Await the client-side crafting progress bar; returns true on completion, false/nil on cancel
    local ok = lib.callback.await('nbk_drug_dealer:craftingProgress', src, recipe.progressbar or recipe.title, recipe.duration or 12100)

    if not ok then
        -- Cancelled — refund items
        if recipe.requireditems then
            for _, req in ipairs(recipe.requireditems) do
                exports.ox_inventory:AddItem(src, req.name, req.amount)
            end
        end
        TriggerClientEvent('ox_lib:notify', src, { title = 'Crafting', description = 'Crafting cancelled.', type = 'error' })
        return
    end

    -- Give crafted output
    if recipe.additems then
        for _, addItem in ipairs(recipe.additems) do
            exports.ox_inventory:AddItem(src, addItem.name, addItem.amount)
        end
    end

    DebugPrint(("Craft: src=%d zone=%s recipe=%s"):format(src, zoneName, recipe.title or '?'))

    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Crafting',
        description = 'Crafted successfully!',
        type        = 'success',
    })
end)

-- ============================================
-- PLUG CRAFTING RECIPES
-- ============================================

RegisterNetEvent('nbk_drug_dealer:completeCrafting', function(recipeIndex)
    local src     = source
    local xPlayer = GetPlayer(src)
    if not xPlayer then return end

    local recipe = Config.CraftingRecipes and Config.CraftingRecipes[recipeIndex]
    if not recipe then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Crafting', description = 'Invalid recipe.', type = 'error' })
        return
    end

    -- Job check
    if recipe.job and xPlayer.job.name ~= recipe.job then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Crafting', description = 'You need the ' .. recipe.job .. ' job.', type = 'error' })
        return
    end

    -- Verify all ingredients are present
    for _, ingredient in ipairs(recipe.ingredients) do
        local have = exports.ox_inventory:Search(src, 'count', ingredient.item) or 0
        if have < ingredient.count then
            TriggerClientEvent('ox_lib:notify', src, {
                title       = 'Crafting',
                description = ('Missing: %dx %s.'):format(ingredient.count, ingredient.item),
                type        = 'error',
            })
            return
        end
    end

    -- Deduct ingredients
    for _, ingredient in ipairs(recipe.ingredients) do
        exports.ox_inventory:RemoveItem(src, ingredient.item, ingredient.count)
    end

    -- Give result
    local result     = recipe.result
    local resultMeta = result.metadata or {}
    exports.ox_inventory:AddItem(src, result.item, result.count or 1, resultMeta)

    DebugPrint(("PlugCraft: src=%d recipe=%d -> %s"):format(src, recipeIndex, result.item))

    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Crafting',
        description = ('Crafted %s!'):format(result.item),
        type        = 'success',
    })
end)
