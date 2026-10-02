-- gcStats.lua
--
-- SHOW GC STATS (user, 2026-10-01). Guard cancels, kept over every blocked
-- string you tried one in and split by the side you were on, so a session of
-- practice reads as two lines, and each step of the motion as two more. Drawn
-- by hud.lua - at the top left while nothing else of its kind is up there,
-- otherwise at the bottom right above the input bar:
--
--   GC Side Total  Pass  Fail Success  GC t Input t
--   1P         12     9     3  75.00%  7.30   18.20
--   2P          4     1     3  25.00%  9.00       -
--   1P  ->    v  6.10    v> 10.20    [btn]  1.90      (the trace's arrows)
--   2P  <-    v     -    <v     -    [btn]     -
--
-- IN PB STATS' WORDS (user, 2026-10-01: 表記がPBとぶれてる). Total, Pass, Fail
-- and Success, two decimal places, - where there is nothing yet, and Pass and
-- Success in its green - the two boxes share the screen and must not use two
-- vocabularies for one idea. The columns are the design's own (Try OK NG Rate
-- were its first words for them).
--
-- P1 ONLY (user, 2026-10-01: 測定は1Pで良い). Nothing is counted while Coin has
-- handed P1 to the dummy - P1's guard cancels are then the dummy's own - or
-- while a recording is pressing P1's keys. Handing control over does NOT clear
-- the numbers (user, 2026-10-01: レコーディングウィザードで消さない): the
-- Recording Wizard does it on every take, and with only P1 ever counted nothing
-- from another character can mix in. Counting simply pauses.
--
-- THE SIDE IS WHERE P1 STANDS (user, 2026-10-01: キャラが右側に行ったら2P
-- SIDE). On the left, facing right, is the 1P side; on the right, the 2P side
-- - the 1P / 2P side of position.lua. Read from $120, the byte the game
-- mirrors a GROUND command by (0x0221DC; VSAV_MEMORY_NOTES, 左右の補正). A
-- guard cancel only exists on the ground, so this is the side the motion had
-- to be entered for. $0B, the facing, agrees with it except while the two
-- characters pass each other: it only turns when the character turns. This
-- hook runs after 0x022130 has updated $120 for the tick, so the byte is
-- current here - it is a tick stale only to code that reads it earlier.
--
-- ONE TRY IS ONE BLOCKED STRING. A string runs from the contact ($05 to 02)
-- until you are out of the stun again - $05 stays 02 while the next hit
-- arrives inside the stun, so a string is one run of it (pbStats.lua counts a
-- touch the same way). A gap where you could act ends it. It is a try only if:
--
--   * a guard cancel window opened in it ($158, ground guards only - the air
--     guard does not load it, ROM 0x02393A). Being hit is not a block.
--   * the guard cancel command moved at least TRIAL_MIN_STEPS steps, counting
--     a motion begun before the block that is still alive at the contact.
--     Guarding alone is not a try.
--
-- Pass if a guard cancel came out anywhere in the string - gc_next_state's
-- success, the test the GC Command Trace and the input bar make. Fail if the
-- string ended without one. A window running out or the command expiring in
-- the middle of the string ends nothing: you can input it again and cancel a
-- later hit, and that is still the same try.
--
-- WHEN THE STRING ENDS, IN THE RIGHT ORDER. A guard cancel takes you out of
-- the stun: in the 2026-09-25 guard pose logs (sampled per displayed frame)
-- $05 had left 02 on the very sample $06 first showed the special, all 84
-- times, and no sample ever showed the special with $05 still 02. So the
-- success is counted first and the end second, on one tick. And while a
-- window is still open the string is not over even if $05 has let go - in
-- the same logs the window had closed before all 267 stun ends that were not
-- a cancel, so this only waits where it has to.
--
-- THE AVERAGES ARE OVER THE PASSES ONLY. Neither is a score - a smaller number
-- is not a better guard cancel.
--
--   GC t     ticks from the window opening to the cancel. The number the
--            input bar draws beside SUCCESS and the trace beside Success.
--   Input t  ticks from the first direction the game TOOK for the motion
--            that finished the cancel, to the cancel. A motion begun before
--            the block counts from its own first direction; after an expired
--            command and a fresh one, only the fresh one counts. Both ends are
--            read in the same hook, on the monotonic p1_tick_seq, so there is
--            no byte to wrap. Not the trace's gaps added up - absolute ticks.
--            Averaged over the same Passes as the steps below.
--
-- OFF AND ON AGAIN STARTS FROM ZERO, as PB Stats does (user, 2026-10-01: PB
-- Statsとあわせて). Nothing is counted while Show GC Stats is off, and the
-- master script clears it every frame it is off. The design had it count on
-- while hidden. That and a character select are the only resets - there is
-- no reset row (user, 2026-10-01: キャラ選択に戻ればクリアだから要らない). A
-- load, the position shortcut and the round ending throw away the string in
-- progress without counting it. Nothing is saved.
--
-- EACH STEP OF THE MOTION, AVERAGED (user, 2026-10-01: コマンドの各方向の平均).
-- Over the Passes, the gaps the GC Command Trace draws row by row: first
-- direction to second, second to third, third to the button. hud.lua draws
-- them with the trace's own arrows.
--
-- INPUT t AND THE THREE STEPS ARE ONE MEASUREMENT (2026-10-02). With t1 t2 t3
-- the ticks the game took the three directions of the motion that came out
-- and ts the cancel, the steps are t2 - t1, t3 - t2 and ts - t3 and Input t
-- is ts - t1. All four are added from the same Passes - the ones whose motion
-- was seen from its first direction and took exactly three - so the three
-- step averages add up to the Input t average exactly, before the two-decimal
-- display rounds each of them. They were counted under two separate tests
-- before (the first direction seen, and three of them seen), which nothing
-- kept in step. A Pass outside them - its motion began before the count
-- could see it (the script started, a load), or it took other than three -
-- still counts as a Pass and is left out of all four (no_input says how
-- many). GC t keeps its own test, the window's opening, and can be averaged
-- over more Passes than these. The one log with +1 in it (v11.7.11, 3 Passes)
-- has all three directions seen every time.
--
-- COUNTS STOP AT 99999, as PB Stats' do (user, 2026-10-01: PBにあわせて). The
-- design drew 9999+ and went on counting; a side whose Total has reached the
-- limit now takes nothing more, so its line holds still.

local MAX = 99999
-- How far the guard cancel command has to get for a string to count as a try.
-- One, as designed and kept (user, 2026-10-01: しきい値は1でよい): a motion
-- that took only its first direction is a try that failed. Holding forward
-- re-takes that first direction every time it lapses (VSAV_MEMORY_NOTES, 9.
-- コマンド認識), so walking forward and then blocking also counts as a try.
local TRIAL_MIN_STEPS = 1

-- PB Stats' colours (pbStats.lua): grey labels, Pass and Success green, Fail
-- red.
local C_HEAD, C_TEXT, C_PASS, C_FAIL = "#AAAAAA", "#FFFFFF", "#00FF00", "#FF0000"

local function new_side()
	-- n_in counts the Passes behind Input t and the three steps alike.
	return { total = 0, pass = 0, fail = 0, n_gc = 0, sum_gc = 0, n_in = 0, sum_in = 0,
	         sum_st = { 0, 0, 0 } }
end

local st
-- What the next tick is compared against, and the string in progress. A
-- discarded string is not counted; the first tick after only learns.
local function forget()
	st.cur, st.w05, st.prog, st.step, st.tk, st.taken = nil, nil, nil, nil, nil, 0
end
local function reset()
	st = {
		[1] = new_side(), [2] = new_side(),
		-- Passes left out of GC t (its window's opening was not seen), and of
		-- Input t and the steps (its three directions were not all seen).
		no_gc_t = 0, no_input = 0,
	}
	forget()
end
reset()

-- A recording driving P1 is not you. Its keys are what macro.lua merges over
-- the pad this frame (master script, merge_macro_keys), named as joypad names
-- them; Coin and Start are not play.
local function p1_is_yours()
	if globals == nil or globals.controlling_p1 ~= true then return false end
	local mac = globals.macroLua
	if mac ~= nil and mac.playing == true and mac.get_keytable ~= nil then
		for k, v in pairs(mac.get_keytable() or {}) do
			if v and type(k) == "string" and k:sub(1, 3) == "P1 "
			   and k ~= "P1 Coin" and k ~= "P1 Start" then
				return false
			end
		end
	end
	return true
end

-- Show GC Stats on: off counts nothing, as pbStats.lua's enabled().
local function enabled()
	return globals ~= nil and globals.options ~= nil
		and globals.options.display_gc_stats == true
end

-- Not match_begun, which drops during a transformation (CLAUDE.md).
local function running()
	return globals ~= nil and globals.match_running ~= nil
		and globals.match_running() == true
end

local function side_of(b120) return (b120 == 1) and 1 or 2 end

local function finish_fail(c)
	if c.trial and c.window then
		local s = st[c.side]
		if s.total >= MAX then return end
		s.total, s.fail = s.total + 1, s.fail + 1
	end
end

-- ONE TICK, FROM guardCancel.lua's P1 HOOK (0x0221CC), after gct_tick:
--   seq   globals.p1_tick_seq
--   gc    this tick's window state, gc_next_state
--   gct   gc_tick_count's ticks from the window opening, on the success tick
--   prog  the guard cancel command block's +0 (nil: no block for this cid)
--   step  its +1
--   s05   P1 $05
--   b120  P1 $120
local function on_tick(seq, gc, gct, prog, step, s05, b120)
	if not enabled() or not p1_is_yours() or not running() then
		forget()
		return
	end

	-- THE MOTION, FOLLOWED THE WAY gct_tick FOLLOWS IT. +0 leaving 0 is a
	-- fresh first direction, +0 falling back to 0 is the end of it, and a
	-- direction was taken if +0 or +1 rose. +1 alone has to be able to carry
	-- it: a cancel whose last direction and button land on one tick drops +0
	-- to 0 on that tick (gct_tick's note, seq=5576).
	--
	-- tk is the ticks the live motion took its directions on, in order: nil
	-- with no motion alive, false with one alive that began before the first
	-- tick seen (the script starting, a load). That one's later directions
	-- must not stand in for its start, so it keeps false until it ends.
	local p0, s0 = st.prog, st.step
	st.prog, st.step = prog, step
	local dropped = false
	if prog == nil then
		st.tk, st.taken = nil, 0
	elseif p0 == nil then
		-- Not "(prog ~= 0) and false or nil": and/or cannot yield false.
		st.tk, st.taken = nil, 0
		if prog ~= 0 then st.tk = false end
	else
		local took = prog > p0 or step > s0
		dropped = p0 ~= 0 and prog == 0
		if p0 == 0 and prog ~= 0 then st.tk, st.taken = nil, 0 end
		if took then
			st.taken = st.taken + 1
			if st.tk ~= false then
				st.tk = st.tk or {}
				st.tk[#st.tk + 1] = seq
			end
		end
	end
	-- A motion alive since before the first tick seen has taken at least one.
	local steps = st.taken
	if steps == 0 and prog ~= nil and prog ~= 0 then steps = 1 end

	local w05 = st.w05
	st.w05 = s05
	local open = gc == "p1_gc_begin" or gc == "p1_gc_in_progress"
	if w05 ~= nil and s05 == 0x02 and w05 ~= 0x02 then
		-- A new contact. A string still waiting on its window is over now.
		if st.cur ~= nil and not st.cur.done then finish_fail(st.cur) end
		st.cur = {}
	end
	local c = st.cur
	if c ~= nil and not c.done then
		if open then c.window = true end
		if not c.trial and steps >= TRIAL_MIN_STEPS then
			c.trial, c.side = true, side_of(b120)
		end
		if gc == "p1_gc_success" then
			-- A cancel is a try by definition, whatever was seen before it.
			if not c.trial then c.trial, c.side = true, side_of(b120) end
			local s = st[c.side]
			-- A full side takes nothing more, as PB Stats stops.
			if s.total < MAX then
				s.total, s.pass = s.total + 1, s.pass + 1
				if gct ~= nil then
					s.n_gc, s.sum_gc = s.n_gc + 1, s.sum_gc + gct
				else
					st.no_gc_t = st.no_gc_t + 1
				end
				-- Input t and the three steps, together or not at all.
				local tk = st.tk
				if type(tk) == "table" and #tk == 3 then
					s.n_in = s.n_in + 1
					s.sum_in = s.sum_in + (seq - tk[1])
					s.sum_st[1] = s.sum_st[1] + (tk[2] - tk[1])
					s.sum_st[2] = s.sum_st[2] + (tk[3] - tk[2])
					s.sum_st[3] = s.sum_st[3] + (seq - tk[3])
				else
					st.no_input = st.no_input + 1
				end
			end
			-- Counted. The rest of this string, if any, is not a second try.
			c.done = true
		end
	end
	if c ~= nil and s05 ~= 0x02 and not open then
		if not c.done then finish_fail(c) end
		st.cur = nil
	end
	-- After the success above has read where the motion began.
	if dropped then st.tk, st.taken = nil, 0 end
end

local function avg(sum, n)
	if n == 0 then return "-" end
	return string.format("%.2f", sum / n)
end
local function right(s, w) return string.rep(" ", w - #s) .. s end

-- Widths fit 99999, 100.00% and an average of 999.99; one space between.
local W_SIDE, W_N, W_RATE, W_GC, W_IN = 7, 5, 7, 5, 7

-- The three lines, each a list of { text, colour } drawn left to right at one
-- glyph per character, so the offline test reads exactly what the screen gets.
-- The heading is one cell per column like the rows, so both are placed by the
-- same arithmetic and cannot drift apart along the line.
local function lines()
	local out = {
		{ { "GC Side", C_HEAD },
		  { " " .. right("Total", W_N), C_HEAD },
		  { " " .. right("Pass", W_N), C_HEAD },
		  { " " .. right("Fail", W_N), C_HEAD },
		  { " " .. right("Success", W_RATE), C_HEAD },
		  { " " .. right("GC t", W_GC), C_HEAD },
		  { " " .. right("Input t", W_IN), C_HEAD } },
	}
	for i, name in ipairs({ "1P", "2P" }) do
		local s = st[i]
		local rate = (s.total > 0)
			and string.format("%.2f%%", s.pass * 100 / s.total) or "-"
		out[#out + 1] = {
			{ name .. string.rep(" ", W_SIDE - #name), C_TEXT },
			{ " " .. right(tostring(s.total), W_N), C_TEXT },
			{ " " .. right(tostring(s.pass), W_N), C_PASS },
			{ " " .. right(tostring(s.fail), W_N), C_FAIL },
			{ " " .. right(rate, W_RATE), C_PASS },
			{ " " .. right(avg(s.sum_gc, s.n_gc), W_GC), C_TEXT },
			{ " " .. right(avg(s.sum_in, s.n_in), W_IN), C_TEXT },
		}
	end
	return out
end

-- The step averages for hud.lua to draw beside the arrows: per side, the gap
-- into the second direction, into the third, and into the button.
local function steps()
	local out = {}
	for i = 1, 2 do
		local s = st[i]
		out[i] = { avg(s.sum_st[1], s.n_in), avg(s.sum_st[2], s.n_in),
		           avg(s.sum_st[3], s.n_in) }
	end
	return out
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

return {
	["on_tick"] = on_tick,
	["lines"] = lines,
	["steps"] = steps,
	["text"] = text,
	-- A character select.
	["clear"] = reset,
	-- A load, the position shortcut: the string in progress goes uncounted.
	["discard"] = forget,
	-- For the offline test.
	["state"] = function() return st end,
	["TRIAL_MIN_STEPS"] = TRIAL_MIN_STEPS,
}
