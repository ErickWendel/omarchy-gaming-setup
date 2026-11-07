-- Managed by omarchy-gaming-setup (components/hypr); local edits are replaced
-- on the next install.

-- Make the DisplayPort monitor the main one. Hyprland lays monitors out in the
-- order the GPU reports them, so the HDMI monitor came first: it sat on the
-- left, took focus at login, and Steam opened on it. Put the DisplayPort
-- monitor at 0x0 with focus and line the others up to its right, each keeping
-- the mode and scale Hyprland gave it. Nothing names a connector or a size, so
-- this follows whatever is plugged in.

local function is_displayport(monitor)
  return monitor.name:match("^DP%-") ~= nil
end

local function logical_width(monitor)
  local width = monitor.transform % 2 == 1 and monitor.height or monitor.width
  return math.floor(width / monitor.scale + 0.5)
end

local function connected()
  local monitors = {}
  for _, monitor in ipairs(hl.get_monitors()) do
    if not monitor.is_mirror then
      monitors[#monitors + 1] = monitor
    end
  end
  return monitors
end

-- The main monitor first: DisplayPort before anything else, then the larger
-- one, then by connector name so the order never changes between boots.
local function ordered(monitors)
  table.sort(monitors, function(left, right)
    if is_displayport(left) ~= is_displayport(right) then
      return is_displayport(left)
    end
    local left_area, right_area = left.width * left.height, right.width * right.height
    if left_area ~= right_area then
      return left_area > right_area
    end
    return left.name < right.name
  end)
  return monitors
end

local function arrange()
  local monitors = ordered(connected())
  local x = 0
  for _, monitor in ipairs(monitors) do
    if monitor.x ~= x or monitor.y ~= 0 then
      hl.monitor({
        output = monitor.name,
        mode = string.format("%dx%d@%.2f", monitor.width, monitor.height, monitor.refresh_rate),
        position = x .. "x0",
        scale = monitor.scale,
        transform = monitor.transform,
      })
    end
    x = x + logical_width(monitor)
  end
  return monitors[1]
end

-- Monitors are not there yet when Hyprland first reads the config; each one
-- that turns up rearranges them all.
arrange()

hl.on("monitor.added", function()
  arrange()
end)

hl.on("monitor.removed", function()
  hl.timer(arrange, { type = "oneshot", timeout = 1 })
end)

hl.on("hyprland.start", function()
  local main = arrange()
  if main then
    hl.dispatch(hl.dsp.focus({ monitor = main.name }))
  end
end)
