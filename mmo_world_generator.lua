local WORLD_DIR = "world"
local CHUNK_W, CHUNK_H = 32, 18
local WORLD_W, WORLD_H = 100, 100

local function ensure_dir(p)
	if not fs.exists(p) then fs.makeDir(p) end
end

local function write_chunk(cx, cy, rows)
	local out = { w = CHUNK_W, h = CHUNK_H, rows = rows }
	local path = ("%s/%d_%d.tbl"):format(WORLD_DIR, cx, cy)
	local f = fs.open(path, "w")
	f.write(textutils.serialize(out))
	f.close()
	print("Wrote "..path)
end

local function solid_row(ch, fg, bg, n)
	return { c = string.rep(ch, n), fg = string.rep(fg, n), bg = string.rep(bg, n) }
end

local function build_chunk(cx, cy)
	local rows = {}
	local grass_fg, grass_bg = "2","d"
	local road_fg,  road_bg  = "4","8"
	local wall_fg,  wall_bg  = "f","7"

	-- World coordinate of chunk's top-left
	local wx0, wy0 = cx * CHUNK_W, cy * CHUNK_H

	for y = 1, CHUNK_H do
		rows[y] = solid_row(".", grass_fg, grass_bg, CHUNK_W)
	end

	-- Center lines for roads
	local road_x = math.floor(WORLD_W / 2)
	local road_y = math.floor(WORLD_H / 2)

	for y = 1, CHUNK_H do
		for x = 1, CHUNK_W do
			local wx, wy = wx0 + (x - 1), wy0 + (y - 1)

			-- Horizontal road
			if wy == road_y then
				rows[y].c  = rows[y].c:sub(1, x-1) .. "-" .. rows[y].c:sub(x+1)
				rows[y].fg = rows[y].fg:sub(1, x-1) .. road_fg .. rows[y].fg:sub(x+1)
				rows[y].bg = rows[y].bg:sub(1, x-1) .. road_bg .. rows[y].bg:sub(x+1)
			end

			-- Vertical road
			if wx == road_x then
				rows[y].c  = rows[y].c:sub(1, x-1) .. "|" .. rows[y].c:sub(x+1)
				rows[y].fg = rows[y].fg:sub(1, x-1) .. road_fg .. rows[y].fg:sub(x+1)
				rows[y].bg = rows[y].bg:sub(1, x-1) .. road_bg .. rows[y].bg:sub(x+1)
			end

			-- Border walls
			if wx == 0 or wy == 0 or wx == WORLD_W - 1 or wy == WORLD_H - 1 then
				rows[y].c  = rows[y].c:sub(1, x-1) .. "#" .. rows[y].c:sub(x+1)
				rows[y].fg = rows[y].fg:sub(1, x-1) .. wall_fg .. rows[y].fg:sub(x+1)
				rows[y].bg = rows[y].bg:sub(1, x-1) .. wall_bg .. rows[y].bg:sub(x+1)
			end
		end
	end

	return rows
end

ensure_dir(WORLD_DIR)

local chunks_x = math.ceil(WORLD_W / CHUNK_W)
local chunks_y = math.ceil(WORLD_H / CHUNK_H)

for cy = 0, chunks_y - 1 do
	for cx = 0, chunks_x - 1 do
		local rows = build_chunk(cx, cy)
		write_chunk(cx, cy, rows)
	end
end

print(("Generated %dx%d world in %d chunks."):format(WORLD_W, WORLD_H, chunks_x * chunks_y))