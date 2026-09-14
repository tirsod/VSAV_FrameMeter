local stageData = require "./scripts/stage-data"
-- char_chosen lives there because the master script asks the same question for
-- the arcade-stick mirror, and the answer is not the obvious byte.
local util = require "./scripts/utilities"

-- might be appropriate to move functionality related to char select to a
-- dedicated char select module someday

-- local STAGE_WRITE_FUNC_ADDR        = 0xAEFA
local STAGE_WRITE_FUNC_MEMCPY_ADDR = 0xAEC4
local P1_CHAR_SEL_CURS_ADDR        = 0xFF8403
local P2_CHAR_SEL_CURS_ADDR        = 0xFF8803
local last_inputs = nil

CHAR_IDS = {
	Bulleta   = 0x00,
	Demitri   = 0x01,
	Gallon    = 0x02,
	Victor    = 0x03,
	Zabel     = 0x04,
	Morrigan  = 0x05,
	Anakaris  = 0x06,
	Felicia   = 0x07,
	Bishamon  = 0x08,
	Aulbath   = 0x09,
	Sasquatch = 0x0A,
	QBee      = 0x0C,
	LeiLei    = 0x0D,
	Lilith    = 0x0E,
	Jedah     = 0x0F
}

local function resolve_char_id_to_stage_value(char_id)
	if     char_id == CHAR_IDS["Bulleta"]   then return stageData["STAGE_VALUES"].WarAgony
	elseif char_id == CHAR_IDS["Demitri"]   then return stageData["STAGE_VALUES"].FeastOfTheDamned
	elseif char_id == CHAR_IDS["Gallon"]    then return stageData["STAGE_VALUES"].ConcreteCave
	elseif char_id == CHAR_IDS["Victor"]    then return stageData["STAGE_VALUES"].ForeverTorment
	elseif char_id == CHAR_IDS["Zabel"]     then return stageData["STAGE_VALUES"].IronHorseIronTerror
	elseif char_id == CHAR_IDS["Morrigan"] 	then return stageData["STAGE_VALUES"].DesertedChateau
	elseif char_id == CHAR_IDS["Anakaris"] 	then return stageData["STAGE_VALUES"].RedThirst
	elseif char_id == CHAR_IDS["Felicia"]   then return stageData["STAGE_VALUES"].TowerOfArrogance
	elseif char_id == CHAR_IDS["Bishamon"]  then return stageData["STAGE_VALUES"].Abaraya
	elseif char_id == CHAR_IDS["Aulbath"]   then return stageData["STAGE_VALUES"].GreenScream
	elseif char_id == CHAR_IDS["Sasquatch"]	then return stageData["STAGE_VALUES"].ForeverTorment
	elseif char_id == CHAR_IDS["QBee"]      then return stageData["STAGE_VALUES"].VanityParadise
	elseif char_id == CHAR_IDS["LeiLei"]    then return stageData["STAGE_VALUES"].VanityParadise
	elseif char_id == CHAR_IDS["Lilith"]    then return stageData["STAGE_VALUES"].DesertedChateau
	elseif char_id == CHAR_IDS["Jedah"]     then return stageData["STAGE_VALUES"].FetusOfGod
	else                                         return nil
	end
end

local function registerStart()
	memory.registerexec(STAGE_WRITE_FUNC_MEMCPY_ADDR, function()
		if globals.desired_stage ~= nil then
			memory.setregister("m68000.d0", globals.desired_stage)
		end
	end)
end

local function registerAfter()
	if not globals.game_state.match_begun then
		local inputs = joypad.getup()
		if last_inputs ~= nil then
			local coin_edge = inputs["P1 Coin"] == nil and last_inputs["P1 Coin"] == false
			-- Select button (if mapped) also triggers stage select, even during P2 takeover
			local sel_edge = inputs["P1 Select"] == nil and last_inputs["P1 Select"] == false
			local p2_coin_edge = inputs["P2 Coin"] == nil and last_inputs["P2 Coin"] == false
			local p2_sel_edge = inputs["P2 Select"] == nil and last_inputs["P2 Select"] == false
			-- Some sticks map Select to Coin, so either edge counts, and P2 controller also works during takeover
			if coin_edge or sel_edge or p2_coin_edge or p2_sel_edge then
				-- Bulleta is character 0x00, so $3BD alone reads as "has not
				-- chosen" for her - which sent the stage cursor to P1's side
				-- during a P2 takeover she was in. See util.char_chosen.
				local p1_sel = util.char_chosen(0xFF8400)
				local p2_sel = util.char_chosen(0xFF8800)
				local is_takeover = p1_sel and not p2_sel and memory.readbyte(0xFF8009) == 2
				local curs_addr = is_takeover and P2_CHAR_SEL_CURS_ADDR or P1_CHAR_SEL_CURS_ADDR
				globals.desired_stage = resolve_char_id_to_stage_value(memory.readbyte(curs_addr))
			end
		end
		last_inputs = inputs
	end
end

stageSelectModule = {
	["registerStart"] = registerStart,
	["registerAfter"] = registerAfter
}
return stageSelectModule