-- ============================================================
--  cclosure.vip   //   @vampire   //   LinoriaLib build
--  executor: Potassium
-- ============================================================

local _functionsSrc = game:HttpGet("https://raw.githubusercontent.com/anxiousgh/hfgfghoifghfgkm-h/main/functions.lua?_=" .. tick())
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
--  of the picker's mode - so one-shot actions don't visually toggle on/off
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

    Tgt:AddDropdown("RagePriority", {
        Values  = { "Closest", "Mouse", "Camera", "LowestHP", "HighestThreat" },
        Default = "Closest",
        Text    = "Target priority",
        Callback = F.ragebot.setPriority,
    })
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
    Tgt:AddLabel("Line color"):AddColorPicker("RageLineColor", {
        Default = F.ragebot.settings.LineColor, Title = "Line color",
        Callback = F.ragebot.setLineColor })
    Tgt:AddLabel("Outline color"):AddColorPicker("RageOutlineColor", {
        Default = F.ragebot.settings.OutlineColor, Title = "Outline color",
        Callback = F.ragebot.setOutlineColor })
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

    -- =================== AUTO-TARGETER (persistent list) ===================
    Tgt:AddDivider()
    Tgt:AddLabel("Auto-targeter (persistent UserId list)")
    Tgt:AddToggle("AutoTargeterEnabled", { Text = "Enable",
        Default = false,
        Callback = function(v) F.autoTargeter.setEnabled(v) end,
    })

    local function labelForEntry(entry)
        return entry.username .. " (" .. tostring(entry.userId) .. ")"
    end
    local labelToId = {}  -- ["Name (uid)"] -> uid

    local function rebuildLists()
        -- current-server players dropdown (excludes ourselves)
        local playerNames = {}
        for _, p in ipairs(LocalPlayer.Parent:GetPlayers()) do
            if p ~= LocalPlayer then table.insert(playerNames, p.Name) end
        end
        table.sort(playerNames)
        if #playerNames == 0 then playerNames = { "(no players)" } end
        if Options.AutoTargetPick then Options.AutoTargetPick:SetValues(playerNames) end

        -- saved list dropdown
        labelToId = {}
        local labels = {}
        for _, e in ipairs(F.autoTargeter.list()) do
            local lbl = labelForEntry(e)
            labelToId[lbl] = e.userId
            table.insert(labels, lbl)
        end
        if #labels == 0 then labels = { "(empty)" } end
        if Options.AutoTargetSaved then Options.AutoTargetSaved:SetValues(labels) end
    end

    Tgt:AddDropdown("AutoTargetPick", {
        Values = { "(no players)" }, Default = "(no players)",
        Text = "Players in server",
    })
    Tgt:AddButton({ Text = "Add picked", Func = function()
        local v = Options.AutoTargetPick and Options.AutoTargetPick.Value
        if not v or v == "(no players)" then return end
        if F.autoTargeter.add(v) then
            Library:Notify("Saved " .. v, 2)
            rebuildLists()
        else
            Library:Notify("Failed to save " .. v, 2)
        end
    end })
    :AddButton({ Text = "Refresh", Func = rebuildLists })

    Tgt:AddInput("AutoTargetInput", {
        Default = "", Text = "Username or UserId",
        Placeholder = "type and press add",
        Finished = false,
    })
    Tgt:AddButton({ Text = "Add typed", Func = function()
        local v = Options.AutoTargetInput and Options.AutoTargetInput.Value
        if not v or v == "" then return end
        task.spawn(function()
            if F.autoTargeter.add(v) then
                Library:Notify("Saved " .. v, 2)
                rebuildLists()
            else
                Library:Notify("Couldn't resolve " .. v, 3)
            end
        end)
    end })

    Tgt:AddDropdown("AutoTargetSaved", {
        Values = { "(empty)" }, Default = "(empty)",
        Text = "Saved targets",
    })
    Tgt:AddButton({ Text = "Remove", Func = function()
        local v = Options.AutoTargetSaved and Options.AutoTargetSaved.Value
        local uid = labelToId[v]
        if not uid then return end
        F.autoTargeter.remove(uid)
        Library:Notify("Removed " .. v, 2)
        rebuildLists()
    end })
    :AddButton({ Text = "Clear all", Func = function()
        F.autoTargeter.clear()
        Library:Notify("Cleared auto-target list", 2)
        rebuildLists()
    end })

    -- keep player dropdown fresh when players join/leave
    LocalPlayer.Parent.PlayerAdded:Connect(function() task.defer(rebuildLists) end)
    LocalPlayer.Parent.PlayerRemoving:Connect(function() task.defer(rebuildLists) end)
    task.defer(rebuildLists)

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

    -- Auto-equip a chosen gun whenever a target enters AutoShootDist
    -- range. Shares the tool list with the AutoEquip dropdown below,
    -- so "Refresh tool list" repopulates this one too. While this
    -- toggle is on, the autoshoot heartbeat will swap to the chosen
    -- tool BEFORE firing the click.
    AutoT:AddToggle("RageAutoShootEquip", { Text = "Auto equip on range",
        Default = F.ragebot.settings.AutoShootEquip,
        Callback = F.ragebot.setAutoShootEquip })
    AutoT:AddDropdown("RageAutoShootEquipTool", {
        Values = { "(refresh)" }, Default = "(refresh)",
        Text = "Auto equip tool",
        Callback = function(v) F.ragebot.setAutoShootEquipTool(v == "(refresh)" and "" or v) end,
    })

    AutoT:AddDivider()
    AutoT:AddLabel("Auto equip")

    AutoT:AddDropdown("AutoEquipTool", {
        Values = { "(refresh)" }, Default = "(refresh)",
        Text = "Tool",
        Callback = function(v) F.autoEquip.setName(v) end,
    })

    -- Preserve current selection on refresh - equipping moves a tool from the
    -- backpack into the character, so the list rebuilds and the user's pick
    -- would otherwise jump to whatever ends up alphabetically first. Also
    -- repopulates the auto-weapon-switch dropdowns (close/medium/long) with
    -- a "(none)"-prefixed variant of the list. Dropdowns that don't exist
    -- yet (first call before they're added) are silently skipped.
    local function refreshToolList()
        local list = F.autoEquip.list()
        if #list == 0 then list = { "(no tools)" } end

        if Options.AutoEquipTool then
            local current = Options.AutoEquipTool.Value
            Options.AutoEquipTool:SetValues(list)
            local keep = false
            for _, n in ipairs(list) do if n == current then keep = true; break end end
            Options.AutoEquipTool:SetValue(keep and current or list[1])
        end

        -- list with leading "(none)" sentinel for the weapon-switch slots
        local listWithNone = { "(none)" }
        for _, n in ipairs(list) do table.insert(listWithNone, n) end

        local function setWithNone(opt)
            if not opt then return end
            local cur = opt.Value
            opt:SetValues(listWithNone)
            local keep = false
            for _, n in ipairs(listWithNone) do if n == cur then keep = true; break end end
            opt:SetValue(keep and cur or "(none)")
        end
        setWithNone(Options.AutoWSClose)
        setWithNone(Options.AutoWSMedium)
        setWithNone(Options.AutoWSLong)

        -- Ragebot auto-equip-on-shoot dropdown: same tool list, but
        -- uses "(refresh)" as the empty sentinel so we don't clash
        -- with the auto-weapon-switch "(none)" sentinel.
        if Options.RageAutoShootEquipTool then
            local cur = Options.RageAutoShootEquipTool.Value
            local listWithRefresh = { "(refresh)" }
            for _, n in ipairs(list) do table.insert(listWithRefresh, n) end
            Options.RageAutoShootEquipTool:SetValues(listWithRefresh)
            local keep = false
            for _, n in ipairs(listWithRefresh) do if n == cur then keep = true; break end end
            Options.RageAutoShootEquipTool:SetValue(keep and cur or "(refresh)")
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

    AutoT:AddDivider()
    AutoT:AddLabel("Auto weapon switch")

    -- Three tool-name dropdowns + two distance thresholds. The dropdowns
    -- share their value-list with the AutoEquipTool dropdown so the
    -- "Refresh tool list" button repopulates all four at once. Tools
    -- not currently in your inventory still equip if you have them
    -- (the dropdown just shows current snapshot for convenience).
    AutoT:AddToggle("AutoWeaponSwitch", { Text = "Enable",
        Default = false,
        Callback = function(v)
            if v then F.autoWeaponSwitch.start() else F.autoWeaponSwitch.stop() end
        end })

    AutoT:AddDropdown("AutoWSClose", {
        Values   = { "(none)" },
        Default  = "(none)",
        Text     = "Close-range tool",
        Callback = function(v) F.autoWeaponSwitch.setClose(v == "(none)" and "" or v) end,
    })
    AutoT:AddSlider("AutoWSCloseMax", {
        Text     = "Close max distance",
        Default  = F.autoWeaponSwitch.getCloseMax(),
        Min = 1, Max = 500, Rounding = 0,
        Callback = F.autoWeaponSwitch.setCloseMax,
    })

    AutoT:AddDropdown("AutoWSMedium", {
        Values   = { "(none)" },
        Default  = "(none)",
        Text     = "Medium-range tool",
        Callback = function(v) F.autoWeaponSwitch.setMedium(v == "(none)" and "" or v) end,
    })
    AutoT:AddSlider("AutoWSMediumMax", {
        Text     = "Medium max distance",
        Default  = F.autoWeaponSwitch.getMediumMax(),
        Min = 1, Max = 1000, Rounding = 0,
        Callback = F.autoWeaponSwitch.setMediumMax,
    })

    AutoT:AddDropdown("AutoWSLong", {
        Values   = { "(none)" },
        Default  = "(none)",
        Text     = "Long-range tool",
        Callback = function(v) F.autoWeaponSwitch.setLong(v == "(none)" and "" or v) end,
    })

    AutoT:AddSlider("AutoWSCooldown", {
        Text     = "Switch cooldown",
        Default  = 0.5, Min = 0.05, Max = 3, Rounding = 2, Suffix = " s",
        Callback = F.autoWeaponSwitch.setCooldown,
    })

    -- One-shot initial population only. We DO NOT auto-refresh on
    -- backpack changes or respawn anymore - that was clobbering the
    -- user's pick every death (tools clear and re-add to Backpack,
    -- the dropdown would reset to the first alphabetical tool).
    -- User has to press "Refresh tool list" to update.
    task.defer(refreshToolList)

    -- =================== VISIBLE CHECK (global, below tabboxes) ===================
    -- One master toggle that flips visibility-gating on ALL four
    -- features (aimbot, triggerbot, camlock, ragebot autoshoot).
    -- Strict + Origin live here too since both apply globally.
    local Vis = Tabs.Combat:AddLeftGroupbox("Visible Check")

    local function setAllVisible(v)
        F.aimbot.setVisibleCheck(v)
        F.triggerbot.setVisibleCheck(v)
        F.camLock.setVisibleCheck(v)
        F.ragebot.setAutoShootVis(v)
    end

    Vis:AddToggle("VisibleCheckMaster", { Text = "Enable visible check",
        Default = false,
        Callback = setAllVisible })
    Vis:AddToggle("StrictVisCheck", { Text = "Strict (block see-through walls)",
        Default = false,
        Callback = F.utils.setStrictVisibleCheck })
    Vis:AddDropdown("VisOrigin", {
        Values  = { "Camera", "Head", "Tool" },
        Default = "Camera",
        Text    = "Origin",
        Callback = F.utils.setVisibleOrigin,
    })
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

    TabEspPlayers:AddDivider()
    TabEspPlayers:AddLabel("Colors")

    -- Enemy / team / neutral colors. Render reads EspSettings live,
    -- so pickers update instantly without re-toggling ESP.
    TabEspPlayers:AddLabel("Enemy"):AddColorPicker("EspEnemyColor", {
        Default = F.esp.settings.EnemyColor, Title = "Enemy color",
        Callback = F.esp.setEnemyColor })
    TabEspPlayers:AddLabel("Team"):AddColorPicker("EspTeamColor", {
        Default = F.esp.settings.TeamColor, Title = "Team color",
        Callback = F.esp.setTeamColor })
    TabEspPlayers:AddLabel("Neutral"):AddColorPicker("EspNeutralColor", {
        Default = F.esp.settings.NeutralColor, Title = "Neutral color",
        Callback = F.esp.setNeutralColor })
    TabEspPlayers:AddLabel("Tracer"):AddColorPicker("EspTracerColor", {
        Default = F.esp.settings.TracerColor, Title = "Tracer color",
        Callback = F.esp.setTracerColor })

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
    TabEspWorld:AddLabel("Chams fill"):AddColorPicker("EspChamsFill", {
        Default = F.esp.settings.ChamsFill, Title = "Chams fill",
        Callback = F.esp.setChamsFill })
    TabEspWorld:AddLabel("Chams outline"):AddColorPicker("EspChamsOutline", {
        Default = F.esp.settings.ChamsOutline, Title = "Chams outline",
        Callback = F.esp.setChamsOutline })

    TabEspWorld:AddDivider()

    TabEspWorld:AddToggle("EspTracerHist", { Text = "Tracer history",
        Default = F.esp.settings.TracerHistory, Callback = F.esp.setTracerHistory })
    TabEspWorld:AddSlider("EspTracerHistLen", { Text = "History length",
        Default = F.esp.settings.TracerHistLen, Min = 0.5, Max = 10, Rounding = 1,
        Suffix = " s", Callback = F.esp.setTracerHistLen })

    TabEspWorld:AddDivider()

    TabEspWorld:AddToggle("EspSelf", { Text = "Self ESP",
        Default = F.esp.settings.SelfESP, Callback = F.esp.setSelf })

    TabEspWorld:AddDivider()
    TabEspWorld:AddLabel("Tool glow")
    TabEspWorld:AddToggle("ToolGlow", { Text = "Tool glow (equipped weapon)",
        Default = false,
        Callback = function(v) if v then F.toolGlow.start() else F.toolGlow.stop() end end })
    TabEspWorld:AddLabel("Fill"):AddColorPicker("ToolGlowFill", {
        Default = F.toolGlow.getFillColor(), Title = "Tool glow fill",
        Callback = F.toolGlow.setFillColor })
    TabEspWorld:AddLabel("Outline"):AddColorPicker("ToolGlowOutline", {
        Default = F.toolGlow.getOutlineColor(), Title = "Tool glow outline",
        Callback = F.toolGlow.setOutlineColor })
    TabEspWorld:AddSlider("ToolGlowFillT", { Text = "Fill transparency",
        Default = 0.35, Min = 0, Max = 1, Rounding = 2,
        Callback = F.toolGlow.setFillTransparency })
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
        Min = 5, Max = 3000, Rounding = 0, Callback = F.fly.setSpeed })

    -- Walkspeed: real Humanoid.WalkSpeed override with anti-restore.
    -- The loop re-asserts every time the game writes a different value,
    -- so games that clamp walkspeed (e.g. "you can't sprint while reloading")
    -- get overridden in real time.
    local WalkspeedToggle = Move:AddToggle("Walkspeed", { Text = "Walkspeed", Default = false,
        Callback = function(v) if v then F.walkspeed.start() else F.walkspeed.stop() end end })
    WalkspeedToggle:AddKeyPicker("WalkspeedKey", {
        Default = "C", Mode = "Toggle", Text = "Walkspeed key", SyncToggleState = true,
    })
    Move:AddSlider("WalkspeedVal", { Text = "Walkspeed value",
        Default = F.walkspeed.getValue(), Min = 8, Max = 1000, Rounding = 0,
        Callback = F.walkspeed.setValue })

    -- Jump power: real Humanoid.JumpPower override with anti-restore.
    -- Pairs with Force Jump if the game also disables the jump state.
    local JumpPowerToggle = Move:AddToggle("JumpPowerToggle", { Text = "Jump power", Default = false,
        Callback = function(v) if v then F.jumpPower.start() else F.jumpPower.stop() end end })
    JumpPowerToggle:AddKeyPicker("JumpPowerKey", {
        Default = "V", Mode = "Toggle", Text = "Jump power key", SyncToggleState = true,
    })
    Move:AddSlider("JumpPowerVal", { Text = "Jump power value",
        Default = F.jumpPower.getValue(), Min = 0, Max = 2000, Rounding = 0,
        Callback = F.jumpPower.setValue })

    -- CFrame speed: legacy speedhack that pushes HRP every frame based on
    -- camera direction + WASD. Doesn't touch Humanoid.WalkSpeed.
    local SpeedToggle = Move:AddToggle("Speed", { Text = "CFrame speed", Default = false,
        Callback = function(v) if v then F.cframeSpeed.start(F.cframeSpeed.getMultiplier()) else F.cframeSpeed.stop() end end })
    SpeedToggle:AddKeyPicker("SpeedKey", {
        Default = "X", Mode = "Toggle", Text = "CFrame speed key", SyncToggleState = true,
    })
    Move:AddSlider("SpeedMult", { Text = "CFrame speed multiplier", Default = F.cframeSpeed.getMultiplier(),
        Min = 1, Max = 100, Rounding = 1, Suffix = "x", Callback = F.cframeSpeed.setMultiplier })

    Move:AddToggle("Bhop", { Text = "Bunnyhop", Default = false,
        Callback = function(v) if v then F.bhop.start() else F.bhop.stop() end end })

    Move:AddToggle("InfJump",    { Text = "Infinite jump", Default = false,
        Callback = function(v) if v then F.infJump.start() else F.infJump.stop() end end })
    Move:AddToggle("ForceJump",  { Text = "Force enable jump", Default = false,
        Callback = function(v) if v then F.forceJump.start() else F.forceJump.stop() end end })
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

    -- Rocket jump: toggle gates Space-as-rocket-boost. Off = normal jump.
    -- On = pressing Space fires the rocket impulse instead. Manual fire
    -- button + tuning sliders are over in the right Extras groupbox.
    Move:AddToggle("RocketJump", {
        Text = "Rocket jump (on jump)",
        Default = false,
        Callback = function(v)
            if v then F.rocketJump.start() else F.rocketJump.stop() end
        end,
    })

    -- right side: extras (spin/flip/ice + blink)
    local Extras = Tabs.Movement:AddRightGroupbox("Extras")

    Extras:AddToggle("Spin", { Text = "Spin", Default = false,
        Callback = function(v) if v then F.spin.start() else F.spin.stop() end end })
    Extras:AddSlider("SpinSpeed", { Text = "Spin speed", Default = 50,
        Min = 1, Max = 1000, Rounding = 0, Callback = F.spin.setSpeed })

    -- orientation spoofs (flip / tilt / backwards) - mutually exclusive
    -- so the spoofs don't compound. Each writes a different rotation to
    -- the server-side HRP and restores the local one before the camera
    -- reads it (BindToRenderStep at First priority).
    local ORIENT_KEYS = { "Flip", "Tilt", "Backwards" }
    local function selectOrient(name)
        for _, k in ipairs(ORIENT_KEYS) do
            if k ~= name and Toggles[k] and Toggles[k].Value then
                Toggles[k]:SetValue(false)
            end
        end
    end

    Extras:AddToggle("Flip", { Text = "Upside down (180° X)",
        Default = false,
        Callback = function(v)
            if v then selectOrient("Flip"); F.flip.start() else F.flip.stop() end
        end,
    })
    Extras:AddToggle("Tilt", { Text = "Tilt sideways (90° Z)",
        Default = false,
        Callback = function(v)
            if v then selectOrient("Tilt"); F.tilt.start() else F.tilt.stop() end
        end,
    })
    Extras:AddToggle("Backwards", { Text = "Face backwards (180° Y)",
        Default = false,
        Callback = function(v)
            if v then selectOrient("Backwards"); F.backwards.start() else F.backwards.stop() end
        end,
    })

    Extras:AddToggle("Ice", { Text = "Ice slide", Default = false,
        Callback = function(v) if v then F.ice.start() else F.ice.stop() end end })
    Extras:AddSlider("IceSlide", { Text = "Slide friction", Default = 0.98,
        Min = 0.5, Max = 0.99, Rounding = 2, Callback = F.ice.setSlide })

    Extras:AddDivider()

    Extras:AddButton({ Text = "Blink forward", Func = F.blink.fire })
    Extras:AddSlider("BlinkDist", { Text = "Blink distance", Default = F.blink.getDistance(),
        Min = 1, Max = 1000, Rounding = 0, Callback = F.blink.setDistance })

    -- Rocket jump - manual fire button + force/bias sliders.
    -- The KeyPicker for it is up in the Move (left) groupbox.
    Extras:AddButton({ Text = "Rocket jump", Func = F.rocketJump.fire })
    Extras:AddSlider("RocketJumpForce", {
        Text = "Rocket force",
        Default = 200, Min = 50, Max = 10000, Rounding = 0,
        Callback = function(v) F.rocketJump.setForce(v) end,
    })
    Extras:AddSlider("RocketJumpUpBias", {
        Text = "Rocket up bias",
        Default = 0.4, Min = 0, Max = 1, Rounding = 2,
        Callback = function(v) F.rocketJump.setUpBias(v) end,
    })
end

-- Desync gets its own dedicated groupbox in the Movement tab.
-- NOTE: Voidspam lives in the Games -> Hood Customs tab because it
-- hooks the HC-specific MainEvent("Shoot") remote; sticking it here
-- would imply it works in any game. The mutex below treats the HC
-- voidspam toggle (HCVoidspam) as part of the same set so all four
-- desync toggles are mutually exclusive.
do
    local Desync = Tabs.Movement:AddRightGroupbox("Desync")

    -- Mutex - the new single "DesyncEnabled" toggle replaces the old
    -- per-mode toggles. HC voidspam + MM2 invisible still need to be
    -- mutually exclusive with us, so they're still tracked here.
    local DESYNC_KEYS = { "DesyncEnabled", "HCVoidspam", "MM2Invisible" }
    local function selectMode(name)
        for _, k in ipairs(DESYNC_KEYS) do
            if k ~= name and Toggles[k] and Toggles[k].Value then
                Toggles[k]:SetValue(false)
            end
        end
    end
    -- expose the mutex helper to other tabs (HC tab uses it for HCVoidspam)
    getgenv()._F_DESYNC_SELECT = selectMode

    -- Map mode-name -> start fn for the dropdown selection. Raknet is
    -- handled inline because its start can fail (needs executor support).
    local MODE_START = {
        Void     = function() F.desync.startVoid()     return true end,
        Sky      = function() F.desync.startSky()      return true end,
        Spin     = function() F.desync.startSpin()     return true end,
        Velocity = function() F.desync.startVelocity() return true end,
        Raknet   = function()
            local ok = F.desync.startRaknet()
            if not ok then
                Library:Notify("Raknet desync unavailable: executor doesn't expose `raknet`", 4)
            end
            return ok
        end,
    }
    local currentMode = "Void"

    Desync:AddDropdown("DesyncMode", {
        Values = { "Void", "Sky", "Spin", "Velocity", "Raknet" },
        Default = currentMode,
        Text = "Desync mode",
        Callback = function(v)
            currentMode = v
            -- if we're already active, restart in the new mode so the
            -- swap is instant instead of "off then re-toggle"
            if Toggles.DesyncEnabled and Toggles.DesyncEnabled.Value then
                F.desync.stop()
                local starter = MODE_START[currentMode]
                if starter and not starter() then
                    Toggles.DesyncEnabled:SetValue(false)
                end
            end
        end,
    })

    Desync:AddToggle("DesyncEnabled", { Text = "Enable desync",
        Default = false,
        Callback = function(v)
            if v then
                selectMode("DesyncEnabled")
                local starter = MODE_START[currentMode]
                if not starter or not starter() then
                    -- raknet failed or unknown mode - turn back off
                    Toggles.DesyncEnabled:SetValue(false)
                end
            else
                F.desync.stop()
            end
        end,
    }):AddKeyPicker("DesyncKey", {
        Default = "Y", Mode = "Toggle", Text = "Desync key",
        SyncToggleState = true,
    })

    Desync:AddDivider()

    do
        local minStuds, maxStuds = 5000, 20000
        local function push() F.desync.setRange(minStuds, maxStuds) end
        Desync:AddSlider("DesyncMinStuds", {
            Text     = "Void min distance",
            Default  = 5000, Min = 500, Max = 100000, Rounding = 0,
            Callback = function(v) minStuds = v; push() end,
        })
        Desync:AddSlider("DesyncMaxStuds", {
            Text     = "Void max distance",
            Default  = 20000, Min = 500, Max = 100000, Rounding = 0,
            Callback = function(v) maxStuds = v; push() end,
        })
    end

    Desync:AddSlider("DesyncSpinSpeed", {
        Text     = "Spin speed (deg/frame)",
        Default  = 47, Min = 1, Max = 360, Rounding = 0,
        Callback = function(v) F.desync.setSpinSpeed(v) end,
    })
    Desync:AddSlider("DesyncVelocityMag", {
        Text     = "Velocity magnitude",
        Default  = 16384, Min = 100, Max = 100000, Rounding = 0,
        Callback = function(v) F.desync.setVelocityMag(v) end,
    })
    Desync:AddSlider("DesyncSkyHeight", {
        Text     = "Sky height",
        Default  = 5000, Min = 50, Max = 100000, Rounding = 0,
        Callback = function(v) F.desync.setSkyHeight(v) end,
    })

    -- =================== PULSE LAGSWITCH ===================
    -- Drops outgoing physics packet (0x1B) on an on/off duty cycle.
    -- ONLY character position is affected - chat, remotes, hit
    -- registrations, etc. all replicate normally. Server sees you
    -- stuttering between frozen and your real position; combined
    -- with movement, this is nearly impossible to aim at.
    local Pulse = Tabs.Movement:AddRightGroupbox("Pulse lagswitch")
    Pulse:AddToggle("PulseLagswitch", { Text = "Enable",
        Default = false,
        Callback = function(v)
            if v then
                local ok = F.pulseLagswitch.start()
                if not ok then
                    Toggles.PulseLagswitch:SetValue(false)
                    Library:Notify("Pulse lagswitch unavailable: executor doesn't expose `raknet`", 4)
                end
            else
                F.pulseLagswitch.stop()
            end
        end,
    })
    Pulse:AddSlider("PulseLagswitchOnMs", {
        Text     = "Blocked phase (ms)",
        Default  = 200, Min = 10, Max = 60000, Rounding = 0,
        Callback = function(v) F.pulseLagswitch.setOnMs(v) end,
    })
    Pulse:AddSlider("PulseLagswitchOffMs", {
        Text     = "Released phase (ms)",
        Default  = 100, Min = 10, Max = 60000, Rounding = 0,
        Callback = function(v) F.pulseLagswitch.setOffMs(v) end,
    })
    Pulse:AddToggle("PulseLagswitchVisual", { Text = "Show server-position marker",
        Default = false,
        Callback = function(v) F.pulseLagswitch.setVisualEnabled(v) end,
    })
end

-- ============================================================
--  PLAYERS TAB
-- ============================================================
do
    local P = Tabs.Players:AddLeftGroupbox("Actions")

    local _selected = nil
    local _selectedLabel = P:AddLabel("Selected: none")
    -- pool: name → { btn = LinoriaButton, player = currentPlayerInstance }
    -- We NEVER destroy buttons. Linoria's groupbox doesn't reclaim space when
    -- buttons are externally Destroy()'d, so over an hour of joins/leaves the
    -- canvas grows and old slots stay reserved → list drifts down off-screen.
    -- Instead, hide the Outer frame on player leave and unhide / re-bind on
    -- join (or on rejoin by the same name).
    local _btnPool = {}        -- [lowerName] = { btn, player, key }
    local _playerToKey = {}    -- [Player] = lowerName (so we can look up on remove)

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
    :AddButton({ Text = "Follow", Func = function()
        if not _selected then Library:Notify("No player selected", 2); return end
        local already = F.players.isFollowing()
        F.players.follow(_selected)
        if already == _selected then
            Library:Notify("Stopped following " .. _selected.Name, 2)
        else
            Library:Notify("Following " .. _selected.Name, 2)
        end
    end })

    P:AddToggle("FollowVisualize", { Text = "Visualize follow path",
        Default = true,
        Callback = function(v) F.players.setFollowVisualize(v) end,
    })

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
    -- visible buttons without us having to destroy + recreate them
    local function reorderPlayers()
        local visibleKeys = {}
        for key, slot in pairs(_btnPool) do
            if slot.player and slot.player.Parent then
                table.insert(visibleKeys, key)
            end
        end
        table.sort(visibleKeys)
        local rank = {}
        for i, k in ipairs(visibleKeys) do rank[k] = i end
        for key, slot in pairs(_btnPool) do
            if slot.btn and slot.btn.Outer then
                local order = rank[key]
                pcall(function()
                    slot.btn.Outer.LayoutOrder = order or 9999
                    slot.btn.Outer.Visible = order ~= nil
                end)
            end
        end
    end

    local function removePlayerButton(pl)
        local key = _playerToKey[pl]
        if not key then return end
        local slot = _btnPool[key]
        if slot then
            slot.player = nil
            if slot.btn and slot.btn.Outer then
                pcall(function() slot.btn.Outer.Visible = false end)
            end
        end
        _playerToKey[pl] = nil
        reorderPlayers()
    end

    local function addPlayerButton(pl)
        if pl == LocalPlayer then return end
        local key = pl.Name:lower()
        local slot = _btnPool[key]
        if slot then
            -- recycle: re-bind to the new Player instance + re-show
            slot.player = pl
            _playerToKey[pl] = key
            if slot.btn and slot.btn.Outer then
                pcall(function() slot.btn.Outer.Visible = true end)
            end
        else
            -- first time we see this name → create exactly one button.
            -- Capture the slot itself so the click handler always uses
            -- whichever Player instance is currently bound (handles rejoin).
            slot = { player = pl, btn = nil, key = key }
            _btnPool[key] = slot
            _playerToKey[pl] = key
            slot.btn = List:AddButton({ Text = pl.Name, Func = function()
                if slot.player and slot.player.Parent then
                    selectPlayer(slot.player)
                end
            end })
            -- on the very first button, walk up to find the parent
            -- UIListLayout and tell it to ignore invisible children, so
            -- hiding a button reclaims its vertical space (default is
            -- IgnoreInvisibleChildren=false → hidden buttons leave gaps)
            if slot.btn and slot.btn.Outer and slot.btn.Outer.Parent then
                local layout = slot.btn.Outer.Parent:FindFirstChildOfClass("UIListLayout")
                if layout then pcall(function() layout.IgnoreInvisibleChildren = true end) end
            end
        end
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

    -- ===================== WHITELIST =====================
    -- Global whitelist tested by ragebot (target skip) and MM2
    -- shoot/trigger. Case-insensitive match against either
    -- Player.Name or Player.DisplayName.
    local WL = Tabs.Players:AddRightGroupbox("Whitelist")
    WL:AddLabel("Skipped by ragebot, MM2 shoot/trigger")

    local function refreshWlDropdown()
        if Options.WhitelistList and Options.WhitelistList.SetValues then
            Options.WhitelistList:SetValues(F.whitelist.list())
        end
    end

    WL:AddInput("WhitelistInput", {
        Text     = "Name",
        Default  = "",
        Numeric  = false,
        Finished = false,
        Placeholder = "Player name to add",
    })
    WL:AddButton({ Text = "Add", Func = function()
        local n = Options.WhitelistInput and Options.WhitelistInput.Value or ""
        if n == "" then return end
        if F.whitelist.add(n) then
            Library:Notify("Whitelisted '" .. n .. "'", 2)
            refreshWlDropdown()
        else
            Library:Notify("'" .. n .. "' already in whitelist", 2)
        end
    end })
    WL:AddButton({ Text = "Add selected", Func = function()
        if not _selected then
            Library:Notify("No player selected in Actions list", 2)
            return
        end
        if F.whitelist.add(_selected.Name) then
            Library:Notify("Whitelisted '" .. _selected.Name .. "'", 2)
            refreshWlDropdown()
        else
            Library:Notify("'" .. _selected.Name .. "' already in whitelist", 2)
        end
    end })

    WL:AddDropdown("WhitelistList", {
        Text     = "Whitelisted",
        Values   = F.whitelist.list(),
        Default  = 1,
        AllowNull = true,
    })
    WL:AddButton({ Text = "Remove selected", Func = function()
        local n = Options.WhitelistList and Options.WhitelistList.Value
        if not n or n == "" then
            Library:Notify("Pick a name from the dropdown first", 2)
            return
        end
        F.whitelist.remove(n)
        Library:Notify("Removed '" .. n .. "'", 2)
        refreshWlDropdown()
    end })
    WL:AddButton({ Text = "Clear all", DoubleClick = true, Func = function()
        F.whitelist.clear()
        refreshWlDropdown()
        Library:Notify("Whitelist cleared", 2)
    end })
end

-- ============================================================
--  MISC TAB  (one-shot actions)
-- ============================================================
do
    local Act = Tabs.Misc:AddLeftGroupbox("Actions")

    Act:AddButton({ Text = "Respawn", Func = F.respawn.fire })

    Act:AddDivider()

    Act:AddButton({ Text = "PANIC - disable everything", DoubleClick = true,
        Func = function()
            F.disableAll()
            for _, name in ipairs({
                "Fly","Speed","Walkspeed","JumpPowerToggle","Bhop","InfJump","AntiAfk","ClickTp","Noclip","AutoRespawn",
                "Fullbright","Freecam","Zoom","Spin","Flip","Ice","StickyEmote","PulseLagswitch",
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

    -- =================== ANTI-FLING ===================
    local AntiFling = Tabs.Misc:AddLeftGroupbox("Anti-fling")
    AntiFling:AddToggle("AntiFling", { Text = "Enable",
        Default = false,
        Callback = function(v)
            if v then F.antiFling.start() else F.antiFling.stop() end
        end,
    })
    AntiFling:AddSlider("AntiFlingCap", {
        Text     = "Velocity cap (stud/sec)",
        Default  = 5000, Min = 100, Max = 50000, Rounding = 0,
        Callback = function(v) F.antiFling.setCap(v) end,
    })

    -- =================== ANTI-KICK ===================
    -- Intercepts and silently drops client-side Kick/Shutdown/Teleport
    -- calls targeting the local player. Won't block true server-side
    -- TCP disconnects (Player:Kick from server), but blocks the common
    -- "server tells client to self-disconnect" pattern.
    local AntiKick = Tabs.Misc:AddLeftGroupbox("Anti-kick")
    AntiKick:AddToggle("AntiKick", { Text = "Block client kicks / teleports",
        Default = false,
        Callback = function(v)
            if v then F.antiKick.start() else F.antiKick.stop() end
        end,
    })

    -- =================== FORCE CHAT ===================
    local ForceChat = Tabs.Misc:AddLeftGroupbox("Force chat")
    ForceChat:AddToggle("ForceChat", { Text = "Re-enable chat",
        Default = false,
        Callback = function(v)
            if v then F.forceChat.start() else F.forceChat.stop() end
        end,
    })

    -- =================== STICKY EMOTES ===================
    -- Keeps catalog emotes playing through movement (promotes the
    -- track to Action4 so WalkAnim/RunAnim can't fade them out, and
    -- replays on Stopped). Type "/e stop" or "/emote stop" in chat
    -- to stop, same as vanilla Roblox.
    local Emotes = Tabs.Misc:AddLeftGroupbox("Sticky emotes")
    Emotes:AddToggle("StickyEmote", { Text = "Keep emotes playing through movement",
        Default = false,
        Callback = function(v)
            if v then F.stickyEmote.start() else F.stickyEmote.stop() end
        end,
    })

    -- =================== PROXIMITY PROMPTS ===================
    local Prompts = Tabs.Misc:AddLeftGroupbox("Proximity prompts")
    Prompts:AddToggle("PromptInstantActivation", { Text = "Instant activation",
        Default = false,
        Callback = function(v)
            if v then F.prompts.instantActivation.start()
            else      F.prompts.instantActivation.stop() end
        end,
    })
    Prompts:AddToggle("PromptUnlimitedRange", { Text = "Unlimited range",
        Default = false,
        Callback = function(v)
            if v then F.prompts.unlimitedRange.start()
            else      F.prompts.unlimitedRange.stop() end
        end,
    })
    Prompts:AddToggle("PromptThroughWalls", { Text = "Through walls",
        Default = false,
        Callback = function(v)
            if v then F.prompts.throughWalls.start()
            else      F.prompts.throughWalls.stop() end
        end,
    })
    Prompts:AddToggle("PromptAutoFire", { Text = "Auto-fire",
        Default = false,
        Callback = function(v)
            if v then F.prompts.autoFire.start()
            else      F.prompts.autoFire.stop() end
        end,
    })

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
    -- All supported games keyed by display name -> list of PlaceIds.
    -- Add new entries here when adding a new game block below.
    local SUPPORTED_GAMES = {
        ["Hood Customs"]              = { 138995385694035, 9825515356 },
        ["Murder Mystery 2"]          = { 142823291 },
        ["Match the Cards!"]          = { 138397085393482 },
        ["Blockerman's Minesweeper"]  = { 7871169780 },
    }
    local function findCurrentGame()
        for name, ids in pairs(SUPPORTED_GAMES) do
            for _, id in ipairs(ids) do
                if game.PlaceId == id then return name end
            end
        end
        return nil
    end
    local _currentGame = findCurrentGame()

    -- Unsupported-game message: single groupbox listing every game
    -- we DO support so the user can see what they're missing.
    if not _currentGame then
        local names = {}
        for n in pairs(SUPPORTED_GAMES) do table.insert(names, n) end
        table.sort(names)
        local g = Tabs.Games:AddLeftGroupbox("Games")
        g:AddLabel(
            ("No Supported games Found, current supported games: '%s'."):format(
                table.concat(names, ", ")),
            true)
    end

    -- ---------------- HOOD CUSTOMS ----------------
    local HC = (_currentGame == "Hood Customs") and Tabs.Games:AddLeftGroupbox("Hood Customs") or nil

    if _currentGame == "Hood Customs" then

    -- ---- Ragebot (HC-specific) ----
    HC:AddLabel("Ragebot")
    HC:AddToggle("RageSkipKnocked", {
        Text = "Skip knocked targets",
        Default = false,
        Callback = F.ragebot.setSkipKnocked,
    })
    HC:AddToggle("RageIgnoreKnocked", {
        Text = "Ignore knocked targets",
        Default = false,
        Callback = F.ragebot.setIgnoreKnocked,
    })

    -- Post-knocked grace window. After a target was last seen knocked,
    -- the ragebot autoshoot waits this many milliseconds before firing
    -- on them again even if they now read alive. Catches the brief
    -- respawn race where the old corpse is still the target but the
    -- new body hasn't replicated yet, so shots wasted on the corpse.
    HC:AddSlider("RageKnockedGraceDelay", {
        Text = "Knocked grace delay",
        Default = F.ragebot.getKnockedGraceDelay(),
        Min = 0, Max = 20, Rounding = 0, Suffix = " ms",
        Callback = F.ragebot.setKnockedGraceDelay,
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
    HC:AddLabel("AFK badge")
    HC:AddToggle("HCAntiAfkTag", { Text = "Anti-AFK tag (hide)",
        Default = true,
        Callback = function(v)
            if v then
                -- mutually exclusive with force-AFK; flip its toggle off too
                if Toggles.HCForceAfkTag and Toggles.HCForceAfkTag.Value then
                    Toggles.HCForceAfkTag:SetValue(false)
                end
                F.games.hoodCustoms.antiAfkTag.start()
            else
                F.games.hoodCustoms.antiAfkTag.stop()
            end
        end,
    })
    HC:AddToggle("HCForceAfkTag", { Text = "Force-AFK tag (always show)",
        Default = false,
        Callback = function(v)
            if v then
                -- mutually exclusive with anti-AFK; flip its toggle off too
                if Toggles.HCAntiAfkTag and Toggles.HCAntiAfkTag.Value then
                    Toggles.HCAntiAfkTag:SetValue(false)
                end
                F.games.hoodCustoms.forceAfkTag.start()
            else
                F.games.hoodCustoms.forceAfkTag.stop()
            end
        end,
    })

    HC:AddDivider()

    -- ---- Godmode ----
    HC:AddLabel("Godmode")
    HC:AddToggle("HCGodmode", { Text = "Godmode",
        Default = false,
        Callback = function(v)
            if v then F.games.hoodCustoms.godmode.start()
            else      F.games.hoodCustoms.godmode.stop() end
        end,
    })

    HC:AddDivider()

    -- ---- Force Hit ----
    -- Target is shared with the Players tab selection (selectPlayer there
    -- calls forceHit.setTarget on every change). Hotkey + part dropdown +
    -- TP-wallbang + auto-refill ammo all live here.
    HC:AddLabel("Force Hit (shotgun support WIP)")
    HC:AddToggle("HCForceHit", { Text = "Enable",
        Default = false,
        Callback = function(v)
            if v then F.games.hoodCustoms.forceHit.start()
            else      F.games.hoodCustoms.forceHit.stop() end
        end,
    })
    HC:AddDropdown("HCForceHitPart", {
        Text     = "Hit part",
        Values   = { "Head", "UpperTorso", "HumanoidRootPart" },
        Default  = "Head",
        Callback = function(v) F.games.hoodCustoms.forceHit.setHitPart(v) end,
    })
    HC:AddSlider("HCForceHitCooldown", {
        Text     = "Cooldown (sec)",
        Default  = 0.20, Min = 0, Max = 2, Rounding = 2,
        Callback = function(v) F.games.hoodCustoms.forceHit.setCooldown(v) end,
    })
    -- Shotgun mode dropdown removed - forceHit always uses synth
    -- (direct FireServer with the canonical HC Shoot payload).

    -- Tracer + hit sound. FireServer doesn't render bullet visuals
    -- because we never go through the gun script, so we fake them
    -- locally for visual + audio feedback on each forced hit.
    HC:AddToggle("HCForceHitTracer", { Text = "Show fake bullet tracer",
        Default = true,
        Callback = function(v) F.games.hoodCustoms.forceHit.setTracerEnabled(v) end,
    })
    HC:AddLabel("Tracer color"):AddColorPicker("HCForceHitTracerColor", {
        Default  = Color3.fromRGB(0, 255, 80),
        Callback = function(c) F.games.hoodCustoms.forceHit.setTracerColor(c) end,
    })
    HC:AddSlider("HCForceHitTracerLife", {
        Text     = "Tracer lifetime",
        Default  = 0.20, Min = 0.05, Max = 1.0, Rounding = 2,
        Callback = function(v) F.games.hoodCustoms.forceHit.setTracerLifetime(v) end,
    })
    -- Beam style selector. Each option uses a different builder in
    -- spawnTracer (see functions.lua) and changes how the bullet
    -- visual draws on screen.
    HC:AddDropdown("HCForceHitTracerStyle", {
        Values = { "Standard", "Laser", "Lightning", "Plasma", "Thin" },
        Default = "Standard",
        Text = "Tracer style",
        Callback = function(v) F.games.hoodCustoms.forceHit.setTracerStyle(v) end,
    })
    HC:AddDivider()
    -- Trail particles along beam path (sparkles that linger after shot).
    HC:AddToggle("HCForceHitTrail", { Text = "Trail particles along beam",
        Default = false,
        Callback = function(v) F.games.hoodCustoms.forceHit.setTrailEnabled(v) end,
    })
    HC:AddDivider()
    HC:AddToggle("HCForceHitHitSound", { Text = "Play hit sound",
        Default = true,
        Callback = function(v) F.games.hoodCustoms.forceHit.setHitSoundEnabled(v) end,
    })
    do
        local SOUNDS = {
            { label = "deep bell",     id = 104441273771318 },
            { label = "crit",          id = 135698842254153 },
            { label = "m4a1",          id = 18521643711 },
            { label = "pack a punch",  id = 7408420244 },
            { label = "random sound",  id = 133749572213659 },
            { label = "weird idk what its called", id = 129157734600366 },
            { label = "csgo headshot", id = 133002449941130 },
            { label = "rust headshot", id = 103094294870161 },
        }
        local labels = {}
        local byLabel = {}
        for _, s in ipairs(SOUNDS) do
            table.insert(labels, s.label)
            byLabel[s.label] = s.id
        end
        HC:AddDropdown("HCForceHitSoundId", {
            Text     = "Hit sound",
            Values   = labels,
            Default  = "crit",
            Callback = function(v)
                local id = byLabel[v]
                if id then F.games.hoodCustoms.forceHit.setHitSoundId(id) end
            end,
        })
        -- push initial value so the API matches the GUI default
        F.games.hoodCustoms.forceHit.setHitSoundId(byLabel["crit"])
    end
    HC:AddSlider("HCForceHitSoundVolume", {
        Text     = "Hit sound volume",
        Default  = 1.0, Min = 0, Max = 3, Rounding = 2,
        Callback = function(v) F.games.hoodCustoms.forceHit.setHitSoundVolume(v) end,
    })

    HC:AddDivider()

    -- =================== KNIFE BOT ===================
    -- Voidspam-on-stab desync + attach-to-ragebot-target + auto-equip.
    -- Lives here (not in Movement -> Desync) because all three pieces
    -- are HC-specific. Voidspam is mutually exclusive with the other
    -- desync modes via the shared selectMode helper.
    HC:AddLabel("Knife Bot")
    HC:AddToggle("HCVoidspam", { Text = "Use Knife Voidspam",
        Default = false,
        Callback = function(v)
            if v then
                local sel = getgenv()._F_DESYNC_SELECT
                if sel then sel("HCVoidspam") end
                F.desync.startVoidspam()
            else
                F.desync.stop()
            end
        end,
    })
    HC:AddSlider("HCVoidspamShotDelayMs", {
        Text     = "Start at % of anim",
        Default  = 40, Min = 0, Max = 100, Rounding = 0,
        Callback = function(v) F.desync.setShotDelayMs(v) end,
    })
    HC:AddSlider("HCVoidspamShotSyncMs", {
        Text     = "End at % of anim",
        Default  = 90, Min = 0, Max = 100, Rounding = 0,
        Callback = function(v) F.desync.setShotSyncMs(v) end,
    })
    HC:AddToggle("HCVoidspamSyncVisual", { Text = "Show sync window visualizer",
        Default  = false,
        Callback = function(v) F.desync.setSyncVisualEnabled(v) end,
    })
    HC:AddToggle("HCKnifeAttach", { Text = "Attach to ragebot target",
        Default  = false,
        Callback = function(v)
            if v then
                -- snapshot prior ranged-toggle state so we can restore
                -- it on attach-off. Stored in getgenv so a script reload
                -- mid-session doesn't lose the prior state.
                getgenv()._F_KNIFE_PREV_AUTOSHOOT =
                    Toggles.RageAutoShoot and Toggles.RageAutoShoot.Value or false
                getgenv()._F_KNIFE_PREV_FORCEHIT =
                    Toggles.HCForceHit    and Toggles.HCForceHit.Value    or false
                -- mute the ranged autos: knife only
                if Toggles.RageAutoShoot then Toggles.RageAutoShoot:SetValue(false) end
                if Toggles.HCForceHit    then Toggles.HCForceHit:SetValue(false)    end
                F.games.hoodCustoms.knifeBot.attach.start()
            else
                F.games.hoodCustoms.knifeBot.attach.stop()
                -- restore whatever ranged-toggle state was active before
                -- attach was enabled
                if getgenv()._F_KNIFE_PREV_AUTOSHOOT and Toggles.RageAutoShoot then
                    Toggles.RageAutoShoot:SetValue(true)
                end
                if getgenv()._F_KNIFE_PREV_FORCEHIT and Toggles.HCForceHit then
                    Toggles.HCForceHit:SetValue(true)
                end
                getgenv()._F_KNIFE_PREV_AUTOSHOOT = nil
                getgenv()._F_KNIFE_PREV_FORCEHIT = nil
            end
        end,
    })
    HC:AddSlider("HCKnifeAttachDistance", {
        Text     = "Attach distance (studs)",
        Default  = 3, Min = 0, Max = 50, Rounding = 1,
        Callback = function(v) F.games.hoodCustoms.knifeBot.attach.setDistance(v) end,
    })
    HC:AddSlider("HCKnifeClickInterval", {
        Text     = "Click interval (s)",
        Default  = 0.6, Min = 0.05, Max = 5, Rounding = 2,
        Callback = function(v) F.games.hoodCustoms.knifeBot.attach.setClickInterval(v) end,
    })
    HC:AddToggle("HCKnifeOrbit", { Text = "Orbit target",
        Default  = false,
        Callback = function(v) F.games.hoodCustoms.knifeBot.attach.setOrbit(v) end,
    })
    HC:AddSlider("HCKnifeOrbitSpeed", {
        Text     = "Orbit speed (deg/s)",
        Default  = 180, Min = 0, Max = 720, Rounding = 0,
        Callback = function(v) F.games.hoodCustoms.knifeBot.attach.setOrbitSpeed(v) end,
    })
    HC:AddToggle("HCKnifeAutoEquip", { Text = "Auto-equip [Knife]",
        Default  = false,
        Callback = function(v)
            if v then F.games.hoodCustoms.knifeBot.autoEquip.start()
            else      F.games.hoodCustoms.knifeBot.autoEquip.stop() end
        end,
    })

    end -- close: if _currentGame == "Hood Customs" then ...

    -- ---------------- MURDER MYSTERY 2 ----------------
    if _currentGame == "Murder Mystery 2" then
        local MM2 = Tabs.Games:AddLeftGroupbox("Murder Mystery 2")

        MM2:AddLabel("Identity ESP")
        MM2:AddToggle("MM2IdentityEsp", { Text = "Sheriff / Murderer labels",
            Default  = false,
            Callback = function(v)
                if v then F.games.mm2.identityEsp.start()
                else      F.games.mm2.identityEsp.stop() end
            end,
        })

        MM2:AddDivider()

        MM2:AddLabel("Gun pickup")
        MM2:AddToggle("MM2DropEsp", { Text = "Dropped gun ESP",
            Default  = false,
            Callback = function(v)
                if v then F.games.mm2.dropEsp.start()
                else      F.games.mm2.dropEsp.stop() end
            end,
        })
        local PICKUP_ERR = {
            no_drop = "Can't pick up yet - Sheriff hasn't dropped the gun.",
            no_hrp  = "Your character isn't loaded.",
            -- "active" is silent - pickup is already in progress
        }
        local function tryPickupGun()
            local ok, reason = F.games.mm2.pickupGun.fire()
            if not ok and reason and PICKUP_ERR[reason] then
                Library:Notify(PICKUP_ERR[reason], 3)
            end
        end
        MM2:AddLabel("Pickup gun key"):AddKeyPicker("MM2PickupGunKey", {
            Default = "G", Mode = "Hold", Text = "Pickup gun",
        })
        bindFireKey("MM2PickupGunKey", tryPickupGun)
        MM2:AddButton({ Text = "Pickup gun now", Func = tryPickupGun })
        MM2:AddToggle("MM2AutoPickupGun", { Text = "Auto pickup gun",
            Default  = false,
            Callback = function(v)
                if v then F.games.mm2.autoPickupGun.start()
                else      F.games.mm2.autoPickupGun.stop() end
            end,
        })

        MM2:AddDivider()
        MM2:AddLabel("Invisible")
        MM2:AddToggle("MM2Invisible", { Text = "Invisible",
            Default  = false,
            Callback = function(v)
                if v then
                    local sel = getgenv()._F_DESYNC_SELECT
                    if sel then sel("MM2Invisible") end
                    F.desync.startInvisible()
                else
                    F.desync.stop()
                end
            end,
        })
        MM2:AddSlider("MM2InvisibleRadius", {
            Text     = "Invisible jitter radius (studs)",
            Default  = 25, Min = 0, Max = 500, Rounding = 0,
            Callback = function(v) F.desync.setInvisibleRadius(v) end,
        })
        -- Toggle-mode KeyPicker's Callback DOES fire on label-attached
        -- pickers (unlike Hold-mode, which needs bindFireKey). Use the
        -- picker's own state directly - pressing V flips it, the
        -- Callback mirrors that state into the main MM2Invisible
        -- toggle, which handles start/stop + mutex.
        MM2:AddLabel("Invisible key"):AddKeyPicker("MM2InvisibleKey", {
            Default = "V", Mode = "Toggle", Text = "Invisible",
            Callback = function(state)
                if Toggles.MM2Invisible then
                    Toggles.MM2Invisible:SetValue(state)
                end
            end,
        })

        MM2:AddDivider()
        MM2:AddLabel("Murderer trigger")
        MM2:AddToggle("MM2TriggerMurderer", { Text = "Hover-fire on Murderer",
            Default  = false,
            Callback = function(v)
                if v then F.games.mm2.triggerMurderer.start()
                else      F.games.mm2.triggerMurderer.stop() end
            end,
        })
        local SHOOT_MURDERER_ERR = {
            no_gun        = "You don't have the Gun. Only the Sheriff can shoot.",
            no_my_hrp     = "Your character isn't loaded yet.",
            no_murderer   = "No player is holding the [Knife] tool right now.",
            no_victim_hrp = "Murderer's character isn't loaded.",
        }
        local function tryShootMurderer()
            local ok, reason = F.games.mm2.shootMurderer.fire()
            if not ok then
                Library:Notify(SHOOT_MURDERER_ERR[reason] or ("Shoot failed: " .. tostring(reason)), 3)
            end
        end
        MM2:AddButton({ Text = "Shoot murderer", Func = tryShootMurderer })
        MM2:AddLabel("Shoot murderer key"):AddKeyPicker("MM2ShootMurdererKey", {
            Default = "J", Mode = "Hold", Text = "Shoot murderer",
        })
        bindFireKey("MM2ShootMurdererKey", function()
            print("[cclosure.vip] Shoot Murderer keybind fired")
            tryShootMurderer()
        end)
    end

    -- ---------------- BLOCKERMAN'S MINESWEEPER ----------------
    if _currentGame == "Blockerman's Minesweeper" then
        local BMS = Tabs.Games:AddLeftGroupbox("Blockerman's Minesweeper")

        BMS:AddLabel("Token capture")
        BMS:AddLabel(
            "Place one flag manually first - the token gets\n"
         .. "captured automatically on the first PlaceFlag call.\n"
         .. "If autocapture doesn't work, paste it manually below.",
            true)  -- true = DoesWrap
        BMS:AddInput("BMSManualToken", {
            Default     = "",
            Placeholder = "paste session token here",
            Text        = "Manual token",
            Tooltip     = "Set the session token manually if autocapture fails",
            Callback    = function(v)
                if v and #v > 8 then
                    F.games.bms.setToken(v)
                    Library:Notify("BMS token set manually", 3)
                end
            end,
        })
        BMS:AddButton({ Text = "Test token", Func = function()
            local t = F.games.bms.getToken()
            if t then
                Library:Notify("Token set: " .. t:sub(1, 16) .. "...", 4)
            else
                Library:Notify("No token captured yet", 4)
            end
        end })

        BMS:AddDivider()

        BMS:AddLabel("Mine ESP")
        BMS:AddToggle("BMSEsp", { Text = "Mine ESP",
            Default = false,
            Callback = function(v)
                if v then F.games.bms.esp.start() else F.games.bms.esp.stop() end
            end,
        })
        BMS:AddSlider("BMSEspRange", { Text = "ESP range",
            Default = 80, Min = 10, Max = 1000, Rounding = 0, Suffix = " studs",
            Callback = function(v) F.games.bms.esp.setRange(v) end,
        })
        BMS:AddToggle("BMSEspShowSafes", { Text = "Highlight deduced-safe tiles",
            Default = false,
            Callback = function(v) F.games.bms.esp.setShowSafes(v) end,
        })
        BMS:AddToggle("BMSEspShowWarnings", { Text = "Highlight false-flag warnings",
            Default = true,
            Callback = function(v) F.games.bms.esp.setShowWarnings(v) end,
        })

        BMS:AddDivider()

        BMS:AddLabel("Legit auto-flag")
        BMS:AddToggle("BMSLegitFlag", { Text = "Auto-flag deduced mines",
            Default = false,
            Callback = function(v)
                if v then F.games.bms.legitFlag.start() else F.games.bms.legitFlag.stop() end
            end,
        })
        BMS:AddSlider("BMSFlagDelay", { Text = "Flag delay (one at a time)",
            Default = 1.0, Min = 0.05, Max = 10, Rounding = 2, Suffix = " s",
            Callback = function(v) F.games.bms.legitFlag.setDelay(v) end,
        })
        BMS:AddSlider("BMSFlagRange", { Text = "Flag range",
            Default = 60, Min = 5, Max = 500, Rounding = 0, Suffix = " studs",
            Callback = function(v) F.games.bms.legitFlag.setRange(v) end,
        })

        BMS:AddDivider()

        BMS:AddLabel("Auto play")
        BMS:AddToggle("BMSAutoPlay", { Text = "Auto play (walk safes + flag mines)",
            Default = false,
            Callback = function(v)
                if v then
                    -- mutex: auto play subsumes legit flag
                    if Toggles.BMSLegitFlag and Toggles.BMSLegitFlag.Value then
                        Toggles.BMSLegitFlag:SetValue(false)
                    end
                    F.games.bms.autoPlay.start()
                else
                    F.games.bms.autoPlay.stop()
                end
            end,
        })
        BMS:AddSlider("BMSAutoStepDelay", { Text = "Walk step max delay",
            Default = 0.4, Min = 0.05, Max = 3, Rounding = 2, Suffix = " s",
            Callback = function(v) F.games.bms.autoPlay.setStepDelay(v) end,
        })
    end

    -- ---------------- MATCH THE CARDS! ----------------
    if _currentGame == "Match the Cards!" then
        local MTC = Tabs.Games:AddLeftGroupbox("Match the Cards!")

        MTC:AddLabel("Card peek")
        MTC:AddToggle("MTCPeek", { Text = "Peek on hover (legit)",
            Default = false,
            Callback = function(v)
                if v then
                    -- mutex: showAll fights for the same cards, kill it
                    if Toggles.MTCShowAll and Toggles.MTCShowAll.Value then
                        Toggles.MTCShowAll:SetValue(false)
                    end
                    F.games.matchTheCards.peek.start()
                else
                    F.games.matchTheCards.peek.stop()
                end
            end,
        })
        MTC:AddSlider("MTCPeekStay", { Text = "Stay flipped after leaving",
            Default = F.games.matchTheCards.peek.getStayTime(),
            Min = 0, Max = 30, Rounding = 1, Suffix = " s",
            Callback = function(v) F.games.matchTheCards.peek.setStayTime(v) end,
        })

        MTC:AddDivider()

        MTC:AddLabel("Show all (not legit)")
        MTC:AddToggle("MTCShowAll", { Text = "Constantly flip every card",
            Default = false,
            Callback = function(v)
                if v then
                    if Toggles.MTCPeek and Toggles.MTCPeek.Value then
                        Toggles.MTCPeek:SetValue(false)
                    end
                    F.games.matchTheCards.showAll.start()
                else
                    F.games.matchTheCards.showAll.stop()
                end
            end,
        })
    end
end

-- ============================================================
--  WATERMARK + UNLOAD
-- ============================================================
Library:SetWatermarkVisibility(true)

-- only update watermark text once per second instead of every frame -
-- reading Stats.Network + string.format + label rewrite was happening
-- every render frame, wasted at 240 fps.
local FrameTimer, FrameCounter, FPS = tick(), 0, 60
local WatermarkConn = RunService.RenderStepped:Connect(function()
    FrameCounter += 1
    if (tick() - FrameTimer) >= 1 then
        FPS = FrameCounter; FrameTimer = tick(); FrameCounter = 0
        local ping = 0
        pcall(function()
            ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
        end)
        Library:SetWatermark(("cclosure.vip v[%s] | %d fps | %d ms"):format(
            (F.getVersion and F.getVersion() or "?"):sub(1, 16), math.floor(FPS), ping))
    end
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

Library:Notify("cclosure.vip loaded - press End to toggle the menu", 4)
