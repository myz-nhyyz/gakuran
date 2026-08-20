-- Auto SCHOOL NEWSPAPER Farmer v24 — FPS Optimized
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:WaitForChild("Humanoid")

local running = false
local jobAccepted = false
local cameraOpened = false
local phoneOpen = false
local trackConnection = nil
local currentTrackTarget = nil

local lastHealth = Humanoid.Health
local combatCooldownUntil = 0
local underAttack = false

local FRAME_RADIUS_RATIO = 0.32
local statusLabels = {}
local logLabel = nil
local logBuffer = {}
local maxLogs = 8

local function logStatus(msg)
    table.insert(logBuffer, os.date("%H:%M:%S") .. " > " .. msg)
    if #logBuffer > maxLogs then table.remove(logBuffer, 1) end
    if logLabel then logLabel.Text = table.concat(logBuffer, "\n") end
    print("[NEWSPAPER] " .. msg)
end

-- ============================================
-- UNIFIED GUI SCAN — 1 pass duy nhất cho assignment + phone, throttle 0.2s
-- ============================================
local guiCache = {
    assignmentName = nil,
    phoneFrame = nil,
    phoneOpen = false,
    lastScan = 0
}
local GUI_SCAN_THROTTLE = 0.2

local function scanGui(force)
    if not force and tick() - guiCache.lastScan < GUI_SCAN_THROTTLE then return end
    guiCache.lastScan = tick()

    local assignmentName = nil
    local phoneFrame = guiCache.phoneFrame
    local phoneValid = phoneFrame and phoneFrame.Parent

    for _, obj in pairs(Player.PlayerGui:GetDescendants()) do
        if not assignmentName and obj:IsA("TextLabel") and obj.Text and obj.Text ~= "" then
            local name = obj.Text:match("[Gg]et a photo of%s+([^%.\n]+)")
            if name then assignmentName = name:gsub("%s+$",""):gsub("^%s+","") end
        end

        -- chỉ quét tìm phoneFrame khi cache cũ đã mất (không quét lồng mỗi vòng)
        if not phoneValid and (obj:IsA("Frame") or obj:IsA("ScreenGui") or obj:IsA("ImageLabel")) then
            local hits = 0
            for _, c in ipairs(obj:GetChildren()) do
                if (c:IsA("TextButton") or c:IsA("TextLabel")) and c.Text then
                    local t = c.Text:upper()
                    if t == "INDEED" or t == "CONTACTS" or t == "MENU"
                       or t == "CAMERA" or t == "DIAL" or t == "MY PHONE" then
                        hits = hits + 1
                    end
                end
            end
            if hits >= 2 then phoneFrame = obj; phoneValid = true end
        end
    end

    guiCache.assignmentName = assignmentName
    guiCache.phoneFrame = phoneFrame
    if phoneFrame and phoneFrame.Parent then
        guiCache.phoneOpen = phoneFrame:IsA("ScreenGui") and phoneFrame.Enabled or phoneFrame.Visible
    else
        guiCache.phoneOpen = false
    end
end

local function getAssignmentTargetName()
    scanGui()
    return guiCache.assignmentName
end

local function isJobActive()
    return getAssignmentTargetName() ~= nil
end

local function isPhoneOpenReal()
    scanGui()
    return guiCache.phoneOpen
end

local function pressKeyRaw(code, downDelay, afterDelay)
    downDelay = downDelay or 0.12
    afterDelay = afterDelay or 0.3
    VirtualInputManager:SendKeyEvent(true, code, false, nil)
    task.wait(downDelay)
    VirtualInputManager:SendKeyEvent(false, code, false, nil)
    task.wait(afterDelay)
end

-- ============================================
-- PHONE OPEN — M để mở, LeftAlt x2 để reset về home nếu đang mở dở
-- ============================================
local function openPhoneToHomeState()
    for attempt = 1, 3 do
        if not running then return false end
        local isOpen = isPhoneOpenReal()

        if not isOpen then
            logStatus("Phone CLOSED -> bấm M mở (lần " .. attempt .. "/3)...")
            pressKeyRaw(Enum.KeyCode.M, 0.12, 0.5)
        else
            logStatus("Phone đang OPEN (trạng thái không rõ) -> reset LeftAlt x2 (lần " .. attempt .. "/3)...")
            pressKeyRaw(Enum.KeyCode.LeftAlt, 0.12, 0.35)
            if not running then return false end
            pressKeyRaw(Enum.KeyCode.LeftAlt, 0.12, 0.5)
        end

        if not running then return false end
        scanGui(true)
        if guiCache.phoneOpen then
            phoneOpen = true
            logStatus("✓ Điện thoại ở trạng thái HOME, sẵn sàng navigate.")
            return true
        end
    end

    phoneOpen = false
    logStatus("⚠ Không đưa điện thoại về trạng thái home được sau 3 lần.")
    return false
end

local function ensurePhoneClosed()
    scanGui(true)
    if guiCache.phoneOpen then
        pressKeyRaw(Enum.KeyCode.LeftAlt, 0.12, 0.15)
        scanGui(true)
    end
    phoneOpen = false
end

-- ============================================
-- Input helpers
-- ============================================
local function rawKeyPress(code, delay)
    delay = delay or 0.4
    VirtualInputManager:SendKeyEvent(true, code, false, nil)
    task.wait(delay)
    VirtualInputManager:SendKeyEvent(false, code, false, nil)
    task.wait(delay)
end

local function key(code, delay)
    if not running then return end
    rawKeyPress(code, delay)
end

local function waitCheck(t)
    local elapsed = 0
    local step = 0.05
    while elapsed < t do
        if not running then return false end
        if tick() < combatCooldownUntil then return false end
        task.wait(step)
        elapsed = elapsed + step
    end
    return true
end

-- ============================================
-- Combat Safety
-- ============================================
local function forceClosePhone()
    ensurePhoneClosed()
    cameraOpened = false
    logStatus("⚠ Bị tấn công! Đóng điện thoại khẩn cấp.")
    underAttack = true
    combatCooldownUntil = tick() + 5
    task.delay(5, function()
        if tick() >= combatCooldownUntil - 0.1 then underAttack = false end
    end)
end

Humanoid.HealthChanged:Connect(function(newHealth)
    if running and not underAttack and newHealth < lastHealth - 0.5 then
        forceClosePhone()
    end
    lastHealth = newHealth
end)

Player.CharacterAdded:Connect(function(newChar)
    Character = newChar
    HumanoidRootPart = newChar:WaitForChild("HumanoidRootPart")
    Humanoid = newChar:WaitForChild("Humanoid")
    lastHealth = Humanoid.Health
    Humanoid.HealthChanged:Connect(function(h)
        if running and not underAttack and h < lastHealth - 0.5 then
            forceClosePhone()
        end
        lastHealth = h
    end)
end)

-- ============================================
-- Reticle Drawing
-- ============================================
local reticleCircle, reticleLine, reticleDot = nil, nil, nil

local function initReticle()
    pcall(function()
        reticleCircle = Drawing.new("Circle")
        reticleCircle.Filled = false; reticleCircle.Color = Color3.fromRGB(255,40,40)
        reticleCircle.Thickness = 3; reticleCircle.NumSides = 40; reticleCircle.Visible = false
        reticleLine = Drawing.new("Line")
        reticleLine.Color = Color3.fromRGB(255,220,40); reticleLine.Thickness = 2; reticleLine.Visible = false
        reticleDot = Drawing.new("Circle")
        reticleDot.Radius = 6; reticleDot.Filled = true; reticleDot.Color = Color3.fromRGB(255,220,40); reticleDot.Visible = false
    end)
end

local function stopVisualOnly()
    if reticleCircle then reticleCircle.Visible = false end
    if reticleLine then reticleLine.Visible = false end
    if reticleDot then reticleDot.Visible = false end
end

-- ============================================
-- ESP — CÓ CACHE, throttle 0.3s để tránh quét workspace liên tục
-- ============================================
local espCache = { result = nil, lastScan = 0 }
local ESP_SCAN_THROTTLE = 0.3

local function findQuestMarker()
    if espCache.result and tick() - espCache.lastScan < ESP_SCAN_THROTTLE then
        local r = espCache.result
        if r.part and r.part.Parent then
            local rp = Character:FindFirstChild("HumanoidRootPart")
            if rp then
                r.pos = r.part.Position
                r.dist = (rp.Position - r.part.Position).Magnitude
            end
            return r
        end
    end

    espCache.lastScan = tick()
    local rootPart = Character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end

    local candidates = {}
    local roots = {workspace, Player.PlayerGui}
    for _, root in ipairs(roots) do
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("BillboardGui") then
                local hasDist = false
                local nm = nil
                for _, child in ipairs(obj:GetChildren()) do
                    if child:IsA("TextLabel") and child.Text and child.Text ~= "" then
                        local t = child.Text:lower()
                        if t:find("studs away") or t:find("m away") or t:match("%d+%s*away") then
                            hasDist = true
                        elseif not nm then
                            nm = child.Text
                        end
                    end
                end
                if hasDist then
                    local ad = obj.Adornee
                    local part = nil
                    if ad and ad:IsA("BasePart") then part = ad
                    elseif obj.Parent and obj.Parent:IsA("BasePart") then part = obj.Parent
                    elseif obj.Parent and obj.Parent:IsA("Model") then
                        part = obj.Parent:FindFirstChild("HumanoidRootPart")
                            or obj.Parent.PrimaryPart
                            or obj.Parent:FindFirstChildWhichIsA("BasePart")
                    end
                    if part then
                        candidates[#candidates+1] = {part=part, name=nm or part.Name}
                    end
                end
            end
        end
    end

    if #candidates == 0 then espCache.result = nil; return nil end

    local result
    local an = (guiCache.assignmentName or ""):lower()
    if #an > 0 then
        for _, c in ipairs(candidates) do
            local cn = (c.name or ""):lower()
            if cn == an or cn:find(an,1,true) or an:find(cn,1,true) then
                if c.part and c.part.Parent then
                    result = {pos=c.part.Position, part=c.part, name=c.name, dist=(rootPart.Position-c.part.Position).Magnitude}
                    break
                end
            end
        end
    end

    if not result then
        local bd = math.huge
        for _, c in ipairs(candidates) do
            if c.part and c.part.Parent then
                local d = (rootPart.Position-c.part.Position).Magnitude
                if d < bd then bd=d; result={pos=c.part.Position, part=c.part, name=c.name, dist=d} end
            end
        end
    end

    espCache.result = result
    return result
end

-- ============================================
-- TRACKING — gộp facing + camera bypass + reticle vào 1 RenderStepped
-- (trước đây là 2 connection riêng, giờ chỉ 1, giảm nửa overhead/frame)
-- ============================================
local MAX_LOCK_DIST_MULT = 1.5

local function stopTracking()
    if trackConnection then trackConnection:Disconnect(); trackConnection = nil end
    currentTrackTarget = nil
    stopVisualOnly()
end

local function startTracking(target)
    stopTracking()
    currentTrackTarget = target

    local vw, vh = Camera.ViewportSize.X, Camera.ViewportSize.Y
    local center = Vector2.new(vw / 2, vh / 2)
    if reticleCircle then
        reticleCircle.Radius = FRAME_RADIUS_RATIO * vw
        reticleCircle.Position = center
        reticleCircle.Visible = true
    end

    trackConnection = RunService.RenderStepped:Connect(function()
        if not running or underAttack then return end
        if not currentTrackTarget or not currentTrackTarget.part or not currentTrackTarget.part.Parent then
            stopTracking()
            return
        end

        local char = Player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local targetPos = currentTrackTarget.part.Position

        local dist = (targetPos - root.Position).Magnitude
        if dist > 60 * MAX_LOCK_DIST_MULT then
            stopTracking()
            return
        end

        -- aim: xoay thẳng về target, bypass hoàn toàn — không nội suy
        local lookAt = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
        root.CFrame = CFrame.new(root.Position, lookAt)

        -- camera bypass
        local focusPos = (targetPos + root.Position) / 2 + Vector3.new(0, 2, 0)
        Camera.CFrame = CFrame.new(Camera.CFrame.Position, focusPos)

        -- reticle — tái sử dụng cùng 1 lần WorldToViewportPoint, không tính lại
        if reticleCircle then
            local vw2, vh2 = Camera.ViewportSize.X, Camera.ViewportSize.Y
            local cen2 = Vector2.new(vw2/2, vh2/2)
            reticleCircle.Radius = FRAME_RADIUS_RATIO * vw2
            reticleCircle.Position = cen2

            local sp, onScreen = Camera:WorldToViewportPoint(targetPos)
            if onScreen then
                reticleLine.From = cen2
                reticleLine.To = Vector2.new(sp.X, sp.Y)
                reticleLine.Visible = true
                reticleDot.Position = Vector2.new(sp.X, sp.Y)
                reticleDot.Visible = true
                local dx, dy = (sp.X-cen2.X)/vw2, (sp.Y-cen2.Y)/vh2
                local locked = math.sqrt(dx*dx+dy*dy) <= FRAME_RADIUS_RATIO
                local c = locked and Color3.fromRGB(60,255,90) or Color3.fromRGB(255,40,40)
                reticleCircle.Color = c
                reticleLine.Color = locked and Color3.fromRGB(60,255,90) or Color3.fromRGB(255,220,40)
                reticleDot.Color = reticleLine.Color
            else
                reticleLine.Visible = false
                reticleDot.Visible = false
                reticleCircle.Color = Color3.fromRGB(255,40,40)
            end
        end
    end)
end

local function isLocked(target)
    if not target.part or not target.part.Parent then return false end
    local sp, onScreen = Camera:WorldToViewportPoint(target.part.Position)
    if not onScreen then return false end
    local vw, vh = Camera.ViewportSize.X, Camera.ViewportSize.Y
    return math.sqrt(((sp.X-vw/2)/vw)^2 + ((sp.Y-vh/2)/vh)^2) <= FRAME_RADIUS_RATIO
end

local function waitForLock(target, ms)
    ms = ms or 0.3
    local dl = tick() + ms
    while running and not underAttack do
        if not target.part or not target.part.Parent then return false end
        if isLocked(target) then return true end
        if tick() > dl then return true end
        task.wait(0.03)
    end
    return running and not underAttack
end

-- ============================================
-- TELEPORT — có xác nhận vị trí thật
-- ============================================
local function teleportNearTarget(target, standDistance)
    standDistance = standDistance or 5
    local char = Player.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    if not target.part or not target.part.Parent then return false end

    local targetPos = target.part.Position

    local diffX = root.Position.X - targetPos.X
    local diffZ = root.Position.Z - targetPos.Z
    local currentDir = Vector3.new(diffX, 0, diffZ)

    if currentDir.Magnitude < 0.1 then
        currentDir = Vector3.new(1, 0, 0)
    end
    currentDir = currentDir.Unit

    local landPos = targetPos + (currentDir * standDistance)
    local destination = Vector3.new(landPos.X, targetPos.Y + 3, landPos.Z)
    root.CFrame = CFrame.new(destination)

    local confirmDeadline = tick() + 3
    local confirmed = false
    while running and tick() < confirmDeadline do
        local curChar = Player.Character
        local curRoot = curChar and curChar:FindFirstChild("HumanoidRootPart")
        if curRoot and (curRoot.Position - destination).Magnitude <= 4 then
            confirmed = true
            break
        end
        if tick() < combatCooldownUntil then return false end
        task.wait(0.05)
    end

    if not confirmed then
        logStatus("⚠ Dịch chuyển chưa xác nhận (lag?), bỏ qua vòng này.")
        return false
    end

    logStatus("✓ Dịch chuyển thành công: " .. target.name)
    return true
end

-- ============================================
-- Chấp nhận job
-- ============================================
local function acceptJob()
    if not running then return end

    if isJobActive() then
        jobAccepted = true
        logStatus("✓ Job đã active sẵn: " .. tostring(getAssignmentTargetName()))
        return
    end

    logStatus("Đưa điện thoại về trạng thái home...")
    if not openPhoneToHomeState() then return end
    if not running then return end

    logStatus("Bước: Enter vào menu...")
    key(Enum.KeyCode.Return, 0.5)
    if not running then return end

    logStatus("Bước: Navigate → ↓↓↓ (tới INDEED)...")
    key(Enum.KeyCode.Right, 0.4)
    if not running then return end
    key(Enum.KeyCode.Down, 0.4)
    if not running then return end
    key(Enum.KeyCode.Down, 0.4)
    if not running then return end
    key(Enum.KeyCode.Down, 0.4)
    if not running or not waitCheck(0.3) then return end

    logStatus("Bước: Enter mở INDEED...")
    key(Enum.KeyCode.Return, 0.7)
    if not running then return end

    logStatus("Bước: đợi 0.5s -> Enter chọn job...")
    if not waitCheck(0.5) then return end
    key(Enum.KeyCode.Return, 0.6)
    if not running then return end

    logStatus("Bước: đợi 0.2s -> Enter APPLY NOW...")
    if not waitCheck(0.2) then return end
    key(Enum.KeyCode.Return, 0.6)
    if not running then return end

    local deadline = tick() + 4
    while running and tick() < deadline do
        if isJobActive() then
            jobAccepted = true
            logStatus("✓ JOB ĐÃ NHẬN THẬT (assignment: " .. tostring(getAssignmentTargetName()) .. ")")
            return
        end
        task.wait(0.2)
    end

    logStatus("Chưa thấy assignment, Enter xác nhận thêm...")
    key(Enum.KeyCode.Return, 0.6)
    if not running then return end

    deadline = tick() + 3
    while running and tick() < deadline do
        if isJobActive() then
            jobAccepted = true
            logStatus("✓ JOB ĐÃ NHẬN THẬT (sau xác nhận thêm).")
            return
        end
        task.wait(0.2)
    end

    jobAccepted = false
    logStatus("⚠ Vẫn chưa nhận được job. Thử lại vòng sau.")
end

-- ============================================
-- Chu kỳ chính
-- ============================================
local function doTargetCycle()
    if not running or underAttack then return false end

    local target = findQuestMarker()
    if not target then return false end

    startTracking(target)

    local tpOk = teleportNearTarget(target, 5)
    if not tpOk or not running then stopTracking(); return false end

    if not waitCheck(2.0) then stopTracking(); return false end

    if not openPhoneToHomeState() then
        stopTracking()
        return false
    end

    key(Enum.KeyCode.Down, 0.3)
    if not running then return false end
    key(Enum.KeyCode.Down, 0.3)
    if not running then return false end
    key(Enum.KeyCode.Down, 0.3)
    if not running then return false end

    key(Enum.KeyCode.Return, 0.5)
    if not running then return false end
    cameraOpened = true

    waitForLock(target, 0.3)
    if not running or underAttack then return false end

    logStatus("📸 Chụp: " .. target.name .. " (" .. string.format("%.1f", target.dist) .. " studs)")
    key(Enum.KeyCode.Return, 0.3)
    if not running then return false end

    if not waitCheck(1.0) then return false end

    key(Enum.KeyCode.Backspace, 0.3)
    if not running then return false end

    stopTracking()
    cameraOpened = false

    return true
end

-- ============================================
-- MAIN LOOP
-- ============================================
local function mainLoop()
    initReticle()

    local attempts = 0
    while running and not jobAccepted and attempts < 3 do
        attempts = attempts + 1
        local ok, err = pcall(acceptJob)
        if not ok then
            logStatus("⚠ Lỗi acceptJob: " .. tostring(err))
        end
        if not jobAccepted then
            waitCheck(1.0)
        end
    end

    while running do
        jobAccepted = isJobActive()

        if not jobAccepted then
            logStatus("Job không active, thử nhận lại...")
            local ok, err = pcall(acceptJob)
            if not ok then logStatus("⚠ Lỗi acceptJob: " .. tostring(err)) end
            waitCheck(1.0)
        elseif underAttack or tick() < combatCooldownUntil then
            waitCheck(0.5)
        else
            local ok, result = pcall(doTargetCycle)
            if not ok then
                logStatus("⚠ Lỗi cycle: " .. tostring(result))
                waitCheck(1.0)
            elseif not running then
                break
            elseif not result then
                waitCheck(1.0)
            end
        end
    end

    stopTracking()
    cameraOpened = false
    logStatus("Đã dừng.")
end

-- ============================================
-- UI
-- ============================================
local function buildUI()
    local sg = Instance.new("ScreenGui")
    sg.Name = "NewspaperUI"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 999
    sg.Parent = Player:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 240, 0, 290)
    frame.Position = UDim2.new(0, 10, 0, 10)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Visible = true
    frame.Parent = sg
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,0,0,26)
    title.BackgroundTransparency = 1
    title.Text = "NEWSPAPER FARMER"
    title.TextColor3 = Color3.fromRGB(255,180,50)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.Parent = frame

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,-20,0,28)
    btn.Position = UDim2.new(0,10,0,30)
    btn.Text = "START"
    btn.BackgroundColor3 = Color3.fromRGB(50,170,70)
    btn.TextColor3 = Color3.new(1,1,1)
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.Parent = frame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,5)

    local statY = 66
    local fields = {"phone","job","combat","camera","target"}
    local defaults = {
        phone = "Phone: --", job = "Job: NOT ACCEPTED",
        combat = "Combat: SAFE", camera = "Camera: CLOSED", target = "Target: --"
    }
    for _, f in ipairs(fields) do
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1,-18,0,18)
        lbl.Position = UDim2.new(0,9,0,statY)
        lbl.BackgroundTransparency = 1
        lbl.Text = defaults[f]
        lbl.TextColor3 = Color3.fromRGB(200,200,200)
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = frame
        statusLabels[f] = lbl
        statY = statY + 19
    end

    logLabel = Instance.new("TextLabel")
    logLabel.Size = UDim2.new(1,-14,0,72)
    logLabel.Position = UDim2.new(0,7,0,162)
    logLabel.BackgroundColor3 = Color3.fromRGB(12,12,18)
    logLabel.BorderSizePixel = 0
    logLabel.Text = ""
    logLabel.TextColor3 = Color3.fromRGB(200,255,150)
    logLabel.TextSize = 9
    logLabel.Font = Enum.Font.Gotham
    logLabel.TextWrapped = true
    logLabel.TextXAlignment = Enum.TextXAlignment.Left
    logLabel.TextYAlignment = Enum.TextYAlignment.Top
    logLabel.Parent = frame
    Instance.new("UICorner", logLabel).CornerRadius = UDim.new(0,5)

    btn.MouseButton1Click:Connect(function()
        running = not running
        if running then
            btn.Text = "STOP"
            btn.BackgroundColor3 = Color3.fromRGB(200,50,50)
            task.spawn(mainLoop)
        else
            btn.Text = "START"
            btn.BackgroundColor3 = Color3.fromRGB(50,170,70)
            stopTracking()
            ensurePhoneClosed()
            cameraOpened = false
        end
    end)

    UserInputService.InputBegan:Connect(function(i, gp)
        if gp then return end
        if i.KeyCode == Enum.KeyCode.K then
            frame.Visible = not frame.Visible
        end
    end)

    -- status poll: KHÔNG force-invalidate cache nữa, chỉ đọc giá trị đã cache sẵn
    task.spawn(function()
        while true do
            task.wait(0.5)
            scanGui()

            if statusLabels.phone then
                statusLabels.phone.Text = "Phone: " .. (guiCache.phoneOpen and "OPEN" or "CLOSED")
                statusLabels.phone.TextColor3 = guiCache.phoneOpen and Color3.fromRGB(80,220,120) or Color3.fromRGB(200,200,200)
            end
            if statusLabels.job then
                local active = guiCache.assignmentName ~= nil
                statusLabels.job.Text = "Job: " .. (active and "ACCEPTED" or "NOT ACCEPTED")
                statusLabels.job.TextColor3 = active and Color3.fromRGB(80,220,120) or Color3.fromRGB(255,150,80)
            end
            if statusLabels.combat then
                statusLabels.combat.Text = "Combat: " .. (underAttack and "⚠ DANGER" or "SAFE")
                statusLabels.combat.TextColor3 = underAttack and Color3.fromRGB(255,60,60) or Color3.fromRGB(80,220,120)
            end
            if statusLabels.camera then
                statusLabels.camera.Text = "Camera: " .. (cameraOpened and "OPEN" or "CLOSED")
                statusLabels.camera.TextColor3 = cameraOpened and Color3.fromRGB(80,220,120) or Color3.fromRGB(200,200,200)
            end
            if statusLabels.target then
                statusLabels.target.Text = "Target: " .. (guiCache.assignmentName or "--")
            end
        end
    end)
end

buildUI()
logStatus("Script loaded v24 — FPS optimized (cached scans, merged RenderStepped).")
