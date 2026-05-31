-- json.lua
-- Minimal decode-only JSON parser for modhousekeeper.
-- Only decoding is needed (to read norns.community's community.json).
-- Handles objects, arrays, strings (with escapes), numbers, true/false/null.

local json = {}

local function skip_ws(s, i)
  local _, j = s:find("^[ \t\r\n]*", i)
  return (j or i - 1) + 1
end

local decode_value  -- forward declaration

local escapes = {
  ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
  b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}

local function decode_string(s, i)
  -- assumes s:sub(i,i) == '"'
  i = i + 1
  local buf = {}
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then
      return table.concat(buf), i + 1
    elseif c == '\\' then
      local e = s:sub(i + 1, i + 1)
      if e == 'u' then
        local hex = s:sub(i + 2, i + 5)
        local code = tonumber(hex, 16)
        if not code then
          error("json: bad \\u escape at " .. i)
        end
        -- Encode code point as UTF-8 (covers the BMP; good enough here)
        if code < 0x80 then
          buf[#buf + 1] = string.char(code)
        elseif code < 0x800 then
          buf[#buf + 1] = string.char(0xC0 + math.floor(code / 0x40),
                                      0x80 + (code % 0x40))
        else
          buf[#buf + 1] = string.char(0xE0 + math.floor(code / 0x1000),
                                      0x80 + (math.floor(code / 0x40) % 0x40),
                                      0x80 + (code % 0x40))
        end
        i = i + 6
      elseif escapes[e] then
        buf[#buf + 1] = escapes[e]
        i = i + 2
      else
        error("json: bad escape '\\" .. tostring(e) .. "' at " .. i)
      end
    else
      buf[#buf + 1] = c
      i = i + 1
    end
  end
  error("json: unterminated string")
end

local function decode_number(s, i)
  local num_str = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
  if not num_str or num_str == "" then
    error("json: invalid number at " .. i)
  end
  return tonumber(num_str), i + #num_str
end

local function decode_array(s, i)
  local arr = {}
  i = skip_ws(s, i + 1)
  if s:sub(i, i) == ']' then
    return arr, i + 1
  end
  while true do
    local val
    val, i = decode_value(s, i)
    arr[#arr + 1] = val
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == ',' then
      i = skip_ws(s, i + 1)
    elseif c == ']' then
      return arr, i + 1
    else
      error("json: expected ',' or ']' at " .. i)
    end
  end
end

local function decode_object(s, i)
  local obj = {}
  i = skip_ws(s, i + 1)
  if s:sub(i, i) == '}' then
    return obj, i + 1
  end
  while true do
    if s:sub(i, i) ~= '"' then
      error("json: expected key string at " .. i)
    end
    local key
    key, i = decode_string(s, i)
    i = skip_ws(s, i)
    if s:sub(i, i) ~= ':' then
      error("json: expected ':' at " .. i)
    end
    i = skip_ws(s, i + 1)
    local val
    val, i = decode_value(s, i)
    obj[key] = val
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == ',' then
      i = skip_ws(s, i + 1)
    elseif c == '}' then
      return obj, i + 1
    else
      error("json: expected ',' or '}' at " .. i)
    end
  end
end

decode_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '{' then
    return decode_object(s, i)
  elseif c == '[' then
    return decode_array(s, i)
  elseif c == '"' then
    return decode_string(s, i)
  elseif c == 't' then
    if s:sub(i, i + 3) == "true" then return true, i + 4 end
    error("json: invalid literal at " .. i)
  elseif c == 'f' then
    if s:sub(i, i + 4) == "false" then return false, i + 5 end
    error("json: invalid literal at " .. i)
  elseif c == 'n' then
    if s:sub(i, i + 3) == "null" then return nil, i + 4 end
    error("json: invalid literal at " .. i)
  else
    return decode_number(s, i)
  end
end

-- Decode a JSON string. Returns the decoded value, or nil + error message.
function json.decode(str)
  if type(str) ~= "string" then
    return nil, "json.decode: expected string"
  end
  local ok, result = pcall(function()
    local value, i = decode_value(str, 1)
    i = skip_ws(str, i)
    if i <= #str then
      error("json: trailing data at " .. i)
    end
    return value
  end)
  if ok then
    return result
  else
    return nil, tostring(result)
  end
end

-- Decode a JSON file by path. Returns decoded value, or nil + error message.
function json.decode_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil, "json: could not open " .. tostring(path)
  end
  local content = f:read("*a")
  f:close()
  return json.decode(content)
end

return json
