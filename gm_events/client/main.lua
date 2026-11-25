-- Presentation only. The server decides who sees what and when.
local cam = nil
local shot = 0

local function release()
    shot = shot + 1
    if cam then
        local old = cam
        cam = nil
        Open77.camera.deactivate({ blendMs = 400 })
        SetTimeout(500, function() Open77.camera.destroy(old) end)
    end
    Open77.hud.setCinematic(false)
end

RegisterNetEvent("gm_events:cinematic", function(x, y, z, heading, seconds)
    if cam then return end -- a shot is already running
    shot = shot + 1
    local mine = shot
    local a = math.rad(heading)
    -- Behind the mark from the staff member's side, raised, looking at it.
    local id, createReason = Open77.camera.create({
        position = vector3(x + math.sin(a) * 28, y - math.cos(a) * 28, z + 9),
        lookAt = vector3(x, y, z + 4),
        fov = 60,
    })
    if not id then
        print("[gm] no camera: " .. tostring(createReason))
        return
    end
    local ok, reason = Open77.camera.activate(id, { blendMs = 600 })
    if not ok then
        print("[gm] no camera: " .. tostring(reason))
        Open77.camera.destroy(id)
        return
    end
    cam = id
    Open77.hud.setCinematic(true, 0.12)
    SetTimeout(math.floor(seconds * 1000), function()
        if shot == mine then release() end
    end)
end)

RegisterNetEvent("gm_events:shake", function()
    if cam then Open77.camera.shake(cam, "explosion", 2.0, 1200) end
end)

RegisterNetEvent("gm_events:release", function() release() end)
