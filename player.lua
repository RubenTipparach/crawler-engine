-- player.lua
-- Grid-based first-person movement with smooth interpolation

Player = {}

Player.gx, Player.gy = 1, 1
Player.dir = 2  -- 0=N,1=E,2=S,3=W (start facing south)

-- smooth visual state
Player.x, Player.z = 0, 0
Player.angle = 0
local target_x, target_z = 0, 0
local target_angle = 0

local CELL = 2
local LERP_SPEED = 0.15

-- direction vectors: N, E, S, W
local dir_dx = {0, 1, 0, -1}
local dir_dz = {-1, 0, 1, 0}
local dir_names = {"n","e","s","w"}

function Player.init(gx, gy, dir)
	Player.gx = gx
	Player.gy = gy
	Player.dir = dir or 2
	Player.x = (gx - 0.5) * CELL
	Player.z = (gy - 0.5) * CELL
	target_x = Player.x
	target_z = Player.z
	-- angle: dir 0(N)=0, 1(E)=0.25, 2(S)=0.5, 3(W)=0.75
	Player.angle = Player.dir * 0.25
	target_angle = Player.angle
end

function Player.update(dng)
	-- turn
	if keyp("left") or keyp("a") then
		Player.dir = (Player.dir - 1) % 4
		target_angle -= 0.25
	end
	if keyp("right") or keyp("d") then
		Player.dir = (Player.dir + 1) % 4
		target_angle += 0.25
	end

	-- move forward
	if keyp("up") or keyp("w") then
		local nx = Player.gx + dir_dx[Player.dir+1]
		local ny = Player.gy + dir_dz[Player.dir+1]
		if Dungeon.is_open(dng, nx, ny) then
			Player.gx = nx
			Player.gy = ny
			target_x = (Player.gx - 0.5) * CELL
			target_z = (Player.gy - 0.5) * CELL
		end
	end

	-- move backward
	if keyp("down") or keyp("s") then
		local back = (Player.dir + 2) % 4
		local nx = Player.gx + dir_dx[back+1]
		local ny = Player.gy + dir_dz[back+1]
		if Dungeon.is_open(dng, nx, ny) then
			Player.gx = nx
			Player.gy = ny
			target_x = (Player.gx - 0.5) * CELL
			target_z = (Player.gy - 0.5) * CELL
		end
	end

	-- lerp
	Player.x += (target_x - Player.x) * LERP_SPEED
	Player.z += (target_z - Player.z) * LERP_SPEED
	Player.angle += (target_angle - Player.angle) * LERP_SPEED
end
