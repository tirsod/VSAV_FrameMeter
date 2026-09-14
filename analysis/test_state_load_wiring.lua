-- STATE LOAD HAS TO TAKE THE EDITOR DOWN WITH IT.
--
-- A load rewinds the game but not the Lua side. The load handler already
-- clears the menu flag and drops whatever the runner was delivering; the
-- editor was left open behind it, holding a draft keyed to a character the
-- loaded state may not have. Closing it there is one line, and one line is
-- exactly the kind of thing that gets dropped in a merge.
--
-- Read from the source rather than run: the handler is inside
-- savestate.registerload, and reaching it means standing up the whole
-- emulator API. What can be checked without that is that the call is there,
-- in that block, ahead of the runner's - the editor's abort must not run
-- after something else has already started tearing the delivery down.
--
--   cd C:/fightcaVSAV-Debug/emulator/fbneo && lua5.1 analysis/test_state_load_wiring.lua
local path = "scripts/vsav_training_master_script.lua"
local src = io.open(path)
assert(src, path .. " が読めない")
src = src:read("*a")

local fails = 0
local function want(what, got, w)
  if got ~= w then
    fails = fails + 1
    print("  NG " .. what .. "   got [" .. tostring(got) .. "]  want [" .. tostring(w) .. "]")
  else
    print("  ok " .. what)
  end
end

print("[1] ステートロードの中身")
local s = src:find("savestate.registerload(function(slot)", 1, true)
want("registerload が見つかる", s ~= nil, true)
-- The handler ends at the line that closes the registration.
local e = s and src:find("\n\tend)", s, true)
want("ブロックの終わりが見つかる", e ~= nil, true)

if s and e then
  local block = src:sub(s, e)
  local abort  = block:find("actionSequenceEditorModule.abort", 1, true)
  local cancel = block:find("actionSequenceRunnerModule.cancel", 1, true)
  want("エディタを閉じている", abort ~= nil, true)
  want("ランナーも止めている", cancel ~= nil, true)
  if abort and cancel then
    want("エディタが先", abort < cancel, true)
  end
end

print(fails == 0 and "\n全て通った" or ("\n" .. fails .. " 件 NG"))
os.exit(fails == 0 and 0 or 1)
