-- A TRANSFORMATION MUST NOT STOP THE MEASUREMENT.
--
-- gameState's match_begun is 0xFF8401 and 0xFF8801 both reading 1, and those
-- drop to 0 while a character is transformed. framedata used it, so Demitri's
-- Bat Spin reset the whole measurement and the readout stayed empty for the
-- entire special - reported as "some specials produce nothing".
--
-- The master script already carries the conservative test for exactly this
-- (see match_actually_running and the note above it). This pins that framedata
-- asks it rather than match_begun, and that it still stops when the match
-- really is over.
--
-- Run from the package root - framedata requires ./scripts/tickData.
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_framedata_gate.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

-- The ticker is an Rx subject in the real thing; all framedata does is
-- subscribe, so the callback is captured here and driven by hand.
local captured
local resets = {}
package.loaded["./scripts/tickData"] = {
	reset = function(reason) resets[#resets + 1] = reason end,
	update = function() end,
	formatResult = function() return "" end,
	isMeasuring = function() return false end,
	getAbortReason = function() return nil end,
}
package.loaded["./scripts/tickDataVsav"] = {
	capture = function(tick) return { tick = tick, p1 = {}, p2 = {} } end,
}

memory = { readbyte = function() return 0 end, readdword = function() return 0 end }
globals = {
	options = { mo_enable_frame_data = true },
	show_menu = false,
	game_state = { match_begun = true },
	truth = { ticker = { subscribe = function(_, fn) captured = fn end } },
	set_last_data = function() end,
	set_last_route = function() end,
}

local fd = dofile("scripts/framedata.lua")
fd.registerStart()
want("購読した", type(captured), "function")

local function tick(n) resets = {} captured(n) return table.concat(resets, ",") end

tick(1)
-- 変身中: 両バイトが 0 になるので match_begun は false。conservative test は
-- true を返す。
globals.match_running = function() return true end
globals.game_state.match_begun = false
want("変身中でも測定を止めない", tick(2), "")

-- 本当に試合が終わったときは止める。
globals.match_running = function() return false end
want("試合が終われば止める", tick(3), "match_not_running")

-- 登場中は測らない。match_running は入場の時点でもう true なので、これだけでは
-- ラウンドが始まる前の行が出てしまう (user, 2026-09-10)。hotkeys_armed が
-- マスタースクリプト側の「ラウンドが生きているか」で、メニューと位置ショート
-- カットが既にこの後ろにいる。
globals.match_running = function() return true end
globals.hotkeys_armed = true
tick(6)
globals.hotkeys_armed = false
want("登場中は止める", tick(7), "round_not_ready")
globals.hotkeys_armed = true
want("ラウンドが始まれば測る", tick(8), "")
-- 試合そのものが終わったときは、理由が別であること。
globals.match_running = function() return false end
want("試合終了は別の理由", tick(9), "match_not_running")
globals.match_running = function() return true end
globals.hotkeys_armed = nil
tick(10)
want("hotkeys_armed が無い環境では今までどおり", tick(11), "")

-- 公開されていない古い環境では match_begun に落ちる。
globals.match_running = nil
globals.hotkeys_armed = nil
globals.game_state.match_begun = true
tick(4)
globals.game_state.match_begun = false
want("未公開なら match_begun を見る", tick(5), "match_not_running")

if fails == 0 then print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
