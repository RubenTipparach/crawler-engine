-- ui.lua
-- Shared UI utilities

UI = {}

-- fog tweaker: F cycles off → color → depth → dither → off
-- I/K: slot  |  J/L: dec/inc value
UI.fog_mode = 0  -- 0=off, 1=color, 2=depth, 3=dither
UI.fog_slot = 1

local dither_modes = {"bayer", "floyd", "none"}

function UI.recolor_fog_tex(level, old_col, new_col)
	local fog = Config.fog
	local textures = {fog.tex_bayer and fog.tex_bayer[level], fog.tex_floyd and fog.tex_floyd[level]}
	for _, tex in pairs(textures) do
		if tex then
			local w, h = tex:width(), tex:height()
			for py = 0, h - 1 do
				for px = 0, w - 1 do
					if tex:get(px, py) == old_col then
						tex:set(px, py, new_col)
					end
				end
			end
		end
	end
end

function UI.fog_tweak_update()
	if keyp("f") then
		UI.fog_mode = (UI.fog_mode + 1) % 5
	end
	if UI.fog_mode == 0 then return end

	local fog = Config.fog
	local n = #fog.colors

	if UI.fog_mode == 4 then
		-- dither mode: J/L cycle dither type
		if keyp("j") or keyp("l") then
			local cur = 1
			for i = 1, #dither_modes do
				if dither_modes[i] == fog.dither then cur = i break end
			end
			if keyp("l") then
				fog.dither = dither_modes[(cur % #dither_modes) + 1]
			else
				fog.dither = dither_modes[((cur - 2) % #dither_modes) + 1]
			end
		end
	else
		if keyp("i") then UI.fog_slot = max(1, UI.fog_slot - 1) end
		if keyp("k") then UI.fog_slot = min(n, UI.fog_slot + 1) end

		local s = UI.fog_slot
		if UI.fog_mode == 1 then
			local old_col = fog.colors[s]
			if keyp("j") then fog.colors[s] = max(0, fog.colors[s] - 1) end
			if keyp("l") then fog.colors[s] = min(32, fog.colors[s] + 1) end
			if fog.colors[s] ~= old_col then
				UI.recolor_fog_tex(s, old_col, fog.colors[s])
			end
		elseif UI.fog_mode == 2 then
			if keyp("j") then fog.start[s] = max(0.5, fog.start[s] - 0.5) end
			if keyp("l") then fog.start[s] = min(20, fog.start[s] + 0.5) end
		elseif UI.fog_mode == 3 then
			if keyp("j") then fog.density[s] = max(0, fog.density[s] - 0.25) end
			if keyp("l") then fog.density[s] = min(1, fog.density[s] + 0.25) end
		end
	end
end

function UI.fog_tweak_draw()
	if UI.fog_mode == 0 then return end

	local fog = Config.fog
	local x, y = 2, 26
	local n = #fog.colors
	local labels = {"color", "depth", "density", "dither"}
	local mode = labels[UI.fog_mode]

	rectfill(x-1, y-1, x+200, y + n * 10 + 28, 0)
	print("fog ["..mode.."] i/k:slot j/l:val", x, y, 6)
	y += 10

	for i = 1, n do
		local sel = i == UI.fog_slot and UI.fog_mode ~= 4
		print(sel and ">" or " ", x, y, sel and 10 or 6)

		local c_on = sel and UI.fog_mode == 1
		print("c="..tostr(fog.colors[i]), x + 10, y, c_on and 10 or 6)

		local d_on = sel and UI.fog_mode == 2
		print("d="..tostr(fog.start[i]), x + 50, y, d_on and 10 or 6)

		local dn_on = sel and UI.fog_mode == 3
		print("n="..tostr(fog.density[i]), x + 100, y, dn_on and 10 or 6)

		y += 10
	end

	-- dither row
	local dt_on = UI.fog_mode == 4
	print("dither: "..fog.dither, x, y, dt_on and 10 or 6)

	-- hold O: preview fog texture for selected slot
	if key("o") and UI.fog_mode ~= 0 and UI.fog_mode ~= 4 then
		local textures = fog.dither == "floyd" and fog.tex_floyd or fog.tex_bayer
		if textures and textures[UI.fog_slot] then
			palt(0, true)
			sspr(textures[UI.fog_slot], 0, 0, 480, 270, 0, 0, 480, 270)
			palt(0, false)
		end
	end
end
