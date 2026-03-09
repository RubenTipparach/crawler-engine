-- benchmark.lua
-- Sort algorithm benchmark with spinning cubes

Benchmark = {}

Benchmark.active = false
Benchmark.done = false
Benchmark.results = {}

-- cube mesh
local cube_verts = {
	{-1,-1,-1}, { 1,-1,-1}, { 1, 1,-1}, {-1, 1,-1},
	{-1,-1, 1}, { 1,-1, 1}, { 1, 1, 1}, {-1, 1, 1},
}
local cube_quads = {
	{1,2,3,4}, {6,5,8,7}, {5,1,4,8},
	{2,6,7,3}, {5,6,2,1}, {4,3,7,8},
}
local tv = {}
local sv = {}
for i=1,8 do tv[i]={0,0,0} sv[i]={0,0,0} end

-- cube positions in a ring
local num_cubes = 30
local cube_pos = {}
for i=1,num_cubes do
	local a = (i-1)/num_cubes
	cube_pos[i] = {cos(a)*4, sin(a*3)*1.5, sin(a)*4}
end

local ang_x, ang_y, ang_z = 0, 0, 0
local use_radix = false
local cam_z = 12

-- benchmark state
local bench_frames = 120
local bench_phase = 0
local frame_counter = 0
local warmup_frames = 30
local cpu_accum = 0
local cpu_samples = 0

local function transform_cube(ox, oy, oz)
	local sa, ca = sin(ang_x), cos(ang_x)
	local sb, cb = sin(ang_y), cos(ang_y)
	local sc, cc = sin(ang_z), cos(ang_z)
	local fov = Renderer.fov
	local cx, cy = Renderer.cx, Renderer.cy

	for i=1,8 do
		local v = cube_verts[i]
		local x,y,z = v[1], v[2], v[3]
		local x1 = x*cb + z*sb
		local z1 = -x*sb + z*cb
		local y1 = y*ca - z1*sa
		local z2 = y*sa + z1*ca
		local x2 = x1*cc - y1*sc
		local y2 = x1*sc + y1*cc
		x2 += ox  y2 += oy  z2 += oz

		tv[i][1] = x2
		tv[i][2] = y2
		tv[i][3] = z2

		local w = 1 / (z2 + cam_z)
		sv[i][1] = cx + x2 * fov * w
		sv[i][2] = cy + y2 * fov * w
		sv[i][3] = w
	end
end

local function render_cubes()
	Renderer.begin_frame()

	for ci=1,num_cubes do
		local p = cube_pos[ci]
		transform_cube(p[1], p[2], p[3])

		for fi=1,#cube_quads do
			local q = cube_quads[fi]
			local a,b,c,d = sv[q[1]], sv[q[2]], sv[q[3]], sv[q[4]]

			if Renderer.is_front(a,b,c) then
				local za = (tv[q[1]][3] + tv[q[2]][3] + tv[q[3]][3] + tv[q[4]][3]) * 0.25
				Renderer.submit_quad(
					{a[1],a[2],a[3]}, {b[1],b[2],b[3]},
					{c[1],c[2],c[3]}, {d[1],d[2],d[3]},
					Renderer.uvs_abc, Renderer.uvs_acd, za
				)
			end
		end
	end

	Renderer.flush(use_radix)
end

function Benchmark.start()
	Benchmark.active = true
	Benchmark.done = false
	Benchmark.results = {}
	bench_phase = 1
	frame_counter = 0
	cpu_accum = 0
	cpu_samples = 0
	ang_x, ang_y, ang_z = 0, 0, 0
end

function Benchmark.stop()
	Benchmark.active = false
	Benchmark.done = false
	bench_phase = 0
end

function Benchmark.update()
	if not Benchmark.active then return end

	ang_x += 0.002
	ang_y += 0.003
	ang_z += 0.001

	if keyp("escape") then
		Benchmark.stop()
		return "menu"
	end

	if bench_phase == 1 then
		use_radix = false
		frame_counter += 1
		if frame_counter >= warmup_frames then
			bench_phase = 2
			frame_counter = 0
			cpu_accum = 0
			cpu_samples = 0
		end
	elseif bench_phase == 2 then
		use_radix = false
		frame_counter += 1
		cpu_accum += stat(1)
		cpu_samples += 1
		if frame_counter >= bench_frames then
			Benchmark.results.qsort_cpu = cpu_accum / cpu_samples
			bench_phase = 3
			frame_counter = 0
			cpu_accum = 0
			cpu_samples = 0
		end
	elseif bench_phase == 3 then
		use_radix = true
		frame_counter += 1
		cpu_accum += stat(1)
		cpu_samples += 1
		if frame_counter >= bench_frames then
			Benchmark.results.radix_cpu = cpu_accum / cpu_samples
			Benchmark.results.tri_count = Renderer.tri_count
			Benchmark.results.num_cubes = num_cubes
			bench_phase = 4
			Benchmark.done = true
			Benchmark.active = false
		end
	end
end

function Benchmark.draw()
	if not Benchmark.active and not Benchmark.done then return end

	cls(0)
	render_cubes()

	-- progress bar
	if bench_phase >= 1 and bench_phase <= 3 then
		local phase_name = ({"warmup","qsort","radix"})[bench_phase]
		local total = bench_phase == 1 and warmup_frames or bench_frames
		rectfill(0, 250, 479, 269, 1)
		print("benchmarking: "..phase_name.."  ["..frame_counter.."/"..total.."]  [esc] cancel", 2, 254, 10)
	end

	-- hud
	local sort_name = use_radix and "radix" or "qsort"
	print("cpu: "..tostr(flr(stat(1)*1000)/10).."%  sort: "..sort_name, 2, 2, 7)
	print("tris: "..Renderer.tri_count.."  cubes: "..num_cubes, 2, 12, 7)

	-- results
	if Benchmark.done then
		local r = Benchmark.results
		local qc = tostr(flr(r.qsort_cpu*1000)/10)
		local rc = tostr(flr(r.radix_cpu*1000)/10)
		rectfill(80, 80, 400, 180, 1)
		rect(80, 80, 400, 180, 6)
		print("benchmark results ("..r.num_cubes.." cubes, "..r.tri_count.." tris)", 90, 90, 7)
		print("quicksort avg cpu: "..qc.."%", 90, 110, 11)
		print("radix sort avg cpu: "..rc.."%", 90, 125, 11)
		local diff = r.radix_cpu - r.qsort_cpu
		local winner = diff < 0 and "radix" or "qsort"
		local pct = tostr(flr(abs(diff)/max(r.qsort_cpu,r.radix_cpu)*1000)/10)
		print(winner.." wins by "..pct.."%", 90, 145, 10)
		print("[esc] back to menu", 90, 165, 5)
	end
end
