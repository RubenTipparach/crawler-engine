-- menu.lua
-- Main menu screen

Menu = {}

local selection = 1
local options = {"explore dungeon", "run benchmark"}

function Menu.update()
	if keyp("up") or keyp("w") then
		selection -= 1
		if selection < 1 then selection = #options end
	end
	if keyp("down") or keyp("s") then
		selection += 1
		if selection > #options then selection = 1 end
	end
	if keyp("x") or keyp("z") or keyp("return") then
		return selection
	end
	return nil
end

function Menu.draw()
	cls(0)
	-- title
	local tx = 240 - #"space crawler" * 4
	print("space crawler", tx, 60, 7)

	-- options
	for i=1,#options do
		local y = 110 + (i-1) * 16
		local col = i == selection and 10 or 6
		local prefix = i == selection and "> " or "  "
		local ox = 240 - #(prefix..options[i]) * 4
		print(prefix..options[i], ox, y, col)
	end

	print("arrows/wasd: select   x/z/enter: confirm", 100, 220, 5)
end
