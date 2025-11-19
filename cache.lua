local dictionary = require("__flib__.dictionary")

local constants = require("constants")
local research_queue = require("research-queue")
local util = require("util")

--- @class Cache
local cache = {}

local function first_entity_prototype(type)
  --- LuaCustomTable does not work with next() and is keyed by name, so we must use pairs()
  for name in pairs(prototypes.get_entity_filtered({ { filter = "type", type = type } })) do
    return "entity/" .. name
  end
end

function cache.build_effect_icons()
  --- Effect icons for dynamic effects. Key is either an effect type or an ammo category name
  --- @type table<string, string>
  local icons = {
    ["follower-robot-lifetime"] = first_entity_prototype("combat-robot"),
    ["laboratory-productivity"] = first_entity_prototype("lab"),
    ["laboratory-speed"] = first_entity_prototype("lab"),
    ["train-braking-force-bonus"] = first_entity_prototype("locomotive"),
    ["worker-robot-battery"] = first_entity_prototype("logistic-robot"),
    ["worker-robot-speed"] = first_entity_prototype("logistic-robot"),
    ["worker-robot-storage"] = first_entity_prototype("logistic-robot"),
  }

  for _, prototype in pairs(prototypes.get_item_filtered({ { filter = "type", type = "ammo" } })) do
    if not prototype.has_flag("hide-from-bonus-gui") then
      local category = prototype.ammo_category
      if not icons[category] then
        icons[category] = "item/" .. prototype.name
      end
    end
  end

  for _, prototype in pairs(prototypes.get_item_filtered({ { filter = "type", type = "capsule" } })) do
    if not prototype.has_flag("hide-from-bonus-gui") then
      local attack_parameters = prototype.capsule_action.attack_parameters
      if attack_parameters then
        for _, category in pairs(attack_parameters.ammo_categories or { attack_parameters.ammo_type.category }) do
          if not icons[category] then
            icons[category] = "item/" .. prototype.name
          end
        end
      end
    end
  end

  for _, prototype in
  pairs(prototypes.get_equipment_filtered({ { filter = "type", type = "active-defense-equipment" } }))
  do
    local attack_parameters = prototype.attack_parameters --[[@as AttackParameters]]
    for _, category in pairs(attack_parameters.ammo_categories or { attack_parameters.ammo_type.category }) do
      if not icons[category] then
        icons[category] = "equipment/" .. prototype.name
      end
    end
  end

  for _, turret_type in pairs({ "electric-turret", "ammo-turret", "artillery-turret", "fluid-turret" }) do
    for _, prototype in pairs(prototypes.get_entity_filtered({ { filter = "type", type = turret_type } })) do
      local attack_parameters = prototype.attack_parameters
      if attack_parameters then
        for _, category in pairs(attack_parameters.ammo_categories or { attack_parameters.ammo_type.category }) do
          if not icons[category] then
            icons[category] = "entity/" .. prototype.name
          end
        end
      end
    end
  end

  for _, prototype in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "combat-robot" } })) do
    local attack_parameters = prototype.attack_parameters --[[@as AttackParameters]]
    for _, category in pairs(attack_parameters.ammo_categories or { attack_parameters.ammo_type.category }) do
      if not icons[category] then
        icons[category] = "entity/" .. prototype.name
      end
    end
  end

  for _, prototype in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "land-mine" } })) do
    local ammo_category = prototype.ammo_category
    if ammo_category and not icons[ammo_category] then
      icons[ammo_category] = "entity/" .. prototype.name
    end
  end

  for _, prototype in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "unit" } })) do
    local attack_parameters = prototype.attack_parameters --[[@as AttackParameters]]
    for _, category in pairs(attack_parameters.ammo_categories or { attack_parameters.ammo_type.category }) do
      if not icons[category] then
        icons[category] = "entity/" .. prototype.name
      end
    end
  end

  storage.effect_icons = icons
end

function cache.build_dictionaries()
  -- Build dictionaries
  dictionary.on_init()
  dictionary.new("recipe")
  for name, recipe in pairs(prototypes.recipe) do
    dictionary.add("recipe", name, { "?", recipe.localised_name, name })
  end
  dictionary.new("technology")
  for name, technology in pairs(prototypes.technology) do
    dictionary.add("technology", name, { "?", technology.localised_name, name })
  end
end

function cache.build_technologies()
  local profiler = game.create_profiler()
  -- prototypes.technology is a LuaCustomTable, so we need to convert it to an array
  --- @type LuaTechnologyPrototype[]
  local technologies = {}
  for _, prototype in pairs(prototypes.technology) do
    technologies[#technologies + 1] = prototype
  end

  -- Sort the technologies array
  -- local l_prototypes = {
  --   fluid = prototypes.fluid,
  --   item = prototypes.item,
  -- }
  local l_prototypes = {}
  local n = 0
  for i, v in pairs(prototypes.fluid) do
    l_prototypes[i] = v
  end
  for i, v in pairs(prototypes.item) do
    l_prototypes[i] = v
  end
  log({ "", "Tech Loaded ", profiler })

  profiler.reset()

  -- Build all prerequisites and direct descendants of each technology
  --- @type table<string, string[]?>
  local prerequisites = {}
  --- @type table<string, string[]?>
  local descendants = {}
  --- @type LuaTechnologyPrototype[]
  local base_techs = {}
  -- Step 1: Assemble descendants for each technology and determine base technologies
  for i = 1, #technologies do
    local technology = technologies[i]
    local prerequisites = technology.prerequisites
    if next(prerequisites) then
      local technology_name = technology.name
      for prerequisite_name in pairs(prerequisites) do
        local descendant_prerequisites = descendants[prerequisite_name]
        if not descendant_prerequisites then
          descendant_prerequisites = {}
          descendants[prerequisite_name] = descendant_prerequisites
        end
        descendant_prerequisites[#descendant_prerequisites + 1] = technology_name
      end
    else
      base_techs[#base_techs + 1] = technology
    end
  end
  -- Step 2: Recursively assemble prerequisites for each technology
  local tech_prototypes = prototypes.technology
  local checked = {}
  --- @param tbl {[string]: boolean, [integer]: string}
  --- @param obj string
  local function unique_insert(tbl, obj)
    if not tbl[obj] then
      tbl[obj] = true
      tbl[#tbl + 1] = obj
    end
  end
  --- @param technology LuaTechnologyPrototype
  local function propagate(technology)
    -- If not all of the prerequisites have been checked, then the list would be incomplete
    for prerequisite_name in pairs(technology.prerequisites) do
      if not checked[prerequisite_name] then
        return
      end
    end
    local technology_name = technology.name
    local technology_prerequisites = prerequisites[technology_name] or {}
    local technology_descendants = descendants[technology_name] or {}
    for i = 1, #technology_descendants do
      local descendant_name = technology_descendants[i]
      -- Create the descendant's prerequisite table
      local descendant_prerequisites = prerequisites[descendant_name]
      if not descendant_prerequisites then
        descendant_prerequisites = {}
        prerequisites[descendant_name] = descendant_prerequisites
      end
      -- Add all of this technology's prerequisites to the descendant's prerequisites
      for i = 1, #technology_prerequisites do
        unique_insert(descendant_prerequisites, technology_prerequisites[i])
      end
      -- Add this technology to the descendant's prerequisites
      unique_insert(descendant_prerequisites, technology_name)
    end
    checked[technology_name] = true
    for i = 1, #technology_descendants do
      propagate(tech_prototypes[technology_descendants[i]])
    end
  end
  for _, technology in pairs(base_techs) do
    propagate(technology)
  end

  profiler.stop()
  log({ "", "Prerequisite Generation ", profiler })

  profiler.reset()

  function topologicalSortByLevels(items)
    local inDegree = {}
    local graph = {}
    local levels = {}

    -- Initialize with all items
    for itemId in pairs(items) do
      inDegree[itemId] = 0
      graph[itemId] = {}
    end

    -- Build dependency graph
    for itemId, item in pairs(items) do
      for _, prereqId in ipairs(item) do
        if items[prereqId] then
          graph[prereqId] = graph[prereqId] or {}
          table.insert(graph[prereqId], itemId)
          inDegree[itemId] = (inDegree[itemId] or 0) + 1
        else
          print("Warning: Missing prerequisite '" .. prereqId .. "' for item '" .. itemId .. "'")
        end
      end
    end

    -- Find starting nodes (no prerequisites)
    local queue = {}
    for itemId, degree in pairs(inDegree) do
      if degree == 0 then
        table.insert(queue, itemId)
      end
    end

    -- Process by levels
    local level = 1
    while #queue > 0 do
      levels[level] = {}
      local nextQueue = {}

      for _, itemId in ipairs(queue) do
        table.insert(levels[level], itemId)

        -- Process successors
        for _, successorId in ipairs(graph[itemId] or {}) do
          inDegree[successorId] = inDegree[successorId] - 1
          if inDegree[successorId] == 0 then
            table.insert(nextQueue, successorId)
          end
        end
      end

      table.sort(levels[level]) -- Optional: sort items within level
      queue = nextQueue
      level = level + 1
    end

    -- Check for cycles
    local totalProcessed = 0
    for _, levelItems in pairs(levels) do
      totalProcessed = totalProcessed + #levelItems
    end

    if totalProcessed < #util.tableKeys(items) then
      -- Find the cyclic items
      local cyclicItems = {}
      for itemId in pairs(items) do
        if inDegree[itemId] and inDegree[itemId] > 0 then
          table.insert(cyclicItems, itemId)
        end
      end
      error("Dependency cycle detected involving: " .. table.concat(cyclicItems, ", "))
    end

    return levels
  end

  function levelsToFlatOrder(levels)
    local flat = {}
    for i = 1, #levels do
      for _, itemId in ipairs(levels[i]) do
        table.insert(flat, itemId)
      end
    end
    return flat
  end

  function scienceLevelToFlatOrder(levels)
    local flat = {}
    for i = 1, #levels do
      for _, itemId in ipairs(levels[i].items) do
        table.insert(flat, itemId)
      end
    end
    return flat
  end

  function buildScienceHierarchy(packs)
    local levels = {}
    local processed = {}

    -- Track all science pack dependencies (only science packs, not regular techs)
    local sciencePackDeps = {}
    for packName, prereqs in pairs(packs) do
      sciencePackDeps[packName] = {}
      for _, prereq in ipairs(prereqs) do
        if packs[prereq] then -- Only include if it's a science pack
          table.insert(sciencePackDeps[packName], prereq)
        end
      end
    end

    -- Helper to get dependency depth
    local function getDependencyDepth(packName, depthMap)
      if depthMap[packName] then return depthMap[packName] end

      local maxDepth = 0
      for _, dep in ipairs(sciencePackDeps[packName] or {}) do
        local depDepth = getDependencyDepth(dep, depthMap)
        maxDepth = math.max(maxDepth, depDepth)
      end

      depthMap[packName] = maxDepth + 1
      return depthMap[packName]
    end

    -- Calculate depths for all science packs
    local depthMap = {}
    for packName in pairs(packs) do
      getDependencyDepth(packName, depthMap)
    end

    -- Group by depth
    for packName, depth in pairs(depthMap) do
      levels[depth] = levels[depth] or {}
      table.insert(levels[depth], packName)
    end

    -- Sort levels
    local sortedLevels = {}
    for depth = 1, #levels do
      if levels[depth] then
        table.sort(levels[depth])
        table.insert(sortedLevels, levels[depth])
      end
    end

    return sortedLevels
  end

  -- Function to build item hierarchy based on science pack prerequisites
  function buildItemHierarchy(items, scienceLevels)
    local itemLevels = {}
    local processed = {}

    -- Create a quick lookup for science pack levels
    local sciencePackLevels = {}
    for level, packs in pairs(scienceLevels) do
      for _, pack in ipairs(packs) do
        sciencePackLevels[pack] = level + 1
      end
    end

    -- Process from highest to lowest science level
    for scienceLevel = #scienceLevels + 1, 2, -1 do
      itemLevels[scienceLevel] = itemLevels[scienceLevel] or {}

      for itemId, item in pairs(items) do
        if not processed[itemId] and item then
          -- Check if this item requires any science pack from current level
          local requiresThisLevel = false
          for _, prereq in ipairs(item) do
            if sciencePackLevels[prereq] == scienceLevel then
              requiresThisLevel = true
              break
            end
          end

          -- If it requires science from this level, add to next level
          if requiresThisLevel then
            table.insert(itemLevels[scienceLevel], itemId)
            processed[itemId] = true
          end
        end
      end
    end

    -- Add remaining items to level 1
    itemLevels[1] = {}
    for itemId, item in pairs(items) do
      if not processed[itemId] then
        table.insert(itemLevels[1], itemId)
      end
    end

    -- Clean up empty levels and return
    local cleanLevels = {}
    for level = 1, #scienceLevels + 1 do
      if itemLevels[level] and #itemLevels[level] > 0 then
        table.sort(itemLevels[level])
        cleanLevels[level] = itemLevels[level]
      end
    end

    return cleanLevels
  end

  function getSciencePackCombinations(items, scienceLevels)
    local combinations = {}
    local sciencePackLevels = {}

    -- Create quick lookup for science pack levels
    for level, packs in pairs(scienceLevels) do
      for _, pack in ipairs(packs) do
        sciencePackLevels[pack] = level
      end
    end

    -- Find all unique science pack combinations used by items
    for itemId, item in pairs(items) do
      -- Extract only science packs from prerequisites
      local sciencePacks = {}
      for _, prereq in ipairs(item) do
        if sciencePackLevels[prereq] then
          table.insert(sciencePacks, prereq)
        end
      end

      -- Create unique key for this combination
      if #sciencePacks > 0 then
        table.sort(sciencePacks)
        local comboKey = table.concat(sciencePacks, "|")

        if not combinations[comboKey] then
          combinations[comboKey] = {
            key = comboKey,
            sciencePacks = sciencePacks,
            items = {},
            maxLevel = 0
          }

          -- Calculate max science level in this combination
          for _, pack in ipairs(sciencePacks) do
            combinations[comboKey].maxLevel = math.max(
              combinations[comboKey].maxLevel,
              sciencePackLevels[pack]
            )
          end
        end

        table.insert(combinations[comboKey].items, itemId)
      else
        local comboKey = "<nil>"
        if not combinations[comboKey] then
          combinations[comboKey] = {
            key = comboKey,
            sciencePacks = sciencePacks,
            items = {},
            maxLevel = 0
          }
        end
        table.insert(combinations[comboKey].items, itemId)
      end
    end

    -- CONVERT TO ARRAY BEFORE SORTING
    local combinationsArray = {}
    for _, combo in pairs(combinations) do
      table.insert(combinationsArray, combo)
    end

    -- Now sort the array
    table.sort(combinationsArray, function(a, b)
      if a.maxLevel ~= b.maxLevel then
        return a.maxLevel < b.maxLevel
      end
      if #a.sciencePacks ~= #b.sciencePacks then
        return #a.sciencePacks < #b.sciencePacks
      end
      return a.key < b.key
    end)

    return combinationsArray
  end

  local allTechs = {}
  for _, basetech in pairs(base_techs) do
    allTechs[basetech.name] = {}
  end
  allTechs = util.tableMerge(allTechs, prerequisites)

  local scienceTechs = {}
  for n, t in pairs(allTechs) do
    if n:find("%-science%-pack") then
      scienceTechs[n] = t
    end
  end

  local scienceLevels = buildScienceHierarchy(scienceTechs)
  -- local scienceLevelTechs = buildItemHierarchy(allTechs, scienceLevels)


  -- Build and order combinations
  local combinations = getSciencePackCombinations(allTechs, scienceLevels)
  -- allTechs = topologicalSortByLevels(allTechs)
  allTechs = scienceLevelToFlatOrder(combinations)
  -- table.sort(technologies, function(tech_a, tech_b)
  --   local ingredients_a = tech_a.research_unit_ingredients
  --   local ingredients_b = tech_b.research_unit_ingredients
  --   local len_a = #ingredients_a
  --   local len_b = #ingredients_b
  --   local prerequisites_a = tech_a.prerequisites
  --   local prerequisites_b = tech_b.prerequisites
  --   local len_prereq_a = #util.tableKeys(prerequisites_a)
  --   local len_prereq_b = #util.tableKeys(prerequisites_b)
  --   -- Always put technologies with zero prerequisites at the front
  --   if (len_prereq_a == 0) ~= (len_prereq_b == 0) then
  --     return len_prereq_a == 0
  --   end
  --   -- Always put technologies with the least cost at the front
  --   local cost_a = tech_a.research_unit_count
  --   local cost_b = tech_b.research_unit_count
  --   if cost_a ~= cost_b then
  --     return cost_a < cost_b
  --   end
  --   -- Always put technologies with zero ingredients at the front
  --   -- if (len_a == 0) ~= (len_b == 0) then
  --   --   return len_a == 0
  --   -- end
  --   -- if #ingredients_a > 0 then
  --   --   -- Compare ingredient order strings
  --   --   -- Check the most expensive packs first, and sort based on the first difference
  --   --   for i = 0, math.min(len_a, len_b) - 1 do
  --   --     local ingredient_a = ingredients_a[len_a - i]
  --   --     local ingredient_b = ingredients_b[len_b - i]
  --   --     local order_a = string.sub(l_prototypes[ingredient_a.name].order, 1, 1)
  --   --     local order_b = string.sub(l_prototypes[ingredient_b.name].order, 1, 1)
  --   --     -- Cheaper pack goes in front
  --   --     if order_a ~= order_b then
  --   --       return order_a < order_b
  --   --     end
  --   --   end
  --   --   -- Sort the technology with fewer ingredients in front
  --   --   if len_a ~= len_b then
  --   --     return len_a < len_b
  --   --   end
  --   -- end
  --   -- Compare technology order strings
  --   -- local order_a = string.sub(tech_a.order, 1, 1)
  --   -- local order_b = string.sub(tech_b.order, 1, 1)
  --   -- if order_a ~= order_b then
  --   --   return order_a < order_b
  --   -- end
  --   -- Compare prototype names
  --   return tech_a.name < tech_b.name
  -- end)

  -- Create order lookup and assemble upgrade groups
  --- @type table<string, LuaTechnologyPrototype[]>
  local upgrade_groups = {}
  --- @type table<string, number>
  local order = {}
  for i = #allTechs, 1, -1 do
    local name = allTechs[i]
    order[name] = i
  end
  for i = 1, #technologies do
    local technology = technologies[i]
    if technology.upgrade then
      local base_name = string.match(technology.name, "^(.*)%-%d*$") or technology.name
      local upgrade_group = upgrade_groups[base_name]
      if not upgrade_group then
        upgrade_group = {}
        upgrade_groups[base_name] = upgrade_group
      end
      upgrade_group[#upgrade_group + 1] = technology
    end
  end
  -- Sort upgrade groups
  for _, group in pairs(upgrade_groups) do
    table.sort(group, function(a, b)
      return a.level < b.level
    end)
  end

  profiler.stop()
  log({ "", "Tech Sorting ", profiler })

  storage.num_technologies = #technologies
  storage.technology_order = order
  storage.technology_prerequisites = prerequisites
  storage.technology_descendants = descendants
  storage.technology_upgrade_groups = upgrade_groups
end

--- @param force LuaForce
function cache.init_force(force)
  local force_table = storage.forces[force.index]
  --- @type table<ResearchState, table<uint, LuaTechnology>>
  local technology_groups = {}
  for _, research_state in pairs(constants.research_state) do
    technology_groups[research_state] = {}
  end
  force_table.technology_groups = technology_groups
  --- @type table<string, ResearchState>
  local research_states = {}
  force_table.research_states = research_states
  for name, technology in pairs(force.technologies) do
    local research_state = research_queue.get_research_state(force_table.queue, technology)
    research_states[name] = research_state
    technology_groups[research_state][storage.technology_order[technology.name]] = technology
  end
end

return cache
