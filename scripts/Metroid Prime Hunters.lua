-- Global state variables
local current_x = 0
local current_y = 0

local deadzone = 0.01  -- Stick deadzone to prevent drift
local sensitivity = 1.5  -- Pixels per frame at full stick deflection; adjust for feel

local end_count = 0
local pressed = 0

-- Touch button feature state variables
local touch_hold_time = 10  -- Frames to hold the touch
local touch_release_time = 5  -- Frames to wait before releasing
local touch_state = 0  -- 0 = idle, positive = holding touch, negative = releasing
local touch_x = 0
local touch_y = 0

-- Double-tap feature state variables
local double_tap_state = 0  -- 0=idle, 1=first press, 2=first release, 3=wait, 4=second press, 5=second release
local double_tap_direction = 0  -- Stores the direction to double-tap
local double_tap_counter = 0  -- Frame counter for timing
local double_tap_press_time = 2  -- Frames to hold each tap (reduced for less lag)
local double_tap_wait_time = 1  -- Frames to wait between taps (reduced for less lag)
local b_was_pressed = false  -- Track B button state to prevent repeat triggers

-- Function to touch a specific position when a button is pressed
-- The touch will be held for multiple frames for better detection
-- Parameters:
--   button_mask: the button constant (e.g., drastic.C.BUTTON_A, drastic.C.BUTTON_B, etc.)
--   x: x coordinate to touch (0-255)
--   y: y coordinate to touch (0-191)
--   hold_frames: optional number of frames to hold touch (default: 10)
function touch_on_button(button_mask, x, y, hold_frames)
    local buttons = drastic.get_buttons()
    hold_frames = hold_frames or touch_hold_time
    
    -- Button is pressed, start new touch
    if buttons & button_mask ~= 0 then
        touch_x = math.floor(x)
        touch_y = math.floor(y)
        touch_state = hold_frames
        return true
    end
    
    return false
end

function on_frame_update()
    local buttons = drastic.get_buttons()
    
    -- Check for double-tap trigger (B button pressed while holding a direction)
    if double_tap_state == 0 then
        local b_pressed = (buttons & drastic.C.BUTTON_B ~= 0)
        
        if b_pressed and not b_was_pressed then
            -- B button just pressed, check if a direction is held
            local direction = 0
            if buttons & drastic.C.BUTTON_UP ~= 0 then
                direction = drastic.C.BUTTON_UP
            elseif buttons & drastic.C.BUTTON_DOWN ~= 0 then
                direction = drastic.C.BUTTON_DOWN
            elseif buttons & drastic.C.BUTTON_LEFT ~= 0 then
                direction = drastic.C.BUTTON_LEFT
            elseif buttons & drastic.C.BUTTON_RIGHT ~= 0 then
                direction = drastic.C.BUTTON_RIGHT
            end
            
            if direction ~= 0 then
                -- Start double-tap sequence
                double_tap_direction = direction
                double_tap_state = 1
                double_tap_counter = double_tap_press_time
            end
        end
        
        b_was_pressed = b_pressed
    end
    
    -- Handle double-tap state machine
    if double_tap_state > 0 then
        double_tap_counter = double_tap_counter - 1
        
        if double_tap_state == 1 then
            -- First press
            drastic.set_buttons(double_tap_direction)
            if double_tap_counter <= 0 then
                double_tap_state = 2
                double_tap_counter = double_tap_wait_time
            end
        elseif double_tap_state == 2 then
            -- First release
            drastic.set_buttons(0)
            if double_tap_counter <= 0 then
                double_tap_state = 3
                double_tap_counter = double_tap_wait_time
            end
        elseif double_tap_state == 3 then
            -- Wait between taps
            drastic.set_buttons(0)
            if double_tap_counter <= 0 then
                double_tap_state = 4
                double_tap_counter = double_tap_press_time
            end
        elseif double_tap_state == 4 then
            -- Second press
            drastic.set_buttons(double_tap_direction)
            if double_tap_counter <= 0 then
                double_tap_state = 5
                double_tap_counter = double_tap_wait_time
            end
        elseif double_tap_state == 5 then
            -- Second release
            drastic.set_buttons(0)
            if double_tap_counter <= 0 then
                double_tap_state = 0
            end
        end
        
        return  -- Skip other input handling during double-tap
    end
    
    if touch_on_button(drastic.C.BUTTON_Y, 6, 20) then
        -- Open Notes
    elseif touch_on_button(drastic.C.BUTTON_X, 248, 20) then
        -- Open Map
    elseif touch_on_button(drastic.C.BUTTON_A, 128, 20) then
        -- Click on action center button
    end
    
    -- Handle touch state machine for button touches
    if touch_state > 0 then
        -- Holding touch - override all buttons with only touch
        local buttons = drastic.C.BUTTON_TOUCH
        drastic.set_buttons(buttons)
        drastic.set_touch(touch_x, touch_y)
        touch_state = touch_state - 1
        
        -- Transition to release state
        if touch_state == 0 then
            touch_state = -touch_release_time
        end
        return  -- Skip analog stick handling while button touch is active
    elseif touch_state < 0 then
        -- Releasing touch - clear all buttons
        local buttons = 0
        drastic.set_buttons(buttons)
        touch_state = touch_state + 1
        return  -- Skip analog stick handling during release
    end

    -- Get right analog stick input
    local rx = android.get_axis_rx()
    local ry = android.get_axis_ry()

    -- Compute magnitude of stick input
    local magnitude = math.sqrt(rx * rx + ry * ry) 
    
    -- If stick is active
    if(magnitude > deadzone) then 
        -- Get buttons
        local buttons = drastic.get_buttons()

        current_x = 128 + (rx * sensitivity) 
        current_y =  96 + (ry * sensitivity) 

        buttons = buttons | drastic.C.BUTTON_TOUCH
        --  buttons = buttons & ~drastic.C.BUTTON_TOUCH
        drastic.set_buttons(buttons)
        drastic.set_touch(math.floor(current_x), math.floor(current_y))
    else  
        if end_count > 0 then
            -- Get buttons
            local buttons = drastic.get_buttons()
            -- Release touch screen 
            buttons = buttons & ~drastic.C.BUTTON_TOUCH 
            drastic.set_buttons(buttons) 
        end
    end
end  