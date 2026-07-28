
--CONFIG--

local pigs = {"pig1", "pig2"};
local speeds = {"slow", "fast"};

-- Map each pig+speed to a {relay, side} pair
-- check your actual peripheral name with peripheral.getNames()
local relayLocation = "back";
local speedOutputs = {
  pig1_slow = {relayLocation, "top"}, pig1_fast = {relayLocation, "left"},
  pig2_slow = {relayLocation, "right"},  pig2_fast = {relayLocation, "back"},
};
local firedOutputs = {};

--Monitor outout
local monitor = peripheral.find("monitor");
if not monitor then
    print("Running without monitor");
else
    monotir.setTextScale(0.5)
    monitor.clear();
end

local finishInputs = {
  pig1 = {"computer", "left"},
  pig2 = {"computer", "right"},
};

-- Plain redstone side for the wireless start transmitter
local startSide = "top";

--ENDCONFIG--

local relays = {};

local monitorLine = 1;
local function outputInformation(string)
    if not monitor then
        print(string);
    else
        monitor.setCursorPos(1, monitorLine);
        monitor.write(string);
        monitorLine = monitorLine + 1;
    end
end

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

--Choose and random speed for each pig and set
local function pulseSpeedSelectors(rolledSpeeds)

    for _, pig in ipairs(pigs) do
        local choice = speeds[math.random(1, 2)]
        rolledSpeeds[pig] = choice
        local target = speedOutputs[pig .. "_" .. choice]
        setOut(target, true)
        table.insert(firedOutputs, target)
    end

    --Print speeds
    for pig, speed in pairs(rolledSpeeds) do
        outputInformation(pig .. " -> " .. speed)
    end
    
end

--Start race
local function fireStart()
    redstone.setOutput(startSide, true);
    sleep(0.5);
    redstone.setOutput(startSide, false);
end

--Returns the winner (waiting for the winner)
local function waitForWinner()

    --Hold until there's a winner
    while true do

        for _, pig in ipairs(pigs) do
            if getIn(finishInputs[pig]) then
                return pig
            end
        end

        sleep(0.05)
    end   

    --Reset speeds
    for _, target in ipairs(firedOutputs) do
        setOut(target, false)
    end

end

--Handle race
local function runRace()
    local chosenSpeeds = {}

    outputInformation("Deciding speeds");
    pulseSpeedSelectors(chosenSpeeds);

    outputInformation("Starting race...");
    fireStart();

    outputInformation("Waiting for winner...");
    local winner = waitForWinner();

    outputInformation("Winner: " .. winner);
    return winner, chosenSpeeds;

end

--Run race
local winner, chosenSpeeds = runRace();

sleep(2);

if monitor then
    monitor.clear();
end

