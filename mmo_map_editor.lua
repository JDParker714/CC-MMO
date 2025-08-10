-- mmo_map_editor.lua
-- CC:T map editor for chunked "world" with full+chunk saving and post-processing.
-- Requires: mmo_world_atlas.lua (for CHUNK_W / CHUNK_H)
-- Files written:
--   world/full.tbl                (full map: {w,h,rows={ {c,fg,bg}, ... }})
--   world/<cx>_<cy>.tbl           (chunks: same row triplet format)

local atlas = require("mmo_world_atlas")

-- ---------- Config / Paths ----------
local WORLD_DIR = "world"
local FULL_PATH = fs.combine(WORLD_DIR, "full.tbl")
local CHUNK_W, CHUNK_H = atlas.CHUNK_W, atlas.CHUNK_H

local SHADE_LIGHT  = "\226\150\145" -- U+2591 ░
local SHADE_MEDIUM = "\226\150\146" -- U+2592 ▒
local SHADE_DARK   = "\226\150\147" -- U+2593 ▓
local BOX_VERT     = "\226\148\130" -- U+2502 │
local BOX_HORZ    = "\226\148\128" -- U+2500 ─
local BOX_CROSS    = "\226\148\188" -- U+253C ┼
local TRIPLE_BAR   = "\226\137\161" -- U+2261 ≡

-- Initialize saved brush slots (edit these to set your defaults).
-- Slots: 1..9 and 0 (for key '0'). Each has ch = glyph, fg/bg = hex blit colors "0".."f"
local BRUSH_PRESETS = {
	[1] = { ch = "g", fg = "5", bg = "d" },	-- grass base
	[2] = { ch = "#", fg = "8", bg = "7" },	-- wall
	[3] = { ch = SHADE_LIGHT, fg = "c", bg = "1" },	-- cliff
	[4] = { ch = TRIPLE_BAR, fg = "7", bg = "8" },	-- stairs
	[5] = { ch = "s", fg = "1", bg = "4" },	-- sand
	[6] = { ch = BOX_VERT, fg = "4", bg = "8" },	-- road vertical
	[7] = { ch = BOX_HORZ, fg = "4", bg = "8" },	-- road horizontal
	[8] = { ch = BOX_CROSS, fg = "4", bg = "8" },	-- road cross
	[9] = { ch = SHADE_MEDIUM, fg = "3", bg = "b" },	-- water
	[0] = { ch = BOX_CROSS, fg = "1", bg = "c" },	-- flooring
}

-- ---------- Post-process rules ----------
-- Each rule: fg (hex), bg (hex), glyphs = set{ [ch]=true }, pattern.even / pattern.odd
local POST_RULES = {
	{
		fg = "5",
		bg = "d",
		glyphs = { ["g"]=true, ["."]=true, ["v"]=true },
		pattern = { even = ".", odd = "v" },
	},
	{
		fg = "1",
		bg = "4",
		glyphs = { ["s"]=true, ["."]=true, ["~"]=true },
		pattern = { even = ".", odd = "~" },
	},
}

-- ---------- Utils ----------
local function ensure_dir(p) if not fs.exists(p) then fs.makeDir(p) end end
ensure_dir(WORLD_DIR)

local function clamp(v, a, b) if v < a then return a elseif v > b then return b else return v end end

local function read_line(prompt)
	term.setCursorBlink(true)
	write(prompt or "")
	local s = read()
	term.setCursorBlink(false)
	return s
end

-- UTF-8 helpers (work even if 'utf8' lib is minimal)
local function utf8_len(s)
	local len = 0
	for _ in string.gmatch(s, "[%z\1-\127\194-\244][\128-\191]*") do len = len + 1 end
	return len
end

local function utf8_byte_index(s, ci) -- 1-based character index -> byte index
	if ci <= 1 then return 1 end
	local i, count = 1, 1
	local len = #s
	while i <= len do
		if count == ci then return i end
		local b = string.byte(s, i)
		local step = (b < 0x80) and 1 or (b < 0xE0) and 2 or (b < 0xF0) and 3 or 4
		i = i + step
		count = count + 1
	end
	-- past end -> return len+1 so sub() with [i, i-1] yields ""
	return len + 1
end

local function utf8_sub(s, i, j)
	-- 1-based character indices inclusive
	local bi = utf8_byte_index(s, i)
	local bj = utf8_byte_index(s, (j or i) + 1) - 1
	if bi > #s or bj < bi then return "" end
	return s:sub(bi, bj)
end

local function utf8_replace_at(s, i, ch)
	local bi = utf8_byte_index(s, i)
	local bj = utf8_byte_index(s, i + 1) - 1
	if bi > #s then return s end
	return s:sub(1, bi - 1) .. ch .. s:sub(bj + 1)
end

local function mk_row(ch, fg, bg, n)
	return { c = string.rep(ch, n), fg = string.rep(fg, n), bg = string.rep(bg, n) }
end

local function serialize_to(path, tbl)
	local f = fs.open(path, "w"); f.write(textutils.serialize(tbl)); f.close()
end

local function unserialize_from(path)
	local f = fs.open(path, "r"); local data = textutils.unserialize(f.readAll()); f.close(); return data
end

-- ---------- Map Model ----------
local world = { w = 0, h = 0, rows = {} }  -- rows[y] = {c,fg,bg}

local function init_world(w, h)
	world.w, world.h = w, h
	world.rows = {}
	-- Checkerboard of "+" and "." with fg "0", bg "8"
	for y = 1, h do
		local c_line, fg_line, bg_line = {}, {}, {}
		for x = 1, w do
			local ch = (((x + y) % 2) == 0) and "+" or "."
			c_line[#c_line+1]  = ch
			fg_line[#fg_line+1]= "0"
			bg_line[#bg_line+1]= "8"
		end
		world.rows[y] = { c = table.concat(c_line), fg = table.concat(fg_line), bg = table.concat(bg_line) }
	end
end

local function load_full_if_exists()
	if fs.exists(FULL_PATH) then
		local ok, data = pcall(unserialize_from, FULL_PATH)
		if ok and type(data)=="table" and type(data.rows)=="table" and data.w and data.h then
			world = data
			return true
		end
	end
	return false
end

local function save_full()
	serialize_to(FULL_PATH, world)
end

-- UTF-8 safe substring by character range
local function utf8_slice_by_chars(s, start_char, end_char)
	return utf8_sub(s, start_char, end_char)
end

local function save_chunks()
	local W, H = world.w, world.h
	local rows = world.rows
	local chunks_x = math.ceil(W / CHUNK_W)
	local chunks_y = math.ceil(H / CHUNK_H)

	for cy = 0, chunks_y - 1 do
		for cx = 0, chunks_x - 1 do
			local c_rows = {}
			for ly = 1, CHUNK_H do
				local wy = cy * CHUNK_H + ly
				if wy >= 1 and wy <= H then
					local src = rows[wy]
					local x0 = cx * CHUNK_W + 1
					local x1 = math.min(x0 + CHUNK_W - 1, W)
					local c  = utf8_slice_by_chars(src.c,  x0, x1)
					local fg = src.fg:sub(x0, x1)
					local bg = src.bg:sub(x0, x1)
					-- pad to chunk width if at world edge
					local cc = utf8_len(c)
					if cc < CHUNK_W then
						local pad = CHUNK_W - cc
						c  = c  .. string.rep(" ", pad)
						fg = fg .. string.rep("7", pad)
						bg = bg .. string.rep("f", pad)
					end
					c_rows[ly] = { c = c, fg = fg, bg = bg }
				else
					c_rows[ly] = mk_row(" ", "7", "f", CHUNK_W)
				end
			end
			local out = { w = CHUNK_W, h = CHUNK_H, rows = c_rows }
			local path = fs.combine(WORLD_DIR, ("%d_%d.tbl"):format(cx, cy))
			serialize_to(path, out)
		end
	end
end

-- Set a single cell at world coords (1-based)
local function set_cell(wx, wy, ch, fg, bg)
	if wx < 1 or wy < 1 or wx > world.w or wy > world.h then return end
	local r = world.rows[wy]
	r.c  = utf8_replace_at(r.c, wx, ch)
	r.fg = r.fg:sub(1, wx-1) .. fg .. r.fg:sub(wx+1)
	r.bg = r.bg:sub(1, wx-1) .. bg .. r.bg:sub(wx+1)
end

local function get_cell(wx, wy)
	if wx < 1 or wy < 1 or wx > world.w or wy > world.h then
		return { ch=" ", fg="7", bg="f" }
	end
	local r = world.rows[wy]
	return {
		ch = utf8_sub(r.c, wx, wx),
		fg = r.fg:sub(wx, wx),
		bg = r.bg:sub(wx, wx)
	}
end

-- Fill a rectangle inclusive in world coords
local function fill_rect(x1, y1, x2, y2, b)
	local ax, bx = math.min(x1,x2), math.max(x1,x2)
	local ay, by = math.min(y1,y2), math.max(y1,y2)
	ax, ay = clamp(ax,1,world.w), clamp(ay,1,world.h)
	bx, by = clamp(bx,1,world.w), clamp(by,1,world.h)
	for y = ay, by do
		for x = ax, bx do
			set_cell(x, y, b.ch, b.fg, b.bg)
		end
	end
end

-- ---------- Post-processing ----------
local function apply_postprocess()
	for y = 1, world.h do
		local r = world.rows[y]
		for x = 1, world.w do
			local ch = utf8_sub(r.c, x, x)
			local fg = r.fg:sub(x, x)
			local bg = r.bg:sub(x, x)
			for _, rule in ipairs(POST_RULES) do
				if fg == rule.fg and bg == rule.bg and rule.glyphs[ch] then
					local is_even = ((x + y) % 2) == 0
					local new_ch = is_even and rule.pattern.even or rule.pattern.odd
					r.c = utf8_replace_at(r.c, x, new_ch)
					break
				end
			end
		end
	end
end

-- ---------- UI State ----------
local tw, th = term.getSize()
local function refresh_term_size()
	tw, th = term.getSize()
end

local cam_x, cam_y = 1, 1        -- top-left world coord of viewport (1-based)
local brush = { ch = "+", fg = "0", bg = "8" }
local brushes = {}               -- [0..9] = {ch,fg,bg}

-- Seed brushes with presets
for k,v in pairs(BRUSH_PRESETS) do
	brushes[k] = { ch = v.ch, fg = v.fg, bg = v.bg }
end

local awaiting_brush_save_slot = false
local rect_anchor = nil          -- {x,y} when rectangle mode armed; nil otherwise
local painting = false
local last_mx, last_my = nil, nil

-- ---------- Colors ----------
local HEX_TO_COLOR = {
	["0"]=colors.white,     ["1"]=colors.orange,   ["2"]=colors.magenta, ["3"]=colors.lightBlue,
	["4"]=colors.yellow,    ["5"]=colors.lime,     ["6"]=colors.pink,    ["7"]=colors.gray,
	["8"]=colors.lightGray, ["9"]=colors.cyan,     ["a"]=colors.purple,  ["b"]=colors.blue,
	["c"]=colors.brown,     ["d"]=colors.green,    ["e"]=colors.red,     ["f"]=colors.black,
}

-- ---------- Rendering (UTF-8 safe, no blit) ----------
local function draw_view()
	term.setBackgroundColor(colors.black)
	term.clear()

	local vw, vh = tw, th - 1 -- leave bottom row for HUD
	for sy = 1, vh do
		local wy = cam_y + sy - 1
		term.setCursorPos(1, sy)
		if wy >= 1 and wy <= world.h then
			local row = world.rows[wy]
			for sx = 1, vw do
				local wx = cam_x + sx - 1
				if wx >= 1 and wx <= world.w then
					local ch = utf8_sub(row.c, wx, wx)
					local fg = row.fg:sub(wx, wx)
					local bg = row.bg:sub(wx, wx)
					term.setTextColor(HEX_TO_COLOR[fg] or colors.white)
					term.setBackgroundColor(HEX_TO_COLOR[bg] or colors.black)
					term.write(ch)
				else
					term.setTextColor(colors.white)
					term.setBackgroundColor(colors.black)
					term.write(" ")
				end
			end
		else
			term.setTextColor(colors.white)
			term.setBackgroundColor(colors.black)
			term.write(string.rep(" ", vw))
		end
	end

	-- HUD (bottom row) - ASCII to keep width exact
	local wx, wy = nil, nil
	if last_mx and last_my then
		wx, wy = cam_x + last_mx - 1, cam_y + last_my - 1
	end
	local pos_str = (wx and wy) and ("(%d,%d)  "):format(wx, wy) or ""
	local info = ("%sbrush[%s,%s,%s]  cam(%d,%d)  %s"):format(
		pos_str, brush.ch, brush.fg, brush.bg, cam_x, cam_y,
		rect_anchor and ("RECT anchor at "..rect_anchor.x..","..rect_anchor.y.." -> click to apply") or ""
	)
	term.setCursorPos(1, th)
	term.setBackgroundColor(colors.gray)
	term.setTextColor(colors.black)
	term.clearLine()
	term.write(info:sub(1, tw))
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.white)
end

-- ---------- Input Helpers ----------
local keys_map = keys

local function pan(dx, dy)
	cam_x = clamp(cam_x + dx, 1, math.max(1, world.w - tw + 1))
	cam_y = clamp(cam_y + dy, 1, math.max(1, world.h - (th - 1) + 1))
end

local function mouse_to_world(mx, my)
	local vw, vh = tw, th - 1
	if my < 1 or my > vh then return nil end
	return cam_x + mx - 1, cam_y + my - 1
end

-- ---------- Brush I/O ----------
local function prompt_glyph()
	local s = read_line("Glyph (single char): ")
	if s and #s >= 1 then brush.ch = s -- NOTE: may be UTF-8, we accept it
	end
end
local function prompt_fg()
	local s = read_line("FG color (0-f hex): ")
	if s and s:match("^[0-9a-f]$") then brush.fg = s end
end
local function prompt_bg()
	local s = read_line("BG color (0-f hex): ")
	if s and s:match("^[0-9a-f]$") then brush.bg = s end
end

local function save_brush_slot(n)
	brushes[n] = { ch = brush.ch, fg = brush.fg, bg = brush.bg }
end
local function recall_brush_slot(n)
	local b = brushes[n]; if b then brush.ch, brush.fg, brush.bg = b.ch, b.fg, b.bg end
end

-- ---------- File Ops ----------
local function do_save_all()
	save_full()
	save_chunks()
end

-- ---------- Startup ----------
local loaded = load_full_if_exists()
if not loaded then
	local w = tonumber(read_line("Map width: "))
	local h = tonumber(read_line("Map height: "))
	if not w or not h or w < 1 or h < 1 then
		print("Invalid size."); return
	end
	init_world(w, h)
	save_full()
else
	print(("Loaded existing map: %dx%d"):format(world.w, world.h))
	sleep(0.7)
end

term.clear()
draw_view()

-- ---------- Main Loop ----------
while true do
	draw_view()
	local e = { os.pullEvent() }
	local ev = e[1]

	if ev == "key" then
		local code = e[2]
		if code == keys_map.left  then pan(-1, 0)
		elseif code == keys_map.right then pan(1, 0)
		elseif code == keys_map.up then pan(0, -1)
		elseif code == keys_map.down then pan(0, 1)

		elseif code == keys_map.c then prompt_glyph()
		elseif code == keys_map.f then prompt_fg()
		elseif code == keys_map.b then prompt_bg()

		elseif code == keys_map.r then
			if rect_anchor then rect_anchor = nil else
				rect_anchor = false -- armed, waiting for anchor click
			end

		elseif code == keys_map.s then
			do_save_all()

		elseif code == keys_map.l then
			if load_full_if_exists() then
				print("Reloaded full map."); sleep(0.5)
			end

		elseif code == keys_map.n then
			awaiting_brush_save_slot = true

		elseif code == keys_map.one   then if awaiting_brush_save_slot then save_brush_slot(1) else recall_brush_slot(1) end; awaiting_brush_save_slot=false
		elseif code == keys_map.two   then if awaiting_brush_save_slot then save_brush_slot(2) else recall_brush_slot(2) end; awaiting_brush_save_slot=false
		elseif code == keys_map.three then if awaiting_brush_save_slot then save_brush_slot(3) else recall_brush_slot(3) end; awaiting_brush_save_slot=false
		elseif code == keys_map.four  then if awaiting_brush_save_slot then save_brush_slot(4) else recall_brush_slot(4) end; awaiting_brush_save_slot=false
		elseif code == keys_map.five  then if awaiting_brush_save_slot then save_brush_slot(5) else recall_brush_slot(5) end; awaiting_brush_save_slot=false
		elseif code == keys_map.six   then if awaiting_brush_save_slot then save_brush_slot(6) else recall_brush_slot(6) end; awaiting_brush_save_slot=false
		elseif code == keys_map.seven then if awaiting_brush_save_slot then save_brush_slot(7) else recall_brush_slot(7) end; awaiting_brush_save_slot=false
		elseif code == keys_map.eight then if awaiting_brush_save_slot then save_brush_slot(8) else recall_brush_slot(8) end; awaiting_brush_save_slot=false
		elseif code == keys_map.nine  then if awaiting_brush_save_slot then save_brush_slot(9) else recall_brush_slot(9) end; awaiting_brush_save_slot=false
		elseif code == keys_map.zero  then if awaiting_brush_save_slot then save_brush_slot(0) else recall_brush_slot(0) end; awaiting_brush_save_slot=false

		elseif code == keys_map.p then
			apply_postprocess()
			do_save_all()
		end

	elseif ev == "mouse_click" or ev == "mouse_drag" then
		local button, mx, my = e[2], e[3], e[4]
		last_mx, last_my = mx, my
		local wx, wy = mouse_to_world(mx, my)
		if wx and wy then
			if button == 1 then
				if rect_anchor == false then
					rect_anchor = { x = wx, y = wy } -- first click sets anchor
				elseif rect_anchor and type(rect_anchor) == "table" then
					fill_rect(rect_anchor.x, rect_anchor.y, wx, wy, brush) -- second click fills
					rect_anchor = nil
				else
					painting = true
					set_cell(wx, wy, brush.ch, brush.fg, brush.bg)
				end
			elseif button == 2 then
				-- right-click eyedropper
				local cell = get_cell(wx, wy)
				brush.ch, brush.fg, brush.bg = cell.ch, cell.fg, cell.bg
			end
		end

	elseif ev == "mouse_up" then
		local button = e[2]
		if button == 1 then painting = false end

	elseif ev == "term_resize" then
		refresh_term_size()
	end
end