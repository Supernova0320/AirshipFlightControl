-- =====================================
-- Airship Unified Frontend
-- UI Optimized Version (2x2 Monitor)
-- =====================================

-- ---------- Debug ----------
local DEBUG = true
local function dbg(...)
    if DEBUG then
        print("[UI]", ...)
    end
end

-- ---------- Peripherals ----------
local monitor = peripheral.find("monitor") or error("No monitor attached", 0)
local modem   = peripheral.find("modem")   or error("No modem attached", 0)

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)
monitor.setBackgroundColor(colors.black)
monitor.clear()

-- ---------- Channels ----------
local MAIN_CHANNEL = 121
modem.open(MAIN_CHANNEL)

-- ---------- Layout ----------
local LEFT_RATIO = 0.5
local BUTTON_HEIGHT = 2
local BUTTON_MARGIN_Y = 1

-- ---------- Palette ----------
local C = {
    bg = colors.black,
    title = colors.cyan,
    label = colors.lightBlue,
    value = colors.white,
    engine_idle = colors.lightBlue,
    engine_active = colors.cyan,
    stop_idle = colors.gray,
    stop_active = colors.red,
    divider = colors.gray,
}

-- ---------- Engine ----------
local buttons = {
    { label = "FULL AHEAD", level = 4 },
    { label = "AHEAD 3",    level = 3 },
    { label = "AHEAD 2",    level = 2 },
    { label = "AHEAD 1",    level = 1 },
    { label = "STOP",       level = 0 },
}
local currentLevel = 0

-- ---------- Navigation ----------
local currentTarget = { x = nil, z = nil }
local navState = {
    x = nil,
    z = nil,
    steering = "stable",
    active = false,
    mode = "IDLE",
    distance = nil
}

-- ---------- Utils ----------
local function hline(x, y, w, color)
    monitor.setBackgroundColor(C.bg)
    monitor.setTextColor(color)
    monitor.setCursorPos(x, y)
    monitor.write(string.rep("-", w))
end

local function spacer(lines)
    lines = lines or 1
    for _ = 1, lines do
        monitor.setCursorPos(1, select(2, monitor.getCursorPos()) + 1)
    end
end

local function block(x, y, w, h, bg, fg, text)
    monitor.setBackgroundColor(bg)
    monitor.setTextColor(fg)
    for i = 0, h - 1 do
        monitor.setCursorPos(x, y + i)
        monitor.write(string.rep(" ", w))
    end
    if text then
        monitor.setCursorPos(
            x + math.floor((w - #text) / 2),
            y + math.floor(h / 2)
        )
        monitor.write(text)
    end
end

local function distance()
    if navState.distance then return navState.distance end
    if not currentTarget.x or not navState.x then return nil end
    local dx = currentTarget.x - navState.x
    local dz = currentTarget.z - navState.z
    return math.sqrt(dx*dx + dz*dz)
end

-- ---------- Messaging ----------
local function sendUICommand(payload)
    payload.type = "ui_cmd"
    dbg("TX", textutils.serialize(payload))
    modem.transmit(MAIN_CHANNEL, MAIN_CHANNEL, payload)
end

local function sendThrottle(level)
    sendUICommand({ throttle = level })
end

local function sendTarget(x, z)
    sendUICommand({ target = { x = x, z = z } })
end

local function clearTarget()
    sendUICommand({ clear_target = true })
end

-- ---------- UI ----------
local function drawUI()
    monitor.setBackgroundColor(C.bg)
    monitor.clear()

    local sw, sh = monitor.getSize()
    local pw = math.floor(sw * LEFT_RATIO)
    local rx = pw + 3
    local panelW = sw - rx - 1

    monitor.setTextColor(C.title)
    monitor.setCursorPos(2, 1)
    monitor.write("ENGINE CONTROL")
    hline(2, 2, pw - 3, C.divider)

    local startY = 4
    for i, btn in ipairs(buttons) do
        local y = startY + (i - 1) * (BUTTON_HEIGHT + BUTTON_MARGIN_Y)
        local bg
        if btn.level == currentLevel then
            bg = (btn.level == 0) and C.stop_active or C.engine_active
        else
            bg = (btn.level == 0) and C.stop_idle or C.engine_idle
        end
        block(2, y, pw - 3, BUTTON_HEIGHT, bg, colors.black, btn.label)
    end

    monitor.setTextColor(C.title)
    monitor.setCursorPos(rx, 1)
    monitor.write("NAVIGATION")
    hline(rx, 2, panelW, C.divider)

    local y = 4
    local indent = 2

    local function section(t)
        monitor.setTextColor(C.title)
        monitor.setCursorPos(rx, y)
        monitor.write(t)
        y = y + 2
    end

    local function longValue(label, value)
        monitor.setTextColor(C.label)
        monitor.setCursorPos(rx, y)
        monitor.write(label)
        y = y + 1
        monitor.setTextColor(C.value)
        monitor.setCursorPos(rx + indent, y)
        monitor.write(value)
        y = y + 1
    end

    local function stateLine(label, value, color)
        monitor.setTextColor(C.label)
        monitor.setCursorPos(rx, y)
        monitor.write(label)
        monitor.setTextColor(color or C.value)
        monitor.setCursorPos(rx + 9, y)
        monitor.write(value)
        y = y + 1
    end

    section("[ TARGET ]")
    longValue("Target X:", currentTarget.x and string.format("%.3f", currentTarget.x) or "--")
    longValue("Target Z:", currentTarget.z and string.format("%.3f", currentTarget.z) or "--")

    section("[ STATE ]")
    stateLine("Mode:", navState.mode or "IDLE", colors.cyan)
    stateLine("Yaw:", string.upper(navState.steering), colors.lightBlue)

    section("[ METRICS ]")
    local d = distance()
    longValue("Distance:", d and string.format("%.3f", d) or "--")
end

-- ---------- Listener ----------
local lastSnapshot = ""

local function navListener()
    while true do
        local _, _, _, _, msg = os.pullEvent("modem_message")
        if type(msg) == "table" and msg.type == "exec_state" then

            if msg.engine ~= nil then currentLevel = msg.engine end
            if msg.pos then
                navState.x = msg.pos.x
                navState.z = msg.pos.z
            end
            if msg.auto then
                navState.steering = msg.auto.steering or navState.steering
                navState.mode = msg.auto.nav_state or navState.mode
                navState.distance = msg.auto.distance
                if msg.auto.target then
                    currentTarget.x = msg.auto.target.x
                    currentTarget.z = msg.auto.target.z
                end
            end

            navState.active = currentTarget.x ~= nil and navState.x ~= nil

            local snap = string.format(
                "%s|%s|%s|%s",
                tostring(navState.mode),
                tostring(navState.steering),
                tostring(navState.distance),
                tostring(currentLevel)
            )

            if snap ~= lastSnapshot then
                dbg(
                    "RX",
                    "mode=", navState.mode,
                    "yaw=", navState.steering,
                    "dist=", navState.distance,
                    "throttle=", currentLevel
                )
                lastSnapshot = snap
            end

            drawUI()
        end
    end
end

-- ---------- Console ----------
local function consoleLoop()
    while true do
        local input = read()
        local upper = input:upper()

        if upper:sub(1, 10) == "SET TARGET" then
            local rest = input:sub(11):match("^%s*(.-)%s*$")
            local x, z = rest:match("([%-%.%d]+)%s+([%-%.%d]+)")
            if x and z then
                currentTarget.x = tonumber(x)
                currentTarget.z = tonumber(z)
                dbg("CMD set target", currentTarget.x, currentTarget.z)
                sendTarget(currentTarget.x, currentTarget.z)
                drawUI()
            end

        elseif upper == "CLEAR TARGET" then
            dbg("CMD clear target")
            currentTarget.x = nil
            currentTarget.z = nil
            navState.distance = nil
            clearTarget()
            drawUI()
        end
    end
end

-- ---------- Touch ----------
local function touchLoop()
    while true do
        local _, _, x, y = os.pullEvent("monitor_touch")
        local sw = monitor.getSize()
        local pw = math.floor(sw * LEFT_RATIO)

        for i, btn in ipairs(buttons) do
            local by = 4 + (i - 1) * (BUTTON_HEIGHT + BUTTON_MARGIN_Y)
            if x >= 2 and x <= pw - 1 and y >= by and y <= by + BUTTON_HEIGHT - 1 then
                currentLevel = btn.level
                dbg("Touch throttle", btn.level)
                sendThrottle(currentLevel)
                drawUI()
            end
        end
    end
end

-- ---------- Startup ----------
dbg("Frontend start, channel", MAIN_CHANNEL)
sendThrottle(0)
drawUI()
parallel.waitForAny(consoleLoop, navListener, touchLoop)
