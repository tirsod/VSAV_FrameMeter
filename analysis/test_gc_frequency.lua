-- GUARD ACTION FREQUENCY - ONE DRAW PER BLOCKED HIT.
--
-- Two defects, found one after the other:
--
--   1. shouldGC() was called from guardCancelCheck once per DISPLAYED FRAME
--      while the arm is a LATCH. A failed roll returned early without clearing
--      the arm, so the next frame drew again:
--          P(fire) = 1 - (1 - p)^frames        50% over 10 frames = 99.9%
--
--   2. The first fix drew once per STUN SPAN, and a span is not one
--      opportunity. BLK.episode is cleared on every rise of $158 - "EVERY
--      BLOCKED HIT GETS ITS OWN MOTION" - so a three-hit blockstring arms three
--      times inside one span. One draw for three turns 58% into 25%, which is
--      what "25% feels low" was.
--
--   3. The second fix drew once per ARM, and an arm is not one opportunity
--      either: BLK.episode is ALSO cleared whenever $140 leaves the block
--      recovery values, so one blocked hit re-arms several times and each
--      re-arm drew again. Back to ~100%, which is what "25% but it behaves as
--      100%" was.
--
-- The opportunity is a BLOCKED HIT - the $158 rise, the boundary the code
-- itself names. gc_opportunity counts those, and the roll is drawn once per
-- count. This runs the real shouldGC() and gc_should_perform() out of
-- guardCancel.lua, with the earlier forms beside them so the numbers the user
-- actually saw are in the output rather than asserted from memory.
--
-- Run from scripts/ - the read below is relative.
--   cd scripts && lua5.1 ../analysis/test_gc_frequency.lua
globals = { options = { gc_freq = 3 } }
-- guardCancel.lua ではグローバル。ここでも同じ形にする。
gc_opportunity = 0
memory = { readbyte = function() return 0 end }

local marks = {}
debugKnockdownModule = { mark_write = function(k, v)
	marks[k] = (marks[k] or 0) + 1
	marks[k .. ":true"] = (marks[k .. ":true"] or 0) + ((v == 1) and 1 or 0)
end }

-- The real functions, sliced out of guardCancel.lua. Taking them from the file
-- is the point: if the roll moves back into a per-frame path this stops
-- matching what ships. shouldGC is a file local, lifted so the old forms can be
-- measured with the same generator underneath.
local src = io.open("guardCancel.lua"):read("*a")
local s = src:find("local function maybe(x)", 1, true)
local e = src:find("\nfunction gc_should_perform(", s, true)
assert(s and e, "guardCancel.lua に maybe/gc_should_perform が見つからない")
e = src:find("\nend", e + 30, true)
assert(e, "gc_should_perform の終端が見つからない")
assert(loadstring(src:sub(s, e + 4) .. "\n_G.shouldGC = shouldGC\n"))()
assert(type(gc_should_perform) == "function", "gc_should_perform が取り出せていない")
assert(type(shouldGC) == "function", "shouldGC が取り出せていない")

local fails = 0
local function fail(what, got, want)
	fails = fails + 1
	print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
end

-- ONE ARM: the latch stands for `hold` displayed frames waiting to be consumed,
-- and guardCancelCheck asks on every one of them. It fires if the gate was open
-- while the arm stood. A refusal clears the arm, which is why the loop stops.
local ARM_HOLD = 4
local function arm()
	for i = 1, ARM_HOLD do
		if not gc_should_perform(true) then
			gc_should_perform(false)   -- 拒否でアームは落ちる
			return false
		end
		if i == ARM_HOLD then
			gc_should_perform(false)   -- 消費されてアームが降りる
			return true
		end
	end
end

-- ONE BLOCKED HIT. $158 が上がるので機会がひとつ増える。
--
-- その 1 発の中で BLK.episode は $140 でも解除されるので、武装は
-- `rearms` 回まで立ち直す。機会は 1 つなので抽選も 1 回でなければならない。
local function blocked_hit(rearms)
	local any = false
	gc_opportunity = gc_opportunity + 1        -- $158 の立ち上がり
	for _ = 1, (rearms or 1) do
		if arm() then any = true end
		gc_should_perform(false)
	end
	return any
end

-- ONE BLOCKSTRING: `hits` 発、各発が機会 1 つ。
local function blockstring(hits, rearms)
	local any = false
	for _ = 1, hits do
		if blocked_hit(rearms) then any = true end
		for _ = 1, 3 do gc_should_perform(false) end   -- 次のガードまでの間
	end
	return any
end

-- 旧 1: 毎フレーム抽選。ラッチが立っている間ずっと引き直す。
local function blockstring_perframe(hits, stun_frames)
	local any = false
	for _ = 1, hits do
		for _ = 1, stun_frames do if shouldGC() then any = true end end
	end
	return any
end

-- 旧 2: スパンに 1 回。連続ガード全体で 1 回しか引かない。
local function blockstring_perspan(hits)
	local roll = shouldGC()
	return roll and hits > 0
end

local N = 20000
local LABEL = { [0x1] = "None", [0x2] = "25%", [0x3] = "50%", [0x4] = "75%", [0x5] = "100%" }
local PCT   = { [0x1] = 0, [0x2] = 25, [0x3] = 50, [0x4] = 75, [0x5] = 100 }
local FREQS = { 0x1, 0x2, 0x3, 0x4, 0x5 }

print("[1] 1 発ガードにつき抽選は 1 回 - 中で 5 回武装し直しても")
marks = {}
globals.options.gc_freq = 0x3
math.randomseed(1)
local fired = 0
for _ = 1, N do if blocked_hit(5) then fired = fired + 1 end end
if marks["gc_roll"] ~= N then fail("抽選回数", marks["gc_roll"], N) end
if marks["gc_roll:true"] ~= fired then
	fail("当たりの回数と発動回数が一致しない", marks["gc_roll:true"], fired)
end
if fails == 0 then
	print(string.format("  ok %d 発 → 抽選 %d 回(1 発の中で 5 回武装、各 %d フレーム保持)",
		N, marks["gc_roll"], ARM_HOLD))
end

print("[2] 1 発ガードの発動率がメニューの表記どおりか")
print("     メニュー   期待    武装1回   武装5回(これが 100% になっていた)")
for _, f in ipairs(FREQS) do
	globals.options.gc_freq = f
	math.randomseed(f * 977)
	local one = 0
	for _ = 1, N do if blocked_hit(1) then one = one + 1 end end
	math.randomseed(f * 977)
	local many = 0
	for _ = 1, N do if blocked_hit(5) then many = many + 1 end end
	local want = PCT[f]
	local ok = math.abs(one * 100 / N - want) <= 1.5
	           and math.abs(many * 100 / N - want) <= 1.5
	if not ok then fails = fails + 1 end
	print(string.format("%s%-8s  %3d%%    %5.1f%%    %5.1f%%",
		ok and "  ok " or "  NG ", LABEL[f], want, one * 100 / N, many * 100 / N))
end

print("[3] 3 発の連続ガード - 1 発ごとに機会があること")
print("     メニュー   期待    修正後   旧1(毎フレーム)  旧2(スパン1回)")
for _, f in ipairs(FREQS) do
	globals.options.gc_freq = f
	local p = PCT[f] / 100
	local want = (1 - (1 - p) ^ 3) * 100
	math.randomseed(f * 31)
	local a = 0
	for _ = 1, N do if blockstring(3, 5) then a = a + 1 end end
	math.randomseed(f * 31)
	local b = 0
	for _ = 1, N do if blockstring_perframe(3, 12) then b = b + 1 end end
	math.randomseed(f * 31)
	local c = 0
	for _ = 1, N do if blockstring_perspan(3) then c = c + 1 end end
	local got = a * 100 / N
	local ok = math.abs(got - want) <= 1.5
	if not ok then fails = fails + 1 end
	print(string.format("%s%-8s  %5.1f%%  %5.1f%%      %5.1f%%          %5.1f%%",
		ok and "  ok " or "  NG ", LABEL[f], want, got, b * 100 / N, c * 100 / N))
end

print("[4] 拒否された機会は、その間ずっとゲートが閉じていること")
-- ここは一度「アームが立っていない間は開ける」と書いていて、それが None でも
-- 毎回出る原因だった。リアクティブ経路はアームを必要とせず、この早期 return
-- だけで塞がれている。だから拒否の答えは機会の全フレームに効かないといけない。
globals.options.gc_freq = 0x1        -- None
gc_opportunity = gc_opportunity + 1
local leaked = 0
for _ = 1, 100 do
	if gc_should_perform(false) then leaked = leaked + 1 end   -- アーム無しの frame
	if gc_should_perform(true)  then leaked = leaked + 1 end   -- アーム有りの frame
end
if leaked > 0 then fail("None なのにゲートが開いたフレーム数", leaked, 0)
else print("  ok None なら 200 フレームすべて閉じている") end

-- 当たった機会は逆に、アームの有無にかかわらず開いたままでなければならない。
globals.options.gc_freq = 0x5        -- 100%
gc_opportunity = gc_opportunity + 1
local closed = 0
for _ = 1, 100 do
	if not gc_should_perform(false) then closed = closed + 1 end
	if not gc_should_perform(true)  then closed = closed + 1 end
end
if closed > 0 then fail("100% なのにゲートが閉じたフレーム数", closed, 0)
else print("  ok 100% なら 200 フレームすべて開いている") end

print("[5] None は 0%、100% は 100%")
for _, f in ipairs({ 0x1, 0x5 }) do
	globals.options.gc_freq = f
	local hit = 0
	for _ = 1, 500 do if blocked_hit(3) then hit = hit + 1 end end
	local want = (f == 0x5) and 500 or 0
	if hit ~= want then fail(LABEL[f], hit, want)
	else print(string.format("  ok %-4s は %d/500", LABEL[f], hit)) end
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
