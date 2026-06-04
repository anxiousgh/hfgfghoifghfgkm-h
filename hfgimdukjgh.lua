-- legacy launcher URL; the real loader is now decay.lua. This stub
-- exists so executors pointed at the old name keep working.
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
    and ("https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPO .. "/" .. _sha .. "/")
    or  ("https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPO .. "/" .. BRANCH .. "/")
loadstring(game:HttpGet(base .. "decay.lua"))()
