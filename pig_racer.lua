
--CONFIG--

local pigs = {"pig1", "pig2"};
local speeds = {"slow", "fast"};

-- Map each pig+speed to a {relay, side} pair on the pig-speed relay.
-- Sides are arbitrary - sync them up with the actual Create contraption
-- in-game and adjust here if needed.
local relayLocation = "redstone_relay_76";
local speedOutputs = {
  pig1_slow = {relayLocation, "front"}, pig1_fast = {relayLocation, "left"},
  pig2_slow = {relayLocation, "right"}, pig2_fast = {relayLocation, "bottom"},
};
local firedOutputs = {};

-- World coordinates of each pig's lane, used to teleport them back to the
-- start once a race finishes.
local lanePositions = {
  pig1 = { start = { x = -556, y = 71, z = -153 }, finish = { x = -551, y = 71, z = -153 } },
  pig2 = { start = { x = -556, y = 71, z = -155 }, finish = { x = -551, y = 71, z = -155 } },
};

-- Colour used for each pig's monitor output / win screen.
local pigColors = {
  pig1 = colors.red,
  pig2 = colors.blue,
};

-- Real names of the pigs (from their name tags). CC:Tweaked can't read an
-- entity's name tag directly, so keep this in sync by hand whenever the
-- pigs get renamed.
local pigNames = {
  pig1 = "pig1",
  pig2 = "pig2",
};

--Monitor output
local monitor = peripheral.wrap("monitor_3");
if not monitor then
    print("Running without monitor");
end

--Printer output
local printer = peripheral.wrap("printer_0");
if not printer then
    print("Running without printer");
end

-- Both win sensors are wired directly to the computer.
local finishInputs = {
  pig1 = {"computer", "front"},
  pig2 = {"computer", "right"},
};

-- Direct computer redstone side that powers the Create fans, propelling
-- the pigs once their speeds have been rolled.
local startSide = "back";

-- Start button relay - front side triggers a new race. No cancel button
-- planned (no space for one), so a race always runs to completion once started.
local startButtonRelay = peripheral.wrap("redstone_relay_78");
local startButtonSide = "front";

--ENDCONFIG--

local relays = {};

local function getRelay(name)
    if name == "computer" then
        return redstone;
    end

    if not relays[name] then
        relays[name] = peripheral.wrap(name);
    end

    return relays[name];
end

local function setOut(target, value)
    local r = getRelay(target[1]);

    if r == redstone then
        redstone.setOutput(target[2], value);
    else
        r.setOutput(target[2], value);
    end
end

local function getIn(target)
    local r = getRelay(target[1]);
    if r == redstone then
        return redstone.getInput(target[2]);
    else
        return r.getInput(target[2]);
    end
end

--Monitor helpers (small scrolling log + a big win screen, like roulette.lua)
local monitorLine = 1;

local function outputInformation(text, color)
    if not monitor then
        print(text);
        return;
    end
    monitor.setTextScale(0.5);
    monitor.setTextColor(color or colors.white);
    monitor.setCursorPos(1, monitorLine);
    monitor.write(text);
    monitorLine = monitorLine + 1;
end

-- Splits `text` into lines of at most `maxWidth` characters, breaking on
-- word boundaries so words are never cut mid-word.
local function wrapText(text, maxWidth)
    if maxWidth < 1 then
        return { text }
    end
    local lines = {}
    local current = ""
    for word in text:gmatch("%S+") do
        local candidate = (current == "" and word) or (current.." "..word)
        if #candidate > maxWidth and current ~= "" then
            table.insert(lines, current)
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then
        table.insert(lines, current)
    end
    return lines
end

-- Clears the monitor and writes `text`, centered and word-wrapped to fit
-- the monitor's width at the given scale.
local function writeCentered(text, textColor, bgColor, scale)
    if not monitor then
        print(text);
        return;
    end
    monitor.setTextScale(scale or 1);
    monitor.setBackgroundColor(bgColor or colors.black);
    monitor.clear();
    local w, h = monitor.getSize();
    local lines = wrapText(text, w);
    local startY = math.floor((h - #lines) / 2) + 1;
    monitor.setTextColor(textColor or colors.white);
    for i, line in ipairs(lines) do
        local x = math.floor((w - #line) / 2) + 1;
        monitor.setCursorPos(x, startY + i - 1);
        monitor.write(line);
    end
end

local function showWinScreen(pig)
    local name = pigNames[pig] or pig;
    writeCentered(name:upper().." WINS!", colors.white, pigColors[pig] or colors.black, 2);
end

--Prints a small page with the winning pig's name on printer_0
local function printWinner(pig)
    if not printer then
        print("No printer found - could not print winner");
        return;
    end
    if not printer.newPage() then
        print("Printer out of paper/ink - could not print winner");
        return;
    end
    printer.setPageTitle("Race Winner");
    printer.write((pigNames[pig] or pig).." wins!");
    printer.endPage();
end

local function showStartPrompt()
    writeCentered("Press the button to start", colors.white, colors.black, 2);
end

local function clearMonitor()
    if not monitor then return end
    monitor.setTextScale(0.5);
    monitor.setBackgroundColor(colors.black);
    monitor.clear();
    monitorLine = 1;
end

--Choose a random speed for each pig and pulse the matching relay side
local function pulseSpeedSelectors(rolledSpeeds)
    firedOutputs = {};

    for _, pig in ipairs(pigs) do
        local choice = speeds[math.random(1, 2)]
        rolledSpeeds[pig] = choice
        local target = speedOutputs[pig .. "_" .. choice]
        setOut(target, true)
        table.insert(firedOutputs, target)
    end

    for pig, speed in pairs(rolledSpeeds) do
        outputInformation(pig .. " -> " .. speed, pigColors[pig])
    end
end

--Turns off every speed output that was fired this race
local function resetSpeedOutputs()
    for _, target in ipairs(firedOutputs) do
        setOut(target, false)
    end
end

--Blocks until the start button is pressed, then waits for release (debounce)
local function waitForStart()
    while true do
        os.pullEvent("redstone")
        if startButtonRelay.getInput(startButtonSide) then
            while startButtonRelay.getInput(startButtonSide) do
                os.pullEvent("redstone")
            end
            return
        end
    end
end

--Turns the Create fans on/off. Stays on for the whole race, not just a pulse.
local function startFans()
    redstone.setOutput(startSide, true);
end

local function stopFans()
    redstone.setOutput(startSide, false);
end

-- Runs a command via the Command Computer `commands` API, printing the
-- failure reason if it doesn't succeed.
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

-- Teleports whichever pig is sitting at `pig`'s lane finish point back to
-- that lane's start point.
local function teleportPigHome(pig)
    local lane = lanePositions[pig];
    local s, f = lane.start, lane.finish;
    runCommand(("execute as @e[type=minecraft:pig,x=%d,y=%d,z=%d,distance=..3] at @s run tp @s %d %d %d")
        :format(f.x, f.y, f.z, s.x, s.y, s.z));
end

-- Resets both pigs back to their lane starts once the race is over.
local function resetPigs()
    for _, pig in ipairs(pigs) do
        teleportPigHome(pig);
    end
end

--Returns the winning pig once either finish sensor trips
local function waitForWinner()
    while true do
        for _, pig in ipairs(pigs) do
            if getIn(finishInputs[pig]) then
                return pig
            end
        end

        sleep(0.05)
    end
end

--Handle race
local function runRace()
    local chosenSpeeds = {}

    clearMonitor();
    outputInformation("Deciding speeds");
    pulseSpeedSelectors(chosenSpeeds);

    outputInformation("Starting race...");
    startFans();

    outputInformation("Waiting for winner...");
    local winner = waitForWinner();

    stopFans();
    resetSpeedOutputs();
    resetPigs();

    outputInformation("Winner: " .. (pigNames[winner] or winner), pigColors[winner]);
    printWinner(winner);
    return winner, chosenSpeeds;
end

--Main loop: wait for the start button, run a race, show the winner, repeat
while true do
    showStartPrompt();
    waitForStart();

    local winner, chosenSpeeds = runRace();

    showWinScreen(winner);
    sleep(3);
end
