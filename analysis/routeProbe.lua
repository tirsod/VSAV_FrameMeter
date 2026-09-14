-- WHAT THE STATE BYTES DO ACROSS A WHOLE JUMP OR DASH.
--
-- Started life as the dash probe, which answered where a dash ends and its
-- attack begins ($10B moves on that tick - VSAV_MEMORY_NOTES.md 11). The
-- Action Route readout needs three more answers and the dash probe could not
-- give them, because it only recorded while the attack flag was up:
--
--   1. Does a jump sit in $06 = 0x06 on the ground and 0x08 in the air? That
--      is the split the frame tables call 予備動作 / 浮遊時間, and the route
--      has to start at the first of them to be comparable with their numbers.
--   2. Is the landing motion $06 = 0x04 ("about to be free"), and does it end
--      by returning to 0x00?
--   3. Does the defender's hitstop ($5C) rise when a hit lands on someone who
--      is ALREADY in stun? The $05 -> 0x02 edge does not fire there, which is
--      why a jump-in during a combo currently shows no contact at all.
--
-- So this records CHANGES, not a window: every tick where any watched byte
-- differs from the tick before gets a line. Standing still costs nothing and a
-- whole jump is about a dozen lines.
--
-- Run INSTEAD of the training script:
--   analysis/run_route_probe.bat        (double click)
--
-- What to do once it is running, once each, with a pause between:
--   1. jump, and attack in the air
--   2. dash, and attack out of the dash
--   3. jump, and land without attacking
--   4. hit the dummy, and while it is still reeling, jump in and hit it again
--   5. walk forward, walk back, crouch - each on its own, standing still
--      between them
--   6. set the dummy to guard, and hit it once in the air and once on the
--      ground. Every session logged so far has $158 = 00 on every line, so
--      nothing measured yet says when the block clock or $140 actually moves.
--   7. an air dash attack, if the character has one - ISSUE-AIR-DASH-NORMAL-001
--      is a BLOCKER with no case that exercises it.
--   8. hit or guard a CPU opponent several times and let it recover on its
--      own, without hitting it again. A CPU walks in after recovering, which
--      is exactly the case that decides whether $06 goes 0x02 -> 0x00 or
--      0x02 -> 0x04 - and therefore whether the advantage reading is wrong
--      when the opponent holds a direction.
--   9. rapid-fire BY HAND: press LP, then press it again to cancel into a
--      second one. Twice and three times, on hit and on whiff. Then hold LP
--      down, and press it again too late - those must NOT move $1B8.
--
-- BY HAND IS THE WHOLE TEST HERE. Auto (Rapid) belongs to the training script,
-- which this runs INSTEAD of - there is no menu while the probe is loaded, and
-- both cannot be loaded at once because emu.registerbefore takes one callback
-- and the master script already holds it. It does not matter: 0x028FB0 reads
-- $126, the press edge, and cannot tell who caused it. Auto is checked by
-- reading the Action Route row in the tool itself, which needs no log.
--
-- Then close the emulator and read dash_probe.log next to fcadefbneo.exe.
local P1 = 0xFF8400
local P2 = 0xFF8800
local TICK = 0xFF8081

local LOG = "dash_probe.log"
local file = nil
local prev = nil
local lines = 0

-- $05 and $06 are the state pair the whole tool reads; $38 is airborne; $105
-- is the attack flag; $10B and $1B7 move when a new move starts inside a dash;
-- $102 and $101 are the strength/family bytes an earlier version tried.
-- On the defender: $05 for the stun edge, $5C for hitstop, $158 for the block
-- clock - the three ways a contact could be seen.
local WATCH = {
	-- $04 and $07 are the other two bytes of the state longword. Nothing in the
	-- tool reads them, but ISSUE-CONTACT-ATTACKER-STATE-001 asks for all four,
	-- and 0x0274CE writes the longword as 02 00 0A 00 - so the pair is the way
	-- to tell "that write happened and $06 was changed back" from "that write
	-- never ran". $382 is the character id, without which a log cannot say
	-- which character it measured.
	{ "p1_04", P1 + 0x004 }, { "p1_07", P1 + 0x007 }, { "char", P1 + 0x382 },
	{ "p1_05", P1 + 0x005 }, { "p1_06", P1 + 0x006 }, { "air", P1 + 0x038 },
	{ "105", P1 + 0x105 }, { "10B", P1 + 0x10B }, { "1B7", P1 + 0x1B7 },
	{ "102", P1 + 0x102 }, { "101", P1 + 0x101 },
	-- HOW THE GAME COUNTS ATTACKS, AND WHY IT STARTED THIS ONE.
	--
	-- $1B8 is a word the ROM adds 1 to at every entry that starts an attack,
	-- the rapid-fire restart at 0x028F18 included - the only signal that says a
	-- rapid LP into LP is a SECOND LP. Logged as two bytes because the probe
	-- prints bytes; 1B9 is the one that moves.
	-- $119 and $11A are the two flags set just before that tail: 0x028ED0 sets
	-- $119 for a chain, 0x028FF0 sets $11A for a rapid repeat. The hit code
	-- reads $11A at 0x0188EE and 0x01896E, so it survives into the hit.
	{ "1B8", P1 + 0x1B8 }, { "1B9", P1 + 0x1B9 },
	{ "119", P1 + 0x119 }, { "11A", P1 + 0x11A },
	{ "21", P1 + 0x021 },
	{ "p2_05", P2 + 0x005 }, { "p2_5C", P2 + 0x05C }, { "p2_158", P2 + 0x158 },
	{ "p2_140", P2 + 0x140 },
	-- THE DEFENDER'S OWN STATE, BECAUSE RECOVERY IS READ FROM IT.
	--
	-- tickData decides the opponent has recovered when $05 and $06 are BOTH
	-- zero. Walking turned out to be $06 = 0x04, not 0x00, so an opponent that
	-- comes out of stun straight into a walk would never satisfy that test and
	-- the advantage would read long. Nothing measured yet says whether the
	-- game actually goes 0x02 -> 0x04, so $06 and the P2 lever are here to
	-- settle it - $04 and $07 come along because they are the same longword.
	{ "p2_04", P2 + 0x004 }, { "p2_06", P2 + 0x006 },
	{ "p2_07", P2 + 0x007 }, { "p2_38", P2 + 0x038 },
	{ "p2_lever", P2 + 0x125 }, { "p2_char", P2 + 0x382 },
	-- Walking and crouching are not in $06 and have to come off the lever. $122
	-- is the BUTTONS and read 00 on every line of the first attempt; $125 is the
	-- stick, and inputHistory.lua had already measured that its neighbour $123
	-- flickers while $125 does not. Both are here so the log settles it.
	{ "btn", P1 + 0x122 }, { "lev123", P1 + 0x123 },
	{ "lever", P1 + 0x125 }, { "face", P1 + 0x00B },
}

-- THE ANIMATION, WHICH IS WHERE THE NEXT ANSWER HAS TO BE.
--
-- $10B turned out not to mean "a move started" (VSAV_MEMORY_NOTES.md), and on a
-- whiffed dash LP nothing else in the list above moves either - the only change
-- is the hitbox appearing, which is too late to be the start of the move. The
-- cel pointer is the remaining candidate: a new move is a jump to another
-- animation script, and $20 is the countdown inside the current cel.
local ANIM = {
	{ "20", P1 + 0x020 },
}

-- The attack box is animation data: the cel pointer at $1C, and +0x0A in the
-- cel is the box id. 0 means no box out this tick.
local function box()
	local cel = memory.readdword(P1 + 0x1C)
	if cel == 0 then return 0 end
	return memory.readbyte(cel + 0x0A)
end

local function row()
	local out = {}
	for _, w in ipairs(WATCH) do
		out[#out + 1] = string.format("%s=%02X", w[1], memory.readbyte(w[2]))
	end
	for _, w in ipairs(ANIM) do
		out[#out + 1] = string.format("%s=%02X", w[1], memory.readbyte(w[2]))
	end
	out[#out + 1] = string.format("cel=%08X", memory.readdword(P1 + 0x1C))
	out[#out + 1] = string.format("box=%02X", box())
	return table.concat(out, " ")
end

local function open()
	if file == nil then
		file = io.open(LOG, "a")
		if file then
			file:write("\n=== route probe " .. os.date() .. " ===\n")
			file:write("# a line per tick on which any watched byte changed\n")
		end
	end
	return file
end

emu.registerbefore(function()
	local text = row()
	-- Only when something moved. A line that repeats the one above it says
	-- nothing, and the interesting runs are short.
	if text == prev then return end
	prev = text
	if open() then
		file:write(string.format("t=%3d %s\n", memory.readbyte(TICK), text))
		lines = lines + 1
		-- Flushed as it goes: the emulator is usually closed by its window
		-- button, and a buffered tail would be the part worth reading.
		if (lines % 32) == 0 then file:flush() end
	end
end)

gui.register(function()
	gui.text(8, 8, string.format("route probe: %d lines -> %s", lines, LOG))
end)

emu.registerexit(function()
	if file then file:write("=== end ===\n") file:close() file = nil end
end)
