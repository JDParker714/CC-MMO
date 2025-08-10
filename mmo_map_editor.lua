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

-- Initialize saved brush slots (edit these to set your defaults).
-- Slots: 1..9 and 0 (for key '0'). Each has ch = glyph, fg/bg = hex blit colors "0".."f"
local BRUSH_PRESETS = {
	[1] = { ch = "g", fg = "5", bg = "d" },	-- grass base
	[2] = { ch = "#", fg = "8", bg = "7" },	-- wall
	[3] = { ch = "#", fg = "c", bg = "1" },	-- cliff
	[4] = { ch = "=", fg = "7", bg = "8" },	-- stairs
	[5] = { ch = "s", fg = "1", bg = "4" },	-- sand
	[6] = { ch = "|", fg = "4", bg = "8" },	-- road vertical
	[7] = { ch = "-", fg = "4", bg = "8" },	-- road horizontal
	[8] = { ch = "+", fg = "4", bg = "8" },	-- road cross
	[9] = { ch = "#", fg = "3", bg = "b" },	-- water
	[0] = { ch = "+", fg = "1", bg = "c" },	-- flooring
}

-- ---------- Post-process rules ----------
-- Each rule: fg (hex char), bg (hex char), glyphs = set{ [ch]=true }, pattern.even / pattern.odd
-- Example: grass beautifier (breaks up large patches).
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

local function replace_at(s, i, ch)
	if i < 1 or i > #s then return s end
	return s:sub(1, i-1) .. ch .. s:sub(i+1)
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
					local c = src.c:sub(x0, x1)
					local fg = src.fg:sub(x0, x1)
					local bg = src.bg:sub(x0, x1)
					-- pad to chunk width if at world edge
					if #c < CHUNK_W then
						local pad = CHUNK_W - #c
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
	r.c  = replace_at(r.c, wx, ch)
	r.fg = replace_at(r.fg, wx, fg)
	r.bg = replace_at(r.bg, wx, bg)
end

local function get_cell(wx, wy)
	if wx < 1 or wy < 1 or wx > world.w or wy > world.h then
		return { ch=" ", fg="7", bg="f" }
	end
	local r = world.rows[wy]
	return {
		ch = r.c:sub(wx, wx),
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
			local ch = r.c:sub(x, x)
			local fg = r.fg:sub(x, x)
			local bg = r.bg:sub(x, x)
			for _, rule in ipairs(POST_RULES) do
				if fg == rule.fg and bg == rule.bg and rule.glyphs[ch] then
					local is_even = ((x + y) % 2) == 0
					local new_ch = is_even and rule.pattern.even or rule.pattern.odd
					r.c = replace_at(r.c, x, new_ch)
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

-- ---------- Rendering ----------
local function draw_view()
	term.setBackgroundColor(colors.black)
	term.clear()

	-- Draw viewport using blit
	local vw, vh = tw, th - 1 -- leave bottom row for HUD
	for sy = 1, vh do
		local wy = cam_y + sy - 1
		if wy >= 1 and wy <= world.h then
			local src = world.rows[wy]
			local x0 = cam_x
			local x1 = math.min(cam_x + vw - 1, world.w)
			local pad = vw - (x1 - x0 + 1)
			local c  = (x0 <= world.w) and src.c:sub(x0, x1) or ""
			local fg = (x0 <= world.w) and src.fg:sub(x0, x1) or ""
			local bg = (x0 <= world.w) and src.bg:sub(x0, x1) or ""
			if pad > 0 then
				c  = c  .. string.rep(" ", pad)
				fg = fg .. string.rep("7", pad)
				bg = bg .. string.rep("f", pad)
			end
			term.setCursorPos(1, sy)
			term.blit(c, fg, bg)
		else
			term.setCursorPos(1, sy)
			term.blit(string.rep(" ", vw), string.rep("7", vw), string.rep("f", vw))
		end
	end

	-- HUD (bottom row)
	local wx, wy = nil, nil
	if last_mx and last_my then
		wx, wy = cam_x + last_mx - 1, cam_y + last_my - 1
	end
	local pos_str = (wx and wy) and ("(%d,%d)  "):format(wx, wy) or ""
	local info = ("%sbrush[%s,%s,%s]  cam(%d,%d)  %s"):format(
		pos_str, brush.ch, brush.fg, brush.bg, cam_x, cam_y,
		rect_anchor and ("RECT anchor at "..rect_anchor.x..","..rect_anchor.y.." → click to apply") or ""
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
	if s and #s >= 1 then brush.ch = s:sub(1,1) end
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
				-- arm rectangle mode; next left click sets anchor if none set; second applies
				rect_anchor = false -- "armed but no anchor yet"
			end

		elseif code == keys_map.s then
			do_save_all()

		elseif code == keys_map.l then
			if load_full_if_exists() then
				print("Reloaded full map."); sleep(0.5)
			end

		elseif code == keys_map.n then
			-- "save current brush to slot" mode; next number assigns
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
					-- first click sets anchor
					rect_anchor = { x = wx, y = wy }
				elseif rect_anchor and type(rect_anchor) == "table" then
					-- second click applies rectangle
					fill_rect(rect_anchor.x, rect_anchor.y, wx, wy, brush)
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

	-- No polling of mouse; painting occurs on drag/click events.
end