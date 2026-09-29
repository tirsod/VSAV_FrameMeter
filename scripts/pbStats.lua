-- pbStats.lua
--
-- SHOW PB STATS, REBUILT (user, 2026-09-28). What the PB Count line at the top
-- shows for one guard, kept over every touch and averaged, so a session of push
-- block practice reads as a few numbers. Drawn by hud.lua beside the GC Command
-- Trace, so both can be practised at once:
--
--   Count Total 186
--         Pass 92  Fail 94
--         Success 49.46%
--   Avg   PB 4.30  at 3.90-10.20t
--         Multi 1.20  Late 0.30
--
-- Count and Avg are labels, grey as AirGap's are; two decimal places; the rate
-- says it is the success rate; Multi and Late are the PB Count line's MultiPush
-- and LateMash, shortened (user, 2026-09-28).
--
-- ONE TOUCH is the other side's attack reaching you on the ground: from $05
-- going to 02 until you are out of it again. A blocked string is one touch -
-- the game keeps counting $170 across it (timers.lua), so a push block granted
-- on its second hit is one success, not a failure and a success. In the air
-- there is no push block window, so an air touch is not counted.
--
--   ONLY A TOUCH YOU PRESSED IN COUNTS. One without a press is ignored, hit or
--   guarded ("ボタンを押していないものはやはり無視"; Guard Only is gone).
--   NOR ONE YOU GUARD CANCELLED OUT OF ("GC成功したらPBから除外"): the cancel
--   was the answer, so its presses are not a push block that failed. The test
--   is the one the GC Command Trace and the input history make.
--   Fail   pressed, and hit ($54 not 0xFF) on any tick of the touch
--          ("ダメージを受けたら失敗"), or no push block came
--   Pass   pressed, and the push block was granted
--
-- "Pressed", guarded, is the PB Count line's count, or LateMash - a press made
-- only after the window is a press that bought nothing. Hit, the line holds the
-- last touch's values (no window opens), so there it is a button edge in $126
-- on a tick of the touch. Total is Pass + Fail and the rate Pass over it. The
-- averages are over the touches you pressed in and guarded through, and they
-- are the PB Count line's own values at the touch's end:
-- its count, the first and last pressed tick of the last window pressed in
-- (at:), MultiPush, and LateMash once it has stopped counting (14 ticks past
-- the window). Nothing is measured twice.
--
-- Counts stop at 99999 (user).
--
-- The old Total / Pass / Fail counted off a second clock in displayed frames
-- and knew nothing of the line above it (design_pb_score.md).

local P1 = 0xFF8400
local MAX = 99999

local C_TEXT, C_PASS, C_FAIL, C_ZERO = "#FFFFFF", "#00FF00", "#FF0000", "#888888"
local C_HEAD = "#AAAAAA"        -- labels, as AirGap's
local LABEL_W = 6               -- "Count "

local st
local function reset()
	st = {
		total = 0, pass = 0, fail = 0,
		-- Sums over the averaged touches, and how many there were. at: has its
		-- own count: a touch pressed only after the window has no at:.
		n = 0, sum_pb = 0, sum_simul = 0, sum_om = 0,
		n_at = 0, sum_at1 = 0, sum_at2 = 0,
		-- The touch in progress, or one that ended and waits for LateMash.
		cur = nil,
		w05 = nil,
	}
end
reset()

local function rb(a) return memory.readbyte(a) end
-- The six attack buttons of $126, as timers.lua's and77.
local function buttons(v)
	return v - (math.floor(v / 8) % 2) * 8 - (math.floor(v / 128) % 2) * 128
end

local function enabled()
	return globals ~= nil and globals.options ~= nil
		and globals.options.display_pb_stats == true
end

-- The first and last pressed tick of a window, as the PB Count line draws at:.
local function at_of(marks)
	if marks == nil then return nil end
	local a, b
	for p = 1, 14 do
		local m = marks[p]
		if m ~= nil and m ~= "-" then
			if a == nil then a = p end
			b = p
		end
	end
	return a, b
end

local function finalize(c)
	if st.total >= MAX then return end
	if c.gc then return end
	if c.hit then
		if not c.pressed then return end
		st.total, st.fail = st.total + 1, st.fail + 1
		return
	end
	if (c.count or 0) == 0 and (c.om or 0) == 0 then return end
	st.total = st.total + 1
	if c.ok then st.pass = st.pass + 1 else st.fail = st.fail + 1 end
	st.n = st.n + 1
	st.sum_pb = st.sum_pb + (c.count or 0)
	st.sum_simul = st.sum_simul + (c.simul or 0)
	st.sum_om = st.sum_om + (c.om or 0)
	if c.at1 ~= nil then
		st.n_at = st.n_at + 1
		st.sum_at1 = st.sum_at1 + c.at1
		st.sum_at2 = st.sum_at2 + c.at2
	end
end

local function on_tick()
	if not enabled() then
		st.cur, st.w05 = nil, nil
		return
	end
	local t = globals.timers
	if t == nil then return end
	local s05 = rb(P1 + 0x05)
	local w05 = st.w05
	st.w05 = s05
	if w05 == nil then return end       -- the first tick only learns
	local c = st.cur

	-- A NEW TOUCH closes the one before, whatever it was still waiting on.
	if s05 == 0x02 and w05 ~= 0x02 then
		if c ~= nil then finalize(c) end
		c = nil
		if rb(P1 + 0x38) == 0 then
			-- What the PB Count line holds on this tick is still the last
			-- touch's: its window opens a tick after the contact. Its marks
			-- table is remembered so they are never read as this one's -
			-- timers.lua starts a new table for every window.
			c = { live = true, stale_marks = t.p1_pb_marks }
		end
		st.cur = c
	end
	if c == nil then return end

	if c.live then
		-- A GUARD CANCEL THAT CAME OUT: the block clock $158 reaching zero with
		-- $06 on a special, an ES or an EX - guardCancel.lua's gc_next_state,
		-- checked there against 35 logged attempts. Read on the tick the touch
		-- ends too: the cancel is what ends it. A special after the stun ran
		-- out is a reversal, not a cancel - the clock was already at zero.
		local clk, act = rb(P1 + 0x158), rb(P1 + 0x06)
		if c.clk ~= nil and c.clk > 0 and clk == 0
		   and (act == 0x0E or act == 0x10 or act == 0x12) then
			c.gc = true
		end
		c.clk = clk
		if s05 == 0x02 then
			-- $54 is the hit's kind from the contact tick on; 0xFF is a guard.
			-- $140 would say the same a tick later (measured: 0 or 12 on the
			-- contact, then 02 guard / 00 hit on the ground).
			if rb(P1 + 0x54) ~= 0xFF then c.hit = true end
			if buttons(rb(P1 + 0x126)) ~= 0 then c.pressed = true end
			-- The PB Count line's values, taken every tick: the last one taken
			-- is the touch's end, and by then they are this touch's.
			c.count = t.p1_pushblock_counter or 0
			c.ok = t.p1_pushblock_ok == true
			c.simul = t.p1_pb_simul or 0
			if t.p1_pb_marks ~= c.stale_marks then
				local a, b = at_of(t.p1_pb_marks)
				if a ~= nil then c.at1, c.at2 = a, b end
			end
		else
			c.live = false
		end
	end
	c.om = t.p1_pb_latemash or 0
	-- Out of the touch, and LateMash has stopped following: nothing more can
	-- change, so it is counted.
	if not c.live and t.p1_pb_latemash_open ~= true then
		finalize(c)
		st.cur = nil
	end
end

local function f2(v) return (v ~= nil) and string.format("%.2f", v) or "-" end

-- The five lines, each a list of { text, colour } drawn left to right at one
-- glyph per character, so the offline test reads exactly what the screen gets.
local function lines()
	local d = st.pass + st.fail
	local rate = (d > 0) and (f2(st.pass * 100 / d) .. "%") or "-"
	local pb, simul, om = nil, nil, nil
	if st.n > 0 then
		pb, simul, om = st.sum_pb / st.n, st.sum_simul / st.n, st.sum_om / st.n
	end
	local at = "-"
	if st.n_at > 0 then
		at = f2(st.sum_at1 / st.n_at) .. "-" .. f2(st.sum_at2 / st.n_at) .. "t"
	end
	-- The two negatives in red when there is any, grey at none - the rule the
	-- PB Count line uses for them.
	local function neg(v) return (v ~= nil and v > 0) and C_FAIL or C_ZERO end
	local function label(s) return { s .. string.rep(" ", LABEL_W - #s), C_HEAD } end
	local under = { string.rep(" ", LABEL_W), C_HEAD }
	return {
		{ label("Count"), { "Total " .. st.total, C_TEXT } },
		{ under, { "Pass " .. st.pass, C_PASS }, { "  Fail " .. st.fail, C_FAIL } },
		{ under, { "Success " .. rate, C_PASS } },
		{ label("Avg"), { "PB " .. f2(pb), C_TEXT }, { "  at " .. at, C_TEXT } },
		{ under, { "Multi " .. f2(simul), neg(simul) }, { "  Late " .. f2(om), neg(om) } },
	}
end

local function text()
	local out = {}
	for i, l in ipairs(lines()) do
		local s = ""
		for _, c in ipairs(l) do s = s .. c[1] end
		out[i] = s
	end
	return out
end

local subscribed = false

return {
	["on_tick"] = on_tick,
	["lines"] = lines,
	["text"] = text,
	["clear"] = reset,
	["registerBefore"] = function()
		-- SUBSCRIBED ONCE, LAZILY, as timers.lua does: this module is loaded
		-- before globals.truth exists.
		if not subscribed and globals ~= nil and globals.truth ~= nil
		   and globals.truth.ticker ~= nil then
			subscribed = true
			globals.truth.ticker:subscribe(function() on_tick() end)
		end
	end,
}
