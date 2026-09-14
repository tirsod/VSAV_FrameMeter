-- A REFUSED CHANCE MUST NOT INHERIT THE LAST ONE'S LEFTOVERS.
--
-- Guard Action Frequency was fixed three times by reasoning about the gate and
-- was wrong three times, because the gate was never the leak.
--
-- M.arm() returns step one and parks steps two onward inside the runner, where
-- nothing in the game can end them - "NO TIMEOUT ANYWHERE HERE". A schedule
-- that could not finish because the dummy got blocked again simply waited, and
-- came out on a later block that the roll had refused. On screen that is
-- indistinguishable from a fresh guard action, which is why three fixes to the
-- gate changed nothing visible.
--
-- test_gc_frequency.lua checks the gate's probability. This checks that one
-- chance is one self-contained unit.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_gc_leftover.lua
local ram = {}
memory = {
	readbyte  = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = {}, options = {} }
training_settings = { action_sequences = {} }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end

-- The real make_input_sequence, lifted out of controller.lua.
local csrc = io.open("controller.lua"):read("*a")
local cs = csrc:find("function make_input_sequence", 1, true)
local ce = csrc:find("\nend", csrc:find("return _sequence", cs, true), true)
assert(cs and ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(csrc:sub(cs, ce + 4)))()

-- Records what the runner hands over, so "did a step go out" is observable.
local queued = {}
function queue_input_sequence(_d, _seq)
	queued[#queued + 1] = _seq
	_d.pending_input_sequence = { sequence = _seq, current_frame = 1 }
end

local R = dofile("actionSequenceRunner.lua")

local fails = 0
local function fail(what, got, want)
	fails = fails + 1
	print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
end
local function eq(what, got, want)
	if got == want then print("  ok " .. what .. " = " .. tostring(got))
	else fail(what, got, want) end
end

local P2 = 0xFF8800
local CID = 0xFF8B82

-- A five-step sequence, the shape the user actually had set up.
local function install_sequence()
	ram[CID] = 0x0F                       -- Jedah
	training_settings.action_sequences = { reversal = { ["15"] = { version = 1, steps = {
		{ action = "atk", lever = "none",      button = "LP", wait = 0 },
		{ action = "atk", lever = "down-back", button = "LP", wait = -1 },
		{ action = "atk", lever = "down-back", button = "MP", wait = -1 },
		{ action = "atk", lever = "down-back", button = "HP", wait = -1 },
		{ action = "atk", lever = "none",      button = "HK", wait = -1 },
	} } } }
end

-- The dummy's state. free = can act, stun = blocked and cannot.
local function set_free()
	ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0 ; ram[P2 + 0x38] = 0
end
local function set_stun()
	ram[P2 + 0x05] = 2 ; ram[P2 + 0x06] = 0x0A ; ram[P2 + 0x38] = 0
end

local defender = {}
local function tick(n)
	for _ = 1, (n or 1) do
		defender.pending_input_sequence = nil   -- 前のステップは配信済み
		R.service(defender)
	end
end

install_sequence()

print("[1] 当たった機会 - 1 歩目が返り、2〜5 歩目が積まれる")
queued = {}
local first = R.arm("reversal")
if first == nil then fail("arm が nil を返した", "nil", "1 歩目の入力列") end
eq("積まれた残りステップ", R.pending_count(), 4)

print("[2] ガード硬直中は残りが出ない")
set_stun()
tick(30)
eq("硬直 30 ティックで出た数", #queued, 0)
eq("まだ待っている数", R.pending_count(), 4)

print("[3] 自由になれば出る - これ自体は正しい動作")
set_free()
tick(20)
if #queued == 0 then fail("自由になっても出ない", 0, "1 つ以上") end
print("     " .. #queued .. " 歩出た、残り " .. R.pending_count())

print("[4] 拒否された機会が、前の残りを持ち込まないこと")
-- 機会 1: 当たり。1 歩目が出て 2〜5 歩目が積まれる。
queued = {}
R.cancel()
R.arm("reversal")
eq("機会 1 の残り", R.pending_count(), 4)
-- ダミーはすぐ次のガードに入るので、残りは出せないまま。
set_stun()
tick(30)
eq("硬直中に出た数", #queued, 0)
-- 機会 2: 外れ。guardCancelCheck の拒否地点が cancel() を呼ぶ。
R.cancel()
eq("拒否のあとの残り", R.pending_count(), 0)
-- ここで自由になっても、何も出てはいけない。
set_free()
tick(40)
eq("拒否後に自由になって出た数", #queued, 0)

print("[5] カウンタが数えている")
R.cancel()
R.steps_fired = 0
R.steps_dropped = 0
R.arm("reversal")
set_free()
tick(40)
local _fired = R.steps_fired
R.cancel()
print(string.format("     seq=%d drop=%d 残り=%d", _fired, R.steps_dropped, R.pending_count()))
if _fired + R.steps_dropped ~= 4 then
	fail("出た数と捨てた数の合計", _fired + R.steps_dropped, 4)
else
	print("  ok 出た数 + 捨てた数 = 積まれた 4 歩")
end

print("[6] 拒否は捨てた数として数えられる")
R.cancel()
R.steps_fired = 0
R.steps_dropped = 0
R.arm("reversal")
R.cancel()
eq("捨てた数", R.steps_dropped, 4)
eq("出た数", R.steps_fired, 0)

print("[7] 拒否地点が実際に cancel() を呼んでいるか")
-- 上のテストは cancel() の動作を見ているだけなので、guardCancelCheck が
-- それを呼ぶことは別に確かめる。ここが外れると、動作テストは全部通ったまま
-- 実機だけが壊れる - 今回まさにその状態だった。
local gsrc = io.open("guardCancel.lua"):read("*a")
local blk = gsrc:match("if _arm_now and not should_perform then(.-)\n\tend")
if blk == nil then
	fail("拒否地点", "見つからない", "if _arm_now and not should_perform then ... end")
else
	local want = {
		["arm_edge = false"]                       = "ダウンのアームを落とす",
		["hs_arm_edge = false"]                    = "やられのアームを落とす",
		["BLK.edge = false"]                       = "ガードのアームを落とす",
		["actionSequenceRunnerModule.cancel()"]    = "前の機会の残りを捨てる",
	}
	for pat, why in pairs(want) do
		if blk:find(pat, 1, true) then print("  ok " .. why)
		else fail(why, "拒否地点に無い", pat) end
	end
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
