-- RANDOM DELAY (v11.7.21.1): A STEP'S OWN RANDOM EXTRA ON TOP OF ITS WAIT.
--
-- Each Action Steps step can add a fresh draw of 0..N game Ticks (N up to 60)
-- after its Wait, whatever the Wait is - a number, After, a measured Auto,
-- Landing or a connection window. Step one's is drawn on the arm together with
-- Random Start Wait. This drives the real runner on a stand-in for
-- guardCancel's tick walker.
--
--   [1]  the setting, clamped, on the compiled step
--   [2]  a numbered Wait: the step comes out the drawn number of Ticks later
--   [3]  After: counted from the tick the dummy can act
--   [4]  a fresh draw on every loop pass
--   [5]  step one: drawn for the arm, and not counted twice on the deferred start
--   [6]  Action Patterns: the arm runs the pattern the draw was made for
--   [7]  the wiring that is only visible in the source
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_random_delay.lua
local ram = {}
memory = {
	readbyte  = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
}
gui = { text = function() end, box = function() end }
emu = { framecount = function() return 1 end }
globals = { dummy = { guard_action = "sequence" }, options = {} }
training_settings = { action_sequences = {}, random_start_wait = 0 }
function mark_training_settings_dirty() end
function dash_attack_ticks_for() return nil end
seq_dash_cancel_reverse = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }

local function slurp(path)
	local fh = io.open(path)
	assert(fh, path .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

local csrc = slurp("controller.lua")
local cs = csrc:find("function make_input_sequence", 1, true)
local ce = csrc:find("\nend", csrc:find("return _sequence", cs, true), true)
assert(cs and ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(csrc:sub(cs, ce + 4)))()

function queue_input_sequence(_d, _seq)
	_d.pending_input_sequence = { sequence = _seq, current_frame = 1 }
end

package.loaded["./scripts/randomStartWait"] = dofile("randomStartWait.lua")
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
local CLOCK = 0xFF8081
local CID = 0xFF8B82

-- The walker's two passes per tick and the v158 pacing, as in
-- test_random_start_wait. Each entry is logged on the first tick it goes in.
local now = 0
local defender = {}
local log = {}
local function cost(e)
	if #e == 0 then return 1 end
	for _, k in ipairs(e) do
		if k ~= "forward" and k ~= "back" and k ~= "up" and k ~= "down" then return 1 end
	end
	return 2
end
local function walk_tick()
	ram[CLOCK] = now % 256
	for _ = 1, 2 do
		if not R.owns(globals.dummy.guard_action) then break end
		R.service(defender)
		local s = defender.pending_input_sequence
		if s == nil or not s.seq_tick then break end
		local i = s.current_frame or 1
		if i <= #s.sequence then
			local e = s.sequence[i]
			if (s.tick_held or 0) == 0 then log[#log + 1] = { tick = now, entry = e } end
			s.tick_held = (s.tick_held or 0) + 1
			if s.tick_held >= cost(e) then s.current_frame = i + 1 ; s.tick_held = 0 end
			break
		end
		defender.pending_input_sequence = nil
	end
	now = now + 1
end
local function run(n) for _ = 1, n do walk_tick() end end
local function free() ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0 ; ram[P2 + 0x38] = 0 end
local function busy() ram[P2 + 0x05] = 0 ; ram[P2 + 0x06] = 0x0A ; ram[P2 + 0x38] = 0 end
local function has(e, k)
	for _, v in ipairs(e or {}) do if v == k then return true end end
	return false
end
local function ticks_of(k)
	local out = {}
	for _, l in ipairs(log) do if has(l.entry, k) then out[#out + 1] = l.tick end end
	return out
end

local function install(steps)
	ram[CID] = 0x0F
	training_settings.action_sequences = { reversal = { ["15"] = { version = 1, steps = steps } } }
end
local function start()
	R.cancel()
	defender = {}
	log = {}
	now = 0
	globals.dummy.guard_action = "sequence"
end

-- The arm places step one; here it is queued straight, as the arm's slot would
-- hold it, so the runner's own timing is what is measured.
local function arm()
	local first = R.arm("reversal")
	queue_input_sequence(defender, first)
	defender.pending_input_sequence.seq_tick = true
end

local real_random = math.random
local function rand_max() math.random = function(a, b) return b or a end end
local function rand_seq(list)
	local k = 0
	math.random = function(a, b)
		k = k + 1
		return list[k] or (b or a)
	end
end
local function rand_real() math.random = real_random end

-- ---------------------------------------------------------------------------
print("[1] 設定は 0..60 に丸めてコンパイル結果に載る")
eq("無し", R.random_delay_of({}), 0)
eq("5", R.random_delay_of({ random_delay = 5 }), 5)
eq("負は 0", R.random_delay_of({ random_delay = -3 }), 0)
eq("上限 60", R.random_delay_of({ random_delay = 75 }), 60)
eq("数でないものは 0", R.random_delay_of({ random_delay = "x" }), 0)
eq("端数は切り捨て", R.random_delay_of({ random_delay = 7.9 }), 7)
install({
	{ action = "atk", lever = "none", button = "LP", wait = 0 },
	{ action = "atk", lever = "none", button = "LK", wait = 6, random_delay = 10 },
})
local sched = R.schedule("reversal")
eq("2 歩目に載る", sched and sched[2].rdelay, 10)
eq("載せていない歩は 0", sched and sched[1].rdelay, 0)

-- ---------------------------------------------------------------------------
print("[2] 数値の Wait: 引いた分だけ遅れて出る")
local function gap(rd, draw)
	install({
		{ action = "atk", lever = "none", button = "LP", wait = 0 },
		{ action = "atk", lever = "none", button = "LK", wait = 6, random_delay = rd },
	})
	start() ; free()
	if draw ~= nil then rand_seq({ draw }) else rand_max() end
	arm()
	run(40)
	rand_real()
	local lp, lk = ticks_of("LP")[1], ticks_of("LK")[1]
	return (lp and lk) and (lk - lp) or nil
end
local g0 = gap(0)
eq("Random Delay 0 は今までどおり (Wait 6)", g0, 6)
eq("10 で上限を引いたら 16", gap(10), 16)
eq("10 で 3 を引いたら 9", gap(10, 3), 9)
eq("10 で 0 を引いたら 6 のまま", gap(10, 0), 6)

-- ---------------------------------------------------------------------------
print("[3] After: 動けるようになってから数える")
install({
	{ action = "atk", lever = "none", button = "LP", wait = 0 },
	{ action = "atk", lever = "none", button = "LK", wait = -1, random_delay = 8 },
})
start() ; busy()
rand_max()
arm()
run(5)                                     -- 1 歩目の後、まだ動けない
free()
local F = now
run(30)
rand_real()
local lk = ticks_of("LK")[1]
eq("動けるようになってから 8 Tick 後に押す", lk and (lk - F), 8)

-- ---------------------------------------------------------------------------
print("[4] ループの各周で引き直す")
install({
	{ action = "atk", lever = "none", button = "LP", wait = 0 },
	{ action = "atk", lever = "none", button = "LK", wait = 6, random_delay = 10 },
})
training_settings.action_steps_loop = true
training_settings.action_steps_loop_wait = 10
start() ; free()
rand_seq({ 2, 9, 5 })
arm()
run(120)
rand_real()
training_settings.action_steps_loop = false
local lps, lks = ticks_of("LP"), ticks_of("LK")
local gaps = {}
for k = 1, 3 do
	if lps[k] and lks[k] then gaps[#gaps + 1] = lks[k] - lps[k] end
end
eq("1 周目 6 + 2", gaps[1], 8)
eq("2 周目 6 + 9", gaps[2], 15)
eq("3 周目 6 + 5", gaps[3], 11)

-- ---------------------------------------------------------------------------
print("[5] 1 歩目: アームで引き、遅らせた開始では二重に数えない")
install({
	{ action = "atk", lever = "none", button = "LP", wait = 0, random_delay = 8 },
	{ action = "atk", lever = "none", button = "LK", wait = 6 },
})
start()
rand_max()
eq("1 歩目の Random Delay を引く", R.draw_first_delay("reversal"), 8)
install({
	{ action = "atk", lever = "none", button = "LP", wait = 0 },
	{ action = "atk", lever = "none", button = "LK", wait = 6 },
})
eq("無ければ 0", R.draw_first_delay("reversal"), 0)
install({
	{ action = "atk", lever = "none", button = "LP", wait = 0, random_delay = 8 },
	{ action = "atk", lever = "none", button = "LK", wait = 6 },
})
-- guardCancel が Random Start Wait と合わせて 8 を渡した形。押しは自由に
-- なった Tick の 8 Tick 後で、step.rdelay の 8 がもう一度足されてはいけない。
start() ; free()
R.arm_deferred("reversal", { wait = 8, adj = 0, delay = 0, hold_dir = false })
F = now
run(30)
rand_real()
local lp = ticks_of("LP")[1]
eq("押しは F + 8 (16 ではない)", lp and (lp - F), 8)

-- ---------------------------------------------------------------------------
print("[6] Action Patterns: 引いたパターンをアームがそのまま使う")
training_settings.guard_action = 0xC
training_settings.action_patterns = { reversal = { ["15"] = { version = 1, items = {
	{ name = "A", use = true, steps = { { action = "atk", lever = "none", button = "LP", wait = 0 } } },
	{ name = "B", use = true, steps = { { action = "atk", lever = "none", button = "HP", wait = 0, random_delay = 5 } } },
} } } }
start()
math.random = function(a, b) return (b == nil) and 2 or b end   -- B を選び、上限を引く
R.prepick("reversal")
eq("先に選んだのは B", R.picked_pattern() and R.picked_pattern().name, "B")
eq("B の 1 歩目の Random Delay を引く", R.draw_first_delay("reversal"), 5)
math.random = function(a, b) return (b == nil) and 1 or a end   -- ここで選び直すと A になる
R.arm("reversal")
eq("アームは選び直さない (B のまま)", R.picked_pattern() and R.picked_pattern().name, "B")
R.arm("reversal")
eq("次のアームは普段どおり選ぶ", R.picked_pattern() and R.picked_pattern().name, "A")
rand_real()
training_settings.guard_action = 0xB
training_settings.action_patterns = nil

-- ---------------------------------------------------------------------------
print("[7] 配線")
local gsrc = slurp("guardCancel.lua")
local d = gsrc:find("function GA.rsw_defer()", 1, true)
local d_end = d and gsrc:find("\nend", d, true)
local body = (d and d_end) and gsrc:sub(d, d_end) or ""
local pp = body:find('actionSequenceRunnerModule.prepick("reversal")', 1, true)
local dr = body:find('actionSequenceRunnerModule.draw_first_delay("reversal")', 1, true)
local zero = body:find("if _w <= 0 then return false end", 1, true)
eq("先にパターンを選ぶ", pp ~= nil, true)
eq("1 歩目の Random Delay を Random Start Wait に足す", dr ~= nil and pp ~= nil and pp < dr, true)
eq("合計 0 なら今どおりアームへ", zero ~= nil and dr ~= nil and dr < zero, true)
local esrc = slurp("actionSequenceEditor.lua")
eq("import が Random Delay を運ぶ", esrc:find("steps[j].random_delay = _rd", 1, true) ~= nil, true)
eq("エディタの上限は 60", esrc:find("local RANDOM_DELAY_MAX = 60", 1, true) ~= nil, true)
eq("runner の上限も 60", R.RANDOM_DELAY_MAX, 60)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
