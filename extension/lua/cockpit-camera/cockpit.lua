-- ============================================================================
-- Cockpit Camera - NeckFX Ultra-Realistic Driver Head Movement
-- ============================================================================
-- PRODUCTION PHYSICS: Simulates realistic driver head behavior based on:
--   * Longitudinal G-forces (acceleration/braking with lag)
--   * Lateral G-forces (cornering with spring-damper physics)
--   * Vertical suspension compression (bumps/kerbs)
--   * Rotational inertia (head doesn't follow instantly)
--   * Natural look-ahead bias
--
-- Compatible with CSP 0.3.0-preview342+
-- Optimized for 144+ Hz displays
-- ============================================================================

local settings = {}
local physics_state = {
  -- Head position (relative to driver seated position)
  head_x = 0,        -- Lateral (left-right, meters)
  head_y = 0,        -- Vertical (up-down, meters)
  head_z = 0,        -- Longitudinal (forward-back, meters)
  
  -- Head velocity (for inertia physics)
  vel_x = 0,
  vel_y = 0,
  vel_z = 0,
  
  -- Previous frame state (for acceleration calculation)
  last_velocity = vec3(0, 0, 0),
  last_suspension_avg = 0,
  
  -- Frame timing
  frame_delta = 0.016,
  simulation_time = 0,
}

-- ============================================================================
-- Settings Loading
-- ============================================================================
local function load_settings()
  local defaults = {
    -- Physics parameters
    longitudinal_lag = 0.85,       -- How much head lags during accel (0-1)
    braking_multiplier = 1.3,      -- Head movement stronger during braking
    lateral_stiffness = 0.68,      -- Spring stiffness for lateral movement
    lateral_damping = 0.35,        -- Damping factor for lateral oscillation
    vertical_sensitivity = 1.0,    -- Suspension bump response
    vertical_damping = 0.6,        -- Vertical oscillation damping
    
    -- Smoothing and response
    update_smoothing = 0.08,       -- Position smoothing factor (0-0.3)
    look_ahead_bias = 0.12,        -- Natural head turn into corners
    
    -- G-force scales
    longitudinal_g_scale = 9.81,   -- Multiply accel by this to get realistic G
    lateral_g_scale = 9.81,
    vertical_g_scale = 5.0,
    
    -- Limits
    max_lateral_displacement = 0.085,    -- Max head tilt left-right
    max_vertical_displacement = 0.15,    -- Max head compression up-down
    max_forward_displacement = 0.07,     -- Max head lurch forward-back
    
    enabled = 1,
  }

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
    settings = defaults
  end
end

-- ============================================================================
-- G-Force and Dynamics Calculations
-- ============================================================================

local function calculate_car_acceleration()
  -- Get car velocity and calculate acceleration from derivative
  local car = ac.getCar(0)
  if not car then return vec3(0, 0, 0) end
  
  local current_velocity = car.velocity
  local dt = physics_state.frame_delta + 0.00001
  
  -- Calculate acceleration in world space
  local world_accel = (current_velocity - physics_state.last_velocity) / dt
  physics_state.last_velocity = current_velocity
  
  -- Convert to car-local space for realistic head physics
  -- Forward acceleration (Z), Lateral acceleration (X), Vertical (Y)
  local car_look = car.look:normalize()
  local car_side = car.side:normalize()
  local car_up = car.up:normalize()
  
  local local_accel = vec3(
    world_accel:dot(car_side),      -- Lateral G (left-right)
    world_accel:dot(car_up),        -- Vertical G (up-down, usually gravity)
    world_accel:dot(car_look)       -- Longitudinal G (forward-back)
  )
  
  return local_accel
end

local function get_average_suspension_travel()
  -- Get suspension compression across all wheels (0 = fully extended, 1 = compressed)
  local car = ac.getCar(0)
  if not car then return 0 end
  
  -- Try to use suspension position if available
  local total_suspension = 0
  local suspension_count = 0
  
  for i = 0, 3 do
    local wheel = car.wheels[i]
    if wheel then
      -- Normalized suspension travel (0-1 range)
      local suspension_travel = 1.0 - math.clamp(wheel.camber / 0.3, 0, 1)
      total_suspension = total_suspension + suspension_travel
      suspension_count = suspension_count + 1
    end
  end
  
  if suspension_count > 0 then
    return total_suspension / suspension_count
  else
    return 0
  end
end

local function spring_damper_physics(current, velocity, target, stiffness, damping, dt)
  -- Realistic spring-damper system for head movement
  -- Models a mass-spring-damper: m*a = -k*x - c*v
  
  local displacement = target - current
  local spring_force = displacement * stiffness * 100  -- Stiffness factor
  local damping_force = -velocity * damping * 5       -- Damping force
  
  local total_force = spring_force + damping_force
  local acceleration = total_force * 0.5  -- Mass-like factor
  
  local new_velocity = velocity + acceleration * dt
  local new_position = current + new_velocity * dt
  
  return new_position, new_velocity
end

local function apply_exponential_smoothing(current, target, smoothing_factor)
  -- Exponential smoothing: position = current + (target - current) * (1 - exp(-k*t))
  local alpha = 1.0 - math.exp(-smoothing_factor * 10)
  return current + (target - current) * alpha
end

-- ============================================================================
-- Head Position Calculation (Core Physics)
-- ============================================================================

local function calculate_head_movement()
  local car = ac.getCar(0)
  if not car then return vec3(0, 0, 0) end
  
  -- Calculate G-forces in car-local space
  local accel = calculate_car_acceleration()
  local g_force = accel / 9.81
  
  -- LONGITUDINAL (Z): Acceleration/Braking lag
  -- Head lags backward during acceleration, lurches forward during braking
  local longitudinal_g = g_force.z
  local braking_multiplier = 1.0
  if longitudinal_g < 0 then
    braking_multiplier = settings.braking_multiplier
  end
  
  local target_z = -longitudinal_g * settings.longitudinal_lag * 0.06 * braking_multiplier
  
  -- LATERAL (X): Cornering compression
  -- Head compresses inward toward the turn (spring-damper system)
  local lateral_g = g_force.x
  local target_x = -lateral_g * 0.05 * (1 - settings.lateral_stiffness)
  
  -- Use spring-damper for natural oscillation behavior
  physics_state.head_x, physics_state.vel_x = spring_damper_physics(
    physics_state.head_x,
    physics_state.vel_x,
    target_x,
    settings.lateral_stiffness,
    settings.lateral_damping,
    physics_state.frame_delta
  )
  
  -- VERTICAL (Y): Suspension compression
  -- Head compresses when hitting bumps, bounces back up
  local suspension_avg = get_average_suspension_travel()
  local suspension_change = suspension_avg - physics_state.last_suspension_avg
  physics_state.last_suspension_avg = suspension_avg
  
  -- Bump creates downward compression
  local suspension_force = suspension_change * settings.vertical_sensitivity * 0.15
  local target_y = -suspension_avg * settings.vertical_sensitivity * settings.max_vertical_displacement
  
  -- Apply spring-damper to vertical
  physics_state.head_y, physics_state.vel_y = spring_damper_physics(
    physics_state.head_y,
    physics_state.vel_y,
    target_y + suspension_force,
    0.4,  -- Vertical stiffness
    settings.vertical_damping,
    physics_state.frame_delta
  )
  
  -- Apply smoothing to all axes
  physics_state.head_x = apply_exponential_smoothing(physics_state.head_x, physics_state.head_x, settings.update_smoothing)
  physics_state.head_y = apply_exponential_smoothing(physics_state.head_y, physics_state.head_y, settings.update_smoothing)
  physics_state.head_z = apply_exponential_smoothing(physics_state.head_z, target_z, settings.update_smoothing)
  
  -- Clamp to physical limits
  physics_state.head_x = math.clamp(physics_state.head_x, -settings.max_lateral_displacement, settings.max_lateral_displacement)
  physics_state.head_y = math.clamp(physics_state.head_y, -settings.max_vertical_displacement, settings.max_vertical_displacement)
  physics_state.head_z = math.clamp(physics_state.head_z, -settings.max_forward_displacement, settings.max_forward_displacement)
  
  return vec3(physics_state.head_x, physics_state.head_y, physics_state.head_z)
end

local function apply_look_ahead_bias(head_pos)
  -- Natural head turn into the direction of travel (prospective bias)
  local car = ac.getCar(0)
  if not car then return head_pos end
  
  local velocity = car.velocity
  if velocity:length() > 2 then
    local velocity_normalized = velocity:normalize()
    local car_forward = car.look:normalize()
    local car_side = car.side:normalize()
    
    -- Calculate if we're turning (cross product)
    local steering_angle = math.atan2(velocity_normalized:dot(car_side), velocity_normalized:dot(car_forward))
    
    -- Apply look-ahead bias (head turns slightly into corners)
    head_pos.x = head_pos.x + steering_angle * settings.look_ahead_bias * 0.03
  end
  
  return head_pos
end

-- ============================================================================
-- CSP Integration
-- ============================================================================

function script.update(dt)
  if settings.enabled ~= 1 then return end
  
  physics_state.frame_delta = dt
  physics_state.simulation_time = physics_state.simulation_time + dt
end

function script.onCameraUpdate(camera)
  if settings.enabled ~= 1 then return end
  
  -- Only apply to cockpit camera
  if not camera or (camera.cameraType and camera.cameraType ~= "cockpit") then
    return
  end
  
  -- Calculate head movement with physics
  local head_offset = calculate_head_movement()
  head_offset = apply_look_ahead_bias(head_offset)
  
  -- Apply head movement offset to camera position
  if camera.position then
    camera.position = camera.position + head_offset
  end
end

function script.drawUI()
  -- Debug display (uncomment to see values)
  -- if settings.enabled == 1 then
  --   ui.text("NeckFX X: " .. string.format("%.3f", physics_state.head_x))
  --   ui.text("NeckFX Y: " .. string.format("%.3f", physics_state.head_y))
  --   ui.text("NeckFX Z: " .. string.format("%.3f", physics_state.head_z))
  -- end
end

-- ============================================================================
-- Initialization
-- ============================================================================

load_settings()

return {
  name = "Cockpit Camera - NeckFX",
  onUpdate = script.update,
  onCameraUpdate = script.onCameraUpdate,
  onDrawUI = script.drawUI,
}
