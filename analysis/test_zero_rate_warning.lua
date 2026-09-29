-- 0% の確率が、別の行で選んだものを止めているときに、それを言うか。
--
-- Guard と Guard Action Type は「何をするか」、Random Guard % と Random Guard
-- Action % は「どれだけの割合でするか」。後の 2 つはどちらも 0% で出荷して
-- いるので、All Guard やガードアクションを選んでも何も起きず、選んだことが
-- 効いていないとは画面のどこにも出ていなかった (PLAYER_UX_REVIEW 4)。
--
-- 値は変えない (0% が狙いのこともある)。言うだけ:
--   * 確率の行がオレンジになる (カーソルが無いとき)
--   * 関係する行にカーソルがあると、凡例の行の右側に理由が出る
-- 確率の行の表記は None ではなく 0% (PLAYER_UX_REVIEW 9)。
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_zero_rate_warning.lua
package.preload["./scripts/charMoves"] = function()
	return { get_player_movelists = function()
		return { P1 = { reversal_names = { "Stub" } }, P2 = { reversal_names = { "Stub" } } }
	end }
end
package.preload["./scripts/actionSequenceEditor"] = function()
	return dofile("actionSequenceEditor.lua")
end
package.preload["./scripts/actionSequenceRunner"] = function()
	return dofile("actionSequenceRunner.lua")
end
package.preload["./scripts/position"] = function()
	return dofile("position.lua")
end

training_settings = {}
globals = {}
memory = { readbyte = function() return 0 end }
gui = { text = function() end, box = function() end }
dofile("menu.lua")
menuModule.guiRegister()

local fails = 0
local function want(what, got, expected)
	if got == expected then
		print("  ok " .. what)
	else
		fails = fails + 1
		print("  NG " .. what)
		print("     got  [" .. tostring(got) .. "]")
		print("     want [" .. tostring(expected) .. "]")
	end
end

local function row(name)
	for _, tab in ipairs(menu) do
		for _, e in ipairs(tab.entries) do
			if e.name == name then return e, tab.name end
		end
	end
	return nil
end
-- 1 行を描いて、出た文字と色を返す。
local function drawn(e, selected)
	local got = nil
	gui.text = function(x, y, t, c) got = { t = t, c = c } end
	e:draw(33, 38, selected)
	gui.text = function() end
	return got
end
-- 凡例の行 (y=199) に右寄せで出る警告。右端 350 は menu.lua の
-- _menu_box_right - 10。
local function warning_on(e)
	local got = nil
	gui.text = function(x, y, t, c) got = { x = x, y = y, t = t, c = c } end
	draw_entry_warning(e, 350, 199)
	gui.text = function() end
	return got
end

local ORANGE = "#FF7F00"
local GUARD, ALL_GUARD, STAND, AUTO = "Guard", 4, 2, 3

print("[1] 名前と 0% - 3 つの確率の行")
local block, block_tab = row("Random Guard %")
local action, action_tab = row("Random Guard Action %")
local tech, tech_tab = row("Random Throw Tech %")
want("Random Guard % は Dummy タブ", block_tab, "Dummy")
want("Random Guard Action % は Dummy タブ", action_tab, "Dummy")
want("Random Throw Tech % は Dummy タブ", tech_tab, "Dummy")
for _, e in ipairs({ block, action, tech }) do
	want((e and e.name or "?") .. " の並び",
		e and table.concat(e.list, ","), "0%,25%,50%,75%,100%")
end
want("旧名は残っていない (P2 Random Guard %)", row("P2 Random Guard %"), nil)
want("旧名は残っていない (Guard Action Frequency)", row("Guard Action Frequency"), nil)
want("旧名は残っていない (Tech Throws)", row("Tech Throws"), nil)
want("Analysis の確認も新しい名前", select(2, row("Random Guard Action % Check")), "Analysis")
-- 保存されるのは添字。1 が 0% のまま、既定値も変わっていない。
local shipped = dofile("config.lua").default_training_settings
want("出荷値 gc_freq は 1 (0%)", shipped.gc_freq, 1)
want("出荷値 p2_block_chance は 1 (0%)", shipped.p2_block_chance, 1)

print("[2] Random Guard % - ガードを選んで 0% なら止まっていると言う")
local guard_row = row(GUARD)
training_settings.guard = ALL_GUARD
training_settings.p2_block_chance = 1
want("All Guard + 0%: 行がオレンジ", drawn(block, false).c, ORANGE)
want("All Guard + 0%: 値は 0%", drawn(block, false).t, "Random Guard % : 0%")
local w = warning_on(guard_row)
want("Guard の行で理由が出る", w and w.t, "Random Guard % is 0%: the dummy never blocks.")
want("理由はオレンジ", w and w.c, ORANGE)
want("理由は凡例の行", w and w.y, 199)
want("右寄せで枠内 (x + 幅 = 350)", w and (w.x + #w.t * 4), 350)
-- 凡例は "MP: Reset to default"。x=33 から 20 字 = 113 まで。重ならないこと。
want("凡例と重ならない", w ~= nil and w.x > 33 + #guard_row:legend() * 4 + 4, true)
want("確率の行でも同じ理由", warning_on(block) and warning_on(block).t, w and w.t)
want("カーソル下は選択色 (括弧と凡例の行が言う)", drawn(block, true).c ~= ORANGE, true)
training_settings.guard = STAND
want("Stand Block + 0% もオレンジ", drawn(block, false).c, ORANGE)
for _, g in ipairs({ 5, 6, 7 }) do
	training_settings.guard = g
	want("Push Block (" .. g .. ") + 0% もオレンジ", drawn(block, false).c, ORANGE)
end
training_settings.guard = ALL_GUARD
for _, v in ipairs({ 2, 3, 4, 5 }) do
	training_settings.p2_block_chance = v
	want("率 " .. v .. " ではオレンジにしない", drawn(block, false).c ~= ORANGE, true)
	want("率 " .. v .. " では理由を出さない", warning_on(guard_row), nil)
end
training_settings.p2_block_chance = 1
-- 確率を読まないガードでは、0% は何も止めていない。
for _, g in ipairs({ 1, AUTO }) do
	training_settings.guard = g
	want("Guard " .. g .. " では理由を出さない", warning_on(guard_row), nil)
end

print("[3] Random Guard Action % - ガードアクションを選んで 0% なら止まっていると言う")
local type_row = row("Guard Action Type")
training_settings.gc_freq = 1
for _, a in ipairs({ 2, 3, 6, 11, 12 }) do
	training_settings.guard_action = a
	want("Type " .. a .. " + 0%: 行がオレンジ", drawn(action, false).c, ORANGE)
	local _w = warning_on(type_row)
	want("Type " .. a .. " + 0%: Guard Action Type の行で理由",
		_w and _w.t, "Random Guard Action % is 0%: it never runs.")
end
local wa = warning_on(type_row)
want("右寄せで枠内", wa and (wa.x + #wa.t * 4), 350)
want("凡例と重ならない", wa ~= nil and wa.x > 33 + #type_row:legend() * 4 + 4, true)
want("確率の行でも同じ理由", warning_on(action) and warning_on(action).t, wa and wa.t)
training_settings.guard_action = 1
want("Type None では理由を出さない", warning_on(type_row), nil)
training_settings.guard_action = 2
for _, v in ipairs({ 2, 3, 4, 5 }) do
	training_settings.gc_freq = v
	want("率 " .. v .. " ではオレンジにしない", drawn(action, false).c ~= ORANGE, true)
	want("率 " .. v .. " では理由を出さない", warning_on(type_row), nil)
end

print("[4] 投げ抜けは警告しない - 0% は「投げを抜けない」という設定そのもの")
training_settings.p2_throw_tech = 1
want("Random Throw Tech % 0% はオレンジにしない", drawn(tech, false).c ~= ORANGE, true)
want("理由も出さない", warning_on(tech), nil)

print("[5] 実際の描画 - メニューの凡例の行から呼んでいる")
local src = io.open("menu.lua"):read("*a")
want("凡例の後で draw_entry_warning を呼ぶ",
	src:find("draw_entry_warning(menu[main_menu_selected_index].entries[sub_menu_selected_index],", 1, true) ~= nil, true)

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
