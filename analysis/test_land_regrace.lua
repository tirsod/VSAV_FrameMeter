-- 凍った配送だけ、最終押しを着地まで待つ。猶予を超えたら頭から入れ直す。
--
-- 着地歩は lead ティック早く commit され、最終エントリが「行動可能になる最初の
-- ティック」に乗る予定で組まれている。それは予測であり、commit の後にヒット
-- ストップが始まると物理だけ止まって歩進はティックを数え続ける。着地は後ろへ
-- ずれ、最終押しは空中で出る。free+0 を外した押しは「遅い」ではなく「出ない」。
--
-- 2026-09-19 実測 (各 10 回):
--   ダッシュ小P  FD:0   動く
--   ダッシュ大P  FD:48  AF 24/24 が床の手前 2 ティックで空振り
-- 遅い技は降下の遅い側で当たるので、凍結がこの配送の中に入る。
--
-- 凍った配送だけを触る。以前「空中なら待つ」だけにしたら LW:240 (24 周) まで
-- 膨れ、動いていた小P側まで遅らせてダッシュキャンセルを壊して差し戻した。
-- 小P の最終押しも半分は空中だが、1 ティックのずれはゲームが受け付けている。
--
-- 待ってもエッジは失わないが、窓は失う。ダッシュの真ん中のニュートラルに
-- 許されるのは 10 ティック (資料、VSAV_MEMORY_NOTES.md)。ヒットストップは
-- 11 ティックなので、猶予を超えたら死んだ窓に押し込まず入れ直す。
--
-- 2026-10-03: ダッシュは「猶予」ではなくゲームの受付そのものを見る。ROM 0x02A4C8 の
-- 前ダッシュ受付は 前 → (段 2) → N → (段 4) → 前 で成立し、各段 12 ティックで消える。
-- 受付はヒットストップ中も進み、成立はその 1 ティックだけ有効で、ダッシュに移るのは
-- 凍結明けの地上。空中や凍結中の入れ直しは、その最初の前が途中のダッシュを空振りで
-- 成立させて使い切る (モリガン 17/17、サスカッチ大P)。このテストは同じ受付の模型を
-- 持ち、「空振りの成立が無く、地上で 1 回成立する」ことをコードで判定する。
--
-- scripts/ から走らせる。
--   cd scripts && lua5.1 ../analysis/test_land_regrace.lua
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
seq_dash_cancel_reverse = { ["forward dash cancel"] = "back", ["back dash cancel"] = "forward" }

local csrc = io.open("controller.lua"):read("*a")
local cs = csrc:find("function make_input_sequence", 1, true)
local ce = csrc:find("\nend", csrc:find("return _sequence", cs, true), true)
assert(cs and ce, "make_input_sequence が controller.lua に見つからない")
assert(loadstring(csrc:sub(cs, ce + 4)))()

function queue_input_sequence(_d, _seq)
	_d.pending_input_sequence = { sequence = _seq, current_frame = 1 }
end

local R = dofile("actionSequenceRunner.lua")

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local BITS = { forward = 0x02, back = 0x01, down = 0x04, up = 0x08 }
local function to_bits(entry)
	local lev, btn = 0, 0
	for _, k in ipairs(entry or {}) do
		if BITS[k] then lev = lev + BITS[k] else btn = 1 end
	end
	return lev, btn
end

local P2 = 0xFF8800
local REC = R.DASH_REC_FORWARD             -- 段 (0xFF89F0) / タイマー (+4)

-- ゲームの前ダッシュ受付 (ROM 0x02A4C8) の模型。ティックの終わりに、そのティックの
-- レバーで 1 回進め、段とタイマーを実機と同じ番地に書く。歩進は次のティックで
-- それを読む - 実機でも歩進のフックは受付より先に走る。
local rec_prev_lev = 0
local recog = {}                           -- 成立したティック: { air, frozen }
local function recognizer(lev)
	local e = 0                            -- 方向ビットの立ち上がり
	for _, bit in ipairs({ 1, 2, 4, 8 }) do
		if (lev % (bit * 2)) >= bit and (rec_prev_lev % (bit * 2)) < bit then e = e + bit end
	end
	rec_prev_lev = lev
	local st, tm = ram[REC] or 0, ram[REC + 4] or 0
	local fwd_edge = (e % 4) >= 2
	if st == 0 then
		if fwd_edge then st, tm = 2, R.DASH_STEP_TICKS end
	elseif st == 2 then
		tm = tm - 1
		if tm == 0 then st = 0
		elseif lev == 0 then st, tm = 4, R.DASH_STEP_TICKS
		elseif (lev % 4) >= 2 then -- 前を押したまま
		else st = 0 end
	elseif st == 4 then
		tm = tm - 1
		if tm == 0 then st = 0
		elseif e ~= 0 then
			if fwd_edge then
				recog[#recog + 1] = { air = ram[P2 + 0x38] ~= 0, frozen = ram[P2 + 0x5C] ~= 0 }
			end
			st = 0
		end
	end
	ram[REC], ram[REC + 4] = st, tm
end
-- 空振りの成立 (空中か凍結中) と、地上で取られた成立の数。
local function spent()
	local n = 0
	for _, r in ipairs(recog) do if r.air or r.frozen then n = n + 1 end end
	return n
end
local function taken()
	local n = 0
	for _, r in ipairs(recog) do if not r.air and not r.frozen then n = n + 1 end end
	return n
end

-- 歩進の代役。guardCancel の seq_tick ブロックと同じ規則。
local defender = {}
local log = {}
local clock = 0
local refeed_last = 0
local function restart(s)
	s.current_frame = 1
	s.tick_held = 0
	s.land_hold = 0
	restarts = (restarts or 0) + 1
end
local function tick()
	local wrote = nil
	clock = clock + 1
	ram[0xFF8081] = clock % 256
	local frozen = ram[P2 + 0x5C] ~= 0
	for _pass = 1, 2 do
		R.service(defender)
		local s = defender.pending_input_sequence
		if s == nil or s.sequence == nil then break end
		local i = s.current_frame or 1
		local stop = false
		if s.seq_land and s.saw_freeze and i == #s.sequence
		   and (s.tick_held or 0) == 0 then
			local rec = R.dash_recognizer(s.sequence)
			local air = ram[P2 + 0x38] ~= 0 and seq_ticks_to_landing() ~= nil
			if rec ~= nil then
				if air or frozen then
					stop = true
				else
					local st, tm = ram[rec] or 0, ram[rec + 4] or 0
					if st == 0 then restart(s) ; i = 1
					elseif not (st == 4 and tm >= 2) then stop = true end
				end
			elseif air then
				s.land_hold = (s.land_hold or 0) + 1
				if s.land_hold < (R.DASH_GRACE_TICKS or 10) - 1 then stop = true
				else restart(s) ; i = 1 end
			end
		end
		if not stop and s.restart_pending then
			if frozen then
				stop = true
			else
				s.restart_pending = nil
				s.tick_held = 0
				s.entry_ticks = 0
				local rec = R.dash_recognizer(s.sequence)
				if rec ~= nil and ram[rec] == 4 and (ram[rec + 4] or 0) >= 2 then
					s.current_frame = #s.sequence
					refeed_last = refeed_last + 1
					stop = true
				else
					s.current_frame = 1
					i = 1
				end
			end
		end
		if stop then
			wrote = { src = ((s.current_frame or 1) == #s.sequence) and "hold" or "wait",
			          lev = 0, btn = 0 }
			break
		end
		if i <= #s.sequence then
			local lev, btn = to_bits(s.sequence[i])
			s.entry_ticks = (s.entry_ticks or 0) + 1
			if (lev ~= 0 or btn ~= 0) and frozen
			   and s.entry_ticks > (R.DASH_GRACE_TICKS or 10) then
				s.restart_pending = true
				wrote = { src = "wait", lev = 0, btn = 0 }
				break
			end
			wrote = { src = "step", lev = lev, btn = btn, idx = i,
			          frozen = frozen, air = (ram[P2 + 0x38] ~= 0) }
			local hold = (btn == 0 and lev ~= 0) and 2 or 1
			-- 凍結中の押しはゲームが捨てるので、配送したと数えない。
			if not ((lev ~= 0 or btn ~= 0) and frozen) then
				s.tick_held = (s.tick_held or 0) + 1
			end
			if (s.tick_held or 0) >= hold then
				s.current_frame = i + 1
				s.tick_held = 0
				s.entry_ticks = 0
			end
			if frozen then s.saw_freeze = true end
			break
		end
		defender.pending_input_sequence = nil
	end
	log[#log + 1] = wrote or { src = "none", lev = 0, btn = 0 }
	recognizer(log[#log].lev)
	return log[#log]
end
local function run(n) for _ = 1, n do tick() end end

local function install()
	ram[0xFF8B82] = 0x0A                       -- サスカッチ
	training_settings.action_sequences = { reversal = { ["10"] = { version = 1, steps = {
		{ action = "atk", lever = "none", button = "LP", wait = 0 },
		{ action = "dash.f", timing = "landing", wait = -1 },
	} } } }
end
local function start()
	log = {} ; restarts = 0 ; recog = {} ; refeed_last = 0
	ram[REC], ram[REC + 4], rec_prev_lev = 0, 0, 0
	defender = {}
	R.cancel()
	R.arm("reversal")
end
local function airborne()
	ram[P2 + 0x38] = 1
	ram[P2 + 0x14] = 6 * 65536
	ram[P2 + 0x44] = -65536
	ram[P2 + 0x4C] = -65536
	ram[P2 + 0x3A] = 0
	ram[P2 + 0x5C] = 0
end
local function finals()
	local n = 0
	for _, e in ipairs(log) do if e.src == "step" and e.idx == 4 then n = n + 1 end end
	return n
end
local function holds()
	local n = 0
	for _, e in ipairs(log) do if e.src == "hold" then n = n + 1 end end
	return n
end
-- 凍結を n ティック、1 ティックごとに減らしながら流す。
local function freeze(n)
	for k = n, 1, -1 do
		ram[P2 + 0x5C] = k
		tick()
	end
	ram[P2 + 0x5C] = 0
end

seq_ticks_to_landing = function() return 4 end

print("[1] 凍らなかった配送は、これまでどおり出る")
install() ; start() ; airborne()
run(10)
want("最終の forward が空中でもそのまま出る", finals() > 0, true)
want("待ちに入らない", holds(), 0)

print("[2] 凍った配送は、着地まで最終押しを待つ")
install() ; start() ; airborne()
-- 凍結は commit の後に始まる。ゲートは凍結中に commit しないので、
-- 最初から凍らせては配送そのものが始まらず、試したことにならない。
run(2)                                     -- commit して助走が始まる
freeze(2)                                  -- ここで凍る
run(4)                                     -- 明けたが、まだ空中
want("最終の forward を空中で打たない", finals(), 0)
want("待っている", holds() > 0, true)

print("[3] 本当に着地したら、その場で出る")
ram[P2 + 0x38] = 0
run(2)
want("着地して最終の forward が出た", finals() > 0, true)
want("ダッシュは地上で 1 回成立した", taken(), 1)
want("空振りの成立は無い", spent(), 0)

print("[4] 空中では、どれだけ待っても入れ直さず、押さない")
-- 以前は 9 ティックで空中のまま入れ直していた。その最初の前が、途中まで入った
-- ダッシュを空中で成立させて使い切り、着地後には新しい 1 段目しか残らなかった。
install() ; start() ; airborne()
run(2)
freeze(2)
run(30)                                    -- 着地しないまま待たせ続ける
want("空中で入れ直さない", (restarts or 0), 0)
want("空中で最後の前を押さない", finals(), 0)
want("空振りの成立は無い", spent(), 0)

-- 実機の並び: 前 (2)、N、ここでヒットストップ、明けて空中、着地。
local function frozen_at_n(n, air_after)
	install() ; start() ; airborne()
	run(3)                                 -- {} 前 前 (助走が始まる)
	freeze(n)                              -- N のティックで凍る
	run(air_after)                         -- 明けて空中
	ram[P2 + 0x38] = 0                     -- 着地
end

print("[4b] 着地で途中のダッシュがまだ生きていれば、最後の前だけで成立させる")
frozen_at_n(6, 1)                          -- N から 8 ティックで着地
tick()
want("入れ直さない", (restarts or 0), 0)
want("着地のティックに最後の前を押す", finals() > 0, true)
want("ダッシュは地上で 1 回成立した", taken(), 1)
want("空振りの成立は無い", spent(), 0)

print("[4c] 実機の形 (モリガン、サスカッチ大K) - 11 ティック凍り、着地で受付が切れる")
frozen_at_n(11, 1)                         -- 着地のティックで受付が消える
tick()
want("消えるティックでは押さない", finals(), 0)
want("消えるティックでは入れ直さない", (restarts or 0), 0)
tick()
want("消えた次のティックで頭から入れ直す", (restarts or 0), 1)
run(8)
want("入れ直した動作が地上で成立した", taken(), 1)
want("空振りの成立は無い", spent(), 0)
want("入れ直しは 1 回だけ", (restarts or 0), 1)

print("[4d] 着地していても、ヒットストップ中は押さない")
install() ; start() ; airborne()
run(3)
ram[P2 + 0x5C] = 11
tick()                                     -- N で凍る
ram[P2 + 0x38] = 0                         -- 凍ったまま着地 (規則として)
run(3)
want("凍っている間は最後の前を押さない", finals(), 0)
want("凍っている間は入れ直さない", (restarts or 0), 0)

print("[4e] 実機の形 (サスカッチ大P) - 助走の 1 回目の前で凍り、押しすぎて入れ直しへ")
-- 遅い大Pは助走の最初のティックで当たる。前を押したまま凍り、10 ティックを超えて
-- 入れ直しに回る。その手を離した瞬間が N になって受付は最後の段へ進む。以前は
-- 明けた空中で頭から入れ直し、その最初の前が空振りで成立して消えていた。
install() ; start() ; airborne()
run(2)                                     -- {} 前 (1 ティック目は凍る前)
freeze(11)
run(2)                                     -- 明けて 2 ティック空中 (実機 lg104-105)
want("最後の前へ進めた (頭からではない)", refeed_last, 1)
want("空中では押さない", finals(), 0)
ram[P2 + 0x38] = 0                         -- 着地
tick()
want("着地のティックで成立させる", taken(), 1)
want("空振りの成立は無い", spent(), 0)
want("頭から入れ直していない", (restarts or 0), 0)

print("[5] 着地が来ないなら停滞しない (前に戻しバグの再発防止)")
install() ; start() ; airborne()
run(2)
freeze(2)
seq_ticks_to_landing = function() return nil end
run(6)
want("最終の forward は出る", finals() > 0, true)
seq_ticks_to_landing = function() return 4 end

print("[6] 出したダッシュ自身のホップで、入れ直しを始めない")
-- 最終の forward は 2 ティック出る。1 ティック目でダッシュが成立し、サスカッチは
-- 足が浮くので $38 が 0 -> 1 になる。2 ティック目に「空中かつ降下中」と見て入れ
-- 直していたため、ダッシュ→着地→ダッシュ→着地が延々続いた (実機 2026-09-19)。
install() ; start() ; airborne()
run(2)
freeze(2)
run(6)                                     -- 空中で待たせる
ram[P2 + 0x38] = 0                         -- 着地。最終エントリの 1 ティック目が出る
tick()
ram[P2 + 0x38] = 1                         -- ダッシュ成立で足が浮く
local r0 = restarts or 0
local f0 = finals()
run(4)
want("浮いても入れ直さない", (restarts or 0), r0)
want("最終エントリを出し切る", finals() > f0, true)

print("[7] 猶予はダッシュの資料値で、出所が書いてある")
want("DASH_GRACE_TICKS = 10", R.DASH_GRACE_TICKS, 10)
want("DASH_STEP_TICKS = 12 (ROM 0x02A552 の 0x0C)", R.DASH_STEP_TICKS, 12)
want("受付の番地 (P2 $1F0 / $1F8)", R.DASH_REC_FORWARD == 0xFF89F0 and R.DASH_REC_BACK == 0xFF89F8, true)
do
	local gsrc = io.open("guardCancel.lua"):read("*a")
	local guard = gsrc:find("if _s0.seq_land and _s0.saw_freeze and _i == #_s0.sequence", 1, true)
	local rs = guard and gsrc:find("_s0.current_frame = 1", guard, true)
	local body = (guard and rs) and gsrc:sub(guard, rs) or ""
	-- ダッシュはゲームの受付を読んで決めること、空中・凍結中は押さないこと (2026-10-03)。
	want("空中と凍結中は待つ", body:find("if _air or memory.readbyte(0xFF885C) ~= 0 then", 1, true) ~= nil, true)
	want("入れ直しはゲームの受付の段を読んで決める", body:find("local _st = memory.readbyte(_rec)", 1, true) ~= nil, true)
	local rp = gsrc:find("if _s0.restart_pending then", 1, true)
	local rp_end = rp and gsrc:find("_s0.current_frame = 1", rp, true) or nil
	local rp_body = (rp and rp_end) and gsrc:sub(rp, rp_end) or ""
	want("押しすぎの入れ直しも、生きている受付なら最後の前へ",
		rp_body:find("_s0.current_frame = #_s0.sequence", 1, true) ~= nil, true)
end
do
	local rsrc = io.open("actionSequenceRunner.lua"):read("*a")
	want("ノーマル 1F = 1 tick の根拠が書いてある",
		rsrc:find("one frame is one tick at Normal", 1, true) ~= nil, true)
	want("ターボと取り違えた経緯が残してある",
		rsrc:find("NOT the emulator's turbo", 1, true) ~= nil, true)

	local gsrc = io.open("guardCancel.lua"):read("*a")
	-- 凍った配送だけを触ること。ここが外れると LW:240 の再発。
	local guard = gsrc:find("if _s0.seq_land and _s0.saw_freeze and _i == #_s0.sequence", 1, true)
	want("凍った配送だけに限っている", guard ~= nil, true)
	-- ticks_to_landing() > 0 を直接聞く形は 2026-09-20 に試して戻した。
	-- 着地ぴったりを狙った押しも「まだ落下中」なので、全部待たせてしまい
	-- サスカッチの 2 回目が再び遅れた (LW:240)。
	want("落下中というだけで待たせない",
		guard ~= nil and gsrc:find("(ticks_to_landing() or 0) > 0", guard, true) == nil, true)
	want("猶予を超えたら先頭へ戻す",
		guard ~= nil and gsrc:find("_s0.current_frame = 1", guard, true) ~= nil, true)
	local write = (guard ~= nil)
		and gsrc:find("if _i <= #_s0.sequence then", guard, true) or nil
	want("押しの書き込みより手前にある", (guard ~= nil and write ~= nil and guard < write), true)
	-- 入れ直しで印を消さないこと。消すと 2 周目が盲目になり、空中で打つ。
	-- このテストが実装から実際に見つけた穴なので、固定しておく。
	local body = (guard ~= nil and write ~= nil) and gsrc:sub(guard, write) or ""
	want("入れ直しても印を消さない",
		body:find("saw_freeze = false", 1, true) == nil, true)
	-- 出し始めた後は触らないこと。ここが外れると自分の出したダッシュに反応する。
	want("最終エントリが始まる瞬間だけを見る",
		gsrc:find("and (_s0.tick_held or 0) == 0", 1, true) ~= nil, true)
	-- 接地で解除すること。「動けるか」($05/$06) に変えたらサスカッチの 2 回目の
	-- ダッシュが遅れたので戻した (2026-09-19)。NF の計測も $06 を読むので、
	-- ファイル全体ではなくガードの区間だけを見る。
	want("接地で解除する (動けるか、ではない)",
		body:find("0xFF8806", 1, true) == nil, true)
end

print(fails == 0 and "REP_OK" or (fails .. " REP_NG"))
if fails ~= 0 then os.exit(1) end
