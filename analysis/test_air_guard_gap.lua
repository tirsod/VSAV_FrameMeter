-- AIR GUARD GAPS: DOES EACH ROW SAY WHAT HAPPENED?
--
-- Every scene below is one taken from the air guard logs of 2026-09-26
-- (Demitri blocking Aulbath's air chain, analysis/air_guard_report.py), rebuilt
-- tick by tick: the guard, 12 ticks frozen, the tick 0x025286 puts the
-- defender back in the jump state, then the gap from tick 1. The rows are
-- compared as the text the screen gets.
--
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_air_guard_gap.lua
local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "\n     got  [" .. tostring(got) .. "]\n     want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local P1, P2 = 0xFF8400, 0xFF8800
local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return (ram[a] or 0) * 256 + (ram[a + 1] or 0) end,
	-- $1C (the animation cel) is written whole below; only it is read this way.
	readdword = function(a) return ram[a] or 0 end,
}
globals = { options = { display_air_guard_gap = true } }
local M = dofile("scripts/airGuardGap.lua")

local function set(base, t) for k, v in pairs(t) do ram[base + k] = v end end
local function bump(base) ram[base + 0x1B9] = (ram[base + 0x1B9] or 0) + 1 end
local function tick()
	M.on_tick()
	ram[P1 + 0x126] = 0      -- a press is an edge: one tick
end
local function wait(n) for _ = 1, n do tick() end end
-- The attack box: $1C points at a cel, +0x0A in it is the box id (Tick Data's
-- read). Each side gets a fake cel, and box(side, 1) puts a box out.
local CEL = { [P1] = 0x100000, [P2] = 0x100100 }
local function box(base, id) ram[base + 0x1C] = CEL[base]; ram[CEL[base] + 0x0A] = id end

local AIR = { [0x05] = 0x00, [0x06] = 0x06, [0x07] = 0x02, [0x38] = 1 }
local NORMAL = { LP = { 0, 0 }, MP = { 2, 0 }, HP = { 4, 0 }, LK = { 0, 2 }, MK = { 2, 2 }, HK = { 4, 2 } }
-- The attacker is in the middle of an air normal.
local function p2_move(n)
	set(P2, { [0x06] = 0x06, [0x105] = 1, [0x102] = NORMAL[n][1], [0x101] = NORMAL[n][2] })
end
-- The attacker starts its next move: $1B8 moves on that tick (26 of 26).
local function p2_start(n) p2_move(n); bump(P2) end
local function p1_attack(n)
	set(P1, { [0x07] = 0x06, [0x105] = 1, [0x102] = NORMAL[n][1], [0x101] = NORMAL[n][2] })
	ram[P1 + 0x126] = 0x01
	bump(P1)
end

-- ONE AIR GUARD, 14 TICKS: the contact, 12 frozen, then 0x025286's tick.
-- `early` are ticks (0 = the contact) with a press; `at_t0` runs on the last.
local function guard(n, early, at_t0, at)
	p2_move(n)
	set(P1, { [0x05] = 0x02, [0x06] = 0x00, [0x07] = 0x00, [0x54] = 0xFF, [0x38] = 1 })
	local e = {}
	for _, t in ipairs(early or {}) do e[t] = true end
	for t = 0, 12 do
		if e[t] then ram[P1 + 0x126] = 0x01 end
		if at and at[t] then at[t]() end
		tick()
		if t == 0 then box(P2, 0) end       -- the box that hit goes away
	end
	set(P1, AIR)
	set(P1, { [0x105] = 0 })
	if e[13] then ram[P1 + 0x126] = 0x01 end
	if at_t0 then at_t0() end
	tick()
end
local function hit_p1() set(P1, { [0x05] = 0x02, [0x06] = 0x00, [0x54] = 0x04 }) end
-- A hit writes 02 02 00 00 over the one struck (0x0296.., the hit code), so on
-- that tick its move can no longer be read. That is what hid the trade's name.
local function hit_p2() set(P2, { [0x05] = 0x02, [0x06] = 0x00, [0x54] = 0x04 }) end
-- 飛ぶ。地上でジャンプの状態が 3 ティック (移行、ジャンプの 1〜3)、4 で空中へ
-- (実機 244 回すべて)。Jump 列はこの 1 から数える。
local function new_jump()
	set(P1, { [0x05] = 0x00, [0x06] = 0x06, [0x07] = 0x00, [0x38] = 0, [0x105] = 0 })
	tick(); tick(); tick()                   -- ジャンプの 1, 2, 3
	set(P1, AIR); set(P1, { [0x105] = 0 })    -- 4 で空中へ
	set(P2, AIR); set(P2, { [0x05] = 0x00, [0x54] = 0x00 })
	-- 場面の区切り。相手の $1B8 を 1 つ進め、前の場面の技の発生を持ち越さない。
	-- 実機では相手の攻撃は必ず $1B8 を動かす。ここでは名前だけ差し替える場面が
	-- あるので (guard の p2_move)、区切りで明示的に新しい技にしておく。
	bump(P2)
	tick()
end

local function screen() return M.text() end
-- The colours of the P / K cells of a line, in order.
local function letter_colours(line)
	local cs = {}
	for _, c in ipairs(line) do if c[1] == "P" or c[1] == "K" then cs[#cs + 1] = c[2] end end
	return cs
end
-- The colours of the pressed ticks after "In Blockstun ... at", in order.
local function stun_colours(line)
	local cs, on = {}, false
	for _, c in ipairs(line) do
		if on and c[1]:find("%d") then cs[#cs + 1] = c[2] end
		if c[1]:find("^In Blockstun") then on = true end
	end
	return cs
end
-- EVERY TICK NUMBER CARRIES ITS t (user, 2026-09-27: 統一感). A list shares
-- one, after its last: 9,13t and 2..12t. The digits that are not ticks are
-- P1 / P2. Returns the bare ones found, "" when none.
local function bare(t)
	local out = {}
	for _, l in ipairs(t) do
		for a, b in l:gmatch("()%d+()") do
			if not l:sub(b, b):match("[t,.]") and l:sub(a - 1, a - 1) ~= "P" then out[#out + 1] = l:sub(a, b - 1) end
		end
	end
	return table.concat(out, ",")
end
local function show(t) for _, l in ipairs(t) do print("     |" .. l .. "|") end end

print("-- 5 発のチェーンをガードだけ (airg_s27)")
new_jump()
guard("LP"); wait(3)
guard("LK"); wait(3)
guard("MP"); wait(9)
guard("MK"); wait(5)
guard("HP")
wait(6)
set(P2, { [0x38] = 0 }); tick()                             -- 相手は @7 で着地
wait(10)
set(P1, { [0x38] = 0 }); tick()                             -- 自分は @18
local s = screen()
show(s)
-- Jump 列: 地上の移行 (3 ティック) と、飛び上がったティックを 1 としたガード。
-- ここでは 1〜3 が移行、4 で空中 (空中の 1)、5 で最初のガード (空中の 2)。
-- 着地はジャンプを始めたティックから数えた、ジャンプ全体の何ティック目か。
want("見出し: 列の名前が列の上に来る", s[1], "AirGap                           Gap  Press>Hit")
want("1 行目: LP から LK まで 3t", s[2], "J.LP > J.LK  ---|                 3t")
want("2 行目: ガードは先頭だけ", s[3], "J.LK > J.MP  ---|                 3t")
want("3 行目: MP から MK まで 9t", s[4], "J.MP > J.MK  ---------|           9t")
want("4 行目: MK から HP まで 5t", s[5], "J.MK > J.HP  -----|               5t")
want("5 行目: 相手は 7 で着地、自分は 18 で着地", s[6], "J.HP > Land  ------L----------L  17t")
-- Jump は表の下の 1 行 (本人、2026-09-27: 列だと右端の入力表示に重なった)。
-- 移行 3、飛んで 2 でガード。最後はどちらが何 t 有利か (本人、2026-09-27:
-- 全体 tick 数よりアドバンテージで): 相手が 101、自分が 112 で着地 → 相手が 11t 有利。
want("Jump の行", s[7], "Jump  PreJump(3t) > Guard 2t")
-- 着地時点の有利は別の行 (本人、2026-09-27: Landing Advantage)。
want("Landing Advantage の行", s[8], "Landing Advantage P2 +11t")
want("押していなければ Blockstun は出ない", table.concat(s, "/"):find("Blockstun", 1, true), nil)
do
	-- 右端のダミーの入力表示 (画面の x 350 あたりから) に届かない幅。
	-- 字送り 4.2、左端 21 から: (350 - 21) / 4.2 = 78 字。余裕を見て 76。
	local widest = 0
	for _, l in ipairs(s) do if #l > widest then widest = #l end end
	want("どの行も 76 字以内", widest <= 76, true)
end
do
	-- 帯の L と Advantage の側が同じ色 (本人、2026-09-27)。
	local row, ls = M.lines()[6], {}
	for _, c in ipairs(row) do if c[1] == "L" then ls[#ls + 1] = c[2] end end
	local adv
	for _, c in ipairs(M.lines()[8]) do if c[1]:find("^P2 ") then adv = c[2] end end
	want("帯の L は 2 つ", #ls, 2)
	want("先の L は P2 の色", ls[1], "#FF9900")
	want("帯の終わりの L は P1 の色", ls[2], "#4D79FF")
	want("有利な P2 は P2 の L と同じ色", adv, ls[1])
end

print("-- 早押し 2 回の後、4 で弱 P、4t で当てて勝つ (airg_s28)")
new_jump()
guard("MP", { 1, 6 })
wait(3)
p1_attack("LP"); p2_start("MK"); tick()     -- @4
wait(3)
box(P1, 1); hit_p2(); tick()                        -- @8 判定が出て、そのまま当たる
box(P1, 0)
s = screen()
show(s)
want("新しいチェーンで描き直す (見出し・行・Jump)", #s, 3)
-- 発生は Tick Data の数え方: 押した 4 を 1 と数えて、判定が出た 8 まで = 5。
-- 相手の MK は 4 で出始めたが、判定が出る前に潰したので発生は出ない。
want("帯は * で止まり、隙間は ?。押した 4、当たった 8、発生 5", s[2], "J.MP > J.MK  ---P---*    ?  LP 4t>8t (5t) WIN")
set(P2, { [0x05] = 0x00 })
wait(22); set(P1, { [0x38] = 0 }); tick()          -- @31 自分が着地
wait(29); set(P2, { [0x38] = 0 }); tick()          -- @61 相手が落ちる
s = screen()
want("勝った行", s[2], "J.MP > J.MK  ---P---*    ?  LP 4t>8t (5t) WIN")
-- 最初の振動は上に行が無いので、自分のガードがある表の下の行に。ガードの直後に
-- 押したボタン、当たりを 1 と数えて 2 と 7 で押した (本人、2026-09-27: 一段前の行、
-- 9,10,11t、メーターの後ろで押すボタン)。
-- 当てた後も有利を出す (本人、2026-09-27: 当てた、殴られたも出して)。この場面の
-- 相手は当たった次の @9 に $05 が 0 に戻り、自分は @31 で着地: 相手が 22t 有利。
want("Jump の行", s[3], "Jump  PreJump(3t) > Guard 2t PP  In Blockstun 14t at 2,7t")
want("Landing Advantage の行", s[4], "Landing Advantage P2 +22t")

-- 色の役割 (本人、2026-09-27): 灰は見出しの行だけ、暗い灰は帯の目盛り、
-- それ以外で何かを言っているものは白か、その意味の色 (結果の緑・黄・赤)。
-- 着地は P1 青 / P2 オレンジで、帯の L と Jump の列が同じ色。P2 のピンクは水色と
-- 見分けられず (2 型で色差 0.7)、P1 の水色は弱ボタンの水色と重なった (色差 0.4)。
local function colour_of(line, text)
	for _, c in ipairs(line) do if c[1] == text then return c[2] end end
end
local GREY, WHITE, GREEN, BLUE, ORANGE = "#AAAAAA", "#FFFFFF", "#00FF00", "#4D79FF", "#FF9900"
do
	local L = M.lines()
	for _, h in ipairs({ "AirGap", "Gap  ", "Press>Hit" }) do
		want("見出し " .. h .. " は灰", colour_of(L[1], h), GREY)
	end
	want("Jump の行の見出しも灰", colour_of(L[3], "Jump  "), GREY)
	want("相手の技は白", colour_of(L[2], "J.MP > J.MK"), WHITE)
	-- 帯の字と同じ強さの色 (本人、2026-09-27: ボタン色をメモリのものと合わせる)。
	want("自分のボタン名は帯の字と同じ色 (弱は水色)", colour_of(L[2], "LP"), "#00CAFF")
	do
		local bar_p
		for _, c in ipairs(L[2]) do if c[1] == "P" then bar_p = c[2] end end
		want("帯の P と同じ色", colour_of(L[2], "LP"), bar_p)
	end
	want("測れなかった隙間も白", colour_of(L[2], "?"), WHITE)
	want("押した>当たったは白", colour_of(L[2], " 4t>8t"), WHITE)
	want("発生は白", colour_of(L[2], " (5t)"), WHITE)
	want("勝ちは緑", colour_of(L[2], " WIN"), GREEN)
	want("PreJump の字は白", colour_of(L[3], "PreJump("), WHITE)
	want("移行の長さは白", colour_of(L[3], "3t"), WHITE)
	want("Guard の字は白", colour_of(L[3], ") > Guard "), WHITE)
	want("ガードしたティックは白", colour_of(L[3], "2t"), WHITE)
	want("In Blockstun の字は白", colour_of(L[3], "In Blockstun 14t at "), WHITE)
	want("区切りの , は白", colour_of(L[3], ","), WHITE)
	local cs = stun_colours(L[3])
	want("押したティックは押した弱 P の水色", cs[1], "#00CAFF")
	want("t の付いた最後のティックも水色", cs[2], "#00CAFF")
	-- 見えている灰は見出しの行だけ。空白は描かれないので数えない。
	local stray = {}
	for i = 2, #L do
		for _, c in ipairs(L[i]) do
			if c[2] == GREY and c[1]:find("%S") and c[1] ~= "Jump  " and c[1] ~= "Landing Advantage " then stray[#stray + 1] = c[1] end
		end
	end
	want("見出し以外に灰の文字は無い", table.concat(stray, ","), "")
	want("早押しの x は描かない", table.concat(screen(), "/"):find("x", 1, true), nil)
	want("@ は使わない", table.concat(screen(), "/"):find("@", 1, true), nil)
	want("数字はすべて t 付き (P1 / P2 を除く)", bare(screen()), "")
end

print("-- 早押し 3 回、押し直しが 9 で遅れて被弾 (airg_s13)")
new_jump()
guard("MP", { 1, 2, 3 })
wait(3)
p2_start("MK"); tick()                       -- @4 相手が MK を出し始める
wait(4)
p1_attack("LP"); tick()                      -- @9
box(P2, 1); hit_p1(); tick()                 -- @10 MK の判定が出て、そのまま届く
box(P2, 0)
s = screen()
show(s)
-- 弱 P は前の場面で判定が出て発生 5 と分かっている (覚えた発生)。この回は判定が
-- 出る前に殴られたので、その 5 を使う。9t の隙間なら 9 - 5 + 1 = 5 までに押す。
-- 結果の語は大文字、量はその後ろ (本人、2026-09-27)。
want("弱 P (発生 5) は 5 まで。9 は 4t 遅い", s[2], "J.MP > J.MK  --------P|   9t  LP 9t (5t) LATE 4t")
want("3 回までは全部", s[3], "Jump  PreJump(3t) > Guard 2t PPP  In Blockstun 14t at 2,3,4t")

print("-- 強 P を 4 で出して相打ち (airg_s04)")
new_jump()
guard("MP")
wait(3)
p1_attack("HP"); p2_start("MK"); tick()      -- @4
wait(5)
box(P1, 1); box(P2, 1); hit_p2(); hit_p1(); tick()   -- @10 同時。相手はもう当たりの状態
box(P1, 0); box(P2, 0)
s = screen()
show(s)
want("同じティックに当たれば相打ち。強 P は発生 7", s[2], "J.MP > J.MK  ---P-----#   9t  HP 4t>10t (7t) TRADE")

do
	-- 押したボタンは P / K、強さは右端の入力表示と同じ色 (本人、2026-09-27)。
	local row = M.lines()[2]
	local ps = {}
	for _, c in ipairs(row) do if c[1] == "P" then ps[#ps + 1] = c[2] end end
	want("強 P の P は赤", ps[1], "#FF0000")
	local hp
	for _, c in ipairs(row) do if c[1] == "HP" then hp = c[2] end end
	want("Press>Hit の HP も赤", hp, "#FF0000")
end

print("-- 3t の隙間は弱 P では割り込めない (airg_s14)")
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP")
p1_attack("LP"); p2_start("LK"); tick()      -- @1 最速
wait(2)
hit_p1(); tick()                             -- @4 LK が届く
s = screen()
show(s)
-- 発生 5 > 隙間 3: 最速の 1 で押しても判定が出るのは 5。測った発生なので出してよい
-- (本人、2026-09-27)。
want("最速でも隙間が足りない", s[2], "J.LP > J.LK  P--|   3t  LP 1t (5t) NO GAP")

print("-- 早押しだけで何も出ず、次もガード (airg_s10 row 30)")
new_jump()
guard("LP", { 13 })                          -- 0x025286 のティックの押し
wait(3)
guard("LK"); wait(3)
guard("MP")
s = screen()
show(s)
-- 14t の振動の 14t 目: 1 ティック早かった。
want("行には何も付かない", s[2], "J.LP > J.LK  ---|   3t")
want("振動の最後のティックの押し", s[5], "Jump  PreJump(3t) > Guard 2t P  In Blockstun 14t at 14t")

print("-- 振動中の押しは、その振動を始めた当たりの行 (一段前) に (本人、2026-09-27)")
-- 2 発目 (LK) をガードした振動は、LK が | で届いた 1 行目に書く。最初の振動は
-- 上に行が無いので、自分のガードがある行 (初動の行か表の下) に書く (上の場面)。
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP"); wait(3)
-- 当たりを 1 として 3 で弱 K、6 で中 K。9 で画面を取る (振動の長さはまだ無い)。
local mid
guard("LK", nil, nil, { [2] = function() ram[P1 + 0x126] = 0x10 end,
                        [5] = function() ram[P1 + 0x126] = 0x20 end,
                        [8] = function() mid = screen() end })
wait(3)
guard("MP")
s = screen()
show(s)
-- ボタンは | の直後 (本人、2026-09-27: メーターの後ろで押すボタン)、ティックは右の列。
want("1 行目 (LK が届いた行) に LK の振動の押し", s[2], "J.LP > J.LK  ---|KK   3t  In Blockstun 14t at 3,6t")
want("2 行目 (その振動の後の隙間) には付かない", s[3], "J.LK > J.MP  ---|     3t")
want("振動の途中は長さなしで押しだけ", mid ~= nil and mid[2]:match("In Blockstun at 3,6t$") ~= nil, true)
do
	local cs = stun_colours(M.lines()[2])
	want("先に押した弱 K は水色", cs[1], "#00CAFF")
	want("後に押した中 K は黄", cs[2], "#FFFF00")
	local ls = letter_colours(M.lines()[2])
	want("| の後の字: 弱 K は水色", ls[1], "#00CAFF")
	want("| の後の字: 中 K は黄", ls[2], "#FFFF00")
end

print("-- 押しても技が出なかった押しは、技の出始めにしない")
-- ゲームが受け付けなかった押し ($1B8 が動かない)。帯には数字で残るが、
-- 技の名前・届くまで・結果は実際に出た 5 の押しから取る。
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()     -- 着地してチェーンを閉じる
set(P2, { [0x05] = 0x00 })
new_jump()
guard("MP")
tick()                                       -- @1
ram[P1 + 0x126] = 0x01; tick()               -- @2 押したが出ない
tick()                                       -- @3
p2_start("MK"); tick()                       -- @4
p1_attack("LP"); tick()                      -- @5 出た
wait(3)                                      -- @6..@8
box(P1, 1); hit_p2(); tick()                        -- @9 当たる
box(P1, 0)
s = screen()
show(s)
want("出たのは 5 の押し、9 で当たって発生 5", s[2], "J.MP > J.MK  -P--P---*    ?  LP 5t>9t (5t) WIN")

print("-- 相手の発生はガードした技の側 (左) に付く (本人、2026-09-27)")
-- チェーンの最初の技 (J.LP) も、行ができる前に出始めているが測れること。
-- ログでは J.LK はあなたの -1 で出始めていた。-1, 0, 1, 2, 3 の 5 ティック目で判定。
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()     -- 着地してチェーンを閉じる
set(P2, { [0x05] = 0x00 })
new_jump()
p2_start("LP"); tick()                       -- J.LP を出し始める (行はまだ無い)
wait(3)
box(P2, 1)                                   -- 5 ティック目に判定が出て、そのまま当たる
-- 前の技 (LP) の判定が、LK を出し始めたティックにまだ残っている形にする。
-- 「出ている」で数えると出始めが発生 1 になる。数えるのは「出た瞬間」。
guard("LP", nil, nil, { [11] = function() box(P2, 1) end,
                        [12] = function() p2_start("LK") end })
box(P2, 0); tick()                           -- @1 前の判定が消える
tick()                                       -- @2
box(P2, 1); tick()                           -- @3 LK の判定が出る (まだ届かない)
guard("LK")                                  -- @4 届く
s = screen()
show(s)
want("最初の技 J.LP も発生 5", s[2], "J.LP(5t) > J.LK  ---|   3t")
want("J.LK の発生 5 は次の行の左", s[3], "J.LK(5t) > ?")

print("-- 発生 7 でも、離れていれば当たるのは 9 (距離が見える)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("MP")
p1_attack("HP"); tick()                      -- @1
wait(5)                                      -- @2..@6
box(P1, 1); tick()                           -- @7 判定が出る
wait(1)                                      -- @8
hit_p2(); tick()                             -- @9 当たる
box(P1, 0)
s = screen()
show(s)
want("押した 1、当たった 9、発生 7", s[2], "J.MP > ?  P-------*    ?  HP 1t>9t (7t) WIN")

print("-- ジャンプ移行中 (まだ地上) に殴られた: PreJump (本人、2026-09-27)")
set(P1, { [0x05] = 0x00, [0x06] = 0x00, [0x38] = 0 }); tick()   -- 着地して地上に立つ
set(P2, AIR); set(P2, { [0x05] = 0x00, [0x54] = 0x00 })
p2_start("LP"); tick()                       -- 相手が J.LP を出し始める
wait(2)
set(P1, { [0x05] = 0x00, [0x06] = 0x06, [0x07] = 0x00, [0x38] = 0 })
tick(); tick()                               -- ジャンプの 1, 2 (まだ地上)
box(P2, 1); hit_p1(); tick()                 -- ジャンプの 3 で当たる
box(P2, 0)
s = screen()
show(s)
-- 左は相手の技だけ。PreJump は自分のジャンプの話なので右 (Jump) に書く。
-- 移行は終わっていないので > で並べない (本人)。
want("行は相手の技だけ", s[2], "J.LP(6t)")
want("Jump の行に PreJump Hit", s[3], "Jump  PreJump Hit 3t")

print("-- ガードに失敗して空中で殴られた (本人、2026-09-27)")
new_jump()                                   -- 1〜3 が移行、4 で空中
p2_start("LP"); tick()                       -- 5 相手が J.LP を出し始める
tick()                                       -- 6
box(P2, 1); hit_p1(); tick()                 -- 7 ガードせず当たる (空中の 4)
box(P2, 0)
s = screen()
show(s)
want("行は相手の技だけ", s[2], "J.LP(3t)")
want("Jump の行に PreJump(3) > Hit 4t", s[3], "Jump  PreJump(3t) > Hit 4t")
do
	local L = M.lines()
	local hit
	for _, c in ipairs(L[3]) do if c[1] == "Hit" then hit = c[2] end end
	want("Hit は赤", hit, "#FF0000")
end

print("-- チェーンの途中で殴られたのは、その行の結果のまま (別の行を作らない)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP"); wait(3)
p2_move("LK"); hit_p1(); tick()              -- 2 発目の LK をガードし損ねた
s = screen()
show(s)
want("1 行のまま、行の結果が HIT", s[2], "J.LP > J.LK  ---|   3t  HIT")
want("行は増えない (見出し・行・Jump)", #s, 3)

print("-- 相手の攻撃が届いたティックに押した: 技が出始めてガードできず被弾 (airg_s16)")
-- 実機ではレバーは後ろのまま、届いたティックに弱 P を押して $1B8 が動いた。
-- その押しを取らないと、行は前の EARLY しか言わなかった (本人、2026-09-27)。
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("MP"); wait(9)                         -- @1..@9
p1_attack("LP"); p2_move("MK"); hit_p1(); tick()   -- @10 押したティックに届く
s = screen()
show(s)
-- 弱 P の発生 5 は前の場面で覚えている。9t の隙間なら 9 - 5 + 1 = 5 まで、10 は 5t 遅い。
want("届いたティックの押しを LATE として取る", s[2]:match("LP 10t %(5t%) LATE 5t") ~= nil, true)

print("-- 振動中に押したあと、ガードせず殴られた: 振動の押しと HIT の両方")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP", { 10 }); wait(2)
p2_move("LK"); hit_p1(); tick()              -- @3 ガードせず当たる
s = screen()
show(s)
want("行は HIT", s[2], "J.LP > J.LK  --|   2t  HIT")
want("押しは振動の中の 11t", s[3], "Jump  PreJump(3t) > Guard 2t P  In Blockstun 14t at 11t")

print("-- ジャンプ以外で空中に出て殴られても、前のジャンプから数えない")
-- 着地したらそのジャンプは終わり。空中へ出る技などで浮いたところを殴られた
-- とき、前のジャンプの飛び上がりから数えた数字を出してはいけない。
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()     -- 着地
local before2 = table.concat(screen(), "/")
set(P1, { [0x05] = 0x00, [0x06] = 0x0E, [0x38] = 1 }); tick()   -- ジャンプを経ずに空中へ
tick()
hit_p1(); tick()
want("ジャンプの数字を出さない", table.concat(screen(), "/"), before2)

print("-- キックは K、中は黄。出なかった押しは押したボタンで")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP")
ram[P1 + 0x126] = 0x10; tick()               -- @1 弱 K を押したが出ない
p1_attack("MK"); ram[P1 + 0x126] = 0x20; tick()   -- @2 中 K が出る
p2_move("LK"); hit_p1(); tick()              -- @3 LK が届く
s = screen()
show(s)
want("弱 K と中 K", s[2]:match("^J%.LP > J%.LK  KK|") ~= nil, true)
do
	local row, ks = M.lines()[2], {}
	for _, c in ipairs(row) do if c[1] == "K" then ks[#ks + 1] = c[2] end end
	want("弱は水色", ks[1], "#00CAFF")
	want("中は黄", ks[2], "#FFFF00")
end

print("-- 発生は空振りでも覚える。空中と地上は別 (本人、2026-09-27)")
-- 地上の弱 P を出して発生 3 を覚えさせる。空中の弱 P (発生 5) とは別の技。
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P1, { [0x06] = 0x0A, [0x105] = 1, [0x102] = 0, [0x101] = 0 }); bump(P1); tick()   -- 地上 LP
tick()
box(P1, 1); tick()                           -- 3 で判定 (空振り)
box(P1, 0)
set(P1, { [0x06] = 0x00, [0x105] = 0 })
-- 空中で弱 K を空振り (行は無い)。4 で判定 = ザベルのジャンプ弱 K の形。
new_jump()
p1_attack("LK"); tick()
tick(); tick()
box(P1, 1); tick()                           -- 4 で判定
box(P1, 0)
set(P1, { [0x07] = 0x02, [0x105] = 0 })
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()     -- 着地
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP")
p1_attack("LK"); ram[P1 + 0x126] = 0x10; tick()   -- @1 弱 K、判定の前に
wait(1)
p2_move("LK"); hit_p1(); tick()              -- @3 LK が届く
s = screen()
show(s)
want("空振りで覚えた J.LK の発生 4 を使う", s[2]:match("LK 1t %(4t%) NO GAP") ~= nil, true)
new_jump()
guard("LP")
p1_attack("LP"); tick()                      -- @1 弱 P、判定の前に
wait(1)
p2_move("LK"); hit_p1(); tick()              -- @3
s = screen()
show(s)
want("空中の弱 P は地上の発生 3 でなく 5", s[2]:match("LP 1t %(5t%) NO GAP") ~= nil, true)

print("-- $1B8 を動かさないキャラ (ジェダ): 攻撃中の印 $105 の立ち上がりで数える")
-- 実機ではジェダのジャンプ攻撃で $1B8 が一度も動かず (判定 31 回)、$1B8 だけで
-- 数えた J.LK は発生 669 と出た (本人のスクリーンショット、2026-09-27)。
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
set(P2, { [0x105] = 0 }); tick()             -- 相手は技を出していない
set(P2, { [0x06] = 0x06, [0x105] = 1, [0x102] = 0, [0x101] = 2 }); tick()   -- J.LK。$1B8 は動かない
wait(3)
box(P2, 1)
guard("LK")                                  -- 5 で判定が出て、そのまま当たる
s = screen()
show(s)
want("$105 の立ち上がりから数えて発生 5", s[2]:match("^J%.LK%(5t%) > ") ~= nil, true)

print("-- ジェダ型のチェーン: $1B8 も動かず $105 も立ったまま、技の入れ替わりで数える")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
set(P2, { [0x105] = 0 }); tick()
set(P2, { [0x06] = 0x06, [0x105] = 1, [0x102] = 0, [0x101] = 0 }); tick()   -- J.LP を出し始める
wait(3)
box(P2, 1)
-- 振動の 11 で J.LK に入れ替わる (弱 P -> 弱 K)。$105 は立ったまま、$1B8 も動かない。
guard("LP", nil, nil, { [11] = function() set(P2, { [0x101] = 2 }) end })
wait(4)                                      -- @1..@4
box(P2, 1)
guard("LK")                                  -- @5 で判定が出て当たる
s = screen()
show(s)
-- LK の始まりは振動の 11 (当たり + 11)。当たり + 18 で判定 = 発生 8。
want("入れ替わりから数えた LK の発生 8", s[3]:match("^J%.LK%(8t%) > ") ~= nil, true)
want("最初の LP は発生 5", s[2]:match("^J%.LP%(5t%) > J%.LK") ~= nil, true)

print("-- ダッシュは技ではない ($06 = 14 のあいだも $105 が立つ)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("MP")
set(P1, { [0x06] = 0x14, [0x105] = 1 }); tick()   -- @1 空中ダッシュ
wait(2)
p2_move("MK"); hit_p1(); tick()              -- @4 殴られる
s = screen()
show(s)
want("ダッシュを技として出さない", s[2]:match("LATE") == nil and s[2]:match("HIT") ~= nil, true)
set(P1, { [0x06] = 0x06, [0x105] = 0 })

print("-- 相手の初動: ジャンプから何ティックで技を出したか (本人、2026-09-27)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
set(P2, { [0x05] = 0x00, [0x06] = 0x06, [0x07] = 0x00, [0x38] = 0, [0x105] = 0 })
tick(); tick(); tick()                       -- 相手のジャンプの 1, 2, 3 (地上)
set(P2, { [0x07] = 0x02, [0x38] = 1 }); tick()   -- 4 で空中へ
p2_start("LP"); tick()                       -- 5 で J.LP
wait(3)
box(P2, 1)
guard("LP")                                  -- J.LP の判定がそのまま当たる
s = screen()
show(s)
-- 相手: ジャンプの 5 で J.LP、その発生 5。Tick Data の Action Timeline と同じく
-- ティックを先に (本人、2026-09-27: Jump > 6t J.LP(5t))。
-- 自分: 移行 3、飛んで 10 でガード。空いている帯の列に (本人、2026-09-27)。
want("初動の行: 相手はジャンプの 5 で J.LP(5)、自分は飛んで 10 でガード", s[2], "Jump > 5t J.LP(5t)         PreJump(3t) > Guard 10t")
-- 自分のガードは Gap より右 (本人、2026-09-27: ギャップより右にガードなんだらを)。
want("自分のガードは Press>Hit の列", s[2]:find("PreJump", 1, true), s[1]:find("Press>Hit", 1, true))
want("その下にガードの行", s[3]:match("^J%.LP%(5t%) > ") ~= nil, true)

print("-- 技を出さずに着地したジャンプも、後の技と組にしない")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00, [0x06] = 0x00, [0x105] = 0 })
new_jump()
set(P2, { [0x05] = 0x00, [0x06] = 0x06, [0x07] = 0x00, [0x38] = 0, [0x105] = 0 })
tick(); tick(); tick()
set(P2, { [0x07] = 0x02, [0x38] = 1 }); wait(10)   -- 空中
set(P2, { [0x06] = 0x00, [0x38] = 0 }); wait(10)   -- 技を出さずに着地
set(P2, { [0x38] = 1 }); p2_start("LP"); tick()
wait(3)
box(P2, 1)
guard("LP")
s = screen()
show(s)
want("着地で捨てたジャンプは出ない", s[2]:match("^Jump") == nil, true)

print("-- 最初の攻撃の振動中の押しは初動の行に、自分のガードの後ろ (本人、2026-09-27)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
set(P2, { [0x05] = 0x00, [0x06] = 0x06, [0x07] = 0x00, [0x38] = 0, [0x105] = 0 })
tick(); tick(); tick()
set(P2, { [0x07] = 0x02, [0x38] = 1 }); tick()
p2_start("LP"); tick()
wait(3)
box(P2, 1)
guard("LP", nil, nil, { [2] = function() ram[P1 + 0x126] = 0x10 end,     -- 弱 K
                        [7] = function() ram[P1 + 0x126] = 0x04 end })    -- 強 P
wait(3)
guard("LK")
s = screen()
show(s)
-- 自分のガードは Gap より右 (本人、2026-09-27)。最初の振動のボタンは受けた技の後ろ、
-- 空いている帯の列 (後の行の | の直後と同じ考え)。Blockstun の字はガードの横に
-- 置くと 90 字を超えるので、押したときだけ 1 行下の同じ列。
want("初動の行の数字もすべて t 付き", bare(s), "")
want("初動の行: ボタンは帯の列、ガードは右の列", s[2], "Jump > 5t J.LP(5t)  KP         PreJump(3t) > Guard 10t")
want("その下の行: 最初の振動", s[3]:match("^%s+In Blockstun 14t at 3,8t$") ~= nil, true)
want("自分のガードは Press>Hit の列", s[2]:find("PreJump", 1, true), s[1]:find("Press>Hit", 1, true))
want("振動の押しも Press>Hit の列", s[3]:find("In Blockstun", 1, true), s[1]:find("Press>Hit", 1, true))
want("ボタンは帯とそろう", s[2]:find("KP", 1, true), s[4]:find("---|", 1, true))
want("J.LP の行には付かない", s[4]:match("Blockstun") == nil, true)
do
	local n = 0
	for _ in table.concat(s, "/"):gmatch("Blockstun") do n = n + 1 end
	want("画面に 1 回だけ (表の下には出さない)", n, 1)
end
do
	local cs = stun_colours(M.lines()[3])
	want("弱 K は水色", cs[1], "#00CAFF")
	want("強 P は赤", cs[2], "#FF0000")
	local ls = letter_colours(M.lines()[2])
	want("受けた技の後の字: 弱 K は水色", ls[1], "#00CAFF")
	want("受けた技の後の字: 強 P は赤", ls[2], "#FF0000")
end

print("-- 振動中に何度も押したら、最初と最後だけ (右端の入力表示にかからない幅)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
set(P2, { [0x05] = 0x00, [0x06] = 0x06, [0x07] = 0x00, [0x38] = 0, [0x105] = 0 })
tick(); tick(); tick()
set(P2, { [0x07] = 0x02, [0x38] = 1 }); tick()
p2_start("LP"); tick()
wait(3)
box(P2, 1)
do
	local f = function() ram[P1 + 0x126] = 0x10 end
	guard("LP", nil, nil, { [1] = f, [3] = f, [5] = f, [7] = f, [9] = f, [11] = f })
end
wait(3)
guard("LK")
s = screen()
show(s)
want("最初と最後 (字)", s[2]:match("^Jump > 5t J%.LP%(5t%)  K%.%.K ") ~= nil, true)
want("最初と最後 (ティック)", s[3]:match("In Blockstun 14t at 2%.%.12t$") ~= nil, true)
want("Press>Hit の列は見出しとそろう", s[3]:find("In Blockstun", 1, true), s[1]:find("Press>Hit", 1, true))
want("ガードも見出しとそろう", s[2]:find("PreJump", 1, true), s[1]:find("Press>Hit", 1, true))
do
	local widest = 0
	for _, l in ipairs(s) do if #l > widest then widest = #l end end
	want("どの行も 76 字以内", widest <= 76, true)
end
want("数字は t 付き (並びは最後に 1 つ)", bare(s), "")

print("-- 初動の行の K..K が帯のどれより長くても、Gap の列まで 2 字空く")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
set(P2, { [0x05] = 0x00, [0x06] = 0x06, [0x07] = 0x00, [0x38] = 0, [0x105] = 0 })
tick(); tick(); tick()
set(P2, { [0x07] = 0x02, [0x38] = 1 }); tick()
p2_start("LP"); tick()
wait(3)
box(P2, 1)
do
	local f = function() ram[P1 + 0x126] = 0x10 end
	guard("LP", nil, nil, { [1] = f, [3] = f, [5] = f, [7] = f })
end
guard("LK")                                  -- すぐ次: 隙間 0t、帯は "|" だけ
s = screen()
show(s)
do
	local _, me = s[2]:find("K..K", 1, true)
	want("K..K の後に 2 字空く", me ~= nil and me <= s[1]:find("Gap  Press", 1, true) - 3, true)
	want("ガードは見出しの下", s[2]:find("PreJump", 1, true), s[1]:find("Press>Hit", 1, true))
end

print("-- 後の行の振動で連打しても、帯の後ろの K..K で列がずれない")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP"); wait(3)
do
	local f = function() ram[P1 + 0x126] = 0x10 end
	guard("LK", nil, nil, { [1] = f, [3] = f, [5] = f, [7] = f })
end
wait(3)
guard("MP")
s = screen()
show(s)
want("| の後ろに K..K", s[2]:match("^J%.LP > J%.LK  %-%-%-|K%.%.K ") ~= nil, true)
do
	-- Gap の数字は見出しの Gap と右端がそろう
	local ge = s[1]:find("Gap  Press>Hit", 1, true) + 2
	want("Gap の数字は見出しの下", select(2, s[2]:find(" 3t", 1, true)), ge)
	want("下の行の Gap の数字も", select(2, s[3]:find(" 3t", 1, true)), ge)
end
want("Blockstun は見出しの下", s[2]:find("In Blockstun", 1, true), s[1]:find("Press>Hit", 1, true))
do
	-- 帯の列の右端から Gap の列までは 2 字空く (字数で測る。".." は 1 つで 2 字)
	local _, be = s[2]:find("K..K", 1, true)
	want("K..K の後に 2 字空く", be <= s[1]:find("Gap  Press", 1, true) - 3, true)
end

print("-- 初動の技の発生はその技のもの。判定が出ずに終わったら括弧なし、後の技の発生を借りない")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
set(P2, { [0x05] = 0x00, [0x06] = 0x06, [0x07] = 0x00, [0x38] = 0, [0x105] = 0 })
tick(); tick(); tick()
set(P2, { [0x07] = 0x02, [0x38] = 1 }); tick()
p2_start("LP"); tick()                       -- 5 で J.LP、判定は出ない
wait(2)
set(P2, { [0x105] = 0 }); tick()             -- 判定が出ずに終わる
p2_start("LK"); tick()                       -- 次の J.LK は判定が出てガードされる
wait(3)
box(P2, 1)
guard("LK")
s = screen()
show(s)
want("初動の行: J.LP に括弧なし", s[2]:match("^Jump > 5t J%.LP%s+PreJump") ~= nil, true)
want("ガードの行: J.LK(5)", s[3]:match("^J%.LK%(5t%) > ") ~= nil, true)

print("-- 相手の初動: ダッシュ。ダッシュ攻撃は $06 = 14 のまま $1B8 で拾う")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
set(P2, { [0x05] = 0x00, [0x06] = 0x14, [0x38] = 0, [0x105] = 0 }); tick()   -- ダッシュの 1
wait(8)                                      -- 2..9
set(P2, { [0x105] = 1, [0x102] = 0, [0x101] = 0 }); bump(P2); tick()   -- 10 でダッシュ LP
wait(3)
box(P2, 1)
guard("LP")
s = screen()
show(s)
want("初動の行: ダッシュの 10 で LP(5)", s[2]:match("^Dash > 10t LP%(5t%)%s+PreJump%(3t%) > Guard %d+t$") ~= nil, true)

print("-- 相手の初動: 浮くダッシュ (ジェダ、サスカッチ)。$1B8 は動かず、$06 = 14 のまま $105 が立ったところが技 (airg_s18)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00, [0x06] = 0x00, [0x105] = 0 })
new_jump()
set(P2, { [0x05] = 0x00, [0x06] = 0x14, [0x07] = 0x02, [0x38] = 1, [0x105] = 0 }); tick()   -- ダッシュの 1 (もう空中)
wait(10)                                     -- 2..11
set(P2, { [0x105] = 1, [0x102] = 0, [0x101] = 2 }); tick()   -- 12 で LK。$1B8 は動かない
wait(3)
box(P2, 1)
guard("LK")
s = screen()
show(s)
-- ジャンプと同じ形 (本人、2026-09-27: ジェダでダッシュ＞LKを一行目に)。
want("初動の行: ダッシュの 12 で J.LK(5)", s[2]:match("^Dash > 12t J%.LK%(5t%)%s+PreJump%(3t%) > Guard %d+t$") ~= nil, true)
want("ガードの行も J.LK(5)", s[3]:match("^J%.LK%(5t%) > ") ~= nil, true)

print("-- 技を出さずに終わった初動は、後の技と組にしない")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00, [0x06] = 0x00, [0x105] = 0 })
new_jump()
set(P2, { [0x05] = 0x00, [0x06] = 0x14, [0x38] = 0, [0x105] = 0 }); tick()   -- ダッシュ
wait(4)
set(P2, { [0x06] = 0x00 }); tick()           -- 技を出さずにダッシュが終わる
wait(20)
set(P2, { [0x38] = 1 }); p2_start("LP"); tick()
wait(3)
box(P2, 1)
guard("LP")
s = screen()
show(s)
want("初動の行は出ない", s[2]:match("^Dash") == nil and s[2]:match("^J%.LP") ~= nil, true)

print("-- 最後は有利: 相手が後から着地すれば自分が有利 (本人、2026-09-27: アドバンテージで)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP")
wait(5)
set(P1, { [0x38] = 0 }); tick()              -- 自分が着地
wait(3)
set(P2, { [0x38] = 0 }); tick()              -- 相手はその 4 ティック後
s = screen()
show(s)
want("Jump の行", s[#s - 1], "Jump  PreJump(3t) > Guard 2t")
want("自分が 4t 有利", s[#s], "Landing Advantage P1 +4t")
do
	local c
	for _, x in ipairs(M.lines()[#s]) do if x[1] == "P1 +4t" then c = x[2] end end
	want("有利な P1 は P1 の色", c, "#4D79FF")
	want("Landing Advantage は見出しと同じ灰 (ラベル)", colour_of(M.lines()[#s], "Landing Advantage "), "#AAAAAA")
end

print("-- 同じティックに着地したら 0t")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP")
wait(5)
set(P1, { [0x38] = 0 }); set(P2, { [0x38] = 0 }); tick()
s = screen()
show(s)
want("五分", s[#s]:match("Advantage 0t$") ~= nil, true)

print("-- 自分の攻撃をガードさせた: 相手のガードが解けたティックと自分の着地 (Tick Data と同じ)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("MP")
wait(1)
p1_attack("LP"); tick()                      -- @2 弱 P
wait(3)
box(P1, 1); set(P2, { [0x05] = 0x02, [0x54] = 0xFF }); tick()   -- @6 相手がガード
box(P1, 0)
wait(12)
set(P2, { [0x05] = 0x00, [0x54] = 0x00 }); tick()   -- @19 相手のガードが解ける
wait(4)
set(P1, { [0x38] = 0 }); tick()              -- @24 自分が着地
wait(3)
set(P2, { [0x38] = 0 }); tick()              -- 相手の着地は使わない
s = screen()
show(s)
want("ガードさせた行", s[2]:match("LP 2t>6t %(5t%) BLOCKED$") ~= nil, true)
want("相手のガードが解けた 19 と自分の着地 24: 相手が 5t 有利", s[#s]:match("Advantage P2 %+5t$") ~= nil, true)

print("-- 殴られた: 自分の $05 が 0 に戻ったティックと、当てた相手の着地 (本人、2026-09-27)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP")
wait(2)
p2_move("LK"); hit_p1(); tick()              -- @3 殴られる
wait(10)
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x38] = 0 }); tick()
s = screen()
show(s)
want("殴られた行", s[2]:match("HIT$") ~= nil, true)
want("自分が戻った次のティックに相手が着地: 自分が 1t 有利", s[#s]:match("Advantage P1 %+1t$") ~= nil, true)

print("-- 当ててダウンさせた: 起き上がって $05 と $06 が両方 0 のティック ($1A7 が動いたらダウン)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00, [0x06] = 0x00, [0x1A7] = 0 })
new_jump()
guard("MP")
wait(3)
p1_attack("LP"); p2_start("MK"); tick()      -- @4
wait(3)
box(P1, 1); hit_p2(); tick()                 -- @8 当てる
box(P1, 0)
wait(10)
set(P1, { [0x38] = 0 }); tick()              -- @19 自分が着地
wait(5)
set(P2, { [0x38] = 0, [0x06] = 0x02 }); tick()   -- @25 相手はダウン ($05 は 02 のまま)
set(P2, { [0x05] = 0x00, [0x06] = 0x04, [0x1A7] = 1 }); tick()   -- @26 $05 は 0、起き上がりは $06
for k = 2, 9 do ram[P2 + 0x1A7] = k; tick() end                   -- @27..34
local before_up = table.concat(screen(), "/")
set(P2, { [0x06] = 0x00 }); tick()           -- @35 両方 0: 動ける
s = screen()
show(s)
want("起き上がるまでは出ない", before_up:find("Advantage", 1, true), nil)
want("起き上がった 35 と自分の着地 19: 自分が 16t 有利", s[#s]:match("Advantage P1 %+16t$") ~= nil, true)

print("-- $1A7 が前のダウンの値のままなら、ダウンではない ($05 が戻ったティック)")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00, [0x06] = 0x00, [0x1A7] = 9 })
new_jump()
guard("MP")
wait(3)
p1_attack("LP"); p2_start("MK"); tick()      -- @4
wait(3)
box(P1, 1); hit_p2(); tick()                 -- @8 当てる
box(P1, 0)
wait(10)
set(P1, { [0x38] = 0 }); tick()              -- @19 自分が着地
wait(3)
set(P2, { [0x05] = 0x00, [0x06] = 0x0C }); tick()   -- @23 すぐガードに入る ($06 は 0 でない)
s = screen()
show(s)
want("$05 が戻った 23 と 19: 自分が 4t 有利", s[#s]:match("Advantage P1 %+4t$") ~= nil, true)
set(P2, { [0x06] = 0x00, [0x1A7] = 0 })

print("-- 相打ち: 両方とも $05 が 0 に戻ったティック")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00, [0x06] = 0x00 })
new_jump()
guard("MP")
wait(3)
p1_attack("HP"); p2_start("MK"); tick()      -- @4
wait(5)
box(P1, 1); box(P2, 1); hit_p2(); hit_p1(); tick()   -- @10 相打ち
box(P1, 0); box(P2, 0)
wait(8)
set(P1, { [0x05] = 0x00 }); tick()           -- @19 自分が戻る
wait(2)
set(P2, { [0x05] = 0x00 }); tick()           -- @22 相手が戻る
s = screen()
show(s)
want("相打ちの行", s[2]:match("TRADE$") ~= nil, true)
want("22 と 19: 自分が 3t 有利", s[#s]:match("Advantage P1 %+3t$") ~= nil, true)

print("-- コンボ: 動けないうちに次が当たったら、最後の当たりから数え直す ($5C が跳ね上がる)")
set(P1, { [0x05] = 0x00, [0x38] = 0, [0x5C] = 0 }); tick()
set(P2, { [0x05] = 0x00, [0x06] = 0x00 })
new_jump()
guard("LP")
wait(2)
p2_move("LK"); hit_p1(); tick()              -- 殴られる
wait(3)
set(P2, { [0x38] = 0, [0x06] = 0x00, [0x105] = 0 }); tick()   -- 相手が着地 (動ける)
wait(2)
local before_combo = table.concat(screen(), "/")
set(P2, { [0x06] = 0x0A, [0x105] = 1 }); set(P1, { [0x5C] = 0x0B }); tick()   -- 地上から 2 発目 (自分は $05 = 02 のまま)
wait(4)
set(P2, { [0x06] = 0x00, [0x105] = 0 }); tick()   -- 相手の攻撃が終わる (T)
wait(6)
set(P1, { [0x05] = 0x00, [0x38] = 0, [0x5C] = 0 }); tick()   -- 自分が戻る (T + 7)
s = screen()
show(s)
want("自分が動けないうちは出ない", before_combo:find("Advantage", 1, true), nil)
want("2 発目から: 相手の攻撃の終わりと自分が戻ったティック。相手が 7t 有利", s[#s]:match("Advantage P2 %+7t$") ~= nil, true)
do
	-- 確定したら、その後の接触では変えない
	local fixed = s[#s]
	set(P2, { [0x05] = 0x02, [0x54] = 0x04 }); tick()
	set(P2, { [0x05] = 0x00, [0x54] = 0x00 }); tick()
	want("両方動けた後の接触では変わらない", screen()[#s], fixed)
end

print("-- 必殺技は SP / ES / EX")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()     -- 着地してチェーンを閉じる
new_jump()
set(P2, { [0x06] = 0x0E })
set(P1, { [0x05] = 0x02, [0x54] = 0xFF, [0x38] = 1 }); tick()
want("SP", screen()[2]:match("^SP > %?") ~= nil, true)
for _, c in ipairs({ { 0x10, "ES" }, { 0x12, "EX" } }) do
	set(P1, { [0x05] = 0x00 }); set(P1, { [0x38] = 0 }); tick()
	new_jump()
	set(P2, { [0x06] = c[1] })
	set(P1, { [0x05] = 0x02, [0x54] = 0xFF, [0x38] = 1 }); tick()
	want(c[2], screen()[2]:match("^" .. c[2] .. " > %?") ~= nil, true)
end

print("-- 地上のガードでは始めない")
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
local before = table.concat(screen(), "/")
set(P1, { [0x05] = 0x02, [0x54] = 0xFF, [0x38] = 0 }); tick()
want("前のチェーンのまま", table.concat(screen(), "/"), before)

print("-- 色が抜けていない (gui.text に nil を渡さない)")
local bad = 0
for _, l in ipairs(M.lines()) do
	for _, c in ipairs(l) do
		if type(c[1]) ~= "string" or type(c[2]) ~= "string" then bad = bad + 1 end
	end
end
want("すべての欄に文字と色", bad, 0)

print("-- キャラ選択 (試合の外) に出たら消える。覚えた発生も (本人、2026-09-27)")
globals.options.display_air_guard_gap = true
want("前の表示が残っている", #M.lines() > 0, true)
globals.match_running = function() return true end
globals.hotkeys_armed = false
tick()
want("入場中 (ラウンド前) は描かない", #M.lines(), 0)
globals.hotkeys_armed = true
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP")
want("試合に戻れば描く", #M.lines() > 0, true)
globals.match_running = function() return false end
tick()
want("試合の外では何も描かない", #M.lines(), 0)
globals.match_running = function() return true end
-- 新しいキャラで弱 P。前のキャラの発生 5 は持ち越さない。
set(P1, { [0x05] = 0x00, [0x38] = 0 }); tick()
set(P2, { [0x05] = 0x00 })
new_jump()
guard("LP")
p1_attack("LP"); tick()                      -- @1
wait(1)
p2_move("LK"); hit_p1(); tick()              -- @3
s = screen()
show(s)
want("前のキャラの発生を使わない", s[2]:match("LP 1t LATE") ~= nil and s[2]:match("%(5t%)") == nil, true)
globals.match_running, globals.hotkeys_armed = nil, nil

print("-- OFF にしたら消える")
globals.options.display_air_guard_gap = false
tick()
want("何も描かない", #M.lines(), 0)

print(fails == 0 and "all ok" or (fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
