-- catalog.lua
-- Loads norns.community's community.json and indexes it by repository URL, so
-- modhousekeeper can resolve canonical install directories (the project_name a
-- mod actually installs into, which may differ from its URL basename) and enrich
-- descriptions. The curated mods.lua remains the source of truth for which
-- projects are mods; this only augments them.

local json = include('modhousekeeper/lib/json')

local catalog = {
  entries = nil,   -- raw array of catalog entries
  by_url = {},     -- normalized url -> entry
  loaded = false,
}

-- Where we look for the catalog, in priority order:
--   1. a fresh copy the user fetched via "Refresh catalog" (in _path.data)
--   2. the copy bundled with the mod
local function refreshed_path()
  return _path.data .. "modhousekeeper_community.json"
end
local function bundled_path()
  return _path.code .. "modhousekeeper/community.json"
end

local function normalize_url(u)
  if not u then return nil end
  return u:lower():gsub("%.git$", ""):gsub("/+$", "")
end
catalog.normalize_url = normalize_url

-- Load and index the catalog. Tries the refreshed copy first, falling back to
-- the bundled copy if it is missing or fails to parse. Returns true on success.
function catalog.load()
  catalog.by_url = {}
  catalog.entries = nil
  catalog.loaded = false

  local paths = {}
  local rp = refreshed_path()
  local rf = io.open(rp, "r")
  if rf then
    rf:close()
    paths[#paths + 1] = rp
  end
  paths[#paths + 1] = bundled_path()

  for _, path in ipairs(paths) do
    local data, err = json.decode_file(path)
    if data and data.entries then
      catalog.entries = data.entries
      for _, e in ipairs(data.entries) do
        local nu = normalize_url(e.project_url)
        if nu then
          catalog.by_url[nu] = e
        end
      end
      catalog.loaded = true
      return true
    else
      print("modhousekeeper: catalog parse failed for " .. path .. " (" .. tostring(err) .. ")")
    end
  end

  return false
end

-- Look up a catalog entry by repository URL (nil if not present).
function catalog.lookup(url)
  return catalog.by_url[normalize_url(url)]
end

-- Fetch the latest community.json into the refreshed path (async), validate it,
-- and reload. callback(ok, message).
function catalog.refresh(callback)
  local url = "https://raw.githubusercontent.com/monome/norns-community/main/community.json"
  local dest = refreshed_path()
  -- Download to a temp file, validate, then move into place so a failed/partial
  -- download never clobbers a working catalog.
  local tmp = dest .. ".tmp"
  local cmd = "curl -sL --fail " .. url .. " -o " .. tmp .. " 2>&1"

  norns.system_cmd(cmd, function(output)
    local data = json.decode_file(tmp)
    if data and data.entries then
      os.rename(tmp, dest)
      catalog.load()
      if callback then
        callback(true, "Catalog refreshed\n" .. #data.entries .. " entries")
      end
    else
      os.remove(tmp)
      print("modhousekeeper: catalog refresh failed:\n" .. tostring(output))
      if callback then
        callback(false, "Refresh failed\nCheck matron")
      end
    end
  end)
end

return catalog
