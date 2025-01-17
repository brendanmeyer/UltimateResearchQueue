local math = require("__flib__.math")

local constants = require("constants")

local util = {}

--- Ensure that the vanilla research queue is disabled
--- @param force LuaForce
function util.ensure_queue_disabled(force)
  if force.research_queue_enabled then
    force.print({ "message.urq-vanilla-queue-disabled" })
    force.research_queue_enabled = false
  end
end

--- @param player LuaPlayer
--- @param text LocalisedString
function util.flying_text(player, text)
  player.create_local_flying_text({
    text = text,
    create_at_cursor = true,
  })
  player.play_sound({ path = "utility/cannot_build" })
end

--- @param ticks number
--- @return LocalisedString
function util.format_time_short(ticks)
  if ticks == 0 then
    return { "time-symbol-seconds-short", 0 }
  end

  local hours = math.floor(ticks / 60 / 60 / 60)
  local minutes = math.floor(ticks / 60 / 60) % 60
  local seconds = math.floor(ticks / 60) % 60
  --- @type LocalisedString
  local result = { "" }
  if hours ~= 0 then
    result[#result + 1] = { "time-symbol-hours-short", hours }
  end
  if minutes ~= 0 then
    result[#result + 1] = { "time-symbol-minutes-short", minutes }
  end
  if seconds ~= 0 then
    result[#result + 1] = { "time-symbol-seconds-short", seconds }
  end
  return result
end

--- @param player LuaPlayer
function util.is_cheating(player)
  local cheat_mode = player.cheat_mode
  if script.active_mods["space-exploration"] and player.controller_type == defines.controllers.god then
    cheat_mode = false
  end
  return cheat_mode or player.controller_type == defines.controllers.editor
end

--- @param force LuaForce
function util.schedule_force_update(force)
  -- FIXME: Tick paused
  global.update_force_guis[force.index] = true
end

--- @param technology LuaTechnology
--- @param research_state ResearchState
--- @param show_disabled boolean
function util.should_show(technology, research_state, show_disabled)
  if technology.prototype.hidden then
    return false
  end
  return show_disabled or technology.visible_when_disabled or research_state ~= constants.research_state.disabled
end

return util
