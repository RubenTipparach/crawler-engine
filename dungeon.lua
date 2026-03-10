-- dungeon.lua
-- Dungeon data + helpers (generation in dungeon_generator.lua)

Dungeon = {}

function Dungeon.is_wall(dng, gx, gy)
	if gx<1 or gx>dng.w or gy<1 or gy>dng.h then return true end
	return dng.map[gy][gx] == 1
end

function Dungeon.is_open(dng, gx, gy)
	return not Dungeon.is_wall(dng, gx, gy)
end
