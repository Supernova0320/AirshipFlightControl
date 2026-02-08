-- ===============================
-- Main Engine Backend Controller
-- Stable Version (Target-based)
-- ===============================

-- ---- Peripheral Initialization ----
local modem = peripheral.find("modem") or error("No modem attached", 0)

local mainEngines = {
    peripheral.wrap("left"),
    peripheral.wrap("right"),
    peripheral.wrap("back")
}

-- ---- Constants ----
local COMMAND_CHANNEL = 15

local THROTTLE_RPM = {
    [0] = 0,
    [1] = 50,
    [2] = 100,
    [3] = 150,
    [4] = 200
}

-- ---- State ----
local currentTargetRPM = nil

-- ---- Utility ----
local function setMainEngineRPM(rpm)
    for _, motor in ipairs(mainEngines) do
        motor.setSpeed(rpm)
    end
end

-- ---- Modem Setup ----
modem.open(COMMAND_CHANNEL)
print("Main Engine Backend Online")
print("Listening on channel:", COMMAND_CHANNEL)

-- ---- Main Loop ----
while true do
    local _, _, channel, _, message = os.pullEvent("modem_message")

    if channel == COMMAND_CHANNEL
       and type(message) == "table"
       and message.type == "main_engine_throttle" then

        local level = message.level or 0
        local rpm = THROTTLE_RPM[level]

        if rpm ~= nil and rpm ~= currentTargetRPM then
            currentTargetRPM = rpm
            setMainEngineRPM(rpm)
            print("Throttle:", level, "Target RPM:", rpm)
        end
    end
end
