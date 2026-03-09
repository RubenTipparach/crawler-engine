-- space_crawler - 3d dungeon crawler
-- grid-based movement, textured walls via vectorized textri

include("renderer.lua")
include("dungeon.lua")
include("dungeon_generator.lua")
include("player.lua")
include("dungeon_view.lua")
include("benchmark.lua")
include("menu.lua")
include("ui.lua")
include("game.lua")

-- fog darkening: remap wall colors to darker variants per level
-- texture uses colors 5(dark gray), 6(light gray), 7(white), 12(blue)
local fog_maps = {
	{[5]=1, [6]=5, [7]=6, [12]=1},   -- level 1: slight
	{[5]=0, [6]=1, [7]=5, [12]=0},   -- level 2: medium
	{[5]=0, [6]=0, [7]=1, [12]=0},   -- level 3: heavy
	{[5]=0, [6]=0, [7]=0, [12]=0},   -- level 4: blackout
}

function _init()
	-- generate wall texture if sprite 0 is blank
	local sp = get_spr(0)
	local blank = true
	for py=0,7 do
		for px=0,7 do
			if sp:get(px,py) ~= 0 then blank = false break end
		end
		if not blank then break end
	end
	if blank then
		local tex = userdata("u8",16,16)
		for py=0,15 do
			for px=0,15 do
				-- 4x4 brick pattern: each sub-tile is 4x4 pixels
				local c = 12
				if (flr(px/2)+flr(py/2)) % 2 == 0 then c = 7 end
				-- grid lines every 4 pixels
				if px%4==0 or py%4==0 then c=6 end
				-- shadow edges
				if px%4==3 or py%4==3 then c=5 end
				tex:set(px,py,c)
			end
		end
		set_spr(0, tex)
	end

	-- generate darkened wall texture variants (sprites 1-4)
	local base = get_spr(0)
	for level=1,#fog_maps do
		local dark_tex = userdata("u8", 16, 16)
		local remap = fog_maps[level]
		for py=0,15 do
			for px=0,15 do
				local c = base:get(px, py)
				dark_tex:set(px, py, remap[c] or c)
			end
		end
		set_spr(level, dark_tex)
	end
end

function _update()
	Game.update()
end

function _draw()
	Game.draw()
end
