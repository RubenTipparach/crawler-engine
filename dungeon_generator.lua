-- dungeon_generator.lua
-- Room-based dungeon generator
-- Each floor has randomly placed rooms connected by corridors

local function carve_corridor(map, x1, y1, x2, y2)
	-- L-shaped: horizontal then vertical
	local sx = x2 >= x1 and 1 or -1
	for x = x1, x2, sx do
		map[y1][x] = 0
	end
	local sy = y2 >= y1 and 1 or -1
	for y = y1, y2, sy do
		map[y][x2] = 0
	end
end

local function find_stairs_dir(map, gx, gy, w, h)
	local sdirs = {{0,-1,0},{1,0,1},{0,1,2},{-1,0,3}}
	for _, sd in ipairs(sdirs) do
		local nx, ny = gx + sd[1], gy + sd[2]
		if nx >= 1 and nx <= w and ny >= 1 and ny <= h and map[ny][nx] == 0 then
			return (sd[3] + 2) % 4
		end
	end
	return 2
end

function Dungeon.generate(w, h, has_down_stairs)
	local dng = {}
	local map = {}

	for y = 1, h do
		map[y] = {}
		for x = 1, w do
			map[y][x] = 1
		end
	end

	-- place rooms (allow overlap for tower-like variety)
	local rooms = {}
	local num_rooms = 5 + flr(rnd(4)) -- 5-8

	for _ = 1, num_rooms do
		local rw = 2 + flr(rnd(3)) -- 2-4
		local rh = 2 + flr(rnd(3))
		local rx = 2 + flr(rnd(w - rw - 2))
		local ry = 2 + flr(rnd(h - rh - 2))

		rooms[#rooms + 1] = {
			x = rx, y = ry, w = rw, h = rh,
			cx = rx + flr(rw / 2),
			cy = ry + flr(rh / 2)
		}
		for py = ry, ry + rh - 1 do
			for px = rx, rx + rw - 1 do
				map[py][px] = 0
			end
		end
	end

	-- connect rooms sequentially
	for i = 2, #rooms do
		carve_corridor(map, rooms[i-1].cx, rooms[i-1].cy,
		               rooms[i].cx, rooms[i].cy)
	end
	-- extra corridor for loops
	if #rooms > 2 then
		carve_corridor(map, rooms[1].cx, rooms[1].cy,
		               rooms[#rooms].cx, rooms[#rooms].cy)
	end

	-- start room = room 1
	local start_room = rooms[1]
	dng.spawn_gx = start_room.cx
	dng.spawn_gy = start_room.cy

	-- place up-stairs in farthest room from room 1
	local best_idx = #rooms
	local best_dist = 0
	for i = 2, #rooms do
		local r = rooms[i]
		local dist = abs(r.cx - start_room.cx) + abs(r.cy - start_room.cy)
		if dist > best_dist then
			best_dist = dist
			best_idx = i
		end
	end
	local stairs_room = rooms[best_idx]

	dng.stairs_gx = stairs_room.cx
	dng.stairs_gy = stairs_room.cy
	dng.stairs_dir = find_stairs_dir(map, dng.stairs_gx, dng.stairs_gy, w, h)

	-- down-stairs (return to previous floor)
	if has_down_stairs then
		dng.down_gx = start_room.cx
		dng.down_gy = start_room.cy
		dng.down_dir = find_stairs_dir(map, dng.down_gx, dng.down_gy, w, h)
	end

	dng.map = map
	dng.w = w
	dng.h = h

	return dng
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
function Dungeon.draw_minimap(dng, player_gx, player_gy, mx, my, scale, vis)
	for y=1,dng.h do
		for x=1,dng.w do
			local c = nil
			if dng.map[y][x] == 1 then
				c = (vis and vis[y * 65536 + x]) and 8 or 5
			end
			if c then
				rectfill(mx+(x-1)*scale, my+(y-1)*scale,
				         mx+x*scale-1, my+y*scale-1, c)
			end
		end
	end
	-- up-stairs marker (green)
	local sx, sy = dng.stairs_gx, dng.stairs_gy
	rectfill(mx+(sx-1)*scale, my+(sy-1)*scale,
	         mx+sx*scale-1, my+sy*scale-1, 10)
	-- down-stairs marker (red)
	if dng.down_gx then
		local dx, dy = dng.down_gx, dng.down_gy
		rectfill(mx+(dx-1)*scale, my+(dy-1)*scale,
		         mx+dx*scale-1, my+dy*scale-1, 8)
	end
	-- player dot
	rectfill(mx+(player_gx-1)*scale, my+(player_gy-1)*scale,
	         mx+player_gx*scale-1, my+player_gy*scale-1, 11)
end
