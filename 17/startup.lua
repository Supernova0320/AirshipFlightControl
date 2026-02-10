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