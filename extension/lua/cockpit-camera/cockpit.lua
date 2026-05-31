-- ============================================================================
-- Cockpit Camera - NeckFX Ultra-Realistic Driver Head Movement
-- ============================================================================
-- Simulates realistic driver head behavior based on:
--   * Longitudinal G-forces (acceleration/braking)
--   * Lateral G-forces (cornering forces)
--   * Vertical suspension movement (bumps/kerbs)
--   * Natural look-ahead bias
--
-- Compatible with CSP 0.3.0-preview342+
-- Optimized for 144+ Hz displays
-- ============================================================================

local settings = {}
local camera_state = {
  head_position = vec3(0, 0, 0),
  head_velocity = vec3(0, 0, 0),
  last_accel = vec3(0, 0, 0),
  frame_delta = 0.016,
}

-- ============================================================================
-- Settings Loading
-- ============================================================================
local function load_settings()
  -- Default settings (fallback if ini not found)
  local defaults = {
    longitudinal_lag = 0.85,
    braking_response = 1.2,
    lateral_stiffness = 0.75,
    vertical_sensitivity = 1.0,
    smoothing = 0.12,
    look_ahead_bias = 0.15,
    longitudinal_g_scale = 1.0,
    lateral_g_scale = 1.0,
    max_vertical_displacement = 0.12,
    enabled = 1,
  }

  -- Try to load from settings.ini
  local config_path = "extension/lua/cockpit-camera/settings.ini"
  if io.fileExists(config_path) then
    local config = ac.INIConfig.load(config_path)
    for key, default_value in pairs(defaults) do
      local loaded = config:get("NeckFX", key)
      if loaded ~= nil then
        settings[key] = tonumber(loaded) or default_value
      else
        settings[key] = default_value
      end
    end
  else
    -- Use defaults if config not found
    settings = defaults
  end
end

-- ============================================================================
-- Physics Calculations
-- ============================================================================

local function get_car_acceleration()
  -- Get car acceleration from physics (m/s²)
  local physics = ac.getCarState(0)
  if not physics then return vec3(0, 0, 0) end
  
  -- Use velocity derivative to estimate acceleration
  local current_velocity = physics.velocity
  local accel = (current_velocity - camera_state.last_accel) / (camera_state.frame_delta + 0.0001)
  camera_state.last_accel = current_velocity
  
  return accel
end

local function get_suspension_movement()
  -- Calculate vertical movement from suspension compression
  -- Returns normalized value (-1 to +1) for vertical travel
  local physics = ac.getCarState(0)
  if not physics then return 0 end
  
  -- Use suspension position averaged across all wheels
  local suspension_sum = 0
  local wheel_count = 0
  
  for i = 1, 4 do
    local wheel_speed = physics.wheelAngularVelocity(i - 1)
    if wheel_speed then
      wheel_count = wheel_count + 1
    end
  end
  
  -- Simplified: use vertical acceleration component
  local physics_accel = get_car_acceleration()
  return physics_accel.y / 40  -- Normalize to suspension range
end

local function calculate_head_target()
  -- Calculate target head position based on car dynamics
  local physics = ac.getCarState(0)
  if not physics then return vec3(0, 0, 0) end
  
  local target = vec3(0, 0, 0)
  
  -- Longitudinal G-forces (acceleration/braking lag)
  local accel = get_car_acceleration()
  local long_force = accel.z * settings.longitudinal_g_scale  -- Forward/backward
  
  -- Braking creates stronger forward head movement
  if long_force < 0 then
    long_force = long_force * settings.braking_response
  end
  
  target.z = -long_force * settings.longitudinal_lag * 0.015  -- Z lag (back/forward)
  
  -- Lateral G-forces (cornering)
  local lateral_force = accel.x * settings.lateral_g_scale  -- Left/right
  local lateral_mag = math.abs(lateral_force) * (1 - settings.lateral_stiffness)
  target.x = math.clamp(lateral_force * 0.012 * (1 - settings.lateral_stiffness), -0.08, 0.08)
  
  -- Vertical suspension movement (bumps/kerbs)
  local susp_movement = get_suspension_movement()
  target.y = math.clamp(susp_movement * settings.vertical_sensitivity * settings.max_vertical_displacement, 
                        -settings.max_vertical_displacement, 
                        settings.max_vertical_displacement)
  
  -- Look-ahead bias (natural direction leading)
  -- Head turns slightly in direction of travel
  local velocity = physics.velocity
  if velocity:length() > 1 then
    local velocity_normalized = velocity:normalize()
    target.x = target.x + velocity_normalized.x * settings.look_ahead_bias * 0.02
  end
  
  return target
end

local function apply_smoothing(current, target)
  -- Smooth camera transition using exponential decay
  local smoothing_factor = math.exp(-settings.smoothing * 10)
  return current * smoothing_factor + target * (1 - smoothing_factor)
end

-- ============================================================================
-- Camera Update
-- ============================================================================

local function update_cockpit_camera(dt)
  if settings.enabled == 0 then return end
  
  camera_state.frame_delta = dt
  
  -- Calculate target head position
  local target_position = calculate_head_target()
  
  -- Apply smoothing to avoid jittery movement
  camera_state.head_position.x = apply_smoothing(camera_state.head_position.x, target_position.x)
  camera_state.head_position.y = apply_smoothing(camera_state.head_position.y, target_position.y)
  camera_state.head_position.z = apply_smoothing(camera_state.head_position.z, target_position.z)
  
  -- Clamp to max displacement
  local max_lateral = 0.08
  local max_vertical = settings.max_vertical_displacement
  local max_forward = 0.06
  
  camera_state.head_position.x = math.clamp(camera_state.head_position.x, -max_lateral, max_lateral)
  camera_state.head_position.y = math.clamp(camera_state.head_position.y, -max_vertical, max_vertical)
  camera_state.head_position.z = math.clamp(camera_state.head_position.z, -max_forward, max_forward)
end

-- ============================================================================
-- CSP Integration Callback
-- ============================================================================

function script.update(dt)
  -- Called each frame by CSP
  if settings.enabled == 1 then
    update_cockpit_camera(dt)
  end
end

function script.drawUI()
  -- Optional: Debug display
  -- Uncomment to see real-time head position values
  -- ui.text("Head Pos: " .. tostring(camera_state.head_position))
end

-- ============================================================================
-- Camera Modifier for Cockpit View
-- ============================================================================

function script.onCameraUpdate(camera)
  if settings.enabled == 0 then return end
  
  -- Only apply to cockpit camera
  if camera.cameraType ~= "cockpit" then return end
  
  -- Apply head movement offset to camera
  -- This modifies the view position relative to car center
  camera.position = camera.position + camera_state.head_position
end

-- ============================================================================
-- Initialization
-- ============================================================================

load_settings()

return {
  name = "Cockpit Camera - NeckFX",
  onUpdate = script.update,
  onDrawUI = script.drawUI,
  onCameraUpdate = script.onCameraUpdate,
}
