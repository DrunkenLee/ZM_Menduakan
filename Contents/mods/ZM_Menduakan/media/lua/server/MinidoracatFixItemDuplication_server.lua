-- server/MinidoracatFixItemDuplication_server.lua

if isClient() then return end

local MinidoracatFixItemDuplication = {}

MinidoracatFixItemDuplication.logRemovedItems = function(player, args)
    if not player or not args.playerName or not args.removedItems then 
        print("[ZM_Menduakan] Invalid arguments received")
        return 
    end

    for _, itemInfo in ipairs(args.removedItems) do
        -- Actually remove the item on the server side
        local containers = getWorldInventories()
        for i = 0, containers:size()-1 do
            local container = containers:get(i)
            if container then
                local item = container:getItemById(itemInfo.id)
                if item then
                    container:Remove(item)
                    break
                end
            end
        end
    end
end

-- Handle player disconnect to flag potential duplication moments
MinidoracatFixItemDuplication.OnPlayerDisconnect = function(player)
    if not player then return end
    
    local username = player:getUsername()
    print(string.format("[MinidoracatFixItemDuplication] Player %s disconnected, flagging for duplicate check on reconnect", username))
    
    -- You could also save the player's last position to check that area specifically on reconnect
end

Events.OnLoad.Add(function()
end)

local function onClientCommand(module, command, player, args)
    if module == "MinidoracatFixItemDuplication" and command == "LogRemovedItems" then
        MinidoracatFixItemDuplication.logRemovedItems(player, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnPlayerDisconnect.Add(MinidoracatFixItemDuplication.OnPlayerDisconnect)

print("[MinidoracatFixItemDuplication] Server-side script loaded")