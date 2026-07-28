
--CONFIG--

local pigs = {"pig1", "pig2"};
local speeds = {"slow", "med", "fast"};

--Cabling
local speedColors = {
  pig1_slow = colors.white,   pig1_med = colors.orange,  pig1_fast = colors.magenta,
  pig2_slow = colors.lightBlue, pig2_med = colors.yellow, pig2_fast = colors.lime,
  pig3_slow = colors.pink,    pig3_med = colors.gray,    pig3_fast = colors.lightGray,
  pig4_slow = colors.cyan,    pig4_med = colors.purple,  pig4_fast = colors.blue,
};

local finishCableSide = "left";

-- Map each pig to the color its finish plate pulses when triggered
local finishColors = {
  pig1 = colors.white,
  pig2 = colors.lightBlue,
  pig3 = colors.pink,
  pig4 = colors.cyan,
};

-- Plain redstone side for the wireless start transmitter
local startSide = "top";

--ENDCONFIG--

--Choose and random speed for each pig and set
local function pulseSpeedSelectors(rolledSpeeds)

    local mask = 0;

    for _, pig in ipairs(pigs) do

    --Set the actual speed
    local choice = speeds[math.random(1, 3)];
    rolledSpeeds[pig] = choice;
    mask = colors.combine(mask, speedColors[pig .. "_" .. choice]);
    end  

    --Output pig speed
    for pig, speed in pairs(rolledSpeeds) do
        print(pig .. " -> " .. speed);
    end


    --Pulse that output
    redstone.setBundledOutput(speedCableSide, mask);
    sleep(0.5);
    redstone.setBundledOutput(speedCableSide, 0);

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
        local mask = redstone.getBundledInput(finishCableSide)
        for _, pig in ipairs(pigs) do
            if colors.test(mask, finishColors[pig]) then
                return pig;
            end
        end
        sleep(0.05); -- check ~every tick
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


