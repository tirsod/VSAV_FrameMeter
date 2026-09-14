-- VSAV CAMERA / TELEPORT INVESTIGATION PROBE (observation only).
-- Capture is armed by the existing Hotkey 2 + lever stage move. After that
-- move completes, this waits roughly 120 displayed frames, then records a
-- bounded trace. The wait is intentionally approximate, not gameplay timing.
-- Output: reversal_logs/camera_probe_<frame>.csv
local M = {}
local active = false
local fh = nil
local path = nil
local rows_since_flush = 0
local sequence = 0
local last_move_serial = 0
local wait_started_at = nil
local start_frame = nil
local WAIT_AFTER_MOVE = 120
local MAX_CAPTURE_FRAMES = 1800

local watched = {
  {0xFF8410,4,"p1_x"}, {0xFF8810,4,"p2_x"},
  {0xFF828C,4,"cand_028c"}, {0xFF8290,2,"left_screen_edge"},
  {0xFF82AC,4,"cand_02ac"}, {0xFF82C4,4,"cand_02c4"},
  {0xFF82CC,4,"cand_02cc"},
  {0xFFB810,2,"scroll_1"}, {0xFFB890,2,"scroll_2"},
  {0xFFB910,2,"scroll_3"}, {0xFFB990,2,"scroll_4"},
}

local function hex(v,digits)
  if v == nil then return "" end
  if v < 0 then v = v + 0x100000000 end
  return string.format("%0" .. tostring(digits or 8) .. "X",v)
end
local function read_value(a,n)
  if n == 1 then return memory.readbyte(a) end
  if n == 2 then return memory.readword(a) end
  return memory.readdword(a)
end
local function reg(name)
  local ok,v = pcall(memory.getregister,"m68000." .. name)
  if ok then return v end
  return nil
end
local function frame()
  -- The master updates globals.current_frame after this module runs. Reading it
  -- here would make the delay and CSV one frame stale, so use the emulator clock.
  return emu.framecount()
end
local function tick() return memory.readbyte(0xFF8081) end
local function emit(kind,name,addr,size,value,note)
  if not active or fh == nil then return end
  sequence = sequence + 1
  fh:write(table.concat({
    tostring(sequence),tostring(frame()),tostring(tick()),kind,name or "",
    hex(addr or 0,6),tostring(size or 0),hex(value or 0,(size or 4)*2),
    hex(reg("pc") or 0,6),hex(reg("a5") or 0,8),hex(reg("a6") or 0,8),
    hex(reg("d0") or 0,8),hex(reg("d1") or 0,8),hex(reg("d2") or 0,8),
    (note or ""):gsub("[\\r\\n,]"," ")
  },",") .. "\n")
  rows_since_flush = rows_since_flush + 1
  if rows_since_flush >= 256 then fh:flush(); rows_since_flush = 0 end
end
local function stop(reason)
  if not active then return end
  emit("STOP","",0,0,0,reason or "")
  active = false
  if fh ~= nil then fh:flush(); fh:close(); fh=nil end
  print("Camera probe stopped: " .. tostring(path))
end
local function start()
  path = "reversal_logs/camera_probe_" .. tostring(emu.framecount()) .. ".csv"
  fh = io.open(path,"w")
  if fh == nil then
    path = "scripts/camera_probe_" .. tostring(emu.framecount()) .. ".csv"
    fh = io.open(path,"w")
  end
  if fh == nil then print("Camera probe: cannot open output file") return end
  fh:write("seq,frame,tick,kind,name,address,size,value,pc,a5,a6,d0,d1,d2,note\n")
  active=true; sequence=0; rows_since_flush=0; start_frame=frame()
  emit("START","",0,0,0,"120 displayed frames after Hotkey 2 move")
  print("Camera probe started: " .. path)
end

for _,w in ipairs(watched) do
  local a,n,name=w[1],w[2],w[3]
  memory.registerwrite(a,n,function()
    emit("WRITE",name,a,n,read_value(a,n),"")
  end)
end

function M.registerBefore()
  local in_match = memory.readbyte(0xFF8009) == 4
  if positionModule ~= nil and positionModule.round_ready ~= nil then
    in_match = in_match and positionModule.round_ready()
  end
  if not in_match then
    wait_started_at = nil
    if active then stop("match ended") end
    return
  end

  local serial = 0
  if positionModule ~= nil and positionModule.hotkey_move_completed_serial ~= nil then
    serial = positionModule.hotkey_move_completed_serial()
  end
  if serial ~= last_move_serial then
    last_move_serial = serial
    wait_started_at = frame()
    if active then stop("new Hotkey 2 move") end
    print("Camera probe armed; capture starts in about 120 frames")
  end
  if not active and wait_started_at ~= nil and frame() - wait_started_at >= WAIT_AFTER_MOVE then
    wait_started_at = nil
    start()
  end
  if not active then return end

  sequence = sequence + 1
  local values = {}
  for _,w in ipairs(watched) do
    values[#values+1] = w[3] .. "=" .. hex(read_value(w[1],w[2]),w[2]*2)
  end
  fh:write(table.concat({tostring(sequence),tostring(frame()),tostring(tick()),
    "SAMPLE","all","000000","0","","000000","00000000","00000000",
    "00000000","00000000","00000000",table.concat(values,";")},",") .. "\n")
  rows_since_flush = rows_since_flush + 1
  if rows_since_flush >= 256 then fh:flush(); rows_since_flush = 0 end
  if frame() - start_frame >= MAX_CAPTURE_FRAMES then stop("capture limit") end
end
function M.guiRegister()
  if active then
    gui.text(2,2,"CAM PROBE REC",0xFFFF00FF,0x000000C0)
  elseif wait_started_at ~= nil then
    local left = WAIT_AFTER_MOVE - (frame() - wait_started_at)
    if left < 0 then left = 0 end
    gui.text(2,2,"CAM PROBE WAIT " .. tostring(left),0xFFFF00FF,0x000000C0)
  end
end
function M.stop() stop("manual") end
return M
