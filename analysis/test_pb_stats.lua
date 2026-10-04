-- Show PB Stats の数え方と表示 (scripts/pbStats.lua)。
--
-- 1 回 = 地上で相手の攻撃に触れてから抜けるまで ($05 が 02 の間)。連続ガードは
-- 全体で 1 回。空中は数えない。**押した回だけ数える** (押していない回はガードでも
-- 食らいでも無視。本人、2026-09-28)。押して PB が出れば Pass、出なかったか食らった
-- ら Fail。平均は押してガードした回の、PB Count の行が最後に出した値。
--
-- Run from the repo root:
--   lua5.1 analysis/test_pb_stats.lua
local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local P1 = 0xFF8400
ram = {}
memory = { readbyte = function(a) return ram[a] or 0 end }
local T = {}
globals = { options = { display_pb_stats = true }, timers = T }
T.p1_pushblock_counter, T.p1_pushblock_ok, T.p1_pb_simul = 0, false, 0
T.p1_pb_marks, T.p1_pb_latemash, T.p1_pb_latemash_open = {}, 0, false

local M = dofile("scripts/pbStats.lua")
local function tick() M.on_tick() end
local function wait(n) for _ = 1, n do tick() end end
local function screen() return M.text() end

-- One ground touch as the PB Count line sees it. The contact tick still shows
-- the last touch's values; the window opens the tick after (a new marks table,
-- LateMash starts following). presses = { [tick] = buttons } - each also a
-- button edge in $126 on that tick - grant = the tick the push block is
-- granted, om = presses after the window, hit = a hit tick, hit_first = hit
-- from the contact (no window).
local function touch(o)
	o = o or {}
	ram[P1 + 0x38] = o.air and 1 or 0
	ram[P1 + 0x05] = 0x02
	ram[P1 + 0x54] = o.hit_first and 0x04 or 0xFF
	tick()                                       -- contact: stale values
	local window = not o.hit_first and not o.air
	if window then
		T.p1_pb_marks = {}
		T.p1_pushblock_counter, T.p1_pushblock_ok, T.p1_pb_simul = 0, false, 0
		T.p1_pb_latemash, T.p1_pb_latemash_open = 0, true
	end
	for k = 1, (o.len or 14) do
		local b = o.presses and o.presses[k]
		if b ~= nil then
			ram[P1 + 0x126] = 0x01
			if window then
				T.p1_pb_marks[k] = tostring(b)
				T.p1_pushblock_counter = T.p1_pushblock_counter + 1
				if b >= 2 then T.p1_pb_simul = T.p1_pb_simul + 1 end
			end
		elseif window and T.p1_pb_marks[k] == nil then
			T.p1_pb_marks[k] = "-"
		end
		if o.grant == k then T.p1_pushblock_ok = true end
		if o.hit == k then ram[P1 + 0x54] = 0x04 end
		tick()
		ram[P1 + 0x126] = 0
	end
	ram[P1 + 0x05] = 0x00                        -- out of it
	ram[P1 + 0x54] = 0x00
	tick()
	if o.om then T.p1_pb_latemash = o.om end
	if not o.keep_open then
		wait(2)
		T.p1_pb_latemash_open = false            -- LateMash has stopped
		tick()
	end
end

tick()                                           -- the first tick only learns

print("-- 何も無いとき (Count と Avg はラベル)")
local s = screen()
want("1 行目 (Guard Only は無い)", s[1], "Count Total 0")
want("2 行目", s[2], "      Pass 0  Fail 0")
want("3 行目 (率はまだ無い)", s[3], "      Success -")
want("4 行目 (平均はまだ無い)", s[4], "Avg   PB -  at -")
want("5 行目 (Multi と Late に短縮)", s[5], "      Multi -  Late -")

print("-- 押して PB が出た: Pass")
touch({ presses = { [3] = 1, [4] = 1, [6] = 2, [8] = 1 }, grant = 8 })
s = screen()
want("Total 1", s[1], "Count Total 1")
want("Pass 1", s[2], "      Pass 1  Fail 0")
want("成功率は Success、小数 2 桁", s[3], "      Success 100.00%")
want("平均: PB 4、at 3-8", s[4], "Avg   PB 4.00  at 3.00-8.00t")
want("Multi 1", s[5], "      Multi 1.00  Late 0.00")

print("-- 押したが出なかった: Fail。平均に入る")
touch({ presses = { [5] = 1, [7] = 1 } })
s = screen()
want("Total 2", s[1], "Count Total 2")
want("Pass 1 Fail 1", s[2], "      Pass 1  Fail 1")
want("50%", s[3], "      Success 50.00%")
want("PB (4+2)/2 = 3、at (3+5)/2-(8+7)/2", s[4], "Avg   PB 3.00  at 4.00-7.50t")
want("Multi (1+0)/2", s[5], "      Multi 0.50  Late 0.00")

print("-- ガードだけ (押さない): 数えない")
touch({})
touch({})
s = screen()
want("Total は増えない", s[1], "Count Total 2")
want("率も平均も変わらない", s[3] .. "/" .. s[4], "      Success 50.00%/Avg   PB 3.00  at 4.00-7.50t")

print("-- 食らったが押していない: 数えない")
touch({ hit_first = true })
s = screen()
want("Total は増えない", s[1], "Count Total 2")
want("Fail も増えない", s[2], "      Pass 1  Fail 1")

print("-- 押して食らった: Fail。平均には入らない (食らうと窓が開かず、行の値は前の回のまま)")
touch({ hit_first = true, presses = { [3] = 1 } })
s = screen()
want("Total 3", s[1], "Count Total 3")
want("Fail 2", s[2], "      Pass 1  Fail 2")
want("率 1/3", s[3], "      Success 33.33%")
want("平均は変わらない", s[4], "Avg   PB 3.00  at 4.00-7.50t")

print("-- ガードの途中で食らった (連続技の崩し): Fail")
touch({ presses = { [2] = 1 }, hit = 6 })
s = screen()
want("Fail 3", s[2], "      Pass 1  Fail 3")
want("25%", s[3], "      Success 25.00%")
want("食らった回は平均に入らない", s[4], "Avg   PB 3.00  at 4.00-7.50t")

print("-- 空中の接触は数えない (PB の窓が無い)")
touch({ air = true, presses = { [2] = 1 } })
s = screen()
want("Total は増えない", s[1], "Count Total 4")
ram[P1 + 0x38] = 0

print("-- 前の回の帯を、この回の at として読まない (当たったティックはまだ前の回の値)")
-- 前の回は押した回 (at 2)。この回は窓の中では押さず、窓の後だけ押す。
print("-- LateMash だけ押した (窓の後): 押したので Fail、at は無い")
touch({ om = 3 })
s = screen()
want("Total 5", s[1], "Count Total 5")
want("Fail 4", s[2], "      Pass 1  Fail 4")
want("20%", s[3], "      Success 20.00%")
want("PB (4+2+0)/3 = 2、at は 2 回分のまま", s[4], "Avg   PB 2.00  at 4.00-7.50t")
want("Late (0+0+3)/3 = 1", s[5], "      Multi 0.33  Late 1.00")

print("-- LateMash が数え終わるまで確定しない")
local before = screen()[1]
touch({ presses = { [4] = 1 }, keep_open = true })
want("まだ数えない", screen()[1], before)
T.p1_pb_latemash = 3
tick()
T.p1_pb_latemash_open = false
tick()
s = screen()
want("数え終わったら 1 回", s[1], "Count Total 6")
-- (0 + 0 + 3 + 3) / 4。ちょうど半分の丸めは処理系で違うので避ける。
want("Late は数え終わった値 3 で", s[5]:match("Late 1%.50$") ~= nil, true)

print("-- GC が出た回は数えない (本人、2026-09-28: GC成功したらPBから除外)")
do
	local t0 = screen()
	-- 押してガード中、受付時計 $158 が 0 になったティックに $06 が必殺技: GC 成立
	ram[P1 + 0x38], ram[P1 + 0x05], ram[P1 + 0x54] = 0, 0x02, 0xFF
	ram[P1 + 0x158] = 14
	tick()
	T.p1_pb_marks = {}; T.p1_pushblock_counter, T.p1_pushblock_ok = 0, false
	T.p1_pb_latemash, T.p1_pb_latemash_open = 0, true
	for k = 1, 4 do
		ram[P1 + 0x158] = 14 - k
		if k == 2 then ram[P1 + 0x126] = 0x01; T.p1_pb_marks[2] = "1"; T.p1_pushblock_counter = 1 end
		tick()
		ram[P1 + 0x126] = 0
	end
	ram[P1 + 0x158], ram[P1 + 0x05], ram[P1 + 0x06] = 0, 0x00, 0x0E   -- 必殺技が出てガードを抜ける
	tick()
	ram[P1 + 0x06] = 0x00
	T.p1_pb_latemash_open = false; tick()
	local s1 = screen()
	want("Total は増えない", s1[1], t0[1])
	want("Fail も増えない", s1[2], t0[2])
	want("平均も変わらない", s1[4], t0[4])

	-- 硬直が明けた後の必殺技 (リバーサル) は GC ではない: 時計は先に 0 になっている
	ram[P1 + 0x05], ram[P1 + 0x54] = 0x02, 0xFF
	ram[P1 + 0x158] = 14
	tick()
	T.p1_pb_marks = {}; T.p1_pushblock_counter, T.p1_pushblock_ok = 0, false
	T.p1_pb_latemash, T.p1_pb_latemash_open = 0, true
	for k = 1, 16 do
		ram[P1 + 0x158] = math.max(14 - k, 0)
		if k == 3 then ram[P1 + 0x126] = 0x01; T.p1_pb_marks[3] = "1"; T.p1_pushblock_counter = 1 end
		tick()
		ram[P1 + 0x126] = 0
	end
	ram[P1 + 0x05], ram[P1 + 0x06] = 0x00, 0x0E                       -- 明けたティックに必殺技
	tick()
	ram[P1 + 0x06] = 0x00
	T.p1_pb_latemash_open = false; tick()
	local s2 = screen()
	want("リバーサルは GC ではないので数える (Fail)", s2[1] ~= s1[1] and s2[2] ~= s1[2], true)
end

print("-- 連続ガードは全体で 1 回 ($05 が 02 のまま次の当たり)")
do
	ram[P1 + 0x38], ram[P1 + 0x05], ram[P1 + 0x54] = 0, 0x02, 0xFF
	tick()
	T.p1_pb_marks = {}; T.p1_pushblock_counter, T.p1_pushblock_ok = 0, false
	T.p1_pb_latemash, T.p1_pb_latemash_open = 0, true
	wait(5)
	-- 2 発目: $05 は 02 のまま、窓が開き直す (新しい帯)。数は持ち越す。
	T.p1_pb_marks = { [1] = "1", [2] = "1" }; T.p1_pushblock_counter = 2
	wait(5)
	T.p1_pushblock_ok = true
	wait(3)
	ram[P1 + 0x05] = 0x00; tick()
	T.p1_pb_latemash_open = false; tick()
	want("1 回だけ増える", screen()[1], "Count Total 8")
	want("Pass 2", screen()[2]:match("^      Pass 2 ") ~= nil, true)
end

print("-- 色: ラベルは灰、Pass と率は緑、Fail は赤、Multi と Late は 0 より大きいと赤")
do
	local L = M.lines()
	want("Count はラベル (AirGap の見出しと同じ灰)", L[1][1][1] .. L[1][1][2], "Count #AAAAAA")
	want("Avg もラベル", L[4][1][1] .. L[4][1][2], "Avg   #AAAAAA")
	want("Pass は緑", L[2][2][2], "#00FF00")
	want("Fail は赤", L[2][3][2], "#FF0000")
	want("率は緑", L[3][2][2], "#00FF00")
	want("Multi > 0 は赤", L[5][2][2], "#FF0000")
	want("Late > 0 は赤", L[5][3][2], "#FF0000")
	M.clear()
	L = M.lines()
	want("消したら 0", M.text()[1], "Count Total 0")
	want("平均が無いときは灰", L[5][2][2], "#888888")
end

print("-- 99999 で止まる")
do
	M.clear()
	tick()
	for _ = 1, 99999 do touch({ presses = { [1] = 1 } }) end
	want("99999", screen()[1], "Count Total 99999")
	touch({ presses = { [1] = 1 } })
	want("それ以上増えない", screen()[1], "Count Total 99999")
	want("Pass と Fail も止まる", screen()[2], "      Pass 0  Fail 99999")
end

print("-- 幅: 99999 でも GC Command Trace にかからない")
do
	local hud = io.open("scripts/hud.lua"):read("*a")
	local x = tonumber(hud:match("local PB_STATS_X, PB_STATS_ROW = (%d+)"))
	-- 上の 3 つ (ボタン一覧・PB Stats・GC Command Trace) は PB Count の行のすぐ下 38。
	-- GC Frequency (Guard Action Frequency Check) を出したときだけ、その行の下 50
	-- (本人、2026-09-28: フリクエンシーは出さなくなったので上に)。
	local on, off = hud:match("display_gc_freq_counter == true%) and (%d+) or (%d+)")
	local y = tonumber(off)
	local trace_x = tonumber(hud:match("local _x, _y = (%d+), blocks_top%(%)\n\tlocal _t0 = _t.rows%[1%]%.t"))
	-- もう少し左に (本人、2026-09-28)。ボタン一覧の TECH HIT (ボタン 2 つ) にはかからない所まで。
	want("PB Stats は x 74", x, 74)
	want("PB Stats は普段 y 38", y, 38)
	want("Frequency の行 (y 36) を出したときは y 50", tonumber(on), 50)
	want("PB Stats も GC Command Trace もその高さから", select(2, hud:gsub("blocks_top%(%)", "")) >= 3, true)
	-- 背景は AirGap と同じ暗い箱 (本人、2026-09-28)
	local body = hud:match("local function draw_pb_stats%(%)(.-)\nend")
	local ag = hud:match("local function draw_air_guard_gap%(%)(.-)\nend")
	local box = body and body:match('gui%.box%b()')
	want("PB Stats に背景の箱がある", box ~= nil, true)
	want("色は AirGap と同じ", box and box:match('"#%x+", "#%x+"'), ag and ag:match('gui%.box%b()'):match('"#%x+", "#%x+"'))
	want("GC Command Trace は x 210 (背景は 208 から)", trace_x, 210)
	local widest = {
		"Count Total 99999",
		"      Pass 99999  Fail 99999",
		"      Success 100.00%",
		"Avg   PB 14.00  at 14.00-14.00t",
		"      Multi 14.00  Late 84.00",
	}
	for _, l in ipairs(widest) do
		want("背景の右端が GC Command Trace の背景 (208) より左: " .. l, x + #l * 4.2 + 2 <= trace_x - 2, true)
	end
	-- tech-hit-inputs.lua: TECH HIT は (ボタンの数 + 1) * 10 + 7 から 8 字
	want("ボタン 2 つの TECH HIT は背景 (x - 2) より左で終わる", (2 + 1) * 10 + 7 + 8 * 4.2 <= x - 2, true)
	local tech = io.open("scripts/tech-hit-inputs.lua"):read("*a")
	want("ボタン一覧は PB Stats の高さを受け取る", hud:find("tech_hit_inputs(PB_STATS_Y)", 1, true) ~= nil, true)
	want("ボタン一覧の 1 行目はその高さ", tech:find("local y = _top + 10 * (n - 1)", 1, true) ~= nil, true)
	-- ボタン一覧も同じ暗い箱 (本人、2026-09-28)。右の余白は 1px で PB Stats の箱 (72) の手前まで。
	local tbox = tech:match('gui%.box%b()')
	want("ボタン一覧にも背景の箱", tbox ~= nil, true)
	-- TECH HIT は Pass / Success と同じ緑 (本人、2026-09-28)
	local pass_c = M.lines()[2][2][2]
	want("TECH HIT は Pass と同じ色", tech:match("'TECH HIT', \"(#%x+)\""), pass_c)
	want("色は PB Stats と同じ", tbox and tbox:match('"#%x+", "#%x+"'), box and box:match('"#%x+", "#%x+"'))
	want("ボタン 2 つ + TECH HIT の箱の右端は PB Stats の箱より左", (2 + 1) * 10 + 7 + 8 * 4.2 + 1 < x - 2, true)
end

if fails == 0 then print("all ok") else print(fails .. " 件 NG") os.exit(1) end
