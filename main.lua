-- space_crawler - 3d dungeon crawler
-- grid-based movement, textured walls via vectorized textri

include("config.lua")
include("renderer.lua")
include("dungeon.lua")
include("dungeon_generator.lua")
include("player.lua")
include("dungeon_view.lua")
include("benchmark.lua")
include("menu.lua")
include("ui.lua")
include("game.lua")


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

	-- spr 1 = floor, spr 2 = ceiling, spr 3 = column (hand-drawn in sprite editor)

end

function _update()
	Game.update()
end

function _draw()
	Game.draw()
end
