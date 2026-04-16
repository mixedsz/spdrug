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
local cornerVeh = nil
local cornerBlip = nil
local blip = nil
local mode = nil
local currentDropoffDrug = nil
local currentDropoffCount = 0
local currentDropoffLoc = nil
local currentDropoffQty = 0
local dropoffPedSpawned = false
local dropoffUsed = {}
local pendingSaleContext = nil -- { mode, ped, veh, drug, qty } for saleResult cleanup
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

-- Get a spawn position on paved street (taxi-style) with heading. nodeType 0 = asphalt only.
local function getStreetNodeWithHeading(x, y, z, nodeType)
    nodeType = nodeType or NODE_TYPE_PAVED_ROAD
    local ok, out = pcall(function()
        local a, b, c, d, e = GetClosestVehicleNodeWithHeading(x, y, z + 5.0, nodeType, 3.0, 0)
        local nx, ny, nz, roadHeading
        if type(a) == "number" and type(b) == "number" and type(c) == "number" then
            nx, ny, nz, roadHeading = a, b, c, (type(d) == "number" and d or 0.0)
        elseif type(b) == "number" and type(c) == "number" and type(d) == "number" then
            nx, ny, nz, roadHeading = b, c, d, (type(e) == "number" and e or 0.0)
        else
            return nil
        end
        return { nx, ny, nz, roadHeading }
    end)
    if ok and out and type(out[1]) == "number" and type(out[2]) == "number" and type(out[3]) == "number" then
        return out[1], out[2], out[3], out[4] or 0.0
    end
    return nil
end

-- True if point is on road (helps avoid sidewalk/grass). Vehicle param ignored by native.
local function isPointOnRoad(x, y, z)
    return IsPointOnRoad(x, y, z, 0) == 1
end

-- Pull-over spot: 8–12m from dealer so they stop on the road well before the curb/sidewalk
local MIN_PULLOVER_DIST = 8.0
local MAX_PULLOVER_DIST = 12.0

-- Force-load collision/nav at coords so MLO and addon road nodes are available when we query (custom hoods)
local function ensureCollisionLoadedAt(x, y, z)
    if type(RequestCollisionAtCoord) == "function" then
        pcall(RequestCollisionAtCoord, x, y, z)
    end
end

-- Optional: use chicago_gps_nodes road/node coords for spawn, dest, and pathfinding (custom Chicago hoods)
local function HasChicagoGpsNodes()
    return GetResourceState("chicago_gps_nodes") == "started"
end

-- Block work: spawn/dest on road when possible. Tries CLOSE range first (better for MLO/custom maps).
-- Destination is ALONG the approach path so they drive toward player.
local function getStreetSpawnAndDest(playerCoords, _playerHeading)
    local spawnPos = nil
    local spawnHeadingOut = 0.0
    local playerHead = _playerHeading or 0.0
    local closeMin = (type(Config.BlockWorkSpawnCloseMin) == "number") and Config.BlockWorkSpawnCloseMin or 80.0
    local closeMax = (type(Config.BlockWorkSpawnCloseMax) == "number") and Config.BlockWorkSpawnCloseMax or 220.0
    local farMin = (type(Config.BlockWorkSpawnFarMin) == "number") and Config.BlockWorkSpawnFarMin or 350.0
    local farMax = (type(Config.BlockWorkSpawnFarMax) == "number") and Config.BlockWorkSpawnFarMax or 550.0

    -- Request collision around player and sample points so MLO/addon road nodes stream in before we search
    ensureCollisionLoadedAt(playerCoords.x, playerCoords.y, playerCoords.z)
    for _, deg in ipairs({ 0, 120, 240 }) do
        local a = math.rad(deg + (playerHead or 0))
        local d = (closeMin + closeMax) * 0.5
        ensureCollisionLoadedAt(playerCoords.x + math.cos(a) * d, playerCoords.y + math.sin(a) * d, playerCoords.z)
    end
    Wait(200)

    -- Prefer chicago_gps_nodes mapping when available so peds use custom hood road coords/connections
    if HasChicagoGpsNodes() then
        local ok, nodesInRadius = pcall(function()
            return exports.chicago_gps_nodes:GetRoadNodesInRadius(playerCoords.x, playerCoords.y, playerCoords.z, closeMax)
        end)
        if ok and nodesInRadius and #nodesInRadius > 0 then
            local playerForward = vector3(math.cos(math.rad(playerHead)), math.sin(math.rad(playerHead)), 0)
            local bestNode = nil
            local bestScore = -1.0
            for _, entry in ipairs(nodesInRadius) do
                local dist = entry.distance or #(entry.coords - playerCoords)
                if dist >= closeMin and dist <= closeMax and entry.coords then
                    local toNode = (entry.coords - playerCoords)
                    local len = #toNode
                    if len < 0.1 then toNode = playerForward len = 1.0 end
                    toNode = toNode / len
                    local dot = toNode.x * playerForward.x + toNode.y * playerForward.y
                    local score = dot + (1.0 - math.abs(dist - (closeMin + closeMax) * 0.5) / closeMax) * 0.3
                    if score > bestScore then bestScore = score bestNode = entry end
                end
            end
            if bestNode and bestNode.coords then
                spawnPos = type(bestNode.coords) == "vector3" and bestNode.coords or vector3(bestNode.coords.x, bestNode.coords.y, bestNode.coords.z)
                local dirToPlayer = (playerCoords - spawnPos)
                local dlen = #dirToPlayer
                if dlen < 1.0 then dlen = 1.0 end
                dirToPlayer = dirToPlayer / dlen
                spawnHeadingOut = math.deg(math.atan2(dirToPlayer.x, dirToPlayer.y)) % 360.0
                local pullOverDist = MIN_PULLOVER_DIST + (MAX_PULLOVER_DIST - MIN_PULLOVER_DIST) * math.random()
                local destGuess = playerCoords - (dirToPlayer * pullOverDist)
                local dOk, _, __, destCoords = pcall(function()
                    return exports.chicago_gps_nodes:GetNearestRoadNode(destGuess.x, destGuess.y, destGuess.z)
                end)
                if dOk and destCoords then
                    local destVec = type(destCoords) == "vector3" and destCoords or vector3(destCoords.x, destCoords.y, destCoords.z)
                    local spawnToDest = #(destVec - spawnPos)
                    local spawnToPlayer = #(playerCoords - spawnPos)
                    if spawnToDest >= 15.0 and spawnToDest <= spawnToPlayer * 1.1 then
                        return spawnPos, destVec, spawnHeadingOut
                    end
                    destVec = spawnPos + (playerCoords - spawnPos) * math.min(1.0, (spawnToPlayer > 1 and (15.0 / spawnToPlayer) or 1.0))
                    local _, gz = GetGroundZFor_3dCoord(destVec.x, destVec.y, destVec.z + 10.0, 0)
                    if gz then destVec = vector3(destVec.x, destVec.y, gz) end
                    return spawnPos, destVec, spawnHeadingOut
                end
            end
        end
    end

    local function trySpawnAtRange(minDist, maxDist)
        local cornerAngles = { 75, 90, 105, -75, -90, -105, 60, 120, -60, -120 }
        for _, deg in ipairs(cornerAngles) do
            local angle = math.rad(playerHead + deg)
            local dist = minDist + (maxDist - minDist) * math.random()
            local gx = playerCoords.x + math.cos(angle) * dist
            local gy = playerCoords.y + math.sin(angle) * dist
            local _, gz = GetGroundZFor_3dCoord(gx, gy, playerCoords.z + 30.0, 0)
            if not gz then gz = playerCoords.z end
            ensureCollisionLoadedAt(gx, gy, gz)
            -- Prefer addon-aware scan (types 1,0,2,8) so custom/minimap roads are used
            local majorPos = getClosestRoadPos(gx, gy, gz, "all")
            if not majorPos then majorPos = getClosestMajorRoadPos(gx, gy, gz) end
            if majorPos then
                local nodeVec = type(majorPos) == "table" and vector3(majorPos.x, majorPos.y, majorPos.z) or majorPos
                if isPointOnRoad(nodeVec.x, nodeVec.y, nodeVec.z) and #(nodeVec - playerCoords) >= (minDist * 0.5) then
                    local _, _, _, h = getStreetNodeWithHeading(nodeVec.x, nodeVec.y, nodeVec.z, NODE_TYPE_PAVED_ROAD)
                    return nodeVec, (h and type(h) == "number") and h or nil
                end
            end
        end
        for _ = 1, 6 do
            local angle = math.rad(math.random(0, 360))
            local dist = minDist + (maxDist - minDist) * math.random()
            local gx = playerCoords.x + math.cos(angle) * dist
            local gy = playerCoords.y + math.sin(angle) * dist
            local _, gz = GetGroundZFor_3dCoord(gx, gy, playerCoords.z + 30.0, 0)
            if not gz then gz = playerCoords.z end
            ensureCollisionLoadedAt(gx, gy, gz)
            local majorPos = getClosestRoadPos(gx, gy, gz, "all") or getClosestMajorRoadPos(gx, gy, gz)
            if majorPos then
                local nodeVec = type(majorPos) == "table" and vector3(majorPos.x, majorPos.y, majorPos.z) or majorPos
                if isPointOnRoad(nodeVec.x, nodeVec.y, nodeVec.z) and #(nodeVec - playerCoords) >= (minDist * 0.5) then
                    local _, _, _, h = getStreetNodeWithHeading(nodeVec.x, nodeVec.y, nodeVec.z, NODE_TYPE_PAVED_ROAD)
                    return nodeVec, (h and type(h) == "number") and h or nil
                end
            end
        end
        return nil, nil
    end

    -- 1) Try CLOSE range first (shorter drive = more reliable with MLO/custom roads)
    local gotPos, gotHead = trySpawnAtRange(closeMin, closeMax)
    if gotPos then
        spawnPos = gotPos
        spawnHeadingOut = (gotHead and type(gotHead) == "number") and gotHead or ((playerHead + 180.0) % 360.0)
    end
    -- 2) Try FAR range if close failed
    if not spawnPos then
        gotPos, gotHead = trySpawnAtRange(farMin, farMax)
        if gotPos then
            spawnPos = gotPos
            spawnHeadingOut = (gotHead and type(gotHead) == "number") and gotHead or (math.random(0, 360) % 360.0)
        end
    end
    -- 3) Last resort: ground coords (no road node) so ped always spawns
    if not spawnPos then
        local angle = math.rad(math.random(0, 360))
        local dist = closeMax + 50.0
        local gx = playerCoords.x + math.cos(angle) * dist
        local gy = playerCoords.y + math.sin(angle) * dist
        local _, gz = GetGroundZFor_3dCoord(gx, gy, playerCoords.z + 30.0, 0)
        if not gz then gz = playerCoords.z end
        spawnPos = getClosestRoadPos(gx, gy, gz, "all") or getClosestMajorRoadPos(gx, gy, gz)
        if not spawnPos then spawnPos = vector3(gx, gy, gz) end
        local sx, sy, sz = spawnPos.x or gx, spawnPos.y or gy, spawnPos.z or gz
        local _, _, _, h = getStreetNodeWithHeading(sx, sy, sz, NODE_TYPE_PAVED_ROAD)
        spawnHeadingOut = (h and type(h) == "number") and h or (math.random(0, 360) % 360.0)
    end

    -- Destination: along the approach path (spawn -> player) so no U-turn; at curb on road, not sidewalk
    local dirToPlayer = (playerCoords - spawnPos)
    local distToPlayer = #dirToPlayer
    if distToPlayer < 1.0 then distToPlayer = 1.0 end
    dirToPlayer = dirToPlayer / distToPlayer
    local pullOverDist = MIN_PULLOVER_DIST + (MAX_PULLOVER_DIST - MIN_PULLOVER_DIST) * math.random()
    local destGuess = playerCoords - (dirToPlayer * pullOverDist)
    local destVec = getClosestRoadPos(destGuess.x, destGuess.y, destGuess.z, "all")
    if not destVec then
        destVec = getClosestMajorRoadPos(destGuess.x, destGuess.y, destGuess.z)
    end
    if not destVec then
        destVec = getClosestRoadPos(playerCoords.x, playerCoords.y, playerCoords.z, "all") or getClosestMajorRoadPos(playerCoords.x, playerCoords.y, playerCoords.z)
    end
    destVec = (type(destVec) == "table") and vector3(destVec[1] or destVec.x, destVec[2] or destVec.y, destVec[3] or destVec.z) or destVec
    if not destVec then destVec = vector3(playerCoords.x, playerCoords.y, playerCoords.z) end
    if not isPointOnRoad(destVec.x, destVec.y, destVec.z) then
        local fallback = getClosestRoadPos(playerCoords.x, playerCoords.y, playerCoords.z, "all") or getClosestMajorRoadPos(playerCoords.x, playerCoords.y, playerCoords.z)
        if fallback then destVec = fallback end
    end
    -- Ensure dest is between spawn and player so the drive path is valid (avoid same spot / behind spawn)
    local spawnToDest = #(destVec - spawnPos)
    local spawnToPlayer = #(playerCoords - spawnPos)
    if spawnToDest < 15.0 or spawnToDest > spawnToPlayer * 1.1 then
        destVec = spawnPos + (playerCoords - spawnPos) * (math.min(1.0, (spawnToPlayer > 1 and (15.0 / spawnToPlayer) or 1.0)))
        local _, gz = GetGroundZFor_3dCoord(destVec.x, destVec.y, destVec.z + 10.0, 0)
        if gz then destVec = vector3(destVec.x, destVec.y, gz) end
    end

    return spawnPos, destVec, spawnHeadingOut
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
        -- When curb-serving, ped must stay in car: do NOT clear tasks (clearing can eject them)
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
        cornerVeh = nil
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
    if cornerBlip then
        RemoveBlip(cornerBlip)
        cornerBlip = nil
    end
    if cornerVeh and DoesEntityExist(cornerVeh) then
        exports.ox_target:removeLocalEntity(cornerVeh, 'blockwork_window_' .. cornerVeh)
        SetEntityAsMissionEntity(cornerVeh, true, true)
        DeleteEntity(cornerVeh)
        cornerVeh = nil
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

local function inSellZone()
    if not Config.SellZones or type(Config.SellZones) ~= "table" then return false end
    local pos = GetEntityCoords(PlayerPedId())
    for _, z in ipairs(Config.SellZones) do
        if z and z.radius then
            local zc = z.coords
            local v = type(zc) == "vector3" and zc or (type(zc) == "table" and vector3(zc.x or zc[1] or 0, zc.y or zc[2] or 0, zc.z or zc[3] or 0))
            if v and #(pos - v) <= (tonumber(z.radius) or 100.0) then return true end
        end
    end
    return false
end

-- ============================================
-- WINDOW POSITION CALCULATION (TRAFFIC SALE)
-- ============================================

local function getWindowPosition(veh, seatIndex)
    -- Simplified positioning - use fixed offsets that work for most GTA vehicles
    -- Position ped RIGHT UP AGAINST the car with forearms on roof/window
    local offsetX, offsetY, offsetZ = 0.0, 0.0, 0.0
    
    -- Seat indices: -1 = driver, 0 = passenger, 1 = rear left, 2 = rear right
    -- Position ped RIGHT UP AGAINST car - NO GAP - forearms on roof/window
    -- X: -0.3 to 0.3 = ped body touching car, forearms resting on roof
    -- Y: Fixed positions for each seat's window area
    -- Z: 0.4 = window height level
    if seatIndex == -1 then
        -- Driver seat - left side, front door window (forearms on car, no gap)
        offsetX, offsetY, offsetZ = -0.3, -0.4, 0.4
    elseif seatIndex == 0 then
        -- Passenger seat - right side, front door window (forearms on car, no gap)
        offsetX, offsetY, offsetZ = 0.3, -0.4, 0.4
    elseif seatIndex == 1 then
        -- Rear left seat - left side, back door window (forearms on car, no gap)
        offsetX, offsetY, offsetZ = -0.3, -0.8, 0.4
    elseif seatIndex == 2 then
        -- Rear right seat - right side, back door window (forearms on car, no gap)
        offsetX, offsetY, offsetZ = 0.3, -0.8, 0.4
    end
    
    return GetOffsetFromEntityInWorldCoords(veh, offsetX, offsetY, offsetZ)
end

-- ============================================
-- VEHICLE TARGET (BLOCK WORK – CURB SERVE VIA WINDOW)
-- ============================================
-- Ped stays in car; player must third-eye the front driver door to complete deal through window.
local function addVehicleTargetForBlockWork(veh, ped, drug, qty)
    exports.ox_target:addLocalEntity(veh, {
        {
            name = 'blockwork_window_' .. veh,
            label = 'Curb Serve (Driver Window)',
            icon = 'hand-holding-usd',
            canInteract = function(entity)
                if not selling or not DoesEntityExist(entity) or not DoesEntityExist(ped) then return false end
                local driverDoorPos = GetOffsetFromEntityInWorldCoords(entity, -0.9, 0.0, 0.4)
                local playerPos = GetEntityCoords(PlayerPedId())
                return #(playerPos - driverDoorPos) <= 2.0
            end,
            onSelect = function()
                local p = PlayerPedId()
                local coords = GetEntityCoords(p)
                exports.ox_target:removeLocalEntity(veh, 'blockwork_window_' .. veh)
                if blip then RemoveBlip(blip) end

                RequestAnimDict("mp_common")
                while not HasAnimDictLoaded("mp_common") do Wait(10) end
                ClearPedTasksImmediately(p)
                TaskPlayAnim(p, "mp_common", "givetake2_a", 8.0, -8.0, -1, 48, 0, false, false, false)
                Wait(1800)
                ClearPedTasks(p)

                lib.progressCircle({ duration = 4000, label = "Swapping product with cash...", disable = { move = true } })

                pendingSaleContext = { mode = "corner", ped = ped, veh = veh, drug = drug, qty = qty or 1 }
                TriggerServerEvent("nbk_drug_dealer:attemptSale", { type = drug, count = qty or 1, coords = coords })
            end
        }
    })
end

-- Server sends one result per attemptSale (percentage-based scam roll is server-side)
RegisterNetEvent('nbk_drug_dealer:saleResult', function(success, data)
    local ctx = pendingSaleContext
    pendingSaleContext = nil
    if not ctx then
        DebugPrint("saleResult ignored (no pending context)")
        return
    end
    DebugPrint("saleResult", success and "success" or "fail", ctx.mode, data and (data.declined and "declined" or data.scammed and "scammed" or data.reason) or "")

    if not success then
        if data and data.declined then
            lib.notify({ title = "Refused", description = Config.DeclinePhrases[math.random(#Config.DeclinePhrases)], type = "error" })
            if data.coords then
                TriggerServerEvent('nbk_drug_dealer:sendDispatch', data.coords, '10-71 - Drug Refusal', 'A junkie refused to buy from a local dealer.', '10-71 - Drug Refusal')
            end
        elseif data and data.scammed then
            lib.notify({ title = "Scammed!", description = "This shit mine!", type = "error" })
            if data.coords then
                TriggerServerEvent('nbk_drug_dealer:sendDispatch', data.coords, '10-71 - Drug Scam', 'A junkie scammed a local dealer.', '10-71 - Drug Scam')
            end
        end
        selling = false
        local p = ctx.ped
        local v = ctx.veh
        local flee = data and data.scammed
        if ctx.mode == "corner" and p and v and DoesEntityExist(p) and DoesEntityExist(v) then
            cornerDriveOffAndDespawn(p, v, flee, true)
        elseif ctx.mode == "ped" and p and DoesEntityExist(p) then
            if v and DoesEntityExist(v) then
                cornerDriveOffAndDespawn(p, v, flee)
            else
                if flee then TaskSmartFleePed(p, PlayerPedId(), 100.0, -1) else TaskWanderStandard(p, 10.0, 10) end
                despawnPedAfter(p, 15000)
            end
            currentDropoffDrug = nil
            currentDropoffCount = 0
            currentDropoffLoc = nil
            dropoffPedSpawned = false
        elseif ctx.mode == "seat" and p and DoesEntityExist(p) then
            if flee then
                TaskSmartFleePed(p, PlayerPedId(), 100.0, -1)
            else
                if v and DoesEntityExist(v) then TaskLeaveVehicle(p, v, 0) end
                TaskWanderStandard(p, 10.0, 10)
            end
            despawnPedAfter(p, 10000)
        end
        ped = nil
        return
    end

    selling = false
    local currentPed = ctx.ped
    ped = nil
    currentDropoffDrug = nil
    currentDropoffCount = 0
    currentDropoffLoc = nil
    dropoffPedSpawned = false
    if ctx.mode == "corner" and currentPed and ctx.veh and DoesEntityExist(currentPed) and DoesEntityExist(ctx.veh) then
        cornerDriveOffAndDespawn(currentPed, ctx.veh, false, true)
    elseif ctx.mode == "ped" and currentPed and DoesEntityExist(currentPed) then
        if mode == "traffic" and ctx.veh and DoesEntityExist(ctx.veh) then
            local vehCoords = GetEntityCoords(ctx.veh)
            local vehHeading = GetEntityHeading(ctx.veh)
            local rad = math.rad(vehHeading)
            local awayX = vehCoords.x - math.sin(rad) * 50.0
            local awayY = vehCoords.y + math.cos(rad) * 50.0
            local _, awayZ = GetGroundZFor_3dCoord(awayX, awayY, vehCoords.z, 0)
            if not awayZ then awayZ = vehCoords.z end
            TaskGoToCoordAnyMeans(currentPed, awayX, awayY, awayZ, 1.0, 0, 0, 786603, 0xbf800000)
            despawnPedAfter(currentPed, 15000)
        elseif ctx.veh and DoesEntityExist(ctx.veh) then
            cornerDriveOffAndDespawn(currentPed, ctx.veh, false)
        else
            TaskWanderStandard(currentPed, 10.0, 10)
            despawnPedAfter(currentPed, 15000)
        end
    elseif ctx.mode == "seat" and currentPed and ctx.veh and DoesEntityExist(currentPed) and DoesEntityExist(ctx.veh) then
        TaskLeaveVehicle(currentPed, ctx.veh, 0)
        Wait(1500)
        SetVehicleDoorsShut(ctx.veh, false)
        Wait(2000)
        TaskWanderStandard(currentPed, 10.0, 10)
        despawnPedAfter(currentPed, 10000)
    end
end)

-- ============================================
-- PED TARGET INTERACTION
-- ============================================

local function addPedTarget(pedEntity, drug, qty, mode, vehicle, windowCoords)
    if not pedEntity or not DoesEntityExist(pedEntity) then
        DebugPrint("addPedTarget skipped (invalid ped)")
        return
    end
    exports.ox_target:addLocalEntity(pedEntity, {
        {
            name = 'drug_confirm_' .. pedEntity,
            label = mode == 'dropoff' and 'Confirm Drop-Off' or (mode == 'traffic' and 'Make Deal' or 'Confirm Sale'),
            icon = 'hand-holding-usd',
            canInteract = function(entity)
                return selling and DoesEntityExist(entity)
            end,
            onSelect = function()
                local p = PlayerPedId()
                local coords = GetEntityCoords(p)
                exports.ox_target:removeLocalEntity(pedEntity, 'drug_confirm_' .. pedEntity)
                if blip then RemoveBlip(blip) end

                RequestAnimDict("mp_common")
                while not HasAnimDictLoaded("mp_common") do Wait(10) end
                ClearPedTasksImmediately(p)
                TaskPlayAnim(p, "mp_common", "givetake2_a", 8.0, -8.0, -1, 48, 0, false, false, false)
                Wait(1800)
                ClearPedTasks(p)

                -- Freeze ped during transaction if traffic mode
                if mode == 'traffic' and DoesEntityExist(pedEntity) then
                    FreezeEntityPosition(pedEntity, true)
                end

                lib.progressCircle({
                    duration = 4000,
                    label = mode == 'dropoff' and "Delivering product..." or "Swapping product with cash...",
                    disable = { move = true }
                })

                -- Unfreeze ped after transaction
                if mode == 'traffic' and DoesEntityExist(pedEntity) then
                    FreezeEntityPosition(pedEntity, false)
                end

                if mode == 'dropoff' then
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
                else
                    pendingSaleContext = { mode = "ped", ped = pedEntity, veh = vehicle, drug = drug, qty = qty or 1 }
                    TriggerServerEvent("nbk_drug_dealer:attemptSale", { type = drug, count = qty or 1, coords = coords })
                end
            end
        }
    })
end

-- ============================================
-- /DEALER COMMAND
-- ============================================

RegisterCommand("dealer", function()
    if not inSellZone() then
        lib.notify({ title = "Dealer", description = "No Junkie's around here! find somewhere else.", type = "error" })
        return
    end

    if selling then
        resetSale()
        if blip then RemoveBlip(blip) end
        lib.notify({ title = "Dealer", description = "Cancelled deal.", type = "error" })
        return
    end

    -- Defer menu so it always opens (avoids UI/callback conflicts on busy servers)
    CreateThread(function()
        Wait(0)
        lib.registerContext({
            id = "dealer_menu",
            title = "select a way to move your product",
            description = "Select your selling method",
            options = {
                { title = "Trap From Whip", description = "Sell from inside your car (any seat; NPC takes a free seat).", icon = "car", event = "nbk:selectMode", args = { m = "curb" } },
                { title = "Block Work", description = "Junkie runs up to you. Third-eye to complete deal.", icon = "walking", event = "nbk:selectMode", args = { m = "corner" } },
                { title = "Drop-Off Product", description = "Drive to meet point; exit car to deliver.", icon = "map-marker-alt", event = "nbk:selectMode", args = { m = "dropoff" } }
            }
        })
        lib.showContext("dealer_menu")
    end)
end)

AddEventHandler("nbk:selectMode", function(data)
    if data.m == "corner" and IsPedInAnyVehicle(PlayerPedId(), false) then
        lib.notify({ title = "Block Work", description = "Exit your vehicle to sell on foot.", type = "error" })
        return
    end

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
            lib.notify({ title = "Dealer", description = "You don't have any retail products to sell. Bust down your wholesale items first.", type = "error" })
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

    if mode == "curb" then
        TriggerEvent("nbk:curbSale", data.drug)
    elseif mode == "corner" then
        TriggerEvent("nbk:cornerSale", data.drug)
    elseif mode == "dropoff" then
        local qty = math.random(Config.DropOffMinQty, Config.DropOffMaxQty)
        qty = math.min(qty, data.count)
        TriggerEvent("nbk:dropOffSale", { drug = data.drug, qty = qty, count = data.count })
    end
end)

-- ============================================
-- TRAFFIC SALE (NEW - ANY SEAT)
-- ============================================

AddEventHandler("nbk:trafficSale", function(drug)
    local p = PlayerPedId()
    local veh = GetVehiclePedIsIn(p, false)
    
    if not veh or veh == 0 then
        lib.notify({ title = "Traffic Selling", description = "You must be in a vehicle.", type = "error" })
        return
    end

    -- Reset any existing sale
    if selling then
        resetSale()
        if blip then RemoveBlip(blip) end
    end

    -- Find which seat player is in
    local currentSeatIndex = nil
    for seat = -1, 2 do
        if GetPedInVehicleSeat(veh, seat) == p then
            currentSeatIndex = seat
            break
        end
    end

    if not currentSeatIndex then
        lib.notify({ title = "Traffic Selling", description = "Could not determine your seat.", type = "error" })
        return
    end

    Wait(100)

    lib.notify({ title = "Traffic Selling", description = "Serve is approaching, stay in vehicle.", type = "inform" })

    -- Calculate window position based on seat
    local windowCoords = getWindowPosition(veh, currentSeatIndex)
    local windowX, windowY, windowZ = windowCoords.x, windowCoords.y, windowCoords.z
    local _, windowGz = GetGroundZFor_3dCoord(windowX, windowY, windowZ, 0)
    if not windowGz then windowGz = windowZ end

    -- Spawn ped near the window (on the correct side of car)
    local vehCoords = GetEntityCoords(veh)
    local vehHeading = GetEntityHeading(veh)
    local spawnDistance = math.random(3, 8)
    local sideDistance = math.random(1, 2)
    
    local spawnOffsetX, spawnOffsetY = 0.0, 0.0
    if currentSeatIndex == -1 or currentSeatIndex == 1 then
        -- Left side - spawn on left
        spawnOffsetX = -sideDistance
    else
        -- Right side - spawn on right
        spawnOffsetX = sideDistance
    end
    
    local rad = math.rad(vehHeading)
    local spawnX = windowX + math.cos(rad) * spawnDistance + math.sin(rad) * spawnOffsetX
    local spawnY = windowY + math.sin(rad) * spawnDistance - math.cos(rad) * spawnOffsetX
    local spawnZ = windowGz
    
    local _, spawnGz = GetGroundZFor_3dCoord(spawnX, spawnY, spawnZ + 5.0, 0)
    if not spawnGz then spawnGz = spawnZ end

    -- Spawn ped
    local m = Config.JunkiePeds[math.random(#Config.JunkiePeds)]
    local pedHash = GetHashKey(m)
    RequestModel(pedHash)
    local modelTimeout = 0
    while not HasModelLoaded(pedHash) and modelTimeout < 5000 do
        Wait(10)
        modelTimeout = modelTimeout + 10
    end

    if not HasModelLoaded(pedHash) then
        lib.notify({ title = "Traffic Selling", description = "Failed to load ped model.", type = "error" })
        return
    end

    ped = CreatePed(4, pedHash, spawnX, spawnY, spawnGz, 0.0, true, true)
    
    if not ped or ped == 0 then
        -- Fallback: spawn near player and teleport
        ped = CreatePed(4, pedHash, vehCoords.x + 5.0, vehCoords.y + 5.0, vehCoords.z, 0.0, true, true)
        if ped and ped ~= 0 then
            SetEntityCoords(ped, spawnX, spawnY, spawnGz, false, false, false, true)
        end
    end

    if not ped or ped == 0 then
        lib.notify({ title = "Traffic Selling", description = "Failed to spawn buyer.", type = "error" })
        return
    end

    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 17, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedCanRagdoll(ped, false)
    SetEntityInvincible(ped, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedKeepTask(ped, true)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)

    -- Blip for window location
    blip = AddBlipForCoord(windowX, windowY, windowGz)
    SetBlipSprite(blip, 280)
    SetBlipColour(blip, 3)
    SetBlipRoute(blip, true)

    selling = true

    -- Make ped walk to window
    TaskGoToCoordAnyMeans(ped, windowX, windowY, windowGz, 1.0, 0, 0, 786603, 0xbf800000)

    CreateThread(function()
        local pedAtWindow = false
        while selling do
            Wait(500)
            
            if not DoesEntityExist(ped) or not DoesEntityExist(veh) or not IsPedInAnyVehicle(p, false) then
                if not IsPedInAnyVehicle(p, false) then
                    lib.notify({ title = 'Traffic Selling', description = 'You left the vehicle, deal canceled.', type = 'error' })
                end
                selling = false
                if DoesEntityExist(ped) then
                    local currentPed = ped
                    ped = nil
                    despawnPedAfter(currentPed, 10000)
                end
                if blip then RemoveBlip(blip) end
                return
            end

            local pedPos = GetEntityCoords(ped)
            local distanceToWindow = #(pedPos - vector3(windowX, windowY, windowGz))

            if not pedAtWindow and distanceToWindow < 2.0 then
                pedAtWindow = true
                RemoveBlip(blip)
                
                -- Snap ped to exact window position
                SetEntityCoords(ped, windowX, windowY, windowGz, false, false, false, true)
                
                -- Make ped face directly toward the car door - perpendicular to vehicle
                -- Body/chest should be squared up with the car, facing the door
                local vehHeading = GetEntityHeading(veh)
                local pedHeading
                
                if currentSeatIndex == -1 or currentSeatIndex == 1 then
                    -- Driver side or rear left - ped on left side, faces right (90° from vehicle heading)
                    -- This makes ped face directly toward the car door
                    pedHeading = (vehHeading + 90.0) % 360.0
                else
                    -- Passenger side or rear right - ped on right side, faces left (270° or -90° from vehicle heading)
                    -- This makes ped face directly toward the car door
                    pedHeading = (vehHeading - 90.0) % 360.0
                end
                
                SetEntityHeading(ped, pedHeading)
                Wait(100)
                
                -- Play the correct animation - ensure it loops
                RequestAnimDict("anim@amb@yacht@rail@standing@female@variant_01@")
                local animTimeout = 0
                while not HasAnimDictLoaded("anim@amb@yacht@rail@standing@female@variant_01@") and animTimeout < 3000 do
                    Wait(10)
                    animTimeout = animTimeout + 10
                end
                
                if HasAnimDictLoaded("anim@amb@yacht@rail@standing@female@variant_01@") then
                    TaskPlayAnim(ped, "anim@amb@yacht@rail@standing@female@variant_01@", "base", 8.0, -8.0, -1, 1, 0, false, false, false)
                end
                
                -- Add target interaction with vehicle and window coords
                addPedTarget(ped, drug, 1, "traffic", veh, vector3(windowX, windowY, windowGz))
            elseif not pedAtWindow then
                -- Keep ped moving to window
                TaskGoToCoordAnyMeans(ped, windowX, windowY, windowGz, 1.0, 0, 0, 786603, 0xbf800000)
            end
        end
    end)
end)

-- ============================================
-- CURB SALE (TRAP FROM WHIP – ANY SEAT, NPC TAKES OPEN PASSENGER SEAT)
-- ============================================

AddEventHandler("nbk:curbSale", function(drug)
    local p = PlayerPedId()
    local veh = GetVehiclePedIsIn(p, false)
    if not veh or veh == 0 then
        lib.notify({ title = "Trap From Whip", description = "You must be in a vehicle.", type = "error" })
        return
    end

    -- Require at least one free passenger seat so NPC can get in
    local freeSeats = {}
    for _, seat in ipairs({ 0, 1, 2 }) do
        if IsVehicleSeatFree(veh, seat) then
            freeSeats[#freeSeats + 1] = seat
        end
    end
    if #freeSeats == 0 then
        lib.notify({ title = "Trap From Whip", description = "No free passenger seat for a serve.", type = "error" })
        return
    end

    lib.notify({ title = "Trap From Whip", description = "Serve is approaching, stay in vehicle.", type = "inform" })

    -- Spawn and path from VEHICLE position/heading so it works from any seat (driver or passenger)
    local vCoords = GetEntityCoords(veh)
    local vHeading = GetEntityHeading(veh)
    local rad = math.rad(vHeading)
    local dist = 15.0 + math.random() * 25.0
    local spawnX = vCoords.x - math.sin(rad) * dist
    local spawnY = vCoords.y + math.cos(rad) * dist
    local _, gz = GetGroundZFor_3dCoord(spawnX, spawnY, vCoords.z + 5.0, 0)
    if not gz then gz = vCoords.z end

    -- Target: spot in front of vehicle so ped runs to car, then enters (works for any player seat)
    local approachDist = 4.0
    local approachX = vCoords.x - math.sin(rad) * approachDist
    local approachY = vCoords.y + math.cos(rad) * approachDist
    local _, approachGz = GetGroundZFor_3dCoord(approachX, approachY, vCoords.z + 2.0, 0)
    if not approachGz then approachGz = vCoords.z end

    ensureCollisionLoadedAt(spawnX, spawnY, gz)
    ensureCollisionLoadedAt(approachX, approachY, approachGz)
    Wait(100)

    local m = Config.JunkiePeds[math.random(#Config.JunkiePeds)]
    local pedHash = GetHashKey(m)
    RequestModel(pedHash)
    local modelTimeout = 0
    while not HasModelLoaded(pedHash) and modelTimeout < 5000 do Wait(10) modelTimeout = modelTimeout + 10 end
    if not HasModelLoaded(pedHash) then
        lib.notify({ title = "Trap From Whip", description = "Failed to load buyer model.", type = "error" })
        return
    end

    ped = CreatePed(4, pedHash, spawnX, spawnY, gz, 0.0, true, true)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        DebugPrint("Trap from whip ped spawn failed", ped)
        lib.notify({ title = "Trap From Whip", description = "Failed to spawn buyer.", type = "error" })
        return
    end
    DebugPrint("Trap from whip ped spawned", ped)
    ClearPedTasksImmediately(ped)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetEntityAsMissionEntity(ped, true, true)
    -- Run to spot in front of vehicle so pathfinding works from any seat
    TaskGoToCoordAnyMeans(ped, approachX, approachY, approachGz, 2.0, 0, 0, 786603, 0xbf800000)

    blip = AddBlipForCoord(approachX, approachY, approachGz)
    SetBlipSprite(blip, 280)
    SetBlipColour(blip, 3)
    SetBlipRoute(blip, true)

    selling = true
    local entered = false
    local lastEnterAttempt = 0
    local lastGotoTime = 0

    CreateThread(function()
        while selling do
            Wait(400)
            if not DoesEntityExist(ped) or not DoesEntityExist(veh) then
                selling = false
                if DoesEntityExist(ped) then despawnPedAfter(ped, 10000) end
                ped = nil
                if blip then RemoveBlip(blip) blip = nil end
                return
            end
            if not IsPedInAnyVehicle(p, false) then
                lib.notify({ title = "Trap From Whip", description = "You left the vehicle, deal canceled.", type = "error" })
                selling = false
                local currentPed = ped
                ped = nil
                despawnPedAfter(currentPed, 10000)
                if blip then RemoveBlip(blip) blip = nil end
                return
            end

            local pedPos = GetEntityCoords(ped)
            local vehPos = GetEntityCoords(veh)
            local distToVeh = #(pedPos - vehPos)
            local now = GetGameTimer()

            -- Re-issue goto every 3s if ped not at vehicle (stuck detection)
            if distToVeh >= 3.0 and not IsPedInVehicle(ped, veh, false) and (now - lastGotoTime) >= 3000 then
                lastGotoTime = now
                local ax = vCoords.x - math.sin(rad) * approachDist
                local ay = vCoords.y + math.cos(rad) * approachDist
                local _, agz = GetGroundZFor_3dCoord(ax, ay, vehPos.z + 2.0, 0)
                if not agz then agz = vehPos.z end
                ClearPedTasks(ped)
                Wait(50)
                TaskGoToCoordAnyMeans(ped, ax, ay, agz, 2.0, 0, 0, 786603, 0xbf800000)
            end

            -- When ped is close to vehicle, tell them to enter (retry every 2s if not in yet)
            if distToVeh < 8.0 and not IsPedInVehicle(ped, veh, false) then
                if not entered or (now - lastEnterAttempt) >= 2000 then
                    lastEnterAttempt = now
                    entered = true
                    local seatToUse = nil
                    for _, s in ipairs({ 0, 1, 2 }) do
                        if IsVehicleSeatFree(veh, s) then seatToUse = s break end
                    end
                    if seatToUse ~= nil then
                        ClearPedTasks(ped)
                        Wait(100)
                        TaskEnterVehicle(ped, veh, -1, seatToUse, 2.0, 1, 0)
                    end
                end
            end

            if IsPedInVehicle(ped, veh, false) then
                if blip then RemoveBlip(blip) blip = nil end
                lib.progressCircle({ duration = 5000, label = "Handing serve the product...", disable = { move = true } })

                local sellAmount = math.random(1, 3)
                pendingSaleContext = { mode = "seat", ped = ped, veh = veh, drug = drug }
                selling = false
                TriggerServerEvent("nbk_drug_dealer:attemptSale", {
                    type = drug,
                    count = sellAmount,
                    coords = GetEntityCoords(p)
                })
                return
            end
        end
    end)
end)

-- ============================================
-- CORNER SALE (ON FOOT)
-- ============================================

AddEventHandler("nbk:cornerSale", function(drug)
    local p = PlayerPedId()

    if selling then resetSale() end

    FreezeEntityPosition(p, true)

    RequestAnimDict("cellphone@")
    while not HasAnimDictLoaded("cellphone@") do Wait(10) end

    local phoneModel = GetHashKey("prop_v_m_phone_o1s")
    RequestModel(phoneModel)
    while not HasModelLoaded(phoneModel) do Wait(10) end

    local phone = CreateObject(phoneModel, 1.0, 1.0, 1.0, true, true, false)
    AttachEntityToEntity(phone, p, GetPedBoneIndex(p, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    TaskPlayAnim(p, "cellphone@", "cellphone_text_read_base", 8.0, -1, -1, 49, 0, false, false, false)

    lib.progressCircle({ duration = 4000, label = "Finding buyer...", disable = { move = true } })
    ClearPedTasks(p)
    DeleteEntity(phone)
    FreezeEntityPosition(p, false)

    local c = GetEntityCoords(p)
    local heading = GetEntityHeading(p)
    -- Load collision at player and spawn so pathfinding works (fixes peds standing still on MLO/custom maps)
    ensureCollisionLoadedAt(c.x, c.y, c.z)
    local dist = 15.0 + math.random() * 25.0
    local angle = math.rad(heading + (math.random() * 120.0 - 60.0))
    local sx = c.x + math.cos(angle) * dist
    local sy = c.y + math.sin(angle) * dist
    local _, sz = GetGroundZFor_3dCoord(sx, sy, c.z + 20.0, 0)
    if not sz then sz = c.z end
    ensureCollisionLoadedAt(sx, sy, sz)
    Wait(100)

    local pedModel = Config.JunkiePeds[math.random(#Config.JunkiePeds)]
    local pedHash = type(pedModel) == "string" and GetHashKey(pedModel) or pedModel
    RequestModel(pedHash)
    local modelTimeout = 0
    while not HasModelLoaded(pedHash) and modelTimeout < 5000 do Wait(10) modelTimeout = modelTimeout + 10 end
    if not HasModelLoaded(pedHash) then
        lib.notify({ title = "Block Work", description = "Failed to load buyer model.", type = "error" })
        return
    end

    ped = CreatePed(4, pedHash, sx, sy, sz, 0.0, true, false)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        DebugPrint("Block work ped spawn failed", ped)
        lib.notify({ title = "Block Work", description = "Failed to spawn buyer.", type = "error" })
        return
    end
    DebugPrint("Block work ped spawned", ped)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, false)
    ClearPedTasksImmediately(ped)
    -- Use coord-based goto so ped actually moves (TaskGoToEntity can fail on custom maps)
    local stopRange = 2.5
    TaskGoToCoordAnyMeans(ped, c.x, c.y, c.z, 2.0, 0, 0, 786603, 0xbf800000)
    -- Stuck detection: re-issue goto to current player pos every 6s if ped hasn't reached player (use PlayerPedId() so respawn-safe)
    CreateThread(function()
        local lastDist = 999.0
        while selling do
            Wait(6000)
            if not selling then break end
            local myPed = PlayerPedId()
            if not DoesEntityExist(ped) or not DoesEntityExist(myPed) then break end
            local pedPos = GetEntityCoords(ped)
            local playerPos = GetEntityCoords(myPed)
            local d = #(pedPos - playerPos)
            if d > stopRange and d >= lastDist - 0.5 then
                DebugPrint("Block work ped stuck, re-issuing goto", d)
                ClearPedTasks(ped)
                Wait(100)
                TaskGoToCoordAnyMeans(ped, playerPos.x, playerPos.y, playerPos.z, 2.0, 0, 0, 786603, 0xbf800000)
            end
            lastDist = d
        end
    end)

    if blip then RemoveBlip(blip) end
    blip = AddBlipForEntity(ped)
    SetBlipSprite(blip, 280)
    SetBlipColour(blip, 3)
    SetBlipScale(blip, 0.85)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Serve")
    EndTextCommandSetBlipName(blip)

    selling = true
    local qty = math.random(3, 5)
    if DoesEntityExist(ped) then
        addPedTarget(ped, drug, qty, "corner", nil, nil)
    end
    lib.notify({ title = "Block Work", description = "Junkie is on the way. Third-eye when they get here.", type = "inform", duration = 6000 })
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
                        addPedTarget(ped, currentDropoffDrug, currentDropoffQty, "dropoff")
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
            addPedTarget(ped, drug, qty, "dropoff")
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

exports('useItem', useItemHandler)

-- IMPORTANT: Your items file must match the resource folder name
-- If your folder is 'SP_DrugSellingV2', items must use: client = { export = 'SP_DrugSellingV2.useItem' }
-- If your items file uses 'nbk_drug_dealer.useItem', you MUST either:
-- 1. Rename resource folder to 'nbk_drug_dealer', OR
-- 2. Update ALL items in ox_inventory to use: client = { export = 'SP_DrugSellingV2.useItem' }
