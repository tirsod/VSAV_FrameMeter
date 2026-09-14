---@author VMP_MBD (MBDesu)

require 'gd'

-- consts
local P1_INPUT_ADDR = 0xff8522
local P1_TECH_HIT_INPUT_COUNT_ADDR = 0xff8570
local TECH_HIT_SUCCESS_CHECK_ADDR = 0x2762a
local INPUT_REPRESENTATIONS = { 'LP', 'MP', 'HP', '', 'LK', 'MK', 'HK' }
local ICON_FILE = 'scrolling-input/capcom-8.png'
local BLANK_PNG_BYTES = {
  '0x89', '0x50', '0x4E', '0x47', '0x0D', '0x0A', '0x1A', '0x0A', '0x00',
  '0x00', '0x00', '0x0D', '0x49', '0x48', '0x44', '0x52', '0x00', '0x00',
  '0x00', '0x40', '0x00', '0x00', '0x00', '0x20', '0x01', '0x03', '0x00',
  '0x00', '0x00', '0x98', '0x53', '0xEC', '0xC7', '0x00', '0x00', '0x00',
  '0x03', '0x50', '0x4C', '0x54', '0x45', '0x00', '0x00', '0x00', '0xA7',
  '0x7A', '0x3D', '0xDA', '0x00', '0x00', '0x00', '0x01', '0x74', '0x52',
  '0x4E', '0x53', '0x00', '0x40', '0xE6', '0xD8', '0x66', '0x00', '0x00',
  '0x00', '0x0D', '0x49', '0x44', '0x41', '0x54', '0x18', '0x95', '0x63',
  '0x60', '0x18', '0x05', '0xF8', '0x00', '0x00', '0x01', '0x20', '0x00',
  '0x01', '0xBF', '0xC1', '0xB1', '0xA8', '0x00', '0x00', '0x00', '0x00',
  '0x49', '0x45', '0x4E', '0x44', '0xAE', '0x42', '0x60', '0x82'
}

-- local state
local last_num_inputs = 0
local tech_hit_input_history = {}
local icons = {}

local png_str_from_bytes = function(bytes)
  local str = ''
  for _, b in pairs(bytes) do
    str = str .. string.char(b)
  end
  return str
end

local image_setup = function()
  local icon_sheet = gd.createFromPng(ICON_FILE)
  for i = 1,6 do
    local tmp = gd.createFromPngStr(png_str_from_bytes(BLANK_PNG_BYTES))
    gd.copyResampled(tmp, icon_sheet, 0, 0, 0, 8 * (8 + (i - 1)), 8, 8, 8, 8)
    icons[#icons + 1] = tmp:gdStr()
  end
end

local btst = function(bit_pos, value)
  return bit.band(bit.lshift(1, bit_pos), value) > 0
end

---Converts a raw button input value from memory into
---an icons representation of all pressed buttons
---@param raw_input number
---@return table<string>
local parse_input = function(raw_input)
  local pressed_buttons = {}

  for i = 1,7 do
    if i ~= 4 and btst(i - 1, raw_input) then
      local icon
      if i < 4 then icon = icons[i] else icon = icons[i - 1] end
      pressed_buttons[#pressed_buttons + 1] = icon
    end
  end
  return pressed_buttons
end

local get_count = function()
  return memory.readbyte(P1_TECH_HIT_INPUT_COUNT_ADDR)
end

local update_tech_hit_input_history = function(did_tech_hit)
  local current_num_inputs = get_count()
  if last_num_inputs > current_num_inputs then
    tech_hit_input_history = {}
  end
  if last_num_inputs ~= current_num_inputs then
    last_num_inputs = current_num_inputs
    local history_entry =
          {current_num_inputs, parse_input(memory.readbyte(P1_INPUT_ADDR))}
    if did_tech_hit == true then
      history_entry[3] = 'TECH HIT'
    end
    tech_hit_input_history[#tech_hit_input_history + 1] = history_entry
  end
end

memory.registerexec(TECH_HIT_SUCCESS_CHECK_ADDR, function()
  -- Z flag will contain indication of success; second bit of SR register
  -- additionally, we only reach 0x2762a on successful tech hit input
  local did_tech_hit = not btst(2, memory.getregister('m68000.sr'))
  update_tech_hit_input_history(did_tech_hit)
end)

image_setup()

local guiRegister = function()
  for i, entry in pairs(tech_hit_input_history) do
      print(entry)
      local y = emu.screenheight() - 160 + 10 * i
      gui.text(5, y, entry[1] .. ': ')
      for j, icon in pairs(entry[2]) do
        local x = 5 + 10 * j
        gui.gdoverlay(x, y - 1, icon)
      end
      if entry[3] ~= nil then
        gui.text((#entry[2] + 1) * 10 + 7, y, 'TECH HIT')
      end
  end
end

return guiRegister