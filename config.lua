Config = {}

Config.fog = {
	spr = 8,              -- color table sprite (generated via coltab)
	colors = {12, 12, 10, 1}, -- draw colors for each fog level (lightest to darkest)
	start  = {2.5, 3.5, 4, 4.5},   -- depth where each fog level begins
	stop   = 10,              -- max render distance
}
