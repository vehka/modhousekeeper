-- animation.lua
-- Lighthouse starting animation for modhousekeeper

-- Debug mode - set to false to disable debug messages
local DEBUG = false

local function debug(msg)
  if DEBUG then
    print("modhousekeeper: " .. msg)
  end
end

local Animation = {
  b = 128,
  t = 0,
  o = 64,
  fps = 60,
  state = "running",
  clock_id = nil,
}

-- Helper functions to mimic p8 drawing API
local function cls(color)
  screen.clear()
  if color and color > 0 then
    screen.level(color)
    screen.rect(0, 0, 128, 64)
    screen.fill()
  end
end

local function circfill(x, y, r, color)
  screen.level(color or 15)
  screen.circle(x, y, r)
  screen.fill()
end

local function rectfill(x1, y1, x2, y2, color)
  screen.level(color or 15)
  local w = x2 - x1
  local h = y2 - y1
  screen.rect(x1, y1, w, h)
  screen.fill()
end

local function line(x1, y1, x2, y2, color)
  screen.level(color or 15)
  screen.move(x1, y1)
  screen.line(x2, y2)
  screen.stroke()
end

-- Reset animation state
function Animation.reset()
  Animation.t = 0
  Animation.state = "running"
end

-- Start the animation
function Animation.start(on_complete, on_redraw)
  Animation.reset()
  Animation.on_complete = on_complete
  Animation.on_redraw = on_redraw
  debug("animation started")

  -- Start animation clock
  Animation.clock_id = clock.run(function()
    local step_s = 1 / Animation.fps
    while Animation.state ~= "done" do
      clock.sleep(step_s)
      Animation.update()

      -- Trigger redraw callback
      if Animation.on_redraw then
        Animation.on_redraw()
      end
    end

    -- Animation completed
    debug("animation completed")
    if Animation.on_complete then
      Animation.on_complete()
    end
  end)
end

-- Stop the animation
function Animation.stop()
  debug("animation stopped/skipped")
  if Animation.clock_id then
    clock.cancel(Animation.clock_id)
    Animation.clock_id = nil
  end
  Animation.state = "done"

  -- Call completion callback
  if Animation.on_complete then
    Animation.on_complete()
  end
end

-- Update animation state
function Animation.update()
  if Animation.state == "running" then
    Animation.t = Animation.t + 0.02

    -- Debug: print every 30 frames (~0.5 seconds)
    if math.floor(Animation.t * 50) % 30 == 0 then
      debug("animation t=" .. string.format("%.2f", Animation.t))
    end

    -- Check for transition to clearing state
    if Animation.t > 0.90 and Animation.t < 0.99 then
      debug("animation transitioning to clearing")
      Animation.state = "clearing"

      -- Schedule transition to text state
      clock.run(function()
        clock.sleep(1)
        debug("animation transitioning to text")
        Animation.state = "text"
      end)
    end
  elseif Animation.state == "text" then
    -- Schedule transition to done state
    clock.run(function()
      clock.sleep(2)
      Animation.state = "done"
    end)
    Animation.state = "text_showing" -- Prevent re-triggering
  end
end

-- Draw the animation
function Animation.draw()
  if Animation.state == "running" then
    Animation.draw_lighthouse()
  elseif Animation.state == "clearing" then
    cls(10)
  elseif Animation.state == "text" or Animation.state == "text_showing" then
    cls(10)
    screen.level(7)
    screen.move(64, 32)
    screen.text_center("MODHOUSEKEEPER")
  elseif Animation.state == "done" then
    cls(0)
  end

  screen.update()
end

-- Draw the lighthouse scene
function Animation.draw_lighthouse()
  local s = math.sin(Animation.t)
  local c = Animation.b * math.cos(Animation.t) + Animation.o

  cls(0)

  -- Lighthouse light (circle at top)
  circfill(Animation.o - 5, 23, 5, 8)

  -- Lighthouse tower (striped)
  local lighthouse_x_start = Animation.o - 10
  local lighthouse_width = 10
  local lighthouse_height = 10 * (Animation.b / 128)
  for i = 25, Animation.b * 0.5, 5 do
    local color = (i % 2 == 0) and 6 or 2
    rectfill(
      lighthouse_x_start,
      i * (Animation.b / 128),
      lighthouse_x_start + lighthouse_width,
      i * (Animation.b / 128) + lighthouse_height,
      color
    )
  end

  -- Terrace
  local terrace_y = 23 * (Animation.b / 128)
  local terrace_width = lighthouse_width * 1.5
  local terrace_x_start = Animation.o - 5 - (terrace_width / 2)
  rectfill(terrace_x_start, terrace_y, terrace_x_start + terrace_width, terrace_y + 4, 1)

  -- Light beam
  local vert_scale = 5
  for v = -s, s, 0.01 do
    local new_end_x = 2 * (Animation.o - 5) - c
    line(Animation.o - 5, Animation.o - 44, new_end_x, Animation.b * v * vert_scale + Animation.o - 42, 10)
  end
end

-- Check if animation is active
function Animation.is_active()
  return Animation.state ~= "done"
end

return Animation
