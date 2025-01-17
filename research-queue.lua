local format = require("__flib__.format")
local math = require("__flib__.math")
local flib_technology = require("__flib__.technology")

local constants = require("constants")
local util = require("util")

--- @class ResearchQueueNode
--- @field technology LuaTechnology
--- @field level uint
--- @field duration string
--- @field key string
--- @field next ResearchQueueNode?

--- @class TechnologyAndLevel
--- @field technology LuaTechnology
--- @field level uint

--- @class ResearchQueue
--- @field force LuaForce
--- @field force_table ForceTable
--- @field head ResearchQueueNode?
--- @field len uint
--- @field lookup table<string, ResearchQueueNode>
--- @field paused boolean
--- @field requeue_multilevel boolean
--- @field updating_active_research boolean

--- @class ResearchQueueMod
local research_queue = {}

--- @param self ResearchQueue
function research_queue.clear(self)
  while self.head do
    research_queue.remove(self, self.head.technology, self.head.level)
  end
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level boolean|uint?
--- @return boolean
function research_queue.contains(self, technology, level)
  if not flib_technology.is_multilevel(technology) then
    return not not self.lookup[technology.name]
  end

  local base_name = flib_technology.get_base_name(technology)
  if level and type(level) == "number" then
    -- This level
    return not not self.lookup[base_name .. "-" .. level]
  elseif level and technology.prototype.max_level ~= math.max_uint then
    local base_key = base_name .. "-"
    -- All levels
    for i = technology.level, technology.prototype.max_level do
      if not self.lookup[base_key .. i] then
        return false
      end
    end
    return true
  else
    -- Any level
    for key in pairs(self.lookup) do
      if string.find(key, base_name, nil, true) then
        return true
      end
    end
    return false
  end
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @return uint
function research_queue.get_highest_level(self, technology)
  local node = self.head
  local highest = 0
  while node do
    if node.technology == technology then
      highest = math.max(node.level, highest)
    end
    node = node.next
  end
  return highest
end

--- @param technology LuaTechnology
local function are_prereqs_satisfied(technology)
  for _, prerequisite in pairs(technology.prerequisites) do
    if not prerequisite.researched then
      return false
    end
  end
  return true
end

--- @param technology LuaTechnology
--- @param queue ResearchQueue
local function are_prereqs_satisfied_or_queued(technology, queue)
  for _, prerequisite in pairs(technology.prerequisites) do
    if not prerequisite.researched and not research_queue.contains(queue, prerequisite, true) then
      return false
    end
  end
  return true
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @return ResearchState
function research_queue.get_research_state(self, technology)
  if technology.researched then
    return constants.research_state.researched
  end
  if technology.prototype.hidden or not technology.enabled then
    return constants.research_state.disabled
  end
  if are_prereqs_satisfied(technology) then
    return constants.research_state.available
  end
  if are_prereqs_satisfied_or_queued(technology, self) then
    return constants.research_state.conditionally_available
  end
  return constants.research_state.not_available
end

--- Add a technology and its prerequisites to the queue.
--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level uint
--- @param index integer?
--- @return LocalisedString?
local function push(self, technology, level, index)
  -- Update flag and length
  self.len = self.len + 1
  -- Add to linked list
  local key = flib_technology.get_leveled_name(technology, level)
  --- @type ResearchQueueNode
  local new_node = { technology = technology, level = level, duration = "[img=infinity]", key = key }
  self.lookup[key] = new_node
  if not self.head or index == 1 then
    new_node.next = self.head
    self.head = new_node
  elseif index then
    local node = self.head
    while node and node.next and index > 2 do
      index = index - 1
      node = node.next
    end
    -- This shouldn't ever fail...
    if node then
      new_node.next = node.next
      node.next = new_node
    end
  else
    local node = self.head
    while node and node.next do
      node = node.next
    end
    -- This shouldn't ever fail...
    node.next = new_node
  end

  util.schedule_force_update(self.force)
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @return LocalisedString?
function research_queue.instant_research(self, technology)
  local research_state = self.force_table.research_states[technology.name]
  if research_state == constants.research_state.researched then
    return { "message.urq-already-researched" }
  end
  if research_state == constants.research_state.available then
    technology.researched = true
    return
  end
  local prerequisites = global.technology_prerequisites[technology.name] or {}
  local technologies = self.force.technologies
  for i = 1, #prerequisites do
    local prerequisite = technologies[prerequisites[i]]
    if not prerequisite.researched then
      prerequisite.researched = true
    end
  end
  technology.researched = true
end

--- This does not account for prerequisites
--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level uint
function research_queue.move_to_front(self, technology, level)
  local node, prev = self.head, nil
  while node and (node.technology ~= technology or node.level ~= level) do
    prev = node
    node = node.next
  end
  if not node or not prev then
    return
  end
  prev.next = node.next
  node.next = self.head
  self.head = node
end

--- @param force LuaForce
--- @param force_table ForceTable
--- @return ResearchQueue
function research_queue.new(force, force_table)
  --- @type ResearchQueue
  return {
    force = force,
    force_table = force_table,
    --- @type ResearchQueueNode?
    head = nil,
    len = 0,
    --- @type table<string, ResearchQueueNode>
    lookup = {},
    paused = false,
    requeue_multilevel = false,
    updating_active_research = true,
  }
end

--- @param to_research TechnologyAndLevel[]
--- @param technology LuaTechnology
--- @param level uint?
--- @param queue ResearchQueue?
local function add_technology(to_research, technology, level, queue)
  local lower = technology.level
  if queue then
    lower = math.clamp(research_queue.get_highest_level(queue, technology) + 1, lower, technology.prototype.max_level) --[[@as uint]]
  end
  for i = lower, level or technology.prototype.max_level do
    --- @cast i uint
    to_research[#to_research + 1] = { technology = technology, level = i }
  end
end

--- Add a technology and its prerequisites to the queue.
--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level uint
--- @return LocalisedString?
function research_queue.push(self, technology, level)
  local research_state = self.force_table.research_states[technology.name]
  if research_state == constants.research_state.researched then
    return { "message.urq-already-researched" }
  elseif research_state == constants.research_state.disabled then
    return { "message.urq-tech-is-disabled" }
  elseif research_queue.contains(self, technology, level) then
    return { "message.urq-already-in-queue" }
  end
  --- @type TechnologyAndLevel[]
  local to_research = {}
  if research_state == constants.research_state.not_available then
    -- Add all prerequisites to research this technology ASAP
    local technologies = self.force.technologies
    local technology_prerequisites = global.technology_prerequisites[technology.name] or {}
    for i = 1, #technology_prerequisites do
      local prerequisite_name = technology_prerequisites[i]
      local prerequisite = technologies[prerequisite_name]
      local prerequisite_research_state = self.force_table.research_states[prerequisite_name]
      if prerequisite_research_state == constants.research_state.disabled then
        return { "message.urq-has-disabled-prerequisites" }
      end
      if
        not research_queue.contains(self, prerequisite, true)
        and prerequisite_research_state ~= constants.research_state.researched
      then
        add_technology(to_research, prerequisite)
      end
    end
  end
  add_technology(to_research, technology, level, self)
  -- Check for errors
  local num_to_research = #to_research
  if num_to_research > constants.queue_limit then
    return { "message.urq-too-many-unresearched-prerequisites" }
  else
    local len = self.len
    -- It shouldn't ever be greater... right?
    if len >= constants.queue_limit then
      return { "message.urq-queue-is-full" }
    elseif len + num_to_research > constants.queue_limit then
      return { "message.urq-too-many-prerequisites-queue-full" }
    end
  end
  for i = 1, #to_research do
    local to_research = to_research[i]
    push(self, to_research.technology, to_research.level)
  end
end

--- Add a technology and its prerequisites to the front of the queue, moving prerequisites if required.
--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level uint
function research_queue.push_front(self, technology, level)
  local research_state = self.force_table.research_states[technology.name]
  if research_state == constants.research_state.researched then
    return { "message.urq-already-researched" }
  elseif research_queue.contains(self, technology, level) then
    -- TODO: Move to front of queue
    return { "message.urq-already-in-queue" }
  end
  --- @type TechnologyAndLevel[]
  local to_research = {}
  --- @type TechnologyAndLevel[]
  local to_move = {}
  -- Add all prerequisites to research this technology ASAP
  local technologies = self.force.technologies
  local technology_prerequisites = global.technology_prerequisites[technology.name] or {}
  for i = 1, #technology_prerequisites do
    local prerequisite_name = technology_prerequisites[i]
    local prerequisite = technologies[prerequisite_name]
    local prerequisite_research_state = self.force_table.research_states[prerequisite_name]
    local in_queue = research_queue.contains(self, prerequisite, true)
    if in_queue then
      add_technology(to_move, prerequisite)
    elseif prerequisite_research_state ~= constants.research_state.researched then
      add_technology(to_research, prerequisite)
    end
  end
  -- Move higher levels of this tech forward
  if flib_technology.is_multilevel(technology) and research_queue.contains(self, technology, true) then
    local highest = research_queue.get_highest_level(self, technology)
    add_technology(to_move, technology, highest)
  end
  add_technology(to_research, technology, level, self)
  -- Check for errors
  local num_to_research = #to_research
  if num_to_research > constants.queue_limit then
    return { "message.urq-too-many-unresearched-prerequisites" }
  else
    local len = self.len
    -- It shouldn't ever be greater... right?
    if len >= constants.queue_limit then
      return { "message.urq-queue-is-full" }
    elseif len + num_to_research > constants.queue_limit then
      return { "message.urq-too-many-prerequisites-queue-full" }
    end
  end
  local num_to_move = #to_move
  for i = num_to_move, 1, -1 do
    local to_move = to_move[i]
    research_queue.move_to_front(self, to_move.technology, to_move.level)
  end
  for i = 1, #to_research do
    local to_research = to_research[i]
    push(self, to_research.technology, to_research.level, num_to_move + i)
  end
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level uint
--- @param skip_validation boolean?
--- @return boolean?
function research_queue.remove(self, technology, level, skip_validation)
  local key = flib_technology.get_leveled_name(technology, level)
  if not self.lookup[key] then
    return
  end
  -- Remove from linked list
  local node, prev = self.head, nil
  while node and (node.technology ~= technology or node.level ~= level) do
    prev = node
    node = node.next
  end
  if not node then
    return
  end
  -- Remove node and decrement length
  self.lookup[key] = nil
  self.len = self.len - 1
  if node == self.head then
    self.head = node.next
  else
    prev.next = node.next
  end

  util.schedule_force_update(self.force)

  if skip_validation then
    return
  end
  -- Remove descendants
  local technologies = self.force.technologies
  local descendants = global.technology_descendants[technology.name]
  local is_multilevel = flib_technology.is_multilevel(technology)
  if descendants then
    for _, descendant_name in pairs(descendants) do
      local descendant = technologies[descendant_name]
      local level = descendant.level
      if is_multilevel then
        level = level + 1
      end
      if research_queue.contains(self, descendant, level) then
        research_queue.remove(self, descendant, level)
      end
    end
  end
  -- Remove all levels above this one
  if is_multilevel and technology.level <= level then
    local node = self.head
    while node do
      if node.technology == technology and node.level > level then
        research_queue.remove(self, technology, node.level)
      end
      node = node.next
    end
  end
end

--- @param self ResearchQueue
function research_queue.requeue_multilevel(self)
  if not self.requeue_multilevel then
    return
  end
  local head = self.head
  if not head then
    return
  end
  local technology = head.technology
  if not flib_technology.is_multilevel(technology) then
    return
  end
  local next_level = research_queue.get_highest_level(self, technology) + 1
  if next_level > technology.prototype.max_level then
    return
  end
  research_queue.push(self, technology, next_level)
end

--- @param self ResearchQueue
function research_queue.toggle_paused(self)
  self.paused = not self.paused
  research_queue.update_active_research(self)
end

--- @param self ResearchQueue
function research_queue.toggle_requeue_multilevel(self)
  self.requeue_multilevel = not self.requeue_multilevel
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
function research_queue.unresearch(self, technology)
  local technologies = self.force.technologies
  local research_states = self.force_table.research_states

  --- @param technology LuaTechnology
  local function propagate(technology)
    local descendants = global.technology_descendants[technology.name] or {}
    for i = 1, #descendants do
      local descendant_name = descendants[i]
      if research_states[descendant_name] == constants.research_state.researched then
        local descendant_data = technologies[descendant_name]
        propagate(descendant_data)
      end
    end
    technology.researched = false
  end

  propagate(technology)
end

--- @param self ResearchQueue
function research_queue.update_active_research(self)
  local head = self.head
  if not self.paused and head then
    local current_research = self.force.current_research
    if not current_research or head.technology.name ~= current_research.name then
      self.updating_active_research = true
      self.force.add_research(head.technology)
      self.updating_active_research = false
      self.force_table.last_research_progress = flib_technology.get_research_progress(head.technology, head.level)
    end
  else
    self.updating_active_research = true
    self.force.cancel_current_research()
    self.updating_active_research = false
    self.force_table.last_research_progress = 0
  end
  self.force_table.last_research_progress_tick = game.tick
end

--- @param self ResearchQueue
function research_queue.update_durations(self)
  local speed = self.force_table.research_speed
  local duration = 0
  local node = self.head
  while node do
    if speed == 0 then
      node.duration = "[img=infinity]"
    else
      local technology, level = node.technology, node.level
      local progress = flib_technology.get_research_progress(technology, level)
      duration = duration
        + (1 - progress)
          * flib_technology.get_research_unit_count(technology, node.level)
          * technology.research_unit_energy
          / speed
      node.duration = format.time(duration --[[@as uint]])
    end
    node = node.next
  end
end

--- @param self ResearchQueue
function research_queue.update_all_research_states(self)
  for _, technology in pairs(self.force.technologies) do
    local order = global.technology_order[technology.name]
    local groups = self.force_table.technology_groups
    local research_states = self.force_table.research_states
    local previous_state = research_states[technology.name]
    local new_state = research_queue.get_research_state(self, technology)
    if new_state ~= previous_state then
      groups[previous_state][order] = nil
      groups[new_state][order] = technology
      research_states[technology.name] = new_state
    end
  end
end

--- @param self ResearchQueue
function research_queue.verify_integrity(self)
  local old_head = self.head
  self.head, self.lookup, self.len = nil, {}, 0
  local node = old_head
  local technologies = self.force.technologies
  while node do
    local old_technology, old_level = node.technology, node.level
    if old_technology.valid then
      local technology = technologies[old_technology.name]
      if old_level >= technology.prototype.level and old_level <= technology.prototype.max_level then
        research_queue.push(self, technology, technology.prototype.level)
      end
    end
    node = node.next
  end
end

return research_queue
