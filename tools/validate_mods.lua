#!/usr/bin/env lua
-- validate_mods.lua
-- Maintenance utility (NOT loaded by the mod): checks every entry in mods.lua
-- against GitHub to catch stale data -- a repo that no longer exists, or a repo
-- that isn't actually a mod (no lib/mod.lua, e.g. a plain Lua library).
--
-- For each entry (and its alts), it resolves the repo + branch from the URL and
-- asks GitHub whether lib/mod.lua exists on that branch.
--   - prefers the `gh` CLI (uses your auth -> high rate limit)
--   - falls back to plain curl against api.github.com (unauthenticated ~60/hr)
--
-- Usage:  lua tools/validate_mods.lua [path/to/mods.lua]
-- Exit 0 if all OK, 1 if any problems were found.

local mods_path = arg[1] or "mods.lua"

-- Resolve repo (owner/name) and branch from a mod URL. Mirrors parse_github_url
-- in lib/mod.lua: supports .../tree/<branch> and ...#<branch>.
local function parse_url(url)
  local branch
  local base = url

  local b = base:match("/tree/(.+)$")
  if b then
    branch = b
    base = base:gsub("/tree/.+$", "")
  else
    b = base:match("#(.+)$")
    if b then
      branch = b
      base = base:gsub("#.+$", "")
    end
  end

  base = base:gsub("%.git$", ""):gsub("/+$", "")
  local owner, name = base:match("github%.com[:/]([^/]+)/([^/]+)$")
  return owner, name, branch
end

-- Detect the gh CLI once.
local have_gh = (function()
  local f = io.popen("command -v gh 2>/dev/null")
  if not f then return false end
  local out = f:read("*a")
  f:close()
  return out ~= nil and out:gsub("%s", "") ~= ""
end)()

-- Returns true if lib/mod.lua exists in owner/name (optionally on `branch`),
-- plus a short status string for reporting.
local function check_mod(owner, name, branch)
  if not owner or not name then
    return false, "unparseable url"
  end

  local path = "repos/" .. owner .. "/" .. name .. "/contents/lib/mod.lua"
  if branch then
    path = path .. "?ref=" .. branch
  end

  if have_gh then
    -- gh exits 0 and prints the name on success; non-zero on 404.
    local cmd = "gh api " .. path .. " --jq .name 2>/dev/null"
    local f = io.popen(cmd)
    local out = f:read("*a") or ""
    local ok = f:close()
    if ok and out:match("mod%.lua") then
      return true, "OK"
    end
    -- Distinguish "repo missing" from "repo exists but no lib/mod.lua".
    local rf = io.popen("gh api repos/" .. owner .. "/" .. name .. " --jq .full_name 2>/dev/null")
    local rout = rf:read("*a") or ""
    rf:close()
    if rout:match("%S") then
      return false, "no lib/mod.lua (not a mod?)"
    end
    return false, "repo not found"
  else
    -- curl fallback against the REST API; -w writes the HTTP status.
    local url = "https://api.github.com/" .. path
    local cmd = "curl -s -o /dev/null -w '%{http_code}' " ..
                "-H 'Accept: application/vnd.github+json' '" .. url .. "'"
    local f = io.popen(cmd)
    local code = (f:read("*a") or ""):gsub("%s", "")
    f:close()
    if code == "200" then
      return true, "OK"
    elseif code == "404" then
      return false, "404 (repo or lib/mod.lua missing)"
    else
      return false, "HTTP " .. code
    end
  end
end

local ok, mods = pcall(dofile, mods_path)
if not ok or type(mods) ~= "table" or type(mods.mods) ~= "table" then
  io.stderr:write("could not load " .. mods_path .. ": " .. tostring(mods) .. "\n")
  os.exit(2)
end

print((have_gh and "using gh CLI" or "using curl (unauthenticated)") ..
      " -- validating " .. #mods.mods .. " mods in " .. mods_path .. "\n")

local problems = {}

local function report(label, url, ok_, status)
  local mark = ok_ and "  ok " or "FAIL "
  print(string.format("%s %-22s %s  [%s]", mark, label, url, status))
  if not ok_ then
    table.insert(problems, label .. " -> " .. url .. " (" .. status .. ")")
  end
end

for _, m in ipairs(mods.mods) do
  local owner, name, branch = parse_url(m.url)
  local ok_, status = check_mod(owner, name, branch)
  report(m.name, m.url, ok_, status)

  if m.alts then
    for _, a in ipairs(m.alts) do
      local ao, an, ab = parse_url(a.url)
      local aok, astatus = check_mod(ao, an, ab)
      report("  alt: " .. (a.description or ""), a.url, aok, astatus)
    end
  end
end

print()
if #problems == 0 then
  print("All entries valid.")
  os.exit(0)
else
  print(#problems .. " problem(s):")
  for _, p in ipairs(problems) do
    print("  - " .. p)
  end
  os.exit(1)
end
