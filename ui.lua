-- ui.lua
-- Shared UI utilities

UI = {}

-- fog tweaker: F cycles off → color → depth → off
-- I/K: slot  |  J/L: dec/inc value
UI.fog_mode = 0  -- 0=off, 1=color, 2=depth
UI.fog_slot = 1

function UI.fog_tweak_update()
	if keyp("f") then
		UI.fog_mode = (UI.fog_mode + 1) % 3
	end
	if UI.fog_mode == 0 then return end

	local fog = Config.fog
	local n = #fog.colors

	if keyp("i") then UI.fog_slot = max(1, UI.fog_slot - 1) end
	if keyp("k") then UI.fog_slot = min(n, UI.fog_slot + 1) end

	local s = UI.fog_slot
	if UI.fog_mode == 1 then
		if keyp("j") then fog.colors[s] = max(0, fog.colors[s] - 1) end
		if keyp("l") then fog.colors[s] = min(32, fog.colors[s] + 1) end
	else
		if keyp("j") then fog.start[s] = max(0.5, fog.start[s] - 0.5) end
		if keyp("l") then fog.start[s] = min(20, fog.start[s] + 0.5) end
	end
end

function UI.fog_tweak_draw()
	if UI.fog_mode == 0 then return end

	local fog = Config.fog
	local x, y = 2, 26
	local n = #fog.colors
	local mode = UI.fog_mode == 1 and "color" or "depth"

	rectfill(x-1, y-1, x+180, y + n * 10 + 18, 0)
	print("fog ["..mode.."] i/k:slot j/l:val", x, y, 6)
	y += 10

	for i = 1, n do
		local sel = i == UI.fog_slot
		print(sel and ">" or " ", x, y, sel and 10 or 6)

		local c_on = sel and UI.fog_mode == 1
		print("c="..tostr(fog.colors[i]), x + 10, y, c_on and 10 or 6)

		local d_on = sel and UI.fog_mode == 2
		print("d="..tostr(fog.start[i]), x + 50, y, d_on and 10 or 6)

		y += 10
	end
end
