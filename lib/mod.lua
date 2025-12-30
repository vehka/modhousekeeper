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
  install_path = _path.code,

  -- UI state
  categories = {},
  all_mods = {},
  flat_list = {},  -- Flattened list for display
  selected_index = 1,
  scroll_offset = 0,
  max_visible = 6,

  -- Confirmation dialog state
  confirm_dialog = nil,  -- {action="install/update/remove", mod_entry=...}

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
  local f = io.open(ModHousekeeper.mods_list_path, "r")
  if not f then
    print("modhousekeeper: ERROR - could not open mods.list")
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
            alt_urls = {},
            repo_id = ModHousekeeper.extract_repo_name(fields[2]),
            category = current_category,
            installed = false,
            has_update = false,
          }

          -- Collect alternative URLs (fields 4+)
          for i = 4, #fields do
            table.insert(mod_entry.alt_urls, fields[i])
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
function ModHousekeeper.install_mod(mod_entry, callback)
  local install_path = ModHousekeeper.install_path .. mod_entry.repo_id
  ModHousekeeper.show_message("Installing " .. mod_entry.name .. "...")

  norns.system_cmd("git clone " .. mod_entry.url .. " " .. install_path .. " 2>&1", function(output)
    if util.file_exists(install_path .. "/lib/mod.lua") then
      mod_entry.installed = true
      ModHousekeeper.show_message(mod_entry.name .. " installed!")
      debug("installed " .. mod_entry.name)
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

-- Initialize mod
function ModHousekeeper.init()
  local status, err = pcall(function()
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
    if ModHousekeeper.confirm_dialog then
      -- In confirmation dialog
      if n == 2 then
        -- K2: Cancel
        ModHousekeeper.confirm_dialog = nil
        mod.menu.redraw()
      elseif n == 3 then
        -- K3: Confirm action
        local dialog = ModHousekeeper.confirm_dialog
        ModHousekeeper.confirm_dialog = nil

        if dialog.action == "install" then
          ModHousekeeper.install_mod(dialog.mod_entry, function()
            mod.menu.redraw()
          end)
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
    else
      -- Normal mode
      if n == 2 then
        -- K2: Return to mod selection menu
        mod.menu.exit()
      elseif n == 3 then
        -- K3: Quick action on selected mod
        local item = ModHousekeeper.flat_list[ModHousekeeper.selected_index]
        if item and item.type == "mod" then
          local mod_entry = item.data

          if mod_entry.installed then
            if mod_entry.has_update then
              ModHousekeeper.confirm_dialog = {action = "update", mod_entry = mod_entry}
              mod.menu.redraw()
            else
              ModHousekeeper.show_message(mod_entry.name .. " is up to date")
              mod.menu.redraw()
            end
          else
            ModHousekeeper.confirm_dialog = {action = "install", mod_entry = mod_entry}
            mod.menu.redraw()
          end
        end
      end
    end
  end
end

menu_ui.enc = function(n, delta)
  if ModHousekeeper.confirm_dialog then
    return  -- Ignore encoder input during confirmation dialog
  end

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
  mod.menu.redraw()
end

menu_ui.redraw = function()
  screen.clear()

  -- Check if confirmation dialog is active
  if ModHousekeeper.confirm_dialog then
    local dialog = ModHousekeeper.confirm_dialog
    local action_text = dialog.action:upper()

    screen.level(15)
    screen.move(64, 20)
    screen.text_center(action_text .. " MOD?")

    screen.move(64, 32)
    screen.level(10)
    screen.text_center(dialog.mod_entry.name)

    screen.level(15)
    screen.move(64, 50)
    screen.text_center("K2: No    K3: Yes")
  else
    -- Normal UI
    screen.level(15)
    screen.move(0, 8)
    screen.text("ModHousekeeper")
    screen.move(128, 8)
    screen.text_right("K2:exit K3:act")

    -- Draw separator line
    screen.move(0, 10)
    screen.line(128, 10)
    screen.stroke()

    -- Check if list is empty
    if #ModHousekeeper.flat_list == 0 then
      screen.level(8)
      screen.move(64, 35)
      screen.text_center("No mods found")
      screen.move(64, 45)
      screen.text_center("Check matron for errors")
      screen.update()
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

      if item.type == "category" then
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

    -- Draw description for selected mod at bottom
    local selected_item = ModHousekeeper.flat_list[ModHousekeeper.selected_index]
    if selected_item and selected_item.type == "mod" and selected_item.data.description then
      local desc = selected_item.data.description
      -- Truncate if too long
      if #desc > 40 then
        desc = desc:sub(1, 37) .. "..."
      end

      screen.level(0)
      screen.rect(0, 53, 128, 11)
      screen.fill()
      screen.level(8)
      screen.move(2, 60)
      screen.text(desc)
    end

    -- Draw message if present (overlays description)
    if ModHousekeeper.message ~= "" then
      screen.level(0)
      screen.rect(0, 53, 128, 11)
      screen.fill()
      screen.level(15)
      screen.move(64, 60)
      screen.text_center(ModHousekeeper.message)
    end
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
