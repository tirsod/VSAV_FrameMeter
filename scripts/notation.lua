
local notation = "j.HP >> 2LP >> 2MP xx 236.PP (4 hits) xx P"
local terms = {
    {"  links", ">>"},
    {"  links", ">"},
    {"  chains", "-"},
    {"  cancels", "xx"}
}

local function create_substep(steplist, reps)
    local substep = {
        steps = steplist,
        repeats = reps
    }
    return substep
end

local function create_step(str)
    step = {
        direction = "",
        move = "",
        dash = 0,
        jumping = false,
        crouching = false,
        close = false,
        charge = "",
        motion = false,
        term = false,
        multihit = 0
    }

    -- For multihits
    for token in string.gmatch(str, "(%d+)hit") do
        step.multihit = token + 0
        return step
    end

    -- Catches cancels, links, chains
    for _, term in ipairs(terms) do
        if str == term[2] then
            step.move = term[1]
            step.term = true
            return step
        end
    end

    -- Charge moves
    for charge in string.gmatch(str, "(%d~%d)") do
        step.charge = charge
        step.direction = charge
    end

    -- If move isn't charge, directionals.
    if step.charge == "" then
        for directional in str.gmatch(str, "%d+") do
            step.direction = directional
            if (string.len(directional) == 2) then
                print("IS THIS A DASH?!?!? ".."["..directional.."]")
                if directional == "66" then step.dash = 6 end -- Forward dash
                if directional == "44" then step.dash = 4 end -- Backdash
            end
            if (string.len(directional) > 2) then
                step.motion = true
            end
        end
    end

    -- BUTTONS!
    if string.match(str, "^j%.") then
        step.jumping = true
    end

    if string.match(str, "^c%.") then
        step.close = true
    end

    for move in str.gmatch(str, "%a+") do
        step.move = move
    end

    return step
end


local function unify_multi_hits(str)
    local replacements = {}

    local replaces = 1
    for token in string.gmatch(str, "(. hit)") do
        local replacewith = string.gsub(token, " ", "")

        replacements[replaces] = {
            token,
            replacewith
        }
        replaces = replaces + 1
    end

    for _, rep in ipairs(replacements) do
        if rep[1] and rep[2] then
            str = string.gsub(str, rep[1], rep[2])
        end
    end

    return str
end

local function split_string(str)
    local strings = {}
    local ind = 1

    print("Splitting string: "..str)

    str = unify_multi_hits(str)
    print("Unified: "..str)

    for token in string.gmatch(str, "[^%s]+") do
        strings[ind] = token
        ind = ind+1
    end
    return strings
end

local function parse_notation(str)
    local strings = split_string(str)
    return strings
end

local function combo_trial_from_notation(notation)
    local parsed = parse_notation(notation)
    local combo_trial = {}
    local combo_move_ind = 1
    for _, val in ipairs(parsed) do
        step = create_step(val)
        --print ("creating step for "..val)
        if (step.multihit > 1) then
            combo_trial[combo_move_ind-1].multihit = step.multihit
        else
            combo_trial[combo_move_ind] = step
            combo_move_ind = combo_move_ind + 1
        end
    end
    return combo_trial
end

local function sleep (a) 
    local sec = tonumber(os.clock() + a); 
    while (os.clock() < sec) do 
    end 
end

local function print_combo_trial(combo_trial)
    print("Generated combo trial:")
    for index, step in ipairs(combo_trial) do
        sleep(.1)
        local multihitstr = ""
        local chargemovestr = ""
        local jumpingstr = ""
        local motioninputstr = ""
        local movementstr = step.direction
        if (step.multihit > 1) then multihitstr = " (Must hit "..tostring(step.multihit).." times)" end
        if (step.charge ~= "") then chargemovestr = " (Charge move)" end
        if (step.jumping) then jumpingstr = "While jumping, " end
        if (step.motion) then motioninputstr = "(Motion) " end
        if (step.dash == 6) then movementstr = "(Forward Dash) 66" end
        if (step.dash == 4) then movementstr = "(Backdash) 44" end

        print(jumpingstr..motioninputstr..movementstr..step.move..chargemovestr..multihitstr)
    end
end

while true do
    local combo = ""
    print("FEED ME A STRAY COMBO: ")
    combo = io.read()
    print_combo_trial( combo_trial_from_notation(combo) )
end