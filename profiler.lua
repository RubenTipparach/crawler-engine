-- profiler.lua - Performance profiler (based on abledbody's profiler)
-- Toggle with P key

local function do_nothing() end

local profile_meta = {__call = do_nothing}
profile = {draw = do_nothing}
setmetatable(profile, profile_meta)

local running = {}
local profiles = {}
local prof_order = {}  -- insertion order
local prof_n = 0

local function start_profile(name)
	running[name] = {
		start = stat(1)
	}
end

local function stop_profile(name, active, delta)
	local prof = profiles[name]
	if prof then
		prof.time = delta + prof.time
	else
		prof_n += 1
		profiles[name] = {
			time = delta,
			name = name,
			idx = prof_n,
		}
		prof_order[prof_n] = profiles[name]
	end
end

local function _profile(_, name)
	local t = stat(1)
	local active = running[name]
	if active then
		local delta = t - active.start
		stop_profile(name, active, delta)
		running[name] = nil
	else
		start_profile(name)
	end
end

local function print_shadow(text, x, y, color)
	print(text, x + 1, y + 1, 0)
	print(text, x, y, color)
end

local function display_profiles()
	local y = 24
	print_shadow("cpu:" .. string.sub(stat(1) * 100, 1, 5) .. "%  fps:" .. flr(stat(7)), 2, y, 7)
	y += 10
	-- display parents first, then children (indented names starting with space)
	for i = 1, prof_n do
		local prof = prof_order[i]
		if prof.name:sub(1, 1) ~= " " then
			local usage = string.sub(prof.time * 100, 1, 5) .. "%"
			print_shadow(prof.name .. ": " .. usage, 2, y, 7)
			y += 10
			-- show children of this parent
			for j = 1, prof_n do
				local child = prof_order[j]
				if child.name:sub(1, 1) == " " then
					local cu = string.sub(child.time * 100, 1, 5) .. "%"
					print_shadow(child.name .. ": " .. cu, 2, y, 12)
					y += 10
				end
			end
		end
	end
	-- any orphan children (no parent before them)
	profiles = {}
	prof_n = 0
end

function profile.enabled(on)
	profile_meta.__call = on and _profile or do_nothing
	profile.draw = on and display_profiles or do_nothing
end
