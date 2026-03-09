-- game.lua
-- Game state machine: menu, dungeon, benchmark

Game = {}

Game.state = "menu"  -- "menu", "dungeon", "benchmark"
Game.dungeon = nil

function Game.start_dungeon()
	Game.dungeon = Dungeon.generate(10, 10)
	Player.init(2, 2, 2)  -- grid (2,2) = first open cell in maze
	Game.state = "dungeon"
end

function Game.update()
	if Game.state == "menu" then
		local choice = Menu.update()
		if choice == 1 then
			Game.start_dungeon()
		elseif choice == 2 then
			Game.state = "benchmark"
			Benchmark.start()
		end

	elseif Game.state == "dungeon" then
		Player.update(Game.dungeon)
		if keyp("escape") then
			Game.state = "menu"
		end

	elseif Game.state == "benchmark" then
		local result = Benchmark.update()
		if result == "menu" then
			Game.state = "menu"
		end
		if Benchmark.done and keyp("escape") then
			Benchmark.done = false
			Game.state = "menu"
		end
	end
end

function Game.draw()
	if Game.state == "menu" then
		Menu.draw()

	elseif Game.state == "dungeon" then
		DungeonView.draw(Game.dungeon, Player)
		-- minimap (top-right corner)
		Dungeon.draw_minimap(Game.dungeon, Player.gx, Player.gy, 480-Game.dungeon.w*2-4, 4, 2)
		-- hud
		local res = DungeonView.half_res and "half" or "full"
		print("cpu: "..tostr(flr(stat(1)*1000)/10).."%  tris: "..Renderer.tri_count.."  res: "..res, 2, 2, 7)
		print("pos: "..Player.gx..","..Player.gy.."  [m] res  [esc] menu", 2, 12, 7)

	elseif Game.state == "benchmark" then
		Benchmark.draw()
	end
end
