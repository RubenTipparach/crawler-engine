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

-- UV set lookup for cached geometry
local uv_sets = {
	{uv_a, uv_b, uv_c, uv_d},       -- 1: floor/ceiling/stairs
	{wall_a, wall_b, wall_c, wall_d}, -- 2: walls
	{pil_a, pil_b, pil_c, pil_d},     -- 3: pillars
}

-- cached renderer fields (updated per-frame, avoids table lookups in hot loop)
local r_fov, r_cx, r_cy, r_sh

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

		local z_sum = 0
		for i = 1, cn do
			local v = clipped[i]
			local w = 1 / v[3]
			v[6] = r_cx + v[1] * r_fov * w
			v[7] = r_cy - v[2] * r_fov * w
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
	local wa = 1/va_z
	local pax, pay = r_cx + va_x*r_fov*wa, r_cy - dya*r_fov*wa
	local wb = 1/vb_z
	local pbx, pby = r_cx + vb_x*r_fov*wb, r_cy - dyb*r_fov*wb
	local wc = 1/vc_z
	local pcx, pcy = r_cx + vc_x*r_fov*wc, r_cy - dyc*r_fov*wc
	local wd = 1/vd_z
	local pdx, pdy = r_cx + vd_x*r_fov*wd, r_cy - dyd*r_fov*wd

	if (pbx-pax)*(pcy-pay) - (pby-pay)*(pcx-pax) <= 0 then return end

	local depth = (va_z+vb_z+vc_z+vd_z)*0.25

	Renderer.submit_tri(pax,pay,wa, pbx,pby,wb, pcx,pcy,wc,
		uv_a[1],uv_a[2], uv_b[1],uv_b[2], uv_c[1],uv_c[2], depth, base_spr)
	Renderer.submit_tri(pax,pay,wa, pcx,pcy,wc, pdx,pdy,wd,
		uv_a[1],uv_a[2], uv_c[1],uv_c[2], uv_d[1],uv_d[2], depth, base_spr)
end

-- cached geometry helpers
local NUM_STEPS = 10

local function add_q(list, ax,ay,az, bx,by,bz, cx,cy,cz, dx,dy,dz, uv_idx, spr, adj_key)
	list[#list+1] = {ax,ay,az, bx,by,bz, cx,cy,cz, dx,dy,dz, uv_idx, spr or 0, adj_key}
end

local function cache_stairs(list, x0, x1, z0, z1, y_lo, y_hi, dir, going_down)
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

		if dir == 0 then
			local sz0 = z1 - (i + 1) * step_d
			local sz1 = z1 - i * step_d
			add_q(list, x0,tread_y,sz0, x1,tread_y,sz0, x1,tread_y,sz1, x0,tread_y,sz1, 1, 4)
			add_q(list, x0,riser_top,sz1, x1,riser_top,sz1, x1,riser_bot,sz1, x0,riser_bot,sz1, 1, 5)
		elseif dir == 1 then
			local sx0 = x0 + i * step_d
			local sx1 = x0 + (i + 1) * step_d
			add_q(list, sx0,tread_y,z0, sx1,tread_y,z0, sx1,tread_y,z1, sx0,tread_y,z1, 1, 4)
			add_q(list, sx0,riser_top,z0, sx0,riser_top,z1, sx0,riser_bot,z1, sx0,riser_bot,z0, 1, 5)
		elseif dir == 2 then
			local sz0 = z0 + i * step_d
			local sz1 = z0 + (i + 1) * step_d
			add_q(list, x0,tread_y,sz0, x1,tread_y,sz0, x1,tread_y,sz1, x0,tread_y,sz1, 1, 4)
			add_q(list, x1,riser_top,sz0, x0,riser_top,sz0, x0,riser_bot,sz0, x1,riser_bot,sz0, 1, 5)
		elseif dir == 3 then
			local sx0 = x1 - (i + 1) * step_d
			local sx1 = x1 - i * step_d
			add_q(list, sx0,tread_y,z0, sx1,tread_y,z0, sx1,tread_y,z1, sx0,tread_y,z1, 1, 4)
			add_q(list, sx1,riser_top,z1, sx1,riser_top,z0, sx1,riser_bot,z0, sx1,riser_bot,z1, 1, 5)
		end
	end

	if going_down then return end

	for i = 0, NUM_STEPS - 1 do
		local tread_y_i = y_lo + (i + 1) * step_h
		local side_top = tread_y_i
		local side_bot = y_lo

		if dir == 0 then
			local sz0 = z1 - (i + 1) * step_d
			local sz1 = z1 - i * step_d
			add_q(list, x0,side_top,sz0, x0,side_top,sz1, x0,side_bot,sz1, x0,side_bot,sz0, 1, 5)
			add_q(list, x1,side_top,sz1, x1,side_top,sz0, x1,side_bot,sz0, x1,side_bot,sz1, 1, 5)
		elseif dir == 1 then
			local sx0 = x0 + i * step_d
			local sx1 = x0 + (i + 1) * step_d
			add_q(list, sx1,side_top,z0, sx0,side_top,z0, sx0,side_bot,z0, sx1,side_bot,z0, 1, 5)
			add_q(list, sx0,side_top,z1, sx1,side_top,z1, sx1,side_bot,z1, sx0,side_bot,z1, 1, 5)
		elseif dir == 2 then
			local sz0 = z0 + i * step_d
			local sz1 = z0 + (i + 1) * step_d
			add_q(list, x0,side_top,sz0, x0,side_top,sz1, x0,side_bot,sz1, x0,side_bot,sz0, 1, 5)
			add_q(list, x1,side_top,sz1, x1,side_top,sz0, x1,side_bot,sz0, x1,side_bot,sz1, 1, 5)
		elseif dir == 3 then
			local sx0 = x1 - (i + 1) * step_d
			local sx1 = x1 - i * step_d
			add_q(list, sx1,side_top,z0, sx0,side_top,z0, sx0,side_bot,z0, sx1,side_bot,z0, 1, 5)
			add_q(list, sx0,side_top,z1, sx1,side_top,z1, sx1,side_bot,z1, sx0,side_bot,z1, 1, 5)
		end
	end

	local y_bot = y_lo
	local y_top = y_hi
	if dir == 0 then
		add_q(list, x1,y_top,z0, x0,y_top,z0, x0,y_bot,z0, x1,y_bot,z0, 1, 5)
	elseif dir == 1 then
		add_q(list, x1,y_top,z1, x1,y_top,z0, x1,y_bot,z0, x1,y_bot,z1, 1, 5)
	elseif dir == 2 then
		add_q(list, x0,y_top,z1, x1,y_top,z1, x1,y_bot,z1, x0,y_bot,z1, 1, 5)
	elseif dir == 3 then
		add_q(list, x0,y_top,z0, x0,y_top,z1, x0,y_bot,z1, x0,y_bot,z0, 1, 5)
	end
end

-- build static geometry cache (called once per dungeon)
function DungeonView.build_geo_cache(dng)
	local map = dng.map
	local dw, dh = dng.w, dng.h
	local y_hi, y_lo = HALF, -HALF
	local cell_geo = {}

	for gy = 1, dh do
		local row = map[gy]
		local z0 = (gy - 1) * CELL
		local z1 = gy * CELL

		for gx = 1, dw do
			local key = gy * 65536 + gx
			local quads = {}

			if row[gx] == 1 then
				local x0 = (gx - 1) * CELL
				local x1 = gx * CELL
				-- south face
				if gy < dh and map[gy+1][gx] ~= 1 then
					add_q(quads, x0+P,y_hi,z1, x1-P,y_hi,z1, x1-P,y_lo,z1, x0+P,y_lo,z1, 2, 0, (gy+1)*65536+gx)
				end
				-- north face
				if gy > 1 and map[gy-1][gx] ~= 1 then
					add_q(quads, x1-P,y_hi,z0, x0+P,y_hi,z0, x0+P,y_lo,z0, x1-P,y_lo,z0, 2, 0, (gy-1)*65536+gx)
				end
				-- east face
				if gx < dw and row[gx+1] ~= 1 then
					add_q(quads, x1,y_hi,z1-P, x1,y_hi,z0+P, x1,y_lo,z0+P, x1,y_lo,z1-P, 2, 0, gy*65536+gx+1)
				end
				-- west face
				if gx > 1 and row[gx-1] ~= 1 then
					add_q(quads, x0,y_hi,z0+P, x0,y_hi,z1-P, x0,y_lo,z1-P, x0,y_lo,z0+P, 2, 0, gy*65536+gx-1)
				end
			else
				local x0 = (gx - 1) * CELL
				local x1 = gx * CELL

				if gx == dng.stairs_gx and gy == dng.stairs_gy then
					cache_stairs(quads, x0, x1, z0, z1, y_lo, y_hi, dng.stairs_dir, false)
				elseif dng.down_gx and gx == dng.down_gx and gy == dng.down_gy then
					cache_stairs(quads, x0, x1, z0, z1, y_lo, y_hi, dng.down_dir, true)
					add_q(quads, x0,y_hi,z1, x1,y_hi,z1, x1,y_hi,z0, x0,y_hi,z0, 1, 2)
				else
					add_q(quads, x0,y_lo,z0, x1,y_lo,z0, x1,y_lo,z1, x0,y_lo,z1, 1, 1)
					add_q(quads, x0,y_hi,z1, x1,y_hi,z1, x1,y_hi,z0, x0,y_hi,z0, 1, 2)
				end
			end

			if #quads > 0 then
				cell_geo[key] = quads
			end
		end
	end

	-- pillars at grid intersections
	local pillar_geo = {}
	for vy = 1, dh + 1 do
		for vx = 1, dw + 1 do
			local nw_open = vx > 1 and vy > 1 and map[vy-1][vx-1] ~= 1
			local ne_open = vx <= dw and vy > 1 and map[vy-1][vx] ~= 1
			local sw_open = vx > 1 and vy <= dh and map[vy][vx-1] ~= 1
			local se_open = vx <= dw and vy <= dh and map[vy][vx] ~= 1

			local has_open = nw_open or ne_open or sw_open or se_open
			local has_wall = not (nw_open and ne_open and sw_open and se_open)

			if has_open and has_wall then
				local wx = (vx - 1) * CELL
				local wz = (vy - 1) * CELL

				-- south face
				if sw_open or se_open then
					local fx0 = sw_open and wx - P or wx
					local fx1 = se_open and wx + P or wx
					if fx0 < fx1 then
						local vk = {}
						if sw_open then vk[#vk+1] = vy*65536+(vx-1) end
						if se_open then vk[#vk+1] = vy*65536+vx end
						pillar_geo[#pillar_geo+1] = {fx0,y_hi,wz+P, fx1,y_hi,wz+P, fx1,y_lo,wz+P, fx0,y_lo,wz+P, 3, 3, vk=vk, gx=vx, gy=vy}
					end
				end

				-- north face
				if nw_open or ne_open then
					local fx0 = nw_open and wx - P or wx
					local fx1 = ne_open and wx + P or wx
					if fx0 < fx1 then
						local vk = {}
						if nw_open then vk[#vk+1] = (vy-1)*65536+(vx-1) end
						if ne_open then vk[#vk+1] = (vy-1)*65536+vx end
						pillar_geo[#pillar_geo+1] = {fx1,y_hi,wz-P, fx0,y_hi,wz-P, fx0,y_lo,wz-P, fx1,y_lo,wz-P, 3, 3, vk=vk, gx=vx, gy=vy}
					end
				end

				-- east face
				if ne_open or se_open then
					local fz0 = ne_open and wz - P or wz
					local fz1 = se_open and wz + P or wz
					if fz0 < fz1 then
						local vk = {}
						if ne_open then vk[#vk+1] = (vy-1)*65536+vx end
						if se_open then vk[#vk+1] = vy*65536+vx end
						pillar_geo[#pillar_geo+1] = {wx+P,y_hi,fz1, wx+P,y_hi,fz0, wx+P,y_lo,fz0, wx+P,y_lo,fz1, 3, 3, vk=vk, gx=vx, gy=vy}
					end
				end

				-- west face
				if nw_open or sw_open then
					local fz0 = nw_open and wz - P or wz
					local fz1 = sw_open and wz + P or wz
					if fz0 < fz1 then
						local vk = {}
						if nw_open then vk[#vk+1] = (vy-1)*65536+(vx-1) end
						if sw_open then vk[#vk+1] = vy*65536+(vx-1) end
						pillar_geo[#pillar_geo+1] = {wx-P,y_hi,fz0, wx-P,y_hi,fz1, wx-P,y_lo,fz1, wx-P,y_lo,fz0, 3, 3, vk=vk, gx=vx, gy=vy}
					end
				end
			end
		end
	end

	dng.cell_geo = cell_geo
	dng.pillar_geo = pillar_geo
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

	-- cache renderer fields as upvalues for try_quad
	r_fov = Renderer.fov
	r_cx = Renderer.cx
	r_cy = Renderer.cy
	r_sh = Renderer.screen_h

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
	local dw, dh = dng.w, dng.h

	-- build visibility from player position
	profile(" visibility")
	build_visibility(cam_x, cam_z, ca, sa, map, dw, dh)
	profile(" visibility")

	-- build geometry cache on first draw
	if not dng.cell_geo then
		DungeonView.build_geo_cache(dng)
	end
	local cell_geo = dng.cell_geo
	local pillar_geo = dng.pillar_geo

	profile(" geometry")
	-- submit cached cell quads
	for gy = gy0, gy1 do
		for gx = gx0, gx1 do
			local key = gy * 65536 + gx
			if vis[key] then
				local quads = cell_geo[key]
				if quads then
					for i = 1, #quads do
						local q = quads[i]
						local adj = q[15]
						if not adj or vis[adj] then
							local uvs = uv_sets[q[13]]
							try_quad(
								q[1],q[2],q[3], q[4],q[5],q[6], q[7],q[8],q[9], q[10],q[11],q[12],
								cam_x,cam_y,cam_z, ca,sa, uvs[1],uvs[2],uvs[3],uvs[4], q[14]
							)
						end
					end
				end
			end
		end
	end

	-- submit cached pillar quads (spatial filter by render radius)
	for i = 1, #pillar_geo do
		local p = pillar_geo[i]
		local pvx, pvy = p.gx, p.gy
		if pvx >= gx0 and pvx <= gx1+1 and pvy >= gy0 and pvy <= gy1+1 then
			local vk = p.vk
			local visible = false
			for j = 1, #vk do
				if vis[vk[j]] then visible = true break end
			end
			if visible then
				local uvs = uv_sets[p[13]]
				try_quad(
					p[1],p[2],p[3], p[4],p[5],p[6], p[7],p[8],p[9], p[10],p[11],p[12],
					cam_x,cam_y,cam_z, ca,sa, uvs[1],uvs[2],uvs[3],uvs[4], p[14]
				)
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
