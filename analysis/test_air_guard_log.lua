-- AIR GUARD LOG: DOES IT START, END AND WRITE WHERE IT SHOULD?
--
-- airGuardLog.lua is measurement only, but a logger that quietly records
-- nothing costs a whole session of air guards on the real machine. So the
-- trigger, the ticks from before it, the end and the write are stepped here
-- by hand. The real caller of on_tick is the emulator's clock.
--
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_air_guard_log.lua
local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local P1, P2 = 0xFF8400, 0xFF8800
local ram = {}
local function rb(a) return ram[a] or 0 end
memory = {
	readbyte = rb,
	readdword = function(a)
		return ((rb(a) * 256 + rb(a + 1)) * 256 + rb(a + 2)) * 256 + rb(a + 3)
	end,
}
local written = {}
function write_object_to_json_file(o, path)
	written[#written + 1] = { o = o, path = path }
	return true
end
local subs = {}
globals = {
	options = { knockdown_logger_enable = true, game_speed = 3 },
	truth = { ticker = { subscribe = function(_, f) subs[#subs + 1] = f end } },
}

local M = dofile("scripts/airGuardLog.lua")

print("-- 登録")
M.registerBefore("vTEST")
M.registerBefore("vTEST")
want("ticker に 1 回だけ登録する", #subs, 1)

local lg = 0
local function tick() lg = (lg + 1) % 256; ram[0xFF8081] = lg; subs[1]() end
local function state(who, s05, s54, s38)
	ram[who + 0x05], ram[who + 0x54], ram[who + 0x38] = s05, s54, s38
end

print("-- 始まりと、その前の 12 ティック")
state(P1, 0x00, 0x00, 1)
for _ = 1, 15 do tick() end
M.registerBefore("vTEST")
want("空中ガードが無ければ書かない", #written, 0)
state(P1, 0x02, 0xFF, 1)
tick()
state(P1, 0x00, 0xFF, 1)
for _ = 1, 5 do tick() end
-- 2 回目の空中ガード。同じ記録の中に events として残る。
state(P1, 0x02, 0xFF, 1)
tick()
state(P1, 0x00, 0xFF, 1)
tick()

print("-- 着地して 20 ティックで終わる")
state(P1, 0x00, 0xFF, 0)
for _ = 1, 19 do tick() end
M.registerBefore("vTEST")
want("19 ティックではまだ書かない", #written, 0)
tick()
M.registerBefore("vTEST")
want("20 ティック目で 1 本書く", #written, 1)
local o = written[1] and written[1].o or {}
want("ファイル名", written[1] and written[1].path, "reversal_logs/airg_s01.json")
want("版が入る", o.script_version, "vTEST")
want("守った側は P1", o.def, 1)
want("前 12 + 空中 8 + 着地 20 行", #(o.rows or {}), 12 + 8 + 20)
want("空中ガードは 2 回", #(o.events or {}), 2)
want("1 回目は 13 行目", o.events and o.events[1] and o.events[1].i, 13)
want("2 回目は 19 行目", o.events and o.events[2] and o.events[2].i, 19)
want("最初の行は全体を持つ", o.rows and o.rows[1] and #o.rows[1].base, 512)
want("振動の表を読む", o.hitstop_table and #o.hitstop_table, 112)
-- 判定の番号は ROM 側 (コマ +0x0A) なので、行ごとに P1 / P2 の 2 つを持たせる。
want("行ごとに判定の番号を持つ", o.rows and o.rows[13] and o.rows[13].ab and #o.rows[13].ab, 2)

-- 差分から 13 行目を組み立て直すと、P1 の $04-$07 が 00 02 00 00 になる。
local cur = {}
for i, v in ipairs(o.rows[1].base) do cur[i] = v end
for r = 2, 13 do
	local d = o.rows[r].d
	for k = 1, #d, 2 do cur[d[k]] = d[k + 1] end
end
want("差分から戻すと 13 行目は空中ガード", cur[2], 0x00020000)
want("P1 の $38 は dword 15 の先頭", math.floor(cur[15] / 0x1000000), 1)

print("-- 前の空中ガードの $140 が残っていても、当たりは数えない")
written = {}
state(P1, 0x02, 0x02, 1)
ram[P1 + 0x140] = 0x12
for _ = 1, 3 do tick() end
state(P1, 0x00, 0x00, 0)
for _ = 1, 25 do tick() end
M.registerBefore("vTEST")
want("空中で当たっただけなら書かない", #written, 0)

print("-- 地上ガードは数えない")
state(P2, 0x02, 0xFF, 0)
for _ = 1, 25 do tick() end
M.registerBefore("vTEST")
want("地上のガードなら書かない", #written, 0)

print("-- P2 が守った側でも記録する")
state(P2, 0x02, 0xFF, 1)
tick()
state(P2, 0x00, 0xFF, 0)
for _ = 1, 20 do tick() end
M.registerBefore("vTEST")
want("P2 の空中ガードを書く", #written, 1)
want("守った側は P2", written[1] and written[1].o.def, 2)
want("2 本目は s02", written[1] and written[1].path, "reversal_logs/airg_s02.json")

print("-- ジャンプ移行中 (地上) に殴られたときも記録する (本人、2026-09-27)")
written = {}
state(P2, 0x00, 0x00, 0)
ram[P1 + 0x06], ram[P1 + 0x07] = 0x06, 0x00
state(P1, 0x00, 0x00, 0)                    -- 地上でジャンプの状態 = 移行
tick()
state(P1, 0x02, 0x04, 0)                    -- 移行中に当たる
tick()
ram[P1 + 0x06] = 0x00
state(P1, 0x02, 0x04, 0)
for _ = 1, 20 do tick() end
M.registerBefore("vTEST")
want("移行中の被弾を書く", #written, 1)
want("守った側 (殴られた側) は P1", written[1] and written[1].o.def, 1)
state(P1, 0x00, 0x00, 0)
for _ = 1, 3 do tick() end

print("-- ガードに失敗して空中で殴られたときも記録する (本人、2026-09-27)")
written = {}
state(P1, 0x00, 0x00, 1)                    -- 空中で自由に動ける
tick()
state(P1, 0x02, 0x04, 1)                    -- ガードせず当たる
tick()
state(P1, 0x02, 0x04, 0)
for _ = 1, 20 do tick() end
M.registerBefore("vTEST")
want("空中の被弾を書く", #written, 1)
state(P1, 0x00, 0x00, 0)
for _ = 1, 3 do tick() end

print("-- スイッチが切れていれば何もしない")
written = {}
globals.options.knockdown_logger_enable = false
state(P2, 0x02, 0xFF, 1)
tick()
state(P2, 0x00, 0xFF, 0)
for _ = 1, 25 do tick() end
M.registerBefore("vTEST")
want("OFF なら書かない", #written, 0)

print("-- 着地しなくても 300 行で切る")
globals.options.knockdown_logger_enable = true
state(P2, 0x00, 0x00, 0)
tick()
state(P1, 0x02, 0xFF, 1)
tick()
state(P1, 0x00, 0xFF, 1)
for _ = 1, 400 do tick() end
M.registerBefore("vTEST")
want("上限で 1 本", #written, 1)
want("300 行で止まる", written[1] and #written[1].o.rows, 300)

print(fails == 0 and "all ok" or (fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
