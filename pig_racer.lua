
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
  pig2 = {"computer", "left"},
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

local function showWinScreen(pig)
    local name = pigNames[pig] or pig;
    if not monitor then
        print(name .. " wins!");
        return;
    end
    monitor.setTextScale(2);
    monitor.setBackgroundColor(pigColors[pig] or colors.black);
    monitor.clear();
    local w, h = monitor.getSize();
    local text = name:upper().." WINS!";
    local x = math.floor((w - #text) / 2) + 1;
    local y = math.floor(h / 2) + 1;
    monitor.setCursorPos(x, y);
    monitor.setTextColor(colors.white);
    monitor.write(text);
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

--Start race
local function fireStart()
    redstone.setOutput(startSide, true);
    sleep(0.5);
    redstone.setOutput(startSide, false);
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
    fireStart();

    outputInformation("Waiting for winner...");
    local winner = waitForWinner();

    resetSpeedOutputs();

    outputInformation("Winner: " .. (pigNames[winner] or winner), pigColors[winner]);
    printWinner(winner);
    return winner, chosenSpeeds;
end

--Main loop: wait for the start button, run a race, show the winner, repeat
clearMonitor();
while true do
    outputInformation("Waiting for start button...");
    waitForStart();

    local winner, chosenSpeeds = runRace();

    showWinScreen(winner);
    sleep(3);
    clearMonitor();
end
