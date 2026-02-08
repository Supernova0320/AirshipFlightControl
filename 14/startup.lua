-- =========================================
-- Auto Flight Controller (BRAIN ONLY)
-- =========================================

local modem = peripheral.find("modem") or error("No modem")

local PERCEPTION_CHANNEL = 65520
local UI_CHANNEL         = 121
local AUTO_CHANNEL       = 301

modem.open(PERCEPTION_CHANNEL)
modem.open(UI_CHANNEL)

local shipState = nil
local target    = nil
local mode      = "IDLE"

local CRUISE_ENGINE = 2
local BRAKE_DIST    = 500
local STOP_DIST     = 100

-- ---------- Math ----------
local function len(x,z) return math.sqrt(x*x+z*z) end

local function yawDecision()
    local dx = target.x - shipState.position.x
    local dz = target.z - shipState.position.z
    local fx = shipState.velocity.x
    local fz = shipState.velocity.z

    local cross = fx * dz - fz * dx
    if math.abs(cross) < 0.1 then return "stable" end
    return cross > 0 and "left" or "right"
end

local function send(cmd)
    cmd.type = "auto_cmd"
    modem.transmit(AUTO_CHANNEL, AUTO_CHANNEL, cmd)
end

print("=================================")
print("Auto Flight ONLINE")
print("=================================")

while true do
    local _, _, ch, _, msg = os.pullEvent("modem_message")
    if type(msg) ~= "table" then goto continue end

    if ch == UI_CHANNEL and msg.type == "target" then
        target = msg.x and {x=msg.x,z=msg.z} or nil
        mode = target and "TURNING" or "IDLE"
        print("[AUTO] target set", target and "YES" or "CLEARED")

    elseif ch == PERCEPTION_CHANNEL and msg.position and msg.velocity then
        shipState = msg
        if not target then goto continue end

        local dist = len(
            target.x - shipState.position.x,
            target.z - shipState.position.z
        )

        if mode == "TURNING" then
            local yaw = yawDecision()
            print("[TURNING] yaw =", yaw)
            send({ mode=mode, yaw=yaw, engine=0 })
            if yaw == "stable" then
                mode = "CRUISE"
            end

        elseif mode == "CRUISE" then
            print("[CRUISE] engine =", CRUISE_ENGINE)
            send({ mode=mode, yaw="stable", engine=CRUISE_ENGINE })
            if dist < BRAKE_DIST then
                mode = "BRAKING"
            end

        elseif mode == "BRAKING" then
            print("[BRAKING]")
            send({ mode=mode, engine=0 })
            if dist < STOP_DIST then
                mode = "IDLE"
                target = nil
                send({ mode="IDLE", engine=0, yaw="stable" })
            end
        end
    end

    ::continue::
end
