-- =========================================
-- Airship Main Controller (DUMB EXECUTOR)
-- =========================================

local modem = peripheral.find("modem") or error("No modem")
local ship  = peripheral.find("ship")

-- ---------- Channels ----------
local PERCEPTION_CHANNEL = 65520
local UI_CHANNEL         = 121
local AUTO_CHANNEL       = 301
local ENGINE_CHANNEL     = 15

modem.open(PERCEPTION_CHANNEL)
modem.open(UI_CHANNEL)
modem.open(AUTO_CHANNEL)

-- ---------- Sensor Cache ----------
local sensor = nil

local target = nil
local uiEngineLevel = nil
local autoState = nil

-- ---------- Debug ----------
local lastDebug = 0
local function debugLog(message)
    local now = os.clock()
    if now - lastDebug >= 1.5 then
        print(string.format("[Main] %s", message))
        lastDebug = now
    end
end

-- ---------- Execution State ----------
local execState = {
    mode   = "IDLE",
    yaw    = "stable",
    engine = 0,
    brake  = nil
}

-- ---------- Actuators ----------
local function setYaw(cmd)
    execState.yaw = cmd
    if cmd == "left" then
        redstone.setOutput("left", true)
        redstone.setOutput("right", false)
    elseif cmd == "right" then
        redstone.setOutput("left", false)
        redstone.setOutput("right", true)
    else
        redstone.setOutput("left", false)
        redstone.setOutput("right", false)
    end
end

local function setEngine(level)
    execState.engine = level
    modem.transmit(
        ENGINE_CHANNEL,
        ENGINE_CHANNEL,
        { type = "main_engine_throttle", level = level }
    )
end

local function applyBrake(brake)
    execState.brake = brake
    if not brake or not ship then return end

    local dir = brake.dir or { x = brake.x, z = brake.z }
    local power = brake.power or 0
    if not dir or not dir.x or not dir.z or power == 0 then return end

    local force = { x = dir.x * power, y = 0, z = dir.z * power }
    local pos = sensor and sensor.pos or (ship.getWorldspacePosition and ship.getWorldspacePosition())

    if pos and ship.applyWorldForce then
        pcall(function()
            ship.applyWorldForce(force, pos)
        end)
    end
end

-- ---------- UI Feedback ----------
local function sendUIState()
    modem.transmit(
        UI_CHANNEL,
        UI_CHANNEL,
        {
            type   = "exec_state",
            mode   = execState.mode,
            yaw    = execState.yaw,
            engine = execState.engine,
            brake  = execState.brake,
            pos    = sensor and sensor.pos or nil,
            vel    = sensor and sensor.vel or nil,
            target = target,
            auto   = autoState
        }
    )
end

local function sendAutoSensorUpdate()
    modem.transmit(
        AUTO_CHANNEL,
        AUTO_CHANNEL,
        {
            type  = "sensor_update",
            sensor = sensor and {
                pos = sensor.pos,
                vel = sensor.vel,
                heading = sensor.heading
            } or nil,
            target = target
        }
    )
end

local function sendAutoTarget()
    modem.transmit(
        AUTO_CHANNEL,
        AUTO_CHANNEL,
        {
            type = "nav_target",
            target = target
        }
    )
end

print("=================================")
print("Main Controller ONLINE")
print("Mode: DUMB EXECUTOR")
print("=================================")

-- ---------- Main Loop ----------
while true do
    local _, _, channel, _, msg = os.pullEvent("modem_message")
    if type(msg) ~= "table" then goto continue end

    -- ===== Perception (Front / Rear Sensors) =====
    if channel == PERCEPTION_CHANNEL and msg.position then
        sensor = {
            pos = msg.position,
            vel = msg.velocity,
            heading = msg.heading,
            t   = msg.timestamp
        }

        sendAutoSensorUpdate()
        sendUIState()
        debugLog(string.format(
            "sensor pos=(%.1f,%.1f) heading=(%.2f,%.2f)",
            sensor.pos.x or 0,
            sensor.pos.z or 0,
            (sensor.heading and sensor.heading.x) or 0,
            (sensor.heading and sensor.heading.z) or 0
        ))

    -- ===== UI Command =====
    elseif channel == UI_CHANNEL and msg.type == "ui_cmd" then
        if msg.throttle ~= nil then
            uiEngineLevel = msg.throttle
            setEngine(uiEngineLevel)
        end

        if msg.target then
            target = msg.target
            sendAutoTarget()
        elseif msg.clear_target then
            target = nil
            sendAutoTarget()
        end

        sendUIState()
        debugLog(string.format(
            "ui_cmd throttle=%s target=%s",
            msg.throttle ~= nil and tostring(msg.throttle) or "-",
            msg.target and string.format("(%.1f,%.1f)", msg.target.x or 0, msg.target.z or 0) or "-"
        ))

    -- ===== AUTO Command =====
    elseif channel == AUTO_CHANNEL and msg.type == "auto_cmd" then
        if msg.mode   then execState.mode = msg.mode end
        if msg.yaw    then setYaw(msg.yaw) end
        if msg.engine and uiEngineLevel == nil then setEngine(msg.engine) end
        if msg.brake  then applyBrake(msg.brake) end

        sendUIState()
        debugLog(string.format(
            "auto_cmd mode=%s yaw=%s engine=%s",
            msg.mode or execState.mode,
            msg.yaw or execState.yaw,
            msg.engine and tostring(msg.engine) or "-"
        ))

    -- ===== AUTO State =====
    elseif channel == AUTO_CHANNEL and msg.type == "auto_state" then
        autoState = msg
        if msg.nav_state then execState.mode = msg.nav_state end
        sendUIState()
        debugLog(string.format(
            "auto_state=%s dist=%s",
            msg.nav_state or "-",
            msg.distance and string.format("%.1f", msg.distance) or "-"
        ))
    end

    ::continue::
end
