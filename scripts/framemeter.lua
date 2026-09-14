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

img_noaction_prev = gd.createFromPng("images/framemeter/FMO_inactive.png"):gdStr()
img_startup_prev = gd.createFromPng("images/framemeter/FMO_startup.png"):gdStr()
img_active_prev = gd.createFromPng("images/framemeter/FMO_active.png"):gdStr()
img_recovery_prev = gd.createFromPng("images/framemeter/FMO_recovery.png"):gdStr()
img_hurt_prev = gd.createFromPng("images/framemeter/FMO_hurt.png"):gdStr()
img_projectile_prev = gd.createFromPng("images/framemeter/FMO_projectile.png"):gdStr()
img_invul_prev = gd.createFromPng("images/framemeter/FMO_invul.png"):gdStr()
img_nothrow_prev = gd.createFromPng("images/framemeter/FMO_nothrow.png"):gdStr()

img_skipped = gd.createFromPng("images/framemeter/FM_skipped.png"):gdStr()


local states = {
	{img_noaction, img_noaction_prev},
	{img_startup, img_startup_prev},
	{img_active, img_active_prev},
	{img_recovery, img_recovery_prev},
	{img_hurt, img_hurt_prev},
	{img_projectile, img_projectile_prev},
	{img_nothrow, img_nothrow_prev},
	{img_invul, img_invul_prev}
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
        attackbyte = function(addr) return memory.readbyte(addr + 0x20) end,
		supering  = function(addr) return memory.readbyte(addr + 0x006) == 0x12 end,
		hurt      = function(addr) return memory.readbyte(addr + 0x005) == 0x02 end,
		thrown    = function(addr) return memory.readbyte(addr + 0x005) == 0x06 end,
		hitfreeze = function(addr) return memory.readbyte(addr + 0x05C) ~= 0x00 end,
		knockdown = function(addr) return memory.readbyte(addr + 0x1A7) ~= 0 end,
		invulnerable = function(addr) return memory.readbyte(addr + 0x147) ~= 0 end,
		nothrow = function(addr) return memory.readbyte(addr + 0x143) ~= 0 end,
		delay = {startup = -1, atk_recover = 1, hit_recover = 1},
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
local log_length = log_drawn * 3
local log_position = 0
local idle_frames = 0
local max_idle_frames = 15

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
		player_state[p] = get_attack_state[super_mode](addr) or game.hurt(addr) or game.thrown(addr) or game.hitfreeze(addr, game.address[(p == 1 and 2) or 1]) or (game.superfreeze and game.superfreeze(addr, game.address[(p == 1 and 2) or 1]))
	end

	if any_true(player_state) then
		test_state = "action"
	else
		test_state = "idle"
		idle_frames = idle_frames + 1
	end

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

local function get_player_state(tick)

	local capture = vsav.capture(tick)

	-- -- -- -- -- -- probably does nothing! (it probably does.)
    --if game.address.projectile_slowdown and
	--	memory.readbyte(game.address[1] + 0x02) ~= 0x04 and memory.readbyte(game.address[2] + 0x02) ~= 0x04 then
	--	memory.writebyte(game.address.projectile_slowdown, 0) --disable projectile slowdown
	--end
	--if game.no_frameskip then
		--print("* disabling frameskip")
	--	game.no_frameskip() --disable frameskip
	--end

    local player = {{}, {}}
	for p = 1, 2 do --get the current status of the players from RAM
		local addr = game.address[p]
		local opp_addr = (p == 1 and game.address[2]) or game.address[1]
		player[p].attacking   = get_attack_state[super_mode](addr)
		player[p].hurt        = game.hurt(addr)
		player[p].thrown      = game.thrown(addr)
		player[p].hitfreeze   = game.hitfreeze(addr, opp_addr)
		player[p].superfreeze = game.superfreeze and game.superfreeze(addr, opp_addr)
		player[p].projectile  = player_owns_projectile(addr)
		player[p].attack_box  = bool(attack_box(addr) ~= 0)
		player[p].knockdown   = game.knockdown(addr)
		player[p].invulnerable= game.invulnerable(addr)
		player[p].nothrow     = game.nothrow(addr)
	end

	
	for p = 1, 2 do
		-- clear 2 frames ahead
		state_log[p][log_position+1%log_length] = 0
		state_log[p][log_position+2%log_length] = 0

		-- set current frame's state for each player @ log_position
		-- 
		if player[p].projectile then
			state_log[p][log_position] = 6	
		elseif player[p].invulnerable then
			state_log[p][log_position] = 8
		elseif player[p].nothrow then
			if globals.options.show_throw_invuln_timer then state_log[p][log_position] = 7 end
		elseif player[p].attack_box then
			state_log[p][log_position] = 3
		elseif player[p].hurt or player[p].knockdown then
			state_log[p][log_position] = 5
		elseif player[p].attacking then
			state_log[p][log_position] = 2

			-- Hacky little way of drawing the recovery frames.
			-- Checks if the previous frame was of type active(3), recovery(4), or projectile(6) and if so, sets the current frame to recovery(4)
			-- but only during "attacking" frames. (no accidentally setting idle frames as recovery)

			local previousState = state_log[p][log_position-1%log_length]
			if previousState == 3 or previousState == 4 or previousState == 6 then
				state_log[p][log_position] = 4
			end

		end

		-- (Meant to be used for logging frameskips. Not really useful.)

		--state_log[3][log_position] = 0
		--if (frameskip) then
		--	state_log[3][log_position] = 1
		--end

	end

	log_position = (log_position + 1) % log_length

end

-- Walks backwards (right to left) from the current log position to find the last idle frame,
-- The distance from the rightmost position [log_position] to the last idle frame is logged as [idle_offset]
-- The idle_offsets of both players are compared afterwards to find the frame advantage between the two players.
-- When a player was fully idle, the idle_offset is set to be equal to the current log_position.
-- (So if player 1 attacks and is busy for 10 frames,
-- And player 2 has been idle since frame 1,
-- Assuming log_position ended at 20,
-- this gives player 1 an idle_offset of 10 and player 2 an idle_offset of 20, giving player 1 a frame advantage of -10)

local function measure_player(player) -- Thanks, vscode

	local function at(offset)
		local index = ((log_position - offset - 1) % log_length)
		return state_log[player][index] or 0
	end

	local function is_idle_state(state)
		return state == 0 or state == 1 or state == 7
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
		elseif state == 2 then
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

	-- This used to draw skipped frames as a line between both frame meters.
	-- I don't think it's useful at all.

	--for i = startI, (startI + log_drawn - 1) % log_length do
	--	image = img_skipped
	--	if (state_log[3][i] ~= 0 and state_log[3][i] ~= nil) then
	--		gui.image(drawX + (i*4), drawY+16, image)
	--	end
    --end

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
		if (globals.options.mo_enable_frame_data) then
        	draw_meter()
		end
    end
}

return frameMeterModule