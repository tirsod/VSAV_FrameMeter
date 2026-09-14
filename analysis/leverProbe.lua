-- WHAT DOES THE LEVER READ AS, WHEN HOTKEY 2 IS PRESSED?
--
-- Left and Right stopped changing the standing position; down-left and
-- down-right still work (user, 2026-09-12). position.lua turns the pad into one
-- of six arrangements and the mapping has not been touched since it was written:
--
--   left            -> 2   |21------|   opponent at the left wall
--   down + left     -> 1   |12------|   I am at the left wall
--   right           -> 5   |------12|   opponent at the right wall
--   down + right    -> 6   |------21|   I am at the right wall
--   down            -> 4   |---21---|
--   nothing         -> 3   |---12---|
--
-- Since the arithmetic is unchanged, what reaches it must have changed. The two
-- failing cases are exactly the two with no Down in them, so the suspicion is
-- that Down reads as held when it is not - which would turn a plain Left into
-- the down-left arrangement and look like "Left does nothing new".
--
-- This reads the pad the same way position.lua does and prints what it sees,
-- so the answer is on screen while the lever is held.
--
-- Run INSTEAD of the training script:
--   analysis/run_lever_probe.bat        (double click)
--
-- What to do, once a round is up:
--   1. hold LEFT on its own. Read the "now" line.
--   2. hold DOWN+LEFT. Read it again.
--   3. hold RIGHT, then DOWN+RIGHT.
--   4. press Lua Hotkey 2 while holding each of the four. The "latched" line
--      keeps what was read on that press, so the lever can be let go before
--      looking.
--
-- What to look for: with LEFT alone, "d" must be false and mode must be 2. If d
-- is true there, the pad is reporting Down and the fault is upstream of the
-- arithmetic. If d is false and mode is 2, the reading is right and the fault is
-- in what happens after - which is the other half of position.lua.
local LOG = "lever_probe.log"
local file = nil
local latched = "(まだ押されていない)"
local lines = 0

-- WHAT HAPPENS AFTER THE PRESS, WHICH IS THE HALF STILL UNACCOUNTED FOR.
--
-- The reading turned out to be right: LEFT alone gives d=false and mode 2
-- (measured 2026-09-12). So the fault is in what the arrangement does with it,
-- and the only part of that visible from outside is where the two characters
-- actually end up. Their X is recorded for a while after each press.
--
-- Same addresses position.lua uses: $10 is the integer half of a 16.16
-- position, and the walls it clamps to are 280 and 1000.
local P1 = 0xFF8400
local P2 = 0xFF8800
local X = 0x10
local WALL_L, WALL_R = 280, 1000
local watch_left = 0
local watch_mode = 0

local function sw(v)
	if v >= 0x8000 then return v - 0x10000 end
	return v
end
local function getx(base) return sw(memory.readword(base + X)) end

local FIGURE = { "|12------|", "|21------|", "|---12---|",
                 "|---21---|", "|------12|", "|------21|" }

-- Copied from position.lua deliberately, not required from it: what is being
-- measured is what this arithmetic sees, so it has to be the same arithmetic.
local function read_pad()
	local ok, j = pcall(joypad.get)
	if not ok or j == nil then return nil end
	return {
		u = j["P1 Up"] == true,
		d = j["P1 Down"] == true,
		l = j["P1 Left"] == true,
		r = j["P1 Right"] == true,
	}
end

local function lever_mode(p)
	if p == nil then return 3 end
	if p.l and not p.r then if p.d then return 1 else return 2 end end
	if p.r and not p.l then if p.d then return 6 else return 5 end end
	if p.d then return 4 end
	return 3
end

local function describe(p)
	if p == nil then return "joypad.get() が使えない" end
	local held = {}
	if p.u then held[#held + 1] = "Up" end
	if p.d then held[#held + 1] = "Down" end
	if p.l then held[#held + 1] = "Left" end
	if p.r then held[#held + 1] = "Right" end
	local m = lever_mode(p)
	return string.format("held[%s]  u=%s d=%s l=%s r=%s  -> mode %d %s",
		table.concat(held, "+"), tostring(p.u), tostring(p.d),
		tostring(p.l), tostring(p.r), m, FIGURE[m] or "?")
end

-- EVERY HOTKEY, NOT JUST NUMBER 2.
--
-- Two runs came back with the latch untouched: the press was not reaching the
-- callback at all (user, 2026-09-12). In the tool it clearly does reach it -
-- down+left rearranges the pair - so the question is which index the key the
-- player presses actually is. Registering all eight and showing which one
-- fires answers that without another round trip.
local fired = {}
local last_fired = 0

local function on_hotkey(n)
	return function()
		fired[n] = (fired[n] or 0) + 1
		last_fired = n
		local p = read_pad()
		latched = "hotkey " .. tostring(n) .. "  " .. describe(p)
		watch_mode = lever_mode(p)
		watch_left = 200
		if file == nil then file = io.open(LOG, "a") end
		if file then
			file:write(string.format("f=%d hotkey%d  %s  P1x=%d P2x=%d\n",
				emu.framecount(), n, describe(p), getx(P1), getx(P2)))
			file:flush()
			lines = lines + 1
		end
	end
end

if input ~= nil and input.registerhotkey ~= nil then
	for _n = 1, 8 do input.registerhotkey(_n, on_hotkey(_n)) end
end

-- The slide writes X every frame, so only the frames on which it changed are
-- worth a line. A press that does nothing at all leaves none.
local last_pair = nil
emu.registerbefore(function()
	if watch_left <= 0 then return end
	watch_left = watch_left - 1
	local a, b = getx(P1), getx(P2)
	local pair = tostring(a) .. "," .. tostring(b)
	if pair ~= last_pair then
		last_pair = pair
		if file then
			file:write(string.format("  f=%d mode=%d P1x=%4d P2x=%4d  %s\n",
				emu.framecount(), watch_mode, a, b,
				(a <= b) and "P1 left" or "P2 left"))
		end
	end
	if watch_left == 0 and file then
		file:write(string.format("  -- end mode=%d P1x=%d P2x=%d (walls %d / %d)\n",
			watch_mode, getx(P1), getx(P2), WALL_L, WALL_R))
		file:flush()
	end
end)

gui.register(function()
	local p = read_pad()
	gui.text(8, 8, "lever probe   Lua Hotkey 2 で latch   " .. tostring(lines) .. " 件記録")
	gui.text(8, 18, "now:     " .. describe(p))
	gui.text(8, 28, "latched: " .. latched)
	gui.text(8, 38, string.format("P1x=%d P2x=%d   wall %d / %d",
		getx(P1), getx(P2), WALL_L, WALL_R))
	local _f = {}
	for _n = 1, 8 do
		if fired[_n] ~= nil then
			_f[#_f + 1] = tostring(_n) .. "x" .. tostring(fired[_n])
		end
	end
	gui.text(8, 48, "hotkey が来た番号: " ..
		((#_f > 0) and table.concat(_f, " ") or "まだ 1 つも来ていない"))
	gui.text(8, 58, "押したあと 200 フレーム、X の動きを記録する")
end)

emu.registerexit(function()
	if file then file:close() file = nil end
end)
