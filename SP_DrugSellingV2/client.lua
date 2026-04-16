-- ============================================
-- DRUG DEALING SYSTEM - CLIENT SIDE
-- ============================================

local function DebugPrint(...)
    if Config.Debug then print("[nbk_drug_dealer]", ...) end
end

local canInteract = false
local interactionPed = nil
local selling = false
local ped = nil
local blip = nil
local mode = nil
local currentDropoffDrug = nil
local currentDropoffCount = 0
local currentDropoffLoc = nil
local currentDropoffQty = 0
local dropoffPedSpawned = false
local dropoffUsed = {}
local activeDrugEffects = {}
local activeEffectThreads = {} -- Store effect threads so they can be stopped
local activeProgressHandlers = {} -- Store progress completion handlers
local craftingActive = false
local drugUseInProgress = false -- Prevents double-use / overlapping pill use

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

local function getUniqueDropoff()
    if #dropoffUsed >= #Config.DropOffLocations then
        dropoffUsed = {}
    end

    local available = {}
    for _, loc in ipairs(Config.DropOffLocations) do
        local used = false
        for _, u in ipairs(dropoffUsed) do
            if loc.x == u.x and loc.y == u.y and loc.z == u.z then
                used = true
                break
            end
        end
        if not used then
            table.insert(available, loc)
        end
    end

    local selected = available[math.random(#available)]
    table.insert(dropoffUsed, selected)
    return selected
end

-- Node types: 0 = asphalt only, 1 = simple path/asphalt (broader - includes addon roads), 2 = all roads, 8 = asphalt variant
local NODE_TYPE_PAVED_ROAD = 0
local NODE_TYPES_ADDON = { 1, 0, 2, 8 } -- Try multiple so addon/custom roads (MLO hoods, minimap) are found

-- Closest point on a major/drivable road (vanilla major nodes only)
local function getClosestMajorRoadPos(x, y, z)
    local out = nil
    pcall(function()
        local rx, ry, rz = GetClosestMajorVehicleNode(x, y, z + 5.0, 3.0, 0)
        if type(rx) == "number" and type(ry) == "number" and type(rz) == "number" then
            out = { rx, ry, rz }
        end
    end)
    if out and type(out[1]) == "number" and type(out[2]) == "number" and type(out[3]) == "number" then
        return vector3(out[1], out[2], out[3])
    end
    return nil
end

-- Scan for closest road node; try multiple node types so addon roads (custom MLO/minimap roads) are included
local function getClosestRoadPos(x, y, z, nodeType)
    local tryTypes = (nodeType == nil or nodeType == "all") and NODE_TYPES_ADDON or { nodeType or NODE_TYPE_PAVED_ROAD }
    for _, nType in ipairs(tryTypes) do
        local out = nil
        local ok = pcall(function()
            local rx, ry, rz = GetClosestVehicleNode(x, y, z + 5.0, nType, 3.0, 0)
            if type(rx) == "number" and type(ry) == "number" and type(rz) == "number" then
                out = { rx, ry, rz }
            end
        end)
        if ok and out and type(out[1]) == "number" and type(out[2]) == "number" and type(out[3]) == "number" then
            return vector3(out[1], out[2], out[3])
        end
    end
    local out = nil
    pcall(function()
        local rx, ry, rz = GetClosestVehicleNode(x, y, z + 5.0)
        if type(rx) == "number" and type(ry) == "number" and type(rz) == "number" then
            out = { rx, ry, rz }
        end
    end)
    if out and type(out[1]) == "number" then
        return vector3(out[1], out[2], out[3])
    end
    local _, gz = GetGroundZFor_3dCoord(x, y, z + 10.0, 0)
    return vector3(x, y, gz or z)
end

-- Force-load collision/nav at coords so MLO and addon road nodes are available when we query (custom hoods)
local function ensureCollisionLoadedAt(x, y, z)
    if type(RequestCollisionAtCoord) == "function" then
        pcall(RequestCollisionAtCoord, x, y, z)
    end
end


local function despawnPedAfter(pedEntity, delay)
    CreateThread(function()
        Wait(delay or 10000)
        if DoesEntityExist(pedEntity) then
            SetEntityAsMissionEntity(pedEntity, true, true)
            DeleteEntity(pedEntity)
        end
    end)
end

local function cornerDriveOffAndDespawn(pedEntity, vehEntity, flee, pedAlreadyInVeh)
    CreateThread(function()
        if not DoesEntityExist(pedEntity) or not DoesEntityExist(vehEntity) then return end
        SetBlockingOfNonTemporaryEvents(pedEntity, false)
        if not pedAlreadyInVeh then
            ClearPedTasksImmediately(pedEntity)
        end
        if flee then
            TaskSmartFleePed(pedEntity, PlayerPedId(), 80.0, -1)
            Wait(10000)
        else
            local inVeh = pedAlreadyInVeh or IsPedInVehicle(pedEntity, vehEntity, false)
            if not inVeh then
                TaskEnterVehicle(pedEntity, vehEntity, -1, -1, 2.0, 1, 0)
                local timeout = 0
                while not IsPedInVehicle(pedEntity, vehEntity, false) and timeout < 10000 do
                    Wait(200)
                    timeout = timeout + 200
                end
            end
            if IsPedInVehicle(pedEntity, vehEntity, false) then
                local vehPos = GetEntityCoords(vehEntity)
                local heading = GetEntityHeading(vehEntity)
                local rad = math.rad(heading)
                local awayX = vehPos.x - math.sin(rad) * 100.0
                local awayY = vehPos.y + math.cos(rad) * 100.0
                local _, awayZ = GetGroundZFor_3dCoord(awayX, awayY, vehPos.z + 50.0, 0)
                if not awayZ then awayZ = vehPos.z end
                local driveStyle = (Config.DriverlessDrivingStyle ~= nil) and Config.DriverlessDrivingStyle or 786603
                TaskVehicleDriveToCoordLongrange(pedEntity, vehEntity, awayX, awayY, awayZ, 22.0, driveStyle, 10.0)
                Wait(10000)
            end
        end
        Wait(1000)
        if DoesEntityExist(pedEntity) then
            SetEntityAsMissionEntity(pedEntity, true, true)
            DeleteEntity(pedEntity)
        end
        if DoesEntityExist(vehEntity) then
            SetEntityAsMissionEntity(vehEntity, true, true)
            DeleteEntity(vehEntity)
        end
    end)
end

local function resetSale()
    if DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        local currentPed = ped
        ped = nil
        despawnPedAfter(currentPed, 10000)
    end
    if blip then
        RemoveBlip(blip)
        blip = nil
    end
    selling = false
    canInteract = false
    interactionPed = nil
    lib.hideTextUI()
end

local function getDrugInfo(itemName)
    for _, drug in ipairs(Config.Drugs) do
        if drug.name == itemName then return drug end
    end
    return nil
end


-- ============================================
-- PED TARGET INTERACTION
-- ============================================

local function addPedTarget(pedEntity, drug, qty, vehicle)
    if not pedEntity or not DoesEntityExist(pedEntity) then
        DebugPrint("addPedTarget skipped (invalid ped)")
        return
    end
    exports.ox_target:addLocalEntity(pedEntity, {
        {
            name = 'drug_confirm_' .. pedEntity,
            label = 'Confirm Drop-Off',
            icon = 'hand-holding-usd',
            canInteract = function(entity)
                return selling and DoesEntityExist(entity)
            end,
            onSelect = function()
                local p = PlayerPedId()
                exports.ox_target:removeLocalEntity(pedEntity, 'drug_confirm_' .. pedEntity)
                if blip then RemoveBlip(blip) end

                RequestAnimDict("mp_common")
                while not HasAnimDictLoaded("mp_common") do Wait(10) end
                ClearPedTasksImmediately(p)
                TaskPlayAnim(p, "mp_common", "givetake2_a", 8.0, -8.0, -1, 48, 0, false, false, false)
                Wait(1800)
                ClearPedTasks(p)

                lib.progressCircle({
                    duration = 4000,
                    label = "Delivering product...",
                    disable = { move = true }
                })

                TriggerServerEvent("nbk_drug_dealer:completeDropOff", drug, qty)
                selling = false
                ped = nil
                currentDropoffDrug = nil
                currentDropoffCount = 0
                currentDropoffLoc = nil
                dropoffPedSpawned = false
                if DoesEntityExist(pedEntity) then
                    if vehicle and DoesEntityExist(vehicle) then
                        cornerDriveOffAndDespawn(pedEntity, vehicle, false)
                    else
                        TaskWanderStandard(pedEntity, 10.0, 10)
                        despawnPedAfter(pedEntity, 15000)
                    end
                end
            end
        }
    })
end

-- ============================================
-- /DEALER COMMAND
-- ============================================

RegisterCommand("wholesales", function()
    if selling then
        resetSale()
        if blip then RemoveBlip(blip) end
        lib.notify({ title = "Wholesales", description = "Cancelled drop-off.", type = "error" })
        return
    end

    -- Defer menu so it always opens (avoids UI/callback conflicts on busy servers)
    CreateThread(function()
        Wait(0)
        lib.registerContext({
            id = "wholesales_menu",
            title = "Wholesale Drop-Off",
            description = "Drive product to the meet spot and deliver",
            options = {
                { title = "Drop-Off Product", description = "Drive to meet point; exit car to deliver.", icon = "map-marker-alt", event = "nbk:selectMode", args = { m = "dropoff" } }
            }
        })
        lib.showContext("wholesales_menu")
    end)
end)

AddEventHandler("nbk:selectMode", function(data)
    mode = data.m
    lib.callback("nbk_drug_dealer:getPlayerDrugs", false, function(drugs)
        if #drugs == 0 then
            lib.notify({ title = "Dealer", description = "No drugs in inventory.", type = "error" })
            return
        end

        -- Filter to only show retail drugs (can be sold to NPC)
        local retailDrugs = {}
        for _, d in ipairs(drugs) do
            local drugInfo = getDrugInfo(d.name)
            if drugInfo and drugInfo.canSellToNPC then
                table.insert(retailDrugs, d)
            end
        end

        if #retailDrugs == 0 then
            lib.notify({ title = "Dealer", description = "You don't have any products to drop off. Bust down your wholesale items first.", type = "error" })
            return
        end

        local opts = {}
        for _, d in ipairs(retailDrugs) do
            table.insert(opts, {
                title = d.label .. " (" .. d.count .. "x)",
                description = "Tap to sell this product",
                icon = "capsules",
                event = "nbk:startSale",
                args = { drug = d.name, count = d.count }
            })
        end

        lib.registerContext({
            id = "drug_menu",
            title = "Select Product",
            description = "Choose what product you want to move",
            options = opts
        })
        lib.showContext("drug_menu")
    end)
end)

AddEventHandler("nbk:startSale", function(data)
    if not data.drug then return end

    local qty = math.random(Config.DropOffMinQty, Config.DropOffMaxQty)
    qty = math.min(qty, data.count)
    TriggerEvent("nbk:dropOffSale", { drug = data.drug, qty = qty, count = data.count })
end)

-- ============================================
-- DROP-OFF SALE
-- ============================================

AddEventHandler("nbk:dropOffSale", function(data)
    local drug = data.drug
    local qty = data.qty
    local p = PlayerPedId()

    if selling and (not currentDropoffDrug or currentDropoffDrug ~= drug) then
        selling = false
        dropoffPedSpawned = false
        if DoesEntityExist(ped) then
            exports.ox_target:removeLocalEntity(ped, 'drug_confirm_' .. ped)
            DeleteEntity(ped)
        end
        ped = nil
        canInteract = false
        interactionPed = nil
        lib.hideTextUI()
        if blip then RemoveBlip(blip) end
    end

    if not selling or not currentDropoffLoc then
        FreezeEntityPosition(p, true)
        RequestAnimDict("cellphone@")
        while not HasAnimDictLoaded("cellphone@") do Wait(10) end

        local phoneModel = GetHashKey("prop_v_m_phone_o1s")
        RequestModel(phoneModel)
        while not HasModelLoaded(phoneModel) do Wait(10) end

        local phone = CreateObject(phoneModel, 1.0, 1.0, 1.0, true, true, false)
        AttachEntityToEntity(phone, p, GetPedBoneIndex(p, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
        TaskPlayAnim(p, "cellphone@", "cellphone_text_read_base", 8.0, -1, -1, 49, 0, false, false, false)

        lib.progressCircle({ duration = 4000, label = "Finding serve...", disable = { move = true } })
        ClearPedTasks(p)
        DeleteEntity(phone)
        FreezeEntityPosition(p, false)

        local loc = getUniqueDropoff()
        if not loc or not loc.x then
            lib.notify({ title = "Drop-Off Error", description = "Drop-off location failed to load.", type = "error" })
            return
        end

        selling = true
        dropoffPedSpawned = false
        currentDropoffLoc = loc
        currentDropoffDrug = drug
        currentDropoffCount = data.count or qty
        currentDropoffQty = qty

        if blip then RemoveBlip(blip) end
        blip = AddBlipForCoord(loc.x, loc.y, loc.z)
        SetBlipSprite(blip, 94)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.9)
        SetBlipColour(blip, 5)
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, 5)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Drop-Off")
        EndTextCommandSetBlipName(blip)

        lib.notify({ title = "Drop-Off Product", description = "Drive to the location. Serve will be there when you arrive.", type = "inform" })

        -- Spawn ped when player arrives (within 30m)
        CreateThread(function()
            local pedModel = Config.JunkiePeds[math.random(#Config.JunkiePeds)]
            local pedHash = GetHashKey(pedModel)
            RequestModel(pedHash)
            while not HasModelLoaded(pedHash) do Wait(10) end

            while selling and currentDropoffLoc and currentDropoffDrug and not dropoffPedSpawned do
                Wait(500)
                local playerPos = GetEntityCoords(PlayerPedId())
                local dist = #(playerPos - currentDropoffLoc)
                if dist < 30.0 then
                    dropoffPedSpawned = true
                    local loc = currentDropoffLoc
                    -- Spawn on nearest major road (black road), not sidewalk (parking lots OK)
                    local roadPos = getClosestMajorRoadPos(loc.x, loc.y, loc.z)
                    if not roadPos then
                        roadPos = getClosestRoadPos(loc.x, loc.y, loc.z, NODE_TYPE_PAVED_ROAD)
                    end
                    local spawnX = roadPos.x
                    local spawnY = roadPos.y
                    local spawnZ = roadPos.z
                    ped = CreatePed(4, pedHash, spawnX, spawnY, spawnZ, 0.0, true, true)
                    if ped and ped ~= 0 then
                        SetEntityAsMissionEntity(ped, true, true)
                        SetBlockingOfNonTemporaryEvents(ped, true)
                        FreezeEntityPosition(ped, true)
                        TaskStandStill(ped, -1)
                        addPedTarget(ped, currentDropoffDrug, currentDropoffQty, nil)
                        lib.notify({ title = "Drop-Off", description = "Serve is here. Third-eye to complete the deal.", type = "success" })
                    end
                    break
                end
            end
        end)
    else
        currentDropoffDrug = drug
        currentDropoffCount = data.count or qty
        currentDropoffQty = qty
        if DoesEntityExist(ped) and dropoffPedSpawned then
            addPedTarget(ped, drug, qty, nil)
        end
    end
end)

RegisterNetEvent('nbk_drug_dealer:dropOffResult', function(success, remaining)
    currentDropoffDrug = nil
    currentDropoffCount = 0
    currentDropoffLoc = nil
    currentDropoffQty = 0
    dropoffPedSpawned = false
end)

-- ============================================
-- BUST-DOWN SYSTEM
-- ============================================

RegisterNetEvent('nbk_drug_dealer:bustDown', function(itemName, slot)
    local drugInfo = getDrugInfo(itemName)
    if not drugInfo then
        lib.notify({ title = "Bust Down", description = "Item not recognized.", type = "error" })
        return
    end

    -- Check if item can be bust down (either requiresBustDown OR has bustDownResult)
    if not drugInfo.requiresBustDown and not drugInfo.bustDownResult then
        lib.notify({ title = "Bust Down", description = "This item cannot be bust down.", type = "error" })
        return
    end

    -- Check if player has required item(s) (only if requiresBustDown is true)
    local requiredItems = drugInfo.bustDownItem
    if requiredItems and drugInfo.requiresBustDown then
        -- Handle both single item (string) and multiple items (table)
        local itemsToCheck = {}
        if type(requiredItems) == "table" then
            itemsToCheck = requiredItems
        else
            itemsToCheck = {requiredItems}
        end
        
        -- Check all required items
        local missingItems = {}
        local checkedCount = 0
        local totalItems = #itemsToCheck
        local allItemsPresent = false
        local checkComplete = false
        
        for i, requiredItem in ipairs(itemsToCheck) do
            lib.callback("nbk_drug_dealer:hasItem", false, function(hasItem)
                checkedCount = checkedCount + 1
                if not hasItem then
                    local itemLabel = requiredItem == "scale" and "Scale" or (requiredItem == "gloves" and "Gloves" or (requiredItem == "plasticbaggie" and "Plastic Baggie" or (requiredItem == "baby_bottle" and "Baby Bottle" or requiredItem)))
                    table.insert(missingItems, itemLabel)
                end
                
                if checkedCount == totalItems then
                    checkComplete = true
                    if #missingItems > 0 then
                        local missingText = table.concat(missingItems, " and ")
                        lib.notify({ title = "Bust Down", description = ("You need %s to bust down this item."):format(missingText), type = "error" })
                        return
                    end
                    allItemsPresent = true
                end
            end, requiredItem)
        end
        
        -- Wait for all callbacks to complete
        local waitCount = 0
        while not checkComplete and waitCount < 50 do
            Wait(100)
            waitCount = waitCount + 1
        end
        
            if not allItemsPresent or #missingItems > 0 then
                drugUseInProgress = false
                return
            end

        -- Load bust-down animation if available (for coke, promethazine)
        local p = PlayerPedId()
        if drugInfo.bustDownAnim and drugInfo.bustDownAnim.dict and drugInfo.bustDownAnim.clip then
            RequestAnimDict(drugInfo.bustDownAnim.dict)
            local animTimeout = 0
            while not HasAnimDictLoaded(drugInfo.bustDownAnim.dict) and animTimeout < 5000 do
                Wait(10)
                animTimeout = animTimeout + 10
            end
            
            if HasAnimDictLoaded(drugInfo.bustDownAnim.dict) then
                TaskPlayAnim(p, drugInfo.bustDownAnim.dict, drugInfo.bustDownAnim.clip, 8.0, -8.0, 5000, 0, 0, false, false, false)
            end
        end

        -- Determine progress label based on drug type
        local progressLabel = "Busting down product..."
        if drugInfo.type == "promethazine" and drugInfo.subtype then
            -- Promethazine pint: measuring deuce
            progressLabel = "Measuring deuce up be still"
        end

        -- Start bust down process (weed_pound: allow movement)
        local disableMove = (itemName ~= "weed_pound")
        lib.progressCircle({
            duration = 5000,
            label = progressLabel,
            disable = { move = disableMove }
        })
        
        -- Stop animation after progress
        if drugInfo.bustDownAnim and drugInfo.bustDownAnim.dict then
            ClearPedTasks(p)
        end

        TriggerServerEvent("nbk_drug_dealer:processBustDown", itemName, slot)
    else
        -- No tool required (like opening pill bottle or promethazine box)
        -- Pill bottles need 5 seconds, boxes need shorter time
        local progressDuration = 2000 -- Default 2 seconds for boxes
        if drugInfo.type == "pills" and drugInfo.subtype then
            -- Pill bottles: 5 seconds to open
            progressDuration = 5000
        end
        
        local progressLabel = "Opening product..."
        if drugInfo.type == "pills" and drugInfo.subtype then
            progressLabel = "Opening pill bottle..."
        elseif drugInfo.type == "promethazine" and drugInfo.subtype then
            -- Promethazine box: unpackaging pints
            progressLabel = "Unpackaging pints of promethazine"
        end
        
        -- Animation and progress: all pill bottles (xanax, percocet, painkiller) = same system: walk allowed, twitchy anim, 7 sec.
        local p = PlayerPedId()
        local isPillBottle = (drugInfo.type == "pills" and drugInfo.subtype)
        
        if isPillBottle then
            -- Pill bottle: no progress UI, anim with flag 48 (upper body only) so player can walk/run.
            if drugInfo.bustDownAnim and drugInfo.bustDownAnim.dict and drugInfo.bustDownAnim.clip then
                RequestAnimDict(drugInfo.bustDownAnim.dict)
                local animTimeout = 0
                while not HasAnimDictLoaded(drugInfo.bustDownAnim.dict) and animTimeout < 5000 do
                    Wait(10)
                    animTimeout = animTimeout + 10
                end
                if HasAnimDictLoaded(drugInfo.bustDownAnim.dict) then
                    CreateThread(function()
                        local ped = PlayerPedId()
                        -- Flag 48 = upper body only: anim plays on upper body, walk/run allowed
                        TaskPlayAnim(ped, drugInfo.bustDownAnim.dict, drugInfo.bustDownAnim.clip, 8.0, -8.0, -1, 48, 0.0, false, false, false)
                        -- Ensure movement isn't blocked by task
                        SetBlockingOfNonTemporaryEvents(ped, false)
                    end)
                end
            end
            lib.notify({ title = "Opening pill bottle...", description = "You can move around.", type = "inform", duration = 3000 })
            local start = GetGameTimer()
            while (GetGameTimer() - start) < progressDuration do
                Wait(500)
            end
            if drugInfo.bustDownAnim and drugInfo.bustDownAnim.dict then
                ClearPedTasks(p)
            end
            TriggerServerEvent("nbk_drug_dealer:processBustDown", itemName, slot)
            return
        end
        
        -- Others (e.g. promethazine box): use progress + single anim, movement disabled
        if drugInfo.bustDownAnim and drugInfo.bustDownAnim.dict and drugInfo.bustDownAnim.clip then
            RequestAnimDict(drugInfo.bustDownAnim.dict)
            local animTimeout = 0
            while not HasAnimDictLoaded(drugInfo.bustDownAnim.dict) and animTimeout < 5000 do
                Wait(10)
                animTimeout = animTimeout + 10
            end
            if HasAnimDictLoaded(drugInfo.bustDownAnim.dict) then
                TaskPlayAnim(p, drugInfo.bustDownAnim.dict, drugInfo.bustDownAnim.clip, 8.0, -8.0, progressDuration, 0, 0, false, false, false)
            end
        end
        
        lib.progressCircle({
            duration = progressDuration,
            label = progressLabel,
            disable = { move = true }
        })
        
        if drugInfo.bustDownAnim and drugInfo.bustDownAnim.dict then
            ClearPedTasks(p)
        end

        TriggerServerEvent("nbk_drug_dealer:processBustDown", itemName, slot)
    end
end)

-- ============================================
-- USABLE DRUG SYSTEM
-- ============================================

RegisterNetEvent('nbk_drug_dealer:useDrug', function(itemName, slot, metadata)
    if drugUseInProgress then
        lib.notify({ title = "Drug Use", description = "Already using an item. Wait for it to finish.", type = "inform" })
        return
    end
    local drugInfo = getDrugInfo(itemName)
    if not drugInfo or not drugInfo.canUse then
        lib.notify({ title = "Use Drug", description = "This item cannot be used.", type = "error" })
        return
    end
    drugUseInProgress = true

    -- Check if drug requires another item (like prometh needs cup, or weed needs backwood + lighter)
    if drugInfo.useRequires then
        -- If drug has useResult (like prometh), use processUse
        if drugInfo.useResult then
            -- Handle both single item (string) and multiple items (table)
            local requiredItems = {}
            if type(drugInfo.useRequires) == "table" then
                requiredItems = drugInfo.useRequires
            else
                requiredItems = {drugInfo.useRequires}
            end
            
            -- Check all required items sequentially
            local missingItems = {}
            local checkedCount = 0
            local totalItems = #requiredItems
            
            for i, requiredItem in ipairs(requiredItems) do
                lib.callback("nbk_drug_dealer:hasItem", false, function(hasItem)
                    checkedCount = checkedCount + 1
                    if not hasItem then
                        local itemLabel = requiredItem == "backwood" and "Backwood" or (requiredItem == "lighter" and "Lighter" or (requiredItem == "styrofoam_cup" and "Styrofoam Cup" or requiredItem))
                        table.insert(missingItems, itemLabel)
                    end
                    
                    -- When all items are checked, proceed
                    if checkedCount == totalItems then
                        if #missingItems > 0 then
                            local missingText = table.concat(missingItems, " and ")
                            lib.notify({ title = "Use Drug", description = ("You need %s to use this."):format(missingText), type = "error" })
                            drugUseInProgress = false
                            return
                        end
                        
                        -- All items present, process use
                        TriggerServerEvent("nbk_drug_dealer:processUse", itemName, slot, metadata, requiredItems)
                    end
                end, requiredItem)
            end
            
            drugUseInProgress = false
            return -- Wait for callbacks to complete
        end
        -- If no useResult (like weed), check items before proceeding
        if drugInfo.type == "weed" then
            local requiredItems = {}
            if type(drugInfo.useRequires) == "table" then
                requiredItems = drugInfo.useRequires
            else
                requiredItems = {drugInfo.useRequires}
            end
            
            -- Check all required items sequentially
            local missingItems = {}
            local checkedCount = 0
            local totalItems = #requiredItems
            local allItemsPresent = false
            local checkComplete = false
            
            for i, requiredItem in ipairs(requiredItems) do
                lib.callback("nbk_drug_dealer:hasItem", false, function(hasItem)
                    checkedCount = checkedCount + 1
                    if not hasItem then
                        local itemLabel = requiredItem == "backwood" and "Backwood" or (requiredItem == "lighter" and "Lighter" or requiredItem)
                        table.insert(missingItems, itemLabel)
                    end
                    
                    -- When all items are checked, proceed
                    if checkedCount == totalItems then
                        checkComplete = true
                        if #missingItems > 0 then
                            local missingText = table.concat(missingItems, " and ")
                            lib.notify({ title = "Use Drug", description = ("You need %s to use this."):format(missingText), type = "error" })
                            drugUseInProgress = false
                            return
                        end
                        allItemsPresent = true
                    end
                end, requiredItem)
            end
            
            -- Wait for all callbacks to complete
            local waitCount = 0
            while not checkComplete and waitCount < 50 do
                Wait(100)
                waitCount = waitCount + 1
            end
            
            -- Check if all items are present (only if check completed)
            if checkComplete then
                if not allItemsPresent or #missingItems > 0 then
                    drugUseInProgress = false
                    return
                end
            else
                if #missingItems > 0 then
                    local missingText = table.concat(missingItems, " and ")
                    lib.notify({ title = "Use Drug", description = ("You need %s to use this."):format(missingText), type = "error" })
                    drugUseInProgress = false
                    return
                end
            end
        end
    end

    -- Direct use (items without useRequires, e.g. prometh cups)
    local effect = drugInfo.useEffect
    if not effect then
        drugUseInProgress = false
        return
    end

        -- Load animation dictionary before starting
        if effect.animDict and effect.animClip then
            RequestAnimDict(effect.animDict)
            local animTimeout = 0
            while not HasAnimDictLoaded(effect.animDict) and animTimeout < 5000 do
                Wait(10)
                animTimeout = animTimeout + 10
            end
        end

        -- Pill timeline: 3s animation, 7s loading bar (completes 4s after anim), effect 6s after bar = 13s total
        local useDuration
        local effectKickInDelay = 0 -- seconds to wait after bar before effect (pills only)
        if drugInfo.type == "pills" and effect.animDuration then
            useDuration = 7000
            effectKickInDelay = 6000
        else
            useDuration = effect.duration and math.min(effect.duration, 10000) or 10000
        end
        local progressStartTime = GetGameTimer()
        local progressEndTime = progressStartTime + useDuration
        local useCancelled = false
        local p = PlayerPedId()
        local drugUseProp = nil

        local function spawnUseProp()
            if not effect.useProp or type(effect.useProp) ~= "string" or effect.useProp == "" then return end
            local propModel = effect.useProp
            local model = joaat(propModel)
            RequestModel(model)
            local t = 0
            while not HasModelLoaded(model) and t < 5000 do Wait(10) t = t + 10 end
            -- Pill prop fallback: if single pill model doesn't load, use pill bottle so prop is visible
            if not HasModelLoaded(model) and (drugInfo.type == "pills" or (drugInfo.type == "street" and effect.animDict == "mp_suicide") or drugInfo.type == "weed" and effect.animDict == "mp_player_inteat@pnq") then
                propModel = "prop_cs_pill_bottle_01"
                model = joaat(propModel)
                RequestModel(model)
                t = 0
                while not HasModelLoaded(model) and t < 5000 do Wait(10) t = t + 10 end
            end
            if not HasModelLoaded(model) then return end
            p = PlayerPedId()
            local coords = GetEntityCoords(p)
            local fwd = GetEntityForwardVector(p)
            local prop = CreateObject(model, coords.x + fwd.x, coords.y + fwd.y, coords.z, false, false, false)
            Wait(0)
            if not DoesEntityExist(prop) then return end
            SetEntityCollision(prop, false, false)
            SetEntityVisible(prop, true)
            SetEntityAlpha(prop, 255)
            local boneIndex = GetPedBoneIndex(p, 28422)
            local ox, oy, oz = 0.12, 0.0, 0.0
            local rx, ry, rz = -100.0, 0.0, 0.0
            if effect.usePropOffset and type(effect.usePropOffset) == "table" and #effect.usePropOffset >= 3 then
                ox, oy, oz = effect.usePropOffset[1], effect.usePropOffset[2], effect.usePropOffset[3]
            end
            if effect.usePropRot and type(effect.usePropRot) == "table" and #effect.usePropRot >= 3 then
                rx, ry, rz = effect.usePropRot[1], effect.usePropRot[2], effect.usePropRot[3]
            end
            AttachEntityToEntity(prop, p, boneIndex, ox, oy, oz, rx, ry, rz, true, true, false, true, 1, true)
            drugUseProp = prop
        end

        local function deleteUseProp()
            if drugUseProp and DoesEntityExist(drugUseProp) then
                DeleteEntity(drugUseProp)
                drugUseProp = nil
            end
        end
        
        -- Start animation 2 seconds after progress bar starts (for weed and cocaine)
        if (drugInfo.type == "weed" or drugInfo.type == "cocaine") and effect.animDict and effect.animClip then
            -- Ensure animation dictionary is loaded
            if not HasAnimDictLoaded(effect.animDict) then
                RequestAnimDict(effect.animDict)
                local animTimeout = 0
                while not HasAnimDictLoaded(effect.animDict) and animTimeout < 5000 do
                    Wait(10)
                    animTimeout = animTimeout + 10
                end
            end
            
            if HasAnimDictLoaded(effect.animDict) then
                CreateThread(function()
                    Wait(2000)
                    if not useCancelled then
                        p = PlayerPedId()
                        -- Start animation first so hand is moving, then spawn prop so it doesn't appear out of thin air
                        local animDuration = useDuration - 2000
                        TaskPlayAnim(p, effect.animDict, effect.animClip, 8.0, -8.0, animDuration, 48, 0, false, false, false)
                        local propDelay = (effect.usePropDelay and type(effect.usePropDelay) == "number") and effect.usePropDelay or 500
                        Wait(propDelay)
                        if not useCancelled then
                            p = PlayerPedId()
                            spawnUseProp()
                        end
                        SetPedCanRagdoll(p, true)
                        SetBlockingOfNonTemporaryEvents(p, false)
                        SetPedConfigFlag(p, 281, true)
                    end
                end)
            end
        elseif effect.animDict and effect.animClip and HasAnimDictLoaded(effect.animDict) then
            if drugInfo.type == "pills" and effect.animDuration then
                spawnUseProp()
                CreateThread(function()
                    local animLen = 3000 -- 3 second pill animation (bar continues 4s after = 7s total)
                    TaskPlayAnim(p, effect.animDict, effect.animClip, 8.0, -8.0, animLen, 49, 0, false, false, false)
                    Wait(animLen)
                    if DoesEntityExist(PlayerPedId()) then
                        ClearPedTasks(PlayerPedId()) -- Stop animation after pill is taken
                    end
                end)
            elseif drugInfo.type == "promethazine" or drugInfo.type == "street" then
                spawnUseProp()
                TaskPlayAnim(p, effect.animDict, effect.animClip, 8.0, -8.0, -1, 49, 0, false, false, false)
            else
                spawnUseProp()
                TaskPlayAnim(p, effect.animDict, effect.animClip, 8.0, -8.0, -1, 49, 0, false, false, false)
            end
        end
        
        -- No visible loading bar for drug use (realism). Same system as pill bottle: ox noti + timer only.
        local progressLabel = "Using " .. (drugInfo.label or itemName) .. "..."
        local progressComplete = false
        local progressCancelled = false
        
        lib.notify({ title = progressLabel, description = "You can move around.", type = "inform", duration = 3000 })
        CreateThread(function()
            local start = GetGameTimer()
            while (GetGameTimer() - start) < useDuration and not progressCancelled do
                Wait(200)
            end
            progressComplete = true
        end)
        
        -- Monitor for cancellation and animation
        CreateThread(function()
            while not progressComplete and GetGameTimer() < progressEndTime and not useCancelled do
                Wait(100)
                p = PlayerPedId()
                
                -- Check for X key press to cancel drug use
                if IsControlJustPressed(0, 73) then -- X key
                    useCancelled = true
                    progressCancelled = true
                    progressComplete = true
                    if drugUseProp and DoesEntityExist(drugUseProp) then DeleteEntity(drugUseProp) drugUseProp = nil end
                    ClearPedTasksImmediately(p)
                    ClearPedTasks(p)
                    lib.notify({ title = "Drug Use", description = "Drug use cancelled.", type = "error" })
                    break
                end
                
                -- Restart animation if it stopped (only for looping animations, and only during use)
                -- Note: Weed, cocaine, and pills (with animDuration) use one-shot animations - don't restart
                if effect.animDict and effect.animClip and drugInfo.type ~= "weed" and drugInfo.type ~= "cocaine" and not (drugInfo.type == "pills" and effect.animDuration) and not IsEntityPlayingAnim(p, effect.animDict, effect.animClip, 3) and not useCancelled then
                    if drugInfo.type == "promethazine" or drugInfo.type == "street" then
                        TaskPlayAnim(p, effect.animDict, effect.animClip, 8.0, -8.0, -1, 49, 0, false, false, false)
                    elseif drugInfo.type ~= "pills" then
                        TaskPlayAnim(p, effect.animDict, effect.animClip, 8.0, -8.0, -1, 49, 0, false, false, false)
                    end
                end
            end
        end)
        
        -- Wait for progress to complete
        while not progressComplete do
            Wait(100)
        end
        
        -- If progress was cancelled, set useCancelled flag
        if progressCancelled then
            useCancelled = true
        end
        
        -- Pills: effect kicks in 6 seconds after the loading bar completes (~13s total from start)
        if effectKickInDelay > 0 and not useCancelled then
            Wait(effectKickInDelay)
        end
        
        -- Remove prop and stop animation
        if drugUseProp and DoesEntityExist(drugUseProp) then DeleteEntity(drugUseProp) drugUseProp = nil end
        ClearPedTasks(PlayerPedId())
        
        if useCancelled then
            drugUseInProgress = false
            return
        end
        
        -- Apply restoration effects from Config.VisualEffects (generic - any drug with these in effect config)
        local effectConfig = effect and effect.visualEffect and Config.VisualEffects[effect.visualEffect]
        if effectConfig then
            local p = PlayerPedId()
            local effectTitle = drugInfo.label or itemName

            -- Helper: resolve min/max or single value
            local function resolveAmount(val)
                if type(val) == "table" and val.min and val.max then
                    return math.random(val.min, val.max)
                end
                return tonumber(val) or 0
            end

            -- Armor restore
            if effectConfig.armorRestore then
                local armorAmount = resolveAmount(effectConfig.armorRestore)
                if armorAmount > 0 then
                    local currentArmor = GetPedArmour(p)
                    local newArmor = math.min(100.0, currentArmor + armorAmount)
                    SetPedArmour(p, newArmor)
                    SetPedMaxHealth(p, GetEntityMaxHealth(p))
                    lib.notify({
                        title = effectTitle,
                        description = ("Restored %d armor (Total: %.0f/100)"):format(armorAmount, newArmor),
                        type = "success"
                    })
                end
            end

            -- Stamina restore
            if effectConfig.staminaRestore then
                local staminaAmount = resolveAmount(effectConfig.staminaRestore)
                if staminaAmount > 0 then
                    local currentStamina = GetPlayerStamina(PlayerId())
                    local newStamina = math.min(100.0, currentStamina + staminaAmount)
                    SetPlayerStamina(PlayerId(), newStamina)
                    lib.notify({
                        title = effectTitle,
                        description = ("Restored %d stamina (Total: %.0f/100)"):format(staminaAmount, newStamina),
                        type = "success"
                    })
                end
            end

            -- Health restore
            if effectConfig.healthRestore then
                local healthAmount = resolveAmount(effectConfig.healthRestore)
                if healthAmount > 0 then
                    local currentHealth = GetEntityHealth(p)
                    local maxHealth = GetEntityMaxHealth(p)
                    local newHealth = math.min(maxHealth, currentHealth + healthAmount)
                    SetEntityHealth(p, math.floor(newHealth))
                    SetPedMaxHealth(p, maxHealth)
                    lib.notify({
                        title = effectTitle,
                        description = ("Restored %d health (Total: %.0f/%d)"):format(healthAmount, newHealth, maxHealth),
                        type = "success"
                    })
                end
            end
        end
        
        -- Apply effects (item is consumed here) - only if not cancelled
        TriggerServerEvent("nbk_drug_dealer:consumeDrug", itemName, slot, metadata, effect)
        drugUseInProgress = false
end)


-- ============================================
-- VISUAL EFFECTS SYSTEM
-- ============================================

-- Function to stop all active drug effects
local function stopAllDrugEffects()
    -- Check if there are any active effects
    local hasEffects = false
    if #activeDrugEffects > 0 or next(activeEffectThreads) then
        hasEffects = true
    end
    
    if not hasEffects then
        DebugPrint("cleaneyes: no active effects")
        lib.notify({ title = "Drug Effects", description = "No active drug effects to disable.", type = "inform" })
        return
    end
    DebugPrint("cleaneyes: stopping", #activeDrugEffects, "effects")

    -- Stop all effect threads first - set active to false to break loops
    for effectId, threadData in pairs(activeEffectThreads) do
        if threadData then
            threadData.active = false
        end
    end
    
    -- Wait a frame to let threads exit
    Wait(100)
    
    -- Cleanup all effects immediately
    for _, effect in ipairs(activeDrugEffects) do
        if effect and effect.config then
            if effect.config.screenEffect then
                AnimpostfxStop(effect.config.screenEffect)
            end
        end
    end
    
    -- Final cleanup - reset all modifiers IMMEDIATELY
    AnimpostfxStop("DrugsMichaelAliensFight")
    AnimpostfxStop("DrugsMichaelAliensFightIn")
    AnimpostfxStop("DrugsDrivingIn")
    AnimpostfxStop("")
    ClearTimecycleModifier()
    StopGameplayCamShaking(true)
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    SetSwimMultiplierForPlayer(PlayerId(), 1.0)
    SetTimeScale(1.0)
    SetPlayerWeaponDefenseModifier(PlayerId(), 1.0) -- Reset weapon modifier (xanax steady aim)
    
    -- Force cleanup again after a short delay to ensure everything is reset
    CreateThread(function()
        Wait(200)
        ClearTimecycleModifier()
        StopGameplayCamShaking(true)
        SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
        SetSwimMultiplierForPlayer(PlayerId(), 1.0)
        SetTimeScale(1.0)
        SetPlayerWeaponDefenseModifier(PlayerId(), 1.0)
    end)
    
    -- Clear tables
    activeDrugEffects = {}
    activeEffectThreads = {}
    
    lib.notify({ title = "Drug Effects", description = "All drug effects have been disabled.", type = "success" })
    DebugPrint("cleaneyes: done")
end

RegisterNetEvent('nbk_drug_dealer:applyEffect', function(effectName, duration, metadata)
    local effectConfig = Config.VisualEffects[effectName]
    if not effectConfig then return end

    -- Notify when xanax steady aim activates (no visual effects, so user needs feedback)
    if effectName == "xanax_steady" then
        lib.notify({
            title = "Xanax",
            description = ("Steady aim active for %d min"):format(math.floor(duration / 60000)),
            type = "success"
        })
    end

    local effectId = #activeDrugEffects + 1
    activeDrugEffects[effectId] = {
        id = effectId, -- Store ID for lookup
        name = effectName,
        config = effectConfig,
        startTime = GetGameTimer(),
        duration = duration,
        metadata = metadata or {}
    }

    -- Create thread data to track and allow stopping
    local threadData = { active = true, effectId = effectId }
    activeEffectThreads[effectId] = threadData

    CreateThread(function()
        local startTime = GetGameTimer()
        local endTime = startTime + duration
        local fadeStartTime = endTime - 30000 -- Start fading 30 seconds before end (for weed)
        
        -- Screen blackout for promethazine (10 seconds after start, then every 15 seconds)
        if effectConfig.screenBlackout and effectConfig.screenBlackout > 0 then
            local blackoutDuration = effectConfig.screenBlackout * 1000 -- Convert to milliseconds (0.5 seconds)
            local firstBlackoutTime = startTime + 10000 -- First blackout at 10 seconds
            local blackoutInterval = 15000 -- Every 15 seconds after first blackout
            
            -- Create blackout effect thread
            CreateThread(function()
                local nextBlackoutTime = firstBlackoutTime
                
                while GetGameTimer() < endTime and threadData.active do
                    local currentTime = GetGameTimer()
                    
                    -- Check if it's time for a blackout
                    if currentTime >= nextBlackoutTime and currentTime < nextBlackoutTime + blackoutDuration then
                        -- Draw blackout
                        DrawRect(0.5, 0.5, 1.0, 1.0, 0, 0, 0, 255) -- Full screen black
                    elseif currentTime >= nextBlackoutTime + blackoutDuration then
                        -- Move to next blackout time
                        nextBlackoutTime = nextBlackoutTime + blackoutInterval
                    end
                    
                    Wait(0)
                end
            end)
        end

        while GetGameTimer() < endTime and threadData.active do
            Wait(0)
            
            -- Check if effect was cancelled - exit immediately
            if not threadData.active then
                break
            end
            
            local p = PlayerPedId()
            local currentTime = GetGameTimer()
            local elapsed = currentTime - startTime
            local remaining = endTime - currentTime
            
            -- Calculate fade strength (1.0 = full effect, 0.0 = no effect)
            local fadeStrength = 1.0
            if currentTime >= fadeStartTime and effectName == "weed_high" then
                -- Fade out over last 30 seconds for weed
                local fadeDuration = endTime - fadeStartTime
                local fadeElapsed = currentTime - fadeStartTime
                fadeStrength = 1.0 - (fadeElapsed / fadeDuration)
                fadeStrength = math.max(0.0, math.min(1.0, fadeStrength))
            end

            -- Only apply effects if still active
            if threadData.active then
                -- Screen effects (stronger for coke)
                if effectConfig.screenEffect then
                    if effectName == "coke_high" then
                        -- Play screen effect with higher intensity for coke
                        AnimpostfxPlay(effectConfig.screenEffect, 0, true)
                        -- Add additional screen effect for more intensity
                        AnimpostfxPlay("DrugsMichaelAliensFight", 0, true)
                    else
                        AnimpostfxPlay(effectConfig.screenEffect, 0, true)
                    end
                end

                -- Color modifier (with fade for weed, strong color flash for coke, purple/blue for prometh)
                if effectConfig.colorModifier then
                    if effectName == "weed_high" then
                        SetTimecycleModifier("drug_deadman_blend")
                        SetTimecycleModifierStrength(0.5 * fadeStrength)
                    elseif effectName == "coke_high" then
                        -- Strong color flash filter for coke
                        SetTimecycleModifier("drug_deadman")
                        SetTimecycleModifierStrength(1.0) -- Maximum strength for strong filter (visible)
                    elseif effectName == "prometh_high" then
                        -- Purple/blue tint filter for promethazine
                        local modifierName = type(effectConfig.colorModifier) == "string" and effectConfig.colorModifier or "drug_deadman_blend"
                        local modifierStrength = effectConfig.colorModifierStrength or 0.7
                        SetTimecycleModifier(modifierName)
                        SetTimecycleModifierStrength(modifierStrength * fadeStrength)
                    else
                        -- Generic: percocet_high, painkiller_high, street drugs, etc.
                        local modifierName = type(effectConfig.colorModifier) == "string" and effectConfig.colorModifier or "drug_deadman_blend"
                        local modifierStrength = effectConfig.colorModifierStrength or 0.5
                        SetTimecycleModifier(modifierName)
                        SetTimecycleModifierStrength(modifierStrength)
                    end
                end

                -- Motion blur (with fade for weed) - using timecycle modifier instead
                if effectConfig.motionBlur then
                    -- Motion blur is handled through timecycle modifier, no separate native needed
                    -- The blur effect comes from the screen effect and timecycle modifier
                end

                -- Camera shake (with fade for weed, strong vibration for coke)
                if effectConfig.cameraShake then
                    if effectName == "coke_high" then
                        -- Strong screen vibration for coke (constant, no fade)
                        ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", effectConfig.cameraShake)
                        -- Add additional shake for more intensity
                        ShakeGameplayCam("HAND_SHAKE", effectConfig.cameraShake * 0.5)
                    else
                        ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", effectConfig.cameraShake * fadeStrength)
                    end
                end

                -- Speed boost removed for coke - no speed boosting

                -- Stamina boost removed - cocaine now uses usage-based stamina (+2 per use)
                -- Stamina drains normally when running, not infinite
                -- The +2 stamina is applied once when the drug is consumed (handled in useDrug event)
                
                -- Armor restore is applied once when drug is consumed, not continuously

                -- Slow motion (prometh)
                if effectConfig.slowMotion then
                    local slowStrength = 1.0 - (1.0 - effectConfig.slowMotion) * fadeStrength
                    SetTimeScale(slowStrength)
                end
                
                -- Screen sway (prometh) - visual screen movement (more aggressive)
                if effectConfig.screenSway then
                    -- For promethazine we ONLY use camera shake, no forced heading/pitch,
                    -- so players can still look/aim freely and the camera won't get stuck.
                    if effectName == "prometh_high" then
                        -- More aggressive shake while effect is active
                        -- Apply shake more frequently and with higher intensity
                        if math.random() < 0.3 then -- 30% chance per frame (more frequent)
                            ShakeGameplayCam("HAND_SHAKE", effectConfig.cameraShake * 0.8) -- Higher intensity
                        end
                        -- Also apply a constant subtle shake for continuous effect
                        ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", effectConfig.cameraShake * 0.3)
                    else
                        -- Fallback for any other future effects using screenSway
                        ShakeGameplayCam("HAND_SHAKE", effectConfig.cameraShake * 0.2)
                    end
                end

                -- Steady aim (xanax) - reduces weapon sway
                if effectConfig.steadyAim then
                    -- Reduce weapon sway by setting a global variable that your sway script can check
                    -- Your sway script should check: GetResourceMetadata(GetCurrentResourceName(), 'xanax_steady', 0)
                    -- For now, we'll use a client-side variable that can be checked
                    SetPlayerWeaponDefenseModifier(PlayerId(), 0.5) -- Slight reduction in weapon movement
                    -- Note: This integrates with your sway script - check for activeDrugEffects with xanax_steady
                end
            end
        end

        -- Immediate cleanup when effect stops (whether cancelled or expired)
        -- Clean up immediately
        if effectConfig.screenEffect then
            AnimpostfxStop(effectConfig.screenEffect)
        end
        
        -- Only do fade-out if effect wasn't manually stopped and naturally expired
        if threadData.active and GetGameTimer() >= endTime then
            -- Cleanup - fade out completely
            local fadeOutTime = 2000 -- 2 seconds to fully fade out
            local fadeOutStart = GetGameTimer()
            local fadeOutEnd = fadeOutStart + fadeOutTime
            
            while GetGameTimer() < fadeOutEnd and threadData.active do
                Wait(0)
                local fadeProgress = (GetGameTimer() - fadeOutStart) / fadeOutTime
                fadeProgress = math.min(1.0, fadeProgress)
                local fadeStrength = 1.0 - fadeProgress
                
                if effectConfig.motionBlur then
                    -- Motion blur handled through timecycle modifier
                end
                if effectConfig.colorModifier then
                    SetTimecycleModifierStrength(0.5 * fadeStrength)
                end
                if effectConfig.cameraShake then
                    ShakeGameplayCam("SMALL_EXPLOSION_SHAKE", effectConfig.cameraShake * fadeStrength)
                end
                -- Speed boost removed for coke
                if effectConfig.slowMotion then
                    local slowStrength = 1.0 - (1.0 - effectConfig.slowMotion) * fadeStrength
                    SetTimeScale(slowStrength)
                end
                if effectConfig.screenSway then
                    -- Camera shake will naturally fade out, no need to reset pitch/heading
                    -- (we're not using pitch/heading manipulation anymore)
                end
            end
        end

        -- Final cleanup (only if thread is still active, otherwise stopAllDrugEffects already cleaned up)
        if threadData.active then
            if effectConfig.screenEffect then
                AnimpostfxStop(effectConfig.screenEffect)
            end
            
            -- Check if there are other active effects before clearing modifiers
            local otherEffectsActive = false
            for i, otherEffect in ipairs(activeDrugEffects) do
                if otherEffect and otherEffect.id and otherEffect.id ~= effectId then
                    local otherThread = activeEffectThreads[otherEffect.id]
                    if otherThread and otherThread.active then
                        otherEffectsActive = true
                        break
                    end
                end
            end
            
            -- Only clear modifiers if this is the last effect
            if not otherEffectsActive then
                ClearTimecycleModifier()
                SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
                SetSwimMultiplierForPlayer(PlayerId(), 1.0)
                SetTimeScale(1.0)
                SetPlayerWeaponDefenseModifier(PlayerId(), 1.0) -- Reset weapon modifier
                -- Camera shake will naturally stop, no need to reset pitch/heading
                -- (we're not using pitch/heading manipulation anymore to prevent camera stuck on floor)
            end
        end

        -- Remove from active effects using effectId
        for i, effect in ipairs(activeDrugEffects) do
            if effect and effect.id == effectId then
                table.remove(activeDrugEffects, i)
                break
            end
        end
        
        -- Remove from active threads
        activeEffectThreads[effectId] = nil
    end)
end)

-- ============================================
-- ARMOR MELEE PROTECTION (Custom Damage Handler)
-- ============================================

-- Make armor protect against melee damage - armor must be depleted before health takes damage
local lastHealth = 0
local lastArmor = 0
local damageCooldown = 0
local initialized = false

CreateThread(function()
    -- Initialize values after a delay
    Wait(2000)
    local p = PlayerPedId()
    if DoesEntityExist(p) then
        lastHealth = GetEntityHealth(p)
        lastArmor = GetPedArmour(p)
        initialized = true
    end
    
    while true do
        Wait(50) -- Check every 50ms
        local p = PlayerPedId()
        if not DoesEntityExist(p) then goto continue end
        
        local currentHealth = GetEntityHealth(p)
        local currentArmor = GetPedArmour(p)
        
        -- Update cooldown
        if damageCooldown > 0 then
            damageCooldown = damageCooldown - 1
        end
        
        -- Only process if initialized
        if initialized then
            -- Prevent passive armor decay: armor only goes down from melee/gun damage (health drop)
            if currentArmor < lastArmor and currentHealth >= lastHealth - 2 then
                SetPedArmour(p, lastArmor)
                currentArmor = lastArmor
                DebugPrint("Armor restored (passive decay blocked)", lastArmor)
            end
        end

        if initialized and damageCooldown == 0 then
            -- Check if player took health damage
            if currentHealth < lastHealth then
                local healthLost = lastHealth - currentHealth
                local armorLost = lastArmor - currentArmor
                
                -- If health decreased but armor didn't decrease much, it's likely melee damage
                -- Bullets reduce armor proportionally (usually close to 1:1)
                -- Melee damage doesn't reduce armor in GTA V by default
                if healthLost > 1 and armorLost < healthLost * 0.3 and lastArmor > 0 then
                    -- This is likely melee damage
                    -- Convert ALL health damage to armor damage first
                    local totalDamage = healthLost
                    
                    -- Restore health (armor will absorb it)
                    SetEntityHealth(p, lastHealth)
                    
                    -- Reduce armor by the damage amount (armor absorbs melee damage)
                    local newArmor = math.max(0.0, lastArmor - totalDamage)
                    SetPedArmour(p, newArmor)
                    
                    -- If armor is depleted and there's still damage, apply to health
                    if newArmor <= 0 and totalDamage > lastArmor then
                        local remainingDamage = totalDamage - lastArmor
                        local newHealth = math.max(0.0, currentHealth - remainingDamage)
                        SetEntityHealth(p, math.floor(newHealth))
                    end
                    
                    -- Set cooldown to prevent multiple triggers
                    damageCooldown = 3
                end
            end
        end
        
        -- Update tracking values
        lastHealth = GetEntityHealth(p)
        lastArmor = GetPedArmour(p)
        
        ::continue::
    end
end)

-- ============================================
-- EXPORT FOR SWAY SCRIPT (XANAX STEADY AIM)
-- ============================================

-- Export function for sway script to check if Xanax steady aim is active
exports('isXanaxSteadyActive', function()
    for _, effect in ipairs(activeDrugEffects) do
        if effect and effect.name == "xanax_steady" then
            local thread = activeEffectThreads[effect.id]
            if thread and thread.active then
                return true
            end
        end
    end
    return false
end)

-- ============================================
-- CLEAN EYES COMMAND (clear drug visual effects)
-- ============================================

RegisterCommand("cleaneyes", function()
    stopAllDrugEffects()
end, false)

-- ============================================
-- JOB-BASED CRAFTING (NUI AT COORDS)
-- ============================================
local isCraftingUIOpen = false
local currentCraftingData = nil
local craftingShowingTextUI = false
local lastCraftingEKey = 0
local craftingZoneCache = {} -- zoneName -> { canCraft = bool, at = gameTimer }
local CRAFTING_CACHE_MS = 1500

local function openCraftingMenu(zoneName, craftingData)
    if isCraftingUIOpen or not zoneName or not craftingData or not craftingData.items then return end
    isCraftingUIOpen = true
    currentCraftingData = craftingData
    local medications = {}
    for index, item in ipairs(craftingData.items) do
        medications[#medications + 1] = {
            index = index - 1,
            luaIndex = index,
            title = item.title,
            description = item.description or "",
            duration = item.duration or 12100,
            progressbar = item.progressbar or item.title,
            requireditems = item.requireditems or {},
            additems = item.additems or {}
        }
    end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "craftingOpen",
        medications = medications,
        craftingType = zoneName,
        label = craftingData.label or "Crafting"
    })
end

RegisterNUICallback("craftingCloseUI", function(_, cb)
    isCraftingUIOpen = false
    currentCraftingData = nil
    if craftingShowingTextUI then lib.hideTextUI() end
    craftingShowingTextUI = false
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("craftItem", function(data, cb)
    if not data or not data.craftingType or not data.item then cb({ success = false, error = "Invalid data" }) return end
    local craftingData = currentCraftingData or (Config.Craftings and Config.Craftings[data.craftingType])
    if not craftingData or not craftingData.items then cb({ success = false, error = "Crafting not found" }) return end
    local itemData = data.item
    local luaIndex = (itemData.luaIndex and type(itemData.luaIndex) == "number") and itemData.luaIndex or (itemData.index and type(itemData.index) == "number" and (itemData.index + 1))
    local originalItem = luaIndex and craftingData.items[luaIndex]
    if not originalItem then
        for idx, it in ipairs(craftingData.items) do
            if it.title == (itemData.title or "") then originalItem = it luaIndex = idx break end
        end
        if not originalItem then
            cb({ success = false, error = "Item not found" })
            return
        end
    end
    if not originalItem.additems then cb({ success = false, error = "Item not found" }) return end
    -- Send zone + 1-based index so server uses recipe from Config (fixes custom drug / glove give-take)
    if luaIndex and luaIndex >= 1 then
        TriggerServerEvent("nbk_drug_dealer:craftingGiveItems", data.craftingType, luaIndex)
    else
        TriggerServerEvent("nbk_drug_dealer:craftingGiveItems", data.craftingType, originalItem)
    end
    cb({ success = true })
end)

lib.callback.register("nbk_drug_dealer:craftingProgress", function(_, label, duration)
    SendNUIMessage({ action = "showLoading", text = label or "Crafting...", duration = duration or 12100 })
    local start = GetGameTimer()
    CreateThread(function()
        while GetGameTimer() - start < (duration or 12100) do
            Wait(50)
            local progress = math.min(((GetGameTimer() - start) / (duration or 12100)) * 100, 100)
            SendNUIMessage({ action = "updateProgress", progress = progress, text = label })
        end
        Wait(300)
        SendNUIMessage({ action = "hideLoading" })
    end)
    local result = lib.progressBar({
        duration = duration or 12100,
        label = label or "Crafting...",
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = { dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", clip = "machinic_loop_mechandplayer" },
    })
    return result
end)

CreateThread(function()
    if not Config.Craftings then return end
    Wait(2000)
    while true do
        local sleep = 500
        if not isCraftingUIOpen then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local now = GetGameTimer()
            local foundZone, foundData = nil, nil
            for name, craftingData in pairs(Config.Craftings) do
                if craftingData.coords then
                    for _, c in pairs(craftingData.coords) do
                        local x, y, z = c.x or c[1], c.y or c[2], c.z or c[3]
                        if x and y and z then
                            local dist = #(coords - vector3(x, y, z))
                            if dist < 2.5 then
                                local cache = craftingZoneCache[name]
                                if not cache or (now - cache.at) > CRAFTING_CACHE_MS then
                                    craftingZoneCache[name] = { canCraft = lib.callback.await("nbk_drug_dealer:canCraftAtZone", false, name), at = now }
                                end
                                if craftingZoneCache[name] and craftingZoneCache[name].canCraft then
                                    foundZone, foundData = name, craftingData
                                end
                                break
                            end
                        end
                    end
                end
            end
            if foundZone and foundData then
                sleep = 0
                if not craftingShowingTextUI then
                    lib.showTextUI("[E] Open crafting menu")
                    craftingShowingTextUI = true
                end
                if IsControlJustPressed(0, 38) and (now - lastCraftingEKey) > 200 then
                    lastCraftingEKey = now
                    lib.hideTextUI()
                    craftingShowingTextUI = false
                    openCraftingMenu(foundZone, foundData)
                end
            else
                if craftingShowingTextUI then lib.hideTextUI() craftingShowingTextUI = false end
            end
        else
            if craftingShowingTextUI then lib.hideTextUI() craftingShowingTextUI = false end
        end
        Wait(sleep)
    end
end)

-- Refresh zone access cache for all zones (for markers + E prompt)
CreateThread(function()
    if not Config.Craftings then return end
    while true do
        Wait(1500)
        local now = GetGameTimer()
        for name, _ in pairs(Config.Craftings) do
            craftingZoneCache[name] = { canCraft = lib.callback.await("nbk_drug_dealer:canCraftAtZone", false, name), at = now }
        end
    end
end)

-- Colored circle marker at crafting coords (visible when player has job / can craft at zone)
-- Draw every frame when in range so the marker doesn't flash
CreateThread(function()
    if not Config.Craftings then return end
    local markerDist = type(Config.CraftingMarkerDistance) == "number" and Config.CraftingMarkerDistance or 30.0
    local col = Config.CraftingMarkerColor or { r = 0, g = 200, b = 255, a = 120 }
    while true do
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local inRange = false
        for name, craftingData in pairs(Config.Craftings) do
            local cache = craftingZoneCache[name]
            if cache and cache.canCraft and craftingData.coords then
                for _, c in pairs(craftingData.coords) do
                    local x, y, z = c.x or c[1], c.y or c[2], (c.z or c[3]) - 0.99
                    if x and y and z then
                        local d = #(coords - vector3(x, y, z + 0.99))
                        if d <= markerDist then
                            inRange = true
                            DrawMarker(25, x, y, z + 0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.5, col.r or 0, col.g or 200, col.b or 255, col.a or 120)
                        end
                    end
                end
            end
        end
        Wait(inRange and 0 or 400)
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if isCraftingUIOpen then SetNuiFocus(false, false) end
    if craftingShowingTextUI then lib.hideTextUI() end
end)

-- ============================================
-- CRAFTING SYSTEM (PLUG RECIPES)
-- ============================================

RegisterNetEvent('nbk_drug_dealer:startCrafting', function(recipeIndex)
    if craftingActive then
        lib.notify({ title = "Crafting", description = "You are already crafting something.", type = "error" })
        return
    end

    local recipe = Config.CraftingRecipes[recipeIndex]
    if not recipe then return end

    craftingActive = true

    lib.progressCircle({
        duration = recipe.time or Config.CraftingTime,
        label = "Crafting " .. (recipe.result.label or recipe.result.item) .. "...",
        disable = { move = true }
    })

    TriggerServerEvent("nbk_drug_dealer:completeCrafting", recipeIndex)
    
    craftingActive = false
end)

-- ============================================
-- ADDICTION SYSTEM
-- ============================================

if Config.EnableAddiction then
    CreateThread(function()
        while true do
            Wait(60000) -- Check every minute
            -- Addiction logic would go here
            -- This is a placeholder for the addiction system
        end
    end)
end

-- ============================================
-- OX_INVENTORY ITEM USE EXPORT
-- ============================================

-- Register export for ox_inventory (works with any resource name)
local function useItemHandler(data, slot)
    local itemName = data and data.name
    if not itemName or type(itemName) ~= "string" or itemName == "" then
        return
    end

    local drugInfo = getDrugInfo(itemName)
    if not drugInfo then
        return
    end

    -- Check if item requires bust down
    if drugInfo.requiresBustDown then
        TriggerEvent('nbk_drug_dealer:bustDown', itemName, slot)
        return
    end

    -- Check if item can be used
    if drugInfo.canUse then
        local metadata = data.metadata or {}
        -- Delay so inventory fully closes before use starts (fixes first-use not applying effects)
        CreateThread(function()
            Wait(350)
            TriggerEvent('nbk_drug_dealer:useDrug', itemName, slot, metadata)
        end)
        return
    end

    -- Check if item is a box that needs to be opened (like prometh box)
    if drugInfo.bustDownResult and not drugInfo.requiresBustDown then
        -- This is a box that opens directly (no tool needed)
        TriggerEvent('nbk_drug_dealer:bustDown', itemName, slot)
        return
    end
end

-- Items are registered via ESX.RegisterUsableItem on the server.
-- No ox_inventory export or client export required in items.lua.
RegisterNetEvent('nbk_drug_dealer:useItem')
AddEventHandler('nbk_drug_dealer:useItem', function(itemName)
    useItemHandler({ name = itemName, metadata = {} }, nil)
end)
