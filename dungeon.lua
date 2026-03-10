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

-- direction vectors: 0=N,1=E,2=S,3=W
local dir_dx = {0, 1, 0, -1}
local dir_dz = {-1, 0, 1, 0}

-- check if player can move from (fx,fy) to (tx,ty)
-- up-stairs can only be entered from the entry side (opposite of stairs_dir)
function Dungeon.can_enter(dng, fx, fy, tx, ty)
	if Dungeon.is_wall(dng, tx, ty) then return false end
	if tx == dng.stairs_gx and ty == dng.stairs_gy then
		local d = dng.stairs_dir
		local entry_gx = dng.stairs_gx - dir_dx[d + 1]
		local entry_gy = dng.stairs_gy - dir_dz[d + 1]
		if fx ~= entry_gx or fy ~= entry_gy then
			return false
		end
	end
	return true
end
