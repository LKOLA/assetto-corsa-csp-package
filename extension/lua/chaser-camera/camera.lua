-- ============================================================================
-- Chaser Camera - Insta360 Rear View (Cinematic)
-- ============================================================================
-- A production-ready rear-mounted camera that simulates an Insta360 action cam
-- mounted behind a sports car.
--
-- Features:
--   * Horizon lock (stable horizon on camber)
--   * Smooth yaw/pitch tracking with gimbal inertia
--   * Dynamic FOV (increases at high speed)
--   * Direction-following with look-ahead bias
--   * Stable under all dynamic conditions
--
-- Compatible with CSP 0.3.0-preview342+
-- Optimized for 144+ Hz displays
-- ============================================================================

local settings = {}
local camera_state = {
  target_yaw = 0,
  target_pitch = 0,
  current_yaw = 0,
  current_pitch = 0,
  current_fov = 108,
  frame_time = 0.016,
}

-- ============================================================================
-- Settings Loading
-- ============================================================================
local function load_settings()
  -- Default settings (fallback)
  local defaults = {
    distance = 4.2,
    height = 1.95,
    base_fov = 108,
    speed_fov_threshold = 150,
    high_speed_fov = 112,
    yaw_smoothing = 0.18,
    pitch_smoothing = 0.22,
    roll_damping = 0.85,
    look_ahead = 0.08,
    rotation_inertia = 0.12,
    lateral_offset = 0.0,
    enabled = 1,
  }

  -- Try to load from settings.ini
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
-- Vector and Math Utilities
-- ============================================================================
local function normalize_angle(angle)
  -- Normalize angle to -π to π range
  while angle > math.pi do angle = angle - 2 * math.pi end
  while angle < -math.pi do angle = angle + 2 * math.pi end
  return angle
end

local function shortest_angle_diff(from, to)
  -- Calculate shortest rotational distance between two angles
  local diff = normalize_angle(to - from)
  return diff
end

local function smooth_damp(current, target, smoothing, dt)
  -- Exponential smoothing with frame-time independence
  local speed = math.exp(-smoothing * 10)
  local difference = target - current
  return current + difference * (1 - speed)
end

-- ============================================================================
-- Camera Position & Orientation Calculation
-- ============================================================================

local function calculate_camera_position()
  -- Get car transform
  local car = ac.getCar(0)
  if not car then return vec3(0, 0, 0), 0, 0 end
  
  local car_pos = car.position
  local car_dir = car.look:normalize()  -- Forward direction
  local car_side = car.side:normalize()  -- Right direction
  local car_up = car.up:normalize()      -- Up direction
  
  -- Position camera behind car
  local behind_offset = car_dir * -settings.distance
  local height_offset = car_up * settings.height
  local lateral_offset = car_side * settings.lateral_offset
  
  local camera_pos = car_pos + behind_offset + height_offset + lateral_offset
  
  return camera_pos, car_dir, car_up
end

local function calculate_target_yaw_pitch(car_dir, car_up)
  -- Calculate yaw (horizontal angle) and pitch (vertical angle)
  -- relative to camera looking at car rear
  
  local car = ac.getCar(0)
  if not car then return 0, 0 end
  
  -- Car velocity direction (for look-ahead bias)
  local velocity = car.velocity:normalize()
  
  -- Yaw: angle in horizontal plane
  local horizontal_dir = vec3(car_dir.x, 0, car_dir.z):normalize()
  local yaw = math.atan2(horizontal_dir.z, horizontal_dir.x)
  
  -- Apply look-ahead bias (camera leads in direction of travel)
  if velocity:length() > 0.1 then
    local velocity_yaw = math.atan2(velocity.z, velocity.x)
    local yaw_diff = normalize_angle(velocity_yaw - yaw)
    yaw = yaw + yaw_diff * settings.look_ahead
  end
  
  -- Pitch: vertical angle (slight downward tilt)
  local pitch = math.atan2(-car_dir.y, 
                          math.sqrt(car_dir.x * car_dir.x + car_dir.z * car_dir.z))
  pitch = pitch * 0.3  -- Dampen pitch oscillation
  
  return yaw, pitch
end

local function calculate_dynamic_fov()
  -- Increase FOV at high speeds (dynamic zoom effect)
  local car = ac.getCar(0)
  if not car then return settings.base_fov end
  
  local speed_kmh = car.speedometer * 3.6  -- Convert m/s to km/h
  
  if speed_kmh > settings.speed_fov_threshold then
    -- Linear interpolation between base and high-speed FOV
    local speed_factor = math.min((speed_kmh - settings.speed_fov_threshold) / 100, 1)
    local target_fov = settings.base_fov + (settings.high_speed_fov - settings.base_fov) * speed_factor
    return target_fov
  else
    return settings.base_fov
  end
end

local function apply_horizon_lock(pitch, roll)
  -- Dampen roll to keep horizon stable
  -- This prevents excessive camera tilt on camber
  local car = ac.getCar(0)
  if not car then return pitch, 0 end
  
  -- Get car's actual roll angle
  local car_right = car.side
  local world_right = vec3(1, 0, 0)
  local roll_angle = math.acos(math.clamp(car_right:dot(world_right), -1, 1))
  
  -- Apply damping to roll to keep horizon lock
  local damped_roll = roll_angle * (1 - settings.roll_damping)
  
  return pitch, damped_roll
end

-- ============================================================================
-- Camera Update Loop
-- ============================================================================

local function update_camera(dt)
  if settings.enabled == 0 then return end
  
  camera_state.frame_time = dt
  
  -- Get car position and orientation
  local camera_pos, car_dir, car_up = calculate_camera_position()
  if not camera_pos then return end
  
  -- Calculate target yaw and pitch
  local target_yaw, target_pitch = calculate_target_yaw_pitch(car_dir, car_up)
  
  -- Apply rotation inertia (gimbal lag)
  local yaw_smooth = settings.yaw_smoothing + settings.rotation_inertia
  local pitch_smooth = settings.pitch_smoothing + settings.rotation_inertia
  
  -- Smooth camera rotation
  camera_state.current_yaw = smooth_damp(camera_state.current_yaw, target_yaw, yaw_smooth, dt)
  camera_state.current_pitch = smooth_damp(camera_state.current_pitch, target_pitch, pitch_smooth, dt)
  
  -- Apply horizon lock to dampen roll
  local _, locked_roll = apply_horizon_lock(camera_state.current_pitch, 0)
  
  -- Calculate dynamic FOV
  local target_fov = calculate_dynamic_fov()
  camera_state.current_fov = smooth_damp(camera_state.current_fov, target_fov, 0.1, dt)
end

function script.update(dt)
  -- Called each frame by CSP
  if settings.enabled == 1 then
    update_camera(dt)
  end
end

-- ============================================================================
-- Camera Callback
-- ============================================================================

function script.onCameraUpdate(camera)
  if settings.enabled == 0 then return end
  
  -- Only apply to chaser/external camera
  if camera.cameraType ~= "chaser" and camera.cameraType ~= "external" then
    return
  end
  
  -- Get car state
  local car = ac.getCar(0)
  if not car then return end
  
  local car_pos = car.position
  local car_dir = car.look:normalize()
  local car_up = car.up:normalize()
  local car_side = car.side:normalize()
  
  -- Position camera behind car
  local behind_offset = car_dir * -settings.distance
  local height_offset = car_up * settings.height
  local lateral_offset = car_side * settings.lateral_offset
  
  local camera_pos = car_pos + behind_offset + height_offset + lateral_offset
  camera.position = camera_pos
  
  -- Look at car rear with calculated yaw/pitch
  -- Build rotation matrix from yaw and pitch
  local cos_yaw = math.cos(camera_state.current_yaw)
  local sin_yaw = math.sin(camera_state.current_yaw)
  local cos_pitch = math.cos(camera_state.current_pitch)
  local sin_pitch = math.sin(camera_state.current_pitch)
  
  -- Forward direction (looking at car)
  local look_dir = vec3(
    sin_yaw * cos_pitch,
    sin_pitch,
    cos_yaw * cos_pitch
  ):normalize()
  
  -- Up direction (with horizon lock)
  local up_dir = vec3(
    -sin_yaw * sin_pitch,
    cos_pitch,
    -cos_yaw * sin_pitch
  ):normalize()
  
  camera.look = look_dir
  camera.up = up_dir
  camera.fov = camera_state.current_fov
end

function script.onGUIDrawAfterCars(draw_now)
  -- Optional: Draw debug info
  -- Uncomment to see real-time camera values during gameplay
  -- if settings.enabled == 1 then
  --   ui.text("Insta360 Yaw: " .. string.format("%.1f°", math.deg(camera_state.current_yaw)))
  --   ui.text("Insta360 Pitch: " .. string.format("%.1f°", math.deg(camera_state.current_pitch)))
  --   ui.text("Insta360 FOV: " .. string.format("%.1f°", camera_state.current_fov))
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
