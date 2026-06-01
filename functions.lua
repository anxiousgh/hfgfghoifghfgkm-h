-- cclosure.vip / vampireware functions module
-- GUI-agnostic: extracted gameplay logic from vampireware.lua
-- Usage:
--   local F = loadstring(game:HttpGet('https://raw.githubusercontent.com/anxiousgh/asdasdasdasdasd/main/functions.lua'))()
--   F.fly.toggle(); F.fly.setSpeed(80)
--   F.aimbot.setEnabled(true); F.aimbot.setFov(120); F.aimbot.setHitPart('Head')
--   F.esp.toggle(); F.esp.setBox(true)
-- See bottom of file for the full API table.

-- ============================================================
--  VERSION  (bumped on every push so you can verify which build
--           is actually running). Look at the watermark + load
--           notification to compare against the latest commit
--           on GitHub. Format: "YYYY-MM-DD HH:MM <short summary>"
-- ============================================================
local SCRIPT_VERSION = "v1.21.1"

--// services
local HttpService         = game:GetService("HttpService")
local TweenService        = game:GetService("TweenService")
local UserInputService    = game:GetService("UserInputService")
local RunService          = game:GetService("RunService")
local plrs                = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
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
    TargetUserId=nil, TargetPlayer=nil, SkipKnocked=false, IgnoreKnocked=false,
    ShowLine=true, ShowOutline=true, LineOrigin="Bottom", FaceTarget=false,
    OutlineColor = Color3.fromRGB(255, 80, 80),
    LineColor    = Color3.fromRGB(255, 60, 60),
    Orbit=false, OrbitDistance=15, OrbitSpeed=60, OrbitHeight=5,
    AutoShoot=false, AutoShootDist=50, AutoShootVis=true, AutoShootRequireTool=false,
    AutoShootCooldown=100, EquipDelay=0.5, FFCheck=true,
    -- when on, equip AutoShootEquipTool (from backpack) the moment
    -- a target enters AutoShootDist range, before firing.
    AutoShootEquip=false, AutoShootEquipTool="",
    -- post-knocked grace window (ms). If the target was seen knocked
    -- within the last N ms, hold fire even if they currently read as
    -- alive - covers the brief respawn window where the old corpse
    -- is still selectable but the new character isn't there yet.
    KnockedGraceDelay=0,
    SilentForce=false, SilentMethod="All",
    SpeedPanic=false, SpeedPanicVal=0,
    TpBehind=false, TpBehindDist=0,
    CamSnap=false, CamSmoothing=0.15,
    AutoSwitch=true, NotifyTarget=true,
    SwitchByMouse=false,
    -- Priority mode for rbGetTarget. One of:
    --   "Closest"         - world distance from local HRP (default)
    --   "Mouse"           - screen distance from cursor
    --   "Camera"          - smallest angle from camera lookvector
    --   "LowestHP"        - lowest Humanoid.Health first
    --   "HighestThreat"   - close + holding a tool first
    Priority="Closest",
}

local EspSettings = {
    Enabled=false, BoxESP=false, NameESP=false, HealthESP=false, HealthNum=false,
    DistanceESP=false, TracerESP=false, SkeletonESP=false, TeamCheck=false,
    ChamsEnabled=false, HeldItem=false, SelfESP=false,
    RadarEnabled=false, XCTEnabled=false, TracerHistory=false, TracerHistLen=2,
    BoxStyle="Corners", TracerOrigin="Bottom", ChamsStyle="Overlay",
    -- Colors (live-readable by render code; setters on F.esp).
    EnemyColor    = Color3.fromRGB(220,  60,  60),
    TeamColor     = Color3.fromRGB( 80, 220,  80),
    NeutralColor  = Color3.fromRGB(255, 255, 255),
    ChamsFill     = Color3.fromRGB(255,  60,  60),
    ChamsOutline  = Color3.fromRGB(255, 255, 255),
    HealthBarColor= Color3.fromRGB( 80, 220,  80),
    TracerColor   = Color3.fromRGB(255,  60,  60),
}

local _rbTargetList = {}

-- ============================================================
--  VISIBILITY HELPER (cache raw Raycast before any hooks)
-- ============================================================
local rawRaycast = workspace.Raycast
local _visParams = RaycastParams.new()
_visParams.FilterType = Enum.RaycastFilterType.Exclude

-- when strict, any raycast hit blocks visibility (even see-through /
-- no-collide / no-shadow parts). Default false matches the old "smart"
-- behavior that ignored decorative geometry.
local _visStrict = false
-- which point the visibility raycast STARTS from. One of:
--   "Camera" - workspace.CurrentCamera.CFrame.Position (default, classic)
--   "Head"   - lplr.Character.Head.Position
--   "Tool"   - currently-equipped Tool's Handle.Position, falls back to Head
local _visOrigin = "Camera"
local function _visGetOrigin()
    local mode = _visOrigin
    local c = lplr.Character
    if mode == "Tool" and c then
        local tool = c:FindFirstChildOfClass("Tool")
        local handle = tool and tool:FindFirstChild("Handle")
        if handle then return handle.Position end
        mode = "Head"  -- fall through if no tool equipped
    end
    if mode == "Head" and c then
        local head = c:FindFirstChild("Head")
        if head then return head.Position end
    end
    return workspace.CurrentCamera.CFrame.Position
end
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
        if _visStrict then return false end
        local hit = result.Instance
        if hit.Transparency >= 0.5 or not hit.CanCollide then
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
    G.flyActive=true
    if G.flyConn then G.flyConn:Disconnect() end
    G.flyConn=RunService.Heartbeat:Connect(function(dt)
        if not G.flyActive then return end
        local char=lplr.Character; if not char then return end
        local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
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

-- ============================================================
--  WALKSPEED  (real Humanoid.WalkSpeed override with anti-restore)
-- ============================================================
--  Forces Humanoid.WalkSpeed every frame. We write on BOTH
--  Heartbeat AND BindToRenderStep at the lowest priority --
--  RenderStep's "Last" priority runs after every Heartbeat /
--  Stepped connection, immediately before the camera renders,
--  so it's the absolute latest point in the frame we can write.
--  This wins the race against game scripts that try to clamp
--  WalkSpeed back to 16 on Heartbeat. Previously the game's
--  Heartbeat connection often ran after ours and we'd lose the
--  current frame's value -- on respawn the game's controller
--  hadn't initialized yet so our value stuck, which is why the
--  slider only "took effect" after a respawn.
--  Default game walkspeed is 16; stop() restores 16.
-- ============================================================
G.walkspeedValue  = 16
G.walkspeedActive = false
local _WS_BIND_NAME = "_F_WalkspeedEnforce"
local function _wsGetHum()
    local c = lplr.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function _wsEnforceOnce()
    if not G.walkspeedActive then return end
    local hum = _wsGetHum()
    if not hum then return end
    if hum.WalkSpeed ~= G.walkspeedValue then
        pcall(function() hum.WalkSpeed = G.walkspeedValue end)
    end
end
local function stopWalkspeed()
    G.walkspeedActive = false
    if G._wsHeartConn then G._wsHeartConn:Disconnect(); G._wsHeartConn = nil end
    pcall(function() RunService:UnbindFromRenderStep(_WS_BIND_NAME) end)
    local hum = _wsGetHum()
    if hum then pcall(function() hum.WalkSpeed = 16 end) end
end
local function startWalkspeed()
    G.walkspeedActive = true
    if G._wsHeartConn then G._wsHeartConn:Disconnect() end
    G._wsHeartConn = RunService.Heartbeat:Connect(_wsEnforceOnce)
    -- BindToRenderStep at the latest possible priority (after every
    -- Heartbeat/Stepped). Wrapped in pcall because the bind name
    -- might already be taken if start() is called twice.
    pcall(function() RunService:UnbindFromRenderStep(_WS_BIND_NAME) end)
    pcall(function()
        RunService:BindToRenderStep(_WS_BIND_NAME, Enum.RenderPriority.Last.Value + 1, _wsEnforceOnce)
    end)
end

-- ============================================================
--  JUMPPOWER  (real Humanoid.JumpPower override with anti-restore)
-- ============================================================
--  Same dual-event enforcement as walkspeed (Heartbeat +
--  RenderStep Last) PLUS re-enables the Jumping state every
--  tick so games that block jumping via SetStateEnabled get
--  overridden too.
-- ============================================================
G.jumpPowerValue  = 50
G.jumpPowerActive = false
local _JP_BIND_NAME = "_F_JumpPowerEnforce"
local function _jpGetHum()
    local c = lplr.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function _jpDesiredHeight()
    -- power 50 ~= height 7.2; mirror the slider in JumpHeight units
    return G.jumpPowerValue / 7
end
local function _jpEnforceOnce()
    if not G.jumpPowerActive then return end
    local hum = _jpGetHum()
    if not hum then return end
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
    pcall(function()
        if hum.UseJumpPower then
            if hum.JumpPower ~= G.jumpPowerValue then
                hum.JumpPower = G.jumpPowerValue
            end
        else
            local h = _jpDesiredHeight()
            if math.abs(hum.JumpHeight - h) > 0.05 then
                hum.JumpHeight = h
            end
        end
    end)
end
local function stopJumpPower()
    G.jumpPowerActive = false
    if G._jpHeartConn then G._jpHeartConn:Disconnect(); G._jpHeartConn = nil end
    pcall(function() RunService:UnbindFromRenderStep(_JP_BIND_NAME) end)
    local hum = _jpGetHum()
    if hum then
        pcall(function()
            if hum.UseJumpPower then hum.JumpPower = 50 else hum.JumpHeight = 7.2 end
        end)
    end
end
local function startJumpPower()
    G.jumpPowerActive = true
    if G._jpHeartConn then G._jpHeartConn:Disconnect() end
    G._jpHeartConn = RunService.Heartbeat:Connect(_jpEnforceOnce)
    pcall(function() RunService:UnbindFromRenderStep(_JP_BIND_NAME) end)
    pcall(function()
        RunService:BindToRenderStep(_JP_BIND_NAME, Enum.RenderPriority.Last.Value + 1, _jpEnforceOnce)
    end)
end

-- ============================================================
--  CFRAME SPEED  (camera-WASD-driven CFrame nudge - "speed hack")
-- ============================================================
local function stopCframeSpeed()
    G.speedActive=false; if G.speedConn then G.speedConn:Disconnect(); G.speedConn=nil end
end
local function startCframeSpeed(mult)
    G.speedActive=true; G.speedValue=mult or 2
    if G.speedConn then G.speedConn:Disconnect() end
    G.speedConn=RunService.Heartbeat:Connect(function(dt)
        if not G.speedActive then return end
        if UserInputService:GetFocusedTextBox() then return end
        local char=lplr.Character; if not char then return end
        local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
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

-- ============================================================
--  FORCE-ENABLE JUMP
--  Defeats games that limit / disable jumping. Three common
--  mechanisms covered:
--    1. Humanoid:SetStateEnabled(Jumping, false) - we re-enable
--       on every Space press AND on every property write the
--       game makes via PropertyChangedSignal.
--    2. Humanoid.JumpPower = 0 / JumpHeight = 0 - we re-write
--       to a safe value whenever the game tries to zero them.
--    3. Custom jump counter that just decides not to fire
--       Humanoid.Jump = true - we directly write Humanoid.Jump
--       = true on Space press, bypassing the game's check.
-- ============================================================
local _forceJumpConns = {}
local function _fjClear()
    for _, c in ipairs(_forceJumpConns) do pcall(function() c:Disconnect() end) end
    _forceJumpConns = {}
end
local function _fjEnforce(hum)
    if not hum then return end
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
    pcall(function()
        if hum.UseJumpPower then
            if hum.JumpPower <= 0 then hum.JumpPower = 50 end
        else
            if hum.JumpHeight <= 0 then hum.JumpHeight = 7.2 end
        end
    end)
end
local function _fjHookChar(char)
    _fjClear()
    local hum = char:WaitForChild("Humanoid", 5)
    if not hum then return end
    _fjEnforce(hum)
    table.insert(_forceJumpConns, hum:GetPropertyChangedSignal("JumpPower"):Connect(function()
        if G.forceJumpActive then _fjEnforce(hum) end
    end))
    table.insert(_forceJumpConns, hum:GetPropertyChangedSignal("JumpHeight"):Connect(function()
        if G.forceJumpActive then _fjEnforce(hum) end
    end))
end
local function stopForceJump()
    G.forceJumpActive = false
    _fjClear()
    if G._fjCharConn  then G._fjCharConn:Disconnect();  G._fjCharConn  = nil end
    if G._fjInputConn then G._fjInputConn:Disconnect(); G._fjInputConn = nil end
end
local function startForceJump()
    G.forceJumpActive = true
    if G._fjCharConn then G._fjCharConn:Disconnect() end
    G._fjCharConn = lplr.CharacterAdded:Connect(function(c)
        if G.forceJumpActive then _fjHookChar(c) end
    end)
    if lplr.Character then _fjHookChar(lplr.Character) end
    if G._fjInputConn then G._fjInputConn:Disconnect() end
    G._fjInputConn = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if not G.forceJumpActive then return end
        if input.KeyCode ~= Enum.KeyCode.Space then return end
        local c = lplr.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        if hum then
            -- re-enable state + JumpPower right before the actual jump
            -- (handles "you jumped 3 times, jump is on cooldown" cases
            -- where the game flipped state/power right before this press)
            _fjEnforce(hum)
            pcall(function() hum.Jump = true end)
        end
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
            -- firesignal(lplr.Idled) was here but is a no-op (and a footgun):
            -- the connections to lplr.Idled were disabled in startAntiAfk above,
            -- so firing the signal does nothing. If a future change re-enables
            -- those connections it would actively *trigger* the AFK kick.
            -- The VirtualInputManager W-press below is what actually keeps the
            -- engine considering us "active".
            pcall(function()
                local vim=VirtualInputManager
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
                local pos = result.Position + Vector3.new(0, 3, 0)
                local lv  = hrp.CFrame.LookVector
                local horiz = Vector3.new(lv.X, 0, lv.Z)
                if horiz.Magnitude < 0.01 then horiz = Vector3.new(0, 0, -1) end
                horiz = horiz.Unit
                pcall(function()
                    hrp.CFrame = CFrame.new(pos, pos + horiz)
                    hrp.AssemblyLinearVelocity  = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                end)
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
    -- pre-clean: if we're ragdolled / upside-down / sitting, joint
    -- forces will yank HRP back the moment after we set CFrame. Clear
    -- those states FIRST so the humanoid stops fighting the teleport.
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum.PlatformStand = false end)
            pcall(function() hum.Sit            = false end)
        end
    end

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
    local newCF = CFrame.new(position, position + horiz)
    pcall(function()
        hrp.CFrame = newCF
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    -- notify desync so its Heartbeat-captured realCF gets updated to the
    -- new position. otherwise its RenderStepped restore would undo our TP.
    if F and F.desync and F.desync.notifyTeleport then
        F.desync.notifyTeleport(newCF)
    end
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
            if newHrp then
                task.wait(0.15)
                local upright = _uprightCF(cf)
                if upright then pcall(function() newHrp.CFrame = upright end) end
            end
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
        -- snapshot G.savedCFrame BEFORE the yield. Otherwise a second
        -- cmdRe / autoRe Once may set it to nil during task.wait(0.1)
        -- and we'd assign nil to CFrame ("CoordinateFrame expected, got nil")
        local cf = G.savedCFrame
        G.savedCFrame = nil
        if cf then
            local newHrp = newChar:WaitForChild("HumanoidRootPart",5)
            if newHrp then
                task.wait(0.1)
                local upright = _uprightCF(cf)
                if upright then pcall(function() newHrp.CFrame = upright end) end
            end
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
-- Standard noclip: just override CanCollide=false every Heartbeat while
-- active. We deliberately do NOT use getconnections():Disable() on the
-- engine's CanCollide listeners - that left collision in a broken state
-- on toggle off (engine internals stay desynced even after Enable()).
-- Per-frame override is enough; on stop we just stop overriding and the
-- engine takes back over.
local function stopNoclip()
    G.noclipActive=false
    pcall(function() RunService:UnbindFromRenderStep("NoclipStep") end)
    if G.noclipHBConn then G.noclipHBConn:Disconnect(); G.noclipHBConn=nil end
    if G.noclipConn and type(G.noclipConn)~="boolean" then G.noclipConn:Disconnect() end
    G.noclipConn=nil
    -- restore CanCollide on the parts we were overriding. The engine
    -- doesn't auto-restore once we stop writing false - parts stay at
    -- the last value, so the character keeps passing through walls
    -- after the toggle is off. Set them back to true here.
    local c = lplr.Character
    if c then
        for _, name in ipairs({"HumanoidRootPart","UpperTorso","Torso","Head","LowerTorso"}) do
            local p = c:FindFirstChild(name)
            if p and p:IsA("BasePart") then
                pcall(function() p.CanCollide = true end)
            end
        end
    end
end
local function startNoclip()
    G.noclipActive=true
    -- only the 5 collision-relevant parts need CanCollide=false; iterating
    -- char:GetDescendants() every Heartbeat (accessories, decals, attachments,
    -- scripts) was wasted work. Audit flagged this as a freeze contributor.
    RunService:BindToRenderStep("NoclipStep", Enum.RenderPriority.First.Value, function()
        if not G.noclipActive then return end
        local c=lplr.Character; if not c then return end
        for _,name in ipairs({"HumanoidRootPart","UpperTorso","Torso","Head","LowerTorso"}) do
            local p=c:FindFirstChild(name); if p then p.CanCollide=false end
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
    if G._freecamCharConn then G._freecamCharConn:Disconnect(); G._freecamCharConn=nil end
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
    -- anchor body + zero walkspeed/jump on every (re)spawn while active.
    -- without the CharacterAdded hook, the new character would drift away
    -- from where freecam expected to anchor it after a respawn.
    local function anchorChar(char)
        if not char then return end
        local hrp=char:WaitForChild("HumanoidRootPart",5)
        if hrp then
            local existing=hrp:FindFirstChild("FreecamAnchor")
            if existing then existing:Destroy() end
            local bv=Instance.new("BodyVelocity")
            bv.Name="FreecamAnchor"; bv.Velocity=Vector3.zero
            bv.MaxForce=Vector3.new(1e5,1e5,1e5); bv.Parent=hrp
        end
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed=0; hum.JumpPower=0 end
    end
    anchorChar(lplr.Character)
    if G._freecamCharConn then G._freecamCharConn:Disconnect() end
    G._freecamCharConn=lplr.CharacterAdded:Connect(function(c)
        if G.freecamActive then anchorChar(c) end
    end)
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
    pcall(function() RunService:UnbindFromRenderStep("FlipRestore") end)
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
        -- camera offset zeroed: BindToRenderStep at First priority below
        -- restores HRP BEFORE the camera samples it, so the camera
        -- naturally stays at the local upright head position. No offset
        -- needed - and the previous -5 offset put the camera above the
        -- head because the timing fixed itself differently here.
        if hum then hum.CameraOffset=Vector3.zero end
        local _real={}; local _spoofing=false
        if G._flipHb then G._flipHb:Disconnect() end
        pcall(function() RunService:UnbindFromRenderStep("FlipRestore") end)
        G._flipHb=RunService.Heartbeat:Connect(function()
            if not hrp or not hrp.Parent then return end
            _real[1]=hrp.CFrame; _real[2]=hrp.AssemblyLinearVelocity; _spoofing=true
            local look=hrp.CFrame.LookVector
            local yaw=math.atan2(look.X,look.Z)
            hrp.CFrame=CFrame.new(hrp.Position)*CFrame.fromEulerAnglesYXZ(0,yaw,0)*CFrame.Angles(math.pi,0,0)
        end)
        -- restore at First priority so the default camera sees the upright
        -- local HRP, not the spoofed flipped one
        RunService:BindToRenderStep("FlipRestore", Enum.RenderPriority.First.Value, function()
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

-- ---- Tilt 90° (sideways roll) ----
-- Same Heartbeat-spoof / RenderStep-First-restore pattern as flip, but
-- the spoof multiplies by CFrame.Angles(0,0,math.pi/2) instead of (pi,0,0).
-- Server sees us lying on our side; locally we're upright (camera locked
-- to local head via First-priority restore).
local function stopTilt()
    G.tiltActive=false
    if G._tiltHb then G._tiltHb:Disconnect(); G._tiltHb=nil end
    pcall(function() RunService:UnbindFromRenderStep("TiltRestore") end)
    if G._tiltCharConn then G._tiltCharConn:Disconnect(); G._tiltCharConn=nil end
    local char=lplr.Character
    if char then
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.CameraOffset=Vector3.zero end
    end
end
local function startTilt()
    G.tiltActive=true
    local function setup(char)
        if not char then return end
        local hrp=char:WaitForChild("HumanoidRootPart",5); if not hrp then return end
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.CameraOffset=Vector3.zero end
        local _real={}; local _spoofing=false
        if G._tiltHb then G._tiltHb:Disconnect() end
        pcall(function() RunService:UnbindFromRenderStep("TiltRestore") end)
        G._tiltHb=RunService.Heartbeat:Connect(function()
            if not hrp or not hrp.Parent then return end
            _real[1]=hrp.CFrame; _real[2]=hrp.AssemblyLinearVelocity; _spoofing=true
            local look=hrp.CFrame.LookVector
            local yaw=math.atan2(look.X,look.Z)
            -- preserve yaw, tilt 90° on Z (sideways)
            hrp.CFrame=CFrame.new(hrp.Position)*CFrame.fromEulerAnglesYXZ(0,yaw,0)*CFrame.Angles(0,0,math.pi/2)
        end)
        RunService:BindToRenderStep("TiltRestore", Enum.RenderPriority.First.Value, function()
            if _spoofing and _real[1] then
                if hrp and hrp.Parent then hrp.CFrame=_real[1]; hrp.AssemblyLinearVelocity=_real[2] end
                _spoofing=false
            end
        end)
    end
    setup(lplr.Character)
    G._tiltCharConn=lplr.CharacterAdded:Connect(function(c)
        if G.tiltActive then task.wait(0.1); setup(c) end
    end)
end

-- ---- Backwards (180° yaw - server sees us facing the opposite way) ----
-- Useful as anti-aim: enemies' silent aim/aimbot points at the back of
-- our head while our local head is facing the other way.
local function stopBackwards()
    G.backwardsActive=false
    if G._bwHb then G._bwHb:Disconnect(); G._bwHb=nil end
    pcall(function() RunService:UnbindFromRenderStep("BackwardsRestore") end)
    if G._bwCharConn then G._bwCharConn:Disconnect(); G._bwCharConn=nil end
    local char=lplr.Character
    if char then
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.CameraOffset=Vector3.zero end
    end
end
local function startBackwards()
    G.backwardsActive=true
    local function setup(char)
        if not char then return end
        local hrp=char:WaitForChild("HumanoidRootPart",5); if not hrp then return end
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.CameraOffset=Vector3.zero end
        local _real={}; local _spoofing=false
        if G._bwHb then G._bwHb:Disconnect() end
        pcall(function() RunService:UnbindFromRenderStep("BackwardsRestore") end)
        G._bwHb=RunService.Heartbeat:Connect(function()
            if not hrp or not hrp.Parent then return end
            _real[1]=hrp.CFrame; _real[2]=hrp.AssemblyLinearVelocity; _spoofing=true
            local look=hrp.CFrame.LookVector
            local yaw=math.atan2(look.X,look.Z)
            -- rotate yaw by 180° so we face the opposite direction
            hrp.CFrame=CFrame.new(hrp.Position)*CFrame.fromEulerAnglesYXZ(0,yaw+math.pi,0)
        end)
        RunService:BindToRenderStep("BackwardsRestore", Enum.RenderPriority.First.Value, function()
            if _spoofing and _real[1] then
                if hrp and hrp.Parent then hrp.CFrame=_real[1]; hrp.AssemblyLinearVelocity=_real[2] end
                _spoofing=false
            end
        end)
    end
    setup(lplr.Character)
    G._bwCharConn=lplr.CharacterAdded:Connect(function(c)
        if G.backwardsActive then task.wait(0.1); setup(c) end
    end)
end

local function stopSpin()
    G.spinActive=false
    if G._spinCharConn then G._spinCharConn:Disconnect(); G._spinCharConn=nil end
    G._spinGyro=nil
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
    local function setup(char)
        if not char then return end
        local hrp=char:WaitForChild("HumanoidRootPart",5); if not hrp then return end
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate=false end
        -- clear any stale gyro on this (potentially recycled) HRP before re-creating
        local existing=hrp:FindFirstChild("SpinGyro")
        if existing then existing:Destroy() end
        local gyro=Instance.new("BodyAngularVelocity")
        gyro.Name="SpinGyro"; gyro.AngularVelocity=Vector3.new(0,SPIN_SPEED,0)
        gyro.MaxTorque=Vector3.new(0,1e6,0); gyro.Parent=hrp
        G._spinGyro=gyro
    end
    setup(lplr.Character)
    if G._spinCharConn then G._spinCharConn:Disconnect() end
    G._spinCharConn=lplr.CharacterAdded:Connect(function(c)
        if G.spinActive then setup(c) end
    end)
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

-- Sticky emotes module lives down by F.stickyEmote registration
-- (search for "F.stickyEmote = (function()") so it can build the
-- F.stickyEmote table directly without consuming top-level chunk
-- locals. Luau has a 200-local-register-per-function limit and the
-- chunk was right at it.

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
--  FOLLOW PLAYER (pathfinding)
--  Continuously walks toward the target using PathfindingService.
--  Click to start, click again on the same target to stop.
-- ============================================================
local _PathfindingService = game:GetService("PathfindingService")
local _follow = {
    target = nil, conn = nil, path = nil, waypoints = {}, idx = 1,
    lastCompute = 0, viz = true, vizFolder = nil,
    -- Steering state read every Heartbeat by the steerConn loop.
    -- Updated (but never interrupted) by the path worker.
    steerDir  = Vector3.zero,
    steerJump = false,
    steerConn = nil,
}

-- ---- pathfinding visualization ----
-- Spawns small neon spheres at each waypoint and thin neon parts
-- as line segments between consecutive waypoints. Jump waypoints
-- get a distinct color. The "current" waypoint (the one we're
-- walking toward this tick) is highlighted brighter.
local function vizClear()
    if _follow.vizFolder then _follow.vizFolder:Destroy(); _follow.vizFolder = nil end
end

local function vizDot(pos, color, size)
    local p = Instance.new("Part")
    p.Anchored = true; p.CanCollide = false
    p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
    p.Shape = Enum.PartType.Ball
    p.Material = Enum.Material.Neon
    p.Color = color
    p.Size = Vector3.new(size, size, size)
    p.CFrame = CFrame.new(pos)
    p.Parent = _follow.vizFolder
    return p
end

local function vizLine(a, b, color)
    local dist = (b - a).Magnitude
    if dist < 0.1 then return end
    local p = Instance.new("Part")
    p.Anchored = true; p.CanCollide = false
    p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
    p.Material = Enum.Material.Neon
    p.Color = color
    p.Transparency = 0.4
    p.Size = Vector3.new(0.3, 0.3, dist)
    p.CFrame = CFrame.new((a + b) * 0.5, b)
    p.Parent = _follow.vizFolder
end

local function vizRebuild()
    vizClear()
    if not _follow.viz then return end
    if #_follow.waypoints < 2 then return end
    _follow.vizFolder = Instance.new("Folder")
    _follow.vizFolder.Name = "_follow_path_viz"
    _follow.vizFolder.Parent = workspace
    local walkCol = Color3.fromRGB(80, 200, 255)
    local jumpCol = Color3.fromRGB(255, 180, 60)
    local nextCol = Color3.fromRGB(120, 255, 120)
    for i = 1, #_follow.waypoints do
        local wp = _follow.waypoints[i]
        local isJump = wp.Action == Enum.PathWaypointAction.Jump
        local isNext = i == _follow.idx
        local col = isNext and nextCol or (isJump and jumpCol or walkCol)
        vizDot(wp.Position, col, isNext and 1.5 or 1.0)
        if i > 1 then
            vizLine(_follow.waypoints[i - 1].Position, wp.Position, col)
        end
    end
end

local function followStop()
    _follow.target = nil  -- the worker task exits on its next yield
    _follow.waypoints = {}
    _follow.idx = 1
    vizClear()
    local c = lplr.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if hum then
        -- Move(0) halts the continuous direction set by the worker.
        -- MoveTo(self) is a belt-and-suspenders stop for any legacy path.
        pcall(function() hum:Move(Vector3.zero, false) end)
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if hrp then pcall(function() hum:MoveTo(hrp.Position) end) end
    end
end

-- helpers for follow worker
local function _followGetLocal()
    local c = lplr.Character
    if not c then return nil, nil end
    return c:FindFirstChildOfClass("Humanoid"), c:FindFirstChild("HumanoidRootPart")
end

local function _followGetTargetHRP()
    local t = _follow.target
    if not t or not t.Parent then return nil end
    local tc = t.Character
    return tc and tc:FindFirstChild("HumanoidRootPart")
end

-- Walk to a waypoint: issue MoveTo, then wait until either we get close
-- enough, the target/our character changes, or we time out (stuck on
-- geometry). Returns true if we made it, false if the worker should stop.
-- Polls per-Heartbeat (no task.wait) so close-enough detection is instant.
local function _followWalkTo(hum, pos, isJump, timeout)
    if not hum or not hum.Parent then return false end
    pcall(function() hum:MoveTo(pos) end)
    if isJump then pcall(function() hum.Jump = true end) end
    local target = _follow.target
    local startT = tick()
    while _follow.target == target do
        local _, hrp = _followGetLocal()
        if not hrp then return false end
        if (hrp.Position - pos).Magnitude < 4 then return true end
        if tick() - startT > timeout then return true end  -- give up, continue
        RunService.Heartbeat:Wait()
    end
    return false
end

local function followPlayer(plr)
    if typeof(plr) == "string" then plr = findPlayerByName(plr) end
    if _follow.target == plr then followStop(); return end
    followStop()
    if not plr then return end
    _follow.target = plr
    _follow.path = _PathfindingService:CreatePath({
        AgentRadius     = 1.5,
        AgentHeight     = 5,
        AgentCanJump    = true,
        AgentJumpHeight = 7.2,
        AgentMaxSlope   = 45,
    })

    -- Classic Humanoid:MoveTo() + MoveToFinished:Wait() pattern.
    -- The two-loop steerDir / steerConn approach was flaky in practice
    -- because Humanoid:Move(dir, false) only persists for one physics
    -- step before the default character controller overrides it, and
    -- on games that write to the Humanoid every frame (HC) our calls
    -- got silently clobbered - net result was no movement at all.
    --
    -- MoveTo issues a single walk command the humanoid honors until
    -- it reaches the goal, hits the 8s timeout, or we issue a new
    -- MoveTo. We re-issue every waypoint and bail out of the path
    -- early if we get close to the actual target.
    task.spawn(function()
        local target = plr
        while _follow.target == target do
            local hum, hrp = _followGetLocal()
            local thrp     = _followGetTargetHRP()
            if not (hum and hrp and thrp) then
                task.wait(0.2); continue
            end

            local dToTarget = (hrp.Position - thrp.Position).Magnitude

            -- Close enough: direct walk, no pathfinding.
            if dToTarget < 8 then
                pcall(function() hum:MoveTo(thrp.Position) end)
                task.wait(0.15)
                continue
            end

            -- Pathfind, then walk through up to 6 waypoints before
            -- recomputing (target may have moved a lot).
            local ok = pcall(function()
                _follow.path:ComputeAsync(hrp.Position, thrp.Position)
            end)
            if ok and _follow.path.Status == Enum.PathStatus.Success then
                _follow.waypoints = _follow.path:GetWaypoints()
                vizRebuild()
                for i = 2, math.min(#_follow.waypoints, 7) do
                    if _follow.target ~= target then break end
                    local hum2, hrp2 = _followGetLocal()
                    if not hum2 or not hrp2 then break end
                    local wp = _follow.waypoints[i]
                    _follow.idx = i; vizRebuild()
                    if wp.Action == Enum.PathWaypointAction.Jump then
                        pcall(function() hum2.Jump = true end)
                    end
                    pcall(function() hum2:MoveTo(wp.Position) end)
                    -- Wait for arrival or 1.5s timeout (per waypoint).
                    -- MoveToFinished can fire false if the humanoid gives
                    -- up; either way we move to the next waypoint.
                    local finished = false
                    task.spawn(function()
                        hum2.MoveToFinished:Wait()
                        finished = true
                    end)
                    local waited = 0
                    while not finished and waited < 1.5 and _follow.target == target do
                        RunService.Heartbeat:Wait()
                        waited = waited + (1/60)
                    end
                    -- Early-exit: if we're already near the actual target,
                    -- stop walking the rest of the (now stale) path.
                    local _, hrp3 = _followGetLocal()
                    if hrp3 and (hrp3.Position - thrp.Position).Magnitude < 8 then break end
                end
            else
                -- NoPath: try direct walk; if still stuck, the next
                -- iteration recomputes.
                pcall(function() hum:MoveTo(thrp.Position) end)
                task.wait(0.5)
            end
        end
        vizClear()
    end)
end

local function followSetVisualize(v)
    _follow.viz = v == true
    if not _follow.viz then vizClear() else vizRebuild() end
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
    local camPos=_visGetOrigin()
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
        if F.whitelist and F.whitelist.contains(plr) then continue end
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

-- aimbot per-frame: update cached target + draw.
--
-- Fast early-out: if nothing in aimbot wants per-frame work
-- (Enabled, ShowFOV, ShowTarget all off), bail immediately. Avoids
-- a full Players scan / WorldToViewportPoint / GetMouseLocation per
-- frame while the feature is off - cumulative cost shows up as
-- "freezes" when combined with the other always-on loops.
RunService.RenderStepped:Connect(function()
    if not AimbotSettings.Enabled
        and not AimbotSettings.ShowFOV
        and not AimbotSettings.ShowTarget then
        -- Cheap idle path: hide any drawings still left visible from
        -- when the feature was last on, clear cached target, return.
        if cachedTarget then cachedTarget = nil; cachedHitPoint = nil end
        if A_fovCircle and A_fovCircle.Visible  then A_fovCircle.Visible  = false end
        if A_targetBox and A_targetBox.Visible  then A_targetBox.Visible  = false end
        return
    end
    if AimbotSettings.Enabled then
        cachedTarget, cachedHitPoint = aimFindClosest()
    else
        cachedTarget = nil; cachedHitPoint = nil
    end
    if A_fovCircle then
        A_fovCircle.Visible = AimbotSettings.ShowFOV
        if AimbotSettings.ShowFOV then
            local mousePos = UserInputService:GetMouseLocation()
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
    -- track tool presence with event-driven updates instead of per-frame
    -- char:GetChildren() walks. Saves an unconditional RenderStepped that
    -- ran forever even when aimbot was off.
    local hasTool = false
    local _toolWatchers = {}
    local function _refreshTool(c)
        if not c then hasTool = false; return end
        hasTool = false
        for _, v in ipairs(c:GetChildren()) do
            if v:IsA("Tool") then hasTool = true; break end
        end
    end
    local function _hookChar(c)
        if not c then return end
        for _, conn in ipairs(_toolWatchers) do pcall(function() conn:Disconnect() end) end
        _toolWatchers = {}
        table.insert(_toolWatchers, c.ChildAdded:Connect(function(ch) if ch:IsA("Tool") then hasTool = true end end))
        table.insert(_toolWatchers, c.ChildRemoved:Connect(function(ch) if ch:IsA("Tool") then _refreshTool(c) end end))
        _refreshTool(c)
    end
    lplr.CharacterAdded:Connect(_hookChar)
    if lplr.Character then _hookChar(lplr.Character) end

    -- guard against re-stacking on script reload: if we've already
    -- installed __namecall, bail. Each stacked wrapper adds latency to
    -- every Raycast call, which compounds freezing on rerun.
    if not getgenv()._F_NAMECALL_HOOKED then
        getgenv()._F_NAMECALL_HOOKED = true
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
        -- Cheap-bool early-outs FIRST. Roblox calls __namecall thousands of
        -- times per second; the previous version did getnamecallmethod() +
        -- 5 string compares for every single call before checking Enabled.
        -- That overhead compounds with the ragebot/voidspam hooks and was
        -- a freeze contributor.
        if not AimbotSettings.Enabled then return oldNamecall(...) end
        if not cachedTarget then return oldNamecall(...) end
        if not hasTool then return oldNamecall(...) end
        if checkcaller() then return oldNamecall(...) end
        local method = getnamecallmethod()
        if method ~= "Raycast" and method ~= "FindPartOnRay" and method ~= "findPartOnRay"
            and method ~= "FindPartOnRayWithIgnoreList" and method ~= "FindPartOnRayWithWhitelist" then
            return oldNamecall(...)
        end
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
    end -- _F_NAMECALL_HOOKED guard
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
    local camPos=_visGetOrigin()
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
    for _, plr in ipairs(_cachedPlayers or plrs:GetPlayers()) do
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
    -- Fast early-out: skip the entire camlock per-frame when nothing
    -- in the module wants work (both Enabled and ShowFOV are off).
    -- Avoids repeated property writes to the FOV circle while the
    -- feature is idle.
    if not CamLockSettings.Enabled and not CamLockSettings.ShowFOV then
        if clStickyTarget then clStickyTarget = nil end
        if CL_fovCircle and CL_fovCircle.Visible then CL_fovCircle.Visible = false end
        return
    end
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
    local camPos=_visGetOrigin()
    local ignore={lchar,char}
    for _,p in ipairs(_cachedPlayers) do
        if p.Character and p.Character~=char and p.Character~=lchar then table.insert(ignore,p.Character) end
    end
    return isReallyVisible(camPos, hrp.Position, ignore)
end

local _trigLastShot = 0
local _trigCurrentPart = nil  -- currently-best target part this frame, for ShowTarget
RunService.Heartbeat:Connect(function()
    -- Fast early-out: skip GetMouseLocation + camera lookup + everything
    -- when triggerbot is fully idle. The old path still hit UIS +
    -- workspace.CurrentCamera each frame even when nothing was on.
    if not TrigSettings.Enabled and not TrigSettings.ShowFOV and not TrigSettings.ShowTarget then
        if TB_fovCircle and TB_fovCircle.Visible then TB_fovCircle.Visible = false end
        if TB_targetBox and TB_targetBox.Visible then TB_targetBox.Visible = false end
        return
    end
    local cam = workspace.CurrentCamera
    local mousePos = UserInputService:GetMouseLocation()

    if TB_fovCircle then
        TB_fovCircle.Visible = TrigSettings.ShowFOV
        if TrigSettings.ShowFOV then
            TB_fovCircle.Position = mousePos
            TB_fovCircle.Radius   = TrigSettings.FOVRadius
        end
    end

    -- early-out: if nothing is asking for a target this frame, skip the
    -- per-player + per-part scan entirely.
    if not TrigSettings.Enabled and not TrigSettings.ShowTarget then
        if TB_targetBox then TB_targetBox.Visible = false end
        return
    end

    -- find best player inside FOV.
    -- TargetPart "All" → scan every BasePart and pick closest to mouse.
    local hitPlr, hitPart, bestD = nil, nil, math.huge
    for _, plr in ipairs(_cachedPlayers or plrs:GetPlayers()) do
        if plr == lplr then continue end
        if F.whitelist and F.whitelist.contains(plr) then continue end
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
        local vim = VirtualInputManager
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
-- Snapshot of Humanoid.AutoRotate before we forced it off lives on G
-- (G._rbFaceSavedAutoRotate) to avoid eating a top-level local slot -
-- the chunk function is right at Luau's 200-local-per-function limit.
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
    local camPos = _visGetOrigin()
    local ignore = {lchar, char}
    for _, p in ipairs(plrs:GetPlayers()) do
        if p.Character and p.Character ~= char and p.Character ~= lchar then table.insert(ignore, p.Character) end
    end
    return isReallyVisible(camPos, root.Position, ignore)
end

-- Returns true if the target should be completely skipped from selection
-- (IgnoreKnocked mode). Separate from SkipKnocked which only blocks the
-- auto-shoot but keeps the target locked.
local function rbIgnoreByKnocked(plr)
    if not RageSettings.IgnoreKnocked then return false end
    local hc = F and F.games and F.games.hoodCustoms
    if not hc or not hc.isKnocked then return false end
    local ok, knocked = pcall(hc.isKnocked, plr)
    return ok and knocked
end

-- score a candidate target for a priority mode. lower = better.
-- returns math.huge to exclude the candidate from selection.
local function rbScoreTarget(plr, char, hrp, hum, lhrp, cam, mousePos, camPos, camLook)
    local mode = RageSettings.Priority or "Closest"
    if RageSettings.SwitchByMouse and mode == "Closest" then mode = "Mouse" end
    if mode == "Mouse" then
        local sp, onScreen = cam:WorldToViewportPoint(hrp.Position)
        if not onScreen then return math.huge end
        return (mousePos - Vector2.new(sp.X, sp.Y)).Magnitude
    elseif mode == "Camera" then
        local toTarget = (hrp.Position - camPos).Unit
        local dotV = toTarget:Dot(camLook)
        if dotV <= 0 then return math.huge end  -- behind us
        return 1 - dotV  -- closer to 0 = more directly in front
    elseif mode == "LowestHP" then
        return hum.Health
    elseif mode == "HighestThreat" then
        -- threat = closeness + tool drawn. lower distance + tool out = best.
        local d = lhrp and (lhrp.Position - hrp.Position).Magnitude or math.huge
        local hasTool = char:FindFirstChildOfClass("Tool") ~= nil
        return d + (hasTool and 0 or 1000)
    end
    -- Closest (default fallback)
    return lhrp and (lhrp.Position - hrp.Position).Magnitude or math.huge
end

local function rbGetTarget()
    if #_rbTargetList > 0 then
        local lchar=lplr.Character
        local lhrp=lchar and lchar:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        local mousePos = UserInputService:GetMouseLocation()
        local camCF = cam.CFrame
        local camPos, camLook = camCF.Position, camCF.LookVector
        local best, bestScore = nil, math.huge
        for _,entry in ipairs(_rbTargetList) do
            if not entry.plr or not entry.plr.Parent then
                for _,p in ipairs(plrs:GetPlayers()) do
                    if p.UserId==entry.userId then entry.plr=p; break end
                end
            end
            local plr=entry.plr; if not plr or not plr.Parent then continue end
            if F.whitelist and F.whitelist.contains(plr) then continue end  -- skip whitelisted players
            local char=plr.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            local hum=char:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health<=0 then continue end
            if rbIgnoreByKnocked(plr) then continue end
            local score = rbScoreTarget(plr, char, hrp, hum, lhrp, cam, mousePos, camPos, camLook)
            if score < bestScore then bestScore = score; best = plr end
        end
        if best then RageSettings.TargetPlayer=best; RageSettings.TargetUserId=best.UserId; return best end
    end
    local uid=RageSettings.TargetUserId; if not uid then return nil end
    local plr=RageSettings.TargetPlayer
    if plr and plr.Parent and plr.UserId==uid then
        if rbIgnoreByKnocked(plr) then return nil end
        return plr
    end
    for _,p in ipairs(plrs:GetPlayers()) do
        if p.UserId==uid then
            if F.whitelist and F.whitelist.contains(p) then return nil end
            if rbIgnoreByKnocked(p) then return nil end
            RageSettings.TargetPlayer=p; return p
        end
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
        if F.whitelist and F.whitelist.contains(plr) then continue end
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
    -- early-out when nothing is asking for ragebot work - skips the
    -- rbGetTarget() player-iteration each frame at idle. Audit flagged
    -- this as an always-on RenderStepped consumer.
    if not RageSettings.SilentForce
        and not RageSettings.AutoShoot
        and not RageSettings.ShowLine
        and not RageSettings.ShowOutline
        and not RageSettings.CamSnap
        and not RageSettings.FaceTarget
        and not RageSettings.SpeedPanic
        and not RageSettings.TargetPlayer
        and (not _rbTargetList or #_rbTargetList == 0)
    then
        if RB_targetLine then RB_targetLine.Visible = false end
        if RB_outlineHL  then RB_outlineHL.Enabled  = false end
        rbCachedTarget = nil
        return
    end
    local plr = rbGetTarget()
    local char = plr and plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    rbCachedTarget = hrp

    -- target line origin: Bottom / Center / Top / Mouse
    -- Always draw - even when target is off-screen or behind the camera
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
                RB_targetLine.Color = RageSettings.LineColor or Color3.fromRGB(255, 80, 80)
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
        hl.OutlineColor = RageSettings.OutlineColor or Color3.fromRGB(255, 80, 80)
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
            -- Bind at Last+1 so we run AFTER everything:
            --   * PlayerModule shiftlock (Camera priority, 200)
            --   * Any game script using BindToRenderStep at arbitrary priorities
            --   * Any game script using RenderStepped:Connect (fires at Last=2000)
            -- Last+1 (2001) makes our HRP.CFrame write the final word that frame.
            -- That's what fixes shiftlock / gun-aim systems still overriding us.
            RunService:BindToRenderStep("rbFaceStep", Enum.RenderPriority.Last.Value+1, function()
                if not RageSettings.FaceTarget then
                    RunService:UnbindFromRenderStep("rbFaceStep")
                    _rbFaceStepBound = false
                    -- restore the AutoRotate we forced off below
                    local c   = lplr.Character
                    local hum = c and c:FindFirstChildOfClass("Humanoid")
                    if hum and G._rbFaceSavedAutoRotate ~= nil then
                        pcall(function() hum.AutoRotate = G._rbFaceSavedAutoRotate end)
                    end
                    G._rbFaceSavedAutoRotate = nil
                    return
                end
                local char2=lplr.Character; if not char2 then return end
                local lhrp2=char2:FindFirstChild("HumanoidRootPart"); if not lhrp2 then return end
                -- Pin AutoRotate=false so the engine doesn't rotate the
                -- character toward MoveDirection / camera between our writes.
                -- Capture the user's original value once so we can restore.
                local hum = char2:FindFirstChildOfClass("Humanoid")
                if hum then
                    if G._rbFaceSavedAutoRotate == nil then
                        G._rbFaceSavedAutoRotate = hum.AutoRotate
                    end
                    if hum.AutoRotate then
                        pcall(function() hum.AutoRotate = false end)
                    end
                end
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
            -- restore AutoRotate when face-target toggles off via the outer
            -- guard (target lost, etc.), not via the inner self-unbind path
            local hum = lc:FindFirstChildOfClass("Humanoid")
            if hum and G._rbFaceSavedAutoRotate ~= nil then
                pcall(function() hum.AutoRotate = G._rbFaceSavedAutoRotate end)
            end
            G._rbFaceSavedAutoRotate = nil
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

-- silent force hooks (independent of aimbot).
-- Guard against re-stacking on script reload - ragebot's namecall+index
-- hooks compound the same freezing problem the aimbot ones did.
if hookmetamethod and not getgenv()._F_RB_NAMECALL_HOOKED then
    getgenv()._F_RB_NAMECALL_HOOKED = true
    local rbOldNamecall
    rbOldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
        -- cheap bool / userdata checks first; only do getnamecallmethod
        -- + string compares on the rare frames where ragebot is engaged
        if not RageSettings.SilentForce then return rbOldNamecall(...) end
        local part = rbCachedTarget; if not part then return rbOldNamecall(...) end
        if RageSettings.SilentMethod == "Mouse.Hit/Target" then return rbOldNamecall(...) end
        if checkcaller() then return rbOldNamecall(...) end
        local method = getnamecallmethod()
        if method ~= "Raycast" and method ~= "FindPartOnRay" and method ~= "findPartOnRay"
            and method ~= "FindPartOnRayWithIgnoreList" and method ~= "FindPartOnRayWithWhitelist" then
            return rbOldNamecall(...)
        end
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

-- ============================================================
--  ANTI-KICK  (best-effort client-side kick interception)
-- ============================================================
--  Hooks __namecall to intercept and SILENTLY DROP:
--    - Player:Kick(...)       on the LocalPlayer (client API)
--    - DataModel:Shutdown()   game:Shutdown() / GuiService:Shutdown()
--    - TeleportService:Teleport*(...)  on the LocalPlayer (soft-kick)
--  Note: server-initiated disconnects (Player:Kick called server-side)
--  still happen because they're a TCP-level disconnect packet -- there
--  is no client interception point for those. This blocks the common
--  pattern where the SERVER tells the CLIENT "self-disconnect", which
--  many HC-style games use for cheat detection. The toggle is gated
--  via getgenv()._F_ANTIKICK_ACTIVE so multi-script reloads stay safe.
-- ============================================================
getgenv()._F_ANTIKICK_ACTIVE = getgenv()._F_ANTIKICK_ACTIVE or false
if hookmetamethod and not getgenv()._F_ANTIKICK_NAMECALL_HOOKED then
    getgenv()._F_ANTIKICK_NAMECALL_HOOKED = true
    local akOldNamecall
    akOldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
        if not getgenv()._F_ANTIKICK_ACTIVE then return akOldNamecall(...) end
        local method = getnamecallmethod()
        -- fast-path early-out: only the methods we care about
        if method ~= "Kick"
            and method ~= "Shutdown"
            and method ~= "Teleport"
            and method ~= "TeleportToPlaceInstance"
            and method ~= "TeleportToPrivateServer"
            and method ~= "TeleportPartyAsync"
            and method ~= "TeleportAsync" then
            return akOldNamecall(...)
        end
        local args = {...}
        local self = args[1]
        if method == "Kick" then
            -- block Kick on our local player
            if rawequal(self, lplr) or rawequal(self, game.Players.LocalPlayer) then
                warn("[anti-kick] blocked Player:Kick(", args[2], ")")
                return
            end
        elseif method == "Shutdown" then
            -- block any Shutdown call from script
            warn("[anti-kick] blocked Shutdown()")
            return
        elseif method:sub(1, 8) == "Teleport" then
            -- block teleport calls that include the local player. Server-
            -- initiated TeleportService:Teleport(placeId, player) is the
            -- main soft-kick path; we look for our player in args.
            for i = 2, #args do
                if rawequal(args[i], lplr) then
                    warn("[anti-kick] blocked ", method, "(... local player ...)")
                    return
                end
                if type(args[i]) == "table" then
                    for _, v in pairs(args[i]) do
                        if rawequal(v, lplr) then
                            warn("[anti-kick] blocked ", method, "(... {local player} ...)")
                            return
                        end
                    end
                end
            end
        end
        return akOldNamecall(...)
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
-- [Player] = tick() last time we saw them in a knocked state.
-- Cleared on PlayerRemoving. Read by the KnockedGraceDelay guard.
local _rbLastKnockedAt = {}
local _rbLastAutoEquipAt = 0  -- throttle: don't try to equip every frame
plrs.PlayerRemoving:Connect(function(p) _rbLastKnockedAt[p] = nil end)
RunService.Heartbeat:Connect(function()
    if not RageSettings.AutoShoot then return end
    local now = tick()
    if (now - _rbEquipTime) < RageSettings.EquipDelay then return end
    if (now - _rbLastShot) < (RageSettings.AutoShootCooldown / 1000) then return end
    local plr = rbGetTarget(); if not plr then return end
    -- HC knocked status: stamp _rbLastKnockedAt every frame the target is
    -- knocked, and short-circuit if SkipKnocked is on.
    local _hcMod = F.games and F.games.hoodCustoms
    local _isKnockedNow = false
    if _hcMod and _hcMod.isKnocked then
        local okK, knocked = pcall(_hcMod.isKnocked, plr)
        _isKnockedNow = okK and knocked or false
    end
    if _isKnockedNow then
        _rbLastKnockedAt[plr] = now
        if RageSettings.SkipKnocked then return end
    end
    -- Post-knocked grace: even when the target now reads alive, if they
    -- were knocked within the last KnockedGraceDelay ms hold fire. This
    -- catches the respawn race where the old K.O body is still the
    -- selected target but the new character isn't replicated yet, so
    -- shooting wastes ammo.
    if RageSettings.KnockedGraceDelay > 0 then
        local lastK = _rbLastKnockedAt[plr]
        if lastK and (now - lastK) * 1000 < RageSettings.KnockedGraceDelay then return end
    end
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local lchar = lplr.Character
    local lhrp = lchar and lchar:FindFirstChild("HumanoidRootPart"); if not lhrp then return end
    local dist = (lhrp.Position - hrp.Position).Magnitude
    if dist > RageSettings.AutoShootDist then return end
    if RageSettings.AutoShootVis and not rbIsVisible(plr) then return end
    if RageSettings.FFCheck and char:FindFirstChildOfClass("ForceField") then return end
    -- Auto-equip on shoot range: if the chosen tool isn't currently held,
    -- pull it from the backpack via Humanoid:EquipTool. Throttled to 0.2s
    -- so a missing tool doesn't spam EquipTool every frame.
    --
    -- IMPORTANT: only `return` early when we actually need to wait for an
    -- equip. If the chosen tool is already held, fall through to the
    -- shoot logic below — otherwise auto-equip mode would silently
    -- block every shot.
    if RageSettings.AutoShootEquip and RageSettings.AutoShootEquipTool ~= "" then
        local heldTool = lchar:FindFirstChildOfClass("Tool")
        if not heldTool or heldTool.Name ~= RageSettings.AutoShootEquipTool then
            -- Wrong / no tool held: try to equip, then wait a frame
            -- (watchToolEquip will stamp _rbEquipTime so the EquipDelay
            -- gate above keeps this loop quiet until the gun is ready).
            if (now - _rbLastAutoEquipAt) > 0.2 then
                _rbLastAutoEquipAt = now
                local bp = lplr:FindFirstChild("Backpack")
                local tool = bp and bp:FindFirstChild(RageSettings.AutoShootEquipTool)
                local hum = lchar:FindFirstChildOfClass("Humanoid")
                if tool and hum then
                    pcall(function() hum:EquipTool(tool) end)
                end
            end
            return
        end
        -- Correct tool already held: do nothing, fall through to shoot.
    end
    if RageSettings.AutoShootRequireTool then
        local lc = lplr.Character
        if not lc or not lc:FindFirstChildOfClass("Tool") then return end
    end
    _rbLastShot = tick()
    -- HC Force Hit hook: when active, fire the synthetic Shoot remote
    -- (or click for shotguns) instead of just clicking. forceHit.fire()
    -- is gated by G.hcForceHitActive and reads ragebot's current target,
    -- so locking a target with the ragebot is what selects the victim.
    if G.hcForceHitActive
        and F and F.games and F.games.hoodCustoms
        and F.games.hoodCustoms.forceHit
        and F.games.hoodCustoms.forceHit.fire then
        F.games.hoodCustoms.forceHit.fire()
        return
    end
    VirtualInputManager:SendMouseButtonEvent(0,0,0,true,game,0)
    VirtualInputManager:SendMouseButtonEvent(0,0,0,false,game,0)
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
        return plr.Team==lplr.Team and EspSettings.TeamColor or EspSettings.EnemyColor
    end
    return EspSettings.NeutralColor
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
    hi.FillColor=EspSettings.ChamsFill; hi.OutlineColor=EspSettings.ChamsOutline
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
    local rootPos,_onScreen=Camera:WorldToViewportPoint(hrp.Position)
    -- Hide only when the player is BEHIND the camera (sp.Z <= 0).
    -- Previously we hid whenever sp.X/sp.Y fell outside the viewport,
    -- which made ESP flicker / disappear for players near screen edges
    -- or close to the camera (head/feet projected off-screen). The
    -- Drawing API clips off-viewport coords automatically, so it's
    -- safe to keep drawing with out-of-bounds X/Y.
    if rootPos.Z <= 0 then hideEsp(d); return end
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
    -- Compute size from KNOWN body parts only (not GetExtentsSize, which
    -- includes anything welded to the character - games like HC attach
    -- map parts / building pieces to player characters, which made the
    -- ESP box grow huge. Falls back to a sane default if no body parts
    -- are found yet.
    local _BODY_PARTS_FOR_BOX = {
        "Head","HumanoidRootPart","Torso","UpperTorso","LowerTorso",
        "LeftFoot","RightFoot","LeftHand","RightHand",
    }
    local minP, maxP
    for _, _bname in ipairs(_BODY_PARTS_FOR_BOX) do
        local _bp = char:FindFirstChild(_bname)
        if _bp and _bp:IsA("BasePart") then
            local _ppos, _psz = _bp.Position, _bp.Size
            local _lo = _ppos - _psz/2
            local _hi = _ppos + _psz/2
            if not minP then minP, maxP = _lo, _hi
            else
                minP = Vector3.new(math.min(minP.X,_lo.X), math.min(minP.Y,_lo.Y), math.min(minP.Z,_lo.Z))
                maxP = Vector3.new(math.max(maxP.X,_hi.X), math.max(maxP.Y,_hi.Y), math.max(maxP.Z,_hi.Z))
            end
        end
    end
    local size = (minP and maxP) and (maxP - minP) or Vector3.new(4, 5.5, 2)
    local cf=hrp.CFrame
    local topV,_topOn=Camera:WorldToViewportPoint((cf*CFrame.new(0,size.Y/2,0)).Position)
    local botV,_botOn=Camera:WorldToViewportPoint((cf*CFrame.new(0,-size.Y/2,0)).Position)
    -- Same fix as above: only hide when the body's top or bottom is
    -- BEHIND the camera (Z <= 0). Off-viewport X/Y is fine - let
    -- the box / lines extend past the screen edge.
    if topV.Z <= 0 or botV.Z <= 0 then hideEsp(d); return end
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
                local sA=Camera:WorldToViewportPoint(pA.Position); local sB=Camera:WorldToViewportPoint(pB.Position)
                -- Only hide when EITHER joint is behind the camera (Z<=0).
                -- Off-viewport X/Y is fine - Drawing clips automatically.
                if sA.Z>0 and sB.Z>0 then line.From=Vector2.new(sA.X,sA.Y); line.To=Vector2.new(sB.X,sB.Y); line.Color=col; line.Thickness=1; line.Transparency=1; line.Visible=true
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
            -- Re-apply colors each frame so the color picker updates live.
            hi.FillColor    = EspSettings.ChamsFill
            hi.OutlineColor = EspSettings.ChamsOutline
            hi.Parent=char; hi.Enabled=true
        else hi.Enabled=false end
    end
end

local function startEspRender()
    if espRenderConn or not Drawing then return end
    -- Throttle the ESP render to ~120 Hz max. Caps the cost
    -- (WorldToViewportPoint per part per player) on 144/240 Hz
    -- monitors while still being smooth enough that fast-moving
    -- targets don't visibly lag behind their boxes.
    local MIN_DT = 1 / 120
    local accum = 0
    espRenderConn = RunService.RenderStepped:Connect(function(dt)
        if not EspSettings.Enabled then
            for _,d in pairs(EspDrawings) do hideEsp(d) end
            for _,h in pairs(EspHighlights) do h.Enabled=false end
            return
        end
        accum = accum + dt
        if accum < MIN_DT then return end
        accum = 0
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

-- Version string baked at push time. Use F.getVersion() from the loader
-- to display it in the watermark / on-load notification so you can see
-- at a glance whether the GitHub raw URL served the latest commit.
F.SCRIPT_VERSION = SCRIPT_VERSION
F.getVersion = function() return SCRIPT_VERSION end

F.fly = makeToggle(startFly, stopFly, "flyActive")
F.fly.setSpeed   = function(n) FLY_SPEED = tonumber(n) or FLY_SPEED end
F.fly.getSpeed   = function() return FLY_SPEED end

-- anti-kick: wraps the getgenv flag that the namecall hook reads
F.antiKick = {
    start  = function() getgenv()._F_ANTIKICK_ACTIVE = true end,
    stop   = function() getgenv()._F_ANTIKICK_ACTIVE = false end,
    toggle = function()
        getgenv()._F_ANTIKICK_ACTIVE = not getgenv()._F_ANTIKICK_ACTIVE
    end,
    isActive = function() return getgenv()._F_ANTIKICK_ACTIVE == true end,
}


-- Real Humanoid.WalkSpeed override w/ anti-restore. Setting the value
-- while active applies it instantly; the loop re-asserts whenever the
-- game writes a different value.
F.walkspeed = {
    start  = startWalkspeed,
    stop   = stopWalkspeed,
    toggle = function() if G.walkspeedActive then stopWalkspeed() else startWalkspeed() end end,
    isActive = function() return G.walkspeedActive == true end,
    setValue = function(n)
        G.walkspeedValue = tonumber(n) or G.walkspeedValue
        -- Apply immediately so the slider feels responsive; the Heartbeat
        -- loop in startWalkspeed will keep re-asserting from now on.
        if G.walkspeedActive then
            local c = lplr.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            if hum then pcall(function() hum.WalkSpeed = G.walkspeedValue end) end
        end
    end,
    getValue = function() return G.walkspeedValue end,
}

-- Real Humanoid.JumpPower override w/ anti-restore. Pair with Force
-- Jump if the game ALSO disables the jump state.
F.jumpPower = {
    start  = startJumpPower,
    stop   = stopJumpPower,
    toggle = function() if G.jumpPowerActive then stopJumpPower() else startJumpPower() end end,
    isActive = function() return G.jumpPowerActive == true end,
    setValue = function(n)
        G.jumpPowerValue = tonumber(n) or G.jumpPowerValue
        if G.jumpPowerActive then
            local c = lplr.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function()
                    if hum.UseJumpPower then
                        hum.JumpPower = G.jumpPowerValue
                    else
                        hum.JumpHeight = G.jumpPowerValue / 7
                    end
                end)
            end
        end
    end,
    getValue = function() return G.jumpPowerValue end,
}

-- CFrame-based "speed hack" (camera-WASD-driven HRP nudge).
-- Doesn't touch Humanoid.WalkSpeed - use F.walkspeed for that.
F.cframeSpeed = {
    start  = function(mult) startCframeSpeed(mult) end,
    stop   = stopCframeSpeed,
    toggle = function(mult) if G.speedActive then stopCframeSpeed() else startCframeSpeed(mult) end end,
    isActive = function() return G.speedActive == true end,
    setMultiplier = function(n) G.speedValue = tonumber(n) or G.speedValue end,
    getMultiplier = function() return G.speedValue end,
}
-- legacy alias (old code referenced F.speed)
F.speed = F.cframeSpeed

F.bhop      = makeToggle(startBhop,      stopBhop,      "bhopActive")
F.bhop.config = BHOP_CFG
F.infJump   = makeToggle(startInfJump,   stopInfJump,   "infJumpActive")
F.forceJump = makeToggle(startForceJump, stopForceJump, "forceJumpActive")
F.antiAfk   = makeToggle(startAntiAfk,   stopAntiAfk,   "antiAfkActive")
F.clickTp   = makeToggle(startClickTp,   stopClickTp,   "clickTpActive")
F.autoRespawn = makeToggle(startAutoRe,  stopAutoRe,    "autoReActive")
F.noclip    = makeToggle(startNoclip,    stopNoclip,    "noclipActive")
F.fullbright= makeToggle(startFullbright,stopFullbright,"fullbrightActive")
F.freecam   = makeToggle(startFreecam,   stopFreecam,   "freecamActive")
F.zoom      = makeToggle(startZoom,      stopZoom,      "zoomActive")
F.spin      = makeToggle(startSpin,      stopSpin,      "spinActive")
F.spin.setSpeed = function(n)
    SPIN_SPEED = tonumber(n) or SPIN_SPEED
    -- live-update the running gyro so the slider takes effect immediately
    -- instead of requiring a toggle off/on
    if G._spinGyro and G._spinGyro.Parent then
        G._spinGyro.AngularVelocity = Vector3.new(0, SPIN_SPEED, 0)
    end
end
F.flip      = makeToggle(startFlip,      stopFlip,      "flipActive")
F.tilt      = makeToggle(startTilt,      stopTilt,      "tiltActive")
F.backwards = makeToggle(startBackwards, stopBackwards, "backwardsActive")
F.ice       = makeToggle(startIce,       stopIce,       "iceActive")
F.ice.setSlide = function(n) ICE_SLIDE = math.clamp(tonumber(n) or ICE_SLIDE, 0, 0.999) end

-- ============================================================
--  STICKY EMOTES  (entire module inlined here)
-- ============================================================
--  Two filters keep us catching ONLY emotes, not weapon/tool anims:
--    1. Tool-ancestor filter - if the source Animation Instance is
--       parented under a Tool (or HopperBin) anywhere up the chain,
--       it's a tool/weapon animation (knife slash, gun fire) and we
--       skip it.
--    2. Builtin filter - Roblox's Animate LocalScript tracks
--       (WalkAnim, RunAnim, IdleAnim, ToolNoneAnim, etc.) are
--       excluded by exact-name + parent-folder + low-priority.
--  Anything that passes both is treated as an emote (catalog OR
--  game-custom). No-stacking via G._stickyTracks - we only ever
--  touch tracks we ourselves captured or spawned.
--
--  Built as an IIFE that returns the {start,stop,toggle,isActive}
--  table directly into F.stickyEmote. None of the helpers leak to
--  the chunk's local register pool - that 200-local limit was hit
--  when these were declared at chunk top level.
-- ============================================================
F.stickyEmote = (function()
    local BUILTIN_ANIM_NAMES = {
        WalkAnim = true, RunAnim = true, JumpAnim = true, IdleAnim = true,
        FallAnim = true, ClimbAnim = true, SwimAnim = true, SwimIdleAnim = true,
        ToolNoneAnim = true, ToolSlashAnim = true, ToolLungeAnim = true,
        ["Idle Anim"] = true, ["Walk Anim"] = true, ["Run Anim"] = true,
        ["Jump Anim"] = true, ["Fall Anim"] = true, ["Climb Anim"] = true,
        PoseAnim = true, DeathAnim = true, SitAnim = true,
    }
    local BUILTIN_PARENT_NAMES = {
        walk = true, run = true, jump = true, idle = true, fall = true,
        climb = true, swim = true, swimidle = true, sit = true,
        toolnone = true, toolslash = true, toollunge = true,
    }
    local function getAnimator()
        local c = lplr.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        return hum and hum:FindFirstChildOfClass("Animator")
    end
    local function isToolAnim(track)
        local a = track.Animation
        if not a then return false end
        local p = a.Parent
        for _ = 1, 12 do
            if not p or p == game then return false end
            if p:IsA("Tool") or p:IsA("HopperBin") then return true end
            p = p.Parent
        end
        return false
    end
    local function isBuiltin(track)
        local a = track.Animation
        if not a then return true end
        if BUILTIN_ANIM_NAMES[a.Name or ""] then return true end
        local parent = a.Parent
        if parent then
            if BUILTIN_PARENT_NAMES[(parent.Name or ""):lower()] then return true end
            local grand = parent.Parent
            if grand and grand.Name == "Animate" then return true end
        end
        local prio = track.Priority
        if prio == Enum.AnimationPriority.Idle
           or prio == Enum.AnimationPriority.Movement
           or prio == Enum.AnimationPriority.Core then
            return true
        end
        return false
    end
    local function shouldStick(track)
        if isToolAnim(track) then return false end
        if isBuiltin(track) then return false end
        return true
    end
    local function stopOurs()
        G._stickyTracks = G._stickyTracks or {}
        for t, _ in pairs(G._stickyTracks) do
            pcall(function() t:Stop(0) end)
        end
        table.clear(G._stickyTracks)
    end
    local function stopFn()
        G.stickyEmoteActive   = false
        G._currentEmoteId     = nil
        G._emoteStopRequested = false
        if G._emoteAnimConn     then G._emoteAnimConn:Disconnect();     G._emoteAnimConn     = nil end
        if G._emoteCharConn     then G._emoteCharConn:Disconnect();     G._emoteCharConn     = nil end
        if G._emoteChatConn     then G._emoteChatConn:Disconnect();     G._emoteChatConn     = nil end
        if G._emoteTextChatConn then G._emoteTextChatConn:Disconnect(); G._emoteTextChatConn = nil end
        if G._emoteHbConn       then G._emoteHbConn:Disconnect();       G._emoteHbConn       = nil end
        stopOurs()
    end
    local function startFn()
        G.stickyEmoteActive   = true
        G._emoteStopRequested = false
        G._currentEmoteId     = nil
        G._stickyTracks       = G._stickyTracks or {}

        local function hookChar(char)
            if not char then return end
            local hum = char:WaitForChild("Humanoid", 5); if not hum then return end
            local animator = hum:WaitForChild("Animator", 5); if not animator then return end
            if G._emoteAnimConn then G._emoteAnimConn:Disconnect() end
            G._emoteAnimConn = animator.AnimationPlayed:Connect(function(track)
                if not G.stickyEmoteActive or G._emoteStopRequested then return end
                if not shouldStick(track) then return end
                local a = track.Animation
                if not a or a.AnimationId == "" then return end
                -- our own Heartbeat replay of the current emote - just track it
                if G._currentEmoteId == a.AnimationId then
                    G._stickyTracks[track] = true
                    pcall(function() track.Priority = Enum.AnimationPriority.Action4 end)
                    return
                end
                -- different emote - supersede old set so they don't stack
                stopOurs()
                G._stickyTracks[track] = true
                G._currentEmoteId = a.AnimationId
                pcall(function() track.Priority = Enum.AnimationPriority.Action4 end)
            end)
        end
        hookChar(lplr.Character)
        if G._emoteCharConn then G._emoteCharConn:Disconnect() end
        G._emoteCharConn = lplr.CharacterAdded:Connect(function(c)
            if G.stickyEmoteActive then
                G._currentEmoteId = nil
                table.clear(G._stickyTracks)
                hookChar(c)
            end
        end)

        -- Heartbeat keep-alive: re-create from AssetId when our tracks die
        if G._emoteHbConn then G._emoteHbConn:Disconnect() end
        G._emoteHbConn = RunService.Heartbeat:Connect(function()
            if not G.stickyEmoteActive or G._emoteStopRequested then return end
            local id = G._currentEmoteId
            if not id or id == "" then return end
            local animator = getAnimator()
            if not animator then return end
            for t, _ in pairs(G._stickyTracks) do
                if not t.IsPlaying and t.Parent ~= animator then
                    G._stickyTracks[t] = nil
                end
            end
            for t, _ in pairs(G._stickyTracks) do
                if t.IsPlaying and t.Animation and t.Animation.AnimationId == id then
                    if t.Priority ~= Enum.AnimationPriority.Action4 then
                        pcall(function() t.Priority = Enum.AnimationPriority.Action4 end)
                    end
                    return
                end
            end
            local anim = Instance.new("Animation")
            anim.AnimationId = id
            local newTrack
            pcall(function() newTrack = animator:LoadAnimation(anim) end)
            if newTrack then
                pcall(function() newTrack.Priority = Enum.AnimationPriority.Action4 end)
                pcall(function() newTrack:Play(0) end)
                G._stickyTracks[newTrack] = true
            end
        end)

        -- /e stop interception, both chat systems
        local function onChat(msg)
            if not G.stickyEmoteActive or type(msg) ~= "string" then return end
            local m = msg:lower():gsub("^%s+", "")
            if m:match("^/e%s+stop") or m:match("^/emote%s+stop") then
                G._emoteStopRequested = true
                G._currentEmoteId     = nil
                stopOurs()
                task.delay(0.5, function() G._emoteStopRequested = false end)
            end
        end
        if G._emoteChatConn then G._emoteChatConn:Disconnect() end
        G._emoteChatConn = lplr.Chatted:Connect(onChat)
        if G._emoteTextChatConn then G._emoteTextChatConn:Disconnect() end
        pcall(function()
            local TCS = game:GetService("TextChatService")
            if TCS and TCS.SendingMessage then
                G._emoteTextChatConn = TCS.SendingMessage:Connect(function(message)
                    if message and message.Text then onChat(message.Text) end
                end)
            end
        end)
    end
    return {
        start    = startFn,
        stop     = stopFn,
        toggle   = function() if G.stickyEmoteActive then stopFn() else startFn() end end,
        isActive = function() return G.stickyEmoteActive == true end,
    }
end)()

F.respawn = { fire = cmdRe }
F.blink   = {
    fire = cmdBlink,
    setDistance = function(n) BLINK_DIST = tonumber(n) or BLINK_DIST end,
    getDistance = function() return BLINK_DIST end,
}
F.fov = { set = setFov, get = function() return CUSTOM_FOV end }

-- ============================================================
--  TOOL GLOW
-- ============================================================
--  Highlights the currently equipped Tool with a configurable
--  fill + outline color so it pops visually. Watches both the
--  character (re-wires on respawn) and tool equip / unequip
--  so the highlight follows whatever you're holding.
-- ============================================================
F.toolGlow = (function()
    local active = false
    local fillColor    = Color3.fromRGB(255,  60,  60)
    local outlineColor = Color3.fromRGB(255, 255, 255)
    local fillTransp   = 0.35
    local outlineTransp= 0.0
    local hl
    local equipConn, unequipConn, charConn

    local function ensureHl()
        if hl and hl.Parent then return hl end
        hl = Instance.new("Highlight")
        hl.Name             = "_decay_tool_glow"
        hl.DepthMode        = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillColor        = fillColor
        hl.OutlineColor     = outlineColor
        hl.FillTransparency = fillTransp
        hl.OutlineTransparency = outlineTransp
        hl.Enabled          = true
        return hl
    end

    local function attachToCurrent()
        if not active then return end
        local c = lplr.Character; if not c then return end
        local tool = c:FindFirstChildOfClass("Tool")
        if tool then
            local h = ensureHl()
            h.FillColor = fillColor; h.OutlineColor = outlineColor
            h.FillTransparency = fillTransp; h.OutlineTransparency = outlineTransp
            h.Adornee = tool
            h.Parent  = tool
            h.Enabled = true
        else
            if hl then hl.Enabled = false end
        end
    end

    local function wireChar(c)
        if equipConn   then equipConn:Disconnect();   equipConn   = nil end
        if unequipConn then unequipConn:Disconnect(); unequipConn = nil end
        if not c then return end
        equipConn = c.ChildAdded:Connect(function(ch)
            if ch:IsA("Tool") then task.defer(attachToCurrent) end
        end)
        unequipConn = c.ChildRemoved:Connect(function(ch)
            if ch:IsA("Tool") then task.defer(attachToCurrent) end
        end)
        attachToCurrent()
    end

    local function start()
        if active then return end
        active = true
        if charConn then charConn:Disconnect() end
        charConn = lplr.CharacterAdded:Connect(function(c)
            if active then task.wait(0.3); wireChar(c) end
        end)
        wireChar(lplr.Character)
    end

    local function stop()
        active = false
        if hl then pcall(function() hl:Destroy() end); hl = nil end
        if equipConn   then equipConn:Disconnect();   equipConn   = nil end
        if unequipConn then unequipConn:Disconnect(); unequipConn = nil end
        if charConn    then charConn:Disconnect();    charConn    = nil end
    end

    return {
        start    = start,
        stop     = stop,
        toggle   = function() if active then stop() else start() end end,
        isActive = function() return active end,
        setFillColor          = function(c) if typeof(c) == "Color3" then fillColor    = c; if hl then hl.FillColor    = c end end end,
        setOutlineColor       = function(c) if typeof(c) == "Color3" then outlineColor = c; if hl then hl.OutlineColor = c end end end,
        setFillTransparency   = function(n) fillTransp    = math.clamp(tonumber(n) or 0.35, 0, 1); if hl then hl.FillTransparency    = fillTransp    end end,
        setOutlineTransparency= function(n) outlineTransp = math.clamp(tonumber(n) or 0,    0, 1); if hl then hl.OutlineTransparency = outlineTransp end end,
        getFillColor    = function() return fillColor    end,
        getOutlineColor = function() return outlineColor end,
    }
end)()

-- ============================================================
--  ROCKET JUMP
--  Toggle on -> pressing Space triggers an instant velocity blast
--  in (camera lookvector + up) * force. Toggle off -> Space does
--  the normal jump again. fire() can also be called directly for
--  the manual-fire button.
-- ============================================================
F.rocketJump = (function()
    local force  = 200   -- studs/sec impulse magnitude
    local upBias = 0.4   -- 0=pure forward, 1=pure up
    local jumpConn, charConn

    local function fire()
        local c = lplr.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        -- Use the CHARACTER's facing direction (HRP.LookVector), not the
        -- camera's. The camera may be looking down at the player from
        -- behind/above; we want to launch in the direction the body is
        -- actually facing. Project to horizontal so a downward camera
        -- doesn't yank you into the floor.
        local fwd = hrp.CFrame.LookVector
        fwd = Vector3.new(fwd.X, 0, fwd.Z)
        if fwd.Magnitude > 0.01 then fwd = fwd.Unit else fwd = Vector3.zero end
        local dir = fwd * (1 - upBias) + Vector3.new(0, 1, 0) * upBias
        if dir.Magnitude < 0.01 then dir = Vector3.new(0, 1, 0) end
        dir = dir.Unit
        pcall(function()
            hrp.AssemblyLinearVelocity = dir * force
        end)
    end

    -- Hook the Jumping state transition. We previously listened to
    -- PropertyChangedSignal("Jump"), but Jump=true fires on EVERY Space
    -- press -- including mid-air, during cooldown, while stunned, etc.
    -- -- even when no actual jump occurs, which caused the rocket to fire
    -- spuriously. StateChanged -> Jumping only fires when the humanoid
    -- genuinely leaves the ground due to a jump action, so this matches
    -- the user's expectation: "fire only when I actually jump."
    -- Re-hooks on respawn via charConn.
    local function hook(char)
        local hum = char and char:WaitForChild("Humanoid", 5)
        if not hum then return end
        if jumpConn then jumpConn:Disconnect() end
        jumpConn = hum.StateChanged:Connect(function(_old, new)
            if not G.rocketJumpActive then return end
            if new == Enum.HumanoidStateType.Jumping then
                fire()
            end
        end)
    end

    local function start()
        G.rocketJumpActive = true
        if charConn then charConn:Disconnect() end
        charConn = lplr.CharacterAdded:Connect(function(c)
            if G.rocketJumpActive then task.spawn(hook, c) end
        end)
        if lplr.Character then task.spawn(hook, lplr.Character) end
    end

    local function stop()
        G.rocketJumpActive = false
        if jumpConn then jumpConn:Disconnect(); jumpConn = nil end
        if charConn then charConn:Disconnect(); charConn = nil end
    end

    local t = makeToggle(start, stop, "rocketJumpActive")
    t.fire      = fire    -- manual button still works regardless of toggle
    t.setForce  = function(n) force  = math.clamp(tonumber(n) or 200, 10, 5000) end
    t.setUpBias = function(n) upBias = math.clamp(tonumber(n) or 0.4, 0, 1) end
    return t
end)()

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
    setOutlineColor = function(c) if typeof(c) == "Color3" then RageSettings.OutlineColor = c; if RB_outlineHL then RB_outlineHL.OutlineColor = c end end end,
    setLineColor    = function(c) if typeof(c) == "Color3" then RageSettings.LineColor    = c end end,
    setSkipKnocked  = function(b) RageSettings.SkipKnocked = b == true end,
    setIgnoreKnocked = function(b) RageSettings.IgnoreKnocked = b == true end,
    setFaceTarget  = function(b) RageSettings.FaceTarget = b == true end,
    setOrbit       = function(b) RageSettings.Orbit = b == true end,
    setOrbitDistance = function(n) RageSettings.OrbitDistance = math.clamp(tonumber(n) or 15, 2, 200) end,
    setOrbitSpeed    = function(n) RageSettings.OrbitSpeed    = math.clamp(tonumber(n) or 60, 1, 9999) end,
    setOrbitHeight   = function(n) RageSettings.OrbitHeight   = math.clamp(tonumber(n) or 5, -50, 50) end,
    setAutoShoot     = function(b) RageSettings.AutoShoot = b == true end,
    setAutoShootDist     = function(n) RageSettings.AutoShootDist = math.clamp(tonumber(n) or 50, 1, 500) end,
    setAutoShootCooldown = function(n) RageSettings.AutoShootCooldown = math.clamp(tonumber(n) or 100, 0, 10000) end,
    setAutoShootRequireTool = function(b) RageSettings.AutoShootRequireTool = b == true end,
    -- auto-equip-on-shoot
    setAutoShootEquip     = function(b) RageSettings.AutoShootEquip = b == true end,
    setAutoShootEquipTool = function(s) RageSettings.AutoShootEquipTool = tostring(s or "") end,
    getAutoShootEquipTool = function() return RageSettings.AutoShootEquipTool end,
    -- knocked grace
    setKnockedGraceDelay = function(n) RageSettings.KnockedGraceDelay = math.clamp(tonumber(n) or 0, 0, 20) end,
    getKnockedGraceDelay = function() return RageSettings.KnockedGraceDelay end,
    setAutoShootVis  = function(b) RageSettings.AutoShootVis = b == true end,
    setFFCheck       = function(b) RageSettings.FFCheck = b == true end,
    setEquipDelay    = function(n) RageSettings.EquipDelay = math.clamp(tonumber(n) or 0.5, 0, 5) end,
    setCamSnap       = function(b) RageSettings.CamSnap = b == true end,
    setCamSmoothing  = function(n) RageSettings.CamSmoothing = math.clamp(tonumber(n) or 0.15, 0.01, 0.99) end,
    setSpeedPanic    = function(b) RageSettings.SpeedPanic = b == true end,
    setSwitchByMouse = function(b) RageSettings.SwitchByMouse = b == true end,
    setPriority = function(s)
        local valid = { Closest=true, Mouse=true, Camera=true,
                        LowestHP=true, HighestThreat=true }
        if valid[s] then RageSettings.Priority = s end
    end,
    getPriority = function() return RageSettings.Priority end,
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
    -- Color setters. Render loop reads EspSettings.* each frame so
    -- the picker updates take effect immediately - no reset needed.
    setEnemyColor     = function(c) if typeof(c) == "Color3" then EspSettings.EnemyColor    = c end end,
    setTeamColor      = function(c) if typeof(c) == "Color3" then EspSettings.TeamColor     = c end end,
    setNeutralColor   = function(c) if typeof(c) == "Color3" then EspSettings.NeutralColor  = c end end,
    setChamsFill      = function(c) if typeof(c) == "Color3" then EspSettings.ChamsFill     = c end end,
    setChamsOutline   = function(c) if typeof(c) == "Color3" then EspSettings.ChamsOutline  = c end end,
    setTracerColor    = function(c) if typeof(c) == "Color3" then EspSettings.TracerColor   = c end end,
}

-- players
F.players = {
    list   = function() return plrs:GetPlayers() end,
    find   = findPlayerByName,
    goto   = gotoPlayer,
    view   = viewPlayer,
    fling  = flingPlayer,
    follow = followPlayer,
    followStop = followStop,
    isFollowing = function() return _follow.target end,
    setFollowVisualize = followSetVisualize,
    getFollowVisualize = function() return _follow.viz end,
}

-- ============================================================
--  AUTO-TARGETER
--  Persistent UserId->username list. When the toggle is on, any
--  player in the list who's in the current server (or who joins
--  later) is automatically added to the ragebot's target list.
--  UserId is the persistent key since usernames can change.
--  Stored in `cclosure_autotarget.json` via writefile/readfile.
-- ============================================================
F.autoTargeter = (function()
    local SAVE_FILE = "cclosure_autotarget.json"
    local HttpService = game:GetService("HttpService")

    local entries = {}  -- [userId(number)] = username(string)
    local enabled = false

    local function save()
        if not writefile then return end
        local serializable = {}
        for uid, name in pairs(entries) do
            serializable[tostring(uid)] = name
        end
        pcall(function() writefile(SAVE_FILE, HttpService:JSONEncode(serializable)) end)
    end

    local function load()
        if not (readfile and isfile) then return end
        if not isfile(SAVE_FILE) then return end
        local ok, content = pcall(readfile, SAVE_FILE)
        if not ok or not content then return end
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, content)
        if not ok2 or type(data) ~= "table" then return end
        entries = {}
        for k, v in pairs(data) do
            local uid = tonumber(k)
            if uid and type(v) == "string" then entries[uid] = v end
        end
    end

    local function listAll()
        local out = {}
        for uid, name in pairs(entries) do
            table.insert(out, { userId = uid, username = name })
        end
        table.sort(out, function(a, b) return a.username:lower() < b.username:lower() end)
        return out
    end

    local function isInList(userId)
        return entries[tonumber(userId)] ~= nil
    end

    local function addById(uid, username)
        uid = tonumber(uid); if not uid then return false end
        if not username then
            local ok, n = pcall(plrs.GetNameFromUserIdAsync, plrs, uid)
            username = ok and n or ("UserId " .. uid)
        end
        entries[uid] = username
        save()
        return true
    end

    local function addByName(name)
        if not name or name == "" then return false end
        -- if name matches a current player, use their UserId directly
        for _, p in ipairs(plrs:GetPlayers()) do
            if p.Name:lower() == name:lower() then
                return addById(p.UserId, p.Name)
            end
        end
        -- otherwise resolve via web API
        local ok, uid = pcall(plrs.GetUserIdFromNameAsync, plrs, name)
        if not ok or not uid then return false end
        return addById(uid, name)
    end

    -- accepts a Player, UserId (number/numeric string), or username
    local function add(x)
        if typeof(x) == "Instance" and x:IsA("Player") then
            return addById(x.UserId, x.Name)
        elseif tonumber(x) then
            return addById(tonumber(x))
        else
            return addByName(tostring(x))
        end
    end

    local function remove(userId)
        userId = tonumber(userId); if not userId then return false end
        entries[userId] = nil
        save()
        return true
    end

    local function clear()
        entries = {}
        save()
    end

    -- push every in-server, in-list player to the ragebot target list
    local function sweep()
        if not enabled then return end
        if not (F.ragebot and F.ragebot.addTarget) then return end
        for _, p in ipairs(plrs:GetPlayers()) do
            if p ~= lplr and entries[p.UserId] then
                pcall(F.ragebot.addTarget, p)
            end
        end
    end

    -- watch new joins
    plrs.PlayerAdded:Connect(function(p)
        if not enabled then return end
        if entries[p.UserId] and F.ragebot and F.ragebot.addTarget then
            pcall(F.ragebot.addTarget, p)
        end
    end)

    local function setEnabled(v)
        enabled = v == true
        G.autoTargeterActive = enabled
        if enabled then sweep() end
    end

    load()

    return {
        add        = add,
        remove     = remove,
        clear      = clear,
        list       = listAll,
        isInList   = isInList,
        setEnabled = setEnabled,
        isEnabled  = function() return enabled end,
        sweep      = sweep,
    }
end)()

-- utility helpers (exposed for advanced users)
F.utils = {
    isReallyVisible = isReallyVisible,
    setStrictVisibleCheck = function(v) _visStrict = v == true end,
    getStrictVisibleCheck = function() return _visStrict end,
    setVisibleOrigin = function(s)
        local valid = { Camera = true, Head = true, Tool = true }
        if valid[s] then _visOrigin = s end
    end,
    getVisibleOrigin = function() return _visOrigin end,
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
--  ANTI-FLING
--  Caps HRP linear+angular velocity each Heartbeat. Real fling
--  exploits push velocities to 1e6+ stud/sec; anything above the
--  cap gets clamped before physics applies it. Default cap is
--  generous (5000 stud/sec) so it doesn't fight fly/speed/blink.
--  Also resets velocity to zero when over the cap, since fling
--  exploits often spike a single frame and then stop.
-- ============================================================
F.antiFling = (function()
    local cap     = 5000      -- stud/sec, both linear and angular
    local hbConn
    local charConn

    local function clampHrp()
        local c = lplr.Character; if not c then return end
        local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        local v  = hrp.AssemblyLinearVelocity
        local av = hrp.AssemblyAngularVelocity
        if v and v.Magnitude > cap then
            pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
        end
        if av and av.Magnitude > cap then
            pcall(function() hrp.AssemblyAngularVelocity = Vector3.zero end)
        end
        -- some flings target other body parts (Torso, limbs); sweep
        -- those too. Limited to a few high-mass parts so we don't
        -- iterate the whole rig every frame.
        for _, name in ipairs({"UpperTorso","LowerTorso","Torso","Head"}) do
            local p = c:FindFirstChild(name)
            if p and p:IsA("BasePart") then
                local pv  = p.AssemblyLinearVelocity
                local pav = p.AssemblyAngularVelocity
                if pv and pv.Magnitude > cap then
                    pcall(function() p.AssemblyLinearVelocity = Vector3.zero end)
                end
                if pav and pav.Magnitude > cap then
                    pcall(function() p.AssemblyAngularVelocity = Vector3.zero end)
                end
            end
        end
    end

    local function start()
        G.antiFlingActive = true
        if hbConn then hbConn:Disconnect() end
        hbConn = RunService.Heartbeat:Connect(function()
            if not G.antiFlingActive then return end
            clampHrp()
        end)
        if charConn then charConn:Disconnect() end
        charConn = lplr.CharacterAdded:Connect(function() task.wait(0.2); clampHrp() end)
    end

    local function stop()
        G.antiFlingActive = false
        if hbConn   then hbConn:Disconnect();   hbConn   = nil end
        if charConn then charConn:Disconnect(); charConn = nil end
    end

    local t = makeToggle(start, stop, "antiFlingActive")
    t.setCap = function(n) cap = math.max(50, tonumber(n) or 5000) end
    t.getCap = function() return cap end
    return t
end)()

-- ============================================================
--  FORCE CHAT  (re-enable chat in games that hid it)
--  Some games disable Roblox's chat via StarterGui:SetCoreGuiEnabled
--  or by setting TextChatService config Enabled = false. We force
--  both back on and re-apply periodically so subsequent script
--  attempts to disable it don't stick.
-- ============================================================
F.forceChat = (function()
    local StarterGui = game:GetService("StarterGui")
    local TextChatService = game:GetService("TextChatService")

    local function applyOnce()
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
        end)
        if TextChatService then
            for _, c in ipairs(TextChatService:GetDescendants()) do
                if c:IsA("ChatWindowConfiguration")
                or c:IsA("ChatInputBarConfiguration")
                or c:IsA("BubbleChatConfiguration") then
                    pcall(function() c.Enabled = true end)
                end
            end
        end
    end

    local function start()
        G.forceChatActive = true
        -- spawn a polling loop that re-applies every 2s. simpler than
        -- hooking signals on multiple services + the SetCoreGuiEnabled
        -- side. exits when G.forceChatActive flips false.
        task.spawn(function()
            while G.forceChatActive do
                applyOnce()
                task.wait(2)
            end
        end)
    end

    local function stop()
        G.forceChatActive = false
    end

    return makeToggle(start, stop, "forceChatActive")
end)()

-- ============================================================
--  PROXIMITY PROMPTS  (3 independent modules)
--    F.prompts.instantActivation  HoldDuration = 0 on every prompt
--    F.prompts.unlimitedRange     MaxActivationDistance = huge,
--                                  RequiresLineOfSight = false
--    F.prompts.autoFire           on PromptShown -> fireproximityprompt
--                                  (requires executor support)
--  Each module independently scans existing prompts on start, hooks
--  workspace.DescendantAdded for future prompts, and disconnects
--  cleanly on stop.
-- ============================================================
F.prompts = (function()
    -- Each prompt: ONE PropertyChangedSignal per watched property + ONE
    -- PromptShown for autoFire, installed on first sight. Listeners
    -- self-gate on G flags, so toggling modules on/off never connects/
    -- disconnects per-prompt.
    --
    -- Anti-restore: when the game writes a property back to default, the
    -- listener re-applies our value.
    --
    -- Originals are stashed as instance attributes the first time we see
    -- a prompt - so when a module turns OFF we can restore the prompt's
    -- original HoldDuration / MaxActivationDistance / RequiresLineOfSight
    -- instead of leaving it stuck on our spoofed value.

    local installed = setmetatable({}, { __mode = "k" })
    local ATTR_HOLD = "_F_origHoldDuration"
    local ATTR_DIST = "_F_origMaxDist"
    local ATTR_LOS  = "_F_origRequiresLoS"

    local function installAll(prompt)
        if installed[prompt] then return end
        installed[prompt] = true

        -- stash originals once. Only write the attribute if it's missing,
        -- so re-installation across script reloads doesn't overwrite the
        -- attribute with our already-spoofed value.
        if prompt:GetAttribute(ATTR_HOLD) == nil then
            prompt:SetAttribute(ATTR_HOLD, prompt.HoldDuration)
        end
        if prompt:GetAttribute(ATTR_DIST) == nil then
            prompt:SetAttribute(ATTR_DIST, prompt.MaxActivationDistance)
        end
        if prompt:GetAttribute(ATTR_LOS) == nil then
            prompt:SetAttribute(ATTR_LOS, prompt.RequiresLineOfSight)
        end

        prompt:GetPropertyChangedSignal("HoldDuration"):Connect(function()
            if G.promptInstantActive and prompt.HoldDuration ~= 0 then
                pcall(function() prompt.HoldDuration = 0 end)
            end
        end)
        prompt:GetPropertyChangedSignal("MaxActivationDistance"):Connect(function()
            if G.promptRangeActive and prompt.MaxActivationDistance ~= math.huge then
                pcall(function() prompt.MaxActivationDistance = math.huge end)
            end
        end)
        prompt:GetPropertyChangedSignal("RequiresLineOfSight"):Connect(function()
            if G.promptWallsActive and prompt.RequiresLineOfSight then
                pcall(function() prompt.RequiresLineOfSight = false end)
            end
        end)
        prompt.PromptShown:Connect(function()
            if G.promptAutoFireActive and fireproximityprompt then
                pcall(function() fireproximityprompt(prompt) end)
            end
        end)

        -- apply currently-active states
        if G.promptInstantActive then pcall(function() prompt.HoldDuration = 0 end) end
        if G.promptRangeActive   then pcall(function() prompt.MaxActivationDistance = math.huge end) end
        if G.promptWallsActive   then pcall(function() prompt.RequiresLineOfSight   = false end) end
    end

    if not getgenv()._F_PROMPT_HOOKED then
        getgenv()._F_PROMPT_HOOKED = true
        workspace.DescendantAdded:Connect(function(d)
            if d:IsA("ProximityPrompt") then installAll(d) end
        end)
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") then installAll(d) end
        end
    end

    -- ---- generic apply / restore helpers ----
    local function sweep(applyFn)
        for prompt in pairs(installed) do
            if prompt.Parent then pcall(function() applyFn(prompt) end) end
        end
    end
    local function restoreFromAttr(attr, prop, fallback)
        for prompt in pairs(installed) do
            if prompt.Parent then
                local orig = prompt:GetAttribute(attr)
                if orig == nil then orig = fallback end
                pcall(function() prompt[prop] = orig end)
            end
        end
    end

    local instantActivation = makeToggle(
        function()
            G.promptInstantActive = true
            sweep(function(p) p.HoldDuration = 0 end)
        end,
        function()
            G.promptInstantActive = false
            restoreFromAttr(ATTR_HOLD, "HoldDuration", 1)
        end,
        "promptInstantActive"
    )
    local unlimitedRange = makeToggle(
        function()
            G.promptRangeActive = true
            sweep(function(p) p.MaxActivationDistance = math.huge end)
        end,
        function()
            G.promptRangeActive = false
            restoreFromAttr(ATTR_DIST, "MaxActivationDistance", 10)
        end,
        "promptRangeActive"
    )
    local throughWalls = makeToggle(
        function()
            G.promptWallsActive = true
            sweep(function(p) p.RequiresLineOfSight = false end)
        end,
        function()
            G.promptWallsActive = false
            restoreFromAttr(ATTR_LOS, "RequiresLineOfSight", true)
        end,
        "promptWallsActive"
    )
    local autoFire = makeToggle(
        function() G.promptAutoFireActive = true end,
        function() G.promptAutoFireActive = false end,
        "promptAutoFireActive"
    )

    return {
        instantActivation = instantActivation,
        unlimitedRange    = unlimitedRange,
        throughWalls      = throughWalls,
        autoFire          = autoFire,
    }
end)()

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
        local vim = VirtualInputManager
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
            -- (whichever the game uses) - 10s safety cap.
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
F.autoEquip = (function()
    local name
    local charConn

    local function listTools()
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

    local function equip(n)
        if not n or n == "" then return false end
        local char = lplr.Character; if not char then return false end
        local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return false end
        local tool = (lplr:FindFirstChild("Backpack") and lplr.Backpack:FindFirstChild(n))
                  or char:FindFirstChild(n)
        if not tool or not tool:IsA("Tool") then return false end
        pcall(function() hum:EquipTool(tool) end)
        return true
    end

    local function start()
        G.autoEquipActive = true
        if charConn then charConn:Disconnect() end
        charConn = lplr.CharacterAdded:Connect(function()
            if not G.autoEquipActive then return end
            if not name or name == "" then return end
            local bp = lplr:WaitForChild("Backpack", 10); if not bp then return end
            bp:WaitForChild(name, 10)
            if not G.autoEquipActive then return end
            equip(name)
        end)
    end

    local function stop()
        G.autoEquipActive = false
        if charConn then charConn:Disconnect(); charConn = nil end
    end

    local t = makeToggle(start, stop, "autoEquipActive")
    t.list    = listTools
    t.equip   = function(n) name = n; return equip(n) end
    t.setName = function(n) name = n end
    t.getName = function() return name end
    return t
end)()

-- ============================================================
--  AUTO WEAPON SWITCH
--  Switches the equipped tool based on distance to the current
--  ragebot target. Three configurable slots:
--    close  : equipped when dist < closeMax
--    medium : equipped when closeMax <= dist < mediumMax
--    long   : equipped when dist >= mediumMax
--  Empty / "(none)" slots are skipped (so leaving 'medium' empty
--  means close-range tool stays equipped until past mediumMax).
--  Cooldown between switches stops oscillation at boundaries.
-- ============================================================
F.autoWeaponSwitch = (function()
    local active = false
    local closeName, mediumName, longName = "", "", ""
    local closeMax, mediumMax = 30, 100
    local switchCooldown = 0.5  -- seconds; cap switches at 2/sec
    local lastSwitch = 0
    local conn

    local function currentEquippedName()
        local c = lplr.Character
        local t = c and c:FindFirstChildOfClass("Tool")
        return t and t.Name or nil
    end

    local function chooseFor(dist)
        if dist < closeMax  and closeName  ~= "" and closeName  ~= "(none)" then return closeName  end
        if dist < mediumMax and mediumName ~= "" and mediumName ~= "(none)" then return mediumName end
        if longName ~= "" and longName ~= "(none)" then return longName end
        -- nothing configured for this bucket - try walk-up to populated slots
        if mediumName ~= "" and mediumName ~= "(none)" then return mediumName end
        if closeName  ~= "" and closeName  ~= "(none)" then return closeName  end
        return nil
    end

    local function tick()
        if not active then return end
        if (os.clock() - lastSwitch) < switchCooldown then return end
        local plr = (rbGetTarget and rbGetTarget()) or nil
        if not plr or not plr.Character then return end
        local thrp = plr.Character:FindFirstChild("HumanoidRootPart")
        if not thrp then return end
        local c = lplr.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local d = (thrp.Position - hrp.Position).Magnitude
        local want = chooseFor(d)
        if not want then return end
        if currentEquippedName() == want then return end
        if F.autoEquip and F.autoEquip.equip(want) then
            lastSwitch = os.clock()
        end
    end

    -- throttle: tick @ ~5x/sec (heartbeat is 60hz, so every 12 frames)
    local function start()
        active = true
        if conn then conn:Disconnect() end
        local frame = 0
        conn = RunService.Heartbeat:Connect(function()
            frame = frame + 1
            if frame < 12 then return end
            frame = 0
            tick()
        end)
    end
    local function stop()
        active = false
        if conn then conn:Disconnect(); conn = nil end
    end

    return {
        start    = start,
        stop     = stop,
        toggle   = function() if active then stop() else start() end end,
        isActive = function() return active end,
        setClose      = function(n) closeName  = n or "" end,
        setMedium     = function(n) mediumName = n or "" end,
        setLong       = function(n) longName   = n or "" end,
        setCloseMax   = function(n) closeMax   = tonumber(n) or closeMax end,
        setMediumMax  = function(n) mediumMax  = tonumber(n) or mediumMax end,
        setCooldown   = function(n) switchCooldown = math.max(0, tonumber(n) or 0.5) end,
        getClose      = function() return closeName  end,
        getMedium     = function() return mediumName end,
        getLong       = function() return longName   end,
        getCloseMax   = function() return closeMax   end,
        getMediumMax  = function() return mediumMax  end,
    }
end)()

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
-- cached MainEvent getter (closure-local cache lives in IIFE, no extra top-level locals)
local getMainEvent = (function()
    local cache
    return function()
        if cache and cache.Parent then return cache end
        cache = ReplicatedStorage:FindFirstChild("MainEvent")
        return cache
    end
end)()

-- HC: detect "grabbed" state. When player A picks up player B, the K.O
-- value on B's BodyEffects flips OFF (so the regular K.O check thinks B
-- is alive). Meanwhile, on A's BodyEffects, a "Grabbed" value is set to
-- B's name / B's player ref. We scan every character's BodyEffects.Grabbed
-- and treat plr as "being grabbed" if any other character points to them.
-- Handles both StringValue (name) and ObjectValue (Player / Character)
-- forms since we don't know which HC uses without inspecting in-game.
local function _hcIsGrabbed(plr)
    if not plr then return false end
    local wsPlayers = workspace:FindFirstChild("Players")
    local chars = wsPlayers and wsPlayers:FindFirstChild("Characters")
    if not chars then return false end
    local target = plr.Name
    for _, mdl in ipairs(chars:GetChildren()) do
        if mdl.Name ~= target then  -- skip own folder
            local fx = mdl:FindFirstChild("BodyEffects")
            if fx then
                local g = fx:FindFirstChild("Grabbed")
                if g then
                    local v = g.Value
                    if v == target then return true end
                    if typeof(v) == "Instance" then
                        if v == plr then return true end
                        if v.Name == target then return true end
                    end
                end
            end
        end
    end
    return false
end

-- HC-specific knocked check via workspace.Players.Characters.<name>.BodyEffects["K.O"].Value
-- Treats "being grabbed by someone" as still knocked, since the K.O bool
-- gets flipped off the instant a grabber starts carrying them. Without
-- this every grabbed target would slip through SkipKnocked / IgnoreKnocked
-- and we'd dump shots into people who are effectively still down.
local function _hcIsKnocked(plr)
    if not plr then return false end
    local wsPlayers = workspace:FindFirstChild("Players")
    local chars = wsPlayers and wsPlayers:FindFirstChild("Characters")
    if not chars then return false end
    local mdl = chars:FindFirstChild(plr.Name)
    if mdl then
        local fx = mdl:FindFirstChild("BodyEffects")
        if fx then
            local ko = fx:FindFirstChild("K.O")
            if ko ~= nil and ko.Value == true then return true end
        end
    end
    -- Grabbed counts as knocked (K.O flips off when picked up)
    return _hcIsGrabbed(plr)
end

F.games = F.games or {}
F.games.hoodCustoms = F.games.hoodCustoms or {}
F.games.hoodCustoms.isKnocked = _hcIsKnocked
F.games.hoodCustoms.isGrabbed = _hcIsGrabbed

F.games.hoodCustoms.autoStomp = (function()
    local conn
    local last = 0
    local radius, vertUp, vertDown = 5, 7, 1
    local interval = 0
    local rageTargets = false

    local function someoneBelow()
        local lc = lplr.Character
        local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
        if not lhrp then return false end
        for _, p in ipairs(_cachedPlayers or plrs:GetPlayers()) do
            if p == lplr then continue end
            local char = p.Character; if not char then continue end
            local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then continue end
            local d = lhrp.Position - hrp.Position
            local horizD = Vector2.new(d.X, d.Z).Magnitude
            if horizD <= radius and d.Y <= vertUp and d.Y >= -vertDown then return true end
        end
        return false
    end

    local function start()
        G.hcAutoStompActive = true
        if conn then conn:Disconnect() end
        conn = RunService.Heartbeat:Connect(function()
            if not G.hcAutoStompActive then return end
            if interval > 0 and tick() - last < interval then return end
            local me = getMainEvent()
            if not me then return end
            if rageTargets then
                local list = F.ragebot.getTargetList and F.ragebot.getTargetList() or {}
                for _, plr in ipairs(list) do
                    if _hcIsKnocked(plr) then
                        local char = plr.Character
                        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local lc   = lplr.Character
                            local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
                            if lhrp then _uprightTp(lc, lhrp, hrp.Position + Vector3.new(0, 3, 0), nil) end
                            last = tick()
                            pcall(function() me:FireServer("Stomp") end)
                            return
                        end
                    end
                end
            end
            if not someoneBelow() then return end
            last = tick()
            pcall(function() me:FireServer("Stomp") end)
        end)
    end

    local function stop()
        G.hcAutoStompActive = false
        if conn then conn:Disconnect(); conn = nil end
    end

    local t = makeToggle(start, stop, "hcAutoStompActive")
    t.setRadius      = function(n) radius   = math.clamp(tonumber(n) or 5, 1, 30) end
    t.getRadius      = function() return radius end
    t.setInterval    = function(n) interval = math.clamp(tonumber(n) or 0, 0, 5) end
    t.getInterval    = function() return interval end
    t.setRageTargets = function(b) rageTargets = b == true end
    t.getRageTargets = function() return rageTargets end
    return t
end)()

-- ============================================================
--  GAMES: HOOD CUSTOMS - AUTO RELOAD
--  Reads exactly:  lplr.Character.<Tool>.Script.Ammo
--  When that IntValue is <= threshold, sends the configured reload key.
-- ============================================================
F.games.hoodCustoms.autoReload = (function()
    local key = Enum.KeyCode.R
    local threshold = 0
    local cooldown = 1.5
    local last = 0
    local conn

    local function getAmmo()
        local char = lplr.Character;                                      if not char then return nil end
        local tool = char:FindFirstChildOfClass("Tool");                  if not tool then return nil end
        local script = tool:FindFirstChild("Script");                     if not script then return nil end
        local ammo = script:FindFirstChild("Ammo")
        if ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue")) then return ammo end
        return nil
    end

    local function fireKey()
        pcall(function()
            VirtualInputManager:SendKeyEvent(true,  key, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, key, false, game)
        end)
    end

    local function start()
        G.hcAutoReloadActive = true
        if conn then conn:Disconnect() end
        conn = RunService.Heartbeat:Connect(function()
            if not G.hcAutoReloadActive then return end
            if tick() - last < cooldown then return end
            local ammo = getAmmo();              if not ammo then return end
            if ammo.Value > threshold then return end
            last = tick()
            fireKey()
        end)
    end

    local function stop()
        G.hcAutoReloadActive = false
        if conn then conn:Disconnect(); conn = nil end
    end

    local t = makeToggle(start, stop, "hcAutoReloadActive")
    t.setKey = function(k)
        if typeof(k) == "EnumItem" then key = k
        elseif type(k) == "string" then key = Enum.KeyCode[k] or key end
    end
    t.setThreshold = function(n) threshold = tonumber(n) or 0 end
    t.getThreshold = function() return threshold end
    t.setCooldown  = function(n) cooldown = math.clamp(tonumber(n) or 1.5, 0.1, 10) end
    t.getCooldown  = function() return cooldown end
    return t
end)()

-- (HC Ammo.CLIENT auto-sync removed in v1.4.7 - it caused reload
-- slowdown because the game's reload state machine watches CLIENT,
-- and mirroring fresh Value writes into CLIENT interrupted the
-- reload animation. Old listeners from prior script runs will GC
-- once the character respawns and their Ammo instances destruct.)

-- ============================================================
--  GAMES: HOOD CUSTOMS - KNIFE REACH
--  Resizes lplr.Character.Knife.Handle.HITBOX_PART up to MAX (13,13,13).
--  Anything above that triggers HC's anti-cheat. Survives respawn via a
--  Heartbeat loop that re-applies whenever the knife reappears.
-- ============================================================
F.games.hoodCustoms.knifeReach = (function()
    local DEFAULT = Vector3.new(2.5, 1, 1)
    local MAX     = 13
    local size, visualize = 13, false
    local conn

    local function getHb()
        local function find(p)
            local k = p and p:FindFirstChild("[Knife]")
            if not k then return nil end
            local h = k:FindFirstChild("Handle"); if not h then return nil end
            return h:FindFirstChild("HITBOX_PART")
        end
        return find(lplr:FindFirstChildOfClass("Backpack")) or find(lplr.Character)
    end

    local function start()
        G.hcKnifeReachActive = true
        if conn then conn:Disconnect() end
        conn = RunService.Heartbeat:Connect(function()
            if not G.hcKnifeReachActive then return end
            local hb = getHb(); if not hb then return end
            local target = Vector3.new(size, size, size)
            if hb.Size ~= target then pcall(function() hb.Size = target end) end
            if hb.Transparency ~= 0.9999 then pcall(function() hb.Transparency = 0.9999 end) end
            local hl = hb:FindFirstChild("_kr_hl")
            if visualize then
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

    local function stop()
        G.hcKnifeReachActive = false
        if conn then conn:Disconnect(); conn = nil end
        local hb = getHb()
        if hb then
            pcall(function() hb.Size = DEFAULT end)
            pcall(function() hb.Transparency = 1 end)
            local hl = hb:FindFirstChild("_kr_hl")
            if hl then hl:Destroy() end
        end
    end

    local t = makeToggle(start, stop, "hcKnifeReachActive")
    t.setSize       = function(n) size = math.clamp(tonumber(n) or MAX, 1, MAX) end
    t.getSize       = function() return size end
    t.maxSize       = MAX
    t.setVisualize  = function(b) visualize = b == true end
    t.getVisualize  = function() return visualize end
    return t
end)()

-- ============================================================
--  GAMES: HOOD CUSTOMS - ANTI-AFK TAG
--  Watches HumanoidRootPart.CharacterAFK (BillboardGui).Enabled.
--  When it goes true the game has flagged you as AFK; we fire
--  MainEvent:FireServer("RequestAFKDisplay", false) to clear it.
--  Survives respawn (re-hooks via CharacterAdded).
-- ============================================================
F.games.hoodCustoms.antiAfkTag = (function()
    local propConn, charConn

    local function clearOnce()
        local me = getMainEvent()
        if me then pcall(function() me:FireServer("RequestAFKDisplay", false) end) end
    end

    local function hook(char)
        if not char then return end
        local hrp = char:WaitForChild("HumanoidRootPart", 5); if not hrp then return end
        local gui = hrp:WaitForChild("CharacterAFK", 5); if not gui then return end
        if propConn then propConn:Disconnect() end
        if gui.Enabled then
            pcall(function() gui.Enabled = false end)
            clearOnce()
        end
        propConn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not G.hcAntiAfkTagActive then return end
            if gui.Enabled then
                pcall(function() gui.Enabled = false end)
                clearOnce()
            end
        end)
    end

    local function start()
        -- mutually exclusive with force-AFK tag
        if G.hcForceAfkTagActive and F.games.hoodCustoms.forceAfkTag then
            pcall(function() F.games.hoodCustoms.forceAfkTag.stop() end)
        end
        G.hcAntiAfkTagActive = true
        if charConn then charConn:Disconnect() end
        charConn = lplr.CharacterAdded:Connect(function(c)
            if G.hcAntiAfkTagActive then task.spawn(hook, c) end
        end)
        if lplr.Character then task.spawn(hook, lplr.Character) end
    end

    local function stop()
        G.hcAntiAfkTagActive = false
        if propConn then propConn:Disconnect(); propConn = nil end
        if charConn then charConn:Disconnect(); charConn = nil end
    end

    -- always-on by default - but only auto-start in Hood Customs.
    -- Outside HC, hook() does WaitForChild("CharacterAFK", 5) which times
    -- out (5s noise) on every character spawn for no reason.
    local _HC_PLACE_IDS = { [138995385694035] = true, [9825515356] = true }
    if _HC_PLACE_IDS[game.PlaceId] then task.spawn(start) end
    return makeToggle(start, stop, "hcAntiAfkTagActive")
end)()

-- ============================================================
--  GAMES: HOOD CUSTOMS - FORCE AFK TAG
--  Reverse of antiAfkTag: keeps HumanoidRootPart.CharacterAFK
--  (BillboardGui).Enabled = true, and fires
--  MainEvent:FireServer("RequestAFKDisplay", true) so the server
--  also flags you as AFK to other players. Re-asserts whenever
--  anything sets Enabled back to false. Survives respawn.
--  Mutually exclusive with antiAfkTag - turning this on disables
--  the anti tag, and vice versa (the loader handles that wiring).
-- ============================================================
F.games.hoodCustoms.forceAfkTag = (function()
    local propConn, charConn

    local function setOnce()
        local me = getMainEvent()
        if me then pcall(function() me:FireServer("RequestAFKDisplay", true) end) end
    end

    local function hook(char)
        if not char then return end
        local hrp = char:WaitForChild("HumanoidRootPart", 5); if not hrp then return end
        local gui = hrp:WaitForChild("CharacterAFK", 5); if not gui then return end
        if propConn then propConn:Disconnect() end
        if not gui.Enabled then
            pcall(function() gui.Enabled = true end)
            setOnce()
        end
        propConn = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not G.hcForceAfkTagActive then return end
            if not gui.Enabled then
                pcall(function() gui.Enabled = true end)
                setOnce()
            end
        end)
    end

    local function start()
        -- mutually exclusive with anti-AFK tag
        if G.hcAntiAfkTagActive and F.games.hoodCustoms.antiAfkTag then
            pcall(function() F.games.hoodCustoms.antiAfkTag.stop() end)
        end
        G.hcForceAfkTagActive = true
        if charConn then charConn:Disconnect() end
        charConn = lplr.CharacterAdded:Connect(function(c)
            if G.hcForceAfkTagActive then task.spawn(hook, c) end
        end)
        if lplr.Character then task.spawn(hook, lplr.Character) end
    end

    local function stop()
        G.hcForceAfkTagActive = false
        if propConn then propConn:Disconnect(); propConn = nil end
        if charConn then charConn:Disconnect(); charConn = nil end
        -- restore the badge to whatever the server thinks (don't force off
        -- here - antiAfkTag is the explicit "always off" toggle)
    end

    return makeToggle(start, stop, "hcForceAfkTagActive")
end)()

-- HC godmode: built inside an IIFE so all its locals live in the inner
-- function's own register pool - none of them count against the file-
-- top-level chunk's 200-register Luau budget (we're at the limit).
F.games.hoodCustoms.godmode = (function()
    -- ============================================================
    -- HC godmode = FROZEN EMOTE EXPLOIT.
    --
    -- The limb-detach approach turned out to be unreliable on HC's
    -- current build. This is a much simpler exploit that actually
    -- works: load a specific emote animation, play it, then every
    -- Heartbeat re-set its TimePosition to a specific frame
    -- (freezetime) and AdjustSpeed(0). This locks the character in
    -- the very first pose of the emote, which puts HC's hit-detection
    -- in a state where damage doesn't apply.
    --
    -- Two helpers that keep it solid:
    --   * AnimationPlayed listener: HC plays its own animations on
    --     equip / move / shoot etc. The moment another animation
    --     starts, our frozen track gets blended out and we lose
    --     godmode. So we listen for AnimationPlayed and re-fire the
    --     setup ~20-50ms later (small random jitter so we don't trip
    --     "scripted on every frame" detection).
    --   * CharacterAdded: respawn rebuilds the Humanoid - wait 0.25s
    --     for HC to fully assemble the new rig, then re-fire setup.
    --
    -- Toggle off: stop+destroy the animation track, disconnect both
    -- helpers. Nothing to restore - we never touched joints, welds,
    -- constraints, or anchors. Cleanup is essentially free.
    -- ============================================================
    local EMOTE_ID   = "rbxassetid://70883871260184"
    local FREEZE_T   = 0.1265

    local track, hbConn, animConn, charConn
    local lastArmAt = 0       -- re-arm throttle (HC fires AnimationPlayed many times/sec)
    local lastListenAt = 0    -- listener throttle (don't even schedule redundant task.delays)

    local function getHumanoid()
        local c = lplr.Character
        if not c then return nil end
        return c:FindFirstChildOfClass("Humanoid")
    end

    local function killTrack()
        if hbConn   then hbConn:Disconnect();   hbConn   = nil end
        if animConn then animConn:Disconnect(); animConn = nil end
        if track then
            pcall(function() track:Stop() end)
            pcall(function() track:Destroy() end)
            track = nil
        end
    end

    -- declared forward so animConn can re-call after a delay.
    local arm
    arm = function()
        if not G.hcGmActive then return end
        -- Re-arm throttle. HC fires AnimationPlayed many times per
        -- second (walk, idle, sway, equip ...) and each fire would
        -- otherwise rebuild the track + both connections + the
        -- limb-void setup. Cap to once per 150ms - plenty fast to
        -- re-grab godmode after HC interrupts the emote, cheap
        -- enough that the game doesn't melt.
        local now = tick()
        if now - lastArmAt < 0.15 then return end
        lastArmAt = now

        local hum = getHumanoid()
        if not hum then return end

        killTrack()

        local anim = Instance.new("Animation")
        anim.AnimationId = EMOTE_ID
        local ok, newTrack = pcall(function() return hum:LoadAnimation(anim) end)
        if not ok or not newTrack then return end
        track = newTrack
        pcall(function() track:Play(0, 1, 1) end)

        -- Every Heartbeat: hold the animation at the godmode frame.
        -- AdjustSpeed(0) freezes the play head; setting TimePosition
        -- back to FREEZE_T defends against any external nudge.
        --
        -- Cheap-path: once the track is paused at FREEZE_T, the
        -- per-frame cost is just one TimePosition read + a compare.
        -- We only write when the position has actually drifted -
        -- writing TimePosition forces a full rig re-pose, which is
        -- what was tanking FPS when stacked on the rest of the
        -- executor's load. Same logic for Speed.
        hbConn = RunService.Heartbeat:Connect(function()
            if not G.hcGmActive then killTrack(); return end
            if not track then return end
            local ok, tp = pcall(function() return track.TimePosition end)
            if ok and math.abs(tp - FREEZE_T) > 0.001 then
                pcall(function() track.TimePosition = FREEZE_T end)
            end
            local ok2, sp = pcall(function() return track.Speed end)
            if ok2 and sp ~= 0 then
                pcall(function() track:AdjustSpeed(0) end)
            end
        end)

        -- HC plays its own animations (equip, move, shoot, etc.).
        -- Whenever a NEW animation starts, our track loses priority
        -- and the godmode breaks - so re-arm shortly after.
        --
        -- Throttle the LISTENER itself, not just arm(): without this
        -- we still queue a task.delay() for every fire (30+/sec from
        -- HC), and each scheduled task allocates a closure even if
        -- the eventual arm() call hits the throttle and returns.
        animConn = hum.AnimationPlayed:Connect(function(newAnim)
            if not G.hcGmActive then return end
            if not track or newAnim == track then return end
            local now = tick()
            if now - lastListenAt < 0.1 then return end
            lastListenAt = now
            task.delay(0.02 + math.random() * 0.03, arm)
        end)
    end

    return makeToggle(
        function()
            G.hcGmActive = true
            lastArmAt = 0  -- bypass throttle on first arm
            arm()
            if charConn then charConn:Disconnect() end
            charConn = lplr.CharacterAdded:Connect(function()
                if not G.hcGmActive then return end
                killTrack()
                task.wait(0.25)  -- let HC finish assembling the new rig
                if G.hcGmActive then
                    lastArmAt = 0
                    arm()
                end
            end)
        end,
        function()
            G.hcGmActive = false
            killTrack()
            if charConn then charConn:Disconnect(); charConn = nil end
        end,
        "hcGmActive"
    )
end)()


-- ============================================================
--  GAMES: HOOD CUSTOMS - FORCE HIT  (single-fire, shotgun WIP)
--  On hotkey press, force a hit on the chosen target:
--
--   * SINGLE-FIRE weapons -> direct FireServer("Shoot", payload)
--     with synthetic single-pellet payload (Head as origin,
--     camera-aligned aim, hit on chosen body part). Optional
--     TP-wallbang teleports into LoS, fires, teleports back.
--
--   * SHOTGUNS ([Shotgun] / [Double Barrel] / [Tactical Shotgun]) -
--     synthesizing a payload trips HC's per-shot PRNG check
--     ("attempt on spoofing spread pattern"). Falls back to
--     VirtualInputManager click so the gun fires natively. Pellets
--     land on target via natural cone when silent aim is on. No
--     TP wallbang on this path - silent aim collapsing the cone
--     to 0 spread also trips the pattern check.
--
--  Optional ammo refill writes Tool.Script.Ammo.Value to its
--  observed max each Heartbeat (cclosure-style), keeps the gun
--  visually full and ready to click-fire.
-- ============================================================

F.games.hoodCustoms.forceHit = (function()
    local SHOTGUN_NAMES = {
        ["[Shotgun]"]          = true,
        ["[Double Barrel]"]    = true,
        ["[DoubleBarrel]"]     = true,  -- HC's exact tool name (no space)
        ["[Tactical Shotgun]"] = true,
    }
    local SHOTGUN_PELLETS = {
        ["[Shotgun]"]          = 5,
        ["[Double Barrel]"]    = 5,
        ["[DoubleBarrel]"]     = 5,
        ["[Tactical Shotgun]"] = 5,
    }
    -- Fallback substrings: catches any HC tool whose actual Name differs
    -- from our hardcoded keys (case / spacing / bracket variations).
    -- Without this fuzzy match, isShotgun() returns false and forceHit
    -- routes the shot through fireDirect() which only sends 1 pellet -
    -- the server flags "shotgun fired with 1 pellet" and kicks.
    local SHOTGUN_SUBSTRINGS = { "shotgun", "barrel" }
    local _loggedTools = {}  -- tools we've already logged Tool.Name for

    local target          = nil
    local hitPartName     = "Head"
    local cooldown        = 0.20
    -- shotgun spread strategy
    --   "click"   -> click the mouse, gun fires natively (works, low risk)
    --   "synth"   -> synthesize a 2-section payload (WIP - tries to bypass
    --                the per-shot PRNG check). 2 stacked clusters ~3 studs
    --                apart, sub-stud anti-zero-spread jitter inside each.
    -- shotgunMode used to be "click" vs "synth"; click let the gun's own
    -- script fire via VirtualInputManager. Removed entirely per user
    -- request - fireShoot (the synth path) is the only path now since
    -- the canonical HC Shoot payload it sends doesn't kick.

    -- visual / audio feedback (FireServer doesn't render bullet visuals
    -- because we never hit the gun script, so we fake them locally)
    local tracerEnabled   = true
    local tracerColor     = Color3.fromRGB(0, 255, 80)
    local tracerLifetime  = 0.20
    local tracerThickness = 0.12
    -- Beam visual style. Each name maps to a builder in spawnTracer.
    --   "Standard"  - two-beam halo + white-hot inner with scrolling texture
    --   "Laser"     - single sharp solid beam, no halo, no texture
    --   "Lightning" - segmented jagged beam with electric texture
    --   "Plasma"    - thick pulsing glowing beam
    --   "Thin"      - single thin beam in solid color, no halo
    local tracerStyle     = "Standard"
    -- Trail particles along the beam path (sparkles linger after the shot).
    local trailEnabled    = false
    local hitSoundEnabled = true
    local hitSoundId      = 135698842254153  -- "crit" by default
    local hitSoundVolume  = 1.0

    local lastFire = 0

    local _RS = game:GetService("ReplicatedStorage")

    local function getEquippedTool()
        local c = lplr.Character
        return c and c:FindFirstChildOfClass("Tool")
    end

    local function isShotgun()
        local t = getEquippedTool()
        if not t then return false end
        if SHOTGUN_NAMES[t.Name] then return true end
        -- substring fallback for unknown naming variations
        local lower = t.Name:lower()
        for _, key in ipairs(SHOTGUN_SUBSTRINGS) do
            if lower:find(key, 1, true) then return true end
        end
        return false
    end

    -- diagnostic: log Tool.Name once per unique tool so the user can see
    -- what HC actually names guns and confirm shotgun detection
    local function logToolOnce()
        local t = getEquippedTool()
        if t and not _loggedTools[t.Name] then
            _loggedTools[t.Name] = true
            print(("[forceHit] equipped: %q  isShotgun=%s"):format(t.Name, tostring(isShotgun())))
        end
    end

    local function getHead()
        local c = lplr.Character
        return c and c:FindFirstChild("Head")
    end

    -- Pretty fake bullet tracer using two layered Beam constraints:
    --   * OUTER beam = wide, semi-transparent halo glow (the user's
    --     chosen tracerColor)
    --   * INNER beam = narrower bright core with a white midpoint
    --     gradient (gives the laser a hot-center feel)
    --   * Width tapers from origin -> hit so it looks like a real
    --     bullet streak (fat at the muzzle, thin at the target)
    --
    -- Stages:
    --   1. Travel: the END attachment animates from origin toward
    --      hitPos over ~40ms so the beam "extends" along the bullet
    --      path
    --   2. Impact: neon ball + PointLight at hit, expands and fades
    --   3. Fade: both beams fade transparency to 1 over tracerLifetime
    --
    -- All local-only.
    local function spawnTracer(origin, hitPos)
        if not tracerEnabled then return end
        local dist = (hitPos - origin).Magnitude
        if dist < 0.5 then return end

        local dir = (hitPos - origin).Unit

        local function invisAnchor(pos)
            local p = Instance.new("Part")
            p.Anchored     = true
            p.CanCollide   = false
            p.CanTouch     = false
            p.CanQuery     = false
            p.CastShadow   = false
            p.Size         = Vector3.new(0.05, 0.05, 0.05)
            p.Transparency = 1
            p.CFrame       = CFrame.new(pos)
            p.Parent       = workspace
            return p
        end

        local startPart = invisAnchor(origin)
        startPart.Name  = "_fh_tracer_start"
        local endPart   = invisAnchor(origin)  -- starts at origin, animates to hit
        endPart.Name    = "_fh_tracer_end"

        local att0 = Instance.new("Attachment"); att0.Parent = startPart
        local att1 = Instance.new("Attachment"); att1.Parent = endPart

        -- Build the beam(s) according to tracerStyle. Each builder
        -- returns a list of Beam instances so the fade phase can
        -- animate all of them uniformly.
        local beams = {}
        local function mkBeam()
            local b = Instance.new("Beam")
            b.Attachment0 = att0; b.Attachment1 = att1
            b.LightEmission = 1; b.LightInfluence = 0
            b.FaceCamera = true; b.Segments = 1
            b.Parent = startPart
            table.insert(beams, b)
            return b
        end

        if tracerStyle == "Laser" then
            -- single sharp thin beam, full opacity, no texture, no halo
            local b = mkBeam()
            b.Width0 = tracerThickness * 1.2
            b.Width1 = tracerThickness * 1.2
            b.Color  = ColorSequence.new(tracerColor)
            b.Transparency = NumberSequence.new(0)

        elseif tracerStyle == "Thin" then
            -- single thin beam in tracerColor, no halo, no texture
            local b = mkBeam()
            b.Width0 = tracerThickness * 0.6
            b.Width1 = tracerThickness * 0.6
            b.Color  = ColorSequence.new(tracerColor)
            b.Transparency = NumberSequence.new(0.1)

        elseif tracerStyle == "Lightning" then
            -- jagged electric beam with multiple segments + scrolling texture
            local b = mkBeam()
            b.Width0 = tracerThickness * 2.5
            b.Width1 = tracerThickness * 2.5
            b.Segments = math.max(8, math.floor(dist / 4))
            b.CurveSize0 = 1.5; b.CurveSize1 = -1.5
            b.Color = ColorSequence.new(tracerColor)
            b.Transparency = NumberSequence.new(0.1)
            pcall(function()
                b.Texture = "rbxassetid://446111271"
                b.TextureMode = Enum.TextureMode.Wrap
                b.TextureLength = 1
                b.TextureSpeed = 15
            end)

        elseif tracerStyle == "Plasma" then
            -- thick pulsing glow, no inner core
            local b = mkBeam()
            b.Width0 = tracerThickness * 7
            b.Width1 = tracerThickness * 5
            b.Color = ColorSequence.new(tracerColor)
            b.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0,   0.4),
                NumberSequenceKeypoint.new(0.5, 0.15),
                NumberSequenceKeypoint.new(1,   0.4),
            })
            pcall(function()
                b.Texture = "rbxassetid://1837228550"  -- soft glow
                b.TextureMode = Enum.TextureMode.Stretch
            end)

        else
            -- "Standard" - outer halo + inner white-hot core w/ scrolling texture
            local outer = mkBeam()
            outer.Width0 = tracerThickness * 5
            outer.Width1 = tracerThickness * 4
            outer.Color  = ColorSequence.new(tracerColor)
            outer.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0,   0.55),
                NumberSequenceKeypoint.new(0.5, 0.35),
                NumberSequenceKeypoint.new(1,   0.55),
            })
            local inner = mkBeam()
            inner.Width0 = tracerThickness * 1.8
            inner.Width1 = tracerThickness * 1.2
            inner.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0,   tracerColor),
                ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1,   tracerColor),
            })
            inner.Transparency = NumberSequence.new(0.05)
            pcall(function()
                inner.Texture = "rbxassetid://446111271"
                inner.TextureMode = Enum.TextureMode.Wrap
                inner.TextureLength = 6
                inner.TextureSpeed = 8
            end)
        end

        -- TRAIL PARTICLES: sparkles along the bullet path that linger
        -- ~500ms. Anchored midpoint parts each emit once.
        if trailEnabled then
            local TRAIL_PARTS = math.clamp(math.floor(dist / 6), 3, 12)
            task.spawn(function()
                for i = 1, TRAIL_PARTS do
                    local pos = origin + dir * (dist * (i / TRAIL_PARTS))
                    local anchor = invisAnchor(pos)
                    anchor.Name = "_fh_tracer_trail"
                    local att = Instance.new("Attachment", anchor)
                    local pe = Instance.new("ParticleEmitter")
                    pe.Texture = "rbxassetid://241876428"
                    pe.LightEmission = 1
                    pe.Color = ColorSequence.new(tracerColor)
                    pe.Size = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.25),
                        NumberSequenceKeypoint.new(1, 0),
                    })
                    pe.Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.2),
                        NumberSequenceKeypoint.new(1, 1),
                    })
                    pe.Lifetime = NumberRange.new(0.3, 0.5)
                    pe.Rate = 0
                    pe.Speed = NumberRange.new(0.5, 1.5)
                    pe.SpreadAngle = Vector2.new(180, 180)
                    pe.Parent = att
                    pe:Emit(3)
                    task.delay(0.6, function() if anchor.Parent then anchor:Destroy() end end)
                end
            end)
        end

        task.spawn(function()
            -- (1) travel: extend end attachment from origin -> hit.
            -- A bit longer than before (60ms) so the eye can actually
            -- track the beam shoot out rather than seeing it pop in.
            local TRAVEL_STEPS    = 8
            local TRAVEL_DURATION = 0.06
            for i = 1, TRAVEL_STEPS do
                task.wait(TRAVEL_DURATION / TRAVEL_STEPS)
                if not startPart.Parent then return end
                endPart.CFrame = CFrame.new(origin + dir * (dist * (i / TRAVEL_STEPS)))
            end
            if not startPart.Parent then return end
            endPart.CFrame = CFrame.new(hitPos)

            -- (2) impact: bright neon ball, expanding shockwave ring,
            --     and a sparkle particle burst.
            local flash = invisAnchor(hitPos)
            flash.Transparency = 0
            flash.Material     = Enum.Material.Neon
            flash.Color        = tracerColor
            flash.Shape        = Enum.PartType.Ball
            flash.Size         = Vector3.new(0.6, 0.6, 0.6)
            flash.Name         = "_fh_tracer_flash"
            local light = Instance.new("PointLight")
            light.Color      = tracerColor
            light.Brightness = 5
            light.Range      = 10
            light.Parent     = flash

            -- shockwave ring (a thin disc that expands outward)
            local ring = Instance.new("Part")
            ring.Anchored=true; ring.CanCollide=false; ring.CanTouch=false; ring.CanQuery=false; ring.CastShadow=false
            ring.Material = Enum.Material.Neon
            ring.Shape    = Enum.PartType.Cylinder
            ring.Color    = tracerColor
            ring.Size     = Vector3.new(0.05, 0.5, 0.5)
            ring.Transparency = 0.3
            -- orient ring perpendicular to the bullet path
            ring.CFrame   = CFrame.lookAt(hitPos, hitPos + dir) * CFrame.Angles(0, math.rad(90), 0)
            ring.Parent   = workspace
            ring.Name     = "_fh_tracer_ring"

            -- sparkle particle burst via an Attachment+ParticleEmitter
            local sparkAtt = Instance.new("Attachment", flash)
            local sparks = Instance.new("ParticleEmitter")
            sparks.Texture          = "rbxassetid://241876428"  -- soft glow
            sparks.LightEmission    = 1
            sparks.Color            = ColorSequence.new(tracerColor)
            sparks.Size             = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.4),
                NumberSequenceKeypoint.new(1, 0)
            })
            sparks.Transparency     = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1)
            })
            sparks.Lifetime         = NumberRange.new(0.15, 0.35)
            sparks.Rate             = 0
            sparks.Speed            = NumberRange.new(8, 14)
            sparks.SpreadAngle      = Vector2.new(180, 180)
            sparks.Parent           = sparkAtt
            sparks:Emit(18)

            task.spawn(function()
                local FLASH_STEPS    = 10
                local FLASH_DURATION = 0.22
                for i = 1, FLASH_STEPS do
                    task.wait(FLASH_DURATION / FLASH_STEPS)
                    if not flash.Parent then return end
                    local p = i / FLASH_STEPS
                    local s = 0.6 + p * 2.6
                    flash.Size         = Vector3.new(s, s, s)
                    flash.Transparency = p
                    light.Brightness   = 5 * (1 - p)
                    -- shockwave ring expands faster than the ball
                    if ring.Parent then
                        local r = 0.5 + p * 4.5
                        ring.Size = Vector3.new(0.05, r, r)
                        ring.Transparency = 0.3 + (1 - 0.3) * p
                    end
                end
                if flash.Parent then flash:Destroy() end
                if ring.Parent  then ring:Destroy()  end
            end)

            -- (3) fade all beams uniformly over tracerLifetime
            local FADE_STEPS = 8
            for i = 1, FADE_STEPS do
                task.wait(tracerLifetime / FADE_STEPS)
                if not startPart.Parent then return end
                local p = i / FADE_STEPS
                for _, b in ipairs(beams) do
                    if b.Parent then
                        b.Transparency = NumberSequence.new(p)
                    end
                end
            end
            if startPart.Parent then startPart:Destroy() end
            if endPart.Parent   then endPart:Destroy()   end
        end)
    end

    -- play the configured hit sound at the target's position. Local-only
    -- (parented to PlayerGui so distance-based attenuation doesn't fade
    -- it when we're far from the target). Auto-destroys after playback.
    local function playHitSound()
        if not hitSoundEnabled then return end
        if not hitSoundId or hitSoundId == 0 then return end
        local pg = lplr:FindFirstChildOfClass("PlayerGui")
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://" .. tostring(hitSoundId)
        s.Volume  = math.clamp(hitSoundVolume, 0, 5)
        s.Parent  = pg or workspace
        s:Play()
        task.delay(5, function() if s and s.Parent then s:Destroy() end end)
    end

    -- Canonical HC client-side Shoot payload, verified against a
    -- working reference implementation. pelletCount identical entries
    -- all referencing the SAME target part, with:
    --   origin = local player's HRP.Position
    --   aim    = local player's HRP.Position  (yes, identical to origin)
    --   stamp  = workspace:GetServerTimeNow()
    -- No MainFunction:InvokeServer("GunCheck") follow-up - that extra
    -- remote call was part of what was tripping HC's anti-cheat. The
    -- "Normal" field is set to the head position (NOT a unit vector);
    -- the reference impl does this and the server accepts it, so we
    -- match exactly rather than reasoning about why.
    local function fireShoot(part, pelletCount)
        if not part then return false end
        local me = _RS:FindFirstChild("MainEvent")
        if not me then return false end
        local c = lplr.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        local hitPos  = part.Position
        local hits    = table.create(pelletCount)
        local targets = table.create(pelletCount)
        for i = 1, pelletCount do
            hits[i]    = { Normal = hitPos, Instance = part, Position = hitPos }
            targets[i] = { thePart = part, theOffset = Vector3.zero }
        end
        local payload = { hits, targets, root.Position, root.Position, workspace:GetServerTimeNow() }
        return pcall(function() me:FireServer("Shoot", payload) end)
    end
    -- Legacy single-shot wrapper kept for non-shotgun call sites
    local function fireDirect(part)
        return fireShoot(part, 1)
    end

    -- Resolve the gun's actual muzzle position. HC's anti-cheat compares
    -- packet origin against the equipped tool's barrel position; using
    -- our head's position made every shot look like a head-mounted gun.
    -- Falls back to head if no tool / handle.
    local function getMuzzlePos()
        local c = lplr.Character
        if not c then return nil end
        local tool = c:FindFirstChildOfClass("Tool")
        if tool then
            local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
            if handle then
                -- attachments named Muzzle/Tip take precedence; some HC guns
                -- have a "Muzzle" Attachment on the Handle
                for _, a in ipairs(handle:GetChildren()) do
                    if a:IsA("Attachment") and (a.Name == "Muzzle" or a.Name == "Tip") then
                        return a.WorldPosition
                    end
                end
                return handle.Position
            end
        end
        local h = getHead(); return h and h.Position or nil
    end

    -- shotgun synth path (v11): TWO-PART V-SHAPE.
    -- User wants pellets spread across TWO body parts forming a V:
    --   - partA (UpperTorso) pellets on a line angled +30deg from horiz
    --   - partB (LowerTorso) pellets on a line angled -30deg from horiz
    -- Together they form a chevron / V pattern when viewed from camera.
    -- partA is the `part` passed in (already UpperTorso, set by fireOnce);
    -- partB is sibling LowerTorso (falls back to HumanoidRootPart if
    -- LowerTorso doesn't exist on the rig).
    --
    -- The line on each part is in WORLD-horizontal direction, rotated
    -- by +-LINE_ANGLE around the face's outward normal. Each line has
    -- its own LINE_HALF_LEN range; per-pellet position is random along
    -- the line + tiny perpendicular jitter.
    local LINE_HALF_LEN = 0.28   -- shorter than v10 so 2 lines fit cleanly
    local LINE_PERP_JIT = 0.02
    local LINE_ANGLE_DEG = 30    -- arms of the V at +-30deg from horiz

    -- helper: generate `count` pellet entries on `bp` at line angle `angDeg`.
    -- Appends into `hits` and `targets` starting at index `baseIdx + 1`.
    local function _vGenOnPart(bp, count, angDeg, origin, hits, targets, baseIdx)
        local sz = bp.Size
        local toLocal = bp.CFrame:VectorToObjectSpace(origin - bp.Position)
        local ax, ay, az = math.abs(toLocal.X), math.abs(toLocal.Y), math.abs(toLocal.Z)
        local faceIdx, faceSign
        if ax >= ay and ax >= az then
            faceIdx, faceSign = 1, (toLocal.X >= 0) and 1 or -1
        elseif ay >= az then
            faceIdx, faceSign = 2, (toLocal.Y >= 0) and 1 or -1
        else
            faceIdx, faceSign = 3, (toLocal.Z >= 0) and 1 or -1
        end

        local LOCAL_AXES = {
            Vector3.new(1, 0, 0),
            Vector3.new(0, 1, 0),
            Vector3.new(0, 0, 1),
        }
        local FACE_INPLANE = {
            [1] = { 2, 3 },
            [2] = { 1, 3 },
            [3] = { 1, 2 },
        }
        local axA, axB = FACE_INPLANE[faceIdx][1], FACE_INPLANE[faceIdx][2]
        local worldAxA = bp.CFrame:VectorToWorldSpace(LOCAL_AXES[axA])
        local worldAxB = bp.CFrame:VectorToWorldSpace(LOCAL_AXES[axB])
        -- horiz = smaller |Y|, vert = larger |Y|
        local horizIdx, vertIdx
        if math.abs(worldAxA.Y) <= math.abs(worldAxB.Y) then
            horizIdx, vertIdx = axA, axB
        else
            horizIdx, vertIdx = axB, axA
        end
        local horizVec = LOCAL_AXES[horizIdx]
        local vertVec  = LOCAL_AXES[vertIdx]

        -- line direction in (horiz, vert) plane, rotated by angDeg
        local rad = math.rad(angDeg)
        local lineH, lineV = math.cos(rad), math.sin(rad)
        local perpH, perpV = -lineV, lineH

        local faceSize = ({sz.X, sz.Y, sz.Z})[faceIdx]
        local faceOff  = LOCAL_AXES[faceIdx] * (faceSize * 0.5 * faceSign)
        local worldN   = bp.CFrame:VectorToWorldSpace(LOCAL_AXES[faceIdx] * faceSign)

        local ts = table.create(count)
        for i = 1, count do
            ts[i] = (math.random() * 2 - 1) * LINE_HALF_LEN
        end
        table.sort(ts)
        for i = 1, count do
            local t = ts[i]
            local p = (math.random() * 2 - 1) * LINE_PERP_JIT
            local h = t * lineH + p * perpH
            local v = t * lineV + p * perpV
            local off = faceOff + horizVec * h + vertVec * v
            local pos = bp.CFrame:PointToWorldSpace(off)
            local idx = baseIdx + i
            hits[idx]    = { Normal = worldN, Instance = bp, Position = pos }
            targets[idx] = { thePart = bp, theOffset = off }
        end
    end

    -- Shotgun fire path: just routes to fireShoot with the gun's pellet
    -- count. The old V-pattern / barrel-origin / centroid-aim synth was
    -- what HC anti-cheat was kicking on. Reference impl sends N identical
    -- pellets all at the same part, and HC accepts it.
    local function fireShotgunSynth(part, pelletCount)
        return fireShoot(part, pelletCount or 5)
    end

    -- pick whichever target is most current. Ragebot's target auto-switches
    -- with locks/closest/mouse - we prefer it. Fall back to a manually-set
    -- target if ragebot has none.
    local function currentTarget()
        if rbGetTarget then
            local p = rbGetTarget()
            if p and p.Parent then return p end
        end
        if target and target.Parent then return target end
        return nil
    end

    -- like getTargetMainPart() but uses currentTarget() instead of `target`
    local function getCurrentTargetPart()
        local p = currentTarget(); if not p or not p.Character then return nil end
        local sp = p.Character:FindFirstChild("SpecialParts") or p.Character
        return sp:FindFirstChild(hitPartName)
            or sp:FindFirstChild("HumanoidRootPart")
            or sp:FindFirstChild("Head")
    end

    -- self-knock check: refuse to fire while we're K.O. so we don't
    -- waste shots / trip "shooting while knocked" detection
    local function selfIsKnocked()
        if F.games and F.games.hoodCustoms and F.games.hoodCustoms.isKnocked then
            local ok, knocked = pcall(F.games.hoodCustoms.isKnocked, lplr)
            if ok and knocked then return true end
        end
        return false
    end

    -- ============================================================
    --  Event-driven FX watchers
    -- ============================================================
    --  The old "snapshot value, wait 150ms, compare" approach was
    --  racy: if multiple shots are in flight, the second shot's
    --  snapshot captures the post-first-shot value, so when its
    --  delayed check fires the value LOOKS unchanged and we silently
    --  miss the second tracer / sound.
    --
    --  Event-driven: maintain a watcher on the relevant signal
    --  (Ammo.Value or Humanoid.HealthChanged). Every individual
    --  decrement event fires the FX exactly once, gated by "we
    --  fired within the last 0.5s" so unrelated damage (other
    --  players shooting the same target) doesn't trigger.
    -- ============================================================

    -- last-fire bookkeeping (read by the watchers when they fire)
    local _lastFireOrigin, _lastFireHit
    local _lastFireForFx = 0
    local FX_FIRE_WINDOW = 0.5  -- seconds after fire that a damage / ammo event can claim

    -- find first Tool in Character or Backpack that has a Script.Ammo IntValue
    local function findCurrentAmmo()
        local function pull(parent)
            if not parent then return nil end
            for _, tool in ipairs(parent:GetChildren()) do
                if tool:IsA("Tool") then
                    local scr = tool:FindFirstChild("Script")
                    if scr then
                        local av = scr:FindFirstChild("Ammo")
                        if av and (av:IsA("IntValue") or av:IsA("NumberValue")) then
                            return av
                        end
                    end
                end
            end
            return nil
        end
        return pull(lplr.Character) or pull(lplr:FindFirstChild("Backpack"))
    end

    -- ammo watcher: each Value-decrease event spawns ONE tracer using
    -- the stashed origin/hit from the most recent fire (if within the
    -- fire window). Consumes the stash so multiple decrements without
    -- another fire don't all draw the same tracer.
    local _watchedAmmo, _watchedAmmoConn, _watchedAmmoLast
    local function ensureAmmoWatch()
        local av = findCurrentAmmo()
        if av == _watchedAmmo then return end
        if _watchedAmmoConn then _watchedAmmoConn:Disconnect(); _watchedAmmoConn = nil end
        _watchedAmmo = av
        if not av then return end
        _watchedAmmoLast = av.Value
        _watchedAmmoConn = av:GetPropertyChangedSignal("Value"):Connect(function()
            local newV = av.Value
            local old  = _watchedAmmoLast
            _watchedAmmoLast = newV
            if old and newV < old
                and _lastFireOrigin
                and (tick() - _lastFireForFx < FX_FIRE_WINDOW) then
                spawnTracer(_lastFireOrigin, _lastFireHit)
                _lastFireOrigin, _lastFireHit = nil, nil  -- consume
            end
        end)
    end

    -- target-humanoid watcher: each HealthChanged with health < lastHealth
    -- plays ONE hit sound (gated by recent fire). Re-attaches when the
    -- target changes.
    local _watchedHum, _watchedHumConn, _watchedHumLast
    local function ensureHumWatch()
        local plr = currentTarget()
        local hum = plr and plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
        if hum == _watchedHum then return end
        if _watchedHumConn then _watchedHumConn:Disconnect(); _watchedHumConn = nil end
        _watchedHum = hum
        if not hum then return end
        _watchedHumLast = hum.Health
        _watchedHumConn = hum.HealthChanged:Connect(function(newHP)
            local old = _watchedHumLast
            _watchedHumLast = newHP
            if old and newHP < old and (tick() - _lastFireForFx < FX_FIRE_WINDOW) then
                playHitSound()
            end
        end)
    end

    local function fireOnce()
        if tick() - lastFire < cooldown then return end
        if selfIsKnocked() then return end
        local part = getCurrentTargetPart(); if not part then return end

        -- diagnostic so the user can see if shotgun detection actually matches
        logToolOnce()

        local headPart = getHead()
        local origin   = headPart and headPart.Position
        local shotgun  = isShotgun()
        local tool     = getEquippedTool()
        -- pellet count: explicit table lookup, otherwise default to 5 for
        -- anything substring-matched as a shotgun, otherwise 1
        local pellets
        if shotgun then
            pellets = (tool and SHOTGUN_PELLETS[tool.Name]) or 5
        else
            pellets = 1
        end

        -- For SHOTGUNS, override the target body part to ALWAYS be the
        -- torso, regardless of what hitPart the user picked. The hitPart
        -- dropdown still controls fireDirect (revolvers / pistols).
        -- Rationale: shotguns naturally land their pellet line on a
        -- large flat area; the torso is the largest, most consistent
        -- target. Head-targeting shotgun shots produced 200 dmg per
        -- shot which trips the per-shot damage cap.
        if shotgun then
            local sp = part.Parent
            if sp and sp.Name == "SpecialParts" then
                local torso = sp:FindFirstChild("UpperTorso")
                           or sp:FindFirstChild("Torso")
                           or sp:FindFirstChild("LowerTorso")
                           or sp:FindFirstChild("HumanoidRootPart")
                if torso and torso:IsA("BasePart") then
                    part = torso
                end
            end
        end

        local fired = false
        if shotgun then
            if fireShotgunSynth(part, pellets) then fired = true end
        else
            if fireDirect(part) then fired = true end
        end

        if fired then
            lastFire = tick()
            -- Stash this fire's origin/hit so the ammo watcher can
            -- consume them on the next decrement event, and bump the
            -- fire-window timestamp so both watchers consider this a
            -- recent fire for FX-gating purposes.
            _lastFireOrigin = origin
            _lastFireHit    = part.Position
            _lastFireForFx  = tick()
            -- Make sure watchers are attached to the current ammo /
            -- target. Cheap when nothing changed (refs match).
            ensureAmmoWatch()
            ensureHumWatch()
        end
    end

    -- ============================================================
    --  Fake ammo HUD
    -- ============================================================
    --  A small rounded panel in the bottom-right (above the real
    --  ammo counter) showing "Ammo / MaxAmmo" read straight off
    --  Tool.Script.Ammo + Tool.Script.MaxAmmo. Sub-label says
    --  "(forcehit ammo)" so it's obvious it's the cheat's view of
    --  the true ammo, not the game's CLIENT counter (which would
    --  otherwise stay stale after every forceHit shot).
    --
    --  Only shown while G.hcForceHitActive. Created on start(),
    --  destroyed on stop().
    -- ============================================================
    local hudGui, hudConn

    local function findAmmoPair()
        -- Only check Character — i.e. the tool the player currently has
        -- equipped. If nothing's equipped (no Tool under Character), we
        -- return nil so the HUD hides itself. Backpack tools are
        -- intentionally ignored so the panel disappears the moment the
        -- gun is unequipped instead of lingering with stale Backpack
        -- numbers.
        local char = lplr.Character
        if not char then return nil, nil end
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") then
                local scr = tool:FindFirstChild("Script")
                if scr then
                    local av = scr:FindFirstChild("Ammo")
                    if av and (av:IsA("IntValue") or av:IsA("NumberValue")) then
                        local mv = scr:FindFirstChild("MaxAmmo")
                        local maxV = mv and (mv:IsA("IntValue") or mv:IsA("NumberValue")) and mv.Value or nil
                        return av.Value, maxV
                    end
                end
            end
        end
        return nil, nil
    end

    local function hudDestroy()
        if hudConn then hudConn:Disconnect(); hudConn = nil end
        if hudGui  then pcall(function() hudGui:Destroy() end); hudGui = nil end
    end

    local function hudCreate()
        if hudGui then return end
        hudGui = Instance.new("ScreenGui")
        hudGui.Name             = "_fh_ammo_hud"
        hudGui.ResetOnSpawn     = false
        hudGui.IgnoreGuiInset   = true
        hudGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
        -- prefer CoreGui (CoreGui survives respawn AND can't be wiped
        -- by the game), fall back to PlayerGui
        local parented = pcall(function() hudGui.Parent = game:GetService("CoreGui") end)
        if not parented or not hudGui.Parent then
            hudGui.Parent = lplr:WaitForChild("PlayerGui")
        end

        local frame = Instance.new("Frame")
        frame.Name                  = "Bg"
        frame.Size                  = UDim2.fromOffset(140, 60)
        -- anchor to bottom-right, slightly above the game's ammo counter
        frame.AnchorPoint           = Vector2.new(1, 1)
        frame.Position              = UDim2.new(1, -20, 1, -100)
        frame.BackgroundColor3      = Color3.fromRGB(15, 15, 15)
        frame.BackgroundTransparency = 0.35
        frame.BorderSizePixel       = 0
        frame.Parent                = hudGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent       = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color        = Color3.fromRGB(80, 80, 80)
        stroke.Thickness    = 1
        stroke.Transparency = 0.4
        stroke.Parent       = frame

        local mainLbl = Instance.new("TextLabel")
        mainLbl.Name                   = "Ammo"
        mainLbl.Size                   = UDim2.new(1, -8, 0, 32)
        mainLbl.Position               = UDim2.new(0, 4, 0, 4)
        mainLbl.BackgroundTransparency = 1
        mainLbl.Text                   = "0 / 0"
        mainLbl.TextColor3             = Color3.fromRGB(255, 255, 255)
        mainLbl.TextStrokeTransparency = 0.5
        mainLbl.TextSize               = 24
        mainLbl.Font                   = Enum.Font.GothamBold
        mainLbl.Parent                 = frame

        local subLbl = Instance.new("TextLabel")
        subLbl.Name                   = "Sub"
        subLbl.Size                   = UDim2.new(1, -8, 0, 16)
        subLbl.Position               = UDim2.new(0, 4, 0, 38)
        subLbl.BackgroundTransparency = 1
        subLbl.Text                   = "(forcehit ammo)"
        subLbl.TextColor3             = Color3.fromRGB(180, 180, 180)
        subLbl.TextSize               = 12
        subLbl.Font                   = Enum.Font.Gotham
        subLbl.Parent                 = frame

        if hudConn then hudConn:Disconnect() end
        hudConn = RunService.Heartbeat:Connect(function()
            if not G.hcForceHitActive or not hudGui then return end
            local a, m = findAmmoPair()
            if a then
                mainLbl.Text  = tostring(a) .. " / " .. tostring(m or "?")
                frame.Visible = true
            else
                frame.Visible = false
            end
        end)
    end

    local function start()
        G.hcForceHitActive = true
        hudCreate()
    end

    local function stop()
        G.hcForceHitActive = false
        hudDestroy()
    end

    local t = makeToggle(start, stop, "hcForceHitActive")
    -- public hotkey trigger - the loader's bindFireKey calls this
    t.fire          = function()
        if not G.hcForceHitActive then return end
        fireOnce()
    end
    t.setTarget     = function(plr) target = plr end
    t.getTarget     = function() return target end
    t.setHitPart    = function(name) hitPartName = name or "Head" end
    t.getHitPart    = function() return hitPartName end
    t.setCooldown   = function(n) cooldown = math.max(0, tonumber(n) or 0.2) end
    -- setShotgunMode / getShotgunMode removed - there's only one path now
    -- (synth, the canonical-payload direct FireServer). Kept as no-op
    -- stubs so the loader doesn't crash if it still tries to call them.
    t.setShotgunMode = function() end
    t.getShotgunMode = function() return "synth" end
    -- tracer + hit sound
    t.setTracerEnabled  = function(v) tracerEnabled = v == true end
    t.setTracerColor    = function(c) if typeof(c) == "Color3" then tracerColor = c end end
    t.setTracerLifetime = function(n) tracerLifetime = math.clamp(tonumber(n) or 0.2, 0.05, 2) end
    t.setTracerThickness = function(n) tracerThickness = math.clamp(tonumber(n) or 0.12, 0.02, 1) end
    t.setTracerStyle    = function(s) tracerStyle = tostring(s or "Standard") end
    t.getTracerStyle    = function() return tracerStyle end
    t.setTrailEnabled   = function(v) trailEnabled = v == true end
    t.setHitSoundEnabled = function(v) hitSoundEnabled = v == true end
    t.setHitSoundId      = function(id) hitSoundId = tonumber(id) or 0 end
    t.setHitSoundVolume  = function(n) hitSoundVolume = math.clamp(tonumber(n) or 1, 0, 5) end
    t.isShotgunEquipped = isShotgun
    return t
end)()

-- ============================================================
--  HOOD CUSTOMS: KNIFE BOT (attach + 1Hz stab + auto-equip)
-- ============================================================
--  Two independent toggles bundled under F.games.hoodCustoms.knifeBot:
--
--    attach.start() / .stop() / .setDistance(n)
--      Each Heartbeat, snap HRP to a position `distance` studs
--      behind the ragebot's current target. Once per second, fire
--      a synthetic MouseButton1 click via VirtualInputManager so the
--      equipped knife swings at the target.
--
--    autoEquip.start() / .stop()
--      Each CharacterAdded + once on start, equip the "[Knife]" tool
--      from the player's Backpack. Re-equips on respawn.
--
--  Built as an IIFE so all the local helpers stay scoped here and
--  don't eat top-level register slots (chunk is at Luau's 200-local
--  limit).
-- ============================================================
F.games.hoodCustoms.knifeBot = (function()
    local KNIFE_NAME = "[Knife]"

    -- -------- attach --------
    local attachDistance = 3      -- studs from target
    local clickInterval  = 0.6    -- seconds between auto-clicks
    local orbitActive    = false  -- rotate around target while attached
    local orbitSpeed     = 180    -- degrees / second
    local orbitAngle     = 0      -- internal accumulator
    local attachHbConn, attachClickThread
    local attachActive   = false

    local function getTargetHRP()
        if not rbGetTarget then return nil end
        local plr = rbGetTarget()
        if not plr or plr == lplr then return nil end
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- forcibly disable ragebot autoshoot + HC forcehit so they don't
    -- fire alongside the knife. Setting RageSettings.AutoShoot = false
    -- + G.hcForceHitActive = false here is the engine-level mute;
    -- the loader also flips the UI toggles off so the GUI matches.
    local function muteRangedAutos()
        pcall(function()
            if RageSettings then RageSettings.AutoShoot = false end
        end)
        G.hcForceHitActive = false
        pcall(function()
            if F.games and F.games.hoodCustoms and F.games.hoodCustoms.forceHit then
                F.games.hoodCustoms.forceHit.stop()
            end
        end)
    end

    local function attachStart()
        if attachActive then return end
        attachActive = true
        G.hcKnifeAttachActive = true
        orbitAngle = 0
        muteRangedAutos()

        if attachHbConn then attachHbConn:Disconnect() end
        attachHbConn = RunService.Heartbeat:Connect(function(dt)
            if not attachActive then return end
            -- keep ragebot autoshoot + forcehit muted every frame in
            -- case something else flips them back on
            muteRangedAutos()

            local c = lplr.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local tHrp = getTargetHRP()
            if not tHrp then return end

            local pos
            if orbitActive then
                orbitAngle = (orbitAngle + orbitSpeed * dt) % 360
                local rad = math.rad(orbitAngle)
                pos = tHrp.Position + Vector3.new(math.cos(rad), 0, math.sin(rad)) * attachDistance
            else
                -- snap behind the target (so the knife swing arc lands)
                local forward = tHrp.CFrame.LookVector
                pos = tHrp.Position - forward * attachDistance
            end
            pcall(function()
                hrp.CFrame = CFrame.new(pos, tHrp.Position)
            end)
        end)

        if attachClickThread then pcall(task.cancel, attachClickThread) end
        attachClickThread = task.spawn(function()
            while attachActive do
                local tHrp = getTargetHRP()
                if tHrp then
                    pcall(function()
                        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true,  game, 0)
                        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                    end)
                end
                -- read the live value so slider changes take effect
                -- immediately without needing a toggle off/on
                task.wait(clickInterval)
            end
        end)
    end

    local function attachStop()
        attachActive = false
        G.hcKnifeAttachActive = false
        if attachHbConn then attachHbConn:Disconnect(); attachHbConn = nil end
        if attachClickThread then pcall(task.cancel, attachClickThread); attachClickThread = nil end
    end

    -- -------- auto-equip --------
    local autoEquipActive = false
    local autoEquipCharConn, autoEquipThread

    local function tryEquipKnife()
        local char = lplr.Character; if not char then return false end
        local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return false end
        if char:FindFirstChild(KNIFE_NAME) then return true end
        local bp = lplr:FindFirstChild("Backpack")
        if not bp then return false end
        local tool = bp:FindFirstChild(KNIFE_NAME)
        if not tool or not tool:IsA("Tool") then return false end
        pcall(function() hum:EquipTool(tool) end)
        return true
    end

    local function autoEquipStart()
        if autoEquipActive then return end
        autoEquipActive = true
        G.hcKnifeAutoEquipActive = true
        tryEquipKnife()

        if autoEquipCharConn then autoEquipCharConn:Disconnect() end
        autoEquipCharConn = lplr.CharacterAdded:Connect(function()
            if not autoEquipActive then return end
            local bp = lplr:WaitForChild("Backpack", 10)
            if bp then bp:WaitForChild(KNIFE_NAME, 10) end
            if autoEquipActive then tryEquipKnife() end
        end)

        -- aggressive re-check: every 0.2s so a brief unequip
        -- (tool switch, animation interrupt) is corrected fast.
        if autoEquipThread then pcall(task.cancel, autoEquipThread) end
        autoEquipThread = task.spawn(function()
            while autoEquipActive do
                task.wait(0.2)
                if autoEquipActive then tryEquipKnife() end
            end
        end)
    end

    local function autoEquipStop()
        autoEquipActive = false
        G.hcKnifeAutoEquipActive = false
        if autoEquipCharConn then autoEquipCharConn:Disconnect(); autoEquipCharConn = nil end
        if autoEquipThread then pcall(task.cancel, autoEquipThread); autoEquipThread = nil end
    end

    return {
        attach = {
            start            = attachStart,
            stop             = attachStop,
            isActive         = function() return attachActive end,
            setDistance      = function(n) attachDistance = math.clamp(tonumber(n) or 3, 0, 50) end,
            getDistance      = function() return attachDistance end,
            setClickInterval = function(n) clickInterval = math.clamp(tonumber(n) or 0.6, 0.05, 5) end,
            getClickInterval = function() return clickInterval end,
            setOrbit         = function(v) orbitActive = v == true end,
            getOrbit         = function() return orbitActive end,
            setOrbitSpeed    = function(n) orbitSpeed = math.clamp(tonumber(n) or 180, 0, 720) end,
            getOrbitSpeed    = function() return orbitSpeed end,
        },
        autoEquip = {
            start    = autoEquipStart,
            stop     = autoEquipStop,
            isActive = function() return autoEquipActive end,
        },
    }
end)()

-- ============================================================
--  GAMES: MURDER MYSTERY 2 (MM2)
-- ============================================================
--  Three features bundled under F.games.mm2:
--
--    identityEsp.start() / .stop()
--      Scans every player's Character + Backpack for tools named
--      "Gun" or "Knife". Above their head, renders a BillboardGui
--      label saying "Sheriff" (Gun) or "Murderer" (Knife). Other
--      players show no label. Updates every 0.5s.
--
--    pickupGun.fire()
--      Locates a BasePart named "GunDrop" in workspace. Spoofs our
--      HRP.CFrame to the drop's position on Heartbeat (write) +
--      RenderStep First (restore real CFrame so locally we stay
--      put). Server sees us at the drop -> auto-pickup proximity
--      triggers. Stops after ~1.5s or when the drop disappears.
--
--    autoPickupGun.start() / .stop()
--      Polls every 0.5s for a GunDrop. When one exists, calls
--      pickupGun.fire() then waits 1.5s before the next check
--      to avoid re-triggering on the same drop.
-- ============================================================
F.games.mm2 = (function()
    local Players = game:GetService("Players")
    local IDENTITY = { Gun = "Sheriff", Knife = "Murderer" }
    local COLORS = {
        Sheriff  = Color3.fromRGB( 80, 160, 255),
        Murderer = Color3.fromRGB(255,  80,  80),
    }

    -- ---------- Identity ESP ----------
    -- Uses Drawing.new("Text") (matches the main ESP look) instead
    -- of BillboardGui. Position is projected from each player's
    -- head every RenderStepped so labels follow heads smoothly.
    -- Identity (Gun -> Sheriff, Knife -> Murderer) is re-scanned
    -- in a separate thread every 0.25s.
    local identityActive = false
    local identityScanThread
    local identityRenderConn
    local identityDraws = {}  -- [Player] = Drawing.new("Text")
    local identityCache = {}  -- [Player] = "Sheriff"|"Murderer"|nil

    -- Reads a player's identity from their Character + Backpack tools.
    -- Callers that want to skip the local player must filter
    -- themselves - autoPickupGun uses this to detect "am I the
    -- murderer" so it can skip pickups.
    local function getIdentity(plr)
        if not plr then return nil end
        local function scan(parent)
            if not parent then return nil end
            for _, t in ipairs(parent:GetChildren()) do
                if t:IsA("Tool") and IDENTITY[t.Name] then
                    return IDENTITY[t.Name]
                end
            end
            return nil
        end
        return scan(plr.Character) or scan(plr:FindFirstChild("Backpack"))
    end

    local function buildDraw()
        if not Drawing or not Drawing.new then return nil end
        local t = Drawing.new("Text")
        t.Visible      = false
        t.Center       = true
        t.Outline      = true
        t.OutlineColor = Color3.new(0, 0, 0)
        t.Color        = Color3.fromRGB(255, 255, 255)
        t.Size         = 13         -- matches main ESP name size
        t.Font         = 2          -- bold
        t.Text         = ""
        return t
    end

    local function removeDraw(plr)
        local d = identityDraws[plr]
        if d then pcall(function() d:Remove() end) end
        identityDraws[plr] = nil
        identityCache[plr] = nil
    end

    local function clearAllDraws()
        for plr, _ in pairs(identityDraws) do
            removeDraw(plr)
        end
    end

    local function identityStart()
        if identityActive then return end
        identityActive = true

        -- background scan: refresh identity cache every 0.25s
        if identityScanThread then pcall(task.cancel, identityScanThread) end
        identityScanThread = task.spawn(function()
            while identityActive do
                local live = {}
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= lplr then
                        live[plr] = true
                        local id = getIdentity(plr)
                        identityCache[plr] = id
                        -- IDENTITY LOST: nuke the draw too. Without
                        -- this, the render loop stops iterating this
                        -- player (cache nil = no entry) and the
                        -- drawing stays stuck at its last position.
                        if not id and identityDraws[plr] then
                            removeDraw(plr)
                        end
                    end
                end
                -- PLAYER LEFT: prune draws (and cache entries) for any
                -- player no longer in Players:GetPlayers().
                for plr, _ in pairs(identityDraws) do
                    if not live[plr] then removeDraw(plr) end
                end
                task.wait(0.25)
            end
        end)

        -- render loop: project head -> screen, position label,
        -- runs every frame so labels follow movement smoothly.
        if identityRenderConn then identityRenderConn:Disconnect() end
        identityRenderConn = RunService.RenderStepped:Connect(function()
            if not identityActive then return end
            local cam = workspace.CurrentCamera
            if not cam then return end
            for plr, id in pairs(identityCache) do
                local d = identityDraws[plr]
                local char = plr.Character
                local head = char and char:FindFirstChild("Head")
                if id and head then
                    if not d then
                        d = buildDraw()
                        identityDraws[plr] = d
                    end
                    if d then
                        local sp, onScreen = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 2.6, 0))
                        if onScreen then
                            d.Position = Vector2.new(sp.X, sp.Y)
                            d.Text     = id
                            d.Color    = COLORS[id] or Color3.fromRGB(255, 255, 255)
                            d.Visible  = true
                        else
                            d.Visible = false
                        end
                    end
                elseif d then
                    -- character / head missing OR identity nil: remove
                    -- the draw entirely so it can't get stuck visible.
                    -- A fresh one rebuilds next time identity returns.
                    removeDraw(plr)
                end
            end
        end)
    end

    local function identityStop()
        identityActive = false
        if identityScanThread then pcall(task.cancel, identityScanThread); identityScanThread = nil end
        if identityRenderConn then identityRenderConn:Disconnect(); identityRenderConn = nil end
        clearAllDraws()
    end

    -- ---------- GunDrop tracking ----------
    -- A live cache of every BasePart named "GunDrop" currently in
    -- workspace, maintained via DescendantAdded/Removing listeners.
    -- The previous workspace:GetDescendants() scan was the dominant
    -- perf cost when MM2 maps have thousands of descendants - this
    -- replaces it with O(1) lookups.
    --
    -- Cache + listener installation are gated on getgenv so script
    -- reloads don't double-stack listeners. The cache table itself
    -- is shared via getgenv too, so listeners installed by a prior
    -- script run still write to the same table this run reads.
    getgenv()._F_MM2_GUNDROP_CACHE = getgenv()._F_MM2_GUNDROP_CACHE or {}
    local _gunDropCache = getgenv()._F_MM2_GUNDROP_CACHE
    if not getgenv()._F_MM2_GUNDROP_HOOKED then
        getgenv()._F_MM2_GUNDROP_HOOKED = true
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == "GunDrop" then
                _gunDropCache[d] = true
            end
        end
        workspace.DescendantAdded:Connect(function(d)
            if d:IsA("BasePart") and d.Name == "GunDrop" then
                _gunDropCache[d] = true
            end
        end)
        workspace.DescendantRemoving:Connect(function(d)
            if _gunDropCache[d] then
                _gunDropCache[d] = nil
            end
        end)
    end

    local function findGunDrop()
        for d, _ in pairs(_gunDropCache) do
            if d.Parent then return d end
            _gunDropCache[d] = nil  -- prune stale
        end
        return nil
    end

    -- Actual teleport pickup: save HRP CFrame, write GunDrop CFrame,
    -- wait PICKUP_HOLD_MS, write the saved CFrame back. The brief
    -- physical presence at the drop triggers MM2's proximity-based
    -- pickup remote. The previous Heartbeat-write/RenderStep-restore
    -- "desync" never put us PHYSICALLY there at all (just spoofed
    -- replication briefly), so the pickup never fired.
    local PICKUP_HOLD_MS = 100   -- ms to stay at the drop
    local pickupActive = false

    -- If any F.desync mode is active when we start the pickup, we
    -- stop it for the duration so our HRP is actually at our REAL
    -- position before the teleport (otherwise the server sees us in
    -- the void / sky / wherever, never at the drop). We restart the
    -- same mode once the pickup window closes.
    local DESYNC_RESTARTERS = {
        void      = "startVoid",
        voidspam  = "startVoidspam",
        sky       = "startSky",
        spin      = "startSpin",
        velocity  = "startVelocity",
        raknet    = "startRaknet",
        invisible = "startInvisible",
    }

    -- Return values:
    --   true                success - teleport in progress
    --   false, "active"     a previous pickup is still mid-flight (silent)
    --   false, "no_drop"    no GunDrop exists in the workspace (notify)
    --   false, "no_hrp"     local character isn't loaded
    local function pickupOnce()
        if pickupActive then return false, "active" end
        local drop = findGunDrop(); if not drop then return false, "no_drop" end
        local char = lplr.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false, "no_hrp" end

        -- snapshot + stop any active desync so we actually go to the
        -- drop position rather than sitting at our spoofed location
        local restartName
        if F.desync and F.desync.getMode then
            local m = F.desync.getMode()
            if m and m ~= "off" and DESYNC_RESTARTERS[m] then
                restartName = DESYNC_RESTARTERS[m]
                F.desync.stop()
            end
        end

        pickupActive = true
        local realCF = hrp.CFrame
        pcall(function() hrp.CFrame = drop.CFrame end)
        task.delay(PICKUP_HOLD_MS / 1000, function()
            if hrp.Parent then
                pcall(function() hrp.CFrame = realCF end)
            end
            pickupActive = false
            -- restore the desync mode that was active before pickup
            if restartName and F.desync and F.desync[restartName] then
                pcall(function() F.desync[restartName]() end)
            end
        end)
        return true
    end

    -- ---------- Dropped-gun ESP ----------
    -- Highlight on the drop part (so you can see through walls) +
    -- a Drawing.new("Text") "GUN" label above it (matches main ESP).
    -- Scan every 0.3s for new/removed drops; project the label
    -- position every RenderStepped.
    local dropEspActive = false
    local dropEspScanThread
    local dropEspRenderConn
    local dropEspAdorned = {}  -- [drop part] = { hl, draw }

    local function buildDropDraw()
        if not Drawing or not Drawing.new then return nil end
        local t = Drawing.new("Text")
        t.Visible      = false
        t.Center       = true
        t.Outline      = true
        t.OutlineColor = Color3.new(0, 0, 0)
        t.Color        = Color3.fromRGB(255, 215, 60)
        t.Size         = 13
        t.Font         = 2
        t.Text         = "GUN"
        return t
    end

    local function attachDropMarker(drop)
        local hl = Instance.new("Highlight")
        hl.Name                = "_mm2_dropgun_hl"
        hl.FillColor           = Color3.fromRGB(255, 215,  60)
        hl.OutlineColor        = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency    = 0.45
        hl.OutlineTransparency = 0
        hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Adornee             = drop
        hl.Parent              = drop
        return hl, buildDropDraw()
    end

    local function removeDropMarker(m)
        if m.hl   and m.hl.Parent   then pcall(function() m.hl:Destroy() end) end
        if m.draw                   then pcall(function() m.draw:Remove() end) end
    end

    local function dropEspClearAll()
        for _, m in pairs(dropEspAdorned) do removeDropMarker(m) end
        dropEspAdorned = {}
    end

    local function dropEspScanTick()
        -- iterate the live cache (O(N) where N = active drop count,
        -- usually 0 or 1) instead of workspace:GetDescendants()
        local seen = {}
        for d, _ in pairs(_gunDropCache) do
            if d.Parent then
                seen[d] = true
                if not dropEspAdorned[d] then
                    local hl, draw = attachDropMarker(d)
                    dropEspAdorned[d] = { hl = hl, draw = draw }
                end
            else
                _gunDropCache[d] = nil  -- prune stale
            end
        end
        for drop, m in pairs(dropEspAdorned) do
            if not seen[drop] or not drop.Parent then
                removeDropMarker(m)
                dropEspAdorned[drop] = nil
            end
        end
    end

    local function dropEspStart()
        if dropEspActive then return end
        dropEspActive = true
        if dropEspScanThread then pcall(task.cancel, dropEspScanThread) end
        dropEspScanThread = task.spawn(function()
            while dropEspActive do
                pcall(dropEspScanTick)
                task.wait(0.3)
            end
        end)
        if dropEspRenderConn then dropEspRenderConn:Disconnect() end
        dropEspRenderConn = RunService.RenderStepped:Connect(function()
            if not dropEspActive then return end
            local cam = workspace.CurrentCamera
            if not cam then return end
            for drop, m in pairs(dropEspAdorned) do
                if drop.Parent and m.draw then
                    local sp, onScreen = cam:WorldToViewportPoint(drop.Position + Vector3.new(0, 1.5, 0))
                    if onScreen then
                        m.draw.Position = Vector2.new(sp.X, sp.Y)
                        m.draw.Visible  = true
                    else
                        m.draw.Visible = false
                    end
                end
            end
        end)
    end

    local function dropEspStop()
        dropEspActive = false
        if dropEspScanThread then pcall(task.cancel, dropEspScanThread); dropEspScanThread = nil end
        if dropEspRenderConn then dropEspRenderConn:Disconnect(); dropEspRenderConn = nil end
        dropEspClearAll()
    end

    -- ---------- Murderer trigger (hover -> fire nil RemoteEvent) ----------
    -- When mouse hovers over the player identified as Murderer, fire a
    -- nil-parented RemoteEvent with (theirHRP.CFrame, myHRP.CFrame).
    -- Args format matches the canonical MM2 hit payload the user
    -- provided. Throttled per-fire so we don't spam the remote.
    local triggerActive = false
    local triggerConn
    local triggerLastFire = 0
    local TRIGGER_COOLDOWN = 0.4

    -- The Gun tool's Shoot RemoteEvent works whether the Gun is in
    -- the Character (equipped) OR in the Backpack (not equipped) -
    -- captured both cases. We check both parents so no auto-equip
    -- is needed.
    local function findHitRemote()
        local function pull(parent)
            if not parent then return nil end
            local gun = parent:FindFirstChild("Gun")
            if not gun then return nil end
            return gun:FindFirstChild("Shoot")
        end
        return pull(lplr.Character) or pull(lplr:FindFirstChild("Backpack"))
    end

    local mouseRef
    local function getMouse()
        if mouseRef then return mouseRef end
        mouseRef = lplr:GetMouse()
        return mouseRef
    end

    local function getHoveredPlayer()
        local m = getMouse(); if not m then return nil end
        local target = m.Target; if not target then return nil end
        local model = target:FindFirstAncestorOfClass("Model")
        if not model then return nil end
        return Players:GetPlayerFromCharacter(model)
    end

    -- Hit-position resolver. Prefers HumanoidRootPart by name (raw
    -- instance, no GetPivot - MM2 might re-point PrimaryPart so the
    -- pivot would be spoofed). Falls through a wide chain so we
    -- ALWAYS return a CFrame as long as the character has any
    -- BasePart, even if MM2 is messing with the standard names.
    local function targetHitCF(char)
        if not char then return nil end
        -- Head first - MM2 server validates the hit part client-claims,
        -- and the shoot remote accepts head shots all the same. Aiming
        -- at the head also makes the visual match what you'd see if
        -- you actually shot the player normally.
        local head = char:FindFirstChild("Head")
        if head and head:IsA("BasePart") then return head.CFrame end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp.CFrame end
        local p = char:FindFirstChild("LowerTorso")
              or char:FindFirstChild("Torso")
              or char:FindFirstChild("UpperTorso")
        if p and p:IsA("BasePart") then return p.CFrame end
        -- GetPivot fallback (may return spoofed pivot but at least
        -- it's a CFrame so the shot fires)
        if char.GetPivot then
            local ok, cf = pcall(function() return char:GetPivot() end)
            if ok and cf then return cf end
        end
        -- Final fallback: any BasePart anywhere in the character
        local any = char:FindFirstChildWhichIsA("BasePart")
        return any and any.CFrame or nil
    end
    -- Second arg is "my position" with identity rotation - matches the
    -- canonical payload exactly (CFrame.new(x, y, z) without basis
    -- vectors).
    local function myPosCFrame()
        local c = lplr.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        return CFrame.new(hrp.Position)
    end


    local function triggerStart()
        if triggerActive then return end
        triggerActive = true
        if triggerConn then triggerConn:Disconnect() end
        triggerConn = RunService.RenderStepped:Connect(function()
            if not triggerActive then return end
            if tick() - triggerLastFire < TRIGGER_COOLDOWN then return end
            local plr = getHoveredPlayer()
            if not plr or plr == lplr then return end
            if F.whitelist and F.whitelist.contains(plr) then return end
            if identityCache[plr] ~= "Murderer" and getIdentity(plr) ~= "Murderer" then return end
            local theirCF = targetHitCF(plr.Character)
            local myPos   = myPosCFrame()
            if not theirCF or not myPos then return end
            local remote = findHitRemote()
            if not remote then return end  -- no Gun in Character or Backpack -> not Sheriff
            -- Canonical payload from captures: arg1 = target's pivot
            -- CFrame (= HRP.CFrame), arg2 = our HRP position with
            -- identity rotation.
            pcall(function() remote:FireServer(theirCF, myPos) end)
            triggerLastFire = tick()
        end)
    end

    local function triggerStop()
        triggerActive = false
        if triggerConn then triggerConn:Disconnect(); triggerConn = nil end
    end

    -- ---------- Shoot murderer (one-shot, no hover required) ----------
    -- Resolves the Murderer from a live getIdentity() scan, then fires
    -- the Gun's Shoot remote with (theirHRP.CFrame, myHRP.CFrame).
    --
    -- If the Gun isn't equipped but we have it in our Backpack
    -- (we're the Sheriff), auto-equips it and delays the fire by
    -- 0.5s so the Gun child + its Shoot remote have time to mount.
    --
    -- Return values (loader uses reason for specific notify):
    --   true                     success (immediate or deferred)
    --   false, "no_my_hrp"       local HRP missing
    --   false, "no_murderer"     no player holds the Knife
    --   false, "no_victim_hrp"   target's HRP missing
    --   false, "no_gun"          no Gun in Character or Backpack
    --                            (we're not the Sheriff)
    -- Same desync-stop-restart pattern as pickup. If we're spoofed
    -- to the void at fire time, the server's shooter-position
    -- validation rejects the hit because arg2 (our real HRP) won't
    -- match where the server thinks we are.
    local SHOOT_DESYNC_RESTARTERS = {
        void      = "startVoid",
        voidspam  = "startVoidspam",
        sky       = "startSky",
        spin      = "startSpin",
        velocity  = "startVelocity",
        raknet    = "startRaknet",
        invisible = "startInvisible",
    }

    local function shootMurdererFire()
        local victim
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lplr
                and not (F.whitelist and F.whitelist.contains(plr))
                and getIdentity(plr) == "Murderer" then
                victim = plr; break
            end
        end
        if not victim then return false, "no_murderer" end
        local theirCF = targetHitCF(victim.Character)
        if not theirCF then return false, "no_victim_hrp" end

        local remote = findHitRemote()
        if not remote then return false, "no_gun" end

        -- snapshot + stop any active desync so our HRP is at the real
        -- position before the shot. Server-side shooter-position
        -- validation rejects the hit otherwise.
        local restartName
        if F.desync and F.desync.getMode then
            local m = F.desync.getMode()
            if m and m ~= "off" and SHOOT_DESYNC_RESTARTERS[m] then
                restartName = SHOOT_DESYNC_RESTARTERS[m]
                F.desync.stop()
            end
        end

        -- Now read myPos AFTER the desync stopped (HRP is back at the
        -- real position) so arg2 matches what the server has for us.
        local myPos = myPosCFrame()
        if not myPos then
            if restartName and F.desync and F.desync[restartName] then
                pcall(function() F.desync[restartName]() end)
            end
            return false, "no_my_hrp"
        end

        -- Canonical payload from MM2 captures:
        --   arg1 = target's HumanoidRootPart CFrame
        --   arg2 = shooter HRP position with IDENTITY rotation
        --          (CFrame.new(x, y, z) with default basis)
        local ok, err = pcall(function() remote:FireServer(theirCF, myPos) end)
        if not ok then
            print("[cclosure.vip] Shoot FireServer error:", err)
        end

        -- restart desync after a brief grace period so the shot has
        -- time to register server-side before we vanish again
        if restartName then
            task.delay(0.2, function()
                if F.desync and F.desync[restartName] then
                    pcall(function() F.desync[restartName]() end)
                end
            end)
        end
        return true
    end

    -- ---------- Auto-pickup ----------
    local autoActive = false
    local autoThread

    local function autoStart()
        if autoActive then return end
        autoActive = true
        if autoThread then pcall(task.cancel, autoThread) end
        autoThread = task.spawn(function()
            while autoActive do
                local drop = findGunDrop()
                -- skip pickup if we're the murderer (have Knife) - we
                -- don't want to grab the sheriff's gun and reveal our
                -- identity, and we can't use it anyway
                local myIdentity = getIdentity(lplr)
                if drop and myIdentity ~= "Murderer" then
                    pickupOnce()
                    task.wait(2)
                else
                    task.wait(0.5)
                end
            end
        end)
    end

    local function autoStop()
        autoActive = false
        if autoThread then pcall(task.cancel, autoThread); autoThread = nil end
    end

    return {
        identityEsp = {
            start    = identityStart,
            stop     = identityStop,
            isActive = function() return identityActive end,
        },
        pickupGun = {
            fire = pickupOnce,
        },
        autoPickupGun = {
            start    = autoStart,
            stop     = autoStop,
            isActive = function() return autoActive end,
        },
        dropEsp = {
            start    = dropEspStart,
            stop     = dropEspStop,
            isActive = function() return dropEspActive end,
        },
        triggerMurderer = {
            start    = triggerStart,
            stop     = triggerStop,
            isActive = function() return triggerActive end,
        },
        shootMurderer = {
            fire = shootMurdererFire,
        },
    }
end)()

-- ============================================================
--  GAMES: MATCH THE CARDS!  (place id 138397085393482)
-- ============================================================
--  Detects which table the local player is sitting at by walking
--    Humanoid.SeatPart -> ChairN -> Chairs -> Games["N"]
--  and exposes two card-reveal modes against that table's Cards
--  folder:
--    peek     - hover-only flip with a configurable "stay flipped"
--               delay after the mouse leaves the card. Restores the
--               original rotation on timer expiry.
--    showAll  - constantly flip every card in the table face-up.
--               Restores all cards when toggled off.
--
--  Mutually exclusive at runtime: starting showAll disables peek
--  (and vice versa) since they fight for control of the cards.
-- ============================================================
F.games.matchTheCards = (function()
    local UserInputService = game:GetService("UserInputService")

    local peekRot = CFrame.Angles(0, math.rad(90), 0)

    local function myTable()
        local c = lplr.Character; if not c then return nil end
        local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return nil end
        local seat = hum.SeatPart; if not seat then return nil end
        local chair = seat.Parent
        local chairs = chair and chair.Parent
        if not chairs or chairs.Name ~= "Chairs" then return nil end
        return chairs.Parent  -- Games["N"]
    end

    -- Already-matched cards are recolored to RGB(17, 255, 17) by the
    -- game. Skip them in both modes so we don't pointlessly re-flip
    -- cards that are already revealed correct.
    local CORRECT_R, CORRECT_G, CORRECT_B = 17 / 255, 255 / 255, 17 / 255
    local COLOR_EPS = 0.02  -- forgive minor float drift from the game
    local function isCorrect(part)
        local col = part.Color
        return math.abs(col.R - CORRECT_R) < COLOR_EPS
           and math.abs(col.G - CORRECT_G) < COLOR_EPS
           and math.abs(col.B - CORRECT_B) < COLOR_EPS
    end

    -- ---- PEEK MODE (hover + delay) ----
    local peekActive = false
    local peekConn
    -- peeking[part] = { savedRot = CFrame, restoreAt = number | math.huge }
    local peeking = {}
    local STAY_TIME = 3
    local hovered = nil

    local function flipBack(part, rot)
        if part and part.Parent and rot then
            part.CFrame = CFrame.new(part.Position) * rot
        end
    end

    local function flipUp(part)
        if peeking[part] then
            peeking[part].restoreAt = math.huge
            return
        end
        peeking[part] = {
            savedRot  = part.CFrame - part.CFrame.Position,
            restoreAt = math.huge,
        }
        part.CFrame = CFrame.new(part.Position) * peekRot
    end

    local function peekStart()
        if peekActive then return end
        peekActive = true
        if peekConn then peekConn:Disconnect() end
        peekConn = RunService.RenderStepped:Connect(function()
            if not peekActive then return end
            local mouse = lplr:GetMouse()
            local tbl   = myTable()
            local cards = tbl and tbl:FindFirstChild("Cards")
            local t     = mouse.Target
            -- Force every matched (green) card to stay flipped face-up
            -- every frame. They never enter peeking[] - we just rewrite
            -- their CFrame and leave them alone.
            if cards then
                for _, p in ipairs(cards:GetDescendants()) do
                    if p:IsA("BasePart") and isCorrect(p) then
                        p.CFrame = CFrame.new(p.Position) * peekRot
                    end
                end
            end

            -- Skip cards that are already matched for the hover peek path
            -- (they're already face-up via the loop above; no need to
            -- enter peeking/restore-timer state).
            local isCard = cards and t and t:IsA("BasePart") and t:IsDescendantOf(cards) and not isCorrect(t)

            if isCard then
                if hovered ~= t then
                    if hovered and peeking[hovered] then
                        peeking[hovered].restoreAt = tick() + STAY_TIME
                    end
                    hovered = t
                    flipUp(t)
                end
            else
                if hovered and peeking[hovered] then
                    peeking[hovered].restoreAt = tick() + STAY_TIME
                end
                hovered = nil
            end

            local now = tick()
            for part, info in pairs(peeking) do
                if now >= info.restoreAt then
                    flipBack(part, info.savedRot)
                    peeking[part] = nil
                end
            end
        end)
    end

    local function peekStop()
        peekActive = false
        if peekConn then peekConn:Disconnect(); peekConn = nil end
        -- restore any cards still face-up
        for part, info in pairs(peeking) do
            flipBack(part, info.savedRot)
        end
        peeking = {}
        hovered = nil
    end

    -- ---- SHOW ALL MODE ----
    local showAllActive = false
    local showConn
    -- shown[part] = savedRot. We snapshot on first sight and restore on stop.
    local shown = {}

    local function showAllStart()
        if showAllActive then return end
        showAllActive = true
        if showConn then showConn:Disconnect() end
        showConn = RunService.Heartbeat:Connect(function()
            if not showAllActive then return end
            local tbl = myTable()
            local cards = tbl and tbl:FindFirstChild("Cards")
            if not cards then return end
            for _, part in ipairs(cards:GetDescendants()) do
                if part:IsA("BasePart") then
                    if isCorrect(part) then
                        -- Matched cards: force face-up but don't snapshot.
                        -- We never want to "restore" their original
                        -- rotation - they're done, leave them flipped.
                        part.CFrame = CFrame.new(part.Position) * peekRot
                    else
                        if not shown[part] then
                            shown[part] = part.CFrame - part.CFrame.Position
                        end
                        part.CFrame = CFrame.new(part.Position) * peekRot
                    end
                end
            end
        end)
    end

    local function showAllStop()
        showAllActive = false
        if showConn then showConn:Disconnect(); showConn = nil end
        for part, rot in pairs(shown) do
            flipBack(part, rot)
        end
        shown = {}
    end

    return {
        peek = {
            start    = function() showAllStop(); peekStart() end,
            stop     = peekStop,
            isActive = function() return peekActive end,
            setStayTime = function(n) STAY_TIME = math.clamp(tonumber(n) or 3, 0, 30) end,
            getStayTime = function() return STAY_TIME end,
        },
        showAll = {
            start    = function() peekStop(); showAllStart() end,
            stop     = showAllStop,
            isActive = function() return showAllActive end,
        },
    }
end)()

-- ============================================================
--  GAMES: BLOCKERMAN'S MINESWEEPER  (place id 7871169780)
-- ============================================================
--  Tile model:
--    workspace.Flag.Parts.<child>   one BasePart per tile
--    state per tile:
--      covered  - no NumberGui child, no Model child
--      revealed - has child named "NumberGui" (number inside it)
--      flagged  - has any Model child (auto-inserted on flag)
--      mine     - revealed mine = part.Color flipped to (252,0,0)
--
--  Server-side flag remote:
--    ReplicatedStorage.Events.FlagEvents.PlaceFlag:FireServer(
--      tile, sessionToken, true)
--    sessionToken is minted client-side once per session, the server
--    validates it. We grab it via a __namecall hook on the first
--    flag the user places manually, then reuse it.
-- ============================================================
-- ============================================================
--  GAMES: BMS BULLETS CHALLENGE DEFENDER
-- ============================================================
--  One of Blockerman's Minesweeper's challenges spawns 'Bullet-Part'
--  parts in workspace that you have to dodge. Easier to just delete
--  them as they appear.
-- ============================================================
F.games.bmsBullets = (function()
    local active = false
    local conn, charConn, pollThread
    local killCount = 0

    local function destroyIfBullet(d)
        if not active or not d then return end
        if d.Name == "Bullet-Part" then
            pcall(function() d:Destroy() end)
            killCount = killCount + 1
        end
    end

    local function sweepWorkspace()
        for _, d in ipairs(workspace:GetDescendants()) do
            if not active then return end
            if d.Name == "Bullet-Part" then
                pcall(function() d:Destroy() end)
                killCount = killCount + 1
            end
        end
    end

    -- DescendantAdded sometimes silently drops on respawn / round
    -- transitions on Potassium. The poll loop is the backup that
    -- guarantees bullets get destroyed even if the event listener
    -- never fires.
    local function startPoll()
        if pollThread then pcall(task.cancel, pollThread) end
        pollThread = task.spawn(function()
            while active do
                sweepWorkspace()
                task.wait(0.05)
            end
        end)
    end

    -- Re-attach the event listener on every character respawn since
    -- some games re-parent workspace contents after the character
    -- streams in.
    local function attachListener()
        if conn then conn:Disconnect() end
        conn = workspace.DescendantAdded:Connect(destroyIfBullet)
    end

    return {
        start = function()
            if active then return end
            active = true
            killCount = 0
            attachListener()
            if charConn then charConn:Disconnect() end
            charConn = game:GetService("Players").LocalPlayer.CharacterAdded:Connect(function()
                task.wait(0.2)
                if active then attachListener(); sweepWorkspace() end
            end)
            startPoll()
            sweepWorkspace()
            print("[BMS bullets] enabled - polling every 50ms + DescendantAdded listener")
        end,
        stop = function()
            active = false
            if conn       then conn:Disconnect();     conn       = nil end
            if charConn   then charConn:Disconnect(); charConn   = nil end
            if pollThread then pcall(task.cancel, pollThread); pollThread = nil end
            print(("[BMS bullets] disabled - %d bullets destroyed"):format(killCount))
        end,
        isActive = function() return active end,
        getKills = function() return killCount end,
    }
end)()

F.games.bms = (function()
    local RS = game:GetService("ReplicatedStorage")

    local function getPlaceFlag()
        local ev = RS:FindFirstChild("Events")
        local fe = ev and ev:FindFirstChild("FlagEvents")
        return fe and fe:FindFirstChild("PlaceFlag")
    end

    local function getParts()
        local f = workspace:FindFirstChild("Flag")
        return f and f:FindFirstChild("Parts")
    end

    -- Token capture. Resolve the remote ref once (try immediate, fall
    -- back to deferred WaitForChild) and have the hook do nothing but
    -- a single ref compare against the cached ref.
    local function resolveRefSync()
        local ev = RS:FindFirstChild("Events")
        local fe = ev and ev:FindFirstChild("FlagEvents")
        local pf = fe and fe:FindFirstChild("PlaceFlag")
        if pf then
            getgenv()._BMS_PLACEFLAG_REF = pf
            print("[BMS] resolved PlaceFlag ref:", pf:GetFullName())
            return true
        end
        return false
    end
    if not getgenv()._BMS_PLACEFLAG_REF then
        if not resolveRefSync() then
            task.defer(function()
                local ev = RS:WaitForChild("Events", 30)
                local fe = ev and ev:WaitForChild("FlagEvents", 30)
                local pf = fe and fe:WaitForChild("PlaceFlag", 30)
                if pf then
                    getgenv()._BMS_PLACEFLAG_REF = pf
                    print("[BMS] resolved PlaceFlag ref (deferred):", pf:GetFullName())
                else
                    warn("[BMS] failed to resolve PlaceFlag - Events folder never appeared")
                end
            end)
        end
    end
    if not getgenv()._BMS_HOOK_INSTALLED and hookmetamethod then
        getgenv()._BMS_HOOK_INSTALLED = true
        local _old
        _old = hookmetamethod(game, "__namecall", function(self, ...)
            if self == getgenv()._BMS_PLACEFLAG_REF then
                local _, tok = ...
                if typeof(tok) == "string" and #tok > 8 and getgenv()._BMS_TOKEN ~= tok then
                    getgenv()._BMS_TOKEN = tok
                    print("[BMS] captured token:", tok)
                end
            end
            return _old(self, ...)
        end)
        print("[BMS] __namecall hook installed (hookmetamethod available)")
    elseif not hookmetamethod then
        warn("[BMS] hookmetamethod not available on this executor - use manual token input")
    end

    -- Public helper for manual token entry (UI exposes a textbox).
    local function setManualToken(s)
        s = tostring(s or "")
        if #s > 8 then
            getgenv()._BMS_TOKEN = s
            print("[BMS] manual token set:", s)
            return true
        end
        return false
    end

    -- ---- per-tile helpers ----
    local function tileState(tile)
        for _, ch in ipairs(tile:GetChildren()) do
            if ch:IsA("Model")        then return "flagged"  end
            if ch.Name == "NumberGui" then return "revealed" end
        end
        return "covered"
    end

    local function tileNumber(tile)
        local g = tile:FindFirstChild("NumberGui")
        if not g then return nil end
        for _, d in ipairs(g:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                local n = tonumber(d.Text)
                if n then return n end
            end
        end
    end

    -- ---- neighbor caches ----
    --   neighbors[]         - 8-direction (includes diagonals).
    --                         Used by the DEDUCTION solver since
    --                         minesweeper numbers count diagonal mines.
    --   cardinalNeighbors[] - 4-direction (N/S/E/W only).
    --                         Used by the AUTO-PLAY pathfinder so the
    --                         character never cuts diagonally across
    --                         an unknown tile's corner and falls in.
    local neighbors         = {}
    local cardinalNeighbors = {}
    local neighborsDirty = true
    local cachedPartsCount = 0
    local function ensureNeighbors(allParts)
        if not neighborsDirty and #allParts == cachedPartsCount then return end
        neighborsDirty = false
        cachedPartsCount = #allParts
        neighbors         = {}
        cardinalNeighbors = {}
        if not allParts[1] then return end
        local size = math.max(allParts[1].Size.X, allParts[1].Size.Z)
        local diagR2 = (size * 1.6) ^ 2   -- includes diagonals
        local cardR2 = (size * 1.1) ^ 2   -- 4-direction only
        for _, t in ipairs(allParts) do
            local list8, list4, px, pz = {}, {}, t.Position.X, t.Position.Z
            for _, o in ipairs(allParts) do
                if o ~= t then
                    local dx, dz = o.Position.X - px, o.Position.Z - pz
                    local d2 = dx*dx + dz*dz
                    if d2 < diagR2 then table.insert(list8, o) end
                    if d2 < cardR2 then table.insert(list4, o) end
                end
            end
            neighbors[t]         = list8
            cardinalNeighbors[t] = list4
        end
    end

    -- watch for new tiles in infinite mode
    do
        local parts = getParts()
        if parts then
            parts.ChildAdded:Connect(function() neighborsDirty = true end)
            parts.ChildRemoved:Connect(function() neighborsDirty = true end)
        end
    end

    -- ---- deduction (basic rules + subset reduction) ----
    --
    -- For each revealed number N we get a constraint:
    --   "exactly (N - knownMinesAround) mines exist in this set of
    --   unknown neighbors."
    --
    -- Basic rules:
    --   rule 1: remaining == |unknown|  -> all unknown are mines
    --   rule 2: remaining == 0          -> all unknown are safe
    --
    -- Subset reduction (this is what catches 1-2-1, 1-2-2-1, edge
    -- patterns and a lot of mid-game stuff the basic rules miss):
    --   if constraint A.set is a STRICT subset of constraint B.set,
    --   then B.set \ A.set contains exactly (B.remaining - A.remaining)
    --   mines. From which:
    --     if (B.rem - A.rem) == |B.set \ A.set|  -> all extras are mines
    --     if (B.rem - A.rem) == 0                -> all extras are safe
    --
    -- Both rules + subset reduction are re-applied to fixed point so
    -- newly-discovered mines/safes propagate into the next iteration.
    -- ============================================================
    local function deduce(parts, state)
        local knownMines = {}
        local knownSafes = {}
        local tileProbs  = {}  -- [tile] = mine probability (only filled by tank solver for tiles in small components)

        local function buildConstraints()
            -- Rebuild the constraint list from the current known sets.
            -- Each constraint = { set = {tile=true,...}, list = {tile,...},
            --                     remaining = mines_left, count = #list }
            -- Skip constraints whose unknown set is empty.
            local out = {}
            for _, t in ipairs(parts) do
                if state[t] == "revealed" then
                    local n = tileNumber(t)
                    if n then
                        local nbrs = neighbors[t]
                        if nbrs then
                            local minesIn, set, list = 0, {}, {}
                            for _, nb in ipairs(nbrs) do
                                if knownMines[nb] then
                                    minesIn = minesIn + 1
                                elseif knownSafes[nb] then
                                    -- already safe = ignore from constraint
                                elseif state[nb] == "covered" or state[nb] == "flagged" then
                                    -- "flagged" stays in unknown set; we
                                    -- don't trust user flags.
                                    if not set[nb] then
                                        set[nb] = true
                                        table.insert(list, nb)
                                    end
                                end
                            end
                            if #list > 0 then
                                table.insert(out, {
                                    set = set, list = list,
                                    remaining = n - minesIn,
                                    count = #list,
                                })
                            end
                        end
                    end
                end
            end
            return out
        end

        local function basicPass(constraints)
            local changed = false
            for _, c in ipairs(constraints) do
                -- rule 1
                if c.remaining == c.count then
                    for _, u in ipairs(c.list) do
                        if not knownMines[u] then knownMines[u] = true; changed = true end
                    end
                end
                -- rule 2
                if c.remaining == 0 then
                    for _, u in ipairs(c.list) do
                        if not knownSafes[u] then knownSafes[u] = true; changed = true end
                    end
                end
            end
            return changed
        end

        local function subsetPass(constraints)
            local changed = false
            for i = 1, #constraints do
                local A = constraints[i]
                for j = 1, #constraints do
                    if i ~= j then
                        local B = constraints[j]
                        -- check A.set strictly subset of B.set, A smaller
                        if A.count < B.count then
                            local subset = true
                            for u in pairs(A.set) do
                                if not B.set[u] then subset = false; break end
                            end
                            if subset then
                                local extras = {}
                                for u in pairs(B.set) do
                                    if not A.set[u] then table.insert(extras, u) end
                                end
                                local extraMines = B.remaining - A.remaining
                                if extraMines == #extras and extraMines > 0 then
                                    for _, u in ipairs(extras) do
                                        if not knownMines[u] then
                                            knownMines[u] = true; changed = true
                                        end
                                    end
                                elseif extraMines == 0 then
                                    for _, u in ipairs(extras) do
                                        if not knownSafes[u] then
                                            knownSafes[u] = true; changed = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            return changed
        end

        -- ---- TANK SOLVER (brute-force enumeration) ----
        --
        -- After pattern rules converge, split the remaining constraints
        -- into connected components (constraints linked by shared
        -- unknowns). For each component small enough to brute-force,
        -- enumerate all 2^N mine/safe assignments, keep the valid ones
        -- (satisfy every constraint exactly), then mark any unknown
        -- that's a mine in EVERY valid assignment (definite mine) or
        -- safe in every valid assignment (definite safe).
        --
        -- This catches every named pattern (1>2<1 pinch, T-pattern,
        -- T1-T5 tricks, corner combinations, etc) because they're all
        -- special cases of global constraint satisfaction.
        --
        -- Cap each component at MAX_TANK unknowns (2^N enumerations).
        -- 14 = ~16k iters per component = milliseconds; 18 = ~260k =
        -- borderline. 14 is a safe default. MAX_TANK_TOTAL is a per-
        -- deduce-call budget across ALL components combined - prevents
        -- a board with 10 connected 14-tile blobs from spinning for
        -- ~160k * 10 iters in one tick.
        local MAX_TANK = 14
        local MAX_TANK_TOTAL = 50000
        local function tankPass(cs)
            if #cs == 0 then return false end
            -- union-find groups constraints that share any unknown
            local parent_uf = {}
            local function find(x)
                while parent_uf[x] ~= x do x = parent_uf[x] end
                return x
            end
            local function union(a, b)
                a = find(a); b = find(b)
                if a ~= b then parent_uf[a] = b end
            end
            local allUnk = {}  -- ordered list of all unknown tiles across cs
            local seenU = {}
            for _, c in ipairs(cs) do
                for u in pairs(c.set) do
                    if not seenU[u] then
                        seenU[u] = true
                        parent_uf[u] = u
                        table.insert(allUnk, u)
                    end
                end
            end
            for _, c in ipairs(cs) do
                local prev
                for u in pairs(c.set) do
                    if prev then union(prev, u) end
                    prev = u
                end
            end
            -- group unknowns + constraints by root
            local groupUnk, groupCons = {}, {}
            for _, u in ipairs(allUnk) do
                local r = find(u)
                groupUnk[r] = groupUnk[r] or {}
                table.insert(groupUnk[r], u)
            end
            for _, c in ipairs(cs) do
                local anyU; for u in pairs(c.set) do anyU = u; break end
                if anyU then
                    local r = find(anyU)
                    groupCons[r] = groupCons[r] or {}
                    table.insert(groupCons[r], c)
                end
            end
            local changed = false
            local totalBudget = MAX_TANK_TOTAL
            for root, unknowns in pairs(groupUnk) do
                local n = #unknowns
                if n > 0 and n <= MAX_TANK then
                    local twoN_check = 1
                    for _ = 1, n do twoN_check = twoN_check * 2 end
                    if twoN_check > totalBudget then
                        -- skip this component if it'd blow the per-tick budget
                        -- (still useful: smaller components after still run)
                    else
                    totalBudget = totalBudget - twoN_check
                    local gcs = groupCons[root] or {}
                    -- precompute: idx[tile] = position in unknowns
                    -- cIdx[ci] = list of unknown indices for constraint ci
                    local idx = {}
                    for i = 1, n do idx[unknowns[i]] = i end
                    local cIdx = {}
                    local cRem = {}
                    for ci, c in ipairs(gcs) do
                        local list = {}
                        for u in pairs(c.set) do
                            list[#list + 1] = idx[u]
                        end
                        cIdx[ci] = list
                        cRem[ci] = c.remaining
                    end
                    local mineYes, mineNo = {}, {}
                    for i = 1, n do mineYes[i] = 0; mineNo[i] = 0 end
                    local totalValid = 0
                    local twoN = 1
                    for _ = 1, n do twoN = twoN * 2 end
                    -- assignment vector is 0/1 ints so we can sum directly
                    local assign = table.create and table.create(n, 0) or {}
                    if #assign < n then for i = 1, n do assign[i] = 0 end end
                    for mask = 0, twoN - 1 do
                        local m = mask
                        for i = 1, n do
                            local bit = m % 2
                            assign[i] = bit
                            m = (m - bit) * 0.5
                        end
                        -- check all constraints; early-out on failure
                        local valid = true
                        for ci = 1, #gcs do
                            local list = cIdx[ci]
                            local mc = 0
                            for k = 1, #list do mc = mc + assign[list[k]] end
                            if mc ~= cRem[ci] then valid = false; break end
                        end
                        if valid then
                            totalValid = totalValid + 1
                            for i = 1, n do
                                if assign[i] == 1 then mineYes[i] = mineYes[i] + 1
                                else                   mineNo[i]  = mineNo[i]  + 1 end
                            end
                        end
                    end
                    if totalValid > 0 then
                        for i = 1, n do
                            local u = unknowns[i]
                            if mineYes[i] == totalValid and not knownMines[u] then
                                knownMines[u] = true; changed = true
                            elseif mineNo[i] == totalValid and not knownSafes[u] then
                                knownSafes[u] = true; changed = true
                            else
                                -- partial: record mine probability for
                                -- 50/50 ESP + auto-play guessing
                                tileProbs[u] = mineYes[i] / totalValid
                            end
                        end
                    end
                    end  -- close totalBudget check
                end
            end
            return changed
        end

        -- iterate basic + subset + tank to fixed point.
        for _ = 1, 12 do
            local cs = buildConstraints()
            local c1 = basicPass(cs)
            local c2 = subsetPass(cs)
            local c3 = tankPass(cs)
            if not c1 and not c2 and not c3 then break end
        end

        -- false flags: user flagged it but our deduction says safe
        local falseFlags = {}
        for _, t in ipairs(parts) do
            if state[t] == "flagged" and not knownMines[t] and knownSafes[t] then
                falseFlags[t] = true
            end
        end
        -- prune probs for tiles we now know definitively
        for t in pairs(tileProbs) do
            if knownMines[t] or knownSafes[t] then tileProbs[t] = nil end
        end
        -- Pure 50/50 pairs: constraints with exactly 2 unknowns and 1
        -- mine. Auto-play in guess mode flags one + walks the other in
        -- the same tick (both are equally likely, the choice is
        -- arbitrary; the walked tile reveals safely 50% of the time,
        -- and the flagged tile is correctly marked the other 50%).
        local fiftyPairs = {}
        do
            local seen = {}
            for _, c in ipairs(buildConstraints()) do
                if c.count == 2 and c.remaining == 1 then
                    -- dedupe by sorted-pair key
                    local a, b = c.list[1], c.list[2]
                    local key = (tostring(a) < tostring(b))
                        and (tostring(a) .. "|" .. tostring(b))
                        or  (tostring(b) .. "|" .. tostring(a))
                    if not seen[key] then
                        seen[key] = true
                        table.insert(fiftyPairs, { a, b })
                    end
                end
            end
        end
        return knownMines, knownSafes, falseFlags, tileProbs, fiftyPairs
    end

    -- ---- range filter ----
    local function inRange(tile, originPos, rangeSq)
        local dx = tile.Position.X - originPos.X
        local dy = tile.Position.Y - originPos.Y
        local dz = tile.Position.Z - originPos.Z
        return (dx*dx + dy*dy + dz*dz) < rangeSq
    end

    local function myPos()
        local c = lplr.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        return hrp and hrp.Position or Vector3.zero
    end

    -- ---- ESP (SurfaceGui-based, no per-scene cap) ----
    --
    -- Highlight instances have a soft cap (~31 active before they
    -- silently stop rendering). Late-game with 80+ flagged tiles
    -- caused ESP to vanish. Switching to a SurfaceGui parented to
    -- each tile (Top face) - it's just a colored Frame + UIStroke,
    -- no engine cap, no scene-wide cost.
    local surfaces = {}  -- [tile] = SurfaceGui (cached)
    local espActive = false
    local espRange = 80
    local espShowSafes = false
    local espShowWarnings = true
    local espThread

    local function ensureSurface(tile)
        local sg = surfaces[tile]
        if sg and sg.Parent then return sg end
        sg = Instance.new("SurfaceGui")
        sg.Name              = "_BMS_ESP"
        sg.Face              = Enum.NormalId.Top
        sg.AlwaysOnTop       = true
        sg.LightInfluence    = 0
        sg.SizingMode        = Enum.SurfaceGuiSizingMode.PixelsPerStud
        sg.PixelsPerStud     = 50
        sg.Adornee           = tile
        sg.Parent            = tile

        local frame = Instance.new("Frame")
        frame.Name                   = "Fill"
        frame.Size                   = UDim2.fromScale(1, 1)
        frame.BackgroundTransparency = 0.4
        frame.BorderSizePixel        = 0
        frame.Parent                 = sg

        local stroke = Instance.new("UIStroke")
        stroke.Thickness    = 3
        stroke.Transparency = 0
        stroke.Parent       = frame

        surfaces[tile] = sg
        return sg
    end

    local function setColor(tile, color)
        local sg = ensureSurface(tile)
        local fr = sg:FindFirstChild("Fill")
        if fr then
            fr.BackgroundColor3 = color
            local st = fr:FindFirstChildOfClass("UIStroke")
            if st then st.Color = color end
        end
        sg.Enabled = true
    end

    local function clearAllHl()
        for _, sg in pairs(surfaces) do if sg then sg.Enabled = false end end
    end

    -- All ESP colors are user-settable via F.games.bms.esp.set*Color
    local MINE_COLOR  = Color3.fromRGB(255, 40,  40)
    local SAFE_COLOR  = Color3.fromRGB(40,  220, 80)
    local WARN_COLOR  = Color3.fromRGB(255, 0,   200)  -- magenta: doesn't clash with heatmap green->yellow->red
    local FIFTY_COLOR = Color3.fromRGB(60,  140, 255)
    local espShowFifties = true
    local espHeatmap     = false  -- color every covered tile by mine probability

    -- gradient 0% -> 50% -> 100% maps to green -> yellow -> red
    local function probToColor(p)
        if p <= 0.5 then
            local t = p / 0.5  -- 0..1
            return Color3.new(t, 1, 0)  -- green (0,1,0) -> yellow (1,1,0)
        else
            local t = (p - 0.5) / 0.5  -- 0..1
            return Color3.new(1, 1 - t, 0)  -- yellow (1,1,0) -> red (1,0,0)
        end
    end

    -- Per-tick cache so we only re-deduce when state actually changed.
    -- Cheap signature: count of covered/revealed/flagged. If counts
    -- match the prior tick the constraints are the same -> reuse the
    -- prior mines/safes/falseFlags result and just re-render. This is
    -- the dominant late-game lag fix: skip the O(C^2 * iters) deduce
    -- on every tick when nothing changed.
    local _lastSig, _lastResult = nil, nil

    local function espTick()
        local parts = getParts()
        if not parts then clearAllHl(); return end
        local all = parts:GetChildren()
        ensureNeighbors(all)
        local state = {}
        local cov, rev, flg = 0, 0, 0
        for _, t in ipairs(all) do
            local s = tileState(t)
            state[t] = s
            if     s == "covered"  then cov = cov + 1
            elseif s == "revealed" then rev = rev + 1
            elseif s == "flagged"  then flg = flg + 1 end
        end
        local sig = cov * 1e6 + rev * 1000 + flg
        local mines, safes, falseFlags
        local probs
        if _lastSig == sig and _lastResult then
            mines, safes, falseFlags, probs = _lastResult[1], _lastResult[2], _lastResult[3], _lastResult[4]
        else
            local ok, m, s2, ff, pr = pcall(deduce, all, state)
            if not ok then
                warn("[BMS] deduce error:", m)
                mines, safes, falseFlags, probs = {}, {}, {}, {}
            else
                mines, safes, falseFlags, probs = m, s2, ff, pr or {}
            end
            _lastSig    = sig
            _lastResult = { mines, safes, falseFlags, probs }
        end
        -- prune dead surfaces: tiles destroyed between ticks leave
        -- orphan SurfaceGui entries in the table. Iterating thousands
        -- of those per tick would stall ESP late game.
        for tile, sg in pairs(surfaces) do
            if not tile.Parent or not sg.Parent then
                pcall(function() sg:Destroy() end)
                surfaces[tile] = nil
            end
        end
        -- only highlight within range of player
        local origin  = myPos()
        local rangeSq = espRange * espRange
        local seen = {}
        for t in pairs(mines) do
            if inRange(t, origin, rangeSq) then
                seen[t] = true
                setColor(t, MINE_COLOR)
            end
        end
        if espShowSafes then
            for t in pairs(safes) do
                if inRange(t, origin, rangeSq) then
                    seen[t] = true
                    setColor(t, SAFE_COLOR)
                end
            end
        end
        if espShowWarnings then
            for t in pairs(falseFlags) do
                if inRange(t, origin, rangeSq) then
                    seen[t] = true
                    setColor(t, WARN_COLOR)
                end
            end
        end
        -- 50/50 tiles: probability in [0.4, 0.6]. Tank solver only fills
        -- probs for tiles in small connected components (<=14 unknowns).
        if espShowFifties and probs then
            for t, p in pairs(probs) do
                if p >= 0.4 and p <= 0.6 and inRange(t, origin, rangeSq) then
                    -- don't overpaint if already marked (mine/safe/warn win)
                    if not seen[t] then
                        seen[t] = true
                        setColor(t, FIFTY_COLOR)
                    end
                end
            end
        end
        -- Heatmap: paint every uncertain covered tile by its mine prob
        -- (0% green -> 50% yellow -> 100% red). Tank solver only knows
        -- prob for tiles in small (<=14 unknowns) connected components;
        -- larger components don't get heatmapped. Definitely-mine and
        -- definitely-safe tiles are NOT in probs (deduce prunes them)
        -- so they keep their solid red/green from above.
        if espHeatmap and probs then
            for t, p in pairs(probs) do
                if not seen[t] and inRange(t, origin, rangeSq) then
                    seen[t] = true
                    setColor(t, probToColor(p))
                end
            end
        end
        -- hide surfaces not in the visible set
        for tile, sg in pairs(surfaces) do
            if not seen[tile] then sg.Enabled = false end
        end
    end

    local function espStart()
        if espActive then return end
        espActive = true
        if espThread then pcall(task.cancel, espThread) end
        espThread = task.spawn(function()
            while espActive do
                pcall(espTick)
                task.wait(0.1)  -- 10 Hz - smoother than the old 2 Hz
            end
        end)
    end

    local function espStop()
        espActive = false
        if espThread then pcall(task.cancel, espThread); espThread = nil end
        clearAllHl()
    end

    -- ---- legit auto-flag (queued, one at a time) ----
    local flagActive    = false
    local flagDelayMin  = 0.6
    local flagDelayMax  = 1.4
    local flagMissChance = 0   -- 0..100 percent
    local flagRange     = 60
    local flagThread
    -- module-scope so the setters can RESET it. Setting a new delay
    -- value now takes effect immediately instead of waiting for the
    -- OLD cooldown to elapse first.
    local lastFlagAt = 0

    local function flagDelayRoll()
        if flagDelayMin >= flagDelayMax then return flagDelayMin end
        return flagDelayMin + math.random() * (flagDelayMax - flagDelayMin)
    end
    local function flagMissRoll()
        return flagMissChance > 0 and (math.random() * 100 < flagMissChance)
    end
    -- aim-cone filter: only flag tiles within a half-angle from camera
    -- forward. Used by both legit auto-flag and auto-play's flag step.
    local flagAimCone     = false
    local flagAimHalfDeg  = 30
    -- (chain-flag logic removed in v1.13.2 - pick always uses player pos)

    local function inAimCone(tile)
        if not flagAimCone then return true end
        local cam = workspace.CurrentCamera
        if not cam then return true end
        local toTile = tile.Position - cam.CFrame.Position
        if toTile.Magnitude < 0.01 then return true end
        local dot = cam.CFrame.LookVector:Dot(toTile.Unit)
        return dot >= math.cos(math.rad(flagAimHalfDeg))
    end

    local function legitFlagStart()
        if flagActive then return end
        flagActive = true
        if flagThread then pcall(task.cancel, flagThread) end
        flagThread = task.spawn(function()
            while flagActive do
                local token = getgenv()._BMS_TOKEN
                local remote = getPlaceFlag()
                if not token or not remote then
                    task.wait(0.5); continue
                end
                local parts = getParts()
                if not parts then task.wait(0.5); continue end
                local all = parts:GetChildren()
                ensureNeighbors(all)
                local state = {}
                for _, t in ipairs(all) do state[t] = tileState(t) end
                local mines = deduce(all, state)
                -- pick the closest unflagged deduced mine within range
                local origin  = myPos()
                local rangeSq = flagRange * flagRange
                -- Pick the unflagged deduced mine closest to the PLAYER
                -- (within range + aim cone). Simple + predictable - no
                -- last-flagged chaining.
                local best, bestD2 = nil, math.huge
                for t in pairs(mines) do
                    if state[t] ~= "flagged" and inAimCone(t) then
                        local dx = t.Position.X - origin.X
                        local dy = t.Position.Y - origin.Y
                        local dz = t.Position.Z - origin.Z
                        local d2 = dx*dx + dy*dy + dz*dz
                        if d2 < rangeSq and d2 < bestD2 then
                            best, bestD2 = t, d2
                        end
                    end
                end
                if best then
                    -- roll for miss chance (makes flagging look less robotic)
                    if not flagMissRoll() then
                        pcall(function() remote:FireServer(best, token, true) end)
                    end
                    task.wait(flagDelayRoll())
                else
                    task.wait(0.25)  -- nothing to flag right now, idle
                end
            end
        end)
    end

    local function legitFlagStop()
        flagActive = false
        if flagThread then pcall(task.cancel, flagThread); flagThread = nil end
    end

    -- ---- auto-play (walk to safes + flag mines, never step on unknowns) ----
    --
    -- Loop:
    --   1. Deduce mines + safes.
    --   2. If there's an unflagged deduced mine within range, flag it
    --      (one at a time, respecting flagDelay).
    --   3. Otherwise pick the nearest deduced-safe tile that is REACHABLE
    --      via revealed/flagged tiles only (BFS through walkable
    --      neighbors), walk to its closest walkable neighbor, then step
    --      onto the safe tile.
    --   4. If neither flag nor walk has work, idle briefly.
    --
    -- Pathfinding is restricted: only tiles whose state is "revealed"
    -- or "flagged" AND not a deduced mine count as walkable. So we
    -- never accidentally step onto a covered/unknown tile en route.
    local autoActive = false
    local autoThread
    local autoStepDelay = 0.4   -- per-tile MoveTo cap
    local autoGuess     = false -- when stuck, walk to a 50/50 tile

    -- ---- PathfindingService blacklist ----
    -- Each tile gets a PathfindingModifier child. Its Label is one of:
    --   "BMS_Safe"  - revealed (non-mine), flagged (any), or deduced
    --                 covered-safe destination
    --   "BMS_Avoid" - covered+unknown, OR deduced mine
    -- The path is computed with Costs.BMS_Avoid = math.huge, so the
    -- navmesh REFUSES to route over any avoid tile. Better: the path
    -- automatically stays AgentRadius (2 studs) away from any avoid
    -- tile's boundary - that's a hard clearance guarantee, no more
    -- 'pixel touched the covered tile' deaths.
    local PathfindingService = game:GetService("PathfindingService")
    local pfModifiers = {}  -- tile -> modifier instance (cached so we
                            -- don't re-find or re-create per tick)
    local pfLabels    = {}  -- tile -> last-applied label (skip
                            -- redundant property writes)

    local function ensurePfModifier(tile)
        local m = pfModifiers[tile]
        if m and m.Parent == tile then return m end
        m = tile:FindFirstChild("_BMS_PFM")
        if not m then
            m = Instance.new("PathfindingModifier")
            m.Name = "_BMS_PFM"
            m.Parent = tile
        end
        pfModifiers[tile] = m
        return m
    end

    local function updatePfModifiers(parts, state, knownMines, knownSafes)
        for _, t in ipairs(parts) do
            local s = state[t]
            local label
            -- FLAGGED tiles are ALWAYS BMS_Safe. The 'flag protects you'
            -- rule applies regardless of whether deduce thinks the
            -- underlying tile is a mine - that's the entire point of
            -- the flag. Previous version checked knownMines[t] first,
            -- which incorrectly blacklisted any flagged-and-deduced-
            -- mine tile (i.e. the well-flagged mines), so the bot
            -- couldn't walk over them. Fixed by checking state first.
            if s == "flagged" then
                label = "BMS_Safe"
            elseif knownMines[t] then
                label = "BMS_Avoid"
            elseif s == "covered" then
                -- covered-deduced-safe IS the bot's destination, so
                -- those need to be reachable. Other covered = avoid.
                label = knownSafes[t] and "BMS_Safe" or "BMS_Avoid"
            else
                label = "BMS_Safe"  -- revealed non-mine
            end
            if pfLabels[t] ~= label then
                local m = ensurePfModifier(t)
                m.Label = label
                pfLabels[t] = label
            end
        end
    end

    local function computePfPath(startPos, goalPos)
        local path = PathfindingService:CreatePath({
            -- AgentRadius bumped 2 -> 3.5: hard clearance buffer
            -- from every BMS_Avoid tile boundary. Default Roblox
            -- character body is ~1-1.25 stud radius, so 3.5 leaves
            -- ~2.25 studs of body-to-blacklist gap. No 'pixel
            -- touching' the covered tile, even with character
            -- animation overshoot or momentum drift.
            AgentRadius     = 3.5,
            AgentHeight     = 5,
            AgentCanJump    = false,
            -- WaypointSpacing 2.5: not so dense the character is
            -- constantly retargeting (looks robotic), but tight
            -- enough that straight-line MoveTo segments don't
            -- drift off the safe navmesh on curves.
            WaypointSpacing = 2.5,
            Costs = {
                BMS_Avoid = math.huge,
                BMS_Safe  = 1,
            },
        })
        local ok = pcall(function() path:ComputeAsync(startPos, goalPos) end)
        if not ok then return nil end
        if path.Status ~= Enum.PathStatus.Success then return nil end
        return path:GetWaypoints()
    end

    -- ---- path preview ----
    -- Glowing neon segments between consecutive tiles on the path the
    -- bot is about to walk. Parts are pooled (reused across ticks) so
    -- we don't churn Instance.new every iteration.
    local pathPreview      = false
    local pathPreviewColor = Color3.fromRGB(0, 200, 255)
    local pathSegments     = {}
    local function ensurePathSeg(i)
        local p = pathSegments[i]
        if p and p.Parent then return p end
        p = Instance.new("Part")
        p.Anchored     = true
        p.CanCollide   = false
        p.CanTouch     = false
        p.CanQuery     = false
        p.CastShadow   = false
        p.Material     = Enum.Material.Neon
        p.Color        = pathPreviewColor
        p.Size         = Vector3.new(0.25, 0.25, 0.25)
        p.Name         = "_BMS_path_seg"
        p.Parent       = workspace
        pathSegments[i] = p
        return p
    end
    local function hidePathSegments(startIdx)
        for i = startIdx or 1, #pathSegments do
            local p = pathSegments[i]
            if p then p.Transparency = 1 end
        end
    end
    local function clearPathPreview()
        for _, p in ipairs(pathSegments) do
            if p and p.Parent then pcall(function() p:Destroy() end) end
        end
        pathSegments = {}
    end
    -- Draw segments between raw world positions (for PathfindingService
    -- waypoints, which are Vector3s, not tile parts).
    local function drawPathPreviewPositions(positions)
        if not pathPreview or not positions or #positions < 2 then
            hidePathSegments(); return
        end
        for i = 1, #positions - 1 do
            local a, b = positions[i], positions[i + 1]
            local mid  = (a + b) * 0.5
            local diff = b - a
            local len  = diff.Magnitude
            if len < 0.05 then continue end
            local seg = ensurePathSeg(i)
            seg.Color        = pathPreviewColor
            seg.Size         = Vector3.new(0.4, 0.4, len)
            seg.CFrame       = CFrame.new(mid, b)
            seg.Transparency = 0
        end
        hidePathSegments(#positions)
    end

    local function drawPathPreview(tiles)
        if not pathPreview or not tiles or #tiles < 2 then
            hidePathSegments(); return
        end
        for i = 1, #tiles - 1 do
            local ta, tb = tiles[i], tiles[i + 1]
            if not ta or not tb or not ta.Parent or not tb.Parent then break end
            -- Lift the line ABOVE the tile top face. Without this the
            -- segment center sits inside the tile and the neon part is
            -- occluded by the floor mesh - which is exactly the
            -- 'path not visible' symptom.
            local lift = Vector3.new(0, ta.Size.Y * 0.5 + 0.6, 0)
            local a    = ta.Position + lift
            local b    = tb.Position + lift
            local mid  = (a + b) * 0.5
            local diff = b - a
            local len  = diff.Magnitude
            if len < 0.05 then continue end
            local seg  = ensurePathSeg(i)
            seg.Color        = pathPreviewColor
            seg.Size         = Vector3.new(0.4, 0.4, len)
            seg.CFrame       = CFrame.new(mid, b)
            seg.Transparency = 0
        end
        hidePathSegments(#tiles)  -- hide trailing pool entries
    end
    -- target-switch debounce: once the auto-play picks a tile to walk
    -- to, don't switch to a different target for this many seconds even
    -- if a closer safe appears. Prevents jittery target-flipping
    -- between candidate safes when deductions reshuffle mid-walk.
    local autoTargetDebounce = 0.2
    local _lastWalkTarget    = nil
    local _lastWalkTargetAt  = 0

    local function findCurrentTile(allParts, originPos)
        -- Pick the tile closest to player HRP on XZ.
        local best, bestD2 = nil, math.huge
        for _, t in ipairs(allParts) do
            local dx = t.Position.X - originPos.X
            local dz = t.Position.Z - originPos.Z
            local d2 = dx*dx + dz*dz
            if d2 < bestD2 then best, bestD2 = t, d2 end
        end
        return best
    end

    -- CARDINAL-ONLY BFS. No diagonal moves at all.
    --
    -- Why no diagonals: a diagonal sweep from A to D physically
    -- passes through the corner-junction where 4 tiles meet (A, the
    -- two corner tiles B/C, and D). The character body briefly
    -- overlaps all four at the midpoint. Even with strict corner
    -- safety checks, body momentum + Roblox character drift can let
    -- a pixel touch a NEIGHBOUR of one of the corner tiles. If that
    -- neighbour is an unrevealed bomb, game over.
    --
    -- Cardinal-only moves cross exactly ONE tile boundary per step
    -- (the one between cur and nb). The character body stays inside
    -- the cur->nb central corridor and never crosses into any other
    -- tile. As long as both cur and nb are safe (revealed or
    -- flagged), the walk is provably brush-free.
    --
    -- Trade-off: paths are Manhattan-distance instead of Chebyshev,
    -- so ~40% longer on average. Worth it for the safety guarantee.
    local function bfsPath(startTile, goalTile, state, knownMines, knownFalse)
        knownFalse = knownFalse or {}
        if startTile == goalTile then return {} end

        -- Walking ONTO a tile - flagged is OK (flag protects you,
        -- and a cardinal move into a flagged tile crosses just the
        -- one boundary, no other tile is touched).
        local function isWalkable(t)
            local s = state[t]
            if s == "flagged"  then return true end
            if s == "revealed" then return not knownMines[t] end
            return false
        end

        local visited = { [startTile] = true }
        local parent  = {}
        local queue   = { startTile }
        local head    = 1
        while head <= #queue do
            local cur = queue[head]; head = head + 1
            for _, nb in ipairs(cardinalNeighbors[cur] or {}) do
                if not visited[nb] then
                    visited[nb] = true
                    parent[nb]  = cur
                    if nb == goalTile then
                        local path = {}
                        local x = goalTile
                        while x and x ~= startTile do
                            table.insert(path, 1, x)
                            x = parent[x]
                        end
                        return path
                    end
                    if isWalkable(nb) then
                        table.insert(queue, nb)
                    end
                end
            end
        end
        return nil
    end

    -- Pure MoveTo walk. No CFrame snap.
    --
    -- nextTile (optional) - the tile after this one in the path. Used
    -- to widen the reach threshold on straight runs (cardinal BFS
    -- often has multiple cardinal-aligned tiles in a row), so the
    -- character keeps moving instead of decelerating to tile-center.
    local function walkTo(tile, nextTile)
        local c = lplr.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return false end
        local goalPos = tile.Position + Vector3.new(0, hrp.Size.Y * 0.5 + tile.Size.Y * 0.5, 0)
        pcall(function() hum:MoveTo(goalPos) end)

        local reachR
        if not nextTile then
            reachR = 0.6  -- final tile: precise
        else
            local v1x = tile.Position.X - hrp.Position.X
            local v1z = tile.Position.Z - hrp.Position.Z
            local v2x = nextTile.Position.X - tile.Position.X
            local v2z = nextTile.Position.Z - tile.Position.Z
            local m1  = math.sqrt(v1x*v1x + v1z*v1z)
            local m2  = math.sqrt(v2x*v2x + v2z*v2z)
            if m1 > 0.01 and m2 > 0.01 then
                local cosA = (v1x*v2x + v1z*v2z) / (m1 * m2)
                if cosA > 0.85 then
                    -- straight continuation: glide through at ~40%
                    -- of tile width away from center
                    reachR = math.max(1.5, tile.Size.X * 0.4)
                elseif cosA > 0.5 then
                    reachR = math.max(1.2, tile.Size.X * 0.3)
                else
                    reachR = 0.6  -- 90deg cardinal turn: stop close
                end
            else
                reachR = 1.0
            end
        end
        local reachR2 = reachR * reachR
        local waited = 0
        while waited < autoStepDelay and autoActive do
            local dx = hrp.Position.X - goalPos.X
            local dz = hrp.Position.Z - goalPos.Z
            if (dx*dx + dz*dz) < reachR2 then return true end
            RunService.Heartbeat:Wait()
            waited = waited + (1/60)
        end
        return true
    end

    -- Walk a sequence of PathfindingService waypoints. The path was
    -- computed with BMS_Avoid=math.huge AND AgentRadius=3.5, so every
    -- waypoint is on safe ground AND >=3.5 studs clear of any
    -- avoid-tile boundary.
    --
    -- Human-feel: the reach threshold for each waypoint depends on
    -- the angle to the NEXT waypoint:
    --   nearly-straight continuation -> wide threshold (~2.5 studs)
    --     so the character GLIDES through without slowing down. This
    --     was the "robotic" symptom - the old fixed 1-stud threshold
    --     meant the humanoid decelerated to a precise stop at every
    --     1-stud waypoint, even on dead-straight stretches.
    --   moderate turn -> medium threshold so the pivot is smooth
    --   sharp turn / final waypoint -> tight threshold so the corner
    --     is crisp and the character actually arrives at the goal
    local function walkPfWaypoints(waypoints)
        if not waypoints or #waypoints < 2 then return false end
        local finalWp = waypoints[#waypoints]
        for i = 2, #waypoints do
            if not autoActive then return false end
            local wp = waypoints[i]
            local c = lplr.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp then return false end
            -- already at the goal area? skip remaining waypoints
            local fdx = hrp.Position.X - finalWp.Position.X
            local fdz = hrp.Position.Z - finalWp.Position.Z
            if (fdx*fdx + fdz*fdz) < 1.5 then return true end
            pcall(function() hum:MoveTo(wp.Position) end)

            -- compute reach threshold based on turn angle to next wp
            local reachR
            if i == #waypoints then
                reachR = 1.0  -- final: precise landing
            else
                local nextWp = waypoints[i + 1]
                local v1x = wp.Position.X - hrp.Position.X
                local v1z = wp.Position.Z - hrp.Position.Z
                local v2x = nextWp.Position.X - wp.Position.X
                local v2z = nextWp.Position.Z - wp.Position.Z
                local m1  = math.sqrt(v1x*v1x + v1z*v1z)
                local m2  = math.sqrt(v2x*v2x + v2z*v2z)
                if m1 > 0.01 and m2 > 0.01 then
                    local cosA = (v1x*v2x + v1z*v2z) / (m1 * m2)
                    if cosA > 0.85 then
                        reachR = 2.5      -- nearly straight: glide
                    elseif cosA > 0.5 then
                        reachR = 1.7      -- gentle turn
                    else
                        reachR = 1.0      -- sharp turn: be crisp
                    end
                else
                    reachR = 1.5
                end
            end
            local reachR2 = reachR * reachR
            local waited = 0
            while waited < autoStepDelay and autoActive do
                local dx = hrp.Position.X - wp.Position.X
                local dz = hrp.Position.Z - wp.Position.Z
                if (dx*dx + dz*dz) < reachR2 then break end
                RunService.Heartbeat:Wait()
                waited = waited + (1/60)
            end
        end
        return true
    end

    -- Camera setup while auto-play is active:
    --   1. Switch Roblox's Computer movement mode to Follow so the
    --      camera tracks the character's facing direction.
    --   2. Every 1 second, briefly flip CameraType to Scriptable and
    --      write a CFrame with a slight downward pitch (so the user
    --      can see the board). Then flip back to Custom - the Roblox
    --      CameraScript picks up the new orientation as its starting
    --      state. The user can still mouse-look freely in between.
    local _camModeBefore = nil
    local _camTiltThread = nil
    local _camCharConn   = nil
    local _camTiltAngle  = math.rad(-60)  -- 60 degrees down (default)
    local _camTiltOn     = true  -- whether the periodic tilt is enabled

    local function setFollowCam(enable)
        local ok, ugs = pcall(function()
            return UserSettings():GetService("UserGameSettings")
        end)
        if not ok or not ugs then return end
        if enable then
            if _camModeBefore == nil then
                _camModeBefore = ugs.ComputerCameraMovementMode
            end
            pcall(function()
                ugs.ComputerCameraMovementMode = Enum.ComputerCameraMovementMode.Follow
            end)
            if _camTiltThread then pcall(task.cancel, _camTiltThread) end
            _camTiltThread = task.spawn(function()
                while autoActive do
                    if _camTiltOn then
                        local cam = workspace.CurrentCamera
                        if cam then
                            local pos   = cam.CFrame.Position
                            local lookV = cam.CFrame.LookVector
                            local yaw   = math.atan2(-lookV.X, -lookV.Z)
                            pcall(function()
                                local prev = cam.CameraType
                                cam.CameraType = Enum.CameraType.Scriptable
                                cam.CFrame = CFrame.new(pos)
                                    * CFrame.fromOrientation(_camTiltAngle, yaw, 0)
                                task.wait()
                                cam.CameraType = prev
                            end)
                        end
                    end
                    task.wait(1)
                end
            end)

            -- Recover from death: the brief Scriptable flip during tilt
            -- can leave the camera detached if the character respawns
            -- mid-flip. On CharacterAdded, force CameraType back to Custom
            -- + re-bind CameraSubject to the new humanoid.
            if _camCharConn then _camCharConn:Disconnect() end
            _camCharConn = lplr.CharacterAdded:Connect(function(c)
                if not autoActive then return end
                task.wait(0.3)  -- let the new character settle
                local cam = workspace.CurrentCamera
                local hum = c:FindFirstChildOfClass("Humanoid")
                if cam then
                    pcall(function() cam.CameraType = Enum.CameraType.Custom end)
                    if hum then pcall(function() cam.CameraSubject = hum end) end
                end
            end)
        else
            if _camTiltThread then pcall(task.cancel, _camTiltThread); _camTiltThread = nil end
            if _camCharConn   then _camCharConn:Disconnect(); _camCharConn = nil end
            if _camModeBefore ~= nil then
                pcall(function() ugs.ComputerCameraMovementMode = _camModeBefore end)
                _camModeBefore = nil
            end
            -- safety: in case the tilt thread left the camera detached
            local cam = workspace.CurrentCamera
            if cam and cam.CameraType == Enum.CameraType.Scriptable then
                pcall(function() cam.CameraType = Enum.CameraType.Custom end)
                local c = lplr.Character
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                if hum then pcall(function() cam.CameraSubject = hum end) end
            end
        end
    end

    -- ====================================================================
    -- makePlan() - one synchronous tick of "what should the bot do next?".
    -- Handles flag-firing AND target picking AND PF compute. Returns a
    -- job (a table describing one walk) or nil if nothing to do.
    --
    -- Pick rule: ALWAYS the nearest covered-deduced-safe tile by
    -- Euclidean distance to the player. If the nearest isn't reachable
    -- via BFS, try the next nearest, etc. No locked-target debounce -
    -- user explicitly asked for "always nearest".
    --
    -- This is called both synchronously (when there's no pre-planned
    -- job ready) and from inside a coroutine spawned in parallel with
    -- the current walk (so the next plan is ready before the current
    -- walk ends - the source of the "no stops" behaviour).
    -- ====================================================================
    local function makePlan()
        local parts = getParts()
        if not parts then return nil end
        local all = parts:GetChildren()
        ensureNeighbors(all)
        local state = {}
        for _, t in ipairs(all) do state[t] = tileState(t) end
        local mines, safes, falseFlags, probs, fiftyPairs = deduce(all, state)
        falseFlags = falseFlags or {}
        probs      = probs or {}
        fiftyPairs = fiftyPairs or {}

        local origin = myPos()
        local token  = getgenv()._BMS_TOKEN
        local remote = getPlaceFlag()
        local now    = tick()

        -- FLAG: closest unflagged deduced mine (or false-flag to remove)
        -- if the cooldown has elapsed. Non-blocking - we just FireServer
        -- and move on, no wait. The walk happens regardless.
        if token and remote and (now - lastFlagAt) >= flagDelayMin then
            local fb, fbD2 = nil, math.huge
            for t in pairs(mines) do
                if state[t] ~= "flagged" and inAimCone(t) then
                    local dx = t.Position.X - origin.X
                    local dz = t.Position.Z - origin.Z
                    local d2 = dx*dx + dz*dz
                    if d2 < fbD2 then fb, fbD2 = t, d2 end
                end
            end
            for t in pairs(falseFlags) do
                if inAimCone(t) then
                    local dx = t.Position.X - origin.X
                    local dz = t.Position.Z - origin.Z
                    local d2 = dx*dx + dz*dz
                    if d2 < fbD2 then fb, fbD2 = t, d2 end
                end
            end
            if fb then
                if not flagMissRoll() then
                    pcall(function() remote:FireServer(fb, token, true) end)
                end
                lastFlagAt = now + flagDelayRoll() - flagDelayMin
            end
        end

        local startTile = findCurrentTile(all, origin)
        if not startTile then return nil end

        -- PICK: nearest covered-deduced-safe that's BFS-reachable.
        -- Sort candidates by raw Euclidean d^2 to player, then walk
        -- the list trying BFS reach in order. First reachable wins.
        local candidates = {}
        for s in pairs(safes) do
            if state[s] == "covered" then
                local dx = s.Position.X - origin.X
                local dz = s.Position.Z - origin.Z
                table.insert(candidates, { tile = s, d2 = dx*dx + dz*dz })
            end
        end
        table.sort(candidates, function(a, b) return a.d2 < b.d2 end)

        local pick, bfsTiles
        for _, c in ipairs(candidates) do
            if not autoActive then return nil end
            local p = bfsPath(startTile, c.tile, state, mines, falseFlags)
            if p and #p > 0 then
                pick     = c.tile
                bfsTiles = p
                break
            end
        end

        -- GUESS FALLBACK: no certain safes. If autoGuess is on, try
        -- a 50/50 pair or lowest-prob covered tile.
        if not pick and autoGuess then
            for _, pair in ipairs(fiftyPairs) do
                local a, b = pair[1], pair[2]
                if a.Parent and b.Parent
                   and state[a] == "covered" and state[b] == "covered" then
                    local pA = bfsPath(startTile, a, state, mines, falseFlags)
                    local pB = bfsPath(startTile, b, state, mines, falseFlags)
                    local walkT, flagT, ptiles
                    if pA then walkT, flagT, ptiles = a, b, pA
                    elseif pB then walkT, flagT, ptiles = b, a, pB end
                    if walkT and token and remote then
                        pcall(function() remote:FireServer(flagT, token, true) end)
                        lastFlagAt = tick()
                        pick     = walkT
                        bfsTiles = ptiles
                        break
                    end
                end
            end
            if not pick then
                local guesses = {}
                for tile, p in pairs(probs) do
                    if state[tile] == "covered" and p <= 0.55 then
                        table.insert(guesses, { tile = tile, p = p })
                    end
                end
                table.sort(guesses, function(a, b) return a.p < b.p end)
                for _, g in ipairs(guesses) do
                    local p = bfsPath(startTile, g.tile, state, mines, falseFlags)
                    if p and #p > 0 then
                        pick     = g.tile
                        bfsTiles = p
                        break
                    end
                end
            end
        end

        if not pick then return nil end

        -- COMPUTE PF PATH. Update the modifier labels first (cheap -
        -- only changed tiles get rewritten), then ComputeAsync.
        updatePfModifiers(all, state, mines, safes)
        local hrp = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
        local startPos = hrp and hrp.Position or origin
        local goalPos  = pick.Position + Vector3.new(0, pick.Size.Y * 0.5 + 3, 0)
        local pfWp = computePfPath(startPos, goalPos)
        if pfWp and #pfWp >= 2 then
            return { kind = "pf", waypoints = pfWp, tile = pick, mines = mines }
        end
        -- PF failed - fall back to BFS waypoints (less precise but still
        -- safe via the cardinal-only rule).
        return {
            kind      = "bfs",
            tiles     = bfsTiles,
            tile      = pick,
            startTile = startTile,
            mines     = mines,
        }
    end

    -- Walk one job. Synchronous - returns when the walk finishes (or is
    -- aborted by autoActive going false).
    local function walkJob(job)
        if not job then return end
        if job.kind == "pf" then
            local poss = {}
            for _, w in ipairs(job.waypoints) do
                table.insert(poss, w.Position + Vector3.new(0, 0.6, 0))
            end
            drawPathPreviewPositions(poss)
            walkPfWaypoints(job.waypoints)
        elseif job.kind == "bfs" then
            local seq = job.tiles
            drawPathPreview({ job.startTile, table.unpack(seq) })
            local lastIdx = #seq
            for stepIdx, step in ipairs(seq) do
                if not autoActive then return end
                local s = tileState(step)
                if stepIdx < lastIdx then
                    if s == "flagged" then
                        -- ok, flag protects
                    elseif s ~= "revealed" or (job.mines and job.mines[step]) then
                        return
                    end
                else
                    if job.mines and job.mines[step] then return end
                end
                walkTo(step, seq[stepIdx + 1])
            end
        end
    end

    local function autoPlayStart()
        if autoActive then return end
        autoActive = true
        setFollowCam(true)
        if autoThread then pcall(task.cancel, autoThread) end
        lastFlagAt = 0  -- reset cooldown so a fresh autoplay session starts immediately

        autoThread = task.spawn(function()
            -- The continuous-motion architecture:
            --   currentJob - the job we're walking RIGHT NOW
            --   plannedJob - the NEXT job, computed in parallel by a
            --                spawned coroutine while we walk currentJob
            -- When the current walk finishes, we swap plannedJob into
            -- currentJob immediately and start walking - no
            -- deduce/ComputeAsync delay between targets, no stops.
            local currentJob = nil
            local plannedJob = nil

            while autoActive do
                -- ensure we have a job to walk
                if not currentJob then
                    if plannedJob then
                        currentJob = plannedJob
                        plannedJob = nil
                    else
                        currentJob = makePlan()
                    end
                    if not currentJob then
                        task.wait(0.1)  -- nothing to do this tick
                        continue
                    end
                end

                -- start the planner for the NEXT job, in parallel
                -- with the upcoming walk. Wait for the current goal to
                -- reveal (so the next deduce sees the new state) then
                -- call makePlan. By the time the current walk ends,
                -- plannedJob should be ready.
                plannedJob = nil
                local plannerGoal = currentJob.tile
                task.spawn(function()
                    local waited = 0
                    while autoActive and waited < 5 do
                        if not plannerGoal.Parent then break end
                        if tileState(plannerGoal) ~= "covered" then break end
                        task.wait(0.05)
                        waited = waited + 0.05
                    end
                    if autoActive then
                        plannedJob = makePlan()
                    end
                end)

                walkJob(currentJob)
                currentJob = nil
                -- loop iterates: plannedJob is (usually) ready already
            end
        end)
    end


    local function autoPlayStop()
        autoActive = false
        if autoThread then pcall(task.cancel, autoThread); autoThread = nil end
        clearPathPreview()
        setFollowCam(false)
    end

    return {
        esp = {
            start    = espStart,
            stop     = espStop,
            isActive = function() return espActive end,
            setRange         = function(n) espRange         = math.clamp(tonumber(n) or 80,  10, 1000) end,
            setShowSafes     = function(v) espShowSafes     = v == true end,
            setShowWarnings  = function(v) espShowWarnings  = v == true end,
            setShowFifties   = function(v) espShowFifties   = v == true end,
            setHeatmap       = function(v) espHeatmap       = v == true end,
            setMineColor     = function(c) if typeof(c) == "Color3" then MINE_COLOR  = c end end,
            setSafeColor     = function(c) if typeof(c) == "Color3" then SAFE_COLOR  = c end end,
            setWarnColor     = function(c) if typeof(c) == "Color3" then WARN_COLOR  = c end end,
            setFiftyColor    = function(c) if typeof(c) == "Color3" then FIFTY_COLOR = c end end,
            getMineColor     = function() return MINE_COLOR end,
            getSafeColor     = function() return SAFE_COLOR end,
            getWarnColor     = function() return WARN_COLOR end,
            getFiftyColor    = function() return FIFTY_COLOR end,
        },
        legitFlag = {
            start    = legitFlagStart,
            stop     = legitFlagStop,
            isActive = function() return flagActive end,
            -- Setters reset lastFlagAt so the new value takes effect on
            -- the very next tick instead of waiting for the OLD cooldown
            -- to elapse. That was the 'settings don't feel live' issue.
            setDelayMin   = function(n) flagDelayMin   = math.clamp(tonumber(n) or 0.6, 0.05, 10); lastFlagAt = 0 end,
            setDelayMax   = function(n) flagDelayMax   = math.clamp(tonumber(n) or 1.4, 0.05, 10); lastFlagAt = 0 end,
            setMissChance = function(n) flagMissChance = math.clamp(tonumber(n) or 0,   0,    100) end,
            setRange      = function(n) flagRange = math.clamp(tonumber(n) or 60, 5, 500) end,
            setAimCone    = function(v) flagAimCone = v == true end,
            setAimHalfDeg = function(n) flagAimHalfDeg = math.clamp(tonumber(n) or 30, 1, 180) end,
        },
        autoPlay = {
            start    = function() legitFlagStop(); autoPlayStart() end,
            stop     = autoPlayStop,
            isActive = function() return autoActive end,
            setStepDelay      = function(n) autoStepDelay = math.clamp(tonumber(n) or 0.4, 0.05, 3) end,
            setGuess          = function(v) autoGuess = v == true end,
            setTargetDebounce = function(n) autoTargetDebounce = math.clamp(tonumber(n) or 0.2, 0, 5) end,
            setPathPreview    = function(v) pathPreview = v == true; if not v then hidePathSegments() end end,
            setPathPreviewColor = function(c) if typeof(c) == "Color3" then pathPreviewColor = c end end,
            getPathPreviewColor = function() return pathPreviewColor end,
            -- camera tilt
            setCamTilt        = function(v) _camTiltOn = v == true end,
            setCamTiltAngle   = function(n)
                local deg = math.clamp(tonumber(n) or 60, 0, 90)
                _camTiltAngle = math.rad(-deg)
            end,
        },
        hasToken      = function() return getgenv()._BMS_TOKEN ~= nil end,
        setToken      = setManualToken,
        getToken      = function() return getgenv()._BMS_TOKEN end,
    }
end)()

-- ============================================================
--  MOVEMENT: DESYNC  (multiple spoof methods)
--
--  Shared frame pattern:
--    Heartbeat (after physics):  save real HRP state, write a SPOOFED
--                                state. This replicates to the server.
--    BindToRenderStep / First:   restore real HRP state BEFORE the
--                                camera reads it. Locally we render
--                                normally; server gets the spoofed state.
--
--  Modes:
--    "void"        random point in [VOID_MIN, VOID_MAX] stud cube each
--                  Heartbeat. Server can't hit you, you can't shoot
--                  out either (unless voidspam).
--    "voidspam"    same as void, but our outbound Shoot remote fires
--                  unblock the spoof for ~SHOT_SYNC_MS so the shot
--                  processes at the real position. Lets you shoot
--                  while staying server-uninhittable the rest of time.
--    "spin"        rotate HRP wildly each Heartbeat (random Euler).
--                  Position preserved, just the rotation churns.
--                  Confuses server-side aim prediction without a void
--                  jump.
--    "velocity"    keep CFrame, write Vector3.one * 16384 to
--                  AssemblyLinearVelocity. Server thinks we're moving
--                  at impossible speed -> backtrack rejection on
--                  shooters trying to lead us.
-- ============================================================
F.desync = (function()
    local VOID_MIN     = 5000
    local VOID_MAX     = 20000
    -- Knife Voidspam has its own tighter range so the spoofed
    -- position stays in a smaller cluster (less server detection
    -- + easier to reason about). User specified 5k-10k.
    local VOIDSPAM_MIN = 5000
    local VOIDSPAM_MAX = 10000
    local SHOT_SYNC_MS = 100
    local SPIN_STEP    = 47
    local VEL_MAGNITUDE = 16384
    -- sky desync: how many studs to shove HRP up server-side (X/Z preserved)
    local SKY_HEIGHT   = 5000
    -- invisible desync: tight-radius void TP. Picks a base void point
    -- on each spoof, jitters within INVIS_RADIUS studs of it. Result:
    -- server sees the character clustered in a small area far from
    -- the real position (so it doesn't render for other players),
    -- but the cluster is small enough that the server doesn't
    -- treat the per-tick motion as anti-cheat-worthy "warping".
    local INVIS_BASE_DIST = 1500   -- how far the cluster center is from origin
    local INVIS_RADIUS    = 25     -- jitter radius around the cluster center

    -- shared state in getgenv() so the raknet hook (which is installed
    -- ONCE at module load and survives script re-runs) reads the current
    -- IIFE's active/mode rather than stale upvalues from an old IIFE.
    getgenv()._F_DESYNC_STATE = getgenv()._F_DESYNC_STATE or { active = false, mode = "off" }
    local SHARED = getgenv()._F_DESYNC_STATE

    local active   = false
    local mode     = "off"   -- "void"|"voidspam"|"sky"|"spin"|"velocity"|"raknet"|"invisible"|"off"
    local _invisBase  -- cluster center for invisible mode (picked once per session)
    local realCF, realLV, realAV
    local syncEnd  = 0
    local hbConn
    local RESTORE_BIND = "_F_DESYNC_RESTORE"
    local _spinAngle = 0

    local function randVoidPos()
        local function axis()
            local mag = VOID_MIN + math.random() * (VOID_MAX - VOID_MIN)
            return (math.random() < 0.5) and -mag or mag
        end
        return Vector3.new(axis(), axis(), axis())
    end

    -- compute the spoofed HRP state for the current mode. Caller is
    -- responsible for capturing realCF/realLV/realAV before this runs.
    local function applySpoof(hrp)
        if mode == "void" then
            hrp.CFrame = CFrame.new(randVoidPos())
        elseif mode == "voidspam" then
            -- Tighter range than regular void (VOIDSPAM_MIN..MAX,
            -- default 5k-15k). Inline so we don't touch the shared
            -- randVoidPos() that startVoid uses.
            local function axis()
                local m = VOIDSPAM_MIN + math.random() * (VOIDSPAM_MAX - VOIDSPAM_MIN)
                return (math.random() < 0.5) and -m or m
            end
            hrp.CFrame = CFrame.new(Vector3.new(axis(), axis(), axis()))
        elseif mode == "sky" then
            -- preserve XZ + rotation, push Y up by SKY_HEIGHT. server sees
            -- us floating in the sky directly above our real position.
            local cf = hrp.CFrame
            hrp.CFrame = cf + Vector3.new(0, SKY_HEIGHT, 0)
        elseif mode == "spin" then
            _spinAngle = (_spinAngle + SPIN_STEP) % 360
            hrp.CFrame = hrp.CFrame * CFrame.Angles(
                math.rad(_spinAngle),
                math.rad(_spinAngle * 2),
                math.rad(_spinAngle * 0.5)
            )
        elseif mode == "velocity" then
            -- CFrame untouched - we only spoof the velocity vector
            hrp.AssemblyLinearVelocity = Vector3.new(1, 1, 1) * VEL_MAGNITUDE
        elseif mode == "invisible" then
            -- Tight-radius void cluster. Pick the cluster center once
            -- (a far-away point), then each frame jitter ±INVIS_RADIUS
            -- around it. Looks like a player standing still at a void
            -- coordinate from the server's POV.
            if not _invisBase then
                local function axis()
                    return ((math.random() < 0.5) and -1 or 1) * INVIS_BASE_DIST
                end
                _invisBase = Vector3.new(axis(), axis(), axis())
            end
            local r = INVIS_RADIUS
            local jitter = Vector3.new(
                (math.random() * 2 - 1) * r,
                (math.random() * 2 - 1) * r,
                (math.random() * 2 - 1) * r
            )
            hrp.CFrame = CFrame.new(_invisBase + jitter)
        end
    end

    local function bind()
        if hbConn then hbConn:Disconnect() end
        pcall(function() RunService:UnbindFromRenderStep(RESTORE_BIND) end)

        hbConn = RunService.Heartbeat:Connect(function()
            if not active then return end
            local c = lplr.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            realCF = hrp.CFrame
            realLV = hrp.AssemblyLinearVelocity
            realAV = hrp.AssemblyAngularVelocity
            -- voidspam: pure void desync (random per-frame position)
            -- EXCEPT during the MouseButton1 sync window where we skip
            -- the spoof entirely. syncEnd is written by the input
            -- listener pinned in getgenv() so it survives script reload.
            if mode == "voidspam" then
                local ge = getgenv()._F_DESYNC_SYNC_END or 0
                if tick() < ge then return end
            end
            pcall(function() applySpoof(hrp) end)
        end)

        RunService:BindToRenderStep(
            RESTORE_BIND, Enum.RenderPriority.First.Value,
            function()
                if not active then return end
                local c = lplr.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                if not hrp or not realCF then return end
                pcall(function()
                    hrp.CFrame = realCF
                    if realLV then hrp.AssemblyLinearVelocity  = realLV end
                    if realAV then hrp.AssemblyAngularVelocity = realAV end
                end)
            end
        )
    end

    -- raknet desync: hook outbound packet 0x1B (physics replication) and
    -- corrupt a 4-byte field at offset 1. Resolves raknet lazily because
    -- some executors expose it after script load, not before. Hook is
    -- installed at most ONCE per session, gated by SHARED state so the
    -- IIFE on script reload doesn't stack hooks.
    local function findRaknet()
        local r = rawget(getgenv(), "raknet")
        if r then return r end
        local ok, val = pcall(function() return raknet end)
        if ok and val then return val end
        return nil
    end

    local function ensureRaknetHook()
        if getgenv()._F_DESYNC_RAKNET_INSTALLED then return true end
        local r = findRaknet()
        if not r or not r.add_send_hook then return false end
        getgenv()._F_DESYNC_RAKNET_INSTALLED = true
        -- pin the hook function on getgenv so it can't be garbage-collected
        -- even if the executor's raknet impl doesn't keep a strong ref to it.
        -- Reads SHARED via the always-fresh getgenv() lookup so state changes
        -- by the IIFE on script reload are seen immediately.
        getgenv()._F_DESYNC_RAKNET_FN = function(packet)
            local s = getgenv()._F_DESYNC_STATE
            if not s or not s.active or s.mode ~= "raknet" then return end
            if packet.PacketId == 0x1B then
                -- BLOCK the outbound physics replication packet entirely
                -- instead of corrupting bytes. The previous version wrote
                -- 0xFFFFFFFF at offset 1 of packet.AsBuffer which, on
                -- Potassium, overlapped RakNet's sequence/control bytes
                -- and made the executor's send queue choke - local
                -- movement froze because the engine was waiting for acks
                -- that never came. Blocking is cleaner:
                --   * server stops receiving position updates -> we appear
                --     frozen to other players (the desync we want)
                --   * the rest of the connection (chat, remotes, etc.)
                --     keeps working because RakNet itself is untouched
                --   * local engine still updates our HRP each frame so we
                --     can walk around normally
                -- Try every block API we know about; return false is the
                -- convention most executors use.
                pcall(function() packet:SetCanBeSent(false) end)
                pcall(function() packet:Drop() end)
                pcall(function() packet:Block() end)
                pcall(function() packet:Ignore() end)
                return false
            end
        end
        pcall(function()
            r.add_send_hook(getgenv()._F_DESYNC_RAKNET_FN)
        end)
        return true
    end

    -- watchdog: re-asserts SHARED.active state every 1s AND re-installs the
    -- raknet hook every 10s. Potassium's raknet hooks have been observed to
    -- expire / get cleared after a while - re-calling add_send_hook with our
    -- pinned function refreshes the registration. If the executor dedupes
    -- by fn ref it's a no-op; if it stacks, the duplicate hooks all do the
    -- same idempotent write (write 0xFFFFFFFF at offset 1) so output is
    -- unchanged. The 10s cadence is slow enough to avoid runaway stacking.
    if not getgenv()._F_DESYNC_RAKNET_WATCHDOG then
        getgenv()._F_DESYNC_RAKNET_WATCHDOG = true
        task.spawn(function()
            local lastReinstall = 0
            while true do
                task.wait(1)
                local s = getgenv()._F_DESYNC_STATE
                local want = getgenv()._F_DESYNC_RAKNET_WANTED
                if want and s then
                    -- (a) state re-assert (fast path)
                    if not s.active or s.mode ~= "raknet" then
                        s.active = true
                        s.mode   = "raknet"
                    end
                    -- (b) hook re-install (slow path, every 10s)
                    if tick() - lastReinstall >= 10 then
                        lastReinstall = tick()
                        local r = findRaknet()
                        if r and r.add_send_hook and getgenv()._F_DESYNC_RAKNET_FN then
                            pcall(function()
                                r.add_send_hook(getgenv()._F_DESYNC_RAKNET_FN)
                            end)
                        end
                    end
                end
            end
        end)
    end

    -- voidspam: pure input-based trigger. On MouseButton1 down, set
    -- syncEnd so the Heartbeat skips the spoof for SHOT_SYNC_MS ms.
    -- No namecall hook, no synchronous HRP.CFrame writes per shot -
    -- the previous version did a write inside the namecall closure on
    -- every Shoot fire, which stalled / crashed the engine when
    -- ForceHit's autoshoot fired many shots per second.
    --
    -- Trigger: knife SWING ANIMATION (not MouseButton1). Click-based
    -- triggering doesn't account for ping - the actual server-side
    -- hit registration lines up with the swing animation playing,
    -- which already includes the round-trip latency.
    --
    -- Sync window is a sub-range of the swing animation:
    --   off-from  = anim_start + (START_FRAC * length)
    --   off-until = anim_start + (END_FRAC   * length)
    --
    --   START_FRAC = _F_DESYNC_SHOT_DELAY_MS / 100  (% of anim,
    --                "Start at % of anim" slider, default 40)
    --   END_FRAC   = _F_DESYNC_SHOT_SYNC_MS  / 100  (% of anim,
    --                "End at % of anim"   slider, default 90)
    --
    -- Example: anim length 0.5s, start 40%, end 90%
    --   off from t=0.20s to t=0.45s (relative to anim start)
    local KNIFE_SWING_ANIM_ID = "rbxassetid://15862130681"

    local function _voidspamArmFromAnim(track)
        local L = track.Length
        if not L or L <= 0 then
            -- Length isn't published yet (e.g., first play). Fall
            -- back to assuming a 0.5s anim.
            L = 0.5
        end
        local startFrac = (getgenv()._F_DESYNC_SHOT_DELAY_MS or 40) / 100
        local endFrac   = (getgenv()._F_DESYNC_SHOT_SYNC_MS  or 90) / 100
        startFrac = math.clamp(startFrac, 0, 1)
        endFrac   = math.clamp(endFrac,   0, 1)
        if endFrac < startFrac then endFrac = startFrac end  -- guard
        local startAt = startFrac * L            -- seconds from anim start
        local endAt   = endFrac   * L            -- seconds from anim start
        local hold    = math.max(0, endAt - startAt)

        task.delay(startAt, function()
            local s2 = getgenv()._F_DESYNC_STATE
            if not s2 or not s2.active or s2.mode ~= "voidspam" then return end
            local endTime = tick() + hold
            -- extend SYNC_END if the new end is later; never shrink
            -- (so overlapping swings don't accidentally close the
            -- window early)
            if endTime > (getgenv()._F_DESYNC_SYNC_END or 0) then
                getgenv()._F_DESYNC_SYNC_END = endTime
            end
        end)
    end

    if not getgenv()._F_DESYNC_ANIM_HOOK then
        getgenv()._F_DESYNC_ANIM_HOOK = true
        local connByAnimator = setmetatable({}, { __mode = "k" })

        local function hookAnimator(animator)
            if not animator or connByAnimator[animator] then return end
            connByAnimator[animator] = animator.AnimationPlayed:Connect(function(track)
                local s = getgenv()._F_DESYNC_STATE
                if not s or not s.active or s.mode ~= "voidspam" then return end
                local a = track.Animation
                if not a or a.AnimationId ~= KNIFE_SWING_ANIM_ID then return end
                _voidspamArmFromAnim(track)
            end)
        end

        local function hookChar(char)
            if not char then return end
            local hum = char:WaitForChild("Humanoid", 5); if not hum then return end
            local animator = hum:WaitForChild("Animator", 5)
            hookAnimator(animator)
        end

        if lplr.Character then hookChar(lplr.Character) end
        lplr.CharacterAdded:Connect(hookChar)
    end
    -- mirror SHOT_SYNC_MS into getgenv so the input listener (which is
    -- pinned across reloads) sees the current value
    getgenv()._F_DESYNC_SHOT_SYNC_MS  = SHOT_SYNC_MS
    getgenv()._F_DESYNC_SHOT_DELAY_MS = getgenv()._F_DESYNC_SHOT_DELAY_MS or 40

    -- ============================================================
    --  Server-position marker (lightweight)
    -- ============================================================
    --  Same approach as F.pulseLagswitch's visualizer: ONE Part + ONE
    --  Highlight. No character clone, no Animator, no particles, no
    --  Model. The previous "ghost" - a full :Clone() of the character
    --  with attachments, particle emitters, animated rings, and a
    --  per-frame VFX loop - froze the client for hundreds of ms on
    --  low-end devices and tripped some games' anti-cheat that scans
    --  for new player-shaped Models. This version doesn't.
    --
    --  Made noticeable via: bright cyan neon Part + Highlight visible
    --  through walls + slow transparency pulse driven by tick().
    -- ============================================================
    local ghostPart, ghostHighlight, ghostVfxConn

    local function ghostRemove()
        if ghostVfxConn   then ghostVfxConn:Disconnect();   ghostVfxConn   = nil end
        if ghostHighlight then ghostHighlight:Destroy();    ghostHighlight = nil end
        if ghostPart      then ghostPart:Destroy();         ghostPart      = nil end
    end

    local function ghostCreate(pos)
        ghostRemove()

        ghostPart = Instance.new("Part")
        ghostPart.Name         = "_DesyncServerMarker"
        ghostPart.Anchored     = true
        ghostPart.CanCollide   = false
        ghostPart.CanTouch     = false
        ghostPart.CanQuery     = false
        ghostPart.CastShadow   = false
        ghostPart.Massless     = true
        ghostPart.Material     = Enum.Material.Neon
        ghostPart.Color        = Color3.fromRGB(0, 220, 255)
        ghostPart.Size         = Vector3.new(2, 5, 1)
        ghostPart.Transparency = 0.35
        ghostPart.CFrame       = CFrame.new(pos)
        ghostPart.Parent       = workspace

        ghostHighlight = Instance.new("Highlight")
        ghostHighlight.FillColor           = Color3.fromRGB(0, 220, 255)
        ghostHighlight.OutlineColor        = Color3.fromRGB(255, 255, 255)
        ghostHighlight.FillTransparency    = 0.35
        ghostHighlight.OutlineTransparency = 0
        ghostHighlight.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
        ghostHighlight.Adornee             = ghostPart
        ghostHighlight.Parent              = ghostPart

        -- slow pulse so it's clearly visible without flashing.
        -- Cheap: just sin(tick()) -> transparency on one Part / one Highlight.
        ghostVfxConn = RunService.RenderStepped:Connect(function()
            if not ghostPart or not ghostPart.Parent then return end
            local t = tick() * 4
            ghostPart.Transparency           = 0.20 + 0.15 * (math.sin(t)           * 0.5 + 0.5)
            ghostHighlight.FillTransparency  = 0.20 + 0.20 * (math.sin(t + math.pi) * 0.5 + 0.5)
        end)
    end

    local function startMode(newMode)
        mode = newMode
        active = true
        syncEnd = 0
        SHARED.active = true
        SHARED.mode   = newMode
        -- watchdog flag: tells the periodic re-asserter to keep SHARED in
        -- the raknet state. Cleared on stop or non-raknet mode switch.
        getgenv()._F_DESYNC_RAKNET_WANTED = (newMode == "raknet")
        if newMode == "raknet" then
            if hbConn then hbConn:Disconnect(); hbConn = nil end
            pcall(function() RunService:UnbindFromRenderStep(RESTORE_BIND) end)
            -- build the ghost at the current HRP position so the user
            -- can see where the server thinks they are
            local c = lplr.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            if hrp then ghostCreate(hrp.Position) end
            return
        end
        -- non-raknet mode: tear down any existing ghost
        ghostRemove()
        bind()
    end

    local function stopAll()
        active = false
        SHARED.active = false
        SHARED.mode   = "off"
        getgenv()._F_DESYNC_RAKNET_WANTED = false
        getgenv()._F_DESYNC_SYNC_END      = 0
        -- always remove the ghost on any stop (cheap if it doesn't exist)
        ghostRemove()
        -- We intentionally DO NOT call r.remove_send_hook here. The hook
        -- function early-returns when SHARED.active is false or mode is
        -- not "raknet", so leaving it registered is harmless. Removing
        -- it left _F_DESYNC_RAKNET_INSTALLED == true, so the next
        -- ensureRaknetHook() call skipped re-install and we'd wait up
        -- to 10s for the watchdog re-installer to put it back. That's
        -- the "takes a while to turn on again" lag the user reported.
        if hbConn then hbConn:Disconnect(); hbConn = nil end
        pcall(function() RunService:UnbindFromRenderStep(RESTORE_BIND) end)
        local c = lplr.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if hrp and realCF then
            pcall(function()
                hrp.CFrame = realCF
                if realLV then hrp.AssemblyLinearVelocity  = realLV end
                if realAV then hrp.AssemblyAngularVelocity = realAV end
            end)
        end
        realCF, realLV, realAV = nil, nil, nil
        mode = "off"
    end

    -- ============================================================
    --  Sync window visualizer
    --  When the void spoof is OFF (i.e., tick() < SYNC_END), render
    --  a "VULNERABLE" banner at the top-center of the screen so the
    --  user can see at a glance when they're hittable.
    --  Pure Drawing API - one Text + one filled Square, no GUI.
    -- ============================================================
    local syncVisualEnabled = false
    local syncVisualText, syncVisualBg, syncVisualConn

    local function syncVisualRemove()
        if syncVisualConn then syncVisualConn:Disconnect(); syncVisualConn = nil end
        if syncVisualText then pcall(function() syncVisualText:Remove() end); syncVisualText = nil end
        if syncVisualBg   then pcall(function() syncVisualBg:Remove()   end); syncVisualBg   = nil end
    end

    local function syncVisualCreate()
        if syncVisualText then return end
        if not Drawing or not Drawing.new then return end
        syncVisualBg = Drawing.new("Square")
        syncVisualBg.Visible      = false
        syncVisualBg.Color        = Color3.fromRGB(220, 40, 40)
        syncVisualBg.Filled       = true
        syncVisualBg.Transparency = 0.55
        syncVisualBg.Thickness    = 1

        syncVisualText = Drawing.new("Text")
        syncVisualText.Visible      = false
        syncVisualText.Center       = true
        syncVisualText.Outline      = true
        syncVisualText.OutlineColor = Color3.new(0, 0, 0)
        syncVisualText.Color        = Color3.fromRGB(255, 230, 230)
        syncVisualText.Size         = 22
        syncVisualText.Font         = 2  -- bold
        syncVisualText.Text         = "VULNERABLE"

        syncVisualConn = RunService.RenderStepped:Connect(function()
            if not syncVisualEnabled then
                if syncVisualText then syncVisualText.Visible = false end
                if syncVisualBg   then syncVisualBg.Visible   = false end
                return
            end
            local active = tick() < (getgenv()._F_DESYNC_SYNC_END or 0)
            if active then
                local cam = workspace.CurrentCamera
                local vs  = cam and cam.ViewportSize or Vector2.new(800, 600)
                local cx  = vs.X * 0.5
                local cy  = 60
                local w, h = 200, 30
                syncVisualBg.Position   = Vector2.new(cx - w * 0.5, cy - 4)
                syncVisualBg.Size       = Vector2.new(w, h)
                syncVisualBg.Visible    = true
                syncVisualText.Position = Vector2.new(cx, cy)
                syncVisualText.Visible  = true
            else
                syncVisualText.Visible = false
                syncVisualBg.Visible   = false
            end
        end)
    end

    return {
        -- mode starters - mutually exclusive (calling one auto-stops any
        -- previous mode by re-binding the same Heartbeat)
        startVoid       = function() startMode("void") end,
        startVoidspam   = function() startMode("voidspam") end,
        startSky        = function() startMode("sky") end,
        startSpin       = function() startMode("spin") end,
        startVelocity   = function() startMode("velocity") end,
        startRaknet     = function()
            if not ensureRaknetHook() then return false end
            startMode("raknet")
            return true
        end,
        startInvisible  = function()
            _invisBase = nil  -- fresh cluster center every enable
            startMode("invisible")
        end,
        stop            = stopAll,
        isRaknetAvailable = function() return findRaknet() ~= nil end,
        isActive        = function() return active end,
        getMode         = function() return mode end,
        setRange        = function(minV, maxV)
            VOID_MIN = math.max(100, tonumber(minV) or VOID_MIN)
            VOID_MAX = math.max(VOID_MIN + 1, tonumber(maxV) or VOID_MAX)
        end,
        -- Invisible-mode jitter radius (studs) around the cluster
        -- center. Smaller = tighter, less "warping" perceived by
        -- server anti-cheat; larger = more chaotic position.
        setInvisibleRadius = function(n)
            INVIS_RADIUS = math.clamp(tonumber(n) or 25, 0, 500)
        end,
        getInvisibleRadius = function() return INVIS_RADIUS end,
        -- Now interpreted as "End at % of anim" - the percentage
        -- of the swing animation where the spoof-off window closes.
        setShotSyncMs   = function(n)
            SHOT_SYNC_MS = math.clamp(tonumber(n) or 90, 0, 100)
            getgenv()._F_DESYNC_SHOT_SYNC_MS = SHOT_SYNC_MS
        end,
        -- Delay between MouseButton1 click and when the void spoof
        -- actually turns off (sync window begins). 0 = immediate
        -- (original behavior). Higher values let the user fire
        -- while still spoofed, then drop to real position after N ms.
        -- Now interpreted as "start at % of anim" - what fraction
        -- of the swing animation has played before the spoof goes
        -- off. 40 = spoof off starts at 40% of the swing.
        -- (Slider value is 0-100, used as a percent.)
        setShotDelayMs  = function(n)
            local v = math.clamp(tonumber(n) or 40, 0, 100)
            getgenv()._F_DESYNC_SHOT_DELAY_MS = v
        end,
        getShotDelayMs  = function()
            return getgenv()._F_DESYNC_SHOT_DELAY_MS or 0
        end,
        -- Sync window visualizer: shows a "VULNERABLE" banner at the
        -- top of the screen while the void spoof is currently off
        -- (i.e., tick() < SYNC_END). Pure Drawing API, no GUI.
        setSyncVisualEnabled = function(v)
            syncVisualEnabled = v == true
            if syncVisualEnabled then syncVisualCreate() else syncVisualRemove() end
        end,
        getSyncVisualEnabled = function() return syncVisualEnabled end,
        setSpinSpeed    = function(n)
            SPIN_STEP = math.clamp(tonumber(n) or 47, 1, 360)
        end,
        setVelocityMag  = function(n)
            VEL_MAGNITUDE = math.max(1, tonumber(n) or 16384)
        end,
        setSkyHeight    = function(n)
            SKY_HEIGHT = math.clamp(tonumber(n) or 5000, 50, 100000)
        end,
        -- called by external TP code (_uprightTp etc) so our captured
        -- realCF reflects the new position. without this our next
        -- RenderStepped restore would yank HRP back to where it was
        -- before the user's teleport.
        notifyTeleport  = function(newCF)
            if typeof(newCF) == "CFrame" then
                realCF = newCF
            else
                local c = lplr.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                if hrp then realCF = hrp.CFrame end
            end
        end,
    }
end)()

-- ============================================================
--  PULSE LAGSWITCH
-- ============================================================
--  Selectively blocks outgoing PHYSICS REPLICATION packets
--  (PacketId 0x1B) on a configurable on/off duty cycle. Only
--  character position/velocity is affected - chat, RemoteEvents,
--  Shoot fires, hit registrations, etc. all pass through normally.
--
--  Server sees your position in stuttered bursts (e.g. on 200ms,
--  off 100ms): from its POV you're frozen for 200ms, jump to the
--  new position, frozen again, jump, etc. Combined with movement,
--  this makes you nearly impossible to track for human shooters
--  and silent-aim alike.
--
--  Installs its OWN raknet send_hook independent of F.desync's, so
--  the two can coexist (though combining is weird). Hook is pinned
--  in getgenv so script reload doesn't double-stack.
-- ============================================================
F.pulseLagswitch = (function()
    local PHYSICS_PACKET_ID = 0x1B
    local active = false
    local onMs   = 200   -- ms in the blocked phase
    local offMs  = 100   -- ms in the released phase
    local pulseTask

    -- Live flag the send_hook reads. On getgenv so reload-time
    -- module re-creation doesn't strand the hook reading a stale
    -- upvalue.
    getgenv()._F_PLS_BLOCKING = getgenv()._F_PLS_BLOCKING or false
    -- Snapshot of HRP.Position taken at the moment a blocked phase
    -- begins. Approximates the position the server has stored.
    getgenv()._F_PLS_LAST_SERVER_POS = getgenv()._F_PLS_LAST_SERVER_POS or nil

    local function findRaknet()
        local r = rawget(getgenv(), "raknet")
        if r then return r end
        local ok, val = pcall(function() return raknet end)
        if ok and val then return val end
        return nil
    end

    local function ensureHook()
        if getgenv()._F_PLS_HOOKED then return true end
        local r = findRaknet()
        if not r or not r.add_send_hook then return false end
        getgenv()._F_PLS_HOOKED = true
        getgenv()._F_PLS_FN = function(packet)
            if not getgenv()._F_PLS_BLOCKING then return end
            if packet.PacketId ~= PHYSICS_PACKET_ID then return end
            -- block physics packet only; everything else passes through
            pcall(function() packet:SetCanBeSent(false) end)
            pcall(function() packet:Drop() end)
            pcall(function() packet:Block() end)
            pcall(function() packet:Ignore() end)
            return false
        end
        pcall(function() r.add_send_hook(getgenv()._F_PLS_FN) end)
        return true
    end

    -- ---------------- VISUALIZER ----------------
    -- Lightweight server-position marker. Just ONE Part + ONE Highlight,
    -- no character clone, no Animator, no particles, no per-frame
    -- animations.
    --
    -- The existing raknet-desync ghost was a full character clone with
    -- a humanoid, attachments, particle emitters, animated rings, and
    -- a per-frame render loop. On low-end devices and in games that
    -- scan for new Models (anti-cheat), spawning that clone could
    -- freeze the client for hundreds of ms - which is what the user
    -- was hitting. This version sidesteps all of that.
    --
    -- Behavior: only visible during BLOCKED phases (when server's
    -- position has actually diverged from yours). Pulses with the
    -- lagswitch rhythm. Visible through walls via Highlight at
    -- AlwaysOnTop depth mode.
    local visualEnabled = false
    local visualPart, visualHighlight, visualConn

    local function visualRemove()
        if visualConn      then visualConn:Disconnect();   visualConn      = nil end
        if visualHighlight then visualHighlight:Destroy(); visualHighlight = nil end
        if visualPart      then visualPart:Destroy();      visualPart      = nil end
    end

    local function visualCreate()
        if visualPart and visualPart.Parent then return end
        visualRemove()  -- clear any stale refs

        visualPart = Instance.new("Part")
        visualPart.Name         = "_PulseLagswitchVisual"
        visualPart.Anchored     = true
        visualPart.CanCollide   = false
        visualPart.CanTouch     = false
        visualPart.CanQuery     = false
        visualPart.CastShadow   = false
        visualPart.Massless     = true
        visualPart.Material     = Enum.Material.Neon
        visualPart.Color        = Color3.fromRGB(0, 220, 255)  -- bright cyan
        visualPart.Size         = Vector3.new(2, 5, 1)
        visualPart.Transparency = 1  -- hidden until first blocked phase
        visualPart.Parent       = workspace

        visualHighlight = Instance.new("Highlight")
        visualHighlight.FillColor           = Color3.fromRGB(0, 220, 255)
        visualHighlight.OutlineColor        = Color3.fromRGB(255, 255, 255)
        visualHighlight.FillTransparency    = 0.35
        visualHighlight.OutlineTransparency = 0
        visualHighlight.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
        visualHighlight.Adornee             = visualPart
        visualHighlight.Enabled             = false
        visualHighlight.Parent              = visualPart

        if visualConn then visualConn:Disconnect() end
        visualConn = RunService.RenderStepped:Connect(function()
            if not visualPart or not visualPart.Parent then return end
            local blocking = getgenv()._F_PLS_BLOCKING
            local pos      = getgenv()._F_PLS_LAST_SERVER_POS
            if blocking and pos then
                -- show marker at server's stored position with a gentle
                -- pulse so it draws the eye but isn't seizure-inducing.
                local pulse = 0.20 + 0.15 * (math.sin(tick() * 4) * 0.5 + 0.5)
                visualPart.CFrame       = CFrame.new(pos)
                visualPart.Transparency = pulse
                if visualHighlight then
                    visualHighlight.Enabled          = true
                    visualHighlight.FillTransparency = 0.20 + 0.20 * (math.sin(tick() * 4) * 0.5 + 0.5)
                end
            else
                -- released: server == real position, no info to show
                visualPart.Transparency = 1
                if visualHighlight then visualHighlight.Enabled = false end
            end
        end)
    end

    local function start()
        if active then return true end
        if not ensureHook() then return false end
        active = true
        if visualEnabled then visualCreate() end
        if pulseTask then pcall(task.cancel, pulseTask); pulseTask = nil end
        pulseTask = task.spawn(function()
            while active do
                -- Snapshot HRP just before entering the blocked phase -
                -- this is approximately the position the server has
                -- stored from our last successful 0x1B packet.
                local c   = lplr.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                if hrp then getgenv()._F_PLS_LAST_SERVER_POS = hrp.Position end

                getgenv()._F_PLS_BLOCKING = true
                task.wait(onMs / 1000)
                if not active then break end
                getgenv()._F_PLS_BLOCKING = false
                task.wait(offMs / 1000)
            end
            getgenv()._F_PLS_BLOCKING = false
        end)
        return true
    end

    local function stop()
        active = false
        getgenv()._F_PLS_BLOCKING = false
        if pulseTask then pcall(task.cancel, pulseTask); pulseTask = nil end
        visualRemove()
    end

    return {
        start    = start,
        stop     = stop,
        toggle   = function() if active then stop() else return start() end end,
        isActive = function() return active end,
        setOnMs  = function(n) onMs  = math.clamp(tonumber(n) or onMs,  10, 60000) end,
        setOffMs = function(n) offMs = math.clamp(tonumber(n) or offMs, 10, 60000) end,
        getOnMs  = function() return onMs  end,
        getOffMs = function() return offMs end,
        isRaknetAvailable = function() return findRaknet() ~= nil end,
        -- visualizer: independent toggle. Cheap (one Part + one Highlight)
        -- so it shouldn't freeze on the games where the raknet ghost did.
        setVisualEnabled = function(v)
            visualEnabled = v == true
            if active then
                if visualEnabled then visualCreate() else visualRemove() end
            end
        end,
        getVisualEnabled = function() return visualEnabled end,
    }
end)()

-- ============================================================
--  WHITELIST  (global, all-features-aware)
-- ============================================================
--  Lookup tested by:
--    * Ragebot targeting (rbGetTarget + rbLockClosest skip
--      whitelisted players entirely)
--    * MM2 shootMurderer + triggerMurderer (skip whitelisted)
--
--  Case-insensitive. Matches by both Name and DisplayName so a user
--  can whitelist either. Stored on getgenv so script reloads keep
--  the list within a session.
-- ============================================================
F.whitelist = (function()
    getgenv()._F_WHITELIST = getgenv()._F_WHITELIST or {}
    local store = getgenv()._F_WHITELIST  -- map: actualName -> true
    -- Rebuild lowercase index from store (in case getgenv survived
    -- a reload).
    local lower = {}
    for n in pairs(store) do lower[n:lower()] = n end

    local function add(name)
        if type(name) ~= "string" or name == "" then return false end
        local k = name:lower()
        if lower[k] then return false end  -- already in
        store[name] = true
        lower[k] = name
        return true
    end

    local function remove(name)
        if type(name) ~= "string" then return false end
        local k = name:lower()
        local actual = lower[k]
        if not actual then return false end
        store[actual] = nil
        lower[k] = nil
        return true
    end

    local function contains(plr)
        if not plr then return false end
        if type(plr) == "string" then
            return lower[plr:lower()] ~= nil
        end
        if typeof(plr) == "Instance" and plr:IsA("Player") then
            if lower[plr.Name:lower()] then return true end
            local dn = plr.DisplayName
            if dn and dn ~= "" and lower[dn:lower()] then return true end
        end
        return false
    end

    local function list()
        local out = {}
        for n in pairs(store) do table.insert(out, n) end
        table.sort(out, function(a, b) return a:lower() < b:lower() end)
        return out
    end

    local function clear()
        for k in pairs(store) do store[k] = nil end
        for k in pairs(lower) do lower[k] = nil end
    end

    return {
        add      = add,
        remove   = remove,
        contains = contains,
        list     = list,
        clear    = clear,
    }
end)()

-- bulk teardown (call this when your GUI closes)
F.disableAll = function()
    stopFly(); stopCframeSpeed(); stopWalkspeed(); stopJumpPower(); stopBhop(); stopInfJump(); stopForceJump(); stopAntiAfk()
    stopClickTp(); stopAutoRe(); F.autoEquip.stop(); F.autoWeaponSwitch.stop()
    F.games.hoodCustoms.antiAfkTag.stop(); F.games.hoodCustoms.forceAfkTag.stop()
    F.games.hoodCustoms.autoStomp.stop()
    F.games.hoodCustoms.autoReload.stop(); F.games.hoodCustoms.godmode.stop()
    F.games.hoodCustoms.forceHit.stop()
    F.games.hoodCustoms.knifeReach.stop()
    if F.games.hoodCustoms.knifeBot then
        F.games.hoodCustoms.knifeBot.attach.stop()
        F.games.hoodCustoms.knifeBot.autoEquip.stop()
    end
    if F.games.mm2 then
        F.games.mm2.identityEsp.stop()
        F.games.mm2.autoPickupGun.stop()
        F.games.mm2.dropEsp.stop()
        F.games.mm2.triggerMurderer.stop()
    end
    if F.desync then F.desync.stop() end
    if F.pulseLagswitch then F.pulseLagswitch.stop() end
    if F.antiFling then F.antiFling.stop() end
    if F.rocketJump and F.rocketJump.stop then F.rocketJump.stop() end
    if F.prompts then
        if F.prompts.instantActivation then F.prompts.instantActivation.stop() end
        if F.prompts.unlimitedRange    then F.prompts.unlimitedRange.stop()    end
        if F.prompts.throughWalls      then F.prompts.throughWalls.stop()      end
        if F.prompts.autoFire          then F.prompts.autoFire.stop()          end
    end
    if F.forceChat and F.forceChat.stop then F.forceChat.stop() end
    stopNoclip(); stopFullbright(); stopFreecam()
    stopZoom(); stopSpin(); stopFlip(); stopTilt(); stopBackwards(); stopIce()
    if F.stickyEmote then F.stickyEmote.stop() end
    AimbotSettings.Enabled=false; CamLockSettings.Enabled=false
    TrigSettings.Enabled=false
    RageSettings.SilentForce=false; RageSettings.AutoShoot=false
    RageSettings.FaceTarget=false; RageSettings.Orbit=false
    RageSettings.CamSnap=false; RageSettings.SpeedPanic=false
    EspSettings.Enabled=false; stopEspRender()
end

return F
