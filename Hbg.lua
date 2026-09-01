-- Hero Battleground | Full Suite v4 — Mobile Edition
-- Executor: Arceus X / Delta / Fluxus Mobile
-- by Axiom

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- ========================
-- CONFIG
-- ========================
local Config = {
    HookDash = {
        Enabled      = false,
        MobileMode   = false,   -- bật thì hiện mobile panel
        MaxRange     = 22,
        ArcRadius    = 5,
        DashSpeed    = 0.18,
        BehindOffset = 5,
        ArcSteps     = 12,
        StepJitter   = 0.004,
        AutoM1       = true,
        -- PC keys (chỉ hoạt động khi MobileMode = false)
        TargetKey    = Enum.KeyCode.V,
        ActivateKey  = Enum.KeyCode.C,
    },
    Aimbot = {
        Enabled      = false,
        FOV          = 180,
        SmoothFactor = 0.13,
        AimKey       = Enum.UserInputType.MouseButton2,
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
    ESP = {
        Enabled = false,
    },
}

-- ========================
-- STATE
-- ========================
local State = {
    HookTarget   = nil,
    DashCooldown = false,
    BlockActive  = false,
    FOVCircle    = nil,
    MobilePanel  = nil,
}

local ESPBoxes = {}

-- ========================
-- UTILITY
-- ========================
local function GetCharacter(p)  return p and p.Character end
local function GetRootPart(p)
    local c = GetCharacter(p)
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end
local function GetHumanoid(p)
    local c = GetCharacter(p)
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function IsAlive(p)
    local h = GetHumanoid(p)
    return h and h.Health > 0
end
local function Dist(p)
    local a, b = GetRootPart(LocalPlayer), GetRootPart(p)
    return (a and b) and (a.Position - b.Position).Magnitude or math.huge
end

local function GetClosestToCursor()
    local best, bestD = nil, Config.Aimbot.FOV
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not IsAlive(p) then continue end
        local c = GetCharacter(p)
        if not c then continue end
        local part = c:FindFirstChild(Config.Aimbot.HitPart) or c:FindFirstChild("HumanoidRootPart")
        if not part then continue end
        local sp, on = Camera:WorldToViewportPoint(part.Position)
        if not on then continue end
        local d = (Vector2.new(sp.X, sp.Y) - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
        if d < bestD then bestD = d; best = p end
    end
    return best
end

-- Closest player theo world distance (mobile target lock)
local function GetClosestPlayerWorld()
    local best, bestD = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not IsAlive(p) then continue end
        local d = Dist(p)
        if d < bestD then bestD = d; best = p end
    end
    return best
end

local function GetPlayerLookingAt()
    local ray = Camera:ScreenPointToRay(Mouse.X, Mouse.Y)
    local rp  = RaycastParams.new()
    rp.FilterDescendantsInstances = {GetCharacter(LocalPlayer)}
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local res = Workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
    if res and res.Instance then
        local model = res.Instance:FindFirstAncestorOfClass("Model")
        if model then
            local p = Players:GetPlayerFromCharacter(model)
            if p and p ~= LocalPlayer then return p end
        end
    end
    return GetClosestToCursor()
end

-- ========================
-- HOOK DASH
-- ========================
local TargetHL = nil

local function SetHookTarget(player)
    if TargetHL then TargetHL:Destroy(); TargetHL = nil end
    State.HookTarget = player
    if not player then return end
    local c = GetCharacter(player)
    if not c then return end
    TargetHL = Instance.new("SelectionBox")
    TargetHL.Adornee             = c
    TargetHL.Color3              = Color3.fromRGB(255, 80, 80)
    TargetHL.LineThickness       = 0.04
    TargetHL.SurfaceTransparency = 0.6
    TargetHL.SurfaceColor3       = Color3.fromRGB(255, 50, 50)
    TargetHL.Parent              = Workspace
end

local function Bezier(p0, p1, p2, t)
    return (1-t)^2 * p0 + 2*(1-t)*t * p1 + t^2 * p2
end

local function PerformSideDash(target)
    if State.DashCooldown then return end
    local myRoot     = GetRootPart(LocalPlayer)
    local targetRoot = GetRootPart(target)
    if not myRoot or not targetRoot then return end
    if Dist(target) > Config.HookDash.MaxRange then return end

    State.DashCooldown = true

    local cfg  = Config.HookDash
    local p0   = myRoot.Position
    local tCF  = targetRoot.CFrame
    local side = (math.random(0,1) == 0) and 1 or -1

    local flank  = (tCF * CFrame.new(side * cfg.ArcRadius * 2.2, 0, 0)).Position
    local p1     = Vector3.new(flank.X, p0.Y, flank.Z)
    local behind = (tCF * CFrame.new(0, 0, cfg.BehindOffset)).Position
    local p2     = Vector3.new(behind.X, p0.Y, behind.Z)

    local steps    = cfg.ArcSteps
    local stepTime = cfg.DashSpeed / steps
    local char     = GetCharacter(LocalPlayer)

    local function DoStep(i)
        if not char or not char.Parent then
            State.DashCooldown = false
            return
        end
        local root = GetRootPart(LocalPlayer)
        local tgt  = GetRootPart(target)
        if not root or not tgt then
            State.DashCooldown = false
            return
        end
        local t   = i / steps
        local pos = Bezier(p0, p1, p2, t)
        local look = Vector3.new(tgt.Position.X, pos.Y, tgt.Position.Z)
        pcall(function() root.CFrame = CFrame.new(pos, look) end)

        if i >= steps then
            if cfg.AutoM1 then
                task.delay(0.06, function()
                    local vim = game:GetService("VirtualInputManager")
                    if vim then
                        pcall(function()
                            vim:SendMouseButtonEvent(Mouse.X, Mouse.Y, 0, true, game, 0)
                            task.delay(0.09, function()
                                vim:SendMouseButtonEvent(Mouse.X, Mouse.Y, 0, false, game, 0)
                            end)
                        end)
                    end
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
-- MOBILE HOOK DASH PANEL
-- ========================
local function DestroyMobilePanel()
    if State.MobilePanel then
        State.MobilePanel:Destroy()
        State.MobilePanel = nil
    end
end

local function BuildMobilePanel()
    DestroyMobilePanel()
    if not Config.HookDash.MobileMode then return end

    local sg = Instance.new("ScreenGui")
    sg.Name           = "AxiomMobilePanel"
    sg.ResetOnSpawn   = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent         = LocalPlayer.PlayerGui

    State.MobilePanel = sg

    -- Panel nền — góc dưới phải, draggable
    local Panel = Instance.new("Frame")
    Panel.Name            = "HookPanel"
    Panel.Size            = UDim2.new(0, 200, 0, 110)
    Panel.Position        = UDim2.new(1, -220, 1, -180)
    Panel.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
    Panel.BorderSizePixel = 0
    Panel.Active          = true
    Panel.Draggable       = true
    Panel.Parent          = sg
    Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)

    local PanelStroke = Instance.new("UIStroke")
    PanelStroke.Color     = Color3.fromRGB(200, 45, 45)
    PanelStroke.Thickness = 1.5
    PanelStroke.Parent    = Panel

    -- Title strip
    local Strip = Instance.new("Frame")
    Strip.Size            = UDim2.new(1, 0, 0, 28)
    Strip.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    Strip.BorderSizePixel = 0
    Strip.Parent          = Panel
    Instance.new("UICorner", Strip).CornerRadius = UDim.new(0, 12)

    local StripPatch = Instance.new("Frame")
    StripPatch.Size            = UDim2.new(1, 0, 0, 8)
    StripPatch.Position        = UDim2.new(0, 0, 1, -8)
    StripPatch.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    StripPatch.BorderSizePixel = 0
    StripPatch.Parent          = Strip

    local StripLbl = Instance.new("TextLabel")
    StripLbl.Text      = "⚡ Hook Dash"
    StripLbl.Font      = Enum.Font.GothamBold
    StripLbl.TextSize  = 12
    StripLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    StripLbl.Size      = UDim2.new(1, 0, 1, 0)
    StripLbl.BackgroundTransparency = 1
    StripLbl.Parent    = Strip

    -- Target indicator label
    local TargetLbl = Instance.new("TextLabel")
    TargetLbl.Name      = "TargetLbl"
    TargetLbl.Text      = "Target: None"
    TargetLbl.Font      = Enum.Font.Gotham
    TargetLbl.TextSize  = 11
    TargetLbl.TextColor3 = Color3.fromRGB(160, 160, 170)
    TargetLbl.Size      = UDim2.new(1, -12, 0, 18)
    TargetLbl.Position  = UDim2.new(0, 8, 0, 32)
    TargetLbl.BackgroundTransparency = 1
    TargetLbl.TextXAlignment = Enum.TextXAlignment.Left
    TargetLbl.Parent    = Panel

    -- Button factory
    local function MakeBtn(xPos, w, label, color, callback)
        local Btn = Instance.new("TextButton")
        Btn.Size            = UDim2.new(0, w, 0, 40)
        Btn.Position        = UDim2.new(0, xPos, 0, 58)
        Btn.BackgroundColor3 = color
        Btn.BorderSizePixel = 0
        Btn.Text            = label
        Btn.Font            = Enum.Font.GothamBold
        Btn.TextSize        = 13
        Btn.TextColor3      = Color3.fromRGB(255, 255, 255)
        Btn.AutoButtonColor = false
        Btn.Parent          = Panel
        Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 8)

        -- Press feedback
        Btn.MouseButton1Down:Connect(function()
            TweenService:Create(Btn, TweenInfo.new(0.08), {
                BackgroundColor3 = color:Lerp(Color3.fromRGB(0,0,0), 0.25)
            }):Play()
        end)
        Btn.MouseButton1Up:Connect(function()
            TweenService:Create(Btn, TweenInfo.new(0.08), {
                BackgroundColor3 = color
            }):Play()
        end)
        Btn.MouseButton1Click:Connect(callback)
        return Btn
    end

    -- TARGET button — lock nearest player
    MakeBtn(8, 88, "🎯 TARGET", Color3.fromRGB(40, 40, 55), function()
        -- Mobile: lock closest player by world distance
        local t = GetClosestPlayerWorld()
        SetHookTarget(t)
        local lbl = Panel:FindFirstChild("TargetLbl")
        if lbl then
            lbl.Text = t and ("Target: " .. t.Name) or "Target: None"
            lbl.TextColor3 = t
                and Color3.fromRGB(255, 100, 100)
                or  Color3.fromRGB(160, 160, 170)
        end
    end)

    -- DASH button
    MakeBtn(104, 88, "⚡ DASH", Color3.fromRGB(190, 35, 35), function()
        if State.HookTarget and IsAlive(State.HookTarget) then
            PerformSideDash(State.HookTarget)
        else
            -- Jika target sudah mati, reset label
            local lbl = Panel:FindFirstChild("TargetLbl")
            if lbl then
                lbl.Text      = "Target: None"
                lbl.TextColor3 = Color3.fromRGB(160, 160, 170)
            end
            SetHookTarget(nil)
        end
    end)

    -- Heartbeat: sync target label nếu target chết
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not State.MobilePanel or not State.MobilePanel.Parent then
            conn:Disconnect()
            return
        end
        local lbl = Panel:FindFirstChild("TargetLbl")
        if not lbl then return end
        if State.HookTarget then
            if not IsAlive(State.HookTarget) then
                SetHookTarget(nil)
                lbl.Text       = "Target: None"
                lbl.TextColor3 = Color3.fromRGB(160, 160, 170)
            else
                lbl.Text = "Target: " .. State.HookTarget.Name
            end
        end
    end)
end

-- ========================
-- AIMBOT + FOV CIRCLE
-- ========================
local function BuildFOVCircle()
    if State.FOVCircle then State.FOVCircle:Destroy(); State.FOVCircle = nil end
    if not Config.Aimbot.ShowFOV then return end

    local sg = Instance.new("ScreenGui")
    sg.Name           = "AxiomFOV"
    sg.ResetOnSpawn   = false
    sg.IgnoreGuiInset = true
    sg.Parent         = LocalPlayer.PlayerGui

    local d = Instance.new("Frame")
    local r = Config.Aimbot.FOV
    d.Size        = UDim2.new(0, r*2, 0, r*2)
    d.AnchorPoint = Vector2.new(0.5, 0.5)
    d.Position    = UDim2.new(0.5, 0, 0.5, 0)
    d.BackgroundTransparency = 1
    d.Parent      = sg

    local ring = Instance.new("Frame")
    ring.Size = UDim2.new(1,0,1,0)
    ring.BackgroundTransparency = 1
    ring.BorderSizePixel = 0
    ring.Parent = d
    Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)

    local stroke = Instance.new("UIStroke")
    stroke.Color        = Color3.fromRGB(255, 80, 80)
    stroke.Thickness    = 1.2
    stroke.Transparency = 0.3
    stroke.Parent       = ring

    State.FOVCircle = sg

    RunService.RenderStepped:Connect(function()
        if not State.FOVCircle or not State.FOVCircle.Parent then return end
        d.Position = UDim2.new(0, Mouse.X, 0, Mouse.Y)
    end)
end

local function RunAimbot()
    if not Config.Aimbot.Enabled then return end
    if not UserInputService:IsMouseButtonPressed(Config.Aimbot.AimKey) then return end
    local target = GetClosestToCursor()
    if not target then return end
    local c = GetCharacter(target)
    if not c then return end
    local part = c:FindFirstChild(Config.Aimbot.HitPart) or c:FindFirstChild("HumanoidRootPart")
    if not part then return end
    local sp, on = Camera:WorldToViewportPoint(part.Position)
    if not on then return end
    local delta = (Vector2.new(sp.X,sp.Y) - Vector2.new(Mouse.X,Mouse.Y)) * Config.Aimbot.SmoothFactor
    pcall(function() mousemoverel(delta.X, delta.Y) end)
end

-- ========================
-- AUTOBLOCK
-- ========================
local function IsM1Incoming(player)
    local c = GetCharacter(player)
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
    local er = GetRootPart(player)
    local mr = GetRootPart(LocalPlayer)
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
    local vim = game:GetService("VirtualInputManager")
    if vim then
        pcall(function() vim:SendKeyEvent(down, Enum.KeyCode.F, false, game) end)
    end
end

local function RunAutoblock()
    if not Config.Autoblock.Enabled or State.BlockActive then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not IsAlive(p) then continue end
        if Dist(p) > Config.Autoblock.MaxRange then continue end
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
-- ESP
-- ========================
local function IsValidPlayerChar(model)
    if not model then return false end
    local p = Players:GetPlayerFromCharacter(model)
    return p ~= nil and p ~= LocalPlayer
end

local function CreateESPBox(player)
    if ESPBoxes[player] then return end
    local char = GetCharacter(player)
    if not char or not IsValidPlayerChar(char) then return end
    local box = Instance.new("SelectionBox")
    box.Adornee             = char
    box.Color3              = Color3.fromRGB(255, 80, 80)
    box.LineThickness       = 0.03
    box.SurfaceTransparency = 0.85
    box.SurfaceColor3       = Color3.fromRGB(255, 50, 50)
    box.Parent              = Workspace
    ESPBoxes[player]        = box
end

local function RemoveESPBox(player)
    if ESPBoxes[player] then
        ESPBoxes[player]:Destroy()
        ESPBoxes[player] = nil
    end
end

local function UpdateESP()
    if not Config.ESP.Enabled then
        for p in pairs(ESPBoxes) do RemoveESPBox(p) end
        return
    end
    local valid = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        valid[p] = true
        local char = GetCharacter(p)
        if not char or Players:GetPlayerFromCharacter(char) ~= p or not IsAlive(p) then
            RemoveESPBox(p); continue
        end
        if not ESPBoxes[p] then
            CreateESPBox(p)
        elseif ESPBoxes[p].Adornee ~= char then
            ESPBoxes[p].Adornee = char
        end
    end
    for p in pairs(ESPBoxes) do
        if not valid[p] then RemoveESPBox(p) end
    end
end

-- ========================
-- MAIN MENU
-- ========================
local function BuildMenu()
    local old = LocalPlayer.PlayerGui:FindFirstChild("AxiomMenu")
    if old then old:Destroy() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name           = "AxiomMenu"
    ScreenGui.ResetOnSpawn   = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent         = LocalPlayer.PlayerGui

    -- Frame lebih tinggi untuk mobile toggle row
    local Frame = Instance.new("Frame")
    Frame.Name             = "MainFrame"
    Frame.Size             = UDim2.new(0, 250, 0, 490)
    Frame.Position         = UDim2.new(0, 20, 0.5, -245)
    Frame.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    Frame.BorderSizePixel  = 0
    Frame.Active           = true
    Frame.Draggable        = true
    Frame.Parent           = ScreenGui
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 10)

    local Stroke = Instance.new("UIStroke")
    Stroke.Color     = Color3.fromRGB(200, 45, 45)
    Stroke.Thickness = 1.5
    Stroke.Parent    = Frame

    -- Title bar
    local TitleBar = Instance.new("Frame")
    TitleBar.Size             = UDim2.new(1, 0, 0, 38)
    TitleBar.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    TitleBar.BorderSizePixel  = 0
    TitleBar.Parent           = Frame
    Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

    local Patch = Instance.new("Frame")
    Patch.Size             = UDim2.new(1, 0, 0, 10)
    Patch.Position         = UDim2.new(0, 0, 1, -10)
    Patch.BackgroundColor3 = Color3.fromRGB(190, 35, 35)
    Patch.BorderSizePixel  = 0
    Patch.Parent           = TitleBar

    local TitleLbl = Instance.new("TextLabel")
    TitleLbl.Text      = "⚡  AXIOM SUITE"
    TitleLbl.Font      = Enum.Font.GothamBold
    TitleLbl.TextSize  = 14
    TitleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    TitleLbl.Size      = UDim2.new(1, 0, 1, 0)
    TitleLbl.BackgroundTransparency = 1
    TitleLbl.Parent    = TitleBar

    local SubLbl = Instance.new("TextLabel")
    SubLbl.Text      = "Hero Battleground  •  v4 Mobile"
    SubLbl.Font      = Enum.Font.Gotham
    SubLbl.TextSize  = 10
    SubLbl.TextColor3 = Color3.fromRGB(120, 120, 135)
    SubLbl.Size      = UDim2.new(1, -16, 0, 14)
    SubLbl.Position  = UDim2.new(0, 10, 0, 42)
    SubLbl.BackgroundTransparency = 1
    SubLbl.TextXAlignment = Enum.TextXAlignment.Left
    SubLbl.Parent    = Frame

    -- Toggle factory
    local function MakeToggle(yPos, icon, label, desc, cfgTable, cfgKey, onToggle)
        local Row = Instance.new("Frame")
        Row.Size             = UDim2.new(1, -20, 0, 52)
        Row.Position         = UDim2.new(0, 10, 0, yPos)
        Row.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        Row.BorderSizePixel  = 0
        Row.Parent           = Frame
        Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 7)

        local RowStroke = Instance.new("UIStroke")
        RowStroke.Color     = Color3.fromRGB(35, 35, 48)
        RowStroke.Thickness = 1
        RowStroke.Parent    = Row

        local IconLbl = Instance.new("TextLabel")
        IconLbl.Text      = icon
        IconLbl.Font      = Enum.Font.GothamBold
        IconLbl.TextSize  = 16
        IconLbl.TextColor3 = Color3.fromRGB(200, 45, 45)
        IconLbl.Size      = UDim2.new(0, 30, 1, 0)
        IconLbl.Position  = UDim2.new(0, 8, 0, 0)
        IconLbl.BackgroundTransparency = 1
        IconLbl.Parent    = Row

        local MainLbl = Instance.new("TextLabel")
        MainLbl.Text      = label
        MainLbl.Font      = Enum.Font.GothamBold
        MainLbl.TextSize  = 12
        MainLbl.TextColor3 = Color3.fromRGB(230, 230, 230)
        MainLbl.Size      = UDim2.new(1, -90, 0, 22)
        MainLbl.Position  = UDim2.new(0, 44, 0, 6)
        MainLbl.BackgroundTransparency = 1
        MainLbl.TextXAlignment = Enum.TextXAlignment.Left
        MainLbl.Parent    = Row

        local DescLbl = Instance.new("TextLabel")
        DescLbl.Text      = desc
        DescLbl.Font      = Enum.Font.Gotham
        DescLbl.TextSize  = 10
        DescLbl.TextColor3 = Color3.fromRGB(95, 95, 115)
        DescLbl.Size      = UDim2.new(1, -90, 0, 16)
        DescLbl.Position  = UDim2.new(0, 44, 0, 28)
        DescLbl.BackgroundTransparency = 1
        DescLbl.TextXAlignment = Enum.TextXAlignment.Left
        DescLbl.Parent    = Row

        local PillBg = Instance.new("Frame")
        PillBg.Size            = UDim2.new(0, 44, 0, 22)
        PillBg.Position        = UDim2.new(1, -52, 0.5, -11)
        PillBg.BorderSizePixel = 0
        PillBg.Parent          = Row
        Instance.new("UICorner", PillBg).CornerRadius = UDim.new(1, 0)

        local PillDot = Instance.new("Frame")
        PillDot.Size           = UDim2.new(0, 16, 0, 16)
        PillDot.BorderSizePixel = 0
        PillDot.Parent         = PillBg
        Instance.new("UICorner", PillDot).CornerRadius = UDim.new(1, 0)

        local function Refresh()
            local on = cfgTable[cfgKey]
            TweenService:Create(PillBg, TweenInfo.new(0.15), {
                BackgroundColor3 = on
                    and Color3.fromRGB(200, 40, 40)
                    or  Color3.fromRGB(45, 45, 58)
            }):Play()
            TweenService:Create(PillDot, TweenInfo.new(0.15), {
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
        Btn.Size               = UDim2.new(1, 0, 1, 0)
        Btn.BackgroundTransparency = 1
        Btn.Text               = ""
        Btn.Parent             = Row

        Btn.MouseButton1Click:Connect(function()
            cfgTable[cfgKey] = not cfgTable[cfgKey]
            Refresh()
            if onToggle then onToggle(cfgTable[cfgKey]) end
        end)
    end

    -- Row 1: Hook Dash enable
    MakeToggle(62,  "⚡", "Hook Dash",    "V: Lock  |  C: Arc Dash (PC)",
        Config.HookDash,  "Enabled", nil)

    -- Row 2: Mobile Mode — bật thì show panel nổi
    MakeToggle(124, "📱", "Mobile Mode",  "Show TARGET + DASH buttons",
        Config.HookDash,  "MobileMode", function(val)
            if val then
                BuildMobilePanel()
            else
                DestroyMobilePanel()
            end
        end)

    -- Row 3: Aimbot
    MakeToggle(186, "🎯", "Aimbot",       "RMB: Smooth Aim to Head",
        Config.Aimbot,    "Enabled", nil)

    -- Row 4: Auto Block
    MakeToggle(248, "🛡", "Auto Block",   "Auto-F on enemy M1",
        Config.Autoblock, "Enabled", nil)

    -- Row 5: Box ESP
    MakeToggle(310, "📦", "Box ESP",      "Players only — no skill boxes",
        Config.ESP,       "Enabled", function(val)
            if not val then
                for p in pairs(ESPBoxes) do RemoveESPBox(p) end
            end
        end)

    -- Row 6: FOV Circle
    MakeToggle(372, "👁", "FOV Circle",   "Visualize aim radius",
        Config.Aimbot,    "ShowFOV", function(val)
            if val then
                BuildFOVCircle()
            else
                if State.FOVCircle then
                    State.FOVCircle:Destroy()
                    State.FOVCircle = nil
                end
            end
        end)

    local Footer = Instance.new("TextLabel")
    Footer.Text      = "by Axiom  •  drag to move"
    Footer.Font      = Enum.Font.Gotham
    Footer.TextSize  = 9
    Footer.TextColor3 = Color3.fromRGB(55, 55, 70)
    Footer.Size      = UDim2.new(1, 0, 0, 18)
    Footer.Position  = UDim2.new(0, 0, 1, -20)
    Footer.BackgroundTransparency = 1
    Footer.Parent    = Frame
end

-- ========================
-- INIT
-- ========================
BuildMenu()
BuildFOVCircle()

-- ========================
-- PC INPUT (chỉ active khi MobileMode = false)
-- ========================
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if Config.HookDash.MobileMode then return end  -- mobile panel handles it

    if input.KeyCode == Config.HookDash.TargetKey and Config.HookDash.Enabled then
        local t = GetPlayerLookingAt()
        SetHookTarget(t)
        print(t and ("[Axiom] Locked: "..t.Name) or "[Axiom] No target")
    end
    if input.KeyCode == Config.HookDash.ActivateKey and Config.HookDash.Enabled then
        if State.HookTarget and IsAlive(State.HookTarget) then
            PerformSideDash(State.HookTarget)
        end
    end
end)

Players.PlayerRemoving:Connect(function(p)
    if State.HookTarget == p then SetHookTarget(nil) end
    RemoveESPBox(p)
end)

-- ========================
-- HEARTBEAT
-- ========================
RunService.Heartbeat:Connect(function()
    if State.HookTarget and not IsAlive(State.HookTarget) then
        SetHookTarget(nil)
    end
    if TargetHL and State.HookTarget then
        local c = GetCharacter(State.HookTarget)
        if c then TargetHL.Adornee = c end
    end
    RunAimbot()
    RunAutoblock()
    UpdateESP()
end)

print("[Axiom] v4 Mobile loaded — Main menu active. Toggle Mobile Mode for Hook Dash panel.")
