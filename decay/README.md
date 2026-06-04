# decay.lua

Multi-game Roblox script. Each supported game lives in its own self-contained
module under `games/` and is only loaded if the local game matches.

## Loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/anxiousgh/hfgfghoifghfgkm-h/main/decay/decay.lua"))()
```

## Layout

```
decay/
├── decay.lua             main entry. SHA-pins the repo, loads the UI,
│                         detects the current game, dispatches to the
│                         matching module.
├── lib/
│   └── dollarware.lua    vendored copy of topitbopit/dollarware. Edit
│                         this file directly to customise the UI.
├── games/
│   ├── hoodcustoms.lua   Hood Customs features
│   ├── mm2.lua           Murder Mystery 2 features
│   ├── matchthecards.lua Match the Cards features
│   └── minesweeper.lua   Blockerman's Minesweeper features
└── README.md
```

## Game module contract

Each game module is a chunk loaded via `loadstring(src)(ctx)`. Inside:

```lua
local ctx = ({...})[1]
local ui, window = ctx.ui, ctx.window
-- ...feature setup...
```

`ctx` contains:

| field      | type              | description                                  |
|------------|-------------------|----------------------------------------------|
| `ui`       | Dollarware ui     | top-level lib handle (notify, themes, etc.)  |
| `window`   | ui window         | the already-created shared window            |
| `fetch`    | function          | `fetch("path")` → loaded function (relative to `decay/`) |
| `base`     | string            | the SHA-pinned raw URL prefix                |
| `player`   | Player            | LocalPlayer                                  |
| `gameKey`  | string            | `"hoodcustoms"` / `"mm2"` / etc.             |
| `gameName` | string            | the title resolved from MarketplaceService   |
| `services` | table             | `Players`, `UserInputService`, `RunService`, `TweenService`, `ReplicatedStorage`, `MarketplaceService` |

## UI library

Dollarware ([topitbopit/dollarware](https://github.com/topitbopit/dollarware))
is vendored as `lib/dollarware.lua`. Customising the UI = editing that file
in this repo; downstream loaders see changes on the next SHA-pinned fetch.
