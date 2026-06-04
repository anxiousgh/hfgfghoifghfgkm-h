-- ============================================================
-- decay // Murder Mystery 2 module
-- ============================================================
-- Loaded by decay.lua via:  fetch("games/mm2.lua")(ctx)
-- Inside the chunk: ctx is the first vararg.
-- ============================================================
local ctx = ({...})[1]
local ui, window = ctx.ui, ctx.window

print("[decay/mm2] module loaded")

local menu = window:addMenu({ text = "Murder Mystery 2" })
do
    local section = menu:addSection({ text = "Status" })
    section:addLabel({ text = "Murder Mystery 2 module — stub." })
    section:addLabel({ text = "Add features here." })
end
