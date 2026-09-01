-- Hero Battleground | Full Suite v6 — Anti-Detect Mobile
-- Executor: Arceus X / Delta / Fluxus Mobile
-- by Axiom

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")
local CoreGui          = game:GetService("CoreGui")
local VIM              = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera
local Mouse       = LocalPlayer:GetMouse()

-- ========================
-- ANTI-DETECT WRAPPER
-- ========================
-- Dùng CoreGui thay PlayerGui để tránh Hyperion scan
local function SafeGui(name)
    local old = CoreGui:FindFirstChild(name)
    if old then old:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name           = name
    sg.ResetOnSpawn   = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    -- syn.protect_gui nếu executor support (Synapse X)
    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(sg)
        end
    end)

    -- protect_gui universal fallback
    pcall(function()
        if protect_gui then protect_gui(sg) end
    end)

    sg.Parent = CoreGui
    return sg
end

-- VIM wrapper: tránh gọi trực tiếp — một số game patch VIM trên mobile
-- Dùng firebutton / firetouchinterest nếu có (Arceus X / Delta)
local function SimulateClick(x, y)
    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true,  game, 0) end)
    task.delay(0.09, function()
        pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
    end)
end

local function SimulateKey(down, keyCode)
    pcall(function() VIM:SendKeyEvent(down, keyCode, false, game) end)
end

-- ========================
-- CONFIG
-- ========================
local Config = {
    HookDash = {
        Enabled      = false,
        MobileMode   = false,
        MaxRange     = 22,
        ArcRadius    = 5,
        DashSpeed    = 0.18,
        BehindOffset = 5,
        ArcSteps     = 12,
        StepJitter   = 0.004,
        AutoM1       = true,
        TargetKey    = Enum.KeyCode.V,
        ActivateKey  = Enum.KeyCode.C,
    },
    Aimbot = {
        Enabled      = false,
        MobileMode   = false,
        FOV          = 180,
        SmoothFactor = 0.13,
        AimKey       = Enum.KeyCode.H,
        HitPart      = "Head",
        ShowFOV      = false,
    },
    Autoblock = {
        Enabled      = false,
        ReactionTime = 0.03,
        UnblockDelay = 0.15,
        VelThreshold = 18,
        VelDotMin    = 0.6,
        MaxRange     = 15,
    },
}

-- ========================
-- STATE
-- ========================
local State = {
    HookTarget      = nil,
    DashCooldown    = false,
    BlockActive     = false,
    AimActive       = false,   -- toggle, không phải hold
    TargetHL        = nil,
    FOVCircle       = nil,
    MenuVisible     = false,   -- mặc định ẩn
    MobileDashPanel = nil,
    MobileAimPanel  = nil,
}

-- ========================
-- UTILITY
-- ========================
local function GetChar(p)
    return p and p.Character
end
local function GetRoot(p)
    local c = GetChar(p)
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end
local function GetHum(p)
    local c = GetChar(p)
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function IsAlive(p)
    local h = GetHum(p)
    return h and h.Health > 0
end
local function WorldDist(p)
    local a, b = GetRoot(LocalPlayer), GetRoot(p)
    return (a and b) and (a.Position - b.Position).Magnitude or math.huge
end
local function ClosestWorld()
    local best, bd = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not IsAlive(p) then continue end
        local d = WorldDist(p)
        if d < bd then bd = d; best = p end
    end
    return best
end
local function ClosestToCenter()
    local cx = Camera.ViewportSize.X / 2
    local cy = Camera.ViewportSize.Y / 2
    local best, bd = nil, Config.Aimbot.FOV
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not IsAlive(p) then continue end
        local c = GetChar(p)
        if not c then continue end
        local part = c:FindFirstChild(Config.Aimbot.HitPart) or c:FindFirstChild("HumanoidRootPart")
        if not part then continue end
        local sp, on = Camera:WorldToViewportPoint(part.Position)
        if not on then continue end
        local d = (Vector2.new(sp.X, sp.Y) - Vector2.new(cx, cy)).Magnitude
        if d < bd then bd = d; best = p end
    end
    return best
end
local function ClosestToCursor()
    local best, bd = nil, Config.Aimbot.FOV
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not IsAlive(p) then continue end
        local c = GetChar(p)
        if not c then continue end
        local part = c:FindFirstChild(Config.Aimbot.HitPart) or c:FindFirstChild("HumanoidRootPart")
        if not part then continue end
        local sp, on = Camera:WorldToViewportPoint(part.Position)
        if not on then continue end
        local d = (Vector2.new(sp.X, sp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
        if d < bd then bd = d; best = p end
    end
    return best
end

-- ========================
-- HOOK DASH
-- ========================
local function SetHookTarget(player)
    if State.TargetHL then
        State.TargetHL:Destroy()
        State.TargetHL = nil
    end
    State.HookTarget = player
    if not player then return end
    local c = GetChar(player)
    if not c then return end
    local hl = Instance.new("SelectionBox")
    hl.Adornee             = c
    hl.Color3              = Color3.fromRGB(255, 80, 80)
    hl.LineThickness       = 0.04
    hl.SurfaceTransparency = 0.6
    hl.SurfaceColor3       = Color3.fromRGB(255, 50, 50)
    hl.Parent              = Workspace
    State.TargetHL         = hl
end

local function Bezier(p0, p1, p2, t)
    return (1-t)^2 * p0 + 2*(1-t)*t * p1 + t^2 * p2
end

local function PerformSideDash(target)
    if State.DashCooldown then return end
    local myRoot     = GetRoot(LocalPlayer)
    local targetRoot = GetRoot(target)
    if not myRoot or not targetRoot then return end
    if WorldDist(target) > Config.HookDash.MaxRange then return end

    State.DashCooldown = true

    local cfg    = Config.HookDash
    local p0     = myRoot.Position
    local tCF    = targetRoot.CFrame
    local side   = (math.random(0, 1) == 0) and 1 or -1
    local flank  = (tCF * CFrame.new(side * cfg.ArcRadius * 2.2, 0, 0)).Position
    local p1     = Vector3.new(flank.X, p0.Y, flank.Z)
    local behind = (tCF * CFrame.new(0, 0, cfg.BehindOffset)).Position
    local p2     = Vector3.new(behind.X, p0.Y, behind.Z)

    local steps    = cfg.ArcSteps
    local stepTime = cfg.DashSpeed / steps
    local char     = GetChar(LocalPlayer)

    local function DoStep(i)
        if not char or not char.Parent then
            State.DashCooldown = false; return
        end
        local root = GetRoot(LocalPlayer)
        local tgt  = GetRoot(target)
        if not root or not tgt then
            State.DashCooldown = false; return
        end
        local t   = i / steps
        local pos = Bezier(p0, p1, p2, t)
        local lk  = Vector3.new(tgt.Position.X, pos.Y, tgt.Position.Z)
        pcall(function() root.CFrame = CFrame.new(pos, lk) end)

        if i >= steps then
            if cfg.AutoM1 then
                task.delay(0.06, function()
                    SimulateClick(Mouse.X, Mouse.Y)
                end)
            end
            task.delay(0.55, function() State.DashCooldown = false end)
            return
        end
        local jitter = stepTime + (math.random() - 0.5) * cfg.StepJitter * 2
        task.delay(jitter, function() DoStep(i + 1) end)
    end

    task.spawn(function() DoStep(1) end)
end

-- ========================
-- FOV CIRCLE
-- ========================
local function DestroyFOV()
    if State.FOVCircle then
        State.FOVCircle:Destroy()
        State.FOVCircle = nil
    end
end

local function BuildFOVCircle()
    DestroyFOV()
    if not Config.Aimbot.ShowFOV or not Config.Aimbot.Enabled then return end

    local sg = SafeGui("AxiomFOV")
    local r  = Config.Aimbot.FOV

    local d = Instance.new("Frame")
    d.Size                   = UDim2.new(0, r*2, 0, r*2)
    d.AnchorPoint            = Vector2.new(0.5, 0.5)
    d.BackgroundTransparency = 1
    d.Parent                 = sg

    local ring = Instance.new("Frame")
    ring.Size                   = UDim2.new(1, 0, 1, 0)
    ring.BackgroundTransparency = 1
    ring.BorderSizePixel        = 0
    ring.Parent                 = d
    Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)

    local stroke = Instance.new("UIStroke")
    stroke.Color        = Color3.fromRGB(255, 80, 80)
    stroke.Thickness    = 1.2
    stroke.Transparency = 0.3
    stroke.Parent       = ring

    State.FOVCircle = sg

    RunService.RenderStepped:Connect(function()
        if not State.FOVCircle or not State.FOVCircle.Parent then return end
        if Config.Aimbot.MobileMode then
            d.Position = UDim2.new(0.5, 0, 0.5, 0)
        else
            d.Position = UDim2.new(0, Mouse.X, 0, Mouse.Y)
        end
    end)
end

-- ========================
-- AIMBOT (TOGGLE)
-- ========================
local function RunAimbot()
    if not Config.Aimbot.Enabled then return end
    if not State.AimActive then return end

    local target = Config.Aimbot.MobileMode
        and ClosestToCenter()
        or  ClosestToCursor()
    if not target then return end

    local c = GetChar(target)
    if not c then return end
    local part = c:FindFirstChild(Config.Aimbot.HitPart) or c:FindFirstChild("HumanoidRootPart")
    if not part then return end

    local sp, on = Camera:WorldToViewportPoint(part.Position)
    if not on then return end

    local ref = Config.Aimbot.MobileMode
        and Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
        or  Vector2.new(Mouse.X, Mouse.Y)

    local delta = (Vector2.new(sp.X, sp.Y) - ref) * Config.Aimbot.SmoothFactor
    pcall(function() mousemoverel(delta.X, delta.Y) end)
end

-- ========================
-- AUTOBLOCK
-- ========================
local function IsM1Incoming(player)
    local c = GetChar(player)
    if not c then return false end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local anim = hum:FindFirstChildOfClass("Animator")
    if anim then
        for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
            local id = track.Animation.AnimationId:lower()
            if id:find("punch") or id:find("attack") or id:find("hit")
            or id:find("m1")    or id:find("swing") then
                return true
            end
        end
    end
    local er = GetRoot(player)
    local mr = GetRoot(LocalPlayer)
    if er and mr then
        local vel = er.AssemblyLinearVelocity
        local dir = (mr.Position - er.Position).Unit
        if vel.Magnitude > Config.Autoblock.VelThreshold
        and vel.Unit:Dot(dir) > Config.Autoblock.VelDotMin then
            return true
        end
    end
    return false
end

local function RunAutoblock()
    if not Config.Autoblock.Enabled or State.BlockActive then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not IsAlive(p) then continue end
        if WorldDist(p) > Config.Autoblock.MaxRange then continue end
        if IsM1Incoming(p) then
            State.BlockActive = true
            task.delay(Config.Autoblock.ReactionTime, function()
                SimulateKey(true, Enum.KeyCode.F)
                task.delay(Config.Autoblock.UnblockDelay, function()
                    SimulateKey(false, Enum.KeyCode.F)
                    task.delay(0.05, function()
                        State.BlockActive = false
                    end)
                end)
            end)
            break
        end
    end
end

-- ========================
-- MOBILE PANELS
-- ========================
local function DestroyPanel(key)
    if State[key] then
        State[key]:Destroy()
        State[key] = nil
    end
end

local function MakeTouchBtn(parent, xPos, yPos, w, h, label, color, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size             = UDim2.new(0, w, 0, h)
    Btn.Position         = UDim2.new(0, xPos, 0, yPos)
    Btn.BackgroundColor3 = color
    Btn.BorderSizePixel  = 0
    Btn.Text             = label
    Btn.Font             = Enum.Font.GothamBold
    Btn.TextSize         = 13
    Btn.TextColor3       = Color3.fromRGB(255, 255, 255)
    Btn.AutoButtonColor  = false
    Btn.Parent           = parent
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 10)

    local base = color
    Btn.MouseButton1Down:Connect(function()
        TweenService:Create(Btn, TweenInfo.new(0.07), {
            BackgroundColor3 = base:Lerp(Color3.new(0,0,0), 0.3)
        }):Play()
    end)
    Btn.MouseButton1Up:Connect(function()
        TweenService:Create(Btn, TweenInfo.new(0.07), {
            BackgroundColor3 = base
        }):Play()
    end)
    Btn.MouseButton1Click:Connect(callback)
    return Btn
end

-- Panel header helper
local function MakePanelHeader(parent, h, title)
    local Bar = Instance.new("Frame")
    Bar.Size             = UDim2.new(1, 0, 0, h)
    Bar.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    Bar.BorderSizePixel  = 0
    Bar.Parent           = parent
    Instance.new("UICorner", Bar).CornerRadius = UDim.new(0, 12)

    local Patch = Instance.new("Frame")
    Patch.Size             = UDim2.new(1, 0, 0, 8)
    Patch.Position         = UDim2.new(0, 0, 1, -8)
    Patch.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    Patch.BorderSizePixel  = 0
    Patch.Parent           = Bar

    local Lbl = Instance.new("TextLabel")
    Lbl.Text               = title
    Lbl.Font               = Enum.Font.GothamBold
    Lbl.TextSize           = 12
    Lbl.TextColor3         = Color3.fromRGB(255, 255, 255)
    Lbl.Size               = UDim2.new(1, 0, 1, 0)
    Lbl.BackgroundTransparency = 1
    Lbl.Parent             = Bar
end

local function MakeFloatPanel(guiName, w, h, defaultX, defaultY)
    local sg = SafeGui(guiName)
    local Panel = Instance.new("Frame")
    Panel.Size             = UDim2.new(0, w, 0, h)
    Panel.Position         = UDim2.new(0, defaultX, 0, defaultY)
    Panel.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
    Panel.BorderSizePixel  = 0
    Panel.Active           = true
    Panel.Draggable        = true
    Panel.Parent           = sg
    Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)

    local PS = Instance.new("UIStroke")
    PS.Color = Color3.fromRGB(200, 45, 45); PS.Thickness = 1.5
    PS.Parent = Panel

    return sg, Panel
end

local function BuildMobileDashPanel()
    DestroyPanel("MobileDashPanel")

    local sg, Panel = MakeFloatPanel(
        "AxiomDashPanel", 215, 125,
        -- góc dưới phải — tính từ viewport
        Camera.ViewportSize.X - 230,
        Camera.ViewportSize.Y - 220
    )
    State.MobileDashPanel = sg

    MakePanelHeader(Panel, 30, "⚡ Hook Dash")

    local TLbl = Instance.new("TextLabel")
    TLbl.Name               = "TLbl"
    TLbl.Text               = "Target: None"
    TLbl.Font               = Enum.Font.Gotham
    TLbl.TextSize           = 11
    TLbl.TextColor3         = Color3.fromRGB(150, 150, 160)
    TLbl.Size               = UDim2.new(1, -12, 0, 18)
    TLbl.Position           = UDim2.new(0, 8, 0, 33)
    TLbl.BackgroundTransparency = 1
    TLbl.TextXAlignment     = Enum.TextXAlignment.Left
    TLbl.Parent             = Panel

    MakeTouchBtn(Panel, 8, 55, 97, 58, "🎯\nTARGET",
        Color3.fromRGB(35, 35, 52), function()
            if not Config.HookDash.Enabled then return end
            local t = ClosestWorld()
            SetHookTarget(t)
            TLbl.Text       = t and ("📍 " .. t.Name) or "Target: None"
            TLbl.TextColor3 = t
                and Color3.fromRGB(255, 100, 100)
                or  Color3.fromRGB(150, 150, 160)
        end)

    MakeTouchBtn(Panel, 112, 55, 97, 58, "⚡\nDASH",
        Color3.fromRGB(190, 35, 35), function()
            if not Config.HookDash.Enabled then return end
            if State.HookTarget and IsAlive(State.HookTarget) then
                PerformSideDash(State.HookTarget)
            else
                SetHookTarget(nil)
                TLbl.Text       = "Target: None"
                TLbl.TextColor3 = Color3.fromRGB(150, 150, 160)
            end
        end)

    -- Sync target label
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not State.MobileDashPanel or not State.MobileDashPanel.Parent then
            conn:Disconnect(); return
        end
        if State.HookTarget and not IsAlive(State.HookTarget) then
            SetHookTarget(nil)
            TLbl.Text       = "Target: None"
            TLbl.TextColor3 = Color3.fromRGB(150, 150, 160)
        end
    end)
end

local function BuildMobileAimPanel()
    DestroyPanel("MobileAimPanel")

    local sg, Panel = MakeFloatPanel(
        "AxiomAimPanel", 140, 85,
        Camera.ViewportSize.X - 155,
        Camera.ViewportSize.Y - 310
    )
    State.MobileAimPanel = sg

    MakePanelHeader(Panel, 28, "🎯 Aimbot")

    -- Toggle aim button (tap to on/off)
    local AimBtn = Instance.new("TextButton")
    AimBtn.Size             = UDim2.new(1, -16, 0, 44)
    AimBtn.Position         = UDim2.new(0, 8, 0, 33)
    AimBtn.BorderSizePixel  = 0
    AimBtn.Font             = Enum.Font.GothamBold
    AimBtn.TextSize         = 13
    AimBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
    AimBtn.AutoButtonColor  = false
    AimBtn.Parent           = Panel
    Instance.new("UICorner", AimBtn).CornerRadius = UDim.new(0, 8)

    local function RefreshAimBtn()
        AimBtn.Text = State.AimActive and "● ON" or "○ OFF"
        TweenService:Create(AimBtn, TweenInfo.new(0.12), {
            BackgroundColor3 = State.AimActive
                and Color3.fromRGB(200, 40, 40)
                or  Color3.fromRGB(35, 35, 52)
        }):Play()
    end

    RefreshAimBtn()

    AimBtn.MouseButton1Click:Connect(function()
        State.AimActive = not State.AimActive
        RefreshAimBtn()
    end)
end

-- ========================
-- MAIN MENU
-- ========================
local function BuildMenu()
    local old = CoreGui:FindFirstChild("AxiomMenu")
    if old then old:Destroy() end

    local RootGui = SafeGui("AxiomMenu")

    -- ── Icon button (ô vuông đỏ, góc trên trái) ──
    local IconBtn = Instance.new("TextButton")
    IconBtn.Name             = "MenuIcon"
    IconBtn.Size             = UDim2.new(0, 48, 0, 48)
    IconBtn.Position         = UDim2.new(0, 12, 0, 12)
    IconBtn.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    IconBtn.BorderSizePixel  = 0
    IconBtn.Text             = "⚡"
    IconBtn.Font             = Enum.Font.GothamBold
    IconBtn.TextSize         = 24
    IconBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
    IconBtn.AutoButtonColor  = false
    IconBtn.ZIndex           = 20
    IconBtn.Parent           = RootGui
    Instance.new("UICorner", IconBtn).CornerRadius = UDim.new(0, 10)

    local IStroke = Instance.new("UIStroke")
    IStroke.Color       = Color3.fromRGB(255, 255, 255)
    IStroke.Thickness   = 1
    IStroke.Transparency = 0.5
    IStroke.Parent      = IconBtn

    -- ── Menu frame (mặc định ẩn) ──
    local Frame = Instance.new("Frame")
    Frame.Name             = "MainFrame"
    Frame.Size             = UDim2.new(0, 255, 0, 460)
    Frame.Position         = UDim2.new(0, 12, 0, 68)
    Frame.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    Frame.BorderSizePixel  = 0
    Frame.Active           = true
    Frame.Draggable        = true
    Frame.Visible          = false   -- ẩn mặc định
    Frame.ZIndex           = 10
    Frame.Parent           = RootGui
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 10)

    local MStroke = Instance.new("UIStroke")
    MStroke.Color     = Color3.fromRGB(200, 45, 45)
    MStroke.Thickness = 1.5
    MStroke.Parent    = Frame

    -- Title bar
    local TitleBar = Instance.new("Frame")
    TitleBar.Size             = UDim2.new(1, 0, 0, 38)
    TitleBar.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    TitleBar.BorderSizePixel  = 0
    TitleBar.ZIndex           = 11
    TitleBar.Parent           = Frame
    Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

    local TBPatch = Instance.new("Frame")
    TBPatch.Size             = UDim2.new(1, 0, 0, 10)
    TBPatch.Position         = UDim2.new(0, 0, 1, -10)
    TBPatch.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    TBPatch.BorderSizePixel  = 0
    TBPatch.ZIndex           = 11
    TBPatch.Parent           = TitleBar

    local TitleLbl = Instance.new("TextLabel")
    TitleLbl.Text               = "⚡  AXIOM SUITE"
    TitleLbl.Font               = Enum.Font.GothamBold
    TitleLbl.TextSize           = 14
    TitleLbl.TextColor3         = Color3.fromRGB(255, 255, 255)
    TitleLbl.Size               = UDim2.new(1, 0, 1, 0)
    TitleLbl.BackgroundTransparency = 1
    TitleLbl.ZIndex             = 12
    TitleLbl.Parent             = TitleBar

    local SubLbl = Instance.new("TextLabel")
    SubLbl.Text             = "Hero Battleground  •  v6"
    SubLbl.Font             = Enum.Font.Gotham
    SubLbl.TextSize         = 10
    SubLbl.TextColor3       = Color3.fromRGB(120, 120, 135)
    SubLbl.Size             = UDim2.new(1, -16, 0, 14)
    SubLbl.Position         = UDim2.new(0, 10, 0, 42)
    SubLbl.BackgroundTransparency = 1
    SubLbl.TextXAlignment   = Enum.TextXAlignment.Left
    SubLbl.Parent           = Frame

    -- Icon toggle
    IconBtn.MouseButton1Click:Connect(function()
        Frame.Visible = not Frame.Visible
        TweenService:Create(IconBtn, TweenInfo.new(0.1), {
            BackgroundColor3 = Frame.Visible
                and Color3.fromRGB(190, 35, 35)
                or  Color3.fromRGB(40, 40, 55),
        }):Play()
    end)

    -- ── Toggle factory ──
    local function MakeToggle(yPos, icon, label, desc, cfgTable, cfgKey, onToggle)
        local Row = Instance.new("Frame")
        Row.Size             = UDim2.new(1, -20, 0, 52)
        Row.Position         = UDim2.new(0, 10, 0, yPos)
        Row.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        Row.BorderSizePixel  = 0
        Row.Parent           = Frame
        Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 7)

        local RS = Instance.new("UIStroke")
        RS.Color = Color3.fromRGB(35, 35, 48); RS.Thickness = 1
        RS.Parent = Row

        local ILbl = Instance.new("TextLabel")
        ILbl.Text = icon; ILbl.Font = Enum.Font.GothamBold
        ILbl.TextSize = 16; ILbl.TextColor3 = Color3.fromRGB(200, 45, 45)
        ILbl.Size = UDim2.new(0, 30, 1, 0)
        ILbl.Position = UDim2.new(0, 8, 0, 0)
        ILbl.BackgroundTransparency = 1; ILbl.Parent = Row

        local MLbl = Instance.new("TextLabel")
        MLbl.Text = label; MLbl.Font = Enum.Font.GothamBold
        MLbl.TextSize = 12; MLbl.TextColor3 = Color3.fromRGB(230, 230, 230)
        MLbl.Size = UDim2.new(1, -90, 0, 22)
        MLbl.Position = UDim2.new(0, 44, 0, 6)
        MLbl.BackgroundTransparency = 1
        MLbl.TextXAlignment = Enum.TextXAlignment.Left
        MLbl.Parent = Row

        local DLbl = Instance.new("TextLabel")
        DLbl.Text = desc; DLbl.Font = Enum.Font.Gotham
        DLbl.TextSize = 10; DLbl.TextColor3 = Color3.fromRGB(95, 95, 115)
        DLbl.Size = UDim2.new(1, -90, 0, 16)
        DLbl.Position = UDim2.new(0, 44, 0, 28)
        DLbl.BackgroundTransparency = 1
        DLbl.TextXAlignment = Enum.TextXAlignment.Left
        DLbl.Parent = Row

        local PBg = Instance.new("Frame")
        PBg.Size = UDim2.new(0, 44, 0, 22)
        PBg.Position = UDim2.new(1, -52, 0.5, -11)
        PBg.BorderSizePixel = 0; PBg.Parent = Row
        Instance.new("UICorner", PBg).CornerRadius = UDim.new(1, 0)

        local PDot = Instance.new("Frame")
        PDot.Size = UDim2.new(0, 16, 0, 16)
        PDot.BorderSizePixel = 0; PDot.Parent = PBg
        Instance.new("UICorner", PDot).CornerRadius = UDim.new(1, 0)

        local function Refresh()
            local on = cfgTable[cfgKey]
            TweenService:Create(PBg, TweenInfo.new(0.15), {
                BackgroundColor3 = on
                    and Color3.fromRGB(200, 40, 40)
                    or  Color3.fromRGB(45, 45, 58)
            }):Play()
            TweenService:Create(PDot, TweenInfo.new(0.15), {
                Position = on
                    and UDim2.new(0, 25, 0.5, -8)
                    or  UDim2.new(0,  3, 0.5, -8),
                BackgroundColor3 = on
                    and Color3.fromRGB(255, 255, 255)
                    or  Color3.fromRGB(120, 120, 135),
            }):Play()
        end
        Refresh()

        local Btn = Instance.new("TextButton")
        Btn.Size = UDim2.new(1, 0, 1, 0)
        Btn.BackgroundTransparency = 1; Btn.Text = ""
        Btn.Parent = Row
        Btn.MouseButton1Click:Connect(function()
            cfgTable[cfgKey] = not cfgTable[cfgKey]
            Refresh()
            if onToggle then onToggle(cfgTable[cfgKey]) end
        end)
    end

    -- ── Menu rows ──
    MakeToggle(62,  "⚡", "Hook Dash",
        "V: Lock | C: Dash  (PC)",
        Config.HookDash, "Enabled", nil)

    MakeToggle(124, "📱", "Dash Mobile",
        "Hiện panel TARGET + DASH",
        Config.HookDash, "MobileMode", function(val)
            if val then
                BuildMobileDashPanel()
            else
                DestroyPanel("MobileDashPanel")
            end
        end)

    MakeToggle(186, "🎯", "Aimbot",
        "Toggle aim  |  H key (PC)",
        Config.Aimbot, "Enabled", function(val)
            if val then
                BuildFOVCircle()
                if Config.Aimbot.MobileMode then
                    BuildMobileAimPanel()
                end
            else
                State.AimActive = false
                DestroyPanel("MobileAimPanel")
                DestroyFOV()
            end
        end)

    MakeToggle(248, "📱", "Aim Mobile",
        "Hiện nút ON/OFF aimbot",
        Config.Aimbot, "MobileMode", function(val)
            if val and Config.Aimbot.Enabled then
                BuildMobileAimPanel()
            else
                State.AimActive = false
                DestroyPanel("MobileAimPanel")
            end
        end)

    MakeToggle(310, "🛡", "Auto Block",
        "Auto-F khi enemy M1",
        Config.Autoblock, "Enabled", nil)

    MakeToggle(372, "👁", "FOV Circle",
        "Vòng tròn FOV aimbot",
        Config.Aimbot, "ShowFOV", function(val)
            if val and Config.Aimbot.Enabled then
                BuildFOVCircle()
            else
                DestroyFOV()
            end
        end)

    local Footer = Instance.new("TextLabel")
    Footer.Text             = "by Axiom  •  ⚡ để ẩn/hiện"
    Footer.Font             = Enum.Font.Gotham
    Footer.TextSize         = 9
    Footer.TextColor3       = Color3.fromRGB(55, 55, 70)
    Footer.Size             = UDim2.new(1, 0, 0, 18)
    Footer.Position         = UDim2.new(0, 0, 1, -20)
    Footer.BackgroundTransparency = 1
    Footer.Parent           = Frame
end

-- ========================
-- INIT
-- ========================
BuildMenu()

-- ========================
-- PC INPUT
-- ========================
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if not Config.HookDash.MobileMode and Config.HookDash.Enabled then
        if input.KeyCode == Config.HookDash.TargetKey then
            local t = ClosestToCursor()
            SetHookTarget(t)
            print(t and ("[Axiom] Locked: "..t.Name) or "[Axiom] No target")
        end
        if input.KeyCode == Config.HookDash.ActivateKey then
            if State.HookTarget and IsAlive(State.HookTarget) then
                PerformSideDash(State.HookTarget)
            end
        end
    end

    -- H key toggle aimbot (PC, non-mobile)
    if not Config.Aimbot.MobileMode and Config.Aimbot.Enabled then
        if input.KeyCode == Config.Aimbot.AimKey then
            State.AimActive = not State.AimActive
        end
    end
end)

Players.PlayerRemoving:Connect(function(p)
    if State.HookTarget == p then SetHookTarget(nil) end
end)

-- ========================
-- HEARTBEAT
-- ========================
RunService.Heartbeat:Connect(function()
    if State.HookTarget and not IsAlive(State.HookTarget) then
        SetHookTarget(nil)
    end
    if State.TargetHL and State.HookTarget then
        local c = GetChar(State.HookTarget)
        if c then State.TargetHL.Adornee = c end
    end
    RunAimbot()
    RunAutoblock()
end)

print("[Axiom] v6 loaded — tap ⚡ icon to open menu")
