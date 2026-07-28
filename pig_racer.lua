
--CONFIG--

local pigs = {"pig1", "pig2"};
local speeds = {"slow", "fast"};

-- Map each pig+speed to a {relay, side} pair
-- check your actual peripheral name with peripheral.getNames()
local speedOutputs = {
  pig1_slow = {"relay1", "top"}, pig1_fast = {"relay1", "left"},
  pig2_slow = {"relay1", "right"},  pig2_fast = {"relay1", "back"},
};

local finishInputs = {
  pig1 = {"computer", "left"},
  pig2 = {"computer", "right"},
};

-- Plain redstone side for the wireless start transmitter
local startSide = "top";

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

--Choose and random speed for each pig and set
local function pulseSpeedSelectors(rolledSpeeds)
    local firedOutputs = {}

    for _, pig in ipairs(pigs) do
        local choice = speeds[math.random(1, 2)]
        rolledSpeeds[pig] = choice
        local target = speedOutputs[pig .. "_" .. choice]
        setOut(target, true)
        table.insert(firedOutputs, target)
    end

    for pig, speed in pairs(rolledSpeeds) do
        print(pig .. " -> " .. speed)
    end

    sleep(0.5)

    for _, target in ipairs(firedOutputs) do
        setOut(target, false)
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

    print("Deciding speeds");
    pulseSpeedSelectors(chosenSpeeds);

    print("Starting race...");
    fireStart();

    print("Waiting for winner...");
    local winner = waitForWinner();

    print("Winner: " .. winner);
    return winner, chosenSpeeds;

end

--Run race
local winner, chosenSpeeds = runRace();


