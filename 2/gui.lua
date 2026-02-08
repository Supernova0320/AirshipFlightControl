local modem = peripheral.find("modem")
local CHANNEL = 100
modem.open(CHANNEL)

local rpm = 0

print("W/S 调速 | 空格 停止")

while true do
    local _, key = os.pullEvent("key")

    if key == keys.w then
        rpm = rpm + 16
    elseif key == keys.s then
        rpm = rpm - 16
    elseif key == keys.space then
        rpm = 0
    end

    -- 限制范围
    if rpm > 256 then rpm = 256 end
    if rpm < -256 then rpm = -256 end

    modem.transmit(CHANNEL, CHANNEL, rpm)
    print("Send RPM:", rpm)
end