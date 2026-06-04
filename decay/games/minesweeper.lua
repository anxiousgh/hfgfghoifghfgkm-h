-- ============================================================
-- decay // Blockerman's Minesweeper module
-- ============================================================
-- Loaded by decay.lua via:  fetch("games/minesweeper.lua")(ctx)
-- Inside the chunk: ctx is the first vararg.
-- ============================================================
local ctx = ({...})[1]
local ui, window = ctx.ui, ctx.window

print("[decay/minesweeper] module loaded")

local menu = window:addMenu({ text = "Minesweeper" })
do
    local section = menu:addSection({ text = "Status" })
    section:addLabel({ text = "Blockerman's Minesweeper module — stub." })
    section:addLabel({ text = "Add features here." })
end
