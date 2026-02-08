-- =========================================
-- Airship Main Controller (DUMB EXECUTOR)
-- =========================================

local modem = peripheral.find("modem") or error("No modem")
local ship  = peripheral.find("ship")

-- ---------- Channels ----------
local PERCEPTION_CHANNEL = 65520
local UI_CHANNEL         = 121
local AUTO_CHANNEL       = 301
local ENGINE_CHANNEL     = 15   -- 预留

modem.open(PERCEPTION_CHANNEL)
modem.open(UI_CHANNEL)
modem.open(AUTO_CHANNEL)

-- ---------- Sensor Cache ----------
local sensors = {
    front = nil,
    rear  = nil
}

-- ---------- Execution State ----------
local execState = {
    mode   = "IDLE",
    yaw    = "stable",
    engine = 0,
    brake  = { dir = 0, power = 0 }
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
    -- 预留
end

local function applyBrake(brake)
    execState.brake = brake
    -- 这里只记录，具体实现之后接
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
            pos    = sensors.front and sensors.front.pos or nil
        }
    )
end

print("=================================")
print("Main Controller ONLINE")
print("Mode: DUMB EXECUTOR")
print("=================================")

-- ---------- Main Loop ----------
while true do
    local _, _, channel, _, msg, senderId = os.pullEvent("modem_message")
    if type(msg) ~= "table" then goto continue end

    -- ===== Perception (Front / Rear Sensors) =====
    if channel == PERCEPTION_CHANNEL and msg.role then
        sensors[msg.role] = {
            pos = msg.position,
            vel = msg.velocity,
            t   = msg.timestamp
        }

        -- 传感器数据转发给自动驾驶
        modem.transmit(
            AUTO_CHANNEL,
            AUTO_CHANNEL,
            {
                type  = "sensor_update",
                front = sensors.front and {
                    pos = sensors.front.pos,
                    vel = sensors.front.vel
                } or nil,
                rear  = sensors.rear and {
                    pos = sensors.rear.pos
                } or nil
            }
        )

        sendUIState()

    -- ===== UI Command =====
    elseif channel == UI_CHANNEL and msg.type == "ui_cmd" then
        -- UI 命令直接转交自动驾驶
        modem.transmit(AUTO_CHANNEL, AUTO_CHANNEL, msg)

    -- ===== AUTO Command =====
    elseif channel == AUTO_CHANNEL and msg.type == "auto_cmd" then
        if msg.mode   then execState.mode = msg.mode end
        if msg.yaw    then setYaw(msg.yaw) end
        if msg.engine then setEngine(msg.engine) end
        if msg.brake  then applyBrake(msg.brake) end

        sendUIState()
    end

    ::continue::
end
