-- renderer.lua
-- General-purpose 3D rendering pipeline: camera, textri, sorting

Renderer = {}

Renderer.fov = 240
Renderer.cx, Renderer.cy = 240, 135
Renderer.screen_h = 270
Renderer.tri_count = 0
Renderer.near = 0.1

-- textri buffers (pre-allocated, reused)
local scanlines = userdata("f64", 11, 270)
local vpool = userdata("f64", 6, 3)

-- draw list
local draw_list = {}
local dl_n = 0

-- uv presets (16x16 sprite, tiled 4x4 via UV wrapping)
local s = 64
Renderer.uvs_abc = {{0,0},{s,0},{s,s}}
Renderer.uvs_acd = {{0,0},{s,s},{0,s}}

--- draw list API ---

function Renderer.begin_frame()
	dl_n = 0
	Renderer.tri_count = 0
end

function Renderer.submit_tri(
	pax,pay,paw, pbx,pby,pbw, pcx,pcy,pcw,
	su1,sv1, su2,sv2, su3,sv3, depth, base_spr
)
	dl_n += 1
	local e = draw_list[dl_n]
	if not e then e = {} draw_list[dl_n] = e end
	e.ax = pax  e.ay = pay  e.aw = paw
	e.bx = pbx  e.by = pby  e.bw = pbw
	e.cx = pcx  e.cy = pcy  e.cw = pcw
	e.u1 = su1  e.v1 = sv1
	e.u2 = su2  e.v2 = sv2
	e.u3 = su3  e.v3 = sv3
	e.d = depth
	e.spr = base_spr or 0
end

function Renderer.submit_quad(sa, sb, sc, sd, uvs_t1, uvs_t2, depth)
	Renderer.submit_tri(
		sa[1],sa[2],sa[3], sb[1],sb[2],sb[3], sc[1],sc[2],sc[3],
		uvs_t1[1][1],uvs_t1[1][2], uvs_t1[2][1],uvs_t1[2][2], uvs_t1[3][1],uvs_t1[3][2], depth
	)
	Renderer.submit_tri(
		sa[1],sa[2],sa[3], sc[1],sc[2],sc[3], sd[1],sd[2],sd[3],
		uvs_t2[1][1],uvs_t2[1][2], uvs_t2[2][1],uvs_t2[2][2], uvs_t2[3][1],uvs_t2[3][2], depth
	)
end

function Renderer.flush(use_radix)
	if dl_n > 1 then
		if use_radix then
			radix_sort(draw_list, dl_n)
		else
			quicksort(draw_list, 1, dl_n)
		end
	end
	for i=1,dl_n do
		Renderer.textri(0, draw_list[i])
		Renderer.tri_count += 1
	end
end

-- flush geometry + fog using painter's algorithm (back-to-front).
-- fog overlays are color-tinted rectangles at fixed depth thresholds.
-- they are interleaved with sorted geometry so that:
--   - far tris get painted BEFORE fog rects → fog darkens them
--   - near tris get painted AFTER fog rects → they stay bright
-- this creates depth-based fog without per-pixel depth testing.
function Renderer.flush_with_fog()
	local fog = Config.fog
	local n = #fog.colors       -- number of fog depth levels
	local starts = fog.start    -- depth threshold per level (ascending)
	local dither = fog.dither   -- "bayer", "floyd", or "none"
	local textures = dither == "floyd" and fog.tex_floyd or fog.tex_bayer

	-- sort all geometry back-to-front (descending depth)
	if dl_n > 1 then
		quicksort(draw_list, 1, dl_n)
	end

	local ct = get_spr(fog.spr) -- color table sprite for tinting
	local fov = Renderer.fov
	local cy = Renderer.cy
	local sw = Renderer.cx * 2 - 1  -- screen width
	local sh = Renderer.screen_h - 1 -- screen height

	-- walk fog planes from farthest (n) to nearest (1).
	-- fi tracks the next fog plane to insert.
	local fi = n

	-- main loop: draw each tri in back-to-front order.
	-- before each tri, check if any fog planes sit between
	-- the previous tri's depth and this tri's depth.
	for i = 1, dl_n do
		local d = draw_list[i].d

		-- draw any fog planes that are farther than this tri.
		-- a fog rect at depth starts[fi] darkens everything
		-- already drawn (which is all farther geometry).
		while fi >= 1 and d < starts[fi] do
			-- rect height = fov / depth (perspective projection)
			local ht = fov / starts[fi]
			local top = mid(0, cy - ht, sh)
			local bot = mid(0, cy + ht, sh)

			memmap(0x8000, ct)    -- map color table to draw palette
			poke(0x550b, 0x3f)   -- enable color remapping
			if dither ~= "none" and textures then
				palt(0, true)
				sspr(textures[fi], 0, top, sw + 1, bot - top + 1, 0, top, sw + 1, bot - top + 1)
				palt(0, false)
			else
				rectfill(0, top, sw, bot, fog.colors[fi])
			end
			unmap(ct)
			poke(0x550b, 0x00)   -- disable color remapping

			fi -= 1
		end

		-- draw the tri (on top of any fog rects just placed)
		Renderer.textri(draw_list[i].spr, draw_list[i])
		Renderer.tri_count += 1
	end

	-- any fog planes nearer than ALL geometry still need drawing.
	-- (rare: only if fog thresholds are closer than the nearest tri)
	while fi >= 1 do
		local ht = fov / starts[fi]
		local top = mid(0, cy - ht, sh)
		local bot = mid(0, cy + ht, sh)

		memmap(0x8000, ct)
		poke(0x550b, 0x3f)
		if dither ~= "none" and textures then
			palt(0, true)
			sspr(textures[fi], 0, top, sw + 1, bot - top + 1, 0, top, sw + 1, bot - top + 1)
			palt(0, false)
		else
			rectfill(0, top, sw, bot, fog.colors[fi])
		end
		unmap(ct)
		poke(0x550b, 0x00)

		fi -= 1
	end
end

-- switch resolution (updates projection constants)
function Renderer.set_resolution(w, h)
	Renderer.cx = w / 2
	Renderer.cy = h / 2
	Renderer.fov = w / 2
	Renderer.screen_h = h
end

--- camera: transform world point to screen ---

-- transform world→view space (no rejection)
function Renderer.to_view(wx, wy, wz, cam_x, cam_y, cam_z, ca, sa)
	local dx = wx - cam_x
	local dy = wy - cam_y
	local dz = wz - cam_z
	return dx * ca - dz * sa, dy, -dx * sa - dz * ca
end

-- project view-space point to screen (returns nil if behind near plane)
function Renderer.project_view(vx, vy, vz)
	if vz < Renderer.near then return nil end
	local w = 1 / vz
	local fov = Renderer.fov
	return {
		Renderer.cx + vx * fov * w,
		Renderer.cy - vy * fov * w,
		w
	}, vz
end

-- convenience: world→screen (used by benchmark etc)
function Renderer.project(wx, wy, wz, cam_x, cam_y, cam_z, ca, sa)
	local vx, vy, vz = Renderer.to_view(wx, wy, wz, cam_x, cam_y, cam_z, ca, sa)
	return Renderer.project_view(vx, vy, vz)
end

--- vectorized textri ---

function Renderer.textri(spr_idx, e)
	vpool[0],vpool[1],vpool[3],vpool[4],vpool[5] = e.ax,e.ay,e.aw,e.u1,e.v1
	vpool[6],vpool[7],vpool[9],vpool[10],vpool[11] = e.bx,e.by,e.bw,e.u2,e.v2
	vpool[12],vpool[13],vpool[15],vpool[16],vpool[17] = e.cx,e.cy,e.cw,e.u3,e.v3
	vpool[2],vpool[8],vpool[14] = 0,0,0

	vpool:sort(1)

	local x1,y1,w1, y2,w2, x3,y3,w3 =
		vpool[0],vpool[1],vpool[3],
		vpool[7],vpool[9],
		vpool[12],vpool[13],vpool[15]

	if y3 == y1 then return end

	local uv_top = vec(vpool[4],vpool[5])*w1
	local uv_bot = vec(vpool[16],vpool[17])*w3

	local t = (y2-y1)/(y3-y1)
	local uvd = (uv_bot-uv_top)*t+uv_top

	local v1 = vec(spr_idx,x1,y1,x1,y1, uv_top.x,uv_top.y, uv_top.x,uv_top.y, w1,w1)
	local v2 = vec(
		spr_idx,
		vpool[6],y2,
		(x3-x1)*t+x1, y2,
		vpool[10]*w2, vpool[11]*w2,
		uvd.x, uvd.y,
		w2, (w3-w1)*t+w1
	)

	local y_max = Renderer.screen_h - 1
	local start_y = y1 < -1 and -1 or y1\1
	local mid_y   = y2 < -1 and -1 or y2 > y_max and y_max or y2\1
	local stop_y  = y3 <= y_max and y3\1 or y_max

	local dy = mid_y - start_y
	if dy > 0 then
		local slope = (v2-v1):div(y2-y1)
		scanlines:copy(slope*(start_y+1-y1)+v1, true, 0,0,11)
			:copy(slope, true, 0,11,11, 0,11,dy-1)
		tline3d(scanlines:add(scanlines, true, 0,11,11, 11,11,dy-1), 0, dy)
	end

	local v3 = vec(spr_idx,x3,y3,x3,y3, uv_bot.x,uv_bot.y, uv_bot.x,uv_bot.y, w3,w3)
	dy = stop_y - mid_y
	if dy > 0 then
		local slope = (v3-v2):div(y3-y2)
		scanlines:copy(slope*(mid_y+1-y2)+v2, true, 0,0,11)
			:copy(slope, true, 0,11,11, 0,11,dy-1)
		tline3d(scanlines:add(scanlines, true, 0,11,11, 11,11,dy-1), 0, dy)
	end
end

-- backface cull (screen-space cross product, >0 = facing camera)
function Renderer.is_front(a,b,c)
	return (b[1]-a[1])*(c[2]-a[2]) - (b[2]-a[2])*(c[1]-a[1]) > 0
end

--- sorting ---

local function insertion_sort(t, lo, hi)
	for i = lo+1, hi do
		local key = t[i]
		local kd = key.d
		local j = i-1
		while j >= lo and t[j].d < kd do
			t[j+1] = t[j]
			j -= 1
		end
		t[j+1] = key
	end
end

function quicksort(t, lo, hi)
	while lo < hi do
		if hi - lo < 16 then
			insertion_sort(t, lo, hi)
			return
		end
		local pivot = t[hi].d
		local i = lo - 1
		for j = lo, hi-1 do
			if t[j].d >= pivot then
				i += 1
				t[i], t[j] = t[j], t[i]
			end
		end
		i += 1
		t[i], t[hi] = t[hi], t[i]
		if i - lo < hi - i then
			quicksort(t, lo, i-1)
			lo = i+1
		else
			quicksort(t, i+1, hi)
			hi = i-1
		end
	end
end

local radix_buckets = {}
local radix_tmp = {}
for i=0,255 do radix_buckets[i] = 0 end

function radix_sort(t, n)
	if n <= 1 then return end
	local dmin, dmax = t[1].d, t[1].d
	for i=2,n do
		local d = t[i].d
		if d < dmin then dmin = d end
		if d > dmax then dmax = d end
	end
	if dmax == dmin then return end

	local scale = 255 / (dmax - dmin)
	for i=0,255 do radix_buckets[i] = 0 end
	for i=1,n do
		local b = (t[i].d - dmin) * scale \ 1
		if b > 255 then b = 255 end
		radix_buckets[b] += 1
		radix_tmp[i] = t[i]
		radix_tmp[i]._rb = b
	end

	local offsets = {}
	offsets[255] = 1
	for i=254,0,-1 do
		offsets[i] = offsets[i+1] + radix_buckets[i+1]
	end

	for i=1,n do
		local b = radix_tmp[i]._rb
		t[offsets[b]] = radix_tmp[i]
		offsets[b] += 1
	end
end
