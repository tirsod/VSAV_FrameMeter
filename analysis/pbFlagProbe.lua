-- WHY IS "PB Count: 0" GREEN?
--
-- The counter box goes red when the count is 0 and the digit goes green when
-- the push block was granted, so "green 0 on red" says granted-with-no-presses
-- (user screenshot, 2026-09-13). Reading the code could not produce that state:
-- the only reset of the flag (ROM 0x023966) clears the count in the same
-- breath, and the only way to reach the grant (ROM 0x027632) is through the
-- increment at 0x027606. Verified against the MAME listing:
--
--   0275CE  cmpi.b #$6,($382,A6) / beq      character gate
--   0275D8  tst.b  ($1ab,A6)     / beq      window closed
--   0275E0  tst.b  ($184,A6)     / bne      ALREADY GRANTED - exits here
--   0275E8  cmpi.w #$202,($4,A6) / bne
--   0275F0  cmpi.b #$2,($140,A6) / bne
--   0275F8  tst.b  ($3b4,A6)     / bne
--   0275FE  bsr    $274ba        / beq      ($15d,A5)==0 and ($126 & $77)
--   027606  addq.b #1,($170,A6)           <- the game's own count
--   02760E  cmpi.b #$8,D0 / bcc $2762c    <- eight is guaranteed
--   02761E  jsr    $14e8a                 <- otherwise a roll
--   027632  move.b #$1,($184,A6)          <- GRANTED
--
-- So either the tool's count is being zeroed by something other than the reset
-- (hud.lua zeroes it, and not the flag, when the readout is switched off), or
-- the counting hook is missing presses the game takes. This tells the two
-- apart, because it shows BOTH counts side by side: the one this probe keeps
-- the way timers.lua keeps it, and the game's own $170.
--
-- Run INSTEAD of the training script:
--   analysis/run_pb_flag_probe.bat        (double click)
--
-- What to do, once a round is up:
--   1. Guard an attack and mash a button to push block. Do it several times,
--      including attempts you do NOT complete.
--   2. Watch the "anomaly" count. It rises the moment lua=0 and ok=true are
--      true together - the state in the screenshot.
--   3. Let the round end and start another. Push block again.
--
-- What to look for:
--   lua and game should move together. If lua stalls at 0 while game climbs,
--   the counting hook is wrong. If both sit at 0 while ok stays true, the flag
--   is simply stale and nothing resets it.
local LOG = "pb_flag_probe.log"
local file = nil
local lines = 0

local P1, P2 = 0xFF8400, 0xFF8800

-- Copied from timers.lua deliberately, not required from it: what is being
-- measured is what THAT arithmetic does, so it has to be the same arithmetic.
local pb_pressed = { [P1] = 0, [P2] = 0 }
local ok = { [P1] = false, [P2] = false }

local anomalies = 0
local last_note = "(まだ何も起きていない)"
local last_anomaly = "(まだ無い)"

local function and77(v)
	local r = 0
	for _, b in ipairs({1, 2, 4, 16, 32, 64}) do
		if math.floor(v / b) % 2 == 1 then r = r + b end
	end
	return r
end

local function side(a6)
	if a6 == P1 then return "P1" end
	if a6 == P2 then return "P2" end
	return "??"
end

local function write(s)
	if file == nil then file = io.open(LOG, "a") end
	if file then
		file:write(s .. "\n")
		file:flush()
		lines = lines + 1
	end
end

-- The game's own state, so the tool's count can be checked against it rather
-- than against an argument.
local function snap(a6)
	return string.format("$170=%d $184=%d $1ab=%02X $04=%04X $140=%02X",
		memory.readbyte(a6 + 0x170), memory.readbyte(a6 + 0x184),
		memory.readbyte(a6 + 0x1AB), memory.readword(a6 + 0x04),
		memory.readbyte(a6 + 0x140))
end

-- 023966: move.b #$e, ($1ab,A6)   a blocked hit opens a new window
memory.registerexec(0x023966, function()
	local a6 = memory.getregister("m68000.a6")
	if pb_pressed[a6] == nil then return end
	local was = pb_pressed[a6]
	pb_pressed[a6] = 0
	ok[a6] = false
	last_note = string.format("f=%d %s 窓が開いた (前回 %d)", emu.framecount(), side(a6), was)
	write(string.format("f=%d OPEN   %s  lua %d -> 0  ok -> false   %s",
		emu.framecount(), side(a6), was, snap(a6)))
end)

-- 0275E0: the press the game is about to count (or refuse)
memory.registerexec(0x0275E0, function()
	local a6 = memory.getregister("m68000.a6")
	if pb_pressed[a6] == nil then return end
	-- The tests the ROM makes after this point, repeated. $184 is deliberately
	-- NOT among them: timers.lua counts presses made after the grant too.
	local why = nil
	if memory.readword(a6 + 0x04) ~= 0x0202 then why = "$04"
	elseif memory.readbyte(a6 + 0x140) ~= 0x02 then why = "$140"
	elseif memory.readbyte(a6 + 0x3B4) ~= 0 then why = "$3b4"
	elseif memory.readbyte(0xFF815D) ~= 0 then why = "$15d"
	elseif and77(memory.readbyte(a6 + 0x126)) == 0 then why = "$126"
	end
	if why ~= nil then
		-- A refusal matters as much as a count: if the game increments $170 on
		-- a tick this refused, the mirror is wrong and that is the answer.
		write(string.format("f=%d SKIP   %s  %s de hajiita   lua=%d   %s",
			emu.framecount(), side(a6), why, pb_pressed[a6], snap(a6)))
		return
	end
	pb_pressed[a6] = pb_pressed[a6] + 1
	last_note = string.format("f=%d %s 押した -> %d", emu.framecount(), side(a6), pb_pressed[a6])
	write(string.format("f=%d COUNT  %s  lua -> %d   %s",
		emu.framecount(), side(a6), pb_pressed[a6], snap(a6)))
end)

-- 027632: move.b #$1, ($184,A6)   the push block is granted
memory.registerexec(0x027632, function()
	local a6 = memory.getregister("m68000.a6")
	if pb_pressed[a6] == nil then return end
	ok[a6] = true
	last_note = string.format("f=%d %s 成立 (lua=%d)", emu.framecount(), side(a6), pb_pressed[a6])
	write(string.format("f=%d GRANT  %s  lua=%d   %s",
		emu.framecount(), side(a6), pb_pressed[a6], snap(a6)))
end)

-- THE STATE THE SCREENSHOT SHOWED, SAMPLED EVERY DRAWN FRAME.
--
-- It is a state rather than an event, so one look per drawn frame finds it -
-- the tick the tool misses cannot hide something that stays true.
local was_anomalous = { [P1] = false, [P2] = false }
emu.registerbefore(function()
	for _, a6 in ipairs({P1, P2}) do
		local bad = (pb_pressed[a6] == 0) and ok[a6]
		if bad and not was_anomalous[a6] then
			anomalies = anomalies + 1
			last_anomaly = string.format("f=%d %s  lua=0 nanoni ok=true  ($170=%d)",
				emu.framecount(), side(a6), memory.readbyte(a6 + 0x170))
			write("f=" .. emu.framecount() .. " ANOMALY " .. side(a6) ..
				"  lua=0 ok=true   " .. snap(a6))
		end
		was_anomalous[a6] = bad
	end
end)

gui.register(function()
	gui.text(8, 8, string.format("pb flag probe   anomaly %d   log %d lines", anomalies, lines))
	for i, a6 in ipairs({P1, P2}) do
		gui.text(8, 8 + i * 10, string.format("%s  lua=%d ok=%s   %s",
			side(a6), pb_pressed[a6], tostring(ok[a6]), snap(a6)),
			((pb_pressed[a6] == 0) and ok[a6]) and "#00FF00" or "#FFFFFF")
	end
	gui.text(8, 38, "last:    " .. last_note)
	gui.text(8, 48, "anomaly: " .. last_anomaly)
	gui.text(8, 58, "Guard, then mash to push block. Several times, some unfinished.")
end)

emu.registerexit(function()
	if file then file:close() file = nil end
end)
