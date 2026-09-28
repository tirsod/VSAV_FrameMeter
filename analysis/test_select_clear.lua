-- A CHARACTER SELECT IS A FRESH START (user, 2026-09-27: 起動しなおしの代わり).
--
-- Entering the select screen ($8009 = 2) clears what the last match left on
-- screen: the input history, the icon columns down the edges, PB Count with
-- its timeline and LateMash, PB Stats, the GC Command Trace. Once on the way
-- in, not every frame. What each clear does is run in the modules' own tests
-- (test_pb_counter, test_guard_mark_column, test_gc_command_trace); this reads
-- the wiring, which nothing can run without the whole emulator.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_select_clear.lua
local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end
local NL = string.char(10)

print("-- メインスクリプト: キャラ選択の場面に入ったとき 1 回だけ")
local m = io.open("vsav_training_master_script.lua"):read("*a")
local a = m:find("if memory.readbyte(0xFF8009) == 2 then", 1, true)
local b = m:find(NL .. "\telse" .. NL .. "\t\tglobals._select_cleared = false", a or 1, true)
want("キャラ選択の場面の中にある", a ~= nil and b ~= nil, true)
local body = m:sub(a or 1, b or 1)
for _, call in ipairs({
	"inpHistoryModule.clear()", "vsavScriptModule.clear()", "timersModule.clear()",
	"guardCancelModule.clear_trace()",
	"globals.total_pb_attempt_counter = {}", "globals.successful_pb_counter = {}",
}) do
	want("消す: " .. call, body:find(call, 1, true) ~= nil, true)
end
want("1 回だけ (入ったときに旗を立てる)",
	body:find("if not globals._select_cleared then", 1, true) ~= nil
	and body:find("globals._select_cleared = true", 1, true) ~= nil, true)
want("出たら旗を下ろす", b ~= nil, true)

print("-- 右端の入力表示: 読み込み直しと同じ空の表に戻す")
local v = io.open("vsavscriptv2.lua"):read("*a")
local ca = v:find('["clear"] = function()', 1, true)
local cb = v:find(NL .. "\tend,", ca or 1, true)
want("clear がある", ca ~= nil and cb ~= nil, true)
local cbody = v:sub(ca or 1, cb or 1)
want("両方の列を空に", cbody:find("inp  = { [1] = {}, [2] = {} }", 1, true) ~= nil, true)
want("待ちの数も 0 に", cbody:find("idle = { [1] =  0, [2] =  0 }", 1, true) ~= nil, true)
want("P2 のティック待ちも捨てる", cbody:find("globals.p2_tick_inputs = {}", 1, true) ~= nil, true)

if fails == 0 then print("all ok") else print(fails .. " 件 NG") os.exit(1) end
