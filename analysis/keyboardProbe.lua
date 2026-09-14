-- IS THE PC KEYBOARD READABLE FROM LUA, ON THIS EMULATOR?
--
-- input.get() returns the keyboard (and mouse) state in the FBNeo Lua API, and
-- the sibling project fbneo-training-mode reads it that way
-- (fbneo-training-mode.lua:1276, "check every button", skipping xmouse/ymouse).
-- Nothing in THIS tool uses it, and the tool runs on fcadefbneo rather than
-- stock FBNeo, so whether it works here is unmeasured.
--
-- It matters because it decides how Action Patterns can be shared. With a
-- keyboard a name can be typed, and a typed name means a shared file does not
-- have to live in one of a handful of fixed slots. Without one, fixed slots are
-- the only option - Lua 5.1 here has no way to list a directory.
--
-- Run INSTEAD of the training script:
--   analysis/run_keyboard_probe.bat        (double click)
--
-- What to do, with the emulator window focused:
--   1. press a few letters - A, B, C
--   2. press Enter, Backspace, Escape, Shift, Ctrl
--   3. type a short word and watch whether every letter appears
--   4. move the mouse over the window
--
-- What to look for on screen:
--   "keys:" lists what is held right now. If it stays empty while typing, the
--   keyboard is not readable here and the answer is no.
--   "typed:" is the word built from key presses, which is the thing a name
--   entry would actually need.
local typed = ""
local held = {}
local seen_any = false
local frames = 0
local mouse = "none"

-- Held-to-pressed, so a key does not repeat sixty times a second.
local was = {}

emu.registerbefore(function()
	frames = frames + 1
	local ok, state = pcall(input.get)
	if not ok or type(state) ~= "table" then
		held = { "input.get() が使えない" }
		return
	end
	held = {}
	local now = {}
	for k, v in pairs(state) do
		if k == "xmouse" or k == "ymouse" then
			mouse = tostring(state.xmouse) .. "," .. tostring(state.ymouse)
		elseif v then
			seen_any = true
			now[k] = true
			held[#held + 1] = tostring(k)
			if not was[k] then
				-- One character per press. Anything longer than one character
				-- is a named key (enter, backspace, shift...) and is shown as
				-- <name> so the two cases can be told apart.
				if #tostring(k) == 1 then
					typed = typed .. tostring(k)
				elseif k == "backspace" then
					typed = string.sub(typed, 1, #typed - 1)
				else
					typed = typed .. "<" .. tostring(k) .. ">"
				end
				if #typed > 60 then typed = string.sub(typed, #typed - 59) end
			end
		end
	end
	was = now
end)

gui.register(function()
	gui.text(8, 8, "keyboard probe   frames " .. tostring(frames))
	gui.text(8, 18, "keys: " .. (table.concat(held, " ") ~= "" and table.concat(held, " ") or "(none)"))
	gui.text(8, 28, "typed: " .. typed)
	gui.text(8, 38, "mouse: " .. mouse)
	gui.text(8, 48, seen_any and "READABLE - a key has been seen" or "nothing seen yet")
end)
