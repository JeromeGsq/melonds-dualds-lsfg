-- Auto screen-swap: samples the bottom-left pixel of the top screen every frame; when
-- it's black, swaps screens (drastic.set_swap_screen), otherwise swaps back.
local BLACK_THRESHOLD = 16  -- per-channel; tolerates near-black compression/dither noise

local SAMPLE_X = 0
local SAMPLE_Y = 191  -- bottom-left of the top screen (native 256x192 coordinates)

local frame_count = 0
local swapped = false
local last_pixel_text = "pixel: waiting..."
local last_pixel_color = 0xFFFFFF

function on_frame_update()
    frame_count = frame_count + 1

    local r, g, b = drastic.get_pixel(drastic.C.SCREEN_TOP, SAMPLE_X, SAMPLE_Y)
    if r then
        last_pixel_text = string.format("pixel: r=%d g=%d b=%d", r, g, b)
        last_pixel_color = (r << 16) | (g << 8) | b

        local isBlack = r <= BLACK_THRESHOLD and g <= BLACK_THRESHOLD and b <= BLACK_THRESHOLD
        local shouldSwap = not isBlack
        if shouldSwap ~= swapped then
            swapped = shouldSwap
            drastic.set_swap_screen(swapped)
        end
    end
    if frame_count % 120 == 0 then
        print(last_pixel_text .. " swapped=" .. tostring(swapped))
    end

    drastic.log(drastic.C.SCREEN_TOP, "frame " .. frame_count, 4, 4, 0x00FF00)
    drastic.log(drastic.C.SCREEN_TOP, "swapped: " .. tostring(swapped), 4, 20, 0xFFFF00)
    drastic.log(drastic.C.SCREEN_TOP, last_pixel_text, 4, 36, last_pixel_color)
end
