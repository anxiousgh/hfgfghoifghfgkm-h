-- tool_dump.lua
-- Run this in your executor console while holding a gun.
-- Appends the tool's attributes to "decay_tool_dump.txt" in the
-- executor's workspace folder. Run it again with a different gun
-- and it adds a new block to the same file.

local lplr = game:GetService("Players").LocalPlayer
local char = lplr.Character or lplr.CharacterAdded:Wait()

-- Find equipped tool (standard Tool OR any Model with gun attributes)
local tool = char:FindFirstChildOfClass("Tool")
if not tool then
    for _, v in ipairs(char:GetChildren()) do
        if (v:IsA("Model") or v:IsA("Tool"))
           and (v:GetAttribute("Damage") or v:GetAttribute("CurrentAmmo")) then
            tool = v
            break
        end
    end
end

if not tool then
    warn("[tool_dump] No tool equipped. Equip a gun and run again.")
    return
end

-- GetAttributes returns a {name -> value} dictionary
local attrs = tool:GetAttributes()
local attrCount = 0
for _ in pairs(attrs) do attrCount = attrCount + 1 end

if attrCount == 0 then
    warn("[tool_dump] Tool '" .. tool.Name .. "' has no attributes.")
    return
end

-- Sort attribute names alphabetically for consistent output
local keys = {}
for k in pairs(attrs) do table.insert(keys, k) end
table.sort(keys)

-- Build the block
local lines = {}
table.insert(lines, tool.Name .. ": {")
for _, k in ipairs(keys) do
    local v = attrs[k]
    local vStr
    if type(v) == "number" then
        if v == math.huge then
            vStr = "math.huge"
        elseif v ~= v then          -- NaN check
            vStr = "NaN"
        elseif v == math.floor(v) then
            vStr = tostring(math.floor(v))
        else
            vStr = string.format("%.6g", v)
        end
    elseif typeof(v) == "Vector3" then
        vStr = string.format("Vector3(%.4g, %.4g, %.4g)", v.X, v.Y, v.Z)
    elseif typeof(v) == "Color3" then
        vStr = string.format("Color3(%.3f, %.3f, %.3f)", v.R, v.G, v.B)
    elseif typeof(v) == "CFrame" then
        vStr = "CFrame(...)"
    else
        vStr = tostring(v)
    end
    table.insert(lines, "    " .. k .. " = " .. vStr)
end
table.insert(lines, "}")
table.insert(lines, "")  -- blank line between entries

local block = table.concat(lines, "\n")
local filename = "decay_tool_dump.txt"

-- Append to existing file (or create new)
local existing = ""
if isfile and isfile(filename) then
    existing = readfile(filename)
end
writefile(filename, existing .. block)

print(string.format("[tool_dump] '%s' dumped (%d attrs) -> %s",
    tool.Name, attrCount, filename))
