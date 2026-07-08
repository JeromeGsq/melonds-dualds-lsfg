-- Global state variables
local touch_hold_time = 10  -- Frames to hold the touch
local touch_release_time = 5  -- Frames to wait before releasing
local touch_state = 0  -- 0 = idle, positive = holding touch, negative = releasing
local touch_x = 0
local touch_y = 0

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
    
    -- Check if B button should trigger touch
    if touch_on_button(drastic.C.BUTTON_B, 32, 18) then
        -- Touch started, will be handled below
    end
    
    -- Handle touch state machine
    if touch_state > 0 then
        -- Holding touch
        buttons = buttons | drastic.C.BUTTON_TOUCH
        drastic.set_buttons(buttons)
        drastic.set_touch(touch_x, touch_y)
        touch_state = touch_state - 1
        
        -- Transition to release state
        if touch_state == 0 then
            touch_state = -touch_release_time
        end
    elseif touch_state < 0 then
        -- Releasing touch
        buttons = buttons & ~drastic.C.BUTTON_TOUCH
        drastic.set_buttons(buttons)
        touch_state = touch_state + 1
    else
        -- Idle state
        drastic.set_buttons(buttons)
    end
end  