-- legacy launcher URL; the real loader is now decay.lua. This stub
-- exists so executors pointed at the old name keep working.
local _ghOwner, _ghRepo, _ghBranch = "anxiousgh", "hfgfghoifghfgkm-h", "main"
local _sha
do
    local ok, body = pcall(game.HttpGet, game,
        "https://api.github.com/repos/" .. _ghOwner .. "/" .. _ghRepo .. "/commits/" .. _ghBranch)
    if ok and type(body) == "string" then
        _sha = body:match('"sha"%s*:%s*"([0-9a-f]+)"')
    end
end
local base = _sha
    and ("https://raw.githubusercontent.com/" .. _ghOwner .. "/" .. _ghRepo .. "/" .. _sha .. "/")
    or  ("https://raw.githubusercontent.com/" .. _ghOwner .. "/" .. _ghRepo .. "/" .. _ghBranch .. "/")
loadstring(game:HttpGet(base .. "decay.lua"))()
