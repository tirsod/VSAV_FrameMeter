-- "HAS THIS PLAYER CHOSEN A CHARACTER YET", INCLUDING WHEN THEY CHOSE BULLETA.
--
-- The arcade-stick mirror and the stage cursor both ask this. They used to ask
-- it of $3BD alone, which is the character id - and Bulleta is 0x00, so she
-- answered the same as an empty slot. Control never passed to P2 for her, and
-- for nobody else, because she is the only character numbered zero.
--
-- The numbers below are from analysis/select_probe.log (2026-09-12): both
-- players' $3E1 read 0x00 until each locked in, then P1 read 0x01 having taken
-- Demitri and P2 read 0x03 having taken Bishamon.
--
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_char_chosen.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return ram[a] or 0 end,
	readdword = function(a) return ram[a] or 0 end,
	writebyte = function(a, v) ram[a] = v end,
}
emu = { framecount = function() return 0 end }
gui = { text = function() end }

local util = dofile("scripts/utilities.lua")
local P1, P2 = 0xFF8400, 0xFF8800

local fails = 0
local function want(what, got, w)
	if got ~= w then
		fails = fails + 1
		print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
	else
		print("  ok " .. what)
	end
end

local function clear()
	ram[P1 + 0x3BD], ram[P1 + 0x3E1] = 0, 0
	ram[P2 + 0x3BD], ram[P2 + 0x3E1] = 0, 0
end

clear()
want("誰も選んでいない", util.char_chosen(P1), false)

-- 実測: デミトリを選んだ P1 は $3BD=01 $3E1=01。
ram[P1 + 0x3BD], ram[P1 + 0x3E1] = 0x01, 0x01
want("デミトリを選んだ", util.char_chosen(P1), true)
want("相手はまだ選んでいない", util.char_chosen(P2), false)

-- 実測: ビシャモンを選んだ P2 は $3BD=08 $3E1=03。$3E1 は id ではない。
ram[P2 + 0x3BD], ram[P2 + 0x3E1] = 0x08, 0x03
want("ビシャモンを選んだ", util.char_chosen(P2), true)

-- これが直したかったもの。バレッタは id 0x00 なので $3BD は 0 のまま。
clear()
ram[P1 + 0x3BD], ram[P1 + 0x3E1] = 0x00, 0x01
want("バレッタを選んでも選択済みと分かる", util.char_chosen(P1), true)

-- 逆側も成り立つこと。$3E1 が 0 でも $3BD が立っていれば選択済み - 今まで
-- 動いていた経路を落とさないための条件。
clear()
ram[P1 + 0x3BD] = 0x0A
want("$3E1 が無くても $3BD で分かる", util.char_chosen(P1), true)

-- 片側だけ選んでいる状態。ミラーはこの形のときだけ働く。
clear()
ram[P1 + 0x3BD], ram[P1 + 0x3E1] = 0x00, 0x01
want("バレッタの P1 は選択済み", util.char_chosen(P1), true)
want("P2 は未選択のまま", util.char_chosen(P2), false)

if fails == 0 then print("全て通った") else print(fails .. " 件 NG") os.exit(1) end
