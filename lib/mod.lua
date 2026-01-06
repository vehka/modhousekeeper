-- modhousekeeper
-- v1.0.0 by vehka
-- Norns mod manager with install, update, and removal functionality

local mod = require 'core/mods'
local util = require 'util'
local tabutil = require 'tabutil'
local animation = include('modhousekeeper/lib/animation')

-- Debug mode - set to false to disable debug messages
local DEBUG = false

local function debug(msg)
  if DEBUG then
    print("modhousekeeper: " .. msg)
  end
end

local modhousekeeper = {
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
    {id = "update_modhousekeeper", name = "Update modhousekeeper", type = "trigger"},
    {id = "check_mod_updates", name = "Check for mod updates", type = "trigger"},
  },
  settings_selected = 1,

  -- Info popup state
  info_popup = nil,  -- {message="...", timer=...}

  -- UI state
  categories = {},
  all_mods = {},
  category_order = {},  -- Ordered list of category names
  flat_list = {},  -- Flattened list for display
  collapsed_categories = {},  -- {category_name = true/false}
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
function modhousekeeper.extract_repo_name(url)
  -- Handle URLs like https://github.com/user/reponame or git@github.com:user/reponame.git
  local repo = url:match("([^/]+)%.git$") or url:match("([^/]+)$")
  if repo then
    repo = repo:gsub("%.git$", "")  -- Remove .git suffix if present
  end
  return repo
end

-- Parse CSV line with support for quoted fields
local function parse_csv_line(csv_line)
  local fields = {}
  local current_field = ""
  local in_quotes = false
  local i = 1

  while i <= #csv_line do
    local char = csv_line:sub(i, i)

    if in_quotes then
      if char == '"' then
        -- Check if it's an escaped quote (doubled "")
        if csv_line:sub(i+1, i+1) == '"' then
          current_field = current_field .. '"'
          i = i + 1  -- Skip the second quote
        else
          -- End of quoted field
          in_quotes = false
        end
      else
        current_field = current_field .. char
      end
    else
      if char == '"' then
        -- Start of quoted field
        in_quotes = true
      elseif char == ',' then
        -- Field separator - save current field and trim whitespace
        table.insert(fields, (current_field:gsub("^%s*(.-)%s*$", "%1")))
        current_field = ""
      else
        current_field = current_field .. char
      end
    end

    i = i + 1
  end

  -- Add the last field
  table.insert(fields, (current_field:gsub("^%s*(.-)%s*$", "%1")))

  return fields
end

-- Parse mods.list file
function modhousekeeper.parse_mods_list()
  local path = modhousekeeper.get_active_mods_list_path()
  local f = io.open(path, "r")
  if not f then
    print("modhousekeeper: ERROR - could not open mods list at " .. path)
    return
  end

  local current_category = nil
  local categories = {}
  local category_order = {}
  local all_mods = {}
  local mod_count = 0

  for line in f:lines() do
    if line:match("%S") then
      local category = line:match("^#%s*(.+)")
      if category then
        current_category = category
        categories[current_category] = {}
        table.insert(category_order, current_category)
        debug("found category: " .. category)
      else
        local fields = parse_csv_line(line)
        debug("parsed line: " .. line)
        debug("  -> " .. #fields .. " fields: [" .. table.concat(fields, "] [") .. "]")

        if #fields >= 3 and current_category then
          local mod_entry = {
            name = fields[1],
            url = fields[2],
            description = fields[3],
            alt_repos = {},
            repo_id = modhousekeeper.extract_repo_name(fields[2]),
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
          debug("  -> added mod: " .. mod_entry.name)
        else
          debug("  -> SKIPPED (not enough fields or no category)")
        end
      end
    end
  end

  f:close()
  debug("parsed " .. mod_count .. " mods in " .. tabutil.count(categories) .. " categories")

  modhousekeeper.categories = categories
  modhousekeeper.category_order = category_order
  modhousekeeper.all_mods = all_mods
  modhousekeeper.build_flat_list()
end

-- Scan for installed mods not in mods.list
function modhousekeeper.scan_local_mods()
  local pattern = "*/lib/mod.lua"
  local matches = norns.system_glob(_path.code .. pattern)

  if not matches then
    debug("no mods found during scan")
    return
  end

  local local_mods = {}

  for _, path in ipairs(matches) do
    -- Extract mod name from path
    local mod_name = path:match(_path.code .. "([%w_%-]+)/lib/mod%.lua")

    if mod_name and mod_name ~= "modhousekeeper" then
      -- Check if this mod is in our mods.list
      local in_list = false
      for name, mod_entry in pairs(modhousekeeper.all_mods) do
        if mod_entry.repo_id == mod_name then
          in_list = true
          break
        end
      end

      -- If not in list, add to local mods
      if not in_list then
        table.insert(local_mods, {
          name = mod_name,
          repo_id = mod_name,
          description = "Local mod",
          url = "",
          alt_repos = {},
          category = "Local mods",
          installed = true,
          has_update = false,
          installed_url = nil
        })
      end
    end
  end

  -- Add local mods to categories if any found
  if #local_mods > 0 then
    modhousekeeper.categories["Local mods"] = local_mods
    for _, mod_entry in ipairs(local_mods) do
      modhousekeeper.all_mods[mod_entry.name] = mod_entry
    end
    debug("found " .. #local_mods .. " local mods")
  end
end

-- Build flattened list for display
function modhousekeeper.build_flat_list()
  local flat = {}

  -- Add settings entry at the top
  table.insert(flat, {type = "settings", name = "Settings"})

  -- Add Local mods category first (if it exists)
  if modhousekeeper.categories["Local mods"] then
    table.insert(flat, {type = "category", name = "Local mods"})
    if not modhousekeeper.collapsed_categories["Local mods"] then
      for _, mod_entry in ipairs(modhousekeeper.categories["Local mods"]) do
        table.insert(flat, {type = "mod", data = mod_entry})
      end
    end
  end

  -- Add other categories in the order they appear in mods.list
  for _, cat_name in ipairs(modhousekeeper.category_order) do
    local mods = modhousekeeper.categories[cat_name]
    if mods then
      table.insert(flat, {type = "category", name = cat_name})

      -- Only add mods if category is not collapsed
      if not modhousekeeper.collapsed_categories[cat_name] then
        for _, mod_entry in ipairs(mods) do
          table.insert(flat, {type = "mod", data = mod_entry})
        end
      end
    end
  end

  modhousekeeper.flat_list = flat
  debug("built flat list with " .. #flat .. " items")
end

-- Check installation status of all mods
function modhousekeeper.check_installation_status()
  for name, mod_entry in pairs(modhousekeeper.all_mods) do
    local mod_path = modhousekeeper.install_path .. mod_entry.repo_id
    mod_entry.installed = util.file_exists(mod_path .. "/lib/mod.lua")
  end
  modhousekeeper.build_flat_list()
end

-- Show info popup with auto-dismiss
function modhousekeeper.show_info_popup(message)
  modhousekeeper.info_popup = {message = message}
  mod.menu.redraw()

  -- Auto-dismiss after 3 seconds
  clock.run(function()
    clock.sleep(3)
    modhousekeeper.info_popup = nil
    mod.menu.redraw()
  end)
end

-- Update modhousekeeper itself
function modhousekeeper.update_self()
  modhousekeeper.show_message("Updating modhousekeeper...")

  norns.system_cmd("cd " .. _path.code .. "modhousekeeper && git pull 2>&1", function(output)
    if output:match("Already up to date") or output:match("Already up%-to%-date") then
      modhousekeeper.show_info_popup("modhousekeeper\nalready up to date")
    elseif output:match("Updating") or output:match("Fast%-forward") then
      modhousekeeper.show_info_popup("modhousekeeper\nupdated!\nRestart norns to\napply changes")
    else
      modhousekeeper.show_info_popup("Update failed\nCheck matron")
      print("modhousekeeper: update output:\n" .. output)
    end
  end)
end

-- Check for updates (simplified: just check if git repo can be pulled)
function modhousekeeper.check_updates(callback)
  local checked = 0
  local total = 0

  for name, mod_entry in pairs(modhousekeeper.all_mods) do
    if mod_entry.installed then
      total = total + 1
    end
  end

  if total == 0 then
    if callback then callback() end
    return
  end

  for name, mod_entry in pairs(modhousekeeper.all_mods) do
    if mod_entry.installed then
      local mod_path = modhousekeeper.install_path .. mod_entry.repo_id

      -- Check if updates are available
      norns.system_cmd("cd " .. mod_path .. " && git fetch 2>&1", function(output)
        norns.system_cmd("cd " .. mod_path .. " && git rev-list HEAD...@{u} --count 2>&1", function(count_output)
          local count = tonumber(count_output)
          mod_entry.has_update = count and count > 0

          checked = checked + 1
          if checked >= total then
            modhousekeeper.build_flat_list()
            if callback then callback() end
          end
        end)
      end)
    end
  end
end

-- Check for updates and show popup with results
function modhousekeeper.check_updates_with_popup()
  -- Count total installed mods
  local total = 0
  for name, mod_entry in pairs(modhousekeeper.all_mods) do
    if mod_entry.installed then
      total = total + 1
    end
  end

  if total == 0 then
    modhousekeeper.show_info_popup("No mods installed")
    return
  end

  -- Create a state table to track progress
  local check_state = {
    checked = 0,
    total = total,
    update_count = 0
  }

  -- Show initial popup
  modhousekeeper.info_popup = {message = "Checking 0/" .. total .. " mods"}
  mod.menu.redraw()

  -- Check each mod
  for name, mod_entry in pairs(modhousekeeper.all_mods) do
    if mod_entry.installed then
      local mod_path = modhousekeeper.install_path .. mod_entry.repo_id

      norns.system_cmd("cd " .. mod_path .. " && git fetch 2>&1", function(output)
        norns.system_cmd("cd " .. mod_path .. " && git rev-list HEAD...@{u} --count 2>&1", function(count_output)
          local count = tonumber(count_output)
          mod_entry.has_update = count and count > 0

          if mod_entry.has_update then
            check_state.update_count = check_state.update_count + 1
          end

          check_state.checked = check_state.checked + 1

          -- Update progress
          if check_state.checked < check_state.total then
            if modhousekeeper.info_popup then
              modhousekeeper.info_popup.message = "Checking " .. check_state.checked .. "/" .. check_state.total .. " mods"
              mod.menu.redraw()
            end
          else
            -- All done - show results
            modhousekeeper.build_flat_list()
            local msg
            if check_state.update_count == 0 then
              msg = "No updates found"
            elseif check_state.update_count == 1 then
              msg = "1 update found"
            else
              msg = check_state.update_count .. " updates found"
            end
            modhousekeeper.show_info_popup(msg)
          end
        end)
      end)
    end
  end
end

-- Parse GitHub URL to extract repo URL and branch name
-- Returns: repo_url, branch_name (branch_name is nil if no branch specified)
local function parse_github_url(url)
  -- Check for /tree/branch-name format
  local repo_url, branch = url:match("^(https?://[^/]+/[^/]+/[^/]+)/tree/(.+)$")
  if repo_url and branch then
    return repo_url, branch
  end

  -- Check for #branch-name format
  repo_url, branch = url:match("^(https?://.-)#(.+)$")
  if repo_url and branch then
    return repo_url, branch
  end

  -- No branch specified, return the URL as-is
  return url, nil
end

-- Install a mod
function modhousekeeper.install_mod(mod_entry, callback, install_url)
  local url = install_url or mod_entry.url
  local install_path = modhousekeeper.install_path .. mod_entry.repo_id

  -- Parse URL to check for branch specification
  local repo_url, branch = parse_github_url(url)

  modhousekeeper.show_message("Installing " .. mod_entry.name .. "...")

  local clone_cmd
  if branch then
    -- Clone specific branch
    clone_cmd = "git clone -b " .. branch .. " " .. repo_url .. " " .. install_path .. " 2>&1"
    debug("cloning " .. repo_url .. " branch " .. branch)
  else
    -- Clone default branch
    clone_cmd = "git clone " .. repo_url .. " " .. install_path .. " 2>&1"
  end

  norns.system_cmd(clone_cmd, function(output)
    if util.file_exists(install_path .. "/lib/mod.lua") then
      mod_entry.installed = true
      mod_entry.installed_url = url
      modhousekeeper.show_message(mod_entry.name .. " installed!")
      debug("installed " .. mod_entry.name .. " from " .. url)
    else
      modhousekeeper.show_message("Failed to install " .. mod_entry.name)
      print("modhousekeeper: install failed - " .. mod_entry.name .. "\n" .. output)
    end
    modhousekeeper.build_flat_list()
    if callback then callback() end
  end)
end

-- Update a mod
function modhousekeeper.update_mod(mod_entry, callback)
  local mod_path = modhousekeeper.install_path .. mod_entry.repo_id

  modhousekeeper.show_message("Updating " .. mod_entry.name .. "...")

  norns.system_cmd("cd " .. mod_path .. " && git pull 2>&1", function(output)
    mod_entry.has_update = false
    modhousekeeper.show_message(mod_entry.name .. " updated!")
    modhousekeeper.build_flat_list()
    if callback then callback() end
  end)
end

-- Remove a mod
function modhousekeeper.remove_mod(mod_entry, callback)
  local mod_path = modhousekeeper.install_path .. mod_entry.repo_id

  modhousekeeper.show_message("Removing " .. mod_entry.name .. "...")

  norns.system_cmd("rm -rf " .. mod_path .. " 2>&1", function(output)
    mod_entry.installed = false
    mod_entry.has_update = false
    modhousekeeper.show_message(mod_entry.name .. " removed!")
    modhousekeeper.build_flat_list()
    if callback then callback() end
  end)
end

-- Build action menu for a mod
function modhousekeeper.build_action_menu(mod_entry)
  local items = {}

  -- Add mod description as info item (full text, no truncation)
  table.insert(items, {type = "info", text = mod_entry.description})

  -- Add primary action
  if mod_entry.installed then
    -- If installed from alt repo, offer to reinstall from main
    local is_alt_installed = mod_entry.installed_url and mod_entry.installed_url ~= mod_entry.url

    if mod_entry.has_update then
      table.insert(items, {type = "action", text = "Update", action = "update", url = mod_entry.url})
    end

    -- Show appropriate remove text based on what's installed
    if is_alt_installed then
      table.insert(items, {type = "action", text = "Remove alt version", action = "remove"})
    else
      table.insert(items, {type = "action", text = "Remove", action = "remove"})
    end

    if is_alt_installed then
      table.insert(items, {
        type = "alt_repo",
        text = "Reinstall",
        description = "main version",
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
          text = "Reinstall",
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

  modhousekeeper.action_menu = {
    mod_entry = mod_entry,
    selected = 2,  -- Start on first action, not description
    items = items
  }
end

-- Show temporary message
function modhousekeeper.show_message(msg)
  modhousekeeper.message = msg
  if modhousekeeper.message_timer then
    clock.cancel(modhousekeeper.message_timer)
  end
  modhousekeeper.message_timer = clock.run(function()
    clock.sleep(2)
    modhousekeeper.message = ""
    mod.menu.redraw()
  end)
  mod.menu.redraw()
end

-- Save settings to file
function modhousekeeper.save_settings()
  local f = io.open(modhousekeeper.settings_path, "w")
  if not f then return end
  io.output(f)
  io.write("return {\n")
  for k, v in pairs(modhousekeeper.settings) do
    local vstr = type(v) == "string" and ("'" .. v .. "'") or tostring(v)
    io.write("  " .. k .. " = " .. vstr .. ",\n")
  end
  io.write("}\n")
  io.close(f)
  debug("settings saved")
end

-- Load settings from file
function modhousekeeper.load_settings()
  local f = io.open(modhousekeeper.settings_path, "r")
  if f then
    io.close(f)
    modhousekeeper.settings = dofile(modhousekeeper.settings_path)
    debug("settings loaded")
  end
end

-- Create local mods.list copy if it doesn't exist
function modhousekeeper.create_local_mods_list()
  local f = io.open(modhousekeeper.mods_list_local_path, "r")
  if f then
    io.close(f)
    return  -- Already exists
  end

  -- Copy from main mods.list
  local source = io.open(modhousekeeper.mods_list_path, "r")
  if not source then
    print("modhousekeeper: ERROR - could not open mods.list to copy")
    return
  end

  local dest = io.open(modhousekeeper.mods_list_local_path, "w")
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
function modhousekeeper.get_active_mods_list_path()
  if modhousekeeper.settings.use_local_mods_list then
    return modhousekeeper.mods_list_local_path
  else
    return modhousekeeper.mods_list_path
  end
end

-- Initialize mod
function modhousekeeper.init()
  local status, err = pcall(function()
    modhousekeeper.load_settings()
    modhousekeeper.parse_mods_list()
    modhousekeeper.check_installation_status()
    modhousekeeper.scan_local_mods()
    modhousekeeper.build_flat_list()
  end)

  if not status then
    print("modhousekeeper: ERROR during init: " .. tostring(err))
  else
    debug("init complete - " .. tabutil.count(modhousekeeper.all_mods) .. " mods, " .. #modhousekeeper.flat_list .. " items")
  end
end

-- Hook: system_post_startup
function modhousekeeper.system_post_startup()
  print("modhousekeeper: system started")
end

-- Menu UI object
local menu_ui = {
  animation_active = false,
}

menu_ui.init = function()
  modhousekeeper.check_installation_status()

  -- Start animation if not disabled
  if not modhousekeeper.settings.disable_animation then
    menu_ui.animation_active = true
    animation.start(
      function()
        -- On complete callback
        menu_ui.animation_active = false
        mod.menu.redraw()
      end,
      function()
        -- On redraw callback
        mod.menu.redraw()
      end
    )
  end
end

menu_ui.deinit = function()
  -- Stop animation if still running
  if menu_ui.animation_active then
    animation.stop()
    menu_ui.animation_active = false
  end
end

menu_ui.key = function(n, z)
  if z > 0 then  -- Key down
    -- Skip animation if active
    if menu_ui.animation_active then
      animation.stop()
      menu_ui.animation_active = false
      mod.menu.redraw()
      return
    end

    if modhousekeeper.action_menu then
      -- In action menu
      if n == 2 then
        -- K2: Close action menu
        modhousekeeper.action_menu = nil
        mod.menu.redraw()
      elseif n == 3 then
        -- K3: Execute selected action
        local menu = modhousekeeper.action_menu
        local item = menu.items[menu.selected]

        if item and (item.type == "action" or item.type == "alt_repo") then
          -- Show confirmation dialog
          modhousekeeper.confirm_dialog = {
            action = item.action,
            mod_entry = menu.mod_entry,
            url = item.url
          }
          modhousekeeper.action_menu = nil
          mod.menu.redraw()
        end
      end
    elseif modhousekeeper.confirm_dialog then
      -- In confirmation dialog
      if n == 2 then
        -- K2: Cancel
        modhousekeeper.confirm_dialog = nil
        mod.menu.redraw()
      elseif n == 3 then
        -- K3: Confirm action
        local dialog = modhousekeeper.confirm_dialog
        modhousekeeper.confirm_dialog = nil

        if dialog.action == "install" or dialog.action == "reinstall" then
          -- For reinstall, first remove then install
          if dialog.action == "reinstall" then
            local mod_path = modhousekeeper.install_path .. dialog.mod_entry.repo_id
            norns.system_cmd("rm -rf " .. mod_path .. " 2>&1", function()
              dialog.mod_entry.installed = false
              modhousekeeper.install_mod(dialog.mod_entry, function()
                mod.menu.redraw()
              end, dialog.url)
            end)
          else
            modhousekeeper.install_mod(dialog.mod_entry, function()
              mod.menu.redraw()
            end, dialog.url)
          end
        elseif dialog.action == "update" then
          modhousekeeper.update_mod(dialog.mod_entry, function()
            mod.menu.redraw()
          end)
        elseif dialog.action == "remove" then
          modhousekeeper.remove_mod(dialog.mod_entry, function()
            mod.menu.redraw()
          end)
        end
      end
    elseif modhousekeeper.current_screen == "settings" then
      -- Settings screen
      if n == 2 then
        -- K2: Return to mod list
        modhousekeeper.current_screen = "mod_list"
        mod.menu.redraw()
      elseif n == 3 then
        -- K3: Execute trigger action
        local setting = modhousekeeper.settings_list[modhousekeeper.settings_selected]
        if setting.type == "trigger" then
          if setting.id == "update_modhousekeeper" then
            modhousekeeper.update_self()
          elseif setting.id == "check_mod_updates" then
            modhousekeeper.check_updates_with_popup()
          end
        end
      end
    else
      -- Mod list screen
      if n == 2 then
        -- K2: Return to mod selection menu
        mod.menu.exit()
      elseif n == 3 then
        -- K3: Action on selected item
        local item = modhousekeeper.flat_list[modhousekeeper.selected_index]

        if item and item.type == "settings" then
          -- Enter settings mode
          modhousekeeper.current_screen = "settings"
          mod.menu.redraw()
        elseif item and item.type == "category" then
          -- Toggle category collapse
          modhousekeeper.collapsed_categories[item.name] = not modhousekeeper.collapsed_categories[item.name]
          modhousekeeper.build_flat_list()
          mod.menu.redraw()
        elseif item and item.type == "mod" then
          -- Open action menu
          modhousekeeper.build_action_menu(item.data)
          mod.menu.redraw()
        end
      end
    end
  end
end

menu_ui.enc = function(n, delta)
  if modhousekeeper.confirm_dialog then
    return  -- Ignore encoder input during confirmation dialog
  end

  if modhousekeeper.action_menu then
    -- Action menu navigation
    if n == 2 then
      local menu = modhousekeeper.action_menu
      menu.selected = util.clamp(menu.selected + delta, 1, #menu.items)
    end
  elseif modhousekeeper.current_screen == "mod_list" then
    -- Mod list screen encoders
    if #modhousekeeper.flat_list == 0 then
      return  -- Guard against empty list
    end

    if n == 2 then
      -- E2: Scroll through list
      modhousekeeper.selected_index = util.clamp(
        modhousekeeper.selected_index + delta,
        1,
        #modhousekeeper.flat_list
      )

      -- Adjust scroll offset
      if modhousekeeper.selected_index < modhousekeeper.scroll_offset + 1 then
        modhousekeeper.scroll_offset = modhousekeeper.selected_index - 1
      elseif modhousekeeper.selected_index > modhousekeeper.scroll_offset + modhousekeeper.max_visible then
        modhousekeeper.scroll_offset = modhousekeeper.selected_index - modhousekeeper.max_visible
      end
    elseif n == 3 then
      -- E3: Show confirmation dialog for action
      local item = modhousekeeper.flat_list[modhousekeeper.selected_index]
      if item and item.type == "mod" then
        local mod_entry = item.data

        if delta > 0 then
          -- Install or update
          if mod_entry.installed then
            if mod_entry.has_update then
              modhousekeeper.confirm_dialog = {action = "update", mod_entry = mod_entry}
            else
              modhousekeeper.show_message(mod_entry.name .. " is up to date")
            end
          else
            modhousekeeper.confirm_dialog = {action = "install", mod_entry = mod_entry}
          end
        else
          -- Remove
          if mod_entry.installed then
            modhousekeeper.confirm_dialog = {action = "remove", mod_entry = mod_entry}
          else
            modhousekeeper.show_message(mod_entry.name .. " not installed")
          end
        end
      end
    end

  elseif modhousekeeper.current_screen == "settings" then
    -- Settings screen encoders
    if n == 2 then
      -- E2: Navigate settings
      modhousekeeper.settings_selected = util.clamp(
        modhousekeeper.settings_selected + delta,
        1,
        #modhousekeeper.settings_list
      )
    elseif n == 3 then
      -- E3: Toggle or trigger setting
      local setting = modhousekeeper.settings_list[modhousekeeper.settings_selected]
      if setting.type == "toggle" then
        modhousekeeper.settings[setting.id] = not modhousekeeper.settings[setting.id]

        -- Handle special actions for certain settings
        if setting.id == "use_local_mods_list" then
          if modhousekeeper.settings[setting.id] then
            modhousekeeper.create_local_mods_list()
          end
          -- Reload mods list from the newly selected source
          modhousekeeper.parse_mods_list()
          modhousekeeper.check_installation_status()
          modhousekeeper.build_flat_list()
          modhousekeeper.show_message("Mods list reloaded")
        end

        modhousekeeper.save_settings()
      elseif setting.type == "trigger" then
        -- Execute trigger action
        if setting.id == "update_modhousekeeper" then
          modhousekeeper.update_self()
        elseif setting.id == "check_mod_updates" then
          modhousekeeper.check_updates_with_popup()
        end
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
  screen.text_center("MODHOUSEKEEPER")
end

-- Draw mod list screen
local function draw_mod_list()
  draw_title_bar()

  -- Check if list is empty
  if #modhousekeeper.flat_list == 0 then
    screen.level(8)
    screen.move(64, 35)
    screen.text_center("No mods found")
    screen.move(64, 45)
    screen.text_center("Check matron for errors")
    return
  end

  -- Calculate scroll bounds
  local start_idx = modhousekeeper.scroll_offset + 1
  local end_idx = math.min(start_idx + modhousekeeper.max_visible - 1, #modhousekeeper.flat_list)

  -- Draw visible items
  local y = 18
  for i = start_idx, end_idx do
    local item = modhousekeeper.flat_list[i]
    local is_selected = (i == modhousekeeper.selected_index)

    if item.type == "settings" then
      screen.level(is_selected and 15 or 10)
      screen.move(2, y)
      screen.text("▦ " .. item.name)
    elseif item.type == "category" then
      screen.level(is_selected and 15 or 10)
      screen.move(2, y)
      local collapsed = modhousekeeper.collapsed_categories[item.name]
      local indicator = collapsed and "+" or "-"
      screen.text(indicator .. " " .. item.name)
    else
      local mod_entry = item.data
      screen.level(is_selected and 15 or 8)

      -- Status indicator
      if mod_entry.has_update then
        screen.move(2, y)
        screen.text("◆")  -- Update available
      elseif mod_entry.installed then
        screen.move(2, y)
        screen.text("◉")  -- Installed
      else
        screen.move(2, y)
        screen.text("○")  -- Not installed
      end

      -- Mod name
      screen.move(12, y)
      screen.text(mod_entry.name)
    end

    y = y + 9
  end

  -- Draw message if present at bottom
  if modhousekeeper.message ~= "" then
    screen.level(0)
    screen.rect(0, 53, 128, 11)
    screen.fill()
    screen.level(15)
    screen.move(64, 60)
    screen.text_center(modhousekeeper.message)
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
  local menu = modhousekeeper.action_menu
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
  -- Find the last line of the selected item to ensure all lines are visible
  local selected_line = 1
  for i, line in ipairs(rendered_lines) do
    if line.item_idx == menu.selected then
      selected_line = i
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
  for i, setting in ipairs(modhousekeeper.settings_list) do
    local is_selected = (i == modhousekeeper.settings_selected)
    screen.level(is_selected and 15 or 8)

    -- Setting name
    screen.move(2, y)
    screen.text(setting.name)

    -- Setting value/indicator
    if setting.type == "toggle" then
      local value_text = modhousekeeper.settings[setting.id] and "ON" or "OFF"
      screen.move(126, y)
      screen.text_right(value_text)
    elseif setting.type == "trigger" then
      screen.move(126, y)
      screen.text_right(">")
    end

    y = y + 12
  end

  -- Draw message if present at bottom
  if modhousekeeper.message ~= "" then
    screen.level(0)
    screen.rect(0, 53, 128, 11)
    screen.fill()
    screen.level(15)
    screen.move(64, 60)
    screen.text_center(modhousekeeper.message)
  end
end

menu_ui.redraw = function()
  screen.clear()

  -- Draw animation if active
  if menu_ui.animation_active then
    animation.draw()
    return
  end

  -- Draw base screen
  if modhousekeeper.current_screen == "mod_list" then
    draw_mod_list()
  elseif modhousekeeper.current_screen == "settings" then
    draw_settings()
  end

  -- Draw overlays
  if modhousekeeper.action_menu then
    draw_action_menu()
  elseif modhousekeeper.confirm_dialog then
    local dialog = modhousekeeper.confirm_dialog
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
  elseif modhousekeeper.info_popup then
    -- Info popup
    local lines = {}
    for line in modhousekeeper.info_popup.message:gmatch("[^\n]+") do
      table.insert(lines, line)
    end

    local height = #lines * 10 + 10
    local y_start = 32 - (height / 2)

    screen.level(0)
    screen.rect(16, y_start, 96, height)
    screen.fill()
    screen.level(15)
    screen.rect(16, y_start, 96, height)
    screen.stroke()

    local y = y_start + 8
    for _, line in ipairs(lines) do
      screen.level(15)
      screen.move(64, y)
      screen.text_center(line)
      y = y + 10
    end
  end

  screen.update()
end

-- Initialize the mod
modhousekeeper.init()

-- Register menu UI
mod.menu.register(mod.this_name, menu_ui)

-- Register hooks
mod.hook.register("system_post_startup", "modhousekeeper_system_post_startup", modhousekeeper.system_post_startup)

debug("mod loaded")
