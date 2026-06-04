-- ============================================================
--  decay.lua  //  multi-game Roblox script
--  See README.md for the project layout.
-- ============================================================

print("[decay] decay.lua loaded - if you don't see this, the loader URL itself is cached")

-- ============================================================
-- SHA-pin the repo so subsequent fetches always hit a fresh URL
-- (raw.githubusercontent.com ignores query strings for cache
-- keying, so the only way to bust the CDN is to embed a commit
-- SHA in the path). Falls back to the branch name if the GitHub
-- API call fails (rare).
-- ============================================================
local OWNER, REPO, BRANCH = "anxiousgh", "hfgfghoifghfgkm-h", "main"
local _sha
do
    local ok, body = pcall(game.HttpGet, game,
        "https://api.github.com/repos/" .. OWNER .. "/" .. REPO .. "/commits/" .. BRANCH)
    if ok and type(body) == "string" then
        _sha = body:match('"sha"%s*:%s*"([0-9a-f]+)"')
    end
end
local base = _sha
    and ("https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPO .. "/" .. _sha .. "/decay/")
    or  ("https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPO .. "/" .. BRANCH .. "/decay/")

if _sha then
    print("[decay] SHA-pinned base:", _sha:sub(1, 12) .. "...")
else
    warn("[decay] GitHub API failed - falling back to main branch (may be cached)")
end

-- ============================================================
-- fetch helper. Compiles the chunk and returns the function so
-- the caller can invoke it with any args they want.
-- ============================================================
local function fetch(path)
    local src = game:HttpGet(base .. path)
    local fn, err = loadstring(src)
    if not fn then
        error("[decay] " .. path .. " compile failed: " .. tostring(err), 0)
    end
    return fn
end

-- ============================================================
-- UI library bootstrap (vendored Dollarware - see lib/dollarware.lua)
-- ============================================================
local ui = fetch("lib/dollarware.lua")({
    rounding       = false,
    theme          = "blueberry",   -- cherry / orange / lemon / lime / raspberry / blueberry / grape / watermelon
    smoothDragging = true,
})
ui.autoDisableToggles = true

-- ============================================================
-- Game detection (MarketplaceService title -> fingerprint fallback)
-- ============================================================
local PLAYERS      = game:GetService("Players")
local MARKET       = game:GetService("MarketplaceService")
local USER_INPUT   = game:GetService("UserInputService")
local RUN_SERVICE  = game:GetService("RunService")
local TWEEN        = game:GetService("TweenService")
local REPL_STORAGE = game:GetService("ReplicatedStorage")
local LOCAL_PLAYER = PLAYERS.LocalPlayer

local function detectGame()
    local ok, info = pcall(function() return MARKET:GetProductInfo(game.PlaceId) end)
    local rawName  = ok and info and info.Name or ""
    local title    = string.lower(rawName)

    if title:find("hood") and title:find("custom") then return "hoodcustoms", rawName end
    if title:find("murder") and title:find("mystery") then return "mm2", rawName end
    if title:find("match") and title:find("the cards") then return "matchthecards", rawName end
    if title:find("minesweeper") or title:find("blockerman") then return "minesweeper", rawName end

    -- fingerprint fallback for cases where the title rename / private
    -- server name doesn't match.
    local ws = workspace
    if ws:FindFirstChild("Players") and ws.Players:FindFirstChild("Characters") then
        return "hoodcustoms", "Hood Customs"
    end
    if ws:FindFirstChild("Lobby") and ws:FindFirstChild("Map") then
        return "mm2", "Murder Mystery 2"
    end
    if ws:FindFirstChild("Flag") and ws.Flag:FindFirstChild("Parts") then
        return "minesweeper", "Blockerman's Minesweeper"
    end

    return nil, rawName
end

local gameKey, gameName = detectGame()
print(("[decay] detected: %s (%s)"):format(gameKey or "(none)", gameName or "?"))

-- ============================================================
-- Window
-- ============================================================
local window = ui.newWindow({
    text   = "decay.lua  //  " .. (gameName ~= "" and gameName or "no game"),
    resize = true,
    size   = Vector2.new(580, 400),
})

-- ============================================================
-- ctx: everything a game module needs. Each game module is a
-- self-contained chunk loaded via loadstring(...)(ctx). Inside
-- the chunk: `local ctx = ({...})[1]`.
-- ============================================================
local ctx = {
    ui       = ui,
    window   = window,
    fetch    = fetch,
    base     = base,
    player   = LOCAL_PLAYER,
    gameKey  = gameKey,
    gameName = gameName,
    services = {
        Players          = PLAYERS,
        MarketplaceService = MARKET,
        UserInputService = USER_INPUT,
        RunService       = RUN_SERVICE,
        TweenService     = TWEEN,
        ReplicatedStorage = REPL_STORAGE,
    },
}

-- ============================================================
-- Load the matching game module. Errors are caught + reported
-- in the UI so a bad module doesn't kill the whole loader.
-- ============================================================
if gameKey then
    local ok, err = pcall(function()
        fetch("games/" .. gameKey .. ".lua")(ctx)
    end)
    if not ok then
        warn("[decay] game module '" .. gameKey .. "' failed: " .. tostring(err))
        local menu    = window:addMenu({ text = "Error" })
        local section = menu:addSection({ text = gameKey .. ".lua" })
        section:addLabel({ text = "Module failed to load:" })
        section:addLabel({ text = tostring(err) })
    end
else
    -- Unsupported game: still show a window so the user can see
    -- the script loaded; just no game-specific features.
    local menu    = window:addMenu({ text = "decay" })
    local section = menu:addSection({ text = "Unsupported game" })
    section:addLabel({ text = "No matching game module for:" })
    section:addLabel({ text = "PlaceId: " .. tostring(game.PlaceId) })
    section:addLabel({ text = "Title: "   .. (gameName ~= "" and gameName or "?") })
    section:addLabel({ text = "" })
    section:addLabel({ text = "Supported games:" })
    section:addLabel({ text = " - Hood Customs" })
    section:addLabel({ text = " - Murder Mystery 2" })
    section:addLabel({ text = " - Match the Cards" })
    section:addLabel({ text = " - Blockerman's Minesweeper" })
end

print("[decay] ready")
