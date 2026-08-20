-- Auto SCHOOL NEWSPAPER Farmer v22 — Auto phone-state detect + reopen
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
local facingConnection = nil
local drawConnection = nil
local currentFaceTarget = nil

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
-- REAL PHONE STATE DETECTION
-- ============================================
local phoneFrameCache = nil

local function findPhoneFrame()
    if phoneFrameCache and phoneFrameCache.Parent then
        return phoneFrameCache
    end
    phoneFrameCache = nil

    for _, obj in pairs(Player.PlayerGui:GetDescendants()) do
        if obj:IsA("Frame") or obj:IsA("ScreenGui") or obj:IsA("ImageLabel") then
            local markerHits = 0
            for _, child in ipairs(obj:GetDescendants()) do
                if (child:IsA("TextButton") or child:IsA("TextLabel")) and child.Text then
                    local t = child.Text:upper()
                    if t == "INDEED" or t == "CONTACTS" or t == "MENU"
                       or t == "CAMERA" or t == "DIAL" or t == "MY PHONE" then
                        markerHits = markerHits + 1
                    end
                end
            end
            if markerHits >= 2 then
                phoneFrameCache = obj
                return obj
            end
        end
    end
    return nil
end

local function isPhoneOpenReal()
    local frame = findPhoneFrame()
    if not frame then
        return false
    end
    if frame:IsA("ScreenGui") then
        return frame.Enabled
    else
        return frame.Visible
    end
end

local function pressLeftAlt()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftAlt, false, nil)
    task.wait(0.12)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftAlt, false, nil)
end

local function ensurePhoneState(wantOpen, waitAfter)
    waitAfter = waitAfter or 0.4
    phoneFrameCache = nil
    local actual = isPhoneOpenReal()
    if actual ~= wantOpen then
        pressLeftAlt()
        task.wait(waitAfter)
        phoneFrameCache = nil
        logStatus("Phone toggle: " .. tostring(actual) .. " -> " .. tostring(wantOpen))
    end
    phoneOpen = wantOpen
end

-- Mở điện thoại và VERIFY thật sự đã mở (retry tối đa 3 lần)
-- Dùng trước mọi thao tác UI trên phone
local function ensurePhoneOpenVerified()
    for attempt = 1, 3 do
        if not running then return false end
        phoneFrameCache = nil
        if isPhoneOpenReal() then
            phoneOpen = true
            if attempt > 1 then
                logStatus("✓ Điện thoại đã MỞ (lần thử " .. attempt .. ")")
            end
            return true
        end
        logStatus("Phone CLOSED — bấm LeftAlt mở lại (lần " .. attempt .. "/3)...")
        pressLeftAlt()
        if not waitCheck(0.55) then return false end
        phoneFrameCache = nil
    end

    phoneOpen = isPhoneOpenReal()
    if not phoneOpen then
        logStatus("⚠ Không mở được điện thoại sau 3 lần. Bỏ vòng này.")
        return false
    end
    return true
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
-- Assignment detect (nguồn xác thực job DUY NHẤT)
-- ============================================
local function getAssignmentTargetName()
    for _, obj in pairs(Player.PlayerGui:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Text and obj.Text ~= "" then
            local name = obj.Text:match("[Gg]et a photo of%s+([^%.\n]+)")
            if name then return name:gsub("%s+$",""):gsub("^%s+","") end
        end
    end
    return nil
end

local function isJobActive()
    return getAssignmentTargetName() ~= nil
end

-- ============================================
-- Combat Safety
-- ============================================
local function forceClosePhone()
    ensurePhoneState(false, 0.15)
    cameraOpened = false
    logStatus("⚠ Bị tấn công! Đóng điện thoại khẩn cấp.")
    underAttack = true
    combatCooldownUntil = tick() + 5
    task.delay(5, function()
        if tick() >= combatCooldownUntil - 0.1 then underAttack = false end
    end)
end

Humanoid.HealthChanged:Connect(function(newHealth)
    if newHealth < lastHealth - 0.5 then forceClosePhone() end
    lastHealth = newHealth
end)

Player.CharacterAdded:Connect(function(newChar)
    Character = newChar
    HumanoidRootPart = newChar:WaitForChild("HumanoidRootPart")
    Humanoid = newChar:WaitForChild("Humanoid")
    lastHealth = Humanoid.Health
    Humanoid.HealthChanged:Connect(function(h)
        if h < lastHealth - 0.5 then forceClosePhone() end
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
        reticleCircle.Thickness = 3; reticleCircle.NumSides = 50; reticleCircle.Visible = false
        reticleLine = Drawing.new("Line")
        reticleLine.Color = Color3.fromRGB(255,220,40); reticleLine.Thickness = 2; reticleLine.Visible = false
        reticleDot = Drawing.new("Circle")
        reticleDot.Radius = 6; reticleDot.Filled = true; reticleDot.Color = Color3.fromRGB(255,220,40); reticleDot.Visible = false
    end)
end

local function updateReticleVisual(target)
    if not reticleCircle then return end
    local vw, vh = Camera.ViewportSize.X, Camera.ViewportSize.Y
    local center = Vector2.new(vw / 2, vh / 2)
    reticleCircle.Radius = FRAME_RADIUS_RATIO * vw
    reticleCircle.Position = center
    reticleCircle.Visible = true

    if target and target.part and target.part.Parent then
        local sp, onScreen = Camera:WorldToViewportPoint(target.part.Position)
        if onScreen then
            reticleLine.From = center
            reticleLine.To = Vector2.new(sp.X, sp.Y)
            reticleLine.Visible = true
            reticleDot.Position = Vector2.new(sp.X, sp.Y)
            reticleDot.Visible = true
            local dx, dy = (sp.X-center.X)/vw, (sp.Y-center.Y)/vh
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
    else
        reticleLine.Visible = false
        reticleDot.Visible = false
    end
end

local function startVisual(target)
    if drawConnection then drawConnection:Disconnect() end
    drawConnection = RunService.RenderStepped:Connect(function()
        if not running then return end
        updateReticleVisual(target)
    end)
end

local function stopVisual()
    if drawConnection then drawConnection:Disconnect(); drawConnection = nil end
    if reticleCircle then reticleCircle.Visible = false end
    if reticleLine then reticleLine.Visible = false end
    if reticleDot then reticleDot.Visible = false end
end

-- ============================================
-- ESP
-- ============================================
local function findQuestMarker()
    local rootPart = Character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end

    local candidates = {}
    local roots = {workspace, Player.PlayerGui}
    for _, root in ipairs(roots) do
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("BillboardGui") then
                local hasDist = false
                local nm = nil
                for _, child in ipairs(obj:GetDescendants()) do
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
    if #candidates == 0 then return nil end

    local an = (getAssignmentTargetName() or ""):lower()
    if #an > 0 then
        for _, c in ipairs(candidates) do
            local cn = (c.name or ""):lower()
            if cn == an or cn:find(an,1,true) or an:find(cn,1,true) then
                if c.part and c.part.Parent then
                    return {pos=c.part.Position, part=c.part, name=c.name, dist=(rootPart.Position-c.part.Position).Magnitude}
                end
            end
        end
    end

    local best, bd = nil, math.huge
    for _, c in ipairs(candidates) do
        if c.part and c.part.Parent then
            local d = (rootPart.Position-c.part.Position).Magnitude
            if d < bd then bd=d; best={pos=c.part.Position, part=c.part, name=c.name, dist=d} end
        end
    end
    return best
end

-- ============================================
-- Facing / Camera Bypass — force CFrame trực tiếp, không cần Q
-- ============================================
local MAX_LOCK_DIST_MULT = 1.5

local function stopFacing()
    if facingConnection then facingConnection:Disconnect(); facingConnection = nil end
    currentFaceTarget = nil
end

local function startFacing(target)
    stopFacing()
    currentFaceTarget = target
    facingConnection = RunService.RenderStepped:Connect(function()
        if not running or underAttack then return end
        if not currentFaceTarget or not currentFaceTarget.part or not currentFaceTarget.part.Parent then
            stopFacing()
            return
        end

        local char = Player.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local targetPos = currentFaceTarget.part.Position

        local dist = (targetPos - root.Position).Magnitude
        if dist > 60 * MAX_LOCK_DIST_MULT then
            stopFacing()
            return
        end

        local lookAt = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
        root.CFrame = CFrame.new(root.Position, lookAt)

        local focusPos = (targetPos + root.Position) / 2 + Vector3.new(0, 2, 0)
        Camera.CFrame = CFrame.new(Camera.CFrame.Position, focusPos)
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
-- TELEPORT — có xác nhận vị trí thật (fix máy khựng/lag)
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
-- Chấp nhận job — LeftAlt(nếu cần) -> Enter -> →↓↓↓ -> Enter -> đợi 0.5s -> Enter -> đợi 0.2s -> Enter
-- ============================================
local function acceptJob()
    if not running then return end

    if isJobActive() then
        jobAccepted = true
        logStatus("✓ Job đã active sẵn: " .. tostring(getAssignmentTargetName()))
        return
    end

    logStatus("Kiểm tra trạng thái điện thoại thật...")
    if not ensurePhoneOpenVerified() then return end
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
-- teleport -> xác nhận -> đợi 2s -> ENSURE PHONE OPEN -> Backspace x2 -> ↓↓↓ -> Enter -> Enter -> đợi 1s -> Backspace
-- ============================================
local function doTargetCycle()
    if not running or underAttack then return false end

    local target = findQuestMarker()
    if not target then return false end

    startVisual(target)
    startFacing(target)

    local tpOk = teleportNearTarget(target, 5)
    if not tpOk or not running then stopFacing(); stopVisual(); return false end

    -- đợi 2s sau khi xác nhận dịch chuyển thành công
    if not waitCheck(2.0) then stopFacing(); stopVisual(); return false end

    -- ★ AUTO-DETECT: nếu phone đang đóng thì mở lại trước khi bấm UI
    if not ensurePhoneOpenVerified() then
        stopFacing(); stopVisual()
        return false
    end

    -- Backspace x2
    key(Enum.KeyCode.Backspace, 0.3)
    if not running then return false end
    key(Enum.KeyCode.Backspace, 0.3)
    if not running then return false end

    -- ↓↓↓
    key(Enum.KeyCode.Down, 0.3)
    if not running then return false end
    key(Enum.KeyCode.Down, 0.3)
    if not running then return false end
    key(Enum.KeyCode.Down, 0.3)
    if not running then return false end

    -- Enter mở camera
    key(Enum.KeyCode.Return, 0.5)
    if not running then return false end
    cameraOpened = true

    waitForLock(target, 0.3)
    if not running or underAttack then return false end

    -- Enter chụp
    logStatus("📸 Chụp: " .. target.name .. " (" .. string.format("%.1f", target.dist) .. " studs)")
    key(Enum.KeyCode.Return, 0.3)
    if not running then return false end

    -- đợi chụp xong 1s
    if not waitCheck(1.0) then return false end

    -- Backspace thoát camera
    key(Enum.KeyCode.Backspace, 0.3)
    if not running then return false end

    stopFacing()
    stopVisual()
    cameraOpened = false

    return true
end

-- ============================================
-- MAIN LOOP — crash-safe
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

    stopVisual()
    stopFacing()
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
            stopVisual()
            stopFacing()
            ensurePhoneState(false, 0.15)
            cameraOpened = false
        end
    end)

    UserInputService.InputBegan:Connect(function(i, gp)
        if gp then return end
        if i.KeyCode == Enum.KeyCode.M then
            frame.Visible = not frame.Visible
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.3)
            phoneFrameCache = nil
            local realPhoneState = isPhoneOpenReal()
            phoneOpen = realPhoneState

            if statusLabels.phone then
                statusLabels.phone.Text = "Phone: " .. (realPhoneState and "OPEN" or "CLOSED")
                statusLabels.phone.TextColor3 = realPhoneState and Color3.fromRGB(80,220,120) or Color3.fromRGB(200,200,200)
            end
            if statusLabels.job then
                local active = isJobActive()
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
                local n = getAssignmentTargetName()
                statusLabels.target.Text = "Target: " .. (n or "--")
            end
        end
    end)
end

buildUI()
logStatus("Script loaded v22 — Auto phone-state detect, reopen if CLOSED.")
