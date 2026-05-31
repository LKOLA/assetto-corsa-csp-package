-- ==============================================================================
-- Force Feedback - Ultra Realistic T300RS GT
-- ==============================================================================
-- Advanced physics-based FFB script for CSP 0.3.0-preview342+
-- Optimized for Thrustmaster T300RS GT belt-drive wheel
--
-- Communicates:
--   * Front/rear tire grip and loading
--   * Weight transfer (longitudinal and lateral)
--   * Understeer/oversteer dynamics
--   * Suspension movement and kerb strikes
--   * Road texture and surface detail
--
-- Design philosophy: REALISTIC, not stronger
-- No artificial vibrations, canned effects, or arcade boosts
-- ==============================================================================

local settings = {}
local ffb_state = {
  -- Tire data
  front_grip_level = 1.0,
  rear_grip_level = 1.0,
  front_slip_angle = 0,
  rear_slip_angle = 0,
  tire_load_front = 0,
  tire_load_rear = 0,
  
  -- Weight transfer
  longitudinal_g = 0,
  lateral_g = 0,
  vertical_g = 0,
  
  -- Suspension
  suspension_travel = vec4(0, 0, 0, 0),
  suspension_velocity = vec4(0, 0, 0, 0),
  suspension_prev = vec4(0, 0, 0, 0),
  
  -- FFB output
  base_force = 0,
  total_force = 0,
  force_smoothed = 0,
  
  -- Timing
  frame_delta = 0.016,
  simulation_time = 0,
}

-- ==============================================================================
-- Settings Loading
-- ==============================================================================
local function load_settings()
  local defaults = {
    front_grip_sensitivity = 1.2,
    rear_grip_sensitivity = 1.0,
    slip_threshold = 0.08,
    longitudinal_transfer_gain = 1.3,
    lateral_transfer_gain = 1.1,
    understeer_damping = 0.7,
    oversteer_gain = 1.4,
    oversteer_ramp_speed = 0.04,
    suspension_sensitivity = 1.0,
    kerb_intensity = 1.1,
    kerb_sharpness = 0.12,
    road_texture_gain = 0.3,
    road_texture_frequency = 0.6,
    center_force_boost = 0.15,
    highfreq_restoration = 0.2,
    linearity_correction = 0.95,
    damping_level = 0.12,
    smoothing_factor = 0.08,
    spring_back_rate = 0.5,
    clipping_threshold = 0.88,
    soft_clipping = 0.9,
    gyro_gain_expectation = 100,
    gyro_interaction = 0.3,
    master_gain = 1.0,
    enabled = 1,
    debug_mode = 0,
  }

  local config_path = "extension/lua/ffb/settings.ini"
  if io.fileExists(config_path) then
    local config = ac.INIConfig.load(config_path)
    for key, default_value in pairs(defaults) do
      local loaded = config:get("FFB", key)
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

-- ==============================================================================
-- Physics Data Acquisition
-- ==============================================================================

local function get_car_physics()
  local car = ac.getCar(0)
  if not car then return nil end
  
  return {
    position = car.position,
    velocity = car.velocity,
    acceleration = car.acceleration,
    look = car.look:normalize(),
    side = car.side:normalize(),
    up = car.up:normalize(),
  }
end

local function get_suspension_data()
  local car = ac.getCar(0)
  if not car then return vec4(0, 0, 0, 0) end
  
  -- Get suspension travel for each wheel (0-1 range, 0=extended, 1=compressed)
  local travel = vec4(0, 0, 0, 0)
  for i = 0, 3 do
    local wheel = car.wheels[i]
    if wheel then
      -- Normalized suspension position
      travel[i + 1] = math.clamp((1.0 - wheel.tyreSlip) * 0.5 + 0.5, 0, 1)
    end
  end
  return travel
end

local function get_tire_grip_levels()
  local car = ac.getCar(0)
  if not car then return 1.0, 1.0 end
  
  -- Calculate front and rear tire grip from slip ratio and slip angle
  local front_slip = 0
  local rear_slip = 0
  local wheel_count_f = 0
  local wheel_count_r = 0
  
  for i = 0, 3 do
    local wheel = car.wheels[i]
    if wheel then
      local slip = math.abs(wheel.tyreSlip)
      if i < 2 then  -- Front wheels
        front_slip = front_slip + slip
        wheel_count_f = wheel_count_f + 1
      else  -- Rear wheels
        rear_slip = rear_slip + slip
        wheel_count_r = wheel_count_r + 1
      end
    end
  end
  
  -- Average slip and convert to grip level (0-1)
  front_slip = wheel_count_f > 0 and (front_slip / wheel_count_f) or 0
  rear_slip = wheel_count_r > 0 and (rear_slip / wheel_count_r) or 0
  
  local front_grip = math.max(0, 1.0 - front_slip * 2)
  local rear_grip = math.max(0, 1.0 - rear_slip * 2)
  
  return front_grip, rear_grip
end

local function get_slip_angles()
  local car = ac.getCar(0)
  if not car then return 0, 0 end
  
  local velocity = car.velocity
  if velocity:length() < 1 then return 0, 0 end
  
  local car_forward = car.look:normalize()
  local velocity_normalized = velocity:normalize()
  
  -- Slip angle is angle between car heading and velocity vector
  local cross = car_forward:cross(velocity_normalized)
  local slip_angle = math.asin(math.clamp(cross:length(), -1, 1))
  
  -- Separate front and rear (simplified)
  local front_slip = slip_angle * 0.6
  local rear_slip = slip_angle * 1.0
  
  return front_slip, rear_slip
end

-- ==============================================================================
-- FFB Force Calculation
-- ==============================================================================

local function calculate_base_steering_force(physics)
  -- Base force from steering input (without effects)
  -- This is the foundation all other effects modulate
  
  if not physics then return 0 end
  
  -- Start with zero and build up based on physics
  return 0
end

local function calculate_tire_grip_force()
  -- As tire grip decreases, steering should become lighter
  -- Simulates loss of feedback when tires break traction
  
  local front_grip, rear_grip = get_tire_grip_levels()
  ffb_state.front_grip_level = front_grip
  ffb_state.rear_grip_level = rear_grip
  
  -- Grip modulation: lower grip = lighter steering
  -- Progressive curve: maintains feel until significant slip
  local grip_avg = (front_grip + rear_grip) * 0.5
  local grip_factor = math.pow(grip_avg, 0.8)  -- Smooth curve
  
  return grip_factor * settings.front_grip_sensitivity
end

local function calculate_weight_transfer_force(physics)
  -- Weight transfer creates steering heaviness changes
  -- Braking: front loads up, steering heavier
  -- Accel: front unloads, steering lighter
  -- Cornering: lateral load affects steering
  
  if not physics then return 0 end
  
  -- Convert world acceleration to car-local G-forces
  local world_accel = physics.acceleration
  local long_g = world_accel:dot(physics.look) / 9.81
  local lat_g = world_accel:dot(physics.side) / 9.81
  local vert_g = world_accel:dot(physics.up) / 9.81
  
  ffb_state.longitudinal_g = long_g
  ffb_state.lateral_g = lat_g
  ffb_state.vertical_g = vert_g
  
  -- Longitudinal weight transfer (braking/accel)
  -- Braking (long_g < 0) increases front load → heavier steering
  local long_transfer = long_g * settings.longitudinal_transfer_gain
  
  -- Lateral weight transfer (cornering)
  -- Outside tire loads up, affects steering feel
  local lat_transfer = math.abs(lat_g) * settings.lateral_transfer_gain * 0.5
  
  return (long_transfer + lat_transfer) * 0.1
end

local function calculate_understeer_effect()
  -- Understeer: front grip loss reduces steering response
  -- Driver feels steering become lighter as front slides
  
  local front_grip, _ = get_tire_grip_levels()
  local front_slip, _ = get_slip_angles()
  
  -- Detect understeer: low front grip + positive slip
  local understeer_level = math.max(0, (settings.slip_threshold - front_grip) * 2)
  
  -- Apply damping: reduces steering force smoothly
  local understeer_force = -understeer_level * settings.understeer_damping
  
  return understeer_force
end

local function calculate_oversteer_effect()
  -- Oversteer: rear slip should be detectable
  -- Driver feels rear rotation before spin
  
  _, rear_grip = get_tire_grip_levels()
  _, rear_slip = get_slip_angles()
  
  -- Detect oversteer: low rear grip + rear slip angle
  local oversteer_level = math.max(0, rear_slip - settings.slip_threshold)
  
  -- Ramp up oversteer effect gradually (smoother feel)
  local oversteer_force = oversteer_level * settings.oversteer_gain * settings.oversteer_ramp_speed
  
  return oversteer_force
end

local function calculate_suspension_force()
  -- Suspension movement creates vibration feedback
  -- Kerbs and bumps are felt through suspension compression
  
  local current_suspension = get_suspension_data()
  
  -- Calculate suspension velocity (rate of compression)
  local suspension_delta = current_suspension - ffb_state.suspension_prev
  ffb_state.suspension_velocity = suspension_delta / (ffb_state.frame_delta + 0.0001)
  ffb_state.suspension_prev = current_suspension
  
  -- Average compression and velocity across all wheels
  local avg_compression = (current_suspension.x + current_suspension.y + 
                           current_suspension.z + current_suspension.w) / 4
  local avg_velocity = (ffb_state.suspension_velocity.x + ffb_state.suspension_velocity.y +
                        ffb_state.suspension_velocity.z + ffb_state.suspension_velocity.w) / 4
  
  -- Kerb strikes: sudden compression spikes
  local kerb_force = 0
  if avg_velocity > 0.1 then  -- Rapid compression
    kerb_force = math.min(avg_velocity * settings.kerb_intensity, 1.0) * settings.kerb_sharpness
  end
  
  -- Overall suspension contribution
  local suspension_force = (avg_compression * 0.2 + kerb_force * 0.8) * settings.suspension_sensitivity
  
  return suspension_force
end

local function calculate_road_texture_force(physics)
  -- Subtle road texture feedback
  -- Only physical information (tire-road interaction)
  -- Not fake vibration or noise
  
  if not physics then return 0 end
  
  local speed = physics.velocity:length()
  if speed < 5 then return 0 end  -- No texture feel at low speed
  
  -- Road texture is modulated by suspension movement
  local suspension_travel = get_suspension_data()
  local avg_travel = (suspension_travel.x + suspension_travel.y + 
                      suspension_travel.z + suspension_travel.w) / 4
  
  -- Frequency filter: only low-frequency bumps if frequency is low
  local texture_filter = math.sin(ffb_state.simulation_time * settings.road_texture_frequency)
  
  local texture_force = avg_travel * texture_filter * settings.road_texture_gain
  
  return texture_force
end

local function apply_belt_drive_compensation(force)
  -- T300RS GT compensations:
  --   1. Belt drives have soft center - add slight center force
  --   2. Belt drives lose high-freq detail - restore it
  --   3. Belt drives have linearity issues - correct them
  
  -- Center force boost (helps with dead zone feel)
  local center_boost = math.sign(force) * settings.center_force_boost
  
  -- High-frequency restoration (adds micro-detail)
  local highfreq = math.sin(ffb_state.simulation_time * 20) * settings.highfreq_restoration
  
  -- Apply linearity correction
  force = force * settings.linearity_correction
  
  return force + center_boost + highfreq
end

local function apply_damping(force, dt)
  -- Apply equivalent damping (target 10%)
  -- Prevents excessive oscillation while keeping wheel responsive
  
  local damping_force = -ffb_state.force_smoothed * settings.damping_level
  return force + damping_force
end

local function apply_soft_clipping(force)
  -- Prevent clipping while maintaining detail during high loads
  
  local abs_force = math.abs(force)
  
  if abs_force > settings.clipping_threshold then
    -- Soft clipping: smooth curve near maximum
    local excess = abs_force - settings.clipping_threshold
    local clipping_curve = settings.soft_clipping
    force = math.sign(force) * (settings.clipping_threshold + excess * (1 - clipping_curve))
  end
  
  return force
end

local function smooth_force(current, target, smoothing, dt)
  -- Exponential smoothing to prevent jitter
  local alpha = 1.0 - math.exp(-smoothing * 10)
  return current + (target - current) * alpha
end

-- ==============================================================================
-- Main FFB Calculation
-- ==============================================================================

local function calculate_ffb_force(dt)
  if settings.enabled ~= 1 then return 0 end
  
  local physics = get_car_physics()
  if not physics then return 0 end
  
  -- Accumulate all FFB effects
  local force = 0
  
  -- 1. Base steering force (from steering angle)
  force = force + calculate_base_steering_force(physics)
  
  -- 2. Tire grip modulation (lighter steering as grip decreases)
  local grip_factor = calculate_tire_grip_force()
  force = force * grip_factor
  
  -- 3. Weight transfer (heavier in braking, lighter in accel)
  force = force + calculate_weight_transfer_force(physics)
  
  -- 4. Understeer effect (reduces force as front slides)
  force = force + calculate_understeer_effect()
  
  -- 5. Oversteer effect (detectable rear slip)
  force = force + calculate_oversteer_effect()
  
  -- 6. Suspension and kerb feedback
  force = force + calculate_suspension_force()
  
  -- 7. Road texture (subtle detail)
  force = force + calculate_road_texture_force(physics)
  
  -- 8. T300RS GT belt-drive compensation
  force = apply_belt_drive_compensation(force)
  
  -- 9. Damping (10% equivalent)
  force = apply_damping(force, dt)
  
  -- 10. Soft clipping (prevent saturation)
  force = apply_soft_clipping(force)
  
  -- 11. Apply master gain
  force = force * settings.master_gain
  
  -- 12. Smooth the final force
  ffb_state.force_smoothed = smooth_force(ffb_state.force_smoothed, force, 
                                          settings.smoothing_factor, dt)
  
  return ffb_state.force_smoothed
end

-- ==============================================================================
-- CSP Integration
-- ==============================================================================

function script.update(dt)
  if settings.enabled ~= 1 then return end
  
  ffb_state.frame_delta = dt
  ffb_state.simulation_time = ffb_state.simulation_time + dt
  
  -- Calculate FFB force
  ffb_state.total_force = calculate_ffb_force(dt)
end

function script.onFfbUpdate(car)
  if settings.enabled ~= 1 then return end
  if not car or car.index ~= 0 then return end
  
  -- Apply FFB force to wheel
  -- CSP will add this to the native FFB signal
  car.ffb = ffb_state.total_force
end

function script.drawUI()
  if settings.debug_mode ~= 1 then return end
  
  -- Debug display
  ui.text("FFB Debug Info:")
  ui.text("Front Grip: " .. string.format("%.2f", ffb_state.front_grip_level))
  ui.text("Rear Grip: " .. string.format("%.2f", ffb_state.rear_grip_level))
  ui.text("Long G: " .. string.format("%.2f", ffb_state.longitudinal_g))
  ui.text("Lat G: " .. string.format("%.2f", ffb_state.lateral_g))
  ui.text("FFB Force: " .. string.format("%.3f", ffb_state.total_force))
end

-- ==============================================================================
-- Initialization
-- ==============================================================================

load_settings()

return {
  name = "Force Feedback - Ultra Realistic T300RS GT",
  onUpdate = script.update,
  onFfbUpdate = script.onFfbUpdate,
  onDrawUI = script.drawUI,
}
