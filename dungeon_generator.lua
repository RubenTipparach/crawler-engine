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

-- direction vectors: 0=N,1=E,2=S,3=W
local dir_dx = {0, 1, 0, -1}
local dir_dz = {-1, 0, 1, 0}

-- up-stairs: must have a wall in the facing direction, open on opposite (entry) side
local function find_up_stairs_cell(map, room, w, h)
	for py = room.y, room.y + room.h - 1 do
		for px = room.x, room.x + room.w - 1 do
			if map[py][px] == 0 then
				for d = 0, 3 do
					local wx = px + dir_dx[d + 1]
					local wy = py + dir_dz[d + 1]
					local ex = px - dir_dx[d + 1]
					local ey = py - dir_dz[d + 1]
					local has_wall = wx < 1 or wx > w or wy < 1 or wy > h or map[wy][wx] == 1
					local has_entry = ex >= 1 and ex <= w and ey >= 1 and ey <= h and map[ey][ex] == 0
					if has_wall and has_entry then
						return px, py, d
					end
				end
			end
		end
	end
	-- fallback: room center, find any wall side and carve entry
	local cx, cy = room.cx, room.cy
	for d = 0, 3 do
		local wx = cx + dir_dx[d + 1]
		local wy = cy + dir_dz[d + 1]
		if wx < 1 or wx > w or wy < 1 or wy > h or map[wy][wx] == 1 then
			local ex = cx - dir_dx[d + 1]
			local ey = cy - dir_dz[d + 1]
			if ex >= 1 and ex <= w and ey >= 1 and ey <= h then
				map[ey][ex] = 0
			end
			return cx, cy, d
		end
	end
	return cx, cy, 2
end

-- check all 8 neighbors (cardinal + diagonal) are open
local function all8_open(map, px, py, w, h)
	for dy = -1, 1 do
		for dx = -1, 1 do
			if dx ~= 0 or dy ~= 0 then
				local nx, ny = px + dx, py + dy
				if nx < 1 or nx > w or ny < 1 or ny > h or map[ny][nx] ~= 0 then
					return false
				end
			end
		end
	end
	return true
end

-- carve all 8 neighbors around a cell
local function carve8(map, px, py, w, h)
	for dy = -1, 1 do
		for dx = -1, 1 do
			if dx ~= 0 or dy ~= 0 then
				local nx, ny = px + dx, py + dy
				if nx >= 1 and nx <= w and ny >= 1 and ny <= h then
					map[ny][nx] = 0
				end
			end
		end
	end
end

-- down-stairs: must have all 8 neighbors open
local function find_down_stairs_cell(map, room, w, h)
	for py = room.y, room.y + room.h - 1 do
		for px = room.x, room.x + room.w - 1 do
			if map[py][px] == 0 and all8_open(map, px, py, w, h) then
				return px, py
			end
		end
	end
	-- fallback: carve all 8 neighbors of room center
	local cx, cy = room.cx, room.cy
	carve8(map, cx, cy, w, h)
	return cx, cy
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

	dng.stairs_gx, dng.stairs_gy, dng.stairs_dir = find_up_stairs_cell(map, stairs_room, w, h)

	-- down-stairs (return to previous floor) — all 4 neighbors must be open
	if has_down_stairs then
		dng.down_gx, dng.down_gy = find_down_stairs_cell(map, start_room, w, h)
		dng.down_dir = flr(rnd(4))
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

-- build cached minimap texture (call once per dungeon)
function Dungeon.build_minimap_tex(dng, scale)
	local tw = dng.w * scale
	local th = dng.h * scale
	local tex = userdata("u8", tw, th)
	for y = 1, dng.h do
		for x = 1, dng.w do
			if dng.map[y][x] == 1 then
				local px0 = (x - 1) * scale
				local py0 = (y - 1) * scale
				for py = py0, py0 + scale - 1 do
					for px = px0, px0 + scale - 1 do
						tex:set(px, py, 5)
					end
				end
			end
		end
	end
	dng.minimap_tex = tex
	dng.minimap_scale = scale
end

-- draw minimap (uses cached texture for walls, draws dynamic markers on top)
function Dungeon.draw_minimap(dng, player_gx, player_gy, mx, my, scale, vis)
	-- rebuild cache if needed
	if not dng.minimap_tex or dng.minimap_scale ~= scale then
		Dungeon.build_minimap_tex(dng, scale)
	end

	-- blit cached wall texture
	local tex = dng.minimap_tex
	local tw, th = tex:width(), tex:height()
	sspr(tex, 0, 0, tw, th, mx, my, tw, th)

	-- overdraw visible walls in brighter color
	if vis then
		for y = 1, dng.h do
			local row = dng.map[y]
			local ykey = y * 65536
			for x = 1, dng.w do
				if row[x] == 1 and vis[ykey + x] then
					rectfill(mx+(x-1)*scale, my+(y-1)*scale,
					         mx+x*scale-1, my+y*scale-1, 8)
				end
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
