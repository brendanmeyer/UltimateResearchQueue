local cache = require("cache")
local gui = require("gui")
local research_queue = require("research-queue")
local util = require("util")

local migrations = {}

function migrations.generic()
  cache.build_dictionaries()
  cache.build_effect_icons()
  cache.build_technologies()
  for _, force in pairs(game.forces) do
    migrations.migrate_force(force)
  end
  for _, player in pairs(game.players) do
    migrations.migrate_player(player)
  end
end

--- @class ForceTable
--- @field force LuaForce
--- @field last_research_progress double
--- @field last_research_progress_tick uint
--- @field research_speed double
--- @field research_states table<string, ResearchState>
--- @field queue ResearchQueue
--- @field technology_groups table<ResearchState, table<uint, LuaTechnology>>

--- @param force LuaForce
function migrations.init_force(force)
  --- @type ForceTable
  local force_table = {
    force = force,
    last_research_progress = 0,
    last_research_progress_tick = 0,
    queue = nil, --- @diagnostic disable-line
    research_speed = 0,
    research_states = {},
    technology_groups = {},
  }
  force_table.queue = research_queue.new(force, force_table)
  global.forces[force.index] = force_table
end

--- @param force LuaForce
function migrations.migrate_force(force)
  local force_table = global.forces[force.index]
  if not force_table then
    return
  end
  cache.init_force(force)
  util.ensure_queue_disabled(force)
  research_queue.verify_integrity(force_table.queue)
end

--- @param player LuaPlayer
function migrations.migrate_player(player)
  gui.new(player)
end

migrations.by_version = {}

return migrations
