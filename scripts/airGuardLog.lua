-- airGuardLog.lua
--
-- MEASUREMENT ONLY. Records air guards tick by tick, for working out how an
-- air-blocked chain can be interrupted (user, 2026-09-26). Nothing here
-- changes how the tool behaves.
--
-- WHAT THE ROM ALREADY SAYS (analysis/mame_code/c20.txt):
--
--   02393A  move.b #$12,($140,A6)     the guard init. With $38 set (in the
--   023954  tst.b ($38,A6) / bne       air) it branches past 02395A-023966,
--                                      so the ground-only writes of $158 (the
--                                      GC window) and $1AB (the PB window) do
--                                      not happen in the air
--   0243E4  $5C counted down           the hit stop, both sides frozen
--   0247F2  $06 = 2 dispatches on $140, and 0x12 goes to
--   025286  move.l #$2000602,($4,A6)  straight back to the jump state
--                                      ($05 = 00, $06 = 06, $07 = 02), with
--                                      ten ticks of $143 on both players
--
-- WHAT IT DOES NOT SAY, AND THIS IS FOR: whether a press made during the hit
-- stop is lost or kept, on which tick the first air attack can come out, how
-- long each side's hit stop is on a guard, and why pressing too early gets
-- the defender hit. The hit stop lengths come from a table at 0x0195A2 that
-- 0x0188FE reads; the listings are an opcode-space dump and show garbage for
-- data, so the table is dumped here through the CPU map instead.
--
-- Recording starts on the tick either player enters an air guard and runs on
-- through the rest of the chain, with PRE ticks from before it. It ends once
-- the defender has been on the ground for GROUND_END ticks, or after CAP.
-- Both player objects, 0x000-0x3FF, every tick, delta encoded.
--
-- Output: reversal_logs/airg_s01.json .. airg_s30.json, a ring. Gated on the
-- Knockdown Logger switch (Analysis tab), so it adds no menu row and ships off.
--
-- FILES ARE WRITTEN FROM registerBefore, NEVER FROM THE TICK. The tick is
-- driven from a ROM hook, and a file opened inside one is never written.

local LOG_DIR    = "reversal_logs"
local RING       = 30
local PRE        = 12
local GROUND_END = 20
local CAP        = 300
local BASES      = { 0xFF8400, 0xFF8800 }
local DWORDS     = 256          -- 0x400 bytes per player
local HITSTOP_TABLE = 0x0195A2  -- 0x0188CA; the guard pair starts at +2

local subscribed = false
local pre        = {}           -- the last PRE ticks, before anything began
local rec        = nil          -- the air guard being recorded
local done       = {}           -- finished, waiting for a frame to write them
local slot       = 0
local seq        = 0
local was        = { false, false }
local was_js     = { false, false }  -- in the jump's startup, on the ground
local was_air    = { false, false }  -- free ($05 = 00) and in the air
local last_raw   = nil

local function enabled()
	return globals ~= nil and globals.options ~= nil
		and globals.options.knockdown_logger_enable == true
end

local function sweep()
	local out, n = {}, 0
	for _, b in ipairs(BASES) do
		for i = 0, DWORDS - 1 do
			n = n + 1
			out[n] = memory.readdword(b + i * 4)
		end
	end
	return out
end

-- IN A GUARD, IN THE AIR. $54 = 0xFF is what 0x02381E sends to the guard
-- init, and $38 is the test 0x023954 makes. $140 is not used: it keeps 0x12
-- from an earlier air guard until the next init runs, so the tick a hit lands
-- after an air guard would read as another one.
local function air_guarding(base)
	return memory.readbyte(base + 0x05) == 0x02
		and memory.readbyte(base + 0x54) == 0xFF
		and memory.readbyte(base + 0x38) ~= 0
end

-- IN A JUMP'S STARTUP: the jump state, still on the ground (three ticks, then
-- $38 rises - 244 of 244). Struck here is the other case airGuardGap.lua shows:
-- caught before the jump left the ground (user, 2026-09-27).
local function jump_startup(base)
	return memory.readbyte(base + 0x05) == 0x00
		and memory.readbyte(base + 0x06) == 0x06
		and memory.readbyte(base + 0x07) == 0x00
		and memory.readbyte(base + 0x38) == 0
end

-- THE ATTACK BOX ID, which the object dump cannot carry: it lives in the
-- animation cel $1C points at (+0x0A), and that is ROM. Read here so a replay
-- can count startup the way Tick Data does (analysis/replay_air_guard_gap.py).
local function attack_box(base)
	local cel = memory.readdword(base + 0x1C)
	if cel == nil or cel == 0 then return 0 end
	return memory.readbyte(cel + 0x0A)
end

local function add_row(r, lg, raw, ab)
	local row = { lg = lg, ab = ab }
	if last_raw == nil then
		row.base = raw
	else
		local d = {}
		for i = 1, #raw do
			if raw[i] ~= last_raw[i] then
				d[#d + 1] = i
				d[#d + 1] = raw[i]
			end
		end
		row.d = d
	end
	last_raw = raw
	r.rows[#r.rows + 1] = row
end

local function on_tick()
	if not enabled() then
		pre, rec, last_raw, was, was_js, was_air =
			{}, nil, nil, { false, false }, { false, false }, { false, false }
		return
	end
	local lg = memory.readbyte(0xFF8081)
	local raw = sweep()
	local ab = { attack_box(BASES[1]), attack_box(BASES[2]) }
	local now = { air_guarding(BASES[1]), air_guarding(BASES[2]) }
	local js = { jump_startup(BASES[1]), jump_startup(BASES[2]) }
	local air = {}
	for p = 1, 2 do
		local b = BASES[p]
		air[p] = memory.readbyte(b + 0x05) == 0x00 and memory.readbyte(b + 0x38) ~= 0
		-- Struck out of the jump's startup counts as a start as well, and so
		-- does a hit in the air out of a free state: the guard that failed.
		if memory.readbyte(b + 0x05) == 0x02 and (was_js[p] or was_air[p]) then now[p] = true end
	end

	if rec == nil then
		for p = 1, 2 do
			if now[p] and not was[p] then
				rec = { def = p, rows = {}, events = {}, ground = 0 }
				last_raw = nil
				for _, t in ipairs(pre) do add_row(rec, t.lg, t.raw, t.ab) end
				break
			end
		end
	end

	if rec ~= nil then
		add_row(rec, lg, raw, ab)
		for p = 1, 2 do
			if now[p] and not was[p] then
				rec.events[#rec.events + 1] = { i = #rec.rows, p = p }
			end
		end
		if memory.readbyte(BASES[rec.def] + 0x38) == 0 then
			rec.ground = rec.ground + 1
		else
			rec.ground = 0
		end
		if rec.ground >= GROUND_END or #rec.rows >= CAP then
			done[#done + 1] = rec
			rec, pre, last_raw = nil, {}, nil
		end
	else
		pre[#pre + 1] = { lg = lg, raw = raw, ab = ab }
		if #pre > PRE then table.remove(pre, 1) end
	end
	was = now
	was_js = js
	was_air = air
end

local function rom_dump(base, n)
	local t = {}
	for i = 0, n - 1 do t[i + 1] = memory.readbyte(base + i) end
	return t
end

local function write_one(version)
	local r = table.remove(done, 1)
	slot = slot % RING + 1
	seq = seq + 1
	write_object_to_json_file({
		script_version = version,
		kind      = "air_guard",
		seq       = seq,
		slot      = slot,
		def       = r.def,
		cid1      = memory.readbyte(BASES[1] + 0x382),
		cid2      = memory.readbyte(BASES[2] + 0x382),
		gs        = globals.options.game_speed,
		pre       = PRE,
		dwords    = DWORDS,
		note      = "rows: lg = 0xFF8081; base = first row, both objects as " ..
		            "dwords (P1 0xFF8400 then P2 0xFF8800); d = pairs of " ..
		            "1-based dword index and new value. ab = attack box id " ..
		            "(cel +0x0A) of P1, P2. events: i = row, " ..
		            "p = the player who entered an air guard.",
		hitstop_table = rom_dump(HITSTOP_TABLE, 112),
		events    = r.events,
		rows      = r.rows,
	}, LOG_DIR .. string.format("/airg_s%02d.json", slot))
end

return {
	-- Exported so the offline test can drive it; the real caller is the tick.
	["on_tick"] = on_tick,
	["registerBefore"] = function(version)
		-- SUBSCRIBED ONCE, LAZILY, as timers.lua does: this module is loaded
		-- before globals.truth exists.
		if not subscribed and globals ~= nil and globals.truth ~= nil
		   and globals.truth.ticker ~= nil then
			subscribed = true
			globals.truth.ticker:subscribe(function() on_tick() end)
		end
		if #done > 0 and write_object_to_json_file ~= nil then
			write_one(version)
		end
	end,
}
