-- game.lua
-- Game state machine: menu, dungeon, benchmark, climbing

Game = {}

Game.state = "menu"  -- "menu", "dungeon", "benchmark", "climbing"
Game.dungeon = nil
Game.floor = 1
Game.floors = {}     -- persisted dungeon data per floor
Game.climb = nil     -- climb animation state
Game.on_stairs = false -- suppress stair re-trigger after climb

local CELL = Config.cell_size
local CLIMB_MOVE_FRAMES = Config.climb.move_frames
local CLIMB_SETTLE_FRAMES = Config.climb.settle_frames
local CLIMB_UP_Y = Config.climb.up_height
local CLIMB_DOWN_Y = Config.climb.down_height
local GRID_W, GRID_H = Config.grid_w, Config.grid_h

-- direction offsets: 0=N,1=E,2=S,3=W
local DIR_DX = {0, 1, 0, -1}
local DIR_DZ = {-1, 0, 1, 0}

function Game.start_dungeon()
	Game.floor = 1
	Game.floors = {}
	Game.dungeon = Dungeon.generate(GRID_W, GRID_H, false)
	Player.init(Game.dungeon.spawn_gx, Game.dungeon.spawn_gy, 2)
	Game.state = "dungeon"
end

function Game.go_up()
	-- save current floor
	Game.floors[Game.floor] = Game.dungeon
	Game.floor += 1

	if Game.floors[Game.floor] then
		-- revisiting a previously generated floor
		Game.dungeon = Game.floors[Game.floor]
	else
		-- generate new floor (has down-stairs since floor > 1)
		Game.dungeon = Dungeon.generate(GRID_W, GRID_H, true)
	end

	local dng = Game.dungeon
	local face = (dng.down_dir + 2) % 4
	Player.init(dng.down_gx + DIR_DX[face + 1], dng.down_gy + DIR_DZ[face + 1], face)
end

function Game.go_down()
	-- save current floor
	Game.floors[Game.floor] = Game.dungeon
	Game.floor -= 1
	Game.dungeon = Game.floors[Game.floor]

	local dng = Game.dungeon
	local face = (dng.stairs_dir + 2) % 4
	Player.init(dng.stairs_gx + DIR_DX[face + 1], dng.stairs_gy + DIR_DZ[face + 1], face)
end

function Game.start_climb(direction)
	local dng = Game.dungeon
	local target_gx, target_gy, stair_dir

	if direction == "up" then
		target_gx = dng.stairs_gx
		target_gy = dng.stairs_gy
		stair_dir = dng.stairs_dir
	else
		target_gx = dng.down_gx
		target_gy = dng.down_gy
		stair_dir = dng.down_dir
	end

	-- find shortest rotation to face stairs direction
	local target_a = stair_dir * 0.25
	local da = target_a - Player.angle
	while da > 0.5 do da -= 1 end
	while da < -0.5 do da += 1 end

	Game.climb = {
		direction = direction,
		phase = "move",
		timer = 0,
		start_x = Player.x,
		start_z = Player.z,
		start_y = Player.y,
		start_angle = Player.angle,
		end_x = (target_gx - 0.5) * CELL,
		end_z = (target_gy - 0.5) * CELL,
		end_angle = Player.angle + da,
	}
	Game.state = "climbing"
end

function Game.update_climbing()
	local c = Game.climb
	c.timer += 1

	local peak = c.direction == "up" and CLIMB_UP_Y or -CLIMB_DOWN_Y

	if c.phase == "move" then
		local t = c.timer / CLIMB_MOVE_FRAMES
		if t >= 1 then
			t = 1
			if c.direction == "up" then
				Game.go_up()
			else
				Game.go_down()
			end
			c.phase = "settle"
			c.timer = 0
			Player.y = peak
			return
		end
		-- smoothstep easing
		local st = t * t * (3 - 2 * t)
		Player.x = c.start_x + (c.end_x - c.start_x) * st
		Player.z = c.start_z + (c.end_z - c.start_z) * st
		Player.y = c.start_y + (peak - c.start_y) * st
		Player.angle = c.start_angle + (c.end_angle - c.start_angle) * st

	elseif c.phase == "settle" then
		local t = c.timer / CLIMB_SETTLE_FRAMES
		if t >= 1 then
			Player.y = 0
			Game.state = "dungeon"
			Game.climb = nil
			Game.on_stairs = true -- suppress until player moves off
			return
		end
		local st = t * t * (3 - 2 * t)
		Player.y = peak * (1 - st)
	end
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
		UI.fog_tweak_update()
		-- check stairs (suppressed until player moves off after a climb)
		local dng = Game.dungeon
		local on_up = Player.gx == dng.stairs_gx and Player.gy == dng.stairs_gy
		local on_down = dng.down_gx and Player.gx == dng.down_gx and Player.gy == dng.down_gy
		if Game.on_stairs then
			if not on_up and not on_down then
				Game.on_stairs = false
			end
		else
			if on_up then
				Game.start_climb("up")
			elseif on_down then
				Game.start_climb("down")
			end
		end
		if keyp("escape") then
			Game.state = "menu"
		end

	elseif Game.state == "climbing" then
		Game.update_climbing()

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

	elseif Game.state == "dungeon" or Game.state == "climbing" then
		DungeonView.draw(Game.dungeon, Player)
		-- minimap (top-right corner)
		Dungeon.draw_minimap(Game.dungeon, Player.gx, Player.gy, 480-Game.dungeon.w*2-4, 4, 2, DungeonView.vis)
		-- hud
		local res_names = {"full", "half", "quarter"}
		local res = res_names[DungeonView.res_mode + 1]
		print("cpu: "..tostr(flr(stat(1)*1000)/10).."%  tris: "..Renderer.tri_count.."  res: "..res, 2, 2, 7)
		print("pos: "..Player.gx..","..Player.gy.."  floor: "..Game.floor.."  [m] res [f] fog [esc] menu", 2, 12, 7)
		UI.fog_tweak_draw()

	elseif Game.state == "benchmark" then
		Benchmark.draw()
	end
end
