-- Hero Battleground | Full Suite v5
-- Executor: Arceus X / Delta / Fluxus Mobile
-- by Axiom

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")
local Workspace      = game:GetService("Workspace")
local VIM            = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera
local Mouse       = LocalPlayer:GetMouse()

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
        ShowFOV      = true,
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
    AimHeld         = false,
    TargetHL        = nil,
    FOVCircle       = nil,
    MenuVisible     = true,
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

-- Closest player by world distance
local function ClosestWorld()
    local best, bd = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not IsAlive(p) then continue end
        local d = WorldDist(p)
        if d < bd then bd = d; best = p end
    end
    return best
end

-- Closest player to screen center (aimbot)
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

-- Closest player to mouse cursor
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
-- HOOK DASH TARGET HIGHLIGHT
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

-- ========================
-- BEZIER ARC DASH
-- ========================
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
            State.DashCooldown = false
            return
        end
        local root = GetRoot(LocalPlayer)
        local tgt  = GetRoot(target)
        if not root or not tgt then
            State.DashCooldown = false
            return
        end
        local t   = i / steps
        local pos = Bezier(p0, p1, p2, t)
        local lk  = Vector3.new(tgt.Position.X, pos.Y, tgt.Position.Z)
        pcall(function() root.CFrame = CFrame.new(pos, lk) end)

        if i >= steps then
            if cfg.AutoM1 then
                task.delay(0.06, function()
                    pcall(function()
                        VIM:SendMouseButtonEvent(Mouse.X, Mouse.Y, 0, true, game, 0)
                        task.delay(0.09, function()
                            pcall(function()
                                VIM:SendMouseButtonEvent(Mouse.X, Mouse.Y, 0, false, game, 0)
                            end)
                        end)
                    end)
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
local function BuildFOVCircle()
    if State.FOVCircle then
        State.FOVCircle:Destroy()
        State.FOVCircle = nil
    end
    if not Config.Aimbot.ShowFOV or not Config.Aimbot.Enabled then return end

    local sg = Instance.new("ScreenGui")
    sg.Name           = "AxiomFOV"
    sg.ResetOnSpawn   = false
    sg.IgnoreGuiInset = true
    sg.Parent         = LocalPlayer.PlayerGui

    local r = Config.Aimbot.FOV
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

    -- Trên mobile: center màn hình. Trên PC: theo cursor.
    RunService.RenderStepped:Connect(function()
        if not State.FOVCircle or not State.FOVCircle.Parent then return end
        if Config.Aimbot.MobileMode then
            d.Position = UDim2.new(0.5, 0, 0.5, 0)
            d.AnchorPoint = Vector2.new(0.5, 0.5)
        else
            d.AnchorPoint = Vector2.new(0.5, 0.5)
            d.Position = UDim2.new(0, Mouse.X, 0, Mouse.Y)
        end
    end)
end

-- ========================
-- AIMBOT
-- ========================
local function RunAimbot()
    if not Config.Aimbot.Enabled then return end
    if not State.AimHeld then return end

    local target
    if Config.Aimbot.MobileMode then
        target = ClosestToCenter()
    else
        target = ClosestToCursor()
    end
    if not target then return end

    local c = GetChar(target)
    if not c then return end
    local part = c:FindFirstChild(Config.Aimbot.HitPart) or c:FindFirstChild("HumanoidRootPart")
    if not part then return end

    local sp, on = Camera:WorldToViewportPoint(part.Position)
    if not on then return end

    if Config.Aimbot.MobileMode then
        -- Mobile: rotate camera
        local cx = Camera.ViewportSize.X / 2
        local cy = Camera.ViewportSize.Y / 2
        local delta = (Vector2.new(sp.X, sp.Y) - Vector2.new(cx, cy)) * Config.Aimbot.SmoothFactor
        pcall(function() mousemoverel(delta.X, delta.Y) end)
    else
        local delta = (Vector2.new(sp.X, sp.Y) - Vector2.new(Mouse.X, Mouse.Y)) * Config.Aimbot.SmoothFactor
        pcall(function() mousemoverel(delta.X, delta.Y) end)
    end
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

local function PressBlock(down)
    pcall(function() VIM:SendKeyEvent(down, Enum.KeyCode.F, false, game) end)
end

local function RunAutoblock()
    if not Config.Autoblock.Enabled or State.BlockActive then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not IsAlive(p) then continue end
        if WorldDist(p) > Config.Autoblock.MaxRange then continue end
        if IsM1Incoming(p) then
            State.BlockActive = true
            task.delay(Config.Autoblock.ReactionTime, function()
                PressBlock(true)
                task.delay(Config.Autoblock.UnblockDelay, function()
                    PressBlock(false)
                    task.delay(0.05, function() State.BlockActive = false end)
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

-- Helper: big touch button
local function MakeTouchBtn(parent, xPos, yPos, w, h, label, color, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size             = UDim2.new(0, w, 0, h)
    Btn.Position         = UDim2.new(0, xPos, 0, yPos)
    Btn.BackgroundColor3 = color
    Btn.BorderSizePixel  = 0
    Btn.Text             = label
    Btn.Font             = Enum.Font.GothamBold
    Btn.TextSize         = 14
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

local function BuildMobileDashPanel()
    DestroyPanel("MobileDashPanel")
    if not Config.HookDash.MobileMode then return end

    local sg = Instance.new("ScreenGui")
    sg.Name           = "AxiomDashPanel"
    sg.ResetOnSpawn   = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent         = LocalPlayer.PlayerGui
    State.MobileDashPanel = sg

    local Panel = Instance.new("Frame")
    Panel.Name             = "DashPanel"
    Panel.Size             = UDim2.new(0, 210, 0, 120)
    Panel.Position         = UDim2.new(1, -225, 1, -200)
    Panel.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
    Panel.BorderSizePixel  = 0
    Panel.Active           = true
    Panel.Draggable        = true
    Panel.Parent           = sg
    Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)

    local PStroke = Instance.new("UIStroke")
    PStroke.Color     = Color3.fromRGB(200, 45, 45)
    PStroke.Thickness = 1.5
    PStroke.Parent    = Panel

    -- Header
    local Header = Instance.new("Frame")
    Header.Size             = UDim2.new(1, 0, 0, 30)
    Header.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    Header.BorderSizePixel  = 0
    Header.Parent           = Panel
    Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 12)

    local HPatch = Instance.new("Frame")
    HPatch.Size             = UDim2.new(1, 0, 0, 8)
    HPatch.Position         = UDim2.new(0, 0, 1, -8)
    HPatch.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    HPatch.BorderSizePixel  = 0
    HPatch.Parent           = Header

    local HLbl = Instance.new("TextLabel")
    HLbl.Text               = "⚡ Hook Dash"
    HLbl.Font               = Enum.Font.GothamBold
    HLbl.TextSize           = 12
    HLbl.TextColor3         = Color3.fromRGB(255, 255, 255)
    HLbl.Size               = UDim2.new(1, 0, 1, 0)
    HLbl.BackgroundTransparency = 1
    HLbl.Parent             = Header

    -- Target label
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

    -- TARGET button
    MakeTouchBtn(Panel, 8, 55, 95, 55, "🎯\nTARGET",
        Color3.fromRGB(35, 35, 50), function()
            if not Config.HookDash.Enabled then return end
            local t = ClosestWorld()
            SetHookTarget(t)
            TLbl.Text      = t and ("Target: "..t.Name) or "Target: None"
            TLbl.TextColor3 = t
                and Color3.fromRGB(255, 100, 100)
                or  Color3.fromRGB(150, 150, 160)
        end)

    -- DASH button
    MakeTouchBtn(Panel, 110, 55, 95, 55, "⚡\nDASH",
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

    -- Sync label heartbeat
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
    if not Config.Aimbot.MobileMode or not Config.Aimbot.Enabled then return end

    local sg = Instance.new("ScreenGui")
    sg.Name           = "AxiomAimPanel"
    sg.ResetOnSpawn   = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent         = LocalPlayer.PlayerGui
    State.MobileAimPanel = sg

    local Panel = Instance.new("Frame")
    Panel.Name             = "AimPanel"
    Panel.Size             = UDim2.new(0, 130, 0, 80)
    Panel.Position         = UDim2.new(1, -150, 1, -300)
    Panel.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
    Panel.BorderSizePixel  = 0
    Panel.Active           = true
    Panel.Draggable        = true
    Panel.Parent           = sg
    Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)

    local PStroke = Instance.new("UIStroke")
    PStroke.Color     = Color3.fromRGB(200, 45, 45)
    PStroke.Thickness = 1.5
    PStroke.Parent    = Panel

    -- Header
    local Header = Instance.new("Frame")
    Header.Size             = UDim2.new(1, 0, 0, 28)
    Header.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    Header.BorderSizePixel  = 0
    Header.Parent           = Panel
    Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 12)

    local HPatch = Instance.new("Frame")
    HPatch.Size             = UDim2.new(1, 0, 0, 8)
    HPatch.Position         = UDim2.new(0, 0, 1, -8)
    HPatch.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    HPatch.BorderSizePixel  = 0
    HPatch.Parent           = Header

    local HLbl = Instance.new("TextLabel")
    HLbl.Text               = "🎯 Aimbot"
    HLbl.Font               = Enum.Font.GothamBold
    HLbl.TextSize           = 12
    HLbl.TextColor3         = Color3.fromRGB(255, 255, 255)
    HLbl.Size               = UDim2.new(1, 0, 1, 0)
    HLbl.BackgroundTransparency = 1
    HLbl.Parent             = Header

    -- AIM hold button (hold = aim active)
    local AimBtn = Instance.new("TextButton")
    AimBtn.Size             = UDim2.new(1, -16, 0, 40)
    AimBtn.Position         = UDim2.new(0, 8, 0, 34)
    AimBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    AimBtn.BorderSizePixel  = 0
    AimBtn.Text             = "HOLD TO AIM"
    AimBtn.Font             = Enum.Font.GothamBold
    AimBtn.TextSize         = 13
    AimBtn.TextColor3       = Color3.fromRGB(200, 200, 210)
    AimBtn.AutoButtonColor  = false
    AimBtn.Parent           = Panel
    Instance.new("UICorner", AimBtn).CornerRadius = UDim.new(0, 8)

    AimBtn.MouseButton1Down:Connect(function()
        State.AimHeld = true
        TweenService:Create(AimBtn, TweenInfo.new(0.07), {
            BackgroundColor3 = Color3.fromRGB(200, 40, 40)
        }):Play()
        AimBtn.Text = "● AIMING"
    end)
    AimBtn.MouseButton1Up:Connect(function()
        State.AimHeld = false
        TweenService:Create(AimBtn, TweenInfo.new(0.07), {
            BackgroundColor3 = Color3.fromRGB(35, 35, 50)
        }):Play()
        AimBtn.Text = "HOLD TO AIM"
    end)
end

-- ========================
-- MAIN MENU
-- ========================
local function BuildMenu()
    local old = LocalPlayer.PlayerGui:FindFirstChild("AxiomMenu")
    if old then old:Destroy() end

    local RootGui = Instance.new("ScreenGui")
    RootGui.Name           = "AxiomMenu"
    RootGui.ResetOnSpawn   = false
    RootGui.IgnoreGuiInset = true
    RootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    RootGui.Parent         = LocalPlayer.PlayerGui

    -- ── Menu icon button (góc trên trái) ──
    local IconBtn = Instance.new("TextButton")
    IconBtn.Name             = "MenuIcon"
    IconBtn.Size             = UDim2.new(0, 44, 0, 44)
    IconBtn.Position         = UDim2.new(0, 10, 0, 10)
    IconBtn.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    IconBtn.BorderSizePixel  = 0
    IconBtn.Text             = "⚡"
    IconBtn.Font             = Enum.Font.GothamBold
    IconBtn.TextSize         = 22
    IconBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
    IconBtn.AutoButtonColor  = false
    IconBtn.ZIndex           = 10
    IconBtn.Parent           = RootGui
    Instance.new("UICorner", IconBtn).CornerRadius = UDim.new(0, 12)

    local IStroke = Instance.new("UIStroke")
    IStroke.Color     = Color3.fromRGB(255, 255, 255)
    IStroke.Thickness = 1
    IStroke.Transparency = 0.6
    IStroke.Parent    = IconBtn

    -- ── Menu frame ──
    local Frame = Instance.new("Frame")
    Frame.Name             = "MainFrame"
    Frame.Size             = UDim2.new(0, 250, 0, 490)
    Frame.Position         = UDim2.new(0, 10, 0, 62)
    Frame.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    Frame.BorderSizePixel  = 0
    Frame.Active           = true
    Frame.Draggable        = true
    Frame.Visible          = State.MenuVisible
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
    TitleBar.Parent           = Frame
    Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

    local TBPatch = Instance.new("Frame")
    TBPatch.Size             = UDim2.new(1, 0, 0, 10)
    TBPatch.Position         = UDim2.new(0, 0, 1, -10)
    TBPatch.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    TBPatch.BorderSizePixel  = 0
    TBPatch.Parent           = TitleBar

    local TLbl = Instance.new("TextLabel")
    TLbl.Text               = "⚡  AXIOM SUITE"
    TLbl.Font               = Enum.Font.GothamBold
    TLbl.TextSize           = 14
    TLbl.TextColor3         = Color3.fromRGB(255, 255, 255)
    TLbl.Size               = UDim2.new(1, 0, 1, 0)
    TLbl.BackgroundTransparency = 1
    TLbl.Parent             = TitleBar

    local SubLbl = Instance.new("TextLabel")
    SubLbl.Text             = "Hero Battleground  •  v5"
    SubLbl.Font             = Enum.Font.Gotham
    SubLbl.TextSize         = 10
    SubLbl.TextColor3       = Color3.fromRGB(120, 120, 135)
    SubLbl.Size             = UDim2.new(1, -16, 0, 14)
    SubLbl.Position         = UDim2.new(0, 10, 0, 42)
    SubLbl.BackgroundTransparency = 1
    SubLbl.TextXAlignment   = Enum.TextXAlignment.Left
    SubLbl.Parent           = Frame

    -- Icon toggle logic
    IconBtn.MouseButton1Click:Connect(function()
        State.MenuVisible = not State.MenuVisible
        Frame.Visible = State.MenuVisible
        TweenService:Create(IconBtn, TweenInfo.new(0.1), {
            BackgroundColor3 = State.MenuVisible
                and Color3.fromRGB(190, 35, 35)
                or  Color3.fromRGB(40, 40, 55)
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

    -- ── Rows ──
    MakeToggle(62,  "⚡", "Hook Dash",
        "V: Lock | C: Dash (PC)",
        Config.HookDash, "Enabled", nil)

    MakeToggle(124, "📱", "Dash Mobile",
        "Show TARGET + DASH panel",
        Config.HookDash, "MobileMode", function(val)
            if val then BuildMobileDashPanel()
            else DestroyPanel("MobileDashPanel") end
        end)

    MakeToggle(186, "🎯", "Aimbot",
        "H key (PC) | Mobile panel below",
        Config.Aimbot, "Enabled", function(val)
            if not val then
                DestroyPanel("MobileAimPanel")
                if State.FOVCircle then
                    State.FOVCircle:Destroy()
                    State.FOVCircle = nil
                end
            else
                BuildFOVCircle()
                if Config.Aimbot.MobileMode then
                    BuildMobileAimPanel()
                end
            end
        end)

    MakeToggle(248, "📱", "Aim Mobile",
        "Show HOLD TO AIM button",
        Config.Aimbot, "MobileMode", function(val)
            if val and Config.Aimbot.Enabled then
                BuildMobileAimPanel()
            else
                DestroyPanel("MobileAimPanel")
            end
        end)

    MakeToggle(310, "🛡", "Auto Block",
        "Auto-F on enemy M1",
        Config.Autoblock, "Enabled", nil)

    MakeToggle(372, "👁", "FOV Circle",
        "Visualize aim radius",
        Config.Aimbot, "ShowFOV", function(val)
            if val and Config.Aimbot.Enabled then
                BuildFOVCircle()
            else
                if State.FOVCircle then
                    State.FOVCircle:Destroy()
                    State.FOVCircle = nil
                end
            end
        end)

    local Footer = Instance.new("TextLabel")
    Footer.Text             = "by Axiom  •  ⚡ icon to hide"
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

    -- Hook Dash PC
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

    -- Aimbot H key PC
    if not Config.Aimbot.MobileMode and Config.Aimbot.Enabled then
        if input.KeyCode == Config.Aimbot.AimKey then
            State.AimHeld = true
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if not Config.Aimbot.MobileMode and input.KeyCode == Config.Aimbot.AimKey then
        State.AimHeld = false
    end
end)

Players.PlayerRemoving:Connect(function(p)
    if State.HookTarget == p then SetHookTarget(nil) end
end)

-- ========================
-- HEARTBEAT
-- ========================
RunService.Heartbeat:Connect(function()
    -- Hook target cleanup
    if State.HookTarget and not IsAlive(State.HookTarget) then
        SetHookTarget(nil)
    end
    -- Update highlight adornee on respawn
    if State.TargetHL and State.HookTarget then
        local c = GetChar(State.HookTarget)
        if c then State.TargetHL.Adornee = c end
    end

    RunAimbot()
    RunAutoblock()
end)

print("[Axiom] v5 loaded — ⚡ icon top-left to show/hide menu")
