-- ==============================================================================
-- Ferrari 812 Digital Cluster Script
-- ==============================================================================
-- KPH Display with Dynamic License Plate Support
-- Compatible with CSP 0.3.0-preview342+
--
-- Features:
--   * Speed display in KPH (not MPH)
--   * Real-time license plate text rendering
--   * Dynamic gear display
--   * Configurable plate text via settings.ini
-- ==============================================================================

-- Gear mapping
local gearT = {
    [-1] = "R",
    [0] = "N",
    [1] = "1",
    [2] = "2",
    [3] = "3",
    [4] = "4",
    [5] = "5",
    [6] = "6",
    [7] = "7",
    [8] = "8"
}

-- Colors
local white = rgb(1, 1, 1)
local orange = rgb(0, 1, 1.7)
local blue = rgb(1, 1, 1)
local red = rgb(1, 0, 0)

-- Configuration
local config = {
    speed_display_enabled = true,
    license_plate_text = "812ITALIA",  -- Default license plate text
    license_plate_enabled = true,
    font_speed = "mg",
    font_gear = "c7_new",
    color_speed = white,
    color_gear = white,
    color_plate = white,
}

-- ==============================================================================
-- Load Configuration from File
-- ==============================================================================
local function load_config()
    -- Try to load custom settings
    local config_path = "cfg/ferrari_812_cluster.ini"
    if io.fileExists(config_path) then
        local file = io.open(config_path, "r")
        if file then
            for line in file:lines() do
                -- Parse simple INI format
                if line:find("PLATE_TEXT") then
                    local text = line:match("PLATE_TEXT%s*=%s*(.+)")
                    if text then
                        config.license_plate_text = text:gsub('"', ''):gsub("'", '')
                    end
                end
            end
            io.close(file)
        end
    end
end

-- ==============================================================================
-- Display Functions
-- ==============================================================================

local function display_speed_kph()
    -- Display speed in KPH (not MPH)
    local speed_kph = math.floor(car.speedKmh)  -- Already in KPH
    
    display.text({
        text = tostring(speed_kph),
        pos = vec2(200, 229),
        letter = vec2(140, 170),
        font = config.font_speed,
        color = config.color_speed,
        alignment = 0.5,
        width = 310,
        spacing = 0
    })
end

local function display_kph_unit()
    -- Display "KPH" text (changed from "mph")
    display.text({
        text = 'km/h',
        pos = vec2(560, 178),
        letter = vec2(55, 64),
        font = config.font_speed,
        color = config.color_speed,
        alignment = -3,
        width = 251,
        spacing = -2
    })
end

local function display_gear()
    -- Display current gear
    display.text({
        text = gearT[car.gear] or "N",
        pos = vec2(1100, 155),
        letter = vec2(40, 77),
        font = config.font_gear,
        color = config.color_gear,
        alignment = 0.5,
        width = 251,
        spacing = 1
    })
end

local function display_license_plate()
    -- Display dynamic license plate text
    if not config.license_plate_enabled then return end
    
    display.text({
        text = config.license_plate_text,
        pos = vec2(300, 400),  -- Adjust position as needed for your cluster layout
        letter = vec2(25, 45),
        font = "digital_big",
        color = config.color_plate,
        alignment = 0.5,
        width = 400,
        spacing = 1
    })
end

-- ==============================================================================
-- Input Handling (for real-time license plate changes)
-- ==============================================================================

local plate_input_buffer = ""
local is_editing_plate = false

local function handle_plate_edit()
    -- Allow user input for license plate (if implemented in your UI system)
    -- This is a placeholder for custom UI interaction
    -- In a real implementation, you would hook into Content Manager's input system
end

-- ==============================================================================
-- Main Update Loop
-- ==============================================================================

function update(dt)
    -- Update display every frame
    if config.speed_display_enabled then
        display_speed_kph()
        display_kph_unit()
    end
    
    -- Display gear
    display_gear()
    
    -- Display license plate
    display_license_plate()
end

-- ==============================================================================
-- Initialization
-- ==============================================================================

-- Load configuration on startup
load_config()
