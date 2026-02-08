-- =====================================
-- Main Engine Frontend Controller
-- Polished UI (No size change)
-- =====================================

-- ---- Peripherals ----
local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
local modem   = peripheral.find("modem")   or error("No modem attached", 0)

monitor.setTextScale(0.5)
monitor.clear()
monitor.setCursorBlink(false)

-- ---- Constants ----
local COMMAND_CHANNEL = 15

local LEFT_PANEL_RATIO = 0.5
local BUTTON_HEIGHT = 2
local BUTTON_MARGIN_Y = 1

local buttons = {
    { label = "FULL AHEAD", level = 4 },
    { label = "AHEAD 3",    level = 3 },
    { label = "AHEAD 2",    level = 2 },
    { label = "AHEAD 1",    level = 1 },
    { label = "STOP",       level = 0 },
}

-- ---- State ----
local currentLevel = 0

-- ---- Communication ----
local function sendThrottle(level)
    modem.transmit(
        COMMAND_CHANNEL,
        COMMAND_CHANNEL,
        { type = "main_engine_throttle", level = level }
    )
end

-- ---- Drawing Helpers ----
local function drawBlock(x, y, w, h, bg, fg, text)
    monitor.setBackgroundColor(bg)
    monitor.setTextColor(fg)

    for i = 0, h - 1 do
        monitor.setCursorPos(x, y + i)
        monitor.write(string.rep(" ", w))
    end

    if text then
        local tx = x + math.floor((w - #text) / 2)
        local ty = y + math.floor(h / 2)
        monitor.setCursorPos(tx, ty)
        monitor.write(text)
    end
end

local function drawHLine(x, y, w, color)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(color)
    monitor.setCursorPos(x, y)
    monitor.write(string.rep("-", w))
end

-- ---- UI ----
local function drawUI()
    monitor.clear()
    local sw, sh = monitor.getSize()
    local panelWidth = math.floor(sw * LEFT_PANEL_RATIO)

    -- ===== Left Panel Title =====
    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.black)
    monitor.setCursorPos(2, 1)
    monitor.write("ENGINE CONTROL")

    drawHLine(2, 2, panelWidth - 3, colors.gray)

    -- ===== Buttons =====
    local startY = 3

    for i, btn in ipairs(buttons) do
        local y = startY + (i - 1) * (BUTTON_HEIGHT + BUTTON_MARGIN_Y)

        local bg
        if btn.level == currentLevel then
            bg = (btn.level == 0) and colors.red or colors.blue
        else
            bg = (btn.level == 0) and colors.gray or colors.lightGray
        end

        drawBlock(
            2,
            y,
            panelWidth - 3,
            BUTTON_HEIGHT,
            bg,
            colors.white,
            btn.label
        )
    end

    -- ===== Right Panel =====
    local rx = panelWidth + 2

    monitor.setTextColor(colors.white)
    monitor.setCursorPos(rx, 1)
    monitor.write("STATUS")

    drawHLine(rx, 2, sw - rx - 1, colors.gray)

    monitor.setTextColor(colors.lightGray)
    monitor.setCursorPos(rx, 4)
    monitor.write("ENGINE:")

    monitor.setCursorPos(rx, 5)
    if currentLevel == 0 then
        monitor.setTextColor(colors.red)
        monitor.write("STOPPED")
    else
        monitor.setTextColor(colors.green)
        monitor.write("AHEAD " .. currentLevel)
    end

    monitor.setTextColor(colors.gray)
    monitor.setCursorPos(rx, 7)
    monitor.write("CHANNEL:")
    monitor.setCursorPos(rx, 8)
    monitor.write(tostring(COMMAND_CHANNEL))
end

-- ---- Init ----
sendThrottle(0)
drawUI()

-- ---- Main Loop ----
while true do
    local _, _, x, y = os.pullEvent("monitor_touch")

    local sw, sh = monitor.getSize()
    local panelWidth = math.floor(sw * LEFT_PANEL_RATIO)

    for i, btn in ipairs(buttons) do
        local by = 3 + (i - 1) * (BUTTON_HEIGHT + BUTTON_MARGIN_Y)
        local bx1 = 2
        local bx2 = panelWidth - 1
        local by2 = by + BUTTON_HEIGHT - 1

        if x >= bx1 and x <= bx2 and y >= by and y <= by2 then
            currentLevel = btn.level
            sendThrottle(currentLevel)
            drawUI()
            break
        end
    end
end
