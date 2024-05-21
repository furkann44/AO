LatestGameState = LatestGameState or nil
InAction = InAction or false 

Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

function addLog(msg, text) 
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

function calcDistance(x1, y1, x2, y2)
    return math.sqrt(math.pow((y2 - y1), 2) + math.pow((x2 - x1), 2))
end

function is_equal(a, b, epsilon) return math.abs(a - b) < (epsilon or 1e-9) end

-- find near person,return personX,personY
function findRecentPerson()
    local player = LatestGameState.Players[ao.id]
    local minDistance = math.maxinteger
    local x = 0
    local y = 0
    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id then
            local distance = calcDistance(player.x, player.y, state.x, state.y)
            print(
                colors.blue .. "distance data:" .. distance .. ":" .. player.x ..
                    ',' .. player.y .. ":" .. state.x .. ',' .. state.y ..
                    " minDistance:" .. minDistance)
            if is_equal(minDistance, distance) or distance < minDistance then
                x = state.x
                y = state.y
                minDistance=distance
            end
        end
    end
    return x, y
end

-- go person
function goPerson(personX, personY)
    local player = LatestGameState.Players[ao.id]
    local distanceX = math.abs(personX - player.x)
    local distanceY = math.abs(personY - player.y)
    local moveStr = ""
    if distanceX <= distanceY then
        if player.y <= personY then
            moveStr = moveStr .. "Up"
        else
            moveStr = moveStr .. "Down"
        end

        if player.x ~= personX then
            if player.x < personX then
                moveStr = moveStr .. "Right"
            else
                moveStr = moveStr .. "Left"
            end
        end
    else
        if player.x <= personX then
            moveStr = moveStr .. "Right"
        else
            moveStr = moveStr .. "Left"
        end

        if player.y ~= personY then
            if player.y < personY then
                moveStr = "Up" .. moveStr
            else
                moveStr = "Down" .. moveStr
            end
        end
    end
    return moveStr
end

function getPersonNumber() return #LatestGameState.Players - 1 end

-- void persons
function voidPerson(personX, personY)
    local player = LatestGameState.Players[ao.id]
    local str = goPerson(personX, personY)
    local swtichResult = {
        Up = "Down",
        Down = "Up",
        Left = "Right",
        Right = "Left",
        UpRight = "UpLeft",
        UpLeft = "UpRight",
        DownRight = "DownLeft",
        DownLeft = "DownRight"
    }
    -- void go person in border when only have one person
    if getPersonNumber() == 1 then
        if player.x == 40 or player.y == 40 or player.y == 1 or player.x == 1 then
            return swtichResult[swtichResult[str]]
        end
    end
    return swtichResult[str]
end

-- if have one person,attack he!
-- if have moer person,avoid all person,wait only hava one person! 
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local personNum = getPersonNumber()
    local personX, personY = findRecentPerson()
    local playerEnergy = LatestGameState.Players[ao.id].energy
    if playerEnergy == undefined then playerEnergy = 0 end
    local moveOrder = ""
    print(colors.red .. "Recent Person:" .. personX .. ',' .. personY)
    print(colors.red .. "My Position:" .. player.x .. ',' .. player.y)
    if personNum ~= 1 then
        moveOrder = voidPerson(personX, personY)
        print(colors.red .. "personNum != 1 move:" .. moveOrder)
        ao.send({
            Target = Game,
            Action = "PlayerMove",
            Player = ao.id,
            Direction = moveOrder
        })
    else
        local targetInRange = false
        for target, state in pairs(LatestGameState.Players) do
            if target ~= ao.id and
                inRange(player.x, player.y, state.x, state.y, 1) then
                targetInRange = true
                break
            end
        end
        if playerEnergy <= 10 then
            moveOrder = voidPerson(personX, personY)
            print(colors.red .. "playerEnergy <= 10 move:" .. moveOrder)
            ao.send({
                Target = Game,
                Action = "PlayerMove",
                Player = ao.id,
                Direction = moveOrder
            })
        else
            if targetInRange then
                print(colors.red .. "Player in range. Attacking." ..
                          colors.reset)
                ao.send({
                    Target = Game,
                    Action = "PlayerAttack",
                    Player = ao.id,
                    AttackEnergy = tostring(player.energy)
                })
            else
                moveOrder = goPerson(personX, personY)
                print(colors.red .. "go target:" .. moveOrder)
                ao.send({
                    Target = Game,
                    Action = "PlayerMove",
                    Player = ao.id,
                    Direction = moveOrder
                })
            end
        end
    end
    InAction = false 
end


Handlers.add("PrintAnnouncements",
             Handlers.utils.hasMatchingTag("Action", "Announcement"),
             function(msg)
    if msg.Event == "Started-Waiting-Period" then
        ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
        InAction = true 
        ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then 
        print("action still in progress.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
end)


Handlers.add("GetGameStateOnTick",
             Handlers.utils.hasMatchingTag("Action", "Tick"), function()
    if not InAction then 
        InAction = true 
        print(colors.gray .. "Getting game state..." .. colors.reset)
        ao.send({Target = Game, Action = "GetGameState"})
    else
        print("action still in progress.")
    end
end)


Handlers.add("AutoPay", Handlers.utils.hasMatchingTag("Action", "AutoPay"),
             function(msg)
    print("Auto-paying confirmation fees.")
    ao.send({
        Target = Game,
        Action = "Transfer",
        Recipient = Game,
        Quantity = "1000"
    })
end)



Handlers.add("UpdateGameState",
             Handlers.utils.hasMatchingTag("Action", "GameState"), function(msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
end)


Handlers.add("decideNextAction",
             Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
             function()
    if LatestGameState.GameMode ~= "Playing" then
        InAction = false 
        return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
end)


Handlers.add("ReturnAttack", Handlers.utils.hasMatchingTag("Action", "Hit"),
             function(msg)
    if not InAction then 
        InAction = true 
        local playerEnergy = LatestGameState.Players[ao.id].energy
        if playerEnergy == undefined then
            print(colors.red .. "energy could not be drawn." .. colors.reset)
            ao.send({
                Target = Game,
                Action = "Attack-Failed",
                Reason = "energy could not be drawn."
            })
        elseif playerEnergy == 0 then
            print(colors.red .. "low energy." ..
                      colors.reset)
            ao.send({
                Target = Game,
                Action = "Attack-Failed",
                Reason = "no energy."
            })
        else
            print(colors.red .. "Returning attack." .. colors.reset)
            ao.send({
                Target = Game,
                Action = "PlayerAttack",
                Player = ao.id,
                AttackEnergy = tostring(playerEnergy)
            })
        end
        InAction = false --  InAction
        ao.send({Target = ao.id, Action = "Tick"})
    else
        print("action still in progress.")
    end
end)
