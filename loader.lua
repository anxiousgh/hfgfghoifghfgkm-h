-- ============================================================
--  cclosure.vip   //   @vampire   //   LinoriaLib build
--  executor: Potassium
-- ============================================================

local _functionsSrc = game:HttpGet("https://raw.githubusercontent.com/anxiousgh/hfgfghoifghfgkm-h/main/functions.lua")
local _fnFn, _fnErr = loadstring(_functionsSrc)
if not _fnFn then
    error("[cclosure.vip] functions.lua failed to compile: " .. tostring(_fnErr), 0)
end
local F = _fnFn()

local repo = "https://raw.githubusercontent.com/anxiousgh/hfgfghoifghfgkm-h/main/"
local Library      = loadstring(game:HttpGet(repo .. "lib.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "libaddons/tman.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "libaddons/sman.lua"))()

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
    if UserInputService:GetFocusedTextBox() then return end
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
    Combat   = Window:AddTab("Combat"),
    Visual   = Window:AddTab("Visual"),
    Movement = Window:AddTab("Movement"),
    Players  = Window:AddTab("Players"),
    Misc     = Window:AddTab("Misc"),
    Games    = Window:AddTab("Games"),
    Config   = Window:AddTab("Config"),
}

-- ============================================================
--  COMBAT TAB  (silent aim / ragebot / triggerbot / camlock)
-- ============================================================
do
    local CombatLeft  = Tabs.Combat:AddLeftTabbox()
    local CombatRight = Tabs.Combat:AddRightTabbox()

    local Aim = CombatLeft:AddTab("Silent Aim")

    local AimEnabledToggle = Aim:AddToggle("AimEnabled", { Text = "Enabled",
        Default = F.aimbot.settings.Enabled, Callback = F.aimbot.setEnabled })
    AimEnabledToggle:AddKeyPicker("AimKey", {
        Default = "J", Mode = "Toggle", Text = "Silent aim key",
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
    local Trig = CombatLeft:AddTab("Triggerbot")

    local TrigEnabledToggle = Trig:AddToggle("TrigEnabled", { Text = "Enabled",
        Default = F.triggerbot.settings.Enabled, Callback = F.triggerbot.setEnabled })
    TrigEnabledToggle:AddKeyPicker("TrigKey", {
        Default = "Y", Mode = "Toggle", Text = "Triggerbot key",
        SyncToggleState = true, NoUI = false,
    })

    Trig:AddToggle("TrigTeamCheck", { Text = "Team check",
        Default = F.triggerbot.settings.TeamCheck, Callback = F.triggerbot.setTeamCheck })
    Trig:AddToggle("TrigVisCheck",  { Text = "Visible check",
        Default = F.triggerbot.settings.VisibleCheck, Callback = F.triggerbot.setVisibleCheck })

    Trig:AddDropdown("TrigHitPart", {
        Values = {
            "All",  -- fires on any body part of any player
            -- shared
            "HumanoidRootPart", "Head",
            -- R15
            "UpperTorso", "LowerTorso",
            "LeftUpperArm", "LeftLowerArm", "LeftHand",
            "RightUpperArm", "RightLowerArm", "RightHand",
            "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
            "RightUpperLeg", "RightLowerLeg", "RightFoot",
            -- R6
            "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
            -- random
            "Random",
        },
        Default = F.triggerbot.settings.TargetPart,
        Text = "Hit part",
        Callback = F.triggerbot.setHitPart,
    })

    Trig:AddSlider("TrigFov", { Text = "FOV radius", Default = F.triggerbot.settings.FOVRadius,
        Min = 1, Max = 500, Rounding = 0, Callback = F.triggerbot.setFov })
    Trig:AddSlider("TrigDelay", { Text = "Click delay", Default = F.triggerbot.settings.ClickDelay,
        Min = 0, Max = 2000, Rounding = 0, Suffix = " ms", Callback = F.triggerbot.setDelay })

    Trig:AddToggle("TrigShowFov",    { Text = "Show FOV",
        Default = F.triggerbot.settings.ShowFOV, Callback = F.triggerbot.setShowFov })
    Trig:AddToggle("TrigShowTarget", { Text = "Show target",
        Default = F.triggerbot.settings.ShowTarget, Callback = F.triggerbot.setShowTarget })

    -- Camlock
    local Cam = CombatLeft:AddTab("Camlock")

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
    Cam:AddToggle("CamClosestPart",{ Text = "Closest bodypart", Default = F.camLock.settings.ClosestPart,
        Callback = F.camLock.setClosestPart })

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

    -- =================== RAGEBOT (target + auto/orbit) ===================
    local Tgt = CombatRight:AddTab("Ragebot")

    local targetLabel = Tgt:AddLabel("No target locked")
    local listLabel   = Tgt:AddLabel("Targets: (none)", true)  -- DoesWrap

    local function refreshTargetLabel()
        local t = F.ragebot.getTarget()
        targetLabel:SetText(t and ("Locked: " .. t.Name) or "No target locked")

        local list = F.ragebot.getTargetList()
        if #list == 0 then
            listLabel:SetText("Targets: (none)")
        else
            local names = {}
            for _, pl in ipairs(list) do table.insert(names, pl.Name) end
            listLabel:SetText(("Targets (%d): %s"):format(#list, table.concat(names, ", ")))
        end
    end

    Tgt:AddButton({ Text = "TP behind target", Func = F.ragebot.tpBehind })
    :AddButton({ Text = "TP shoot",
        Func = F.ragebot.tpShoot })

    Tgt:AddToggle("RageAutoTargetDamager", {
        Text = "Auto target damager",
        Default = false,
    })

    Tgt:AddToggle("RageTargetGui", {
        Text = "Show target HUD",
        Default = false,
        Callback = function(v)
            if v then F.ragebot.targetGui.start() else F.ragebot.targetGui.stop() end
        end })

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
    Tgt:AddToggle("RageShowLine",      { Text = "Show target line",
        Default = F.ragebot.settings.ShowLine,    Callback = F.ragebot.setShowLine })
    Tgt:AddDropdown("RageLineOrigin", {
        Values = { "Bottom", "Center", "Top", "Mouse" },
        Default = F.ragebot.settings.LineOrigin,
        Text = "Line origin",
        Callback = F.ragebot.setLineOrigin,
    })
    Tgt:AddToggle("RageShowOutline",   { Text = "Show target outline",
        Default = F.ragebot.settings.ShowOutline, Callback = F.ragebot.setShowOutline })
    Tgt:AddToggle("RageFaceTarget",    { Text = "Face target",
        Default = F.ragebot.settings.FaceTarget,  Callback = F.ragebot.setFaceTarget })
    Tgt:AddToggle("RageCamSnap",       { Text = "Cam snap",
        Default = F.ragebot.settings.CamSnap,     Callback = F.ragebot.setCamSnap })
    Tgt:AddSlider("RageCamSmoothing",  { Text = "Cam smoothing",
        Default = F.ragebot.settings.CamSmoothing, Min = 0.01, Max = 0.99, Rounding = 2,
        Callback = F.ragebot.setCamSmoothing })

    -- orbit-only tab
    local Orbit = CombatRight:AddTab("Orbit")

    Orbit:AddToggle("RageOrbit", { Text = "Orbit",
        Default = F.ragebot.settings.Orbit, Callback = F.ragebot.setOrbit })
    Orbit:AddSlider("RageOrbitDist",   { Text = "Orbit distance",
        Default = F.ragebot.settings.OrbitDistance, Min = 2, Max = 200, Rounding = 0,
        Callback = F.ragebot.setOrbitDistance })
    Orbit:AddSlider("RageOrbitSpeed",  { Text = "Orbit speed",
        Default = F.ragebot.settings.OrbitSpeed, Min = 1, Max = 9999, Rounding = 0,
        Callback = F.ragebot.setOrbitSpeed })
    Orbit:AddSlider("RageOrbitHeight", { Text = "Orbit height",
        Default = F.ragebot.settings.OrbitHeight, Min = -50, Max = 50, Rounding = 0,
        Callback = F.ragebot.setOrbitHeight })

    -- one-shot keybinds (fired via InputBegan, no toggle visual)
    Tgt:AddLabel("Lock closest"):AddKeyPicker("RageLockKey", {
        Default = "V", Mode = "Hold", Text = "Lock closest", NoUI = false,
    })
    Tgt:AddLabel("Unlock all"):AddKeyPicker("RageUnlockKey", {
        Default = "N", Mode = "Hold", Text = "Unlock all targets", NoUI = false,
    })
    Tgt:AddLabel("TP behind"):AddKeyPicker("RageTpKey", {
        Default = "H", Mode = "Hold", Text = "TP behind target", NoUI = false,
    })

    -- Lock key: first press locks closest, subsequent presses add NEXT closest
    -- (skipping anyone already in the target list)
    bindFireKey("RageLockKey", function()
        local excl = {}
        for _, pl in ipairs(F.ragebot.getTargetList()) do excl[pl] = true end
        local closest = F.utils.findClosestPlayer({ fov = 9999, exclude = excl })
        if not closest then Library:Notify("No more players nearby", 2); return end
        if F.ragebot.getTarget() then
            F.ragebot.addTarget(closest)
            Library:Notify("Added " .. closest.Name .. " to multi-target", 2)
        else
            F.ragebot.lockPlayer(closest)
            Library:Notify("Locked " .. closest.Name, 2)
        end
        refreshTargetLabel()
    end)
    bindFireKey("RageUnlockKey", function()
        F.ragebot.unlock()
        refreshTargetLabel()
        Library:Notify("Unlocked", 2)
    end)
    bindFireKey("RageTpKey", F.ragebot.tpBehind)

    -- Tp-shoot keybind
    Tgt:AddLabel("TP shoot"):AddKeyPicker("RageTpShootKey", {
        Default = "G", Mode = "Hold", Text = "TP shoot", NoUI = false,
    })
    bindFireKey("RageTpShootKey", F.ragebot.tpShoot)

    -- Auto-target damager wiring
    F.damage.onDamaged(function(attacker)
        if not Toggles.RageAutoTargetDamager or not Toggles.RageAutoTargetDamager.Value then return end
        if F.ragebot.isTargeted(attacker) then return end
        F.ragebot.addTarget(attacker)
        Library:Notify("Auto-targeted " .. attacker.Name .. " (damaged you)", 3)
    end)

    -- keep labels fresh on auto-switches and list changes
    task.spawn(function()
        local lastTarget
        local lastListSig = ""
        while not Library.Unloaded do
            local t = F.ragebot.getTarget()
            local list = F.ragebot.getTargetList()
            local sig = ""
            for _, pl in ipairs(list) do sig = sig .. pl.Name .. "|" end
            if t ~= lastTarget or sig ~= lastListSig then
                lastTarget, lastListSig = t, sig
                refreshTargetLabel()
            end
            task.wait(0.25)
        end
    end)

    -- =================== AUTO (auto-shoot + auto-equip), right tabbox ===================
    local AutoT = CombatRight:AddTab("Auto")

    AutoT:AddLabel("Auto shoot")
    AutoT:AddToggle("RageAutoShoot",        { Text = "Auto shoot",
        Default = F.ragebot.settings.AutoShoot, Callback = F.ragebot.setAutoShoot })
    AutoT:AddToggle("RageAutoShootVis",     { Text = "Require visible",
        Default = F.ragebot.settings.AutoShootVis, Callback = F.ragebot.setAutoShootVis })
    AutoT:AddToggle("RageAutoShootReqTool", { Text = "Require tool",
        Default = F.ragebot.settings.AutoShootRequireTool, Callback = F.ragebot.setAutoShootRequireTool })
    AutoT:AddToggle("RageFFCheck",          { Text = "Forcefield check",
        Default = F.ragebot.settings.FFCheck, Callback = F.ragebot.setFFCheck })

    AutoT:AddSlider("RageAutoShootDist", { Text = "Max distance",
        Default = F.ragebot.settings.AutoShootDist, Min = 1, Max = 500, Rounding = 0,
        Callback = F.ragebot.setAutoShootDist })
    AutoT:AddSlider("RageCooldown", { Text = "Cooldown",
        Default = F.ragebot.settings.AutoShootCooldown, Min = 0, Max = 2000, Rounding = 0,
        Suffix = " ms", Callback = F.ragebot.setAutoShootCooldown })
    AutoT:AddSlider("RageEquipDelay", { Text = "Equip delay",
        Default = F.ragebot.settings.EquipDelay, Min = 0, Max = 5, Rounding = 2,
        Suffix = " s", Callback = F.ragebot.setEquipDelay })

    AutoT:AddDivider()
    AutoT:AddLabel("Auto equip")

    AutoT:AddDropdown("AutoEquipTool", {
        Values = { "(refresh)" }, Default = "(refresh)",
        Text = "Tool",
        Callback = function(v) F.autoEquip.setName(v) end,
    })

    -- Preserve current selection on refresh — equipping moves a tool from the
    -- backpack into the character, so the list rebuilds and the user's pick
    -- would otherwise jump to whatever ends up alphabetically first.
    local function refreshToolList()
        local list = F.autoEquip.list()
        if #list == 0 then list = { "(no tools)" } end
        local current = Options.AutoEquipTool and Options.AutoEquipTool.Value
        Options.AutoEquipTool:SetValues(list)
        local keep = false
        for _, n in ipairs(list) do if n == current then keep = true; break end end
        if keep then
            Options.AutoEquipTool:SetValue(current)
        else
            Options.AutoEquipTool:SetValue(list[1])
        end
    end

    AutoT:AddButton({ Text = "Refresh tool list", Func = refreshToolList })
    :AddButton({ Text = "Equip now", Func = function()
        local name = Options.AutoEquipTool.Value
        if F.autoEquip.equip(name) then
            Library:Notify("Equipped " .. name, 2)
        else
            Library:Notify("Couldn't equip " .. tostring(name), 2)
        end
    end })

    AutoT:AddToggle("AutoEquipOnRespawn", { Text = "Auto equip on respawn",
        Default = false,
        Callback = function(v)
            if v then F.autoEquip.start() else F.autoEquip.stop() end
        end })

    -- auto-refresh tool list when backpack changes / on respawn
    local function hookBackpack(bp)
        if not bp then return end
        bp.ChildAdded:Connect(function() task.defer(refreshToolList) end)
        bp.ChildRemoved:Connect(function() task.defer(refreshToolList) end)
    end
    hookBackpack(LocalPlayer:FindFirstChildOfClass("Backpack"))
    LocalPlayer.ChildAdded:Connect(function(c)
        if c:IsA("Backpack") then hookBackpack(c) end
    end)
    LocalPlayer.CharacterAdded:Connect(function() task.wait(0.5); pcall(refreshToolList) end)
    task.defer(refreshToolList)

    -- =================== HITBOX EXTENDER (left side, below the tabbox) ===================
    local Hb = Tabs.Combat:AddLeftGroupbox("Hitbox")

    Hb:AddToggle("HitboxEnabled", { Text = "Hitbox extender",
        Default = false,
        Callback = function(v) if v then F.hitboxExtender.start() else F.hitboxExtender.stop() end end,
    })

    Hb:AddSlider("HitboxSize", { Text = "Hitbox size",
        Default = F.hitboxExtender.getSize(), Min = 1, Max = 50, Rounding = 0,
        Callback = F.hitboxExtender.setSize })

    Hb:AddDropdown("HitboxPart", {
        Values = {
            "HumanoidRootPart","Head","UpperTorso","LowerTorso","Torso",
            "LeftUpperArm","LeftLowerArm","LeftHand","RightUpperArm","RightLowerArm","RightHand",
            "LeftUpperLeg","LeftLowerLeg","LeftFoot","RightUpperLeg","RightLowerLeg","RightFoot",
            "Left Arm","Right Arm","Left Leg","Right Leg",
        },
        Default = F.hitboxExtender.getTargetPart(),
        Text = "Target part",
        Callback = F.hitboxExtender.setTargetPart,
    })

    Hb:AddSlider("HitboxTransparency", { Text = "Transparency",
        Default = 0.6, Min = 0, Max = 1, Rounding = 2,
        Callback = F.hitboxExtender.setTransparency })
end

-- ============================================================
--  VISUAL TAB  (lighting + post FX + atmosphere + camera + ESP)
-- ============================================================
do
    local Lighting = game:GetService("Lighting")

    -- helper: get-or-create a Lighting effect with a unique name so we don't
    -- clobber whatever the game itself already has parented in there
    local function fxInstance(class, name)
        local existing = Lighting:FindFirstChild(name)
        if existing and existing:IsA(class) then return existing end
        local inst = Instance.new(class)
        inst.Name = name
        inst.Enabled = false
        inst.Parent = Lighting
        return inst
    end

    local CC      = fxInstance("ColorCorrectionEffect", "_cclosure_cc")
    local Bloom   = fxInstance("BloomEffect",           "_cclosure_bloom")
    local Blur    = fxInstance("BlurEffect",            "_cclosure_blur")
    local SunRays = fxInstance("SunRaysEffect",         "_cclosure_sunrays")

    local LIGHTING_DEFAULTS = {
        Brightness     = 1, ClockTime = 14, FogStart = 0, FogEnd = 100000,
        Ambient        = Color3.fromRGB(70, 70, 70),
        OutdoorAmbient = Color3.fromRGB(128, 128, 128),
        FogColor       = Color3.fromRGB(192, 192, 192),
        GlobalShadows  = true,
    }

    -- ---------------- LEFT TABBOX ----------------
    local Left = Tabs.Visual:AddLeftTabbox()

    -- Lighting
    local TabLight = Left:AddTab("Lighting")

    TabLight:AddToggle("Fullbright", { Text = "Fullbright", Default = false,
        Callback = function(v) if v then F.fullbright.start() else F.fullbright.stop() end end })
    TabLight:AddToggle("GlobalShadows", { Text = "Global shadows",
        Default = Lighting.GlobalShadows,
        Callback = function(v) Lighting.GlobalShadows = v end })

    TabLight:AddDivider()

    TabLight:AddSlider("LightBrightness", { Text = "Brightness",
        Default = Lighting.Brightness, Min = 0, Max = 10, Rounding = 2,
        Callback = function(v) Lighting.Brightness = v end })
    TabLight:AddSlider("LightClockTime", { Text = "Time of day",
        Default = Lighting.ClockTime, Min = 0, Max = 24, Rounding = 2,
        Callback = function(v) Lighting.ClockTime = v end })
    TabLight:AddSlider("LightExposure", { Text = "Exposure",
        Default = Lighting.ExposureCompensation, Min = -5, Max = 5, Rounding = 2,
        Callback = function(v) Lighting.ExposureCompensation = v end })

    TabLight:AddDivider()

    TabLight:AddLabel("Ambient"):AddColorPicker("LightAmbient", {
        Default = Lighting.Ambient, Title = "Ambient",
        Callback = function(c) Lighting.Ambient = c end,
    })
    TabLight:AddLabel("Outdoor ambient"):AddColorPicker("LightOutdoor", {
        Default = Lighting.OutdoorAmbient, Title = "Outdoor ambient",
        Callback = function(c) Lighting.OutdoorAmbient = c end,
    })

    TabLight:AddDivider()

    TabLight:AddButton({ Text = "Restore default lighting", Func = function()
        for k, v in pairs(LIGHTING_DEFAULTS) do pcall(function() Lighting[k] = v end) end
        if Toggles.Fullbright    then Toggles.Fullbright:SetValue(false)    end
        if Toggles.GlobalShadows then Toggles.GlobalShadows:SetValue(true)  end
        Library:Notify("Lighting restored", 2)
    end })

    -- Post FX
    local TabFX = Left:AddTab("Post FX")

    TabFX:AddLabel("Color correction")
    TabFX:AddToggle("CCEnabled", { Text = "Enabled", Default = false,
        Callback = function(v) CC.Enabled = v end })
    TabFX:AddSlider("CCBrightness", { Text = "Brightness",
        Default = 0, Min = -1, Max = 1, Rounding = 2,
        Callback = function(v) CC.Brightness = v end })
    TabFX:AddSlider("CCContrast", { Text = "Contrast",
        Default = 0, Min = -1, Max = 1, Rounding = 2,
        Callback = function(v) CC.Contrast = v end })
    TabFX:AddSlider("CCSaturation", { Text = "Saturation",
        Default = 0, Min = -1, Max = 5, Rounding = 2,
        Callback = function(v) CC.Saturation = v end })
    TabFX:AddLabel("Tint"):AddColorPicker("CCTint", {
        Default = Color3.fromRGB(255, 255, 255), Title = "Tint",
        Callback = function(c) CC.TintColor = c end,
    })

    TabFX:AddDivider()

    TabFX:AddLabel("Bloom")
    TabFX:AddToggle("BloomEnabled", { Text = "Enabled", Default = false,
        Callback = function(v) Bloom.Enabled = v end })
    TabFX:AddSlider("BloomIntensity", { Text = "Intensity",
        Default = 0.4, Min = 0, Max = 5, Rounding = 2,
        Callback = function(v) Bloom.Intensity = v end })
    TabFX:AddSlider("BloomThreshold", { Text = "Threshold",
        Default = 2.0, Min = 0, Max = 10, Rounding = 2,
        Callback = function(v) Bloom.Threshold = v end })
    TabFX:AddSlider("BloomSize", { Text = "Size",
        Default = 24, Min = 0, Max = 64, Rounding = 0,
        Callback = function(v) Bloom.Size = v end })

    TabFX:AddDivider()

    TabFX:AddLabel("Blur")
    TabFX:AddToggle("BlurEnabled", { Text = "Enabled", Default = false,
        Callback = function(v) Blur.Enabled = v end })
    TabFX:AddSlider("BlurSize", { Text = "Size",
        Default = 12, Min = 0, Max = 56, Rounding = 0,
        Callback = function(v) Blur.Size = v end })

    TabFX:AddDivider()

    TabFX:AddLabel("Sun rays")
    TabFX:AddToggle("SunRaysEnabled", { Text = "Enabled", Default = false,
        Callback = function(v) SunRays.Enabled = v end })
    TabFX:AddSlider("SunRaysIntensity", { Text = "Intensity",
        Default = 0.25, Min = 0, Max = 1, Rounding = 2,
        Callback = function(v) SunRays.Intensity = v end })
    TabFX:AddSlider("SunRaysSpread", { Text = "Spread",
        Default = 1.0, Min = 0, Max = 1, Rounding = 2,
        Callback = function(v) SunRays.Spread = v end })

    TabFX:AddDivider()

    TabFX:AddButton({ Text = "Disable all post FX", Func = function()
        if Toggles.CCEnabled      then Toggles.CCEnabled:SetValue(false)      end
        if Toggles.BloomEnabled   then Toggles.BloomEnabled:SetValue(false)   end
        if Toggles.BlurEnabled    then Toggles.BlurEnabled:SetValue(false)    end
        if Toggles.SunRaysEnabled then Toggles.SunRaysEnabled:SetValue(false) end
    end })

    -- ESP players
    local TabEspPlayers = Left:AddTab("ESP")

    local EspEnabledToggle = TabEspPlayers:AddToggle("EspEnabled", { Text = "Enabled",
        Default = F.esp.settings.Enabled,
        Callback = function(v) if v then F.esp.start() else F.esp.stop() end end })
    EspEnabledToggle:AddKeyPicker("EspKey", {
        Default = "M", Mode = "Toggle", Text = "ESP key", SyncToggleState = true,
    })

    TabEspPlayers:AddDivider()

    TabEspPlayers:AddToggle("EspBox", { Text = "Boxes",
        Default = F.esp.settings.BoxESP, Callback = F.esp.setBox })
    TabEspPlayers:AddDropdown("EspBoxStyle", {
        Values = { "Corners", "Full" }, Default = F.esp.settings.BoxStyle,
        Text = "Box style", Callback = F.esp.setBoxStyle,
    })

    TabEspPlayers:AddToggle("EspNames", { Text = "Names",
        Default = F.esp.settings.NameESP, Callback = F.esp.setNames })
    TabEspPlayers:AddToggle("EspHealth", { Text = "Health bars",
        Default = F.esp.settings.HealthESP, Callback = F.esp.setHealth })
    TabEspPlayers:AddToggle("EspHealthNum", { Text = "Health number",
        Default = F.esp.settings.HealthNum, Callback = F.esp.setHealthNum })
    TabEspPlayers:AddToggle("EspDistance", { Text = "Distance",
        Default = F.esp.settings.DistanceESP, Callback = F.esp.setDistance })

    TabEspPlayers:AddToggle("EspTracer", { Text = "Tracers",
        Default = F.esp.settings.TracerESP, Callback = F.esp.setTracer })
    TabEspPlayers:AddDropdown("EspTracerOrigin", {
        Values = { "Bottom", "Center", "Top", "Mouse" },
        Default = F.esp.settings.TracerOrigin,
        Text = "Tracer origin", Callback = F.esp.setTracerOrigin,
    })

    TabEspPlayers:AddToggle("EspSkeleton", { Text = "Skeleton",
        Default = F.esp.settings.SkeletonESP, Callback = F.esp.setSkeleton })
    TabEspPlayers:AddToggle("EspHeldItem", { Text = "Held item",
        Default = F.esp.settings.HeldItem, Callback = F.esp.setHeldItem })
    TabEspPlayers:AddToggle("EspTeamColors", { Text = "Team colors",
        Default = F.esp.settings.TeamCheck, Callback = F.esp.setTeamCheck })

    -- ---------------- RIGHT TABBOX ----------------
    local Right = Tabs.Visual:AddRightTabbox()

    -- Camera
    local TabCamera = Right:AddTab("Camera")

    local FreecamToggle = TabCamera:AddToggle("Freecam", { Text = "Freecam",
        Default = false,
        Callback = function(v) if v then F.freecam.start() else F.freecam.stop() end end })
    FreecamToggle:AddKeyPicker("FreecamKey", {
        Default = "L", Mode = "Toggle", Text = "Freecam key", SyncToggleState = true,
    })

    TabCamera:AddToggle("Zoom", { Text = "Extended zoom", Default = false,
        Callback = function(v) if v then F.zoom.start() else F.zoom.stop() end end })

    TabCamera:AddDivider()

    TabCamera:AddSlider("Fov", { Text = "FOV", Default = F.fov.get(),
        Min = 30, Max = 120, Rounding = 0, Callback = F.fov.set })

    -- Atmosphere
    local TabAtmo = Right:AddTab("Atmosphere")

    TabAtmo:AddSlider("FogStart", { Text = "Fog start",
        Default = math.min(Lighting.FogStart, 5000), Min = 0, Max = 5000, Rounding = 0,
        Callback = function(v) Lighting.FogStart = v end })
    TabAtmo:AddSlider("FogEnd", { Text = "Fog end",
        Default = math.min(Lighting.FogEnd, 50000), Min = 0, Max = 50000, Rounding = 0,
        Callback = function(v) Lighting.FogEnd = v end })
    TabAtmo:AddLabel("Fog color"):AddColorPicker("FogColor", {
        Default = Lighting.FogColor, Title = "Fog color",
        Callback = function(c) Lighting.FogColor = c end,
    })

    TabAtmo:AddDivider()

    TabAtmo:AddButton({ Text = "Clear fog", Func = function()
        Lighting.FogStart = 0
        Lighting.FogEnd   = 100000
        if Options.FogStart then Options.FogStart:SetValue(0) end
        if Options.FogEnd   then Options.FogEnd:SetValue(50000) end
    end })

    -- World ESP
    local TabEspWorld = Right:AddTab("World ESP")

    TabEspWorld:AddToggle("EspChams", { Text = "Chams",
        Default = F.esp.settings.ChamsEnabled, Callback = F.esp.setChams })
    TabEspWorld:AddDropdown("EspChamsStyle", {
        Values = { "Overlay", "Occluded", "Outline" },
        Default = F.esp.settings.ChamsStyle,
        Text = "Chams style", Callback = F.esp.setChamsStyle,
    })

    TabEspWorld:AddDivider()

    TabEspWorld:AddToggle("EspTracerHist", { Text = "Tracer history",
        Default = F.esp.settings.TracerHistory, Callback = F.esp.setTracerHistory })
    TabEspWorld:AddSlider("EspTracerHistLen", { Text = "History length",
        Default = F.esp.settings.TracerHistLen, Min = 0.5, Max = 10, Rounding = 1,
        Suffix = " s", Callback = F.esp.setTracerHistLen })

    TabEspWorld:AddDivider()

    TabEspWorld:AddToggle("EspSelf", { Text = "Self ESP",
        Default = F.esp.settings.SelfESP, Callback = F.esp.setSelf })
end

-- ============================================================
--  MOVEMENT TAB
-- ============================================================
do
    local Move = Tabs.Movement:AddLeftGroupbox("Movement")

    local FlyToggle = Move:AddToggle("Fly", { Text = "Fly", Default = false,
        Callback = function(v) if v then F.fly.start() else F.fly.stop() end end })
    FlyToggle:AddKeyPicker("FlyKey", {
        Default = "Z", Mode = "Toggle", Text = "Fly key", SyncToggleState = true,
    })
    Move:AddSlider("FlySpeed", { Text = "Fly speed", Default = F.fly.getSpeed(),
        Min = 5, Max = 500, Rounding = 0, Callback = F.fly.setSpeed })

    local SpeedToggle = Move:AddToggle("Speed", { Text = "Speed", Default = false,
        Callback = function(v) if v then F.speed.start(F.speed.getMultiplier()) else F.speed.stop() end end })
    SpeedToggle:AddKeyPicker("SpeedKey", {
        Default = "X", Mode = "Toggle", Text = "Speed key", SyncToggleState = true,
    })
    Move:AddSlider("SpeedMult", { Text = "Speed multiplier", Default = F.speed.getMultiplier(),
        Min = 1, Max = 20, Rounding = 1, Suffix = "x", Callback = F.speed.setMultiplier })

    Move:AddToggle("Bhop", { Text = "Bunnyhop", Default = false,
        Callback = function(v) if v then F.bhop.start() else F.bhop.stop() end end })

    Move:AddToggle("InfJump",    { Text = "Infinite jump", Default = false,
        Callback = function(v) if v then F.infJump.start() else F.infJump.stop() end end })
    Move:AddToggle("AntiAfk",    { Text = "Anti-AFK",      Default = false,
        Callback = function(v) if v then F.antiAfk.start() else F.antiAfk.stop() end end })

    local ClickTpToggle = Move:AddToggle("ClickTp", { Text = "Click TP", Default = false,
        Callback = function(v) if v then F.clickTp.start() else F.clickTp.stop() end end })
    ClickTpToggle:AddKeyPicker("ClickTpKey", {
        Default = "K", Mode = "Toggle", Text = "Click TP key", SyncToggleState = true,
    })

    local NoclipToggle = Move:AddToggle("Noclip", { Text = "Noclip", Default = false,
        Callback = function(v) if v then F.noclip.start() else F.noclip.stop() end end })
    NoclipToggle:AddKeyPicker("NoclipKey", {
        Default = "U", Mode = "Toggle", Text = "Noclip key", SyncToggleState = true,
    })

    Move:AddToggle("AutoRespawn",{ Text = "Auto-respawn",  Default = false,
        Callback = function(v) if v then F.autoRespawn.start() else F.autoRespawn.stop() end end })

    -- right side: extras (spin/flip/ice + blink)
    local Extras = Tabs.Movement:AddRightGroupbox("Extras")

    Extras:AddToggle("Spin", { Text = "Spin", Default = false,
        Callback = function(v) if v then F.spin.start() else F.spin.stop() end end })
    Extras:AddSlider("SpinSpeed", { Text = "Spin speed", Default = 50,
        Min = 1, Max = 200, Rounding = 0, Callback = F.spin.setSpeed })

    Extras:AddToggle("Flip", { Text = "Upside down",
        Default = false,
        Callback = function(v) if v then F.flip.start() else F.flip.stop() end end })

    Extras:AddToggle("Ice", { Text = "Ice slide", Default = false,
        Callback = function(v) if v then F.ice.start() else F.ice.stop() end end })
    Extras:AddSlider("IceSlide", { Text = "Slide friction", Default = 0.98,
        Min = 0.5, Max = 0.99, Rounding = 2, Callback = F.ice.setSlide })

    Extras:AddDivider()

    Extras:AddButton({ Text = "Blink forward", Func = F.blink.fire })
    Extras:AddSlider("BlinkDist", { Text = "Blink distance", Default = F.blink.getDistance(),
        Min = 1, Max = 200, Rounding = 0, Callback = F.blink.setDistance })
end

-- ============================================================
--  PLAYERS TAB
-- ============================================================
do
    local P = Tabs.Players:AddLeftGroupbox("Actions")

    local _selected = nil
    local _selectedLabel = P:AddLabel("Selected: none")
    local _playerButtons = {}  -- map [Player] = LinoriaLib button object

    local function refreshSelectedLabel()
        if _selected and _selected.Parent then
            _selectedLabel:SetText("Selected: " .. _selected.Name)
        else
            _selectedLabel:SetText("Selected: none")
        end
    end

    local function selectPlayer(pl)
        _selected = pl
        refreshSelectedLabel()
    end

    P:AddDivider()

    P:AddButton({ Text = "Goto",  Func = function()
        if _selected then F.players.goto(_selected)
        else Library:Notify("No player selected", 2) end
    end })
    :AddButton({ Text = "View",  Func = function()
        if _selected then F.players.view(_selected)
        else Library:Notify("No player selected", 2) end
    end })

    P:AddButton({ Text = "Fling", Func = function()
        if not _selected then Library:Notify("No player selected", 2); return end
        F.players.fling(_selected)
        Library:Notify("Flinging " .. _selected.Name, 3)
    end })

    P:AddDivider()

    P:AddButton({ Text = "Reset camera view", Func = function()
        workspace.CurrentCamera.CameraSubject =
            LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    end })

    -- right side: live player list
    local List = Tabs.Players:AddRightGroupbox("Players")
    List:AddLabel("Click a player to select them")
    List:AddDivider()

    -- alphabetical order via LayoutOrder so the underlying UIListLayout sorts
    -- buttons without us having to destroy + recreate them on every join
    local function reorderPlayers()
        local names = {}
        for plr, _ in pairs(_playerButtons) do
            if plr.Parent then table.insert(names, plr.Name) end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        local rank = {}
        for i, n in ipairs(names) do rank[n] = i end
        for plr, btn in pairs(_playerButtons) do
            local order = rank[plr.Name]
            if btn and btn.Outer and order then
                pcall(function() btn.Outer.LayoutOrder = order end)
            end
        end
    end

    local function removePlayerButton(pl)
        local b = _playerButtons[pl]
        if b and b.Outer then pcall(function() b.Outer:Destroy() end) end
        _playerButtons[pl] = nil
        reorderPlayers()
    end

    local function addPlayerButton(pl)
        if pl == LocalPlayer then return end
        if _playerButtons[pl] then return end
        local btn = List:AddButton({ Text = pl.Name, Func = function()
            selectPlayer(pl)
        end })
        _playerButtons[pl] = btn
        reorderPlayers()
    end

    for _, pl in ipairs(Players:GetPlayers()) do addPlayerButton(pl) end

    Players.PlayerAdded:Connect(function(pl)
        if Library.Unloaded then return end
        addPlayerButton(pl)
    end)
    Players.PlayerRemoving:Connect(function(pl)
        removePlayerButton(pl)
        if _selected == pl then selectPlayer(nil) end
    end)
end

-- ============================================================
--  MISC TAB  (one-shot actions)
-- ============================================================
do
    local Act = Tabs.Misc:AddLeftGroupbox("Actions")

    Act:AddButton({ Text = "Respawn", Func = F.respawn.fire })

    Act:AddDivider()

    Act:AddButton({ Text = "Anti VC ban", DoubleClick = true,
        Func = function()
            F.antiVcBan.fire()
            Library:Notify("Anti VC ban running — wait ~7s", 5)
        end,
    })

    Act:AddDivider()

    Act:AddButton({ Text = "PANIC — disable everything", DoubleClick = true,
        Func = function()
            F.disableAll()
            for _, name in ipairs({
                "Fly","Speed","Bhop","InfJump","AntiAfk","ClickTp","Noclip","AutoRespawn",
                "Fullbright","Freecam","Zoom","Spin","Flip","Ice",
                "AimEnabled","TrigEnabled","CamEnabled",
                "RageSilentForce","RageAutoShoot","RageOrbit","RageFaceTarget","RageCamSnap",
                "EspEnabled",
            }) do
                if Toggles[name] then Toggles[name]:SetValue(false) end
            end
            Library:Notify("All features disabled", 3)
        end,
    })

    -- respawn keybind (Hold)
    Act:AddLabel("Respawn key"):AddKeyPicker("RespawnKey", {
        Default = "T", Mode = "Hold", Text = "Respawn",
    })
    bindFireKey("RespawnKey", F.respawn.fire)

    -- =================== SERVER HOPPER ===================
    local Srv = Tabs.Misc:AddLeftGroupbox("Server hop")

    local _selectedServer = nil
    local _serverSelLabel = Srv:AddLabel("Selected: none")
    local function refreshSelLabel()
        if _selectedServer then
            _serverSelLabel:SetText(("Selected: #%d  %d/%d  %dms"):format(
                _selectedServer.index or 0,
                _selectedServer.playing,
                _selectedServer.maxPlayers,
                math.floor(_selectedServer.ping or 0)))
        else
            _serverSelLabel:SetText("Selected: none")
        end
    end

    Srv:AddDivider()

    Srv:AddButton({ Text = "Rejoin current server", Func = F.servers.rejoin })

    Srv:AddButton({ Text = "Join selected", Func = function()
        if not _selectedServer then Library:Notify("No server selected", 2); return end
        Library:Notify("Teleporting...", 3)
        F.servers.join(_selectedServer.jobId)
    end })

    -- right side: live server list, button per server (Players-tab pattern)
    local List = Tabs.Misc:AddRightGroupbox("Servers")
    List:AddLabel("Click Refresh, then click a server to select")
    List:AddDivider()

    local _serverButtons = {}

    local function clearServerButtons()
        for _, b in ipairs(_serverButtons) do
            if b and b.Outer then pcall(function() b.Outer:Destroy() end) end
        end
        _serverButtons = {}
    end

    local function refreshServerList()
        Library:Notify("Fetching servers...", 2)
        task.spawn(function()
            local list = F.servers.list(2)
            clearServerButtons()
            _selectedServer = nil
            refreshSelLabel()
            if #list == 0 then
                Library:Notify("No servers found", 2)
                return
            end
            for i, s in ipairs(list) do
                s.index = i
                local btn = List:AddButton({
                    Text = ("#%d  %d/%d  %dms"):format(i, s.playing, s.maxPlayers, math.floor(s.ping)),
                    Func = function()
                        _selectedServer = s
                        refreshSelLabel()
                    end,
                })
                table.insert(_serverButtons, btn)
            end
            Library:Notify(("Found %d servers"):format(#list), 2)
        end)
    end

    Srv:AddButton({ Text = "Refresh list", Func = refreshServerList })
end

-- ============================================================
--  GAMES TAB  (per-game features)
-- ============================================================
do
    local HC_PLACE_IDS = { 138995385694035, 9825515356 }
    local function inHoodCustoms()
        for _, id in ipairs(HC_PLACE_IDS) do
            if game.PlaceId == id then return true end
        end
        return false
    end

    local HC = Tabs.Games:AddLeftGroupbox("Hood Customs")

    if not inHoodCustoms() then
        HC:AddLabel(
            ("Hood Customs only.\nCurrent place: %d\nValid: %d, %d"):format(
                game.PlaceId, HC_PLACE_IDS[1], HC_PLACE_IDS[2]),
            true)
    else

    -- ---- Ragebot (HC-specific) ----
    HC:AddLabel("Ragebot")
    HC:AddToggle("RageSkipKnocked", {
        Text = "Skip knocked targets",
        Default = false,
        Callback = F.ragebot.setSkipKnocked,
    })

    HC:AddDivider()

    -- ---- Auto stomp ----
    HC:AddLabel("Auto stomp")
    HC:AddToggle("HCAutoStomp", { Text = "Auto stomp",
        Default = false,
        Callback = function(v)
            if v then F.games.hoodCustoms.autoStomp.start()
            else      F.games.hoodCustoms.autoStomp.stop() end
        end,
    })

    HC:AddSlider("HCAutoStompRadius", { Text = "Stomp radius",
        Default = F.games.hoodCustoms.autoStomp.getRadius(),
        Min = 1, Max = 20, Rounding = 1,
        Suffix = " studs",
        Callback = F.games.hoodCustoms.autoStomp.setRadius })

    HC:AddSlider("HCAutoStompInterval", { Text = "Min interval",
        Default = F.games.hoodCustoms.autoStomp.getInterval(),
        Min = 0, Max = 1, Rounding = 2,
        Suffix = " s",
        Callback = F.games.hoodCustoms.autoStomp.setInterval })

    HC:AddToggle("HCAutoStompRage", {
        Text = "Auto stomp ragebot targets",
        Default = false,
        Callback = F.games.hoodCustoms.autoStomp.setRageTargets,
    })

    HC:AddDivider()

    HC:AddToggle("HCAutoReload", { Text = "Auto reload",
        Default = false,
        Callback = function(v)
            if v then F.games.hoodCustoms.autoReload.start()
            else      F.games.hoodCustoms.autoReload.stop() end
        end,
    })

    HC:AddSlider("HCAutoReloadThreshold", { Text = "Reload at",
        Default = F.games.hoodCustoms.autoReload.getThreshold(),
        Min = 0, Max = 10, Rounding = 0,
        Callback = F.games.hoodCustoms.autoReload.setThreshold })

    HC:AddSlider("HCAutoReloadCooldown", { Text = "Cooldown",
        Default = F.games.hoodCustoms.autoReload.getCooldown(),
        Min = 0.1, Max = 10, Rounding = 1, Suffix = " s",
        Callback = F.games.hoodCustoms.autoReload.setCooldown })

    HC:AddLabel("Reload key"):AddKeyPicker("HCAutoReloadKey", {
        Default = "R", NoUI = true, Text = "Reload key",
    })
    Options.HCAutoReloadKey:OnChanged(function()
        F.games.hoodCustoms.autoReload.setKey(Options.HCAutoReloadKey.Value)
    end)

    HC:AddDivider()

    -- ---- Knife reach ----
    HC:AddLabel("Knife reach")
    HC:AddToggle("HCKnifeReach", { Text = "Enable knife reach",
        Default = false,
        Callback = function(v)
            if v then F.games.hoodCustoms.knifeReach.start()
            else      F.games.hoodCustoms.knifeReach.stop() end
        end })

    HC:AddSlider("HCKnifeReachSize", { Text = "Hitbox size",
        Default = F.games.hoodCustoms.knifeReach.getSize(),
        Min = 1, Max = F.games.hoodCustoms.knifeReach.maxSize, Rounding = 1,
        Suffix = " studs",
        Callback = F.games.hoodCustoms.knifeReach.setSize })

    HC:AddToggle("HCKnifeReachVis", { Text = "Visualize hitbox",
        Default = false,
        Callback = F.games.hoodCustoms.knifeReach.setVisualize })

    HC:AddDivider()

    -- ---- Anti-AFK tag ----
    HC:AddLabel("Anti-AFK")
    HC:AddToggle("HCAntiAfkTag", { Text = "Anti-AFK tag",
        Default = true,
        Callback = function(v)
            if v then F.games.hoodCustoms.antiAfkTag.start()
            else      F.games.hoodCustoms.antiAfkTag.stop() end
        end,
    })

    HC:AddDivider()

    -- ---- Godmode ----
    HC:AddLabel("Godmode")
    HC:AddToggle("HCGodmode", { Text = "Godmode (legs)",
        Default = false,
        Callback = function(v)
            if v then F.games.hoodCustoms.godmode.start()
            else      F.games.hoodCustoms.godmode.stop() end
        end,
    })

    end -- close: if not inHoodCustoms() then ... else ...
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

-- KeybindFrame visibility is wired up to a Config toggle further down

Library:OnUnload(function()
    pcall(function() WatermarkConn:Disconnect() end)
    pcall(F.disableAll)
    Library.Unloaded = true
    print("[cclosure.vip] unloaded")
end)

-- ============================================================
--  UI SETTINGS  (theme + saves + menu keybind + unload)
-- ============================================================
local Menu = Tabs.Config:AddLeftGroupbox("Menu")

Menu:AddToggle("ShowKeybindFrame", { Text = "Show keybinds panel", Default = true,
    Callback = function(v)
        if Library.KeybindFrame then Library.KeybindFrame.Visible = v end
    end })

Menu:AddButton({ Text = "Unbind all keybinds", DoubleClick = true,
    Func = function()
        local n = 0
        for idx, opt in pairs(Options) do
            if opt and opt.Type == "KeyPicker" and idx ~= "MenuKeybind" then
                pcall(function() opt:SetValue({ "None", opt.Mode or "Toggle" }) end)
                n = n + 1
            end
        end
        Library:Notify(("Unbound %d keybinds"):format(n), 3)
    end })

Menu:AddDivider()

Menu:AddButton({ Text = "Unload script", Func = function() Library:Unload() end })

Menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
    Default = "Insert", NoUI = true, Text = "Menu keybind",
})
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("cclosure.vip")
SaveManager:SetFolder("cclosure.vip/configs")

SaveManager:BuildConfigSection(Tabs.Config)
ThemeManager:ApplyToTab(Tabs.Config)

SaveManager:LoadAutoloadConfig()

Library:Notify("cclosure.vip loaded — press End to toggle the menu", 4)
