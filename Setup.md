# Mining Prototype Setup

## Folder structure

```text
ReplicatedStorage
  Mining
    BlockTemplates (Folder)
      <Part/Model templates>
    Config
      MiningConfig (ModuleScript)
    Shared
      MiningTypes (ModuleScript)
      MiningConstants (ModuleScript)
    Remotes
      RequestMineBlock (RemoteEvent, auto-created if missing)
    UI
      BlockHealthBillboard (ModuleScript)
      MineResetCountdownBillboard (ModuleScript)

ServerScriptService
  Mining
    Services
      MineGenerationService (ModuleScript)
      MineResetService (ModuleScript)
      MiningValidationService (ModuleScript)
      BlockStateService (ModuleScript)
    Bootstrap.server.lua

StarterPack
  Pickaxe (Tool)
    LocalMining.client.lua

Workspace
  MineVolume (Part)
  MineExitPoint (Part)
```

## Setup steps

1. Create `Workspace.MineVolume` as a single Part volume container for generated mine blocks.
2. Create `Workspace.MineExitPoint` as a safe teleport destination.
3. Create `ReplicatedStorage.Mining.BlockTemplates` and add valid `Part` or `Model` templates.
4. Add the scripts/modules in this repository to their matching Roblox locations.
5. Ensure players have the `Pickaxe` tool in `StarterPack`.
6. Run the game; `Bootstrap.server.lua` generates the mine, starts mining validation, starts the reset loop, and updates the countdown UI.

## Required attributes on generated blocks

Generated blocks are assigned automatically by server code:

- `IsMineBlock` = `true`
- `MaxDurability` = number
- `CurrentDurability` = number
- `MineCycleId` = number

Template override:

- Optional template attribute: `MaxDurability` (number > 0)
- If missing/invalid, falls back to `MiningConfig.DefaultDurability`

## What changed in this revision

Updated behavior:

1. Blocks now generate flush with no visible intentional gaps.
2. Block health bars are centered on blocks instead of above them.
3. Block health bars stay hidden at full durability and only show after damage.
4. Mine reset countdown UI is shown above `MineVolume` and updates live.

Files modified:

- `ReplicatedStorage/Mining/Config/MiningConfig.lua`
- `ReplicatedStorage/Mining/UI/BlockHealthBillboard.lua`
- `ReplicatedStorage/Mining/UI/MineResetCountdownBillboard.lua` (new)
- `ServerScriptService/Mining/Services/MineGenerationService.lua`
- `ServerScriptService/Mining/Services/MineResetService.lua`
- `Setup.md`

## No-gap block placement

- `BlockSize` remains locked to `Vector3.new(4, 3.308, 3.861)`.
- `GridSpacing` default is now `Vector3.new(0, 0, 0)` for flush placement.
- Grid math still uses floor-based best fit and a tiny epsilon only for floating-point safety when computing counts.
- Cell positions are computed directly from index * step using deterministic offsets (no accumulated drift), keeping blocks inside `MineVolume` bounds.

## Centered health bar behavior

- `BlockHealthBillboard` now uses `StudsOffset = Vector3.new(0, 0, 0)` so the UI renders in the block’s center region.
- `MaxDistance` remains `10` for normal mining readability.
- UI updates remain event-driven only when durability changes.

## Show health bar only when damaged

- New blocks start with hidden health bars.
- On each durability update, visibility is driven by ratio:
  - full health (`CurrentDurability == MaxDurability`) → hidden
  - damaged (`CurrentDurability < MaxDurability`) → visible
- Reset/regeneration creates fresh blocks at full health, so bars are hidden again by default.
- Block destruction/unregister still removes billboards cleanly.

## Mine reset countdown UI

- Added world-space countdown billboard above `MineVolume`.
- Countdown text format: `Mine resets in MM:SS`.
- `MaxDistance` is set to `500`.
- Fixed-size `BillboardGui` and fixed `TextSize` are used for stable readability.
- The service ensures only one countdown UI exists (reuses existing by name).
- Countdown updates continuously and carries across reset cycles.
- If `ReplicatedStorage/Mining/UI/MineResetCountdownBillboard` is missing, mining still runs and only countdown UI is disabled (warning logged).

## Config values to tune

In `MiningConfig.lua`:

- `GridSpacing`: default `Vector3.new(0, 0, 0)` (flush blocks)
- `ResetCountdown.StudsAboveMine`: vertical offset above `MineVolume`
- `ResetCountdown.UpdateIntervalSeconds`: countdown refresh rate
- `ResetCountdown.MaxDistance`: visibility distance (`500`)

## Reset behavior

Reset timer is controlled by `ResetIntervalSeconds`.

On each reset:

1. Reset lock enables (prevents double reset).
2. Players inside `MineVolume` bounds are detected with volume-space checks.
3. Valid alive characters are teleported to `MineExitPoint`.
4. Existing generated blocks are cleared/unregistered.
5. Mine is regenerated and a new cycle id is assigned.
6. Countdown immediately continues into the next cycle.

Mining requests are rejected while reset lock is active and stale cycle targets are rejected by validation.
