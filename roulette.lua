-- =========================================================
-- CONFIG
-- =========================================================
local monitor = peripheral.find("monitor");
local buttonRelay = peripheral.wrap("redstone_relay_73");

-- Lamp number (1-16, matches relay order) -> wheel colour.
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

-- Winning payout = bet count * multiplier (e.g. bet 5 red, win 10 back).
local payoutMultipliers = {
    red = 2,
    black = 2,
    green = 8,   -- rarer (4 of 16 slots), so higher payout
}

-- =========================================================
-- PERIPHERAL SETUP
-- =========================================================

-- Wraps `count` peripherals named "<prefix><startNum>".."<prefix><startNum+count-1>",
-- skipping (and printing a warning for) any that can't be found.
local function wrapPeripherals(prefix, startNum, count)
    local found = {}
    for i = 0, count - 1 do
        local name = prefix .. (startNum + i)
        local wrapped = peripheral.wrap(name)
        if wrapped then
            table.insert(found, wrapped)
        else
            print("Warning: could not find " .. name)
        end
    end
    return found
end

local relays = wrapPeripherals("redstone_relay_", 56, 16);
local barrels = wrapPeripherals("minecraft:barrel_", 0, 3);

-- The vault holds locked-in bets for the round (barrel_3). Never returned to
-- players directly - winners are paid via fresh duplicated items instead.
local vaultName = "minecraft:barrel_3";

-- barrels[1..3] map to red/black/green in that order (barrel_0/1/2).
local betBarrels = {
    red   = barrels[1],
    black = barrels[2],
    green = barrels[3],
}

-- World coordinates of each bet barrel, needed for the /item replace block
-- payout command (CC:Tweaked has no API to look up a peripheral's position).
local betBarrelPositions = {
    red   = { x = -558, y = 66, z = -152 },
    black = { x = -558, y = 66, z = -154 },
    green = { x = -558, y = 66, z = -156 },
}

-- =========================================================
-- MONITOR HELPERS
-- =========================================================

local function clearAll()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
end

-- Clears the monitor and writes each string in `lines`, centered and
-- stacked vertically around the middle of the screen.
local function writeLines(mon, lines, textColor, bgColor, scale)
    mon.setTextScale(scale or 1)
    mon.setBackgroundColor(bgColor or colors.black)
    mon.clear()
    local w, h = mon.getSize()
    local startY = math.floor((h - #lines) / 2) + 1
    mon.setTextColor(textColor or colors.white)
    for i, line in ipairs(lines) do
        local x = math.floor((w - #line) / 2) + 1
        mon.setCursorPos(x, startY + i - 1)
        mon.write(line)
    end
end

-- Single-line convenience wrapper around writeLines.
local function writeCentered(mon, text, textColor, bgColor, scale)
    writeLines(mon, { text }, textColor, bgColor, scale)
end

-- Flashes the monitor background to the winning colour with the colour
-- name printed on top. Called once the ball has landed.
local function showLandingScreen(color)
    local bg = colors.black
    if color == "red" then
        bg = colors.red
    elseif color == "black" then
        bg = colors.gray
    elseif color == "green" then
        bg = colors.green
    end
    writeCentered(monitor, color:upper(), colors.white, bg, 5)
end

-- =========================================================
-- WHEEL / SPIN
-- =========================================================

-- Turns lamp `lamp`'s relay output on for `duration` seconds, then off -
-- one "blink" as the ball passes it during the spin.
local function flashLamp(lamp, duration)
    relays[lamp].setOutput("bottom", true);
    sleep(duration);
    relays[lamp].setOutput("bottom", false);
end

-- Blinks through the lamps in order, slowing to a stop on lamp `choice`,
-- then shows the result on the monitor. Returns the winning colour.
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

-- Picks a random lamp, runs the spin animation, and returns the winning colour.
local function rollBall()
    local random_choice = math.random(1,#relays);
    local color = animateBall(random_choice);
    print("Landed on "..random_choice.." ("..color..")");
    return color;
end

-- =========================================================
-- BETTING & PAYOUTS
-- =========================================================

-- Snapshot of what was bet on each colour this round, set by lockBets().
-- currentBets[color] = { { name = itemName, count = n }, ... }
local currentBets = { red = {}, black = {}, green = {} };

-- Records what's currently in each bet barrel (into currentBets) and moves
-- it all into the vault, locking in bets for the round. Call once, right
-- after the start button is pressed and before the spin begins.
local function lockBets()
    currentBets = { red = {}, black = {}, green = {} };
    for color, barrel in pairs(betBarrels) do
        for slot, item in pairs(barrel.list()) do
            table.insert(currentBets[color], { name = item.name, count = item.count });
            barrel.pushItems(vaultName, slot);
        end
    end
    return currentBets;
end

-- Turns a bets table (as returned by lockBets) into display lines, one per
-- colour, e.g. "RED: 3x minecraft:emerald" or "GREEN: no bets".
local function summarizeBets(bets)
    local lines = {};
    for _, color in ipairs({ "red", "black", "green" }) do
        local entries = bets[color];
        if #entries == 0 then
            table.insert(lines, color:upper()..": no bets");
        else
            local items = {};
            for _, entry in ipairs(entries) do
                table.insert(items, entry.count.."x "..entry.name);
            end
            table.insert(lines, color:upper()..": "..table.concat(items, ", "));
        end
    end
    return lines;
end

-- Runs a command via the Command Computer `commands` API, printing the
-- failure reason if it doesn't succeed (silent failures are hard to debug).
-- Requires this computer to actually be a Command Computer.
local function runCommand(cmd)
    local ok, output = commands.exec(cmd);
    if not ok then
        print("Command failed: "..cmd);
        if output then
            for _, line in ipairs(output) do
                print("  "..line);
            end
        end
    end
    return ok;
end

-- Sets container slot `slot` (1-indexed, matching CC's barrel.list()) at
-- block `pos` to hold `count` of `itemName`. Minecraft's container.N slot
-- component is 0-indexed, hence slot - 1.
local function replaceSlot(pos, slot, itemName, count)
    return runCommand(("item replace block %d %d %d container.%d with %s %d")
        :format(pos.x, pos.y, pos.z, slot - 1, itemName, count));
end

-- Pays `count` of `itemName` into the `color` bet barrel: tops up any
-- existing matching stack first, then fills empty slots. Warns (rather
-- than erroring) if the barrel fills up before the full amount is placed.
local function depositItems(color, itemName, count)
    local barrel = betBarrels[color];
    local pos = betBarrelPositions[color];
    local remaining = count;

    -- Top up any existing stack of the same item first
    for slot, item in pairs(barrel.list()) do
        if remaining <= 0 then break end
        if item.name == itemName and item.count < 64 then
            local add = math.min(64 - item.count, remaining);
            replaceSlot(pos, slot, itemName, item.count + add);
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
                replaceSlot(pos, slot, itemName, add);
                remaining = remaining - add;
            end
            slot = slot + 1;
        end
    end

    if remaining > 0 then
        print("Warning: "..color.." barrel is full, could not pay out "..remaining.." x "..itemName);
    end
end

-- Pays out the winning colour's bets (from the currentBets snapshot) at
-- payoutMultipliers[winningColor]x, via freshly duplicated items - the
-- original stake and all losing bets stay in the vault. Call after
-- lockBets() and rollBall().
local function handlePayouts(winningColor)
    local bets = currentBets[winningColor];
    local multiplier = payoutMultipliers[winningColor];

    for _, entry in ipairs(bets) do
        local payout = entry.count * multiplier;
        print("Paying out "..payout.." x "..entry.name.." to "..winningColor);
        depositItems(winningColor, entry.name, payout);
    end
end

-- =========================================================
-- BUTTON INPUT
-- =========================================================

-- Blocks until buttonRelay's redstone input on `side` goes high, then
-- waits for it to drop low again (debounce) before returning - one call
-- per physical button press.
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

-- Blocks until the start button (top of buttonRelay) is pressed.
local function waitForStart()
    waitForInput("top")
end

-- Blocks until the cancel button (bottom of buttonRelay) is pressed.
local function waitForCancel()
    waitForInput("bottom")
end

-- =========================================================
-- MAIN LOOP
-- =========================================================

-- Round loop: show the welcome screen, wait for start, lock in bets, spin,
-- pay out the winner, repeat forever. Runs alongside waitForCancel below -
-- whichever finishes first wins the race and the other is abandoned, so a
-- cancel press can interrupt mid-round.
local function gameLoop()
    while true do
        clearAll()
        writeCentered(monitor, "Welcome! Place your bets in the barrel & press the button", colors.white, colours.black, 5)
        print("Waiting for start button...")
        waitForStart()

        local bets = lockBets()

        print("Round starting!")
        local summary = summarizeBets(bets)
        table.insert(summary, 1, "Spinning, good luck!")
        writeLines(monitor, summary, colors.white, colours.black, 2)
        local winningColor = rollBall()
        handlePayouts(winningColor)
    end
end

-- =========================================================
-- ENTRY POINT
-- =========================================================

parallel.waitForAny(gameLoop, waitForCancel)

clearAll()
writeCentered(monitor, "Game Stopped", colors.white, colors.red)
print("Cancel button pressed - game stopped.")
