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
	-- keep your existing colors (they looked good for you)
	local rows = {}
	local grass_fg, grass_bg = "5","d"
	local road_fg,  road_bg  = "4","8"
	local wall_fg,  wall_bg  = "f","7"

	-- Chunk's top-left in world coords
	local wx0, wy0 = cx * CHUNK_W, cy * CHUNK_H

	-- World midlines for roads
	local road_x = math.floor(WORLD_W / 2)
	local road_y = math.floor(WORLD_H / 2)

	for y = 1, CHUNK_H do
		local c_line, fg_line, bg_line = {}, {}, {}
		for x = 1, CHUNK_W do
			local wx, wy = wx0 + (x - 1), wy0 + (y - 1)

			-- Default: grass checkerboard text pattern
			local ch   = (((wx + wy) % 2) == 0) and "." or "v"
			local fg   = grass_fg
			local bg   = grass_bg

			-- Border walls (override everything)
			local on_border = (wx == 0 or wy == 0 or wx == WORLD_W - 1 or wy == WORLD_H - 1)
			if on_border then
				ch, fg, bg = "#", wall_fg, wall_bg
			else
				-- Roads only on interior tiles (stop before walls)
				local on_h_road = (wy == road_y) and (wx > 0 and wx < WORLD_W - 1)
				local on_v_road = (wx == road_x) and (wy > 0 and wy < WORLD_H - 1)

				if on_h_road and on_v_road then
					ch, fg, bg = "+", road_fg, road_bg
				elseif on_h_road then
					ch, fg, bg = "-", road_fg, road_bg
				elseif on_v_road then
					ch, fg, bg = "|", road_fg, road_bg
				end
			end

			c_line[#c_line+1]  = ch
			fg_line[#fg_line+1]= fg
			bg_line[#bg_line+1]= bg
		end

		rows[y] = {
			c  = table.concat(c_line),
			fg = table.concat(fg_line),
			bg = table.concat(bg_line)
		}
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