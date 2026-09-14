-- HIT-STUN COUNTDOWN: THE ENTRY COUNT HAS TO BE IN IT.
--
-- The countdown decides when a reversal's motion starts going in, working back
-- from "the final direction lands on free-1". Its derivation names three
-- entries - first, second-to-last, last - and subtracted one displayed frame
-- for the single delivery between them. A command with more entries has more
-- deliveries, and those were unaccounted for: the whole motion went in early,
-- completed early, and timed out of the recogniser (14-19 ticks) before the
-- dummy could act.
--
-- Measured by the user: every 3-entry command comes out, no 5- or 6-entry one
-- does, and the only place a long one DOES work is after a Chaos Flare - the
-- one reaction routed through hs_0c_arm_at, the only arm point that already
-- scaled with the entry count.
--
-- The block is READ FROM SOURCE rather than copied here. A copy would keep
-- passing after the real one lost the term, which is the failure this exists to
-- prevent.
--
-- Run from scripts/ - the read below is relative.
--   cd scripts && lua5.1 ../analysis/test_hs_countdown.lua
local src = io.open("guardCancel.lua"):read("*a")
local s = src:find("-- HOW MANY ENTRIES THE COMMAND HAS", 1, true)
local e = src:find("\nend", src:find("local function hs_countdown_for", s, true), true)
assert(s and e, "hs_countdown_for が guardCancel.lua に見つからない")

-- The constants the block reads, at the values guardCancel declares them with.
-- Taken from source too, for the same reason.
local function const(name)
	local v = src:match("\nlocal " .. name .. "%s*=%s*(%-?%d+)")
	assert(v ~= nil, name .. " が読めない")
	return tonumber(v)
end
local HS_TARGET_HOLD     = const("HS_TARGET_HOLD")
local hs_ticks_per_frame = const("hs_ticks_per_frame")

local ENTRIES = nil
local env = {
	HS_TARGET_HOLD = HS_TARGET_HOLD,
	hs_ticks_per_frame = hs_ticks_per_frame,
	seq_len = function() return ENTRIES end,
	globals = { dummy = { counter_attack_stick = 1 } },
	type = type,
}
local chunk = assert(loadstring(src:sub(s, e + 4)
	.. "\nreturn hs_countdown_for, hs_entries, HS_BASE_ENTRIES"))
setfenv(chunk, env)
local countdown, entries_of, BASE = chunk()

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- The three leads $59 gives, measured 82/82 (HS_LEAD_BY_59).
local LEADS = { 14, 19, 23 }

print("[1] 3 エントリは実測調整済みの値から動かない")
-- lead - (hold + 1) - tpf, with no excess. This is the expression every
-- measured batch was recorded against; changing it would move a working case.
for _, lead in ipairs(LEADS) do
	ENTRIES = 3
	want("lead " .. lead, countdown(lead), lead - (HS_TARGET_HOLD + 1) - hs_ticks_per_frame)
end

print("\n[2] 3 より短い命令でも動かない")
-- Clamped, not extrapolated: a 1- or 2-entry motion is not a case the constants
-- were measured against either, and shortening the countdown there would start
-- it later than anything that has been tested.
for _, n in ipairs({ 1, 2 }) do
	ENTRIES = n
	want(n .. " エントリ", countdown(19), 19 - (HS_TARGET_HOLD + 1) - hs_ticks_per_frame)
end

print("\n[3] 長い命令は 1 エントリごとに 1 フレーム分早く始める")
ENTRIES = 3
local base = countdown(19)
for _, n in ipairs({ 4, 5, 6 }) do
	ENTRIES = n
	want(n .. " エントリ", countdown(19), base - (n - 3) * hs_ticks_per_frame)
end

print("\n[4] 端の扱い")
ENTRIES = 6
want("短い lead でも 1 を下回らない", countdown(8), 1)
ENTRIES = nil
want("seq_len が答えないときは 3 エントリ扱い", countdown(19),
     19 - (HS_TARGET_HOLD + 1) - hs_ticks_per_frame)


print("\n[5] 前置きの余裕が長さに依らず一定であること")
-- 本題。entry k は queue+k+1、free-1 は署名。だから最後の前置きは
-- free-(queue-len) に落ちる。ここが一定でないと、長い命令だけ署名のティックに
-- ぶつかって末尾のエントリが落ちる - 実測では LK が消えた。
for _, n in ipairs({ 3, 4, 5, 6 }) do
	ENTRIES = n
	local _queue = 14 - countdown(14)      -- free からの距離
	local _slack = (_queue - n) - 1        -- 最後の前置きと free-1 の間
	want(n .. " エントリの余裕", _slack, 4)
end

print("\n[6] エントリ数を答える側の契約")
-- countdown からは見えない。3 以下はどれも excess 0 に丸められるので、既定値が
-- 1 でも 3 でも同じ答えになる。ここで直接聞く。
ENTRIES = nil
want("seq_len が答えないときは基準値", entries_of(), BASE)
ENTRIES = "5"
want("数値でなければ基準値", entries_of(), BASE)
ENTRIES = 0
want("0 以下なら基準値", entries_of(), BASE)
ENTRIES = 6
want("答えたらその数", entries_of(), 6)
-- guardCancel はここが読み込まれる時点で globals が立っていない場面を持つ。
env.globals = nil
want("globals が無ければ基準値", entries_of(), BASE)
env.globals = { dummy = { counter_attack_stick = 1 } }
print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
