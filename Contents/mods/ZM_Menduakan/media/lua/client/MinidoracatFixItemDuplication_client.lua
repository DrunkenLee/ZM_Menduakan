-- client/MinidoracatFixItemDuplication_client.lua

local MinidoracatFixItemDuplication = {}

-- Configuration
MinidoracatFixItemDuplication.DEBUG_MODE = true -- Set to false for production
MinidoracatFixItemDuplication.MINUTES_BETWEEN_CHECKS = 5 -- How often to run full checks

-- State variables
MinidoracatFixItemDuplication.containerCache = {}
MinidoracatFixItemDuplication.containersUpdated = false
MinidoracatFixItemDuplication.lastFullCheckTime = 0
MinidoracatFixItemDuplication.delayedCheckScheduled = false

-- Logging function
MinidoracatFixItemDuplication.log = function(message)
    if MinidoracatFixItemDuplication.DEBUG_MODE then
        print("[MinidoracatFixItemDuplication] " .. tostring(message))
    end
end

MinidoracatFixItemDuplication.resetContainerCache = function()
    MinidoracatFixItemDuplication.containerCache = {}
    MinidoracatFixItemDuplication.containersUpdated = false
    MinidoracatFixItemDuplication.log("Container cache reset")
end

MinidoracatFixItemDuplication.canBeAdded = function(container, playerObj)
    if not container or not playerObj then return false end
    
    -- Player inventories are always allowed
    if container:getType() == "inventoryfemale" or container:getType() == "inventorymale" then
        return true
    end

    -- Don't add locked containers
    local object = container:getParent()
    if object and instanceof(object, "IsoThumpable") and object:isLockedToCharacter(playerObj) then
        return false
    end

    return true
end

-- Scan for vehicle containers and add them to cache
-- MinidoracatFixItemDuplication.scanVehicleContainers = function(playerObj)
--     if not playerObj then return end
    
--     -- Check player's vehicle
--     local vehicle = playerObj:getVehicle()
--     if vehicle then
--         MinidoracatFixItemDuplication.log("Scanning vehicle containers")
--         for i=0, vehicle:getPartCount()-1 do
--             local part = vehicle:getPartByIndex(i)
--             if part and part:getInventoryItem() and part:getItemContainer() then
--                 -- Add vehicle containers to cache with special index to avoid conflicts
--                 local containerIndex = "veh_" .. vehicle:getId() .. "_" .. i
--                 MinidoracatFixItemDuplication.containerCache[containerIndex] = part:getItemContainer()
--             end
--         end
--     end
    
--     -- Check nearby vehicles (within interaction range)
--     local cell = getWorld():getCell()
--     local x, y, z = playerObj:getX(), playerObj:getY(), playerObj:getZ()
--     local range = 10  -- Interaction range
    
--     for vehX = math.floor(x) - range, math.floor(x) + range do
--         for vehY = math.floor(y) - range, math.floor(y) + range do
--             local square = cell:getGridSquare(vehX, vehY, z)
--             if square then
--                 local vehicles = square:getVehicles()
--                 if vehicles then
--                     for i = 0, vehicles:size()-1 do
--                         local veh = vehicles:get(i)
--                         if veh and veh ~= vehicle then  -- Skip player's vehicle (already processed)
--                             for j=0, veh:getPartCount()-1 do
--                                 local part = veh:getPartByIndex(j)
--                                 if part and part:getInventoryItem() and part:getItemContainer() then
--                                     local containerIndex = "veh_" .. veh:getId() .. "_" .. j
--                                     MinidoracatFixItemDuplication.containerCache[containerIndex] = part:getItemContainer()
--                                 end
--                             end
--                         end
--                     end
--                 end
--             end
--         end
--     end
-- end

-- Scan additional containers like world containers
MinidoracatFixItemDuplication.scanWorldContainers = function(playerObj)
    if not playerObj then return end
    
    -- MinidoracatFixItemDuplication.log("Scanning world containers")
    local cell = getWorld():getCell()
    local x, y, z = playerObj:getX(), playerObj:getY(), playerObj:getZ()
    local range = 20  -- Interaction range
    
    for worldX = math.floor(x) - range, math.floor(x) + range do
        for worldY = math.floor(y) - range, math.floor(y) + range do
            local square = cell:getGridSquare(worldX, worldY, z)
            if square then
                for i = 0, square:getObjects():size()-1 do
                    local object = square:getObjects():get(i)
                    if object and object:getContainer() then
                        local container = object:getContainer()
                        local containerIndex = "world_" .. worldX .. "_" .. worldY .. "_" .. z .. "_" .. i
                        MinidoracatFixItemDuplication.containerCache[containerIndex] = container
                    end
                end
            end
        end
    end
end

MinidoracatFixItemDuplication.removeDuplicateItem = function(item)
    if not item then return false end

    local container = item:getContainer()
    if not container then return false end

    MinidoracatFixItemDuplication.log("Removing item: " .. tostring(item:getName()) .. " (ID: " .. tostring(item:getID()) .. ")")

    -- First remove on server if we're a client
    if isClient() then
        container:removeItemOnServer(item)
    end

    -- Handle world items properly
    if item:getWorldItem() then
        item:getWorldItem():removeFromWorld()
        item:getWorldItem():removeFromSquare()
        item:getWorldItem():setSquare(nil)
    end

    -- Remove from container
    container:Remove(item)

    return true
end

MinidoracatFixItemDuplication.checkAndRemoveDuplicateItems = function(playerObj)
    if not playerObj then
        MinidoracatFixItemDuplication.log("No player object provided for checkAndRemoveDuplicateItems")
        return
    end

    MinidoracatFixItemDuplication.log("Checking for duplicate items")
    
    -- Scan for additional containers before checking
    -- MinidoracatFixItemDuplication.scanVehicleContainers(playerObj)
    MinidoracatFixItemDuplication.scanWorldContainers(playerObj)
    
    local playerItemIds = {}
    local containerItemIds = {}
    local removedItems = {}

    -- First check player inventory
    local playerInventory = playerObj:getInventory()
    if playerInventory then
        local playerItemList = playerInventory:getItems()
        for i = 0, playerItemList:size() - 1 do
            local item = playerItemList:get(i)
            if item then
                playerItemIds[item:getID()] = true
            end
        end
    end

    -- Then check all cached containers
    for index, container in pairs(MinidoracatFixItemDuplication.containerCache) do
        if container and container:getItems() then
            local itemList = container:getItems()
            local itemsToRemove = {}
            
            for i = 0, itemList:size() - 1 do
                local item = itemList:get(i)
                if item then
                    local itemId = item:getID()
                    if playerItemIds[itemId] or containerItemIds[itemId] then
                        -- This is a duplicate, mark for removal
                        table.insert(itemsToRemove, item)
                    else
                        -- First occurrence, remember we've seen it
                        containerItemIds[itemId] = true
                    end
                end
            end
            
            -- Remove all duplicates found in this container
            for _, item in ipairs(itemsToRemove) do
                if MinidoracatFixItemDuplication.removeDuplicateItem(item) then
                    MinidoracatFixItemDuplication.log(string.format("Removed duplicate item: %s (ID: %s, Type: %s) from container %s", 
                        item:getName(), tostring(item:getID()), item:getType(), tostring(index)))
                    table.insert(removedItems, {
                        name = item:getName(),
                        type = item:getType(),
                        id = item:getID(),
                        containerIndex = index
                    })
                end
            end
        end
    end

    -- Send information about removed items to the server
    if #removedItems > 0 then
        sendClientCommand(playerObj, "MinidoracatFixItemDuplication", "LogRemovedItems", {
            playerName = playerObj:getUsername(),
            removedItems = removedItems
        })
        MinidoracatFixItemDuplication.log(string.format("Removed %d duplicate items", #removedItems))
    else
        MinidoracatFixItemDuplication.log("No duplicate items found")
    end
end

-- Function for delayed check (used after player reconnection)
MinidoracatFixItemDuplication.delayedCheck = function()
    local player = getPlayer()
    if player then
        -- Run the more aggressive post-reconnection check
        MinidoracatFixItemDuplication.postReconnectionCheck(player)
    end
    Events.OnTick.Remove(MinidoracatFixItemDuplication.delayedCheck)
    MinidoracatFixItemDuplication.delayedCheckScheduled = false
end

-- Schedule a delayed check to ensure all containers are loaded
MinidoracatFixItemDuplication.scheduleDelayedCheck = function(playerObj)
    if not MinidoracatFixItemDuplication.delayedCheckScheduled then
        MinidoracatFixItemDuplication.log("Scheduling delayed check")
        Events.OnTick.Add(MinidoracatFixItemDuplication.delayedCheck)
        MinidoracatFixItemDuplication.delayedCheckScheduled = true
    end
end

-- When inventory UI is refreshed, check containers
MinidoracatFixItemDuplication.OnRefreshInventoryWindowContainers = function(inventoryPage, state)
    local playerObj = getSpecificPlayer(inventoryPage.player)
    if not playerObj then return end
    
    -- Skip if on character screen or in vehicle (handled separately)
    if inventoryPage.onCharacter then return end

    if state == "begin" then
        MinidoracatFixItemDuplication.resetContainerCache()
    elseif state == "buttonsAdded" then
        local containersChanged = false
        
        -- Add inventory container backpacks to cache
        if inventoryPage.backpacks then
            for i = 1, (#inventoryPage.backpacks - 1) do
                local invToAdd = inventoryPage.backpacks[i].inventory
                if invToAdd and MinidoracatFixItemDuplication.canBeAdded(invToAdd, playerObj) then
                    if not MinidoracatFixItemDuplication.containerCache[i] then
                        MinidoracatFixItemDuplication.containerCache[i] = invToAdd
                        containersChanged = true
                    end
                end
            end
        end
        
        -- If containers changed, check for duplicates
        if containersChanged then
            MinidoracatFixItemDuplication.checkAndRemoveDuplicateItems(playerObj)
            MinidoracatFixItemDuplication.containersUpdated = true
        end
    end
end

-- Check when player connects initially
MinidoracatFixItemDuplication.OnPlayerConnect = function(playerObj)
    MinidoracatFixItemDuplication.log("Player connected, checking for duplicates")
    MinidoracatFixItemDuplication.scheduleDelayedCheck(playerObj)
end

-- Check when player is created (including after reconnect)
MinidoracatFixItemDuplication.OnCreatePlayer = function(playerIndex, playerObj)
    MinidoracatFixItemDuplication.log("Player created, scheduling delayed check")
    MinidoracatFixItemDuplication.scheduleDelayedCheck(playerObj)
end

-- Periodic check based on time passed
MinidoracatFixItemDuplication.OnPlayerUpdate = function(playerObj)
    if not playerObj then return end
    
    local currentTime = getGameTime():getWorldAgeHours() * 60
    if (currentTime - MinidoracatFixItemDuplication.lastFullCheckTime) >= MinidoracatFixItemDuplication.MINUTES_BETWEEN_CHECKS then
        MinidoracatFixItemDuplication.log("Running periodic full check")
        MinidoracatFixItemDuplication.checkAndRemoveDuplicateItems(playerObj)
        MinidoracatFixItemDuplication.lastFullCheckTime = currentTime
    end
end

-- Event manager helpers
local function safeAddEvent(event, func)
    if event then
        event.Add(func)
    end
end

local function safeRemoveEvent(event, func)
    if event then
        event.Remove(func)
    end
end

-- Remove event handlers if already registered
safeRemoveEvent(Events.OnRefreshInventoryWindowContainers, MinidoracatFixItemDuplication.OnRefreshInventoryWindowContainers)
safeRemoveEvent(Events.OnPlayerConnect, MinidoracatFixItemDuplication.OnPlayerConnect)
safeRemoveEvent(Events.OnCreatePlayer, MinidoracatFixItemDuplication.OnCreatePlayer)
safeRemoveEvent(Events.OnPlayerUpdate, MinidoracatFixItemDuplication.OnPlayerUpdate)

-- Register event handlers
safeAddEvent(Events.OnRefreshInventoryWindowContainers, MinidoracatFixItemDuplication.OnRefreshInventoryWindowContainers)
safeAddEvent(Events.OnPlayerConnect, MinidoracatFixItemDuplication.OnPlayerConnect)
safeAddEvent(Events.OnCreatePlayer, MinidoracatFixItemDuplication.OnCreatePlayer)
safeAddEvent(Events.OnPlayerUpdate, MinidoracatFixItemDuplication.OnPlayerUpdate)

MinidoracatFixItemDuplication.log("Client-side script loaded")

-- Add these new functions to the existing code

-- Special check for world containers that might be duplicated after disconnect
MinidoracatFixItemDuplication.checkGroundBagDuplicates = function(playerObj)
    if not playerObj then return end
    
    local playerInv = playerObj:getInventory()
    local playerItems = {}
    
    -- First, catalog all items in player inventory by ID
    local allPlayerItems = playerInv:getItems()
    for i = 0, allPlayerItems:size()-1 do
        local item = allPlayerItems:get(i)
        if item then
            playerItems[item:getID()] = item
        end
    end
    
    -- Now check nearby ground for duplicates of player's items
    local cell = getWorld():getCell()
    local x, y, z = playerObj:getX(), playerObj:getY(), playerObj:getZ()
    local range = 30  -- Larger range to catch items that might have been dropped
    
    local worldDuplicates = {}
    
    -- Scan all nearby squares
    for worldX = math.floor(x) - range, math.floor(x) + range do
        for worldY = math.floor(y) - range, math.floor(y) + range do
            local square = cell:getGridSquare(worldX, worldY, z)
            if square then
                -- Check world items on this square
                local worldItems = square:getWorldObjects()
                if worldItems then
                    for i = 0, worldItems:size()-1 do
                        local worldItem = worldItems:get(i)
                        if worldItem and worldItem:getItem() then
                            local item = worldItem:getItem()
                            -- If this world item has the same ID as a player inventory item
                            if playerItems[item:getID()] then
                                table.insert(worldDuplicates, {
                                    worldItem = worldItem,
                                    item = item,
                                    square = square
                                })
                            end
                        end
                    end
                end
                
                -- Also check containers on this square
                for i = 0, square:getObjects():size()-1 do
                    local object = square:getObjects():get(i)
                    if object and object:getContainer() then
                        local container = object:getContainer()
                        local containerItems = container:getItems()
                        for j = 0, containerItems:size()-1 do
                            local item = containerItems:get(j)
                            if playerItems[item:getID()] then
                                MinidoracatFixItemDuplication.removeDuplicateItem(item)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Remove world duplicate items
    for _, duplicate in ipairs(worldDuplicates) do
        MinidoracatFixItemDuplication.log("Removing duplicate world item: " .. duplicate.item:getName())
        duplicate.worldItem:removeFromWorld()
        duplicate.worldItem:removeFromSquare()
        duplicate.square:transmitRemoveItemFromSquare(duplicate.worldItem)
    end
    
    return #worldDuplicates
end

-- Add an aggressive post-reconnection check
MinidoracatFixItemDuplication.postReconnectionCheck = function(player)
    if not player then return end
    
    MinidoracatFixItemDuplication.log("Running post-reconnection duplicate check")
    
    -- First run the normal check
    MinidoracatFixItemDuplication.checkAndRemoveDuplicateItems(player)
    
    -- Then run a special check for ground bags and other world duplicates
    local worldDupsRemoved = MinidoracatFixItemDuplication.checkGroundBagDuplicates(player)
    if worldDupsRemoved > 0 then
        MinidoracatFixItemDuplication.log("Removed " .. worldDupsRemoved .. " world duplicates after reconnection")
    end
end

-- Add this to check world objects when a player interacts with them
MinidoracatFixItemDuplication.OnObjectInteracted = function(object, playerObj)
    if not object or not playerObj then return end
    
    -- Check if this is a container object
    if object:getContainer() then
        -- Run a quick duplicate check focused on this container
        MinidoracatFixItemDuplication.checkAndRemoveDuplicateItems(playerObj)
    end
end

-- Add this event near the end with the other event registrations
safeAddEvent(Events.OnObjectLeftMouseButtonUp, MinidoracatFixItemDuplication.OnObjectInteracted)