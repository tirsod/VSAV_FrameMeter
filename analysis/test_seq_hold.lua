-- HOLD: THE DIRECTION STAYS DOWN AFTER THE ATTACK.
--
-- A charge move is a direction held and then let go. A step's input otherwise
-- exists for the one tick it is written - the walker frees the delivery slot
-- and nothing writes 0xFF8B94 again until the next step - so nothing charges.
--
-- The Hold row on an attack marks the step, the compiler turns it into the
-- LEVER of the last entry with the buttons stripped, and the walker keeps
-- asserting that until the next step takes over.
--
-- This drives the real compiler and a stand-in for the walker built to the same
-- rules, recording what lands on the input word each tick.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_seq_hold.lua
local ram = {}
memory = {
	readbyte  = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = { guard_action = "sequence" }, options = {} }
training_settings = { action_sequences = {} }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end
-- キャンセル方向の地図 (guardCancel が公開する seq_dash_cancel_reverse の代役)。
seq_dash_cancel_reverse = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }

local csrc = io.open("controller.lua"):read("*a")
local cs = csrc:find("function make_input_sequence", 1, true)
local ce = csrc:find("\nend", csrc:find("return _sequence", cs, true), true)
assert(cs and ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(csrc:sub(cs, ce + 4)))()

-- The record queue_input_sequence builds, reduced to what the walker uses.
local queued = nil
function queue_input_sequence(_d, _seq)
	queued = { sequence = _seq, current_frame = 1 }
	_d.pending_input_sequence = queued
end

local R = dofile("actionSequenceRunner.lua")

local fails = 0
local function fail(what, got, want)
	fails = fails + 1
	print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
end

-- Names to bits, the same mapping entry_to_bits uses (facing 0 = forward is
-- 0x02). Buttons are only distinguished from zero here.
local BITS = { forward = 0x02, back = 0x01, down = 0x04, up = 0x08 }
local function to_bits(entry)
	local lev, btn = 0, 0
	for _, k in ipairs(entry or {}) do
		if BITS[k] then lev = lev + BITS[k] else btn = 1 end
	end
	return lev, btn
end
local function lev_name(lev)
	if lev == 0 then return "-" end
	local out = {}
	for _, k in ipairs({ "up", "down", "back", "forward" }) do
		if lev % (BITS[k] * 2) >= BITS[k] then out[#out + 1] = k end
	end
	return table.concat(out, "+")
end

local P2 = 0xFF8800
local function set_free() ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0 ; ram[P2 + 0x38] = 0 end
local function set_stun() ram[P2 + 0x05] = 2 ; ram[P2 + 0x06] = 0x0A ; ram[P2 + 0x38] = 0 end

-- THE WALKER, TO THE SAME RULES AS guardCancel's seq_tick BLOCK.
--
-- Two passes so one tick can end a segment and start the next; the v158 hold
-- (buttonless entries take two ticks); the hold picked up when a segment runs
-- off its end; and dropped once the schedule is empty.
local held_lever = nil
local defender = {}
local log = {}
local function tick()
	local wrote = nil
	for _pass = 1, 2 do
		R.service(defender)
		local s = defender.pending_input_sequence
		if s == nil or s.sequence == nil then break end
		held_lever = nil
		local i = s.current_frame or 1
		if i <= #s.sequence then
			local lev, btn = to_bits(s.sequence[i])
			wrote = { lev = lev, btn = btn, src = "step" }
			local hold = (btn == 0 and lev ~= 0) and 2 or 1
			s.tick_held = (s.tick_held or 0) + 1
			if s.tick_held >= hold then
				s.current_frame = i + 1
				s.tick_held = 0
			end
			break
		end
		held_lever = s.seq_hold
		defender.pending_input_sequence = nil
	end
	if wrote == nil and held_lever ~= nil then
		if R.pending_count() == 0 then
			held_lever = nil
		else
			local lev = to_bits(held_lever)
			wrote = { lev = lev, btn = 0, src = "hold" }
		end
	end
	log[#log + 1] = wrote or { lev = 0, btn = 0, src = "none" }
	return log[#log]
end
local function run(n) for _ = 1, n do tick() end end
local function trace()
	local out = {}
	for _, e in ipairs(log) do
		out[#out + 1] = e.src .. ":" .. lev_name(e.lev) .. (e.btn ~= 0 and "+B" or "")
	end
	return table.concat(out, " ")
end

local function install(steps)
	ram[0xFF8B82] = 0x08                       -- Bishamon
	training_settings.action_sequences = { reversal = { ["8"] = { version = 1, steps = steps } } }
end
local function start()
	log = {} ; held_lever = nil ; queued = nil
	defender = {}
	R.cancel()
	R.arm("reversal")                          -- 1 歩目は呼び出し側が出す
end

print("[1] Hold なし - ステップを出したら方向は離れる")
install({
	{ action = "atk", lever = "none",      button = "LP", wait = 0 },
	{ action = "atk", lever = "down-back", button = "LP", wait = -1 },
})
start()
set_free()
run(6)
do
	local held = 0
	for _, e in ipairs(log) do if e.src == "hold" then held = held + 1 end end
	if held ~= 0 then fail("保持したティック数", held, 0)
	else print("  ok 保持は 0 ティック   " .. trace()) end
end

print("[2] Hold あり - 次のステップまで方向が残り、ボタンは落ちる")
install({
	{ action = "atk", lever = "none",      button = "LP", wait = 0 },
	{ action = "atk", lever = "down-back", button = "LP", hold = true, wait = -1 },
	{ action = "atk", lever = "forward",   button = "HP", wait = -1 },
})
start()
set_free()
run(1)          -- 2 歩目を出させる
-- ここで硬直に入れる。自由なままだと 3 歩目が使い切りと同じティックで
-- キューされてしまい、保持が始まる前に上書きされる。
set_stun()
run(12)
do
	local held, btn_leak = 0, 0
	for _, e in ipairs(log) do
		if e.src == "hold" then
			held = held + 1
			if e.lev ~= (0x04 + 0x01) then fail("保持しているレバー", lev_name(e.lev), "down+back") end
			if e.btn ~= 0 then btn_leak = btn_leak + 1 end
		end
	end
	if held < 10 then fail("硬直中に保持したティック数", held, ">= 10") end
	if btn_leak ~= 0 then fail("保持にボタンが混ざったティック数", btn_leak, 0) end
	if fails == 0 then
		print(string.format("  ok 硬直 12 ティックのうち %d ティック down+back を保持、ボタンは 0", held))
	end
end

print("[3] 硬直が明けたら次のステップが上書きする")
set_free()
local before = #log
run(6)
do
	local switched = false
	for i = before + 1, #log do
		if log[i].src == "step" then switched = true break end
	end
	if not switched then fail("3 歩目が出たか", "出ていない", "出る")
	else print("  ok 保持 → 3 歩目へ切り替わった") end
end

print("[4] 最後のステップのあとは何も残さない")
do
	run(8)
	local tail_hold = 0
	for i = #log - 5, #log do
		if log[i] and log[i].src == "hold" then tail_hold = tail_hold + 1 end
	end
	if tail_hold ~= 0 then fail("シーケンス終了後に保持していたティック数", tail_hold, 0)
	else print("  ok ダミーは方向にもたれたままにならない") end
end

print("[5] 保持していても、次が裸の方向なら先頭ニュートラルで一度離す")
-- opens_with_direction が入れるニュートラルは、押しっぱなしの方向に押しエッジが
-- 立たない問題への対処。Hold と噛み合っていないと歩き出しやダッシュが死ぬ。
install({
	{ action = "atk",    lever = "none",      button = "LP", wait = 0 },
	{ action = "atk",    lever = "down-back", button = "LP", hold = true, wait = -1 },
	{ action = "dash.f", wait = -1 },
})
local sched = R.compile(training_settings.action_sequences.reversal["8"])
do
	local third = sched[3].sequence
	local first_is_neutral = (#third[1] == 0)
	if not first_is_neutral then
		local names = {}
		for _, k in ipairs(third[1]) do names[#names + 1] = k end
		fail("ダッシュの先頭エントリ", table.concat(names, "+"), "ニュートラル")
	else
		print("  ok ダッシュは先頭ニュートラルから始まる(保持が解ける)")
	end
end

print("[6] Hold は最後のエントリの方向だけを取る")
do
	local one = R.compile({ version = 1, steps = {
		{ action = "atk", lever = "none",         button = "LP", wait = 0 },
		{ action = "atk", lever = "down-forward", button = "HK", hold = true, wait = -1 },
	} })
	local h = one[2].hold
	local names = {}
	for _, k in ipairs(h or {}) do names[#names + 1] = k end
	table.sort(names)
	local got = table.concat(names, "+")
	if got ~= "down+forward" then fail("hold の中身", got, "down+forward")
	else print("  ok hold = down+forward   ボタン HK は入っていない") end
end

print("[6b] 1 歩目の Hold も効くこと - 20 ティック歩いて投げ")
-- 1 歩目はアームが出すので、runner のキュー地点(seq_hold を付ける場所)を
-- 通らない。取りこぼすと歩かないまま投げに行って、届かず何も出ない。
install({
	{ action = "walk.f", hold = true,  wait = 0 },
	{ action = "atk", lever = "forward", button = "HK", hold = true, wait = 20 },
})
do
	local sched = R.compile(training_settings.action_sequences.reversal["8"])
	local h = sched[1].hold
	local names = {}
	for _, k in ipairs(h or {}) do names[#names + 1] = k end
	if table.concat(names, "+") ~= "forward" then
		fail("1 歩目の hold", table.concat(names, "+"), "forward")
	end
	-- アームは 1 歩目の入力リストしか返さないので、hold は別に預けられる。
	R.cancel()
	R.arm("reversal")
	local taken = R.take_arm_hold()
	local tn = {}
	for _, k in ipairs(taken or {}) do tn[#tn + 1] = k end
	if table.concat(tn, "+") ~= "forward" then
		fail("預けた 1 歩目の hold", table.concat(tn, "+"), "forward")
	end
	-- 一度きり。ウォーカーは毎ティック聞きに来るので、2 回返すと
	-- 2 歩目の保持を上書きしてしまう。
	if R.take_arm_hold() ~= nil then fail("2 回目", "値が返った", "nil") end
	-- cancel で捨てられること。
	R.cancel()
	R.arm("reversal")
	R.cancel()
	if R.take_arm_hold() ~= nil then fail("cancel 後", "値が残っている", "nil") end
	if fails == 0 then print("  ok 1 歩目の hold は預けられ、一度だけ取り出せ、cancel で消える") end
end

print("[7] Hold を付けていないステップの hold は nil")
do
	local two = R.compile({ version = 1, steps = {
		{ action = "atk", lever = "none",      button = "LP", wait = 0 },
		{ action = "atk", lever = "down-back", button = "LP", wait = -1 },
	} })
	if two[2].hold ~= nil then fail("hold", tostring(two[2].hold), "nil")
	else print("  ok nil") end
end

print("[8] ダッシュキャンセルの rev - タップの 2 ティック後から保持し、合流で消える")
do
	-- 状態機械を直接叩く。park はセグメント終端 (= 最後のタップ) で呼ばれ、
	-- 保持はその 2 ティック後から始まる (v207: 先に置くとダッシュが消える)。
	-- 256 の半周期を過ぎると黙る - 保持が 2 秒も続くことはなく、いつかは
	-- 合流か cancel で終わるというこの機構の性質の 保険。
	R.cancel()
	R.park_rev("back", 100)
	if R.rev_lever_now(100) ~= nil then fail("park したティック", "既に立った", "nil") end
	if R.rev_lever_now(101) ~= nil then fail("1 ティック後", "既に立った", "nil") end
	if R.rev_lever_now(102) ~= "back" then fail("2 ティック後", tostring(R.rev_lever_now(102)), "back") end
	if R.rev_lever_now(150) ~= "back" then fail("48 ティック後も", tostring(R.rev_lever_now(150)), "back") end
	if R.rev_lever_now(230) ~= nil then fail("半周期を超えたら", "立った", "nil") end
	-- 合流で消える。ウォーカーはエントリを書いた後に rev_clear を呼ぶ。
	R.rev_clear()
	if R.rev_lever_now(102) ~= nil then fail("clear 後", "残っている", "nil") end
	if fails == 0 then print("  ok park → 2 ティック後に立ち、clear で消える") end
end

print("[8b] 1 歩目が cancel ステップ - arm が rev を預け、キャンセルで消える")
do
	install({
		{ action = "dashc.f", wait = -1 },
		{ action = "atk", lever = "none", button = "HP", wait = -1 },
	})
	local sched = R.compile(training_settings.action_sequences.reversal["8"])
	if sched[1].rev ~= "back" then fail("compile の rev", tostring(sched[1].rev), "back") end
	if sched[1].hold ~= nil then fail("compile の hold", tostring(sched[1].hold), "nil") end
	R.cancel()
	R.arm("reversal")
	-- hold は握りつぶされているので、take_arm_hold は何も返さない。
	if R.take_arm_hold() ~= nil then fail("cancel ステップの hold", "値が返った", "nil") end
	-- 記録が終わる前は立たない。_due は一度だけ返り、park する。
	if R.rev_lever_now(50) ~= nil then fail("記録が終わる前", "立った", "nil") end
	if R.arm_rev_due(50) ~= "back" then fail("arm_rev_due", tostring(R.arm_rev_due(50)), "back") end
	if R.rev_lever_now(51) ~= nil then fail("park 直後", "立った", "nil") end
	if R.rev_lever_now(52) ~= "back" then fail("2 ティック後", tostring(R.rev_lever_now(52)), "back") end
	R.cancel()
	if R.rev_lever_now(52) ~= nil then fail("cancel 後", "残っている", "nil") end
	if fails == 0 then print("  ok 1 歩目の rev は預けられ、一度だけ受け取り、cancel で消える") end
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
