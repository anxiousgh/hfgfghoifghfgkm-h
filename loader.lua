-- ============================================================
--  cclosure.vip   //   @vampire   //   LinoriaLib build
--  executor: Potassium
-- ============================================================

local F = loadstring(game:HttpGet("https://raw.githubusercontent.com/anxiousgh/hfgfghoifghfgkm-h/main/functions.lua"))()

local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

-- Patch: LinoriaLib button labels render a hair too low because the font's
-- visual midpoint sits below its line-box center. Shift button labels up by 1px.
do
    local orig = Library.CreateLabel
    if orig then
        Library.CreateLabel = function(self, props, ...)
            local lbl = orig(self, props, ...)
            if lbl and props
                and props.Size    == UDim2.new(1, 0, 1, 0)
                and props.TextSize == 14
                and props.ZIndex   == 6 then
                lbl.Position = UDim2.fromOffset(0, -1)
            end
            return lbl
        end
    end
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
--  one-shot keybind infrastructure
--  fires on press for any KeyPicker registered via bindFireKey, regardless
--  of the picker's mode — so one-shot actions don't visually toggle on/off
-- ============================================================
local _fireKeys = {}
local function bindFireKey(optKey, fn) _fireKeys[optKey] = fn end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if Library and Library.Unloaded then return end
    local kc  = input.KeyCode
    local uit = input.UserInputType
    local function matches(v)
        if v == nil then return false end
        if typeof(v) == "EnumItem" then
            return kc == v or uit == v
        end
        local s = tostring(v)
        if kc and kc ~= Enum.KeyCode.Unknown and kc.Name == s then return true end
        local n = uit and uit.Name or ""
        if (n == "MouseButton1" and s == "MB1")
            or (n == "MouseButton2" and s == "MB2")
            or (n == "MouseButton3" and s == "MB3") then return true end
        return false
    end
    for optKey, fn in pairs(_fireKeys) do
        local opt = Options[optKey]
        if opt and matches(opt.Value) then pcall(fn) end
    end
end)

local Window = Library:CreateWindow({
    Title         = "cclosure.vip | @vampire",
    Center        = true,
    AutoShow      = true,
    TabPadding    = 8,
    MenuFadeTime  = 0.2,
})

local Tabs = {
    Combat        = Window:AddTab("Combat"),
    Ragebot       = Window:AddTab("Ragebot"),
    ESP           = Window:AddTab("ESP"),
    Movement      = Window:AddTab("Movement"),
    Fun           = Window:AddTab("Fun"),
    Players       = Window:AddTab("Players"),
    ["UI Settings"] = Window:AddTab("UI Settings"),
}

-- ============================================================
--  COMBAT TAB  (silent aim / triggerbot / camlock)
-- ============================================================
do
    local Aim = Tabs.Combat:AddLeftGroupbox("Silent Aim")

    local AimEnabledToggle = Aim:AddToggle("AimEnabled", { Text = "Enabled",
        Default = F.aimbot.settings.Enabled, Callback = F.aimbot.setEnabled })
    AimEnabledToggle:AddKeyPicker("AimKey", {
        Default = "MB2", Mode = "Toggle", Text = "Silent aim key",
        SyncToggleState = true, NoUI = false,
    })

    Aim:AddToggle("AimTeamCheck", { Text = "Team check", Default = F.aimbot.settings.TeamCheck,
        Callback = F.aimbot.setTeamCheck })
    Aim:AddToggle("AimVisCheck", { Text = "Visible check", Default = F.aimbot.settings.VisibleCheck,
        Callback = F.aimbot.setVisibleCheck })
    Aim:AddToggle("AimClosestPart", { Text = "Closest bodypart", Default = F.aimbot.settings.ClosestPart,
        Callback = F.aimbot.setClosestPart })

    Aim:AddDropdown("AimHitPart", {
        Values = { "HumanoidRootPart", "Head", "UpperTorso", "Random" },
        Default = F.aimbot.settings.TargetPart, Text = "Hit part",
        Callback = F.aimbot.setHitPart,
    })
    Aim:AddDropdown("AimMethod", {
        Values = { "All", "FindPartOnRay", "FindPartOnRayWithIgnoreList",
                   "FindPartOnRayWithWhitelist", "Mouse.Hit/Target" },
        Default = F.aimbot.settings.Method, Text = "Method",
        Callback = F.aimbot.setMethod,
    })

    Aim:AddSlider("AimFov", { Text = "FOV radius", Default = F.aimbot.settings.FOVRadius,
        Min = 1, Max = 1000, Rounding = 0, Callback = F.aimbot.setFov })
    Aim:AddSlider("AimHitChance", { Text = "Hit chance", Default = F.aimbot.settings.HitChance,
        Min = 0, Max = 100, Rounding = 0, Suffix = "%", Callback = F.aimbot.setHitChance })

    Aim:AddToggle("AimShowFov",    { Text = "Show FOV",    Default = F.aimbot.settings.ShowFOV,
        Callback = F.aimbot.setShowFov })
    Aim:AddToggle("AimShowTarget", { Text = "Show target", Default = F.aimbot.settings.ShowTarget,
        Callback = F.aimbot.setShowTarget })
    Aim:AddToggle("AimPrediction", { Text = "Prediction",  Default = F.aimbot.settings.Prediction,
        Callback = F.aimbot.setPrediction })
    Aim:AddSlider("AimPredictionAmt", { Text = "Prediction amount",
        Default = F.aimbot.settings.PredictionAmount, Min = 0, Max = 2, Rounding = 3,
        Callback = F.aimbot.setPredictionAmount })

    -- Triggerbot
    local Trig = Tabs.Combat:AddRightGroupbox("Triggerbot")

    local TrigEnabledToggle = Trig:AddToggle("TrigEnabled", { Text = "Enabled",
        Default = F.triggerbot.settings.Enabled, Callback = F.triggerbot.setEnabled })
    TrigEnabledToggle:AddKeyPicker("TrigKey", {
        Default = "X", Mode = "Toggle", Text = "Triggerbot key",
        SyncToggleState = true, NoUI = false,
    })

    Trig:AddToggle("TrigTeamCheck",{ Text = "Team check",    Default = F.triggerbot.settings.TeamCheck,
        Callback = F.triggerbot.setTeamCheck })
    Trig:AddToggle("TrigVisCheck", { Text = "Visible check", Default = F.triggerbot.settings.VisibleCheck,
        Callback = F.triggerbot.setVisibleCheck })
    Trig:AddToggle("TrigShowFov",  { Text = "Show FOV",      Default = F.triggerbot.settings.ShowFOV,
        Callback = F.triggerbot.setShowFov })
    Trig:AddSlider("TrigFov",      { Text = "FOV radius", Default = F.triggerbot.settings.FOVRadius,
        Min = 1, Max = 500, Rounding = 0, Callback = F.triggerbot.setFov })
    Trig:AddSlider("TrigDelay",    { Text = "Click delay", Default = F.triggerbot.settings.ClickDelay,
        Min = 0, Max = 2000, Rounding = 0, Suffix = " ms", Callback = F.triggerbot.setDelay })

    -- Camlock
    local Cam = Tabs.Combat:AddRightGroupbox("Camlock")

    local CamEnabledToggle = Cam:AddToggle("CamEnabled", { Text = "Enabled",
        Default = F.camLock.settings.Enabled, Callback = F.camLock.setEnabled })
    CamEnabledToggle:AddKeyPicker("CamKey", {
        Default = "C", Mode = "Toggle", Text = "Camlock key",
        SyncToggleState = true, NoUI = false,
    })

    Cam:AddToggle("CamTeamCheck", { Text = "Team check",    Default = F.camLock.settings.TeamCheck,
        Callback = F.camLock.setTeamCheck })
    Cam:AddToggle("CamVisCheck",  { Text = "Visible check", Default = F.camLock.settings.VisibleCheck,
        Callback = F.camLock.setVisibleCheck })
    Cam:AddToggle("CamSticky",    { Text = "Sticky target", Default = F.camLock.settings.Sticky,
        Callback = F.camLock.setSticky })

    Cam:AddDropdown("CamHitPart", {
        Values = { "Head", "HumanoidRootPart", "UpperTorso", "Random" },
        Default = F.camLock.settings.TargetPart, Text = "Hit part",
        Callback = F.camLock.setHitPart,
    })
    Cam:AddDropdown("CamMode", {
        Values = { "Mouse", "Cam" },
        Default = F.camLock.settings.Mode, Text = "Mode",
        Callback = F.camLock.setMode,
    })

    Cam:AddSlider("CamFov",       { Text = "FOV radius", Default = F.camLock.settings.FOVRadius,
        Min = 1, Max = 2000, Rounding = 0, Callback = F.camLock.setFov })
    Cam:AddSlider("CamSmoothing", { Text = "Smoothing", Default = F.camLock.settings.Smoothing,
        Min = 0, Max = 0.99, Rounding = 2, Callback = F.camLock.setSmoothing })

    Cam:AddToggle("CamShowFov",   { Text = "Show FOV",   Default = F.camLock.settings.ShowFOV,
        Callback = F.camLock.setShowFov })
    Cam:AddToggle("CamPrediction",{ Text = "Prediction", Default = F.camLock.settings.Prediction,
        Callback = F.camLock.setPrediction })
    Cam:AddSlider("CamPredictionAmt", { Text = "Prediction amount",
        Default = F.camLock.settings.PredictionAmount, Min = 0, Max = 2, Rounding = 3,
        Callback = F.camLock.setPredictionAmount })
end

-- ============================================================
--  RAGEBOT TAB
-- ============================================================
do
    local Tgt = Tabs.Ragebot:AddLeftGroupbox("Target")

    local targetLabel = Tgt:AddLabel("No target locked")
    local function refreshTargetLabel()
        local t = F.ragebot.getTarget()
        targetLabel:SetText(t and ("Locked: " .. t.Name) or "No target locked")
    end

    Tgt:AddDropdown("RagePlayer", {
        SpecialType = "Player", Text = "Player",
        Tooltip = "Player to lock or add to multi-target",
    })

    local function selectedRagePlayer()
        local name = Options.RagePlayer.Value
        if not name or name == "" then return nil end
        return F.players.find(name)
    end

    -- one-shot action buttons
    Tgt:AddButton({ Text = "Lock closest to mouse", Func = function()
        local p = F.ragebot.lockClosest()
        refreshTargetLabel()
        Library:Notify(p and ("Locked " .. p.Name) or "No target found", 2)
    end })
    :AddButton({ Text = "Lock selected", Func = function()
        local pl = selectedRagePlayer()
        if not pl then Library:Notify("No player selected", 2); return end
        F.ragebot.lockPlayer(pl); refreshTargetLabel()
        Library:Notify("Locked " .. pl.Name, 2)
    end })

    Tgt:AddButton({ Text = "Add selected to multi-target", Func = function()
        local pl = selectedRagePlayer()
        if not pl then Library:Notify("No player selected", 2); return end
        F.ragebot.addTarget(pl)
        Library:Notify("Added " .. pl.Name .. " to multi-target", 2)
    end })
    :AddButton({ Text = "Unlock all", Func = function()
        F.ragebot.unlock(); refreshTargetLabel()
        Library:Notify("Unlocked", 2)
    end })

    Tgt:AddButton({ Text = "TP behind target", Func = F.ragebot.tpBehind })

    Tgt:AddDivider()

    Tgt:AddToggle("RageSilentForce", { Text = "Silent force",
        Default = F.ragebot.settings.SilentForce, Callback = F.ragebot.setSilentForce })

    Tgt:AddDropdown("RageSilentMethod", {
        Values = { "All", "FindPartOnRay", "FindPartOnRayWithIgnoreList",
                   "FindPartOnRayWithWhitelist", "Mouse.Hit/Target" },
        Default = F.ragebot.settings.SilentMethod, Text = "Silent method",
        Callback = F.ragebot.setSilentMethod,
    })

    Tgt:AddToggle("RageSwitchByMouse", { Text = "Switch by mouse",
        Default = F.ragebot.settings.SwitchByMouse, Callback = F.ragebot.setSwitchByMouse })
    Tgt:AddToggle("RageShowLine",      { Text = "Show line",
        Default = F.ragebot.settings.ShowLine,    Callback = F.ragebot.setShowLine })
    Tgt:AddToggle("RageShowOutline",   { Text = "Show outline",
        Default = F.ragebot.settings.ShowOutline, Callback = F.ragebot.setShowOutline })
    Tgt:AddToggle("RageFaceTarget",    { Text = "Face target",
        Default = F.ragebot.settings.FaceTarget,  Callback = F.ragebot.setFaceTarget })
    Tgt:AddToggle("RageCamSnap",       { Text = "Cam snap",
        Default = F.ragebot.settings.CamSnap,     Callback = F.ragebot.setCamSnap })
    Tgt:AddSlider("RageCamSmoothing",  { Text = "Cam smoothing",
        Default = F.ragebot.settings.CamSmoothing, Min = 0.01, Max = 0.99, Rounding = 2,
        Callback = F.ragebot.setCamSmoothing })

    -- auto / orbit
    local Auto = Tabs.Ragebot:AddRightGroupbox("Auto / Orbit")

    Auto:AddToggle("RageAutoShoot",        { Text = "Auto shoot",
        Default = F.ragebot.settings.AutoShoot, Callback = F.ragebot.setAutoShoot })
    Auto:AddToggle("RageAutoShootVis",     { Text = "Require visible",
        Default = F.ragebot.settings.AutoShootVis, Callback = F.ragebot.setAutoShootVis })
    Auto:AddToggle("RageAutoShootReqTool", { Text = "Require tool",
        Default = F.ragebot.settings.AutoShootRequireTool, Callback = F.ragebot.setAutoShootRequireTool })
    Auto:AddToggle("RageFFCheck",          { Text = "Forcefield check",
        Default = F.ragebot.settings.FFCheck, Callback = F.ragebot.setFFCheck })

    Auto:AddSlider("RageAutoShootDist", { Text = "Max distance",
        Default = F.ragebot.settings.AutoShootDist, Min = 1, Max = 500, Rounding = 0,
        Callback = F.ragebot.setAutoShootDist })
    Auto:AddSlider("RageCooldown", { Text = "Cooldown",
        Default = F.ragebot.settings.AutoShootCooldown, Min = 0, Max = 2000, Rounding = 0,
        Suffix = " ms", Callback = F.ragebot.setAutoShootCooldown })
    Auto:AddSlider("RageEquipDelay", { Text = "Equip delay",
        Default = F.ragebot.settings.EquipDelay, Min = 0, Max = 5, Rounding = 2,
        Suffix = " s", Callback = F.ragebot.setEquipDelay })

    Auto:AddDivider()

    Auto:AddToggle("RageOrbit", { Text = "Orbit",
        Default = F.ragebot.settings.Orbit, Callback = F.ragebot.setOrbit })
    Auto:AddSlider("RageOrbitDist",   { Text = "Orbit distance",
        Default = F.ragebot.settings.OrbitDistance, Min = 2, Max = 200, Rounding = 0,
        Callback = F.ragebot.setOrbitDistance })
    Auto:AddSlider("RageOrbitSpeed",  { Text = "Orbit speed",
        Default = F.ragebot.settings.OrbitSpeed, Min = 1, Max = 360, Rounding = 0,
        Callback = F.ragebot.setOrbitSpeed })
    Auto:AddSlider("RageOrbitHeight", { Text = "Orbit height",
        Default = F.ragebot.settings.OrbitHeight, Min = -50, Max = 50, Rounding = 0,
        Callback = F.ragebot.setOrbitHeight })

    Auto:AddToggle("RageSpeedPanic", { Text = "Speed panic",
        Default = F.ragebot.settings.SpeedPanic, Callback = F.ragebot.setSpeedPanic })

    -- one-shot keybinds (fired via InputBegan, no toggle visual)
    Tgt:AddLabel("Lock closest"):AddKeyPicker("RageLockKey", {
        Default = "E", Mode = "Toggle", Text = "Lock closest / unlock", NoUI = false,
    })
    Tgt:AddLabel("Add to multi-target"):AddKeyPicker("RageMultiKey", {
        Default = "M", Mode = "Toggle", Text = "Add closest to multi-target", NoUI = false,
    })
    Tgt:AddLabel("TP behind"):AddKeyPicker("RageTpKey", {
        Default = "Y", Mode = "Toggle", Text = "TP behind target", NoUI = false,
    })

    -- Lock-closest key: unlock if already locked, otherwise lock closest
    bindFireKey("RageLockKey", function()
        if F.ragebot.getTarget() then
            F.ragebot.unlock()
        else
            F.ragebot.lockClosest()
        end
        refreshTargetLabel()
    end)
    -- Multi-target key: add closest to mouse to the multi-target list (does NOT unlock)
    bindFireKey("RageMultiKey", function()
        local closest = F.utils.findClosestPlayer({ fov = 9999 })
        if not closest then Library:Notify("No player nearby", 2); return end
        F.ragebot.addTarget(closest)
        Library:Notify("Added " .. closest.Name .. " to multi-target", 2)
    end)
    bindFireKey("RageTpKey", F.ragebot.tpBehind)

    -- keep label fresh on auto-switches
    task.spawn(function()
        local last
        while not Library.Unloaded do
            local t = F.ragebot.getTarget()
            if t ~= last then last = t; refreshTargetLabel() end
            task.wait(0.25)
        end
    end)
end

-- ============================================================
--  ESP TAB
-- ============================================================
do
    local Players_ = Tabs.ESP:AddLeftGroupbox("Players")

    local EspEnabledToggle = Players_:AddToggle("EspEnabled", { Text = "Enabled",
        Default = F.esp.settings.Enabled,
        Callback = function(v) if v then F.esp.start() else F.esp.stop() end end })
    EspEnabledToggle:AddKeyPicker("EspKey", {
        Default = "Insert", Mode = "Toggle", Text = "ESP key", SyncToggleState = true,
    })
    Players_:AddToggle("EspBox",     { Text = "Boxes",         Default = F.esp.settings.BoxESP,
        Callback = F.esp.setBox })
    Players_:AddDropdown("EspBoxStyle", {
        Values = { "Corners", "Full" }, Default = F.esp.settings.BoxStyle,
        Text = "Box style", Callback = F.esp.setBoxStyle,
    })
    Players_:AddToggle("EspNames",     { Text = "Names",        Default = F.esp.settings.NameESP,
        Callback = F.esp.setNames })
    Players_:AddToggle("EspHealth",    { Text = "Health bars",  Default = F.esp.settings.HealthESP,
        Callback = F.esp.setHealth })
    Players_:AddToggle("EspHealthNum", { Text = "Health number", Default = F.esp.settings.HealthNum,
        Callback = F.esp.setHealthNum })
    Players_:AddToggle("EspDistance",  { Text = "Distance",     Default = F.esp.settings.DistanceESP,
        Callback = F.esp.setDistance })
    Players_:AddToggle("EspTracer",    { Text = "Tracers",      Default = F.esp.settings.TracerESP,
        Callback = F.esp.setTracer })
    Players_:AddDropdown("EspTracerOrigin", {
        Values = { "Bottom", "Center", "Top", "Mouse" },
        Default = F.esp.settings.TracerOrigin,
        Text = "Tracer origin", Callback = F.esp.setTracerOrigin,
    })
    Players_:AddToggle("EspSkeleton",  { Text = "Skeleton",   Default = F.esp.settings.SkeletonESP,
        Callback = F.esp.setSkeleton })
    Players_:AddToggle("EspHeldItem",  { Text = "Held item",  Default = F.esp.settings.HeldItem,
        Callback = F.esp.setHeldItem })
    Players_:AddToggle("EspTeamColors",{ Text = "Team colors",Default = F.esp.settings.TeamCheck,
        Callback = F.esp.setTeamCheck })

    local World = Tabs.ESP:AddRightGroupbox("World")

    World:AddToggle("EspChams", { Text = "Chams", Default = F.esp.settings.ChamsEnabled,
        Callback = F.esp.setChams })
    World:AddDropdown("EspChamsStyle", {
        Values = { "Overlay", "Occluded", "Outline" },
        Default = F.esp.settings.ChamsStyle,
        Text = "Chams style", Callback = F.esp.setChamsStyle,
    })

    World:AddToggle("EspTracerHist", { Text = "Tracer history",
        Default = F.esp.settings.TracerHistory, Callback = F.esp.setTracerHistory })
    World:AddSlider("EspTracerHistLen", { Text = "History length",
        Default = F.esp.settings.TracerHistLen, Min = 0.5, Max = 10, Rounding = 1,
        Suffix = " s", Callback = F.esp.setTracerHistLen })

    World:AddToggle("EspSelf", { Text = "Self ESP", Default = F.esp.settings.SelfESP,
        Callback = F.esp.setSelf })
end

-- ============================================================
--  MOVEMENT TAB
-- ============================================================
do
    local Move = Tabs.Movement:AddLeftGroupbox("Movement")

    local FlyToggle = Move:AddToggle("Fly", { Text = "Fly", Default = false,
        Callback = function(v) if v then F.fly.start() else F.fly.stop() end end })
    FlyToggle:AddKeyPicker("FlyKey", {
        Default = "F", Mode = "Toggle", Text = "Fly key", SyncToggleState = true,
    })
    Move:AddSlider("FlySpeed", { Text = "Fly speed", Default = F.fly.getSpeed(),
        Min = 5, Max = 500, Rounding = 0, Callback = F.fly.setSpeed })

    local SpeedToggle = Move:AddToggle("Speed", { Text = "Speed", Default = false,
        Callback = function(v) if v then F.speed.start(F.speed.getMultiplier()) else F.speed.stop() end end })
    SpeedToggle:AddKeyPicker("SpeedKey", {
        Default = "G", Mode = "Toggle", Text = "Speed key", SyncToggleState = true,
    })
    Move:AddSlider("SpeedMult", { Text = "Speed multiplier", Default = F.speed.getMultiplier(),
        Min = 1, Max = 20, Rounding = 1, Suffix = "x", Callback = F.speed.setMultiplier })

    local BhopToggle = Move:AddToggle("Bhop", { Text = "Bunnyhop", Default = false,
        Callback = function(v) if v then F.bhop.start() else F.bhop.stop() end end })
    BhopToggle:AddKeyPicker("BhopKey", {
        Default = "H", Mode = "Toggle", Text = "Bhop key", SyncToggleState = true,
    })

    Move:AddToggle("InfJump",    { Text = "Infinite jump", Default = false,
        Callback = function(v) if v then F.infJump.start() else F.infJump.stop() end end })
    Move:AddToggle("AntiAfk",    { Text = "Anti-AFK",      Default = false,
        Callback = function(v) if v then F.antiAfk.start() else F.antiAfk.stop() end end })
    Move:AddToggle("ClickTp",    { Text = "Click TP",      Default = false,
        Callback = function(v) if v then F.clickTp.start() else F.clickTp.stop() end end })

    local NoclipToggle = Move:AddToggle("Noclip", { Text = "Noclip", Default = false,
        Callback = function(v) if v then F.noclip.start() else F.noclip.stop() end end })
    NoclipToggle:AddKeyPicker("NoclipKey", {
        Default = "N", Mode = "Toggle", Text = "Noclip key", SyncToggleState = true,
    })

    Move:AddToggle("AutoRespawn",{ Text = "Auto-respawn",  Default = false,
        Callback = function(v) if v then F.autoRespawn.start() else F.autoRespawn.stop() end end })

    local Cam = Tabs.Movement:AddRightGroupbox("Camera / Visual")

    Cam:AddToggle("Fullbright", { Text = "Fullbright", Default = false,
        Callback = function(v) if v then F.fullbright.start() else F.fullbright.stop() end end })

    local FreecamToggle = Cam:AddToggle("Freecam", { Text = "Freecam", Default = false,
        Callback = function(v) if v then F.freecam.start() else F.freecam.stop() end end })
    FreecamToggle:AddKeyPicker("FreecamKey", {
        Default = "K", Mode = "Toggle", Text = "Freecam key", SyncToggleState = true,
    })

    Cam:AddToggle("Zoom",       { Text = "Extended zoom", Default = false,
        Callback = function(v) if v then F.zoom.start() else F.zoom.stop() end end })

    Cam:AddSlider("Fov", { Text = "FOV", Default = F.fov.get(),
        Min = 30, Max = 120, Rounding = 0, Callback = F.fov.set })
end

-- ============================================================
--  FUN TAB
-- ============================================================
do
    local Fun = Tabs.Fun:AddLeftGroupbox("Movement extras")

    Fun:AddToggle("Spin", { Text = "Spin", Default = false,
        Callback = function(v) if v then F.spin.start() else F.spin.stop() end end })
    Fun:AddSlider("SpinSpeed", { Text = "Spin speed", Default = 50,
        Min = 1, Max = 200, Rounding = 0, Callback = F.spin.setSpeed })

    Fun:AddToggle("Flip", { Text = "Upside down", Tooltip = "Flip your character upside-down",
        Default = false,
        Callback = function(v) if v then F.flip.start() else F.flip.stop() end end })

    Fun:AddToggle("Ice", { Text = "Ice slide", Default = false,
        Callback = function(v) if v then F.ice.start() else F.ice.stop() end end })
    Fun:AddSlider("IceSlide", { Text = "Slide friction", Default = 0.98,
        Min = 0.5, Max = 0.99, Rounding = 2, Callback = F.ice.setSlide })

    local Act = Tabs.Fun:AddRightGroupbox("Actions")

    Act:AddButton({ Text = "Blink forward", Func = F.blink.fire,
        Tooltip = "Teleport forward in camera direction" })
    Act:AddSlider("BlinkDist", { Text = "Blink distance", Default = F.blink.getDistance(),
        Min = 1, Max = 200, Rounding = 0, Callback = F.blink.setDistance })

    Act:AddButton({ Text = "Respawn", Func = F.respawn.fire,
        Tooltip = "Respawn at current position" })

    Act:AddDivider()

    Act:AddButton({ Text = "PANIC — disable everything", DoubleClick = true,
        Tooltip = "Double-click to disable every active feature",
        Func = function()
            F.disableAll()
            -- reflect the change back into the UI toggles
            for _, name in ipairs({
                "Fly","Speed","Bhop","InfJump","AntiAfk","ClickTp","Noclip","AutoRespawn",
                "Fullbright","Freecam","Zoom","Spin","Flip","Ice",
                "AimEnabled","TrigEnabled","CamEnabled",
                "RageSilentForce","RageAutoShoot","RageOrbit","RageFaceTarget","RageCamSnap","RageSpeedPanic",
                "EspEnabled",
            }) do
                if Toggles[name] then Toggles[name]:SetValue(false) end
            end
            Library:Notify("All features disabled", 3)
        end,
    })

    -- one-shot keybinds for blink / respawn (no toggle visual)
    Act:AddLabel("Blink key"):AddKeyPicker("BlinkKey", {
        Default = "B", Mode = "Toggle", Text = "Blink forward",
    })
    Act:AddLabel("Respawn key"):AddKeyPicker("RespawnKey", {
        Default = "R", Mode = "Toggle", Text = "Respawn",
    })
    bindFireKey("BlinkKey", F.blink.fire)
    bindFireKey("RespawnKey", F.respawn.fire)
end

-- ============================================================
--  PLAYERS TAB
-- ============================================================
do
    local P = Tabs.Players:AddLeftGroupbox("Actions")

    P:AddLabel("Pick a player and choose an action")

    P:AddDropdown("PlayerPick", {
        SpecialType = "Player", Text = "Player",
        Tooltip = "All players except yourself",
    })

    local function selectedPlayer()
        local name = Options.PlayerPick.Value
        if not name or name == "" then return nil end
        return F.players.find(name)
    end

    P:AddButton({ Text = "Goto",  Func = function()
        local pl = selectedPlayer(); if pl then F.players.goto(pl)
        else Library:Notify("No player selected", 2) end
    end })
    :AddButton({ Text = "View",  Func = function()
        local pl = selectedPlayer(); if pl then F.players.view(pl)
        else Library:Notify("No player selected", 2) end
    end })

    P:AddButton({ Text = "Fling", Func = function()
        local pl = selectedPlayer()
        if not pl then Library:Notify("No player selected", 2); return end
        F.players.fling(pl)
        Library:Notify("Flinging " .. pl.Name, 3)
    end })

    P:AddDivider()

    P:AddButton({ Text = "Reset camera view", Func = function()
        workspace.CurrentCamera.CameraSubject =
            LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    end })
end

-- ============================================================
--  WATERMARK + UNLOAD
-- ============================================================
Library:SetWatermarkVisibility(true)

local FrameTimer, FrameCounter, FPS = tick(), 0, 60
local WatermarkConn = RunService.RenderStepped:Connect(function()
    FrameCounter += 1
    if (tick() - FrameTimer) >= 1 then
        FPS = FrameCounter; FrameTimer = tick(); FrameCounter = 0
    end
    local ping = 0
    pcall(function()
        ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
    end)
    Library:SetWatermark(("cclosure.vip | %d fps | %d ms"):format(math.floor(FPS), ping))
end)

Library.KeybindFrame.Visible = true

Library:OnUnload(function()
    pcall(function() WatermarkConn:Disconnect() end)
    pcall(F.disableAll)
    Library.Unloaded = true
    print("[cclosure.vip] unloaded")
end)

-- ============================================================
--  UI SETTINGS  (theme + saves + menu keybind + unload)
-- ============================================================
local Menu = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

Menu:AddButton({ Text = "Unload script", Func = function() Library:Unload() end })

Menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
    Default = "End", NoUI = true, Text = "Menu keybind",
})
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("cclosure.vip")
SaveManager:SetFolder("cclosure.vip/configs")

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()

Library:Notify("cclosure.vip loaded — press End to toggle the menu", 4)
