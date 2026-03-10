Config = {}

Config.cell_size = 2        -- world units per grid cell

Config.grid_w = 20          -- dungeon width in cells
Config.grid_h = 20          -- dungeon height in cells

Config.move_smoothing = 0.25  -- per-frame interpolation for movement (0=frozen, 1=instant)
Config.turn_smoothing = 0.4  -- per-frame interpolation for turning (0=frozen, 1=instant)

Config.climb = {
	move_frames   = 35,   -- frames to walk onto stairs
	settle_frames = 25,   -- frames to ease into new floor
	up_height     = 1.0,  -- camera vertical offset when climbing up
	down_height   = 1.0,  -- camera vertical offset when climbing down
}

Config.render = {
	radius   = 7,         -- max grid cells rendered from player
	near     = 0.1,       -- near clipping plane distance
	num_rays = 120,       -- DDA visibility rays
}

Config.fog = {
	spr = 8,              -- color table sprite (generated via coltab)
	-- colors = {15, 14, 8,   1, 1}, -- draw colors per level (lightest to darkest)
	-- start  = {2,  2,  3, 4, 8}, -- depth thresholds (more levels = smoother gradient)
	colors = {14, 10, 6,   3, 1}, -- draw colors per level (lightest to darkest)
	start  = {1.5,  3,  3, 4.5, 5}, -- depth thresholds (more levels = smoother gradient)
	density = {0.25, 0.25, 0.5, 0.75, 1.0}, -- fog coverage per level (0=clear, 1=solid)
	dither = "floyd",     -- "bayer", "floyd", or "none"
	stop   = 8,           -- max render distance
}
