-- ============================================================
-- decay // Hood Customs module
-- ============================================================
-- Loaded by decay.lua via:  fetch("games/hoodcustoms.lua")(ctx)
-- Inside the chunk: ctx is the first vararg.
-- ============================================================
local ctx = ({...})[1]
local ui, window = ctx.ui, ctx.window

print("[decay/hoodcustoms] module loaded")

local menu = window:addMenu({ text = "Hood Customs" })
do
    local section = menu:addSection({ text = "Status" })
    section:addLabel({ text = "Hood Customs module — stub." })
    section:addLabel({ text = "Add features here." })
end
