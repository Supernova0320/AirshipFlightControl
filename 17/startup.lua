-- ================================
--  CC:VS Perception Layer
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
-- 感知数据采集
-- ================================

local function collectShipState()
    local quaternion = safe(ship.getQuaternion)
    local heading = nil
    if quaternion and quaternion.x and quaternion.y and quaternion.z and quaternion.w then
        local x = quaternion.x
        local y = quaternion.y
        local z = quaternion.z
        local w = quaternion.w
        heading = {
            x = 2 * (x * z + w * y),
            y = 2 * (y * z - w * x),
            z = 1 - 2 * (x * x + y * y)
        }
    end

    return {
        -- ★ 身份字段（关键）
        role = ROLE,

        timestamp = os.clock(),

        -- 基本信息
        id       = safe(ship.getId),
        slug     = safe(ship.getSlug),
        mass     = safe(ship.getMass),
        isStatic = safe(ship.isStatic),

        -- 位置与速度
        position = safe(ship.getWorldspacePosition),
        velocity = safe(ship.getVelocity),
        omega    = safe(ship.getAngularVelocity),

        -- 姿态
        quaternion = quaternion,
        transform  = safe(ship.getTransformationMatrix),
        heading    = heading,

        -- 物理属性
        scale   = safe(ship.getScale),
        inertia = safe(ship.getMomentOfInertiaTensor),
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
    print("=== SHIP PERCEPTION ===")
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
            "Heading: %.2f %.2f %.2f",
            state.heading.x,
            state.heading.y,
            state.heading.z
        ))
    end

    sleep(0)
end
