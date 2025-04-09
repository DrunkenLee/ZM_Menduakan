-- client/MinidoracatFixItemDuplication_client.lua

local MinidoracatFixItemDuplication = {}

MinidoracatFixItemDuplication.containerCache = {}
MinidoracatFixItemDuplication.containersUpdated = false


MinidoracatFixItemDuplication.resetContainerCache = function()
    MinidoracatFixItemDuplication.containerCache = {}
    MinidoracatFixItemDuplication.containersUpdated = false
end

MinidoracatFixItemDuplication.canBeAdded = function(container, playerObj)
    if not container or not playerObj then return false end


    if container:getType() == "inventoryfemale" or container:getType() == "inventorymale" then
        return true
    end


    local object = container:getParent()
    if object and instanceof(object, "IsoThumpable") and object:isLockedToCharacter(playerObj) then
        return false
    end

    return true
end

MinidoracatFixItemDuplication.removeDuplicateItem = function(item)
    if not item then return false end

    local container = item:getContainer()
    if not container then return false end

    if isClient() then
        container:removeItemOnServer(item)
    end

    if item:getWorldItem() then
        item:getWorldItem():removeFromWorld()
        item:getWorldItem():removeFromSquare()
        item:getWorldItem():setSquare(nil)
    end

    container:Remove(item)

    return true
end

MinidoracatFixItemDuplication.checkAndRemoveDuplicateItems = function(playerObj)
    if not playerObj then
        return
    end

    local playerItemIds = {}
    local containerItemIds = {}
    local removedItems = {}

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

    for index, container in pairs(MinidoracatFixItemDuplication.containerCache) do
        local itemList = container:getItems()
        if itemList then
            local itemsToRemove = {}
            for i = 0, itemList:size() - 1 do
                local item = itemList:get(i)
                if item then
                    local itemId = item:getID()
                    if playerItemIds[itemId] or containerItemIds[itemId] then
                        table.insert(itemsToRemove, item)
                    else
                        containerItemIds[itemId] = true
                    end
                end
            end

            for _, item in ipairs(itemsToRemove) do
                if MinidoracatFixItemDuplication.removeDuplicateItem(item) then
                    print(string.format("[MinidoracatFixItemDuplication] Removed duplicate item: %s (ID: %s, Type: %s) from container %d",
                        item:getName(), tostring(item:getID()), item:getType(), index))
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

    if #removedItems > 0 then
        sendClientCommand(playerObj, "MinidoracatFixItemDuplication", "LogRemovedItems", {
            playerName = playerObj:getUsername(),
            removedItems = removedItems
        })
        print(string.format("[MinidoracatFixItemDuplication] Removed %d duplicate items", #removedItems))
    end
end

MinidoracatFixItemDuplication.OnRefreshInventoryWindowContainers = function(inventoryPage, state)
    local playerObj = getSpecificPlayer(inventoryPage.player)
    if not playerObj or inventoryPage.onCharacter or playerObj:getVehicle() then
        return
    end

    if state == "begin" then
        MinidoracatFixItemDuplication.resetContainerCache()
    elseif state == "buttonsAdded" then
        local containersChanged = false
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

        if containersChanged then
            MinidoracatFixItemDuplication.checkAndRemoveDuplicateItems(playerObj)
            MinidoracatFixItemDuplication.containersUpdated = true
        end
    end
end

MinidoracatFixItemDuplication.OnPlayerConnect = function(playerObj)
    MinidoracatFixItemDuplication.checkAndRemoveDuplicateItems(playerObj)
end

MinidoracatFixItemDuplication.OnActionPerformed = function(character, action)
  if not character or not action then return end

  -- Check if this is an inventory-related action
  local actionType = action:getType()
  if actionType == "Take" or actionType == "AddItemInInventory" or
     actionType == "TransferItemAction" or actionType == "MoveToInventory" then
      -- Short delay to allow the inventory to update first
      TimerManager.instance:add(MinidoracatFixItemDuplication.OnActionPerformed, 10, function()
          MinidoracatFixItemDuplication.checkAndRemoveDuplicateItems(character)
      end)
  end
end

MinidoracatFixItemDuplication.OnCreatePlayer = function(playerNum, player)
  -- Only check for the local player
  if player and getSpecificPlayer(playerNum) == getPlayer() then
      -- Short delay to ensure inventory is fully loaded
      TimerManager.instance:add(MinidoracatFixItemDuplication.OnCreatePlayer, 200, function()
          MinidoracatFixItemDuplication.checkAndRemoveDuplicateItems(player)
      end)
  end
end

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

safeRemoveEvent(Events.OnRefreshInventoryWindowContainers, MinidoracatFixItemDuplication.OnRefreshInventoryWindowContainers)
safeRemoveEvent(Events.OnPlayerConnect, MinidoracatFixItemDuplication.OnPlayerConnect)
safeRemoveEvent(Events.OnCreatePlayer, MinidoracatFixItemDuplication.OnCreatePlayer)

safeAddEvent(Events.OnRefreshInventoryWindowContainers, MinidoracatFixItemDuplication.OnRefreshInventoryWindowContainers)
safeAddEvent(Events.OnPlayerConnect, MinidoracatFixItemDuplication.OnPlayerConnect)
safeAddEvent(Events.OnCreatePlayer, MinidoracatFixItemDuplication.OnCreatePlayer)

if EventsPlus then
  EventsPlus:Add("OnActionPerformed", MinidoracatFixItemDuplication.OnActionPerformed, "MinidoracatFixItemDuplication")
end

print("[MinidoracatFixItemDuplication] Client-side script loaded")