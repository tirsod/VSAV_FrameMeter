-- THE PUSH BLOCK READOUT HAS TO AGREE WITH THE NUMBER THE GAME IS USING.
--
-- $170 is the count 0x02760E and 0x02761E read to decide the push block, and
-- the game clears it when GUARD STUN ENDS (0x024AF2 / 0x024B1A), not when a
-- blocked hit re-arms the window (0x023966). timers.lua used to reset there,
-- so through a multi-hit blocked string the readout restarted from zero while
-- the game kept counting. Measured over eleven granted push blocks: seven
-- disagreed, the worst reading 1 against the game's 4
-- (analysis/pb_flag_probe_20260913.log, 2026-09-13).
--
-- The count and the granted flag also have to move together. They did not:
-- the flag was only cleared at 0x023966 while hud.lua zeroed the count on its
-- own when the row was switched off, which drew a green 0 on the red
-- nothing-counted box (user screenshot, 2026-09-13).
--
-- This drives the two ROM hooks by hand, because nothing else can: they only
-- run when the game reaches those addresses.
--
-- Run from scripts/ - the requires below are relative.
--   cd scripts && lua5.1 ../analysis/test_pb_counter.lua
local P1, P2 = 0xFF8400, 0xFF8800

local ram = {}
local execs = {}
local a6 = P1
memory = {
	readbyte = function(x) return ram[x] or 0 end,
	readbytesigned = function(x) return ram[x] or 0 end,
	readword = function(x) return ram[x] or 0 end,
	readwordsigned = function(x) return ram[x] or 0 end,
	readdword = function(x) return ram[x] or 0 end,
	readdwordsigned = function(x) return ram[x] or 0 end,
	writebyte = function(x, v) ram[x] = v end,
	writeword = function(x, v) ram[x] = v end,
	writedword = function(x, v) ram[x] = v end,
	registerexec = function(addr, f) execs[addr] = f end,
	getregister = function() return a6 end,
}
gui = { text = function() end, box = function() end, rect = function() end }
emu = { framecount = function() return 1 end, screenwidth = function() return 384 end,
        screenheight = function() return 224 end }
globals = { options = {}, dummy = {}, controlling_p1 = true }
package.preload["./scripts/debugKnockdown"] = function()
	return { mark_write = function() end }
end

local timersModule = dofile("timers.lua")
local timers = timersModule.registerBefore()

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

want("0275E0 のフックがある", type(execs[0x0275E0]), "function")
want("027632 のフックがある", type(execs[0x027632]), "function")
-- The reset hook is gone on purpose: the game's own state is the reset.
want("023966 のフックは無い", execs[0x023966], nil)

-- THE STATE THE ROUTINE IS ENTERED IN.
--
-- Reaching 0x0275E0 already means the window is open ($1ab, tested two
-- instructions earlier). The rest are what the ROM checks after this point and
-- what timers.lua repeats: hurt-and-guarding, guard recovery, no $3b4, no
-- global $15d, and a button edge in $126.
local function guarding(who, count, granted, pressing)
	a6 = who
	ram[who + 0x170] = count
	ram[who + 0x184] = granted and 1 or 0
	ram[who + 0x04] = 0x0202
	ram[who + 0x140] = 0x02
	ram[who + 0x3B4] = 0
	ram[0xFF815D] = 0
	ram[who + 0x126] = pressing and 0x01 or 0x00
end

-- One tick inside the window. The game adds to $170 itself when it takes the
-- press, which is what the caller does through `count`.
local function tick(who, count, granted, pressing)
	guarding(who, count, granted, pressing)
	execs[0x0275E0]()
end

local function grant(who)
	a6 = who
	execs[0x027632]()
end

print("-- ガードして 3 回押す")
tick(P1, 0, false, false)                 -- window open, nothing pressed yet
want("押す前は 0", timers.p1_pushblock_counter, 0)
want("押す前は成立していない", timers.p1_pushblock_ok, false)
tick(P1, 0, false, true)
want("1 回目", timers.p1_pushblock_counter, 1)
tick(P1, 1, false, true)
want("2 回目", timers.p1_pushblock_counter, 2)
tick(P1, 2, false, true)
want("3 回目", timers.p1_pushblock_counter, 3)
grant(P1)
want("成立した", timers.p1_pushblock_ok, true)
want("成立しても数は 3 のまま", timers.p1_pushblock_counter, 3)

print("-- 成立後も押し続ける ($170 は止まる)")
tick(P1, 3, true, true)
want("成立後の 1 回目は 4", timers.p1_pushblock_counter, 4)
tick(P1, 3, true, true)
want("成立後の 2 回目は 5", timers.p1_pushblock_counter, 5)
want("成立の色は残る", timers.p1_pushblock_ok, true)

print("-- 多段ガードの 2 発目。ゲームは $170 を消さない")
-- 0x023966 re-arms $1ab and leaves $170 and $184 where they were. The readout
-- has to carry on from the game's number, which is the bug this test exists
-- for: it used to restart from zero here.
tick(P1, 3, true, true)
want("2 発目でも巻き戻らない", timers.p1_pushblock_counter, 6)

print("-- ガード硬直が明けた。ゲームが $170 と $184 を消す")
-- 0x024AF2 / 0x024B1A. The reading stays up so it can be read, and goes on the
-- first tick of the NEXT guard.
want("硬直明けでも表示は残る", timers.p1_pushblock_counter, 6)
tick(P1, 0, false, false)
want("次のガードで消える", timers.p1_pushblock_counter, 0)
want("成立の色も一緒に消える", timers.p1_pushblock_ok, false)

print("-- 途中から見始めても、ゲームの数に合わせる")
-- A savestate load, a script reload, or simply a tick the hook did not get
-- puts $170 somewhere no Lua-side tally knows about. Counting up from one here
-- is the shape of the original bug, and the only case that separates "follow
-- the game's byte" from "keep our own": both give the same answer while the
-- two happen to agree.
tick(P1, 0, false, false)
want("土台を消した", timers.p1_pushblock_counter, 0)
tick(P1, 5, false, true)
want("見ていなかった分も入る", timers.p1_pushblock_counter, 6)
tick(P1, 0, false, false)

print("-- 押していないティックは数えない")
tick(P1, 0, false, false)
want("押さなければ増えない", timers.p1_pushblock_counter, 0)

print("-- ガードしていなければ数えない")
tick(P1, 0, false, true)
want("土台として 1", timers.p1_pushblock_counter, 1)
guarding(P1, 1, false, true)
ram[P1 + 0x04] = 0x0000          -- not in hitstun/blockstun
execs[0x0275E0]()
want("$04 が違えば増えない", timers.p1_pushblock_counter, 1)
guarding(P1, 1, false, true)
ram[P1 + 0x140] = 0x00           -- not the guard recovery kind
execs[0x0275E0]()
want("$140 が違えば増えない", timers.p1_pushblock_counter, 1)
guarding(P1, 1, false, true)
ram[0xFF815D] = 1                -- intro disarmament
execs[0x0275E0]()
want("$15d が立てば増えない", timers.p1_pushblock_counter, 1)
ram[0xFF815D] = 0

print("-- P2 は別勘定")
tick(P2, 0, false, true)
want("P2 が 1", timers.p2_pushblock_counter, 1)
want("P1 は動かない", timers.p1_pushblock_counter, 1)
grant(P2)
want("P2 が成立", timers.p2_pushblock_ok, true)
want("P1 は成立していない", timers.p1_pushblock_ok, false)

print("-- プレイヤー以外のオブジェクトは無視する")
local before = timers.p1_pushblock_counter
tick(0xFF8C00, 0, false, true)
want("他のオブジェクトでは動かない", timers.p1_pushblock_counter, before)

print("-- 0 なのに成立している状態は作れない")
-- The screenshot: a green digit on the red "nothing counted" box. Both are
-- published from the same place now, so the pair cannot come apart.
local bad = 0
for _, who in ipairs({ P1, P2 }) do
	for _, n in ipairs({ 0, 1, 3 }) do
		for _, g in ipairs({ true, false }) do
			for _, press in ipairs({ true, false }) do
				tick(who, n, g, press)
			end
		end
	end
	local c = (who == P1) and timers.p1_pushblock_counter or timers.p2_pushblock_counter
	local o = (who == P1) and timers.p1_pushblock_ok or timers.p2_pushblock_ok
	if c == 0 and o then bad = bad + 1 end
end
want("count 0 かつ ok true にならない", bad, 0)

if fails == 0 then
	print("test_pb_counter ok")
else
	print(fails .. " 件 NG")
	os.exit(1)
end
