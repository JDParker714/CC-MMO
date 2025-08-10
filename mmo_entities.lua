-- mmo_entities.lua
-- Core entity system for MMO server: base class, registry, factory.

local world = require("mmo_world_atlas")

local M = {}

-- ===== Base "class" =======================================================
local Base = {}
Base.__index = Base

function Base:new(o)
	o = o or {}
	setmetatable(o, self)
	-- required gameplay fields
	o.x = assert(o.x, "Entity needs x")
	o.y = assert(o.y, "Entity needs y")
    o.last_dx = 0
    o.last_dy = 0
	o.glyph = o.glyph or "E"			-- character to draw
	o.fg = o.fg or "f"					-- blit fg
	o.bg = o.bg or "e"					-- blit bg
	o.cd = o.cd or 0					-- current cooldown (ticks)
	o.cd_max = o.cd_max or 2			-- ticks between moves
	return o
end

-- Override per type if you need special passability
function Base:can_move(nx, ny, players, entities)
	if world.is_blocked(nx, ny) then return false end
	for _, p in pairs(players) do
		if p.x == nx and p.y == ny then return false end
	end
	for _, e in ipairs(entities) do
		if e ~= self and e.x == nx and e.y == ny then return false end
	end
	return true
end

-- Default AI: stand still
function Base:think(players, entities)
	-- return dx, dy
	return 0, 0
end

function Base:step(players, entities)
	if self.cd > 0 then
		self.cd = self.cd - 1
		return
	end
	local dx, dy = self:think(players, entities)
	if dx ~= 0 or dy ~= 0 then
        self.last_dx = dx
        self.last_dy = dy
		local nx, ny = self.x + dx, self.y + dy
		if self:can_move(nx, ny, players, entities) then
			self.x, self.y = nx, ny
			self.cd = self.cd_max
		end
	end
end

M.Base = Base

-- ===== Type Registry ======================================================
-- Register new kinds here (or from the server via M.register)
local TYPES = {}

-- Helper to create a subclass from Base
local function subclass(def)
	def.__index = def
	return setmetatable(def, { __index = Base })
end

function M.register(kind, def)
	-- def should be a table with optional: glyph, fg, bg, cd_max, and a think(self, players, entities) method
	TYPES[kind] = subclass(def)
end

-- Factory: create entity of a registered kind
function M.new(kind, x, y, opts)
	local T = TYPES[kind]
	assert(T, "Unknown entity kind: "..tostring(kind))
	opts = opts or {}
	opts.x, opts.y = x, y
	opts.kind = kind
	return T:new(opts)
end

-- ===== Built-in Examples ==================================================
-- Goblin: random wander, a bit faster
M.register("goblin", {
	glyph = "G", fg = "f", bg = "5", cd_max = 1,
	think = function(self, players, entities)
		local r = math.random(4)
		if r == 1 then return 0,-1
		elseif r == 2 then return 0, 1
		elseif r == 3 then return-1, 0
		else              return 1, 0 end
	end
})

-- Raider: prefers horizontal wandering
M.register("raider", {
	glyph = "^", fg = "f", bg = "c", cd_max = 2,
	think = function(self, players, entities)
		local r = math.random(6)
		if r <= 2 then return 0, (r==1) and -1 or 1
		else
			local h = (math.random(2) == 1) and -1 or 1
			return h, 0
		end
	end
})

-- Dragon: slow, long pauses; drifts toward nearest player if any
M.register("dragon", {
	glyph = "D", fg = "1", bg = "e", cd_max = 3,
	think = function(self, players, entities)
		-- Find nearest player within 12 tiles; else idle
		local best_id, best_d, best_dx, best_dy = nil, math.huge, 0, 0
		for id, p in pairs(players) do
			local dx, dy = p.x - self.x, p.y - self.y
			local d = math.sqrt(dx * dx + dy * dy)
			if d < best_d then
				best_d = d; best_id = id; best_dx = dx; best_dy = dy
			end
		end
		if best_id and best_d <= 15 then
			if math.abs(best_dx) > math.abs(best_dy) then
				if best_dx < 0 then return -1, 0 else return 1, 0 end
			else
				if best_dy < 0 then return 0, -1 else return 0, 1 end
			end
		end

		-- idle/random nudge
		if math.random(3) == 1 then
			local r = math.random(4)
			if r == 1 then return 0,-1
			elseif r == 2 then return 0, 1
			elseif r == 3 then return-1, 0
			else              return 1, 0 end
		end
		return 0, 0
	end
})

-- NPC: does not move; holds dialogue lines and a trigger radius
M.register("npc", {
	glyph = "N", fg = "0", bg = "8", cd_max = 999999,
	think = function(self, players, entities)
		return 0, 0  -- totally stationary
	end
})

return M