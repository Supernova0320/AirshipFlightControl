-- =========================================
-- Auto Flight Controller (BRAIN ONLY)
-- =========================================

local modem = peripheral.find("modem") or error("No modem")

local AUTO_CHANNEL = 301
modem.open(AUTO_CHANNEL)

local sensor = nil
local target = nil

local navState = "NAV_IDLE"
local steering = "stable"
local distance = nil

local CRUISE_ENGINE = 2
local BRAKE_DIST    = 500
local STOP_DIST     = 5
local STOP_SPEED    = 0.5
local ALIGN_DOT     = 0.95

-- ---------- Math ----------
local function len2(x, z)
    return math.sqrt(x * x + z * z)
end

local function normalize(x, z)
    local l = len2(x, z)
    if l == 0 then return 0, 0, 0 end
    return x / l, z / l, l
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function headingVector()
    if sensor and sensor.heading then
        return { x = sensor.heading.x, z = sensor.heading.z }
    end

    if sensor and sensor.vel then
        return { x = sensor.vel.x, z = sensor.vel.z }
    end

    return nil
end

local function steeringDecision(targetVec, heading)
    local cross = heading.x * targetVec.z - heading.z * targetVec.x
    if math.abs(cross) < 0.1 then
        return "stable"
    end
    return cross > 0 and "left" or "right"
end

local function isAligned(targetVec, heading)
    local hx, hz, hl = normalize(heading.x, heading.z)
    local tx, tz, tl = normalize(targetVec.x, targetVec.z)
    if hl == 0 or tl == 0 then return true end
    local dot = hx * tx + hz * tz
    return dot >= ALIGN_DOT
end

-- ---------- Messaging ----------
local function sendAutoCmd(cmd)
    cmd.type = "auto_cmd"
    modem.transmit(AUTO_CHANNEL, AUTO_CHANNEL, cmd)
end

local function sendAutoState()
    modem.transmit(
        AUTO_CHANNEL,
        AUTO_CHANNEL,
        {
            type = "auto_state",
            nav_state = navState,
            steering = steering,
            distance = distance,
            target = target
        }
    )
end

local function resetToIdle()
    navState = "NAV_IDLE"
    steering = "stable"
    distance = nil
    sendAutoCmd({ mode = navState, yaw = "stable", engine = 0, brake = nil })
    sendAutoState()
end

local function processNavigation()
    if not target or not sensor or not sensor.pos then
        resetToIdle()
        return
    end

    local dx = target.x - sensor.pos.x
    local dz = target.z - sensor.pos.z
    distance = len2(dx, dz)

    local heading = headingVector()
    if not heading then
        resetToIdle()
        return
    end

    local targetVec = { x = dx, z = dz }
    steering = steeringDecision(targetVec, heading)

    if navState == "NAV_IDLE" then
        navState = "NAV_TURNING"
    end

    if navState == "NAV_TURNING" then
        sendAutoCmd({ mode = navState, yaw = steering, engine = 0 })
        if isAligned(targetVec, heading) then
            navState = "NAV_CRUISING"
        end

    elseif navState == "NAV_CRUISING" then
        sendAutoCmd({ mode = navState, yaw = steering, engine = CRUISE_ENGINE })
        if distance and distance <= BRAKE_DIST then
            navState = "NAV_BRAKING"
        end

    elseif navState == "NAV_BRAKING" then
        local brake = nil
        if sensor.vel then
            local vx = sensor.vel.x
            local vz = sensor.vel.z
            local speed = len2(vx, vz)
            local dirX, dirZ = 0, 0
            if speed > 0 then
                dirX, dirZ = -vx / speed, -vz / speed
            end
            local power = clamp(speed * speed / (2 * math.max(distance, 1)), 0, 50)
            brake = { dir = { x = dirX, z = dirZ }, power = power }
            if distance <= STOP_DIST and speed <= STOP_SPEED then
                target = nil
                resetToIdle()
                return
            end
        end

        sendAutoCmd({ mode = navState, yaw = steering, engine = 0, brake = brake })
    end

    sendAutoState()
end

print("=================================")
print("Auto Flight ONLINE")
print("=================================")

while true do
    local _, _, ch, _, msg = os.pullEvent("modem_message")
    if ch ~= AUTO_CHANNEL or type(msg) ~= "table" then goto continue end

    if msg.type == "sensor_update" then
        sensor = msg.sensor or sensor
        if msg.target ~= nil then
            target = msg.target
        end
        processNavigation()

    elseif msg.type == "nav_target" then
        target = msg.target
        if not target then
            resetToIdle()
        else
            navState = "NAV_TURNING"
            processNavigation()
        end
    end

    ::continue::
end
