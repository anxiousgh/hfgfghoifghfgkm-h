-- ============================================================
-- decay // Match the Cards! module
-- ============================================================
-- Loaded by decay.lua via:  fetch("games/matchthecards.lua")(ctx)
-- Inside the chunk: ctx is the first vararg.
-- ============================================================
local ctx = ({...})[1]
local ui, window = ctx.ui, ctx.window

print("[decay/matchthecards] module loaded")

local menu = window:addMenu({ text = "Match the Cards" })
do
    local section = menu:addSection({ text = "Status" })
    section:addLabel({ text = "Match the Cards module — stub." })
    section:addLabel({ text = "Add features here." })
end
