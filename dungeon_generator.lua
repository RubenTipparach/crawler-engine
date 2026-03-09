-- dungeon_generator.lua
-- Generates a 1/0 tile grid: 1=wall, 0=open
-- Uses recursive backtracker on logical cells, then expands to tile grid

function Dungeon.generate(mw, mh)
	local w = mw * 2 + 1
	local h = mh * 2 + 1
	local map = {}

	-- fill all with walls
	for y=1,h do
		map[y] = {}
		for x=1,w do
			map[y][x] = 1
		end
	end

	-- recursive backtracker
	-- logical cells are at grid positions (cx*2, cy*2)
	-- walls between cells are at odd grid positions
	local visited = {}
	local stack = {}
	local cx, cy = 1, 1
	map[cy*2][cx*2] = 0
	visited[cy*256+cx] = true
	local count = 1
	local total = mw * mh
	local dirs = {{0,-1},{1,0},{0,1},{-1,0}}

	while count < total do
		local nbrs = {}
		for _,d in ipairs(dirs) do
			local nx, ny = cx+d[1], cy+d[2]
			if nx>=1 and nx<=mw and ny>=1 and ny<=mh and not visited[ny*256+nx] then
				nbrs[#nbrs+1] = d
			end
		end
		if #nbrs > 0 then
			local d = nbrs[flr(rnd(#nbrs))+1]
			stack[#stack+1] = {cx,cy}
			-- carve passage wall between cells
			map[cy*2+d[2]][cx*2+d[1]] = 0
			cx += d[1]
			cy += d[2]
			-- carve destination cell
			map[cy*2][cx*2] = 0
			visited[cy*256+cx] = true
			count += 1
		else
			local p = stack[#stack]
			stack[#stack] = nil
			cx, cy = p[1], p[2]
		end
	end

	Dungeon.map = map
	Dungeon.w = w
	Dungeon.h = h
	Dungeon.mw = mw
	Dungeon.mh = mh
	return Dungeon
end

-- print the map as text (for debugging)
function Dungeon.print_map(dng, px, py)
	for y=1,dng.h do
		local row = ""
		for x=1,dng.w do
			if dng.map[y][x] == 1 then
				row = row .. "#"
			else
				row = row .. "."
			end
		end
		print(row, 2, py + (y-1)*6, 7)
	end
end

-- draw minimap
function Dungeon.draw_minimap(dng, player_gx, player_gy, mx, my, scale)
	for y=1,dng.h do
		for x=1,dng.w do
			if dng.map[y][x] == 1 then
				rectfill(mx+(x-1)*scale, my+(y-1)*scale,
				         mx+x*scale-1, my+y*scale-1, 5)
			end
		end
	end
	-- player dot
	rectfill(mx+(player_gx-1)*scale, my+(player_gy-1)*scale,
	         mx+player_gx*scale-1, my+player_gy*scale-1, 11)
end
