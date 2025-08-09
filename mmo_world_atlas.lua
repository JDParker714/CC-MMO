-- world_atlas.lua
-- On-disk chunked world storage. Each chunk file is a textutils-serialized table:
--	 { w=CHUNK_W, h=CHUNK_H, rows = { {c=..., fg=..., bg=...}, ... } }
-- stored at /world/<cx>_<cy>.tbl (cx,cy can be negative, include minus sign)

local M = {}

M.CHUNK_W = 32
M.CHUNK_H = 18

local WORLD_DIR = "world"
if not fs.exists(WORLD_DIR) then fs.makeDir(WORLD_DIR) end

local cache = {}	-- cache[cy] [cx] = chunkTable or false (negative cache)

local function chunk_path(cx, cy)
	return ("%s/%d_%d.tbl"):format(WORLD_DIR, cx, cy)
end

local function load_chunk(cx, cy)
	cache[cy] = cache[cy] or {}
	if cache[cy][cx] ~= nil then return cache[cy][cx] end

	local path = chunk_path(cx, cy)
	if not fs.exists(path) then
		cache[cy][cx] = false
		return false
	end

	local f = fs.open(path, "r")
	local data = textutils.unserialize(f.readAll())
	f.close()

	-- Very light validation
	if type(data) == "table" and type(data.rows) == "table" and data.w and data.h then
		cache[cy][cx] = data
	else
		cache[cy][cx] = false
	end
	return cache[cy][cx]
end

function M.is_blocked(wx, wy)
	local cx, cy, lx, ly = w2c(wx, wy)
	local ch = load_chunk(cx, cy)
	if not ch or not ch.rows[ly] then return true end	-- void = blocked
	local r = ch.rows[ly]
	local tile = r.c:sub(lx, lx)
	return tile == "#"
end

local function floorDiv(a, b) return (a - (a % b)) / b end
local function w2c(wx, wy)
	local cw, ch = M.CHUNK_W, M.CHUNK_H
	local cx = floorDiv(wx, cw)
	local cy = floorDiv(wy, ch)
	local lx = (wx % cw) + 1
	local ly = (wy % ch) + 1
	return cx, cy, lx, ly
end

-- Return a viewport centered on (wx,wy) with size (vw,vh) as rows of {c,fg,bg}
function M.get_view(wx, wy, vw, vh)
	local half_w, half_h = math.floor(vw/2), math.floor(vh/2)
	local x0, y0 = wx - half_w, wy - half_h
	local rows = {}

	for sy = 0, vh-1 do
		local wy_row = y0 + sy
		local c_line, fg_line, bg_line = {}, {}, {}

		for sx = 0, vw-1 do
			local wx_col = x0 + sx
			local cx, cy, lx, ly = w2c(wx_col, wy_row)
			local ch = load_chunk(cx, cy)
			if ch and ch.rows[ly] then
				local r = ch.rows[ly]
				c_line[#c_line+1]	= r.c:sub(lx,lx)
				fg_line[#fg_line+1]= r.fg:sub(lx,lx)
				bg_line[#bg_line+1]= r.bg:sub(lx,lx)
			else
				-- Void tile fallback
				c_line[#c_line+1]	= " "
				fg_line[#fg_line+1]= "7"
				bg_line[#bg_line+1]= "0"
			end
		end

		rows[#rows+1] = { c=table.concat(c_line), fg=table.concat(fg_line), bg=table.concat(bg_line) }
	end

	return rows
end

return M
