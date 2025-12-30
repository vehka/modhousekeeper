-- modhousekeeper
-- v1.0.0 by vehka
-- Norns mod manager with install, update, and removal functionality

local mod = require 'core/mods'
local util = require 'util'
local tabutil = require 'tabutil'

-- Debug mode - set to false to disable debug messages
local DEBUG = false

local function debug(msg)
  if DEBUG then
    print("modhousekeeper: " .. msg)
  end
end

local ModHousekeeper = {
  mods_list_path = _path.code .. "modhousekeeper/mods.list",
  mods_list_local_path = _path.code .. "modhousekeeper/mods.list.local",
  install_path = _path.code,
  settings_path = _path.data .. "modhousekeeper_settings.lua",

  -- Screen/mode state
  current_screen = "mod_list",  -- "mod_list" or "settings"
  screens = {"mod_list", "settings"},

  -- Settings
  settings = {
    disable_animation = false,
    use_local_mods_list = false,
  },
  settings_list = {
    {id = "disable_animation", name = "Disable start animation", type = "toggle"},
    {id = "use_local_mods_list", name = "Use local mods.list", type = "toggle"},
  },
  settings_selected = 1,

  -- UI state
  categories = {},
  all_mods = {},
  flat_list = {},  -- Flattened list for display
  selected_index = 1,
  scroll_offset = 0,
  max_visible = 6,

  -- Confirmation dialog state
  confirm_dialog = nil,  -- {action="install/update/remove", mod_entry=...}

  -- Action menu state
  action_menu = nil,  -- {mod_entry=..., selected=1, items=[...]}

  -- Display state
  message = "",
  message_timer = nil,
}

-- Extract repository name from git URL
function ModHousekeeper.extract_repo_name(url)
  -- Handle URLs like https://github.com/user/reponame or git@github.com:user/reponame.git
  local repo = url:match("([^/]+)%.git$") or url:match("([^/]+)$")
  if repo then
    repo = repo:gsub("%.git$", "")  -- Remove .git suffix if present
  end
  return repo
end

-- Parse mods.list file
function ModHousekeeper.parse_mods_list()
  local path = ModHousekeeper.get_active_mods_list_path()
  local f = io.open(path, "r")
  if not f then
    print("modhousekeeper: ERROR - could not open mods list at " .. path)
    return
  end

  local current_category = nil
  local categories = {}
  local all_mods = {}
  local mod_count = 0

  for line in f:lines() do
    if line:match("%S") then
      local category = line:match("^#%s*(.+)")
      if category then
        current_category = category
        categories[current_category] = {}
        debug("found category: " .. category)
      else
        local fields = {}
        for field in line:gmatch("([^,]+)") do
          local trimmed = field:gsub("^%s*(.-)%s*$", "%1")
          table.insert(fields, trimmed)
        end

        if #fields >= 3 and current_category then
          local mod_entry = {
            name = fields[1],
            url = fields[2],
            description = fields[3],
            alt_repos = {},
            repo_id = ModHousekeeper.extract_repo_name(fields[2]),
            category = current_category,
            installed = false,
            has_update = false,
            installed_url = nil,  -- Track which URL is actually installed
          }

          -- Collect alternative repos as URL/description pairs (fields 4+)
          for i = 4, #fields, 2 do
            if fields[i+1] then
              table.insert(mod_entry.alt_repos, {
                url = fields[i],
                description = fields[i+1]
              })
            end
          end

          table.insert(categories[current_category], mod_entry)
          all_mods[mod_entry.name] = mod_entry
          mod_count = mod_count + 1
        end
      end
    end
  end

  f:close()
  debug("parsed " .. mod_count .. " mods in " .. tabutil.count(categories) .. " categories")

  ModHousekeeper.categories = categories
  ModHousekeeper.all_mods = all_mods
  ModHousekeeper.build_flat_list()
end

-- Build flattened list for display
function ModHousekeeper.build_flat_list()
  local flat = {}

  -- Add settings entry at the top
  table.insert(flat, {type = "settings", name = "SETTINGS"})

  for cat_name, mods in pairs(ModHousekeeper.categories) do
    table.insert(flat, {type = "category", name = cat_name})
    for _, mod_entry in ipairs(mods) do
      table.insert(flat, {type = "mod", data = mod_entry})
    end
  end

  ModHousekeeper.flat_list = flat
  debug("built flat list with " .. #flat .. " items")
end

-- Check installation status of all mods
function ModHousekeeper.check_installation_status()
  for name, mod_entry in pairs(ModHousekeeper.all_mods) do
    local mod_path = ModHousekeeper.install_path .. mod_entry.repo_id
    mod_entry.installed = util.file_exists(mod_path .. "/lib/mod.lua")
  end
  ModHousekeeper.build_flat_list()
end

-- Check for updates (simplified: just check if git repo can be pulled)
function ModHousekeeper.check_updates(callback)
  local checked = 0
  local total = 0

  for name, mod_entry in pairs(ModHousekeeper.all_mods) do
    if mod_entry.installed then
      total = total + 1
    end
  end

  if total == 0 then
    if callback then callback() end
    return
  end

  for name, mod_entry in pairs(ModHousekeeper.all_mods) do
    if mod_entry.installed then
      local mod_path = ModHousekeeper.install_path .. mod_entry.repo_id

      -- Check if updates are available
      norns.system_cmd("cd " .. mod_path .. " && git fetch 2>&1", function(output)
        norns.system_cmd("cd " .. mod_path .. " && git rev-list HEAD...@{u} --count 2>&1", function(count_output)
          local count = tonumber(count_output)
          mod_entry.has_update = count and count > 0

          checked = checked + 1
          if checked >= total then
            ModHousekeeper.build_flat_list()
            if callback then callback() end
          end
        end)
      end)
    end
  end
end

-- Install a mod
function ModHousekeeper.install_mod(mod_entry, callback, install_url)
  local url = install_url or mod_entry.url
  local install_path = ModHousekeeper.install_path .. mod_entry.repo_id
  ModHousekeeper.show_message("Installing " .. mod_entry.name .. "...")

  norns.system_cmd("git clone " .. url .. " " .. install_path .. " 2>&1", function(output)
    if util.file_exists(install_path .. "/lib/mod.lua") then
      mod_entry.installed = true
      mod_entry.installed_url = url
      ModHousekeeper.show_message(mod_entry.name .. " installed!")
      debug("installed " .. mod_entry.name .. " from " .. url)
    else
      ModHousekeeper.show_message("Failed to install " .. mod_entry.name)
      print("modhousekeeper: install failed - " .. mod_entry.name .. "\n" .. output)
    end
    ModHousekeeper.build_flat_list()
    if callback then callback() end
  end)
end

-- Update a mod
function ModHousekeeper.update_mod(mod_entry, callback)
  local mod_path = ModHousekeeper.install_path .. mod_entry.repo_id

  ModHousekeeper.show_message("Updating " .. mod_entry.name .. "...")

  norns.system_cmd("cd " .. mod_path .. " && git pull 2>&1", function(output)
    mod_entry.has_update = false
    ModHousekeeper.show_message(mod_entry.name .. " updated!")
    ModHousekeeper.build_flat_list()
    if callback then callback() end
  end)
end

-- Remove a mod
function ModHousekeeper.remove_mod(mod_entry, callback)
  local mod_path = ModHousekeeper.install_path .. mod_entry.repo_id

  ModHousekeeper.show_message("Removing " .. mod_entry.name .. "...")

  norns.system_cmd("rm -rf " .. mod_path .. " 2>&1", function(output)
    mod_entry.installed = false
    mod_entry.has_update = false
    ModHousekeeper.show_message(mod_entry.name .. " removed!")
    ModHousekeeper.build_flat_list()
    if callback then callback() end
  end)
end

-- Build action menu for a mod
function ModHousekeeper.build_action_menu(mod_entry)
  local items = {}

  -- Add mod description as info item (full text, no truncation)
  table.insert(items, {type = "info", text = mod_entry.description})

  -- Add primary action
  if mod_entry.installed then
    if mod_entry.has_update then
      table.insert(items, {type = "action", text = "Update", action = "update", url = mod_entry.url})
    end
    table.insert(items, {type = "action", text = "Remove", action = "remove"})

    -- If installed from alt repo, offer to reinstall from main
    local is_alt_installed = mod_entry.installed_url and mod_entry.installed_url ~= mod_entry.url
    if is_alt_installed then
      table.insert(items, {
        type = "alt_repo",
        text = "Reinstall from",
        description = "main",
        action = "reinstall",
        url = mod_entry.url
      })
    end

    -- Add alternative repos as reinstall options
    for _, alt in ipairs(mod_entry.alt_repos) do
      -- Skip if this alt is currently installed
      if not (mod_entry.installed_url == alt.url) then
        table.insert(items, {
          type = "alt_repo",
          text = "Reinstall from",
          description = alt.description,
          action = "reinstall",
          url = alt.url
        })
      end
    end
  else
    -- Not installed - offer install from main
    table.insert(items, {type = "action", text = "Install", action = "install", url = mod_entry.url})

    -- Offer install from alt repos
    for _, alt in ipairs(mod_entry.alt_repos) do
      table.insert(items, {
        type = "alt_repo",
        text = "Install from",
        description = alt.description,
        action = "install",
        url = alt.url
      })
    end
  end

  ModHousekeeper.action_menu = {
    mod_entry = mod_entry,
    selected = 2,  -- Start on first action, not description
    items = items
  }
end

-- Show temporary message
function ModHousekeeper.show_message(msg)
  ModHousekeeper.message = msg
  if ModHousekeeper.message_timer then
    clock.cancel(ModHousekeeper.message_timer)
  end
  ModHousekeeper.message_timer = clock.run(function()
    clock.sleep(2)
    ModHousekeeper.message = ""
    mod.menu.redraw()
  end)
  mod.menu.redraw()
end

-- Save settings to file
function ModHousekeeper.save_settings()
  local f = io.open(ModHousekeeper.settings_path, "w")
  if not f then return end
  io.output(f)
  io.write("return {\n")
  for k, v in pairs(ModHousekeeper.settings) do
    local vstr = type(v) == "string" and ("'" .. v .. "'") or tostring(v)
    io.write("  " .. k .. " = " .. vstr .. ",\n")
  end
  io.write("}\n")
  io.close(f)
  debug("settings saved")
end

-- Load settings from file
function ModHousekeeper.load_settings()
  local f = io.open(ModHousekeeper.settings_path, "r")
  if f then
    io.close(f)
    ModHousekeeper.settings = dofile(ModHousekeeper.settings_path)
    debug("settings loaded")
  end
end

-- Create local mods.list copy if it doesn't exist
function ModHousekeeper.create_local_mods_list()
  local f = io.open(ModHousekeeper.mods_list_local_path, "r")
  if f then
    io.close(f)
    return  -- Already exists
  end

  -- Copy from main mods.list
  local source = io.open(ModHousekeeper.mods_list_path, "r")
  if not source then
    print("modhousekeeper: ERROR - could not open mods.list to copy")
    return
  end

  local dest = io.open(ModHousekeeper.mods_list_local_path, "w")
  if not dest then
    io.close(source)
    print("modhousekeeper: ERROR - could not create mods.list.local")
    return
  end

  io.output(dest)
  for line in source:lines() do
    io.write(line .. "\n")
  end

  io.close(source)
  io.close(dest)
  debug("created local mods.list")
end

-- Get the active mods list path based on settings
function ModHousekeeper.get_active_mods_list_path()
  if ModHousekeeper.settings.use_local_mods_list then
    return ModHousekeeper.mods_list_local_path
  else
    return ModHousekeeper.mods_list_path
  end
end

-- Initialize mod
function ModHousekeeper.init()
  local status, err = pcall(function()
    ModHousekeeper.load_settings()
    ModHousekeeper.parse_mods_list()
    ModHousekeeper.check_installation_status()
  end)

  if not status then
    print("modhousekeeper: ERROR during init: " .. tostring(err))
  else
    debug("init complete - " .. tabutil.count(ModHousekeeper.all_mods) .. " mods, " .. #ModHousekeeper.flat_list .. " items")
  end
end

-- Hook: system_post_startup
function ModHousekeeper.system_post_startup()
  print("modhousekeeper: system started")
end

-- Menu UI object
local menu_ui = {}

menu_ui.init = function()
  ModHousekeeper.check_installation_status()
end

menu_ui.deinit = function() end

menu_ui.key = function(n, z)
  if z > 0 then  -- Key down
    if ModHousekeeper.action_menu then
      -- In action menu
      if n == 2 then
        -- K2: Close action menu
        ModHousekeeper.action_menu = nil
        mod.menu.redraw()
      elseif n == 3 then
        -- K3: Execute selected action
        local menu = ModHousekeeper.action_menu
        local item = menu.items[menu.selected]

        if item and (item.type == "action" or item.type == "alt_repo") then
          -- Show confirmation dialog
          ModHousekeeper.confirm_dialog = {
            action = item.action,
            mod_entry = menu.mod_entry,
            url = item.url
          }
          ModHousekeeper.action_menu = nil
          mod.menu.redraw()
        end
      end
    elseif ModHousekeeper.confirm_dialog then
      -- In confirmation dialog
      if n == 2 then
        -- K2: Cancel
        ModHousekeeper.confirm_dialog = nil
        mod.menu.redraw()
      elseif n == 3 then
        -- K3: Confirm action
        local dialog = ModHousekeeper.confirm_dialog
        ModHousekeeper.confirm_dialog = nil

        if dialog.action == "install" or dialog.action == "reinstall" then
          -- For reinstall, first remove then install
          if dialog.action == "reinstall" then
            local mod_path = ModHousekeeper.install_path .. dialog.mod_entry.repo_id
            norns.system_cmd("rm -rf " .. mod_path .. " 2>&1", function()
              dialog.mod_entry.installed = false
              ModHousekeeper.install_mod(dialog.mod_entry, function()
                mod.menu.redraw()
              end, dialog.url)
            end)
          else
            ModHousekeeper.install_mod(dialog.mod_entry, function()
              mod.menu.redraw()
            end, dialog.url)
          end
        elseif dialog.action == "update" then
          ModHousekeeper.update_mod(dialog.mod_entry, function()
            mod.menu.redraw()
          end)
        elseif dialog.action == "remove" then
          ModHousekeeper.remove_mod(dialog.mod_entry, function()
            mod.menu.redraw()
          end)
        end
      end
    elseif ModHousekeeper.current_screen == "settings" then
      -- Settings screen
      if n == 2 then
        -- K2: Return to mod list
        ModHousekeeper.current_screen = "mod_list"
        mod.menu.redraw()
      end
    else
      -- Mod list screen
      if n == 2 then
        -- K2: Return to mod selection menu
        mod.menu.exit()
      elseif n == 3 then
        -- K3: Action on selected item
        local item = ModHousekeeper.flat_list[ModHousekeeper.selected_index]

        if item and item.type == "settings" then
          -- Enter settings mode
          ModHousekeeper.current_screen = "settings"
          mod.menu.redraw()
        elseif item and item.type == "mod" then
          -- Open action menu
          ModHousekeeper.build_action_menu(item.data)
          mod.menu.redraw()
        end
      end
    end
  end
end

menu_ui.enc = function(n, delta)
  if ModHousekeeper.confirm_dialog then
    return  -- Ignore encoder input during confirmation dialog
  end

  if ModHousekeeper.action_menu then
    -- Action menu navigation
    if n == 2 then
      local menu = ModHousekeeper.action_menu
      menu.selected = util.clamp(menu.selected + delta, 1, #menu.items)
    end
  elseif ModHousekeeper.current_screen == "mod_list" then
    -- Mod list screen encoders
    if #ModHousekeeper.flat_list == 0 then
      return  -- Guard against empty list
    end

    if n == 2 then
      -- E2: Scroll through list
      ModHousekeeper.selected_index = util.clamp(
        ModHousekeeper.selected_index + delta,
        1,
        #ModHousekeeper.flat_list
      )

      -- Adjust scroll offset
      if ModHousekeeper.selected_index < ModHousekeeper.scroll_offset + 1 then
        ModHousekeeper.scroll_offset = ModHousekeeper.selected_index - 1
      elseif ModHousekeeper.selected_index > ModHousekeeper.scroll_offset + ModHousekeeper.max_visible then
        ModHousekeeper.scroll_offset = ModHousekeeper.selected_index - ModHousekeeper.max_visible
      end
    elseif n == 3 then
      -- E3: Show confirmation dialog for action
      local item = ModHousekeeper.flat_list[ModHousekeeper.selected_index]
      if item and item.type == "mod" then
        local mod_entry = item.data

        if delta > 0 then
          -- Install or update
          if mod_entry.installed then
            if mod_entry.has_update then
              ModHousekeeper.confirm_dialog = {action = "update", mod_entry = mod_entry}
            else
              ModHousekeeper.show_message(mod_entry.name .. " is up to date")
            end
          else
            ModHousekeeper.confirm_dialog = {action = "install", mod_entry = mod_entry}
          end
        else
          -- Remove
          if mod_entry.installed then
            ModHousekeeper.confirm_dialog = {action = "remove", mod_entry = mod_entry}
          else
            ModHousekeeper.show_message(mod_entry.name .. " not installed")
          end
        end
      end
    end

  elseif ModHousekeeper.current_screen == "settings" then
    -- Settings screen encoders
    if n == 2 then
      -- E2: Navigate settings
      ModHousekeeper.settings_selected = util.clamp(
        ModHousekeeper.settings_selected + delta,
        1,
        #ModHousekeeper.settings_list
      )
    elseif n == 3 then
      -- E3: Toggle setting
      local setting = ModHousekeeper.settings_list[ModHousekeeper.settings_selected]
      if setting.type == "toggle" then
        ModHousekeeper.settings[setting.id] = not ModHousekeeper.settings[setting.id]

        -- Handle special actions for certain settings
        if setting.id == "use_local_mods_list" and ModHousekeeper.settings[setting.id] then
          ModHousekeeper.create_local_mods_list()
        end

        ModHousekeeper.save_settings()
      end
    end
  end

  mod.menu.redraw()
end

-- Draw title bar
local function draw_title_bar()
  -- Gray background
  screen.level(4)
  screen.rect(0, 0, 128, 10)
  screen.fill()

  -- Title text centered
  screen.level(15)
  screen.move(64, 8)
  screen.text_center("modhousekeeper")
end

-- Draw mod list screen
local function draw_mod_list()
  draw_title_bar()

  -- Check if list is empty
  if #ModHousekeeper.flat_list == 0 then
    screen.level(8)
    screen.move(64, 35)
    screen.text_center("No mods found")
    screen.move(64, 45)
    screen.text_center("Check matron for errors")
    return
  end

  -- Calculate scroll bounds
  local start_idx = ModHousekeeper.scroll_offset + 1
  local end_idx = math.min(start_idx + ModHousekeeper.max_visible - 1, #ModHousekeeper.flat_list)

  -- Draw visible items
  local y = 18
  for i = start_idx, end_idx do
    local item = ModHousekeeper.flat_list[i]
    local is_selected = (i == ModHousekeeper.selected_index)

    if item.type == "settings" then
      screen.level(is_selected and 15 or 10)
      screen.move(2, y)
      screen.text("⚙ " .. item.name)
    elseif item.type == "category" then
      screen.level(is_selected and 15 or 10)
      screen.move(2, y)
      screen.text("# " .. item.name)
    else
      local mod_entry = item.data
      screen.level(is_selected and 15 or 8)

      -- Status indicator
      if mod_entry.has_update then
        screen.move(2, y)
        screen.text("U")  -- Update available
      elseif mod_entry.installed then
        screen.move(2, y)
        screen.text("*")  -- Installed
      else
        screen.move(2, y)
        screen.text("-")  -- Not installed
      end

      -- Mod name
      screen.move(12, y)
      screen.text(mod_entry.name)
    end

    y = y + 9
  end

  -- Draw message if present at bottom
  if ModHousekeeper.message ~= "" then
    screen.level(0)
    screen.rect(0, 53, 128, 11)
    screen.fill()
    screen.level(15)
    screen.move(64, 60)
    screen.text_center(ModHousekeeper.message)
  end
end

-- Word wrap text to fit within width
local function wrap_text(text, max_chars)
  local lines = {}
  local words = {}
  for word in text:gmatch("%S+") do
    table.insert(words, word)
  end

  local current_line = ""
  for _, word in ipairs(words) do
    local test_line = current_line == "" and word or (current_line .. " " .. word)
    if #test_line <= max_chars then
      current_line = test_line
    else
      if current_line ~= "" then
        table.insert(lines, current_line)
      end
      current_line = word
    end
  end
  if current_line ~= "" then
    table.insert(lines, current_line)
  end

  return lines
end

-- Calculate total height needed for menu content
local function calculate_menu_height(items)
  local line_height = 8
  local total_lines = 0

  -- Title + separator
  total_lines = total_lines + 3

  -- Count lines for each item
  for _, item in ipairs(items) do
    if item.type == "info" then
      local wrapped = wrap_text(item.text, 23)
      total_lines = total_lines + #wrapped
    elseif item.type == "action" then
      total_lines = total_lines + 1
    elseif item.type == "alt_repo" then
      total_lines = total_lines + 1
      if item.description then
        total_lines = total_lines + 1
      end
    end
    total_lines = total_lines + 0.25  -- spacing
  end

  return math.min(total_lines * line_height + 6, 52)
end

-- Draw action menu pop-up
local function draw_action_menu()
  local menu = ModHousekeeper.action_menu
  local mod_entry = menu.mod_entry

  -- Calculate required height
  local menu_height = calculate_menu_height(menu.items)
  local menu_y = 12  -- Start after title bar

  -- Draw box
  screen.level(0)
  screen.rect(8, menu_y, 112, menu_height)
  screen.fill()
  screen.level(15)
  screen.rect(8, menu_y, 112, menu_height)
  screen.stroke()

  -- Mod name at top
  screen.level(15)
  screen.move(64, menu_y + 6)
  screen.text_center(mod_entry.name)

  -- Draw separator
  screen.move(10, menu_y + 8)
  screen.line(118, menu_y + 8)
  screen.stroke()

  -- Calculate visible area for scrolling
  local content_start_y = menu_y + 14
  local content_height = menu_height - 16
  local y_offset = 0

  -- Build list of rendered lines with their metadata
  local rendered_lines = {}
  for i, item in ipairs(menu.items) do
    if item.type == "info" then
      local wrapped = wrap_text(item.text, 23)
      for _, line in ipairs(wrapped) do
        table.insert(rendered_lines, {
          text = line,
          level = 8,
          indent = 0,
          item_idx = i
        })
      end
    elseif item.type == "action" then
      table.insert(rendered_lines, {
        text = "> " .. item.text,
        level = 10,
        indent = 0,
        item_idx = i
      })
    elseif item.type == "alt_repo" then
      table.insert(rendered_lines, {
        text = "> " .. item.text,
        level = 10,
        indent = 0,
        item_idx = i
      })
      if item.description then
        table.insert(rendered_lines, {
          text = item.description,
          level = 8,
          indent = 4,
          item_idx = i
        })
      end
    end
  end

  -- Calculate scroll offset to keep selected item visible
  local selected_line = 1
  for i, line in ipairs(rendered_lines) do
    if line.item_idx == menu.selected then
      selected_line = i
      break
    end
  end

  local max_visible_lines = math.floor(content_height / 8)

  -- Initialize scroll offset if not set
  if not menu.scroll_offset then
    menu.scroll_offset = 0
  end

  -- Only scroll if selected item is outside visible area
  if selected_line < menu.scroll_offset + 1 then
    menu.scroll_offset = selected_line - 1
  elseif selected_line > menu.scroll_offset + max_visible_lines then
    menu.scroll_offset = selected_line - max_visible_lines
  end

  local scroll_offset = menu.scroll_offset

  -- Draw visible lines
  local y = content_start_y
  for i = scroll_offset + 1, math.min(#rendered_lines, scroll_offset + max_visible_lines) do
    local line = rendered_lines[i]
    local is_selected_item = (line.item_idx == menu.selected)

    screen.level(is_selected_item and 15 or line.level)
    screen.move(12 + line.indent, y)
    screen.text(line.text)
    y = y + 8
  end
end

-- Draw settings screen
local function draw_settings()
  draw_title_bar()

  local y = 20
  for i, setting in ipairs(ModHousekeeper.settings_list) do
    local is_selected = (i == ModHousekeeper.settings_selected)
    screen.level(is_selected and 15 or 8)

    -- Setting name
    screen.move(2, y)
    screen.text(setting.name)

    -- Setting value
    local value_text = ModHousekeeper.settings[setting.id] and "ON" or "OFF"
    screen.move(126, y)
    screen.text_right(value_text)

    y = y + 12
  end

  -- Help text at bottom
  screen.level(4)
  screen.move(64, 60)
  screen.text_center("E2: select  E3: toggle")
end

menu_ui.redraw = function()
  screen.clear()

  -- Draw base screen
  if ModHousekeeper.current_screen == "mod_list" then
    draw_mod_list()
  elseif ModHousekeeper.current_screen == "settings" then
    draw_settings()
  end

  -- Draw overlays
  if ModHousekeeper.action_menu then
    draw_action_menu()
  elseif ModHousekeeper.confirm_dialog then
    local dialog = ModHousekeeper.confirm_dialog
    local action_text = dialog.action:upper()

    -- Semi-transparent overlay
    screen.level(0)
    screen.rect(20, 20, 88, 30)
    screen.fill()
    screen.level(15)
    screen.rect(20, 20, 88, 30)
    screen.stroke()

    screen.level(15)
    screen.move(64, 28)
    screen.text_center(action_text .. " MOD?")

    screen.move(64, 36)
    screen.level(10)
    screen.text_center(dialog.mod_entry.name)

    screen.level(15)
    screen.move(64, 46)
    screen.text_center("K2: No    K3: Yes")
  end

  screen.update()
end

-- Initialize the mod
ModHousekeeper.init()

-- Register menu UI
mod.menu.register(mod.this_name, menu_ui)

-- Register hooks
mod.hook.register("system_post_startup", "modhousekeeper_system_post_startup", ModHousekeeper.system_post_startup)

debug("mod loaded")
