-- space_crawler - 3d dungeon crawler
-- grid-based movement, textured walls via vectorized textri

include("config.lua")
include("profiler.lua")
include("renderer.lua")
include("dungeon.lua")
include("dungeon_generator.lua")
include("player.lua")
include("dungeon_view.lua")
include("benchmark.lua")
include("menu.lua")
include("ui.lua")
include("game.lua")


function _init()
	-- generate wall texture if sprite 0 is blank
	local sp = get_spr(0)
	local blank = true
	for py=0,7 do
		for px=0,7 do
			if sp:get(px,py) ~= 0 then blank = false break end
		end
		if not blank then break end
	end
	if blank then
		local tex = userdata("u8",16,16)
		for py=0,15 do
			for px=0,15 do
				-- 4x4 brick pattern: each sub-tile is 4x4 pixels
				local c = 12
				if (flr(px/2)+flr(py/2)) % 2 == 0 then c = 7 end
				-- grid lines every 4 pixels
				if px%4==0 or py%4==0 then c=6 end
				-- shadow edges
				if px%4==3 or py%4==3 then c=5 end
				tex:set(px,py,c)
			end
		end
		set_spr(0, tex)
	end

	-- generate stair tread texture (sprite 4): solid flat color
	local sp4 = get_spr(4)
	local blank4 = true
	for py=0,7 do
		for px=0,7 do
			if sp4:get(px,py) ~= 0 then blank4 = false break end
		end
		if not blank4 then break end
	end
	if blank4 then
		local tex = userdata("u8",16,16)
		for py=0,15 do
			for px=0,15 do
				tex:set(px,py,6) -- solid grey
			end
		end
		set_spr(4, tex)
	end

	-- generate stair riser texture (sprite 5): dithered dark
	local sp5 = get_spr(5)
	local blank5 = true
	for py=0,7 do
		for px=0,7 do
			if sp5:get(px,py) ~= 0 then blank5 = false break end
		end
		if not blank5 then break end
	end
	if blank5 then
		local tex = userdata("u8",16,16)
		for py=0,15 do
			for px=0,15 do
				tex:set(px,py,5) -- solid dark grey
			end
		end
		set_spr(5, tex)
	end

	-- spr 1 = floor, spr 2 = ceiling, spr 3 = column (hand-drawn in sprite editor)

	-- generate fog dither textures (bayer + floyd-steinberg)
	generate_fog_textures()
	Renderer.fog_ct = get_spr(Config.fog.spr)
end

local function draw_loading(step, total, label)
	cls(0)
	local bx, by, bw, bh = 140, 125, 200, 20
	rect(bx, by, bx + bw, by + bh, 6)
	local fill_w = flr(bw * step / total)
	if fill_w > 0 then
		rectfill(bx + 1, by + 1, bx + fill_w, by + bh - 1, 12)
	end
	print(label, 240 - #label * 4, by - 12, 7)
	local pct = tostr(flr(step / total * 100)).."%"
	print(pct, 240 - #pct * 4, by + 6, 7)
	flip()
end

function generate_fog_textures()
	local fog = Config.fog
	local sw, sh = 480, 270
	local n = #fog.colors
	local total_steps = n * 2  -- bayer + floyd per level

	-- 4x4 Bayer threshold matrix (values 0-15, normalized to 0..1)
	local bayer = {
		{0/16, 8/16, 2/16, 10/16},
		{12/16, 4/16, 14/16, 6/16},
		{3/16, 11/16, 1/16, 9/16},
		{15/16, 7/16, 13/16, 5/16},
	}

	fog.tex_bayer = {}
	fog.tex_floyd = {}
	local step = 0

	draw_loading(0, total_steps, "generating fog textures...")

	-- BAYER: non-overlapping masks via threshold bands
	-- layer i only draws pixels where prev_density <= threshold < density[i]
	for level = 1, n do
		local col = fog.colors[level]
		local d = fog.density[level]
		local prev_d = level > 1 and fog.density[level - 1] or 0

		local btex = userdata("u8", sw, sh)
		for py = 0, sh - 1 do
			local row = bayer[(py % 4) + 1]
			for px = 0, sw - 1 do
				local t = row[(px % 4) + 1]
				if t >= prev_d and t < d then
					btex:set(px, py, col)
				end
			end
		end
		fog.tex_bayer[level] = btex
		step += 1
		draw_loading(step, total_steps, "generating fog textures...")
	end

	-- FLOYD-STEINBERG: non-overlapping masks via cumulative subtraction
	-- generate cumulative pattern at each density, then exclusive mask =
	-- pixels ON in current cumulative but OFF in previous cumulative
	local prev_cumul = nil
	for level = 1, n do
		local col = fog.colors[level]
		local d = fog.density[level]

		-- generate cumulative dither at this density
		local cumul = userdata("u8", sw, sh)
		local err = {}
		for y = 0, sh - 1 do
			err[y] = {}
			for x = 0, sw - 1 do
				err[y][x] = 0
			end
		end
		for py = 0, sh - 1 do
			local erow = err[py]
			for px = 0, sw - 1 do
				local val = d + erow[px]
				local out = val >= 0.5 and 1 or 0
				local e = val - out
				if px < sw - 1 then
					erow[px + 1] += e * 7 / 16
				end
				if py < sh - 1 then
					local nrow = err[py + 1]
					if px > 0 then
						nrow[px - 1] += e * 3 / 16
					end
					nrow[px] += e * 5 / 16
					if px < sw - 1 then
						nrow[px + 1] += e * 1 / 16
					end
				end
				if out == 1 then
					cumul:set(px, py, 1) -- marker
				end
			end
			err[py] = nil -- free row
		end

		-- exclusive mask: ON here but OFF in previous layer
		local ftex = userdata("u8", sw, sh)
		for py = 0, sh - 1 do
			for px = 0, sw - 1 do
				if cumul:get(px, py) ~= 0 then
					if prev_cumul == nil or prev_cumul:get(px, py) == 0 then
						ftex:set(px, py, col)
					end
				end
			end
		end
		fog.tex_floyd[level] = ftex
		prev_cumul = cumul

		step += 1
		draw_loading(step, total_steps, "generating fog textures...")
	end
end

function _update()
	Game.update()
end

function _draw()
	Game.draw()
end
