-- RECORDING WIZARD (Stage A).
-- Spec: MUSE_VSAV_RECORDING_WIZARD_IMPLEMENTATION_SPEC.md (retargeted to
-- v11.3.3). Guided dummy recording: pick a slot, control switches to P2, the
-- recording starts on the first game input, and it auto-stops after 120 frames
-- of the dummy standing free with nothing held (2 seconds). The recording is
-- then played back once on P2 - with control already handed to P1 and both
-- characters put back where they started - and only saved over the chosen slot
-- if the user confirms. No savestate capture yet.
--
-- Lua key 1 cancels the wizard from any state; the hotkey only raises a flag
-- and the teardown runs on the wizard's own frame.
--
-- Deliberate deviations from the spec, both recorded here:
--  * During ARMED, MP does NOT cancel. MP is a valid recording input (spec
--    6.1) and letting it cancel would make moves starting with MP
--    unrecordable. ARMED has no timeout - it waits for the first input, and
--    Lua key 1 is the way out.
--  * The wizard waits for one fully neutral frame after the control switch
--    before arming, so the LP press that opened the wizard can never be
--    counted as the first recording input.
-- Slot entries show when each slot was recorded, read from the .mis header.
-- Frame counts would need a segment parse and are cosmetic.

-- Recording ends after this many frames of the dummy standing free with
-- nothing held. Counting only free frames matters: a long move leaves the
-- pad neutral while the character is still committed, and counting those
-- would cut the recording off in the middle of its own recovery.
local AUTO_STOP_NEUTRAL_FRAMES = 120
local RESULT_FLASH_FRAMES = 180

-- Breathing room after the slot is confirmed, before the wizard will look at
-- the pad at all. The pad stays masked for its whole length, so it also
-- covers letting go of the confirming LP. Half a second, the same wait that
-- reads well on the character-select mirror.
local ARM_SETTLE_FRAMES = 30

-- Wait before the slot list will look at the pad, and before the players are
-- handed back to the game. The menu disables both players when it opens, and
-- the wizard used to re-enable them the instant it started - with the LP that
-- launched it still held, so P2 threw a jab the moment it came back. The pad
-- is masked for the whole wait, so the press is long gone by the time the
-- characters can act on anything.
local SELECT_GRACE_FRAMES = 30

-- Short settle before the save prompt accepts an answer, so an input left
-- over from the playback cannot answer it by accident.
local CONFIRM_GRACE_FRAMES = 20

-- How long the result sits on screen after a save before the slot list comes
-- back. Long enough to read which slot it went to, short enough that filling
-- several slots in a row does not feel like waiting.
local SAVED_HOLD_FRAMES = 60

-- Left edge shared by the slot list's heading, rows and hints.
local SELECT_LEFT = 112

-- The save prompt's three choices, in cursor order.
-- Title Case, to agree with the main menu and the sequence editor. The
-- wizard was the only screen still writing its commands as sentences.
local CONFIRM_ITEMS = { "Save to This Slot", "Record Again", "Play Again" }

-- Character X, a 16.16 value: integer half at $10, fraction at $12. Same
-- layout position.lua works on (position.lua:33-35), but its accessors are
-- local to that module, so the two words are read and written here directly.
-- Both halves are kept, and the raw words are written back unchanged, so the
-- restore is exact and needs no sign handling.
local P1_BASE, P2_BASE = 0xFF8400, 0xFF8800
local X_OFF = 0x10
-- Facing byte, the same one autoguard/guardCancel/dummyState read.
local FACE_OFF = 0x0B

-- The ten game inputs by pad-name suffix, for masking both sides at once.
local PAD_SUFFIX = {
	"Up", "Down", "Left", "Right",
	"Weak Punch", "Medium Punch", "Strong Punch",
	"Weak Kick", "Medium Kick", "Strong Kick",
}

-- The ten recording-relevant inputs, as { display name, pad name in the
-- swapped input table }. Coin/Start/Volume/hotkeys are never valid wizard
-- inputs (spec 6.1).
--
-- These are read from globals._input, NOT from player_objects[2].input:
-- controller.registerBefore swaps P1<->P2 inside globals._input
-- (controller.lua:945), but playerObject.update_input then calls joypad.get()
-- a second time (playerObject.lua:81), which returns the RAW ports and so
-- discards that swap. While the wizard holds control at P2 the user's pad is
-- physically P1, so it reaches the game only through the swapped table -
-- player_objects[2] would show the idle P2 port instead and no amount of
-- stick movement would ever satisfy the start condition.
local P2_PAD_KEYS = {
	{ "up",    "P2 Up" },
	{ "down",  "P2 Down" },
	{ "left",  "P2 Left" },
	{ "right", "P2 Right" },
	{ "LP",    "P2 Weak Punch" },
	{ "MP",    "P2 Medium Punch" },
	{ "HP",    "P2 Strong Punch" },
	{ "LK",    "P2 Weak Kick" },
	{ "MK",    "P2 Medium Kick" },
	{ "HK",    "P2 Strong Kick" },
}

local state = "IDLE"          -- IDLE / SELECT_SLOT / ARMED / RECORDING /
                              -- FINALIZING / PREVIEW / CONFIRM / SAVED_HOLD
local slot_cursor = 1         -- 1..5, or BACK_ROW
local BACK_ROW = 6            -- the "Back to menu" row under the slots
local confirm_cursor = 1      -- 1..3, the save prompt
local chosen_slot = nil
local arm_frames = 0
local arm_settled = false     -- one fully neutral frame seen since entering ARMED
local neutral_frames = 0
local raw_frames = 0
local grace_frames = 0        -- input grace right after leaving the menu
local saved_pos = nil         -- {P1 int, P1 frac, P2 int, P2 frac} X, from ARMED
local saved_cam = nil         -- the camera at ARMED, restored with the pair
local pending_restore = nil   -- queued for the frame phase that can carry it
local confirm_armed = false   -- the answering buttons have been seen released
local rec_facing = nil        -- P2 facing byte at ARMED, for the playback mirror
local cancel_requested = false -- raised by Lua key 1, acted on next wizard frame
local preview_started = false -- the confirmation playback has been kicked off
local mask_until_release = false -- swallow P1 until the answering button is let go
local players_enabled = false -- the menu's disable has been lifted again
local saved_slot = nil        -- slot named in the result message
local slot_labels = {}        -- per-slot capture stamp, read when the wizard opens
local flash_msg = nil
local flash_timer = 0

local function macro()
	return globals and globals.macroLua or nil
end

local function macro_path()
	local p = path or ".\\macro\\"
	return (p:gsub("\\", "/"))
end

local function char_prefix()
	local o = globals and globals.options
	if o and o.use_character_specific_slots and globals.dummy and globals.dummy.p2_char then
		return globals.dummy.p2_char
	end
	return ""
end

local function slot_file(slot)
	return macro_path() .. char_prefix() .. "/slot_" .. slot .. ".mis"
end

-- When the slot was recorded, taken from the header finalize() writes:
-- "# <romname> <os.date()>". os.date() follows the system locale, so the
-- stamp is whatever sits after the rom name and is shown verbatim - existing
-- slots carry "1/10/2021 11:13:42 AM" while new ones read "2026/08/26
-- 21:05:49". Falls back to "Saved" for a file with no readable header.
-- Old slots were written under a locale that used 12-hour time, so one row
-- read "11:59:21 PM" while the rest read "21:05:49" - the odd one out in the
-- list. Folded into 24-hour rather than just dropping the suffix, which would
-- have made 11:59 PM indistinguishable from 11:59 AM.
local function to_24h(stamp)
	local h, rest, ap = stamp:match("(%d+)(:%d+:?%d*)%s*([AaPp])[Mm]")
	if h == nil then return stamp end
	h = tonumber(h)
	if ap:lower() == "p" and h < 12 then h = h + 12 end
	if ap:lower() == "a" and h == 12 then h = 0 end
	return (stamp:gsub("%d+:%d+:?%d*%s*[AaPp][Mm]", string.format("%02d", h) .. rest))
end

local function slot_stamp(slot)
	local f = io.open(slot_file(slot), "r")
	if f == nil then return "Empty" end
	local first = f:read("*l")
	f:close()
	local body = first ~= nil and first:match("^#%s*(.-)%s*$") or nil
	if body == nil or body == "" then return "Saved" end
	return to_24h(body:match("^%a[%w_]*%s+(.+)$") or body)
end

-- Read once when the wizard opens rather than every frame: the slot list is
-- redrawn 60 times a second and this opens five files.
local function refresh_slot_labels()
	slot_labels = {}
	for i = 1, 5 do slot_labels[i] = slot_stamp(i) end
end

-- Names of the inputs currently held on the P2 side of the swapped table.
local function p2_held_inputs()
	local held = {}
	local inp = globals and globals._input
	if inp == nil then return held end
	for _, kv in ipairs(P2_PAD_KEYS) do
		if inp[kv[2]] then held[#held + 1] = kv[1] end
	end
	return held
end

local function p2_has_valid_input()
	return #p2_held_inputs() > 0
end

-- Standing neutral and out of stun. $05 is non-zero through hit/block stun
-- and knockdown (debugKnockdown calls it "hurt"); $06 is the action id, where
-- guardCancel reads 0x14 as a dash and 0x04 as the actionable wake-up
-- sub-state, and dummyState treats 0x00 as the stance a guard comes out of.
local function p2_is_free()
	return memory.readbyte(P2_BASE + 0x05) == 0 and memory.readbyte(P2_BASE + 0x06) == 0
end

local function flash(msg)
	flash_msg = msg
	flash_timer = RESULT_FLASH_FRAMES
end

-- The menu disables both players when it opens (togglemenu). The wizard closes
-- the menu WITHOUT going through togglemenu, so the enable side has to be done
-- here or the game ignores every input and the dummy never moves. Held back
-- until the launch wait is over: doing it immediately handed the characters
-- back while the launching LP was still down, and P2 threw a jab.
-- Back to the menu the wizard was opened from. Goes through togglemenu so the
-- players are disabled the way an open menu expects - setting show_menu on its
-- own would leave the two live behind it.
local function back_to_menu()
	if globals.menuModule ~= nil and globals.menuModule.togglemenu ~= nil
	   and globals.show_menu ~= true then
		globals.menuModule.togglemenu()
	end
end

local function enable_players_once()
	if players_enabled then return end
	players_enabled = true
	if globals.controllerModule ~= nil and globals.controllerModule.enable_both_players ~= nil then
		globals.controllerModule.enable_both_players()
	end
end

-- Both characters' X, captured when the wizard arms and written back when it
-- finishes, so the recording is always replayed from the spacing it was made
-- at. Y is deliberately not touched: a recording that ends in the air would
-- otherwise be restored to a mid-jump height with no jump under it.
local function capture_positions()
	saved_pos = {
		memory.readword(P1_BASE + X_OFF),     memory.readword(P1_BASE + X_OFF + 2),
		memory.readword(P2_BASE + X_OFF),     memory.readword(P2_BASE + X_OFF + 2),
	}
	rec_facing = memory.readbyte(P2_BASE + FACE_OFF)
	-- The exact framing, not one worked out from the positions. They agree
	-- here - the pair has been standing still since ARMED, so the camera has
	-- caught up - but the recorded value is the one that was actually on
	-- screen, and it costs nothing to keep it.
	local pm = positionModule
	if pm ~= nil and pm.camera_read ~= nil then saved_cam = pm.camera_read() end
end

-- Deliberately keeps saved_pos: the replay button restores the same spacing
-- again, so it is only dropped when the wizard ends.
--
-- WHY THIS ONLY QUEUES.
--
-- The wizard's state machine runs from guiRegister, which is the drawing
-- phase - after the frame's game logic has already run. Writing the camera
-- there tore the background permanently, while the same four words written
-- from registerBefore survived a jump of the entire stage width. The values
-- are identical; only the phase differs, and the game's own drawing origin is
-- evidently updated in step with the camera during its logic, not after it.
--
-- So the restore is put on a queue here and carried out by apply_restore
-- below, which runs from mask_input - called every frame, before the frame
-- runs, whatever state the wizard is in.
--
-- The values are copied rather than read again later, so cleanup() can drop
-- saved_pos immediately afterwards the way it always has.
local function restore_positions()
	if saved_pos == nil then
		return
	end
	pending_restore = { saved_pos[1], saved_pos[2], saved_pos[3], saved_pos[4], saved_cam }
end

-- Runs before the frame, from mask_input. positionModule.registerBefore has
-- already taken this frame's step by then.
local function apply_restore()
	if pending_restore == nil then return end
	-- The round has to be running for any of this to mean anything. If it is
	-- not, the scene being restored to is gone and the queue is dropped.
	if globals == nil or globals.hotkeys_armed ~= true then
		pending_restore = nil
		return
	end
	local r = pending_restore
	local pm = positionModule

	if pm == nil or pm.camera_restore_start == nil then
		-- No module: put them back the blunt way rather than not at all.
		memory.writeword(P1_BASE + X_OFF,     r[1])
		memory.writeword(P1_BASE + X_OFF + 2, r[2])
		memory.writeword(P2_BASE + X_OFF,     r[3])
		memory.writeword(P2_BASE + X_OFF + 2, r[4])
		pending_restore = nil
		return
	end

	if not r.started then
		r.started = true
		pm.camera_restore_start(r[5], r[1], r[2], r[3], r[4])
	end
	-- The camera moves at most 16 pixels a frame - one tile, which is all the
	-- background can be drawn in - so a restore across the stage takes about
	-- two dozen frames.
	if pm.camera_restore_busy ~= nil and pm.camera_restore_busy() then return end

	pending_restore = nil
end

-- Recorded input is absolute stick direction, so it only reproduces the same
-- move while P2 faces the way it faced when recorded. If it is facing the
-- other way at playback time, left and right have to be swapped.
-- REPLAYING NEEDS A DUMMY THAT CAN ACT.
--
-- A recording is trimmed to its last input, so the playback ends with the
-- character still committed to whatever that input started. Replaying from
-- there restarts against a dummy that cannot act and reproduces nothing.
--
-- No frame count: a move takes as long as it takes, and a number chosen to
-- cover the longest one seen so far is a number that cuts the next one short.
-- $05 is non-zero through stun and knockdown, $06 is the action id.
local function replay_ready()
	return memory.readbyte(P2_BASE + 0x05) == 0
	   and memory.readbyte(P2_BASE + 0x06) == 0
end

local function preview_flip()
	if rec_facing == nil then return false end
	return memory.readbyte(P2_BASE + FACE_OFF) ~= rec_facing
end

-- Always back to P1. Split out of cleanup() because the preview needs it
-- early: the recording plays back on P2 while the user watches from P1.
--
-- It used to put the target back wherever it was found. That bookkeeping was
-- itself a bug source once the wizard began looping back to the slot list -
-- the saved value was cleared by the first take, so the second one had nothing
-- to restore and left the pad on the dummy. The wizard is a P1-side tool, so
-- P1 is simply where it finishes.
local function restore_control()
	if globals.controllerModule ~= nil and globals.controllerModule.set_controlling_target ~= nil then
		globals.controllerModule.set_controlling_target("P1")
	end
end

-- Copy the temp recording over the chosen slot. Only reached from CONFIRM,
-- so nothing is overwritten until the user has seen the playback and said
-- yes.
local function commit_slot(slot)
	local ml = macro()
	local st = ml ~= nil and ml.get_recording_status ~= nil and ml.get_recording_status() or nil
	local temp_name = (st ~= nil and st.temp_name) or "wizard_temp.mis"
	local fin = io.open(macro_path() .. temp_name, "rb")
	if fin == nil then return false end
	local data = fin:read("*a")
	fin:close()
	if data == nil or data == "" then return false end
	local fout = io.open(slot_file(slot), "wb")
	if fout == nil then return false end
	fout:write(data)
	fout:close()
	return true
end

-- The wizard owns the inputs until the recording can legitimately begin.
-- Without this the LP that confirms the slot reaches the game on the same
-- frame and P1 punches the dummy. Masking covers slot selection and the
-- pre-latch part of ARMED - exactly the span where the user is being asked
-- to let go of everything - and stops the moment the latch is set, so the
-- first real input both starts and is recorded normally.
local function p1_holding_anything()
	local p1 = player_objects and player_objects[1]
	if p1 == nil or p1.input == nil or p1.input.down == nil then return false end
	for _, kv in ipairs(P2_PAD_KEYS) do
		if p1.input.down[kv[1]] then return true end
	end
	return false
end

local function mask_input(_input)
	-- Here rather than in guiRegister: this is called every frame, before the
	-- frame runs, whatever state the wizard is in. Both the restore and its
	-- samples need that - the restore because the drawing origin only takes a
	-- new camera cleanly at this point in the frame, the samples because a
	-- restore that ends the wizard would otherwise lose every one due after it.
	apply_restore()
	if _input == nil then return end
	-- CONFIRM is masked too, or the LP that answers "save?" also throws a
	-- punch. PREVIEW is deliberately left open so the playback can be blocked
	-- or countered while it is being checked.
	if state == "SELECT_SLOT" or state == "CONFIRM"
	   or (state == "ARMED" and not arm_settled) then
		for _, suffix in ipairs(PAD_SUFFIX) do
			_input["P1 " .. suffix] = false
			_input["P2 " .. suffix] = false
		end
		return
	end
	-- Answering the prompt moves the wizard on immediately, but the button is
	-- still physically down for a few more frames - and the state it moved to
	-- does not mask. Without this the LP/MP/LK that answered lands in the game
	-- one frame later and whichever side holds control punches or kicks. Both
	-- sides are cleared because control can sit on either; the playback is
	-- merged after this runs, so it is not affected.
	if mask_until_release then
		if p1_holding_anything() then
			for _, suffix in ipairs(PAD_SUFFIX) do
				_input["P1 " .. suffix] = false
				_input["P2 " .. suffix] = false
			end
		else
			mask_until_release = false
		end
	end
end

local function cleanup(reason)
	local ml = macro()
	if ml ~= nil and ml.get_recording_status ~= nil then
		local st = ml.get_recording_status()
		if st.recording then
			-- A cancel must not leave a file behind. stop_ is the completion
			-- path and always finalizes, so cancelling goes through the
			-- discard entry point instead.
			if reason == "cancelled" and ml.cancel_temporary_recording ~= nil then
				ml.cancel_temporary_recording()
			elseif ml.stop_temporary_recording ~= nil then
				ml.stop_temporary_recording()
			end
		end
		if st.playing and ml.stop_macro_playback ~= nil then ml.stop_macro_playback() end
	end
	if ml ~= nil and ml.end_temporary_playback ~= nil then ml.end_temporary_playback() end
	restore_control()
	-- Put both characters back where they stood when the wizard armed. Done
	-- on every exit, not just the saved one, so a cancel also leaves the
	-- match exactly as it was found. Both restores are no-ops if the preview
	-- path already ran them.
	restore_positions()
	saved_pos = nil
	saved_cam = nil
	rec_facing = nil
	-- Cancelling during the launch wait would otherwise leave the menu's
	-- disable in place with no menu open to lift it.
	enable_players_once()
	state = "IDLE"
	arm_frames, neutral_frames, raw_frames = 0, 0, 0
	arm_settled = false
	grace_frames = 0
	preview_started = false
	if reason == "interrupted" then flash("RECORDING WAS INTERRUPTED - DISCARDED")
	elseif reason == "empty" then flash("RECORDING WAS EMPTY - DISCARDED")
	elseif reason == "cancelled" then flash("RECORDING CANCELLED")
	elseif reason == "write_failed" then flash("COULD NOT WRITE SLOT " .. tostring(saved_slot))
	elseif reason == "error" then flash("RECORDING WIZARD ERROR")
	end
	saved_slot = nil
end

local function start()
	-- The log is appended to across sessions, so mark where each run begins.
	if state ~= "IDLE" then return end
	-- Anything already playing has to stop: it would drive P2 through the
	-- whole wizard, so the dummy would never be still and the recording would
	-- capture a fight with a macro instead of a clean take.
	local ml = macro()
	if ml ~= nil and ml.get_recording_status ~= nil then
		local st = ml.get_recording_status()
		if st.playing then
			if ml.stop_macro_playback ~= nil then ml.stop_macro_playback() end
			if ml.end_temporary_playback ~= nil then ml.end_temporary_playback() end
		end
	end
	slot_cursor = 1
	refresh_slot_labels()
	mask_until_release = false
	grace_frames = SELECT_GRACE_FRAMES
	players_enabled = false
	state = "SELECT_SLOT"
	globals.show_menu = false
end

local function shutdown()
	-- Script exit path: restore control, drop an in-flight recording, no flash.
	if state == "IDLE" then return end
	local ml = macro()
	if ml ~= nil and ml.get_recording_status ~= nil then
		local st = ml.get_recording_status()
		if st.recording and ml.stop_temporary_recording ~= nil then ml.stop_temporary_recording() end
	end
	if globals.controllerModule ~= nil and globals.controllerModule.set_controlling_target ~= nil then
		globals.controllerModule.set_controlling_target("P1")
	end
	state = "IDLE"
	arm_frames, neutral_frames, raw_frames = 0, 0, 0
	arm_settled = false
	grace_frames = 0
	preview_started = false
end

local function is_active()
	return state ~= "IDLE"
end

-- Lua key 1. Raise a flag only: the teardown runs on the wizard's own frame.
local function request_cancel()
	if state == "IDLE" then return end
	cancel_requested = true
end

-- The result message outlives the wizard: cleanup() drops the state to IDLE,
-- and from that frame on the master draws the normal menu path instead of the
-- wizard. Drawn from there too, or COMPLETE / CANCELLED would be set and then
-- never appear on screen.
-- gui.text draws one fixed size, so a heading cannot simply be set larger.
-- Striking it twice a pixel apart thickens every stroke, which is what reads
-- as "bigger" at this resolution, and a second pass one pixel down squares
-- off the letterforms without smearing them.
local function heading(x, y, text, color)
	gui.text(x, y, text, color)
	gui.text(x + 1, y, text, color)
	gui.text(x, y + 1, text, color)
end

local function draw_flash()
	if flash_timer > 0 then
		flash_timer = flash_timer - 1
		gui.text(100, 30, flash_msg, "#00FF00")
		if flash_timer == 0 then flash_msg = nil end
	end
end

local function guiRegister()
	draw_flash()
	if state == "IDLE" then
		cancel_requested = false
		return
	end
	-- Lua key 1 asks to cancel. The hotkey callback only raises the flag -
	-- doing the work inside the callback itself once killed the hotkey - so
	-- the actual teardown happens here, on the wizard's own frame.
	if cancel_requested then
		cancel_requested = false
		mask_until_release = true
		cleanup("cancelled")
		back_to_menu()
		return
	end
	-- Only the wizard's own preview may drive P2 while it is running. The
	-- playback hotkey stays live during the wizard, so whatever it starts is
	-- stopped again here rather than being left to fight the recording.
	if state ~= "PREVIEW" then
		local _ml = macro()
		if _ml ~= nil and _ml.get_recording_status ~= nil then
			local _st = _ml.get_recording_status()
			if _st.playing then
				if _ml.stop_macro_playback ~= nil then _ml.stop_macro_playback() end
				if _ml.end_temporary_playback ~= nil then _ml.end_temporary_playback() end
			end
		end
	end

	local p1 = player_objects and player_objects[1]

	if state == "SELECT_SLOT" then
		-- One left edge for the heading, the rows and the hints. The cursor
		-- markers sit in a two-character gutter that every row reserves,
		-- selected or not - wrapping only the selected row in "< >" pushed it
		-- out to the left of the others and the column read as crooked.
		-- Sits directly above the list. The other screens put their heading at
		-- 38 with the body at 60; this list starts at 78, so the same heading
		-- height left a three-line hole between the two.
		heading(SELECT_LEFT, 58, "SELECT RECORDING SLOT", "#FFFF00")
		for i = 1, 5 do
			local label = "Slot " .. i .. " : " .. (slot_labels[i] or "Empty")
			local _sel = (i == slot_cursor)
			gui.text(SELECT_LEFT, 62 + i * 16,
				(_sel and "< " or "  ") .. label .. (_sel and " >" or ""),
				_sel and "#00FF00" or "#FFFFFF")
		end
		-- Set apart from the slots by a gap: it leaves rather than chooses.
		local _back = (slot_cursor == BACK_ROW)
		gui.text(SELECT_LEFT, 164,
			(_back and "< " or "  ") .. "Back to menu" .. (_back and " >" or ""),
			_back and "#00FF00" or "#FFFFFF")
		gui.text(SELECT_LEFT, 184, "  LP / Right: Choose   MP: Cancel", "#AAAAAA")
		gui.text(SELECT_LEFT, 196, "  Lua key 1 : Cancel wizard", "#AAAAAA")
		if grace_frames > 0 then
			grace_frames = grace_frames - 1
			-- Hand the characters back only once the launching press is over.
			if grace_frames == 0 then enable_players_once() end
			return
		end
		if p1 ~= nil and p1.input ~= nil and p1.input.pressed ~= nil then
			if p1.input.pressed.up and slot_cursor > 1 then slot_cursor = slot_cursor - 1 end
			if p1.input.pressed.down and slot_cursor < BACK_ROW then slot_cursor = slot_cursor + 1 end
			-- Right goes in as well as LP, the way it does in the menu.
			-- input.pressed is edge-only, so a held direction cannot repeat
			-- here the way it can on the menu's autofire.
			if (p1.input.pressed.LP or p1.input.pressed.right) and slot_cursor == BACK_ROW then
				mask_until_release = true
				cleanup("closed")
				back_to_menu()
				return
			elseif p1.input.pressed.LP or p1.input.pressed.right then
				chosen_slot = slot_cursor
				if globals.controllerModule ~= nil and globals.controllerModule.set_controlling_target ~= nil then
					globals.controllerModule.set_controlling_target("P2")
				end
				arm_frames = 0
				arm_settled = false
				grace_frames = ARM_SETTLE_FRAMES
				capture_positions()
				state = "ARMED"
			elseif p1.input.pressed.MP then
				cleanup("cancelled")
			end
		end

	elseif state == "ARMED" then
		arm_frames = arm_frames + 1
		-- arm_settled LATCHES on the first fully neutral frame and is never
		-- cleared again. Clearing it whenever an input is held made the start
		-- condition below unsatisfiable: a frame with input cleared the latch
		-- immediately before the check that requires both the latch and an
		-- input, and a frame without input satisfied the latch but had no
		-- input to start on. The latch exists only so the LP that chose the
		-- slot cannot be read as the first recording input.
		if grace_frames > 0 then
			grace_frames = grace_frames - 1
		elseif not arm_settled and not p2_has_valid_input() then
			arm_settled = true
		end
		if grace_frames > 0 then
			heading(112, 38, "GET READY... " .. string.format("%.1f", grace_frames / 60), "#FFFF00")
		else
			heading(102, 38, "START MOVING TO RECORD!", "#00FF00")
		end
		gui.text(130, 60, "Slot : " .. chosen_slot)
		gui.text(130, 72, "Control : P2")
		gui.text(130, 84, "Recording starts with first input.")
		gui.text(130, 96, "Positions saved - restored when done.")
		gui.text(130, 120, "Lua key 1 : Cancel wizard", "#AAAAAA")
		-- DEBUG VISIBILITY: the latch and the live input source, so a failure
		-- to start is diagnosable from a single screenshot.
		local _armheld = p2_held_inputs()
		gui.text(130, 108, "Ready : " .. (arm_settled and "yes" or "no - release all inputs")
			.. "   Held : " .. (#_armheld > 0 and table.concat(_armheld, " ") or "(none)"),
			"#FFFF00")
		if grace_frames == 0 and arm_settled and p2_has_valid_input() then
			local ml = macro()
			if ml ~= nil and ml.begin_temporary_recording ~= nil and ml.begin_temporary_recording() then
				neutral_frames = 0
				raw_frames = 0
				state = "RECORDING"
			else
				cleanup("error")
			end
		end
		-- No arm timeout: ARMED waits indefinitely for the first input. There
		-- is always a way out without one - any input starts the recording and
		-- 120 neutral frames then finish it.

	elseif state == "RECORDING" then
		-- Something outside the wizard can switch the recording off underneath
		-- it - a savestate load does exactly that, since bulletproof() refuses
		-- a state that has no data for the take in progress. Notice it and say
		-- so, rather than counting frames into a recording that is no longer
		-- running and reporting it as empty at the end.
		local _rst = macro() ~= nil and macro().get_recording_status ~= nil
		             and macro().get_recording_status() or nil
		if _rst ~= nil and not _rst.recording then
			cleanup("interrupted")
			return
		end
		raw_frames = raw_frames + 1
		if p2_has_valid_input() or not p2_is_free() then
			neutral_frames = 0
		else
			neutral_frames = neutral_frames + 1
		end
		heading(137, 38, "RECORDING...", "#FF0000")
		gui.text(130, 60, "Slot : " .. chosen_slot)
		gui.text(130, 72, "Raw frames : " .. raw_frames)
		gui.text(130, 84, "Free+idle : " .. neutral_frames .. " / " .. AUTO_STOP_NEUTRAL_FRAMES)
		gui.text(130, 96, "Auto-complete after " .. AUTO_STOP_NEUTRAL_FRAMES .. " free frames (2 sec).")
		gui.text(130, 120, "Lua key 1 : Cancel wizard", "#AAAAAA")
		-- DEBUG VISIBILITY: name the keys currently holding P2 non-neutral, so
		-- a stuck key (from any source) is identifiable on screen at once.
		local held = p2_held_inputs()
		gui.text(130, 108, "Held : " .. (#held > 0 and table.concat(held, " ") or "(none)"), "#FFFF00")
		if neutral_frames >= AUTO_STOP_NEUTRAL_FRAMES then
			state = "FINALIZING"
		end

	elseif state == "FINALIZING" then
		local ml = macro()
		local ok = ml ~= nil and ml.stop_temporary_recording ~= nil and ml.stop_temporary_recording()
		if not ok then cleanup("empty") return end
		-- Recording is over: give the pad back to P1 and put both characters
		-- back where they started, so the check that follows plays out from
		-- the spacing it was recorded at, with the user watching from P1.
		restore_control()
		restore_positions()
		preview_started = false
		confirm_armed = false
		state = "PREVIEW"

	elseif state == "PREVIEW" then
		local ml = macro()
		if not preview_started then
			-- WAITING IS NOT FINISHING.
			--
			-- The restore takes up to 24 frames, and until it lands the
			-- playback must not start - it would run against the wrong
			-- spacing. But "not started yet" and "already over" are different
			-- things, and the check further down reads a stopped macro as
			-- over. Nesting the wait keeps it out of that branch.
			if pending_restore == nil then
				if ml ~= nil and ml.play_temporary_recording ~= nil and ml.play_temporary_recording() then
					preview_started = true
				else
					-- Nothing to show. Still offer the save: the file is
					-- written and only the playback failed.
					grace_frames = CONFIRM_GRACE_FRAMES
					confirm_cursor = 1
					state = "CONFIRM"
				end
			end
		else
			local st = ml ~= nil and ml.get_recording_status ~= nil and ml.get_recording_status() or nil
			-- THE SEQUENCE ENDS BEFORE THE DUMMY DOES.
			--
			-- stop_temporary_recording trims the recording back to the last
			-- frame that carried an input, so the playback stops the moment the
			-- inputs run out - with the character still committed to whatever
			-- the last one started. Moving on there puts the save prompt up
			-- over a replay that is visibly still running, which is why its
			-- choices could be answered mid-playback, and why Play again
			-- pressed then restarted from a dummy that could not act and
			-- reproduced nothing.
			--
			-- The prompt comes up as soon as the inputs run out, not when the
			-- dummy has finished moving. Saving and recording again do not care
			-- what the dummy is doing, and waiting for it would hold up anyone
			-- who already knows what they want. Only Play again has to wait,
			-- and it waits for itself further down.
			if st == nil or not st.playing then
				if ml ~= nil and ml.end_temporary_playback ~= nil then ml.end_temporary_playback() end
				grace_frames = CONFIRM_GRACE_FRAMES
				confirm_cursor = 1
				confirm_armed = false
				state = "CONFIRM"
			end
		end
		heading(122, 38, "PLAYING BACK...", "#00FFFF")
		gui.text(130, 60, "Slot : " .. chosen_slot)
		gui.text(130, 72, "Watch the dummy repeat what you recorded.")
		if preview_flip() then
			gui.text(130, 84, "Facing reversed - inputs mirrored.", "#FFFF00")
		end
		gui.text(130, 96, "Lua key 1 : Cancel wizard", "#AAAAAA")

	elseif state == "CONFIRM" then
		heading(SELECT_LEFT, 38, "SAVE TO SLOT " .. chosen_slot .. "?", "#FFFF00")
		local _cur = slot_labels[chosen_slot]
		gui.text(SELECT_LEFT, 60, "  " .. ((_cur ~= nil and _cur ~= "Empty")
			and ("Overwrites the recording from " .. _cur)
			or ("Slot " .. chosen_slot .. " is empty.")))
		-- The three choices are a list like the slot screen, so the whole
		-- wizard is driven the same way: lever to move, LP or Right to take
		-- it. The buttons stay as direct shortcuts for the two that are not
		-- the default, which is what the muscle memory expects.
		for i = 1, 3 do
			local _sel = (i == confirm_cursor)
			-- Play again is the only choice that cares what the dummy is
			-- doing, so it is the only one greyed out. Saving and recording
			-- again are answered the moment the prompt appears.
			local _off = (i == 3) and not replay_ready()
			local _col = "#FFFFFF"
			if _off then _col = "#808080" elseif _sel then _col = "#00FF00" end
			gui.text(SELECT_LEFT, 68 + i * 16,
				(_sel and "< " or "  ") .. CONFIRM_ITEMS[i]
				.. (_sel and " >" or "") .. (_off and "   (still moving)" or ""),
				_col)
		end
		gui.text(SELECT_LEFT, 136, "  LP / Right: Choose   MP: Record Again   LK: Play Again", "#AAAAAA")
		gui.text(SELECT_LEFT, 148, "  Lua key 1 : Cancel wizard (discards)", "#AAAAAA")
		if grace_frames > 0 then grace_frames = grace_frames - 1 return end
		-- A BUTTON HELD FROM THE PLAYBACK IS NOT AN ANSWER.
		--
		-- The grace above is a fixed count, so a button still held when it runs
		-- out answers the prompt by itself. Nothing is taken until every
		-- answering button has been seen released at least once.
		if not confirm_armed then
			if p1 ~= nil and p1.input ~= nil and p1.input.down ~= nil then
				if p1.input.down.LP or p1.input.down.MP or p1.input.down.LK
				   or p1.input.down.right then return end
			end
			confirm_armed = true
		end
		if p1 ~= nil and p1.input ~= nil and p1.input.pressed ~= nil then
			if p1.input.pressed.up and confirm_cursor > 1 then confirm_cursor = confirm_cursor - 1 end
			if p1.input.pressed.down and confirm_cursor < 3 then confirm_cursor = confirm_cursor + 1 end
			local _take = nil
			if p1.input.pressed.LP or p1.input.pressed.right then _take = confirm_cursor
			elseif p1.input.pressed.MP then _take = 2
			elseif p1.input.pressed.LK then _take = 3 end

			if _take == 1 then
				mask_until_release = true
				saved_slot = chosen_slot
				if commit_slot(chosen_slot) then
					-- Straight back to the slot list, so several slots can be
					-- filled in one sitting. A second on the result first: the
					-- list would otherwise replace the message before it had
					-- been read.
					flash("RECORDING COMPLETE - SAVED TO SLOT " .. chosen_slot)
					refresh_slot_labels()
					-- The preview left both characters wherever the recording
					-- put them; the list should come back to the spacing the
					-- take started from, ready for the next one.
					restore_positions()
					saved_pos, rec_facing, saved_slot = nil, nil, nil
					grace_frames = SAVED_HOLD_FRAMES
					state = "SAVED_HOLD"
				else
					cleanup("write_failed")
				end
			elseif _take == 2 then
				-- Retake into the same slot. Same starting spacing, control
				-- back to P2, and the neutral latch has to be earned again.
				mask_until_release = true
				restore_positions()
				if globals.controllerModule ~= nil and globals.controllerModule.set_controlling_target ~= nil then
					globals.controllerModule.set_controlling_target("P2")
				end
				arm_frames = 0
				arm_settled = false
				grace_frames = ARM_SETTLE_FRAMES
				preview_started = false
				state = "ARMED"
			elseif _take == 3 and replay_ready() then
				-- Watch it again from the same spacing it was recorded at.
				mask_until_release = true
				restore_positions()
				preview_started = false
				confirm_armed = false
				state = "PREVIEW"
			end
		end

	elseif state == "SAVED_HOLD" then
		-- The result message is drawn by draw_flash at the top of this
		-- function; this only holds the wizard open long enough to read it.
		if grace_frames > 0 then
			grace_frames = grace_frames - 1
		else
			chosen_slot = nil
			grace_frames = SELECT_GRACE_FRAMES
			state = "SELECT_SLOT"
		end
	end
end

return {
	["start"] = start,
	["shutdown"] = shutdown,
	["is_active"] = is_active,
	["guiRegister"] = guiRegister,
	["mask_input"] = mask_input,
	["request_cancel"] = request_cancel,
	["draw_flash"] = draw_flash,
	["preview_flip"] = preview_flip,
	["slot_stamp"] = slot_stamp,
}
