-- WHICH BYTE SAYS "THIS PLAYER HAS LOCKED IN", WHEN THE CHARACTER IS BULLETA.
--
-- The arcade-stick mirror in vsav_training_master_script.lua asks
-- memory.readbyte(0xFF8400 + 0x3BD) ~= 0 and takes non-zero to mean P1 has
-- chosen. It works for everyone except Bulleta, and the ROM says why:
--
--   020AC8: move.b ($382,A6), ($3bd,A6)
--
-- $3BD is a COPY OF THE CHARACTER ID. Bulleta is 0x00, so "has chosen
-- Bulleta" and "has chosen nobody" are the same byte value. A flag is needed
-- instead of an id, and this finds it.
--
-- Both readers in the ROM test $3BC before using $3BD as an index
-- (0x00A77C and 0x00AF1C), so $3BC is the obvious candidate - but that pair is
-- written at character init, not necessarily at the select screen, so it is a
-- guess until something is measured.
--
-- Run INSTEAD of the training script:
--   analysis/run_select_probe.bat        (double click)
--
-- What to do:
--   1. let it reach the character select screen
--   2. choose BULLETA on P1 and lock in. Wait a second.
--   3. choose anyone on P2 and lock in. Wait a second.
--   4. back out to the select screen (or restart) and do it again with
--      DEMITRI on P1, so there is a working case to compare against.
--
-- Then close the emulator and read select_probe.log next to fcadefbneo.exe.
--
-- A line per frame on which any watched byte changed. The screen id is in the
-- line, so the select screen can be picked out from everything else.
local P1 = 0xFF8400
local P2 = 0xFF8800
local SCREEN = 0xFF8009

local LOG = "select_probe.log"
local file = nil
local prev = nil
local lines = 0

-- The window around the two bytes the ROM pairs. $382 is the character id the
-- rest of the tool reads, kept as the reference: whatever the flag turns out to
-- be, it has to rise while this one is still 0 for Bulleta.
local LOW, HIGH = 0x3B8, 0x3E8

local function row()
	local out = { string.format("scr=%02X", memory.readbyte(SCREEN)) }
	out[#out + 1] = string.format("p1_382=%02X", memory.readbyte(P1 + 0x382))
	out[#out + 1] = string.format("p2_382=%02X", memory.readbyte(P2 + 0x382))
	-- The cursor stage-select.lua already uses, so the log can say where the
	-- player was pointing when a byte moved.
	out[#out + 1] = string.format("p1_403=%02X", memory.readbyte(P1 + 0x003))
	out[#out + 1] = string.format("p2_403=%02X", memory.readbyte(P2 + 0x003))
	for a = LOW, HIGH do
		local v1 = memory.readbyte(P1 + a)
		local v2 = memory.readbyte(P2 + a)
		if v1 ~= 0 or v2 ~= 0 then
			out[#out + 1] = string.format("%03X=%02X/%02X", a, v1, v2)
		end
	end
	return table.concat(out, " ")
end

local function open()
	if file == nil then
		file = io.open(LOG, "a")
		if file then
			file:write("\n=== select probe " .. os.date() .. " ===\n")
			file:write("# scr=FF8009 (02 is character select). ")
			file:write("OFFSET=P1/P2, zero on both sides omitted\n")
		end
	end
	return file
end

emu.registerbefore(function()
	local text = row()
	if text == prev then return end
	prev = text
	if open() then
		file:write(string.format("f=%d %s\n", emu.framecount(), text))
		lines = lines + 1
		if (lines % 32) == 0 then file:flush() end
	end
end)

gui.register(function()
	gui.text(8, 8, string.format("select probe: %d lines -> %s", lines, LOG))
	gui.text(8, 18, string.format("screen %02X   P1 $382=%02X  $3BC=%02X  $3BD=%02X",
		memory.readbyte(SCREEN), memory.readbyte(P1 + 0x382),
		memory.readbyte(P1 + 0x3BC), memory.readbyte(P1 + 0x3BD)))
end)

emu.registerexit(function()
	if file then file:write("=== end ===\n") file:close() file = nil end
end)
