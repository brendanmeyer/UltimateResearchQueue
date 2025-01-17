local flib_format = require("__flib__.format")
local flib_math = require("__flib__.math")
local flib_table = require("__flib__.table")
local flib_gui_templates = require("__flib__.gui-templates")
local flib_technology = require("__flib__.technology")

local constants = require("constants")
local util = require("util")

local gui_util = {}

--- @param technology_name string
--- @param upgrade_group LuaTechnologyPrototype[]
--- @param research_states table<string, ResearchState>
function gui_util.check_upgrade_group(technology_name, upgrade_group, research_states)
  if research_states[technology_name] == constants.research_state.researched then
    -- Show if highest researched
    for i = #upgrade_group, 1, -1 do
      local other_tech_name = upgrade_group[i].name
      if research_states[other_tech_name] == constants.research_state.researched then
        return other_tech_name == technology_name
      end
    end
  else
    -- Show if lowest unresearched
    for i = 1, #upgrade_group do
      local other_tech_name = upgrade_group[i].name
      if research_states[other_tech_name] ~= constants.research_state.researched then
        return other_tech_name == technology_name
      end
    end
  end
end

--- @param effect TechnologyModifier
--- @param show_controls boolean
function gui_util.effect_button(effect, show_controls)
  --- @type LocalisedString?, LocalisedString?, ElemID?
  local sprite, tooltip, elem_tooltip

  if effect.type == "ammo-damage" then
    sprite = global.effect_icons[effect.ammo_category]
    tooltip =
      { "modifier-description." .. effect.ammo_category .. "-damage-bonus", tostring(effect.modifier * 100) .. "%" }
  elseif effect.type == "give-item" then
    sprite = "item/" .. effect.item
    elem_tooltip = { type = "item", name = effect.item }
    if show_controls and script.active_mods["RecipeBook"] then
      tooltip = { "gui.urq-tooltip-view-in-recipe-book" }
    end
  elseif effect.type == "gun-speed" then
    sprite = global.effect_icons[effect.ammo_category]
    tooltip = {
      "modifier-description." .. effect.ammo_category .. "-shooting-speed-bonus",
      tostring(effect.modifier * 100) .. "%",
    }
  elseif effect.type == "nothing" then
    tooltip = effect.effect_description
  elseif effect.type == "turret-attack" then
    sprite = "entity/" .. effect.turret_id
    tooltip = {
      "modifier-description." .. effect.turret_id .. "-attack-bonus",
      tostring(effect.modifier * 100) .. "%",
    }
  elseif effect.type == "unlock-recipe" then
    sprite = "recipe/" .. effect.recipe
    elem_tooltip = { type = "recipe", name = effect.recipe }
    if show_controls and script.active_mods["RecipeBook"] then
      tooltip = { "gui.urq-tooltip-view-in-recipe-book" }
    end
  else
    sprite = global.effect_icons[effect.type] or ("utility/" .. string.gsub(effect.type, "%-", "_") .. "_modifier_icon")
    local modifier = effect.modifier
    --- @type LocalisedString
    local formatted = tostring(modifier)
    local format = constants.effect_display_type[effect.type]
    if format then
      if format == "float" then
        formatted = tostring(flib_math.round(modifier, 0.01))
      elseif format == "float_percent" then
        formatted = { "format-percent", tostring(flib_math.round(modifier * 100, 0.01)) }
      elseif format == "signed" or format == "unsigned" then
        formatted = tostring(flib_math.round(modifier))
      elseif format == "ticks" then
        formatted = util.format_time_short(effect.modifier)
      end
    end
    tooltip = { "modifier-description." .. effect.type, formatted }
  end

  local overlay_constant = constants.overlay_constant[effect.type]
  --- @type GuiElemDef?
  local overlay_elem
  if overlay_constant then
    overlay_elem =
      { type = "sprite-button", style = "transparent_slot", sprite = overlay_constant, ignored_by_interaction = true }
  end

  return {
    type = "sprite-button",
    style = "transparent_slot",
    sprite = sprite or "utility/nothing_modifier_icon",
    number = effect.count,
    tooltip = tooltip,
    elem_tooltip = elem_tooltip,
    overlay_elem,
  }
end

--- @param name string
--- @param sprite string
--- @param tooltip LocalisedString
--- @param action function
--- @return GuiElemDef
function gui_util.frame_action_button(name, sprite, tooltip, action)
  return {
    type = "sprite-button",
    name = name,
    style = "frame_action_button",
    tooltip = tooltip,
    sprite = sprite .. "_white",
    hovered_sprite = sprite .. "_black",
    clicked_sprite = sprite .. "_black",
    handler = { [defines.events.on_gui_click] = action },
  }
end

--- @class TechnologySlotProperties
--- @field max_level_str string
--- @field research_state_str string
--- @field style string

--- @param technology LuaTechnology
--- @param research_state ResearchState
--- @return TechnologySlotProperties
function gui_util.get_technology_slot_properties(technology, research_state)
  local max_level_str = technology.prototype.max_level == flib_math.max_uint and "[img=infinity]"
    or tostring(technology.prototype.max_level)
  local research_state_str = flib_table.find(flib_technology.research_state, research_state)
  local style = "flib_technology_slot_" .. research_state_str
  if technology.upgrade or flib_technology.is_multilevel(technology) or technology.prototype.level > 1 then
    style = style .. "_multilevel"
  end

  return { max_level_str = max_level_str, research_state_str = research_state_str, style = style }
end

--- @param elem LuaGuiElement
function gui_util.is_double_click(elem)
  local tags = elem.tags
  local last_click_tick = tags.last_click_tick or 0
  local is_double_click = game.ticks_played - last_click_tick < 20
  if is_double_click then
    tags.last_click_tick = nil
  else
    tags.last_click_tick = game.ticks_played
  end
  elem.tags = tags
  return is_double_click
end

--- @param technology LuaTechnology
--- @param query string
--- @param dictionaries table<string, TranslatedDictionary>?
--- @return boolean
function gui_util.match_search_strings(technology, query, dictionaries)
  local to_search = {}
  if dictionaries then
    to_search[#to_search + 1] = dictionaries.technology[technology.name]
    local effects = technology.effects
    for i = 1, #effects do
      local effect = effects[i]
      if effect.type == "unlock-recipe" then
        to_search[#to_search + 1] = dictionaries.recipe[effect.recipe]
      end
    end
  else
    to_search[#to_search + 1] = technology.name
  end
  for _, str in pairs(to_search) do
    if string.find(string.lower(str), query, 1, true) then
      return true
    end
  end
  return false
end

--- @param element LuaGuiElement
--- @param parent LuaGuiElement
--- @param index number
function gui_util.move_to(element, parent, index)
  --- @cast index uint
  local dummy = parent.add({ type = "empty-widget", index = index })
  parent.swap_children(element.get_index_in_parent(), index)
  dummy.destroy()
end

--- @param caption LocalisedString
--- @param table_name string
function gui_util.tech_info_sublist(caption, table_name)
  return {
    type = "flow",
    direction = "vertical",
    {
      type = "line",
      direction = "horizontal",
      style_mods = { left_margin = -2, right_margin = -2, top_margin = 4 },
    },
    { type = "label", style = "heading_2_label", caption = caption },
    {
      type = "frame",
      style = "urq_tech_list_frame",
      { type = "table", name = table_name, style = "slot_table", column_count = 6 },
    },
  }
end

--- @param parent LuaGuiElement
--- @param technology LuaTechnology
--- @param level uint
--- @param research_state ResearchState
--- @param show_controls boolean
--- @param on_click GuiElemHandler
--- @param is_selected boolean?
--- @param name string?
--- @param index uint?
--- @return LuaGuiElement
function gui_util.technology_slot(
  parent,
  technology,
  level,
  research_state,
  show_controls,
  on_click,
  is_selected,
  name,
  index
)
  local slot = flib_gui_templates.technology_slot(parent, technology, level, research_state, on_click, {
    cost = flib_technology.get_research_unit_count(technology, level),
    level = level,
    research_state = research_state,
    tech_name = technology.name,
  }, index)
  slot.name = name or technology.name
  slot.add({
    type = "label",
    name = "duration_label",
    style = "urq_technology_slot_duration_label",
    ignored_by_interaction = true,
  })
  if is_selected then
    slot.toggled = is_selected
  end
  if show_controls then
    --- @type LocalisedString
    local tooltip = {
      "",
      { "gui.urq-tooltip-view-details" },
      { "gui.urq-tooltip-add-to-queue" },
      { "gui.urq-tooltip-add-to-queue-front" },
      { "gui.urq-tooltip-remove-from-queue" },
    }
    if script.active_mods["RecipeBook"] then
      tooltip[#tooltip + 1] = { "", "\n", { "gui.urq-tooltip-view-in-recipe-book" } }
    end
    slot.tooltip = tooltip
  end

  if not flib_technology.is_multilevel(technology) then
    return slot
  end

  -- We can't use built-in tooltips for multi-level technologies.

  slot.elem_tooltip = nil

  --- @type LocalisedString
  local tooltip = { "" }
  -- Title
  local name = technology.localised_name
  if flib_technology.is_multilevel(technology) then
    name = { "", name, " ", level }
  end
  tooltip[#tooltip + 1] = { "gui.urq-tooltip-title", name }
  -- Description
  tooltip[#tooltip + 1] = { "?", { "", "\n", technology.localised_description }, "" }
  -- Cost
  local cost = flib_technology.get_research_unit_count(technology, level)
  local ingredients_tt = ""
  for _, ingredient in pairs(technology.research_unit_ingredients) do
    ingredients_tt = ingredients_tt .. "[img=item/" .. ingredient.name .. "]" .. ingredient.amount
  end
  tooltip[#tooltip + 1] = {
    "",
    "\n[",
    ingredients_tt,
    " [img=quantity-time][font=default-semibold]",
    flib_format.number(technology.research_unit_energy / 60, true),
    "[/font]] × ",
    flib_format.number(cost),
  }
  local existing = slot.tooltip
  if existing then
    tooltip[#tooltip + 1] = { "", "\n", existing }
  end
  slot.tooltip = tooltip

  return slot
end

--- @param elem LuaGuiElement
--- @param value boolean
--- @param sprite_base string
function gui_util.toggle_frame_action_button(elem, sprite_base, value)
  if value then
    elem.style = "flib_selected_frame_action_button"
    elem.sprite = sprite_base .. "_black"
  else
    elem.style = "frame_action_button"
    elem.sprite = sprite_base .. "_white"
  end
end

--- @param self Gui
--- @param elem_table LuaGuiElement
--- @param handler function
--- @param technologies LuaTechnology[]
function gui_util.update_technology_info_sublist(self, elem_table, handler, technologies)
  local selected = self.state.selected or {}
  local research_states = self.force_table.research_states
  local show_controls = self.player.mod_settings["urq-show-control-hints"].value --[[@as boolean]]
  local show_disabled = self.player.mod_settings["urq-show-disabled-techs"].value --[[@as boolean]]
  elem_table.clear()
  local added = false
  for _, technology in pairs(technologies) do
    local research_state = research_states[technology.name]
    if util.should_show(technology, research_state, show_disabled) then
      added = true
      gui_util.technology_slot(
        elem_table,
        technology,
        technology.level,
        research_state,
        show_controls,
        handler,
        selected.technology == technology and selected.level == technology.level
      )
    end
  end
  if added then
    elem_table.parent.parent.visible = true
  else
    elem_table.parent.parent.visible = false
  end
end

--- @param button LuaGuiElement
--- @param technology LuaTechnology
--- @param level uint
--- @param research_state ResearchState
--- @param in_queue boolean
--- @param is_selected boolean?
function gui_util.update_technology_slot(button, technology, level, research_state, in_queue, is_selected)
  local properties = gui_util.get_technology_slot_properties(technology, research_state)
  local tags = button.tags
  button.style = properties.style
  button.toggled = is_selected or false
  if tags.research_state ~= research_state then
    if research_state == constants.research_state.researched then
      button.progressbar.visible = false
      button.progressbar.value = 0
    end
    if technology.upgrade or flib_technology.is_multilevel(technology) or technology.prototype.level > 1 then
      button.level_label.style = "flib_technology_slot_level_label_" .. properties.research_state_str
    end
    if flib_technology.is_multilevel(technology) then
      button.level_range_label.style = "flib_technology_slot_level_range_label_" .. properties.research_state_str
    end
    tags.research_state = research_state --[[@as AnyBasic]]
    button.tags = tags
  end
  --- @type LocalisedString?
  local tooltip
  if flib_technology.is_multilevel(technology) then
    if tags.level ~= level then
      tags.level = level
      button.tags = tags
      tooltip = button.tooltip
      tooltip[2][2][4] = level --- @diagnostic disable-line
    end
    local level_label = button.level_label
    if level_label then
      level_label.caption = tostring(level)
    end
    local cost = flib_technology.get_research_unit_count(technology, level)
    if tags.cost ~= cost then
      tags.cost = cost
      if not tooltip then
        tooltip = button.tooltip
      end
      tooltip[4][7] = flib_format.number(cost) --- @diagnostic disable-line
    end
  end
  if tooltip then
    button.tooltip = tooltip
  end
  button.duration_label.visible = in_queue

  button.tags = tags
end

return gui_util
