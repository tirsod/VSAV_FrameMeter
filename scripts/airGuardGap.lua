-- airGuardGap.lua
--
-- AIR GUARD GAPS (user, 2026-09-26). After each hit of an air chain you
-- blocked: how many ticks you could act before the next one arrived, where in
-- that gap you pressed, and when your attack connected. The last row runs to
-- your landing, with the other side's landing marked too. Drawn under PB
-- Count by hud.lua.
--
--   AirGap                           Gap  Press>Hit
--   Jump > 6t J.LP(5t)  PK                PreJump(3t) > Guard 12t
--                                         In Blockstun 14t at 9,13t
--   J.LP(5t) > J.LK     ---|P         3t  In Blockstun 14t at 12t
--   J.MP(6t) > J.MK     ---P---*       ?  LP 4t>8t (5t) WIN
--   J.HK(9t) > Land     ---------L    9t
--   Landing Advantage P2 +13t
--
--   EVERY TICK NUMBER CARRIES ITS t, in parentheses too (user, 2026-09-27:
--   統一感). Tick Data writes a startup the same way: Startup 5t.
--
-- Jump is P1's own jump, so everything about it is on the right, never in the
-- label - the label is the other side's moves (user, 2026-09-27). The jump
-- begins with its startup: three ticks still on the ground in the jump state
-- ($06 = 06, $07 = 00, $38 = 0; 244 of 244 takeoffs measured), then $38
-- rises. PreJump(3t) > Guard 4t is that startup, then the chain's first guard
-- on the fourth tick after leaving the ground (the first guard only). A hit
-- before it left the ground is PreJump Hit 3t, on the startup's third tick;
-- a guard that failed in the air, PreJump(3t) > Hit 4t (user, 2026-09-27).
-- Landings count from the jump's first tick: the jump as a whole.
--
-- (nt) IS STARTUP AS TICK DATA COUNTS IT (user, 2026-09-27): the tick the move
-- starts is 1, up to and including the tick its attack box first appears -
-- 発生 on a frame-data table. So "can I interrupt this gap" reads the way a
-- player already reads frame data: fastest, a move gets in if its startup is
-- no more than the gap.
--
-- THE OTHER SIDE'S STARTUP GOES ON THE MOVE YOU BLOCKED, the left of the
-- label (user, 2026-09-27). Every move of the chain is blocked once, the last
-- one on the row that runs to Land, so every startup shows. On the right,
-- the chain's first move never had one and each move lost it a row later.
--
-- L is a landing, P1's and P2's each in its own colour - the same colour as
-- that side under Landing Advantage (user, 2026-09-27).
--
-- WHAT IT RESTS ON, all measured by airGuardLog.lua over 120 air guards
-- (VSAV_MEMORY_NOTES.md, "空中ガード"):
--
--   * 0x025286 puts the defender back in the jump state ($05 = 00, $06 = 06)
--     on one tick, and it can act from the NEXT one. That next tick is 1 here.
--   * A press before it is thrown away, held or not: In Blockstun 14t at 9t
--     on the row above - the row whose hit began that stun.
--   * An interrupt wins when it connects before the next hit's tick; the same
--     tick is a trade. 30 of 30.
--   * $1B8 moves on the tick an attack starts (26 of 26), and $105 / $102 /
--     $101 name it the way tickDataVsav.lua does.
--
-- No tick count is written down here. Every one is read off the game.
--
-- THE ORDER OF THE TESTS IN on_tick MATTERS: your hit and the next hit on you
-- can land on the same tick, and that is the trade.

local P1, P2 = 0xFF8400, 0xFF8800
local MAX_ROWS = 8      -- rows kept per chain (display space, not game time)
local MAX_BAR  = 48     -- cells drawn per bar (display space, not game time)

-- GREY IS THE HEADER ROW ONLY; the bar's empty ticks are the darker grey
-- below. Everything that says something is white or its own colour
-- (user, 2026-09-27: 灰色はメーターやラベルだけ).
local C_HEAD  = "#AAAAAA"
local C_DASH  = "#555555"
local C_TEXT  = "#FFFFFF"
local C_WIN   = "#00FF00"
local C_TRADE = "#FFD700"
local C_HIT   = "#FF0000"
-- A landing, per side: the L on the bar and that side's number under Land.
-- BLUE AND ORANGE, NOT BLUE AND PINK. Pink was reported as indistinguishable
-- from the blue (user, 2026-09-27), and measured so: CIEDE2000 0.7 with
-- deuteranopia simulated. Blue against orange stays above 50 normally and
-- under all three simulated deficiencies (analysis/cvd_check.py).
-- P1 WAS #66CCFF UNTIL THE PRESSES TOOK THE INPUT COLUMN'S LIGHT BLUE
-- (#00CAFF): CIEDE2000 0.4 between the two. #4D79FF keeps 17.9 from it and
-- 59 from P2's orange under all four simulated visions (user, 2026-09-27).
local C_P1    = "#4D79FF"
local C_P2    = "#FF9900"
local RESULT_COLOR = { WIN = C_WIN, TRADE = C_TRADE, LATE = C_HIT }

local st

local function reset()
	st = {
		now = 0, chain = nil, row = nil, track = nil,
		-- The tick P1's current jump began (its startup, still on the ground)
		-- and the tick it left the ground.
		jump_start = nil, takeoff = nil,
		-- The other side's opening action - its jump or dash - and the first
		-- attack out of it (user, 2026-09-27: Jump > 6t J.LP(5t)).
		p2act = nil,
		-- The other side's current move: $1B8 when it started, the tick it
		-- started, the tick its attack box came out.
		p2 = {},
		-- YOUR MOVES' STARTUPS, learned whenever a box comes out - a whiff
		-- counts, no row needed - keyed with J. for air moves so a ground LP
		-- and a jumping LP stay apart. A startup belongs to the move, not the
		-- distance, so one sighting serves every later row (user, 2026-09-27:
		-- measured is fine, a guess is not).
		startup = {},
		p1 = {},
		-- What move_start compares against, per side.
		m1 = {}, m2 = {},
		was = { p1_05 = 0, p2_05 = 0, p1_38 = 0, p2_38 = 0, box1 = 0, box2 = 0, p1_js = false,
		        p2_js = false, p2_dash = false, p1_5c = 0, p2_5c = 0 },
		-- Who can act first after the chain's last contact (see ADVANTAGE).
		adv = nil,
	}
end
reset()

local function rb(a) return memory.readbyte(a) end
local function seq(base) return memory.readword(base + 0x1B8) end

-- WHEN DID A MOVE START? Three signs, any one of them:
--   * $1B8, the game's count of attacks started - every start for Aulbath and
--     Demitri (26 of 26), but Jedah's jump attacks never moved it (31 of 31
--     boxes in the 2026-09-27 logs). Counted from the last $1B8 alone, his
--     J.LK read a startup of 669 (user screenshot).
--   * the attack flag $105 rising - there 5 ticks before each Jedah box;
--   * a new strength / punch-kick pair while $105 stays up: a chained move.
-- A dash raises $105 by itself ($06 = 0x14, tickDataVsav.lua) and is no
-- attack - but a dash ATTACK is made inside that state too. Zabel's dash
-- raises $105 on the tick it becomes one ("同時に $105 も立つ"), and his dash
-- attacks move $1B8. A floating dash - Jedah's, Sasquatch's - carries $105 = 0
-- and raises it with its attack, without $1B8 (airg_s18-20, 2026-09-27: 3 of
-- 3; Sasquatch in VSAV_MEMORY_NOTES.md). So inside a dash already on, $105
-- rising is a start; on the dash's own first tick it is the dash. The first
-- tick only learns the values.
local function move_start(t, base)
	local s, f, s06 = seq(base), rb(base + 0x105), rb(base + 0x06)
	local id = (f ~= 0) and (rb(base + 0x102) * 256 + rb(base + 0x101)) or nil
	local rise = f ~= 0 and t.f == 0
	local fresh = t.f ~= nil and (s ~= t.seq
		or (s06 ~= 0x14 and (rise or (id ~= nil and t.id ~= nil and id ~= t.id)))
		or (s06 == 0x14 and t.s06 == 0x14 and rise))
	t.seq, t.f, t.id, t.s06 = s, f, id, s06
	return fresh, f
end

-- IS AN ATTACK BOX OUT? The read tickDataVsav.lua makes for Tick Data's
-- startup, and the hitbox display before it: $1C is the current animation cel,
-- +0x0A in that cel the attack box id, 0 for none.
local function attack_box(base)
	local cel = memory.readdword(base + 0x1C)
	if cel == nil or cel == 0 then return 0 end
	return memory.readbyte(cel + 0x0A)
end

-- $126 masked to the six attack buttons (0x77): bit0 LP, bit1 MP, bit2 HP,
-- bit4 LK, bit5 MK, bit6 HK (inputHistory.lua's layout).
local function buttons(v)
	return v - (math.floor(v / 8) % 2) * 8 - (math.floor(v / 128) % 2) * 128
end

-- A PRESS ON THE BAR IS THE BUTTON, NOT A COUNT (user, 2026-09-27: the count
-- meant nothing). P or K in the strength's colour - the signal colours the
-- dummy's input column already uses, read off its icons
-- (scripts/scrolling-input/capcom-8.png): light #00CAFF, medium #FFFF00,
-- heavy #FF0000. One cell holds one letter, so two buttons on one tick show
-- the heavier (a punch before a kick of the same strength).
local STRENGTH_COLOR = { L = "#00CAFF", M = "#FFFF00", H = "#FF0000" }
local BUTTON_BITS = {           -- heaviest first
	{ 4, "HP" }, { 64, "HK" }, { 2, "MP" }, { 32, "MK" }, { 1, "LP" }, { 16, "LK" },
}
local function button_of(bits)
	for _, b in ipairs(BUTTON_BITS) do
		if math.floor(bits / b[1]) % 2 == 1 then return b[2] end
	end
	return nil
end
local function button_cell(name)
	return { name:sub(-1), STRENGTH_COLOR[name:sub(1, 1)] or C_TEXT }
end

-- A normal by its button, a special only as a special (user, 2026-09-26: "必殺技
-- と分かればいい"). Same bytes as tickDataVsav.lua's move_name. The other
-- side's moves carry J. in the air, so an anti-air from the ground reads apart
-- from the chain; yours never do - here they are all air moves.
local STRENGTH = { [0] = "L", [2] = "M", [4] = "H" }
local function move_name(base, mark_air)
	local s06 = rb(base + 0x06)
	if s06 == 0x0E then return "SP" end
	if s06 == 0x10 then return "ES" end
	if s06 == 0x12 then return "EX" end
	-- $105 ALONE, not $06 = 06 with it: on the tick a hit lands the hit code has
	-- already written 02 02 00 00 over $04-$07, and an attack started on that
	-- same tick is still in $105 / $102 / $101 (airg_s16, 2026-09-27).
	if s06 == 0x0A or rb(base + 0x105) ~= 0 then
		local n = (STRENGTH[rb(base + 0x102)] or "?")
			.. ((rb(base + 0x101) == 0) and "P" or "K")
		if mark_air and rb(base + 0x38) ~= 0 then n = "J." .. n end
		return n
	end
	return "?"
end

-- The move that just arrived: read it now, or - if this tick already shows
-- the other side being hit - the move it had started (see the open gap below).
local function arriving(r)
	local n = move_name(P2, true)
	if n == "?" then n = r.foe_next or "?" end
	return n
end


local function enabled()
	return globals ~= nil and globals.options ~= nil
		and globals.options.display_air_guard_gap == true
end

local function on_tick()
	if not enabled() then
		if st.now ~= 0 then reset() end
		return
	end
	-- NOTHING CARRIES OVER A CHARACTER SELECT (user, 2026-09-27: the last chain
	-- stayed up against the next opponent). Off the match - the select screen,
	-- the walk-on - everything is dropped, the learned startups too: they were
	-- the old character's moves. The same test framedata.lua makes for Tick
	-- Data: match_running, then hotkeys_armed for "is the round live".
	local match = globals.match_running == nil or globals.match_running() == true
	local armed = globals.hotkeys_armed
	if armed == nil then armed = match end
	if not match or armed ~= true then
		if st.now ~= 0 then reset() end
		return
	end
	st.now = st.now + 1
	local now, w = st.now, st.was
	local p1_05, p1_06, p1_38 = rb(P1 + 0x05), rb(P1 + 0x06), rb(P1 + 0x38)
	-- THE JUMP'S STARTUP: in the jump state, still on the ground. Three ticks,
	-- then $38 rises and $07 goes to 02 (244 of 244 in the air guard logs).
	local p1_js = p1_05 == 0x00 and p1_06 == 0x06 and rb(P1 + 0x07) == 0x00 and p1_38 == 0
	if p1_js and not w.p1_js then st.jump_start, st.takeoff = now, nil end
	if p1_38 ~= 0 and w.p1_38 == 0 and w.p1_js then st.takeoff = now end
	-- A landing ends the jump: nothing later is counted from its takeoff. The
	-- rows keep their own copy for the numbers they already show.
	if p1_38 == 0 and w.p1_38 ~= 0 then st.takeoff = nil end
	local p2_05, p2_38 = rb(P2 + 0x05), rb(P2 + 0x38)
	local pressed = buttons(rb(P1 + 0x126))
	local box1, box2 = attack_box(P1), attack_box(P2)
	-- A box COMING OUT, not one already out: a move's own box appearing.
	local box1_up = box1 ~= 0 and w.box1 == 0
	local box2_up = box2 ~= 0 and w.box2 == 0

	-- THE OTHER SIDE'S CURRENT MOVE, followed all the time rather than per row,
	-- so the move that opens a chain - started before any row existed - has a
	-- startup too. A move that ends ($105 down) before a box came out leaves
	-- nothing to count from: a start is never carried into a later move.
	local p2_fresh, p2_f = move_start(st.m2, P2)
	-- THE OTHER SIDE'S OPENING ACTION: a jump (its startup on the ground, read
	-- the way P1's is) or a dash ($06 = 14), and the first attack out of it,
	-- counted from the action's first tick as 1. An action that ends with no
	-- attack - a jump that lands, a dash that stops - pairs with nothing later.
	local p2_06 = rb(P2 + 0x06)
	local p2_js = p2_05 == 0x00 and p2_06 == 0x06 and rb(P2 + 0x07) == 0x00 and p2_38 == 0
	local p2_dash = p2_05 == 0x00 and p2_06 == 0x14
	if p2_js and not w.p2_js then st.p2act = { kind = "Jump", at = now }
	elseif p2_dash and not w.p2_dash then st.p2act = { kind = "Dash", at = now } end
	local act = st.p2act
	if act ~= nil and act.atk == nil then
		if p2_fresh then
			act.atk, act.name = now, move_name(P2, true)
		else
			-- A jump lands only after it has left the ground: the tick its startup
			-- begins can look like a landing too (straight from the air, or a
			-- landing jumped out of at once).
			if act.kind == "Jump" and p2_38 ~= 0 then act.left = true end
			if (act.kind == "Jump" and act.left and p2_38 == 0)
			   or (act.kind == "Dash" and not p2_dash and w.p2_dash and p2_f == 0) then
				st.p2act = nil
			end
		end
	end
	local p2 = st.p2
	if p2_fresh then
		p2.start, p2.active = now, (box2_up and now or nil)
	elseif p2.start ~= nil and p2.active == nil then
		if box2_up then p2.active = now
		elseif p2_f == 0 then p2.start = nil end
	end
	-- The opening attack's own startup, for Jump > 6t J.LP(5t) (user,
	-- 2026-09-27). Its own, not the first guarded row's: an opening attack
	-- that whiffs is not the move blocked first.
	if act ~= nil and act.atk ~= nil and act.su == nil
	   and p2.start == act.atk and p2.active ~= nil then
		act.su = p2.active - p2.start + 1
	end
	-- YOUR CURRENT MOVE, the same way, so its startup is learned even where no
	-- row is open. Named on its start tick: the strength bytes are already set
	-- (26 of 26).
	local p1_fresh, p1_f = move_start(st.m1, P1)
	local p1t = st.p1
	if p1_fresh then
		p1t.start, p1t.key = now, move_name(P1, true)
		if box1_up then st.startup[p1t.key] = 1; p1t.start = nil end
	elseif p1t.start ~= nil then
		if box1_up then
			st.startup[p1t.key] = now - p1t.start + 1
			p1t.start = nil
		elseif p1_f == 0 then
			p1t.start = nil
		end
	end
	-- IN A GUARD, IN THE AIR: $54 = 0xFF from 0x018810, $38 as 0x023954 tests.
	local guard = p1_05 == 0x02 and rb(P1 + 0x54) == 0xFF and p1_38 ~= 0
	local p1_struck = p1_05 == 0x02 and w.p1_05 ~= 0x02
	local p2_struck = p2_05 == 0x02 and w.p2_05 ~= 0x02
	local r = st.row

	-- STARTUPS, before anything below can close the row on this same tick.
	if r ~= nil then
		if r.atk ~= nil and r.atk_active == nil and box1_up then r.atk_active = now end
	end

	-- YOUR PRESS AND YOUR ATTACK, ALSO BEFORE: a press on the very tick the next
	-- hit lands still starts an attack, and that attack is why the hit was not
	-- blocked - $1B8 moved on the J.HP's tick with the lever held back (airg_s16,
	-- 2026-09-27; 2 of 2 in the logs were hits, 47 of 47 without a press were
	-- guards). Read after the row closed, the row showed only the earlier EARLY.
	if r ~= nil and r.z ~= nil and now >= r.z then
		if pressed > 0 then r.presses[now] = pressed end
		if r.atk == nil and p1_fresh then
			r.atk, r.atk_name, r.atk_key = now, move_name(P1), move_name(P1, true)
			if box1_up then r.atk_active = now end
		end
	end

	-- YOUR ATTACK CONNECTED. Before the hit on you, so a same-tick pair is seen
	-- as the trade it is.
	if r ~= nil and r.atk ~= nil and r.struck == nil and p2_struck then
		r.struck = now
		if rb(P2 + 0x54) == 0xFF then
			r.result = "BLOCKED"
		else
			r.result = "WIN"
			r.next = r.foe_next
		end
	end

	-- THE NEXT HIT ARRIVED, blocked or not.
	if p1_struck then
		if r ~= nil then
			if r.result == "WIN" then
				if r.struck == now and not guard then
					r.result = "TRADE"
					r.end_at, r.end_kind, r.next = now, "hit", arriving(r)
				end
			else
				r.end_at, r.end_kind = now, guard and "guard" or "hit"
				r.next = arriving(r)
				if r.atk ~= nil then
					if r.result == nil then r.result = guard and "WHIFF" or "LATE" end
				elseif not guard then
					r.result = "HIT"
				end
			end
			st.row, r = nil, nil
		end
		if guard then
			if st.chain == nil or st.chain.closed then
				st.chain = { rows = {}, closed = false, approach = st.p2act }
				st.p2act = nil
			end
			local nr = { prev = move_name(P2, true), contact = now, early = {},
			             presses = {},
			             js = st.jump_start, takeoff = st.takeoff,
			             first = (#st.chain.rows == 0),
			             -- the move just blocked: its box has been out, it hit
			             prev_su = (p2.start ~= nil and p2.active ~= nil)
			                 and (p2.active - p2.start + 1) or nil }
			local rows = st.chain.rows
			if #rows >= MAX_ROWS then table.remove(rows, 1) end
			rows[#rows + 1] = nr
			st.row, st.track, r = nr, nr, nr
		elseif w.p1_js and st.jump_start ~= nil then
			-- CAUGHT IN THE JUMP'S STARTUP, before it left the ground: no air
			-- guard, so no chain - but not nothing either. One row saying so.
			st.chain = { closed = true, approach = st.p2act, rows = { {
				prev = move_name(P2, true), early = {}, presses = {},
				prev_su = (p2.start ~= nil and p2.active ~= nil)
				    and (p2.active - p2.start + 1) or nil,
				prejump = now - st.jump_start + 1,
				prejump_kind = (rb(P1 + 0x54) == 0xFF) and "Guard" or "Hit",
			} } }
			st.row, st.track, r, st.p2act = nil, nil, nil, nil
		elseif w.p1_05 == 0x00 and w.p1_38 ~= 0 and st.takeoff ~= nil
		       and (st.chain == nil or st.chain.closed) then
			-- HIT IN THE AIR, WITH NO GUARD BEFORE IT IN THIS JUMP: the guard
			-- failed. Free the tick before ($05 = 00) and in the air, so a
			-- juggle - already being hit - is not this. A hit after a guard in
			-- the same jump is that row's HIT / LATE, not a row of its own.
			st.chain = { closed = true, approach = st.p2act, rows = { {
				prev = move_name(P2, true), early = {}, presses = {},
				prev_su = (p2.start ~= nil and p2.active ~= nil)
				    and (p2.active - p2.start + 1) or nil,
				airhit = true, contact = now, js = st.jump_start, takeoff = st.takeoff,
			} } }
			st.row, st.track, r, st.p2act = nil, nil, nil, nil
		elseif st.chain ~= nil then
			st.chain.closed = true
		end
	end

	-- THE WIN FREEZES ITS BAR. Nothing after it is about that gap.
	if r ~= nil and r.result == "WIN" then st.row, r = nil, nil end

	-- LANDINGS. $38 back to 0, the same moment Advantage counts from.
	if p1_38 == 0 and w.p1_38 ~= 0 then
		if r ~= nil then
			if r.z == nil then r.z = now end
			r.end_at, r.end_kind, r.next = now, "land", "Land"
			if r.atk ~= nil and r.result == nil then r.result = "WHIFF" end
			st.row, r = nil, nil
		end
		if st.chain ~= nil then st.chain.closed = true end
	end
	if p2_38 == 0 and w.p2_38 ~= 0 and st.track ~= nil and st.track.foe_land == nil then
		st.track.foe_land = now
	end

	-- THE OPEN GAP.
	if r ~= nil then
		-- THE OTHER SIDE'S LATEST MOVE, named on the tick it starts - $1B8 and the
		-- strength bytes move together (measured). Kept because on a trade the
		-- hit has already turned it into a hit reaction ($06 = 00) by the tick
		-- this row ends, and the name can no longer be read there (seen on the
		-- machine, 2026-09-27: "j.MP > ?").
		-- After this row's contact only: the move that hit started before it.
		if p2_fresh and now > r.contact then r.foe_next = move_name(P2, true) end
		if r.z == nil then
			if pressed > 0 then
				-- Every press in the stun, in order: the tick and the button.
				r.early[#r.early + 1] = now
				r.early_btn = r.early_btn or {}
				r.early_btn[#r.early_btn + 1] = pressed
			end
			-- 0x025286's tick. You can act from the next one.
			if p1_05 == 0x00 and p1_06 == 0x06 then r.z = now + 1 end
		end
	end

	-- ADVANTAGE, AS TICK DATA TAKES IT (user, 2026-09-27: 当てた、殴られたも
	-- 出して): after the last contact, the first tick each side can act.
	--   * Hit or guarded: $05 back to 00. After a knockdown, $05 and $06 both
	--     00 - the wake-up is $06 - and a knockdown is $1A7 MOVING: it counts
	--     through the wake-up (VSAV_MEMORY_NOTES.md 6) and may still hold the
	--     last one's count.
	--   * The side that made the contact: touchdown in the air - the landing
	--     motion cancels into a grounded normal - or, on the ground, its attack
	--     ending ($105 back to 0).
	--   * Your air guard inside the chain: your touchdown. The next exchange is
	--     taken on the ground - both came down is two touchdowns.
	-- A contact is the $05 edge into 02, or - already in a hit, where $05
	-- stays 02 through a combo - hitstop ($5C) jumping back up, which every
	-- hit does (VSAV_MEMORY_NOTES.md). Each one before both can act starts it
	-- again, so a combo is judged from its last hit; once both can act it
	-- stands until the next chain.
	local p1_5c, p2_5c = rb(P1 + 0x5C), rb(P2 + 0x5C)
	local p1_contact = p1_struck or (p1_05 == 0x02 and w.p1_05 == 0x02 and p1_5c > w.p1_5c)
	local p2_contact = p2_struck or (p2_05 == 0x02 and w.p2_05 == 0x02 and p2_5c > w.p2_5c)
	local A = st.adv
	if st.chain ~= nil and (p1_contact or p2_contact)
	   and (A == nil or A.chain ~= st.chain or not A.done) then
		local function side(base, hit, air_guard, s38)
			local m
			if hit then m = air_guard and "land" or "stun"
			else m = (s38 ~= 0) and "land" or "attack" end
			return { mode = m, kd0 = rb(base + 0x1A7) }
		end
		st.adv = { chain = st.chain, at = now,
			p1 = side(P1, p1_contact, p1_struck and guard, p1_38),
			p2 = side(P2, p2_contact, false, p2_38) }
	elseif A ~= nil and not A.done and now > A.at then
		for _, x in ipairs({ { A.p1, P1, p1_05, p1_06, p1_38 }, { A.p2, P2, p2_05, p2_06, p2_38 } }) do
			local d, base, s05, s06, s38 = x[1], x[2], x[3], x[4], x[5]
			if d.free == nil then
				if rb(base + 0x1A7) ~= d.kd0 then d.kd = true end
				if (d.mode == "land" and s38 == 0)
				   or (d.mode == "attack" and rb(base + 0x105) == 0)
				   or (d.mode == "stun" and s05 == 0x00 and (not d.kd or s06 == 0x00)) then
					d.free = now
				end
			end
		end
		if A.p1.free ~= nil and A.p2.free ~= nil then A.done = true end
	end

	w.p1_05, w.p2_05, w.p1_38, w.p2_38 = p1_05, p2_05, p1_38, p2_38
	w.p1_5c, w.p2_5c = p1_5c, p2_5c
	w.p1_js = p1_js
	w.p2_js, w.p2_dash = p2_js, p2_dash
	w.box1, w.box2 = box1, box2
end

-- DRAWING, AS TEXT. Each line is a list of { text, colour } drawn left to right
-- at one glyph per character, so the offline test can read exactly what the
-- screen gets.

local function rel(r, t) return t - r.z + 1 end

local function bar_cells(r)
	local cells = {}
	if r.z == nil then return cells end
	local last
	if r.result == "WIN" then last = rel(r, r.struck)
	elseif r.end_at ~= nil then last = rel(r, r.end_at)
	else last = rel(r, st.now) end
	if last > MAX_BAR then last = MAX_BAR end
	for i = 1, last do cells[i] = { "-", C_DASH } end
	if r.foe_land ~= nil then
		local i = rel(r, r.foe_land)
		if i >= 1 and i <= last then cells[i] = { "L", C_P2 } end
	end
	for t, bits in pairs(r.presses) do
		local i = rel(r, t)
		if i >= 1 and i <= last then
			-- The press that started the attack shows the move that came out;
			-- any other shows what was pressed.
			local name = (t == r.atk and r.atk_name ~= nil and r.atk_name:match("^[LMH][PK]$"))
				and r.atk_name or button_of(bits)
			cells[i] = name and button_cell(name) or { "?", C_TEXT }
		end
	end
	if r.struck ~= nil then
		local i = rel(r, r.struck)
		if i >= 1 and i <= last then cells[i] = { "*", (r.result == "WIN") and C_WIN or C_TEXT } end
	end
	if r.end_at ~= nil and r.result ~= "WIN" then
		local i = rel(r, r.end_at)
		if i >= 1 and i <= last then
			if r.result == "TRADE" then cells[i] = { "#", C_TRADE }
			elseif r.end_kind == "land" then cells[i] = { "L", C_P1 }
			elseif r.end_kind == "hit" then cells[i] = { "|", C_HIT }
			else cells[i] = { "|", C_TEXT } end
		end
	end
	return cells
end

-- Before tick 1: the presses that were thrown away, and the other side landing
-- before you could act.
-- COLOURS HAVE ONE JOB EACH (user, 2026-09-27): grey is the header row, dark
-- grey a tick where nothing happened, white everything that says something -
-- the moves, the numbers, the next hit arriving - green / yellow / red are
-- results, and a landing takes its side's colour - blue P1, orange P2 -
-- on the bar and under Jump alike. Result words are all
-- capitals, the amount after them: LATE 4t (user, 2026-09-27).

-- Gap: the ticks you could act. A win leaves it unmeasured - the next hit
-- never came - so it is "?", in grey, rather than a borrowed number.
local function gap_cell(r)
	if r.result == "WIN" then return { "?", C_TEXT } end
	if r.z == nil or r.end_at == nil then return { "", C_HEAD } end
	return { (rel(r, r.end_at) - 1) .. "t", C_TEXT }
end

-- Press>Hit: LP 1t>5t (5t) WIN is LP pressed on tick 1 of the gap, hitting on
-- tick 5, with a startup of 5. Or the presses that were thrown away.
local function attack_cells(r)
	local out = {}
	if r.z == nil then return out end
	local function add(s, c) out[#out + 1] = { s, c } end
	if r.atk ~= nil then
		local a = rel(r, r.atk)
		-- In the strength's colour, as its letter on the bar (user, 2026-09-27:
		-- ボタン色をメモリのものと合わせる). A special has no strength: white.
		add(r.atk_name, (r.atk_name:match("^[LMH][PK]$") and STRENGTH_COLOR[r.atk_name:sub(1, 1)]) or C_TEXT)
		-- This attempt's startup if its box came out; otherwise the one learned
		-- for this move, which is what an attack cut short never shows.
		local sun = (r.atk_active ~= nil) and (r.atk_active - r.atk + 1) or st.startup[r.atk_key]
		local su = (sun ~= nil) and (" (" .. sun .. "t)") or ""
		if r.struck ~= nil then
			add(" " .. a .. "t>" .. rel(r, r.struck) .. "t", C_TEXT)
			if su ~= "" then add(su, C_TEXT) end
			add(" " .. r.result, RESULT_COLOR[r.result] or C_TEXT)
		else
			add(" " .. a .. "t", C_TEXT)
			if su ~= "" then add(su, C_TEXT) end
			if r.result == "LATE" then
				-- HOW LATE, from the move's startup: pressed on tick p, its box is
				-- out on p + startup - 1, and that has to come by the gap's last
				-- tick. The last press that can is gap - startup + 1; below 1 the
				-- move never fits this gap (NO GAP). The box coming out is not
				-- the box reaching - distance can still add to it - so this is
				-- the least it needed, never more.
				local ok = (sun ~= nil and r.end_at ~= nil)
					and ((rel(r, r.end_at) - 1) - sun + 1) or nil
				if ok ~= nil and ok < 1 then
					add(" NO GAP", C_HIT)
				else
					add(" LATE", C_HIT)
					if ok ~= nil and a > ok then add(" " .. (a - ok) .. "t", C_HIT) end
				end
			elseif r.result ~= nil then
				add(" " .. r.result, C_TEXT)
			end
		end
	else
		-- Nothing came out. The presses thrown away before it are on the row
		-- above, with the stun they were in.
		if r.result == "HIT" then add("HIT", C_HIT) end
	end
	return out
end

-- JUMP, ONE LINE UNDER THE TABLE, NOT A COLUMN (user, 2026-09-27: the rows ran
-- into the dummy's input column at the right edge). It was never about one
-- row: the jump's first guard (the first only), where each side landed - P1 /
-- P2 as the rest of the tool says it, in that side's colour ("foe" was not
-- understood, and @ is hard to read in this font) - or a jump caught before
-- it left the ground. Counted from the tick the jump began.
local function opening_cells(rows)
	local out = {}
	local r1 = rows[1]
	if r1.prejump ~= nil then
		-- No ">": the startup never finished, nothing came after it (user).
		out[#out + 1] = { "PreJump ", C_TEXT }
		out[#out + 1] = { r1.prejump_kind, (r1.prejump_kind == "Hit") and C_HIT or C_TEXT }
		out[#out + 1] = { " " .. r1.prejump .. "t", C_TEXT }
	elseif r1.airhit then
		out[#out + 1] = { "PreJump(", C_TEXT }
		out[#out + 1] = { (r1.takeoff - r1.js) .. "t", C_TEXT }
		out[#out + 1] = { ") > ", C_TEXT }
		out[#out + 1] = { "Hit", C_HIT }
		out[#out + 1] = { " " .. (r1.contact - r1.takeoff + 1) .. "t", C_TEXT }
	elseif r1.first and r1.js ~= nil then
		if r1.takeoff ~= nil then
			-- The startup on the ground, then the guard counted from leaving it.
			out[#out + 1] = { "PreJump(", C_TEXT }
			out[#out + 1] = { (r1.takeoff - r1.js) .. "t", C_TEXT }
			out[#out + 1] = { ") > Guard ", C_TEXT }
			out[#out + 1] = { (r1.contact - r1.takeoff + 1) .. "t", C_TEXT }
		else
			out[#out + 1] = { "Guard ", C_TEXT }
			out[#out + 1] = { (r1.contact - r1.js + 1) .. "t", C_TEXT }
		end
	end
	return out
end

-- WHO CAME OUT AHEAD, AND BY HOW MUCH (user, 2026-09-27: 全体 tick 数より
-- アドバンテージで). Tick Data's Advantage, taken from your side: the tick the
-- other side can act minus the tick you can, after the chain's last contact
-- (ADVANTAGE in on_tick). Nothing until both can act.
-- Shown as the side that is ahead, in its colour: P2 +18t. LANDING ADVANTAGE,
-- ITS OWN LINE (user, 2026-09-27: 着地時点の有利不利): your side is your
-- touchdown in all but a knockdown of you (then your wake-up), so it reads as
-- where things stand as you come down - "+18 on landing". A label, so grey.
local function advantage_cells()
	local A = st.adv
	if A == nil or A.chain ~= st.chain or not A.done then return {} end
	local adv = A.p2.free - A.p1.free
	local out = { { "Landing Advantage ", C_HEAD } }
	if adv > 0 then out[#out + 1] = { "P1 +" .. adv .. "t", C_P1 }
	elseif adv < 0 then out[#out + 1] = { "P2 +" .. (-adv) .. "t", C_P2 }
	else out[#out + 1] = { "0t", C_TEXT } end
	return out
end

local function width(cells)
	local n = 0
	for _, c in ipairs(cells) do n = n + #c[1] end
	return n
end
local function spaces(n) return { string.rep(" ", math.max(n, 0)), C_HEAD } end

-- THE PRESSES A BLOCKSTUN THREW AWAY (user, 2026-09-27): In Blockstun 14t at
-- 9,13t - the stun a guard began, counted from the contact as 1, and the
-- ticks you pressed in it, each in its button's strength colour. Only when
-- something was pressed ("押した時だけでいい"). Blockstun, not hitstop: the
-- freeze ($5C) is 11 of those 14 ticks, and Tick Data's Hitstun leaves the
-- freeze out. The length is read every time, so a move with a hitstop of its
-- own shows its own (Jedah's J.HP: 6t, 29 of 29). A stun cut short by the
-- next hit has no length, only the presses.
local MAX_STUN_PRESSES = 3      -- presses listed per stun (display space, not game time)
-- The presses listed: all of them, or when mashed the first and the last with
-- ".." between (0) - when it began and ended.
local function shown(n)
	local out = {}
	if n <= MAX_STUN_PRESSES then
		for k = 1, n do out[k] = k end
	else
		out = { 1, 0, n }
	end
	return out
end

-- WHICH BUTTONS, right after the hit that began the stun (user, 2026-09-27:
-- メーターの後ろで押すボタン): P or K in the strength's colour, in order. Which,
-- not when - the ticks are in the Blockstun text, the same presses.
local function early_cells(r)
	local out = {}
	for _, k in ipairs(shown(#(r.early_btn or {}))) do
		local name = (k > 0) and button_of(r.early_btn[k]) or nil
		out[#out + 1] = (k == 0) and { "..", C_TEXT } or (name and button_cell(name) or { "?", C_TEXT })
	end
	return out
end
local function stun_cells(r)
	local out = {}
	local n = #r.early
	if n == 0 then return out end
	out[#out + 1] = { "In Blockstun " .. ((r.z ~= nil) and ((r.z - r.contact) .. "t ") or "") .. "at ", C_TEXT }
	-- One t for the whole list, after the last (user, 2026-09-27: 9,10,11t).
	-- Mashed: 2..12t.
	local show = shown(n)
	for i, k in ipairs(show) do
		if k == 0 then
			out[#out + 1] = { "..", C_TEXT }
		else
			if i > 1 and show[i - 1] ~= 0 then out[#out + 1] = { ",", C_TEXT } end
			local name = button_of(r.early_btn[k])
			out[#out + 1] = { (r.early[k] - r.contact + 1) .. ((i == #show) and "t" or ""),
			                  name and STRENGTH_COLOR[name:sub(1, 1)] or C_TEXT }
		end
	end
	return out
end

-- Capitalised like every label in the menu (user, 2026-09-27).
local HEAD_GAP, HEAD_ATK, HEAD_JUMP = "Gap", "Press>Hit", "Jump  "

-- THE OPENING AS ONE MOVE (user, 2026-09-27): Jump > 6t J.LP(5t) - the jump,
-- the attack out on its sixth tick, and that attack's startup. The tick goes
-- in front of what happened on it, as Tick Data's timeline writes it
-- (1t PreJump > 4t Air > 10t MP). A dash the same way: Dash > 10t LP(5t).
local function opening_label(ap)
	return ap.kind .. " > " .. (ap.atk - ap.at + 1) .. "t " .. (ap.name or "?")
		.. ((ap.su ~= nil) and ("(" .. ap.su .. "t)") or "")
end

-- One column per question, headed on the first line so the right-hand side
-- says what it is (user, 2026-09-27: "右側の何かがわからん").
local function lines()
	if st.chain == nil or #st.chain.rows == 0 then return {} end
	local rows = st.chain.rows
	local built, lw, bw = {}, 0, 0
	for i, r in ipairs(rows) do
		built[i] = {
			label = (r.prev or "?")
				.. ((r.prev_su ~= nil) and ("(" .. r.prev_su .. "t)") or "")
				.. ((r.prejump ~= nil or r.airhit) and "" or (" > " .. (r.next or "?"))),
			bar = bar_cells(r), gap = gap_cell(r),
			atk = attack_cells(r),
		}
	end
	-- A BLOCKSTUN GOES ON THE ROW ABOVE (user, 2026-09-27: 一段前の行): the row
	-- whose hit, at its "|", began it. The chain's first stun follows the
	-- opening, so it goes where your guard is - the opening row, or under the
	-- table when there is none.
	local ap0 = st.chain.approach
	local has_ap = ap0 ~= nil and ap0.atk ~= nil
	local first_stun, first_marks = {}, {}
	for i, r in ipairs(rows) do
		local cells = stun_cells(r)
		if #cells > 0 then
			if i > 1 then
				-- The buttons right after that row's "|", the hit that began the
				-- stun; the Blockstun text in its Press>Hit column.
				local bar = built[i - 1].bar
				for _, c in ipairs(early_cells(r)) do bar[#bar + 1] = c end
				local atk = built[i - 1].atk
				if #atk > 0 then atk[#atk + 1] = spaces(2) end
				for _, c in ipairs(cells) do atk[#atk + 1] = c end
			else
				first_stun, first_marks = cells, early_cells(r)
			end
		end
	end
	local opening = opening_cells(rows)
	if has_ap then
		lw = math.max(lw, #opening_label(ap0))
		-- The first stun's buttons take the opening row's bar column, right
		-- after the attack that began it - as a later stun's follow its "|".
		bw = math.max(bw, width(first_marks))
	end
	for _, b in ipairs(built) do
		lw = math.max(lw, #b.label)
		-- In characters: a mashed stun's ".." is one cell of two.
		bw = math.max(bw, width(b.bar))
	end
	local left = lw + 2 + bw + 2
	local out = { {
		{ "AirGap", C_HEAD }, spaces(left - 6 + 3 - #HEAD_GAP),
		{ HEAD_GAP .. "  ", C_HEAD }, { HEAD_ATK, C_HEAD },
	} }
	-- THE OPENING, ABOVE THE GUARDS (user, 2026-09-27): what the other side did
	-- before the chain and the buttons pressed in the stun of that first
	-- attack; yours - your jump and your guard ("自分のガードタイミングは一行目
	-- に") - right of Gap ("ギャップより右にガードなんだらを"). The stun's
	-- Blockstun text has no room left on that row - beside your guard the row
	-- ran past 90 characters, into the input display at the right edge - so
	-- when you pressed in it, it takes the line under, in the same column.
	if has_ap then
		local lab = opening_label(ap0)
		local l = { { lab, C_TEXT }, spaces(lw - #lab + 2) }
		for _, c in ipairs(first_marks) do l[#l + 1] = c end
		l[#l + 1] = spaces(bw - width(first_marks) + 2 + 3 + 2)
		for _, c in ipairs(opening) do l[#l + 1] = c end
		out[#out + 1] = l
		if #first_stun > 0 then
			local u = { spaces(lw + 2 + bw + 2 + 3 + 2) }
			for _, c in ipairs(first_stun) do u[#u + 1] = c end
			out[#out + 1] = u
		end
	end
	for _, b in ipairs(built) do
		local l = { { b.label, C_TEXT }, spaces(lw - #b.label + 2) }
		for _, c in ipairs(b.bar) do l[#l + 1] = c end
		l[#l + 1] = spaces(bw - width(b.bar) + 2 + 3 - #b.gap[1])
		l[#l + 1] = b.gap
		l[#l + 1] = spaces(2)
		for _, c in ipairs(b.atk) do l[#l + 1] = c end
		out[#out + 1] = l
	end
	-- Under the table: your opening and the first stun when no opening row
	-- took them - the buttons right after your guard - then, on a line of its
	-- own, who came out ahead.
	local jl = {}
	if not has_ap then
		for _, c in ipairs(opening) do jl[#jl + 1] = c end
		if #first_marks > 0 then
			if #jl > 0 then jl[#jl + 1] = spaces(1) end
			for _, c in ipairs(first_marks) do jl[#jl + 1] = c end
		end
		if #first_stun > 0 then
			if #jl > 0 then jl[#jl + 1] = spaces(2) end
			for _, c in ipairs(first_stun) do jl[#jl + 1] = c end
		end
	end
	if #jl > 0 then
		local l = { { HEAD_JUMP, C_HEAD } }
		for _, c in ipairs(jl) do l[#l + 1] = c end
		out[#out + 1] = l
	end
	local lc = advantage_cells()
	if #lc > 0 then out[#out + 1] = lc end
	return out
end

-- The same lines flattened, for the test and for reading a log.
local function text()
	local out = {}
	for i, l in ipairs(lines()) do
		local s = ""
		for _, c in ipairs(l) do s = s .. c[1] end
		out[i] = (s:gsub("%s+$", ""))
	end
	return out
end

local subscribed = false

return {
	["on_tick"] = on_tick,
	["lines"] = lines,
	["text"] = text,
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
