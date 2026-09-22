-- Frame meter module by tirsod - based on vampiresavior001's VSAV Trainer w/ newest tickrate display
-- CHANGES
-- 0.1: Meter display with idle, startup, active, "recovery", projectile, and hurt frames. advantage display w/ colored text.
-- 0.2 (current): throw invulnerability, invulnerable frames display. Logs data only after match has started. Tidied up state arrays
-- -- throw invulnerability frame is logged only if the respective display is enabled in "other"

-- Loads the framemeter images
require "gd"
img_noaction = gd.createFromPng("images/framemeter/FM_inactive.png"):gdStr()
img_startup = gd.createFromPng("images/framemeter/FM_startup.png"):gdStr()
img_active = gd.createFromPng("images/framemeter/FM_active.png"):gdStr()
img_recovery = gd.createFromPng("images/framemeter/FM_recovery.png"):gdStr()
img_hurt = gd.createFromPng("images/framemeter/FM_hurt.png"):gdStr()
img_projectile = gd.createFromPng("images/framemeter/FM_projectile.png"):gdStr()
img_invul = gd.createFromPng("images/framemeter/FM_invul.png"):gdStr()
img_nothrow = gd.createFromPng("images/framemeter/FM_nothrow.png"):gdStr()
img_movement = gd.createFromPng("images/framemeter/FM_move.png"):gdStr()


img_noaction_prev = gd.createFromPng("images/framemeter/FMO_inactive.png"):gdStr()
img_startup_prev = gd.createFromPng("images/framemeter/FMO_startup.png"):gdStr()
img_active_prev = gd.createFromPng("images/framemeter/FMO_active.png"):gdStr()
img_recovery_prev = gd.createFromPng("images/framemeter/FMO_recovery.png"):gdStr()
img_hurt_prev = gd.createFromPng("images/framemeter/FMO_hurt.png"):gdStr()
img_projectile_prev = gd.createFromPng("images/framemeter/FMO_projectile.png"):gdStr()
img_invul_prev = gd.createFromPng("images/framemeter/FMO_invul.png"):gdStr()
img_nothrow_prev = gd.createFromPng("images/framemeter/FMO_nothrow.png"):gdStr()
img_movement_prev = gd.createFromPng("images/framemeter/FMO_move.png"):gdStr()

img_skipped = gd.createFromPng("images/framemeter/FM_skipped.png"):gdStr()


local states = {
	{img_noaction, img_noaction_prev},			-- 0/1/nil
	{img_startup, img_startup_prev},			-- 2
	{img_active, img_active_prev},				-- 3
	{img_recovery, img_recovery_prev},			-- 4
	{img_hurt, img_hurt_prev},					-- 5
	{img_projectile, img_projectile_prev},		-- 6
	{img_nothrow, img_nothrow_prev},			-- 7
	{img_invul, img_invul_prev},				-- 8
	{img_movement, img_movement_prev}			-- 9
}

-- Screen height for drawing the frame meter.
-- Why does emu.getscreenheight() different values on startup & when the .lua is loaded manually?
local _height = 220

-- From: framedata.lua -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
local tickData = require "./scripts/tickData"
local vsav = require "./scripts/tickDataVsav"

local game, count
local super_mode = false
local profile = {
	{
		games = {"vsav","vhunt2","vsav2"},
		address = {0xFF8400, 0xFF8800},
		PROJ = 0xFF9400,
		PROJ_COUNT = 32,
        attacking = function(addr) return memory.readbyte(addr + 0x105) == 0x01 end,

        status_1 = function(addr) return memory.readbyte(addr + 0x05) end,
		hurt      = function(addr) return memory.readbyte(addr + 0x005) == 0x02 end,
		thrown    = function(addr) return memory.readbyte(addr + 0x005) == 0x06 end,
		throwing  = function(addr) return memory.readbyte(addr + 0x005) == 0x04 end,

		status_2 = function(addr) return memory.readbyte(addr + 0x06) end,
		walking = function(addr) return memory.readbyte(addr + 0x06) == 0x04 end,
		supering  = function(addr) return memory.readbyte(addr + 0x06) == 0x12 end,
		dfreturn  = function(addr) return memory.readbyte(addr + 0x06) == 0x1A end,

		hitfreeze = function(addr) return memory.readbyte(addr + 0x05C) ~= 0x00 end,
		knockdown = function(addr) return memory.readbyte(addr + 0x1A7) ~= 0 end,
		invulnerable = function(addr) return memory.readbyte(addr + 0x147) ~= 0 end,
		nothrow = function(addr) return memory.readbyte(addr + 0x143) ~= 0 end,
		
		jump = function(addr) 	 return memory.readbyte(addr + 0x006) == 0x06 end,
		dash = function(addr) 	 return memory.readbyte(addr + 0x006) == 0x14 end,
		stunned = function(addr) return memory.readbyte(addr + 0x006) == 0x02 end
	}
}
for _, game in ipairs(profile) do
	game.update = game.update or {func = emu.registerafter, cycle = 1}
end

any_true = function(condition)
	for n = 1, #condition do
		if condition[n] == true then return true end
	end
end

-- Set logging variables & log length
local log_drawn = 90
local log_length = log_drawn * 128
local log_position = 0
local idle_frames = 0
local max_idle_frames = 5

-- State log format: 0/nil/1 = idle, 2 = startup, 3 = active, 4 = recovery, 5 = hurt, 6 = projectile
-- Third array is for skipped frames, 0 = not skipped, 1 = skipped
local state_log = {{},{},{}}
local test_state = "actionable"

local get_attack_state = {
	[false] = function(addr) --non-super mode
		return game.attacking(addr)
	end,

	[true] = function(addr) --super mode
		return game.supering(addr)
	end,
}

local function refresh_meter()
	local player_state = {false, false}

	for p = 1, 2 do
		local addr = game.address[p]
		player_state[p] = 
			(get_attack_state[super_mode](addr) and (not game.walking(addr)))
			or game.hurt(addr)
			or game.thrown(addr)
			or game.hitfreeze(addr, game.address[(p == 1 and 2) or 1])
			or (game.superfreeze and game.superfreeze(addr, game.address[(p == 1 and 2) or 1]))
			or game.invulnerable(addr)
			or globals.options.fm_movement_data and (game.dash(addr) or game.jump(addr))
			or game.dfreturn(addr)
	end

	if any_true(player_state) then
		test_state = "action"
	else
		test_state = "idle"
		idle_frames = idle_frames + 1
	end

	--gui.text(128, 64, test_state)

	if idle_frames > max_idle_frames and test_state == "action" then
		idle_frames = 0
		log_position = 0
		state_log = {{},{},{}}
	end
end

local function bool(v) return v == true end

-- Borrowed from tickDataVsav.lua

local function attack_box(base)
	local cel = memory.readdword(base + 0x1C)
	if cel == nil or cel == 0 then return 0 end
	return memory.readbyte(cel + 0x0A)
end

local function player_owns_projectile(player_address)
	local PROJ_COUNT = game.PROJ_COUNT
	local PROJ = game.PROJ

	for i = 0, PROJ_COUNT - 1 do
		local b = PROJ + i * 0x100
		if memory.readword(b) > 0x0100 and memory.readbyte(b + 0x04) == 0x02 then
			local owner = memory.readword(b + 0x30)
			local id = attack_box(b)
			return owner == (player_address % 0x10000) and id ~= 0
    	end
  	end
	return false
end

local function get_player_objects()
	local player = {{}, {}}
	for p = 1, 2 do --get the current status of the players from RAM
		local addr = game.address[p]
		local opp_addr = (p == 1 and game.address[2]) or game.address[1]
		player[p].attacking   = get_attack_state[super_mode](addr)
		player[p].hurt        = game.hurt(addr)
		player[p].thrown      = game.thrown(addr)
		player[p].throwing 	  = game.throwing(addr)
		player[p].hitfreeze   = game.hitfreeze(addr, opp_addr)
		player[p].superfreeze = game.superfreeze and game.superfreeze(addr, opp_addr)
		player[p].projectile  = player_owns_projectile(addr)
		player[p].attack_box  = bool(attack_box(addr) ~= 0)
		player[p].knockdown   = game.knockdown(addr)
		player[p].invulnerable= game.invulnerable(addr)
		player[p].nothrow     = game.nothrow(addr)
		
		player[p].jump		  = game.jump(addr)
		player[p].dash	      = game.dash(addr)
		player[p].movement 	  = player[p].jump or player[p].dash
		player[p].stunned	  = game.stunned(addr)
		player[p].status_1	  = game.status_1(addr)
		player[p].status_2	  = game.status_2(addr)
		player[p].walking 	  = game.walking(addr)
		player[p].dfreturn 	  = game.dfreturn(addr)
	end
	return player
end


local previous_player = {{}, {}} 

local function get_player_state(tick)

    local player = get_player_objects()

	for p = 1, 2 do
		-- clear 2 frames ahead
		-- -- This was kinda my fuck up but we can come back from this.
		--state_log[p][log_position+1%log_length] = 0
		--state_log[p][log_position+2%log_length] = 0

		-- we're so back
		-- (we're not)
		-- oh yeah we are
		if (log_position > log_drawn) then
			state_log[p][((log_position-log_drawn)+4)%log_length] = nil
			state_log[p][((log_position-log_drawn)+3)%log_length] = nil
			state_log[p][((log_position-log_drawn)+2)%log_length] = nil
		end

		-- set current frame's state for each player @ log_position
		
		previousState = state_log[p][log_position-1%log_length]

		priolist = {
			{player[p].invulnerable, 8},
			{player[p].nothrow and globals.options.fm_no_throw, 7},
			{player[p].attack_box, 3},
			{player[p].hurt or player[p].knockbox, 5},
			{player[p].dfreturn, 4},
			{player[p].attacking and (previousState == 3 or previousState == 4 or previousState == 6) and (not player[p].walking), 4},
			{player[p].attacking and (not player[p].walking or player[p].throwing), 2},
			{player[p].projectile, 6},
			{player[p].movement and globals.options.fm_movement_data, 9},
		}

		state_log[p][log_position] = 0
		for _, item in ipairs(priolist) do
			if item[1] then
				state_log[p][log_position] = item[2]
				break
			end
		end
	end

	log_position = (log_position + 1) % log_length
	previous_player = player

end

local function measure_player(player)

	local function at(offset)
		local index = ((log_position - offset - 1) % log_length)
		return state_log[player][index] or 0
	end

	local function is_idle_state(state)
		return state == 0 or state == 1 or state == 7 or state == 6
	end

	local idle_offset = nil
	for offset = 1, log_length - 1 do
		if is_idle_state(at(offset)) and not is_idle_state(at(offset + 1)) then
			idle_offset = offset
			break
		end
	end

	if idle_frames < max_idle_frames then 
		return "--", "--", "--", nil
	end
	if (idle_offset == nil) then
		idle_offset = log_position
	end

	local recovery, active, startup = 0, 0, 0
	local offset = idle_offset + 1
	while true do
		local state = at(offset)
		if state == 4 then
			recovery = recovery + 1
		elseif state == 3 then
			active = active + 1
		elseif state == 2 or state == 9 then
			startup = startup + 1
		elseif is_idle_state(state) then
			break
		else
			break
		end
		offset = offset + 1
	end
	local total = (startup + active + recovery)
	return tostring(startup), tostring(total), tostring(recovery), idle_offset
end

function draw_meter()

	-- Why is the meter drawn twice? To show the looping blocks of 90 frames.
	-- See here: https://imgur.com/a/ZXt4ffZ

    drawX = 8
    drawY = _height - 64

	-- -- The frame meter draws 90 frames to screen (log_drawn), but the log itself is 270 frames long (log_length = log_drawn * 3)
	-- -- The drawing is then divided into 3 blocks of 90 frames. The current block is drawn first, fully colored,
	-- -- The previous block is drawn afterwards, ahead of the current position but with a different set of darker images.

	-- This draws the current block of 90 frames.

	local block_start = math.floor(log_position / log_drawn) * log_drawn
	for player = 1, 2 do -- Draw meter for each chara
		local xx = drawX
		for offset = 0, log_drawn - 1 do
			local i = (block_start + offset) % log_length
			xx = i%log_drawn * 4

			local image = states[1][1]
			local st = state_log[player][i]
			local state_entry = states[st]
			if state_entry and state_entry[1] ~= nil then
				image = state_entry[1]
			end
			gui.image(drawX + xx, drawY + (10*player), image)
        end
    end

	-- This draws the previous block, "behind" the frames that are currently being logged. 

	local block = math.floor(log_position / log_drawn)
	block = (block - 1) % (log_length/log_drawn)
	local block_start = block * log_drawn

	for player = 1, 2 do -- Draw meter for each chara
		local xx = drawX
		for offset = (log_position%log_drawn), log_drawn - 1 do
			local i = (block_start + offset) % log_length
			xx = (i%log_drawn) * 4

			local image = states[1][2]
			local st = state_log[player][i]
			local state_entry = states[st]
			if state_entry and state_entry[2] ~= nil then
				image = state_entry[2]
				gui.image(drawX + xx, drawY + (10*player), image)
			end
        end
    end

	-- String handling for the frame display.

	local startup1, total1, recovery1, zero1 = measure_player(1)
	local startup2, total2, recovery2, zero2 = measure_player(2)
	local advantage1, advantage2 = "--", "--"
	local plus = 0 -- 0 = neutral, 1 = player 1 has advantage, 2 = player 2 has advantage

	if zero1 ~= nil or zero2 ~= nil then
		if zero1 == nil then zero1 = 0 end
		if zero2 == nil then zero2 = 0 end
		advantage1 = tostring(zero1 - zero2)
		advantage2 = tostring(zero2 - zero1)
		plus = 1
		if (zero2 - zero1 > 0) then
			plus = 2
		end
	end

	local measure1 = string.format("Startup %s / Total %s / Recovery %s / Advantage ", startup1, total1, recovery1)
	local measure2 = string.format("Startup %s / Total %s / Recovery %s / Advantage ", startup2, total2, recovery2)

	local adv1 = string.format("%s", advantage1)
	local adv2 = string.format("%s", advantage2)

	-- Draw measurement string
	gui.text(drawX + (4*1), drawY+2, measure1, "#FFFFFF")
	gui.text(drawX + (4*1), drawY+28, measure2, "#FFFFFF")

	-- Draw frame advantage, colored 
	local adv_neutral = "#FFFFFF"
	local adv_positive = "#00BEFF"
	local adv_negative = "#F64100"

	-- Sets color for each player's frame advantage.
	c1, c2 = adv_neutral, adv_neutral
	if (plus == 1) then
		c1 = adv_positive
		c2 = adv_negative
	elseif (plus == 2) then
		c1 = adv_negative
		c2 = adv_positive
	end

	-- Draw frame advantage string
	gui.text(drawX + (4*1) + string.len(measure1)*4, drawY+2, adv1, c1)
	gui.text(drawX + (4*1) + string.len(measure2)*4, drawY+28, adv2, c2)

	-- Draw player 1/player 2 labels
	gui.text(drawX + (4*82), drawY+2, "Player 1", "#FFFFFF")
	gui.text(drawX + (4*82), drawY+29, "Player 2", "#FFFFFF")

end

-- update. Called with the cpu's ticks.
local freezeNextFrame = false
local function update(tick)

	--[[local player = get_player_objects()
	
	local P1 = 0xFF8400
	local _cel = memory.readdword(P1 + 0x1C) or 0

	Debug prints
	gui.text(64, 64, 
	"player1 jump "..tostring(player[1].jump)
	.."\nplayer1 dash "..tostring(player[1].dash)
	.."\n player1 attacking "..tostring(player[1].attacking)
	.."\n player1 stat1 "..tostring(player[1].status_1)
	.."\n player1 stat2 "..tostring(player[1].status_2)
	.."\n player1 walking "..tostring(player[1].walking)
	.."\n player1 test "..tostring( memory.readword(P1 + 0X1B8) )
	)]]

	if not freezeNextFrame then
		refresh_meter()
		if (idle_frames < max_idle_frames and globals.game_state.match_begun) then
			get_player_state(tick)
		end
	end

	-- Don't draw any new frames to the meter if the game is frozen for dramatic effect.
	freezeNextFrame = false
	if game.hitfreeze(game.address[1]) or game.hitfreeze(game.address[2]) then
		freezeNextFrame = true
	end
end

local subscription_generation = 0
local frameMeterModule = {
    ["registerStart"] = function()
		game = nil

		-- subscription generation borrowed from framedata.lua
		subscription_generation = subscription_generation + 1
		local mine = subscription_generation
		globals.truth.ticker:subscribe(function(tick)
			if mine == subscription_generation then
				if game ~= nil then update(tick, rawState) end
			end
		end)

		for n, module in ipairs(profile) do
			for m, shortname in ipairs(module.games) do
				if emu.romname() == shortname or emu.parentname() == shortname then
					game = module
					if fba and (emu.sourcename() == "CPS1" or emu.sourcename() == "CPS2") then
						print("Warning: FBA gives inaccurate results for CPS1/CPS2.")
					end
					if game.supering then
						print("Lua hotkey 2: toggle normal/super-only mode")
					end
					if game.no_frameskip then
						print("* disabling frameskip")
					end
					if game.address.projectile_slowdown then
						print("* disabling projectile slowdown")
					end
					return
				end
			end
		end

		print("not prepared for " .. emu.romname() .. " frame data")
	end,
    ["guiRegister"] = function()
		if (globals.options.display_frame_meter) then
        	draw_meter()
		end
    end
}

return frameMeterModule