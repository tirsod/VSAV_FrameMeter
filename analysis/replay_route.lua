-- REPLAY A PROBE LOG THROUGH actionRoute, WITHOUT THE EMULATOR.
--
-- routeProbe writes one line per tick on which something changed. This reads
-- the log, fills the gaps back in (a value that did not change is a value that
-- was held), and feeds the result to the same state machine the tool runs. What
-- comes out is the row that would have been on screen - so a measurement can be
-- checked against reality at a desk.
--
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/replay_route.lua
--
-- Every session in the log is replayed in order. The probe appends, so picking
-- one would mean guessing which run was the interesting one; printing them all
-- is faster to read. A session boundary is the emulator being restarted, so the
-- measurement in flight is dropped there, exactly as it would be in the tool.
--
-- The probe's tick column is the raw $FF8081 byte and wraps at 256; the wrap is
-- undone here. The tool itself is fed a monotonic counter, so this is only the
-- log's problem.
package.path = "./?.lua;./?/init.lua;" .. package.path
local ar = require "scripts/actionRoute"

local LOG = "analysis/dash_probe.log"
local f = io.open(LOG)
if f == nil then print("読めない: " .. LOG) os.exit(1) end
local text = f:read("*a")
f:close()

local NL = string.char(10)
local rows = {}
local base, prev = 0, nil
for line in text:gmatch("[^" .. NL .. "]+") do
  if line:find("=== route probe", 1, true) then
    rows[#rows + 1] = { reset = true }
    base, prev = base + 512, nil
  end
  local t, rest = line:match("^t=%s*(%d+)%s+(.*)$")
  if t then
    t = tonumber(t)
    if prev ~= nil and t < prev then base = base + 256 end
    prev = t
    -- キーに _ が入るので %w では足りない。p1_05 が 05 になって潰れる。
    local r = { tick = base + t }
    for k, v in rest:gmatch("([%w_]+)=(%x+)") do r[k] = tonumber(v, 16) end
    rows[#rows + 1] = r
  end
end
print(string.format("%s から %d 行", LOG, #rows))

-- アダプタと同じ規則で名前と鍵を作る。ログには $06 $105 $102 $101 $106 が入って
-- いるので、実機と同じものが組める。必殺技の名前だけは charMoves が要るので、
-- ここでは id をそのまま出す。
local STRENGTH = { [0] = "L", [2] = "M", [4] = "H" }
local function button_name(r)
  return (STRENGTH[r["102"] or 0] or "?") .. (((r["101"] or 0) == 0) and "P" or "K")
end
local function move_name(r)
  local st = r.p1_06
  if st == 0x0A or (st == 0x06 and (r["105"] or 0) ~= 0) then
    return (STRENGTH[r["102"] or 0] or "?") .. (((r["101"] or 0) == 0) and "P" or "K")
  elseif st == 0x0E or st == 0x10 or st == 0x12 then
    return string.format("SP%02X", r["106"] or 0)
  end
  return nil
end
local function move_key(r)
  local st = r.p1_06
  if st == 0x0A or (st == 0x06 and (r["105"] or 0) ~= 0) then
    return 0x10000 + (r["102"] or 0) * 0x100 + (r["101"] or 0)
  elseif st == 0x0E or st == 0x10 or st == 0x12 then
    return 0x20000 + st * 0x100 + (r["106"] or 0)
  end
  return 0
end

-- tickDataVsav.lua と同じ規則。前後は画面上で逆に出たので両方 Walk。
local function stance(r)
  local st = r.p1_06
  if (r.air or 0) ~= 0 then return nil end
  if r.p1_05 ~= 0 then return nil end
  if st ~= 0x00 and st ~= 0x04 then return nil end
  local lever = r.lever or 0
  if math.floor(lever / 4) % 2 == 1 then return "Crouch" end
  if lever % 2 == 1 then return "Walk" end
  if math.floor(lever / 2) % 2 == 1 then return "Walk" end
  return nil
end

local function snapshot(r)
  return {
    tick = r.tick,
    p1 = {
      free = (r.p1_05 == 0 and r.p1_06 == 0),
      -- 歩きは $06 = 0x04 (2026-09-10 実測)。行動として扱わないのはアダプタと
      -- 同じで、レバー経由で stance に出る。
      stunned = r.p1_05 == 0x02,
      jump_state = r.p1_06 == 0x06,
      dash = r.p1_06 == 0x14,
      airborne = (r.air or 0) ~= 0,
      attack = r["105"] or 0,
      attack_box = (r.box or 0) ~= 0,
      cel = r.cel or 0,
      move_key = move_key(r), move_name = move_name(r),
      -- $1B8 は語。プローブはバイトで出すので、ここで組み直す。同じ技の 2 本目
      -- はこれでしか分からない (連打キャンセル)。
      attack_seq = ((r["1B8"] or 0) * 256) + (r["1B9"] or 0),
      button_name = button_name(r),
      -- レバーは 2026-09-09 からログに入っている。アダプタと同じ規則で組む:
      -- 地上で $06 が 0x00 か 0x04 のときだけ読み、下 > 前 > 後ろの順。
      stance = stance(r),
      action = (r.p1_06 == 0x06 or r.p1_06 == 0x0A or r.p1_06 == 0x0E
        or r.p1_06 == 0x10 or r.p1_06 == 0x12 or r.p1_06 == 0x14
        or r.p1_06 == 0x16),
    },
    p2 = { status = r.p2_05 or 0, block_clock = r.p2_158 or 0,
           hitstop = r.p2_5C or 0, guarding = false },
  }
end

-- PROBE は 4 ティックに 1 回取りこぼす。
--
-- routeProbe は emu.registerbefore で走るので描画フレームごと。ツール本体は
-- rawStateService の ticker で回っていて、turbo の 4 つ目 (描かれないティック)
-- も見ている。だからログでは 0x18 が 2 つ重なって 0x30 の 1 回に見えることが
-- あり、そのままだと「アニメが飛んだ」= 技の開始と読まれてしまう。
--
-- 埋めるティックの側でセルを 0x18 ずつ進め、本体が見ていたはずの形に戻す。
-- 数を作っているのではなく、取りこぼした分を戻しているだけ。
local CEL_SIZE = 0x18

-- 記録の無いティックは、直前の行がそのまま続いていたということ。
ar.reset("replay", true)
local shown, seen = 0, nil
for i = 1, #rows do
  local r = rows[i]
  if r.reset then
    ar.reset("session", false)
  else
    local nxt = rows[i + 1]
    local upto = (nxt and nxt.tick and (nxt.tick - 1)) or r.tick
    -- 次の行までにセルが 0x18 の倍数だけ進んでいるなら、その分は取りこぼした
    -- ティックで 1 コマずつ進んだということ。埋める側に配る。
    local steps = 0
    if nxt and nxt.cel and r.cel then
      local d = nxt.cel - r.cel
      if d > 0 and (d % CEL_SIZE) == 0 then
        local k = d / CEL_SIZE
        if k >= 2 and k <= (upto - r.tick + 1) then steps = k - 1 end
      end
    end
    for t = r.tick, upto do
      local s = snapshot(r)
      s.tick = t
      -- 末尾から steps 個のティックに 1 コマずつ配る。
      local from_end = upto - t
      if steps > 0 and from_end < steps then
        s.p1.cel = r.cel + (steps - from_end) * CEL_SIZE
      end
      ar.update(s)
      local out = ar.getResult()
      if out ~= nil and out ~= seen then
        seen = out
        shown = shown + 1
        print(string.format("%3d  %s", shown, ar.formatResult()))
      end
    end
  end
end
if shown == 0 then print("道筋は 1 本も出なかった") end
