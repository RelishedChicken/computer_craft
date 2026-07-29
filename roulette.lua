local relays = {peripheral.find("redstone_relay")};
local barres = {peripheral.find("barrel")};
local monitor = peripheral.find("monitor");
local buttonRelay = peripheral.wrap("redstone_relay_73");
local wheelColors = {
    [1] = "red",   [2] = "black", [3] = "red",
    [4] = "green",
    [5] = "black", [6] = "red",   [7] = "black",
    [8] = "green",
    [9] = "red",   [10] = "black", [11] = "red",
    [12] = "green",
    [13] = "black", [14] = "red",  [15] = "black",
    [16] = "green",
}
local payoutMultipliers = {
    red = 2,     -- e.g. bet 5, win 10 (even money)
    black = 2,   -- same as red
    green = 8,   -- rarer (4 out of 16 slots), so higher payout
}

--Relay prep
local function wrapRelays(startNum, count)
    local relays = {}
    for i = 0, count - 1 do
        local name = "redstone_relay_" .. (startNum + i)
        local relay = peripheral.wrap(name)
        if relay then
            table.insert(relays, relay)
        else
            print("Warning: could not find " .. name)
        end
    end
    return relays
end

--Barrels prep
local function wrapBarrels(startNum, count)
    local barrels = {}
    for i = 0, count - 1 do
        local name = "minecraft:barrel_" .. (startNum + i)
        local barrel = peripheral.wrap(name)
        if barrel then
            table.insert(barrels, barrel)
        else
            print("Warning: could not find " .. name)
        end
    end
    return barrels
end

--Get the real peripheral names
local relays = wrapRelays(56, 16);
local barrels = wrapBarrels(0, 3);

--Vault & bet barrel info
local vaultName = "minecraft:barrel_3";
local betBarrels = {
    red   = barrels[1],
    black = barrels[2],
    green = barrels[3],
}
local betBarrelPositions = {
    red   = { x = -558, y = 66, z = -152 },
    black = { x = -558, y = 66, z = -154 },
    green = { x = -558, y = 66, z = -156 },
}

--Monitor helpers
local function writeCentered(mon, text, yOffset, textColor, bgColor, scale)
    mon.setTextScale(scale or 1)
    local w, h = mon.getSize()
    local x = math.floor((w - #text) / 2) + 1
    local y = math.floor(h / 2) + (yOffset or 0)
    mon.setBackgroundColor(bgColor or colors.black)
    mon.clear()
    mon.setCursorPos(x, y)
    mon.setTextColor(textColor or colors.white)
    mon.write(text)
end

local function clearAll()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
end

local function showLandingScreen(color)
    local bg = colors.black
    if color == "red" then
        bg = colors.red
    elseif color == "black" then
        bg = colors.gray
    elseif color == "green" then
        bg = colors.green
    end
    writeCentered(monitor, color:upper(), 0, colors.white, bg, 5)
end

--Running Code
local function flashLamp(lamp, duration)
    relays[lamp].setOutput("bottom", true);
    sleep(duration);
    relays[lamp].setOutput("bottom", false);
end

local function animateBall(choice)
    local landed = false;
    local loops = 12;

    for i = 1, loops do
        for l = 1, #relays do
            if l == choice and i == loops then
                landed = true;
                break;
            end
            flashLamp(l, 0.1);
        end
        if landed then
            break;
        end
    end

    -- Stop on the chosen lamp
    showLandingScreen(wheelColors[choice]);
    flashLamp(choice, 3);
    return wheelColors[choice];

end

local function rollBall()
    local random_choice = math.random(1,#relays);
    local color = animateBall(random_choice);
    print("Landed on "..random_choice.." ("..color..")");
    return color;
end

--Betting & payouts
local currentBets = { red = {}, black = {}, green = {} };

local function lockBets()
    currentBets = { red = {}, black = {}, green = {} };
    for color, barrel in pairs(betBarrels) do
        for slot, item in pairs(barrel.list()) do
            table.insert(currentBets[color], { name = item.name, count = item.count });
            barrel.pushItems(vaultName, slot);
        end
    end
end

local function depositItems(color, itemName, count)
    local barrel = betBarrels[color];
    local pos = betBarrelPositions[color];
    local remaining = count;

    -- Top up any existing stack of the same item first
    for slot, item in pairs(barrel.list()) do
        if remaining <= 0 then break end
        if item.name == itemName and item.count < 64 then
            local add = math.min(64 - item.count, remaining);
            commands.exec(("item replace block %d %d %d container.%d with %s %d")
                :format(pos.x, pos.y, pos.z, slot - 1, itemName, item.count + add));
            remaining = remaining - add;
        end
    end

    -- Fill empty slots with whatever is left
    if remaining > 0 then
        local occupied = {};
        for slot in pairs(barrel.list()) do
            occupied[slot] = true;
        end
        local slot = 1;
        while remaining > 0 and slot <= barrel.size() do
            if not occupied[slot] then
                local add = math.min(64, remaining);
                commands.exec(("item replace block %d %d %d container.%d with %s %d")
                    :format(pos.x, pos.y, pos.z, slot - 1, itemName, add));
                remaining = remaining - add;
            end
            slot = slot + 1;
        end
    end

    if remaining > 0 then
        print("Warning: "..color.." barrel is full, could not pay out "..remaining.." x "..itemName);
    end
end

local function handlePayouts(winningColor)
    local bets = currentBets[winningColor];
    local multiplier = payoutMultipliers[winningColor];

    for _, entry in ipairs(bets) do
        local payout = entry.count * multiplier;
        print("Paying out "..payout.." x "..entry.name.." to "..winningColor);
        depositItems(winningColor, entry.name, payout);
    end
end

--Button handling
local function waitForInput(side)
    while true do
        os.pullEvent("redstone")
        if buttonRelay.getInput(side) then
            -- debounce: wait for release before returning
            while buttonRelay.getInput(side) do
                os.pullEvent("redstone")
            end
            return
        end
    end
end

local function waitForStart()
    waitForInput("top")
end

local function waitForCancel()
    waitForInput("bottom")
end

--Main game loop
local function gameLoop()
    while true do
        clearAll()
        writeCentered(monitor, "Welcome! Place your bets in the barrel & press the button", 0, colors.white)
        print("Waiting for start button...")
        waitForStart()

        lockBets()

        print("Round starting!")
        writeCentered(monitor, "Spinning!", 0, colors.white)
        local winningColor = rollBall()
        handlePayouts(winningColor)
    end
end

parallel.waitForAny(gameLoop, waitForCancel)

clearAll()
writeCentered(monitor, "Game Stopped", 0, colors.white, colors.red)
print("Cancel button pressed - game stopped.")

