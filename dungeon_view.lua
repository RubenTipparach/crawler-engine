-- dungeon_view.lua
-- voxel-style dungeon renderer with near-plane clipping + occlusion culling

DungeonView = {}

local CELL = Config.cell_size
local HALF = CELL / 2
local RENDER_R = Config.render.radius
local NEAR = Config.render.near
local NUM_RAYS = Config.render.num_rays

-- resolution modes: 0=full(480x270), 1=half(240x135), 2=quarter(120x67)
local RES_MODES = {
	{240, 135},  -- half
	{120, 67},   -- quarter
}
local res_bufs = {}
for i = 1, #RES_MODES do
	res_bufs[i] = userdata("u8", RES_MODES[i][1], RES_MODES[i][2])
end
DungeonView.res_mode = 1  -- 0=full, 1=half, 2=quarter
-- keep half_res for backwards compat in HUD
DungeonView.half_res = true

-- pre-allocated clip buffers (zero per-frame allocations)
local _cv = {}
local _co = {}
for i=1,8 do
	_cv[i] = {0,0,0,0,0,0,0,0}
	_co[i] = {0,0,0,0,0,0,0,0}
end

-- pre-allocated UV tables (constant, reused every frame)
local UV_S = 64
local uv_a = {0, 0}
local uv_b = {UV_S, 0}
local uv_c = {UV_S, UV_S}
local uv_d = {0, UV_S}

local P = CELL / 8
local uv_p = P / CELL * UV_S
local wall_a = {uv_p, 0}
local wall_b = {UV_S - uv_p, 0}
local wall_c = {UV_S - uv_p, UV_S}
local wall_d = {uv_p, UV_S}

local pil_s = 16
local pil_a = {0, 0}
local pil_b = {pil_s, 0}
local pil_c = {pil_s, UV_S}
local pil_d = {0, UV_S}

-- Sutherland-Hodgman clip polygon against near plane
local function clip_near(verts, n)
	local out_n = 0
	local pv = verts[n]
	local p_in = pv[3] >= NEAR

	for i = 1, n do
		local cv = verts[i]
		local c_in = cv[3] >= NEAR

		if p_in ~= c_in then
			local t = (NEAR - pv[3]) / (cv[3] - pv[3])
			out_n += 1
			local o = _co[out_n]
			o[1] = pv[1] + t * (cv[1] - pv[1])
			o[2] = pv[2] + t * (cv[2] - pv[2])
			o[3] = NEAR
			o[4] = pv[4] + t * (cv[4] - pv[4])
			o[5] = pv[5] + t * (cv[5] - pv[5])
		end

		if c_in then
			out_n += 1
			local o = _co[out_n]
			o[1],o[2],o[3],o[4],o[5] = cv[1],cv[2],cv[3],cv[4],cv[5]
		end

		pv = cv
		p_in = c_in
	end

	return _co, out_n
end

local function try_quad(
	ax,ay,az, bx,by,bz, cx,cy,cz, dx,dy,dz,
	cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, base_spr
)
	-- inline view transforms (avoid function call overhead)
	local dxa, dya, dza = ax-cam_x, ay-cam_y, az-cam_z
	local va_x, va_z = dxa*ca-dza*sa, -dxa*sa-dza*ca
	local dxb, dyb, dzb = bx-cam_x, by-cam_y, bz-cam_z
	local vb_x, vb_z = dxb*ca-dzb*sa, -dxb*sa-dzb*ca
	local dxc, dyc, dzc = cx-cam_x, cy-cam_y, cz-cam_z
	local vc_x, vc_z = dxc*ca-dzc*sa, -dxc*sa-dzc*ca
	local dxd, dyd, dzd = dx-cam_x, dy-cam_y, dz-cam_z
	local vd_x, vd_z = dxd*ca-dzd*sa, -dxd*sa-dzd*ca

	if va_z < NEAR and vb_z < NEAR and vc_z < NEAR and vd_z < NEAR then return end

	-- clip path (rare - vertex behind near plane)
	if va_z < NEAR or vb_z < NEAR or vc_z < NEAR or vd_z < NEAR then
		_cv[1][1],_cv[1][2],_cv[1][3],_cv[1][4],_cv[1][5] = va_x,dya,va_z,uv_a[1],uv_a[2]
		_cv[2][1],_cv[2][2],_cv[2][3],_cv[2][4],_cv[2][5] = vb_x,dyb,vb_z,uv_b[1],uv_b[2]
		_cv[3][1],_cv[3][2],_cv[3][3],_cv[3][4],_cv[3][5] = vc_x,dyc,vc_z,uv_c[1],uv_c[2]
		_cv[4][1],_cv[4][2],_cv[4][3],_cv[4][4],_cv[4][5] = vd_x,dyd,vd_z,uv_d[1],uv_d[2]
		local clipped, cn = clip_near(_cv, 4)
		if cn < 3 then return end

		local fov = Renderer.fov
		local scx = Renderer.cx
		local scy = Renderer.cy
		local z_sum = 0
		for i = 1, cn do
			local v = clipped[i]
			local w = 1 / v[3]
			v[6] = scx + v[1] * fov * w
			v[7] = scy - v[2] * fov * w
			v[8] = w
			z_sum += v[3]
		end

		local c1, c2, c3 = clipped[1], clipped[2], clipped[3]
		if (c2[6]-c1[6])*(c3[7]-c1[7]) - (c2[7]-c1[7])*(c3[6]-c1[6]) <= 0 then return end

		local depth = z_sum / cn
		for i = 2, cn - 1 do
			local vi, vi1 = clipped[i], clipped[i+1]
			Renderer.submit_tri(
				c1[6],c1[7],c1[8], vi[6],vi[7],vi[8], vi1[6],vi1[7],vi1[8],
				c1[4],c1[5], vi[4],vi[5], vi1[4],vi1[5], depth, base_spr
			)
		end
		return
	end

	-- fast path: all vertices in front (zero allocations)
	local fov = Renderer.fov
	local scx = Renderer.cx
	local scy = Renderer.cy

	local wa = 1/va_z
	local pax, pay = scx + va_x*fov*wa, scy - dya*fov*wa
	local wb = 1/vb_z
	local pbx, pby = scx + vb_x*fov*wb, scy - dyb*fov*wb
	local wc = 1/vc_z
	local pcx, pcy = scx + vc_x*fov*wc, scy - dyc*fov*wc
	local wd = 1/vd_z
	local pdx, pdy = scx + vd_x*fov*wd, scy - dyd*fov*wd

	if (pbx-pax)*(pcy-pay) - (pby-pay)*(pcx-pax) <= 0 then return end

	local depth = (va_z+vb_z+vc_z+vd_z)*0.25

	Renderer.submit_tri(pax,pay,wa, pbx,pby,wb, pcx,pcy,wc,
		uv_a[1],uv_a[2], uv_b[1],uv_b[2], uv_c[1],uv_c[2], depth, base_spr)
	Renderer.submit_tri(pax,pay,wa, pcx,pcy,wc, pdx,pdy,wd,
		uv_a[1],uv_a[2], uv_c[1],uv_c[2], uv_d[1],uv_d[2], depth, base_spr)
end

-- stairs geometry: 10 flat-shaded steps with dithered risers
local NUM_STEPS = 10

local function render_stairs(x0, x1, z0, z1, y_lo, y_hi, dir, cam_x, cam_y, cam_z, ca, sa, uv_a, uv_b, uv_c, uv_d, going_down)
	local y_range = y_hi - y_lo
	local step_h = y_range / NUM_STEPS
	local step_d = CELL / NUM_STEPS

	for i = 0, NUM_STEPS - 1 do
		local tread_y, riser_top, riser_bot
		if going_down then
			tread_y = y_lo - (i + 1) * step_h
			riser_top = y_lo - i * step_h
			riser_bot = tread_y
		else
			tread_y = y_lo + (i + 1) * step_h
			riser_top = tread_y
			riser_bot = y_lo + i * step_h
		end

		if dir == 0 then -- north (-z), entrance from south
			local sz0 = z1 - (i + 1) * step_d
			local sz1 = z1 - i * step_d
			try_quad(x0,tread_y,sz0, x1,tread_y,sz0, x1,tread_y,sz1, x0,tread_y,sz1,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 4)
			try_quad(x0,riser_top,sz1, x1,riser_top,sz1, x1,riser_bot,sz1, x0,riser_bot,sz1,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)

		elseif dir == 1 then -- east (+x), entrance from west
			local sx0 = x0 + i * step_d
			local sx1 = x0 + (i + 1) * step_d
			try_quad(sx0,tread_y,z0, sx1,tread_y,z0, sx1,tread_y,z1, sx0,tread_y,z1,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 4)
			try_quad(sx0,riser_top,z0, sx0,riser_top,z1, sx0,riser_bot,z1, sx0,riser_bot,z0,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)

		elseif dir == 2 then -- south (+z), entrance from north
			local sz0 = z0 + i * step_d
			local sz1 = z0 + (i + 1) * step_d
			try_quad(x0,tread_y,sz0, x1,tread_y,sz0, x1,tread_y,sz1, x0,tread_y,sz1,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 4)
			try_quad(x1,riser_top,sz0, x0,riser_top,sz0, x0,riser_bot,sz0, x1,riser_bot,sz0,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)

		elseif dir == 3 then -- west (-x), entrance from east
			local sx0 = x1 - (i + 1) * step_d
			local sx1 = x1 - i * step_d
			try_quad(sx0,tread_y,z0, sx1,tread_y,z0, sx1,tread_y,z1, sx0,tread_y,z1,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 4)
			try_quad(sx1,riser_top,z1, sx1,riser_top,z0, sx1,riser_bot,z0, sx1,riser_bot,z1,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)
		end
	end

	-- stair-stepped side walls + back wall only for up-stairs
	if going_down then return end

	for i = 0, NUM_STEPS - 1 do
		local tread_y_i
		if going_down then
			tread_y_i = y_lo - (i + 1) * step_h
		else
			tread_y_i = y_lo + (i + 1) * step_h
		end

		local side_top = going_down and y_lo or tread_y_i
		local side_bot = going_down and tread_y_i or y_lo

		if dir == 0 then
			local sz0 = z1 - (i + 1) * step_d
			local sz1 = z1 - i * step_d
			-- west side (facing west, outward)
			try_quad(x0,side_top,sz0, x0,side_top,sz1, x0,side_bot,sz1, x0,side_bot,sz0,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)
			-- east side (facing east, outward)
			try_quad(x1,side_top,sz1, x1,side_top,sz0, x1,side_bot,sz0, x1,side_bot,sz1,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)

		elseif dir == 1 then
			local sx0 = x0 + i * step_d
			local sx1 = x0 + (i + 1) * step_d
			-- north side (facing north, outward)
			try_quad(sx1,side_top,z0, sx0,side_top,z0, sx0,side_bot,z0, sx1,side_bot,z0,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)
			-- south side (facing south, outward)
			try_quad(sx0,side_top,z1, sx1,side_top,z1, sx1,side_bot,z1, sx0,side_bot,z1,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)

		elseif dir == 2 then
			local sz0 = z0 + i * step_d
			local sz1 = z0 + (i + 1) * step_d
			-- west side (facing west, outward)
			try_quad(x0,side_top,sz0, x0,side_top,sz1, x0,side_bot,sz1, x0,side_bot,sz0,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)
			-- east side (facing east, outward)
			try_quad(x1,side_top,sz1, x1,side_top,sz0, x1,side_bot,sz0, x1,side_bot,sz1,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)

		elseif dir == 3 then
			local sx0 = x1 - (i + 1) * step_d
			local sx1 = x1 - i * step_d
			-- north side (facing north, outward)
			try_quad(sx1,side_top,z0, sx0,side_top,z0, sx0,side_bot,z0, sx1,side_bot,z0,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)
			-- south side (facing south, outward)
			try_quad(sx0,side_top,z1, sx1,side_top,z1, sx1,side_bot,z1, sx0,side_bot,z1,
				cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)
		end
	end

	-- back wall (flat shaded, facing outward from stairs)
	local y_bot = going_down and (y_lo - y_range) or y_lo
	local y_top = y_hi

	if dir == 0 then
		-- north end, facing north
		try_quad(x1,y_top,z0, x0,y_top,z0, x0,y_bot,z0, x1,y_bot,z0,
			cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)
	elseif dir == 1 then
		-- east end, facing east
		try_quad(x1,y_top,z1, x1,y_top,z0, x1,y_bot,z0, x1,y_bot,z1,
			cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)
	elseif dir == 2 then
		-- south end, facing south
		try_quad(x0,y_top,z1, x1,y_top,z1, x1,y_bot,z1, x0,y_bot,z1,
			cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)
	elseif dir == 3 then
		-- west end, facing west
		try_quad(x0,y_top,z0, x0,y_top,z1, x0,y_bot,z1, x0,y_bot,z0,
			cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 5)
	end
end

-- DDA raycast through grid, marking visible open cells
local vis = {}
DungeonView.vis = vis

local function build_visibility(px, pz, ca, sa, map, dw, dh)
	-- clear
	for k in pairs(vis) do vis[k] = nil end

	-- forward = (-sa, -ca), right = (ca, -sa)
	local fwd_x, fwd_z = -sa, -ca
	local rt_x, rt_z = ca, -sa

	-- player grid-space position (0-based fractional)
	local gpx = px / CELL
	local gpz = pz / CELL
	local max_steps = RENDER_R * 3
	local max_dist = Config.fog.stop / CELL
	local _flr = flr
	local _abs = abs
	local inv_rays = 2 / NUM_RAYS

	-- pre-compute player grid cell (constant across all rays)
	local pgx = _flr(gpx)
	local pgz = _flr(gpz)

	-- always mark player's own cell visible
	local pmgx, pmgz = pgx + 1, pgz + 1
	if pmgx >= 1 and pmgx <= dw and pmgz >= 1 and pmgz <= dh then
		vis[pmgz * 65536 + pmgx] = true
	end

	for r = 0, NUM_RAYS do
		local t = r * inv_rays - 1
		local rdx = fwd_x + rt_x * t
		local rdz = fwd_z + rt_z * t

		-- DDA setup
		local gx = pgx
		local gz = pgz
		local sx = rdx >= 0 and 1 or -1
		local sz = rdz >= 0 and 1 or -1
		local idx = rdx ~= 0 and _abs(1 / rdx) or 32000
		local idz = rdz ~= 0 and _abs(1 / rdz) or 32000
		local tx = rdx >= 0 and (gx + 1 - gpx) * idx or (gpx - gx) * idx
		local tz = rdz >= 0 and (gz + 1 - gpz) * idz or (gpz - gz) * idz

		for _ = 1, max_steps do
			local mgx = gx + 1
			local mgz = gz + 1
			if mgx < 1 or mgx > dw or mgz < 1 or mgz > dh then break end

			local key = mgz * 65536 + mgx
			if map[mgz][mgx] == 1 then
				vis[key] = true
				break
			end

			vis[key] = true

			if tx < tz then
				if tx > max_dist then break end
				gx += sx
				tx += idx
			else
				if tz > max_dist then break end
				gz += sz
				tz += idz
			end
		end
	end
end

function DungeonView.draw(dng, player)
	if keyp("m") then
		DungeonView.res_mode = (DungeonView.res_mode + 1) % 3
		DungeonView.half_res = DungeonView.res_mode > 0
	end

	local rm = DungeonView.res_mode
	if rm > 0 then
		local rw, rh = RES_MODES[rm][1], RES_MODES[rm][2]
		Renderer.set_resolution(rw, rh)
		set_draw_target(res_bufs[rm])
	else
		Renderer.set_resolution(480, 270)
	end
	cls(0)
	Renderer.begin_frame()

	local cam_x = player.x
	local cam_y = player.y or 0
	local cam_z = player.z
	local ca = cos(player.angle)
	local sa = sin(player.angle)

	local pgx, pgy = player.gx, player.gy
	local gx0 = max(1, pgx - RENDER_R)
	local gx1 = min(dng.w, pgx + RENDER_R)
	local gy0 = max(1, pgy - RENDER_R)
	local gy1 = min(dng.h, pgy + RENDER_R)

	local map = dng.map
	local y_hi, y_lo = HALF, -HALF
	local dw, dh = dng.w, dng.h

	-- build visibility from player position
	profile(" visibility")
	build_visibility(cam_x, cam_z, ca, sa, map, dw, dh)
	profile(" visibility")

	profile(" geometry")
	for gy = gy0, gy1 do
		local row = map[gy]
		local z0 = (gy - 1) * CELL
		local z1 = gy * CELL

		for gx = gx0, gx1 do
			local key = gy * 65536 + gx
			if not vis[key] then
				-- not visible, skip
			elseif row[gx] == 1 then
				local x0 = (gx - 1) * CELL
				local x1 = gx * CELL

				-- south face (inset x by P for column fit)
				if gy < dh and map[gy+1][gx] ~= 1 and vis[(gy+1) * 65536 + gx] then
					try_quad(x0+P,y_hi,z1, x1-P,y_hi,z1, x1-P,y_lo,z1, x0+P,y_lo,z1,
						cam_x,cam_y,cam_z, ca,sa, wall_a,wall_b,wall_c,wall_d)
				end

				-- north face (inset x by P)
				if gy > 1 and map[gy-1][gx] ~= 1 and vis[(gy-1) * 65536 + gx] then
					try_quad(x1-P,y_hi,z0, x0+P,y_hi,z0, x0+P,y_lo,z0, x1-P,y_lo,z0,
						cam_x,cam_y,cam_z, ca,sa, wall_a,wall_b,wall_c,wall_d)
				end

				-- east face (inset z by P)
				if gx < dw and row[gx+1] ~= 1 and vis[gy * 65536 + gx + 1] then
					try_quad(x1,y_hi,z1-P, x1,y_hi,z0+P, x1,y_lo,z0+P, x1,y_lo,z1-P,
						cam_x,cam_y,cam_z, ca,sa, wall_a,wall_b,wall_c,wall_d)
				end

				-- west face (inset z by P)
				if gx > 1 and row[gx-1] ~= 1 and vis[gy * 65536 + gx - 1] then
					try_quad(x0,y_hi,z0+P, x0,y_hi,z1-P, x0,y_lo,z1-P, x0,y_lo,z0+P,
						cam_x,cam_y,cam_z, ca,sa, wall_a,wall_b,wall_c,wall_d)
				end
			else
				-- open cell
				local x0 = (gx - 1) * CELL
				local x1 = gx * CELL

				if gx == dng.stairs_gx and gy == dng.stairs_gy then
					-- up-stairs: no floor, no ceiling (stairwell opening)
					render_stairs(x0, x1, z0, z1, y_lo, y_hi, dng.stairs_dir,
						cam_x, cam_y, cam_z, ca, sa, uv_a, uv_b, uv_c, uv_d, false)
				elseif dng.down_gx and gx == dng.down_gx and gy == dng.down_gy then
					-- down-stairs: descending steps, with ceiling
					render_stairs(x0, x1, z0, z1, y_lo, y_hi, dng.down_dir,
						cam_x, cam_y, cam_z, ca, sa, uv_a, uv_b, uv_c, uv_d, true)
					try_quad(x0,y_hi,z1, x1,y_hi,z1, x1,y_hi,z0, x0,y_hi,z0,
						cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 2)
				else
					-- normal floor
					try_quad(x0,y_lo,z0, x1,y_lo,z0, x1,y_lo,z1, x0,y_lo,z1,
						cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 1)
					-- ceiling
					try_quad(x0,y_hi,z1, x1,y_hi,z1, x1,y_hi,z0, x0,y_hi,z0,
						cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d, 2)
				end
			end
		end
	end

	-- pillars at grid intersections (wall corners bordering open space)
	for vy = gy0, gy1 + 1 do
		for vx = gx0, gx1 + 1 do
			-- check 4 cells around this vertex: nw(vx-1,vy-1) ne(vx,vy-1) sw(vx-1,vy) se(vx,vy)
			local nw_open = vx > 1 and vy > 1 and map[vy-1][vx-1] ~= 1
			local ne_open = vx <= dw and vy > 1 and map[vy-1][vx] ~= 1
			local sw_open = vx > 1 and vy <= dh and map[vy][vx-1] ~= 1
			local se_open = vx <= dw and vy <= dh and map[vy][vx] ~= 1

			local has_open = nw_open or ne_open or sw_open or se_open
			local has_wall = not (nw_open and ne_open and sw_open and se_open)

			if has_open and has_wall then
				-- visibility per cell
				local nw_vis = nw_open and vis[(vy-1)*65536+(vx-1)]
				local ne_vis = ne_open and vis[(vy-1)*65536+vx]
				local sw_vis = sw_open and vis[vy*65536+(vx-1)]
				local se_vis = se_open and vis[vy*65536+vx]

				if nw_vis or ne_vis or sw_vis or se_vis then
					local wx = (vx - 1) * CELL
					local wz = (vy - 1) * CELL

					-- per-face rendering: each face protrudes P into open space
					-- side faces act as steps connecting column to recessed wall

					-- south face at z=wz+P
					if sw_vis or se_vis then
						local fx0 = sw_open and wx - P or wx
						local fx1 = se_open and wx + P or wx
						if fx0 < fx1 then
							try_quad(fx0,y_hi,wz+P, fx1,y_hi,wz+P, fx1,y_lo,wz+P, fx0,y_lo,wz+P,
								cam_x,cam_y,cam_z, ca,sa, pil_a,pil_b,pil_c,pil_d, 3)
						end
					end

					-- north face at z=wz-P
					if nw_vis or ne_vis then
						local fx0 = nw_open and wx - P or wx
						local fx1 = ne_open and wx + P or wx
						if fx0 < fx1 then
							try_quad(fx1,y_hi,wz-P, fx0,y_hi,wz-P, fx0,y_lo,wz-P, fx1,y_lo,wz-P,
								cam_x,cam_y,cam_z, ca,sa, pil_a,pil_b,pil_c,pil_d, 3)
						end
					end

					-- east face at x=wx+P
					if ne_vis or se_vis then
						local fz0 = ne_open and wz - P or wz
						local fz1 = se_open and wz + P or wz
						if fz0 < fz1 then
							try_quad(wx+P,y_hi,fz1, wx+P,y_hi,fz0, wx+P,y_lo,fz0, wx+P,y_lo,fz1,
								cam_x,cam_y,cam_z, ca,sa, pil_a,pil_b,pil_c,pil_d, 3)
						end
					end

					-- west face at x=wx-P
					if nw_vis or sw_vis then
						local fz0 = nw_open and wz - P or wz
						local fz1 = sw_open and wz + P or wz
						if fz0 < fz1 then
							try_quad(wx-P,y_hi,fz0, wx-P,y_hi,fz1, wx-P,y_lo,fz1, wx-P,y_lo,fz0,
								cam_x,cam_y,cam_z, ca,sa, pil_a,pil_b,pil_c,pil_d, 3)
						end
					end
				end
			end
		end
	end

	profile(" geometry")

	Renderer.flush_with_fog()

	if rm > 0 then
		local rw, rh = RES_MODES[rm][1], RES_MODES[rm][2]
		set_draw_target()
		cls(0)
		Renderer.set_resolution(480, 270)
		sspr(res_bufs[rm], 0, 0, rw, rh, 0, 0, 480, 270)
	end
end
