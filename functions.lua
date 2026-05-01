-- cclosure.vip / vampireware functions module
-- GUI-agnostic: extracted gameplay logic from vampireware.lua
-- Usage:
--   local F = loadstring(game:HttpGet('https://raw.githubusercontent.com/anxiousgh/asdasdasdasdasd/main/functions.lua'))()
--   F.fly.toggle(); F.fly.setSpeed(80)
--   F.aimbot.setEnabled(true); F.aimbot.setFov(120); F.aimbot.setHitPart('Head')
--   F.esp.toggle(); F.esp.setBox(true)
-- See bottom of file for the full API table.

--// services
local HttpService      = game:GetService("HttpService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local plrs             = game:GetService("Players")
local lplr             = plrs.LocalPlayer
local Camera           = workspace.CurrentCamera

--// forward-declare the public API table so functions defined below can
--   reference it (otherwise `F.games` etc. resolve to a global lookup that
--   stays nil even after `local F = {}` further down).
local F

--// cached player list
local _cachedPlayers = plrs:GetPlayers()
plrs.PlayerAdded:Connect(function() _cachedPlayers = plrs:GetPlayers() end)
plrs.PlayerRemoving:Connect(function() task.defer(function() _cachedPlayers = plrs:GetPlayers() end) end)

--// no-op GUI stubs (the original script wired these to the legacy GUI;
--   we keep the calls to preserve behavior without doing anything visible)
local function setIndicator() end
local function refreshHud() end
local function showToast() end

--// shared state
local G = { speedValue = 2 }
local FLY_SPEED   = 60
local SPIN_SPEED  = 50
local ICE_SLIDE   = 0.98
local BLINK_DIST  = 20
local CUSTOM_FOV  = 70

local BHOP_CFG = {
    AIR_ACCEL              = 250,
    AIR_SPEED              = 50,
    AIR_MAX_SPEED          = 100,
    AIR_MAX_SPEED_FRIC     = 3,
    AIR_MAX_SPEED_FRIC_DEC = 1,
    AIR_FRICTION           = 0.05,
    FRICTION               = 3,
    GROUND_DECCEL          = 10,
    JUMP_VELOCITY          = 20,
}

local AimbotSettings = {
    Enabled=false, TeamCheck=false, VisibleCheck=false,
    TargetPart="HumanoidRootPart", Method="Mouse.Hit/Target", ClosestPart=false,
    FOVRadius=130, ShowFOV=false, ShowTarget=false,
    Prediction=false, PredictionAmount=0.165, HitChance=100,
}

local CamLockSettings = {
    Enabled=false, TeamCheck=false, VisibleCheck=false,
    TargetPart="Head", ClosestPart=false,
    Mode="Mouse", FOVRadius=200, ShowFOV=false,
    Prediction=false, PredictionAmount=0.165,
    Smoothing=0.25, Sticky=true,
}

local TrigSettings = {
    Enabled=false, TeamCheck=false, VisibleCheck=false,
    Prediction=false, PredictionAmount=0.1,
    ClickDelay=0, FOVRadius=20, ShowFOV=false,
    TargetPart="HumanoidRootPart", ShowTarget=false,
}

local RageSettings = {
    TargetUserId=nil, TargetPlayer=nil, SkipKnocked=false,
    ShowLine=true, ShowOutline=true, LineOrigin="Bottom", FaceTarget=false,
    Orbit=false, OrbitDistance=15, OrbitSpeed=60, OrbitHeight=5,
    AutoShoot=false, AutoShootDist=50, AutoShootVis=true, AutoShootRequireTool=false,
    AutoShootCooldown=100, EquipDelay=0.5, FFCheck=true,
    SilentForce=false, SilentMethod="All",
    SpeedPanic=false, SpeedPanicVal=0,
    TpBehind=false, TpBehindDist=0,
    CamSnap=false, CamSmoothing=0.15,
    AutoSwitch=true, NotifyTarget=true,
    SwitchByMouse=false,
}

local EspSettings = {
    Enabled=false, BoxESP=false, NameESP=false, HealthESP=false, HealthNum=false,
    DistanceESP=false, TracerESP=false, SkeletonESP=false, TeamCheck=false,
    ChamsEnabled=false, HeldItem=false, SelfESP=false,
    RadarEnabled=false, XCTEnabled=false, TracerHistory=false, TracerHistLen=2,
    BoxStyle="Corners", TracerOrigin="Bottom", ChamsStyle="Overlay",
}

local _rbTargetList = {}

-- ============================================================
--  VISIBILITY HELPER (cache raw Raycast before any hooks)
-- ============================================================
local rawRaycast = workspace.Raycast
local _visParams = RaycastParams.new()
_visParams.FilterType = Enum.RaycastFilterType.Exclude

local function isReallyVisible(fromPos, toPos, ignoreList)
    local dir = toPos - fromPos
    local dist = dir.Magnitude
    if dist < 0.1 then return true end
    _visParams.FilterDescendantsInstances = ignoreList
    local remaining = dist
    local origin = fromPos
    local unit = dir.Unit
    for _ = 1, 3 do
        if remaining <= 0 then break end
        local result = rawRaycast(workspace, origin, unit * remaining, _visParams)
        if not result then return true end
        local hit = result.Instance
        if hit.Transparency >= 0.5 or not hit.CanCollide or hit.CastShadow == false then
            local stepped = (result.Position - origin).Magnitude + 0.05
            origin = origin + unit * stepped
            remaining = remaining - stepped
        else
            return false
        end
    end
    return true
end

-- ============================================================
--  MOVEMENT: FLY / SPEED / BHOP / INFJUMP / ANTIAFK / CLICKTP
-- ============================================================
local function stopFly()
    G.flyActive=false; if G.flyConn then G.flyConn:Disconnect(); G.flyConn=nil end
end
local function startFly()
    local char=lplr.Character; if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    G.flyActive=true
    G.flyConn=RunService.Heartbeat:Connect(function(dt)
        char=lplr.Character; if not char then stopFly(); return end
        hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then stopFly(); return end
        local cam=workspace.CurrentCamera; local dir=Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W)         then dir+=cam.CFrame.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.S)         then dir-=cam.CFrame.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.A)         then dir-=cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D)         then dir+=cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then dir+=Vector3.new(0,1,0)     end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir-=Vector3.new(0,1,0)     end
        hrp.AssemblyLinearVelocity=Vector3.zero; hrp.AssemblyAngularVelocity=Vector3.zero
        if UserInputService:GetFocusedTextBox() then return end
        if dir.Magnitude>0 then hrp.CFrame=hrp.CFrame+dir.Unit*FLY_SPEED*dt end
    end)
end

local function stopSpeed()
    G.speedActive=false; if G.speedConn then G.speedConn:Disconnect(); G.speedConn=nil end
end
local function startSpeed(mult)
    local char=lplr.Character; if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    G.speedActive=true; G.speedValue=mult or 2
    G.speedConn=RunService.Heartbeat:Connect(function(dt)
        char=lplr.Character; if UserInputService:GetFocusedTextBox() then return end
        if not char then stopSpeed(); return end
        hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then stopSpeed(); return end
        local dir=Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir+=workspace.CurrentCamera.CFrame.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir-=workspace.CurrentCamera.CFrame.LookVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir-=workspace.CurrentCamera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir+=workspace.CurrentCamera.CFrame.RightVector end
        dir=Vector3.new(dir.X,0,dir.Z)
        if dir.Magnitude>0 then hrp.CFrame=hrp.CFrame+dir.Unit*(16*(G.speedValue-1))*dt end
    end)
end

-- bhop: pure AssemblyLinearVelocity, Quake-style air accel
local _bhopStepConn, _bhopJumpConn, _bhopAirFric, _bhopVel = nil, nil, 0, Vector3.zero

local function bhopApplyFriction(dt, modifier)
    local speed = _bhopVel.Magnitude
    if speed < 0.1 then _bhopVel = Vector3.zero; return end
    local control = math.max(speed, BHOP_CFG.GROUND_DECCEL)
    local drop = control * BHOP_CFG.FRICTION * dt * (modifier or 1)
    local newSpeed = math.max(speed - drop, 0)
    _bhopVel = _bhopVel * (newSpeed / speed)
end
local function bhopAirAccel(dt, wishDir)
    local wishSpeed = BHOP_CFG.AIR_SPEED
    local currSpeed = _bhopVel:Dot(wishDir)
    local addSpeed  = wishSpeed - currSpeed
    if addSpeed <= 0 then return end
    local accelSpeed = math.min(BHOP_CFG.AIR_ACCEL * dt * wishSpeed, addSpeed)
    _bhopVel = _bhopVel + wishDir * accelSpeed
end

local function stopBhop()
    G.bhopActive=false
    if _bhopStepConn then _bhopStepConn:Disconnect(); _bhopStepConn=nil end
    if _bhopJumpConn then _bhopJumpConn:Disconnect(); _bhopJumpConn=nil end
    if G.bhopConn    then G.bhopConn:Disconnect();    G.bhopConn   =nil end
    _bhopVel=Vector3.zero; _bhopAirFric=0
    local char=lplr.Character
    if char then
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate=true end
    end
end

local function startBhop()
    G.bhopActive=true; _bhopVel=Vector3.zero; _bhopAirFric=0
    local function setup(char)
        if not char then return end
        local hrp=char:WaitForChild("HumanoidRootPart",5); if not hrp then return end
        local hum=char:FindFirstChildOfClass("Humanoid");   if not hum then return end
        hum.AutoRotate=false
        _bhopVel=Vector3.new(hrp.AssemblyLinearVelocity.X,0,hrp.AssemblyLinearVelocity.Z)
        if _bhopJumpConn then _bhopJumpConn:Disconnect() end
        local _lastJump=0
        _bhopJumpConn=RunService.Heartbeat:Connect(function()
            if not G.bhopActive then return end
            local state=hum:GetState()
            local grounded=state==Enum.HumanoidStateType.Running
                or state==Enum.HumanoidStateType.RunningNoPhysics
                or state==Enum.HumanoidStateType.Landed
            if grounded and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                local now=tick()
                if now-_lastJump>0.1 then
                    _lastJump=now
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    hrp.AssemblyLinearVelocity=Vector3.new(
                        hrp.AssemblyLinearVelocity.X, BHOP_CFG.JUMP_VELOCITY, hrp.AssemblyLinearVelocity.Z)
                end
            end
        end)
        if _bhopStepConn then _bhopStepConn:Disconnect() end
        _bhopStepConn=RunService.RenderStepped:Connect(function(dt)
            if not G.bhopActive then return end
            if not hrp or not hrp.Parent then return end
            local cam=workspace.CurrentCamera; local look=cam.CFrame.LookVector
            hrp.CFrame=CFrame.new(hrp.Position, hrp.Position+Vector3.new(look.X,0,look.Z))
            local fwd =(UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)+(UserInputService:IsKeyDown(Enum.KeyCode.S) and -1 or 0)
            local side=(UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)+(UserInputService:IsKeyDown(Enum.KeyCode.A) and -1 or 0)
            local wishDir=Vector3.zero
            if fwd~=0 or side~=0 then
                local cf=hrp.CFrame
                wishDir=(cf.LookVector*fwd+cf.RightVector*side)*Vector3.new(1,0,1)
                if wishDir.Magnitude>0 then wishDir=wishDir.Unit end
            end
            local state=hum:GetState()
            local inAir=state==Enum.HumanoidStateType.Freefall or state==Enum.HumanoidStateType.Jumping
            local planeSpeed=_bhopVel.Magnitude
            if inAir then
                if planeSpeed>BHOP_CFG.AIR_MAX_SPEED then _bhopAirFric=BHOP_CFG.AIR_MAX_SPEED_FRIC end
                if _bhopAirFric>0 then
                    local sub=BHOP_CFG.AIR_MAX_SPEED_FRIC_DEC*dt*60
                    bhopApplyFriction(dt, math.max(1,_bhopAirFric/BHOP_CFG.FRICTION))
                    _bhopAirFric=math.max(0,_bhopAirFric-sub)
                else
                    local s2=_bhopVel.Magnitude
                    if s2>0 then
                        local drop=s2*BHOP_CFG.AIR_FRICTION*dt
                        _bhopVel=_bhopVel*math.max(0,(s2-drop)/s2)
                    end
                end
                if wishDir.Magnitude>0 then bhopAirAccel(dt,wishDir) end
            else
                _bhopAirFric=0
                _bhopVel=Vector3.new(hrp.AssemblyLinearVelocity.X,0,hrp.AssemblyLinearVelocity.Z)
                bhopApplyFriction(dt)
            end
            hrp.AssemblyLinearVelocity=Vector3.new(_bhopVel.X, hrp.AssemblyLinearVelocity.Y, _bhopVel.Z)
        end)
    end
    setup(lplr.Character)
    G.bhopConn=lplr.CharacterAdded:Connect(function(c)
        if G.bhopActive then _bhopVel=Vector3.zero; setup(c) end
    end)
end

local function stopInfJump()
    G.infJumpActive=false; if G.infJumpConn then G.infJumpConn:Disconnect(); G.infJumpConn=nil end
end
local function startInfJump()
    G.infJumpActive=true
    G.infJumpConn=UserInputService.JumpRequest:Connect(function()
        local char=lplr.Character; if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end

local function stopAntiAfk()
    G.antiAfkActive=false
    if G.antiAfkConn then G.antiAfkConn:Disconnect(); G.antiAfkConn=nil end
    if G.antiAfkDisabled then
        for _, conn in ipairs(G.antiAfkDisabled) do pcall(function() conn:Enable() end) end
        G.antiAfkDisabled = nil
    end
end
local function startAntiAfk()
    G.antiAfkActive=true
    local disabled = {}
    pcall(function()
        for _, conn in ipairs(getconnections(lplr.Idled)) do
            conn:Disable(); table.insert(disabled, conn)
        end
    end)
    G.antiAfkDisabled = disabled
    local t=0
    G.antiAfkConn=RunService.Heartbeat:Connect(function(dt)
        t+=dt
        if t>=55 then
            t=0
            pcall(function() firesignal(lplr.Idled) end)
            pcall(function()
                local vim=game:GetService("VirtualInputManager")
                vim:SendKeyEvent(true,Enum.KeyCode.W,false,game)
                vim:SendKeyEvent(false,Enum.KeyCode.W,false,game)
            end)
        end
    end)
end

local function stopClickTp()
    G.clickTpActive=false; if G.clickTpConn then G.clickTpConn:Disconnect(); G.clickTpConn=nil end
end
local function startClickTp()
    G.clickTpActive=true
    G.clickTpConn=UserInputService.InputBegan:Connect(function(inp,gp)
        if gp then return end
        if inp.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        local cam=workspace.CurrentCamera; local ray=cam:ScreenPointToRay(inp.Position.X,inp.Position.Y)
        local result=workspace:Raycast(ray.Origin,ray.Direction*1000)
        if result then
            local lc=lplr.Character
            local hrp=lc and lc:FindFirstChild("HumanoidRootPart")
            if hrp then
                _uprightTp(lc, hrp, result.Position + Vector3.new(0, 3, 0), nil)
            end
        end
    end)
end

-- ============================================================
--  AUTO-RESPAWN / RESPAWN
-- ============================================================
-- strip a CFrame down to position + horizontal yaw so the player always
-- spawns upright (otherwise restoring a ragdolled CFrame leaves them lying
-- down for several seconds while the engine reconciles the state)
local function _uprightCF(cf)
    if not cf then return nil end
    local lv = cf.LookVector
    local horiz = Vector3.new(lv.X, 0, lv.Z)
    if horiz.Magnitude < 0.01 then horiz = Vector3.new(0, 0, -1) end
    horiz = horiz.Unit
    return CFrame.new(cf.Position, cf.Position + horiz)
end

-- force the new humanoid out of any ragdoll / sit / platform-stand state
-- the moment it spawns, so we don't lay on the floor briefly
local function _forceStanding(newChar)
    if not newChar then return end
    local hum = newChar:WaitForChild("Humanoid", 3)
    if not hum then return end
    pcall(function() hum.PlatformStand = false end)
    pcall(function() hum.Sit            = false end)
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    -- second nudge after a frame in case the game's own scripts re-set the state
    task.delay(0.1, function()
        if not hum.Parent then return end
        pcall(function() hum.PlatformStand = false end)
        pcall(function() hum.Sit            = false end)
        if hum:GetState() ~= Enum.HumanoidStateType.Running then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
    end)
end

-- generic upright-teleport helper used by every TP path so we never tip
-- over into a ragdoll on landing.
--   char     - lplr.Character (used for the standing fix)
--   hrp      - HumanoidRootPart (BasePart)
--   position - Vector3 destination
--   faceDir  - Vector3 to face (only horizontal component is used).
--              Pass nil to keep current horizontal facing.
local function _uprightTp(char, hrp, position, faceDir)
    local horiz
    if faceDir then
        horiz = Vector3.new(faceDir.X, 0, faceDir.Z)
    end
    if not horiz or horiz.Magnitude < 0.01 then
        local lv = hrp.CFrame.LookVector
        horiz = Vector3.new(lv.X, 0, lv.Z)
        if horiz.Magnitude < 0.01 then horiz = Vector3.new(0, 0, -1) end
    end
    horiz = horiz.Unit
    pcall(function()
        hrp.CFrame = CFrame.new(position, position + horiz)
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    if char then _forceStanding(char) end
end

local function hookAutoReChar(char)
    local hrp=char:WaitForChild("HumanoidRootPart",5); local hum=char:WaitForChild("Humanoid",5)
    if not hrp or not hum then return end
    local psc; psc=RunService.Heartbeat:Connect(function()
        if hrp and hrp.Parent then G.savedCFrame=hrp.CFrame else pcall(function() psc:Disconnect() end) end
    end)
    local dc; dc=hum.Died:Connect(function()
        dc:Disconnect(); pcall(function() psc:Disconnect() end)
        local cf=G.savedCFrame; if not G.autoReActive or not cf then return end
        lplr.CharacterAdded:Once(function(newChar)
            if not G.autoReActive then return end
            local newHrp=newChar:WaitForChild("HumanoidRootPart",5)
            if newHrp then task.wait(0.15); newHrp.CFrame = _uprightCF(cf) end
            _forceStanding(newChar)
        end)
    end)
    char.AncestryChanged:Connect(function()
        if not char.Parent then pcall(function() psc:Disconnect() end); pcall(function() dc:Disconnect() end) end
    end)
end
local function stopAutoRe()
    G.autoReActive=false; if G.autoReConn then G.autoReConn:Disconnect(); G.autoReConn=nil end
end
local function startAutoRe()
    if G.autoReActive then return end; G.autoReActive=true
    if lplr.Character then task.spawn(hookAutoReChar,lplr.Character) end
    G.autoReConn=lplr.CharacterAdded:Connect(function(c) if G.autoReActive then task.spawn(hookAutoReChar,c) end end)
end

local function cmdRe()
    local char=lplr.Character; if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart")
    if hrp then G.savedCFrame=hrp.CFrame end
    lplr.CharacterAdded:Once(function(newChar)
        if G.savedCFrame then
            local newHrp=newChar:WaitForChild("HumanoidRootPart",5)
            if newHrp then task.wait(0.1); newHrp.CFrame = _uprightCF(G.savedCFrame); G.savedCFrame=nil end
        end
        _forceStanding(newChar)
    end)
    local hum=char:FindFirstChildOfClass("Humanoid")
    task.spawn(function()
        pcall(function() replicatesignal(lplr.Kill) end)
        if hum then pcall(function() replicatesignal(hum.HealthChanged, 0) end) end
        if hum then pcall(function() hum.Health=0 end) end
        if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Dead) end) end
        if hum then pcall(function() hum:TakeDamage(math.huge) end) end
        if hum then pcall(function() hum.MaxHealth=0; hum.Health=0 end) end
        pcall(function() lplr:LoadCharacter() end)
    end)
end

-- ============================================================
--  NOCLIP / FULLBRIGHT / FREECAM / ZOOM
-- ============================================================
G.noclipOriginals = {}

local function stopNoclip()
    G.noclipActive=false
    pcall(function() RunService:UnbindFromRenderStep("NoclipStep") end)
    if G.noclipHBConn then G.noclipHBConn:Disconnect(); G.noclipHBConn=nil end
    if G.noclipConn and type(G.noclipConn)~="boolean" then G.noclipConn:Disconnect() end
    G.noclipConn=nil
    local char=lplr.Character
    if char then
        for _,p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = G.noclipOriginals[p]~=nil and G.noclipOriginals[p] or true
            end
        end
    end
    G.noclipOriginals={}
end
local function startNoclip()
    G.noclipActive=true; G.noclipOriginals={}
    local char=lplr.Character
    if char then
        for _,p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then G.noclipOriginals[p]=p.CanCollide end
        end
    end
    local function applyNoclip(c)
        if not c then return end
        for _,p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide=false end
        end
        pcall(function()
            for _,p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then
                    for _,conn in ipairs(getconnections(p:GetPropertyChangedSignal("CanCollide"))) do
                        if conn.LuaConnection then conn:Disable() end
                    end
                end
            end
        end)
    end
    RunService:BindToRenderStep("NoclipStep", Enum.RenderPriority.First.Value, function()
        if not G.noclipActive then return end
        local c=lplr.Character; if not c then return end
        for _,name in ipairs({"HumanoidRootPart","UpperTorso","Torso","Head","LowerTorso"}) do
            local p=c:FindFirstChild(name); if p then p.CanCollide=false end
        end
    end)
    G.noclipHBConn=RunService.Heartbeat:Connect(function()
        if not G.noclipActive then return end
        local c=lplr.Character; if not c then return end
        for _,p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide=false end
        end
    end)
    applyNoclip(char)
    G.noclipConn=lplr.CharacterAdded:Connect(function(newChar)
        task.wait(0.1)
        if G.noclipActive then
            for _,p in ipairs(newChar:GetDescendants()) do
                if p:IsA("BasePart") then G.noclipOriginals[p]=p.CanCollide end
            end
            applyNoclip(newChar)
        end
    end)
end

local function stopFullbright()
    G.fullbrightActive=false
    local L=game:GetService("Lighting")
    L.Brightness=1; L.ClockTime=14; L.GlobalShadows=true
    L.Ambient=Color3.fromRGB(70,70,70); L.OutdoorAmbient=Color3.fromRGB(128,128,128)
end
local function startFullbright()
    G.fullbrightActive=true
    local L=game:GetService("Lighting")
    L.Brightness=2; L.ClockTime=14; L.GlobalShadows=false
    L.Ambient=Color3.fromRGB(255,255,255); L.OutdoorAmbient=Color3.fromRGB(255,255,255)
    for _,v in ipairs(L:GetChildren()) do
        if v:IsA("Atmosphere") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("SunRaysEffect") then
            v.Enabled=false
        end
    end
end

local function stopFreecam()
    G.freecamActive=false
    if G.freecamConn then G.freecamConn:Disconnect(); G.freecamConn=nil end
    if G.freecamMouseConn then G.freecamMouseConn:Disconnect(); G.freecamMouseConn=nil end
    pcall(function() RunService:UnbindFromRenderStep("FreecamRender") end)
    workspace.CurrentCamera.CameraType=Enum.CameraType.Custom
    UserInputService.MouseBehavior=Enum.MouseBehavior.Default
    local char=lplr.Character
    if char then
        local hrp=char:FindFirstChild("HumanoidRootPart")
        if hrp then local bv=hrp:FindFirstChild("FreecamAnchor"); if bv then bv:Destroy() end end
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed=16; hum.JumpPower=50 end
    end
end
local function startFreecam()
    G.freecamActive=true
    local cam=workspace.CurrentCamera
    G.freecamCF=cam.CFrame
    cam.CameraType=Enum.CameraType.Scriptable
    do
        local char=lplr.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local bv=Instance.new("BodyVelocity")
                bv.Name="FreecamAnchor"; bv.Velocity=Vector3.zero
                bv.MaxForce=Vector3.new(1e5,1e5,1e5); bv.Parent=hrp
            end
            local hum=char:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed=0; hum.JumpPower=0 end
        end
    end
    local BASE_SPEED=40; local SPRINT_MULT=4
    local rotX=math.asin(math.clamp(cam.CFrame.LookVector.Y,-1,1))
    local rotY=math.atan2(-cam.CFrame.LookVector.X,-cam.CFrame.LookVector.Z)
    G.freecamMouseConn=UserInputService.InputChanged:Connect(function(inp)
        if not G.freecamActive then return end
        if inp.UserInputType==Enum.UserInputType.MouseMovement then
            rotY=rotY-inp.Delta.X*0.003
            rotX=math.clamp(rotX-inp.Delta.Y*0.003,-math.pi/2+0.01,math.pi/2-0.01)
        end
    end)
    RunService:BindToRenderStep("FreecamRender", Enum.RenderPriority.Camera.Value+1, function(dt)
        if not G.freecamActive then return end
        UserInputService.MouseBehavior=Enum.MouseBehavior.LockCurrentPosition
        local cf=CFrame.new(G.freecamCF.Position)*CFrame.fromEulerAnglesYXZ(rotX,rotY,0)
        local dir=Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir+=cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir-=cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir-=cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir+=cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir+=Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) then dir-=Vector3.new(0,1,0) end
        local sprint=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and SPRINT_MULT or 1
        if dir.Magnitude>0 then
            G.freecamCF=CFrame.new(G.freecamCF.Position+dir.Unit*BASE_SPEED*sprint*dt)
        end
        cam.CFrame=CFrame.new(G.freecamCF.Position)*CFrame.fromEulerAnglesYXZ(rotX,rotY,0)
    end)
end

local function stopZoom()
    G.zoomActive=false
    if G.zoomConn then G.zoomConn:Disconnect(); G.zoomConn=nil end
    lplr.CameraMaxZoomDistance=400
end
local function startZoom()
    G.zoomActive=true
    local function applyZoom() lplr.CameraMaxZoomDistance=500 end
    applyZoom()
    G.zoomConn=lplr.CharacterAdded:Connect(function() task.wait(0.1); applyZoom() end)
end

-- ============================================================
--  SPIN / FLIP / ICE / BLINK
-- ============================================================
local function stopFlip()
    G.flipActive=false
    if G._flipHb then G._flipHb:Disconnect(); G._flipHb=nil end
    if G._flipRs then G._flipRs:Disconnect(); G._flipRs=nil end
    if G._flipCharConn then G._flipCharConn:Disconnect(); G._flipCharConn=nil end
    local char=lplr.Character
    if char then
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.CameraOffset=Vector3.zero end
    end
end
local function startFlip()
    G.flipActive=true
    local function setup(char)
        if not char then return end
        local hrp=char:WaitForChild("HumanoidRootPart",5); if not hrp then return end
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.CameraOffset=Vector3.new(0,-4,0) end
        local _real={}; local _spoofing=false
        if G._flipHb then G._flipHb:Disconnect() end
        if G._flipRs then G._flipRs:Disconnect() end
        G._flipHb=RunService.Heartbeat:Connect(function()
            if not hrp or not hrp.Parent then return end
            _real[1]=hrp.CFrame; _real[2]=hrp.AssemblyLinearVelocity; _spoofing=true
            local look=hrp.CFrame.LookVector
            local yaw=math.atan2(look.X,look.Z)
            hrp.CFrame=CFrame.new(hrp.Position)*CFrame.fromEulerAnglesYXZ(0,yaw,0)*CFrame.Angles(math.pi,0,0)
        end)
        G._flipRs=RunService.RenderStepped:Connect(function()
            if _spoofing and _real[1] then
                if hrp and hrp.Parent then hrp.CFrame=_real[1]; hrp.AssemblyLinearVelocity=_real[2] end
                _spoofing=false
            end
        end)
    end
    setup(lplr.Character)
    G._flipCharConn=lplr.CharacterAdded:Connect(function(c)
        if G.flipActive then task.wait(0.1); setup(c) end
    end)
end

local function stopSpin()
    G.spinActive=false
    pcall(function() RunService:UnbindFromRenderStep("SpinStep") end)
    local char=lplr.Character
    if char then
        local hrp=char:FindFirstChild("HumanoidRootPart")
        if hrp then local bg=hrp:FindFirstChild("SpinGyro"); if bg then bg:Destroy() end end
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate=true end
    end
end
local function startSpin()
    G.spinActive=true
    local char=lplr.Character; if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local hum=char:FindFirstChildOfClass("Humanoid")
    if hum then hum.AutoRotate=false end
    local gyro=Instance.new("BodyAngularVelocity")
    gyro.Name="SpinGyro"; gyro.AngularVelocity=Vector3.new(0,SPIN_SPEED,0)
    gyro.MaxTorque=Vector3.new(0,1e6,0); gyro.Parent=hrp
end

local function stopIce()
    G.iceActive=false
    pcall(function() RunService:UnbindFromRenderStep("IceStep") end)
end
local function startIce()
    G.iceActive=true
    local vel=Vector3.zero
    RunService:BindToRenderStep("IceStep", Enum.RenderPriority.Character.Value, function(dt)
        if not G.iceActive then return end
        local char=lplr.Character; if not char then return end
        local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        local cam=workspace.CurrentCamera
        local dir=Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir+=cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir-=cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir-=cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir+=cam.CFrame.RightVector end
        dir=Vector3.new(dir.X,0,dir.Z)
        local accel=dir.Magnitude>0 and dir.Unit*60*dt or Vector3.zero
        vel=(vel+accel)*ICE_SLIDE
        if vel.Magnitude>0.1 then hrp.CFrame=hrp.CFrame+vel*dt end
    end)
end

local function cmdBlink()
    local char=lplr.Character; if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local cam=workspace.CurrentCamera
    local dist=BLINK_DIST
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={char}
    local origin=hrp.Position+Vector3.new(0,0.5,0)
    local dir=cam.CFrame.LookVector*dist
    local result=workspace:Raycast(origin,dir,params)
    local target=result and (result.Position+Vector3.new(0,2.5,0)) or (hrp.Position+dir)
    _uprightTp(char, hrp, target, cam.CFrame.LookVector)
end

-- ============================================================
--  CAMERA FOV
-- ============================================================
local function setFov(n)
    CUSTOM_FOV = n
    pcall(function() workspace.CurrentCamera.FieldOfView = n end)
end

-- ============================================================
--  PLAYERS: GOTO / VIEW / FLING
-- ============================================================
local function findPlayerByName(target)
    if not target then return nil end
    local p = plrs:FindFirstChild(target)
    if p then return p end
    local t = target:lower()
    for _,pp in ipairs(plrs:GetPlayers()) do
        if pp.Name:lower():find(t,1,true) or pp.DisplayName:lower():find(t,1,true) then return pp end
    end
    return nil
end

local function gotoPlayer(plr)
    if typeof(plr)=="string" then plr=findPlayerByName(plr) end
    if not plr then return end
    local tHrp=plr.Character and plr.Character:FindFirstChild("HumanoidRootPart"); if not tHrp then return end
    local lc=lplr.Character
    local hrp=lc and lc:FindFirstChild("HumanoidRootPart")
    if hrp then _uprightTp(lc, hrp, tHrp.Position + Vector3.new(3, 0, 0), tHrp.CFrame.LookVector) end
end

local _viewPrevSubject, _viewPrevType, _viewConn = nil, nil, nil
local function viewPlayer(plr)
    local cam=workspace.CurrentCamera
    if _viewConn then
        _viewConn:Disconnect(); _viewConn=nil
        if _viewPrevSubject then cam.CameraSubject=_viewPrevSubject; _viewPrevSubject=nil end
        if _viewPrevType    then cam.CameraType=_viewPrevType;       _viewPrevType=nil    end
        return
    end
    if typeof(plr)=="string" then plr=findPlayerByName(plr) end
    if not plr then return end
    local function applySubject()
        local tc=plr.Character; local hum=tc and tc:FindFirstChildOfClass("Humanoid")
        if hum then
            _viewPrevSubject=_viewPrevSubject or cam.CameraSubject; _viewPrevType=_viewPrevType or cam.CameraType
            cam.CameraSubject=hum; cam.CameraType=Enum.CameraType.Follow
        end
    end
    applySubject()
    _viewConn=plr.CharacterAdded:Connect(function() task.wait(0.1); applySubject() end)
end

-- spin-desync fling
local function flingPlayer(plr)
    if typeof(plr)=="string" then plr=findPlayerByName(plr) end
    if not plr then return end
    local target=plr
    local char=lplr.Character; if not char then return end
    local lhrp=char:FindFirstChild("HumanoidRootPart"); if not lhrp then return end
    local savedCF=lhrp.CFrame
    task.spawn(function()
        local _types={}; local _spoofing=false; local _angle=0
        local _hbConn,_rsConn
        _hbConn=RunService.Heartbeat:Connect(function()
            local c=lplr.Character; if not c then return end
            local h=c:FindFirstChild("HumanoidRootPart"); if not h then return end
            _types[1]=h.CFrame; _types[2]=h.AssemblyLinearVelocity; _spoofing=true; _angle=(_angle+45)%360
            h.CFrame=h.CFrame*CFrame.Angles(math.rad(_angle),math.rad(_angle*2),math.rad(_angle*0.5))
            h.AssemblyLinearVelocity=Vector3.new(1,1,1)*16384
        end)
        _rsConn=RunService.RenderStepped:Connect(function()
            if _spoofing and _types[1] then
                local c=lplr.Character; if not c then return end
                local h=c:FindFirstChild("HumanoidRootPart"); if not h then return end
                h.CFrame=_types[1]; h.AssemblyLinearVelocity=_types[2]; _spoofing=false
            end
        end)
        local deadline=tick()+2.5
        while tick()<deadline do
            local echar=target.Character; if not echar then break end
            local ehrp=echar:FindFirstChild("HumanoidRootPart"); if not ehrp then break end
            if not lplr.Character then break end
            local lh=lplr.Character:FindFirstChild("HumanoidRootPart"); if not lh then break end
            lh.CFrame=ehrp.CFrame*CFrame.new(0,0,0.5); task.wait(0.016)
        end
        if _hbConn then _hbConn:Disconnect() end
        if _rsConn then _rsConn:Disconnect() end
        if lplr.Character then
            local lh=lplr.Character:FindFirstChild("HumanoidRootPart")
            if lh then
                lh.Anchored=true; lh.AssemblyLinearVelocity=Vector3.zero; lh.CFrame=savedCF
                task.delay(1,function() if lh and lh.Parent then lh.Anchored=false end end)
            end
        end
    end)
end

-- ============================================================
--  AIMBOT CORE (drawing + closest target finder + namecall hook)
-- ============================================================
local A_fovCircle, A_targetBox
local cachedTarget, cachedHitPoint = nil, nil

if Drawing and Drawing.new then
    A_fovCircle = Drawing.new("Circle")
    A_fovCircle.Thickness=1; A_fovCircle.NumSides=100
    A_fovCircle.Radius=AimbotSettings.FOVRadius; A_fovCircle.Filled=false; A_fovCircle.Visible=false
    A_fovCircle.ZIndex=999; A_fovCircle.Transparency=1; A_fovCircle.Color=Color3.fromRGB(255,255,255)
    A_targetBox = Drawing.new("Circle")
    A_targetBox.Visible=false; A_targetBox.ZIndex=999; A_targetBox.Color=Color3.fromRGB(255,255,255)
    A_targetBox.Thickness=1; A_targetBox.Filled=true; A_targetBox.Radius=4; A_targetBox.NumSides=32
end

local function aimIsVisible(plr)
    local char=plr.Character; local lchar=lplr.Character
    if not char or not lchar then return false end
    local root=char:FindFirstChild(AimbotSettings.TargetPart) or char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local camPos=workspace.CurrentCamera.CFrame.Position
    local ignore={lchar,char}
    for _,p in ipairs(_cachedPlayers) do
        if p.Character and p.Character~=char and p.Character~=lchar then
            table.insert(ignore,p.Character)
        end
    end
    return isReallyVisible(camPos, root.Position, ignore)
end

local ALL_PARTS = {
    "Head","HumanoidRootPart","UpperTorso","LowerTorso",
    "RightUpperArm","LeftUpperArm","RightLowerArm","LeftLowerArm",
    "RightHand","LeftHand","RightUpperLeg","LeftUpperLeg",
    "RightLowerLeg","LeftLowerLeg","RightFoot","LeftFoot",
    "Torso","Left Arm","Right Arm","Left Leg","Right Leg",
}
local function partScreenDist(cam, part, mousePos)
    local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
    local t = (part.Position - ray.Origin):Dot(ray.Direction)
    local closestWorld = ray.Origin + ray.Direction * math.max(t, 0)
    local local_p = part.CFrame:PointToObjectSpace(closestWorld)
    local hs = part.Size * 0.5
    local clamped = Vector3.new(
        math.clamp(local_p.X, -hs.X, hs.X),
        math.clamp(local_p.Y, -hs.Y, hs.Y),
        math.clamp(local_p.Z, -hs.Z, hs.Z))
    local worldPoint = part.CFrame:PointToWorldSpace(clamped)
    local sp, onScreen = cam:WorldToViewportPoint(worldPoint)
    if not onScreen then return math.huge, nil end
    return (mousePos - Vector2.new(sp.X, sp.Y)).Magnitude, worldPoint
end

local function aimFindClosest()
    local cam = workspace.CurrentCamera
    local closest, closestDist, closestHit = nil, AimbotSettings.FOVRadius + 1, nil
    local mousePos = UserInputService:GetMouseLocation()
    for _, plr in ipairs(_cachedPlayers or plrs:GetPlayers()) do
        if plr == lplr then continue end
        if AimbotSettings.TeamCheck and plr.Team == lplr.Team then continue end
        local char = plr.Character; if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp or not hum or hum.Health <= 0 then continue end
        if AimbotSettings.VisibleCheck and not aimIsVisible(plr) then continue end
        if AimbotSettings.ClosestPart then
            for _, partName in ipairs(ALL_PARTS) do
                local part = char:FindFirstChild(partName); if not part then continue end
                local dist, hitPt = partScreenDist(cam, part, mousePos)
                if dist < closestDist then closest=part; closestDist=dist; closestHit=hitPt end
            end
        else
            local partName = AimbotSettings.TargetPart
            if partName == "Random" then partName = ({"Head","HumanoidRootPart"})[math.random(1,2)] end
            local targetPart = char:FindFirstChild(partName) or hrp
            local sp, onScreen = cam:WorldToViewportPoint(targetPart.Position)
            if not onScreen then continue end
            local dist = (mousePos - Vector2.new(sp.X, sp.Y)).Magnitude
            if dist < closestDist then closest=targetPart; closestDist=dist; closestHit=targetPart.Position end
        end
    end
    return closest, closestHit
end

-- aimbot per-frame: update cached target + draw
RunService.RenderStepped:Connect(function()
    if AimbotSettings.Enabled then
        cachedTarget, cachedHitPoint = aimFindClosest()
    else
        cachedTarget = nil; cachedHitPoint = nil
    end
    if A_fovCircle then
        local mousePos = UserInputService:GetMouseLocation()
        A_fovCircle.Visible = AimbotSettings.ShowFOV
        if AimbotSettings.ShowFOV then
            A_fovCircle.Radius = AimbotSettings.FOVRadius
            A_fovCircle.Position = mousePos
        end
        if AimbotSettings.ShowTarget and AimbotSettings.Enabled and cachedTarget then
            local sp, onScreen = workspace.CurrentCamera:WorldToViewportPoint(cachedTarget.Position)
            if onScreen then
                A_targetBox.Position = Vector2.new(sp.X, sp.Y)
                A_targetBox.Visible = true
            else A_targetBox.Visible = false end
        else A_targetBox.Visible = false end
    end
end)

local function saDirection(origin, targetPos) return (targetPos - origin).Unit * 1000 end

if hookmetamethod then
    -- track tool presence
    local hasTool = false
    RunService.RenderStepped:Connect(function()
        local c = lplr.Character
        if not c then hasTool=false; return end
        hasTool = false
        for _,v in ipairs(c:GetChildren()) do
            if v:IsA("Tool") then hasTool=true; break end
        end
    end)

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
        local method = getnamecallmethod()
        if method ~= "Raycast" and method ~= "FindPartOnRay" and method ~= "findPartOnRay"
            and method ~= "FindPartOnRayWithIgnoreList" and method ~= "FindPartOnRayWithWhitelist" then
            return oldNamecall(...)
        end
        if not AimbotSettings.Enabled then return oldNamecall(...) end
        if checkcaller() then return oldNamecall(...) end
        if not hasTool then return oldNamecall(...) end
        if not cachedTarget then return oldNamecall(...) end
        if math.random(100) > AimbotSettings.HitChance then return oldNamecall(...) end
        local args = {...}
        if not rawequal(args[1], workspace) then return oldNamecall(...) end
        local _aimBase = cachedHitPoint or cachedTarget.Position
        local targetPos = AimbotSettings.Prediction
            and (_aimBase + (cachedTarget.AssemblyLinearVelocity * AimbotSettings.PredictionAmount))
            or _aimBase
        local m = AimbotSettings.Method
        if method == "Raycast" then
            if typeof(args[2]) ~= "Vector3" then return oldNamecall(...) end
            local dir = args[3]
            if typeof(dir) == "Vector3" and dir.Magnitude < 20 then return oldNamecall(...) end
            if m == "All" or m == "Raycast" then
                args[3] = saDirection(args[2], targetPos)
                return oldNamecall(unpack(args))
            end
        else
            local ray = args[2]; if not ray then return oldNamecall(...) end
            local origin = ray.Origin; if not origin then return oldNamecall(...) end
            if ray.Direction.Magnitude < 20 then return oldNamecall(...) end
            local matches = (m == "All")
                or (m == "FindPartOnRay" and (method == "FindPartOnRay" or method == "findPartOnRay"))
                or (m == "FindPartOnRayWithIgnoreList" and method == "FindPartOnRayWithIgnoreList")
                or (m == "FindPartOnRayWithWhitelist" and method == "FindPartOnRayWithWhitelist")
            if matches then
                args[2] = Ray.new(origin, saDirection(origin, targetPos))
                return oldNamecall(unpack(args))
            end
        end
        return oldNamecall(...)
    end))

    -- __index hook for Mouse.Hit / Mouse.Target
    local mouse = lplr:GetMouse()
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
        if not AimbotSettings.Enabled then return oldIndex(self, key) end
        if AimbotSettings.Method ~= "Mouse.Hit/Target" then return oldIndex(self, key) end
        if not rawequal(self, mouse) then return oldIndex(self, key) end
        if checkcaller() then return oldIndex(self, key) end
        if key ~= "Hit" and key ~= "hit" and key ~= "Target" and key ~= "target" then
            return oldIndex(self, key)
        end
        local part = cachedTarget; if not part then return oldIndex(self, key) end
        local _aimBase = cachedHitPoint or part.Position
        local tp = AimbotSettings.Prediction
            and (_aimBase + (part.AssemblyLinearVelocity * AimbotSettings.PredictionAmount))
            or _aimBase
        if key == "Target" or key == "target" then return part end
        return CFrame.new(tp)
    end))
end

-- ============================================================
--  CAMLOCK CORE
-- ============================================================
local CL_fovCircle
if Drawing and Drawing.new then
    CL_fovCircle = Drawing.new("Circle")
    CL_fovCircle.Thickness=1; CL_fovCircle.NumSides=100
    CL_fovCircle.Radius=CamLockSettings.FOVRadius; CL_fovCircle.Filled=false; CL_fovCircle.Visible=false
    CL_fovCircle.ZIndex=999; CL_fovCircle.Transparency=1; CL_fovCircle.Color=Color3.fromRGB(255,200,0)
end

local clStickyTarget = nil

local function clIsVisible(plr)
    local char=plr.Character; local lchar=lplr.Character
    if not char or not lchar then return false end
    local root=char:FindFirstChild(CamLockSettings.TargetPart) or char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local camPos=workspace.CurrentCamera.CFrame.Position
    local ignore={lchar,char}
    for _,p in ipairs(_cachedPlayers) do
        if p.Character and p.Character~=char and p.Character~=lchar then table.insert(ignore,p.Character) end
    end
    return isReallyVisible(camPos, root.Position, ignore)
end

local function clIsAlive(plr)
    if plr == lplr then return false end
    if CamLockSettings.TeamCheck and plr.Team == lplr.Team then return false end
    local char = plr.Character; if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return hrp ~= nil and hum ~= nil and hum.Health > 0
end

local function clIsValidTarget(plr)
    if plr == lplr then return false end
    if CamLockSettings.TeamCheck and plr.Team == lplr.Team then return false end
    local char = plr.Character; if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp or not hum or hum.Health <= 0 then return false end
    if CamLockSettings.VisibleCheck and not clIsVisible(plr) then return false end
    return true, char, hrp
end

local function clGetPartForPlayer(char, hrp)
    if CamLockSettings.ClosestPart then
        local cam = workspace.CurrentCamera
        local mousePos = UserInputService:GetMouseLocation()
        local best, bestDist = hrp, math.huge
        for _, pname in ipairs(ALL_PARTS) do
            local part = char:FindFirstChild(pname); if not part then continue end
            local d = partScreenDist(cam, part, mousePos)
            if d < bestDist then bestDist = d; best = part end
        end
        return best
    else
        local pname = CamLockSettings.TargetPart
        if pname == "Random" then pname = ({"Head","HumanoidRootPart"})[math.random(1,2)] end
        return char:FindFirstChild(pname) or hrp
    end
end

local function clFindTarget()
    local cam = workspace.CurrentCamera
    local mousePos = UserInputService:GetMouseLocation()
    if CamLockSettings.Sticky and clStickyTarget then
        local sPlr = plrs:GetPlayerFromCharacter(clStickyTarget.Parent)
        if sPlr and clIsAlive(sPlr) then
            local char = sPlr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then clStickyTarget = clGetPartForPlayer(char, hrp) end
            return clStickyTarget
        end
        clStickyTarget = nil
    end
    local closest, closestDist = nil, CamLockSettings.FOVRadius + 1
    for _, plr in ipairs(plrs:GetPlayers()) do
        local ok, char, hrp = clIsValidTarget(plr); if not ok then continue end
        local checkPart = char:FindFirstChild(CamLockSettings.TargetPart) or hrp
        local sp, onScreen = cam:WorldToViewportPoint(checkPart.Position)
        if not onScreen then continue end
        local d = (mousePos - Vector2.new(sp.X, sp.Y)).Magnitude
        if d < closestDist then closestDist = d; closest = clGetPartForPlayer(char, hrp) end
    end
    clStickyTarget = closest
    return closest
end

RunService.RenderStepped:Connect(function(dt)
    if CL_fovCircle then
        CL_fovCircle.Visible = CamLockSettings.ShowFOV
        if CamLockSettings.ShowFOV then
            local mp = UserInputService:GetMouseLocation()
            CL_fovCircle.Radius = CamLockSettings.FOVRadius
            CL_fovCircle.Position = mp
        end
    end
    if not CamLockSettings.Enabled then clStickyTarget = nil; return end
    if G.freecamActive then return end
    local part = clFindTarget(); if not part then return end
    local targetPos = CamLockSettings.Prediction
        and (part.Position + (part.AssemblyLinearVelocity * CamLockSettings.PredictionAmount))
        or part.Position
    local cam = workspace.CurrentCamera
    local desired = CFrame.new(cam.CFrame.Position, targetPos)
    if CamLockSettings.Mode == "Cam" then
        cam.CFrame = desired
    else
        local alpha = math.clamp(1 - (CamLockSettings.Smoothing ^ (dt * 60)), 0, 1)
        cam.CFrame = cam.CFrame:Lerp(desired, alpha)
    end
end)

-- ============================================================
--  TRIGGERBOT
-- ============================================================
local TB_fovCircle, TB_targetBox
if Drawing and Drawing.new then
    TB_fovCircle = Drawing.new("Circle"); TB_fovCircle.Thickness=1; TB_fovCircle.NumSides=100
    TB_fovCircle.Radius=TrigSettings.FOVRadius; TB_fovCircle.Filled=false; TB_fovCircle.Visible=false
    TB_fovCircle.Color=Color3.fromRGB(255,180,0); TB_fovCircle.Transparency=1

    TB_targetBox = Drawing.new("Circle")
    TB_targetBox.Visible=false; TB_targetBox.ZIndex=999
    TB_targetBox.Color=Color3.fromRGB(255,180,0)
    TB_targetBox.Thickness=1; TB_targetBox.Filled=true; TB_targetBox.Radius=4; TB_targetBox.NumSides=32
end

-- pick the target part by name, with R6/R15 friendly fallbacks
local function tbResolvePart(char, name)
    if not char then return nil end
    if name == "Random" then
        local parts = {}
        for _, p in ipairs(char:GetChildren()) do
            if p:IsA("BasePart") then table.insert(parts, p) end
        end
        if #parts == 0 then return char:FindFirstChild("HumanoidRootPart") end
        return parts[math.random(1, #parts)]
    end
    return char:FindFirstChild(name) or char:FindFirstChild("HumanoidRootPart")
end

local function trigIsVisible(plr)
    local char=plr.Character; local lchar=lplr.Character
    if not char or not lchar then return false end
    local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return false end
    local camPos=workspace.CurrentCamera.CFrame.Position
    local ignore={lchar,char}
    for _,p in ipairs(_cachedPlayers) do
        if p.Character and p.Character~=char and p.Character~=lchar then table.insert(ignore,p.Character) end
    end
    return isReallyVisible(camPos, hrp.Position, ignore)
end

local _trigLastShot = 0
local _trigCurrentPart = nil  -- currently-best target part this frame, for ShowTarget
RunService.Heartbeat:Connect(function()
    local cam = workspace.CurrentCamera
    local mousePos = UserInputService:GetMouseLocation()

    if TB_fovCircle then
        TB_fovCircle.Visible = TrigSettings.ShowFOV
        if TrigSettings.ShowFOV then
            TB_fovCircle.Position = mousePos
            TB_fovCircle.Radius   = TrigSettings.FOVRadius
        end
    end

    -- find best player inside FOV.
    -- TargetPart "All" → scan every BasePart and pick closest to mouse.
    local hitPlr, hitPart, bestD = nil, nil, math.huge
    for _, plr in ipairs(_cachedPlayers or plrs:GetPlayers()) do
        if plr == lplr then continue end
        if TrigSettings.TeamCheck and plr.Team == lplr.Team then continue end
        local char = plr.Character; if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        if TrigSettings.VisibleCheck and not trigIsVisible(plr) then continue end

        if TrigSettings.TargetPart == "All" then
            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") then
                    local sp, onScreen = cam:WorldToViewportPoint(part.Position)
                    if onScreen then
                        local d = (mousePos - Vector2.new(sp.X, sp.Y)).Magnitude
                        if d <= TrigSettings.FOVRadius and d < bestD then
                            hitPlr, hitPart, bestD = plr, part, d
                        end
                    end
                end
            end
        else
            local part = tbResolvePart(char, TrigSettings.TargetPart)
            if part then
                local sp, onScreen = cam:WorldToViewportPoint(part.Position)
                if onScreen then
                    local d = (mousePos - Vector2.new(sp.X, sp.Y)).Magnitude
                    if d <= TrigSettings.FOVRadius and d < bestD then
                        hitPlr, hitPart, bestD = plr, part, d
                    end
                end
            end
        end
    end
    _trigCurrentPart = hitPart

    if TB_targetBox then
        if TrigSettings.ShowTarget and TrigSettings.Enabled and hitPart then
            local sp, onScreen = cam:WorldToViewportPoint(hitPart.Position)
            if onScreen then
                TB_targetBox.Position = Vector2.new(sp.X, sp.Y)
                TB_targetBox.Visible  = true
            else TB_targetBox.Visible = false end
        else TB_targetBox.Visible = false end
    end

    if not TrigSettings.Enabled then return end
    if (tick() - _trigLastShot) * 1000 < TrigSettings.ClickDelay then return end
    if not hitPlr then return end
    _trigLastShot = tick()
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendMouseButtonEvent(0,0,0,true,game,0)
        vim:SendMouseButtonEvent(0,0,0,false,game,0)
    end)
end)

-- ============================================================
--  RAGEBOT CORE
-- ============================================================
local _rbMousePos = UserInputService:GetMouseLocation()
UserInputService.InputChanged:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseMovement then
        _rbMousePos = UserInputService:GetMouseLocation()
    end
end)

local rbCachedTarget = nil
local _rbFaceStepBound = false
local rbOrbitAngle = 0

-- target visualization
local RB_targetLine, RB_outlineHL
if Drawing and Drawing.new then
    RB_targetLine = Drawing.new("Line")
    RB_targetLine.Visible     = false
    RB_targetLine.Thickness   = 2
    RB_targetLine.Color       = Color3.fromRGB(255, 80, 80)
    RB_targetLine.Transparency= 1
end
local function ensureRBHighlight()
    if RB_outlineHL and RB_outlineHL.Parent then return RB_outlineHL end
    RB_outlineHL = Instance.new("Highlight")
    RB_outlineHL.Name = "_cclosure_rb_outline"
    RB_outlineHL.FillTransparency    = 1
    RB_outlineHL.OutlineColor        = Color3.fromRGB(255, 80, 80)
    RB_outlineHL.OutlineTransparency = 0
    RB_outlineHL.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    RB_outlineHL.Enabled             = false
    pcall(function() RB_outlineHL.Parent = game:GetService("CoreGui") end)
    if not RB_outlineHL.Parent then RB_outlineHL.Parent = workspace end
    return RB_outlineHL
end

local function rbIsVisible(plr)
    local char = plr.Character; local lchar = lplr.Character
    if not char or not lchar then return false end
    local root = char:FindFirstChild("HumanoidRootPart"); if not root then return false end
    local camPos = workspace.CurrentCamera.CFrame.Position
    local ignore = {lchar, char}
    for _, p in ipairs(plrs:GetPlayers()) do
        if p.Character and p.Character ~= char and p.Character ~= lchar then table.insert(ignore, p.Character) end
    end
    return isReallyVisible(camPos, root.Position, ignore)
end

local function rbGetTarget()
    if #_rbTargetList > 0 then
        local lchar=lplr.Character
        local lhrp=lchar and lchar:FindFirstChild("HumanoidRootPart")
        local useMouse=RageSettings.SwitchByMouse
        local cam=useMouse and workspace.CurrentCamera or nil
        local mousePos=useMouse and UserInputService:GetMouseLocation() or nil
        local best,bestDist=nil,math.huge
        for _,entry in ipairs(_rbTargetList) do
            if not entry.plr or not entry.plr.Parent then
                for _,p in ipairs(plrs:GetPlayers()) do
                    if p.UserId==entry.userId then entry.plr=p; break end
                end
            end
            local plr=entry.plr; if not plr or not plr.Parent then continue end
            local char=plr.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            local hum=char:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health<=0 then continue end
            local dist
            if useMouse then
                local sp,onScreen=cam:WorldToViewportPoint(hrp.Position)
                if not onScreen then continue end
                dist=(mousePos-Vector2.new(sp.X,sp.Y)).Magnitude
            else
                dist=lhrp and (lhrp.Position-hrp.Position).Magnitude or math.huge
            end
            if dist<bestDist then bestDist=dist; best=plr end
        end
        if best then RageSettings.TargetPlayer=best; RageSettings.TargetUserId=best.UserId; return best end
    end
    local uid=RageSettings.TargetUserId; if not uid then return nil end
    local plr=RageSettings.TargetPlayer
    if plr and plr.Parent and plr.UserId==uid then return plr end
    for _,p in ipairs(plrs:GetPlayers()) do
        if p.UserId==uid then RageSettings.TargetPlayer=p; return p end
    end
    return nil
end

-- expose lockClosest / unlock / tpBehind / etc.
local function rbLockClosest()
    local cam = workspace.CurrentCamera
    local mousePos = UserInputService:GetMouseLocation()
    local best, bestDist = nil, math.huge
    for _, plr in ipairs(plrs:GetPlayers()) do
        if plr == lplr then continue end
        local char = plr.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local sp, onScreen = cam:WorldToViewportPoint(hrp.Position)
        if not onScreen then continue end
        local d = (mousePos - Vector2.new(sp.X, sp.Y)).Magnitude
        if d < bestDist then bestDist = d; best = plr end
    end
    if best then
        _rbTargetList = {{userId=best.UserId, plr=best}}
        RageSettings.TargetPlayer = best
        RageSettings.TargetUserId = best.UserId
    end
    return best
end
local function rbLockByPlayer(plr)
    if typeof(plr)=="string" then plr=findPlayerByName(plr) end
    if not plr then return nil end
    _rbTargetList = {{userId=plr.UserId, plr=plr}}
    RageSettings.TargetPlayer = plr
    RageSettings.TargetUserId = plr.UserId
    return plr
end
local function rbAddTarget(plr)
    if typeof(plr)=="string" then plr=findPlayerByName(plr) end
    if not plr then return end
    for _,e in ipairs(_rbTargetList) do if e.userId==plr.UserId then return end end
    table.insert(_rbTargetList, {userId=plr.UserId, plr=plr})
end
local function rbUnlock()
    _rbTargetList = {}
    RageSettings.TargetPlayer = nil
    RageSettings.TargetUserId = nil
end
local function rbTpBehind()
    local plr = RageSettings.TargetPlayer; if not plr then return end
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local lchar = lplr.Character
    local lhrp = lchar and lchar:FindFirstChild("HumanoidRootPart")
    if not lhrp then return end

    -- direction the target is facing, projected horizontal
    local lv = hrp.CFrame.LookVector
    local horiz = Vector3.new(lv.X, 0, lv.Z)
    if horiz.Magnitude < 0.01 then horiz = Vector3.new(0, 0, -1) end
    horiz = horiz.Unit

    -- TpBehindDist=0 (default) puts us inside the target's HRP, larger values
    -- step back along their look direction
    local position = hrp.Position - horiz * (RageSettings.TpBehindDist or 0)
    _uprightTp(lchar, lhrp, position, horiz)
end

-- ragebot per-frame: face target / orbit / cam snap / speed panic
RunService.RenderStepped:Connect(function(dt)
    local plr = rbGetTarget()
    local char = plr and plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    rbCachedTarget = hrp

    -- target line origin: Bottom / Center / Top / Mouse
    -- Always draw — even when target is off-screen or behind the camera
    -- we project onto the screen edge so the line still points at them.
    if RB_targetLine then
        local function isFinite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end

        local cam = hrp and workspace.CurrentCamera
        local pos = hrp and hrp.Position
        local validPos = pos and isFinite(pos.X) and isFinite(pos.Y) and isFinite(pos.Z)

        if RageSettings.ShowLine and hrp and validPos and cam then
            local sp = cam:WorldToViewportPoint(pos)
            local vs = cam.ViewportSize
            local toX, toY = sp.X, sp.Y

            -- if behind camera, mirror across screen center and push outward
            -- (capped to a sane multiplier so we never produce huge numbers)
            if sp.Z < 0 then
                local cx, cy = vs.X * 0.5, vs.Y * 0.5
                toX = cx + (cx - toX) * 4
                toY = cy + (cy - toY) * 4
            end

            -- if anything went non-finite during projection, hide instead of
            -- snapping to (0,0) where Drawing renders NaN
            if not (isFinite(toX) and isFinite(toY)) then
                RB_targetLine.Visible = false
            else
                local origin = RageSettings.LineOrigin
                local from
                if origin == "Top" then
                    from = Vector2.new(vs.X * 0.5, 0)
                elseif origin == "Center" then
                    from = Vector2.new(vs.X * 0.5, vs.Y * 0.5)
                elseif origin == "Mouse" then
                    from = UserInputService:GetMouseLocation()
                else
                    from = Vector2.new(vs.X * 0.5, vs.Y)
                end
                RB_targetLine.From = from
                RB_targetLine.To   = Vector2.new(toX, toY)
                RB_targetLine.Visible = true
            end
        else
            RB_targetLine.Visible = false
        end
    end

    -- target outline: highlight on the locked character
    if RageSettings.ShowOutline and char then
        local hl = ensureRBHighlight()
        if hl.Adornee ~= char then hl.Adornee = char end
        hl.Enabled = true
    elseif RB_outlineHL then
        RB_outlineHL.Enabled = false
    end

    if RageSettings.CamSnap and hrp then
        local cam = workspace.CurrentCamera
        local desired = CFrame.new(cam.CFrame.Position, hrp.Position)
        local alpha = math.clamp(1-(RageSettings.CamSmoothing^(dt*60)),0,1)
        cam.CFrame = cam.CFrame:Lerp(desired, alpha)
    end

    local lc = lplr.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if RageSettings.FaceTarget and hrp and lhrp then
        if not _rbFaceStepBound then
            _rbFaceStepBound = true
            RunService:BindToRenderStep("rbFaceStep", Enum.RenderPriority.Camera.Value+1, function()
                if not RageSettings.FaceTarget then
                    RunService:UnbindFromRenderStep("rbFaceStep")
                    _rbFaceStepBound = false
                    return
                end
                local char2=lplr.Character; if not char2 then return end
                local lhrp2=char2:FindFirstChild("HumanoidRootPart"); if not lhrp2 then return end
                local tplr=RageSettings.TargetPlayer; if not tplr then return end
                local tchar=tplr.Character; if not tchar then return end
                local thrp=tchar:FindFirstChild("HumanoidRootPart"); if not thrp then return end
                local dir=(thrp.Position-lhrp2.Position)*Vector3.new(1,0,1)
                if dir.Magnitude<0.1 then return end
                local yaw=math.atan2(-dir.X,-dir.Z)
                lhrp2.CFrame=CFrame.new(lhrp2.Position)*CFrame.fromEulerAnglesYXZ(0,yaw,0)
            end)
        end
    elseif lhrp then
        if _rbFaceStepBound then
            RunService:UnbindFromRenderStep("rbFaceStep")
            _rbFaceStepBound=false
        end
    end

    if RageSettings.SpeedPanic and char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed=0; hum.JumpPower=0 end
    end

    if RageSettings.Orbit and hrp then
        if lhrp then
            rbOrbitAngle = (rbOrbitAngle + RageSettings.OrbitSpeed * dt) % 360
            local rad = math.rad(rbOrbitAngle); local d = RageSettings.OrbitDistance
            local targetPos = hrp.Position + Vector3.new(math.cos(rad)*d, RageSettings.OrbitHeight, math.sin(rad)*d)
            lhrp.CFrame = CFrame.new(targetPos, hrp.Position)
        end
    end
end)

-- silent force hooks (independent of aimbot)
if hookmetamethod then
    local rbOldNamecall
    rbOldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
        local method = getnamecallmethod()
        if method ~= "Raycast" and method ~= "FindPartOnRay" and method ~= "findPartOnRay"
            and method ~= "FindPartOnRayWithIgnoreList" and method ~= "FindPartOnRayWithWhitelist" then
            return rbOldNamecall(...)
        end
        if not RageSettings.SilentForce then return rbOldNamecall(...) end
        if RageSettings.SilentMethod == "Mouse.Hit/Target" then return rbOldNamecall(...) end
        if checkcaller() then return rbOldNamecall(...) end
        local part = rbCachedTarget; if not part then return rbOldNamecall(...) end
        local args = {...}
        if not rawequal(args[1], workspace) then return rbOldNamecall(...) end
        local m = RageSettings.SilentMethod; local targetPos = part.Position
        if method == "Raycast" then
            if typeof(args[2]) ~= "Vector3" then return rbOldNamecall(...) end
            if args[3] and typeof(args[3])=="Vector3" and args[3].Magnitude < 20 then return rbOldNamecall(...) end
            if m=="All" or m=="Raycast" then
                args[3] = (targetPos - args[2]).Unit * 1000
                return rbOldNamecall(unpack(args))
            end
        else
            local ray = args[2]; if not ray then return rbOldNamecall(...) end
            local origin = ray.Origin; if not origin then return rbOldNamecall(...) end
            if ray.Direction.Magnitude < 20 then return rbOldNamecall(...) end
            if m=="All" or (m=="FindPartOnRay" and (method=="FindPartOnRay" or method=="findPartOnRay"))
                or (m=="FindPartOnRayWithIgnoreList" and method=="FindPartOnRayWithIgnoreList")
                or (m=="FindPartOnRayWithWhitelist" and method=="FindPartOnRayWithWhitelist") then
                args[2] = Ray.new(origin, (targetPos-origin).Unit*1000)
                return rbOldNamecall(unpack(args))
            end
        end
        return rbOldNamecall(...)
    end))

    local rbMouse = lplr:GetMouse()
    local rbOldIndex
    rbOldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
        if not RageSettings.SilentForce then return rbOldIndex(self, key) end
        if RageSettings.SilentMethod ~= "Mouse.Hit/Target" then return rbOldIndex(self, key) end
        if not rawequal(self, rbMouse) then return rbOldIndex(self, key) end
        if checkcaller() then return rbOldIndex(self, key) end
        if key ~= "Hit" and key ~= "hit" and key ~= "Target" and key ~= "target" then return rbOldIndex(self, key) end
        local part = rbCachedTarget; if not part then return rbOldIndex(self, key) end
        if key == "Target" or key == "target" then return part end
        return CFrame.new(part.Position)
    end))
end

-- ragebot auto-shoot
local _rbEquipTime = 0
local function watchToolEquip(char)
    if not char then return end
    char.ChildAdded:Connect(function(c) if c:IsA("Tool") then _rbEquipTime = tick() end end)
end
lplr.CharacterAdded:Connect(watchToolEquip)
if lplr.Character then watchToolEquip(lplr.Character) end

local _rbLastShot = 0
RunService.Heartbeat:Connect(function()
    if not RageSettings.AutoShoot then return end
    local now = tick()
    if (now - _rbEquipTime) < RageSettings.EquipDelay then return end
    if (now - _rbLastShot) < (RageSettings.AutoShootCooldown / 1000) then return end
    local plr = rbGetTarget(); if not plr then return end
    -- skip knocked targets if the toggle is on (HC: BodyEffects K.O) — only auto-shoot,
    -- silent aim still tracks them so you can keep targeting them visually
    if RageSettings.SkipKnocked
        and F.games and F.games.hoodCustoms and F.games.hoodCustoms.isKnocked
        and F.games.hoodCustoms.isKnocked(plr) then return end
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local lchar = lplr.Character
    local lhrp = lchar and lchar:FindFirstChild("HumanoidRootPart"); if not lhrp then return end
    local dist = (lhrp.Position - hrp.Position).Magnitude
    if dist > RageSettings.AutoShootDist then return end
    if RageSettings.AutoShootVis and not rbIsVisible(plr) then return end
    if RageSettings.FFCheck and char:FindFirstChildOfClass("ForceField") then return end
    if RageSettings.AutoShootRequireTool then
        local lc = lplr.Character
        if not lc or not lc:FindFirstChildOfClass("Tool") then return end
    end
    _rbLastShot = tick()
    game:GetService("VirtualInputManager"):SendMouseButtonEvent(0,0,0,true,game,0)
    game:GetService("VirtualInputManager"):SendMouseButtonEvent(0,0,0,false,game,0)
end)

-- ============================================================
--  ESP CORE (drawings + render loop)
-- ============================================================
local EspDrawings, EspHighlights = {}, {}
local _tracerHistory = {}
local espRenderConn = nil

local function newLine()  if not Drawing then return nil end local l=Drawing.new("Line");   l.Visible=false; l.Thickness=1; l.Color=Color3.new(1,1,1); l.Transparency=1; return l end
local function newSquare() if not Drawing then return nil end local s=Drawing.new("Square"); s.Visible=false; s.Filled=false; s.Color=Color3.new(1,1,1); s.Transparency=1; s.Thickness=1; return s end
local function newText()  if not Drawing then return nil end local t=Drawing.new("Text");   t.Visible=false; t.Size=13; t.Center=true; t.Outline=true; t.Color=Color3.new(1,1,1); t.Font=2; return t end

local function espColor(plr)
    if EspSettings.TeamCheck then
        return plr.Team==lplr.Team and Color3.fromRGB(80,220,80) or Color3.fromRGB(220,60,60)
    end
    return Color3.fromRGB(255,255,255)
end

local function createEspForPlayer(plr)
    if plr==lplr or not Drawing then return end
    local d={
        box={newLine(),newLine(),newLine(),newLine(),newLine(),newLine(),newLine(),newLine()},
        boxFull=newSquare(), tracer=newLine(), hpBg=newSquare(), hpFill=newSquare(), hpText=newText(),
        name=newText(), dist=newText(), held=newText(),
        skeleton={newLine(),newLine(),newLine(),newLine(),newLine(),newLine(),newLine(),
                  newLine(),newLine(),newLine(),newLine(),newLine(),newLine(),newLine()},
    }
    EspDrawings[plr]=d
    local hi=Instance.new("Highlight")
    hi.FillColor=Color3.fromRGB(255,60,60); hi.OutlineColor=Color3.new(1,1,1)
    hi.FillTransparency=0.5; hi.OutlineTransparency=0
    hi.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hi.Enabled=false
    EspHighlights[plr]=hi
end

local function removeEspForPlayer(plr)
    local d=EspDrawings[plr]
    if d then
        for _,l in ipairs(d.box) do l:Remove() end; d.boxFull:Remove(); d.tracer:Remove()
        d.hpBg:Remove(); d.hpFill:Remove(); d.hpText:Remove(); d.name:Remove(); d.dist:Remove(); d.held:Remove()
        for _,l in ipairs(d.skeleton) do l:Remove() end
        if d.trailLines then for _,l in ipairs(d.trailLines) do l:Remove() end end
        EspDrawings[plr]=nil; _tracerHistory[plr]=nil
    end
    local hi=EspHighlights[plr]; if hi then hi:Destroy(); EspHighlights[plr]=nil end
end

local function hideEsp(d)
    for _,l in ipairs(d.box) do l.Visible=false end; d.boxFull.Visible=false
    d.tracer.Visible=false; d.hpBg.Visible=false; d.hpFill.Visible=false; d.hpText.Visible=false
    d.name.Visible=false; d.dist.Visible=false; d.held.Visible=false
    for _,l in ipairs(d.skeleton) do l.Visible=false end
end

local function updateEspForPlayer(plr)
    local d=EspDrawings[plr]; if not d then return end
    local char=plr.Character
    local hrp=char and char:FindFirstChild("HumanoidRootPart")
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health<=0 then hideEsp(d); return end
    local rootPos,onScreen=Camera:WorldToViewportPoint(hrp.Position)
    if not onScreen then hideEsp(d); return end
    if EspSettings.TracerHistory then
        if not _tracerHistory[plr] then _tracerHistory[plr]={} end
        table.insert(_tracerHistory[plr],{pos=hrp.Position,t=tick()})
        local cutoff=tick()-EspSettings.TracerHistLen
        while #_tracerHistory[plr]>0 and _tracerHistory[plr][1].t<cutoff do
            table.remove(_tracerHistory[plr],1)
        end
        if not d.trailLines then d.trailLines={} end
        local pts=_tracerHistory[plr]
        for _,ln in ipairs(d.trailLines) do ln.Visible=false end
        for i=2,#pts do
            local ln=d.trailLines[i-1]
            if not ln then
                ln=Drawing.new("Line"); ln.Thickness=1.5; ln.ZIndex=50; ln.Visible=false
                d.trailLines[i-1]=ln
            end
            local sp1=Camera:WorldToViewportPoint(pts[i-1].pos)
            local sp2=Camera:WorldToViewportPoint(pts[i].pos)
            local age=tick()-pts[i].t
            local alpha=1-(age/EspSettings.TracerHistLen)
            ln.From=Vector2.new(sp1.X,sp1.Y); ln.To=Vector2.new(sp2.X,sp2.Y)
            ln.Color=Color3.fromRGB(220,220,220); ln.Transparency=math.clamp(alpha,0,1); ln.Visible=true
        end
    else
        if d.trailLines then for _,ln in ipairs(d.trailLines) do ln.Visible=false end end
        _tracerHistory[plr]=nil
    end
    local dist=(hrp.Position-Camera.CFrame.Position).Magnitude
    if dist>1000 then hideEsp(d); return end
    local col=espColor(plr)
    local size=char:GetExtentsSize(); local cf=hrp.CFrame
    local topV,topOn=Camera:WorldToViewportPoint((cf*CFrame.new(0,size.Y/2,0)).Position)
    local botV,botOn=Camera:WorldToViewportPoint((cf*CFrame.new(0,-size.Y/2,0)).Position)
    if not topOn or not botOn then hideEsp(d); return end
    local bH=botV.Y-topV.Y; local bW=bH*0.55; local bX=topV.X-bW/2; local bY=topV.Y; local cS=math.max(4,bW*0.22)

    if EspSettings.BoxESP then
        if EspSettings.BoxStyle=="Full" then
            for _,l in ipairs(d.box) do l.Visible=false end
            d.boxFull.Position=Vector2.new(bX,bY); d.boxFull.Size=Vector2.new(bW,bH)
            d.boxFull.Color=col; d.boxFull.Thickness=1; d.boxFull.Filled=false; d.boxFull.Visible=true
        else
            d.boxFull.Visible=false
            local tl=Vector2.new(bX,bY); local tr=Vector2.new(bX+bW,bY)
            local bl=Vector2.new(bX,bY+bH); local br=Vector2.new(bX+bW,bY+bH)
            local corners={{tl,tl+Vector2.new(cS,0)},{tl,tl+Vector2.new(0,cS)},
                           {tr,tr+Vector2.new(-cS,0)},{tr,tr+Vector2.new(0,cS)},
                           {bl,bl+Vector2.new(cS,0)},{bl,bl+Vector2.new(0,-cS)},
                           {br,br+Vector2.new(-cS,0)},{br,br+Vector2.new(0,-cS)}}
            for i,c in ipairs(corners) do
                d.box[i].From=c[1]; d.box[i].To=c[2]; d.box[i].Color=col; d.box[i].Thickness=1; d.box[i].Transparency=1; d.box[i].Visible=true
            end
        end
    else for _,l in ipairs(d.box) do l.Visible=false end; d.boxFull.Visible=false end

    if EspSettings.TracerESP then
        local vp=Camera.ViewportSize; local from
        if EspSettings.TracerOrigin=="Top" then from=Vector2.new(vp.X/2,0)
        elseif EspSettings.TracerOrigin=="Center" then from=Vector2.new(vp.X/2,vp.Y/2)
        elseif EspSettings.TracerOrigin=="Mouse" then local mp=UserInputService:GetMouseLocation(); from=Vector2.new(mp.X,mp.Y)
        else from=Vector2.new(vp.X/2,vp.Y) end
        d.tracer.From=from; d.tracer.To=Vector2.new(rootPos.X,rootPos.Y)
        d.tracer.Color=col; d.tracer.Thickness=1; d.tracer.Transparency=1; d.tracer.Visible=true
    else d.tracer.Visible=false end

    if EspSettings.HealthESP then
        local pct=math.clamp(hum.Health/hum.MaxHealth,0,1)
        local barX=bX-4; local barY=bY
        d.hpBg.Size=Vector2.new(2,bH); d.hpBg.Position=Vector2.new(barX,barY)
        d.hpBg.Color=Color3.fromRGB(20,20,20); d.hpBg.Filled=true; d.hpBg.Transparency=1; d.hpBg.Visible=true
        local fillH=bH*pct
        d.hpFill.Size=Vector2.new(2,fillH); d.hpFill.Position=Vector2.new(barX,barY+bH-fillH)
        d.hpFill.Color=Color3.fromRGB(math.floor((1-pct)*255),math.floor(pct*200)+55,30)
        d.hpFill.Filled=true; d.hpFill.Transparency=1; d.hpFill.Visible=true
    else d.hpBg.Visible=false; d.hpFill.Visible=false end

    if EspSettings.HealthNum then
        local pct=math.clamp(hum.Health/hum.MaxHealth,0,1)
        local nameOffset = EspSettings.NameESP and 24 or 13
        d.hpText.Text=math.floor(hum.Health).."/"..math.floor(hum.MaxHealth).." hp"
        d.hpText.Position=Vector2.new(bX+bW/2, bY-nameOffset)
        d.hpText.Color=Color3.fromRGB(math.floor((1-pct)*220)+35, math.floor(pct*200)+55, 40)
        d.hpText.Size=11; d.hpText.Visible=true
    else d.hpText.Visible=false end

    if EspSettings.NameESP then
        d.name.Text=plr.Name; d.name.Position=Vector2.new(bX+bW/2,bY-13); d.name.Color=col; d.name.Size=13; d.name.Visible=true
    else d.name.Visible=false end

    if EspSettings.DistanceESP then
        d.dist.Text=math.floor(dist).." st"; d.dist.Position=Vector2.new(bX+bW/2,bY+bH+2)
        d.dist.Color=Color3.fromRGB(180,180,180); d.dist.Size=11; d.dist.Visible=true
    else d.dist.Visible=false end

    if EspSettings.HeldItem then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            d.held.Text="["..tool.Name.."]"; d.held.Position=Vector2.new(bX+bW/2, bY+bH+13)
            d.held.Color=Color3.fromRGB(255,215,60); d.held.Size=11; d.held.Visible=true
        else d.held.Visible=false end
    else d.held.Visible=false end

    if EspSettings.SkeletonESP then
        local joints={{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
            {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
            {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
            {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
            {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"}}
        for i,pair in ipairs(joints) do
            local pA=char:FindFirstChild(pair[1]); local pB=char:FindFirstChild(pair[2]); local line=d.skeleton[i]
            if pA and pB and line then
                local sA,onA=Camera:WorldToViewportPoint(pA.Position); local sB,onB=Camera:WorldToViewportPoint(pB.Position)
                if onA and onB then line.From=Vector2.new(sA.X,sA.Y); line.To=Vector2.new(sB.X,sB.Y); line.Color=col; line.Thickness=1; line.Transparency=1; line.Visible=true
                else line.Visible=false end
            elseif line then line.Visible=false end
        end
    else for _,l in ipairs(d.skeleton) do l.Visible=false end end

    local hi=EspHighlights[plr]
    if hi then
        if EspSettings.ChamsEnabled and char then
            if EspSettings.ChamsStyle=="Overlay" then hi.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hi.FillTransparency=0.4; hi.OutlineTransparency=0
            elseif EspSettings.ChamsStyle=="Occluded" then hi.DepthMode=Enum.HighlightDepthMode.Occluded; hi.FillTransparency=0.3; hi.OutlineTransparency=0
            elseif EspSettings.ChamsStyle=="Outline" then hi.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hi.FillTransparency=1; hi.OutlineTransparency=0 end
            hi.Parent=char; hi.Enabled=true
        else hi.Enabled=false end
    end
end

local function startEspRender()
    if espRenderConn or not Drawing then return end
    espRenderConn=RunService.RenderStepped:Connect(function()
        if not EspSettings.Enabled then
            for _,d in pairs(EspDrawings) do hideEsp(d) end
            for _,h in pairs(EspHighlights) do h.Enabled=false end
            return
        end
        for _,plr in ipairs(_cachedPlayers or plrs:GetPlayers()) do
            if plr~=lplr then
                if not EspDrawings[plr] then createEspForPlayer(plr) end
                updateEspForPlayer(plr)
            end
        end
    end)
end
local function stopEspRender()
    if espRenderConn then espRenderConn:Disconnect(); espRenderConn=nil end
    for _,d in pairs(EspDrawings) do hideEsp(d) end
    for _,h in pairs(EspHighlights) do h.Enabled=false end
end

plrs.PlayerRemoving:Connect(function(plr) removeEspForPlayer(plr) end)

-- ============================================================
--  PUBLIC API
-- ============================================================
local function makeToggle(startFn, stopFn, isActiveKey)
    return {
        start  = startFn,
        stop   = stopFn,
        toggle = function() if G[isActiveKey] then stopFn() else startFn() end end,
        isActive = function() return G[isActiveKey] == true end,
    }
end

F = {}  -- assigns the forward-declared local

F.fly = makeToggle(startFly, stopFly, "flyActive")
F.fly.setSpeed   = function(n) FLY_SPEED = tonumber(n) or FLY_SPEED end
F.fly.getSpeed   = function() return FLY_SPEED end

F.speed = {
    start  = function(mult) startSpeed(mult) end,
    stop   = stopSpeed,
    toggle = function(mult) if G.speedActive then stopSpeed() else startSpeed(mult) end end,
    isActive = function() return G.speedActive == true end,
    setMultiplier = function(n) G.speedValue = tonumber(n) or G.speedValue end,
    getMultiplier = function() return G.speedValue end,
}

F.bhop      = makeToggle(startBhop,      stopBhop,      "bhopActive")
F.bhop.config = BHOP_CFG
F.infJump   = makeToggle(startInfJump,   stopInfJump,   "infJumpActive")
F.antiAfk   = makeToggle(startAntiAfk,   stopAntiAfk,   "antiAfkActive")
F.clickTp   = makeToggle(startClickTp,   stopClickTp,   "clickTpActive")
F.autoRespawn = makeToggle(startAutoRe,  stopAutoRe,    "autoReActive")
F.noclip    = makeToggle(startNoclip,    stopNoclip,    "noclipActive")
F.fullbright= makeToggle(startFullbright,stopFullbright,"fullbrightActive")
F.freecam   = makeToggle(startFreecam,   stopFreecam,   "freecamActive")
F.zoom      = makeToggle(startZoom,      stopZoom,      "zoomActive")
F.spin      = makeToggle(startSpin,      stopSpin,      "spinActive")
F.spin.setSpeed = function(n) SPIN_SPEED = tonumber(n) or SPIN_SPEED end
F.flip      = makeToggle(startFlip,      stopFlip,      "flipActive")
F.ice       = makeToggle(startIce,       stopIce,       "iceActive")
F.ice.setSlide = function(n) ICE_SLIDE = math.clamp(tonumber(n) or ICE_SLIDE, 0, 0.999) end

F.respawn = { fire = cmdRe }
F.blink   = {
    fire = cmdBlink,
    setDistance = function(n) BLINK_DIST = tonumber(n) or BLINK_DIST end,
    getDistance = function() return BLINK_DIST end,
}
F.fov = { set = setFov, get = function() return CUSTOM_FOV end }

-- aimbot
F.aimbot = {
    settings   = AimbotSettings,
    setEnabled = function(b) AimbotSettings.Enabled = b == true end,
    toggle     = function() AimbotSettings.Enabled = not AimbotSettings.Enabled end,
    isActive   = function() return AimbotSettings.Enabled end,
    setFov     = function(n) AimbotSettings.FOVRadius = math.clamp(tonumber(n) or 130, 1, 1000) end,
    setHitPart = function(s) AimbotSettings.TargetPart = tostring(s) end,
    setMethod  = function(s) AimbotSettings.Method = tostring(s) end,
    setTeamCheck    = function(b) AimbotSettings.TeamCheck = b == true end,
    setVisibleCheck = function(b) AimbotSettings.VisibleCheck = b == true end,
    setShowFov      = function(b) AimbotSettings.ShowFOV = b == true end,
    setShowTarget   = function(b) AimbotSettings.ShowTarget = b == true end,
    setPrediction   = function(b) AimbotSettings.Prediction = b == true end,
    setPredictionAmount = function(n) AimbotSettings.PredictionAmount = math.clamp(tonumber(n) or 0.165, 0, 2) end,
    setHitChance    = function(n) AimbotSettings.HitChance = math.clamp(tonumber(n) or 100, 0, 100) end,
    setClosestPart  = function(b) AimbotSettings.ClosestPart = b == true end,
    getTarget       = function() return cachedTarget end,
}

-- camlock
F.camLock = {
    settings   = CamLockSettings,
    setEnabled = function(b) CamLockSettings.Enabled = b == true end,
    toggle     = function() CamLockSettings.Enabled = not CamLockSettings.Enabled end,
    isActive   = function() return CamLockSettings.Enabled end,
    setFov     = function(n) CamLockSettings.FOVRadius = math.clamp(tonumber(n) or 200, 1, 2000) end,
    setHitPart = function(s) CamLockSettings.TargetPart = tostring(s) end,
    setMode    = function(s) CamLockSettings.Mode = tostring(s) end,
    setSmoothing = function(n) CamLockSettings.Smoothing = math.clamp(tonumber(n) or 0.25, 0, 0.99) end,
    setTeamCheck    = function(b) CamLockSettings.TeamCheck = b == true end,
    setVisibleCheck = function(b) CamLockSettings.VisibleCheck = b == true end,
    setShowFov      = function(b) CamLockSettings.ShowFOV = b == true end,
    setSticky       = function(b) CamLockSettings.Sticky = b == true end,
    setPrediction   = function(b) CamLockSettings.Prediction = b == true end,
    setPredictionAmount = function(n) CamLockSettings.PredictionAmount = math.clamp(tonumber(n) or 0.165, 0, 2) end,
    setClosestPart  = function(b) CamLockSettings.ClosestPart = b == true end,
}

-- triggerbot
F.triggerbot = {
    settings   = TrigSettings,
    setEnabled = function(b) TrigSettings.Enabled = b == true end,
    toggle     = function() TrigSettings.Enabled = not TrigSettings.Enabled end,
    isActive   = function() return TrigSettings.Enabled end,
    setFov     = function(n) TrigSettings.FOVRadius = math.clamp(tonumber(n) or 20, 1, 500) end,
    setDelay   = function(n) TrigSettings.ClickDelay = math.clamp(tonumber(n) or 0, 0, 2000) end,
    setTeamCheck    = function(b) TrigSettings.TeamCheck = b == true end,
    setVisibleCheck = function(b) TrigSettings.VisibleCheck = b == true end,
    setShowFov      = function(b) TrigSettings.ShowFOV = b == true end,
    setHitPart      = function(s) TrigSettings.TargetPart = tostring(s) end,
    setShowTarget   = function(b) TrigSettings.ShowTarget = b == true end,
}

-- ragebot
F.ragebot = {
    settings    = RageSettings,
    lockClosest = rbLockClosest,
    lockPlayer  = rbLockByPlayer,
    addTarget   = rbAddTarget,
    unlock      = rbUnlock,
    tpBehind    = rbTpBehind,
    setSilentForce  = function(b) RageSettings.SilentForce = b == true end,
    setSilentMethod = function(s) RageSettings.SilentMethod = tostring(s) end,
    setShowLine     = function(b) RageSettings.ShowLine = b == true end,
    setShowOutline  = function(b) RageSettings.ShowOutline = b == true end,
    setLineOrigin   = function(s) RageSettings.LineOrigin = tostring(s) end,
    setSkipKnocked  = function(b) RageSettings.SkipKnocked = b == true end,
    setFaceTarget  = function(b) RageSettings.FaceTarget = b == true end,
    setOrbit       = function(b) RageSettings.Orbit = b == true end,
    setOrbitDistance = function(n) RageSettings.OrbitDistance = math.clamp(tonumber(n) or 15, 2, 200) end,
    setOrbitSpeed    = function(n) RageSettings.OrbitSpeed    = math.clamp(tonumber(n) or 60, 1, 9999) end,
    setOrbitHeight   = function(n) RageSettings.OrbitHeight   = math.clamp(tonumber(n) or 5, -50, 50) end,
    setAutoShoot     = function(b) RageSettings.AutoShoot = b == true end,
    setAutoShootDist     = function(n) RageSettings.AutoShootDist = math.clamp(tonumber(n) or 50, 1, 500) end,
    setAutoShootCooldown = function(n) RageSettings.AutoShootCooldown = math.clamp(tonumber(n) or 100, 0, 10000) end,
    setAutoShootRequireTool = function(b) RageSettings.AutoShootRequireTool = b == true end,
    setAutoShootVis  = function(b) RageSettings.AutoShootVis = b == true end,
    setFFCheck       = function(b) RageSettings.FFCheck = b == true end,
    setEquipDelay    = function(n) RageSettings.EquipDelay = math.clamp(tonumber(n) or 0.5, 0, 5) end,
    setCamSnap       = function(b) RageSettings.CamSnap = b == true end,
    setCamSmoothing  = function(n) RageSettings.CamSmoothing = math.clamp(tonumber(n) or 0.15, 0.01, 0.99) end,
    setSpeedPanic    = function(b) RageSettings.SpeedPanic = b == true end,
    setSwitchByMouse = function(b) RageSettings.SwitchByMouse = b == true end,
    getTarget        = function() return RageSettings.TargetPlayer end,
    getTargetList    = function()
        local out = {}
        for _, e in ipairs(_rbTargetList) do
            if e.plr and e.plr.Parent then table.insert(out, e.plr) end
        end
        return out
    end,
    isTargeted       = function(plr)
        if not plr then return false end
        for _, e in ipairs(_rbTargetList) do
            if e.userId == plr.UserId then return true end
        end
        return false
    end,
}

-- ESP
F.esp = {
    settings = EspSettings,
    start    = function() EspSettings.Enabled = true; startEspRender() end,
    stop     = function() EspSettings.Enabled = false; stopEspRender() end,
    toggle   = function()
        EspSettings.Enabled = not EspSettings.Enabled
        if EspSettings.Enabled then startEspRender() else stopEspRender() end
    end,
    isActive = function() return EspSettings.Enabled end,
    -- toggles
    setBox        = function(b) EspSettings.BoxESP        = b == true end,
    setNames      = function(b) EspSettings.NameESP       = b == true end,
    setHealth     = function(b) EspSettings.HealthESP     = b == true end,
    setHealthNum  = function(b) EspSettings.HealthNum     = b == true end,
    setDistance   = function(b) EspSettings.DistanceESP   = b == true end,
    setTracer     = function(b) EspSettings.TracerESP     = b == true end,
    setSkeleton   = function(b) EspSettings.SkeletonESP   = b == true end,
    setTeamCheck  = function(b) EspSettings.TeamCheck     = b == true end,
    setChams      = function(b) EspSettings.ChamsEnabled  = b == true end,
    setHeldItem   = function(b) EspSettings.HeldItem      = b == true end,
    setSelf       = function(b) EspSettings.SelfESP       = b == true end,
    setTracerHistory = function(b) EspSettings.TracerHistory = b == true end,
    setBoxStyle      = function(s) EspSettings.BoxStyle      = tostring(s) end,
    setTracerOrigin  = function(s) EspSettings.TracerOrigin  = tostring(s) end,
    setChamsStyle    = function(s) EspSettings.ChamsStyle    = tostring(s) end,
    setTracerHistLen = function(n) EspSettings.TracerHistLen = math.clamp(tonumber(n) or 2, 0.5, 10) end,
}

-- players
F.players = {
    list  = function() return plrs:GetPlayers() end,
    find  = findPlayerByName,
    goto  = gotoPlayer,
    view  = viewPlayer,
    fling = flingPlayer,
}

-- utility helpers (exposed for advanced users)
F.utils = {
    isReallyVisible = isReallyVisible,
    findClosestPlayer = function(opts)
        opts = opts or {}
        local cam = workspace.CurrentCamera
        local mp  = UserInputService:GetMouseLocation()
        local maxDist = opts.fov or math.huge
        local exclude = opts.exclude  -- table mapping [Player] = true
        local best, bestD = nil, maxDist + 1
        for _, p in ipairs(plrs:GetPlayers()) do
            if p == lplr then continue end
            if exclude and exclude[p] then continue end
            if opts.teamCheck and p.Team == lplr.Team then continue end
            local char = p.Character; if not char then continue end
            local hum = char:FindFirstChildOfClass("Humanoid"); local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp or not hum or hum.Health <= 0 then continue end
            local sp, on = cam:WorldToViewportPoint(hrp.Position); if not on then continue end
            local d = (mp - Vector2.new(sp.X, sp.Y)).Magnitude
            if d < bestD then bestD = d; best = p end
        end
        return best
    end,
    getCharacter = function() return lplr.Character end,
    getRoot      = function() local c=lplr.Character; return c and c:FindFirstChild("HumanoidRootPart") end,
    getHumanoid  = function() local c=lplr.Character; return c and c:FindFirstChildOfClass("Humanoid") end,
}

-- ============================================================
--  ANTI VC BAN
--  Cycles voice connections + swaps the mic icon with a fake one
--  that just publishes pause state. Idempotent within a session.
--  Source: github.com/EnterpriseExperience/MicUpSource
-- ============================================================
local function antiVcBanFire()
    if getgenv().__cclosure_anti_vc_ban_running then return end
    getgenv().__cclosure_anti_vc_ban_running = true

    task.spawn(function()
        local ok, err = pcall(function()
            local VoiceChatService  = game:GetService("VoiceChatService")
            local VoiceChatInternal = game:GetService("VoiceChatInternal")
            local CoreGui           = game:GetService("CoreGui")
            local MUTED_IMAGE  = "rbxasset://textures/ui/VoiceChat/MicLight/Muted.png"
            local REJOIN_COUNT = 4
            local REJOIN_DELAY = 5
            local CurrentlyMuted = true

            local TopBarApp = CoreGui:WaitForChild("TopBarApp"):WaitForChild("TopBarApp")
            local MicPath = CoreGui:FindFirstChild("toggle_mic_mute", true)
            while not MicPath do
                task.wait()
                MicPath = CoreGui:FindFirstChild("toggle_mic_mute", true)
            end
            local MicContainer = MicPath.Parent

            if not getgenv().toggle_mic_muter_icon_found_descendant then
                getgenv().toggle_mic_muter_icon_found_descendant = true
                CoreGui.DescendantAdded:Connect(function(v)
                    if v.Name == "toggle_mic_mute" then
                        MicPath = v
                        MicContainer = v.Parent
                    end
                end)
            end

            local function get_mic_icon(button)
                button = button or MicPath
                if not button then return end
                return button:FindFirstChild("1", true)
            end

            local function ensure_voice_joined()
                if not VoiceChatService:IsVoiceEnabledForUserIdAsync(plrs.LocalPlayer.UserId) then return end
                VoiceChatService:joinVoice()
            end

            local function cycle_voice_connections()
                local groupId = VoiceChatInternal:GetGroupId()
                VoiceChatInternal:JoinByGroupId(groupId, true)
                VoiceChatService:leaveVoice()
                task.wait()
                for _ = 1, REJOIN_COUNT do
                    VoiceChatInternal:JoinByGroupId(groupId, true)
                end
                task.wait(REJOIN_DELAY)
                VoiceChatService:joinVoice()
                VoiceChatInternal:JoinByGroupId(groupId, true)
            end

            local function replace_mic_button()
                MicPath.Visible = false
                local newMic = MicPath:Clone()
                newMic.Name = "toggle_mic_mute_new"
                newMic.Visible = true
                newMic.Parent = MicContainer
                return newMic
            end

            local function watch_old_mic(newMic)
                local visConn, destConn
                visConn = MicPath:GetPropertyChangedSignal("Visible"):Connect(function()
                    if MicPath.Visible and newMic then newMic:Destroy() end
                end)
                destConn = MicPath.Destroying:Connect(function()
                    if newMic then newMic:Destroy() end
                end)
                newMic.Destroying:Connect(function()
                    if visConn then visConn:Disconnect() end
                    if destConn then destConn:Disconnect() end
                end)
            end

            local function setup_mic_toggle(newMic)
                local icon = get_mic_icon(newMic)
                while not icon do task.wait(); icon = get_mic_icon(newMic) end
                local hitArea = newMic:FindFirstChild("IconHitArea_toggle_mic_mute", true)
                while not hitArea do
                    task.wait()
                    hitArea = newMic:FindFirstChild("IconHitArea_toggle_mic_mute", true)
                end
                local highlighter = newMic:FindFirstChild("Highlighter", true)
                if highlighter then highlighter.Visible = false end
                icon.Image = MUTED_IMAGE
                VoiceChatInternal:PublishPause(true)
                CurrentlyMuted = true
                hitArea.MouseEnter:Connect(function()
                    if highlighter then highlighter.Visible = true end
                end)
                hitArea.MouseLeave:Connect(function()
                    if highlighter then highlighter.Visible = false end
                end)
                hitArea.Activated:Connect(function()
                    CurrentlyMuted = not CurrentlyMuted
                    VoiceChatInternal:PublishPause(CurrentlyMuted)
                    icon.Image = CurrentlyMuted and MUTED_IMAGE or ""
                end)
            end

            ensure_voice_joined()

            local prompt = Instance.new("TextLabel")
            prompt.Text = "Please unmute your microphone to continue."
            prompt.BackgroundTransparency = 1
            prompt.Size = UDim2.new(1, 0, 0.03, 0)
            prompt.AnchorPoint = Vector2.new(0.5, 0.5)
            prompt.Position = UDim2.new(0.5, 0, 0.5, 0)
            prompt.TextScaled = true
            prompt.TextColor3 = Color3.fromRGB(255, 255, 255)
            prompt.Parent = TopBarApp
            task.wait(2)
            prompt:Destroy()

            cycle_voice_connections()

            local newMic = replace_mic_button()
            watch_old_mic(newMic)
            setup_mic_toggle(newMic)
        end)
        if not ok then
            warn("[anti vc ban] failed:", err)
            getgenv().__cclosure_anti_vc_ban_running = false
        end
    end)
end

F.antiVcBan = { fire = antiVcBanFire }

-- ============================================================
--  SERVER HOPPER
-- ============================================================
local TeleportService = game:GetService("TeleportService")

local function _serversFetch(placeId, cursor)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(placeId)
    if cursor then url = url .. "&cursor=" .. cursor end
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if not ok or not body then return nil end
    local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok2 then return nil end
    return data
end

-- ============================================================
--  DAMAGE DETECTION  ("creator" tag pattern)
--  Watches the local Humanoid for transient ObjectValue children that
--  most Roblox combat scripts parent on hit (creator / DamageSource /
--  Attacker / Killer). Fires registered callbacks with the attacker.
-- ============================================================
local _damageCallbacks = {}

local function _isDamageTag(name)
    if not name then return false end
    local n = string.lower(name)
    return n == "creator" or n == "damagesource" or n == "attacker" or n == "killer"
end

local function _watchDamage(char)
    if not char then return end
    local hum = char:WaitForChild("Humanoid", 5); if not hum then return end
    local conn = hum.ChildAdded:Connect(function(c)
        if not c:IsA("ObjectValue") then return end
        if not _isDamageTag(c.Name) then return end
        local v = c.Value
        if typeof(v) ~= "Instance" then return end
        local attacker
        if v:IsA("Player") then attacker = v
        elseif v:IsA("Model") then attacker = plrs:GetPlayerFromCharacter(v)
        end
        if attacker and attacker ~= lplr then
            for _, cb in ipairs(_damageCallbacks) do pcall(cb, attacker) end
        end
    end)
    char.AncestryChanged:Connect(function()
        if not char.Parent then pcall(function() conn:Disconnect() end) end
    end)
end

if lplr.Character then task.spawn(_watchDamage, lplr.Character) end
lplr.CharacterAdded:Connect(_watchDamage)

F.damage = {
    onDamaged = function(fn) table.insert(_damageCallbacks, fn) end,
}

-- ============================================================
--  RAGEBOT: TP-SHOOT
--  Saves your CFrame, teleports behind the current locked target,
--  fires one click, then restores the saved CFrame. Distance and
--  return delay are reused from the existing tpBehind config.
-- ============================================================
F.ragebot.tpShoot = function()
    local target = RageSettings.TargetPlayer
    if not target then return end
    local char = target.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local lc   = lplr.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp then return end

    local saved = lhrp.CFrame
    -- TP into the target, upright, facing target's horizontal direction
    local lv = hrp.CFrame.LookVector
    local horiz = Vector3.new(lv.X, 0, lv.Z)
    if horiz.Magnitude < 0.01 then horiz = Vector3.new(0, 0, -1) end
    horiz = horiz.Unit
    local position = hrp.Position - horiz * (RageSettings.TpBehindDist or 0)
    _uprightTp(lc, lhrp, position, horiz)

    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendMouseButtonEvent(0, 0, 0, true,  game, 0)
        vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    end)

    -- Detect rage-target stomp mode at call time. If on, instead of the
    -- normal 0.15s restore, hand off to the auto-stomp loop's "wait until
    -- BodyEffects.Dead" path so we hover on top of the target until the
    -- stomp finishes the kill, then snap back to the original spot.
    local rageOn = F.games and F.games.hoodCustoms
        and F.games.hoodCustoms.autoStomp
        and F.games.hoodCustoms.autoStomp.getRageTargets
        and F.games.hoodCustoms.autoStomp.getRageTargets()

    -- run the wait + restore in a separate coroutine so the keybind handler
    -- isn't blocked while we wait
    task.spawn(function()
        if rageOn then
            -- wait for the TARGET's BodyEffects.Dead to become true.
            -- check both plr.Character.BodyEffects.Dead and the workspace
            -- mirror at workspace.Players.Characters.<name>.BodyEffects.Dead
            -- (whichever the game uses) — 10s safety cap.
            local deadline = tick() + 10
            local function targetDead()
                local function isTrue(node)
                    local fx = node and node:FindFirstChild("BodyEffects")
                    local d  = fx and fx:FindFirstChild("Dead")
                    return d ~= nil and d.Value == true
                end
                if isTrue(target.Character) then return true end
                local wsp = workspace:FindFirstChild("Players")
                local chars = wsp and wsp:FindFirstChild("Characters")
                local mdl = chars and chars:FindFirstChild(target.Name)
                if isTrue(mdl) then return true end
                return false
            end
            while tick() < deadline do
                if targetDead() then break end
                task.wait()
            end
        else
            task.wait(0.15)
        end

        local nc = lplr.Character
        local nhrp = nc and nc:FindFirstChild("HumanoidRootPart")
        if nhrp then
            _uprightTp(nc, nhrp, saved.Position, saved.LookVector)
        end
    end)
end

-- ============================================================
--  RAGEBOT: TARGET HUD  (floating panel with avatar/name/hp/tool/dist)
--  Built once, then toggled visible. Hides itself when nothing is
--  locked. Mirrors the pattern from vampireware.lua.
-- ============================================================
local _rbHud, _rbHudConn, _rbHudFrame, _rbAvatar, _rbName, _rbHpFill, _rbHeld, _rbDist
local _rbHudLastUid = nil

local function _buildRbHud()
    if _rbHud and _rbHud.Parent then return end
    local sg = Instance.new("ScreenGui")
    sg.Name = "_cclosure_rb_hud"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Global
    sg.DisplayOrder = 9997
    pcall(function() sg.Parent = lplr:WaitForChild("PlayerGui") end)
    if not sg.Parent then sg.Parent = game:GetService("CoreGui") end
    _rbHud = sg

    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
    frame.BackgroundTransparency = 0.12
    frame.BorderSizePixel = 0
    frame.AnchorPoint = Vector2.new(0.5, 1)
    frame.Position = UDim2.new(0.5, 0, 1, -90)
    frame.Size = UDim2.new(0, 320, 0, 64)
    frame.Visible = false
    frame.Parent = sg
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = frame end
    do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(60, 60, 70); s.Thickness = 1
       s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = frame end
    _rbHudFrame = frame

    local avatar = Instance.new("ImageLabel")
    avatar.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    avatar.BorderSizePixel = 0
    avatar.Size = UDim2.new(0, 52, 0, 52)
    avatar.AnchorPoint = Vector2.new(0, 0.5)
    avatar.Position = UDim2.new(0, 6, 0.5, 0)
    avatar.ScaleType = Enum.ScaleType.Crop
    avatar.Image = ""
    avatar.Parent = frame
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = avatar end
    _rbAvatar = avatar

    local text = Instance.new("Frame")
    text.BackgroundTransparency = 1
    text.BorderSizePixel = 0
    text.AnchorPoint = Vector2.new(0, 0)
    text.Position = UDim2.new(0, 64, 0, 4)
    text.Size = UDim2.new(1, -70, 1, -8)
    text.Parent = frame
    do local l = Instance.new("UIListLayout"); l.SortOrder = Enum.SortOrder.LayoutOrder
       l.Padding = UDim.new(0, 2); l.Parent = text end

    local function lbl(order, h)
        local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.BorderSizePixel = 0
        l.Size = UDim2.new(1, 0, 0, h or 13); l.LayoutOrder = order
        l.Font = Enum.Font.Gotham; l.Text = ""; l.TextColor3 = Color3.fromRGB(235, 235, 240)
        l.TextScaled = true; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = text
        local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 11; c.Parent = l
        return l
    end

    _rbName = lbl(1, 13)
    -- health bar (between name and held)
    local hpBg = Instance.new("Frame"); hpBg.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    hpBg.BorderSizePixel = 0; hpBg.Size = UDim2.new(1, 0, 0, 6); hpBg.LayoutOrder = 2
    hpBg.Parent = text
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 3); c.Parent = hpBg end
    _rbHpFill = Instance.new("Frame")
    _rbHpFill.BackgroundColor3 = Color3.fromRGB(75, 200, 95)
    _rbHpFill.BorderSizePixel = 0; _rbHpFill.Size = UDim2.new(1, 0, 1, 0); _rbHpFill.Parent = hpBg
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 3); c.Parent = _rbHpFill end

    _rbHeld = lbl(3, 11)
    _rbDist = lbl(4, 11)
end

local function _rbHudUpdate()
    if not _rbHudFrame then return end
    local plr = RageSettings.TargetPlayer
    local char = plr and plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not plr or not hrp or not hum or hum.Health <= 0 then
        _rbHudFrame.Visible = false
        return
    end
    _rbHudFrame.Visible = true

    local dn = plr.DisplayName
    local un = plr.Name
    _rbName.Text = (dn ~= un and dn .. " (@" .. un .. ")" or "@" .. un) .. " / " .. tostring(plr.UserId)
    _rbName.TextColor3 = Color3.fromRGB(140, 200, 255)

    local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
    _rbHpFill.Size = UDim2.new(pct, 0, 1, 0)
    _rbHpFill.BackgroundColor3 = Color3.fromRGB(
        math.floor((1 - pct) * 220) + 35,
        math.floor(pct * 180) + 55,
        40)

    local tool = char:FindFirstChildOfClass("Tool")
    _rbHeld.Text = "Holding: " .. (tool and tool.Name or "none")
    _rbHeld.TextColor3 = tool and Color3.fromRGB(255, 215, 60) or Color3.fromRGB(160, 160, 170)

    local lc = lplr.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if lhrp then
        _rbDist.Text = ("Distance: %d studs"):format(math.floor((lhrp.Position - hrp.Position).Magnitude))
    else _rbDist.Text = "" end
    _rbDist.TextColor3 = Color3.fromRGB(160, 160, 170)

    if plr.UserId ~= _rbHudLastUid then
        _rbHudLastUid = plr.UserId
        _rbAvatar.Image = ""
        task.spawn(function()
            local ok, img = pcall(function()
                return plrs:GetUserThumbnailAsync(plr.UserId,
                    Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
            end)
            if ok and _rbAvatar then _rbAvatar.Image = img end
        end)
    end
end

local function startRbTargetGui()
    G.rbTargetGuiActive = true
    _buildRbHud()
    if _rbHud then _rbHud.Enabled = true end
    if _rbHudConn then _rbHudConn:Disconnect() end
    _rbHudConn = RunService.RenderStepped:Connect(function()
        if not G.rbTargetGuiActive then return end
        _rbHudUpdate()
    end)
end

local function stopRbTargetGui()
    G.rbTargetGuiActive = false
    if _rbHudConn then _rbHudConn:Disconnect(); _rbHudConn = nil end
    if _rbHudFrame then _rbHudFrame.Visible = false end
    if _rbHud then _rbHud.Enabled = false end
end

F.ragebot.targetGui = makeToggle(startRbTargetGui, stopRbTargetGui, "rbTargetGuiActive")

-- ============================================================
--  AUTO-EQUIP
--  Picks a tool by name and equips it. Optionally auto-equips it
--  on respawn so you never spawn empty-handed.
-- ============================================================
local AutoEquipName  = nil
local _aeCharConn    = nil

local function _aeListTools()
    local out, seen = {}, {}
    local function consider(t)
        if t:IsA("Tool") and not seen[t.Name] then seen[t.Name] = true; table.insert(out, t.Name) end
    end
    if lplr:FindFirstChild("Backpack") then
        for _, t in ipairs(lplr.Backpack:GetChildren()) do consider(t) end
    end
    if lplr.Character then
        for _, t in ipairs(lplr.Character:GetChildren()) do consider(t) end
    end
    table.sort(out)
    return out
end

local function _aeEquip(name)
    if not name or name == "" then return false end
    local char = lplr.Character; if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return false end
    local tool = (lplr:FindFirstChild("Backpack") and lplr.Backpack:FindFirstChild(name))
              or char:FindFirstChild(name)
    if not tool or not tool:IsA("Tool") then return false end
    pcall(function() hum:EquipTool(tool) end)
    return true
end

local function startAutoEquip()
    G.autoEquipActive = true
    if _aeCharConn then _aeCharConn:Disconnect() end
    _aeCharConn = lplr.CharacterAdded:Connect(function()
        if not G.autoEquipActive then return end
        if not AutoEquipName or AutoEquipName == "" then return end
        local bp = lplr:WaitForChild("Backpack", 10); if not bp then return end
        bp:WaitForChild(AutoEquipName, 10)
        if not G.autoEquipActive then return end
        _aeEquip(AutoEquipName)
    end)
end
local function stopAutoEquip()
    G.autoEquipActive = false
    if _aeCharConn then _aeCharConn:Disconnect(); _aeCharConn = nil end
end

F.autoEquip = makeToggle(startAutoEquip, stopAutoEquip, "autoEquipActive")
F.autoEquip.list   = _aeListTools
F.autoEquip.equip  = function(name) AutoEquipName = name; return _aeEquip(name) end
F.autoEquip.setName = function(name) AutoEquipName = name end
F.autoEquip.getName = function() return AutoEquipName end

-- ============================================================
--  HITBOX EXTENDER
--  Locally inflates the size of a chosen part on every other player.
--  Raycasts (and Mouse.Hit) honor the new size client-side, so silent
--  aim / triggerbot land far more reliably. Cosmetic locally — server
--  still has the original size, this can't hurt other players directly.
-- ============================================================
local _hbOriginal     = setmetatable({}, { __mode = "k" })  -- weak keys
local _hbConn         = nil
local HitboxSize      = 8
local HitboxTargetPart = "HumanoidRootPart"
local HitboxTransparency = 0.6  -- visual hint that the box is huge; 1=invisible

local function _hbApply()
    for _, plr in ipairs(plrs:GetPlayers()) do
        if plr == lplr then continue end
        local char = plr.Character; if not char then continue end
        local part = char:FindFirstChild(HitboxTargetPart); if not part then continue end
        if not part:IsA("BasePart") then continue end
        if not _hbOriginal[part] then
            _hbOriginal[part] = {
                Size = part.Size, Transparency = part.Transparency,
                CanCollide = part.CanCollide, Massless = part.Massless,
            }
        end
        local s = HitboxSize
        if part.Size ~= Vector3.new(s, s, s) then
            pcall(function()
                part.Size         = Vector3.new(s, s, s)
                part.Transparency = HitboxTransparency
                part.CanCollide   = false
                part.Massless     = true
            end)
        end
    end
end

local function _hbRestore()
    for part, info in pairs(_hbOriginal) do
        if part.Parent then
            pcall(function()
                part.Size         = info.Size
                part.Transparency = info.Transparency
                part.CanCollide   = info.CanCollide
                part.Massless     = info.Massless
            end)
        end
    end
    _hbOriginal = setmetatable({}, { __mode = "k" })
end

local function startHitboxExtender()
    G.hitboxActive = true
    _hbConn = RunService.Heartbeat:Connect(_hbApply)
end
local function stopHitboxExtender()
    G.hitboxActive = false
    if _hbConn then _hbConn:Disconnect(); _hbConn = nil end
    _hbRestore()
end

F.hitboxExtender = makeToggle(startHitboxExtender, stopHitboxExtender, "hitboxActive")
F.hitboxExtender.setSize         = function(n) HitboxSize = math.clamp(tonumber(n) or 8, 1, 50) end
F.hitboxExtender.getSize         = function() return HitboxSize end
F.hitboxExtender.setTargetPart   = function(s) HitboxTargetPart = tostring(s) end
F.hitboxExtender.getTargetPart   = function() return HitboxTargetPart end
F.hitboxExtender.setTransparency = function(n) HitboxTransparency = math.clamp(tonumber(n) or 0.6, 0, 1) end

F.servers = {
    list = function(maxPages)
        maxPages = maxPages or 2
        local out = {}
        local cursor = nil
        for _ = 1, maxPages do
            local data = _serversFetch(game.PlaceId, cursor)
            if not data or not data.data then break end
            for _, srv in ipairs(data.data) do
                if srv.id ~= game.JobId and (srv.playing or 0) < (srv.maxPlayers or 0) then
                    table.insert(out, {
                        jobId      = srv.id,
                        playing    = srv.playing or 0,
                        maxPlayers = srv.maxPlayers or 0,
                        ping       = srv.ping or 0,
                        fps        = srv.fps or 0,
                    })
                end
            end
            cursor = data.nextPageCursor
            if not cursor then break end
        end
        return out
    end,

    rejoin = function()
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, lplr)
        end)
    end,

    join = function(jobId)
        if not jobId or jobId == "" then return false end
        local ok = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, lplr)
        end)
        return ok
    end,

    joinRandom = function()
        local servers = F.servers.list(1)
        if #servers == 0 then return false end
        local pick = servers[math.random(1, #servers)]
        return F.servers.join(pick.jobId), pick
    end,
}

-- ============================================================
--  GAMES: HOOD CUSTOMS - AUTO STOMP
--  Spams ReplicatedStorage.MainEvent:FireServer("Stomp") on Heartbeat,
--  but only while the local player is standing over another player
--  (within a small horizontal radius and slightly above them) so we
--  don't flood the server when there's nothing to stomp.
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- HC-specific knocked check via workspace.Players.Characters.<name>.BodyEffects["K.O"].Value
local function _hcIsKnocked(plr)
    if not plr then return false end
    local wsPlayers = workspace:FindFirstChild("Players")
    local chars = wsPlayers and wsPlayers:FindFirstChild("Characters")
    if not chars then return false end
    local mdl = chars:FindFirstChild(plr.Name)
    if not mdl then return false end
    local fx = mdl:FindFirstChild("BodyEffects")
    if not fx then return false end
    local ko = fx:FindFirstChild("K.O")
    return ko ~= nil and ko.Value == true
end

local _hcStompConn   = nil
local HC_STOMP_RADIUS    = 5    -- horizontal studs
local HC_STOMP_VERT_UP   = 7    -- max studs we can be above them
local HC_STOMP_VERT_DOWN = 1    -- max studs they can be above us
local HC_STOMP_INTERVAL  = 0    -- seconds between fires; 0 = every Heartbeat
local HC_STOMP_RAGE_TARGETS = false
local _hcStompLast = 0

local function _hcSomeoneBelowMe()
    local lc = lplr.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp then return false end
    for _, p in ipairs(plrs:GetPlayers()) do
        if p == lplr then continue end
        local char = p.Character; if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local d = lhrp.Position - hrp.Position
        local horizD = Vector2.new(d.X, d.Z).Magnitude
        if horizD <= HC_STOMP_RADIUS
            and d.Y <= HC_STOMP_VERT_UP
            and d.Y >= -HC_STOMP_VERT_DOWN then
            return true
        end
    end
    return false
end

local function startHcAutoStomp()
    G.hcAutoStompActive = true
    if _hcStompConn then _hcStompConn:Disconnect() end
    _hcStompConn = RunService.Heartbeat:Connect(function()
        if not G.hcAutoStompActive then return end
        if HC_STOMP_INTERVAL > 0 and tick() - _hcStompLast < HC_STOMP_INTERVAL then return end
        local me = ReplicatedStorage:FindFirstChild("MainEvent")
        if not me then return end

        -- mode A: actively pursue knocked ragebot targets — TP onto them and
        -- spam stomp until they respawn (i.e. K.O flips back to false)
        if HC_STOMP_RAGE_TARGETS then
            local list = F.ragebot.getTargetList and F.ragebot.getTargetList() or {}
            for _, plr in ipairs(list) do
                if _hcIsKnocked(plr) then
                    local char = plr.Character
                    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local lc   = lplr.Character
                        local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
                        if lhrp then
                            _uprightTp(lc, lhrp, hrp.Position + Vector3.new(0, 3, 0), nil)
                        end
                        _hcStompLast = tick()
                        pcall(function() me:FireServer("Stomp") end)
                        return
                    end
                end
            end
        end

        -- mode B: passive — only stomp while we're physically standing on someone
        if not _hcSomeoneBelowMe() then return end
        _hcStompLast = tick()
        pcall(function() me:FireServer("Stomp") end)
    end)
end

local function stopHcAutoStomp()
    G.hcAutoStompActive = false
    if _hcStompConn then _hcStompConn:Disconnect(); _hcStompConn = nil end
end

F.games = F.games or {}
F.games.hoodCustoms = F.games.hoodCustoms or {}
F.games.hoodCustoms.autoStomp = makeToggle(startHcAutoStomp, stopHcAutoStomp, "hcAutoStompActive")
F.games.hoodCustoms.autoStomp.setRadius   = function(n) HC_STOMP_RADIUS   = math.clamp(tonumber(n) or 5, 1, 30) end
F.games.hoodCustoms.autoStomp.getRadius   = function() return HC_STOMP_RADIUS end
F.games.hoodCustoms.autoStomp.setInterval = function(n) HC_STOMP_INTERVAL = math.clamp(tonumber(n) or 0, 0, 5) end
F.games.hoodCustoms.autoStomp.getInterval = function() return HC_STOMP_INTERVAL end
F.games.hoodCustoms.autoStomp.setRageTargets = function(b) HC_STOMP_RAGE_TARGETS = b == true end
F.games.hoodCustoms.autoStomp.getRageTargets = function() return HC_STOMP_RAGE_TARGETS end
F.games.hoodCustoms.isKnocked = _hcIsKnocked

-- ============================================================
--  GAMES: HOOD CUSTOMS - AUTO RELOAD
--  Reads exactly:  lplr.Character.<Tool>.Script.Ammo
--  When that IntValue is <= threshold, sends the configured reload key.
-- ============================================================
local HC_RELOAD_KEY       = Enum.KeyCode.R
local HC_RELOAD_THRESHOLD = 0
local HC_RELOAD_COOLDOWN  = 1.5
local _hcReloadLast = 0
local _hcReloadConn = nil

local function _hcGetAmmoValue()
    local char = lplr.Character;                                      if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool");                  if not tool then return nil end
    local script = tool:FindFirstChild("Script");                     if not script then return nil end
    local ammo = script:FindFirstChild("Ammo")
    if ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue")) then return ammo end
    return nil
end

local function _hcReloadFire()
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true,  HC_RELOAD_KEY, false, game)
        task.wait(0.05)
        vim:SendKeyEvent(false, HC_RELOAD_KEY, false, game)
    end)
end

local function startHcAutoReload()
    G.hcAutoReloadActive = true
    if _hcReloadConn then _hcReloadConn:Disconnect() end
    _hcReloadConn = RunService.Heartbeat:Connect(function()
        if not G.hcAutoReloadActive then return end
        if tick() - _hcReloadLast < HC_RELOAD_COOLDOWN then return end
        local ammo = _hcGetAmmoValue();              if not ammo then return end
        if ammo.Value > HC_RELOAD_THRESHOLD then return end
        _hcReloadLast = tick()
        _hcReloadFire()
    end)
end

local function stopHcAutoReload()
    G.hcAutoReloadActive = false
    if _hcReloadConn then _hcReloadConn:Disconnect(); _hcReloadConn = nil end
end

F.games.hoodCustoms.autoReload = makeToggle(startHcAutoReload, stopHcAutoReload, "hcAutoReloadActive")
F.games.hoodCustoms.autoReload.setKey = function(k)
    if typeof(k) == "EnumItem" then HC_RELOAD_KEY = k
    elseif type(k) == "string" then HC_RELOAD_KEY = Enum.KeyCode[k] or HC_RELOAD_KEY end
end
F.games.hoodCustoms.autoReload.setThreshold = function(n) HC_RELOAD_THRESHOLD = tonumber(n) or 0 end
F.games.hoodCustoms.autoReload.getThreshold = function() return HC_RELOAD_THRESHOLD end
F.games.hoodCustoms.autoReload.setCooldown  = function(n) HC_RELOAD_COOLDOWN  = math.clamp(tonumber(n) or 1.5, 0.1, 10) end
F.games.hoodCustoms.autoReload.getCooldown  = function() return HC_RELOAD_COOLDOWN end

-- ============================================================
--  GAMES: HOOD CUSTOMS - KNIFE REACH
--  Resizes lplr.Character.Knife.Handle.HITBOX_PART up to MAX (13,13,13).
--  Anything above that triggers HC's anti-cheat. Survives respawn via a
--  Heartbeat loop that re-applies whenever the knife reappears.
-- ============================================================
local HC_KNIFE_DEFAULT_SIZE = Vector3.new(2.5, 1, 1)
local HC_KNIFE_MAX          = 13
local HC_KNIFE_REACH_SIZE   = 13
local HC_KNIFE_VISUALIZE    = false
local _hcKnifeConn = nil

-- Tool is literally named "[Knife]" (square brackets). Check Backpack first
-- (unequipped), then Character (equipped) — matches the working snippet.
local function _hcKnifeHitbox()
    local function find(p)
        local k = p and p:FindFirstChild("[Knife]")
        if not k then return nil end
        local h = k:FindFirstChild("Handle"); if not h then return nil end
        return h:FindFirstChild("HITBOX_PART")
    end
    return find(lplr:FindFirstChildOfClass("Backpack")) or find(lplr.Character)
end

local function startHcKnifeReach()
    G.hcKnifeReachActive = true
    if _hcKnifeConn then _hcKnifeConn:Disconnect() end
    _hcKnifeConn = RunService.Heartbeat:Connect(function()
        if not G.hcKnifeReachActive then return end
        local hb = _hcKnifeHitbox(); if not hb then return end

        local s = HC_KNIFE_REACH_SIZE
        local target = Vector3.new(s, s, s)
        if hb.Size ~= target then
            pcall(function() hb.Size = target end)
        end
        if hb.Transparency ~= 0.9999 then
            pcall(function() hb.Transparency = 0.9999 end)
        end

        local hl = hb:FindFirstChild("_kr_hl")
        if HC_KNIFE_VISUALIZE then
            if not hl then
                hl = Instance.new("Highlight")
                hl.Name             = "_kr_hl"
                hl.FillTransparency = 1
                hl.DepthMode        = Enum.HighlightDepthMode.Occluded
                hl.Parent           = hb
            end
        else
            if hl then hl:Destroy() end
        end
    end)
end

local function stopHcKnifeReach()
    G.hcKnifeReachActive = false
    if _hcKnifeConn then _hcKnifeConn:Disconnect(); _hcKnifeConn = nil end
    local hb = _hcKnifeHitbox()
    if hb then
        pcall(function() hb.Size = HC_KNIFE_DEFAULT_SIZE end)
        pcall(function() hb.Transparency = 1 end)
        local hl = hb:FindFirstChild("_kr_hl")
        if hl then hl:Destroy() end
    end
end

F.games.hoodCustoms.knifeReach = makeToggle(startHcKnifeReach, stopHcKnifeReach, "hcKnifeReachActive")
F.games.hoodCustoms.knifeReach.setSize = function(n)
    HC_KNIFE_REACH_SIZE = math.clamp(tonumber(n) or HC_KNIFE_MAX, 1, HC_KNIFE_MAX)
end
F.games.hoodCustoms.knifeReach.getSize = function() return HC_KNIFE_REACH_SIZE end
F.games.hoodCustoms.knifeReach.maxSize = HC_KNIFE_MAX
F.games.hoodCustoms.knifeReach.setVisualize = function(b) HC_KNIFE_VISUALIZE = b == true end
F.games.hoodCustoms.knifeReach.getVisualize = function() return HC_KNIFE_VISUALIZE end

-- ============================================================
--  GAMES: HOOD CUSTOMS - ANTI-AFK TAG
--  Watches HumanoidRootPart.CharacterAFK (BillboardGui).Enabled.
--  When it goes true the game has flagged you as AFK; we fire
--  MainEvent:FireServer("RequestAFKDisplay", false) to clear it.
--  Survives respawn (re-hooks via CharacterAdded).
-- ============================================================
local _hcAfkPropConn = nil
local _hcAfkCharConn = nil

local function _hcAfkClearOnce()
    local me = ReplicatedStorage:FindFirstChild("MainEvent")
    if me then pcall(function() me:FireServer("RequestAFKDisplay", false) end) end
end

local function _hcAfkHook(char)
    if not char then return end
    local hrp = char:WaitForChild("HumanoidRootPart", 5); if not hrp then return end
    local gui = hrp:WaitForChild("CharacterAFK", 5); if not gui then return end
    if _hcAfkPropConn then _hcAfkPropConn:Disconnect() end

    -- Hide locally immediately so the tag never visually appears, even for one
    -- frame. The property-changed signal fires synchronously on assignment, so
    -- when the game tries to set Enabled=true we override it to false in the
    -- same call stack — the engine never gets a chance to render it.
    if gui.Enabled then
        pcall(function() gui.Enabled = false end)
        _hcAfkClearOnce()
    end
    _hcAfkPropConn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not G.hcAntiAfkTagActive then return end
        if gui.Enabled then
            pcall(function() gui.Enabled = false end)
            _hcAfkClearOnce()
        end
    end)
end

local function startHcAntiAfkTag()
    G.hcAntiAfkTagActive = true
    if _hcAfkCharConn then _hcAfkCharConn:Disconnect() end
    _hcAfkCharConn = lplr.CharacterAdded:Connect(function(c)
        if G.hcAntiAfkTagActive then task.spawn(_hcAfkHook, c) end
    end)
    if lplr.Character then task.spawn(_hcAfkHook, lplr.Character) end
end

local function stopHcAntiAfkTag()
    G.hcAntiAfkTagActive = false
    if _hcAfkPropConn then _hcAfkPropConn:Disconnect(); _hcAfkPropConn = nil end
    if _hcAfkCharConn then _hcAfkCharConn:Disconnect(); _hcAfkCharConn = nil end
end

F.games.hoodCustoms.antiAfkTag = makeToggle(startHcAntiAfkTag, stopHcAntiAfkTag, "hcAntiAfkTagActive")

-- always-on by default — clear any current AFK tag and lock the BillboardGui
-- to disabled for the rest of the session. The toggle in the UI can still
-- turn it off if needed; this just means the user doesn't have to touch it.
task.spawn(startHcAntiAfkTag)

-- ============================================================
--  GAMES: HOOD CUSTOMS - GODMODE
--  Continuously overrides leg-part CFrames each Heartbeat to stack
--  them inside HRP. The Heartbeat write is what gets shipped to the
--  server (we own our character's physics), so the server stores
--  the hidden CFrame — others see no legs, hit detection on the
--  legs fails. Locally, the Animator runs after Heartbeat and the
--  Motor6Ds yank the legs back to their natural pose for the render
--  frame, so visually you keep your legs.
--  Motor6Ds are never touched — toggling off lets them snap back.
-- ============================================================
local HC_GM_LEG_PARTS = {
    -- R15
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
    -- R6 fallback
    "Left Leg", "Right Leg",
}
local _hcGmConn = nil

local function startHcGodmode()
    G.hcGmActive = true
    if _hcGmConn then _hcGmConn:Disconnect() end
    local voidCF = CFrame.new(0, -50000, 0)
    _hcGmConn = RunService.Heartbeat:Connect(function()
        if not G.hcGmActive then return end
        local char = lplr.Character; if not char then return end
        for _, name in ipairs(HC_GM_LEG_PARTS) do
            local limb = char:FindFirstChild(name)
            if limb and limb:IsA("BasePart") then
                pcall(function() limb.CFrame = voidCF end)
            end
        end
    end)
end

local function stopHcGodmode()
    G.hcGmActive = false
    if _hcGmConn then _hcGmConn:Disconnect(); _hcGmConn = nil end
end

F.games.hoodCustoms.godmode = makeToggle(startHcGodmode, stopHcGodmode, "hcGmActive")

-- bulk teardown (call this when your GUI closes)
F.disableAll = function()
    stopFly(); stopSpeed(); stopBhop(); stopInfJump(); stopAntiAfk()
    stopClickTp(); stopAutoRe(); stopHcAutoReload(); stopHcKnifeReach(); stopHcAntiAfkTag(); stopAutoEquip(); stopHitboxExtender()
    stopHcAutoStomp(); stopHcGodmode(); stopNoclip(); stopFullbright(); stopFreecam()
    stopZoom(); stopSpin(); stopFlip(); stopIce()
    AimbotSettings.Enabled=false; CamLockSettings.Enabled=false
    TrigSettings.Enabled=false
    RageSettings.SilentForce=false; RageSettings.AutoShoot=false
    RageSettings.FaceTarget=false; RageSettings.Orbit=false
    RageSettings.CamSnap=false; RageSettings.SpeedPanic=false
    EspSettings.Enabled=false; stopEspRender()
end

return F
