-- ================================
--  CC:VS Perception Layer (CALIBRATED)
-- ================================

local MODEM_PORT = 65520
local ROLE = "sensor"

-- modem（可选）
local modem = peripheral.find("modem")
if modem then
    modem.open(MODEM_PORT)
end

-- ================================
-- 检查 Ship API 是否存在
-- ================================

if type(ship) ~= "table" then
    error("no ship api found (computer is not bound to a VS ship)")
end

local ok = pcall(ship.getId)
if not ok then
    error("ship api exists but is not ready")
end

print("ship api ready, role =", ROLE)

-- ================================
-- 安全调用封装
-- ================================

local function safe(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

-- ================================
-- 船头方向解算（核心校准逻辑）
-- 船体局部坐标中：-X 为船头
-- ================================

local function getCalibratedHeading()
    if not ship.transformPositionToWorld then
        return nil
    end

    -- 船体局部原点
    local w0 = safe(function()
        return ship.transformPositionToWorld(0, 0, 0)
    end)

    -- 船体局部 -X 方向（你已确认这是船头）
    local wF = safe(function()
        return ship.transformPositionToWorld(-1, 0, 0)
    end)

    if not w0 or not wF then
        return nil
    end

    return {
        x = wF.x - w0.x,
        y = wF.y - w0.y,
        z = wF.z - w0.z
    }
end


-- ================================
-- 感知数据采集
-- ================================

local function collectShipState()
    local heading = getCalibratedHeading()

    return {
        -- ★ 身份字段（关键）
        role = ROLE,
        timestamp = os.clock(),

        -- 基本信息
        id       = safe(ship.getId),
        slug     = safe(ship.getSlug),
        mass     = safe(ship.getMass),
        isStatic = safe(ship.isStatic),

        -- 位置与速度（世界坐标）
        position = safe(ship.getWorldspacePosition),
        velocity = safe(ship.getVelocity),
        omega    = safe(ship.getAngularVelocity),

        -- 姿态（已校准船头）
        heading  = heading,

        -- 其他（保留，方便以后扩展）
        transform  = safe(ship.getTransformationMatrix),
        scale      = safe(ship.getScale),
        inertia    = safe(ship.getMomentOfInertiaTensor),
    }
end

-- ================================
-- 主循环
-- ================================

while true do
    local state = collectShipState()

    if modem then
        modem.transmit(MODEM_PORT, MODEM_PORT, state)
    end

    term.clear()
    term.setCursorPos(1, 1)
    print("=== SHIP PERCEPTION (CALIBRATED) ===")
    print("ROLE:", state.role)
    print("ID:", state.id)
    print("Mass:", state.mass)

    if state.position then
        print(string.format(
            "Pos: %.2f %.2f %.2f",
            state.position.x,
            state.position.y,
            state.position.z
        ))
    end

    if state.velocity then
        print(string.format(
            "Vel: %.2f %.2f %.2f",
            state.velocity.x,
            state.velocity.y,
            state.velocity.z
        ))
    end

    if state.heading then
        print(string.format(
            "Heading(FWD): %.3f %.3f %.3f",
            state.heading.x,
            state.heading.y,
            state.heading.z
        ))
    else
        print("Heading: N/A")
    end

    sleep(0)
end
-- =========================================
-- Auto Flight Controller (BRAIN ONLY)
-- =========================================

local modem = peripheral.find("modem") or error("No modem")

local AUTO_CHANNEL = 301
modem.open(AUTO_CHANNEL)

local sensor = nil
local target      = nil

local navState = "NAV_IDLE"
local steering = "stable"
local distance = nil

-- ---------- Debug ----------
local lastDebug = 0
local lastNavState = navState
local lastSteering = steering
local function debugLog(message)
    local now = os.clock()
    if now - lastDebug >= 1.5 then
        print(string.format("[Auto] %s", message))
        lastDebug = now
    end
end

local CRUISE_ENGINE = 2
local BRAKE_DIST    = 500
local STOP_DIST     = 5
local STOP_SPEED    = 0.5
local ALIGN_DOT     = 0.95
local TURN_DOT      = 0.98

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

local function alignmentDot(targetVec, heading)
    local hx, hz, hl = normalize(heading.x, heading.z)
    local tx, tz, tl = normalize(targetVec.x, targetVec.z)
    if hl == 0 or tl == 0 then return true end
    return hx * tx + hz * tz
end

local function steeringDecision(targetVec, heading)
    local dot = alignmentDot(targetVec, heading)
    if dot == true or dot >= TURN_DOT then
        return "stable"
    end

    local cross = heading.x * targetVec.z - heading.z * targetVec.x
    return cross > 0 and "left" or "right"
end

local function isAligned(targetVec, heading)
    local dot = alignmentDot(targetVec, heading)
    if dot == true then return true end
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
    debugLog("reset to NAV_IDLE")
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
        local yaw = steering ~= "stable" and steering or "stable"
        sendAutoCmd({ mode = navState, yaw = yaw, engine = 0 })
        if steering == "stable" then
            navState = "NAV_CRUISING"
        end

    elseif navState == "NAV_CRUISING" then
        local yaw = steering ~= "stable" and steering or "stable"
        sendAutoCmd({ mode = navState, yaw = yaw, engine = CRUISE_ENGINE })
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

    if navState ~= lastNavState or steering ~= lastSteering then
        debugLog(string.format(
            "state=%s steering=%s dist=%s",
            navState,
            steering,
            distance and string.format("%.1f", distance) or "-"
        ))
        lastNavState = navState
        lastSteering = steering
    end
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

