-- THE RANDOM SETTINGS AND THE GENERATOR BEHIND THEM.
--
-- Three defects found in one pass, all of the same kind - a number on the menu
-- that the code did not actually use:
--
--   * Guard Action Frequency said 25%/75% and rolled 35/65
--   * P2 Block Chance said 25%/75% and rolled 35/65
--   * math.randomseed was never called, so Lua 5.1's math.random (the C
--     library's rand(), seeded 1 when nobody says otherwise) produced the same
--     sequence on every launch. Measured: two runs of the same script both gave
--     0 2 0 4 2 2 1 4. The distribution was right and the sequence was
--     learnable, which for a training dummy is the same complaint.
--
-- Read from the source rather than executed: the point is that two files agree
-- about a number, and that a call exists at all. Both are things a later edit
-- can quietly break with no test failing anywhere else.
--
-- Run from scripts/ - the reads below are relative.
--   cd scripts && lua5.1 ../analysis/test_random_sources.lua
local fails = 0
local function fail(what, got, want)
	fails = fails + 1
	print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(want) .. "]")
end

local function slurp(path)
	local fh = io.open(path)
	assert(fh, path .. " が読めない")
	local s = fh:read("*a")
	fh:close()
	return s
end

local menu = slurp("menu.lua")

-- menu.lua の list を読む。"None" と "100%" 以外の数字が期待値。
local function menu_percents(name)
	local s = menu:find("\n" .. name .. " = {", 1, true)
	assert(s, name .. " が menu.lua に見つからない")
	local e = menu:find("\n}", s, true)
	local body = menu:sub(s, e)
	local out = {}
	for label in body:gmatch('"([^"]+)"') do
		out[#out + 1] = tonumber(label:match("^(%d+)%%$")) or (label == "None" and 0 or nil)
	end
	return out
end

-- 実装側の maybe(N) を、指定の関数の中から順に拾う。
local function impl_percents(path, fname)
	local src = slurp(path)
	local s = src:find("function " .. fname .. "(", 1, true)
	assert(s, fname .. " が " .. path .. " に見つからない")
	local e = src:find("\nend", s, true)
	local body = src:sub(s, e)
	local out = { 0 }                       -- 0x1 = None は常に false
	for n in body:gmatch("maybe%((%d+)%)") do out[#out + 1] = tonumber(n) end
	out[#out + 1] = 100                     -- 0x5 = 100% は常に true
	return out
end

local function compare(what, menu_name, path, fname)
	local want = menu_percents(menu_name)
	local got  = impl_percents(path, fname)
	local line = {}
	local ok = (#want == #got)
	for i = 1, math.max(#want, #got) do
		local a, b = got[i], want[i]
		if a ~= b then ok = false end
		line[#line + 1] = string.format("%s%s", tostring(b), (a == b) and "" or ("→" .. tostring(a)))
	end
	if ok then print("  ok " .. what .. "   " .. table.concat(line, " / ") .. " %")
	else fail(what, table.concat(line, " / "), "menu.lua と一致") end
end

print("[1] メニューの表記と実装の確率が一致するか")
compare("Guard Action Frequency", "gc_freq",         "guardCancel.lua", "shouldGC")
compare("P2 Block Chance",        "p2_block_chance", "autoguard.lua",   "get_block_chance")

print("[2] 乱数の種が撒かれているか")
local master = slurp("vsav_training_master_script.lua")
if not master:find("math.randomseed", 1, true) then
	fail("math.randomseed の呼び出し", "なし",
	     "vsav_training_master_script.lua に 1 つ")
else
	print("  ok vsav_training_master_script.lua が math.randomseed を呼んでいる")
end
-- 種を撒かない Lua 5.1 が何をするかを、この場で示しておく。
local a, b = {}, {}
math.randomseed(1)
for i = 1, 6 do a[i] = math.random(0, 4) end
math.randomseed(1)
for i = 1, 6 do b[i] = math.random(0, 4) end
if table.concat(a, " ") ~= table.concat(b, " ") then
	fail("同じ種なら同じ列になるはず", table.concat(a, " "), table.concat(b, " "))
else
	print("     参考: 種が同じなら列も同じ  [" .. table.concat(a, " ") .. "]")
end

print("[3] 毎フレーム引き捨てている場所が無いか")
-- dummy_guard の先頭に、代入するだけで誰も読まない get_block_chance() が
-- あった。読まれない抽選は分布を変えないが、生成器を毎フレーム進める。
local ag = slurp("autoguard.lua")
local dead = ag:match("function dummy_guard%b()%s*\n%s*local%s+([%w_]+)%s*=%s*get_block_chance%(%)")
if dead ~= nil then
	fail("dummy_guard の先頭で引き捨てている", "local " .. dead .. " = get_block_chance()", "なし")
else
	print("  ok dummy_guard の先頭に引き捨ての抽選は無い")
end
-- 実際に読まれる抽選は、攻撃 1 回につき 1 回ラッチされる形であること。
if not ag:find("if attack_flag and current_block_chance == nil then", 1, true) then
	fail("P2 Block Chance のラッチ", "見つからない", "攻撃ごとに 1 回")
else
	print("  ok P2 Block Chance は攻撃 1 回につき 1 回ラッチされる")
end

print("[4] ランダム再生のスロット選択が一様か")
-- get_playback_file は globals に絡んでいるので、選択そのものの式を見る。
local macro = slurp("macro.lua")
if not macro:find("math.random(0, numItems - 1)", 1, true) then
	fail("スロット選択の式", "見つからない", "math.random(0, numItems - 1)")
else
	print("  ok 有効なスロットから一様に 1 つ選んでいる")
end
-- playcontrol は毎フレームではなくイベントで呼ばれる。毎フレーム呼ばれる
-- 場所から呼ばれるようになったら、ここに気づける形にしておく。
local n_playcontrol = 0
for _ in macro:gmatch("playcontrol%(") do n_playcontrol = n_playcontrol + 1 end
print(string.format("     macro.lua 内の playcontrol( は %d 箇所(定義 1 + 呼び出し)", n_playcontrol))

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
