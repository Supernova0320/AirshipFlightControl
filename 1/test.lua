-- 包装外设
local motor = peripheral.wrap("right")
local modem = peripheral.find("modem")

local CHANNEL = 100
modem.open(CHANNEL)

print("Motor server online")

while true do
    local _, _, _, _, message = os.pullEvent("modem_message")

    -- 约定：message 就是 rpm 数值
    if type(message) == "number" then
        -- 安全限制
        if message > 256 then message = 256 end
        if message < -256 then message = -256 end

        if motor.getSpeed() ~= message then
            motor.setSpeed(message)
            print("Set RPM:", message)
        end
    end
end