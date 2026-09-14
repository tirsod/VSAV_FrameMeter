-- ONE PRESS, ONE ARRANGEMENT - EVEN THOUGH THE HOTKEY REPEATS.
--
-- FBNeo calls a Lua hotkey callback for as long as the key is held. A probe
-- that registered all eight counted 38 firings of hotkey 2 in a session of a
-- few presses (measured 2026-09-12). position.lua acted on every one, and
-- place() rebuilds its step list from scratch - so any arrangement needing
-- more than one step never reached its second.
--
-- The arrangements that need three steps are the ones that EXCHANGE the pair:
-- lever left or right, from a start where the player is already on the left.
-- Down+left from that start needs one step and worked, which is why this read
-- as "left and right stopped working, diagonals are fine".
--
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_position_hotkey.lua
local P1, P2 = 0xFF8400, 0xFF8800
local X = 0x10

local ram = {}
local function setx(base, v) ram[base + X] = v % 0x10000 end
local function getx(base)
	local v = ram[base + X] or 0
	if v >= 0x8000 then return v - 0x10000 end
	return v
end

local pad = {}
local hotkey = nil
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	writebyte = function(a, v) ram[a] = v end,
	writeword = function(a, v) ram[a] = v end,
}
local frame = 0
emu = { framecount = function() return frame end }
gui = { text = function() end }
input = { registerhotkey = function(n, f) if n == 2 then hotkey = f end end }
joypad = { get = function() return pad end, set = function() end }

globals = {
	hotkeys_armed = true,
	options = { stage_position = 4 },   -- middle, so nothing is pending
	_input = pad,
}

-- THIS TEST MUST NOT WRITE THE TRACE LOG.
--
-- position.lua's diagnostic trace appends to position_slide.log, and so this
-- test was appending to the same file the emulator writes. Two analyses were
-- then made of a log that was mostly this test's own output - the frame
-- numbers 21 / 241 / 461 / 693 in it are this file's 20 idle frames plus 200
-- per case, not anything the game did (2026-09-13). Swallow the write.
local real_open = io.open
io.open = function(name, mode)
	if mode == "a" or mode == "w" then return nil end
	return real_open(name, mode)
end

local pos = dofile("scripts/position.lua")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

want("hotkey 2 が登録されている", type(hotkey), "function")
want("round_ready がある", type(pos.round_ready), "function")

-- The round has to be "on screen" before a slide is allowed. position.lua sets
-- that from watching X settle, so let it watch a still pair for a while.
local function idle(n)
	for _ = 1, n do frame = frame + 1 pos.registerBefore() end
end

-- P1 on the left, P2 on the right - the ordinary start, and the one where
-- "lever left" has to exchange the two.
local function reset()
	setx(P1, 400)
	setx(P2, 700)
	globals.options.stage_position = 4
	ram[P1 + 0x05] = 0
	ram[P1 + 0x06] = 0
	pad["P1 Left"] = nil
	pad["P1 Right"] = nil
	pad["P1 Down"] = nil
	idle(20)
end

-- Held left: mode 2, |21------|, which wants P2 at the left wall and P1 beside
-- it. P1 starts on the left, so the pair has to be exchanged first.
--
-- AND THE CHARACTER IS WALKING WHILE THE LEVER IS HELD. $06 = 0x04, measured
-- on 2026-09-10. Without this the test could not see the bug it exists for:
-- slide_allowed() asked for $06 == 0x00, so holding left refused the very
-- press that holding left is for.
local function hold_left()
	pad["P1 Left"] = true
	pad["P1 Right"] = nil
	pad["P1 Down"] = nil
	ram[P1 + 0x05] = 0
	ram[P1 + 0x06] = 0x04
end

-- Down crouches instead of walking, and crouching stays at 0x00. This is why
-- the diagonals worked while the horizontals did not.
local function hold_down_with(dir)
	pad["P1 Left"] = nil
	pad["P1 Right"] = nil
	pad[dir] = true
	pad["P1 Down"] = true
	ram[P1 + 0x05] = 0
	ram[P1 + 0x06] = 0x00
end

reset()
hold_left()

-- THE PRESS, REPEATED THE WAY THE EMULATOR REPEATS IT.
--
-- One callback per frame for the whole run, which is what a held key does.
local moved_p1, moved_p2 = {}, {}
for _ = 1, 200 do
	frame = frame + 1
	hotkey()
	pos.registerBefore()
	moved_p1[#moved_p1 + 1] = getx(P1)
	moved_p2[#moved_p2 + 1] = getx(P2)
end

local p1_end, p2_end = getx(P1), getx(P2)
want("P2 が左に来た (|21------|)", p2_end < p1_end, true)
-- The wall is 280 and the pair cannot stand closer than about 30, so exact
-- arrival is not the test - being at the left end of the stage is.
want("左端まで行った", p2_end <= 340, true)

-- And the one that always worked must still work: down+left is one step.
reset()
hold_down_with("P1 Left")
for _ = 1, 200 do
	frame = frame + 1
	hotkey()
	pos.registerBefore()
end
want("下+左では P1 が左", getx(P1) < getx(P2), true)
want("こちらも左端", getx(P1) <= 340, true)

-- AND THE PLAYER CAN WALK AFTERWARDS, WITH THE KEY STILL HELD.
--
-- This is the symptom that was actually reported. Every firing used to call
-- place() again, so once the arrangement was finished the pair was re-pinned
-- to the same two pixels every frame and mask_input went on swallowing the
-- lever. The characters were where they had been asked to be and nothing the
-- player did moved them.
reset()
hold_left()
for _ = 1, 200 do
	frame = frame + 1
	hotkey()
	pos.registerBefore()
end
-- Walk P1 the way the game would, while the key is STILL held.
local before_walk = getx(P1)
setx(P1, before_walk + 60)
for _ = 1, 10 do
	frame = frame + 1
	hotkey()
	pos.registerBefore()
end
want("押しっぱなしでも歩いた先に留まる", getx(P1) >= before_walk + 40, true)

-- Releasing and pressing again must still work: the guard is about repeats,
-- not about locking the shortcut out.
reset()
hold_down_with("P1 Right")
-- Two frames with no firing is a release.
frame = frame + 1 pos.registerBefore()
frame = frame + 1 pos.registerBefore()
for _ = 1, 200 do
	frame = frame + 1
	hotkey()
	pos.registerBefore()
end
want("離して押し直せば効く (下+右)", getx(P2) < getx(P1), true)
want("右端まで行った", getx(P1) >= 940, true)

io.open = real_open

if fails == 0 then print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
