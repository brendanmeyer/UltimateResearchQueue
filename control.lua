local dictionary = require("__flib__.dictionary-lite")
local migration = require("__flib__.migration")
local flib_technology = require("__flib__.technology")

local gui = require("gui")
local migrations = require("migrations")
local research_queue = require("research-queue")
local util = require("util")

-- Bootstrap

script.on_init(function()
  --- @type table<uint, integer>
  global.filter_tech_list = {}
  --- @type table<uint, ForceTable>
  global.forces = {}
  --- @type table<uint, Gui?>
  global.guis = {}
  --- @type table<uint, boolean>
  global.update_force_guis = {}

  -- game.forces is apparently keyed by name, not index
  for _, force in pairs(game.forces) do
    migrations.init_force(force)
  end
  migrations.generic()

  -- Add each force's current research to the queue
  for _, force in pairs(game.forces) do
    local current_research = force.current_research
    if current_research then
      research_queue.push(global.forces[force.index].queue, current_research, current_research.level)
      gui.update_force(force)
    end
  end
end)

migration.handle_on_configuration_changed(nil, migrations.generic)

-- Dictionaries

dictionary.handle_events()

-- Force and Player

script.on_event(defines.events.on_force_created, function(e)
  migrations.init_force(e.force)
  migrations.migrate_force(e.force)
end)

script.on_event(defines.events.on_player_created, function(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end
  migrations.migrate_player(player)
end)

script.on_event({
  defines.events.on_player_toggled_map_editor,
  defines.events.on_player_cheat_mode_enabled,
  defines.events.on_player_cheat_mode_disabled,
}, function(e)
  local player_gui = gui.get(e.player_index)
  if player_gui then
    gui.update_tech_info_footer(player_gui)
  end
end)

script.on_event(defines.events.on_player_changed_surface, function(e)
  -- Recreate GUI if the force changed
  gui.get(e.player_index)
end)

-- Gui

gui.handle_events()

script.on_event(defines.events.on_gui_opened, function(e)
  local player = game.get_player(e.player_index)
  if not player or player.opened_gui_type ~= defines.gui_type.research then
    return
  end
  local player_gui = gui.get(e.player_index)
  if player_gui and not player_gui.state.opening_graph then
    local opened = player.opened --[[@as LuaTechnology?]]
    player.opened = nil
    gui.show(player_gui, opened and opened.name or nil)
  end
end)

script.on_event(defines.events.on_gui_closed, function(e)
  if gui.dispatch(e) or e.gui_type ~= defines.gui_type.research then
    return
  end
  local player_gui = gui.get(e.player_index)
  if player_gui and player_gui.elems.urq_window.visible and not player_gui.state.pinned then
    player_gui.player.opened = player_gui.elems.urq_window
  end
end)

script.on_event("urq-focus-search", function(e)
  local player_gui = gui.get(e.player_index)
  if not player_gui then
    return
  end
  local player = game.get_player(e.player_index)
  if not player or player.opened ~= player_gui.elems.urq_window then
    return
  end
  gui.toggle_search(player_gui)
end)

script.on_event("urq-toggle-gui", function(e)
  local player_gui = gui.get(e.player_index)
  if player_gui then
    gui.toggle_visible(player_gui)
  end
end)

script.on_event(defines.events.on_lua_shortcut, function(e)
  if e.prototype_name ~= "urq-toggle-gui" then
    return
  end
  local player_gui = gui.get(e.player_index)
  if player_gui then
    gui.toggle_visible(player_gui)
  end
end)

-- Research

script.on_event(defines.events.on_research_started, function(e)
  local technology = e.research
  local force = technology.force
  local force_table = global.forces[force.index]
  if not force_table then
    return
  end
  util.ensure_queue_disabled(force)

  local level = technology.level
  if research_queue.contains(force_table.queue, technology, level) then
    if force_table.queue.head.technology == technology then
      return
    end
    research_queue.remove(force_table.queue, technology, level)
  end
  research_queue.push(force_table.queue, technology, level)
  util.schedule_force_update(force)
end)

script.on_event(defines.events.on_research_cancelled, function(e)
  local force = e.force
  local force_table = global.forces[force.index]
  if not force_table then
    return
  end
  util.ensure_queue_disabled(force)

  local force_queue = force_table.queue
  if force_queue.paused or force_queue.updating_active_research then
    return
  end
  local technologies = force.technologies
  for tech_name in pairs(e.research) do
    local technology = technologies[tech_name]
    research_queue.remove(force_queue, technology, technology.level)
  end
  util.schedule_force_update(force)
end)

script.on_event(defines.events.on_research_finished, function(e)
  local technology = e.research
  local force = technology.force
  local force_table = global.forces[force.index]
  if not force_table then
    return
  end
  util.ensure_queue_disabled(force)

  local level = technology.level
  -- For multi-level techs, we want to remove the level that was just finished, not the new level.
  -- If `researched` is true, then this was the last level and it won't have incremented.
  if flib_technology.is_multilevel(technology) and not technology.researched then
    level = level - 1
  end
  if research_queue.contains(force_table.queue, technology, level) then
    research_queue.requeue_multilevel(force_table.queue)
    research_queue.remove(force_table.queue, technology, level, true)
  end

  util.schedule_force_update(force)
end)

script.on_event(defines.events.on_research_reversed, function(e)
  local technology = e.research
  local force = technology.force
  local force_table = global.forces[force.index]
  if not force_table then
    return
  end
  util.ensure_queue_disabled(force)
  util.schedule_force_update(force)
end)

-- Settings

script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
  if e.setting == "urq-show-disabled-techs" then
    local player_gui = gui.get(e.player_index)
    if player_gui then
      gui.update(player_gui)
    end
  elseif e.setting == "urq-show-control-hints" then
    local player = game.get_player(e.player_index)
    if not player then
      return
    end
    gui.new(player)
  end
end)

-- Tick

script.on_event(defines.events.on_tick, function(e)
  dictionary.on_tick()
  -- Update force GUIs
  if next(global.update_force_guis) then
    for force_index in pairs(global.update_force_guis) do
      local force_table = global.forces[force_index]
      research_queue.update_all_research_states(force_table.queue)
      research_queue.update_active_research(force_table.queue)
      gui.update_force(force_table.force)
    end
    global.update_force_guis = {}
  end
  -- Filter technology lists
  for player_index, tick in pairs(global.filter_tech_list) do
    if tick <= e.tick then
      local player_gui = gui.get(player_index)
      if player_gui and player_gui.elems.urq_window.visible then
        gui.filter_tech_list(player_gui)
      end
      global.filter_tech_list[player_index] = nil
    end
  end
end)

--- @param force LuaForce
--- @param force_table ForceTable
--- @param current_research LuaTechnology
local function update_force_durations(force, force_table, current_research)
  local current_progress = force.research_progress
  local research_time = current_research.research_unit_energy
    * flib_technology.get_research_unit_count(current_research)

  local progress_delta = current_progress - force_table.last_research_progress
  local tick_delta = game.tick - force_table.last_research_progress_tick

  local normalized_speed = (progress_delta * research_time) / tick_delta

  force_table.last_research_progress = current_progress
  force_table.last_research_progress_tick = game.tick
  force_table.research_speed = normalized_speed

  research_queue.update_durations(force_table.queue)

  gui.update_force_progress(force)
end

script.on_nth_tick(60, function()
  for force_index, force_table in pairs(global.forces) do
    local force = game.forces[force_index]
    if not force then
      global.forces[force_index] = nil
      goto continue
    end
    local current_research = force.current_research
    if current_research then
      update_force_durations(force, force_table, current_research)
    end
    ::continue::
  end
end)
