-- dungeon_view.lua
-- voxel-style dungeon renderer with near-plane clipping + occlusion culling

DungeonView = {}

local CELL = 2
local HALF = CELL / 2
local RENDER_R = 7
local NEAR = 0.1
local NUM_RAYS = 120

-- half-res render target
local HALF_W, HALF_H = 240, 135
local half_buf = userdata("u8", HALF_W, HALF_H)
DungeonView.half_res = true  -- toggle with M key

-- pre-allocated clip buffers (zero per-frame allocations)
local _cv = {}
local _co = {}
for i=1,8 do
	_cv[i] = {0,0,0,0,0,0,0,0}
	_co[i] = {0,0,0,0,0,0,0,0}
end

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
	cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d
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
				c1[4],c1[5], vi[4],vi[5], vi1[4],vi1[5], depth
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
		uv_a[1],uv_a[2], uv_b[1],uv_b[2], uv_c[1],uv_c[2], depth)
	Renderer.submit_tri(pax,pay,wa, pcx,pcy,wc, pdx,pdy,wd,
		uv_a[1],uv_a[2], uv_c[1],uv_c[2], uv_d[1],uv_d[2], depth)
end

-- DDA raycast through grid, marking visible open cells
local vis = {}

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

	for r = 0, NUM_RAYS do
		local t = (r / NUM_RAYS) * 2 - 1
		local rdx = fwd_x + rt_x * t
		local rdz = fwd_z + rt_z * t

		-- DDA setup
		local gx = flr(gpx)
		local gz = flr(gpz)
		local sx = rdx >= 0 and 1 or -1
		local sz = rdz >= 0 and 1 or -1
		local idx = rdx ~= 0 and abs(1 / rdx) or 32000
		local idz = rdz ~= 0 and abs(1 / rdz) or 32000
		local tx = rdx >= 0 and (gx + 1 - gpx) * idx or (gpx - gx) * idx
		local tz = rdz >= 0 and (gz + 1 - gpz) * idz or (gpz - gz) * idz

		for _ = 1, max_steps do
			local mgx = gx + 1  -- 1-based
			local mgz = gz + 1
			if mgx < 1 or mgx > dw or mgz < 1 or mgz > dh then break end

			if map[mgz][mgx] == 1 then
				-- hit wall: mark it so its faces get rendered, then stop
				vis[mgz * 65536 + mgx] = true
				break
			end

			-- mark open cell as visible
			vis[mgz * 65536 + mgx] = true

			if tx < tz then
				gx += sx
				tx += idx
			else
				gz += sz
				tz += idz
			end
		end
	end
end

function DungeonView.draw(dng, player)
	if keyp("m") then DungeonView.half_res = not DungeonView.half_res end

	if DungeonView.half_res then
		Renderer.set_resolution(HALF_W, HALF_H)
		set_draw_target(half_buf)
	else
		Renderer.set_resolution(480, 270)
	end
	cls(0)
	Renderer.begin_frame()

	local cam_x = player.x
	local cam_y = 0
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
	build_visibility(cam_x, cam_z, ca, sa, map, dw, dh)

	-- quad corner UVs
	local s = 64
	local uv_a = {0, 0}
	local uv_b = {s, 0}
	local uv_c = {s, s}
	local uv_d = {0, s}

	for gy = gy0, gy1 do
		local row = map[gy]
		local z0 = (gy - 1) * CELL
		local z1 = gy * CELL

		for gx = gx0, gx1 do
			if row[gx] == 1 and vis[gy * 65536 + gx] then
				local x0 = (gx - 1) * CELL
				local x1 = gx * CELL

				-- south face: render if neighbor to south is open AND visible
				if gy < dh and map[gy+1][gx] ~= 1 and vis[(gy+1) * 65536 + gx] then
					try_quad(x0,y_hi,z1, x1,y_hi,z1, x1,y_lo,z1, x0,y_lo,z1,
						cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d)
				end

				-- north face
				if gy > 1 and map[gy-1][gx] ~= 1 and vis[(gy-1) * 65536 + gx] then
					try_quad(x1,y_hi,z0, x0,y_hi,z0, x0,y_lo,z0, x1,y_lo,z0,
						cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d)
				end

				-- east face
				if gx < dw and row[gx+1] ~= 1 and vis[gy * 65536 + gx + 1] then
					try_quad(x1,y_hi,z1, x1,y_hi,z0, x1,y_lo,z0, x1,y_lo,z1,
						cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d)
				end

				-- west face
				if gx > 1 and row[gx-1] ~= 1 and vis[gy * 65536 + gx - 1] then
					try_quad(x0,y_hi,z0, x0,y_hi,z1, x0,y_lo,z1, x0,y_lo,z0,
						cam_x,cam_y,cam_z, ca,sa, uv_a,uv_b,uv_c,uv_d)
				end
			end
		end
	end

	-- pillars at grid intersections (wall corners bordering open space)
	local P = CELL / 8  -- pillar half-width
	local pil_s = 16  -- 1 tile width for narrow pillar face
	local pil_a = {0, 0}
	local pil_b = {pil_s, 0}
	local pil_c = {pil_s, s}
	local pil_d = {0, s}

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
					local px0, px1 = wx - P, wx + P
					local pz0, pz1 = wz - P, wz + P

					-- only render faces facing open visible cells
					if sw_vis or se_vis then -- south face
						try_quad(px0,y_hi,pz1, px1,y_hi,pz1, px1,y_lo,pz1, px0,y_lo,pz1,
							cam_x,cam_y,cam_z, ca,sa, pil_a,pil_b,pil_c,pil_d)
					end
					if nw_vis or ne_vis then -- north face
						try_quad(px1,y_hi,pz0, px0,y_hi,pz0, px0,y_lo,pz0, px1,y_lo,pz0,
							cam_x,cam_y,cam_z, ca,sa, pil_a,pil_b,pil_c,pil_d)
					end
					if ne_vis or se_vis then -- east face
						try_quad(px1,y_hi,pz1, px1,y_hi,pz0, px1,y_lo,pz0, px1,y_lo,pz1,
							cam_x,cam_y,cam_z, ca,sa, pil_a,pil_b,pil_c,pil_d)
					end
					if nw_vis or sw_vis then -- west face
						try_quad(px0,y_hi,pz0, px0,y_hi,pz1, px0,y_lo,pz1, px0,y_lo,pz0,
							cam_x,cam_y,cam_z, ca,sa, pil_a,pil_b,pil_c,pil_d)
					end
				end
			end
		end
	end

	Renderer.flush_with_fog(4)

	if DungeonView.half_res then
		set_draw_target()
		cls(0)
		Renderer.set_resolution(480, 270)
		sspr(half_buf, 0, 0, HALF_W, HALF_H, 0, 0, 480, 270)
	end
end
