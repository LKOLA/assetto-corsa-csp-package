-- ============================================================================
-- Chaser Camera - Insta360 Rear View (Cinematic)
-- ============================================================================
-- PRODUCTION PHYSICS: Rear-mounted camera simulating Insta360 action cam
-- mounted behind a sports car.
--
-- Features:
--   * Horizon lock (stable horizon on camber)
--   * Smooth yaw/pitch/roll tracking with gimbal inertia
--   * Dynamic FOV (increases at high speed)
--   * Direction-following with look-ahead bias
--   * Spring-damper camera physics for natural motion
--   * Stable under all dynamic conditions
--
-- Compatible with CSP 0.3.0-preview342+
-- Optimized for 144+ Hz displays
-- ============================================================================

local settings = {}
local camera_physics = {
  -- Gimbal rotation state
  current_yaw = 0,
  current_pitch = 0,
  current_roll = 0,
  
  -- Gimbal velocity (for inertia)
  yaw_velocity = 0,
  pitch_velocity = 0,
  roll_velocity = 0,
  
  -- FOV state
  current_fov = 108,
  
  -- Frame timing
  frame_delta = 0.016,
  simulation_time = 0,
}

-- ============================================================================
-- Settings Loading
-- ============================================================================
local function load_settings()
  local defaults = {
    -- Camera positioning
    distance = 4.2,              -- Distance behind car (meters)
    height = 1.95,               -- Height above ground (meters)
    lateral_offset = 0.0,        -- Left-right offset from centerline
    
    -- FOV dynamics
    base_fov = 108,              -- Base field of view (degrees)
    speed_fov_threshold = 150,   -- Speed at which FOV increases (km/h)
    high_speed_fov = 112,        -- FOV at high speed (degrees)
    
    -- Gimbal smoothing (lower = snappier, higher = sluggish)
    yaw_smoothing = 0.15,        -- Horizontal tracking smoothness
    pitch_smoothing = 0.20,      -- Vertical tracking smoothness
    roll_smoothing = 0.25,       -- Horizon lock smoothness
    
    -- Gimbal inertia (rotational lag from physics)
    rotation_inertia = 0.08,     -- Gimbal lag (0-0.3, higher = more lag)
    
    -- Horizon lock damping (higher = more stable)
    roll_damping = 0.82,         -- Prevents excessive tilt on camber
    
    -- Direction-following bias
    look_ahead = 0.06,           -- Bias toward direction of travel
    yaw_lead_gain = 1.0,         -- Yaw response to car heading
    
    enabled = 1,
  }

  local config_path = "extension/lua/chaser-camera/settings.ini"
  if io.fileExists(config_path) then
    local config = ac.INIConfig.load(config_path)
    for key, default_value in pairs(defaults) do
      local loaded = config:get("Insta360", key)
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
-- Math Utilities
-- ============================================================================

local function normalize_angle(angle)
  -- Normalize to -π to +π range
  while angle > math.pi do angle = angle - 2 * math.pi end
  while angle < -math.pi do angle = angle + 2 * math.pi end
  return angle
end

local function shortest_angle_diff(current, target)
  -- Calculate shortest rotational path
  local diff = normalize_angle(target - current)
  return diff
end

local function gimbal_inertia_physics(current, velocity, target, smoothing, inertia, dt)
  -- Physics-based gimbal tracking with rotational inertia
  -- Models: angular_accel = -k*(angle - target) - c*angular_velocity
  
  local angle_error = shortest_angle_diff(current, target)
  
  -- Spring-like force toward target
  local stiffness = (1.0 - smoothing) * 3.0
  local spring_force = angle_error * stiffness
  
  -- Damping to prevent oscillation
  local damping = smoothing * 2.0
  local damping_force = -velocity * damping
  
  -- Inertia: rotational lag (gimbal doesn't snap instantly)
  local inertia_force = inertia * 0.5
  
  local total_force = spring_force + damping_force
  local angular_accel = total_force * (1.0 - inertia_force)
  
  local new_velocity = velocity + angular_accel * dt
  local new_angle = current + new_velocity * dt
  
  return normalize_angle(new_angle), new_velocity
end

local function exponential_damp(current, target, smoothing, dt)
  -- Simple exponential smoothing
  local alpha = 1.0 - math.exp(-smoothing * 10)
  return current + (target - current) * alpha
end

-- ============================================================================
-- Camera Orientation Calculation
-- ============================================================================

local function calculate_target_angles()
  local car = ac.getCar(0)
  if not car then return 0, 0, 0 end
  
  local car_dir = car.look:normalize()    -- Car forward
  local car_side = car.side:normalize()   -- Car right
  local car_up = car.up:normalize()       -- Car up
  local velocity = car.velocity:normalize()
  
  -- YAW: Horizontal angle (left-right looking at car rear)
  -- This is the primary tracking axis
  local horizontal_proj = vec3(car_dir.x, 0, car_dir.z):normalize()
  local yaw = math.atan2(horizontal_proj.z, horizontal_proj.x)
  
  -- Apply look-ahead bias (camera leads in direction of travel)
  if velocity:length() > 0.5 then
    local velocity_yaw = math.atan2(velocity.z, velocity.x)
    local yaw_diff = shortest_angle_diff(yaw, velocity_yaw)
    yaw = yaw + yaw_diff * settings.look_ahead
  end
  
  -- PITCH: Vertical angle (slight downward tilt to see rear bumper)
  -- Fixed slight downward angle for framing
  local pitch = math.atan2(-car_dir.y, 
                          math.sqrt(car_dir.x * car_dir.x + car_dir.z * car_dir.z))
  pitch = pitch * 0.25  -- Dampen pitch to keep horizon level
  
  -- ROLL: Camera tilt (for horizon lock)
  -- Extract roll from car up vector
  local roll = math.atan2(car_side.y, car_up.y)
  roll = roll * (1.0 - settings.roll_damping)  -- Dampen roll for stable horizon
  
  return yaw, pitch, roll
end

local function calculate_dynamic_fov()
  -- Increase FOV at high speeds (cinematic zoom)
  local car = ac.getCar(0)
  if not car then return settings.base_fov end
  
  local speed_kmh = car.speedometer * 3.6  -- m/s to km/h
  
  if speed_kmh > settings.speed_fov_threshold then
    -- Linear interpolation
    local excess_speed = math.min(speed_kmh - settings.speed_fov_threshold, 100)
    local speed_factor = excess_speed / 100
    local target_fov = settings.base_fov + (settings.high_speed_fov - settings.base_fov) * speed_factor
    return target_fov
  else
    return settings.base_fov
  end
end

-- ============================================================================
-- Camera Position Calculation
-- ============================================================================

local function calculate_camera_position()
  local car = ac.getCar(0)
  if not car then return vec3(0, 0, 0) end
  
  local car_pos = car.position
  local car_dir = car.look:normalize()
  local car_up = car.up:normalize()
  local car_side = car.side:normalize()
  
  -- Position camera behind and above car
  local behind = car_dir * -settings.distance
  local above = car_up * settings.height
  local lateral = car_side * settings.lateral_offset
  
  return car_pos + behind + above + lateral
end

local function build_rotation_matrix(yaw, pitch, roll)
  -- Build rotation matrix from Euler angles (yaw-pitch-roll)
  local cy = math.cos(yaw)
  local sy = math.sin(yaw)
  local cp = math.cos(pitch)
  local sp = math.sin(pitch)
  local cr = math.cos(roll)
  local sr = math.sin(roll)
  
  -- Calculate forward direction (camera looking vector)
  local look = vec3(
    sy * cp * cr - cy * sr,
    sp * cr,
    cy * cp * cr + sy * sr
  ):normalize()
  
  -- Calculate up direction
  local up = vec3(
    sy * cp * sr + cy * cr,
    sp * sr,
    cy * cp * sr - sy * cr
  ):normalize()
  
  return look, up
end

-- ============================================================================
-- Update Loop
-- ============================================================================

local function update_camera(dt)
  if settings.enabled ~= 1 then return end
  
  camera_physics.frame_delta = dt
  camera_physics.simulation_time = camera_physics.simulation_time + dt
  
  -- Calculate target gimbal angles
  local target_yaw, target_pitch, target_roll = calculate_target_angles()
  
  -- Apply gimbal inertia physics (smooth tracking with lag)
  camera_physics.current_yaw, camera_physics.yaw_velocity = gimbal_inertia_physics(
    camera_physics.current_yaw,
    camera_physics.yaw_velocity,
    target_yaw,
    settings.yaw_smoothing,
    settings.rotation_inertia,
    dt
  )
  
  camera_physics.current_pitch, camera_physics.pitch_velocity = gimbal_inertia_physics(
    camera_physics.current_pitch,
    camera_physics.pitch_velocity,
    target_pitch,
    settings.pitch_smoothing,
    settings.rotation_inertia * 0.7,
    dt
  )
  
  camera_physics.current_roll, camera_physics.roll_velocity = gimbal_inertia_physics(
    camera_physics.current_roll,
    camera_physics.roll_velocity,
    target_roll,
    settings.roll_smoothing,
    settings.rotation_inertia * 0.5,
    dt
  )
  
  -- Calculate dynamic FOV
  local target_fov = calculate_dynamic_fov()
  camera_physics.current_fov = exponential_damp(camera_physics.current_fov, target_fov, 0.12, dt)
end

function script.update(dt)
  if settings.enabled ~= 1 then return end
  update_camera(dt)
end

-- ============================================================================
-- Camera Callback (CSP Integration)
-- ============================================================================

function script.onCameraUpdate(camera)
  if settings.enabled ~= 1 then return end
  if not camera then return end
  
  -- Apply to external/chaser cameras
  if camera.cameraType and camera.cameraType ~= "chaser" and camera.cameraType ~= "external" then
    return
  end
  
  -- Set camera position
  camera.position = calculate_camera_position()
  
  -- Set camera orientation using gimbal angles
  local look_dir, up_dir = build_rotation_matrix(
    camera_physics.current_yaw,
    camera_physics.current_pitch,
    camera_physics.current_roll
  )
  
  camera.look = look_dir
  camera.up = up_dir
  camera.fov = camera_physics.current_fov
end

function script.onGUIDrawAfterCars(draw_now)
  -- Debug info (uncomment to display values)
  -- if settings.enabled == 1 then
  --   ui.text("Insta360 | Yaw: " .. string.format("%.1f°", math.deg(camera_physics.current_yaw)))
  --   ui.text("Insta360 | Pitch: " .. string.format("%.1f°", math.deg(camera_physics.current_pitch)))
  --   ui.text("Insta360 | Roll: " .. string.format("%.1f°", math.deg(camera_physics.current_roll)))
  --   ui.text("Insta360 | FOV: " .. string.format("%.1f°", camera_physics.current_fov))
  -- end
end

-- ============================================================================
-- Initialization
-- ============================================================================

load_settings()

return {
  name = "Chaser Camera - Insta360 Rear View",
  onUpdate = script.update,
  onCameraUpdate = script.onCameraUpdate,
  onGUIDrawAfterCars = script.onGUIDrawAfterCars,
}
